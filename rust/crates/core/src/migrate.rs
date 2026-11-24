//! 一次性迁移通道（去兼容第三步立、第四步改 Value 级，
//! refactor_remove_compat §4 的 D2/D3）：把旧格式形态的文档
//! 一次性归一为 Rust 原生规范形，与主线读写分离。
//!
//! 本通道作用于模型解析**之前**的 `serde_json::Value`：
//! 第四步起模型已单形化（id 只认字符串、时间戳只认 ISO、
//! 字段只认 attrs 位、块类型只认规范名），旧形态在模型解析
//! 期即被拒——旧备份导入（D2）与存量首启迁移（D3）都必须
//! 先过本通道把 Value 归一，再交模型解析。主线（渲染/导出/
//! 编辑）从此不接触旧形态。
//!
//! 归一的规范形（与现行写路径同口径）：
//! - 备忘 id：数字形 → 字符串形；时间戳：毫秒数 → ISO-8601
//!   （`YYYY-MM-DDTHH:MM:SS.mmmZ`，与原版 `toISOString()` 同形）；
//! - 附件 fileId：顶层 → `attrs.fileId`（冲突时以顶层值覆写
//!   attrs 后删顶层；顶层空串只删顶层）；
//! - heading 的 level、todo 的 checked：顶层 → attrs（attrs
//!   已有则顶层为影子值、只删顶层）；
//! - gallery 条目：`attrs.items` 统一为 `{fileId}` / `{url}`
//!   对象形（字符串形转换、无效条目剔除）；`attrs.items`
//!   缺失/非数组时按 children 兜底口径把子节点的 fileId 物化
//!   进 `attrs.items`；items 归一后，若 children 全部是
//!   fileId 载体（纯影子副本）则一并清除，含其他内容的
//!   children 原样保留；
//! - 块类型旧名：`music` → `musicCard`、`code` → `codeBlock`；
//! - 行内标记旧名：`strike` → `strikethrough`（主线双名读已
//!   于第一步删除，迁移改名保住历史删除线）。
//!
//! 不触碰：`avatars`（首页/编辑页头像功能的数据，原样保留）、
//! 备忘与文件的其余键、manifest（第五步建模）、未知字段一律
//! 透传。归一是纯函数式变换：不动输入之外的任何状态，对已
//! 归一数据重跑命中恒为零（幂等），无法解读的异常值（非
//! 对象 attrs、非字符串 fileId 等）一律原样保留、不销毁。

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use crate::model::Timestamp;

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
    /// gallery 的 children 在 items 归一后被清除的节点数
    /// （children 全部为 fileId 载体时才清，第四步）。
    pub gallery_children_removed: usize,
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
            + self.gallery_children_removed
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
             gal_str={} gal_kids={} gal_rm={} gal_drop={} level_move={} level_clear={} \
             checked_move={} checked_clear={} music={} code={} strike={} changed={}",
            self.memos,
            self.nodes,
            self.numeric_ids,
            self.millis_timestamps,
            self.file_id_moved,
            self.file_id_cleared,
            self.gallery_string_items,
            self.gallery_children_forms,
            self.gallery_children_removed,
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

/// 递归统计节点数（Value 级：doc/children 数组内的对象节点，
/// 含行内文本节点；非对象条目不计）。
pub fn count_nodes_value(nodes: &[Value]) -> usize {
    nodes
        .iter()
        .map(|n| {
            if !n.is_object() {
                return 0;
            }
            1 + n
                .get("children")
                .and_then(|c| c.as_array())
                .map(|kids| count_nodes_value(kids))
                .unwrap_or(0)
        })
        .sum()
}

/// 把一份备份（模型解析前的原始 JSON）的全部备忘归一为
/// 规范形（原地），返回命中统计。只改 `memos` 内的文档
/// 形态；`avatars`、`exportedAt` 与根级其余键原样不动。
/// 入口形状不对（无 memos 数组）时零命中返回、不动输入。
pub fn normalize_value(backup: &mut Value) -> MigrationStats {
    let mut stats = MigrationStats::default();
    let Some(memos) = backup
        .get_mut("memos")
        .and_then(|m| m.as_array_mut())
    else {
        return stats;
    };
    stats.memos = memos.len();
    for memo in memos.iter_mut() {
        let Some(memo) = memo.as_object_mut() else {
            continue;
        };
        if let Some(num) = memo.get("id").and_then(|v| v.as_number()) {
            let s = num.to_string();
            memo.insert("id".to_string(), Value::String(s));
            stats.numeric_ids += 1;
        }
        for key in ["createdAt", "updatedAt"] {
            if let Some(m) = memo.get(key).and_then(|v| v.as_i64()) {
                if let Some(ts) = Timestamp::from_millis(m) {
                    memo.insert(key.to_string(), Value::String(ts.0));
                    stats.millis_timestamps += 1;
                }
            }
        }
        if let Some(doc) = memo.get_mut("doc").and_then(|d| d.as_array_mut()) {
            for node in doc.iter_mut() {
                normalize_node(node, &mut stats);
            }
        }
    }
    stats
}

