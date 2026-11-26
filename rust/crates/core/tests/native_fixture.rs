//! 原生格式夹具门禁（T-1，refactor_remove_compat §3.3）：测试
//! 内以原生模型程序化构造全块类型 + 附件的备份夹具，断言原生
//! 格式往返无损与行为口径。默认套件不再依赖仓库外验收样本
//! （real_backup.zip 等）在位与否，CI 恒跑；仓库外样本保留为
//! 可选外检（T-2，tests/backup_zip.rs / storage pipeline）。
//!
//! 夹具形态口径：块的专有字段一律原生位——heading 的 level
//! 在 attrs、todo 的 checked 在 attrs、image/gallery/attachment
//! 的 fileId 在 attrs、gallery items 为对象形、块名为原生名
//! （musicCard/codeBlock）；代码块与公式按现行共用模型以
//! paragraph 承载 MD 源码（§2.13）。

use std::collections::BTreeMap;

use moment_core::{
    read_backup_zip, read_backup_zip_migrated, write_backup_zip, AttachmentMeta, BackupFile,
    Manifest, Node,
};
use serde_json::{json, Value};

const DUMMY_AVATAR: &str = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

/// 全块类型原生夹具（程序化构造，内容全为构造数据）。
fn native_backup() -> BackupFile {
    let v = json!({
        "version": 2,
        "avatars": { "native-a": DUMMY_AVATAR },
        "memos": [
            {
                "id": "native-a",
                "title": "原生夹具全块篇",
                "pinned": true,
                "createdAt": "2026-01-02T03:04:05.000Z",
                "updatedAt": "2026-01-03T03:04:05.000Z",
                "layout": { "mode": "independent" },
                "doc": [
                    { "type": "heading", "id": "na-h1",
                      "attrs": { "level": 1 },
                      "children": [{ "text": "原生夹具标题" }] },
                    { "type": "paragraph", "id": "na-p1",
                      "children": [
                          { "text": "普通文本" },
                          { "text": "删除线文本", "strikethrough": true },
                          { "text": "加粗文本", "bold": true }
                      ] },
                    { "type": "todo", "id": "na-t1",
                      "attrs": { "checked": true },
                      "children": [{ "text": "已完成待办" }] },
                    { "type": "todo", "id": "na-t2",
                      "attrs": { "checked": false },
                      "children": [{ "text": "未完成待办" }] },
                    { "type": "bulleted-list", "id": "na-l1",
                      "children": [
                          { "type": "paragraph", "id": "na-l1a",
                            "children": [{ "text": "无序项一" }] },
                          { "type": "paragraph", "id": "na-l1b",
                            "children": [{ "text": "无序项二" }] }
                      ] },
                    { "type": "numbered-list", "id": "na-l2",
                      "attrs": { "start": 3 },
                      "children": [
                          { "type": "paragraph", "id": "na-l2a",
                            "children": [{ "text": "有序项三" }] },
                          { "type": "paragraph", "id": "na-l2b",
                            "children": [{ "text": "有序项四" }] }
                      ] },
                    { "type": "image", "id": "na-i1",
                      "attrs": { "fileId": "att-img-1" } },
                    { "type": "image", "id": "na-i2",
                      "attrs": { "url": "https://example.com/ext.png" } },
                    { "type": "gallery", "id": "na-g1",
                      "attrs": { "items": [
                          { "fileId": "att-img-1" },
                          { "url": "https://example.com/g.png" }
                      ] } },
                    { "type": "attachment", "id": "na-a1",
                      "attrs": { "fileId": "att-file-1" },
                      "status": "done" },
                    { "type": "musicCard", "id": "na-m1",
                      "url": "https://example.com/song",
                      "meta": null, "status": "loading" },
                    { "type": "paragraph", "id": "na-p2",
                      "children": [{ "text": "```rust\nfn main() {}\n```" }] },
                    { "type": "codeBlock", "id": "na-c1",
                      "children": [{ "text": "let x = 1;" }] },
                    { "type": "link-card", "id": "na-k1",
                      "url": "https://example.com/article",
                      "title": "示例文章" },
                    { "type": "video", "id": "na-v1",
                      "attrs": { "fileId": "att-vid-1" } },
                    { "type": "audio", "id": "na-u1",
                      "url": "https://example.com/a.mp3" },
                    { "type": "file", "id": "na-f1",
                      "attrs": { "fileId": "att-file-2" } },
                    { "type": "quote", "id": "na-q1",
                      "children": [{ "text": "引用文本" }] },
                    { "type": "divider", "id": "na-d1" },
                    { "type": "callout", "id": "na-w1",
                      "calloutType": "warning",
                      "children": [{ "text": "注意文本" }] },
                    { "type": "imgTextCard", "id": "na-x1",
                      "attrs": { "fileId": "att-img-1" },
                      "children": [{ "text": "图文卡文本" }] },
                    { "type": "imageTextRow", "id": "na-x2",
                      "attrs": { "fileId": "att-img-1" },
                      "children": [{ "text": "图文行文本" }] },
                    { "type": "paragraph", "id": "na-p3",
                      "children": [{ "text": "$$E=mc^2$$" }] }
                ]
            },
            {
                "id": "native-b",
                "createdAt": "2026-01-04T03:04:05.000Z",
                "updatedAt": "2026-01-04T03:04:05.000Z",
                "doc": [
                    { "type": "paragraph", "id": "nb-p1",
                      "children": [{ "text": "第二篇正文，含检索词组鹭江。" }] },
                    { "type": "todo", "id": "nb-t1",
                      "attrs": { "checked": false },
                      "children": [{ "text": "第二篇待办" }] }
                ]
            }
        ]
    });
    serde_json::from_value(v).expect("native fixture parses under strict model")
}

