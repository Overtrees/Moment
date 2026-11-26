//! Moment 原生 FFI 缝（UniFFI）：Swift/Kotlin 侧只经本层
//! 调用 Rust Core 与存储层。边界纪律：
//! - 备忘数据一律以 JSON 字符串过界（格式事实源在
//!   moment-core 模型，绑定层不另立模型、不做字段映射）；
//! - 其余只过标量（计数、哈希、路径、查询词）；
//! - 错误统一收敛为 FfiError 的 message 文本。
//!
//! `run_phase0_checks` 是原生阶段 0 的自检链：在给定目录内
//! 走完「建库 → 写入 → 读回 → 中文检索 → 导出 ZIP → 换库
//! 导入 → 哈希对账 → 删除」并返回逐项报告。宿主 cargo test
//! 与真机 app 调同一函数，逻辑只写一份。

use std::path::Path;
use std::sync::{Arc, Mutex};

use moment_core::Memo;
use moment_storage::Store;

uniffi::setup_scaffolding!();

#[derive(Debug, uniffi::Error)]
pub enum FfiError {
    Store { message: String },
    Json { message: String },
}

impl std::fmt::Display for FfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FfiError::Store { message } => write!(f, "store: {message}"),
            FfiError::Json { message } => write!(f, "json: {message}"),
        }
    }
}

impl std::error::Error for FfiError {}

impl From<moment_storage::StoreError> for FfiError {
    fn from(e: moment_storage::StoreError) -> Self {
        FfiError::Store {
            message: e.to_string(),
        }
    }
}

impl From<serde_json::Error> for FfiError {
    fn from(e: serde_json::Error) -> Self {
        FfiError::Json {
            message: e.to_string(),
        }
    }
}

/// 原生侧的库句柄：内部持有一份打开的 Store（互斥保护，
/// UniFFI 对象本身是 Send+Sync 要求）。
#[derive(uniffi::Object)]
pub struct MomentLibrary {
    store: Mutex<Store>,
}

#[uniffi::export]
impl MomentLibrary {
    /// 在 path（.sqlite3 文件路径）打开或新建库。
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Arc<Self>, FfiError> {
        let store = Store::open(Path::new(&path))?;
        Ok(Arc::new(Self {
            store: Mutex::new(store),
        }))
    }

    pub fn memo_count(&self) -> Result<u64, FfiError> {
        let store = self.store.lock().expect("store mutex poisoned");
        Ok(store.memo_count()? as u64)
    }

    /// 全库备忘的 JSON 数组（core 模型序列化形，与 Web 版
    /// 备份/存量同一格式）。
    pub fn list_memos_json(&self) -> Result<String, FfiError> {
        let store = self.store.lock().expect("store mutex poisoned");
        let memos = store.list_memos()?;
        Ok(serde_json::to_string(&memos)?)
    }

    /// 写入一篇备忘（JSON 为 core 模型形，须已归一——原生
    /// 写入方自产规范形；存量旧形走导入通道归一）。
    pub fn upsert_memo_json(&self, json: String) -> Result<(), FfiError> {
        let memo: Memo = serde_json::from_str(&json)?;
        let mut store = self.store.lock().expect("store mutex poisoned");
        store.upsert_memo(&memo)?;
        Ok(())
    }

    pub fn remove_memo(&self, id: String) -> Result<(), FfiError> {
        let mut store = self.store.lock().expect("store mutex poisoned");
        store.remove_memo(&id)?;
        Ok(())
    }

    /// 中文子串检索（FTS5 trigram，短词回退 LIKE），返回
    /// 命中备忘 id 的 JSON 数组。
    pub fn search_ids_json(&self, query: String) -> Result<String, FfiError> {
        let store = self.store.lock().expect("store mutex poisoned");
        let ids = store.search(&query)?;
        Ok(serde_json::to_string(&ids)?)
    }

    /// 导入备份 ZIP（整包校验后单事务替换），返回统计行
    /// `memos=N attachments=M`。
    pub fn import_backup(&self, zip_path: String) -> Result<String, FfiError> {
        let mut store = self.store.lock().expect("store mutex poisoned");
        let stats = store.import_backup(Path::new(&zip_path))?;
        Ok(format!(
            "memos={} attachments={}",
            stats.memos, stats.attachments
        ))
    }

