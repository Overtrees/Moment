//! 标题编辑会话的唯一所有者（标题胶囊按用户口径重构）：
//! 监听以 web-sys 直接注册在标题 input 上，不经 JS 桥、
//! 不经 Dioxus 合成事件；编辑会话内文本、胶囊宽与提交
//! 全归本控制器，框架渲染不碰标题子树（静态壳见
//! title.rs 的 TitleCapsule）。
//!
//! 元素形态（用户 2026-11-23 裁定，标题胶囊豁免原版对
//! 齐）：原生 <input type="text">。上一代 contenteditable
//! + 独立 scroller 在 WebKit 下把 marked（组字）区间作
//! 选区式绘制、组字串首尾各出一条竖条且起始缘随内部横
//! 滚驻留胶囊中段（冻结构建与原版闩锁构建真机两度再
//! 现）；input 的组字走平台文本系统、只有一个光标，双
//! 竖条从构造上不存在。随之我方对标题元素 scrollLeft
//! 的写入归零——输入内部滚动全交平台；旧几何机器
//! （sync_layout 闩锁、边距 caret 同步、scroller、内容
//! 驱动定宽、弹簧、组字冻结）整段删除，不叠层共存。
//!
//! 对称居中是构造性质、非运行时校正：胶囊内距只由 CSS
//! 类规则的 padding 单值给出（输入态与展示态同值，控
//! 制器永不写内距）；input 宽 = 胶囊内容盒、
//! text-align:center，文本装得下时左右留白天然相等；
//! 胶囊在坞内 flex 居中，变宽以中心为锚两边同步展开。
//! 编辑态与展示态同字号（14px 恒定，无闩锁翻转）、同
//! 内距、同一定宽公式。
//!
//! 宽度规则（sync_width，唯一写者、只写胶囊 width）：
//! 胶囊宽 = max(实时全文宽, meta 宽) + 左右内距 + 边
//! 框，钳 [66, 坞内可用宽]。实时全文含组字串：组字期
//! 以 compositionupdate 的 data 按组字区间拼回（value
//! 对组字串的反映随时序分两态——input 事件到达前仍是
//! 原选区、到达后已含上一组字串，拼接的跳过段由
//! comp_reflected 分流，见 live_text）；全文宽由离屏镜像 span 以
//! 与 input 相同的字体走引擎实测；可用宽运行时从坞布
//! 局实测（坞内容宽，行模式下扣头像等兄弟元素与间
//! 隙，不写死设备数值）。写入走胶囊 CSS 的
//! transition: width，逐字输入时宽度平滑跟随、不阶梯
//! 跳动；文本超出可用宽后胶囊停在可用宽，溢出滚动与
//! 光标可见性由平台接管。
//!
//! 状态机：Idle → Editing ⇄ Composing → Committing →
//! Idle。文本写回时机：compositionend（原文）、blur
//! （trim、空回退「无标题」）、Enter（失焦走 blur 落
//! 定）；Esc 还原会话起始文本后失焦、不提交改动（旧
//! 控制器 Esc 仅失焦、按当前文本提交，与本口径不符，
//! 本代按规格落实还原）。逐键输入只驱动定宽，不写回。
//!
//! Diag（titleGeom）：事件行（focus/input 节流/compstart
//! /compupdate 节流/compend/commit/blur）+ MutationObserver
//! 外来变更守卫：控制器自写打 selfWrite 标记，非自写的
//! 属性/结构变更记 ph=foreign 并累计到
//! window.__mnTitleGeomForeign。字段口径：len=实时全文
//! UTF-16 长（组字期含组字串）、tw=镜像实测全文宽、
//! cw=胶囊 rect 宽、wsd=左右留白实测差（input rect 在
//! 胶囊内容盒内的偏移与居中量合成）、sl=平台自身的
//! input.scrollLeft（只读观测，我方零写入）、fs=恒 14、
//! sel=选区 UTF-16 位移（-1 为不在标题内）。

