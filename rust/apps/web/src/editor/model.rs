//! 模型组（批 14 P-D5 自 editor.rs 拆出）：文档节点模型
//! 基础——节点构造与定位（Loc/find_loc/node_at）、块谓词、
//! 尾随段物化与行内形态归一、流式分段、行内劈分数学、
//! attrs/list-start 字段读写、占位判定与 gallery 形态归一。
//! 二轮续入：布局 JSON 辅助（memo_layout_json/
//! apply_memo_layout）、wiki 反链缓存与打开热路径预热、
//! restore_focus 焦点恢复。全部为纯模型函数，只做文件
//! 组织，行为不变。

use super::*;

/// 第一个可编辑块的 id（撤销/重做后焦点兜底落点）。
pub(super) fn first_editable_id(doc: &[Node]) -> Option<String> {
    for b in doc {
        let ty = b.block_type().unwrap_or("");
        if is_text_block(ty) {
            return b.id.clone();
        }
        if ty == "bulleted-list" || ty == "numbered-list" {
            if let Some(kids) = &b.children {
                for item in kids {
                    if item.is_block() {
                        return item.id.clone();
                    }
                }
            }
        }
    }
    None
}

pub(super) fn empty_text_node() -> Node {
    Node {
        text: Some(String::new()),
        ..Default::default()
    }
}

pub(super) fn new_block(block_type: &str) -> Node {
    Node {
        node_type: Some(block_type.to_string()),
        id: Some(gen_id()),
        children: Some(vec![empty_text_node()]),
        ..Default::default()
    }
}

/// 打开编辑器时给所有可编辑节点补 id（真实数据的块都带 id，
/// 列表项等个别可能没有）——DOM 桥按 id 寻址。
pub(super) fn ensure_ids(doc: &mut [Node]) {
    for block in doc.iter_mut() {
        if block.id.is_none() {
            block.id = Some(gen_id());
        }
        if let Some(kids) = &mut block.children {
            for item in kids.iter_mut() {
                if item.is_block() && item.id.is_none() {
                    item.id = Some(gen_id());
                }
            }
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
pub(super) enum Loc {
    Top(usize),
    Item(usize, usize),
}

pub(super) fn find_loc(doc: &[Node], bid: &str) -> Option<Loc> {
    for (i, b) in doc.iter().enumerate() {
        if b.id.as_deref() == Some(bid) {
            return Some(Loc::Top(i));
        }
        if let Some(kids) = &b.children {
            for (j, item) in kids.iter().enumerate() {
                if item.is_block() && item.id.as_deref() == Some(bid) {
                    return Some(Loc::Item(i, j));
                }
            }
        }
    }
    None
}

pub(super) fn node_at<'a>(doc: &'a [Node], loc: Loc) -> &'a Node {
    match loc {
        Loc::Top(i) => &doc[i],
        Loc::Item(li, ii) => &doc[li].children.as_ref().unwrap()[ii],
    }
}

pub(super) fn node_at_mut<'a>(doc: &'a mut [Node], loc: Loc) -> &'a mut Node {
    match loc {
        Loc::Top(i) => &mut doc[i],
        Loc::Item(li, ii) => &mut doc[li].children.as_mut().unwrap()[ii],
    }
}

/// 文档顺序里上一个可编辑文本块（合并的目标）。
pub(super) fn prev_editable(doc: &[Node], loc: Loc) -> Option<Loc> {
    let mut prev: Option<Loc> = None;
    for (i, b) in doc.iter().enumerate() {
        let ty = b.block_type().unwrap_or("");
        if is_text_block(ty) {
            let cur = Loc::Top(i);
            if cur == loc {
                return prev;
            }
            prev = Some(cur);
        }
        if ty == "bulleted-list" || ty == "numbered-list" {
            if let Some(kids) = &b.children {
                for (j, item) in kids.iter().enumerate() {
                    if item.is_block() {
                        let cur = Loc::Item(i, j);
                        if cur == loc {
                            return prev;
                        }
                        prev = Some(cur);
                    }
                }
            }
        }
    }
    None
}

pub(super) fn is_text_block(ty: &str) -> bool {
    matches!(
        ty,
        "paragraph" | "heading" | "quote" | "todo" | "callout" | "list-item" | "codeBlock"
    )
}

/// 块纯文本长度，口径 = JS String.length（UTF-16 码元）。
/// 全部调用点都是 DOM 光标偏移（__mnFocus/__mnSetHtml 按
/// textContent.length 走 TreeWalker、caretInfo 按 range 字
/// 符串长度计），原版单宿主里浏览器原生合并的光标落点同
/// 口径。此前按 chars()（标量）计，前块含星光平面字符
/// （emoji/𐮷 等）时合并接合点、撤销恢复钳制、粘贴落点
/// 一律少算、光标落进代理对中间（跨块语义组实测 MERGE1
/// utf16=3 应为 4）。
pub(super) fn plain_len(node: &Node) -> usize {
    node.plain_text().encode_utf16().count()
}

