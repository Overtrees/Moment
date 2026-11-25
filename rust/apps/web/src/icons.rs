//! 图标集（全仓 UI 图标的唯一出处）：与原版 src/utils/svg.js 的
//! SvgIcon 同源——同一套 path 数据、同样的描边参数（strokeWidth 2.5、
//! round cap/join、fill none），避免用 emoji/字符冒充图标造成视觉走样。
//! UI 层禁止再散落内联 SVG 或 emoji 图标字面：新增图标一律先进本文件。
//!
//! 命名规范：全小写 kebab-case，按域分组（见 paths() 内分段注释）；
//! 同义图标只留一个名（如来源行链接图标统一叫 link，不另立 link-2）。
//! 描边口径：paths() 表内图标统一 24×24 viewBox、stroke 由调用方传
//! （currentColor 或既有令牌）、stroke-width 主流 2.5（callout 系 2.2、
//! 备份行图标 2，见各专用函数注）。尺寸由调用方以 size 参数定，
//! 不在图标内写死第二套尺寸。
//!
//! 图标清单（名 → 用途）：
//! - 通用：pin 置顶 / del 删除（垃圾桶）/ edit 编辑 / back 返回 /
//!   check 对勾 / palette 底色 / undo 撤销 / redo 重做 /
//!   warning 三角叹号（空状态·加载失败、错误徽章警告条目）/
//!   check-circle 成功（toast）/ x-circle 失败（toast）/
//!   file-text 备忘（空库空状态）/ search 搜索（空状态、手势页）/
//!   monitor 显示器（错误徽章 RENDER 条目）/ clock 时钟（错误徽章
//!   PROMISE 条目）/ film 胶片（错误徽章 REACT 条目）。
//! - 编辑器块/格式：heading / heading2 / heading3 / paragraph /
//!   quote / todo / divider / bold / italic / highlight / codeBlock /
//!   list / olist / callout / code / strikethrough / columns 双栏。
//! - 媒体与卡片：music 音乐 / video 视频 / image 图片 / gallery 图库 /
//!   camera 相机（图文行无图占位）/ imgTextCard / imageTextRow /
//!   link 链接 / attach 回形针（附件文件行）。
//! - 手势页：swipe 左滑 / press 长按 / keyboard 键盘（斜杠命令）/
//!   columns 双栏 / search 快速搜索（与通用 search 同名复用）。
//! - 专用函数（非 paths 表）：dino_markup 恐龙头像（DINO_PATHS 与
//!   导出文档共用同一份 path 数据）/ search_markup 搜索胶囊 /
//!   dots_markup ••• 菜单 / back_markup 返回箭头 /
//!   export_icon_markup / import_icon_markup 备份行 /
//!   callout_icon_markup MD 与独立块共用的 Callout 五变体 /
//!   export_back_markup / export_dots_markup 导出 HTML 文档专用形态
//!   （无 xmlns、显式闭合标签，与导出快照口径逐字一致，勿与应用内
//!   back/dots 混用）。

use dioxus::prelude::*;

