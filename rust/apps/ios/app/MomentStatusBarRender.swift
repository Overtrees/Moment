import SwiftUI
import UIKit

// ── 状态栏字色·带区渲染采样器 + 根承载（三轮根治
// fix_statusbar_render_sample）──────────────────
// 分层（用户 2026-11-28 08:43 定性）：状态栏字色
// 是两层机制——
//   · 模式层（基础，不拆）：主题令牌 dyn、trait 变
//     化链、模式派生的静态登记色（MomentStatusBar
//     的 provider 栈 + evaluate）。它决定「模式给
//     的底色是什么」，并在渲染不可得的瞬间兜底；
//   · 增强层（本文件）：在模式之上以状态栏带区的
//     实际渲染像素做精细化判定，专治模式判不了的
//     面——彩色备忘底、图片滚入带区、开屏渐变。
// 三轮把二轮的两条特路（图片页 ImageBandSampler、
// 开屏公式色）收口为全页面统一的渲染采样单点：
// 首页/设置族/编辑/图片/救援/开屏的承载查询一律先
// 问本采样器（MomentStatusBar.renderedStyle），采
// 样不可得（窗口未就绪/首帧前/退后台）才回落模式
// 层静态求值，Diag 以 bg=render 与 bg=#RRGGBB 区
// 分两路。判定度量不变（纯核心 CIELAB L*，阈值
// 字面独占核心文件），本文件只产出采样 L*、不做
// 判定（判定单点仍在 MomentStatusBar）。
//
// 采样方式：把 window 的带区条带以 drawHierarchy
// 实渲染进小位图（与屏幕合成逐像素一致，含当前
// 页面内容、滚动覆盖、一切图层，免手工坐标/方向
// 换算），缩绘 16×4 逐像素算 L* 平均；同批像素算
// 指纹（FNV-1a），指纹不变即像素未变、不重算不
// 戳送达。成本：单次 = 窗宽×带区高（约 1179×177
// px @3x ≈ 0.21MP）的带区限幅绘制 + 64 像素读
// 取，毫秒级；频率受控——查询时按需（距上次采样
// <90ms 用缓存）+ 离散事件触发 + 图片滚动 90ms
// 节流，无定时器、无逐帧轮询。退后台停采样。

final class BandRenderSampler: NSObject {
    static let shared = BandRenderSampler()

    /// 最近一次渲染采样的带区平均感知明度（nil =
    /// 尚无渲染采样/采样不可得，承载回落模式层）。
    private(set) var currentLightness: Double?
    /// 最近一次图片页几何覆盖率（Diag 附加字段；
    /// 非图片页语境为 nil）。覆盖率由纯核心
    /// StatusBarCore.coverage 计算（图可见矩形 ∩
    /// 滚动视图与带区矩形交叠），仅作对读证据——
    /// 渲染采样本身已天然合成覆盖与未覆盖部分，
    /// 不再以覆盖率作采样门（二轮的零扰动性质由
    /// 「同像素同判定」结构性保持）。
    private(set) var coverage: Double?

    private weak var window: UIWindow?
    private weak var imageScrollView: UIScrollView?
    private weak var imageView: UIImageView?
    private var fingerprint: Int?
    private var lastSampleAt: CFTimeInterval = 0
    private var trailing: DispatchWorkItem?
    private var deliveredLight: Bool?
    private var suspended = false