/// 字数口径逐字对原版 editor.js:2454：只统计顶层 paragraph 块
/// 的第一个叶子的文本（去掉 \n）。标题/待办/列表等不计入——
/// 此前按全块纯文本统计，看展备忘多出标题 4 字（118 vs 114）。
/// 长度按 JS String.length（UTF-16 码元）计：原版是 .length，
/// emoji 等星光平面字符算 2——此前按 chars() 计，混排夹具
/// 编辑页字数 232 vs 原版 233，差的就是一个 😀。
pub(super) fn orig_char_count(doc: &[Node]) -> usize {
    doc.iter()
        .filter(|n| n.block_type() == Some("paragraph"))
        .map(|n| {
            n.children
                .as_ref()
                .and_then(|c| c.first())
                .and_then(|f| f.text.as_ref())
                .map(|t| t.replace('\n', "").encode_utf16().count())
                .unwrap_or(0)
        })
        .sum()
}

/// 列表源段落（原版转换管线的 pass2 先行成组转换，不带
/// ensureTrailing 回调）。
pub(super) fn is_list_para(node: &Node) -> bool {
    node.block_type() == Some("paragraph")
        && matches!(
            crate::blocks::md_classify(&node.plain_text()),
            Some(crate::blocks::MdKind::List { .. })
        )
}

/// 渲染成块级 md 预览的段落（行内预览不算）。
pub(super) fn is_block_preview_para(node: &Node) -> bool {
    if node.block_type() != Some("paragraph") {
        return false;
    }
    let text = node.plain_text();
    crate::blocks::md_classify(&text).is_some()
        && crate::blocks::md_is_block_preview(&text)
}

/// 原版 ensureTrailingParagraphBlock（editor.js:410-420）的
/// 等价确定性规则：块级 md 预览（列表组除外）之后，若紧邻
/// 的下一个块是不可编辑形态——原子块 / 分割线 / 另一个块
/// 级预览（列表组预览与单预览同为 contentEditable=false
/// 的 div）/ 文档末尾——补一个空段落。判定口径取原版打开
/// 时的稳态：加载管线把全部 md 块渲染成预览后逐个跑
/// ensureTrailing，故相邻预览之间同样有段（原版活体实测：
/// 两段相邻代码预览之间与文末各一段）；会话内失焦转换时
/// 「下一块正在源码编辑」由 materialize 的 editing 守卫对
/// 齐（转换时点不补、失焦后补，与原版收敛形态一致）。
/// 批 11 MD-P2 单点化：trail 判定（list / block_preview）
/// 每节点在一趟 materialize 内只算一次——此前 trail_after
/// 对本块与下一块各重跑 classify（block_preview 还含全量
/// parse），每节点被评多达 4 次。判定函数本体不变、结果
/// 逐字等价；插入的空段落判定恒为 (false, false)（空文本
/// classify 为 None），与重算一致，judges  vec 随 doc 同步
/// 插入默认项保持下标对齐。
#[derive(Clone, Copy, Default)]
pub(super) struct TrailJudge {
    pub(super) list: bool,
    pub(super) block_preview: bool,
}

pub(super) fn trail_judges(doc: &[Node]) -> Vec<TrailJudge> {
    doc.iter()
        .map(|n| TrailJudge {
            list: is_list_para(n),
            block_preview: is_block_preview_para(n),
        })
        .collect()
}

pub(super) fn trail_after(doc: &[Node], judges: &[TrailJudge], i: usize) -> bool {
    if !judges[i].block_preview || judges[i].list {
        return false;
    }
    match doc.get(i + 1) {
        None => true,
        Some(next) => {
            let t = next.block_type().unwrap_or("");
            matches!(
                t,
                "image"
                    | "gallery"
                    | "imgTextCard"
                    | "imageTextRow"
                    | "attachment"
                    | "link-card"
                    | "musicCard"
                    | "embedCard"
                    | "divider"
            ) || judges[i + 1].list
                || judges[i + 1].block_preview
        }
    }
}

/// 文末原子块清单（原版 editor.js:426 init 口径的有效集）：
/// init 检查的是最后一块 DOM 的 dataset.type，故只有渲染
/// 时带 data-type 的类型才真正触发 trail_ 推入——musicCard
/// /link-card/attachment/image/gallery/imgTextCard/image
/// TextRow/todo。divider 渲染为裸 <hr>（无 data-type）、
/// embedCard/decorative_divider 落 <p> 兜底，均不触发（原
/// 版活体实测：文末分割线的备忘打开后 DOM 与落盘都无尾随
/// 段）；这些块的尾随段由插入路径产生（斜杠转 divider 自
/// 带段落、粘贴/插入原子块后 ensure），不在打开时补。
pub(super) const TRAIL_END_ATOMIC: [&str; 8] = [
    "musicCard",
    "link-card",
    "attachment",
    "image",
    "gallery",
    "imgTextCard",
    "imageTextRow",
    "todo",
];

