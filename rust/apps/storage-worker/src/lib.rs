//! Mynote 存储 Worker（SQLite 接入阶段二）：Dedicated
//! Worker 内以 SAHPool VFS（OPFS 同步句柄池）承载
//! moment-storage 的 Store 本体，主线程经 postMessage
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

use moment_core::BackupFile;
use moment_storage::{fnv1a_64, library_hash, Store};
use serde_json::{json, Value};
use wasm_bindgen::prelude::*;

const DB_NAME: &str = "moment.db";
/// 改名前旧库文件名（2026-11-26 改名批 2）：仅作存量池
/// 搬运来源，搬运校验通过即从旧池删除（见 migrate_pool）。
const LEGACY_DB_NAME: &str = "mynote.db";

/// install 失败的结构化分类（步位 + DOMException 名/原文）：
/// 步位是主线程分流的唯一判据——handle 步（createSyncAccess
/// Handle）= 真锁冲突（另一标签持有同池句柄）；其余步位 =
/// 本上下文存储不可用（无痕/易失会话在 directory 步被
/// WebKit 政策性拒绝为其典型形态）。分类直接按
/// OpfsSAHError 变体取步位，不经 Display 文案匹配（Display
/// 是固定话术、且会丢弃内含 DOMException 的 name/message，
/// 此处从 JsValue 本体提取）。
#[cfg(all(target_family = "wasm", target_os = "unknown"))]
struct InstallFailure {
    step: &'static str,
    err_name: String,
    err_msg: String,
}

#[cfg(all(target_family = "wasm", target_os = "unknown"))]
fn dom_exc_info(v: &JsValue) -> (String, String) {
    let get = |k: &str| {
        js_sys::Reflect::get(v, &JsValue::from_str(k))
            .ok()
            .and_then(|x| x.as_string())
            .unwrap_or_default()
    };
    let name = get("name");
    let msg = get("message");
    if name.is_empty() && msg.is_empty() {
        // 非 DOMException 形态（字符串/普通对象）：整体串化兜底。
        let s = v
            .as_string()
            .unwrap_or_else(|| format!("{v:?}"));
        (String::new(), s)
    } else {
        (name, msg)
    }
}

#[cfg(all(target_family = "wasm", target_os = "unknown"))]
fn classify_install_error(
    e: &sqlite_wasm_vfs::sahpool::OpfsSAHError,
) -> InstallFailure {
    use sqlite_wasm_vfs::sahpool::OpfsSAHError as E;
    let (step, val): (&'static str, Option<&JsValue>) = match e {
        E::GetDirHandle(v) => ("directory", Some(v)),
        E::CreateSyncAccessHandle(v) => ("handle", Some(v)),
        E::GetFileHandle(v) => ("file", Some(v)),
        E::Vfs(_) => ("register", None),
        E::NotSupported => ("unsupported", None),
        E::ImportDb(_) => ("import", None),
        E::IterHandle(v) => ("other", Some(v)),
        E::GetPath(v) => ("other", Some(v)),
        E::RemoveEntity(v) => ("other", Some(v)),
        E::GetSize(v) => ("other", Some(v)),
        E::Read(v) => ("other", Some(v)),
        E::Write(v) => ("other", Some(v)),
        E::Flush(v) => ("other", Some(v)),
        E::Truncate(v) => ("other", Some(v)),
        E::Reflect(v) => ("other", Some(v)),
        E::Generic(_) => ("other", None),
    };
    let (err_name, err_msg) = match val {
        Some(v) => dom_exc_info(v),
        None => (String::new(), format!("{e}")),
    };
    InstallFailure { step, err_name, err_msg }
}

#[cfg(all(target_family = "wasm", target_os = "unknown"))]
impl InstallFailure {
    /// 分流状态：handle 步 → occupied；其余步 → unavailable。
    fn status(&self) -> &'static str {
        if self.step == "handle" {
            "occupied"
        } else {
            "unavailable"
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "status": self.status(),
            "step": self.step,
            "err_name": self.err_name,
            "err_msg": self.err_msg,
        })
    }
}

#[cfg(all(target_family = "wasm", target_os = "unknown"))]
mod imp {
    use super::*;
    use sqlite_wasm_rs as ffi;
    use sqlite_wasm_vfs::sahpool::{
        install as install_opfs_sahpool, OpfsSAHPoolCfg, OpfsSAHPoolCfgBuilder,
        OpfsSAHPoolUtil,
    };

