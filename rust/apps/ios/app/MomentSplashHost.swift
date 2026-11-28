import SwiftUI
import UIKit
import Combine

// ── 开屏单承载序列（fix_splash_flash_sequence）──
// 沿革：二轮（fix_statusbar_dynamic）把开屏收进
// 独立全屏呈现的承载控制器，根视图与开屏分属两
// 个视图控制器层；三轮的根承载换根曾被归因为闪
// 现来源并在 0.9.64 拆除，但 0.9.65 真机实报两症
// 状仍在（开屏期间闪过首页空态 10–20ms、结束闪
// 黑）——旧归因被证伪：接缝不在某一轮的增层，而
// 在呈现式承载结构本身（定案见报告）：
//   ① 入口接缝：根 ListView 自首帧即渲染（空态无
//   就绪门），呈现只能在根入窗后下一事务生效，
//   中间 1–2 帧空态直接进窗口；
//   ② 出口接缝：全屏呈现下根视图被移出窗口，退
//   出淡出的底是窗口本身，而全仓从未设窗口底色
//   （默认黑）——淡出实为向黑淡出，末尾再以无动
//   画卸载硬切回首页。
// 本批按红线重构为单承载：开屏是根层级内的一层
// （SplashLaunchLayer），与首页同属一个视图层
// 级、随根首帧同帧在位；退场只有一条路径（状态
// 机 gone → 本层 opacity 淡出 → exited 卸载），
// 无呈现、无卸载、无根切换。窗口底色由铬面探针
// 自首帧起钉在开屏同源色/根页底色，间隙帧结构
// 上不存在黑底。
//
// 节奏基线（用户 2026-11-28 裁定：整体节奏不
// 变）：静止 500ms（定时）→ progress 线性 1.0s
// （动画）→ 再 1.0s（定时）置 timelineComplete
// → 退出门 = didLoad && timelineComplete（就绪
// 等待：冷启数据就绪为百 ms 级、被 2.5s 节拍完
// 全吸收，实际占 0）→ easeOut 260ms 淡出（减弱
// 动态效果时 timelineComplete 立即置位、淡出
// 0）。本批逐项未动；唯一位移是时间线起锚由
// 「呈现完成」提前到「根首帧」，差 ≤1–2 帧——
// 即被消除的闪现窗口本身。verify [53] SB-10
// 锁此构成。
//
// 职责保全（对旧承载逐项）：品牌时间线与画布
// （SplashOverlayView，本体自 MomentApp 迁入、
// 逻辑未动）；方向锁 SB-8（决定面迁至应用委托
// 掩码门，见 LaunchOrientationGate）；看门狗浮
// 条压开屏（根 ZStack 层序保持，浮条在开屏层
// 之上）；安全模式不挂开屏（根挂载条件与旧呈
// 现器挂载同口径）；资源缺失不挂（resources
// Ready 闸）；呈现失败回落内联的旧兜底职责随
// 呈现通道退役而结构性消解——开屏只是一层视
// 图，不再有可失败的呈现动作；Diag 留痕升级为
// 相位行（SPLASH phase *，Clock.ms 时刻），供
// 装机后桥回读对账相位间隔。

// ── 开屏方向门（SB-8 决定面）────────────────
// 掩码的唯一决定面：应用委托按本门回当前掩码。
// 开屏在位（splashActive）且 iPhone → 竖屏；其
// 余回全向三向（与 plist ~ipad 数组及 iPhone 无
// 全局键时的系统默认逐值一致，行为等价）。过
// 程起点为真（正常冷启必经开屏）；开屏层不挂
// 载的启动（安全模式/资源缺失）由铬面探针在首
// 帧清门，开屏退出完成由探针的 exited 订阅清
// 门，两路都经 refreshOrientations 触发系统重
// 估。全部访问在主线程（委托查询与视图回调均
// 在主线程），无锁。
enum LaunchOrientationGate {
    static var splashActive = true

    static var mask: UIInterfaceOrientationMask {
        let full: UIInterfaceOrientationMask =
            [.portrait, .landscapeLeft, .landscapeRight]
        if splashActive,
           UIDevice.current.userInterfaceIdiom == .phone {
            return .portrait
        }
        return full
    }

    /// 触发系统按当前门值重估窗口方向掩码（iOS
    /// 16+ 的根控制器重估入口；部署目标 16.0）。
    static func refreshOrientations(
        in window: UIWindow?) {
        window?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// 应用委托（仅方向掩码一件职责）：SwiftUI 生
/// 命周期下由 MomentApp 的 UIApplication
/// DelegateAdaptor 挂载；方向支持的系统查询链
/// 末端即应用委托，本类把查询转给方向门单点。
final class MomentAppDelegate: NSObject,
    UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        LaunchOrientationGate.mask
    }
}

