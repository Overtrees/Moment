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

/// 子树内文本的 UTF-16 总长。
fn subtree_units(n: &web_sys::Node) -> u32 {
    n.text_content()
        .map(|s| s.chars().map(|c| c.len_utf16() as u32).sum())
        .unwrap_or(0)
}

/// 选区端点 (target, offset) 之前、cur 子树内的文本 UTF-16 长
/// （与桥 rangeOffsets 同口径的 DOM 遍历版）；端点不在此子树
/// 返回 None。端点为文本节点时 offset 是字符内 UTF-16 位移，
/// 为元素时是子节点序号。
fn units_before_in(cur: &web_sys::Node, target: &web_sys::Node, offset: u32) -> Option<u32> {
    if cur.is_same_node(Some(target)) {
        if cur.node_type() == 3 {
            let s = cur.text_content().unwrap_or_default();
            let mut acc = 0u32;
            for ch in s.chars() {
                let l = ch.len_utf16() as u32;
                if acc + l > offset {
                    break;
                }
                acc += l;
            }
            return Some(acc);
        }
        let kids = cur.child_nodes();
        let mut acc = 0u32;
        for i in 0..offset.min(kids.length()) {
            if let Some(k) = kids.get(i) {
                acc += subtree_units(&k);
            }
        }
        return Some(acc);
    }
    let kids = cur.child_nodes();
    let mut acc = 0u32;
    for i in 0..kids.length() {
        let Some(k) = kids.get(i) else { continue };
        match units_before_in(&k, target, offset) {
            Some(v) => return Some(acc + v),
            None => acc += subtree_units(&k),
        }
    }
    None
}

/// 点按落点捕获（调优，用户 2026-11-22 拍板，有意偏离原版的
/// 「截断标题聚焦一律光标文末」口径）：pointerdown 时以点按
/// 坐标对仍处截断显示的标题做命中（caretRangeFromPoint，与
/// 桥 setCaretByPoint 同机制），得截断串内字符位后映射到
/// 全文——落在可见前缀（前 10 字，含省略号前边界）→ 同位；
/// 落在省略号之后 → 全文末尾（省略号所代表隐藏段的就近端
/// 点）。捕获必须在 pointerdown（聚焦之前）：Chromium 点按
/// 的原生光标在 focus 事件之后才落入标题，onfocus 时读选区
/// 只读得到旧选区（时序探针实测）。仅截断形态（全文 >10
/// 字、DOM 为「前缀 + …」形）适用，其余返回 None（非点按 /
/// 不可映射一律维持文末口径）。返回值是全文字偏移。
fn tap_caret_target(el: &web_sys::Element, full: &str, x: f64, y: f64) -> Option<usize> {
    let full_len = full.chars().count();
    if full_len <= 10 {
        return None;
    }
    let dom_text = el.text_content().unwrap_or_default();
    if dom_text.chars().count() != 11 || !dom_text.ends_with('…') {
        return None;
    }
    let prefix: String = dom_text.chars().take(10).collect();
    if !full.starts_with(&prefix) {
        return None;
    }
    let doc = web_sys::window()?.document()?;
    // web-sys 未绑定 WebKit 私有 caretRangeFromPoint（只有
    // 标准版 caretPositionFromPoint），经 Reflect 直调，
    // 返回的 Range 后续口径不变（出场线代修，标题线复核）。
    let func = js_sys::Reflect::get(&doc, &wasm_bindgen::JsValue::from_str("caretRangeFromPoint"))
        .ok()?
        .dyn_into::<js_sys::Function>()
        .ok()?;
    let range = func
        .call2(
            &doc,
            &wasm_bindgen::JsValue::from_f64(x),
            &wasm_bindgen::JsValue::from_f64(y),
        )
        .ok()?
        .dyn_into::<web_sys::Range>()
        .ok()?;
    let el_node: &web_sys::Node = el.unchecked_ref();
    let start = range.start_container().ok()?;
    if !el_node.contains(Some(&start)) {
        return None;
    }
    let before = units_before_in(el_node, &start, range.start_offset().ok()?)?;
    let mut acc = 0u32;
    let mut c = 0usize;
    for ch in dom_text.chars() {
        let l = ch.len_utf16() as u32;
        if acc + l > before {
            break;
        }
        acc += l;
        c += 1;
    }
    Some(if c <= 10 { c } else { full_len })
}

