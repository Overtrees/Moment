//! 此刻 · Rust Web（Dioxus / DOM 路线）：
//! 真实数据闭环——备份 ZIP 导入（core 校验）→ IndexedDB 持久
//! → 列表/搜索 → 块编辑器 → 备份 ZIP 导出。
//! 首次打开以真实样本数据播种，导入后全量替换（原版恢复语义）。
//! 页面结构与度量对原版逐项复刻（见各模块注释）。

mod backup;
mod blocks;
mod diag;
mod editor;
mod errbadge;
mod icons;
mod idb;
mod i18n;
mod list;
mod settings;
mod warmup;
mod wiki;

use dioxus::prelude::*;
use std::collections::HashSet;
use mynote_core::{BackupFile, Memo};
use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

const EMPTY_MANIFEST: &str = "{\"version\":1,\"attachments\":{}}";

/// 样式按模块拆分（styles/ 目录，对齐原版 styles 的组织）：
/// tokens.css 设计令牌（含深色令牌组）/ base.css 基础+列表 /
/// editor.css 编辑器+块渲染 / panels.css 功能页。
/// 组件里禁止再堆内联样式；动态值只走 CSS 变量注入。
const CSS: &str = concat!(
    include_str!("../styles/tokens.css"),
    include_str!("../styles/base.css"),
    include_str!("../styles/editor.css"),
    include_str!("../styles/panels.css"),
);

fn main() {
    diag::init();
    diag::log("APP", "start");
    // 清掉外壳的启动页占位：dioxus::launch 只往 #main 追加根节点，
    // 不清已有子节点，启动页会残留并把应用顶到一屏之外
    if let Some(el) = web_sys::window()
        .and_then(|w| w.document())
        .and_then(|d| d.get_element_by_id("main"))
    {
        el.set_inner_html("");
    }
    dioxus::launch(App);
}

/// 安全区探针：用一个临时元素的 env() padding 读四边 inset，
/// 连同 inner/vv 尺寸与 standalone 态打进 Diag（标签 SAFE）。
/// 列表滚动监听的一次性注册（见 App 内注释）：JS 侧 rAF 合并
/// 回送 window.scrollY，写回 scroll_y 信号（0.5px 去重）。
fn spawn_list_scroll_listener(mut scroll_y: Signal<f64>) {
    use dioxus::prelude::*;
    spawn(async move {
        let mut eval = document::eval(
            "if (window.__mnListScrollCleanup) window.__mnListScrollCleanup();\
             let raf = 0;\
             const onScroll = () => {\
               if (raf) return;\
               raf = requestAnimationFrame(() => { raf = 0; dioxus.send(window.scrollY); });\
             };\
             window.addEventListener('scroll', onScroll, { passive: true });\
             window.__mnListScrollCleanup = () => {\
               window.removeEventListener('scroll', onScroll);\
               if (raf) cancelAnimationFrame(raf);\
               window.__mnListScrollCleanup = null;\
             };\
             dioxus.send(window.scrollY);",
        );
        while let Ok(v) = eval.recv::<f64>().await {
            if (v - *scroll_y.read()).abs() > 0.5 {
                scroll_y.set(v.max(0.0));
            }
        }
    });
}

/// 当前系统配色（同步直读 matchMedia，与 editor::
/// is_dark_mode 同口径）。仅供根色派生输入摘要记 scheme
/// 分项——派生本体不读它（配色经 effective_bg 内部同口
/// 径体现），只作 Diag 呈现。
fn scheme_is_dark() -> bool {
    web_sys::window()
        .and_then(|w| w.match_media("(prefers-color-scheme: dark)").ok().flatten())
        .map(|m| m.matches())
        .unwrap_or(false)
}

/// 深浅模式监听（App 生命周期常驻）：系统深浅切换时 bump
/// scheme_tick，驱动根背景重派生（编辑器自定义色深色下压暗）
/// 与相关重渲染。App 永不卸载，spawn 依附 App 作用域安全。
fn spawn_scheme_listener(mut scheme_tick: Signal<u32>) {
    use dioxus::prelude::*;
    spawn(async move {
        let mut eval = document::eval(
            "const mq = window.matchMedia('(prefers-color-scheme: dark)'); \
             mq.addEventListener('change', () => dioxus.send('scheme')); \
             dioxus.send('ready');",
        );
        while let Ok(msg) = eval.recv::<String>().await {
            // 只对真实翻转 bump：'ready' 是注册回执，不算一次
            // 方案变化（误 bump 会让玻璃胶囊在启动后无谓重挂载
            // 一次）。翻转时 bump 触发 App 重渲染（渲染体消费
            // scheme_gen）+ 根背景 effect 重派生，同帧完成。
            if msg == "scheme" {
                let next = scheme_tick.read().wrapping_add(1);
                scheme_tick.set(next);
                diag::log("APP", &format!("scheme flip gen={next} (glass remount)"));
            }
        }
    });
}

/// 方案代际重挂载边界（深色切换玻璃根治的收敛形态）：四个独立
/// 玻璃胶囊各自做成边界组件——组件自身订阅 scheme_tick，翻转时
/// 只有该组件重渲染，并以代际为键重挂其根节点，玻璃背板层在新
/// 方案下首次合成。键只出现在各组件自己的模板内，不进 App 根
/// 片段：根片段挂键曾使翻转连带重挂载整棵列表子树、重置左滑
/// 开启态（探针 expando 实证：翻转后行与按钮节点全部换新；
/// 原版列表不随方案翻转重渲染、开启态保持）。边界组件不产生
/// 额外 DOM 节点，结构与原口径逐一对应。
#[component]
fn CompactTitle(
    scheme_tick: Signal<u32>,
    on_open_settings: EventHandler<()>,
    compact: bool,
) -> Element {
    let gen = *scheme_tick.read();
    let vis = if compact { "visible" } else { "hidden" };
    let op = if compact { 1.0 } else { 0.0 };
    rsx! {
        // 单元素键控迭代：key 只在动态节点位置生效，静态单根
        // 模板上挂 key 不重挂（探针实证——同批的 SearchCapsule/
        // AvatarContent 因根带条件分支属动态位置而生效）；以
        // once(gen) 把根放进键控列表位置，代际变化即换新节点。
        for g in std::iter::once(gen) {
            div {
                key: "{g}",
                class: "page-title compact",
                style: "visibility:{vis};opacity:{op};pointer-events:auto;cursor:pointer;width:fit-content;margin:0 auto;",
                onclick: move |_| on_open_settings.call(()),
                "{i18n::t(\"app.title\")}"
            }
        }
    }
}

/// 标题头像边界：把方案代际传给 AvatarContent，由其落键到根
/// 元素重挂（组件调用处挂键不重挂子组件根节点，见 list.rs
/// AvatarContent 注释），不引入额外节点。
#[component]
fn KeyedAvatar(scheme_tick: Signal<u32>, size: u32) -> Element {
    let gen = *scheme_tick.read();
    rsx! {
        list::AvatarContent { size, remount_gen: gen }
    }
}

/// 搜索胶囊边界（面板/触发二态）：根节点以代际为键重挂。
/// 静态声明已归 .glass-search-panel/.glass-search-trigger 类
/// 规则（base.css），内联只留随滚动折叠态变化的
/// opacity/visibility。
#[component]
fn SearchCapsule(
    scheme_tick: Signal<u32>,
    mut search_open: Signal<bool>,
    mut query: Signal<String>,
    compact: bool,
) -> Element {
    let gen = *scheme_tick.read();
    let open = *search_open.read();
    let vis_h = if compact { "hidden" } else { "visible" };
    let op_nc = if compact { 0.0 } else { 1.0 };
    rsx! {
        if open {
            div {
                key: "{gen}",
                class: "glass-search-panel",
                style: "opacity:{op_nc};visibility:{vis_h};",
                span { dangerous_inner_html: "{icons::search_markup(18)}" }
                input {
                    class: "glass-search-input",
                    placeholder: "{i18n::t(\"search.placeholder\")}",
                    value: "{query}",
                    oninput: move |e| query.set(e.value()),
                    onblur: move |_| search_open.set(false),
                    onkeydown: move |e| {
                        if e.key() == Key::Escape {
                            search_open.set(false);
                        }
                    },
                    onmounted: move |e| {
                        spawn(async move {
                            let _ = e.set_focus(true).await;
                        });
                    },
                    style: "width:140px;height:40px;border:none;background:transparent;font-size:var(--font-15);color:var(--text-main);outline:none;font-family:inherit;",
                }
            }
        } else {
            button {
                key: "{gen}",
                class: "glass-search-trigger",
                r#type: "button",
                onclick: move |_| search_open.set(true),
                style: "opacity:{op_nc};visibility:{vis_h};",
                span { dangerous_inner_html: "{icons::search_markup(20)}" }
                span { style: "font-size:var(--font-14);color:var(--glass-label-color);letter-spacing:-0.1px;", "{i18n::t(\"search.trigger\")}" }
            }
        }
    }
}

/// 颜色字符串 → "r,g,b" 三元组（#rgb/#rrggbb/rgb()/rgba()）。
/// effective_bg 的输出恒为 #rrggbb；导入数据里的 bgColor 若为
/// 其他写法也尽量解析，解析不了返回 None（渐变层回落方案默认）。
fn color_to_rgb_triplet(color: &str) -> Option<String> {
    let c = color.trim();
    if let Some(h) = c.strip_prefix('#') {
        let ch = |s: &str| u8::from_str_radix(s, 16).ok();
        return match h.len() {
            6 if h.chars().all(|x| x.is_ascii_hexdigit()) => Some(format!(
                "{},{},{}",
                ch(&h[0..2])?,
                ch(&h[2..4])?,
                ch(&h[4..6])?
            )),
            3 if h.chars().all(|x| x.is_ascii_hexdigit()) => {
                let mut it = h.chars();
                let (r, g, b) = (it.next()?, it.next()?, it.next()?);
                Some(format!(
                    "{},{},{}",
                    ch(&r.to_string().repeat(2))?,
                    ch(&g.to_string().repeat(2))?,
                    ch(&b.to_string().repeat(2))?
                ))
            }
            _ => None,
        };
    }
    let inner = c
        .strip_prefix("rgba(")
        .or_else(|| c.strip_prefix("rgb("))?
        .strip_suffix(')')?;
    let parts: Vec<&str> = inner.split(',').collect();
    if parts.len() >= 3 {
        let v: Option<Vec<u8>> = parts[..3]
            .iter()
            .map(|p| p.trim().parse::<u8>().ok())
            .collect();
        return v.map(|v| format!("{},{},{}", v[0], v[1], v[2]));
    }
    None
}

