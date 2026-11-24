//! 一次性迁移通道（去兼容第三步，refactor_remove_compat §4 的
//! D2/D3）：把旧格式形态的文档一次性归一为 Rust 原生规范形，
//! 与主线读写分离——主线（渲染/导出/编辑）的双读点在本通道于
//! 真机跑过一轮后由第四步逐项收紧，本模块是那些收紧动作的
//! 统一前置。
//!
//! 归一的规范形（与现行写路径同口径）：
//! - 备忘 id：数字形 → 字符串形；时间戳：毫秒数 → ISO-8601
//!   （`YYYY-MM-DDTHH:MM:SS.mmmZ`，与原版 `toISOString()` 同形）；
//! - 附件 fileId：顶层 → `attrs.fileId`（读口径顶层优先，故以
//!   顶层值覆写 attrs 后删顶层；顶层空串只删顶层）；
//! - heading 的 level、todo 的 checked：顶层 → attrs（读口径
//!   attrs 优先，attrs 已有则顶层为影子值、只删顶层）；
//! - gallery 条目：`attrs.items` 统一为 `{fileId}` / `{url}`
//!   对象形（字符串形转换、读者会丢弃的无效条目剔除）；
//!   `attrs.items` 缺失/非数组时按 children 兜底读口径把子节点
//!   的 fileId 物化进 `attrs.items`（children 本身保留不动——
//!   读者一律 items 优先，物化后兜底不再命中，children 的清理由
//!   第四步随兜底删除一并处置）；
//! - 块类型旧名：`music` → `musicCard`、`code` → `codeBlock`；
//! - 行内标记旧名：`strike` → `strikethrough`（双名读已于第一
//!   步删除，迁移改名保住历史删除线）。
//!
//! 不触碰：`avatars`（首页/编辑页头像功能的数据，原样保留）、
//! 备忘与文件的 `extra` 其余键、manifest（第五步建模）、未知
//! 字段一律透传。归一是纯函数式变换：不动输入之外的任何状态，
//! 对已归一数据重跑命中恒为零（幂等），无法解读的异常值（非
//! 对象 attrs、非字符串 fileId 等）一律原样保留、不销毁。

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use crate::backup::BackupFile;
use crate::model::{Id, Node, Timestamp};

/// 一次归一的命中统计（dry-run 与实跑共用同一口径）：计数为
/// 「旧形态出现次数」，`total_changes` 为实际改动节点的总量级
/// （同一节点多处命中分别计数）。
#[derive(Debug, Default, Clone, PartialEq)]
pub struct MigrationStats {
    /// 扫描的备忘篇数。
    pub memos: usize,
    /// 扫描的节点总数（含行内文本节点）。
    pub nodes: usize,
    /// 数字形备忘 id 转字符串的个数。
    pub numeric_ids: usize,
    /// 毫秒数时间戳转 ISO 的个数（createdAt/updatedAt 分别计）。
    pub millis_timestamps: usize,
    /// 顶层 fileId 的值搬入 attrs 的节点数。
    pub file_id_moved: usize,
    /// 顶层 fileId 为空串、只删顶层的节点数。
    pub file_id_cleared: usize,
    /// gallery 字符串条目转 `{fileId}` 对象的个数。
    pub gallery_string_items: usize,
    /// gallery 由 children 兜底物化出 `attrs.items` 的节点数。
    pub gallery_children_forms: usize,
    /// gallery 条目中读者会丢弃的无效条目剔除数。
    pub gallery_items_dropped: usize,
    /// 顶层 level 搬入 attrs 的节点数。
    pub level_moved: usize,
    /// 顶层 level 被 attrs 影子覆盖、只删顶层的节点数。
    pub level_cleared: usize,
    /// 顶层 checked 搬入 attrs 的节点数。
    pub checked_moved: usize,
    /// 顶层 checked 被 attrs 影子覆盖、只删顶层的节点数。
    pub checked_cleared: usize,
    /// 块类型旧名 `music` 改 `musicCard` 的节点数。
    pub music_blocks: usize,
    /// 块类型旧名 `code` 改 `codeBlock` 的节点数。
    pub code_blocks: usize,
    /// 行内标记 `strike` 改名 `strikethrough` 的节点数。
    pub strike_marks: usize,
    /// 块类型普查（归一前的原始类型名 → 节点数），供存量扫描。
    pub block_types: BTreeMap<String, usize>,
}