/// 尾随空段模型化（原版 ensureTrailing + init trail_ 的模型
/// 层等价）：在 trail_after 命中的预览块之后、以及文末原子
/// 块之后，插入真实空段落块（new_block("paragraph")，与原
/// 版 {type:'paragraph', children:[{text:''}]} 同形态）。原
/// 版里这些段落是带 blockid 的可编辑 <p>，首次 parseEditor
/// DOM 同步即成为 docRef 中的真实段落并落盘——不存在视图
/// 层形态。插入后同一位置的 trail_after 转假、文末块变为
/// 段落，故重复调用幂等。editing 是当前源码编辑中的块 id：
/// 它之后的尾随段等失焦转预览时再补（原版 ensureTrailing
/// 在预览转换时点才触发）。返回插入数。
pub(super) fn materialize_trails(doc: &mut Vec<Node>, editing: Option<&str>) -> usize {
    let mut judges = trail_judges(doc);
    let mut inserted = 0;
    let mut i = 0;
    while i < doc.len() {
        if trail_after(doc, &judges, i) && editing != doc[i].id.as_deref() {
            doc.insert(i + 1, new_block("paragraph"));
            judges.insert(i + 1, TrailJudge::default());
            inserted += 1;
            i += 2;
        } else {
            i += 1;
        }
    }
    if let Some(last) = doc.last() {
        if TRAIL_END_ATOMIC.contains(&last.block_type().unwrap_or("")) {
            doc.push(new_block("paragraph"));
            inserted += 1;
        }
    }
    inserted
}

/// 行内形态归一（打开时一次性，与 materialize_trails 同位）：
/// 存量 bool 标记块（外部工具/旧版本写入的 children 多子节点
/// + bold/italic 等 bool 键）经编辑对往返折成字面单节点形态。
/// 必须在首次渲染前完成：编辑对填充已把 bool 折成字面文本
/// 住进 DOM，会话内任何一次全量回收（菜单打开/返回/撤销的
/// apply_sync_map）都会把这类块归一——若归一发生在会话中途，
/// 块的纯文本凭空多出字面标记、渲染形态由可编辑段落翻成
/// md 预览（导出冒烟实测：菜单 sync 后块几何 17→16、快照丢
/// data-bid）。打开时先归一，块从第一帧起就是它最终的形态，
/// 此后填充/回收往返恒等、被动 sync 恢复隐形。仅处理带标记
/// bool 或链接节点的行内列（无标记纯文本列往返本就恒等，
/// 不动）；下划线往返恒等（<u> 元素承载），计数不虚报。
/// 返回实际变更的块数。
pub(super) fn normalize_inline_forms(doc: &mut Vec<Node>) -> usize {
    fn has_mark_or_link(kids: &[Node]) -> bool {
        kids.iter().any(|c| {
            c.block_type() == Some("link")
                || c.bold.unwrap_or(false)
                || c.italic.unwrap_or(false)
                || c.underline.unwrap_or(false)
                || c.strikethrough.unwrap_or(false)
                || c.code.unwrap_or(false)
        })
    }
    fn walk(nodes: &mut [Node]) -> usize {
        let mut changed = 0;
        for n in nodes.iter_mut() {
            let Some(mut kids) = n.children.take() else {
                continue;
            };
            if has_mark_or_link(&kids) {
                let round = editor_html_to_inlines(&inlines_to_editor_html(&kids));
                if round != kids {
                    changed += 1;
                    kids = round;
                }
            }
            changed += walk(&mut kids);
            n.children = Some(kids);
        }
        changed
    }
    walk(doc)
}

/// 块流渲染单元：普通块单渲；相邻的列表源段落（≥2）合成
/// 一个合并预览（M6）。原版依据：blur 管线 pass1 用
/// collectListGroup（src/editor/md-blocks.js:38-49）把同流内
/// 相邻的列表行段落成组，join('\n') 后 marked 一次渲染、
/// 替换为单个 .md-preview.block（首块 id）；点击该预览按
/// use-editor-dom.js:117-132 还原为单个源码段（其余块消
/// 失）。Rust 块流在渲染层等价成组，点击时把模型合并回
/// 首块（见 MergedListPreview），存储形态不变（段落文本本
/// 就可含 \n）。
pub(super) enum FlowRun {
    Single(usize),
    ListGroup(Vec<usize>),
}

/// 组员资格（原版 LIST_RE，md-blocks.js:9）：段落修剪后以
/// [-*] 或 数字. 开头（后跟空白）；且非源码编辑/聚焦态、
/// 本身会渲染为 md 预览（与单块路径同门控）。
pub(super) fn is_list_group_member(
    node: &Node,
    is_md: bool,
    editing_id: Option<&str>,
    active_id: Option<&str>,
) -> bool {
    if node.block_type() != Some("paragraph") {
        return false;
    }
    let bid = node.id.as_deref().unwrap_or("");
    if Some(bid) == editing_id || Some(bid) == active_id {
        return false;
    }
    // 批 11 MD-P2：分类有无由渲染趟统一预判（para_kinds）
    // 传入，不在此重跑 md_classify；下方 LIST_RE 前缀判定
    // 本体不变。
    if !is_md {
        return false;
    }
    let text = node.plain_text();
    let t = text.trim();
    let b = t.as_bytes();
    if b.len() >= 2
        && (b[0] == b'-' || b[0] == b'*')
        && (b[1] as char).is_whitespace()
    {
        return true;
    }
    let mut i = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    i > 0 && i + 1 < b.len() && b[i] == b'.' && (b[i + 1] as char).is_whitespace()
}