// ── 开屏时序状态机 ───────────────────────────
/// 开屏时序状态（口径 = 原生壳工程 NativeSplash
/// Timeline，用户 2026-11-26 提供的启动动画源
/// 码）：静止 500ms → progress 线性 1.0s 走完
/// 呼吸曲线 → 再 1.0s 置 timelineComplete；退
/// 出条件 = 数据就绪（didLoad）&& timeline
/// Complete，easeOut 260ms 淡出；减弱动态效果
/// 时 timelineComplete 立即置位、淡出时长 0。
/// 资源缺失（构建异常）时宿主直接不呈现，绝不
/// 让开屏挡住应用。本类自 MomentApp 迁入（拒
/// 绝上帝文件），字段在原三件（progress /
/// timelineComplete / gone）之外增 exited（淡
/// 出完成、层卸载凭据）与相位时刻三枚（Diag 证
/// 据记账，不参与判定）。
final class SplashState: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var timelineComplete = false
    @Published var gone = false
    /// 淡出完成：启动层据此整体卸载、铬面探针
    /// 据此换窗口底色并清方向门。
    @Published var exited = false
    /// 退出淡出时长（启动层 opacity 动画消费）：
    /// beginExitIfReady 按减弱动态效果置 0/0.26。
    @Published var exitDuration: TimeInterval = 0.26
    /// 相位时刻（Clock.ms()，进程起算）：show =
    /// 时间线起跑、data = didLoad 观察到、time
    /// line = 节拍走完；退出行一并打出三值供对
    /// 账（退出时点 = max(节拍, 数据)，节奏对账
    /// 基线见文件头）。
    var showMs = -1
    var dataMs = -1
    var timelineMs = -1
}

// ── 开屏画布（原根内画布本体迁入）──────────
/// 开屏呈现本体：底色垫层 + 品牌画布 + 时间线
/// 驱动 + 退出门。gone 后不自卸（淡出与卸载由
/// 启动层按 gone/exited 两段收口：gone 只翻透
/// 明度，画布在淡出全程保持在位——旧内联形态
/// 的 gone 即自卸在单承载下会让淡出无对象，随
/// 呈现式形态一并退役）。
struct SplashOverlayView: View {
    @ObservedObject var library: Library
    @ObservedObject var state: SplashState
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    static var resourcesReady: Bool {
        Bundle.main.url(forResource: "MomentSplash-light-vector",
                        withExtension: "json") != nil
            && Bundle.main.url(
                forResource: "MomentSplash-dark-vector",
                withExtension: "json") != nil
    }

    /// 开屏底色单源（UIColor 形态）：原壳
    /// launchBackgroundColor 同值、与系统开屏
    /// LaunchBackground 资产同值——浅 (35,121,
    /// 220) / 深 (31,31,33)；动态色按 trait 自
    /// 行解析。SwiftUI 垫层色（下）与铬面探针的
    /// 窗口底色同出此源，字面对全仓仅此一对
    /// （DM45-1 改判登记）。
    static var uiColor: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 31.0 / 255,
                          green: 31.0 / 255,
                          blue: 33.0 / 255, alpha: 1)
                : UIColor(red: 35.0 / 255,
                          green: 121.0 / 255,
                          blue: 220.0 / 255, alpha: 1)
        }
    }

    /// 开屏底色（SwiftUI 形态）：由单源 uiColor
    /// 派生（动态色桥接、随 trait 解析，与旧
    /// colorScheme 双支逐值一致）。
    private var splashColor: Color {
        Color(uiColor: Self.uiColor)
    }

    var body: some View {
        // 宿主形态按原壳原样（2026-11-26 用户实
        // 报上下半透明条后核证）：底色垫层满屏
        // ignoresSafeArea + 画布 ignoresSafeArea
        // (.container) 全屏。
        ZStack {
            splashColor
                .ignoresSafeArea()
            NativeMomentSplash(progress: state.progress)
                .ignoresSafeArea(.container, edges: .all)
                .accessibilityHidden(true)
        }
        .task(id: reduceMotion) {
            await runTimeline()
        }
        .onChange(of: library.didLoad) { ready in
            if ready && state.dataMs < 0 {
                state.dataMs = Clock.ms()
                DiagLog.shared.log(.info,
                    "SPLASH phase data t=\(state.dataMs)")
            }
            beginExitIfReady()
        }
        .onChange(of: state.gone) { gone in
            guard gone else { return }
            // 淡出走完才置 exited（启动层卸载、探
            // 针换底清门都以此为准）；时长 0 时同
            // 拍收口。
            let dur = state.exitDuration
            DispatchQueue.main.asyncAfter(
                deadline: .now() + dur) {
                state.exited = true
                DiagLog.shared.log(.info,
                    "SPLASH phase end t=\(Clock.ms())")
            }
        }
    }

    private func runTimeline() async {
        state.showMs = Clock.ms()
        DiagLog.shared.log(.info,
            "SPLASH phase show t=\(state.showMs)")
        if reduceMotion {
            state.timelineMs = Clock.ms()
            state.timelineComplete = true
            beginExitIfReady()
            return
        }
        do {
            try await Task.sleep(
                nanoseconds: 500_000_000)
        } catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(.linear(duration: 1.0)) {
            state.progress = 1
        }
        do {
            try await Task.sleep(
                nanoseconds: 1_000_000_000)
        } catch { return }
        guard !Task.isCancelled else { return }
        state.timelineMs = Clock.ms()
        DiagLog.shared.log(.info,
            "SPLASH phase timeline t=\(state.timelineMs)")
        state.timelineComplete = true
        beginExitIfReady()
    }

    /// 退出门（单点，节奏基线见文件头）：双条件
    /// 齐备才翻 gone；gone 的唯一写点在本函数。
    private func beginExitIfReady() {
        guard library.didLoad, state.timelineComplete,
              !state.gone else { return }
        state.exitDuration = reduceMotion ? 0 : 0.26
        withAnimation(.easeOut(duration: reduceMotion
            ? 0 : 0.26)) {
            state.gone = true
        }
        DiagLog.shared.log(.info,
            "SPLASH phase exit t=\(Clock.ms()) "
            + "data=\(state.dataMs) "
            + "timeline=\(state.timelineMs)")
    }
}

