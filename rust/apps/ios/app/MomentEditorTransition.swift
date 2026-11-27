import SwiftUI
import UIKit
import Combine

// ── 编辑器转场宿主（0.9.50 呈现重构）──────────────────
// 新建/打开笔记的呈现自此由 UIKit 单一转场拥有，不再
// 走 SwiftUI NavigationStack 的 navigationDestination
// push。三轮定案背景（fix_new_note_transition_round2
// + 0.9.48 真机 Diag）：业务分段（create/listpass/
// bodypass/kb）已全数干净，剩余卡顿在呈现机制本身——
// 旧形态下目标页在 push 动画窗内才构建、初始落焦认领
// 在安装帧触发，键盘动画于 dest 后 36–67ms 即起、与
// 约 350ms 的 push 动画全程重叠，用户体感为「接力式
// 两段过渡」。本宿主的编排（任一时刻只有一个动画）：
//   1. 转场开始前先把编辑器承载控制器建好并强制完成
//      首帧构建与布局（loadViewIfNeeded + layout），
//      首帧工作全部落在转场窗外；
//   2. UINavigationController push 一次完成（系统转
//      场，与旧 push 同一导航控制器、同一手势语义）；
//   3. 初始落焦认领由门控挡在转场 completion 之后：
//      completion 回调里 openFocusGate，块视图才认领，
//      键盘在页面落定后单独升起。
// 列表侧配合：新建入口在 ListView.createAndOpen 内以
// disablesAnimations 事务收敛（新行插入不与转场共演）。
// 返回路径确定性：页眉返回钮与图片页返回钮经 onClose/
// onBack 闭包直达本宿主的 pop，不依赖环境 dismiss 在
// 手动 push 承载控制器内的未定口径。
// TRANSITION 打点：每次呈现一行（push 起点/构建止/
// 转场止/认领/键盘四时点），下次 Diag 直接验「单段
// 动画」——claim/kb 时点取 EditorModel 的 CREATE 计
// 时戳（仅新建篇有戳，其余 kind 记 na，如实）。

/// 导航控制器探针：挂在首页根视图背景，视图入窗后沿
/// 响应链找到承载 NavigationStack 的 UINavigation
/// Controller 并登记给宿主。只登记、不动导航栈状态；
/// 探针视图不参与命中。
struct EditorNavProbe: UIViewRepresentable {
    var onAttach: (UINavigationController) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        v.onAttach = onAttach
        return v
    }

    func updateUIView(_ v: ProbeView, context: Context) {
        v.onAttach = onAttach
        v.tryAttach()
    }

    final class ProbeView: UIView {
        var onAttach: ((UINavigationController) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            tryAttach()
        }

        func tryAttach() {
            guard window != nil, let onAttach else { return }
            var r: UIResponder? = self
            while let cur = r {
                if let vc = cur as? UIViewController,
                   let nav = vc.navigationController {
                    onAttach(nav)
                    return
                }
                r = cur.next
            }
        }
    }
}

/// 编辑器承载控制器：系统导航栏恒隐（全应用口径，编
/// 辑页自带悬浮页眉）；真正离开导航栈（pop/被替换）
/// 时回调宿主收口会话。判定取「disappear 后已无导航
/// 控制器」——交互式返回取消时导航控制器仍在，不误报。
final class EditorHostingController: UIHostingController<EditorView> {
    var onRemoved: (() -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(
            true, animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController == nil {
            onRemoved?()
        }
    }
}

/// 图片页承载控制器（编辑器 imageTarget 的呈现已由
/// 宿主接管，见 EditorTransitionHost.observeImage）。
final class ImageHostingController: UIHostingController<ImagePageView> {
    var onRemoved: (() -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(
            true, animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController == nil {
            onRemoved?()
        }
    }
}

final class EditorTransitionHost {
    private weak var navController: UINavigationController?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var attachRetries = 0

    private final class Session {
        let editor: EditorModel
        let kind: String
        let t0: CFAbsoluteTime
        var tBuild: CFAbsoluteTime = 0
        var tEnd: CFAbsoluteTime = 0
        var logged = false
        weak var hostVC: EditorHostingController?
        weak var imageVC: ImageHostingController?
        var cancellables: Set<AnyCancellable> = []