/// 根背景单次写入（web_sys 同步直调，无异步面）。写入分两
/// 路：【权威路径】html 与 body 的内联 style.backgroundColor
/// 直写（原版 editor.js:617-636 同款机制：设值直写、清理置
/// ''）——画布与视口外带区由浏览器按根元素背景绘制，内联
/// 样式变更是设备实证能触发带区重绘的路径；仅经 CSS 变量
/// 驱动根背景时 WebKit 不重绘带区、锁存陈旧采样（2026-11-23
/// 真机定案：变量撤净、html/body computed 均已回落列表色、
/// VARMUT/LATE 无任何复写，眼见顶部实心栏仍为编辑色——栏
/// 不在文档内，是带区对变量驱动变更的陈旧采样）。【同步镜
/// 像】:root 变量 --mn-root-bg（及 --mn-root-rgb 三元组）同
/// 值写入：base.css 的 html/body 规则以它为内联未设时的默
/// 认层，验收探针与 Diag 亦读它作页内同步与量测面；内联在
/// 场时以内联为准（优先级更高），两路同值不存在分叉。
/// body::before 顶带渐变是 base.css 基础规则（写死白/黑、与
/// 原版同构），不消费本变量；编辑器曾另有 #body-before-bg
/// 改写装置消费 --mn-root-rgb，已整套移除（见 editor.rs
/// scheme effect 注）。
/// None = 两路全清：内联 backgroundColor 清空、变量撤除，
/// 各层回落 var(--primary-bg)（根页面色）。
/// 调用方：App 派生 effect（权威/兜底：页面状态一变必然重派
/// 生，无清理步可失效）+ 各转变的发起任务同步先行写入同一值
/// （打开备忘 open_memo、关闭 on_close、编辑页换色 set_bg、
/// 深浅切换的编辑器 scheme 处理）——发起任务里先写、渲染与
/// effect 随后重申同值，慢设备上渲染分帧也不会闪旧色。
/// 返回列表顶部白带的根治在 Nav 的提交语义（编辑器离页窗
/// 口内页面状态不提交、根色与离页层自有底同值），不在写入
/// 时机，见 App 派生 effect 长注的定案段。
/// 根色写入失败留痕（ROOTERR）：apply_root_bg 的 set/remove
/// 原以 `let _ =` 吞错——写入失败时根色静默不动、日志却记成
/// 功，是「意图与实值脱节」的一类盲区；现仅失败时记一行。
fn root_err<T>(res: Result<T, wasm_bindgen::JsValue>, op: &str, val: &str) {
    if let Err(e) = res {
        let msg = js_sys::Reflect::get(&e, &"message".into())
            .ok()
            .and_then(|m| m.as_string())
            .unwrap_or_else(|| "js error".to_string());
        diag::log("APP", &format!("ROOTERR {op} val={val} err={msg}"));
    }
}

pub(crate) fn apply_root_bg(color: Option<&str>) {
    let Some(w) = web_sys::window() else { return };
    let Some(d) = w.document() else { return };
    let Some(el) = d.document_element() else { return };
    let Ok(html) = el.dyn_into::<web_sys::HtmlElement>() else {
        return;
    };
    let style = html.style();
    let body_style = d.body().map(|b| b.style());
    match color {
        Some(c) => {
            // 权威路径：html/body 内联 backgroundColor 直写。
            root_err(
                style.set_property("background-color", c),
                "set html background-color",
                c,
            );
            if let Some(bs) = &body_style {
                root_err(
                    bs.set_property("background-color", c),
                    "set body background-color",
                    c,
                );
            }
            // 同步镜像：变量同值（默认层与量测面）。
            root_err(style.set_property("--mn-root-bg", c), "set --mn-root-bg", c);
            match color_to_rgb_triplet(c) {
                Some(t) => {
                    root_err(style.set_property("--mn-root-rgb", &t), "set --mn-root-rgb", &t);
                }
                None => {
                    root_err(style.remove_property("--mn-root-rgb"), "remove --mn-root-rgb", "");
                }
            }
        }
        None => {
            // 两路全清：内联清空（原版置 '' 口径）+ 变量撤除。
            root_err(
                style.remove_property("background-color"),
                "clear html background-color",
                "",
            );
            if let Some(bs) = &body_style {
                root_err(
                    bs.remove_property("background-color"),
                    "clear body background-color",
                    "",
                );
            }
            root_err(style.remove_property("--mn-root-bg"), "remove --mn-root-bg", "");
            root_err(style.remove_property("--mn-root-rgb"), "remove --mn-root-rgb", "");
        }
    }
}

/// 根色模型（现行，2026-11-24 收口）：根背景 = 页面
/// 状态的纯函数——编辑页打开时为该篇有效背景
/// （effective_bg），其余页面（列表/设置/图片页等）
/// 为 None、回落根页面色（--primary-bg）。计算只在
/// App 派生 effect 一处；编辑器内的换色/scheme 先行
/// 写入直写同值（effective_bg），只提前生效时点、不
/// 另立口径。旧压暗栈与浮层在场派生输入已随其功能
/// 退役整删（压暗栈恒无注册者、派生恒等），根色无
/// 第二计算者。

/// 离页条目（组件页）：返回导航（Nav::go_back）的出场
/// 窗口——name 为正在出场的当前页、dest 为提交目标、gen
/// 为代际（提交计时到时须校验仍属本代，前进顶替/重复返
/// 回推进代际后旧计时自行作废）。窗口内页面状态不变、
/// 本页本体以 closing 在流内播 slideOut（与编辑器离页同
/// 语义，见 Nav 注释）；不再有快照重挂与冻结包裹。
#[derive(Clone)]
struct LeavingPage {
    name: &'static str,
    dest: &'static str,
    gen: u32,
}

/// 离页条目（编辑器）：编辑器不快照重挂——桥、根渐变、
/// __mn* 全局监听等单例机器都挂在实例上，重挂一份快照会
/// 与原实例的卸载清理竞态（本仓有清理永不执行的前科）。
/// 关闭时同一实例留在编辑器槽位内翻 closing prop，以当
/// 前页身份在流内原地播出场（串行交换，见 Nav 注释），
/// 本条目记 id（槽位键）、代际与列表滚动恢复值（提交
/// 点执行，基线时序）；窗口内实例渲染由槽位持
/// 有（selected 未清前由 selected、空备忘关闭即删除后由
/// 本条目兜底），不依赖 data 查得此备忘。
#[derive(Clone)]
struct LeavingEditor {
    id: String,
    gen: u32,
    restore: f64,
}

/// 导航状态机（App 层页面交接）：全应用一套机制（2026
/// -11-24 顶栏确诊后收敛，diagnose_settings_topbar.md）。
/// 前进导航（go）即刻挂载新页、同提交卸载旧页，与打开
/// 编辑器（open_memo）同形——自列表进入时先存列表滚动
/// 并回顶。返回导航（go_back）与编辑器离页同语义：页面
/// 状态保持到出场播完，提交计时到时在同一任务内清离页
/// 条目、翻转页面状态、恢复目标滚动（回列表走
/// list_restore、图片页返回走 img_restore），并打
/// committed + POST/CENSUS/LATE 提交普查。旧栈式快照交
/// 接（组件页即刻提交 + fixed 离页层重挂 closing 快照、
/// 滚动不管理、提交无打点）整套退役：其设置页往返后列
/// 表滚动停在浏览器钳制残值（真机实测 ~110pt、顶栏被
/// 截断）为确诊缺陷本体。
/// 编辑器→列表走串行同帧交换（2026-11-23 审计恢复集
/// (a)，audit_band_diff_45b5b46.md）：出场窗口内文档只
/// 有编辑器一层、编辑器以当前页身份在流内播出场，列表
/// 不预挂载；320ms 提交帧内编辑器卸载、列表挂载、根色
/// 翻转三者同帧——恢复基线 45b5b46 时序。此路曾用重叠
/// 交接（列表点击同帧预挂载为上层进入层），其结构差
/// （列表挂载与根色翻转解耦、挂载发生在根色仍为编辑色
/// 的时刻）为返回列表顶部白带的唯一结构差异，审计裁定
/// 恢复串行；串行下新页进场动画起步冻结（4x 节流 84ms）
/// 在此路随之回归，为用户知情接受的代价。编辑器同实例
/// 留槽翻 closing（见 LeavingEditor），不快照重挂。
/// 列表不入栈（有据偏离：前进导航的入页根层全不透明、
/// 挂载即全屏覆盖，交换提交前浏览器保持最后一帧即列表
/// 本身，无空白帧可填）。
/// 卸载计时走 web_sys setTimeout + 代际校验，不用 spawn：
/// 导航多由子页/编辑器的异步任务里触发，spawn 依附发起
/// 方作用域、其卸载会连带取消计时（本仓有同类前科，见
/// 编辑器 on_close 处理旧注）。
#[derive(Clone, Copy)]
struct Nav {
    page: Signal<&'static str>,
    selected: Signal<Option<String>>,
    leaving_page: Signal<Option<LeavingPage>>,
    leaving_editor: Signal<Option<LeavingEditor>>,
    gen: Signal<u32>,
    editor_closing: Signal<bool>,
    /// 图片页请求（ImgPage context 的信号本体）：图片页
    /// 返回提交点清除（出场窗口内本页本体仍靠它渲染）。
    img_req: Signal<Option<crate::blocks::ImgView>>,
    /// 列表滚动保存槽（与 App 的 list_scroll_restore 同一
    /// 句柄）：前进离开列表时存、返回提交点恢复。
    list_restore: Signal<f64>,
    /// 图片页进页前的编辑器滚动保存槽（与 App 的
    /// img_restore 同一信号）：图片页返回提交点恢复。
    img_restore: Signal<f64>,
}

impl Nav {
    fn next_gen(mut self) -> u32 {
        let g = self.gen.read().wrapping_add(1);
        self.gen.set(g);
        g
    }

    fn window_scroll() -> f64 {
        web_sys::window()
            .and_then(|w| w.scroll_y().ok())
            .unwrap_or(0.0)
    }

