import SwiftUI
import UIKit
import Combine

// ── 开屏独立承载（fix_statusbar_dynamic 立、
// remove_statusbar_sampling 改判）──────────────
// 本文件把开屏收进应用自有承载控制器全屏呈现
// （与编辑/图片页同模式）：呈现时序、退出淡出与
// iPhone 方向锁（SB-8）由承载持有。沿革：二轮立
// 承载的初衷是给开屏状态栏字色接应用背景色采样
// 单点（带区公式色现算）；用户 2026-11-28 裁定
// 背景色采样整套去除后，承载的状态栏决定面随之
// 退役——不再设状态栏样式的承载 override，
// 开屏期字色回平台默认（按 trait 决定，与全应用
// 同口径，remove_statusbar_sampling.md）。承载
// 本体保留的理由与采样无关：呈现节拍（首帧即开
// 屏本色、gone 淡出卸载）与方向锁都挂在它身上。
// 时序状态机（SplashState/SplashHost
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

/// 开屏承载控制器：全屏呈现的承载本体（呈现
/// 节拍与退出淡出由呈现器经它收口）。状态栏字
/// 色不设应用决定面（背景色采样去除后回平台默
/// 认，remove_statusbar_sampling）；本类现只持
/// 方向锁一件 override。
final class SplashHostingController:
    UIHostingController<SplashHostedRootView> {
    /// 时序状态（呈现器创建并注入）：gone 翻转
    /// 由呈现器订阅收口（淡出 + 卸载）。
    var splashState: SplashState?

    /// 开屏方向锁（用户 2026-11-28 裁定）：iPhone
    /// 开屏在位期间方向掩码收窄为竖屏，设备横置
    /// 也不转；退出卸载后根的 plist 口径自动恢
    /// 复（全屏呈现的承载即方向决定面，无状态需
    /// 回滚、其他页零改动）。iPad 不在范围内（用
    /// 户两次明示）：idiom 闸使收窄在 iPad 路径结
    /// 构上不可达——恒回 super 既有口径，plist 的
    /// ~ipad 配置与开屏画布 isPad 分支均零改动
    /// （verify [53] SB-8 守卫）。
    override var supportedInterfaceOrientations:
        UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone
            ? .portrait
            : super.supportedInterfaceOrientations
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
