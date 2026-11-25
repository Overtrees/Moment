//! 块渲染（只读路径与编辑器共用）：DOM 结构与类名对原版
//! editor.css / editor-shell.css 的阅读态规则——段落/标题/引用/
//! 待办（圆形勾选）/Callout 变体/链接卡 lkc/图文卡/附件文件卡等。

use dioxus::prelude::*;
use mynote_core::{safe_http_url, safe_image_url, split_highlight, Node};

use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

use crate::idb;

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

#[derive(Clone, Copy)]
pub struct CardMenu(pub Signal<Option<CardMenuState>>);

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

/// encodeURIComponent 等价的百分号编码。
pub fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 2);
    for &b in s.as_bytes() {
        let c = b as char;
        if c.is_ascii_alphanumeric() || "-_.!~*'()".contains(c) {
            out.push(c);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

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
    format!(
        "https://mynote.overtrees.workers.dev/img?url={}",
        url_encode(&u)
    )
}

/// 卡片来源图标（原版 getTypeIcon）。
pub fn type_icon(meta_type: Option<&str>) -> &'static str {
    match meta_type {
        Some("music") => "🎵",
        Some("video") => "🎬",
        _ => "🔗",
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

fn gallery_item_of(e: &mynote_core::GalleryEntry) -> Option<GalleryItem> {
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
                        mark { class: "mynote-highlight", key: "h{idx}", {inner} }
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
            if let Some(bytes) = idb::get_attachment(&fid).await {
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
                match crate::idb::get_attachment(&fid).await {
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
                            if let Some(bytes) = crate::idb::get_attachment(&fid).await {
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
                    crate::diag::log("ATT", &format!("open {fid} -> missing"));
                } else {
                    let mime_c = mime_click.clone();
                    spawn(async move {
                        match crate::idb::get_attachment(&fid).await {
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
                                crate::diag::log("ATT", &format!("open {fid} -> missing"));
                            }
                        }
                    });
                }
            },
            span { class: "att-icon", "{icon}" }
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
            let (icon, title_key) = match variant {
                "warning" => ("⚠", "callout.warning"),
                "tip" => ("💡", "callout.tip"),
                "important" => ("❗", "callout.important"),
                "caution" => ("⛔", "callout.caution"),
                _ => ("ℹ", "callout.note"),
            };
            rsx! {
                div { class: "callout callout-{variant}",
                    div { class: "callout-header",
                        span { class: "callout-icon", "{icon}" }
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
                                span { class: "gallery-empty-icon", "🖼" }
                                span { class: "gallery-empty-label", "{crate::i18n::t(gallery_add_key)}" }
                            }
                            div { class: "gallery-empty-tile alt", "data-liftsurface": "",
                                span { class: "gallery-empty-icon", "🖼" }
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
            // 封面 2.4/1 + 三行骨架 + 转圈）→ error 卡（🎵+链接+
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
                        icon: "🎵".to_string(),
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
                            span { class: "lkc-source-icon", "🎵" }
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
                        span { class: "music-card-error-icon", "🎵" }
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
                    span { "🎵" }
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
                        span { "🎵" }
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
                            icon: "📎".to_string(),
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
                            span { class: "lkc-source-icon", "🔗" }
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
                            span { class: "lkc-source-icon", "{icon}" }
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
                            // 文案状态感知（见 BlockView 头注）
                            div { class: "itc-placeholder", "{crate::i18n::t(add_image_key)}" }
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
                            // C-15/D-16：原版为 div 占位、emoji
                            // 为 📷（此前 span + 🖼 双分叉）
                            div { class: "itr-placeholder", "📷" }
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

/// Markdown 源段落（原版模型实证，use-slash.js:518-545）：
/// 代码块/列表/Callout 在文档里都是 type=paragraph、children[0].text
/// 存 Markdown 源码，渲染时成 md-preview；点击回源码编辑。
/// 这里是与原版 editor.md.js 等价的分类器（只覆盖块级三类）。
#[derive(Clone, PartialEq)]
pub enum MdKind {
    Code(String),
    /// 含合法 wiki 链接的普通段落（原版 looksLikeMarkdown 含
    /// [[…]] 模式，此类段落进 md 预览、链接成锚点可点）。
    Rich(String),
    Callout {
        style: &'static str,
        title: String,
        body: Vec<String>,
    },
    List {
        ordered: bool,
        items: Vec<String>,
    },
    /// 表格（GFM）：表头 / 对齐（0 左 1 中 2 右）/ 行
    Table {
        head: Vec<String>,
        align: Vec<u8>,
        rows: Vec<Vec<String>>,
    },
    /// 单行 md 标题段（# … ######）
    Heading {
        level: u8,
        text: String,
    },
    /// 引用块：全部行以 > 起（非 Callout），段落已分好
    Quote(Vec<String>),
    /// 分隔线段（--- / *** / ___）
    Divider,
}

fn callout_style_title(raw: &str) -> (&'static str, Option<&'static str>) {
    // editor.md.js CALLOUT_STYLE / CALLOUT_TITLE 逐字移植（标题为
    // 原版硬编码中文，不走语言包——与原版行为一致）。C-21：
    // 未知类型标题回退类型原文（rawType），故标题以 Option
    // 返回——None 时调用方用原文（保留大小写）兜底；此前恒
    // 返回「笔记」，[!FOO] 的标题被吞。
    match raw {
        "note" => ("note", Some("笔记")),
        "info" => ("note", Some("信息")),
        "todo" => ("note", Some("待办")),
        "abstract" => ("note", Some("摘要")),
        "quote" => ("note", Some("引用")),
        "tip" => ("tip", Some("提示")),
        "success" => ("tip", Some("成功")),
        "example" => ("tip", Some("示例")),
        "question" => ("warning", Some("问题")),
        "warning" => ("warning", Some("注意")),
        "important" => ("important", Some("重要")),
        "failure" => ("important", Some("失败")),
        "bug" => ("important", Some("问题")),
        "caution" => ("caution", Some("小心")),
        "danger" => ("caution", Some("危险")),
        _ => ("note", None),
    }
}

/// 表格行拆分：去掉首尾的 | 后按 | 切分；\| 是转义竖线、
/// 不作分隔（marked 口径，预言机实测表头 `a \| b` 为一格），
/// 保留 `\|` 原样留待 parse_inlines 的反斜杠转义解成 '|'。
fn split_table_row(line: &str) -> Vec<String> {
    let t = line.trim();
    let t = t.strip_prefix('|').unwrap_or(t);
    let t = if t.ends_with('|') && !t.ends_with("\\|") {
        &t[..t.len() - 1]
    } else {
        t
    };
    let mut cells = Vec::new();
    let mut cur = String::new();
    let mut it = t.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            cur.push(c);
            if let Some(nc) = it.next() {
                cur.push(nc);
            }
        } else if c == '|' {
            cells.push(std::mem::take(&mut cur));
        } else {
            cur.push(c);
        }
    }
    cells.push(cur);
    cells
}

/// 分类入口（批 11 MD-P1 量测包装）：实际分类在
/// md_classify_impl，本层只累计调用次数与耗时到 MD_PERF
/// 计数（结果侧量测，MdPreview 节流取走落 Diag PERF 行）。
pub fn md_classify(text: &str) -> Option<MdKind> {
    let t0 = md_now_ms();
    let r = md_classify_impl(text);
    md_perf_record_classify(md_now_ms() - t0);
    r
}

fn md_classify_impl(text: &str) -> Option<MdKind> {
    let trimmed = text.trim_matches('\n');
    if trimmed.is_empty() {
        return None;
    }
    let lines: Vec<&str> = trimmed.split('\n').collect();
    // 代码围栏：首行 ``` 或 ~~~ 起；闭合行同字符、长度 ≥ 开围栏，
    // 可缺省（未闭合按 marked 口径取到段尾）。原版分类见 M4。
    if lines.len() >= 2 {
        let f0 = lines[0].trim_start();
        let fc = if f0.starts_with("```") {
            Some('`')
        } else if f0.starts_with("~~~") {
            Some('~')
        } else {
            None
        };
        if let Some(fc) = fc {
            let open_len = f0.chars().take_while(|c| *c == fc).count();
            let mut close_idx: Option<usize> = None;
            for (k, l) in lines.iter().enumerate().skip(1) {
                let t = l.trim();
                if !t.is_empty() && t.len() >= open_len && t.chars().all(|c| c == fc) {
                    close_idx = Some(k);
                    break;
                }
            }
            // C-23 guard：空围栏不转预览（原版失焦 guard：
            // text 剥尽 ``` 后无内容即跳过，如 "```\n```"）。
            if fc == '`' && trimmed.replace("```", "").trim().is_empty() {
                return None;
            }
            let inner = match close_idx {
                Some(k) => lines[1..k].join("\n"),
                None => lines[1..].join("\n"),
            };
            return Some(MdKind::Code(inner));
        }
    }
    // C-23 失焦 guards（原版 md-blocks.js renderSingleParagraph
    // 的 guards 仅失焦路径；Rust 无状态渲染以分类层为等价
    // 单点）：引用正文（剥首行 ^>\s* 后全文）<2 字符不转
    // 预览；> [! 未以 \[!\w+\] 闭合不转预览。此前无等价物，
    // `> a` 这类极短引用失焦即被转成预览块。
    {
        let t = trimmed.trim_start();
        if t.starts_with('>') {
            let after_gt = t[1..].trim_start();
            if after_gt.starts_with("[!") {
                let valid = after_gt[2..]
                    .find(']')
                    .map(|e| {
                        let raw = &after_gt[2..2 + e];
                        !raw.is_empty()
                            && raw
                                .chars()
                                .all(|c| c.is_ascii_alphanumeric() || c == '_')
                    })
                    .unwrap_or(false);
                if !valid {
                    return None;
                }
            } else if after_gt.chars().count() < 2 {
                return None;
            }
        }
    }
    // Callout：首行 > [!TYPE] 可带折叠符 +/- 与自定义标题，
    // 其余行 > 前缀。折叠符不是标题（M5：原版 preprocessCallouts
    // 的正则 \[!(\w+)\]([+-]?)(?:[ \t]+title)? ）。
    if let Some(first) = lines.first() {
        let f = first.trim_start();
        if let Some(rest) = f.strip_prefix("> [!") {
            if let Some(end) = rest.find(']') {
                let raw_orig = &rest[..end];
                let raw = raw_orig.to_lowercase();
                let mut tail = &rest[end + 1..];
                if tail.starts_with('+') || tail.starts_with('-') {
                    tail = &tail[1..];
                }
                let custom = tail.trim().to_string();
                let (style, default_title) = callout_style_title(&raw);
                // C-21：未知类型标题回退类型原文（保留大小写）
                let title = if !custom.is_empty() {
                    custom
                } else if let Some(dt) = default_title {
                    dt.to_string()
                } else {
                    raw_orig.to_string()
                };
                let body: Vec<String> = lines[1..]
                    .iter()
                    .map(|l| {
                        let t = l.trim_start();
                        t.strip_prefix('>')
                            .map(|r| r.strip_prefix(' ').unwrap_or(r).to_string())
                            .unwrap_or_else(|| l.to_string())
                    })
                    .collect();
                return Some(MdKind::Callout { style, title, body });
            }
        }
    }
    // C-28 缩进代码块：全部非空行 ≥4 缩进（须在 List 分支
    // 之前——"    - x" 此前被 trim 后误判 List，marked 给
    // 代码块）。
    {
        let ne: Vec<&&str> = lines.iter().filter(|l| !l.trim().is_empty()).collect();
        if !ne.is_empty() && ne.iter().all(|l| is_code_indented(l)) {
            let text = lines
                .iter()
                .map(|l| dedent4(l))
                .collect::<Vec<_>>()
                .join("\n")
                .trim_end()
                .to_string();
            return Some(MdKind::Code(text));
        }
    }
    // 列表：全部非空行同为 - 或 N. 前缀
    let non_empty: Vec<&&str> = lines.iter().filter(|l| !l.trim().is_empty()).collect();
    if !non_empty.is_empty() {
        if non_empty.iter().all(|l| l.trim_start().starts_with("- ")) {
            return Some(MdKind::List {
                ordered: false,
                items: non_empty
                    .iter()
                    .map(|l| l.trim_start()[2..].to_string())
                    .collect(),
            });
        }
        let is_num = |l: &str| -> Option<String> {
            let t = l.trim_start();
            let dot = t.find(". ")?;
            if t[..dot].chars().all(|c| c.is_ascii_digit()) && dot > 0 {
                Some(t[dot + 2..].to_string())
            } else {
                None
            }
        };
        if non_empty.iter().all(|l| is_num(l).is_some()) {
            return Some(MdKind::List {
                ordered: true,
                items: non_empty.iter().map(|l| is_num(l).unwrap()).collect(),
            });
        }
    }
    // 分隔线：整段就是 ---（3 个以上）。*** / ___ 独占段在原版
    // 门控 looksLikeMarkdown 下不转换（M8），不归入此类。
    {
        let t = trimmed.trim();
        if t.len() >= 3 && t.chars().all(|c| c == '-') {
            return Some(MdKind::Divider);
        }
    }
    // 单行标题：# ~ ###### + 空格
    if lines.len() == 1 {
        let t = lines[0].trim_start();
        let hashes = t.chars().take_while(|c| *c == '#').count();
        if (1..=6).contains(&hashes) && t[hashes..].starts_with(' ') {
            return Some(MdKind::Heading {
                level: hashes as u8,
                text: t[hashes + 1..].trim().to_string(),
            });
        }
    }
    // 表格：首行含 |、次行是 |---|---| 分隔行。另须全文过
    // looksLikeMarkdown 门控：原版没有表格分组通道，表格段
    // 只经单段落通道转换，门控与其它段相同——单元格无任何
    // 行内 md 信号的纯表格在原版保持源码态（审计 e08 的表格
    // 是靠单元格里的 **粗** 与 `代码` 过门控的）。这是与 M8
    // 同类的反向差：Rust 曾无条件转表格，现收窄对齐原版。
    if lines.len() >= 2 && lines[0].contains('|') && looks_like_markdown(text) {
        let sep = lines[1].trim();
        let cells: Vec<String> = split_table_row(sep);
        let is_sep = !cells.is_empty()
            && cells.iter().all(|c| {
                let c = c.trim();
                !c.is_empty()
                    && c.chars().all(|ch| ch == '-' || ch == ':')
                    && c.contains('-')
            });
        if is_sep {
            let align: Vec<u8> = cells
                .iter()
                .map(|c| {
                    let c = c.trim();
                    if c.starts_with(':') && c.ends_with(':') {
                        1
                    } else if c.ends_with(':') {
                        2
                    } else {
                        0
                    }
                })
                .collect();
            return Some(MdKind::Table {
                head: split_table_row(lines[0])
                    .iter()
                    .map(|c| c.trim().to_string())
                    .collect(),
                align,
                rows: lines[2..]
                    .iter()
                    .filter(|l| !l.trim().is_empty())
                    .map(|l| {
                        split_table_row(l)
                            .iter()
                            .map(|c| c.trim().to_string())
                            .collect()
                    })
                    .collect(),
            });
        }
    }
    // 引用块：全部非空行以 > 起（Callout 已先行处理）
    if !non_empty.is_empty()
        && non_empty.iter().all(|l| l.trim_start().starts_with('>'))
    {
        let mut paras: Vec<String> = Vec::new();
        let mut cur: Vec<String> = Vec::new();
        for l in &lines {
            let t = l.trim_start();
            let body = t
                .strip_prefix('>')
                .map(|r| r.strip_prefix(' ').unwrap_or(r))
                .unwrap_or("");
            if body.trim().is_empty() {
                if !cur.is_empty() {
                    paras.push(cur.join(" "));
                    cur = Vec::new();
                }
            } else {
                cur.push(body.trim().to_string());
            }
        }
        if !cur.is_empty() {
            paras.push(cur.join(" "));
        }
        if !paras.is_empty() {
            return Some(MdKind::Quote(paras));
        }
    }
    // 其余可转换段落（纯行内 md、混合结构、脚注、上下标等）：
    // 原版门控 looksLikeMarkdown 命中即转预览，归 Rich（M1/M3）。
    if looks_like_markdown(text) {
        return Some(MdKind::Rich(text.to_string()));
    }
    None
}

/// 原版 looksLikeMarkdown（editor.md.js:330-335）的手写等价：
/// 行首结构模式 + 全文行内模式任一命中即判定为 Markdown。
/// 数学公式门控（hasMathSyntax）由 core::mathml 提供（行为
/// 规格对齐原版：$$ 成对、$ 成对且内容过启发式）。
pub fn looks_like_markdown(text: &str) -> bool {
    let s = text.trim();
    if s.is_empty() {
        return false;
    }
    // 行首模式：(^|\n)#{1,6}\s / [-*+]\s / \d+\.\s / >\s / ---+ 整行
    for line in s.split('\n') {
        let lc: Vec<char> = line.chars().collect();
        let mut h = 0;
        while h < lc.len() && lc[h] == '#' {
            h += 1;
        }
        if (1..=6).contains(&h) && h < lc.len() && lc[h].is_whitespace() {
            return true;
        }
        if lc.len() >= 2 && matches!(lc[0], '-' | '*' | '+') && lc[1].is_whitespace() {
            return true;
        }
        let mut d = 0;
        while d < lc.len() && lc[d].is_ascii_digit() {
            d += 1;
        }
        if d >= 1 && d + 1 < lc.len() && lc[d] == '.' && lc[d + 1].is_whitespace() {
            return true;
        }
        if lc.len() >= 2 && lc[0] == '>' && lc[1].is_whitespace() {
            return true;
        }
        if line.len() >= 3 && line.chars().all(|c| c == '-') {
            return true;
        }
    }
    let chars: Vec<char> = s.chars().collect();
    let n = chars.len();
    // `{1,3}：任一反引号即命中
    if chars.contains(&'`') {
        return true;
    }
    let span = |open: &[char], close: &[char], forbid: &[char]| -> bool {
        scan_span(&chars, 0, open, close, forbid).is_some()
    };
    // \*\*[^*]+\*\* / __[^_]+__ / ~~[^~]+~~ / ==[^=]+==
    if span(&['*', '*'], &['*', '*'], &['*']) {
        return true;
    }
    if span(&['_', '_'], &['_', '_'], &['_']) {
        return true;
    }
    if span(&['~', '~'], &['~', '~'], &['~', '\n']) {
        return true;
    }
    if span(&['=', '='], &['=', '='], &['=', '\n']) {
        return true;
    }
    // \[[^\]]+\]\] 与 \[\^[^\]]+\]
    if span(&['[', '['], &[']', ']'], &[']']) {
        return true;
    }
    if span(&['[', '^'], &[']'], &[']']) {
        return true;
    }
    // \^\([^\n]+\)\^ / ~\([^\n]+\)~
    if span(&['^', '('], &[')', '^'], &['(', ')', '\n']) {
        return true;
    }
    if span(&['~', '('], &[')', '~'], &['(', ')', '\n']) {
        return true;
    }
    // !\[[^\]]*\]\([^)]+\) 与 \[[^\]]+\]\([^)]+\)
    if find_md_link(&chars, true).is_some() || find_md_link(&chars, false).is_some() {
        return true;
    }
    // (^|[^*])\*[^*\n]+\*($|[^*])
    {
        let mut i = 0;
        while i < n {
            if chars[i] == '*' && (i == 0 || chars[i - 1] != '*') {
                let mut j = i + 1;
                while j < n && chars[j] != '*' && chars[j] != '\n' {
                    j += 1;
                }
                if j < n && chars[j] == '*' && j > i + 1 && (j + 1 >= n || chars[j + 1] != '*') {
                    return true;
                }
            }
            i += 1;
        }
    }
    // \^[A-Za-z0-9][A-Za-z0-9,+-]*\^
    {
        let mut i = 0;
        while i + 1 < n {
            if chars[i] == '^' && is_sup_char(chars[i + 1], true) {
                let mut j = i + 1;
                while j < n && is_sup_char(chars[j], false) {
                    j += 1;
                }
                if j < n && chars[j] == '^' && j > i + 1 {
                    return true;
                }
            }
            i += 1;
        }
    }
    // (^|[^~])~[A-Za-z0-9][A-Za-z0-9,+-]*~(?!~)
    {
        let mut i = 0;
        while i + 1 < n {
            if chars[i] == '~'
                && (i == 0 || chars[i - 1] != '~')
                && is_sup_char(chars[i + 1], true)
            {
                let mut j = i + 1;
                while j < n && is_sup_char(chars[j], false) {
                    j += 1;
                }
                if j < n && chars[j] == '~' && j > i + 1 && (j + 1 >= n || chars[j + 1] != '~')
                {
                    return true;
                }
            }
            i += 1;
        }
    }
    // 数学公式门控（hasMathSyntax 等价，core::mathml）。
    mynote_core::has_math_syntax(s)
}

/// 上下标裸形字符集 [A-Za-z0-9,+-]；first=true 时只许字母数字起手。
fn is_sup_char(c: char, first: bool) -> bool {
    if c.is_ascii_alphanumeric() {
        true
    } else {
        !first && matches!(c, ',' | '+' | '-')
    }
}

/// 在 chars[from..] 中找 open…close 跨度：open 后至少一个不含
/// forbid 的字符再接 close。命中返回 (内容, close 之后下标)。
fn scan_span(
    chars: &[char],
    from: usize,
    open: &[char],
    close: &[char],
    forbid: &[char],
) -> Option<(String, usize)> {
    let n = chars.len();
    let mut i = from;
    while i + open.len() <= n {
        if chars[i..i + open.len()] == *open {
            let start = i + open.len();
            let mut j = start;
            loop {
                if j + close.len() <= n && chars[j..j + close.len()] == *close {
                    if j > start {
                        return Some((chars[start..j].iter().collect(), j + close.len()));
                    }
                    break;
                }
                if j >= n || forbid.contains(&chars[j]) {
                    break;
                }
                j += 1;
            }
        }
        i += 1;
    }
    None
}

/// 找 [text](href)（image=true 时找 ![alt](href)）的第一处命中，
/// 返回 (文本字符, href, 结束下标)。
fn find_md_link(chars: &[char], image: bool) -> Option<(Vec<char>, String, usize)> {
    let n = chars.len();
    let mut i = 0;
    while i < n {
        let open = if image {
            if chars[i] == '!' && i + 1 < n && chars[i + 1] == '[' {
                Some(i + 1)
            } else {
                None
            }
        } else if chars[i] == '[' {
            Some(i)
        } else {
            None
        };
        if let Some(o) = open {
            if let Some(res) = parse_md_link_at(chars, o) {
                if image || !res.0.is_empty() {
                    return Some(res);
                }
            }
        }
        i += 1;
    }
    None
}

/// 在 chars[start]=='[' 处解析 [text](href)：text 取首个 ']'，
/// 其后须紧跟 '('，href 取首个 ')'（空格后的 "title" 部分丢弃）。
fn parse_md_link_at(
    chars: &[char],
    start: usize,
) -> Option<(Vec<char>, String, usize)> {
    let n = chars.len();
    let mut close = start + 1;
    while close < n && chars[close] != ']' {
        close += 1;
    }
    if close >= n {
        return None;
    }
    if close + 1 >= n || chars[close + 1] != '(' {
        return None;
    }
    let mut end = close + 2;
    while end < n && chars[end] != ')' {
        end += 1;
    }
    if end >= n {
        return None;
    }
    let raw_href: String = chars[close + 2..end].iter().collect();
    let href = raw_href
        .trim()
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string();
    if href.is_empty() {
        return None;
    }
    Some((chars[start + 1..close].to_vec(), href, end + 1))
}

/// GFM 裸链接 autolink 扫描（chars[i] 为 ASCII 字母数字）：
/// 命中返回 (显示文本, href, 结束下标)。口径（marked gfm +
/// 双边预言机实测）：
/// - http:// / https:// / ftp://（大小写不敏感）与 www. 开头
///   （www. 的主机段须再含一个 '.'；href 补 http://）；
/// - URL 吞到空白或 '<' 为止，尾部标点（?!.,:*_~'）与不配平
///   的 ')' / ']' 剥除；
/// - 邮箱 local@domain.tld（TLD ≥1 位纯字母；a@b 无点不算，
///   a@b.c 算——预言机实测）→ mailto:；
/// - 起点前一字符为 ASCII 字母数字或 '.'/'/'/'@'/'_' 时不
///   触发（词中/路径中不算新链接起点）；CJK 前字不挡（原版
///   marked 在 CJK 后照样起链接、且把后续 CJK 吞进 URL，
///   本实现吞入规则与之相同，仅 href 不做百分号编码）。
fn scan_autolink(chars: &[char], i: usize) -> Option<(String, String, usize)> {
    let n = chars.len();
    if i > 0 {
        let p = chars[i - 1];
        if p.is_ascii_alphanumeric() || matches!(p, '.' | '/' | '@' | '_') {
            return None;
        }
    }
    let rest: String = chars[i..].iter().collect();
    let lower = rest.to_ascii_lowercase();
    // URL 形
    let (prefix_len, is_www) = if lower.starts_with("https://") {
        (8, false)
    } else if lower.starts_with("http://") {
        (7, false)
    } else if lower.starts_with("ftp://") {
        (6, false)
    } else if lower.starts_with("www.") {
        (4, true)
    } else {
        (0, false)
    };
    if prefix_len > 0 {
        let mut j = i;
        while j < n && !chars[j].is_whitespace() && chars[j] != '<' {
            j += 1;
        }
        let mut end = j;
        // 尾部标点与不配平括号剥除（GFM 口径）
        loop {
            if end <= i + prefix_len {
                break;
            }
            let last = chars[end - 1];
            if matches!(last, '?' | '!' | '.' | ',' | ':' | '*' | '_' | '~' | '\'') {
                end -= 1;
                continue;
            }
            if last == ')' || last == ']' {
                let (open, close) = if last == ')' { ('(', ')') } else { ('[', ']') };
                let opens = chars[i..end].iter().filter(|c| **c == open).count();
                let closes = chars[i..end].iter().filter(|c| **c == close).count();
                if closes > opens {
                    end -= 1;
                    continue;
                }
            }
            break;
        }
        if end <= i + prefix_len {
            return None;
        }
        if is_www {
            // 主机段（首个 '/' 前）除 www. 外须再含一个 '.'
            let host: String = chars[i + 4..end]
                .iter()
                .take_while(|c| **c != '/')
                .collect();
            if !host.contains('.') {
                return None;
            }
        }
        let label: String = chars[i..end].iter().collect();
        let href = if is_www {
            format!("http://{label}")
        } else {
            label.clone()
        };
        return Some((label, href, end));
    }
    // 邮箱形：local@domain.tld
    let mut j = i;
    while j < n
        && (chars[j].is_ascii_alphanumeric() || matches!(chars[j], '.' | '_' | '%' | '+' | '-'))
    {
        j += 1;
    }
    if j == i || j >= n || chars[j] != '@' {
        return None;
    }
    let mut k = j + 1;
    while k < n
        && (chars[k].is_ascii_alphanumeric() || matches!(chars[k], '.' | '-'))
    {
        k += 1;
    }
    let mut end = k;
    while end > j + 1 && matches!(chars[end - 1], '.' | '-') {
        end -= 1;
    }
    let domain: String = chars[j + 1..end].iter().collect();
    let dot = domain.rfind('.')?;
    let tld = &domain[dot + 1..];
    if dot == 0 || tld.is_empty() || !tld.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    let label: String = chars[i..end].iter().collect();
    Some((label.clone(), format!("mailto:{label}"), end))
}

/// scan_span 的锚定版：open 必须恰在 from 处（行内解析用，
/// 避免本处不成跨度时误吞后文的同类跨度）。
fn scan_span_at(
    chars: &[char],
    from: usize,
    open: &[char],
    close: &[char],
    forbid: &[char],
) -> Option<(String, usize)> {
    let n = chars.len();
    if from + open.len() > n || chars[from..from + open.len()] != *open {
        return None;
    }
    let start = from + open.len();
    let mut j = start;
    loop {
        if j + close.len() <= n && chars[j..j + close.len()] == *close {
            if j > start {
                return Some((chars[start..j].iter().collect(), j + close.len()));
            }
            return None;
        }
        if j >= n || forbid.contains(&chars[j]) {
            return None;
        }
        j += 1;
    }
}

// ===== 行内 Markdown 解析（marked 子集 + 此刻扩展语法） =====
//
// 优先级按原版管线：代码段先保护（protectCodeSegments），
// 扩展语法（~~/==/上下标/wiki/脚注）在 marked 之前 stash，
// 其内容不再二次解析；**/__ 粗体、*/_ 斜体、链接文本递归解析。

#[derive(Clone, PartialEq)]
pub enum InlineSeg {
    Text(String),
    Code(String),
    Strong(Vec<InlineSeg>),
    Em(Vec<InlineSeg>),
    /// 原始 HTML <u> 下划线（C-28）：md 语法无对应定界符，
    /// 仅 HTML 通道产生，子段递归解析（marked 口径）。
    Underline(Vec<InlineSeg>),
    /// ~~删除~~：原版 stash 直出 HTML，内容不解析
    Del(String),
    /// ==高亮==：同上
    Highlight(String),
    Sup(String),
    Sub(String),
    Link {
        href: String,
        children: Vec<InlineSeg>,
    },
    Image {
        src: String,
        alt: String,
    },
    Wiki {
        target: String,
        label: String,
    },
    FootRef {
        id: String,
        ref_id: String,
        number: usize,
    },
    /// 数学公式（$…$ / $$…$$）：预览层经 core::mathml 渲染
    /// MathML；渲染硬错误时回退红色原码（.math-source）。
    Math {
        tex: String,
        display: bool,
    },
    Break,
}

/// 脚注定义（原版 preprocessFootnotes 的逐段等价实现）。
struct FootnoteDef {
    label: String,
    body: String,
    original: String,
    id: String,
    number: usize,
}

/// 行内解析上下文：脚注定义表 + 引用计数（编号按定义顺序，
/// 与原版 order.indexOf 口径一致）。
struct InlineCtx {
    /// 小写 label → 定义下标
    def_map: std::collections::HashMap<String, usize>,
    defs: Vec<FootnoteDef>,
    /// 定义下标 → 已出现的 ref id 列表（文档顺序）
    ref_ids: std::collections::HashMap<usize, Vec<String>>,
    counts: std::collections::HashMap<usize, usize>,
    /// 正在解析链接文本：其内不再触发裸链接 autolink
    /// （marked 不在链接文本内再套链接）。
    in_link: bool,
    /// C-28 引用式链接定义：归一 label（小写、内部空白折叠）
    /// → href，由 parse_md_document 在块解析前装填。
    link_defs: std::collections::HashMap<String, String>,
    /// 本文档已解析的引用式链接数 / 原始 HTML 标签数（Diag）
    ref_links_used: usize,
    html_tags_used: usize,
}

impl InlineCtx {
    fn empty() -> Self {
        InlineCtx {
            def_map: std::collections::HashMap::new(),
            defs: Vec::new(),
            ref_ids: std::collections::HashMap::new(),
            counts: std::collections::HashMap::new(),
            in_link: false,
            link_defs: std::collections::HashMap::new(),
            ref_links_used: 0,
            html_tags_used: 0,
        }
    }
    fn foot_ref(&mut self, label: &str) -> Option<InlineSeg> {
        let idx = *self.def_map.get(&label.to_lowercase())?;
        let def = &self.defs[idx];
        let (id, number) = (def.id.clone(), def.number);
        let c = {
            let e = self.counts.entry(idx).or_insert(0);
            *e += 1;
            *e
        };
        let ref_id = format!("{id}-ref-{c}");
        self.ref_ids.entry(idx).or_default().push(ref_id.clone());
        Some(InlineSeg::FootRef {
            id,
            ref_id,
            number,
        })
    }
}

/// encodeURIComponent 后 %→_、再把 [^A-Za-z0-9_-] 换 _（原版 footnoteId）。
fn footnote_id(label: &str) -> String {
    let enc = url_encode(label.trim());
    let mut out = String::from("fn-");
    for c in enc.chars() {
        if c == '%' {
            out.push('_');
        } else if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    out
}

/// 抽出脚注定义行（含缩进续行），返回 (剩余文本, 定义表)。
/// 定义顺序即编号顺序；重复 label 只取首个（原版口径）。
fn extract_footnotes(text: &str) -> (String, Vec<FootnoteDef>) {
    fn def_line(line: &str) -> Option<(String, String)> {
        let b = line.as_bytes();
        let mut i = 0;
        while i < b.len() && b[i] == b' ' && i < 3 {
            i += 1;
        }
        let rest = &line[i..];
        let rest = rest.strip_prefix("[^")?;
        let close = rest.find("]:")?;
        let label = &rest[..close];
        if label.is_empty() || label.chars().any(|c| c.is_whitespace() || c == ']') {
            return None;
        }
        let body = rest[close + 2..].trim_start_matches([' ', '\t']);
        Some((label.to_string(), body.to_string()))
    }
    fn continuation(line: &str) -> Option<String> {
        if let Some(r) = line.strip_prefix('\t') {
            return Some(r.to_string());
        }
        let spaces = line.chars().take_while(|c| *c == ' ').count();
        if spaces >= 2 {
            return Some(line[spaces..].to_string());
        }
        None
    }
    let lines: Vec<&str> = text.split('\n').collect();
    let mut kept: Vec<&str> = Vec::new();
    let mut defs: Vec<FootnoteDef> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut i = 0;
    while i < lines.len() {
        if let Some((label, first)) = def_line(lines[i]) {
            let mut body = vec![first];
            let mut original = vec![lines[i].to_string()];
            let mut j = i + 1;
            while j < lines.len() {
                match continuation(lines[j]) {
                    Some(c) => {
                        body.push(c);
                        original.push(lines[j].to_string());
                        j += 1;
                    }
                    None => break,
                }
            }
            if seen.insert(label.to_lowercase()) {
                let number = defs.len() + 1;
                defs.push(FootnoteDef {
                    id: footnote_id(&label),
                    label,
                    body: body.join("\n").trim().to_string(),
                    original: original.join("\n"),
                    number,
                });
            }
            i = j;
        } else {
            kept.push(lines[i]);
            i += 1;
        }
    }
    (kept.join("\n"), defs)
}

/// 引用 label 归一（marked 口径）：内部空白折叠为单空格、
/// 去首尾空白、转小写。
fn normalize_ref_label(label: &str) -> String {
    label.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}

/// C-28：抽出链接引用定义行 `[label]: href "title"`（marked
/// 词法层吞行、正文不渲染），返回 (剩余文本, 定义表)。href
/// 可用 <> 包裹，其后标题部分丢弃；同 label 只取首个定义。
/// 与 extract_footnotes 同构：围栏内的定义形行也会被抽走
/// （既有脚注抽取的同款取舍）。
fn extract_link_defs(text: &str) -> (String, Vec<(String, String)>) {
    fn def_line(line: &str) -> Option<(String, String)> {
        let bytes = line.as_bytes();
        let mut i = 0;
        while i < bytes.len() && i < 3 && bytes[i] == b' ' {
            i += 1;
        }
        let rest = line[i..].strip_prefix('[')?;
        // 脚注定义已先行抽走，此处防御性排除
        if rest.starts_with('^') {
            return None;
        }
        let close = rest.find("]:")?;
        let label_raw = &rest[..close];
        if label_raw.is_empty() {
            return None;
        }
        let after = rest[close + 2..].trim_start();
        if after.is_empty() {
            return None;
        }
        let href = if let Some(h) = after.strip_prefix('<') {
            let e = h.find('>')?;
            h[..e].to_string()
        } else {
            after.split_whitespace().next()?.to_string()
        };
        if href.is_empty() {
            return None;
        }
        Some((normalize_ref_label(label_raw), href))
    }
    let lines: Vec<&str> = text.split('\n').collect();
    let mut kept: Vec<&str> = Vec::new();
    let mut defs: Vec<(String, String)> = Vec::new();
    for line in lines {
        match def_line(line) {
            Some((label, href)) => {
                if !defs.iter().any(|(l, _)| *l == label) {
                    defs.push((label, href));
                }
            }
            None => kept.push(line),
        }
    }
    (kept.join("\n"), defs)
}

/// C-28 引用式链接/图片解析：chars[start]=='[' 处依次试
/// 全引用 [text][label]、折叠引用 [text][]、快捷引用
/// [label]。命中 ctx.link_defs 才消费；未命中返回 None
/// （调用方按字面处理）。返回 (文本字符, href, 结束下标)。
fn parse_ref_link_at(
    chars: &[char],
    start: usize,
    ctx: &InlineCtx,
) -> Option<(Vec<char>, String, usize)> {
    let n = chars.len();
    if start >= n || chars[start] != '[' {
        return None;
    }
    let mut j = start + 1;
    while j < n && chars[j] != ']' {
        j += 1;
    }
    if j >= n || j == start + 1 {
        return None;
    }
    let text: Vec<char> = chars[start + 1..j].to_vec();
    if j + 1 < n && chars[j + 1] == '[' {
        let mut k = j + 2;
        while k < n && chars[k] != ']' {
            k += 1;
        }
        if k >= n {
            return None;
        }
        let label_raw: String = if k == j + 2 {
            text.iter().collect()
        } else {
            chars[j + 2..k].iter().collect()
        };
        let href = ctx.link_defs.get(&normalize_ref_label(&label_raw))?;
        return Some((text, href.clone(), k + 1));
    }
    // 快捷引用：其后紧跟 ( 时归行内链接形态，不半消费
    if j + 1 < n && chars[j + 1] == '(' {
        return None;
    }
    let label_raw: String = text.iter().collect();
    let href = ctx.link_defs.get(&normalize_ref_label(&label_raw))?;
    Some((text, href.clone(), j + 1))
}

/// 行内解析入口：text 为段落/单元格/列表项的原始行内文本。
fn parse_inlines(text: &str, ctx: &mut InlineCtx) -> Vec<InlineSeg> {
    let chars: Vec<char> = text.chars().collect();
    parse_inline_chars(&chars, ctx)
}

/// 行内解析（带公式切分）：先经 core::split_math 切出公式段
/// （代码段在切分器内整体保护、转义与防误判口径见 core::
/// mathml），文本段再走字符级解析。递归子段（粗斜体/链接
/// 文本）也经此入口，公式在任意嵌套层都能命中。
fn parse_inline_chars(chars: &[char], ctx: &mut InlineCtx) -> Vec<InlineSeg> {
    let text: String = chars.iter().collect();
    let segs = mynote_core::split_math(&text);
    let single_text = segs.len() == 1
        && matches!(&segs[0], mynote_core::MathSegment::Text(t) if t.as_str() == text.as_str());
    if single_text {
        return parse_inline_chars_raw(chars, ctx);
    }
    let mut out: Vec<InlineSeg> = Vec::new();
    for seg in segs {
        match seg {
            mynote_core::MathSegment::Text(t) => {
                let cs: Vec<char> = t.chars().collect();
                out.extend(parse_inline_chars_raw(&cs, ctx));
            }
            mynote_core::MathSegment::Math { tex, display } => {
                out.push(InlineSeg::Math { tex, display });
            }
        }
    }
    out
}

/// C-28 原始 HTML：一个标签的解析结果（属性只保留 href/
/// src/alt 等渲染所需项的原始串，消毒在渲染层过闸）。
struct HtmlTag {
    name: String,
    closing: bool,
    self_closing: bool,
    attrs: Vec<(String, String)>,
    end: usize,
}

fn html_tag_attr<'a>(tag: &'a HtmlTag, name: &str) -> Option<&'a str> {
    tag.attrs
        .iter()
        .find(|(k, _)| k == name)
        .map(|(_, v)| v.as_str())
}

fn is_void_html(name: &str) -> bool {
    matches!(
        name,
        "area" | "base" | "br" | "col" | "embed" | "hr" | "img" | "input" | "link" | "meta"
            | "param" | "source" | "track" | "wbr"
    )
}

/// 连内容一并丢弃的标签（DOMPurify 对 script/style 等的
/// DROP_CONTENT 口径）。svg/math 在 DOMPurify 白名单内，
/// 但段模型无对应结构——丢弃并在提交信息注明此取舍。
fn is_drop_content_html(name: &str) -> bool {
    matches!(
        name,
        "script" | "style" | "title" | "iframe" | "object" | "textarea" | "xmp" | "noscript"
            | "template" | "svg" | "math" | "head" | "noembed" | "noframes" | "frame"
            | "frameset" | "applet"
    )
}

/// 解析 chars[start]=='<' 处的一个标签：属性值可含引号内
/// 的 '>'；形态不合（无标签名、未闭合等）返回 None，调用
/// 方按字面处理。
fn parse_html_tag(chars: &[char], start: usize) -> Option<HtmlTag> {
    let n = chars.len();
    let mut i = start + 1;
    let mut closing = false;
    if i < n && chars[i] == '/' {
        closing = true;
        i += 1;
    }
    if i >= n || !chars[i].is_ascii_alphabetic() {
        return None;
    }
    let name_start = i;
    while i < n && (chars[i].is_ascii_alphanumeric() || chars[i] == '-') {
        i += 1;
    }
    let name: String = chars[name_start..i]
        .iter()
        .collect::<String>()
        .to_lowercase();
    let mut attrs: Vec<(String, String)> = Vec::new();
    loop {
        while i < n && chars[i].is_whitespace() {
            i += 1;
        }
        if i >= n {
            return None;
        }
        if chars[i] == '>' {
            return Some(HtmlTag {
                name,
                closing,
                self_closing: false,
                attrs,
                end: i + 1,
            });
        }
        if chars[i] == '/' {
            if i + 1 < n && chars[i + 1] == '>' {
                return Some(HtmlTag {
                    name,
                    closing,
                    self_closing: true,
                    attrs,
                    end: i + 2,
                });
            }
            return None;
        }
        let a_start = i;
        while i < n
            && !chars[i].is_whitespace()
            && chars[i] != '='
            && chars[i] != '>'
            && chars[i] != '/'
        {
            i += 1;
        }
        if i == a_start {
            return None;
        }
        let a_name: String = chars[a_start..i]
            .iter()
            .collect::<String>()
            .to_lowercase();
        while i < n && chars[i].is_whitespace() {
            i += 1;
        }
        let mut a_val = String::new();
        if i < n && chars[i] == '=' {
            i += 1;
            while i < n && chars[i].is_whitespace() {
                i += 1;
            }
            if i < n && (chars[i] == '"' || chars[i] == '\'') {
                let q = chars[i];
                i += 1;
                let v_start = i;
                while i < n && chars[i] != q {
                    i += 1;
                }
                if i >= n {
                    return None;
                }
                a_val = chars[v_start..i].iter().collect();
                i += 1;
            } else {
                let v_start = i;
                while i < n && !chars[i].is_whitespace() && chars[i] != '>' {
                    i += 1;
                }
                a_val = chars[v_start..i].iter().collect();
            }
        }
        attrs.push((a_name, a_val));
    }
}

/// 同名嵌套计数地找闭合标签：返回 (内容结束下标, 闭合标
/// 签之后下标)；无闭合返回 None（调用方取到输入尾）。
fn scan_html_close(chars: &[char], from: usize, name: &str) -> Option<(usize, usize)> {
    let n = chars.len();
    let mut depth = 1usize;
    let mut j = from;
    while j < n {
        if chars[j] == '<' {
            if let Some(t) = parse_html_tag(chars, j) {
                if t.name == name {
                    if t.closing {
                        depth -= 1;
                        if depth == 0 {
                            return Some((j, t.end));
                        }
                    } else if !t.self_closing && !is_void_html(&t.name) {
                        depth += 1;
                    }
                }
                j = t.end;
                continue;
            }
        }
        j += 1;
    }
    None
}

/// 段列拍平为纯文本（Del/Highlight/Sub/Sup/Code 等 String
/// 载荷段的内层口径，与 marked 渲染后取文本一致）。
fn segs_plain_text(segs: &[InlineSeg]) -> String {
    let mut s = String::new();
    for seg in segs {
        match seg {
            InlineSeg::Text(t) | InlineSeg::Code(t) | InlineSeg::Del(t)
            | InlineSeg::Highlight(t) => s.push_str(t),
            InlineSeg::Strong(c) | InlineSeg::Em(c) | InlineSeg::Underline(c) => {
                s.push_str(&segs_plain_text(c))
            }
            InlineSeg::Link { children, .. } => s.push_str(&segs_plain_text(children)),
            InlineSeg::Sub(t) | InlineSeg::Sup(t) => s.push_str(t),
            InlineSeg::Image { alt, .. } => s.push_str(alt),
            InlineSeg::Math { tex, .. } => s.push_str(tex),
            InlineSeg::Wiki { label, target } => {
                s.push_str(if label.is_empty() { target } else { label })
            }
            InlineSeg::FootRef { .. } | InlineSeg::Break => {}
        }
    }
    s
}

/// C-28：chars[start]=='<' 处的原始 HTML 处理（原版
/// marked + DOMPurify 白名单面的段模型等价）：可映射标签
/// 转结构段，其余白名单标签剥标签留子段，DROP_CONTENT
/// 集连内容丢弃，危险 href/src 在渲染层经 C-30 的
/// safe_http_url / safe_image_url 过闸（此处不裸放行）。
/// 非标签形态返回 None（调用方回落 autolink / 字面）。
fn handle_html_at(
    chars: &[char],
    start: usize,
    ctx: &mut InlineCtx,
) -> Option<(Vec<InlineSeg>, usize)> {
    let n = chars.len();
    // 注释 <!-- … -->：闭合才吞，未闭合按字面
    if chars[start + 1..].starts_with(&['!', '-', '-']) {
        let mut j = start + 4;
        while j + 2 < n {
            if chars[j] == '-' && chars[j + 1] == '-' && chars[j + 2] == '>' {
                ctx.html_tags_used += 1;
                return Some((Vec::new(), j + 3));
            }
            j += 1;
        }
        return None;
    }
    // <!…> / <?…> 声明：跳到 '>'
    if start + 1 < n && (chars[start + 1] == '!' || chars[start + 1] == '?') {
        let mut j = start + 1;
        while j < n && chars[j] != '>' {
            j += 1;
        }
        if j >= n {
            return None;
        }
        ctx.html_tags_used += 1;
        return Some((Vec::new(), j + 1));
    }
    let tag = parse_html_tag(chars, start)?;
    // 游离闭标签直接丢弃（DOMPurify 同口径）
    if tag.closing {
        ctx.html_tags_used += 1;
        return Some((Vec::new(), tag.end));
    }
    ctx.html_tags_used += 1;
    let name = tag.name.as_str();
    if is_void_html(name) {
        return Some((
            match name {
                "br" | "hr" => vec![InlineSeg::Break],
                "img" => vec![InlineSeg::Image {
                    src: html_tag_attr(&tag, "src").unwrap_or("").to_string(),
                    alt: html_tag_attr(&tag, "alt").unwrap_or("").to_string(),
                }],
                _ => Vec::new(),
            },
            tag.end,
        ));
    }
    // 容器内容范围：自闭合为空；无闭合取到输入尾
    let (inner, after): (Vec<char>, usize) = if tag.self_closing {
        (Vec::new(), tag.end)
    } else if let Some((inner_end, close_end)) = scan_html_close(chars, tag.end, name) {
        (chars[tag.end..inner_end].to_vec(), close_end)
    } else {
        (chars[tag.end..].to_vec(), n)
    };
    if is_drop_content_html(name) {
        return Some((Vec::new(), after));
    }
    // code/kbd 内容按原文（不二次解析）
    if name == "code" || name == "kbd" {
        return Some((
            vec![InlineSeg::Code(inner.iter().collect())],
            after,
        ));
    }
    if name == "a" {
        let saved = ctx.in_link;
        ctx.in_link = true;
        let children = parse_inline_chars_raw(&inner, ctx);
        ctx.in_link = saved;
        return Some((
            vec![InlineSeg::Link {
                href: html_tag_attr(&tag, "href").unwrap_or("").to_string(),
                children,
            }],
            after,
        ));
    }
    let children = parse_inline_chars_raw(&inner, ctx);
    let segs = match name {
        "b" | "strong" => vec![InlineSeg::Strong(children)],
        "i" | "em" => vec![InlineSeg::Em(children)],
        "u" | "ins" => vec![InlineSeg::Underline(children)],
        "s" | "del" | "strike" => vec![InlineSeg::Del(segs_plain_text(&children))],
        "mark" => vec![InlineSeg::Highlight(segs_plain_text(&children))],
        "sup" => vec![InlineSeg::Sup(segs_plain_text(&children))],
        "sub" => vec![InlineSeg::Sub(segs_plain_text(&children))],
        // 其余白名单/未知标签：剥标签，子段直接拼入
        _ => children,
    };
    Some((segs, after))
}

fn parse_inline_chars_raw(chars: &[char], ctx: &mut InlineCtx) -> Vec<InlineSeg> {
    let n = chars.len();
    let mut out: Vec<InlineSeg> = Vec::new();
    let mut buf = String::new();
    let flush = |buf: &mut String, out: &mut Vec<InlineSeg>| {
        if !buf.is_empty() {
            out.push(InlineSeg::Text(std::mem::take(buf)));
        }
    };
    let mut i = 0;
    while i < n {
        let c = chars[i];
        // 硬换行：行尾 2+ 空格 + \n（marked 口径）
        if c == ' ' && i + 1 < n && chars[i + 1] == ' ' {
            let mut j = i;
            while j < n && chars[j] == ' ' {
                j += 1;
            }
            if j < n && chars[j] == '\n' {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Break);
                i = j + 1;
                continue;
            }
        }
        // 软换行：原版 marked 以 breaks:true 渲染（markdown-
        // bridge setOptions），段内单个 \n 即 <br>（双边预言机
        // 实测：多行段落/引用懒续行/列表项续行皆然）。
        if c == '\n' {
            flush(&mut buf, &mut out);
            out.push(InlineSeg::Break);
            i += 1;
            continue;
        }
        // 反斜杠转义 ASCII 标点
        if c == '\\' && i + 1 < n && chars[i + 1].is_ascii_punctuation() {
            buf.push(chars[i + 1]);
            i += 2;
            continue;
        }
        // 代码段（等长反引号串闭合）
        if c == '`' {
            let mut run = 1;
            while i + run < n && chars[i + run] == '`' {
                run += 1;
            }
            match find_code_close(chars, i + run, run) {
                Some((content, end)) => {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Code(code_content(&content)));
                    i = end;
                }
                None => {
                    for _ in 0..run {
                        buf.push('`');
                    }
                    i += run;
                }
            }
            continue;
        }
        // 图片 ![alt](src)
        if c == '!' && i + 1 < n && chars[i + 1] == '[' {
            if let Some((alt_chars, href, end)) = parse_md_link_at(chars, i + 1) {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Image {
                    src: href,
                    alt: alt_chars.iter().collect(),
                });
                i = end;
                continue;
            }
            // C-28 引用式图片 ![alt][label]
            if let Some((alt_chars, href, end)) = parse_ref_link_at(chars, i + 1, ctx) {
                flush(&mut buf, &mut out);
                ctx.ref_links_used += 1;
                out.push(InlineSeg::Image {
                    src: href,
                    alt: alt_chars.iter().collect(),
                });
                i = end;
                continue;
            }
        }
        if c == '[' {
            // wiki 链接 [[目标|标签]]
            if i + 1 < n && chars[i + 1] == '[' {
                if let Some((target, label, end)) = parse_wiki_at(chars, i) {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Wiki { target, label });
                    i = end;
                    continue;
                }
            }
            // 脚注引用 [^label]
            if i + 1 < n && chars[i + 1] == '^' {
                let mut j = i + 2;
                while j < n && chars[j] != ']' {
                    j += 1;
                }
                if j < n && j > i + 2 {
                    let label: String = chars[i + 2..j].iter().collect();
                    if let Some(seg) = ctx.foot_ref(label.trim()) {
                        flush(&mut buf, &mut out);
                        out.push(seg);
                        i = j + 1;
                        continue;
                    }
                }
            }
            // 普通链接 [text](href)
            if let Some((text_chars, href, end)) = parse_md_link_at(chars, i) {
                flush(&mut buf, &mut out);
                let saved = ctx.in_link;
                ctx.in_link = true;
                let children = parse_inline_chars(&text_chars, ctx);
                ctx.in_link = saved;
                out.push(InlineSeg::Link { href, children });
                i = end;
                continue;
            }
            // C-28 引用式链接 [text][label] / [text][] / [label]
            if let Some((text_chars, href, end)) = parse_ref_link_at(chars, i, ctx) {
                flush(&mut buf, &mut out);
                ctx.ref_links_used += 1;
                let saved = ctx.in_link;
                ctx.in_link = true;
                let children = parse_inline_chars(&text_chars, ctx);
                ctx.in_link = saved;
                out.push(InlineSeg::Link { href, children });
                i = end;
                continue;
            }
        }
        // 原始 HTML（C-28，先于 autolink）与角标 autolink
        // <https://…>
        if c == '<' {
            if let Some((segs, end)) = handle_html_at(chars, i, ctx) {
                flush(&mut buf, &mut out);
                out.extend(segs);
                i = end;
                continue;
            }
            let mut j = i + 1;
            while j < n && chars[j] != '>' && chars[j] != '\n' {
                j += 1;
            }
            if j < n && chars[j] == '>' {
                let inner: String = chars[i + 1..j].iter().collect();
                if inner.starts_with("http://") || inner.starts_with("https://") {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Link {
                        href: inner.clone(),
                        children: vec![InlineSeg::Text(inner)],
                    });
                    i = j + 1;
                    continue;
                }
            }
        }
        // GFM 裸链接 / 邮箱 autolink（marked gfm 口径，双边
        // 预言机实测：https://…、www.…、me@example.com 成
        // 链接；a@b 不成）。链接文本内不触发（ctx.in_link）。
        if !ctx.in_link && c.is_ascii_alphanumeric() {
            if let Some((label, href, end)) = scan_autolink(chars, i) {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Link {
                    href,
                    children: vec![InlineSeg::Text(label)],
                });
                i = end;
                continue;
            }
        }
        // ~~删除~~（内容不二次解析）
        if c == '~' && i + 1 < n && chars[i + 1] == '~' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['~', '~'], &['~', '~'], &['~', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Del(content));
                i = end;
                continue;
            }
        }
        // ==高亮==（内容不二次解析）
        if c == '=' && i + 1 < n && chars[i + 1] == '=' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['=', '='], &['=', '='], &['=', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Highlight(content));
                i = end;
                continue;
            }
        }
        // ^(上标)^ / ~(下标)~
        if c == '^' && i + 1 < n && chars[i + 1] == '(' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['^', '('], &[')', '^'], &['(', ')', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sup(content));
                i = end;
                continue;
            }
        }
        if c == '~' && i + 1 < n && chars[i + 1] == '(' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['~', '('], &[')', '~'], &['(', ')', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sub(content));
                i = end;
                continue;
            }
        }
        // ^裸上标^
        if c == '^' && i + 1 < n && is_sup_char(chars[i + 1], true) {
            let mut j = i + 1;
            while j < n && is_sup_char(chars[j], false) {
                j += 1;
            }
            if j < n && chars[j] == '^' && j > i + 1 {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sup(chars[i + 1..j].iter().collect()));
                i = j + 1;
                continue;
            }
        }
        // ~裸下标~（前字符非 ~、闭合 ~ 后非 ~）
        if c == '~'
            && (i == 0 || chars[i - 1] != '~')
            && i + 1 < n
            && is_sup_char(chars[i + 1], true)
        {
            let mut j = i + 1;
            while j < n && is_sup_char(chars[j], false) {
                j += 1;
            }
            if j < n && chars[j] == '~' && j > i + 1 && (j + 1 >= n || chars[j + 1] != '~')
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sub(chars[i + 1..j].iter().collect()));
                i = j + 1;
                continue;
            }
        }
        // 三连定界 ***x*** / ___x___：原版 marked 渲染为
        // <em><strong>x</strong></em>（双边预言机实测）。
        if (c == '*' || c == '_')
            && i + 3 < n
            && chars[i + 1] == c
            && chars[i + 2] == c
            && !chars[i + 3].is_whitespace()
        {
            let word_inner = c == '_' && i > 0 && chars[i - 1].is_alphanumeric();
            if !word_inner {
                let mut k = i + 3;
                let mut closed = None;
                while k + 2 < n {
                    if chars[k] == c && chars[k + 1] == c && chars[k + 2] == c {
                        if k > i + 3 && !chars[k - 1].is_whitespace() {
                            closed = Some(k);
                        }
                        break;
                    }
                    k += 1;
                }
                if let Some(k) = closed {
                    let inner: Vec<char> = chars[i + 3..k].to_vec();
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Em(vec![InlineSeg::Strong(
                        parse_inline_chars(&inner, ctx),
                    )]));
                    i = k + 3;
                    continue;
                }
            }
        }
        // 粗体 ** / __（__ 不在词内触发；开定界后不得是空白，
        // marked flanking 口径：`** 粗 **` 保持字面）
        if (c == '*' || c == '_')
            && i + 2 < n
            && chars[i + 1] == c
            && !chars[i + 2].is_whitespace()
        {
            let word_inner = c == '_' && i > 0 && chars[i - 1].is_alphanumeric();
            if !word_inner {
                if let Some((inner, end)) = scan_delim(chars, i + 2, c, true) {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Strong(parse_inline_chars(&inner, ctx)));
                    i = end;
                    continue;
                }
            }
        }
        // 斜体 * / _（开定界后不得是空白，同上；当前符若是
        // 双符 run 的起点则不作单符斜体——那是粗体/三连的
        // 领地，粗体因 flanking 失败时原版保持字面，如
        // `** 粗**` 不得退化成斜体吞掉第二个 *）
        if (c == '*' || c == '_')
            && i + 1 < n
            && chars[i + 1] != c
            && !chars[i + 1].is_whitespace()
        {
            let word_inner = c == '_' && i > 0 && chars[i - 1].is_alphanumeric();
            if !word_inner {
                if let Some((inner, end)) = scan_delim(chars, i + 1, c, false) {
                    // _ 斜体闭合后不得紧跟字母数字（词内不触发）
                    let after_ok = c == '*'
                        || end >= n
                        || !chars[end].is_alphanumeric();
                    if after_ok {
                        flush(&mut buf, &mut out);
                        out.push(InlineSeg::Em(parse_inline_chars(&inner, ctx)));
                        i = end;
                        continue;
                    }
                }
            }
        }
        buf.push(c);
        i += 1;
    }
    flush(&mut buf, &mut out);
    out
}

