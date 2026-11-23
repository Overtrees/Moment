//! 此刻 · Rust Web（Dioxus / DOM 路线）：
//! 真实数据闭环——备份 ZIP 导入（core 校验）→ IndexedDB 持久
//! → 列表/搜索 → 块编辑器 → 备份 ZIP 导出。
//! 首次打开以真实样本数据播种，导入后全量替换（原版恢复语义）。
//! 页面结构与度量对原版逐项复刻（见各模块注释）。

mod backup;
mod blocks;
mod diag;
mod editor;
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
fn CompactTitle(scheme_tick: Signal<u32>, mut page: Signal<&'static str>, compact: bool) -> Element {
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
                onclick: move |_| page.set("settings"),
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

/// 根背景单次写入（web_sys 同步直调，无异步面）：把当前页面
/// 背景写成 :root 上的 CSS 变量 --mn-root-bg（及供顶部渐变层
/// 消费的 --mn-root-rgb 三元组）。html/body 的 background-color
/// 与 body::before 渐变全部只消费这组变量（base.css /
/// #body-before-bg）——颜色源只有一个、写入只有一处，各层在
/// 同一帧生效，不存在逐层重绘的时序差（背景色同步根治）。
/// None = 撤变量，各层回落 var(--primary-bg)（根页面色）。
/// 调用方：App 派生 effect（权威/兜底：页面状态一变必然重派
/// 生，无清理步可失效）+ 各转变的发起任务同步先行写入同一值
/// （打开备忘 open_memo、关闭 on_close、编辑页换色 set_bg、
/// 深浅切换的编辑器 scheme 处理）——发起任务里先写、渲染与
/// effect 随后重申同值，慢设备上渲染分帧也不会闪旧色。
pub(crate) fn apply_root_bg(color: Option<&str>) {
    let Some(w) = web_sys::window() else { return };
    let Some(d) = w.document() else { return };
    let Some(el) = d.document_element() else { return };
    let Ok(html) = el.dyn_into::<web_sys::HtmlElement>() else {
        return;
    };
    let style = html.style();
    match color {
        Some(c) => {
            let _ = style.set_property("--mn-root-bg", c);
            match color_to_rgb_triplet(c) {
                Some(t) => {
                    let _ = style.set_property("--mn-root-rgb", &t);
                }
                None => {
                    let _ = style.remove_property("--mn-root-rgb");
                }
            }
        }
        None => {
            let _ = style.remove_property("--mn-root-bg");
            let _ = style.remove_property("--mn-root-rgb");
        }
    }
}

/// 当前 --primary-bg 的计算值（:root 令牌，深浅随系统）：根色
/// 派生在压暗生效且页面 base 为「回落根页面色」时以它为 base
/// 求等效实色——与 CSS 回落同一色源，不另立常量。
fn primary_bg_value() -> Option<String> {
    let w = web_sys::window()?;
    let el = w.document()?.document_element()?;
    let cs = w.get_computed_style(&el).ok()??;
    let v = cs.get_property_value("--primary-bg").ok()?;
    let v = v.trim().to_string();
    if v.is_empty() {
        None
    } else {
        Some(v)
    }
}

/// 颜色向黑混合：channel' = round(channel × (1−α))，与
/// rgba(0,0,0,α) 的 scrim 叠在该底色上的合成结果同值；输出
/// #rrggbb。解析失败返回 None（调用方回退未压暗值并记 Diag）。
fn dim_toward_black(color: &str, alpha: f64) -> Option<String> {
    let t = color_to_rgb_triplet(color)?;
    let mut it = t.split(',').map(|p| p.trim().parse::<f64>());
    let (r, g, b) = (it.next()?.ok()?, it.next()?.ok()?, it.next()?.ok()?);
    let k = 1.0 - alpha.clamp(0.0, 1.0);
    Some(format!(
        "#{:02x}{:02x}{:02x}",
        (r * k).round() as u8,
        (g * k).round() as u8,
        (b * k).round() as u8
    ))
}

/// 模态压暗栈（App 层 context 提供）：全站真压暗层（备份确认
/// 模态 α0.28、灯箱 α0.88）挂载时入栈、卸载时出栈；App 的根色
/// 派生 effect 读栈，栈非空时把根色向黑按栈内最大 α 混合成
/// 等效实色再写入 --mn-root-bg。缘由：视口内压暗由 scrim 自行
/// 绘制，视口外（布局视口下缘以下）只能由浏览器以根（html）
/// 背景绘制——根色不跟随压暗，模态一开底部就露出一条未压暗
/// 的实心原色栏（真机量测定案：条带 = 根色原值、压暗面 =
/// 根色 ×(1−0.28)、分界恰在布局视口下缘）。压暗呈现本身不
/// 改，只补根色同步缺失的这一路输入。
#[derive(Clone, Copy)]
pub struct DimStack(pub Signal<Vec<f64>>);

impl DimStack {
    fn push(&mut self, alpha: f64, tag: &str) {
        self.0.write().push(alpha);
        diag::log(
            "APP",
            &format!("dim push {tag} a={alpha} depth={}", self.0.read().len()),
        );
    }

    fn pop(&mut self, alpha: f64, tag: &str) {
        {
            let mut v = self.0.write();
            if let Some(pos) = v.iter().rposition(|a| (*a - alpha).abs() < 1e-9) {
                v.remove(pos);
            }
        }
        diag::log(
            "APP",
            &format!("dim pop {tag} a={alpha} depth={}", self.0.read().len()),
        );
    }
}

/// 压暗登记守卫：构造即入栈、Drop 即出栈，全同步无异步面。
/// 由 DimLayer 以 use_hook 持有——组件卸载时 hook 状态同步
/// 析构；不走 spawn 内 use_drop（本仓有清理任务随作用域取消、
/// 永不执行的前科，见根色派生注释）。
struct DimGuard {
    stack: DimStack,
    alpha: f64,
    tag: &'static str,
}

impl DimGuard {
    fn new(mut stack: DimStack, alpha: f64, tag: &'static str) -> Self {
        stack.push(alpha, tag);
        Self { stack, alpha, tag }
    }
}

impl Drop for DimGuard {
    fn drop(&mut self) {
        self.stack.pop(self.alpha, self.tag);
    }
}

/// 压暗登记组件：与真压暗层同挂载/同卸载（放在其条件渲染块
/// 内），把该层 α 登记进 DimStack。自身不渲染任何节点。
#[component]
pub(crate) fn DimLayer(alpha: f64, tag: &'static str) -> Element {
    let stack = use_context::<DimStack>();
    let _guard = use_hook(|| std::rc::Rc::new(DimGuard::new(stack, alpha, tag)));
    rsx! {}
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

/// 首次播种 = 原版内置示例数据（demo-memos.js 的数据口径移植：
/// 同标题、同正文、同结构；时间按原版相对今天生成——今天 /
/// 昨天 / 3 天前 / 7 天前 / 14 天前；heading 的 level 与 todo
/// 的 checked 按原版节点工厂放 attrs）。原先的静态样本是真实
/// 备忘的骨架（正文为空、图片附件无字节），首屏会出现一整张
/// 空白图片卡，与原版首屏完全两样，故废弃。
fn sample_data() -> BackupFile {
    let now = js_sys::Date::now() as i64;
    let day: i64 = 86_400_000;
    let p = |id: &str, text: &str| {
        serde_json::json!({ "id": id, "type": "paragraph",
            "children": [{ "text": text }] })
    };
    let v = serde_json::json!({
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
    serde_json::from_value(v).expect("demo seed must parse")
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
    let mut page = use_signal(|| "");
    // 折叠展开的子组集合（键 "{label}-img" / "{label}-txt"，原版口径）
    let mut expanded = use_signal(HashSet::<String>::new);
    // 列表滚动位置（驱动标题收缩与紧凑胶囊，原版 TITLE_THRESHOLD=30）
    let mut scroll_y = use_signal(|| 0f64);
    // 列表滚动保存槽（原版 scrollRestoreRef，memo-list.js:184）：
    // 打开备忘前存当前 scrollY 并回顶，关闭时双 rAF 恢复（S1）。
    let mut list_scroll_restore = use_signal(|| 0f64);
    let mut search_open = use_signal(|| false);
    use_hook(spawn_safe_probe);
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
    // 状态 = :root 上的 --mn-root-bg 变量，在此按当前页面状态
    // 响应式派生——编辑页打开（page 空且有选中备忘，与渲染
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
    // 派生输入另含模态压暗栈（DimStack，定义见 apply_root_bg
    // 后）：真压暗层在场时根色须压成等效实色，否则视口外由浏
    // 览器以根背景绘制的带区露未压暗原色（实心栏定案，见
    // DimStack 注释）。深色 base 为 #000 时混合后仍 #000，天
    // 然无副作用。
    let dim_stack = use_signal(|| Vec::<f64>::new());
    use_context_provider(|| DimStack(dim_stack));
    let mut root_bg_last = use_signal(|| Option::<String>::None);
    use_effect(move || {
        let _ = scheme_tick.read();
        let base: Option<String> = if page.read().is_empty() {
            selected.read().clone().and_then(|id| {
                data.read()
                    .memos
                    .iter()
                    .find(|m| m.id.to_string() == id)
                    .map(|m| {
                        let bgc = m
                            .extra
                            .get("bgColor")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string());
                        editor::effective_bg(&bgc)
                    })
            })
        } else {
            None
        };
        // 压暗跟随：栈非空时 base 向黑按栈内最大 α 混合成等效
        // 实色（base 为回落态时以 --primary-bg 计算值为 base，
        // 与 CSS 回落同一色源）；混合解析失败回退未压暗值。
        let alpha = dim_stack.read().iter().copied().fold(0.0f64, f64::max);
        let target: Option<String> = if alpha > 0.0 {
            match base.clone().or_else(primary_bg_value) {
                Some(c) => match dim_toward_black(&c, alpha) {
                    Some(d) => Some(d),
                    None => {
                        diag::log(
                            "APP",
                            &format!("dim mix parse fail base={c} a={alpha}, keep undimmed"),
                        );
                        Some(c)
                    }
                },
                None => {
                    diag::log("APP", &format!("dim active a={alpha} but no base color"));
                    base.clone()
                }
            }
        } else {
            base
        };
        if *root_bg_last.peek() != target {
            diag::log(
                "APP",
                &format!(
                    "root bg -> {}",
                    target.as_deref().unwrap_or("(root default)")
                ),
            );
            root_bg_last.set(target.clone());
        }
        apply_root_bg(target.as_deref());
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
                        Ok(parsed) => {
                            diag::log("APP", &format!("loaded persisted memos={}", parsed.memos.len()));
                            data.set(parsed);
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
    let sel_memo = sel_id.as_ref().and_then(|id| {
        data.read()
            .memos
            .iter()
            .find(|m| m.id.to_string() == *id)
            .cloned()
    });

    // 方案代际（深色切换玻璃根治）：渲染体不再消费 scheme_tick
    // ——四个独立玻璃胶囊（紧凑标题胶囊、标题头像、搜索触发、
    // 搜索面板）各自是边界组件（CompactTitle/KeyedAvatar/
    // SearchCapsule），由其自身订阅代际并重挂载。App 根片段曾
    // 直接挂代际键，翻转时整棵列表子树被连带重挂载、左滑开启
    // 态被重置，故收敛到组件边界；根背景派生仍由上方 effect
    // 消费 scheme_tick，不受影响。

    // scroll_y 只在列表页可见时读取：其他页面滚动不订阅该信号，
    // 不触发 App 重渲染（S5 消费收敛）。
    let list_visible = sel_memo.is_none() && page.read().is_empty();
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
            apply_root_bg(Some(&editor::effective_bg(&bgc)));
        }
        let mut sel = selected;
        sel.set(Some(mid));
    };

    rsx! {
        document::Style { {CSS} }
        div {
            if *page.read() == "diag" {
                DiagView { on_back: move |_| page.set("settings") }
            } else if *page.read() == "language" {
                LanguageView { on_back: move |_| page.set("settings") }
            } else if *page.read() == "backup" {
                settings::BackupView {
                    data,
                    manifest,
                    status,
                    gen,
                    on_back: move |_| page.set("settings"),
                }
            } else if *page.read() == "settings" {
                settings::SettingsView {
                    font_size,
                    on_back: move |_| page.set(""),
                    on_backup: move |_| page.set("backup"),
                    on_language: move |_| page.set("language"),
                    on_diag: move |_| page.set("diag"),
                }
            } else if sel_memo.is_none() {
                CompactTitle { scheme_tick, page, compact: is_compact }
                div { class: "page-enter", style: "position:relative;background-color:var(--primary-bg);",
                    header { class: "main-header",
                        div { class: "header-actions" }
                    }
                    div { style: "position:relative;",
                        h1 {
                            class: "page-title",
                            style: "transform:scale({title_scale}) translateY({title_ty}px);opacity:{op_title};visibility:{vis_h};transform-origin:left center;pointer-events:auto;cursor:pointer;display:inline-block;width:fit-content;",
                            onclick: move |_| page.set("settings"),
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
            } else if let Some(memo) = sel_memo {
                editor::Editor {
                    key: "{memo.id}",
                    memo_id: memo.id.to_string(),
                    data,
                    manifest,
                    gen,
                    is_new: new_ids.read().contains(&memo.id.to_string()),
                    on_close: {
                        let close_id = memo.id.to_string();
                        move |_| {
                            new_ids.write().remove(&close_id);
                            // 根背景与卸载同任务同步撤除（背景同步
                            // 根治）：带区与列表在同一帧回根色，
                            // 不等 effect 派生（其随后重申同值）。
                            apply_root_bg(None);
                            selected.set(None);
                            // 返回列表恢复滚动位置（原版 closeEditor，
                            // memo-list.js:247-258：双 rAF 后 scrollTo
                            // 保存值；保存值为 0 时不处理）（S1）
                            let saved = *list_scroll_restore.read();
                            if saved > 0.0 {
                                diag::log("APP", &format!("close editor, restore list scroll {saved:.0}"));
                                // 双 rAF 恢复走 web_sys 闭包，不用 spawn+eval：
                                // spawn 依附编辑器作用域，本处理器刚把
                                // selected 置 None、编辑器随即卸载，任务被
                                // 取消，恢复永不落地（实测 sy 恒为 0）。
                                if let Some(w) = web_sys::window() {
                                    let w_inner = w.clone();
                                    let inner = wasm_bindgen::closure::Closure::once_into_js(
                                        move || {
                                            w_inner.scroll_to_with_x_and_y(0.0, saved);
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

#[component]
fn DiagView(on_back: EventHandler<()>) -> Element {
    let mut text = use_signal(|| diag::lines().join("\n"));
    rsx! {
        div { class: "page-enter", style: "background:var(--primary-bg);min-height:100vh;",
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
                            let all = diag::lines().join("\n");
                            spawn(async move {
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
fn LanguageView(on_back: EventHandler<()>) -> Element {
    let mut busy = use_signal(|| Option::<String>::None);
    let mut failed = use_signal(|| false);
    let cur = i18n::current();
    rsx! {
        div { class: "page-enter", style: "background:var(--primary-bg);min-height:100vh;",
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
