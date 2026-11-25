//! Web 持久层门面（SQLite 接入阶段三：双写对账观察期）。
//! 消费面与 idb.rs 的分条口径逐项对齐，三种后端形态由运
//! 行时开关 `mynote_backend_v1`（localStorage）+ URL 参数
//! `?backend=` 决定（救援面板可改、改完重启即生效、回滚
//! 不需重新部署）；构建层由 `sqlite-backend` feature 决定
//! 是否带 Worker 后端（无 feature 时恒 IDB、行为与阶段三
//! 之前逐字一致）。
//!
//! 形态语义（设计稿 PHASE3_DESIGN.md）：
//! - Idb：纯 IDB 分条（主线现行口径）。
//! - Dual（观察期默认）：SQLite 主写 + IDB 差量镜像；冷
//!   启逐篇哈希对账、SQLite 为准单向收敛镜像；Worker 硬
//!   失败 → 自动降级 IDB 镜像只读 + 横幅告知（不走可写
//!   直读回退，防静默分叉）。
//! - Sqlite：纯 SQLite（正式切换后的形态，本轮仅作开关
//!   位存在）；硬失败 → 阻断提示（镜像已停写、只读呈现
//!   会误导），救援层可切回兼容模式。
//!
//! 桥口径表（消费面 → dual 落点）：
//!   load_state        → Worker load_all（迁移编排后）
//!   save_backup_delta → Worker save_sync + IDB 分条增量镜像
//!   save_backup_full  → Worker save_sync + IDB 分条全量镜像
//!   save_all          → Worker import_library + IDB save_all 全量镜像（两段提交）
//!   save_manifest     → Worker save_manifest + IDB kv 镜像同写
//!   put/get/get_all_attachments → IDB attachments（文件式，两形态同）
//!   blob_url*         → idb.rs 纯函数（不经门面）
//!
//! 迁移编排（dual/sqlite 首启、IDB 有存量而 SQLite 无库
//! 时）：迁移源 = idb 组装读（分条/旧全量两形态都经
//! idb::load_state 收敛）；入 Worker 前先在主线程过
//! core::migrate 存量归一（逐篇隔离通道与加载路径同一
//! 套），隔离原文先落 idb 隔离区成功才迁（顺序红线同主
//! 加载路径）；迁移后以 load_all 结果走 IDB 分条全量写
//! 回作收敛镜像。quarantine_json 是 IDB 侧独立 kv 键，不
//! 进 SQLite、任何写回都不触碰。

use wasm_bindgen::prelude::*;

#[cfg(feature = "sqlite-backend")]
use std::cell::RefCell;
#[cfg(feature = "sqlite-backend")]
use std::collections::HashMap;
#[cfg(feature = "sqlite-backend")]
use std::rc::Rc;
#[cfg(feature = "sqlite-backend")]
use std::sync::atomic::{AtomicBool, Ordering};

/// 后端形态（运行时开关解析结果）。Dual/Sqlite 仅在
/// sqlite-backend 构建里可达（默认构建恒 Idb）。
#[cfg_attr(not(feature = "sqlite-backend"), allow(dead_code))]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Backend {
    Idb,
    Dual,
    Sqlite,
}

#[cfg(feature = "sqlite-backend")]
thread_local! {
    /// 本会话解析出的后端形态与来源（url/stored/default/
    /// build）：启动时解析一次，运行中不变（切换靠重启）。
    static MODE: RefCell<Option<(Backend, &'static str)>> = const { RefCell::new(None) };
}

#[cfg(feature = "sqlite-backend")]
fn resolve_backend() -> (Backend, &'static str) {
    // URL 参数优先（救援/回滚的一次性入口，设计稿 §4）。
    if let Some(w) = web_sys::window() {
        if let Ok(search) = w.location().search() {
            for pair in search.trim_start_matches('?').split('&') {
                if let Some(v) = pair.strip_prefix("backend=") {
                    if let Some(b) = parse_backend_value(v) {
                        return (b, "url");
                    }
                }
            }
        }
        if let Ok(Some(storage)) = w.local_storage() {
            if let Ok(Some(v)) = storage.get_item("mynote_backend_v1") {
                match parse_backend_value(&v) {
                    Some(b) => return (b, "stored"),
                    // "auto"/未识别值 → 构建默认。
                    None => return (Backend::Dual, "stored-auto"),
                }
            }
        }
    }
    (Backend::Dual, "default")
}

/// 当前后端形态。无 sqlite-backend feature 的构建恒 Idb。
pub fn backend() -> Backend {
    #[cfg(not(feature = "sqlite-backend"))]
    {
        Backend::Idb
    }
    #[cfg(feature = "sqlite-backend")]
    {
        MODE.with(|m| {
            let mut slot = m.borrow_mut();
            if let Some((b, _)) = *slot {
                return b;
            }
            let resolved = resolve_backend();
            *slot = Some(resolved);
            resolved.0
        })
    }
}

#[cfg(feature = "sqlite-backend")]
fn backend_source() -> &'static str {
    backend();
    MODE.with(|m| m.borrow().map(|(_, s)| s).unwrap_or("default"))
}

