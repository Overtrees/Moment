//! 备份 ZIP 读写验收：两份真实互通样本（原版导出 + Flutter
//! 导出）经 core 的 read → write → read 后语义不变——memos 深
//! 相等（数字按 f64 归一、键序无关、数组序敏感）、manifest
//! 模型相等且序列化字节稳定（第五步建模后无原文透传）、附件
//! 逐 id 字节一致。另锁原生形往返（模型直出 → 主线直读逐值
//! 等价）与旧形 manifest 的通道归一/主线拒绝。
//!
//! 样本含真实数据，只存放在仓库外的 mynote-zip-acceptance/
//! （不入 git）；缺失时本文件测试跳过（打印说明后返回），
//! 存在时全部断言照常执行。CI 等干净检出环境不因样本缺席
//! 变红，本机验收口径不变。样本目录可用环境变量
//! MYNOTE_ZIP_ACCEPTANCE_DIR 覆盖。

use std::collections::BTreeMap;
use std::io::{Read, Write as _};
use std::path::PathBuf;

use mynote_core::{
    read_backup_zip, read_backup_zip_migrated, write_backup_zip, AttachmentMeta, BackupFile,
    Manifest,
};
use serde_json::Value;

fn acceptance_zip(name: &str) -> Option<Vec<u8>> {
    let dir = std::env::var_os("MYNOTE_ZIP_ACCEPTANCE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(format!(
                "{}/../../../../mynote-zip-acceptance",
                env!("CARGO_MANIFEST_DIR")
            ))
        });
    let p = dir.join(name);
    if !p.exists() {
        eprintln!("acceptance zip missing, skipped: {}", p.display());
        return None;
    }
    Some(std::fs::read(p).unwrap())
}

fn normalize(v: &Value) -> Value {
    match v {
        Value::Number(n) => serde_json::json!(n.as_f64().unwrap()),
        Value::Array(a) => Value::Array(a.iter().map(normalize).collect()),
        Value::Object(m) => {
            Value::Object(m.iter().map(|(k, x)| (k.clone(), normalize(x))).collect())
        }
        other => other.clone(),
    }
}

fn check_roundtrip(name: &str) {
    let Some(bytes) = acceptance_zip(name) else { return };
    let pkg = read_backup_zip(&bytes).unwrap();
    assert_eq!(pkg.backup.memos.len(), 2, "{name}: memo count");
    assert_eq!(pkg.attachments.len(), 17, "{name}: attachment count");
    assert_eq!(pkg.manifest.version, 1, "{name}: manifest version");

    let out = write_backup_zip(&pkg.backup, &pkg.manifest, &pkg.attachments).unwrap();
    let pkg2 = read_backup_zip(&out).unwrap();

    let a = normalize(&serde_json::to_value(&pkg.backup).unwrap());
    let b = normalize(&serde_json::to_value(&pkg2.backup).unwrap());
    // exportedAt 是导出时刻，两包都会带且必然不同——比较前摘掉
    let mut a = a;
    let mut b = b;
    a.as_object_mut().unwrap().remove("exportedAt");
    b.as_object_mut().unwrap().remove("exportedAt");
    assert_eq!(a, b, "{name}: memos deep-equal after zip roundtrip");
    assert_eq!(pkg.manifest, pkg2.manifest, "{name}: manifest model");
    assert_eq!(
        serde_json::to_string(&pkg.manifest).unwrap(),
        serde_json::to_string(&pkg2.manifest).unwrap(),
        "{name}: manifest serialization stable"
    );
    assert_eq!(pkg.attachments, pkg2.attachments, "{name}: attachment bytes");
}

fn zip_entry(bytes: &[u8], name: &str) -> Vec<u8> {
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(bytes)).unwrap();
    let mut entry = archive.by_name(name).unwrap();
    let mut buf = Vec::new();
    entry.read_to_end(&mut buf).unwrap();
    buf
}

