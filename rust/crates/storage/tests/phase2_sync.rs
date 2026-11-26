//! 阶段二存储 API 门禁：差量同步（sync_library）、单行
//! 更新/删除（upsert_memo/remove_memo）、整库替换
//! （replace_library）、逐篇哈希对账（memo_hashes /
//! library_hash）、开库整库重归一（renormalize_library）、
//! 字节导入（import_backup_bytes）。全部程序化造数，不
//! 依赖仓库外样本。

use moment_core::{BackupFile, Memo};
use moment_storage::{fnv1a_64, library_hash, Store, NORMALIZE_VERSION};
use serde_json::json;

fn memo(id: &str, text: &str, updated: &str) -> Memo {
    serde_json::from_value(json!({
        "id": id,
        "title": format!("标题{id}"),
        "createdAt": "2026-01-02T03:04:05.000Z",
        "updatedAt": updated,
        "doc": [
            { "type": "paragraph", "id": format!("{id}-p1"),
              "children": [{ "text": text }] }
        ]
    }))
    .unwrap()
}

fn backup(memos: Vec<Memo>) -> BackupFile {
    BackupFile { version: 2, exported_at: None, memos, avatars: None }
}

#[test]
fn sync_library_diff_semantics() {
    let mut store = Store::open_in_memory().unwrap();
    let a = memo("s-a", "第一篇正文苇岸", "2026-01-02T03:04:05.000Z");
    let b = memo("s-b", "第二篇正文", "2026-01-03T03:04:05.000Z");
    let stats = store.sync_library(&backup(vec![a.clone(), b.clone()])).unwrap();
    assert_eq!(stats.upserted, 2);
    assert_eq!(stats.deleted, 0);
    assert_eq!(store.memo_count().unwrap(), 2);

    // 无变化再同步：全部 unchanged、零写入。
    let stats = store.sync_library(&backup(vec![a.clone(), b.clone()])).unwrap();
    assert_eq!(stats.unchanged, 2);
    assert_eq!(stats.upserted, 0);

    // 改一篇、删一篇、加一篇。
    let a2 = memo("s-a", "第一篇正文改稿", "2026-01-05T03:04:05.000Z");
    let c = memo("s-c", "第三篇正文", "2026-01-06T03:04:05.000Z");
    let stats = store.sync_library(&backup(vec![a2, c])).unwrap();
    assert_eq!(stats.upserted, 2);
    assert_eq!(stats.deleted, 1);
    assert_eq!(store.memo_count().unwrap(), 2);
    // FTS 跟随差量：新词命中、被删篇词不命中。
    let hits = store.search("改稿").unwrap();
    assert_eq!(hits, vec!["s-a".to_string()]);
    let hits = store.search("第二篇正文").unwrap();
    assert!(hits.is_empty(), "deleted memo must not hit FTS: {hits:?}");
    // 归一版本戳已落。
    assert_eq!(
        store.get_meta("normalize_version").unwrap().as_deref(),
        Some(NORMALIZE_VERSION.to_string().as_str())
    );
}

#[test]
fn upsert_and_remove_single_row() {
    let mut store = Store::open_in_memory().unwrap();
    let a = memo("u-a", "单行甲", "2026-01-02T03:04:05.000Z");
    store.upsert_memo(&a).unwrap();
    assert_eq!(store.memo_count().unwrap(), 1);
    let a2 = memo("u-a", "单行甲改", "2026-01-03T03:04:05.000Z");
    store.upsert_memo(&a2).unwrap();
    assert_eq!(store.memo_count().unwrap(), 1);
    assert_eq!(store.search("单行甲改").unwrap(), vec!["u-a".to_string()]);
    store.remove_memo("u-a").unwrap();
    assert_eq!(store.memo_count().unwrap(), 0);
    assert!(store.search("单行甲改").unwrap().is_empty());
}