/// 启动时记一行后端形态（Diag 观察期判读面）；IDB 构建
/// 不记（行为与阶段三之前一致）。
fn log_backend_mode_once() {
    #[cfg(feature = "sqlite-backend")]
    {
        static LOGGED: AtomicBool = AtomicBool::new(false);
        if !LOGGED.swap(true, Ordering::Relaxed) {
            crate::diag::log(
                "SQLITE",
                &format!(
                    "backend mode={} source={}",
                    match backend() {
                        Backend::Idb => "idb",
                        Backend::Dual => "dual",
                        Backend::Sqlite => "sqlite",
                    },
                    backend_source(),
                ),
            );
        }
    }
}

/// 存储是否正被另一标签独占（呈现经 set_state_listener
/// 回调推送；本读取面供 notify 组装三值，IDB 形态恒
/// false）。
#[cfg(feature = "sqlite-backend")]
static OCCUPIED: AtomicBool = AtomicBool::new(false);
/// 提示态「立即重试」按钮的催促标记（独占等待循环据此
/// 提前重试，不必等满轮询间隔）。
#[cfg(feature = "sqlite-backend")]
static NUDGE: AtomicBool = AtomicBool::new(false);
/// dual 硬失败降级只读标记（本会话）：数据面为 IDB 镜
/// 像，写路径一律拒绝，防与 SQLite 恢复后分叉。
#[cfg(feature = "sqlite-backend")]
static READONLY: AtomicBool = AtomicBool::new(false);
/// sqlite 形态硬失败阻断标记（本会话）：呈现阻断提示，
/// 写路径同样拒绝。
#[cfg(feature = "sqlite-backend")]
static UNAVAILABLE: AtomicBool = AtomicBool::new(false);
/// 镜像写失败待对账修复标记（Diag 已记行，本标记供对账
/// 触发判断与后续观测）。
#[cfg(feature = "sqlite-backend")]
static MIRROR_DIRTY: AtomicBool = AtomicBool::new(false);
/// 本会话发生过迁移/导入（刚做完全量对齐，冷启对账跳过）。
#[cfg(feature = "sqlite-backend")]
static SESSION_ALIGNED: AtomicBool = AtomicBool::new(false);

// 存储状态呈现回调（App 启动时注册一次）：三标记任一
// 变化经 notify_state 以最新三值（独占 / 只读降级 /
// 阻断）同步调用，把状态推给呈现信号——取代旧 500ms
// 轮询同步（标记清除到呈现消失曾有至多 500ms 滞后）。
// 回调只写呈现信号，不得回调 persist 写路径：notify
// 在置位点内同步触发，WASM 单线程下重入写路径会与独
// 占等待循环纠缠。
#[cfg(feature = "sqlite-backend")]
thread_local! {
    static STATE_LISTENER: RefCell<Option<Box<dyn FnMut(bool, bool, bool)>>> =
        const { RefCell::new(None) };
}

/// 注册存储状态呈现回调（见 STATE_LISTENER 注）。无
/// sqlite-backend 的构建三标记恒定、注册即忽略。
pub fn set_state_listener(listener: impl FnMut(bool, bool, bool) + 'static) {
    #[cfg(feature = "sqlite-backend")]
    {
        STATE_LISTENER.with(|l| *l.borrow_mut() = Some(Box::new(listener)));
    }
    #[cfg(not(feature = "sqlite-backend"))]
    {
        let _ = listener;
    }
}

/// 三标记统一 notify 入口：各置位点经 set_* 写原子后调
/// 用，以最新三值触发已注册回调（未注册时静默，标记本
/// 身仍可经 is_* 读取）。
#[cfg(feature = "sqlite-backend")]
fn notify_state() {
    let values = (is_occupied(), is_readonly(), is_unavailable());
    STATE_LISTENER.with(|l| {
        if let Some(f) = &mut *l.borrow_mut() {
            f(values.0, values.1, values.2);
        }
    });
}

/// 置位点收口（set_occupied / set_readonly /
/// set_unavailable）：值真变化才 notify——接管成功路径
/// 在未曾独占时也写 false，无变化不打扰呈现。
#[cfg(feature = "sqlite-backend")]
fn set_occupied(v: bool) {
    if OCCUPIED.swap(v, Ordering::Relaxed) != v {
        notify_state();
    }
}

#[cfg(feature = "sqlite-backend")]
fn set_readonly(v: bool) {
    if READONLY.swap(v, Ordering::Relaxed) != v {
        notify_state();
    }
}

#[cfg(feature = "sqlite-backend")]
fn set_unavailable(v: bool) {
    if UNAVAILABLE.swap(v, Ordering::Relaxed) != v {
        notify_state();
    }
}

#[cfg_attr(not(feature = "sqlite-backend"), allow(dead_code))]
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

/// dual 硬失败降级只读中（App 出常驻横幅）。
#[cfg_attr(not(feature = "sqlite-backend"), allow(dead_code))]
pub fn is_readonly() -> bool {
    #[cfg(feature = "sqlite-backend")]
    {
        READONLY.load(Ordering::Relaxed)
    }
    #[cfg(not(feature = "sqlite-backend"))]
    {
        false
    }
}

