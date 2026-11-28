import UIKit
import AVFoundation

// ── 状态栏像素保底采样器（impl_statusbar_native_
// adaptation）──────────────────────────────────
// 用户 2026-11-28 方案第二条：像素只做保底——仅
// 数据层回答不了的媒体面才读实际像素，且只读一
// 个点。本文件是全仓唯一的像素读取面，三采样器
// 按介质分工：
//   · 图片：CGImage 1×1 裁剪（同步、低开销）；
//   · 图层/渐变：CALayer.render(in:) 离屏渲染读
//     目标点所在像素；
//   · 视频：AVPlayerItemVideoOutput 取当前帧中
//     心像素。
// 红线：严禁整屏截图——本文件不出现 drawHierarchy
// / snapshotView / UIWindow 引用（verify [53]
// SB-12 锁）；采样点恒为调用方给定的单点（状态
// 栏带中心），不在此放大采样面。采样结果只喂判
// 定引擎的保底面，不扩散回数据面。
//
// 结果语义（fix_statusbar_sampling_integrity，
// 对照壳 App 采样翻车案 L1/L2）：采样不许静默
// 失败——imagePoint 回三态结果（实测 / 未覆盖
// / 未就绪 / 失败+原因码），引擎按态消费、Diag
// 读数按态分账；旧「失败一律回 nil、与未覆盖
// 不可区分」的形态退役（SB-18 锁）。

/// 采样失败原因码（引擎 Diag 读数 px=failed:<码>
/// 直用 rawValue，分账「没取到」的具体形态）。
enum StatusBarPixelFailure: String {
    /// 图无 CGImage（SVG 等矢量图 / 未解码出栅格）。
    case noRaster = "noraster"
    /// 显示面尺寸退化（宽或高 < 1 像素）。
    case degenerate = "degenerate"
    /// 1×1 裁剪或回读上下文失败。
    case crop = "crop"
    /// 采样点像素全透明，无色可读。
    case transparent = "transparent"
}

/// 采样结果（引擎消费面）：实测值 / 未覆盖（点
/// 不在图面可见内容上——带下实景非图，数据色
/// 即真值、非失败）/ 未就绪（图或视图未备好，
/// 引擎暂缓判定）/ 失败（带原因码，引擎兜底且
/// 读数写明）。
enum StatusBarPixelOutcome {
    case measured(UIColor)
    case notCovered
    case notReady
    case failed(StatusBarPixelFailure)
}

enum StatusBarPixel {

    /// 图片点采样：pointInImageView 为图视图本地
    /// 坐标（点）。图视图帧与图自然尺寸同构（本
    /// 应用图片页口径），按 image.scale 换算到显
    /// 示像素面，再按 imageOrientation 的 EXIF 方
    /// 向映射回原始像素面，cropping 1×1 取色。
    /// 点落在图外回 .notCovered、图无 CGImage 等
    /// 取色失败回 .failed（原因码），不回含糊的
    /// 空值。动图取首帧（UIImage.cgImage 口径），
    /// 带区判定以首帧色调为准。
    static func imagePoint(image: UIImage,
                           pointInImageView: CGPoint)
        -> StatusBarPixelOutcome {
        guard let cg = image.cgImage
        else { return .failed(.noRaster) }
        let dispW = image.size.width * image.scale
        let dispH = image.size.height * image.scale
        guard dispW >= 1, dispH >= 1
        else { return .failed(.degenerate) }
        let dx = pointInImageView.x * image.scale
        let dy = pointInImageView.y * image.scale
        guard dx >= 0, dy >= 0, dx < dispW, dy < dispH
        else { return .notCovered }
        // 显示面归一化坐标 → 原始像素面归一化坐标
        // （EXIF 方向标准映射，两面均为 y 向下）。
        let u = Double(dx / dispW)
        let v = Double(dy / dispH)
        let ru: Double
        let rv: Double
        switch image.imageOrientation {
        case .up:            (ru, rv) = (u, v)
        case .down:          (ru, rv) = (1 - u, 1 - v)
        case .left:          (ru, rv) = (1 - v, u)
        case .right:         (ru, rv) = (v, 1 - u)
        case .upMirrored:    (ru, rv) = (1 - u, v)
        case .downMirrored:  (ru, rv) = (u, 1 - v)
        case .leftMirrored:  (ru, rv) = (v, u)
        case .rightMirrored: (ru, rv) = (1 - v, 1 - u)
        @unknown default:    (ru, rv) = (u, v)
        }
        let rx = min(max(Int(ru * Double(cg.width)), 0),
                     cg.width - 1)
        let ry = min(max(Int(rv * Double(cg.height)), 0),
                     cg.height - 1)
        guard let crop = cg.cropping(
            to: CGRect(x: rx, y: ry, width: 1, height: 1))
        else { return .failed(.crop) }
        return readSinglePixel(cg: crop)
    }