/// 原版 PATHS（svg.js）+ 编辑器内联图标，name → path d（| 分隔多段）。
pub(crate) fn paths(name: &str) -> Option<&'static str> {
    Some(match name {
        "pin" => "M12 17v5|M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24Z",
        "del" => "M3 6h18|M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6|M10 11v6|M14 11v6|M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2",
        // 卡片浮层菜单「编辑」项（卡片交互专项新增）：与上表
        // 同描边口径的铅笔形（feather edit-2 同形）。
        "edit" => "M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z",
        "back" => "M15 18l-6-6 6-6",
        "check" => "M5.5 12.3 10 16.7 18.8 7.8",
        "palette" => "M12 3.5a8.5 8.5 0 1 0 8.5 8.5c0-1.1-.9-2-2-2h-1.6a1.8 1.8 0 0 1-1.8-1.8V6.5A3 3 0 0 0 12 3.5Z",
        "undo" => "M1 4v6h6|M3.51 15a9 9 0 1 0 2.13-9.36L1 10",
        "redo" => "M23 4v6h-6|M20.49 15a9 9 0 1 1-2.12-9.36L23 10",
        "attach" => "M8.2 11.8l4.9-4.9a3 3 0 1 1 4.2 4.2l-6.5 6.5a5 5 0 1 1-7.1-7.1l7.1-7.1",
        "export" => "M12 3v12m0 0 4-4m-4 4-4-4M5 17v3h14v-3",
        "columns" => "M3 4h18v16H3z|M12 4v16",
        "heading" => "M5 5v14|M19 5v14|M5 12h14|M5 19h8",
        "heading2" => "M5 5v14|M19 5v14|M5 12h14|M7 19h10",
        "heading3" => "M6 6v12|M18 6v12|M6 12h12",
        "paragraph" => "M10 6h10|M4 10h16|M4 14h16|M4 18h8",
        "quote" => "M6 17h5v-6H7v-1a2 2 0 0 1 2-2V6a5 5 0 0 0-5 5v6zm8 0h5v-6h-4v-1a2 2 0 0 1 2-2V6a5 5 0 0 0-5 5v6z",
        "todo" => "M5 5h14v14H5z|m8 12 3 3 5-6",
        "divider" => "M3 12h18",
        "bold" => "M7 4h6a4 4 0 0 1 0 8H7z|M7 12h7a4 4 0 0 1 0 8H7z",
        "italic" => "M15 4H9|M15 4l-6 16|M15 20H9",
        "highlight" => "M4 16 14 6l4 4L8 20H4z|M12 8l4 4|M3 21h14",
        "codeBlock" => "M4 4h16v16H4z|m9 9-3 3 3 3|m15 9 3 3-3 3",
        "list" => "M9 6h12|M9 12h12|M9 18h12|M4 6h.01|M4 12h.01|M4 18h.01",
        "olist" => "M3 7h2V4H3m0 5h2|M3 12h2v3H3m0 0 1.5-1.5|M3 20h2v-3H3m0 0 1.5 1.5|M9 5h12|M9 12h12|M9 19h12",
        "callout" => "M4 4h16v16H4z|M8 9h8|M8 13h6|M6 7v10",
        "imgTextCard" => "M4 4h16v16H4z|M6 6h12v7H6z|M7 16h10",
        "imageTextRow" => "M3 5h8v14H3z|M14 5h7v14h-7z|M5 9h4",
        "link" => "M10 13a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.7 1.7|M14 11a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.7-1.7",
        "code" => "m8 8-4 4 4 4|m16 8 4 4-4 4",
        "strikethrough" => "M14 7a3 3 0 0 0-3-2H9a3 3 0 0 0-1 5.8|M5 12h14|M8 16a3 3 0 0 0 3 3h2a3 3 0 0 0 3-3",
        "music" => "M8 19a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z|M17 17a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z|M10.5 16V5l9-2v11",
        "image" => "M4 5h16v14H4z|M8 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z|m4 16 5-5 3 3 3-4 5 6",
        "gallery" => "M5 7h15v14H5z|M4 17H3V3h15v2",
        "warning" => "M12 2L2 20h20L12 2z|M12 10v4|M12 17h.01",
        // —— 以下为图标集统一批新增（feather 同形、描边口径同上）——
        // 媒体：视频（卡片来源行）、相机（图文行无图占位）。
        "video" => "M14 5H3a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2Z|M23 7l-7 5 7 5Z",
        "camera" => "M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2Z|M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z",
        // 通用：搜索、文件文本（空库空状态）、显示器/时钟/胶片
        // （错误徽章条目分类）、成功/失败圆圈（toast 反馈）。
        "search" => "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Z|M21 21l-4.35-4.35",
        "file-text" => "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z|M14 2v6h6|M16 13H8|M16 17H8|M10 9H8",
        "monitor" => "M5 3h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z|M8 21h8|M12 17v4",
        "clock" => "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z|M12 7v5l3 2",
        "film" => "M2 4a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2Z|M7 2v20|M17 2v20|M2 12h20|M2 7h5|M2 17h5|M17 17h5|M17 7h5",
        "check-circle" => "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z|M9 12l2 2 4-4",
        "x-circle" => "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z|M15 9l-6 6|M9 9l6 6",
        // 手势页：左滑（箭头抵右界）、长按（同心圆+中心点）、
        // 键盘（键点+空格条）。
        "swipe" => "M21 12H9|M14 5l-7 7 7 7|M21 6v12",
        "press" => "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z|M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z|M12 12h.01",
        "keyboard" => "M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z|M6 9h.01|M10 9h.01|M14 9h.01|M18 9h.01|M6 13h.01|M18 13h.01|M9 13h6",
        _ => return None,
    })
}

