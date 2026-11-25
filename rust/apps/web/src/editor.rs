//! W2 块编辑器：DOM contenteditable（每块一个，非受控——初始
//! HTML 只写一次，之后的键入完全归浏览器，Dioxus 重渲染不碰
//! 已挂载块的内容）+ JS 桥（回车分块/退格合并/斜杠面板/自动
//! 同步的事件采集与光标数学）+ Rust 侧模型操作（core 的行内
//! HTML 桥做 DOM⇄模型转换）。
//!
//! 拼音安全要点：组合输入期间 JS 桥不拦截任何按键（回车确认
//! 候选词不会被误判为分块）；结构操作的消息都自带块的当前
//! HTML，模型永远以 DOM 为准对齐。
//!
//! 子模块分工：bridge（JS 桥与卸载清理）、cards（链接/音乐
//! 卡解析与音乐输入胶囊）、columns（双栏分界）、export（导
//! 出全链）、title（标题显示口径与静态壳）、title_controller
//! （标题编辑会话的唯一所有者）；本文件留编辑器主体、模型
//! 操作与块渲染。

use dioxus::prelude::*;
use mynote_core::{
    editor_html_to_inlines, inlines_to_editor_html, inlines_to_html, BackupFile, Node,
};
use serde_json::{json, Map, Value};

use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

use crate::blocks::BlockView;
use crate::diag;
use crate::idb;

mod bridge;
mod cards;
mod columns;
mod export;
mod model;
mod ops;
mod render;
mod title;
mod title_controller;

use bridge::{sync_editor_cleanup, EDITOR_JS};
use model::{
    clear_type_fields, editable_units, empty_text_node, ensure_ids, find_loc, first_editable_id,
    flow_runs, inlines_len, is_atomic_class, is_empty_para, is_text_block,
    list_start, materialize_trails, new_block, next_is_empty_para, node_at, node_at_mut,
    normalize_inline_forms, orig_char_count, placeholder_shows, plain_len, remove_start_field,
    set_attr, set_list_start, shift_list_start, split_inlines_at, text_node, FlowRun, Loc,
};
use ops::{
    apply_smart_prefix, apply_sync_map, b64_decode, handle_media_files, hist_push, op_convert,
    op_insert_media_placeholder, op_merge, op_move_block, op_paste_card, op_paste_text,
    op_replace_range, op_split, smart_prefix_match, step_redo, step_undo, HistSnap,
};
use render::{slash_record_recent, EditorBlock, MergedListPreview, SlashPanel};
use export::{
    animate_export_close, begin_export_open, collect_export_assets, collect_export_files,
    doc_to_html, download_text, export_char_count, export_filename, memo_to_markdown,
    settle_export_on_resume, time_label, EXPORT_ANIM_CLOSING, EXPORT_ANIM_IDLE,
};
use cards::{op_music_input, spawn_resolve_card};
use columns::{canonical_boundary, column_boundary, normalize_boundary};
use title::{blur_title_if_focused, TitleCapsule};

/// 行内斜杠命令：不改块类型，由 JS 桥对选区就地执行。
const INLINE_ACTS: &[&str] = &["bold", "italic", "highlight", "code", "strikethrough"];

/// 媒体文件请求：斜杠「图片/画廊」替换当前块，或给图文块换图。
#[derive(Clone, PartialEq)]
pub(crate) enum MediaReq {
    Replace { bid: String, gallery: bool },
    SetImage { bid: String },
    /// 卡片编辑态点画廊格换单图（index=Some，保图库的表示
    /// 形态）/ 点空态占位格追加所选（index=None）。
    GalleryPick { bid: String, index: Option<usize> },
}

/// 历史快照压栈：与栈顶不同才压（截断重做尾，上限 50）。
fn perf_now_ms() -> f64 {
    js_sys::Date::now()
}

thread_local! {
    /// 批 4 笔 2：inputSync Diag 节流状态——(上次记行时刻
    /// ms, 累计已应用爆发数)。5s 窗口至多记一行，行内带
    /// 累计数，供探针断言与后续性能定级读取。
    static INPUT_SYNC_DIAG: std::cell::Cell<(f64, u64)> =
        std::cell::Cell::new((0.0, 0));
}

/// 当前备忘的 layout 快照（压栈/基线/分叉判定共用读口）。
fn memo_layout_json(data: &BackupFile, memo_id: &str) -> Option<String> {
    data.memos
        .iter()
        .find(|m| m.id.to_string() == memo_id)
        .and_then(|m| m.extra.get("layout"))
        .map(|v| v.to_string())
}

/// 把 layout 快照写回总数据（撤销/重做恢复）：None 移除
/// 锚、回到无锚规范分界。写后由调用方 persist 一并落盘
/// （build_backup 保留 extra，layout 随之持久化）。
fn apply_memo_layout(data: &mut Signal<BackupFile>, memo_id: &str, layout: Option<&str>) {
    let mut backup = data.read().clone();
    if let Some(m) = backup
        .memos
        .iter_mut()
        .find(|m| m.id.to_string() == memo_id)
    {
        match layout {
            Some(s) => {
                if let Ok(v) = serde_json::from_str::<Value>(s) {
                    m.extra.insert("layout".to_string(), v);
                }
            }
            None => {
                m.extra.remove("layout");
            }
        }
    }
    data.set(backup);
}

/// 撤销/重做后恢复焦点（编辑态审计 D4）：优先回到操作前所在块
/// （偏移按新文档钳制），块已不存在则落到第一个可编辑块。
/// 没有这一步，epoch 整体重挂载后 activeElement 落到 BODY，
/// 后续打字无处落点。
fn restore_focus(
    doc: &[Node],
    focus_req: &mut Signal<Option<(String, usize)>>,
    focus: Option<(String, usize)>,
) {
    if let Some((bid, off)) = focus {
        if let Some(loc) = find_loc(doc, &bid) {
            let len = plain_len(node_at(doc, loc));
            focus_req.set(Some((bid, off.min(len))));
            return;
        }
    }
    if let Some(bid) = first_editable_id(doc) {
        focus_req.set(Some((bid, 0)));
    }
}

/// 把标题+文档合并进总数据（persist 与离开路径共用）。
/// 一致性守卫（纵深防御）：doc/title 是 Editor 实例的挂载
/// 期状态、只归属其加载 id（state_owner）；写目标 memo_id
/// 与之不一致即拒写、记 Diag 并返回 None——实例身份本由
/// App 槽位键控重挂绑定备忘 id（main.rs），正常路径两者
/// 恒等、守卫永不触发；它拦的是「prop 换 id 而状态未换」
/// 类回归以新 id 写旧内容覆盖目标篇存量的损坏模式（曾实
/// 证）。调用方收到 None 须整笔跳过落盘（离开路径只跳保
/// 存、不拦退出）。目标篇不在 data 中时维持旧口径：合并
/// 无处落点、原样返回（留槽渲染等场景的空写无副作用）。
fn build_backup(
    data: Signal<BackupFile>,
    memo_id: &str,
    state_owner: &str,
    doc_snapshot: Vec<Node>,
    title_snapshot: String,
) -> Option<BackupFile> {
    if memo_id != state_owner {
        diag::log(
            "EDIT",
            &format!("persist refused: state owner {state_owner} != target {memo_id}"),
        );
        return None;
    }
    let mut backup = data.read().clone();
    if let Some(m) = backup
        .memos
        .iter_mut()
        .find(|m| m.id.to_string() == memo_id)
    {
        m.title = if title_snapshot.is_empty() {
            None
        } else {
            Some(title_snapshot)
        };
        m.doc = doc_snapshot;
        m.updated_at = mynote_core::model::Timestamp(now_iso());
    }
    Some(backup)
}

async fn save_backup(backup: &BackupFile) {
    match serde_json::to_string(backup) {
        Ok(json) => match idb::save_memos(&json).await {
            Ok(()) => diag::log("EDIT", &format!("save_memos ok {}B", json.len())),
            Err(e) => diag::log("EDIT", &format!("save err: {e:?}")),
        },
        Err(e) => diag::log("EDIT", &format!("serialize err: {e}")),
    }
}

fn now_iso() -> String {
    js_sys::Date::new_0()
        .to_iso_string()
        .as_string()
        .unwrap_or_default()
}

fn now_millis() -> i64 {
    js_sys::Date::now() as i64
}

fn gen_id() -> String {
    let r = js_sys::Math::random();
    format!("b{:x}", (r * 1e12) as u64)
}

/// 深色模式（渲染期读 matchMedia；切换由 scheme_tick 触发重渲染）。
fn is_dark_mode() -> bool {
    web_sys::window()
        .and_then(|w| w.match_media("(prefers-color-scheme: dark)").ok().flatten())
        .map(|m| m.matches())
        .unwrap_or(false)
}

/// 深色下压暗自定义背景（原版 getDarkenedColor：每通道 ×0.35）。
fn darken_hex(hex: &str) -> String {
    let h = hex.trim_start_matches('#');
    if h.len() != 6 || !h.chars().all(|c| c.is_ascii_hexdigit()) {
        return hex.to_string();
    }
    let ch = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0);
    let f = |v: u8| ((v as f32 * 0.35).round() as u8);
    format!("#{:02x}{:02x}{:02x}", f(ch(0)), f(ch(2)), f(ch(4)))
}

/// 拉取链接元数据（原版 fetchLinkMeta：GET Worker /meta?url=，
/// 非 2xx 或解析失败返回 None）。
async fn fetch_link_meta(url: &str) -> Option<serde_json::Value> {
    use wasm_bindgen::JsCast;
    let win = web_sys::window()?;
    let api = format!(
        "https://mynote.overtrees.workers.dev/meta?url={}",
        crate::blocks::url_encode(url)
    );
    let resp_val = wasm_bindgen_futures::JsFuture::from(win.fetch_with_str(&api))
        .await
        .ok()?;
    let resp: web_sys::Response = resp_val.dyn_into().ok()?;
    if !resp.ok() {
        return None;
    }
    let json_val = wasm_bindgen_futures::JsFuture::from(resp.json().ok()?)
        .await
        .ok()?;
    let text = js_sys::JSON::stringify(&json_val)
        .ok()
        .and_then(|s| s.as_string())?;
    serde_json::from_str(&text).ok()
}

/// 编辑器有效背景（原版 editorBg）：自定义色（深色压暗）优先，
/// 否则浅色 #FAFAFA（--color-editor-bg）/ 深色 #000。
/// App 外壳的根背景派生也用它（main.rs 单一写入者），口径必须
/// 只有一个实现。
pub(crate) fn effective_bg(bg: &Option<String>) -> String {
    match bg {
        Some(c) => {
            if is_dark_mode() {
                darken_hex(c)
            } else {
                c.clone()
            }
        }
        None => {
            if is_dark_mode() {
                "#000000".to_string()
            } else {
                "#FAFAFA".to_string()
            }
        }
    }
}

/// 同步武装 md 源码落点守卫（window.__mnFocusAtMount，桥内
/// MutationObserver 守候目标挂载后经 __mnFocus 落末尾，
/// usize::MAX 由其钳到文本长）。必须同步直调而非 spawn
/// eval：MergedListPreview 在编辑态置位后立即卸载，其
/// spawn 任务随组件作用域取消、eval 永不执行（第八批时间
/// 线探针实测 ARM 未达）；EditorBlock 单块入口不卸载故旧
/// spawn 偶能存活。未安装时跳过（桥随编辑器挂载先行安装）。
fn sync_arm_md_focus(bid: &str) {
    let Some(w) = web_sys::window() else { return };
    let wv: &wasm_bindgen::JsValue = w.as_ref();
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnFocusAtMount".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call2(
                wv,
                &wasm_bindgen::JsValue::from_str(bid),
                &wasm_bindgen::JsValue::from_f64(usize::MAX as f64),
            );
        }
    }
}

/// 菜单关闭完成后的去向（浮层出场补齐）：无 / 链式打开
/// 导出面板 / 链式打开背景色底表——原版 openExportPanel
/// 与更换背景菜单项都是「closeEditorMenu 后 220ms 再挂
/// 下一层」，去向在关闭发起时随计时一同排定、完成时消费。
#[derive(Clone, Copy, PartialEq)]
enum MenuAfter {
    None,
    Export,
    Bg,
}

/// 背景色底表关闭完成后的动作（原版 BgSheet
/// closeWithAnim 的 afterClose 口径）：选色/移除在动画播
/// 满、底表卸载时点才生效，不是点击瞬间。
#[derive(Clone, PartialEq)]
enum BgAfter {
    None,
    Apply(Option<String>),
}

/// 编辑菜单关闭动画（原版 closeEditorMenu 口径）：置
/// closing 态让 CSS transition 播满 220ms 再卸载面板；
/// 每次发起递增代际并重排计时（原版 clearTimeout 重启
/// 语义），旧回调按代际自动作废。完成时按 MenuAfter 消
/// 费去向：导出/背景底表在菜单退场后链式打开（原版同
/// 为 220ms 后挂载）。关闭的完成只依赖 setTimeout，不
/// 依赖 rAF（与导出面板代际口径一致）。
#[allow(clippy::too_many_arguments)]
fn animate_menu_close(
    mut menu_open: Signal<bool>,
    mut menu_closing: Signal<bool>,
    mut menu_gen: Signal<u32>,
    after: MenuAfter,
    show_export: Signal<bool>,
    export_closing: Signal<bool>,
    export_gen: Signal<u32>,
    export_anim: Signal<u8>,
    mut bg_open: Signal<bool>,
) {
    if !*menu_open.read() {
        return;
    }
    let gen = *menu_gen.read() + 1;
    menu_gen.set(gen);
    menu_closing.set(true);
    spawn(async move {
        let mut eval = document::eval("setTimeout(() => dioxus.send(null), 220);");
        let _ = eval.recv::<Value>().await;
        if *menu_gen.read() != gen {
            // 已被重排/取消/重开取代，本回调作废
            return;
        }
        menu_closing.set(false);
        match after {
            MenuAfter::None => {
                menu_open.set(false);
                diag::log("EDIT", "menu closed");
            }
            MenuAfter::Export => {
                // menu_open 是整个浮层块（含导出面板）的渲染
                // 总开关（menu_state），此处保持不动、只切
                // show_export——清掉它导出面板永不挂载（实证）。
                begin_export_open(show_export, export_closing, export_gen, export_anim);
            }
            MenuAfter::Bg => {
                menu_open.set(false);
                bg_open.set(true);
                diag::log("EDIT", "menu closed -> bg sheet");
            }
        }
    });
}

/// 取消进行中的菜单关闭（关闭中按 ••• 重开：原版
/// toggleEditorMenu 在 menuClosing 时走 openEditorMenu
/// 清计时）：递增代际让挂起的完成回调作废并撤 closing
/// 态；面板 is-closing 类摘除后进场关键帧重播回终态
/// （原版为 transition 回弹，视觉等价）。
fn cancel_menu_close(mut menu_gen: Signal<u32>, mut menu_closing: Signal<bool>) {
    let gen = *menu_gen.read() + 1;
    menu_gen.set(gen);
    menu_closing.set(false);
}

/// 背景色生效（原 set_bg 的落库半边，现由底表关闭完成
/// 时点调用）：写 memo.extra["bgColor"]、根背景同任务
/// 同步、落库保存。根背景先行值即本篇有效背景，与
/// App 派生同值（派生已是页面状态纯函数，见 main.rs
/// 根色模型注）。
fn apply_bg_color(
    mut data: Signal<BackupFile>,
    mut bg: Signal<Option<String>>,
    memo_id: &str,
    color: Option<String>,
) {
    bg.set(color.clone());
    let mut backup = data.read().clone();
    if let Some(m) = backup
        .memos
        .iter_mut()
        .find(|m| m.id.to_string() == memo_id)
    {
        match &color {
            Some(c) => {
                m.extra
                    .insert("bgColor".to_string(), Value::String(c.clone()));
            }
            None => {
                m.extra.remove("bgColor");
            }
        }
    }
    data.set(backup.clone());
    // 发起任务内同步生效（背景同步根治）：根背景先行
    // 写入，中心/顶带/底带同帧达新色；先行值即本篇有
    // 效背景、与 App 派生同值，派生 effect 随后重申
    // 同值（Diag 的 APP root bg 记录仍是单次派生口
    // 径）。顶部渐变已回落 base.css 基础规则、不消费
    // 根色变量，无同任务刷新可言（改写装置已移除，
    // 见 scheme effect 注）。
    let t = effective_bg(&color);
    let t = t.as_str();
    crate::apply_root_bg(Some(t));
    diag::log("EDIT", &format!("bg -> {color:?}"));
    spawn(async move {
        save_backup(&backup).await;
    });
}

/// 背景色底表关闭动画（原版 BgSheet closeWithAnim 口
/// 径）：置 closing 态（.sheet-wrap.is-closing：opacity
/// 200ms ease + transform 250ms 弹簧 → +20px），220ms
/// 后卸载；选色/移除经 BgAfter::Apply 在完成时点才生
/// 效。重排语义同菜单（代际守卫、旧回调作废）。
#[allow(clippy::too_many_arguments)]
fn animate_bg_close(
    mut bg_open: Signal<bool>,
    mut bg_closing: Signal<bool>,
    mut bg_gen: Signal<u32>,
    after: BgAfter,
    data: Signal<BackupFile>,
    bg: Signal<Option<String>>,
    memo_id: String,
) {
    if !*bg_open.read() {
        return;
    }
    let gen = *bg_gen.read() + 1;
    bg_gen.set(gen);
    bg_closing.set(true);
    // MODAL 量测：关闭发起时点（底表尚在场）记 close 行，
    // 与 scrim onmounted 的 open 行成对；卸载完成行
    // 「bg sheet closed」保留原位。
    diag::log_modal("sheet-bg", "close");
    spawn(async move {
        let mut eval = document::eval("setTimeout(() => dioxus.send(null), 220);");
        let _ = eval.recv::<Value>().await;
        if *bg_gen.read() != gen {
            return;
        }
        bg_open.set(false);
        bg_closing.set(false);
        diag::log("EDIT", "bg sheet closed");
        if let BgAfter::Apply(color) = after {
            apply_bg_color(data, bg, &memo_id, color);
        }
    });
}

/// 图文全文面板关闭动画（原版 ImageTextSheet
/// closeWithAnim 口径）：置 is-closing（backdrop
/// opacity 200ms、wrap opacity 200ms + transform
/// 250ms 弹簧 → +20px），220ms 后卸载。原版以
/// closingRef 守卫：关闭中重复触发直接忽略（不重
/// 排）；完成时校验面板仍是发起时那张（bid 一致）才
/// 卸载，防止误关其间新开的面板。
fn animate_text_sheet_close(
    mut text_sheet: Signal<Option<(String, String)>>,
    mut text_sheet_closing: Signal<bool>,
    mut text_sheet_gen: Signal<u32>,
) {
    if *text_sheet_closing.read() {
        return;
    }
    let Some((bid, _)) = text_sheet.read().clone() else {
        return;
    };
    let gen = *text_sheet_gen.read() + 1;
    text_sheet_gen.set(gen);
    text_sheet_closing.set(true);
    // MODAL 量测：关闭发起时点（底表尚在场）记 close 行，
    // 与 backdrop onmounted 的 open 行成对；卸载完成行
    // 「text sheet closed」保留原位。
    diag::log_modal("sheet-media", "close");
    spawn(async move {
        let mut eval = document::eval("setTimeout(() => dioxus.send(null), 220);");
        let _ = eval.recv::<Value>().await;
        if *text_sheet_gen.read() != gen {
            return;
        }
        text_sheet_closing.set(false);
        if text_sheet
            .read()
            .as_ref()
            .map(|(b, _)| b == &bid)
            .unwrap_or(false)
        {
            // 焦点归还 + 陷阱摘除（原版 closeWithAnim 口径，
            // 审计 D-20）：220ms 到点先摘 Tab 陷阱监听、把
            // 焦点还给触发块的说明文字元素（.itc-text /
            // .itr-text），再卸载；是否真落位由 JS 回传实测
            // 记 Diag（结果侧口径）。
            let bid_js = serde_json::to_string(&bid).unwrap_or_else(|_| "\"\"".to_string());
            let mut feval = document::eval(&format!(
                "if (window.__mnSheetTrap) {{ document.removeEventListener('keydown', window.__mnSheetTrap); window.__mnSheetTrap = null; }} \
                 const wrap = document.querySelector('[data-wrapbid=\"' + {bid_js} + '\"]'); \
                 const cap = wrap && (wrap.querySelector('.itc-text') || wrap.querySelector('.itr-text')); \
                 let ok = 0; \
                 if (cap) {{ try {{ cap.focus({{ preventScroll: true }}); }} catch (_) {{ cap.focus(); }} ok = document.activeElement === cap ? 1 : 0; }} \
                 dioxus.send(ok);"
            ));
            let focused = feval.recv::<i64>().await.unwrap_or(0);
            text_sheet.set(None);
            diag::log(
                "EDIT",
                &format!("text sheet closed focus_return={focused}"),
            );
        }
    });
}

