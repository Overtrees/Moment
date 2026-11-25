//! Web 持久层：IndexedDB（库 mynote-web，v2）。
//! - kv 店：manifest_raw、backup_meta（BackupFile 去 memos 的
//!   信封 JSON）、memos_order（篇目顺序的 id 数组 JSON）。
//!   旧形态 memos_json 全量键仅作存量拆条迁移的来源，迁移
//!   成功后删除（见 load_state）。
//! - memos 店：memo id → 单篇序列化 JSON（分条存储）。编辑
//!   保存只写变更条 + 删条，消除整库序列化/写回的写放大。
//! - attachments 店：id → 字节（Uint8Array）
//! 导入语义与原生端一致：包先经 core 完整校验，落库是横跨
//! kv+memos+attachments 三店的单事务全量替换，任一失败整
//! 体回滚（save_all）。

use mynote_core::BackupFile;
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;
use web_sys::{
    IdbDatabase, IdbObjectStore, IdbOpenDbRequest, IdbRequest, IdbTransaction,
    IdbTransactionMode,
};

const DB_NAME: &str = "mynote-web";
const DB_VERSION: u32 = 2;
const KV: &str = "kv";
const MEMOS: &str = "memos";
const ATT: &str = "attachments";
const KEY_MANIFEST: &str = "manifest_raw";
const KEY_META: &str = "backup_meta";
const KEY_ORDER: &str = "memos_order";
const KEY_LEGACY: &str = "memos_json";

fn request_promise(req: &IdbRequest) -> js_sys::Promise {
    let req = req.clone();
    js_sys::Promise::new(&mut |resolve, reject| {
        let r1 = req.clone();
        let onsuccess = Closure::once_into_js(move |_: JsValue| {
            let _ = resolve.call1(&JsValue::UNDEFINED, &r1.result().unwrap_or_default());
        });
        let r2 = req.clone();
        let onerror = Closure::once_into_js(move |_: JsValue| {
            let err = r2
                .error()
                .ok()
                .flatten()
                .map(JsValue::from)
                .unwrap_or_default();
            let _ = reject.call1(&JsValue::UNDEFINED, &err);
        });
        req.set_onsuccess(Some(onsuccess.unchecked_ref()));
        req.set_onerror(Some(onerror.unchecked_ref()));
    })
}

async fn await_req(req: &IdbRequest) -> Result<JsValue, JsValue> {
    JsFuture::from(request_promise(req)).await
}

/// 事务完成承诺：complete resolve、abort/error reject。多店
/// 单事务的落盘点以此为准（单个 request 成功不等于已提交）。
fn tx_promise(tx: &IdbTransaction) -> js_sys::Promise {
    let tx = tx.clone();
    js_sys::Promise::new(&mut |resolve, reject| {
        let oncomplete = Closure::once_into_js(move |_: JsValue| {
            let _ = resolve.call0(&JsValue::UNDEFINED);
        });
        tx.set_oncomplete(Some(oncomplete.unchecked_ref()));
        let r = reject.clone();
        let onabort = Closure::once_into_js(move |_: JsValue| {
            let _ = r.call1(&JsValue::UNDEFINED, &JsValue::from_str("tx aborted"));
        });
        tx.set_onabort(Some(onabort.unchecked_ref()));
        let onerror = Closure::once_into_js(move |_: JsValue| {
            let _ = reject.call1(&JsValue::UNDEFINED, &JsValue::from_str("tx error"));
        });
        tx.set_onerror(Some(onerror.unchecked_ref()));
    })
}

async fn await_tx(tx: &IdbTransaction) -> Result<(), JsValue> {
    JsFuture::from(tx_promise(tx)).await.map(|_| ())
}