/// 找等长反引号闭合串，返回 (内容字符, 闭合串之后下标)。
fn find_code_close(
    chars: &[char],
    from: usize,
    run: usize,
) -> Option<(Vec<char>, usize)> {
    let n = chars.len();
    let mut j = from;
    while j < n {
        if chars[j] == '`' {
            let mut r = 0;
            while j + r < n && chars[j + r] == '`' {
                r += 1;
            }
            if r == run {
                return Some((chars[from..j].to_vec(), j + r));
            }
            j += r;
        } else {
            j += 1;
        }
    }
    None
}

/// marked 代码段内容规范化：换行变空格；首尾各一个空格且
/// 内容非全空格时各剥一个。
fn code_content(raw: &[char]) -> String {
    let mut s: String = raw
        .iter()
        .map(|c| if *c == '\n' { ' ' } else { *c })
        .collect();
    if s.len() > 1 && s.starts_with(' ') && s.ends_with(' ') && !s.trim().is_empty() {
        s.remove(0);
        s.pop();
    }
    s
}

/// 在 chars[start]=='[' 且 chars[start+1]=='[' 处解析
/// [[目标|标签]]（规则同 parse_wiki 注释），返回
/// (target, label, 结束下标)。
fn parse_wiki_at(chars: &[char], start: usize) -> Option<(String, String, usize)> {
    let n = chars.len();
    let mut j = start + 2;
    let mut close = None;
    while j < n {
        if chars[j] == '\n' || chars[j] == '\r' {
            return None;
        }
        if chars[j] == ']' {
            if j + 1 < n && chars[j + 1] == ']' {
                close = Some(j);
            }
            break;
        }
        j += 1;
    }
    let close = close?;
    let inner: String = chars[start + 2..close].iter().collect();
    let mut parts = inner.splitn(2, '|');
    let target_raw = parts.next().unwrap_or("");
    let label_raw = parts.next();
    if target_raw.is_empty() {
        return None;
    }
    if let Some(l) = label_raw {
        if l.is_empty() {
            return None;
        }
    }
    let target = target_raw.trim().to_string();
    if target.is_empty() {
        return None;
    }
    let label = label_raw
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .unwrap_or(target.clone());
    Some((target, label, close + 2))
}