    /// 图层点采样：把 layer 在 point（layer 本地
    /// 坐标）处的内容离屏渲染进 1×1 上下文，读该
    /// 点所在像素。只渲染目标 layer 子树，不是整
    /// 屏抓取——状态栏本身不在任何应用 layer 内，
    /// 无自反馈之虞。
    static func layerPoint(layer: CALayer,
                           point: CGPoint) -> UIColor? {
        let px = UnsafeMutablePointer<UInt8>
            .allocate(capacity: 4)
        defer { px.deallocate() }
        px.initialize(repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: px, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo
                .premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: -floor(point.x),
                        y: -floor(point.y))
        layer.render(in: ctx)
        return readPremultiplied(px)
    }

    /// 视频帧采样：自 AVPlayerItemVideoOutput 取
    /// time 时刻的当前帧，读帧中心像素。像素缓冲
    /// 口径为 32BGRA（输出属性由消费方按此请求，
    /// 本采样器只读不建）。无新帧/格式不符回 nil。
    static func videoCenter(
        output: AVPlayerItemVideoOutput,
        time: CMTime) -> UIColor? {
        guard let pb = output.copyPixelBuffer(
            forItemTime: time, itemTimeForDisplay: nil)
        else { return nil }
        guard CVPixelBufferGetPixelFormatType(pb)
                == kCVPixelFormatType_32BGRA
        else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        }
        guard let base = CVPixelBufferGetBaseAddress(pb)
        else { return nil }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        guard w > 0, h > 0 else { return nil }
        let p = base.advanced(by: (h / 2) * bpr + (w / 2) * 4)
            .assumingMemoryBound(to: UInt8.self)
        return UIColor(red: CGFloat(p[2]) / 255,
                       green: CGFloat(p[1]) / 255,
                       blue: CGFloat(p[0]) / 255,
                       alpha: 1)
    }

    /// 1×1 CGImage 读像素（经 1×1 上下文回读，
    /// 裁剪图本身即 1×1、无重采样）：上下文失败
    /// 与全透明像素分开报码，不合并成含糊空值。
    private static func readSinglePixel(cg: CGImage)
        -> StatusBarPixelOutcome {
        let px = UnsafeMutablePointer<UInt8>
            .allocate(capacity: 4)
        defer { px.deallocate() }
        px.initialize(repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: px, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo
                .premultipliedLast.rawValue)
        else { return .failed(.crop) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0,
                                 width: 1, height: 1))
        guard let color = readPremultiplied(px)
        else { return .failed(.transparent) }
        return .measured(color)
    }

    /// 预乘 RGBA 字节 → 非预乘 UIColor（a=0 无色
    /// 可读，回 nil）。
    private static func readPremultiplied(
        _ px: UnsafeMutablePointer<UInt8>) -> UIColor? {
        let a = CGFloat(px[3]) / 255
        guard a > 0 else { return nil }
        return UIColor(red: CGFloat(px[0]) / 255 / a,
                       green: CGFloat(px[1]) / 255 / a,
                       blue: CGFloat(px[2]) / 255 / a,
                       alpha: 1)
    }
}
