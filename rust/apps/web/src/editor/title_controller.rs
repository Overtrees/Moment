//! 标题编辑会话的唯一所有者（标题胶囊全面重构）：监听以
//! web-sys 直接注册在标题元素上，不经 JS 桥、不经 Dioxus
//! 合成事件；编辑会话内 DOM 文本、几何（胶囊宽/内边距/滚
//! 动）、光标跟随与提交全归本控制器，框架渲染不碰标题子
//! 树（静态壳见 title.rs 的 TitleCapsule）。
//!
//! 状态机：Idle → Editing ⇄ Composing → Committing → Idle。
//! 文本只在 compositionend / blur / Enter / Esc 四个时机写
//! 回（经 on_commit 交 Editor 置标题信号 + persist），逐键
//! 输入只驱动几何——组字跨阈值不再引发整树重渲染，也不再
//! 有第二个写者与本控制器抢标题元素。
//!
//! 几何＝原版机制等价移植（editor.js 的标题闩锁 + 布局
//! 同步 + caret 同步三件套，逐项对原版行号取证）：
//! ① 闩锁按**实时全文**（含组字串）的 UTF-16 长度判定
//! ——>5 字 is_long、>11 字 is_overflow，聚焦时按初始全
//! 文取初值、会话内只升不降；② 布局同步（sync_layout，
//! 对原版 syncTitleCompositionLayout）：闩锁/模式变化时
//! 一次性直写模式样式——非 overflow 时胶囊 width 为
//! auto（内容驱动 shrink-to-fit，浏览器对在场文本的布
//! 局本身即宽度，无镜像量测、无弹簧、无显式 px 宽）、
//! 字号 11/14、长态折行；overflow 时胶囊定宽 184、滚动
//! 区 width 100% + padding-inline 16 + scroll-padding-
//! inline 16、输入 nowrap + min-width max-content + 左
//! 对齐；③ caret 同步（schedule_caret_sync，对原版同名
//! 机制）：事件驱动双 rAF 合并，相邻字形边界量 caret
//! x，仅当 caret 距滚动区左右缘 <16px 时按边距规则挪
//! scrollLeft（钳 [0, scrollWidth-clientWidth]），触发源
//! 与原版同集（input/compositionupdate/focus/selection-
//! change/resize/visualViewport）。标题面内距只许
//! padding-inline / padding-block 单值简写（胶囊 long
//! 6/18、short 0/20），左右对称是构造性质。
//!
//! 组字期不冻结、布局跟随实时全文（根治中段蓝竖条）：
//! 上一版冻结把胶囊宽钉在已提交文本宽上（空起打时 cw
//! 97.9 而组字串长到 44 字、sl 232），整串被塞进窄胶
//! 囊横滚、组字串起始缘停在胶囊中段被 WebKit 绘出竖
//! 条；且我方组字期零写入、补丁层无解。新机制下组字串
//! 与已提交文本同权定尺寸：≤11 字整串在流内完整呈现
//! （横滚不启动、sl 恒 0），第 12 字闩锁翻转即刻到
//! 184 终宽 + max-content 输入 + 边距规则滚动，起始缘
//! 随滚动整体移出左缘。scrollLeft 全仓只有三个写者
//! （聚焦归零、失焦归零、边距规则 caret 同步——选区不
//! 在输入内时 no-op），旧帧循环的非 cap 强制归零与 cap
//! 校正互抢（compend 后 412→3→412 跳变）随写者消失；
//! 聚焦宽超 cap（269→184）是旧弹簧以展示涌现宽为起点
//! 所致，新机制聚焦首帧即闩锁定宽、无超 cap 帧。
//!
//! Diag（titleGeom）：事件行（focus/compstart/compupdate
//! 节流/compend/commit/blur/cap）+ 帧行（cw 变化 ≥1px 或
//! sl 变化）+ MutationObserver 外来变更守卫：控制器自写打
//! selfWrite 标记，非自写的属性/结构变更记 ph=foreign 并
//! 累计到 window.__mnTitleGeomForeign（真机再现双竖条时
//! 先看 foreign 行定层）。

use super::*;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use wasm_bindgen::closure::Closure;

/// caret 边距（原版 scheduleTitleCaretSync 的 MARGIN 与
/// TITLE_CARET_GUTTER 同值 16）。
const CARET_MARGIN: f64 = 16.0;
/// is_long 闩锁阈值（原版：实时全文长度 >5 字号切 11px、
/// 胶囊内距切 6/18、输入转折行）。
const LONG_UNITS: usize = 5;
/// is_overflow 闩锁阈值（原版：>11 胶囊定宽 184 =
/// TITLE_CAPSULE_MAX_CONTENT_W 148 + 内距 36）。
const OVERFLOW_UNITS: usize = 11;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Idle,
    Editing,
    Composing,
    Committing,
}

struct Listener {
    target: web_sys::EventTarget,
    kind: &'static str,
    closure: Closure<dyn FnMut(web_sys::Event)>,
}