    thread_local! {
        static POOL: std::cell::RefCell<
            Option<sqlite_wasm_vfs::sahpool::OpfsSAHPoolUtil>,
        > = const { std::cell::RefCell::new(None) };
        static STORE: std::cell::RefCell<Option<Store>> =
            const { std::cell::RefCell::new(None) };
        /// 本 Worker 选定的池身份 (pool, pool_dir)：init 回
        /// 复与 already 回复的 pool/pool_dir 字段来源。
        static POOL_META: std::cell::RefCell<Option<(String, String)>> =
            const { std::cell::RefCell::new(None) };
    }

    fn now_ms() -> f64 {
        js_sys::Date::now()
    }

    /// 池 id 校验（主线程指纹的防御性复核）：[A-Za-z0-9-]
    /// 且长度 1..=32 才认，其余一律回退默认池。
    fn pool_fp_valid(fp: &str) -> bool {
        !fp.is_empty()
            && fp.len() <= 32
            && fp.bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
    }

    /// 新名默认池（2026-11-26 改名批 2）。
    const NEW_DEFAULT: (&str, &str) = ("opfs-moment", ".opfs-moment");

    /// 改名前默认池候选（存量连续性）：(vfs 名, 目录名)。
    /// ① `.opfs-sahpool-default`：现网用户当前库所在——
    /// 主线程写回的池 id "default" 此前被当作指纹拼后缀
    /// （映射错误），现网池实际是这个后缀目录而非 crate
    /// 默认目录；② crate 默认 `.opfs-sahpool`：指纹机制
    /// 上线前（阶段三窗口期）的库所在。改名解析依次探
    /// 两池、先探到的有库者整池搬运到新名池（见
    /// resolve_default_pool / migrate_pool）。
    const LEGACY_DEFAULT_CANDIDATES: [(&str, &str); 2] = [
        ("opfs-sahpool-default", ".opfs-sahpool-default"),
        ("opfs-sahpool", ".opfs-sahpool"),
    ];

    fn cfg_for(vfs_name: &str, directory: &str) -> OpfsSAHPoolCfg {
        OpfsSAHPoolCfgBuilder::new()
            .vfs_name(vfs_name)
            .directory(directory)
            .build()
    }

    enum PoolInstall {
        Ready {
            pool: String,
            pool_dir: String,
            /// 本次 init 发生了改名搬运时为旧池目录名，
            /// 随 ready 回复带回主线程记 Diag。
            renamed_from: Option<String>,
        },
        Failed(InstallFailure),
    }

    fn set_pool(util: OpfsSAHPoolUtil, pool: &str, pool_dir: &str) {
        POOL.with(|p| *p.borrow_mut() = Some(util));
        POOL_META.with(|m| {
            *m.borrow_mut() = Some((pool.to_string(), pool_dir.to_string()));
        });
    }

    /// 以默认 VFS 身份安装选定池并置 POOL/POOL_META。
    async fn install_chosen(
        cfg: &OpfsSAHPoolCfg,
        pool: &str,
        pool_dir: &str,
        renamed_from: Option<String>,
    ) -> PoolInstall {
        match install_opfs_sahpool::<ffi::WasmOsCallback>(cfg, true).await {
            Ok(util) => {
                set_pool(util, pool, pool_dir);
                PoolInstall::Ready {
                    pool: pool.to_string(),
                    pool_dir: pool_dir.to_string(),
                    renamed_from,
                }
            }
            Err(e) => PoolInstall::Failed(classify_install_error(&e)),
        }
    }

    /// 探池（指定库文件名）：以非默认 VFS 安装候选池、
    /// 读 has_library 后 pause 释放全部句柄（不留占用）。
    /// 只读 meta——Store 打开仅走 SCHEMA 的 IF NOT EXISTS
    /// 幂等建表，不重归一、不写任何戳，探池不污染对账/
    /// 迁移状态。Ok(true) = 有库（迁移戳在位或
    /// has_library=1，与 cmd_load_all 的 has_library 同
    /// 口径）；池内从未开过库（无 db 文件）直接判无库，
    /// 不打开免凭空建文件。
    async fn probe_pool(cfg: &OpfsSAHPoolCfg, db_name: &str) -> Result<bool, InstallFailure> {
        let util = install_opfs_sahpool::<ffi::WasmOsCallback>(cfg, false)
            .await
            .map_err(|e| classify_install_error(&e))?;
        let has = pool_has_library(&util, cfg, db_name);
        // 探毕释放：pause 注销 VFS 并放掉全部同步句柄，
        // 未选中的池不留占用、选中者随后以默认身份重装。
        let _ = util.pause_vfs();
        has
    }

