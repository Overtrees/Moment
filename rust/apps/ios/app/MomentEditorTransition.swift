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
        // 在席登记（U0 地基）：桥/驱动据此判在席，
        // 登记点与会话点同回合，见 EditorSeatRegistry。
        EditorSeatRegistry.shared.seat(
            editor: editor, token: ObjectIdentifier(session))
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
        EditorSeatRegistry.shared.seat(
            editor: editor, token: ObjectIdentifier(session))
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

    /// 桥导航通道的关闭点（U0）：栈内有编辑器会话
    /// 时 pop 回根视图（列表）——图片页压在编辑器
    /// 之上时随栈一并退。编辑器消失收口走视图既
    /// 有 onDisappear（saveNow），与手势返回同路；
    /// 栈内无编辑器会话时回 false（调用方据在席事
    /// 实另行判读，不假成功）。
    @discardableResult
    func dismissSeatedEditor() -> Bool {
        guard let nav = navController else { return false }
        let inStack = sessions.values.contains { s in
            guard let hc = s.hostVC else { return false }
            return nav.viewControllers.contains {
                $0 === hc
            }
        }
        guard inStack else { return false }
        nav.popToRootViewController(animated: true)
        return true
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
        // 在席注销（U0）：带会话令牌，关联替换时旧
        // 会话后收口不会误清新会话的在席登记。
        EditorSeatRegistry.shared.unseat(
            token: ObjectIdentifier(session))
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

// ── 在席注册表 + 桥导航通道（U0 地基）──────────────
// 桥 M2 §7.1 的接线待办与 UI 自检驱动方案（plan_ui
// _selftest_driver.md）U0 共用的地基：编辑器会话的
// 在席事实只此一处登记——转场宿主在 push/替换时登
// 记、会话收口时注销；桥侧据此判 memo_busy、读在
// 席状态、经导航通道请求开/关编辑器。导航请求走
// 宿主 pushEditor 的正规呈现路径，不另起呈现栈；
// 通道未接线（安全模式下 ListView 不在层级、根视
// 图不构建）时请求一律明确拒绝，不假成功。

/// 在席状态快照（在席类工具的地基读数）：只出结
/// 构与状态键，不出正文（块只出 id/type 序）。
struct EditorSeatSnapshot {
    let memoId: String
    let title: String
    let focusBlockId: String?
    let editingBlockId: String?
    let draggingId: String?
    let blockIds: [String]
    let blockTypes: [String]
    let columnsActive: Bool
}

/// 在席注册表：当前编辑器会话的 (memoId, 模型弱引
/// 用)。登记/注销只由转场宿主在会话点调用；注销
/// 须带会话令牌——关联替换的收口序是新会话先登
/// 记、旧会话后注销，无令牌会误清新在席。
final class EditorSeatRegistry {
    static let shared = EditorSeatRegistry()

    private var token: ObjectIdentifier?
    private weak var editor: EditorModel?
    private var memoId: String?

    /// 在席变更钩子（fix_home_regressions_0957）：
    /// seat/unseat 是全部编辑器会话开始/结束的单
    /// 一收口（宿主 pushEditor/replaceTopEditor 均
    /// 经 seat），钩子在此处发出即覆盖手指/桥/关联
    /// 全部呈现路径。首页据此在会话边界收敛搜索焦
    /// 点：桥路径直调宿主 push、不经首页各辞焦点，
    /// 「搜索焦点不与编辑器会话共存」的不变量只能
    /// 在此边界成立，逐路径补辞焦必漏。由 ListView
    /// 在探针接线点登记（幂等覆盖写、恒指向现行
    /// ListView 实例）。
    var onSeatChange: ((Bool) -> Void)?

    func seat(editor: EditorModel,
              token: ObjectIdentifier) {
        self.editor = editor
        self.token = token
        memoId = editor.item.id
        DiagLog.shared.log(.info,
            "BRIDGE seat register memo=\(editor.item.id)")
        onSeatChange?(true)
    }

    func unseat(token: ObjectIdentifier) {
        guard self.token == token else { return }
        if let memoId {
            DiagLog.shared.log(.info,
                "BRIDGE seat unregister memo=\(memoId)")
        }
        self.token = nil
        editor = nil
        memoId = nil
        onSeatChange?(false)
    }

    /// 在席模型（弱引用已释放即视为退席）。
    var currentEditor: EditorModel? { editor }

    var currentMemoId: String? {
        editor != nil ? memoId : nil
    }

    func isSeated(_ id: String) -> Bool {
        currentMemoId == id
    }

    /// 在席快照（editor_get_state 的地基读数）。
    func snapshot() -> EditorSeatSnapshot? {
        guard let editor, let memoId else { return nil }
        return EditorSeatSnapshot(
            memoId: memoId,
            title: editor.title,
            focusBlockId: editor.focusBlockId,
            editingBlockId: editor.editingBlockId,
            draggingId: editor.draggingId,
            blockIds: editor.blocks.map { $0.id },
            blockTypes: editor.blocks.map { $0.type },
            columnsActive: editor.columnsActive)
    }

    /// 落焦地基（editor_focus_block 的消费点）：目
    /// 标块须在在席篇内存在才置 focusBlockId（置焦
    /// 语义与编辑器内既有落焦同路，如插图后落焦）。
    @discardableResult
    func focusBlock(_ blockId: String,
                    caretEnd: Bool) -> Bool {
        guard let editor,
              editor.blocks.contains(
                where: { $0.id == blockId })
        else { return false }
        editor.focusCaretEnd = caretEnd
        editor.focusBlockId = blockId
        return true
    }

    /// 立即落盘地基（editor_save_now 的消费点）。
    @discardableResult
    func saveNow() -> Bool {
        guard let editor else { return false }
        editor.saveNow()
        return true
    }
}

/// 桥导航拒绝口径（U0）：memo_not_found /
/// memo_busy / read_only_mode 为桥方案错误表的既
/// 有码；nav_unavailable / nav_timeout 为通道内
/// 部码——在席类工具入册批须先把这两码登记进错
/// 误表才可对外（本批只在 App 内与 Diag 中用）。
enum BridgeNavError: Error {
    /// 通道未接线（安全模式/列表不在位）。
    case navUnavailable
    /// 只读打开态（R2）：编辑器落不了盘，不开。
    case readOnlyMode
    /// 目标不存在或已软删/待删。
    case memoNotFound(String)
    /// 在席被他篇占用（带在席 memoId）：不抢导航、
    /// 不代关用户的编辑器。
    case seatOccupied(String)
    /// 等在席登记/注销超时（呈现事实未落定）。
    case seatTimeout

    var code: String {
        switch self {
        case .navUnavailable: return "nav_unavailable"
        case .readOnlyMode: return "read_only_mode"
        case .memoNotFound: return "memo_not_found"
        case .seatOccupied: return "memo_busy"
        case .seatTimeout: return "nav_timeout"
        }
    }
}

/// 桥导航通道：桥侧请求开/关编辑器的唯一入口。
/// 由根视图（ListView）在探针 attach 同点位接线
/// （宿主 + 库 + 关联打开回调，幂等）；请求-应答
/// 式：打开等在席登记对上号才回成功（方案
/// editor_open 口径「等模型 id 对上或超时」），
/// 关闭等注销落定才回成功。全程主队列（桥分发
/// 本就在主队列，轮询同队列续跑）。
final class BridgeNavigationChannel {
    static let shared = BridgeNavigationChannel()

    private weak var host: EditorTransitionHost?
    private weak var library: Library?
    private var openLinked: ((MemoItem) -> Void)?
    private var wired = false

    func wire(host: EditorTransitionHost,
              library: Library,
              openLinked: @escaping (MemoItem) -> Void) {
        self.host = host
        self.library = library
        self.openLinked = openLinked
        if !wired {
            wired = true
            DiagLog.shared.log(.info, "BRIDGE nav wire")
        }
    }

    /// 请求打开指定篇的编辑器。已在席同篇 = 现状
    /// 成功（already）；在席他篇 = memo_busy 拒
    /// 绝；软删/待删篇按不存在处理。
    func requestOpen(
        memoId: String,
        completion: @escaping
            (Result<EditorSeatSnapshot, BridgeNavError>)
            -> Void) {
        DiagLog.shared.log(.info,
            "BRIDGE nav request open memo=\(memoId)")
        func reject(_ e: BridgeNavError) {
            DiagLog.shared.log(.warn,
                "BRIDGE nav open rejected memo=\(memoId) "
                + "code=\(e.code)")
            completion(.failure(e))
        }
        guard let host, let library, let openLinked
        else { reject(.navUnavailable); return }
        if library.isReadOnly {
            reject(.readOnlyMode); return
        }
        let seat = EditorSeatRegistry.shared
        if let cur = seat.currentMemoId {
            if cur == memoId, let snap = seat.snapshot() {
                DiagLog.shared.log(.info,
                    "BRIDGE nav open ok memo=\(memoId) "
                    + "already=1")
                completion(.success(snap))
            } else {
                reject(.seatOccupied(cur))
            }
            return
        }
        guard let memo = library.memos.first(where: {
                  $0.id == memoId && $0.deletedAtMs == nil
              }),
              library.pendingDeletions[memoId] == nil
        else { reject(.memoNotFound(memoId)); return }
        host.pushEditor(
            EditorModel(item: memo, library: library),
            kind: "open", onOpenMemo: openLinked)
        waitForSeat(memoId: memoId, deadline: 2.5) {
            result in
            switch result {
            case .success(let snap):
                DiagLog.shared.log(.info,
                    "BRIDGE nav open ok memo=\(memoId)")
                completion(.success(snap))
            case .failure(let e):
                reject(e)
            }
        }
    }

    /// 请求关闭编辑器回首页。无在席 = 现状成功；
    /// 在席时经宿主 pop 回根，关闭收口走视图既有
    /// onDisappear（saveNow），与手势返回同路——
    /// 标题草稿未经 commitTitle 的部分同手势返回
    /// 同命运（commit 链是页眉返回钮的动作体，通
    /// 道不代按、不代存）。
    func requestClose(
        completion: @escaping
            (Result<EditorSeatSnapshot?, BridgeNavError>)
            -> Void) {
        DiagLog.shared.log(.info,
            "BRIDGE nav request close")
        func reject(_ e: BridgeNavError) {
            DiagLog.shared.log(.warn,
                "BRIDGE nav close rejected code=\(e.code)")
            completion(.failure(e))
        }
        guard let host else {
            reject(.navUnavailable); return
        }
        let seat = EditorSeatRegistry.shared
        guard let cur = seat.currentMemoId else {
            DiagLog.shared.log(.info,
                "BRIDGE nav close ok memo=- already=1")
            completion(.success(nil))
            return
        }
        if !host.dismissSeatedEditor() {
            // 注册表称在席、宿主栈内却无此会话：内
            // 部不一致留痕，结论仍以等注销的结果为
            // 准（超时即 nav_timeout，不假成功）。
            DiagLog.shared.log(.error,
                "BRIDGE nav error seat_inconsistent "
                + "memo=\(cur)")
        }
        waitForUnseat(memoId: cur, deadline: 2.5) {
            result in
            switch result {
            case .success:
                DiagLog.shared.log(.info,
                    "BRIDGE nav close ok memo=\(cur)")
                completion(.success(nil))
            case .failure(let e):
                reject(e)
            }
        }
    }

    /// 等在席对上号（100ms 轮询）：呈现是异步的
    /// （探针未登记时宿主有界重试），请求-应答以
    /// 登记事实为准，不以 push 已调用为准；等期
    /// 间在席被他篇占走即 memo_busy。
    private func waitForSeat(
        memoId: String, deadline: TimeInterval,
        completion: @escaping
            (Result<EditorSeatSnapshot, BridgeNavError>)
            -> Void) {
        let seat = EditorSeatRegistry.shared
        if seat.currentMemoId == memoId,
           let snap = seat.snapshot() {
            completion(.success(snap))
            return
        }
        if let cur = seat.currentMemoId {
            completion(.failure(.seatOccupied(cur)))
            return
        }
        guard deadline > 0 else {
            completion(.failure(.seatTimeout))
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.1) { [weak self] in
            self?.waitForSeat(
                memoId: memoId,
                deadline: deadline - 0.1,
                completion: completion)
        }
    }

    /// 等注销落定（在席不再是目标篇即成：注销或
    /// 被替换都算关闭已生效）。
    private func waitForUnseat(
        memoId: String, deadline: TimeInterval,
        completion: @escaping
            (Result<Void, BridgeNavError>) -> Void) {
        if EditorSeatRegistry.shared.currentMemoId
            != memoId {
            completion(.success(()))
            return
        }
        guard deadline > 0 else {
            completion(.failure(.seatTimeout))
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.1) { [weak self] in
            self?.waitForUnseat(
                memoId: memoId,
                deadline: deadline - 0.1,
                completion: completion)
        }
    }
}