    private override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil)
        nc.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
    }

    @objc private func appDidEnterBackground() {
        // 退后台停采样：取消尾随、查询一律回落模
        // 式层（后台无状态栏判定需求，前台恢复后
        // 由触发面重新采样接管）。
        suspended = true
        trailing?.cancel()
        trailing = nil
    }

    @objc private func appWillEnterForeground() {
        suspended = false
        lastSampleAt = 0
    }

    /// 窗口登记（根承载安装/任一触发面顺带调用）：
    /// 换窗即旧窗采样作废（多窗各自采样，不串窗）。
    func noteWindow(_ w: UIWindow) {
        if window !== w {
            window = w
            fingerprint = nil
            currentLightness = nil
            lastSampleAt = 0
        }
    }

    /// 查询面（承载 preferredStatusBarStyle 调用）：
    /// 缓存新鲜（<90ms）直接用；过期即当场实渲染
    /// 一次——保证任一次判定都来自实际渲染像素或
    /// 明确的不可得回落，无陈旧值冒充实况。
    func lightness(for window: UIWindow?) -> Double? {
        guard !suspended, let window else { return nil }
        noteWindow(window)
        if currentLightness != nil,
           CACurrentMediaTime() - lastSampleAt < 0.09 {
            return currentLightness
        }
        return renderNow(window)
    }

    /// 事件触发面（页面出现/模式切换/编辑换底/开
    /// 屏布局落定）：与查询面同路，判定翻转的戳送
    /// 达在 renderNow 内完成。
    func refresh(from view: UIView) {
        guard let w = view.window else { return }
        _ = lightness(for: w)
    }

    /// 送达登记（生效层每次以渲染判定应答后回
    /// 记）：采样翻转时据此判断要不要戳承载链重
    /// 估——未送达过的判定不戳（在途查询自会读
    /// 到），已送达判定被新采样推翻才戳。
    func markDelivered(light: Bool) {
        deliveredLight = light
    }

    // ── 图片页滚动喂入（二轮 ImageBandSampler 并
    // 入）：几何覆盖率 + 90ms 节流 + 收尾实算 ──

    /// 滚动/缩放/布局事件入口（ZoomableImageView
    /// 的 Coordinator 转发）：记下视图引用、算覆
    /// 盖率、按节流实渲染。
    func noteImageScroll(_ sv: UIScrollView,
                         _ iv: UIImageView) {
        imageScrollView = sv
        imageView = iv
        updateCoverage(sv, iv)
        let now = CACurrentMediaTime()
        if now - lastSampleAt >= 0.09 {
            trailing?.cancel()
            trailing = nil
            if let w = sv.window { _ = renderNow(w) }
        } else if trailing == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.trailing = nil
                if let w = self.imageScrollView?.window {
                    _ = self.renderNow(w)
                }
            }
            trailing = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.09, execute: work)
        }
    }

    /// 滚动/缩放收尾：取消尾随、立即实算一次（终
    /// 态值不许停在节流中间态）。
    func noteImageScrollEnd() {
        trailing?.cancel()
        trailing = nil
        if let w = imageScrollView?.window {
            _ = renderNow(w)
        }
    }

    /// 图片页离开：覆盖率与视图引用作废（带区回
    /// 到下层页面，采样由其触发面/查询面接管）。
    func invalidateImage() {
        trailing?.cancel()
        trailing = nil
        imageScrollView = nil
        imageView = nil
        coverage = nil
    }

    private func updateCoverage(_ sv: UIScrollView,
                                _ iv: UIImageView) {
        guard let window = sv.window else {
            coverage = nil
            return
        }
        let bandH = window.safeAreaInsets.top
        guard bandH > 0 else {
            coverage = nil
            return
        }
        let band = StatusBarCore.SBRect(
            x: 0, y: 0, w: Double(window.bounds.width),
            h: Double(bandH))
        let ivWin = iv.convert(iv.bounds, to: window)
        let svWin = sv.convert(sv.bounds, to: window)
        let visible = StatusBarCore.intersection(
            rect(ivWin), rect(svWin))
        coverage = StatusBarCore.coverage(
            band: band, content: visible)
    }

    private func rect(_ r: CGRect)
        -> StatusBarCore.SBRect {
        StatusBarCore.SBRect(
            x: Double(r.origin.x), y: Double(r.origin.y),
            w: Double(r.size.width),
            h: Double(r.size.height))
    }

    // ── 实渲染 ──────────────────────────────────

    private func renderNow(_ window: UIWindow)
        -> Double? {
        lastSampleAt = CACurrentMediaTime()
        guard let sample = Self.stripSample(
            window: window) else {
            // 带区高为 0/渲染失败：采样不可得，作
            // 废缓存回落模式层，不拿旧值冒充实况。
            currentLightness = nil
            fingerprint = nil
            return nil
        }
        if sample.fingerprint == fingerprint,
           let cur = currentLightness {
            return cur
        }
        fingerprint = sample.fingerprint
        currentLightness = sample.lightness
        let light = StatusBarCore.prefersLightContent(
            lightness: sample.lightness)
        if let delivered = deliveredLight,
           delivered != light {
            window.rootViewController?
                .setNeedsStatusBarAppearanceUpdate()
        }
        return sample.lightness
    }

    /// 带区条带实渲染：把 window 全幅绘进「宽 ×
    /// 带区高」画布（画布外自动裁切，只剩带区条
    /// 带），再缩绘到 16×4 位图逐像素算 L* 平均
    /// 并对原始字节算指纹。与二轮 imgToneHex/
    /// ImageBandSampler 的取色口径同路（ctx.draw
    /// 缩绘取样）。
    private static func stripSample(window: UIWindow)
        -> (lightness: Double, fingerprint: Int)? {
        let bandH = window.safeAreaInsets.top
        guard bandH > 0,
              window.bounds.width > 0 else { return nil }
        let full = UIGraphicsImageRenderer(
            size: CGSize(width: window.bounds.width,
                         height: bandH))
        let strip = full.image { _ in
            window.drawHierarchy(
                in: CGRect(origin: .zero,
                           size: window.bounds.size),
                afterScreenUpdates: false)
        }
        guard let cg = strip.cgImage else { return nil }
        let w = 16, h = 4
        var px = [UInt8](
            repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo
                .premultipliedLast.rawValue)
        guard let ctx else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0,
                                width: w, height: h))
        var sum = 0.0
        var n = 0
        var fp: UInt64 = 1469598103934665603
        for i in 0..<(w * h) {
            for k in 0..<4 {
                fp = (fp ^ UInt64(px[i * 4 + k]))
                    &* 1099511628211
            }
            // premultipliedLast：不透明像素 alpha
            // =255；透明像素不计（带区恒有不透明
            // 内容垫底，理论上不出现）。
            guard px[i * 4 + 3] > 0 else { continue }
            sum += StatusBarCore.lightness(
                r: Double(px[i * 4]) / 255,
                g: Double(px[i * 4 + 1]) / 255,
                b: Double(px[i * 4 + 2]) / 255)
            n += 1
        }
        guard n > 0 else { return nil }
        return (sum / Double(n), Int(bitPattern:
            UInt(truncatingIfNeeded: fp)))
    }
}

