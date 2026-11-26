//! 块操作组（批 14 P-D5 自 editor.rs 拆出）：历史快照与
//! 撤销/重做、块移动/劈分/合并/范围替换、粘贴（卡片/文本）、
//! 智能前缀与类型转换、媒体占位与媒体文件落地、DOM 同步
//! 并入（apply_sync_map）。二轮续入：待恢复输入回收
//! （recover_pending_input）与附件文件落地（attach_file/
//! attach_one）。只做文件组织，行为不变。

use super::model::ensure_gallery_items_form;
use super::*;

/// 历史快照（B-7）：doc JSON + 双栏 layout 快照。原版
/// use-history.js 每条历史含 layout/redoLayout，撤销/重做
/// 时 restoreLayout 把栏分界与滚动模式连同文档一起回
/// 退；Rust 此前只快照 doc，撤销跨栏移动后栏锚不随历史
/// 走、分界按现行锚重算，与撤销前所见栏分布可不一致。
/// layout 取 memo.layout 的序列化（None = 无锚，
/// 含流式不写锚的备忘）；成对快照后撤销/重做天然各取目
/// 标条目的 layout，等价原版 layout/redoLayout 双轨。
#[derive(Clone, PartialEq)]
pub(super) struct HistSnap {
    pub(super) doc: String,
    pub(super) layout: Option<String>,
}

/// 压入一个新快照（原版 use-history.js recordUndoPoint 口
/// 径）：上限 100 步；coalesce 的连续输入在 600ms 内替换栈
/// 顶当前快照（撤销一次回到输入爆发前），结构性压栈断开
/// 合并链。撤销/重做后 idx 不在栈顶，同样不合并。快照相
/// 等判定含 layout（B-7）：仅 layout 变化也成撤销点。
pub(super) fn hist_push(
    mut hist: Signal<Vec<HistSnap>>,
    mut hist_idx: Signal<usize>,
    mut hist_clock: Signal<(f64, bool)>,
    snap: HistSnap,
    coalesce: bool,
) {
    let mut h = hist.read().clone();
    let idx = *hist_idx.read();
    if h.get(idx) == Some(&snap) {
        return;
    }
    let now = perf_now_ms();
    let (last_at, chain) = *hist_clock.read();
    if coalesce && chain && idx + 1 == h.len() && now - last_at < 600.0 {
        h[idx] = snap;
        hist.set(h);
        hist_clock.set((now, true));
        diag::log_once("hist-coalesce", "EDIT", "undo point coalesced (600ms window)");
        return;
    }
    h.truncate(idx + 1);
    h.push(snap);
    if h.len() > 100 {
        h.remove(0);
    }
    hist_idx.set(h.len() - 1);
    hist.set(h);
    hist_clock.set((now, coalesce));
}

/// 撤销一步：先把（可选的）DOM 全量同步并入模型并压栈，保证
/// 当前状态可被重做找回，再回到上一快照整体重挂载。
/// 菜单与键盘（桥）两路共用，行为一致（编辑态审计 D2/D4）。
#[allow(clippy::too_many_arguments)]
pub(super) fn step_undo(
    doc: &mut Signal<Vec<Node>>,
    hist: &mut Signal<Vec<HistSnap>>,
    hist_idx: &mut Signal<usize>,
    hist_clock: &mut Signal<(f64, bool)>,
    epoch: &mut Signal<u32>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    persist: &PersistHandle,
    mut data: Signal<BackupFile>,
    title: &Signal<String>,
    memo_id: &str,
    sync_json: Option<&str>,
    focus: Option<(String, usize)>,
    mut layout_sig: Signal<Option<moment_core::MemoLayout>>,
) {
    let mut d = doc.read().clone();
    if let Some(s) = sync_json {
        apply_sync_map(&mut d, s);
        doc.set(d.clone());
    }
    let cur = HistSnap {
        doc: serde_json::to_string(&d).unwrap_or_default(),
        layout: layout_json(&layout_sig.read().clone()),
    };
    let mut h = hist.read().clone();
    let mut idx = *hist_idx.read();
    if h.get(idx) != Some(&cur) {
        h.truncate(idx + 1);
        h.push(cur.clone());
        if h.len() > 100 {
            h.remove(0);
        }
        idx = h.len() - 1;
    }
    // 撤销打断输入合并链（原版 undo 后 lastPushAt 归零同义）
    hist_clock.set((0.0, false));
    if idx == 0 {
        hist.set(h);
        hist_idx.set(idx);
        return;
    }
    idx -= 1;
    let snap = h[idx].clone();
    if let Ok(nd) = serde_json::from_str::<Vec<Node>>(&snap.doc) {
        doc.set(nd.clone());
        let e = *epoch.read();
        epoch.set(e + 1);
        // B-7：栏布局随快照一并回退（原版 restoreLayout）
        if snap.layout != cur.layout {
            apply_memo_layout(&mut data, memo_id, snap.layout.as_deref(), &mut layout_sig);
            diag::log(
                "EDIT",
                &format!(
                    "undo layout <- {}",
                    if snap.layout.is_some() { "anchored" } else { "none" }
                ),
            );
        }
        restore_focus(&nd, focus_req, focus);
        persist.call(nd, title.read().clone(), data);
        diag::log("EDIT", &format!("undo -> snapshot {idx}"));
    }
    hist.set(h);
    hist_idx.set(idx);
}

/// 重做一步：同样先同步并压栈——撤销后又打了字再重做时，
/// 同步值与栈顶不一致说明历史已分叉，按新分支处理（压栈后
/// 不再前进），避免旧未来快照吞掉新输入。
#[allow(clippy::too_many_arguments)]
pub(super) fn step_redo(
    doc: &mut Signal<Vec<Node>>,
    hist: &mut Signal<Vec<HistSnap>>,
    hist_idx: &mut Signal<usize>,
    hist_clock: &mut Signal<(f64, bool)>,
    epoch: &mut Signal<u32>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    persist: &PersistHandle,
    mut data: Signal<BackupFile>,
    title: &Signal<String>,
    memo_id: &str,
    sync_json: Option<&str>,
    focus: Option<(String, usize)>,
    mut layout_sig: Signal<Option<moment_core::MemoLayout>>,
) {
    let mut d = doc.read().clone();
    if let Some(s) = sync_json {
        apply_sync_map(&mut d, s);
        doc.set(d.clone());
    }
    let cur = HistSnap {
        doc: serde_json::to_string(&d).unwrap_or_default(),
        layout: layout_json(&layout_sig.read().clone()),
    };
    let mut h = hist.read().clone();
    let idx = *hist_idx.read();
    // 重做同样打断输入合并链
    hist_clock.set((0.0, false));
    if h.get(idx) != Some(&cur) {
        h.truncate(idx + 1);
        h.push(cur);
        if h.len() > 100 {
            h.remove(0);
        }
        let top = h.len() - 1;
        hist.set(h);
        hist_idx.set(top);
        return; // 已分叉：新输入即最新状态，无旧未来可重做
    }
    if idx + 1 < h.len() {
        let snap = h[idx + 1].clone();
        if let Ok(nd) = serde_json::from_str::<Vec<Node>>(&snap.doc) {
            doc.set(nd.clone());
            let e = *epoch.read();
            epoch.set(e + 1);
            // B-7：重做同样恢复目标条目的 layout
            if snap.layout != cur.layout {
                apply_memo_layout(&mut data, memo_id, snap.layout.as_deref(), &mut layout_sig);
                diag::log(
                    "EDIT",
                    &format!(
                        "redo layout <- {}",
                        if snap.layout.is_some() { "anchored" } else { "none" }
                    ),
                );
            }
            restore_focus(&nd, focus_req, focus);
            hist_idx.set(idx + 1);
            persist.call(nd, title.read().clone(), data);
            diag::log("EDIT", &format!("redo -> snapshot {}", idx + 1));
        }
    }
    hist.set(h);
}

