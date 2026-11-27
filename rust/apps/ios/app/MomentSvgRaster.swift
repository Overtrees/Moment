// ── SVG 光栅化（P2-7 根治，定案 fix_svg_image_page.md）──
// iOS ImageIO/UIImage(data:) 对 SVG 无光栅解码，
// 凡经 ImageLoader 漏斗的 SVG（图片页 / 内联图
// 块 / gallery 瓦 / 附件整幅 / 首页封面）在原生
// 恒失败占位。Web <img> 直渲 SVG 是真实能力、
// 非平台妥协，故在解码漏斗内按内容嗅探分流至
// 离屏 WKWebView 光栅化：禁脚本 + baseURL: nil
// 即 SVG-as-image 语义（禁脚本、禁外部资源、独
// 立文档）的原生等价实现。光栅化器形态照
// MathImageStore：单例 + 串行队列 + 单离屏
// webview 挂关键窗口 + 明暗覆写。

import Foundation
import UIKit
import WebKit

/// 内容嗅探：loader 只持有字节（URL 项可无
/// .svg 后缀、MIME 未接入 loader），故按内容
/// 判——跳过 BOM / 前导空白与 XML 序言（<?xml
/// …?>、注释、<!DOCTYPE …>），首个元素须为
/// <svg。二进制格式（GIF/PNG/JPEG…）天然不命
/// 中；嗅探置于 decodeImage 调用之前且仅命中
/// 时改道，GIF 逐帧路零影响。
func isSvgData(_ data: Data) -> Bool {
    guard !data.isEmpty else { return false }
    let s = String(decoding: data, as: UTF8.self)
    var i = s.startIndex
    if i < s.endIndex, s[i] == "\u{FEFF}" {
        i = s.index(after: i)
    }
    func rest() -> Substring { s[i...] }
    while true {
        while i < s.endIndex, s[i].isWhitespace {
            i = s.index(after: i)
        }
        guard i < s.endIndex, s[i] == "<" else {
            return false
        }
        if rest().hasPrefix("<?") {
            guard let e = s.range(of: "?>",
                                  range: i..<s.endIndex)
            else { return false }
            i = e.upperBound
        } else if rest().hasPrefix("<!--") {
            guard let e = s.range(of: "-->",
                                  range: i..<s.endIndex)
            else { return false }
            i = e.upperBound
        } else if rest().hasPrefix("<!DOCTYPE") {
            // DOCTYPE 可含内部子集 [ … ]，其中的
            // > 不作终结——按括号深度扫到真终结。
            var depth = 0
            var j = i
            var closed = false
            while j < s.endIndex {
                let c = s[j]
                if c == "[" { depth += 1 }
                else if c == "]" { depth -= 1 }
                else if c == ">", depth == 0 {
                    closed = true
                    break
                }
                j = s.index(after: j)
            }
            guard closed else { return false }
            i = s.index(after: j)
        } else if rest().hasPrefix("<!") {
            guard let e = s.range(of: ">",
                                  range: i..<s.endIndex)
            else { return false }
            i = e.upperBound
        } else {
            break
        }
    }
    guard rest().hasPrefix("<svg") else { return false }
    let j = s.index(i, offsetBy: 4)
    guard j < s.endIndex else { return false }
    let c = s[j]
    return c == ">" || c == "/" || c.isWhitespace
}

/// 根 <svg> 标签全文（引号内的 > 不作终结）。
func svgRootTag(_ text: String) -> String? {
    guard let r = text.range(of: "<svg") else {
        return nil
    }
    var j = r.lowerBound
    var quote: Character? = nil
    while j < text.endIndex {
        let c = text[j]
        if let q = quote {
            if c == q { quote = nil }
        } else if c == "\"" || c == "'" {
            quote = c
        } else if c == ">" {
            return String(text[r.lowerBound...j])
        }
        j = text.index(after: j)
    }
    return nil
}