fn native_manifest() -> Manifest {
    let mut attachments = BTreeMap::new();
    attachments.insert(
        "att-img-1".to_string(),
        AttachmentMeta { name: "原生图.jpg".into(), mime: "image/jpeg".into() },
    );
    attachments.insert(
        "att-file-1".to_string(),
        AttachmentMeta { name: "原生文档.pdf".into(), mime: "application/pdf".into() },
    );
    attachments.insert(
        "att-file-2".to_string(),
        AttachmentMeta { name: "原生文本.txt".into(), mime: "text/plain".into() },
    );
    attachments.insert(
        "att-vid-1".to_string(),
        AttachmentMeta { name: "原生视频.mp4".into(), mime: "video/mp4".into() },
    );
    Manifest { version: 1, attachments }
}

fn native_files() -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    files.insert("att-img-1".to_string(), vec![0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    files.insert("att-file-1".to_string(), b"%PDF-1.4 sample".to_vec());
    files.insert("att-file-2".to_string(), b"plain text file".to_vec());
    files.insert("att-vid-1".to_string(), vec![0, 0, 0, 24, b'f', b't', b'y', b'p']);
    files
}

fn census(nodes: &[Node], out: &mut BTreeMap<String, usize>) {
    for n in nodes {
        if let Some(t) = n.block_type() {
            *out.entry(t.to_string()).or_default() += 1;
        }
        if let Some(kids) = &n.children {
            census(kids, out);
        }
    }
}

#[test]
fn native_fixture_block_census_and_text() {
    let backup = native_backup();
    let mut got = BTreeMap::new();
    for m in &backup.memos {
        census(&m.doc, &mut got);
    }
    let expected: BTreeMap<String, usize> = [
        ("paragraph", 8),
        ("heading", 1),
        ("todo", 3),
        ("bulleted-list", 1),
        ("numbered-list", 1),
        ("image", 2),
        ("gallery", 1),
        ("attachment", 1),
        ("musicCard", 1),
        ("codeBlock", 1),
        ("link-card", 1),
        ("video", 1),
        ("audio", 1),
        ("file", 1),
        ("quote", 1),
        ("divider", 1),
        ("callout", 1),
        ("imgTextCard", 1),
        ("imageTextRow", 1),
    ]
    .iter()
    .map(|(k, v)| (k.to_string(), *v))
    .collect();
    assert_eq!(got, expected, "native fixture must cover every block type exactly as designed");
    assert_eq!(got.values().sum::<usize>(), 29);

    let text_a = backup.memos[0].plain_text();
    for needle in ["原生夹具标题", "删除线文本", "已完成待办", "有序项四", "图文卡文本", "let x = 1;"] {
        assert!(text_a.contains(needle), "memo A plain_text missing {needle}");
    }
    assert!(backup.memos[1].plain_text().contains("鹭江"));
    // 无标题备忘的 title 缺省往返（skip_serializing 口径）。
    assert_eq!(backup.memos[1].title, None);
}

#[test]
fn native_fixture_model_json_roundtrip() {
    let backup = native_backup();
    let back: BackupFile =
        serde_json::from_value(serde_json::to_value(&backup).unwrap()).unwrap();
    assert_eq!(back, backup, "model JSON roundtrip must be lossless");
}

#[test]
fn native_fixture_zip_roundtrip_lossless() {
    let backup = native_backup();
    let manifest = native_manifest();
    let files = native_files();

    let out = write_backup_zip(&backup, &manifest, &files).unwrap();
    let pkg = read_backup_zip(&out).unwrap();
    assert_eq!(pkg.backup, backup, "backup model after zip roundtrip");
    assert_eq!(pkg.manifest, manifest, "manifest model after zip roundtrip");
    assert_eq!(pkg.attachments, files, "attachment bytes after zip roundtrip");

    // 包内 memos.json 与模型序列化逐值一致（exportedAt 两边
    // 摘除后比；写入方若盖导出时刻戳不计入内容差异）。
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(out.clone())).unwrap();
    use std::io::Read as _;
    let mut memos_raw = Vec::new();
    archive.by_name("memos.json").unwrap().read_to_end(&mut memos_raw).unwrap();
    let mut in_zip: Value = serde_json::from_slice(&memos_raw).unwrap();
    let mut model = serde_json::to_value(&backup).unwrap();
    in_zip.as_object_mut().unwrap().remove("exportedAt");
    model.as_object_mut().unwrap().remove("exportedAt");
    assert_eq!(in_zip, model, "memos.json in zip must be the model serialization");
    let mut manifest_raw = Vec::new();
    archive.by_name("manifest.json").unwrap().read_to_end(&mut manifest_raw).unwrap();
    assert_eq!(
        manifest_raw,
        serde_json::to_string(&manifest).unwrap().into_bytes(),
        "manifest.json in zip must be the model serialization"
    );
}

#[test]
fn native_fixture_is_migration_fixed_point() {
    // 原生形过迁移通道必须零命中——通道只归一旧形态，原生
    // 数据不得被改写（与 D3 存量归一的幂等口径同源）。
    let backup = native_backup();
    let manifest = native_manifest();
    let files = native_files();
    let out = write_backup_zip(&backup, &manifest, &files).unwrap();
    let (pkg, stats) = read_backup_zip_migrated(&out).unwrap();
    assert_eq!(
        stats.total_changes(),
        0,
        "native form must pass the migration channel untouched: {}",
        stats.summary()
    );
    assert_eq!(pkg.backup, backup);
    assert_eq!(pkg.manifest, manifest);
    assert_eq!(pkg.attachments, files);
}
