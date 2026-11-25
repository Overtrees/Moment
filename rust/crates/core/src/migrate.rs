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
//!   （`YYYY-MM-DDTHH:MM:SS.mmmZ`，与原版 `toISOString()` 同形；
//!   备忘 createdAt/updatedAt 与备份根级 exportedAt 同口径）；
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
//! - callout 变体旧名：`kind` / `variant` → `calloutType`
//!   （旧读链为节点顶层三级回退 calloutType → kind →
//!   variant；主线回退读已于第一步删除、只认 calloutType，
//!   两旧名从此只在本通道出现，见 [`normalize_callout`]）。
//! - manifest（第五步，独立入口 [`normalize_manifest_value`]，
//!   作用于 manifest.json 的 Value）：attachments 数组形 →
//!   字典形（条目须自带字符串 id 为键、无 id 者剔除）、缺失/
//!   null → 空字典；条目收为 {name, type} 字符串两键（多余
//!   键剥离、缺失/非字符串字段补空串）；根级多余键剥离。
//! - 字段类型归一（§2.2 模型类型化收尾）：模型已建模的键
//!   若类型不合（attrs 的 level/checked/fileId/start/href/
//!   url、节点的 url/status/name/title/caption/calloutType
//!   与标记键、备忘的 title/pinned/deletedAt/bgColor），
//!   能无损换算者换算（浮点整数值/数字字符串 → 整数），
//!   无法解读或类型不合者剔除并计数——类型化模型解析期只
//!   认规范类型，通道不收敛即整包解析失败，故此处是唯一
//!   收敛点；attrs 非对象时整键剔除。未建模的未知键通道
//!   仍不触碰（由模型侧退役透传、不再往返）。
//! - 备忘 layout 归一（§2.2 同批）：`twoPane:true`（无字符串
//!   mode 时）→ `mode:"independent"` 后删 twoPane；mode 非
//!   字符串、version 非数字剔除；left/right 非数组剔除、
//!   数组内非字符串条目过滤；未知键剥离（模型只承载
//!   version/mode/left/right）；layout 非对象整键剔除。
//!
//! 不触碰：`avatars`（首页/编辑页头像功能的数据，原样保留）、
//! 未建模的未知字段（通道不改、模型不再透传）。归一是纯
//! 函数式变换：不动输入之外的任何状态，对已归一数据重跑
//! 命中恒为零（幂等）。
//!
//! 存量加载另有逐篇隔离入口 [`normalize_stock_value`]：
//! 与导入共用同一套逐篇归一，但处置分工——导入维持整包
//! 严格（坏篇整包拒），存量加载把归一后仍过不了结构校验
//! 的坏篇整篇隔离保全、好篇照常加载（单篇坏行不整库判
//! 死）。隔离只在本入口，`normalize_value` 本身不隔离。

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use crate::backup::Manifest;
use crate::model::{Memo, Timestamp};

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
    /// 毫秒数时间戳转 ISO 的个数（备忘 createdAt/updatedAt
    /// 与备份根级 exportedAt 分别计）。
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
    /// callout 变体旧名改名 `calloutType` 的节点数（旧名
    /// `kind` / `variant` 提供了生效值、被搬为 calloutType）。
    pub callout_moved: usize,
    /// callout 旧名被生效值影子覆盖、只删旧名的个数（逐旧名
    /// 键计：同一节点的 kind 与 variant 各算一次）。
    pub callout_cleared: usize,
    /// manifest：attachments 形态修正次数（数组形转字典、
    /// 缺失/null 补空字典），逐 manifest 计一次。
    pub manifest_form_fixes: usize,
    /// manifest：被剔除的无效条目数（非对象条目、数组形里
    /// 无字符串 id 的条目）。
    pub manifest_entries_dropped: usize,
    /// manifest：字段归一数（根级多余键剥离、条目多余键
    /// 剥离、name/type 缺失补空串或非字符串改空串），逐键计。
    pub manifest_fields_normalized: usize,
    /// 字段类型归一数（§2.2 模型类型化）：已建模键类型不合
    /// 的换算/剔除，逐键计（备忘级 title/pinned/deletedAt/
    /// bgColor、节点顶层字符串/布尔键、attrs 已知键与 attrs
    /// 非对象整键剔除；gallery 的 items 由 gallery 归一自管、
    /// 不在此计）。
    pub fields_normalized: usize,
    /// 备忘 layout 归一数（§2.2）：twoPane 转换/剔除、mode/
    /// version 类型剔除、left/right 形态修正、未知键剥离、
    /// 非对象整键剔除，逐键计。
    pub layout_normalized: usize,
    /// 存量加载逐篇隔离数（仅 [`normalize_stock_value`] 计）：
    /// 归一后仍过不了结构校验/模型试解析的坏篇被整篇隔离
    /// 保全的篇数。导入路径（[`normalize_value`]）恒为 0。
    pub quarantined: usize,
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
            + self.callout_moved
            + self.callout_cleared
            + self.manifest_form_fixes
            + self.manifest_entries_dropped
            + self.manifest_fields_normalized
            + self.fields_normalized
            + self.layout_normalized
            + self.quarantined
    }

    /// 单行摘要（Diag 与测试共用口径）。
    pub fn summary(&self) -> String {
        format!(
            "memos={} nodes={} num_id={} millis_ts={} fileid_move={} fileid_clear={} \
             gal_str={} gal_kids={} gal_rm={} gal_drop={} level_move={} level_clear={} \
             checked_move={} checked_clear={} music={} code={} strike={} \
             callout_move={} callout_clear={} \
             mform={} mdrop={} mfield={} fields_norm={} layout_norm={} quarantined={} changed={}",
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
            self.callout_moved,
            self.callout_cleared,
            self.manifest_form_fixes,
            self.manifest_entries_dropped,
            self.manifest_fields_normalized,
            self.fields_normalized,
            self.layout_normalized,
            self.quarantined,
            self.total_changes(),
        )
    }

    /// 并入另一份统计（逐篇处理时把单篇统计汇总进整包
    /// 统计用）：计数逐项相加、块类型普查逐名相加。
    fn absorb(&mut self, other: MigrationStats) {
        self.memos += other.memos;
        self.nodes += other.nodes;
        self.numeric_ids += other.numeric_ids;
        self.millis_timestamps += other.millis_timestamps;
        self.file_id_moved += other.file_id_moved;
        self.file_id_cleared += other.file_id_cleared;
        self.gallery_string_items += other.gallery_string_items;
        self.gallery_children_forms += other.gallery_children_forms;
        self.gallery_children_removed += other.gallery_children_removed;
        self.gallery_items_dropped += other.gallery_items_dropped;
        self.level_moved += other.level_moved;
        self.level_cleared += other.level_cleared;
        self.checked_moved += other.checked_moved;
        self.checked_cleared += other.checked_cleared;
        self.music_blocks += other.music_blocks;
        self.code_blocks += other.code_blocks;
        self.strike_marks += other.strike_marks;
        self.callout_moved += other.callout_moved;
        self.callout_cleared += other.callout_cleared;
        self.manifest_form_fixes += other.manifest_form_fixes;
        self.manifest_entries_dropped += other.manifest_entries_dropped;
        self.manifest_fields_normalized += other.manifest_fields_normalized;
        self.fields_normalized += other.fields_normalized;
        self.layout_normalized += other.layout_normalized;
        self.quarantined += other.quarantined;
        for (k, v) in other.block_types {
            *self.block_types.entry(k).or_default() += v;
        }
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
/// 形态与根级 `exportedAt` 的毫秒数形（字符串形不动）；
/// `avatars` 与根级其余键原样不动。无 memos 数组时只归一
/// exportedAt 后返回、不动其余输入。
pub fn normalize_value(backup: &mut Value) -> MigrationStats {
    let mut stats = MigrationStats::default();
    if let Some(m) = backup.get("exportedAt").and_then(|v| v.as_i64()) {
        if let Some(ts) = Timestamp::from_millis(m) {
            if let Some(root) = backup.as_object_mut() {
                root.insert("exportedAt".to_string(), Value::String(ts.0));
                stats.millis_timestamps += 1;
            }
        }
    }
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
        // 备忘级已建模标量键的类型收敛（§2.2 模型类型化）：
        // 类型不合者剔除、deletedAt 浮点整数值换算为整数，
        // 否则类型化模型解析期会拒、整包失败。
        for key in ["title", "bgColor"] {
            if memo.get(key).map(|v| !v.is_string()).unwrap_or(false) {
                memo.remove(key);
                stats.fields_normalized += 1;
            }
        }
        if memo.get("pinned").map(|v| !v.is_boolean()).unwrap_or(false) {
            memo.remove("pinned");
            stats.fields_normalized += 1;
        }
        if let Some(d) = memo.get("deletedAt") {
            if d.as_i64().is_none() {
                match as_int_coerced(d) {
                    Some(i) => {
                        memo.insert("deletedAt".to_string(), json!(i));
                    }
                    None => {
                        memo.remove("deletedAt");
                    }
                }
                stats.fields_normalized += 1;
            }
        }
        normalize_layout(memo, &mut stats);
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

/// 存量加载的逐篇归一 + 隔离结果（[`normalize_stock_value`]）。
#[derive(Debug, Default, Clone, PartialEq)]
pub struct StockNormalization {
    pub stats: MigrationStats,
    /// 被隔离篇的原始 JSON（归一前原文，逐篇完整保全，
    /// 顺序与存量中出现顺序一致）。调用方须先把这批原文
    /// 落到隔离区保全，才可把归一结果写回主库收敛。
    pub quarantined: Vec<Value>,
}

/// 存量加载专用（D3）：逐篇归一 + 结构隔离。与导入共用
/// 同一套逐篇归一（[`normalize_value`]），分工只在处置：
/// 导入（D2）维持整包严格、坏篇整包拒；存量加载面对的是
/// 用户设备上已落盘的资产，单篇结构坏行不得整库判死——
/// 坏篇整篇隔离保全（原文经 [`StockNormalization`] 返回），
/// 好篇归一后照常加载。
///
/// 逐篇流程：原文 → 包成单篇 backup 过 `normalize_value`
/// 归一（标量字段收敛与整包口径完全一致）→ 节点守恒校验
/// （归一前节点数 − gallery 影子 children 清除数 == 归一
/// 后节点数，防归一自身丢节点）→ 结构校验即模型试解析
/// （[`Memo`]：条目须为对象、doc 须为数组、节点 children
/// 须为数组、id/createdAt/updatedAt 等必填字段在归一后
/// 存在且类型正确）。任一步不过即整篇隔离（不做节点级
/// 抢救）。根级 `exportedAt` 的毫秒形在整包层同口径归一。
/// 根非对象 / memos 非数组 / 无 memos 键时无可隔离：原样
/// 返回、隔离为空（调用方严格解析按既有失败态处理，即
/// 全损保全口径）。
pub fn normalize_stock_value(backup: &mut Value) -> StockNormalization {
    let mut out = StockNormalization::default();
    // 根级 exportedAt 归一：临时摘出 memos 过整包归一（无
    // memos 时该函数只动 exportedAt），再逐篇处理装回。
    let memos_taken = backup
        .as_object_mut()
        .and_then(|root| root.remove("memos"));
    let root_stats = normalize_value(backup);
    out.stats.absorb(root_stats);
    let Some(memos_value) = memos_taken else {
        return out;
    };
    let Some(entries) = memos_value.as_array().cloned() else {
        // memos 非数组：结构全损口径，原样装回、不隔离。
        if let Some(root) = backup.as_object_mut() {
            root.insert("memos".to_string(), memos_value);
        }
        return out;
    };
    out.stats.memos = entries.len();
    let mut kept: Vec<Value> = Vec::with_capacity(entries.len());
    for entry in entries {
        let nodes_before = entry
            .get("doc")
            .and_then(|d| d.as_array())
            .map(|doc| count_nodes_value(doc))
            .unwrap_or(0);
        let mut single = json!({ "memos": [entry.clone()] });
        let mut single_stats = normalize_value(&mut single);
        let normalized = single
            .get_mut("memos")
            .and_then(|m| m.as_array_mut())
            .map(|a| a.remove(0))
            .unwrap_or(Value::Null);
        let nodes_after = normalized
            .get("doc")
            .and_then(|d| d.as_array())
            .map(|doc| count_nodes_value(doc))
            .unwrap_or(0);
        let conserved =
            nodes_before - single_stats.gallery_children_removed == nodes_after;
        let parses = serde_json::from_value::<Memo>(normalized.clone()).is_ok();
        // 单篇统计并入总账（memos 已按整包扫描口径计，
        // 不重复计单篇的 1）。
        single_stats.memos = 0;
        out.stats.absorb(single_stats);
        if conserved && parses {
            kept.push(normalized);
        } else {
            out.quarantined.push(entry);
        }
    }
    out.stats.quarantined = out.quarantined.len();
    if let Some(root) = backup.as_object_mut() {
        root.insert("memos".to_string(), Value::Array(kept));
    }
    out
}

/// 隔离区文档合并（存量加载坏篇保全的落盘口径）：隔离区
/// 是一份 JSON 数组文档（逐篇原文）。既有内容宽容读：
/// 数组直用、其他 JSON 值整体作一条、不可解析则整串作
/// 一条字符串条目——既有保全内容在任何形态下都不因合并
/// 被销毁。新条目按序列化文本去重（同一坏篇多次加载不
/// 重复堆积）。返回 (合并后文档序列化, 条目总数)。
pub fn merge_quarantine(existing_raw: Option<&str>, new_entries: &[Value]) -> (String, usize) {
    let mut entries: Vec<Value> = match existing_raw {
        Some(raw) if !raw.trim().is_empty() => {
            match serde_json::from_str::<Value>(raw) {
                Ok(Value::Array(a)) => a,
                Ok(other) => vec![other],
                Err(_) => vec![Value::String(raw.to_string())],
            }
        }
        _ => Vec::new(),
    };
    let mut seen: std::collections::HashSet<String> =
        entries.iter().map(|e| e.to_string()).collect();
    for e in new_entries {
        if seen.insert(e.to_string()) {
            entries.push(e.clone());
        }
    }
    let n = entries.len();
    (Value::Array(entries).to_string(), n)
}

/// 把一份 manifest（manifest.json 的原始 JSON）归一为原生形
/// （原地，命中计入 `stats` 的 manifest 三计数）：根级只留
/// version + attachments；attachments 恒为字典（数组形逐条以
/// 自带字符串 id 为键转入、无 id/非对象条目剔除；缺失/null
/// 补空字典）；条目恒 {name, type} 字符串两键（多余键剥离、
/// 缺失补空串、非字符串改空串）。version 本身不动——缺失或
/// 非数字时模型解析会拒、导入按坏包处理（与主线口径一致）。
/// 根非对象时原样保留、零命中（同上，模型解析会拒）。
pub fn normalize_manifest_value(value: &mut Value, stats: &mut MigrationStats) {
    let Some(root) = value.as_object_mut() else {
        return;
    };
    let extra_root: Vec<String> = root
        .keys()
        .filter(|k| k.as_str() != "version" && k.as_str() != "attachments")
        .cloned()
        .collect();
    for k in extra_root {
        root.remove(&k);
        stats.manifest_fields_normalized += 1;
    }
    match root.remove("attachments") {
        None => {
            root.insert("attachments".to_string(), Value::Object(Map::new()));
            stats.manifest_form_fixes += 1;
        }
        Some(Value::Null) => {
            root.insert("attachments".to_string(), Value::Object(Map::new()));
            stats.manifest_form_fixes += 1;
        }
        Some(Value::Array(items)) => {
            stats.manifest_form_fixes += 1;
            let mut dict = Map::new();
            for item in items {
                let Some(mut entry) = item.as_object().cloned() else {
                    stats.manifest_entries_dropped += 1;
                    continue;
                };
                let Some(id) = entry
                    .remove("id")
                    .and_then(|v| v.as_str().filter(|s| !s.is_empty()).map(str::to_string))
                else {
                    stats.manifest_entries_dropped += 1;
                    continue;
                };
                normalize_manifest_entry(&mut entry, stats);
                dict.insert(id, Value::Object(entry));
            }
            root.insert("attachments".to_string(), Value::Object(dict));
        }
        Some(Value::Object(mut dict)) => {
            let keys: Vec<String> = dict.keys().cloned().collect();
            for id in keys {
                let keep = match dict.get_mut(&id) {
                    Some(Value::Object(entry)) => {
                        normalize_manifest_entry(entry, stats);
                        true
                    }
                    _ => false,
                };
                if !keep {
                    dict.remove(&id);
                    stats.manifest_entries_dropped += 1;
                }
            }
            root.insert("attachments".to_string(), Value::Object(dict));
        }
        Some(other) => {
            // attachments 是字符串/数字等无法解读的形态：原样
            // 放回、不销毁（模型解析会拒，导入按坏包处理）。
            root.insert("attachments".to_string(), other);
        }
    }
}

/// 单个 manifest 条目收为 {name, type} 字符串两键。
fn normalize_manifest_entry(entry: &mut Map<String, Value>, stats: &mut MigrationStats) {
    let extra: Vec<String> = entry
        .keys()
        .filter(|k| k.as_str() != "name" && k.as_str() != "type")
        .cloned()
        .collect();
    for k in extra {
        entry.remove(&k);
        stats.manifest_fields_normalized += 1;
    }
    for key in ["name", "type"] {
        match entry.get(key) {
            Some(v) if v.is_string() => {}
            Some(_) => {
                entry.insert(key.to_string(), Value::String(String::new()));
                stats.manifest_fields_normalized += 1;
            }
            None => {
                entry.insert(key.to_string(), Value::String(String::new()));
                stats.manifest_fields_normalized += 1;
            }
        }
    }
}

/// 内部存量 manifest 字符串的宽容解析：先按原生形直解，失败
/// 则过本通道归一再解，全失败返回 None（调用方回退空清单）。
/// 供 storage / Web 读旧版本写下的 manifest 存量——那些字节
/// 是旧格式原文、未经本通道；新写入一律是模型序列化（原生
/// 形），直解即中。
pub fn manifest_parse_lenient(raw: &str) -> Option<Manifest> {
    if let Ok(m) = serde_json::from_str::<Manifest>(raw) {
        return Some(m);
    }
    let mut value: Value = serde_json::from_str(raw).ok()?;
    let mut stats = MigrationStats::default();
    normalize_manifest_value(&mut value, &mut stats);
    serde_json::from_value(value).ok()
}

/// 整数形换算：JSON 整数原样、浮点整数值（2.0 类）转整数、
/// 数字字符串转整数；其余（小数、非数字字符串、复合值）
/// 返回 None。只用于已建模整数键的类型收敛。
fn as_int_coerced(v: &Value) -> Option<i64> {
    if let Some(i) = v.as_i64() {
        return Some(i);
    }
    if let Some(f) = v.as_f64() {
        if f.fract() == 0.0 && f >= i64::MIN as f64 && f <= i64::MAX as f64 {
            return Some(f as i64);
        }
        return None;
    }
    v.as_str().and_then(|s| s.parse::<i64>().ok())
}

/// 备忘 layout 归一（§2.2 模型类型化）：类型化 `MemoLayout`
/// 只承载 version/mode/left/right——twoPane 旧形在此转换、
/// 类型不合与未知键在此剥离（逐键计 layout_normalized），
/// 主线不再读 twoPane。layout 非对象整键剔除。
fn normalize_layout(memo: &mut Map<String, Value>, stats: &mut MigrationStats) {
    if memo.get("layout").map(|v| !v.is_object()).unwrap_or(false) {
        memo.remove("layout");
        stats.layout_normalized += 1;
        return;
    }
    let Some(layout) = memo
        .get_mut("layout")
        .and_then(|v| v.as_object_mut())
    else {
        return;
    };
    if layout.contains_key("twoPane") {
        let two_pane_true = layout
            .get("twoPane")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if two_pane_true
            && layout.get("mode").and_then(|v| v.as_str()).is_none()
        {
            layout.insert(
                "mode".to_string(),
                Value::String("independent".to_string()),
            );
            stats.layout_normalized += 1;
        }
        layout.remove("twoPane");
        stats.layout_normalized += 1;
    }
    if layout.get("mode").map(|v| !v.is_string()).unwrap_or(false) {
        layout.remove("mode");
        stats.layout_normalized += 1;
    }
    if layout
        .get("version")
        .map(|v| !v.is_number())
        .unwrap_or(false)
    {
        layout.remove("version");
        stats.layout_normalized += 1;
    }
    for key in ["left", "right"] {
        if layout.get(key).map(|v| !v.is_array()).unwrap_or(false) {
            layout.remove(key);
            stats.layout_normalized += 1;
        } else if let Some(arr) = layout.get_mut(key).and_then(|v| v.as_array_mut()) {
            let before = arr.len();
            arr.retain(|x| x.is_string());
            if arr.len() != before {
                stats.layout_normalized += 1;
            }
        }
    }
    let unknown: Vec<String> = layout
        .keys()
        .filter(|k| !matches!(k.as_str(), "version" | "mode" | "left" | "right"))
        .cloned()
        .collect();
    for k in unknown {
        layout.remove(&k);
        stats.layout_normalized += 1;
    }
}

/// 节点已建模字段的类型归一（§2.2 模型类型化）：类型化
/// 模型对已建模键只认规范类型，类型不合的值在解析期会让
/// 整包失败——通道在此收敛：整数键能无损换算者换算、其余
/// 类型不合者剔除（逐键计 fields_normalized）。未建模的
/// 未知键不在此列（通道不碰、模型侧退役透传）。gallery 的
/// items 由 [`normalize_gallery`] 自管形态，此处跳过。
fn normalize_node_fields(
    obj: &mut Map<String, Value>,
    is_gallery: bool,
    stats: &mut MigrationStats,
) {
    for key in ["url", "status", "name", "title", "caption", "calloutType"] {
        if obj.get(key).map(|v| !v.is_string()).unwrap_or(false) {
            obj.remove(key);
            stats.fields_normalized += 1;
        }
    }
    for key in ["image", "bold", "italic", "underline", "strikethrough", "code"] {
        if obj.get(key).map(|v| !v.is_boolean()).unwrap_or(false) {
            obj.remove(key);
            stats.fields_normalized += 1;
        }
    }
    if obj.get("attrs").map(|v| !v.is_object()).unwrap_or(false) {
        obj.remove("attrs");
        stats.fields_normalized += 1;
        return;
    }
    let Some(attrs) = obj.get_mut("attrs").and_then(|v| v.as_object_mut()) else {
        return;
    };
    if let Some(v) = attrs.get("level").cloned() {
        match as_int_coerced(&v) {
            Some(i) => {
                if v.as_i64() != Some(i) {
                    attrs.insert("level".to_string(), json!(i));
                    stats.fields_normalized += 1;
                }
            }
            None => {
                attrs.remove("level");
                stats.fields_normalized += 1;
            }
        }
    }
    if attrs
        .get("checked")
        .map(|v| !v.is_boolean())
        .unwrap_or(false)
    {
        attrs.remove("checked");
        stats.fields_normalized += 1;
    }
    for key in ["fileId", "href", "url", "text"] {
        if attrs.get(key).map(|v| !v.is_string()).unwrap_or(false) {
            attrs.remove(key);
            stats.fields_normalized += 1;
        }
    }
    if let Some(v) = attrs.get("start").cloned() {
        match as_int_coerced(&v).filter(|i| *i >= 0) {
            Some(i) => {
                if v.as_u64() != Some(i as u64) {
                    attrs.insert("start".to_string(), json!(i as u64));
                    stats.fields_normalized += 1;
                }
            }
            None => {
                attrs.remove("start");
                stats.fields_normalized += 1;
            }
        }
    }
    if !is_gallery {
        if let Some(items) = attrs.get_mut("items") {
            if !items.is_array() {
                attrs.remove("items");
                stats.fields_normalized += 1;
            } else if let Some(arr) = items.as_array_mut() {
                let before = arr.len();
                arr.retain(|x| x.is_object());
                if arr.len() != before {
                    stats.fields_normalized += 1;
                }
            }
        }
    }
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
    // attrs 非对象先行剔除（§2.2 字段类型归一的前置）：
    // 类型化模型容不下非对象 attrs，且它会让后续搬运步
    // 整体跳过、归一跨趟不收敛（幂等破坏）；在此整键剔
    // 除并计数，后续步面对的 attrs 恒是对象形或缺失。
    if obj.get("attrs").map(|v| !v.is_object()).unwrap_or(false) {
        obj.remove("attrs");
        stats.fields_normalized += 1;
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
    if obj.get("type").and_then(|v| v.as_str()) == Some("callout") {
        normalize_callout(obj, stats);
    }
    let is_gallery = obj.get("type").and_then(|v| v.as_str()) == Some("gallery");
    normalize_node_fields(obj, is_gallery, stats);
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

/// callout 变体旧名改名（refactor_remove_compat §2.7 的通道
/// 侧归一）：旧读链为节点顶层 `calloutType → kind → variant`
/// 三级回退（各级只取字符串值），主线已于第一步收口为只读
/// `calloutType`——`kind` / `variant` 两名从此只在本通道
/// 出现，主线不得再读。本函数与旧读链严格等价：生效值 =
/// 三名中首个字符串值；生效值来自旧名时写入 `calloutType`
/// （calloutType 为非字符串时被生效值覆写——旧读链同样跳过
/// 它）；字符串形的旧名一律删除（提供生效值者计 moved、
/// 被影子覆盖者计 cleared）；非字符串的旧名无法解读、原样
/// 保留（通道不销毁原则，与顶层 fileId 非字符串同口径）。
/// 仅作用于 callout 块：其他块的同名键从未被读路径消费，
/// 不在改名范围。
fn normalize_callout(obj: &mut Map<String, Value>, stats: &mut MigrationStats) {
    if obj.get("calloutType").and_then(|v| v.as_str()).is_none() {
        let source = ["kind", "variant"].iter().find_map(|k| {
            obj.get(*k)
                .and_then(|v| v.as_str())
                .map(|s| (*k, s.to_string()))
        });
        if let Some((key, value)) = source {
            obj.insert("calloutType".to_string(), Value::String(value));
            obj.remove(key);
            stats.callout_moved += 1;
        }
    }
    for key in ["kind", "variant"] {
        if obj.get(key).map(|v| v.is_string()).unwrap_or(false) {
            obj.remove(key);
            stats.callout_cleared += 1;
        }
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