/// 在 chars[j..]（定界符 run 起点）找一段完整的双字符定界
/// 跨度（**…** / __…__，内容首尾非空白），返回跨度之后下标。
/// 单字符定界扫描遇到双符 run 时用它整段跳过内层粗体。
fn skip_strong_span(chars: &[char], j: usize, delim: char) -> Option<usize> {
    let n = chars.len();
    let mut run = 0;
    while j + run < n && chars[j + run] == delim {
        run += 1;
    }
    if run < 2 {
        return None;
    }
    let start = j + run;
    let mut k = start;
    while k < n {
        if chars[k] == delim {
            let mut r2 = 0;
            while k + r2 < n && chars[k + r2] == delim {
                r2 += 1;
            }
            if r2 >= 2
                && k > start
                && !chars[start].is_whitespace()
                && !chars[k - 1].is_whitespace()
            {
                return Some(k + r2);
            }
            k += r2;
        } else {
            k += 1;
        }
    }
    None
}

/// 找粗/斜体闭合定界：double=true 找双字符定界，否则单字符。
/// 按 marked（CommonMark 定界栈）的近似口径：开定界后首字符
/// 与闭定界前末字符都不得是空白（`** 粗 **`、`* 3 *` 在原版
/// 保持字面）；闭合候选若内容以空白结尾则跳过继续找；同定
/// 界的嵌套开定界（前空白、后非空白）计深度，深度归零处才
/// 是外层闭合（`*a *b* c*`、`**a **b** c**` 的嵌套形）。
/// 单字符扫描遇到双符 run 时，若其构成完整粗体跨度则整段
/// 跳过（`*斜 **粗** 斜*`）。
fn scan_delim(
    chars: &[char],
    from: usize,
    delim: char,
    double: bool,
) -> Option<(Vec<char>, usize)> {
    let n = chars.len();
    let unit = if double { 2 } else { 1 };
    let mut depth = 1usize;
    let mut j = from;
    while j < n {
        if chars[j] != delim {
            j += 1;
            continue;
        }
        let mut run = 0;
        while j + run < n && chars[j + run] == delim {
            run += 1;
        }
        if !double && run >= 2 {
            if let Some(after) = skip_strong_span(chars, j, delim) {
                j = after;
                continue;
            }
        }
        if double && run < 2 {
            j += run;
            continue;
        }
        // 闭合候选：定界前一字符（即内容末字符）非空白
        let can_close = j > from && !chars[j - 1].is_whitespace();
        if can_close {
            if depth == 1 {
                return Some((chars[from..j].to_vec(), j + unit));
            }
            depth -= 1;
            j += run;
            continue;
        }
        // 不能闭合：若是嵌套开定界（前空白、run 后非空白）计深度
        let after = j + run;
        let can_open = after < n
            && !chars[after].is_whitespace()
            && (j == 0 || chars[j - 1].is_whitespace());
        if can_open {
            depth += 1;
        }
        j += run;
    }
    None
}