    fn pool_has_library(
        util: &OpfsSAHPoolUtil,
        cfg: &OpfsSAHPoolCfg,
        db_name: &str,
    ) -> Result<bool, InstallFailure> {
        match util.exists(db_name) {
            Ok(true) => {}
            Ok(false) => return Ok(false),
            Err(e) => return Err(classify_install_error(&e)),
        }
        let store = Store::open_with_vfs(Path::new(db_name), &cfg.vfs_name).map_err(|e| {
            InstallFailure {
                step: "open",
                err_name: String::new(),
                err_msg: format!("{e}"),
            }
        })?;
        let has = store
            .get_meta("migration_stamp")
            .map(|s| s.is_some())
            .unwrap_or(false)
            || store
                .get_meta("has_library")
                .map(|v| v.as_deref() == Some("1"))
                .unwrap_or(false);
        Ok(has)
    }

    /// 整池改名搬运：旧池 mynote.db 的原始文件字节经
    /// export_db 搬到新池、改名 moment.db 落盘（import_db）
    /// ——字节级搬运，库内容/迁移戳/has_library 逐字不变。
    /// 校验 = 两池篇数与 memo_hashes 聚合哈希逐项相等；
    /// 通过才删旧池的库文件。任一步失败回 Err（旧池原样
    /// 保留、下次启动重试），两池 util 均 pause 释放。
    async fn migrate_pool(
        legacy_cfg: &OpfsSAHPoolCfg,
        new_cfg: &OpfsSAHPoolCfg,
    ) -> Result<(), InstallFailure> {
        let legacy_util = install_opfs_sahpool::<ffi::WasmOsCallback>(legacy_cfg, false)
            .await
            .map_err(|e| classify_install_error(&e))?;
        let outcome = migrate_pool_with(&legacy_util, legacy_cfg, new_cfg).await;
        let _ = legacy_util.pause_vfs();
        outcome
    }

    async fn migrate_pool_with(
        legacy_util: &OpfsSAHPoolUtil,
        legacy_cfg: &OpfsSAHPoolCfg,
        new_cfg: &OpfsSAHPoolCfg,
    ) -> Result<(), InstallFailure> {
        let open_err = |e: moment_storage::StoreError| InstallFailure {
            step: "open",
            err_name: String::new(),
            err_msg: format!("{e}"),
        };
        let legacy_store =
            Store::open_with_vfs(Path::new(LEGACY_DB_NAME), &legacy_cfg.vfs_name)
                .map_err(open_err)?;
        let legacy_count = legacy_store.memo_count().map_err(open_err)?;
        let legacy_hash = library_hash(&legacy_store.memo_hashes().map_err(open_err)?);
        drop(legacy_store);
        let bytes = legacy_util
            .export_db(LEGACY_DB_NAME)
            .map_err(|e| classify_install_error(&e))?;
        let new_util = install_opfs_sahpool::<ffi::WasmOsCallback>(new_cfg, false)
            .await
            .map_err(|e| classify_install_error(&e))?;
        let result = (|| -> Result<(), InstallFailure> {
            if new_util
                .exists(DB_NAME)
                .map_err(|e| classify_install_error(&e))?
            {
                // 新池已有同名文件（中断残留的空库等）：先删再导入。
                new_util
                    .delete_db(DB_NAME)
                    .map_err(|e| classify_install_error(&e))?;
            }
            new_util
                .import_db(DB_NAME, &bytes)
                .map_err(|e| classify_install_error(&e))?;
            let new_store =
                Store::open_with_vfs(Path::new(DB_NAME), &new_cfg.vfs_name).map_err(open_err)?;
            let new_count = new_store.memo_count().map_err(open_err)?;
            let new_hash = library_hash(&new_store.memo_hashes().map_err(open_err)?);
            if new_count != legacy_count || new_hash != legacy_hash {
                return Err(InstallFailure {
                    step: "open",
                    err_name: String::new(),
                    err_msg: "rename migration verify mismatch".to_string(),
                });
            }
            Ok(())
        })();
        let _ = new_util.pause_vfs();
        result?;
        legacy_util
            .delete_db(LEGACY_DB_NAME)
            .map_err(|e| classify_install_error(&e))?;
        Ok(())
    }