// ── 开屏启动层（根 ZStack 的一层）────────────
/// 单承载的根层形态：exited 前渲染画布（gone
/// 后仅透明度归零、淡出全程在位且挡触摸，与旧
/// 呈现形态的模态语义等价），exited 后整体不
/// 渲染。挂载条件由根决定（正常模式 && 资源就
/// 绪），与旧呈现器挂载同口径。
struct SplashLaunchLayer: View {
    @ObservedObject var library: Library
    @ObservedObject var state: SplashState

    var body: some View {
        if !state.exited {
            SplashOverlayView(library: library,
                              state: state)
                .opacity(state.gone ? 0 : 1)
        }
    }
}

// ── 启动铬面探针（窗口底色 + 方向门送达）────
/// 根 background 挂载，零尺寸、不参与命中。三
/// 件职责：
/// ① 窗口底色：入窗即置开屏同源动态色（与
/// LaunchBackground 资产同值、按 trait 自行解
/// 析）；exited 后换根页底色 T.bgUI（同为动态
/// 色）。窗口在任何间隙帧露底都只会是这两色
/// 之一——黑底帧在结构上不存在。
/// ② 方向门送达：入窗时若开屏不挂载（安全模
/// 式/资源缺失）即清门并触发重估；exited 订阅
/// 在退出完成时清门 + 重估 + 换底。
/// ③ 安全模式中途进入（看门狗切救援）时开屏
/// 层随根分支卸载，方向门由根的 bootIsSafe 变
/// 化观察兜底清（见 attach 的门值对账：每次
/// updateUIView 都按当前挂载事实校正门值）。
struct LaunchChromeProbe: UIViewRepresentable {
    @ObservedObject var library: Library
    @ObservedObject var state: SplashState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        context.coordinator.library = library
        context.coordinator.state = state
        context.coordinator.probeView = v
        v.onWindow = { [weak coordinator =
                        context.coordinator] in
            coordinator?.attach()
        }
        return v
    }

    func updateUIView(_ v: ProbeView,
                      context: Context) {
        context.coordinator.library = library
        context.coordinator.state = state
        context.coordinator.attach()
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
        var state: SplashState?
        weak var probeView: ProbeView?
        private var exitedSink: AnyCancellable?
        private var restingApplied = false

        /// 开屏是否挂载（与根挂载条件同式）：探
        /// 针据此对账方向门——挂载在位则门开（退
        /// 出完成前），不挂载则门必须清。
        private var splashMounted: Bool {
            guard let library else { return false }
            return !library.bootIsSafe
                && SplashOverlayView.resourcesReady
        }

        func attach() {
            guard let view = probeView,
                  let window = view.window,
                  let state else { return }
            if exitedSink == nil {
                exitedSink = state.$exited
                    .dropFirst()
                    .sink { [weak self] exited in
                        guard exited else { return }
                        self?.applyResting()
                    }
            }
            if state.exited {
                applyResting()
                return
            }
            window.backgroundColor =
                SplashOverlayView.uiColor
            // 门值对账：挂载事实与门不一致才动
            // （避免每次 update 都触发重估）。
            if splashMounted != LaunchOrientationGate
                .splashActive {
                LaunchOrientationGate.splashActive =
                    splashMounted
                LaunchOrientationGate
                    .refreshOrientations(in: window)
            }
        }

        /// 退出完成后的静息铬面：窗口底换根页底
        /// 色、方向门清零并重估。幂等（attach 与
        /// exited 订阅双路可达）。
        private func applyResting() {
            guard !restingApplied else { return }
            restingApplied = true
            guard let window = probeView?.window
            else { return }
            window.backgroundColor = T.bgUI
            if LaunchOrientationGate.splashActive {
                LaunchOrientationGate.splashActive =
                    false
                LaunchOrientationGate
                    .refreshOrientations(in: window)
            }
        }
    }
}
