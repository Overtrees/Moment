//! Web 持久层门面（SQLite 接入阶段二）：消费面与 idb.rs
//! 逐项对齐，两种后端——
//! - 默认（无 `sqlite-backend` feature）：直通 idb.rs，
//!   行为与阶段二之前逐字一致；
//! - `sqlite-backend`：备忘与清单走存储 Worker
//!   （Dedicated Worker + SAHPool SQLite，见
//!   apps/storage-worker），附件字节维持 IDB attachments
//!   店（文件式口径：不入 SQLite BLOB，引用为单向 id、
//!   缺附件有既有降级面）。启动加载时若 IDB 有存量且
//!   SQLite 无迁移戳，先在门面内完成一次性迁移（IDB
//!   原库保留不删，阶段三观察期后另行处置）。
//!
//! 桥口径表（idb.rs 消费面 → sqlite 模式落点）：
//!   load_state        → Worker load_all（迁移检查后）
//!   save_memos        → Worker save_sync（逐篇差量）
//!   save_all          → Worker import_library + IDB 附件全量替换
//!   save_manifest     → Worker save_manifest（meta）
//!   put_attachment    → IDB attachments（两模式同）
//!   get_attachment    → IDB attachments（两模式同）
//!   get_all_attachments → IDB attachments（两模式同）
//!   blob_url*         → idb.rs 纯函数（不经门面）

use wasm_bindgen::prelude::*;

#[cfg(feature = "sqlite-backend")]
use std::cell::RefCell;
#[cfg(feature = "sqlite-backend")]
use std::collections::HashMap;
#[cfg(feature = "sqlite-backend")]
use std::rc::Rc;
#[cfg(feature = "sqlite-backend")]
use std::sync::atomic::{AtomicBool, Ordering};

/// 存储是否正被另一标签独占（App 轮询此标记出提示态；
/// IDB 模式恒 false）。
#[cfg(feature = "sqlite-backend")]
static OCCUPIED: AtomicBool = AtomicBool::new(false);
/// 提示态「立即重试」按钮的催促标记（独占等待循环据此
/// 提前重试，不必等满轮询间隔）。
#[cfg(feature = "sqlite-backend")]
static NUDGE: AtomicBool = AtomicBool::new(false);

pub fn is_occupied() -> bool {
    #[cfg(feature = "sqlite-backend")]
    {
        OCCUPIED.load(Ordering::Relaxed)
    }
    #[cfg(not(feature = "sqlite-backend"))]
    {
        false
    }
}

pub fn nudge_retry() {
    #[cfg(feature = "sqlite-backend")]
    {
        NUDGE.store(true, Ordering::Relaxed);
    }
}

pub async fn load_state() -> Option<(String, String)> {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        crate::idb::load_state().await
    }
    #[cfg(feature = "sqlite-backend")]
    {
        sqlite::load_state().await
    }
}

pub async fn save_memos(memos_json: &str) -> Result<(), JsValue> {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        idb_save_full_str(memos_json).await
    }
    #[cfg(feature = "sqlite-backend")]
    {
        sqlite::save_memos(memos_json).await
    }
}

pub async fn save_all(
    memos_json: &str,
    manifest_raw: &str,
    attachments: &[(String, Vec<u8>)],
) -> Result<(), JsValue> {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        crate::idb::save_all(memos_json, manifest_raw, attachments).await
    }
    #[cfg(feature = "sqlite-backend")]
    {
        sqlite::save_all(memos_json, manifest_raw, attachments).await
    }
}

pub async fn save_manifest(manifest_raw: &str) -> Result<(), JsValue> {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        crate::idb::save_manifest(manifest_raw).await
    }
    #[cfg(feature = "sqlite-backend")]
    {
        sqlite::save_manifest(manifest_raw).await
    }
}

pub async fn put_attachment(id: &str, bytes: &[u8]) -> Result<(), JsValue> {
    crate::idb::put_attachment(id, bytes).await
}

pub async fn get_attachment(id: &str) -> Option<Vec<u8>> {
    crate::idb::get_attachment(id).await
}

pub async fn get_all_attachments() -> Vec<(String, Vec<u8>)> {
    crate::idb::get_all_attachments().await
}

/// 整串形态的全量写回（加载期收敛/迁移镜像用）：解析后走
/// idb 分条全量写。解析失败即报错，不静默吞。
pub async fn idb_save_full_str(memos_json: &str) -> Result<(), JsValue> {
    let backup: mynote_core::BackupFile = serde_json::from_str(memos_json)
        .map_err(|e| JsValue::from_str(&format!("save_full parse: {e}")))?;
    crate::idb::save_backup_full(&backup).await?;
    Ok(())
}