fn zip_with_manifest(manifest_json: &str) -> Vec<u8> {
    let mut writer = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    writer.start_file("memos.json", opts).unwrap();
    writer
        .write_all(br#"{"version":2,"memos":[]}"#)
        .unwrap();
    writer.start_file("manifest.json", opts).unwrap();
    writer.write_all(manifest_json.as_bytes()).unwrap();
    writer.finish().unwrap().into_inner()
}

#[test]
fn native_zip_roundtrip_model_direct() {
    // 原生形往返锁：模型直出 → 主线直读，逐值等价；包内
    // manifest.json 字节即模型序列化本身。
    let backup = BackupFile {
        version: 2,
        exported_at: None,
        memos: Vec::new(),
        avatars: None,
        extra: Default::default(),
    };
    let mut attachments_meta = BTreeMap::new();
    attachments_meta.insert(
        "a1".to_string(),
        AttachmentMeta {
            name: "照片 1.jpg".to_string(),
            mime: "image/jpeg".to_string(),
        },
    );
    attachments_meta.insert(
        "b2".to_string(),
        AttachmentMeta {
            name: String::new(),
            mime: "application/pdf".to_string(),
        },
    );
    let manifest = Manifest {
        version: 1,
        attachments: attachments_meta,
    };
    let mut files = BTreeMap::new();
    files.insert("a1".to_string(), vec![1u8, 2, 3]);
    files.insert("b2".to_string(), vec![4u8, 5]);

    let out = write_backup_zip(&backup, &manifest, &files).unwrap();
    assert_eq!(
        zip_entry(&out, "manifest.json"),
        serde_json::to_string(&manifest).unwrap().into_bytes(),
        "manifest.json in zip must be the model serialization"
    );
    let pkg = read_backup_zip(&out).unwrap();
    assert_eq!(pkg.backup, backup);
    assert_eq!(pkg.manifest, manifest);
    assert_eq!(pkg.attachments, files);
}

#[test]
fn old_form_manifest_channel_only() {
    // 旧形 manifest（数组形 + 条目多余键 + 根级多余键 + 无 id
    // 条目）：主线拒绝、迁移通道归一为原生形。
    let bytes = zip_with_manifest(
        r#"{"version":1,"legacy":true,"attachments":[
            {"id":"a1","name":"x.png","type":"image/png","junk":1},
            {"name":"no-id.png","type":"image/png"},
            "garbage",
            {"id":"b2","name":"y.pdf"}
        ]}"#,
    );
    assert!(
        read_backup_zip(&bytes).is_err(),
        "mainline must reject array-form manifest"
    );
    let (pkg, stats) = read_backup_zip_migrated(&bytes).unwrap();
    assert_eq!(stats.manifest_form_fixes, 1);
    assert_eq!(stats.manifest_entries_dropped, 2);
    // 根级 legacy 剥离 1 + a1 的 junk 剥离 1 + b2 缺 type 补 1
    assert_eq!(stats.manifest_fields_normalized, 3);
    let mut expected = BTreeMap::new();
    expected.insert(
        "a1".to_string(),
        AttachmentMeta {
            name: "x.png".to_string(),
            mime: "image/png".to_string(),
        },
    );
    expected.insert(
        "b2".to_string(),
        AttachmentMeta {
            name: "y.pdf".to_string(),
            mime: String::new(),
        },
    );
    assert_eq!(
        pkg.manifest,
        Manifest {
            version: 1,
            attachments: expected
        }
    );
    // 归一后可主线直读（原生形往返）。
    let out = write_backup_zip(&pkg.backup, &pkg.manifest, &pkg.attachments).unwrap();
    assert!(read_backup_zip(&out).is_ok());
}

fn zip_with_memos(memos_json: &str) -> Vec<u8> {
    let mut writer = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    writer.start_file("memos.json", opts).unwrap();
    writer.write_all(memos_json.as_bytes()).unwrap();
    writer.start_file("manifest.json", opts).unwrap();
    writer
        .write_all(br#"{"version":1,"attachments":{}}"#)
        .unwrap();
    writer.finish().unwrap().into_inner()
}

#[test]
fn callout_rename_is_channel_only_and_export_is_native() {
    // 旧包：callout 变体分别以 kind / variant 旧名承载（§2.7）。
    let bytes = zip_with_memos(
        r#"{"version":2,"memos":[{"id":"m1",
            "createdAt":"2026-05-08T15:43:19.257Z",
            "updatedAt":"2026-05-08T15:43:19.257Z",
            "doc":[
                {"type":"callout","id":"c1","kind":"warning","children":[{"text":"a"}]},
                {"type":"callout","id":"c2","variant":"tip","children":[{"text":"b"}]},
                {"type":"callout","id":"c3","calloutType":"caution","children":[{"text":"c"}]}
            ]}]}"#,
    );
    // 主线直读：不改名（旧名只在 extra 透传中原样，主线无双读、
    // 无改名）——改名是迁移通道的独占职责。
    let plain = read_backup_zip(&bytes).unwrap();
    let d = &plain.backup.memos[0].doc;
    assert!(d[0].extra.contains_key("kind"));
    assert!(!d[0].extra.contains_key("calloutType"));
    // 通道读：改名完成，旧名零残留。
    let (pkg, stats) = read_backup_zip_migrated(&bytes).unwrap();
    assert_eq!(stats.callout_moved, 2);
    assert_eq!(stats.callout_cleared, 0);
    let d = &pkg.backup.memos[0].doc;
    assert_eq!(
        d[0].extra.get("calloutType").and_then(|v| v.as_str()),
        Some("warning")
    );
    assert_eq!(
        d[1].extra.get("calloutType").and_then(|v| v.as_str()),
        Some("tip")
    );
    assert_eq!(
        d[2].extra.get("calloutType").and_then(|v| v.as_str()),
        Some("caution")
    );
    for n in d {
        assert!(!n.extra.contains_key("kind"), "kind must not survive the channel");
        assert!(!n.extra.contains_key("variant"), "variant must not survive the channel");
    }
    // 原生导出只出新名，且可主线直读（原生形往返）。
    let out = write_backup_zip(&pkg.backup, &pkg.manifest, &pkg.attachments).unwrap();
    let memos_json = String::from_utf8(zip_entry(&out, "memos.json")).unwrap();
    assert!(memos_json.contains(r#""calloutType":"warning""#));
    assert!(memos_json.contains(r#""calloutType":"tip""#));
    assert!(!memos_json.contains(r#""kind""#), "export must not carry old name: {memos_json}");
    assert!(!memos_json.contains(r#""variant""#), "export must not carry old name: {memos_json}");
    assert!(read_backup_zip(&out).is_ok());
}

#[test]
fn real_backup_zip_roundtrip() {
    check_roundtrip("real_backup.zip");
}

#[test]
fn flutter_export_zip_roundtrip() {
    check_roundtrip("flutter_export.zip");
}
