//! W2 块编辑器：DOM contenteditable（每块一个，非受控——初始
//! HTML 只写一次，之后的键入完全归浏览器，Dioxus 重渲染不碰
//! 已挂载块的内容）+ JS 桥（回车分块/退格合并/斜杠面板/自动
//! 同步的事件采集与光标数学）+ Rust 侧模型操作（core 的行内
//! HTML 桥做 DOM⇄模型转换）。
//!
//! 拼音安全要点：组合输入期间 JS 桥不拦截任何按键（回车确认
//! 候选词不会被误判为分块）；结构操作的消息都自带块的当前
//! HTML，模型永远以 DOM 为准对齐。
//!
//! 子模块分工：bridge（JS 桥与卸载清理）、cards（链接/音乐
//! 卡解析与音乐输入胶囊）、columns（双栏分界）、export（导
//! 出全链）、title（标题显示口径与静态壳）、title_controller
//! （标题编辑会话的唯一所有者）；本文件留编辑器主体、模型
//! 操作与块渲染。

use dioxus::prelude::*;
use mynote_core::{
    editor_html_to_inlines, inlines_to_editor_html, inlines_to_html, BackupFile, Node,
};
use serde_json::{json, Map, Value};

use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

use crate::blocks::BlockView;
use crate::diag;
use crate::idb;
use crate::{DimLayer, DimStack};

mod bridge;
mod cards;
mod columns;
mod export;
mod title;
mod title_controller;

use bridge::{sync_editor_cleanup, EDITOR_JS};
use export::{
    animate_export_close, begin_export_open, collect_export_assets, collect_export_files,
    doc_to_html, download_text, export_char_count, export_filename, memo_to_markdown,
    settle_export_on_resume, time_label, EXPORT_ANIM_CLOSING, EXPORT_ANIM_IDLE,
};
use cards::{op_music_input, spawn_resolve_card};
use columns::{canonical_boundary, column_boundary, normalize_boundary};
use title::{blur_title_if_focused, TitleCapsule};

/// 动作 / 图标名 / 标题键 / 副标题键 / 快捷键标记 / 分组
/// （0 基础、1 媒体）。行内命令（bold 等）由 JS 桥就地执行。
struct SlashCmd {
    act: &'static str,
    /// 原版 commands.js 的 id（最近使用按它存 localStorage）
    oid: &'static str,
    /// 原版 commands.js 的 type（过滤 haystack 的一员，
    /// 原版 slash-model.js 口径：title+sub+kw+type+拼音）
    ty: &'static str,
    icon: &'static str,
    title: &'static str,
    sub: &'static str,
    shortcut: &'static str,
    group: u8,
    /// 原版 keywords（搜索全集的一部分，含中文词）
    kw: &'static str,
    /// 原版 pinyin 首字母
    py: &'static str,
}
const SLASH_CMDS: &[SlashCmd] = &[
    SlashCmd { act: "heading1", icon: "heading", title: "slash.heading1", sub: "slash.heading1_sub", shortcut: "# ", group: 0, oid: "heading", ty: "heading", kw: "h1 heading 标题 一级", py: "bt1" },
    SlashCmd { act: "heading2", icon: "heading2", title: "slash.heading2", sub: "slash.heading2_sub", shortcut: "## ", group: 0, oid: "heading2", ty: "heading", kw: "h2 heading2 标题 二级", py: "bt2" },
    SlashCmd { act: "heading3", icon: "heading3", title: "slash.heading3", sub: "slash.heading3_sub", shortcut: "### ", group: 0, oid: "heading3", ty: "heading", kw: "h3 heading3 标题 三级", py: "bt3" },
    SlashCmd { act: "paragraph", icon: "paragraph", title: "slash.paragraph", sub: "slash.paragraph_sub", shortcut: "", group: 0, oid: "paragraph", ty: "paragraph", kw: "p paragraph 文本", py: "wb" },
    SlashCmd { act: "quote", icon: "quote", title: "slash.quote", sub: "slash.quote_sub", shortcut: "> ", group: 0, oid: "quote", ty: "quote", kw: "q quote 引用", py: "yy" },
    SlashCmd { act: "todo", icon: "todo", title: "slash.todo", sub: "slash.todo_sub", shortcut: "[ ] ", group: 0, oid: "todo", ty: "todo", kw: "t todo 待办", py: "db" },
    SlashCmd { act: "divider", icon: "divider", title: "slash.divider", sub: "slash.divider_sub", shortcut: "---", group: 0, oid: "divider", ty: "divider", kw: "d divider 分割线", py: "fgx" },
    SlashCmd { act: "bold", icon: "bold", title: "slash.bold", sub: "slash.bold_sub", shortcut: "** **", group: 0, oid: "bold", ty: "inline_bold", kw: "b bold 加粗 粗体", py: "jc" },
    SlashCmd { act: "italic", icon: "italic", title: "slash.italic", sub: "slash.italic_sub", shortcut: "* *", group: 0, oid: "italic", ty: "inline_italic", kw: "i italic 斜体 倾斜", py: "xt" },
    SlashCmd { act: "highlight", icon: "highlight", title: "slash.highlight", sub: "slash.highlight_sub", shortcut: "== ==", group: 0, oid: "highlight", ty: "inline_highlight", kw: "h highlight 高亮", py: "gl" },
    SlashCmd { act: "codeBlock", icon: "codeBlock", title: "slash.code_block", sub: "slash.code_block_sub", shortcut: "```", group: 0, oid: "codeBlock", ty: "code_block", kw: "code codeblock 代码块", py: "dmk" },
    SlashCmd { act: "bulletList", icon: "list", title: "slash.bullet_list", sub: "slash.bullet_list_sub", shortcut: "- ", group: 0, oid: "unorderedList", ty: "unordered_list", kw: "list ul 无序列表 列表", py: "wxl" },
    SlashCmd { act: "numberList", icon: "olist", title: "slash.number_list", sub: "slash.number_list_sub", shortcut: "1. ", group: 0, oid: "orderedList", ty: "ordered_list", kw: "ol list 有序列表 列表", py: "yxl" },
    SlashCmd { act: "callout", icon: "callout", title: "slash.callout", sub: "slash.callout_sub", shortcut: "> [!]", group: 0, oid: "callout", ty: "callout", kw: "callout note tip warning 提示 警告", py: "callout" },
    SlashCmd { act: "link", icon: "link", title: "slash.link", sub: "slash.link_sub", shortcut: "[](url)", group: 0, oid: "link", ty: "inline_link", kw: "l link 链接 超链接", py: "lj" },
    SlashCmd { act: "code", icon: "code", title: "slash.code", sub: "slash.code_sub", shortcut: "` `", group: 0, oid: "code", ty: "inline_code", kw: "c code 代码 内联", py: "dm" },
    SlashCmd { act: "strikethrough", icon: "strikethrough", title: "slash.strikethrough", sub: "slash.strikethrough_sub", shortcut: "~~ ~~", group: 0, oid: "strikethrough", ty: "inline_strike", kw: "s strike strikethrough 删除线", py: "scx" },
    SlashCmd { act: "imgTextCard", icon: "imgTextCard", title: "slash.img_text_card", sub: "slash.img_text_card_sub", shortcut: "", group: 1, oid: "imgTextCard", ty: "imgTextCard", kw: "image text card 图文 卡片", py: "twkp" },
    SlashCmd { act: "imageTextRow", icon: "imageTextRow", title: "slash.image_text_row", sub: "slash.image_text_row_sub", shortcut: "", group: 1, oid: "imageTextRow", ty: "imageTextRow", kw: "image text row 图文 混排 左右", py: "twhp" },
    SlashCmd { act: "musicCard", icon: "music", title: "slash.music_card", sub: "slash.music_card_sub", shortcut: "", group: 1, oid: "musicCard", ty: "musicCard", kw: "m music 音乐 卡片", py: "yykp" },
    SlashCmd { act: "image", icon: "image", title: "slash.image", sub: "slash.image_sub", shortcut: "", group: 1, oid: "image", ty: "image", kw: "i image 图片", py: "tp" },
    SlashCmd { act: "gallery", icon: "gallery", title: "slash.gallery", sub: "slash.gallery_sub", shortcut: "", group: 1, oid: "gallery", ty: "gallery", kw: "g gallery 画廊", py: "hl" },
];

/// 标题排序（D-3，原版 slash-model.js:20 的
/// `a.title.localeCompare(b.title, 'zh-Hans-CN')`）：直调
/// 浏览器 JS String.prototype.localeCompare，与原版同为
/// 浏览器 ICU collation、零偏差（预计算拼音键难与 ICU
/// 全等价，不取）。调用失败兜底字节序。
fn slash_title_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    use wasm_bindgen::{JsCast, JsValue};
    let sa: JsValue = js_sys::JsString::from(a).into();
    let f = js_sys::Reflect::get(&sa, &JsValue::from_str("localeCompare"))
        .ok()
        .and_then(|f| f.dyn_into::<js_sys::Function>().ok());
    if let Some(f) = f {
        let args = js_sys::Array::new();
        args.push(&JsValue::from_str(b));
        args.push(&JsValue::from_str("zh-Hans-CN"));
        if let Ok(v) = f.apply(&sa, &args) {
            if let Some(n) = v.as_f64() {
                return if n < 0.0 {
                    Ordering::Less
                } else if n > 0.0 {
                    Ordering::Greater
                } else {
                    Ordering::Equal
                };
            }
        }
    }
    a.cmp(b)
}

/// 最近使用（原版 use-slash.js 口径）：localStorage
/// memos_slash_recent_v1 存原版 id 数组，最多 6 条，最新在前。
fn slash_recent_ids() -> Vec<String> {
    let raw = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|st| st.get_item("memos_slash_recent_v1").ok().flatten())
        .unwrap_or_default();
    let mut ids: Vec<String> = serde_json::from_str::<Vec<String>>(&raw).unwrap_or_default();
    ids.truncate(6);
    ids
}

fn slash_record_recent(act: &str) {
    let Some(cmd) = SLASH_CMDS.iter().find(|c| c.act == act) else {
        return;
    };
    let mut ids = slash_recent_ids();
    ids.retain(|i| i != cmd.oid);
    ids.insert(0, cmd.oid.to_string());
    ids.truncate(6);
    if let Some(st) = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
    {
        let _ = st.set_item(
            "memos_slash_recent_v1",
            &serde_json::to_string(&ids).unwrap_or_default(),
        );
    }
    diag::log("EDIT", &format!("slash recent <- {}", cmd.oid));
}

/// 行内斜杠命令：不改块类型，由 JS 桥对选区就地执行。
const INLINE_ACTS: &[&str] = &["bold", "italic", "highlight", "code", "strikethrough"];

/// 媒体文件请求：斜杠「图片/画廊」替换当前块，或给图文块换图。
#[derive(Clone, PartialEq)]
pub(crate) enum MediaReq {
    Replace { bid: String, gallery: bool },
    SetImage { bid: String },
    /// 卡片编辑态点画廊格换单图（index=Some，保图库的表示
    /// 形态）/ 点空态占位格追加所选（index=None）。
    GalleryPick { bid: String, index: Option<usize> },
}

/// 历史快照压栈：与栈顶不同才压（截断重做尾，上限 50）。
fn perf_now_ms() -> f64 {
    js_sys::Date::now()
}

/// 压入一个新快照（原版 use-history.js recordUndoPoint 口
/// 径）：上限 100 步；coalesce 的连续输入在 600ms 内替换栈
/// 顶当前快照（撤销一次回到输入爆发前），结构性压栈断开
/// 合并链。撤销/重做后 idx 不在栈顶，同样不合并。
fn hist_push(
    mut hist: Signal<Vec<String>>,
    mut hist_idx: Signal<usize>,
    mut hist_clock: Signal<(f64, bool)>,
    json: String,
    coalesce: bool,
) {
    let mut h = hist.read().clone();
    let idx = *hist_idx.read();
    if h.get(idx).map(|x| x.as_str()) == Some(json.as_str()) {
        return;
    }
    let now = perf_now_ms();
    let (last_at, chain) = *hist_clock.read();
    if coalesce && chain && idx + 1 == h.len() && now - last_at < 600.0 {
        h[idx] = json;
        hist.set(h);
        hist_clock.set((now, true));
        diag::log_once("hist-coalesce", "EDIT", "undo point coalesced (600ms window)");
        return;
    }
    h.truncate(idx + 1);
    h.push(json);
    if h.len() > 100 {
        h.remove(0);
    }
    hist_idx.set(h.len() - 1);
    hist.set(h);
    hist_clock.set((now, coalesce));
}

/// 第一个可编辑块的 id（撤销/重做后焦点兜底落点）。
fn first_editable_id(doc: &[Node]) -> Option<String> {
    for b in doc {
        let ty = b.block_type().unwrap_or("");
        if is_text_block(ty) {
            return b.id.clone();
        }
        if ty == "bulleted-list" || ty == "numbered-list" {
            if let Some(kids) = &b.children {
                for item in kids {
                    if item.is_block() {
                        return item.id.clone();
                    }
                }
            }
        }
    }
    None
}

/// 撤销/重做后恢复焦点（编辑态审计 D4）：优先回到操作前所在块
/// （偏移按新文档钳制），块已不存在则落到第一个可编辑块。
/// 没有这一步，epoch 整体重挂载后 activeElement 落到 BODY，
/// 后续打字无处落点。
fn restore_focus(
    doc: &[Node],
    focus_req: &mut Signal<Option<(String, usize)>>,
    focus: Option<(String, usize)>,
) {
    if let Some((bid, off)) = focus {
        if let Some(loc) = find_loc(doc, &bid) {
            let len = plain_len(node_at(doc, loc));
            focus_req.set(Some((bid, off.min(len))));
            return;
        }
    }
    if let Some(bid) = first_editable_id(doc) {
        focus_req.set(Some((bid, 0)));
    }
}

/// 撤销一步：先把（可选的）DOM 全量同步并入模型并压栈，保证
/// 当前状态可被重做找回，再回到上一快照整体重挂载。
/// 菜单与键盘（桥）两路共用，行为一致（编辑态审计 D2/D4）。
#[allow(clippy::too_many_arguments)]
fn step_undo(
    doc: &mut Signal<Vec<Node>>,
    hist: &mut Signal<Vec<String>>,
    hist_idx: &mut Signal<usize>,
    hist_clock: &mut Signal<(f64, bool)>,
    epoch: &mut Signal<u32>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    persist: &PersistHandle,
    data: Signal<BackupFile>,
    title: &Signal<String>,
    sync_json: Option<&str>,
    focus: Option<(String, usize)>,
) {
    let mut d = doc.read().clone();
    if let Some(s) = sync_json {
        apply_sync_map(&mut d, s);
        doc.set(d.clone());
    }
    let cur = serde_json::to_string(&d).unwrap_or_default();
    let mut h = hist.read().clone();
    let mut idx = *hist_idx.read();
    if h.get(idx).map(|x| x.as_str()) != Some(cur.as_str()) {
        h.truncate(idx + 1);
        h.push(cur);
        if h.len() > 100 {
            h.remove(0);
        }
        idx = h.len() - 1;
    }
    // 撤销打断输入合并链（原版 undo 后 lastPushAt 归零同义）
    hist_clock.set((0.0, false));
    if idx == 0 {
        hist.set(h);
        hist_idx.set(idx);
        return;
    }
    idx -= 1;
    if let Ok(nd) = serde_json::from_str::<Vec<Node>>(&h[idx]) {
        doc.set(nd.clone());
        let e = *epoch.read();
        epoch.set(e + 1);
        restore_focus(&nd, focus_req, focus);
        persist.call(nd, title.read().clone(), data);
        diag::log("EDIT", &format!("undo -> snapshot {idx}"));
    }
    hist.set(h);
    hist_idx.set(idx);
}

/// 重做一步：同样先同步并压栈——撤销后又打了字再重做时，
/// 同步值与栈顶不一致说明历史已分叉，按新分支处理（压栈后
/// 不再前进），避免旧未来快照吞掉新输入。
#[allow(clippy::too_many_arguments)]
fn step_redo(
    doc: &mut Signal<Vec<Node>>,
    hist: &mut Signal<Vec<String>>,
    hist_idx: &mut Signal<usize>,
    hist_clock: &mut Signal<(f64, bool)>,
    epoch: &mut Signal<u32>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    persist: &PersistHandle,
    data: Signal<BackupFile>,
    title: &Signal<String>,
    sync_json: Option<&str>,
    focus: Option<(String, usize)>,
) {
    let mut d = doc.read().clone();
    if let Some(s) = sync_json {
        apply_sync_map(&mut d, s);
        doc.set(d.clone());
    }
    let cur = serde_json::to_string(&d).unwrap_or_default();
    let mut h = hist.read().clone();
    let idx = *hist_idx.read();
    // 重做同样打断输入合并链
    hist_clock.set((0.0, false));
    if h.get(idx).map(|x| x.as_str()) != Some(cur.as_str()) {
        h.truncate(idx + 1);
        h.push(cur);
        if h.len() > 100 {
            h.remove(0);
        }
        let top = h.len() - 1;
        hist.set(h);
        hist_idx.set(top);
        return; // 已分叉：新输入即最新状态，无旧未来可重做
    }
    if idx + 1 < h.len() {
        if let Ok(nd) = serde_json::from_str::<Vec<Node>>(&h[idx + 1]) {
            doc.set(nd.clone());
            let e = *epoch.read();
            epoch.set(e + 1);
            restore_focus(&nd, focus_req, focus);
            hist_idx.set(idx + 1);
            persist.call(nd, title.read().clone(), data);
            diag::log("EDIT", &format!("redo -> snapshot {}", idx + 1));
        }
    }
    hist.set(h);
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
fn build_backup(
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
        m.updated_at = mynote_core::model::Timestamp::Iso(now_iso());
    }
    Some(backup)
}

async fn save_backup(backup: &BackupFile) {
    match serde_json::to_string(backup) {
        Ok(json) => match idb::save_memos(&json).await {
            Ok(()) => diag::log("EDIT", &format!("save_memos ok {}B", json.len())),
            Err(e) => diag::log("EDIT", &format!("save err: {e:?}")),
        },
        Err(e) => diag::log("EDIT", &format!("serialize err: {e}")),
    }
}

fn now_iso() -> String {
    js_sys::Date::new_0()
        .to_iso_string()
        .as_string()
        .unwrap_or_default()
}

fn now_millis() -> i64 {
    js_sys::Date::now() as i64
}

fn gen_id() -> String {
    let r = js_sys::Math::random();
    format!("b{:x}", (r * 1e12) as u64)
}

fn empty_text_node() -> Node {
    Node {
        text: Some(String::new()),
        node_type: None,
        id: None,
        children: None,
        extra: Map::new(),
    }
}

fn new_block(block_type: &str) -> Node {
    Node {
        text: None,
        node_type: Some(block_type.to_string()),
        id: Some(gen_id()),
        children: Some(vec![empty_text_node()]),
        extra: Map::new(),
    }
}

/// 打开编辑器时给所有可编辑节点补 id（真实数据的块都带 id，
/// 列表项等个别可能没有）——DOM 桥按 id 寻址。
fn ensure_ids(doc: &mut [Node]) {
    for block in doc.iter_mut() {
        if block.id.is_none() {
            block.id = Some(gen_id());
        }
        if let Some(kids) = &mut block.children {
            for item in kids.iter_mut() {
                if item.is_block() && item.id.is_none() {
                    item.id = Some(gen_id());
                }
            }
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Loc {
    Top(usize),
    Item(usize, usize),
}

fn find_loc(doc: &[Node], bid: &str) -> Option<Loc> {
    for (i, b) in doc.iter().enumerate() {
        if b.id.as_deref() == Some(bid) {
            return Some(Loc::Top(i));
        }
        if let Some(kids) = &b.children {
            for (j, item) in kids.iter().enumerate() {
                if item.is_block() && item.id.as_deref() == Some(bid) {
                    return Some(Loc::Item(i, j));
                }
            }
        }
    }
    None
}

fn node_at<'a>(doc: &'a [Node], loc: Loc) -> &'a Node {
    match loc {
        Loc::Top(i) => &doc[i],
        Loc::Item(li, ii) => &doc[li].children.as_ref().unwrap()[ii],
    }
}

fn node_at_mut<'a>(doc: &'a mut [Node], loc: Loc) -> &'a mut Node {
    match loc {
        Loc::Top(i) => &mut doc[i],
        Loc::Item(li, ii) => &mut doc[li].children.as_mut().unwrap()[ii],
    }
}

/// 文档顺序里上一个可编辑文本块（合并的目标）。
fn prev_editable(doc: &[Node], loc: Loc) -> Option<Loc> {
    let mut prev: Option<Loc> = None;
    for (i, b) in doc.iter().enumerate() {
        let ty = b.block_type().unwrap_or("");
        if is_text_block(ty) {
            let cur = Loc::Top(i);
            if cur == loc {
                return prev;
            }
            prev = Some(cur);
        }
        if ty == "bulleted-list" || ty == "numbered-list" {
            if let Some(kids) = &b.children {
                for (j, item) in kids.iter().enumerate() {
                    if item.is_block() {
                        let cur = Loc::Item(i, j);
                        if cur == loc {
                            return prev;
                        }
                        prev = Some(cur);
                    }
                }
            }
        }
    }
    None
}

fn is_text_block(ty: &str) -> bool {
    matches!(
        ty,
        "paragraph" | "heading" | "quote" | "todo" | "callout" | "list-item" | "codeBlock"
    )
}

/// 块纯文本长度，口径 = JS String.length（UTF-16 码元）。
/// 全部调用点都是 DOM 光标偏移（__mnFocus/__mnSetHtml 按
/// textContent.length 走 TreeWalker、caretInfo 按 range 字
/// 符串长度计），原版单宿主里浏览器原生合并的光标落点同
/// 口径。此前按 chars()（标量）计，前块含星光平面字符
/// （emoji/𐮷 等）时合并接合点、撤销恢复钳制、粘贴落点
/// 一律少算、光标落进代理对中间（跨块语义组实测 MERGE1
/// utf16=3 应为 4）。
fn plain_len(node: &Node) -> usize {
    node.plain_text().encode_utf16().count()
}

/// 字数口径逐字对原版 editor.js:2454：只统计顶层 paragraph 块
/// 的第一个叶子的文本（去掉 \n）。标题/待办/列表等不计入——
/// 此前按全块纯文本统计，看展备忘多出标题 4 字（118 vs 114）。
/// 长度按 JS String.length（UTF-16 码元）计：原版是 .length，
/// emoji 等星光平面字符算 2——此前按 chars() 计，混排夹具
/// 编辑页字数 232 vs 原版 233，差的就是一个 😀。
fn orig_char_count(doc: &[Node]) -> usize {
    doc.iter()
        .filter(|n| n.block_type() == Some("paragraph"))
        .map(|n| {
            n.children
                .as_ref()
                .and_then(|c| c.first())
                .and_then(|f| f.text.as_ref())
                .map(|t| t.replace('\n', "").encode_utf16().count())
                .unwrap_or(0)
        })
        .sum()
}

/// 列表源段落（原版转换管线的 pass2 先行成组转换，不带
/// ensureTrailing 回调）。
fn is_list_para(node: &Node) -> bool {
    node.block_type() == Some("paragraph")
        && matches!(
            crate::blocks::md_classify(&node.plain_text()),
            Some(crate::blocks::MdKind::List { .. })
        )
}

/// 渲染成块级 md 预览的段落（行内预览不算）。
fn is_block_preview_para(node: &Node) -> bool {
    if node.block_type() != Some("paragraph") {
        return false;
    }
    let text = node.plain_text();
    crate::blocks::md_classify(&text).is_some()
        && crate::blocks::md_is_block_preview(&text)
}

/// 原版 ensureTrailingParagraphBlock（editor.js:410-420）的
/// 等价确定性规则：块级 md 预览（列表组除外）之后，若紧邻
/// 的下一个块是不可编辑形态——原子块 / 分割线 / 另一个块
/// 级预览（列表组预览与单预览同为 contentEditable=false
/// 的 div）/ 文档末尾——补一个空段落。判定口径取原版打开
/// 时的稳态：加载管线把全部 md 块渲染成预览后逐个跑
/// ensureTrailing，故相邻预览之间同样有段（原版活体实测：
/// 两段相邻代码预览之间与文末各一段）；会话内失焦转换时
/// 「下一块正在源码编辑」由 materialize 的 editing 守卫对
/// 齐（转换时点不补、失焦后补，与原版收敛形态一致）。
fn trail_after(doc: &[Node], i: usize) -> bool {
    if !is_block_preview_para(&doc[i]) || is_list_para(&doc[i]) {
        return false;
    }
    match doc.get(i + 1) {
        None => true,
        Some(next) => {
            let t = next.block_type().unwrap_or("");
            matches!(
                t,
                "image"
                    | "gallery"
                    | "imgTextCard"
                    | "imageTextRow"
                    | "attachment"
                    | "link-card"
                    | "musicCard"
                    | "embedCard"
                    | "divider"
            ) || is_list_para(next)
                || is_block_preview_para(next)
        }
    }
}

/// 文末原子块清单（原版 editor.js:426 init 口径的有效集）：
/// init 检查的是最后一块 DOM 的 dataset.type，故只有渲染
/// 时带 data-type 的类型才真正触发 trail_ 推入——musicCard
/// /link-card/attachment/image/gallery/imgTextCard/image
/// TextRow/todo。divider 渲染为裸 <hr>（无 data-type）、
/// embedCard/decorative_divider 落 <p> 兜底，均不触发（原
/// 版活体实测：文末分割线的备忘打开后 DOM 与落盘都无尾随
/// 段）；这些块的尾随段由插入路径产生（斜杠转 divider 自
/// 带段落、粘贴/插入原子块后 ensure），不在打开时补。
const TRAIL_END_ATOMIC: [&str; 8] = [
    "musicCard",
    "link-card",
    "attachment",
    "image",
    "gallery",
    "imgTextCard",
    "imageTextRow",
    "todo",
];

