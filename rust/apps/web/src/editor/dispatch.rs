//! 桥消息分发与持久化（批 14 二轮自 editor.rs 拆出）：
//! JS 桥消息的统一处理入口（handle_bridge_msg）、持久化
//! 句柄（PersistHandle）与 persist 落盘半边（build_backup
//! 合并总数据 + save_backup_delta 分条增量写 IDB）、桥侧 inputSync 的
//! Diag 节流钟。只做文件组织，行为不变。

use super::*;

/// 历史快照压栈：与栈顶不同才压（截断重做尾，上限 50）。
pub(super) fn perf_now_ms() -> f64 {
    js_sys::Date::now()
}

thread_local! {
    /// 批 4 笔 2：inputSync Diag 节流状态——(上次记行时刻
    /// ms, 累计已应用爆发数)。5s 窗口至多记一行，行内带
    /// 累计数，供探针断言与后续性能定级读取。
    static INPUT_SYNC_DIAG: std::cell::Cell<(f64, u64)> =
        std::cell::Cell::new((0.0, 0));
}

/// 把标题+文档合并进总数据（persist 与离开路径共用）。
/// 一致性守卫（纵深防御）：doc/title 是 Editor 实例的挂载
/// 期状态、只归属其加载 id（state_owner）；写目标 memo_id
/// 与之不一致即拒写、记 Diag 并返回 None——实例身份本由
/// App 槽位键控重挂绑定备忘 id（main.rs），正常路径两者
/// 恒等、守卫永不触发；它拦的是「prop 换 id 而状态未换」
/// 类回归以新 id 写旧内容覆盖目标篇存量的损坏模式（曾实
/// 证）。调用方收到 None 须整笔跳过落盘（离开路径只跳保
/// 存、不拦退出）。目标篇不在 data 中时维持旧口径：合并
/// 无处落点、原样返回（留槽渲染等场景的空写无副作用）。
pub(super) fn build_backup(
    data: Signal<BackupFile>,
    memo_id: &str,
    state_owner: &str,
    doc_snapshot: Vec<Node>,
    title_snapshot: String,
) -> Option<BackupFile> {
    if memo_id != state_owner {
        diag::log(
            "EDIT",
            &format!("persist refused: state owner {state_owner} != target {memo_id}"),
        );
        return None;
    }
    let mut backup = data.read().clone();
    if let Some(m) = backup
        .memos
        .iter_mut()
        .find(|m| m.id.to_string() == memo_id)
    {
        m.title = if title_snapshot.is_empty() {
            None
        } else {
            Some(title_snapshot)
        };
        m.doc = doc_snapshot;
        m.updated_at = moment_core::model::Timestamp(now_iso());
    }
    Some(backup)
}

/// persist 落盘：分条增量写（idb 层记 IDB 结果行）。upsert/
/// delete 为本笔变更的篇目（各至多一篇；纯信封变更如头像
/// 两者皆 None，信封经缓存比对有变才写）。
pub(super) async fn save_backup_delta(
    backup: &BackupFile,
    upsert: Option<&str>,
    delete: Option<&str>,
) {
    if let Err(e) = persist::save_backup_delta(backup, upsert, delete).await {
        diag::log("EDIT", &format!("save err: {e:?}"));
    }
}

type PersistFn = dyn Fn(Vec<Node>, String, Signal<BackupFile>) + 'static;

/// 持久化句柄：包一层以满足 Dioxus 组件 props 的 PartialEq 要求。
#[derive(Clone)]
pub(super) struct PersistHandle(pub(super) std::rc::Rc<PersistFn>);

impl PartialEq for PersistHandle {
    fn eq(&self, other: &Self) -> bool {
        std::rc::Rc::ptr_eq(&self.0, &other.0)
    }
}