async fn open_db() -> Result<IdbDatabase, JsValue> {
    let window = web_sys::window().ok_or_else(|| JsValue::from_str("no window"))?;
    let factory = window
        .indexed_db()?
        .ok_or_else(|| JsValue::from_str("no indexeddb"))?;
    let req: IdbOpenDbRequest = factory.open_with_u32(DB_NAME, DB_VERSION)?.unchecked_into();
    let onup = Closure::once_into_js(move |e: web_sys::Event| {
        let target = e.target().expect("upgrade event target");
        let open_req: IdbOpenDbRequest = target.unchecked_into();
        let db: IdbDatabase = open_req.result().expect("db on upgrade").unchecked_into();
        for name in [KV, MEMOS, ATT] {
            if !db.object_store_names().contains(name) {
                db.create_object_store(name).expect("create object store");
            }
        }
    });
    req.set_onupgradeneeded(Some(onup.unchecked_ref()));
    let result = await_req(req.as_ref()).await?;
    Ok(result.unchecked_into())
}

fn store(db: &IdbDatabase, name: &str, mode: IdbTransactionMode) -> Result<IdbObjectStore, JsValue> {
    Ok(db.transaction_with_str_and_mode(name, mode)?.object_store(name)?)
}

fn tx_stores(
    db: &IdbDatabase,
    names: &[&str],
    mode: IdbTransactionMode,
) -> Result<(IdbTransaction, Vec<IdbObjectStore>), JsValue> {
    let arr = js_sys::Array::new();
    for n in names {
        arr.push(&JsValue::from_str(n));
    }
    let tx = db.transaction_with_str_sequence_and_mode(&arr, mode)?;
    let stores = names
        .iter()
        .map(|n| tx.object_store(n))
        .collect::<Result<Vec<_>, _>>()?;
    Ok((tx, stores))
}

async fn kv_get(db: &IdbDatabase, key: &str) -> Result<Option<String>, JsValue> {
    let s = store(db, KV, IdbTransactionMode::Readonly)?;
    let v = await_req(&s.get(&JsValue::from_str(key))?).await?;
    Ok(if v.is_undefined() || v.is_null() {
        None
    } else {
        v.as_string()
    })
}

async fn kv_put(db: &IdbDatabase, key: &str, value: &str) -> Result<(), JsValue> {
    let s = store(db, KV, IdbTransactionMode::Readwrite)?;
    await_req(&s.put_with_key(&JsValue::from_str(value), &JsValue::from_str(key))?).await?;
    Ok(())
}

// ---------- BackupFile ⇄ 分条形态（纯函数，可单测） ----------

/// 分条形态：信封（BackupFile 去 memos 的根对象 JSON）+
/// 篇目顺序 + 逐篇 (id, 单篇 JSON)。
struct SplitBackup {
    meta: String,
    order: Vec<String>,
    entries: Vec<(String, String)>,
}

