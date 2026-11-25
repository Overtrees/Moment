//! 焦点组 hooks（批 14 三轮自 editor.rs 拆出）：typed
//! 追踪、面板/焦点请求信号组与新建自动聚焦、尾随空段会
//! 话内物化、结构操作后的光标/DOM 回写请求消费。段内代
//! 码逐字搬移，只做文件组织，行为不变。

use super::super::*;

/// 面板/焦点信号组（use_panel_fx 返回）：斜杠面板、焦点
/// 请求、卡片落点、链接表单与媒体请求信号。
pub(in crate::editor) struct PanelFx {
    pub(in crate::editor) panel: Signal<Option<(String, String, f64, f64, f64)>>,
    pub(in crate::editor) focus_req: Signal<Option<(String, usize)>>,
    pub(in crate::editor) card_caret: Signal<Option<String>>,
    pub(in crate::editor) slash_click: Signal<Option<(String, String)>>,
    pub(in crate::editor) link_for: Signal<Option<String>>,
    pub(in crate::editor) link_click: Signal<Option<(String, String)>>,
    pub(in crate::editor) link_pos: Signal<(f64, f64, f64)>,
    pub(in crate::editor) media_req: Signal<Option<MediaReq>>,
}

pub(in crate::editor) fn use_typed(
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    initial_doc_json: String,
    initial_title: String,
) -> Signal<bool> {
let mut typed = use_signal(|| false);
{
    let initial_doc_json = initial_doc_json.clone();
    let initial_title = initial_title.clone();
    use_effect(move || {
        let dj = serde_json::to_string(&doc.read().clone()).unwrap_or_default();
        if dj != initial_doc_json || *title.read() != initial_title {
            typed.set(true);
        }
    });
}
    typed
}

pub(in crate::editor) fn use_panel_fx(doc: Signal<Vec<Node>>, is_new: bool) -> PanelFx {
let panel = use_signal(|| Option::<(String, String, f64, f64, f64)>::None);
let focus_req = use_signal(|| Option::<(String, usize)>::None);
// 新建备忘自动聚焦首段（原版三层同向：memo-list.js
// handleNew 在创建手势内同步尝试 focusEditableWithCaret
// (firstParagraph, 0) 并 rAF 重试；editor.js autoFocus
// 200ms effect；以及与 autoFocus 无关的 300ms effect——
// 文档恰为单个空段落的旧备忘打开时同样聚焦首段）。判
// 定在挂载时用 use_hook 锁定（is_new 或初始文档为单个
// 空段落），聚焦走既有 focus_req 通道、光标在段首。
// 只动焦点不动文档：typed 口径与关空备忘删除不受影响。
let auto_focus_first = use_hook(|| -> Option<String> {
    let d = doc.read();
    let single_empty = d.len() == 1
        && d[0].block_type() == Some("paragraph")
        && d[0].plain_text().is_empty();
    if is_new || single_empty {
        d.iter()
            .find(|n| n.block_type() == Some("paragraph"))
            .and_then(|n| n.id.clone())
    } else {
        None
    }
});
{
    let target = auto_focus_first.clone();
    use_effect(move || {
        if let Some(fid) = target.clone() {
            // 桥（EDITOR_JS）由挂载 effect 异步安装，
            // __mnFocus 未就绪时直接调用会被空转；原版
            // 同策略（同步尝试 + rAF 重试 + 延时 effect
            // 兜底）：eval 内轮询就绪后直接聚焦并回传
            // 结果（上限 2s），不走 focus_req 以免被其
            // 消费时序吞掉。
            spawn(async move {
                // PERF（调优续推）：原版策略本就是「同步尝试 +
                // rAF 重试」；此前实现只有 50ms 间隔轮询、且
                // 首次检查也要等一个间隔，聚焦平均白等 ~25ms。
                // 改为立即尝试一次、未就绪再以 10ms 间隔轮询
                // （上限仍 2s、落点仍段首 0），语义不变、只缩
                // 短察觉就绪的延迟。
                let js = format!(
                    "new Promise((res) => {{ let n = 0; const tryF = () => {{ if (window.__mnFocus) {{ window.__mnFocus({}, 0); res(1); return true; }} return false; }}; if (!tryF()) {{ const t = setInterval(() => {{ if (tryF()) {{ clearInterval(t); }} else if (++n > 200) {{ clearInterval(t); res(0); }} }}, 10); }} }}).then((v) => dioxus.send(v));",
                    serde_json::to_string(&fid).unwrap_or_default()
                );
                let mut eval = document::eval(&js);
                match eval.recv::<Value>().await {
                    Ok(v) if v.as_i64() == Some(1) => {
                        diag::log("EDIT", &format!("auto focus first paragraph {fid}"));
                    }
                    _ => {
                        diag::log("EDIT", "auto focus skipped: bridge not ready");
                    }
                }
            });
        }
    });
}
// 音乐输入解析的待落点卡片 id：解析完成时把光标放到该
// 卡片下方一行开头（原版 focusCaretBelowResolvedCard）
let card_caret = use_signal(|| Option::<String>::None);
let slash_click = use_signal(|| Option::<(String, String)>::None);
// 斜杠链接表单：Some(块 id) 时面板切为链接表单；提交后由
// link_click 触发 __mnApplyLink（选区由桥的 savedRange 恢复）
let link_for = use_signal(|| Option::<String>::None);
let link_click = use_signal(|| Option::<(String, String)>::None);
// 链接表单的位置：Enter 路径下面板已关，坐标从最后一次
// slash 消息的位置继承
let link_pos = use_signal(|| (20f64, 160f64, 200f64));
// 媒体选择请求（斜杠图片/画廊、图文块换图）
let media_req = use_signal(|| Option::<MediaReq>::None);
    PanelFx { panel, focus_req, card_caret, slash_click, link_for, link_click, link_pos, media_req }
}

