//! 桥接线组 hooks（批 14 三轮自 editor.rs 拆出）：持
//! 久化句柄与尾巴恢复落盘、标题会话回调、桥消息循环、
//! 上下文提供、回前台补完监听、深浅模式切换监听。段内
//! 代码逐字搬移，只做文件组织，行为不变。

use super::super::*;

/// 持久化句柄组（use_persist 返回）。
pub(in crate::editor) struct PersistFx {
    pub(in crate::editor) persist: PersistHandle,
}

/// 标题会话回调组（use_title_session 返回）。
pub(in crate::editor) struct TitleSession {
    pub(in crate::editor) title_commit: EventHandler<String>,
    pub(in crate::editor) title_session: EventHandler<bool>,
}

/// 上下文信号组（use_contexts 返回）：块组件经 context
/// 消费的编辑态信号（声明与 provider 在本 hook 内按原
/// 交错序执行）。
pub(in crate::editor) struct Contexts {
    pub(in crate::editor) md_edit: Signal<Option<String>>,
    pub(in crate::editor) active_edit: Signal<Option<String>>,
    pub(in crate::editor) card_retry: Signal<Option<String>>,
    pub(in crate::editor) wiki_nav: Signal<Option<String>>,
    pub(in crate::editor) sel_block: Signal<Option<String>>,
    pub(in crate::editor) card_edit: Signal<Option<String>>,
    pub(in crate::editor) card_menu: Signal<Option<crate::blocks::CardMenuState>>,
}