/// 只统计不改动：克隆后归一，返回命中统计（存量扫描口径）。
pub fn dry_run_value(backup: &Value) -> MigrationStats {
    let mut clone = backup.clone();
    normalize_value(&mut clone)
}

fn normalize_node(node: &mut Value, stats: &mut MigrationStats) {
    let Some(obj) = node.as_object_mut() else {
        return;
    };
    stats.nodes += 1;
    // 普查记归一前的原始类型名（旧名命中在普查里也可见）。
    if let Some(ty) = obj.get("type").and_then(|v| v.as_str()) {
        let ty = ty.to_string();
        *stats.block_types.entry(ty.clone()).or_default() += 1;
        match ty.as_str() {
            "music" => {
                obj.insert("type".to_string(), Value::String("musicCard".to_string()));
                stats.music_blocks += 1;
            }
            "code" => {
                obj.insert("type".to_string(), Value::String("codeBlock".to_string()));
                stats.code_blocks += 1;
            }
            _ => {}
        }
    }
    normalize_file_id(obj, stats);
    move_top_to_attrs(obj, "level", &mut stats.level_moved, &mut stats.level_cleared);
    move_top_to_attrs(
        obj,
        "checked",
        &mut stats.checked_moved,
        &mut stats.checked_cleared,
    );
    normalize_strike(obj, stats);
    let is_gallery = obj.get("type").and_then(|v| v.as_str()) == Some("gallery");
    // 子节点先归一（普查/计数含将被 gallery 清除的 children，
    // 口径诚实），gallery 处置最后——物化读的是已归一的子节点。
    if let Some(children) = obj
        .get_mut("children")
        .and_then(|c| c.as_array_mut())
    {
        for child in children.iter_mut() {
            normalize_node(child, stats);
        }
    }
    if is_gallery {
        normalize_gallery(obj, stats);
    }
}

/// 取节点的 attrs 对象（须已存在且为对象；不存在时按 `create`
/// 决定是否新建）。attrs 存在但非对象时返回 None（异常形态，
/// 调用方跳过该节点的字段搬运、不销毁）。
fn attrs_mut<'a>(obj: &'a mut Map<String, Value>, create: bool) -> Option<&'a mut Map<String, Value>> {
    if !obj.contains_key("attrs") {
        if !create {
            return None;
        }
        obj.insert("attrs".to_string(), Value::Object(Map::new()));
    }
    obj.get_mut("attrs").and_then(|v| v.as_object_mut())
}

/// 顶层 fileId → attrs.fileId（通道内的冲突口径：顶层非空串
/// 即为生效值，覆写 attrs 后删顶层；顶层空串不生效，只删
/// 顶层、attrs 保留；顶层非字符串原样保留不动）。
fn normalize_file_id(obj: &mut Map<String, Value>, stats: &mut MigrationStats) {
    let Some(raw) = obj.get("fileId") else {
        return;
    };
    let Some(value) = raw.as_str() else {
        return;
    };
    if value.is_empty() {
        obj.remove("fileId");
        stats.file_id_cleared += 1;
        return;
    }
    let value = value.to_string();
    if let Some(attrs) = attrs_mut(obj, true) {
        attrs.insert("fileId".to_string(), Value::String(value));
        obj.remove("fileId");
        stats.file_id_moved += 1;
    }
}

/// 顶层键 → attrs 同名键（level/checked 共用）。attrs 已有
/// 同名键时顶层为影子值，只删顶层（cleared）；attrs 没有时
/// 搬入（moved）；attrs 非对象时整项跳过、顶层原样保留。
fn move_top_to_attrs(
    obj: &mut Map<String, Value>,
    key: &str,
    moved: &mut usize,
    cleared: &mut usize,
) {
    if !obj.contains_key(key) {
        return;
    }
    let attrs_has = obj
        .get("attrs")
        .and_then(|a| a.as_object())
        .map(|a| a.contains_key(key))
        .unwrap_or(false);
    if attrs_has {
        obj.remove(key);
        *cleared += 1;
        return;
    }
    // 先确认 attrs 可写再取顶层值，避免 attrs 非对象时把顶层
    // 值摘掉又无处安放。
    if attrs_mut(obj, true).is_none() {
        return;
    }
    let value = obj.remove(key).unwrap_or(Value::Null);
    if let Some(attrs) = attrs_mut(obj, false) {
        attrs.insert(key.to_string(), value);
        *moved += 1;
    }
}