    /// 导出备份 ZIP 到 zip_path（与 Web 版同格式互通）。
    pub fn export_backup(&self, zip_path: String) -> Result<(), FfiError> {
        let store = self.store.lock().expect("store mutex poisoned");
        store.export_backup(Path::new(&zip_path))?;
        Ok(())
    }

    /// 全库聚合哈希（逐篇 FNV-1a 串联，跨端对账口径）。
    pub fn library_hash(&self) -> Result<u64, FfiError> {
        let store = self.store.lock().expect("store mutex poisoned");
        let per_memo = store.memo_hashes()?;
        Ok(moment_storage::library_hash(&per_memo))
    }
}

/// 阶段 0 自检样本：三篇规范形备忘（构造经 core 模型解析，
/// 与真实数据同形）。样本二正文含检索关键词「彩云天气」。
fn sample_memos() -> Result<Vec<Memo>, serde_json::Error> {
    let raw = serde_json::json!([
        {
            "id": "ffi-check-1",
            "title": "原生自检 · 置顶篇",
            "pinned": true,
            "createdAt": "2026-11-26T01:00:00.000Z",
            "updatedAt": "2026-11-26T01:00:00.000Z",
            "doc": [
                { "id": "b1", "type": "heading", "attrs": { "level": 2 },
                  "children": [{ "text": "阶段零自检" }] },
                { "id": "b2", "type": "paragraph",
                  "children": [{ "text": "这篇由 Rust Core 在原生端写入。" }] }
            ]
        },
        {
            "id": "ffi-check-2",
            "title": "原生自检 · 检索篇",
            "createdAt": "2026-11-26T02:00:00.000Z",
            "updatedAt": "2026-11-26T02:00:00.000Z",
            "doc": [
                { "id": "b3", "type": "paragraph",
                  "children": [{ "text": "今天彩云天气有小雨，和风主源、彩云兜底。" }] }
            ]
        },
        {
            "id": "ffi-check-3",
            "title": "原生自检 · 普通篇",
            "createdAt": "2026-11-26T03:00:00.000Z",
            "updatedAt": "2026-11-26T03:00:00.000Z",
            "doc": [
                { "id": "b4", "type": "paragraph",
                  "children": [{ "text": "第三篇样本，供计数与哈希对账。" }] }
            ]
        }
    ]);
    serde_json::from_value(raw)
}

/// 自检记步：Ok 记 ✓ 行（detail 为补充读数），Err 记 ✗ 行
/// 并累加失败数。
fn step(lines: &mut Vec<String>, fails: &mut usize, name: &str, res: Result<String, String>) {
    match res {
        Ok(detail) => lines.push(format!("✓ {name} {detail}")),
        Err(e) => {
            *fails += 1;
            lines.push(format!("✗ {name}: {e}"));
        }
    }
}