/// 块拖拽排序（新增能力）：原版 src/app/editor.js 有一套
/// 从未接线的死实现（onDragStart/onDragOver/onDragEnd 无任
/// 何引用、无元素被设 draggable、活体不可用），其数据语义
/// 在此沿用——remove+insert 重排、双栏时保持分界块数。桥
/// 在落点确认后发 moveBlock{ids, to, sync}：ids 是拖动单元
/// 覆盖的顶层块（列表组为多块），to 是原文档序的插入位
/// （插到该位块之前，to == len 为文末）。先按 sync 全量同
/// 步 DOM 文本（与撤销路径同口径），再重排；layout 锚存在
/// 时按重排前分界块数重写锚（新序在同一切分点分栏，与原
/// 版 afterLayout 及关闭保存的写锚口径一致，normalize 自
/// 洽）；落盘一次，历史由消息循环按文档变化自动压栈（结
/// 构性、断合并链），故撤销可回退。
#[allow(clippy::too_many_arguments)]
pub(super) fn op_move_block(
    doc: &mut Signal<Vec<Node>>,
    mut data: Signal<BackupFile>,
    memo_id: &str,
    title: &Signal<String>,
    ids: &[String],
    to: usize,
    sync: Option<&str>,
    persist: &PersistHandle,
    mut layout_sig: Signal<Option<moment_core::MemoLayout>>,
) {
    if ids.is_empty() {
        return;
    }
    let mut d = doc.read().clone();
    if let Some(s) = sync {
        apply_sync_map(&mut d, s);
    }
    let Some(Loc::Top(start)) = find_loc(&d, &ids[0]) else {
        diag::log(
            "EDIT",
            &format!("move block abort: head {} not top-level", ids[0]),
        );
        return;
    };
    let n = ids.len();
    let contiguous = d.get(start..start + n).is_some_and(|seg| {
        seg.iter()
            .zip(ids.iter())
            .all(|(node, id)| node.id.as_deref() == Some(id.as_str()))
    });
    if !contiguous {
        diag::log("EDIT", "move block abort: ids not contiguous");
        return;
    }
    if to >= start && to <= start + n {
        // 落回原范围 = 顺序无变化；sync 可能带了文本变化，
        // 照常落盘（与菜单打开时的全量同步同义）。
        if sync.is_some() {
            doc.set(d.clone());
            persist.call(d, title.read().clone(), data);
        }
        return;
    }
    // 双栏锚：重排前先记分界（锚存在才维护；无锚时分界是
    // 文档内容的确定性纯函数，重排后自动重算）。
    let layout_before = layout_sig.read().clone();
    let boundary = layout_before
        .as_ref()
        .map(|l| column_boundary(&d, Some(l)));
    let seg: Vec<Node> = d.drain(start..start + n).collect();
    let insert_at = if to > start { to - n } else { to }.min(d.len());
    for (k, node) in seg.into_iter().enumerate() {
        d.insert(insert_at + k, node);
    }
    doc.set(d.clone());
    if let (Some(l), Some(b)) = (layout_before, boundary) {
        let mode = l.mode.as_deref().unwrap_or("independent").to_string();
        let ids_v: Vec<String> = d
            .iter()
            .map(|x| x.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
            .collect();
        let (left, right) = ids_v.split_at(b.min(ids_v.len()));
        let new_layout = moment_core::MemoLayout {
            version: Some(1),
            mode: Some(mode),
            left: Some(left.to_vec()),
            right: Some(right.to_vec()),
        };
        let mut backup = data.read().clone();
        if let Some(m) = backup
            .memos
            .iter_mut()
            .find(|m| m.id.to_string() == memo_id)
        {
            m.layout = Some(new_layout.clone());
        }
        data.set(backup);
        layout_sig.set(Some(new_layout));
    }
    persist.call(d.clone(), title.read().clone(), data);
    diag::log(
        "EDIT",
        &format!("move block {} x{n} {start} -> {insert_at}", ids[0]),
    );
}

/// 把 {bid: innerHTML} 同步进文档的文本块（行内重解析）。
pub(super) fn apply_sync_map(doc: &mut Vec<Node>, map_json: &str) {
    let Ok(map) = serde_json::from_str::<Map<String, Value>>(map_json) else {
        return;
    };
    fn apply(nodes: &mut [Node], map: &Map<String, Value>) {
        for n in nodes.iter_mut() {
            let ty = n.block_type().unwrap_or("").to_string();
            if is_text_block(&ty) {
                if let Some(bid) = &n.id {
                    if let Some(html) = map.get(bid).and_then(|v| v.as_str()) {
                        n.children = Some(editor_html_to_inlines(html));
                    }
                }
            }
            if ty == "bulleted-list" || ty == "numbered-list" {
                if let Some(kids) = &mut n.children {
                    apply(kids, map);
                }
            }
        }
    }
    apply(doc, &map);
}

pub(super) fn op_split(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    before_html: &str,
    after_html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
) {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("split: block not found {bid}"));
        return;
    };
    let cur = node_at(&d, loc).clone();
    let ty = cur.block_type().unwrap_or("paragraph").to_string();
    let before_inlines = editor_html_to_inlines(before_html);
    let after_inlines = editor_html_to_inlines(after_html);
    let before_text: String = before_inlines.iter().map(|n| n.plain_text()).collect();
    let after_text: String = after_inlines.iter().map(|n| n.plain_text()).collect();

    // 空列表项回车 = 退出列表（该项变段落，后续项另起一表）。
    // 空块的 before/after 文本只含 <br> 换行（\n），须 trim 判空。
    if let Loc::Item(li, ii) = loc {
        if before_text.trim().is_empty() && after_text.trim().is_empty() {
            let list = d[li].clone();
            let items = list.children.clone().unwrap_or_default();
            let tail: Vec<Node> = items.iter().skip(ii + 1).cloned().collect();
            let para = new_block("paragraph");
            let para_id = para.id.clone().unwrap_or_default();
            let insert_at = if ii > 0 {
                d[li].children = Some(items[..ii].to_vec());
                li + 1
            } else {
                d.remove(li);
                li
            };
            d.insert(insert_at, para);
            if !tail.is_empty() {
                let mut nl = list.clone();
                nl.id = Some(gen_id());
                nl.children = Some(tail);
                // E-17 ①：尾表首项原显示号 = 原 start + ii + 1
                //（被退出项占一号），按首项号语义传递 start。
                set_list_start(&mut nl, list_start(&list) + (ii + 1) as u64);
                d.insert(insert_at + 1, nl);
            }
            doc.set(d);
            focus_req.set(Some((para_id, 0)));
            diag::log("EDIT", &format!("split-exit-list {bid}"));
            return;
        }
    }

    // 标题/标注回车（编辑态审计 B1，原版 editor.js:2080-2114）：
    // 不拆分文本——原块整段保留（空块亦然），只在其后插入一个
    // 空段落并把光标放进去。桥已 preventDefault，DOM 仍是全文，
    // 模型不动即与 DOM 一致，无需回写。标题口径与 Notion 一致，
    // 调优评估（audit_tuning_report.md）结论为保留。
    if matches!(ty.as_str(), "heading" | "callout") {
        if let Loc::Top(i) = loc {
            let para = new_block("paragraph");
            let para_id = para.id.clone().unwrap_or_default();
            d.insert(i + 1, para);
            doc.set(d);
            focus_req.set(Some((para_id, 0)));
            diag::log("EDIT", &format!("split-styled-insert-para {bid}"));
            return;
        }
    }

    // 待办/引用回车（调优评估结论，偏离原版 B1 口径）：主流编辑器
    // （Notion/Apple Notes/Obsidian/飞书/Word）无一例外做延续——
    // 有内容按光标拆为同型新块（新待办未勾选）；空块回车则自身
    // 转段落退出（与空列表项退出列表同构），避免留空待办垃圾块
    // 与每条待办重走一遍斜杠的交互成本。拆分走下方通用路径。
    if matches!(ty.as_str(), "todo" | "quote")
        && before_text.trim().is_empty()
        && after_text.trim().is_empty()
    {
        let n = node_at_mut(&mut d, loc);
        n.node_type = Some("paragraph".to_string());
        n.attrs = moment_core::Attrs::default();
        // 子节点一并清空：清空动作可能还没经 autosync 进模型，
        // 不清的话旧文本会随类型转换被重新渲染出来（实测教训）
        n.children = Some(vec![empty_text_node()]);
        doc.set(d);
        focus_req.set(Some((bid.to_string(), 0)));
        diag::log("EDIT", &format!("split-exit-styled {bid}"));
        return;
    }

    let new_ty = match ty.as_str() {
        "list-item" => "list-item",
        "todo" => "todo",
        "quote" => "quote",
        _ => "paragraph",
    };
    let mut new_block = new_block(new_ty);
    if new_ty == "todo" {
        set_attr(&mut new_block, "checked", json!(false));
    }
    new_block.children = Some(after_inlines);
    let new_id = new_block.id.clone().unwrap_or_default();

    {
        let n = node_at_mut(&mut d, loc);
        n.children = Some(before_inlines);
    }
    match loc {
        Loc::Top(i) => d.insert(i + 1, new_block),
        Loc::Item(li, ii) => {
            d[li].children.as_mut().unwrap().insert(ii + 1, new_block);
        }
    }
    doc.set(d);
    // 源块 DOM 回写（编辑态审计 D1）：源块是非受控 DOM，模型拆分
    // 后它的 innerHTML 仍是拆分前全文，不回写则屏幕重复显示，
    // 且 autosync/开菜单/返回会拿旧 DOM 覆盖模型落库。回写内容
    // 就是桥传来的 before 片段，与模型解析源逐字一致；焦点由
    // focus_req 落到新块（dom_set 的附带聚焦会被其覆盖）。
    dom_set.set(Some((
        bid.to_string(),
        before_html.to_string(),
        before_text.encode_utf16().count(),
    )));
    focus_req.set(Some((new_id, 0)));
}

/// 退格合并的目标分类：文档顺序里**紧邻**的上一个块。
/// 此前 op_merge 沿文档顺序一路跳过原子块找文本块，
/// [段][图][段] 段首退格会把后段文本越过图片并进前段
/// （跨块语义组 B10 实测）；原版单宿主里文本永不跨原子块
/// 移动，紧邻关系才是规格。
pub(super) enum PrevKind {
    /// 可编辑文本块（列表时为其末项）：常规合并目标。
    Text(Loc),
    /// 原子块（图片/卡片/分割线等不可编辑顶层块）。
    Atomic(usize),
    /// 没有上一个块。
    None,
}

