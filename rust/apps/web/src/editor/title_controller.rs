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
//! 几何定义化（取代旧 flex 涌现 + 类翻转台阶）：坞内不可
//! 见镜像元素量文本宽 textW、聚焦量一次 meta 宽 metaW，
//! target = clamp(max(metaW, textW) + 2·pad, 66, 184)；单
//! 一 rAF 循环先读后写、单帧单写，指数弹簧（τ≈90ms）驱动
//! 胶囊 width 与 padding-inline，亚像素吸附。字号聚焦按初
//! 始全文长度定格（>5 字 11px 否则 14px），会话内不切换。
//! cap 态（textW + 2·pad ≥ 184）会话内单向啮合：胶囊锁
//! 184、滚动区宽随内容盒（≈148）、padding-inline 16 接管
//! caret 边距、scrollLeft 只由 rAF 循环在写宽后按 caret 矩
//! 形校正一次（selectionchange 只置脏标记）；非 cap 态滚
//! 动区 overflow-x:hidden、scrollLeft 恒 0（帧循环强制归
//! 零——旧实现编辑态 scrollLeft 被原生 scroll-into-view 顶
//! 动后无人归零，正是「未回车内距不对称、回车后恢复」的
//! 主源）。标题面内距只许 padding-inline 单值简写，CSS 与
//! 本控制器写入皆然——左右对称是构造性质，不是量测结果。
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