    /// 离页卸载计时：到时且条目仍属本代才撤（顶替/重开
    /// 已把代际推进，旧计时自行作废）。编辑器路的到时动作
    /// 是**提交**而不只是卸载：离页条目清除、selected 清
    /// 除（仍指向离页备忘时）、editor_closing 复位在同一
    /// 任务内完成——页面状态自此才从编辑器翻到列表，编辑
    /// 器卸载、列表挂载、根色翻转同属随后一次渲染提交
    /// （基线同帧交换）；列表滚动恢复也在此提交点以双
    /// rAF 执行（基线 on_close 时序：窗口内文档只有编辑
    /// 器，恢复须等列表挂载后落地；发起任务内先行恢复会
    /// 把在流内的编辑器拽到列表滚动位）。
    fn arm_unload(self, g: u32, editor: bool) {
        let ms = settings::page_transition_ms(editor);
        let Some(w) = web_sys::window() else {
            return;
        };
        let mut leaving_page = self.leaving_page;
        let mut leaving_editor = self.leaving_editor;
        let mut selected = self.selected;
        let mut editor_closing = self.editor_closing;
        let mut page = self.page;
        let mut img_req = self.img_req;
        let list_restore = self.list_restore;
        let img_restore = self.img_restore;
        let cb = wasm_bindgen::closure::Closure::once_into_js(move || {
            if editor {
                let hit = leaving_editor.peek().as_ref().and_then(|le| {
                    if le.gen == g {
                        Some((le.id.clone(), le.restore))
                    } else {
                        None
                    }
                });
                if let Some((id, restore)) = hit {
                    leaving_editor.set(None);
                    if selected.peek().as_deref() == Some(id.as_str()) {
                        selected.set(None);
                    }
                    editor_closing.set(false);
                    diag::log(
                        "APP",
                        &format!("TRANS editor {id} -> committed gen={g}"),
                    );
                    // 列表滚动恢复（原版 closeEditor，memo-list
                    // .js:247-258：双 rAF 后 scrollTo 保存值；保
                    // 存值为 0 时不处理）。落点在提交点而非发
                    // 起任务：串行窗口内文档只有在流内的编辑
                    // 器，先行恢复会拽动编辑器自身（见本函数
                    // 注释）；双 rAF 闭包不依附任何组件作用
                    // 域，提交后列表已挂载、恢复必落地。
                    if restore > 0.0 {
                        diag::log(
                            "APP",
                            &format!("close editor, restore list scroll {restore:.0}"),
                        );
                        if let Some(w) = web_sys::window() {
                            let w_inner = w.clone();
                            let inner = wasm_bindgen::closure::Closure::once_into_js(
                                move || {
                                    w_inner.scroll_to_with_x_and_y(0.0, restore);
                                },
                            );
                            let w_outer = w.clone();
                            let outer = wasm_bindgen::closure::Closure::once_into_js(
                                move || {
                                    let _ = w_outer
                                        .request_animation_frame(inner.unchecked_ref());
                                },
                            );
                            let _ = w.request_animation_frame(outer.unchecked_ref());
                        }
                    }
                    // 结果侧实测（诊断覆盖补齐）：提交点同任务取
                    // computed 与节点普查（此刻渲染尚未跟进、变
                    // 量仍为提交前值——与 LATE 的落定值对照成时
                    // 间线）；300/1000/3000ms 三发延迟重采样抓
                    // 提交后的晚到写入/监听回写。
                    diag::log_probe("APP", "POST");
                    diag::log_census("APP");
                    if let Some(w2) = web_sys::window() {
                        for delay in [300u32, 1000, 3000] {
                            let late = wasm_bindgen::closure::Closure::once_into_js(
                                move || diag::log_late(delay),
                            );
                            let _ = w2
                                .set_timeout_with_callback_and_timeout_and_arguments_0(
                                    late.unchecked_ref(),
                                    delay as i32,
                                );
                        }
                    }
                }
            } else {
                // 组件页路的到时动作同编辑器路：**提交**而非
                // 只是卸载——清离页条目、翻页面状态在同一任
                // 务内完成，离页页卸载、目标页挂载、根色翻
                // 转同属随后一次渲染提交；目标滚动恢复（回
                // 列表走 list_restore、图片页返回走
                // img_restore）也在此提交点以双 rAF 执行
                // （发起任务内先行恢复会拽动仍在流内的离页
                // 页自身，同编辑器路注）。图片页请求在提交
                // 点才清：出场窗口内本页本体仍靠它渲染。
                let hit = leaving_page.peek().as_ref().and_then(|l| {
                    if l.gen == g {
                        Some((l.name, l.dest))
                    } else {
                        None
                    }
                });
                if let Some((name, dest)) = hit {
                    leaving_page.set(None);
                    page.set(dest);
                    if name == "image" {
                        img_req.set(None);
                    }
                    diag::log(
                        "APP",
                        &format!("TRANS {name} -> committed gen={g}"),
                    );
                    let restore = if name == "image" {
                        *img_restore.peek()
                    } else if dest.is_empty() {
                        *list_restore.peek()
                    } else {
                        0.0
                    };
                    if restore > 0.0 {
                        diag::log(
                            "APP",
                            &format!("commit, restore scroll {restore:.0}"),
                        );
                        if let Some(w) = web_sys::window() {
                            let w_inner = w.clone();
                            let inner = wasm_bindgen::closure::Closure::once_into_js(
                                move || {
                                    w_inner.scroll_to_with_x_and_y(0.0, restore);
                                },
                            );
                            let w_outer = w.clone();
                            let outer = wasm_bindgen::closure::Closure::once_into_js(
                                move || {
                                    let _ = w_outer
                                        .request_animation_frame(inner.unchecked_ref());
                                },
                            );
                            let _ = w.request_animation_frame(outer.unchecked_ref());
                        }
                    }
                    // 结果侧实测（与编辑器路同口径）：POST +
                    // CENSUS + LATE 三发，抓提交后的晚到写入。
                    diag::log_probe("APP", "POST");
                    diag::log_census("APP");
                    if let Some(w2) = web_sys::window() {
                        for delay in [300u32, 1000, 3000] {
                            let late = wasm_bindgen::closure::Closure::once_into_js(
                                move || diag::log_late(delay),
                            );
                            let _ = w2
                                .set_timeout_with_callback_and_timeout_and_arguments_0(
                                    late.unchecked_ref(),
                                    delay as i32,
                                );
                        }
                    }
                }
            }
        });
        let _ = w.set_timeout_with_callback_and_timeout_and_arguments_0(
            cb.unchecked_ref(),
            ms as i32,
        );
    }

    /// 前进导航（列表→组件页、组件页→其子页、编辑器→图
    /// 片页）：即刻挂载新页、同提交卸载旧页（与 open_memo
    /// 同形）。本页若正在出场（返回窗口内被前进顶替），
    /// 先作废离页条目与旧计时。自列表进入时先存列表滚动
    /// 并回顶（open_memo 同形）；编辑器在场时不经此处理
    /// （图片页进页 effect 已自存编辑器滚动并回顶）。
    fn go(mut self, target: &'static str) {
        if *self.page.peek() == target {
            return;
        }
        if self.leaving_page.peek().is_some() {
            self.next_gen();
            let mut lp = self.leaving_page;
            lp.set(None);
        }
        if self.page.peek().is_empty() && self.selected.peek().is_none() {
            let y = Self::window_scroll();
            let mut lr = self.list_restore;
            lr.set(y);
            if let Some(w) = web_sys::window() {
                w.scroll_to_with_x_and_y(0.0, 0.0);
            }
            diag::log(
                "APP",
                &format!("go page {target} (list scroll {y:.0} saved)"),
            );
        }
        self.page.set(target);
    }

    /// 返回导航（组件页的全部 on_back 收敛于此）：与编辑
    /// 器离页同语义——页面状态**不在此处提交**：记离页
    /// 条目，当前页本体随之以 closing 在流内播 slideOut，
    /// 目标页不预挂载；提交计时到时在同一任务内清条目、
    /// 翻 page、恢复目标滚动并打提交普查（arm_unload）。
    fn go_back(self, dest: &'static str) {
        let cur = *self.page.peek();
        if cur.is_empty() || cur == dest {
            return;
        }
        let g = self.next_gen();
        let mut lp = self.leaving_page;
        lp.set(Some(LeavingPage {
            name: cur,
            dest,
            gen: g,
        }));
        diag::log(
            "APP",
            &format!("TRANS {cur} -> leaving gen={g}"),
        );
        self.arm_unload(g, false);
    }

    /// 编辑器离页（关闭回列表）：记离页条目并翻
    /// editor_closing——槽位内的同一实例随之以当前页身份
    /// 在流内播 slideOut，列表不预挂载（串行同帧交换，
    /// 2026-11-23 审计恢复集 (a)，见 Nav 注释）。
    /// 提交点语义（保留）：编辑器的页面状态**不在此处提
    /// 交**——selected 保留到卸载计时到时才在同一任务内
    /// 清除（arm_unload），离页窗口内当前页仍是编辑器，
    /// 根色派生继续给编辑底；提交帧内条目清除、selected
    /// 清除、closing 复位同任务完成，编辑器卸载、列表挂
    /// 载、根色翻转随同一次渲染提交同帧发生（与基线
    /// 45b5b46 的 on_close 同任务形态一致）。restore 为
    /// 打开该备忘时保存的列表滚动位，提交点双 rAF 恢复
    /// （arm_unload），不在此先行。
    /// 组件页返回（go_back）同走此提交点语义（2026-11
    /// -24 收敛）：窗口内当前页仍是离页页本体、根色派生
    /// 继续给其页面底，提交帧同任务翻转。
    fn begin_editor_leaving(self, id: &str, restore: f64) {
        let g = self.next_gen();
        let scroll = Self::window_scroll();
        let mut le = self.leaving_editor;
        le.set(Some(LeavingEditor {
            id: id.to_string(),
            gen: g,
            restore,
        }));
        let mut ec = self.editor_closing;
        ec.set(true);
        diag::log(
            "APP",
            &format!("TRANS editor {id} -> leaving gen={g} scroll={scroll:.0}"),
        );
        self.arm_unload(g, true);
    }

    /// 打开编辑器前清离页编辑器条目并复位 closing：同 id
    /// 快速重开时实例留在槽位、closing 翻回 false 续用
    /// （会话状态不丢）；异 id 时槽位换键重挂。旧条目计时
    /// 靠代际校验自行作废，此处须同步推进代际。
    fn clear_editor_leaving(self) {
        if self.leaving_editor.peek().is_some() {
            self.next_gen();
            let mut le = self.leaving_editor;
            le.set(None);
        }
        let mut ec = self.editor_closing;
        ec.set(false);
    }
}

fn spawn_safe_probe() {
    use dioxus::prelude::*;
    spawn(async move {
        let mut eval = document::eval(
            "const d = document.createElement('div');\
             d.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom);padding-left:env(safe-area-inset-left);padding-right:env(safe-area-inset-right)';\
             document.body.appendChild(d);\
             const cs = getComputedStyle(d);\
             const r = { t: cs.paddingTop, b: cs.paddingBottom, l: cs.paddingLeft, r: cs.paddingRight, iw: innerWidth, ih: innerHeight, vv: visualViewport ? Math.round(visualViewport.height) : -1, standalone: (navigator.standalone === true) || matchMedia('(display-mode: standalone)').matches };\
             d.remove();\
             dioxus.send(JSON.stringify(r));",
        );
        if let Ok(s) = eval.recv::<String>().await {
            diag::log("SAFE", &s);
        }
    });
}

/// 根色变更监视（VARMUT，诊断覆盖补齐）：App 挂载时给
/// documentElement 与 body 的 style 装 MutationObserver
/// （window 标志防重复装，App 常驻不卸故不摘）。监视面 =
/// apply_root_bg 的全部写入：--mn-root-bg / --mn-root-rgb
/// 变量与 html/body 内联 backgroundColor——任一被改即记一
/// 行（新值 + performance.now 相对时刻）。apply_root_bg
/// 是唯一合法写者，任何晚到写入（残留监听回写、竞速的异
/// 步写）在此必留痕，与 POST/LATE 的时点采样互为印证。
/// font-size 等其他内联样式变更不触监视面、不成行。
fn spawn_varmut_observer() {
    use dioxus::prelude::*;
    spawn(async move {
        let mut eval = document::eval(
            "if (!window.__mnVarMut) { \
               const de = document.documentElement; \
               const bd = document.body; \
               let pb = de.style.getPropertyValue('--mn-root-bg'); \
               let pr = de.style.getPropertyValue('--mn-root-rgb'); \
               let ph = de.style.backgroundColor; \
               let py = bd ? bd.style.backgroundColor : ''; \
               const obs = new MutationObserver(() => { \
                 const b = de.style.getPropertyValue('--mn-root-bg'); \
                 const r = de.style.getPropertyValue('--mn-root-rgb'); \
                 const h = de.style.backgroundColor; \
                 const y = bd ? bd.style.backgroundColor : ''; \
                 if (b !== pb || r !== pr || h !== ph || y !== py) { \
                   dioxus.send('bg=' + (b || '(unset)') + ' rgb=' + (r || '(unset)') + ' inl=' + (h || '(unset)') + '/' + (y || '(unset)') + ' t=' + Math.round(performance.now())); \
                   pb = b; pr = r; ph = h; py = y; \
                 } \
               }); \
               obs.observe(de, { attributes: true, attributeFilter: ['style'] }); \
               if (bd) obs.observe(bd, { attributes: true, attributeFilter: ['style'] }); \
               window.__mnVarMut = obs; \
             }",
        );
        while let Ok(msg) = eval.recv::<String>().await {
            diag::log("APP", &format!("VARMUT {msg}"));
        }
    });
}

/// 首次播种 = 原版内置示例数据（demo-memos.js 的数据口径移植：
/// 同标题、同正文、同结构；时间按原版相对今天生成——今天 /
/// 昨天 / 3 天前 / 7 天前 / 14 天前；heading 的 level 与 todo
/// 的 checked 按原版节点工厂放 attrs）。原先的静态样本是真实
/// 备忘的骨架（正文为空、图片附件无字节），首屏会出现一整张
/// 空白图片卡，与原版首屏完全两样，故废弃。
fn sample_data() -> BackupFile {
    sample_data_at(js_sys::Date::now() as i64)
}