/// 生成与原版 SvgIcon 等价的 <svg> 标记字符串。
pub(crate) fn svg_markup(name: &str, size: u32, stroke_width: &str, stroke: &str) -> String {
    let Some(d) = paths(name) else { return String::new() };
    let mut out = format!(
        "<svg viewBox=\"0 0 24 24\" width=\"{size}\" height=\"{size}\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">"
    );
    for p in d.split('|') {
        out.push_str(&format!(
            "<path d=\"{p}\" stroke=\"{stroke}\" stroke-width=\"{stroke_width}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" fill=\"none\"/>"
        ));
    }
    out.push_str("</svg>");
    out
}

/// 描边图标组件（dangerous_inner_html 注入与原版一致的 SVG）。
#[component]
pub(crate) fn Icon(name: String, size: u32, stroke_width: String, stroke: String) -> Element {
    let markup = svg_markup(&name, size, &stroke_width, &stroke);
    rsx! {
        span {
            style: "display:inline-flex;align-items:center;justify-content:center;",
            dangerous_inner_html: "{markup}",
        }
    }
}

/// 恐龙线稿 path 数据（viewBox 512）：应用内头像与导出 HTML 文档
/// 共用同一份，禁止在导出侧另存副本。
pub(crate) const DINO_PATHS: [&str; 10] = [
        "M 90,460 L 90,170 C 90,110 140,70 210,70 L 380,95 C 440,95 470,130 470,185 C 470,225 450,240 410,245 C 350,250 280,230 210,265 C 190,275 190,295 210,310 C 270,350 350,380 410,360 C 435,350 440,325 410,315",
        "M 160,330 C 180,380 230,440 280,460",
        "M 240,365 C 220,400 240,440 310,460",
        "M 90,460 L 310,460",
        "M 415,135 C 425,140 435,150 435,160",
        "M 230,115 C 260,95 310,120 355,140",
        "M 255,140 C 255,170 290,195 320,185 C 345,175 350,150 335,135",
        "M 290,145 C 290,165 315,165 315,150",
        "M 250,243 L 255,265 L 265,243 M 275,245 L 282,270 L 292,245 M 302,246 L 310,273 L 320,247 M 330,248 L 340,275 L 350,248 M 360,249 L 370,274 L 380,248 M 390,248 L 400,270 L 408,246 M 415,244 L 425,263 L 432,240 M 438,235 L 448,252 L 452,228",
        "M 250,323 L 255,305 L 263,326 M 273,329 L 280,308 L 288,333 M 298,336 L 306,313 L 314,340 M 324,343 L 333,318 L 341,346 M 351,348 L 361,323 L 369,351 M 379,352 L 389,328 L 396,353 M 404,351 L 413,330 L 418,348",
];

/// 恐龙线稿（原版头像/编辑器头像共用，viewBox 512，stroke 图标弱色）。
pub(crate) fn dino_markup(size: u32, translate_y: i32) -> String {
    let mut out = format!(
        "<svg viewBox=\"0 0 512 512\" width=\"{size}\" height=\"{size}\" fill=\"none\" stroke=\"var(--color-icon-muted)\" stroke-width=\"22\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"transform: translateY({translate_y}px)\">"
    );
    for p in DINO_PATHS {
        out.push_str(&format!("<path d=\"{p}\"/>"));
    }
    out.push_str("</svg>");
    out
}

