//! 双栏分界：规范估高 + layout 锚归一（原版 editorBlockHeight
//! 回退表与 normalizeColumnLayout 口径）。分界是文档内容
//! 的确定性纯函数，不依赖实测高、加载状态或会话。

use super::*;

/// 块的规范估高（原版 editorBlockHeight 的回退表，
/// src/editor/editor.render.js）：图片/画廊/图文卡 280，
/// 音乐/链接/嵌入卡与附件文件卡 120，带图附件 280，其余
/// 按纯文本行数 28+行×25（44 字/行）。原版优先用实测高，
/// 但实测依赖加载状态与会话（骨架→成卡、图片到达、字体
/// 切换），分界随之漂移；这里只用规范表，使分界成为文档
/// 内容的确定性纯函数（md 源码段按源文本计行，编辑态与
/// 预览态同口径）。
fn est_block_height(node: &Node) -> f64 {
    match node.block_type().unwrap_or("") {
        "image" | "gallery" | "imgTextCard" | "imageTextRow" => 280.0,
        "musicCard" | "link-card" | "embedCard" => 120.0,
        "attachment" => {
            if node
                .extra
                .get("image")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                280.0
            } else {
                120.0
            }
        }
        _ => {
            // 原版 editorBlockHeight 回退表按 text.length
            // （UTF-16 码元）折行，与光标偏移同一口径。
            let len = node.plain_text().encode_utf16().count();
            let lines = ((len as f64) / 44.0).ceil().max(1.0);
            28.0 + lines * 25.0
        }
    }
}

/// 无锚时的规范分界（原版 setIndependentScroll 首次启用
/// 的分法）：在 [1, len-1] 中取使左右估高最接近的分界；
/// 不足两块时全归左栏。
pub(super) fn canonical_boundary(doc: &[Node]) -> usize {
    if doc.len() < 2 {
        return doc.len();
    }
    let weights: Vec<f64> = doc.iter().map(est_block_height).collect();
    let total: f64 = weights.iter().sum();
    let mut running = 0.0f64;
    let mut split = 1usize;
    let mut best = f64::INFINITY;
    for i in 1..doc.len() {
        running += weights[i - 1];
        let diff = (total - running * 2.0).abs();
        if diff < best {
            best = diff;
            split = i;
        }
    }
    split
}

/// 锚归一化（原版 normalizeColumnLayout 的边界口径）：
/// layout.right 中按文档序第一个仍存在的块即右栏起点；
/// right 全灭时取最后一个仍存在的 left 块之后。layout
/// 形状不合（非对象、left/right 非数组）或两边都无存活
/// id 时返回 None（视同无锚，走规范分界——原版此情形会
/// 把全部块判入右栏，属病理输出，这里不从）。
pub(super) fn normalize_boundary(doc: &[Node], layout: &Value) -> Option<usize> {
    let left = layout.get("left")?.as_array()?;
    let right = layout.get("right")?.as_array()?;
    let ids: Vec<String> = doc
        .iter()
        .map(|n| n.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
        .collect();
    let positions = |arr: &[Value]| -> Vec<usize> {
        arr.iter()
            .filter_map(|x| x.as_str())
            .filter_map(|s| ids.iter().position(|i| i == s))
            .collect()
    };
    if let Some(first) = positions(right).iter().min() {
        return Some(*first);
    }
    if let Some(last) = positions(left).iter().max() {
        return Some((last + 1).min(doc.len()));
    }
    None
}

/// 双栏分界：有 layout 锚时成员由锚决定（与编辑、加载
/// 状态、会话无关）；无锚时按规范估高分界（文档内容的
/// 确定性纯函数）。独立滚动首次渲染会把规范分界落锚
/// （见 Editor 的 column anchor capture），此后走锚路径。
/// 此前实现无锚时按纯文本字数分半：卡片/图片字数≈0 而
/// 长文本字数独大，分界既偏离栏高均衡、又随每次编辑改
/// 变字数而漂移（回来再进来块跨栏迁移的根源）。
pub(super) fn column_boundary(doc: &[Node], layout: Option<&Value>) -> usize {
    if let Some(l) = layout {
        if let Some(b) = normalize_boundary(doc, l) {
            return b;
        }
    }
    canonical_boundary(doc)
}

/// 跨栏判定（A-2 流式跨栏）：原版多列流的 column-span 名单
/// ——image/gallery/imgTextCard/imageTextRow/musicCard 五类
/// 按 block_type；带图附件 = attachment 且 extra["image"]
/// 为真且有 fileId（与 blocks.rs 附件渲染同口径：无 fileId
/// 时走文件卡形态、不跨）。video/link-card/embedCard 与
/// 普通附件不在名单。与 est_block_height 的类型口径同源，
/// 两处改名单须同步。
pub(super) fn is_span_block(node: &Node) -> bool {
    match node.block_type().unwrap_or("") {
        "image" | "gallery" | "imgTextCard" | "imageTextRow" | "musicCard" => true,
        "attachment" => {
            node.extra
                .get("image")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
                && crate::blocks::file_id(node).is_some()
        }
        _ => false,
    }
}

/// 流式×宽屏的渲染分段（A-2）：文档按跨栏块切段——连续
/// 非跨栏块成 Columns 段、跨栏块各自成 Span 段。段内切分
/// 用段切片的 canonical_boundary（规范估高平衡），与
/// layout 锚正交：不读不写锚（分段只看文档序与块类型，
/// 是文档内容的确定性纯函数）。空段不产出（跨栏块在
/// 首/尾、连续跨栏块）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum FlowSeg {
    Columns {
        left: std::ops::Range<usize>,
        right: std::ops::Range<usize>,
    },
    Span(usize),
}