/// 尾随空段模型化（原版 ensureTrailing + init trail_ 的模型
/// 层等价）：在 trail_after 命中的预览块之后、以及文末原子
/// 块之后，插入真实空段落块（new_block("paragraph")，与原
/// 版 {type:'paragraph', children:[{text:''}]} 同形态）。原
/// 版里这些段落是带 blockid 的可编辑 <p>，首次 parseEditor
/// DOM 同步即成为 docRef 中的真实段落并落盘——不存在视图
/// 层形态。插入后同一位置的 trail_after 转假、文末块变为
/// 段落，故重复调用幂等。editing 是当前源码编辑中的块 id：
/// 它之后的尾随段等失焦转预览时再补（原版 ensureTrailing
/// 在预览转换时点才触发）。返回插入数。
fn materialize_trails(doc: &mut Vec<Node>, editing: Option<&str>) -> usize {
    let mut inserted = 0;
    let mut i = 0;
    while i < doc.len() {
        if trail_after(doc, i) && editing != doc[i].id.as_deref() {
            doc.insert(i + 1, new_block("paragraph"));
            inserted += 1;
            i += 2;
        } else {
            i += 1;
        }
    }
    if let Some(last) = doc.last() {
        if TRAIL_END_ATOMIC.contains(&last.block_type().unwrap_or("")) {
            doc.push(new_block("paragraph"));
            inserted += 1;
        }
    }
    inserted
}

/// 行内形态归一（打开时一次性，与 materialize_trails 同位）：
/// 存量 bool 标记块（外部工具/旧版本写入的 children 多子节点
/// + bold/italic 等 bool 键）经编辑对往返折成字面单节点形态。
/// 必须在首次渲染前完成：编辑对填充已把 bool 折成字面文本
/// 住进 DOM，会话内任何一次全量回收（菜单打开/返回/撤销的
/// apply_sync_map）都会把这类块归一——若归一发生在会话中途，
/// 块的纯文本凭空多出字面标记、渲染形态由可编辑段落翻成
/// md 预览（导出冒烟实测：菜单 sync 后块几何 17→16、快照丢
/// data-bid）。打开时先归一，块从第一帧起就是它最终的形态，
/// 此后填充/回收往返恒等、被动 sync 恢复隐形。仅处理带标记
/// bool 或链接节点的行内列（无标记纯文本列往返本就恒等，
/// 不动）；下划线往返恒等（<u> 元素承载），计数不虚报。
/// 返回实际变更的块数。
fn normalize_inline_forms(doc: &mut Vec<Node>) -> usize {
    fn has_mark_or_link(kids: &[Node]) -> bool {
        kids.iter().any(|c| {
            c.block_type() == Some("link")
                || [
                    "bold",
                    "italic",
                    "underline",
                    "strikethrough",
                    "strike",
                    "code",
                ]
                .iter()
                .any(|k| c.extra.get(*k).and_then(|v| v.as_bool()).unwrap_or(false))
        })
    }
    fn walk(nodes: &mut [Node]) -> usize {
        let mut changed = 0;
        for n in nodes.iter_mut() {
            let Some(mut kids) = n.children.take() else {
                continue;
            };
            if has_mark_or_link(&kids) {
                let round = editor_html_to_inlines(&inlines_to_editor_html(&kids));
                if round != kids {
                    changed += 1;
                    kids = round;
                }
            }
            changed += walk(&mut kids);
            n.children = Some(kids);
        }
        changed
    }
    walk(doc)
}

/// 块流渲染单元：普通块单渲；相邻的列表源段落（≥2）合成
/// 一个合并预览（M6）。原版依据：blur 管线 pass1 用
/// collectListGroup（src/editor/md-blocks.js:38-49）把同流内
/// 相邻的列表行段落成组，join('\n') 后 marked 一次渲染、
/// 替换为单个 .md-preview.block（首块 id）；点击该预览按
/// use-editor-dom.js:117-132 还原为单个源码段（其余块消
/// 失）。Rust 块流在渲染层等价成组，点击时把模型合并回
/// 首块（见 MergedListPreview），存储形态不变（段落文本本
/// 就可含 \n）。
enum FlowRun {
    Single(usize),
    ListGroup(Vec<usize>),
}

/// 组员资格（原版 LIST_RE，md-blocks.js:9）：段落修剪后以
/// [-*] 或 数字. 开头（后跟空白）；且非源码编辑/聚焦态、
/// 本身会渲染为 md 预览（与单块路径同门控）。
fn is_list_group_member(
    node: &Node,
    editing_id: Option<&str>,
    active_id: Option<&str>,
) -> bool {
    if node.block_type() != Some("paragraph") {
        return false;
    }
    let bid = node.id.as_deref().unwrap_or("");
    if Some(bid) == editing_id || Some(bid) == active_id {
        return false;
    }
    let text = node.plain_text();
    if crate::blocks::md_classify(&text).is_none() {
        return false;
    }
    let t = text.trim();
    let b = t.as_bytes();
    if b.len() >= 2
        && (b[0] == b'-' || b[0] == b'*')
        && (b[1] as char).is_whitespace()
    {
        return true;
    }
    let mut i = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    i > 0 && i + 1 < b.len() && b[i] == b'.' && (b[i + 1] as char).is_whitespace()
}

/// 把 [start, end) 区间的块序切成渲染单元（同流内成组，
/// 不跨调用方给定的区间边界 = 不跨栏）。
fn flow_runs(
    doc: &[Node],
    range: std::ops::Range<usize>,
    editing_id: Option<&str>,
    active_id: Option<&str>,
) -> Vec<FlowRun> {
    let mut runs = Vec::new();
    let mut i = range.start;
    while i < range.end {
        if is_list_group_member(&doc[i], editing_id, active_id) {
            let mut j = i + 1;
            while j < range.end
                && is_list_group_member(&doc[j], editing_id, active_id)
            {
                j += 1;
            }
            if j - i >= 2 {
                runs.push(FlowRun::ListGroup((i..j).collect()));
            } else {
                runs.push(FlowRun::Single(i));
            }
            i = j;
        } else {
            runs.push(FlowRun::Single(i));
            i += 1;
        }
    }
    runs
}

/// 合并列表预览（M6）：组内各段修剪文本 join('\n') 后走
/// 同一个 MdPreview（任务 checkbox、有序 start 在组内口径
/// 下由 marked 子集解析器自然成立）。点击 = 原版还原口
/// 径：模型里把组员合并回首块（首块 id 与位置保留，文本
/// 为合并源码），其余块删除，进源码编辑态、光标落合并
/// 源码末尾（原版 use-editor-dom.js:117-135 对块级预览统
/// 一 collapse(false) 落末尾；点击位置不参与落点，M9 审
/// 计的「点击处附近」系元素偏移误读，第八批双边复测证伪）。
#[component]
fn MergedListPreview(
    bids: Vec<String>,
    text: String,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
) -> Element {
    let md_ctx = try_use_context::<crate::blocks::MdEdit>();
    let first = bids.first().cloned().unwrap_or_default();
    let bids_attr = bids.join(",");
    rsx! {
        div {
            class: "md-hit",
            "data-bids": "{bids_attr}",
            onclick: move |_| {
                let Some(c) = md_ctx else { return };
                let mut d = doc.read().clone();
                // 成员须仍是紧邻的顶层段落且顺序一致（渲染后
                // 文档可能已变）；对不上就只进首块源码编辑。
                let mut ok = false;
                if let Some(Loc::Top(top)) = find_loc(&d, &first) {
                    let mut idxs = Vec::new();
                    for (k, b) in bids.iter().enumerate() {
                        match d.get(top + k) {
                            Some(n)
                                if n.id.as_deref() == Some(b.as_str())
                                    && n.block_type() == Some("paragraph") =>
                            {
                                idxs.push(top + k);
                            }
                            _ => break,
                        }
                    }
                    if idxs.len() == bids.len() && idxs.len() >= 2 {
                        let joined: String = idxs
                            .iter()
                            .map(|&ix| d[ix].plain_text().trim().to_string())
                            .collect::<Vec<_>>()
                            .join("\n");
                        let n0 = node_at_mut(&mut d, Loc::Top(top));
                        n0.children = Some(vec![text_node(&joined)]);
                        for &ix in idxs[1..].iter().rev() {
                            d.remove(ix);
                        }
                        ok = true;
                    }
                }
                if ok {
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                }
                let mut s = c.0;
                s.set(Some(first.clone()));
                diag::log(
                    "EDIT",
                    &format!(
                        "md preview -> source edit {first} form=list-group caret=end offset={} (merged={ok}, {} blocks)",
                        doc.read()
                            .iter()
                            .find(|n| n.id.as_deref() == Some(first.as_str()))
                            .map(|n| n.plain_text().encode_utf16().count())
                            .unwrap_or(0),
                        bids.len()
                    ),
                );
                // 落点 = 合并源码末尾（原版 use-editor-dom.js:117-135
                // 对 .md-preview.block 还原后 selectNodeContents +
                // collapse(false)；M9 审计的 focusOffset 1 是元素
                // 节点偏移=唯一文本子节点之后，即末尾，复测见
                // 第八批探针）。同步武装桥的挂载守卫（本组件随即
                // 卸载，spawn/eval 与旧 setTimeout 60ms 均在此竞
                // 速丢失，见 sync_arm_md_focus）。
                sync_arm_md_focus(&first);
            },
            crate::blocks::MdPreview { text }
        }
    }
}

// 尾随空段已模型化（见 materialize_trails）：尾随位置在
// 打开备忘时即补成真实空段落块、会话内由物化 effect 续
// 补，渲染走普通 EditorBlock 路径，不再有视图层占位。

/// 深色模式（渲染期读 matchMedia；切换由 scheme_tick 触发重渲染）。
fn is_dark_mode() -> bool {
    web_sys::window()
        .and_then(|w| w.match_media("(prefers-color-scheme: dark)").ok().flatten())
        .map(|m| m.matches())
        .unwrap_or(false)
}

/// 深色下压暗自定义背景（原版 getDarkenedColor：每通道 ×0.35）。
fn darken_hex(hex: &str) -> String {
    let h = hex.trim_start_matches('#');
    if h.len() != 6 || !h.chars().all(|c| c.is_ascii_hexdigit()) {
        return hex.to_string();
    }
    let ch = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0);
    let f = |v: u8| ((v as f32 * 0.35).round() as u8);
    format!("#{:02x}{:02x}{:02x}", f(ch(0)), f(ch(2)), f(ch(4)))
}

/// 拉取链接元数据（原版 fetchLinkMeta：GET Worker /meta?url=，
/// 非 2xx 或解析失败返回 None）。
async fn fetch_link_meta(url: &str) -> Option<serde_json::Value> {
    use wasm_bindgen::JsCast;
    let win = web_sys::window()?;
    let api = format!(
        "https://mynote.overtrees.workers.dev/meta?url={}",
        crate::blocks::url_encode(url)
    );
    let resp_val = wasm_bindgen_futures::JsFuture::from(win.fetch_with_str(&api))
        .await
        .ok()?;
    let resp: web_sys::Response = resp_val.dyn_into().ok()?;
    if !resp.ok() {
        return None;
    }
    let json_val = wasm_bindgen_futures::JsFuture::from(resp.json().ok()?)
        .await
        .ok()?;
    let text = js_sys::JSON::stringify(&json_val)
        .ok()
        .and_then(|s| s.as_string())?;
    serde_json::from_str(&text).ok()
}

/// 编辑器有效背景（原版 editorBg）：自定义色（深色压暗）优先，
/// 否则浅色 #FAFAFA（--color-editor-bg）/ 深色 #000。
/// App 外壳的根背景派生也用它（main.rs 单一写入者），口径必须
/// 只有一个实现。
pub(crate) fn effective_bg(bg: &Option<String>) -> String {
    match bg {
        Some(c) => {
            if is_dark_mode() {
                darken_hex(c)
            } else {
                c.clone()
            }
        }
        None => {
            if is_dark_mode() {
                "#000000".to_string()
            } else {
                "#FAFAFA".to_string()
            }
        }
    }
}

/// 同步武装 md 源码落点守卫（window.__mnFocusAtMount，桥内
/// MutationObserver 守候目标挂载后经 __mnFocus 落末尾，
/// usize::MAX 由其钳到文本长）。必须同步直调而非 spawn
/// eval：MergedListPreview 在编辑态置位后立即卸载，其
/// spawn 任务随组件作用域取消、eval 永不执行（第八批时间
/// 线探针实测 ARM 未达）；EditorBlock 单块入口不卸载故旧
/// spawn 偶能存活。未安装时跳过（桥随编辑器挂载先行安装）。
fn sync_arm_md_focus(bid: &str) {
    let Some(w) = web_sys::window() else { return };
    let wv: &wasm_bindgen::JsValue = w.as_ref();
    if let Ok(f) = js_sys::Reflect::get(wv, &"__mnFocusAtMount".into()) {
        if let Some(func) = f.dyn_ref::<js_sys::Function>() {
            let _ = func.call2(
                wv,
                &wasm_bindgen::JsValue::from_str(bid),
                &wasm_bindgen::JsValue::from_f64(usize::MAX as f64),
            );
        }
    }
}

/// 菜单关闭完成后的去向（浮层出场补齐）：无 / 链式打开
/// 导出面板 / 链式打开背景色底表——原版 openExportPanel
/// 与更换背景菜单项都是「closeEditorMenu 后 220ms 再挂
/// 下一层」，去向在关闭发起时随计时一同排定、完成时消费。
#[derive(Clone, Copy, PartialEq)]
enum MenuAfter {
    None,
    Export,
    Bg,
}

/// 背景色底表关闭完成后的动作（原版 BgSheet
/// closeWithAnim 的 afterClose 口径）：选色/移除在动画播
/// 满、底表卸载时点才生效，不是点击瞬间。
#[derive(Clone, PartialEq)]
enum BgAfter {
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
fn animate_menu_close(
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
fn cancel_menu_close(mut menu_gen: Signal<u32>, mut menu_closing: Signal<bool>) {
    let gen = *menu_gen.read() + 1;
    menu_gen.set(gen);
    menu_closing.set(false);
}

/// 背景色生效（原 set_bg 的落库半边，现由底表关闭完成
/// 时点调用）：写 memo.extra["bgColor"]、根背景同任务
/// 同步、落库保存。
fn apply_bg_color(
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
                m.extra
                    .insert("bgColor".to_string(), Value::String(c.clone()));
            }
            None => {
                m.extra.remove("bgColor");
            }
        }
    }
    data.set(backup.clone());
    // 发起任务内同步生效（背景同步根治）：根背景变量
    // 先写，中心/顶带/底带同帧达新色；App 派生 effect
    // 随后重申同值（Diag 的 APP root bg 记录仍是单次
    // 派生口径）。顶部渐变已回落 base.css 基础规则、不
    // 消费根色变量，无同任务刷新可言（改写装置已移除，
    // 见 scheme effect 注）。
    crate::apply_root_bg(Some(&effective_bg(&color)));
    diag::log("EDIT", &format!("bg -> {color:?}"));
    spawn(async move {
        save_backup(&backup).await;
    });
}

/// 背景色底表关闭动画（原版 BgSheet closeWithAnim 口
/// 径）：置 closing 态（.sheet-wrap.is-closing：opacity
/// 200ms ease + transform 250ms 弹簧 → +20px），220ms
/// 后卸载；选色/移除经 BgAfter::Apply 在完成时点才生
/// 效。重排语义同菜单（代际守卫、旧回调作废）。
#[allow(clippy::too_many_arguments)]
fn animate_bg_close(
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
fn animate_text_sheet_close(
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
            text_sheet.set(None);
            diag::log("EDIT", "text sheet closed");
        }
    });
}

