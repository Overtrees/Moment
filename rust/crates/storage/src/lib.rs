//! Mynote 存储层：SQLite 本地库 + 备份 ZIP 导入/导出。
//!
//! 设计要点（阶段 1）：
//! - 每条备忘以完整 JSON 原样入库（memo_json），另抽索引列
//!   （标题/置顶/时间/纯文本）供列表与检索——导出保真由原样
//!   JSON 保证，查询性能由索引列保证，两者不互相妥协。
//! - 备份导入沿用原版语义：先完整解析校验，再单事务全量替换。
//! - 检索用 FTS5 trigram，对中文做子串匹配（与现行子串检索
//!   语义一致）；trigram 要求查询至少 3 个字符，短查询回退
//!   LIKE 子串扫描。

use std::collections::BTreeMap;
use std::path::Path;

use mynote_core::{BackupFile, Memo, Timestamp};
use rusqlite::{params, Connection};

pub struct Store {
    conn: Connection,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ImportStats {
    pub memos: usize,
    pub attachments: usize,
}

#[derive(Debug)]
pub enum StoreError {
    Sqlite(rusqlite::Error),
    Json(serde_json::Error),
    Backup(mynote_core::BackupZipError),
    Io(std::io::Error),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StoreError::Sqlite(e) => write!(f, "sqlite: {e}"),
            StoreError::Json(e) => write!(f, "json: {e}"),
            StoreError::Backup(e) => write!(f, "backup: {e}"),
            StoreError::Io(e) => write!(f, "io: {e}"),
        }
    }
}
impl std::error::Error for StoreError {}
impl From<rusqlite::Error> for StoreError {
    fn from(e: rusqlite::Error) -> Self {
        StoreError::Sqlite(e)
    }
}
impl From<serde_json::Error> for StoreError {
    fn from(e: serde_json::Error) -> Self {
        StoreError::Json(e)
    }
}
impl From<mynote_core::BackupZipError> for StoreError {
    fn from(e: mynote_core::BackupZipError) -> Self {
        StoreError::Backup(e)
    }
}
impl From<std::io::Error> for StoreError {
    fn from(e: std::io::Error) -> Self {
        StoreError::Io(e)
    }
}

pub type Result<T> = std::result::Result<T, StoreError>;

/// 写路径归一的版本戳（SQLite 接入方案 (b)：归一只在写入
/// 路径——导入/迁移/保存——发生，库内以 meta
/// `normalize_version` 记录已归一到的版本；开库时戳低于
/// 本值即先整库归一再用）。归一规则（core::migrate）发生
/// 不兼容变更时递增此值，旧库在下次开库时自动整库重归一。
pub const NORMALIZE_VERSION: u32 = 1;