    /// 默认池解析（pool="default"/缺失/非法指纹的落点，
    /// "default" 在此显式特判、不再当指纹拼后缀）：
    /// ① 先探新名池——有库即用（改名已完成态），并顺手
    /// 清理仍带库的旧名池（上次搬运删尾失败的残留）；
    /// ② 新名无库 → 依次探旧名候选，先探到的有库者整池
    /// 搬运到新名池（migrate_pool）后用新名池；
    /// ③ 皆无库 → 新名池开新库。
    /// 任一 install 失败即按分类收口（handle 步 = 该池正
    /// 被另一标签持有，被持有即占用正解；directory 步 =
    /// OPFS 整体不可用），不继续探。
    async fn resolve_default_pool() -> PoolInstall {
        let new_cfg = cfg_for(NEW_DEFAULT.0, NEW_DEFAULT.1);
        match probe_pool(&new_cfg, DB_NAME).await {
            Ok(true) => {
                cleanup_legacy_defaults().await;
                return install_chosen(&new_cfg, "default", NEW_DEFAULT.1, None).await;
            }
            Ok(false) => {}
            Err(f) => return PoolInstall::Failed(f),
        }
        for (vfs, dir) in LEGACY_DEFAULT_CANDIDATES {
            let legacy_cfg = cfg_for(vfs, dir);
            match probe_pool(&legacy_cfg, LEGACY_DB_NAME).await {
                Ok(true) => {
                    return match migrate_pool(&legacy_cfg, &new_cfg).await {
                        Ok(()) => {
                            install_chosen(
                                &new_cfg,
                                "default",
                                NEW_DEFAULT.1,
                                Some(dir.to_string()),
                            )
                            .await
                        }
                        Err(f) => PoolInstall::Failed(f),
                    };
                }
                Ok(false) => {}
                Err(f) => return PoolInstall::Failed(f),
            }
        }
        install_chosen(&new_cfg, "default", NEW_DEFAULT.1, None).await
    }

    /// 旧名默认池残留清理（新名池已探得有库后调用）：旧
    /// 候选池若仍带 mynote.db（搬运删尾失败等），装池删
    /// 其库文件。全程尽力而为——装池失败（被他标签持有
    /// 等）即跳过，不影响已就绪的新名池。
    async fn cleanup_legacy_defaults() {
        for (vfs, dir) in LEGACY_DEFAULT_CANDIDATES {
            let cfg = cfg_for(vfs, dir);
            if let Ok(util) = install_opfs_sahpool::<ffi::WasmOsCallback>(&cfg, false).await {
                if util.exists(LEGACY_DB_NAME).unwrap_or(false) {
                    let _ = util.delete_db(LEGACY_DB_NAME);
                }
                let _ = util.pause_vfs();
            }
        }
    }

    /// 池安装总入口：指纹池直接以默认身份安装；默认池走
    /// resolve_default_pool 探用。本 Worker 生命周期内池
    /// 身份只定一次（POOL 在位即短路回既定身份）。
    async fn ensure_pool(raw: Option<&str>) -> PoolInstall {
        if POOL.with(|p| p.borrow().is_some()) {
            let (pool, pool_dir) = POOL_META
                .with(|m| m.borrow().clone())
                .unwrap_or_else(|| ("default".to_string(), ".opfs-moment".to_string()));
            return PoolInstall::Ready {
                pool,
                pool_dir,
                renamed_from: None,
            };
        }
        let fp = raw
            .filter(|s| *s != "default")
            .filter(|s| pool_fp_valid(s));
        match fp {
            Some(fp) => {
                // 指纹池同走改名解析：新名池有库即用；旧名
                // 池有库则整池搬运；皆无库新名池开新库。
                let new_dir = format!(".opfs-moment-{fp}");
                let new_cfg = cfg_for(&format!("opfs-moment-{fp}"), &new_dir);
                match probe_pool(&new_cfg, DB_NAME).await {
                    Ok(true) => install_chosen(&new_cfg, fp, &new_dir, None).await,
                    Ok(false) => {
                        let legacy_dir = format!(".opfs-sahpool-{fp}");
                        let legacy_cfg =
                            cfg_for(&format!("opfs-sahpool-{fp}"), &legacy_dir);
                        match probe_pool(&legacy_cfg, LEGACY_DB_NAME).await {
                            Ok(true) => match migrate_pool(&legacy_cfg, &new_cfg).await {
                                Ok(()) => {
                                    install_chosen(
                                        &new_cfg,
                                        fp,
                                        &new_dir,
                                        Some(legacy_dir),
                                    )
                                    .await
                                }
                                Err(f) => PoolInstall::Failed(f),
                            },
                            Ok(false) => install_chosen(&new_cfg, fp, &new_dir, None).await,
                            Err(f) => PoolInstall::Failed(f),
                        }
                    }
                    Err(f) => PoolInstall::Failed(f),
                }
            }
            None => resolve_default_pool().await,
        }
    }