#[test]
fn replace_library_and_hash_reconcile() {
    let mut store = Store::open_in_memory().unwrap();
    let memos = vec![
        memo("r-a", "对账甲篇", "2026-01-02T03:04:05.000Z"),
        memo("r-b", "对账乙篇", "2026-01-03T03:04:05.000Z"),
    ];
    store
        .replace_library(
            &backup(memos.clone()),
            Some("{\"version\":1,\"attachments\":{}}"),
            &[("migration_stamp", "{\"memos\":2}")],
        )
        .unwrap();
    // 逐篇哈希与独立复算一致（对账口径）。
    let hashes = store.memo_hashes().unwrap();
    assert_eq!(hashes.len(), 2);
    for m in &memos {
        let expect = fnv1a_64(serde_json::to_string(m).unwrap().as_bytes());
        let got = hashes.iter().find(|(id, _)| id == &m.id.to_string()).unwrap().1;
        assert_eq!(got, expect);
    }
    let agg = library_hash(&hashes);
    assert_ne!(agg, 0);
    assert_eq!(
        store.get_meta("migration_stamp").unwrap().as_deref(),
        Some("{\"memos\":2}")
    );
    // 替换为更小库：旧篇消失。
    store
        .replace_library(&backup(vec![memos[0].clone()]), None, &[])
        .unwrap();
    assert_eq!(store.memo_count().unwrap(), 1);
}

#[test]
fn renormalize_upgrades_stale_version() {
    let mut store = Store::open_in_memory().unwrap();
    // 以旧形态直接落库（毫秒时间戳），戳置 0 模拟未归一存量。
    let old: Memo = serde_json::from_value(json!({
        "id": "n-a",
        "createdAt": "2026-01-02T03:04:05.000Z",
        "updatedAt": "2026-01-02T03:04:05.000Z",
        "doc": [{ "type": "paragraph", "id": "n-p1", "children": [{ "text": "归一前" }] }]
    }))
    .unwrap();
    store.upsert_memo(&old).unwrap();
    store.set_meta("normalize_version", "0").unwrap();
    // 现行版本即为 1 且该篇已是原生形：归一无变更、只升戳。
    let changed = store.renormalize_library().unwrap();
    assert_eq!(changed, 0);
    assert_eq!(
        store.get_meta("normalize_version").unwrap().as_deref(),
        Some(NORMALIZE_VERSION.to_string().as_str())
    );
    // 已是现行版本：直接返回 0。
    assert_eq!(store.renormalize_library().unwrap(), 0);
}

#[test]
fn import_backup_bytes_no_attachments_mode() {
    let (pkg_backup, manifest, files) = {
        let backup: BackupFile = serde_json::from_value(json!({
            "version": 2,
            "memos": [{
                "id": "z-a",
                "createdAt": "2026-01-02T03:04:05.000Z",
                "updatedAt": "2026-01-02T03:04:05.000Z",
                "doc": [{ "type": "paragraph", "id": "z-p1",
                          "children": [{ "text": "字节导入篇" }] }]
            }]
        }))
        .unwrap();
        let manifest = moment_core::Manifest { version: 1, attachments: Default::default() };
        let mut files = std::collections::BTreeMap::new();
        files.insert("att-1".to_string(), vec![1u8, 2, 3]);
        (backup, manifest, files)
    };
    let bytes = moment_core::write_backup_zip(&pkg_backup, &manifest, &files).unwrap();
    let mut store = Store::open_in_memory().unwrap();
    let (stats, _mig) = store.import_backup_bytes(&bytes, false).unwrap();
    assert_eq!(stats.memos, 1);
    assert_eq!(stats.attachments, 1);
    // 不入 BLOB 口径：附件表为空，备忘在库。
    assert_eq!(store.attachment_count().unwrap(), 0);
    assert_eq!(store.memo_count().unwrap(), 1);
    // 入 BLOB 口径对照。
    let (stats2, _) = store.import_backup_bytes(&bytes, true).unwrap();
    assert_eq!(stats2.attachments, 1);
    assert_eq!(store.attachment_count().unwrap(), 1);
}
