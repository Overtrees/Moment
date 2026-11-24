//! 错误徽章通道（原版 src/error-boundary.js 的 MynoteErrors
//! 等价物，审计 E-1 根治）：编辑页没有 toast——失败经
//! add_warn 进右下角徽章（36×36、有错误红底/纯警告黄底、
//! 不自动消失、点击展开详情面板、累积上限 20 条含时间与
//! 堆栈、面板可一键清除）；全局运行时错误由 diag 的错误
//! 钩以 RENDER/PROMISE 类型一并投递（原版 window error /
//! unhandledrejection 监听同口径，REACT 类型在 Dioxus 下
//! 无对应面、不产）。条目仅存内存（原版同为内存数组、
//! 刷新即清），不落盘；每次投递以 Diag ERRBADGE 行记结果
//! 侧总量（投递后条数），供探针核对通道真实生效。

use dioxus::prelude::*;

const MAX_ENTRIES: usize = 20;

#[derive(Clone, PartialEq)]
pub(crate) struct ErrEntry {
    /// WARN / RENDER / PROMISE（原版 type 字段）。
    kind: &'static str,
    message: String,
    /// 位置（原版 loc：source 文件名:行号；仅全局错误有）。
    loc: String,
    stack: String,
    /// 原版 time：new Date().toLocaleString()（浏览器默认
    /// 语言环境、无参数，与原版逐字同口径）。
    time: String,
}

static ENTRIES: GlobalSignal<Vec<ErrEntry>> = Signal::global(Vec::new);

fn now_locale_string() -> String {
    // 原版 toLocaleString() 无参 = 浏览器默认语言环境；
    // js-sys 签名须传 locale 串，以 navigator.language 等价。
    let locale = web_sys::window()
        .and_then(|w| w.navigator().language())
        .unwrap_or_default();
    js_sys::Date::new_0()
        .to_locale_string(&locale, &wasm_bindgen::JsValue::UNDEFINED)
        .as_string()
        .unwrap_or_default()
}

fn first_lines(s: &str, n: usize) -> String {
    s.lines().take(n).collect::<Vec<_>>().join("\n")
}

fn trunc_chars(s: &str, n: usize) -> String {
    if s.chars().count() > n {
        s.chars().take(n).collect()
    } else {
        s.to_string()
    }
}

/// 以给定 message 新建 JS Error 取其 stack（原版 addWarn/
/// addError 收 err 对象、取 stack 前 4/8 行的等价物：调用
/// 点没有现成 Error 对象时在此合成，堆栈指向投递点）。
fn capture_stack(message: &str, lines: usize) -> String {
    let err = js_sys::Error::new(message);
    let stack = js_sys::Reflect::get(
        &wasm_bindgen::JsValue::from(err),
        &wasm_bindgen::JsValue::from_str("stack"),
    )
    .ok()
    .and_then(|v| v.as_string())
    .unwrap_or_default();
    first_lines(&stack, lines)
}

fn push(kind: &'static str, message: &str, loc: &str, stack: String) {
    let total = {
        let mut w = ENTRIES.write();
        w.push(ErrEntry {
            kind,
            message: message.to_string(),
            loc: loc.to_string(),
            stack,
            time: now_locale_string(),
        });
        if w.len() > MAX_ENTRIES {
            w.remove(0);
        }
        w.len()
    };
    // 结果侧打点：记投递后的实际条数（通道是否真入列以此为准）。
    crate::diag::log(
        "ERRBADGE",
        &format!(
            "{kind} +1 total={total} msg={}",
            trunc_chars(message, 60)
        ),
    );
}

/// 警告投递（原版 addWarn）：编辑页各失败点调用。detail 为
/// 底层错误文本时作堆栈首行呈现（原版传 err 对象取其
/// stack 前 4 行）；无 detail 时合成 Error 取 stack。
pub(crate) fn add_warn(message: &str, detail: Option<&str>) {
    let stack = match detail {
        Some(d) if !d.is_empty() => first_lines(d, 4),
        _ => capture_stack(message, 4),
    };
    push("WARN", message, "", stack);
}

/// 全局错误投递（原版 addError）：diag 错误钩调用，stack
/// 取前 8 行（原版口径）。
pub(crate) fn add_error(kind: &'static str, message: &str, loc: &str, stack: &str) {
    push(kind, message, loc, first_lines(stack, 8));
}

fn clear_all() -> usize {
    let mut w = ENTRIES.write();
    let n = w.len();
    w.clear();
    n
}

fn kind_icon(kind: &str) -> &'static str {
    match kind {
        "RENDER" => "🖥️",
        "PROMISE" => "⏳",
        "REACT" => "🎬",
        _ => "⚠️",
    }
}

/// 徽章 + 详情面板（原版 createOverlay 的 DOM 等价物）：
/// 条数为 0 时不渲染（原版徽章 opacity 0、无条目不可见，
/// 用户可见行为等价）；样式在 styles/base.css 的 .eb-* 段。
#[component]
pub(crate) fn ErrorBadge() -> Element {
    let mut open = use_signal(|| false);
    let entries = ENTRIES.read().clone();
    let count = entries.len();
    if count == 0 {
        return rsx! {};
    }
    let has_error = entries.iter().any(|e| e.kind != "WARN");
    let count_label = if count > 99 {
        "99+".to_string()
    } else {
        count.to_string()
    };
    let badge_bg = if has_error {
        "var(--color-danger-bright)"
    } else {
        "var(--color-warning)"
    };
    let title = if has_error {
        crate::i18n::t("errbadge.title_error")
    } else {
        crate::i18n::t("errbadge.title_warn")
    };
    let title_color = if has_error {
        "var(--color-danger-light)"
    } else {
        "var(--color-warning)"
    };
    rsx! {
        div {
            class: "eb-badge",
            style: "background:{badge_bg}",
            onclick: move |_| {
                let next = !*open.read();
                open.set(next);
                if next {
                    crate::diag::log("ERRBADGE", &format!("panel open total={count}"));
                }
            },
            span { class: "eb-dot",
                span { class: "eb-bang", "!" }
                span { class: "eb-count", "{count_label}" }
            }
        }
        if *open.read() {
            div { class: "eb-panel",
                div { class: "eb-panel-head",
                    span { class: "eb-title", style: "color:{title_color}", "{title}" }
                    span {
                        class: "eb-clear",
                        onclick: move |_| {
                            let n = clear_all();
                            open.set(false);
                            crate::diag::log("ERRBADGE", &format!("clear {n}"));
                        },
                        "{crate::i18n::t(\"errbadge.clear\")}"
                    }
                }
                div { class: "eb-list",
                    for e in entries.iter().rev() {
                        div { class: "eb-entry",
                            span { class: "eb-entry-icon", "{kind_icon(e.kind)}" }
                            div { class: "eb-entry-body",
                                div {
                                    class: "eb-entry-msg",
                                    style: if e.kind == "WARN" { "color:var(--color-warning)" } else { "color:var(--color-white)" },
                                    "{trunc_chars(&e.message, 120)}"
                                }
                                div { class: "eb-entry-meta",
                                    if !e.loc.is_empty() {
                                        span { class: "eb-entry-loc", "{e.loc}" }
                                    }
                                    span { "{e.time}" }
                                }
                                if !e.stack.is_empty() {
                                    pre { class: "eb-entry-stack", "{e.stack}" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
