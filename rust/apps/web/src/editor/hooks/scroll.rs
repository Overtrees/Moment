//! 滚动组 hooks（批 14 三轮自 editor.rs 拆出）：滚动
//! 量订阅与联动（坞紧凑态/滚动即关/斜杠跟随）、typed
//! 的 DOM input 事件源。段内代码逐字搬移，只做文件组
//! 织，行为不变。

use super::super::*;

#[allow(clippy::too_many_arguments)]
pub(in crate::editor) fn use_scroll_watch(
    mut panel: Signal<Option<(String, String, f64, f64, f64)>>,
    title_editing: Signal<bool>,
    mut ed_scroll: Signal<f64>,
    show_export: Signal<bool>,
    export_closing: Signal<bool>,
    menu_open: Signal<bool>,
    export_gen: Signal<u32>,
    export_anim: Signal<u8>,
    export_to_menu: Signal<bool>,
    menu_closing: Signal<bool>,
    menu_gen: Signal<u32>,
    bg_open: Signal<bool>,
) {
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
}

pub(in crate::editor) fn use_typed_mark(mut typed: Signal<bool>) {
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
}