/// 行内标记旧名 strike → strikethrough（生效值 = 两名任一为
/// 真，与旧主线双读 `strikethrough || strike` 同语义）。
fn normalize_strike(obj: &mut Map<String, Value>, stats: &mut MigrationStats) {
    let Some(old) = obj.remove("strike") else {
        return;
    };
    stats.strike_marks += 1;
    let was_true = old.as_bool().unwrap_or(false);
    let existing_true = obj
        .get("strikethrough")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if was_true || existing_true {
        obj.insert("strikethrough".to_string(), Value::Bool(true));
    }
}

/// 节点的附件 id（通道内口径：顶层优先、其次 attrs、空串
/// 视为无）——gallery children 兜底物化与载体判定专用。
fn node_file_id(node: &Value) -> Option<String> {
    if let Some(fid) = node.get("fileId").and_then(|v| v.as_str()) {
        if !fid.is_empty() {
            return Some(fid.to_string());
        }
    }
    node.get("attrs")
        .and_then(|a| a.get("fileId"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
}

/// gallery 条目归一（见模块头注）：items 数组在位则逐条转
/// 对象形；不在位（缺失/非数组）则按 children 兜底口径物化。
/// items 归一完成后，若 children 全部是 fileId 载体（与 items
/// 重复的影子副本）则清除 children 并计数；含其他内容（如带
/// 文本的子节点）时原样保留、不销毁（通道不销毁原则）。
fn normalize_gallery(obj: &mut Map<String, Value>, stats: &mut MigrationStats) {
    let has_items_array = obj
        .get("attrs")
        .and_then(|a| a.get("items"))
        .map(|v| v.is_array())
        .unwrap_or(false);
    let mut canonical = false;
    if has_items_array {
        let Some(items) = obj
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
                Value::Object(o) => {
                    let has_file = o
                        .get("fileId")
                        .and_then(|v| v.as_str())
                        .map(|s| !s.is_empty())
                        .unwrap_or(false);
                    let has_url = o
                        .get("url")
                        .and_then(|v| v.as_str())
                        .map(|s| !s.is_empty())
                        .unwrap_or(false);
                    if has_file || has_url {
                        kept.push(Value::Object(o));
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
        canonical = true;
    } else {
        // children 兜底形：把子节点 fileId 物化进 attrs.items。
        let fids: Vec<String> = obj
            .get("children")
            .and_then(|c| c.as_array())
            .map(|kids| kids.iter().filter_map(node_file_id).collect())
            .unwrap_or_default();
        if !fids.is_empty() {
            if let Some(attrs) = attrs_mut(obj, true) {
                let items: Vec<Value> = fids
                    .into_iter()
                    .map(|f| json!({ "fileId": f }))
                    .collect();
                attrs.insert("items".to_string(), Value::Array(items));
                stats.gallery_children_forms += 1;
                canonical = true;
            }
        }
    }
    // items 已归一且 children 全部是 fileId 载体（纯影子副本）
    // 时清除 children；任一子节点带其他内容则整组保留。
    if canonical {
        let all_carriers = obj
            .get("children")
            .and_then(|c| c.as_array())
            .map(|kids| {
                !kids.is_empty() && kids.iter().all(|k| node_file_id(k).is_some())
            })
            .unwrap_or(false);
        if all_carriers {
            if let Some(kids) = obj.remove("children") {
                stats.gallery_children_removed +=
                    kids.as_array().map(|a| a.len()).unwrap_or(0);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn millis_iso_roundtrip() {
        // 与真实样本同一瞬间（tests/timestamp.rs 同值）。
        let ts = Timestamp::from_millis(1778254999257).expect("in range");
        assert_eq!(ts.as_str(), "2026-05-08T15:43:19.257Z");
        assert_eq!(
            ts.to_millis(),
            Some(1778254999257),
            "归一后 ISO 必须换算回同一毫秒"
        );
        assert_eq!(
            Timestamp::from_millis(0).map(|t| t.as_str().to_string()).as_deref(),
            Some("1970-01-01T00:00:00.000Z")
        );
    }
}
