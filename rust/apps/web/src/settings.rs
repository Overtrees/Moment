//! 设置与备份页（对齐原版 components/SettingsView.js、
//! BackupView.js 的文件分工）：设置页、备份页与导入/导出处理。

use dioxus::prelude::*;
use mynote_core::{read_backup_zip, write_backup_zip, BackupFile};
use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

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
    rsx! {
        div { class: "page-enter", style: "background:var(--primary-bg);min-height:100vh;",
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
            div { class: "page-content",
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

/// 备份页（原版 BackupView 复刻）：状态总览 hero + 本地备份卡
/// （导出/导入，带确认弹窗）+ Google Drive 卡（未连接态；
/// 云备份方案待定）+ 最近操作。
#[component]
pub(crate) fn BackupView(
    data: Signal<BackupFile>,
    manifest: Signal<String>,
    mut status: Signal<String>,
    gen: Signal<u32>,
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
    // 「上次备份」口径对齐原版 BackupView.js:83-110：从历史中
    // 取最近一条 type=upload 且成功的时间并格式化（今天/昨天
    // HH:MM 或 M/D HH:MM）；本地导出不算备份，未上传过即「暂无」。
    // 此前用独立 localStorage 键存原始 ISO 串且本地导出即更新，
    // 格式与口径双差。
    let last_backup = history
        .iter()
        .find(|h| {
            h.get("type").and_then(|v| v.as_str()) == Some("upload")
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
        div { class: "page-enter", style: "background:var(--primary-bg);min-height:100vh;",
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
            div { class: "page-content",
                div { class: "backup-hero",
                    div { class: "backup-hero-top",
                        div { class: "backup-hero-title", "{i18n::t(\"backup.hero_title\")}" }
                        div { class: "backup-hero-badge disconnected", "{i18n::t(\"backup.disconnected\")}" }
                    }
                    div { class: "backup-desc",
                        span { "☁️ Google Drive {i18n::t(\"backup.disconnected\")}" }
                        span { style: "opacity:0.3;", "·" }
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
                                    if let Some((name, bytes)) = pick_file_bytes().await {
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
                div { class: "backup-card",
                    div { class: "backup-row",
                        div { class: "backup-row-left",
                            div { class: "backup-row-title", "{i18n::t(\"backup.drive_title\")}" }
                            div { class: "backup-row-desc", "{i18n::t(\"backup.drive_desc\")}" }
                        }
                        div { class: "backup-state disconnected", "{i18n::t(\"backup.disconnected\")}" }
                    }
                    div { class: "backup-action-bar",
                        button {
                            class: "backup-btn primary",
                            onclick: move |_| {
                                diag::log("BACKUP", "drive connect tapped (pending)");
                                toast.show("info", i18n::t("backup.drive_pending"));
                            },
                            "{i18n::t(\"backup.connect_google\")}"
                        }
                    }
                }
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
                                    "upload" => i18n::t("backup.kind_upload"),
                                    "export" => i18n::t("backup.kind_export"),
                                    "restore" => i18n::t("backup.kind_restore"),
                                    _ => i18n::t("backup.kind_connect"),
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
            // 原版口径：优先系统分享面板，不支持/失败才回退
            // 下载；用户在分享面板取消则两者都不做。
            // 注：本地导出不更新「上次备份」（原版仅云端上传
            // 成功才更新，见 BackupView 的 last_backup 推导）。
            let filename = export_filename();
            match try_share_zip(&bytes, &filename).await {
                ShareOutcome::Shared => {
                    // 原版条目：message「文件已分享」+ detail 文件名
                    push_history("export", true, &i18n::t("status.shared"), &filename);
                    toast.show("success", i18n::t("status.shared"));
                }
                ShareOutcome::Cancelled => {
                    diag::log("EXPORT", "share cancelled by user");
                }
                ShareOutcome::Fallback => {
                    download_zip(&bytes, &filename);
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

/// 读导入文件：返回 (文件名, 字节)。文件名供历史条目 detail
/// （原版 restore 条目 detail = file.name）。
async fn pick_file_bytes() -> Option<(String, Vec<u8>)> {
    let window = web_sys::window()?;
    let doc = window.document()?;
    let input: web_sys::HtmlInputElement = doc.get_element_by_id("file-import")?.dyn_into().ok()?;
    let file = input.files()?.get(0)?;
    let name = file.name();
    let buf = JsFuture::from(file.array_buffer()).await.ok()?;
    let arr = js_sys::Uint8Array::new(&buf);
    let bytes = arr.to_vec();
    input.set_value("");
    Some((name, bytes))
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

enum ShareOutcome {
    Shared,
    Cancelled,
    Fallback,
}

/// 系统分享：字节 → Blob URL → JS fetch 转 File → canShare
/// 判定 → navigator.share。返回 shared/cancelled/fallback。
async fn try_share_zip(bytes: &[u8], filename: &str) -> ShareOutcome {
    let Some(window) = web_sys::window() else {
        return ShareOutcome::Fallback;
    };
    let Some(_doc) = window.document() else {
        return ShareOutcome::Fallback;
    };
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::BlobPropertyBag::new();
    opts.set_type("application/zip");
    let Ok(blob) = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &opts) else {
        return ShareOutcome::Fallback;
    };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(&blob) else {
        return ShareOutcome::Fallback;
    };
    let fname_js = serde_json::to_string(filename).unwrap_or_else(|_| "\"backup.zip\"".to_string());
    let js = format!(
        "(async () => {{ try {{ if (!navigator.share || !navigator.canShare) {{ dioxus.send('fallback'); return; }} const r = await fetch('{url}'); const b = await r.blob(); const f = new File([b], {fname_js}, {{ type: 'application/zip' }}); if (!navigator.canShare({{ files: [f] }})) {{ dioxus.send('fallback'); return; }} await navigator.share({{ files: [f] }}); dioxus.send('shared'); }} catch (e) {{ dioxus.send(e && e.name === 'AbortError' ? 'cancelled' : 'fallback'); }} }})();"
    );
    let mut eval = dioxus::document::eval(&js);
    let outcome = match eval.recv::<String>().await {
        Ok(v) if v == "shared" => ShareOutcome::Shared,
        Ok(v) if v == "cancelled" => ShareOutcome::Cancelled,
        _ => ShareOutcome::Fallback,
    };
    let _ = web_sys::Url::revoke_object_url(&url);
    outcome
}

fn download_zip(bytes: &[u8], filename: &str) {
    let Some(window) = web_sys::window() else { return };
    let Some(doc) = window.document() else { return };
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::BlobPropertyBag::new();
    opts.set_type("application/zip");
    let Ok(blob) = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &opts) else {
        return;
    };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(&blob) else {
        return;
    };
    if let Ok(el) = doc.create_element("a") {
        let a: web_sys::HtmlAnchorElement = el.unchecked_into();
        a.set_href(&url);
        a.set_download(filename);
        a.click();
    }
    let _ = web_sys::Url::revoke_object_url(&url);
}