pub(super) fn prev_sibling(doc: &[Node], loc: Loc) -> PrevKind {
    fn classify_top(doc: &[Node], i: usize) -> PrevKind {
        let ty = doc[i].block_type().unwrap_or("");
        if is_text_block(ty) {
            PrevKind::Text(Loc::Top(i))
        } else if ty == "bulleted-list" || ty == "numbered-list" {
            match doc[i].children.as_ref().and_then(|c| c.len().checked_sub(1)) {
                Some(last) => PrevKind::Text(Loc::Item(i, last)),
                None => PrevKind::Atomic(i),
            }
        } else {
            PrevKind::Atomic(i)
        }
    }
    match loc {
        Loc::Top(0) => PrevKind::None,
        Loc::Top(i) => classify_top(doc, i - 1),
        Loc::Item(li, ii) if ii > 0 => PrevKind::Text(Loc::Item(li, ii - 1)),
        Loc::Item(0, _) => PrevKind::None,
        Loc::Item(li, _) => classify_top(doc, li - 1),
    }
}

pub(super) fn op_merge(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
    sel_block: &mut Signal<Option<String>>,
) {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("merge: block not found {bid}"));
        return;
    };
    let remove_cur = |d: &mut Vec<Node>| match loc {
        Loc::Top(i) => {
            d.remove(i);
        }
        Loc::Item(li, ii) => {
            d[li].children.as_mut().unwrap().remove(ii);
            if d[li].children.as_ref().map(|c| c.is_empty()).unwrap_or(false) {
                d.remove(li);
            } else if ii == 0 {
                // E-17 ①：首项被合并/删除，存续首项原号不变
                // → start 递增 1；删非首项不走此支（号顺移）。
                shift_list_start(&mut d[li], 1);
            }
        }
    };
    match prev_sibling(&d, loc) {
        PrevKind::None => {}
        PrevKind::Text(prev_loc) => {
            let junction = plain_len(node_at(&d, prev_loc));
            let prev_id = node_at(&d, prev_loc).id.clone().unwrap_or_default();
            let cur_inlines = editor_html_to_inlines(html);
            let merged_html = {
                let prev = node_at_mut(&mut d, prev_loc);
                let mut kids = prev.children.clone().unwrap_or_default();
                kids.extend(cur_inlines);
                let html = inlines_to_editor_html(&kids);
                prev.children = Some(kids);
                html
            };
            remove_cur(&mut d);
            doc.set(d);
            // 存活块 DOM 回写（编辑态审计 D1）：合并后模型是全文拼接，
            // 存活块的非受控 DOM 仍只有前半，不回写则后半从屏幕消失、
            // 且会被 autosync 以旧 DOM 覆盖落库造成永久丢字。
            dom_set.set(Some((prev_id.clone(), merged_html, junction)));
            focus_req.set(Some((prev_id, junction)));
        }
        PrevKind::Atomic(ai) => {
            let atom_id = d[ai].id.clone().unwrap_or_default();
            let cur_empty = editor_html_to_inlines(html)
                .iter()
                .all(|n| n.plain_text().is_empty());
            if cur_empty {
                // B-3（原版 editor.js 退格分支口径）：空段退
                // 格沿文档序向前跳过**全部**连续原子块，落到
                // 更早文本块末尾一步到位；前面只有原子块/无
                // 块时保留空段、什么都不做（原版 preventDefault
                // 保留空段，避免删除后选区失焦）。全程不删任
                // 何非文本块——原子块原样保留，删卡仍走长按/
                // 右键菜单明路（键盘不变量不破：本支只删空段
                // 本身）。此前实现为删空段+选中紧邻原子块
                // （K3 落点），需再按一次退格且仍无文本光标，
                // 本次按原版与 landing_plan 批 4 口径改落点。
                let mut target: Option<Loc> = None;
                for j in (0..ai).rev() {
                    match prev_sibling(&d, Loc::Top(j + 1)) {
                        PrevKind::Text(t) => {
                            target = Some(t);
                            break;
                        }
                        PrevKind::Atomic(_) => {}
                        PrevKind::None => break,
                    }
                }
                match target {
                    Some(t) => {
                        let target_id = node_at(&d, t).id.clone().unwrap_or_default();
                        let end = plain_len(node_at(&d, t));
                        remove_cur(&mut d);
                        doc.set(d);
                        focus_req.set(Some((target_id.clone(), end)));
                        diag::log(
                            "EDIT",
                            &format!(
                                "merge: empty block removed over atomics, caret to end of {target_id}"
                            ),
                        );
                    }
                    None => {
                        diag::log(
                            "EDIT",
                            "merge: empty block kept (only atomics before)",
                        );
                    }
                }
            } else {
                // 键盘删块收口（K2）：非空块块首退格撞上原子
                // 块时不再删卡（旧行为与「文本被吸入原子 div
                // 后被 parser 丢弃」的原版缺陷同为键盘直删非
                // 文本块，一并收口）——至多把该卡带入选中态
                // （与空段支同落点），两块与文本全保留。
                sel_block.set(Some(atom_id.clone()));
                diag::log(
                    "EDIT",
                    &format!("merge: backspace before atomic {atom_id} selected (kept)"),
                );
            }
        }
    }
}

