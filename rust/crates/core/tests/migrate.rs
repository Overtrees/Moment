//! 一次性迁移通道（core::migrate）的集成测试：旧形态夹具逐项
//! 归一断言、幂等、坏数据不毁、avatars 不触碰；以及借 dry-run
//! 对仓库内真实夹具（与仓库外验收 ZIP，在位时）的存量扫描。

use mynote_core::migrate::{dry_run_backup, normalize_backup};
use mynote_core::{read_backup_zip, BackupFile};
use serde_json::{json, Value};

/// 全旧形态夹具。doc 下标即断言坐标（见各用例注释）。
fn legacy_backup() -> BackupFile {
    let v = json!({
        "version": 2,
        "exportedAt": "2026-01-01T00:00:00.000Z",
        "avatars": { "memo-x": { "nested": [1, 2, 3] } },
        "memos": [
            {
                "id": 12345,
                "title": "legacy",
                "createdAt": 1778254999257i64,
                "updatedAt": "2026-05-08T15:43:19.257Z",
                "doc": [
                    // 0: heading 顶层 level（无 attrs）→ 搬入
                    { "type": "heading", "id": "h1", "level": 3,
                      "children": [{ "text": "t" }] },
                    // 1: heading attrs.level=2 + 顶层 5 → 影子清除
                    { "type": "heading", "id": "h2", "level": 5,
                      "attrs": { "level": 2 }, "children": [{ "text": "t" }] },
                    // 2: todo 顶层 checked → 搬入
                    { "type": "todo", "id": "t1", "checked": true,
                      "children": [{ "text": "x" }] },
                    // 3: todo attrs.checked=false + 顶层 true → 影子清除
                    { "type": "todo", "id": "t2", "checked": true,
                      "attrs": { "checked": false }, "children": [{ "text": "x" }] },
                    // 4: image 顶层 fileId 覆写 attrs（读口径顶层优先）
                    { "type": "image", "id": "i1", "fileId": "att-top",
                      "attrs": { "fileId": "att-attrs" } },
                    // 5: image 顶层 fileId 空串 → 只删顶层
                    { "type": "image", "id": "i2", "fileId": "",
                      "attrs": { "fileId": "att-keep" } },
                    // 6: attachment 只有顶层 fileId、无 attrs → 建 attrs 搬入
                    { "type": "attachment", "id": "a1", "fileId": "att-only" },
                    // 7: gallery items 混合形态
                    { "type": "gallery", "id": "g1",
                      "attrs": { "items": [
                          "s1",
                          { "fileId": "o1" },
                          { "url": "https://example.com/x.png" },
                          "",
                          { "name": "nope" },
                          42,
                          { "fileId": "", "url": "https://example.com/y.png" }
                      ] } },
                    // 8: gallery children 兜底形（子节点 attrs.fileId）
                    { "type": "gallery", "id": "g2",
                      "children": [
                          { "type": "image", "id": "gi1",
                            "attrs": { "fileId": "c2" } },
                          { "type": "paragraph", "id": "gp1",
                            "children": [{ "text": "" }] }
                      ] },
                    // 9: gallery attrs.items 非数组 + children 顶层 fileId
                    { "type": "gallery", "id": "g3",
                      "attrs": { "items": "junk" },
                      "children": [
                          { "type": "image", "id": "gi2", "fileId": "c9" }
                      ] },
                    // 10: 块类型旧名 music
                    { "type": "music", "id": "m1", "url": "https://example.com/s" },
                    // 11: 列表子项里的旧名 code（递归）
                    { "type": "bulleted-list", "id": "l1",
                      "children": [
                          { "type": "code", "id": "cb1",
                            "children": [{ "text": "x=1" }] }
                      ] },
                    // 12: 行内 strike 三态
                    { "type": "paragraph", "id": "p1",
                      "children": [
                          { "text": "a", "strike": true },
                          { "text": "b", "strike": false, "strikethrough": false },
                          { "text": "c", "strike": true, "strikethrough": false }
                      ] },
                    // 13: attrs 非对象 + 顶层 level → 整项跳过、原样保留
                    { "type": "heading", "id": "h3", "level": 4,
                      "attrs": "junk", "children": [{ "text": "t" }] },
                    // 14: 顶层 fileId 非字符串 → 原样保留
                    { "type": "image", "id": "i3", "fileId": 777 }
                ]
            },
            {
                "id": "already-native",
                "title": "native",
                "createdAt": "2026-05-08T15:43:19.257Z",
                "updatedAt": "2026-05-08T15:43:19.257Z",
                "doc": [
                    { "type": "paragraph", "id": "np1",
                      "children": [{ "text": "plain", "strikethrough": true }] }
                ]
            }
        ]
    });
    serde_json::from_value(v).expect("legacy fixture parses")
}

fn doc(backup: &BackupFile) -> Vec<Value> {
    backup.memos[0]
        .doc
        .iter()
        .map(|n| serde_json::to_value(n).unwrap())
        .collect()
}

