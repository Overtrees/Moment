//! 存储管线原生门禁（T-1，refactor_remove_compat §3.3）：以
//! 程序化构造的原生格式备份 ZIP 跑导入 → 检索 → 导出全链，
//! 并锁再导入替换语义（替换而非追加）。默认套件不依赖仓库外
//! 验收样本（tests/pipeline.rs 的 T-2 可选外检口径不变）。

use std::collections::BTreeMap;
use std::io::Read;
use std::path::PathBuf;

use moment_core::{write_backup_zip, AttachmentMeta, BackupFile, Manifest};
use moment_storage::Store;
use serde_json::{json, Value};

fn native_package() -> (BackupFile, Manifest, BTreeMap<String, Vec<u8>>) {
    let backup: BackupFile = serde_json::from_value(json!({
        "version": 2,
        "memos": [
            {
                "id": "pipe-a",
                "title": "原生管线篇",
                "pinned": true,
                "createdAt": "2026-01-02T03:04:05.000Z",
                "updatedAt": "2026-01-03T03:04:05.000Z",
                "doc": [
                    { "type": "heading", "id": "pa-h1",
                      "attrs": { "level": 2 },
                      "children": [{ "text": "管线标题" }] },
                    { "type": "paragraph", "id": "pa-p1",
                      "children": [{ "text": "管线检索样本词组鹭江夜泊在此。" }] },
                    { "type": "image", "id": "pa-i1",
                      "attrs": { "fileId": "att-img-1" } },
                    { "type": "attachment", "id": "pa-a1",
                      "attrs": { "fileId": "att-file-1" }, "status": "done" }
                ]
            },
            {
                "id": "pipe-b",
                "createdAt": "2026-01-04T03:04:05.000Z",
                "updatedAt": "2026-01-04T03:04:05.000Z",
                "doc": [
                    { "type": "paragraph", "id": "pb-p1",
                      "children": [{ "text": "第二篇正文，白鹭洲词组在此。" }] },
                    { "type": "todo", "id": "pb-t1",
                      "attrs": { "checked": false },
                      "children": [{ "text": "第二篇待办" }] }
                ]
            }
        ]
    }))
    .unwrap();
    let mut attachments = BTreeMap::new();
    attachments.insert(
        "att-img-1".to_string(),
        AttachmentMeta { name: "管线图.jpg".into(), mime: "image/jpeg".into() },
    );
    attachments.insert(
        "att-file-1".to_string(),
        AttachmentMeta { name: "管线文档.pdf".into(), mime: "application/pdf".into() },
    );
    let manifest = Manifest { version: 1, attachments };
    let mut files = BTreeMap::new();
    files.insert("att-img-1".to_string(), vec![0xFF, 0xD8, 0xFF, 0xE0, 9, 9]);
    files.insert("att-file-1".to_string(), b"%PDF-1.4 pipeline".to_vec());
    (backup, manifest, files)
}

fn write_zip(tag: &str, backup: &BackupFile, manifest: &Manifest, files: &BTreeMap<String, Vec<u8>>) -> PathBuf {
    let bytes = write_backup_zip(backup, manifest, files).unwrap();
    let path = std::env::temp_dir().join(format!(
        "mynote_native_pipeline_{}_{}.zip",
        std::process::id(),
        tag
    ));
    std::fs::write(&path, bytes).unwrap();
    path
}

fn zip_entries(path: &PathBuf) -> BTreeMap<String, Vec<u8>> {
    let file = std::fs::File::open(path).unwrap();
    let mut archive = zip::ZipArchive::new(file).unwrap();
    let mut out = BTreeMap::new();
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).unwrap();
        let name = entry.name().to_string();
        let mut buf = Vec::new();
        entry.read_to_end(&mut buf).unwrap();
        out.insert(name, buf);
    }
    out
}

