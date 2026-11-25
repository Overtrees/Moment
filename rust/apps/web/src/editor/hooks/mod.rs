//! hooks 组（批 14 三轮自 editor.rs 拆出）：Editor 组
//! 件的按域自定义 hooks——域内信号声明、其 use_effect
//! 与紧密耦合的处理闭包按域成组（focus 焦点/面板、
//! slash 斜杠执行、bridge_wire 桥接线、columns 双栏、
//! overlay 浮层、scroll 滚动、sheets_state 导出/图文
//! 信号、cards_fx 卡片接线），组件内按原声明顺序无条
//! 件调用，hook 调用序与拆分前逐项一致。只做文件组
//! 织，行为不变。

mod bridge_wire;
mod cards_fx;
mod columns;
mod focus;
mod overlay;
mod scroll;
mod sheets_state;
mod slash;

pub(super) use bridge_wire::{
    use_bridge_loop, use_contexts, use_persist, use_resume_watch, use_scheme_watch,
    use_title_session, Contexts, PersistFx, TitleSession,
};
pub(super) use cards_fx::{use_card_hydrate, use_card_retry, use_wiki_nav};
pub(super) use columns::{use_columns, Columns};
pub(super) use focus::{use_focus_requests, use_panel_fx, use_trail_materialize, use_typed, PanelFx};
pub(super) use overlay::{use_esc_close, use_menu_signals, use_page_enter, MenuSignals};
pub(super) use scroll::{use_scroll_watch, use_typed_mark};
pub(super) use sheets_state::{
    use_export_signals, use_sheet_mirror, use_sheet_signals, ExportSignals, SheetSignals,
};
pub(super) use slash::{use_link_submit, use_slash_click};