/// sqlite 形态硬失败阻断中（App 出阻断提示）。
#[cfg_attr(not(feature = "sqlite-backend"), allow(dead_code))]
pub fn is_unavailable() -> bool {
    #[cfg(feature = "sqlite-backend")]
    {
        UNAVAILABLE.load(Ordering::Relaxed)
    }
    #[cfg(not(feature = "sqlite-backend"))]
    {
        false
    }
}

#[cfg(feature = "sqlite-backend")]
fn writes_blocked() -> bool {
    READONLY.load(Ordering::Relaxed) || UNAVAILABLE.load(Ordering::Relaxed)
}

pub async fn load_state() -> Option<(String, String)> {
    log_backend_mode_once();
    match backend() {
        Backend::Idb => crate::idb::load_state().await,
        #[cfg(feature = "sqlite-backend")]
        Backend::Dual | Backend::Sqlite => sqlite::load_state().await,
        #[cfg(not(feature = "sqlite-backend"))]
        _ => crate::idb::load_state().await,
    }
}

/// 编辑保存（分条增量口径）。dual：SQLite 主写成功即成
/// 功，镜像失败只记行 + 置待对账标记，不让保存报错（设
/// 计稿 §1.1）；sqlite 主写失败则整体失败（镜像不单独
/// 写，防分叉）。
pub async fn save_backup_delta(
    backup: &mynote_core::BackupFile,
    upsert: Option<&str>,
    delete: Option<&str>,
) -> Result<(), JsValue> {
    match backend() {
        Backend::Idb => {
            crate::idb::save_backup_delta(backup, upsert, delete).await?;
            Ok(())
        }
        #[cfg(feature = "sqlite-backend")]
        Backend::Dual | Backend::Sqlite => sqlite::save_delta(backup, upsert, delete).await,
        #[cfg(not(feature = "sqlite-backend"))]
        _ => {
            crate::idb::save_backup_delta(backup, upsert, delete).await?;
            Ok(())
        }
    }
}

/// 全量写回（加载期归一收敛）。dual 同 delta 的主写 +
/// 全量镜像口径。
pub async fn save_backup_full(backup: &mynote_core::BackupFile) -> Result<(), JsValue> {
    match backend() {
        Backend::Idb => {
            crate::idb::save_backup_full(backup).await?;
            Ok(())
        }
        #[cfg(feature = "sqlite-backend")]
        Backend::Dual | Backend::Sqlite => sqlite::save_full(backup).await,
        #[cfg(not(feature = "sqlite-backend"))]
        _ => {
            crate::idb::save_backup_full(backup).await?;
            Ok(())
        }
    }
}

/// 导入（两段提交，设计稿 §5.6）：SQLite import_library
/// 与 IDB 侧落盘无法同事务——dual 的 IDB 段是全量镜像，
/// sqlite 的 IDB 段只是附件替换；任一段失败分别记 Diag，
/// 半成品由下次冷启对账（dual）收敛。
pub async fn save_all(
    memos_json: &str,
    manifest_raw: &str,
    attachments: &[(String, Vec<u8>)],
) -> Result<(), JsValue> {
    match backend() {
        Backend::Idb => crate::idb::save_all(memos_json, manifest_raw, attachments).await,
        #[cfg(feature = "sqlite-backend")]
        Backend::Dual | Backend::Sqlite => {
            sqlite::save_all(memos_json, manifest_raw, attachments).await
        }
        #[cfg(not(feature = "sqlite-backend"))]
        _ => crate::idb::save_all(memos_json, manifest_raw, attachments).await,
    }
}

pub async fn save_manifest(manifest_raw: &str) -> Result<(), JsValue> {
    match backend() {
        Backend::Idb => crate::idb::save_manifest(manifest_raw).await,
        #[cfg(feature = "sqlite-backend")]
        Backend::Dual | Backend::Sqlite => sqlite::save_manifest(manifest_raw).await,
        #[cfg(not(feature = "sqlite-backend"))]
        _ => crate::idb::save_manifest(manifest_raw).await,
    }
}

pub async fn put_attachment(id: &str, bytes: &[u8]) -> Result<(), JsValue> {
    #[cfg(feature = "sqlite-backend")]
    {
        if writes_blocked() {
            return Err(JsValue::from_str("storage readonly/unavailable"));
        }
    }
    crate::idb::put_attachment(id, bytes).await
}

pub async fn get_attachment(id: &str) -> Option<Vec<u8>> {
    crate::idb::get_attachment(id).await
}

pub async fn get_all_attachments() -> Vec<(String, Vec<u8>)> {
    crate::idb::get_all_attachments().await
}

/// 冷启对账（设计稿 §2）：列表首绘后由 App 异步调用。
/// 仅 dual 且本会话未迁移/未导入/未降级时执行；其余形
/// 态空转。收敛方向只有 SQLite → IDB，对主库只读。
pub async fn reconcile_if_needed() {
    #[cfg(feature = "sqlite-backend")]
    {
        sqlite::reconcile().await;
    }
}