/// 把 [start, end) 区间的块序切成渲染单元（同流内成组，
/// 不跨调用方给定的区间边界 = 不跨栏）。
pub(super) fn flow_runs(
    doc: &[Node],
    range: std::ops::Range<usize>,
    kinds: &[bool],
    editing_id: Option<&str>,
    active_id: Option<&str>,
) -> Vec<FlowRun> {
    let mut runs = Vec::new();
    let mut i = range.start;
    while i < range.end {
        if is_list_group_member(&doc[i], kinds[i], editing_id, active_id) {
            let mut j = i + 1;
            while j < range.end
                && is_list_group_member(&doc[j], kinds[j], editing_id, active_id)
            {
                j += 1;
            }
            if j - i >= 2 {
                runs.push(FlowRun::ListGroup((i..j).collect()));
            } else {
                runs.push(FlowRun::Single(i));
            }
            i = j;
        } else {
            runs.push(FlowRun::Single(i));
            i += 1;
        }
    }
    runs
}

/// 占位符显隐的空判定（B-14，原版 editor.js 正文宿主
/// show-placeholder 条件口径）：只看**首个子节点**的 text
/// 真值——首子节点不存在或其 text 为空串才显占位；首子
/// 节点是纯空格字符串时 text 为真值、不显（旧实现用整块
/// plain_text().trim() 判定，纯空格单段会误显、与原版相
/// 反）。等价面：真空段（无子节点/首子节点空串）两口径
/// 一致；差异面仅在「首子节点非空但整块 trim 为空」（纯
/// 空格）与「首子节点空串但后续子节点有文本」两类形态，
/// 均按原版字面口径走。
pub(super) fn placeholder_shows(block: &Node) -> bool {
    match block.children.as_ref().and_then(|c| c.first()) {
        Some(first) => first.text.as_deref().unwrap_or("").is_empty(),
        None => true,
    }
}

/// UTF-16 码元偏移 → 字符串字节下标（劈点落在代理对中间
/// 时钳到该字符起点；光标口径下不应发生，仅作防御）。
pub(super) fn utf16_byte_index(t: &str, off16: usize) -> usize {
    let mut acc = 0;
    for (bi, ch) in t.char_indices() {
        if acc >= off16 {
            return bi;
        }
        acc += ch.len_utf16();
    }
    t.len()
}

/// 按 UTF-16 偏移把行内列劈成前后两半（口径契约同
/// plain_len）。劈点在文本节点中间时克隆节点分置两侧；
/// 链接节点递归劈其子列；恰在边界时整节点归前侧。
pub(super) fn split_inlines_at(inlines: &[Node], off16: usize) -> (Vec<Node>, Vec<Node>) {
    let mut head: Vec<Node> = Vec::new();
    let mut tail: Vec<Node> = Vec::new();
    let mut rest = off16;
    let mut done = false;
    for n in inlines {
        if done {
            tail.push(n.clone());
            continue;
        }
        let l = n.plain_text().encode_utf16().count();
        if rest > l {
            head.push(n.clone());
            rest -= l;
            continue;
        }
        if rest == l {
            head.push(n.clone());
            done = true;
            continue;
        }
        // rest < l
        if rest == 0 {
            tail.push(n.clone());
            done = true;
            continue;
        }
        if n.node_type.as_deref() == Some("link") {
            let kids = n.children.clone().unwrap_or_default();
            let (h, t) = split_inlines_at(&kids, rest);
            if !h.is_empty() {
                let mut hn = n.clone();
                hn.children = Some(h);
                head.push(hn);
            }
            if !t.is_empty() {
                let mut tn = n.clone();
                tn.children = Some(t);
                tail.push(tn);
            }
        } else if let Some(t) = &n.text {
            let bi = utf16_byte_index(t, rest);
            let (h, tl) = t.split_at(bi);
            if !h.is_empty() {
                let mut hn = n.clone();
                hn.text = Some(h.to_string());
                head.push(hn);
            }
            if !tl.is_empty() {
                let mut tn = n.clone();
                tn.text = Some(tl.to_string());
                tail.push(tn);
            }
        } else {
            // 无文本的异型行内节点：整体归尾侧，不吞内容
            tail.push(n.clone());
        }
        done = true;
    }
    (head, tail)
}

/// 文档顺序的全部可编辑单元（顶层文本块 + 列表项），与
/// prev_editable 的遍历同序。
pub(super) fn editable_units(doc: &[Node]) -> Vec<Loc> {
    let mut out = Vec::new();
    for (i, b) in doc.iter().enumerate() {
        let ty = b.block_type().unwrap_or("");
        if is_text_block(ty) {
            out.push(Loc::Top(i));
        } else if ty == "bulleted-list" || ty == "numbered-list" {
            if let Some(kids) = &b.children {
                for (j, item) in kids.iter().enumerate() {
                    if item.is_block() {
                        out.push(Loc::Item(i, j));
                    }
                }
            }
        }
    }
    out
}

/// 原子块分类（与 prev_sibling 的 classify_top 同口径）：
/// 非文本块、且不是含项列表（空列表按原子计）。
pub(super) fn is_atomic_class(n: &Node) -> bool {
    let ty = n.block_type().unwrap_or("");
    if is_text_block(ty) {
        return false;
    }
    if ty == "bulleted-list" || ty == "numbered-list" {
        return n.children.as_ref().map(|c| c.is_empty()).unwrap_or(true);
    }
    true
}

