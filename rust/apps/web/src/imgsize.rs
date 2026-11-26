//! 图片自然尺寸 + 几何预留（D-22 续项，用户 2026-11-24
//! 立项）：批 11 已给编辑页图片落 loading="lazy" /
//! decoding="async"，但全块同帧挂载 + 图片零预留高度，
//! 赋 src 时全图挤在懒加载阈值内、属性被击穿（20 图长
//! 备忘开页仍 20/20 解码）。本模块是编辑页全部图片呈现
//! 共用的唯一预留机制（BlobMedia / URL 形 image 块 /
//! gallery Url 项 / MdPreview 行内图共同消费）：
//!   - 附件图：取字节时从字节头解析自然尺寸（PNG /
//!     JPEG / GIF / WebP 纯 Rust 小解析器，异常字节安全
//!     失败、无预留回退现行行为），并按 fileId 回填缓存；
//!   - URL 图：尺寸缓存（键 = URL，localStorage 持久），
//!     首次由元素 load 事件回填（track_img_load），再次
//!     进入即有预留；data: 图直接解析其 base64 头部、
//!     不入缓存；blob: 不缓存（会话内临时地址）；
//!   - 预留样式按呈现上下文的现行 CSS 几何分三型
//!     （Reserve），目标是占位盒几何 == 载入后最终几何、
//!     载入零位移。几何实证（box，应用真实 CSS）：
//!     width/height 属性与单独 aspect-ratio 均被现行规则
//!     （全局 height:auto 等）压成 0 盒，只有内联
//!     width + aspect-ratio 能预留；高图还需在 width 里
//!     以 calc 把 max-height 上限折算成宽度上限。

use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};

/// 预留样式型：与各呈现上下文现行 CSS 的最终几何对应。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Reserve {
    /// 独立图片块（.atomic[data-type=image] > img）：
    /// width auto、max-width 100%、max-height 668px、
    /// object-fit contain、margin auto。
    Capped,
    /// MD 行内图（.markdown-render img）：width auto、
    /// max-width 100%、无高度上限。
    Natural,
    /// 宽 100% 型（附件图 / 图文卡 / gallery / 图文行）：
    /// 宽度由 CSS 定死，只需 aspect-ratio 定高；高度被
    /// CSS 定死处（gallery 366px、图文行 100%）aspect
    /// 自动失效、无副作用。
    Fill,
}

/// 独立图片块的高度上限（editor.css
/// .atomic[data-type="image"] > img 的 max-height，与
/// 该规则同值；改那条规则须同步改这里）。
const STANDALONE_MAX_H: u32 = 668;

/// 按型生成预留内联样式；尺寸未知返回空串（无预留、
/// 与现行行为一致）。载入后同一元素同一式样：内联
/// width 的 min() 三项（自然宽 / 容器宽 / 高度上限折
/// 算宽）与样式表最终几何逐项同值（box 实证大图
/// 1200x900、高图 900x2000、小图 200x150 三形载入前
/// 后盒逐字一致）。
pub fn reserve_style(mode: Reserve, size: Option<(u32, u32)>) -> String {
    let Some((w, h)) = size.filter(|(w, h)| *w > 0 && *h > 0) else {
        return String::new();
    };
    match mode {
        Reserve::Capped => format!(
            "width:min({w}px,100%,calc({STANDALONE_MAX_H}px * {w} / {h}));aspect-ratio:{w}/{h};"
        ),
        Reserve::Natural => format!("width:min({w}px,100%);aspect-ratio:{w}/{h};"),
        Reserve::Fill => format!("aspect-ratio:{w}/{h};"),
    }
}

// ── 字节头解析（纯函数，异常输入安全失败）────────────

fn be32(b: &[u8], off: usize) -> Option<u32> {
    Some(u32::from_be_bytes(b.get(off..off + 4)?.try_into().ok()?))
}

fn le16(b: &[u8], off: usize) -> Option<u16> {
    Some(u16::from_le_bytes(b.get(off..off + 2)?.try_into().ok()?))
}

fn le24(b: &[u8], off: usize) -> Option<u32> {
    let s = b.get(off..off + 3)?;
    Some(s[0] as u32 | (s[1] as u32) << 8 | (s[2] as u32) << 16)
}

