//! 迁移语料回归（T-3，refactor_remove_compat §3.3）：仓库内
//! 脱敏样本夹具（由真实备份结构派生，见 fixtures/README.md）
//! 经迁移通道归一后，内容/结构等价于期望原生形——备忘与块的
//! 身份、顺序、块型序列、文本内容逐项守恒，旧形态（attachment
//! 顶层 fileId）按通道口径搬入 attrs，归一结果可被单形化模型
//! 严格解析且重跑零命中（幂等）。原生格式自身的往返由
//! tests/native_fixture.rs（T-1）守，本文件只守迁移正确性。

use moment_core::migrate::{normalize_manifest_value, normalize_value, MigrationStats};
use moment_core::{BackupFile, Manifest};
use serde_json::Value;

fn load_fixture(fixture: &str) -> Value {
    let raw = std::fs::read_to_string(format!("tests/fixtures/{fixture}")).unwrap();
    serde_json::from_str(&raw).unwrap()
}

/// 深度收集 JSON 里全部 "text" 值（文档序），迁移前后各测
/// 一次比对——迁移只搬形态，不许动文本内容。
fn collect_texts(v: &Value, out: &mut Vec<String>) {
    match v {
        Value::Object(m) => {
            for (k, x) in m {
                if k == "text" {
                    if let Value::String(s) = x {
                        out.push(s.clone());
                    }
                } else {
                    collect_texts(x, out);
                }
            }
        }
        Value::Array(a) => a.iter().for_each(|x| collect_texts(x, out)),
        _ => {}
    }
}

fn block_type_seq(memo: &Value) -> Vec<String> {
    memo["doc"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| n["type"].as_str().unwrap_or("").to_string())
        .collect()
}

fn check_sample_migration(fixture: &str) {
    let orig = load_fixture(fixture);
    let mut migrated = orig.clone();
    let stats = normalize_value(&mut migrated);

    // 语料的旧形态只有一处：图片备忘 attachment 节点的顶层
    // fileId（通道搬入 attrs）。其余命中必须为零——语料形态
    // 若被后续改动引入新旧形，此处先红。
    assert_eq!(stats.memos, 2, "{fixture}: memo census");
    assert_eq!(stats.file_id_moved, 1, "{fixture}: top-level fileId move");
    assert_eq!(stats.total_changes(), 1, "{fixture}: unexpected extra migrations: {}", stats.summary());

    // 归一结果可被单形化模型严格解析（通道与主线的契约）。
    let backup: BackupFile =
        serde_json::from_value(migrated.clone()).expect("migrated sample parses under strict model");
    assert_eq!(backup.version, 2);
    assert_eq!(backup.memos.len(), 2);

    // 结构等价：备忘身份/顺序、块型序列、块 id 逐项守恒。
    let orig_memos = orig["memos"].as_array().unwrap();
    for (i, om) in orig_memos.iter().enumerate() {
        let mm = &backup.memos[i];
        assert_eq!(mm.id.to_string(), om["id"].as_str().unwrap(), "{fixture}: memo {i} id");
        assert_eq!(
            mm.title.as_deref(),
            om["title"].as_str(),
            "{fixture}: memo {i} title"
        );
        let migrated_memo = serde_json::to_value(mm).unwrap();
        assert_eq!(
            block_type_seq(&migrated_memo),
            block_type_seq(om),
            "{fixture}: memo {i} block type sequence"
        );
        let orig_ids: Vec<&str> = om["doc"]
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n["id"].as_str().unwrap())
            .collect();
        let migrated_ids: Vec<&str> = migrated_memo["doc"]
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n["id"].as_str().unwrap())
            .collect();
        assert_eq!(orig_ids, migrated_ids, "{fixture}: memo {i} block ids");
    }

    // 内容等价：全部行内文本逐字守恒（迁移不改内容）。
    let mut before = Vec::new();
    let mut after = Vec::new();
    collect_texts(&orig, &mut before);
    collect_texts(&migrated, &mut after);
    assert_eq!(before, after, "{fixture}: text content must survive migration verbatim");
    assert_eq!(before.len(), 23, "{fixture}: text run census (incl. empty)");
    assert_eq!(
        before.iter().filter(|s| !s.is_empty()).count(),
        13,
        "{fixture}: non-empty text run census"
    );

    // 期望原生形定点：attachment 节点 fileId 已入 attrs、顶层
    // 无残留，其余自有字段（status/image）原样保留。
    let att = migrated["memos"][0]["doc"]
        .as_array()
        .unwrap()
        .iter()
        .find(|n| n["type"] == "attachment")
        .expect("sample attachment node");
    assert!(att.get("fileId").is_none(), "{fixture}: top-level fileId must be gone");
    assert_eq!(att["attrs"]["fileId"], Value::String("awoiuh2w".into()));
    assert_eq!(att["status"], Value::String("done".into()));
    assert_eq!(att["image"], Value::Bool(true));

    // avatars 通道不触碰（头像功能数据通道，用户硬约束）。
    assert_eq!(migrated["avatars"], orig["avatars"], "{fixture}: avatars untouched");
    assert_eq!(
        backup.avatars.as_ref().map(|a| a.as_object().unwrap().len()),
        Some(7),
        "{fixture}: avatar entries preserved"
    );

    // 幂等：归一结果重跑零命中，且模型往返稳定（原生形即
    // 模型序列化形）。
    let mut again = migrated.clone();
    let stats2 = normalize_value(&mut again);
    assert_eq!(stats2.total_changes(), 0, "{fixture}: migration must be idempotent on the corpus");
    assert_eq!(again, migrated);
    let roundtripped = serde_json::to_value(&backup).unwrap();
    assert_eq!(
        roundtripped, migrated,
        "{fixture}: migrated form must equal model serialization"
    );
}