/// 编辑保存（分条增量口径）：消费面与 idb::save_backup_delta
/// 对齐。sqlite 模式本步先走 Worker save_sync（阶段二口径），
/// 双写差量镜像在阶段三观察期形态笔落地。
pub async fn save_backup_delta(
    backup: &mynote_core::BackupFile,
    upsert: Option<&str>,
    delete: Option<&str>,
) -> Result<(), JsValue> {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        crate::idb::save_backup_delta(backup, upsert, delete).await
    }
    #[cfg(feature = "sqlite-backend")]
    {
        let json = serde_json::to_string(backup)
            .map_err(|e| JsValue::from_str(&format!("save_delta serialize: {e}")))?;
        sqlite::save_memos(&json).await
    }
}

/// 全量写回（加载期归一收敛）：与 idb::save_backup_full 对齐。
pub async fn save_backup_full(backup: &mynote_core::BackupFile) -> Result<(), JsValue> {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        crate::idb::save_backup_full(backup).await?;
        Ok(())
    }
    #[cfg(feature = "sqlite-backend")]
    {
        let json = serde_json::to_string(backup)
            .map_err(|e| JsValue::from_str(&format!("save_full serialize: {e}")))?;
        sqlite::save_memos(&json).await
    }
}

#[cfg(feature = "sqlite-backend")]
mod sqlite {
    use super::*;

    struct Bridge {
        worker: web_sys::Worker,
        pending: Rc<RefCell<HashMap<u32, (js_sys::Function, js_sys::Function)>>>,
        next_id: std::cell::Cell<u32>,
    }

    thread_local! {
        static BRIDGE: RefCell<Option<Rc<Bridge>>> =
            const { RefCell::new(None) };
    }

    async fn sleep_ms(ms: i32) {
        let promise = js_sys::Promise::new(&mut |resolve, _| {
            let window = web_sys::window().expect("window");
            let _ = window.set_timeout_with_callback_and_timeout_and_arguments_0(&resolve, ms);
        });
        let _ = wasm_bindgen_futures::JsFuture::from(promise).await;
    }

    fn bridge() -> Result<Rc<Bridge>, String> {
        let existing = BRIDGE.with(|b| b.borrow().clone());
        if let Some(b) = existing {
            return Ok(b);
        }
        let opts = web_sys::WorkerOptions::new();
        opts.set_type(web_sys::WorkerType::Module);
        let worker = web_sys::Worker::new_with_options("./storage-worker/worker.js", &opts)
            .map_err(|e| format!("spawn worker: {e:?}"))?;
        let bridge = Rc::new(Bridge {
            worker,
            pending: Rc::new(RefCell::new(HashMap::new())),
            next_id: std::cell::Cell::new(0),
        });
        let pending = bridge.pending.clone();
        let onmessage = Closure::<dyn FnMut(web_sys::MessageEvent)>::new(
            move |e: web_sys::MessageEvent| {
                let data = e.data();
                let id = js_sys::Reflect::get(&data, &JsValue::from_str("id"))
                    .ok()
                    .and_then(|v| v.as_f64())
                    .map(|v| v as u32);
                let Some(id) = id else { return };
                let slot = pending.borrow_mut().remove(&id);
                let Some((resolve, reject)) = slot else { return };
                let ok = js_sys::Reflect::get(&data, &JsValue::from_str("ok"))
                    .ok()
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if ok {
                    let result = js_sys::Reflect::get(&data, &JsValue::from_str("result"))
                        .unwrap_or(JsValue::NULL);
                    let _ = resolve.call1(&JsValue::UNDEFINED, &result);
                } else {
                    let err = js_sys::Reflect::get(&data, &JsValue::from_str("error"))
                        .unwrap_or(JsValue::from_str("worker error"));
                    let _ = reject.call1(&JsValue::UNDEFINED, &err);
                }
            },
        );
        bridge
            .worker
            .set_onmessage(Some(onmessage.as_ref().unchecked_ref()));
        onmessage.forget();
        BRIDGE.with(|b| *b.borrow_mut() = Some(bridge.clone()));
        Ok(bridge)
    }

    async fn rpc(cmd: &str, payload: JsValue) -> Result<serde_json::Value, String> {
        let bridge = bridge()?;
        let id = bridge.next_id.get() + 1;
        bridge.next_id.set(id);
        let msg = js_sys::Object::new();
        let _ = js_sys::Reflect::set(&msg, &JsValue::from_str("id"), &JsValue::from_f64(id as f64));
        let _ = js_sys::Reflect::set(&msg, &JsValue::from_str("cmd"), &JsValue::from_str(cmd));
        let _ = js_sys::Reflect::set(&msg, &JsValue::from_str("payload"), &payload);
        let pending = bridge.pending.clone();
        let promise = js_sys::Promise::new(&mut |resolve, reject| {
            pending.borrow_mut().insert(id, (resolve, reject));
        });
        bridge
            .worker
            .post_message(&JsValue::from(msg))
            .map_err(|e| format!("post {cmd}: {e:?}"))?;
        match wasm_bindgen_futures::JsFuture::from(promise).await {
            Ok(v) => Ok(serde_wasm_json(v)),
            Err(e) => Err(e.as_string().unwrap_or_else(|| format!("{e:?}"))),
        }
    }