impl MigrationStats {
    /// 实际改动总量（不含扫描计数 memos/nodes 与普查）。
    pub fn total_changes(&self) -> usize {
        self.numeric_ids
            + self.millis_timestamps
            + self.file_id_moved
            + self.file_id_cleared
            + self.gallery_string_items
            + self.gallery_children_forms
            + self.gallery_items_dropped
            + self.level_moved
            + self.level_cleared
            + self.checked_moved
            + self.checked_cleared
            + self.music_blocks
            + self.code_blocks
            + self.strike_marks
    }

    /// 单行摘要（Diag 与测试共用口径）。
    pub fn summary(&self) -> String {
        format!(
            "memos={} nodes={} num_id={} millis_ts={} fileid_move={} fileid_clear={} \
             gal_str={} gal_kids={} gal_drop={} level_move={} level_clear={} \
             checked_move={} checked_clear={} music={} code={} strike={} changed={}",
            self.memos,
            self.nodes,
            self.numeric_ids,
            self.millis_timestamps,
            self.file_id_moved,
            self.file_id_cleared,
            self.gallery_string_items,
            self.gallery_children_forms,
            self.gallery_items_dropped,
            self.level_moved,
            self.level_cleared,
            self.checked_moved,
            self.checked_cleared,
            self.music_blocks,
            self.code_blocks,
            self.strike_marks,
            self.total_changes(),
        )
    }

    /// 块类型普查单行（按类型名字典序）。
    pub fn census_summary(&self) -> String {
        self.block_types
            .iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect::<Vec<_>>()
            .join(" ")
    }
}

/// 递归统计节点数（含节点自身与全部后代）。
pub fn count_nodes(nodes: &[Node]) -> usize {
    nodes
        .iter()
        .map(|n| 1 + n.children.as_deref().map(count_nodes).unwrap_or(0))
        .sum()
}

/// 把一份备份的全部备忘归一为规范形（原地），返回命中统计。
/// 只改 `memos` 内的文档形态；`avatars`、`exportedAt` 与根
/// `extra` 原样不动。
pub fn normalize_backup(backup: &mut BackupFile) -> MigrationStats {
    let mut stats = MigrationStats::default();
    stats.memos = backup.memos.len();
    for memo in backup.memos.iter_mut() {
        if let Id::Num(n) = memo.id {
            memo.id = Id::Str(n.to_string());
            stats.numeric_ids += 1;
        }
        normalize_timestamp(&mut memo.created_at, &mut stats);
        normalize_timestamp(&mut memo.updated_at, &mut stats);
        for node in memo.doc.iter_mut() {
            normalize_node(node, &mut stats);
        }
    }
    stats
}

/// 只统计不改动：克隆后归一，返回命中统计（存量扫描口径）。
pub fn dry_run_backup(backup: &BackupFile) -> MigrationStats {
    let mut clone = backup.clone();
    normalize_backup(&mut clone)
}

fn normalize_timestamp(ts: &mut Timestamp, stats: &mut MigrationStats) {
    if let Timestamp::Millis(m) = *ts {
        if let Some(iso) = millis_to_iso(m) {
            *ts = Timestamp::Iso(iso);
            stats.millis_timestamps += 1;
        }
    }
}