/// PERF（第八批 T2）：反向链接的每渲全库扫描缓存。
/// compute_backlinks 此前在 Editor 每次渲染时对全部备忘
/// 逐篇跑 memo_wiki_targets（三趟 Vec<char> 全文变换）；
/// 300 篇库实测单次 ≈12ms、每次打开至少付两遍（守卫修复
/// 后一遍），键入/滚动等会话内重渲同样反复付。targets 只
/// 由备忘 doc 的「wiki 源文本」（collect_wiki_source 口径
/// 收集、'\n' 拼接）决定，故按该源文本的 FNV-1a 指纹做
/// 会话内缓存：指纹未变的备忘直接复用 targets，指纹变了
/// 才重算——结果与逐次现算逐字一致（顺序、标题、命中集
/// 均不变），Diag 的 backlinks log_once 同口径保留。
fn wiki_source_fingerprint(memo: &mynote_core::model::Memo) -> u64 {
    fn hash_bytes(mut h: u64, bytes: &[u8]) -> u64 {
        for &b in bytes {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        h
    }
    fn walk(node: &Node, h: &mut u64, first: &mut bool) {
        // 与 wiki::collect_wiki_source 同口径：code 类节点
        // 整棵子树跳过（其文本不进源文本、不入指纹）。判定
        // 共用 wiki::is_code_node_type（ASCII 免分配快径，
        // PERF 调优续推：本走查每次渲染对全库执行）。
        if let Some(t) = &node.node_type {
            if crate::wiki::is_code_node_type(t) {
                return;
            }
        }
        if let Some(text) = &node.text {
            if !*first {
                *h = hash_bytes(*h, b"\n");
            }
            *first = false;
            *h = hash_bytes(*h, text.as_bytes());
        }
        if let Some(children) = &node.children {
            for c in children {
                walk(c, h, first);
            }
        }
    }
    let mut h: u64 = 0xcbf29ce484222325;
    let mut first = true;
    for block in &memo.doc {
        walk(block, &mut h, &mut first);
    }
    h
}

type BacklinkCache =
    std::rc::Rc<std::cell::RefCell<std::collections::HashMap<String, (u64, std::collections::HashSet<String>)>>>;

/// compute_backlinks 的缓存等价版：语义/结果与原版逐字一致，
/// 仅把未变化备忘的 targets 提取换成指纹命中复用。
/// PERF（调优续推）：有缓存未命中（真重算）时记一行 PERF
/// 计时（含指纹走查 + 未命中篇的 targets 提取总耗时），
/// 首渲全库扫描的成本从此在 Diag 里可直接读数。
fn backlinks_cached(
    cache: &BacklinkCache,
    memos: &[mynote_core::model::Memo],
    current_id: &str,
    live_title: &str,
) -> Vec<(String, String)> {
    let effective = if live_title.trim() == "无标题" {
        ""
    } else {
        live_title
    };
    let key = crate::wiki::wiki_title_key(effective);
    if key.is_empty() {
        return Vec::new();
    }
    let t_start = js_sys::Date::now();
    let mut misses = 0usize;
    let mut extract_ms = 0.0f64;
    let mut cache = cache.borrow_mut();
    let mut out: Vec<(String, String)> = Vec::new();
    for m in memos {
        let mid = m.id.to_string();
        if mid == current_id {
            continue;
        }
        let fp = wiki_source_fingerprint(m);
        let targets = match cache.get(&mid) {
            Some((cached_fp, targets)) if *cached_fp == fp => targets.clone(),
            _ => {
                misses += 1;
                let t_ex = js_sys::Date::now();
                let targets = crate::wiki::memo_wiki_targets(m);
                extract_ms += js_sys::Date::now() - t_ex;
                cache.insert(mid.clone(), (fp, targets.clone()));
                targets
            }
        };
        if targets.contains(&key) {
            out.push((mid, m.title.clone().unwrap_or_default()));
        }
    }
    if misses > 0 {
        diag::log(
            "PERF",
            &format!(
                "backlinks compute {misses} memo(s) in {:.1}ms (extract {:.1}ms)",
                js_sys::Date::now() - t_start,
                extract_ms
            ),
        );
    }
    diag::log_once(
        &format!("backlinks:{current_id}:{key}:{}", out.len()),
        "WIKI",
        &format!("backlinks '{live_title}' <- {} memo(s)", out.len()),
    );
    out
}

/// 冷开预热（列表页空闲期由 warmup 模块以合成备忘调用）：
/// 预跑打开路径上的纯函数——wiki 源文本指纹走查（编辑器
/// 每渲对全库执行）与双栏分界（规范估高 + 锚归一两条路）。
/// 不触碰编辑器状态、signal 与桥。返回工作量读数。
pub(crate) fn warm_open_pure_paths(memos: &[mynote_core::model::Memo]) -> usize {
    let mut work = 0usize;
    // 合成锚：与 warmup 语料的块 id 对齐（wb1/wb2 左、wb5 起右）
    let layout: serde_json::Value = serde_json::from_str(
        r#"{"left":["wb1","wb2"],"right":["wb5"]}"#,
    )
    .unwrap_or(serde_json::Value::Null);
    for memo in memos {
        work = work.wrapping_add(wiki_source_fingerprint(memo) as usize);
        work += column_boundary(&memo.doc, None);
        work += column_boundary(&memo.doc, Some(&layout));
    }
    work
}

#[component]
pub fn Editor(
    memo_id: String,
    data: Signal<BackupFile>,
    manifest: Signal<String>,
    gen: Signal<u32>,
    on_close: EventHandler<()>,
    on_open_wiki: EventHandler<String>,
    /// 本会话新建的备忘（原版 __isNewNote）：仅它适用「空白
    /// 关闭即删除」，旧备忘清空后退出保留空壳（原版口径）。
    is_new: bool,
    /// 离页态（App 栈式交接）：关闭时本实例不卸载——App 把
    /// 它留在编辑器槽位、翻此 prop 在原地播 slideOut，出场
    /// 时长后由 App 统一卸载。进/出场动画由此 prop 派生
    /// （取代旧内部 page_closing 信号 + go_back 的 320ms
    /// 等待：串行交换下新页挂载长任务冻结进场首帧，见
    /// main.rs Nav 注释）。实例恒以当前态挂载（closing 只在
    /// 关闭后由 App 翻 true），故挂载期读到的恒为 false。
    closing: bool,
) -> Element {
    // 备忘来源：渲染期以 data 现查为准（保存回写、外部变更
    // 即时可见）；挂载首查的快照作回退。回退的唯一现实触发
    // 是空备忘关闭即删除路径：go_back 先 on_close 登记离页、
    // 再 data.set 删备忘（同任务内先后落地），而本实例按
    // #14/③终版设计留槽播出场（main.rs LeavingEditor 明文：
    // 实例靠槽位留存渲染、不依赖 data 查得此备忘）——若查
    // 无即回空模板，离页首帧 #editor-root 就被换成「备忘不
    // 存在」占位、窗口内自有底与内容尽失（probe_page_
    // transitions ④ 实测推翻、Diag close empty memo 序列与
    // 本机 MutationObserver 现场实证）。快照与 state_owner
    // 同口径：实例状态只归属其加载 id、挂载时定格。hook 恒
    // 居组件首行，原先行 return 在全部 hooks 之前（首次查
    // 无时 hooks 从未注册、后再查得才注册）的脆弱形态一并
    // 收掉；首次渲染备忘恒在（打开入口自列表/新建），快照
    // 为 None 仅余防御语义、与旧行为一致。
    let memo_held = use_hook(|| {
        data.read()
            .memos
            .iter()
            .find(|m| m.id.to_string() == memo_id)
            .cloned()
    });
    let memo = data
        .read()
        .memos
        .iter()
        .find(|m| m.id.to_string() == memo_id)
        .cloned()
        .or(memo_held);
    let Some(memo) = memo else {
        return rsx! { div { class: "empty", "{crate::i18n::t(\"editor.missing\")}" } };
    };

    let mut doc = use_signal(|| {
        let mut d = memo.doc.clone();
        ensure_ids(&mut d);
        // 尾随空段在打开时即模型化（原版 init 的 trail_ 推入
        // + ensureTrailing 首次同步入 docRef 的等价终点）；
        // 赶在 initial_doc_json 快照与撤销基线之前，快照口径
        // 与原版一致（尾随段是基础设施，不是用户输入）。
        let n = materialize_trails(&mut d, None);
        if n > 0 {
            diag::log("EDIT", &format!("trail materialized x{n} (open)"));
        }
        // 行内形态归一同位执行（见 normalize_inline_forms）：
        // 存量 bool 块在首次渲染前折成字面形态，会话内不再
        // 出现渲染形态翻转。
        let nb = normalize_inline_forms(&mut d);
        if nb > 0 {
            diag::log("EDIT", &format!("inline normalize x{nb} (open)"));
        }
        // MD-C10 围栏跨块合并同位执行（见 blocks::
        // merge_split_fences）：存量拆段围栏在首次渲染前
        // 并回一段，与原版 collectFenceGroup 的加载口径
        // 等价；赶在初始快照之前（同上两项）。
        let nf = crate::blocks::merge_split_fences(&mut d);
        if nf > 0 {
            diag::log("EDIT", &format!("fence merge x{nf} (open)"));
        }
        d
    });
    let mut title = use_signal(|| memo.title.clone().unwrap_or_default());
    // 原版 hasTyped 的等价追踪：doc/title 任一偏离初始快照即
    // 置位且不回落（打过字再删光也算 typed）。供「空白关闭即
    // 删除」与空占位提示共用。
    // 初始快照必须用 use_hook 锁定挂载值：组件体随每次重渲
    // 染重执行，若在此处直接 read 当前信号，「初始」会随输
    // 入同步漂移，typed 追踪与标题相等判定双双失效（实测：
    // 仅打标题的新备忘关闭时被误判为空而删除；原版
    // initialTitle 取打开时的 memo.title 快照，标题改过即
    // 不算空，见 src/app/editor.js handleClose）。
    let initial_doc_json =
        use_hook(|| serde_json::to_string(&doc.read().clone()).unwrap_or_default()).clone();
    let initial_title = use_hook(|| title.read().clone()).clone();
    // 状态归属 id（挂载锁定，同上两快照口径）：本实例的
    // doc/title 等全部挂载期状态只归属这一 id，persist 守
    // 卫以此校验写目标（见 build_backup）。实例身份由 App
    // 槽位键控重挂绑定备忘 id（main.rs），本值与 memo_id
    // prop 在实例生命内恒等——守卫是纵深防御：任何让 prop
    // 与状态归属分叉的回归都会被拒写，而非以新 id 写旧内
    // 容损坏目标篇存量。
    let state_owner = use_hook(|| memo_id.clone()).clone();
    let mut typed = use_signal(|| false);
    {
        let initial_doc_json = initial_doc_json.clone();
        let initial_title = initial_title.clone();
        use_effect(move || {
            let dj = serde_json::to_string(&doc.read().clone()).unwrap_or_default();
            if dj != initial_doc_json || *title.read() != initial_title {
                typed.set(true);
            }
        });
    }
    let mut panel = use_signal(|| Option::<(String, String, f64, f64, f64)>::None);
    let mut focus_req = use_signal(|| Option::<(String, usize)>::None);
    // 新建备忘自动聚焦首段（原版三层同向：memo-list.js
    // handleNew 在创建手势内同步尝试 focusEditableWithCaret
    // (firstParagraph, 0) 并 rAF 重试；editor.js autoFocus
    // 200ms effect；以及与 autoFocus 无关的 300ms effect——
    // 文档恰为单个空段落的旧备忘打开时同样聚焦首段）。判
    // 定在挂载时用 use_hook 锁定（is_new 或初始文档为单个
    // 空段落），聚焦走既有 focus_req 通道、光标在段首。
    // 只动焦点不动文档：typed 口径与关空备忘删除不受影响。
    let auto_focus_first = use_hook(|| -> Option<String> {
        let d = doc.read();
        let single_empty = d.len() == 1
            && d[0].block_type() == Some("paragraph")
            && d[0].plain_text().is_empty();
        if is_new || single_empty {
            d.iter()
                .find(|n| n.block_type() == Some("paragraph"))
                .and_then(|n| n.id.clone())
        } else {
            None
        }
    });
    {
        let target = auto_focus_first.clone();
        use_effect(move || {
            if let Some(fid) = target.clone() {
                // 桥（EDITOR_JS）由挂载 effect 异步安装，
                // __mnFocus 未就绪时直接调用会被空转；原版
                // 同策略（同步尝试 + rAF 重试 + 延时 effect
                // 兜底）：eval 内轮询就绪后直接聚焦并回传
                // 结果（上限 2s），不走 focus_req 以免被其
                // 消费时序吞掉。
                spawn(async move {
                    // PERF（调优续推）：原版策略本就是「同步尝试 +
                    // rAF 重试」；此前实现只有 50ms 间隔轮询、且
                    // 首次检查也要等一个间隔，聚焦平均白等 ~25ms。
                    // 改为立即尝试一次、未就绪再以 10ms 间隔轮询
                    // （上限仍 2s、落点仍段首 0），语义不变、只缩
                    // 短察觉就绪的延迟。
                    let js = format!(
                        "new Promise((res) => {{ let n = 0; const tryF = () => {{ if (window.__mnFocus) {{ window.__mnFocus({}, 0); res(1); return true; }} return false; }}; if (!tryF()) {{ const t = setInterval(() => {{ if (tryF()) {{ clearInterval(t); }} else if (++n > 200) {{ clearInterval(t); res(0); }} }}, 10); }} }}).then((v) => dioxus.send(v));",
                        serde_json::to_string(&fid).unwrap_or_default()
                    );
                    let mut eval = document::eval(&js);
                    match eval.recv::<Value>().await {
                        Ok(v) if v.as_i64() == Some(1) => {
                            diag::log("EDIT", &format!("auto focus first paragraph {fid}"));
                        }
                        _ => {
                            diag::log("EDIT", "auto focus skipped: bridge not ready");
                        }
                    }
                });
            }
        });
    }
    // 音乐输入解析的待落点卡片 id：解析完成时把光标放到该
    // 卡片下方一行开头（原版 focusCaretBelowResolvedCard）
    let mut card_caret = use_signal(|| Option::<String>::None);
    let mut slash_click = use_signal(|| Option::<(String, String)>::None);
    // 斜杠链接表单：Some(块 id) 时面板切为链接表单；提交后由
    // link_click 触发 __mnApplyLink（选区由桥的 savedRange 恢复）
    let mut link_for = use_signal(|| Option::<String>::None);
    let mut link_click = use_signal(|| Option::<(String, String)>::None);
    // 链接表单的位置：Enter 路径下面板已关，坐标从最后一次
    // slash 消息的位置继承
    let mut link_pos = use_signal(|| (20f64, 160f64, 200f64));
    // 媒体选择请求（斜杠图片/画廊、图文块换图）
    let mut media_req = use_signal(|| Option::<MediaReq>::None);
    // 导出面板（菜单内切换，不是独立弹窗）
    let mut show_export = use_signal(|| false);
    // 导出面板进出场态（原版 exportPanelClosing）：true 时面板
    // 呈 opacity 0 / translateY(-10px) scale(0.94)，靠 CSS
    // transition 与常态之间弹簧过渡（开场双 rAF 后撤、关闭
    // 220ms 后卸载）
    let mut export_closing = use_signal(|| false);
    // 导出面板生命周期代际：开/关每次递增，异步回调（开场
    // 双 rAF、关闭 220ms 计时）按代际守卫、过期自动作废。
    // 关闭语义对齐原版 closeExportPanel 的 clearTimeout 重
    // 排，杜绝视觉态门闩造成的遮罩永久残留（见
    // animate_export_close 注释）。
    let mut export_gen = use_signal(|| 0u32);
    // 导出面板动画相位与关闭去向（遮挡续修）：相位区分挂
    // 起的是开场还是关闭（export_closing 两义），去向记关
    // 闭完成时回菜单还是全关——回前台补完（__mnResume 监
    // 听 → settle_export_on_resume）据此收尾；渲染层据去
    // 向在全关发起瞬间释放遮罩命中（菜单遮罩渲染处）。
    let mut export_anim = use_signal(|| EXPORT_ANIM_IDLE);
    let mut export_to_menu = use_signal(|| false);
    // 页面滚动量：标题坞 >30 切换紧凑行态
    let mut ed_scroll = use_signal(|| 0f64);
    // 标题编辑会话开关（原版 editingTitle）：由 TitleController
    // 经 on_session 回报（聚焦 true / 失焦 false），仅供 S7 滚
    // 动翻转抑制消费。标题的文本与几何自全面重构起全归
    // TitleController 所有（title_controller.rs）：文本只在
    // compositionend/blur/Enter/Esc 时机经 on_commit 写回本
    // 信号，编辑器渲染路径不再持有任何标题布局状态（旧的
    // 布局锁存信号、组字信号与桥快照投影一并删除——多写者
    // 并发正是组字期几何翻转与光标双画的使能条件）。
    let mut title_editing = use_signal(|| false);
    // 深浅模式切换计数（原版监听 matchMedia change 后重算背景）
    let mut scheme_tick = use_signal(|| 0u32);
    // 页面进/出场（原版 editor.js 的 closing/animDone）：进场
    // slideIn 播完 320ms 摘除（page_anim_done）；出场由
    // closing prop 派生（App 栈式交接在原地翻 prop 播
    // slideOut 并计时卸载），不再有内部 page_closing 信号。
    let mut page_anim_done = use_signal(|| false);
    // 图文全文面板（blocks::TextSheet 上下文）
    let mut text_sheet = use_signal(|| Option::<(String, String)>::None);
    let mut sheet_edit = use_signal(|| false);
    let mut sheet_draft = use_signal(String::new);
    // 图文面板出场态与代际（原版 ImageTextSheet closing）
    let mut text_sheet_closing = use_signal(|| false);
    let mut text_sheet_gen = use_signal(|| 0u32);
    // 本篇头像（原版 per-note avatar，存 backup.avatars[memoId]）
    let mut avatar_url = use_signal(|| {
        data.read()
            .avatars
            .as_ref()
            .and_then(|a| a.get(&memo_id))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    });
    let mut dom_set = use_signal(|| Option::<(String, String, usize)>::None);
    // 背景色 / 双栏：存 memo.extra（原版 bgColor 顶层字段、layout 透传）
    let mut bg = use_signal(|| {
        memo.extra
            .get("bgColor")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    });
    let mut twopane = use_signal(|| {
        let layout = memo.extra.get("layout");
        if let Some(mode) = layout.and_then(|v| v.get("mode")).and_then(|v| v.as_str()) {
            return mode == "independent";
        }
        if layout
            .and_then(|v| v.get("twoPane"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return true;
        }
        if layout.is_some() {
            return false;
        }
        web_sys::window()
            .and_then(|w| w.local_storage().ok().flatten())
            .and_then(|st| st.get_item("sj_editor_independent_scroll").ok().flatten())
            .map(|v| v == "1")
            .unwrap_or(false)
    });
    // 宽屏判定（原版双栏媒体查询）：(min-width:768px 且
    // min-height:600px) 或 min-width:1100px；matchMedia 监听
    let mut wide = use_signal(|| {
        web_sys::window()
            .map(|w| {
                w.match_media("(min-width: 768px) and (min-height: 600px), (min-width: 1100px)")
                    .ok()
                    .flatten()
                    .map(|m| m.matches())
                    .unwrap_or(false)
            })
            .unwrap_or(false)
    });
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                // change 监听具名登记（页面副作用审计·泄漏 3）：
                // 旧实现匿名 addEventListener，每次挂载 +1 且永
                // 不摘除、卸载后仍向死通道 send。改走具名
                // handler + window.__mnWideCleanup 幂等清理：
                // 重挂载先调上一代清理，卸载时 sync_editor_
                // cleanup 同步直调，与桥清理并入同一次卸载清理。
                "(() => { if (window.__mnWideCleanup) window.__mnWideCleanup(); const mq = window.matchMedia('(min-width: 768px) and (min-height: 600px), (min-width: 1100px)'); const h = (e) => dioxus.send(e.matches); mq.addEventListener('change', h); window.__mnWideCleanup = () => { mq.removeEventListener('change', h); window.__mnWideCleanup = null; }; dioxus.send(mq.matches); })();",
            );
            while let Ok(v) = eval.recv::<bool>().await {
                // PERF（第八批 T2）：初值回送与现值相同（窄屏
                // false = 初始值）时不 set——Signal::set 无条件
                // 通知订阅者，同值 set 会让整个 Editor 在挂载
                // 后多渲一遍（实测渲染遍数 2→1、打开长任务
                // 173→128ms）；值真变化时照旧 set，行为不变。
                if *wide.peek() != v {
                    wide.set(v);
                }
            }
        });
    });
    // 双栏落锚（原版 captureColumnLayout 在独立滚动启用时
    // 捕获成员并落库的口径）：独立双栏首次渲染且备忘尚无
    // 有效 layout 锚时，按规范估高分界一次性落锚；此后成
    // 员由锚决定，不随编辑、卡片加载、会话漂移。只写
    // extra.layout，不动 doc/title/updated_at。
    let mut col_anchor_done = use_signal(|| false);
    {
        let memo_id = memo_id.clone();
        use_effect(move || {
            if *col_anchor_done.read() {
                return;
            }
            if !(*twopane.read() && *wide.read()) {
                return;
            }
            let d = doc.read().clone();
            let anchored = data
                .read()
                .memos
                .iter()
                .find(|m| m.id.to_string() == memo_id)
                .and_then(|m| m.extra.get("layout").cloned())
                .and_then(|l| normalize_boundary(&d, &l))
                .is_some();
            col_anchor_done.set(true);
            if anchored || d.len() < 2 {
                return;
            }
            let b = canonical_boundary(&d);
            let ids: Vec<Value> = d
                .iter()
                .map(|n| {
                    Value::String(n.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
                })
                .collect();
            let (left, right) = ids.split_at(b.min(ids.len()));
            let mut backup = data.read().clone();
            if let Some(m) = backup
                .memos
                .iter_mut()
                .find(|m| m.id.to_string() == memo_id)
            {
                m.extra.insert(
                    "layout".to_string(),
                    json!({"version": 1, "mode": "independent", "left": left, "right": right}),
                );
            }
            data.set(backup.clone());
            diag::log("EDIT", &format!("column anchor captured boundary={b}"));
            spawn(async move {
                save_backup(&backup).await;
            });
        });
    }
    let mut menu_open = use_signal(|| false);
    let mut bg_open = use_signal(|| false);
    // 菜单/背景底表出场态与生命周期代际（浮层出场补齐，
    // 原版 menuClosing / BgSheet closing）：closing 期间
    // 面板保持挂载播出场 transition，220ms 计时完成后才
    // 卸载；代际守卫让重排/取消的旧回调自动作废。
    let mut menu_closing = use_signal(|| false);
    let mut menu_gen = use_signal(|| 0u32);
    let mut bg_closing = use_signal(|| false);
    let mut bg_gen = use_signal(|| 0u32);
    // 编辑页状态提示：与备份页共用 settings::Toast 同规格
    // （seq 作 key、同文案必重挂、计时器按 seq 校验卸载、
    // Diag 一行；审计 G1/G2 编辑页半边）。原版编辑器无自有
    // 状态条，形态复用备份页 .backup-toast 全宽条口径。
    let ed_status = crate::settings::Toast {
        msg: use_signal(String::new),
        seq: use_signal(|| 0u64),
        kind: use_signal(|| "info"),
        tag: "EDIT",
    };
    // 撤销/重做：文档 JSON 快照栈（与原版 use-history 的全量快照思路一致）
    // 基线 = 打开时的会话文档（含已模型化的尾随空段），撤销
    // 回到基线时尾随段仍在（与原版快照含 DOM 尾随段同口径）。
    let mut hist = use_signal(|| {
        vec![serde_json::to_string(&doc.read().clone()).unwrap_or_default()]
    });
    let mut hist_idx = use_signal(|| 0usize);
    // 撤销合并时钟（原版 use-history recordUndoPoint 口径）：
    // (最近一次连续输入压栈时刻 ms, 合并链是否活着)。600ms
    // 内连续输入替换栈顶；结构操作/撤销/重做断链。
    let mut hist_clock = use_signal(|| (0f64, false));
    let mut epoch = use_signal(|| 0u32);
    // 最近编辑块（桥消息维护）：菜单撤销/重做时恢复焦点的落点
    let mut focus_hint = use_signal(|| Option::<(String, usize)>::None);
    let mut lightbox = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::Lightbox(lightbox));
    use_context_provider(|| crate::blocks::TextSheet(text_sheet));
    let mut md_edit = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::MdEdit(md_edit));
    // 聚焦中的编辑块（桥 focusBlock/blurBlock 维护）：编辑中的
    // 段落不转 md 预览，失焦才转（原版 blur 转换口径）
    let mut active_edit = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::ActiveEdit(active_edit));
    // 卡片重试（blocks::CardRetry 上下文）：音乐卡 error 态点重试
    let mut card_retry = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::CardRetry(card_retry));
    // Wiki 导航（blocks::WikiNav 上下文）：md 预览里的 wiki
    // 链接点击 → 先落盘当前编辑再导航（原版双链优先 + flush）
    let mut wiki_nav = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::WikiNav(wiki_nav));
    // 原子块选中态（blocks::SelBlock 上下文）
    let mut sel_block = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::SelBlock(sel_block));
    // 卡片编辑态（blocks::CardEdit 上下文，卡片交互专项）：
    // 经浮层菜单「编辑」进入，全局同时仅一张卡在编辑态。
    let mut card_edit = use_signal(|| Option::<String>::None);
    use_context_provider(|| crate::blocks::CardEdit(card_edit));
    // 卡片浮层菜单（blocks::CardMenu 上下文，卡片交互专
    // 项）：长按拾起/桌面右键两路同开。
    let mut card_menu = use_signal(|| Option::<crate::blocks::CardMenuState>::None);
    use_context_provider(|| crate::blocks::CardMenu(card_menu));
    // 附件清单（blocks::Manifest 上下文）：附件块文件名查
    // manifest（审计 E2，原版 renderAtomicHTML files 表口径）
    use_context_provider(|| crate::blocks::Manifest(manifest));
    // 反向链接 targets 会话缓存（PERF 第八批 T2，见
    // backlinks_cached）：Rc+RefCell 非响应式持有，不订阅
    // 不触发重渲；随 Editor 实例生灭，跨篇导航重建一次。
    let bl_cache = use_hook(|| -> BacklinkCache {
        std::rc::Rc::new(std::cell::RefCell::new(std::collections::HashMap::new()))
    });

    // 持久化：把当前标题+文档写回总数据并落 IndexedDB
    let persist = PersistHandle(std::rc::Rc::new({
        let memo_id = memo_id.clone();
        let state_owner = state_owner.clone();
        move |doc_snapshot: Vec<Node>, title_snapshot: String, mut data: Signal<BackupFile>| {
            // 守卫拒写（状态归属与写目标不一致）时整笔跳过：
            // 不 set、不落盘（见 build_backup）。
            let Some(backup) =
                build_backup(data, &memo_id, &state_owner, doc_snapshot, title_snapshot)
            else {
                return;
            };
            data.set(backup.clone());
            spawn(async move {
                save_backup(&backup).await;
            });
        }
    }));

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
                    let (skip_hist, coalesce) = handle_bridge_msg(&msg, &memo_id, doc, title, data, panel, link_for, link_pos, focus_req, dom_set, md_edit, active_edit, sel_block, manifest, hist, hist_idx, hist_clock, epoch, focus_hint, ed_scroll, card_caret, card_menu, card_edit, media_req, &persist);
                    let after = serde_json::to_string(&*doc.read()).unwrap_or_default();
                    if !skip_hist && after != before {
                        hist_push(hist, hist_idx, hist_clock, after, coalesce);
                    }
                }
                diag::log("EDIT", "bridge channel closed");
            });
        });
    }

    // 尾随空段模型化（会话内续补）：失焦转预览、删块、转换
    // 等让新的尾随位置出现时，把真实空段落补进模型（原版
    // ensureTrailing 在预览转换时点补段、首次同步即入
    // docRef 的等价）。订阅 doc 与编辑态：插入后同一位置不
    // 再命中，effect 再跑必为 0 处、自稳；源码编辑中的块其
    // 后不补（其失焦消息清掉 active_edit 后本 effect 续跑
    // 再补，与原版转换时点对齐）。补段不走 persist（各 op
    // 自行落盘、返回时全量落盘兜底），不压撤销栈（快照在桥
    // 循环按 handle 前后 JSON 判定，与本 effect 互不干扰）。
    use_effect(move || {
        let editing = active_edit
            .read()
            .clone()
            .or_else(|| md_edit.read().clone());
        let mut d = doc.read().clone();
        let n = materialize_trails(&mut d, editing.as_deref());
        if n > 0 {
            doc.set(d);
            diag::log("EDIT", &format!("trail materialized x{n}"));
        }
    });

    // 结构操作后的光标恢复
    use_effect(move || {
        let req = focus_req.read().clone();
        if let Some((bid, off)) = req {
            focus_req.set(None);
            spawn(async move {
                let js = format!(
                    "if (window.__mnFocus) window.__mnFocus({}, {}); dioxus.send(null);",
                    serde_json::to_string(&bid).unwrap_or_default(),
                    off
                );
                let mut eval = document::eval(&js);
                let _ = eval.recv::<Value>().await;
            });
        }
    });

    // 多行粘贴后，当前块的 DOM 由桥按模型回写（非受控块不会
    // 自己重渲染）并把光标放到首行末尾
    use_effect(move || {
        let req = dom_set.read().clone();
        if let Some((bid, html, off)) = req {
            dom_set.set(None);
            spawn(async move {
                let js = format!(
                    "if (window.__mnSetHtml) window.__mnSetHtml({}, {}, {}); dioxus.send(null);",
                    serde_json::to_string(&bid).unwrap_or_default(),
                    serde_json::to_string(&html).unwrap_or_default(),
                    off
                );
                let mut eval = document::eval(&js);
                let _ = eval.recv::<Value>().await;
            });
        }
    });

    // 斜杠面板的点击在 Editor 作用域里执行（SlashPanel 点击后
    // 立即卸载，它自己 spawn 的异步会被一并取消——踩过）。
    // 按命令类别分流：行内命令走 __mnInline 就地执行；图片/画廊
    // 走文件选择替换当前块；其余走 strip + op_convert。
    {
        let persist = persist.clone();
        use_effect(move || {
            let click = slash_click.read().clone();
            if let Some((bid, act)) = click {
                slash_click.set(None);
                slash_record_recent(&act);
                let persist = persist.clone();
                if INLINE_ACTS.contains(&act.as_str()) {
                    spawn(async move {
                        let js = format!(
                            "dioxus.send(window.__mnInline ? window.__mnInline({}, {}) : '');",
                            serde_json::to_string(&act).unwrap_or_default(),
                            serde_json::to_string(&bid).unwrap_or_default()
                        );
                        let mut eval = document::eval(&js);
                        let html = eval.recv::<String>().await.unwrap_or_default();
                        let mut d = doc.read().clone();
                        if let Some(loc) = find_loc(&d, &bid) {
                            node_at_mut(&mut d, loc).children =
                                Some(editor_html_to_inlines(&html));
                            doc.set(d.clone());
                            persist.call(d, title.read().clone(), data);
                            diag::log("EDIT", &format!("slash inline {act} {bid}"));
                        }
                    });
                } else if act == "image" || act == "gallery" {
                    // 占位块路径（S4）：落占位块 + 尾随空段，不在
                    // 应用瞬间弹文件选择器
                    let mut doc2 = doc;
                    let mut focus_req2 = focus_req;
                    op_insert_media_placeholder(&mut doc2, &bid, act == "gallery", &mut focus_req2);
                    persist.call(doc2.read().clone(), title.read().clone(), data);
                } else {
                    spawn(async move {
                        let js = format!(
                            "dioxus.send(window.__mnStripSlash ? window.__mnStripSlash({}) : '');",
                            serde_json::to_string(&bid).unwrap_or_default()
                        );
                        let mut eval = document::eval(&js);
                        let html = eval.recv::<String>().await.unwrap_or_default();
                        let mut doc = doc;
                        let mut focus_req = focus_req;
                        let mut md_edit = md_edit;
                        let mut dom_set = dom_set;
                        if let Some(src) = op_convert(&mut doc, &bid, &act, &html, &mut focus_req, &mut md_edit) {
                            // md 源转换：DOM 回写为源码（<br> 换行）并聚焦
                            let esc = src
                                .replace('&', "&amp;")
                                .replace('<', "&lt;")
                                .replace('>', "&gt;")
                                .replace('\n', "<br>");
                            let len = src.chars().count();
                            dom_set.set(Some((bid.clone(), esc, len)));
                        }
                        persist.call(doc.read().clone(), title.read().clone(), data);
                    });
                }
            }
        });
    }

    // 链接表单提交：__mnStripSlash 后 __mnApplyLink（桥内恢复
    // 打开表单前保存的选区），返回的 HTML 对齐模型
    {
        let persist = persist.clone();
        use_effect(move || {
            let click = link_click.read().clone();
            if let Some((bid, url)) = click {
                link_click.set(None);
                link_for.set(None);
                slash_record_recent("link");
                let persist = persist.clone();
                spawn(async move {
                    let js = format!(
                        "if (window.__mnStripSlash) window.__mnStripSlash({0}); dioxus.send(window.__mnApplyLink ? window.__mnApplyLink({1}, {0}) : '');",
                        serde_json::to_string(&bid).unwrap_or_default(),
                        serde_json::to_string(&url).unwrap_or_default()
                    );
                    let mut eval = document::eval(&js);
                    let html = eval.recv::<String>().await.unwrap_or_default();
                    let mut d = doc.read().clone();
                    if let Some(loc) = find_loc(&d, &bid) {
                        node_at_mut(&mut d, loc).children =
                            Some(editor_html_to_inlines(&html));
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        diag::log("EDIT", &format!("slash link {bid}"));
                    }
                });
            }
        });
    }

    // 滚动量订阅：标题坞紧凑态切换（>30px）。监听器具名挂在
    // window 上、重挂前先摘旧的、卸载时在 use_drop 里摘除——
    // 匿名监听无移除路径会逐周期泄漏（滚动审计 S4）。
    use_effect(move || {
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnEdScroll) window.removeEventListener('scroll', window.__mnEdScroll); let last = -1; const f = () => { const y = window.scrollY || 0; if (Math.abs(y - last) > 2) { last = y; dioxus.send(y); } }; window.__mnEdScroll = f; window.addEventListener('scroll', f, { passive: true }); f();",
            );
            while let Ok(y) = eval.recv::<f64>().await {
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
                // （closeExportPanel：220ms 过渡后卸载并关菜单）
                if *show_export.read() {
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

    // Esc 关闭浮层（编辑态审计 B12，原版菜单组件的 document
    // 级 Esc 口径）：菜单/导出/背景底表/链接表单/斜杠面板统一
    // 关；监听具名登记，卸载时在 use_drop 里摘除。
    let memo_id_esc = memo_id.clone();
    let persist_esc = persist.clone();
    use_effect(move || {
        let memo_id_esc = memo_id_esc.clone();
        let persist_esc = persist_esc.clone();
        spawn(async move {
            let mut eval = document::eval(
                "if (window.__mnEsc) document.removeEventListener('keydown', window.__mnEsc, true); const f = (e) => { if (e.key === 'Escape') dioxus.send('esc'); }; window.__mnEsc = f; document.addEventListener('keydown', f, true);",
            );
            while let Ok(msg) = eval.recv::<String>().await {
                if msg == "esc" {
                    // 图文面板层级最高（z 4001）先关：原版
                    // ImageTextSheet 自带 Esc → closeWithAnim；
                    // 本版按遮罩点击同路，编辑中先存盘再出场
                    if let Some((bid, _)) = text_sheet.read().clone() {
                        if *sheet_edit.read() {
                            save_sheet_text(
                                doc,
                                title,
                                data,
                                &persist_esc,
                                &bid,
                                &sheet_draft.read().clone(),
                            );
                        }
                        animate_text_sheet_close(text_sheet, text_sheet_closing, text_sheet_gen);
                    }
                    // 卡片浮层菜单/编辑态（卡片交互专项）：Esc
                    // 先关菜单，其次退出编辑态。
                    let ce_esc = card_edit.read().clone();
                    if card_menu.read().is_some() {
                        card_menu.set(None);
                    } else if let Some(b) = ce_esc {
                        card_edit.set(None);
                        diag::log("EDIT", &format!("card edit exit {b} (esc)"));
                    }
                    if *show_export.read() {
                        // 原版 Esc 关导出面板走 closeExportPanel
                        // 动画并把焦点还给 ••• 按钮
                        animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
                    } else if *menu_open.read() {
                        animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                    }
                    if *bg_open.read() {
                        animate_bg_close(bg_open, bg_closing, bg_gen, BgAfter::None, data, bg, memo_id_esc.clone());
                    }
                    if link_for.read().is_some() {
                        link_for.set(None);
                    }
                    if panel.read().is_some() {
                        panel.set(None);
                    }
                }
            }
        });
    });

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

    // 压暗栈（App 层 context）：scheme 分支直写根色时须按栈
    // 现值取派生同值（见下方 scheme 分支注）。
    let dim_stack = use_context::<DimStack>();
    // 深浅模式切换通知（原版 editor.js useLayoutEffect 的方
    // 案半边）：mq 翻转时通知 Rust——bump 本地 scheme_tick
    // （Editor 主体渲染期订阅，是编辑器深浅重渲染的唯一触
    // 发源）并同任务直写根背景变量（压暗口径，见 handler
    // 注）。mq 监听登记 __mnSchemeCleanup（安装前先调上一
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
                    // 深浅切换与换色同口径（背景同步根治）：根
                    // 背景变量按新 scheme 同任务重写，不走
                    // eval/rAF；App 派生随后重申同值。压暗在场
                    // （如灯箱开着时系统切深浅色）必须写派生同
                    // 值：本分支不触任何派生输入、与 App 的
                    // scheme 监听（spawn_scheme_listener）无定
                    // 序，直写未压暗值一旦后到即把根色粘在原
                    // 色、无后续重派生纠正（带区露未压暗实心
                    // 栏，关灯箱 pop 时才恢复）——现按
                    // DimStack::dimmed 取值（公式与派生同一实
                    // 现）。
                    let base = effective_bg(&bg.peek().clone());
                    let target = dim_stack.dimmed(&base);
                    if target != base {
                        diag::log(
                            "EDIT",
                            &format!("scheme root bg dimmed -> {target}"),
                        );
                    }
                    crate::apply_root_bg(Some(&target));
                }
            }
        });
    });

    // 背景色延伸到安全区（背景同步根治后）：根背景由 App 外
    // 壳按页面状态派生、apply_root_bg 双写落地（html/body 内
    // 联 backgroundColor 为带区权威路径、:root 变量同值镜像；
    // 编辑页打开 = 本篇有效背景，其他页 = 根页面色）；换色的发
    // 起任务（set_bg）同步先行写入同值，故此处不再有刷新
    // effect——旧实现选色后 spawn eval + rAF 读 body 计算色
    // （须等 App 写完）刷新顶部渐变，实测恒晚其余层 1 帧起、
    // 顺序无保证时取旧色，已删；渐变改写装置本身亦已整套移
    // 除（见上方 scheme effect 注）。

    // 卸载清理（同步）：撤编辑器具名全局监听（含 scheme mq
    // 的 __mnSchemeCleanup）。
    // 教训（页面色泄漏根因）：旧实现把清理放在 use_drop 里
    // spawn 出去的 eval 中——spawn 依附组件作用域，卸载即被
    // 取消，清理一次都没执行过（探针实证：返回列表后
    // __mnEsc 仍为 function、html/body 内联背景永久残留）。
    // 清理必须在 use_drop 闭包内同步直调（sync_editor_cleanup）。
    // html/body 根背景由 App 派生，不在此处碰。
    use_drop(move || {
        sync_editor_cleanup();
        // 清理后普查（结果侧证据，诊断覆盖补齐）：stage/编辑
        // 器根/离页层计数与 body 子节点成行；#body-before-bg
        // 恒不存在（bbbg=false）是渐变改写装置已移除的长期
        // 证据。
        diag::log_census("EDIT");
    });

    // 打开时补拉（原版 hydrate）：musicCard/link-card 有 url 且
    // 无标题 meta 或仍在 loading → 逐张解析（挂载快照，只跑一次）
    {
        let persist = persist.clone();
        use_effect(move || {
            let snapshot = doc.peek().clone();
            for n in &snapshot {
                let ty = n.node_type.as_deref().unwrap_or("");
                if ty != "musicCard" && ty != "music" && ty != "link-card" {
                    continue;
                }
                let url = n.extra.get("url").and_then(|v| v.as_str()).unwrap_or("");
                if url.is_empty() {
                    continue;
                }
                let status = n.extra.get("status").and_then(|v| v.as_str()).unwrap_or("");
                let has_title = n
                    .extra
                    .get("meta")
                    .and_then(|m| m.get("title"))
                    .and_then(|v| v.as_str())
                    .map(|s| !s.is_empty())
                    .unwrap_or(false);
                if has_title && status != "loading" {
                    continue;
                }
                if let Some(bid) = n.id.clone() {
                    spawn_resolve_card(doc, bid, url.to_string(), title, data, persist.clone(), None, None);
                }
            }
        });
    }

    // 卡片重试（原版 retryMusicCard）：先置 loading 再解析
    {
        let persist = persist.clone();
        use_effect(move || {
            let retry_req = card_retry.read().clone();
            if let Some(bid) = retry_req {
                card_retry.set(None);
                let mut d = doc.read().clone();
                if let Some(loc) = find_loc(&d, &bid) {
                    let url = {
                        let n = node_at_mut(&mut d, loc);
                        n.extra.insert("meta".into(), serde_json::Value::Null);
                        n.extra.insert("status".into(), json!("loading"));
                        n.extra
                            .get("url")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string()
                    };
                    if !url.is_empty() {
                        doc.set(d.clone());
                        persist.call(d, title.read().clone(), data);
                        diag::log("CARD", &format!("retry {bid}"));
                        spawn_resolve_card(doc, bid, url, title, data, persist.clone(), None, None);
                    }
                }
            }
        });
    }

    // Wiki 导航：收到 target 后先落盘当前 doc/title（原版
    // flushAutoSave 后导航；落盘失败也照样导航，仅记日志），
    // 再回调宿主解析目标（命中打开 / 未命中新建同名备忘）。
    {
        let persist = persist.clone();
        let on_open_wiki = on_open_wiki.clone();
        let from_id = memo_id.clone();
        use_effect(move || {
            let req = wiki_nav.read().clone();
            if let Some(target) = req {
                wiki_nav.set(None);
                persist.call(doc.read().clone(), title.read().clone(), data);
                diag::log("WIKI", &format!("nav '{target}' from {from_id}"));
                on_open_wiki.call(target);
            }
        });
    }

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

    // 图文面板打开时重置草稿（编辑态从只读开始）
    use_effect(move || {
        if let Some((_, t)) = text_sheet.read().clone() {
            sheet_draft.set(t);
            sheet_edit.set(false);
        }
    });

    // 返回：全量同步 → 落库 → 关页；空笔记（无文本、无卡片块、
    // 无背景、标题为空）按原版规则关闭即删除
    let go_back = {
        let memo_id = memo_id.clone();
        let state_owner = state_owner.clone();
        let initial_title = initial_title.clone();
        move |_| {
            // 标题未提交文本先行落定：Controller 只在失焦等
            // 时机写标题信号，点返回不触发标题失焦（iOS 点
            // 按钮不转移焦点），在此同步失焦把会话提交了再
            // 走关闭流程（空备忘判定与落盘标题都读现值）。
            blur_title_if_focused();
            let memo_id = memo_id.clone();
            let state_owner = state_owner.clone();
            let initial_title = initial_title.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                );
                let mut d = doc.read().clone();
                match eval.recv::<String>().await {
                    Ok(s) => apply_sync_map(&mut d, &s),
                    Err(e) => {
                        diag::log("EDIT", &format!("back-sync recv err: {e:?}"))
                    }
                }
                doc.set(d.clone());
                let has_text = d.iter().any(|b| !b.plain_text().trim().is_empty());
                let has_card = d.iter().any(|b| {
                    matches!(
                        b.node_type.as_deref(),
                        Some(
                            "image"
                                | "video"
                                | "music"
                                | "attachment"
                                | "link-card"
                                | "gallery"
                                | "divider"
                        )
                    )
                });
                let norm_title = |v: &str| {
                    let t = v.trim();
                    if t.is_empty() { "无标题".to_string() } else { t.to_string() }
                };
                let empty = is_new
                    && !*typed.read()
                    && !has_text
                    && !has_card
                    && bg.read().is_none()
                    && avatar_url.read().is_none()
                    && norm_title(&title.read()) == norm_title(&initial_title);
                if empty {
                    // 出场（栈式交接口径）：即刻 on_close——App
                    // 把本实例留在编辑器槽位翻 closing 播
                    // slideOut 并计时卸载（旧串行口径在此等待
                    // 320ms 播满才关页，已退役）。on_close 先于
                    // data.set 的次序与理由不动，见下注。
                    diag::log("EDIT", "page exit slideOut");
                    // 先 on_close 再删数据：若先 data.set，App 会因
                    // sel_memo 查无此备忘而提前渲染列表并卸载编辑器，
                    // 本 spawn 随即在 save_backup 的 await 点被取消，
                    // on_close 永不执行、列表滚动恢复（S1）失效
                    //（实测：新建空备忘返回列表时滚动恒为 0）。
                    // 栈式交接下 on_close 只翻离页条目、实例以
                    // 槽位键留存，删除后本实例改由离页条目持有
                    // 渲染（不再依赖 data 查得此备忘）。
                    on_close.call(());
                    let mut backup = data.read().clone();
                    backup.memos.retain(|m| m.id.to_string() != memo_id);
                    data.set(backup.clone());
                    diag::log("EDIT", &format!("close empty memo -> deleted {memo_id}"));
                    save_backup(&backup).await;
                    return;
                }
                // 双栏开启时把归一化 layout 一并落库（原版
                // 保存路径 captureCurrentColumnLayout 口径）
                let boundary = if *twopane.read() {
                    let cur = data
                        .read()
                        .memos
                        .iter()
                        .find(|m| m.id.to_string() == memo_id)
                        .and_then(|m| m.extra.get("layout").cloned());
                    Some(column_boundary(&d, cur.as_ref()))
                } else {
                    None
                };
                // 守卫拒写（状态归属与写目标不一致）时整笔跳
                // 过保存：layout 派生同出自本实例 doc、随合并
                // 一并跳过；退出流程本身不受守卫拦截，下方
                // on_close 照常执行。
                if let Some(mut backup) =
                    build_backup(data, &memo_id, &state_owner, d.clone(), title.read().clone())
                {
                    if let Some(b) = boundary {
                        if let Some(m) = backup
                            .memos
                            .iter_mut()
                            .find(|m| m.id.to_string() == memo_id)
                        {
                            let ids: Vec<Value> = d
                                .iter()
                                .map(|n| {
                                    Value::String(
                                        n.id.as_ref()
                                            .map(|i| i.to_string())
                                            .unwrap_or_default(),
                                    )
                                })
                                .collect();
                            let (left, right) = ids.split_at(b.min(ids.len()));
                            m.extra.insert(
                                "layout".to_string(),
                                json!({"version": 1, "mode": "independent", "left": left, "right": right}),
                            );
                        }
                    }
                    data.set(backup.clone());
                    save_backup(&backup).await;
                }
                // 出场（原版 handleClose 尾段的次序保留、形态
                // 改栈式交接）：保存完成即刻 on_close，App 把
                // 本实例留在槽位翻 closing 播 slideOut 并计时
                // 卸载（旧口径在此等待 320ms 播满才卸载，已
                // 退役——等待期正是新页进场被串行门控的来源）。
                diag::log("EDIT", "page exit slideOut");
                on_close.call(());
            });
        }
    };

    // 撤销/重做：与键盘路径共用 step_undo/step_redo（先全量同步
    // 当前 DOM 并压栈，再回退快照整体重挂载，并恢复焦点到最近
    // 编辑块——编辑态审计 D2/D4）。菜单从鼠标打开、桥不在场，
    // 同步串靠一次 eval 向桥索取。
    let do_undo = {
        let persist = persist.clone();
        move |_| {
            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
            let persist = persist.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                );
                let sync = eval.recv::<String>().await.ok();
                step_undo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    &persist, data, &title, sync.as_deref(), focus_hint.read().clone(),
                );
            });
        }
    };

    let do_redo = {
        let persist = persist.clone();
        move |_| {
            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
            let persist = persist.clone();
            spawn(async move {
                let mut eval = document::eval(
                    "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                );
                let sync = eval.recv::<String>().await.ok();
                step_redo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    &persist, data, &title, sync.as_deref(), focus_hint.read().clone(),
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
                ed_status2.show("success", crate::i18n::t("export.done"));
                diag::log("EDIT", &format!("export md memo={memo_id} {}B", md.len()));
            });
        }
    };

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
                let b = column_boundary(&d, m.extra.get("layout"));
                let ids: Vec<Value> = d
                    .iter()
                    .map(|n| Value::String(n.id.as_ref().map(|i| i.to_string()).unwrap_or_default()))
                    .collect();
                let (left, right) = ids.split_at(b.min(ids.len()));
                m.extra.insert(
                    "layout".to_string(),
                    json!({
                        "version": 1,
                        "mode": if next { "independent" } else { "flow" },
                        "left": left,
                        "right": right,
                    }),
                );
            }
            data.set(backup.clone());
            diag::log("EDIT", &format!("twopane -> {next}"));
            spawn(async move {
                save_backup(&backup).await;
            });
        }
    };

    let doc_snapshot = doc.read().clone();
    let panel_state = panel.read().clone();

    let bg_state = bg.read().clone();
    let menu_state = *menu_open.read();
    let menu_closing_state = *menu_closing.read();
    let bg_sheet_state = *bg_open.read();
    let bg_closing_state = *bg_closing.read();
    let sheet_closing_state = *text_sheet_closing.read();
    let can_undo = *hist_idx.read() > 0;
    let can_redo = *hist_idx.read() + 1 < hist.read().len();
    let words = orig_char_count(&doc_snapshot);
    let sub_line = format!(
        "{} · {}",
        time_label(memo.updated_at.to_millis().unwrap_or(0)),
        crate::i18n::tf("editor.words", &[("n", &words.to_string())])
    );
    let ed_status_text = ed_status.msg.read().clone();
    let ed_status_seq = *ed_status.seq.read();
    let ed_status_kind = *ed_status.kind.read();
    let persist_attach = persist.clone();
    // 导出 HTML / PDF（原版导出面板的另两条路径）
    let export_html = {
        let memo_id = memo_id.clone();
        let memo_upd_ts = memo.updated_at.clone();
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
                // E-2：HTML 导出用专属文案键，此前误用 MD 的
                // export.done、toast 误显示「已导出 Markdown」
                ed_status2.show("success", crate::i18n::t("export.done_html"));
                diag::log("EDIT", &format!("export html memo={memo_id} {}B", html.len()));
            });
        }
    };
    let export_pdf = {
        let memo_id = memo_id.clone();
        let memo_upd_ts = memo.updated_at.clone();
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
            let ed_status2 = ed_status;
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
                    ed_status2.show("error", crate::i18n::t("export.pdf_blocked"));
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
                    ed_status2.show("error", crate::i18n::t("export.pdf_failed"));
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
                    ed_status2.show("error", crate::i18n::t("export.pdf_failed"));
                    diag::log("EDIT", "export pdf window gone before write");
                }
            });
        }
    };

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

    // 媒体文件选择完成：按 media_req 分发（替换块 / 图文换图）
    let on_media_files = {
        let persist = persist.clone();
        move |_| {
            let persist = persist.clone();
            spawn(async move {
                handle_media_files(doc, title, data, manifest, media_req, &persist).await;
            });
        }
    };

    let _scheme = *scheme_tick.read();
    let scrolled = *ed_scroll.read() > 30.0;
    let avatar_state = avatar_url.read().clone();
    // 标题坞：胶囊子树已静态壳化（TitleCapsule，见 title.rs）
    // ——渲染路径不再计算标题的类/几何，全部归 TitleController。
    let meta_line = format!(
        "{} · {}",
        crate::list::time_ago(&memo.updated_at),
        crate::i18n::tf("editor.words", &[("n", &words.to_string())])
    );
    let sheet_state = text_sheet.read().clone();
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
    let sheet_editing = *sheet_edit.read();
    let twopane_state = *twopane.read();
    // 双栏（宽屏）：左右恒为两个物理栏容器，成员由分界
    // 决定（锚优先、无锚规范估高——column_boundary）。独
    // 立滚动开关只切换滚动形态（栏内滚 vs 整页滚），不切
    // 换成员。此前 flow 形态走 CSS 多列：成员由浏览器按
    // 实测高平衡，卡片/图片加载前后分界漂移、回来再进来
    // 块跨栏迁移，且与独立形态成员不一致。
    let two_col = twopane_state && *wide.read();
    let show_cols = *wide.read();
    let boundary = if show_cols {
        let layout = data
            .read()
            .memos
            .iter()
            .find(|m| m.id.to_string() == memo_id)
            .and_then(|m| m.extra.get("layout").cloned());
        column_boundary(&doc_snapshot, layout.as_ref())
    } else {
        0
    };
    // 尾随空段已在模型层（materialize_trails 于打开时与会
    // 话内 effect 补齐），渲染无需再算视图层尾随位置。
    // 跨块列表组合并（M6）：按流区间预计算渲染单元；双栏
    // 左右栏各自成流、不跨栏成组（原版同流相邻才成组）。
    let editing_id = md_edit.read().clone();
    let active_id = active_edit.read().clone();
    // PERF（第八批 T2）：三组 runs 此前每渲无条件全算，但
    // 渲染端只消费其中一组（宽屏用 left/right、窄屏用
    // all），另两组是纯浪费（每组逐块 plain_text +
    // md_classify）。按 show_cols 只算会被消费的组，未用
    // 组留空 Vec——rsx 分支与所用组严格对应，渲染结果
    // 不变。
    let (runs_all, runs_left, runs_right) = if show_cols {
        (
            Vec::new(),
            flow_runs(
                &doc_snapshot,
                0..boundary,
                editing_id.as_deref(),
                active_id.as_deref(),
            ),
            flow_runs(
                &doc_snapshot,
                boundary..doc_snapshot.len(),
                editing_id.as_deref(),
                active_id.as_deref(),
            ),
        )
    } else {
        (
            flow_runs(
                &doc_snapshot,
                0..doc_snapshot.len(),
                editing_id.as_deref(),
                active_id.as_deref(),
            ),
            Vec::new(),
            Vec::new(),
        )
    };
    let export_open = *show_export.read();
    let export_is_closing = *export_closing.read();
    // 全关关闭中（遮挡续修）：命中即刻释放——遮罩在卸载
    // 计时落定前不再拦截点按，计时停摆也锁不住页面；回
    // 菜单的关闭不释放（菜单仍在场，遮罩归菜单所有）。
    let export_releasing = export_is_closing
        && *export_anim.read() == EXPORT_ANIM_CLOSING
        && !*export_to_menu.read();
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
    let link_state = link_for.read().clone();
    let (link_x, link_top, link_bottom) = *link_pos.read();
    // 根节点进/出场（原版 editor.js 根 style 三态，时长/曲线
    // 字面量与原版一致、不走 var()）：关闭中 slideOut
    // forwards；进场 slideIn both、animDone 后摘除。摘除不能
    // 用空串：dioxus-web 的 style 保留路径只覆写不删属性，
    // 声明从 style 串里消失不会从 CSSOM 移除（计时与置位
    // 均实测到达、动画却常驻），须显式 animation:none 覆写
    let page_anim = if closing {
        "animation:slideOutToRight 0.28s cubic-bezier(0.22,0.61,0.36,1) forwards;"
    } else if *page_anim_done.read() {
        "animation:none;"
    } else {
        "animation:slideInFromRight 0.28s cubic-bezier(0.22,0.61,0.36,1) both;"
    };

    rsx! {
        div {
            id: "editor-root",
            // 有效背景（自定义色深色压暗 / 默认 #FAFAFA / 深色 #000）；
            // 写具体色不用 var()（CSSOM 对 var() 简写静默拒绝的坑）。
            // 恒自带有效背景、关闭中不改 transparent：离页窗口
            // 内页面状态未提交（Nav 提交点后移，selected 保留
            // 至卸载帧），根色派生同刻给出同一备忘的有效背景，
            // 本节点自有底与根色单源同值——不是异色第二来源，
            // 编辑器以自身底色出场、衬底不透入页色；提交帧本
            // 实例卸载与根色翻值同属一次渲染提交（返回列表顶
            // 部白带定案终版，见 main.rs 根色派生注）。曾试
            // closing 改 transparent：带区虽正，衬底透出列表
            // 色 8 色阶成交换式残差，已回退。
            style: format!(
                "background:{};{}",
                effective_bg(&bg_state),
                page_anim
            ),
            button {
                class: "editor-fab left",
                onclick: go_back,
                dangerous_inner_html: "{crate::icons::back_markup()}",
            }
            button {
                class: "editor-fab right",
                onclick: move |_| {
                    // 同 go_back：菜单动作（导出/删除等）读标题
                    // 信号前，先同步失焦落定标题会话。
                    blur_title_if_focused();
                    // 读信号现值而非渲染期快照：状态刚变而未重渲染时
                    // 快照会让开关方向反转（冒烟实测踩过）
                    if *menu_open.read() {
                        if *export_anim.read() == EXPORT_ANIM_CLOSING {
                            // 导出面板关闭中点按 = 改道回菜单，不
                            // 重排关闭（原版 toggleEditorMenu 与面
                            // 板状态机解耦、点按永不被面板吞掉；
                            // Rust 合并架构的等价落点是关闭照常落
                            // 定、终点由全关改为菜单）。去向在关
                            // 闭完成时按 export_to_menu 现值结算
                            // （见 animate_export_close），计时与
                            // 动画不重启；已是回菜单去向时无操作。
                            if !*export_to_menu.read() {
                                export_to_menu.set(true);
                                diag::log("EDIT", "export close diverted to menu");
                            }
                        } else if *show_export.read() {
                            animate_export_close(show_export, export_closing, menu_open, export_gen, export_anim, export_to_menu, false);
                        } else if *menu_closing.read() {
                            // 关闭中再按 = 重开（原版 toggle 在
                            // menuClosing 时走 openEditorMenu 清计时）
                            cancel_menu_close(menu_gen, menu_closing);
                        } else {
                            animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                        }
                    } else {
                        // 开菜单（原版 openEditorMenu 口径）：挂载即
                        // closing 态，双 rAF 后撤下让 transition 弹
                        // 簧入场；入场代际守卫——未落定即被关闭/重
                        // 开取代时不得把面板翻回。
                        let gen = *menu_gen.read() + 1;
                        menu_gen.set(gen);
                        spawn(async move {
                            let mut eval = document::eval(
                                "dioxus.send(window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()) : '{}');",
                            );
                            let mut d = doc.read().clone();
                            if let Ok(s) = eval.recv::<String>().await {
                                apply_sync_map(&mut d, &s);
                                doc.set(d.clone());
                                hist_push(
                                    hist,
                                    hist_idx,
                                    hist_clock,
                                    serde_json::to_string(&d).unwrap_or_default(),
                                    false,
                                );
                            }
                            if *menu_gen.read() != gen {
                                return;
                            }
                            menu_closing.set(true);
                            menu_open.set(true);
                            // 同 begin_export_open 的双触发口径：
                            // rAF 为主、setTimeout 兜底防唤醒丢失
                            let mut eval2 = document::eval(
                                "requestAnimationFrame(() => requestAnimationFrame(() => dioxus.send(null))); setTimeout(() => dioxus.send(null), 150);",
                            );
                            let _ = eval2.recv::<Value>().await;
                            if *menu_gen.read() != gen {
                                return;
                            }
                            menu_closing.set(false);
                        });
                    }
                },
                dangerous_inner_html: "{crate::icons::dots_markup()}",
            }
            div {
                class: if scrolled { "editor-title-dock scrolled" } else { "editor-title-dock" },
                label {
                    class: "editor-avatar-button",
                    style: if avatar_state.is_some() { "border:none;background:transparent;backdrop-filter:none;-webkit-backdrop-filter:none" } else { "" },
                    if let Some(u) = &avatar_state {
                        img { src: "{u}", style: "width:100%;height:100%;object-fit:cover;border-radius:50%;display:block" }
                    } else {
                        span { dangerous_inner_html: "{crate::icons::dino_markup(60, 10)}" }
                    }
                    input {
                        id: "file-avatar",
                        r#type: "file",
                        accept: "image/*",
                        class: "hidden-input",
                        onchange: pick_avatar,
                    }
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
            if !ed_status_text.is_empty() {
                // key = seq（非文案）：同文案重触发也重挂（审计
                // G1）；形态与备份页同规格全宽条（审计 G2）
                div { key: "{ed_status_seq}", class: "backup-toast",
                    if ed_status_kind == "info" {
                        span { class: "backup-toast-spinner" }
                    } else if ed_status_kind == "success" {
                        span { class: "backup-toast-icon", "✅" }
                    } else {
                        span { class: "backup-toast-icon", "❌" }
                    }
                    span { class: "backup-toast-text", "{ed_status_text}" }
                }
            }
            if let Some((cm_style, cm_has_edit)) = card_menu_view.clone() {
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
                                                            n.extra.insert("url".into(), json!(url.clone()));
                                                            n.extra.insert("meta".into(), serde_json::Value::Null);
                                                            n.extra.insert("status".into(), json!("loading"));
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
            if menu_state {
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
                        button {
                            class: if can_undo { "menu-item" } else { "menu-item dis" },
                            disabled: !can_undo,
                            onclick: do_undo,
                            span { class: "menu-icon", crate::icons::Icon { name: "undo".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.undo\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.undo_sub\")}" }
                            }
                        }
                        button {
                            class: if can_redo { "menu-item" } else { "menu-item dis" },
                            disabled: !can_redo,
                            onclick: do_redo,
                            span { class: "menu-icon", crate::icons::Icon { name: "redo".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.redo\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.redo_sub\")}" }
                            }
                        }
                        label { class: "menu-item", style: "margin-top:4px", r#for: "file-attach",
                            span { class: "menu-icon", crate::icons::Icon { name: "attach".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.attach\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.attach_sub\")}" }
                            }
                        }
                        div { class: "menu-section",
                            button {
                                class: "menu-item",
                                onclick: open_export,
                                span { class: "menu-icon", crate::icons::Icon { name: "export".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
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
                            span { class: "menu-icon", crate::icons::Icon { name: "palette".to_string(), size: 20, stroke_width: "2.5".to_string(), stroke: "var(--color-accent)".to_string() } }
                            span { class: "menu-copy",
                                span { class: "menu-title", "{crate::i18n::t(\"menu.bg\")}" }
                                span { class: "menu-sub", "{crate::i18n::t(\"menu.bg_sub\")}" }
                            }
                        }
                    }
                }
            }
            if bg_sheet_state {
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
                            for c in BG_COLORS {
                                button {
                                    key: "{c}",
                                    class: if bg_state.as_deref() == Some(c) { "bg-dot sel" } else { "bg-dot" },
                                    style: "background:{c}",
                                    onclick: {
                                        let mut set_bg = set_bg.clone();
                                        move |_| set_bg(Some(c.to_string()))
                                    },
                                    if bg_state.as_deref() == Some(c) {
                                        span { dangerous_inner_html: "{crate::icons::svg_markup(\"check\", 20, \"2.5\", \"#007AFF\")}" }
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
                                            crate::icons::Icon { name: "del".to_string(), size: 17, stroke_width: "2.5".to_string(), stroke: "var(--color-danger-bright)".to_string() }
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
            div {
                class: if twopane_state { "detail spread" } else { "detail" },
                key: "{epoch}",
                div { class: "editor-pad editor-spread",
                    if show_cols {
                        div { class: {
                            let mut c = if two_col { "editor-body is-independent-scroll".to_string() } else { "editor-body is-flow-columns".to_string() };
                            if !*typed.read()
                                && doc_snapshot.len() == 1
                                && doc_snapshot[0].node_type.as_deref() == Some("paragraph")
                                && doc_snapshot[0].plain_text().trim().is_empty()
                            {
                                c.push_str(" show-placeholder");
                            }
                            c
                        },
                            div { class: "editor-column", "data-editor-column": "left",
                                for run in runs_left.iter() {
                                    {
                                        match run {
                                            FlowRun::Single(bi) => {
                                                let block = &doc_snapshot[*bi];
                                                rsx! {
                                                    EditorBlock { key: "{epoch}-{block.id.clone().unwrap_or_default()}", node: block.clone(), gen, doc, title, data, persist: persist.clone(), media_req }
                                                }
                                            }
                                            FlowRun::ListGroup(idxs) => {
                                                let gtext = idxs.iter().map(|&ix| doc_snapshot[ix].plain_text().trim().to_string()).collect::<Vec<_>>().join("\n");
                                                let gbids: Vec<String> = idxs.iter().map(|&ix| doc_snapshot[ix].id.clone().unwrap_or_default()).collect();
                                                let gfirst = gbids.first().cloned().unwrap_or_default();
                                                let glast = *idxs.last().unwrap();
                                                rsx! {
                                                    MergedListPreview { key: "{epoch}-lg-{gfirst}", bids: gbids, text: gtext, doc, title, data, persist: persist.clone() }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            div { class: "editor-column", "data-editor-column": "right",
                                for run in runs_right.iter() {
                                    {
                                        match run {
                                            FlowRun::Single(bi) => {
                                                let block = &doc_snapshot[*bi];
                                                rsx! {
                                                    EditorBlock { key: "{epoch}-{block.id.clone().unwrap_or_default()}", node: block.clone(), gen, doc, title, data, persist: persist.clone(), media_req }
                                                }
                                            }
                                            FlowRun::ListGroup(idxs) => {
                                                let gtext = idxs.iter().map(|&ix| doc_snapshot[ix].plain_text().trim().to_string()).collect::<Vec<_>>().join("\n");
                                                let gbids: Vec<String> = idxs.iter().map(|&ix| doc_snapshot[ix].id.clone().unwrap_or_default()).collect();
                                                let gfirst = gbids.first().cloned().unwrap_or_default();
                                                let glast = *idxs.last().unwrap();
                                                rsx! {
                                                    MergedListPreview { key: "{epoch}-lg-{gfirst}", bids: gbids, text: gtext, doc, title, data, persist: persist.clone() }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        div { class: if !*typed.read()
                            && doc_snapshot.len() == 1
                            && doc_snapshot[0].node_type.as_deref() == Some("paragraph")
                            && doc_snapshot[0].plain_text().trim().is_empty()
                        { "editor-body show-placeholder" } else { "editor-body" },
                            for run in runs_all.iter() {
                                {
                                    match run {
                                        FlowRun::Single(bi) => {
                                            let block = &doc_snapshot[*bi];
                                            rsx! {
                                                EditorBlock { key: "{epoch}-{block.id.clone().unwrap_or_default()}", node: block.clone(), gen, doc, title, data, persist: persist.clone(), media_req }
                                            }
                                        }
                                        FlowRun::ListGroup(idxs) => {
                                            let gtext = idxs.iter().map(|&ix| doc_snapshot[ix].plain_text().trim().to_string()).collect::<Vec<_>>().join("\n");
                                            let gbids: Vec<String> = idxs.iter().map(|&ix| doc_snapshot[ix].id.clone().unwrap_or_default()).collect();
                                            let gfirst = gbids.first().cloned().unwrap_or_default();
                                            let glast = *idxs.last().unwrap();
                                            rsx! {
                                                MergedListPreview { key: "{epoch}-lg-{gfirst}", bids: gbids, text: gtext, doc, title, data, persist: persist.clone() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                {
                    // 反向链接（原版 editor.js:3271-3284）：引用本篇
                    // 标题的备忘现算列表，非空才渲染；条目点击直接
                    // 导航（来源必存在，不新建）。切篇前先落盘。
                    let backlinks = backlinks_cached(&bl_cache, &data.read().memos, &memo_id, &title.read());
                    if backlinks.is_empty() {
                        rsx! {}
                    } else {
                        let bl_aria = crate::i18n::t("editor.backlinks_aria");
                        let bl_title = crate::i18n::t("editor.backlinks");
                        rsx! {
                            section { class: "wiki-backlinks", "aria-label": "{bl_aria}",
                                h2 { class: "wiki-backlinks-title", "{bl_title}" }
                                div { class: "wiki-backlinks-list",
                                    for (sid, stitle) in backlinks.iter() {
                                        {
                                            let stitle = stitle.clone();
                                            let persist_b = persist.clone();
                                            let label = if stitle.trim().is_empty() { crate::i18n::t("editor.untitled") } else { stitle.clone() };
                                            rsx! {
                                                button {
                                                    key: "{sid}",
                                                    r#type: "button",
                                                    class: "wiki-backlink",
                                                    onclick: move |_| {
                                                        persist_b.call(doc.read().clone(), title.read().clone(), data);
                                                        diag::log("WIKI", &format!("backlink -> '{stitle}'"));
                                                        on_open_wiki.call(stitle.clone());
                                                    },
                                                    "{label}"
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
            input {
                id: "file-attach",
                r#type: "file",
                accept: "image/*,application/pdf,text/plain,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                multiple: true,
                class: "hidden-input",
                onchange: move |_| {
                    animate_menu_close(menu_open, menu_closing, menu_gen, MenuAfter::None, show_export, export_closing, export_gen, export_anim, bg_open);
                    show_export.set(false);
                    let persist = persist_attach.clone();
                    spawn(async move {
                        attach_file(doc, title, data, manifest, &persist, ed_status).await;
                    });
                },
            }
            input {
                id: "file-media",
                r#type: "file",
                accept: "image/*",
                multiple: true,
                class: "hidden-input",
                onchange: on_media_files,
            }
            if let Some(u) = lightbox.read().clone() {
                div {
                    class: "lightbox",
                    // LBX 量测（诊断覆盖补齐）：挂载后（元素已入
                    // DOM、rect/挂载链可实测）记 open 行；点关在
                    // 摘除前记 close 行；异常关闭（编辑器卸载带
                    // 走）由 DimGuard Drop 的 LBX pop 兜底。
                    onmounted: move |_| diag::log_lbx("open"),
                    onclick: move |_| {
                        diag::log_lbx("close");
                        lightbox.set(None);
                    },
                    // 压暗登记（α0.88 与 .lightbox 样式同值）：
                    // 根色派生据此跟随压暗（见 main.rs DimStack）。
                    DimLayer { alpha: 0.88, tag: "lightbox" }
                    img { src: "{u}" }
                }
            }
            if let Some((bid, _txt)) = sheet_state {
                div {
                    class: if sheet_closing_state { "image-text-sheet-backdrop is-closing" } else { "image-text-sheet-backdrop" },
                    // MODAL 量测（审计 §6-4 补 open 行，与
                    // animate_text_sheet_close 的 close 行成对）。
                    onmounted: move |_| diag::log_modal("sheet-media", "open"),
                    onclick: {
                        let persist = persist.clone();
                        let bid_bg = bid.clone();
                        move |_| {
                            if *sheet_edit.read() {
                                save_sheet_text(doc, title, data, &persist, &bid_bg, &sheet_draft.read().clone());
                            }
                            animate_text_sheet_close(text_sheet, text_sheet_closing, text_sheet_gen);
                        }
                    },
                }
                div { class: if sheet_closing_state { "image-text-sheet-wrap is-closing" } else { "image-text-sheet-wrap" },
                    section { class: "image-text-sheet",
                        div { class: "image-text-sheet-header",
                            h2 { "{crate::i18n::t(\"sheet.full_text\")}" }
                        }
                        if sheet_editing {
                            textarea {
                                class: "image-text-sheet-editor",
                                value: "{sheet_draft}",
                                oninput: move |e| sheet_draft.set(e.value()),
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
                                onclick: {
                                    let persist = persist.clone();
                                    move |_| {
                                        if *sheet_edit.read() {
                                            save_sheet_text(doc, title, data, &persist, &bid, &sheet_draft.read().clone());
                                            animate_text_sheet_close(text_sheet, text_sheet_closing, text_sheet_gen);
                                        } else {
                                            sheet_edit.set(true);
                                        }
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
            if let Some((bid, filter, ax, atop, abottom)) = panel_state {
                SlashPanel { bid, filter, anchor_x: ax, anchor_top: atop, anchor_bottom: abottom, panel, slash_click, link_for, link_pos, link_click }
            } else if let Some(bid) = link_state {
                SlashPanel { bid, filter: String::new(), anchor_x: link_x, anchor_top: link_top, anchor_bottom: link_bottom, panel, slash_click, link_for, link_pos, link_click }
            }
        }
    }
}

type PersistFn = dyn Fn(Vec<Node>, String, Signal<BackupFile>) + 'static;

/// 持久化句柄：包一层以满足 Dioxus 组件 props 的 PartialEq 要求。
#[derive(Clone)]
struct PersistHandle(std::rc::Rc<PersistFn>);

impl PartialEq for PersistHandle {
    fn eq(&self, other: &Self) -> bool {
        std::rc::Rc::ptr_eq(&self.0, &other.0)
    }
}

impl PersistHandle {
    fn call(&self, doc: Vec<Node>, title: String, data: Signal<BackupFile>) {
        (self.0)(doc, title, data)
    }
}

/// 块拖拽排序（新增能力）：原版 src/app/editor.js 有一套
/// 从未接线的死实现（onDragStart/onDragOver/onDragEnd 无任
/// 何引用、无元素被设 draggable、活体不可用），其数据语义
/// 在此沿用——remove+insert 重排、双栏时保持分界块数。桥
/// 在落点确认后发 moveBlock{ids, to, sync}：ids 是拖动单元
/// 覆盖的顶层块（列表组为多块），to 是原文档序的插入位
/// （插到该位块之前，to == len 为文末）。先按 sync 全量同
/// 步 DOM 文本（与撤销路径同口径），再重排；layout 锚存在
/// 时按重排前分界块数重写锚（新序在同一切分点分栏，与原
/// 版 afterLayout 及关闭保存的写锚口径一致，normalize 自
/// 洽）；落盘一次，历史由消息循环按文档变化自动压栈（结
/// 构性、断合并链），故撤销可回退。
#[allow(clippy::too_many_arguments)]
fn op_move_block(
    doc: &mut Signal<Vec<Node>>,
    mut data: Signal<BackupFile>,
    memo_id: &str,
    title: &Signal<String>,
    ids: &[String],
    to: usize,
    sync: Option<&str>,
    persist: &PersistHandle,
) {
    if ids.is_empty() {
        return;
    }
    let mut d = doc.read().clone();
    if let Some(s) = sync {
        apply_sync_map(&mut d, s);
    }
    let Some(Loc::Top(start)) = find_loc(&d, &ids[0]) else {
        diag::log(
            "EDIT",
            &format!("move block abort: head {} not top-level", ids[0]),
        );
        return;
    };
    let n = ids.len();
    let contiguous = d.get(start..start + n).is_some_and(|seg| {
        seg.iter()
            .zip(ids.iter())
            .all(|(node, id)| node.id.as_deref() == Some(id.as_str()))
    });
    if !contiguous {
        diag::log("EDIT", "move block abort: ids not contiguous");
        return;
    }
    if to >= start && to <= start + n {
        // 落回原范围 = 顺序无变化；sync 可能带了文本变化，
        // 照常落盘（与菜单打开时的全量同步同义）。
        if sync.is_some() {
            doc.set(d.clone());
            persist.call(d, title.read().clone(), data);
        }
        return;
    }
    // 双栏锚：重排前先记分界（锚存在才维护；无锚时分界是
    // 文档内容的确定性纯函数，重排后自动重算）。
    let layout_before = data
        .read()
        .memos
        .iter()
        .find(|m| m.id.to_string() == memo_id)
        .and_then(|m| m.extra.get("layout").cloned());
    let boundary = layout_before
        .as_ref()
        .map(|l| column_boundary(&d, Some(l)));
    let seg: Vec<Node> = d.drain(start..start + n).collect();
    let insert_at = if to > start { to - n } else { to }.min(d.len());
    for (k, node) in seg.into_iter().enumerate() {
        d.insert(insert_at + k, node);
    }
    doc.set(d.clone());
    if let (Some(l), Some(b)) = (layout_before, boundary) {
        let mode = l
            .get("mode")
            .and_then(|v| v.as_str())
            .unwrap_or("independent")
            .to_string();
        let ids_v: Vec<Value> = d
            .iter()
            .map(|x| {
                Value::String(x.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
            })
            .collect();
        let (left, right) = ids_v.split_at(b.min(ids_v.len()));
        let mut backup = data.read().clone();
        if let Some(m) = backup
            .memos
            .iter_mut()
            .find(|m| m.id.to_string() == memo_id)
        {
            m.extra.insert(
                "layout".to_string(),
                json!({"version": 1, "mode": mode, "left": left, "right": right}),
            );
        }
        data.set(backup);
    }
    persist.call(d.clone(), title.read().clone(), data);
    diag::log(
        "EDIT",
        &format!("move block {} x{n} {start} -> {insert_at}", ids[0]),
    );
}

#[allow(clippy::too_many_arguments)]
fn handle_bridge_msg(
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
    mut hist: Signal<Vec<String>>,
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
                    persist, data, &title, sync.as_deref(), focus,
                );
            } else {
                step_redo(
                    &mut doc, &mut hist, &mut hist_idx, &mut hist_clock, &mut epoch, &mut focus_req,
                    persist, data, &title, sync.as_deref(), focus,
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
            panel.set(None);
            if act == "image" || act == "gallery" {
                // 占位块路径（S4）：桥已 strip 掉令牌，但整块将被
                // 占位块替换，html 不再使用
                op_insert_media_placeholder(&mut doc, bid, act == "gallery", &mut focus_req);
            } else if let Some(src) = op_convert(&mut doc, bid, act, html, &mut focus_req, &mut md_edit) {
                let esc = src
                    .replace('&', "&amp;")
                    .replace('<', "&lt;")
                    .replace('>', "&gt;")
                    .replace('\n', "<br>");
                let len = src.chars().count();
                dom_set.set(Some((bid.to_string(), esc, len)));
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
                if idb::put_attachment(&fid, &bytes).await.is_err() {
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
                let _ = idb::save_manifest(&man_str).await;
                let mut d = doc.read().clone();
                if let Some(loc) = find_loc(&d, &bid_owned) {
                    let top = match loc {
                        Loc::Top(i) => i,
                        Loc::Item(li, _) => li,
                    };
                    let mut extra = Map::new();
                    extra.insert("attrs".to_string(), json!({"fileId": fid}));
                    let node = Node {
                        text: None,
                        node_type: Some("image".to_string()),
                        id: Some(gen_id()),
                        children: Some(vec![]),
                        extra,
                    };
                    d.insert(top + 1, node);
                    doc.set(d.clone());
                    persist2.call(d, title.read().clone(), data);
                    diag::log("EDIT", &format!("pasteImage {fid} {}B", bytes.len()));
                }
            });
        }
        "sync" => {
            // 自动同步：只更新持久副本，不动正在编辑的 doc 信号
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
    if matches!(op, "pasteSync" | "mdText" | "split" | "merge" | "pasteText")
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

/// 把 {bid: innerHTML} 同步进文档的文本块（行内重解析）。
fn apply_sync_map(doc: &mut Vec<Node>, map_json: &str) {
    let Ok(map) = serde_json::from_str::<Map<String, Value>>(map_json) else {
        return;
    };
    fn apply(nodes: &mut [Node], map: &Map<String, Value>) {
        for n in nodes.iter_mut() {
            let ty = n.block_type().unwrap_or("").to_string();
            if is_text_block(&ty) {
                if let Some(bid) = &n.id {
                    if let Some(html) = map.get(bid).and_then(|v| v.as_str()) {
                        n.children = Some(editor_html_to_inlines(html));
                    }
                }
            }
            if ty == "bulleted-list" || ty == "numbered-list" {
                if let Some(kids) = &mut n.children {
                    apply(kids, map);
                }
            }
        }
    }
    apply(doc, &map);
}

fn op_split(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    before_html: &str,
    after_html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
) {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("split: block not found {bid}"));
        return;
    };
    let cur = node_at(&d, loc).clone();
    let ty = cur.block_type().unwrap_or("paragraph").to_string();
    let before_inlines = editor_html_to_inlines(before_html);
    let after_inlines = editor_html_to_inlines(after_html);
    let before_text: String = before_inlines.iter().map(|n| n.plain_text()).collect();
    let after_text: String = after_inlines.iter().map(|n| n.plain_text()).collect();

    // 空列表项回车 = 退出列表（该项变段落，后续项另起一表）。
    // 空块的 before/after 文本只含 <br> 换行（\n），须 trim 判空。
    if let Loc::Item(li, ii) = loc {
        if before_text.trim().is_empty() && after_text.trim().is_empty() {
            let list = d[li].clone();
            let items = list.children.clone().unwrap_or_default();
            let tail: Vec<Node> = items.iter().skip(ii + 1).cloned().collect();
            let para = new_block("paragraph");
            let para_id = para.id.clone().unwrap_or_default();
            let insert_at = if ii > 0 {
                d[li].children = Some(items[..ii].to_vec());
                li + 1
            } else {
                d.remove(li);
                li
            };
            d.insert(insert_at, para);
            if !tail.is_empty() {
                let mut nl = list.clone();
                nl.id = Some(gen_id());
                nl.children = Some(tail);
                d.insert(insert_at + 1, nl);
            }
            doc.set(d);
            focus_req.set(Some((para_id, 0)));
            diag::log("EDIT", &format!("split-exit-list {bid}"));
            return;
        }
    }

    // 标题/标注回车（编辑态审计 B1，原版 editor.js:2080-2114）：
    // 不拆分文本——原块整段保留（空块亦然），只在其后插入一个
    // 空段落并把光标放进去。桥已 preventDefault，DOM 仍是全文，
    // 模型不动即与 DOM 一致，无需回写。标题口径与 Notion 一致，
    // 调优评估（audit_tuning_report.md）结论为保留。
    if matches!(ty.as_str(), "heading" | "callout") {
        if let Loc::Top(i) = loc {
            let para = new_block("paragraph");
            let para_id = para.id.clone().unwrap_or_default();
            d.insert(i + 1, para);
            doc.set(d);
            focus_req.set(Some((para_id, 0)));
            diag::log("EDIT", &format!("split-styled-insert-para {bid}"));
            return;
        }
    }

    // 待办/引用回车（调优评估结论，偏离原版 B1 口径）：主流编辑器
    // （Notion/Apple Notes/Obsidian/飞书/Word）无一例外做延续——
    // 有内容按光标拆为同型新块（新待办未勾选）；空块回车则自身
    // 转段落退出（与空列表项退出列表同构），避免留空待办垃圾块
    // 与每条待办重走一遍斜杠的交互成本。拆分走下方通用路径。
    if matches!(ty.as_str(), "todo" | "quote")
        && before_text.trim().is_empty()
        && after_text.trim().is_empty()
    {
        let n = node_at_mut(&mut d, loc);
        n.node_type = Some("paragraph".to_string());
        n.extra.remove("attrs");
        // 子节点一并清空：清空动作可能还没经 autosync 进模型，
        // 不清的话旧文本会随类型转换被重新渲染出来（实测教训）
        n.children = Some(vec![empty_text_node()]);
        doc.set(d);
        focus_req.set(Some((bid.to_string(), 0)));
        diag::log("EDIT", &format!("split-exit-styled {bid}"));
        return;
    }

    let new_ty = match ty.as_str() {
        "list-item" => "list-item",
        "todo" => "todo",
        "quote" => "quote",
        _ => "paragraph",
    };
    let mut new_block = new_block(new_ty);
    if new_ty == "todo" {
        set_attr(&mut new_block, "checked", json!(false));
    }
    new_block.children = Some(after_inlines);
    let new_id = new_block.id.clone().unwrap_or_default();

    {
        let n = node_at_mut(&mut d, loc);
        n.children = Some(before_inlines);
    }
    match loc {
        Loc::Top(i) => d.insert(i + 1, new_block),
        Loc::Item(li, ii) => {
            d[li].children.as_mut().unwrap().insert(ii + 1, new_block);
        }
    }
    doc.set(d);
    // 源块 DOM 回写（编辑态审计 D1）：源块是非受控 DOM，模型拆分
    // 后它的 innerHTML 仍是拆分前全文，不回写则屏幕重复显示，
    // 且 autosync/开菜单/返回会拿旧 DOM 覆盖模型落库。回写内容
    // 就是桥传来的 before 片段，与模型解析源逐字一致；焦点由
    // focus_req 落到新块（dom_set 的附带聚焦会被其覆盖）。
    dom_set.set(Some((
        bid.to_string(),
        before_html.to_string(),
        before_text.encode_utf16().count(),
    )));
    focus_req.set(Some((new_id, 0)));
}

/// 退格合并的目标分类：文档顺序里**紧邻**的上一个块。
/// 此前 op_merge 用 prev_editable 一路跳过原子块找文本块，
/// [段][图][段] 段首退格会把后段文本越过图片并进前段
/// （跨块语义组 B10 实测）；原版单宿主里文本永不跨原子块
/// 移动，紧邻关系才是规格。
enum PrevKind {
    /// 可编辑文本块（列表时为其末项）：常规合并目标。
    Text(Loc),
    /// 原子块（图片/卡片/分割线等不可编辑顶层块）。
    Atomic(usize),
    /// 没有上一个块。
    None,
}

fn prev_sibling(doc: &[Node], loc: Loc) -> PrevKind {
    fn classify_top(doc: &[Node], i: usize) -> PrevKind {
        let ty = doc[i].block_type().unwrap_or("");
        if is_text_block(ty) {
            PrevKind::Text(Loc::Top(i))
        } else if ty == "bulleted-list" || ty == "numbered-list" {
            match doc[i].children.as_ref().and_then(|c| c.len().checked_sub(1)) {
                Some(last) => PrevKind::Text(Loc::Item(i, last)),
                None => PrevKind::Atomic(i),
            }
        } else {
            PrevKind::Atomic(i)
        }
    }
    match loc {
        Loc::Top(0) => PrevKind::None,
        Loc::Top(i) => classify_top(doc, i - 1),
        Loc::Item(li, ii) if ii > 0 => PrevKind::Text(Loc::Item(li, ii - 1)),
        Loc::Item(0, _) => PrevKind::None,
        Loc::Item(li, _) => classify_top(doc, li - 1),
    }
}

fn op_merge(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
    sel_block: &mut Signal<Option<String>>,
) {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("merge: block not found {bid}"));
        return;
    };
    let remove_cur = |d: &mut Vec<Node>| match loc {
        Loc::Top(i) => {
            d.remove(i);
        }
        Loc::Item(li, ii) => {
            d[li].children.as_mut().unwrap().remove(ii);
            if d[li].children.as_ref().map(|c| c.is_empty()).unwrap_or(false) {
                d.remove(li);
            }
        }
    };
    match prev_sibling(&d, loc) {
        PrevKind::None => {}
        PrevKind::Text(prev_loc) => {
            let junction = plain_len(node_at(&d, prev_loc));
            let prev_id = node_at(&d, prev_loc).id.clone().unwrap_or_default();
            let cur_inlines = editor_html_to_inlines(html);
            let merged_html = {
                let prev = node_at_mut(&mut d, prev_loc);
                let mut kids = prev.children.clone().unwrap_or_default();
                kids.extend(cur_inlines);
                let html = inlines_to_editor_html(&kids);
                prev.children = Some(kids);
                html
            };
            remove_cur(&mut d);
            doc.set(d);
            // 存活块 DOM 回写（编辑态审计 D1）：合并后模型是全文拼接，
            // 存活块的非受控 DOM 仍只有前半，不回写则后半从屏幕消失、
            // 且会被 autosync 以旧 DOM 覆盖落库造成永久丢字。
            dom_set.set(Some((prev_id.clone(), merged_html, junction)));
            focus_req.set(Some((prev_id, junction)));
        }
        PrevKind::Atomic(ai) => {
            let atom_id = d[ai].id.clone().unwrap_or_default();
            let cur_empty = editor_html_to_inlines(html)
                .iter()
                .all(|n| n.plain_text().is_empty());
            if cur_empty {
                // 空段删除、焦点落到原子块（K3，合裁定「至多
                // 选中」）：分块架构下原子块无光标位，以选中态
                // 承载「焦点在原子块」。选中态下再退格不删块
                // （K1 收口），删卡走长按/右键菜单明路。
                remove_cur(&mut d);
                doc.set(d);
                sel_block.set(Some(atom_id.clone()));
                diag::log(
                    "EDIT",
                    &format!("merge: empty block removed, atomic selected {atom_id}"),
                );
            } else {
                // 键盘删块收口（K2）：非空块块首退格撞上原子
                // 块时不再删卡（旧行为与「文本被吸入原子 div
                // 后被 parser 丢弃」的原版缺陷同为键盘直删非
                // 文本块，一并收口）——至多把该卡带入选中态
                // （与空段支同落点），两块与文本全保留。
                sel_block.set(Some(atom_id.clone()));
                diag::log(
                    "EDIT",
                    &format!("merge: backspace before atomic {atom_id} selected (kept)"),
                );
            }
        }
    }
}

/// UTF-16 码元偏移 → 字符串字节下标（劈点落在代理对中间
/// 时钳到该字符起点；光标口径下不应发生，仅作防御）。
fn utf16_byte_index(t: &str, off16: usize) -> usize {
    let mut acc = 0;
    for (bi, ch) in t.char_indices() {
        if acc >= off16 {
            return bi;
        }
        acc += ch.len_utf16();
    }
    t.len()
}

/// 按 UTF-16 偏移把行内列劈成前后两半（口径契约同
/// plain_len）。劈点在文本节点中间时克隆节点分置两侧；
/// 链接节点递归劈其子列；恰在边界时整节点归前侧。
fn split_inlines_at(inlines: &[Node], off16: usize) -> (Vec<Node>, Vec<Node>) {
    let mut head: Vec<Node> = Vec::new();
    let mut tail: Vec<Node> = Vec::new();
    let mut rest = off16;
    let mut done = false;
    for n in inlines {
        if done {
            tail.push(n.clone());
            continue;
        }
        let l = n.plain_text().encode_utf16().count();
        if rest > l {
            head.push(n.clone());
            rest -= l;
            continue;
        }
        if rest == l {
            head.push(n.clone());
            done = true;
            continue;
        }
        // rest < l
        if rest == 0 {
            tail.push(n.clone());
            done = true;
            continue;
        }
        if n.node_type.as_deref() == Some("link") {
            let kids = n.children.clone().unwrap_or_default();
            let (h, t) = split_inlines_at(&kids, rest);
            if !h.is_empty() {
                let mut hn = n.clone();
                hn.children = Some(h);
                head.push(hn);
            }
            if !t.is_empty() {
                let mut tn = n.clone();
                tn.children = Some(t);
                tail.push(tn);
            }
        } else if let Some(t) = &n.text {
            let bi = utf16_byte_index(t, rest);
            let (h, tl) = t.split_at(bi);
            if !h.is_empty() {
                let mut hn = n.clone();
                hn.text = Some(h.to_string());
                head.push(hn);
            }
            if !tl.is_empty() {
                let mut tn = n.clone();
                tn.text = Some(tl.to_string());
                tail.push(tn);
            }
        } else {
            // 无文本的异型行内节点：整体归尾侧，不吞内容
            tail.push(n.clone());
        }
        done = true;
    }
    (head, tail)
}

/// 文档顺序的全部可编辑单元（顶层文本块 + 列表项），与
/// prev_editable 的遍历同序。
fn editable_units(doc: &[Node]) -> Vec<Loc> {
    let mut out = Vec::new();
    for (i, b) in doc.iter().enumerate() {
        let ty = b.block_type().unwrap_or("");
        if is_text_block(ty) {
            out.push(Loc::Top(i));
        } else if ty == "bulleted-list" || ty == "numbered-list" {
            if let Some(kids) = &b.children {
                for (j, item) in kids.iter().enumerate() {
                    if item.is_block() {
                        out.push(Loc::Item(i, j));
                    }
                }
            }
        }
    }
    out
}

/// 原子块分类（与 prev_sibling 的 classify_top 同口径）：
/// 非文本块、且不是含项列表（空列表按原子计）。
fn is_atomic_class(n: &Node) -> bool {
    let ty = n.block_type().unwrap_or("");
    if is_text_block(ty) {
        return false;
    }
    if ty == "bulleted-list" || ty == "numbered-list" {
        return n.children.as_ref().map(|c| c.is_empty()).unwrap_or(true);
    }
    true
}

/// 跨块选区替换（跨块语义组）：桥的虚拟选区在删除/覆打/
/// 回车/粘贴时发 replaceRange。语义对原版单宿主的原生选
/// 区：起止单元各取选区外侧（头/尾）行内，中间文本块整
/// 块删除，头+插入文本+尾并成结果块列置于起始单元处；
/// 光标落插入末尾（回车时落尾块首）。
/// sync 先行全量同步（与 moveBlock/撤销同口径），保证模
/// 型与活 DOM 一致再手术。from_start/to_end 是 Ctrl+A 的
/// 全文标记。
/// 键盘删块收口（K5）：选区内及 Ctrl+A 首尾外侧的原子块
/// 全程存活、原位保留，替换按原子边界分段——首段承接
/// head+插入文本，尾行内由末段首位的新块承接（回车时尾
/// 归末段、光标随之）；无原子介入时与旧行为逐字不变。
#[allow(clippy::too_many_arguments)]
fn op_replace_range(
    doc: &mut Signal<Vec<Node>>,
    a_bid: &str,
    a_off: usize,
    f_bid: &str,
    f_off: usize,
    text: &str,
    enter: bool,
    from_start: bool,
    to_end: bool,
    sync: Option<&str>,
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
) {
    let mut d = doc.read().clone();
    if let Some(s) = sync {
        apply_sync_map(&mut d, s);
    }
    let (Some(a_loc), Some(f_loc)) = (find_loc(&d, a_bid), find_loc(&d, f_bid)) else {
        diag::log("EDIT", "replaceRange: endpoint not found");
        return;
    };
    let units = editable_units(&d);
    let (Some(ia), Some(ie)) = (
        units.iter().position(|u| *u == a_loc),
        units.iter().position(|u| *u == f_loc),
    ) else {
        diag::log("EDIT", "replaceRange: endpoint not editable unit");
        return;
    };
    let ((s_loc, s_off), (e_loc, e_off)) = if ia <= ie {
        ((a_loc, a_off), (f_loc, f_off))
    } else {
        ((f_loc, f_off), (a_loc, a_off))
    };
    let s_kids = node_at(&d, s_loc).children.clone().unwrap_or_default();
    let (head, _) = split_inlines_at(&s_kids, s_off);
    let e_kids = node_at(&d, e_loc).children.clone().unwrap_or_default();
    let (_, tail) = split_inlines_at(&e_kids, e_off);
    let head_len = inlines_len(&head);

    // K5 分段路径：选区内有原子块存活时按原子边界分段重
    // 组（无原子时走下方原路径，行为逐字不变）。
    let s_top = match s_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let e_top = match e_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let atoms_kept = (s_top + 1..e_top)
        .filter(|&t| is_atomic_class(&d[t]))
        .count();
    if atoms_kept > 0 {
        let s_id = node_at(&d, s_loc).id.clone().unwrap_or_default();
        // 首段列：head + 插入文本逐行成列（尾行内不并入首
        // 段，由末段承接）；回车时首段只有 head、尾归末段。
        let mut seg_cols: Vec<Vec<Node>> = Vec::new();
        let (caret_in_tail, caret_col, caret_off);
        if enter {
            seg_cols.push(head);
            caret_in_tail = true;
            caret_col = 0;
            caret_off = 0;
        } else {
            let lines: Vec<&str> = text.split('\n').collect();
            let mut first = head;
            if !lines[0].is_empty() {
                first.push(text_node(lines[0]));
            }
            seg_cols.push(first);
            for mid in &lines[1..] {
                seg_cols.push(if mid.is_empty() {
                    Vec::new()
                } else {
                    vec![text_node(mid)]
                });
            }
            caret_in_tail = false;
            caret_col = seg_cols.len() - 1;
            caret_off = if lines.len() > 1 {
                lines[lines.len() - 1].encode_utf16().count()
            } else {
                head_len + text.encode_utf16().count()
            };
        }
        // 末段承接列：尾行内成新块落末段首位（原尾单元随选
        // 区移除，避免其非受控 DOM 残留旧文与模型脱节）；
        // 非回车且尾为空时不立空块——全选清空后只留首段一
        // 个空段承载光标。
        let tail_col: Option<Vec<Node>> = if enter {
            Some(tail)
        } else if tail.iter().all(|n| n.plain_text().is_empty()) {
            None
        } else {
            Some(tail)
        };
        // 实例化：首段第 0 列写回起始单元、其余列新建块；
        // 末段列新建块（止端为列表项时作列表项进原列表）。
        let mut seg_ids: Vec<String> = vec![s_id.clone()];
        let mut seg_extra: Vec<Node> = Vec::new();
        for kids in seg_cols.iter().skip(1) {
            let mut b = match s_loc {
                Loc::Top(_) => new_block("paragraph"),
                Loc::Item(..) => new_block("list-item"),
            };
            b.children = Some(kids.clone());
            seg_ids.push(b.id.clone().unwrap_or_default());
            seg_extra.push(b);
        }
        let mut tail_block: Option<Node> = None;
        let mut tail_id = String::new();
        if let Some(kids) = &tail_col {
            let mut b = match e_loc {
                Loc::Top(_) => new_block("paragraph"),
                Loc::Item(..) => new_block("list-item"),
            };
            b.children = Some(kids.clone());
            tail_id = b.id.clone().unwrap_or_default();
            tail_block = Some(b);
        }
        // 按文档顺序重组：原子块原位保留，其余按段落位。
        let mut out: Vec<Node> = Vec::new();
        for (t, block) in d.iter().enumerate() {
            if t < s_top {
                if !from_start || is_atomic_class(block) {
                    out.push(block.clone());
                }
                continue;
            }
            if t > e_top {
                if !to_end || is_atomic_class(block) {
                    out.push(block.clone());
                }
                continue;
            }
            if t == s_top {
                match s_loc {
                    Loc::Top(_) => {
                        let mut b = block.clone();
                        b.children = Some(seg_cols[0].clone());
                        out.push(b);
                        out.extend(seg_extra.iter().cloned());
                    }
                    Loc::Item(_, s_ii) => {
                        let mut list = block.clone();
                        let items = list.children.clone().unwrap_or_default();
                        let mut kids: Vec<Node> = Vec::new();
                        if !from_start {
                            kids.extend(items[..s_ii].iter().cloned());
                        }
                        let mut first_item = items[s_ii].clone();
                        first_item.children = Some(seg_cols[0].clone());
                        kids.push(first_item);
                        kids.extend(seg_extra.iter().cloned());
                        list.children = Some(kids);
                        out.push(list);
                    }
                }
                continue;
            }
            if t == e_top {
                if let Loc::Item(_, e_ii) = e_loc {
                    let items = block.children.clone().unwrap_or_default();
                    let mut kids: Vec<Node> = Vec::new();
                    if let Some(tb) = &tail_block {
                        kids.push(tb.clone());
                    }
                    if !to_end {
                        kids.extend(items[e_ii + 1..].iter().cloned());
                    }
                    if !kids.is_empty() {
                        let mut list = block.clone();
                        list.children = Some(kids);
                        out.push(list);
                    }
                } else if let Some(tb) = &tail_block {
                    out.push(tb.clone());
                }
                continue;
            }
            // s_top < t < e_top：原子块存活；文本块与含项列
            // 表整块在选区内，丢弃。
            if is_atomic_class(block) {
                out.push(block.clone());
            }
        }
        doc.set(out);
        let (caret_id, caret_final) = if caret_in_tail {
            (tail_id.clone(), caret_off)
        } else {
            (seg_ids[caret_col].clone(), caret_off)
        };
        let unit0_caret = if !caret_in_tail && caret_col == 0 {
            caret_off
        } else {
            inlines_len(&seg_cols[0])
        };
        dom_set.set(Some((
            s_id.clone(),
            inlines_to_editor_html(&seg_cols[0]),
            unit0_caret,
        )));
        focus_req.set(Some((caret_id, caret_final)));
        diag::log(
            "EDIT",
            &format!(
                "replace range {a_bid}@{a_off}..{f_bid}@{f_off} ins={}B enter={enter} atoms kept={atoms_kept}",
                text.len()
            ),
        );
        return;
    }

    // 结果块列（行内列）与光标落点（第几列、列内 UTF-16）
    let mut result: Vec<Vec<Node>> = Vec::new();
    let (caret_unit, caret_off);
    if enter {
        result.push(head);
        result.push(tail);
        caret_unit = 1;
        caret_off = 0;
    } else {
        let lines: Vec<&str> = text.split('\n').collect();
        let mut first = head;
        if !lines[0].is_empty() {
            first.push(text_node(lines[0]));
        }
        result.push(first);
        if lines.len() > 2 {
            for mid in &lines[1..lines.len() - 1] {
                result.push(if mid.is_empty() {
                    Vec::new()
                } else {
                    vec![text_node(mid)]
                });
            }
        }
        if lines.len() > 1 {
            let last = lines[lines.len() - 1];
            let mut last_kids: Vec<Node> = Vec::new();
            if !last.is_empty() {
                last_kids.push(text_node(last));
            }
            last_kids.extend(tail);
            result.push(last_kids);
            caret_unit = result.len() - 1;
            caret_off = last.encode_utf16().count();
        } else {
            let tl = text.encode_utf16().count();
            result[0].extend(tail);
            caret_unit = 0;
            caret_off = head_len + tl;
        }
    }

    let s_top = match s_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let e_top = match e_loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let s_id = node_at(&d, s_loc).id.clone().unwrap_or_default();

    // 结果列实例化：第 0 列写回起始单元（保 id/类型），其
    // 余列新建块（顶层段落 / 列表内列表项），记 id 供落点。
    let mut result_ids: Vec<String> = vec![s_id.clone()];
    let mut extra_blocks: Vec<Node> = Vec::new();
    for kids in result.iter().skip(1) {
        let mut b = match s_loc {
            Loc::Top(_) => new_block("paragraph"),
            Loc::Item(..) => new_block("list-item"),
        };
        b.children = Some(kids.clone());
        result_ids.push(b.id.clone().unwrap_or_default());
        extra_blocks.push(b);
    }

    // 按文档顺序重组：起始容器写回结果列，中间整块丢弃，
    // 止容器为止项时保留未覆盖的尾项，其余按 from/to 标记。
    let mut out: Vec<Node> = Vec::new();
    for (t, block) in d.iter().enumerate() {
        if t < s_top {
            if !from_start {
                out.push(block.clone());
            }
            continue;
        }
        if t > e_top {
            if !to_end {
                out.push(block.clone());
            }
            continue;
        }
        if t == s_top {
            match s_loc {
                Loc::Top(_) => {
                    let mut b = block.clone();
                    b.children = Some(result[0].clone());
                    out.push(b);
                    out.extend(extra_blocks.iter().cloned());
                }
                Loc::Item(_, s_ii) => {
                    let mut list = block.clone();
                    let items = list.children.clone().unwrap_or_default();
                    let mut kids: Vec<Node> = Vec::new();
                    if !from_start {
                        kids.extend(items[..s_ii].iter().cloned());
                    }
                    let mut first_item = items[s_ii].clone();
                    first_item.children = Some(result[0].clone());
                    kids.push(first_item);
                    kids.extend(extra_blocks.iter().cloned());
                    if s_top == e_top {
                        if let Loc::Item(_, e_ii) = e_loc {
                            if !to_end {
                                kids.extend(items[e_ii + 1..].iter().cloned());
                            }
                        }
                    }
                    list.children = Some(kids);
                    out.push(list);
                }
            }
            continue;
        }
        if t == e_top {
            // 止容器（与起始容器不同）：止单元为列表项时保
            // 留其后未覆盖的项；顶层止块整块已被尾行内抽
            // 走，直接丢弃（to_end 时尾项一并丢弃）。
            if let Loc::Item(_, e_ii) = e_loc {
                if !to_end {
                    let items = block.children.clone().unwrap_or_default();
                    let rest_items: Vec<Node> = items[e_ii + 1..].to_vec();
                    if !rest_items.is_empty() {
                        let mut list = block.clone();
                        list.children = Some(rest_items);
                        out.push(list);
                    }
                }
            }
            continue;
        }
        // s_top < t < e_top：整块在选区内，丢弃
    }
    doc.set(out);

    let caret_id = result_ids[caret_unit].clone();
    let unit0_caret = if caret_unit == 0 {
        caret_off
    } else {
        inlines_len(&result[0])
    };
    dom_set.set(Some((s_id.clone(), inlines_to_editor_html(&result[0]), unit0_caret)));
    focus_req.set(Some((caret_id, caret_off)));
    diag::log(
        "EDIT",
        &format!("replace range {a_bid}@{a_off}..{f_bid}@{f_off} ins={}B enter={enter}", text.len()),
    );
}

fn text_node(s: &str) -> Node {
    Node {
        text: Some(s.to_string()),
        node_type: None,
        id: None,
        children: None,
        extra: Map::new(),
    }
}

/// 行内列纯文本长度（UTF-16 码元口径，同 plain_len 的光
/// 标偏移契约；唯一调用点是粘贴多行时首块的 dom_set 落点）。
fn inlines_len(nodes: &[Node]) -> usize {
    nodes
        .iter()
        .map(|n| n.plain_text().encode_utf16().count())
        .sum()
}

/// 粘贴 URL 生成卡片（原版 insertLinkCardAtDOM 口径）：当前
/// 块按光标拆分（前段留原块、后段成新段落），卡片插中间；
/// 音乐域名 → musicCard，其余 → link-card，均先 loading
/// 再由 spawn_resolve_card 回填 meta。remain 非空时在卡后
/// 另起一段（原版「剩余文本保留为卡后段落」）并聚焦它。
fn op_paste_card(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    url: &str,
    remain: &str,
    before_html: &str,
    after_html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
) -> Option<String> {
    const MUSIC_HOSTS: [&str; 6] = [
        "music.163.com",
        "163cn.tv",
        "y.qq.com",
        "i.y.qq.com",
        "open.spotify.com",
        "music.apple.com",
    ];
    let is_music = MUSIC_HOSTS.iter().any(|h| url.contains(h));
    let mut d = doc.read().clone();
    let loc = find_loc(&d, bid)?;
    let before = editor_html_to_inlines(before_html);
    let after = editor_html_to_inlines(after_html);
    node_at_mut(&mut d, loc).children = Some(before);
    let top_idx = match loc {
        Loc::Top(i) => i,
        Loc::Item(li, _) => li,
    };
    let mut card = new_block(if is_music { "musicCard" } else { "link-card" });
    card.extra.insert("url".to_string(), json!(url));
    card.extra.insert("status".to_string(), json!("loading"));
    let card_id = card.id.clone().unwrap_or_default();
    let mut at = top_idx + 1;
    d.insert(at, card);
    at += 1;
    let mut focus: Option<(String, usize)> = None;
    if !remain.trim().is_empty() {
        let mut pnode = new_block("paragraph");
        pnode.children = Some(vec![text_node(remain.trim())]);
        let pid = pnode.id.clone().unwrap_or_default();
        d.insert(at, pnode);
        at += 1;
        focus = Some((pid, usize::MAX));
    }
    let after_text: String = after.iter().map(|n| n.plain_text()).collect();
    if !after_text.is_empty() {
        let mut pnode = new_block("paragraph");
        pnode.children = Some(after);
        let pid = pnode.id.clone().unwrap_or_default();
        d.insert(at, pnode);
        if focus.is_none() {
            focus = Some((pid, 0));
        }
    }
    if focus.is_none() {
        // 原版 insertAtomicBlockToDOM 恒保证卡片后有可编辑块
        // 并聚焦其开头：remain/after 都为空时，卡后现成的文本
        // 块直接用；不是文本块（或没有下一块）就补空段落。
        // 缺这一步时光标会滞留在卡片之前的原段落里。
        let card_at = top_idx + 1;
        let next_is_text = d
            .get(card_at + 1)
            .map(|n| is_text_block(n.block_type().unwrap_or("")))
            .unwrap_or(false);
        if next_is_text {
            let pid = d[card_at + 1].id.clone().unwrap_or_default();
            if !pid.is_empty() {
                focus = Some((pid, 0));
            }
        } else {
            let pnode = new_block("paragraph");
            let pid = pnode.id.clone().unwrap_or_default();
            d.insert(card_at + 1, pnode);
            focus = Some((pid, 0));
        }
    }
    diag::log("CARD", &format!("skeleton {card_id}"));
    doc.set(d);
    if let Some(f) = focus {
        focus_req.set(Some(f));
    }
    Some(card_id)
}

/// 极小 base64 解码（粘贴图片字节通路；无第三方依赖）。
fn b64_decode(s: &str) -> Vec<u8> {
    let mut table = [255u8; 256];
    for (i, c) in b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        .iter()
        .enumerate()
    {
        table[*c as usize] = i as u8;
    }
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let mut acc: u32 = 0;
    let mut nbits = 0u32;
    for &b in s.as_bytes() {
        if b == b'=' {
            break;
        }
        let v = table[b as usize];
        if v == 255 {
            continue;
        }
        acc = (acc << 6) | v as u32;
        nbits += 6;
        if nbits >= 8 {
            nbits -= 8;
            out.push((acc >> nbits) as u8);
        }
    }
    out
}

/// 单块光标处的多行纯文本粘贴（桥 pasteText）：首行并入
/// 当前块保其类型，中间行各成新段，末行带上光标后的原内
/// 容，当前块 DOM 由 dom_set 回写对齐。与跨块选区替换的
/// op_replace_range 是两条独立路径（批 1 B-8 衔接）：后者
/// 对 xsel 选区的替换文本同样按行拆块——2026-11-23 双侧
/// 活体量测证实原版 insertText+parse 对跨块选区粘贴亦按
/// 行落块（含 \n\n 生成空块），两侧口径一致，非死代码、
/// 不再合并。
fn op_paste_text(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    before_html: &str,
    after_html: &str,
    lines: &[String],
    focus_req: &mut Signal<Option<(String, usize)>>,
    dom_set: &mut Signal<Option<(String, String, usize)>>,
) {
    if lines.len() < 2 {
        return;
    }
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("pasteText: block not found {bid}"));
        return;
    };
    let before = editor_html_to_inlines(before_html);
    let after = editor_html_to_inlines(after_html);
    let mut first_kids = before;
    first_kids.push(text_node(&lines[0]));
    let first_html = inlines_to_editor_html(&first_kids);
    let first_len = inlines_len(&first_kids);
    node_at_mut(&mut d, loc).children = Some(first_kids);

    let last_idx = lines.len() - 1;
    let mut new_blocks: Vec<Node> = Vec::new();
    for (k, line) in lines.iter().enumerate().skip(1) {
        let mut kids = vec![text_node(line)];
        if k == last_idx {
            kids.extend(after.clone());
        }
        let mut b = match loc {
            Loc::Top(_) => new_block("paragraph"),
            Loc::Item(..) => new_block("list-item"),
        };
        b.children = Some(kids);
        new_blocks.push(b);
    }
    let last_id = new_blocks
        .last()
        .and_then(|b| b.id.clone())
        .unwrap_or_default();
    let last_len = lines[last_idx].encode_utf16().count();
    match loc {
        Loc::Top(i) => {
            for (k, b) in new_blocks.into_iter().enumerate() {
                d.insert(i + 1 + k, b);
            }
        }
        Loc::Item(li, ii) => {
            for (k, b) in new_blocks.into_iter().enumerate() {
                d[li].children.as_mut().unwrap().insert(ii + 1 + k, b);
            }
        }
    }
    doc.set(d);
    dom_set.set(Some((bid.to_string(), first_html, first_len)));
    focus_req.set(Some((last_id, last_len)));
    diag::log("EDIT", &format!("paste text {} lines into {bid}", lines.len()));
}

/// attrs 字段读写（原版节点工厂把 level/checked/fileId 放 attrs）。
fn set_attr(n: &mut Node, key: &str, val: Value) {
    let mut attrs = n
        .extra
        .get("attrs")
        .and_then(|v| v.as_object().cloned())
        .unwrap_or_default();
    attrs.insert(key.to_string(), val);
    n.extra.insert("attrs".into(), Value::Object(attrs));
}

fn del_attr(n: &mut Node, key: &str) {
    if let Some(attrs) = n
        .extra
        .get_mut("attrs")
        .and_then(|v| v.as_object_mut())
    {
        attrs.remove(key);
    }
}

/// 清掉标题/待办的类型字段（顶层旧形 + attrs 正形都清）。
fn clear_type_fields(n: &mut Node) {
    n.extra.remove("level");
    n.extra.remove("checked");
    del_attr(n, "level");
    del_attr(n, "checked");
}

/// md 源段落 → 纯文本（去围栏/引用/列表前缀），转换出口径。
fn strip_md_prefixes(text: &str) -> String {
    match crate::blocks::md_classify(text) {
        Some(crate::blocks::MdKind::Code(code)) => code,
        Some(crate::blocks::MdKind::Callout { body, .. }) => body.join("\n"),
        Some(crate::blocks::MdKind::List { items, .. }) => items.join("\n"),
        Some(crate::blocks::MdKind::Rich(src)) => src,
        Some(crate::blocks::MdKind::Heading { text, .. }) => text,
        Some(crate::blocks::MdKind::Quote(paras)) => paras.join("\n"),
        Some(crate::blocks::MdKind::Table { .. }) => text.to_string(),
        Some(crate::blocks::MdKind::Divider) => text.to_string(),
        None => text.to_string(),
    }
}

/// 智能前缀命中（原版 editor.js:1919-1956 的 PATTERNS 表，
/// 逐条镜像其 JS 正则语义）：对段落首叶文本（S3 字面口径
/// 下即整段纯文本）判定。(.+) 不跨行——多行文本只看首行，
/// 首行之外的内容在原版转换时一并丢弃，此处同口径。
enum PrefixHit {
    Heading(u8, String),
    Quote(String),
    Todo(String),
    Divider,
}

fn smart_prefix_match(raw: &str) -> Option<PrefixHit> {
    if raw.is_empty() {
        return None;
    }
    let first_line = raw.split('\n').next().unwrap_or("");
    // ### / ## / # + 字面空格 + 至少一字符（捕获 trim 后为正文）
    for (prefix, level) in [("### ", 3u8), ("## ", 2), ("# ", 1)] {
        if let Some(rest) = first_line.strip_prefix(prefix) {
            if !rest.is_empty() {
                return Some(PrefixHit::Heading(level, rest.trim().to_string()));
            }
        }
    }
    // > + 至少一字符；负向前瞻 (?!\s*\[!\S)：> [!TYPE] 是
    // 标注源段、不转引用（与 md_classify 的 Callout 同界）
    if let Some(rest) = first_line.strip_prefix('>') {
        if !rest.is_empty() {
            let t = rest.trim_start();
            let callout = t.starts_with("[!")
                && t[2..].chars().next().is_some_and(|c| !c.is_whitespace());
            if !callout {
                return Some(PrefixHit::Quote(rest.trim().to_string()));
            }
        }
    }
    // [ ] / [] + 字面空格 + 至少一字符 → 待办（未勾选）
    for prefix in ["[ ] ", "[] "] {
        if let Some(rest) = first_line.strip_prefix(prefix) {
            if !rest.is_empty() {
                return Some(PrefixHit::Todo(rest.trim().to_string()));
            }
        }
    }
    // 分隔线：全文恰为 ---（原版 exact 全串相等，不 trim）
    if raw == "---" {
        return Some(PrefixHit::Divider);
    }
    None
}

/// 智能前缀扫描（原版 editor.js:1915-1996）：扫全 doc 顶层
/// 段落（文档序），首个命中者转块型、每周期只转一处，返回
/// (被转换块 id, 聚焦块 id, 光标偏移)。转换形态与斜杠转换
/// 同构（apply_type 口径：同 id、单文本子节点、类型字段先
/// 清后设）；焦点落新块文末（原版 focusEditableWithCaret
/// (caretAt = 转换后文本长度)）。divider 无正文：原版只
/// 原地替换、不补尾随段，焦点落 divider 本身（caretAt
/// =0，聚焦 id 与被转换 id 同为该块）。第四元是被转换块的
/// 编辑态 HTML（dom_set 回写用：非受控块不会自己重渲染，
/// 转换改了文本必须同步改写活 DOM，与 slashApply 同口径）；
/// divider 的旧元素随类型变更卸载，无需回写，为 None。
fn apply_smart_prefix(
    doc: &mut Signal<Vec<Node>>,
) -> Option<(String, String, usize, Option<String>)> {
    let mut d = doc.read().clone();
    for i in 0..d.len() {
        if d[i].block_type() != Some("paragraph") {
            continue;
        }
        let raw = d[i].plain_text();
        let Some(hit) = smart_prefix_match(&raw) else {
            continue;
        };
        let bid = d[i].id.clone().unwrap_or_default();
        match hit {
            PrefixHit::Divider => {
                // 原版 editor.js 智能前缀 `---`：只原地替换为
                // divider、不补尾随段；焦点落 divider 本身
                // （focusEditableWithCaret(命中元素, 0)——
                // divider 无 children 故 caretAt=0）。
                let mut div = new_block("divider");
                div.id = Some(bid.clone());
                div.children = None;
                d[i] = div;
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> divider {bid}"));
                return Some((bid.clone(), bid, 0, None));
            }
            PrefixHit::Heading(level, text) => {
                let len = text.chars().count();
                let kids = vec![text_node(&text)];
                let html = inlines_to_editor_html(&kids);
                let n = &mut d[i];
                n.node_type = Some("heading".to_string());
                clear_type_fields(n);
                set_attr(n, "level", json!(level as u64));
                n.children = Some(kids);
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> heading{level} {bid}"));
                return Some((bid.clone(), bid, len, Some(html)));
            }
            PrefixHit::Quote(text) => {
                let len = text.chars().count();
                let kids = vec![text_node(&text)];
                let html = inlines_to_editor_html(&kids);
                let n = &mut d[i];
                n.node_type = Some("quote".to_string());
                clear_type_fields(n);
                n.children = Some(kids);
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> quote {bid}"));
                return Some((bid.clone(), bid, len, Some(html)));
            }
            PrefixHit::Todo(text) => {
                let len = text.chars().count();
                let kids = vec![text_node(&text)];
                let html = inlines_to_editor_html(&kids);
                let n = &mut d[i];
                n.node_type = Some("todo".to_string());
                clear_type_fields(n);
                set_attr(n, "checked", json!(false));
                n.children = Some(kids);
                doc.set(d);
                diag::log("EDIT", &format!("smart prefix -> todo {bid}"));
                return Some((bid.clone(), bid, len, Some(html)));
            }
        }
    }
    None
}

fn apply_type(n: &mut Node, act: &str) {
    match act {
        "heading1" | "heading2" | "heading3" => {
            n.node_type = Some("heading".into());
            let lv: u64 = act[7..].parse().unwrap_or(2);
            clear_type_fields(n);
            set_attr(n, "level", json!(lv));
        }
        "todo" => {
            n.node_type = Some("todo".into());
            clear_type_fields(n);
            set_attr(n, "checked", json!(false));
        }
        "quote" => {
            n.node_type = Some("quote".into());
            clear_type_fields(n);
        }
        "imgTextCard" => {
            // 原版工厂（斜杠审计 S6）：正文被固定占位文替换（不
            // 保留用户原文），attrs 带 fileId:''
            n.node_type = Some("imgTextCard".into());
            clear_type_fields(n);
            n.children = Some(vec![text_node("点击输入文字")]);
            set_attr(n, "fileId", json!(""));
        }
        "imageTextRow" => {
            n.node_type = Some("imageTextRow".into());
            clear_type_fields(n);
            n.children = Some(vec![text_node("点击输入说明文字")]);
            set_attr(n, "fileId", json!(""));
        }
        "musicCard" => {
            // 原版工厂（斜杠审计 S5）：{url:'', meta:null,
            // status:'input'} 且无 children 键
            n.node_type = Some("musicCard".into());
            clear_type_fields(n);
            n.children = None;
            n.extra.insert("url".to_string(), json!(""));
            n.extra.insert("meta".to_string(), serde_json::Value::Null);
            n.extra.insert("status".to_string(), json!("input"));
        }
        _ => {
            n.node_type = Some("paragraph".into());
            clear_type_fields(n);
        }
    }
}

/// 空段落判定（原版 use-slash.js:541-544 的 next-empty
/// 口径：type=paragraph 且正文为空）。尾随段补插各路共用：
/// 下一块已是现成空段就不多插、焦点改落该段。
fn is_empty_para(n: &Node) -> bool {
    n.block_type() == Some("paragraph") && n.plain_text().trim().is_empty()
}

fn next_is_empty_para(d: &[Node], i: usize) -> bool {
    d.get(i + 1).map(is_empty_para).unwrap_or(false)
}

/// 斜杠图片/画廊（斜杠审计 S4，原版 use-slash.js 工厂口径）：
/// 应用即落占位块（image: attrs.fileId=''；gallery:
/// attrs.items=[]）+ 尾随空段落并聚焦之。文件选择留到点占位
/// 块选中后的「选择图片」按钮，不再在应用瞬间弹选择器、
/// 取消即无事发生。
fn op_insert_media_placeholder(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    gallery: bool,
    focus_req: &mut Signal<Option<(String, usize)>>,
) {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("media placeholder: block not found {bid}"));
        return;
    };
    let mut ph = new_block(if gallery { "gallery" } else { "image" });
    if gallery {
        set_attr(&mut ph, "items", json!([]));
    } else {
        set_attr(&mut ph, "fileId", json!(""));
    }
    let para = new_block("paragraph");
    let para_id = para.id.clone().unwrap_or_default();
    // 尾随空段（D-14，原版 use-slash needsTrailingParagraph
    // + next-empty 判定）：占位块之后已有现成空段就不多
    // 插，焦点改落该段；否则补一段并聚焦之。
    let mut focus_id = para_id.clone();
    match loc {
        Loc::Top(i) => {
            if next_is_empty_para(&d, i) {
                focus_id = d[i + 1].id.clone().unwrap_or_default();
                d[i] = ph;
            } else {
                d[i] = ph;
                d.insert(i + 1, para);
            }
        }
        Loc::Item(li, ii) => {
            // 列表项里应用：把该项提出列表（与 op_convert 同结构）
            let list = d[li].clone();
            let items = list.children.clone().unwrap_or_default();
            let head: Vec<Node> = items[..ii].to_vec();
            let tail: Vec<Node> = items[ii + 1..].to_vec();
            let mut replacement: Vec<Node> = Vec::new();
            if !head.is_empty() {
                let mut hl = list.clone();
                hl.children = Some(head);
                replacement.push(hl);
            }
            replacement.push(ph);
            // 占位块之后紧跟的是 tail 列表（非空段）或原
            // 列表的下一块：后者已是现成空段时不插新段。
            let next_empty = if tail.is_empty() {
                d.get(li + 1).filter(|n| is_empty_para(n))
            } else {
                None
            };
            if let Some(n) = next_empty {
                focus_id = n.id.clone().unwrap_or_default();
            } else {
                replacement.push(para);
            }
            if !tail.is_empty() {
                let mut tl = list.clone();
                tl.id = Some(gen_id());
                tl.children = Some(tail);
                replacement.push(tl);
            }
            d.splice(li..=li, replacement);
        }
    }
    doc.set(d);
    focus_req.set(Some((focus_id, 0)));
    diag::log("EDIT", &format!("slash media placeholder gallery={gallery} {bid}"));
}

fn op_convert(
    doc: &mut Signal<Vec<Node>>,
    bid: &str,
    act: &str,
    html: &str,
    focus_req: &mut Signal<Option<(String, usize)>>,
    md_edit: &mut Signal<Option<String>>,
) -> Option<String> {
    let mut d = doc.read().clone();
    let Some(loc) = find_loc(&d, bid) else {
        diag::log("EDIT", &format!("convert: block not found {bid}"));
        return None;
    };
    let inlines = editor_html_to_inlines(html);

    // 列表项：列表类型互换只改父列表；其余转换把该项提出列表
    if let Loc::Item(li, ii) = loc {
        if act == "bulletList" || act == "numberList" {
            d[li].node_type = Some(
                if act == "bulletList" {
                    "bulleted-list"
                } else {
                    "numbered-list"
                }
                .to_string(),
            );
            let len = plain_len(node_at(&d, loc));
            doc.set(d);
            focus_req.set(Some((bid.to_string(), len)));
            diag::log("EDIT", &format!("convert list type -> {act}"));
            return None;
        }
        let list = d[li].clone();
        let items = list.children.clone().unwrap_or_default();
        let mut converted = items[ii].clone();
        converted.children = Some(inlines);
        let head: Vec<Node> = items[..ii].to_vec();
        let tail: Vec<Node> = items[ii + 1..].to_vec();
        let mut replacement: Vec<Node> = Vec::new();
        if !head.is_empty() {
            let mut hl = list.clone();
            hl.children = Some(head);
            replacement.push(hl);
        }
        let mut focus = (bid.to_string(), 0usize);
        if act == "divider" {
            let mut div = new_block("divider");
            div.id = Some(bid.to_string());
            div.children = None;
            replacement.push(div);
            // 尾随空段（D-14）：divider 之后紧跟的是 tail
            // 列表（非空段）或原列表的下一块；后者已是现
            // 成空段就不多插、焦点落该段，否则补一段。
            let next_empty = if tail.is_empty() {
                d.get(li + 1).filter(|n| is_empty_para(n))
            } else {
                None
            };
            if let Some(n) = next_empty {
                focus = (n.id.clone().unwrap_or_default(), 0);
            } else {
                let para = new_block("paragraph");
                focus = (para.id.clone().unwrap_or_default(), 0);
                replacement.push(para);
            }
        } else {
            apply_type(&mut converted, act);
            focus = (bid.to_string(), plain_len(&converted));
            replacement.push(converted);
        }
        if !tail.is_empty() {
            let mut tl = list.clone();
            tl.id = Some(gen_id());
            tl.children = Some(tail);
            replacement.push(tl);
        }
        d.remove(li);
        for (k, b) in replacement.into_iter().enumerate() {
            d.insert(li + k, b);
        }
        doc.set(d);
        focus_req.set(Some(focus));
        diag::log("EDIT", &format!("convert lift {bid} -> {act}"));
        return None;
    }

    let Loc::Top(i) = loc else { return None };

    // 代码/列表/Callout：原版模型是 md 源段落（use-slash.js 实证），
    // 不造 codeBlock/bulleted-list/callout 类型。转后直接进源码
    // 编辑态（原版转换后光标落在源码段落里）。
    if matches!(act, "bulletList" | "numberList" | "codeBlock" | "callout") {
        let cur_text: String = inlines.iter().map(|n| n.plain_text()).collect();
        let plain = strip_md_prefixes(&cur_text);
        let plain = if plain.trim().is_empty() {
            match act {
                "bulletList" | "numberList" => "列表项".to_string(),
                "callout" => "提示内容".to_string(),
                _ => String::new(),
            }
        } else {
            plain
        };
        let src = match act {
            "bulletList" => plain
                .lines()
                .map(|l| format!("- {l}"))
                .collect::<Vec<_>>()
                .join("\n"),
            "numberList" => plain
                .lines()
                .enumerate()
                .map(|(k, l)| format!("{}. {l}", k + 1))
                .collect::<Vec<_>>()
                .join("\n"),
            "codeBlock" => {
                // D-13（原版 use-slash.js:514-516）：围栏随
                // 正文最长连续反引号串加长（下限 3），且正
                // 文保留原样、不剥 md 前缀（cleanedText 直
                // 入围栏）；其余 md 类臂维持先剥前缀口径。
                let body = if plain.is_empty() {
                    String::new()
                } else {
                    cur_text.clone()
                };
                let longest = body
                    .split(|c| c != '`')
                    .map(|s| s.chars().count())
                    .max()
                    .unwrap_or(0);
                let fence = "`".repeat((longest + 1).max(3));
                format!("{fence}\n{body}\n{fence}")
            }
            _ => {
                let body = plain
                    .lines()
                    .map(|l| format!("> {l}"))
                    .collect::<Vec<_>>()
                    .join("\n");
                format!("> [!NOTE]\n{body}")
            }
        };
        let n = node_at_mut(&mut d, loc);
        n.node_type = Some("paragraph".into());
        clear_type_fields(n);
        n.children = Some(vec![text_node(&src)]);
        // Callout 在原版尾随空段清单内（斜杠审计 S7）
        if act == "callout" && !next_is_empty_para(&d, i) {
            d.insert(i + 1, new_block("paragraph"));
        }
        doc.set(d);
        md_edit.set(Some(bid.to_string()));
        diag::log("EDIT", &format!("convert {bid} -> md source ({act})"));
        return Some(src);
    }

    if act == "divider" {
        let mut divider = new_block("divider");
        divider.id = Some(bid.to_string());
        divider.children = None;
        // 尾随空段（D-14）：下一块已是现成空段就不多插、
        // 焦点落该段；否则补一段并聚焦之。
        let focus_id = if next_is_empty_para(&d, i) {
            d[i] = divider;
            d[i + 1].id.clone().unwrap_or_default()
        } else {
            let para = new_block("paragraph");
            let para_id = para.id.clone().unwrap_or_default();
            d[i] = divider;
            d.insert(i + 1, para);
            para_id
        };
        doc.set(d);
        focus_req.set(Some((focus_id, 0)));
        diag::log("EDIT", &format!("convert {bid} -> divider"));
        return None;
    }

    let n = node_at_mut(&mut d, loc);
    n.children = Some(inlines);
    apply_type(n, act);
    let len = plain_len(node_at(&d, loc));
    // 尾随空段（斜杠审计 S7，原版 needsTrailingParagraph）：
    // todo/musicCard/imgTextCard/imageTextRow 转换后，下一块
    // 不是现成的空段落就补一个（divider/图片/画廊各自已带）
    if matches!(act, "todo" | "musicCard" | "imgTextCard" | "imageTextRow")
        && !next_is_empty_para(&d, i)
    {
        d.insert(i + 1, new_block("paragraph"));
    }
    // 图文卡/混排（D-12）：卡片块本身是原子块、不可落点，
    // 焦点落尾随空段起点（上一步已保证 i+1 为空段——原版
    // shouldFocusAfterBlock 口径）；其余仍落本块。
    let focus = if matches!(act, "imgTextCard" | "imageTextRow") {
        (d[i + 1].id.clone().unwrap_or_default(), 0)
    } else if act == "musicCard" {
        // 音乐卡输入胶囊（原版 use-slash 口径）：聚焦胶囊
        // 且光标落在占位文本末尾（usize::MAX 由 __mnFocus
        // 钳到文本长）
        (bid.to_string(), usize::MAX)
    } else {
        (bid.to_string(), len)
    };
    doc.set(d);
    focus_req.set(Some(focus));
    diag::log("EDIT", &format!("convert {bid} -> {act}"));
    None
}

/// 音乐输入胶囊（原版 editor.render.js musicCard input 分支）：
/// 可编辑的玻璃胶囊，占位文案是真实文本（聚焦后光标落其末
/// 尾）；粘贴/输入/回车由桥的 musicInput 链复检全文，命中
/// URL 即整节点转 loading——本组件随之卸载、骨架接棒，焦
/// 点自然消失（加载期无光标，原版 removeAllRanges 口径）。
/// 独立组件：保证每次进入 input 态都以占位文案全新挂载，
/// 不复用其他块编辑组件的初始 HTML 状态。
#[component]
fn MusicInputPill(bid: String) -> Element {
    let init_html = use_hook(|| {
        crate::i18n::t("media.music_paste_hint")
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
    });
    rsx! {
        div {
            class: "music-input-pill",
            "data-bid": "{bid}",
            "data-btype": "musicInput",
            contenteditable: "true",
            spellcheck: "false",
            dangerous_inner_html: "{init_html}",
        }
    }
}

#[component]
fn EditorBlock(
    node: Node,
    gen: Signal<u32>,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
    media_req: Signal<Option<MediaReq>>,
) -> Element {
    let ty = node.block_type().unwrap_or("").to_string();
    // 上下文钩子必须无条件、同序地在组件顶部调用：块类型转换会让
    // 同一实例在 match 分支间切换，分支内调用 try_use_context 会让
    // 钩子槽位类型错位（MdEdit 槽被 SelBlock 读）直接 panic——斜杠
    // 转分割线时实测崩溃。分支内只许用这里算好的 editing / sel。
    let md_ctx = try_use_context::<crate::blocks::MdEdit>();
    let sel_ctx = try_use_context::<crate::blocks::SelBlock>();
    let act_ctx = try_use_context::<crate::blocks::ActiveEdit>();
    let bid0 = node.id.clone().unwrap_or_default();
    let editing = md_ctx
        .as_ref()
        .map(|c| c.0.read().as_deref() == Some(bid0.as_str()))
        .unwrap_or(false);
    // 聚焦编辑中：即使文本已像 Markdown 也保持可编辑形态，
    // 失焦后才按分类转预览（原版 blur 转换口径，见 ActiveEdit）
    let active = act_ctx
        .as_ref()
        .map(|c| c.0.read().as_deref() == Some(bid0.as_str()))
        .unwrap_or(false);
    let sel = sel_ctx
        .as_ref()
        .map(|c| c.0.read().as_deref() == Some(bid0.as_str()))
        .unwrap_or(false);
    // 卡片交互专项：编辑态（描边 + 子区域门禁的渲染侧标
    // 记，桥凭 card-editing 类分流点按）。同为顶部无条件
    // 读取（钩子铁律同上）。
    let cedit_ctx = try_use_context::<crate::blocks::CardEdit>();
    let card_editing = cedit_ctx
        .as_ref()
        .map(|c| c.0.read().as_deref() == Some(bid0.as_str()))
        .unwrap_or(false);
    match ty.as_str() {
        "paragraph" => {
            // md 源段落：预览态（点回源码编辑）/ 源码编辑态。
            // 编辑态优先于分类结果：源码打字中间态（如只打了「-」）
            // 暂时不构成合法 md，若按分类切换分支会把编辑区重挂载
            // 成普通段落、丢掉 mdsrc 语义——原版源码段落编辑期间
            // 始终是普通 <p>，同理编辑态必须稳定不 flicker。
            let plain = node.plain_text();
            let bid = node.id.clone().unwrap_or_default();
            if editing || (!active && crate::blocks::md_classify(&plain).is_some()) {
                if editing {
                    let esc = plain
                        .replace('&', "&amp;")
                        .replace('<', "&lt;")
                        .replace('>', "&gt;")
                        .replace('\n', "<br>");
                    rsx! {
                        EditableDiv {
                            node,
                            cls: "blk-p ed-line".to_string(),
                            force_btype: "mdsrc".to_string(),
                            initial_html: esc,
                        }
                    }
                } else {
                    let ctx = md_ctx;
                    let plain_off = plain.encode_utf16().count();
                    rsx! {
                        div {
                            class: "md-hit",
                            "data-bids": "{bid}",
                            onclick: move |_| {
                                if let Some(c) = ctx {
                                    let mut s = c.0;
                                    s.set(Some(bid.clone()));
                                    diag::log(
                                        "EDIT",
                                        &format!(
                                            "md preview -> source edit {bid} form=single caret=end offset={plain_off}"
                                        ),
                                    );
                                    // 落点 = 源码末尾（原版同行为：
                                    // use-editor-dom.js:117-135 块级预览
                                    // 与 183-238 通用还原均为
                                    // selectNodeContents + collapse(false)，
                                    // 表格分行时落最后一行末尾——单块模型
                                    // 下即全文末尾；点击位置不参与落点）。
                                    // 同步武装桥的挂载守卫 __mnFocusAtMount，
                                    // 不再 setTimeout 硬等（与 list-group 同路）。
                                    sync_arm_md_focus(&bid);
                                }
                            },
                            crate::blocks::MdPreview { text: plain }
                        }
                    }
                }
            } else {
                rsx! { EditableDiv { node, cls: "blk-p ed-line".to_string() } }
            }
        }
        "heading" => {
            let lv = crate::blocks::heading_level(&node);
            let cls = format!("blk-h{lv} ed-line");
            rsx! { EditableDiv { node, cls } }
        }
        "quote" => {
            // C-04：结构对齐原版 blockquote > div——.blk-quote
            // 类挂 blockquote 外层，EditableDiv 只留 ed-line
            rsx! {
                blockquote { class: "blk-quote",
                    EditableDiv { node, cls: "ed-line".to_string() }
                }
            }
        }
        "callout" => {
            let variant = node
                .extra
                .get("calloutType")
                .or_else(|| node.extra.get("kind"))
                .or_else(|| node.extra.get("variant"))
                .and_then(|v| v.as_str())
                .unwrap_or("note")
                .to_lowercase();
            let (icon, title_key) = match variant.as_str() {
                "warning" => ("⚠", "callout.warning"),
                "tip" => ("💡", "callout.tip"),
                "important" => ("❗", "callout.important"),
                "caution" => ("⛔", "callout.caution"),
                _ => ("ℹ", "callout.note"),
            };
            let vcls = if matches!(
                variant.as_str(),
                "note" | "warning" | "tip" | "important" | "caution"
            ) {
                variant.clone()
            } else {
                "note".to_string()
            };
            rsx! {
                div { class: "callout callout-{vcls}",
                    div { class: "callout-header",
                        span { class: "callout-icon", "{icon}" }
                        span { class: "callout-title", "{crate::i18n::t(title_key)}" }
                    }
                    EditableDiv { node, cls: "callout-body ed-line".to_string() }
                }
            }
        }
        "codeBlock" => {
            rsx! { EditableDiv { node, cls: "blk-code ed-line".to_string() } }
        }
        "todo" => {
            let done = crate::blocks::todo_checked(&node);
            let bid = node.id.clone().unwrap_or_default();
            let label = node.plain_text();
            rsx! {
                div { class: if done { "todo-row done" } else { "todo-row" },
                    button {
                        class: if done { "todo-checkbox on" } else { "todo-checkbox" },
                        // C-05：原版为真 checkbox input 带
                        // aria-checked 与 aria-label=待办文本；
                        // button 形态以 role=checkbox 等价补齐
                        role: "checkbox",
                        "aria-checked": "{done}",
                        "aria-label": "{label}",
                        onclick: {
                            let bid = bid.clone();
                            let mut doc = doc;
                            let persist = persist.clone();
                            move |_| {
                                let mut d = doc.read().clone();
                                if let Some(loc) = find_loc(&d, &bid) {
                                    let n = node_at_mut(&mut d, loc);
                                    let cur = crate::blocks::todo_checked(n);
                                    set_attr(n, "checked", json!(!cur));
                                    n.extra.remove("checked");
                                    doc.set(d.clone());
                                    persist.call(d, title.read().clone(), data);
                                    diag::log("EDIT", &format!("todo toggle {bid} -> {}", !cur));
                                }
                            }
                        },
                    }
                    EditableDiv { node, cls: "todo-text ed-line".to_string() }
                }
            }
        }
        "bulleted-list" | "numbered-list" => {
            let ordered = ty == "numbered-list";
            let kids = node.children.clone().unwrap_or_default();
            rsx! {
                div { class: "list-wrap",
                    for (j, item) in kids.iter().enumerate() {
                        div { key: "{item.id.clone().unwrap_or_default()}", class: "list-row",
                            span { class: "list-marker",
                                if ordered { "{j + 1}." } else { "•" }
                            }
                            EditableDiv { node: item.clone(), cls: "ed-line".to_string() }
                        }
                    }
                }
            }
        }
        "imgTextCard" | "imageTextRow" => {
            let bid = node.id.clone().unwrap_or_default();
            let cls = match (sel, card_editing) {
                (true, true) => "blk-wrap sel card-editing",
                (true, false) => "blk-wrap sel",
                (false, true) => "blk-wrap card-editing",
                (false, false) => "blk-wrap",
            };
            rsx! {
                div { class: "{cls}", "data-wrapbid": "{bid}", "data-wtype": "{ty}",
                    BlockView { node, gen }
                }
            }
        }
        "musicCard" => {
            let bid = node.id.clone().unwrap_or_default();
            let status = node
                .extra
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            if status == "input" {
                // 输入态 = 可编辑胶囊（原版 editor.render.js 的
                // musicCard input 分支）：contenteditable、占位
                // 文案即真实文本、桥的 musicInput 链负责解析；
                // 不进 blk-wrap（原版胶囊就是编辑区直子元素）。
                return rsx! {
                    MusicInputPill { bid: bid.clone() }
                };
            }
            let cls = match (sel, card_editing) {
                (true, true) => "blk-wrap blk-music sel card-editing",
                (true, false) => "blk-wrap blk-music sel",
                (false, true) => "blk-wrap blk-music card-editing",
                (false, false) => "blk-wrap blk-music",
            };
            rsx! {
                div { class: "{cls}", "data-wrapbid": "{bid}", "data-wtype": "{ty}",
                    BlockView { node, gen }
                }
            }
        }
        _ => {
            let bid = node.id.clone().unwrap_or_default();
            let cls = match (sel, card_editing) {
                (true, true) => "blk-wrap sel card-editing",
                (true, false) => "blk-wrap sel",
                (false, true) => "blk-wrap card-editing",
                (false, false) => "blk-wrap",
            };
            rsx! {
                div { class: "{cls}", "data-wrapbid": "{bid}", "data-wtype": "{ty}",
                    BlockView { node, gen }
                }
            }
        }
    }
}

/// 非受控可编辑区：初始 HTML 只在挂载时写一次（use_hook 锁定），
/// 此后内容归浏览器，模型同步走 JS 桥消息。data-btype 供桥区分
/// 代码块（回车不分块、斜杠不触发）。填充/回收统一走编辑对
/// （inlines_to_editor_html / editor_html_to_inlines，全字面口径，
/// 斜杠审计 S3）；只读渲染与导出仍走渲染对。
#[component]
fn EditableDiv(
    node: Node,
    cls: String,
    force_btype: Option<String>,
    initial_html: Option<String>,
) -> Element {
    let bid = node.id.clone().unwrap_or_default();
    let btype = force_btype
        .clone()
        .unwrap_or_else(|| node.block_type().unwrap_or("paragraph").to_string());
    let initial = use_hook(|| {
        initial_html
            .clone()
            .unwrap_or_else(|| inlines_to_editor_html(node.children.as_deref().unwrap_or(&[])))
    });
    rsx! {
        div {
            class: "{cls}",
            "data-bid": "{bid}",
            "data-btype": "{btype}",
            contenteditable: "true",
            dangerous_inner_html: "{initial}",
        }
    }
}

/// 斜杠行命中高亮切分（D-4，原版 slash-panel.js hl 口径）：
/// 在 text 中找 q（已 trim+小写）的首个大小写不敏感命中，
/// 切成（命中前，命中段，命中后）；无命中时命中段为 None。
fn slash_hl_parts(text: &str, q: &str) -> (String, Option<String>, String) {
    let miss = || (text.to_string(), None, String::new());
    if q.is_empty() || text.is_empty() {
        return miss();
    }
    let t: Vec<char> = text.chars().collect();
    let p: Vec<char> = q.chars().collect();
    if p.is_empty() || p.len() > t.len() {
        return miss();
    }
    'outer: for i in 0..=(t.len() - p.len()) {
        for (j, qc) in p.iter().enumerate() {
            let mut low = t[i + j].to_lowercase();
            if low.next() != Some(*qc) || low.next().is_some() {
                continue 'outer;
            }
        }
        return (
            t[..i].iter().collect(),
            Some(t[i..i + p.len()].iter().collect()),
            t[i + p.len()..].iter().collect(),
        );
    }
    miss()
}

/// 斜杠行文字（D-4）：命中段包 <mark class="slash-match">。
#[component]
fn SlashHl(text: String, q: String) -> Element {
    let (pre, mid, post) = slash_hl_parts(&text, &q);
    rsx! {
        "{pre}"
        if let Some(m) = mid {
            mark { class: "slash-match", "{m}" }
        }
        "{post}"
    }
}

/// 斜杠面板：21 条命令（基础/媒体两组）+ 链接表单态。定位用
/// 桥传来的光标矩形（fixed），靠下时上翻避免溢出屏幕。
#[component]
fn SlashPanel(
    bid: String,
    filter: String,
    anchor_x: f64,
    anchor_top: f64,
    anchor_bottom: f64,
    mut panel: Signal<Option<(String, String, f64, f64, f64)>>,
    mut slash_click: Signal<Option<(String, String)>>,
    mut link_for: Signal<Option<String>>,
    mut link_pos: Signal<(f64, f64, f64)>,
    mut link_click: Signal<Option<(String, String)>>,
) -> Element {
    // 定位/宽度 = 原版 use-slash.js 公式逐项移植：宽度由命令标题
    // 启发式估算（title 字数×16 + shortcut×8 + 固定 56，分组 +20），
    // min(360, max(220, 内容宽+12, 视口宽-24))；left 钳制在视口内
    // 12px 边距；top = 锚底 + 10，放不下（高 260 估算）则上翻。
    // 视口量以 visualViewport 为准（原版公式口径）：真机软
    // 键盘弹起时 vv 的 offset/height 与 inner* 分叉，只用
    // inner* 定位会把面板放到键盘下方的不可见区（真机
    // 「下半部输入、面板跑到上半部」的主因，代码级定性）；
    // vv 缺失时 fallback inner*、偏移为 0。
    let (vx, vy, vw, vh) = web_sys::window()
        .map(|w| {
            let iw = w.inner_width().ok().and_then(|v| v.as_f64()).unwrap_or(0.0);
            let ih = w.inner_height().ok().and_then(|v| v.as_f64()).unwrap_or(0.0);
            match w.visual_viewport() {
                Some(vp) => (vp.offset_left(), vp.offset_top(), vp.width(), vp.height()),
                None => (0.0, 0.0, iw, ih),
            }
        })
        .unwrap_or((0.0, 0.0, 0.0, 0.0));
    let mut max_content_w: f64 = 240.0;
    for c in SLASH_CMDS.iter() {
        let title_w = crate::i18n::t(c.title).chars().count() as f64 * 16.0;
        let short_w = c.shortcut.chars().count() as f64 * 8.0;
        let mut row_w = 24.0 + 10.0 + title_w + (if short_w > 0.0 { 8.0 + short_w } else { 0.0 }) + 22.0;
        if c.group > 0 {
            row_w += 20.0;
        }
        if row_w > max_content_w {
            max_content_w = row_w;
        }
    }
    let width = 360.0f64.min((max_content_w + 12.0).max(220.0).max(vw - 24.0));
    let left = (vx + vw - width - 12.0).min(anchor_x - 8.0).max(vx + 12.0);
    let mut top = anchor_bottom + 10.0;
    if top + 260.0 > vy + vh - 8.0 {
        top = (anchor_top - 260.0 - 10.0).max(vy + 76.0);
    }
    // 动态限高（原版 slash-panel 内联口径）：上限随锚点位
    // 置收紧、面板永不溢出视口底——下半部带靠收缩而非翻
    // 转解决；CSS 的静态 max-height:320 只作兜底。
    let style = format!(
        "left:{left}px;top:{top}px;width:{width}px;max-height:min(320px,calc(100dvh - {}px))",
        top + 16.0
    );
    if link_for.read().as_deref() == Some(bid.as_str()) {
        // 链接表单（斜杠审计 S8，原版口径）：预填 https:// 并
        // 聚焦全选；取消只退回命令列表（面板不关）；校验走 URL
        // 解析 + 协议白名单，不再是 starts_with 粗判。
        let mut url = use_signal(|| "https://".to_string());
        let mut err = use_signal(|| false);
        return rsx! {
            div { id: "slash-panel", class: "slash-panel", style: "{style}",
                div { class: "slash-link-form",
                    div { class: "slash-link-title", "{crate::i18n::t(\"slash.link_form_title\")}" }
                    input {
                        class: "slash-link-input",
                        placeholder: "https://example.com",
                        value: "{url}",
                        onmounted: move |_| {
                            spawn(async move {
                                let mut eval = document::eval(
                                    "const i = document.querySelector('.slash-link-input'); if (i) { i.focus(); i.select(); } dioxus.send(null);",
                                );
                                let _ = eval.recv::<Value>().await;
                            });
                        },
                        oninput: move |e| {
                            err.set(false);
                            url.set(e.value());
                        },
                    }
                    if *err.read() {
                        div { class: "slash-link-error", "{crate::i18n::t(\"slash.link_invalid\")}" }
                    }
                    div { class: "slash-link-actions",
                        button {
                            onclick: move |_| {
                                link_for.set(None);
                            },
                            "{crate::i18n::t(\"action.cancel\")}"
                        }
                        button {
                            class: "slash-link-submit",
                            onclick: {
                                let bid = bid.clone();
                                move |_| {
                                    let u = url.read().trim().to_string();
                                    let ok = web_sys::Url::new(&u)
                                        .map(|p| {
                                            p.protocol() == "http:" || p.protocol() == "https:"
                                        })
                                        .unwrap_or(false);
                                    if !ok {
                                        err.set(true);
                                        return;
                                    }
                                    link_click.set(Some((bid.clone(), u)));
                                }
                            },
                            "{crate::i18n::t(\"slash.link_insert\")}"
                        }
                    }
                }
            }
        };
    }
    // 过滤/分组逐项对原版 slash-model.js filter：
    // 有查询 → 全串（本地化标题+副标题+keywords+type+拼音）
    // 小写包含匹配，前缀命中（标题+keywords 或拼音以查询
    // 开头）优先，其余按标题排序，无分组头；
    // 无查询 → 「最近使用」组置顶（按存储顺序，行尾带
    // 「最近」胶囊），其余命令按基础/媒体分组且排除已在
    // 最近组里的。
    let q = filter.trim().to_lowercase();
    struct SRow {
        head: Option<String>,
        cmd: Option<&'static SlashCmd>,
        sel: bool,
        recent: bool,
    }
    let mut rows: Vec<SRow> = Vec::new();
    if !q.is_empty() {
        let mut hits: Vec<&'static SlashCmd> = SLASH_CMDS
            .iter()
            .filter(|c| {
                let hay = format!(
                    "{} {} {} {} {}",
                    crate::i18n::t(c.title),
                    crate::i18n::t(c.sub),
                    c.kw,
                    c.ty,
                    c.py
                )
                .to_lowercase();
                hay.contains(&q)
            })
            .collect();
        hits.sort_by(|a, b| {
            let starts = |c: &SlashCmd| {
                let tk = format!("{} {}", crate::i18n::t(c.title), c.kw).to_lowercase();
                (tk.starts_with(&q) || c.py.starts_with(&q)) as u8
            };
            starts(b)
                .cmp(&starts(a))
                .then_with(|| slash_title_cmp(&crate::i18n::t(a.title), &crate::i18n::t(b.title)))
        });
        for (i, c) in hits.into_iter().enumerate() {
            rows.push(SRow { head: None, cmd: Some(c), sel: i == 0, recent: false });
        }
    } else {
        let recent_ids = slash_recent_ids();
        let recent_cmds: Vec<&'static SlashCmd> = recent_ids
            .iter()
            .filter_map(|oid| SLASH_CMDS.iter().find(|c| &c.oid == oid))
            .collect();
        let mut first = true;
        if !recent_cmds.is_empty() {
            rows.push(SRow {
                head: Some(crate::i18n::t("slash.recent")),
                cmd: None,
                sel: false,
                recent: false,
            });
            for c in &recent_cmds {
                rows.push(SRow { head: None, cmd: Some(c), sel: first, recent: true });
                first = false;
            }
        }
        for g in [0u8, 1u8] {
            let items: Vec<&'static SlashCmd> = SLASH_CMDS
                .iter()
                .filter(|c| c.group == g && !recent_ids.iter().any(|oid| oid == c.oid))
                .collect();
            if items.is_empty() {
                continue;
            }
            rows.push(SRow {
                head: Some(crate::i18n::t(if g == 0 {
                    "slash.group_basic"
                } else {
                    "slash.group_media"
                })),
                cmd: None,
                sel: false,
                recent: false,
            });
            for c in items {
                rows.push(SRow { head: None, cmd: Some(c), sel: first, recent: false });
                first = false;
            }
        }
    }
    let any = rows.iter().any(|r| r.cmd.is_some());
    rsx! {
        div { id: "slash-panel", class: "slash-panel", style: "{style}",
            for row in rows {
                if let Some(label) = row.head {
                    div { class: "slash-section-heading", "{label}" }
                }
                if let Some(c) = row.cmd {
                    button {
                        class: if row.sel { "slash-row sel" } else { "slash-row" },
                        "data-act": "{c.act}",
                        "aria-selected": if row.sel { "true" } else { "false" },
                        onclick: {
                            let act = c.act;
                            let bid = bid.clone();
                            move |_| {
                                if act == "link" {
                                    // 与键盘 slashLink 路径一致化：
                                    // 进表单的同时以面板现值锚定
                                    // link_pos，不再借面板分支残留
                                    // 锚点渲染（潜伏不一致收口）。
                                    link_pos.set((anchor_x, anchor_top, anchor_bottom));
                                    link_for.set(Some(bid.clone()));
                                } else {
                                    panel.set(None);
                                    slash_click.set(Some((bid.clone(), act.to_string())));
                                }
                            }
                        },
                        span { class: "slash-row-icon",
                            crate::icons::Icon { name: c.icon.to_string(), size: 20, stroke_width: "1.9".to_string(), stroke: "currentColor".to_string() }
                        }
                        span { class: "slash-row-copy",
                            span { class: "slash-row-title",
                                span { class: "slash-row-title-text",
                                    SlashHl { text: crate::i18n::t(c.title), q: q.clone() }
                                }
                                if row.recent {
                                    span { class: "slash-recent-pill", "aria-label": "{crate::i18n::t(\"slash.recent\")}", "{crate::i18n::t(\"slash.recent_pill\")}" }
                                }
                            }
                            span { class: "slash-row-subtitle",
                                SlashHl { text: crate::i18n::t(c.sub), q: q.clone() }
                            }
                        }
                        if !c.shortcut.is_empty() {
                            span { class: "slash-shortcut", "{c.shortcut}" }
                        }
                    }
                }
            }
            if !any {
                // 空态（D-5，原版 slash-panel.js 全形）：28px
                // 搜索图标 + 未找到匹配命令 + 拼音 kbd 提示行，
                // role=status。
                div { class: "slash-empty-state", role: "status",
                    svg {
                        width: "28",
                        height: "28",
                        view_box: "0 0 20 20",
                        fill: "none",
                        stroke: "currentColor",
                        stroke_width: "1.5",
                        stroke_linecap: "round",
                        stroke_linejoin: "round",
                        "aria-hidden": "true",
                        circle { cx: "8.5", cy: "8.5", r: "5.5" }
                        line { x1: "12.5", y1: "12.5", x2: "17", y2: "17" }
                    }
                    div { "{crate::i18n::t(\"slash.no_match\")}" }
                    div { class: "slash-empty-hint",
                        "{crate::i18n::t(\"slash.empty_hint_lead\")}"
                        kbd { "bt" }
                        " {crate::i18n::t(\"slash.empty_hint_1\")} · "
                        kbd { "tp" }
                        " {crate::i18n::t(\"slash.empty_hint_2\")} · "
                        kbd { "yykp" }
                        " {crate::i18n::t(\"slash.empty_hint_3\")}"
                    }
                }
            }
        }
    }
}

/// 图文面板保存：文本写回块 extra["text"] 并落库（编辑器头部
/// 的两处调用——遮罩点击与「完成编辑」——共用）。
fn save_sheet_text(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: &PersistHandle,
    bid: &str,
    txt: &str,
) {
    let mut d = doc.read().clone();
    if let Some(loc) = find_loc(&d, bid) {
        node_at_mut(&mut d, loc)
            .extra
            .insert("text".to_string(), json!(txt));
        doc.set(d.clone());
        persist.call(d, title.read().clone(), data);
        diag::log("EDIT", &format!("imgtext sheet save {bid}"));
    }
}

/// 媒体文件处理：上传全部选中文件到 IDB + manifest，再按请求
/// 分发——SetImage 给图文块换图；Replace 把斜杠所在块替换为
/// 图片块（多选依次插入）或单个画廊块。
async fn handle_media_files(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    mut media_req: Signal<Option<MediaReq>>,
    persist: &PersistHandle,
) {
    let Some(req) = media_req.read().clone() else {
        return;
    };
    media_req.set(None);
    let Some(window) = web_sys::window() else {
        return;
    };
    let Some(document) = window.document() else {
        return;
    };
    let Some(input) = document
        .get_element_by_id("file-media")
        .and_then(|e| e.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        return;
    };
    let Some(files) = input.files() else {
        return;
    };
    let mut man: Value =
        serde_json::from_str(&manifest.read()).unwrap_or_else(|_| json!({"version": 1}));
    if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
        man["attachments"] = json!({});
    }
    let mut fids: Vec<String> = Vec::new();
    for i in 0..files.length() {
        let Some(file) = files.get(i) else { continue };
        let name = file.name();
        let mime = file.type_();
        let Ok(buf) = JsFuture::from(file.array_buffer()).await else {
            continue;
        };
        let bytes = js_sys::Uint8Array::new(&buf).to_vec();
        let fid = gen_id();
        if idb::put_attachment(&fid, &bytes).await.is_err() {
            continue;
        }
        man["attachments"][&fid] = json!({"name": name, "type": mime});
        fids.push(fid);
    }
    if fids.is_empty() {
        return;
    }
    let man_str = man.to_string();
    manifest.set(man_str.clone());
    let _ = idb::save_manifest(&man_str).await;

    let img_node = |fid: &str| {
        let mut extra = Map::new();
        extra.insert("attrs".to_string(), json!({"fileId": fid}));
        Node {
            text: None,
            node_type: Some("image".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            extra,
        }
    };
    let mut d = doc.read().clone();
    match req {
        MediaReq::SetImage { bid } => {
            if let Some(loc) = find_loc(&d, &bid) {
                node_at_mut(&mut d, loc)
                    .extra
                    .insert("attrs".to_string(), json!({"fileId": fids[0]}));
                diag::log("EDIT", &format!("imgtext set image {bid}"));
            }
        }
        MediaReq::GalleryPick { bid, index } => {
            if let Some(loc) = find_loc(&d, &bid) {
                let n = node_at_mut(&mut d, loc);
                // 写回形态与 gallery_items 的读序同构：attrs.
                // items 数组优先（保元素形态——裸串替裸串、
                // 对象改 fileId 键、纯 url 对象整替为 fileId
                // 对象），否则 children 图子节点形态。
                let items_form = n
                    .extra
                    .get("attrs")
                    .and_then(|a| a.get("items"))
                    .map(|v| v.is_array())
                    .unwrap_or(false);
                if items_form {
                    if let Some(items) = n
                        .extra
                        .get_mut("attrs")
                        .and_then(|a| a.get_mut("items"))
                        .and_then(|v| v.as_array_mut())
                    {
                        match index {
                            Some(i) => {
                                if let Some(slot) = items.get_mut(i) {
                                    if slot.is_string() {
                                        *slot = json!(fids[0]);
                                    } else if slot.get("fileId").is_some() {
                                        slot["fileId"] = json!(fids[0]);
                                    } else {
                                        *slot = json!({ "fileId": fids[0] });
                                    }
                                }
                            }
                            None => {
                                for f in &fids {
                                    items.push(json!(f));
                                }
                            }
                        }
                    }
                    diag::log("EDIT", &format!("gallery pick {bid} index={index:?} (items)"));
                } else {
                    match index {
                        Some(i) => {
                            if let Some(kid) = n.children.as_mut().and_then(|c| c.get_mut(i)) {
                                kid.extra
                                    .insert("attrs".to_string(), json!({ "fileId": fids[0] }));
                            }
                        }
                        None => {
                            let kids = n.children.get_or_insert_with(Vec::new);
                            for f in &fids {
                                kids.push(img_node(f));
                            }
                        }
                    }
                    diag::log("EDIT", &format!("gallery pick {bid} index={index:?} (children)"));
                }
            }
        }
        MediaReq::Replace { bid, gallery } => {
            let nodes: Vec<Node> = if gallery {
                let mut g = new_block("gallery");
                g.children = Some(fids.iter().map(|f| img_node(f)).collect());
                vec![g]
            } else {
                fids.iter().map(|f| img_node(f)).collect()
            };
            match find_loc(&d, &bid) {
                Some(Loc::Top(i)) => {
                    d.remove(i);
                    for (k, n) in nodes.into_iter().enumerate() {
                        d.insert(i + k, n);
                    }
                }
                Some(Loc::Item(li, _)) => {
                    for (k, n) in nodes.into_iter().enumerate() {
                        d.insert(li + 1 + k, n);
                    }
                }
                None => {
                    for n in nodes {
                        d.push(n);
                    }
                }
            }
            diag::log("EDIT", &format!("slash media replace {bid} gallery={gallery}"));
        }
    }
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
}

/// 背景色 8 色（原版 BgSheet：冷雾/暖沙/浅绿/浅蓝/浅粉/米橙/淡紫/浅杏）。
const BG_COLORS: [&str; 8] = [
    "#eaeef2", "#e8e0d4", "#d4e8d0", "#d0e0e8", "#e8d0d4", "#fff3e0", "#e8e0f0",
    "#f0e8d0",
];

/// 添加附件：读 #file-attach 选中的文件 → 写 IDB 附件库 →
/// 更新 manifest → 文档末尾插入图片/附件块并落库。
async fn attach_file(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    persist: &PersistHandle,
    ed_status: crate::settings::Toast,
) {
    let Some(window) = web_sys::window() else {
        return;
    };
    let Some(document) = window.document() else {
        return;
    };
    let Some(input) = document
        .get_element_by_id("file-attach")
        .and_then(|e| e.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        return;
    };
    let Some(files) = input.files() else {
        return;
    };
    for fi in 0..files.length() {
        let Some(file) = files.get(fi) else {
            continue;
        };
        attach_one(&file, doc, title, data, manifest, persist, ed_status).await;
    }
}

/// 单个附件文件：写 IDB → 更新 manifest → 末尾插块并落库。
async fn attach_one(
    file: &web_sys::File,
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut manifest: Signal<String>,
    persist: &PersistHandle,
    ed_status: crate::settings::Toast,
) {
    let name = file.name();
    let mime = file.type_();
    let Ok(buf) = JsFuture::from(file.array_buffer()).await else {
        return;
    };
    let bytes = js_sys::Uint8Array::new(&buf).to_vec();
    let fid = gen_id();
    if let Err(e) = idb::put_attachment(&fid, &bytes).await {
        diag::log("EDIT", &format!("attach put err: {e:?}"));
        return;
    }
    // manifest.attachments[fid] = {name, type}
    let mut man: Value =
        serde_json::from_str(&manifest.read()).unwrap_or_else(|_| json!({"version": 1}));
    if !man.get("attachments").map(|a| a.is_object()).unwrap_or(false) {
        man["attachments"] = json!({});
    }
    man["attachments"][&fid] = json!({"name": name, "type": mime});
    let man_str = man.to_string();
    manifest.set(man_str.clone());
    let _ = idb::save_manifest(&man_str).await;

    let is_image = mime.starts_with("image/");
    let mut extra = Map::new();
    let node = if is_image {
        extra.insert("attrs".to_string(), json!({"fileId": fid}));
        Node {
            text: None,
            node_type: Some("image".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            extra,
        }
    } else {
        extra.insert("fileId".to_string(), Value::String(fid.clone()));
        // 文件名冗余写节点顶层（导出渲染的兜底读法同字段；
        // 编辑器渲染优先查 manifest，原版校验器不拒未知字段）
        extra.insert("name".to_string(), Value::String(name.clone()));
        extra.insert("status".to_string(), Value::String("done".to_string()));
        extra.insert("image".to_string(), Value::Bool(false));
        Node {
            text: None,
            node_type: Some("attachment".to_string()),
            id: Some(gen_id()),
            children: Some(vec![]),
            extra,
        }
    };
    let mut d = doc.read().clone();
    d.push(node);
    doc.set(d.clone());
    persist.call(d, title.read().clone(), data);
    ed_status.show("success", crate::i18n::t("attach.done"));
    diag::log("EDIT", &format!("attach {fid} {name} {mime} {}B", bytes.len()));
}