use super::*;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use wasm_bindgen::closure::Closure;

/// 胶囊最小宽（与 CSS 类规则的 min-width: 66px 同值；
/// 定宽公式的下限钳制）。
const MIN_CAPSULE_W: f64 = 66.0;

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
    input: web_sys::HtmlInputElement,
    capsule: web_sys::Element,
    meta: web_sys::Element,
    dock: web_sys::Element,
    /// 离屏镜像 span（挂 body，与 input 同字体，引擎实测
    /// 全文宽；attach 建、detach 摘）
    mirror: web_sys::HtmlElement,
    committed: String,
    /// 会话起始文本（Esc 还原的回退点，聚焦时快照）
    session_base: String,
    on_commit: EventHandler<String>,
    on_session: EventHandler<bool>,
    phase: Phase,
    // —— 组字区间（组字期 value 不含 marked 文本，实时
    // 全文靠它与 comp_data 拼回）——
    /// 组字区间在 value 内的 UTF-16 [start, end)（组字
    /// 开始时的选区），非组字期为 None
    comp_range: Option<(usize, usize)>,
    /// 当前组字串（compositionupdate 的 data 全量）
    comp_data: String,
    /// value 是否已反映当前组字串（组字期 input 事件到
    /// 达即置位）：实时全文拼接时据此决定 value 里要跳
    /// 过的段是原选区还是已落值的上一组字串
    comp_reflected: bool,
    // —— Diag 节流基线 ——
    last_upd_log_ms: f64,
    last_upd_len: usize,
    // —— 点按落点记号（pointerdown 捕获、focus 消费）——
    /// 全文 char 位 + 捕获时刻（ms）
    tap_mark: Option<(usize, f64)>,
    /// 首次定宽已完成（首写免 transition 防挂载跳变）
    width_primed: bool,
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

/// 元素内联样式（web-sys 的 style() 只绑在 HtmlElement
/// 上，胶囊为 div，统一经此取）。
fn style_of(el: &web_sys::Element) -> web_sys::CssStyleDeclaration {
    el.unchecked_ref::<web_sys::HtmlElement>().style()
}

/// 计算样式的 px 数值（"20px" → 20，缺失/不可解析 → 0）。
/// 内距一律读逻辑属性 padding-inline-start/end（量的是
/// 类规则 padding 单值在行内的两端，与 verify 标题门禁
/// 「禁物理分写字面」口径相容——此处是测量、非写入）。
fn computed_px(el: &web_sys::Element, prop: &str) -> f64 {
    let Some(w) = window() else { return 0.0 };
    let Ok(Some(cs)) = w.get_computed_style(el) else {
        return 0.0;
    };
    cs.get_property_value(prop)
        .ok()
        .and_then(|v| v.trim().trim_end_matches("px").parse::<f64>().ok())
        .unwrap_or(0.0)
}

/// 字符串的 UTF-16 单位数（与 JS .length / input 选区
/// 下标同口径）。
fn utf16_len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// 按 UTF-16 单位下标切子串（下标钳到字符边界与串长）。
fn slice_by_utf16(s: &str, start: usize, end: usize) -> String {
    let mut out = String::new();
    let mut acc = 0usize;
    for ch in s.chars() {
        let l = ch.len_utf16();
        if acc >= start && acc + l <= end {
            out.push(ch);
        }
        acc += l;
    }
    out
}

/// 第 char_idx 个字符之前的 UTF-16 单位数（点按落点由
/// char 位换算 input 选区下标用）。
fn utf16_of_char(s: &str, char_idx: usize) -> usize {
    s.chars().take(char_idx).map(|c| c.len_utf16()).sum()
}