/// 毫秒 epoch → ISO-8601（毫秒精度、Z 后缀，与原版
/// `Date::toISOString()` 同形）；超出 chrono 可表范围返回 None
/// （调用方保留原值不销毁）。
fn millis_to_iso(millis: i64) -> Option<String> {
    use chrono::TimeZone;
    chrono::Utc
        .timestamp_millis_opt(millis)
        .single()
        .map(|dt| dt.to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
}

fn normalize_node(node: &mut Node, stats: &mut MigrationStats) {
    stats.nodes += 1;
    // 普查记归一前的原始类型名（旧名命中在普查里也可见）。
    if let Some(ty) = node.node_type.clone() {
        *stats.block_types.entry(ty).or_default() += 1;
    }
    match node.node_type.as_deref() {
        Some("music") => {
            node.node_type = Some("musicCard".to_string());
            stats.music_blocks += 1;
        }
        Some("code") => {
            node.node_type = Some("codeBlock".to_string());
            stats.code_blocks += 1;
        }
        _ => {}
    }
    normalize_file_id(node, stats);
    move_top_to_attrs(node, "level", &mut stats.level_moved, &mut stats.level_cleared);
    move_top_to_attrs(
        node,
        "checked",
        &mut stats.checked_moved,
        &mut stats.checked_cleared,
    );
    normalize_strike(node, stats);
    if node.node_type.as_deref() == Some("gallery") {
        normalize_gallery(node, stats);
    }
    if let Some(children) = node.children.as_mut() {
        for child in children.iter_mut() {
            normalize_node(child, stats);
        }
    }
}

/// 取节点的 attrs 对象（须已存在且为对象；不存在时按 `create`
/// 决定是否新建）。attrs 存在但非对象时返回 None（异常形态，
/// 调用方跳过该节点的字段搬运、不销毁）。
fn attrs_mut<'a>(node: &'a mut Node, create: bool) -> Option<&'a mut Map<String, Value>> {
    if !node.extra.contains_key("attrs") {
        if !create {
            return None;
        }
        node.extra
            .insert("attrs".to_string(), Value::Object(Map::new()));
    }
    node.extra
        .get_mut("attrs")
        .and_then(|v| v.as_object_mut())
}

/// 顶层 fileId → attrs.fileId。读口径（blocks::file_id）顶层
/// 优先：顶层非空串即为生效值，覆写 attrs 后删顶层；顶层空串
/// 不生效，只删顶层、attrs 保留；顶层非字符串读者不认，原样
/// 保留不动。
fn normalize_file_id(node: &mut Node, stats: &mut MigrationStats) {
    let Some(raw) = node.extra.get("fileId") else {
        return;
    };
    let Some(value) = raw.as_str() else {
        return;
    };
    if value.is_empty() {
        node.extra.remove("fileId");
        stats.file_id_cleared += 1;
        return;
    }
    let value = value.to_string();
    if let Some(attrs) = attrs_mut(node, true) {
        attrs.insert("fileId".to_string(), Value::String(value));
        node.extra.remove("fileId");
        stats.file_id_moved += 1;
    }
}

/// 顶层键 → attrs 同名键（level/checked 共用）。读口径 attrs
/// 优先：attrs 已有同名键时顶层为影子值，只删顶层（cleared）；
/// attrs 没有时搬入（moved）；attrs 非对象时整项跳过、顶层
/// 原样保留。
fn move_top_to_attrs(node: &mut Node, key: &str, moved: &mut usize, cleared: &mut usize) {
    if !node.extra.contains_key(key) {
        return;
    }
    let attrs_has = node
        .extra
        .get("attrs")
        .and_then(|a| a.as_object())
        .map(|a| a.contains_key(key))
        .unwrap_or(false);
    if attrs_has {
        node.extra.remove(key);
        *cleared += 1;
        return;
    }
    // 先确认 attrs 可写再取顶层值，避免 attrs 非对象时把顶层
    // 值摘掉又无处安放。
    if attrs_mut(node, true).is_none() {
        return;
    }
    let value = node.extra.remove(key).unwrap_or(Value::Null);
    if let Some(attrs) = attrs_mut(node, false) {
        attrs.insert(key.to_string(), value);
        *moved += 1;
    }
}