    /// Worker 回的结果是 JS 对象（worker.js 已把 rpc 的
    /// JSON 字符串解析回对象），经 JSON 往返转 serde 值。
    fn serde_wasm_json(v: JsValue) -> serde_json::Value {
        let s = js_sys::JSON::stringify(&v)
            .ok()
            .and_then(|s| s.as_string())
            .unwrap_or_else(|| "null".to_string());
        serde_json::from_str(&s).unwrap_or(serde_json::Value::Null)
    }

    fn obj_payload(pairs: &[(&str, JsValue)]) -> JsValue {
        let obj = js_sys::Object::new();
        for (k, v) in pairs {
            let _ = js_sys::Reflect::set(&obj, &JsValue::from_str(k), v);
        }
        obj.into()
    }

    enum InitOutcome {
        Ready,
        Occupied,
        Failed(String),
    }

    async fn bridge_init() -> InitOutcome {
        match rpc("init", JsValue::UNDEFINED).await {
            Ok(v) => match v.get("status").and_then(|s| s.as_str()) {
                Some("ready") => InitOutcome::Ready,
                Some("occupied") => InitOutcome::Occupied,
                _ => InitOutcome::Failed(format!("unexpected init reply: {v}")),
            },
            Err(e) => InitOutcome::Failed(e),
        }
    }

    /// 独占等待：被另一标签持有时置 OCCUPIED（App 出提
    /// 示态），每 250ms 查催促标记、满 2s 重试 init；接
    /// 管成功记结果行后返回 true。硬失败返回 false（调
    /// 用方回退 IDB 直读，保应用可用）。
    async fn wait_ready() -> bool {
        let mut announced = false;
        let mut retries = 0u32;
        loop {
            match bridge_init().await {
                InitOutcome::Ready => {
                    if announced {
                        crate::diag::log(
                            "SQLITE",
                            &format!("takeover ok after {retries} retries"),
                        );
                    }
                    OCCUPIED.store(false, Ordering::Relaxed);
                    return true;
                }
                InitOutcome::Occupied => {
                    if !announced {
                        announced = true;
                        OCCUPIED.store(true, Ordering::Relaxed);
                        crate::diag::log_warn(
                            "SQLITE",
                            "storage occupied by another tab; waiting for takeover",
                        );
                    }
                    // 250ms × 8 拍 ≈ 2s 一轮；催促标记提前唤醒。
                    for _ in 0..8 {
                        if NUDGE.swap(false, Ordering::Relaxed) {
                            break;
                        }
                        sleep_ms(250).await;
                    }
                    retries += 1;
                }
                InitOutcome::Failed(e) => {
                    crate::diag::log("SQLITE", &format!("worker init failed: {e}"));
                    OCCUPIED.store(false, Ordering::Relaxed);
                    return false;
                }
            }
        }
    }

