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
//! 子模块分工：bridge（JS 桥与卸载清理，桥 JS 本体在
//! bridge/js/editor.js）、cards（链接/音乐卡解析与音乐输入
//! 胶囊）、columns（双栏分界）、dispatch（桥消息分发与持
//! 久化落盘）、export（导出全链）、hooks（按域自定义
//! hooks：信号组/effect/接线，见 hooks/mod.rs）、layers
//! （页头坞/卡片菜单/编辑菜单层/背景底表/图文底表五个
//! rsx 子组件）、model（节点模型基础：构造/定位/谓词/
//! 字段读写，含布局 JSON 辅助与 wiki 反链缓存，三轮续
//! 入时间/id 基础）、ops（块操作：历史/劈分/合并/替换/
//! 粘贴/转换，含待恢复输入与附件落地）、render（斜杠
//! 表、块组件与斜杠面板）、sheets（菜单/背景层/文字层
//! 关闭动画与底表写回，三轮续入暗色推导）、title（标
//! 题显示口径与静态壳）、title_controller（标题编辑会
//! 话的唯一所有者）；本文件留编辑器主体（Editor 组件
//! 的状态编排与主干渲染、生命周期接线）。

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
mod dispatch;
mod export;
mod hooks;
use hooks::{
    Columns, Contexts, ExportSignals, MenuSignals, PanelFx, PersistFx, SheetSignals, TitleSession,
};
mod layers;
mod model;
mod ops;
mod render;
mod sheets;
mod title;
mod title_controller;

use bridge::{sync_editor_cleanup, EDITOR_JS};
use dispatch::{build_backup, handle_bridge_msg, perf_now_ms, save_backup, PersistHandle};
use layers::{BgSheetLayer, CardMenuLayer, MenuLayer, TextSheetLayer, TitleDock};
use sheets::{
    animate_bg_close, animate_menu_close, animate_text_sheet_close, bg_color_name,
    cancel_menu_close, darken_hex, is_dark_mode, save_sheet_text, BgAfter, MenuAfter, BG_COLORS,
};
use model::{
    apply_memo_layout, backlinks_cached, clear_type_fields, editable_units, empty_text_node,
    ensure_ids, find_loc, flow_runs, inlines_len, is_atomic_class,
    is_empty_para, is_text_block, layout_json, list_start, materialize_trails, new_block,
    gen_id, next_is_empty_para, node_at, node_at_mut, normalize_inline_forms, now_iso,
    orig_char_count,
    placeholder_shows, plain_len, remove_start_field, restore_focus, set_attr, set_list_start,
    shift_list_start, split_inlines_at, text_node, BacklinkCache, FlowRun, Loc,
};
pub(crate) use model::warm_open_pure_paths;
use ops::{
    apply_smart_prefix, apply_sync_map, attach_file, b64_decode, handle_media_files, hist_push,
    op_convert, op_insert_media_placeholder, op_merge, op_move_block, op_paste_card,
    op_paste_text, op_replace_range, op_split, step_redo, step_undo, HistSnap,
};
pub(crate) use ops::recover_pending_input;
use render::{slash_record_recent, EditorBlock, MergedListPreview, SlashPanel};
use export::{
    animate_export_close, begin_export_open, collect_export_assets, collect_export_files,
    doc_to_html, download_text, export_char_count, export_filename, memo_to_markdown,
    settle_export_on_resume, time_label, EXPORT_ANIM_CLOSING, EXPORT_ANIM_IDLE,
};
use cards::{op_music_input, spawn_resolve_card};
use columns::{canonical_boundary, column_boundary, normalize_boundary};
use title::{blur_title_if_focused, TitleCapsule};