/// 跨块选区替换（跨块语义组）：桥的虚拟选区在删除/覆打/
/// 回车/粘贴时发 replaceRange。语义对原版单宿主的原生选
/// 区：起止单元各取选区外侧（头/尾）行内，中间文本块整
/// 块删除，头+插入文本+尾并成结果块列置于起始单元处；
/// 光标落插入末尾（回车时落尾块首）。
/// sync 先行全量同步（与 moveBlock/撤销同口径），保证模
/// 型与活 DOM 一致再手术。from_start/to_end 是 Ctrl+A 的
/// 全文标记。
/// 键盘删块收口（K5）：选区内及 Ctrl+A 首尾外侧的原子块
/// 全程存活、原位保留，替换按原子边界分段——首段承接
/// head+插入文本，尾行内由末段首位的新块承接（回车时尾
/// 归末段、光标随之）；无原子介入时与旧行为逐字不变。
#[allow(clippy::too_many_arguments)]
pub(super) fn op_replace_range(
    doc: &mut Signal<Vec<Node>>,
    a_bid: &str,
    a_off: usize,
    f_bid: &str,
    f_off: usize,
    text: &str,
    enter: bool,
    from_start: bool,
    to_end: bool,
    sync: Option<&str>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
) {
    let mut d = doc.read().clone();
    if let Some(s) = sync {
        apply_sync_map(&mut d, s);
    }
    let (Some(a_loc), Some(f_loc)) = (find_loc(&d, a_bid), find_loc(&d, f_bid)) else {
        diag::log("EDIT", "replaceRange: endpoint not found");
        return;
    };
    let units = editable_units(&d);
    let (Some(ia), Some(ie)) = (
        units.iter().position(|u| *u == a_loc),
        units.iter().position(|u| *u == f_loc),
    ) else {
        diag::log("EDIT", "replaceRange: endpoint not editable unit");
        return;
    };
    let ((s_loc, s_off), (e_loc, e_off)) = if ia <= ie {
        ((a_loc, a_off), (f_loc, f_off))
    } else {
        ((f_loc, f_off), (a_loc, a_off))
    };
    let s_kids = node_at(&d, s_loc).children.clone().unwrap_or_default();
    let (head, _) = split_inlines_at(&s_kids, s_off);
    let e_kids = node_at(&d, e_loc).children.clone().unwrap_or_default();
    let (_, tail) = split_inlines_at(&e_kids, e_off);
    let head_len = inlines_len(&head);

    // K5 分段路径：选区内有原子块存活时按原子边界分段重
    // 组（无原子时走下方原路径，行为逐字不变）。
    let s_top = match s_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let e_top = match e_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let atoms_kept = (s_top + 1..e_top)
        .filter(|&t| is_atomic_class(&d[t]))
        .count();
    if atoms_kept > 0 {
        let s_id = node_at(&d, s_loc).id.clone().unwrap_or_default();
        // 首段列：head + 插入文本逐行成列（尾行内不并入首
        // 段，由末段承接）；回车时首段只有 head、尾归末段。
        let mut seg_cols: Vec<Vec<Node>> = Vec::new();
        let (caret_in_tail, caret_col, caret_off);
        if enter {
            seg_cols.push(head);
            caret_in_tail = true;
            caret_col = 0;
            caret_off = 0;
        } else {
            let lines: Vec<&str> = text.split('\n').collect();
            let mut first = head;
            if !lines[0].is_empty() {
                first.push(text_node(lines[0]));
            }
            seg_cols.push(first);
            for mid in &lines[1..] {
                seg_cols.push(if mid.is_empty() {
                    Vec::new()
                } else {
                    vec![text_node(mid)]
                });
            }
            caret_in_tail = false;
            caret_col = seg_cols.len() - 1;
            caret_off = if lines.len() > 1 {
                lines[lines.len() - 1].encode_utf16().count()
            } else {
                head_len + text.encode_utf16().count()
            };
        }
        // 末段承接列：尾行内成新块落末段首位（原尾单元随选
        // 区移除，避免其非受控 DOM 残留旧文与模型脱节）；
        // 非回车且尾为空时不立空块——全选清空后只留首段一
        // 个空段承载光标。
        let tail_col: Option<Vec<Node>> = if enter {
            Some(tail)
        } else if tail.iter().all(|n| n.plain_text().is_empty()) {
            None
        } else {
            Some(tail)
        };
        // 实例化：首段第 0 列写回起始单元、其余列新建块；
        // 末段列新建块（止端为列表项时作列表项进原列表）。
        let mut seg_ids: Vec<String> = vec![s_id.clone()];
        let mut seg_extra: Vec<Node> = Vec::new();
        for kids in seg_cols.iter().skip(1) {
            let mut b = match s_loc {
                Loc::Top(_) => new_block("paragraph"),
                Loc::Item(..) => new_block("list-item"),
            };
            b.children = Some(kids.clone());
            seg_ids.push(b.id.clone().unwrap_or_default());
            seg_extra.push(b);
        }
        let mut tail_block: Option<Node> = None;
        let mut tail_id = String::new();
        if let Some(kids) = &tail_col {
            let mut b = match e_loc {
                Loc::Top(_) => new_block("paragraph"),
                Loc::Item(..) => new_block("list-item"),
            };
            b.children = Some(kids.clone());
            tail_id = b.id.clone().unwrap_or_default();
            tail_block = Some(b);
        }
        // 按文档顺序重组：原子块原位保留，其余按段落位。
        let mut out: Vec<Node> = Vec::new();
        for (t, block) in d.iter().enumerate() {
            if t < s_top {
                if !from_start || is_atomic_class(block) {
                    out.push(block.clone());
                }
                continue;
            }
            if t > e_top {
                if !to_end || is_atomic_class(block) {
                    out.push(block.clone());
                }
                continue;
            }
            if t == s_top {
                match s_loc {
                    Loc::Top(_) => {
                        let mut b = block.clone();
                        b.children = Some(seg_cols[0].clone());
                        out.push(b);
                        out.extend(seg_extra.iter().cloned());
                    }
                    Loc::Item(_, s_ii) => {
                        let mut list = block.clone();
                        let items = list.children.clone().unwrap_or_default();
                        let mut kids: Vec<Node> = Vec::new();
                        if !from_start {
                            kids.extend(items[..s_ii].iter().cloned());
                        }
                        let mut first_item = items[s_ii].clone();
                        first_item.children = Some(seg_cols[0].clone());
                        kids.push(first_item);
                        kids.extend(seg_extra.iter().cloned());
                        // E-17 ①：Ctrl+A 自文档首起删时头部
                        // s_ii 项被丢弃，存续首项（原 s_ii 项
                        // 本身）号不变 → start 递增 s_ii。
                        if from_start {
                            shift_list_start(&mut list, s_ii as u64);
                        }
                        list.children = Some(kids);
                        out.push(list);
                    }
                }
                continue;
            }
            if t == e_top {
                if let Loc::Item(_, e_ii) = e_loc {
                    let items = block.children.clone().unwrap_or_default();
                    let mut kids: Vec<Node> = Vec::new();
                    if let Some(tb) = &tail_block {
                        kids.push(tb.clone());
                    }
                    if !to_end {
                        kids.extend(items[e_ii + 1..].iter().cloned());
                    }
                    if !kids.is_empty() {
                        let mut list = block.clone();
                        // E-17 ①：止表头部项全丢：新首项为尾
                        // 项（原 e_ii 项的尾段）时 start 递增
                        // e_ii；无尾项、由原 e_ii+1 项存续时
                        // 递增 e_ii+1——均保其原显示号。
                        let removed = if tail_block.is_some() {
                            e_ii
                        } else {
                            e_ii + 1
                        };
                        shift_list_start(&mut list, removed as u64);
                        list.children = Some(kids);
                        out.push(list);
                    }
                } else if let Some(tb) = &tail_block {
                    out.push(tb.clone());
                }
                continue;
            }
            // s_top < t < e_top：原子块存活；文本块与含项列
            // 表整块在选区内，丢弃。
            if is_atomic_class(block) {
                out.push(block.clone());
            }
        }
        doc.set(out);
        let (caret_id, caret_final) = if caret_in_tail {
            (tail_id.clone(), caret_off)
        } else {
            (seg_ids[caret_col].clone(), caret_off)
        };
        let unit0_caret = if !caret_in_tail && caret_col == 0 {
            caret_off
        } else {
            inlines_len(&seg_cols[0])
        };
        dom_set.set(Some((
            s_id.clone(),
            inlines_to_editor_html(&seg_cols[0]),
            unit0_caret,
        )));
        focus_req.set(Some((caret_id, caret_final)));
        diag::log(
            "EDIT",
            &format!(
                "replace range {a_bid}@{a_off}..{f_bid}@{f_off} ins={}B enter={enter} atoms kept={atoms_kept}",
                text.len()
            ),
        );
        return;
    }

    // 结果块列（行内列）与光标落点（第几列、列内 UTF-16）
    let mut result: Vec<Vec<Node>> = Vec::new();
    let (caret_unit, caret_off);
    if enter {
        result.push(head);
        result.push(tail);
        caret_unit = 1;
        caret_off = 0;
    } else {
        let lines: Vec<&str> = text.split('\n').collect();
        let mut first = head;
        if !lines[0].is_empty() {
            first.push(text_node(lines[0]));
        }
        result.push(first);
        if lines.len() > 2 {
            for mid in &lines[1..lines.len() - 1] {
                result.push(if mid.is_empty() {
                    Vec::new()
                } else {
                    vec![text_node(mid)]
                });
            }
        }
        if lines.len() > 1 {
            let last = lines[lines.len() - 1];
            let mut last_kids: Vec<Node> = Vec::new();
            if !last.is_empty() {
                last_kids.push(text_node(last));
            }
            last_kids.extend(tail);
            result.push(last_kids);
            caret_unit = result.len() - 1;
            caret_off = last.encode_utf16().count();
        } else {
            let tl = text.encode_utf16().count();
            result[0].extend(tail);
            caret_unit = 0;
            caret_off = head_len + tl;
        }
    }

    let s_top = match s_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let e_top = match e_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let s_id = node_at(&d, s_loc).id.clone().unwrap_or_default();

    // 结果列实例化：第 0 列写回起始单元（保 id/类型），其
    // 余列新建块（顶层段落 / 列表内列表项），记 id 供落点。
    let mut result_ids: Vec<String> = vec![s_id.clone()];
    let mut extra_blocks: Vec<Node> = Vec::new();
    for kids in result.iter().skip(1) {
        let mut b = match s_loc {
            Loc::Top(_) => new_block("paragraph"),
            Loc::Item(..) => new_block("list-item"),
        };
        b.children = Some(kids.clone());
        result_ids.push(b.id.clone().unwrap_or_default());
        extra_blocks.push(b);
    }

    // 按文档顺序重组：起始容器写回结果列，中间整块丢弃，
    // 止容器为止项时保留未覆盖的尾项，其余按 from/to 标记。
    let mut out: Vec<Node> = Vec::new();
    for (t, block) in d.iter().enumerate() {
        if t < s_top {
            if !from_start {
                out.push(block.clone());
            }
            continue;
        }
        if t > e_top {
            if !to_end {
                out.push(block.clone());
            }
            continue;
        }
        if t == s_top {
            match s_loc {
                Loc::Top(_) => {
                    let mut b = block.clone();
                    b.children = Some(result[0].clone());
                    out.push(b);
                    out.extend(extra_blocks.iter().cloned());
                }
                Loc::Item(_, s_ii) => {
                    let mut list = block.clone();
                    let items = list.children.clone().unwrap_or_default();
                    let mut kids: Vec<Node> = Vec::new();
                    if !from_start {
                        kids.extend(items[..s_ii].iter().cloned());
                    }
                    let mut first_item = items[s_ii].clone();
                    first_item.children = Some(result[0].clone());
                    kids.push(first_item);
                    kids.extend(extra_blocks.iter().cloned());
                    // E-17 ①：同 K5 分段路径口径——from_start
                    // 时头部 s_ii 项被丢弃，start 递增 s_ii。
                    if from_start {
                        shift_list_start(&mut list, s_ii as u64);
                    }
                    if s_top == e_top {
                        if let Loc::Item(_, e_ii) = e_loc {
                            if !to_end {
                                kids.extend(items[e_ii + 1..].iter().cloned());
                            }
                        }
                    }
                    list.children = Some(kids);
                    out.push(list);
                }
            }
            continue;
        }
        if t == e_top {
            // 止容器（与起始容器不同）：止单元为列表项时保
            // 留其后未覆盖的项；顶层止块整块已被尾行内抽
            // 走，直接丢弃（to_end 时尾项一并丢弃）。
            if let Loc::Item(_, e_ii) = e_loc {
                if !to_end {
                    let items = block.children.clone().unwrap_or_default();
                    let rest_items: Vec<Node> = items[e_ii + 1..].to_vec();
                    if !rest_items.is_empty() {
                        let mut list = block.clone();
                        // E-17 ①：止表头部 e_ii+1 项全丢，存续
                        // 首项原号不变 → start 递增 e_ii+1（本路
                        // 径尾行内已抽入起始段、无尾项存续）。
                        shift_list_start(&mut list, (e_ii + 1) as u64);
                        list.children = Some(rest_items);
                        out.push(list);
                    }
                }
            }
            continue;
        }
        // s_top < t < e_top：整块在选区内，丢弃
    }
    doc.set(out);

    let caret_id = result_ids[caret_unit].clone();
    let unit0_caret = if caret_unit == 0 {
        caret_off
    } else {
        inlines_len(&result[0])
    };
    dom_set.set(Some((s_id.clone(), inlines_to_editor_html(&result[0]), unit0_caret)));
    focus_req.set(Some((caret_id, caret_off)));
    diag::log(
        "EDIT",
        &format!("replace range {a_bid}@{a_off}..{f_bid}@{f_off} ins={}B enter={enter}", text.len()),
    );
}

