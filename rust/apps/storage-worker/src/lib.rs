//! Mynote 存储 Worker（SQLite 接入阶段二）：Dedicated
//! Worker 内以 SAHPool VFS（OPFS 同步句柄池）承载
//! mynote-storage 的 Store 本体，主线程经 postMessage
//! RPC 桥调用（worker.js 分发 → 本文件 `rpc`）。
//!
//! RPC 协议：请求 {id, cmd, payload}，响应由 worker.js
//! 包裹 {id, ok, result|error}；本文件只管 cmd 语义。
//! 命令面与现行 idb.rs 消费面对齐（见 apps/web/src/
//! persist.rs 的桥口径表）：
//!   init / migration_status / migrate / load_all /
//!   save_sync / import_library / save_manifest /
//!   search / bench_import_zip / stats
//!
//! 数据纪律：
//! - 归一只在写入路径（方案 (b)）：migrate 逐篇过
//!   core::migrate 通道（与主线程加载期归一同校验纪律：
//!   节点守恒校验不过整笔放弃、源不动）；sync/import 的
//!   入参已是模型态（主线程通道产物），落库时盖
//!   normalize_version 戳；开库戳过期由 Store::
//!   renormalize_library 整库重归一。
//! - 附件不入 SQLite（Web 口径留文件式）：本 Worker 不
//!   读写附件字节，attachments 表恒空。
//! - 迁移单事务换库 + 回读哈希对账，全等才落
//!   migration_stamp；IDB 原库由主线程持有、本 Worker
//!   永不写 IDB，迁移失败/中断后重跑 migrate 即续演练。

use std::path::Path;

use mynote_core::BackupFile;
use mynote_storage::{fnv1a_64, library_hash, Store};
use serde_json::{json, Value};
use wasm_bindgen::prelude::*;

const DB_NAME: &str = "mynote.db";

#[cfg(all(target_family = "wasm", target_os = "unknown"))]
mod imp {
    use super::*;
    use sqlite_wasm_rs as ffi;
    use sqlite_wasm_vfs::sahpool::{install as install_opfs_sahpool, OpfsSAHPoolCfg};

    thread_local! {
        static POOL: std::cell::RefCell<
            Option<sqlite_wasm_vfs::sahpool::OpfsSAHPoolUtil>,
        > = const { std::cell::RefCell::new(None) };
        static STORE: std::cell::RefCell<Option<Store>> =
            const { std::cell::RefCell::new(None) };
    }

    fn now_ms() -> f64 {
        js_sys::Date::now()
    }

    /// 开库（含 SAHPool 安装与开库整库重归一）。独占冲突
    /// 时返回 status=occupied 的结构化结果（非错误）：
    /// SAHPool 单连接独占下第二标签的 install 必失败，
    /// 主线程据此出提示态、不触碰数据库。
    async fn cmd_init() -> Result<Value, String> {
        let installed = POOL.with(|p| p.borrow().is_some());
        if !installed {
            match install_opfs_sahpool::<ffi::WasmOsCallback>(&OpfsSAHPoolCfg::default(), true)
                .await
            {
                Ok(util) => POOL.with(|p| *p.borrow_mut() = Some(util)),
                Err(e) => {
                    return Ok(json!({
                        "status": "occupied",
                        "error": format!("sahpool install failed: {e}"),
                    }));
                }
            }
        }
        if STORE.with(|s| s.borrow().is_some()) {
            return Ok(json!({ "status": "ready", "already": true }));
        }
        let mut store = Store::open(Path::new(DB_NAME)).map_err(|e| format!("open: {e}"))?;
        let renormalized = store
            .renormalize_library()
            .map_err(|e| format!("renormalize: {e}"))?;
        let memos = store.memo_count().map_err(|e| format!("count: {e}"))?;
        let migrated = store
            .get_meta("migration_stamp")
            .map_err(|e| format!("stamp: {e}"))?
            .is_some();
        STORE.with(|s| *s.borrow_mut() = Some(store));
        Ok(json!({
            "status": "ready",
            "memos": memos,
            "migrated": migrated,
            "renormalized": renormalized,
        }))
    }

    fn with_store<R>(f: impl FnOnce(&mut Store) -> Result<R, String>) -> Result<R, String> {
        STORE.with(|s| {
            let mut slot = s.borrow_mut();
            let store = slot.as_mut().ok_or("store not initialized")?;
            f(store)
        })
    }

    fn payload_str(payload: &JsValue, key: &str) -> Result<String, String> {
        let v = js_sys::Reflect::get(payload, &JsValue::from_str(key))
            .map_err(|_| format!("payload.{key} unreadable"))?;
        v.as_string().ok_or_else(|| format!("payload.{key} missing"))
    }

    fn node_total(backup: &Value) -> usize {
        backup
            .get("memos")
            .and_then(|m| m.as_array())
            .map(|memos| {
                memos
                    .iter()
                    .map(|m| {
                        m.get("doc")
                            .and_then(|d| d.as_array())
                            .map(|doc| mynote_core::migrate::count_nodes_value(doc))
                            .unwrap_or(0)
                    })
                    .sum()
            })
            .unwrap_or(0)
    }

