//! 浮层组 hooks（批 14 三轮自 editor.rs 拆出）：菜单/
//! 背景底表信号组、Esc 关闭链、进场动画摘除。段内代码
//! 逐字搬移，只做文件组织，行为不变。

use super::super::*;

/// 菜单/背景底表信号组（use_menu_signals 返回）。
pub(in crate::editor) struct MenuSignals {
    pub(in crate::editor) menu_open: Signal<bool>,
    pub(in crate::editor) bg_open: Signal<bool>,
    pub(in crate::editor) menu_closing: Signal<bool>,
    pub(in crate::editor) menu_gen: Signal<u32>,
    pub(in crate::editor) bg_closing: Signal<bool>,
    pub(in crate::editor) bg_gen: Signal<u32>,
}

pub(in crate::editor) fn use_menu_signals() -> MenuSignals {
let menu_open = use_signal(|| false);
let bg_open = use_signal(|| false);
// 菜单/背景底表出场态与生命周期代际（浮层出场补齐，
// 原版 menuClosing / BgSheet closing）：closing 期间
// 面板保持挂载播出场 transition，220ms 计时完成后才
// 卸载；代际守卫让重排/取消的旧回调自动作废。
let menu_closing = use_signal(|| false);
let menu_gen = use_signal(|| 0u32);
let bg_closing = use_signal(|| false);
let bg_gen = use_signal(|| 0u32);
    MenuSignals { menu_open, bg_open, menu_closing, menu_gen, bg_closing, bg_gen }
}

#[allow(clippy::too_many_arguments)]
pub(in crate::editor) fn use_esc_close(
    text_sheet: Signal<Option<(String, String)>>,
    text_sheet_closing: Signal<bool>,
    text_sheet_gen: Signal<u32>,
    mut card_menu: Signal<Option<crate::blocks::CardMenuState>>,
    mut card_edit: Signal<Option<String>>,
    show_export: Signal<bool>,
    export_closing: Signal<bool>,
    menu_open: Signal<bool>,
    export_gen: Signal<u32>,
    export_anim: Signal<u8>,
    export_to_menu: Signal<bool>,
    menu_closing: Signal<bool>,
    menu_gen: Signal<u32>,
    bg_open: Signal<bool>,
    bg_closing: Signal<bool>,
    bg_gen: Signal<u32>,
    data: Signal<BackupFile>,
    bg: Signal<Option<String>>,
    mut link_for: Signal<Option<String>>,
    mut panel: Signal<Option<(String, String, f64, f64, f64)>>,
    memo_id: String,
) {
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
}

pub(in crate::editor) fn use_page_enter(closing: bool, mut page_anim_done: Signal<bool>) {
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
}