        init(editor: EditorModel, kind: String,
             t0: CFAbsoluteTime) {
            self.editor = editor
            self.kind = kind
            self.t0 = t0
        }
    }

    /// 探针登记（同一控制器重复登记无副作用）。
    func attach(navController nav: UINavigationController) {
        if navController !== nav {
            navController = nav
        }
    }

    // ── 呈现入口 ──────────────────────────────────────

    /// push 打开编辑器（kind: create/open）。编辑器在
    /// push 前完成首帧构建；新建篇的落焦认领等转场
    /// completion 后由门控放行（见 transitionCompleted）。
    func pushEditor(_ editor: EditorModel, kind: String,
                    onOpenMemo: @escaping (MemoItem) -> Void) {
        guard let nav = navController else {
            // 探针尚未登记（理论上只在首帧前一瞬）：下一
            // 主线程回合重试，有界 20 次后放弃并留痕。
            attachRetries += 1
            if attachRetries <= 20 {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.05) { [weak self] in
                    self?.pushEditor(editor, kind: kind,
                                     onOpenMemo: onOpenMemo)
                }
            } else {
                attachRetries = 0
                DiagLog.shared.log(.error,
                    "TRANSITION attach missing kind=\(kind)")
            }
            return
        }
        attachRetries = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        // CREATE dest 戳单点收敛于此（呈现发起点 == 旧
        // nav.dest 置位点，同回合）：仅新建篇带计时痕，
        // 普通打开在 noteCreateDest 内 guard 自行跳过。
        editor.noteCreateDest()
        let session = Session(editor: editor, kind: kind, t0: t0)
        let hc = makeEditorController(editor,
                                      onOpenMemo: onOpenMemo)
        session.hostVC = hc
        hc.onRemoved = { [weak self, weak session] in
            guard let session else { return }
            self?.endSession(session)
        }
        sessions[ObjectIdentifier(session)] = session
        // 首帧前置：承载视图建好并强制布局一趟，SwiftUI
        // 首轮 body 与块视图安装都在转场窗外完成。
        hc.loadViewIfNeeded()
        hc.view.frame = nav.view.bounds
        hc.view.layoutIfNeeded()
        session.tBuild = CFAbsoluteTimeGetCurrent()
        observeImage(session, nav: nav)
        nav.pushViewController(hc, animated: true)
        if let coord = nav.transitionCoordinator {
            coord.animate(alongsideTransition: nil) {
                [weak self, weak session] ctx in
                guard let session else { return }
                session.tEnd = CFAbsoluteTimeGetCurrent()
                if ctx.isCancelled {
                    self?.logTransition(session)
                } else {
                    self?.transitionCompleted(session)
                }
            }
        } else {
            session.tEnd = CFAbsoluteTimeGetCurrent()
            transitionCompleted(session)
        }
    }