    pub async fn load_state() -> Option<(String, String)> {
        if !wait_ready().await {
            // Worker 硬失败：回退 IDB 直读（未迁移用户数
            // 据无损；已迁移用户读到的是冻结副本，Diag 已
            // 记 init failed，阶段三切生产前须另定硬姿态）。
            return crate::idb::load_state().await;
        }
        let status = rpc("migration_status", JsValue::UNDEFINED)
            .await
            .unwrap_or(serde_json::Value::Null);
        let migrated = status.get("done").and_then(|v| v.as_bool()).unwrap_or(false);
        let idb_state = crate::idb::load_state().await;
        let mut migrated_now = false;
        if !migrated {
            if let Some((memos_json, manifest_raw)) = &idb_state {
                let payload = obj_payload(&[
                    ("memos_json", JsValue::from_str(memos_json)),
                    ("manifest_raw", JsValue::from_str(manifest_raw)),
                ]);
                match rpc("migrate", payload).await {
                    Ok(rep) => {
                        migrated_now = true;
                        let atts_idb = crate::idb::attachment_ids().await.len();
                        crate::diag::log(
                            "SQLITE",
                            &format!(
                                "migrate ok memos={} hash={} atts_idb={} {:.0}ms",
                                rep.get("memos").and_then(|v| v.as_u64()).unwrap_or(0),
                                rep.get("hash").and_then(|v| v.as_str()).unwrap_or("?"),
                                atts_idb,
                                rep.get("ms").and_then(|v| v.as_f64()).unwrap_or(0.0),
                            ),
                        );
                        // 归一摘要与主线程加载期归一同行口径
                        // （同一通道、同一 boot 的归一事件；
                        // probe_load_stock 的 MIGRATE 断言据此
                        // 在两后端同口径成立）。
                        if rep.get("mig_changes").and_then(|v| v.as_u64()).unwrap_or(0) > 0 {
                            if let Some(s) = rep.get("mig_summary").and_then(|v| v.as_str()) {
                                crate::diag::log("APP", &format!("MIGRATE d3 {s}"));
                            }
                            if let Some(s) = rep.get("mig_census").and_then(|v| v.as_str()) {
                                crate::diag::log("APP", &format!("MIGRATE census {s}"));
                            }
                        }
                    }
                    Err(e) => {
                        crate::diag::log("SQLITE", &format!("migrate failed: {e}"));
                        return idb_state;
                    }
                }
            }
        }
        match rpc("load_all", JsValue::UNDEFINED).await {
            Ok(v) => {
                let memos_json = v
                    .get("memos_json")
                    .and_then(|s| s.as_str())
                    .unwrap_or_default()
                    .to_string();
                let manifest_raw = v
                    .get("manifest_raw")
                    .and_then(|s| s.as_str())
                    .unwrap_or_default()
                    .to_string();
                let has_library =
                    v.get("has_library").and_then(|b| b.as_bool()).unwrap_or(false);
                let n = v.get("memos").and_then(|x| x.as_u64()).unwrap_or(0);
                if !has_library && n == 0 && idb_state.is_none() {
                    // 两后端皆空：与 IDB 模式同口径返回
                    // None，应用走种子样本。
                    return None;
                }
                if migrated_now {
                    // 迁移后收敛镜像：归一后形态写回 IDB
                    // kv（与 IDB 模式加载期收敛写回同口径），
                    // IDB 副本由此保持为有效回退面；迁移失
                    // 败路径走不到这里、IDB 原样不动。后续
                    // 常规保存仍只写 SQLite——双写对账是阶
                    // 段三的范围。
                    let _ = super::idb_save_full_str(&memos_json).await;
                    crate::diag::log("SQLITE", "idb mirror converged after migrate");
                }
                crate::diag::log("SQLITE", &format!("load source=sqlite memos={n}"));
                Some((memos_json, manifest_raw))
            }
            Err(e) => {
                crate::diag::log("SQLITE", &format!("load_all failed: {e}"));
                idb_state
            }
        }
    }

    pub async fn save_memos(memos_json: &str) -> Result<(), JsValue> {
        let payload = obj_payload(&[("memos_json", JsValue::from_str(memos_json))]);
        match rpc("save_sync", payload).await {
            Ok(rep) => {
                crate::diag::log(
                    "SQLITE",
                    &format!(
                        "save_sync upserted={} deleted={} unchanged={} {:.0}ms",
                        rep.get("upserted").and_then(|v| v.as_u64()).unwrap_or(0),
                        rep.get("deleted").and_then(|v| v.as_u64()).unwrap_or(0),
                        rep.get("unchanged").and_then(|v| v.as_u64()).unwrap_or(0),
                        rep.get("ms").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    ),
                );
                Ok(())
            }
            Err(e) => Err(JsValue::from_str(&e)),
        }
    }

    pub async fn save_all(
        memos_json: &str,
        manifest_raw: &str,
        attachments: &[(String, Vec<u8>)],
    ) -> Result<(), JsValue> {
        let payload = obj_payload(&[
            ("memos_json", JsValue::from_str(memos_json)),
            ("manifest_raw", JsValue::from_str(manifest_raw)),
        ]);
        rpc("import_library", payload)
            .await
            .map_err(|e| JsValue::from_str(&e))?;
        // 附件落 IDB 店 + 全量 IDB 镜像：导入是低频用户动
        // 作，顺手把 IDB 副本刷新到与 SQLite 一致（回退面
        // 不旧于最近一次导入/迁移，与迁移后收敛镜像同口
        // 径）；常规编辑保存仍只写 SQLite（双写对账是阶
        // 段三范围）。
        crate::idb::save_all(memos_json, manifest_raw, attachments).await?;
        crate::diag::log(
            "SQLITE",
            &format!(
                "import_library ok memos_json={}B atts={} (idb mirrored)",
                memos_json.len(),
                attachments.len()
            ),
        );
        Ok(())
    }

    pub async fn save_manifest(manifest_raw: &str) -> Result<(), JsValue> {
        let payload = obj_payload(&[("manifest_raw", JsValue::from_str(manifest_raw))]);
        rpc("save_manifest", payload)
            .await
            .map(|_| ())
            .map_err(|e| JsValue::from_str(&e))
    }
}