struct Inner {
    input: web_sys::HtmlElement,
    scroller: web_sys::Element,
    capsule: web_sys::Element,
    meta: web_sys::Element,
    committed: String,
    on_commit: EventHandler<String>,
    on_session: EventHandler<bool>,
    phase: Phase,
    // —— 会话几何（原版闩锁模型） ——
    /// 当前字号（闩锁派生：is_long 时 11、否则 14；Diag
    /// fs 字段与 apply_display 共用此落点）
    fs: f64,
    /// 长态闩锁（实时全文 >5 字，只升不降）
    is_long: bool,
    /// 横滚态闩锁（实时全文 >11 字，只升不降；Diag cap）
    is_overflow: bool,
    /// 模式样式是否已按当前闩锁写入（模式未变不重写）
    layout_applied: bool,
    applied_mode: (bool, bool),
    // —— caret 同步双 rAF 链 ——
    raf_id: Option<i32>,
    raf_closure: Option<Closure<dyn FnMut(f64)>>,
    /// 双 rAF 链已排队（合并多次调度，原版同口径）
    sync_queued: bool,
    /// 已过第一跳、下一帧执行边距校正
    sync_second: bool,
    // —— Diag 节流/帧行基线 ——
    last_upd_log_ms: f64,
    last_upd_len: usize,
    logged_cw: f64,
    logged_sl: f64,
    // —— 点按落点记号（pointerdown 捕获、focus 消费）——
    tap_mark: Option<(usize, f64)>,
    // —— 外来变更守卫 ——
    self_write: Rc<Cell<bool>>,
    foreign: u32,
    /// 控制器几何写计数（布局同步的模式样式写 + caret
    /// 同步的 scrollLeft 写，挂 window.__mnTitleGeomWrites，
    /// 与 foreign 同口径，供探针/Diag 观测写者活动）
    geom_writes: u32,
    observer: Option<web_sys::MutationObserver>,
    observer_cb: Option<Closure<dyn FnMut(js_sys::Array)>>,
    listeners: Vec<Listener>,
}

/// 标题控制器句柄（静态壳持有，卸载时 detach）。
pub(super) struct TitleController {
    inner: Rc<RefCell<Inner>>,
}

fn window() -> Option<web_sys::Window> {
    web_sys::window()
}

/// scrollLeft 浮点读/写（web-sys 绑定为 i32 会截断小数量，
/// 与旧桥 JS 的浮点口径对齐走 Reflect）。
fn scroll_left_f(el: &web_sys::Element) -> f64 {
    js_sys::Reflect::get(el, &"scrollLeft".into())
        .ok()
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0)
}

fn set_scroll_left_f(el: &web_sys::Element, v: f64) {
    let _ = js_sys::Reflect::set(el, &"scrollLeft".into(), &wasm_bindgen::JsValue::from_f64(v));
}

/// 元素内联样式（web-sys 的 style() 只绑在 HtmlElement
/// 上，标题四元素均为 div/span，统一经此取）。
fn style_of(el: &web_sys::Element) -> web_sys::CssStyleDeclaration {
    el.unchecked_ref::<web_sys::HtmlElement>().style()
}

/// 子树内文本的 UTF-16 总长。
fn subtree_units(n: &web_sys::Node) -> u32 {
    n.text_content()
        .map(|s| s.encode_utf16().count() as u32)
        .unwrap_or(0)
}

/// 选区端点 (target, offset) 之前、cur 子树内的文本 UTF-16
/// 长（DOM 遍历版）；端点不在此子树返回 None。端点为文本
/// 节点时 offset 是字符内 UTF-16 位移，为元素时是子节点
/// 序号。
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

/// 点按落点捕获（调优，用户 2026-11-22 拍板，有意偏离原版
/// 的「截断标题聚焦一律光标文末」口径，自旧 TitleText 迁
/// 入、口径不变）：pointerdown 时以点按坐标对仍处截断显
/// 示的标题做命中（caretRangeFromPoint），得截断串内字符
/// 位后映射到全文——落在可见前缀（前 10 字）→ 同位；落在
/// 省略号之后 → 全文末尾。仅截断形态（全文 >10 字、DOM
/// 为「前缀 + …」形）适用，其余返回 None（维持文末口径）。
/// 返回值是全文字偏移。
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
    let doc = window()?.document()?;
    // web-sys 未绑定 WebKit 私有 caretRangeFromPoint（只有
    // 标准版 caretPositionFromPoint），经 Reflect 直调。
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

/// 文本节点的 UTF-16 长（0 长返回 None 的判定在调用侧）。
fn text_units(node: &web_sys::Node) -> u32 {
    node.text_content()
        .map(|s| s.encode_utf16().count() as u32)
        .unwrap_or(0)
}

/// 从 node 起按 from_end 方向找第一个非空文本节点（旧桥
/// syncTitleCaret 的 findEdgeText 等价移植：元素锚选区要
/// 落到相邻字形边界上量 x）。
fn find_edge_text(node: &web_sys::Node, from_end: bool) -> Option<web_sys::Node> {
    if node.node_type() == 3 {
        return if text_units(node) > 0 {
            Some(node.clone())
        } else {
            None
        };
    }
    let kids = node.child_nodes();
    let n = kids.length();
    for i in 0..n {
        let idx = if from_end { n - 1 - i } else { i };
        if let Some(k) = kids.get(idx) {
            if let Some(f) = find_edge_text(&k, from_end) {
                return Some(f);
            }
        }
    }
    None
}