pub(super) fn flow_segments(doc: &[Node]) -> Vec<FlowSeg> {
    let mut segs = Vec::new();
    let mut run_start: Option<usize> = None;
    for (i, node) in doc.iter().enumerate() {
        if is_span_block(node) {
            if let Some(s) = run_start.take() {
                segs.push(columns_seg(doc, s, i));
            }
            segs.push(FlowSeg::Span(i));
        } else if run_start.is_none() {
            run_start = Some(i);
        }
    }
    if let Some(s) = run_start {
        segs.push(columns_seg(doc, s, doc.len()));
    }
    segs
}

fn columns_seg(doc: &[Node], start: usize, end: usize) -> FlowSeg {
    let b = start + canonical_boundary(&doc[start..end]);
    FlowSeg::Columns {
        left: start..b,
        right: b..end,
    }
}

#[cfg(test)]
mod flow_segments_tests {
    use super::*;

    // 直构字面量（与 e17_start_tests 同口径：主机靶测试
    // 无 wasm 导入可用，不走 new_block/gen_id）。
    fn blk(ty: &str, text: &str) -> Node {
        Node {
            text: None,
            node_type: Some(ty.to_string()),
            id: Some(format!("{ty}-{text}")),
            children: Some(vec![Node {
                text: Some(text.to_string()),
                node_type: None,
                id: None,
                children: None,
                extra: Map::new(),
            }]),
            extra: Map::new(),
        }
    }

    fn para(text: &str) -> Node {
        blk("paragraph", text)
    }

    fn attachment(image: bool, fid: Option<&str>) -> Node {
        let mut n = blk("attachment", "");
        if image {
            n.extra.insert("image".to_string(), json!(true));
        }
        if let Some(f) = fid {
            n.extra.insert("fileId".to_string(), json!(f));
        }
        n
    }

    #[test]
    fn empty_doc_no_segments() {
        assert!(flow_segments(&[]).is_empty());
    }

    #[test]
    fn no_span_single_segment_canonical_split() {
        // 四段等高文本：规范切分居中 2|2。
        let doc = vec![para("a"), para("b"), para("c"), para("d")];
        assert_eq!(
            flow_segments(&doc),
            vec![FlowSeg::Columns {
                left: 0..2,
                right: 2..4
            }]
        );
    }

    #[test]
    fn single_block_segment_all_left() {
        // canonical 对 len<2 全归左（既有语义）。
        let doc = vec![para("a"), blk("image", ""), para("b")];
        assert_eq!(
            flow_segments(&doc),
            vec![
                FlowSeg::Columns {
                    left: 0..1,
                    right: 1..1
                },
                FlowSeg::Span(1),
                FlowSeg::Columns {
                    left: 2..3,
                    right: 3..3
                },
            ]
        );
    }

    #[test]
    fn span_at_head_and_tail_no_empty_segments() {
        let doc = vec![blk("gallery", ""), para("a"), para("b"), blk("musicCard", "")];
        assert_eq!(
            flow_segments(&doc),
            vec![
                FlowSeg::Span(0),
                FlowSeg::Columns {
                    left: 1..2,
                    right: 2..3
                },
                FlowSeg::Span(3),
            ]
        );
    }

    #[test]
    fn consecutive_spans_each_own_segment() {
        let doc = vec![para("a"), blk("image", ""), blk("imgTextCard", ""), para("b")];
        assert_eq!(
            flow_segments(&doc),
            vec![
                FlowSeg::Columns {
                    left: 0..1,
                    right: 1..1
                },
                FlowSeg::Span(1),
                FlowSeg::Span(2),
                FlowSeg::Columns {
                    left: 3..4,
                    right: 4..4
                },
            ]
        );
    }

    #[test]
    fn attachment_span_needs_image_flag_and_file_id() {
        assert!(is_span_block(&attachment(true, Some("f1"))));
        assert!(!is_span_block(&attachment(true, None)));
        assert!(!is_span_block(&attachment(false, Some("f1"))));
        // 不在名单：video / link-card / embedCard 不跨。
        assert!(!is_span_block(&blk("video", "")));
        assert!(!is_span_block(&blk("link-card", "")));
        assert!(!is_span_block(&blk("embedCard", "")));
        assert!(is_span_block(&blk("imageTextRow", "")));
    }
}
