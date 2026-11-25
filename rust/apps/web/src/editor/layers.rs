//! 浮层渲染组（批 14 二轮自 editor.rs 拆出）：Editor 的
//! 页头坞（头像 + 标题胶囊）、卡片浮层菜单、编辑菜单层
//! （含导出面板）、背景色底表、图文全文底表五个 rsx 段
//! 拆为子组件——段内计算与 handler 闭包随段迁入，信号
//! 经 props 原样穿线，渲染输出与求值口径不变。rsx 段保
//! 持拆分前的缩进（逐字搬移，不做重排）。

use super::*;

/// 页头坞：返回/菜单 fab 之间的头像钮 + 标题胶囊行。
#[component]
pub(super) fn TitleDock(
    memo_id: String,
    initial_title: String,
    meta_line: String,
    scrolled: bool,
    avatar_state: Option<String>,
    avatar_url: Signal<Option<String>>,
    data: Signal<BackupFile>,
    title_commit: EventHandler<String>,
    title_session: EventHandler<bool>,
) -> Element {
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
    rsx! {
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
    }
}

/// 卡片浮层菜单（长按/右键）：定位视图计算 + 菜单面板。
#[component]
pub(super) fn CardMenuLayer(
    card_menu: Signal<Option<crate::blocks::CardMenuState>>,
    card_edit: Signal<Option<String>>,
    sel_block: Signal<Option<String>>,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
) -> Element {
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
    if let Some((cm_style, cm_has_edit)) = card_menu_view.clone() {
        rsx! {
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
                                                            n.url = Some(url.clone());
                                                            n.meta = Some(serde_json::Value::Null);
                                                            n.status = Some("loading".to_string());
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
    } else {
        rsx! {}
    }
}

/// 编辑菜单层：遮罩 + 导出面板 / 菜单面板（二选一）。
#[component]
#[allow(clippy::too_many_arguments)]
pub(super) fn MenuLayer(
    memo_id: String,
    memo_updated: mynote_core::model::Timestamp,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    manifest: Signal<String>,
    persist: PersistHandle,
    menu_open: Signal<bool>,
    menu_closing: Signal<bool>,
    menu_gen: Signal<u32>,
    show_export: Signal<bool>,
    export_closing: Signal<bool>,
    export_gen: Signal<u32>,
    export_anim: Signal<u8>,
    export_to_menu: Signal<bool>,
    bg_open: Signal<bool>,
    twopane: Signal<bool>,
    hist: Signal<Vec<HistSnap>>,
    hist_idx: Signal<usize>,
    hist_clock: Signal<(f64, bool)>,
    epoch: Signal<u32>,
    avatar_url: Signal<Option<String>>,
    bg: Signal<Option<String>>,
    focus_req: Signal<Option<(String, usize)>>,
    focus_hint: Signal<Option<(String, usize)>>,
    ed_msg: Signal<String>,
    ed_seq: Signal<u64>,
    ed_kind: Signal<&'static str>,
) -> Element {
    let ed_status = crate::settings::Toast {
        msg: ed_msg,
        seq: ed_seq,
        kind: ed_kind,
        tag: "EDIT",
    };
    let menu_state = *menu_open.read();
    let menu_closing_state = *menu_closing.read();
    let export_open = *show_export.read();
    let export_is_closing = *export_closing.read();
    // 全关关闭中（遮挡续修）：命中即刻释放——遮罩在卸载
    // 计时落定前不再拦截点按，计时停摆也锁不住页面；回
    // 菜单的关闭不释放（菜单仍在场，遮罩归菜单所有）。
    let export_releasing = export_is_closing
        && *export_anim.read() == EXPORT_ANIM_CLOSING
        && !*export_to_menu.read();
    let can_undo = *hist_idx.read() > 0;
    let can_redo = *hist_idx.read() + 1 < hist.read().len();
    let twopane_state = *twopane.read();
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
                let b = column_boundary(&d, m.layout.as_ref());
                let ids: Vec<String> = d
                    .iter()
                    .map(|n| n.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
                    .collect();
                let (left, right) = ids.split_at(b.min(ids.len()));
                m.layout = Some(mynote_core::MemoLayout {
                    version: Some(1),
                    mode: Some(if next { "independent" } else { "flow" }.to_string()),
                    left: Some(left.to_vec()),
                    right: Some(right.to_vec()),
                });
            }
            data.set(backup.clone());
            diag::log("EDIT", &format!("twopane -> {next}"));
            spawn(async move {
                save_backup(&backup).await;
            });
        }
    };
    // 导出 HTML / PDF（原版导出面板的另两条路径）
    let export_html = {
        let memo_id = memo_id.clone();
        let memo_upd_ts = memo_updated.clone();
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
        let memo_upd_ts = memo_updated.clone();
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
    if menu_state {
        rsx! {
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
    } else {
        rsx! {}
    }
}

/// 背景色底表：遮罩 + 色点网格 + 移除行。
#[component]
pub(super) fn BgSheetLayer(
    bg_open: Signal<bool>,
    bg_closing: Signal<bool>,
    bg_gen: Signal<u32>,
    bg: Signal<Option<String>>,
    bg_state: Option<String>,
    data: Signal<BackupFile>,
    memo_id: String,
) -> Element {
    let bg_sheet_state = *bg_open.read();
    let bg_closing_state = *bg_closing.read();
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
    if bg_sheet_state {
        rsx! {
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
    } else {
        rsx! {}
    }
}

/// 图文全文底表：遮罩 + 阅读/编辑面板。
#[component]
pub(super) fn TextSheetLayer(
    text_sheet: Signal<Option<(String, String)>>,
    text_sheet_closing: Signal<bool>,
    text_sheet_gen: Signal<u32>,
    sheet_edit: Signal<bool>,
    sheet_draft: Signal<String>,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
) -> Element {
    let sheet_state = text_sheet.read().clone();
    let sheet_closing_state = *text_sheet_closing.read();
    let sheet_editing = *sheet_edit.read();
    if let Some((bid, _txt)) = sheet_state {
        rsx! {
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
    } else {
        rsx! {}
    }
}
