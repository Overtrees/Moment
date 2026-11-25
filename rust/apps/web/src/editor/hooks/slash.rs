//! 斜杠执行组 hooks（批 14 三轮自 editor.rs 拆出）：
//! 斜杠面板点击的命令分流执行与链接表单提交。段内代码
//! 逐字搬移，只做文件组织，行为不变。

use super::super::*;

/// 行内斜杠命令：不改块类型，由 JS 桥对选区就地执行。
pub(in crate::editor) const INLINE_ACTS: &[&str] = &["bold", "italic", "highlight", "code", "strikethrough"];

pub(in crate::editor) fn use_slash_click(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut slash_click: Signal<Option<(String, String)>>,
    focus_req: Signal<Option<(String, usize)>>,
    md_edit: Signal<Option<String>>,
    dom_set: Signal<Option<(String, String, usize)>>,
    persist: PersistHandle,
) {
// 斜杠面板的点击在 Editor 作用域里执行（SlashPanel 点击后
// 立即卸载，它自己 spawn 的异步会被一并取消——踩过）。
// 按命令类别分流：行内命令走 __mnInline 就地执行；图片/画廊
// 走文件选择替换当前块；其余走 strip + op_convert。
{
    let persist = persist.clone();
    use_effect(move || {
        let click = slash_click.read().clone();
        if let Some((bid, act)) = click {
            slash_click.set(None);
            slash_record_recent(&act);
            let persist = persist.clone();
            if INLINE_ACTS.contains(&act.as_str()) {
                spawn(async move {
                    let js = format!(
                        "dioxus.send(window.__mnInline ? window.__mnInline({}, {}) : '');",
                        serde_json::to_string(&act).unwrap_or_default(),
                        serde_json::to_string(&bid).unwrap_or_default()
                    );
                    let mut eval = document::eval(&js);
                    let html = eval.recv::<String>().await.unwrap_or_default();
                    let mut d = doc.read().clone();
                    if let Some(loc) = find_loc(&d, &bid) {
                        node_at_mut(&mut d, loc).children =
                            Some(editor_html_to_inlines(&html));
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        diag::log("EDIT", &format!("slash inline {act} {bid}"));
                    }
                });
            } else if act == "image" || act == "gallery" {
                // 占位块路径（S4）：落占位块 + 尾随空段，不在
                // 应用瞬间弹文件选择器
                let mut doc2 = doc;
                let mut focus_req2 = focus_req;
                op_insert_media_placeholder(&mut doc2, &bid, act == "gallery", &mut focus_req2);
                persist.call(doc2.read().clone(), title.read().clone(), data);
            } else {
                spawn(async move {
                    let js = format!(
                        "dioxus.send(window.__mnStripSlash ? window.__mnStripSlash({}) : '');",
                        serde_json::to_string(&bid).unwrap_or_default()
                    );
                    let mut eval = document::eval(&js);
                    let raw = eval.recv::<String>().await.unwrap_or_default();
                    // __mnStripSlash 返回 {html, pos} JSON
                    //（D-11）；解析失败时整串作 html、pos=0
                    let (html, pos) = serde_json::from_str::<Value>(&raw)
                        .ok()
                        .and_then(|v| {
                            v.get("html")
                                .and_then(|h| h.as_str())
                                .map(|h| (h.to_string(), v.get("pos").and_then(|p| p.as_u64()).unwrap_or(0) as usize))
                        })
                        .unwrap_or((raw, 0));
                    let mut doc = doc;
                    let mut focus_req = focus_req;
                    let mut md_edit = md_edit;
                    let mut dom_set = dom_set;
                    if let Some((src, off)) = op_convert(&mut doc, &bid, &act, &html, pos, &mut focus_req, &mut md_edit) {
                        // md 源转换：DOM 回写为源码（<br> 换行）并聚焦
                        let esc = src
                            .replace('&', "&amp;")
                            .replace('<', "&lt;")
                            .replace('>', "&gt;")
                            .replace('\n', "<br>");
                        dom_set.set(Some((bid.clone(), esc, off)));
                    }
                    persist.call(doc.read().clone(), title.read().clone(), data);
                });
            }
        }
    });
}
}

pub(in crate::editor) fn use_link_submit(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut link_click: Signal<Option<(String, String)>>,
    mut link_for: Signal<Option<String>>,
    persist: PersistHandle,
) {
// 链接表单提交：__mnStripSlash 后 __mnApplyLink（桥内恢复
// 打开表单前保存的选区），返回的 HTML 对齐模型
{
    let persist = persist.clone();
    use_effect(move || {
        let click = link_click.read().clone();
        if let Some((bid, url)) = click {
            link_click.set(None);
            link_for.set(None);
            slash_record_recent("link");
            let persist = persist.clone();
            spawn(async move {
                let js = format!(
                    "if (window.__mnStripSlash) window.__mnStripSlash({0}); dioxus.send(window.__mnApplyLink ? window.__mnApplyLink({1}, {0}) : '');",
                    serde_json::to_string(&bid).unwrap_or_default(),
                    serde_json::to_string(&url).unwrap_or_default()
                );
                let mut eval = document::eval(&js);
                let html = eval.recv::<String>().await.unwrap_or_default();
                let mut d = doc.read().clone();
                if let Some(loc) = find_loc(&d, &bid) {
                    node_at_mut(&mut d, loc).children =
                        Some(editor_html_to_inlines(&html));
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                    diag::log("EDIT", &format!("slash link {bid}"));
                }
            });
        }
    });
}
}
