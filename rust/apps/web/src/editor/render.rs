//! 渲染组（批 14 P-D5 自 editor.rs 拆出）：斜杠命令表与
//! 最近使用、合并列表预览、块组件（EditorBlock/EditableDiv/
//! 音乐输入胶囊）与斜杠面板。只做文件组织，行为不变。

use super::*;

/// 动作 / 图标名 / 标题键 / 副标题键 / 快捷键标记 / 分组
/// （0 基础、1 媒体）。行内命令（bold 等）由 JS 桥就地执行。
pub(super) struct SlashCmd {
    pub(super) act: &'static str,
    /// 原版 commands.js 的 id（最近使用按它存 localStorage）
    pub(super) oid: &'static str,
    /// 原版 commands.js 的 type（过滤 haystack 的一员，
    /// 原版 slash-model.js 口径：title+sub+kw+type+拼音）
    pub(super) ty: &'static str,
    pub(super) icon: &'static str,
    pub(super) title: &'static str,
    pub(super) sub: &'static str,
    pub(super) shortcut: &'static str,
    pub(super) group: u8,
    /// 原版 keywords（搜索全集的一部分，含中文词）
    pub(super) kw: &'static str,
    /// 原版 pinyin 首字母
    pub(super) py: &'static str,
}
pub(super) const SLASH_CMDS: &[SlashCmd] = &[
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
pub(super) fn slash_title_cmp(a: &str, b: &str) -> std::cmp::Ordering {
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
pub(super) fn slash_recent_ids() -> Vec<String> {
    let raw = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|st| st.get_item("memos_slash_recent_v1").ok().flatten())
        .unwrap_or_default();
    let mut ids: Vec<String> = serde_json::from_str::<Vec<String>>(&raw).unwrap_or_default();
    ids.truncate(6);
    ids
}

pub(super) fn slash_record_recent(act: &str) {
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

/// 合并列表预览（M6）：组内各段修剪文本 join('\n') 后走
/// 同一个 MdPreview（任务 checkbox、有序 start 在组内口径
/// 下由 marked 子集解析器自然成立）。点击 = 原版还原口
/// 径：模型里把组员合并回首块（首块 id 与位置保留，文本
/// 为合并源码），其余块删除，进源码编辑态、光标落合并
/// 源码末尾（原版 use-editor-dom.js:117-135 对块级预览统
/// 一 collapse(false) 落末尾；点击位置不参与落点，M9 审
/// 计的「点击处附近」系元素偏移误读，第八批双边复测证伪）。
#[component]
pub(super) fn MergedListPreview(
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

/// 音乐输入胶囊（原版 editor.render.js musicCard input 分支）：
/// 可编辑的玻璃胶囊，占位文案是真实文本（聚焦后光标落其末
/// 尾）；粘贴/输入/回车由桥的 musicInput 链复检全文，命中
/// URL 即整节点转 loading——本组件随之卸载、骨架接棒，焦
/// 点自然消失（加载期无光标，原版 removeAllRanges 口径）。
/// 独立组件：保证每次进入 input 态都以占位文案全新挂载，
/// 不复用其他块编辑组件的初始 HTML 状态。
#[component]
pub(super) fn MusicInputPill(bid: String) -> Element {
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
pub(super) fn EditorBlock(
    node: Node,
    gen: Signal<u32>,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
    media_req: Signal<Option<MediaReq>>,
    /// 批 11 MD-P2：段落 md 分类有无预判（父级每渲染趟单
    /// 点计算，与 flow_runs 组员判定同源）；仅段落分支
    /// 消费，非段落传 false。
    para_md: bool,
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
            // 批 11 MD-P2：门控用父级预判 para_md（与
            // flow_runs 同一趟分类），不在此重跑 md_classify。
            if editing || (!active && para_md) {
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
                .callout_type
                .as_deref()
                .unwrap_or("note")
                .to_lowercase();
            let title_key = match variant.as_str() {
                "warning" => "callout.warning",
                "tip" => "callout.tip",
                "important" => "callout.important",
                "caution" => "callout.caution",
                _ => "callout.note",
            };
            let vcls = if matches!(
                variant.as_str(),
                "note" | "warning" | "tip" | "important" | "caution"
            ) {
                variant.clone()
            } else {
                "note".to_string()
            };
            // 图标与 MD Callout 共用 icons::callout_icon_markup
            // 单一出处（C-17/D-23 统一，独立块弃 emoji）。
            let icon = crate::icons::callout_icon_markup(&vcls);
            rsx! {
                div { class: "callout callout-{vcls}",
                    div { class: "callout-header",
                        span { class: "callout-icon", dangerous_inner_html: "{icon}" }
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
            let start = list_start(&node);
            let kids = node.children.clone().unwrap_or_default();
            rsx! {
                div { class: "list-wrap",
                    for (j, item) in kids.iter().enumerate() {
                        div { key: "{item.id.clone().unwrap_or_default()}", class: "list-row",
                            span { class: "list-marker",
                                if ordered { "{start + j as u64}." } else { "•" }
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
            let status = node.status.as_deref().unwrap_or("").to_string();
            let cls = match (sel, card_editing) {
                (true, true) => "blk-wrap blk-music sel card-editing",
                (true, false) => "blk-wrap blk-music sel",
                (false, true) => "blk-wrap blk-music card-editing",
                (false, false) => "blk-wrap blk-music",
            };
            if status == "input" {
                // 输入态与成品态同走 blk-wrap（块级统一机制
                // 接入）：桥的拾起命中、卡片菜单（编辑/删除）、
                // 右键菜单、选中态都以 wrap 为命中面——胶囊旧
                // 形态裸挂编辑区直子时三路全够不着（菜单删除
                // 无路，而键盘删块收口 K4 明文「删胶囊走卡片
                // 菜单」是死路；长按拾起被归类为文本块又恒被
                // 自身光标挡下）。胶囊本体仍是 contenteditable
                // 输入面：桥 unitKind 对「内层可编辑区与 wrap
                // 同 id」的单元按文本块分类，光标在胶囊内时
                // 长按仍是文本选择/粘贴（既有文本块口径），
                // 光标不在时拾起与菜单同原子块无异。
                rsx! {
                    div { class: "{cls}", "data-wrapbid": "{bid}", "data-wtype": "{ty}",
                        MusicInputPill { bid: bid.clone() }
                    }
                }
            } else {
                rsx! {
                    div { class: "{cls}", "data-wrapbid": "{bid}", "data-wtype": "{ty}",
                        BlockView { node, gen }
                    }
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
pub(super) fn EditableDiv(
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
pub(super) fn slash_hl_parts(text: &str, q: &str) -> (String, Option<String>, String) {
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
pub(super) fn SlashHl(text: String, q: String) -> Element {
    let (pre, mid, post) = slash_hl_parts(&text, &q);
    rsx! {
        "{pre}"
        if let Some(m) = mid {
            mark { class: "slash-match", "{m}" }
        }
        "{post}"
    }
}

/// 链接表单提交（D-10）：校验与原版口径一致（URL 解析 +
/// http/https 协议白名单），不过置 err、通过置 link_click
/// 触发桥 __mnApplyLink。提交按钮点击与输入框 Enter 共用
/// 此一条路径（原版为 form onSubmit 统一承接）。
pub(super) fn submit_slash_link(
    url: Signal<String>,
    mut err: Signal<bool>,
    mut link_click: Signal<Option<(String, String)>>,
    bid: &str,
) {
    let u = url.read().trim().to_string();
    let ok = web_sys::Url::new(&u)
        .map(|p| p.protocol() == "http:" || p.protocol() == "https:")
        .unwrap_or(false);
    if !ok {
        err.set(true);
        return;
    }
    link_click.set(Some((bid.to_string(), u)));
}

/// 斜杠面板：21 条命令（基础/媒体两组）+ 链接表单态。定位用
/// 桥传来的光标矩形（fixed），靠下时上翻避免溢出屏幕。
#[component]
pub(super) fn SlashPanel(
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
                role: "dialog",
                "aria-label": "{crate::i18n::t(\"slash.link_dialog_label\")}",
                "aria-orientation": "vertical",
                div { class: "slash-link-form",
                    div { class: "slash-link-title", "{crate::i18n::t(\"slash.link_form_title\")}" }
                    input {
                        class: "slash-link-input",
                        id: "mynote-slash-link-url",
                        r#type: "url",
                        inputmode: "url",
                        autocomplete: "url",
                        required: true,
                        placeholder: "https://example.com",
                        value: "{url}",
                        "aria-invalid": if *err.read() { "true" } else { "false" },
                        "aria-describedby": if *err.read() { Some("mynote-slash-link-error") } else { None },
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
                        // D-10：焦点在输入框时桥面板 keydown 不
                        // 接管（其 editableOf 门），Enter/Esc 在
                        // 此承接（原版 form onSubmit + input
                        // onKeyDown Esc）：Enter 走与提交按钮同
                        // 一校验路径、Esc 取消回命令列表。
                        onkeydown: {
                            let bid = bid.clone();
                            move |e: Event<KeyboardData>| {
                                if e.key() == Key::Enter {
                                    submit_slash_link(url, err, link_click, &bid);
                                } else if e.key() == Key::Escape {
                                    link_for.set(None);
                                }
                            }
                        },
                    }
                    if *err.read() {
                        div {
                            class: "slash-link-error",
                            id: "mynote-slash-link-error",
                            role: "alert",
                            "{crate::i18n::t(\"slash.link_invalid\")}"
                        }
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
                                move |_| submit_slash_link(url, err, link_click, &bid)
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
        /// 命令行序号（D-6：行 id mynote-slash-option-{cidx}
        /// 与面板 aria-activedescendant 的指向，原版口径）
        cidx: usize,
        /// 行 aria-label（标题，副标题，快捷键 X；原版口径）
        aria: String,
    }
    fn slash_row_aria(c: &SlashCmd) -> String {
        let mut parts = vec![crate::i18n::t(c.title), crate::i18n::t(c.sub)];
        if !c.shortcut.is_empty() {
            parts.push(format!(
                "{} {}",
                crate::i18n::t("slash.shortcut_hint"),
                c.shortcut
            ));
        }
        parts.join("，")
    }
    let mut rows: Vec<SRow> = Vec::new();
    let mut next_cidx = 0usize;
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
            rows.push(SRow { head: None, cmd: Some(c), sel: i == 0, recent: false, cidx: next_cidx, aria: slash_row_aria(c) });
            next_cidx += 1;
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
                cidx: 0,
                aria: String::new(),
            });
            for c in &recent_cmds {
                rows.push(SRow { head: None, cmd: Some(c), sel: first, recent: true, cidx: next_cidx, aria: slash_row_aria(c) });
                next_cidx += 1;
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
                cidx: 0,
                aria: String::new(),
            });
            for c in items {
                rows.push(SRow { head: None, cmd: Some(c), sel: first, recent: false, cidx: next_cidx, aria: slash_row_aria(c) });
                next_cidx += 1;
                first = false;
            }
        }
    }
    let any = rows.iter().any(|r| r.cmd.is_some());
    rsx! {
        div { id: "slash-panel", class: "slash-panel", style: "{style}",
            role: "listbox",
            "aria-label": "{crate::i18n::t(\"slash.panel_label\")}",
            "aria-orientation": "vertical",
            "aria-activedescendant": any.then(|| "mynote-slash-option-0".to_string()),
            for row in rows {
                if let Some(label) = row.head {
                    div { class: "slash-section-heading", "{label}" }
                }
                if let Some(c) = row.cmd {
                    button {
                        class: if row.sel { "slash-row sel" } else { "slash-row" },
                        id: "mynote-slash-option-{row.cidx}",
                        role: "option",
                        "data-act": "{c.act}",
                        "aria-selected": if row.sel { "true" } else { "false" },
                        "aria-label": "{row.aria}",
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
