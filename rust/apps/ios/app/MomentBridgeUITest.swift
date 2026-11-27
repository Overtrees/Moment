// ── 桥内 UI 自检驱动（U 批，方案
// plan_ui_selftest_driver.md）──
// 桥住在 App 进程内：驱动在主线程走与手指相同
// 的 handler 路径执行编译期内置场景，把状态、
// 几何量测与 Diag 证据经桥回传判读。口径钉
// 死：不构造 UITouch、不注入 UIKit 事件、不
// 碰私有 API——可驱动面的前提是其手势/按钮动
// 作体已抽成具名入口，手指与驱动共用同一闭包
// （单一来源规则，方案 §3.2）。等价面是
// handler 以内的状态机与呈现；命中投递与识别
// 器仲裁不在证据面（方案 §3.5/§6，报告不得
// 升级表述）。
//
// 本文件：注册表 + 注册锚点 + 步进引擎 + S1
// 场景 + 夹具卫生链 + 并发门/复原链 + 桥工
// 具面（uitest 四件）。注册纪律照 DragPress-
// Anchor 已实证模式：0 尺寸寄生锚点、
// updateUIView 刷新注册、dismantle 注销。

import Foundation
import SwiftUI
import UIKit

// ── 视图注册表 ──

/// 可测面条目：闭包只捕获视图状态对象（编辑
/// 器模型/UI 状态/字段控制面），不捕获视图本
/// 体；frame 闭包返回 nil = 面已离场，驱动据
/// 此判 surface_missing，不拿陈旧 frame 下结
/// 论。同 id+instance 重复注册以后到为准；注
/// 销只认注册属主，防行回收误注销新实例。
struct UITestSurfaceEntry {
    let id: String
    let kind: String
    let instance: String
    /// frame 来源：条目自带（编辑器/菜单面读
    /// UI 量测）或由注册锚点的宿主视图几何填
    /// 充（胶囊面，DragPress Row.hostView 先
    /// 例）——由 UITestAnchor 的 providesFrame
    /// 标志决定，见锚点 updateUIView。
    var frameInWindow: () -> CGRect? = { nil }
    /// 具名动作：参数为可选数值（胶囊 tap 的
    /// atX），其余动作忽略。
    var actions: [String: (Double?) -> Void] = [:]
    var state: [String: () -> String] = [:]
    var setText: ((String) -> Void)?
}

final class UITestRegistry {
    static let shared = UITestRegistry()

    private var entries: [String: UITestSurfaceEntry] = [:]
    private var owners: [String: UUID] = [:]
    private var ownedKey: [UUID: String] = [:]

    private func key(_ id: String,
                     _ instance: String) -> String {
        id + "\u{1}" + instance
    }

    func register(_ entry: UITestSurfaceEntry,
                  owner: UUID) {
        let k = key(entry.id, entry.instance)
        if let prev = owners[k], prev != owner {
            ownedKey[prev] = nil
        }
        if let old = ownedKey[owner], old != k {
            entries[old] = nil
            owners[old] = nil
        }
        entries[k] = entry
        owners[k] = owner
        ownedKey[owner] = k
    }

    func unregister(owner: UUID) {
        guard let k = ownedKey[owner] else { return }
        ownedKey[owner] = nil
        if owners[k] == owner {
            owners[k] = nil
            entries[k] = nil
        }
    }

    func entry(id: String,
               instance: String) -> UITestSurfaceEntry? {
        entries[key(id, instance)]
    }

    func all() -> [UITestSurfaceEntry] {
        Array(entries.values)
    }
}

/// 注册锚点（DragPressAnchor 同构）：0 尺寸、
/// 不参与命中；updateUIView 以当轮 body 闭包
/// 刷新注册（回调随渲染保鲜），dismantle 按属
/// 主注销。
struct UITestAnchor: UIViewRepresentable {
    var providesFrame = false
    var makeEntry: () -> UITestSurfaceEntry

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: UIView,
                      context: Context) {
        var entry = makeEntry()
        if !providesFrame {
            entry.frameInWindow = { [weak v] in
                guard let v else { return nil }
                return v.convert(v.bounds, to: nil)
            }
        }
        context.coordinator.register(entry)
    }

    static func dismantleUIView(
        _ v: UIView, coordinator: Coordinator) {
        coordinator.unregister()
    }

    final class Coordinator {
        private let owner = UUID()
        func register(_ entry: UITestSurfaceEntry) {
            UITestRegistry.shared.register(
                entry, owner: owner)
        }
        func unregister() {
            UITestRegistry.shared.unregister(
                owner: owner)
        }
    }
}

/// 滚动锚点（U4a）：与 UITestAnchor 同注册纪
/// 律，另持宿主视图弱引用——动作/量测沿
/// superview 链找承载的 UIScrollView（编辑器
/// 单列 ScrollView 的 UIKit 本体），程序化设
/// contentOffset 驱动滚动。app 的 scrollY 由
/// 内容内探针派生（非 contentOffset 直读），
/// 两量各有 state 键分开回报，场景据探针量判
/// 落定、据 offsetY 判驱动到达。
struct UITestScrollAnchor: UIViewRepresentable {
    var makeEntry: () -> UITestSurfaceEntry

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: UIView,
                      context: Context) {
        context.coordinator.host = v
        var entry = makeEntry()
        entry.frameInWindow = { [weak v] in
            guard let v else { return nil }
            return v.convert(v.bounds, to: nil)
        }
        let coord = context.coordinator
        entry.actions["to"] = { [weak coord] y in
            coord?.scrollTo(y ?? 0)
        }
        entry.state["offsetY"] = { [weak coord] in
            coord?.offsetY().map { "\($0)" } ?? ""
        }
        context.coordinator.register(entry)
    }

    static func dismantleUIView(
        _ v: UIView, coordinator: Coordinator) {
        coordinator.unregister()
    }

    final class Coordinator {
        private let owner = UUID()
        weak var host: UIView?

        func register(_ entry: UITestSurfaceEntry) {
            UITestRegistry.shared.register(
                entry, owner: owner)
        }
        func unregister() {
            UITestRegistry.shared.unregister(
                owner: owner)
        }
        func scrollView() -> UIScrollView? {
            var v = host?.superview
            while let cur = v {
                if let sv = cur as? UIScrollView {
                    return sv
                }
                v = cur.superview
            }
            return nil
        }
        func scrollTo(_ y: Double) {
            guard let sv = scrollView() else { return }
            sv.setContentOffset(
                CGPoint(x: sv.contentOffset.x,
                        y: CGFloat(y)),
                animated: false)
        }
        func offsetY() -> CGFloat? {
            scrollView()?.contentOffset.y
        }
    }
}

// ── 夹具登记与残留扫描 ──

/// 夹具双标记（方案 §5.1）：标题前缀「自检」
/// 肉眼可辨 + 进程内登记集程序只认。驱动的一
/// 切写路径先验目标 id ∈ 登记集，不在集内即
/// 拒（fixture_guard）——结构上够不到用户既
/// 有笔记。
enum UITestFixture {
    static let titleMark = "「自检」"
    private static var ids: Set<String> = []

    static func register(_ id: String) {
        ids.insert(id)
    }
    static func unregister(_ id: String) {
        ids.remove(id)
    }
    static func isFixture(_ id: String) -> Bool {
        ids.contains(id)
    }
}

/// 残留兜底（方案 §5.1）：进程在运行中被杀时
/// 夹具可能残留——标题带自检标记且不在活动
/// run 登记集内的篇即孤儿。只报不删：启动链/
/// app_state 顺手扫一遍记行 + 计数，删除由助
/// 手侧以桥工具按受限形态处理或用户手动删。
enum UITestFixtureSweep {
    static func orphans(
        in library: Library) -> [MemoItem] {
        library.memos.filter {
            $0.deletedAtMs == nil
                && $0.title.hasPrefix(
                    UITestFixture.titleMark)
                && !UITestFixture.isFixture($0.id)
        }
    }

    static func noteOrphans(in library: Library) {
        for m in orphans(in: library) {
            DiagLog.shared.logOnce(
                "uitest-orphan-\(m.id)", .warn,
                "UITEST fixture orphan id=\(m.id)")
        }
    }
}

// ── 步进引擎 ──

struct UITestAssertion {
    let name: String
    let pass: Bool
    let expected: String
    let actual: String

    var dict: [String: Any] {
        ["name": name, "pass": pass,
         "expected": expected, "actual": actual]
    }
}

struct UITestStepOutcome {
    var ok = true
    var assertions: [UITestAssertion] = []
    var note: String?
}

struct UITestStep {
    let kind: String
    let label: String
    let body: (UITestRunContext,
               @escaping (UITestStepOutcome) -> Void)
        -> Void
}

/// 运行上下文：场景步的共享面（夹具、窗口、
/// 等待原语）。等待一律走落定判据（方案
/// §3.4）：Diag 行入环可见、状态谓词连续两轮
/// 成立、布局量测连续两次差 ≤0.5pt——不许写
/// 死睡眠冒充落定。
final class UITestRunContext {
    let runId: String
    let library: Library
    let fixtureId: String
    let preLibraryHash: String
    let shortTitle: String
    let longTitle: String
    let shortTitle2: String
    let deadline: Date
    var stepStart = Date()
    var expectSeat = false
    var aborted = false
    var timedOut = false
    var hygieneFailed = false
    /// 跨步存储（U4a 泛化）：场景步间传递量测与
    /// 预期值（落点预期标量、夹具块 id 表等），
    /// 不再靠场景专属字段逐个加进 ctx。
    var store: [String: Any] = [:]

    init(runId: String, library: Library,
         fixtureId: String, preLibraryHash: String,
         hash4: String) {
        self.runId = runId
        self.library = library
        self.fixtureId = fixtureId
        self.preLibraryHash = preLibraryHash
        self.deadline = Date()
            .addingTimeInterval(90)
        // 标题模板（App 内生成，不由桥参数传入
        // 正文）：短 ≤10 标量（非截断态）、长
        // >10 标量（截断态），全程带自检前缀。
        shortTitle = UITestFixture.titleMark
            + hash4 + "短"
        shortTitle2 = UITestFixture.titleMark
            + hash4 + "短二"
        longTitle = UITestFixture.titleMark
            + hash4 + "这是一个用于自检的长标题文本"
    }

