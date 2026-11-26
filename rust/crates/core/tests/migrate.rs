//! 一次性迁移通道（core::migrate）的集成测试：旧形态夹具逐项
//! 归一断言、幂等、坏数据不毁、avatars 不触碰；以及借 dry-run
//! 对仓库内真实夹具（与仓库外验收 ZIP，在位时）的存量扫描。
//! 通道作用于模型解析前的原始 JSON（Value）——夹具因此保持
//! Value 形态，归一后再交模型解析做类型侧断言。

use moment_core::migrate::{
    dry_run_value, manifest_parse_lenient, normalize_manifest_value, normalize_value,
    MigrationStats,
};
use moment_core::{read_backup_zip_migrated, BackupFile, Manifest};
use serde_json::{json, Value};

/// 全旧形态夹具。doc 下标即断言坐标（见各用例注释）。
fn legacy_backup() -> Value {
    json!({
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
                    // 13: attrs 非对象 + 顶层 level → attrs 整键
                    // 剔除后 level 正常搬入（§2.2 类型化口径：
                    // 非对象 attrs 模型容不下，不再原样保留）
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
    })
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
    let mut v = legacy_backup();
    let stats = normalize_value(&mut v);
    // 通道级原值（模型解析前）：未建模键的保留在此层核对。
    let raw_doc = v["memos"][0]["doc"].clone();
    // 归一后必须能被单形化模型严格解析（通道与主线的契约）。
    let backup: BackupFile =
        serde_json::from_value(v).expect("normalized backup parses under strict model");

    // 备忘级：数字 id → 字符串；毫秒时间戳 → ISO（同瞬间）。
    let m0 = &backup.memos[0];
    assert_eq!(m0.id.to_string(), "12345");
    assert_eq!(m0.created_at.to_millis(), Some(1778254999257));
    assert_eq!(m0.created_at.as_str(), "2026-05-08T15:43:19.257Z");

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
    // 13: 非对象 attrs 剔除、顶层 level 搬入新 attrs。
    assert_eq!(d[13]["attrs"]["level"], json!(4));
    assert!(d[13].get("level").is_none());
    // 14: 顶层 fileId 非字符串 → 通道级原样保留（通道不销毁），
    // 模型级不再承载（顶层 fileId 已退役、只认 attrs.fileId）。
    assert_eq!(raw_doc[14]["fileId"], json!(777));
    assert!(d[14].get("fileId").is_none());

    // avatars 与 exportedAt 不触碰。
    assert_eq!(
        backup.avatars,
        Some(json!({ "memo-x": { "nested": [1, 2, 3] } }))
    );
    assert_eq!(
        backup.exported_at.as_ref().map(|t| t.as_str()),
        Some("2026-01-01T00:00:00.000Z")
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
    assert_eq!(stats.level_moved, 2, "case 0 搬入 + case 13 在 attrs 剔除后搬入");
    assert_eq!(stats.level_cleared, 1);
    assert_eq!(stats.checked_moved, 1);
    assert_eq!(stats.checked_cleared, 1);
    assert_eq!(stats.music_blocks, 1);
    assert_eq!(stats.code_blocks, 1);
    assert_eq!(stats.strike_marks, 3);
    assert_eq!(stats.fields_normalized, 1, "仅 case 13 的非对象 attrs 整键剔除");
    assert_eq!(stats.total_changes(), 24);
    // 普查记原始名：music/code 以旧名入账。
    assert_eq!(stats.block_types.get("music"), Some(&1));
    assert_eq!(stats.block_types.get("code"), Some(&1));
    assert_eq!(stats.block_types.get("gallery"), Some(&3));
}

#[test]
fn callout_legacy_names_rename_in_channel() {
    // callout 变体旧名 kind/variant 只在迁移通道改名为
    // calloutType（§2.7）：主线只读 calloutType，归一口径与
    // 旧三级回退读链（calloutType → kind → variant，各取
    // 字符串值）严格等价。
    let mut v = json!({
        "version": 2,
        "memos": [{
            "id": "c1",
            "createdAt": "2026-05-08T15:43:19.257Z",
            "updatedAt": "2026-05-08T15:43:19.257Z",
            "doc": [
                // 0: 只有 kind → 搬为 calloutType
                { "type": "callout", "id": "k1", "kind": "warning",
                  "children": [{ "text": "x" }] },
                // 1: 只有 variant → 搬为 calloutType
                { "type": "callout", "id": "k2", "variant": "tip",
                  "children": [{ "text": "x" }] },
                // 2: kind + variant → kind 优先，variant 影子清除
                { "type": "callout", "id": "k3", "kind": "caution", "variant": "tip",
                  "children": [{ "text": "x" }] },
                // 3: calloutType 已在 + 两旧名 → 原生值胜，旧名全清
                { "type": "callout", "id": "k4", "calloutType": "important",
                  "kind": "warning", "variant": "tip",
                  "children": [{ "text": "x" }] },
                // 4: kind 非字符串 + variant 字符串 → variant 生效，
                //    kind 无法解读原样保留（通道不销毁）
                { "type": "callout", "id": "k5", "kind": 7, "variant": "warning",
                  "children": [{ "text": "x" }] },
                // 5: 非 callout 块的 kind 从未被读路径消费 → 不动
                { "type": "paragraph", "id": "k6", "kind": "warning",
                  "children": [{ "text": "x" }] },
                // 6: 嵌套 callout（递归）同样改名
                { "type": "quote", "id": "k7",
                  "children": [
                      { "type": "callout", "id": "k8", "variant": "note",
                        "children": [{ "text": "x" }] }
                  ] }
            ]
        }]
    });
    let stats = normalize_value(&mut v);
    // 通道级原值（模型解析前）：非字符串旧名与非 callout 块
    // 的 kind 在此层核对——类型化模型不再承载 kind 键本身。
    let raw_doc = v["memos"][0]["doc"].clone();
    let backup: BackupFile =
        serde_json::from_value(v).expect("normalized backup parses under strict model");
    let d = doc(&backup);
    assert_eq!(d[0]["calloutType"], json!("warning"));
    assert!(d[0].get("kind").is_none());
    assert_eq!(d[1]["calloutType"], json!("tip"));
    assert!(d[1].get("variant").is_none());
    assert_eq!(d[2]["calloutType"], json!("caution"));
    assert!(d[2].get("kind").is_none());
    assert!(d[2].get("variant").is_none());
    assert_eq!(d[3]["calloutType"], json!("important"));
    assert!(d[3].get("kind").is_none());
    assert!(d[3].get("variant").is_none());
    assert_eq!(d[4]["calloutType"], json!("warning"));
    assert_eq!(raw_doc[4]["kind"], json!(7), "非字符串旧名在通道级原样保留");
    assert!(d[4].get("kind").is_none(), "模型不再承载 kind 键（§2.2 透传退役）");
    assert!(d[4].get("variant").is_none());
    assert_eq!(raw_doc[5]["kind"], json!("warning"), "非 callout 块通道不改名");
    assert!(d[5].get("kind").is_none(), "模型不再承载 kind 键（§2.2 透传退役）");
    assert!(d[5].get("calloutType").is_none());
    let nested = &d[6]["children"][0];
    assert_eq!(nested["calloutType"], json!("note"));
    assert!(nested.get("variant").is_none());
    // moved: k1/k2/k3/k5/k8；cleared: k3 的 variant + k4 的两旧名。
    assert_eq!(stats.callout_moved, 5);
    assert_eq!(stats.callout_cleared, 3);
    assert!(
        stats.summary().contains("callout_move=5 callout_clear=3"),
        "summary 口径: {}",
        stats.summary()
    );
    // 幂等：已归一（含保留的非字符串 kind 与非 callout kind）
    // 重跑零命中。
    let mut v2 = serde_json::to_value(&backup).unwrap();
    let stats2 = normalize_value(&mut v2);
    assert_eq!(stats2.total_changes(), 0);
}

#[test]
fn numeric_exported_at_normalizes_in_channel() {
    // exportedAt 类型化（§2.2）后的契约：毫秒数形模型直解
    // 拒绝、迁移通道归一为 ISO 后可解；字符串形通道不动。
    let mut v = json!({
        "version": 2,
        "exportedAt": 1778254999257i64,
        "memos": []
    });
    assert!(
        serde_json::from_value::<BackupFile>(v.clone()).is_err(),
        "strict model must reject millis exportedAt"
    );
    let stats = normalize_value(&mut v);
    assert_eq!(stats.millis_timestamps, 1);
    let backup: BackupFile = serde_json::from_value(v).unwrap();
    assert_eq!(
        backup.exported_at.as_ref().map(|t| t.as_str()),
        Some("2026-05-08T15:43:19.257Z")
    );
    assert_eq!(backup.exported_at.as_ref().and_then(|t| t.to_millis()), Some(1778254999257));
}

#[test]
fn normalize_is_idempotent() {
    let mut v = legacy_backup();
    normalize_value(&mut v);
    let once = v.clone();
    let stats2 = normalize_value(&mut v);
    assert_eq!(stats2.total_changes(), 0, "已归一数据重跑必须零命中");
    assert_eq!(v, once);
}

#[test]
fn dry_run_does_not_mutate() {
    let v = legacy_backup();
    let before = v.clone();
    let dry = dry_run_value(&v);
    assert_eq!(v, before);
    let mut clone = v.clone();
    let real = normalize_value(&mut clone);
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
    let mut out = v;
    let stats = normalize_value(&mut out);
    assert_eq!(out["memos"].as_array().unwrap().len(), 1);
    assert_eq!(out["memos"][0]["doc"].as_array().unwrap().len(), 3);
    // items 里 4 个无效条目全剔除；未建模的顶层 fileId 异常
    // 值原样（通道不销毁、模型侧不再承载）；顶层 level 为
    // 不可解读的数组——旧口径靠 extra 透传保真，§2.2 透传
    // 退役后无处承载：搬入 attrs 后被字段类型归一剔除，
    // 读取回落默认 level 2。
    assert_eq!(out["memos"][0]["doc"][0]["attrs"]["items"], json!([]));
    assert_eq!(out["memos"][0]["doc"][1]["fileId"], json!({ "x": 1 }));
    assert!(out["memos"][0]["doc"][2].get("level").is_none());
    assert!(out["memos"][0]["doc"][2]["attrs"].get("level").is_none());
    assert_eq!(stats.gallery_items_dropped, 4);
}

/// 仓库外验收 ZIP（与 tests/backup_zip.rs 同口径：缺失即跳过）。
fn acceptance_zip(name: &str) -> Option<Vec<u8>> {
    let dir = std::env::var_os("MOMENT_ZIP_ACCEPTANCE_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(format!(
                "{}/../../../../moment-zip-acceptance",
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

/// 存量扫描：仓库内脱敏样本夹具 dry-run（T-3 语料，由真实
/// 备份结构派生，见 fixtures/README.md）。结论口径只对夹具
/// proven（样本普查见 refactor_remove_compat §2.8：块类型只有
/// paragraph/attachment、id 均为字符串）；用户真机存量不在
/// 本机可达范围，真机证据由 D3 首启迁移的 Diag 统计行给出。
#[test]
fn stock_scan_fixtures() {
    for name in ["sample_memos.json", "sample_flutter_memos.json"] {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        let backup: Value = serde_json::from_slice(&bytes).unwrap();
        let stats = dry_run_value(&backup);
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
        // 验收 ZIP 经迁移通道读（D2 入口）：stats 即归一命中，
        // 通道读通本身就是旧形态可归一的回归证据。
        let (_pkg, stats) = read_backup_zip_migrated(&bytes).unwrap();
        println!(
            "scan {name}: {} | census {}",
            stats.summary(),
            stats.census_summary()
        );
        assert_eq!(stats.music_blocks, 0, "{name} 不应含 music 旧名");
        assert_eq!(stats.code_blocks, 0, "{name} 不应含 code 旧名");
    }
}

#[test]
fn manifest_dict_form_normalizes_fields() {
    // 字典形旧 manifest：根级多余键、条目多余键、type 缺失、
    // name 非字符串、非对象条目——逐项归一并计数。
    let mut v = json!({
        "version": 1,
        "legacyRoot": true,
        "attachments": {
            "a1": { "name": "x.png", "type": "image/png", "size": 42 },
            "b2": { "name": "y.pdf" },
            "c3": { "name": 7, "type": "text/plain" },
            "d4": "not-an-object"
        }
    });
    let mut stats = MigrationStats::default();
    normalize_manifest_value(&mut v, &mut stats);
    assert_eq!(
        v,
        json!({
            "version": 1,
            "attachments": {
                "a1": { "name": "x.png", "type": "image/png" },
                "b2": { "name": "y.pdf", "type": "" },
                "c3": { "name": "", "type": "text/plain" }
            }
        })
    );
    assert_eq!(stats.manifest_form_fixes, 0);
    assert_eq!(stats.manifest_entries_dropped, 1);
    // 根级 1 + a1 多余键 1 + b2 补 type 1 + c3 name 改空串 1
    assert_eq!(stats.manifest_fields_normalized, 4);
    // 归一后模型可解析，且重跑零命中（幂等）。
    let parsed: Manifest = serde_json::from_value(v.clone()).unwrap();
    assert_eq!(parsed.attachments.len(), 3);
    let mut stats2 = MigrationStats::default();
    normalize_manifest_value(&mut v, &mut stats2);
    assert_eq!(stats2.total_changes(), 0, "已归一 manifest 重跑必须零命中");
}

#[test]
fn manifest_array_and_missing_forms() {
    // 数组形：条目以自带 id 为键；无 id 与非对象条目剔除。
    let mut v = json!({
        "version": 1,
        "attachments": [
            { "id": "a1", "name": "x.png", "type": "image/png" },
            { "name": "no-id.png", "type": "image/png" },
            42
        ]
    });
    let mut stats = MigrationStats::default();
    normalize_manifest_value(&mut v, &mut stats);
    assert_eq!(
        v,
        json!({
            "version": 1,
            "attachments": { "a1": { "name": "x.png", "type": "image/png" } }
        })
    );
    assert_eq!(stats.manifest_form_fixes, 1);
    assert_eq!(stats.manifest_entries_dropped, 2);

    // attachments 缺失 / null → 补空字典（§2.12 数组回退形
    // 的空数组同样收为 {}）。
    for mut v in [
        json!({ "version": 1 }),
        json!({ "version": 1, "attachments": null }),
        json!({ "version": 1, "attachments": [] }),
    ] {
        let mut stats = MigrationStats::default();
        normalize_manifest_value(&mut v, &mut stats);
        assert_eq!(v, json!({ "version": 1, "attachments": {} }));
        assert_eq!(stats.manifest_form_fixes, 1);
    }

    // 根非对象：原样保留、零命中（模型解析会拒）。
    let mut v = json!("garbage");
    let mut stats = MigrationStats::default();
    normalize_manifest_value(&mut v, &mut stats);
    assert_eq!(v, json!("garbage"));
    assert_eq!(stats.total_changes(), 0);
}

#[test]
fn manifest_lenient_parse_paths() {
    // 原生形直解。
    let m = manifest_parse_lenient(
        r#"{"version":1,"attachments":{"a1":{"name":"x.png","type":"image/png"}}}"#,
    )
    .unwrap();
    assert_eq!(m.attachments["a1"].name, "x.png");
    assert_eq!(m.attachments["a1"].mime, "image/png");
    // 旧形经通道归一后解出。
    let m = manifest_parse_lenient(
        r#"{"version":1,"attachments":[{"id":"a1","name":"x.png","type":"image/png"}]}"#,
    )
    .unwrap();
    assert_eq!(m.attachments.len(), 1);
    // 全坏 → None（调用方回退空清单）。
    assert!(manifest_parse_lenient("not json").is_none());
    assert!(manifest_parse_lenient(r#"{"attachments":{}}"#).is_none());
}