/// 行内标记旧名 strike → strikethrough（生效值 = 两名任一为
/// 真，与旧双读 `strikethrough || strike` 同语义）。
fn normalize_strike(node: &mut Node, stats: &mut MigrationStats) {
    let Some(old) = node.extra.remove("strike") else {
        return;
    };
    stats.strike_marks += 1;
    let was_true = old.as_bool().unwrap_or(false);
    let existing_true = node
        .extra
        .get("strikethrough")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if was_true || existing_true {
        node.extra
            .insert("strikethrough".to_string(), Value::Bool(true));
    }
}

/// 块上的附件 id（与 blocks::file_id 同口径：顶层优先、其次
/// attrs、空串视为无）——gallery children 兜底物化专用。
fn node_file_id(node: &Node) -> Option<String> {
    if let Some(fid) = node.extra.get("fileId").and_then(|v| v.as_str()) {
        if !fid.is_empty() {
            return Some(fid.to_string());
        }
    }
    node.extra
        .get("attrs")
        .and_then(|a| a.get("fileId"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
}

/// gallery 条目归一（见模块头注）：items 数组在位则逐条转
/// 对象形；不在位（缺失/非数组）则按 children 兜底口径物化。
fn normalize_gallery(node: &mut Node, stats: &mut MigrationStats) {
    let has_items_array = node
        .extra
        .get("attrs")
        .and_then(|a| a.get("items"))
        .map(|v| v.is_array())
        .unwrap_or(false);
    if has_items_array {
        let Some(items) = node
            .extra
            .get_mut("attrs")
            .and_then(|a| a.get_mut("items"))
            .and_then(|v| v.as_array_mut())
        else {
            return;
        };
        let old = std::mem::take(items);
        let mut kept: Vec<Value> = Vec::with_capacity(old.len());
        for item in old {
            match item {
                Value::String(s) => {
                    if s.is_empty() {
                        stats.gallery_items_dropped += 1;
                    } else {
                        kept.push(json!({ "fileId": s }));
                        stats.gallery_string_items += 1;
                    }
                }
                Value::Object(obj) => {
                    let has_file = obj
                        .get("fileId")
                        .and_then(|v| v.as_str())
                        .map(|s| !s.is_empty())
                        .unwrap_or(false);
                    let has_url = obj
                        .get("url")
                        .and_then(|v| v.as_str())
                        .map(|s| !s.is_empty())
                        .unwrap_or(false);
                    if has_file || has_url {
                        kept.push(Value::Object(obj));
                    } else {
                        stats.gallery_items_dropped += 1;
                    }
                }
                _ => {
                    stats.gallery_items_dropped += 1;
                }
            }
        }
        *items = kept;
        return;
    }
    // children 兜底形：把子节点 fileId 物化进 attrs.items；
    // children 原样保留（读者 items 优先，兜底不再命中）。
    let fids: Vec<String> = node
        .children
        .as_deref()
        .unwrap_or(&[])
        .iter()
        .filter_map(node_file_id)
        .collect();
    if fids.is_empty() {
        return;
    }
    if let Some(attrs) = attrs_mut(node, true) {
        let items: Vec<Value> = fids
            .into_iter()
            .map(|f| json!({ "fileId": f }))
            .collect();
        attrs.insert("items".to_string(), Value::Array(items));
        stats.gallery_children_forms += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn millis_iso_roundtrip() {
        // 与真实样本同一瞬间（tests/timestamp.rs 同值）。
        let iso = millis_to_iso(1778254999257).expect("in range");
        assert_eq!(iso, "2026-05-08T15:43:19.257Z");
        assert_eq!(
            Timestamp::Iso(iso).to_millis(),
            Some(1778254999257),
            "归一后 ISO 必须换算回同一毫秒"
        );
        assert_eq!(millis_to_iso(0).as_deref(), Some("1970-01-01T00:00:00.000Z"));
    }
}