/// 粘贴 URL 生成卡片（原版 insertLinkCardAtDOM 口径）：当前
/// 块按光标拆分（前段留原块、后段成新段落），卡片插中间；
/// 音乐域名 → musicCard，其余 → link-card，均先 loading
/// 再由 spawn_resolve_card 回填 meta。remain 非空时在卡后
/// 另起一段（原版「剩余文本保留为卡后段落」）并聚焦它。
pub(super) fn op_paste_card(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    url: &str,
    remain: &str,
    before_html: &str,
    after_html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
) -> Option<String> {
    const MUSIC_HOSTS: [&str; 6] = [
        "music.163.com",
        "163cn.tv",
        "y.qq.com",
        "i.y.qq.com",
        "open.spotify.com",
        "music.apple.com",
    ];
    let is_music = MUSIC_HOSTS.iter().any(|h| url.contains(h));
    let mut d = doc.read().clone();
    let loc = find_loc(&d, bid)?;
    let before = editor_html_to_inlines(before_html);
    let after = editor_html_to_inlines(after_html);
    node_at_mut(&mut d, loc).children = Some(before);
    let top_idx = match loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let mut card = new_block(if is_music { "musicCard" } else { "link-card" });
    card.url = Some(url.to_string());
    card.status = Some("loading".to_string());
    let card_id = card.id.clone().unwrap_or_default();
    let mut at = top_idx + 1;
    d.insert(at, card);
    at += 1;
    let mut focus: Option<(String, usize)> = None;
    if !remain.trim().is_empty() {
        let mut pnode = new_block("paragraph");
        pnode.children = Some(vec![text_node(remain.trim())]);
        let pid = pnode.id.clone().unwrap_or_default();
        d.insert(at, pnode);
        at += 1;
        focus = Some((pid, usize::MAX));
    }
    let after_text: String = after.iter().map(|n| n.plain_text()).collect();
    if !after_text.is_empty() {
        let mut pnode = new_block("paragraph");
        pnode.children = Some(after);
        let pid = pnode.id.clone().unwrap_or_default();
        d.insert(at, pnode);
        if focus.is_none() {
            focus = Some((pid, 0));
        }
    }
    if focus.is_none() {
        // 原版 insertAtomicBlockToDOM 恒保证卡片后有可编辑块
        // 并聚焦其开头：remain/after 都为空时，卡后现成的文本
        // 块直接用；不是文本块（或没有下一块）就补空段落。
        // 缺这一步时光标会滞留在卡片之前的原段落里。
        let card_at = top_idx + 1;
        let next_is_text = d
            .get(card_at + 1)
            .map(|n| is_text_block(n.block_type().unwrap_or("")))
            .unwrap_or(false);
        if next_is_text {
            let pid = d[card_at + 1].id.clone().unwrap_or_default();
            if !pid.is_empty() {
                focus = Some((pid, 0));
            }
        } else {
            let pnode = new_block("paragraph");
            let pid = pnode.id.clone().unwrap_or_default();
            d.insert(card_at + 1, pnode);
            focus = Some((pid, 0));
        }
    }
    diag::log("CARD", &format!("skeleton {card_id}"));
    doc.set(d);
    if let Some(f) = focus {
        focus_req.set(Some(f));
    }
    Some(card_id)
}

/// 极小 base64 解码（粘贴图片字节通路；无第三方依赖）。
pub(super) fn b64_decode(s: &str) -> Vec<u8> {
    let mut table = [255u8; 256];
    for (i, c) in b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        .iter()
        .enumerate()
    {
        table[*c as usize] = i as u8;
    }
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let mut acc: u32 = 0;
    let mut nbits = 0u32;
    for &b in s.as_bytes() {
        if b == b'=' {
            break;
        }
        let v = table[b as usize];
        if v == 255 {
            continue;
        }
        acc = (acc << 6) | v as u32;
        nbits += 6;
        if nbits >= 8 {
            nbits -= 8;
            out.push((acc >> nbits) as u8);
        }
    }
    out
}

/// 单块光标处的多行纯文本粘贴（桥 pasteText）：首行并入
/// 当前块保其类型，中间行各成新段，末行带上光标后的原内
/// 容，当前块 DOM 由 dom_set 回写对齐。与跨块选区替换的
/// op_replace_range 是两条独立路径（批 1 B-8 衔接）：后者
/// 对 xsel 选区的替换文本同样按行拆块——2026-11-23 双侧
/// 活体量测证实原版 insertText+parse 对跨块选区粘贴亦按
/// 行落块（含 \n\n 生成空块），两侧口径一致，非死代码、
/// 不再合并。
pub(super) fn op_paste_text(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    before_html: &str,
    after_html: &str,
    lines: &[String],
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
) {
    if lines.len() < 2 {
        return;
    }
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("pasteText: block not found {bid}"));
        return;
    };
    let before = editor_html_to_inlines(before_html);
    let after = editor_html_to_inlines(after_html);
    let mut first_kids = before;
    first_kids.push(text_node(&lines[0]));
    let first_html = inlines_to_editor_html(&first_kids);
    let first_len = inlines_len(&first_kids);
    node_at_mut(&mut d, loc).children = Some(first_kids);

    let last_idx = lines.len() - 1;
    let mut new_blocks: Vec<Node> = Vec::new();
    for (k, line) in lines.iter().enumerate().skip(1) {
        let mut kids = vec![text_node(line)];
        if k == last_idx {
            kids.extend(after.clone());
        }
        let mut b = match loc {
            Loc::Top(_) => new_block("paragraph"),
            Loc::Item(..) => new_block("list-item"),
        };
        b.children = Some(kids);
        new_blocks.push(b);
    }
    let last_id = new_blocks
        .last()
        .and_then(|b| b.id.clone())
        .unwrap_or_default();
    let last_len = lines[last_idx].encode_utf16().count();
    match loc {
        Loc::Top(i) => {
            for (k, b) in new_blocks.into_iter().enumerate() {
                d.insert(i + 1 + k, b);
            }
        }
        Loc::Item(li, ii) => {
            for (k, b) in new_blocks.into_iter().enumerate() {
                d[li].children.as_mut().unwrap().insert(ii + 1 + k, b);
            }
        }
    }
    doc.set(d);
    dom_set.set(Some((bid.to_string(), first_html, first_len)));
    focus_req.set(Some((last_id, last_len)));
    diag::log("EDIT", &format!("paste text {} lines into {bid}", lines.len()));
}

/// md 源段落 → 纯文本（去围栏/引用/列表前缀），转换出口径。
pub(super) fn strip_md_prefixes(text: &str) -> String {
    match crate::blocks::md_classify(text) {
        Some(crate::blocks::MdKind::Code(code)) => code,
        Some(crate::blocks::MdKind::Callout { body, .. }) => body.join("\n"),
        Some(crate::blocks::MdKind::List { items, .. }) => items.join("\n"),
        Some(crate::blocks::MdKind::Rich(src)) => src,
        Some(crate::blocks::MdKind::Heading { text, .. }) => text,
        Some(crate::blocks::MdKind::Quote(paras)) => paras.join("\n"),
        Some(crate::blocks::MdKind::Table { .. }) => text.to_string(),
        Some(crate::blocks::MdKind::Divider) => text.to_string(),
        None => text.to_string(),
    }
}

/// 智能前缀命中（原版 editor.js:1919-1956 的 PATTERNS 表，
/// 逐条镜像其 JS 正则语义）：对段落首叶文本（S3 字面口径
/// 下即整段纯文本）判定。(.+) 不跨行——多行文本只看首行，
/// 首行之外的内容在原版转换时一并丢弃，此处同口径。
pub(super) enum PrefixHit {
    Heading(u8, String),
    Quote(String),
    Todo(String),
    Divider,
}

