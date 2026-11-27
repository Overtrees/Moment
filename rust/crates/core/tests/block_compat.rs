//! 真块型往返契约（plan_web_native_block_compat §2 G5 / §3
//! 验收 1·2·5）：落盘形态以原生真块型为正（用户
//! 2026-11-27 裁定）——含真 codeBlock / callout /
//! bulleted-list·numbered-list 的文档经类型化模型解析 →
//! 序列化必须逐块深等；编辑无关块不得殃及三类块子树；
//! 存量 MD 源段落（段落宇宙）往返与迁移归一均不得变形。
//! 本文件只守模型层契约（加载/落盘保真），转换产出同形
//! 由 apps/web 的 ops/export 测试守（§3 验收 3·4）。

use moment_core::migrate::normalize_value;
use moment_core::BackupFile;
use serde_json::Value;

/// 夹具（§3 夹具单源的代码级部分）：真块型全集——多行
/// 代码（含反引号、带标记 runs）、五变体 callout、
/// start=3 的有序列表（嵌套无序子列表）、带标记与链接
/// 的无序列表、一篇可编辑的普通段落；外加一篇纯存量
/// MD 源段落文档（围栏/Callout 头/列表源形）。
const FIXTURE: &str = r#"{
  "version": 2,
  "memos": [
    {
      "id": "memo-true-blocks",
      "title": "真块型夹具",
      "createdAt": "2026-11-27T00:00:00.000Z",
      "updatedAt": "2026-11-27T00:00:00.000Z",
      "doc": [
        {"type": "paragraph", "id": "p-intro", "children": [
          {"text": "开头"},
          {"text": "加粗", "bold": true},
          {"text": "段落"}
        ]},
        {"type": "codeBlock", "id": "b-code", "children": [
          {"text": "fn main() {\n"},
          {"text": "let s = \"``\";", "code": true},
          {"text": "\n}"}
        ]},
        {"type": "callout", "id": "b-note", "calloutType": "note", "children": [{"text": "提示一"}]},
        {"type": "callout", "id": "b-warning", "calloutType": "warning", "children": [{"text": "提示二"}]},
        {"type": "callout", "id": "b-tip", "calloutType": "tip", "children": [{"text": "提示三"}]},
        {"type": "callout", "id": "b-important", "calloutType": "important", "children": [{"text": "提示四"}]},
        {"type": "callout", "id": "b-caution", "calloutType": "caution", "children": [{"text": "提示五"}]},
        {"type": "numbered-list", "id": "b-num", "attrs": {"start": 3}, "children": [
          {"type": "list-item", "id": "b-num-1", "children": [{"text": "第三项"}]},
          {"type": "list-item", "id": "b-num-2", "children": [
            {"text": "第四项"},
            {"type": "bulleted-list", "id": "b-num-2-sub", "children": [
              {"type": "list-item", "id": "b-num-2-sub-1", "children": [{"text": "嵌套子项"}]}
            ]}
          ]}
        ]},
        {"type": "bulleted-list", "id": "b-bul", "children": [
          {"type": "list-item", "id": "b-bul-1", "children": [
            {"text": "父项"},
            {"text": "粗体", "bold": true},
            {"type": "link", "url": "https://example.com", "children": [{"text": "链接"}]}
          ]},
          {"type": "list-item", "id": "b-bul-2", "children": [{"text": "次项"}]}
        ]},
        {"type": "paragraph", "id": "p-editable", "children": [{"text": "可编辑段落"}]}
      ]
    },
    {
      "id": "memo-stock-source",
      "title": "存量源段落",
      "createdAt": "2026-11-27T00:00:00.000Z",
      "updatedAt": "2026-11-27T00:00:00.000Z",
      "doc": [
        {"type": "paragraph", "id": "s-code", "children": [{"text": "```\nlet x = 1;\n```"}]},
        {"type": "paragraph", "id": "s-callout", "children": [{"text": "> [!WARNING]\n> 小心"}]},
        {"type": "paragraph", "id": "s-bul", "children": [{"text": "- 甲\n- 乙"}]},
        {"type": "paragraph", "id": "s-num", "children": [{"text": "1. 甲\n2. 乙"}]}
      ]
    }
  ]
}"#;

fn fixture_value() -> Value {
    serde_json::from_str(FIXTURE).unwrap()
}

fn doc_of(backup: &Value, memo_idx: usize) -> Vec<Value> {
    backup["memos"][memo_idx]["doc"]
        .as_array()
        .unwrap()
        .clone()
}

fn block_by_id(doc: &[Value], id: &str) -> Value {
    doc.iter()
        .find(|n| n["id"] == id)
        .unwrap_or_else(|| panic!("block {id} missing"))
        .clone()
}

/// 验收 1（无编辑往返不变）：迁移通道对原生形零命中，
/// 类型化解析 → 序列化与原文逐块深等——钉「打开即改写」
/// 与未来未建模字段被静默吞噬（新字段若故意不建模，
/// 本测试红即提醒补建模）。
#[test]
fn true_blocks_roundtrip_deep_equal() {
    let mut v = fixture_value();
    let stats = normalize_value(&mut v);
    assert_eq!(
        stats.total_changes(),
        0,
        "native form must not be rewritten by migration: {}",
        stats.summary()
    );
    let backup: BackupFile = serde_json::from_value(v.clone()).expect("fixture parses");
    let back = serde_json::to_value(&backup).unwrap();
    for idx in 0..2 {
        assert_eq!(
            doc_of(&back, idx),
            doc_of(&v, idx),
            "memo {idx} doc must roundtrip deep-equal"
        );
    }
}

/// 验收 2（编辑他块不殃及）：只改一篇中的一个普通段落，
/// 三类真块子树逐字段与导入前等。
#[test]
fn editing_unrelated_block_preserves_true_blocks() {
    let v = fixture_value();
    let mut backup: BackupFile = serde_json::from_value(v.clone()).unwrap();
    let memo = &mut backup.memos[0];
    let para = memo
        .doc
        .iter_mut()
        .find(|n| n.id.as_deref() == Some("p-editable"))
        .expect("editable paragraph present");
    para.children = Some(vec![moment_core::Node {
        text: Some("改过的段落".to_string()),
        ..Default::default()
    }]);
    let back = serde_json::to_value(&backup).unwrap();
    let before = doc_of(&v, 0);
    let after = doc_of(&back, 0);
    for id in [
        "b-code",
        "b-note",
        "b-warning",
        "b-tip",
        "b-important",
        "b-caution",
        "b-num",
        "b-bul",
    ] {
        assert_eq!(
            block_by_id(&after, id),
            block_by_id(&before, id),
            "true block {id} must be untouched by unrelated edit"
        );
    }
    assert_eq!(
        block_by_id(&after, "p-editable")["children"][0]["text"],
        Value::String("改过的段落".into())
    );
}

/// 验收 5（存量不回退）：纯 MD 源段落篇往返逐字不变——
/// 段落宇宙与真块型共存无损，G1-G3 不碰段落形态。
#[test]
fn stock_source_paragraphs_roundtrip_unchanged() {
    let v = fixture_value();
    let backup: BackupFile = serde_json::from_value(v.clone()).unwrap();
    let back = serde_json::to_value(&backup).unwrap();
    assert_eq!(doc_of(&back, 1), doc_of(&v, 1));
}