#[test]
fn legacy_forms_normalize_item_by_item() {
    let mut backup = legacy_backup();
    let stats = normalize_backup(&mut backup);

    // 备忘级：数字 id → 字符串；毫秒时间戳 → ISO（同瞬间）。
    let m0 = &backup.memos[0];
    assert_eq!(m0.id.to_string(), "12345");
    assert_eq!(m0.created_at.to_millis(), Some(1778254999257));
    match &m0.created_at {
        mynote_core::model::Timestamp::Iso(s) => {
            assert_eq!(s, "2026-05-08T15:43:19.257Z")
        }
        other => panic!("created_at should be Iso, got {other:?}"),
    }

    let d = doc(&backup);
    // 0/1: level 搬入与影子清除。
    assert_eq!(d[0]["attrs"]["level"], json!(3));
    assert!(d[0].get("level").is_none());
    assert_eq!(d[1]["attrs"]["level"], json!(2));
    assert!(d[1].get("level").is_none());
    // 2/3: checked 搬入与影子清除。
    assert_eq!(d[2]["attrs"]["checked"], json!(true));
    assert!(d[2].get("checked").is_none());
    assert_eq!(d[3]["attrs"]["checked"], json!(false));
    assert!(d[3].get("checked").is_none());
    // 4/5/6: fileId 顶层覆写、空串清除、无 attrs 建位。
    assert_eq!(d[4]["attrs"]["fileId"], json!("att-top"));
    assert!(d[4].get("fileId").is_none());
    assert_eq!(d[5]["attrs"]["fileId"], json!("att-keep"));
    assert!(d[5].get("fileId").is_none());
    assert_eq!(d[6]["attrs"]["fileId"], json!("att-only"));
    assert!(d[6].get("fileId").is_none());
    // 7: gallery items 转对象形、无效条目剔除、url 对象原样。
    assert_eq!(
        d[7]["attrs"]["items"],
        json!([
            { "fileId": "s1" },
            { "fileId": "o1" },
            { "url": "https://example.com/x.png" },
            { "fileId": "", "url": "https://example.com/y.png" }
        ])
    );
    // 8: children 兜底物化；children 含非载体子节点（段落），
    // 整组保留不销毁。
    assert_eq!(d[8]["attrs"]["items"], json!([{ "fileId": "c2" }]));
    assert_eq!(d[8]["children"].as_array().unwrap().len(), 2);
    // 9: items 非数组同样按兜底物化（子节点顶层 fileId 先经
    // 递归搬入 attrs 再物化）；children 全部是 fileId 载体，
    // 归一后清除。
    assert_eq!(d[9]["attrs"]["items"], json!([{ "fileId": "c9" }]));
    assert!(d[9].get("children").is_none());
    // 10/11: 旧名改名（含递归子项）。
    assert_eq!(d[10]["type"], json!("musicCard"));
    assert_eq!(d[11]["children"][0]["type"], json!("codeBlock"));
    // 12: strike 改名三态。
    let kids = d[12]["children"].as_array().unwrap();
    assert_eq!(kids[0]["strikethrough"], json!(true));
    assert!(kids[0].get("strike").is_none());
    assert_eq!(kids[1]["strikethrough"], json!(false));
    assert!(kids[1].get("strike").is_none());
    assert_eq!(kids[2]["strikethrough"], json!(true));
    assert!(kids[2].get("strike").is_none());
    // 13/14: 异常形态原样保留。
    assert_eq!(d[13]["level"], json!(4));
    assert_eq!(d[13]["attrs"], json!("junk"));
    assert_eq!(d[14]["fileId"], json!(777));

    // avatars 与 exportedAt 不触碰。
    assert_eq!(
        backup.avatars,
        Some(json!({ "memo-x": { "nested": [1, 2, 3] } }))
    );
    assert_eq!(
        backup.exported_at,
        Some(json!("2026-01-01T00:00:00.000Z"))
    );

    // 统计逐项（与夹具设计一一对应）。
    assert_eq!(stats.memos, 2);
    assert_eq!(stats.numeric_ids, 1);
    assert_eq!(stats.millis_timestamps, 1);
    assert_eq!(stats.file_id_moved, 3, "i1 覆写 + a1 建位 + g3 子节点");
    assert_eq!(stats.file_id_cleared, 1);
    assert_eq!(stats.gallery_string_items, 1);
    assert_eq!(stats.gallery_children_forms, 2);
    assert_eq!(stats.gallery_children_removed, 1, "仅 g3 的全载体 children");
    assert_eq!(stats.gallery_items_dropped, 3, "空串 + 无键对象 + 数字");
    assert_eq!(stats.level_moved, 1);
    assert_eq!(stats.level_cleared, 1);
    assert_eq!(stats.checked_moved, 1);
    assert_eq!(stats.checked_cleared, 1);
    assert_eq!(stats.music_blocks, 1);
    assert_eq!(stats.code_blocks, 1);
    assert_eq!(stats.strike_marks, 3);
    assert_eq!(stats.total_changes(), 22);
    // 普查记原始名：music/code 以旧名入账。
    assert_eq!(stats.block_types.get("music"), Some(&1));
    assert_eq!(stats.block_types.get("code"), Some(&1));
    assert_eq!(stats.block_types.get("gallery"), Some(&3));
}