/// 光标的视口 x（相邻字形边界量法，与旧桥同口径）：折叠
/// 选区自身 rect 在元素锚形态下为全零不可用，故按选区端
/// 点相邻字符的 rect 取右/左缘。选区不在标题内返回 None。
fn caret_client_x(input: &web_sys::Element) -> Option<f64> {
    let w = window()?;
    let sel = w.get_selection().ok()??;
    if sel.range_count() == 0 {
        return None;
    }
    let focus_node = sel.focus_node()?;
    let focus_off = sel.focus_offset();
    let (tn, off) = if focus_node.node_type() == 3 {
        (focus_node.clone(), focus_off)
    } else if focus_node.node_type() == 1 {
        let at_end = focus_off > 0;
        let child = focus_node
            .child_nodes()
            .get(if at_end { focus_off - 1 } else { focus_off })?;
        let t = find_edge_text(&child, at_end)?;
        let l = text_units(&t);
        (t, if at_end { l } else { 0 })
    } else {
        return None;
    };
    let input_node: &web_sys::Node = input.unchecked_ref();
    if !input_node.contains(Some(&tn)) {
        return None;
    }
    let l = text_units(&tn);
    if l == 0 {
        return None;
    }
    let off = off.min(l);
    let (from, to) = if off > 0 {
        (off - 1, off)
    } else {
        (0, 1.min(l))
    };
    let doc = w.document()?;
    let range = doc.create_range().ok()?;
    range.set_start(&tn, from).ok()?;
    range.set_end(&tn, to).ok()?;
    let r = range.get_bounding_client_rect();
    if r.height() == 0.0 {
        return None;
    }
    Some(if off > 0 { r.right() } else { r.left() })
}

/// 选区端点在标题内的 UTF-16 位移（Diag sel 字段）；选区
/// 不在标题内或无选区返回 -1。
fn sel_offset_units(input: &web_sys::Element) -> i64 {
    let Some(w) = window() else { return -1 };
    let Ok(Some(sel)) = w.get_selection() else {
        return -1;
    };
    if sel.range_count() == 0 {
        return -1;
    }
    let Some(focus_node) = sel.focus_node() else {
        return -1;
    };
    let input_node: &web_sys::Node = input.unchecked_ref();
    if !input_node.contains(Some(&focus_node)) {
        return -1;
    }
    units_before_in(input_node, &focus_node, sel.focus_offset())
        .map(|v| v as i64)
        .unwrap_or(-1)
}

impl Inner {
    fn text_now(&self) -> String {
        let node: &web_sys::Node = self.input.unchecked_ref();
        node.text_content().unwrap_or_default()
    }

    /// Diag titleGeom 行（字段 ph/len/comp/tw/cw/sl/fs/cap/
    /// caret/capR/sel）。len 为实时全文的 UTF-16 单位数
    /// （与原版 JS .length 同口径，组字期含组字串）；tw
    /// 为在场全文的布局宽（Range 量输入内容矩形，组字期
    /// 随组字串实时变化——新机制下它就是定宽依据的地面
    /// 真值，不再是冻结值）；cw 为胶囊实时 rect 宽。
    fn geom_line(&self, ph: &str) -> String {
        let len = self.text_now().encode_utf16().count();
        let comp = if self.phase == Phase::Composing { 1 } else { 0 };
        let sl = scroll_left_f(&self.scroller);
        let caret = caret_client_x(&self.input)
            .map(|v| v.round() as i64)
            .unwrap_or(-1);
        let cap_r = self.capsule.get_bounding_client_rect().right().round() as i64;
        let sel = sel_offset_units(&self.input);
        format!(
            "titleGeom ph={ph} len={len} comp={comp} tw={:.1} cw={:.1} sl={:.1} fs={:.0} cap={} caret={caret} capR={cap_r} sel={sel}",
            live_text_w(&self.input),
            self.capsule.get_bounding_client_rect().width(),
            sl,
            self.fs,
            if self.is_overflow { 1 } else { 0 },
        )
    }

    fn log_geom(&mut self, ph: &str) {
        let line = self.geom_line(ph);
        self.logged_cw = self.capsule.get_bounding_client_rect().width();
        self.logged_sl = scroll_left_f(&self.scroller);
        diag::log("EDIT", &line);
    }

    /// 自写标记开：随后同一同步块内的 DOM 写入在
    /// MutationObserver 回调里被认作自写（标记的清除挂微
    /// 任务，排在观察者回调之后，见 self_write_end）。
    fn self_write_begin(&self) {
        self.self_write.set(true);
    }

    fn self_write_end(&self) {
        // 清标必须排在 MutationObserver 的投递微任务之后：
        // 观察者投递在首个变更记录产生时入队，若清标只跳一
        // 个微任务、且本写块之前已有空写块排过清标，投递会
        // 落在两次清标之间、把自写误判为外来（真机同理）。
        // 两跳清标保证投递先行；同任务内后续写块再置位不
        // 受影响（置位在清标执行前发生时标志仍为真）。
        let flag = self.self_write.clone();
        if let Some(w) = window() {
            let flag2 = flag.clone();
            let hop2 = Closure::once_into_js(move || flag2.set(false));
            let hop1 = Closure::once_into_js(move || {
                if let (Some(w2), Some(f2)) = (window(), hop2.dyn_ref::<js_sys::Function>()) {
                    w2.queue_microtask(f2);
                }
            });
            if let Some(f1) = hop1.dyn_ref::<js_sys::Function>() {
                w.queue_microtask(f1);
            } else {
                flag.set(false);
            }
        }
    }