#[test]
fn sample_backup_migrates_to_native_form() {
    check_sample_migration("sample_memos.json");
}

#[test]
fn sample_flutter_export_migrates_to_native_form() {
    check_sample_migration("sample_flutter_memos.json");
}

fn check_sample_manifest(fixture: &str) {
    let orig = load_fixture(fixture);
    let mut migrated = orig.clone();
    let mut stats = MigrationStats::default();
    normalize_manifest_value(&mut migrated, &mut stats);
    // 语料 manifest 已是字典形 {name, type}，通道零命中；
    // 归一后严格解析、条数守恒、与 doc 引用交叉对齐。
    assert_eq!(stats.total_changes(), 0, "{fixture}: manifest already native: {}", stats.summary());
    let manifest: Manifest = serde_json::from_value(migrated).unwrap();
    assert_eq!(manifest.version, 1);
    assert_eq!(manifest.attachments.len(), 17, "{fixture}: attachment census");
    let att = &manifest.attachments["awoiuh2w"];
    assert_eq!(att.name, "sample-photo-03.jpeg");
    assert_eq!(att.mime, "image/jpeg");
    assert!(
        manifest
            .attachments
            .values()
            .all(|a| a.name.starts_with("sample-photo-") && a.mime == "image/jpeg"),
        "{fixture}: all entries desensitized"
    );
}

#[test]
fn sample_manifest_is_native_form() {
    check_sample_manifest("sample_manifest.json");
}

#[test]
fn sample_memos_expose_plain_text() {
    let mut v = load_fixture("sample_memos.json");
    normalize_value(&mut v);
    let parsed: BackupFile = serde_json::from_value(v).unwrap();
    // 样本里「样本文本备忘」是文本备忘，「样本图片备忘」是纯
    // 图片备忘（段落文本为空、正文只有附件块）——按这一事实
    // 断言，不强求每条都有文本。
    let text_memo = parsed
        .memos
        .iter()
        .find(|m| m.title.as_deref() == Some("样本文本备忘"))
        .expect("sample text memo missing");
    let text = text_memo.plain_text();
    assert!(text.contains("样本段落01"), "first sample paragraph present");
    assert!(text.contains("样本段落13"), "last sample paragraph present");
    let image_memo = parsed
        .memos
        .iter()
        .find(|m| m.title.as_deref() == Some("样本图片备忘"))
        .expect("sample image memo missing");
    assert_eq!(image_memo.plain_text(), "", "image memo carries no text");
}