    /// 关联笔记打开（编辑器内反链/wiki）：旧形态是同层
    /// 换 dest 内容（无 push 动画、返回直达列表），等价
    /// 实现为无动画替换栈顶承载控制器。栈顶不是编辑器
    /// 时退化为普通 push。
    func replaceTopEditor(
        _ editor: EditorModel,
        onOpenMemo: @escaping (MemoItem) -> Void) {
        guard let nav = navController,
              let top = nav.topViewController
                as? EditorHostingController,
              let old = sessions.values.first(where: {
                  $0.hostVC === top
              }) else {
            pushEditor(editor, kind: "link",
                       onOpenMemo: onOpenMemo)
            return
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        let session = Session(editor: editor, kind: "link",
                              t0: t0)
        let hc = makeEditorController(editor,
                                      onOpenMemo: onOpenMemo)
        session.hostVC = hc
        hc.onRemoved = { [weak self, weak session] in
            guard let session else { return }
            self?.endSession(session)
        }
        sessions[ObjectIdentifier(session)] = session
        hc.loadViewIfNeeded()
        hc.view.frame = nav.view.bounds
        hc.view.layoutIfNeeded()
        session.tBuild = CFAbsoluteTimeGetCurrent()
        observeImage(session, nav: nav)
        var stack = nav.viewControllers
        stack[stack.count - 1] = hc
        nav.setViewControllers(stack, animated: false)
        session.tEnd = CFAbsoluteTimeGetCurrent()
        // 旧会话的 onRemoved 会随旧控制器离开层级触发
        // endSession（订阅释放）；此处只需收新会话的尾。
        _ = old
        transitionCompleted(session)
    }

    // ── 内部 ──────────────────────────────────────────

    private func makeEditorController(
        _ editor: EditorModel,
        onOpenMemo: @escaping (MemoItem) -> Void)
        -> EditorHostingController {
        let view = EditorView(
            editor: editor,
            onOpenMemo: onOpenMemo,
            onClose: { [weak self] in
                self?.popTop()
            })
        return EditorHostingController(rootView: view)
    }

    private func popTop() {
        navController?.popViewController(animated: true)
    }

    /// 转场落定单点：开认领门（新建篇）+ 出 TRANSITION
    /// 行。带落焦的会话延迟 0.9s 出行，让 claim/kb 戳
    /// 先落（认领在开门后一轮更新内、键盘随后升起）。
    private func transitionCompleted(_ session: Session) {
        let editor = session.editor
        if editor.wantsInitialFocus {
            editor.openFocusGate()
            // 兜底再推一拍：首拍更新若未落到块视图（层
            // 级刚落定），0.2s 后旗仍在则再开一次门（开
            // 门动作本身幂等，只多一次 tick 发布）。
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.2) { [weak editor] in
                guard let editor,
                      editor.wantsInitialFocus else { return }
                editor.openFocusGate()
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.9) { [weak self, weak session] in
                guard let session else { return }
                self?.logTransition(session)
            }
        } else {
            logTransition(session)
        }
    }

    /// 图片页呈现（代旧 navigationDestination）：编辑
    /// 器 imageTarget 置位即 push、清空即 pop、页面被
    /// 返回钮/手势关掉时反向清空 imageTarget——与旧绑
    /// 定语义逐项等价。
    private func observeImage(_ session: Session,
                              nav: UINavigationController) {
        let editor = session.editor
        editor.$imageTarget
            .sink { [weak self, weak session, weak nav] target in
                guard let self, let session, let nav
                else { return }
                if let target {
                    guard session.imageVC == nil,
                          nav.topViewController
                            === session.hostVC else { return }
                    let page = ImagePageView(
                        fileId: target.fileId,
                        urlString: target.urlString,
                        name: target.name,
                        library: editor.library,
                        onClose: { [weak self] in
                            self?.popTop()
                        })
                    let ivc = ImageHostingController(
                        rootView: page)
                    ivc.onRemoved = { [weak session] in
                        guard let session else { return }
                        session.imageVC = nil
                        if session.editor.imageTarget != nil {
                            session.editor.imageTarget = nil
                        }
                    }
                    session.imageVC = ivc
                    nav.pushViewController(ivc, animated: true)
                } else if let ivc = session.imageVC,
                          nav.topViewController === ivc {
                    nav.popViewController(animated: true)
                }
            }
            .store(in: &session.cancellables)
    }

    private func endSession(_ session: Session) {
        session.cancellables.removeAll()
        sessions.removeValue(
            forKey: ObjectIdentifier(session))
    }

    /// TRANSITION 一行（四时点相对 push 起点 ms）：
    /// build=首帧前置构建、anim=纯转场动画段（tBuild→
    /// tEnd）、claim/kb 取 CREATE 戳（dest 基准换算到
    /// push 基准差 <1ms，同回合）。单段动画的判据：
    /// anim ≈ 系统 push 时长且 claim > anim（认领必在
    /// 转场结束后）、kb > claim。
    private func logTransition(_ session: Session) {
        guard !session.logged else { return }
        session.logged = true
        let ed = session.editor
        func rel(_ t: CFAbsoluteTime) -> String {
            t > 0 ? "\(Int((t - session.t0) * 1000))" : "na"
        }
        let animSeg = (session.tBuild > 0
            && session.tEnd > session.tBuild)
            ? "\(Int((session.tEnd - session.tBuild) * 1000))"
            : "na"
        DiagLog.shared.log(.info,
            "TRANSITION id=\(ed.item.id) "
            + "kind=\(session.kind) "
            + "build=\(rel(session.tBuild))ms "
            + "anim=\(animSeg)ms "
            + "claim=\(rel(ed.traceClaim))ms "
            + "kb=\(rel(ed.traceKb))ms")
    }
}
