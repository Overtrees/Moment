import SwiftUI
import UIKit
import Combine

// ── 开屏独立承载（fix_statusbar_dynamic）────────────
// 一轮根治时开屏没有应用自有承载：它只是根 ZStack
// 里的一层 SwiftUI 浮层，状态栏由平台承载控制器内
// 部求值决定——应用采样单点（MomentStatusBar）够不
// 着它，采样源事实上错位（平台求值不看开屏渐变、
// 也不看应用登记）。用户 2026-11-28 实报：浅色主
// 题开屏期字色一直黑（品牌蓝被判浅底）。本文件把
// 开屏收进应用自有承载控制器（与编辑/图片页同模
// 式）：全屏呈现、preferredStatusBarStyle 走采样
// 单点，采样源 = 渐变带区公式色（bandAverage
// Color 现算，见 SplashBandColor 注）。沿革：三
// 轮曾改走带区实渲染采样、公式色降为兜底；用户
// 同日装机实报开屏三症状（闪白/透出首页空态/结
// 束闪黑）后裁定全页回退，本文件恢复二轮形态
// （fix_statusbar_rollback_all.md）。时序状态机
// （SplashState/SplashHost
// View）本体不搬家：状态由承载持有、gone 翻转即
// 退出信号，退出淡出以承载视图 alpha 动画复刻原
// 260ms easeOut 口径。呈现通道异常时回落根内联
// 呈现（SplashGate.inlineFallback → 根的
// InlineSplashHost），不让开屏呈现成为启动单点
// 故障。

/// 开屏呈现门：根持有（@StateObject），呈现器异
/// 常时置 inlineFallback 切内联兜底。
final class SplashGate: ObservableObject {
    @Published var inlineFallback = false
}

/// 开屏带区采样色（模式层）：按当前主题取
/// artwork 数值表，以视图尺寸 + 顶部安全区高
/// （运行期实值）算带区平均色——开屏状态栏字
/// 色的主采样源（二轮立、三轮曾降为兜底、回
/// 退后复任主源）。其正确性由 verify [53]
/// SB-7 以资源原表对账锁定（公式即采样源本
/// 身，错值即开屏字色错）。安全区高尚不可用（首帧布局前）
/// 时回退垫层平色（与画布下方的 splashColor
/// 同值：浅 (35,121,220) / 深 (31,31,33)）——带
/// 区在画布落定前实际露出的正是垫层色，兜底与
/// 呈现一致。源画布尺寸与 NativeSplashCanvas
/// 的 sourceWidth/sourceHeight 同值（1179×2556）。
enum SplashBandColor {
    static func uiColor(dark: Bool,
                        viewSize: CGSize,
                        bandH: CGFloat) -> UIColor {
        guard bandH > 0, viewSize.width > 0,
              viewSize.height > 0 else {
            return dark
                ? UIColor(red: 31.0 / 255,
                          green: 31.0 / 255,
                          blue: 33.0 / 255, alpha: 1)
                : UIColor(red: 35.0 / 255,
                          green: 121.0 / 255,
                          blue: 220.0 / 255, alpha: 1)
        }
        let art = dark ? NativeSplashArtwork.dark
            : NativeSplashArtwork.light
        let avg = StatusBarCore.bandAverageColor(
            stops: art.backgroundStops,
            start: art.backgroundStart,
            end: art.backgroundEnd,
            sourceW: 1179, sourceH: 2556,
            viewW: Double(viewSize.width),
            viewH: Double(viewSize.height),
            bandH: Double(bandH))
        return UIColor(red: CGFloat(avg.r),
                       green: CGFloat(avg.g),
                       blue: CGFloat(avg.b), alpha: 1)
    }
}

/// 开屏托管根视图：与根 ZStack 的开屏层级逐项同
/// 构（错误徽章在开屏之下、看门狗浮条在开屏之
/// 上——S8「浮条必须压得住开屏」的口径随承载迁
/// 移保持）；语言环境对象显式注入同一实例（独
/// 立承载不继承根的 environmentObject）。
struct SplashHostedRootView: View {
    @ObservedObject var library: Library
    @ObservedObject var state: SplashState

    var body: some View {
        ZStack {
            ErrBadgeOverlay()
            SplashHostView(library: library,
                           state: state, hosted: true)
            if library.watchdogFired
                && !library.bootIsSafe {
                WatchdogBar(library: library)
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity,
                           alignment: .bottom)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .environmentObject(LangStore.shared)
    }
}

/// 开屏承载控制器：全屏呈现期状态栏的唯一应用
/// 决定面——preferredStatusBarStyle 走 evaluate
/// （src=splash），采样源 = 渐变带区公式色
/// （bandColor 现算，模式层）。
final class SplashHostingController:
    UIHostingController<SplashHostedRootView> {
    /// 时序状态（呈现器创建并注入）：gone 翻转
    /// 由呈现器订阅收口（淡出 + 卸载）。
    var splashState: SplashState?
    private var didNudgeInsets = false

    override var preferredStatusBarStyle:
        UIStatusBarStyle {
        MomentStatusBar.evaluate(
            source: "splash",
            background: bandColor(),
            trait: traitCollection)
    }

    /// 开屏方向锁（用户 2026-11-28 裁定）：iPhone
    /// 开屏在位期间方向掩码收窄为竖屏，设备横置
    /// 也不转；退出卸载后根的 plist 口径自动恢
    /// 复（全屏呈现的承载即方向决定面，与状态栏
    /// 字色同构的 override 单点，无状态需回滚、
    /// 其他页零改动）。iPad 不在范围内（用户两
    /// 次明示）：idiom 闸使收窄在 iPad 路径结构
    /// 上不可达——恒回 super 既有口径，plist 的
    /// ~ipad 配置与开屏画布 isPad 分支均零改动
    /// （verify [53] SB-8 守卫）。
    override var supportedInterfaceOrientations:
        UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone
            ? .portrait
            : super.supportedInterfaceOrientations
    }

