//! 设置与备份页（对齐原版 components/SettingsView.js、
//! BackupView.js 的文件分工）：设置页、备份页与导入/导出处理。

use dioxus::prelude::*;
use mynote_core::{read_backup_zip, write_backup_zip, BackupFile};

use crate::backup::BackupProvider;
use crate::diag;
use crate::i18n;
use crate::icons;
use crate::idb;

/// 原版文字大小映射（MynoteTokens.fontSizeMap）：小 14 / 中 16 /
/// 大 19（px），存 localStorage sj_fontsize（与原版同键）。
pub(crate) fn font_px(key: &str) -> &'static str {
    match key {
        "small" => "14px",
        "large" => "19px",
        _ => "16px",
    }
}

fn local_get(key: &str) -> Option<String> {
    web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|s| s.get_item(key).ok().flatten())
}

fn local_set(key: &str, val: &str) {
    if let Some(s) = web_sys::window().and_then(|w| w.local_storage().ok().flatten()) {
        let _ = s.set_item(key, val);
    }
}

/// 页面过渡时长（原版 getPageTransitionMs 口径）：reduced-
/// motion 为 0；编辑器为 320（出场字面 280ms + 原版 +40
/// 余量，与 editor.js handleClose 的等待同值）；其余页读根
/// 元素 --motion-page-transition 计算值、缺失/异常回落 280。
/// 同步直读（web_sys），供 App 栈式交接的离页卸载计时复用
/// ——旧 close_page 的「置 closing + JS 延时后 on_back 卸载」
/// 串行交换已随栈式交接退役：关闭即刻 on_back，离页由 App
/// 以 closing prop 快照渲染、出场与卸载归 App 状态机。
pub(crate) fn page_transition_ms(editor: bool) -> u32 {
    let Some(w) = web_sys::window() else {
        return if editor { 320 } else { 280 };
    };
    let reduced = w
        .match_media("(prefers-reduced-motion: reduce)")
        .ok()
        .flatten()
        .map(|m| m.matches())
        .unwrap_or(false);
    if reduced {
        return 0;
    }
    if editor {
        return 320;
    }
    let var_ms = (|| {
        let el = w.document()?.document_element()?;
        let style = w.get_computed_style(&el).ok()??;
        let raw = style.get_property_value("--motion-page-transition").ok()?;
        raw.trim()
            .trim_end_matches("ms")
            .trim()
            .parse::<f64>()
            .ok()
    })();
    match var_ms {
        Some(v) if v.is_finite() && v >= 0.0 => v.round() as u32,
        _ => 280,
    }
}

/// 全局 toast（备份页与编辑页共用同规格；原版
/// BackupView.showStatus 口径，审计 G1/G2/G3 根治，编辑页
/// 半边在集成收口时并入）：类型由调用点显式给出——success 3s、
/// error 6s、info 6s 后自动消失并卸载 DOM（原版 info 类是
/// 进行中提示、无自动消失，靠下一条状态覆盖；此处给 info
/// 同设 6s 上限属有意调优，避免待定类提示永久驻留）。
/// 每次 show 自增 seq 并以 seq 作渲染 key：同文案重复触发
/// 也会重挂、入场动画重启，不再「第二次起不可见」；计时器
/// 回调按 seq 校验，旧计时器不会误关后来的 toast。
#[derive(Clone, Copy)]
pub(crate) struct Toast {
    pub(crate) msg: Signal<String>,
    pub(crate) seq: Signal<u64>,
    pub(crate) kind: Signal<&'static str>,
    /// Diag 标签（备份页 BACKUP / 编辑页 EDIT），show 时记一行。
    pub(crate) tag: &'static str,
}

