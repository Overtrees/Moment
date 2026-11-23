//! 标题胶囊：显示口径、静态壳与返回前的标题失焦接线。
//!
//! 标题编辑会话（文本、胶囊宽、光标、提交）全归
//! title_controller::TitleController 所有。本文件的
//! TitleCapsule 只是挂载壳：props 只有备忘 id、初始标题、
//! meta 文案与两个会话回调（提交/会话开关）；挂载后标题
//! 子树退出 VDOM 托管——无动态 class、无 Dioxus 合成事
//! 件，标题元素是原生 <input type="text">（用户口径重
//! 构，见 title_controller 模块注）。input 的 value 绝
//! 不进 vnode：壳因 meta 文案变化重执行时，框架解释器
//! 会把 vnode 的 value 按挂载快照重写进元素（setAttribute
//! 路径实测踩到：编辑提交后点正文，显示被打回旧标题），
//! 故初始显示值由 Controller 在 attach 时写入、其后全
//! 归控制器就地读写，vnode 只管结构与静态属性。壳以
//! memo_id 为 key（调用点），换篇即整壳重挂、控制器随
//! 之新建。

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

/// 标题坞静态壳：胶囊/输入/meta 的一次性渲染 +
/// Controller 的挂载/卸载接线。input 不带 value 属性渲
/// 染（见模块注），初始显示值由 Controller attach 时按
/// 显示口径写入。
#[component]
pub(super) fn TitleCapsule(
    memo_id: String,
    initial_title: String,
    meta_line: String,
    on_commit: EventHandler<String>,
    on_session: EventHandler<bool>,
) -> Element {
    let _ = &memo_id; // key 在调用点消费，本字段仅作 props 完整性
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
            input {
                id: "editor-title-text",
                class: "editor-title-input",
                r#type: "text",
                "aria-label": "{crate::i18n::t(\"editor.untitled\")}",
                "enterkeyhint": "done",
                autocomplete: "off",
                spellcheck: "false",
            }
            div { class: "editor-title-meta", "{meta_line}" }
        }
    }
}