    /// 布局同步（原版 syncTitleCompositionLayout 的等价
    /// 移植）：按实时全文（含组字串）的 UTF-16 长度升级
    /// is_long / is_overflow 闩锁（只升不降），模式变化时
    /// 一次性直写模式样式。非组字 input 与组字事件共用
    /// 此落点（原版非组字走 state 重渲染写同组样式、组
    /// 字期直写，值同源）。非 overflow 时胶囊不写 width
    /// （auto＝内容驱动），文本在流内完整呈现、横滚不启
    /// 动；overflow 时定宽 184、滚动区 gutter 16 接管
    /// caret 边距、输入 max-content 全长布局——组字串起
    /// 始缘只会随滚动整体移出左缘，不停中段。
    fn sync_layout(&mut self) {
        let units = self.text_now().encode_utf16().count();
        let mut cap_flip = false;
        if units > LONG_UNITS && !self.is_long {
            self.is_long = true;
        }
        if units > OVERFLOW_UNITS && !self.is_overflow {
            self.is_overflow = true;
            cap_flip = true;
        }
        let mode = (self.is_long, self.is_overflow);
        if self.layout_applied && self.applied_mode == mode {
            return;
        }
        self.layout_applied = true;
        self.applied_mode = mode;
        self.fs = if self.is_long { 11.0 } else { 14.0 };
        self.self_write_begin();
        let cap_style = style_of(&self.capsule);
        if self.is_overflow {
            let _ = cap_style.set_property("width", "184px");
        } else {
            let _ = cap_style.remove_property("width");
        }
        let _ = cap_style.set_property(
            "padding-inline",
            if self.is_long { "18px" } else { "20px" },
        );
        let _ = cap_style.set_property(
            "padding-block",
            if self.is_long { "6px" } else { "0px" },
        );
        let scr = style_of(&self.scroller);
        let _ = scr.set_property("width", if self.is_overflow { "100%" } else { "auto" });
        let _ = scr.set_property(
            "padding-inline",
            if self.is_overflow { "16px" } else { "0px" },
        );
        let _ = scr.set_property(
            "scroll-padding-inline",
            if self.is_overflow { "16px" } else { "0px" },
        );
        let inp = self.input.style();
        let _ = inp.set_property("font-size", if self.is_long { "11px" } else { "14px" });
        let _ = inp.set_property(
            "white-space",
            if self.is_overflow || !self.is_long {
                "nowrap"
            } else {
                "normal"
            },
        );
        let _ = inp.set_property(
            "word-break",
            if !self.is_overflow && self.is_long {
                "break-all"
            } else {
                "normal"
            },
        );
        let _ = inp.set_property(
            "text-align",
            if self.is_overflow { "left" } else { "center" },
        );
        let _ = inp.set_property(
            "min-width",
            if self.is_overflow { "max-content" } else { "auto" },
        );
        self.self_write_end();
        self.geom_writes += 1;
        set_geom_writes_counter(self.geom_writes);
        if cap_flip {
            self.log_geom("cap");
        }
    }

    /// caret 同步调度（原版 scheduleTitleCaretSync 的等
    /// 价移植）：双 rAF 等布局落定后才量 caret、合并快速
    /// 输入期间排队的多次调度。会话外不排队。
    fn schedule_caret_sync(&mut self) {
        if !matches!(self.phase, Phase::Editing | Phase::Composing) {
            return;
        }
        if self.sync_queued {
            return;
        }
        self.sync_queued = true;
        self.sync_second = false;
        self.request_sync_frame();
    }

    fn request_sync_frame(&mut self) {
        if let (Some(w), Some(cb)) = (window(), self.raf_closure.as_ref()) {
            if let Ok(id) = w.request_animation_frame(cb.as_ref().unchecked_ref()) {
                self.raf_id = Some(id);
            }
        }
    }

    /// 双 rAF 链的帧回调：第一跳只续排第二跳（等布局落
    /// 定），第二跳执行边距校正。
    fn on_sync_frame(&mut self) {
        self.raf_id = None;
        if !self.sync_queued {
            return;
        }
        if !self.sync_second {
            self.sync_second = true;
            self.request_sync_frame();
            return;
        }
        self.sync_queued = false;
        self.sync_second = false;
        self.caret_sync_run();
    }

    fn cancel_sync(&mut self) {
        self.sync_queued = false;
        self.sync_second = false;
        if let Some(id) = self.raf_id.take() {
            if let Some(w) = window() {
                let _ = w.cancel_animation_frame(id);
            }
        }
    }

    /// 边距规则校正（原版同口径）：相邻字形边界量 caret
    /// x，仅当 caret 距滚动区左右缘 <16px 时挪 scrollLeft
    /// （钳 [0, scrollWidth-clientWidth]）；选区不在标题
    /// 内时 caret_client_x 返回 None、整步 no-op——这也
    /// 是 compend 后 sl 跳变消失的构造原因：选区瞬时丢
    /// 失的帧里没有写者。内容装得下时 max_sl=0、天然
    /// no-op，不需要模式分流。
    fn caret_sync_run(&mut self) {
        if !matches!(self.phase, Phase::Editing | Phase::Composing) {
            return;
        }
        let Some(cx) = caret_client_x(&self.input) else {
            return;
        };
        let rect = self.scroller.get_bounding_client_rect();
        let cur = scroll_left_f(&self.scroller);
        let max_sl = (self.scroller.scroll_width() - self.scroller.client_width()).max(0) as f64;
        let mut sl = cur;
        if cx < rect.left() + CARET_MARGIN {
            sl = (cur - (rect.left() + CARET_MARGIN - cx)).max(0.0);
        } else if cx > rect.right() - CARET_MARGIN {
            sl = (cur + (cx - rect.right() + CARET_MARGIN)).min(max_sl);
        }
        let mut wrote = false;
        if (sl - cur).abs() > 0.01 {
            set_scroll_left_f(&self.scroller, sl);
            self.geom_writes += 1;
            set_geom_writes_counter(self.geom_writes);
            wrote = true;
        }
        // 帧行：胶囊宽较上次记录漂移 ≥1px 或本次写了
        // scrollLeft 才记（避免静止期刷屏）
        let cw_now = self.capsule.get_bounding_client_rect().width();
        if (cw_now - self.logged_cw).abs() >= 1.0 || wrote {
            self.log_geom("frame");
        }
    }