impl Toast {
    pub(crate) fn show(self, kind: &'static str, text: String) {
        let mut seq = self.seq;
        let n = seq() + 1;
        seq.set(n);
        let mut kind_sig = self.kind;
        kind_sig.set(kind);
        let mut msg = self.msg;
        msg.set(text);
        diag::log(self.tag, &format!("toast {kind} #{n}"));
        let ms: u32 = if kind == "success" { 3000 } else { 6000 };
        spawn(async move {
            let mut eval = document::eval(&format!(
                "setTimeout(() => dioxus.send(null), {ms});"
            ));
            let _ = eval.recv::<serde_json::Value>().await;
            if seq() == n {
                msg.set(String::new());
            }
        });
    }
}

/// 备份操作历史（原版 BackupView 的「最近操作」，本地保存）。
/// 条目带 detail（原版 addHistoryEntry 的 detail：导出/恢复成功
/// 时为文件名，失败时为空），成功与失败都记（审计 S5）。
/// 注：历史键与原版 `memos_backup_history` 不互通一项只评估
/// 不迁移——两版部署在不同 origin，localStorage 本就不共享，
/// 且条目 schema 不同（原版 {type,status,message,detail,
/// timestamp}），强行迁移无实际收益。
fn push_history(kind: &str, ok: bool, title: &str, detail: &str) {
    let raw = local_get("mynote_backup_history").unwrap_or_else(|| "[]".to_string());
    let mut arr: Vec<serde_json::Value> =
        serde_json::from_str(&raw).unwrap_or_default();
    arr.insert(
        0,
        serde_json::json!({
            "type": kind,
            "ok": ok,
            "title": title,
            "detail": detail,
            "at": now_iso(),
        }),
    );
    arr.truncate(20);
    if let Ok(s) = serde_json::to_string(&arr) {
        local_set("mynote_backup_history", &s);
    }
    diag::log("BACKUP", &format!("history {kind} ok={ok} {title}"));
}