/// PERF（第八批 T2）：反向链接的每渲全库扫描缓存。
/// compute_backlinks 此前在 Editor 每次渲染时对全部备忘
/// 逐篇跑 memo_wiki_targets（三趟 Vec<char> 全文变换）；
/// 300 篇库实测单次 ≈12ms、每次打开至少付两遍（守卫修复
/// 后一遍），键入/滚动等会话内重渲同样反复付。targets 只
/// 由备忘 doc 的「wiki 源文本」（collect_wiki_source 口径
/// 收集、'\n' 拼接）决定，故按该源文本的 FNV-1a 指纹做
/// 会话内缓存：指纹未变的备忘直接复用 targets，指纹变了
/// 才重算——结果与逐次现算逐字一致（顺序、标题、命中集
/// 均不变），Diag 的 backlinks log_once 同口径保留。
fn wiki_source_fingerprint(memo: &mynote_core::model::Memo) -> u64 {
    fn hash_bytes(mut h: u64, bytes: &[u8]) -> u64 {
        for &b in bytes {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        h
    }
    fn walk(node: &Node, h: &mut u64, first: &mut bool) {
        // 与 wiki::collect_wiki_source 同口径：code 类节点
        // 整棵子树跳过（其文本不进源文本、不入指纹）。判定
        // 共用 wiki::is_code_node_type（ASCII 免分配快径，
        // PERF 调优续推：本走查每次渲染对全库执行）。
        if let Some(t) = &node.node_type {
            if crate::wiki::is_code_node_type(t) {
                return;
            }
        }
        if let Some(text) = &node.text {
            if !*first {
                *h = hash_bytes(*h, b"\n");
            }
            *first = false;
            *h = hash_bytes(*h, text.as_bytes());
        }
        if let Some(children) = &node.children {
            for c in children {
                walk(c, h, first);
            }
        }
    }
    let mut h: u64 = 0xcbf29ce484222325;
    let mut first = true;
    for block in &memo.doc {
        walk(block, &mut h, &mut first);
    }
    h
}

type BacklinkCache =
    std::rc::Rc<std::cell::RefCell<std::collections::HashMap<String, (u64, std::collections::HashSet<String>)>>>;

/// compute_backlinks 的缓存等价版：语义/结果与原版逐字一致，
/// 仅把未变化备忘的 targets 提取换成指纹命中复用。
/// PERF（调优续推）：有缓存未命中（真重算）时记一行 PERF
/// 计时（含指纹走查 + 未命中篇的 targets 提取总耗时），
/// 首渲全库扫描的成本从此在 Diag 里可直接读数。
fn backlinks_cached(
    cache: &BacklinkCache,
    memos: &[mynote_core::model::Memo],
    current_id: &str,
    live_title: &str,
) -> Vec<(String, String)> {
    let effective = if live_title.trim() == "无标题" {
        ""
    } else {
        live_title
    };
    let key = crate::wiki::wiki_title_key(effective);
    if key.is_empty() {
        return Vec::new();
    }
    let t_start = js_sys::Date::now();
    let mut misses = 0usize;
    let mut extract_ms = 0.0f64;
    let mut cache = cache.borrow_mut();
    let mut out: Vec<(String, String)> = Vec::new();
    for m in memos {
        let mid = m.id.to_string();
        if mid == current_id {
            continue;
        }
        let fp = wiki_source_fingerprint(m);
        let targets = match cache.get(&mid) {
            Some((cached_fp, targets)) if *cached_fp == fp => targets.clone(),
            _ => {
                misses += 1;
                let t_ex = js_sys::Date::now();
                let targets = crate::wiki::memo_wiki_targets(m);
                extract_ms += js_sys::Date::now() - t_ex;
                cache.insert(mid.clone(), (fp, targets.clone()));
                targets
            }
        };
        if targets.contains(&key) {
            out.push((mid, m.title.clone().unwrap_or_default()));
        }
    }
    if misses > 0 {
        diag::log(
            "PERF",
            &format!(
                "backlinks compute {misses} memo(s) in {:.1}ms (extract {:.1}ms)",
                js_sys::Date::now() - t_start,
                extract_ms
            ),
        );
    }
    diag::log_once(
        &format!("backlinks:{current_id}:{key}:{}", out.len()),
        "WIKI",
        &format!("backlinks '{live_title}' <- {} memo(s)", out.len()),
    );
    out
}

/// 冷开预热（列表页空闲期由 warmup 模块以合成备忘调用）：
/// 预跑打开路径上的纯函数——wiki 源文本指纹走查（编辑器
/// 每渲对全库执行）与双栏分界（规范估高 + 锚归一两条路）。
/// 不触碰编辑器状态、signal 与桥。返回工作量读数。
pub(crate) fn warm_open_pure_paths(memos: &[mynote_core::model::Memo]) -> usize {
    let mut work = 0usize;
    // 合成锚：与 warmup 语料的块 id 对齐（wb1/wb2 左、wb5 起右）
    let layout: serde_json::Value = serde_json::from_str(
        r#"{"left":["wb1","wb2"],"right":["wb5"]}"#,
    )
    .unwrap_or(serde_json::Value::Null);
    for memo in memos {
        work = work.wrapping_add(wiki_source_fingerprint(memo) as usize);
        work += column_boundary(&memo.doc, None);
        work += column_boundary(&memo.doc, Some(&layout));
    }
    work
}

#[component]
pub fn Editor(
    memo_id: String,
    data: Signal<BackupFile>,
    manifest: Signal<String>,
    gen: Signal<u32>,
    on_close: EventHandler<()>,
    on_open_wiki: EventHandler<String>,
    /// 本会话新建的备忘（原版 __isNewNote）：仅它适用「空白
    /// 关闭即删除」，旧备忘清空后退出保留空壳（原版口径）。
    is_new: bool,
    /// 离页态（App 栈式交接）：关闭时本实例不卸载——App 把
    /// 它留在编辑器槽位、翻此 prop 在原地播 slideOut，出场
    /// 时长后由 App 统一卸载。进/出场动画由此 prop 派生
    /// （取代旧内部 page_closing 信号 + go_back 的 320ms
    /// 等待：串行交换下新页挂载长任务冻结进场首帧，见
    /// main.rs Nav 注释）。实例恒以当前态挂载（closing 只在
    /// 关闭后由 App 翻 true），故挂载期读到的恒为 false。
    closing: bool,
) -> Element {
    // 备忘来源：渲染期以 data 现查为准（保存回写、外部变更
    // 即时可见）；挂载首查的快照作回退。回退的唯一现实触发
    // 是空备忘关闭即删除路径：go_back 先 on_close 登记离页、
    // 再 data.set 删备忘（同任务内先后落地），而本实例按
    // #14/③终版设计留槽播出场（main.rs LeavingEditor 明文：
    // 实例靠槽位留存渲染、不依赖 data 查得此备忘）——若查
    // 无即回空模板，离页首帧 #editor-root 就被换成「备忘不
    // 存在」占位、窗口内自有底与内容尽失（probe_page_
    // transitions ④ 实测推翻、Diag close empty memo 序列与
    // 本机 MutationObserver 现场实证）。快照与 state_owner
    // 同口径：实例状态只归属其加载 id、挂载时定格。hook 恒
    // 居组件首行，原先行 return 在全部 hooks 之前（首次查
    // 无时 hooks 从未注册、后再查得才注册）的脆弱形态一并
    // 收掉；首次渲染备忘恒在（打开入口自列表/新建），快照
    // 为 None 仅余防御语义、与旧行为一致。
    let memo_held = use_hook(|| {
        data.read()
            .memos
            .iter()
            .find(|m| m.id.to_string() == memo_id)
            .cloned()
    });
    let memo = data
        .read()
        .memos
        .iter()
        .find(|m| m.id.to_string() == memo_id)
        .cloned()
        .or(memo_held);
    let Some(memo) = memo else {
        return rsx! { div { class: "empty", "{crate::i18n::t(\"editor.missing\")}" } };
    };

    // 待发尾巴恢复命中数（doc 初始化闭包写入、挂载后
    // effect 消费落盘）：跨闭包传值用 Rc<Cell>（同
    // BacklinkCache 的 use_hook 持有口径）。
    let tail_recovered = use_hook(|| std::rc::Rc::new(std::cell::Cell::new(0usize)));
    let tail_cell = tail_recovered.clone();
    let mut doc = use_signal(|| {
        let mut d = memo.doc.clone();
        ensure_ids(&mut d);
        // 待发尾巴恢复（批 4 链尾产品红根治）：卸载前桥
        // 存入保险丝的未落模型键入（启动恢复未覆盖的应
        // 用内卸载场景在此兜底）——与下方三项归一同位、
        // 赶在初始快照与撤销基线之前，恢复内容是打开态
        // 的一部分、不另记撤销步。
        let n_tail = recover_pending_input(&mut d);
        if n_tail > 0 {
            tail_cell.set(n_tail);
            diag::log("EDIT", &format!("pending input recovered x{n_tail} (open)"));
        }
        // 尾随空段在打开时即模型化（原版 init 的 trail_ 推入
        // + ensureTrailing 首次同步入 docRef 的等价终点）；
        // 赶在 initial_doc_json 快照与撤销基线之前，快照口径
        // 与原版一致（尾随段是基础设施，不是用户输入）。
        let n = materialize_trails(&mut d, None);
        if n > 0 {
            diag::log("EDIT", &format!("trail materialized x{n} (open)"));
        }
        // 行内形态归一同位执行（见 normalize_inline_forms）：
        // 存量 bool 块在首次渲染前折成字面形态，会话内不再
        // 出现渲染形态翻转。
        let nb = normalize_inline_forms(&mut d);
        if nb > 0 {
            diag::log("EDIT", &format!("inline normalize x{nb} (open)"));
        }
        // MD-C10 围栏跨块合并同位执行（见 blocks::
        // merge_split_fences）：存量拆段围栏在首次渲染前
        // 并回一段，与原版 collectFenceGroup 的加载口径
        // 等价；赶在初始快照之前（同上两项）。
        let nf = crate::blocks::merge_split_fences(&mut d);
        if nf > 0 {
            diag::log("EDIT", &format!("fence merge x{nf} (open)"));
        }
        d
    });
    let mut title = use_signal(|| memo.title.clone().unwrap_or_default());
    // 原版 hasTyped 的等价追踪：doc/title 任一偏离初始快照即
    // 置位且不回落（打过字再删光也算 typed）。供「空白关闭即
    // 删除」与空占位提示共用。
    // 初始快照必须用 use_hook 锁定挂载值：组件体随每次重渲
    // 染重执行，若在此处直接 read 当前信号，「初始」会随输
    // 入同步漂移，typed 追踪与标题相等判定双双失效（实测：
    // 仅打标题的新备忘关闭时被误判为空而删除；原版
    // initialTitle 取打开时的 memo.title 快照，标题改过即
    // 不算空，见 src/app/editor.js handleClose）。
    let initial_doc_json =
        use_hook(|| serde_json::to_string(&doc.read().clone()).unwrap_or_default()).clone();
    let initial_title = use_hook(|| title.read().clone()).clone();
    // 状态归属 id（挂载锁定，同上两快照口径）：本实例的
    // doc/title 等全部挂载期状态只归属这一 id，persist 守
    // 卫以此校验写目标（见 build_backup）。实例身份由 App
    // 槽位键控重挂绑定备忘 id（main.rs），本值与 memo_id
    // prop 在实例生命内恒等——守卫是纵深防御：任何让 prop
    // 与状态归属分叉的回归都会被拒写，而非以新 id 写旧内
    // 容损坏目标篇存量。
    let state_owner = use_hook(|| memo_id.clone()).clone();
    let mut typed = use_signal(|| false);
    {
        let initial_doc_json = initial_doc_json.clone();
        let initial_title = initial_title.clone();
        use_effect(move || {
            let dj = serde_json::to_string(&doc.read().clone()).unwrap_or_default();
            if dj != initial_doc_json || *title.read() != initial_title {
                typed.set(true);
            }
        });
    }
    let mut panel = use_signal(|| Option::<(String, String, f64, f64, f64)>::None);
    let mut focus_req = use_signal(|| Option::<(String, usize)>::None);
    // 新建备忘自动聚焦首段（原版三层同向：memo-list.js
    // handleNew 在创建手势内同步尝试 focusEditableWithCaret
    // (firstParagraph, 0) 并 rAF 重试；editor.js autoFocus
    // 200ms effect；以及与 autoFocus 无关的 300ms effect——
    // 文档恰为单个空段落的旧备忘打开时同样聚焦首段）。判
    // 定在挂载时用 use_hook 锁定（is_new 或初始文档为单个
    // 空段落），聚焦走既有 focus_req 通道、光标在段首。
    // 只动焦点不动文档：typed 口径与关空备忘删除不受影响。
    let auto_focus_first = use_hook(|| -> Option<String> {
        let d = doc.read();
        let single_empty = d.len() == 1
            && d[0].block_type() == Some("paragraph")
            && d[0].plain_text().is_empty();
        if is_new || single_empty {
            d.iter()
                .find(|n| n.block_type() == Some("paragraph"))
                .and_then(|n| n.id.clone())
        } else {
            None
        }
    });
    {
        let target = auto_focus_first.clone();
        use_effect(move || {
            if let Some(fid) = target.clone() {
                // 桥（EDITOR_JS）由挂载 effect 异步安装，
                // __mnFocus 未就绪时直接调用会被空转；原版
                // 同策略（同步尝试 + rAF 重试 + 延时 effect
                // 兜底）：eval 内轮询就绪后直接聚焦并回传
                // 结果（上限 2s），不走 focus_req 以免被其
                // 消费时序吞掉。
                spawn(async move {
                    // PERF（调优续推）：原版策略本就是「同步尝试 +
                    // rAF 重试」；此前实现只有 50ms 间隔轮询、且
                    // 首次检查也要等一个间隔，聚焦平均白等 ~25ms。
                    // 改为立即尝试一次、未就绪再以 10ms 间隔轮询
                    // （上限仍 2s、落点仍段首 0），语义不变、只缩
                    // 短察觉就绪的延迟。
                    let js = format!(
                        "new Promise((res) => {{ let n = 0; const tryF = () => {{ if (window.__mnFocus) {{ window.__mnFocus({}, 0); res(1); return true; }} return false; }}; if (!tryF()) {{ const t = setInterval(() => {{ if (tryF()) {{ clearInterval(t); }} else if (++n > 200) {{ clearInterval(t); res(0); }} }}, 10); }} }}).then((v) => dioxus.send(v));",
                        serde_json::to_string(&fid).unwrap_or_default()
                    );
                    let mut eval = document::eval(&js);
                    match eval.recv::<Value>().await {
                        Ok(v) if v.as_i64() == Some(1) => {
                            diag::log("EDIT", &format!("auto focus first paragraph {fid}"));
                        }
                        _ => {
                            diag::log("EDIT", "auto focus skipped: bridge not ready");
                        }
                    }
                });
            }
        });
    }
    // 音乐输入解析的待落点卡片 id：解析完成时把光标放到该
    // 卡片下方一行开头（原版 focusCaretBelowResolvedCard）
    let mut card_caret = use_signal(|| Option::<String>::None);
    let mut slash_click = use_signal(|| Option::<(String, String)>::None);
    // 斜杠链接表单：Some(块 id) 时面板切为链接表单；提交后由
    // link_click 触发 __mnApplyLink（选区由桥的 savedRange 恢复）
    let mut link_for = use_signal(|| Option::<String>::None);
    let mut link_click = use_signal(|| Option::<(String, String)>::None);
    // 链接表单的位置：Enter 路径下面板已关，坐标从最后一次
    // slash 消息的位置继承
    let mut link_pos = use_signal(|| (20f64, 160f64, 200f64));
    // 媒体选择请求（斜杠图片/画廊、图文块换图）
    let mut media_req = use_signal(|| Option::<MediaReq>::None);
    // 导出面板（菜单内切换，不是独立弹窗）
    let mut show_export = use_signal(|| false);
    // 导出面板进出场态（原版 exportPanelClosing）：true 时面板
    // 呈 opacity 0 / translateY(-10px) scale(0.94)，靠 CSS
    // transition 与常态之间弹簧过渡（开场双 rAF 后撤、关闭
    // 220ms 后卸载）
    let mut export_closing = use_signal(|| false);
    // 导出面板生命周期代际：开/关每次递增，异步回调（开场
    // 双 rAF、关闭 220ms 计时）按代际守卫、过期自动作废。
    // 关闭语义对齐原版 closeExportPanel 的 clearTimeout 重
    // 排，杜绝视觉态门闩造成的遮罩永久残留（见
    // animate_export_close 注释）。
    let mut export_gen = use_signal(|| 0u32);
    // 导出面板动画相位与关闭去向（遮挡续修）：相位区分挂
    // 起的是开场还是关闭（export_closing 两义），去向记关
    // 闭完成时回菜单还是全关——回前台补完（__mnResume 监
    // 听 → settle_export_on_resume）据此收尾；渲染层据去
    // 向在全关发起瞬间释放遮罩命中（菜单遮罩渲染处）。
    let mut export_anim = use_signal(|| EXPORT_ANIM_IDLE);
    let mut export_to_menu = use_signal(|| false);
    // 页面滚动量：标题坞 >30 切换紧凑行态
    let mut ed_scroll = use_signal(|| 0f64);
    // 标题编辑会话开关（原版 editingTitle）：由 TitleController
    // 经 on_session 回报（聚焦 true / 失焦 false），仅供 S7 滚
    // 动翻转抑制消费。标题的文本与几何自全面重构起全归
    // TitleController 所有（title_controller.rs）：文本只在
    // compositionend/blur/Enter/Esc 时机经 on_commit 写回本
    // 信号，编辑器渲染路径不再持有任何标题布局状态（旧的
    // 布局锁存信号、组字信号与桥快照投影一并删除——多写者
    // 并发正是组字期几何翻转与光标双画的使能条件）。
    let mut title_editing = use_signal(|| false);
    // 深浅模式切换计数（原版监听 matchMedia change 后重算背景）
    let mut scheme_tick = use_signal(|| 0u32);
    // 页面进/出场（原版 editor.js 的 closing/animDone）：进场
    // slideIn 播完 320ms 摘除（page_anim_done）；出场由
    // closing prop 派生（App 栈式交接在原地翻 prop 播
    // slideOut 并计时卸载），不再有内部 page_closing 信号。
    let mut page_anim_done = use_signal(|| false);
    // 图文全文面板（blocks::TextSheet 上下文）
    let mut text_sheet = use_signal(|| Option::<(String, String)>::None);
    let mut sheet_edit = use_signal(|| false);
    let mut sheet_draft = use_signal(String::new);
    // 图文面板出场态与代际（原版 ImageTextSheet closing）
    let mut text_sheet_closing = use_signal(|| false);
    let mut text_sheet_gen = use_signal(|| 0u32);
    // 本篇头像（原版 per-note avatar，存 backup.avatars[memoId]）
    let mut avatar_url = use_signal(|| {
        data.read()
            .avatars
            .as_ref()
            .and_then(|a| a.get(&memo_id))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    });
    let mut dom_set = use_signal(|| Option::<(String, String, usize)>::None);
    // 背景色 / 双栏：存 memo.extra（原版 bgColor 顶层字段、layout 透传）
    let mut bg = use_signal(|| {
        memo.extra
            .get("bgColor")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    });
    let mut twopane = use_signal(|| {
        let layout = memo.extra.get("layout");
        if let Some(mode) = layout.and_then(|v| v.get("mode")).and_then(|v| v.as_str()) {
            return mode == "independent";
        }
        if layout
            .and_then(|v| v.get("twoPane"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return true;
        }
        if layout.is_some() {
            // G-2（A-2 批翻转）：layout 存在但无 mode（且
            // twoPane 非 true）时默认 independent，与原版
            // normalize 缺 mode 口径对齐（editor.render.js）。
            // 此类 layout 只来自导入的旧/手写备份；首次宽屏
            // 打开后落锚/关存路径会将其归一为带 mode 的
            // 完整形状（名单合法者名单不动）。
            return true;
        }
        web_sys::window()
            .and_then(|w| w.local_storage().ok().flatten())
            .and_then(|st| st.get_item("sj_editor_independent_scroll").ok().flatten())
            .map(|v| v == "1")
            .unwrap_or(false)
    });
    // 宽屏判定（原版双栏媒体查询）：(min-width:768px 且
    // min-height:600px) 或 min-width:1100px；matchMedia 监听
    let mut wide = use_signal(|| {
        web_sys::window()
            .map(|w| {
                w.match_media("(min-width: 768px) and (min-height: 600px), (min-width: 1100px)")
                    .ok()
                    .flatten()
                    .map(|m| m.matches())
                    .unwrap_or(false)
            })
            .unwrap_or(false)
    });
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                // change 监听具名登记（页面副作用审计·泄漏 3）：
                // 旧实现匿名 addEventListener，每次挂载 +1 且永
                // 不摘除、卸载后仍向死通道 send。改走具名
                // handler + window.__mnWideCleanup 幂等清理：
                // 重挂载先调上一代清理，卸载时 sync_editor_
                // cleanup 同步直调，与桥清理并入同一次卸载清理。
                "(() => { if (window.__mnWideCleanup) window.__mnWideCleanup(); const mq = window.matchMedia('(min-width: 768px) and (min-height: 600px), (min-width: 1100px)'); const h = (e) => dioxus.send(e.matches); mq.addEventListener('change', h); window.__mnWideCleanup = () => { mq.removeEventListener('change', h); window.__mnWideCleanup = null; }; dioxus.send(mq.matches); })();",
            );
            while let Ok(v) = eval.recv::<bool>().await {
                // PERF（第八批 T2）：初值回送与现值相同（窄屏
                // false = 初始值）时不 set——Signal::set 无条件
                // 通知订阅者，同值 set 会让整个 Editor 在挂载
                // 后多渲一遍（实测渲染遍数 2→1、打开长任务
                // 173→128ms）；值真变化时照旧 set，行为不变。
                if *wide.peek() != v {
                    wide.set(v);
                }
            }
        });
    });
    // 双栏落锚（原版 captureColumnLayout 在独立滚动启用时
    // 捕获成员并落库的口径）：独立双栏首次渲染且备忘尚无
    // 有效 layout 锚时，按规范估高分界一次性落锚；此后成
    // 员由锚决定，不随编辑、卡片加载、会话漂移。只写
    // extra.layout，不动 doc/title/updated_at。
    let mut col_anchor_done = use_signal(|| false);
    {
        let memo_id = memo_id.clone();
        use_effect(move || {
            if *col_anchor_done.read() {
                return;
            }
            if !(*twopane.read() && *wide.read()) {
                return;
            }
            let d = doc.read().clone();
            let anchored = data
                .read()
                .memos
                .iter()
                .find(|m| m.id.to_string() == memo_id)
                .and_then(|m| m.extra.get("layout").cloned())
                .and_then(|l| normalize_boundary(&d, &l))
                .is_some();
            col_anchor_done.set(true);
            if anchored || d.len() < 2 {
                return;
            }
            let b = canonical_boundary(&d);
            let ids: Vec<Value> = d
                .iter()
                .map(|n| {
                    Value::String(n.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
                })
                .collect();
            let (left, right) = ids.split_at(b.min(ids.len()));
            let mut backup = data.read().clone();
            if let Some(m) = backup
                .memos
                .iter_mut()
                .find(|m| m.id.to_string() == memo_id)
            {
                m.extra.insert(
                    "layout".to_string(),
                    json!({"version": 1, "mode": "independent", "left": left, "right": right}),
                );
            }
            data.set(backup.clone());
            diag::log("EDIT", &format!("column anchor captured boundary={b}"));
            spawn(async move {
                save_backup(&backup).await;
            });
        });
    }
    let mut menu_open = use_signal(|| false);
    let mut bg_open = use_signal(|| false);
    // 菜单/背景底表出场态与生命周期代际（浮层出场补齐，
    // 原版 menuClosing / BgSheet closing）：closing 期间
    // 面板保持挂载播出场 transition，220ms 计时完成后才
    // 卸载；代际守卫让重排/取消的旧回调自动作废。
    let mut menu_closing = use_signal(|| false);
    let mut menu_gen = use_signal(|| 0u32);
    let mut bg_closing = use_signal(|| false);
    let mut bg_gen = use_signal(|| 0u32);
    // 编辑页失败提示走错误徽章通道（原版 MynoteErrors.
    // addWarn，审计 E-1）：失败投 errbadge、不走 toast。
    // 成功提示仅保留导出 MD/HTML 两处 toast（用户
    // 2026-11-24 裁定：属比原版增强的调优——iOS 下载
    // 反馈近乎不可见，予以保留；附件成功不弹，块插入
    // 本身即反馈）。形态与备份页共用 settings::Toast
    // 同规格（seq 作 key、同文案必重挂、计时器按 seq
    // 校验卸载、Diag 一行；审计 G1/G2 编辑页半边）。
    let ed_status = crate::settings::Toast {
        msg: use_signal(String::new),
        seq: use_signal(|| 0u64),
        kind: use_signal(|| "info"),
        tag: "EDIT",
    };
    // 撤销/重做：文档 JSON 快照栈（与原版 use-history 的全量快照思路一致）
    // 基线 = 打开时的会话文档（含已模型化的尾随空段），撤销
    // 回到基线时尾随段仍在（与原版快照含 DOM 尾随段同口径）。
    let mut hist = use_signal(|| {
        vec![HistSnap {
            doc: serde_json::to_string(&doc.read().clone()).unwrap_or_default(),
            layout: memo_layout_json(&data.read(), &memo_id),
        }]
    });
    let mut hist_idx = use_signal(|| 0usize);
    // 撤销合并时钟（原版 use-history recordUndoPoint 口径）：
    // (最近一次连续输入压栈时刻 ms, 合并链是否活着)。600ms
    // 内连续输入替换栈顶；结构操作/撤销/重做断链。
    let mut hist_clock = use_signal(|| (0f64, false));
    let mut epoch = use_signal(|| 0u32);
    // 最近编辑块（桥消息维护）：菜单撤销/重做时恢复焦点的落点
    let mut focus_hint = use_signal(|| Option::<(String, usize)>::None);
    use_context_provider(|| crate::blocks::TextSheet(text_sheet));
    let mut md_edit = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::MdEdit(md_edit));
    // 聚焦中的编辑块（桥 focusBlock/blurBlock 维护）：编辑中的
    // 段落不转 md 预览，失焦才转（原版 blur 转换口径）
    let mut active_edit = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::ActiveEdit(active_edit));
    // 卡片重试（blocks::CardRetry 上下文）：音乐卡 error 态点重试
    let mut card_retry = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::CardRetry(card_retry));
    // Wiki 导航（blocks::WikiNav 上下文）：md 预览里的 wiki
    // 链接点击 → 先落盘当前编辑再导航（原版双链优先 + flush）
    let mut wiki_nav = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::WikiNav(wiki_nav));
    // 原子块选中态（blocks::SelBlock 上下文）
    let mut sel_block = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::SelBlock(sel_block));
    // 卡片编辑态（blocks::CardEdit 上下文，卡片交互专项）：
    // 经浮层菜单「编辑」进入，全局同时仅一张卡在编辑态。
    let mut card_edit = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::CardEdit(card_edit));
    // 卡片浮层菜单（blocks::CardMenu 上下文，卡片交互专
    // 项）：长按拾起/桌面右键两路同开。
    let mut card_menu = use_signal(|| Option::<crate::blocks::CardMenuState>::None);
    use_context_provider(|| crate::blocks::CardMenu(card_menu));
    // 附件清单（blocks::Manifest 上下文）：附件块文件名查
    // manifest（审计 E2，原版 renderAtomicHTML files 表口径）
    use_context_provider(|| crate::blocks::Manifest(manifest));
    // 反向链接 targets 会话缓存（PERF 第八批 T2，见
    // backlinks_cached）：Rc+RefCell 非响应式持有，不订阅
    // 不触发重渲；随 Editor 实例生灭，跨篇导航重建一次。
    let bl_cache = use_hook(|| -> BacklinkCache {
        std::rc::Rc::new(std::cell::RefCell::new(std::collections::HashMap::new()))
    });

    // 持久化：把当前标题+文档写回总数据并落 IndexedDB
    let persist = PersistHandle(std::rc::Rc::new({
        let memo_id = memo_id.clone();
        let state_owner = state_owner.clone();
        move |doc_snapshot: Vec<Node>, title_snapshot: String, mut data: Signal<BackupFile>| {
            // 守卫拒写（状态归属与写目标不一致）时整笔跳过：
            // 不 set、不落盘（见 build_backup）。
            let Some(backup) =
                build_backup(data, &memo_id, &state_owner, doc_snapshot, title_snapshot)
            else {
                return;
            };
            data.set(backup.clone());
            spawn(async move {
                save_backup(&backup).await;
            });
        }
    }));

    // 待发尾巴恢复的落盘（doc 初始化命中时）：恢复内容
    // 已进 doc 信号与撤销基线，这里补一次 persist 写回
    // 总数据与 IndexedDB——否则打开后无任何操作再次卸
    // 载，保险丝已被消费、尾巴会二次丢失。
    {
        let persist = persist.clone();
        let tail_cell = tail_recovered.clone();
        use_effect(move || {
            let n = tail_cell.get();
            if n == 0 {
                return;
            }
            tail_cell.set(0);
            persist.call(doc.read().clone(), title.read().clone(), data);
            diag::log("EDIT", &format!("pending input persisted (open recovery x{n})"));
        });
    }

    // 标题会话回调（TitleController → Editor）：use_hook 锁
    // 定，保证 TitleCapsule 的 props 逐值稳定、重渲染整段跳
    // 过。on_commit 是标题文本的唯一写回路径（Controller 在
    // compositionend/blur/Enter/Esc 时机调用）：置标题信号
    // 并以当前文档快照 persist。
    let title_commit = use_hook(|| {
        let persist = persist.clone();
        EventHandler::new(move |text: String| {
            if *title.read() != text {
                title.set(text.clone());
            }
            persist.call(doc.read().clone(), text, data);
        })
    });
    let title_session = use_hook(|| {
        EventHandler::new(move |active: bool| {
            if *title_editing.read() != active {
                title_editing.set(active);
            }
            if !active {
                // 会话结束重播（S7 resync 缺口）：会话期滚动
                // 翻转被抑制、滚动值被丢弃，会话后 ed_scroll
                // 原须等下一条滚动消息才与实际滚动重同步——
                // 此处按当刻 window.scrollY（与滚动订阅同一
                // 来源）重播一次，坞态即时归位；值未变不 set
                // 不记行。
                if let Some(w) = web_sys::window() {
                    let y = w.scroll_y().unwrap_or(0.0);
                    if *ed_scroll.peek() != y {
                        diag::log(
                            "EDIT",
                            &format!(
                                "title session end: replay ed_scroll <- scrollY {y:.0} (S7 resync)"
                            ),
                        );
                        ed_scroll.set(y);
                    }
                }
            }
        })
    });

    // JS 桥：挂载时装一次，消息循环处理全部编辑操作
    {
        let memo_id = memo_id.clone();
        let persist_bridge = persist.clone();
        use_effect(move || {
            let persist = persist_bridge.clone();
            diag::log("EDIT", &format!("open memo={memo_id}"));
            let memo_id = memo_id.clone();
            spawn(async move {
                let mut eval = document::eval(EDITOR_JS);
                while let Ok(msg) = eval.recv::<String>().await {
                    let before = serde_json::to_string(&*doc.read()).unwrap_or_default();
                    let before_layout = memo_layout_json(&data.read(), &memo_id);
                    let (skip_hist, coalesce) = handle_bridge_msg(&msg, &memo_id, doc, title, data, panel, link_for, link_pos, focus_req, dom_set, md_edit, active_edit, sel_block, manifest, hist, hist_idx, hist_clock, epoch, focus_hint, ed_scroll, card_caret, card_menu, card_edit, media_req, &persist);
                    let after = serde_json::to_string(&*doc.read()).unwrap_or_default();
                    let after_layout = memo_layout_json(&data.read(), &memo_id);
                    // B-7：layout 单独变化（跨栏移动只改锚的
                    // 形态）也成撤销点，快照成对捕获。
                    if !skip_hist && (after != before || after_layout != before_layout) {
                        hist_push(
                            hist,
                            hist_idx,
                            hist_clock,
                            HistSnap { doc: after, layout: after_layout },
                            coalesce,
                        );
                    }
                }
                diag::log("EDIT", "bridge channel closed");
            });
        });
    }

    // 尾随空段模型化（会话内续补）：失焦转预览、删块、转换
    // 等让新的尾随位置出现时，把真实空段落补进模型（原版
    // ensureTrailing 在预览转换时点补段、首次同步即入
    // docRef 的等价）。订阅 doc 与编辑态：插入后同一位置不
    // 再命中，effect 再跑必为 0 处、自稳；源码编辑中的块其
    // 后不补（其失焦消息清掉 active_edit 后本 effect 续跑
    // 再补，与原版转换时点对齐）。补段不走 persist（各 op
    // 自行落盘、返回时全量落盘兜底），不压撤销栈（快照在桥
    // 循环按 handle 前后 JSON 判定，与本 effect 互不干扰）。
    use_effect(move || {
        let editing = active_edit
            .read()
            .clone()
            .or_else(|| md_edit.read().clone());
        let mut d = doc.read().clone();
        let n = materialize_trails(&mut d, editing.as_deref());
        if n > 0 {
            doc.set(d);
            diag::log("EDIT", &format!("trail materialized x{n}"));
        }
    });

    // 结构操作后的光标恢复
    use_effect(move || {
        let req = focus_req.read().clone();
        if let Some((bid, off)) = req {
            focus_req.set(None);
            spawn(async move {
                let js = format!(
                    "if (window.__mnFocus) window.__mnFocus({}, {}); dioxus.send(null);",
                    serde_json::to_string(&bid).unwrap_or_default(),
                    off
                );
                let mut eval = document::eval(&js);
                let _ = eval.recv::<Value>().await;
            });
        }
    });

    // 多行粘贴后，当前块的 DOM 由桥按模型回写（非受控块不会
    // 自己重渲染）并把光标放到首行末尾
    use_effect(move || {
        let req = dom_set.read().clone();
        if let Some((bid, html, off)) = req {
            dom_set.set(None);
            spawn(async move {
                let js = format!(
                    "if (window.__mnSetHtml) window.__mnSetHtml({}, {}, {}); dioxus.send(null);",
                    serde_json::to_string(&bid).unwrap_or_default(),
                    serde_json::to_string(&html).unwrap_or_default(),
                    off
                );
                let mut eval = document::eval(&js);
                let _ = eval.recv::<Value>().await;
            });
        }
    });

    // 斜杠面板的点击在 Editor 作用域里执行（SlashPanel 点击后
    // 立即卸载，它自己 spawn 的异步会被一并取消——踩过）。
    // 按命令类别分流：行内命令走 __mnInline 就地执行；图片/画廊
    // 走文件选择替换当前块；其余走 strip + op_convert。
    {
        let persist = persist.clone();
        use_effect(move || {
            let click = slash_click.read().clone();
            if let Some((bid, act)) = click {
                slash_click.set(None);
                slash_record_recent(&act);
                let persist = persist.clone();
                if INLINE_ACTS.contains(&act.as_str()) {
                    spawn(async move {
                        let js = format!(
                            "dioxus.send(window.__mnInline ? window.__mnInline({}, {}) : '');",
                            serde_json::to_string(&act).unwrap_or_default(),
                            serde_json::to_string(&bid).unwrap_or_default()
                        );
                        let mut eval = document::eval(&js);
                        let html = eval.recv::<String>().await.unwrap_or_default();
                        let mut d = doc.read().clone();
                        if let Some(loc) = find_loc(&d, &bid) {
                            node_at_mut(&mut d, loc).children =
                                Some(editor_html_to_inlines(&html));
                            doc.set(d.clone());
                            persist.call(d, title.read().clone(), data);
                            diag::log("EDIT", &format!("slash inline {act} {bid}"));
                        }
                    });
                } else if act == "image" || act == "gallery" {
                    // 占位块路径（S4）：落占位块 + 尾随空段，不在
                    // 应用瞬间弹文件选择器
                    let mut doc2 = doc;
                    let mut focus_req2 = focus_req;
                    op_insert_media_placeholder(&mut doc2, &bid, act == "gallery", &mut focus_req2);
                    persist.call(doc2.read().clone(), title.read().clone(), data);
                } else {
                    spawn(async move {
                        let js = format!(
                            "dioxus.send(window.__mnStripSlash ? window.__mnStripSlash({}) : '');",
                            serde_json::to_string(&bid).unwrap_or_default()
                        );
                        let mut eval = document::eval(&js);
                        let raw = eval.recv::<String>().await.unwrap_or_default();
                        // __mnStripSlash 返回 {html, pos} JSON
                        //（D-11）；解析失败时整串作 html、pos=0
                        let (html, pos) = serde_json::from_str::<Value>(&raw)
                            .ok()
                            .and_then(|v| {
                                v.get("html")
                                    .and_then(|h| h.as_str())
                                    .map(|h| (h.to_string(), v.get("pos").and_then(|p| p.as_u64()).unwrap_or(0) as usize))
                            })
                            .unwrap_or((raw, 0));
                        let mut doc = doc;
                        let mut focus_req = focus_req;
                        let mut md_edit = md_edit;
                        let mut dom_set = dom_set;
                        if let Some((src, off)) = op_convert(&mut doc, &bid, &act, &html, pos, &mut focus_req, &mut md_edit) {
                            // md 源转换：DOM 回写为源码（<br> 换行）并聚焦
                            let esc = src
                                .replace('&', "&amp;")
                                .replace('<', "&lt;")
                                .replace('>', "&gt;")
                                .replace('\n', "<br>");
                            dom_set.set(Some((bid.clone(), esc, off)));
                        }
                        persist.call(doc.read().clone(), title.read().clone(), data);
                    });
                }
            }
        });
    }

    // 链接表单提交：__mnStripSlash 后 __mnApplyLink（桥内恢复
    // 打开表单前保存的选区），返回的 HTML 对齐模型
    {
        let persist = persist.clone();
        use_effect(move || {
            let click = link_click.read().clone();
            if let Some((bid, url)) = click {
                link_click.set(None);
                link_for.set(None);
                slash_record_recent("link");
                let persist = persist.clone();
                spawn(async move {
                    let js = format!(
                        "if (window.__mnStripSlash) window.__mnStripSlash({0}); dioxus.send(window.__mnApplyLink ? window.__mnApplyLink({1}, {0}) : '');",
                        serde_json::to_string(&bid).unwrap_or_default(),
                        serde_json::to_string(&url).unwrap_or_default()
                    );
                    let mut eval = document::eval(&js);
                    let html = eval.recv::<String>().await.unwrap_or_default();
                    let mut d = doc.read().clone();
                    if let Some(loc) = find_loc(&d, &bid) {
                        node_at_mut(&mut d, loc).children =
                            Some(editor_html_to_inlines(&html));
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        diag::log("EDIT", &format!("slash link {bid}"));
                    }
                });
            }
        });
    }

    // 滚动量订阅：标题坞紧凑态切换（>30px）。监听器具名挂在
    // window 上、重挂前先摘旧的、卸载时在 use_drop 里摘除——
    // 匿名监听无移除路径会逐周期泄漏（滚动审计 S4）。
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnEdScroll) window.removeEventListener('scroll', window.__mnEdScroll); let last = -1; const f = () => { const y = window.scrollY || 0; if (Math.abs(y - last) > 2) { last = y; const p = window.__mnProgScroll; dioxus.send([y, (p && Date.now() < p.until) ? 1 : 0]); } }; window.__mnEdScroll = f; window.addEventListener('scroll', f, { passive: true }); f();",
            );
            while let Ok(v) = eval.recv::<Vec<f64>>().await {
                let y = v.first().copied().unwrap_or(0.0);
                // prog=1：应用编排滚动（桥 S8 失焦回顶在
                // __mnProgScroll 窗口内打标）——不是用户滚
                // 动，不触发下方「滚动即关菜单/导出面板」；
                // 滚动量本身照常消费（标题坞状态、斜杠跟随
                // 不依赖来源）。确诊见
                // diagnose_bgsheet_after_att.md。
                let prog = v.get(1).copied().unwrap_or(0.0) > 0.5;
                // 标题编辑期抑制 scrolled 翻转（滚动审计 S7，
                // 原版 editor.js:1013-1019）：点胶囊引发的页面
                // 回弹滚动不许在编辑中途切换胶囊横竖布局；滚
                // 动量本身仍照常消费（菜单关闭等联动不依赖它）。
                if *title_editing.read() {
                    if (y > 30.0) != (*ed_scroll.read() > 30.0) {
                        diag::log_once(
                            "s7-guard",
                            "EDIT",
                            "scrolled flip suppressed while editing title (S7)",
                        );
                    }
                } else if *ed_scroll.peek() != y {
                    // PERF（第八批 T2）：桥装载即回送 y=0（初始
                    // 值同为 0），同值 set 会无条件通知订阅者、
                    // 让 Editor 挂载后多渲一遍；仅值真变化时
                    // set，下方滚动联动逻辑不受影响（仍逐条
                    // 消息执行）。
                    ed_scroll.set(y);
                }
                // 滚动即关菜单/导出面板（滚动审计 S2，原版
                // editor.js:241-292 同口径；不清的话 scrim 还会
                // 拦截后续点击）。导出面板开着时走原版关闭动画
                // （closeExportPanel：220ms 过渡后卸载并关菜单）。
                // 仅用户滚动适用：编排滚动（prog）跳过本支，
                // 并在菜单/导出在场时回记结果行（链路留痕）。
                if prog {
                    if *show_export.read() || *menu_open.read() {
                        diag::log("EDIT", &format!("app scroll y={y:.0} -> menu close skipped"));
                    }
                } else if *show_export.read() {
                    animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
                } else if *menu_open.read() {
                    animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                }
                // 斜杠面板跟随滚动重定位（滚动审计 S3，原版按
                // 选区重算锚点）：向桥索取该块当前 rect 更新锚点
                let cur_panel = panel.read().clone();
                if let Some((pbid, pfilter, _, _, _)) = cur_panel {
                    spawn(async move {
                        let js = format!(
                            "dioxus.send(window.__mnSlashAnchor ? window.__mnSlashAnchor({}) : null);",
                            serde_json::to_string(&pbid).unwrap_or_default()
                        );
                        let mut eval = document::eval(&js);
                        if let Ok(v) = eval.recv::<Value>().await {
                            if let (Some(x), Some(top), Some(bottom)) = (
                                v.get("x").and_then(|n| n.as_f64()),
                                v.get("y").and_then(|n| n.as_f64()),
                                v.get("b").and_then(|n| n.as_f64()),
                            ) {
                                // 面板可能已在此期间关闭/换块，仍是
                                // 同一块才更新锚点
                                let now = panel.read().clone();
                                if let Some((nbid, _, _, _, _)) = &now {
                                    if *nbid == pbid {
                                        panel.set(Some((pbid, pfilter, x, top, bottom)));
                                    }
                                }
                            }
                        }
                    });
                }
            }
        });
    });

    // Esc 关闭浮层（编辑态审计 B12，原版菜单组件的 document
    // 级 Esc 口径）：监听具名登记，卸载时在 use_drop 里摘除。
    // 审计 E-15：原版各浮层 Esc 互斥、一次只关一层——下方
    // 处理为优先级 else-if 链（沿书写序：图文底表 >
    // 卡片菜单 > 卡片编辑态 > 导出面板 > 菜单 > 背景底表 >
    // 链接表单 > 斜杠面板），每层命中记一行 esc -> 层名
    // 打点供探针断言；斜杠面板关闭只走本链（桥面板
    // keydown 的 Escape 不再发 slashClose、只吞键）。
    // 链接表单开时焦点恒在其 input 内、Esc 语义为取消
    // 回命令列表，由 input 自带 onkeydown 单一承接——
    // __mnEsc 对 .slash-link-form 内的事件直接放行（防
    // 本链与 input 处理竞态连关面板），链内 link-form
    // 分支只作焦点不在 input 时的兜底。
    let memo_id_esc = memo_id.clone();
    use_effect(move || {
        let memo_id_esc = memo_id_esc.clone();
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnEsc) document.removeEventListener('keydown', window.__mnEsc, true); const f = (e) => { if (e.key !== 'Escape') return; if (e.target && e.target.closest && e.target.closest('.slash-link-form')) return; if (document.querySelector('.image-text-sheet, .card-menu-panel, .editor-export-panel, .editor-menu-panel, .bg-sheet, .slash-link-form, #slash-panel')) e.preventDefault(); dioxus.send('esc'); }; window.__mnEsc = f; document.addEventListener('keydown', f, true);",
            );
            while let Ok(msg) = eval.recv::<String>().await {
                if msg == "esc" {
                    let ce_esc = card_edit.read().clone();
                    if text_sheet.read().is_some() {
                        // 图文面板（z 4001）：原版 ImageTextSheet
                        // 自带 Esc → closeWithAnim。文本逐键已写
                        // 回落盘（D-20），关表无待存草稿，直接出场。
                        diag::log("EDIT", "esc -> text-sheet");
                        animate_text_sheet_close(text_sheet, text_sheet_closing, text_sheet_gen);
                    } else if card_menu.read().is_some() {
                        // 卡片浮层菜单/编辑态（卡片交互专项）：
                        // 先关菜单，其次退出编辑态。
                        diag::log("EDIT", "esc -> card-menu");
                        card_menu.set(None);
                    } else if let Some(b) = ce_esc {
                        card_edit.set(None);
                        diag::log("EDIT", &format!("card edit exit {b} (esc)"));
                    } else if *show_export.read() {
                        // 原版 Esc 关导出面板走 closeExportPanel
                        // 动画并把焦点还给 ••• 按钮
                        diag::log("EDIT", "esc -> export");
                        animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
                    } else if *menu_open.read() {
                        diag::log("EDIT", "esc -> menu");
                        animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                    } else if *bg_open.read() {
                        diag::log("EDIT", "esc -> bg-sheet");
                        animate_bg_close(bg_open, bg_closing, bg_gen, BgAfter::None, data, bg, memo_id_esc.clone());
                    } else if link_for.read().is_some() {
                        diag::log("EDIT", "esc -> link-form");
                        link_for.set(None);
                    } else if panel.read().is_some() {
                        diag::log("EDIT", "esc -> slash-panel");
                        panel.set(None);
                    }
                }
            }
        });
    });

    // 回前台补完（遮挡续修）：导出面板的开/关完成原本只
    // 依赖 rAF/setTimeout 回传，页面被遮挡/挂起（切页签
    // 看 PDF 弹窗、打印表单呈现）时计时队列整体停摆、完
    // 成永不落地。visibilitychange 转 visible / pageshow /
    // focus 任一到达即按相位收尾挂起的开/关
    // （settle_export_on_resume，空闲时无副作用）。监听具
    // 名登记 __mnResume，卸载时在 sync_editor_cleanup 里
    // 摘除。
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnResume) { document.removeEventListener('visibilitychange', window.__mnResume); window.removeEventListener('pageshow', window.__mnResume); window.removeEventListener('focus', window.__mnResume); } \
                 const f = () => { if (!document.hidden) dioxus.send('resume'); }; \
                 window.__mnResume = f; \
                 document.addEventListener('visibilitychange', f); \
                 window.addEventListener('pageshow', f); \
                 window.addEventListener('focus', f);",
            );
            while let Ok(msg) = eval.recv::<String>().await {
                if msg == "resume" {
                    settle_export_on_resume(
                        show_export,
                        export_closing,
                        menu_open,
                        export_gen,
                        export_anim,
                        export_to_menu,
                    );
                }
            }
        });
    });

    // typed 的事件源（原版 hasTyped 的直接对应物）：编辑器
    // 内发生过任何一次 DOM input 即置位且不回落。仅靠 doc
    // 信号与初始快照的偏离比较不可靠——DOM 先行编辑（打
    // 字后在下一个同步点前删光）对信号不可见，实测正文打
    // 字又删光的新备忘被误判为空删除。偏离比较保留为第二
    // 来源（程序化改 doc 的路径）。监听具名登记，卸载时在
    // use_drop 里摘除。
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnTypedMark) document.removeEventListener('input', window.__mnTypedMark, true); \
                 window.__mnTypedSent = false; \
                 const f = (e) => { \
                   if (window.__mnTypedSent) return; \
                   const root = document.getElementById('editor-root'); \
                   if (root && e.target && root.contains(e.target)) { window.__mnTypedSent = true; dioxus.send('typed'); } \
                 }; \
                 window.__mnTypedMark = f; \
                 document.addEventListener('input', f, true);",
            );
            while let Ok(msg) = eval.recv::<String>().await {
                if msg == "typed" {
                    typed.set(true);
                    break;
                }
            }
        });
    });

    // 深浅模式切换通知（原版 editor.js useLayoutEffect 的方
    // 案半边）：mq 翻转时通知 Rust——bump 本地 scheme_tick
    // （Editor 主体渲染期订阅，是编辑器深浅重渲染的唯一触
    // 发源）并同任务直写根背景变量（见 handler 注）。mq 监
    // 听登记 __mnSchemeCleanup（安装前先调上一
    // 代、卸载时 sync_editor_cleanup 同步直调摘除），不留
    // 匿名累积。
    // 曾与本 effect 同居的顶部 body::before 渐变改写装置
    // （#body-before-bg 样式元素 + scroll 驱动 alpha 更新 +
    // __mnBgUpdate/__mnBgCleanup 全局）已于 2026-11-23 整套
    // 移除（用户裁定）：其一，功能仅为渐变着色（色跟随
    // --mn-root-rgb、滚动淡入），编辑器内回落 base.css 基
    // 础规则形态（全应用同构、与原版 base 一致）可替代；
    // 其二，安装走 spawn+eval 异步、清理是 use_drop 同步直
    // 调，快速开→关时清理可先于安装落地，安装到达后样式
    // 元素与 scroll 监听永久无主残留，且渐变在变量缺失时
    // 回落写死字面量 250,250,250（编辑色），与根色状态无
    // 关地画编辑色顶条——竞态与残留随装置一并消失。
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnSchemeCleanup) window.__mnSchemeCleanup(); \
                 const mq = window.matchMedia('(prefers-color-scheme: dark)'); \
                 const onScheme = () => dioxus.send('scheme'); \
                 mq.addEventListener('change', onScheme); \
                 window.__mnSchemeCleanup = () => { mq.removeEventListener('change', onScheme); window.__mnSchemeCleanup = null; };",
            );
            while let Ok(msg) = eval.recv::<String>().await {
                if msg == "scheme" {
                    let next = scheme_tick.read().wrapping_add(1);
                    scheme_tick.set(next);
                    // 可见性自守（图片页化补）：图片页在场时
                    // 编辑器槽位被隐藏（stage display:none，
                    // 见 main.rs），根色归 App 派生（图片页
                    // = 根页面色）——本分支只 bump 本地代际
                    // 完成自身深浅重渲染、不写根色，防与派
                    // 生竞速把根色粘在编辑值（两路监听无定
                    // 序、直写不触派生输入则无后续纠正）。
                    let mut chk = document::eval(
                        "const s = document.querySelector('.editor-stage'); dioxus.send(s ? getComputedStyle(s).display : '');",
                    );
                    let stage_hidden = chk
                        .recv::<String>()
                        .await
                        .map(|d| d == "none")
                        .unwrap_or(false);
                    if stage_hidden {
                        continue;
                    }
                    // 深浅切换与换色同口径（背景同步根治）：根
                    // 背景变量按新 scheme 同任务重写，不走
                    // eval/rAF；App 派生随后重申同值。先行值
                    // 即本篇按新 scheme 的有效背景（effective_
                    // bg 读当前 mq），派生已是页面状态纯函
                    // 数、无第二计算者，无需再经任何派生输入
                    // 换算。
                    let t = effective_bg(&bg.peek().clone());
                    let t = t.as_str();
                    crate::apply_root_bg(Some(t));
                }
            }
        });
    });

    // 背景色延伸到安全区（背景同步根治后）：根背景由 App 外
    // 壳按页面状态派生、经唯一写者双路落地（html/body 内联
    // backgroundColor 为带区权威路径、:root 变量同值镜像；
    // 编辑页打开 = 本篇有效背景，其他页 = 根页面色）；换色的发
    // 起任务（set_bg）同步先行写入同值，故此处不再有刷新
    // effect——旧实现选色后 spawn eval + rAF 读 body 计算色
    // （须等 App 写完）刷新顶部渐变，实测恒晚其余层 1 帧起、
    // 顺序无保证时取旧色，已删；渐变改写装置本身亦已整套移
    // 除（见上方 scheme effect 注）。

    // 卸载清理（同步）：撤编辑器具名全局监听（含 scheme mq
    // 的 __mnSchemeCleanup）。
    // 教训（页面色泄漏根因）：旧实现把清理放在 use_drop 里
    // spawn 出去的 eval 中——spawn 依附组件作用域，卸载即被
    // 取消，清理一次都没执行过（探针实证：返回列表后
    // __mnEsc 仍为 function、html/body 内联背景永久残留）。
    // 清理必须在 use_drop 闭包内同步直调（sync_editor_cleanup）。
    // html/body 根背景由 App 派生，不在此处碰。
    use_drop(move || {
        sync_editor_cleanup();
        // 清理后普查（结果侧证据，诊断覆盖补齐）：stage/编辑
        // 器根/离页层计数与 body 子节点成行；#body-before-bg
        // 恒不存在（bbbg=false）是渐变改写装置已移除的长期
        // 证据。
        diag::log_census("EDIT");
    });

    // 打开时补拉（原版 hydrate）：musicCard/link-card 有 url 且
    // 无标题 meta 或仍在 loading → 逐张解析（挂载快照，只跑一次）
    {
        let persist = persist.clone();
        use_effect(move || {
            let snapshot = doc.peek().clone();
            for n in &snapshot {
                let ty = n.node_type.as_deref().unwrap_or("");
                if ty != "musicCard" && ty != "link-card" {
                    continue;
                }
                let url = n.extra.get("url").and_then(|v| v.as_str()).unwrap_or("");
                if url.is_empty() {
                    continue;
                }
                let status = n.extra.get("status").and_then(|v| v.as_str()).unwrap_or("");
                let has_title = n
                    .extra
                    .get("meta")
                    .and_then(|m| m.get("title"))
                    .and_then(|v| v.as_str())
                    .map(|s| !s.is_empty())
                    .unwrap_or(false);
                if has_title && status != "loading" {
                    continue;
                }
                if let Some(bid) = n.id.clone() {
                    spawn_resolve_card(doc, bid, url.to_string(), title, data, persist.clone(), None, None);
                }
            }
        });
    }

    // 卡片重试（原版 retryMusicCard）：先置 loading 再解析
    {
        let persist = persist.clone();
        use_effect(move || {
            let retry_req = card_retry.read().clone();
            if let Some(bid) = retry_req {
                card_retry.set(None);
                let mut d = doc.read().clone();
                if let Some(loc) = find_loc(&d, &bid) {
                    let url = {
                        let n = node_at_mut(&mut d, loc);
                        n.extra.insert("meta".into(), serde_json::Value::Null);
                        n.extra.insert("status".into(), json!("loading"));
                        n.extra
                            .get("url")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string()
                    };
                    if !url.is_empty() {
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        diag::log("CARD", &format!("retry {bid}"));
                        spawn_resolve_card(doc, bid, url, title, data, persist.clone(), None, None);
                    }
                }
            }
        });
    }

    // Wiki 导航：收到 target 后先落盘当前 doc/title（原版
    // flushAutoSave 后导航；落盘失败也照样导航，仅记日志），
    // 再回调宿主解析目标（命中打开 / 未命中新建同名备忘）。
    {
        let persist = persist.clone();
        let on_open_wiki = on_open_wiki.clone();
        let from_id = memo_id.clone();
        use_effect(move || {
            let req = wiki_nav.read().clone();
            if let Some(target) = req {
                wiki_nav.set(None);
                persist.call(doc.read().clone(), title.read().clone(), data);
                diag::log("WIKI", &format!("nav '{target}' from {from_id}"));
                on_open_wiki.call(target);
            }
        });
    }

    // 进场动画摘除（原版 animDone，editor.js:108-112）：挂载
    // 后 320ms 摘掉根节点进场动画——both 填充的终帧
    // transform 常驻会成为 fixed 后代（返回钮/标题坞）的
    // 包含块、把它们困在页面盒里。关闭先行时不摘，出场
    // 动画（closing prop）在 page_anim 里优先于摘除态，故
    // 此处按挂载时点判定即可（实例恒以 closing=false 挂
    // 载，见 closing prop 注释）。落点用 use_hook：编辑器
    // 按 memo.id 键控、每次打开必重挂，挂载一次性语义与
    // 原版 useEffect([closing]) 的首挂载一致；use_hook +
    // spawn 也是 warmup 已验证的挂载延时落法。
    use_hook(move || {
        diag::log("EDIT", "page enter slideIn");
        spawn(async move {
            let mut eval = document::eval("setTimeout(() => dioxus.send(null), 320);");
            let _ = eval.recv::<serde_json::Value>().await;
            if !closing {
                page_anim_done.set(true);
            }
        });
    });

    // 图文面板打开时同步文本镜像并重置为阅读态（编辑态从
    // 只读开始；镜像与块 text 经逐键写回恒一致，D-20）
    use_effect(move || {
        if let Some((_, t)) = text_sheet.read().clone() {
            sheet_draft.set(t);
            sheet_edit.set(false);
        }
    });

    // 返回：全量同步 → 落库 → 关页；空笔记（无文本、无卡片块、
    // 无背景、标题为空）按原版规则关闭即删除
    let go_back = {
        let memo_id = memo_id.clone();
        let state_owner = state_owner.clone();
        let initial_title = initial_title.clone();
        move |_| {
            // 标题未提交文本先行落定：Controller 只在失焦等
            // 时机写标题信号，点返回不触发标题失焦（iOS 点
            // 按钮不转移焦点），在此同步失焦把会话提交了再
            // 走关闭流程（空备忘判定与落盘标题都读现值）。
            blur_title_if_focused();
            let memo_id = memo_id.clone();
            let state_owner = state_owner.clone();
            let initial_title = initial_title.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                );
                let mut d = doc.read().clone();
                match eval.recv::<String>().await {
                    Ok(s) => apply_sync_map(&mut d, &s),
                    Err(e) => {
                        diag::log("EDIT", &format!("back-sync recv err: {e:?}"))
                    }
                }
                doc.set(d.clone());
                let has_text = d.iter().any(|b| !b.plain_text().trim().is_empty());
                let has_card = d.iter().any(|b| {
                    matches!(
                        b.node_type.as_deref(),
                        Some(
                            "image"
                                | "video"
                                | "musicCard"
                                | "attachment"
                                | "link-card"
                                | "gallery"
                                | "divider"
                        )
                    )
                });
                let norm_title = |v: &str| {
                    let t = v.trim();
                    if t.is_empty() { "无标题".to_string() } else { t.to_string() }
                };
                let empty = is_new
                    && !*typed.read()
                    && !has_text
                    && !has_card
                    && bg.read().is_none()
                    && avatar_url.read().is_none()
                    && norm_title(&title.read()) == norm_title(&initial_title);
                if empty {
                    // 出场（栈式交接口径）：即刻 on_close——App
                    // 把本实例留在编辑器槽位翻 closing 播
                    // slideOut 并计时卸载（旧串行口径在此等待
                    // 320ms 播满才关页，已退役）。on_close 先于
                    // data.set 的次序与理由不动，见下注。
                    diag::log("EDIT", "page exit slideOut");
                    // 先 on_close 再删数据：若先 data.set，App 会因
                    // sel_memo 查无此备忘而提前渲染列表并卸载编辑器，
                    // 本 spawn 随即在 save_backup 的 await 点被取消，
                    // on_close 永不执行、列表滚动恢复（S1）失效
                    //（实测：新建空备忘返回列表时滚动恒为 0）。
                    // 栈式交接下 on_close 只翻离页条目、实例以
                    // 槽位键留存，删除后本实例改由离页条目持有
                    // 渲染（不再依赖 data 查得此备忘）。
                    on_close.call(());
                    let mut backup = data.read().clone();
                    backup.memos.retain(|m| m.id.to_string() != memo_id);
                    data.set(backup.clone());
                    diag::log("EDIT", &format!("close empty memo -> deleted {memo_id}"));
                    save_backup(&backup).await;
                    return;
                }
                // 双栏开启时把归一化 layout 一并落库（原版
                // 保存路径 captureCurrentColumnLayout 口径）
                let boundary = if *twopane.read() {
                    let cur = data
                        .read()
                        .memos
                        .iter()
                        .find(|m| m.id.to_string() == memo_id)
                        .and_then(|m| m.extra.get("layout").cloned());
                    Some(column_boundary(&d, cur.as_ref()))
                } else {
                    None
                };
                // 守卫拒写（状态归属与写目标不一致）时整笔跳
                // 过保存：layout 派生同出自本实例 doc、随合并
                // 一并跳过；退出流程本身不受守卫拦截，下方
                // on_close 照常执行。
                if let Some(mut backup) =
                    build_backup(data, &memo_id, &state_owner, d.clone(), title.read().clone())
                {
                    if let Some(b) = boundary {
                        if let Some(m) = backup
                            .memos
                            .iter_mut()
                            .find(|m| m.id.to_string() == memo_id)
                        {
                            let ids: Vec<Value> = d
                                .iter()
                                .map(|n| {
                                    Value::String(
                                        n.id.as_ref()
                                            .map(|i| i.to_string())
                                            .unwrap_or_default(),
                                    )
                                })
                                .collect();
                            let (left, right) = ids.split_at(b.min(ids.len()));
                            m.extra.insert(
                                "layout".to_string(),
                                json!({"version": 1, "mode": "independent", "left": left, "right": right}),
                            );
                        }
                    }
                    data.set(backup.clone());
                    save_backup(&backup).await;
                }
                // 出场（原版 handleClose 尾段的次序保留、形态
                // 改栈式交接）：保存完成即刻 on_close，App 把
                // 本实例留在槽位翻 closing 播 slideOut 并计时
                // 卸载（旧口径在此等待 320ms 播满才卸载，已
                // 退役——等待期正是新页进场被串行门控的来源）。
                diag::log("EDIT", "page exit slideOut");
                on_close.call(());
            });
        }
    };

    // 撤销/重做：与键盘路径共用 step_undo/step_redo（先全量同步
    // 当前 DOM 并压栈，再回退快照整体重挂载，并恢复焦点到最近
    // 编辑块——编辑态审计 D2/D4）。菜单从鼠标打开、桥不在场，
    // 同步串靠一次 eval 向桥索取。
    let do_undo = {
        let persist = persist.clone();
        let memo_id = memo_id.clone();
        move |_| {
            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
            let persist = persist.clone();
            let memo_id = memo_id.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                );
                let sync = eval.recv::<String>().await.ok();
                step_undo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    &persist, data, &title, &memo_id, sync.as_deref(), focus_hint.read().clone(),
                );
            });
        }
    };

    let do_redo = {
        let persist = persist.clone();
        let memo_id = memo_id.clone();
        move |_| {
            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
            let persist = persist.clone();
            let memo_id = memo_id.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                );
                let sync = eval.recv::<String>().await.ok();
                step_redo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    &persist, data, &title, &memo_id, sync.as_deref(), focus_hint.read().clone(),
                );
            });
        }
    };

    // 导出笔记：语义 Markdown 下载（原版 export 的 MD 路径；
    // 附件先解析为 data: URL 再生成，原版 files 表口径）
    let export_md = {
        let memo_id = memo_id.clone();
        move |_| {
            // 原版 handleExportFormat：先关面板（动画）再导出
            animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
            let t = title.read().clone();
            let d = doc.read().clone();
            let manifest_raw = manifest.read().clone();
            let ed_status2 = ed_status;
            let memo_id = memo_id.clone();
            // 原版 noteTitle 口径：空标题以「无标题」参与内容与文件名
            let eff_title = if t.trim().is_empty() {
                "无标题".to_string()
            } else {
                t.trim().to_string()
            };
            spawn(async move {
                let files = collect_export_files(&d, &manifest_raw).await;
                let md = memo_to_markdown(&eff_title, &d, &files, &manifest_raw);
                download_text(
                    &export_filename(&eff_title, "md"),
                    &md,
                    "text/markdown;charset=utf-8",
                );
                // 成功 toast 保留（用户 2026-11-24 裁定：
                // 增强型调优，iOS 下载反馈近乎不可见）
                ed_status2.show("success", crate::i18n::t("export.done"));
                diag::log("EDIT", &format!("export md memo={memo_id} {}B", md.len()));
            });
        }
    };

    // 背景色：选色/移除走底表出场动画（原版 BgSheet
    // closeWithAnim(afterClose) 口径）——点击只发起关
    // 闭，颜色在 220ms 后底表卸载时点才经
    // BgAfter::Apply 生效（apply_bg_color 落库）。
    let set_bg = {
        let memo_id = memo_id.clone();
        move |color: Option<String>| {
            animate_bg_close(
                bg_open,
                bg_closing,
                bg_gen,
                BgAfter::Apply(color),
                data,
                bg,
                memo_id.clone(),
            );
        }
    };

    // 双栏开关（原版 toggleIndependentColumns 口径）：layout
    // 写原版形状 {version:1, mode, left, right}（归一化后
    // left/right 即分界点前后），并记 localStorage 默认值
    // 供无 layout 的备忘下次打开沿用。
    let toggle_twopane = {
        let memo_id = memo_id.clone();
        move |_| {
            let next = !*twopane.read();
            twopane.set(next);
            if let Some(st) = web_sys::window()
                .and_then(|w| w.local_storage().ok().flatten())
            {
                let _ = st.set_item(
                    "sj_editor_independent_scroll",
                    if next { "1" } else { "0" },
                );
            }
            let mut backup = data.read().clone();
            if let Some(m) = backup
                .memos
                .iter_mut()
                .find(|m| m.id.to_string() == memo_id)
            {
                let d = doc.read().clone();
                let b = column_boundary(&d, m.extra.get("layout"));
                let ids: Vec<Value> = d
                    .iter()
                    .map(|n| Value::String(n.id.as_ref().map(|i| i.to_string()).unwrap_or_default()))
                    .collect();
                let (left, right) = ids.split_at(b.min(ids.len()));
                m.extra.insert(
                    "layout".to_string(),
                    json!({
                        "version": 1,
                        "mode": if next { "independent" } else { "flow" },
                        "left": left,
                        "right": right,
                    }),
                );
            }
            data.set(backup.clone());
            diag::log("EDIT", &format!("twopane -> {next}"));
            spawn(async move {
                save_backup(&backup).await;
            });
        }
    };

    let doc_snapshot = doc.read().clone();
    let panel_state = panel.read().clone();

    let bg_state = bg.read().clone();
    let menu_state = *menu_open.read();
    let menu_closing_state = *menu_closing.read();
    let bg_sheet_state = *bg_open.read();
    let bg_closing_state = *bg_closing.read();
    let sheet_closing_state = *text_sheet_closing.read();
    let can_undo = *hist_idx.read() > 0;
    let can_redo = *hist_idx.read() + 1 < hist.read().len();
    let words = orig_char_count(&doc_snapshot);
    let sub_line = format!(
        "{} · {}",
        time_label(memo.updated_at.to_millis().unwrap_or(0)),
        crate::i18n::tf("editor.words", &[("n", &words.to_string())])
    );
    let ed_status_text = ed_status.msg.read().clone();
    let ed_status_seq = *ed_status.seq.read();
    let ed_status_kind = *ed_status.kind.read();
    let persist_attach = persist.clone();
    // 导出 HTML / PDF（原版导出面板的另两条路径）
    let export_html = {
        let memo_id = memo_id.clone();
        let memo_upd_ts = memo.updated_at.clone();
        move |_| {
            animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
            let t = title.read().clone();
            let d = doc.read().clone();
            // 副标题时间口径与原版导出一致：相对标签 timeAgo
            //（与应用内 meta_line 同函数），不是时钟标签
            let subtitle = format!(
                "{} · {}",
                crate::list::time_ago(&memo_upd_ts),
                crate::i18n::tf("editor.words", &[("n", &export_char_count(&d).to_string())])
            );
            let av = avatar_url.read().clone();
            let bgc = bg.read().clone();
            let page_bg = effective_bg(&bgc);
            let manifest_raw = manifest.read().clone();
            let ed_status2 = ed_status;
            let memo_id = memo_id.clone();
            spawn(async move {
                let assets = collect_export_assets(&subtitle, &t).await;
                // 快照缺失才需要附件表走模型渲染 fallback
                let files = if assets.snapshot_html.is_none() {
                    collect_export_files(&d, &manifest_raw).await
                } else {
                    std::collections::HashMap::new()
                };
                let html = doc_to_html(
                    &t,
                    &d,
                    &subtitle,
                    av.as_deref(),
                    &page_bg,
                    &assets,
                    &files,
                );
                let eff_title = if t.trim().is_empty() {
                    "无标题"
                } else {
                    t.trim()
                };
                download_text(
                    &export_filename(eff_title, "html"),
                    &html,
                    "text/html;charset=utf-8",
                );
                // 成功 toast 保留（用户 2026-11-24 裁定，
                // 同 export_md；HTML 用专属键 done_html，
                // 勿与 MD 的 done 混用）
                ed_status2.show("success", crate::i18n::t("export.done_html"));
                diag::log("EDIT", &format!("export html memo={memo_id} {}B", html.len()));
            });
        }
    };
    let export_pdf = {
        let memo_id = memo_id.clone();
        let memo_upd_ts = memo.updated_at.clone();
        move |_| {
            animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
            let t = title.read().clone();
            let d = doc.read().clone();
            // 副标题时间口径同 export_html：原版 timeAgo 相对标签
            let subtitle = format!(
                "{} · {}",
                crate::list::time_ago(&memo_upd_ts),
                crate::i18n::tf("editor.words", &[("n", &export_char_count(&d).to_string())])
            );
            let av = avatar_url.read().clone();
            let bgc = bg.read().clone();
            let page_bg = effective_bg(&bgc);
            let manifest_raw = manifest.read().clone();
            diag::log("EDIT", &format!("export pdf memo={memo_id}"));
            // 原版 handleExportFormat 口径：window.open 必须在点击
            // 处理函数的同步执行段内调用。WebKit 的用户激活在任何
            // 异步跳跃（spawn/await）之后即失效——旧实现把开窗 eval
            // 放在 spawn 的 future 里、等 collect 之前才执行，真机
            // （iPhone 内置浏览器）实测被弹窗拦截直接失败（Diag 只
            // 有 memo= 与 blocked 两行、无 doc 行）。dioxus-web
            // 0.7.10 的 document::eval 在创建瞬间同步执行 JS
            // （WebEvaluator::create 直接 call1，JS 无 await 时
            // 同步跑完），故开窗 eval 在此同步创建、句柄存
            // window.__mnPrintWin；recv 留到 spawn 内等待（Channel
            // 内部有 pending 缓冲，send 先于 recv 不丢消息）。
            let mut open_eval = document::eval(
                "const w = window.open('', '_blank'); window.__mnPrintWin = w || null; window.__mnPrintOpenOk = w ? 1 : 0; dioxus.send(w ? 1 : 0);",
            );
            spawn(async move {
                let mut opened = open_eval.recv::<i64>().await.unwrap_or(-1);
                if opened < 0 {
                    // 通道异常时以同步 eval 留下的窗口标志为准，
                    // 不把通道故障误报成弹窗拦截
                    let mut flag_eval = document::eval(
                        "dioxus.send(window.__mnPrintOpenOk ? 1 : 0);",
                    );
                    opened = flag_eval.recv::<i64>().await.unwrap_or(0);
                }
                if opened == 0 {
                    crate::errbadge::add_warn(&crate::i18n::t("export.pdf_blocked"), None);
                    diag::log("EDIT", "export pdf blocked by popup blocker");
                    return;
                }
                diag::log("EDIT", "export pdf window opened");
                let assets = collect_export_assets(&subtitle, &t).await;
                // 收集失败（快照 eval 无回传时 css/快照/chrome 全
                // 空）：关掉已开的空白窗并提示，不留空白页签、
                // 不写残缺文档
                if assets.css.is_empty()
                    && assets.snapshot_html.is_none()
                    && assets.chrome_html.is_none()
                {
                    let mut close_eval = document::eval(
                        "const w = window.__mnPrintWin; if (w && !w.closed) w.close(); window.__mnPrintWin = null; dioxus.send(null);",
                    );
                    let _ = close_eval.recv::<Value>().await;
                    crate::errbadge::add_warn(&crate::i18n::t("export.pdf_failed"), None);
                    diag::log("EDIT", "export pdf collect failed, window closed");
                    return;
                }
                let files = if assets.snapshot_html.is_none() {
                    collect_export_files(&d, &manifest_raw).await
                } else {
                    std::collections::HashMap::new()
                };
                let html = doc_to_html(
                    &t,
                    &d,
                    &subtitle,
                    av.as_deref(),
                    &page_bg,
                    &assets,
                    &files,
                );
                diag::log("EDIT", &format!("export pdf doc {}B", html.len()));
                // 原版 printAfterImages 口径：document.open 后
                // 写入，等全部图片就绪（单图 2.5s 上限）再隔
                // 120ms 聚焦并打印，不用固定延时赌图片加载。
                // 回传 wrote：收集期间用户把空白页签关掉时写入
                // 目标已消失，要提示而不是静默无声。
                let js = format!(
                    "const w = window.__mnPrintWin; \
                     let wrote = 0; \
                     if (w && !w.closed) {{ \
                       w.document.open(); \
                       w.document.write({}); \
                       w.document.close(); \
                       wrote = 1; \
                       const imgs = Array.prototype.slice.call(w.document.images || []); \
                       Promise.all(imgs.map((im) => im.complete ? Promise.resolve() : new Promise((res) => {{ const tm = setTimeout(res, 2500); im.onload = im.onerror = () => {{ clearTimeout(tm); res(); }}; }}))) \
                         .then(() => setTimeout(() => {{ if (!w.closed) {{ w.focus(); w.print(); }} }}, 120)); \
                     }} \
                     dioxus.send(wrote);",
                    serde_json::to_string(&html).unwrap_or_default()
                );
                let mut eval = document::eval(&js);
                let wrote = eval.recv::<i64>().await.unwrap_or(0);
                if wrote == 0 {
                    crate::errbadge::add_warn(&crate::i18n::t("export.pdf_failed"), None);
                    diag::log("EDIT", "export pdf window gone before write");
                }
            });
        }
    };

    // 头像选择：读为 data URL 存入 backup.avatars[memoId]（原版
    // saveAvatarToDB 的备份等价物），整包落库
    let pick_avatar = {
        let memo_id = memo_id.clone();
        move |_| {
            let memo_id = memo_id.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "const f = document.getElementById('file-avatar'); const file = f && f.files && f.files[0]; if (!file) { dioxus.send(''); } else { const r = new FileReader(); r.onload = () => dioxus.send(String(r.result || '')); r.onerror = () => dioxus.send(''); r.readAsDataURL(file); }",
                );
                if let Ok(url) = eval.recv::<String>().await {
                    if !url.is_empty() {
                        avatar_url.set(Some(url.clone()));
                        let mut backup = data.read().clone();
                        let mut av = backup
                            .avatars
                            .take()
                            .filter(|v| v.is_object())
                            .unwrap_or_else(|| json!({}));
                        if let Some(obj) = av.as_object_mut() {
                            obj.insert(memo_id.clone(), Value::String(url));
                        }
                        backup.avatars = Some(av);
                        data.set(backup.clone());
                        save_backup(&backup).await;
                        diag::log("EDIT", &format!("avatar set memo={memo_id}"));
                    }
                }
            });
        }
    };

    // 媒体文件选择完成：按 media_req 分发（替换块 / 图文换图）
    let on_media_files = {
        let persist = persist.clone();
        move |_| {
            let persist = persist.clone();
            spawn(async move {
                handle_media_files(doc, title, data, manifest, media_req, &persist).await;
            });
        }
    };

    let _scheme = *scheme_tick.read();
    let scrolled = *ed_scroll.read() > 30.0;
    let avatar_state = avatar_url.read().clone();
    // 标题坞：胶囊子树已静态壳化（TitleCapsule，见 title.rs）
    // ——渲染路径不再计算标题的类/几何，全部归 TitleController。
    let meta_line = format!(
        "{} · {}",
        crate::list::time_ago(&memo.updated_at),
        crate::i18n::tf("editor.words", &[("n", &words.to_string())])
    );
    let sheet_state = text_sheet.read().clone();
    // 卡片浮层菜单视图（卡片交互专项）：定位与斜杠面板同
    // 口径——卡锚优先贴卡下方、放不下翻上方；点锚贴点下
    // 方、同理上翻；横向 12px 视口钳制。面板宽 216
    // （.card-menu-panel）、高 = 项数×50 + 内距 14。
    let card_menu_state = card_menu.read().clone();
    let card_menu_view = card_menu_state.as_ref().map(|cm| {
        let (vw, vh) = web_sys::window()
            .map(|w| {
                (
                    w.inner_width().ok().and_then(|v| v.as_f64()).unwrap_or(0.0),
                    w.inner_height().ok().and_then(|v| v.as_f64()).unwrap_or(0.0),
                )
            })
            .unwrap_or((0.0, 0.0));
        let has_edit = matches!(
            cm.wtype.as_str(),
            "imgTextCard" | "imageTextRow" | "image" | "gallery" | "musicCard"
        );
        let h = if has_edit { 114.0 } else { 64.0 };
        let (base_x, below_y, above_y) = if let Some((px, py)) = cm.anchor_point {
            (px, py + 8.0, py - h - 8.0)
        } else {
            (cm.rect.0, cm.rect.1 + cm.rect.3 + 8.0, cm.rect.1 - h - 8.0)
        };
        let top = if below_y + h > vh - 12.0 { above_y } else { below_y }.max(12.0);
        let left = base_x.max(12.0).min((vw - 216.0 - 12.0).max(12.0));
        (format!("left:{left}px;top:{top}px"), has_edit)
    });
    let cm_bid = card_menu_state
        .as_ref()
        .map(|c| c.bid.clone())
        .unwrap_or_default();
    let cm_wtype = card_menu_state
        .as_ref()
        .map(|c| c.wtype.clone())
        .unwrap_or_default();
    let sheet_editing = *sheet_edit.read();
    let twopane_state = *twopane.read();
    // 双栏（宽屏）：独立与流式同为两个物理栏容器、同一
    // 渲染，差异只在分栏来源与滚动形态——独立成员由
    // layout 锚决定（锚优先、无锚规范估高——
    // column_boundary）；流式不读不写 layout，分界恒为
    // 规范估高切分（canonical_boundary，文档内容的确定
    // 性纯函数，同文档同结果、重开一致）。宽屏流式不跨
    // 栏（用户 2026-11-24 裁定，覆盖 A-2 跨栏设计）：
    // 任何块都留在栏内，视觉与双栏一致。此前 flow 形态
    // 走 CSS 多列：成员由浏览器按实测高平衡，卡片/图片
    // 加载前后分界漂移、回来再进来块跨栏迁移。
    let two_col = twopane_state && *wide.read();
    let show_cols = *wide.read();
    let boundary = if two_col {
        let layout = data
            .read()
            .memos
            .iter()
            .find(|m| m.id.to_string() == memo_id)
            .and_then(|m| m.extra.get("layout").cloned());
        column_boundary(&doc_snapshot, layout.as_ref())
    } else if show_cols {
        canonical_boundary(&doc_snapshot)
    } else {
        0
    };
    // 尾随空段已在模型层（materialize_trails 于打开时与会
    // 话内 effect 补齐），渲染无需再算视图层尾随位置。
    // 跨块列表组合并（M6）：按流区间预计算渲染单元；双栏
    // 左右栏各自成流、不跨栏成组（原版同流相邻才成组）。
    let editing_id = md_edit.read().clone();
    let active_id = active_edit.read().clone();
    // 批 11 MD-P2 单点化：段落 md 分类每渲染趟只算一次
    // （para_kinds 与 doc_snapshot 下标对齐），flow_runs 的
    // 组员判定与 EditorBlock 的预览门控共同消费——此前两处
    // 各自 plain_text + md_classify 重跑。两个消费方都只需
    // 分类有无，故只存 bool（不克隆 MdKind 本体）。
    let para_kinds: Vec<bool> = doc_snapshot
        .iter()
        .map(|n| {
            n.block_type() == Some("paragraph")
                && crate::blocks::md_classify(&n.plain_text()).is_some()
        })
        .collect();
    // PERF（第八批 T2）：三组 runs 此前每渲无条件全算，但
    // 渲染端只消费其中一组（宽屏用 left/right、窄屏用
    // all），另两组是纯浪费（每组逐块 plain_text +
    // md_classify）。按 show_cols 只算会被消费的组，未用
    // 组留空 Vec——rsx 分支与所用组严格对应，渲染结果
    // 不变。
    let (runs_all, runs_left, runs_right) = if show_cols {
        (
            Vec::new(),
            flow_runs(
                &doc_snapshot,
                0..boundary,
                &para_kinds,
                editing_id.as_deref(),
                active_id.as_deref(),
            ),
            flow_runs(
                &doc_snapshot,
                boundary..doc_snapshot.len(),
                &para_kinds,
                editing_id.as_deref(),
                active_id.as_deref(),
            ),
        )
    } else {
        (
            flow_runs(
                &doc_snapshot,
                0..doc_snapshot.len(),
                &para_kinds,
                editing_id.as_deref(),
                active_id.as_deref(),
            ),
            Vec::new(),
            Vec::new(),
        )
    };
    let export_open = *show_export.read();
    let export_is_closing = *export_closing.read();
    // 全关关闭中（遮挡续修）：命中即刻释放——遮罩在卸载
    // 计时落定前不再拦截点按，计时停摆也锁不住页面；回
    // 菜单的关闭不释放（菜单仍在场，遮罩归菜单所有）。
    let export_releasing = export_is_closing
        && *export_anim.read() == EXPORT_ANIM_CLOSING
        && !*export_to_menu.read();
    // 打开导出面板（原版 openExportPanel 时序）：先让菜
    // 单播满 220ms 出场，完成后才由 begin_export_open 挂
    // 面板并弹簧入场（面板侧开场见 export.rs）。
    let open_export = move |_| {
        animate_menu_close(
            menu_open,
            menu_closing,
            menu_gen,
            MenuAfter::Export,
            show_export,
            export_closing,
            export_gen,
            export_anim,
            bg_open,
        );
    };
    let link_state = link_for.read().clone();
    let (link_x, link_top, link_bottom) = *link_pos.read();
    // 根节点进/出场（原版 editor.js 根 style 三态，时长/曲线
    // 字面量与原版一致、不走 var()）：关闭中 slideOut
    // forwards；进场 slideIn both、animDone 后摘除。摘除不能
    // 用空串：dioxus-web 的 style 保留路径只覆写不删属性，
    // 声明从 style 串里消失不会从 CSSOM 移除（计时与置位
    // 均实测到达、动画却常驻），须显式 animation:none 覆写
    let page_anim = if closing {
        "animation:slideOutToRight 0.28s cubic-bezier(0.22,0.61,0.36,1) forwards;"
    } else if *page_anim_done.read() {
        "animation:none;"
    } else {
        "animation:slideInFromRight 0.28s cubic-bezier(0.22,0.61,0.36,1) both;"
    };

    rsx! {
        div {
            id: "editor-root",
            // 有效背景（自定义色深色压暗 / 默认 #FAFAFA / 深色 #000）；
            // 写具体色不用 var()（CSSOM 对 var() 简写静默拒绝的坑）。
            // 恒自带有效背景、关闭中不改 transparent：离页窗口
            // 内页面状态未提交（Nav 提交点后移，selected 保留
            // 至卸载帧），根色派生同刻给出同一备忘的有效背景，
            // 本节点自有底与根色单源同值——不是异色第二来源，
            // 编辑器以自身底色出场、衬底不透入页色；提交帧本
            // 实例卸载与根色翻值同属一次渲染提交（返回列表顶
            // 部白带定案终版，见 main.rs 根色派生注）。曾试
            // closing 改 transparent：带区虽正，衬底透出列表
            // 色 8 色阶成交换式残差，已回退。
            style: format!(
                "background:{};{}",
                effective_bg(&bg_state),
                page_anim
            ),
            button {
                class: "editor-fab left",
                aria_label: "{crate::i18n::t(\"editor.back_aria\")}",
                // 审计 E-9：原版 fab 为 onPointerDown 触发
                // （不等抬手）+ stopPropagation 防穿透。
                onpointerdown: move |e: Event<PointerData>| {
                    e.stop_propagation();
                    go_back(e);
                },
                dangerous_inner_html: "{crate::icons::back_markup()}",
            }
            button {
                class: "editor-fab right",
                aria_label: "{crate::i18n::t(\"editor.menu_aria\")}",
                // 审计 E-9：同返回 fab，pointerdown 触发。
                onpointerdown: move |e: Event<PointerData>| {
                    e.stop_propagation();
                    // 同 go_back：菜单动作（导出/删除等）读标题
                    // 信号前，先同步失焦落定标题会话。
                    blur_title_if_focused();
                    // 读信号现值而非渲染期快照：状态刚变而未重渲染时
                    // 快照会让开关方向反转（冒烟实测踩过）
                    if *menu_open.read() {
                        if *export_anim.read() == EXPORT_ANIM_CLOSING {
                            // 导出面板关闭中点按 = 改道回菜单，不
                            // 重排关闭（原版 toggleEditorMenu 与面
                            // 板状态机解耦、点按永不被面板吞掉；
                            // Rust 合并架构的等价落点是关闭照常落
                            // 定、终点由全关改为菜单）。去向在关
                            // 闭完成时按 export_to_menu 现值结算
                            // （见 animate_export_close），计时与
                            // 动画不重启；已是回菜单去向时无操作。
                            if !*export_to_menu.read() {
                                export_to_menu.set(true);
                                diag::log("EDIT", "export close diverted to menu");
                            }
                        } else if *show_export.read() {
                            animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
                        } else if *menu_closing.read() {
                            // 关闭中再按 = 重开（原版 toggle 在
                            // menuClosing 时走 openEditorMenu 清计时）
                            cancel_menu_close(menu_gen, menu_closing);
                        } else {
                            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                        }
                    } else {
                        // 开菜单（原版 openEditorMenu 口径）：挂载即
                        // closing 态，双 rAF 后撤下让 transition 弹
                        // 簧入场；入场代际守卫——未落定即被关闭/重
                        // 开取代时不得把面板翻回。
                        let gen = *menu_gen.read() + 1;
                        menu_gen.set(gen);
                        let memo_id = memo_id.clone();
                        spawn(async move {
                            let mut eval = document::eval(
                                "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                            );
                            let mut d = doc.read().clone();
                            if let Ok(s) = eval.recv::<String>().await {
                                apply_sync_map(&mut d, &s);
                                doc.set(d.clone());
                                hist_push(
                                    hist,
                                    hist_idx,
                                    hist_clock,
                                    HistSnap {
                                        doc: serde_json::to_string(&d)
                                            .unwrap_or_default(),
                                        layout: memo_layout_json(&data.read(), &memo_id),
                                    },
                                    false,
                                );
                            }
                            if *menu_gen.read() != gen {
                                return;
                            }
                            menu_closing.set(true);
                            menu_open.set(true);
                            // 同 begin_export_open 的双触发口径：
                            // rAF 为主、setTimeout 兜底防唤醒丢失
                            let mut eval2 = document::eval(
                                "requestAnimationFrame(() => requestAnimationFrame(() => dioxus.send(null))); setTimeout(() => dioxus.send(null), 150);",
                            );
                            let _ = eval2.recv::<Value>().await;
                            if *menu_gen.read() != gen {
                                return;
                            }
                            menu_closing.set(false);
                        });
                    }
                },
                dangerous_inner_html: "{crate::icons::dots_markup()}",
            }
            div {
                class: if scrolled { "editor-title-dock scrolled" } else { "editor-title-dock" },
                // 审计 E-8(b)：头像形态复原为 button（原版
                // editor.js 口径，此前为 label）；点击经 eval
                // 唤起 #file-avatar（与 #file-media 唤起同
                // 路径，input 移出 button 作同级）。Safari
                // 瞬时激活是否成立以 probe_avatar_button
                // 链尾实跑为关单条件——不过则回退 label +
                // aria-label 等价收口并登记。
                button {
                    class: "editor-avatar-button",
                    r#type: "button",
                    aria_label: "{crate::i18n::t(\"editor.avatar_aria\")}",
                    style: if avatar_state.is_some() { "border:none;background:transparent;backdrop-filter:none;-webkit-backdrop-filter:none" } else { "" },
                    onclick: move |_| {
                        spawn(async move {
                            let mut eval = document::eval(
                                "const i = document.getElementById('file-avatar'); if (i) i.click(); dioxus.send(null);",
                            );
                            let _ = eval.recv::<Value>().await;
                        });
                    },
                    if let Some(u) = &avatar_state {
                        img { src: "{u}", style: "width:100%;height:100%;object-fit:cover;border-radius:50%;display:block" }
                    } else {
                        span { dangerous_inner_html: "{crate::icons::dino_markup(60, 10)}" }
                    }
                }
                input {
                    id: "file-avatar",
                    r#type: "file",
                    accept: "image/*",
                    class: "hidden-input",
                    onchange: pick_avatar,
                }
                TitleCapsule {
                    key: "{memo_id}",
                    memo_id: memo_id.clone(),
                    initial_title: initial_title.clone(),
                    meta_line: meta_line.clone(),
                    on_commit: title_commit,
                    on_session: title_session,
                }
            }
            if !ed_status_text.is_empty() {
                // key = seq（非文案）：同文案重触发也重挂（审计
                // G1）；形态与备份页同规格全宽条（审计 G2）。
                // 现仅导出 MD/HTML 成功 toast 走此通道，
                // 失败一律 errbadge（E-1）。
                div { key: "{ed_status_seq}", class: "backup-toast",
                    if ed_status_kind == "info" {
                        span { class: "backup-toast-spinner" }
                    } else if ed_status_kind == "success" {
                        span { class: "backup-toast-icon", "✅" }
                    } else {
                        span { class: "backup-toast-icon", "❌" }
                    }
                    span { class: "backup-toast-text", "{ed_status_text}" }
                }
            }
            if let Some((cm_style, cm_has_edit)) = card_menu_view.clone() {
                // 卡片浮层菜单（卡片交互专项）：样式与「更多
                // 菜单」同源（.menu-inner/.menu-item + 玻璃面
                // 令牌），项 = 编辑（有内部可编辑子区域的卡才
                // 有）+ 删除（危险色）。点遮罩关菜单并退出编
                // 辑态（点卡外区域退出的口径）。
                div {
                    class: "card-menu-scrim",
                    onclick: move |_| {
                        card_menu.set(None);
                        let ce = card_edit.read().clone();
                        if let Some(b) = ce {
                            card_edit.set(None);
                            diag::log("EDIT", &format!("card edit exit {b} (scrim)"));
                        }
                    },
                }
                div { class: "card-menu-panel", style: "{cm_style}",
                    div { class: "menu-inner",
                        if cm_has_edit {
                            button {
                                class: "menu-item",
                                onclick: {
                                    let b = cm_bid.clone();
                                    let wt = cm_wtype.clone();
                                    let persist_m = persist.clone();
                                    move |_| {
                                        card_menu.set(None);
                                        if wt == "musicCard" {
                                            // 音乐卡「编辑」= 设链接即时
                                            // 动作（无内部子区域可门禁，
                                            // 不设持续编辑态）：原悬浮钮
                                            // 的 prompt 流程原样移入。
                                            let bid2 = b.clone();
                                            let persist2 = persist_m.clone();
                                            spawn(async move {
                                                let mut eval = document::eval(&format!(
                                                    "dioxus.send(window.prompt({}, '') || '');",
                                                    serde_json::to_string(&crate::i18n::t("music.url_prompt")).unwrap_or_default()
                                                ));
                                                if let Ok(url) = eval.recv::<String>().await {
                                                    let url = url.trim().to_string();
                                                    if !url.is_empty() {
                                                        let mut d = doc.read().clone();
                                                        if let Some(loc) = find_loc(&d, &bid2) {
                                                            let n = node_at_mut(&mut d, loc);
                                                            n.extra.insert("url".into(), json!(url.clone()));
                                                            n.extra.insert("meta".into(), serde_json::Value::Null);
                                                            n.extra.insert("status".into(), json!("loading"));
                                                            doc.set(d.clone());
                                                            persist2.call(d, title.read().clone(), data);
                                                            diag::log("EDIT", &format!("music url set {bid2}"));
                                                            spawn_resolve_card(doc, bid2.clone(), url, title, data, persist2.clone(), None, None);
                                                        }
                                                    }
                                                }
                                            });
                                        } else {
                                            card_edit.set(Some(b.clone()));
                                            diag::log("EDIT", &format!("card edit enter {b} ({wt})"));
                                        }
                                    }
                                },
                                span { class: "menu-icon", crate::icons::Icon { name: "edit".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                                span { class: "menu-copy",
                                    span { class: "menu-title", "{crate::i18n::t(\"cardmenu.edit\")}" }
                                }
                            }
                        }
                        button {
                            class: "menu-item danger",
                            onclick: {
                                let b = cm_bid.clone();
                                let persist_d = persist.clone();
                                move |_| {
                                    let mut d = doc.read().clone();
                                    if let Some(Loc::Top(i)) = find_loc(&d, &b) {
                                        d.remove(i);
                                        doc.set(d.clone());
                                        persist_d.call(d, title.read().clone(), data);
                                        diag::log("EDIT", &format!("card menu delete {b}"));
                                    }
                                    card_menu.set(None);
                                    if sel_block.read().as_deref() == Some(b.as_str()) {
                                        sel_block.set(None);
                                    }
                                    if card_edit.read().as_deref() == Some(b.as_str()) {
                                        card_edit.set(None);
                                    }
                                }
                            },
                            span { class: "menu-icon", crate::icons::Icon { name: "del".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-danger)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"editor.delete_block\")}" }
                            }
                        }
                    }
                }
            }
            if menu_state {
                div {
                    class: "menu-scrim",
                    style: if export_releasing { "pointer-events:none" } else { "" },
                    onclick: move |_| {
                        if *show_export.read() {
                            animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
                        } else {
                            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                        }
                    },
                }
                if export_open {
                    // 导出面板（原版 editor.js 内联样式口径）：dialog
                    // 语义、内层 padding 7 纵列（头部固定/选项滚动/
                    // 尾注固定）、每项带 ›、PDF 尾注、进出场走
                    // closing 态 + CSS transition（度量覆盖在
                    // panels.css 的导出面板修正段）
                    div { class: "editor-export-panel",
                        role: "dialog",
                        aria_modal: "true",
                        aria_label: "{crate::i18n::t(\"export.title\")}",
                        // pointer-events 两态都显式给值：Dioxus 的
                        // style 补丁不摘除消失的属性，只给 none 不
                        // 给 auto 会让关闭态的值残留到打开态、面板
                        // 整体点不动（出场链探针实证）。
                        style: if export_is_closing { "opacity:0;transform:translateY(-10px) scale(0.94);transition:opacity 180ms ease,transform 220ms cubic-bezier(0.34,1.56,0.64,1);will-change:opacity,transform;pointer-events:none" } else { "opacity:1;transform:translateY(0) scale(1);transition:opacity 180ms ease,transform 220ms cubic-bezier(0.34,1.56,0.64,1);will-change:opacity,transform;pointer-events:auto" },
                        div { class: "export-inner",
                            div { class: "export-head",
                                button {
                                    class: "export-back",
                                    aria_label: "{crate::i18n::t(\"export.back_aria\")}",
                                    onclick: move |_| animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, true),
                                    dangerous_inner_html: "{crate::icons::back_markup()}",
                                }
                                div { class: "export-title", "{crate::i18n::t(\"export.title\")}" }
                            }
                            div { class: "export-choices",
                                button { class: "editor-export-choice", onclick: export_md,
                                    "data-export-format": "markdown",
                                    aria_label: "{crate::i18n::tf(\"export.as\", &[(\"label\", &crate::i18n::t(\"export.md\"))])}",
                                    span { class: "export-badge", "MD" }
                                    span { class: "export-copy",
                                        span { class: "export-label", "{crate::i18n::t(\"export.md\")}" }
                                        span { class: "export-detail", "{crate::i18n::t(\"export.md_detail\")}" }
                                    }
                                    span { class: "export-chevron", "›" }
                                }
                                button { class: "editor-export-choice", onclick: export_html,
                                    "data-export-format": "html",
                                    aria_label: "{crate::i18n::tf(\"export.as\", &[(\"label\", &crate::i18n::t(\"export.html\"))])}",
                                    span { class: "export-badge", "<>" }
                                    span { class: "export-copy",
                                        span { class: "export-label", "{crate::i18n::t(\"export.html\")}" }
                                        span { class: "export-detail", "{crate::i18n::t(\"export.html_detail\")}" }
                                    }
                                    span { class: "export-chevron", "›" }
                                }
                                button { class: "editor-export-choice", onclick: export_pdf,
                                    "data-export-format": "pdf",
                                    aria_label: "{crate::i18n::tf(\"export.as\", &[(\"label\", &crate::i18n::t(\"export.pdf\"))])}",
                                    span { class: "export-badge sm", "PDF" }
                                    span { class: "export-copy",
                                        span { class: "export-label", "{crate::i18n::t(\"export.pdf\")}" }
                                        span { class: "export-detail", "{crate::i18n::t(\"export.pdf_detail\")}" }
                                    }
                                    span { class: "export-chevron", "›" }
                                }
                            }
                            div { class: "export-note", "{crate::i18n::t(\"export.pdf_note\")}" }
                        }
                    }
                } else {
                    div { class: if menu_closing_state { "editor-menu-panel is-closing" } else { "editor-menu-panel" },
                        // 双栏开关行：原版专属结构（editor.js:2807-2827
                        // + editor-shell.css .editor-column-mode-toggle/
                        // -icon/-copy/-title/-subtitle/.editor-column-
                        // toggle-track/-knob，令牌尺寸 42×26/钮 20/
                        // 行程 16/开态 accent）；可见性由该类自带的
                        // display:none !important + 宽屏媒体规则掌管，
                        // 不再复用 .menu-item/.switch。
                        button {
                            r#type: "button",
                            class: "editor-column-mode-toggle",
                            role: "switch",
                            aria_checked: if twopane_state { "true" } else { "false" },
                            aria_label: "{crate::i18n::t(\"menu.twopane\")}",
                            onclick: toggle_twopane,
                            span {
                                class: "editor-column-mode-icon",
                                aria_hidden: "true",
                                crate::icons::Icon { name: "columns".to_string(), size: 20, stroke_width: "1.8".to_string(), stroke: "currentColor".to_string() }
                            }
                            span { class: "editor-column-mode-copy",
                                span { class: "editor-column-mode-title", "{crate::i18n::t(\"menu.twopane\")}" }
                                span { class: "editor-column-mode-subtitle", "{crate::i18n::t(\"menu.twopane_sub\")}" }
                            }
                            span {
                                class: "editor-column-toggle-track",
                                aria_hidden: "true",
                                aria_checked: if twopane_state { "true" } else { "false" },
                                span { class: "editor-column-toggle-knob" }
                            }
                        }
                        // 撤销/重做无历史时不禁用（原版口径，审计
                        // E-4）：dis 类仅视觉变淡，点按仍走
                        // do_undo/do_redo 先关菜单，step_* 在
                        // idx 边界不改 doc。
                        button {
                            class: if can_undo { "menu-item" } else { "menu-item dis" },
                            onclick: do_undo,
                            span { class: "menu-icon", crate::icons::Icon { name: "undo".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.undo\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.undo_sub\")}" }
                            }
                        }
                        button {
                            class: if can_redo { "menu-item" } else { "menu-item dis" },
                            onclick: do_redo,
                            span { class: "menu-icon", crate::icons::Icon { name: "redo".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.redo\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.redo_sub\")}" }
                            }
                        }
                        label { class: "menu-item", style: "margin-top:4px", r#for: "file-attach",
                            // 审计 E-6（时机订正 2026-11-24，
                            // 确诊 diagnose_addatt_imgpage.md）：
                            // 关菜单须在 click 内启动，不得在
                            // pointerdown 预关——预关使面板在
                            // 手势中途挂上 .is-closing，其
                            // pointer-events:none 摘掉面板命中，
                            // 随后的兼容 mousedown/click 改道
                            // 离开 label（box 实测落 menu-
                            // scrim、真机穿透落到下方图片块），
                            // label 收不到 click、原生唤起链
                            // 断裂，文件选择永不调起。click 内
                            // 启动则唤起行为把合成 click 直接
                            // 派发到 input 本体（不经坐标命中），
                            // 关闭再快也够不着；选择器取消（无
                            // onchange）时菜单已退场不残留，
                            // E-6 目标保持。label 原生唤起链不
                            // 改，避免 button+eval 路径丢 Safari
                            // 瞬时激活。
                            onclick: move |_| {
                                animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                            },
                            span { class: "menu-icon", crate::icons::Icon { name: "attach".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.attach\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.attach_sub\")}" }
                            }
                            span { class: "menu-chevron", "›" }
                        }
                        div { class: "menu-section",
                            button {
                                class: "menu-item",
                                onclick: open_export,
                                span { class: "menu-icon", crate::icons::Icon { name: "export".to_string(), size: 20, stroke_width: "2.2".to_string(), stroke: "var(--color-accent)".to_string() } }
                                span { class: "menu-copy",
                                    span { class: "menu-title", "{crate::i18n::t(\"menu.export\")}" }
                                    span { class: "menu-sub", "{crate::i18n::t(\"menu.export_sub\")}" }
                                }
                                span { class: "menu-chevron", "›" }
                            }
                        }
                        button {
                            class: "menu-item",
                            style: "margin-top:4px",
                            onclick: move |_| {
                                // 原版：closeEditorMenu 后 220ms
                                // 才挂底表（菜单退场时序承接）
                                animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::Bg, show_export, export_closing, export_gen, export_anim, bg_open);
                            },
                            span { class: "menu-icon", crate::icons::Icon { name: "palette".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-purple)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.bg\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.bg_sub\")}" }
                            }
                            span { class: "menu-chevron", "›" }
                        }
                    }
                }
            }
            if bg_sheet_state {
                div {
                    class: "sheet-scrim",
                    // MODAL 量测（审计 §6-4 补 open 行，与
                    // animate_bg_close 的 close 行成对）。
                    onmounted: move |_| diag::log_modal("sheet-bg", "open"),
                    onclick: {
                        let memo_id = memo_id.clone();
                        move |_| animate_bg_close(bg_open, bg_closing, bg_gen, BgAfter::None, data, bg, memo_id.clone())
                    },
                }
                div { class: if bg_closing_state { "sheet-wrap is-closing" } else { "sheet-wrap" },
                    div { class: "bg-sheet",
                        div { class: "bg-head",
                            div { class: "bg-title", "{crate::i18n::t(\"bg.title\")}" }
                            div { class: "bg-sub", "{crate::i18n::t(\"bg.sub\")}" }
                        }
                        div { class: "bg-grid",
                            for (ci, c) in BG_COLORS.into_iter().enumerate() {
                                button {
                                    key: "{c}",
                                    class: if bg_state.as_deref() == Some(c) { "bg-dot sel" } else { "bg-dot" },
                                    aria_label: "{bg_color_name(ci)}",
                                    style: "background:{c}",
                                    onclick: {
                                        let mut set_bg = set_bg.clone();
                                        move |_| set_bg(Some(c.to_string()))
                                    },
                                    if bg_state.as_deref() == Some(c) {
                                        span { dangerous_inner_html: "{crate::icons::svg_markup(\"check\", 20, \"2.5\", \"var(--color-accent)\")}" }
                                    }
                                }
                            }
                        }
                        if bg_state.is_some() {
                            div { class: "bg-remove-wrap",
                                button {
                                    class: "bg-remove",
                                    onclick: {
                                        let mut set_bg = set_bg.clone();
                                        move |_| set_bg(None)
                                    },
                                    span { class: "col",
                                        span { class: "row",
                                            crate::icons::Icon { name: "del".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-danger-bright)".to_string() }
                                            span { class: "tx", "{crate::i18n::t(\"bg.remove\")}" }
                                        }
                                        span { class: "note", "{crate::i18n::t(\"bg.note\")}" }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            div {
                class: if twopane_state { "detail spread" } else { "detail" },
                key: "{epoch}",
                div { class: "editor-pad editor-spread",
                    if show_cols {
                        div { class: {
                            let mut c = if two_col { "editor-body is-independent-scroll".to_string() } else { "editor-body is-flow-columns".to_string() };
                            if !*typed.read()
                                && doc_snapshot.len() == 1
                                && doc_snapshot[0].node_type.as_deref() == Some("paragraph")
                                && placeholder_shows(&doc_snapshot[0])
                            {
                                c.push_str(" show-placeholder");
                            }
                            c
                        },
                            div { class: "editor-column", "data-editor-column": "left",
                                for run in runs_left.iter() {
                                    {
                                        match run {
                                            FlowRun::Single(bi) => {
                                                let block = &doc_snapshot[*bi];
                                                rsx! {
                                                    EditorBlock { key: "{epoch}-{block.id.clone().unwrap_or_default()}", node: block.clone(), gen, doc, title, data, persist: persist.clone(), media_req, para_md: para_kinds[*bi] }
                                                }
                                            }
                                            FlowRun::ListGroup(idxs) => {
                                                let gtext = idxs.iter().map(|&ix| doc_snapshot[ix].plain_text().trim().to_string()).collect::<Vec<_>>().join("\n");
                                                let gbids: Vec<String> = idxs.iter().map(|&ix| doc_snapshot[ix].id.clone().unwrap_or_default()).collect();
                                                let gfirst = gbids.first().cloned().unwrap_or_default();
                                                let glast = *idxs.last().unwrap();
                                                rsx! {
                                                    MergedListPreview { key: "{epoch}-lg-{gfirst}", bids: gbids, text: gtext, doc, title, data, persist: persist.clone() }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            div { class: "editor-column", "data-editor-column": "right",
                                for run in runs_right.iter() {
                                    {
                                        match run {
                                            FlowRun::Single(bi) => {
                                                let block = &doc_snapshot[*bi];
                                                rsx! {
                                                    EditorBlock { key: "{epoch}-{block.id.clone().unwrap_or_default()}", node: block.clone(), gen, doc, title, data, persist: persist.clone(), media_req, para_md: para_kinds[*bi] }
                                                }
                                            }
                                            FlowRun::ListGroup(idxs) => {
                                                let gtext = idxs.iter().map(|&ix| doc_snapshot[ix].plain_text().trim().to_string()).collect::<Vec<_>>().join("\n");
                                                let gbids: Vec<String> = idxs.iter().map(|&ix| doc_snapshot[ix].id.clone().unwrap_or_default()).collect();
                                                let gfirst = gbids.first().cloned().unwrap_or_default();
                                                let glast = *idxs.last().unwrap();
                                                rsx! {
                                                    MergedListPreview { key: "{epoch}-lg-{gfirst}", bids: gbids, text: gtext, doc, title, data, persist: persist.clone() }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        div { class: if !*typed.read()
                            && doc_snapshot.len() == 1
                            && doc_snapshot[0].node_type.as_deref() == Some("paragraph")
                            && placeholder_shows(&doc_snapshot[0])
                        { "editor-body show-placeholder" } else { "editor-body" },
                            for run in runs_all.iter() {
                                {
                                    match run {
                                        FlowRun::Single(bi) => {
                                            let block = &doc_snapshot[*bi];
                                            rsx! {
                                                EditorBlock { key: "{epoch}-{block.id.clone().unwrap_or_default()}", node: block.clone(), gen, doc, title, data, persist: persist.clone(), media_req, para_md: para_kinds[*bi] }
                                            }
                                        }
                                        FlowRun::ListGroup(idxs) => {
                                            let gtext = idxs.iter().map(|&ix| doc_snapshot[ix].plain_text().trim().to_string()).collect::<Vec<_>>().join("\n");
                                            let gbids: Vec<String> = idxs.iter().map(|&ix| doc_snapshot[ix].id.clone().unwrap_or_default()).collect();
                                            let gfirst = gbids.first().cloned().unwrap_or_default();
                                            let glast = *idxs.last().unwrap();
                                            rsx! {
                                                MergedListPreview { key: "{epoch}-lg-{gfirst}", bids: gbids, text: gtext, doc, title, data, persist: persist.clone() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                {
                    // 反向链接（原版 editor.js:3271-3284）：引用本篇
                    // 标题的备忘现算列表，非空才渲染；条目点击直接
                    // 导航（来源必存在，不新建）。切篇前先落盘。
                    let backlinks = backlinks_cached(&bl_cache, &data.read().memos, &memo_id, &title.read());
                    if backlinks.is_empty() {
                        rsx! {}
                    } else {
                        let bl_aria = crate::i18n::t("editor.backlinks_aria");
                        let bl_title = crate::i18n::t("editor.backlinks");
                        rsx! {
                            section { class: "wiki-backlinks", "aria-label": "{bl_aria}",
                                h2 { class: "wiki-backlinks-title", "{bl_title}" }
                                div { class: "wiki-backlinks-list",
                                    for (sid, stitle) in backlinks.iter() {
                                        {
                                            let stitle = stitle.clone();
                                            let persist_b = persist.clone();
                                            let label = if stitle.trim().is_empty() { crate::i18n::t("editor.untitled") } else { stitle.clone() };
                                            rsx! {
                                                button {
                                                    key: "{sid}",
                                                    r#type: "button",
                                                    class: "wiki-backlink",
                                                    onclick: move |_| {
                                                        persist_b.call(doc.read().clone(), title.read().clone(), data);
                                                        diag::log("WIKI", &format!("backlink -> '{stitle}'"));
                                                        on_open_wiki.call(stitle.clone());
                                                    },
                                                    "{label}"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            input {
                id: "file-attach",
                r#type: "file",
                accept: "image/*,application/pdf,text/plain,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                multiple: true,
                class: "hidden-input",
                onchange: move |_| {
                    animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                    show_export.set(false);
                    let persist = persist_attach.clone();
                    spawn(async move {
                        attach_file(doc, title, data, manifest, &persist).await;
                    });
                },
            }
            input {
                id: "file-media",
                r#type: "file",
                accept: "image/*",
                multiple: true,
                class: "hidden-input",
                onchange: on_media_files,
            }
            if let Some((bid, _txt)) = sheet_state {
                div {
                    class: if sheet_closing_state { "image-text-sheet-backdrop is-closing" } else { "image-text-sheet-backdrop" },
                    // MODAL 量测（审计 §6-4 补 open 行，与
                    // animate_text_sheet_close 的 close 行成对）。
                    onmounted: move |_| diag::log_modal("sheet-media", "open"),
                    // 文本逐键已写回落盘（D-20），点遮罩直接
                    // 关表、无待存草稿。
                    onclick: move |_| {
                        animate_text_sheet_close(text_sheet, text_sheet_closing, text_sheet_gen);
                    },
                }
                div { class: if sheet_closing_state { "image-text-sheet-wrap is-closing" } else { "image-text-sheet-wrap" },
                    section {
                        class: "image-text-sheet",
                        id: "image-text-sheet-dialog",
                        role: "dialog",
                        "aria-modal": "true",
                        "aria-labelledby": "image-text-sheet-title",
                        tabindex: -1,
                        // 对话框语义与焦点管理（原版
                        // ImageTextSheet 口径，审计 D-20/E-11）：
                        // 挂载即聚焦 dialog 并装 Tab 焦点陷阱
                        // （document 级具名监听，关表到点在
                        // animate_text_sheet_close 里摘除并归
                        // 还焦点）。
                        onmounted: move |_| {
                            spawn(async move {
                                let mut eval = document::eval(
                                    "if (window.__mnSheetTrap) document.removeEventListener('keydown', window.__mnSheetTrap); \
                                     const focusEl = (el) => { if (!el) return; try { el.focus({ preventScroll: true }); } catch (_) { el.focus(); } }; \
                                     const trap = (e) => { \
                                       if (e.key !== 'Tab') return; \
                                       const dialog = document.getElementById('image-text-sheet-dialog'); \
                                       if (!dialog) return; \
                                       const sel = 'a[href], area[href], input:not([type=\"hidden\"]), select, textarea, button, iframe, object, embed, [contenteditable=\"true\"], [tabindex]'; \
                                       const focusable = Array.prototype.slice.call(dialog.querySelectorAll(sel)).filter((el) => { \
                                         if (el.disabled || el.hidden || el.tabIndex < 0 || el.getAttribute('aria-hidden') === 'true') return false; \
                                         if (typeof el.getClientRects === 'function' && el.getClientRects().length === 0) return false; \
                                         if (window.getComputedStyle && window.getComputedStyle(el).visibility === 'hidden') return false; \
                                         return true; \
                                       }); \
                                       if (!focusable.length) { e.preventDefault(); focusEl(dialog); return; } \
                                       const idx = focusable.indexOf(document.activeElement); \
                                       if (e.shiftKey) { if (idx <= 0) { e.preventDefault(); focusEl(focusable[focusable.length - 1]); } } \
                                       else if (idx < 0 || idx === focusable.length - 1) { e.preventDefault(); focusEl(focusable[0]); } \
                                     }; \
                                     window.__mnSheetTrap = trap; \
                                     document.addEventListener('keydown', trap); \
                                     const d = document.getElementById('image-text-sheet-dialog'); \
                                     focusEl(d); \
                                     dioxus.send(d && document.activeElement === d ? 1 : 0);",
                                );
                                let focused = eval.recv::<i64>().await.unwrap_or(0);
                                diag::log("EDIT", &format!("text sheet dialog focus={focused}"));
                            });
                        },
                        div { class: "image-text-sheet-header",
                            h2 { id: "image-text-sheet-title", "{crate::i18n::t(\"sheet.full_text\")}" }
                        }
                        if sheet_editing {
                            textarea {
                                class: "image-text-sheet-editor",
                                value: "{sheet_draft}",
                                placeholder: "{crate::i18n::t(\"sheet.placeholder\")}",
                                "aria-label": "{crate::i18n::t(\"sheet.editor_aria\")}",
                                // 逐键写回（原版 onChange 口径，
                                // D-20）：每键即写回块 text 并
                                // 落盘，无「未保存」状态。
                                oninput: {
                                    let persist = persist.clone();
                                    let bid_in = bid.clone();
                                    move |e| {
                                        let v = e.value();
                                        sheet_draft.set(v.clone());
                                        save_sheet_text(doc, title, data, &persist, &bid_in, &v);
                                    }
                                },
                            }
                        } else {
                            div { class: "image-text-sheet-content",
                                if sheet_draft.read().trim().is_empty() {
                                    "{crate::i18n::t(\"sheet.empty\")}"
                                } else {
                                    "{sheet_draft}"
                                }
                            }
                        }
                        div { class: "image-text-sheet-footer",
                            button {
                                class: "image-text-sheet-action",
                                // 「完成编辑」只切回阅读态、底表
                                // 保持打开（原版口径，D-20）；焦
                                // 点随态移动：进编辑态落
                                // textarea、出编辑态回本按钮（原
                                // 版 useEffect 同口径）。
                                onclick: move |_| {
                                    if *sheet_edit.read() {
                                        sheet_edit.set(false);
                                        diag::log("EDIT", &format!("text sheet edit off len={}", sheet_draft.read().chars().count()));
                                        spawn(async move {
                                            let mut eval = document::eval(
                                                "requestAnimationFrame(() => { const b = document.querySelector('.image-text-sheet-action'); if (b) { try { b.focus({ preventScroll: true }); } catch (_) { b.focus(); } } dioxus.send(null); });",
                                            );
                                            let _ = eval.recv::<Value>().await;
                                        });
                                    } else {
                                        sheet_edit.set(true);
                                        diag::log("EDIT", "text sheet edit on");
                                        spawn(async move {
                                            let mut eval = document::eval(
                                                "requestAnimationFrame(() => { const t = document.querySelector('.image-text-sheet-editor'); if (t) { try { t.focus({ preventScroll: true }); } catch (_) { t.focus(); } } dioxus.send(null); });",
                                            );
                                            let _ = eval.recv::<Value>().await;
                                        });
                                    }
                                },
                                if sheet_editing {
                                    "{crate::i18n::t(\"sheet.done\")}"
                                } else {
                                    "{crate::i18n::t(\"sheet.edit\")}"
                                }
                            }
                        }
                    }
                }
            }
            if let Some((bid, filter, ax, atop, abottom)) = panel_state {
                SlashPanel { bid, filter, anchor_x: ax, anchor_top: atop, anchor_bottom: abottom, panel, slash_click, link_for, link_pos, link_click }
            } else if let Some(bid) = link_state {
                SlashPanel { bid, filter: String::new(), anchor_x: link_x, anchor_top: link_top, anchor_bottom: link_bottom, panel, slash_click, link_for, link_pos, link_click }
            }
        }
    }
}

type PersistFn = dyn Fn(Vec<Node>, String, Signal<BackupFile>) + 'static;

/// 持久化句柄：包一层以满足 Dioxus 组件 props 的 PartialEq 要求。
#[derive(Clone)]
struct PersistHandle(std::rc::Rc<PersistFn>);

impl PartialEq for PersistHandle {
    fn eq(&self, other: &Self) -> bool {
        std::rc::Rc::ptr_eq(&self.0, &other.0)
    }
}

impl PersistHandle {
    fn call(&self, doc: Vec<Node>, title: String, data: Signal<BackupFile>) {
        (self.0)(doc, title, data)
    }
}

#[allow(clippy::too_many_arguments)]
fn handle_bridge_msg(
    msg: &str,
    memo_id: &str,
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut panel: Signal<Option<(String, String, f64, f64, f64)>>,
    mut link_for: Signal<Option<String>>,
    mut link_pos: Signal<(f64, f64, f64)>,
    mut focus_req: Signal<Option<(String, usize)>>,
    mut dom_set: Signal<Option<(String, String, usize)>>,
    mut md_edit: Signal<Option<String>>,
    mut active_edit: Signal<Option<String>>,
    mut sel_block: Signal<Option<String>>,
    mut manifest: Signal<String>,
    mut hist: Signal<Vec<HistSnap>>,
    mut hist_idx: Signal<usize>,
    mut hist_clock: Signal<(f64, bool)>,
    mut epoch: Signal<u32>,
    mut focus_hint: Signal<Option<(String, usize)>>,
    mut ed_scroll: Signal<f64>,
    mut card_caret: Signal<Option<String>>,
    mut card_menu: Signal<Option<crate::blocks::CardMenuState>>,
    mut card_edit: Signal<Option<String>>,
    mut media_req: Signal<Option<MediaReq>>,
    persist: &PersistHandle,
) -> (bool, bool) {
    // 返回 (skip_hist, coalesce)：skip_hist=true = 本条消息已
    // 自行管理历史栈（撤销/重做），消息循环不要再按「文档变
    // 了」自动压栈；coalesce=true = 连续输入类消息，压栈走
    // 600ms 合并（原版 recordUndoPoint 口径）。
    let Ok(v) = serde_json::from_str::<Value>(msg) else {
        diag::log("EDIT", &format!("bad bridge msg: {}", &msg[..msg.len().min(80)]));
        return (false, false);
    };
    let op = v.get("op").and_then(|x| x.as_str()).unwrap_or("");
    let bid = v.get("id").and_then(|x| x.as_str()).unwrap_or("");
    let mut coalesce = false;
    // 最近编辑块（菜单撤销/重做恢复焦点的落点提示）
    if !bid.is_empty() && op != "undo" && op != "redo" {
        focus_hint.set(Some((bid.to_string(), usize::MAX)));
    }
    match op {
        "undo" | "redo" => {
            let sync = v.get("sync").map(|s| s.to_string());
            let off = v.get("off").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let focus = if bid.is_empty() {
                focus_hint.read().clone()
            } else {
                Some((bid.to_string(), off))
            };
            if op == "undo" {
                step_undo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    persist, data, &title, memo_id, sync.as_deref(), focus,
                );
            } else {
                step_redo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    persist, data, &title, memo_id, sync.as_deref(), focus,
                );
            }
            return (true, false);
        }
        "forceTop" => {
            // 失焦回顶（滚动审计 S8）：桥已 scrollTo(0,0)，这里
            // 把滚动量状态压回 0（标题坞回未滚动形态）。桥以
            // 80ms 间隔重发最多 6 次，压住 iOS 异步恢复的滚动。
            if *ed_scroll.read() != 0.0 {
                ed_scroll.set(0.0);
            }
            diag::log_once("force-top", "EDIT", "blur -> force unscrolled (S8)");
        }
        "caretMove" => {
            let dir = v.get("dir").and_then(|x| x.as_str()).unwrap_or("");
            diag::log("EDIT", &format!("caret cross-block {dir} from {bid}"));
        }
        "drag" => {
            // 桥块排序拾起/落位/取消记行：只记日志，状态机
            // 与几何由桥的长按拾起引擎决定。
            let note = v.get("note").and_then(|x| x.as_str()).unwrap_or("");
            diag::log("EDIT", &format!("drag {note}"));
        }
        "canvasFocus" => {
            // 画布空白点按落焦（桥 canvasFocusRoute）：焦点
            // 与选区已由桥内 setCaretEdge 落定，focusin 随后
            // 以 focusBlock 同步 active_edit；此处只记 Diag。
            // via=detailbg 为头部以下 .detail 背景区落焦（用
            // 户 2026-11-23 落焦区域扩展），行尾加 (detailbg)
            // 后缀与画布口径区分。
            let via = v.get("via").and_then(|x| x.as_str()).unwrap_or("");
            if via == "detailbg" {
                diag::log("EDIT", &format!("canvas focus -> {bid} (detailbg)"));
            } else {
                diag::log("EDIT", &format!("canvas focus -> {bid}"));
            }
        }
        "selectBlock" => {
            sel_block.set(Some(bid.to_string()));
        }
        "clearSelect" => {
            if sel_block.read().is_some() {
                sel_block.set(None);
            }
        }
        "cardMenu" => {
            // 卡片浮层菜单打开（桥三路：长按拾起=卡锚、右键=
            // 点锚；悬停钮走上下文直设不经桥）。定位在渲染侧
            // 按锚点与视口钳制（CardMenu 渲染段）。
            let wtype = v.get("wtype").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let anchor = v.get("anchor").and_then(|x| x.as_str()).unwrap_or("card");
            let rf = |i: usize| {
                v.get("rect")
                    .and_then(|r| r.get(i))
                    .and_then(|x| x.as_f64())
                    .unwrap_or(0.0)
            };
            let anchor_point = if anchor == "point" {
                Some((
                    v.get("x").and_then(|x| x.as_f64()).unwrap_or(0.0),
                    v.get("y").and_then(|x| x.as_f64()).unwrap_or(0.0),
                ))
            } else {
                None
            };
            card_menu.set(Some(crate::blocks::CardMenuState {
                bid: bid.to_string(),
                wtype,
                anchor_point,
                rect: (rf(0), rf(1), rf(2), rf(3)),
            }));
            diag::log("EDIT", &format!("card menu open {bid} anchor={anchor}"));
        }
        "cardMenuHide" => {
            if card_menu.read().is_some() {
                card_menu.set(None);
            }
        }
        "cardEditExit" => {
            let cur = card_edit.read().clone();
            if let Some(b) = cur {
                card_edit.set(None);
                diag::log("EDIT", &format!("card edit exit {b}"));
            }
        }
        "cardPick" => {
            // 编辑态点图片区：按 kind 登记媒体请求并唤起系统
            // 选图（set=整卡换图、galleryItem=换画廊单格、
            // galleryAdd=空画廊追加）。
            let kind = v.get("kind").and_then(|x| x.as_str()).unwrap_or("set");
            match kind {
                "galleryItem" => {
                    let ix = v.get("index").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
                    media_req.set(Some(MediaReq::GalleryPick {
                        bid: bid.to_string(),
                        index: Some(ix),
                    }));
                }
                "galleryAdd" => {
                    media_req.set(Some(MediaReq::GalleryPick {
                        bid: bid.to_string(),
                        index: None,
                    }));
                }
                _ => {
                    media_req.set(Some(MediaReq::SetImage { bid: bid.to_string() }));
                }
            }
            spawn(async move {
                let mut eval = document::eval(
                    "const i = document.getElementById('file-media'); if (i) i.click(); dioxus.send(null);",
                );
                let _ = eval.recv::<Value>().await;
            });
            diag::log("EDIT", &format!("card pick {kind} {bid}"));
        }
        "insertPara" => {
            // 原版原子块边缘点击（use-editor-dom.js）：左 28px 在
            // 块前插空段并聚焦；右 28px 聚焦下一个可编辑兄弟，
            // 没有才在块后插空段。批 1 B-13 起卡片类右 15% 区
            // 带 kind=card 单独标记：原版卡片右区的动作是恒在
            // 卡后新插一段并聚焦（「新增一行」），不走附件的
            // 聚焦既有下一段口径——否则区虽命中、落段行为仍
            // 与原版分叉（宽卡右区点完只跳焦点不新增行）。
            let where_ = v.get("where").and_then(|x| x.as_str()).unwrap_or("before");
            let card_zone = v.get("kind").and_then(|x| x.as_str()) == Some("card");
            let mut d = doc.read().clone();
            if let Some(Loc::Top(i)) = find_loc(&d, bid) {
                sel_block.set(None);
                if where_ == "after" && card_zone {
                    let para = new_block("paragraph");
                    let pid = para.id.clone().unwrap_or_default();
                    d.insert(i + 1, para);
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                    focus_req.set(Some((pid, 0)));
                    diag::log("EDIT", &format!("insert para after card {bid}"));
                } else if where_ == "after" {
                    let next_ed = ((i + 1)..d.len()).find(|&j| {
                        matches!(
                            d[j].block_type().unwrap_or(""),
                            "paragraph" | "heading" | "quote" | "todo"
                        )
                    });
                    if let Some(j) = next_ed {
                        let nid = d[j].id.clone().unwrap_or_default();
                        focus_req.set(Some((nid, 0)));
                    } else {
                        let para = new_block("paragraph");
                        let pid = para.id.clone().unwrap_or_default();
                        d.insert(i + 1, para);
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        focus_req.set(Some((pid, 0)));
                        diag::log("EDIT", &format!("insert para after {bid}"));
                    }
                } else {
                    let para = new_block("paragraph");
                    let pid = para.id.clone().unwrap_or_default();
                    d.insert(i, para);
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                    focus_req.set(Some((pid, 0)));
                    diag::log("EDIT", &format!("insert para before {bid}"));
                }
            }
        }
        "split" => {
            let before = v.get("before").and_then(|x| x.as_str()).unwrap_or("");
            let after = v.get("after").and_then(|x| x.as_str()).unwrap_or("");
            op_split(&mut doc, bid, before, after, &mut focus_req, &mut dom_set);
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "merge" => {
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            op_merge(&mut doc, bid, html, &mut focus_req, &mut dom_set, &mut sel_block);
            // 被合并掉的块若正处 md 源码编辑态，编辑态一并清掉
            if md_edit.read().as_deref() == Some(bid) {
                md_edit.set(None);
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "replaceRange" => {
            let a_bid = v.get("aBid").and_then(|x| x.as_str()).unwrap_or("");
            let a_off = v.get("aOff").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let f_bid = v.get("fBid").and_then(|x| x.as_str()).unwrap_or("");
            let f_off = v.get("fOff").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            let enter = v.get("enter").and_then(|x| x.as_bool()).unwrap_or(false);
            let from_start = v.get("fromStart").and_then(|x| x.as_bool()).unwrap_or(false);
            let to_end = v.get("toEnd").and_then(|x| x.as_bool()).unwrap_or(false);
            let sync = v.get("sync").map(|s| s.to_string());
            op_replace_range(
                &mut doc,
                a_bid,
                a_off,
                f_bid,
                f_off,
                text,
                enter,
                from_start,
                to_end,
                sync.as_deref(),
                &mut focus_req,
                &mut dom_set,
            );
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "moveBlock" => {
            let ids: Vec<String> = v
                .get("ids")
                .and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|x| x.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            let to = v.get("to").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let sync = v.get("sync").map(|s| s.to_string());
            op_move_block(
                &mut doc,
                data,
                memo_id,
                &title,
                &ids,
                to,
                sync.as_deref(),
                persist,
            );
        }
        "slash" => {
            let filter = v.get("filter").and_then(|x| x.as_str()).unwrap_or("");
            let x = v.get("x").and_then(|x| x.as_f64()).unwrap_or(20.0);
            let top = v.get("y").and_then(|x| x.as_f64()).unwrap_or(160.0);
            let bottom = v.get("b").and_then(|x| x.as_f64()).unwrap_or(200.0);
            panel.set(Some((bid.to_string(), filter.to_string(), x, top, bottom)));
        }
        "slashPos" => {
            // 跟随重锚（桥 slashPos，rAF 节流 + 选区守卫后发）：
            // 只更新坐标——面板为该 bid 开着则更新 panel 锚，
            // 链接表单为该 bid 则更新 link_pos；已关/换块
            // no-op。坐标真变化才记 Diag。
            let x = v.get("x").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let top = v.get("y").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let bottom = v.get("b").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let moved = |ox: f64, ot: f64, ob: f64| {
                (x - ox).abs() > 0.5 || (top - ot).abs() > 0.5 || (bottom - ob).abs() > 0.5
            };
            let cur = panel.read().clone();
            if let Some((pbid, pfilter, ox, ot, ob)) = cur {
                if pbid == bid && moved(ox, ot, ob) {
                    panel.set(Some((pbid, pfilter, x, top, bottom)));
                    diag::log("EDIT", &format!("slash reposition {bid}"));
                }
            } else if link_for.read().as_deref() == Some(bid) {
                let (ox, ot, ob) = *link_pos.read();
                if moved(ox, ot, ob) {
                    link_pos.set((x, top, bottom));
                    diag::log("EDIT", &format!("slash reposition link {bid}"));
                }
            }
        }
        "slashLink" => {
            // 链接命令：面板切换为链接表单（斜杠字符留在块里，
            // 插入时由 __mnApplyLink 前的 __mnStripSlash 清掉）
            if let Some((_, _, x, top, bottom)) = panel.read().clone() {
                link_pos.set((x, top, bottom));
            }
            panel.set(None);
            link_for.set(Some(bid.to_string()));
        }
        "slashClose" => panel.set(None),
        "slashApply" => {
            let act = v.get("act").and_then(|x| x.as_str()).unwrap_or("");
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            // D-11：桥随消息带回的令牌起点（转换落点用）
            let pos = v.get("pos").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            panel.set(None);
            if act == "image" || act == "gallery" {
                // 占位块路径（S4）：桥已 strip 掉令牌，但整块将被
                // 占位块替换，html 不再使用
                op_insert_media_placeholder(&mut doc, bid, act == "gallery", &mut focus_req);
            } else if let Some((src, off)) =
                op_convert(&mut doc, bid, act, html, pos, &mut focus_req, &mut md_edit)
            {
                let esc = src
                    .replace('&', "&amp;")
                    .replace('<', "&lt;")
                    .replace('>', "&gt;")
                    .replace('\n', "<br>");
                dom_set.set(Some((bid.to_string(), esc, off)));
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "mdText" => {
            // md 源编辑：整块文本就是源码，单文本节点落模型。
            // 逐键消息 = 连续输入，压栈走 600ms 合并。
            coalesce = true;
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            let text = text.trim_end_matches('\n').to_string();
            let mut d = doc.read().clone();
            if let Some(loc) = find_loc(&d, bid) {
                let n = node_at_mut(&mut d, loc);
                n.children = Some(vec![text_node(&text)]);
                doc.set(d);
            }
        }
        "mdDone" => {
            if md_edit.read().as_deref() == Some(bid) {
                md_edit.set(None);
                persist.call(doc.read().clone(), title.read().clone(), data);
                diag::log("EDIT", &format!("md source done {bid}"));
            }
        }
        "focusBlock" => {
            if active_edit.read().as_deref() != Some(bid) {
                active_edit.set(Some(bid.to_string()));
            }
        }
        "blurBlock" => {
            if active_edit.read().as_deref() == Some(bid) {
                active_edit.set(None);
            }
        }
        "pasteSync" => {
            // 富文本粘贴已由 JS 插入 DOM，这里只对齐模型。
            // 来源含打字路径（实时高亮/软换行/粘贴落位），按
            // 连续输入走 600ms 合并压栈。
            coalesce = true;
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            let mut d = doc.read().clone();
            if let Some(loc) = find_loc(&d, bid) {
                node_at_mut(&mut d, loc).children = Some(editor_html_to_inlines(html));
                doc.set(d);
                diag::log("EDIT", &format!("paste html synced {bid}"));
                if html.contains("<mark") {
                    diag::log("EDIT", &format!("highlight mark synced {bid}"));
                }
            } else {
                diag::log("EDIT", &format!("pasteSync: block not found {bid}"));
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "pasteText" => {
            let before = v.get("before").and_then(|x| x.as_str()).unwrap_or("");
            let after = v.get("after").and_then(|x| x.as_str()).unwrap_or("");
            let lines: Vec<String> = v
                .get("lines")
                .and_then(|x| x.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|x| x.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            op_paste_text(&mut doc, bid, before, after, &lines, &mut focus_req, &mut dom_set);
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "pasteCard" => {
            let url = v.get("url").and_then(|x| x.as_str()).unwrap_or("");
            let remain = v.get("remain").and_then(|x| x.as_str()).unwrap_or("");
            let before = v.get("before").and_then(|x| x.as_str()).unwrap_or("");
            let after = v.get("after").and_then(|x| x.as_str()).unwrap_or("");
            if let Some(card_id) =
                op_paste_card(&mut doc, bid, url, remain, before, after, &mut focus_req)
            {
                persist.call(doc.read().clone(), title.read().clone(), data);
                spawn_resolve_card(doc, card_id, url.to_string(), title, data, persist.clone(), None, None);
                diag::log("EDIT", &format!("pasteCard {url} remain={}", remain.len()));
            }
        }
        "musicInput" => {
            // 音乐输入胶囊的粘贴/输入/回车复检：提出 URL 才
            // 转 loading 并解析（op_music_input 内含状态守卫
            // 与全套 Diag）；无 URL 时无动作、不落盘。via 标
            // 记来源（批 1 B-9：direct=胶囊本尊粘贴/输入、
            // paste-divert=engaged 时错位粘贴在 paste 阶段
            // 分流、paste-recover=原生落地后 input 阶段 diff
            // 回收），供 Diag 区分三路。
            let via = v.get("via").and_then(|x| x.as_str()).unwrap_or("");
            if !via.is_empty() {
                diag::log("EDIT", &format!("musicInput via {via} bid={bid}"));
            }
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            op_music_input(
                &mut doc,
                bid,
                text,
                &mut card_caret,
                &mut focus_req,
                title,
                data,
                persist,
            );
        }
        "musicFocusPrev" => {
            // 音乐胶囊段首退格收口（K4）：不删块，仅把焦点移
            // 回上一个可编辑单元末尾；无上一单元则无操作。胶
            // 囊保留，删除走卡片菜单明路。
            let d = doc.read().clone();
            if let Some(Loc::Top(i)) = find_loc(&d, bid) {
                let units = editable_units(&d);
                let prev = units.iter().rev().find(|u| match u {
                    Loc::Top(t) => *t < i,
                    Loc::Item(li, _) => *li < i,
                });
                if let Some(pu) = prev {
                    let n = node_at(&d, *pu);
                    let pid = n.id.clone().unwrap_or_default();
                    if !pid.is_empty() {
                        focus_req.set(Some((pid.clone(), plain_len(n))));
                        diag::log(
                            "EDIT",
                            &format!("music input backspace -> focus prev {pid}"),
                        );
                    }
                }
            }
        }
        "pasteImage" => {
            let name = v
                .get("name")
                .and_then(|x| x.as_str())
                .unwrap_or("image.png")
                .to_string();
            let mime = v
                .get("mime")
                .and_then(|x| x.as_str())
                .unwrap_or("image/png")
                .to_string();
            let b64 = v.get("b64").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let bid_owned = bid.to_string();
            let persist2 = persist.clone();
            spawn(async move {
                let bytes = b64_decode(&b64);
                if bytes.is_empty() {
                    diag::log("EDIT", "pasteImage: empty bytes");
                    return;
                }
                let fid = gen_id();
                if idb::put_attachment(&fid, &bytes).await.is_err() {
                    diag::log("EDIT", "pasteImage: idb put failed");
                    return;
                }
                let mut man: Value = serde_json::from_str(&manifest.read())
                    .unwrap_or_else(|_| json!({"version": 1}));
                if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
                    man["attachments"] = json!({});
                }
                man["attachments"][&fid] = json!({"name": name, "type": mime});
                let man_str = man.to_string();
                manifest.set(man_str.clone());
                let _ = idb::save_manifest(&man_str).await;
                let mut d = doc.read().clone();
                if let Some(loc) = find_loc(&d, &bid_owned) {
                    let top = match loc {
                        Loc::Top(i) => i,
                        Loc::Item(li, _) => li,
                    };
                    let mut extra = Map::new();
                    extra.insert("attrs".to_string(), json!({"fileId": fid}));
                    let node = Node {
                        text: None,
                        node_type: Some("image".to_string()),
                        id: Some(gen_id()),
                        children: Some(vec![]),
                        extra,
                    };
                    d.insert(top + 1, node);
                    doc.set(d.clone());
                    persist2.call(d, title.read().clone(), data);
                    diag::log("EDIT", &format!("pasteImage {fid} {}B", bytes.len()));
                }
            });
        }
        "inputSync" => {
            // 批 4 B-4：打字 80ms 防抖增量同步（桥
            // scheduleInputSync 只带真打过字的块）——落真
            // doc 信号，消息循环按 coalesce=true 压栈
            // （600ms 爆发合并）；无变化则整条 no-op（不
            // set、不落盘），避免无谓重渲染与写盘。20s
            // sync 自此退兜底（其影子比对恒无变化）。编
            // 辑态块为非受控渲染（EditableDiv 初始 HTML
            // use_hook 锁定），doc.set 不回写活 DOM。
            coalesce = true;
            if let Some(map) = v.get("map") {
                let n_blocks = map.as_object().map(|o| o.len()).unwrap_or(0);
                let map_str = map.to_string();
                let before_json = serde_json::to_string(&*doc.read()).unwrap_or_default();
                let mut d = doc.read().clone();
                apply_sync_map(&mut d, &map_str);
                if serde_json::to_string(&d).unwrap_or_default() != before_json {
                    doc.set(d);
                    persist.call(doc.read().clone(), title.read().clone(), data);
                    // Diag 节流行（批 4 笔 2）：真实落模型
                    // 才计数，5s 窗口至多一行。
                    INPUT_SYNC_DIAG.with(|c| {
                        let (last, total) = c.get();
                        let total = total + 1;
                        let now = perf_now_ms();
                        if now - last >= 5000.0 {
                            diag::log(
                                "EDIT",
                                &format!("input sync applied ({n_blocks} blocks, total {total})"),
                            );
                            c.set((now, total));
                        } else {
                            c.set((last, total));
                        }
                    });
                }
            }
        }
        "sync" => {
            // 兜底自动同步（批 4 后口径）：只更新持久副本，
            // 不动正在编辑的 doc 信号；打字主通道是 inputSync
            if let Some(map) = v.get("map") {
                let map_str = map.to_string();
                let mut shadow = doc.read().clone();
                let before_json = serde_json::to_string(&shadow).unwrap_or_default();
                apply_sync_map(&mut shadow, &map_str);
                if serde_json::to_string(&shadow).unwrap_or_default() != before_json {
                    persist.call(shadow, title.read().clone(), data);
                    diag::log_once("autosync", "EDIT", "autosync applied");
                }
            }
        }
        _ => diag::log("EDIT", &format!("unknown op: {op}")),
    }
    // 智能前缀扫描（原版在输入防抖尾部跑：文本落模型后扫
    // 全 doc 转首个命中段落）。挂在文本类消息（打字同步/
    // md 源输入/拆分/合并/粘贴文本）落定之后、同一消息内
    // 完成——与原版同属一个撤销步（消息循环按本消息前后
    // JSON 压栈）。斜杠面板/链接表单打开时跳过（原版
    // showSlash 守卫）。转换块若正处 md 源码编辑态则编辑
    // 态失效；转换改了块文本，非受控 DOM 不会自己重渲染，
    // 按 slashApply 同口径用 dom_set 把新内容回写活 DOM 并
    // 落光标（__mnSetHtml）；焦点以转换落点为准（原版转换
    // 后 focusEditableWithCaret 覆盖此前落点）。
    if matches!(
        op,
        "pasteSync" | "mdText" | "split" | "merge" | "pasteText" | "inputSync"
    )
        && panel.read().is_none()
        && link_for.read().is_none()
    {
        if let Some((cid, fid, coff, dom_html)) = apply_smart_prefix(&mut doc) {
            if md_edit.read().as_deref() == Some(cid.as_str()) {
                md_edit.set(None);
            }
            if let Some(html) = dom_html {
                dom_set.set(Some((cid, html, coff)));
            }
            focus_req.set(Some((fid, coff)));
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
    }
    (false, coalesce)
}

/// 待发输入保险丝的 localStorage 键（与桥侧
/// stashPendingInput 同名同格式：{bid: innerHTML}）。
const PENDING_INPUT_KEY: &str = "mynote_pending_input_v1";

/// 待发输入尾巴恢复（批 4 链尾产品红根治）：打字后
/// <80ms 内整页卸载 / 桥拆除 / 切后台时，80ms 防抖
/// inputSync 未及发火、消息通道与异步落盘又赶不上卸
/// 载，桥侧把脏块当前 innerHTML 同步存入 localStorage
/// 保险丝。本函数把属于 doc 的条目经 apply_sync_map
/// 落回模型并摘除已消费条目，未命中的（他篇尾巴）原
/// 样写回等其本篇恢复；返回实际应用的条数。调用点：
/// 启动逐篇（main.rs，赶在列表/深链打开前回写落盘）
/// 与打开备忘的 doc 初始化（应用内卸载场景兜底）。
pub(crate) fn recover_pending_input(doc: &mut Vec<Node>) -> usize {
    let Some(st) = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
    else {
        return 0;
    };
    let Some(raw) = st.get_item(PENDING_INPUT_KEY).ok().flatten() else {
        return 0;
    };
    let Ok(map) = serde_json::from_str::<Map<String, Value>>(&raw) else {
        // 格式损坏：整键作废，避免每次打开重复踩坏数据
        let _ = st.remove_item(PENDING_INPUT_KEY);
        return 0;
    };
    if map.is_empty() {
        return 0;
    }
    // 本篇块 id 全集（与 apply_sync_map 同遍历面：顶层
    // 块 + 列表子项递归）
    fn collect_ids(nodes: &[Node], out: &mut std::collections::HashSet<String>) {
        for n in nodes {
            if let Some(id) = &n.id {
                out.insert(id.clone());
            }
            if let Some(kids) = &n.children {
                collect_ids(kids, out);
            }
        }
    }
    let mut ids = std::collections::HashSet::new();
    collect_ids(doc, &mut ids);
    let (mine, rest): (Map<String, Value>, Map<String, Value>) =
        map.into_iter().partition(|(k, _)| ids.contains(k));
    if mine.is_empty() {
        return 0;
    }
    let n = mine.len();
    apply_sync_map(doc, &Value::Object(mine).to_string());
    if rest.is_empty() {
        let _ = st.remove_item(PENDING_INPUT_KEY);
    } else {
        let _ = st.set_item(PENDING_INPUT_KEY, &Value::Object(rest).to_string());
    }
    n
}

/// 图文面板文本写回：块 extra["text"] 写回并落库。批 5
/// D-20 后为逐键调用（textarea oninput 每键一次，与原版
/// onChange 逐键回写 + triggerAutoSave 同口径）——关表路
/// 径不再有集中保存点，本函不逐键记 Diag（防刷环），
/// 落盘结果由「完成编辑」时的 len 打点与探针读库核对。
fn save_sheet_text(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: &PersistHandle,
    bid: &str,
    txt: &str,
) {
    let mut d = doc.read().clone();
    if let Some(loc) = find_loc(&d, bid) {
        node_at_mut(&mut d, loc)
            .extra
            .insert("text".to_string(), json!(txt));
        doc.set(d.clone());
        persist.call(d, title.read().clone(), data);
    }
}

/// 背景色 8 色（原版 BgSheet：冷雾/暖沙/浅绿/浅蓝/浅粉/米橙/淡紫/浅杏）。
const BG_COLORS: [&str; 8] = [
    "#eaeef2", "#e8e0d4", "#d4e8d0", "#d0e0e8", "#e8d0d4", "#fff3e0", "#e8e0f0",
    "#f0e8d0",
];

/// BgSheet 色点无障碍名（审计 E-12）：按下标取 bg.color_N，
/// 与 BG_COLORS 同序（原版 BgSheet.js colorNames 口径）。
/// 键字面列全（verify 僵尸键检查按字面引用判定）。
fn bg_color_name(idx: usize) -> String {
    crate::i18n::t(match idx {
        0 => "bg.color_0",
        1 => "bg.color_1",
        2 => "bg.color_2",
        3 => "bg.color_3",
        4 => "bg.color_4",
        5 => "bg.color_5",
        6 => "bg.color_6",
        _ => "bg.color_7",
    })
}

/// 添加附件：读 #file-attach 选中的文件 → 写 IDB 附件库 →
/// 更新 manifest → 文档末尾插入图片/附件块并落库。
async fn attach_file(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    persist: &PersistHandle,
) {
    let Some(window) = web_sys::window() else {
        return;
    };
    let Some(document) = window.document() else {
        return;
    };
    let Some(input) = document
        .get_element_by_id("file-attach")
        .and_then(|e| e.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        return;
    };
    let Some(files) = input.files() else {
        return;
    };
    for fi in 0..files.length() {
        let Some(file) = files.get(fi) else {
            continue;
        };
        attach_one(&file, doc, title, data, manifest, persist).await;
    }
}

/// 单个附件文件：写 IDB → 更新 manifest → 末尾插块并落库。
async fn attach_one(
    file: &web_sys::File,
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    persist: &PersistHandle,
) {
    let name = file.name();
    let mime = file.type_();
    // 失败经错误徽章提示（原版 addWarn 口径，审计 E-3）：
    // 读/写任一失败都不插块（原版为插入后回滚移除，用户
    // 可见终态一致——无块 + 一条 warn）。
    let Ok(buf) = JsFuture::from(file.array_buffer()).await else {
        crate::errbadge::add_warn(&crate::i18n::t("attach.save_failed"), None);
        diag::log("EDIT", &format!("attach read err: {name}"));
        return;
    };
    let bytes = js_sys::Uint8Array::new(&buf).to_vec();
    let fid = gen_id();
    if let Err(e) = idb::put_attachment(&fid, &bytes).await {
        crate::errbadge::add_warn(
            &crate::i18n::t("attach.save_failed"),
            Some(&format!("{e:?}")),
        );
        diag::log("EDIT", &format!("attach put err: {e:?}"));
        return;
    }
    // manifest.attachments[fid] = {name, type}
    let mut man: Value =
        serde_json::from_str(&manifest.read()).unwrap_or_else(|_| json!({"version": 1}));
    if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
        man["attachments"] = json!({});
    }
    man["attachments"][&fid] = json!({"name": name, "type": mime});
    let man_str = man.to_string();
    manifest.set(man_str.clone());
    let _ = idb::save_manifest(&man_str).await;

    let is_image = mime.starts_with("image/");
    let mut extra = Map::new();
    let node = if is_image {
        extra.insert("attrs".to_string(), json!({"fileId": fid}));
        Node {
            text: None,
            node_type: Some("image".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            extra,
        }
    } else {
        // fileId 只写 attrs（与图片工厂同位）；顶层 fileId 是
        // 旧写出形态，读取端保留双读至存量归一（去兼容笔4）。
        extra.insert("attrs".to_string(), json!({ "fileId": fid }));
        // 文件名冗余写节点顶层（导出渲染的兜底读法同字段；
        // 编辑器渲染优先查 manifest，原版校验器不拒未知字段）
        extra.insert("name".to_string(), Value::String(name.clone()));
        extra.insert("status".to_string(), Value::String("done".to_string()));
        extra.insert("image".to_string(), Value::Bool(false));
        Node {
            text: None,
            node_type: Some("attachment".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            extra,
        }
    };
    let mut d = doc.read().clone();
    d.push(node);
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
    // 成功无提示（原版口径，E-3 备注）
    diag::log("EDIT", &format!("attach {fid} {name} {mime} {}B", bytes.len()));
}

