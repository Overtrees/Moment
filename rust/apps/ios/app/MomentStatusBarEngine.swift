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
// 锁）。翻转必记 Diag 一行（面/来源/判定明度；
// 图片面兜底另带 px 分账——未覆盖/未就绪超时/
// 失败原因码，fix_statusbar_sampling_integrity），
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
    /// 像素未就绪超时：图片面采样报未就绪时暂缓
    /// 判定的最长时长，超时以页背景兜底且读数
    /// 带因（fix_statusbar_sampling_integrity，
    /// 对照案 L3 口径 1 秒）。
    static let pixelReadyTimeout: TimeInterval = 1.0
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

/// 面输入：给定上下文回（底色, 是否像素来源,
/// 像素分账）；nil = 本次无判定（保持现状、不
/// 翻转）。px 分账仅图片面非实测时非空（未覆盖
/// / 未就绪超时 / 失败原因码），随判定进 Diag
/// 读数——兜底不再与实测、与数据面同貌（fix_
/// statusbar_sampling_integrity，SB-18 锁）。
typealias StatusBarInputProvider
    = (StatusBarEvalContext)
        -> (color: UIColor, pixel: Bool, px: String?)?

/// 像素保底源（图片页图面）：回带中心采样三态
/// 结果（采样层 StatusBarPixelOutcome），引擎
/// 按态消费——实测入判定、未覆盖/失败以页背景
/// 兜底带分账、未就绪暂缓判定。
typealias StatusBarPixelSource
    = (StatusBarEvalContext) -> StatusBarPixelOutcome

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
                              lum: CGFloat, pixel: Bool,
                              px: String?)?
    private var pendingWork: DispatchWorkItem?
    private var lastFlipAt: CFAbsoluteTime = 0

    /// 像素未就绪暂缓集（图片面）：集起于首次报
    /// 未就绪（源未注册 / 图未备好），集内不下判
    /// 定、保持现答；源报出任何定态（实测/未覆盖
    /// /失败）或超时到期即终结——超时以页背景兜
    /// 底且读数带 px=notready。集起/超时各记一行
    /// Diag（集内重复触发不重复记）。
    private var pixelDeferSince: CFAbsoluteTime?
    private var pixelDeferWork: DispatchWorkItem?
    /// 超时兜底已服务闩：同一未就绪长窗内超时只
    /// 起集一次，其后未就绪直回兜底值（分账不变
    /// ），定态到达或面进出才复位。
    private var pixelDeferServed = false

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
        // 图片面新一轮进入：上一轮的未就绪暂缓集
        // 不跨面存续（源与图都是新一轮的）。
        if surface == .image { clearPixelDefer() }
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
        if surface == .image { clearPixelDefer() }
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
    // 节流入口，evaluate 本身幂等廉价）；非外观
    // trait 变 → noteTrait（同普通通道）；外观
    // 切换（userInterfaceStyle 变）→ note
    // AppearanceChanged（确定性通道，见下）。

    func inputChanged() { evaluate() }
    func noteLayout() { evaluate() }
    func noteTrait() { evaluate() }

    /// 外观切换补遗（fix_statusbar_appearance_
    /// trigger，用户 2026-11-28 15:02 裁定）：
    /// 外观切换是确定性事件、不是抖动源——不进
    /// 普通候选通道（去抖 + 驻留 + 可被中间重估
    /// 取消），变化即按当前 trait 的有效色重算
    /// 并直落。订阅点唯一：根容器 traitCollect-
    /// ionDidChange 在 style 变化时调本入口（同
    /// 帧重复触发由容器侧 style 变化过滤合并）。
    func noteAppearanceChanged() {
        evaluate(deterministic: true)
    }

    // ── 判定 ──────────────────────────────────

    private var activeEntry: Entry? {
        overlayStack.last ?? baseEntry
    }

    private func evaluate(deterministic: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluate(deterministic: deterministic)
            }
            return
        }
        guard let answerer else { return }
        // 本工具链 SDK 接口里 UIViewController.
        // view 为 Optional（非 IUO）：按仓内成例
        // （MomentEditorTransition）先 loadViewIf
        // Needed 再解包；取不到视图即无带可判、
        // 本轮不答（后续布局触发会再送达）。
        answerer.loadViewIfNeeded()
        guard let view = answerer.view else { return }
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
            apply(raw, meta: (entry.surface, lum,
                              out.pixel, out.px),
                  animated: false,
                  trigger: deterministic ? "appearance"
                                         : "eval")
            return
        }
        if raw == currentStyle {
            // 外观重答与现行一致：记一行作链活证
            // 据（切换已达引擎且按新外观重算过），
            // 免得「无翻转」与「没触发」在 Diag 里
            // 不可分辨（补遗验收对账点）。
            if deterministic {
                // 子表达式先落 let：整链内嵌三元 +
                // format 时类型检查器超时（tree 首
                // 编译实证），拆分后输出逐字不变。
                let srcName = out.pixel ? "pixel" : "data"
                let lumText = String(format: "%.3f", lum)
                let pxText = out.px.map { " px=\($0)" }
                    ?? ""
                DiagLog.shared.log(.info,
                    "STATUSBAR appearance surface="
                    + "\(entry.surface.rawValue) "
                    + "src=\(srcName)\(pxText) "
                    + "lum=\(lumText) "
                    + "style=\(Self.name(raw))")
            }
            pendingStyle = nil
            pendingMeta = nil
            pendingWork?.cancel()
            pendingWork = nil
            return
        }
        // 外观确定性直落：候选通道（去抖/驻留）
        // 只治高频抖动源（滚动/布局）；外观切换
        // 一次性且结论确定，进候选会被中间重估
        // 整段取消、事件过后无人重发——故直落
        // （淡变仍走 apply 的 fade 口径）。
        if deterministic {
            apply(raw, meta: (entry.surface, lum,
                              out.pixel, out.px),
                  animated: true, trigger: "appearance")
            return
        }
        if pendingStyle == raw {
            // 同候选：只刷新证据值，不重置去抖计时。
            pendingMeta = (entry.surface, lum,
                           out.pixel, out.px)
            return
        }
        pendingStyle = raw
        pendingMeta = (entry.surface, lum,
                       out.pixel, out.px)
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
               lum: CGFloat, pixel: Bool,
               px: String?),
        animated: Bool,
        trigger: String = "eval") {
        pendingStyle = nil
        pendingMeta = nil
        pendingWork?.cancel()
        pendingWork = nil
        currentStyle = style
        hasApplied = true
        lastFlipAt = CFAbsoluteTimeGetCurrent()
        // 子表达式先落 let（同 appearance 行：
        // 整链内嵌三元 + format 触发类型检查
        // 器超时），输出逐字不变。px 分账紧跟
        // src：图片面兜底（未覆盖/未就绪超时/
        // 失败）与数据面、实测在读数上可分辨。
        let srcName = meta.pixel ? "pixel" : "data"
        let lumText = String(format: "%.3f", meta.lum)
        let pxText = meta.px.map { " px=\($0)" } ?? ""
        DiagLog.shared.log(.info,
            "STATUSBAR flip surface=\(meta.surface.rawValue) "
            + "src=\(srcName)\(pxText) "
            + "lum=\(lumText) "
            + "style=\(Self.name(style)) "
            + "trigger=\(trigger)")
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
                 false, nil)
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
                    return (c, false, nil)
                }
                return (SplashOverlayView.uiColor
                    .resolvedColor(with: ctx.trait),
                    false, nil)
            }
        case .image:
            // 像素保底三态消费（imageInput 单点）：
            // 实测入判定；未覆盖/失败以页背景兜底
            // 带分账（带区实景即页背景，ChromeView
            // .background(T.bg) 与图面可用区顶让
            // 126 的构造口径）；未就绪暂缓、超时才
            // 兜底。旧「nil 即兜底、读数同貌」退役。
            return { [weak self] ctx in
                self?.imageInput(ctx)
            }
        case .editor:
            // 编辑面须由承载以备忘底色闭包登记
            // （beginSurface 带 provider）；缺登记时
            // 回根令牌色，不臆测。
            return { ctx in
                (T.bgUI.resolvedColor(with: ctx.trait),
                 false, nil)
            }
        }
    }

    // ── 图片面输入（像素三态消费单点）────────

    /// 图片面判定输入：像素源三态在此收口——
    /// .measured 直入判定（px 分账空）；.notCovered
    /// / .failed 以页背景（根令牌色）兜底并带分
    /// 账（notcovered / failed:<原因码>）；.notReady
    /// 与源未注册（图面未就绪窗）进暂缓集（见
    /// deferPixelFallback）。页背景色在此单点解
    /// 析一次供各兜底支共用（SB-16 计数口径）。
    private func imageInput(
        _ ctx: StatusBarEvalContext)
        -> (color: UIColor, pixel: Bool, px: String?)? {
        let bg = T.bgUI.resolvedColor(with: ctx.trait)
        guard let source = imagePixelSource else {
            return deferPixelFallback(bg)
        }
        switch source(ctx) {
        case .measured(let color):
            clearPixelDefer()
            return (color, true, nil)
        case .notCovered:
            clearPixelDefer()
            return (bg, false, "notcovered")
        case .failed(let reason):
            clearPixelDefer()
            return (bg, false,
                    "failed:\(reason.rawValue)")
        case .notReady:
            return deferPixelFallback(bg)
        }
    }

    /// 未就绪暂缓：集内回 nil（evaluate 保持现
    /// 答、不翻转），集起记 defer 一行并挂超时重
    /// 估一枚；图片面既有候选在集起时取消（候选
    /// 证据属集前形态，不跨未就绪窗落定）。超时
    /// 仍未就绪 → 以页背景兜底、记 fallback 一
    /// 行、判定 px 分账 notready。
    private func deferPixelFallback(
        _ bg: UIColor)
        -> (color: UIColor, pixel: Bool, px: String?)? {
        if pixelDeferServed {
            return (bg, false, "notready")
        }
        let now = CFAbsoluteTimeGetCurrent()
        if let since = pixelDeferSince {
            guard now - since
                    >= StatusBarParams.pixelReadyTimeout
            else { return nil }
            pixelDeferSince = nil
            pixelDeferWork?.cancel()
            pixelDeferWork = nil
            pixelDeferServed = true
            DiagLog.shared.log(.info,
                "STATUSBAR fallback surface=image "
                + "px=notready")
            return (bg, false, "notready")
        }
        pixelDeferSince = now
        if pendingMeta?.surface == .image {
            pendingStyle = nil
            pendingMeta = nil
            pendingWork?.cancel()
            pendingWork = nil
        }
        DiagLog.shared.log(.info,
            "STATUSBAR defer surface=image px=notready")
        let work = DispatchWorkItem { [weak self] in
            self?.evaluate()
        }
        pixelDeferWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + StatusBarParams.pixelReadyTimeout,
            execute: work)
        return nil
    }

    /// 暂缓集终结（定态到达 / 面进出）：清计时、
    /// 挂起的超时重估与已服务闩。
    private func clearPixelDefer() {
        pixelDeferSince = nil
        pixelDeferWork?.cancel()
        pixelDeferWork = nil
        pixelDeferServed = false
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