/// 行内分段渲染：wiki 段经 WikiNav 上报导航，其余按
/// marked 元素形状输出。
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
                    del { key: "d{i}", class: "mynote-strikethrough", "{t}" }
                },
                InlineSeg::Highlight(t) => rsx! {
                    span { key: "h{i}", class: "mynote-highlight", "{t}" }
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
                            class: "mynote-wiki-link",
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
                mynote_core::render_mathml(tex, display).map_err(|e| e.to_string())
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
        if looks_like_markdown(text) {
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

// ===== 块级 Markdown 解析（marked 子集） =====
//
// 把一个 md 源段落的全文解析为块序列：混合结构段（标题+正文、
// 正文+列表、setext）按 marked 的块语法逐行切分，不再要求整段
// 同型（M3）。行内文本在切分时即经 parse_inlines 解析为分段。

#[derive(Clone, PartialEq)]
enum MdBlock {
    Code {
        lang: Option<String>,
        code: String,
    },
    Heading {
        level: u8,
        segs: Vec<InlineSeg>,
    },
    Para {
        segs: Vec<InlineSeg>,
    },
    /// 独占段落的块级公式（$$…$$）：居中成块渲染。
    Math {
        tex: String,
    },
    Quote {
        blocks: Vec<MdBlock>,
    },
    Callout {
        style: &'static str,
        title: String,
        folding: Option<char>,
        blocks: Vec<MdBlock>,
    },
    List {
        ordered: bool,
        start: u64,
        items: Vec<MdItem>,
    },
    Table {
        head: Vec<Vec<InlineSeg>>,
        align: Vec<u8>,
        rows: Vec<Vec<Vec<InlineSeg>>>,
    },
    Divider,
    Footnotes {
        items: Vec<FnItem>,
    },
}

#[derive(Clone, PartialEq)]
struct MdItem {
    checked: Option<bool>,
    segs: Vec<InlineSeg>,
    /// 缩进子块（嵌套列表等）：原版 marked 把 `- 父项` 下
    /// 缩进的 `- 子项` 渲染为 li 内的嵌套 ul/ol（预言机实测），
    /// 旧实现把它拍平成同级项。
    sub: Vec<MdBlock>,
}

#[derive(Clone, PartialEq)]
struct FnItem {
    id: String,
    ref_ids: Vec<String>,
    blocks: Vec<MdBlock>,
}

#[derive(Clone, PartialEq)]
enum Marker {
    Bullet(char),
    Ordered(u64, char),
}

fn leading_spaces(line: &str) -> usize {
    line.chars().take_while(|c| *c == ' ').count()
}

/// C-28 缩进代码判定：≥4 空格或行首 tab（marked 按 4 列宽
/// 折算 tab）。
fn is_code_indented(line: &str) -> bool {
    leading_spaces(line) >= 4 || line.starts_with('\t')
}

/// 剥一层代码缩进：4 空格或 1 tab。
fn dedent4(line: &str) -> String {
    if let Some(r) = line.strip_prefix("    ") {
        r.to_string()
    } else if let Some(r) = line.strip_prefix('\t') {
        r.to_string()
    } else {
        line.to_string()
    }
}

/// 围栏起始行（≤3 空格 + 3 个以上 ` 或 ~），返回 (字符, 长度, info)。
fn fence_start(line: &str) -> Option<(char, usize, String)> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let rest = &line[sp..];
    let fc = rest.chars().next()?;
    if fc != '`' && fc != '~' {
        return None;
    }
    let len = rest.chars().take_while(|c| *c == fc).count();
    if len < 3 {
        return None;
    }
    let info = rest[len..].trim().to_string();
    if fc == '`' && info.contains('`') {
        return None;
    }
    Some((fc, len, info))
}

fn fence_close(line: &str, fc: char, open_len: usize) -> bool {
    let sp = leading_spaces(line);
    if sp > 3 {
        return false;
    }
    let rest = line[sp..].trim_end();
    !rest.is_empty() && rest.len() >= open_len && rest.chars().all(|c| c == fc)
}

/// ATX 标题行，返回 (级别, 文本)。闭合 # 序列按 marked 剥除。
fn atx_heading(line: &str) -> Option<(u8, String)> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let rest = &line[sp..];
    let hashes = rest.chars().take_while(|c| *c == '#').count();
    if hashes == 0 || hashes > 6 {
        return None;
    }
    let after = &rest[hashes..];
    if after.is_empty() {
        return Some((hashes as u8, String::new()));
    }
    if !after.starts_with(' ') && !after.starts_with('\t') {
        return None;
    }
    let mut text = after.trim().to_string();
    if text.ends_with('#') {
        let stripped = text.trim_end_matches('#');
        if stripped.len() < text.len()
            && (stripped.is_empty() || stripped.ends_with(' ') || stripped.ends_with('\t'))
        {
            text = stripped.trim().to_string();
        }
    }
    Some((hashes as u8, text))
}

