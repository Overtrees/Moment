import SwiftUI
import UIKit

// ── 状态栏字色·背景采样生效层（fix_statusbar_sampling）──
// 决策单点：全应用状态栏字色只经 MomentStatusBar
// .evaluate 求值——采样状态栏后方当前生效的背景色，
// 按当前 trait 实时解析为具体色，交纯核心（Moment
// StatusBar.swift）按相对亮度判定。采样恒为查询时
// 现算：本层不缓存任何采样结果（唯一的静态状态是
// 页面登记栈与 Diag 去重键，都不参与决策）。
// 送达链：① 两个应用自有承载控制器（编辑/图片）
// override preferredStatusBarStyle 调 evaluate，系
// 统每次查询都拿现算值；② 根观察器（StatusBar
// TraitObserver）在 trait 变化当场触发承载链重估，
// 不等生命周期偶遇（用户实证：旧症挂后台重进即自
// 愈 = 值源正确、坏在送达）；③ 编辑页换底（bgColor
// 变更）由承载控制器订阅当场重估。平台自有承载面
// （首页/设置族/救援，背景同为根色单源 T.bg）的字
// 色由平台默认求值，其深浅两形态与采样判定逐值一
// 致（L 0.891→黑字、0→白字），全局结果一致。
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
        let lum = StatusBarCore.relativeLuminance(
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
                + "lum=\(String(format: "%.3f", lum)) "
                + "style=\(light ? "light" : "dark") "
                + "src=\(source)")
        }
        return light ? .lightContent : .darkContent
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
    static func requestRefresh(from view: UIView) {
        view.window?.rootViewController?
            .setNeedsStatusBarAppearanceUpdate()
        _ = evaluate(source: "trait",
                     background: currentBackground(),
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
