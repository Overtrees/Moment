//! 浮层动画与底表组（批 14 二轮自 editor.rs 拆出）：菜单 /
//! 背景色底表 / 图文全文面板的关闭动画与去向（MenuAfter /
//! BgAfter）、背景色生效落库、图文面板文本写回与背景色
//! 色板。只做文件组织，行为不变。

use super::*;

/// 菜单关闭完成后的去向（浮层出场补齐）：无 / 链式打开
/// 导出面板 / 链式打开背景色底表——原版 openExportPanel
/// 与更换背景菜单项都是「closeEditorMenu 后 220ms 再挂
/// 下一层」，去向在关闭发起时随计时一同排定、完成时消费。
#[derive(Clone, Copy, PartialEq)]
pub(super) enum MenuAfter {
    None,
    Export,
    Bg,
}

/// 背景色底表关闭完成后的动作（原版 BgSheet
/// closeWithAnim 的 afterClose 口径）：选色/移除在动画播
/// 满、底表卸载时点才生效，不是点击瞬间。
#[derive(Clone, PartialEq)]
pub(super) enum BgAfter {
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
pub(super) fn animate_menu_close(
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
pub(super) fn cancel_menu_close(mut menu_gen: Signal<u32>, mut menu_closing: Signal<bool>) {
    let gen = *menu_gen.read() + 1;
    menu_gen.set(gen);
    menu_closing.set(false);
}

/// 背景色生效（原 set_bg 的落库半边，现由底表关闭完成
/// 时点调用）：写 memo.bgColor、根背景同任务
/// 同步、落库保存。根背景先行值即本篇有效背景，与
/// App 派生同值（派生已是页面状态纯函数，见 main.rs
/// 根色模型注）。
pub(super) fn apply_bg_color(
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
                m.bg_color = Some(c.clone());
            }
            None => {
                m.bg_color = None;
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
    let mid = memo_id.to_string();
    spawn(async move {
        save_backup_delta(&backup, Some(&mid), None).await;
    });
}

/// 背景色底表关闭动画（原版 BgSheet closeWithAnim 口
/// 径）：置 closing 态（.sheet-wrap.is-closing：opacity
/// 200ms ease + transform 250ms 弹簧 → +20px），220ms
/// 后卸载；选色/移除经 BgAfter::Apply 在完成时点才生
/// 效。重排语义同菜单（代际守卫、旧回调作废）。
#[allow(clippy::too_many_arguments)]
pub(super) fn animate_bg_close(
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
pub(super) fn animate_text_sheet_close(
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

/// 图文面板文本写回：块 text 字段写回并落库。批 5
/// D-20 后为逐键调用（textarea oninput 每键一次，与原版
/// onChange 逐键回写 + triggerAutoSave 同口径）——关表路
/// 径不再有集中保存点，本函不逐键记 Diag（防刷环），
/// 落盘结果由「完成编辑」时的 len 打点与探针读库核对。
pub(super) fn save_sheet_text(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: &PersistHandle,
    bid: &str,
    txt: &str,
) {
    let mut d = doc.read().clone();
    if let Some(loc) = find_loc(&d, bid) {
        node_at_mut(&mut d, loc).text = Some(txt.to_string());
        doc.set(d.clone());
        persist.call(d, title.read().clone(), data);
    }
}

/// 背景色 8 色（原版 BgSheet：冷雾/暖沙/浅绿/浅蓝/浅粉/米橙/淡紫/浅杏）。
pub(super) const BG_COLORS: [&str; 8] = [
    "#eaeef2", "#e8e0d4", "#d4e8d0", "#d0e0e8", "#e8d0d4", "#fff3e0", "#e8e0f0",
    "#f0e8d0",
];

/// BgSheet 色点无障碍名（审计 E-12）：按下标取 bg.color_N，
/// 与 BG_COLORS 同序（原版 BgSheet.js colorNames 口径）。
/// 键字面列全（verify 僵尸键检查按字面引用判定）。
pub(super) fn bg_color_name(idx: usize) -> String {
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

// ── 三轮续入：暗色推导（自 editor.rs 文件头分流，原文逐字）。

/// 深色模式（渲染期读 matchMedia；切换由 scheme_tick 触发重渲染）。
pub(super) fn is_dark_mode() -> bool {
    web_sys::window()
        .and_then(|w| w.match_media("(prefers-color-scheme: dark)").ok().flatten())
        .map(|m| m.matches())
        .unwrap_or(false)
}

/// 深色下压暗自定义背景（原版 getDarkenedColor：每通道 ×0.35）。
pub(super) fn darken_hex(hex: &str) -> String {
    let h = hex.trim_start_matches('#');
    if h.len() != 6 || !h.chars().all(|c| c.is_ascii_hexdigit()) {
        return hex.to_string();
    }
    let ch = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0);
    let f = |v: u8| ((v as f32 * 0.35).round() as u8);
    format!("#{:02x}{:02x}{:02x}", f(ch(0)), f(ch(2)), f(ch(4)))
}
