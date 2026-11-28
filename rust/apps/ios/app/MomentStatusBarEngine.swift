import UIKit

// ── 状态栏明暗判定引擎（impl_statusbar_native_
// adaptation）──────────────────────────────────
// 用户 2026-11-28 方案第一/三条的决定面：主判定
// 交给数据——每个面登记自己的已知底色（令牌色 /
// 备忘底色 / 开屏渐变停点投影色），引擎按相对明
// 度单点判定；像素只做保底（图片页经覆盖门读一
// 个点，采样器在 MomentStatusBarPixel）。回答者
// 唯一：全应用只有根容器（MomentStatusBarRoot）
// 实现 preferredStatusBarStyle 并回问本引擎，容
// 器 childForStatusBarStyle 恒 nil——编辑/图片
// 承载不再各自 override，只登记面与输入、触发
// 重估（verify [53] SB-11 锁此唯一性）。
//
// 手感参数（用户给定、沿用网页层口径）单源于
// StatusBarParams：阈值 0.45、去抖 48ms、最短
// 驻留 120ms、淡变 160ms，全仓仅此一份（SB-13
// 锁）。翻转必记 Diag 一行（面/来源/判定明度），
// 供装机后桥回读核翻转行为。
//
// 沿革：旧背景色采样家族已于 71b6354 整套退
// 役、其符号集持续禁绝（SB-1 改判锁全仓零命
// 中、本文件不复述）；本引擎是其后的新架构，
// 不复活任何旧符号：度量换相对明度、无带区
// 平均、无整屏渲染采样。

/// 手感参数单源（用户 2026-11-28 给定值）。
enum StatusBarParams {
    /// 相对明度阈值：> 阈值判深字（.darkContent）。
    static let luminanceThreshold: CGFloat = 0.45
    /// 去抖：候选判定须稳定存续此时长才进入落定。
    static let debounce: TimeInterval = 0.048
    /// 最短驻留：两次翻转之间的最短间隔。
    static let minDwell: TimeInterval = 0.120
    /// 淡变：翻转时状态栏外观更新的动画时长。
    static let fade: TimeInterval = 0.160
}

/// 可达顶层的面（普查表与报告 §普查同名）。
enum StatusBarSurface: String {
    case splash   // 开屏层（根 ZStack 内，渐变数据自答）
    case root     // 首页 + 设置族（根令牌色数据自答）
    case rescue   // 救援页（根令牌色数据自答）
    case editor   // 编辑页（备忘底色数据自答）
    case image    // 图片页（像素保底、覆盖门后回落数据）
}

/// 一次求值的上下文：回答者（根容器）的当前
/// trait / 视图尺寸 / 状态栏带高（运行时安全区
/// 实值，禁写死单机数值）。
struct StatusBarEvalContext {
    let trait: UITraitCollection
    let viewSize: CGSize
    let bandH: CGFloat
}

/// 面输入：给定上下文回（底色， 是否像素来源）；
/// nil = 本次无判定（保持现状、不翻转）。
typealias StatusBarInputProvider
    = (StatusBarEvalContext) -> (color: UIColor, pixel: Bool)?

/// 像素保底源（图片页图面）：回带中心采样色，
/// 图未覆盖带中心 / 不可采样时回 nil。
typealias StatusBarPixelSource
    = (StatusBarEvalContext) -> UIColor?

final class StatusBarEngine {
    static let shared = StatusBarEngine()
    private init() {}

    /// 回答者（根容器）：全应用唯一向系统回答
    /// preferredStatusBarStyle 的控制器。
    private weak var answerer: UIViewController?
    /// 转发链活证：容器首次被系统询问时记一行——
    /// 若装机后此行缺失，即「根承载未把询问转发
    /// 到容器」的实证（报告 §留账第一验点）。
    private var answererLiveLogged = false

    private struct Entry {
        let surface: StatusBarSurface
        let provider: StatusBarInputProvider
    }
    /// 底层（根层级面：splash/root/rescue 三选一）。
    private var baseEntry: Entry?
    /// 覆盖层（承载面：editor/image，进出成栈）。
    private var overlayStack: [Entry] = []
    /// 图片页像素保底源（图面注册/注销）。
    private var imagePixelSource: StatusBarPixelSource?