    /// 展示态几何（挂载时与会话收尾时）：长标题（展示串
    /// >5 字）以 11px 折行形态呈现、胶囊内距 block 6 /
    /// inline 18（与会话闩锁同口径、即原版渲染函数的非
    /// 编辑分支），其余全归 CSS 基础值。写者只有本控制器。
    fn apply_display(&mut self) {
        let disp_len = super::title::display_title_of(&self.committed)
            .chars()
            .count();
        let long = disp_len > 5;
        self.fs = if long { 11.0 } else { 14.0 };
        if long {
            self.self_write_begin();
            let inp = self.input.style();
            let _ = inp.set_property("font-size", "11px");
            let _ = inp.set_property("white-space", "normal");
            let _ = inp.set_property("word-break", "break-all");
            let _ = inp.set_property("max-height", "2.7em");
            let cap_style = style_of(&self.capsule);
            let _ = cap_style.set_property("padding-inline", "18px");
            let _ = cap_style.set_property("padding-block", "6px");
            self.self_write_end();
        }
    }

    /// 文本提交（compositionend 口径）：原文直写（不 trim，
    /// 与旧桥 compositionend 上报等价），变化才经 on_commit
    /// 交 Editor 置信号 + persist。
    fn commit_raw(&mut self, why: &str) {
        let raw = self.text_now();
        if raw != self.committed {
            self.committed = raw.clone();
            self.on_commit.call(raw);
            self.log_geom(why);
        }
    }

    fn on_focus(&mut self) {
        if self.phase != Phase::Idle {
            return;
        }
        self.phase = Phase::Editing;
        self.on_session.call(true);
        let full = self.committed.clone();

        // —— 空态/文本结构规范化（武装组字前一次性处理）：
        // 空标题置单个 <br>、非空置单个文本节点，会话内不
        // 再动文本节点结构（旧实现截断换文本同位，此处把
        // 结构口径写死，杜绝组字期节点形态漂移）。
        let cur = self.text_now();
        let node: &web_sys::Node = self.input.unchecked_ref();
        let single_text = node.child_nodes().length() == 1
            && node.first_child().map(|c| c.node_type() == 3).unwrap_or(false);
        let mut replaced = false;
        self.self_write_begin();
        if full.is_empty() {
            let is_br_only = node.child_nodes().length() == 1
                && node
                    .first_child()
                    .map(|c| c.node_name() == "BR")
                    .unwrap_or(false);
            if !is_br_only {
                node.set_text_content(None);
                if let Some(doc) = window().and_then(|w| w.document()) {
                    if let Ok(br) = doc.create_element("br") {
                        let _ = node.append_child(&br);
                    }
                }
            }
            replaced = cur != full;
        } else if cur != full || !single_text {
            node.set_text_content(Some(&full));
            replaced = true;
        }
        self.self_write_end();

        // —— 闩锁按初始全文取初值（原版快照口径：会话内
        // 只升不降，其后由 sync_layout 按实时全文升级，
        // 组字期同样生效）；模式样式由 sync_layout 按闩
        // 锁一次写齐，聚焦首帧即终态宽（长标题直接 184，
        // 无旧弹簧的涌现宽起点超 cap） ——
        let units = full.encode_utf16().count();
        self.is_long = units > LONG_UNITS;
        self.is_overflow = units > OVERFLOW_UNITS;
        self.layout_applied = false;

        // —— 会话样式（自写）：编辑期 max-height 放开（原
        // 版口径）、滚动归零（原版 onFocus 同动作） ——
        self.self_write_begin();
        let _ = self.input.style().set_property("max-height", "none");
        set_scroll_left_f(&self.scroller, 0.0);
        self.self_write_end();
        self.sync_layout();

        // —— 光标落位（仅换文本时；rAF 延后与旧实现同口径：
        // focus 事务内同步设选区会被 WebKit 落点计算冲掉） ——
        let tap_m = match self.tap_mark.take() {
            Some((m, ts)) if js_sys::Date::now() - ts <= 2000.0 => Some(m),
            _ => None,
        };
        if replaced {
            let tap_units = tap_m.map(|m| {
                diag::log("EDIT", &format!("title caret tap -> {m}"));
                full.chars()
                    .take(m)
                    .map(|c| c.len_utf16() as u32)
                    .sum::<u32>()
            });
            place_caret_next_frame(self.input.clone(), tap_units);
        }
        self.log_geom("focus");
        self.schedule_caret_sync();
    }

    fn on_blur(&mut self) {
        if self.phase == Phase::Idle {
            return;
        }
        // 组字中失焦（罕见）：compositionend 通常先行，此处
        // 按已落定文本收尾（迟到 compositionend 在 Idle 被
        // 守卫忽略，不回灌下一会话）。
        self.phase = Phase::Committing;
        self.cancel_sync();
        self.tap_mark = None;

        // —— 同步提交（旧 onblur 已验证口径逐项等价）：全文
        // trim、空回退「无标题」、写信号 + persist ——
        let raw = self.text_now();
        let trimmed = raw.trim().to_string();
        let committed = if trimmed.is_empty() {
            crate::i18n::t("editor.untitled")
        } else {
            trimmed
        };
        let changed = committed != self.committed;
        self.committed = committed.clone();
        if changed {
            self.on_commit.call(committed.clone());
            self.log_geom("commit");
        }

        // —— 就地回截断展示 + 摘全部会话 inline + 展示几何 ——
        self.self_write_begin();
        let node: &web_sys::Node = self.input.unchecked_ref();
        let disp = super::title::display_title_of(&committed);
        if node.text_content().as_deref() != Some(disp.as_str()) {
            node.set_text_content(Some(&disp));
        }
        set_scroll_left_f(&self.scroller, 0.0);
        let _ = self.input.remove_attribute("style");
        let _ = self.scroller.remove_attribute("style");
        let _ = self.capsule.remove_attribute("style");
        self.self_write_end();
        self.apply_display();

        self.phase = Phase::Idle;
        self.on_session.call(false);
        self.log_geom("blur");
    }