pub(super) fn smart_prefix_match(raw: &str) -> Option<PrefixHit> {
    if raw.is_empty() {
        return None;
    }
    let first_line = raw.split('\n').next().unwrap_or("");
    // ### / ## / # + 字面空格 + 至少一字符（捕获 trim 后为正文）
    for (prefix, level) in [("### ", 3u8), ("## ", 2), ("# ", 1)] {
        if let Some(rest) = first_line.strip_prefix(prefix) {
            if !rest.is_empty() {
                return Some(PrefixHit::Heading(level, rest.trim().to_string()));
            }
        }
    }
    // > + 至少一字符；负向前瞻 (?!\s*\[!\S)：> [!TYPE] 是
    // 标注源段、不转引用（与 md_classify 的 Callout 同界）
    if let Some(rest) = first_line.strip_prefix('>') {
        if !rest.is_empty() {
            let t = rest.trim_start();
            let callout = t.starts_with("[!")
                && t[2..].chars().next().is_some_and(|c| !c.is_whitespace());
            if !callout {
                return Some(PrefixHit::Quote(rest.trim().to_string()));
            }
        }
    }
    // [ ] / [] + 字面空格 + 至少一字符 → 待办（未勾选）
    for prefix in ["[ ] ", "[] "] {
        if let Some(rest) = first_line.strip_prefix(prefix) {
            if !rest.is_empty() {
                return Some(PrefixHit::Todo(rest.trim().to_string()));
            }
        }
    }
    // 分隔线：全文恰为 ---（原版 exact 全串相等，不 trim）
    if raw == "---" {
        return Some(PrefixHit::Divider);
    }
    None
}

/// 智能前缀扫描（原版 editor.js:1915-1996）：扫全 doc 顶层
/// 段落（文档序），首个命中者转块型、每周期只转一处，返回
/// (被转换块 id, 聚焦块 id, 光标偏移)。转换形态与斜杠转换
/// 同构（apply_type 口径：同 id、单文本子节点、类型字段先
/// 清后设）；焦点落新块文末（原版 focusEditableWithCaret
/// (caretAt = 转换后文本长度)）。divider 无正文：原版只
/// 原地替换、不补尾随段，焦点落 divider 本身（caretAt
/// =0，聚焦 id 与被转换 id 同为该块）。第四元是被转换块的
/// 编辑态 HTML（dom_set 回写用：非受控块不会自己重渲染，
/// 转换改了文本必须同步改写活 DOM，与 slashApply 同口径）；
/// divider 的旧元素随类型变更卸载，无需回写，为 None。
pub(super) fn apply_smart_prefix(
    doc: &mut Signal<Vec<Node>>,
) -> Option<(String, String, usize, Option<String>)> {
    let mut d = doc.read().clone();
    for i in 0..d.len() {
        if d[i].block_type() != Some("paragraph") {
            continue;
        }
        let raw = d[i].plain_text();
        let Some(hit) = smart_prefix_match(&raw) else {
            continue;
        };
        let bid = d[i].id.clone().unwrap_or_default();
        match hit {
            PrefixHit::Divider => {
                // 原版 editor.js 智能前缀 `---`：只原地替换为
                // divider、不补尾随段；焦点落 divider 本身
                // （focusEditableWithCaret(命中元素, 0)——
                // divider 无 children 故 caretAt=0）。
                let mut div = new_block("divider");
                div.id = Some(bid.clone());
                div.children = None;
                d[i] = div;
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> divider {bid}"));
                return Some((bid.clone(), bid, 0, None));
            }
            PrefixHit::Heading(level, text) => {
                let len = text.chars().count();
                let kids = vec![text_node(&text)];
                let html = inlines_to_editor_html(&kids);
                let n = &mut d[i];
                n.node_type = Some("heading".to_string());
                clear_type_fields(n);
                set_attr(n, "level", json!(level as u64));
                n.children = Some(kids);
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> heading{level} {bid}"));
                return Some((bid.clone(), bid, len, Some(html)));
            }
            PrefixHit::Quote(text) => {
                let len = text.chars().count();
                let kids = vec![text_node(&text)];
                let html = inlines_to_editor_html(&kids);
                let n = &mut d[i];
                n.node_type = Some("quote".to_string());
                clear_type_fields(n);
                n.children = Some(kids);
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> quote {bid}"));
                return Some((bid.clone(), bid, len, Some(html)));
            }
            PrefixHit::Todo(text) => {
                let len = text.chars().count();
                let kids = vec![text_node(&text)];
                let html = inlines_to_editor_html(&kids);
                let n = &mut d[i];
                n.node_type = Some("todo".to_string());
                clear_type_fields(n);
                set_attr(n, "checked", json!(false));
                n.children = Some(kids);
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> todo {bid}"));
                return Some((bid.clone(), bid, len, Some(html)));
            }
        }
    }
    None
}

pub(super) fn apply_type(n: &mut Node, act: &str) {
    match act {
        "heading1" | "heading2" | "heading3" => {
            n.node_type = Some("heading".into());
            let lv: u64 = act[7..].parse().unwrap_or(2);
            clear_type_fields(n);
            set_attr(n, "level", json!(lv));
        }
        "todo" => {
            n.node_type = Some("todo".into());
            clear_type_fields(n);
            set_attr(n, "checked", json!(false));
        }
        "quote" => {
            n.node_type = Some("quote".into());
            clear_type_fields(n);
        }
        "imgTextCard" => {
            // 原版工厂（斜杠审计 S6）：正文被固定占位文替换（不
            // 保留用户原文），attrs 带 fileId:''
            n.node_type = Some("imgTextCard".into());
            clear_type_fields(n);
            n.children = Some(vec![text_node("点击输入文字")]);
            set_attr(n, "fileId", json!(""));
        }
        "imageTextRow" => {
            n.node_type = Some("imageTextRow".into());
            clear_type_fields(n);
            n.children = Some(vec![text_node("点击输入说明文字")]);
            set_attr(n, "fileId", json!(""));
        }
        "musicCard" => {
            // 原版工厂（斜杠审计 S5）：{url:'', meta:null,
            // status:'input'} 且无 children 键
            n.node_type = Some("musicCard".into());
            clear_type_fields(n);
            n.children = None;
            n.url = Some(String::new());
            n.meta = Some(serde_json::Value::Null);
            n.status = Some("input".to_string());
        }
        _ => {
            n.node_type = Some("paragraph".into());
            clear_type_fields(n);
        }
    }
}

/// 斜杠图片/画廊（斜杠审计 S4，原版 use-slash.js 工厂口径）：
/// 应用即落占位块（image: attrs.fileId=''；gallery:
/// attrs.items=[]）+ 尾随空段落并聚焦之。文件选择留到点占位
/// 块选中后的「选择图片」按钮，不再在应用瞬间弹选择器、
/// 取消即无事发生。
pub(super) fn op_insert_media_placeholder(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    gallery: bool,
    focus_req: &mut Signal<Option<(String, usize)>>,
) {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("media placeholder: block not found {bid}"));
        return;
    };
    let mut ph = new_block(if gallery { "gallery" } else { "image" });
    if gallery {
        set_attr(&mut ph, "items", json!([]));
    } else {
        set_attr(&mut ph, "fileId", json!(""));
    }
    let para = new_block("paragraph");
    let para_id = para.id.clone().unwrap_or_default();
    // 尾随空段（D-14，原版 use-slash needsTrailingParagraph
    // + next-empty 判定）：占位块之后已有现成空段就不多
    // 插，焦点改落该段；否则补一段并聚焦之。
    let mut focus_id = para_id.clone();
    match loc {
        Loc::Top(i) => {
            if next_is_empty_para(&d, i) {
                focus_id = d[i + 1].id.clone().unwrap_or_default();
                d[i] = ph;
            } else {
                d[i] = ph;
                d.insert(i + 1, para);
            }
        }
        Loc::Item(li, ii) => {
            // 列表项里应用：把该项提出列表（与 op_convert 同结构）
            let list = d[li].clone();
            let items = list.children.clone().unwrap_or_default();
            let head: Vec<Node> = items[..ii].to_vec();
            let tail: Vec<Node> = items[ii + 1..].to_vec();
            let mut replacement: Vec<Node> = Vec::new();
            if !head.is_empty() {
                let mut hl = list.clone();
                hl.children = Some(head);
                replacement.push(hl);
            }
            replacement.push(ph);
            // 占位块之后紧跟的是 tail 列表（非空段）或原
            // 列表的下一块：后者已是现成空段时不插新段。
            let next_empty = if tail.is_empty() {
                d.get(li + 1).filter(|n| is_empty_para(n))
            } else {
                None
            };
            if let Some(n) = next_empty {
                focus_id = n.id.clone().unwrap_or_default();
            } else {
                replacement.push(para);
            }
            if !tail.is_empty() {
                let mut tl = list.clone();
                tl.id = Some(gen_id());
                tl.children = Some(tail);
                // E-17 ①：尾表 start 按首项号传递（同 op_split
                // 退出列表口径：原 start + ii + 1）。
                set_list_start(&mut tl, list_start(&list) + (ii + 1) as u64);
                replacement.push(tl);
            }
            d.splice(li..=li, replacement);
        }
    }
    doc.set(d);
    focus_req.set(Some((focus_id, 0)));
    diag::log("EDIT", &format!("slash media placeholder gallery={gallery} {bid}"));
}