pub(in crate::editor) fn use_persist(
    memo_id: String,
    state_owner: String,
    tail_recovered: std::rc::Rc<std::cell::Cell<usize>>,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    updated_sig: Signal<moment_core::model::Timestamp>,
) -> PersistFx {
// 持久化：把当前标题+文档写回总数据并落 IndexedDB
let persist = PersistHandle(std::rc::Rc::new({
    let memo_id = memo_id.clone();
    let state_owner = state_owner.clone();
    move |doc_snapshot: Vec<Node>, title_snapshot: String, mut data: Signal<BackupFile>| {
        // Fn 闭包内写信号：句柄本地副本（Signal 为 Copy，
        // 同一底层信号），与本仓桥闭包同口径。
        let mut updated_sig = updated_sig;
        // 守卫拒写（状态归属与写目标不一致）时整笔跳过：
        // 不 set、不落盘（见 build_backup）。
        let Some(backup) =
            build_backup(data, &memo_id, &state_owner, doc_snapshot, title_snapshot)
        else {
            return;
        };
        // 实例自有 updated_at 镜像：build_backup 已把该篇
        // updated_at bump 到当刻，实例信号同值跟进，渲染
        // 期时间标签只读实例态（更严口径，见 editor.rs）。
        if let Some(m) = backup
            .memos
            .iter()
            .find(|m| m.id.to_string() == memo_id)
        {
            updated_sig.set(m.updated_at.clone());
        }
        data.set(backup.clone());
        let mid = memo_id.clone();
        spawn(async move {
            save_backup_delta(&backup, Some(&mid), None).await;
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
    PersistFx { persist }
}

pub(in crate::editor) fn use_title_session(
    persist: PersistHandle,
    doc: Signal<Vec<Node>>,
    mut title: Signal<String>,
    data: Signal<BackupFile>,
    mut ed_scroll: Signal<f64>,
    mut title_editing: Signal<bool>,
) -> TitleSession {
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
    TitleSession { title_commit, title_session }
}

#[allow(clippy::too_many_arguments)]
pub(in crate::editor) fn use_bridge_loop(
    memo_id: String,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    panel: Signal<Option<(String, String, f64, f64, f64)>>,
    link_for: Signal<Option<String>>,
    link_pos: Signal<(f64, f64, f64)>,
    focus_req: Signal<Option<(String, usize)>>,
    dom_set: Signal<Option<(String, String, usize)>>,
    md_edit: Signal<Option<String>>,
    active_edit: Signal<Option<String>>,
    sel_block: Signal<Option<String>>,
    manifest: Signal<String>,
    hist: Signal<Vec<HistSnap>>,
    hist_idx: Signal<usize>,
    hist_clock: Signal<(f64, bool)>,
    epoch: Signal<u32>,
    focus_hint: Signal<Option<(String, usize)>>,
    ed_scroll: Signal<f64>,
    card_caret: Signal<Option<String>>,
    card_menu: Signal<Option<crate::blocks::CardMenuState>>,
    card_edit: Signal<Option<String>>,
    media_req: Signal<Option<MediaReq>>,
    persist: PersistHandle,
    layout_sig: Signal<Option<moment_core::MemoLayout>>,
) {
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
                let before_layout = layout_json(&layout_sig.read().clone());
                let (skip_hist, coalesce) = handle_bridge_msg(&msg, &memo_id, doc, title, data, panel, link_for, link_pos, focus_req, dom_set, md_edit, active_edit, sel_block, manifest, hist, hist_idx, hist_clock, epoch, focus_hint, ed_scroll, card_caret, card_menu, card_edit, media_req, &persist, layout_sig);
                let after = serde_json::to_string(&*doc.read()).unwrap_or_default();
                let after_layout = layout_json(&layout_sig.read().clone());
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
}

pub(in crate::editor) fn use_contexts(
    text_sheet: Signal<Option<(String, String)>>,
    manifest: Signal<String>,
) -> Contexts {
use_context_provider(|| crate::blocks::TextSheet(text_sheet));
let md_edit = use_signal(|| Option::<String>::None);
use_context_provider(|| crate::blocks::MdEdit(md_edit));
// 聚焦中的编辑块（桥 focusBlock/blurBlock 维护）：编辑中的
// 段落不转 md 预览，失焦才转（原版 blur 转换口径）
let active_edit = use_signal(|| Option::<String>::None);
use_context_provider(|| crate::blocks::ActiveEdit(active_edit));
// 卡片重试（blocks::CardRetry 上下文）：音乐卡 error 态点重试
let card_retry = use_signal(|| Option::<String>::None);
use_context_provider(|| crate::blocks::CardRetry(card_retry));
// Wiki 导航（blocks::WikiNav 上下文）：md 预览里的 wiki
// 链接点击 → 先落盘当前编辑再导航（原版双链优先 + flush）
let wiki_nav = use_signal(|| Option::<String>::None);
use_context_provider(|| crate::blocks::WikiNav(wiki_nav));
// 原子块选中态（blocks::SelBlock 上下文）
let sel_block = use_signal(|| Option::<String>::None);
use_context_provider(|| crate::blocks::SelBlock(sel_block));
// 卡片编辑态（blocks::CardEdit 上下文，卡片交互专项）：
// 经浮层菜单「编辑」进入，全局同时仅一张卡在编辑态。
let card_edit = use_signal(|| Option::<String>::None);
use_context_provider(|| crate::blocks::CardEdit(card_edit));
// 卡片浮层菜单（信号经 Contexts 以 props 下传，卡片
// 交互专项）：长按拾起/桌面右键两路同开。
let card_menu = use_signal(|| Option::<crate::blocks::CardMenuState>::None);
// 附件清单（blocks::Manifest 上下文）：附件块文件名查
// manifest（审计 E2，原版 renderAtomicHTML files 表口径）
use_context_provider(|| crate::blocks::Manifest(manifest));
    Contexts { md_edit, active_edit, card_retry, wiki_nav, sel_block, card_edit, card_menu }
}

pub(in crate::editor) fn use_resume_watch(
    show_export: Signal<bool>,
    export_closing: Signal<bool>,
    menu_open: Signal<bool>,
    export_gen: Signal<u32>,
    export_anim: Signal<u8>,
    export_to_menu: Signal<bool>,
) {
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
}

pub(in crate::editor) fn use_scheme_watch(
    mut scheme_tick: Signal<u32>,
    bg: Signal<Option<String>>,
) {
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
}