/// 设置页（原版 SettingsView 逐项复刻）：玻璃返回圆钮 + 紧凑
/// 标题 + 126px 顶距内容；外观（文字大小分段）/ 数据（备份与
/// 恢复；语言、诊断为按用户要求加入的同组入口）/ 关于卡。
#[component]
pub(crate) fn SettingsView(
    mut font_size: Signal<String>,
    /// 离页态（App 栈式交接）：为 true 时本实例是离页层里的
    /// 出场快照——内容层直接挂 slideOut、返回即刻回调（当前
    /// 实例的返回钮也不再延时，卸载归 App 状态机）。
    closing: bool,
    on_back: EventHandler<()>,
    on_backup: EventHandler<()>,
    on_language: EventHandler<()>,
    on_diag: EventHandler<()>,
) -> Element {
    let cur_lang_native = i18n::LANGS
        .iter()
        .find(|l| l.code == i18n::current())
        .map(|l| l.native)
        .unwrap_or("");
    let fs = font_size.read().clone();
    // 进/出场（原版 SettingsView 口径）：动画只挂内容层，
    // 根层、返回钮与标题胶囊不滑动。出场由 App 栈式交接以
    // closing prop 驱动（离页层快照渲染），本组件不再自管
    // closing 信号与延时卸载。
    use_hook(move || {
        if !closing {
            diag::log("SET", "settings enter slideIn");
        }
    });
    let content_class = if closing {
        "page-content page-slide-out"
    } else {
        "page-content page-slide-in"
    };
    rsx! {
        div { style: "background:var(--primary-bg);min-height:100vh;",
            button {
                class: "editor-fab left",
                onclick: move |_| on_back.call(()),
                span { dangerous_inner_html: "{icons::back_markup()}" }
            }
            div {
                class: "page-title compact",
                style: "visibility:visible;opacity:1;pointer-events:none;",
                "{i18n::t(\"settings.title\")}"
            }
            div { class: "{content_class}",
                div { class: "section-header", style: "padding-top:4px;", "{i18n::t(\"settings.appearance\")}" }
                div { class: "list-group",
                    div { class: "swipe-wrapper",
                        div { class: "list-item", style: "cursor:default;",
                            div { class: "item-left",
                                div { class: "item-title",
                                    span { class: "item-title-text", "{i18n::t(\"settings.font_size\")}" }
                                }
                                div { class: "item-meta", "{i18n::t(\"settings.font_note\")}" }
                            }
                            div { class: "seg-row",
                                for (key, label, lfs) in [("small", "settings.font_small", "0.8125rem"), ("medium", "settings.font_medium", "0.9375rem"), ("large", "settings.font_large", "1.0625rem")] {
                                    button {
                                        class: if fs == key { "seg-btn sel" } else { "seg-btn" },
                                        key: "{key}",
                                        style: "font-size:{lfs};",
                                        onclick: move |_| {
                                            local_set("sj_fontsize", key);
                                            font_size.set(key.to_string());
                                            diag::log("SET", &format!("font size {key}"));
                                        },
                                        "{i18n::t(label)}"
                                    }
                                }
                            }
                        }
                    }
                }
                div { class: "page-gap" }
                div { class: "section-header", style: "padding-top:4px;", "{i18n::t(\"settings.data\")}" }
                div { class: "backup-card",
                    div { class: "set-row", onclick: move |_| on_backup.call(()),
                        div { class: "item-left",
                            div { class: "item-title",
                                span { class: "item-title-text", "{i18n::t(\"settings.backup\")}" }
                            }
                            div { class: "item-meta", "{i18n::t(\"settings.backup_meta\")}" }
                        }
                        span { class: "row-chevron", "›" }
                    }
                    div { class: "about-div" }
                    div { class: "set-row", onclick: move |_| on_language.call(()),
                        div { class: "item-left",
                            div { class: "item-title",
                                span { class: "item-title-text", "{i18n::t(\"settings.language\")}" }
                            }
                            div { class: "item-meta", "{cur_lang_native}" }
                        }
                        span { class: "row-chevron", "›" }
                    }
                    div { class: "about-div" }
                    div { class: "set-row", onclick: move |_| on_diag.call(()),
                        div { class: "item-left",
                            div { class: "item-title",
                                span { class: "item-title-text", "{i18n::t(\"settings.diag\")}" }
                            }
                        }
                        span { class: "row-chevron", "›" }
                    }
                }
                div { class: "page-gap" }
                div { class: "section-header", style: "padding-top:4px;", "{i18n::t(\"settings.about\")}" }
                div { class: "backup-card",
                    div { class: "about-row",
                        div { class: "item-title", "{i18n::t(\"settings.version\")}" }
                        span { class: "about-val", "2.2.7" }
                    }
                    div { class: "about-div" }
                    div { class: "about-row",
                        div { class: "item-title", "{i18n::t(\"settings.contact\")}" }
                        span { class: "about-val", style: "font-size:0.85rem;", "overcanopies@gmail.com" }
                    }
                }
                div { class: "settings-footer", "{i18n::t(\"settings.footer\")}" }
            }
        }
    }
}