    private func bandColor() -> UIColor {
        SplashBandColor.uiColor(
            dark: traitCollection.userInterfaceStyle
                == .dark,
            viewSize: view.bounds.size,
            bandH: view.safeAreaInsets.top)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MomentStatusBar.registerCurrent(
            id: ObjectIdentifier(self)) { [weak self] in
            self?.bandColor() ?? T.bgUI
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        MomentStatusBar.clearCurrent(
            id: ObjectIdentifier(self))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 安全区在布局落定后才有实值：首个有效带
        // 区高出现时重估一次（此前的查询走垫层平
        // 色，与首帧呈现一致；重估后公式色以实带
        // 区高现算）。
        if !didNudgeInsets,
           view.safeAreaInsets.top > 0 {
            didNudgeInsets = true
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    override func traitCollectionDidChange(
        _ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if let previous,
           previous.userInterfaceStyle
            != traitCollection.userInterfaceStyle {
            // 模式切换是一级触发源：新模式下公式
            // 色按新 trait 现算，当场重估。
            setNeedsStatusBarAppearanceUpdate()
        }
    }
}

/// 呈现器挂载点（根 background 内）：安全模式与
/// 资源缺失时不挂载（与旧内联开屏的挂载条件同
/// 口径——安全模式 didLoad 不置真、无开屏）。
struct SplashPresenterMount: View {
    var library: Library
    var gate: SplashGate

    var body: some View {
        if !library.bootIsSafe
            && SplashHostView.resourcesReady {
            SplashPresenter(library: library,
                            gate: gate)
        }
    }
}

/// 开屏呈现器：根视图入窗后把 SplashHosting
/// Controller 全屏呈现（不带动画，首帧即开屏本
/// 色）；订阅 SplashState.gone 完成退出（alpha
/// 淡出 exitDuration 后卸载）。窗口/根控制器久
/// 不可用（有界重试 10 次 × 0.25s）则置
/// gate.inlineFallback 回落内联并留痕——呈现失
/// 败不许挡住应用。
struct SplashPresenter: UIViewRepresentable {
    var library: Library
    var gate: SplashGate

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        context.coordinator.library = library
        context.coordinator.gate = gate
        context.coordinator.probeView = v
        v.onWindow = { [weak coordinator =
                        context.coordinator] in
            coordinator?.tryPresent()
        }
        return v
    }

    func updateUIView(_ v: ProbeView,
                      context: Context) {
        context.coordinator.library = library
        context.coordinator.gate = gate
        context.coordinator.tryPresent()
    }

    final class ProbeView: UIView {
        var onWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow?() }
        }
    }

    final class Coordinator {
        var library: Library?
        var gate: SplashGate?
        private var presented = false
        private var attempts = 0
        private var goneSink: AnyCancellable?

        func tryPresent() {
            guard !presented,
                  let library, let gate else { return }
            guard let view = probeView,
                  let window = view.window,
                  let root = window.rootViewController,
                  root.presentedViewController == nil
            else {
                attempts += 1
                if attempts <= 10 {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.25) {
                        [weak self] in
                        self?.tryPresent()
                    }
                } else if !gate.inlineFallback {
                    DiagLog.shared.log(.warn,
                        "SPLASH presenter fallback inline")
                    gate.inlineFallback = true
                }
                return
            }
            presented = true
            let state = SplashState()
            let vc = SplashHostingController(
                rootView: SplashHostedRootView(
                    library: library, state: state))
            vc.splashState = state
            vc.modalPresentationStyle = .fullScreen
            vc.modalPresentationCapturesStatusBarAppearance
                = true
            goneSink = state.$gone
                .dropFirst()
                .sink { [weak self, weak vc] gone in
                    guard gone else { return }
                    self?.dismiss(vc)
                }
            root.present(vc, animated: false)
            DiagLog.shared.log(.info, "SPLASH present vc")
        }

        /// 探针视图弱引用（tryPresent 的窗口来
        /// 源）：makeUIView 时登记、入窗回调与根
        /// 更新回调共同驱动 tryPresent。
        weak var probeView: ProbeView?

        private func dismiss(
            _ vc: SplashHostingController?) {
            guard let vc else { return }
            let dur = vc.splashState?.exitDuration
                ?? 0.26
            if dur <= 0 {
                vc.dismiss(animated: false)
                return
            }
            UIView.animate(
                withDuration: dur, delay: 0,
                options: [.curveEaseOut]) {
                vc.view.alpha = 0
            } completion: { _ in
                vc.dismiss(animated: false)
            }
        }
    }
}