/// 镜像实测文本宽：把文本放进离屏镜像 span（与 input
/// 同字体），读布局宽（引擎实测，含字距）。
fn measure_text(mirror: &web_sys::HtmlElement, text: &str) -> f64 {
    let node: &web_sys::Node = mirror.unchecked_ref();
    if node.text_content().as_deref() != Some(text) {
        node.set_text_content(Some(text));
    }
    mirror.get_bounding_client_rect().width()
}

/// meta 行的文本宽（Range 量内容矩形；display:none 时
/// 为 0，滚动态自动不计）。
fn meta_text_w(meta: &web_sys::Element) -> f64 {
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

/// 点按落点捕获（调优，用户 2026-11-22 拍板，口径沿旧
/// 代：截断标题点按落点映射到全文对应处，键盘/程序聚
/// 焦仍落文末）：input 的文本在影子树内、caretRange-
/// FromPoint 命中不到，改几何法——显示串居中于 input，
/// 以镜像逐前缀实测宽把点按 x 换算成最近字符边界，再
/// 按截断规则映射：落在可见前缀（前 10 字）→ 同位；落
/// 在省略号上/之后 → 全文末尾。仅截断形态（全文 >10
/// 字、当前值确为「前缀 + …」）适用；未截断时原生落点
/// 本就准确，返回 None 不干预。返回值是全文 char 位。
fn tap_caret_target(
    input: &web_sys::HtmlInputElement,
    mirror: &web_sys::HtmlElement,
    full: &str,
    x: f64,
) -> Option<usize> {
    let full_len = full.chars().count();
    if full_len <= 10 || full.is_empty() {
        return None;
    }
    let disp = input.value();
    if disp.chars().count() != 11 || !disp.ends_with('…') {
        return None;
    }
    let prefix: String = disp.chars().take(10).collect();
    if !full.starts_with(&prefix) {
        return None;
    }
    let rect = input.get_bounding_client_rect();
    let disp_w = measure_text(mirror, &disp);
    // 显示串居中：文本左缘 = input 左缘 + 两侧留白之半
    let start_x = rect.left() + (rect.width() - disp_w) / 2.0;
    let rel = x - start_x;
    if rel <= 0.0 {
        return Some(0);
    }
    // 逐前缀实测宽找最近字符边界（前缀宽单调，越过 rel
    // 且距离变大即可停）
    let chars: Vec<char> = disp.chars().collect();
    let mut best = 0usize;
    let mut best_d = rel.abs();
    for b in 1..=chars.len() {
        let pfx: String = chars[..b].iter().collect();
        let w = measure_text(mirror, &pfx);
        let d = (w - rel).abs();
        if d < best_d {
            best_d = d;
            best = b;
        } else if w > rel {
            break;
        }
    }
    Some(if best <= 10 { best } else { full_len })
}

impl Inner {
    /// 实时全文：非组字期就是 input.value；组字期按组字
    /// 区间把组字串拼回（前缀 + 组字串 + 后缀）。value
    /// 里要跳过的段随平台时序变：组字期 input 事件未到
    /// 时 value 仍是原选区 [a, b)；input 事件到达后
    /// value 在 a 处已含上一组字串（长 = comp_data），
    /// 跳过段随之换算——两口径由 comp_reflected 分流，
    /// 拼接结果恒为当前实时全文。
    fn live_text(&self) -> String {
        self.live_text_impl(None)
    }

    /// new_data 给定时以它为当前组字串（compositionupdate
    /// 落点在 comp_data 赋值前先算实时全文用）。
    fn live_text_impl(&self, new_data: Option<&str>) -> String {
        let v = self.input.value();
        if self.phase == Phase::Composing {
            if let Some((a, b)) = self.comp_range {
                let data = new_data.unwrap_or(&self.comp_data);
                let skip = if self.comp_reflected {
                    a + utf16_len(&self.comp_data)
                } else {
                    b
                };
                let mut s = slice_by_utf16(&v, 0, a);
                s.push_str(data);
                s.push_str(&slice_by_utf16(&v, skip, usize::MAX));
                return s;
            }
        }
        v
    }

    /// Diag titleGeom 行（字段口径见模块注）：len/tw 为
    /// 实时全文（组字期含组字串）的 UTF-16 长与镜像实测
    /// 宽；wsd 为左右留白实测差——input rect 相对胶囊内
    /// 容盒的偏移与「内容盒宽 − 全文宽」的居中余量合成
    /// （文本装得下时构造上恒 0，偏差只来自 input 未填
    /// 满内容盒或文本被钳制溢出）；sl 为平台自身的
    /// input.scrollLeft（只读）；sel 为选区 UTF-16 位移。
    fn geom_line(&self, ph: &str) -> String {
        let live = self.live_text();
        let len = utf16_len(&live);
        let comp = if self.phase == Phase::Composing { 1 } else { 0 };
        let tw = measure_text(&self.mirror, &live);
        let cap_r = self.capsule.get_bounding_client_rect();
        let in_r = self.input.get_bounding_client_rect();
        let content_l = cap_r.left()
            + computed_px(&self.capsule, "border-left-width")
            + computed_px(&self.capsule, "padding-inline-start");
        let content_r = cap_r.right()
            - computed_px(&self.capsule, "border-right-width")
            - computed_px(&self.capsule, "padding-inline-end");
        let slack = ((in_r.width() - tw).max(0.0)) / 2.0;
        let gap_l = (in_r.left() - content_l) + slack;
        let gap_r = (content_r - in_r.right()) + slack;
        let sel = self
            .input
            .selection_start()
            .ok()
            .flatten()
            .map(|v| v as i64)
            .unwrap_or(-1);
        format!(
            "titleGeom ph={ph} len={len} comp={comp} tw={:.1} cw={:.1} wsd={:.1} fs=14 sl={} sel={sel}",
            tw,
            cap_r.width(),
            gap_l - gap_r,
            self.input.scroll_left(),
        )
    }

    fn log_geom(&mut self, ph: &str) {
        let line = self.geom_line(ph);
        diag::log("EDIT", &line);
    }

    /// input / compupdate 的节流记行（≥50ms 或实时长度
    /// 变化才记，避免逐键刷屏）。
    fn maybe_log_upd(&mut self, ph: &str) {
        let now = js_sys::Date::now();
        let len = utf16_len(&self.live_text());
        if now - self.last_upd_log_ms >= 50.0 || len != self.last_upd_len {
            self.last_upd_log_ms = now;
            self.last_upd_len = len;
            self.log_geom(ph);
        }
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

    /// 坞内可用宽（运行时实测）：坞内容盒宽；行模式
    /// （.scrolled，坞内 flex-direction: row）下再扣其
    /// 他可见兄弟元素（头像钮等）的宽与相邻间隙。列模
    /// 式下胶囊独占一行、不扣。禁止写死设备数值——坞宽
    /// 本身已由 CSS 的 left/right 内缩给出。
    fn avail_width(&self) -> f64 {
        let dock = &self.dock;
        let mut avail = dock.client_width() as f64
            - computed_px(dock, "padding-inline-start")
            - computed_px(dock, "padding-inline-end");
        let row_mode = window()
            .and_then(|w| w.get_computed_style(dock).ok().flatten())
            .and_then(|cs| cs.get_property_value("flex-direction").ok())
            .map(|v| v.trim() == "row")
            .unwrap_or(false);
        if row_mode {
            let gap = computed_px(dock, "column-gap");
            let kids = dock.child_nodes();
            let mut sibs = 0.0;
            for i in 0..kids.length() {
                let Some(k_node) = kids.get(i) else { continue };
                if k_node.node_type() != 1
                    || k_node.is_same_node(Some(self.capsule.unchecked_ref()))
                {
                    continue;
                }
                let k: &web_sys::Element = k_node.unchecked_ref();
                let w = k.get_bounding_client_rect().width();
                if w > 0.0 {
                    avail -= w;
                    sibs += 1.0;
                }
            }
            avail -= gap * sibs;
        }
        avail
    }

    /// 定宽（胶囊 width 的唯一写者）：宽 = max(实时全文
    /// 宽, meta 宽) + 左右内距 + 边框（内距/边框按
    /// computed 实测，与 CSS 单值口径自动一致），钳
    /// [MIN_CAPSULE_W, 可用宽]。写入走 CSS 的 width
    /// transition 弹性跟随；挂载首写免 transition（从
    /// auto 起步不跳）。目标未变（±0.1）不重写。
    fn sync_width(&mut self) {
        let live = self.live_text();
        self.sync_width_for(&live);
    }

    /// sync_width 的定宽主体（live 为已算好的实时全文，
    /// 组字落点先算后赋 comp_data 时直接传）。
    fn sync_width_for(&mut self, live: &str) {
        let tw = measure_text(&self.mirror, live);
        let content = tw.max(meta_text_w(&self.meta));
        let pad_x = computed_px(&self.capsule, "padding-inline-start")
            + computed_px(&self.capsule, "padding-inline-end");
        let border_x = computed_px(&self.capsule, "border-left-width")
            + computed_px(&self.capsule, "border-right-width");
        let avail = self.avail_width().max(MIN_CAPSULE_W);
        let target = (content + pad_x + border_x).clamp(MIN_CAPSULE_W, avail);
        let style = style_of(&self.capsule);
        let cur = style
            .get_property_value("width")
            .ok()
            .and_then(|v| v.trim().trim_end_matches("px").parse::<f64>().ok());
        if let Some(c) = cur {
            if (c - target).abs() <= 0.1 {
                return;
            }
        }
        self.self_write_begin();
        if !self.width_primed {
            self.width_primed = true;
            let _ = style.set_property("transition", "none");
            let _ = style.set_property("width", &format!("{target:.1}px"));
            // 强制同步布局 flush 后再恢复 CSS transition，
            // 后续变宽才走弹性跟随
            let _ = self.capsule.get_bounding_client_rect();
            let _ = style.remove_property("transition");
        } else {
            let _ = style.set_property("width", &format!("{target:.1}px"));
        }
        self.self_write_end();
    }

    /// 文本提交（compositionend 口径）：原文直写（不 trim，
    /// 与旧桥 compositionend 上报等价），变化才经 on_commit
    /// 交 Editor 置信号 + persist。compend 时 value 已含
    /// 落定文本，直接读。
    fn commit_raw(&mut self, why: &str) {
        let raw = self.input.value();
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
        // Esc 还原点 = 会话起始的已提交文本
        self.session_base = self.committed.clone();
        let full = self.committed.clone();

        // 展示值（可能截断/占位）→ 全文：input 的 value
        // 即编辑全文，截断只在 Idle 呈现。value 特性归控
        // 制器就地读写，框架不托管、不回灌。
        let replaced = self.input.value() != full;
        if replaced {
            self.input.set_value(&full);
        }
        self.sync_width();

        // —— 光标落位（rAF 延后，与旧口径同时序：focus 事
        // 务内同步设选区会被 WebKit 落点计算冲掉）：点按
        // 记号优先落映射位；其次换值时落文末；未换值且无
        // 记号（短标题点按）不干预原生落点 ——
        let tap_units = match self.tap_mark.take() {
            Some((m, ts)) if js_sys::Date::now() - ts <= 2000.0 => {
                diag::log("EDIT", &format!("title caret tap -> {m}"));
                Some(utf16_of_char(&full, m) as u32)
            }
            _ => None,
        };
        if tap_units.is_some() || replaced {
            place_caret_next_frame(self.input.clone(), tap_units);
        }
        self.log_geom("focus");
    }

    fn on_blur(&mut self) {
        if self.phase == Phase::Idle {
            return;
        }
        // 组字中失焦（罕见）：compositionend 通常先行，此
        // 处按 value 现值收尾（迟到 compositionend 在
        // Idle 被守卫忽略，不回灌下一会话）。
        self.phase = Phase::Committing;
        self.comp_range = None;
        self.comp_data.clear();
        self.comp_reflected = false;
        self.tap_mark = None;

        // —— 同步提交（旧 onblur 已验证口径逐项等价）：全
        // 文 trim、空回退「无标题」、写信号 + persist ——
        let raw = self.input.value();
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

        // —— 回展示值 + 同一公式定宽：展示态与编辑态同公
        // 式、同内距、同字号，对称居中不因状态切换改变；
        // 控制器只写胶囊 width 一项 inline、两态共用，
        // 无会话样式需摘 ——
        let disp = super::title::display_title_of(&committed);
        if self.input.value() != disp {
            self.input.set_value(&disp);
        }
        self.sync_width();

        self.phase = Phase::Idle;
        self.on_session.call(false);
        self.log_geom("blur");
    }

    fn on_composition_start(&mut self) {
        if self.phase == Phase::Editing {
            self.phase = Phase::Composing;
            // 记组字区间（此刻选区在 value 内的 UTF-16
            // [start, end)）：组字期 value 不含 marked 文
            // 本，实时全文靠它与 comp_data 拼回（见
            // live_text）。
            let a = self.input.selection_start().ok().flatten().unwrap_or(0) as usize;
            let b = self.input.selection_end().ok().flatten().unwrap_or(0) as usize;
            self.comp_range = Some((a, b.max(a)));
            self.comp_data.clear();
            self.comp_reflected = false;
            self.log_geom("compstart");
        }
    }

    fn on_composition_update(&mut self, data: String) {
        if self.phase != Phase::Composing {
            return;
        }
        // 组字串更新即按含组字串的实时全文定宽：胶囊随
        // 组字增长弹性展开，组字串全程在流内、无内部横
        // 滚可言（平台在 input 内处理 marked 呈现）。实
        // 时全文须在 comp_data 换新前算（拼接的跳过段按
        // 旧组字串计）。
        let live = self.live_text_impl(Some(&data));
        self.comp_data = data;
        self.sync_width_for(&live);
        let now = js_sys::Date::now();
        let len = utf16_len(&live);
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
                self.comp_range = None;
                self.comp_data.clear();
                self.comp_reflected = false;
                // value 已含落定文本：提交原文 + 按落定全
                // 文定宽收敛。
                self.commit_raw("compend");
                self.sync_width();
            }
            _ => {}
        }
    }
}