const CAP_W: f64 = 184.0;
const MIN_W: f64 = 66.0;
const CARET_MARGIN: f64 = 16.0;
/// cap 啮合时滚动区的 caret 边距（padding-inline 接管）。
const CAP_PAD: f64 = 18.0;

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
    mirror: web_sys::Element,
    committed: String,
    on_commit: EventHandler<String>,
    on_session: EventHandler<bool>,
    phase: Phase,
    // —— 会话几何 ——
    /// 字号（聚焦按初始全文定格，会话内不变）
    fs: f64,
    /// 会话内距（长 18 / 短 20，聚焦定格）
    pad_session: f64,
    pad_cur: f64,
    /// 胶囊当前宽（弹簧状态）
    cw: f64,
    meta_w: f64,
    text_w: f64,
    cap: bool,
    caret_dirty: bool,
    // —— rAF 弹簧循环 ——
    raf_id: Option<i32>,
    raf_closure: Option<Closure<dyn FnMut(f64)>>,
    last_ts: f64,
    // —— Diag 节流/帧行基线 ——
    last_upd_log_ms: f64,
    last_upd_target: f64,
    logged_cw: f64,
    logged_sl: f64,
    // —— 点按落点记号（pointerdown 捕获、focus 消费）——
    tap_mark: Option<(usize, f64)>,
    // —— 外来变更守卫 ——
    self_write: Rc<Cell<bool>>,
    foreign: u32,
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
    /// caret/capR/sel）。
    fn geom_line(&self, ph: &str) -> String {
        let len = self.text_now().chars().count();
        let comp = if self.phase == Phase::Composing { 1 } else { 0 };
        let sl = scroll_left_f(&self.scroller);
        let caret = caret_client_x(&self.input)
            .map(|v| v.round() as i64)
            .unwrap_or(-1);
        let cap_r = self.capsule.get_bounding_client_rect().right().round() as i64;
        let sel = sel_offset_units(&self.input);
        format!(
            "titleGeom ph={ph} len={len} comp={comp} tw={:.1} cw={:.1} sl={:.1} fs={:.0} cap={} caret={caret} capR={cap_r} sel={sel}",
            self.text_w,
            self.cw,
            sl,
            self.fs,
            if self.cap { 1 } else { 0 },
        )
    }

    fn log_geom(&mut self, ph: &str) {
        let line = self.geom_line(ph);
        self.logged_cw = self.cw;
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

    /// 目标宽（cap 时恒 184）。+2px 构造余量：胶囊为
    /// border-box，定义宽含边框 2×0.5px，且滚动区/输入的
    /// 嵌套盒按整数像素截断（clientWidth 口径）再耗 ~1px
    /// ——不留余量时内容盒比 textW 窄约 2px，文本右溢、
    /// 左右留白差 2px（探针实测定位）。余量保证内容盒
    /// ≥ textW，居中不溢出、对称由构造恢复。
    fn target_w(&self) -> f64 {
        if self.cap {
            CAP_W
        } else {
            (self.meta_w.max(self.text_w) + 2.0 * self.pad_session + 2.0).clamp(MIN_W, CAP_W)
        }
    }

    fn kick(&mut self) {
        if self.raf_id.is_some() {
            return;
        }
        if !matches!(self.phase, Phase::Editing | Phase::Composing) {
            return;
        }
        if let (Some(w), Some(cb)) = (window(), self.raf_closure.as_ref()) {
            if let Ok(id) = w.request_animation_frame(cb.as_ref().unchecked_ref()) {
                self.raf_id = Some(id);
            }
        }
    }

    fn cancel_raf(&mut self) {
        if let Some(id) = self.raf_id.take() {
            if let Some(w) = window() {
                let _ = w.cancel_animation_frame(id);
            }
        }
    }

    /// rAF 弹簧帧：先读（镜像量宽、cap 判定、caret 矩形）
    /// 后写（胶囊 width + padding-inline、cap 的 scrollLeft
    /// 校正），单帧单写。
    fn frame(&mut self, ts: f64) {
        self.raf_id = None;
        if !matches!(self.phase, Phase::Editing | Phase::Composing) {
            return;
        }
        let dt = if self.last_ts > 0.0 {
            (ts - self.last_ts).clamp(1.0, 100.0)
        } else {
            16.7
        };
        self.last_ts = ts;

        // —— 读 ——
        let text = self.text_now();
        if self.mirror.text_content().as_deref() != Some(text.as_str()) {
            self.self_write_begin();
            self.mirror.set_text_content(Some(&text));
            self.self_write_end();
        }
        self.text_w = self.mirror.get_bounding_client_rect().width();
        let mut cap_flip = false;
        if !self.cap && self.text_w + 2.0 * self.pad_session >= CAP_W {
            self.cap = true;
            cap_flip = true;
        }
        let pad_target = if self.cap { CAP_PAD } else { self.pad_session };
        let target = self.target_w();
        let caret_x = if self.cap && self.caret_dirty {
            caret_client_x(&self.input)
        } else {
            None
        };

        // —— 弹簧 ——
        let alpha = 1.0 - (-dt / 90.0).exp();
        self.cw += (target - self.cw) * alpha;
        if (target - self.cw).abs() < 0.5 {
            self.cw = target;
        }
        self.pad_cur += (pad_target - self.pad_cur) * alpha;
        if (pad_target - self.pad_cur).abs() < 0.5 {
            self.pad_cur = pad_target;
        }

        // —— 写（单帧单写，自写标记） ——
        self.self_write_begin();
        let cap_style = style_of(&self.capsule);
        let _ = cap_style.set_property("width", &format!("{:.2}px", self.cw));
        let _ = cap_style.set_property("padding-inline", &format!("{:.2}px", self.pad_cur));
        if cap_flip {
            let scr = style_of(&self.scroller);
            let _ = scr.set_property("overflow-x", "auto");
            let _ = scr.set_property("padding-inline", "16px");
            let inp = self.input.style();
            let _ = inp.set_property("min-width", "max-content");
            let _ = inp.set_property("text-align", "left");
        }
        if self.cap {
            if self.caret_dirty {
                if let Some(cx) = caret_x {
                    let rect = self.scroller.get_bounding_client_rect();
                    let cur = scroll_left_f(&self.scroller);
                    let max_sl =
                        (self.scroller.scroll_width() - self.scroller.client_width()) as f64;
                    let mut sl = cur;
                    if cx < rect.left() + CARET_MARGIN {
                        sl = (cur - (rect.left() + CARET_MARGIN - cx)).max(0.0);
                    } else if cx > rect.right() - CARET_MARGIN {
                        sl = (cur + (cx - rect.right() + CARET_MARGIN)).min(max_sl.max(0.0));
                    }
                    if (sl - cur).abs() > 0.01 {
                        set_scroll_left_f(&self.scroller, sl);
                    }
                }
            }
        } else {
            // 非 cap 态 scrollLeft 恒 0：原生 scroll-into-view
            // 顶动后由帧循环归零（不对称内距的主源封堵）。
            let cur = scroll_left_f(&self.scroller);
            if cur != 0.0 {
                set_scroll_left_f(&self.scroller, 0.0);
            }
        }
        self.self_write_end();
        self.caret_dirty = false;

        if cap_flip {
            self.log_geom("cap");
        }
        // 帧行：cw 变化 ≥1px 或 sl 变化才记（避免静止期刷屏）
        let sl_now = scroll_left_f(&self.scroller);
        if (self.cw - self.logged_cw).abs() >= 1.0 || (sl_now - self.logged_sl).abs() > 0.01 {
            self.log_geom("frame");
        }

        let settled = (target - self.cw).abs() < 0.01 && (pad_target - self.pad_cur).abs() < 0.01;
        if !settled {
            self.kick();
        }
    }

    /// 展示态几何（挂载时与会话收尾时）：长标题（展示串
    /// >5 字）以 11px 折行形态呈现、胶囊内距 18，其余全归
    /// CSS 基础值。与旧类驱动（.long/.is-long）的计算口径
    /// 逐项等价，但写者只有本控制器。
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
            let _ = style_of(&self.capsule).set_property("padding-inline", "18px");
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

        // —— 字号/内距会话冻结（按初始全文长度定格） ——
        let n = full.chars().count();
        self.fs = if n > 5 { 11.0 } else { 14.0 };
        self.pad_session = if n > 5 { CAP_PAD } else { 20.0 };
        self.pad_cur = self.pad_session;
        self.cap = false;
        self.caret_dirty = false;

        // —— 会话样式（自写） ——
        self.self_write_begin();
        let inp = self.input.style();
        let _ = inp.set_property("font-size", &format!("{:.0}px", self.fs));
        let _ = inp.set_property("white-space", "nowrap");
        let _ = inp.set_property("word-break", "normal");
        let _ = inp.set_property("text-align", "center");
        let _ = inp.set_property("max-height", "none");
        let _ = inp.remove_property("min-width");
        let scr = style_of(&self.scroller);
        let _ = scr.set_property("overflow-x", "hidden");
        let _ = scr.set_property("padding-inline", "0px");
        set_scroll_left_f(&self.scroller, 0.0);
        self.self_write_end();

        // —— 量测：meta 一次、镜像就位、弹簧起点 = 当前宽 ——
        self.meta_w = measure_meta_w(&self.meta);
        self.self_write_begin();
        let mir = style_of(&self.mirror);
        let _ = mir.set_property("font-size", &format!("{:.0}px", self.fs));
        self.mirror.set_text_content(Some(&full));
        self.self_write_end();
        self.text_w = self.mirror.get_bounding_client_rect().width();
        let rect_w = self.capsule.get_bounding_client_rect().width();
        self.cw = if rect_w > 0.0 {
            rect_w
        } else {
            self.target_w()
        };
        // 涌现宽即刻冻结为定义宽（同值写入、无视觉跳变），
        // 之后由弹簧驱动趋近 target。
        self.self_write_begin();
        let cap_style = style_of(&self.capsule);
        let _ = cap_style.set_property("width", &format!("{:.2}px", self.cw));
        let _ = cap_style.set_property("padding-inline", &format!("{:.2}px", self.pad_cur));
        self.self_write_end();
        self.last_ts = 0.0;

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
        self.kick();
    }

    fn on_blur(&mut self) {
        if self.phase == Phase::Idle {
            return;
        }
        // 组字中失焦（罕见）：compositionend 通常先行，此处
        // 按已落定文本收尾（迟到 compositionend 在 Idle 被
        // 守卫忽略，不回灌下一会话）。
        self.phase = Phase::Committing;
        self.cancel_raf();
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
            self.log_geom("compstart");
            self.kick();
        }
    }

    fn on_composition_update(&mut self) {
        if self.phase != Phase::Composing {
            return;
        }
        self.kick();
        // 节流：≥50ms 或 target 变化 ≥0.5px 才记（cap 翻
        // 转另有 ph=cap 帧行，不在此重复）
        let now = js_sys::Date::now();
        let target = self.target_w();
        if now - self.last_upd_log_ms >= 50.0 || (target - self.last_upd_target).abs() >= 0.5 {
            self.last_upd_log_ms = now;
            self.last_upd_target = target;
            self.log_geom("compupdate");
        }
    }

    fn on_composition_end(&mut self) {
        match self.phase {
            Phase::Composing | Phase::Editing => {
                self.phase = Phase::Editing;
                self.commit_raw("compend");
                self.kick();
            }
            _ => {}
        }
    }
}

