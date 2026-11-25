//! SQLite 接入 spike（阶段一脚手架，阶段二丢弃）。
//!
//! 只证三件事：rusqlite 0.40 + ffi-sqlite-wasm-rs 能编进 wasm；
//! Dedicated Worker 内以 SAHPool VFS（OPFS 同步句柄池）开库、
//! 建表、写入、查询、FTS5 trigram 中文检索；整页重载后数据仍在。
//! 不接任何业务路径（不碰 idb.rs / mynote-storage 的 Store）。

use wasm_bindgen::prelude::*;

#[cfg(all(target_family = "wasm", target_os = "unknown", feature = "sqlite"))]
mod imp {
    use rusqlite::{params, Connection};
    use serde_json::json;
    use sqlite_wasm_rs as ffi;
    use sqlite_wasm_vfs::sahpool::{install as install_opfs_sahpool, OpfsSAHPoolCfg};

    const DB_NAME: &str = "spike.db";

    async fn ensure_pool() -> Result<(), String> {
        // install 返回池管理句柄（Worker 限定、非 Sync），
        // 存 thread_local 保活（spike 期间不卸载）。
        thread_local! {
            static POOL: std::cell::RefCell<
                Option<sqlite_wasm_vfs::sahpool::OpfsSAHPoolUtil>,
            > = const { std::cell::RefCell::new(None) };
        }
        let installed = POOL.with(|p| p.borrow().is_some());
        if !installed {
            let util = install_opfs_sahpool::<ffi::WasmOsCallback>(
                &OpfsSAHPoolCfg::default(),
                true,
            )
            .await
            .map_err(|e| format!("sahpool install failed: {e}"))?;
            POOL.with(|p| *p.borrow_mut() = Some(util));
        }
        Ok(())
    }

    fn open() -> Result<Connection, String> {
        Connection::open(DB_NAME).map_err(|e| format!("open {DB_NAME}: {e}"))
    }

    fn schema(conn: &Connection) -> Result<(), String> {
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS memos(
                 id INTEGER PRIMARY KEY,
                 title TEXT NOT NULL,
                 body TEXT NOT NULL
             );
             CREATE VIRTUAL TABLE IF NOT EXISTS memos_fts
                 USING fts5(title, body, tokenize='trigram');",
        )
        .map_err(|e| format!("schema: {e}"))
    }

    fn has_tables(conn: &Connection) -> Result<bool, String> {
        let n: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name IN ('memos','memos_fts')",
                [],
                |r| r.get(0),
            )
            .map_err(|e| format!("probe tables: {e}"))?;
        Ok(n == 2)
    }

    fn snapshot(conn: &Connection) -> Result<serde_json::Value, String> {
        let count: i64 = conn
            .query_row("SELECT count(*) FROM memos", [], |r| r.get(0))
            .map_err(|e| format!("count: {e}"))?;
        let mut stmt = conn
            .prepare("SELECT id, title, body FROM memos ORDER BY id")
            .map_err(|e| format!("prepare rows: {e}"))?;
        let rows = stmt
            .query_map([], |row| {
                Ok(json!({
                    "id": row.get::<_, i64>(0)?,
                    "title": row.get::<_, String>(1)?,
                    "body": row.get::<_, String>(2)?,
                }))
            })
            .map_err(|e| format!("query rows: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("collect rows: {e}"))?;
        // 中文子串检索：正文含「中文全文检索」，查 3 字 trigram「文检索」。
        let mut fstmt = conn
            .prepare("SELECT title FROM memos_fts WHERE memos_fts MATCH ?1 ORDER BY rowid")
            .map_err(|e| format!("prepare fts: {e}"))?;
        let hits = fstmt
            .query_map(params!["\"文检索\""], |row| row.get::<_, String>(0))
            .map_err(|e| format!("fts query: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("collect fts: {e}"))?;
        Ok(json!({
            "sqlite_version": rusqlite::version(),
            "count": count,
            "rows": rows,
            "fts_query": "文检索",
            "fts_hits": hits,
        }))
    }

    pub async fn write(tag: String, body: String) -> Result<String, String> {
        ensure_pool().await?;
        let conn = open()?;
        schema(&conn)?;
        conn.execute(
            "INSERT INTO memos(title, body) VALUES (?1, ?2)",
            params![tag, body],
        )
        .map_err(|e| format!("insert memos: {e}"))?;
        conn.execute(
            "INSERT INTO memos_fts(title, body) VALUES (?1, ?2)",
            params![tag, body],
        )
        .map_err(|e| format!("insert fts: {e}"))?;
        let snap = snapshot(&conn)?;
        Ok(snap.to_string())
    }

    pub async fn read() -> Result<String, String> {
        ensure_pool().await?;
        let conn = open()?;
        if !has_tables(&conn)? {
            return Ok(json!({
                "sqlite_version": rusqlite::version(),
                "exists": false,
                "count": 0,
                "rows": [],
                "fts_query": "文检索",
                "fts_hits": [],
            })
            .to_string());
        }
        let mut snap = snapshot(&conn)?;
        snap["exists"] = json!(true);
        Ok(snap.to_string())
    }
}

#[cfg(all(target_family = "wasm", target_os = "unknown", feature = "sqlite"))]
use imp::{read as imp_read, write as imp_write};

#[cfg(not(all(target_family = "wasm", target_os = "unknown", feature = "sqlite")))]
async fn imp_write(_tag: String, _body: String) -> Result<String, String> {
    Ok("{\"error\":\"sqlite feature off (baseline build)\"}".to_string())
}

#[cfg(not(all(target_family = "wasm", target_os = "unknown", feature = "sqlite")))]
async fn imp_read() -> Result<String, String> {
    Ok("{\"error\":\"sqlite feature off (baseline build)\"}".to_string())
}

/// 在 Worker 内建表并写入一条备忘（标题=tag，正文=body），
/// 返回写入后的全量快照 JSON（含 FTS 检索结果）。
#[wasm_bindgen]
pub async fn spike_write(tag: String, body: String) -> Result<String, JsValue> {
    imp_write(tag, body).await.map_err(JsValue::from)
}

/// 在 Worker 内开库读回全部行与 FTS 检索结果，返回 JSON。
/// 库不存在时返回 exists=false，不建表（读路径不产生副作用）。
#[wasm_bindgen]
pub async fn spike_read() -> Result<String, JsValue> {
    imp_read().await.map_err(JsValue::from)
}
