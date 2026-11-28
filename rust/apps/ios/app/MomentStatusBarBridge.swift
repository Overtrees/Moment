import SwiftUI
import UIKit

// ── 状态栏字色·背景采样生效层（fix_statusbar_sampling）──
// 机制（回退后口径，fix_statusbar_rollback_all）：
// 模式层是唯一基础——主题令牌 dyn、trait 变化
// 链、本层静态登记（provider 栈 + evaluate 按
// trait 解析登记色判定）管「模式给的底色」。决
// 策单点在本层：各应用自有承载（编辑/图片/开屏）
// 的 preferredStatusBarStyle 一律经 evaluate 求
// 值，判定度量为纯核心 CIELAB L*（阈值见核心
// 注）。本层不缓存采样结果（静态状态只有页面登
// 记栈与 Diag 去重键，都不参与决策）。
// 沿革：三轮曾在本层之上加带区实渲染采样（承
// 载先问渲染采样器、以带区像素精细化判定），
// 并新建根承载容器收口根页面；用户 2026-11-28 装机
// 实报开屏三症状（闪白/透出首页空态/结束闪黑，
// 归因根承载换根）后裁定全页回退——渲染采样整
// 层拆除、根承载容器一并拆除，根页面恢复平台
// 承载决定（其 .default trait 映射与根背景双形
// 态的 evaluate 判定逐值一致，二轮全页面审计结
// 论），本层扶正为唯一机制。
// 送达链：① 各承载 override 查询时现算；② 根观
// 察器（StatusBarTraitObserver）在 trait 变化当
// 场触发承载链重估——模式切换是一级触发源，不
// 等生命周期偶遇（用户实证：旧症挂后台重进即自
// 愈 = 值源正确、坏在送达）；③ 编辑页换底
// （bgColor 变更）由承载订阅当场触发重估。
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
    /// 析 → 感知明度 L* → 字色样式；判定变化时打
    /// Diag 一行（bg 采样值/lst 一位小数/style/src
    /// 来源），供真机往返终判对读。
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
    /// 沿革：三轮曾在此先驱动渲染采样器重采样并重
    /// 试根承载安装，回退后两节拍随整层拆除退役，
    /// 复原为戳承载链 + 登记面证据行两件。
    static func requestRefresh(from view: UIView) {
        view.window?.rootViewController?
            .setNeedsStatusBarAppearanceUpdate()
        _ = style(source: "trait",
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
