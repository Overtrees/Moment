//! JS 桥：EDITOR_JS（contenteditable 事件采集、光标数学、
//! 全局监听登记册 __mnBridgeCleanup）与编辑器卸载的同步
//! 清理接线（sync_editor_cleanup）。桥 JS 本体在
//! js/editor.js（批 14 自 bridge.rs 内嵌 raw string 抽出，
//! 内容逐字不变），经 include_str! 编译期装载。

use super::*;

pub(super) const EDITOR_JS: &str = include_str!("js/editor.js");

/// 编辑器卸载的同步清理（use_drop 闭包内直调，绝不 spawn）：
/// ① 调 JS 侧 __mnSchemeCleanup（摘 scheme matchMedia 监听，
/// 幂等自清）；② 摘除具名全局监听
/// __mnEdScroll（window scroll）/__mnEsc（document keydown
/// capture）/__mnTypedMark（document input capture）/
/// __mnResume（visibilitychange/pageshow/focus 回前台补完）
/// 并置 null；
/// ③ 调桥的 __mnBridgeCleanup（摘 document/window/
/// visualViewport 全部桥监听、清 20s 同步定时器、桥 window
/// 入口置 null，幂等自清）；④ 调 __mnWideCleanup（摘 wide
/// matchMedia 监听）。③④ 是页面副作用审计泄漏 2/3 的根治：
/// 桥与两处 matchMedia 旧实现全是匿名登记、跨挂载线性累积。
/// 全部 web_sys/js_sys 同步执行——卸载后组件作用域消失，任何
/// 异步清理（spawn+eval）都会被取消、永不落地（实测教训）。
/// html/body 根背景不在此处处理：已改由 App 外壳派生（main.rs）。
/// 清理实证（CLEAN 行，诊断覆盖补齐）：逐项记删前类型与删
/// 后复查——原末尾「cleanup sync done」是无条件打印、证明
/// 不了任何一项真被摘掉。__mnBgCleanup 已随渐变改写装置移
/// 除、不再有清理职责，只列入普查作恒 null 的见证；
/// #body-before-bg 在否（bbbg）同理。
pub(super) fn sync_editor_cleanup() {
    let Some(w) = web_sys::window() else { return };
    let wv: &wasm_bindgen::JsValue = w.as_ref();
    let null = wasm_bindgen::JsValue::NULL;
    // CLEAN 实证：具名全局的删前类型（fn/null/other），清理
    // 后同表复查，末尾成行（见函数头注）。
    fn kind_of(wv: &wasm_bindgen::JsValue, name: &str) -> &'static str {
        match js_sys::Reflect::get(wv, &name.into()) {
            Ok(v) => {
                if v.is_null() || v.is_undefined() {
                    "null"
                } else if v.dyn_ref::<js_sys::Function>().is_some() {
                    "fn"
                } else {
                    "other"
                }
            }
            Err(_) => "err",
        }
    }
    const NAMES: [&str; 8] = [
        "__mnBgCleanup",
        "__mnSchemeCleanup",
        "__mnBridgeCleanup",
        "__mnWideCleanup",
        "__mnEdScroll",
        "__mnEsc",
        "__mnResume",
        "__mnTypedMark",
    ];
    let census = |wv: &wasm_bindgen::JsValue| -> String {
        NAMES
            .iter()
            .map(|n| format!("{n}={}", kind_of(wv, n)))
            .collect::<Vec<_>>()
            .join(" ")
    };
    let pre = census(wv);
    // ① scheme mq 监听清理（瘦身 scheme effect 登记，幂等自清）
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnSchemeCleanup".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call0(wv);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnSchemeCleanup".into(), &null);
    // ③ JS 桥全局登记清理（幂等：调用后自置 null）
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnBridgeCleanup".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call0(wv);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnBridgeCleanup".into(), &null);
    // ④ wide matchMedia 监听清理（幂等：调用后自置 null）
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnWideCleanup".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call0(wv);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnWideCleanup".into(), &null);
    // ② window scroll 监听
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnEdScroll".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = w.remove_event_listener_with_callback("scroll", func);
        }
    }
    let _ = js_sys::Reflect::set(wv, &"__mnEdScroll".into(), &null);
    // ③ document capture 监听（Esc / typed 标记）
    if let Some(d) = w.document() {
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnEsc".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback_and_bool("keydown", func, true);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnEsc".into(), &null);
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnResume".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback("visibilitychange", func);
                let _ = w.remove_event_listener_with_callback("pageshow", func);
                let _ = w.remove_event_listener_with_callback("focus", func);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnResume".into(), &null);
        if let Ok(f) = js_sys::Reflect::get(wv, &"__mnTypedMark".into()) {
            if let Some(func) = f.dyn_ref::<js_sys::Function>() {
                let _ = d.remove_event_listener_with_callback_and_bool("input", func, true);
            }
        }
        let _ = js_sys::Reflect::set(wv, &"__mnTypedMark".into(), &null);
    }
    let post = census(wv);
    let bbbg = w
        .document()
        .and_then(|d| d.get_element_by_id("body-before-bg"))
        .is_some();
    diag::log(
        "EDIT",
        &format!("CLEAN pre[{pre}] post[{post}] bbbg={bbbg}"),
    );
    diag::log("EDIT", "editor cleanup sync done");
}