fn setext_level(line: &str) -> Option<u8> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let t = line[sp..].trim();
    if t.is_empty() {
        return None;
    }
    if t.chars().all(|c| c == '=') {
        Some(1)
    } else if t.chars().all(|c| c == '-') {
        Some(2)
    } else {
        None
    }
}

fn is_thematic_break(line: &str) -> bool {
    let sp = leading_spaces(line);
    if sp > 3 {
        return false;
    }
    let rest: String = line[sp..]
        .chars()
        .filter(|c| *c != ' ' && *c != '\t')
        .collect();
    if rest.len() < 3 {
        return false;
    }
    let fc = rest.chars().next().unwrap();
    matches!(fc, '-' | '*' | '_') && rest.chars().all(|c| c == fc)
}

/// 引用行剥前缀（≤3 空格 + > + 可选一空格），非引用行返回 None。
fn quote_strip(line: &str) -> Option<String> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let r = line[sp..].strip_prefix('>')?;
    Some(r.strip_prefix(' ').unwrap_or(r).to_string())
}

/// 列表标记行，返回 (标记, 项文本)。标记后须有空格/制表符。
fn list_marker(line: &str) -> Option<(Marker, String)> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let rest = &line[sp..];
    let c0 = rest.chars().next()?;
    if matches!(c0, '-' | '*' | '+') {
        let after = &rest[1..];
        if after.starts_with(' ') || after.starts_with('\t') {
            return Some((Marker::Bullet(c0), after[1..].to_string()));
        }
        return None;
    }
    if c0.is_ascii_digit() {
        let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
        if digits.len() > 9 {
            return None;
        }
        let after_digits = &rest[digits.len()..];
        let delim = after_digits.chars().next()?;
        if delim != '.' && delim != ')' {
            return None;
        }
        let after = &after_digits[1..];
        if after.starts_with(' ') || after.starts_with('\t') {
            let num: u64 = digits.parse().ok()?;
            return Some((Marker::Ordered(num, delim), after[1..].to_string()));
        }
    }
    None
}

