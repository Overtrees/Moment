//! §2.2 模型类型化口径锁：
//! ① 旧形（twoPane、浮点 level/deletedAt、备忘/节点/根级
//!    未知键）经 core::migrate 通道归一后可被类型模型直读，
//!    字段落位正确；
//! ② 主线直读类型字段（callout_type / attrs / layout /
//!    deleted_at / bg_color），序列化键名与原生格式一致；
//! ③ 透传退役：未知键解析后不再往返；avatars 例外保留
//!    （用户硬约束：不建模、原样透传）；
//! ④ 通道对新归一形态幂等（第二趟零命中）。

use mynote_core::migrate::normalize_value;
use mynote_core::{BackupFile, Memo};
use serde_json::{json, Value};

fn legacy_backup() -> Value {
    json!({
        "version": 2,
        "exportedAt": "2026-01-01T00:00:00.000Z",
        "futureRootKey": {"x": 1},
        "avatars": {"m1": "data:image/png;base64,AAAA"},
        "memos": [{
            "id": "m1",
            "title": "旧形样本",
            "createdAt": "2026-01-01T00:00:00.000Z",
            "updatedAt": "2026-01-02T00:00:00.000Z",
            "deletedAt": 1767225600000.0,
            "bgColor": "#eaeef2",
            "layout": {"twoPane": true, "left": ["b1", 7, "b2"], "right": "oops", "junk": 1},
            "memoJunk": [1, 2],
            "doc": [
                {"type": "heading", "id": "b1", "attrs": {"level": 3.0},
                 "children": [{"text": "题"}]},
                {"type": "callout", "id": "b2", "kind": "warning",
                 "children": [{"text": "注"}]},
                {"type": "musicCard", "id": "b3", "url": "https://example.com/s",
                 "meta": {"title": "歌"}, "status": "ready", "nodeJunk": "x"},
                {"type": "image", "id": "b4", "attrs": {"fileId": "f1"}}
            ]
        }]
    })
}

#[test]
fn legacy_shapes_normalize_into_typed_fields() {
    let mut v = legacy_backup();
    let stats = normalize_value(&mut v);
    assert!(stats.layout_normalized >= 1, "layout 归一应命中: {stats:?}");
    assert!(stats.fields_normalized >= 1, "字段归一应命中: {stats:?}");

    let backup: BackupFile = serde_json::from_value(v).expect("归一后可解析");
    let memo = &backup.memos[0];
    // layout：twoPane → mode，名单只留字符串，坏 right 剔除。
    let layout = memo.layout.as_ref().expect("layout 类型化");
    assert_eq!(layout.mode.as_deref(), Some("independent"));
    assert_eq!(
        layout.left.as_deref(),
        Some(&["b1".to_string(), "b2".to_string()][..])
    );
    assert_eq!(layout.right, None);
    // 备忘级类型字段。
    assert_eq!(memo.deleted_at, Some(1767225600000));
    assert_eq!(memo.bg_color.as_deref(), Some("#eaeef2"));
    // 节点级类型字段。
    assert_eq!(memo.doc[0].attrs.level, Some(3));
    assert_eq!(memo.doc[1].callout_type.as_deref(), Some("warning"));
    assert_eq!(memo.doc[2].url.as_deref(), Some("https://example.com/s"));
    assert_eq!(memo.doc[2].status.as_deref(), Some("ready"));
    assert_eq!(
        memo.doc[2].meta.as_ref().and_then(|m| m.get("title")).and_then(|t| t.as_str()),
        Some("歌")
    );
    assert_eq!(memo.doc[3].attrs.file_id.as_deref(), Some("f1"));
    // avatars 保留透传（不建模）。
    assert_eq!(
        backup.avatars.as_ref().and_then(|a| a.get("m1")).and_then(|x| x.as_str()),
        Some("data:image/png;base64,AAAA")
    );
}

#[test]
fn unknown_keys_do_not_round_trip() {
    let mut v = legacy_backup();
    normalize_value(&mut v);
    let backup: BackupFile = serde_json::from_value(v).unwrap();
    let out = serde_json::to_value(&backup).unwrap();
    let s = out.to_string();
    for retired in [
        "futureRootKey",
        "memoJunk",
        "nodeJunk",
        "twoPane",
        "\"junk\"",
        "kind",
    ] {
        assert!(!s.contains(retired), "退役键 {retired} 不得往返: {s}");
    }
    // 已建模键以规范名往返。
    for kept in [
        "calloutType",
        "fileId",
        "deletedAt",
        "bgColor",
        "\"layout\"",
        "\"mode\":\"independent\"",
        "avatars",
    ] {
        assert!(s.contains(kept), "规范键 {kept} 应在位: {s}");
    }
}

#[test]
fn mainline_parse_drops_unknown_keys_without_channel() {
    // 主线直读（不经通道）同样不承载未知键：解析即丢弃，
    // 不再有 flatten 透传。
    let memo: Memo = serde_json::from_value(json!({
        "id": "mx",
        "createdAt": "2026-01-01T00:00:00.000Z",
        "updatedAt": "2026-01-01T00:00:00.000Z",
        "someFutureKey": {"deep": true},
        "doc": [{"type": "paragraph", "id": "p1", "alien": 1,
                 "children": [{"text": "正文", "bold": true}]}]
    }))
    .expect("未知键不挡解析");
    let out = serde_json::to_value(&memo).unwrap().to_string();
    assert!(!out.contains("someFutureKey"), "{out}");
    assert!(!out.contains("alien"), "{out}");
    // 已建模的行内标记仍在位。
    assert!(out.contains("\"bold\":true"), "{out}");
}

#[test]
fn channel_idempotent_on_new_normalizations() {
    let mut v = legacy_backup();
    let first = normalize_value(&mut v);
    assert!(first.total_changes() > 0);
    let snapshot = v.clone();
    let second = normalize_value(&mut v);
    assert_eq!(second.total_changes(), 0, "第二趟须零命中: {second:?}");
    assert_eq!(v, snapshot, "第二趟不得改动数据");
}