// ── 根承载（首页/设置族/救援的决定面）──────────
// 根页面此前没有应用自有承载：状态栏由平台根
// UIHostingController 以 .default（trait 映射）
// 内部求值——模式层结论与根背景两形态逐值一致才
// 一直无症状，但决定面不在应用采样单点内，用户
// 三轮口径（所有页面渲染采样）下必须收口。本容
// 器把 SwiftUI 根承载整体接入包含层级：容器自身
// 即根页决定面（不 override childViewController
// ForStatusBarStyle → 默认 nil，决定止于容器），
// 其 preferredStatusBarStyle 走统一渲染采样求值
// （src=root）；编辑/图片承载在包含链内层、开屏
// 以 captures 呈现，各自 override 同问采样器，
// 全应用无第二决定面。容器只决定状态栏字色，不
// 碰方向（开屏方向锁在开屏承载，SB-8 不变）、不
// 碰布局（子承载视图满铺容器、 autoresizing 跟
// 随，几何逐值不变）。

final class StatusBarRootContainerController:
    UIViewController {
    override var preferredStatusBarStyle:
        UIStatusBarStyle {
        MomentStatusBar.renderedStyle(
            source: "root",
            carrierView: view,
            fallback: MomentStatusBar.currentBackground(),
            trait: traitCollection)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        BandRenderSampler.shared.refresh(from: view)
    }
}

/// 根承载安装器：探针入窗时若 window 根仍是平台
/// 承载（SwiftUI 的 UIHostingController），把其
/// 整体接入容器并把容器置为 window 根；已装/根
/// 被呈现占用（开屏呈现中）时跳过，由后续节拍
/// （探针 update、trait 触发、开屏卸载完成）重试。
/// 全程同步完成、无中间渲染帧；根形态异常（非
/// 平台承载且非本容器）只留痕一次、不强装。
enum StatusBarRootInstaller {
    private static weak var container:
        StatusBarRootContainerController?
    private static var skipLogged = false

    static func installIfNeeded(from view: UIView) {
        guard let window = view.window else { return }
        BandRenderSampler.shared.noteWindow(window)
        guard let root = window.rootViewController
        else { return }
        if root is StatusBarRootContainerController {
            return
        }
        if let container, root === container { return }
        guard root.presentedViewController == nil
        else { return }
        let name = String(describing: type(of: root))
        guard name.contains("HostingController")
        else {
            if !skipLogged {
                skipLogged = true
                DiagLog.shared.log(.warn,
                    "STATUSBAR root carrier skipped "
                    + "root=\(name)")
            }
            return
        }
        let c = StatusBarRootContainerController()
        c.view.backgroundColor = .clear
        container = c
        window.rootViewController = c
        c.addChild(root)
        c.view.addSubview(root.view)
        root.view.frame = c.view.bounds
        root.view.autoresizingMask = [
            .flexibleWidth, .flexibleHeight]
        root.didMove(toParent: c)
        DiagLog.shared.log(.info,
            "STATUSBAR root carrier installed")
        BandRenderSampler.shared.refresh(from: c.view)
    }
}

/// 根承载挂载点（@main 根 background，与状态栏观
/// 察器/开屏呈现器同层）：零尺寸、不参与命中，只
/// 在入窗与根更新节拍驱动安装器。
struct StatusBarRootMount: UIViewRepresentable {
    func makeUIView(context: Context) -> MountView {
        let v = MountView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: MountView,
                      context: Context) {
        StatusBarRootInstaller.installIfNeeded(from: v)
    }

    final class MountView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                StatusBarRootInstaller
                    .installIfNeeded(from: self)
            }
        }
    }
}