/// 原生阶段 0 自检链：在 dir 内建两库走完写入/读回/检索/
/// 导出/导入/对账/删除，逐项记 ✓/✗ 并以末行汇总。任何一
/// 步失败不中断后续独立步（报告完整优先），全过末行
/// `PHASE0 ALL PASS`，否则 `PHASE0 FAILED n`。
#[uniffi::export]
pub fn run_phase0_checks(dir: String) -> String {
    let dir = Path::new(&dir);
    let mut lines: Vec<String> = Vec::new();
    let mut fails: usize = 0;
    // 记步走 step() 显式传 &mut（闭包会独占 lines/fails 的
    // 可变借用、与下面的直写点冲突 E0499；宏的 expr 片段
    // 跟随集又不许 `)` 收尾，故都不用）。
    let attempt = |r: Result<_, moment_storage::StoreError>| {
        r.map(|_| String::new())
            .map_err(|e: moment_storage::StoreError| e.to_string())
    };

    let db1 = dir.join("phase0-a.sqlite3");
    let db2 = dir.join("phase0-b.sqlite3");
    let zip = dir.join("phase0-backup.zip");
    for f in [&db1, &db2, &zip] {
        let _ = std::fs::remove_file(f);
    }

    // 1) 建库 + 写入三篇
    let mut store = match Store::open(&db1) {
        Ok(s) => {
            lines.push("✓ open store A".to_string());
            s
        }
        Err(e) => {
            lines.push(format!("✗ open store A: {e}"));
            lines.push("PHASE0 FAILED open".to_string());
            return lines.join("\n");
        }
    };
    let samples = match sample_memos() {
        Ok(m) => m,
        Err(e) => {
            lines.push(format!("✗ sample memos parse: {e}"));
            lines.push("PHASE0 FAILED sample".to_string());
            return lines.join("\n");
        }
    };
    let mut write = Ok(String::new());
    for m in &samples {
        if let Err(e) = store.upsert_memo(m) {
            write = Err(e.to_string());
            break;
        }
    }
    step(&mut lines, &mut fails, "upsert 3 memos", write);

    // 2) 计数与读回
    step(&mut lines, &mut fails,
        "memo_count == 3",
        match store.memo_count() {
            Ok(3) => Ok(String::new()),
            Ok(n) => Err(format!("got {n}")),
            Err(e) => Err(e.to_string()),
        },
    );
    step(&mut lines, &mut fails,
        "list read-back titles",
        match store.list_memos() {
            Ok(list) => {
                let titles: Vec<String> = list
                    .iter()
                    .filter_map(|m| m.title.clone())
                    .collect();
                if titles.iter().any(|t| t.contains("检索篇"))
                    && titles.iter().any(|t| t.contains("置顶篇"))
                {
                    Ok(format!("({} titles)", titles.len()))
                } else {
                    Err(format!("titles: {titles:?}"))
                }
            }
            Err(e) => Err(e.to_string()),
        },
    );

    // 3) 中文检索（FTS trigram）
    step(&mut lines, &mut fails,
        "search 彩云天气 hits ffi-check-2",
        match store.search("彩云天气") {
            Ok(ids) if ids.iter().any(|i| i == "ffi-check-2") => {
                Ok(format!("({} hits)", ids.len()))
            }
            Ok(ids) => Err(format!("ids: {ids:?}")),
            Err(e) => Err(e.to_string()),
        },
    );

    // 4) 导出 ZIP
    step(&mut lines, &mut fails,
        "export backup zip",
        match store.export_backup(&zip) {
            Ok(()) => match std::fs::metadata(&zip) {
                Ok(md) if md.len() > 0 => Ok(format!("({} bytes)", md.len())),
                Ok(_) => Err("zip empty".to_string()),
                Err(e) => Err(e.to_string()),
            },
            Err(e) => Err(e.to_string()),
        },
    );
    let hash_a = store.memo_hashes().map(|p| moment_storage::library_hash(&p));

    // 5) 换库导入 + 哈希对账
    let mut store_b = match Store::open(&db2) {
        Ok(s) => s,
        Err(e) => {
            lines.push(format!("✗ open store B: {e}"));
            lines.push(format!("PHASE0 FAILED {}", fails + 1));
            return lines.join("\n");
        }
    };
    step(&mut lines, &mut fails,
        "import backup into store B",
        match store_b.import_backup(&zip) {
            Ok(stats) if stats.memos == 3 => {
                Ok(format!("(memos={} attachments={})", stats.memos, stats.attachments))
            }
            Ok(stats) => Err(format!("memos={}", stats.memos)),
            Err(e) => Err(e.to_string()),
        },
    );
    step(&mut lines, &mut fails,
        "library hash A == B",
        match (hash_a, store_b.memo_hashes()) {
            (Ok(ha), Ok(pb)) => {
                let hb = moment_storage::library_hash(&pb);
                if ha == hb {
                    Ok(format!("({ha})"))
                } else {
                    Err(format!("A={ha} B={hb}"))
                }
            }
            (Err(e), _) => Err(e.to_string()),
            (_, Err(e)) => Err(e.to_string()),
        },
    );

    // 6) 删除一篇（导入库上的写路径）
    step(&mut lines, &mut fails,
        "remove on store B -> count 2",
        match attempt(store_b.remove_memo("ffi-check-3").map(|_| ())) {
            Ok(_) => match store_b.memo_count() {
                Ok(2) => Ok(String::new()),
                Ok(n) => Err(format!("count {n}")),
                Err(e) => Err(e.to_string()),
            },
            Err(e) => Err(e),
        },
    );

    if fails == 0 {
        lines.push("PHASE0 ALL PASS".to_string());
    } else {
        lines.push(format!("PHASE0 FAILED {fails}"));
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    #[test]
    fn phase0_checks_pass_on_host() {
        let dir = std::env::temp_dir().join(format!("moment-ffi-phase0-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let report = super::run_phase0_checks(dir.to_string_lossy().into_owned());
        let _ = std::fs::remove_dir_all(&dir);
        assert!(report.contains("PHASE0 ALL PASS"), "{report}");
    }
}