pub(super) fn text_node(s: &str) -> Node {
    Node {
        text: Some(s.to_string()),
        ..Default::default()
    }
}

/// 行内列纯文本长度（UTF-16 码元口径，同 plain_len 的光
/// 标偏移契约；唯一调用点是粘贴多行时首块的 dom_set 落点）。
pub(super) fn inlines_len(nodes: &[Node]) -> usize {
    nodes
        .iter()
        .map(|n| n.plain_text().encode_utf16().count())
        .sum()
}

/// attrs 字段读写（原版节点工厂把 level/checked/fileId 放
/// attrs；§2.2 类型化后落 core::Attrs 类型字段，本对函数是
/// 编辑器内的统一写口，键名只认类型化字段集）。
pub(super) fn set_attr(n: &mut Node, key: &str, val: Value) {
    match key {
        "level" => n.attrs.level = val.as_i64(),
        "checked" => n.attrs.checked = val.as_bool(),
        "fileId" => n.attrs.file_id = val.as_str().map(str::to_string),
        "start" => n.attrs.start = val.as_u64(),
        "items" => {
            n.attrs.items = Some(
                val.as_array()
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| {
                                let file_id =
                                    v.get("fileId").and_then(|x| x.as_str()).map(str::to_string);
                                let url =
                                    v.get("url").and_then(|x| x.as_str()).map(str::to_string);
                                if file_id.is_none() && url.is_none() {
                                    None
                                } else {
                                    Some(mynote_core::GalleryEntry { file_id, url })
                                }
                            })
                            .collect()
                    })
                    .unwrap_or_default(),
            );
        }
        "href" => n.attrs.href = val.as_str().map(str::to_string),
        "url" => n.attrs.url = val.as_str().map(str::to_string),
        _ => {}
    }
}

pub(super) fn del_attr(n: &mut Node, key: &str) {
    match key {
        "level" => n.attrs.level = None,
        "checked" => n.attrs.checked = None,
        "fileId" => n.attrs.file_id = None,
        "start" => n.attrs.start = None,
        "items" => n.attrs.items = None,
        "href" => n.attrs.href = None,
        "url" => n.attrs.url = None,
        _ => {}
    }
}

/// 结构化 numbered-list 的起始编号（E-17 ① A 方案，用户
/// 2026-11-24 拍板）：attrs.start = 首项显示号（原版 marked
/// 口径——源段落形态下起始值即首行数字，结构化形态以字段
/// 承载同一语义）。缺失/非法（非整数、<1）一律读为 1：无
/// start 的存量节点按 1 处理，读取不回写、不落多余字段
/// （字节兼容）。
pub(super) fn list_start(n: &Node) -> u64 {
    if n.block_type() != Some("numbered-list") {
        return 1;
    }
    n.attrs.start.filter(|&s| s >= 1).unwrap_or(1)
}

/// 无条件摘除 start 字段（类型互换离开 numbered 时清残留
/// 用，不看当前类型）；attrs 删空后序列化自动整键省略，
/// 不留 "attrs":{} 空壳（Attrs::is_empty 跳过口径）。
pub(super) fn remove_start_field(n: &mut Node) {
    del_attr(n, "start");
}

/// 写起始编号（仅 numbered-list 生效）：start<=1 删字段——
/// 常态（从 1 开始）不落多余字节。
pub(super) fn set_list_start(n: &mut Node, start: u64) {
    if n.block_type() != Some("numbered-list") {
        return;
    }
    if start <= 1 {
        remove_start_field(n);
    } else {
        set_attr(n, "start", json!(start));
    }
}

/// 头部移除 removed 项后，存续项显示号不变：start 相应递
/// 增（原版源段落删首行后 marked 以新首行号为起始的同义
/// 维护）。非 numbered-list 或 removed=0 时无操作。
pub(super) fn shift_list_start(n: &mut Node, removed: u64) {
    if removed == 0 || n.block_type() != Some("numbered-list") {
        return;
    }
    let s = list_start(n) + removed;
    set_list_start(n, s);
}

/// 清掉标题/待办的类型字段（attrs 正形；顶层旧形在类型化
/// 模型上已不存在，无需再清）。
pub(super) fn clear_type_fields(n: &mut Node) {
    del_attr(n, "level");
    del_attr(n, "checked");
}

/// 空段落判定（原版 use-slash.js:541-544 的 next-empty
/// 口径：type=paragraph 且正文为空）。尾随段补插各路共用：
/// 下一块已是现成空段就不多插、焦点改落该段。
pub(super) fn is_empty_para(n: &Node) -> bool {
    n.block_type() == Some("paragraph") && n.plain_text().trim().is_empty()
}

pub(super) fn next_is_empty_para(d: &[Node], i: usize) -> bool {
    d.get(i + 1).map(is_empty_para).unwrap_or(false)
}

