import SwiftUI
import UIKit

// ── 状态栏字色·背景采样生效层（fix_statusbar_sampling，
// 三轮收口 fix_statusbar_render_sample）──
// 分层（用户 2026-11-28 08:43 定性）：模式层是基
// 础——主题令牌 dyn、trait 变化链、本层静态登记
// （provider 栈 + evaluate 按 trait 解析登记色判
// 定）保留其位，管「模式给的底色」并在渲染不可
// 得时兜底；增强层在其上——renderedStyle 先问带
// 区渲染采样器（MomentStatusBarRender.swift），
// 以状态栏带区实际渲染像素的平均 L* 精细化判定，
// 专治模式判不了的面（彩色备忘底、图片滚入带区、
// 开屏渐变）。决策单点仍在本层：全应用承载（根
// 容器/编辑/图片/开屏）的 preferredStatusBarStyle
// 一律经 renderedStyle 求值，判定度量同为纯核心
// CIELAB L*（阈值见核心注）。本层不缓存
// 采样结果（静态状态只有页面登记栈与 Diag 去重
// 键，都不参与决策；渲染缓存归采样器且恒以指纹
// 与新鲜度自证）。
// 送达链：① 各承载 override 查询时现算；② 根观
// 察器（StatusBarTraitObserver）在 trait 变化当
// 场触发重采样 + 承载链重估——模式切换是一级触
// 发源，不等生命周期偶遇（用户实证：旧症挂后台
// 重进即自愈 = 值源正确、坏在送达）；③ 编辑页换
// 底（bgColor 变更）由承载订阅当场触发重采样。
enum MomentStatusBar {
    typealias BackgroundProvider = () -> UIColor

    /// 在顶页面背景登记栈：承载控制器 appear 登记、
    /// disappear 注销（导航覆盖/返回成对进出）；观察
    /// 器的根级采样以栈顶为当前生效背景。
    private static var providers:
        [(id: ObjectIdentifier, provider: BackgroundProvider)]
        = []

    /// Diag 去重键（仅防查询刷屏，不参与决策）。
    private static var lastLoggedKey: String?

    static func registerCurrent(
        id: ObjectIdentifier,
        provider: @escaping BackgroundProvider) {
        providers.removeAll { $0.id == id }
        providers.append((id, provider))
    }

    static func clearCurrent(id: ObjectIdentifier) {
        providers.removeAll { $0.id == id }
    }

    /// 当前生效背景：栈顶页面登记面优先，否则根背
    /// 景单源 T.bg（背景层级模型：根色是唯一背景色
    /// 源，首页/设置族/救援/图片页带区后方均为它）。
    static func currentBackground() -> UIColor {
        providers.last?.provider() ?? T.bgUI
    }

    /// 采样求值（唯一决策点）：背景色按给定 trait 解
    /// 析 → 相对亮度 → 字色样式；判定变化时打 Diag
    /// 一行（bg 采样值/lum 三位小数/style/src 来源），
    /// 供真机往返终判对读。
    static func evaluate(source: String,
                         background: UIColor,
                         trait: UITraitCollection)
        -> UIStatusBarStyle {
        let resolved = background.resolvedColor(with: trait)
        var r: CGFloat = 0, g: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0
        if !resolved.getRed(&r, green: &g, blue: &b,
                            alpha: &a) {
            // 非 RGB 色域兜底：经 sRGB 转换再取分量
            // （本应用令牌均为 RGB 动态色，此支只防
            // 未来图案色令牌静默归零）。
            if let cg = resolved.cgColor.converted(
                to: CGColorSpace(
                    name: CGColorSpace.sRGB)!,
                intent: .defaultIntent, options: nil),
               let comps = cg.components,
               comps.count >= 3 {
                r = comps[0]; g = comps[1]; b = comps[2]
            }
        }
        let rd = Double(r), gd = Double(g), bd = Double(b)
        let lst = StatusBarCore.lightness(
            r: rd, g: gd, b: bd)
        let light = StatusBarCore.prefersLightContent(
            r: rd, g: gd, b: bd)
        let hex = String(
            format: "#%02X%02X%02X",
            Int((rd * 255).rounded()),
            Int((gd * 255).rounded()),
            Int((bd * 255).rounded()))
        let key = "\(hex)|\(light)"
        if key != lastLoggedKey {
            lastLoggedKey = key
            DiagLog.shared.log(.info,
                "STATUSBAR bg=\(hex) "
                + "lst=\(String(format: "%.1f", lst)) "
                + "style=\(light ? "light" : "dark") "
                + "src=\(source)")
        }
        return light ? .lightContent : .darkContent
    }