/// 备份页（原版 BackupView 复刻）：状态总览 hero + 本地备份
/// 卡（导出/导入，带确认弹窗）+ iCloud 说明一行 + 最近操作。
/// 谷歌云备份入口已按用户拍板（2026-11-22）移除；iCloud 不
/// 另设机制——现有导出（分享面板「存储到文件」）与导入
/// （文件选择器）本就可达 iCloud Drive，只以一行静态说明
/// 把路径讲清，不加按钮/管线。
#[component]
pub(crate) fn BackupView(
    data: Signal<BackupFile>,
    manifest: Signal<String>,
    mut status: Signal<String>,
    gen: Signal<u32>,
    /// 离页态（App 栈式交接），语义同 SettingsView 的 closing。
    closing: bool,
    on_back: EventHandler<()>,
) -> Element {
    let memo_count = data.read().memos.len();
    // 附件计数口径对齐原版 BackupView.js:74-96（审计 S9）：
    // 遍历全部备忘 doc 顶层 attachment 块的 fileId 去重计数，
    // 而非 manifest.attachments 键数——manifest 含未被引用的
    // 孤儿附件时旧口径会多计。
    let attach_count = {
        let mut ids = std::collections::HashSet::new();
        for memo in data.read().memos.iter() {
            for node in memo.doc.iter() {
                if node.node_type.as_deref() == Some("attachment") {
                    if let Some(fid) = attachment_file_id(node) {
                        ids.insert(fid);
                    }
                }
            }
        }
        ids.len()
    };
    let history: Vec<serde_json::Value> = local_get("mynote_backup_history")
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    // 「上次备份」口径：从历史中取最近一条 type=export 且
    // 成功的时间并格式化（今天/昨天 HH:MM 或 M/D HH:MM），
    // 未备份过即「暂无」。原版此处取 type=upload（Google 云端
    // 上传成功）；谷歌入口已移除、导出是仅剩的备份动作，
    // 故改取 export（此前取 upload 时该值恒为「暂无」）。
    let last_backup = history
        .iter()
        .find(|h| {
            h.get("type").and_then(|v| v.as_str()) == Some("export")
                && h.get("ok").and_then(|v| v.as_bool()) == Some(true)
        })
        .and_then(|h| h.get("at").and_then(|v| v.as_str()))
        .map(format_last_backup)
        .unwrap_or_else(|| i18n::t("backup.never"));
    // modal: None | "export" | "import"（导入时已暂存校验过的包）
    let mut modal = use_signal(|| Option::<String>::None);
    let mut pending = use_signal(|| Option::<Vec<u8>>::None);
    // 暂存包的文件名（历史条目 detail 用，原版 restore 条目
    // detail = file.name）
    let mut pending_name = use_signal(|| String::new());
    // 进/出场（原版 BackupView 口径，同 SettingsView）：
    // 动画只挂内容层；备份弹窗与 toast 挂在根层，不参与
    // 滑动。出场由 App 栈式交接以 closing prop 驱动。
    use_hook(move || {
        if !closing {
            diag::log("BACKUP", "backup enter slideIn");
        }
    });
    let content_class = if closing {
        "page-content page-slide-out"
    } else {
        "page-content page-slide-in"
    };
    let toast = Toast {
        msg: status,
        seq: use_signal(|| 0u64),
        kind: use_signal(|| "info"),
        tag: "BACKUP",
    };
    let toast_seq = *toast.seq.read();
    let toast_kind = *toast.kind.read();
    let status_text = toast.msg.read().clone();

    rsx! {
        div { style: "background:var(--primary-bg);min-height:100vh;",
            button {
                class: "editor-fab left",
                onclick: move |_| on_back.call(()),
                span { dangerous_inner_html: "{icons::back_markup()}" }
            }
            div {
                class: "page-title compact",
                style: "visibility:visible;opacity:1;pointer-events:none;",
                "{i18n::t(\"settings.backup\")}"
            }
            div { class: "{content_class}",
                div { class: "backup-hero",
                    div { class: "backup-hero-top",
                        div { class: "backup-hero-title", "{i18n::t(\"backup.hero_title\")}" }
                    }
                    div { class: "backup-desc",
                        span { "{i18n::t(\"backup.last\")} {last_backup}" }
                        span { style: "opacity:0.3;", "·" }
                        span { "{memo_count} {i18n::t(\"backup.memos\")} · {attach_count} {i18n::t(\"backup.attachments\")}" }
                    }
                }
                div { class: "backup-card",
                    div {
                        class: "backup-row",
                        onclick: move |_| modal.set(Some("export".to_string())),
                        span { class: "backup-row-icon", dangerous_inner_html: "{crate::icons::export_icon_markup()}" }
                        div { class: "backup-row-left",
                            div { class: "backup-row-title", "{i18n::t(\"backup.export_title\")}" }
                            div { class: "backup-row-desc", "{i18n::t(\"backup.export_desc\")}" }
                        }
                        div { class: "backup-row-right",
                            span { class: "backup-row-arrow", "›" }
                        }
                    }
                    label { class: "backup-row no-border",
                        span { class: "backup-row-icon", dangerous_inner_html: "{crate::icons::import_icon_markup()}" }
                        div { class: "backup-row-left",
                            div { class: "backup-row-title", "{i18n::t(\"backup.import_title\")}" }
                            div { class: "backup-row-desc", "{i18n::t(\"backup.import_desc\")}" }
                        }
                        div { class: "backup-row-right",
                            span { class: "backup-row-arrow", "›" }
                        }
                        input {
                            id: "file-import",
                            r#type: "file",
                            accept: ".zip",
                            style: "display:none",
                            onchange: move |_| {
                                spawn(async move {
                                    if let Some((name, bytes)) = crate::backup::current().fetch().await {
                                        diag::log("IMPORT", &format!("zip {}B staged", bytes.len()));
                                        match read_backup_zip(&bytes) {
                                            Ok(_) => {
                                                pending.set(Some(bytes));
                                                pending_name.set(name);
                                                modal.set(Some("import".to_string()));
                                            }
                                            Err(e) => {
                                                diag::log("IMPORT", &format!("validate err: {e}"));
                                                // 用户文案不带内部错误
                                                // 原文（审计 S7）：原始
                                                // 错误只进 Diag。
                                                push_history("restore", false, &i18n::t("backup.hist_import_failed"), &name);
                                                toast.show("error", i18n::t("status.import_invalid"));
                                            }
                                        }
                                    }
                                });
                            },
                        }
                    }
                }
                div { class: "backup-note", "{i18n::t(\"backup.icloud_note\")}" }
                if !history.is_empty() {
                    div { class: "backup-section-title", "{i18n::t(\"backup.history\")}" }
                    div { class: "backup-card", style: "padding:2px 0;",
                        // 条目形态对齐原版 BackupView 渲染段（审计
                        // S5）：状态色点（成功 success / 失败
                        // danger-bright）+ 标题与类型徽章 + 时间戳
                        // （YYYY-MM-DD HH:MM）与 detail，只渲染
                        // 前 6 条（存储上限仍为 20）。
                        for (i, h) in history.iter().take(6).enumerate() {
                            {
                                let kind = h.get("type").and_then(|v| v.as_str()).unwrap_or("");
                                let kind_label = match kind {
                                    "export" => i18n::t("backup.kind_export"),
                                    "restore" => i18n::t("backup.kind_restore"),
                                    _ => i18n::t("backup.kind_export"),
                                };
                                let ok = h.get("ok").and_then(|v| v.as_bool()).unwrap_or(true);
                                let dot = if ok { "var(--color-success)" } else { "var(--color-danger-bright)" };
                                let title = h.get("title").and_then(|v| v.as_str()).unwrap_or("").to_string();
                                let detail = h.get("detail").and_then(|v| v.as_str()).unwrap_or("").to_string();
                                let at = h.get("at").and_then(|v| v.as_str()).unwrap_or("").to_string();
                                let ts = format_history_ts(&at);
                                let shown = history.len().min(6);
                                let row_style = format!(
                                    "display:flex;align-items:center;gap:12px;padding:12px 14px;{}",
                                    if i + 1 < shown { "border-bottom:0.5px solid var(--border-color);" } else { "" },
                                );
                                rsx! {
                                    div {
                                        key: "{i}",
                                        style: "{row_style}",
                                        span { style: "width:8px;height:8px;border-radius:var(--radius-circle);background:{dot};flex-shrink:0;" }
                                        div { style: "flex:1;min-width:0;",
                                            div { style: "font-size:var(--font-14);font-weight:600;display:flex;align-items:center;gap:6px;",
                                                span { "{title}" }
                                                span { style: "font-size:var(--font-9);font-weight:700;padding:1px 6px;border-radius:var(--radius-999);text-transform:uppercase;letter-spacing:0.3px;background:var(--glass-control-bg);border:0.5px solid var(--glass-control-border);color:var(--glass-label-color);", "{kind_label}" }
                                            }
                                            div { style: "font-size:var(--font-12);color:var(--text-secondary);margin-top:2px;display:flex;align-items:center;gap:6px;",
                                                span { "{ts}" }
                                                if !detail.is_empty() {
                                                    span { style: "opacity:0.3;", "·" }
                                                    span { "{detail}" }
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
            if let Some(m) = modal.read().as_ref() {
                div { class: "backup-modal-scrim",
                    // MODAL 量测（审计 §6 第 0 步，比照 LBX）：
                    // 挂载后记 open 行（根色快照 + 整屏层普
                    // 查）；导出/导入两模式共用此挂载点。关
                    // 闭在确认/取消 handler 摘除前记 close。
                    onmounted: move |_| diag::log_modal("backup", "open"),
                    // 无压暗登记：本层为透明遮罩（原版
                    // fixedOverlay 口径）——2026-11-23 用户
                    // 裁定 C 撤掉 0.28 压暗呈现与 DimLayer
                    // 注册，根色不随本层改写；灯箱的预压暗
                    // 登记其后亦按恢复集 (b) 摘除，DimStack
                    // 现无注册者、派生恒基色（见 main.rs）。
                    div { class: "backup-modal",
                        div { class: "backup-modal-title",
                            if m == "export" { "{i18n::t(\"backup.sheet_export_title\")}" } else { "{i18n::t(\"backup.sheet_import_title\")}" }
                        }
                        div { class: "backup-modal-msg",
                            if m == "export" { "{i18n::t(\"backup.export_msg\")}" } else { "{i18n::t(\"backup.import_msg\")}" }
                        }
                        // 按钮序对齐原版确认表（审计 S3）：确认
                        // （primary）在上、取消在下。
                        div { class: "backup-modal-actions",
                            button {
                                class: "backup-btn primary",
                                onclick: move |_| {
                                    diag::log_modal("backup", "close");
                                    let kind = modal.read().clone();
                                    modal.set(None);
                                    if kind.as_deref() == Some("export") {
                                        let backup = data.read().clone();
                                        let manifest_raw = manifest.read().clone();
                                        spawn(async move {
                                            handle_export(backup, manifest_raw, toast).await;
                                        });
                                    } else {
                                        let pend = pending.read().clone();
                                        if let Some(bytes) = pend {
                                            pending.set(None);
                                            let fname = pending_name.read().clone();
                                            spawn(async move {
                                                apply_import(bytes, fname, data, manifest, toast, gen).await;
                                            });
                                        }
                                    }
                                },
                                if m == "export" { "{i18n::t(\"backup.confirm_export\")}" } else { "{i18n::t(\"backup.confirm_import\")}" }
                            }
                            button {
                                class: "backup-btn secondary",
                                onclick: move |_| {
                                    diag::log_modal("backup", "close");
                                    modal.set(None);
                                    pending.set(None);
                                },
                                "{i18n::t(\"action.cancel\")}"
                            }
                        }
                    }
                }
            }
            if !status_text.is_empty() {
                // key = seq（非文案）：同文案重触发也重挂
                // （审计 G1）；计时到点由 Toast::show 卸载
                // （审计 G3）；形态为原版全宽条（审计 G2）。
                div { key: "{toast_seq}", class: "backup-toast",
                    if toast_kind == "info" {
                        span { class: "backup-toast-spinner" }
                    } else if toast_kind == "success" {
                        span { class: "backup-toast-icon", "✅" }
                    } else {
                        span { class: "backup-toast-icon", "❌" }
                    }
                    span { class: "backup-toast-text", "{status_text}" }
                }
            }
        }
    }
}

/// 确认后执行导入：全量替换（原版恢复语义）。用户可见的失败
/// 文案一律本地化、不带内部错误原文（审计 S7），原文只进
/// Diag；成败都记历史（审计 S5），成功条目 detail = 文件名
/// （原版 addHistoryEntry('restore','success',…, file.name)）。
async fn apply_import(
    bytes: Vec<u8>,
    file_name: String,
    mut data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    toast: Toast,
    mut gen: Signal<u32>,
) {
    match read_backup_zip(&bytes) {
        Ok(pkg) => {
            let memos_json = match serde_json::to_string(&pkg.backup) {
                Ok(s) => s,
                Err(e) => {
                    diag::log("IMPORT", &format!("serialize err: {e}"));
                    push_history("restore", false, &i18n::t("backup.hist_import_failed"), "");
                    toast.show("error", i18n::t("status.import_error"));
                    return;
                }
            };
            let manifest_raw = String::from_utf8_lossy(&pkg.manifest_raw).into_owned();
            let atts: Vec<(String, Vec<u8>)> =
                pkg.attachments.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
            let (n, m) = (pkg.backup.memos.len(), atts.len());
            if let Err(e) = idb::save_all(&memos_json, &manifest_raw, &atts).await {
                diag::log("IMPORT", &format!("save err: {e:?}"));
                push_history("restore", false, &i18n::t("backup.hist_import_failed"), "");
                toast.show("error", i18n::t("status.import_error"));
                return;
            }
            data.set(pkg.backup.clone());
            manifest.set(manifest_raw);
            gen.set(gen() + 1);
            diag::log("IMPORT", &format!("ok memos={n} atts={m}"));
            push_history("restore", true, &i18n::t("backup.hist_restored"), &file_name);
            toast.show("success", i18n::tf("status.imported", &[("n", &n.to_string()), ("m", &m.to_string())]));
        }
        Err(e) => {
            diag::log("IMPORT", &format!("err: {e}"));
            push_history("restore", false, &i18n::t("backup.hist_import_failed"), &file_name);
            toast.show("error", i18n::t("status.import_invalid"));
        }
    }
}

async fn handle_export(
    mut backup: BackupFile,
    manifest_raw: String,
    toast: Toast,
) {
    backup.exported_at = Some(serde_json::Value::String(now_iso()));
    // avatars 键恒在（原版 buildBackupPayload，BackupView.js:
    // 143-155）：无头像时导出 {} 而非省略该键，与原版/Flutter
    // 互通口径一致；有头像时原样带出（导入时已随 BackupFile
    // 整体落库，见 apply_import）。
    if backup.avatars.is_none() {
        backup.avatars = Some(serde_json::json!({}));
    }
    let atts = idb::get_all_attachments().await;
    let att_map: std::collections::BTreeMap<String, Vec<u8>> = atts.into_iter().collect();
    match write_backup_zip(&backup, manifest_raw.as_bytes(), &att_map) {
        Ok(bytes) => {
            diag::log("EXPORT", &format!("ok {}B atts={}", bytes.len(), att_map.len()));
            // 送出经备份 provider 边界（backup::BackupProvider，
            // 当前 FileProvider：优先系统分享面板，不支持/失败
            // 回落下载，用户取消则不送出）。成功记 type=export
            // 历史，「上次备份」取最近一条成功导出（谷歌 upload
            // 口径已随谷歌入口移除，见 BackupView 的
            // last_backup 推导）。
            let filename = export_filename();
            let provider = crate::backup::current();
            match provider.store(&filename, &bytes).await {
                crate::backup::StoreOutcome::Shared => {
                    // 原版条目：message「文件已分享」+ detail 文件名
                    push_history("export", true, &i18n::t("status.shared"), &filename);
                    toast.show("success", i18n::t("status.shared"));
                }
                crate::backup::StoreOutcome::Cancelled => {
                    diag::log("EXPORT", "share cancelled by user");
                }
                crate::backup::StoreOutcome::Downloaded => {
                    // 原版条目：message「备份已下载」+ detail 文件名
                    push_history("export", true, &i18n::t("backup.hist_downloaded"), &filename);
                    toast.show("success", i18n::t("status.exported"));
                }
            }
        }
        Err(e) => {
            diag::log("EXPORT", &format!("err: {e}"));
            // 失败也记历史（审计 S5）；detail 不放内部错误原文
            push_history("export", false, &i18n::t("backup.hist_export_failed"), "");
            toast.show("error", i18n::tf("status.export_failed", &[("e", &e.to_string())]));
        }
    }
}

/// 附件块 fileId（与 blocks::file_id 同口径：extra.fileId 优先，
/// 其次 attrs.fileId；空串视为无）。供备份页附件计数（S9）。
fn attachment_file_id(node: &mynote_core::Node) -> Option<String> {
    let pick = |v: Option<&serde_json::Value>| {
        v.and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
    };
    pick(node.extra.get("fileId"))
        .or_else(|| pick(node.extra.get("attrs").and_then(|a| a.get("fileId"))))
}

/// 历史条目时间戳格式（原版 BackupView 渲染段）：本地时间
/// YYYY-MM-DD HH:MM，月/日/时/分补零。
fn format_history_ts(iso: &str) -> String {
    if iso.is_empty() {
        return String::new();
    }
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_str(iso));
    format!(
        "{}-{:02}-{:02} {:02}:{:02}",
        d.get_full_year() as i64,
        d.get_month() + 1,
        d.get_date(),
        d.get_hours(),
        d.get_minutes()
    )
}

fn now_iso() -> String {
    js_sys::Date::new_0().to_iso_string().as_string().unwrap_or_default()
}

/// 导出文件名（原版 BackupView.js:170）：`此刻备份_<UTC 日期>.zip`，
/// 日期取 ISO 串前 10 位。同日多次导出原版同名（不做去重，
/// 浏览器下载层面的重名处理与原版一致）。
fn export_filename() -> String {
    let iso = now_iso();
    let day = iso.get(..10).unwrap_or(&iso);
    format!("此刻备份_{day}.zip")
}

/// 公历日序数（days-from-civil），供本地日期差比较。
fn day_number(y: i64, m: i64, d: i64) -> i64 {
    let y_adj = if m <= 2 { y - 1 } else { y };
    let era = if y_adj >= 0 { y_adj } else { y_adj - 399 } / 400;
    let yoe = y_adj - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// 「上次备份」时间格式化（原版 BackupView.js:83-110）：
/// 今天/昨天 + 时间，或 M/D + 时间；时间部分 24h 制 HH:MM
/// （时分补零）、12h 制 上午/下午 h:MM。
fn format_last_backup(iso: &str) -> String {
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_str(iso));
    let now = js_sys::Date::new_0();
    let day_of = |dt: &js_sys::Date| {
        day_number(
            dt.get_full_year() as i64,
            dt.get_month() as i64 + 1,
            dt.get_date() as i64,
        )
    };
    let diff = day_of(&now) - day_of(&d);
    let h = d.get_hours();
    let min = d.get_minutes();
    let time = if crate::list::is_24h() {
        format!("{h:02}:{min:02}")
    } else {
        let (ampm, h12) = if h < 12 {
            (i18n::t("time.am"), h % 12)
        } else {
            (i18n::t("time.pm"), h % 12)
        };
        let h12 = if h12 == 0 { 12 } else { h12 };
        format!("{ampm} {h12}:{min:02}")
    };
    if diff <= 0 {
        format!("{} {time}", i18n::t("group.today"))
    } else if diff == 1 {
        format!("{} {time}", i18n::t("group.yesterday"))
    } else {
        format!("{}/{} {time}", d.get_month() + 1, d.get_date())
    }
}