impl PersistHandle {
    pub(super) fn call(&self, doc: Vec<Node>, title: String, data: Signal<BackupFile>) {
        (self.0)(doc, title, data)
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn handle_bridge_msg(
    msg: &str,
    memo_id: &str,
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut panel: Signal<Option<(String, String, f64, f64, f64)>>,
    mut link_for: Signal<Option<String>>,
    mut link_pos: Signal<(f64, f64, f64)>,
    mut focus_req: Signal<Option<(String, usize)>>,
    mut dom_set: Signal<Option<(String, String, usize)>>,
    mut md_edit: Signal<Option<String>>,
    mut active_edit: Signal<Option<String>>,
    mut sel_block: Signal<Option<String>>,
    mut manifest: Signal<String>,
    mut hist: Signal<Vec<HistSnap>>,
    mut hist_idx: Signal<usize>,
    mut hist_clock: Signal<(f64, bool)>,
    mut epoch: Signal<u32>,
    mut focus_hint: Signal<Option<(String, usize)>>,
    mut ed_scroll: Signal<f64>,
    mut card_caret: Signal<Option<String>>,
    mut card_menu: Signal<Option<crate::blocks::CardMenuState>>,
    mut card_edit: Signal<Option<String>>,
    mut media_req: Signal<Option<MediaReq>>,
    persist: &PersistHandle,
    layout_sig: Signal<Option<moment_core::MemoLayout>>,
) -> (bool, bool) {
    // 返回 (skip_hist, coalesce)：skip_hist=true = 本条消息已
    // 自行管理历史栈（撤销/重做），消息循环不要再按「文档变
    // 了」自动压栈；coalesce=true = 连续输入类消息，压栈走
    // 600ms 合并（原版 recordUndoPoint 口径）。
    let Ok(v) = serde_json::from_str::<Value>(msg) else {
        diag::log("EDIT", &format!("bad bridge msg: {}", &msg[..msg.len().min(80)]));
        return (false, false);
    };
    let op = v.get("op").and_then(|x| x.as_str()).unwrap_or("");
    let bid = v.get("id").and_then(|x| x.as_str()).unwrap_or("");
    let mut coalesce = false;
    // 最近编辑块（菜单撤销/重做恢复焦点的落点提示）
    if !bid.is_empty() && op != "undo" && op != "redo" {
        focus_hint.set(Some((bid.to_string(), usize::MAX)));
    }
    match op {
        "undo" | "redo" => {
            let sync = v.get("sync").map(|s| s.to_string());
            let off = v.get("off").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let focus = if bid.is_empty() {
                focus_hint.read().clone()
            } else {
                Some((bid.to_string(), off))
            };
            if op == "undo" {
                step_undo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    persist, data, &title, memo_id, sync.as_deref(), focus, layout_sig,
                );
            } else {
                step_redo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    persist, data, &title, memo_id, sync.as_deref(), focus, layout_sig,
                );
            }
            return (true, false);
        }
        "forceTop" => {
            // 失焦回顶（滚动审计 S8）：桥已 scrollTo(0,0)，这里
            // 把滚动量状态压回 0（标题坞回未滚动形态）。桥以
            // 80ms 间隔重发最多 6 次，压住 iOS 异步恢复的滚动。
            if *ed_scroll.read() != 0.0 {
                ed_scroll.set(0.0);
            }
            diag::log_once("force-top", "EDIT", "blur -> force unscrolled (S8)");
        }
        "caretMove" => {
            let dir = v.get("dir").and_then(|x| x.as_str()).unwrap_or("");
            diag::log("EDIT", &format!("caret cross-block {dir} from {bid}"));
        }
        "drag" => {
            // 桥块排序拾起/落位/取消记行：只记日志，状态机
            // 与几何由桥的长按拾起引擎决定。
            let note = v.get("note").and_then(|x| x.as_str()).unwrap_or("");
            diag::log("EDIT", &format!("drag {note}"));
        }
        "canvasFocus" => {
            // 画布空白点按落焦（桥 canvasFocusRoute）：焦点
            // 与选区已由桥内 setCaretEdge 落定，focusin 随后
            // 以 focusBlock 同步 active_edit；此处只记 Diag。
            // via=detailbg 为头部以下 .detail 背景区落焦（用
            // 户 2026-11-23 落焦区域扩展），行尾加 (detailbg)
            // 后缀与画布口径区分。
            let via = v.get("via").and_then(|x| x.as_str()).unwrap_or("");
            if via == "detailbg" {
                diag::log("EDIT", &format!("canvas focus -> {bid} (detailbg)"));
            } else {
                diag::log("EDIT", &format!("canvas focus -> {bid}"));
            }
        }
        "selectBlock" => {
            sel_block.set(Some(bid.to_string()));
        }
        "clearSelect" => {
            if sel_block.read().is_some() {
                sel_block.set(None);
            }
        }
        "cardMenu" => {
            // 卡片浮层菜单打开（桥三路：长按拾起=卡锚、右键=
            // 点锚；悬停钮走上下文直设不经桥）。定位在渲染侧
            // 按锚点与视口钳制（CardMenu 渲染段）。
            let wtype = v.get("wtype").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let anchor = v.get("anchor").and_then(|x| x.as_str()).unwrap_or("card");
            let rf = |i: usize| {
                v.get("rect")
                    .and_then(|r| r.get(i))
                    .and_then(|x| x.as_f64())
                    .unwrap_or(0.0)
            };
            let anchor_point = if anchor == "point" {
                Some((
                    v.get("x").and_then(|x| x.as_f64()).unwrap_or(0.0),
                    v.get("y").and_then(|x| x.as_f64()).unwrap_or(0.0),
                ))
            } else {
                None
            };
            card_menu.set(Some(crate::blocks::CardMenuState {
                bid: bid.to_string(),
                wtype,
                anchor_point,
                rect: (rf(0), rf(1), rf(2), rf(3)),
            }));
            diag::log("EDIT", &format!("card menu open {bid} anchor={anchor}"));
        }
        "cardMenuHide" => {
            if card_menu.read().is_some() {
                card_menu.set(None);
            }
        }
        "cardEditExit" => {
            let cur = card_edit.read().clone();
            if let Some(b) = cur {
                card_edit.set(None);
                diag::log("EDIT", &format!("card edit exit {b}"));
            }
        }
        "cardPick" => {
            // 编辑态点图片区：按 kind 登记媒体请求并唤起系统
            // 选图（set=整卡换图、galleryItem=换画廊单格、
            // galleryAdd=空画廊追加）。
            let kind = v.get("kind").and_then(|x| x.as_str()).unwrap_or("set");
            match kind {
                "galleryItem" => {
                    let ix = v.get("index").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
                    media_req.set(Some(MediaReq::GalleryPick {
                        bid: bid.to_string(),
                        index: Some(ix),
                    }));
                }
                "galleryAdd" => {
                    media_req.set(Some(MediaReq::GalleryPick {
                        bid: bid.to_string(),
                        index: None,
                    }));
                }
                _ => {
                    media_req.set(Some(MediaReq::SetImage { bid: bid.to_string() }));
                }
            }
            spawn(async move {
                let mut eval = document::eval(
                    "const i = document.getElementById('file-media'); if (i) i.click(); dioxus.send(null);",
                );
                let _ = eval.recv::<Value>().await;
            });
            diag::log("EDIT", &format!("card pick {kind} {bid}"));
        }
        "insertPara" => {
            // 原版原子块边缘点击（use-editor-dom.js）：左 28px 在
            // 块前插空段并聚焦；右 28px 聚焦下一个可编辑兄弟，
            // 没有才在块后插空段。批 1 B-13 起卡片类右 15% 区
            // 带 kind=card 单独标记：原版卡片右区的动作是恒在
            // 卡后新插一段并聚焦（「新增一行」），不走附件的
            // 聚焦既有下一段口径——否则区虽命中、落段行为仍
            // 与原版分叉（宽卡右区点完只跳焦点不新增行）。
            let where_ = v.get("where").and_then(|x| x.as_str()).unwrap_or("before");
            let card_zone = v.get("kind").and_then(|x| x.as_str()) == Some("card");
            let mut d = doc.read().clone();
            if let Some(Loc::Top(i)) = find_loc(&d, bid) {
                sel_block.set(None);
                if where_ == "after" && card_zone {
                    let para = new_block("paragraph");
                    let pid = para.id.clone().unwrap_or_default();
                    d.insert(i + 1, para);
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                    focus_req.set(Some((pid, 0)));
                    diag::log("EDIT", &format!("insert para after card {bid}"));
                } else if where_ == "after" {
                    let next_ed = ((i + 1)..d.len()).find(|&j| {
                        matches!(
                            d[j].block_type().unwrap_or(""),
                            "paragraph" | "heading" | "quote" | "todo"
                        )
                    });
                    if let Some(j) = next_ed {
                        let nid = d[j].id.clone().unwrap_or_default();
                        focus_req.set(Some((nid, 0)));
                    } else {
                        let para = new_block("paragraph");
                        let pid = para.id.clone().unwrap_or_default();
                        d.insert(i + 1, para);
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        focus_req.set(Some((pid, 0)));
                        diag::log("EDIT", &format!("insert para after {bid}"));
                    }
                } else {
                    let para = new_block("paragraph");
                    let pid = para.id.clone().unwrap_or_default();
                    d.insert(i, para);
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                    focus_req.set(Some((pid, 0)));
                    diag::log("EDIT", &format!("insert para before {bid}"));
                }
            }
        }
        "split" => {
            let before = v.get("before").and_then(|x| x.as_str()).unwrap_or("");
            let after = v.get("after").and_then(|x| x.as_str()).unwrap_or("");
            op_split(&mut doc, bid, before, after, &mut focus_req, &mut dom_set);
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "merge" => {
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            op_merge(&mut doc, bid, html, &mut focus_req, &mut dom_set, &mut sel_block);
            // 被合并掉的块若正处 md 源码编辑态，编辑态一并清掉
            if md_edit.read().as_deref() == Some(bid) {
                md_edit.set(None);
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "mergeForward" => {
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            op_merge_forward(&mut doc, bid, html, &mut focus_req, &mut dom_set, &mut sel_block);
            // 被并掉的下一块若正处 md 源码编辑态，其块已消
            // 失，编辑态一并清掉（merge 臂对 bid 的同口径推
            // 广：按存亡核对，不预设被删块 id）
            let stale_md = match md_edit.read().clone() {
                Some(mid) => find_loc(&doc.read(), &mid).is_none(),
                None => false,
            };
            if stale_md {
                md_edit.set(None);
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "replaceRange" => {
            let a_bid = v.get("aBid").and_then(|x| x.as_str()).unwrap_or("");
            let a_off = v.get("aOff").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let f_bid = v.get("fBid").and_then(|x| x.as_str()).unwrap_or("");
            let f_off = v.get("fOff").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            let enter = v.get("enter").and_then(|x| x.as_bool()).unwrap_or(false);
            let from_start = v.get("fromStart").and_then(|x| x.as_bool()).unwrap_or(false);
            let to_end = v.get("toEnd").and_then(|x| x.as_bool()).unwrap_or(false);
            let sync = v.get("sync").map(|s| s.to_string());
            op_replace_range(
                &mut doc,
                a_bid,
                a_off,
                f_bid,
                f_off,
                text,
                enter,
                from_start,
                to_end,
                sync.as_deref(),
                &mut focus_req,
                &mut dom_set,
            );
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "moveBlock" => {
            let ids: Vec<String> = v
                .get("ids")
                .and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|x| x.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            let to = v.get("to").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            let sync = v.get("sync").map(|s| s.to_string());
            op_move_block(
                &mut doc,
                data,
                memo_id,
                &title,
                &ids,
                to,
                sync.as_deref(),
                persist,
                layout_sig,
            );
        }
        "slash" => {
            let filter = v.get("filter").and_then(|x| x.as_str()).unwrap_or("");
            let x = v.get("x").and_then(|x| x.as_f64()).unwrap_or(20.0);
            let top = v.get("y").and_then(|x| x.as_f64()).unwrap_or(160.0);
            let bottom = v.get("b").and_then(|x| x.as_f64()).unwrap_or(200.0);
            panel.set(Some((bid.to_string(), filter.to_string(), x, top, bottom)));
        }
        "slashPos" => {
            // 跟随重锚（桥 slashPos，rAF 节流 + 选区守卫后发）：
            // 只更新坐标——面板为该 bid 开着则更新 panel 锚，
            // 链接表单为该 bid 则更新 link_pos；已关/换块
            // no-op。坐标真变化才记 Diag。
            let x = v.get("x").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let top = v.get("y").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let bottom = v.get("b").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let moved = |ox: f64, ot: f64, ob: f64| {
                (x - ox).abs() > 0.5 || (top - ot).abs() > 0.5 || (bottom - ob).abs() > 0.5
            };
            let cur = panel.read().clone();
            if let Some((pbid, pfilter, ox, ot, ob)) = cur {
                if pbid == bid && moved(ox, ot, ob) {
                    panel.set(Some((pbid, pfilter, x, top, bottom)));
                    diag::log("EDIT", &format!("slash reposition {bid}"));
                }
            } else if link_for.read().as_deref() == Some(bid) {
                let (ox, ot, ob) = *link_pos.read();
                if moved(ox, ot, ob) {
                    link_pos.set((x, top, bottom));
                    diag::log("EDIT", &format!("slash reposition link {bid}"));
                }
            }
        }
        "slashLink" => {
            // 链接命令：面板切换为链接表单（斜杠字符留在块里，
            // 插入时由 __mnApplyLink 前的 __mnStripSlash 清掉）
            if let Some((_, _, x, top, bottom)) = panel.read().clone() {
                link_pos.set((x, top, bottom));
            }
            panel.set(None);
            link_for.set(Some(bid.to_string()));
        }
        "slashClose" => panel.set(None),
        "slashApply" => {
            let act = v.get("act").and_then(|x| x.as_str()).unwrap_or("");
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            // D-11：桥随消息带回的令牌起点（转换落点用）
            let pos = v.get("pos").and_then(|x| x.as_u64()).unwrap_or(0) as usize;
            panel.set(None);
            if act == "image" || act == "gallery" {
                // 占位块路径（S4）：桥已 strip 掉令牌，但整块将被
                // 占位块替换，html 不再使用
                op_insert_media_placeholder(&mut doc, bid, act == "gallery", &mut focus_req);
            } else if let Some((src, off)) =
                op_convert(&mut doc, bid, act, html, pos, &mut focus_req, &mut md_edit)
            {
                let esc = src
                    .replace('&', "&amp;")
                    .replace('<', "&lt;")
                    .replace('>', "&gt;")
                    .replace('\n', "<br>");
                dom_set.set(Some((bid.to_string(), esc, off)));
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "mdText" => {
            // md 源编辑：整块文本就是源码，单文本节点落模型。
            // 逐键消息 = 连续输入，压栈走 600ms 合并。
            coalesce = true;
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            let text = text.trim_end_matches('\n').to_string();
            let mut d = doc.read().clone();
            if let Some(loc) = find_loc(&d, bid) {
                let n = node_at_mut(&mut d, loc);
                n.children = Some(vec![text_node(&text)]);
                doc.set(d);
            }
        }
        "mdDone" => {
            if md_edit.read().as_deref() == Some(bid) {
                md_edit.set(None);
                persist.call(doc.read().clone(), title.read().clone(), data);
                diag::log("EDIT", &format!("md source done {bid}"));
            }
        }
        "focusBlock" => {
            if active_edit.read().as_deref() != Some(bid) {
                active_edit.set(Some(bid.to_string()));
            }
        }
        "blurBlock" => {
            if active_edit.read().as_deref() == Some(bid) {
                active_edit.set(None);
            }
        }
        "pasteSync" => {
            // 富文本粘贴已由 JS 插入 DOM，这里只对齐模型。
            // 来源含打字路径（实时高亮/软换行/粘贴落位），按
            // 连续输入走 600ms 合并压栈。
            coalesce = true;
            let html = v.get("html").and_then(|x| x.as_str()).unwrap_or("");
            let mut d = doc.read().clone();
            if let Some(loc) = find_loc(&d, bid) {
                node_at_mut(&mut d, loc).children = Some(editor_html_to_inlines(html));
                doc.set(d);
                diag::log("EDIT", &format!("paste html synced {bid}"));
                if html.contains("<mark") {
                    diag::log("EDIT", &format!("highlight mark synced {bid}"));
                }
            } else {
                diag::log("EDIT", &format!("pasteSync: block not found {bid}"));
            }
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "pasteText" => {
            let before = v.get("before").and_then(|x| x.as_str()).unwrap_or("");
            let after = v.get("after").and_then(|x| x.as_str()).unwrap_or("");
            let lines: Vec<String> = v
                .get("lines")
                .and_then(|x| x.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|x| x.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            op_paste_text(&mut doc, bid, before, after, &lines, &mut focus_req, &mut dom_set);
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
        "pasteCard" => {
            let url = v.get("url").and_then(|x| x.as_str()).unwrap_or("");
            let remain = v.get("remain").and_then(|x| x.as_str()).unwrap_or("");
            let before = v.get("before").and_then(|x| x.as_str()).unwrap_or("");
            let after = v.get("after").and_then(|x| x.as_str()).unwrap_or("");
            if let Some(card_id) =
                op_paste_card(&mut doc, bid, url, remain, before, after, &mut focus_req)
            {
                persist.call(doc.read().clone(), title.read().clone(), data);
                spawn_resolve_card(doc, card_id, url.to_string(), title, data, persist.clone(), None, None);
                diag::log("EDIT", &format!("pasteCard {url} remain={}", remain.len()));
            }
        }
        "musicInput" => {
            // 音乐输入胶囊的粘贴/输入/回车复检：提出 URL 才
            // 转 loading 并解析（op_music_input 内含状态守卫
            // 与全套 Diag）；无 URL 时无动作、不落盘。via 标
            // 记来源（批 1 B-9：direct=胶囊本尊粘贴/输入、
            // paste-divert=engaged 时错位粘贴在 paste 阶段
            // 分流、paste-recover=原生落地后 input 阶段 diff
            // 回收），供 Diag 区分三路。
            let via = v.get("via").and_then(|x| x.as_str()).unwrap_or("");
            if !via.is_empty() {
                diag::log("EDIT", &format!("musicInput via {via} bid={bid}"));
            }
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            op_music_input(
                &mut doc,
                bid,
                text,
                &mut card_caret,
                &mut focus_req,
                title,
                data,
                persist,
            );
        }
        "musicFocusPrev" => {
            // 音乐胶囊段首退格收口（K4）：不删块，仅把焦点移
            // 回上一个可编辑单元末尾；无上一单元则无操作。胶
            // 囊保留，删除走卡片菜单明路。
            let d = doc.read().clone();
            if let Some(Loc::Top(i)) = find_loc(&d, bid) {
                let units = editable_units(&d);
                let prev = units.iter().rev().find(|u| match u {
                    Loc::Top(t) => *t < i,
                    Loc::Item(li, _) => *li < i,
                });
                if let Some(pu) = prev {
                    let n = node_at(&d, *pu);
                    let pid = n.id.clone().unwrap_or_default();
                    if !pid.is_empty() {
                        focus_req.set(Some((pid.clone(), plain_len(n))));
                        diag::log(
                            "EDIT",
                            &format!("music input backspace -> focus prev {pid}"),
                        );
                    }
                }
            }
        }
        "musicFocusNext" => {
            // 音乐胶囊块末前向删除收口（K4 镜像）：不删块，
            // 仅把焦点移到下一个可编辑单元块首；无下一单元
            // 则无操作。胶囊保留，删除走卡片菜单明路。
            let d = doc.read().clone();
            if let Some(Loc::Top(i)) = find_loc(&d, bid) {
                let units = editable_units(&d);
                let next = units.iter().find(|u| match u {
                    Loc::Top(t) => *t > i,
                    Loc::Item(li, _) => *li > i,
                });
                if let Some(nu) = next {
                    let n = node_at(&d, *nu);
                    let pid = n.id.clone().unwrap_or_default();
                    if !pid.is_empty() {
                        focus_req.set(Some((pid.clone(), 0)));
                        diag::log(
                            "EDIT",
                            &format!("music input delete -> focus next {pid}"),
                        );
                    }
                }
            }
        }
        "pasteImage" => {
            let name = v
                .get("name")
                .and_then(|x| x.as_str())
                .unwrap_or("image.png")
                .to_string();
            let mime = v
                .get("mime")
                .and_then(|x| x.as_str())
                .unwrap_or("image/png")
                .to_string();
            let b64 = v.get("b64").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let bid_owned = bid.to_string();
            let persist2 = persist.clone();
            spawn(async move {
                let bytes = b64_decode(&b64);
                if bytes.is_empty() {
                    diag::log("EDIT", "pasteImage: empty bytes");
                    return;
                }
                let fid = gen_id();
                if persist::put_attachment(&fid, &bytes).await.is_err() {
                    diag::log("EDIT", "pasteImage: idb put failed");
                    return;
                }
                let mut man: Value = serde_json::from_str(&manifest.read())
                    .unwrap_or_else(|_| json!({"version": 1}));
                if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
                    man["attachments"] = json!({});
                }
                man["attachments"][&fid] = json!({"name": name, "type": mime});
                let man_str = man.to_string();
                manifest.set(man_str.clone());
                let _ = persist::save_manifest(&man_str).await;
                let mut d = doc.read().clone();
                if let Some(loc) = find_loc(&d, &bid_owned) {
                    let top = match loc {
                        Loc::Top(i) => i,
                        Loc::Item(li, _) => li,
                    };
                    let node = Node {
                        node_type: Some("image".to_string()),
                        id: Some(gen_id()),
                        children: Some(vec![]),
                        attrs: moment_core::Attrs {
                            file_id: Some(fid.clone()),
                            ..Default::default()
                        },
                        ..Default::default()
                    };
                    d.insert(top + 1, node);
                    doc.set(d.clone());
                    persist2.call(d, title.read().clone(), data);
                    diag::log("EDIT", &format!("pasteImage {fid} {}B", bytes.len()));
                }
            });
        }
        "inputSync" => {
            // 批 4 B-4：打字 80ms 防抖增量同步（桥
            // scheduleInputSync 只带真打过字的块）——落真
            // doc 信号，消息循环按 coalesce=true 压栈
            // （600ms 爆发合并）；无变化则整条 no-op（不
            // set、不落盘），避免无谓重渲染与写盘。20s
            // sync 自此退兜底（其影子比对恒无变化）。编
            // 辑态块为非受控渲染（EditableDiv 初始 HTML
            // use_hook 锁定），doc.set 不回写活 DOM。
            coalesce = true;
            if let Some(map) = v.get("map") {
                let n_blocks = map.as_object().map(|o| o.len()).unwrap_or(0);
                let map_str = map.to_string();
                let before_json = serde_json::to_string(&*doc.read()).unwrap_or_default();
                let mut d = doc.read().clone();
                apply_sync_map(&mut d, &map_str);
                if serde_json::to_string(&d).unwrap_or_default() != before_json {
                    doc.set(d);
                    persist.call(doc.read().clone(), title.read().clone(), data);
                    // Diag 节流行（批 4 笔 2）：真实落模型
                    // 才计数，5s 窗口至多一行。
                    INPUT_SYNC_DIAG.with(|c| {
                        let (last, total) = c.get();
                        let total = total + 1;
                        let now = perf_now_ms();
                        if now - last >= 5000.0 {
                            diag::log(
                                "EDIT",
                                &format!("input sync applied ({n_blocks} blocks, total {total})"),
                            );
                            c.set((now, total));
                        } else {
                            c.set((last, total));
                        }
                    });
                }
            }
        }
        "sync" => {
            // 兜底自动同步（批 4 后口径）：只更新持久副本，
            // 不动正在编辑的 doc 信号；打字主通道是 inputSync
            if let Some(map) = v.get("map") {
                let map_str = map.to_string();
                let mut shadow = doc.read().clone();
                let before_json = serde_json::to_string(&shadow).unwrap_or_default();
                apply_sync_map(&mut shadow, &map_str);
                if serde_json::to_string(&shadow).unwrap_or_default() != before_json {
                    persist.call(shadow, title.read().clone(), data);
                    diag::log_once("autosync", "EDIT", "autosync applied");
                }
            }
        }
        _ => diag::log("EDIT", &format!("unknown op: {op}")),
    }
    // 智能前缀扫描（原版在输入防抖尾部跑：文本落模型后扫
    // 全 doc 转首个命中段落）。挂在文本类消息（打字同步/
    // md 源输入/拆分/合并/粘贴文本）落定之后、同一消息内
    // 完成——与原版同属一个撤销步（消息循环按本消息前后
    // JSON 压栈）。斜杠面板/链接表单打开时跳过（原版
    // showSlash 守卫）。转换块若正处 md 源码编辑态则编辑
    // 态失效；转换改了块文本，非受控 DOM 不会自己重渲染，
    // 按 slashApply 同口径用 dom_set 把新内容回写活 DOM 并
    // 落光标（__mnSetHtml）；焦点以转换落点为准（原版转换
    // 后 focusEditableWithCaret 覆盖此前落点）。
    if matches!(
        op,
        "pasteSync" | "mdText" | "split" | "merge" | "mergeForward" | "pasteText" | "inputSync"
    )
        && panel.read().is_none()
        && link_for.read().is_none()
    {
        if let Some((cid, fid, coff, dom_html)) = apply_smart_prefix(&mut doc) {
            if md_edit.read().as_deref() == Some(cid.as_str()) {
                md_edit.set(None);
            }
            if let Some(html) = dom_html {
                dom_set.set(Some((cid, html, coff)));
            }
            focus_req.set(Some((fid, coff)));
            persist.call(doc.read().clone(), title.read().clone(), data);
        }
    }
    (false, coalesce)
}