    /// 渲染采样求值（三轮主路径，增强层）：先问带
    /// 区渲染采样器取当前承载窗口的实渲染平均
    /// L*，同阈值判定应答并回记送达；Diag 行以
    /// bg=render 与静态路的 bg=#RRGGBB 区分来源
    /// （cov = 图片页几何覆盖率对读值，无则 -）。
    /// 采样不可得（窗口未就绪/首帧前/退后台/带区
    /// 高 0）回落模式层静态求值 evaluate（登记色
    /// 兜底，src 同名、bg 为色值，真机对读可辨）。
    /// 去重键 = 路径 + 来源 + 判定：同判定不重复
    /// 记行，翻转必记一行。
    static func renderedStyle(source: String,
                              carrierView: UIView,
                              fallback: UIColor,
                              trait: UITraitCollection)
        -> UIStatusBarStyle {
        if let l = BandRenderSampler.shared.lightness(
            for: carrierView.window) {
            let light = StatusBarCore
                .prefersLightContent(lightness: l)
            BandRenderSampler.shared.markDelivered(
                light: light)
            let key = "R|\(source)|\(light)"
            if key != lastLoggedKey {
                lastLoggedKey = key
                let cov = BandRenderSampler.shared
                    .coverage.map {
                        String(format: "%.2f", $0)
                    } ?? "-"
                DiagLog.shared.log(.info,
                    "STATUSBAR bg=render "
                    + "lst=\(String(format: "%.1f", l)) "
                    + "cov=\(cov) "
                    + "style=\(light ? "light" : "dark") "
                    + "src=\(source)")
            }
            return light ? .lightContent : .darkContent
        }
        return evaluate(source: source,
                        background: fallback,
                        trait: trait)
    }

    /// 以当前登记面采样（观察器/根级调用点）。
    static func style(source: String,
                      trait: UITraitCollection)
        -> UIStatusBarStyle {
        evaluate(source: source,
                 background: currentBackground(),
                 trait: trait)
    }

    /// 送达单点：强制窗口承载链立即重估状态栏（各承
    /// 载控制器在被查询时现算采样值），并以当前登记
    /// 面补一行采样证据。由根观察器在 trait 变化当
    /// 场调用——旧症「浅→深回程无人扳回」的根治点。
    /// 三轮补：模式切换是一级触发源——先驱动渲染采
    /// 样器按新模式实况重采样（令牌随 trait 重解
    /// 析、带区像素随之变），再戳承载链；顺带重试
    /// 根承载安装（节拍之一）。
    static func requestRefresh(from view: UIView) {
        StatusBarRootInstaller.installIfNeeded(
            from: view)
        BandRenderSampler.shared.refresh(from: view)
        view.window?.rootViewController?
            .setNeedsStatusBarAppearanceUpdate()
        _ = renderedStyle(source: "trait",
                          carrierView: view,
                          fallback: currentBackground(),
                          trait: view.traitCollection)
    }
}

/// 根观察器挂载点（@main 根 ZStack 的 background）：
/// 零尺寸、不参与命中，只做 trait 变化的送达触发。
struct StatusBarTraitObserver: UIViewRepresentable {
    func makeUIView(context: Context)
        -> StatusBarObserverView {
        let v = StatusBarObserverView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: StatusBarObserverView,
                      context: Context) {}
}

/// trait 观察视图：监听外观变化并以 lastStyle 去
/// 重成「每次真变化恰触发一次送达」；变化只认
/// userInterfaceStyle，其余 trait 变化不惊动状态
/// 栏。监听路取 traitCollectionDidChange（iOS 13+
/// 经典路）：iOS 17 的 registerForTraitChanges 在
/// 本机 Linux 工具链的 UIKit 链接桩中无符号（首
/// 次链接实证 undefined symbol、冒烟 [smoke 3/4]
/// 红），部署目标 16.0 下亦需可用性分支——经典路
/// 在现行系统上仍由 UIKit 正常投递，且本机制自
/// 带 Diag 采样行，投递若失效会即时在日志中显形
/// （STATUSBAR 行缺失即证据），不静默。
final class StatusBarObserverView: UIView {
    private var lastStyle: UIUserInterfaceStyle
        = .unspecified

    override func didMoveToWindow() {
        super.didMoveToWindow()
        lastStyle = traitCollection.userInterfaceStyle
    }

    override func traitCollectionDidChange(
        _ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if let previous,
           previous.userInterfaceStyle
            != traitCollection.userInterfaceStyle {
            noteTraitChange()
        }
    }

    private func noteTraitChange() {
        let now = traitCollection.userInterfaceStyle
        guard now != lastStyle else { return }
        lastStyle = now
        MomentStatusBar.requestRefresh(from: self)
    }
}