/// 该行是否打断段落收集（围栏/引用/标题/分隔线/列表；
/// 有序列表仅 1. 可打断，marked 口径）。
fn interrupts_paragraph(line: &str) -> bool {
    if fence_start(line).is_some()
        || quote_strip(line).is_some()
        || atx_heading(line).is_some()
        || is_thematic_break(line)
    {
        return true;
    }
    match list_marker(line) {
        Some((Marker::Bullet(_), _)) => true,
        Some((Marker::Ordered(num, _), _)) => num == 1,
        None => false,
    }
}

/// 表头行 + 分隔行 → 对齐表（列数须相等，marked 口径）。
fn table_aligns(header: &str, sep: &str) -> Option<Vec<u8>> {
    let head = split_table_row(header);
    let cells = split_table_row(sep);
    if head.is_empty() || head.len() != cells.len() {
        return None;
    }
    let mut aligns = Vec::new();
    for c in &cells {
        let c = c.trim();
        if c.is_empty()
            || !c.chars().all(|ch| ch == '-' || ch == ':')
            || !c.contains('-')
        {
            return None;
        }
        aligns.push(if c.starts_with(':') && c.ends_with(':') {
            1
        } else if c.ends_with(':') {
            2
        } else {
            0
        });
    }
    Some(aligns)
}

/// Callout 首行头解析：[!TYPE] + 可选折叠符 + 可选标题
/// （原版 preprocessCallouts 正则口径；无空格的尾巴不作标题）。
fn callout_header(line: &str) -> Option<(String, String, Option<char>, String)> {
    let rest = line.strip_prefix("[!")?;
    let end = rest.find(']')?;
    let raw_type = &rest[..end];
    if raw_type.is_empty()
        || !raw_type
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return None;
    }
    let mut tail = &rest[end + 1..];
    let mut folding = None;
    if tail.starts_with('+') || tail.starts_with('-') {
        folding = Some(tail.chars().next().unwrap());
        tail = &tail[1..];
    }
    let custom = if tail.is_empty() {
        String::new()
    } else if tail.starts_with(' ') || tail.starts_with('\t') {
        tail.trim().to_string()
    } else {
        String::new()
    };
    // C-21：除小写形外同时返回类型原文，未知类型标题兜底用
    Some((raw_type.to_lowercase(), raw_type.to_string(), folding, custom))
}

fn md_quote_block(inner: Vec<String>, ctx: &mut InlineCtx) -> MdBlock {
    if let Some(first) = inner.first() {
        if let Some((raw, raw_orig, folding, custom)) = callout_header(first) {
            let (style, default_title) = callout_style_title(&raw);
            // C-21：未知类型标题回退类型原文（保留大小写）
            let title = if !custom.is_empty() {
                custom
            } else if let Some(dt) = default_title {
                dt.to_string()
            } else {
                raw_orig
            };
            let body_text = inner[1..].join("\n");
            let blocks = if body_text.trim().is_empty() {
                Vec::new()
            } else {
                let blines: Vec<&str> = body_text.split('\n').collect();
                parse_md_blocks(&blines, ctx)
            };
            return MdBlock::Callout {
                style,
                title,
                folding,
                blocks,
            };
        }
    }
    let text = inner.join("\n");
    let lines: Vec<&str> = text.split('\n').collect();
    MdBlock::Quote {
        blocks: parse_md_blocks(&lines, ctx),
    }
}

/// 任务项拆分：[ ] / [x] / [X] 前缀（后接空格或整项仅此标记）。
fn task_split(text: &str) -> (Option<bool>, String) {
    for (pat, val) in [
        ("[ ] ", false),
        ("[x] ", true),
        ("[X] ", true),
    ] {
        if let Some(rest) = text.strip_prefix(pat) {
            return (Some(val), rest.to_string());
        }
    }
    for (pat, val) in [("[ ]", false), ("[x]", true), ("[X]", true)] {
        if text == pat {
            return (Some(val), String::new());
        }
    }
    (None, text.to_string())
}

fn parse_md_list(
    lines: &[&str],
    start: usize,
    first: &Marker,
    ctx: &mut InlineCtx,
) -> (MdBlock, usize) {
    let ordered = matches!(first, Marker::Ordered(..));
    let start_num = match first {
        Marker::Ordered(num, _) => *num,
        _ => 1,
    };
    let same_kind = |m: &Marker| -> bool {
        match (first, m) {
            (Marker::Bullet(a), Marker::Bullet(b)) => a == b,
            (Marker::Ordered(_, a), Marker::Ordered(_, b)) => a == b,
            _ => false,
        }
    };
    let mut items: Vec<MdItem> = Vec::new();
    let mut i = start;
    while i < lines.len() {
        match list_marker(lines[i]) {
            Some((m, content)) if same_kind(&m) => {
                let mut text = content;
                let mut sub: Vec<MdBlock> = Vec::new();
                let mut j = i + 1;
                while j < lines.len() {
                    let l = lines[j];
                    if l.trim().is_empty() {
                        break;
                    }
                    let indented = l.starts_with("  ") || l.starts_with('\t');
                    if !indented {
                        break;
                    }
                    let stripped = l.trim_start();
                    if list_marker(stripped).is_some() {
                        // 缩进列表行 = 嵌套子列表：连续的缩进
                        // 行整体去缩进后递归解析（marked 口径）。
                        let mut sublines: Vec<&str> = Vec::new();
                        while j < lines.len() {
                            let sl = lines[j];
                            if sl.trim().is_empty()
                                || !(sl.starts_with("  ") || sl.starts_with('\t'))
                            {
                                break;
                            }
                            sublines.push(sl.trim_start());
                            j += 1;
                        }
                        sub.extend(parse_md_blocks(&sublines, ctx));
                    } else {
                        text.push('\n');
                        text.push_str(stripped);
                        j += 1;
                    }
                }
                let (checked, item_text) = task_split(&text);
                items.push(MdItem {
                    checked,
                    segs: parse_inlines(&item_text, ctx),
                    sub,
                });
                i = j;
            }
            _ => break,
        }
    }
    (
        MdBlock::List {
            ordered,
            start: start_num,
            items,
        },
        i,
    )
}