/// 开关值解析（纯函数，可单测）：localStorage / URL 参
/// 数共用口径。无法识别 → None（调用方走构建默认）。
#[cfg_attr(not(feature = "sqlite-backend"), allow(dead_code))]
pub fn parse_backend_value(v: &str) -> Option<Backend> {
    match v {
        "idb" => Some(Backend::Idb),
        "dual" => Some(Backend::Dual),
        "sqlite" => Some(Backend::Sqlite),
        _ => None,
    }
}

/// 对账漂移计数（纯函数，可单测）：put = SQLite 有而镜
/// 像缺失或哈希不同；del = 镜像有而 SQLite 已无。
#[cfg(feature = "sqlite-backend")]
fn drift_counts(
    sqlite_hashes: &HashMap<String, u64>,
    idb_hashes: &HashMap<String, u64>,
) -> (usize, usize) {
    let mut put = 0usize;
    let mut del = 0usize;
    for (id, h) in sqlite_hashes {
        match idb_hashes.get(id) {
            Some(ih) if ih == h => {}
            _ => put += 1,
        }
    }
    for id in idb_hashes.keys() {
        if !sqlite_hashes.contains_key(id) {
            del += 1;
        }
    }
    (put, del)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_value_parsing() {
        assert_eq!(parse_backend_value("idb"), Some(Backend::Idb));
        assert_eq!(parse_backend_value("dual"), Some(Backend::Dual));
        assert_eq!(parse_backend_value("sqlite"), Some(Backend::Sqlite));
        assert_eq!(parse_backend_value("auto"), None);
        assert_eq!(parse_backend_value(""), None);
    }

    #[cfg(feature = "sqlite-backend")]
    #[test]
    fn fnv1a_matches_storage_vectors() {
        // 与 mynote-storage::fnv1a_64 同口径的已知向量。
        assert_eq!(fnv1a_64(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a_64(b"a"), 0xaf63_dc4c_8601_ec8c);
    }

    #[cfg(feature = "sqlite-backend")]
    #[test]
    fn drift_counting() {
        let mut s: HashMap<String, u64> = HashMap::new();
        let mut i: HashMap<String, u64> = HashMap::new();
        s.insert("a".into(), 1);
        s.insert("b".into(), 2);
        i.insert("a".into(), 1);
        i.insert("b".into(), 2);
        assert_eq!(drift_counts(&s, &i), (0, 0));
        // 内容漂移 → put。
        i.insert("b".into(), 99);
        assert_eq!(drift_counts(&s, &i), (1, 0));
        // 镜像缺失 → put；镜像多出 → del。
        i.remove("b");
        i.insert("ghost".into(), 7);
        assert_eq!(drift_counts(&s, &i), (1, 1));
        // 镜像全缺 → 全部 put。
        i.clear();
        assert_eq!(drift_counts(&s, &i), (2, 0));
    }
}

/// FNV-1a 64（对账口径）：与 mynote-storage::fnv1a_64 同
/// 常量同算法——web 包不依赖 storage crate（避免把
/// rusqlite 拉进主 wasm），在此复刻并以 storage 原生测
/// 试为口径源。
#[cfg(feature = "sqlite-backend")]
fn fnv1a_64(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        h ^= *b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
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

    // —— 池分区指纹（存储阻断第 5 项）——
    // SQLite 池命名对齐浏览器分区边界：localStorage 键
    // mynote_pool_v1 存本分区的池 id——同分区各标签同值
    // （同池、独占口径不变）；异分区异值（异池、永不互
    // 挡，无痕侧得自有临时数据集）。Worker 无 localStorage
    // 访问权，指纹在主线程解析、经 init 载荷下传。
    // 存量不孤儿：键缺失时先看 IDB 存量——有存量回退现行
    // 默认池并写回 "default"（观察期现网用户的池就是默认
    // 名，首启升级不换池）；无存量才生成随机指纹写回。
    // 指纹只用随机值、不含设备/账号信息；Diag 只记指纹
    // 哈希前 4 位、不记全值。
    const POOL_KEY: &str = "mynote_pool_v1";

    thread_local! {
        static POOL_ID: RefCell<Option<String>> = const { RefCell::new(None) };
    }

    fn pool_fp_valid(fp: &str) -> bool {
        !fp.is_empty()
            && fp.len() <= 32
            && fp.bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
    }

    fn random_pool_fp() -> String {
        let mut buf = [0u8; 8];
        let filled = web_sys::window()
            .and_then(|w| w.crypto().ok())
            .and_then(|c| c.get_random_values_with_u8_array(&mut buf).ok())
            .is_some();
        if !filled {
            for b in buf.iter_mut() {
                *b = (js_sys::Math::random() * 256.0) as u8;
            }
        }
        buf.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn pool_fp_hash4(fp: &str) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        let mut h = DefaultHasher::new();
        fp.hash(&mut h);
        format!("{:016x}", h.finish())[..4].to_string()
    }

    /// 池 id 解析（每页会话一次、结果缓存——Worker 重建
    /// 必须回到同一个池）。返回 "default" 或分区指纹。
    async fn resolve_pool_id() -> String {
        if let Some(id) = POOL_ID.with(|c| c.borrow().clone()) {
            return id;
        }
        let ls = web_sys::window()
            .and_then(|w| w.local_storage().ok().flatten());
        let stored = ls
            .as_ref()
            .and_then(|s| s.get_item(POOL_KEY).ok().flatten());
        let id = match stored.as_deref() {
            Some("default") => "default".to_string(),
            Some(fp) if pool_fp_valid(fp) => fp.to_string(),
            _ => {
                if crate::idb::has_library_data().await {
                    if let Some(s) = &ls {
                        let _ = s.set_item(POOL_KEY, "default");
                    }
                    "default".to_string()
                } else {
                    let fp = random_pool_fp();
                    if let Some(s) = &ls {
                        let _ = s.set_item(POOL_KEY, &fp);
                    }
                    fp
                }
            }
        };
        if id == "default" {
            crate::diag::log("SQLITE", "pool resolved: default");
        } else {
            crate::diag::log(
                "SQLITE",
                &format!("pool resolved: fp hash={}", pool_fp_hash4(&id)),
            );
        }
        POOL_ID.with(|c| *c.borrow_mut() = Some(id.clone()));
        id
    }

    enum InitOutcome {
        Ready,
        /// 独占（install 失败）：随带 Worker 回的失败原文
        /// 摘要，供 Diag 分类打点（见 install_error_kind）。
        Occupied(Option<String>),
        Failed(String),
    }

    async fn bridge_init() -> InitOutcome {
        let pool = resolve_pool_id().await;
        let payload = obj_payload(&[("pool", JsValue::from_str(&pool))]);
        match rpc("init", payload).await {
            Ok(v) => match v.get("status").and_then(|s| s.as_str()) {
                Some("ready") => InitOutcome::Ready,
                Some("occupied") => InitOutcome::Occupied(
                    v.get("error")
                        .and_then(|s| s.as_str())
                        .map(str::to_string),
                ),
                _ => InitOutcome::Failed(format!("unexpected init reply: {v}")),
            },
            Err(e) => InitOutcome::Failed(e),
        }
    }

    /// 终止并丢弃当前存储 Worker（接管重试专用，见
    /// wait_ready）：下一次 rpc 经 bridge() 全新 spawn。
    /// 仅在等待循环内调用——彼时 init 尝试已回、无其他
    /// RPC 在飞，terminate 不会孤儿化在途请求。
    fn reset_bridge() {
        let old = BRIDGE.with(|b| b.borrow_mut().take());
        if let Some(b) = old {
            b.worker.terminate();
        }
    }

    /// install 失败分类（Diag 打点用）：锁冲突的实证签名
    /// = SAHPool 句柄创建失败（阶段一 spike 实测原文
    /// "An error occurred while creating sync access
    /// handle"，Chromium 口径）；其余一律 other，原文摘
    /// 要随行入 Diag——WebKit 文案未实证，不按猜测分流
    /// 呈现（文案不分流），待真机 Diag 回看再定签名。
    fn install_error_kind(err: Option<&str>) -> &'static str {
        match err {
            Some(e) if e.contains("sync access handle") => "lock",
            Some(_) => "other",
            None => "unknown",
        }
    }

    /// 独占等待：被另一标签持有时置 OCCUPIED（App 出提
    /// 示态），每 250ms 查催促标记、满 2s 重试 init；接
    /// 管成功记结果行后返回 true。硬失败返回 false（姿
    /// 态由 load_state 按形态定：dual 只读降级 / sqlite
    /// 阻断，设计稿 §3——不再可写直读回退）。
    ///
    /// 重试一律重建 Worker（2026-11-25 真机缺陷根治）：
    /// iOS Safari 实证——install 失败过的 Worker 实例内
    /// VFS 状态楔死，锁释放后同页反复 install 仍拿不到
    /// 句柄（等十几秒不接管、点重试无果），整页刷新换新
    /// Worker 立即成功。故每次 Occupied 后先 terminate
    /// 旧 Worker，下一轮尝试在全新实例里 spawn +
    /// install；等待期间呈现保持阻断态（OCCUPIED 不动、
    /// 无闪退）。Chromium 口径下旧路径本可接管，重建不
    /// 改变其时序（释放后首个重试周期内成功）。
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
                    set_occupied(false);
                    return true;
                }
                InitOutcome::Occupied(err) => {
                    if !announced {
                        announced = true;
                        set_occupied(true);
                        // 占用行带 install 失败分类与原文摘
                        // 要：「占用」自此是实证不是猜测。
                        let kind = install_error_kind(err.as_deref());
                        let summary = match &err {
                            Some(e) => {
                                let cut: String = e.chars().take(160).collect();
                                format!(" err=\"{cut}\"")
                            }
                            None => String::new(),
                        };
                        crate::diag::log_warn(
                            "SQLITE",
                            &format!(
                                "storage occupied by another tab; waiting for takeover; install kind={kind}{summary}"
                            ),
                        );
                    }
                    // 本轮尝试已回、无 RPC 在飞：终止旧
                    // Worker，下一轮在全新实例里重试（见
                    // 函数注）。催促标记只缩短等待、不改
                    // 这条路径。
                    reset_bridge();
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
                    set_occupied(false);
                    return false;
                }
            }
        }
    }

    /// 硬失败姿态落点：dual → 只读降级（数据面 = IDB 镜
    /// 像）；sqlite → 阻断（数据面同为末次镜像、仅供阻断
    /// 层后呈现，不可写）。返回 IDB 组装读结果作呈现数据。
    async fn hard_failure_state() -> Option<(String, String)> {
        match backend() {
            Backend::Dual => {
                set_readonly(true);
                crate::diag::log_warn("SQLITE", "backend unavailable, readonly fallback");
            }
            _ => {
                set_unavailable(true);
                crate::diag::log_warn("SQLITE", "backend unavailable, blocked");
            }
        }
        crate::idb::load_state().await
    }

    /// 存量归一（迁移入参通道，设计稿 §5.2）：与主加载
    /// 路径 run_stock_migration 同算法——克隆上逐篇归一
    /// + 隔离，候选可严格解析才采用；失败返回 None（调
    /// 用方放弃迁移、原文回退 IDB 加载，归一与隔离由主
    /// 加载路径照旧处理）。
    fn normalize_stock(
        memos_json: &str,
    ) -> Option<(
        String,
        mynote_core::migrate::MigrationStats,
        Vec<serde_json::Value>,
        usize,
    )> {
        let raw: serde_json::Value = serde_json::from_str(memos_json).ok()?;
        let before_memos = raw
            .get("memos")
            .and_then(|m| m.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        let mut candidate = raw;
        let outcome = mynote_core::migrate::normalize_stock_value(&mut candidate);
        let kept = candidate
            .get("memos")
            .and_then(|m| m.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        let valid = serde_json::from_value::<mynote_core::BackupFile>(candidate.clone())
            .map(|b| b.memos.len() == kept)
            .unwrap_or(false);
        if !valid {
            return None;
        }
        let json = serde_json::to_string(&candidate).ok()?;
        Some((json, outcome.stats, outcome.quarantined, before_memos))
    }

    pub async fn load_state() -> Option<(String, String)> {
        if !wait_ready().await {
            return hard_failure_state().await;
        }
        let status = rpc("migration_status", JsValue::UNDEFINED)
            .await
            .unwrap_or(serde_json::Value::Null);
        let migrated = status.get("done").and_then(|v| v.as_bool()).unwrap_or(false);
        let idb_state = crate::idb::load_state().await;
        let mut migrated_now = false;
        if !migrated {
            if let Some((memos_json, manifest_raw)) = &idb_state {
                // 迁移入参先过存量归一（坏篇走隔离通道，
                // 不整库失败）；归一校验不过 → 放弃迁移、
                // 原文回退（主加载路径照旧归一/隔离）。
                let Some((clean_json, stats, quarantined, before_memos)) =
                    normalize_stock(memos_json)
                else {
                    crate::diag::log(
                        "SQLITE",
                        "migrate skipped: stock normalization validation failed, idb load",
                    );
                    return idb_state;
                };
                // 隔离原文先落盘（顺序红线）：失败则本轮
                // 不迁移，盘上存量原样、下轮重试。
                if !quarantined.is_empty() {
                    let existing = crate::idb::load_quarantine().await;
                    let (doc, total) = mynote_core::migrate::merge_quarantine(
                        existing.as_deref(),
                        &quarantined,
                    );
                    match crate::idb::save_quarantine(&doc).await {
                        Ok(()) => {
                            crate::diag::log(
                                "APP",
                                &format!(
                                    "QUARANTINE isolated={} of {before_memos} -> idb kv {} (originals preserved)",
                                    quarantined.len(),
                                    crate::idb::QUARANTINE_KEY
                                ),
                            );
                            crate::diag::log(
                                "APP",
                                &format!(
                                    "QUARANTINE stored total={total} key={}",
                                    crate::idb::QUARANTINE_KEY
                                ),
                            );
                        }
                        Err(_) => {
                            crate::diag::log(
                                "SQLITE",
                                "migrate skipped: quarantine store failed, idb load",
                            );
                            return idb_state;
                        }
                    }
                }
                if stats.total_changes() > 0 {
                    crate::diag::log("APP", &format!("MIGRATE d3 {}", stats.summary()));
                    crate::diag::log("APP", &format!("MIGRATE census {}", stats.census_summary()));
                }
                let payload = obj_payload(&[
                    ("memos_json", JsValue::from_str(&clean_json)),
                    ("manifest_raw", JsValue::from_str(manifest_raw)),
                ]);
                match rpc("migrate", payload).await {
                    Ok(rep) => {
                        migrated_now = true;
                        SESSION_ALIGNED.store(true, Ordering::Relaxed);
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
                    // 两后端皆空：与 IDB 形态同口径返回
                    // None，应用走种子样本。
                    return None;
                }
                if migrated_now {
                    // 迁移后收敛镜像（设计稿 §5.4）：归一
                    // 后形态走 IDB 分条全量写回，IDB 副本
                    // 保持为有效镜像；quarantine_json 键不
                    // 在写回面内、不受触碰。失败只记行——
                    // 主库已在 SQLite，镜像由对账兜底。
                    match serde_json::from_str::<mynote_core::BackupFile>(&memos_json) {
                        Ok(parsed) => match crate::idb::save_backup_full(&parsed).await {
                            Ok(_) => crate::diag::log(
                                "SQLITE",
                                "idb mirror converged after migrate",
                            ),
                            Err(e) => crate::diag::log_warn(
                                "SQLITE",
                                &format!("idb mirror converge failed after migrate: {e:?}"),
                            ),
                        },
                        Err(e) => crate::diag::log_warn(
                            "SQLITE",
                            &format!("idb mirror converge parse failed: {e}"),
                        ),
                    }
                }
                crate::diag::log("SQLITE", &format!("load source=sqlite memos={n}"));
                Some((memos_json, manifest_raw))
            }
            Err(e) => {
                crate::diag::log("SQLITE", &format!("load_all failed: {e}"));
                hard_failure_state().await
            }
        }
    }

    async fn save_sync_rpc(memos_json: &str) -> Result<serde_json::Value, String> {
        let payload = obj_payload(&[("memos_json", JsValue::from_str(memos_json))]);
        rpc("save_sync", payload).await
    }

    fn sync_counts(rep: &serde_json::Value) -> (u64, u64, u64, f64) {
        (
            rep.get("upserted").and_then(|v| v.as_u64()).unwrap_or(0),
            rep.get("deleted").and_then(|v| v.as_u64()).unwrap_or(0),
            rep.get("unchanged").and_then(|v| v.as_u64()).unwrap_or(0),
            rep.get("ms").and_then(|v| v.as_f64()).unwrap_or(0.0),
        )
    }

    /// 主写 + 镜像的统一落点：SQLite save_sync 成功后，
    /// dual 再落 IDB 镜像（delta/full 由 mirror_full 决
    /// 定），结果段拼进同一条 SQLITE save_sync 行（设计
    /// 稿 §1.1）；镜像失败不报错、置 MIRROR_DIRTY 待对账。
    async fn save_with_mirror(
        backup: &mynote_core::BackupFile,
        mirror: Option<(Option<&str>, Option<&str>, bool)>,
    ) -> Result<(), JsValue> {
        if writes_blocked() {
            return Err(JsValue::from_str("storage readonly/unavailable"));
        }
        let json = serde_json::to_string(backup)
            .map_err(|e| JsValue::from_str(&format!("save serialize: {e}")))?;
        let rep = save_sync_rpc(&json)
            .await
            .map_err(|e| JsValue::from_str(&e))?;
        let (up, del, un, ms) = sync_counts(&rep);
        let base = format!("save_sync upserted={up} deleted={del} unchanged={un} {ms:.0}ms");
        match (backend(), mirror) {
            (Backend::Dual, Some((upsert, delete, full))) => {
                let mirrored = if full {
                    crate::idb::save_backup_full(backup)
                        .await
                        .map(|s| (s.upserts, s.deletes))
                } else {
                    crate::idb::save_backup_delta(backup, upsert, delete)
                        .await
                        .map(|s| (s.upserts, s.deletes))
                };
                match mirrored {
                    Ok((mu, md)) => {
                        crate::diag::log(
                            "SQLITE",
                            &format!("{base} mirror=ok up={mu} del={md}"),
                        );
                    }
                    Err(e) => {
                        MIRROR_DIRTY.store(true, Ordering::Relaxed);
                        crate::diag::log_warn(
                            "SQLITE",
                            &format!("{base} mirror=fail {e:?}"),
                        );
                    }
                }
            }
            _ => {
                crate::diag::log("SQLITE", &base);
            }
        }
        Ok(())
    }

    pub async fn save_delta(
        backup: &mynote_core::BackupFile,
        upsert: Option<&str>,
        delete: Option<&str>,
    ) -> Result<(), JsValue> {
        save_with_mirror(backup, Some((upsert, delete, false))).await
    }

    pub async fn save_full(backup: &mynote_core::BackupFile) -> Result<(), JsValue> {
        save_with_mirror(backup, Some((None, None, true))).await
    }

    pub async fn save_all(
        memos_json: &str,
        manifest_raw: &str,
        attachments: &[(String, Vec<u8>)],
    ) -> Result<(), JsValue> {
        if writes_blocked() {
            return Err(JsValue::from_str("storage readonly/unavailable"));
        }
        let payload = obj_payload(&[
            ("memos_json", JsValue::from_str(memos_json)),
            ("manifest_raw", JsValue::from_str(manifest_raw)),
        ]);
        rpc("import_library", payload)
            .await
            .map_err(|e| JsValue::from_str(&e))?;
        // 第二段（IDB 侧）：dual = 全量镜像（基线重对
        // 齐）；sqlite = 仅附件（备忘不镜像）。两段无法
        // 同事务：本段失败记 warn 行，下次冷启对账收敛
        // （dual）；首段已提交，导入不回滚。
        let seg = match backend() {
            Backend::Dual => crate::idb::save_all(memos_json, manifest_raw, attachments)
                .await
                .map(|_| "idb mirrored"),
            _ => crate::idb::replace_attachments(attachments)
                .await
                .map(|_| "attachments idb"),
        };
        match seg {
            Ok(how) => {
                SESSION_ALIGNED.store(true, Ordering::Relaxed);
                crate::diag::log(
                    "SQLITE",
                    &format!(
                        "import_library ok memos_json={}B atts={} ({how})",
                        memos_json.len(),
                        attachments.len()
                    ),
                );
            }
            Err(e) => {
                crate::diag::log_warn(
                    "SQLITE",
                    &format!(
                        "import_library ok memos_json={}B atts={} mirror=fail {e:?}",
                        memos_json.len(),
                        attachments.len()
                    ),
                );
            }
        }
        Ok(())
    }

    pub async fn save_manifest(manifest_raw: &str) -> Result<(), JsValue> {
        if writes_blocked() {
            return Err(JsValue::from_str("storage readonly/unavailable"));
        }
        let payload = obj_payload(&[("manifest_raw", JsValue::from_str(manifest_raw))]);
        rpc("save_manifest", payload)
            .await
            .map_err(|e| JsValue::from_str(&e))?;
        if backend() == Backend::Dual {
            // meta 镜像同写（设计稿 §1.3）：失败只记行，
            // manifest 不属对账面（篇哈希），由导入/迁移
            // 的全量镜像兜底重对齐。
            if let Err(e) = crate::idb::save_manifest(manifest_raw).await {
                crate::diag::log_warn("SQLITE", &format!("manifest mirror=fail {e:?}"));
            }
        }
        Ok(())
    }

    /// 冷启对账本体（门面 reconcile_if_needed 的 sqlite
    /// 实现）：逐篇哈希比对 SQLite vs IDB 镜像，漂移以
    /// load_all 全量镜像写回收敛（漂移应为少数事件，全
    /// 量写回只在有漂移时发生）。
    pub async fn reconcile() {
        if backend() != Backend::Dual
            || READONLY.load(Ordering::Relaxed)
            || UNAVAILABLE.load(Ordering::Relaxed)
            || SESSION_ALIGNED.load(Ordering::Relaxed)
        {
            return;
        }
        let t0 = js_sys::Date::now();
        match run_reconcile().await {
            Ok((n, 0, 0)) => {
                crate::diag::log(
                    "SQLITE",
                    &format!(
                        "reconcile ok memos={n} ms={:.0}",
                        js_sys::Date::now() - t0
                    ),
                );
            }
            Ok((_, put, del)) => {
                crate::diag::log(
                    "SQLITE",
                    &format!(
                        "reconcile drift put={put} del={del} ms={:.0}",
                        js_sys::Date::now() - t0
                    ),
                );
            }
            Err(e) => {
                crate::diag::log_warn("SQLITE", &format!("reconcile fail {e}"));
            }
        }
    }

    async fn run_reconcile() -> Result<(usize, usize, usize), String> {
        let rep = rpc("memo_hashes", JsValue::UNDEFINED).await?;
        let mut sqlite_hashes: HashMap<String, u64> = HashMap::new();
        if let Some(obj) = rep.get("hashes").and_then(|v| v.as_object()) {
            for (id, h) in obj {
                if let Some(hv) = h.as_str().and_then(|s| s.parse::<u64>().ok()) {
                    sqlite_hashes.insert(id.clone(), hv);
                }
            }
        }
        // IDB 镜像侧哈希：组装读 → 模型解析 → 逐篇以
        // typed 序列化复算（与 SQLite 落盘形同口径；分条
        // 条目是 Value 形字节，不能直接对原文哈希）。
        let mut idb_hashes: HashMap<String, u64> = HashMap::new();
        if let Some((memos_json, _)) = crate::idb::load_state().await {
            let backup: mynote_core::BackupFile =
                serde_json::from_str(&memos_json).map_err(|e| format!("idb parse: {e}"))?;
            for m in &backup.memos {
                let typed = serde_json::to_string(m).map_err(|e| format!("reserialize: {e}"))?;
                idb_hashes.insert(m.id.to_string(), fnv1a_64(typed.as_bytes()));
            }
        }
        let (put, del) = drift_counts(&sqlite_hashes, &idb_hashes);
        if put + del > 0 {
            // 收敛：SQLite 全量 → IDB 分条全量镜像写回
            // （对 SQLite 只读；写回不动 quarantine 键）。
            let la = rpc("load_all", JsValue::UNDEFINED).await?;
            let memos_json = la
                .get("memos_json")
                .and_then(|s| s.as_str())
                .unwrap_or_default();
            let backup: mynote_core::BackupFile =
                serde_json::from_str(memos_json).map_err(|e| format!("sqlite parse: {e}"))?;
            crate::idb::save_backup_full(&backup)
                .await
                .map_err(|e| format!("converge write: {e:?}"))?;
            if MIRROR_DIRTY.swap(false, Ordering::Relaxed) {
                crate::diag::log("SQLITE", "mirror dirty cleared by reconcile");
            }
        }
        Ok((sqlite_hashes.len(), put, del))
    }
}