    fn on_composition_start(&mut self) {
        if self.phase == Phase::Editing {
            self.phase = Phase::Composing;
            // 组字开始即按含组字串的实时全文同步布局（原
            // 版 compositionstart 同动作），不冻结。
            self.sync_layout();
            self.log_geom("compstart");
        }
    }

    fn on_composition_update(&mut self) {
        if self.phase != Phase::Composing {
            return;
        }
        // 布局跟随实时全文（闩锁随组字串长度升级）+ caret
        // 同步保持边距——与原版 compositionupdate 的两个
        // 动作一一对应。
        self.sync_layout();
        self.schedule_caret_sync();
        // 节流：≥50ms 或实时长度变化才记（cap 翻转另有
        // ph=cap 行，不在此重复）
        let now = js_sys::Date::now();
        let len = self.text_now().encode_utf16().count();
        if now - self.last_upd_log_ms >= 50.0 || len != self.last_upd_len {
            self.last_upd_log_ms = now;
            self.last_upd_len = len;
            self.log_geom("compupdate");
        }
    }

    fn on_composition_end(&mut self) {
        match self.phase {
            Phase::Composing | Phase::Editing => {
                self.phase = Phase::Editing;
                // 落定文本再同步一次布局（闩锁按最终长度，
                // 与原版 compend 后 state 落定同效），提交原
                // 文，再排 caret 同步按边距规则收敛滚动。
                self.sync_layout();
                self.commit_raw("compend");
                self.schedule_caret_sync();
            }
            _ => {}
        }
    }
}

/// 在场全文的布局宽（Range 量输入内容矩形）：nowrap /
/// overflow 态即整串自然宽，折行态为折行后块宽。仅供
/// Diag tw 字段在记行时取地面真值，不参与任何几何决策
/// （定宽走闩锁 + 内容驱动，见 sync_layout）。
fn live_text_w(input: &web_sys::HtmlElement) -> f64 {
    let Some(doc) = window().and_then(|w| w.document()) else {
        return 0.0;
    };
    let Ok(range) = doc.create_range() else {
        return 0.0;
    };
    let node: &web_sys::Node = input.unchecked_ref();
    if range.select_node_contents(node).is_err() {
        return 0.0;
    }
    range.get_bounding_client_rect().width()
}