/// gallery 写路径归一（去兼容第四步，refactor_remove_compat
/// §2.5）：保证节点是 attrs.items 对象形后再写入——items
/// 缺失时按 children 子节点 fileId 物化（与迁移通道
/// core::migrate 同口径），children 随之清除；在位条目里
/// fileId/url 皆空的无效条目剔除。§2.2 类型化后条目恒为
/// GalleryEntry 对象形（裸串形在模型解析与通道层已绝迹），
/// 写路径只产这一种形态。
pub(super) fn ensure_gallery_items_form(n: &mut Node) {
    if n.attrs.items.is_none() {
        let fids: Vec<String> = n
            .children
            .as_deref()
            .unwrap_or(&[])
            .iter()
            .filter_map(crate::blocks::file_id)
            .collect();
        n.attrs.items = Some(
            fids.into_iter()
                .map(|f| mynote_core::GalleryEntry {
                    file_id: Some(f),
                    url: None,
                })
                .collect(),
        );
        n.children = None;
        return;
    }
    if let Some(items) = &mut n.attrs.items {
        items.retain(|e| {
            e.file_id.as_deref().map(|s| !s.is_empty()).unwrap_or(false)
                || e.url.as_deref().map(|s| !s.is_empty()).unwrap_or(false)
        });
    }
}

/// 当前备忘的 layout 快照（压栈/基线/分叉判定共用读口）。
pub(super) fn memo_layout_json(data: &BackupFile, memo_id: &str) -> Option<String> {
    data.memos
        .iter()
        .find(|m| m.id.to_string() == memo_id)
        .and_then(|m| m.layout.as_ref())
        .map(|l| serde_json::to_string(l).unwrap_or_default())
}

/// 把 layout 快照写回总数据（撤销/重做恢复）：None 清空
/// 锚、回到无锚规范分界。写后由调用方 persist 一并落盘
/// （build_backup 保留 memo.layout，锚随之持久化）。
pub(super) fn apply_memo_layout(data: &mut Signal<BackupFile>, memo_id: &str, layout: Option<&str>) {
    let mut backup = data.read().clone();
    if let Some(m) = backup
        .memos
        .iter_mut()
        .find(|m| m.id.to_string() == memo_id)
    {
        match layout {
            Some(s) => {
                if let Ok(v) = serde_json::from_str::<mynote_core::MemoLayout>(s) {
                    m.layout = Some(v);
                }
            }
            None => {
                m.layout = None;
            }
        }
    }
    data.set(backup);
}

/// 撤销/重做后恢复焦点（编辑态审计 D4）：优先回到操作前所在块
/// （偏移按新文档钳制），块已不存在则落到第一个可编辑块。
/// 没有这一步，epoch 整体重挂载后 activeElement 落到 BODY，
/// 后续打字无处落点。
pub(super) fn restore_focus(
    doc: &[Node],
    focus_req: &mut Signal<Option<(String, usize)>>,
    focus: Option<(String, usize)>,
) {
    if let Some((bid, off)) = focus {
        if let Some(loc) = find_loc(doc, &bid) {
            let len = plain_len(node_at(doc, loc));
            focus_req.set(Some((bid, off.min(len))));
            return;
        }
    }
    if let Some(bid) = first_editable_id(doc) {
        focus_req.set(Some((bid, 0)));
    }
}

