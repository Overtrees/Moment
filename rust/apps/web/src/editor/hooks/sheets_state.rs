//! 底表信号组 hooks（批 14 三轮自 editor.rs 拆出）：
//! 导出面板信号组、图文底表信号组、图文面板打开镜像
//! 同步。段内代码逐字搬移，只做文件组织，行为不变。

use super::super::*;

/// 导出面板信号组（use_export_signals 返回）。
pub(in crate::editor) struct ExportSignals {
    pub(in crate::editor) show_export: Signal<bool>,
    pub(in crate::editor) export_closing: Signal<bool>,
    pub(in crate::editor) export_gen: Signal<u32>,
    pub(in crate::editor) export_anim: Signal<u8>,
    pub(in crate::editor) export_to_menu: Signal<bool>,
    pub(in crate::editor) ed_scroll: Signal<f64>,
}

/// 图文底表信号组（use_sheet_signals 返回）。
pub(in crate::editor) struct SheetSignals {
    pub(in crate::editor) text_sheet: Signal<Option<(String, String)>>,
    pub(in crate::editor) sheet_edit: Signal<bool>,
    pub(in crate::editor) sheet_draft: Signal<String>,
    pub(in crate::editor) text_sheet_closing: Signal<bool>,
    pub(in crate::editor) text_sheet_gen: Signal<u32>,
}

pub(in crate::editor) fn use_export_signals() -> ExportSignals {
// 导出面板（菜单内切换，不是独立弹窗）
let show_export = use_signal(|| false);
// 导出面板进出场态（原版 exportPanelClosing）：true 时面板
// 呈 opacity 0 / translateY(-10px) scale(0.94)，靠 CSS
// transition 与常态之间弹簧过渡（开场双 rAF 后撤、关闭
// 220ms 后卸载）
let export_closing = use_signal(|| false);
// 导出面板生命周期代际：开/关每次递增，异步回调（开场
// 双 rAF、关闭 220ms 计时）按代际守卫、过期自动作废。
// 关闭语义对齐原版 closeExportPanel 的 clearTimeout 重
// 排，杜绝视觉态门闩造成的遮罩永久残留（见
// animate_export_close 注释）。
let export_gen = use_signal(|| 0u32);
// 导出面板动画相位与关闭去向（遮挡续修）：相位区分挂
// 起的是开场还是关闭（export_closing 两义），去向记关
// 闭完成时回菜单还是全关——回前台补完（__mnResume 监
// 听 → settle_export_on_resume）据此收尾；渲染层据去
// 向在全关发起瞬间释放遮罩命中（菜单遮罩渲染处）。
let export_anim = use_signal(|| EXPORT_ANIM_IDLE);
let export_to_menu = use_signal(|| false);
// 页面滚动量：标题坞 >30 切换紧凑行态
let ed_scroll = use_signal(|| 0f64);
    ExportSignals { show_export, export_closing, export_gen, export_anim, export_to_menu, ed_scroll }
}

pub(in crate::editor) fn use_sheet_signals() -> SheetSignals {
// 图文全文面板（blocks::TextSheet 上下文）
let text_sheet = use_signal(|| Option::<(String, String)>::None);
let sheet_edit = use_signal(|| false);
let sheet_draft = use_signal(String::new);
// 图文面板出场态与代际（原版 ImageTextSheet closing）
let text_sheet_closing = use_signal(|| false);
let text_sheet_gen = use_signal(|| 0u32);
    SheetSignals { text_sheet, sheet_edit, sheet_draft, text_sheet_closing, text_sheet_gen }
}

pub(in crate::editor) fn use_sheet_mirror(
    text_sheet: Signal<Option<(String, String)>>,
    mut sheet_draft: Signal<String>,
    mut sheet_edit: Signal<bool>,
) {
// 图文面板打开时同步文本镜像并重置为阅读态（编辑态从
// 只读开始；镜像与块 text 经逐键写回恒一致，D-20）
use_effect(move || {
    if let Some((_, t)) = text_sheet.read().clone() {
        sheet_draft.set(t);
        sheet_edit.set(false);
    }
});
}
