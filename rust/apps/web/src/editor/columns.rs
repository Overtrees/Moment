//! 双栏分界：规范估高 + layout 锚归一（原版 editorBlockHeight
//! 回退表与 normalizeColumnLayout 口径）。分界是文档内容
//! 的确定性纯函数，不依赖实测高、加载状态或会话。

use super::*;

/// 纯文本多行粘贴：首行并入当前块，中间行成新块，末行带上
/// 光标后的原内容。当前块的 DOM 由 dom_set 回写对齐。
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