    /// 开库（含 SAHPool 安装与开库整库重归一）。install
    /// 失败回结构化分类（见 classify_install_error）：
    /// status=occupied 仅当失败在 handle 步（真锁冲突），
    /// 其余步位 status=unavailable（本上下文存储不可用，
    /// 主线程据此分流会话降级/阻断，不再无限等待接管）。
    /// 池分区（payload.pool）：合法指纹用后缀目录的独立
    /// 池（浏览器分区边界对齐）；"default"/缺失/非法走默
    /// 认池探用解析（存量连续性，见 resolve_default_pool）。
    async fn cmd_init(payload: &JsValue) -> Result<Value, String> {
        if STORE.with(|s| s.borrow().is_some()) {
            let (pool, pool_dir) = POOL_META
                .with(|m| m.borrow().clone())
                .unwrap_or_else(|| ("default".to_string(), ".opfs-moment".to_string()));
            return Ok(json!({
                "status": "ready",
                "already": true,
                "pool": pool,
                "pool_dir": pool_dir,
            }));
        }
        let raw_pool = js_sys::Reflect::get(payload, &JsValue::from_str("pool"))
            .ok()
            .and_then(|v| v.as_string());
        let (pool, pool_dir, renamed_from) = match ensure_pool(raw_pool.as_deref()).await {
            PoolInstall::Ready {
                pool,
                pool_dir,
                renamed_from,
            } => (pool, pool_dir, renamed_from),
            PoolInstall::Failed(f) => return Ok(f.to_json()),
        };
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
        let mut reply = json!({
            "status": "ready",
            "memos": memos,
            "migrated": migrated,
            "renormalized": renormalized,
            "pool": pool,
            "pool_dir": pool_dir,
        });
        if let Some(from) = renamed_from {
            reply["renamed_from"] = json!(from);
        }
        Ok(reply)
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
                            .map(|doc| moment_core::migrate::count_nodes_value(doc))
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
        let stats = moment_core::normalize_value(&mut raw);
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

    fn cmd_memo_hashes() -> Result<Value, String> {
        let t0 = now_ms();
        with_store(|store| {
            let pairs = store.memo_hashes().map_err(|e| format!("hashes: {e}"))?;
            // u64 超出 JS 安全整数：哈希一律十进制字符串回传，
            // 桥侧 JSON 往返不丢精度（对账口径见 persist）。
            let mut map = serde_json::Map::with_capacity(pairs.len());
            for (id, h) in pairs {
                map.insert(id, Value::String(h.to_string()));
            }
            Ok(json!({ "hashes": Value::Object(map), "ms": now_ms() - t0 }))
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
            "init" => cmd_init(payload).await,
            "migration_status" => with_store(|store| {
                let stamp = store
                    .get_meta("migration_stamp")
                    .map_err(|e| format!("stamp: {e}"))?;
                let has_library = store
                    .get_meta("has_library")
                    .map_err(|e| format!("has_library: {e}"))?;
                // done 语义（阶段三）：迁移戳在位，或库已由
                // 导入/保存路径建立（has_library）——后者同
                // 为「迁移已无待办」状态，避免种子首存后次
                // 启把自有库再当存量迁一遍。
                Ok(json!({
                    "done": stamp.is_some() || has_library.as_deref() == Some("1"),
                    "stamp": stamp,
                    "has_library": has_library,
                }))
            }),
            "memo_hashes" => cmd_memo_hashes(),
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