pub(super) fn op_convert(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    act: &str,
    html: &str,
    tok_pos: usize,
    focus_req: &mut Signal<Option<(String, usize)>>,
    md_edit: &mut Signal<Option<String>>,
) -> Option<(String, usize)> {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("convert: block not found {bid}"));
        return None;
    };
    let inlines = editor_html_to_inlines(html);

    // 列表项：列表类型互换只改父列表；其余转换把该项提出列表
    if let Loc::Item(li, ii) = loc {
        if act == "bulletList" || act == "numberList" {
            d[li].node_type = Some(
                if act == "bulletList" {
                    "bulleted-list"
                } else {
                    "numbered-list"
                }
                .to_string(),
            );
            // E-17 ①：类型互换生成的新列表 start 默认 1——
            // 清掉旧类型残留的 start 字段（转回 numbered 时
            // 不复活旧起始值）。
            remove_start_field(&mut d[li]);
            doc.set(d);
            // D-11：落点 = 令牌起点（原版 commandCaretOffset）
            focus_req.set(Some((bid.to_string(), tok_pos)));
            diag::log("EDIT", &format!("convert list type -> {act}"));
            return None;
        }
        let list = d[li].clone();
        let items = list.children.clone().unwrap_or_default();
        let mut converted = items[ii].clone();
        converted.children = Some(inlines);
        let head: Vec<Node> = items[..ii].to_vec();
        let tail: Vec<Node> = items[ii + 1..].to_vec();
        let mut replacement: Vec<Node> = Vec::new();
        if !head.is_empty() {
            let mut hl = list.clone();
            hl.children = Some(head);
            replacement.push(hl);
        }
        let mut focus = (bid.to_string(), 0usize);
        if act == "divider" {
            let mut div = new_block("divider");
            div.id = Some(bid.to_string());
            div.children = None;
            replacement.push(div);
            // 尾随空段（D-14）：divider 之后紧跟的是 tail
            // 列表（非空段）或原列表的下一块；后者已是现
            // 成空段就不多插、焦点落该段，否则补一段。
            let next_empty = if tail.is_empty() {
                d.get(li + 1).filter(|n| is_empty_para(n))
            } else {
                None
            };
            if let Some(n) = next_empty {
                focus = (n.id.clone().unwrap_or_default(), 0);
            } else {
                let para = new_block("paragraph");
                focus = (para.id.clone().unwrap_or_default(), 0);
                replacement.push(para);
            }
        } else {
            apply_type(&mut converted, act);
            // D-11：落点 = 令牌起点，不再恒落项末
            focus = (bid.to_string(), tok_pos);
            replacement.push(converted);
        }
        if !tail.is_empty() {
            let mut tl = list.clone();
            tl.id = Some(gen_id());
            tl.children = Some(tail);
            // E-17 ①：尾表 start 按首项号传递（原 start +
            // ii + 1，被提出项占一号）。
            set_list_start(&mut tl, list_start(&list) + (ii + 1) as u64);
            replacement.push(tl);
        }
        d.remove(li);
        for (k, b) in replacement.into_iter().enumerate() {
            d.insert(li + k, b);
        }
        doc.set(d);
        focus_req.set(Some(focus));
        diag::log("EDIT", &format!("convert lift {bid} -> {act}"));
        return None;
    }

    let Loc::Top(i) = loc else { return None };

    // 代码/列表/Callout：原版模型是 md 源段落（use-slash.js 实证），
    // 不造 codeBlock/bulleted-list/callout 类型。转后直接进源码
    // 编辑态（原版转换后光标落在源码段落里）。
    if matches!(act, "bulletList" | "numberList" | "codeBlock" | "callout") {
        let cur_text: String = inlines.iter().map(|n| n.plain_text()).collect();
        let plain = strip_md_prefixes(&cur_text);
        let plain = if plain.trim().is_empty() {
            match act {
                "bulletList" | "numberList" => "列表项".to_string(),
                "callout" => "提示内容".to_string(),
                _ => String::new(),
            }
        } else {
            plain
        };
        // (src, 前缀长)：D-11 落点 = 前缀长 + 令牌起点
        //（原版 markdownPrefixLength + commandCaretOffset：
        // 无序 2、有序 3、围栏 围栏长+1、Callout
        // "> [!NOTE]\n> " 全长 12）。
        let (src, prefix_len) = match act {
            "bulletList" => (
                plain
                    .lines()
                    .map(|l| format!("- {l}"))
                    .collect::<Vec<_>>()
                    .join("\n"),
                2,
            ),
            "numberList" => (
                plain
                    .lines()
                    .enumerate()
                    .map(|(k, l)| format!("{}. {l}", k + 1))
                    .collect::<Vec<_>>()
                    .join("\n"),
                3,
            ),
            "codeBlock" => {
                // D-13（原版 use-slash.js:514-516）：围栏随
                // 正文最长连续反引号串加长（下限 3），且正
                // 文保留原样、不剥 md 前缀（cleanedText 直
                // 入围栏）；其余 md 类臂维持先剥前缀口径。
                let body = if plain.is_empty() {
                    String::new()
                } else {
                    cur_text.clone()
                };
                let longest = body
                    .split(|c| c != '`')
                    .map(|s| s.chars().count())
                    .max()
                    .unwrap_or(0);
                let fence = "`".repeat((longest + 1).max(3));
                let plen = fence.chars().count() + 1;
                (format!("{fence}\n{body}\n{fence}"), plen)
            }
            _ => {
                let body = plain
                    .lines()
                    .map(|l| format!("> {l}"))
                    .collect::<Vec<_>>()
                    .join("\n");
                (format!("> [!NOTE]\n{body}"), 12)
            }
        };
        let n = node_at_mut(&mut d, loc);
        n.node_type = Some("paragraph".into());
        clear_type_fields(n);
        n.children = Some(vec![text_node(&src)]);
        // Callout 在原版尾随空段清单内（斜杠审计 S7）
        if act == "callout" && !next_is_empty_para(&d, i) {
            d.insert(i + 1, new_block("paragraph"));
        }
        doc.set(d);
        md_edit.set(Some(bid.to_string()));
        diag::log("EDIT", &format!("convert {bid} -> md source ({act})"));
        return Some((src, prefix_len + tok_pos));
    }

    if act == "divider" {
        let mut divider = new_block("divider");
        divider.id = Some(bid.to_string());
        divider.children = None;
        // 尾随空段（D-14）：下一块已是现成空段就不多插、
        // 焦点落该段；否则补一段并聚焦之。
        let focus_id = if next_is_empty_para(&d, i) {
            d[i] = divider;
            d[i + 1].id.clone().unwrap_or_default()
        } else {
            let para = new_block("paragraph");
            let para_id = para.id.clone().unwrap_or_default();
            d[i] = divider;
            d.insert(i + 1, para);
            para_id
        };
        doc.set(d);
        focus_req.set(Some((focus_id, 0)));
        diag::log("EDIT", &format!("convert {bid} -> divider"));
        return None;
    }

    let n = node_at_mut(&mut d, loc);
    n.children = Some(inlines);
    apply_type(n, act);
    // 尾随空段（斜杠审计 S7，原版 needsTrailingParagraph）：
    // todo/musicCard/imgTextCard/imageTextRow 转换后，下一块
    // 不是现成的空段落就补一个（divider/图片/画廊各自已带）
    if matches!(act, "todo" | "musicCard" | "imgTextCard" | "imageTextRow")
        && !next_is_empty_para(&d, i)
    {
        d.insert(i + 1, new_block("paragraph"));
    }
    // 图文卡/混排（D-12）：卡片块本身是原子块、不可落点，
    // 焦点落尾随空段起点（上一步已保证 i+1 为空段——原版
    // shouldFocusAfterBlock 口径）；其余仍落本块。
    let focus = if matches!(act, "imgTextCard" | "imageTextRow") {
        (d[i + 1].id.clone().unwrap_or_default(), 0)
    } else if act == "musicCard" {
        // 音乐卡输入胶囊（原版 use-slash 口径）：聚焦胶囊
        // 且光标落在占位文本末尾（usize::MAX 由 __mnFocus
        // 钳到文本长）
        (bid.to_string(), usize::MAX)
    } else {
        // D-11：落点 = 令牌起点（原版 commandCaretOffset
        // = tokenStart），不再恒落全文末尾
        (bid.to_string(), tok_pos)
    };
    doc.set(d);
    focus_req.set(Some(focus));
    diag::log("EDIT", &format!("convert {bid} -> {act}"));
    None
}