    /// 当前已生效判定（容器回答本体）。
    private(set) var currentStyle: UIStatusBarStyle = .default
    private var hasApplied = false
    private var pendingStyle: UIStatusBarStyle?
    private var pendingMeta: (surface: StatusBarSurface,
                              lum: CGFloat, pixel: Bool)?
    private var pendingWork: DispatchWorkItem?
    private var lastFlipAt: CFAbsoluteTime = 0

    // ── 回答者在位与回答 ──────────────────────

    /// 根容器创建时登记（回答者 + 初始底层）。
    func attach(answerer: UIViewController,
                base: StatusBarSurface) {
        self.answerer = answerer
        setBase(base)
    }

    /// 容器的 preferredStatusBarStyle 本体：只读
    /// 已落定判定，绝不在回答内现算（采样/判定都
    /// 在触发点完成，回答零开销、无递归）。
    func answer() -> UIStatusBarStyle {
        if !answererLiveLogged {
            answererLiveLogged = true
            DiagLog.shared.log(.info,
                "STATUSBAR answerer live style="
                + "\(Self.name(currentStyle))")
        }
        return currentStyle
    }

    // ── 面登记 ────────────────────────────────

    /// 底层切换（根 SwiftUI 报告点：开屏退出 /
    /// 安全模式分流变化时调用）。
    func setBase(_ surface: StatusBarSurface) {
        baseEntry = Entry(
            surface: surface,
            provider: builtinProvider(for: surface))
        evaluate()
    }

    /// 承载面进入（编辑/图片承载 viewWillAppear）：
    /// 同面重复进入只换输入闭包、不叠层。
    func beginSurface(
        _ surface: StatusBarSurface,
        provider: StatusBarInputProvider? = nil) {
        let p = provider ?? builtinProvider(for: surface)
        if let idx = overlayStack.lastIndex(
            where: { $0.surface == surface }) {
            overlayStack[idx] = Entry(surface: surface,
                                      provider: p)
        } else {
            overlayStack.append(Entry(surface: surface,
                                      provider: p))
        }
        evaluate()
    }

    /// 承载面真正离开（承载被移出导航栈时）。
    func endSurface(_ surface: StatusBarSurface) {
        overlayStack.removeAll { $0.surface == surface }
        evaluate()
    }

    /// 图片页图面注册像素保底源（图面在位期间）。
    func setImagePixelSource(
        _ source: StatusBarPixelSource?) {
        imagePixelSource = source
        evaluate()
    }

    // ── 触发点（全部收敛到 evaluate）──────────
    // 语义与网页层触发逻辑等价：内容切换/滚动跨
    // 区 → inputChanged；布局落定（带高/尺寸变）
    // → noteLayout（容器 viewDidLayoutSubviews
    // 节流入口，evaluate 本身幂等廉价）；外观
    // trait 变 → noteTrait。

    func inputChanged() { evaluate() }
    func noteLayout() { evaluate() }
    func noteTrait() { evaluate() }

    // ── 判定 ──────────────────────────────────

    private var activeEntry: Entry? {
        overlayStack.last ?? baseEntry
    }

