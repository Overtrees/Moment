//! 文档模型：逐字段镜像现有块 JSON 格式（原版 Web 应用与 Flutter 版
//! 共用的那一份），不新造格式。§2.2 模型类型化（refactor_remove_
//! compat）收尾起，模型即格式的全部承载：备忘/节点/attrs 的已知
//! 字段全部类型化，未知键不再经 `extra` 透传往返（解析时忽略、
//! 序列化不产出）；旧形态（字段位置/类型/旧名）只在迁移通道
//! （core::migrate，模型解析前的 Value 级）归一。唯一保留的
//! 不建模透传是 BackupFile.avatars（头像功能数据通道，用户
//! 硬约束，见 backup.rs）。

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// 笔记 id：只认字符串形（去兼容第四步单形化，
/// refactor_remove_compat §2.1）。数字形只在迁移通道
/// （core::migrate，作用于模型解析前的 serde_json::Value）
/// 归一为字符串；模型解析期遇到数字 id 直接失败，旧备份/
/// 旧存量必须先过通道，不再双形保真。
#[derive(Debug, Clone, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
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
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
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

/// 一条笔记。`doc` 是块数组；备忘级字段（layout/deletedAt/
/// bgColor）已全部类型化（§2.2），未知键不再透传。
/// Default 仅供结构体更新语法补齐可选字段（id/时间戳的
/// 空默认不作真实值使用，构造点恒显式赋值）。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub layout: Option<MemoLayout>,
    /// 软删待删标记（批 12 U3）：删除时刻（毫秒 epoch）。
    /// 在位 = 处于撤销窗口内，各消费面排除该篇；超时真删。
    #[serde(rename = "deletedAt", default, skip_serializing_if = "Option::is_none")]
    pub deleted_at: Option<i64>,
    /// 编辑页背景色（原版备忘级 bgColor 字段）。
    #[serde(rename = "bgColor", default, skip_serializing_if = "Option::is_none")]
    pub bg_color: Option<String>,
}

/// 备忘双栏布局锚：`{version, mode, left, right}`——left/right
/// 为两栏的块 id 名单（数据骨架是一份有序文档 + 名单归一为
/// 前缀/后缀分界）。写入方（编辑器落锚）只产此形；旧形
/// （twoPane、名单含非字符串、未知键）只在迁移通道归一。
/// left/right 用 Option 承载：分界归一的旧口径要求两键都在
/// 才认锚，缺失与空名单须可区分（缺失不落键）。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct MemoLayout {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub left: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub right: Option<Vec<String>>,
}

/// 节点 attrs（原版节点工厂的字段位）：heading 的 level、
/// todo 的 checked、媒体的 fileId、gallery 的 items、有序
/// 列表的 start、行内链接的 href、图片直链的 url。§2.2 类
/// 型化：主线只认本结构；未知键解析时忽略、不再往返，
/// 类型不合值只在迁移通道归一。空 attrs 不落键（与编辑器
/// 既有「attrs 删空整键移除」口径一致）。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Attrs {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub level: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub checked: Option<bool>,
    #[serde(rename = "fileId", default, skip_serializing_if = "Option::is_none")]
    pub file_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items: Option<Vec<GalleryEntry>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub href: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    /// 装饰分割线的文字（decorative_divider 的 attrs.text，
    /// 原版形态；导出侧读取，本应用编辑器无此块的写路径）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

impl Attrs {
    pub fn is_empty(&self) -> bool {
        self.level.is_none()
            && self.checked.is_none()
            && self.file_id.is_none()
            && self.items.is_none()
            && self.start.is_none()
            && self.href.is_none()
            && self.url.is_none()
            && self.text.is_none()
    }
}

/// gallery 条目（归一形态）：`{fileId}` / `{url}` 对象
/// （读者口径 fileId 优先，与原版解析序一致）。裸字符串
/// 等旧形只在迁移通道归一。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct GalleryEntry {
    #[serde(rename = "fileId", default, skip_serializing_if = "Option::is_none")]
    pub file_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

/// 文档节点：行内文本与块共用一个形状，与线上 JSON 一致。
/// 有 `text` 而无 `type` 的是行内文本节点；有 `type` 的是块。
/// 块的专有字段已全部类型化（§2.2）：attrs 见 [`Attrs`]；
/// 卡片的 url/status/meta、附件的 name/image、callout 的
/// calloutType、行内标记（bold 等）与行内链接 url 都在本
/// 结构上，未知键不再透传。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Node {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(rename = "type", default, skip_serializing_if = "Option::is_none")]
    pub node_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub children: Option<Vec<Node>>,
    #[serde(default, skip_serializing_if = "Attrs::is_empty")]
    pub attrs: Attrs,
    #[serde(rename = "calloutType", default, skip_serializing_if = "Option::is_none")]
    pub callout_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    /// 卡片元数据（音乐/链接卡的 provider 载荷）：产品数据
    /// 本体，内容随来源服务变化、不逐键建模；字段本身的
    /// 在位与值由模型承载。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub meta: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
    /// 附件块的图片标记（image:true 时按图片行渲染/派生封面）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bold: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub italic: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub underline: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub strikethrough: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<bool>,
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