fn parse_md_blocks(lines: &[&str], ctx: &mut InlineCtx) -> Vec<MdBlock> {
    let n = lines.len();
    let mut blocks: Vec<MdBlock> = Vec::new();
    let mut i = 0;
    while i < n {
        let line = lines[i];
        if line.trim().is_empty() {
            i += 1;
            continue;
        }
        // C-28 缩进代码块：≥4 空格（或 1 tab）缩进的连续行
        // （marked 口径：缩进代码不能中断段落，故仅块首判
        // 定；段内缩进行由段落收集作续行）。空行可夹在块
        // 内，尾部空行裁掉；每行剥 4 空格 / 1 tab。
        if is_code_indented(line) {
            let mut code_lines: Vec<String> = Vec::new();
            while i < n {
                let l = lines[i];
                if l.trim().is_empty() {
                    code_lines.push(String::new());
                    i += 1;
                    continue;
                }
                if is_code_indented(l) {
                    code_lines.push(dedent4(l));
                    i += 1;
                    continue;
                }
                break;
            }
            while code_lines.last().is_some_and(|s| s.is_empty()) {
                code_lines.pop();
            }
            if !code_lines.is_empty() {
                blocks.push(MdBlock::Code {
                    lang: None,
                    code: code_lines.join("\n"),
                });
                continue;
            }
        }
        // 围栏代码（闭合可缺省，未闭合取到段尾）
        if let Some((fc, flen, info)) = fence_start(line) {
            let mut j = i + 1;
            let mut code_lines: Vec<&str> = Vec::new();
            while j < n {
                if fence_close(lines[j], fc, flen) {
                    break;
                }
                code_lines.push(lines[j]);
                j += 1;
            }
            let lang = info
                .split_whitespace()
                .next()
                .map(|s| s.to_string())
                .filter(|s| !s.is_empty());
            blocks.push(MdBlock::Code {
                lang,
                code: code_lines.join("\n"),
            });
            i = if j < n { j + 1 } else { j };
            continue;
        }
        // 引用 / Callout（含懒续行）
        if quote_strip(line).is_some() {
            let mut inner: Vec<String> = Vec::new();
            let mut j = i;
            while j < n {
                if let Some(s) = quote_strip(lines[j]) {
                    inner.push(s);
                    j += 1;
                } else if !lines[j].trim().is_empty()
                    && !inner
                        .last()
                        .map(|s| s.trim().is_empty())
                        .unwrap_or(true)
                    && !interrupts_paragraph(lines[j])
                {
                    inner.push(lines[j].to_string());
                    j += 1;
                } else {
                    break;
                }
            }
            blocks.push(md_quote_block(inner, ctx));
            i = j;
            continue;
        }
        // ATX 标题
        if let Some((level, text)) = atx_heading(line) {
            blocks.push(MdBlock::Heading {
                level,
                segs: parse_inlines(&text, ctx),
            });
            i += 1;
            continue;
        }
        // 表格
        if line.contains('|') && i + 1 < n {
            if let Some(align) = table_aligns(line, lines[i + 1]) {
                let head_cells = split_table_row(line);
                let width = head_cells.len();
                let head: Vec<Vec<InlineSeg>> = head_cells
                    .iter()
                    .map(|c| parse_inlines(c.trim(), ctx))
                    .collect();
                let mut rows: Vec<Vec<Vec<InlineSeg>>> = Vec::new();
                let mut j = i + 2;
                while j < n && !lines[j].trim().is_empty() {
                    let mut cells: Vec<Vec<InlineSeg>> = split_table_row(lines[j])
                        .iter()
                        .map(|c| parse_inlines(c.trim(), ctx))
                        .collect();
                    cells.truncate(width);
                    while cells.len() < width {
                        cells.push(Vec::new());
                    }
                    rows.push(cells);
                    j += 1;
                }
                blocks.push(MdBlock::Table { head, align, rows });
                i = j;
                continue;
            }
        }
        // 分隔线
        if is_thematic_break(line) {
            blocks.push(MdBlock::Divider);
            i += 1;
            continue;
        }
        // 列表
        if let Some((marker, _)) = list_marker(line) {
            let (list, j) = parse_md_list(lines, i, &marker, ctx);
            blocks.push(list);
            i = j;
            continue;
        }
        // 段落收集（setext 下划线行在此吸收为标题）
        let mut para_lines: Vec<&str> = vec![line];
        let mut setext: Option<u8> = None;
        let mut j = i + 1;
        while j < n {
            let l = lines[j];
            if l.trim().is_empty() {
                break;
            }
            if let Some(lv) = setext_level(l) {
                setext = Some(lv);
                j += 1;
                break;
            }
            if interrupts_paragraph(l) {
                break;
            }
            if l.contains('|') && j + 1 < n && table_aligns(l, lines[j + 1]).is_some()
            {
                break;
            }
            para_lines.push(l);
            j += 1;
        }
        let text = para_lines.join("\n");
        match setext {
            Some(lv) => blocks.push(MdBlock::Heading {
                level: lv,
                segs: parse_inlines(&text, ctx),
            }),
            None => {
                // 独占段落的块级公式 → Math 块（居中成块）。
                let trimmed = text.trim();
                match mynote_core::split_math(trimmed).as_slice() {
                    [mynote_core::MathSegment::Math { tex, display: true }] => {
                        blocks.push(MdBlock::Math { tex: tex.clone() });
                    }
                    _ => blocks.push(MdBlock::Para {
                        segs: parse_inlines(&text, ctx),
                    }),
                }
            }
        }
        i = j;
    }
    blocks
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
/// thread_local）。真解析在本函数 miss 时走 uncached 本体，
/// 其 C-28 计数副作用只在 miss 时发生——计数本就由
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
    let blocks = parse_md_document_uncached(text);
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

fn parse_md_document_uncached(text: &str) -> Vec<MdBlock> {
    // 批 11 MD-P1 量测：真解析次数/耗时/字节落 MD_PERF。
    let t0 = md_now_ms();
    let (kept, defs) = extract_footnotes(text);
    // C-28：链接引用定义在脚注定义抽走后抽取（定义行不渲染）
    let (kept, link_defs) = extract_link_defs(&kept);
    let mut ctx = InlineCtx::empty();
    for (idx, d) in defs.iter().enumerate() {
        ctx.def_map.insert(d.label.to_lowercase(), idx);
    }
    ctx.defs = defs;
    for (label, href) in link_defs {
        ctx.link_defs.insert(label, href);
    }
    let lines: Vec<&str> = kept.split('\n').collect();
    let mut blocks = parse_md_blocks(&lines, &mut ctx);
    // C-28 新解析面计数先落 thread_local，由 MdPreview 在组
    // 件层取走落 Diag（解析层直调 diag 在非 wasm 目标下不
    // 可用，且与既有 md_feature_flags 的落点口径一致）。
    if ctx.ref_links_used > 0 || ctx.html_tags_used > 0 {
        MD_PARSE_DIAG.with(|c| {
            let (r, h) = c.get();
            c.set((r + ctx.ref_links_used, h + ctx.html_tags_used));
        });
    }
    let mut fn_items: Vec<FnItem> = Vec::new();
    let mut unused: Vec<String> = Vec::new();
    for (idx, def) in ctx.defs.iter().enumerate() {
        match ctx.ref_ids.get(&idx) {
            Some(ref_ids) => {
                let mut ectx = InlineCtx::empty();
                let blines: Vec<&str> = def.body.split('\n').collect();
                let body_blocks = if def.body.trim().is_empty() {
                    Vec::new()
                } else {
                    parse_md_blocks(&blines, &mut ectx)
                };
                fn_items.push(FnItem {
                    id: def.id.clone(),
                    ref_ids: ref_ids.clone(),
                    blocks: body_blocks,
                });
            }
            None => {
                // marked 链接定义吞行口径：不渲染（组件层记 RENDER 日志）
                let first_body = def.body.lines().next().unwrap_or("");
                if first_body.chars().any(|c| c.is_whitespace()) {
                    unused.push(def.original.clone());
                }
            }
        }
    }
    if !fn_items.is_empty() {
        blocks.push(MdBlock::Footnotes { items: fn_items });
    }
    for u in unused {
        blocks.push(MdBlock::Para {
            segs: vec![InlineSeg::Text(u)],
        });
    }
    md_perf_record_parse(md_now_ms() - t0, text.len(), false);
    blocks
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
/// span.mynote-highlight，不是 mark）；含块级结构时才是
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
pub fn md_is_block_preview(text: &str) -> bool {
    let blocks = parse_md_document(text);
    !(blocks.len() == 1 && matches!(blocks[0], MdBlock::Para { .. }))
}

// ===== Markdown 渲染回归测试（第八批车道 A） =====
// 期望值全部来自原版预言机（vendor/marked v15 + markdown-
// bridge，breaks:true/gfm:true）对同一语料的实测输出，
// 2026-11-22 以无头 Node 跑原版 editor.md.js 得到。
#[cfg(test)]
mod md_render_tests {
    use super::*;

    fn seg_dump(segs: &[InlineSeg]) -> String {
        segs.iter()
            .map(|s| match s {
                InlineSeg::Text(t) => format!("T({t:?})"),
                InlineSeg::Code(t) => format!("C({t:?})"),
                InlineSeg::Strong(c) => format!("B[{}]", seg_dump(c)),
                InlineSeg::Em(c) => format!("I[{}]", seg_dump(c)),
                InlineSeg::Underline(c) => format!("U[{}]", seg_dump(c)),
                InlineSeg::Del(t) => format!("D({t:?})"),
                InlineSeg::Highlight(t) => format!("H({t:?})"),
                InlineSeg::Sup(t) => format!("Sup({t:?})"),
                InlineSeg::Sub(t) => format!("Sub({t:?})"),
                InlineSeg::Link { href, children } => {
                    format!("A({href})[{}]", seg_dump(children))
                }
                InlineSeg::Image { src, alt } => format!("Img({src},{alt:?})"),
                InlineSeg::Wiki { target, label } => format!("W({target}|{label})"),
                InlineSeg::FootRef { id, ref_id, number } => {
                    format!("Fn({id},{ref_id},{number})")
                }
                InlineSeg::Math { tex, display } => format!("M({tex},{display})"),
                InlineSeg::Break => "BR".to_string(),
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn block_dump(blocks: &[MdBlock]) -> String {
        blocks
            .iter()
            .map(|b| match b {
                MdBlock::Code { lang, code } => {
                    format!("Code({})[{code:?}]", lang.as_deref().unwrap_or("-"))
                }
                MdBlock::Heading { level, segs } => {
                    format!("H{level}[{}]", seg_dump(segs))
                }
                MdBlock::Para { segs } => format!("P[{}]", seg_dump(segs)),
                MdBlock::Math { tex } => format!("MathBlk({tex})"),
                MdBlock::Quote { blocks } => {
                    format!("Q{{{}}}", block_dump(blocks))
                }
                MdBlock::Callout {
                    style,
                    title,
                    folding,
                    blocks,
                } => format!(
                    "Callout({style},{title:?},{}){{{}}}",
                    folding
                        .map(|c| format!("Some({c})"))
                        .unwrap_or_else(|| "None".into()),
                    block_dump(blocks)
                ),
                MdBlock::List {
                    ordered,
                    start,
                    items,
                } => {
                    let its: Vec<String> = items
                        .iter()
                        .map(|it| {
                            format!(
                                "({})[{}]sub{{{}}}",
                                it.checked
                                    .map(|c| c.to_string())
                                    .unwrap_or_else(|| "-".into()),
                                seg_dump(&it.segs),
                                block_dump(&it.sub)
                            )
                        })
                        .collect();
                    format!(
                        "List({},{})[{}]",
                        if *ordered { "ol" } else { "ul" },
                        start,
                        its.join(" ")
                    )
                }
                MdBlock::Table { head, align, rows } => {
                    let h: Vec<String> = head.iter().map(|c| seg_dump(c)).collect();
                    let r: Vec<String> = rows
                        .iter()
                        .map(|row| {
                            row.iter()
                                .map(|c| seg_dump(c))
                                .collect::<Vec<_>>()
                                .join("/")
                        })
                        .collect();
                    format!("Tbl({align:?})[{}]{{{}}}", h.join("/"), r.join(";"))
                }
                MdBlock::Divider => "HR".to_string(),
                MdBlock::Footnotes { items } => {
                    let its: Vec<String> = items
                        .iter()
                        .map(|it| {
                            format!(
                                "FnItem({},{:?}){{{}}}",
                                it.id,
                                it.ref_ids,
                                block_dump(&it.blocks)
                            )
                        })
                        .collect();
                    format!("Fns[{}]", its.join(" "))
                }
            })
            .collect::<Vec<_>>()
            .join(" | ")
    }

    fn dump(text: &str) -> String {
        block_dump(&parse_md_document(text))
    }

    fn gate(text: &str) -> &'static str {
        match md_classify(text) {
            Some(MdKind::Code(_)) => "Code",
            Some(MdKind::Rich(_)) => "Rich",
            Some(MdKind::Callout { .. }) => "Callout",
            Some(MdKind::List { .. }) => "List",
            Some(MdKind::Table { .. }) => "Table",
            Some(MdKind::Heading { .. }) => "Heading",
            Some(MdKind::Quote(_)) => "Quote",
            Some(MdKind::Divider) => "Divider",
            None => "None",
        }
    }

    #[test]
    fn m1_inline_and_nesting() {
        assert_eq!(
            dump("这是 **粗体** 和 *斜体* 与 ~~删除~~ 和 `代码` 以及 [外链](https://example.com) 混合"),
            "P[T(\"这是 \") B[T(\"粗体\")] T(\" 和 \") I[T(\"斜体\")] T(\" 与 \") D(\"删除\") T(\" 和 \") C(\"代码\") T(\" 以及 \") A(https://example.com)[T(\"外链\")] T(\" 混合\")]"
        );
        // 嵌套强调：原版 em>strong / strong 内 em / 同定界嵌套
        assert_eq!(dump("*斜 **粗** 斜*"), "P[I[T(\"斜 \") B[T(\"粗\")] T(\" 斜\")]]");
        assert_eq!(dump("**粗 *斜* 粗**"), "P[B[T(\"粗 \") I[T(\"斜\")] T(\" 粗\")]]");
        assert_eq!(dump("*a *b* c* 嵌套"), "P[I[T(\"a \") I[T(\"b\")] T(\" c\")] T(\" 嵌套\")]");
        assert_eq!(dump("**a **b** c** 嵌套"), "P[B[T(\"a \") B[T(\"b\")] T(\" c\")] T(\" 嵌套\")]");
        // 三连定界 = em 包 strong（* 与 _ 皆然）
        assert_eq!(dump("***粗斜*** 文字"), "P[I[B[T(\"粗斜\")]] T(\" 文字\")]");
        assert_eq!(
            dump("***粗斜*** 与 ___粗斜___ 尾"),
            "P[I[B[T(\"粗斜\")]] T(\" 与 \") I[B[T(\"粗斜\")]] T(\" 尾\")]"
        );
        // flanking：定界贴空白即字面（乘法星号、** 粗 **）
        assert_eq!(dump("计算 2 * 3 * 4 结果"), "P[T(\"计算 2 * 3 * 4 结果\")]");
        assert_eq!(dump("a ** 粗 ** b"), "P[T(\"a ** 粗 ** b\")]");
        assert_eq!(dump("a *b * c"), "P[T(\"a *b * c\")]");
        assert_eq!(
            dump("** 粗** 与 **粗 ** 混 **粗**"),
            "P[T(\"** 粗** 与 **粗 ** 混 \") B[T(\"粗\")]]"
        );
        assert_eq!(dump("*a * b*"), "P[I[T(\"a * b\")]]");
        // 软换行 = <br>（marked breaks:true）
        assert_eq!(
            dump("第一行 **粗**\n第二行普通"),
            "P[T(\"第一行 \") B[T(\"粗\")] BR T(\"第二行普通\")]"
        );
    }

    #[test]
    fn m1_autolink() {
        assert_eq!(
            dump("看 https://example.com/path?q=1 这个链接 **粗**"),
            "P[T(\"看 \") A(https://example.com/path?q=1)[T(\"https://example.com/path?q=1\")] T(\" 这个链接 \") B[T(\"粗\")]]"
        );
        assert_eq!(
            dump("- 访问 https://example.com 详情"),
            "List(ul,1)[(-)[T(\"访问 \") A(https://example.com)[T(\"https://example.com\")] T(\" 详情\")]sub{}]"
        );
        assert_eq!(
            dump("访问 www.example.com/path 看看 **粗**"),
            "P[T(\"访问 \") A(http://www.example.com/path)[T(\"www.example.com/path\")] T(\" 看看 \") B[T(\"粗\")]]"
        );
        assert_eq!(
            dump("联系 me@example.com 邮箱 **粗**"),
            "P[T(\"联系 \") A(mailto:me@example.com)[T(\"me@example.com\")] T(\" 邮箱 \") B[T(\"粗\")]]"
        );
        assert_eq!(
            dump("(https://example.com/a) 尾 **粗**"),
            "P[T(\"(\") A(https://example.com/a)[T(\"https://example.com/a\")] T(\") 尾 \") B[T(\"粗\")]]"
        );
        // a@b 无点不成邮箱；链接文本内不套 autolink
        assert_eq!(dump("价格 a@b 不是邮箱 **粗**"), "P[T(\"价格 a@b 不是邮箱 \") B[T(\"粗\")]]");
        assert_eq!(
            dump("[https://a.com](https://b.com) 与 **粗**"),
            "P[A(https://b.com)[T(\"https://a.com\")] T(\" 与 \") B[T(\"粗\")]]"
        );
    }

    #[test]
    fn m2_inline_inside_blocks() {
        assert_eq!(
            dump("- 项 **粗** 与 `代码` 与 [链接](https://a.com)"),
            "List(ul,1)[(-)[T(\"项 \") B[T(\"粗\")] T(\" 与 \") C(\"代码\") T(\" 与 \") A(https://a.com)[T(\"链接\")]]sub{}]"
        );
        assert_eq!(
            dump("| 名 | 值 |\n| --- | ---: |\n| **粗** | `码` |"),
            "Tbl([0, 2])[T(\"名\")/T(\"值\")]{B[T(\"粗\")]/C(\"码\")}"
        );
        assert_eq!(
            dump("> [!warning] 注意\n> - 项一\n> - 项二"),
            "Callout(warning,\"注意\",None){List(ul,1)[(-)[T(\"项一\")]sub{} (-)[T(\"项二\")]sub{}]}"
        );
        assert_eq!(
            dump("# 标题 **粗** `码`"),
            "H1[T(\"标题 \") B[T(\"粗\")] T(\" \") C(\"码\")]"
        );
        // 表格转义竖线不成多格
        assert_eq!(
            dump("| a \\| b | c |\n| --- | --- |\n| 1 | 2 |"),
            "Tbl([0, 0])[T(\"a | b\")/T(\"c\")]{T(\"1\")/T(\"2\")}"
        );
    }

    #[test]
    fn m3_mixed_structures() {
        assert_eq!(dump("# 标题行\n后面一行正文"), "H1[T(\"标题行\")] | P[T(\"后面一行正文\")]");
        assert_eq!(
            dump("前一行\n- 列表项\n- 第二项"),
            "P[T(\"前一行\")] | List(ul,1)[(-)[T(\"列表项\")]sub{} (-)[T(\"第二项\")]sub{}]"
        );
        assert_eq!(dump("文字上\n---\n文字下"), "H2[T(\"文字上\")] | P[T(\"文字下\")]");
        assert_eq!(dump("> 引用首行\n懒续行"), "Q{P[T(\"引用首行\") BR T(\"懒续行\")]}");
        assert_eq!(
            dump("> 第一段\n>\n> 第二段"),
            "Q{P[T(\"第一段\")] | P[T(\"第二段\")]}"
        );
        // 表格混排：解析层能切分（门控另测）；后随普通行按
        // marked 口径并入表格行（补空单元格）
        assert_eq!(
            dump("前文说明\n| a | b |\n| - | - |\n| 1 | 2 |\n后文行"),
            "P[T(\"前文说明\")] | Tbl([0, 0])[T(\"a\")/T(\"b\")]{T(\"1\")/T(\"2\");T(\"后文行\")/}"
        );
    }

    #[test]
    fn m4_fences() {
        assert_eq!(dump("```js\nconst a = 1;\n```"), "Code(js)[\"const a = 1;\"]");
        assert_eq!(dump("~~~js\nconst a = 1;\n~~~"), "Code(js)[\"const a = 1;\"]");
        assert_eq!(dump("```\n未闭合代码"), "Code(-)[\"未闭合代码\"]");
        assert_eq!(dump("````\na```b\n````"), "Code(-)[\"a```b\"]");
    }

    #[test]
    fn m5_callout_folding() {
        assert_eq!(
            dump("> [!TIP]-\n> 折叠内容"),
            "Callout(tip,\"提示\",Some(-)){P[T(\"折叠内容\")]}"
        );
        assert_eq!(
            dump("> [!TIP]+\n> 展开内容"),
            "Callout(tip,\"提示\",Some(+)){P[T(\"展开内容\")]}"
        );
        assert_eq!(
            dump("> [!note] 我的标题\n> 正文 **粗**"),
            "Callout(note,\"我的标题\",None){P[T(\"正文 \") B[T(\"粗\")]]}"
        );
    }

    #[test]
    fn m6_lists() {
        assert_eq!(
            dump("- [ ] 未完任务\n- [x] 已完任务"),
            "List(ul,1)[(false)[T(\"未完任务\")]sub{} (true)[T(\"已完任务\")]sub{}]"
        );
        assert_eq!(
            dump("2. 第二项\n3. 第三项"),
            "List(ol,2)[(-)[T(\"第二项\")]sub{} (-)[T(\"第三项\")]sub{}]"
        );
        assert_eq!(
            dump("- 无序一\n- 无序二\n\n1. 有序一"),
            "List(ul,1)[(-)[T(\"无序一\")]sub{} (-)[T(\"无序二\")]sub{}] | List(ol,1)[(-)[T(\"有序一\")]sub{}]"
        );
        // 嵌套列表进父项 sub（原版 li 内嵌 ul）
        assert_eq!(
            dump("- 父项\n  - 子项"),
            "List(ul,1)[(-)[T(\"父项\")]sub{List(ul,1)[(-)[T(\"子项\")]sub{}]}]"
        );
        // 项续行 = 项内 <br>
        assert_eq!(
            dump("- 项一\n  续行内容"),
            "List(ul,1)[(-)[T(\"项一\") BR T(\"续行内容\")]sub{}]"
        );
    }

    #[test]
    fn m7_footnotes_and_scripts() {
        assert_eq!(
            dump("正文带脚注[^1] 结尾\n\n[^1]: 脚注内容 **粗**"),
            "P[T(\"正文带脚注\") Fn(fn-1,fn-1-ref-1,1) T(\" 结尾\")] | Fns[FnItem(fn-1,[\"fn-1-ref-1\"]){P[T(\"脚注内容 \") B[T(\"粗\")]]}]"
        );
        assert_eq!(
            dump("公式 x^2^ 与水 H~2~O 及 ^(n+1)^ 和 ~(i)~ 形"),
            "P[T(\"公式 x\") Sup(\"2\") T(\" 与水 H\") Sub(\"2\") T(\"O 及 \") Sup(\"n+1\") T(\" 和 \") Sub(\"i\") T(\" 形\")]"
        );
        // 未引用定义：单 token 正文被 marked 链接定义吞行；
        // 含空白正文则字面回填
        assert_eq!(dump("正文无引用\n\n[^9]: 未用定义"), "P[T(\"正文无引用\")]");
        assert_eq!(
            dump("正文无引用\n\n[^9]: 未用 定义 内容"),
            "P[T(\"正文无引用\")] | P[T(\"[^9]: 未用 定义 内容\")]"
        );
    }

    #[test]
    fn m8_and_gate_parity() {
        // *** / ___ 独占段：原版门控不转（解析层虽出 HR）
        assert_eq!(gate("***"), "None");
        assert_eq!(gate("___"), "None");
        // --- 独占段两边都转
        assert_eq!(gate("---"), "Divider");
        // setext === 独占信号：原版门控不转
        assert_eq!(gate("标题文\n==="), "None");
        // 纯表格（单元格无行内信号）：原版门控不转
        assert_eq!(gate("| a | b |\n| - | - |\n| 1 | 2 |"), "None");
        // 单元格带信号的表格（审计 e08 形）两边都转
        assert_eq!(gate("| 列一 | 列二 |\n| --- | --- |\n| **粗** | `代码` |"), "Table");
        // 混排表格（前文无信号）：原版门控不转
        assert_eq!(gate("前文说明\n| a | b |\n| - | - |\n| 1 | 2 |\n后文行"), "None");
        // 硬换行/有序括号形：原版门控不转
        assert_eq!(gate("行一  \n行二"), "None");
        assert_eq!(gate("1) 第一\n2) 第二"), "None");
    }

    #[test]
    fn batch3_parser_additions() {
        // C-28 引用式链接：全引用 / 折叠 / 快捷 / 引用图片；
        // 定义行不渲染；未命中定义保持字面
        assert_eq!(
            dump("[点此][ex]\n\n[ex]: https://example.com"),
            "P[A(https://example.com)[T(\"点此\")]]"
        );
        assert_eq!(
            dump("[Example][]\n\n[example]: https://example.com"),
            "P[A(https://example.com)[T(\"Example\")]]"
        );
        assert_eq!(
            dump("见 [Example] 页\n\n[example]: https://example.com"),
            "P[T(\"见 \") A(https://example.com)[T(\"Example\")] T(\" 页\")]"
        );
        assert_eq!(
            dump("![图][im]\n\n[im]: https://example.com/a.png"),
            "P[Img(https://example.com/a.png,\"图\")]"
        );
        assert_eq!(dump("[无此定义][nope]"), "P[T(\"[无此定义][nope]\")]");
        // C-28 行内原始 HTML：映射 / 剥标签留子段 /
        // DROP_CONTENT 连内容丢弃
        assert_eq!(
            dump("a <b>粗</b> <u>下划</u> <span>x</span> b"),
            "P[T(\"a \") B[T(\"粗\")] T(\" \") U[T(\"下划\")] T(\" \") T(\"x\") T(\" b\")]"
        );
        assert_eq!(
            dump("前 <script>alert(1)</script> 后"),
            "P[T(\"前 \") T(\" 后\")]"
        );
        assert_eq!(
            dump("<a href=\"https://example.com\">链</a>"),
            "P[A(https://example.com)[T(\"链\")]]"
        );
        assert_eq!(
            dump("<del>删</del> <mark>亮</mark>"),
            "P[D(\"删\") T(\" \") H(\"亮\")]"
        );
        // C-28 缩进代码块（解析层 + 分类层）
        assert_eq!(
            dump("    let a = 1;\n    let b = 2;"),
            "Code(-)[\"let a = 1;\\nlet b = 2;\"]"
        );
        assert_eq!(gate("    - 不是列表"), "Code");
        // C-21 未知 Callout 类型：标题回退类型原文；
        // 已知类型 note 仍走标题表（笔记）
        assert_eq!(
            dump("> [!FOO]\n> 正文"),
            "Callout(note,\"FOO\",None){P[T(\"正文\")]}"
        );
        assert_eq!(
            dump("> [!NOTE]\n> 正文"),
            "Callout(note,\"笔记\",None){P[T(\"正文\")]}"
        );
        // C-23 失焦 guards（分类层）：极短引用 / 未闭合
        // Callout / 空围栏均不转预览
        assert_eq!(gate("> a"), "None");
        assert_eq!(gate("> [!NOTE 未闭合"), "None");
        assert_eq!(gate("```\n```"), "None");
        // C-03 标题缺省级 = 2（渲染层经 heading_level 读
        // 取，此处以分类层无关——见探针 DOM 断言）
    }

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
}
