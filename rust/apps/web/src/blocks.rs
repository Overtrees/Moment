//! 块渲染（只读路径与编辑器共用）：DOM 结构与类名对原版
//! editor.css / editor-shell.css 的阅读态规则——段落/标题/引用/
//! 待办（圆形勾选）/Callout 变体/链接卡 lkc/图文卡/附件文件卡等。

use dioxus::prelude::*;
use moment_core::{safe_http_url, safe_image_url, split_highlight, Node};

/// md 解析类型（实现在 core::md，2026-11-26 下沉）：视图层
/// 与编辑器沿用同一批类型，MdKind 经此再导出保持
/// crate::blocks::MdKind 调用路径不变。
pub use moment_core::md::{InlineSeg, MdBlock, MdKind};

use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

use crate::idb;
use crate::persist;

/// 图片查看页请求：src 为已就绪的显示 URL（附件图为
/// blob URL），file_id 为附件 id（图片页标题按附件清
/// 单查真实文件名用；无附件来源时为 None、标题走兜
/// 底文案）。
#[derive(Clone, PartialEq)]
pub struct ImgView {
    pub src: String,
    pub file_id: Option<String>,
}

/// 图片页上下文：图片点击 → 打开 App 层图片页（与列
/// 表/编辑/设置同级的独立页面，见 main.rs ImagePage；
/// App 根提供、编辑器内图片点击写入）。
#[derive(Clone, Copy)]
pub struct ImgPage(pub Signal<Option<ImgView>>);

/// 图文面板上下文：图文卡/图文混排的文本点击 → 打开完整文本面板。
#[derive(Clone, Copy)]
pub struct TextSheet(pub Signal<Option<(String, String)>>);

/// md 源段落编辑态：值为正在编辑源码的块 id（原版点预览回
/// 源码段落编辑、失焦回预览的模型）。编辑器根提供。
#[derive(Clone, Copy)]
pub struct MdEdit(pub Signal<Option<String>>);

/// 当前正被聚焦编辑的块 id（桥 focusin/focusout 维护）。原版口径：
/// 段落转 md 预览只发生在失焦时（use-editor-dom 的 blur 路径）与
/// 初次加载；编辑中的段落即使文本变得像 Markdown 也必须保持
/// 可编辑形态，否则模型同步触发的重渲染会把编辑区换成预览、
/// 焦点当场丢失（2026-11-21 高亮冒烟实测根因）。
#[derive(Clone, Copy)]
pub struct ActiveEdit(pub Signal<Option<String>>);

/// 卡片重试上下文：音乐卡 error 态的「重试」按钮 → 编辑器根
/// 收到块 id 后走 loading → 拉取元数据 → ready/error（原版
/// retryMusicCard）。编辑器根提供。
#[derive(Clone, Copy)]
pub struct CardRetry(pub Signal<Option<String>>);

/// 原子块选中态：原版是单一 contenteditable，点原子块只有原生
/// 选区；本应用是分块架构，选中态承载原版的边缘点击语义与块
/// 操作入口（删除/换图/设链接只在选中后出现，不常驻）。编辑
/// 器根提供。
#[derive(Clone, Copy)]
pub struct SelBlock(pub Signal<Option<String>>);

/// 卡片编辑态（卡片交互专项）：值为处于编辑态的卡片块 id
/// （全局同时仅一张）。未入编辑态时，复合卡的内部图片区/
/// 文本区点按被桥的门禁拦住（不换图、不开文本面板）；经
/// 浮层菜单点「编辑」入态后，点图片区直调系统选图、点文
/// 本区走该卡既有文本编辑通路。编辑器根提供。
#[derive(Clone, Copy)]
pub struct CardEdit(pub Signal<Option<String>>);

/// 卡片浮层菜单状态（卡片交互专项）：长按拾起、桌面右键
/// 两路同开一个菜单（编辑 + 删除）。anchor_point 为 Some
/// 时按点锚定位（桌面右键），None 时按卡锚（长按，rect
/// 为卡片矩形 left/top/width/height）。编辑器根提供。
#[derive(Clone, PartialEq)]
pub struct CardMenuState {
    pub bid: String,
    pub wtype: String,
    pub anchor_point: Option<(f64, f64)>,
    pub rect: (f64, f64, f64, f64),
}

/// Wiki 导航上下文：md 预览里的 wiki 链接点击 → 编辑器根收到
/// target 原文后先落盘当前编辑、再调 on_open_wiki 导航（原版
/// 「双链优先导航」：此路径优先于点预览回源码编辑）。编辑器
/// 根提供。
#[derive(Clone, Copy)]
pub struct WikiNav(pub Signal<Option<String>>);

/// 附件清单上下文：附件块的文件名按原版 renderAtomicHTML
/// 口径查 manifest 的 files 表——节点本身不带 name（真实备
/// 份与 allblocks 语料实证：name 只在 manifest.attachments
/// 里），旧渲染只读节点 name 导致文件名永远落兜底文案（审
/// 计 E2）。编辑器根提供（manifest 信号与导出路径同源）。
#[derive(Clone, Copy)]
pub struct Manifest(pub Signal<String>);

/// encodeURIComponent 等价的百分号编码（实现在 core::md，
/// 与 md 解析共用一份，此处再导出保持既有调用路径）。
pub use moment_core::md::url_encode;

/// 封面代理（原版 proxyImg）：QQ 音乐封面升分辨率后一律走
/// Worker /img 代理。
pub fn proxy_img(url: &str) -> String {
    if url.is_empty() {
        return String::new();
    }
    let mut u = url.to_string();
    if u.contains("y.gtimg.cn/music/photo_new/T002R") {
        // 原版正则 /T002R\d+x\d+/ → T002R800x800：只替换尺寸段
        // （数字 x 数字）。尺寸之后紧跟专辑 ID（如 M000...，与尺寸
        // 同为字母数字），若按「首个非字母数字处截断」会把 ID 一并
        // 吞掉，拼出的 URL 在 CDN 上 404（实测）——必须逐位按
        // \d+x\d+ 扫描，与原版正则严格等价，不匹配时原样保留。
        if let Some(pos) = u.find("T002R") {
            let rest = &u[pos + 5..];
            let b = rest.as_bytes();
            let mut i = 0;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            if i > 0 && i < b.len() && b[i] == b'x' {
                let mut j = i + 1;
                while j < b.len() && b[j].is_ascii_digit() {
                    j += 1;
                }
                if j > i + 1 {
                    u = format!("{}T002R800x800{}", &u[..pos], &rest[j..]);
                }
            }
        }
    }
    if u.contains("mzstatic.com") {
        // Apple 封面 wp 变体归一（原版 proxyImg 无此处理、与
        // 原版同病）：Worker /meta 给 Apple Music 的 cover 是
        // 1200x630wp-60.jpg——苹果把方形封面垫进 1200×630 的
        // 近白画布（实测底色 248,248,248、封面本体只占中间
        // 约 36% 宽、自带圆角阴影），成品卡 object-fit:cover
        // 铺满容器也救不回：两侧「留白」是图片内容本身、与
        // 容器底色无关（深色下尤显）。归一到同图方形 bb 变体
        // 600x600bb，与 QQ 封面同层处置：只换 URL 末段尺寸段
        // （<digits>x<digits>wp[-<digits>].<ext>），逐位扫描、
        // 不匹配原样保留；查询串不参与匹配、原样带回。
        let (path, query) = match u.find(['?', '#']) {
            Some(p) => (&u[..p], &u[p..]),
            None => (&u[..], ""),
        };
        if let Some(slash) = path.rfind('/') {
            let seg = &path[slash + 1..];
            if let Some(dot) = seg.rfind('.') {
                let (stem, ext) = (&seg[..dot], &seg[dot + 1..]);
                let b = stem.as_bytes();
                let mut i = 0;
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
                let mut ok = i > 0 && i < b.len() && b[i] == b'x';
                let mut j = i + 1;
                if ok {
                    while j < b.len() && b[j].is_ascii_digit() {
                        j += 1;
                    }
                    ok = j > i + 1 && stem[j..].starts_with("wp");
                }
                if ok {
                    let tail = &stem[j + 2..];
                    let tail_ok = tail.is_empty()
                        || (tail.len() > 1
                            && tail.starts_with('-')
                            && tail[1..].bytes().all(|c| c.is_ascii_digit()));
                    let ext_ok = !ext.is_empty()
                        && ext.len() <= 5
                        && ext.bytes().all(|c| c.is_ascii_alphanumeric());
                    if tail_ok && ext_ok {
                        u = format!("{}600x600bb.{}{}", &path[..=slash], ext, query);
                    }
                }
            }
        }
    }
    format!(
        "https://mynote.overtrees.workers.dev/img?url={}",
        url_encode(&u)
    )
}

/// 卡片来源图标（原版 getTypeIcon）：返回图标集名（icons::paths），
/// 渲染点以 svg_markup 注入 SVG（图标集统一批，弃 emoji 字面）。
pub fn type_icon(meta_type: Option<&str>) -> &'static str {
    match meta_type {
        Some("music") => "music",
        Some("video") => "video",
        _ => "link",
    }
}

/// URL 主机名（原版 new URL().hostname 并去掉 www. 前缀；
/// 解析失败返回空串，调用方回退到完整 URL）。无 http(s)
/// scheme 时 new URL() 抛错——C-11：此前把无 scheme 串的
/// 首段当主机名返回，err 卡标题与原版（回退完整 URL）分叉。
pub fn host_of(url: &str) -> String {
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"));
    let Some(rest) = rest else {
        return String::new();
    };
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = host.rsplit('@').next().unwrap_or(host);
    let host = host.split(':').next().unwrap_or(host);
    host.strip_prefix("www.").unwrap_or(host).to_string()
}

/// 字段位置（use-slash.js 节点工厂实证）：heading 的 level、
/// todo 的 checked、gallery 的 items 都在 attrs 里，不在顶层。
/// 读取只认类型化 attrs（去兼容第四步收紧位置、§2.2 收紧
/// 模型，refactor_remove_compat §2.3）：顶层旧形与类型不合
/// 值只在迁移通道（core::migrate）归一，主线不再兜底双读。

/// 结构化 numbered-list 的起始编号（attrs.start，E-17 ①；
/// 与 editor::list_start 同口径，渲染侧只读）：缺失/非法
/// （<1）按 1。
fn list_start(node: &Node) -> u64 {
    if node.block_type() != Some("numbered-list") {
        return 1;
    }
    node.attrs.start.filter(|&s| s >= 1).unwrap_or(1)
}

pub fn heading_level(node: &Node) -> i64 {
    // C-03：原版 editor.render.js 口径——level = attrs.level
    // || 2，无上限钳制（存量可出 h5/h6）；缺省与非法值（<1）
    // 回退 2。此前默认 1 且 clamp(1,4)，无 level 备忘渲染成
    // h1 级、h5/h6 被钳到 4。
    let lv = node.attrs.level.unwrap_or(2);
    if lv < 1 {
        2
    } else {
        lv
    }
}

pub fn todo_checked(node: &Node) -> bool {
    node.attrs.checked.unwrap_or(false)
}