/// 标题输入（原版是 contenteditable div，不是 <input>：input 的
/// 固有宽度会把胶囊撑大、且不能换行）。非受控：初始文本只在
/// 挂载时写一次；文本同步走桥的 titleText 消息（组合期间不
/// 提交）；聚焦时同步展开全文（仅截断显示与全文不一致时才换
/// 文本，未截断不碰选区），光标到末尾走 rAF 延后（同步设选区
/// 会被 WebKit 的落点计算冲掉，见 onfocus 内注）——例外是点按
/// 聚焦截断长标题的调优落点（用户 2026-11-22 拍板，有意偏离
/// 原版文末口径，见 tap_caret_target）；失焦时同步
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
    // 点按落点记号（调优）：pointerdown 时已把点按坐标映射成
    // 全文字偏移并记下（带时间戳），onfocus 在换文本分支消费；
    // 键盘 Tab / 程序聚焦不置位，维持文末口径。onblur 清除。
    let mut tap_mark = use_signal(|| None::<(usize, f64)>);
    rsx! {
        div {
            id: "editor-title-text",
            class: "{cls}",
            contenteditable: "true",
            role: "textbox",
            "aria-label": "{crate::i18n::t(\"editor.untitled\")}",
            "enterkeyhint": "done",
            dangerous_inner_html: "{initial}",
            onpointerdown: move |e| {
                let p = e.data.client_coordinates();
                let mark = title_element()
                    .and_then(|el| tap_caret_target(&el, &title.read(), p.x, p.y));
                tap_mark.set(mark.map(|m| (m, js_sys::Date::now())));
            },
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
                // 桥快照同任务按全文初始化（标题三症根治）：
                // 桥是标题布局的唯一存储、本锁存只是其投影；
                // 桥 focusin 按 DOM textContent 建快照时文本
                // 可能仍是截断显示（溢出位假阴），此处以全文
                // 长度经 __mnTitleSnapInit 覆写，两路同值收
                // 敛。必须同步直调（聚焦事务内），不挂异步。
                if let Some(w) = web_sys::window() {
                    let wv: &wasm_bindgen::JsValue = w.as_ref();
                    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnTitleSnapInit".into()) {
                        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                            let _ = func.call2(
                                wv,
                                &wasm_bindgen::JsValue::from_bool(n > 5),
                                &wasm_bindgen::JsValue::from_bool(n > 11),
                            );
                        }
                    }
                }
                editing.set(true);
                // 点按落点（调优）：pointerdown 记号在 2s 内未被
                // 消费才采用；只读记号、不动 DOM，不破状态先行序。
                let tap_m = match *tap_mark.read() {
                    Some((m, ts)) if js_sys::Date::now() - ts <= 2000.0 => Some(m),
                    _ => None,
                };
                tap_mark.set(None);
                if let Some(el) = title_element() {
                    if let Some(sc) = el.parent_element() {
                        sc.set_scroll_left(0);
                    }
                    // 同步展开：截断态才换文本并把光标移到末尾；
                    // 未截断不碰选区（原生落点）。
                    let node: &web_sys::Node = el.unchecked_ref();
                    if node.text_content().unwrap_or_default() != full {
                        // 调优点按落点：目标在 pointerdown 时已
                        // 捕获映射（见 tap_caret_target），此处只
                        // 换算成 UTF-16 位移、随同帧 rAF 落位；
                        // 无记号（非点按）时为 None，维持文末口径。
                        let tap_units = tap_m.map(|m| {
                            diag::log("EDIT", &format!("title caret tap -> {m}"));
                            full.chars()
                                .take(m)
                                .map(|c| c.len_utf16() as u32)
                                .sum::<u32>()
                        });
                        node.set_text_content(Some(&full));
                        // 光标落位走 rAF（原版 onFocus 同口径）：
                        // 在 focus 事件内同步 remove_all_ranges /
                        // add_range 会与 WebKit 自身的落点计算相
                        // 撞——WebKit 仪表化实测：空标题（新备忘）
                        // 时同步设选区后 rangeCount 归零（无光标，
                        // 键盘输入无处落，即真机首击打不出字）；
                        // 截断标题时同步选区被原生落点覆盖回 tap
                        // 点（光标不在末尾）。延后一帧、等浏览器
                        // 落点尘埃落定后再设，才稳定。目标位：非
                        // 点按 = 文末（原口径）；点按 = pointerdown 捕获的
                        // 映射位（调优），机制与时序不变。
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
                                        let mut placed = false;
                                        if let Some(units) = tap_units {
                                            // 换文本后正文是单一文本
                                            // 节点，按 UTF-16 位移落位。
                                            if let Some(tn) = node.first_child() {
                                                let len = subtree_units(&tn);
                                                if range.set_start(&tn, units.min(len)).is_ok() {
                                                    let _ = range.collapse_with_to_start(true);
                                                    placed = true;
                                                }
                                            }
                                        }
                                        if !placed {
                                            let _ = range.select_node_contents(node);
                                            let _ = range.collapse_with_to_start(false);
                                        }
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
                tap_mark.set(None);
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