    /// 迁移：IDB 存量（memos_json 原文 + manifest_raw）
    /// → SQLite。与主线程加载期归一（run_stock_migration）
    /// 同校验纪律：Value 层归一（方案 (b) 写路径归一）、
    /// 节点守恒 + 篇数守恒校验、严格解析，全过才单事务
    /// 换库并回读逐篇哈希对账；任一步失败整笔放弃，
    /// SQLite 与 IDB 两侧都保持原状（可重入续跑）。
    fn cmd_migrate(payload: &JsValue) -> Result<Value, String> {
        let t0 = now_ms();
        let memos_json = payload_str(payload, "memos_json")?;
        let manifest_raw = payload_str(payload, "manifest_raw").unwrap_or_default();
        let mut raw: Value =
            serde_json::from_str(&memos_json).map_err(|e| format!("source parse: {e}"))?;
        let before_nodes = node_total(&raw);
        let before_memos = raw
            .get("memos")
            .and_then(|m| m.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        let stats = mynote_core::normalize_value(&mut raw);
        // 校验口径与主线程 run_stock_migration 逐项一致：
        // 归一后节点数 = 归一前 - gallery 影子 children 清
        // 除数，且严格解析后篇数守恒；不过整笔放弃。
        let expected_nodes = before_nodes - stats.gallery_children_removed;
        if node_total(&raw) != expected_nodes {
            return Err("migration validation failed, source untouched".into());
        }
        let backup: BackupFile = match serde_json::from_value::<BackupFile>(raw) {
            Ok(b) if b.memos.len() == before_memos => b,
            Ok(_) => return Err("migration validation failed, source untouched".into()),
            Err(e) => return Err(format!("migration validation failed: {e}")),
        };
        // 源侧逐篇哈希（归一后模型序列化口径，与落库的
        // memo_json 同形态）。
        let mut per_memo: Vec<(String, u64)> = Vec::new();
        for m in &backup.memos {
            let s = serde_json::to_string(m).map_err(|e| format!("hash ser: {e}"))?;
            per_memo.push((m.id.to_string(), fnv1a_64(s.as_bytes())));
        }
        let agg = library_hash(&per_memo);
        let stamp = json!({
            "source": "idb",
            "memos": backup.memos.len(),
            "hash": agg.to_string(),
            "at": now_ms() as i64,
        })
        .to_string();
        let manifest_opt = if manifest_raw.is_empty() {
            None
        } else {
            Some(manifest_raw.as_str())
        };
        with_store(|store| {
            store
                .replace_library(&backup, manifest_opt, &[("migration_stamp", &stamp)])
                .map_err(|e| format!("replace: {e}"))?;
            // 回读对账：篇数与聚合哈希须与源侧逐值相等。
            let back = store.memo_hashes().map_err(|e| format!("readback: {e}"))?;
            if back.len() != per_memo.len() || library_hash(&back) != agg {
                return Err("reconcile mismatch after write".into());
            }
            Ok(json!({
                "memos": backup.memos.len(),
                "hash": agg.to_string(),
                "mig_summary": stats.summary(),
                "mig_census": stats.census_summary(),
                "mig_changes": stats.total_changes(),
                "ms": now_ms() - t0,
            }))
        })
    }

    fn cmd_load_all() -> Result<Value, String> {
        with_store(|store| {
            let memos = store.list_memos().map_err(|e| format!("list: {e}"))?;
            let n = memos.len();
            let avatars: Option<Value> = store
                .get_meta("avatars_json")
                .map_err(|e| format!("avatars: {e}"))?
                .and_then(|s| serde_json::from_str(&s).ok())
                .filter(|v: &Value| !v.is_null());
            let backup = BackupFile { version: 2, exported_at: None, memos, avatars };
            let memos_json =
                serde_json::to_string(&backup).map_err(|e| format!("ser: {e}"))?;
            let manifest_raw = store
                .get_meta("manifest_json")
                .map_err(|e| format!("manifest: {e}"))?
                .unwrap_or_default();
            // has_library：本库已被正式使用过（迁移完成或
            // 任一写路径落过数）——门面据此区分「空库首启
            // 走种子」与「用户已删空的真库」。
            let has_library = store
                .get_meta("migration_stamp")
                .map_err(|e| format!("stamp: {e}"))?
                .is_some()
                || store
                    .get_meta("has_library")
                    .map_err(|e| format!("has_library: {e}"))?
                    .as_deref()
                    == Some("1");
            Ok(json!({
                "memos_json": memos_json,
                "manifest_raw": manifest_raw,
                "memos": n,
                "has_library": has_library,
            }))
        })
    }

    fn cmd_save_sync(payload: &JsValue) -> Result<Value, String> {
        let t0 = now_ms();
        let memos_json = payload_str(payload, "memos_json")?;
        let backup: BackupFile =
            serde_json::from_str(&memos_json).map_err(|e| format!("parse: {e}"))?;
        with_store(|store| {
            let stats = store.sync_library(&backup).map_err(|e| format!("sync: {e}"))?;
            store
                .set_meta("has_library", "1")
                .map_err(|e| format!("has_library: {e}"))?;
            Ok(json!({
                "upserted": stats.upserted,
                "deleted": stats.deleted,
                "unchanged": stats.unchanged,
                "ms": now_ms() - t0,
            }))
        })
    }

    fn cmd_import_library(payload: &JsValue) -> Result<Value, String> {
        let t0 = now_ms();
        let memos_json = payload_str(payload, "memos_json")?;
        let manifest_raw = payload_str(payload, "manifest_raw").unwrap_or_default();
        let backup: BackupFile =
            serde_json::from_str(&memos_json).map_err(|e| format!("parse: {e}"))?;
        let n = backup.memos.len();
        with_store(|store| {
            store
                .replace_library(
                    &backup,
                    if manifest_raw.is_empty() { None } else { Some(&manifest_raw) },
                    &[],
                )
                .map_err(|e| format!("replace: {e}"))?;
            store
                .set_meta("has_library", "1")
                .map_err(|e| format!("has_library: {e}"))?;
            Ok(json!({ "memos": n, "ms": now_ms() - t0 }))
        })
    }

    fn cmd_save_manifest(payload: &JsValue) -> Result<Value, String> {
        let manifest_raw = payload_str(payload, "manifest_raw")?;
        with_store(|store| {
            store
                .set_meta("manifest_json", &manifest_raw)
                .map_err(|e| format!("set_meta: {e}"))?;
            Ok(json!({}))
        })
    }

    fn cmd_search(payload: &JsValue) -> Result<Value, String> {
        let t0 = now_ms();
        let query = payload_str(payload, "query")?;
        with_store(|store| {
            let ids = store.search(&query).map_err(|e| format!("search: {e}"))?;
            Ok(json!({ "ids": ids, "ms": now_ms() - t0 }))
        })
    }

    fn cmd_bench_import_zip(payload: &JsValue) -> Result<Value, String> {
        let t0 = now_ms();
        let v = js_sys::Reflect::get(payload, &JsValue::from_str("bytes"))
            .map_err(|_| "payload.bytes unreadable".to_string())?;
        let arr: js_sys::Uint8Array = v
            .dyn_into()
            .map_err(|_| "payload.bytes is not a Uint8Array".to_string())?;
        let bytes = arr.to_vec();
        with_store(|store| {
            let (stats, mig) = store
                .import_backup_bytes(&bytes, false)
                .map_err(|e| format!("import: {e}"))?;
            Ok(json!({
                "memos": stats.memos,
                "attachments": stats.attachments,
                "mig_changes": mig.total_changes(),
                "ms": now_ms() - t0,
            }))
        })
    }

    pub async fn dispatch(cmd: &str, payload: &JsValue) -> Result<Value, String> {
        match cmd {
            "init" => cmd_init().await,
            "migration_status" => with_store(|store| {
                let stamp = store
                    .get_meta("migration_stamp")
                    .map_err(|e| format!("stamp: {e}"))?;
                Ok(json!({ "done": stamp.is_some(), "stamp": stamp }))
            }),
            "migrate" => cmd_migrate(payload),
            "load_all" => cmd_load_all(),
            "save_sync" => cmd_save_sync(payload),
            "import_library" => cmd_import_library(payload),
            "save_manifest" => cmd_save_manifest(payload),
            "search" => cmd_search(payload),
            "bench_import_zip" => cmd_bench_import_zip(payload),
            "stats" => with_store(|store| {
                Ok(json!({
                    "memos": store.memo_count().map_err(|e| format!("count: {e}"))?,
                    "attachments": store
                        .attachment_count()
                        .map_err(|e| format!("att count: {e}"))?,
                    "normalize_version": store
                        .get_meta("normalize_version")
                        .map_err(|e| format!("nv: {e}"))?,
                }))
            }),
            other => Err(format!("unknown cmd {other}")),
        }
    }
}

/// RPC 入口（worker.js 分发）：payload 为 JS 对象
/// （字段随 cmd 而定），返回 JSON 值；错误以字符串拒。
#[wasm_bindgen]
pub async fn rpc(cmd: String, payload: JsValue) -> Result<JsValue, JsValue> {
    #[cfg(all(target_family = "wasm", target_os = "unknown"))]
    {
        match imp::dispatch(&cmd, &payload).await {
            Ok(v) => Ok(serde_json::to_string(&v)
                .map(|s| JsValue::from_str(&s))
                .unwrap_or_else(|_| JsValue::from_str("{}"))),
            Err(e) => Err(JsValue::from_str(&e)),
        }
    }
    #[cfg(not(all(target_family = "wasm", target_os = "unknown")))]
    {
        let _ = (cmd, payload);
        Err(JsValue::from_str("storage worker is wasm-only"))
    }
}