#[test]
fn normalize_is_idempotent() {
    let mut backup = legacy_backup();
    normalize_backup(&mut backup);
    let once = serde_json::to_value(&backup).unwrap();
    let stats2 = normalize_backup(&mut backup);
    assert_eq!(stats2.total_changes(), 0, "已归一数据重跑必须零命中");
    assert_eq!(serde_json::to_value(&backup).unwrap(), once);
}

#[test]
fn dry_run_does_not_mutate() {
    let backup = legacy_backup();
    let before = serde_json::to_value(&backup).unwrap();
    let dry = dry_run_backup(&backup);
    assert_eq!(serde_json::to_value(&backup).unwrap(), before);
    let mut clone = backup.clone();
    let real = normalize_backup(&mut clone);
    assert_eq!(dry, real, "dry-run 与实跑统计必须同口径");
}

#[test]
fn garbage_shapes_survive() {
    // 无法解读的形态不许炸、不许丢备忘：整体仍可往返序列化。
    let v = json!({
        "version": 2,
        "memos": [{
            "id": "g1",
            "createdAt": "2026-05-08T15:43:19.257Z",
            "updatedAt": "2026-05-08T15:43:19.257Z",
            "doc": [
                { "type": "gallery", "attrs": { "items": [null, true, [], {}] } },
                { "type": "image", "attrs": [1, 2], "fileId": { "x": 1 } },
                { "type": "heading", "attrs": null, "level": [3] }
            ]
        }]
    });
    let mut backup: BackupFile = serde_json::from_value(v).unwrap();
    let stats = normalize_backup(&mut backup);
    assert_eq!(backup.memos.len(), 1);
    assert_eq!(backup.memos[0].doc.len(), 3);
    let out = serde_json::to_value(&backup).unwrap();
    // items 里 4 个无效条目全剔除；其余异常原样。
    assert_eq!(out["memos"][0]["doc"][0]["attrs"]["items"], json!([]));
    assert_eq!(out["memos"][0]["doc"][1]["fileId"], json!({ "x": 1 }));
    assert_eq!(out["memos"][0]["doc"][2]["level"], json!([3]));
    assert_eq!(stats.gallery_items_dropped, 4);
}

/// 仓库外验收 ZIP（与 tests/backup_zip.rs 同口径：缺失即跳过）。
fn acceptance_zip(name: &str) -> Option<Vec<u8>> {
    let dir = std::env::var_os("MYNOTE_ZIP_ACCEPTANCE_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(format!(
                "{}/../../../../mynote-zip-acceptance",
                env!("CARGO_MANIFEST_DIR")
            ))
        });
    let path = dir.join(name);
    match std::fs::read(&path) {
        Ok(bytes) => Some(bytes),
        Err(_) => {
            eprintln!("acceptance zip missing, skipped: {}", path.display());
            None
        }
    }
}

/// 存量扫描：仓库内真实夹具 dry-run。结论口径只对夹具 proven
/// （真实夹具普查见 refactor_remove_compat §2.8：块类型只有
/// paragraph/attachment、id 均为字符串）；用户真机存量不在
/// 本机可达范围，真机证据由 D3 首启迁移的 Diag 统计行给出。
#[test]
fn stock_scan_fixtures() {
    for name in ["real_memos.json", "flutter_memos.json"] {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        let backup: BackupFile = serde_json::from_slice(&bytes).unwrap();
        let stats = dry_run_backup(&backup);
        println!("scan {name}: {} | census {}", stats.summary(), stats.census_summary());
        assert_eq!(stats.music_blocks, 0, "{name} 不应含 music 旧名");
        assert_eq!(stats.code_blocks, 0, "{name} 不应含 code 旧名");
        assert!(
            stats
                .block_types
                .keys()
                .all(|k| k == "paragraph" || k == "attachment"),
            "{name} 块类型普查与盘点不符: {:?}",
            stats.block_types
        );
    }
    for name in ["real_backup.zip", "flutter_export.zip"] {
        let Some(bytes) = acceptance_zip(name) else {
            continue;
        };
        let pkg = read_backup_zip(&bytes).unwrap();
        let stats = dry_run_backup(&pkg.backup);
        println!(
            "scan {name}: {} | census {}",
            stats.summary(),
            stats.census_summary()
        );
        assert_eq!(stats.music_blocks, 0, "{name} 不应含 music 旧名");
        assert_eq!(stats.code_blocks, 0, "{name} 不应含 code 旧名");
    }
}