/// 从图片字节头解析自然尺寸（宽，高）。只读头部元数
/// 据、不解码；任何签名不符 / 越界 / 零尺寸都返回
/// None（调用方回退无预留）。
pub fn parse_image_size(bytes: &[u8]) -> Option<(u32, u32)> {
    let size = parse_png(bytes)
        .or_else(|| parse_gif(bytes))
        .or_else(|| parse_jpeg(bytes))
        .or_else(|| parse_webp(bytes))?;
    if size.0 == 0 || size.1 == 0 {
        None
    } else {
        Some(size)
    }
}

fn parse_png(b: &[u8]) -> Option<(u32, u32)> {
    if b.len() < 24 || b.get(0..8)? != b"\x89PNG\r\n\x1a\n" || b.get(12..16)? != b"IHDR" {
        return None;
    }
    Some((be32(b, 16)?, be32(b, 20)?))
}

fn parse_gif(b: &[u8]) -> Option<(u32, u32)> {
    let sig = b.get(0..6)?;
    if sig != b"GIF87a" && sig != b"GIF89a" {
        return None;
    }
    Some((le16(b, 6)? as u32, le16(b, 8)? as u32))
}

fn parse_jpeg(b: &[u8]) -> Option<(u32, u32)> {
    if b.len() < 4 || b[0] != 0xFF || b[1] != 0xD8 {
        return None;
    }
    // 段走查：FF <marker> <len:u16be（含自身 2 字节）>
    // <payload len-2>；SOFn 段 payload 首 5 字节为
    // precision(1) + height(2) + width(2)。
    let mut i = 2usize;
    loop {
        if b.get(i)? != &0xFF {
            return None;
        }
        let mut j = i + 1;
        while b.get(j) == Some(&0xFF) {
            j += 1;
        }
        let marker = *b.get(j)?;
        i = j + 1;
        // 无长度字段的独立标记：SOI / EOI / TEM / RSTn
        if marker == 0xD8 || marker == 0xD9 || marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            continue;
        }
        let seg_len = u16::from_be_bytes([*b.get(i)?, *b.get(i + 1)?]) as usize;
        if seg_len < 2 {
            return None;
        }
        if matches!(
            marker,
            0xC0 | 0xC1 | 0xC2 | 0xC3 | 0xC5 | 0xC6 | 0xC7 | 0xC9 | 0xCA | 0xCB | 0xCD | 0xCE | 0xCF
        ) {
            let h = u16::from_be_bytes([*b.get(i + 3)?, *b.get(i + 4)?]) as u32;
            let w = u16::from_be_bytes([*b.get(i + 5)?, *b.get(i + 6)?]) as u32;
            return Some((w, h));
        }
        i += seg_len;
    }
}