/// meta 文案的文本宽（Range 量内容盒外文本矩形；坞滚动态
/// meta 被 CSS 隐藏时为 0，target 只由 textW 决定）。
fn measure_meta_w(meta: &web_sys::Element) -> f64 {
    let Some(doc) = window().and_then(|w| w.document()) else {
        return 0.0;
    };
    let Ok(range) = doc.create_range() else {
        return 0.0;
    };
    let node: &web_sys::Node = meta.unchecked_ref();
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

impl TitleController {
    /// 在静态壳挂载后调用：定位标题四元素、建镜像、注册
    /// 全部监听与外来变更守卫、应用展示几何。元素缺失返回
    /// None（壳未渲染完成时不应发生）。
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

        // 镜像测量元素（坞内不可见，同字体/字距/字重、
        // nowrap；fixed 定位不占布局）
        let mirror = doc.create_element("span").ok()?;
        let _ = mirror.set_attribute(
            "style",
            "position:fixed;left:0;top:-200px;visibility:hidden;pointer-events:none;white-space:nowrap;font-weight:600;letter-spacing:-0.2px;",
        );
        let _ = capsule.append_child(&mirror);

        let inner = Rc::new(RefCell::new(Inner {
            input,
            scroller,
            capsule,
            meta,
            mirror,
            committed,
            on_commit,
            on_session,
            phase: Phase::Idle,
            fs: 14.0,
            pad_session: 20.0,
            pad_cur: 20.0,
            cw: 0.0,
            meta_w: 0.0,
            text_w: 0.0,
            cap: false,
            caret_dirty: false,
            raf_id: None,
            raf_closure: None,
            last_ts: 0.0,
            last_upd_log_ms: 0.0,
            last_upd_target: 0.0,
            logged_cw: 0.0,
            logged_sl: 0.0,
            tap_mark: None,
            self_write: Rc::new(Cell::new(false)),
            foreign: 0,
            observer: None,
            observer_cb: None,
            listeners: Vec::new(),
        }));

        // rAF 弹簧循环闭包（attach 时建一次，detach 时随
        // Inner 一并释放，打破 Rc 环）
        {
            let rc = inner.clone();
            let raf_closure = Closure::wrap(Box::new(move |ts: f64| {
                if let Ok(mut g) = rc.try_borrow_mut() {
                    g.frame(ts);
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
                g.kick();
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
        // —— 文档/视口级监听（caret 脏标记与几何重踢） ——
        listen_doc(&inner, "selectionchange", |g| {
            if matches!(g.phase, Phase::Editing | Phase::Composing) {
                g.caret_dirty = true;
                g.kick();
            }
        });
        if let Some(vv) = window().and_then(|w| w.visual_viewport()) {
            let target: web_sys::EventTarget = vv.unchecked_into();
            listen_on(&inner, target.clone(), "resize", |g, _| {
                if matches!(g.phase, Phase::Editing | Phase::Composing) {
                    g.caret_dirty = true;
                    g.kick();
                }
            });
            listen_on(&inner, target, "scroll", |g, _| {
                if matches!(g.phase, Phase::Editing | Phase::Composing) {
                    g.caret_dirty = true;
                    g.kick();
                }
            });
        }
        if let Some(w) = window() {
            let target: web_sys::EventTarget = w.unchecked_into();
            listen_on(&inner, target, "resize", |g, _| {
                if matches!(g.phase, Phase::Editing | Phase::Composing) {
                    g.caret_dirty = true;
                    g.kick();
                }
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
        g.cancel_raf();
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

/// 外来变更判定：自写标记内一律豁免；镜像（控制器自有测
/// 量元素）与 meta（框架渲染的文案节点）子树豁免；标题输
/// 入内的 childList/characterData 在会话中是 IME/用户输
/// 入，豁免。其余属性变更与结构变更记 foreign。
fn guard_record(g: &mut Inner, rec: &web_sys::MutationRecord) {
    if g.self_write.get() {
        return;
    }
    let Some(target) = rec.target() else { return };
    if within(&target, &g.mirror) || within(&target, &g.meta) {
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
