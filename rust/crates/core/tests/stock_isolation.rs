//! 存量加载逐篇隔离（core::migrate::normalize_stock_value）
//! 集成测试：单篇结构坏行整篇隔离保全、好篇无损照常加载、
//! 摘要隔离计数；导入路径（normalize_value + 严格解析）
//! 语义不变、不被隔离放宽；隔离区合并去重与导出附带。

use moment_core::migrate::{merge_quarantine, normalize_stock_value, normalize_value};
use moment_core::{
    read_backup_zip_migrated, write_backup_zip_with_quarantine, BackupFile, Manifest,
};
use serde_json::{json, Value};

fn good_memo(id: &str, text: &str) -> Value {
    json!({
        "id": id,
        "title": format!("title-{id}"),
        "createdAt": "2026-05-08T15:43:19.257Z",
        "updatedAt": "2026-05-08T15:43:19.257Z",
        "doc": [
            { "type": "paragraph", "id": format!("{id}-p1"),
              "children": [{ "text": text }] }
        ]
    })
}

fn stock_with(bad: Value) -> Value {
    json!({
        "version": 2,
        "memos": [
            good_memo("good-a", "alpha body"),
            bad,
            good_memo("good-c", "gamma body"),
        ]
    })
}

/// 五变体逐一验：坏篇整篇隔离（原文逐字保全）、两好篇
/// 无损保留且可严格解析、摘要 quarantined=1。
#[test]
fn five_variants_isolated_good_memos_lossless() {
    let variants: Vec<(&str, Value)> = vec![
        ("S7a 非对象条目", json!("garbage-row")),
        (
            "S7b doc 为字符串",
            json!({
                "id": "bad-b", "createdAt": "2026-05-08T15:43:19.257Z",
                "updatedAt": "2026-05-08T15:43:19.257Z", "doc": "not-an-array"
            }),
        ),
        (
            "S7c createdAt 为布尔",
            json!({
                "id": "bad-c", "createdAt": true,
                "updatedAt": "2026-05-08T15:43:19.257Z",
                "doc": [{ "type": "paragraph", "id": "x1", "children": [{ "text": "t" }] }]
            }),
        ),
        (
            "S7d 缺 id",
            json!({
                "createdAt": "2026-05-08T15:43:19.257Z",
                "updatedAt": "2026-05-08T15:43:19.257Z",
                "doc": [{ "type": "paragraph", "id": "x1", "children": [{ "text": "t" }] }]
            }),
        ),
        (
            "S7e children 为对象",
            json!({
                "id": "bad-e", "createdAt": "2026-05-08T15:43:19.257Z",
                "updatedAt": "2026-05-08T15:43:19.257Z",
                "doc": [{ "type": "paragraph", "id": "rb1", "children": { "text": "x" } }]
            }),
        ),
    ];
    for (name, bad) in variants {
        let mut stock = stock_with(bad.clone());
        let out = normalize_stock_value(&mut stock);
        assert_eq!(out.quarantined.len(), 1, "{name}: 应隔离恰一篇");
        assert_eq!(
            out.quarantined[0], bad,
            "{name}: 隔离区须为归一前原文逐字保全"
        );
        assert_eq!(out.stats.quarantined, 1, "{name}: 摘要隔离计数");
        assert!(
            out.stats.summary().contains("quarantined=1"),
            "{name}: summary 须含 quarantined 键: {}",
            out.stats.summary()
        );
        // 好篇无损：归一结果可严格解析且两篇正文齐全。
        let parsed: BackupFile = serde_json::from_value(stock.clone())
            .unwrap_or_else(|e| panic!("{name}: 隔离后存量应可严格解析: {e}"));
        assert_eq!(parsed.memos.len(), 2, "{name}: 好篇篇数");
        let texts: Vec<String> = parsed.memos.iter().map(|m| m.plain_text()).collect();
        assert!(texts.iter().any(|t| t.contains("alpha body")), "{name}: 甲篇正文");
        assert!(texts.iter().any(|t| t.contains("gamma body")), "{name}: 丙篇正文");
        let ids: Vec<&str> = parsed.memos.iter().map(|m| m.id.as_str()).collect();
        assert_eq!(ids, ["good-a", "good-c"], "{name}: 好篇 id 与顺序");
        // 幂等：已收敛存量重跑零隔离零改动。
        let mut again = stock.clone();
        let out2 = normalize_stock_value(&mut again);
        assert_eq!(out2.quarantined.len(), 0, "{name}: 重跑不应再隔离");
        assert_eq!(
            out2.stats.total_changes(),
            0,
            "{name}: 重跑应零改动: {}",
            out2.stats.summary()
        );
        assert_eq!(again, stock, "{name}: 重跑结果应逐字不变");
    }
}

