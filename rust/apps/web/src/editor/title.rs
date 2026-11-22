//! 标题胶囊：显示口径、标题元素同步访问与 TitleText 组件。
//! 聚焦/失焦的关键操作必须在事件任务内同步完成（见
//! title_element 的说明），不得挂 spawn+eval 异步往返。

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

/// 标题元素（同步 DOM 访问）：聚焦/失焦的关键操作必须在事件
/// 任务内同步完成。旧实现把展开全文挂在 spawn+eval 的异步往返
/// 上——iOS 在键盘/输入会话建立之后才等到文本节点被替换，首击
/// 出现「键盘已弹但打不出字」；提交同理挂在 spawn 上，编辑器
/// 先卸载还会把标题改动吞掉。原版 onFocus/onBlur 均为同步。
fn title_element() -> Option<web_sys::Element> {
    web_sys::window()?.document()?.get_element_by_id("editor-title-text")
}

fn title_text_content() -> String {
    title_element()
        .and_then(|el| {
            let node: &web_sys::Node = el.unchecked_ref();
            node.text_content()
        })
        .unwrap_or_default()
}

/// 标题输入（原版是 contenteditable div，不是 <input>：input 的
/// 固有宽度会把胶囊撑大、且不能换行）。非受控：初始文本只在
/// 挂载时写一次；文本同步走桥的 titleText 消息（组合期间不
/// 提交）；聚焦时同步展开全文（仅截断显示与全文不一致时才换
/// 文本，未截断不碰选区），光标到末尾走 rAF 延后（同步设选区
/// 会被 WebKit 的落点计算冲掉，见 onfocus 内注）；失焦时同步
/// 提交并就地回截断显示——都不重挂载，避免键盘/光标被打断。
///
/// 二次定罪后的两条结构口径（真机两症状：首击键盘弹出但打不
/// 出字、第二会话光标落文首；Chromium 仪表化下与原版逐状态
/// 一致、不可复现，属 WebKit 聚焦事务对事务内/事务后 DOM 扰
/// 动的敏感面，只能按与原版的执行形态偏差逐项消除）：
/// 一、字号类驱动（editor.css 的 .is-long/.is-overflow = 11px、
/// 基础 14px），本元素不带 style 属性——旧实现 Dioxus 的
/// style="font-size:…" 属性与失焦清理 eval 的 el.style 写入
/// 是同一属性的两个写者，且组合期 syncTitleLayout 的内联样
/// 式与该属性同体，VDOM 一旦重敷属性即整表覆盖。二、失焦清
/// 理全同步（见 onblur 内注），标题生命周期内不留任何异步
/// DOM 尾巴（原版 onBlur 全同步，React 的样式差分天然覆盖
/// 组合期直写值，无此问题）。
#[component]
pub(super) fn TitleText(
    display: String,
    cls: String,
    title: Signal<String>,
    mut editing: Signal<bool>,
    mut composing: Signal<bool>,
    mut long_latch: Signal<bool>,
    mut ovf_latch: Signal<bool>,
) -> Element {
    let initial = use_hook(|| {
        display
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
    });
    rsx! {
        div {
            id: "editor-title-text",
            class: "{cls}",
            contenteditable: "true",
            role: "textbox",
            "aria-label": "{crate::i18n::t(\"editor.untitled\")}",
            "enterkeyhint": "done",
            dangerous_inner_html: "{initial}",
            onfocus: move |_| {
                // 状态先行（原版 onFocus 同序：isEditingTitleRef /
                // setEditingTitle / 布局快照都在换文本之前）：先置
                // 编辑态与布局锁存，再动 DOM。旧序先换文本、后置
                // 状态——状态引发的重渲染类补丁（.editing 等）随
                // 之落在选区落定之后，构成聚焦事务后的布局扰动
                // 源（二次定罪，见 TitleText 上方长注）。布局锁存
                // 按初始长度置位（会话内只升不降，见 Editor 侧）。
                let full = title.read().clone();
                let n = full.chars().count();
                long_latch.set(n > 5);
                ovf_latch.set(n > 11);
                editing.set(true);
                if let Some(el) = title_element() {
                    if let Some(sc) = el.parent_element() {
                        sc.set_scroll_left(0);
                    }
                    // 同步展开：截断态才换文本并把光标移到末尾；
                    // 未截断不碰选区（原生落点）。
                    let node: &web_sys::Node = el.unchecked_ref();
                    if node.text_content().unwrap_or_default() != full {
                        node.set_text_content(Some(&full));
                        // 光标到末尾走 rAF（原版 onFocus 同口径）：
                        // 在 focus 事件内同步 remove_all_ranges /
                        // add_range 会与 WebKit 自身的落点计算相
                        // 撞——WebKit 仪表化实测：空标题（新备忘）
                        // 时同步设选区后 rangeCount 归零（无光标，
                        // 键盘输入无处落，即真机首击打不出字）；
                        // 截断标题时同步选区被原生落点覆盖回 tap
                        // 点（光标不在末尾）。延后一帧、等浏览器
                        // 落点尘埃落定后再设，才稳定落在末尾。
                        let cb = wasm_bindgen::closure::Closure::once_into_js(move || {
                            if let Some(el) = title_element() {
                                let node: &web_sys::Node = el.unchecked_ref();
                                if !node.is_connected() {
                                    return;
                                }
                                if let Some(doc) =
                                    web_sys::window().and_then(|w| w.document())
                                {
                                    if let Ok(range) = doc.create_range() {
                                        let _ = range.select_node_contents(node);
                                        let _ = range.collapse_with_to_start(false);
                                        if let Some(sel) = web_sys::window()
                                            .and_then(|w| w.get_selection().ok().flatten())
                                        {
                                            let _ = sel.remove_all_ranges();
                                            let _ = sel.add_range(&range);
                                        }
                                    }
                                }
                            }
                        });
                        if let Some(w) = web_sys::window() {
                            let _ = w.request_animation_frame(cb.unchecked_ref());
                        }
                    }
                }
            },
            onblur: move |_| {
                editing.set(false);
                long_latch.set(false);
                ovf_latch.set(false);
                // 同步提交（原版 commitTitleFromDOM）：全文 trim，
                // 空则存「无标题」；随后就地回截断显示。
                let raw = title_text_content();
                let trimmed = raw.trim().to_string();
                let committed = if trimmed.is_empty() {
                    crate::i18n::t("editor.untitled")
                } else {
                    trimmed
                };
                let mut title = title;
                if title.read().as_str() != committed.as_str() {
                    title.set(committed.clone());
                }
                let disp = display_title_of(&committed);
                if let Some(el) = title_element() {
                    let node: &web_sys::Node = el.unchecked_ref();
                    if node.text_content().unwrap_or_default() != disp {
                        node.set_text_content(Some(&disp));
                    }
                    if let Some(sc) = el.parent_element() {
                        sc.set_scroll_left(0);
                    }
                    // 组合期 syncTitleLayout 在胶囊/滚动区/标题元
                    // 素上直写的内联样式，在本失焦任务内同步摘除
                    // 回类驱动（原版 onBlur 全同步、无异步尾巴）。
                    // 旧实现走 spawn+eval 异步清理：其执行时机不
                    // 受本事件控制——执行器繁忙时可拖进下一次聚
                    // 焦事务，在聚焦元素与其祖先上改样式（宽/内
                    // 边距/字号/white-space），是二次定罪认定的
                    // 第二会话光标扰动源之一，故废弃。这三个元素
                    // 不带框架托管的 style 属性（字号已改类驱
                    // 动），其 style 属性整体即组合期直写集，整
                    // 摘除无副作用；旧版「清掉字号后 VDOM 不重敷
                    // 致漂移 16px」的问题随类驱动一并消失。
                    let _ = el.remove_attribute("style");
                    if let Some(sc) = el.parent_element() {
                        let _ = sc.remove_attribute("style");
                        if let Some(cap) = sc.parent_element() {
                            let _ = cap.remove_attribute("style");
                        }
                    }
                }
            },
            oncompositionstart: move |_| composing.set(true),
            oncompositionend: move |_| composing.set(false),
            onkeydown: move |evt: KeyboardEvent| {
                if evt.key() == Key::Enter && !*composing.read() {
                    evt.prevent_default();
                    if let Some(el) = title_element() {
                        let html: &web_sys::HtmlElement = el.unchecked_ref();
                        html.blur();
                    }
                }
            },
        }
    }
}