fn memos_by_id(entries: &BTreeMap<String, Vec<u8>>) -> BTreeMap<String, Value> {
    let mut root: Value = serde_json::from_slice(&entries["memos.json"]).unwrap();
    root.as_object_mut().unwrap().remove("exportedAt");
    root["memos"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| (m["id"].as_str().unwrap().to_string(), m.clone()))
        .collect()
}

#[test]
fn native_backup_full_pipeline() {
    let (backup, manifest, files) = native_package();
    let src = write_zip("src", &backup, &manifest, &files);
    let src_entries = zip_entries(&src);

    let mut store = Store::open_in_memory().unwrap();
    let stats = store.import_backup(&src).unwrap();
    assert_eq!(stats.memos, 2);
    assert_eq!(stats.attachments, 2);
    assert_eq!(store.memo_count().unwrap(), 2);
    assert_eq!(store.attachment_count().unwrap(), 2);

    let memos = store.list_memos().unwrap();
    let titles: Vec<_> = memos.iter().filter_map(|m| m.title.clone()).collect();
    assert_eq!(titles, vec!["原生管线篇".to_string()]);

    // 检索：正文词组（FTS trigram）、2 字短查询（LIKE 回退）、
    // 不存在词不命中。
    assert_eq!(store.search("鹭江夜泊").unwrap(), vec!["pipe-a".to_string()]);
    assert_eq!(store.search("鹭江").unwrap(), vec!["pipe-a".to_string()]);
    assert_eq!(store.search("白鹭洲").unwrap(), vec!["pipe-b".to_string()]);
    assert!(store.search("不存在的词组").unwrap().is_empty());

    // 导出与源包内容等价：memos 按 id 对齐逐值相等（exportedAt
    // 已摘）、manifest 逐值相等、附件逐字节相等。
    let out = std::env::temp_dir().join(format!(
        "mynote_native_pipeline_{}_out.zip",
        std::process::id()
    ));
    store.export_backup(&out).unwrap();
    let out_entries = zip_entries(&out);
    assert_eq!(memos_by_id(&out_entries), memos_by_id(&src_entries));
    let src_manifest: Value = serde_json::from_slice(&src_entries["manifest.json"]).unwrap();
    let out_manifest: Value = serde_json::from_slice(&out_entries["manifest.json"]).unwrap();
    assert_eq!(out_manifest, src_manifest);
    for (name, bytes) in &src_entries {
        if name.starts_with("attachments/") {
            assert_eq!(out_entries.get(name), Some(bytes), "attachment bytes differ: {name}");
        }
    }
    std::fs::remove_file(&src).ok();
    std::fs::remove_file(&out).ok();
}

#[test]
fn native_reimport_replaces_instead_of_appending() {
    let (backup, manifest, files) = native_package();
    let src = write_zip("twice", &backup, &manifest, &files);

    let mut store = Store::open_in_memory().unwrap();
    store.import_backup(&src).unwrap();
    store.import_backup(&src).unwrap();
    assert_eq!(store.memo_count().unwrap(), 2, "same package twice must not append");
    assert_eq!(store.attachment_count().unwrap(), 2);

    // 变体包（删一篇、改一篇标题）再导入：库内容被整体替换，
    // 不是叠加——篇数回落、旧标题与被删篇的检索词一并消失。
    let mut variant = backup.clone();
    variant.memos.retain(|m| m.id.to_string() == "pipe-a");
    variant.memos[0].title = Some("原生管线篇改".to_string());
    let variant_path = write_zip("variant", &variant, &manifest, &files);
    store.import_backup(&variant_path).unwrap();
    assert_eq!(store.memo_count().unwrap(), 1);
    let memos = store.list_memos().unwrap();
    assert_eq!(memos[0].title.as_deref(), Some("原生管线篇改"));
    assert!(store.search("白鹭洲").unwrap().is_empty(), "replaced memo must leave the index");
    assert_eq!(store.search("鹭江夜泊").unwrap(), vec!["pipe-a".to_string()]);

    std::fs::remove_file(&src).ok();
    std::fs::remove_file(&variant_path).ok();
}
