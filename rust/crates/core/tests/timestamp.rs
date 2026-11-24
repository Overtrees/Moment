//! 时间戳/id 单形化（去兼容第四步，refactor_remove_compat
//! §2.1）：模型只认 ISO 字符串时间戳与字符串 id；毫秒入口
//! 只剩 Timestamp::from_millis（迁移通道与种子/新建共用）。

use mynote_core::model::{Id, Timestamp};

#[test]
fn iso_timestamps_convert_to_millis() {
    // 与真实样本同一时刻：memos.json 里该备忘 createdAt 的
    // ISO 写法指向的瞬间。
    let iso = Timestamp("2026-05-08T15:43:19.257Z".to_string());
    assert_eq!(iso.to_millis(), Some(1778254999257));
    // 微秒位（Flutter 导出形）截断到毫秒
    let micro = Timestamp("2026-11-19T06:18:34.470560Z".to_string());
    assert_eq!(micro.to_millis(), Some(1795069114470));
    // 坏输入不猜
    assert_eq!(Timestamp("not a date".to_string()).to_millis(), None);
}

#[test]
fn from_millis_is_the_only_millis_entry() {
    let ts = Timestamp::from_millis(1778254999257).expect("in range");
    assert_eq!(ts.as_str(), "2026-05-08T15:43:19.257Z");
    assert_eq!(ts.to_millis(), Some(1778254999257));
    assert_eq!(
        Timestamp::from_millis(42).map(|t| t.as_str().to_string()).as_deref(),
        Some("1970-01-01T00:00:00.042Z")
    );
}

#[test]
fn model_rejects_legacy_shapes() {
    // 数字形在模型解析期直接失败——旧形态只能过迁移通道。
    assert!(serde_json::from_value::<Timestamp>(serde_json::json!(1778254999257i64)).is_err());
    assert!(serde_json::from_value::<Id>(serde_json::json!(12345)).is_err());
    // 字符串形正常收下且序列化原样。
    let id: Id = serde_json::from_value(serde_json::json!("12345")).unwrap();
    assert_eq!(id.as_str(), "12345");
    assert_eq!(serde_json::to_value(&id).unwrap(), serde_json::json!("12345"));
    let ts: Timestamp =
        serde_json::from_value(serde_json::json!("2026-05-08T15:43:19.257Z")).unwrap();
    assert_eq!(
        serde_json::to_value(&ts).unwrap(),
        serde_json::json!("2026-05-08T15:43:19.257Z")
    );
}