/// 种子本体：直接构造 BackupFile/Memo/Node 类型值（去兼容
/// 第一步——不再拼旧格式 JSON 走 from_value，字段写错由编译
/// 期兜住）。与旧拼装形态的逐值等价由 seed_tests 金标锁死。
fn sample_data_at(now: i64) -> BackupFile {
    use mynote_core::model::{Id, Timestamp};
    use mynote_core::Node;
    use serde_json::{json, Map, Value};

    let day: i64 = 86_400_000;
    let text_node = |text: &str| Node {
        text: Some(text.to_string()),
        node_type: None,
        id: None,
        children: None,
        extra: Map::new(),
    };
    let block = |id: &str, ty: &str, extra: Map<String, Value>, children: Vec<Node>| Node {
        text: None,
        node_type: Some(ty.to_string()),
        id: Some(id.to_string()),
        children: Some(children),
        extra,
    };
    let p = |id: &str, text: &str| block(id, "paragraph", Map::new(), vec![text_node(text)]);
    let attrs = |v: Value| {
        let mut m = Map::new();
        m.insert("attrs".to_string(), v);
        m
    };
    let heading = |id: &str, text: &str| {
        block(id, "heading", attrs(json!({ "level": 2 })), vec![text_node(text)])
    };
    let todo = |id: &str, checked: bool, text: &str| {
        block(id, "todo", attrs(json!({ "checked": checked })), vec![text_node(text)])
    };
    // musicCard 无 children 键（旧形态即如此），单独构造。
    let music = |id: &str, url: &str| {
        let mut extra = Map::new();
        extra.insert("url".to_string(), Value::String(url.to_string()));
        extra.insert("meta".to_string(), Value::Null);
        extra.insert("status".to_string(), Value::String("loading".to_string()));
        Node {
            text: None,
            node_type: Some("musicCard".to_string()),
            id: Some(id.to_string()),
            children: None,
            extra,
        }
    };
    let memo = |id: &str, title: &str, pinned: bool, at: i64, doc: Vec<Node>| Memo {
        id: Id::Str(id.to_string()),
        title: Some(title.to_string()),
        pinned: Some(pinned),
        created_at: Timestamp::Millis(at),
        updated_at: Timestamp::Millis(at),
        doc,
        extra: Map::new(),
    };
    BackupFile {
        version: 2,
        exported_at: None,
        memos: vec![
            memo("demo_exhibit", "周末看展记录", false, now, vec![
                p("de1", "今天去了 UCCA 的「非物质再现」展。光线透过亚克力板投射在墙上的影子会随着人的移动变化，站久了会忘记时间。"),
                p("de2", "想起上周看的书里那句话：==所谓的边界，只是我们还没习惯的过渡带=="),
                heading("de3", "实用信息"),
                p("de4", "地址：798 艺术区 UCCA。票价 100 元。"),
            ]),
            memo("demo_home", "装修踩坑清单", true, now - day, vec![
                todo("dh1", true, "厨房插座至少留 6 个，台面要带开关"),
                todo("dh2", true, "卫生间防水刷到 1.8m，闭水试验做满 48h"),
                todo("dh3", false, "地板和瓷砖之间用极窄收边条，不要过门石"),
                todo("dh4", false, "衣柜做到顶，不要成品柜，顶部积灰严重"),
            ]),
            memo("demo_tools", "好用的工具网站", false, now - 3 * day, vec![
                p("dt1", "几个日常高频用到的小工具，免费无广告。"),
                p("dt2", "Excalidraw — 画架构图和流程图最顺手的白板。"),
                p("dt3", "Carbon — 把代码生成漂亮的分享图，支持 20+ 主题。"),
            ]),
            memo("demo_book", "读书笔记｜设计的觉醒", false, now - 7 * day, vec![
                p("db1", "田中一光的随笔集，断断续续读了一个月。"),
                p("db2", "「设计不是一种技能，而是捕捉事物本质的感觉和洞察力。」"),
                p("db3", "「整理、排布、思考——设计的本质就是这三件事的循环。」"),
            ]),
            memo("demo_music", "最近在听的歌", false, now - 14 * day, vec![
                heading("dm1", "上周循环最多的几首"),
                p("dm2", "She Her Her Hers — Arrows — 吉他前奏一响整个人都松下来了。适合下雨天窝在沙发上单曲循环。"),
                music("dm3", "https://c6.y.qq.com/base/fcgi-bin/u?__=1RE7gOYaMZgO"),
                p("dm4", "陶喆 — 月亮代表谁的心 — 晚上十一点半的地铁上听到这首歌，老歌新唱居然听出了不一样的味道。原来有些旋律不管过多少年都不会过期。"),
                music("dm5", "https://music.apple.com/cn/album/%E6%9C%88%E4%BA%AE%E4%BB%A3%E8%A1%A8%E8%B0%81%E7%9A%84%E5%BF%83/914664926?i=914664941"),
                p("dm6", "黑裙子 — Our Own Summer — 前奏的鼓点一出来就感觉回到了某个无所事事的夏天傍晚，风吹在脸上是热的，但心里是凉的。"),
                music("dm7", "https://163cn.tv/7ceoWN8"),
                p("dm8", "落日飞车 — My Jinji — 适合晚上开车听，吉他音色软软的，像夏天的风从车窗缝里吹进来。"),
                music("dm9", "https://open.spotify.com/track/7npPPrZEDmeHMk6mxvIeFa?si=zp0-QuSsTBWvhaGVKVUfjg"),
            ]),
        ],
        avatars: None,
        extra: Map::new(),
    }
}

#[cfg(test)]
mod seed_tests {
    /// 种子原生化等价金标：类型直构的序列化值须与旧裸 JSON
    /// 拼装形态逐值一致（篇目、文本、结构、时间口径全等）。
    #[test]
    fn seed_matches_legacy_json_shape() {
        let now: i64 = 1_700_000_000_000;
        let day: i64 = 86_400_000;
        let p = |id: &str, text: &str| {
            serde_json::json!({ "id": id, "type": "paragraph",
                "children": [{ "text": text }] })
        };
        let legacy = serde_json::json!({
            "version": 2,
            "memos": [
                { "id": "demo_exhibit", "title": "周末看展记录", "pinned": false,
                  "createdAt": now, "updatedAt": now,
                  "doc": [
                    p("de1", "今天去了 UCCA 的「非物质再现」展。光线透过亚克力板投射在墙上的影子会随着人的移动变化，站久了会忘记时间。"),
                    p("de2", "想起上周看的书里那句话：==所谓的边界，只是我们还没习惯的过渡带=="),
                    { "id": "de3", "type": "heading", "attrs": { "level": 2 }, "children": [{ "text": "实用信息" }] },
                    p("de4", "地址：798 艺术区 UCCA。票价 100 元。")
                  ] },
                { "id": "demo_home", "title": "装修踩坑清单", "pinned": true,
                  "createdAt": now - day, "updatedAt": now - day,
                  "doc": [
                    { "id": "dh1", "type": "todo", "attrs": { "checked": true }, "children": [{ "text": "厨房插座至少留 6 个，台面要带开关" }] },
                    { "id": "dh2", "type": "todo", "attrs": { "checked": true }, "children": [{ "text": "卫生间防水刷到 1.8m，闭水试验做满 48h" }] },
                    { "id": "dh3", "type": "todo", "attrs": { "checked": false }, "children": [{ "text": "地板和瓷砖之间用极窄收边条，不要过门石" }] },
                    { "id": "dh4", "type": "todo", "attrs": { "checked": false }, "children": [{ "text": "衣柜做到顶，不要成品柜，顶部积灰严重" }] }
                  ] },
                { "id": "demo_tools", "title": "好用的工具网站", "pinned": false,
                  "createdAt": now - 3 * day, "updatedAt": now - 3 * day,
                  "doc": [
                    p("dt1", "几个日常高频用到的小工具，免费无广告。"),
                    p("dt2", "Excalidraw — 画架构图和流程图最顺手的白板。"),
                    p("dt3", "Carbon — 把代码生成漂亮的分享图，支持 20+ 主题。")
                  ] },
                { "id": "demo_book", "title": "读书笔记｜设计的觉醒", "pinned": false,
                  "createdAt": now - 7 * day, "updatedAt": now - 7 * day,
                  "doc": [
                    p("db1", "田中一光的随笔集，断断续续读了一个月。"),
                    p("db2", "「设计不是一种技能，而是捕捉事物本质的感觉和洞察力。」"),
                    p("db3", "「整理、排布、思考——设计的本质就是这三件事的循环。」")
                  ] },
                { "id": "demo_music", "title": "最近在听的歌", "pinned": false,
                  "createdAt": now - 14 * day, "updatedAt": now - 14 * day,
                  "doc": [
                    { "id": "dm1", "type": "heading", "attrs": { "level": 2 }, "children": [{ "text": "上周循环最多的几首" }] },
                    p("dm2", "She Her Her Hers — Arrows — 吉他前奏一响整个人都松下来了。适合下雨天窝在沙发上单曲循环。"),
                    { "id": "dm3", "type": "musicCard", "url": "https://c6.y.qq.com/base/fcgi-bin/u?__=1RE7gOYaMZgO", "meta": null, "status": "loading" },
                    p("dm4", "陶喆 — 月亮代表谁的心 — 晚上十一点半的地铁上听到这首歌，老歌新唱居然听出了不一样的味道。原来有些旋律不管过多少年都不会过期。"),
                    { "id": "dm5", "type": "musicCard", "url": "https://music.apple.com/cn/album/%E6%9C%88%E4%BA%AE%E4%BB%A3%E8%A1%A8%E8%B0%81%E7%9A%84%E5%BF%83/914664926?i=914664941", "meta": null, "status": "loading" },
                    p("dm6", "黑裙子 — Our Own Summer — 前奏的鼓点一出来就感觉回到了某个无所事事的夏天傍晚，风吹在脸上是热的，但心里是凉的。"),
                    { "id": "dm7", "type": "musicCard", "url": "https://163cn.tv/7ceoWN8", "meta": null, "status": "loading" },
                    p("dm8", "落日飞车 — My Jinji — 适合晚上开车听，吉他音色软软的，像夏天的风从车窗缝里吹进来。"),
                    { "id": "dm9", "type": "musicCard", "url": "https://open.spotify.com/track/7npPPrZEDmeHMk6mxvIeFa?si=zp0-QuSsTBWvhaGVKVUfjg", "meta": null, "status": "loading" }
                  ] }
            ]
        });
        assert_eq!(
            serde_json::to_value(super::sample_data_at(now)).unwrap(),
            legacy
        );
    }
}

/// 列表口径排序（置顶在前、其余按更新时间倒序，稳定排序）：
/// 只排引用且排序键每条只算一次——旧实现每次 App 渲染都克隆
/// 全部备忘，并在每次比较里重复解析 ISO 时间戳（to_millis），
/// 300 篇量测下滚动每帧触发全量重算（Lane T 实测热点）。
fn sorted_refs(data: &BackupFile) -> Vec<&Memo> {
    let mut refs: Vec<&Memo> = data.memos.iter().collect();
    refs.sort_by_cached_key(|m| {
        (
            std::cmp::Reverse(m.pinned.unwrap_or(false)),
            std::cmp::Reverse(m.updated_at.to_millis().unwrap_or(0)),
        )
    });
    refs
}

/// D3 首启一次性迁移的完成标记键（localStorage；版本后缀便于
/// 将来再启一轮迁移时换新键）。
const STOCK_MIG_KEY: &str = "mynote_stock_mig_v1";

/// 首启一次性迁移（去兼容第三步 D3，refactor_remove_compat
/// §4）：存量备忘经迁移通道（core::migrate）一次性归一并写回，
/// 与 D2 共用同一套转换函数。完成标记落 localStorage、只跑
/// 一次；归一在克隆上进行，校验（序列化往返 + 篇数/节点数守
/// 恒）通过才换入实数据（validate-then-swap）——校验失败原
/// 数据一行不动、不落标记、下次启动重试。命中统计落 Diag
/// （MIGRATE 行），即真机存量的旧形态证据。返回实数据是否
/// 被换入（调用方据此决定是否回写落盘）。无 localStorage
/// （标记无处落）时跳过，避免每次启动重跑。
fn run_stock_migration(parsed: &mut BackupFile) -> bool {
    let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
    else {
        return false;
    };
    if storage.get_item(STOCK_MIG_KEY).ok().flatten().is_some() {
        return false;
    }
    let node_total = |b: &BackupFile| -> usize {
        b.memos
            .iter()
            .map(|m| mynote_core::migrate::count_nodes(&m.doc))
            .sum()
    };
    let before_nodes = node_total(parsed);
    let mut candidate = parsed.clone();
    let stats = mynote_core::migrate::normalize_backup(&mut candidate);
    let valid = node_total(&candidate) == before_nodes
        && serde_json::to_string(&candidate)
            .ok()
            .and_then(|s| serde_json::from_str::<BackupFile>(&s).ok())
            .map(|rt| {
                rt.memos.len() == candidate.memos.len() && node_total(&rt) == before_nodes
            })
            .unwrap_or(false);
    if !valid {
        diag::log(
            "APP",
            "MIGRATE d3 aborted: validation failed, stock untouched",
        );
        return false;
    }
    let changed = stats.total_changes() > 0;
    if changed {
        *parsed = candidate;
    }
    let _ = storage.set_item(STOCK_MIG_KEY, "1");
    diag::log("APP", &format!("MIGRATE d3 {}", stats.summary()));
    diag::log("APP", &format!("MIGRATE census {}", stats.census_summary()));
    changed
}