/// 根标签属性值（双/单引号两式；属性名须非词
/// 字符起界，防 data-width 类误命中）。
func svgAttr(_ tag: String, _ name: String) -> String? {
    for q in ["\"", "'"] {
        let pat = "(?<![\\w-])\(name)\\s*=\\s*\(q)"
            + "([^\(q)]*)\(q)"
        guard let re = try? NSRegularExpression(
            pattern: pat),
              let m = re.firstMatch(
                in: tag,
                range: NSRange(tag.startIndex...,
                               in: tag)),
              let r = Range(m.range(at: 1), in: tag)
        else { continue }
        return String(tag[r])
    }
    return nil
}

/// 数值属性：纯数字或 px 后缀才算数（% 等相对
/// 单位不作自然尺寸），须 > 0。
func svgAttrNumber(_ tag: String,
                   _ name: String) -> CGFloat? {
    guard var v = svgAttr(tag, name) else { return nil }
    v = v.trimmingCharacters(in: .whitespaces)
    if v.hasSuffix("px") { v = String(v.dropLast(2)) }
    guard let d = Double(v), d > 0 else { return nil }
    return CGFloat(d)
}

/// 自然尺寸：width/height 数值属性（两项齐备）
/// 优先，缺失取 viewBox 宽高，再缺失回落浏览
/// 器 SVG-as-image 默认画布 300×150——used-
/// Fallback 供 Diag 记行（fix_svg_image_page
/// §3 登记口径）。
func svgNaturalSize(_ text: String)
    -> (size: CGSize, usedFallback: Bool) {
    let fallback = CGSize(width: 300, height: 150)
    guard let tag = svgRootTag(text) else {
        return (fallback, true)
    }
    if let w = svgAttrNumber(tag, "width"),
       let h = svgAttrNumber(tag, "height") {
        return (CGSize(width: w, height: h), false)
    }
    if let vb = svgAttr(tag, "viewBox") {
        let parts = vb.split(whereSeparator: {
            $0 == " " || $0 == ","
        }).compactMap { Double($0) }
        if parts.count == 4, parts[2] > 0,
           parts[3] > 0 {
            return (CGSize(width: CGFloat(parts[2]),
                           height: CGFloat(parts[3])),
                    false)
        }
    }
    return (fallback, true)
}

/// <svg>…</svg> 元素本体（剥 XML 序言后内联
/// 进包装 HTML）；无闭合标签时取 <svg 起的余
/// 段，畸形输入由渲染失败路收口。
func svgElement(_ text: String) -> String {
    guard let r = text.range(of: "<svg") else {
        return text
    }
    if let e = text.range(of: "</svg>",
                           options: .backwards) {
        return String(text[r.lowerBound..<e.upperBound])
    }
    return String(text[r.lowerBound...])
}