    var shortId: String { String(runId.prefix(8)) }

    /// 步边界漂移检测（方案 §5.2）：在席篇被
    /// 用户切走/关掉即判漂移，作业转
    /// aborted_user_active 走复原链，不与用户
    /// 抢 UI（步边界级，非逐帧抢占——诚实标
    /// 注见方案）。
    func drifted() -> Bool {
        if expectSeat,
           EditorSeatRegistry.shared.currentMemoId
            != fixtureId {
            aborted = true
            return true
        }
        return false
    }

    /// 轮询原语：100ms 一轮；漂移/总超时在此
    /// 收口（cond 不再被调用，直接回 false）。
    func poll(timeoutMs: Int,
              _ cond: @escaping () -> Bool,
              done: @escaping (Bool) -> Void) {
        let limit = Date().addingTimeInterval(
            Double(timeoutMs) / 1000)
        func tick() {
            if drifted() { done(false); return }
            if Date() > deadline {
                timedOut = true
                done(false)
                return
            }
            if cond() { done(true); return }
            if Date() >= limit { done(false); return }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.1) { tick() }
        }
        tick()
    }

    func surface(_ id: String)
        -> UITestSurfaceEntry? {
        UITestRegistry.shared.entry(
            id: id, instance: "-")
    }

    func state(_ surface: String,
               _ key: String) -> String? {
        self.surface(surface)?.state[key]?()
    }

    /// 本步窗口内的 Diag 行（ts ≥ 步起始）。
    func windowEntries() -> [DiagEntry] {
        let from = stepStart.timeIntervalSince1970
        return DiagLog.shared.today.filter {
            $0.ts >= from
        }
    }

    /// 等 Diag 行出现（窗口内包含 pattern）。
    func waitDiag(
        pattern: String, timeoutMs: Int,
        done: @escaping ([DiagEntry]) -> Void) {
        var found: [DiagEntry] = []
        poll(timeoutMs: timeoutMs) {
            found = self.windowEntries().filter {
                $0.text.contains(pattern)
            }
            return !found.isEmpty
        } done: { _ in done(found) }
    }

    /// 等状态谓词（连续两轮成立才算落定）。
    func waitState(
        surface: String, key: String,
        equals: String, timeoutMs: Int,
        done: @escaping (Bool, String?) -> Void) {
        var streak = 0
        var last: String?
        poll(timeoutMs: timeoutMs) {
            last = self.state(surface, key)
            if last == equals {
                streak += 1
            } else {
                streak = 0
            }
            return streak >= 2
        } done: { ok in done(ok, last) }
    }

    /// 等布局落定：同一量测连续两次（≥100ms
    /// 间隔）差 ≤0.5pt 且量测非空。
    func waitLayout(
        probe: @escaping () -> Double?,
        timeoutMs: Int,
        done: @escaping (Bool, Double?) -> Void) {
        var last: Double?
        poll(timeoutMs: timeoutMs) {
            let v = probe()
            defer { last = v }
            guard let v, let l = last else {
                return false
            }
            return abs(v - l) <= 0.5
        } done: { ok in done(ok, last) }
    }
}

/// 作业留存：进程内最近 5 个 runId 供轮询；
/// 进程重启即失（证据真源是 Diag 与
/// operations 流水，作业结果只是呈现层）。
final class UITestJob {
    let runId: String
    let scenario: String
    let startedAt = Date()
    var status = "running"
    var code = "running"
    var finishedAt: Date?
    var stepRecords: [[String: Any]] = []
    /// 实况 activityId（权限批挂点）：begin 起、
    /// finish 收口，非实况环境为 nil。
    var liveId: String?
    var fixtureInfo: [String: Any] = [:]
    var measurements: [String: Any] = [:]
    var grades: [String: Any] = [:]

    init(runId: String, scenario: String) {
        self.runId = runId
        self.scenario = scenario
    }

    func payload() -> [String: Any] {
        var p: [String: Any] = [
            "runId": runId,
            "scenario": scenario,
            "status": status,
            "code": code,
            "startedAtMs": Int64(
                startedAt.timeIntervalSince1970
                    * 1000),
            "fixture": fixtureInfo,
            "steps": stepRecords,
            "measurements": measurements,
            "grades": grades,
        ]
        if let f = finishedAt {
            p["finishedAtMs"] = Int64(
                f.timeIntervalSince1970 * 1000)
        }
        return p
    }
}

/// 夹具形态（U4a 目录化）：title = 单空段（标
/// 题景）；blocks = 全块型矩阵 + 填充段（块矩
/// 阵/斜杠景，填充保内容可滚）；tall = 多段高
/// 内容（紧凑坞景，保 scrollY 可越 30）。
enum UITestFixtureKind {
    case title, blocks, tall
}

/// 场景定义（目录条目）：名、夹具形态、证据分
/// 级、步表构造。begin() 只查目录，不再逐景硬
/// 编码（U4a 泛化，代 S1 单景特判）。
struct UITestScenarioDef {
    let name: String
    let fixture: UITestFixtureKind
    let grades: [String: Any]
    let steps: () -> [UITestStep]
}

/// 夹具模板（App 内建、桥参数不传正文）：块节
/// 点构造与 Library.create() 同式（id 前缀 +
/// type/children/attrs 键集）；未知类型块用虚
/// 构 type 验降级呈现与再保存保真（EDT-17）。
enum UITestFixtureTemplate {

    private static func nid() -> String {
        "b-" + UUID().uuidString.prefix(8)
            .lowercased()
    }

    private static func node(
        _ type: String, text: String? = nil,
        attrs: [String: Any]? = nil,
        children: [[String: Any]]? = nil
    ) -> [String: Any] {
        var n: [String: Any] = [
            "id": nid(), "type": type,
        ]
        if let children {
            n["children"] = children
        } else if let text {
            n["children"] = [["text": text]]
        } else {
            n["children"] = [[String: Any]]()
        }
        if let attrs { n["attrs"] = attrs }
        return n
    }

    /// 返回 (块集, 类型→首块 id, 顶层类型序）。
    static func build(
        _ kind: UITestFixtureKind
    ) -> (blocks: [BlockState],
          byType: [String: String],
          types: [String])? {
        let nodes: [[String: Any]]
        switch kind {
        case .title:
            return nil
        case .blocks:
            let item = { (t: String) in
                node("list-item", text: t)
            }
            nodes = [
                node("paragraph", text: "自检段落甲"),
                node("heading", text: "自检标题",
                     attrs: ["level": 1]),
                node("todo", text: "自检待办",
                     attrs: ["checked": false]),
                node("quote", text: "自检引用"),
                node("callout", text: "自检提示",
                     attrs: ["calloutType": "note"]),
                node("codeBlock", text: "let a = 1"),
                node("divider"),
                node("bulleted-list",
                     children: [item("自检项一"),
                                item("自检项二")]),
                node("numbered-list",
                     attrs: ["start": 1],
                     children: [item("自检序一"),
                                item("自检序二")]),
                node("futureWidget",
                     text: "自检未知块正文"),
                node("paragraph", text: "自检段落乙"),
            ] + (1...10).map {
                node("paragraph",
                     text: "自检填充 \($0)")
            }
        case .tall:
            nodes = [node("paragraph",
                          text: "自检段落甲")]
                + (1...14).map {
                    node("paragraph",
                         text: "自检填充 \($0)")
                }
        }
        let blocks = nodes.map { BlockState(node: $0) }
        var byType: [String: String] = [:]
        for b in blocks where byType[b.type] == nil {
            byType[b.type] = b.id
        }
        return (blocks, byType, blocks.map { $0.type })
    }
}

final class UITestDriver {
    static let shared = UITestDriver()

    private var jobs: [String: UITestJob] = [:]
    private var jobOrder: [String] = []
    private var activeRunId: String?

    var isBusy: Bool { activeRunId != nil }

    /// 场景目录（U4a）：六景 + S1。grades 口径
    /// 恒守方案 §3.5——驱动证状态机/几何/落盘，
    /// 触摸投递与键盘呈现不升级表述。
    static let catalog: [String: UITestScenarioDef] = {
        func grades(_ note: String)
            -> [String: Any] {
            [
                "stateMachine": "proven",
                "persistence": "proven",
                "hitDelivery": "unknown",
                "keyboard": "unknown",
                "note": note,
            ]
        }
        let defs: [UITestScenarioDef] = [
            UITestScenarioDef(
                name: "title_capsule_reedit",
                fixture: .title,
                grades: grades(
                    "S1 证标题胶囊二次编辑的状态"
                    + "机回路与落盘回读（handler 以"
                    + "内）；手指点按能否到达入口、键"
                    + "盘呈现与光标落点不在证据面，仍"
                    + "以真机点按 + Diag 成对行终判。"),
                steps: UITestScenarioS1.steps),
            UITestScenarioDef(
                name: "title_capsule_reedit_compact",
                fixture: .tall,
                grades: grades(
                    "EDT-06：紧凑坞（横排）态下截断"
                    + "标题二次进入 + 会话期坞态锁存"
                    + "零翻转；滚动由驱动程序化驱动，"
                    + "滚动手感不在证据面。"),
                steps: UITestScenarioCompact.steps),
            UITestScenarioDef(
                name: "title_caret_assert",
                fixture: .title,
                grades: grades(
                    "EDT-07：落点算式与记号先行/施"
                    + "加回读在驱动面内对账；坐标投"
                    + "递到真机字段的精度仍一例真机"
                    + "终判。"),
                steps: UITestScenarioCaret.steps),
            UITestScenarioDef(
                name: "title_commit_escape",
                fixture: .title,
                grades: grades(
                    "EDT-08：标题提交口径（trim/空"
                    + "回退）与 Esc 还原草稿的状态机"
                    + "回路；硬件键盘 Esc 实键不在证"
                    + "据面。"),
                steps: UITestScenarioCommitEscape
                    .steps),
            UITestScenarioDef(
                name: "done_capsule_cycle",
                fixture: .title,
                grades: grades(
                    "EDT-09：完成胶囊两轮升降循环 + "
                    + "kb/done/collapse 三行序（键盘"
                    + "通知单点喂入口径）；键盘呈现"
                    + "手感不在证据面。"),
                steps: UITestScenarioDoneCapsule
                    .steps),
            UITestScenarioDef(
                name: "slash_menu_flow",
                fixture: .blocks,
                grades: grades(
                    "EDT-18/19：斜杠触发/过滤/导航/"
                    + "执行的状态机（模型层 handler);"
                    + "逐字输入与 IME 不等价、行内命"
                    + "令抽样待 U4b 块面 setText。"),
                steps: UITestScenarioSlash.steps),
            UITestScenarioDef(
                name: "block_type_matrix",
                fixture: .blocks,
                grades: grades(
                    "EDT-16/17：全块型在位/帧落定/"
                    + "待办勾选落盘/未知块保真（模型"
                    + "与回读面）；未知块降级呈现的"
                    + "像素形态不在证据面。转换清字"
                    + "段断言对齐 E3 落码后语义，E3 "
                    + "未落前该步预期红。"),
                steps: UITestScenarioBlockMatrix
                    .steps),
        ]
        var d: [String: UITestScenarioDef] = [:]
        for def in defs { d[def.name] = def }
        return d
    }()