fn parse_webp(b: &[u8]) -> Option<(u32, u32)> {
    if b.get(0..4)? != b"RIFF" || b.get(8..12)? != b"WEBP" {
        return None;
    }
    match b.get(12..16)? {
        b"VP8X" => Some((le24(b, 24)? + 1, le24(b, 27)? + 1)),
        b"VP8 " => {
            if b.get(23..26)? != b"\x9d\x01\x2a" {
                return None;
            }
            let w = (le16(b, 26)? & 0x3FFF) as u32;
            let h = (le16(b, 28)? & 0x3FFF) as u32;
            Some((w, h))
        }
        b"VP8L" => {
            if b.get(20)? != &0x2F {
                return None;
            }
            let v = u32::from_le_bytes(b.get(21..25)?.try_into().ok()?);
            Some(((v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1))
        }
        _ => None,
    }
}

/// data:image/*;base64 图：解码头部前缀（≤1024 个
/// base64 字符 ≈ 768 字节，覆盖 PNG/GIF/WebP 定长头
/// 与绝大多数 JPEG 的 SOF 位置）后走同一解析器。
pub fn parse_data_uri_size(uri: &str) -> Option<(u32, u32)> {
    let rest = uri.strip_prefix("data:image/")?;
    let (_, b64) = rest.split_once(";base64,")?;
    let take = b64.len().min(1024) / 4 * 4;
    let bytes = base64_decode_prefix(b64.get(..take)?)?;
    parse_image_size(&bytes)
}

fn base64_decode_prefix(s: &str) -> Option<Vec<u8>> {
    fn val(c: u8) -> Option<u32> {
        match c {
            b'A'..=b'Z' => Some((c - b'A') as u32),
            b'a'..=b'z' => Some((c - b'a') as u32 + 26),
            b'0'..=b'9' => Some((c - b'0') as u32 + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            // 填充只出现在完整串末尾（短串整体即夹具时
            // 前缀里也会遇到）：按 0 解，多出的尾字节由
            // 后续签名校验兜底，不影响头部解析。
            b'=' => Some(0),
            _ => None,
        }
    }
    let mut out = Vec::with_capacity(s.len() / 4 * 3);
    for quad in s.as_bytes().chunks_exact(4) {
        let n = (val(quad[0])? << 18) | (val(quad[1])? << 12) | (val(quad[2])? << 6) | val(quad[3])?;
        out.push((n >> 16) as u8);
        out.push((n >> 8) as u8);
        out.push(n as u8);
    }
    Some(out)
}

// ── 尺寸缓存（URL / fileId 双键，localStorage 持久）──

const CACHE_KEY: &str = "moment_imgsize_v1";
/// 条数上限：超限整表清空自愈（尺寸可随时由 load /
/// 字节解析重建，清表只损失一次预留机会）。
const CACHE_CAP: usize = 400;
/// 键长上限：异常长 URL 不入表。
const KEY_MAX: usize = 2048;

thread_local! {
    static CACHE: RefCell<Option<HashMap<String, (u32, u32)>>> =
        const { RefCell::new(None) };
}

fn fid_key(fid: &str) -> String {
    format!("fid:{fid}")
}

fn with_cache<R>(f: impl FnOnce(&mut HashMap<String, (u32, u32)>) -> R) -> R {
    CACHE.with(|c| {
        let mut slot = c.borrow_mut();
        if slot.is_none() {
            let map = load_cache();
            if !map.is_empty() {
                crate::diag::log(
                    "IMGSIZE",
                    &format!("size cache restored: {} entries", map.len()),
                );
            }
            *slot = Some(map);
        }
        f(slot.as_mut().expect("cache initialized"))
    })
}

/// URL 图的已知尺寸：data: 直读头部（不查缓存）、
/// blob: 恒无、http(s) 查缓存。
pub fn size_for_url(url: &str) -> Option<(u32, u32)> {
    if url.starts_with("data:") {
        return parse_data_uri_size(url);
    }
    if url.starts_with("blob:") || url.is_empty() {
        return None;
    }
    with_cache(|c| c.get(url).copied())
}

/// 附件图的已知尺寸（此前任一次取字节解析过即有）。
pub fn size_for_fid(fid: &str) -> Option<(u32, u32)> {
    with_cache(|c| c.get(&fid_key(fid)).copied())
}

fn record(key: &str, w: u32, h: u32) {
    if w == 0 || h == 0 || key.len() > KEY_MAX {
        return;
    }
    with_cache(|c| {
        if c.get(key) == Some(&(w, h)) {
            return;
        }
        if c.len() >= CACHE_CAP && !c.contains_key(key) {
            c.clear();
        }
        c.insert(key.to_string(), (w, h));
        persist_cache(c);
    });
}

/// URL 图载入后回填（track_img_load 调用）：只收
/// http(s)——data: 渲染时直读、blob: 会话临时地址。
pub fn record_url_size(url: &str, w: u32, h: u32) {
    if url.starts_with("http://") || url.starts_with("https://") {
        record(url, w, h);
    }
}

/// 附件图取字节解析后回填（BlobMedia 调用）。
pub fn record_fid_size(fid: &str, w: u32, h: u32) {
    record(&fid_key(fid), w, h);
}

#[cfg(target_arch = "wasm32")]
fn load_cache() -> HashMap<String, (u32, u32)> {
    let raw = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
        .and_then(|s| s.get_item(CACHE_KEY).ok())
        .flatten();
    match raw {
        Some(json) => serde_json::from_str::<HashMap<String, (u32, u32)>>(&json)
            .unwrap_or_default(),
        None => HashMap::new(),
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn load_cache() -> HashMap<String, (u32, u32)> {
    HashMap::new()
}

#[cfg(target_arch = "wasm32")]
fn persist_cache(map: &HashMap<String, (u32, u32)>) {
    if let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    {
        if let Ok(json) = serde_json::to_string(map) {
            let _ = storage.set_item(CACHE_KEY, &json);
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn persist_cache(_map: &HashMap<String, (u32, u32)>) {}

// ── Diag 抽样（结果侧：真实解析到的尺寸）────────────

static PARSED_COUNT: AtomicU32 = AtomicU32::new(0);

/// 附件字节解析成功时回记：每 20 次抽样落一行 Diag，
/// 防长文档开页刷屏；计数本身即结果侧量测。
pub fn note_parsed(fid: &str, w: u32, h: u32) {
    let n = PARSED_COUNT.fetch_add(1, Ordering::Relaxed) + 1;
    if n % 20 == 1 {
        crate::diag::log("IMGSIZE", &format!("parsed {fid} {w}x{h} (#{n})"));
    }
}

// ── URL 图 load 回填（元素级监听）────────────────────

/// URL 图挂载后调用：元素已 complete 则当场回填，
/// 否则装 load 监听，元素每次载入完成按其当时 src
/// 回填（编辑中改 URL 也能跟上）。监听闭包随元素生
/// 命周期存活（forget），每元素一份、量级可忽略。
#[cfg(target_arch = "wasm32")]
pub fn track_img_load(evt: dioxus::prelude::MountedEvent) {
    use dioxus::web::WebEventExt;
    use wasm_bindgen::JsCast;
    let Some(el) = evt.data().try_as_web_event() else {
        return;
    };
    let Ok(img) = el.dyn_into::<web_sys::HtmlImageElement>() else {
        return;
    };
    if record_from_img(&img) {
        return;
    }
    let img2 = img.clone();
    let cb = wasm_bindgen::closure::Closure::<dyn FnMut()>::new(move || {
        record_from_img(&img2);
    });
    let _ = img.add_event_listener_with_callback(
        "load",
        cb.as_ref().unchecked_ref(),
    );
    cb.forget();
}

#[cfg(not(target_arch = "wasm32"))]
pub fn track_img_load(_evt: dioxus::prelude::MountedEvent) {}

#[cfg(target_arch = "wasm32")]
fn record_from_img(img: &web_sys::HtmlImageElement) -> bool {
    let w = img.natural_width();
    let h = img.natural_height();
    if w == 0 || h == 0 {
        return false;
    }
    // 键与渲染侧查询同串：src 属性原值优先，绝对化后
    // 的 current_src 兜底（两者不同时各记一份）。
    let attr = img.get_attribute("src").unwrap_or_default();
    let current = img.current_src();
    record_url_size(&attr, w, h);
    if current != attr {
        record_url_size(&current, w, h);
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png_bytes(w: u32, h: u32) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(b"\x89PNG\r\n\x1a\n");
        v.extend_from_slice(&13u32.to_be_bytes());
        v.extend_from_slice(b"IHDR");
        v.extend_from_slice(&w.to_be_bytes());
        v.extend_from_slice(&h.to_be_bytes());
        v.extend_from_slice(&[8, 2, 0, 0, 0]);
        v
    }

    #[test]
    fn png_header() {
        assert_eq!(parse_image_size(&png_bytes(1200, 900)), Some((1200, 900)));
        assert_eq!(parse_image_size(&png_bytes(1, 1)), Some((1, 1)));
    }

    #[test]
    fn gif_header() {
        let mut v = b"GIF89a".to_vec();
        v.extend_from_slice(&640u16.to_le_bytes());
        v.extend_from_slice(&480u16.to_le_bytes());
        assert_eq!(parse_image_size(&v), Some((640, 480)));
        let mut v87 = b"GIF87a".to_vec();
        v87.extend_from_slice(&3u16.to_le_bytes());
        v87.extend_from_slice(&2u16.to_le_bytes());
        assert_eq!(parse_image_size(&v87), Some((3, 2)));
    }

    fn jpeg_with_sof(sof: u8, app_payload: usize, w: u16, h: u16) -> Vec<u8> {
        let mut v = vec![0xFF, 0xD8];
        // APP0 段（长度含自身 2 字节）
        v.extend_from_slice(&[0xFF, 0xE0]);
        v.extend_from_slice(&((app_payload + 2) as u16).to_be_bytes());
        v.extend(std::iter::repeat(0u8).take(app_payload));
        // SOF 段
        v.extend_from_slice(&[0xFF, sof]);
        v.extend_from_slice(&17u16.to_be_bytes());
        v.push(8);
        v.extend_from_slice(&h.to_be_bytes());
        v.extend_from_slice(&w.to_be_bytes());
        v
    }

    #[test]
    fn jpeg_sof0_and_progressive() {
        assert_eq!(
            parse_image_size(&jpeg_with_sof(0xC0, 14, 800, 600)),
            Some((800, 600))
        );
        assert_eq!(
            parse_image_size(&jpeg_with_sof(0xC2, 200, 1024, 768)),
            Some((1024, 768))
        );
    }

    #[test]
    fn webp_variants() {
        // VP8X：宽高各为 LE24 的值 +1
        let mut x = Vec::new();
        x.extend_from_slice(b"RIFF");
        x.extend_from_slice(&30u32.to_le_bytes());
        x.extend_from_slice(b"WEBP");
        x.extend_from_slice(b"VP8X");
        x.extend_from_slice(&10u32.to_le_bytes());
        x.extend_from_slice(&[0, 0, 0, 0]);
        x.extend_from_slice(&[0x83, 0x03, 0x00]); // 900-1
        x.extend_from_slice(&[0x57, 0x02, 0x00]); // 600-1
        assert_eq!(parse_image_size(&x), Some((900, 600)));
        // VP8（有损）：帧标记 + 9D 01 2A + 14 位宽高
        let mut l = Vec::new();
        l.extend_from_slice(b"RIFF");
        l.extend_from_slice(&30u32.to_le_bytes());
        l.extend_from_slice(b"WEBP");
        l.extend_from_slice(b"VP8 ");
        l.extend_from_slice(&20u32.to_le_bytes());
        l.extend_from_slice(&[0, 0, 0]); // frame tag
        l.extend_from_slice(&[0x9D, 0x01, 0x2A]);
        l.extend_from_slice(&320u16.to_le_bytes());
        l.extend_from_slice(&240u16.to_le_bytes());
        assert_eq!(parse_image_size(&l), Some((320, 240)));
        // VP8L：0x2F 签名 + 打包位域
        let mut ll = Vec::new();
        ll.extend_from_slice(b"RIFF");
        ll.extend_from_slice(&25u32.to_le_bytes());
        ll.extend_from_slice(b"WEBP");
        ll.extend_from_slice(b"VP8L");
        ll.extend_from_slice(&5u32.to_le_bytes());
        ll.push(0x2F);
        let packed: u32 = (500 - 1) | ((300 - 1) << 14);
        ll.extend_from_slice(&packed.to_le_bytes());
        assert_eq!(parse_image_size(&ll), Some((500, 300)));
    }

    #[test]
    fn malformed_inputs_fail_safely() {
        assert_eq!(parse_image_size(&[]), None);
        assert_eq!(parse_image_size(&[0xFF, 0xD8]), None);
        assert_eq!(parse_image_size(b"not an image at all........"), None);
        // 截断的 PNG
        assert_eq!(parse_image_size(&png_bytes(10, 10)[..16]), None);
        // 零尺寸
        assert_eq!(parse_image_size(&png_bytes(0, 10)), None);
        assert_eq!(parse_image_size(&png_bytes(10, 0)), None);
        // JPEG 段长造假（<2）
        assert_eq!(parse_image_size(&[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01]), None);
        // JPEG 无 SOF 走到尽头
        assert_eq!(
            parse_image_size(&[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0xAA, 0xBB]),
            None
        );
    }

    #[test]
    fn data_uri_png() {
        // 用已知 base64：PNG 头部（1x1 透明 PNG 的前 24+
        // 字节即可定 IHDR）——直接由 png_bytes 现场编码
        // 等价断言走解析器：这里用手工拼的最小样本。
        let raw = png_bytes(48, 32);
        let b64 = base64_encode(&raw);
        let uri = format!("data:image/png;base64,{b64}");
        assert_eq!(parse_data_uri_size(&uri), Some((48, 32)));
        assert_eq!(parse_data_uri_size("data:image/png;base64,@@@"), None);
        assert_eq!(parse_data_uri_size("https://x/y.png"), None);
    }

    fn base64_encode(data: &[u8]) -> String {
        const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::new();
        for chunk in data.chunks(3) {
            let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
            let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
            out.push(T[(n >> 18) as usize & 63] as char);
            out.push(T[(n >> 12) as usize & 63] as char);
            out.push(if chunk.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' });
            out.push(if chunk.len() > 2 { T[n as usize & 63] as char } else { '=' });
        }
        out
    }

    #[test]
    fn reserve_styles() {
        assert_eq!(reserve_style(Reserve::Fill, None), "");
        assert_eq!(reserve_style(Reserve::Fill, Some((0, 5))), "");
        assert_eq!(
            reserve_style(Reserve::Fill, Some((1200, 900))),
            "aspect-ratio:1200/900;"
        );
        assert_eq!(
            reserve_style(Reserve::Natural, Some((1200, 900))),
            "width:min(1200px,100%);aspect-ratio:1200/900;"
        );
        assert_eq!(
            reserve_style(Reserve::Capped, Some((900, 2000))),
            "width:min(900px,100%,calc(668px * 900 / 2000));aspect-ratio:900/2000;"
        );
    }
}