/// 搜索放大镜（原版 memo-list 内联 SVG：circle + line，stroke 次级色）。
pub(crate) fn search_markup(size: u32) -> String {
    format!(
        "<svg viewBox=\"0 0 24 24\" width=\"{size}\" height=\"{size}\" fill=\"none\" stroke=\"var(--text-secondary)\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"11\" cy=\"11\" r=\"8\"/><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"/></svg>"
    )
}

/// ••• 圆点（原版 editor-fab.right：三个 fill currentColor 圆）。
pub(crate) fn dots_markup() -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"currentColor\"><circle cx=\"5\" cy=\"12\" r=\"2\"/><circle cx=\"12\" cy=\"12\" r=\"2\"/><circle cx=\"19\" cy=\"12\" r=\"2\"/></svg>".to_string()
}

/// 导出图标（原版 BackupView 内联 SVG 逐字：上箭头 + 托盘，
/// 28px，stroke accent，strokeWidth 2）。
pub(crate) fn export_icon_markup() -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"28\" height=\"28\" fill=\"none\" stroke=\"var(--color-accent)\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\"/><polyline points=\"17 8 12 3 7 8\"/><line x1=\"12\" y1=\"3\" x2=\"12\" y2=\"15\"/></svg>".to_string()
}

/// 导入图标（同上，下箭头 + 托盘）。
pub(crate) fn import_icon_markup() -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"28\" height=\"28\" fill=\"none\" stroke=\"var(--color-accent)\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\"/><polyline points=\"7 10 12 15 17 10\"/><line x1=\"12\" y1=\"15\" x2=\"12\" y2=\"3\"/></svg>".to_string()
}

/// Callout 图标（原版 editor.md.js CALLOUT_ICONS 五路径逐字，
/// stroke 走 --md-callout-*-icon 令牌，18px）。
pub(crate) fn callout_icon_markup(style: &str) -> String {
    let inner = match style {
        "warning" => "<path d=\"M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z\"/><line x1=\"12\" y1=\"9\" x2=\"12\" y2=\"13\"/><line x1=\"12\" y1=\"17\" x2=\"12.01\" y2=\"17\"/>",
        "tip" => "<polygon points=\"12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2\"/>",
        "important" => "<path d=\"M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z\"/><line x1=\"4\" y1=\"22\" x2=\"4\" y2=\"15\"/>",
        "caution" => "<circle cx=\"12\" cy=\"12\" r=\"10\"/><line x1=\"15\" y1=\"9\" x2=\"9\" y2=\"15\"/><line x1=\"9\" y1=\"9\" x2=\"15\" y2=\"15\"/>",
        _ => "<circle cx=\"12\" cy=\"12\" r=\"10\"/><path d=\"M12 16v-4\"/><path d=\"M12 8h.01\"/>",
    };
    format!(
        "<svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--md-callout-{style}-icon)\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">{inner}</svg>"
    )
}

/// 导出 HTML 文档专用返回箭头：与应用内 back_markup 同形，但按
/// 导出快照口径逐字输出（无 xmlns、polyline 显式闭合），勿混用。
pub(crate) fn export_back_markup() -> String {
    "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"15 18 9 12 15 6\"></polyline></svg>".to_string()
}

/// 导出 HTML 文档专用 ••• 圆点：同 export_back_markup 注。
pub(crate) fn export_dots_markup() -> String {
    "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"currentColor\"><circle cx=\"5\" cy=\"12\" r=\"2\"></circle><circle cx=\"12\" cy=\"12\" r=\"2\"></circle><circle cx=\"19\" cy=\"12\" r=\"2\"></circle></svg>".to_string()
}

/// 返回箭头（原版 editor-fab：polyline 15 18 9 12 15 6）。
pub(crate) fn back_markup() -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><polyline points=\"15 18 9 12 15 6\"/></svg>".to_string()
}