/// 换值后的光标落位（rAF 一帧）：点按记号给定时落映射
/// 位（UTF-16 单位）、否则文末。与旧口径同时序（focus
/// 事务内同步设选区会被 WebKit 落点计算冲掉，实测两症
/// 状）。帧内元素已失焦/已卸载则不动作。
fn place_caret_next_frame(input: web_sys::HtmlInputElement, tap_units: Option<u32>) {
    let cb = Closure::once_into_js(move || {
        let node: &web_sys::Node = input.unchecked_ref();
        if !node.is_connected() {
            return;
        }
        let Some(doc) = window().and_then(|w| w.document()) else {
            return;
        };
        let el: &web_sys::Element = input.unchecked_ref();
        if doc.active_element().as_ref() != Some(el) {
            return;
        }
        let len = utf16_len(&input.value()) as u32;
        let at = tap_units.map(|u| u.min(len)).unwrap_or(len);
        let _ = input.set_selection_range(at, at);
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
    /// 在静态壳挂载后调用：定位标题元素、建离屏镜像、注
    /// 册全部监听与外来变更守卫、应用展示定宽。元素缺失
    /// 返回 None（壳未渲染完成时不应发生）。
    pub(super) fn attach(
        committed: String,
        on_commit: EventHandler<String>,
        on_session: EventHandler<bool>,
    ) -> Option<TitleController> {
        let doc = window()?.document()?;
        let input_el = doc.get_element_by_id("editor-title-text")?;

        // —— 离屏镜像 span（挂 body）：与 input 同字体，
        // 全文宽走引擎实测。字体两态恒定，attach 时从
        // input 的 computed 拷一次即可 ——
        let mirror: web_sys::HtmlElement = doc.create_element("span").ok()?.unchecked_into();
        {
            let ms = mirror.style();
            let _ = ms.set_property("position", "fixed");
            let _ = ms.set_property("left", "-9999px");
            let _ = ms.set_property("top", "0");
            let _ = ms.set_property("visibility", "hidden");
            let _ = ms.set_property("white-space", "nowrap");
            let _ = ms.set_property("pointer-events", "none");
            if let Some(w) = window() {
                if let Ok(Some(cs)) = w.get_computed_style(&input_el) {
                    for prop in [
                        "font-family",
                        "font-size",
                        "font-weight",
                        "font-style",
                        "letter-spacing",
                    ] {
                        if let Ok(v) = cs.get_property_value(prop) {
                            let _ = ms.set_property(prop, &v);
                        }
                    }
                }
            }
            let _ = mirror.set_attribute("aria-hidden", "true");
            if let Some(body) = doc.body() {
                let body_node: &web_sys::Node = body.unchecked_ref();
                let m_node: &web_sys::Node = mirror.unchecked_ref();
                let _ = body_node.append_child(m_node);
            }
        }

        let input: web_sys::HtmlInputElement = input_el.unchecked_into();
        // 初始显示值在此写入（壳不以 value 属性渲染
        // input——框架重执行会按 vnode 快照重写 value，
        // 见 title.rs 模块注）：按显示口径（空→「无标
        // 题」、超 10 字截断）一次写好，其后归控制器。
        input.set_value(&super::title::display_title_of(&committed));
        let capsule = input.parent_element()?;
        let dock = capsule.parent_element()?;
        let meta = capsule.query_selector(".editor-title-meta").ok()??;

        let inner = Rc::new(RefCell::new(Inner {
            input,
            capsule,
            meta,
            dock,
            mirror,
            session_base: committed.clone(),
            committed,
            on_commit,
            on_session,
            phase: Phase::Idle,
            comp_range: None,
            comp_data: String::new(),
            comp_reflected: false,
            last_upd_log_ms: 0.0,
            last_upd_len: 0,
            tap_mark: None,
            width_primed: false,
            self_write: Rc::new(Cell::new(false)),
            foreign: 0,
            observer: None,
            observer_cb: None,
            listeners: Vec::new(),
        }));

        // —— 元素级监听（直接注册，不经桥/框架） ——
        listen(&inner, "focus", |g, _| g.on_focus());
        listen(&inner, "blur", |g, _| g.on_blur());
        listen(&inner, "compositionstart", |g, _| g.on_composition_start());
        listen(&inner, "compositionupdate", |g, e| {
            let data = e
                .unchecked_ref::<web_sys::CompositionEvent>()
                .data()
                .unwrap_or_default();
            g.on_composition_update(data);
        });
        listen(&inner, "compositionend", |g, _| g.on_composition_end());
        listen(&inner, "input", |g, _| {
            // 组字期的 input 事件只作「value 已反映组字
            // 串」的时序标记（定宽已由 compositionupdate
            // 的 data 驱动）；非组字输入才走定宽。写回不
            // 在此（compend/blur/Enter 才提交，与旧口径
            // 一致）。
            if g.phase == Phase::Composing {
                g.comp_reflected = true;
            } else if g.phase == Phase::Editing {
                g.sync_width();
                g.maybe_log_upd("input");
            }
        });
        listen(&inner, "pointerdown", |g, e| {
            // 落点记号只在展示态（Idle）捕获：编辑中点按
            // 的原生落点不干预
            if g.phase != Phase::Idle {
                return;
            }
            let pe: &web_sys::PointerEvent = e.unchecked_ref();
            let full = g.committed.clone();
            let mark = tap_caret_target(&g.input, &g.mirror, &full, pe.client_x() as f64);
            g.tap_mark = mark.map(|m| (m, js_sys::Date::now()));
        });
        // keydown 单独注册：Enter/Esc 的 blur() 会同步派发
        // blur 事件再入监听，故判定与动作分两段借用。动
        // 作：0 无、1 Enter 失焦落定、2 Esc 还原后失焦。
        {
            let rc = inner.clone();
            let closure = Closure::wrap(Box::new(move |e: web_sys::Event| {
                let act = {
                    let Ok(mut g) = rc.try_borrow_mut() else {
                        return;
                    };
                    let ke: &web_sys::KeyboardEvent = e.unchecked_ref();
                    let composing = g.phase == Phase::Composing || ke.is_composing();
                    if composing || g.phase == Phase::Idle {
                        0
                    } else {
                        match ke.key().as_str() {
                            "Enter" => {
                                e.prevent_default();
                                1
                            }
                            "Escape" => {
                                // 还原会话起始文本：值写回
                                // 后 blur 按未改动收尾（提交
                                // 检查以 committed 为准，不
                                // 产生改动提交）
                                let base = g.session_base.clone();
                                if g.input.value() != base {
                                    g.input.set_value(&base);
                                }
                                2
                            }
                            _ => 0,
                        }
                    }
                };
                if act != 0 {
                    if let Ok(g) = rc.try_borrow() {
                        let el = g.input.clone();
                        drop(g);
                        let _ = el.blur();
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
        // —— 视口级监听：可用宽随视口变（旋转/窗口缩放/
        // 软键盘升降改 visualViewport），两态都重定宽
        // （公式自带未变不写） ——
        if let Some(vv) = window().and_then(|w| w.visual_viewport()) {
            let target: web_sys::EventTarget = vv.unchecked_into();
            listen_on(&inner, target, "resize", |g, _| {
                g.sync_width();
            });
        }
        if let Some(w) = window() {
            let target: web_sys::EventTarget = w.unchecked_into();
            listen_on(&inner, target, "resize", |g, _| {
                g.sync_width();
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

        // 展示定宽（挂载即应用，与会话收尾共用同一公式；
        // 首写免 transition，见 sync_width）
        inner.borrow_mut().sync_width();

        Some(TitleController { inner })
    }

    /// 壳卸载：摘全部监听、断开观察者、摘镜像；会话未收
    /// 尾时先把当前文本按原文提交（编辑器整体关闭路径
    /// 已在 go_back 同步失焦提交，此处仅兜底）。
    pub(super) fn detach(&self) {
        let mut g = self.inner.borrow_mut();
        if matches!(g.phase, Phase::Editing | Phase::Composing) {
            let raw = g.input.value();
            if raw != g.committed {
                g.committed = raw.clone();
                g.on_commit.call(raw);
            }
            g.phase = Phase::Idle;
            g.on_session.call(false);
        }
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
        let m_node: &web_sys::Node = g.mirror.unchecked_ref();
        if let Some(parent) = m_node.parent_node() {
            let _ = parent.remove_child(m_node);
        }
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
/// 文案节点）子树豁免。input 无 light-DOM 子树（文本在
/// 平台影子内、不产生 MutationRecord），胶囊子树的
/// childList 记录只可能来自框架或外来写者；属性变更与
/// 结构变更一律记 foreign。
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
    g.foreign += 1;
    set_foreign_counter(g.foreign);
    diag::log(
        "EDIT",
        &format!("titleGeom ph=foreign attr={ty} val=node:{}", target.node_name()),
    );
}