/// 媒体文件处理：上传全部选中文件到 IDB + manifest，再按请求
/// 分发——SetImage 给图文块换图；GalleryPick 给画廊格
/// 换图/追加。
pub(super) async fn handle_media_files(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    mut media_req: Signal<Option<MediaReq>>,
    persist: &PersistHandle,
) {
    let Some(req) = media_req.read().clone() else {
        return;
    };
    media_req.set(None);
    let Some(window) = web_sys::window() else {
        return;
    };
    let Some(document) = window.document() else {
        return;
    };
    let Some(input) = document
        .get_element_by_id("file-media")
        .and_then(|e| e.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        return;
    };
    let Some(files) = input.files() else {
        return;
    };
    let mut man: Value =
        serde_json::from_str(&manifest.read()).unwrap_or_else(|_| json!({"version": 1}));
    if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
        man["attachments"] = json!({});
    }
    let mut fids: Vec<String> = Vec::new();
    let mut rejected_non_image = false;
    for i in 0..files.length() {
        let Some(file) = files.get(i) else { continue };
        let name = file.name();
        let mime = file.type_();
        // 失败经错误徽章提示（原版 addWarn 口径，审计 E-3）：
        // 本路径三路（换图/画廊/斜杠媒体）产物均为图片块，
        // 非图片文件整批只提示一次（原版卡片路径以首个文件
        // 判定、画廊逐个过滤后无有效图时提示，合并为此口径）。
        if !mime.starts_with("image/") {
            rejected_non_image = true;
            continue;
        }
        let Ok(buf) = JsFuture::from(file.array_buffer()).await else {
            crate::errbadge::add_warn(&crate::i18n::t("attach.read_failed"), None);
            diag::log("EDIT", &format!("media read err: {name}"));
            continue;
        };
        let bytes = js_sys::Uint8Array::new(&buf).to_vec();
        let fid = gen_id();
        if let Err(e) = persist::put_attachment(&fid, &bytes).await {
            crate::errbadge::add_warn(
                &crate::i18n::t("attach.card_save_failed"),
                Some(&format!("{e:?}")),
            );
            diag::log("EDIT", &format!("media put err: {e:?}"));
            continue;
        }
        man["attachments"][&fid] = json!({"name": name, "type": mime});
        fids.push(fid);
    }
    if rejected_non_image {
        crate::errbadge::add_warn(&crate::i18n::t("attach.image_only"), None);
    }
    if fids.is_empty() {
        return;
    }
    let man_str = man.to_string();
    manifest.set(man_str.clone());
    let _ = persist::save_manifest(&man_str).await;

    let mut d = doc.read().clone();
    match req {
        MediaReq::SetImage { bid } => {
            if let Some(loc) = find_loc(&d, &bid) {
                // 与旧写口同义：attrs 整替为只含 fileId。
                node_at_mut(&mut d, loc).attrs = moment_core::Attrs {
                    file_id: Some(fids[0].clone()),
                    ..Default::default()
                };
                diag::log("EDIT", &format!("imgtext set image {bid}"));
            }
        }
        MediaReq::GalleryPick { bid, index } => {
            if let Some(loc) = find_loc(&d, &bid) {
                let n = node_at_mut(&mut d, loc);
                // 写路径只产归一形态（去兼容第四步）：先把节点
                // 归一为 attrs.items 对象形（旧 children 形在此
                // 一次性物化），再施加本次 pick——替换与追加都
                // 只写 {fileId} 条目，不再产 children 形。
                ensure_gallery_items_form(n);
                if let Some(items) = n.attrs.items.as_mut() {
                    match index {
                        Some(i) => {
                            if let Some(slot) = items.get_mut(i) {
                                *slot = moment_core::GalleryEntry {
                                    file_id: Some(fids[0].clone()),
                                    url: None,
                                };
                            }
                        }
                        None => {
                            for f in &fids {
                                items.push(moment_core::GalleryEntry {
                                    file_id: Some(f.clone()),
                                    url: None,
                                });
                            }
                        }
                    }
                }
                diag::log("EDIT", &format!("gallery pick {bid} index={index:?}"));
            }
        }
    }
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
}

/// 待发输入保险丝的 localStorage 键（与桥侧
/// stashPendingInput 同名同格式：{bid: innerHTML}）。
const PENDING_INPUT_KEY: &str = "mynote_pending_input_v1";

/// 待发输入尾巴恢复（批 4 链尾产品红根治）：打字后
/// <80ms 内整页卸载 / 桥拆除 / 切后台时，80ms 防抖
/// inputSync 未及发火、消息通道与异步落盘又赶不上卸
/// 载，桥侧把脏块当前 innerHTML 同步存入 localStorage
/// 保险丝。本函数把属于 doc 的条目经 apply_sync_map
/// 落回模型并摘除已消费条目，未命中的（他篇尾巴）原
/// 样写回等其本篇恢复；返回实际应用的条数。调用点：
/// 启动逐篇（main.rs，赶在列表/深链打开前回写落盘）
/// 与打开备忘的 doc 初始化（应用内卸载场景兜底）。
pub(crate) fn recover_pending_input(doc: &mut Vec<Node>) -> usize {
    let Some(st) = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
    else {
        return 0;
    };
    let Some(raw) = st.get_item(PENDING_INPUT_KEY).ok().flatten() else {
        return 0;
    };
    let Ok(map) = serde_json::from_str::<Map<String, Value>>(&raw) else {
        // 格式损坏：整键作废，避免每次打开重复踩坏数据
        let _ = st.remove_item(PENDING_INPUT_KEY);
        return 0;
    };
    if map.is_empty() {
        return 0;
    }
    // 本篇块 id 全集（与 apply_sync_map 同遍历面：顶层
    // 块 + 列表子项递归）
    fn collect_ids(nodes: &[Node], out: &mut std::collections::HashSet<String>) {
        for n in nodes {
            if let Some(id) = &n.id {
                out.insert(id.clone());
            }
            if let Some(kids) = &n.children {
                collect_ids(kids, out);
            }
        }
    }
    let mut ids = std::collections::HashSet::new();
    collect_ids(doc, &mut ids);
    let (mine, rest): (Map<String, Value>, Map<String, Value>) =
        map.into_iter().partition(|(k, _)| ids.contains(k));
    if mine.is_empty() {
        return 0;
    }
    let n = mine.len();
    apply_sync_map(doc, &Value::Object(mine).to_string());
    if rest.is_empty() {
        let _ = st.remove_item(PENDING_INPUT_KEY);
    } else {
        let _ = st.set_item(PENDING_INPUT_KEY, &Value::Object(rest).to_string());
    }
    n
}

/// 添加附件：读 #file-attach 选中的文件 → 写 IDB 附件库 →
/// 更新 manifest → 文档末尾插入图片/附件块并落库。
pub(super) async fn attach_file(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    persist: &PersistHandle,
) {
    let Some(window) = web_sys::window() else {
        return;
    };
    let Some(document) = window.document() else {
        return;
    };
    let Some(input) = document
        .get_element_by_id("file-attach")
        .and_then(|e| e.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        return;
    };
    let Some(files) = input.files() else {
        return;
    };
    for fi in 0..files.length() {
        let Some(file) = files.get(fi) else {
            continue;
        };
        attach_one(&file, doc, title, data, manifest, persist).await;
    }
}

/// 单个附件文件：写 IDB → 更新 manifest → 末尾插块并落库。
async fn attach_one(
    file: &web_sys::File,
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    persist: &PersistHandle,
) {
    let name = file.name();
    let mime = file.type_();
    // 失败经错误徽章提示（原版 addWarn 口径，审计 E-3）：
    // 读/写任一失败都不插块（原版为插入后回滚移除，用户
    // 可见终态一致——无块 + 一条 warn）。
    let Ok(buf) = JsFuture::from(file.array_buffer()).await else {
        crate::errbadge::add_warn(&crate::i18n::t("attach.save_failed"), None);
        diag::log("EDIT", &format!("attach read err: {name}"));
        return;
    };
    let bytes = js_sys::Uint8Array::new(&buf).to_vec();
    let fid = gen_id();
    if let Err(e) = persist::put_attachment(&fid, &bytes).await {
        crate::errbadge::add_warn(
            &crate::i18n::t("attach.save_failed"),
            Some(&format!("{e:?}")),
        );
        diag::log("EDIT", &format!("attach put err: {e:?}"));
        return;
    }
    // manifest.attachments[fid] = {name, type}
    let mut man: Value =
        serde_json::from_str(&manifest.read()).unwrap_or_else(|_| json!({"version": 1}));
    if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
        man["attachments"] = json!({});
    }
    man["attachments"][&fid] = json!({"name": name, "type": mime});
    let man_str = man.to_string();
    manifest.set(man_str.clone());
    let _ = persist::save_manifest(&man_str).await;

    let is_image = mime.starts_with("image/");
    let node = if is_image {
        Node {
            node_type: Some("image".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            attrs: moment_core::Attrs {
                file_id: Some(fid.clone()),
                ..Default::default()
            },
            ..Default::default()
        }
    } else {
        // fileId 只写 attrs（与图片工厂同位、规范位）。
        // 文件名冗余写节点顶层 name（导出渲染的兜底读法同
        // 字段；编辑器渲染优先查 manifest）。
        Node {
            node_type: Some("attachment".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            attrs: moment_core::Attrs {
                file_id: Some(fid.clone()),
                ..Default::default()
            },
            name: Some(name.clone()),
            status: Some("done".to_string()),
            image: Some(false),
            ..Default::default()
        }
    };
    let mut d = doc.read().clone();
    d.push(node);
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
    // 成功无提示（原版口径，E-3 备注）
    diag::log("EDIT", &format!("attach {fid} {name} {mime} {}B", bytes.len()));
}