    private func evaluate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluate()
            }
            return
        }
        guard let answerer else { return }
        let view = answerer.view
        let ctx = StatusBarEvalContext(
            trait: answerer.traitCollection,
            viewSize: view.bounds.size,
            bandH: view.safeAreaInsets.top)
        guard let entry = activeEntry,
              let out = entry.provider(ctx),
              let lum = Self.luminance(of: out.color)
        else { return }
        let raw: UIStatusBarStyle = lum
            > StatusBarParams.luminanceThreshold
            ? .darkContent : .lightContent
        // 首判直落（启动期无既存生效值可抖，初始
        // 回答在容器首问前就位）。
        if !hasApplied {
            apply(raw, meta: (entry.surface, lum, out.pixel),
                  animated: false)
            return
        }
        if raw == currentStyle {
            pendingStyle = nil
            pendingMeta = nil
            pendingWork?.cancel()
            pendingWork = nil
            return
        }
        if pendingStyle == raw {
            // 同候选：只刷新证据值，不重置去抖计时。
            pendingMeta = (entry.surface, lum, out.pixel)
            return
        }
        pendingStyle = raw
        pendingMeta = (entry.surface, lum, out.pixel)
        scheduleSettle(after: StatusBarParams.debounce)
    }

    private func scheduleSettle(after delay: TimeInterval) {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settle()
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay, execute: work)
    }

    /// 去抖到期落定：先过最短驻留门（不足顺延），
    /// 再复算一次确认候选未被新输入推翻。
    private func settle() {
        guard pendingStyle != nil else { return }
        let dwellLeft = lastFlipAt
            + StatusBarParams.minDwell
            - CFAbsoluteTimeGetCurrent()
        if hasApplied && dwellLeft > 0 {
            scheduleSettle(after: dwellLeft)
            return
        }
        let before = pendingStyle
        evaluate()
        // evaluate 后候选被取消/替换 → 已由其自理；
        // 候选原样存续 → 落定。
        guard pendingStyle == before,
              let style = pendingStyle,
              let meta = pendingMeta else { return }
        apply(style, meta: meta, animated: true)
    }

    private func apply(
        _ style: UIStatusBarStyle,
        meta: (surface: StatusBarSurface,
               lum: CGFloat, pixel: Bool),
        animated: Bool) {
        pendingStyle = nil
        pendingMeta = nil
        pendingWork?.cancel()
        pendingWork = nil
        currentStyle = style
        hasApplied = true
        lastFlipAt = CFAbsoluteTimeGetCurrent()
        DiagLog.shared.log(.info,
            "STATUSBAR flip surface=\(meta.surface.rawValue) "
            + "src=\(meta.pixel ? "pixel" : "data") "
            + "lum=\(String(format: "%.3f", meta.lum)) "
            + "style=\(Self.name(style))")
        guard let answerer else { return }
        // 重问请求单点（[53] SB-11 锁全仓代码
        // 恰一处）：淡变与否只换调用方式。
        let request = {
            answerer.setNeedsStatusBarAppearanceUpdate()
        }
        if animated {
            UIView.animate(
                withDuration: StatusBarParams.fade,
                animations: request)
        } else {
            request()
        }
    }

    // ── 内建输入（数据面单点）────────────────

    private func builtinProvider(
        for surface: StatusBarSurface)
        -> StatusBarInputProvider {
        switch surface {
        case .root, .rescue:
            // 根令牌色（背景层级模型单源 T.bg）。
            return { ctx in
                (T.bgUI.resolvedColor(with: ctx.trait),
                 false)
            }
        case .splash:
            // 开屏渐变：停点即数据——带中心投影色由
            // 与画布同源的停点表现算（SplashBand
            // Data）；不可算时回垫层平色（同源单值）。
            return { ctx in
                if let c = SplashBandData.centerColor(
                    dark: ctx.trait.userInterfaceStyle
                        == .dark,
                    viewSize: ctx.viewSize,
                    bandH: ctx.bandH) {
                    return (c, false)
                }
                return (SplashOverlayView.uiColor
                    .resolvedColor(with: ctx.trait), false)
            }
        case .image:
            // 像素保底：图面覆盖带中心才采样，覆盖
            // 不达 / 不可采样回落根令牌色（带区实景
            // 即页背景，ChromeView .background(T.bg)
            // 与图面可用区顶让 126 的构造口径）。
            return { [weak self] ctx in
                if let px = self?.imagePixelSource?(ctx) {
                    return (px, true)
                }
                return (T.bgUI.resolvedColor(
                    with: ctx.trait), false)
            }
        case .editor:
            // 编辑面须由承载以备忘底色闭包登记
            // （beginSurface 带 provider）；缺登记时
            // 回根令牌色，不臆测。
            return { ctx in
                (T.bgUI.resolvedColor(with: ctx.trait),
                 false)
            }
        }
    }

    // ── 度量（相对明度，sRGB 线性化加权）─────

    static func luminance(of color: UIColor) -> CGFloat? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b,
                           alpha: &a) else { return nil }
        func lin(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92
                : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g)
            + 0.0722 * lin(b)
    }

    static func name(_ style: UIStatusBarStyle) -> String {
        switch style {
        case .lightContent: return "light"
        case .darkContent: return "dark"
        default: return "default"
        }
    }
}