/// 字段级坏形（归一可收敛）不触发隔离：数字 id + 毫秒戳
/// 的旧形篇归一后照常保留。
#[test]
fn field_level_old_form_is_normalized_not_quarantined() {
    let mut stock = json!({
        "version": 2,
        "memos": [
            good_memo("good-a", "alpha body"),
            {
                "id": 4242,
                "createdAt": 1778254999257i64,
                "updatedAt": 1778254999257i64,
                "doc": [{ "type": "paragraph", "id": "o1", "children": [{ "text": "old form" }] }]
            },
        ]
    });
    let out = normalize_stock_value(&mut stock);
    assert_eq!(out.quarantined.len(), 0, "旧形字段应归一而非隔离");
    let parsed: BackupFile = serde_json::from_value(stock).expect("应可解析");
    assert_eq!(parsed.memos.len(), 2);
    assert_eq!(parsed.memos[1].id.as_str(), "4242");
}

/// 导入路径语义不变：normalize_value 不隔离、坏篇仍在，
/// 其后严格解析整包失败（validate-then-swap 整包严格）。
#[test]
fn import_path_stays_strict_no_isolation() {
    let bad = json!({
        "id": "bad-b", "createdAt": "2026-05-08T15:43:19.257Z",
        "updatedAt": "2026-05-08T15:43:19.257Z", "doc": "not-an-array"
    });
    let mut stock = stock_with(bad);
    let stats = normalize_value(&mut stock);
    assert_eq!(stats.quarantined, 0, "导入通道不计隔离");
    assert_eq!(
        stock["memos"].as_array().map(|a| a.len()),
        Some(3),
        "导入通道不剔篇"
    );
    assert!(
        serde_json::from_value::<BackupFile>(stock).is_err(),
        "坏篇在导入路径仍应整包解析失败"
    );
}

/// 根级全损口径不变：根为数组 / memos 非数组时无可隔离，
/// 原样返回（调用方走既有失败态）。
#[test]
fn root_level_damage_left_untouched() {
    let mut arr = json!([1, 2, 3]);
    let out = normalize_stock_value(&mut arr);
    assert!(out.quarantined.is_empty());
    assert_eq!(arr, json!([1, 2, 3]));

    let mut weird = json!({ "version": 2, "memos": "nope" });
    let out = normalize_stock_value(&mut weird);
    assert!(out.quarantined.is_empty());
    assert_eq!(weird["memos"], json!("nope"), "非数组 memos 原样装回");
}

/// 隔离区合并：追加、按内容去重、既有坏内容不销毁。
#[test]
fn merge_quarantine_appends_dedupes_and_preserves() {
    let bad1 = json!({"id": "bad-1", "doc": "x"});
    let bad2 = json!("garbage-row");
    let (doc, n) = merge_quarantine(None, &[bad1.clone(), bad2.clone()]);
    assert_eq!(n, 2);
    let arr: Vec<Value> = serde_json::from_str(&doc).expect("数组文档");
    assert_eq!(arr, vec![bad1.clone(), bad2.clone()]);
    // 同批重跑（多次加载）：不重复堆积。
    let (doc2, n2) = merge_quarantine(Some(&doc), &[bad1.clone(), bad2.clone()]);
    assert_eq!(n2, 2, "重复合并不得堆积");
    assert_eq!(doc2, doc);
    // 新增一篇追加在尾。
    let bad3 = json!({"id": "bad-3"});
    let (_, n3) = merge_quarantine(Some(&doc), &[bad3]);
    assert_eq!(n3, 3);
    // 既有内容不可解析：整串作一条字符串保全、新条目照常追加。
    let (doc4, n4) = merge_quarantine(Some("{broken json"), &[bad1.clone()]);
    assert_eq!(n4, 2);
    let arr4: Vec<Value> = serde_json::from_str(&doc4).expect("数组文档");
    assert_eq!(arr4[0], json!("{broken json"), "既有坏内容须原样保全");
    assert_eq!(arr4[1], bad1);
}

/// 隔离区原文随备份导出（quarantine.json 条目），且导出
/// 包再导入时该条目被忽略、导入严格口径不放宽。
#[test]
fn quarantine_rides_backup_export_and_import_ignores_it() {
    let backup: BackupFile =
        serde_json::from_value(json!({ "version": 2, "memos": [good_memo("good-a", "alpha body")] }))
            .expect("夹具可解析");
    let quarantine_doc = "[{\"id\":\"bad-1\",\"doc\":\"x\"}]";
    let bytes = write_backup_zip_with_quarantine(
        &backup,
        &Manifest::default(),
        &std::collections::BTreeMap::new(),
        quarantine_doc,
    )
    .expect("导出应成功");
    // 条目在包内且逐字一致。
    let mut archive =
        zip::ZipArchive::new(std::io::Cursor::new(bytes.clone())).expect("zip 可读");
    let mut entry = archive
        .by_name(moment_core::QUARANTINE_ENTRY)
        .expect("quarantine.json 条目应在包内");
    let mut content = String::new();
    std::io::Read::read_to_string(&mut entry, &mut content).expect("可读");
    assert_eq!(content, quarantine_doc);
    drop(entry);
    // 再导入：条目被忽略、好篇正常导入。
    let (pkg, _) = read_backup_zip_migrated(&bytes).expect("导入应成功");
    assert_eq!(pkg.backup.memos.len(), 1);
    assert_eq!(pkg.backup.memos[0].id.as_str(), "good-a");
}
