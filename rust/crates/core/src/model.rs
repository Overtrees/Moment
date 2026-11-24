//! 文档模型：逐字段镜像现有块 JSON 格式（原版 Web 应用与 Flutter 版
//! 共用的那一份），不新造格式。任何本模型尚未显式建模的字段都经
//! `extra` 透传，保证往返序列化无损——格式的事实标准是现网数据，
//! 不是本文件。

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// 笔记 id：只认字符串形（去兼容第四步单形化，
/// refactor_remove_compat §2.1）。数字形只在迁移通道
/// （core::migrate，作用于模型解析前的 serde_json::Value）
/// 归一为字符串；模型解析期遇到数字 id 直接失败，旧备份/
/// 旧存量必须先过通道，不再双形保真。
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Id(pub String);

impl Id {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for Id {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// 时间戳：只认 ISO-8601 字符串形（同 §2.1 单形化）。毫秒数
/// 只在迁移通道归一；`from_millis` 是全仓唯一的毫秒入口，
/// 供迁移通道与种子/新建路径把毫秒换算为 ISO（毫秒精度、
/// Z 后缀，与原版 `Date::toISOString()` 同形）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Timestamp(pub String);

impl Timestamp {
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// 换算为毫秒 epoch；ISO 解析失败时返回 None（不猜）。
    pub fn to_millis(&self) -> Option<i64> {
        chrono::DateTime::parse_from_rfc3339(&self.0)
            .ok()
            .map(|dt| dt.timestamp_millis())
    }

    /// 毫秒 epoch → ISO 时间戳；超出 chrono 可表范围返回
    /// None（调用方保留原值/自行处置，不销毁）。
    pub fn from_millis(millis: i64) -> Option<Self> {
        use chrono::TimeZone;
        chrono::Utc
            .timestamp_millis_opt(millis)
            .single()
            .map(|dt| Timestamp(dt.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)))
    }
}

impl std::fmt::Display for Timestamp {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// 一条笔记。`doc` 是块数组；备忘级扩展（如 layout）走 `extra`。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Memo {
    pub id: Id,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pinned: Option<bool>,
    #[serde(rename = "createdAt")]
    pub created_at: Timestamp,
    #[serde(rename = "updatedAt")]
    pub updated_at: Timestamp,
    #[serde(default)]
    pub doc: Vec<Node>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// 文档节点：行内文本与块共用一个形状，与线上 JSON 一致。
/// 有 `text` 而无 `type` 的是行内文本节点；有 `type` 的是块。
/// 块的专有字段（卡片的 url/status/meta、附件的 fileId、图片的
/// attrs 等）一律经 `extra` 透传，待编辑器内核阶段再逐类建模。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Node {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(rename = "type", default, skip_serializing_if = "Option::is_none")]
    pub node_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub children: Option<Vec<Node>>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl Node {
    pub fn is_text(&self) -> bool {
        self.node_type.is_none() && self.text.is_some()
    }

    pub fn is_block(&self) -> bool {
        self.node_type.is_some()
    }

    /// 块类型名（paragraph / heading / todo / image / link-card …）。
    pub fn block_type(&self) -> Option<&str> {
        self.node_type.as_deref()
    }

    /// 节点的纯文本（行内节点取自身，块递归拼接子节点）。
    pub fn plain_text(&self) -> String {
        let mut out = String::new();
        if let Some(t) = &self.text {
            out.push_str(t);
        }
        if let Some(children) = &self.children {
            for c in children {
                out.push_str(&c.plain_text());
            }
        }
        out
    }
}

impl Memo {
    /// 全文纯文本（搜索索引与摘要用）。
    pub fn plain_text(&self) -> String {
        self.doc.iter().map(|n| n.plain_text()).collect()
    }
}