/// 图库条目（C-08）：只认归一形态——attrs.items 数组内的
/// {fileId} / {url} 对象（原版解析序 fileId 优先，editor.
/// render.js 图库分支与 export.js galleryItems 一致）。裸
/// 字符串条目与 children 兜底形已收紧删除（去兼容第四步，
/// refactor_remove_compat §2.5）：旧形只在迁移通道
/// （core::migrate）归一为对象形/物化进 attrs.items，主线
/// 不再认。本函数是渲染/导出共用的唯一实现。
#[derive(Clone, Debug, PartialEq)]
pub enum GalleryItem {
    File(String),
    Url(String),
}

pub fn gallery_items(node: &Node) -> Vec<GalleryItem> {
    match &node.attrs.items {
        Some(items) => items.iter().filter_map(gallery_item_of).collect(),
        None => Vec::new(),
    }
}

fn gallery_item_of(e: &moment_core::GalleryEntry) -> Option<GalleryItem> {
    if let Some(fid) = e.file_id.as_deref().filter(|s| !s.is_empty()) {
        return Some(GalleryItem::File(fid.to_string()));
    }
    e.url
        .as_deref()
        .filter(|s| !s.is_empty())
        .map(|u| GalleryItem::Url(u.to_string()))
}

/// 媒体直链（video 的 url 形态）白名单：只许 http(s)。
/// 原版无 url 形 video 块，此为本应用扩展形态，按
/// safeHttpUrl 口径收紧（C-30）。
fn safe_media_url(value: &str) -> String {
    let url = value.trim();
    let lower = url.to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        url.to_string()
    } else {
        String::new()
    }
}

/// 块上的附件 id（全应用唯一实现，渲染/导出/设置三方共用）：
/// 只认 attrs.fileId，空串视为无（去兼容第四步收紧，
/// refactor_remove_compat §2.4）。顶层 fileId 旧形只在迁移
/// 通道（core::migrate）归一搬入 attrs，主线不再双读。
pub fn file_id(node: &Node) -> Option<String> {
    // 空字符串视为无 id：原版斜杠命令插入的占位块带
    // attrs {fileId:""}，须走 .atomic-placeholder 占位形态
    // 而非 BlobMedia 空 id 分支（主线口径修正 2026-11-21）。
    node.attrs
        .file_id
        .as_deref()
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
}

/// 行内高亮切分与 core 共用一份（split_highlight）：高亮以字面
/// == 存在文本里，渲染时成 mark。

/// 行内节点渲染：语义标签（strong/em/u/s/code/a）+ 高亮 mark。
#[component]
pub fn Inlines(nodes: Vec<Node>) -> Element {
    rsx! {
        for (i, node) in nodes.iter().enumerate() {
            InlineNode { node: node.clone(), key: "{i}" }
        }
    }
}

#[component]
fn InlineNode(node: Node) -> Element {
    if node.node_type.as_deref() == Some("link") {
        let url = node.url.as_deref().unwrap_or("").to_string();
        let kids = node.children.clone().unwrap_or_default();
        // C-30：href 过协议白名单；被拦只渲染子内容不出锚
        // （与原版 DOMPurify 剥 href 留文本等价）
        let safe = safe_http_url(&url);
        if safe.is_empty() {
            return rsx! { Inlines { nodes: kids } };
        }
        return rsx! {
            a { href: "{safe}", target: "_blank", rel: "noreferrer",
                Inlines { nodes: kids }
            }
        };
    }
    let text = node.text.clone().unwrap_or_default();
    let b = node.bold.unwrap_or(false);
    let i = node.italic.unwrap_or(false);
    let u = node.underline.unwrap_or(false);
    let s = node.strikethrough.unwrap_or(false);
    let code = node.code.unwrap_or(false);
    rsx! {
        for (idx, (hi, seg)) in split_highlight(&text).into_iter().enumerate() {
            {
                let inner = rsx! { "{seg}" };
                let inner = if code { rsx! { code { {inner} } } } else { inner };
                let inner = if s { rsx! { s { {inner} } } } else { inner };
                let inner = if u { rsx! { u { {inner} } } } else { inner };
                let inner = if i { rsx! { em { {inner} } } } else { inner };
                let inner = if b { rsx! { strong { {inner} } } } else { inner };
                rsx! {
                    if hi {
                        mark { class: "moment-highlight", key: "h{idx}", {inner} }
                    } else {
                        span { key: "t{idx}", {inner} }
                    }
                }
            }
        }
    }
}

fn kids_of(node: &Node) -> Vec<Node> {
    node.children.clone().unwrap_or_default()
}

/// 附件媒体：从 IndexedDB 取字节生成 Blob URL 后渲染图片，
/// 点击打开图片页（原版图片点击行为）。图片在建 URL 前
/// 先经 imgsize 解析自然尺寸（D-22 续项共用机制）：尺寸
/// 与 URL 同次落定，img 首帧即带预留几何（rsv 为该呈现
/// 上下文的预留型），lazy 才真正生效；解析结果按 fid
/// 回填缓存，下次进入时占位态（无 src 的同元素 img 盒）
/// 即有预留。
#[component]
pub fn BlobMedia(
    file_id: String,
    gen: Signal<u32>,
    kind: String,
    alt: String,
    rsv: crate::imgsize::Reserve,
) -> Element {
    let mut media = use_signal(|| Option::<(String, Option<(u32, u32)>)>::None);
    let fid = file_id.clone();
    let is_image = kind == "image";
    use_effect(move || {
        let fid = fid.clone();
        spawn(async move {
            if let Some(bytes) = persist::get_attachment(&fid).await {
                let size = if is_image {
                    let sz = crate::imgsize::parse_image_size(&bytes);
                    if let Some((w, h)) = sz {
                        crate::imgsize::record_fid_size(&fid, w, h);
                        crate::imgsize::note_parsed(&fid, w, h);
                    }
                    sz
                } else {
                    None
                };
                media.set(idb::blob_url(&bytes).map(|u| (u, size)));
            } else {
                crate::diag::log_once(
                    &format!("att-missing-{fid}"),
                    "ATT",
                    &format!("attachment {fid} not in IDB"),
                );
            }
        });
    });
    let _ = gen.read();
    let img_page = try_use_context::<ImgPage>();
    let media_state = media.read().clone();
    match media_state.as_ref() {
        Some((u, size)) => {
            let u = u.clone();
            let size = *size;
            if kind == "video" {
                rsx! { video { class: "blk-media", controls: true, src: "{u}" } }
            } else if kind == "audio" {
                rsx! { audio { class: "blk-media", controls: true, src: "{u}" } }
            } else {
                let u2 = u.clone();
                let fid2 = file_id.clone();
                rsx! {
                    img {
                        class: "blk-media img-rsv",
                        src: "{u}",
                        style: "{crate::imgsize::reserve_style(rsv, size)}",
                        // D-22（批 11 量测后落）：长文档屏外
                        // 图不再开页即解码——lazy 推迟到近视口
                        // 才解码、async 解码不占主线程；只动
                        // 加载属性、呈现口径不变。量测：20 图
                        // 长备忘改前开页解码 20/20。预留几何
                        // （D-22 续项）是其生效前置：无预留时
                        // 全图同帧挤在阈值内、属性被击穿。
                        loading: "lazy",
                        decoding: "async",
                        // C-10：附件图 alt = manifest 文件名
                        // （原版 alt=f.name）；其余图传空串
                        alt: "{alt}",
                        onclick: move |_| {
                            if let Some(ip) = img_page {
                                let mut s = ip.0;
                                s.set(Some(ImgView {
                                    src: u2.clone(),
                                    file_id: Some(fid2.clone()),
                                }));
                            }
                        },
                    }
                }
            }
        }
        None => {
            if is_image {
                match crate::imgsize::size_for_fid(&file_id) {
                    // 占位态（缓存已有尺寸）：与载入后同一
                    // img 元素、同样式（.img-rsv + 上下文
                    // 规则 + 预留几何），字节到达只是赋
                    // src——除图片出现外无样式跳变。
                    Some(sz) => rsx! {
                        img {
                            class: "blk-media img-rsv",
                            style: "{crate::imgsize::reserve_style(rsv, Some(sz))}",
                            alt: "",
                        }
                    },
                    None => rsx! { div { class: "atomic-placeholder", "{crate::i18n::t(\"media.loading\")}" } },
                }
            } else {
                rsx! { div { class: "atomic-placeholder", "{crate::i18n::t(\"media.loading\")}" } }
            }
        }
    }
}

fn callout_variant(node: &Node) -> &'static str {
    let raw = node
        .callout_type
        .as_deref()
        .unwrap_or("note")
        .to_lowercase();
    match raw.as_str() {
        "warning" => "warning",
        "tip" => "tip",
        "important" => "important",
        "caution" => "caution",
        _ => "note",
    }
}

fn img_text_of(node: &Node) -> String {
    // 旧读链首项 extra["text"] 在模型字段化后恒与 Node.text
    // 同体（JSON 的 text 键只入字段），plain_text 已含之：
    // caption 优先、否则全文纯文本（§2.2 类型化收口）。
    node.caption
        .clone()
        .unwrap_or_else(|| node.plain_text())
}

/// 附件文件名查 manifest（原版 renderAtomicHTML 的 files
/// 表口径，与导出路径 editor.rs 的 files 优先、节点 name
/// 兜底同序）。清单上下文缺失或条目不存在时返回 None。
fn manifest_att_name(ctx: Option<&Manifest>, fid: &str) -> Option<String> {
    let raw = ctx?.0.read().clone();
    att_name_in_manifest(&raw, fid)
}

/// 附件文件名查清单原文（manifest JSON 串）：与
/// manifest_att_name 同口径，供无 Manifest 上下文处
/// （App 层图片页标题）复用。
pub(crate) fn att_name_in_manifest(raw: &str, fid: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    v.get("attachments")?
        .get(fid)?
        .get("name")?
        .as_str()
        .map(|s| s.to_string())
}

/// 附件 MIME 查清单原文（manifest 条目 {name, type}，
/// type 为写入时的文件 MIME）。
pub(crate) fn att_type_in_manifest(raw: &str, fid: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    v.get("attachments")?
        .get(fid)?
        .get("type")?
        .as_str()
        .map(|s| s.to_string())
}

/// 文件行附件是否为图片类文件（图片页扩围判据，2026-
/// 11-24）：manifest type 非空时以其为准（image/*）；
/// type 缺失时按文件名扩展名兜底。
fn att_file_is_image(ctx: Option<&Manifest>, fid: &str, name: &str) -> bool {
    let raw = ctx.map(|c| c.0.read().clone()).unwrap_or_default();
    att_file_is_image_raw(&raw, fid, name)
}

/// 同上判据的清单原文入口（列表封面派生复用，单一实现）：
/// manifest 原文 + fid + 文件名 → 是否图片类文件。
pub(crate) fn att_file_is_image_raw(raw: &str, fid: &str, name: &str) -> bool {
    if let Some(t) = att_type_in_manifest(raw, fid) {
        if !t.trim().is_empty() {
            return t.trim().to_ascii_lowercase().starts_with("image/");
        }
    }
    let ext = name
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    matches!(
        ext.as_str(),
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp" | "svg" | "avif" | "heic" | "heif"
    )
}

fn manifest_att_type(ctx: Option<&Manifest>, fid: &str) -> Option<String> {
    let raw = ctx?.0.read().clone();
    att_type_in_manifest(&raw, fid)
}

