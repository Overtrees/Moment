//! 标题胶囊：显示口径、静态壳与返回前的标题失焦接线。
//!
//! 标题编辑会话（DOM 文本、几何、光标、提交）全归
//! title_controller::TitleController 所有。本文件的
//! TitleCapsule 只是挂载壳：props 只有备忘 id、初始标题、
//! meta 文案与两个会话回调（提交/会话开关）；挂载后标题
//! 子树退出 VDOM 托管——无动态 class、无 style 属性、无
//! Dioxus 合成事件，初始文本以普通文本子节点渲染（不用
//! dangerous_inner_html）。Editor 重渲染时本壳 props 逐值
//! 相同、整段跳过；偶有重执行，vnode 也逐值相同，不产生
//! 任何标题面 DOM 写入。壳以 memo_id 为 key（调用点），
//! 换篇即整壳重挂、控制器随之新建。

use super::title_controller::TitleController;
use super::*;

/// 标题显示口径（原版 editor.js）：空标题显示「无标题」，
/// 超 10 字截断加省略号（仅非编辑态显示用）。
pub(super) fn display_title_of(raw: &str) -> String {
    if raw.is_empty() {
        crate::i18n::t("editor.untitled")
    } else if raw.chars().count() > 10 {
        format!("{}…", raw.chars().take(10).collect::<String>())
    } else {
        raw.to_string()
    }
}

/// 返回/菜单动作前同步失焦标题：Controller 只在 blur /
/// Enter 等时机写标题信号，而 iOS 上点按钮不转移焦点、标
/// 题会话不会自行失焦——返回流程若直接读标题信号会读到
/// 未提交的旧值（新备忘误判为空、落盘标题过期）。在此同
/// 步 blur() 触发 Controller 的失焦提交（同任务内完成），
/// 再走关闭/菜单流程。标题未聚焦时无操作。
pub(super) fn blur_title_if_focused() {
    let Some(doc) = web_sys::window().and_then(|w| w.document()) else {
        return;
    };
    let Some(el) = doc.get_element_by_id("editor-title-text") else {
        return;
    };
    if let Some(active) = doc.active_element() {
        if active == el {
            let html: &web_sys::HtmlElement = el.unchecked_ref();
            html.blur();
        }
    }
}

/// 标题坞静态壳：胶囊/滚动区/输入/meta 的一次性渲染 +
/// Controller 的挂载/卸载接线。显示文本取挂载时快照（初
/// 始标题的显示口径），其后文本由 Controller 在会话收尾
/// 时就地回写，壳永不以新文本重渲染输入元素。
#[component]
pub(super) fn TitleCapsule(
    memo_id: String,
    initial_title: String,
    meta_line: String,
    on_commit: EventHandler<String>,
    on_session: EventHandler<bool>,
) -> Element {
    let _ = &memo_id; // key 在调用点消费，本字段仅作 props 完整性
    let display = use_hook(|| display_title_of(&initial_title));
    let holder = use_hook(|| std::rc::Rc::new(std::cell::RefCell::new(None::<TitleController>)));
    {
        let holder = holder.clone();
        let committed0 = initial_title.clone();
        use_effect(move || {
            let c = TitleController::attach(committed0.clone(), on_commit, on_session);
            *holder.borrow_mut() = c;
        });
    }
    use_drop({
        let holder = holder.clone();
        move || {
            if let Some(c) = holder.borrow_mut().take() {
                c.detach();
            }
        }
    });
    rsx! {
        div { class: "editor-title-capsule",
            div { class: "editor-title-scroller",
                div {
                    id: "editor-title-text",
                    class: "editor-title-input",
                    contenteditable: "true",
                    role: "textbox",
                    "aria-label": "{crate::i18n::t(\"editor.untitled\")}",
                    "enterkeyhint": "done",
                    "{display}"
                }
            }
            div { class: "editor-title-meta", "{meta_line}" }
        }
    }
}