/// PERF（第八批 T2）：反向链接的每渲全库扫描缓存。
/// compute_backlinks 此前在 Editor 每次渲染时对全部备忘
/// 逐篇跑 memo_wiki_targets（三趟 Vec<char> 全文变换）；
/// 300 篇库实测单次 ≈12ms、每次打开至少付两遍（守卫修复
/// 后一遍），键入/滚动等会话内重渲同样反复付。targets 只
/// 由备忘 doc 的「wiki 源文本」（collect_wiki_source 口径
/// 收集、'\n' 拼接）决定，故按该源文本的 FNV-1a 指纹做
/// 会话内缓存：指纹未变的备忘直接复用 targets，指纹变了
/// 才重算——结果与逐次现算逐字一致（顺序、标题、命中集
/// 均不变），Diag 的 backlinks log_once 同口径保留。
fn wiki_source_fingerprint(memo: &mynote_core::model::Memo) -> u64 {
    fn hash_bytes(mut h: u64, bytes: &[u8]) -> u64 {
        for &b in bytes {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        h
    }
    fn walk(node: &Node, h: &mut u64, first: &mut bool) {
        // 与 wiki::collect_wiki_source 同口径：code 类节点
        // 整棵子树跳过（其文本不进源文本、不入指纹）。判定
        // 共用 wiki::is_code_node_type（ASCII 免分配快径，
        // PERF 调优续推：本走查每次渲染对全库执行）。
        if let Some(t) = &node.node_type {
            if crate::wiki::is_code_node_type(t) {
                return;
            }
        }
        if let Some(text) = &node.text {
            if !*first {
                *h = hash_bytes(*h, b"\n");
            }
            *first = false;
            *h = hash_bytes(*h, text.as_bytes());
        }
        if let Some(children) = &node.children {
            for c in children {
                walk(c, h, first);
            }
        }
    }
    let mut h: u64 = 0xcbf29ce484222325;
    let mut first = true;
    for block in &memo.doc {
        walk(block, &mut h, &mut first);
    }
    h
}

pub(super) type BacklinkCache =
    std::rc::Rc<std::cell::RefCell<std::collections::HashMap<String, (u64, std::collections::HashSet<String>)>>>;

/// compute_backlinks 的缓存等价版：语义/结果与原版逐字一致，
/// 仅把未变化备忘的 targets 提取换成指纹命中复用。
/// PERF（调优续推）：有缓存未命中（真重算）时记一行 PERF
/// 计时（含指纹走查 + 未命中篇的 targets 提取总耗时），
/// 首渲全库扫描的成本从此在 Diag 里可直接读数。
pub(super) fn backlinks_cached(
    cache: &BacklinkCache,
    memos: &[mynote_core::model::Memo],
    current_id: &str,
    live_title: &str,
) -> Vec<(String, String)> {
    let effective = if live_title.trim() == "无标题" {
        ""
    } else {
        live_title
    };
    let key = crate::wiki::wiki_title_key(effective);
    if key.is_empty() {
        return Vec::new();
    }
    let t_start = js_sys::Date::now();
    let mut misses = 0usize;
    let mut extract_ms = 0.0f64;
    let mut cache = cache.borrow_mut();
    let mut out: Vec<(String, String)> = Vec::new();
    for m in memos {
        let mid = m.id.to_string();
        if mid == current_id {
            continue;
        }
        let fp = wiki_source_fingerprint(m);
        let targets = match cache.get(&mid) {
            Some((cached_fp, targets)) if *cached_fp == fp => targets.clone(),
            _ => {
                misses += 1;
                let t_ex = js_sys::Date::now();
                let targets = crate::wiki::memo_wiki_targets(m);
                extract_ms += js_sys::Date::now() - t_ex;
                cache.insert(mid.clone(), (fp, targets.clone()));
                targets
            }
        };
        if targets.contains(&key) {
            out.push((mid, m.title.clone().unwrap_or_default()));
        }
    }
    if misses > 0 {
        diag::log(
            "PERF",
            &format!(
                "backlinks compute {misses} memo(s) in {:.1}ms (extract {:.1}ms)",
                js_sys::Date::now() - t_start,
                extract_ms
            ),
        );
    }
    diag::log_once(
        &format!("backlinks:{current_id}:{key}:{}", out.len()),
        "WIKI",
        &format!("backlinks '{live_title}' <- {} memo(s)", out.len()),
    );
    out
}

/// 冷开预热（列表页空闲期由 warmup 模块以合成备忘调用）：
/// 预跑打开路径上的纯函数——wiki 源文本指纹走查（编辑器
/// 每渲对全库执行）与双栏分界（规范估高 + 锚归一两条路）。
/// 不触碰编辑器状态、signal 与桥。返回工作量读数。
pub(crate) fn warm_open_pure_paths(memos: &[mynote_core::model::Memo]) -> usize {
    let mut work = 0usize;
    // 合成锚：与 warmup 语料的块 id 对齐（wb1/wb2 左、wb5 起右）
    let layout: mynote_core::MemoLayout = serde_json::from_str(
        r#"{"left":["wb1","wb2"],"right":["wb5"]}"#,
    )
    .unwrap_or_default();
    for memo in memos {
        work = work.wrapping_add(wiki_source_fingerprint(memo) as usize);
        work += column_boundary(&memo.doc, None);
        work += column_boundary(&memo.doc, Some(&layout));
    }
    work
}

#[cfg(test)]
mod e17_start_tests {
    use super::*;

    fn numbered(start: Option<u64>, items: &[&str]) -> Node {
        // 直构字面量（不走 new_block/gen_id：主机靶测试无
        // wasm 导入可用）。
        let mut n = Node {
            text: None,
            node_type: Some("numbered-list".to_string()),
            id: Some("l".to_string()),
            children: None,
            ..Default::default()
        };
        if let Some(s) = start {
            set_attr(&mut n, "start", json!(s));
        }
        n.children = Some(
            items
                .iter()
                .map(|t| Node {
                    text: None,
                    node_type: Some("list-item".to_string()),
                    id: None,
                    children: Some(vec![text_node(t)]),
                    ..Default::default()
                })
                .collect(),
        );
        n
    }

    fn shown_numbers(list: &Node) -> Vec<u64> {
        let start = list_start(list);
        (0..list.children.as_ref().map(|c| c.len()).unwrap_or(0) as u64)
            .map(|i| start + i)
            .collect()
    }

    /// 无 start 存量节点：读为 1；写 1 不落字段、序列化逐字
    /// 不变（不冒 attrs 空壳）。
    #[test]
    fn stock_node_without_start_reads_1_and_stays_byte_identical() {
        let n = numbered(None, &["甲", "乙"]);
        let before = serde_json::to_string(&n).unwrap();
        assert_eq!(list_start(&n), 1);
        let mut m = n.clone();
        set_list_start(&mut m, 1);
        shift_list_start(&mut m, 0);
        assert_eq!(serde_json::to_string(&m).unwrap(), before);
        assert!(!before.contains("attrs"), "phantom attrs: {before}");
    }

    /// 删首项（op_merge 删首项支同语义：remove(0) +
    /// shift 1）：start 3 的三项删首项 → start 4，存续项
    /// 显示号 4/5 不变。
    #[test]
    fn delete_first_item_bumps_start_keeps_survivor_numbers() {
        let mut n = numbered(Some(3), &["甲项", "乙项", "丙项"]);
        assert_eq!(shown_numbers(&n), vec![3, 4, 5]);
        n.children.as_mut().unwrap().remove(0);
        shift_list_start(&mut n, 1);
        assert_eq!(list_start(&n), 4);
        assert_eq!(shown_numbers(&n), vec![4, 5]);
    }

    /// 删中间项：start 不动，其后项号顺移（原版删中间行
    /// 同义）。
    #[test]
    fn delete_middle_item_keeps_start_shifts_followers() {
        let mut n = numbered(Some(3), &["甲项", "乙项", "丙项"]);
        n.children.as_mut().unwrap().remove(1);
        // 删非首项不调 start（op 层无 shift 调用）
        assert_eq!(list_start(&n), 3);
        assert_eq!(shown_numbers(&n), vec![3, 4]);
    }

    /// 拆分尾表传递（op_split/op_convert/媒体占位同口径）：
    /// start=3 的表在 ii=0 处拆出尾表 → 尾 start = 3+0+1。
    #[test]
    fn split_tail_inherits_first_item_number() {
        let n = numbered(Some(3), &["甲项", "乙项", "丙项"]);
        let mut tail = n.clone();
        tail.children = Some(n.children.as_ref().unwrap()[1..].to_vec());
        set_list_start(&mut tail, list_start(&n) + 1);
        assert_eq!(shown_numbers(&tail), vec![4, 5]);
        // start=1 常态在 ii=1 拆分：尾 start=3 须落字段
        let m = numbered(None, &["一", "二", "三"]);
        let mut tail2 = m.clone();
        tail2.children = Some(m.children.as_ref().unwrap()[2..].to_vec());
        set_list_start(&mut tail2, list_start(&m) + 2);
        assert_eq!(list_start(&tail2), 3);
        assert!(serde_json::to_string(&tail2)
            .unwrap()
            .contains(r#""start":3"#));
    }

    /// 类型互换清残留：numbered(start=3) → bulleted 摘除
    /// start；转回 numbered 读为默认 1（不复活旧值）。
    #[test]
    fn type_conversion_clears_start_no_resurrection() {
        let mut n = numbered(Some(3), &["甲项"]);
        n.node_type = Some("bulleted-list".to_string());
        remove_start_field(&mut n);
        let s = serde_json::to_string(&n).unwrap();
        assert!(!s.contains("start"), "stale start kept: {s}");
        n.node_type = Some("numbered-list".to_string());
        assert_eq!(list_start(&n), 1);
    }

    /// shift 对 bulleted 无操作（不给无序表写 start）。
    #[test]
    fn shift_ignores_bulleted() {
        let mut b = Node {
            text: None,
            node_type: Some("bulleted-list".to_string()),
            id: Some("b".to_string()),
            children: Some(vec![Node {
                text: None,
                node_type: Some("list-item".to_string()),
                id: None,
                children: Some(vec![text_node("项")]),
                ..Default::default()
            }]),
            ..Default::default()
        };
        let before = serde_json::to_string(&b).unwrap();
        shift_list_start(&mut b, 2);
        assert_eq!(serde_json::to_string(&b).unwrap(), before);
    }
}

#[cfg(test)]
mod b14_placeholder_tests {
    use super::*;

    fn para(children: Option<Vec<Node>>) -> Node {
        Node {
            text: None,
            node_type: Some("paragraph".to_string()),
            id: Some("p".to_string()),
            children,
            ..Default::default()
        }
    }

    /// 真空段两形态（无子节点 / 首子节点空串）：显占位，
    /// 与旧 trim 口径一致的等价面。
    #[test]
    fn empty_block_shows_placeholder() {
        assert!(placeholder_shows(&para(None)));
        assert!(placeholder_shows(&para(Some(vec![]))));
        assert!(placeholder_shows(&para(Some(vec![text_node("")]))));
    }

    /// B-14 差异面一：首子节点纯空格——原版 text 为真值
    /// 不显；旧整块 trim 口径会误显。
    #[test]
    fn space_only_first_child_hides_placeholder() {
        assert!(!placeholder_shows(&para(Some(vec![text_node(" ")]))));
        assert!(!placeholder_shows(&para(Some(vec![text_node("  x")]))));
    }

    /// B-14 差异面二：首子节点空串、后续子节点有文本——
    /// 原版只看首子节点，仍显占位。
    #[test]
    fn empty_first_child_with_later_text_shows() {
        let n = para(Some(vec![text_node(""), text_node("正文")]));
        assert!(placeholder_shows(&n));
    }

    /// 普通有文本段：不显。
    #[test]
    fn text_block_hides_placeholder() {
        assert!(!placeholder_shows(&para(Some(vec![text_node("正文")]))));
    }
}

// ── 三轮续入：时间/id 基础（自 editor.rs 文件头分流，原文逐字）。

pub(super) fn now_iso() -> String {
    js_sys::Date::new_0()
        .to_iso_string()
        .as_string()
        .unwrap_or_default()
}

pub(super) fn now_millis() -> i64 {
    js_sys::Date::now() as i64
}

pub(super) fn gen_id() -> String {
    let r = js_sys::Math::random();
    format!("b{:x}", (r * 1e12) as u64)
}