pub(in crate::editor) fn use_trail_materialize(
    mut doc: Signal<Vec<Node>>,
    active_edit: Signal<Option<String>>,
    md_edit: Signal<Option<String>>,
) {
// 尾随空段模型化（会话内续补）：失焦转预览、删块、转换
// 等让新的尾随位置出现时，把真实空段落补进模型（原版
// ensureTrailing 在预览转换时点补段、首次同步即入
// docRef 的等价）。订阅 doc 与编辑态：插入后同一位置不
// 再命中，effect 再跑必为 0 处、自稳；源码编辑中的块其
// 后不补（其失焦消息清掉 active_edit 后本 effect 续跑
// 再补，与原版转换时点对齐）。补段不走 persist（各 op
// 自行落盘、返回时全量落盘兜底），不压撤销栈（快照在桥
// 循环按 handle 前后 JSON 判定，与本 effect 互不干扰）。
use_effect(move || {
    let editing = active_edit
        .read()
        .clone()
        .or_else(|| md_edit.read().clone());
    let mut d = doc.read().clone();
    let n = materialize_trails(&mut d, editing.as_deref());
    if n > 0 {
        doc.set(d);
        diag::log("EDIT", &format!("trail materialized x{n}"));
    }
});
}

pub(in crate::editor) fn use_focus_requests(
    mut focus_req: Signal<Option<(String, usize)>>,
    mut dom_set: Signal<Option<(String, String, usize)>>,
) {
// 结构操作后的光标恢复
use_effect(move || {
    let req = focus_req.read().clone();
    if let Some((bid, off)) = req {
        focus_req.set(None);
        spawn(async move {
            let js = format!(
                "if (window.__mnFocus) window.__mnFocus({}, {}); dioxus.send(null);",
                serde_json::to_string(&bid).unwrap_or_default(),
                off
            );
            let mut eval = document::eval(&js);
            let _ = eval.recv::<Value>().await;
        });
    }
});

// 多行粘贴后，当前块的 DOM 由桥按模型回写（非受控块不会
// 自己重渲染）并把光标放到首行末尾
use_effect(move || {
    let req = dom_set.read().clone();
    if let Some((bid, html, off)) = req {
        dom_set.set(None);
        spawn(async move {
            let js = format!(
                "if (window.__mnSetHtml) window.__mnSetHtml({}, {}, {}); dioxus.send(null);",
                serde_json::to_string(&bid).unwrap_or_default(),
                serde_json::to_string(&html).unwrap_or_default(),
                off
            );
            let mut eval = document::eval(&js);
            let _ = eval.recv::<Value>().await;
        });
    }
});
}