/// 附件字节 → web_sys::File（原版 dataURLtoBlob + new
/// File 的等价构造）。mime 空时不设 type，File.type 为空
/// 串、canShare 与分享目标按文件名扩展兜底（原版 fi.type
/// 缺省走 application/octet-stream 的终态等价）。
fn make_js_file(bytes: &[u8], name: &str, mime: &str) -> Option<web_sys::File> {
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::FilePropertyBag::new();
    if !mime.is_empty() {
        opts.set_type(mime);
    }
    web_sys::File::new_with_u8_array_sequence_and_options(&parts, name, &opts).ok()
}

/// JS 异常的 name 字段（share 拒绝分级：AbortError = 用
/// 户取消、NotAllowedError = 激活失效/未授权，其余原名记
/// 录）。
fn js_error_name(e: &wasm_bindgen::JsValue) -> String {
    js_sys::Reflect::get(e, &wasm_bindgen::JsValue::from_str("name"))
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_else(|| "Error".to_string())
}

/// 下载兜底（原版 att-hint 分支的 else 路径）：File →
/// 对象 URL → a[download] 程序化点击 → 即刻 revoke（与
/// 原版及 backup.rs download_zip 同形态）。
fn download_js_file(f: &web_sys::File, name: &str) {
    let Some(window) = web_sys::window() else { return };
    let Some(doc) = window.document() else { return };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(f.unchecked_ref()) else { return };
    if let Ok(el) = doc.create_element("a") {
        let a: web_sys::HtmlAnchorElement = el.unchecked_into();
        a.set_href(&url);
        a.set_download(name);
        a.click();
    }
    let _ = web_sys::Url::revoke_object_url(&url);
}

/// 附件打开·分享路（在行 onclick 调用栈内同步执行）：
/// API 在场且 canShare({files}) 通过 → navigator.share
/// ({files, title=文件名})，Promise 结局异步回记 Diag 结
/// 果行（shared / cancelled / error <name>）；API 缺失或
/// canShare 不过 → 同步降级下载并回记。share 与下载的发
/// 起都不跨 await，手势激活有效（与原版 att-hint 同步链
/// 同构）。
fn open_js_file(f: &web_sys::File, name: &str, fid: &str) {
    let meta = format!("{name} {} {}B", f.type_(), f.size() as u64);
    let Some(window) = web_sys::window() else {
        crate::diag::log("ATT", &format!("open {fid} {meta} -> no-window"));
        return;
    };
    let nav = window.navigator();
    let nav_js: wasm_bindgen::JsValue = nav.clone().into();
    let has_fn = |key: &str| {
        js_sys::Reflect::get(&nav_js, &wasm_bindgen::JsValue::from_str(key))
            .map(|v| v.is_function())
            .unwrap_or(false)
    };
    if has_fn("share") && has_fn("canShare") {
        let data = web_sys::ShareData::new();
        let files = js_sys::Array::new();
        files.push(f);
        data.set_files(&wasm_bindgen::JsValue::from(files));
        data.set_title(name);
        if nav.can_share_with_data(&data) {
            let promise = nav.share_with_data(&data);
            let fid = fid.to_string();
            spawn(async move {
                match JsFuture::from(promise).await {
                    Ok(_) => crate::diag::log("ATT", &format!("open {fid} {meta} -> shared")),
                    Err(e) => {
                        let en = js_error_name(&e);
                        if en == "AbortError" {
                            crate::diag::log("ATT", &format!("open {fid} {meta} -> cancelled"));
                        } else {
                            crate::diag::log("ATT", &format!("open {fid} {meta} -> error {en}"));
                        }
                    }
                }
            });
            return;
        }
    }
    download_js_file(f, name);
    crate::diag::log("ATT", &format!("open {fid} {meta} -> download"));
}

/// 附件文件行（非图片附件块与音乐文件行共用）：文件名 +
/// 打开 pill，整行点按分发——
/// · 图片类文件（img_file，att_file_is_image 判定）走图
///   片页（2026-11-24 扩围口径，代码自原行内实现平移：
///   IDB 取字节 → blob URL → ImgView，标题由图片页按
///   file_id 查清单文件名）；
/// · 其余文件走原版 att-hint 的分享链：原版在开篇时把全
///   部附件预加载进内存 files 表、点击时同步取数构造
///   File 并在手势内调 share——本组件以渲染期预取等价
///   实现：挂载即从 IDB 取字节构造 web_sys::File 存信
///   号（与 BlobMedia 的渲染期取数同型），onclick 在手
///   势内同步走 open_js_file。预取未就绪时点击走异步取
///   字节 + 下载兜底（下载不依赖手势激活），结局回记
///   Diag；预取已定无文件记 missing，不静默。
/// 旧实现（点击后 spawn 读 IDB → window.open blob URL）
/// 发起点在 await 之后、手势激活已失效，Safari 静默拦
/// 截且返回值被丢弃、无兜底无结果留痕，非图片路已整段
/// 替换；图片路保留同型 spawn（导航不依赖手势激活）。
#[component]
pub fn AttachmentFileRow(
    file_id: String,
    name: String,
    mime: String,
    icon: String,
    hint: String,
    name_fallback: String,
    img_file: bool,
) -> Element {
    let img_page = try_use_context::<ImgPage>();
    let mut file = use_signal(|| Option::<web_sys::File>::None);
    let mut settled = use_signal(|| false);
    {
        let fid = file_id.clone();
        let share_name = if name.is_empty() {
            "文件".to_string()
        } else {
            name.clone()
        };
        let mime_c = mime.clone();
        use_effect(move || {
            if img_file {
                settled.set(true);
                return;
            }
            let fid = fid.clone();
            let share_name = share_name.clone();
            let mime_c = mime_c.clone();
            spawn(async move {
                match crate::persist::get_attachment(&fid).await {
                    Some(bytes) => match make_js_file(&bytes, &share_name, &mime_c) {
                        Some(f) => file.set(Some(f)),
                        None => {
                            crate::diag::log("ATT", &format!("prefetch {fid} -> file-error"));
                        }
                    },
                    None => crate::diag::log("ATT", &format!("prefetch {fid} -> miss")),
                }
                settled.set(true);
            });
        });
    }
    let shown_name = if name.is_empty() {
        name_fallback
    } else {
        name.clone()
    };
    // icon 入参为图标集名（icons::paths），渲染为 SVG（弃 emoji）。
    let icon_markup = crate::icons::svg_markup(&icon, 30, "2.5", "currentColor");
    let share_name = if name.is_empty() {
        "文件".to_string()
    } else {
        name.clone()
    };
    let fid_click = file_id.clone();
    let mime_click = mime.clone();
    rsx! {
        div { class: "attachment-file",
            onclick: move |_| {
                let fid = fid_click.clone();
                if img_file {
                    if let Some(p) = img_page {
                        spawn(async move {
                            if let Some(bytes) = crate::persist::get_attachment(&fid).await {
                                if let Some(u) = crate::idb::blob_url(&bytes) {
                                    let mut s = p.0;
                                    s.set(Some(ImgView { src: u, file_id: Some(fid.clone()) }));
                                }
                            }
                            crate::diag::log("ATT", &format!("open attachment image {fid}"));
                        });
                    }
                    return;
                }
                let share_name = share_name.clone();
                if let Some(f) = file.read().clone() {
                    open_js_file(&f, &share_name, &fid);
                } else if *settled.read() {
                    crate::diag::log_warn("ATT", &format!("open {fid} -> missing"));
                } else {
                    let mime_c = mime_click.clone();
                    spawn(async move {
                        match crate::persist::get_attachment(&fid).await {
                            Some(bytes) => {
                                match make_js_file(&bytes, &share_name, &mime_c) {
                                    Some(f) => {
                                        let meta = format!(
                                            "{} {} {}B",
                                            share_name,
                                            f.type_(),
                                            f.size() as u64
                                        );
                                        download_js_file(&f, &share_name);
                                        crate::diag::log(
                                            "ATT",
                                            &format!("open {fid} {meta} -> download (prefetch pending)"),
                                        );
                                    }
                                    None => crate::diag::log(
                                        "ATT",
                                        &format!("open {fid} -> file-error"),
                                    ),
                                }
                            }
                            None => {
                                crate::diag::log_warn("ATT", &format!("open {fid} -> missing"));
                            }
                        }
                    });
                }
            },
            span { class: "att-icon", dangerous_inner_html: "{icon_markup}" }
            span { class: "att-name", "{shown_name}" }
            span { class: "att-hint", "{hint}" }
        }
    }
}