    func job(_ runId: String) -> UITestJob? {
        jobs[runId]
    }

    /// 场景引擎共用互斥（M3a，plan_bridge_m3
    /// §4.2/§8.5）：run 互斥锁归先落地的驱动核
    /// 持有（activeRunId 单点），场景引擎经此
    /// 占/放，不另造第二把锁。引擎 run 在位时
    /// uitest_run 的 begin() 以 isBusy 回
    /// driver_busy，同口径互斥。
    func tryClaimExternalRun(_ runId: String) -> Bool {
        guard activeRunId == nil else { return false }
        activeRunId = runId
        return true
    }

    func releaseExternalRun(_ runId: String) {
        if activeRunId == runId {
            activeRunId = nil
        }
    }

    /// 受理：并发门（方案 §5.2）在此逐项查——
    /// 安全/只读/OPS 门已由分发器与工具面先行
    /// （检查序见 B25-9），此处只查呈现面并发：
    /// 前台 active、无在席编辑器（用户正编辑真
    /// 实笔记时绝不抢导航、不代保存）、浮层静
    /// 默、无其他 run。
    func begin(scenario: String,
               library: Library)
        -> Result<String, BridgeToolError> {
        guard let def = Self.catalog[scenario]
        else {
            return .failure(.invalidParams(
                "unknown scenario: \(scenario) "
                + "(registered: "
                + Self.catalog.keys.sorted()
                    .joined(separator: ", ")
                + ")"))
        }
        if isBusy {
            return .failure(BridgeToolError(
                code: "driver_busy",
                message: "another uitest run is "
                    + "in progress"))
        }
        guard UIApplication.shared.applicationState
                == .active else {
            return .failure(BridgeToolError(
                code: "device_busy",
                message: "app is not in the "
                    + "foreground-active state"))
        }
        if let seat = EditorSeatRegistry.shared
            .currentMemoId {
            return .failure(BridgeToolError(
                code: "device_busy",
                message: "memo \(seat) is open in "
                    + "the editor; the driver does "
                    + "not preempt user editing"))
        }
        if let menu = UITestRegistry.shared.entry(
            id: "editor.menuPanel", instance: "-"),
           menu.state["open"]?() == "true" {
            return .failure(BridgeToolError(
                code: "device_busy",
                message: "an editor overlay is open"))
        }
        let runId = UUID().uuidString
            .prefix(8).lowercased()
            + "-" + String(UUID().uuidString
                .prefix(4)).lowercased()
        let job = UITestJob(
            runId: runId, scenario: scenario)
        job.grades = def.grades
        jobs[runId] = job
        jobOrder.append(runId)
        while jobOrder.count > 5 {
            let old = jobOrder.removeFirst()
            if old != runId { jobs[old] = nil }
        }
        activeRunId = runId
        DiagLog.shared.log(.info,
            "UITEST run begin run=\(jobShort(runId)) "
            + "scenario=\(scenario)")
        // 实况挂点（权限批 §5.3）：驱动核执行开始
        // 起实况（非两段提交发 token 时），步进在
        // runSteps 更新、终态在 finish 收口。
        job.liveId = MomentLiveOps.shared.start(
            kind: .scenario,
            title: Lang.t("liveops.scenario"),
            step: scenario,
            total: def.steps().count)
        setup(job: job, library: library, def: def)
        return .success(runId)
    }

    private func jobShort(_ runId: String) -> String {
        String(runId.prefix(8))
    }

    /// 场景前置（方案 §5.1）：先快照（失败即中
    /// 止），记创建前库哈希，再由 App 内
    /// Library.create() 建夹具篇（内置模板、不
    /// 经中继、不经 notes_create 工具面）。
    private func setup(job: UITestJob,
                       library: Library,
                       def: UITestScenarioDef) {
        switch BridgeWriteSupport.shared
            .takeSnapshot(
                library: library,
                reason: "uitest_run") {
        case .failure:
            finish(job: job, ctx: nil,
                   failedStep: nil,
                   code: "snapshot_failed",
                   unrestored: [])
            return
        case .success(let snapId):
            let preHash = library.libraryHash()
            let item = library.create()
            guard library.memos.contains(
                where: { $0.id == item.id }) else {
                finish(job: job, ctx: nil,
                       failedStep: nil,
                       code: "library_unavailable",
                       unrestored: [])
                return
            }
            UITestFixture.register(item.id)
            let hash4 = String(job.runId
                .prefix(4))
            var titled = item
            titled.title = UITestFixture.titleMark
                + hash4 + "短"
            // 夹具形态（目录声明）：非 title 形
            // 态以模板块集替换 create() 的单空段
            // 后同路 persist（写面仍只夹具自篇）。
            let built = UITestFixtureTemplate
                .build(def.fixture)
            if let built {
                titled.blocks = built.blocks
            }
            library.persist(titled)
            DiagLog.shared.log(.info,
                "UITEST fixture create id=\(item.id)")
            job.fixtureInfo = [
                "memoId": item.id,
                "preLibraryHash": preHash,
                "snapshotId": snapId,
            ]
            let ctx = UITestRunContext(
                runId: job.runId, library: library,
                fixtureId: item.id,
                preLibraryHash: preHash,
                hash4: hash4)
            if let built {
                ctx.store["blockIdByType"] =
                    built.byType
                ctx.store["blockTypes"] =
                    built.types
                ctx.store["paragraphIds"] =
                    built.blocks.filter {
                        $0.type == "paragraph"
                    }.map { $0.id }
            }
            runSteps(job: job, ctx: ctx,
                     steps: def.steps(),
                     index: 0, failedStep: nil)
        }
    }

    /// 串行步进：每步后让出 runloop 再续（引擎
    /// 与步进都在主队列，async 续跑不长占主线
    /// 程）。步失败即停步转收尾（复原链在
    /// finish 内）。
    private func runSteps(
        job: UITestJob, ctx: UITestRunContext,
        steps: [UITestStep], index: Int,
        failedStep: Int?) {
        if let failedStep {
            finish(job: job, ctx: ctx,
                   failedStep: failedStep,
                   code: nil, unrestored: nil)
            return
        }
        guard index < steps.count else {
            finish(job: job, ctx: ctx,
                   failedStep: nil,
                   code: nil, unrestored: nil)
            return
        }
        if ctx.drifted() || ctx.timedOut {
            finish(job: job, ctx: ctx,
                   failedStep: index + 1,
                   code: nil, unrestored: nil)
            return
        }
        let step = steps[index]
        ctx.stepStart = Date()
        let t0 = Date()
        step.body(ctx) { outcome in
            let ms = Int(Date()
                .timeIntervalSince(t0) * 1000)
            var record: [String: Any] = [
                "n": index + 1,
                "kind": step.kind,
                "label": step.label,
                "waitMs": ms,
                "ok": outcome.ok,
                "assertions": outcome.assertions
                    .map { $0.dict },
                "diag": ctx.windowEntries()
                    .filter { e in
                        e.text.hasPrefix("EDIT ")
                            || e.text.hasPrefix(
                                "UITEST ")
                            || e.text.hasPrefix(
                                "TRANSITION ")
                            || e.text.hasPrefix(
                                "BRIDGE nav")
                            || e.text.hasPrefix(
                                "BRIDGE seat")
                            || e.text.hasPrefix(
                                "SLASH ")
                            || e.text.hasPrefix(
                                "SCROLL ")
                    }
                    .map { $0.line },
            ]
            if let note = outcome.note {
                record["note"] = note
            }
            job.stepRecords.append(record)
            for a in outcome.assertions where !a.pass {
                DiagLog.shared.log(.warn,
                    "UITEST assert fail "
                    + "name=\(a.name)")
            }
            DiagLog.shared.log(.info,
                "UITEST step n=\(index + 1) "
                + "kind=\(step.kind) "
                + "ok=\(outcome.ok ? 1 : 0) "
                + "ms=\(ms)")
            MomentLiveOps.shared.update(
                id: job.liveId, step: step.label,
                done: index + 1, total: steps.count)
            DispatchQueue.main.async {
                self.runSteps(
                    job: job, ctx: ctx, steps: steps,
                    index: index + 1,
                    failedStep: outcome.ok
                        ? nil : index + 1)
            }
        }
    }