/// SVG 光栅化器（MathImageStore 同形态）：串行
/// 单 webview 逐个处理，完成回调恒在主线程发
/// 布；失败（畸形 SVG / WebView 失败）回调 nil，
/// 由 ImageLoader 既有失败行（fmt=svg）留痕。
final class SvgRasterizer: NSObject,
    WKNavigationDelegate {
    static let shared = SvgRasterizer()

    private struct Job {
        let html: String
        let natural: CGSize
        let frame: CGSize
        let done: (UIImage?) -> Void
    }

    private var queue: [Job] = []
    private var busy = false
    private var webView: WKWebView?
    private var current: Job?
    private var jobSeq = 0
    private var currentSeq = 0

    /// 入口（ImageLoader 汇合点调用）：状态只在
    /// 主队列收口（调用方可在任意队列）。
    func rasterize(data: Data,
                   completion: @escaping (UIImage?) -> Void) {
        let work = {
            self.enqueue(data: data, done: completion)
        }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async(execute: work) }
    }

    private func enqueue(data: Data,
                         done: @escaping (UIImage?) -> Void) {
        let text = String(decoding: data, as: UTF8.self)
        let nat = svgNaturalSize(text)
        if nat.usedFallback {
            DiagLog.shared.logOnce(
                "svg-nat-fallback", .info,
                "SVG 光栅化自然尺寸缺失，回落 300x150")
        }
        // 位图按自然尺寸 × rasterScale 渲染；web-
        // view 帧（点）= 目标像素 / 设备倍率，快照
        // 实际像素与目标像素对齐（设备差异在回填
        // scale 时以实际像素为准再吸收）。
        let scale = Self.rasterScale(for: nat.size)
        let screen = UIScreen.main.scale
        let frame = CGSize(
            width: max(nat.size.width * scale / screen, 1),
            height: max(nat.size.height * scale / screen, 1))
        let html = "<meta name=\"viewport\" content=\""
            + "width=\(frame.width), "
            + "height=\(frame.height)\">"
            + "<style>html,body{margin:0;padding:0;"
            + "background:transparent}"
            + "svg{width:\(frame.width)px;"
            + "height:\(frame.height)px;"
            + "display:block}</style>"
            + svgElement(text)
        queue.append(Job(html: html, natural: nat.size,
                         frame: frame, done: done))
        pump()
    }

    /// 光栅倍率：长边 ≤ 4096px、总像素 ≤ 16M
    /// 的上限内尽量 4（对齐图片页最大缩放 base
    /// ×4 的清晰度需求）。
    static func rasterScale(for size: CGSize) -> CGFloat {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        var s = min(4, 4096 / max(w, h))
        let total = w * h * s * s
        if total > 16_000_000 {
            s *= (16_000_000 / total).squareRoot()
        }
        return max(s, 0.01)
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        busy = true
        jobSeq += 1
        currentSeq = jobSeq
        current = job
        let wv = ensureWebView()
        wv.overrideUserInterfaceStyle = UITraitCollection
            .current.userInterfaceStyle == .dark
            ? .dark : .light
        wv.frame = CGRect(origin: CGPoint(x: -4000,
                                          y: -4000),
                          size: job.frame)
        wv.loadHTMLString(job.html, baseURL: nil)
    }

    private func ensureWebView() -> WKWebView {
        if let wv = webView { return wv }
        let cfg = WKWebViewConfiguration()
        // SVG-as-image 沙箱语义：禁脚本；外部资
        // 源经 loadHTMLString 的 baseURL: nil 封
        // 死（相对引用无基可解、与规范一致）。
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        cfg.defaultWebpagePreferences = prefs
        let wv = WKWebView(frame: CGRect(
            x: -4000, y: -4000, width: 300, height: 150),
            configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = self
        // 离屏挂载（快照需要渲染树）：挂关键窗
        // 口、移出可视区，不入任何页面层级。
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let win = scenes.flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
        win?.addSubview(wv)
        webView = wv
        return wv
    }

    private func finish(_ img: UIImage?) {
        guard let job = current else { return }
        current = nil
        busy = false
        job.done(img)
        pump()
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        guard current != nil else { return }
        let seq = currentSeq
        let cfg = WKSnapshotConfiguration()
        cfg.rect = webView.bounds
        webView.takeSnapshot(with: cfg) { [weak self] img, _ in
            guard let self, self.current != nil,
                  self.currentSeq == seq else { return }
            guard let img, let cg = img.cgImage else {
                self.finish(nil)
                return
            }
            // scale 回填使 image.size（点）恒 = 自
            // 然尺寸：像素宽 / 自然宽即真实倍率
            // （以快照实际像素为准，设备倍率差异
            // 自动吸收）——ZoomableImageView 的
            // fit 规则与 IMGPAGE nat=（点 × scale
            // = 像素）口径自动守恒。
            let scale = CGFloat(cg.width)
                / self.current!.natural.width
            self.finish(UIImage(cgImage: cg,
                                scale: scale,
                                orientation: .up))
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation
                     navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }
}