/// 单块只读渲染（编辑器的非文本块与预览共用）。
#[component]
pub fn BlockView(node: Node, gen: Signal<u32>) -> Element {
    let ty = node.node_type.clone().unwrap_or_else(|| "paragraph".to_string());
    let kids = kids_of(&node);
    let att_manifest = try_use_context::<Manifest>();
    // 图片页入口信号（BlobMedia 自取之外，URL 图与附件
    // 文件行两处新入口在此取用，2026-11-24 扩围）。
    let img_page = try_use_context::<ImgPage>();
    // 卡片占位文案状态感知：非编辑态点图区不再直接加图
    // （编辑态门禁，卡片交互专项），占位文案须引导长按
    // 菜单→编辑的路径；本卡处于编辑态时点按确实加图、
    // 文案回到「点击添加图片」。CardEdit 由编辑器根提
    // 供（editor.rs）；读信号订阅本组件、入/出编辑态即
    // 重渲切换文案。无上下文（非编辑器复用）时按非编辑
    // 态处理。
    let card_editing = try_use_context::<CardEdit>()
        .map(|ce| {
            let cur = (*ce.0.read()).clone();
            cur.is_some() && cur == node.id
        })
        .unwrap_or(false);
    let add_image_key = if card_editing {
        "media.add_image"
    } else {
        "media.add_image_hint"
    };
    let gallery_add_key = if card_editing {
        "media.gallery_add"
    } else {
        "media.gallery_add_hint"
    };
    match ty.as_str() {
        "paragraph" => {
            // md 源段落（代码/列表/Callout）走预览渲染，与原版一致
            let plain = node.plain_text();
            if md_classify(&plain).is_some() {
                rsx! { MdPreview { text: plain } }
            } else if kids.iter().all(|k| {
                matches!(k.node_type.as_deref(), Some("text") | None)
                    && k.plain_text().trim().is_empty()
            }) {
                // C-02：空段补 <br> 保高（原版空段渲染
                // <div><br></div>，空 div 高度塌陷为 0）
                rsx! { div { class: "blk-p", br {} } }
            } else {
                rsx! { div { class: "blk-p", Inlines { nodes: kids } } }
            }
        }
        "heading" => {
            let lv = heading_level(&node);
            let cls = format!("blk-h{lv}");
            rsx! { div { class: "{cls}", Inlines { nodes: kids } } }
        }
        // C-04：结构对齐原版 blockquote > div（CSS 命中归批 8）
        "quote" => rsx! {
            blockquote { class: "blk-quote",
                div { Inlines { nodes: kids } }
            }
        },
        "todo" => {
            let checked = todo_checked(&node);
            let label = node.plain_text();
            rsx! {
                div { class: if checked { "todo-row done" } else { "todo-row" },
                    // C-05：原版为真 checkbox input 带
                    // aria-checked 与 aria-label=待办文本
                    span {
                        class: if checked { "todo-checkbox on" } else { "todo-checkbox" },
                        role: "checkbox",
                        "aria-checked": "{checked}",
                        "aria-label": "{label}",
                    }
                    div { class: "todo-text", Inlines { nodes: kids } }
                }
            }
        }
        "divider" => rsx! { hr { class: "blk-hr" } },
        "callout" => {
            let variant = callout_variant(&node);
            let title_key = match variant {
                "warning" => "callout.warning",
                "tip" => "callout.tip",
                "important" => "callout.important",
                "caution" => "callout.caution",
                _ => "callout.note",
            };
            // 图标与 MD Callout 共用 icons::callout_icon_markup
            // 单一出处（C-17/D-23 统一，独立块弃 emoji）。
            let icon = crate::icons::callout_icon_markup(variant);
            rsx! {
                div { class: "callout callout-{variant}",
                    div { class: "callout-header",
                        span { class: "callout-icon", dangerous_inner_html: "{icon}" }
                        span { class: "callout-title", "{crate::i18n::t(title_key)}" }
                    }
                    div { class: "callout-body", Inlines { nodes: kids } }
                }
            }
        }
        "codeBlock" => {
            let text = node.plain_text();
            rsx! { pre { class: "blk-code", "{text}" } }
        }
        "bulleted-list" | "numbered-list" => {
            let ordered = ty == "numbered-list";
            let start = list_start(&node);
            rsx! {
                div { class: "list-wrap",
                    for (i, item) in kids.iter().enumerate() {
                        div { class: "list-row", key: "{i}",
                            span { class: "list-marker", if ordered { "{start + i as u64}." } else { "•" } }
                            div { style: "flex:1;min-width:0;", Inlines { nodes: kids_of(item) } }
                        }
                    }
                }
            }
        }
        "image" => {
            if let Some(fid) = file_id(&node) {
                rsx! {
                    div { class: "atomic", "data-type": "image",
                        BlobMedia { file_id: fid, gen, kind: "image".to_string(), alt: String::new(), rsv: crate::imgsize::Reserve::Capped }
                    }
                }
            } else if let Some(src) = node
                .url
                .as_deref()
                .map(safe_image_url)
                .filter(|s| !s.is_empty())
            {
                // url 形图片过 safeImageUrl 白名单（C-30），
                // 被拦回落无图占位（原版 imgSrc 为空同口径）。
                // 点按进图片页（2026-11-24 扩围：URL 图与
                // fileId 图同为看图表面、无更高优先级主
                // 动作；无 fileId，页头标题走 i18n 兜底）。
                let src2 = src.clone();
                let ip = img_page.clone();
                // D-22 续项：URL 图走 imgsize 缓存预留
                // （Capped 型，与独立图 CSS 几何同口径）；
                // 尺寸由 track_img_load 在元素载入时回填。
                let rsv_style = crate::imgsize::reserve_style(
                    crate::imgsize::Reserve::Capped,
                    crate::imgsize::size_for_url(&src),
                );
                rsx! {
                    div { class: "atomic", "data-type": "image",
                        img {
                            class: "img-rsv",
                            src: "{src}",
                            style: "{rsv_style}",
                            onmounted: move |evt| crate::imgsize::track_img_load(evt),
                            // D-22：同 BlobMedia 口径懒加载
                            loading: "lazy",
                            decoding: "async",
                            onclick: move |_| {
                                if let Some(p) = &ip {
                                    let mut s = p.0;
                                    s.set(Some(ImgView { src: src2.clone(), file_id: None }));
                                }
                            },
                        }
                    }
                }
            } else {
                // 无图占位（原版 editor.render.js image 分支）：外层
                // 仍是 .atomic[data-type=image]（36px 边距来自它），
                // 内层才是占位盒；文案状态感知（见 BlockView 头
                // 注）：编辑态「点击添加图片」、非编辑态为长按菜
                // 单引导文案。
                rsx! {
                    div { class: "atomic", "data-type": "image",
                        div { class: "atomic-placeholder", "{crate::i18n::t(add_image_key)}" }
                    }
                }
            }
        }
        "gallery" => {
            let items = gallery_items(&node);
            if items.is_empty() {
                // D-17 空态：原版双占位格（左「点击添加」、
                // 右「多张图片」），几何由 .gallery-empty 规则
                // 定（2 列 / 366px / radius 22）
                // 双格带 data-liftsurface 标记：拾起视觉面是
                // 双格整体（并集），非任一单格（桥
                // resolveLiftSurface 标记路）。左格文案状态感
                // 知（见 BlockView 头注），右格为形态描述文案
                // 不分态。
                rsx! {
                    div { class: "atomic", "data-type": "gallery",
                        div { class: "gallery-empty",
                            div { class: "gallery-empty-tile", "data-liftsurface": "",
                                span { class: "gallery-empty-icon", dangerous_inner_html: "{crate::icons::svg_markup(\"image\", 18, \"2.5\", \"currentColor\")}" }
                                span { class: "gallery-empty-label", "{crate::i18n::t(gallery_add_key)}" }
                            }
                            div { class: "gallery-empty-tile alt", "data-liftsurface": "",
                                span { class: "gallery-empty-icon", dangerous_inner_html: "{crate::icons::svg_markup(\"image\", 18, \"2.5\", \"currentColor\")}" }
                                span { class: "gallery-empty-label", "{crate::i18n::t(\"media.gallery_multi\")}" }
                            }
                        }
                    }
                }
            } else {
                rsx! {
                    div { class: "atomic", "data-type": "gallery",
                        // 格网整体即拾起视觉面（标记供桥
                        // resolveLiftSurface 取整体而非单格）
                        div { class: "gallery-grid", "data-liftsurface": "",
                            for (ix, item) in items.iter().enumerate() {
                                match item {
                                    GalleryItem::File(fid) => rsx! {
                                        BlobMedia { file_id: fid.clone(), gen, kind: "image".to_string(), alt: String::new(), key: "g{ix}", rsv: crate::imgsize::Reserve::Fill }
                                    },
                                    GalleryItem::Url(u) => {
                                        // 直链图过 safeImageUrl 白名单
                                        // （C-30）；被拦时 src 为空，与
                                        // 原版 <img src=""> 同形态。
                                        // 点按进图片页（2026-11-24
                                        // 扩围，与 File 项同格网同
                                        // 口径；无 fileId 标题兜底）。
                                        let src = safe_image_url(u);
                                        let src2 = src.clone();
                                        let ip = img_page.clone();
                                        // D-22 续项：同 URL 图口径
                                        // 走 imgsize 缓存（gallery 格
                                        // 高由 CSS 定死、Fill 型只定
                                        // 宽高比、格几何不变）。
                                        let rsv_style = crate::imgsize::reserve_style(
                                            crate::imgsize::Reserve::Fill,
                                            crate::imgsize::size_for_url(&src),
                                        );
                                        rsx! {
                                            img {
                                                class: "img-rsv",
                                                src: "{src}",
                                                key: "g{ix}",
                                                style: "{rsv_style}",
                                                onmounted: move |evt| crate::imgsize::track_img_load(evt),
                                                // D-22：同 BlobMedia 口径懒加载
                                                loading: "lazy",
                                                decoding: "async",
                                                onclick: move |_| {
                                                    if let Some(p) = &ip {
                                                        let mut s = p.0;
                                                        s.set(Some(ImgView { src: src2.clone(), file_id: None }));
                                                    }
                                                },
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
        "video" => {
            if let Some(fid) = file_id(&node) {
                rsx! { div { class: "atomic", "data-type": "video", BlobMedia { file_id: fid, gen, kind: "video".to_string(), alt: String::new(), rsv: crate::imgsize::Reserve::Fill } } }
            } else if let Some(src) = node
                .url
                .as_deref()
                .map(safe_media_url)
                .filter(|s| !s.is_empty())
            {
                rsx! { div { class: "atomic", "data-type": "video", video { controls: true, src: "{src}" } } }
            } else {
                rsx! { div { class: "atomic-placeholder", "{crate::i18n::t(\"media.video_no_src\")}" } }
            }
        }
        "musicCard" => {
            // 状态机逐项对原版 renderAtomicHTMLUnsafe 的 musicCard
            // 分支：input 胶囊 → ready 卡 → loading 骨架（同形：
            // 封面 2.4/1 + 三行骨架，整体脉冲）→ error 卡（音乐图标+链接+
            // 重试）→ 兜底胶囊。带 fileId 的是音频附件走文件行。
            let url = node.url.as_deref().unwrap_or("").to_string();
            let status = node.status.as_deref().unwrap_or("").to_string();
            let meta = node.meta.clone().unwrap_or(serde_json::Value::Null);
            let mtitle = meta.get("title").and_then(|v| v.as_str()).unwrap_or("").to_string();
            if file_id(&node).is_some() {
                let name = file_id(&node)
                    .and_then(|fid| manifest_att_name(att_manifest.as_ref(), &fid))
                    .or_else(|| node.name.clone())
                    .or_else(|| node.title.clone())
                    .unwrap_or_default();
                let fid = file_id(&node).unwrap_or_default();
                let mime = manifest_att_type(att_manifest.as_ref(), &fid)
                    .unwrap_or_default();
                rsx! {
                    AttachmentFileRow {
                        file_id: fid,
                        name,
                        mime,
                        icon: "music".to_string(),
                        hint: crate::i18n::t("media.music"),
                        name_fallback: url.clone(),
                        img_file: false,
                    }
                }
            } else if status == "input" {
                rsx! {
                    div { class: "music-input-pill", "{crate::i18n::t(\"media.music_paste_hint\")}" }
                }
            } else if !mtitle.is_empty() {
                let cover_raw = meta.get("cover").and_then(|v| v.as_str()).unwrap_or("");
                // C-30：封面先过图片白名单再走代理（proxy_img
                // 会把任意串包成 https 代理 URL，必须先闸）
                let cover = if safe_image_url(cover_raw).is_empty() {
                    String::new()
                } else {
                    proxy_img(cover_raw)
                };
                let subtitle = meta.get("subtitle").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let source = meta.get("source").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let shown_source = if source.is_empty() { crate::i18n::t("media.music") } else { source };
                // C-30：卡片 href 过协议白名单，被拦降级为 div
                // （内容照常渲染、不可点，与原版剥 href 等价）
                let safe_url = safe_http_url(&url);
                let inner = rsx! {
                    if !cover.is_empty() {
                        div { class: "lkc-cover", img { src: "{cover}" } }
                    }
                    div { class: if cover.is_empty() { "lkc-body" } else { "lkc-body has-cover" },
                        div { class: "lkc-title", "{mtitle}" }
                        if !subtitle.is_empty() {
                            div { class: "lkc-subtitle", "{subtitle}" }
                        }
                        div { class: "lkc-source",
                            span { class: "lkc-source-icon", dangerous_inner_html: "{crate::icons::svg_markup(\"music\", 14, \"2.5\", \"currentColor\")}" }
                            span { class: "lkc-source-dot" }
                            span { class: "lkc-source-text", "{shown_source}" }
                        }
                    }
                };
                if safe_url.is_empty() {
                    rsx! { div { class: "link-card-block", {inner} } }
                } else {
                    rsx! {
                        a { class: "link-card-block music-card-link", href: "{safe_url}", target: "_blank", rel: "noreferrer",
                            {inner}
                        }
                    }
                }
            } else if status == "loading" && !url.is_empty() {
                rsx! {
                    div { class: "link-card-skeleton",
                        div { class: "link-card-skeleton-cover" }
                        div { class: "link-card-skeleton-body",
                            div { class: "link-card-skeleton-line", style: "width:75%" }
                            div { class: "link-card-skeleton-line", style: "width:50%" }
                            div { class: "link-card-skeleton-line", style: "width:35%" }
                        }
                    }
                }
            } else if status == "error" && !url.is_empty() {
                let retry = try_use_context::<CardRetry>();
                let bid = node.id.clone().unwrap_or_default();
                // C-30：错误卡的 URL 文本锚同样过白名单，
                // 被拦改 span 保文本、不可点
                let safe_url = safe_http_url(&url);
                rsx! {
                    div { class: "link-card-block music-card-error",
                        span { class: "music-card-error-icon", dangerous_inner_html: "{crate::icons::svg_markup(\"music\", 20, \"2.5\", \"currentColor\")}" }
                        if safe_url.is_empty() {
                            span { class: "music-card-error-url", "{url}" }
                        } else {
                            a { class: "music-card-error-url music-card-link", href: "{safe_url}", target: "_blank", rel: "noreferrer", "{url}" }
                        }
                        if let Some(rt) = retry {
                            button {
                                class: "music-card-retry",
                                onclick: move |_| {
                                    let mut s = rt.0;
                                    s.set(Some(bid.clone()));
                                },
                                "{crate::i18n::t(\"media.retry\")}"
                            }
                        }
                    }
                }
            } else if !url.is_empty() {
                // C-30：胶囊锚过白名单，被拦降级 div 保内容
                let safe_url = safe_http_url(&url);
                let inner = rsx! {
                    span { dangerous_inner_html: "{crate::icons::svg_markup(\"music\", 17, \"2.5\", \"currentColor\")}" }
                    span { "{url}" }
                    if status == "error" {
                        span { class: "lkc-source-text", "{crate::i18n::t(\"media.preview_unavailable\")}" }
                    }
                };
                if safe_url.is_empty() {
                    rsx! { div { class: "link-card-block music-card-error music-pill", {inner} } }
                } else {
                    rsx! {
                        a { class: "link-card-block music-card-error music-card-link music-pill", href: "{safe_url}", target: "_blank", rel: "noreferrer",
                            {inner}
                        }
                    }
                }
            } else {
                rsx! {
                    div { class: "music-pill",
                        span { dangerous_inner_html: "{crate::icons::svg_markup(\"music\", 17, \"2.5\", \"currentColor\")}" }
                        span { "{crate::i18n::t(\"media.music_click_hint\")}" }
                    }
                }
            }
        }
        "attachment" => {
            let is_image = node.image.unwrap_or(false);
            if let Some(fid) = file_id(&node) {
                if is_image {
                    // C-10：图片附件 alt = 文件名（原版
                    // alt=f.name；查名顺序与文件分支同：
                    // manifest 优先、节点 name 兜底）
                    let alt = manifest_att_name(att_manifest.as_ref(), &fid)
                        .or_else(|| node.name.clone())
                        .unwrap_or_default();
                    rsx! {
                        div { class: "atomic attachment",
                            BlobMedia { file_id: fid, gen, kind: "image".to_string(), alt, rsv: crate::imgsize::Reserve::Fill }
                        }
                    }
                } else {
                    let name = manifest_att_name(att_manifest.as_ref(), &fid)
                        .or_else(|| node.name.clone())
                        .unwrap_or_default();
                    // 文件行点按分发在 AttachmentFileRow
                    // 内：图片类文件走图片页（2026-11-24
                    // 扩围口径，att_file_is_image 判定）；
                    // 其余文件走原版分享链（预取 File、手
                    // 势内 share、下载兜底）——旧「新标签
                    // 页打开 blob」在 Safari 上激活过期被
                    // 静默拦截，非图片路已替换。
                    let is_img_file = att_file_is_image(att_manifest.as_ref(), &fid, &name);
                    let mime = manifest_att_type(att_manifest.as_ref(), &fid)
                        .unwrap_or_default();
                    rsx! {
                        AttachmentFileRow {
                            file_id: fid.clone(),
                            name,
                            mime,
                            icon: "attach".to_string(),
                            hint: crate::i18n::t("media.open"),
                            name_fallback: crate::i18n::t("media.attachment"),
                            img_file: is_img_file,
                        }
                    }
                }
            } else {
                rsx! { div { class: "atomic-placeholder", "{crate::i18n::t(\"media.att_no_id\")}" } }
            }
        }
        "link-card" => {
            // 逐项对原版 renderAtomicHTMLUnsafe 的 link-card 分支：
            // 无 meta.title → link-card-err（div，标题=主机名，
            // 来源行=完整 URL）；有标题 → ready 卡（字段以渲染器
            // 口径为准：subtitle/source/cover/type——subtitle 只认
            // 本字段，description 不兜底；source/cover 保留旧字段
            // 兜底；哔哩哔哩不显示副标题；封面走 proxyImg）。
            let url = node.url.as_deref().unwrap_or("").to_string();
            let meta = node.meta.clone().unwrap_or(serde_json::Value::Null);
            let title = meta
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let host = host_of(&url);
            // C-12：删除 Rust 多出的 loading 骨架态——原版
            // link-card 无 loading 态，无标题即 err 卡（骨架
            // 类名规则留待样式批次处置，本批只删渲染分支）。
            if title.is_empty() {
                let shown = if host.is_empty() { url.clone() } else { host.clone() };
                // C-11：容器恒为 div + data-url（值过 C-30
                // 白名单，被拦为空串，与原版 data-url=
                // safeHttpUrl(url) 同形态）；打开动作由桥的
                // 委托点击 window.open 承担，不再整卡 <a>。
                let safe_url = safe_http_url(&url);
                let inner = rsx! {
                    div { class: "lkc-body",
                        div { class: "lkc-title", "{shown}" }
                        div { class: "lkc-source",
                            span { class: "lkc-source-icon", dangerous_inner_html: "{crate::icons::svg_markup(\"link\", 14, \"2.5\", \"currentColor\")}" }
                            span { class: "lkc-source-dot" }
                            span { class: "lkc-source-text", "{url}" }
                        }
                    }
                };
                rsx! { div { class: "atomic link-card-err", "data-url": "{safe_url}", {inner} } }
            } else {
                // 副标题只认 meta.subtitle：原版渲染器从不读
                // description，此前用它兜底 subtitle 会让带描述
                // 的卡片多出一行（混排夹具 h85.4 vs 原版 66.8）。
                let subtitle = meta
                    .get("subtitle")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let cover_raw = meta
                    .get("cover")
                    .and_then(|v| v.as_str())
                    .or_else(|| meta.get("image").and_then(|v| v.as_str()))
                    .unwrap_or("");
                // C-30：封面先过图片白名单再走代理
                let cover = if safe_image_url(cover_raw).is_empty() {
                    String::new()
                } else {
                    proxy_img(cover_raw)
                };
                let source = meta
                    .get("source")
                    .and_then(|v| v.as_str())
                    .or_else(|| meta.get("siteName").and_then(|v| v.as_str()))
                    .unwrap_or("")
                    .to_string();
                let shown_source = if !source.is_empty() {
                    source
                } else if !host.is_empty() {
                    host
                } else {
                    String::new()
                };
                let icon = type_icon(meta.get("type").and_then(|v| v.as_str()));
                let is_bilibili = shown_source == "哔哩哔哩"
                    || (meta.get("type").and_then(|v| v.as_str()) == Some("video")
                        && (url.contains("bilibili") || url.contains("b23.tv")));
                // C-11：ready 卡同 err——div + data-url，
                // 点击由桥委托打开（原版同形态）
                let safe_url = safe_http_url(&url);
                let inner = rsx! {
                    if !cover.is_empty() {
                        div { class: "lkc-cover", img { src: "{cover}" } }
                    }
                    div { class: if cover.is_empty() { "lkc-body" } else { "lkc-body has-cover" },
                        div { class: "lkc-title", "{title}" }
                        if !subtitle.is_empty() && !is_bilibili {
                            div { class: "lkc-subtitle", "{subtitle}" }
                        }
                        div { class: "lkc-source",
                            span { class: "lkc-source-icon", dangerous_inner_html: "{crate::icons::svg_markup(icon, 14, \"2.5\", \"currentColor\")}" }
                            span { class: "lkc-source-dot" }
                            span { class: "lkc-source-text", "{shown_source}" }
                        }
                    }
                };
                rsx! { div { class: "link-card-block", "data-url": "{safe_url}", {inner} } }
            }
        }
        "imgTextCard" => {
            let text = img_text_of(&node);
            let sheet = try_use_context::<TextSheet>();
            let fid = file_id(&node);
            let text2 = text.clone();
            rsx! {
                div { class: "img-text-card",
                    div { class: "itc-img-wrap",
                        if let Some(fid) = fid {
                            BlobMedia { file_id: fid, gen, kind: "image".to_string(), alt: String::new(), rsv: crate::imgsize::Reserve::Fill }
                        } else {
                            // C-14：无图占位盒（原版内联样式
                            // 160px 高、--fill-subtle 底、居中、
                            // placeholder 色、font-13），落为
                            // .itc-placeholder 类规则（editor.css）；
                            // 文案状态感知（见 BlockView 头注）。
                            // 图标与图文行占位同集（camera）：图标
                            // 集统一批只剥了五包文案的 📷 前缀、本
                            // 渲染点漏补 SVG，合流全量 probe_batch3
                            // C-14 抓出后补齐（与 gallery 空态同构）。
                            div { class: "itc-placeholder",
                                span { class: "itc-placeholder-icon", dangerous_inner_html: "{crate::icons::svg_markup(\"camera\", 15, \"2.5\", \"currentColor\")}" }
                                span { "{crate::i18n::t(add_image_key)}" }
                            }
                        }
                    }
                    div {
                        class: "itc-text",
                        // C-14：原版 itc-text 带 role/tabindex/
                        // aria-label（硬编码中文与原版一致）
                        role: "button",
                        tabindex: "0",
                        "aria-label": "查看完整文本",
                        onclick: move |_| {
                            if let Some(sh) = sheet {
                                let mut s = sh.0;
                                s.set(Some((node.id.clone().unwrap_or_default(), text2.clone())));
                            }
                        },
                        "{text}"
                    }
                }
            }
        }
        "imageTextRow" => {
            let text = img_text_of(&node);
            let sheet = try_use_context::<TextSheet>();
            let fid = file_id(&node);
            let text2 = text.clone();
            rsx! {
                div { class: "img-text-row",
                    div { class: "itr-img",
                        if let Some(fid) = fid {
                            BlobMedia { file_id: fid, gen, kind: "image".to_string(), alt: String::new(), rsv: crate::imgsize::Reserve::Fill }
                        } else {
                            // C-15/D-16：原版为 div 占位 + 相机
                            // 图标（此前 span + 图片图标双分叉；
                            // 图标集统一批改 camera SVG）
                            div { class: "itr-placeholder", dangerous_inner_html: "{crate::icons::svg_markup(\"camera\", 30, \"2.5\", \"currentColor\")}" }
                        }
                    }
                    div {
                        class: "itr-text",
                        // C-14 同口径：原版 itr-text 同带
                        // role/tabindex/aria-label
                        role: "button",
                        tabindex: "0",
                        "aria-label": "查看完整文本",
                        onclick: move |_| {
                            if let Some(sh) = sheet {
                                let mut s = sh.0;
                                s.set(Some((node.id.clone().unwrap_or_default(), text2.clone())));
                            }
                        },
                        "{text}"
                    }
                }
            }
        }
        _ => {
            crate::diag::log_once(
                &format!("unknown-block-{ty}"),
                "RENDER",
                &format!("unknown block type {ty} degraded to text"),
            );
            let text = node.plain_text();
            rsx! { div { class: "blk-p", "{text}" } }
        }
    }
}

/// 分类入口（批 11 MD-P1 量测包装）：实际分类在
/// core::md::md_classify（解析单点），本层只累计调用次数
/// 与耗时到 MD_PERF 计数（结果侧量测，MdPreview 节流取走
/// 落 Diag PERF 行）。
pub fn md_classify(text: &str) -> Option<MdKind> {
    let t0 = md_now_ms();
    let r = moment_core::md::md_classify(text);
    md_perf_record_classify(md_now_ms() - t0);
    r
}


#[component]
fn InlineSegs(segs: Vec<InlineSeg>) -> Element {
    let nav = try_use_context::<WikiNav>();
    rsx! {
        for (i, seg) in segs.iter().enumerate() {
            match seg {
                InlineSeg::Text(t) => rsx! { span { key: "t{i}", "{t}" } },
                InlineSeg::Code(t) => rsx! { code { key: "c{i}", "{t}" } },
                InlineSeg::Strong(children) => rsx! {
                    strong { key: "s{i}", InlineSegs { segs: children.clone() } }
                },
                InlineSeg::Em(children) => rsx! {
                    em { key: "e{i}", InlineSegs { segs: children.clone() } }
                },
                InlineSeg::Underline(children) => rsx! {
                    u { key: "n{i}", InlineSegs { segs: children.clone() } }
                },
                InlineSeg::Del(t) => rsx! {
                    del { key: "d{i}", class: "moment-strikethrough", "{t}" }
                },
                InlineSeg::Highlight(t) => rsx! {
                    span { key: "h{i}", class: "moment-highlight", "{t}" }
                },
                InlineSeg::Sup(t) => rsx! { sup { key: "u{i}", "{t}" } },
                InlineSeg::Sub(t) => rsx! { sub { key: "b{i}", "{t}" } },
                InlineSeg::Link { href, children } => {
                    // C-30：MD 预览链接过协议白名单，被拦只
                    // 渲染子段（span 保 key，与文本段同形态）
                    let safe = safe_http_url(href);
                    if safe.is_empty() {
                        rsx! { span { key: "l{i}", InlineSegs { segs: children.clone() } } }
                    } else {
                        rsx! { a { key: "l{i}", href: "{safe}", InlineSegs { segs: children.clone() } } }
                    }
                },
                InlineSeg::Image { src, alt } => {
                    // C-30：MD 预览图 src 过图片白名单，被拦
                    // 保留 img 元素、src 置空（原版同形态）
                    // D-22：同 BlobMedia 口径懒加载
                    // D-22 续项：同 URL 图口径走 imgsize
                    // （Natural 型；data: 图渲染时直读头部、
                    // http 图走缓存 + load 回填）
                    let safe = safe_image_url(src);
                    let rsv_style = crate::imgsize::reserve_style(
                        crate::imgsize::Reserve::Natural,
                        crate::imgsize::size_for_url(&safe),
                    );
                    rsx! { img { key: "g{i}", class: "img-rsv", src: "{safe}", style: "{rsv_style}", onmounted: move |evt| crate::imgsize::track_img_load(evt), alt: "{alt}", loading: "lazy", decoding: "async" } }
                },
                InlineSeg::Wiki { target, label } => {
                    let target = target.clone();
                    rsx! {
                        a {
                            key: "w{i}",
                            class: "moment-wiki-link",
                            href: "#",
                            "data-note-title": "{target}",
                            title: "{crate::i18n::tf(\"editor.wiki_open_title\", &[(\"target\", &target)])}",
                            onclick: move |e: Event<MouseData>| {
                                e.stop_propagation();
                                e.prevent_default();
                                if let Some(mut nav) = nav {
                                    nav.0.set(Some(target.clone()));
                                }
                            },
                            "{label}"
                        }
                    }
                }
                InlineSeg::FootRef { id, ref_id, number } => rsx! {
                    sup { key: "f{i}", class: "footnote-ref",
                        a {
                            href: "#{id}",
                            id: "{ref_id}",
                            "aria-label": "脚注 {number}",
                            "{number}"
                        }
                    }
                },
                InlineSeg::Math { tex, display } => rsx! {
                    MathSpan { key: "m{i}", tex: tex.clone(), display: *display }
                },
                InlineSeg::Break => rsx! { br { key: "r{i}" } },
            }
        }
    }
}

thread_local! {
    /// 公式渲染记忆化：同一 (tex, display) 只解析渲染一次，
    /// 避免 Dioxus 重渲染时重复跑 TeX 解析。
    static MATH_CACHE: std::cell::RefCell<std::collections::HashMap<(String, bool), Result<String, String>>> =
        std::cell::RefCell::new(std::collections::HashMap::new());
}

fn mathml_cached(tex: &str, display: bool) -> Result<String, String> {
    MATH_CACHE.with(|c| {
        let mut map = c.borrow_mut();
        map.entry((tex.to_string(), display))
            .or_insert_with(|| {
                moment_core::render_mathml(tex, display).map_err(|e| e.to_string())
            })
            .clone()
    })
}

fn math_fail_diag(tex: &str, err: &str) {
    crate::diag::log_once(
        &format!(
            "math-fail-{}-{}",
            tex.len(),
            tex.chars().take(24).collect::<String>()
        ),
        "MATH",
        &format!(
            "render failed: {err}; tex={}",
            tex.chars().take(60).collect::<String>()
        ),
    );
}

/// 冷开预热（列表页空闲期由 warmup 模块以合成文本调用）：
/// 预跑 md 预览的纯解析路径（分类、门控、文档解析、行内
/// 解析、脚注抽取与组装）与公式 MathML 渲染，把首次执行
/// 成本前移到空闲期。只算不挂载：mathml_cached 的合成样本
/// 会进公式缓存，键为样本原文，与真实公式同键时结果逐字
/// 一致，无语义影响。返回工作量读数（防优化消除）。
pub fn warm_render_paths(md_texts: &[&str], tex_samples: &[(&str, bool)]) -> usize {
    let mut work = 0usize;
    for text in md_texts {
        if md_classify(text).is_some() {
            work += 1;
        }
        if moment_core::md::looks_like_markdown(text) {
            work += 1;
        }
        work += parse_md_document(text).len();
    }
    for &(tex, display) in tex_samples {
        if let Ok(ml) = mathml_cached(tex, display) {
            work += ml.len();
        }
    }
    work
}

/// 行内公式渲染：.math-inline 包裹 MathML；硬错误回退红色
/// 原码（.math-source）并记 Diag（MATH 标签）。
/// 段中 $$…$$（display=true）与原版同形：原版在此处插入
/// div.math-block（块级、居中、上下 0.75em 边距），故这里改用
/// .math-block 类的 span（CSS 令其 display:block，几何与原版
/// 的段中块式一致），而非行内包裹。
#[component]
fn MathSpan(tex: String, display: bool) -> Element {
    match mathml_cached(&tex, display) {
        Ok(ml) => {
            crate::diag::log_once("math-render-ok", "MATH", "mathml render ok");
            let class = if display { "math-block" } else { "math-inline" };
            let html = format!("<span class=\"{class}\" role=\"math\">{ml}</span>");
            rsx! { span { dangerous_inner_html: "{html}" } }
        }
        Err(e) => {
            math_fail_diag(&tex, &e);
            // 兜底形态与原版 renderMath 一致：display 时是块
            // 包裹红色原码，行内时是原地红色原码。
            if display {
                rsx! {
                    span { class: "math-block", role: "math",
                        code { class: "math-source", "{tex}" }
                    }
                }
            } else {
                // C-27：行内错误态与成功态同构——补 .math-inline
                // 包裹层（此前只剩裸 code.math-source）。
                rsx! {
                    span { class: "math-inline", role: "math",
                        code { class: "math-source", "{tex}" }
                    }
                }
            }
        }
    }
}

/// 块级公式（独占段落的 $$…$$）：.math-block 居中成块。
#[component]
fn MathBlock(tex: String) -> Element {
    match mathml_cached(&tex, true) {
        Ok(ml) => {
            crate::diag::log_once("math-render-ok", "MATH", "mathml render ok");
            rsx! {
                div { class: "math-block", role: "math",
                    span { dangerous_inner_html: "{ml}" }
                }
            }
        }
        Err(e) => {
            math_fail_diag(&tex, &e);
            rsx! {
                div { class: "math-block", role: "math",
                    code { class: "math-source", "{tex}" }
                }
            }
        }
    }
}


/// MD-C10 围栏跨块合并（原版 md-blocks.js collectFenceGroup
/// 的文档级等价）：存量备忘里一个 ``` 围栏可能被拆在多个
/// 相邻 paragraph 块中（起始段含开围栏、中间段是代码行、
/// 末段以 ``` 起为闭合行）。打开备忘时把这类段组并回一段
/// （各段 trimmed 文本以 \n 拼接、写为首块的单一文本子节
/// 点、首块保留 id、被并块删除），渲染才成完整代码块。
/// 起始段自身在下标 ≥3 处已含 ``` 时不向下收集；无闭合
/// 段时收集到相邻段落尽头（与原版收集口径一致）。返回
/// 合并组数。
pub fn merge_split_fences(doc: &mut Vec<Node>) -> usize {
    let mut merges = 0usize;
    let mut i = 0usize;
    while i < doc.len() {
        if doc[i].node_type.as_deref() != Some("paragraph") {
            i += 1;
            continue;
        }
        let first = doc[i].plain_text();
        let first_t = first.trim();
        if !first_t.starts_with("```") || first_t[3..].contains("```") {
            i += 1;
            continue;
        }
        let mut texts = vec![first_t.to_string()];
        let mut j = i + 1;
        while j < doc.len() && doc[j].node_type.as_deref() == Some("paragraph") {
            let nt = doc[j].plain_text().trim().to_string();
            let closes = nt.starts_with("```");
            texts.push(nt);
            j += 1;
            if closes {
                break;
            }
        }
        if texts.len() > 1 {
            doc[i].children = Some(vec![Node {
                text: Some(texts.join("\n")),
                node_type: None,
                id: None,
                children: None,
                ..Default::default()
            }]);
            doc.drain(i + 1..j);
            merges += 1;
        }
        i += 1;
    }
    merges
}

// ===== 批 11 MD-P1：md 解析路径量测（结果侧计数） =====
// classify / parse 的实际调用次数、累计耗时与解析字节数
// 落 thread_local，MdPreview 每 5s 至多取走一行落 Diag
// PERF（与批 4 inputSync 的 5s 节流行同口径）。解析层不
// 直调 diag（非 wasm 目标不可用），只记数。

/// 单调毫秒钟：wasm 走 Date::now（与 editor::perf_now_ms
/// 同源），原生测试走 Instant 基准。
fn md_now_ms() -> f64 {
    #[cfg(target_arch = "wasm32")]
    {
        js_sys::Date::now()
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        thread_local! {
            static MD_T0: std::time::Instant = std::time::Instant::now();
        }
        MD_T0.with(|t0| t0.elapsed().as_secs_f64() * 1000.0)
    }
}

#[derive(Default)]
struct MdPerf {
    classify_calls: u64,
    classify_ms: f64,
    parse_calls: u64,
    parse_ms: f64,
    parse_bytes: u64,
    cache_hits: u64,
    cache_misses: u64,
}

thread_local! {
    static MD_PERF: std::cell::RefCell<MdPerf> =
        std::cell::RefCell::new(MdPerf::default());
    /// 上次 PERF 行落盘时刻（ms，md_now_ms 口径）。
    static MD_PERF_AT: std::cell::Cell<f64> =
        const { std::cell::Cell::new(0.0) };
}

fn md_perf_record_classify(ms: f64) {
    MD_PERF.with(|c| {
        let mut p = c.borrow_mut();
        p.classify_calls += 1;
        p.classify_ms += ms;
    });
}

fn md_perf_record_parse(ms: f64, bytes: usize, hit: bool) {
    MD_PERF.with(|c| {
        let mut p = c.borrow_mut();
        if hit {
            p.cache_hits += 1;
        } else {
            p.cache_misses += 1;
            p.parse_calls += 1;
            p.parse_ms += ms;
            p.parse_bytes += bytes as u64;
        }
    });
}

/// 组件层节流取走计数落 Diag（MdPreview 每次渲染调用，
/// 5s 窗内直接返回）。行内为窗口累计值：分类次数/耗时、
/// 真解析次数/耗时/字节、缓存命中/未命中（缓存未落前恒 0）。
pub fn flush_md_perf_diag() {
    let now = md_now_ms();
    let due = MD_PERF_AT.with(|c| {
        if now - c.get() >= 5000.0 {
            c.set(now);
            true
        } else {
            false
        }
    });
    if !due {
        return;
    }
    let p = MD_PERF.with(|c| std::mem::take(&mut *c.borrow_mut()));
    if p.classify_calls + p.parse_calls + p.cache_hits == 0 {
        return;
    }
    crate::diag::log(
        "PERF",
        &format!(
            "md classify x{} {:.1}ms; parse x{} {:.1}ms {}B; cache hit {} miss {}",
            p.classify_calls,
            p.classify_ms,
            p.parse_calls,
            p.parse_ms,
            p.parse_bytes,
            p.cache_hits,
            p.cache_misses,
        ),
    );
}

thread_local! {
    /// C-28 解析面使用计数（引用式链接 / 原始 HTML 标签）：
    /// parse_md_document 累加，MdPreview 经 take_md_parse_diag
    /// 取走落 Diag。
    static MD_PARSE_DIAG: std::cell::Cell<(usize, usize)> =
        const { std::cell::Cell::new((0, 0)) };
}

/// 取走并清零 C-28 解析面计数（引用式链接数, HTML 标签数）。
pub fn take_md_parse_diag() -> (usize, usize) {
    MD_PARSE_DIAG.with(|c| {
        let v = c.get();
        c.set((0, 0));
        v
    })
}

/// 文档级解析：先抽脚注定义，块序列解析后把已引用定义组装为
/// 脚注区（定义顺序）。未引用定义：原版 preprocess 把原文回填
/// 文末后，marked 的词法会把 `[^x]: 单token` 形整行当作链接
/// 定义吞掉（不渲染），正文含空白时才以字面段落出现（双边
/// 预言机实测 U1/U2）——此处按同一口径分流。
/// 文档级解析入口（批 11 MD-P1 记忆化）：按文本全文作键
/// 缓存解析结果——编辑器每次 doc 变化全量重渲、未变段落的
/// 文本逐字相同，命中即 clone 返回（原生量测 clone 约为真
/// 解析的 1/17）。键即内容、无失效问题；容量有界（条目/
/// 键字节双上限，超限整表清空重建，与 MATH_CACHE 同为
/// thread_local）。真解析在本函数 miss 时走 core::md 解析
/// 本体，其 C-28 计数副作用只在 miss 时发生——计数本就由
/// MdPreview 取走且 log_once 去重，命中不重复累加无可观察
/// 差异。超大单文本（> 键字节上限）不入缓存、恒真解析。
fn parse_md_document(text: &str) -> Vec<MdBlock> {
    if text.len() <= MD_PARSE_CACHE_MAX_BYTES {
        let hit = MD_PARSE_CACHE.with(|c| c.borrow().map.get(text).cloned());
        if let Some(blocks) = hit {
            md_perf_record_parse(0.0, 0, true);
            return blocks;
        }
    }
    // 批 11 MD-P1 量测：真解析次数/耗时/字节落 MD_PERF；
    // C-28 计数（引用式链接 / 原始 HTML 标签）由 core 随
    // 结果带出，此处落 MD_PARSE_DIAG 待 MdPreview 取走。
    let t0 = md_now_ms();
    let out = moment_core::md::parse_md_document_counted(text);
    if out.ref_links_used > 0 || out.html_tags_used > 0 {
        MD_PARSE_DIAG.with(|c| {
            let (r, h) = c.get();
            c.set((r + out.ref_links_used, h + out.html_tags_used));
        });
    }
    md_perf_record_parse(md_now_ms() - t0, text.len(), false);
    let blocks = out.blocks;
    if text.len() <= MD_PARSE_CACHE_MAX_BYTES {
        MD_PARSE_CACHE.with(|c| {
            let mut cache = c.borrow_mut();
            if cache.map.len() >= MD_PARSE_CACHE_MAX_ENTRIES
                || cache.bytes + text.len() > MD_PARSE_CACHE_MAX_BYTES
            {
                cache.map.clear();
                cache.bytes = 0;
            }
            cache.bytes += text.len();
            cache.map.insert(text.to_string(), blocks.clone());
        });
    }
    blocks
}

/// 缓存容量上限：条目数与键字节数双限，超限整表清空
/// （失效语义 = 内容键天然失效 + 容量回收，无 LRU 簿记）。
const MD_PARSE_CACHE_MAX_ENTRIES: usize = 48;
const MD_PARSE_CACHE_MAX_BYTES: usize = 512 * 1024;

thread_local! {
    static MD_PARSE_CACHE: std::cell::RefCell<MdParseCache> =
        std::cell::RefCell::new(MdParseCache::default());
}

#[derive(Default)]
struct MdParseCache {
    map: std::collections::HashMap<String, Vec<MdBlock>>,
    /// 键字节总长（容量核算用）。
    bytes: usize,
}


#[component]
fn MdBlocks(blocks: Vec<MdBlock>) -> Element {
    rsx! {
        for (i, b) in blocks.iter().enumerate() {
            MdBlockView { key: "{i}", block: b.clone() }
        }
    }
}

#[component]
fn MdBlockView(block: MdBlock) -> Element {
    match block {
        MdBlock::Code { lang, code } => rsx! {
            pre {
                match lang {
                    Some(l) => rsx! { code { class: "language-{l}", "{code}" } },
                    None => rsx! { code { "{code}" } },
                }
            }
        },
        MdBlock::Heading { level, segs } => rsx! {
            match level {
                1 => rsx! { h1 { InlineSegs { segs } } },
                2 => rsx! { h2 { InlineSegs { segs } } },
                3 => rsx! { h3 { InlineSegs { segs } } },
                4 => rsx! { h4 { InlineSegs { segs } } },
                5 => rsx! { h5 { InlineSegs { segs } } },
                _ => rsx! { h6 { InlineSegs { segs } } },
            }
        },
        MdBlock::Para { segs } => rsx! {
            p { InlineSegs { segs } }
        },
        MdBlock::Math { tex } => rsx! {
            MathBlock { tex: tex.clone() }
        },
        MdBlock::Divider => rsx! { hr {} },
        MdBlock::Quote { blocks } => rsx! {
            blockquote { MdBlocks { blocks } }
        },
        MdBlock::Callout {
            style,
            title,
            folding,
            blocks,
        } => {
            let icon = crate::icons::callout_icon_markup(style);
            rsx! {
                if let Some(f) = folding {
                    details {
                        class: "callout callout-{style} callout-collapsible",
                        open: f == '+',
                        summary { class: "callout-header",
                            span { class: "callout-icon", dangerous_inner_html: "{icon}" }
                            span { class: "callout-title", "{title}" }
                        }
                        div { class: "callout-body", MdBlocks { blocks } }
                    }
                } else {
                    aside { class: "callout callout-{style}",
                        div { class: "callout-header",
                            span { class: "callout-icon", dangerous_inner_html: "{icon}" }
                            span { class: "callout-title", "{title}" }
                        }
                        div { class: "callout-body", MdBlocks { blocks } }
                    }
                }
            }
        }
        MdBlock::List {
            ordered,
            start,
            items,
        } => rsx! {
            if ordered {
                if start != 1 {
                    ol {
                        start: "{start}",
                        for (i, item) in items.iter().enumerate() {
                            li { key: "{i}",
                                if let Some(checked) = item.checked {
                                    input {
                                        r#type: "checkbox",
                                        disabled: true,
                                        checked,
                                    }
                                }
                                InlineSegs { segs: item.segs.clone() }
                                if !item.sub.is_empty() {
                                    MdBlocks { blocks: item.sub.clone() }
                                }
                            }
                        }
                    }
                } else {
                    ol {
                        for (i, item) in items.iter().enumerate() {
                            li { key: "{i}",
                                if let Some(checked) = item.checked {
                                    input {
                                        r#type: "checkbox",
                                        disabled: true,
                                        checked,
                                    }
                                }
                                InlineSegs { segs: item.segs.clone() }
                                if !item.sub.is_empty() {
                                    MdBlocks { blocks: item.sub.clone() }
                                }
                            }
                        }
                    }
                }
            } else {
                ul {
                    for (i, item) in items.iter().enumerate() {
                        li { key: "{i}",
                            if let Some(checked) = item.checked {
                                input {
                                    r#type: "checkbox",
                                    disabled: true,
                                    checked,
                                }
                            }
                            InlineSegs { segs: item.segs.clone() }
                            if !item.sub.is_empty() {
                                MdBlocks { blocks: item.sub.clone() }
                            }
                        }
                    }
                }
            }
        },
        MdBlock::Table { head, align, rows } => {
            let align_style = |i: usize| -> &'static str {
                match align.get(i) {
                    Some(1) => "text-align:center",
                    Some(2) => "text-align:right",
                    _ => "text-align:left",
                }
            };
            rsx! {
                table {
                    thead {
                        tr {
                            for (i, h) in head.iter().enumerate() {
                                th { style: "{align_style(i)}", InlineSegs { segs: h.clone() } }
                            }
                        }
                    }
                    tbody {
                        for row in rows.iter() {
                            tr {
                                for (i, cell) in row.iter().enumerate() {
                                    td { style: "{align_style(i)}", InlineSegs { segs: cell.clone() } }
                                }
                            }
                        }
                    }
                }
            }
        }
        MdBlock::Footnotes { items } => rsx! {
            section { class: "footnotes", "aria-label": "脚注",
                ol {
                    for item in items.iter() {
                        li { id: "{item.id}",
                            MdBlocks { blocks: item.blocks.clone() }
                            span { class: "footnote-backlinks",
                                " "
                                for rid in item.ref_ids.iter() {
                                    a {
                                        class: "footnote-backref",
                                        href: "#{rid}",
                                        "aria-label": "返回脚注引用",
                                        "↩"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
    }
}

/// md 源段落的预览渲染。两种形态按原版 renderSingleParagraph
/// （src/editor/md-blocks.js:100-139）分发：渲染结果只有一段
/// 行内内容（首元素非块级标签）时是「行内预览」——段落元素
/// 本身挂 .md-preview-inline、contenteditable=false、data-mdtext
/// 存源码（如 ==高亮== 段在原版实测即此形态，内文是
/// span.moment-highlight，不是 mark）；含块级结构时才是
/// .md-preview.block 包裹的块级预览。
/// 预览中的公式计数（Diag MATH 门控命中口径）。
fn count_math_segs(segs: &[InlineSeg]) -> usize {
    segs.iter()
        .map(|s| match s {
            InlineSeg::Math { .. } => 1,
            InlineSeg::Strong(c) | InlineSeg::Em(c) | InlineSeg::Underline(c) => {
                count_math_segs(c)
            }
            InlineSeg::Link { children, .. } => count_math_segs(children),
            _ => 0,
        })
        .sum()
}

fn count_math_blocks(blocks: &[MdBlock]) -> usize {
    blocks
        .iter()
        .map(|b| match b {
            MdBlock::Math { .. } => 1,
            MdBlock::Para { segs } | MdBlock::Heading { segs, .. } => count_math_segs(segs),
            MdBlock::Quote { blocks } | MdBlock::Callout { blocks, .. } => {
                count_math_blocks(blocks)
            }
            MdBlock::List { items, .. } => items
                .iter()
                .map(|it| count_math_segs(&it.segs) + count_math_blocks(&it.sub))
                .sum(),
            MdBlock::Table { head, rows, .. } => {
                head.iter().map(|c| count_math_segs(c)).sum::<usize>()
                    + rows
                        .iter()
                        .flat_map(|r| r.iter())
                        .map(|c| count_math_segs(c))
                        .sum::<usize>()
            }
            MdBlock::Footnotes { items } => items
                .iter()
                .map(|it| count_math_blocks(&it.blocks))
                .sum(),
            _ => 0,
        })
        .sum()
}

/// 本批渲染口径的特征扫描（Diag RENDER 记录用）：软换行
/// <br>、裸链接 autolink、嵌套子列表是否出现在此次预览中。
fn md_feature_flags(blocks: &[MdBlock]) -> (bool, bool, bool) {
    fn seg_flags(segs: &[InlineSeg], f: &mut (bool, bool, bool)) {
        for s in segs {
            match s {
                InlineSeg::Break => f.0 = true,
                InlineSeg::Link { href, children } => {
                    if let [InlineSeg::Text(label)] = children.as_slice() {
                        if href == label
                            || href.as_str() == format!("http://{label}")
                            || href.as_str() == format!("mailto:{label}")
                        {
                            f.1 = true;
                        }
                    }
                    seg_flags(children, f);
                }
                InlineSeg::Strong(c) | InlineSeg::Em(c) => seg_flags(c, f),
                _ => {}
            }
        }
    }
    fn block_flags(blocks: &[MdBlock], f: &mut (bool, bool, bool)) {
        for b in blocks {
            match b {
                MdBlock::Para { segs } | MdBlock::Heading { segs, .. } => seg_flags(segs, f),
                MdBlock::Quote { blocks } | MdBlock::Callout { blocks, .. } => {
                    block_flags(blocks, f)
                }
                MdBlock::List { items, .. } => {
                    for it in items {
                        seg_flags(&it.segs, f);
                        if !it.sub.is_empty() {
                            f.2 = true;
                            block_flags(&it.sub, f);
                        }
                    }
                }
                MdBlock::Table { head, rows, .. } => {
                    for c in head {
                        seg_flags(c, f);
                    }
                    for r in rows {
                        for c in r {
                            seg_flags(c, f);
                        }
                    }
                }
                MdBlock::Footnotes { items } => {
                    for it in items {
                        block_flags(&it.blocks, f);
                    }
                }
                _ => {}
            }
        }
    }
    let mut f = (false, false, false);
    block_flags(blocks, &mut f);
    f
}

#[component]
pub fn MdPreview(text: String) -> Element {
    // 批 11 MD-P1：节流落 md 解析量测行（5s 一行，见
    // flush_md_perf_diag）；取走点在组件层与 C-28 计数同位。
    flush_md_perf_diag();
    let blocks = parse_md_document(&text);
    let math_count = count_math_blocks(&blocks);
    if math_count > 0 {
        crate::diag::log_once(
            &format!("math-preview-{math_count}"),
            "MATH",
            &format!("preview math x{math_count}"),
        );
    }
    // C-28 新解析面 Diag：引用式链接 / 原始 HTML 的使用
    // 计数由 parse_md_document 落 thread_local，此处取走
    let (ref_links, html_tags) = take_md_parse_diag();
    if ref_links > 0 {
        crate::diag::log_once(
            &format!("md-ref-links-{ref_links}"),
            "RENDER",
            &format!("md reference-style links resolved x{ref_links}"),
        );
    }
    if html_tags > 0 {
        crate::diag::log_once(
            &format!("md-raw-html-{html_tags}"),
            "RENDER",
            &format!("md raw html tags handled x{html_tags}"),
        );
    }
    let (has_break, has_autolink, has_nested) = md_feature_flags(&blocks);
    if has_break {
        crate::diag::log_once(
            "md-softbreak-br",
            "RENDER",
            "md preview soft line-break rendered as <br> (marked breaks:true parity)",
        );
    }
    if has_autolink {
        crate::diag::log_once(
            "md-autolink",
            "RENDER",
            "md preview bare url/email autolink rendered (marked gfm parity)",
        );
    }
    if has_nested {
        crate::diag::log_once(
            "md-nested-list",
            "RENDER",
            "md preview nested list rendered inside parent item",
        );
    }
    if blocks.len() == 1 {
        if let MdBlock::Para { segs } = &blocks[0] {
            let segs = segs.clone();
            return rsx! {
                p {
                    class: "md-preview-inline",
                    tabindex: "0",
                    role: "group",
                    "aria-label": "Markdown 预览，按回车或空格编辑",
                    InlineSegs { segs }
                }
            };
        }
    }
    rsx! {
        div { class: "md-preview block markdown-render",
            if blocks.is_empty() {
                p { "{text}" }
            } else {
                MdBlocks { blocks }
            }
        }
    }
}

/// 该 md 源文本渲染成块级预览（.md-preview.block）而非行内
/// 预览：parse 后不止一个块，或唯一的块不是普通段落。与
/// MdPreview 的分支判定同源，供编辑器块流决定尾随空段
/// （原版 ensureTrailingParagraphBlock 只跟块级预览）。
/// 实现在 core::md（解析单点），此处仅委托。
pub fn md_is_block_preview(text: &str) -> bool {
    moment_core::md::md_is_block_preview(text)
}

// ===== Markdown 渲染回归测试（第八批车道 A） =====
// 期望值全部来自原版预言机（vendor/marked v15 + markdown-
// bridge，breaks:true/gfm:true）对同一语料的实测输出，
// 2026-11-22 以无头 Node 跑原版 editor.md.js 得到。
#[cfg(test)]
mod proxy_img_tests {
    use super::*;

    fn decoded(out: &str) -> String {
        // proxy_img 输出为 /img?url=<percent-encoded>，断言解码后的目标 URL
        let enc = out
            .strip_prefix("https://mynote.overtrees.workers.dev/img?url=")
            .expect("proxy prefix");
        let mut bytes = Vec::new();
        let b = enc.as_bytes();
        let mut i = 0;
        while i < b.len() {
            if b[i] == b'%' && i + 2 < b.len() {
                bytes.push(u8::from_str_radix(&enc[i + 1..i + 3], 16).unwrap());
                i += 3;
            } else {
                bytes.push(b[i]);
                i += 1;
            }
        }
        String::from_utf8(bytes).unwrap()
    }

    #[test]
    fn mzstatic_wp_variant_normalized_to_square_bb() {
        // Worker /meta 实测返回形态（知了/陳默之 Apple Music）
        let out = proxy_img("https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/f6/d9/14/f6d914d4-d164-9eff-fc73-b537bfd24764/cover.jpg/1200x630wp-60.jpg");
        assert_eq!(
            decoded(&out),
            "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/f6/d9/14/f6d914d4-d164-9eff-fc73-b537bfd24764/cover.jpg/600x600bb.jpg"
        );
    }

    #[test]
    fn mzstatic_wp_without_quality_and_bb_untouched() {
        let out = proxy_img("https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/cover.jpg/1200x630wp.png");
        assert!(decoded(&out).ends_with("/600x600bb.png"));
        let sq = "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/cover.jpg/600x600bb.jpg";
        assert_eq!(decoded(&proxy_img(sq)), sq);
    }

    #[test]
    fn mzstatic_non_wp_and_foreign_wp_untouched() {
        // 末段非 wp 变体（bf 等）不匹配、原样保留
        let bf = "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/cover.jpg/1200x630bf-60.jpg";
        assert_eq!(decoded(&proxy_img(bf)), bf);
        // 非 mzstatic 主机的 wp 形末段不动
        let foreign = "https://example.com/img/1200x630wp-60.jpg";
        assert_eq!(decoded(&proxy_img(foreign)), foreign);
        // 查询串不参与匹配、原样带回
        let out = proxy_img("https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/cover.jpg/1200x630wp-60.jpg?x=1");
        assert!(decoded(&out).ends_with("/600x600bb.jpg?x=1"));
    }

    #[test]
    fn qq_branch_unaffected() {
        let out = proxy_img("https://y.gtimg.cn/music/photo_new/T002R300x300M000abc.jpg");
        assert!(decoded(&out).contains("T002R800x800M000abc.jpg"));
    }
}

#[cfg(test)]
#[test]
fn batch3_fence_merge() {
    // MD-C10：拆段围栏并回一段（首块 id 保留、文本以
    // \n 拼接）；自含闭合段不向下收集；非段落块断链
    let para = |id: &str, text: &str| Node {
        node_type: Some("paragraph".to_string()),
        id: Some(id.to_string()),
        children: Some(vec![Node {
            text: Some(text.to_string()),
            ..Default::default()
        }]),
        ..Default::default()
    };
    let mut doc = vec![
        para("a", "```rust"),
        para("b", "fn main() {}"),
        para("c", "```"),
        para("d", "后续"),
    ];
    assert_eq!(merge_split_fences(&mut doc), 1);
    assert_eq!(doc.len(), 2);
    assert_eq!(doc[0].id.as_deref(), Some("a"));
    assert_eq!(doc[0].plain_text(), "```rust\nfn main() {}\n```");
    let mut closed = vec![para("a", "```\nx\n```"), para("b", "普通")];
    assert_eq!(merge_split_fences(&mut closed), 0);
    assert_eq!(closed.len(), 2);
}