    /// 收尾：任何非 ok 结束必须回到 run 前呈现
    /// 态——复原链（方案 §5.3）后做卫生对账；
    /// 结果码优先级：restore_failed >
    /// hygiene_failed > aborted_user_active >
    /// run_timeout > step_failed > ok。
    /// setup 阶段失败（ctx 为 nil）无呈现面可
    /// 复原，直接以给定码收尾。
    private func finish(
        job: UITestJob, ctx: UITestRunContext?,
        failedStep: Int?, code: String?,
        unrestored: [String]?) {
        guard let ctx else {
            job.code = code ?? "step_failed"
            job.status = "failed"
            job.finishedAt = Date()
            activeRunId = nil
            MomentLiveOps.shared.end(
                id: job.liveId, result: .failed,
                step: job.code)
            DiagLog.shared.log(.info,
                "UITEST run end "
                + "run=\(jobShort(job.runId)) "
                + "code=\(job.code)")
            return
        }
        restore(ctx: ctx) { unrestored in
            let postHash = ctx.library
                .libraryHash()
            let hashMatch = postHash
                == ctx.preLibraryHash
            DiagLog.shared.log(.info,
                "UITEST hygiene "
                + "hashMatch=\(hashMatch ? 1 : 0)")
            job.fixtureInfo["postLibraryHash"] =
                postHash
            job.fixtureInfo["cleaned"] =
                unrestored.isEmpty
            BridgeWriteSupport.shared
                .recordCompletion(
                    tool: "uitest_run",
                    idemKey: nil, idemHash: "",
                    payload: [
                        "targetId": ctx.fixtureId,
                        "preDocHash":
                            ctx.preLibraryHash,
                        "postDocHash": postHash,
                    ])
            let finalCode: String
            if !unrestored.isEmpty {
                finalCode = "restore_failed"
            } else if !hashMatch {
                finalCode = "hygiene_failed"
            } else if ctx.aborted {
                finalCode = "aborted_user_active"
            } else if ctx.timedOut {
                finalCode = "run_timeout"
            } else if failedStep != nil {
                finalCode = "step_failed"
            } else {
                finalCode = "ok"
            }
            job.code = finalCode
            job.status = finalCode == "ok"
                ? "done" : "failed"
            job.finishedAt = Date()
            self.activeRunId = nil
            MomentLiveOps.shared.end(
                id: job.liveId,
                result: finalCode == "ok" ? .ok : .failed,
                step: finalCode)
            DiagLog.shared.log(
                finalCode == "ok" ? .info : .warn,
                "UITEST run end "
                + "run=\(self.jobShort(job.runId)) "
                + "code=\(finalCode)")
        }
    }

    /// 复原链（方案 §5.3 固定序，状态驱动、可
    /// 重入）：① 标题会话按 Esc 口径还原草稿并
    /// 辞焦；② 关浮层；③ 驱动拾起态复位（U1
    /// 不进入拾起态，本步恒空转，U3 补）；④ 关
    /// 驱动打开的编辑器；⑤ 夹具清理（软删 +
    /// 立即真删 + 回读断言消失）。任一未复原项
    /// 记 error 行并回报清单——这是唯一允许带
    /// 着状态结束的情形，且必须向用户报告。
    private func restore(
        ctx: UITestRunContext,
        done: @escaping ([String]) -> Void) {
        var unrestored: [String] = []
        func mark(_ item: String) {
            unrestored.append(item)
            DiagLog.shared.log(.error,
                "UITEST restore failed "
                + "item=\(item)")
        }
        // ① 标题会话还原（仅当焦点在夹具标题
        // 上：escape 动作即 handleEscape 标题支
        // 的同一体）。
        if let cap = ctx.surface(
            "editor.titleCapsule"),
           cap.state["focused"]?() == "true" {
            cap.actions["escape"]?(nil)
        }
        // ② 关浮层（菜单）。
        if let menu = ctx.surface(
            "editor.menuPanel"),
           menu.state["open"]?() == "true" {
            menu.actions["close"]?(nil)
        }
        // ②′ 编辑器瞬态清零（U4a 补）：斜杠/链
        // 接表单/音乐输入三位是 EditorModel 的
        // 会话态，编辑器随夹具关闭即弃，但若关
        // 闭失败走孤儿兜底、三位会随编辑器副本
        // 残留——先清再关，关失败也不留半开面。
        if let ed = EditorSeatRegistry.shared
            .currentEditor,
           ed.item.id == ctx.fixtureId {
            ed.slashBlockId = nil
            ed.linkFormBlockId = nil
            ed.focusMusicId = nil
        }
        // ④ 关编辑器（在席仍是夹具时）。
        let seat = EditorSeatRegistry.shared
        func cleanupFixture() {
            // ⑤ 夹具清理：先验登记集（结构守
            // 卫），再软删 + 立即真删。
            guard UITestFixture.isFixture(
                ctx.fixtureId) else {
                mark("fixture_guard")
                done(unrestored)
                return
            }
            let lib = ctx.library
            if let item = lib.memos.first(
                where: { $0.id == ctx.fixtureId }) {
                lib.softRemove(item)
            }
            if lib.pendingDeletions[ctx.fixtureId]
                != nil {
                lib.commitPendingDeletion(
                    id: ctx.fixtureId)
            }
            let gone = !BridgeReadTools
                .allMemos(lib)
                .contains {
                    $0.id == ctx.fixtureId
                }
            if gone {
                UITestFixture.unregister(
                    ctx.fixtureId)
                DiagLog.shared.log(.info,
                    "UITEST fixture cleanup "
                    + "id=\(ctx.fixtureId)")
            } else {
                mark("fixture_delete")
            }
            done(unrestored)
        }
        if seat.currentMemoId == ctx.fixtureId {
            BridgeNavigationChannel.shared
                .requestClose { result in
                    if case .failure = result {
                        // 编辑器关不掉：在席编辑器
                        // 的下一次保存会复活夹具，
                        // 此刻删它反而留双份——记
                        // 未复原、跳过清理（残留由
                        // 孤儿扫描兜底报告）。
                        mark("editor_close")
                        done(unrestored)
                        return
                    }
                    ctx.expectSeat = false
                    cleanupFixture()
                }
        } else {
            if seat.currentMemoId != nil,
               ctx.expectSeat {
                // 在席已被用户换成他篇：驱动的编
                // 辑器已不在，夹具可径直清理（用
                // 户的编辑器不动）。
                ctx.expectSeat = false
            }
            cleanupFixture()
        }
    }
}

// ── S1 场景：标题胶囊二次编辑回路 ──
// 方案 §4.1 的步表（步 6 的第二轮循环展开为
// 步 6–8，步 7 收尾为步 9；核心断言在步 5：
// 截断态第二次进入、via/begin 两行成对）。

enum UITestScenarioS1 {

    static func assertion(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestAssertion(name: name, pass: pass,
                        expected: expected,
                        actual: actual)
    }