/// 换文本后的光标落位（rAF 一帧）：点按记号给定时落映射
/// 位、否则文末。与旧 TitleText 同机制同时序（focus 事务
/// 内同步设选区会被 WebKit 落点计算冲掉，实测两症状）。
fn place_caret_next_frame(input: web_sys::HtmlElement, tap_units: Option<u32>) {
    let cb = Closure::once_into_js(move || {
        let node: &web_sys::Node = input.unchecked_ref();
        if !node.is_connected() {
            return;
        }
        let Some(doc) = window().and_then(|w| w.document()) else {
            return;
        };
        let Ok(range) = doc.create_range() else {
            return;
        };
        let mut placed = false;
        if let Some(units) = tap_units {
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
        if let Some(sel) = window().and_then(|w| w.get_selection().ok().flatten()) {
            let _ = sel.remove_all_ranges();
            let _ = sel.add_range(&range);
        }
    });
    if let Some(w) = window() {
        let _ = w.request_animation_frame(cb.unchecked_ref());
    }
}

/// node 是否为 ancestor 本身或其后代。
fn within(node: &web_sys::Node, ancestor: &web_sys::Element) -> bool {
    let a: &web_sys::Node = ancestor.unchecked_ref();
    a.is_same_node(Some(node)) || a.contains(Some(node))
}

fn set_foreign_counter(n: u32) {
    if let Some(w) = window() {
        let wv: &wasm_bindgen::JsValue = w.as_ref();
        let _ = js_sys::Reflect::set(
            wv,
            &"__mnTitleGeomForeign".into(),
            &wasm_bindgen::JsValue::from_f64(n as f64),
        );
    }
}

fn set_geom_writes_counter(n: u32) {
    if let Some(w) = window() {
        let wv: &wasm_bindgen::JsValue = w.as_ref();
        let _ = js_sys::Reflect::set(
            wv,
            &"__mnTitleGeomWrites".into(),
            &wasm_bindgen::JsValue::from_f64(n as f64),
        );
    }
}

impl TitleController {
    /// 在静态壳挂载后调用：定位标题四元素、注册全部监听
    /// 与外来变更守卫、应用展示几何。元素缺失返回 None
    /// （壳未渲染完成时不应发生）。
    pub(super) fn attach(
        committed: String,
        on_commit: EventHandler<String>,
        on_session: EventHandler<bool>,
    ) -> Option<TitleController> {
        let doc = window()?.document()?;
        let input_el = doc.get_element_by_id("editor-title-text")?;
        let input: web_sys::HtmlElement = input_el.unchecked_into();
        let scroller = input.parent_element()?;
        let capsule = scroller.parent_element()?;
        let meta = capsule.query_selector(".editor-title-meta").ok()??;

        let inner = Rc::new(RefCell::new(Inner {
            input,
            scroller,
            capsule,
            meta,
            committed,
            on_commit,
            on_session,
            phase: Phase::Idle,
            fs: 14.0,
            is_long: false,
            is_overflow: false,
            layout_applied: false,
            applied_mode: (false, false),
            raf_id: None,
            raf_closure: None,
            sync_queued: false,
            sync_second: false,
            last_upd_log_ms: 0.0,
            last_upd_len: 0,
            logged_cw: 0.0,
            logged_sl: 0.0,
            tap_mark: None,
            self_write: Rc::new(Cell::new(false)),
            foreign: 0,
            geom_writes: 0,
            observer: None,
            observer_cb: None,
            listeners: Vec::new(),
        }));

        // caret 同步双 rAF 链闭包（attach 时建一次，detach
        // 时随 Inner 一并释放，打破 Rc 环）
        {
            let rc = inner.clone();
            let raf_closure = Closure::wrap(Box::new(move |_ts: f64| {
                if let Ok(mut g) = rc.try_borrow_mut() {
                    g.on_sync_frame();
                }
            }) as Box<dyn FnMut(f64)>);
            inner.borrow_mut().raf_closure = Some(raf_closure);
        }

        // —— 元素级监听（直接注册，不经桥/框架） ——
        listen(&inner, "focus", |g, _| g.on_focus());
        listen(&inner, "blur", |g, _| g.on_blur());
        listen(&inner, "compositionstart", |g, _| g.on_composition_start());
        listen(&inner, "compositionupdate", |g, _| g.on_composition_update());
        listen(&inner, "compositionend", |g, _| g.on_composition_end());
        listen(&inner, "input", |g, _| {
            if matches!(g.phase, Phase::Editing | Phase::Composing) {
                // 非组字与组字期共用同一落点：布局按实时全
                // 文同步 + caret 边距同步（原版 onInput 的
                // 两路在控制器内合流，值同源）。
                g.sync_layout();
                g.schedule_caret_sync();
            }
        });
        listen(&inner, "pointerdown", |g, e| {
            let pe: &web_sys::PointerEvent = e.unchecked_ref();
            let el: web_sys::Element = g.input.clone().unchecked_into();
            let full = g.committed.clone();
            let mark = tap_caret_target(&el, &full, pe.client_x() as f64, pe.client_y() as f64);
            g.tap_mark = mark.map(|m| (m, js_sys::Date::now()));
        });
        // keydown 单独注册：Enter/Esc 的 blur() 会同步派发
        // blur 事件再入监听，故判定与动作分两段借用。
        {
            let rc = inner.clone();
            let closure = Closure::wrap(Box::new(move |e: web_sys::Event| {
                let act = {
                    let Ok(g) = rc.try_borrow() else { return };
                    let ke: &web_sys::KeyboardEvent = e.unchecked_ref();
                    let composing = g.phase == Phase::Composing || ke.is_composing();
                    if composing || g.phase == Phase::Idle {
                        false
                    } else {
                        match ke.key().as_str() {
                            "Enter" => {
                                e.prevent_default();
                                true
                            }
                            "Escape" => true,
                            _ => false,
                        }
                    }
                };
                if act {
                    if let Ok(g) = rc.try_borrow() {
                        let el = g.input.clone();
                        drop(g);
                        el.blur();
                    }
                }
            }) as Box<dyn FnMut(web_sys::Event)>);
            let target: web_sys::EventTarget = inner.borrow().input.clone().unchecked_into();
            let _ = target.add_event_listener_with_callback(
                "keydown",
                closure.as_ref().unchecked_ref(),
            );
            inner.borrow_mut().listeners.push(Listener {
                target,
                kind: "keydown",
                closure,
            });
        }
        // —— 文档/视口级监听（caret 同步的其余触发源，与
        // 原版 selectionchange / resize / visualViewport
        // 同集；schedule_caret_sync 内部按会话态守卫） ——
        listen_doc(&inner, "selectionchange", |g| {
            g.schedule_caret_sync();
        });
        if let Some(vv) = window().and_then(|w| w.visual_viewport()) {
            let target: web_sys::EventTarget = vv.unchecked_into();
            listen_on(&inner, target.clone(), "resize", |g, _| {
                g.schedule_caret_sync();
            });
            listen_on(&inner, target, "scroll", |g, _| {
                g.schedule_caret_sync();
            });
        }
        if let Some(w) = window() {
            let target: web_sys::EventTarget = w.unchecked_into();
            listen_on(&inner, target, "resize", |g, _| {
                g.schedule_caret_sync();
            });
        }

        // —— 外来变更守卫 ——
        {
            let rc = inner.clone();
            let obs_cb = Closure::wrap(Box::new(move |records: js_sys::Array| {
                if let Ok(mut g) = rc.try_borrow_mut() {
                    for rec in records.iter() {
                        let rec: web_sys::MutationRecord = rec.unchecked_into();
                        guard_record(&mut g, &rec);
                    }
                }
            }) as Box<dyn FnMut(js_sys::Array)>);
            if let Ok(observer) = web_sys::MutationObserver::new(obs_cb.as_ref().unchecked_ref()) {
                let init = web_sys::MutationObserverInit::new();
                init.set_subtree(true);
                init.set_attributes(true);
                init.set_child_list(true);
                init.set_character_data(true);
                let filter = js_sys::Array::new();
                filter.push(&"style".into());
                filter.push(&"class".into());
                init.set_attribute_filter(&filter);
                let capsule_el = inner.borrow().capsule.clone();
                let target_node: &web_sys::Node = capsule_el.unchecked_ref();
                let _ = observer.observe_with_options(target_node, &init);
                let mut g = inner.borrow_mut();
                g.observer = Some(observer);
                g.observer_cb = Some(obs_cb);
            }
        }
        set_foreign_counter(0);
        set_geom_writes_counter(0);

        // 展示几何（挂载即应用，与会话收尾共用同一落点）
        inner.borrow_mut().apply_display();

        Some(TitleController { inner })
    }

    /// 壳卸载：摘全部监听、断开观察者、取消 rAF；会话未
    /// 收尾时先把当前文本按原文提交（编辑器整体关闭路径
    /// 已在 go_back 同步失焦提交，此处仅兜底）。
    pub(super) fn detach(&self) {
        let mut g = self.inner.borrow_mut();
        if matches!(g.phase, Phase::Editing | Phase::Composing) {
            let raw = g.text_now();
            if raw != g.committed {
                g.committed = raw.clone();
                g.on_commit.call(raw);
            }
            g.phase = Phase::Idle;
            g.on_session.call(false);
        }
        g.cancel_sync();
        if let Some(obs) = g.observer.take() {
            obs.disconnect();
        }
        g.observer_cb = None;
        let listeners = std::mem::take(&mut g.listeners);
        for l in listeners {
            let _ = l.target.remove_event_listener_with_callback(
                l.kind,
                l.closure.as_ref().unchecked_ref(),
            );
        }
        g.raf_closure = None;
        if let Some(w) = window() {
            let wv: &wasm_bindgen::JsValue = w.as_ref();
            let _ = js_sys::Reflect::set(wv, &"__mnTitleGeomForeign".into(), &wasm_bindgen::JsValue::NULL);
            let _ = js_sys::Reflect::set(wv, &"__mnTitleGeomWrites".into(), &wasm_bindgen::JsValue::NULL);
        }
    }
}

/// 在标题输入元素上注册监听（闭包随 Listener 存 Inner，
/// detach 时统一摘除）。
fn listen(
    inner: &Rc<RefCell<Inner>>,
    kind: &'static str,
    mut handler: impl FnMut(&mut Inner, &web_sys::Event) + 'static,
) {
    let target: web_sys::EventTarget = inner.borrow().input.clone().unchecked_into();
    listen_on(inner, target, kind, move |g, e| handler(g, e));
}

fn listen_doc(
    inner: &Rc<RefCell<Inner>>,
    kind: &'static str,
    handler: impl FnMut(&mut Inner) + 'static,
) {
    let Some(doc) = window().and_then(|w| w.document()) else {
        return;
    };
    let target: web_sys::EventTarget = doc.unchecked_into();
    let mut handler = handler;
    listen_on(inner, target, kind, move |g, _| handler(g));
}

fn listen_on(
    inner: &Rc<RefCell<Inner>>,
    target: web_sys::EventTarget,
    kind: &'static str,
    mut handler: impl FnMut(&mut Inner, &web_sys::Event) + 'static,
) {
    let rc = inner.clone();
    let closure = Closure::wrap(Box::new(move |e: web_sys::Event| {
        if let Ok(mut g) = rc.try_borrow_mut() {
            handler(&mut g, &e);
        }
    }) as Box<dyn FnMut(web_sys::Event)>);
    let _ = target.add_event_listener_with_callback(kind, closure.as_ref().unchecked_ref());
    inner.borrow_mut().listeners.push(Listener {
        target,
        kind,
        closure,
    });
}

/// 外来变更判定：自写标记内一律豁免；meta（框架渲染的
/// 文案节点）子树豁免；标题输入内的 childList/characterData
/// 在会话中是 IME/用户输入，豁免。其余属性变更与结构变
/// 更记 foreign。
fn guard_record(g: &mut Inner, rec: &web_sys::MutationRecord) {
    if g.self_write.get() {
        return;
    }
    let Some(target) = rec.target() else { return };
    if within(&target, &g.meta) {
        return;
    }
    let ty = rec.type_();
    if ty == "attributes" {
        let name = rec.attribute_name().unwrap_or_default();
        let val = target
            .unchecked_ref::<web_sys::Element>()
            .get_attribute(&name)
            .unwrap_or_default();
        g.foreign += 1;
        set_foreign_counter(g.foreign);
        diag::log(
            "EDIT",
            &format!(
                "titleGeom ph=foreign attr={name} val={}",
                &val[..val.len().min(60)]
            ),
        );
        return;
    }
    // childList / characterData
    let input_el: &web_sys::Element = g.input.unchecked_ref();
    if within(&target, input_el) && g.phase != Phase::Idle {
        return;
    }
    // characterData 的迟到记录：编辑删除会先改文本节点数
    // 据再将其脱离文档，投递时目标已不在输入子树内——会
    // 话期的脱离文本节点记录只能源于用户/IME 编辑（框架
    // 写标题走节点替换、记录挂在 input 元素上，不在此
    // 豁免面），按会话内编辑豁免；Idle 期不豁免。
    if ty == "characterData"
        && target.node_type() == 3
        && !target.is_connected()
        && g.phase != Phase::Idle
    {
        return;
    }
    g.foreign += 1;
    set_foreign_counter(g.foreign);
    diag::log(
        "EDIT",
        &format!("titleGeom ph=foreign attr={ty} val=node:{}", target.node_name()),
    );
}