/// 篇目 id 的键形：字符串原样、数字取其十进制串（与模型 Id
/// 单形化后的字符串形一致）；其余形态不可作键 → None。
fn entry_key(memo: &serde_json::Value) -> Option<String> {
    match memo.get("id")? {
        serde_json::Value::String(s) => Some(s.clone()),
        serde_json::Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// 全量 JSON → 分条形态。任一篇无可用 id 即整体失败（调用
/// 方保留旧形态路径，不拆坏数据）。
fn split_backup_json(json: &str) -> Option<SplitBackup> {
    let mut root: serde_json::Value = serde_json::from_str(json).ok()?;
    let memos = root.get_mut("memos")?.take();
    let memos = memos.as_array()?;
    let mut order = Vec::with_capacity(memos.len());
    let mut entries = Vec::with_capacity(memos.len());
    for m in memos {
        let key = entry_key(m)?;
        order.push(key.clone());
        entries.push((key, serde_json::to_string(m).ok()?));
    }
    let meta = serde_json::to_string(&root).ok()?;
    Some(SplitBackup { meta, order, entries })
}

/// 分条条目的规范序列化：经 Value 中转再序列化，键序与
/// split_backup_json 的 Value 拆条恒同——同一篇无论经拆条
/// 迁移 / 全量写 / 增量写哪条路落盘，条目字节恒一致（合
/// 流全量 probe_twocol_flow_span F5 逐字节口径抓出：typed
/// 直序列化与 Value 拆条键序不同、跨写路字节漂移）。
fn memo_entry_raw(m: &mynote_core::Memo) -> Result<String, serde_json::Error> {
    serde_json::to_value(m).map(|v| v.to_string())
}

/// 分条形态 → 全量 JSON（加载组装）：信封对象插入 memos
/// 数组。单篇原文解析失败时以字符串元素嵌入，令上层严格
/// 解析照旧失败（与旧形态损坏时的失败面一致，不静默吞篇）。
fn assemble_backup_json(meta: &str, ordered_entries: &[String]) -> String {
    let mut root: serde_json::Value =
        serde_json::from_str(meta).unwrap_or_else(|_| serde_json::json!({}));
    if !root.is_object() {
        root = serde_json::json!({});
    }
    let arr: Vec<serde_json::Value> = ordered_entries
        .iter()
        .map(|raw| {
            serde_json::from_str(raw)
                .unwrap_or_else(|_| serde_json::Value::String(raw.clone()))
        })
        .collect();
    root.as_object_mut()
        .expect("root object")
        .insert("memos".to_string(), serde_json::Value::Array(arr));
    root.to_string()
}

/// 模型 → 信封 JSON + 篇目顺序。逐字段手工组装（不走整包
/// 序列化，保存热路径的序列化量只剩信封 + 变更篇）；字段
/// 名单在此穷举列明，BackupFile 新增字段时本函数编译报错
/// 提醒同步，不静默丢字段。
fn envelope_of(backup: &BackupFile) -> (String, Vec<String>) {
    let BackupFile {
        version,
        exported_at,
        memos,
        avatars,
    } = backup;
    let mut map = serde_json::Map::new();
    map.insert("version".to_string(), serde_json::json!(version));
    if let Some(e) = exported_at {
        if let Ok(v) = serde_json::to_value(e) {
            map.insert("exportedAt".to_string(), v);
        }
    }
    if let Some(a) = avatars {
        map.insert("avatars".to_string(), a.clone());
    }
    let order = memos.iter().map(|m| m.id.to_string()).collect();
    (serde_json::Value::Object(map).to_string(), order)
}

thread_local! {
    /// 本会话已确立的分条信封缓存 (meta, order_json)：与库
    /// 内现值逐字一致时跳过信封/顺序的重复写。冷缓存（未加
    /// 载/未写过）为 None，此时一律写。仅作写跳过优化，写
    /// 入本身幂等，缓存错位最多多写一次、不会少写。
    static ENVELOPE_CACHE: std::cell::RefCell<Option<(String, String)>> =
        const { std::cell::RefCell::new(None) };
}

fn envelope_cache_get() -> Option<(String, String)> {
    ENVELOPE_CACHE.with(|c| c.borrow().clone())
}

fn envelope_cache_set(meta: &str, order_json: &str) {
    ENVELOPE_CACHE.with(|c| {
        *c.borrow_mut() = Some((meta.to_string(), order_json.to_string()));
    });
}

/// 保存结果统计（结果侧打点与验收口径）。
pub struct SaveStats {
    pub upserts: usize,
    pub deletes: usize,
    pub bytes: usize,
    pub full: bool,
}

/// 分条全量写：清 memos 店 + 逐篇写 + 信封/顺序 + 删旧全
/// 量键，单事务（kv+memos）。
async fn write_full(db: &IdbDatabase, backup: &BackupFile) -> Result<SaveStats, JsValue> {
    let (meta, order) = envelope_of(backup);
    let order_json = serde_json::to_string(&order).unwrap_or_else(|_| "[]".to_string());
    let (tx, stores) = tx_stores(db, &[KV, MEMOS], IdbTransactionMode::Readwrite)?;
    let (kv, memos) = (&stores[0], &stores[1]);
    let mut reqs = Vec::new();
    reqs.push(memos.clear()?);
    let mut bytes = 0usize;
    for m in &backup.memos {
        let raw = memo_entry_raw(m).map_err(|e| JsValue::from_str(&e.to_string()))?;
        bytes += raw.len();
        reqs.push(memos.put_with_key(
            &JsValue::from_str(&raw),
            &JsValue::from_str(&m.id.to_string()),
        )?);
    }
    reqs.push(kv.put_with_key(&JsValue::from_str(&meta), &JsValue::from_str(KEY_META))?);
    reqs.push(kv.put_with_key(&JsValue::from_str(&order_json), &JsValue::from_str(KEY_ORDER))?);
    reqs.push(kv.delete(&JsValue::from_str(KEY_LEGACY))?);
    for r in &reqs {
        await_req(r).await?;
    }
    await_tx(&tx).await?;
    envelope_cache_set(&meta, &order_json);
    Ok(SaveStats {
        upserts: backup.memos.len(),
        deletes: 0,
        bytes,
        full: true,
    })
}

/// 分条增量写：只写变更篇/删篇 + 信封或顺序有变时写信封。
/// 分条形态尚未确立（库内无 backup_meta，如种子首存）时
/// 退化为全量写，保证首存完整。
async fn write_delta(
    db: &IdbDatabase,
    backup: &BackupFile,
    upsert: Option<&str>,
    delete: Option<&str>,
) -> Result<SaveStats, JsValue> {
    if envelope_cache_get().is_none() && kv_get(db, KEY_META).await?.is_none() {
        return write_full(db, backup).await;
    }
    let (meta, order) = envelope_of(backup);
    let order_json = serde_json::to_string(&order).unwrap_or_else(|_| "[]".to_string());
    let (tx, stores) = tx_stores(db, &[KV, MEMOS], IdbTransactionMode::Readwrite)?;
    let (kv, memos) = (&stores[0], &stores[1]);
    let mut reqs = Vec::new();
    let mut bytes = 0usize;
    if envelope_cache_get().as_ref() != Some(&(meta.clone(), order_json.clone())) {
        reqs.push(kv.put_with_key(&JsValue::from_str(&meta), &JsValue::from_str(KEY_META))?);
        reqs.push(kv.put_with_key(&JsValue::from_str(&order_json), &JsValue::from_str(KEY_ORDER))?);
        bytes += meta.len() + order_json.len();
    }
    let mut upserts = 0usize;
    if let Some(id) = upsert {
        if let Some(m) = backup.memos.iter().find(|m| m.id.to_string() == id) {
            let raw = memo_entry_raw(m).map_err(|e| JsValue::from_str(&e.to_string()))?;
            bytes += raw.len();
            reqs.push(memos.put_with_key(&JsValue::from_str(&raw), &JsValue::from_str(id))?);
            upserts = 1;
        }
    }
    let mut deletes = 0usize;
    if let Some(id) = delete {
        reqs.push(memos.delete(&JsValue::from_str(id))?);
        deletes = 1;
    }
    for r in &reqs {
        await_req(r).await?;
    }
    await_tx(&tx).await?;
    envelope_cache_set(&meta, &order_json);
    Ok(SaveStats {
        upserts,
        deletes,
        bytes,
        full: false,
    })
}

/// 编辑保存（增量）：upsert/delete 各至多一篇（编辑器与列
/// 表侧单篇变更的统一入口）。结果记 IDB 结果行。
pub async fn save_backup_delta(
    backup: &BackupFile,
    upsert: Option<&str>,
    delete: Option<&str>,
) -> Result<SaveStats, JsValue> {
    let db = open_db().await?;
    let st = write_delta(&db, backup, upsert, delete).await?;
    crate::diag::log(
        "IDB",
        &format!(
            "save ok up={} del={} bytes={} full={}",
            st.upserts, st.deletes, st.bytes, st.full
        ),
    );
    Ok(st)
}

/// 全量写回（加载期归一/恢复后的规范化落盘）：整库分条
/// 重写，单事务。
pub async fn save_backup_full(backup: &BackupFile) -> Result<SaveStats, JsValue> {
    let db = open_db().await?;
    let st = write_full(&db, backup).await?;
    crate::diag::log(
        "IDB",
        &format!("save_full ok memos={} bytes={}", st.upserts, st.bytes),
    );
    Ok(st)
}

/// 存量拆条迁移：旧全量键 → 分条形态。单事务内清店、逐
/// 篇写、写信封/顺序、计数核对篇数，核对通过才删旧键并
/// 提交；任一步失败整事务中止、旧键保留（下次加载重试，
/// 本次走旧形态返回）。绝不先删后写。
async fn split_migrate(db: &IdbDatabase, split: &SplitBackup) -> Result<(), JsValue> {
    let order_json = serde_json::to_string(&split.order).unwrap_or_else(|_| "[]".to_string());
    let (tx, stores) = tx_stores(db, &[KV, MEMOS], IdbTransactionMode::Readwrite)?;
    let (kv, memos) = (&stores[0], &stores[1]);
    let mut reqs = Vec::new();
    reqs.push(memos.clear()?);
    for (id, raw) in &split.entries {
        reqs.push(memos.put_with_key(&JsValue::from_str(raw), &JsValue::from_str(id))?);
    }
    reqs.push(kv.put_with_key(&JsValue::from_str(&split.meta), &JsValue::from_str(KEY_META))?);
    reqs.push(kv.put_with_key(&JsValue::from_str(&order_json), &JsValue::from_str(KEY_ORDER))?);
    for r in &reqs {
        await_req(r).await?;
    }
    let count = await_req(&memos.count()?).await?;
    if count.as_f64() != Some(split.entries.len() as f64) {
        let _ = tx.abort();
        return Err(JsValue::from_str("split-migrate count mismatch"));
    }
    await_req(&kv.delete(&JsValue::from_str(KEY_LEGACY))?).await?;
    await_tx(&tx).await?;
    envelope_cache_set(&split.meta, &order_json);
    Ok(())
}

/// 启动时读回持久状态：(memos_json, manifest_json)。分条
/// 形态在此组装回全量 JSON 串，上层加载语义不变（先
/// migrate 归一后严格解析）。检出旧全量键时先做一次性拆
/// 条迁移，失败保留旧键、本次仍按旧形态返回。
pub async fn load_state() -> Option<(String, String)> {
    let db = open_db().await.ok()?;
    let manifest = kv_get(&db, KEY_MANIFEST).await.ok()?.unwrap_or_default();
    if let Some(meta) = kv_get(&db, KEY_META).await.ok()? {
        // 分条形态：按顺序组装。
        let order: Vec<String> = kv_get(&db, KEY_ORDER)
            .await
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        let s = store(&db, MEMOS, IdbTransactionMode::Readonly).ok()?;
        let keys_v = await_req(&s.get_all_keys().ok()?).await.ok()?;
        let vals_v = await_req(&s.get_all().ok()?).await.ok()?;
        let keys = js_sys::Array::from(&keys_v);
        let vals = js_sys::Array::from(&vals_v);
        let mut by_id: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();
        for (k, v) in keys.iter().zip(vals.iter()) {
            if let (Some(id), Some(raw)) = (k.as_string(), v.as_string()) {
                by_id.insert(id, raw);
            }
        }
        let mut ordered: Vec<String> = Vec::with_capacity(by_id.len());
        for id in &order {
            if let Some(raw) = by_id.remove(id) {
                ordered.push(raw);
            }
        }
        // 顺序表外多出的条目（不应发生）按 id 序附后，不丢篇。
        let mut rest: Vec<(String, String)> = by_id.into_iter().collect();
        rest.sort_by(|a, b| a.0.cmp(&b.0));
        ordered.extend(rest.into_iter().map(|(_, raw)| raw));
        let order_json = serde_json::to_string(&order).unwrap_or_else(|_| "[]".to_string());
        envelope_cache_set(&meta, &order_json);
        return Some((assemble_backup_json(&meta, &ordered), manifest));
    }
    // 旧形态：全量键在则先尝试拆条迁移（一次性），无论成
    // 败本次都返回旧串（内容等价，归一/解析仍在上层）。
    let legacy = kv_get(&db, KEY_LEGACY).await.ok()??;
    match split_backup_json(&legacy) {
        Some(split) => {
            let n = split.entries.len();
            let bytes: usize = split.entries.iter().map(|(_, r)| r.len()).sum();
            match split_migrate(&db, &split).await {
                Ok(()) => crate::diag::log(
                    "IDB",
                    &format!("split-migrate ok memos={n} bytes={bytes}"),
                ),
                Err(e) => crate::diag::log(
                    "IDB",
                    &format!("split-migrate err: {e:?} (legacy kept)"),
                ),
            }
        }
        None => crate::diag::log("IDB", "split-migrate skipped (legacy unparseable)"),
    }
    Some((legacy, manifest))
}

/// 全量替换落库（导入成功后调用；包此前已经 core 校验）。
/// 横跨 kv+memos+attachments 的单事务：清附件/备忘店、
/// 写新条目/信封/顺序/manifest、删旧全量键，任一失败整
/// 体回滚，导入前状态完好。
pub async fn save_all(
    memos_json: &str,
    manifest_raw: &str,
    attachments: &[(String, Vec<u8>)],
) -> Result<(), JsValue> {
    let split = split_backup_json(memos_json)
        .ok_or_else(|| JsValue::from_str("save_all: memos_json unsplittable"))?;
    let order_json = serde_json::to_string(&split.order).unwrap_or_else(|_| "[]".to_string());
    let db = open_db().await?;
    let (tx, stores) = tx_stores(&db, &[KV, MEMOS, ATT], IdbTransactionMode::Readwrite)?;
    let (kv, memos, att) = (&stores[0], &stores[1], &stores[2]);
    let mut reqs = Vec::new();
    reqs.push(memos.clear()?);
    for (id, raw) in &split.entries {
        reqs.push(memos.put_with_key(&JsValue::from_str(raw), &JsValue::from_str(id))?);
    }
    reqs.push(kv.put_with_key(&JsValue::from_str(&split.meta), &JsValue::from_str(KEY_META))?);
    reqs.push(kv.put_with_key(&JsValue::from_str(&order_json), &JsValue::from_str(KEY_ORDER))?);
    reqs.push(kv.put_with_key(&JsValue::from_str(manifest_raw), &JsValue::from_str(KEY_MANIFEST))?);
    reqs.push(kv.delete(&JsValue::from_str(KEY_LEGACY))?);
    reqs.push(att.clear()?);
    for (id, bytes) in attachments {
        let arr = js_sys::Uint8Array::from(bytes.as_slice());
        reqs.push(att.put_with_key(&arr, &JsValue::from_str(id))?);
    }
    for r in &reqs {
        await_req(r).await?;
    }
    await_tx(&tx).await?;
    envelope_cache_set(&split.meta, &order_json);
    crate::diag::log(
        "IDB",
        &format!(
            "save_all ok memos={} memos_json={}B atts={}",
            split.entries.len(),
            memos_json.len(),
            attachments.len()
        ),
    );
    Ok(())
}

/// 隔离区 kv 键：存量加载隔离出的结构坏篇原文（JSON 数组
/// 文档，合并口径见 core::migrate::merge_quarantine）。
/// 沿 kv 店整值读写惯例（与 manifest_raw 同店同式）、不新建
/// 店。合流落点（idb 分条 + 逐篇隔离双线叠合）：本键是普通
/// kv 键，与分条结构（memos 店 + backup_meta/memos_order）
/// 并存，分条迁移不触本键。
pub const QUARANTINE_KEY: &str = "quarantine_json";

/// 读回隔离区文档原文（无隔离记录时 None）。
pub async fn load_quarantine() -> Option<String> {
    let db = open_db().await.ok()?;
    kv_get(&db, QUARANTINE_KEY).await.ok()?
}

/// 写入隔离区文档（合并后的完整文档，调用方合并）。
pub async fn save_quarantine(raw: &str) -> Result<(), JsValue> {
    let db = open_db().await?;
    kv_put(&db, QUARANTINE_KEY, raw).await
}

pub async fn get_attachment(id: &str) -> Option<Vec<u8>> {
    let db = open_db().await.ok()?;
    let s = store(&db, ATT, IdbTransactionMode::Readonly).ok()?;
    let v = await_req(&s.get(&JsValue::from_str(id)).ok()?).await.ok()?;
    if v.is_undefined() || v.is_null() {
        return None;
    }
    let arr: js_sys::Uint8Array = v.unchecked_into();
    Some(arr.to_vec())
}

pub async fn get_all_attachments() -> Vec<(String, Vec<u8>)> {
    let mut out = Vec::new();
    let Ok(db) = open_db().await else { return out };
    let Ok(s) = store(&db, ATT, IdbTransactionMode::Readonly) else {
        return out;
    };
    let Ok(keys_v) = await_req(&s.get_all_keys().unwrap()).await else {
        return out;
    };
    let keys = js_sys::Array::from(&keys_v);
    for k in keys.iter() {
        if let Some(id) = k.as_string() {
            if let Ok(v) = await_req(&s.get(&k).unwrap()).await {
                if !v.is_undefined() && !v.is_null() {
                    let arr: js_sys::Uint8Array = v.unchecked_into();
                    out.push((id, arr.to_vec()));
                }
            }
        }
    }
    out
}

/// 附件字节 → Blob 对象 URL（图片/音视频渲染与下载共用）。
pub fn blob_url(bytes: &[u8]) -> Option<String> {
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let blob = web_sys::Blob::new_with_u8_array_sequence(&parts).ok()?;
    web_sys::Url::create_object_url_with_blob(&blob).ok()
}

/// 附件字节 → 带 MIME 类型的 Blob 对象 URL（D-21 列表封面用：
/// 类型取自 manifest 登记，SVG 等格式在 <img> 中需要正确
/// MIME 才能解码，无类型 Blob 靠浏览器嗅探对它们不可靠）。
pub fn blob_url_typed(bytes: &[u8], mime: &str) -> Option<String> {
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::BlobPropertyBag::new();
    opts.set_type(mime);
    let blob = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &opts).ok()?;
    web_sys::Url::create_object_url_with_blob(&blob).ok()
}

/// 写入单个附件（编辑器添加附件用，不动其他数据）。
pub async fn put_attachment(id: &str, bytes: &[u8]) -> Result<(), JsValue> {
    let db = open_db().await?;
    let s = store(&db, ATT, IdbTransactionMode::Readwrite)?;
    let arr = js_sys::Uint8Array::from(bytes);
    await_req(&s.put_with_key(&arr, &JsValue::from_str(id))?).await?;
    crate::diag::log("IDB", &format!("put_attachment {id} {}B", bytes.len()));
    Ok(())
}

/// 只更新 manifest（添加附件后同步附件索引）。
pub async fn save_manifest(manifest_raw: &str) -> Result<(), JsValue> {
    let db = open_db().await?;
    kv_put(&db, "manifest_raw", manifest_raw).await
}

#[cfg(test)]
mod tests {
    use super::{assemble_backup_json, split_backup_json};

    #[test]
    fn split_assemble_roundtrip() {
        let json = r#"{"version":2,"exportedAt":"2026-01-01T00:00:00.000Z","memos":[{"id":"a","title":"t1"},{"id":"b","doc":[]}],"avatars":{"a":"data:x"}}"#;
        let split = split_backup_json(json).expect("split");
        assert_eq!(split.order, vec!["a".to_string(), "b".to_string()]);
        assert_eq!(split.entries.len(), 2);
        let raws: Vec<String> = split.entries.iter().map(|(_, r)| r.clone()).collect();
        let back = assemble_backup_json(&split.meta, &raws);
        let a: serde_json::Value = serde_json::from_str(json).unwrap();
        let b: serde_json::Value = serde_json::from_str(&back).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn split_numeric_id_keyed_by_decimal() {
        let json = r#"{"version":2,"memos":[{"id":1795494731533,"title":"old"}]}"#;
        let split = split_backup_json(json).expect("split");
        assert_eq!(split.order, vec!["1795494731533".to_string()]);
    }

    #[test]
    fn split_rejects_missing_id() {
        let json = r#"{"version":2,"memos":[{"title":"no id"}]}"#;
        assert!(split_backup_json(json).is_none());
    }

    #[test]
    fn assemble_embeds_corrupt_entry_as_string() {
        let out = assemble_backup_json(r#"{"version":2}"#, &["{broken".to_string()]);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["memos"][0], serde_json::Value::String("{broken".to_string()));
    }
}