#[component]
fn App() -> Element {
    let mut data = use_signal(sample_data);
    let mut manifest = use_signal(|| EMPTY_MANIFEST.to_string());
    // 状态 toast 只报用户动作的结果（导入/导出等），启动不弹
    // （原版首开无 toast）；种子/已加载只记诊断日志。
    let status = use_signal(String::new);
    let mut query = use_signal(String::new);
    let mut selected = use_signal(|| Option::<String>::None);
    // 本会话新建的备忘 id 集（列表新建 / wiki 新建时登记，
    // 编辑器关闭后注销）：供「空白关闭即删除」限定范围。
    let mut new_ids = use_signal(HashSet::<String>::new);
    let mut gen = use_signal(|| 0u32);
    // 子页面："" 列表/编辑 | settings 设置 | backup 备份 |
    // language 语言 | diag 诊断（诊断与语言入口都在设置页内）
    // | image 图片页（编辑器内点图进入，与上列同级）
    let mut page = use_signal(|| "");
    // 页面交接状态（统一机制，见 Nav）：离页条目
    // （组件页/编辑器各一槽）+ 代际 + 编辑器离页翻转信号。
    let leaving_page = use_signal(|| Option::<LeavingPage>::None);
    let leaving_editor = use_signal(|| Option::<LeavingEditor>::None);
    let nav_gen = use_signal(|| 0u32);
    let editor_closing = use_signal(|| false);
    // 图片页请求（ImgPage context）：编辑器内图片点击
    // 写入、App 监听打开图片页（见下方进页 effect）；
    // img_restore 为进页前的编辑器窗口滚动位，返回时
    // 恢复（编辑器实例不卸载、状态保留，滚动属窗口须
    // 单独存还）。
    let mut img_req = use_signal(|| Option::<crate::blocks::ImgView>::None);
    use_context_provider(|| crate::blocks::ImgPage(img_req));
    let mut img_restore = use_signal(|| 0f64);
    // 列表滚动保存槽（原版 scrollRestoreRef，memo-list.js
    // :184）：打开备忘/前进离开列表前存当前 scrollY 并回
    // 顶，返回提交点双 rAF 恢复（S1）。Nav 持同一句柄
    // （组件页前进/返回共用此槽，与编辑器路同值同点）。
    let mut list_scroll_restore = use_signal(|| 0f64);
    let nav = Nav {
        page,
        selected,
        leaving_page,
        leaving_editor,
        gen: nav_gen,
        editor_closing,
        img_req,
        list_restore: list_scroll_restore,
        img_restore,
    };
    // 折叠展开的子组集合（键 "{label}-img" / "{label}-txt"，原版口径）
    let mut expanded = use_signal(HashSet::<String>::new);
    // 列表滚动位置（驱动标题收缩与紧凑胶囊，原版 TITLE_THRESHOLD=30）
    let mut scroll_y = use_signal(|| 0f64);
    let mut search_open = use_signal(|| false);
    use_hook(spawn_safe_probe);
    // 根色变量变更监视（VARMUT）：App 生命周期内只装一次、
    // 常驻——抓任何绕过派生的晚到根色写入（见函数注）。
    use_hook(spawn_varmut_observer);
    // 列表滚动监听：App 生命周期内只注册一次、常驻（原版
    // memo-list.js:190-211 的监听随 MemoList 组件常驻——该组件
    // 渲染 Editor 时自身不卸载，监听跨编辑器往返存活；JS 侧
    // rAF 合并，每帧最多回送一次最新 scrollY）。
    // 曾按 S5 改为随列表页启停（use_effect 依 selected/page
    // 注销/重注册），实测根治前故障：编辑器往返后 effect 的
    // 重注册永不落地（window.__mnListScrollCleanup 恒为 null、
    // scroll_y 冻结在打开备忘时的值），搜索胶囊与标题永久卡在
    // 当时的紧凑态——滚动≥30 打开备忘再返回，胶囊在列表顶部
    // 仍隐藏且不随滚动恢复（偶发渲染异常的根因）；设置页往返
    // 则一切正常。改回常驻注册后，scroll_y 的消费仍只在列表
    // 渲染时读取（见下方 list_visible），编辑/设置/备份/诊断页
    // 滚动不订阅该信号、不触发 App 重渲染，S5 的消费收敛保留。
    use_hook(|| spawn_list_scroll_listener(scroll_y));
    // 深浅模式信号（App 常驻监听）：供根背景派生在系统深浅
    // 切换时重算（编辑器自定义色深色压暗口径）。
    let mut scheme_tick = use_signal(|| 0u32);
    use_hook(move || spawn_scheme_listener(scheme_tick));
    // 冷开预热（列表页空闲期以合成数据预跑编辑器纯渲染 /
    // wiki 提取纯函数路径，把首次执行成本前移到空闲期，
    // 见 warmup 模块）：App 挂载注册一次，离开列表即中止。
    use_hook(move || warmup::spawn_idle_warmup(page, selected));
    // 根背景派生（页面色泄漏根治 + 同步根治）：全站根级颜色
    // 状态在此按当前页面状态响应式派生，经 apply_root_bg 双
    // 写落地（html/body 内联 backgroundColor 为画布/带区权威
    // 路径，:root 变量同值镜像）——编辑页打开（page 空且有选中备忘，与渲染
    // 分支同条件）时 = 该备忘的有效背景（editor::effective_bg，
    // 自定义色优先、深色压暗，与编辑器内口径同一实现）；其他
    // 一切页面 = 撤变量、回落 CSS --primary-bg（根页面色）。
    // 取代旧的编辑器「进入时写、退出时清」命令式配对：旧清理
    // 放在 use_drop 的 spawn+eval 里，卸载即被取消、从未执行，
    // 编辑色永久残留在根上，列表/设置/备份页顶底带全染编辑色
    // （探针实证）。派生式无清理可失效：页面状态一变，effect
    // 随 App 重渲染同步重派生（权威/兜底）。各转变的发起任务
    // （open_memo/on_close/set_bg/scheme 处理）另同步先行写入
    // 同一派生值——同值重申无副作用，只把生效时点提前到发起
    // 任务内，消除慢设备渲染分帧时带区闪旧色（见 apply_root_bg）。
    // 返回列表顶部白带（2026-11-23 用户真机报告）定案：与上
    // 述泄漏异源——设备 Diag 实读与 box 实测均证实返回序列终
    // 点为 (root default)、其后无晚到写者，本派生的静止态取
    // 值正确（分界证据见 TESTING.md 过渡行登记）。产生异色
    // 的状态在呈现侧：#14 栈式交接的离页窗口内，页面状态已
    // 切列表、根色已派生为列表色，但离页编辑器仍以
    // #editor-root 自有底色（effective_bg 内联）作全屏不透
    // 明底留在下层——页面底色出现根色之外的第二来源（违背
    // 背景层级模型：根页面是唯一背景色源、上层不自带底
    // 色），浏览器带区锁存该自有底色、交接后无重采。
    // 根治（同日终版，用户「彻底根治」指令）：不动本派生
    // （保持页面状态纯函数、输入不变、无离页特例），改
    // Nav 的提交语义——编辑器离页窗口内页面状态不提交，
    // selected 保留至卸载计时到时与实例卸载同一任务清除
    // （见 Nav::begin_editor_leaving/arm_unload），与原版
    // 串行语义同构（出场期间当前页即编辑器）。于是窗口内
    // 本派生继续给出编辑底，与 #editor-root 自有底同值
    // （同一备忘、同一 effective_bg）——不透明层不再是异
    // 色第二来源，编辑器以自身底色出场、衬底不透列表色；
    // 提交帧状态翻转、实例卸载与根色翻值同属一次渲染提
    // 交，带区只在此帧翻一次且与编辑器消失同帧。曾试两
    // 版均回退：①「撤色后移卸载点 + 派生对象改在屏编辑
    // 器」——状态已提交列表却让派生输出编辑色（派生对状
    // 态撒谎），用户裁定为补丁；②「closing 时 #editor-root
    // 改 transparent」——带区虽正，离页层衬底透出列表色
    // （#FAFAFA→#F2F2F7，8 色阶，280ms），属交换式残差，
    // 用户不接受。本版与 ① 的分界：改的是状态机提交点而
    // 非颜色管线，派生自始至终只读当前页面状态。
    // 续（2026-11-23 晚，构建 1af457fdd4 真机复测仍 FAIL
    // 后的逐项对比审计，audit_band_diff_45b5b46.md）：上
    // 述提交点语义保留，但呈现侧结构与基线 45b5b46 的唯
    // 一差异被定罪——重叠交接下列表在点击同帧即预挂载，
    // 其挂载发生的时刻根色仍为编辑值，列表挂载与根色翻
    // 转解耦。恢复集 (a) 已落：编辑→列表恢复基线同帧交
    // 换的层结构——窗口内列表不挂载、编辑器不进 fixed
    // 离页层而以当前页身份在流内出场，提交帧编辑器卸
    // 载、列表挂载、根色翻转同帧。本派生与提交点语义一
    // 字未动，变的只是层的结构与挂载时刻。
    // 派生输入至此收口为页面状态本身（page/selected/
    // scheme）：旧压暗栈与浮层在场输入已随其功能退役整
    // 删（见 apply_root_bg 后根色模型注）。
    let mut root_bg_last = use_signal(|| Option::<String>::None);
    use_effect(move || {
        let _ = scheme_tick.read();
        let mut bgc_seen: Option<Option<String>> = None;
        let base: Option<String> = if page.read().is_empty() {
            selected.read().clone().map(|id| {
                // selected 查无此备忘只可能来自空备忘关闭即
                // 删的离页窗口（删除前提含无自定义背景，见
                // editor.rs go_back 的 empty 判定）：其有效
                // 背景恒为默认，回落 effective_bg(&None) 是
                // 事实值而非近似。
                let bgc = data
                    .read()
                    .memos
                    .iter()
                    .find(|m| m.id.to_string() == id)
                    .and_then(|m| m.extra.get("bgColor"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                bgc_seen = Some(bgc.clone());
                editor::effective_bg(&bgc)
            })
        } else {
            None
        };
        // 派生值即 base 本身（页面状态纯函数，见根色模
        // 型注）：编辑页 = 有效背景、其余页 = None 回落
        // 根页面色。各先行写入点（open_memo / set_bg /
        // scheme 分支）直写 effective_bg 同值，先行值与
        // 派生值同源、不会异口径竞速。
        let target = base.clone();
        // 派生输入摘要（Diag 回溯）：target 变化行同附
        // ——「为什么写这个值」可回溯、与量测时点的 DOM
        // 实值可对照。
        let page_desc = if !page.read().is_empty() {
            (*page.read()).to_string()
        } else if base.is_some() {
            "editor".to_string()
        } else {
            "list".to_string()
        };
        let bgc_disp = match &bgc_seen {
            Some(Some(c)) => c.clone(),
            Some(None) => "none".to_string(),
            None => "-".to_string(),
        };
        let summary = format!(
            "inputs page={page_desc} sel={} scheme={} bgc={bgc_disp} base={} target={}",
            selected.read().clone().unwrap_or_else(|| "none".to_string()),
            if scheme_is_dark() { "dark" } else { "light" },
            base.as_deref().unwrap_or("(root)"),
            target.as_deref().unwrap_or("(root)"),
        );
        if *root_bg_last.peek() != target {
            diag::log(
                "APP",
                &format!(
                    "root bg -> {} | {summary}",
                    target.as_deref().unwrap_or("(root default)")
                ),
            );
            root_bg_last.set(target.clone());
        }
        apply_root_bg(target.as_deref());
        // 写后回读（ROOTSET）：派生意图落 DOM 后的实值，与
        // 「root bg ->」意图行成对，脱节即在此显形。
        diag::log_probe("APP", "ROOTSET");
    });
    // 图片页进页（ImgPage context 监听）：编辑器内点图
    // 写入请求 → 存当前窗口滚动位（编辑器滚动）、回顶、
    // 切图片页。走 Nav 组件页同路但不入栈：编辑器不走
    // 栈式快照（见 Nav 注释），实例留在槽位内由 stage
    // 显示开关隐藏、状态与会话原样保留，返回时恢复滚
    // 动位。effect 只订阅 img_req 本身。
    use_effect(move || {
        if img_req.read().is_some() {
            img_restore.set(Nav::window_scroll());
            if let Some(w) = web_sys::window() {
                w.scroll_to_with_x_and_y(0.0, 0.0);
            }
            nav.go("image");
        }
    });
    let mut font_size = use_signal(|| {
        web_sys::window()
            .and_then(|w| w.local_storage().ok().flatten())
            .and_then(|s| s.get_item("sj_fontsize").ok().flatten())
            .unwrap_or_else(|| "medium".to_string())
    });
    // 文字大小 = 原版 applyFontSize：改根字号（rem 全局缩放）
    use_effect(move || {
        let px = settings::font_px(font_size.read().as_str());
        spawn(async move {
            let _ = document::eval(&format!(
                "document.documentElement.style.fontSize = '{px}';"
            ))
            .await;
        });
    });

    // 启动：恢复语言选择（缓存即时应用 + 后台刷新语言包）
    use_effect(move || {
        spawn(async move {
            i18n::init_lang().await;
        });
    });

    // 启动：IndexedDB 有持久数据则覆盖样本
    use_effect(move || {
        spawn(async move {
            match idb::load_state().await {
                Some((memos_json, manifest_raw)) => {
                    match serde_json::from_str::<BackupFile>(&memos_json) {
                        Ok(mut parsed) => {
                            diag::log("APP", &format!("loaded persisted memos={}", parsed.memos.len()));
                            // 首启一次性迁移（D3）：存量旧形态
                            // 在 data 应用之前归一（校验通过才
                            // 换入），换入则与尾巴恢复共用一次
                            // 回写落盘。
                            let stock_migrated = run_stock_migration(&mut parsed);
                            // 待发尾巴恢复（批 4 链尾产品红根
                            // 治）：整页卸载前桥存入 localStorage
                            // 保险丝的未落模型键入，逐篇按块 id
                            // 落回并回写落盘——赶在 data 应用与
                            // 深链打开之前，持久副本即刻含尾巴。
                            let mut recovered = 0usize;
                            for m in parsed.memos.iter_mut() {
                                recovered +=
                                    crate::editor::recover_pending_input(&mut m.doc);
                            }
                            data.set(parsed.clone());
                            if recovered > 0 {
                                diag::log(
                                    "APP",
                                    &format!("pending input recovered ({recovered} blocks)"),
                                );
                            }
                            if stock_migrated || recovered > 0 {
                                if let Ok(json) = serde_json::to_string(&parsed) {
                                    let _ = idb::save_memos(&json).await;
                                }
                            }
                            if !manifest_raw.is_empty() {
                                manifest.set(manifest_raw);
                            }
                            diag::log("APP", "persisted state applied");
                        }
                        Err(e) => diag::log("APP", &format!("persisted memos_json parse err: {e}")),
                    }
                }
                None => diag::log("APP", "no persisted state, seed sample"),
            }
            // ?open= 深链（原版 tryOpenNote）：id 精确或标题
            // 包含匹配，第一篇命中即打开
            if let Some(open) = web_sys::window()
                .and_then(|w| w.location().search().ok())
                .and_then(|q| {
                    q.trim_start_matches('?')
                        .split('&')
                        .find_map(|kv| kv.strip_prefix("open="))
                        .map(|v| {
                            js_sys::decode_uri_component(v)
                                .map(|j| j.as_string().unwrap_or_default())
                                .unwrap_or_default()
                        })
                })
                .filter(|v| !v.is_empty())
            {
                let hit = data
                    .read()
                    .memos
                    .iter()
                    .find(|m| {
                        m.id.to_string() == open
                            || m.title.as_deref().unwrap_or("").contains(&open)
                    })
                    .map(|m| m.id.to_string());
                if let Some(id) = hit {
                    diag::log("APP", &format!("deep link open={open} -> {id}"));
                    // 与 open_memo 同口径（S1）：存当前滚动位置
                    //（启动时为 0）并回顶，再打开
                    let y = web_sys::window()
                        .and_then(|w| w.scroll_y().ok())
                        .unwrap_or(0.0);
                    list_scroll_restore.set(y);
                    if let Some(w) = web_sys::window() {
                        w.scroll_to_with_x_and_y(0.0, 0.0);
                    }
                    selected.set(Some(id));
                }
            }
        });
    });

    let all_count = data.read().memos.len();
    // 分组结果 memo 化（Lane T 实测根治）：排序+搜索过滤+分组
    // 只依赖 data 与 query 两个信号，收进 use_memo 后滚动
    // （scroll_y）、标题收缩等无关信号变化不再触发全量重算——
    // 旧实现挂在 App 函数体里，每次渲染（含每个滚动帧）都重跑
    // 一遍 300 篇的克隆/排序/分组。PERF 日志保留：每次真重算
    // 记一行耗时，供后续真机回溯。
    let groups_memo = use_memo(move || {
        let t0 = js_sys::Date::now();
        let backup = data.read();
        let q = query.read().trim().to_string();
        let filtered: Vec<&Memo> = sorted_refs(&backup)
            .into_iter()
            .filter(|m| list::matches_search(m, &q))
            .collect();
        let groups = list::build_groups(&filtered);
        diag::log(
            "PERF",
            &format!(
                "list groups recompute memos={} in {:.1}ms",
                backup.memos.len(),
                js_sys::Date::now() - t0
            ),
        );
        groups
    });
    let groups = groups_memo.read();
    let sel_id = selected.read().clone();

    // 编辑器槽位：当前编辑（selected）优先——离页窗口内
    // selected 保留至提交帧（见 Nav 提交语义），槽位全程
    // 由 selected 持有；无当前编辑而有离页条目时才由离页
    // 条目兜底持有——同一位置、同一键，实例不卸载（见
    // LeavingEditor）。is_new 只供 go_back 的空备忘判定，
    // 离页渲染不读。列表渲染与列表可见性一律以槽位是否
    // 在场为准（editor_slot.is_none()）：窗口内槽位在场
    // 即不挂列表——空备忘关闭即删除后 data 已无此备忘，
    // 以 data 查有无（旧 sel_memo 口径）判会误挂列表，
    // 串行时序下列表只能在提交帧随槽位释放同帧出现。
    let leaving_ed = leaving_editor.read().clone();
    let editor_slot: Option<String> = sel_id.clone().or_else(|| {
        if *editor_closing.read() {
            leaving_ed.as_ref().map(|le| le.id.clone())
        } else {
            None
        }
    });
    // 离页态 = 槽位正由离页条目所指实例占用且 closing 在场
    // （提交点后移后窗口内 selected 未清，不能再以
    // sel_id.is_none() 判离页）。
    let editor_is_leaving = match (&editor_slot, &leaving_ed) {
        (Some(slot), Some(le)) => *editor_closing.read() && *slot == le.id,
        _ => false,
    };
    // 离页编辑器无冻结包裹：串行形态下它在流内以当前页
    // 身份出场，文档滚动即其自身滚动、无层可冻结（旧重
    // 叠形态的 fixed 离页层靠内层 translateY(-scroll) 冻
    // 结滚动姿态，已随恢复集 (a) 退役）。
    // 组件页出场态：离页条目所指的当前页本体以 closing
    // 渲染（在流内播 slideOut，页面状态提交前不变——与
    // 编辑器离页同语义，见 Nav::go_back）。旧快照重挂渲
    // 染与 fixed 离页层已随栈式交接整套退役（2026-11-24
    // 收敛）。
    let closing_name = leaving_page.read().as_ref().map(|l| l.name);

    // 方案代际（深色切换玻璃根治）：渲染体不再消费 scheme_tick
    // ——四个独立玻璃胶囊（紧凑标题胶囊、标题头像、搜索触发、
    // 搜索面板）各自是边界组件（CompactTitle/KeyedAvatar/
    // SearchCapsule），由其自身订阅代际并重挂载。App 根片段曾
    // 直接挂代际键，翻转时整棵列表子树被连带重挂载、左滑开启
    // 态被重置，故收敛到组件边界；根背景派生仍由上方 effect
    // 消费 scheme_tick，不受影响。

    // scroll_y 只在列表页可见时读取：其他页面滚动不订阅该信号，
    // 不触发 App 重渲染（S5 消费收敛）。可见 = 无组件页在
    // 场且编辑器槽位空（串行时序下离页窗口内列表尚未挂
    // 载，不属可见，编辑器滚动不驱动列表标题进度）。
    let list_visible = editor_slot.is_none() && page.read().is_empty();
    let progress = if list_visible {
        (*scroll_y.read() / 30.0).clamp(0.0, 1.0)
    } else {
        0.0
    };
    let is_compact = progress >= 1.0;
    let title_scale = 1.0 - progress * 0.45;
    let title_ty = progress * -4.0;
    let title_op = 1.0 - progress * 0.3;
    let vis_h = if is_compact { "hidden" } else { "visible" };
    let op_title = if is_compact { 0.0 } else { title_op };

    let persist = move |backup: BackupFile| {
        spawn(async move {
            if let Ok(json) = serde_json::to_string(&backup) {
                let _ = idb::save_memos(&json).await;
            }
        });
    };

    // 打开备忘的统一入口（原版 openEditor，memo-list.js:240-246）：
    // 先存当前滚动位置并回顶，再切换编辑器（S1）。新建备忘
    //（handleNew :275 先存 scrollRestoreRef）与 Wiki 跳转命中
    //（openWikiTarget 走 openEditor）在原版同样先存滚动位置，
    // 故全部入口收敛到这里。
    let open_memo = move |mid: String| {
        // 栈式交接：若有编辑器正在离页（如关闭后快速重开），
        // 先清离页条目并复位 closing——同 id 时槽位实例续用、
        // 异 id 时换键重挂（见 Nav::clear_editor_leaving）。
        nav.clear_editor_leaving();
        let y = web_sys::window()
            .and_then(|w| w.scroll_y().ok())
            .unwrap_or(0.0);
        let mut restore = list_scroll_restore;
        restore.set(y);
        if let Some(w) = web_sys::window() {
            w.scroll_to_with_x_and_y(0.0, 0.0);
        }
        diag::log("APP", &format!("open memo {mid} (list scroll {y:.0} saved)"));
        // 根背景在发起任务内同步先行写入（背景同步根治）：等
        // 渲染/effect 派生在慢设备上分帧时，顶底带会先闪根色；
        // 这里与 App 派生同口径先写同值，effect 随后重申无变化。
        let bgc = data
            .read()
            .memos
            .iter()
            .find(|m| m.id.to_string() == mid)
            .map(|m| {
                m.extra
                    .get("bgColor")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
            });
        if let Some(bgc) = bgc {
            // 先行值即该篇有效背景，与 App 派生同值（派
            // 生已是页面状态纯函数，见根色模型注）。
            let t = editor::effective_bg(&bgc);
            apply_root_bg(Some(&t));
        }
        let mut sel = selected;
        sel.set(Some(mid));
    };

    rsx! {
        document::Style { {CSS} }
        div { class: "page-current",
            if *page.read() == "diag" {
                DiagView { closing: closing_name == Some("diag"), on_back: move |_| nav.go_back("settings") }
            } else if *page.read() == "language" {
                LanguageView { closing: closing_name == Some("language"), on_back: move |_| nav.go_back("settings") }
            } else if *page.read() == "backup" {
                settings::BackupView {
                    data,
                    manifest,
                    status,
                    gen,
                    closing: closing_name == Some("backup"),
                    on_back: move |_| nav.go_back("settings"),
                }
            } else if *page.read() == "settings" {
                settings::SettingsView {
                    font_size,
                    closing: closing_name == Some("settings"),
                    on_back: move |_| nav.go_back(""),
                    on_backup: move |_| nav.go("backup"),
                    on_language: move |_| nav.go("language"),
                    on_diag: move |_| nav.go("diag"),
                }
            } else if *page.read() == "image" {
                // 图片页（与设置等页同级）：内容取当前请
                // 求；返回 = 回编辑页，走统一返回导航
                // （go_back）：本页本体出场、提交点翻 page
                // （编辑器槽位随之恢复显示）、清请求、按
                // 进页时存的滚动位双 rAF 恢复编辑器滚动，
                // 全部在 arm_unload 提交任务内完成。
                match img_req.read().clone() {
                    Some(req) => rsx! {
                        ImagePage {
                            req,
                            manifest,
                            closing: closing_name == Some("image"),
                            on_back: move |_| nav.go_back(""),
                        }
                    },
                    None => rsx! {},
                }
            } else if editor_slot.is_none() {
                CompactTitle { scheme_tick, on_open_settings: move |_| nav.go("settings"), compact: is_compact }
                div { class: "page-enter", style: "position:relative;background-color:var(--primary-bg);",
                    header { class: "main-header",
                        div { class: "header-actions" }
                    }
                    div { style: "position:relative;",
                        h1 {
                            class: "page-title",
                            style: "transform:scale({title_scale}) translateY({title_ty}px);opacity:{op_title};visibility:{vis_h};transform-origin:left center;pointer-events:auto;cursor:pointer;display:inline-block;width:fit-content;",
                            onclick: move |_| nav.go("settings"),
                            KeyedAvatar { scheme_tick, size: 72 }
                        }
                        SearchCapsule { scheme_tick, search_open, query, compact: is_compact }
                    }
                    div { class: "container",
                        div { class: "list-group",
                            list::NewCard {
                                on_new: move |_| {
                                    let now = js_sys::Date::now() as i64;
                                    // 首段必须带 id（与 editor::gen_id 同
                                    // 配方）：无 id 时桥消息的 bid 为空、
                                    // find_loc 永不命中，拆合/撤销焦点
                                    // 恢复在新备忘首段上整体失效。
                                    let first_bid = format!("b{:x}", (js_sys::Math::random() * 1e12) as u64);
                                    let memo = Memo {
                                        id: mynote_core::model::Id::Num(now),
                                        title: None,
                                        pinned: None,
                                        created_at: mynote_core::model::Timestamp::Millis(now),
                                        updated_at: mynote_core::model::Timestamp::Millis(now),
                                        doc: vec![mynote_core::Node {
                                            text: None,
                                            node_type: Some("paragraph".to_string()),
                                            id: Some(first_bid),
                                            children: Some(vec![mynote_core::Node {
                                                text: Some(String::new()),
                                                node_type: None,
                                                id: None,
                                                children: None,
                                                extra: Default::default(),
                                            }]),
                                            extra: Default::default(),
                                        }],
                                        extra: Default::default(),
                                    };
                                    let mut backup = data.read().clone();
                                    backup.memos.push(memo);
                                    data.set(backup.clone());
                                    new_ids.write().insert(now.to_string());
                                    diag::log("APP", &format!("new memo id={now}"));
                                    persist(backup);
                                    open_memo(now.to_string());
                                },
                            }
                        }
                        if all_count == 0 {
                            div { class: "empty-tip", "{i18n::t(\"list.empty_tip\")}" }
                        }
                        for group in groups.iter() {
                            div { key: "g-{group.label}",
                                div { class: "section-header", "{group.label}" }
                                {
                                    let render_sub = |kind: &'static str, sub: Vec<Memo>| {
                                        if sub.is_empty() {
                                            return rsx! {};
                                        }
                                        let fold_key = format!("{}-{}", group.label, kind);
                                        let is_expanded = expanded.read().contains(&fold_key);
                                        let total = sub.len();
                                        let collapsed = total > 2 && !is_expanded;
                                        rsx! {
                                            div { class: "list-group",
                                                if collapsed {
                                                    // 折叠态点首卡 = 展开该组（原版
                                                    // memo-list.js 折叠段：文本行
                                                    // onOpen 为空操作、仅 wrapper
                                                    // 单次 toggle 展开）。此前
                                                    // wrapper 的 toggle 与 MemoRow
                                                    // on_open 的 insert 对同一次
                                                    // 点击各翻一次互相抵消成死
                                                    // 点击；现只保留 on_open 的
                                                    // insert 一条路径，wrapper
                                                    // 不再挂 onclick。
                                                    div {
                                                        class: "card-expand-wrapper",
                                                        list::MemoRow {
                                                            memo: sub[0].clone(),
                                                            expand_text: Some(i18n::tf("list.expand_n", &[("n", &total.to_string())])),
                                                            on_open: {
                                                                let fold_key = fold_key.clone();
                                                                move |_| {
                                                                    let mut s = expanded.read().clone();
                                                                    s.insert(fold_key.clone());
                                                                    expanded.set(s);
                                                                }
                                                            },
                                                            on_pin: move |mid: String| {
                                                                let mut backup = data.read().clone();
                                                                if let Some(m) = backup.memos.iter_mut().find(|m| m.id.to_string() == mid) {
                                                                    let cur = m.pinned.unwrap_or(false);
                                                                    m.pinned = Some(!cur);
                                                                    // 原版 togglePin（memo-list.js:302-308）：
                                                                    // 翻 pinned 的同时刷新 updatedAt，
                                                                    // 组内排序与落库口径随之对齐
                                                                    m.updated_at = mynote_core::model::Timestamp::Iso(
                                                                        js_sys::Date::new_0().to_iso_string().as_string().unwrap_or_default(),
                                                                    );
                                                                }
                                                                data.set(backup.clone());
                                                                diag::log("APP", &format!("pin toggle {mid}"));
                                                                persist(backup);
                                                            },
                                                            on_delete: move |mid: String| {
                                                                let mut backup = data.read().clone();
                                                                backup.memos.retain(|m| m.id.to_string() != mid);
                                                                data.set(backup.clone());
                                                                diag::log("APP", &format!("delete memo {mid} (swipe)"));
                                                                persist(backup);
                                                            },
                                                            on_expand: {
                                                                let fold_key = fold_key.clone();
                                                                move |_| {
                                                                    let mut s = expanded.read().clone();
                                                                    if !s.remove(&fold_key) { s.insert(fold_key.clone()); }
                                                                    expanded.set(s);
                                                                }
                                                            },
                                                            gen,
                                                            manifest,
                                                        }
                                                    }
                                                } else {
                                                    for (i, memo) in sub.iter().enumerate() {
                                                        list::MemoRow {
                                                            memo: memo.clone(),
                                                            key: "{memo.id}",
                                                            expand_text: if total > 2 && i == total - 1 { Some(i18n::t("list.collapse")) } else { None },
                                                            on_open: move |mid: String| open_memo(mid),
                                                            on_pin: move |mid: String| {
                                                                let mut backup = data.read().clone();
                                                                if let Some(m) = backup.memos.iter_mut().find(|m| m.id.to_string() == mid) {
                                                                    let cur = m.pinned.unwrap_or(false);
                                                                    m.pinned = Some(!cur);
                                                                    // 原版 togglePin（memo-list.js:302-308）：
                                                                    // 翻 pinned 的同时刷新 updatedAt，
                                                                    // 组内排序与落库口径随之对齐
                                                                    m.updated_at = mynote_core::model::Timestamp::Iso(
                                                                        js_sys::Date::new_0().to_iso_string().as_string().unwrap_or_default(),
                                                                    );
                                                                }
                                                                data.set(backup.clone());
                                                                diag::log("APP", &format!("pin toggle {mid}"));
                                                                persist(backup);
                                                            },
                                                            on_delete: move |mid: String| {
                                                                let mut backup = data.read().clone();
                                                                backup.memos.retain(|m| m.id.to_string() != mid);
                                                                data.set(backup.clone());
                                                                diag::log("APP", &format!("delete memo {mid} (swipe)"));
                                                                persist(backup);
                                                            },
                                                            on_expand: {
                                                                let fold_key = fold_key.clone();
                                                                move |_| {
                                                                    let mut s = expanded.read().clone();
                                                                    if !s.remove(&fold_key) { s.insert(fold_key.clone()); }
                                                                    expanded.set(s);
                                                                }
                                                            },
                                                            gen,
                                                            manifest,
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    };
                                    rsx! {
                                        {render_sub("img", group.images.clone())}
                                        if !group.images.is_empty() && !group.texts.is_empty() {
                                            div { class: "gap-16" }
                                        }
                                        {render_sub("txt", group.texts.clone())}
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // 编辑器槽位：当前与离页共用同一位置——关闭时实例
        // 不卸载，App 翻 closing 在槽位内以当前页身份在流
        // 内播出场（.editor-stage.leaving 仅标离页态、不再
        // 切 fixed 下层；串行同帧交换，见 Nav 注释），计时
        // 到点才真正卸载、列表同帧挂载。链内不再有编辑器
        // 分支：编辑器打开时 .page-current 的 if/else 链无
        // 分支命中、自然落空；离页窗口内槽位在场、列表分
        // 支同样不命中，文档只有编辑器一层（基线形态）。
        // 实例身份 = 备忘 id（键控重挂，wiki 换篇数据损坏根
        // 治）：Editor 落在单元素键控迭代内——模板静态位置
        // 的 key 不参与组件 diff（dioxus-core 对模板动态节
        // 点按下标 + render_fn 判定、换 prop 只重渲不重挂，
        // CompactTitle 处有同款实证），只有迭代子节点按 key
        // 匹配。此前静态位置渲染时，编辑器内换篇（wiki/反
        // 链经 open_memo 改 selected）只把 prop 换成新 id，
        // 旧实例的 doc/title 等挂载期状态仍属旧篇，persist
        // 遂以新 id 写旧内容、覆盖目标篇存量（实证损坏）。
        // 键 = 备忘 id：同 id（含离页留槽、关闭后快速重开
        // 同篇）键不变、实例续用、会话状态不丢；异 id 键变
        // 即卸旧挂新，状态生命周期与备忘身份严格绑定。卸
        // 挂次序无双注册窗口：旧作用域在 diff 内被同步
        // drop（use_drop 同步直调 sync_editor_cleanup 摘桥
        // 全局登记），新实例的桥安装在提交后 effect 才跑、
        // 且安装入口先调上一代清理——任意时刻至多一套桥
        // 监听存活。
        if let Some(slot_id) = editor_slot.clone() {
            div {
                class: if editor_is_leaving { "editor-stage leaving" } else { "editor-stage" },
                // 图片页在场时隐藏编辑器槽位：.page-current
                // 与 stage 是同级流内兄弟（页在前、编辑器在
                // 后同流排布），图片页须独占文档流与窗口滚
                // 动，故显式隐藏而非任编辑器随流排在其下。
                // 实例不卸载——编辑状态/会话/桥监听全部保
                // 留，返回时恢复显示与滚动位（进页 effect
                // 存位、返回处理恢复）。
                style: if *page.read() == "image" { "display:none;" } else { "" },
                div {
                    for sid in std::iter::once(slot_id) {
                        editor::Editor {
                            key: "{sid}",
                            memo_id: sid.clone(),
                            data,
                            manifest,
                            gen,
                            is_new: new_ids.read().contains(&sid),
                            closing: *editor_closing.read(),
                            on_close: {
                                let close_id = sid.clone();
                                move |_| {
                                    new_ids.write().remove(&close_id);
                                    // 串行同帧交换 + 提交点后移：登记
                                    // 离页条目并翻 closing——本实例留
                                    // 在槽位内以当前页身份在流内播
                                    // slideOut，列表不在窗口内预挂载；
                                    // selected 不在此清除、根色不在此
                                    // 撤除——页面状态在离页窗口内仍为
                                    // 编辑器（派生继续给编辑底、与本
                                    // 实例自有底同值），清除与卸载由
                                    // Nav 卸载计时在提交帧同一任务完
                                    // 成（见 Nav 提交语义）。列表滚动
                                    // 恢复值随条目登记、提交点由
                                    // arm_unload 双 rAF 执行（基线时
                                    // 序）：窗口内文档只有在流内的编
                                    // 辑器，此处先行恢复会拽动编辑器
                                    // 自身（旧重叠形态下进入层须在窗
                                    // 口内落位才先行，已随串行退役）。
                                    let saved = *list_scroll_restore.read();
                                    nav.begin_editor_leaving(&close_id, saved);
                            }
                        },
                        on_open_wiki: move |target: String| {
                            // 原版 openWikiTarget：剥 # → trim → 第一篇
                            // 标题全等者打开；未命中 → 新建同名备忘并打开
                            let requested = target.split('#').next().unwrap_or("").trim().to_string();
                            if requested.is_empty() {
                                return;
                            }
                            let key = requested.to_lowercase();
                            let hit = data
                                .read()
                                .memos
                                .iter()
                                .find(|m| {
                                    m.title.as_deref().unwrap_or("").trim().to_lowercase() == key
                                })
                                .map(|m| m.id.to_string());
                            if let Some(id) = hit {
                                diag::log("WIKI", &format!("open '{requested}' -> {id}"));
                                open_memo(id);
                            } else {
                                let now = js_sys::Date::now() as i64;
                                let memo = Memo {
                                    id: mynote_core::model::Id::Num(now),
                                    title: Some(requested.clone()),
                                    pinned: None,
                                    created_at: mynote_core::model::Timestamp::Millis(now),
                                    updated_at: mynote_core::model::Timestamp::Millis(now),
                                    doc: vec![mynote_core::Node {
                                        text: None,
                                        node_type: Some("paragraph".to_string()),
                                        id: None,
                                        children: Some(vec![mynote_core::Node {
                                            text: Some(String::new()),
                                            node_type: None,
                                            id: None,
                                            children: None,
                                            extra: Default::default(),
                                        }]),
                                        extra: Default::default(),
                                    }],
                                    extra: Default::default(),
                                };
                                let mut backup = data.read().clone();
                                backup.memos.push(memo);
                                data.set(backup.clone());
                                new_ids.write().insert(now.to_string());
                                diag::log("WIKI", &format!("create '{requested}' id={now}"));
                                persist(backup);
                                open_memo(now.to_string());
                            }
                            },
                        }
                    }
                }
            }
        }
        // 错误徽章（原版 error-boundary 浮层，审计 E-1）：全
        // 局浮层挂 App 根、与页面同级，有条目才渲染（见
        // errbadge.rs）。
        errbadge::ErrorBadge {}
    }
}

/// 子页面页头（原版功能页共用：editor-fab 返回 + 紧凑标题胶囊）。
#[component]
fn PageHead(title: String, on_back: EventHandler<()>) -> Element {
    rsx! {
        button {
            class: "editor-fab left",
            onclick: move |_| on_back.call(()),
            span { dangerous_inner_html: "{icons::back_markup()}" }
        }
        div {
            class: "page-title compact",
            style: "visibility:visible;opacity:1;pointer-events:none;",
            "{title}"
        }
    }
}

/// 图片页（2026-11-24 由编辑页浮层改独立页面，用户拍
/// 板）：与列表/编辑/设置同级——页头复用 PageHead（返
/// 回钮样式/位置、标题位置与其它页一致），标题 = 图
/// 片文件名（按 fileId 查附件清单真实名；无名/无附件
/// 来源时兜底 imgpage.untitled）。图片按自然尺寸 1:1
/// CSS 尺寸渲染（不设 max-width/max-height、不缩
/// 放），页面随文档流滚动（纵向为主、超宽图横向可
/// 滚）。根色与其它页同口径：本页在场时 App 派生为
/// None、回落根页面色。进出打点 IMGPAGE：open 行带
/// 文件名与自然尺寸（图就绪后回读 naturalWidth/
/// Height），close 行在返回钮点击时记（出场态
/// closing 渲染不重复记）。
#[component]
fn ImagePage(
    req: crate::blocks::ImgView,
    manifest: Signal<String>,
    closing: bool,
    on_back: EventHandler<()>,
) -> Element {
    let title = crate::blocks::att_name_in_manifest(
        &manifest.read(),
        req.file_id.as_deref().unwrap_or(""),
    )
    .filter(|s| !s.trim().is_empty())
    .unwrap_or_else(|| i18n::t("imgpage.untitled"));
    {
        let title = title.clone();
        use_hook(move || {
            if closing {
                return;
            }
            spawn(async move {
                let mut eval = document::eval(
                    "const img = document.querySelector('.img-page-img'); \
                     if (!img) { dioxus.send('none'); } \
                     else if (img.complete && img.naturalWidth > 0) { dioxus.send(img.naturalWidth + 'x' + img.naturalHeight); } \
                     else { img.addEventListener('load', () => dioxus.send(img.naturalWidth + 'x' + img.naturalHeight), { once: true }); \
                            img.addEventListener('error', () => dioxus.send('error'), { once: true }); }",
                );
                if let Ok(nat) = eval.recv::<String>().await {
                    diag::log("IMGPAGE", &format!("open name={title} nat={nat}"));
                }
            });
        });
    }
    let content_class = if closing {
        "page-content page-slide-out img-page-content"
    } else {
        "page-content page-slide-in img-page-content"
    };
    rsx! {
        div { class: "img-page", style: "background:var(--primary-bg);min-height:100vh;",
            PageHead {
                title,
                on_back: move |_| {
                    if !closing {
                        diag::log("IMGPAGE", "close");
                    }
                    on_back.call(());
                },
            }
            div { class: "{content_class}",
                img { class: "img-page-img", src: "{req.src}" }
            }
        }
    }
}

/// 构建戳（批 10 P-D8 环境头用）：页面没有编译期戳，
/// dist/sw.js 里 build.sh 戳入的 VERSION（wasm md5 前
/// 10 位）是唯一出处——取 sw.js 文本解析。离线/解析失
/// 败记 unknown，不挡复制。
async fn fetch_build_stamp() -> String {
    let fetch = async {
        let w = web_sys::window()?;
        let resp = JsFuture::from(w.fetch_with_str("sw.js")).await.ok()?;
        let resp: web_sys::Response = resp.dyn_into().ok()?;
        let text = JsFuture::from(resp.text().ok()?).await.ok()?;
        text.as_string()
    };
    if let Some(text) = fetch.await {
        if let Some(start) = text.find("VERSION = '") {
            let rest = &text[start + "VERSION = '".len()..];
            if let Some(end) = rest.find('\'') {
                return rest[..end].to_string();
            }
        }
    }
    "unknown".to_string()
}

#[component]
fn DiagView(
    /// 离页态（Nav::go_back 出场窗口）：根层动画由进场
    /// page-enter 切出场 page-slide-out（本页原为即刻交
    /// 换、无自管出场，收敛后与其它组件页同口径）。
    closing: bool,
    on_back: EventHandler<()>,
) -> Element {
    let mut text = use_signal(|| diag::lines().join("\n"));
    rsx! {
        div { class: if closing { "page-slide-out" } else { "page-enter" }, style: "background:var(--primary-bg);min-height:100vh;",
            PageHead { title: i18n::t("diag.title"), on_back }
            div { class: "page-content",
                div { class: "diag-actions",
                    button {
                        class: "backup-btn secondary",
                        onclick: move |_| text.set(diag::lines().join("\n")),
                        "{i18n::t(\"diag.refresh\")}"
                    }
                    button {
                        class: "backup-btn secondary",
                        onclick: move |_| {
                            spawn(async move {
                                // 复制物首行前置环境头（批 10
                                // P-D8）：构建戳/语言包/UA/视
                                // 口/方案，贴回时可还原现场。
                                let stamp = fetch_build_stamp().await;
                                let header = diag::env_header(&stamp, &i18n::current());
                                let all = format!("{header}\n{}", diag::lines().join("\n"));
                                if let Some(nav) = web_sys::window().map(|w| w.navigator()) {
                                    let _ = JsFuture::from(nav.clipboard().write_text(&all)).await;
                                }
                            });
                        },
                        "{i18n::t(\"diag.copy_all\")}"
                    }
                    button {
                        class: "backup-btn secondary",
                        onclick: move |_| {
                            diag::clear();
                            diag::log("DIAG", "cleared");
                            text.set(diag::lines().join("\n"));
                        },
                        "{i18n::t(\"diag.clear\")}"
                    }
                }
                div { class: "diag-body", "{text}" }
            }
        }
    }
}

/// 语言设置（仿 Telegram）：点选语言 → 按需下载语言包 →
/// 立即应用；内置 zh-CN 不需下载；已下载的包缓存在本机。
/// 行结构沿用原版设置页的 .list-item。
#[component]
fn LanguageView(
    /// 离页态（Nav::go_back 出场窗口），语义同 DiagView 的 closing。
    closing: bool,
    on_back: EventHandler<()>,
) -> Element {
    let mut busy = use_signal(|| Option::<String>::None);
    let mut failed = use_signal(|| false);
    let cur = i18n::current();
    rsx! {
        div { class: if closing { "page-slide-out" } else { "page-enter" }, style: "background:var(--primary-bg);min-height:100vh;",
            PageHead { title: i18n::t("lang.title"), on_back }
            div { class: "page-content",
                div { class: "list-group",
                    for lang in i18n::LANGS {
                        {
                            let code = lang.code.to_string();
                            let is_cur = code == cur;
                            let state = if is_cur {
                                i18n::t("lang.active")
                            } else if busy.read().as_deref() == Some(code.as_str()) {
                                i18n::t("lang.downloading")
                            } else if code == i18n::DEFAULT_LANG {
                                i18n::t("lang.builtin")
                            } else if i18n::is_downloaded(&code) {
                                i18n::t("lang.downloaded")
                            } else {
                                i18n::t("lang.download")
                            };
                            rsx! {
                                div {
                                    class: "list-item",
                                    key: "{code}",
                                    onclick: {
                                        let code = code.clone();
                                        move |_| {
                                            if i18n::current() == code {
                                                return;
                                            }
                                            failed.set(false);
                                            busy.set(Some(code.clone()));
                                            let code2 = code.clone();
                                            spawn(async move {
                                                match i18n::apply_lang(&code2).await {
                                                    Ok(()) => busy.set(None),
                                                    Err(e) => {
                                                        diag::log("LANG", &format!("apply {code2} failed: {e}"));
                                                        busy.set(None);
                                                        failed.set(true);
                                                    }
                                                }
                                            });
                                        }
                                    },
                                    div { class: "item-left",
                                        div { class: "item-title",
                                            span { class: "item-title-text", style: "max-width:100%;", "{lang.native}" }
                                        }
                                        div { class: "item-meta", "{lang.english}" }
                                    }
                                    div { class: if is_cur { "lang-state cur" } else { "lang-state" }, "{state}" }
                                }
                            }
                        }
                    }
                }
                if *failed.read() {
                    div { class: "empty-tip", "{i18n::t(\"lang.failed\")}" }
                }
            }
        }
    }
}