    static func steps() -> [UITestStep] {
        [
            // 步 1：经 U0 导航通道打开夹具篇。
            UITestStep(
                kind: "invoke",
                label: "nav open fixture") { ctx, done in
                var out = UITestStepOutcome()
                BridgeNavigationChannel.shared
                    .requestOpen(
                        memoId: ctx.fixtureId) {
                        result in
                        switch result {
                        case .success(let snap):
                            ctx.expectSeat = true
                            out.assertions.append(
                                assertion(
                                    "seat_matches",
                                    snap.memoId
                                        == ctx.fixtureId,
                                    "memoId="
                                        + ctx.fixtureId,
                                    snap.memoId))
                            ctx.waitDiag(
                                pattern: "TRANSITION "
                                    + "id="
                                    + ctx.fixtureId,
                                timeoutMs: 5000) {
                                lines in
                                out.assertions
                                    .append(assertion(
                                        "transition_logged",
                                        !lines.isEmpty,
                                        "TRANSITION "
                                            + "line x1",
                                        lines.first?
                                            .text
                                            ?? "none"))
                                out.ok = out
                                    .assertions
                                    .allSatisfy {
                                        $0.pass
                                    }
                                done(out)
                            }
                        case .failure(let e):
                            out.ok = false
                            out.note = "nav rejected "
                                + "code=\(e.code)"
                            done(out)
                        }
                    }
            },
            // 步 2：短标题态点按 → 会话开始。
            UITestStep(
                kind: "invoke",
                label: "capsule tap (short title)") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.actions["tap"]?(nil)
                ctx.waitDiag(
                    pattern: "EDIT title session "
                        + "begin",
                    timeoutMs: 5000) { lines in
                    out.assertions.append(assertion(
                        "session_begin_seen",
                        lines.count == 1,
                        "EDIT title session "
                            + "begin x1",
                        lines.first?.text
                            ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 步 3：置长标题草稿 → resign 提交 →
            // 回读一致。
            UITestStep(
                kind: "setText",
                label: "set long title + resign") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.setText?(ctx.longTitle)
                cap.actions["resign"]?(nil)
                ctx.waitState(
                    surface: "editor.view",
                    key: "title",
                    equals: ctx.longTitle,
                    timeoutMs: 5000) { ok, actual in
                    out.assertions.append(assertion(
                        "title_committed", ok,
                        ctx.longTitle,
                        actual ?? "none"))
                    switch BridgeReadTools.notesGet(
                        ["id": ctx.fixtureId],
                        library: ctx.library) {
                    case .success(let p):
                        let t = p["title"]
                            as? String ?? ""
                        out.assertions.append(
                            assertion(
                                "notes_get_title",
                                t == ctx.longTitle,
                                ctx.longTitle, t))
                    case .failure(let e):
                        out.assertions.append(
                            assertion(
                                "notes_get_title",
                                false,
                                ctx.longTitle,
                                "error \(e.code)"))
                    }
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 步 4：呈现态断言——截断覆盖层在位
            // （原 bug 的发作态）+ 胶囊帧落定。
            UITestStep(
                kind: "assert",
                label: "truncated state settled") {
                ctx, done in
                var out = UITestStepOutcome()
                ctx.waitState(
                    surface: "editor.titleCapsule",
                    key: "truncated",
                    equals: "true",
                    timeoutMs: 5000) { ok, actual in
                    out.assertions.append(assertion(
                        "truncated_true", ok,
                        "true", actual ?? "none"))
                    let cap = ctx.surface(
                        "editor.titleCapsule")
                    ctx.waitLayout(
                        probe: {
                            guard let f =
                                cap?.frameInWindow()
                            else { return nil }
                            return Double(f.width)
                        },
                        timeoutMs: 5000) {
                        lok, width in
                        out.assertions.append(
                            assertion(
                                "capsule_frame_settled",
                                lok,
                                "two reads within "
                                    + "0.5pt",
                                width.map {
                                    "\($0)pt"
                                } ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            },
            // 步 5：截断态第二次进入（核心断
            // 言）：via/begin 两行成对、各 ×1、
            // 时序 via 在前。
            UITestStep(
                kind: "invoke",
                label: "capsule tap (truncated, "
                    + "core)") { ctx, done in
                coreTap(ctx: ctx, done: done)
            },
            // 步 6：再置短标题 → resign → 回读。
            UITestStep(
                kind: "setText",
                label: "set short title + resign") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.setText?(ctx.shortTitle2)
                cap.actions["resign"]?(nil)
                ctx.waitState(
                    surface: "editor.view",
                    key: "title",
                    equals: ctx.shortTitle2,
                    timeoutMs: 5000) { ok, actual in
                    out.assertions.append(assertion(
                        "title_committed_short", ok,
                        ctx.shortTitle2,
                        actual ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 步 7：回到长标题截断态（聚焦 →
            // 置长草稿 → resign → 截断在位）。
            UITestStep(
                kind: "setText",
                label: "restore long truncated") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.actions["tap"]?(nil)
                cap.setText?(ctx.longTitle)
                cap.actions["resign"]?(nil)
                ctx.waitState(
                    surface: "editor.titleCapsule",
                    key: "truncated",
                    equals: "true",
                    timeoutMs: 5000) { ok, actual in
                    out.assertions.append(assertion(
                        "truncated_again", ok,
                        "true", actual ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 步 8：长标题态第二次循环（防「修
            // 一次好一次」式假绿），断言同步 5。
            UITestStep(
                kind: "invoke",
                label: "capsule tap (truncated, "
                    + "loop 2)") { ctx, done in
                coreTap(ctx: ctx, done: done)
            },
            // 步 9：关编辑器 → 夹具清理 → 库哈
            // 希对账（卫生断言；清理本体在复原
            // 链，本步只断言收尾事实）。
            UITestStep(
                kind: "invoke",
                label: "close editor") { ctx, done in
                var out = UITestStepOutcome()
                BridgeNavigationChannel.shared
                    .requestClose { result in
                        switch result {
                        case .success:
                            ctx.expectSeat = false
                            out.assertions.append(
                                assertion(
                                    "seat_cleared",
                                    EditorSeatRegistry
                                        .shared
                                        .currentMemoId
                                        == nil,
                                    "no seat",
                                    EditorSeatRegistry
                                        .shared
                                        .currentMemoId
                                        ?? "none"))
                        case .failure(let e):
                            out.ok = false
                            out.note = "nav close "
                                + "rejected code="
                                + e.code
                        }
                        out.ok = out.ok
                            && out.assertions
                                .allSatisfy { $0.pass }
                        done(out)
                    }
            },
        ]
    }

    /// 步 5/8 共用：截断态点按 + 两行成对断言
    /// + 失败判读映射（方案 §4.1）：只有 via
    /// 无 begin = 置焦未落（原 bug 复发形态）；
    /// 两行皆无 = 注册动作未达（驱动侧问题）；
    /// begin 有但回读不对 = 提交链问题（步 3/
    /// 6 的回读断言管辖）。
    static func coreTap(
        ctx: UITestRunContext,
        done: @escaping (UITestStepOutcome) -> Void) {
        var out = UITestStepOutcome()
        guard let cap = ctx.surface(
            "editor.titleCapsule") else {
            out.ok = false
            out.note = "surface_missing: "
                + "editor.titleCapsule"
            done(out)
            return
        }
        cap.actions["tap"]?(nil)
        var via: [DiagEntry] = []
        var begin: [DiagEntry] = []
        ctx.poll(timeoutMs: 5000) {
            let w = ctx.windowEntries()
            via = w.filter {
                $0.text.contains(
                    "EDIT title focus via=capsule")
            }
            begin = w.filter {
                $0.text.contains(
                    "EDIT title session begin")
            }
            return !via.isEmpty && !begin.isEmpty
        } done: { _ in
            out.assertions.append(assertion(
                "via_seen_once", via.count == 1,
                "EDIT title focus via=capsule x1",
                via.first?.text ?? "none"))
            out.assertions.append(assertion(
                "begin_seen_once", begin.count == 1,
                "EDIT title session begin x1",
                begin.first?.text ?? "none"))
            if let v = via.first, let b = begin.first {
                out.assertions.append(assertion(
                    "pair_ordered", v.ts <= b.ts,
                    "via before begin",
                    "via=\(v.ts) begin=\(b.ts)"))
            }
            out.ok = out.assertions
                .allSatisfy { $0.pass }
            if !out.ok {
                if !via.isEmpty && begin.isEmpty {
                    out.note = "diagnosis: via only "
                        + "- focus did not land "
                        + "(original bug shape)"
                } else if via.isEmpty
                    && begin.isEmpty {
                    out.note = "diagnosis: neither "
                        + "line - registered action "
                        + "did not reach the entry "
                        + "(driver side)"
                } else if via.isEmpty {
                    out.note = "diagnosis: begin "
                        + "without via - focus set "
                        + "outside the entry"
                }
            }
            done(out)
        }
    }
}

// ── U4a 共享步 ──
// 开/关步与 S1 步 1/9 同体（S1 步表保持原样不
// 动，新景共用此处）；seatedEditor 是驱动读在
// 席模型的前置核验（在席篇必须是夹具篇，否
// 则步失败而非误读他篇）。

enum UITestShared {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestScenarioS1.assertion(
            name, pass, expected, actual)
    }

    static func seatedEditor(
        _ ctx: UITestRunContext) -> EditorModel? {
        guard let ed = EditorSeatRegistry.shared
            .currentEditor,
              ed.item.id == ctx.fixtureId else {
            return nil
        }
        return ed
    }

    static func openStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "nav open fixture") { ctx, done in
            var out = UITestStepOutcome()
            BridgeNavigationChannel.shared
                .requestOpen(
                    memoId: ctx.fixtureId) {
                    result in
                    switch result {
                    case .success(let snap):
                        ctx.expectSeat = true
                        out.assertions.append(a(
                            "seat_matches",
                            snap.memoId
                                == ctx.fixtureId,
                            "memoId=" + ctx.fixtureId,
                            snap.memoId))
                        ctx.waitDiag(
                            pattern: "TRANSITION "
                                + "id="
                                + ctx.fixtureId,
                            timeoutMs: 5000) { lines in
                            out.assertions.append(a(
                                "transition_logged",
                                !lines.isEmpty,
                                "TRANSITION line x1",
                                lines.first?.text
                                    ?? "none"))
                            out.ok = out.assertions
                                .allSatisfy { $0.pass }
                            done(out)
                        }
                    case .failure(let e):
                        out.ok = false
                        out.note = "nav rejected "
                            + "code=\(e.code)"
                        done(out)
                    }
                }
        }
    }

    static func closeStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "close editor") { ctx, done in
            var out = UITestStepOutcome()
            BridgeNavigationChannel.shared
                .requestClose { result in
                    switch result {
                    case .success:
                        ctx.expectSeat = false
                        out.assertions.append(a(
                            "seat_cleared",
                            EditorSeatRegistry.shared
                                .currentMemoId == nil,
                            "no seat",
                            EditorSeatRegistry.shared
                                .currentMemoId
                                ?? "none"))
                    case .failure(let e):
                        out.ok = false
                        out.note = "nav close "
                            + "rejected code="
                            + e.code
                    }
                    out.ok = out.ok
                        && out.assertions
                            .allSatisfy { $0.pass }
                    done(out)
                }
        }
    }

    /// 置长标题草稿 → resign 提交 → 截断态在位
    /// （S1 步 3+4 的合并形，新景共用）。
    static func setLongTruncatedStep()
        -> UITestStep {
        UITestStep(
            kind: "setText",
            label: "set long title + truncated") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let cap = ctx.surface(
                "editor.titleCapsule") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "editor.titleCapsule"
                done(out)
                return
            }
            cap.actions["tap"]?(nil)
            cap.setText?(ctx.longTitle)
            cap.actions["resign"]?(nil)
            ctx.waitState(
                surface: "editor.view",
                key: "title",
                equals: ctx.longTitle,
                timeoutMs: 5000) { ok, actual in
                out.assertions.append(a(
                    "title_committed", ok,
                    ctx.longTitle,
                    actual ?? "none"))
                ctx.waitState(
                    surface: "editor.titleCapsule",
                    key: "truncated",
                    equals: "true",
                    timeoutMs: 5000) { ok2, act2 in
                    out.assertions.append(a(
                        "truncated_true", ok2,
                        "true", act2 ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 块文本喂入（斜杠景）：与 BlockTextView
    /// didChange 的模型侧效果同构——纯文本 runs
    /// 重建 + 文本写入 + updateSlash 单路（选区
    /// 置文本末）。逐字输入/IME 不等价（grades
    /// 已钉），本步只喂状态机入口。
    static func feedBlockText(
        _ ed: EditorModel, _ block: BlockState,
        _ text: String) {
        block.text = text
        block.runs = BlockState.runsFrom(
            children: [["text": text]])
        ed.updateSlash(
            for: block,
            selUTF16: NSRange(
                location: (text as NSString).length,
                length: 0),
            caretX: nil)
    }
}

// ── EDT-06 紧凑坞变体：title_capsule_reedit_compact ──
// 滚动入紧凑态（scrollY>30 → 横排坞）后截断标
// 题二次进入；会话期坞态锁存（DockSession）须
// 零翻转——断言以 editor.view 的 dockCompact
// 两轮一致读为准。

enum UITestScenarioCompact {

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            UITestShared.setLongTruncatedStep(),
            // 滚入紧凑态：驱动滚动面 to(200)，
            // 等坞态两轮一致为 true 且 scrollY
            // 实测越 30。
            UITestStep(
                kind: "invoke",
                label: "scroll to compact dock") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let sc = ctx.surface(
                    "editor.scroll") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.scroll"
                    done(out)
                    return
                }
                sc.actions["to"]?(200)
                ctx.waitState(
                    surface: "editor.view",
                    key: "dockCompact",
                    equals: "true",
                    timeoutMs: 8000) { ok, _ in
                    out.assertions.append(
                        UITestShared.a(
                            "dock_compact_on", ok,
                            "true",
                            ctx.state("editor.view",
                                      "dockCompact")
                                ?? "none"))
                    let sy = Double(ctx.state(
                        "editor.view", "scrollY")
                        ?? "") ?? -1
                    out.assertions.append(
                        UITestShared.a(
                            "scrollY_over_30",
                            sy > 30,
                            ">30", "\(sy)"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 截断态点按（紧凑坞核心）：via/begin
            // 成对断言与 S1 步 5 同体。
            UITestStep(
                kind: "invoke",
                label: "capsule tap (compact, "
                    + "core)") { ctx, done in
                UITestScenarioS1.coreTap(
                    ctx: ctx, done: done)
            },
            // 会话期锁存：焦点在标题时坞态保持
            // compact（两轮一致读），resign 后标
            // 题回读一致。
            UITestStep(
                kind: "assert",
                label: "dock latched in session") {
                ctx, done in
                var out = UITestStepOutcome()
                out.assertions.append(UITestShared.a(
                    "session_focused",
                    ctx.state("editor.titleCapsule",
                              "focused") == "true",
                    "true",
                    ctx.state("editor.titleCapsule",
                              "focused") ?? "none"))
                ctx.waitState(
                    surface: "editor.view",
                    key: "dockCompact",
                    equals: "true",
                    timeoutMs: 3000) { ok, _ in
                    out.assertions.append(
                        UITestShared.a(
                            "dock_latched_compact",
                            ok, "true",
                            ctx.state("editor.view",
                                      "dockCompact")
                                ?? "none"))
                    ctx.surface("editor.titleCapsule")?
                        .actions["resign"]?(nil)
                    ctx.waitState(
                        surface: "editor.view",
                        key: "title",
                        equals: ctx.longTitle,
                        timeoutMs: 5000) { ok2, act in
                        out.assertions.append(
                            UITestShared.a(
                                "title_after_resign",
                                ok2, ctx.longTitle,
                                act ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            },
            // 滚回顶：坞态回落竖排。
            UITestStep(
                kind: "invoke",
                label: "scroll back to top") {
                ctx, done in
                var out = UITestStepOutcome()
                ctx.surface("editor.scroll")?
                    .actions["to"]?(0)
                ctx.waitState(
                    surface: "editor.view",
                    key: "dockCompact",
                    equals: "false",
                    timeoutMs: 8000) { ok, _ in
                    out.assertions.append(
                        UITestShared.a(
                            "dock_back_vertical", ok,
                            "false",
                            ctx.state("editor.view",
                                      "dockCompact")
                                ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            UITestShared.closeStep(),
        ]
    }
}

// ── EDT-07 落点断言：title_caret_assert ──
// 截断态以定点 atX 点按：预期标量在驱动侧以同
// 源量测（fieldFont + kern −0.2）+ 纯函数同式
// 算出，断言 Diag 施加行与字段回读 caretUTF16
// 双对账（算式/记号/施加三段各有断言）。

enum UITestScenarioCaret {

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            UITestShared.setLongTruncatedStep(),
            UITestStep(
                kind: "invoke",
                label: "tap at boundary 5") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule"),
                      let f = cap.frameInWindow()
                else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                let full = ctx.longTitle
                let disp = scalarPrefix(full, 10)
                    + "…"
                let attrs: [NSAttributedString.Key:
                    Any] = [
                    .font: TitleTextField
                        .fieldFont(),
                    .kern: -0.2,
                ]
                var widths: [Double] = []
                var prefix = ""
                for s in disp.unicodeScalars {
                    prefix.unicodeScalars
                        .append(s)
                    widths.append(Double(
                        prefix.size(
                            withAttributes: attrs)
                            .width))
                }
                let rowW = Double(f.width) - 40
                let startX = (rowW
                    - (widths.last ?? 0)) / 2
                // 瞄准第 5 边界（前 5 标量右缘）。
                let tapX = startX + widths[4]
                let expected = TitleTapCaret
                    .caretScalarIndex(
                        fullScalarCount:
                            full.unicodeScalars
                                .count,
                        prefixWidths: widths,
                        tapX: tapX, rowW: rowW)
                ctx.store["expectedCaret"] =
                    expected
                out.assertions.append(UITestShared.a(
                    "aim_is_boundary_5",
                    expected == 5,
                    "5", "\(expected)"))
                cap.actions["tap"]?(tapX)
                ctx.waitDiag(
                    pattern: "EDIT title caret "
                        + "-> \(expected)",
                    timeoutMs: 5000) { lines in
                    out.assertions.append(
                        UITestShared.a(
                            "caret_diag_applied",
                            !lines.isEmpty,
                            "EDIT title caret -> "
                                + "\(expected)",
                            lines.first?.text
                                ?? "none"))
                    let want16 = TitleTapCaret
                        .utf16Offset(
                            ofScalarIndex: expected,
                            in: Array(
                                full.unicodeScalars))
                    let got16 = ctx.state(
                        "editor.titleCapsule",
                        "caretUTF16") ?? "none"
                    out.assertions.append(
                        UITestShared.a(
                            "caret_readback_utf16",
                            got16 == "\(want16)",
                            "\(want16)", got16))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            UITestShared.closeStep(),
        ]
    }
}

// ── EDT-08 提交/Esc：title_commit_escape ──
// Esc 还原草稿（会话起点快照）、resign 提交的
// trim 口径、空标题回退「无标题」三段。

enum UITestScenarioCommitEscape {

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            // Esc 段：改草稿 → escape → 标题未
            // 变、草稿回滚、焦点已辞。
            UITestStep(
                kind: "setText",
                label: "escape reverts draft") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.actions["tap"]?(nil)
                cap.setText?(ctx.shortTitle + "改")
                cap.actions["escape"]?(nil)
                out.assertions.append(UITestShared.a(
                    "title_unchanged",
                    ctx.state("editor.view",
                              "title")
                        == ctx.shortTitle,
                    ctx.shortTitle,
                    ctx.state("editor.view",
                              "title") ?? "none"))
                out.assertions.append(UITestShared.a(
                    "draft_reverted",
                    ctx.state("editor.titleCapsule",
                              "draftLen")
                        == "\(ctx.shortTitle.unicodeScalars.count)",
                    "\(ctx.shortTitle.unicodeScalars.count)",
                    ctx.state("editor.titleCapsule",
                              "draftLen") ?? "none"))
                out.assertions.append(UITestShared.a(
                    "focus_resigned",
                    ctx.state("editor.titleCapsule",
                              "focused") == "false",
                    "false",
                    ctx.state("editor.titleCapsule",
                              "focused") ?? "none"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            },
            // trim 段：两侧空白提交后落 trim 值。
            UITestStep(
                kind: "setText",
                label: "commit trims whitespace") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.actions["tap"]?(nil)
                cap.setText?("  " + ctx.shortTitle2
                    + "  ")
                cap.actions["resign"]?(nil)
                ctx.waitState(
                    surface: "editor.view",
                    key: "title",
                    equals: ctx.shortTitle2,
                    timeoutMs: 5000) { ok, actual in
                    out.assertions.append(
                        UITestShared.a(
                            "title_trimmed", ok,
                            ctx.shortTitle2,
                            actual ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 空回退段：纯空白提交 → 「无标题」。
            UITestStep(
                kind: "setText",
                label: "empty falls back") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let cap = ctx.surface(
                    "editor.titleCapsule") else {
                    out.ok = false
                    out.note = "surface_missing: "
                        + "editor.titleCapsule"
                    done(out)
                    return
                }
                cap.actions["tap"]?(nil)
                cap.setText?("   ")
                cap.actions["resign"]?(nil)
                ctx.waitState(
                    surface: "editor.view",
                    key: "title",
                    equals: "无标题",
                    timeoutMs: 5000) { ok, actual in
                    out.assertions.append(
                        UITestShared.a(
                            "title_fallback", ok,
                            "无标题",
                            actual ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            UITestShared.closeStep(),
        ]
    }
}

// ── EDT-09 完成胶囊：done_capsule_cycle ──
// 触发/行序以现行机制为准（fix_donecapsule_
// retract 后）：kbVisible 唯一写点 = 键盘通知
// （Diag `EDIT kb visible=`），展开派生自该位。
// 两轮循环各断：升起序（kb=1 → expand）与点勾
// 三行序（donecapsule done → kb=0 → collapse），
// 第二轮防闩锁假绿。

enum UITestScenarioDoneCapsule {

    /// 一轮的升起步：点胶囊置焦 → 等 kb=1 与
    /// expand 两行 + expanded 态。
    static func raiseStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "focus raises capsule") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let cap = ctx.surface(
                "editor.titleCapsule") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "editor.titleCapsule"
                done(out)
                return
            }
            cap.actions["tap"]?(nil)
            ctx.waitDiag(
                pattern: "EDIT kb visible=1",
                timeoutMs: 8000) { kb in
                out.assertions.append(UITestShared.a(
                    "kb_visible_1", !kb.isEmpty,
                    "EDIT kb visible=1 x1",
                    kb.first?.text ?? "none"))
                ctx.waitDiag(
                    pattern: "EDIT donecapsule "
                        + "expand",
                    timeoutMs: 5000) { ex in
                    out.assertions.append(
                        UITestShared.a(
                            "capsule_expand_logged",
                            !ex.isEmpty,
                            "EDIT donecapsule "
                                + "expand x1",
                            ex.first?.text
                                ?? "none"))
                    ctx.waitState(
                        surface:
                            "editor.doneCapsule",
                        key: "expanded",
                        equals: "true",
                        timeoutMs: 5000) { ok, act in
                        out.assertions.append(
                            UITestShared.a(
                                "capsule_expanded",
                                ok, "true",
                                act ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            }
        }
    }

    /// 一轮的点勾步：done 动作 → 三行齐且序为
    /// done < kb=0 < collapse，expanded 回落。
    static func doneStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "done retracts capsule") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let dc = ctx.surface(
                "editor.doneCapsule") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "editor.doneCapsule"
                done(out)
                return
            }
            dc.actions["done"]?(nil)
            var dLine: DiagEntry?
            var kLine: DiagEntry?
            var cLine: DiagEntry?
            ctx.poll(timeoutMs: 8000) {
                let w = ctx.windowEntries()
                dLine = w.first {
                    $0.text.contains(
                        "EDIT donecapsule done")
                }
                kLine = w.first {
                    $0.text.contains(
                        "EDIT kb visible=0")
                }
                cLine = w.first {
                    $0.text.contains(
                        "EDIT donecapsule "
                        + "collapse")
                }
                return dLine != nil && kLine != nil
                    && cLine != nil
            } done: { _ in
                out.assertions.append(UITestShared.a(
                    "done_logged", dLine != nil,
                    "EDIT donecapsule done x1",
                    dLine?.text ?? "none"))
                out.assertions.append(UITestShared.a(
                    "kb_visible_0", kLine != nil,
                    "EDIT kb visible=0 x1",
                    kLine?.text ?? "none"))
                out.assertions.append(UITestShared.a(
                    "collapse_logged",
                    cLine != nil,
                    "EDIT donecapsule collapse x1",
                    cLine?.text ?? "none"))
                if let d = dLine, let k = kLine,
                   let c = cLine {
                    out.assertions.append(
                        UITestShared.a(
                            "triple_ordered",
                            d.ts <= k.ts
                                && k.ts <= c.ts,
                            "done <= kb0 "
                                + "<= collapse",
                            "done=\(d.ts) "
                                + "kb0=\(k.ts) "
                                + "collapse="
                                + "\(c.ts)"))
                }
                ctx.waitState(
                    surface: "editor.doneCapsule",
                    key: "expanded",
                    equals: "false",
                    timeoutMs: 5000) { ok, act in
                    out.assertions.append(
                        UITestShared.a(
                            "capsule_retracted",
                            ok, "false",
                            act ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            raiseStep(),
            doneStep(),
            raiseStep(),
            doneStep(),
            UITestShared.closeStep(),
        ]
    }
}

// ── EDT-18/19 斜杠全链：slash_menu_flow ──
// 触发（SLASH open 行）→ 过滤（query/db 命中待
// 办）→ 键盘导航（moveSel 环绕的模型单路）→
// 执行（applySelected：成块型 + token 剥离 +
// 面板关闭 + EDIT slash 行）。执行抽样取块型
// 命令两例（todo/heading1）；行内命令抽样待
// U4b 块面 setText（选区态不在本批驱动面）。

enum UITestScenarioSlash {

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            // 触发段：首段喂 "/" → 面板开、首行
            // 选中 = 行序命令首项。
            UITestStep(
                kind: "invoke",
                label: "slash opens") { ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let pid = (ctx.store[
                        "paragraphIds"]
                        as? [String])?.first,
                      let block = ed.blocks.first(
                        where: { $0.id == pid })
                else {
                    out.ok = false
                    out.note = "fixture block "
                        + "missing"
                    done(out)
                    return
                }
                ctx.store["slashBlockId"] = pid
                UITestShared.feedBlockText(
                    ed, block, "/")
                ctx.waitDiag(
                    pattern: "SLASH open",
                    timeoutMs: 5000) { lines in
                    out.assertions.append(
                        UITestShared.a(
                            "slash_open_logged",
                            !lines.isEmpty,
                            "SLASH open x1",
                            lines.first?.text
                                ?? "none"))
                    ctx.waitState(
                        surface:
                            "editor.slashPanel",
                        key: "open",
                        equals: "true",
                        timeoutMs: 5000) { ok, _ in
                        out.assertions.append(
                            UITestShared.a(
                                "panel_open", ok,
                                "true",
                                ctx.state(
                                    "editor.slashPanel",
                                    "open")
                                    ?? "none"))
                        let want = SlashCmds
                            .rowCommands("")
                            .first?.act ?? ""
                        let got = ctx.state(
                            "editor.slashPanel",
                            "selAct") ?? "none"
                        out.assertions.append(
                            UITestShared.a(
                                "first_selected",
                                got == want,
                                want, got))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            },
            // 过滤段：喂 "/db" → query=db、选中
            // = 待办（拼音首字母命中）。
            UITestStep(
                kind: "invoke",
                label: "slash filters by pinyin") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let pid = ctx.store[
                        "slashBlockId"] as? String,
                      let block = ed.blocks.first(
                        where: { $0.id == pid })
                else {
                    out.ok = false
                    out.note = "fixture block "
                        + "missing"
                    done(out)
                    return
                }
                UITestShared.feedBlockText(
                    ed, block, "/db")
                ctx.waitState(
                    surface: "editor.slashPanel",
                    key: "query",
                    equals: "db",
                    timeoutMs: 5000) { ok, _ in
                    out.assertions.append(
                        UITestShared.a(
                            "query_db", ok, "db",
                            ctx.state(
                                "editor.slashPanel",
                                "query")
                                ?? "none"))
                    let got = ctx.state(
                        "editor.slashPanel",
                        "selAct") ?? "none"
                    out.assertions.append(
                        UITestShared.a(
                            "filter_hits_todo",
                            got == "todo",
                            "todo", got))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 导航段：回空 query，moveSel ±1 环
            // 绕——选中随行序命令表走、回退复位。
            UITestStep(
                kind: "invoke",
                label: "slash keyboard nav") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let pid = ctx.store[
                        "slashBlockId"] as? String,
                      let block = ed.blocks.first(
                        where: { $0.id == pid }),
                      let panel = ctx.surface(
                        "editor.slashPanel")
                else {
                    out.ok = false
                    out.note = "fixture block "
                        + "missing"
                    done(out)
                    return
                }
                UITestShared.feedBlockText(
                    ed, block, "/")
                let cmds = SlashCmds
                    .rowCommands("")
                guard cmds.count >= 2 else {
                    out.ok = false
                    out.note = "command table "
                        + "too small"
                    done(out)
                    return
                }
                panel.actions["moveSel"]?(1)
                let got1 = ctx.state(
                    "editor.slashPanel",
                    "selAct") ?? "none"
                out.assertions.append(UITestShared.a(
                    "nav_down_one",
                    got1 == cmds[1].act,
                    cmds[1].act, got1))
                panel.actions["moveSel"]?(-1)
                let got0 = ctx.state(
                    "editor.slashPanel",
                    "selAct") ?? "none"
                out.assertions.append(UITestShared.a(
                    "nav_back_to_first",
                    got0 == cmds[0].act,
                    cmds[0].act, got0))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            },
            // 执行段一：/db → applySelected →
            // 段成待办、token 剥净、面板关、行
            // 在位。
            UITestStep(
                kind: "invoke",
                label: "slash applies todo") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let pid = ctx.store[
                        "slashBlockId"] as? String,
                      let block = ed.blocks.first(
                        where: { $0.id == pid }),
                      let panel = ctx.surface(
                        "editor.slashPanel")
                else {
                    out.ok = false
                    out.note = "fixture block "
                        + "missing"
                    done(out)
                    return
                }
                UITestShared.feedBlockText(
                    ed, block, "/db")
                panel.actions["applySelected"]?(nil)
                ctx.waitDiag(
                    pattern: "EDIT slash todo",
                    timeoutMs: 5000) { lines in
                    out.assertions.append(
                        UITestShared.a(
                            "slash_todo_logged",
                            !lines.isEmpty,
                            "EDIT slash todo x1",
                            lines.first?.text
                                ?? "none"))
                    let after = ed.blocks.first(
                        where: { $0.id == pid })
                    out.assertions.append(
                        UITestShared.a(
                            "block_became_todo",
                            after?.type == "todo",
                            "todo",
                            after?.type ?? "none"))
                    out.assertions.append(
                        UITestShared.a(
                            "token_stripped",
                            after?.text
                                .contains("/db")
                                == false,
                            "no /db in text",
                            after?.text ?? "none"))
                    out.assertions.append(
                        UITestShared.a(
                            "panel_closed",
                            ctx.state(
                                "editor.slashPanel",
                                "open") == "false",
                            "false",
                            ctx.state(
                                "editor.slashPanel",
                                "open")
                                ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 执行段二（EDT-19 抽样）：段落乙
            // /bt1 → 一级标题（level=1 落 attrs）。
            UITestStep(
                kind: "invoke",
                label: "slash applies heading1") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let pids = ctx.store[
                        "paragraphIds"]
                        as? [String],
                      pids.count >= 2,
                      let block = ed.blocks.first(
                        where: { $0.id == pids[1] }),
                      let panel = ctx.surface(
                        "editor.slashPanel")
                else {
                    out.ok = false
                    out.note = "fixture block "
                        + "missing"
                    done(out)
                    return
                }
                UITestShared.feedBlockText(
                    ed, block, "/bt1")
                panel.actions["applySelected"]?(nil)
                ctx.waitDiag(
                    pattern: "EDIT slash "
                        + "heading1",
                    timeoutMs: 5000) { lines in
                    out.assertions.append(
                        UITestShared.a(
                            "slash_h1_logged",
                            !lines.isEmpty,
                            "EDIT slash heading1 "
                                + "x1",
                            lines.first?.text
                                ?? "none"))
                    let after = ed.blocks.first(
                        where: { $0.id == pids[1] })
                    out.assertions.append(
                        UITestShared.a(
                            "block_became_h1",
                            after?.type
                                == "heading"
                                && after?.level
                                    == 1,
                            "heading level 1",
                            (after?.type ?? "none")
                                + "/"
                                + "\(after?.level ?? -1)"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            UITestShared.closeStep(),
        ]
    }
}

// ── EDT-16/17 块矩阵：block_type_matrix ──
// 全块型在位（类型序对模板）+ 帧落定（块顶序
// 单调）+ 待办勾选两轮落盘回读（toggleTodo-
// Checked 具名入口）+ 未知块再保存保真 + 转换
// 清字段（E3 落码后语义：转出待办清 checked、
// 转出标题清 level；E3 未落前本步预期红，依
// 赖见 impl_uitest_u4a.md）。

enum UITestScenarioBlockMatrix {

    static func notesBlocks(
        _ ctx: UITestRunContext
    ) -> [[String: Any]] {
        switch BridgeReadTools.notesGet(
            ["id": ctx.fixtureId],
            library: ctx.library) {
        case .success(let p):
            return p["blocks"]
                as? [[String: Any]] ?? []
        case .failure:
            return []
        }
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            // 在位 + 帧落定。
            UITestStep(
                kind: "assert",
                label: "all types in place") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                    .seatedEditor(ctx) else {
                    out.ok = false
                    out.note = "no seated "
                        + "fixture editor"
                    done(out)
                    return
                }
                let want = ctx.store["blockTypes"]
                    as? [String] ?? []
                let got = ed.blocks.map { $0.type }
                out.assertions.append(UITestShared.a(
                    "types_match_template",
                    got == want,
                    want.joined(separator: ","),
                    got.joined(separator: ",")))
                // 帧落定：编辑器宽两测一致后，
                // 块顶 frameMinY 随序不递减且末
                // 块低于首块（布局已真实发生）。
                let view = ctx.surface(
                    "editor.view")
                ctx.waitLayout(
                    probe: {
                        view?.frameInWindow()
                            .map {
                                Double($0.width)
                            }
                    },
                    timeoutMs: 5000) { lok, _ in
                    out.assertions.append(
                        UITestShared.a(
                            "layout_settled", lok,
                            "two reads within "
                                + "0.5pt",
                            lok ? "settled"
                                : "unstable"))
                    let ys = ed.blocks.map {
                        $0.frameMinY
                    }
                    let mono = zip(ys, ys.dropFirst())
                        .allSatisfy { $0 <= $1 }
                    out.assertions.append(
                        UITestShared.a(
                            "frames_ordered",
                            mono
                                && (ys.last ?? 0)
                                    > (ys.first
                                        ?? 0),
                            "non-decreasing, "
                                + "last > first",
                            ys.map { "\(Int($0))" }
                                .joined(
                                    separator: ",")))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            },
            // 待办勾选两轮（EDT-16）：入口切换
            // → saveNow → 回读 checked；再切回。
            UITestStep(
                kind: "invoke",
                label: "todo toggle persists") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let tid = (ctx.store[
                        "blockIdByType"]
                        as? [String: String])?[
                            "todo"],
                      let todo = ed.blocks.first(
                        where: { $0.id == tid })
                else {
                    out.ok = false
                    out.note = "todo fixture "
                        + "missing"
                    done(out)
                    return
                }
                ed.toggleTodoChecked(todo)
                out.assertions.append(UITestShared.a(
                    "checked_on_in_model",
                    todo.checked,
                    "true", "\(todo.checked)"))
                ed.saveNow()
                let on = notesBlocks(ctx).first {
                    ($0["id"] as? String) == tid
                }
                out.assertions.append(UITestShared.a(
                    "checked_on_readback",
                    (on?["checked"] as? Bool)
                        == true,
                    "true",
                    "\(String(describing: on?["checked"]))"))
                ed.toggleTodoChecked(todo)
                ed.saveNow()
                let off = notesBlocks(ctx).first {
                    ($0["id"] as? String) == tid
                }
                out.assertions.append(UITestShared.a(
                    "checked_off_readback",
                    (off?["checked"] as? Bool)
                        == false,
                    "false",
                    "\(String(describing: off?["checked"]))"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            },
            // 未知块保真（EDT-17）：saveNow 后
            // 回读类型仍在、模型正文未吞。
            UITestStep(
                kind: "assert",
                label: "unknown block preserved") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let uid = (ctx.store[
                        "blockIdByType"]
                        as? [String: String])?[
                            "futureWidget"],
                      let unk = ed.blocks.first(
                        where: { $0.id == uid })
                else {
                    out.ok = false
                    out.note = "unknown fixture "
                        + "missing"
                    done(out)
                    return
                }
                ed.saveNow()
                let rb = notesBlocks(ctx).first {
                    ($0["id"] as? String) == uid
                }
                out.assertions.append(UITestShared.a(
                    "unknown_type_readback",
                    (rb?["type"] as? String)
                        == "futureWidget",
                    "futureWidget",
                    (rb?["type"] as? String)
                        ?? "none"))
                out.assertions.append(UITestShared.a(
                    "unknown_text_kept",
                    unk.text == "自检未知块正文",
                    "自检未知块正文", unk.text))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            },
            // 转换清字段（E3 语义）：已勾待办转
            // 段落 → node 无 checked 残留；标题
            // 转段落 → 无 level 残留；段落转待
            // 办 → checked=false 在位。
            UITestStep(
                kind: "invoke",
                label: "conversion clears fields") {
                ctx, done in
                var out = UITestStepOutcome()
                guard let ed = UITestShared
                        .seatedEditor(ctx),
                      let byType = ctx.store[
                        "blockIdByType"]
                        as? [String: String],
                      let tid = byType["todo"],
                      let todo = ed.blocks.first(
                        where: { $0.id == tid }),
                      let hid = byType["heading"],
                      let head = ed.blocks.first(
                        where: { $0.id == hid })
                else {
                    out.ok = false
                    out.note = "matrix fixture "
                        + "missing"
                    done(out)
                    return
                }
                if !todo.checked {
                    ed.toggleTodoChecked(todo)
                }
                ed.setBlockType(todo,
                                type: "paragraph")
                let todoAttrs = todo.node["attrs"]
                    as? [String: Any] ?? [:]
                out.assertions.append(UITestShared.a(
                    "todo_out_clears_checked",
                    todoAttrs["checked"] == nil,
                    "checked absent",
                    "\(String(describing: todoAttrs["checked"]))"))
                ed.setBlockType(head,
                                type: "paragraph")
                let headAttrs = head.node["attrs"]
                    as? [String: Any] ?? [:]
                out.assertions.append(UITestShared.a(
                    "heading_out_clears_level",
                    headAttrs["level"] == nil,
                    "level absent",
                    "\(String(describing: headAttrs["level"]))"))
                ed.setBlockType(todo,
                                type: "todo")
                let backAttrs = todo.node["attrs"]
                    as? [String: Any] ?? [:]
                out.assertions.append(UITestShared.a(
                    "todo_in_checked_false",
                    (backAttrs["checked"]
                        as? Bool) == false
                        && todo.checked == false,
                    "checked=false",
                    "\(String(describing: backAttrs["checked"]))"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            },
            UITestShared.closeStep(),
        ]
    }
}

// ── 桥工具面（uitest 四件）──

enum BridgeUITestTools {

    static func listSurfaces(
        library: Library?) -> [String: Any] {
        if let library {
            UITestFixtureSweep.noteOrphans(
                in: library)
        }
        let seat = EditorSeatRegistry.shared
        var editorInfo: [String: Any] = [
            "seated": seat.currentMemoId != nil,
        ]
        if let id = seat.currentMemoId {
            editorInfo["memoId"] = id
            if let library,
               let ed = seat.currentEditor {
                editorInfo["dirty"] =
                    BridgeEditorSeat.isDiverged(
                        editor: ed, library: library)
            }
        }
        let surfaces = UITestRegistry.shared.all()
            .sorted { $0.id < $1.id }
            .map { e -> [String: Any] in
                [
                    "id": e.id,
                    "kind": e.kind,
                    "instance": e.instance,
                    "hasFrame":
                        e.frameInWindow() != nil,
                    "actions": e.actions.keys
                        .sorted(),
                    "stateKeys": e.state.keys
                        .sorted(),
                ]
            }
        return [
            "surfaces": surfaces,
            "editor": editorInfo,
        ]
    }

    /// uitest_run 受理：数据面前置门与
    /// dataWriteTools 同序同码（库在位、非只
    /// 读、OPS 未禁桥）——分发器的数据写门只辖
    /// dataWriteTools 集合，本工具的门在此补齐
    /// 且先于驱动并发门（B25-9 检查序）。
    static func run(
        _ args: [String: Any], library: Library?
    ) -> Result<[String: Any], BridgeToolError> {
        guard let library else {
            return .failure(.libraryUnavailable)
        }
        if library.isReadOnly {
            return .failure(BridgeToolError(
                code: "read_only_mode",
                message: "library is open "
                    + "read-only; uitest_run is "
                    + "unavailable"))
        }
        if OpsDirectives.cached()
            .isDisabled(OpsStep.bridge) {
            return .failure(BridgeToolError(
                code: "ops_disabled",
                message: "bridge disabled by ops "
                    + "directive in current cache"))
        }
        guard let scenario = args["scenario"]
                as? String, !scenario.isEmpty else {
            return .failure(.invalidParams(
                "scenario required"))
        }
        switch UITestDriver.shared.begin(
            scenario: scenario, library: library) {
        case .success(let runId):
            return .success([
                "runId": runId,
                "scenario": scenario,
                "acceptedAtMs": Library.epochMs(),
            ])
        case .failure(let e):
            return .failure(e)
        }
    }

    static func getResult(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let runId = args["runId"] as? String,
              !runId.isEmpty else {
            return .failure(.invalidParams(
                "runId required"))
        }
        guard let job = UITestDriver.shared
            .job(runId) else {
            return .failure(.invalidParams(
                "unknown runId: \(runId)"))
        }
        return .success(job.payload())
    }

    /// 量测探针本体归 U2（方案 §7.1）：U1 只
    /// 落工具壳与探针 id 注册表，探针未落码前
    /// 明确回 invalid_params，不假装有数。
    static func measure(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let probe = args["probe"] as? String,
              !probe.isEmpty else {
            return .failure(.invalidParams(
                "probe required"))
        }
        let known = ["card_alignment", "lift_gaps",
                     "menu_panel"]
        guard known.contains(probe) else {
            return .failure(.invalidParams(
                "unknown probe: \(probe)"))
        }
        return .failure(.invalidParams(
            "probe \(probe) lands in U2; no "
            + "probes are registered in U1"))
    }
}