/// FNV-1a 64 位哈希（对账专用，非安全用途）：跨进程/跨
/// 语言可复算（JS 侧探针以同算法独立核验），供迁移对账
/// 的逐篇内容哈希与全库聚合哈希使用。
pub fn fnv1a_64(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        h ^= *b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// 全库聚合哈希：逐篇 (id, memo_json 哈希）按 id 排序后
/// 再 FNV 串联——顺序无关、内容敏感，对账两侧同口径。
pub fn library_hash(per_memo: &[(String, u64)]) -> u64 {
    let mut sorted: Vec<&(String, u64)> = per_memo.iter().collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    let mut buf = Vec::new();
    for (id, h) in sorted {
        buf.extend_from_slice(id.as_bytes());
        buf.push(0);
        buf.extend_from_slice(&h.to_le_bytes());
    }
    fnv1a_64(&buf)
}

/// sync_library 的差量统计（阶段二保存路径：全量快照入、
/// 单行差量落库）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SyncStats {
    pub upserted: usize,
    pub deleted: usize,
    pub unchanged: usize,
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS memos (
    id_json    TEXT PRIMARY KEY,
    id_text    TEXT NOT NULL,
    title      TEXT,
    pinned     INTEGER NOT NULL DEFAULT 0,
    created_ms INTEGER,
    updated_ms INTEGER,
    plain_text TEXT NOT NULL,
    memo_json  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS attachments (
    id   TEXT PRIMARY KEY,
    data BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS memos_fts USING fts5(
    id UNINDEXED, title, content, tokenize='trigram'
);
";

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)?;
        Self::init(conn)
    }

    /// 显式 VFS 打开（存储 Worker 探池专用）：默认 VFS 归
    /// 最终选定的池，探池阶段逐个候选池以其 VFS 名打开读
    /// 元信息（has_library/篇数），不触碰默认 VFS 归属。
    pub fn open_with_vfs(path: &Path, vfs: &str) -> Result<Self> {
        let conn = Connection::open_with_flags_and_vfs(
            path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE | rusqlite::OpenFlags::SQLITE_OPEN_CREATE,
            vfs,
        )?;
        Self::init(conn)
    }

    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        Self::init(conn)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.execute_batch(SCHEMA)?;
        Ok(Store { conn })
    }

    /// 全量替换式导入一个备份 ZIP（原版恢复语义）：先把包内
    /// 全部内容解析校验完毕，再在单个事务里换库，坏包不污染
    /// 现有数据。
    pub fn import_backup(&mut self, zip_path: &Path) -> Result<ImportStats> {
        // 包的解析校验全在 core 的迁移通道读里完成（含
        // manifest 结构校验与体积上限、旧形态归一）；这里拿到
        // 的是已校验的完整包，之后只剩单事务换库。
        let bytes = std::fs::read(zip_path)?;
        let (pkg, _mig) = mynote_core::read_backup_zip_migrated(&bytes)?;
        self.apply_package(&pkg, true)
    }

    /// 从字节导入备份 ZIP（Worker 桥与演练台用）：校验与
    /// 落库口径与 import_backup 完全一致（core 迁移通道读
    /// + 单事务全量替换），只差输入形态与附件落点选择。
    /// `store_attachments=false` 时附件不入 SQLite（Web 端
    /// 附件留文件式存储的口径，见阶段二报告），统计仍按
    /// 包内附件数报。
    pub fn import_backup_bytes(
        &mut self,
        bytes: &[u8],
        store_attachments: bool,
    ) -> Result<(ImportStats, mynote_core::MigrationStats)> {
        let (pkg, mig) = mynote_core::read_backup_zip_migrated(bytes)?;
        let stats = self.apply_package(&pkg, store_attachments)?;
        Ok((stats, mig))
    }

    /// 已校验包的单事务全量替换（import_backup 与
    /// import_backup_bytes 共用）：清库 → 逐篇插入 →
    /// （可选）附件入库 → manifest/avatars 落 meta →
    /// 归一版本戳落 meta，同事务提交。
    fn apply_package(
        &mut self,
        pkg: &mynote_core::BackupPackage,
        store_attachments: bool,
    ) -> Result<ImportStats> {
        let backup = &pkg.backup;
        let attachments = &pkg.attachments;

        let stats = ImportStats {
            memos: backup.memos.len(),
            attachments: attachments.len(),
        };

        let tx = self.conn.transaction()?;
        tx.execute_batch(
            "DELETE FROM memos; DELETE FROM attachments; DELETE FROM memos_fts;",
        )?;
        for memo in &backup.memos {
            Self::insert_memo(&tx, memo)?;
        }
        if store_attachments {
            for (id, data) in attachments {
                tx.execute(
                    "INSERT INTO attachments (id, data) VALUES (?1, ?2)",
                    params![id, data],
                )?;
            }
        }
        // manifest 存模型序列化（原生形，第五步建模）：库里
        // 从此只有原生形，导出直读直写、不再存原文。
        tx.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('manifest_json', ?1)",
            params![serde_json::to_string(&pkg.manifest)?],
        )?;
        let avatars_json = backup
            .avatars
            .as_ref()
            .map(|a| a.to_string())
            .unwrap_or_else(|| "null".to_string());
        tx.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('avatars_json', ?1)",
            params![avatars_json],
        )?;
        Self::set_meta_tx(&tx, "normalize_version", &NORMALIZE_VERSION.to_string())?;
        tx.commit()?;
        Ok(stats)
    }

    fn insert_memo(conn: &Connection, memo: &Memo) -> Result<()> {
        // prepare_cached（Lane T 实测）：导入是逐条插入的批量路径，
        // conn.execute 每条都重新 prepare 语句，语句缓存后复用。
        // FTS 不再逐条先 DELETE 再 INSERT（同实测）：trigram FTS5
        // 的逐行删除占了导入总耗时约八成（1000 篇 195ms→40ms）；
        // 唯一调用方 import_backup 在同一事务里先全量清空
        // memos_fts，故此处 FTS 必无该 id 的旧行，前置条件成立。
        let id_json = serde_json::to_string(&memo.id)?;
        let id_text = memo.id.to_string();
        let plain = memo.plain_text();
        conn.prepare_cached(
            "INSERT OR REPLACE INTO memos
             (id_json, id_text, title, pinned, created_ms, updated_ms, plain_text, memo_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        )?
        .execute(params![
            id_json,
            id_text,
            memo.title,
            memo.pinned.unwrap_or(false) as i64,
            memo.created_at.to_millis(),
            memo.updated_at.to_millis(),
            plain,
            serde_json::to_string(memo)?,
        ])?;
        conn.prepare_cached(
            "INSERT INTO memos_fts (id, title, content) VALUES (?1, ?2, ?3)",
        )?
        .execute(params![
            id_text,
            memo.title.clone().unwrap_or_default(),
            plain
        ])?;
        Ok(())
    }

    /// 列表顺序与现行应用一致：置顶在前，其余按更新时间倒序。
    pub fn list_memos(&self) -> Result<Vec<Memo>> {
        let mut stmt = self.conn.prepare(
            "SELECT memo_json FROM memos ORDER BY pinned DESC, updated_ms DESC",
        )?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(serde_json::from_str(&row?)?);
        }
        Ok(out)
    }

    pub fn memo_count(&self) -> Result<usize> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM memos", [], |r| r.get::<_, i64>(0))?
            as usize)
    }

    pub fn attachment_count(&self) -> Result<usize> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM attachments",
            [],
            |r| r.get::<_, i64>(0),
        )? as usize)
    }

    /// 子串检索（标题 + 正文）：≥3 字符走 FTS5 trigram 短语
    /// 查询；更短的查询 FTS 索引不了，回退 LIKE 扫描。返回
    /// 命中的备忘 id（文本形），顺序同列表。
    pub fn search(&self, query: &str) -> Result<Vec<String>> {
        let q = query.trim();
        if q.is_empty() {
            return Ok(Vec::new());
        }
        let ids: Vec<String> = if q.chars().count() >= 3 {
            let phrase = format!("\"{}\"", q.replace('"', "\"\""));
            let mut stmt = self.conn.prepare(
                "SELECT id FROM memos_fts WHERE memos_fts MATCH ?1",
            )?;
            let rows = stmt.query_map(params![phrase], |r| r.get::<_, String>(0))?;
            rows.collect::<std::result::Result<_, _>>()?
        } else {
            let like = format!("%{q}%");
            let mut stmt = self.conn.prepare(
                "SELECT id_text FROM memos
                 WHERE title LIKE ?1 OR plain_text LIKE ?1
                 ORDER BY pinned DESC, updated_ms DESC",
            )?;
            let rows = stmt.query_map(params![like], |r| r.get::<_, String>(0))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        Ok(ids)
    }

    /// 导出备份 ZIP：memos.json（version 2，exportedAt 为导出
    /// 时刻，与原版行为一致）+ manifest.json（模型直出序列化）
    /// + attachments/<id> 原始字节。
    pub fn export_backup(&self, zip_path: &Path) -> Result<()> {
        let memos = self.list_memos_ordered_for_export()?;
        let avatars: Option<serde_json::Value> = self
            .meta("avatars_json")?
            .and_then(|s| serde_json::from_str(&s).ok())
            .filter(|v: &serde_json::Value| !v.is_null());
        let backup = BackupFile {
            version: 2,
            exported_at: Some(Timestamp(
                chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string(),
            )),
            memos,
            avatars,
        };
        // manifest 存量是导入时落下的模型序列化（原生形）；
        // 旧版本写下的原文存量经迁移通道宽容解析兜底。无存
        // 量时为空清单原生形——旧的数组回退字符串
        // （refactor_remove_compat §2.12 双形）随第五步退役。
        let manifest = self
            .meta("manifest_json")?
            .and_then(|s| mynote_core::manifest_parse_lenient(&s))
            .unwrap_or_default();

        let mut attachments: BTreeMap<String, Vec<u8>> = BTreeMap::new();
        {
            let mut stmt = self
                .conn
                .prepare("SELECT id, data FROM attachments ORDER BY id")?;
            let rows = stmt.query_map([], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, Vec<u8>>(1)?))
            })?;
            for row in rows {
                let (id, data) = row?;
                attachments.insert(id, data);
            }
        }
        let bytes = mynote_core::write_backup_zip(&backup, &manifest, &attachments)?;
        std::fs::write(zip_path, bytes)?;
        Ok(())
    }

    /// 导出时备忘按创建时间正序（与原版导出文件里的顺序同类）；
    /// 验收按 id 对齐比较，不依赖此顺序。
    fn list_memos_ordered_for_export(&self) -> Result<Vec<Memo>> {
        let mut stmt = self.conn.prepare(
            "SELECT memo_json FROM memos ORDER BY created_ms ASC",
        )?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(serde_json::from_str(&row?)?);
        }
        Ok(out)
    }

    fn meta(&self, key: &str) -> Result<Option<String>> {
        let mut stmt = self.conn.prepare("SELECT value FROM meta WHERE key = ?1")?;
        let mut rows = stmt.query(params![key])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }

    pub fn get_meta(&self, key: &str) -> Result<Option<String>> {
        self.meta(key)
    }

    pub fn set_meta(&mut self, key: &str, value: &str) -> Result<()> {
        let tx = self.conn.transaction()?;
        Self::set_meta_tx(&tx, key, value)?;
        tx.commit()?;
        Ok(())
    }

    fn set_meta_tx(conn: &Connection, key: &str, value: &str) -> Result<()> {
        conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    }

    /// 单篇写入（FTS 行先删后插——insert_memo 的 FTS 前置
    /// 条件是整表已清，单行路径不成立，故此处独立处理）。
    fn upsert_memo_tx(conn: &Connection, memo: &Memo) -> Result<()> {
        let id_text = memo.id.to_string();
        conn.execute("DELETE FROM memos_fts WHERE id = ?1", params![id_text])?;
        Self::insert_memo(conn, memo)
    }

    /// 单行更新（一篇的新增/修改），自带事务。
    pub fn upsert_memo(&mut self, memo: &Memo) -> Result<()> {
        let tx = self.conn.transaction()?;
        Self::upsert_memo_tx(&tx, memo)?;
        tx.commit()?;
        Ok(())
    }

    /// 单行删除（备忘行 + FTS 行），自带事务。
    pub fn remove_memo(&mut self, id_text: &str) -> Result<()> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM memos WHERE id_text = ?1", params![id_text])?;
        tx.execute("DELETE FROM memos_fts WHERE id = ?1", params![id_text])?;
        tx.commit()?;
        Ok(())
    }

    /// 逐篇内容哈希（id 文本形 → memo_json 的 FNV-1a）：
    /// 迁移对账与差量同步的共同口径。
    pub fn memo_hashes(&self) -> Result<Vec<(String, u64)>> {
        let mut stmt = self.conn.prepare("SELECT id_text, memo_json FROM memos")?;
        let rows = stmt.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, json) = row?;
            out.push((id, fnv1a_64(json.as_bytes())));
        }
        Ok(out)
    }

    /// 差量同步（阶段二保存路径）：应用侧给全量快照，本
    /// 函数按逐篇哈希差量落库——内容未变的篇零写入，变
    /// 化的单行 upsert，快照里消失的删除；avatars 与归一
    /// 版本戳同事务更新。写放大从全库降到变更篇量级。
    pub fn sync_library(&mut self, backup: &BackupFile) -> Result<SyncStats> {
        let existing: std::collections::HashMap<String, u64> =
            self.memo_hashes()?.into_iter().collect();
        let mut stats = SyncStats::default();
        let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
        let tx = self.conn.transaction()?;
        for memo in &backup.memos {
            let id_text = memo.id.to_string();
            seen.insert(id_text.clone());
            let json = serde_json::to_string(memo)?;
            let h = fnv1a_64(json.as_bytes());
            match existing.get(&id_text) {
                Some(&old) if old == h => stats.unchanged += 1,
                _ => {
                    Self::upsert_memo_tx(&tx, memo)?;
                    stats.upserted += 1;
                }
            }
        }
        for id_text in existing.keys() {
            if !seen.contains(id_text) {
                tx.execute("DELETE FROM memos WHERE id_text = ?1", params![id_text])?;
                tx.execute("DELETE FROM memos_fts WHERE id = ?1", params![id_text])?;
                stats.deleted += 1;
            }
        }
        let avatars_json = backup
            .avatars
            .as_ref()
            .map(|a| a.to_string())
            .unwrap_or_else(|| "null".to_string());
        Self::set_meta_tx(&tx, "avatars_json", &avatars_json)?;
        Self::set_meta_tx(&tx, "normalize_version", &NORMALIZE_VERSION.to_string())?;
        tx.commit()?;
        Ok(stats)
    }

    /// 整库替换（导入/迁移共用）：单事务清 memos+FTS →
    /// 逐篇插入 → manifest/avatars/归一戳 + extra_meta 落
    /// meta。附件表不动（Web 口径附件留文件式存储）。
    pub fn replace_library(
        &mut self,
        backup: &BackupFile,
        manifest_json: Option<&str>,
        extra_meta: &[(&str, &str)],
    ) -> Result<()> {
        let tx = self.conn.transaction()?;
        tx.execute_batch("DELETE FROM memos; DELETE FROM memos_fts;")?;
        for memo in &backup.memos {
            Self::insert_memo(&tx, memo)?;
        }
        if let Some(m) = manifest_json {
            Self::set_meta_tx(&tx, "manifest_json", m)?;
        }
        let avatars_json = backup
            .avatars
            .as_ref()
            .map(|a| a.to_string())
            .unwrap_or_else(|| "null".to_string());
        Self::set_meta_tx(&tx, "avatars_json", &avatars_json)?;
        Self::set_meta_tx(&tx, "normalize_version", &NORMALIZE_VERSION.to_string())?;
        for (k, v) in extra_meta {
            Self::set_meta_tx(&tx, k, v)?;
        }
        tx.commit()?;
        Ok(())
    }

    /// 开库整库重归一（方案 (b) 的开库半段）：meta 的
    /// normalize_version 低于 NORMALIZE_VERSION 时，把全
    /// 库以 Value 形态过 core::migrate 归一通道，校验
    /// （篇数守恒）后差量写回并升戳。返回归一通道的变更
    /// 总数（0 = 已是现行版本或归一无变更）。校验不过则
    /// 整笔放弃、原库不动（与加载期归一的 validate-then-
    /// swap 同纪律）。
    pub fn renormalize_library(&mut self) -> Result<usize> {
        let cur: u32 = self
            .meta("normalize_version")?
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        if cur >= NORMALIZE_VERSION {
            return Ok(0);
        }
        let memos = self.list_memos_ordered_for_export()?;
        if memos.is_empty() {
            self.set_meta("normalize_version", &NORMALIZE_VERSION.to_string())?;
            return Ok(0);
        }
        let mut value =
            serde_json::json!({ "version": 2, "memos": serde_json::to_value(&memos)? });
        let stats = mynote_core::normalize_value(&mut value);
        if stats.total_changes() == 0 {
            self.set_meta("normalize_version", &NORMALIZE_VERSION.to_string())?;
            return Ok(0);
        }
        let backup: BackupFile = serde_json::from_value(value)?;
        if backup.memos.len() != memos.len() {
            return Err(StoreError::Json(serde_json::Error::io(
                std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "renormalize validation failed: memo count changed",
                ),
            )));
        }
        self.sync_library(&backup)?;
        Ok(stats.total_changes())
    }
}