/// 媒体文件请求：斜杠「图片/画廊」替换当前块，或给图文块换图。
#[derive(Clone, PartialEq)]
pub(crate) enum MediaReq {
    Replace { bid: String, gallery: bool },
    SetImage { bid: String },
    /// 卡片编辑态点画廊格换单图（index=Some，保图库的表示
    /// 形态）/ 点空态占位格追加所选（index=None）。
    GalleryPick { bid: String, index: Option<usize> },
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
    // 备忘交接（更严口径，用户 2026-11-25 定）：备忘自打开
    // 起全程由本实例自有——挂载首查一次性把备忘与本篇头
    // 像从总数据交接进实例（use_hook 定格），渲染/编辑路径
    // 不再回查总表：doc/title/bg/layout/updated_at/头像全
    // 部由实例信号持有（layout 与 updated_at 的会话内写点
    // 逐点镜像，见各写点注），外部变更（列表侧删除/导入替
    // 换等）不扰动打开中的实例；写回仍经 build_backup 的
    // 归属守卫（state_owner）落总数据。此前口径是「渲染期
    // 现查优先、挂载快照回退」，回退的现实触发（空备忘关
    // 闭即删除后留槽播出场、查无即回空模板会把离页首帧换
    // 成占位）由实例自有天然覆盖：删除后本实例改由离页条
    // 目持有渲染（main.rs LeavingEditor），自有备忘恒在。
    // hook 恒居组件首行；首次渲染备忘恒在（打开入口自列
    // 表/新建），交接为 None 仅余防御语义、与旧行为一致。
    let (memo_held, avatar_held) = use_hook(|| {
        let d = data.read();
        let memo = d
            .memos
            .iter()
            .find(|m| m.id.to_string() == memo_id)
            .cloned();
        let avatar = d
            .avatars
            .as_ref()
            .and_then(|a| a.get(&memo_id))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        (memo, avatar)
    });
    let Some(memo) = memo_held else {
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
    let title = use_signal(|| memo.title.clone().unwrap_or_default());
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
    let typed = hooks::use_typed(doc, title, initial_doc_json.clone(), initial_title.clone());

    let PanelFx { panel, focus_req, card_caret, slash_click, link_for, link_click, link_pos, media_req } = hooks::use_panel_fx(doc, is_new);

    let ExportSignals { mut show_export, export_closing, export_gen, export_anim, mut export_to_menu, ed_scroll } = hooks::use_export_signals();

    // 标题编辑会话开关（原版 editingTitle）：由 TitleController
    // 经 on_session 回报（聚焦 true / 失焦 false），仅供 S7 滚
    // 动翻转抑制消费。标题的文本与几何自全面重构起全归
    // TitleController 所有（title_controller.rs）：文本只在
    // compositionend/blur/Enter/Esc 时机经 on_commit 写回本
    // 信号，编辑器渲染路径不再持有任何标题布局状态（旧的
    // 布局锁存信号、组字信号与桥快照投影一并删除——多写者
    // 并发正是组字期几何翻转与光标双画的使能条件）。
    let title_editing = use_signal(|| false);
    // 深浅模式切换计数（原版监听 matchMedia change 后重算背景）
    let scheme_tick = use_signal(|| 0u32);
    // 页面进/出场（原版 editor.js 的 closing/animDone）：进场
    // slideIn 播完 320ms 摘除（page_anim_done）；出场由
    // closing prop 派生（App 栈式交接在原地翻 prop 播
    // slideOut 并计时卸载），不再有内部 page_closing 信号。
    let page_anim_done = use_signal(|| false);
    let SheetSignals { text_sheet, sheet_edit, sheet_draft, text_sheet_closing, text_sheet_gen } = hooks::use_sheet_signals();

    let bg_init = memo.bg_color.clone();
    let layout_init = memo.layout.clone();
    // 实例自有 layout / updated_at（更严口径）：初值取交接
    // 备忘；会话内每个写总数据 layout 的写点（撤销/重做恢
    // 复、双栏开关、跨栏移动、首次落锚、关闭保存）与每个
    // build_backup 写回点（persist 句柄、关闭保存）都同笔
    // 镜像本信号，渲染与编辑路径只读本信号、不回查总表。
    let mut layout_sig = use_signal(|| layout_init.clone());
    let mut updated_sig = use_signal(|| memo.updated_at.clone());
    let Columns { avatar_url, dom_set, bg, twopane, wide } = hooks::use_columns(data, memo_id.clone(), doc, bg_init, layout_init, avatar_held, layout_sig);

    let MenuSignals { mut menu_open, bg_open, mut menu_closing, mut menu_gen, bg_closing, bg_gen } = hooks::use_menu_signals();

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
    let hist = use_signal(|| {
        vec![HistSnap {
            doc: serde_json::to_string(&doc.read().clone()).unwrap_or_default(),
            layout: layout_json(&layout_sig.read().clone()),
        }]
    });
    let hist_idx = use_signal(|| 0usize);
    // 撤销合并时钟（原版 use-history recordUndoPoint 口径）：
    // (最近一次连续输入压栈时刻 ms, 合并链是否活着)。600ms
    // 内连续输入替换栈顶；结构操作/撤销/重做断链。
    let hist_clock = use_signal(|| (0f64, false));
    let epoch = use_signal(|| 0u32);
    // 最近编辑块（桥消息维护）：菜单撤销/重做时恢复焦点的落点
    let focus_hint = use_signal(|| Option::<(String, usize)>::None);
    let Contexts { md_edit, active_edit, card_retry, wiki_nav, sel_block, card_edit, card_menu } = hooks::use_contexts(text_sheet, manifest);

    // 反向链接 targets 会话缓存（PERF 第八批 T2，见
    // backlinks_cached）：Rc+RefCell 非响应式持有，不订阅
    // 不触发重渲；随 Editor 实例生灭，跨篇导航重建一次。
    let bl_cache = use_hook(|| -> BacklinkCache {
        std::rc::Rc::new(std::cell::RefCell::new(std::collections::HashMap::new()))
    });

    let PersistFx { persist } = hooks::use_persist(memo_id.clone(), state_owner.clone(), tail_recovered.clone(), doc, title, data, updated_sig);

    let TitleSession { title_commit, title_session } = hooks::use_title_session(persist.clone(), doc, title, data, ed_scroll, title_editing);

    hooks::use_bridge_loop(memo_id.clone(), doc, title, data, panel, link_for, link_pos, focus_req, dom_set, md_edit, active_edit, sel_block, manifest, hist, hist_idx, hist_clock, epoch, focus_hint, ed_scroll, card_caret, card_menu, card_edit, media_req, persist.clone(), layout_sig);

    hooks::use_trail_materialize(doc, active_edit, md_edit);

    hooks::use_focus_requests(focus_req, dom_set);

    hooks::use_slash_click(doc, title, data, slash_click, focus_req, md_edit, dom_set, persist.clone());
    hooks::use_link_submit(doc, title, data, link_click, link_for, persist.clone());

    hooks::use_scroll_watch(panel, title_editing, ed_scroll, show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, menu_closing, menu_gen, bg_open);

    hooks::use_esc_close(text_sheet, text_sheet_closing, text_sheet_gen, card_menu, card_edit, show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, menu_closing, menu_gen, bg_open, bg_closing, bg_gen, data, bg, link_for, panel, memo_id.clone());

    hooks::use_resume_watch(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu);

    hooks::use_typed_mark(typed);

    hooks::use_scheme_watch(scheme_tick, bg);

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

    hooks::use_card_hydrate(doc, title, data, persist.clone());
    hooks::use_card_retry(doc, title, data, card_retry, persist.clone());

    hooks::use_wiki_nav(wiki_nav, doc, title, data, persist.clone(), on_open_wiki.clone(), memo_id.clone());

    hooks::use_page_enter(closing, page_anim_done);

    hooks::use_sheet_mirror(text_sheet, sheet_draft, sheet_edit);

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
                // 保存路径 captureCurrentColumnLayout 口径）；
                // 当前 layout 读实例信号（与总数据同值）。
                let boundary = if *twopane.read() {
                    let cur = layout_sig.read().clone();
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
                    // 实例 updated_at 镜像（与 persist 句柄同
                    // 口径）：出场渲染的时间标签读实例态。
                    if let Some(m) = backup
                        .memos
                        .iter()
                        .find(|m| m.id.to_string() == memo_id)
                    {
                        updated_sig.set(m.updated_at.clone());
                    }
                    if let Some(b) = boundary {
                        if let Some(m) = backup
                            .memos
                            .iter_mut()
                            .find(|m| m.id.to_string() == memo_id)
                        {
                            let ids: Vec<String> = d
                                .iter()
                                .map(|n| {
                                    n.id.as_ref()
                                        .map(|i| i.to_string())
                                        .unwrap_or_default()
                                })
                                .collect();
                            let (left, right) = ids.split_at(b.min(ids.len()));
                            let new_layout = mynote_core::MemoLayout {
                                version: Some(1),
                                mode: Some("independent".to_string()),
                                left: Some(left.to_vec()),
                                right: Some(right.to_vec()),
                            };
                            m.layout = Some(new_layout.clone());
                            layout_sig.set(Some(new_layout));
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


    let doc_snapshot = doc.read().clone();
    let panel_state = panel.read().clone();

    let bg_state = bg.read().clone();
    let words = orig_char_count(&doc_snapshot);
    let sub_line = format!(
        "{} · {}",
        time_label(updated_sig.read().to_millis().unwrap_or(0)),
        crate::i18n::tf("editor.words", &[("n", &words.to_string())])
    );
    let ed_status_text = ed_status.msg.read().clone();
    let ed_status_seq = *ed_status.seq.read();
    let ed_status_kind = *ed_status.kind.read();
    let persist_attach = persist.clone();
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
        crate::list::time_ago(&updated_sig.read().clone()),
        crate::i18n::tf("editor.words", &[("n", &words.to_string())])
    );
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
        // 分栏锚读实例 layout 信号（更严口径），不回查总表。
        let layout = layout_sig.read().clone();
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
                                        layout: layout_json(&layout_sig.read().clone()),
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
            // 页头坞必须是 fab 的兄弟节点（拆分前结构）：坞为
            // position:fixed 且以视口定位，一旦嵌进 fab button，
            // button 的 backdrop-filter 会成为 fixed 的包含块，
            // 坞被压进 46px 按钮盒并推出视口（批 14 二轮拆分
            // 时闭合括号错位一格所致，box 全量 7 套同签名红）。
            TitleDock { memo_id: memo_id.clone(), initial_title: initial_title.clone(), meta_line, scrolled, avatar_state, avatar_url, data, title_commit, title_session }
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
            CardMenuLayer { card_menu, card_edit, sel_block, doc, title, data, persist: persist.clone() }
            MenuLayer { memo_id: memo_id.clone(), memo_updated: updated_sig.read().clone(), doc, title, data, manifest, persist: persist.clone(), menu_open, menu_closing, menu_gen, show_export, export_closing, export_gen, export_anim, export_to_menu, bg_open, twopane, hist, hist_idx, hist_clock, epoch, avatar_url, bg, focus_req, focus_hint, ed_msg: ed_status.msg, ed_seq: ed_status.seq, ed_kind: ed_status.kind, layout_sig }
            BgSheetLayer { bg_open, bg_closing, bg_gen, bg, bg_state: bg_state.clone(), data, memo_id: memo_id.clone() }
            // A-3 登记（批 14，2026-11-25 判定不做）：编辑页根
            // 节点层级与原版差一层——原版两层（.editor-stage
            // 动画+背景 / 内容），Rust 三层（.editor-stage →
            // .detail → .editor-pad）。computed 已接近（.detail
            // 自带 min-height/position:relative，根层无额外
            // 声明），压层须动 .editor-stage 的动画包含块与
            // go_back 出场机制，回归风险高于收益，保留三层
            // 现状关单；若日后过渡机制再改版，可一并重估。
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
                    // 更严口径的保留例外：此处是对「其它备忘」的
                    // 跨篇查询（与列表页读总表同类），本篇字段零
                    // 读取——目标标题取实例 title 信号、memo_id
                    // 仅作命中键；本篇状态不经此回流。
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
            TextSheetLayer { text_sheet, text_sheet_closing, text_sheet_gen, sheet_edit, sheet_draft, doc, title, data, persist: persist.clone() }
            if let Some((bid, filter, ax, atop, abottom)) = panel_state {
                SlashPanel { bid, filter, anchor_x: ax, anchor_top: atop, anchor_bottom: abottom, panel, slash_click, link_for, link_pos, link_click }
            } else if let Some(bid) = link_state {
                SlashPanel { bid, filter: String::new(), anchor_x: link_x, anchor_top: link_top, anchor_bottom: link_bottom, panel, slash_click, link_for, link_pos, link_click }
            }
        }
    }
}


