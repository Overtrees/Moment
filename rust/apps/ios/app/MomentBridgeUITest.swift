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
    case title, blocks, tall, media
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

    /// 媒体夹具（EDT-60/61）附件 id 与纯色：场
    /// 景以 1x1 平均色（imgToneHex）判图身份，
    /// 三色互不混淆；字节由驱动 setup 经
    /// Library.putAttachment 正式写面落库。
    static let mediaFids = ["att-uitest-ga",
                            "att-uitest-gb",
                            "att-uitest-gc"]
    static let mediaColors: [(Int, Int, Int)] = [
        (255, 0, 0), (0, 255, 0), (0, 0, 255),
    ]
    static let mediaTones = ["ff0000", "00ff00",
                             "0000ff"]

    /// 纯色 PNG 夹具图（8x8 足够 tone 判读）。
    static func solidPNG(_ r: Int, _ g: Int,
                         _ b: Int) -> Data? {
        let size = CGSize(width: 8, height: 8)
        let img = UIGraphicsImageRenderer(
            size: size).image { _ in
            UIColor(red: CGFloat(r) / 255,
                    green: CGFloat(g) / 255,
                    blue: CGFloat(b) / 255,
                    alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero,
                              size: size))
        }
        return img.pngData()
    }

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
        case .media:
            nodes = [
                node("paragraph", text: "自检段落甲"),
                node("gallery",
                     attrs: ["items": mediaFids.map {
                         ["fileId": $0]
                     }]),
                node("paragraph", text: "自检段落乙"),
            ]
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

    /// 场景目录：S1 + U4a 六景 + U4b 撤销景 + 媒体
    /// 两景（EDT-60/61）+ U3 拖拽景 + U5 五景。
    /// grades 口径恒守方案 §3.5——驱动证状态机/
    /// 几何/落盘，触摸投递与键盘呈现不升级表述。
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
            UITestScenarioDef(
                name: "undo_redo_roundtrip",
                fixture: .blocks,
                grades: grades(
                    "EDT-14 撤销回路：漏斗合并/去重/"
                    + "钳制/选区恢复/清重做尾/单消费"
                    + "以模型与 Diag 面 proven；"
                    + "Cmd+Z 与三指的物理投递、识别"
                    + "器仲裁不在证据面（单轨接线由"
                    + "构建期 [47] 锁），选区在真实"
                    + "字段内的落点像素不在证据面。"),
                steps: UITestScenarioUndoRedo.steps),
            UITestScenarioDef(
                name: "image_block_seated_load",
                fixture: .media,
                grades: grades(
                    "EDT-60：斜杠建空图片块 → "
                    + "replaceImage 塞图后键控重载"
                    + "当场出图（全程不重进备忘）；"
                    + "状态机/注册面/Diag 面 proven，"
                    + "选图器内操作与像素呈现不在"
                    + "证据面。"),
                steps: UITestScenarioImageSeated
                    .steps),
            UITestScenarioDef(
                name: "gallery_items_follow",
                fixture: .media,
                grades: grades(
                    "EDT-61：gallery 删首项/换图后"
                    + "逐瓦图随项（项键身份 + 源键"
                    + "重载）；注册面 tone 判图身"
                    + "份，瓦面像素与点按投递不在"
                    + "证据面。"),
                steps: UITestScenarioGalleryFollow
                    .steps),
            UITestScenarioDef(
                name: "drag_pickup_statemachine",
                fixture: .blocks,
                grades: {
                    var g = grades(
                        "EDT-24/25/26/30 + EDT-27 "
                        + "景内段：拾起状态机/让位量/"
                        + "落位块序/取消复位以模型与"
                        + "注册面 proven；驱动经行面"
                        + "调 DragPress 四入口本体（与"
                        + "识别器回调同一组方法），但"
                        + "触摸投递与识别器仲裁不在证"
                        + "据面——长按触发/并行豁免/选"
                        + "区互斥恒归真机（EDT-28）。")
                    g["recognizer"] =
                        "unknown (by construction)"
                    g["geometry"] = "proven"
                    return g
                }(),
                steps: UITestScenarioDragPickup
                    .steps),
            UITestScenarioDef(
                name: "home_search_cycle",
                fixture: .title,
                grades: grades(
                    "HOM-03/04 + HOM-18 扩展：搜索"
                    + "胶囊展开/提交回缩/辞焦退出与"
                    + "命中集回读以注册面 proven；"
                    + "键盘呈现与字段命中不在证据"
                    + "面。HOM-18 段断言编辑返回后"
                    + "命中集即时重算——若红即该缺"
                    + "陷的运行级证据（矩阵行口"
                    + "径），非场景自身失效。"),
                steps: UITestScenarioHomeSearch
                    .steps),
            UITestScenarioDef(
                name: "home_surface_roundtrip",
                fixture: .media,
                grades: grades(
                    "HOM-01/02/13/14：头像入口/紧"
                    + "凑派生一致性/行点开在席/无命"
                    + "中空态以注册面 proven；滚动"
                    + "手感与命中形状不在证据面。"
                    + "全库空态不可由夹具制造，本"
                    + "景只验无命中空态 + 结构在位"
                    + "（矩阵 §4.13 口径差登记）。"),
                steps: UITestScenarioHomeSurface
                    .steps),
            UITestScenarioDef(
                name: "home_list_actions",
                fixture: .media,
                grades: grades(
                    "HOM-07/09/10 UI 腿 + HOM-17 "
                    + "采样：封面派生呈现/置顶/删"
                    + "除撤销链以注册面与模型回读 "
                    + "proven（动作与左滑菜单同"
                    + "体）；左滑手势本身与 toast "
                    + "像素呈现不在证据面。"),
                steps: UITestScenarioHomeActions
                    .steps),
            UITestScenarioDef(
                name: "image_page_open",
                fixture: .media,
                grades: grades(
                    "IMG-01/02/03/06：gallery 项入"
                    + "口（imageTarget 同体赋值）→"
                    + "标题/适配几何/返回后在席未"
                    + "清以注册面 proven；返回恢复"
                    + "深度（焦点/光标/滚动）恒归"
                    + "人工（§7），瓦面点按投递不"
                    + "在证据面。"),
                steps: UITestScenarioImagePage
                    .steps),
            UITestScenarioDef(
                name: "settings_surface_roundtrip",
                fixture: .title,
                grades: grades(
                    "SET-01/03/04/05/06/07/09/10/"
                    + "11/12 + GLB-04 抽样：分组/"
                    + "天气 UI 路径/开关 UI 腿/桥"
                    + "区/语言呈现腿/备份状态腿/手"
                    + "势/诊断/日志结构读以注册面 "
                    + "proven；分享面与系统面板归"
                    + "人工。GLB-04 只抽设备现档"
                    + "（档位切换不可驱动）。天气"
                    + "自填腿在用户已有自填 key 时"
                    + "跳过写入段（不毁用户 key）。"),
                steps: UITestScenarioSettings
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
            // 媒体夹具（EDT-60/61）：纯色图字节经
            // Library 正式写面落附件库（与选图入
            // 口同路），场景以 tone 判图身份；字
            // 节留存与 app 既有「只摘引用」口径
            // 同，不另清理。
            if def.fixture == .media {
                for (fid, rgb) in zip(
                    UITestFixtureTemplate.mediaFids,
                    UITestFixtureTemplate.mediaColors) {
                    guard let png =
                        UITestFixtureTemplate.solidPNG(
                            rgb.0, rgb.1, rgb.2)
                    else { continue }
                    let okPut = library.putAttachment(
                        fid, png, name: fid + ".png")
                    DiagLog.shared.log(.info,
                        "UITEST fixture media "
                        + "fid=\(fid) "
                        + "put=\(okPut ? 1 : 0)")
                }
            }
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
                step: Lang.t("liveops.failed"))
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
                step: finalCode == "ok"
                    ? Lang.t("liveops.done")
                    : Lang.t("liveops.failed"))
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
        // ③ 驱动拾起态复位（U3 补实，矩阵 §6.2）：
        // 在席篇为夹具篇且仍有块被拾起时，经行面
        // cancel 同体复位（dragCancel → 模型
        // clearDragState 单点，与手势取消共用）；
        // 行面已随行卸载注销时以同一单点直清兜
        // 底，不另起复位口径。
        if let ed = EditorSeatRegistry.shared
            .currentEditor,
           ed.item.id == ctx.fixtureId,
           let did = ed.draggingId {
            if let row = UITestRegistry.shared.entry(
                id: "editor.blockRow", instance: did) {
                row.actions["cancel"]?(nil)
            }
            if ed.draggingId != nil {
                ed.clearDragState(for: did)
            }
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

// ── EDT-14 撤销/重做回路（U4b）：undo_redo_roundtrip ──
// 被测面 = E2 撤销漏斗（EditorModel.undo()/redo()
// + UndoHistoryCore，impl_editor_undo_e2.md）：
// 爆发合并（600ms 窗内连续键入一撤整段）、幻影
// 去重（无变更会话不产步）、选区恢复（Diag
// focus= 回读串 + 焦点真落回）、新编辑清重做
// 尾、100 上限钳制、漏斗单消费（一次调用恰一
// 步）。喂入与真实链同构：键入经 noteTextWill-
// Change 检查点（shouldChangeTextIn 普通文本放
// 行点的同一馈入口）+ didChange 的模型侧同步
// （text/runs 重建 + updateSlash）；会话开始经
// 焦点请求面（focusBlockId/pending* 投递 → 真
// 实 textViewDidBeginEditing 压锚）。Cmd+Z/三
// 指的物理投递与识别器仲裁不在证据面（grades
// 已钉；单轨接线由构建期 [47] 锁）。

enum UITestScenarioUndoRedo {

    // ── 同构喂入面 ──

    /// 按 id 现取块（撤销/重做整表换实例，旧引用
    /// 读到的是换前对象——每步现取）。
    static func block(
        _ ed: EditorModel, _ id: String
    ) -> BlockState? {
        ed.blocks.first { $0.id == id }
    }

    /// 焦点请求（应用自身在拆/并/撤销恢复后用的
    /// 同一面）：置 pending 两值后以 focusBlockId
    /// 收口，等真实 didBeginEditing 置 editing-
    /// BlockId（两轮一致才算落定）。
    static func requestFocus(
        _ ctx: UITestRunContext, _ ed: EditorModel,
        blockId: String, caret: Int, selLen: Int,
        done: @escaping (Bool) -> Void) {
        ed.pendingCaretOffset = caret
        ed.pendingSelectionLength = selLen
        ed.focusBlockId = blockId
        var streak = 0
        ctx.poll(timeoutMs: 5000) {
            if ed.editingBlockId == blockId {
                streak += 1
            } else {
                streak = 0
            }
            return streak >= 2
        } done: { ok in done(ok) }
    }

    /// 辞焦（完成路径 finishEditing 的同一体：向
    /// 响应链发 resignFirstResponder），等
    /// editingBlockId 清空（两轮一致）。
    static func resignFocus(
        _ ctx: UITestRunContext, _ ed: EditorModel,
        done: @escaping (Bool) -> Void) {
        UIApplication.shared.sendAction(
            #selector(
                UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
        var streak = 0
        ctx.poll(timeoutMs: 5000) {
            if ed.editingBlockId == nil {
                streak += 1
            } else {
                streak = 0
            }
            return streak >= 2
        } done: { ok in done(ok) }
    }

    /// 键入一键（普通文本放行点同构）：变更前经
    /// 检查点馈入（range 为变更前文本内的替换范
    /// 围、UTF-16 口径，与 feedUndoCheckpoint 的
    /// 传参同式），再按 didChange 的模型侧效果
    /// 同步 text/runs 并跟随 updateSlash。
    static func typeReplace(
        _ ed: EditorModel, _ block: BlockState,
        range: NSRange, _ replacement: String) {
        ed.noteTextWillChange(
            blockId: block.id, text: block.text,
            range: range, replacement: replacement)
        let newText = (block.text as NSString)
            .replacingCharacters(
                in: range, with: replacement)
        block.text = newText
        block.runs = BlockState.runsFrom(
            children: [["text": newText]])
        ed.updateSlash(
            for: block,
            selUTF16: NSRange(
                location: range.location
                    + (replacement as NSString).length,
                length: 0),
            caretX: nil)
    }

    /// 末尾追加一键（range = 文末零长）。
    static func typeAppend(
        _ ed: EditorModel, _ block: BlockState,
        _ ch: String) {
        typeReplace(
            ed, block,
            range: NSRange(
                location: (block.text as NSString)
                    .length,
                length: 0),
            ch)
    }

    // ── Diag 判读 ──

    /// 窗口内最后一条撤销/重做步行（含「余栈」标
    /// 记，与 dedup/clamp 事件行分开）。
    static func lastStepLine(
        _ ctx: UITestRunContext,
        _ prefix: String) -> String? {
        ctx.windowEntries().last {
            $0.text.hasPrefix(prefix)
                && $0.text.contains("余栈")
        }?.text
    }

    /// 步行内 `key=<整数>` 字段解析。
    static func field(
        _ line: String?, _ key: String) -> Int? {
        guard let line,
              let r = line.range(of: key + "=")
        else { return nil }
        let digits = line[r.upperBound...]
            .prefix { $0.isNumber }
        return Int(digits)
    }

    /// 步行内 focus= 回读串（行尾字段）。
    static func focusField(
        _ line: String?) -> String? {
        guard let line,
              let r = line.range(of: "focus=")
        else { return nil }
        return String(line[r.upperBound...])
    }

    // ── 落盘回读 ──

    static func nodeText(
        _ node: [String: Any]) -> String {
        var s = node["text"] as? String ?? ""
        for c in node["children"]
            as? [[String: Any]] ?? [] {
            s += nodeText(c)
        }
        return s
    }

    /// 夹具某块的落盘文本（notesGet 回读）。
    static func notesText(
        _ ctx: UITestRunContext,
        _ blockId: String) -> String? {
        switch BridgeReadTools.notesGet(
            ["id": ctx.fixtureId],
            library: ctx.library) {
        case .success(let p):
            let blocks = p["blocks"]
                as? [[String: Any]] ?? []
            guard let b = blocks.first(where: {
                ($0["id"] as? String) == blockId
            }) else { return nil }
            return nodeText(b)
        case .failure:
            return nil
        }
    }

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestShared.a(name, pass, expected, actual)
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            baselineStep(),
            burstStep(),
            redoTailStep(),
            selectionStep(),
            phantomStep(),
            clampStep(),
            UITestShared.closeStep(),
        ]
    }

    /// 空栈基线：开编即 canUndo/canRedo 皆假
    /// （打开既有篇不落焦、不压栈——落焦意图只
    /// 在新建篇置位），空栈 undo()/redo() 为
    /// no-op——缺席窗内无步行（以时间谓词实现
    /// 的缺席断言，非事件等待）。
    static func baselineStep() -> UITestStep {
        UITestStep(
            kind: "assert",
            label: "empty history no-op") { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                .seatedEditor(ctx) else {
                out.ok = false
                out.note = "no seated fixture editor"
                done(out)
                return
            }
            out.assertions.append(a(
                "canUndo_false_at_open", !ed.canUndo,
                "false", "\(ed.canUndo)"))
            out.assertions.append(a(
                "canRedo_false_at_open", !ed.canRedo,
                "false", "\(ed.canRedo)"))
            ed.undo()
            ed.redo()
            let t0 = Date()
            ctx.poll(timeoutMs: 900) {
                Date() >= t0.addingTimeInterval(0.6)
            } done: { _ in
                let lines = ctx.windowEntries()
                    .filter { $0.text.contains("余栈") }
                out.assertions.append(a(
                    "empty_undo_redo_silent",
                    lines.isEmpty, "no step lines",
                    lines.first?.text ?? "none"))
                out.assertions.append(a(
                    "flags_still_false",
                    !ed.canUndo && !ed.canRedo,
                    "false/false",
                    "\(ed.canUndo)/\(ed.canRedo)"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 爆发合并：焦点请求开会话（真实压锚）后连
    /// 续 5 键入（首键与锚同 key 去重、链照起；
    /// 余 4 键窗内合并）——一次 undo 整段回退
    /// （merged=4）且落盘回读同值，一次 redo 整
    /// 段恢复。
    static func burstStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "burst merges into one undo"
        ) { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let pid = (ctx.store["paragraphIds"]
                    as? [String])?.first,
                  let block = block(ed, pid)
            else {
                out.ok = false
                out.note = "fixture block missing"
                done(out)
                return
            }
            ctx.store["undoBlockA"] = pid
            let baseText = block.text
            ctx.store["undoBaseText"] = baseText
            requestFocus(
                ctx, ed, blockId: pid,
                caret: baseText.count, selLen: 0
            ) { ok in
                out.assertions.append(a(
                    "focus_claimed", ok,
                    "editing=\(pid)",
                    ed.editingBlockId ?? "none"))
                out.assertions.append(a(
                    "session_anchor_canUndo",
                    ed.canUndo, "true", "\(ed.canUndo)"))
                for ch in ["甲", "乙", "丙", "丁", "戊"] {
                    typeAppend(ed, block, ch)
                }
                let burstText = baseText + "甲乙丙丁戊"
                ctx.store["undoBurstText"] = burstText
                out.assertions.append(a(
                    "burst_text_applied",
                    block.text == burstText,
                    burstText, block.text))
                ed.saveNow()
                let rb = notesText(ctx, pid)
                out.assertions.append(a(
                    "burst_text_readback",
                    rb == burstText,
                    burstText, rb ?? "none"))
                ed.undo()
                ctx.waitDiag(
                    pattern: "EDIT undo 余栈",
                    timeoutMs: 5000) { _ in
                    let line = lastStepLine(
                        ctx, "EDIT undo")
                    out.assertions.append(a(
                        "burst_merged_4",
                        field(line, "merged") == 4,
                        "merged=4", line ?? "none"))
                    let reverted = Self.block(ed, pid)
                    out.assertions.append(a(
                        "one_undo_reverts_burst",
                        reverted?.text == baseText,
                        baseText,
                        reverted?.text ?? "none"))
                    out.assertions.append(a(
                        "canRedo_after_undo",
                        ed.canRedo, "true",
                        "\(ed.canRedo)"))
                    ed.saveNow()
                    let rb2 = notesText(ctx, pid)
                    out.assertions.append(a(
                        "reverted_readback",
                        rb2 == baseText,
                        baseText, rb2 ?? "none"))
                    ed.redo()
                    ctx.waitDiag(
                        pattern: "EDIT redo 余栈",
                        timeoutMs: 5000) { _ in
                        let restored = Self.block(ed, pid)
                        out.assertions.append(a(
                            "redo_restores_burst",
                            restored?.text == burstText,
                            burstText,
                            restored?.text ?? "none"))
                        out.assertions.append(a(
                            "canRedo_consumed",
                            !ed.canRedo, "false",
                            "\(ed.canRedo)"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            }
        }
    }

    /// 清重做尾：再撤一次回到爆发前（undo 栈抽
    /// 干、redo 载爆发态），此时一次新键入必须
    /// 清空 redo 尾（canRedo 归假、新文本落位）。
    static func redoTailStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "new edit clears redo tail"
        ) { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let pid = ctx.store["undoBlockA"]
                    as? String,
                  let baseText = ctx.store[
                    "undoBaseText"] as? String
            else {
                out.ok = false
                out.note = "burst state missing"
                done(out)
                return
            }
            ed.undo()
            ctx.waitDiag(
                pattern: "EDIT undo 余栈",
                timeoutMs: 5000) { _ in
                let back = block(ed, pid)
                out.assertions.append(a(
                    "back_to_base",
                    back?.text == baseText,
                    baseText, back?.text ?? "none"))
                out.assertions.append(a(
                    "redo_armed", ed.canRedo,
                    "true", "\(ed.canRedo)"))
                out.assertions.append(a(
                    "undo_drained", !ed.canUndo,
                    "false", "\(ed.canUndo)"))
                guard let cur = back else {
                    out.ok = false
                    done(out)
                    return
                }
                typeAppend(ed, cur, "己")
                out.assertions.append(a(
                    "redo_tail_cleared", !ed.canRedo,
                    "false", "\(ed.canRedo)"))
                out.assertions.append(a(
                    "new_text_applied",
                    cur.text == baseText + "己",
                    baseText + "己", cur.text))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 选区恢复：辞焦后以非零选区替换键入（检查
    /// 点 sel = 被替换范围 (1,2)）再续一键入（窗
    /// 内合并）——撤销后文本回退、Diag 步行
    /// focus= 回读串恰为 A@1+2、焦点真落回 A；
    /// 撤销后 undo 深度记入 store 供幻影步判
    /// 据。注：恢复认领的 didBeginEditing 会再
    /// 压一个与恢复后文档同 key 的锚（栈顶新
    /// 锚），幻影步的深度账以此为前提。
    static func selectionStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "selection restored on undo"
        ) { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let pid = ctx.store["undoBlockA"]
                    as? String,
                  let block = block(ed, pid)
            else {
                out.ok = false
                out.note = "burst state missing"
                done(out)
                return
            }
            let curText = block.text
            resignFocus(ctx, ed) { ok in
                out.assertions.append(a(
                    "resigned_before", ok,
                    "editing=nil",
                    ed.editingBlockId ?? "none"))
                typeReplace(
                    ed, block,
                    range: NSRange(
                        location: 1, length: 2),
                    "甲乙")
                typeAppend(ed, block, "丙")
                let expected = (curText as NSString)
                    .replacingCharacters(
                        in: NSRange(
                            location: 1, length: 2),
                        with: "甲乙") + "丙"
                out.assertions.append(a(
                    "replace_typed",
                    block.text == expected,
                    expected, block.text))
                ed.undo()
                ctx.waitDiag(
                    pattern: "EDIT undo 余栈",
                    timeoutMs: 5000) { _ in
                    let line = lastStepLine(
                        ctx, "EDIT undo")
                    let reverted = Self.block(ed, pid)
                    out.assertions.append(a(
                        "text_reverted",
                        reverted?.text == curText,
                        curText,
                        reverted?.text ?? "none"))
                    out.assertions.append(a(
                        "focus_restored_sel",
                        focusField(line)
                            == "\(pid)@1+2",
                        "\(pid)@1+2",
                        focusField(line) ?? "none"))
                    if let d = field(line, "undo") {
                        ctx.store["undoDepthBase"] = d
                    }
                    out.assertions.append(a(
                        "depth_recorded",
                        ctx.store["undoDepthBase"]
                            != nil,
                        "depth", line ?? "none"))
                    var streak = 0
                    ctx.poll(timeoutMs: 5000) {
                        if ed.editingBlockId == pid {
                            streak += 1
                        } else {
                            streak = 0
                        }
                        return streak >= 2
                    } done: { ok2 in
                        out.assertions.append(a(
                            "focus_landed_back", ok2,
                            "editing=\(pid)",
                            ed.editingBlockId ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            }
        }
    }

    /// 幻影步：三次「开会话→辞焦」全程零变更——
    /// 栈顶已是选区步恢复认领所压的同 key 锚，
    /// 三次会话压锚必须全被去重（dedup 行恰
    /// 3）；其后一次撤销只消费该锚：文档不变、
    /// 深度恰回到选区步基线（去重失效则深度多
    /// 出 3）。
    static func phantomStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "no phantom steps") { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let pid = ctx.store["undoBlockA"]
                    as? String,
                  let n0 = ctx.store["undoDepthBase"]
                    as? Int,
                  let block = block(ed, pid)
            else {
                out.ok = false
                out.note = "selection state missing"
                done(out)
                return
            }
            let stableText = block.text
            resignFocus(ctx, ed) { _ in
                requestFocus(
                    ctx, ed, blockId: pid,
                    caret: 0, selLen: 0) { ok1 in
                    out.assertions.append(a(
                        "session1_claimed", ok1,
                        "editing=\(pid)",
                        ed.editingBlockId ?? "none"))
                    resignFocus(ctx, ed) { _ in
                        requestFocus(
                            ctx, ed, blockId: pid,
                            caret: 0, selLen: 0) { ok2 in
                            out.assertions.append(a(
                                "session2_claimed", ok2,
                                "editing=\(pid)",
                                ed.editingBlockId
                                    ?? "none"))
                            resignFocus(ctx, ed) { _ in
                                requestFocus(
                                    ctx, ed,
                                    blockId: pid,
                                    caret: 0,
                                    selLen: 0) { ok3 in
                                    out.assertions.append(a(
                                        "session3_claimed",
                                        ok3,
                                        "editing=\(pid)",
                                        ed.editingBlockId
                                            ?? "none"))
                                    let dedups = ctx
                                        .windowEntries()
                                        .filter {
                                            $0.text.contains(
                                                "EDIT undo core dedup")
                                        }
                                    out.assertions.append(a(
                                        "dedup_lines_3",
                                        dedups.count == 3,
                                        "3",
                                        "\(dedups.count)"))
                                    ed.undo()
                                    ctx.waitDiag(
                                        pattern: "EDIT undo 余栈",
                                        timeoutMs: 5000) { _ in
                                        let line =
                                            lastStepLine(
                                                ctx,
                                                "EDIT undo")
                                        let after = Self
                                            .block(ed, pid)
                                        out.assertions
                                            .append(a(
                                                "doc_unchanged_by_anchor_undo",
                                                after?.text
                                                    == stableText,
                                                stableText,
                                                after?.text
                                                    ?? "none"))
                                        out.assertions
                                            .append(a(
                                                "depth_back_to_base",
                                                field(line,
                                                      "undo")
                                                    == n0,
                                                "undo=\(n0)",
                                                line
                                                    ?? "none"))
                                        out.ok = out
                                            .assertions
                                            .allSatisfy {
                                                $0.pass
                                            }
                                        done(out)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 钳制与单消费：todo 勾选连翻 105 次（每次
    /// 变更经漏斗压栈、键交替不触去重）——钳制
    /// 行出现且深度恒 100；其后一次 undo 恰退
    /// 一格（步行恰 1 条）、一次 redo 恰回一格
    /// （F-12 的场景面切片：一次漏斗调用 = 一
    /// 步；物理投递的单发性不在证据面）。
    static func clampStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "history clamps at 100"
        ) { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let tid = (ctx.store["blockIdByType"]
                    as? [String: String])?["todo"],
                  let todo = block(ed, tid)
            else {
                out.ok = false
                out.note = "todo block missing"
                done(out)
                return
            }
            let startChecked = todo.checked
            for _ in 0..<105 {
                ed.toggleTodoChecked(todo)
            }
            out.assertions.append(a(
                "toggles_flipped_odd",
                todo.checked == !startChecked,
                "\(!startChecked)",
                "\(todo.checked)"))
            let clamps = ctx.windowEntries().filter {
                $0.text.contains("EDIT undo core clamp")
            }
            out.assertions.append(a(
                "clamp_logged", !clamps.isEmpty,
                ">=1 clamp line",
                clamps.last?.text ?? "none"))
            out.assertions.append(a(
                "clamp_depth_100",
                clamps.last?.text
                    .contains("depth=100") == true,
                "depth=100",
                clamps.last?.text ?? "none"))
            ed.undo()
            let t1 = block(ed, tid)
            out.assertions.append(a(
                "single_undo_one_step",
                t1?.checked == startChecked,
                "\(startChecked)",
                "\(t1?.checked ?? !startChecked)"))
            let undoLines = ctx.windowEntries()
                .filter {
                    $0.text.contains("EDIT undo 余栈")
                }
            out.assertions.append(a(
                "single_undo_one_line",
                undoLines.count == 1, "1",
                "\(undoLines.count)"))
            ed.redo()
            let t2 = block(ed, tid)
            out.assertions.append(a(
                "single_redo_one_step",
                t2?.checked == !startChecked,
                "\(!startChecked)",
                "\(t2?.checked ?? startChecked)"))
            out.ok = out.assertions
                .allSatisfy { $0.pass }
            done(out)
        }
    }
}

// ── EDT-60 图片块在席塞图（fix_image_card_load）：
// image_block_seated_load ──
// 斜杠建空图片块（闩锁旧形态在此把 failed 打
// 死）→ 程序化走 replaceImage 塞夹具图 → 全程
// 不重进备忘、断言键控重载当场出图（IMG reload
// 行 + 注册面 tone）；末步完整性抽样：同篇
// gallery 存量三图 tone 各归其项、不串件。图
// 面以 fid/块 id 为 instance 注册，ctx.state
// 只寻 instance "-"，故场景经注册表直读（既
// 有面限制，见 fix 报告）。

enum UITestScenarioImageSeated {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestShared.a(name, pass, expected, actual)
    }

    static func faceState(
        _ id: String, _ instance: String,
        _ key: String) -> String? {
        UITestRegistry.shared.entry(
            id: id, instance: instance)?
            .state[key]?()
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            slashBuildStep(),
            seatImageStep(),
            integrityStep(),
            UITestShared.closeStep(),
        ]
    }

    static func slashBuildStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "slash builds empty image block") {
            ctx, done in
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
                out.note = "fixture block missing"
                done(out)
                return
            }
            ctx.store["imageBlockId"] = pid
            UITestShared.feedBlockText(
                ed, block, "/")
            ctx.waitDiag(
                pattern: "SLASH open",
                timeoutMs: 5000) { lines in
                out.assertions.append(a(
                    "slash_open_logged",
                    !lines.isEmpty,
                    "SLASH open x1",
                    lines.first?.text ?? "none"))
                UITestShared.feedBlockText(
                    ed, block, "/tp")
                ctx.waitState(
                    surface: "editor.slashPanel",
                    key: "selAct",
                    equals: "image",
                    timeoutMs: 5000) { ok, _ in
                    out.assertions.append(a(
                        "image_cmd_selected", ok,
                        "image",
                        ctx.state(
                            "editor.slashPanel",
                            "selAct") ?? "none"))
                    ctx.surface("editor.slashPanel")?
                        .actions["applySelected"]?(nil)
                    ctx.poll(timeoutMs: 5000) {
                        guard let b = ed.blocks.first(
                            where: { $0.id == pid })
                        else { return false }
                        return b.type == "image"
                            && b.fileId == nil
                            && b.imageURL == nil
                    } done: { okConv in
                        let b = ed.blocks.first(
                            where: { $0.id == pid })
                        out.assertions.append(a(
                            "block_now_empty_image",
                            okConv, "image/nil",
                            "\(b?.type ?? "none")/"
                            + "\(b?.fileId ?? "nil")"))
                        ctx.poll(timeoutMs: 5000) {
                            faceState(
                                "image.block", pid,
                                "hasImage") == "false"
                        } done: { okFace in
                            out.assertions.append(a(
                                "block_face_no_image",
                                okFace, "false",
                                faceState(
                                    "image.block", pid,
                                    "hasImage")
                                    ?? "none"))
                            out.ok = out.assertions
                                .allSatisfy { $0.pass }
                            done(out)
                        }
                    }
                }
            }
        }
    }

    static func seatImageStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "replaceImage seats photo") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let bid = ctx.store[
                    "imageBlockId"] as? String
            else {
                out.ok = false
                out.note = "no seated editor/block"
                done(out)
                return
            }
            let fid = "att-" + UUID().uuidString
                .prefix(12).lowercased()
            let put = UITestFixtureTemplate
                .solidPNG(255, 0, 255).map {
                    ctx.library.putAttachment(
                        fid, $0, name: "uitest.png")
                } ?? false
            out.assertions.append(a(
                "fixture_png_put", put,
                "true", "\(put)"))
            guard put else {
                out.ok = false
                done(out)
                return
            }
            ed.replaceImageBlockId = bid
            ed.replaceImage(fileId: fid)
            ctx.waitDiag(
                pattern: "IMG reload fid=\(fid)",
                timeoutMs: 5000) { lines in
                out.assertions.append(a(
                    "reload_logged", !lines.isEmpty,
                    "IMG reload fid=\(fid)",
                    lines.first?.text ?? "none"))
                ctx.poll(timeoutMs: 5000) {
                    faceState("image.block", bid,
                              "hasImage") == "true"
                        && faceState("image.block",
                                     bid, "tone")
                            == "ff00ff"
                        && faceState("image.block",
                                     bid, "failed")
                            == "false"
                } done: { okImg in
                    out.assertions.append(a(
                        "image_shows_in_place", okImg,
                        "true/ff00ff/false",
                        "\(faceState("image.block", bid, "hasImage") ?? "none")/"
                        + "\(faceState("image.block", bid, "tone") ?? "none")/"
                        + "\(faceState("image.block", bid, "failed") ?? "none")"))
                    // 不重进：编辑器仍在席同篇（全
                    // 程未 close/open，结构即证）。
                    let still = UITestShared
                        .seatedEditor(ctx)
                    out.assertions.append(a(
                        "editor_still_seated",
                        still != nil,
                        "seated \(ctx.fixtureId)",
                        still != nil
                            ? "seated" : "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    static func integrityStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "stock attachments unmixed") {
            ctx, done in
            var out = UITestStepOutcome()
            let fids = UITestFixtureTemplate
                .mediaFids
            let tones = UITestFixtureTemplate
                .mediaTones
            ctx.poll(timeoutMs: 5000) {
                zip(fids, tones).allSatisfy {
                    fid, tone in
                    faceState("image.item", fid,
                              "hasImage") == "true"
                        && faceState("image.item",
                                     fid, "tone")
                            == tone
                }
            } done: { ok in
                let actual = fids.map {
                    faceState("image.item", $0,
                              "tone") ?? "none"
                }.joined(separator: "/")
                out.assertions.append(a(
                    "stock_tones_intact", ok,
                    tones.joined(separator: "/"),
                    actual))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }
}

// ── EDT-61 gallery 图随项（fix_image_card_load）：
// gallery_items_follow ──
// 基线三瓦 tone 各归其项 → 删首项后模型余
// [gb, gc] 且注册面无红图残留（图随位则 gb
// 面呈红、判红）→ 换首项为黄图后新图当场出、
// 末项 tone 不变（存量不串件）。

enum UITestScenarioGalleryFollow {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestShared.a(name, pass, expected, actual)
    }

    static func faceState(
        _ id: String, _ instance: String,
        _ key: String) -> String? {
        UITestRegistry.shared.entry(
            id: id, instance: instance)?
            .state[key]?()
    }

    static func galleryId(
        _ ctx: UITestRunContext) -> String? {
        (ctx.store["blockIdByType"]
            as? [String: String])?["gallery"]
    }

    static func itemsFids(
        _ ed: EditorModel, _ gid: String)
        -> [String] {
        guard let b = ed.blocks.first(
                where: { $0.id == gid }),
              let items = (b.node["attrs"]
                as? [String: Any])?["items"]
                as? [[String: Any]]
        else { return [] }
        return items.map {
            $0["fileId"] as? String ?? ""
        }
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            baselineStep(),
            removeStep(),
            followStep(),
            replaceStep(),
            UITestShared.closeStep(),
        ]
    }

    static func baselineStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "gallery baseline tones") {
            ctx, done in
            var out = UITestStepOutcome()
            let fids = UITestFixtureTemplate
                .mediaFids
            let tones = UITestFixtureTemplate
                .mediaTones
            ctx.poll(timeoutMs: 5000) {
                zip(fids, tones).allSatisfy {
                    fid, tone in
                    faceState("image.item", fid,
                              "hasImage") == "true"
                        && faceState("image.item",
                                     fid, "tone")
                            == tone
                }
            } done: { ok in
                let actual = fids.map {
                    faceState("image.item", $0,
                              "tone") ?? "none"
                }.joined(separator: "/")
                out.assertions.append(a(
                    "baseline_tones", ok,
                    tones.joined(separator: "/"),
                    actual))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    static func removeStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "remove first gallery item") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let gid = galleryId(ctx)
            else {
                out.ok = false
                out.note = "no seated editor/gallery"
                done(out)
                return
            }
            ed.applyGalleryRemove(
                blockId: gid, index: 0)
            let left = itemsFids(ed, gid)
            let want = Array(UITestFixtureTemplate
                .mediaFids.dropFirst())
            out.assertions.append(a(
                "model_items_after_remove",
                left == want,
                want.joined(separator: "/"),
                left.joined(separator: "/")))
            out.ok = out.assertions
                .allSatisfy { $0.pass }
            done(out)
        }
    }

    static func followStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "tiles follow items") {
            ctx, done in
            var out = UITestStepOutcome()
            let gb = UITestFixtureTemplate
                .mediaFids[1]
            let gc = UITestFixtureTemplate
                .mediaFids[2]
            ctx.poll(timeoutMs: 5000) {
                let gbOk = faceState(
                    "image.item", gb, "tone")
                    == "00ff00"
                let gcOk = faceState(
                    "image.item", gc, "tone")
                    == "0000ff"
                let redLeft = UITestRegistry
                    .shared.all()
                    .filter { $0.id == "image.item" }
                    .contains {
                        $0.state["tone"]?()
                            == "ff0000"
                    }
                return gbOk && gcOk && !redLeft
            } done: { ok in
                out.assertions.append(a(
                    "tiles_follow_items", ok,
                    "gb=00ff00/gc=0000ff/no-red",
                    "gb=\(faceState("image.item", gb, "tone") ?? "none")"
                    + "/gc=\(faceState("image.item", gc, "tone") ?? "none")"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    static func replaceStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "replace tile loads new") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let gid = galleryId(ctx)
            else {
                out.ok = false
                out.note = "no seated editor/gallery"
                done(out)
                return
            }
            let gd = "att-uitest-gd"
            let gc = UITestFixtureTemplate
                .mediaFids[2]
            let put = UITestFixtureTemplate
                .solidPNG(255, 255, 0).map {
                    ctx.library.putAttachment(
                        gd, $0, name: gd + ".png")
                } ?? false
            out.assertions.append(a(
                "fixture_png_put", put,
                "true", "\(put)"))
            guard put else {
                out.ok = false
                done(out)
                return
            }
            ed.applyGalleryReplace(
                blockId: gid, index: 0, fileId: gd)
            ctx.poll(timeoutMs: 5000) {
                faceState("image.item", gd,
                          "hasImage") == "true"
                    && faceState("image.item", gd,
                                 "tone") == "ffff00"
                    && faceState("image.item", gc,
                                 "tone") == "0000ff"
            } done: { ok in
                out.assertions.append(a(
                    "replaced_tile_shows_new", ok,
                    "gd=ffff00/gc=0000ff",
                    "gd=\(faceState("image.item", gd, "tone") ?? "none")"
                    + "/gc=\(faceState("image.item", gc, "tone") ?? "none")"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }
}

// ── 几何探针（U2 五件 + U5 P4，矩阵 §6.1/§6.4）──
// uitest_measure 的实装：探针只出数 + 落定标，
// 判读（期望式/阈值）在场景与调用方。量测一律
// 走 BlockState/注册面的既有量测通道，不新开
// 第二套读数路径。
//
// 几何前提账（逐项，落码与断言同读）：
// ① 坐标系：编辑器内帧恒 editorScroll 命名空间
//   （BlockState frameMinX/frameMinY/rowW/height
//   与 face 四值同系）；首页行帧恒 window 坐标
//   （home.row frameInWindow = 行 GeometryReader
//   的 .global 帧）。两系不混算，payload 逐探针
//   标 coords。
// ② 落定口径：探针内两读——首读后泵主 runloop
//   0.15s 复读，全部数值字段两读差 ≤0.5pt 才标
//   settled=true；动画中的帧不作落定数（标
//   settled=false 只出数）。动画过程断言不用探
//   针（帧数口径是 Web 侧手段，原生无等价面）。
// ③ 正文列基准（P1）：在席编辑器内最宽行派生
//   ——文本行恒满列宽、卡面恒内缩或等宽，故最宽
//   行的左右缘即正文列左右缘；无任何已量测行时
//   回 surface_missing，不以视口宽充数。
// ④ 面帧判读：faceRadius 哨兵 −2（未回报）/
//   faceW == 0 时探针回 surface_missing；−1 =
//   面在子视图（image/gallery），帧值仍为行内
//   分支实测（内缩后卡槽），半径无行级单值。
// ⑤ lift 框（P2）：渲染本体 = 面经 LiftFrame 以
//   .padding(−Radius.liftInset) 外扩 + 按面尺寸
//   liftScale 缩放；探针回的 liftFrame 是未缩放
//   派生帧（标 derived），主判读 = 面相对行盒的
//   四边内缩量（实测）与每边间隙期望 4 的关系。

enum UITestProbes {

    static let ids = [
        "card_alignment", "lift_gaps",
        "menu_panel", "slash_panel",
        "radius_derivation", "home_geometry",
    ]

    static func run(
        _ probe: String, args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        switch probe {
        case "card_alignment":
            return twoRead { cardAlignment(args) }
        case "lift_gaps":
            return twoRead { liftGaps(args) }
        case "menu_panel":
            return twoRead { menuPanel() }
        case "slash_panel":
            return twoRead { slashPanel() }
        case "radius_derivation":
            return twoRead { radiusDerivation() }
        case "home_geometry":
            return twoRead { homeGeometry() }
        default:
            return .failure(.invalidParams(
                "unknown probe: \(probe)"))
        }
    }

    // ── 落定两读 ──

    /// 首读 → 泵主 runloop 0.15s → 复读；复读值
    /// 为 payload，两读数值差 ≤0.5 标 settled。
    /// 失败结果不泵（错误即时回）。
    private static func twoRead(
        _ build: () -> Result<[String: Any],
                              BridgeToolError>
    ) -> Result<[String: Any], BridgeToolError> {
        let first = build()
        guard case .success(let a) = first else {
            return first
        }
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.15))
        switch build() {
        case .failure(let e):
            return .failure(e)
        case .success(var b):
            b["settled"] = numericallyClose(a, b)
            return .success(b)
        }
    }

    /// 递归数值比对：字典内全部 NSNumber 字段两
    /// 读差 ≤0.5（字符串/布尔不参与落定判）。
    private static func numericallyClose(
        _ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber,
           let y = b as? NSNumber {
            return abs(x.doubleValue - y.doubleValue)
                <= 0.5
        }
        if let x = a as? [String: Any],
           let y = b as? [String: Any] {
            for (k, v) in x {
                guard let w = y[k],
                      numericallyClose(v, w) else {
                    return false
                }
            }
            return true
        }
        if let x = a as? [Any], let y = b as? [Any] {
            guard x.count == y.count else {
                return false
            }
            return zip(x, y).allSatisfy {
                numericallyClose($0, $1)
            }
        }
        return true
    }

    // ── 共用读数 ──

    private static func missing(
        _ what: String) -> BridgeToolError {
        BridgeToolError(
            code: "surface_missing",
            message: what)
    }

    private static func seatedEditor()
        -> EditorModel? {
        EditorSeatRegistry.shared.currentEditor
    }

    private static func block(
        _ ed: EditorModel, _ args: [String: Any]
    ) -> Result<BlockState, BridgeToolError> {
        guard let bid = args["blockId"] as? String,
              !bid.isEmpty else {
            return .failure(.invalidParams(
                "blockId required"))
        }
        guard let b = ed.blocks.first(
            where: { $0.id == bid }) else {
            return .failure(missing(
                "block not in seated editor: "
                + bid))
        }
        return .success(b)
    }

    private static func frameDict(
        minX: CGFloat, minY: CGFloat,
        w: CGFloat, h: CGFloat) -> [String: Any] {
        [
            "minX": Double(minX),
            "minY": Double(minY),
            "w": Double(w),
            "h": Double(h),
            "maxX": Double(minX + w),
            "maxY": Double(minY + h),
        ]
    }

    private static func rowFrame(
        _ b: BlockState) -> [String: Any] {
        frameDict(minX: b.frameMinX,
                  minY: b.frameMinY,
                  w: b.rowW, h: b.height)
    }

    /// 卡面帧：未回报（faceW == 0 或半径哨兵
    /// −2）回 nil，消费方据此转 surface_missing。
    private static func faceFrame(
        _ b: BlockState) -> [String: Any]? {
        guard b.faceW > 0, b.faceRadius != -2
        else { return nil }
        return frameDict(minX: b.faceMinX,
                         minY: b.faceMinY,
                         w: b.faceW, h: b.faceH)
    }

    // ── P1 card_alignment ──
    // 回行盒帧 + 卡面帧 + 正文列基准 + 两缘差。
    // 判读基线（调用方按块型选期望式）：满宽卡
    // 两差 ≈0（±0.5）；image/gallery 单栏态两差
    // ≈36 对称（内缩口径）、双栏态 ≈0。

    private static func cardAlignment(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let ed = seatedEditor() else {
            return .failure(missing(
                "no editor seated"))
        }
        let b: BlockState
        switch block(ed, args) {
        case .failure(let e): return .failure(e)
        case .success(let v): b = v
        }
        guard let face = faceFrame(b) else {
            return .failure(missing(
                "face channel unreported for "
                + "block \(b.id)"))
        }
        // 正文列基准：在席内最宽行（前提③）。
        guard let widest = ed.blocks
            .filter({ $0.rowW > 0 })
            .max(by: { $0.rowW < $1.rowW }) else {
            return .failure(missing(
                "no measured row in seated "
                + "editor"))
        }
        let colMinX = Double(widest.frameMinX)
        let colMaxX = Double(
            widest.frameMinX + widest.rowW)
        let faceMinX = face["minX"] as? Double
            ?? 0
        let faceMaxX = face["maxX"] as? Double
            ?? 0
        return .success([
            "probe": "card_alignment",
            "coords": "editorScroll",
            "blockId": b.id,
            "type": b.type,
            "row": rowFrame(b),
            "face": face,
            "column": [
                "minX": colMinX, "maxX": colMaxX,
                "w": colMaxX - colMinX,
                "basis": "widest_row",
            ],
            "leftDelta": faceMinX - colMinX,
            "rightDelta": colMaxX - faceMaxX,
            "faceRadius": Double(b.faceRadius),
        ])
    }

    // ── P2 lift_gaps ──
    // 前置：目标块正被拾起（draggingId ==
    // blockId，否则 invalid_params 明示）。回行
    // 盒/卡面实测帧 + 框派生帧（derived）+ 面相
    // 对行盒四边内缩量（实测主判读）+ 面到框四
    // 边间隙（派生恒 = liftInset，附缩放后视觉
    // 间隙期望式供调用方对读）。

    private static func liftGaps(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let ed = seatedEditor() else {
            return .failure(missing(
                "no editor seated"))
        }
        let b: BlockState
        switch block(ed, args) {
        case .failure(let e): return .failure(e)
        case .success(let v): b = v
        }
        guard ed.draggingId == b.id else {
            return .failure(.invalidParams(
                "block not lifted (draggingId="
                + (ed.draggingId ?? "nil") + ")"))
        }
        guard let face = faceFrame(b) else {
            return .failure(missing(
                "face channel unreported for "
                + "block \(b.id)"))
        }
        let inset = Radius.liftInset
        let lift = frameDict(
            minX: b.faceMinX - inset,
            minY: b.faceMinY - inset,
            w: b.faceW + inset * 2,
            h: b.faceH + inset * 2)
        // liftScale 与 BlockRow.liftScale 同式
        // （Web liftScaleFor）：max((dim−8)/dim,
        // 0.9)，量测缺失回退 0.97。
        func liftScale(_ dim: CGFloat) -> CGFloat {
            dim > 0
                ? max((dim - 8) / dim, 0.9) : 0.97
        }
        let sx = liftScale(b.faceW)
        let sy = liftScale(b.faceH)
        return .success([
            "probe": "lift_gaps",
            "coords": "editorScroll",
            "blockId": b.id,
            "type": b.type,
            "dragDy": Double(ed.dragDy),
            "row": rowFrame(b),
            "face": face,
            "liftFrame": lift,
            "liftFrameDerived": true,
            "faceInsets": [
                "left": Double(
                    b.faceMinX - b.frameMinX),
                "right": Double(
                    b.frameMinX + b.rowW
                    - (b.faceMinX + b.faceW)),
                "top": Double(
                    b.faceMinY - b.frameMinY),
                "bottom": Double(
                    b.frameMinY + b.height
                    - (b.faceMinY + b.faceH)),
            ],
            "gaps": [
                "left": Double(inset),
                "right": Double(inset),
                "top": Double(inset),
                "bottom": Double(inset),
            ],
            "liftScaleX": Double(sx),
            "liftScaleY": Double(sy),
            "visualGapX": Double(
                inset + b.faceW * (1 - sx) / 2),
            "visualGapY": Double(
                inset + b.faceH * (1 - sy) / 2),
            "faceRadius": Double(b.faceRadius),
        ])
    }

    // ── P3 menu_panel / slash_panel ──
    // 三值直读注册面：contentH（内容实测）/
    // renderedH（帧实高）/cap（限高公式值）。
    // 面板未开时回 open=false 的成功 payload
    // （前置由调用方经注册面动作或场景打开，
    // 探针不代开）。

    private static func menuPanel()
        -> Result<[String: Any], BridgeToolError> {
        guard let e = UITestRegistry.shared.entry(
            id: "editor.menuPanel", instance: "-")
        else {
            return .failure(missing(
                "editor.menuPanel not registered "
                + "(no editor seated)"))
        }
        let open = e.state["open"]?() == "true"
        guard open else {
            return .success([
                "probe": "menu_panel",
                "open": false,
            ])
        }
        let contentH = Double(
            e.state["contentH"]?() ?? "") ?? 0
        let renderedH = e.frameInWindow()
            .map { Double($0.height) } ?? 0
        var viewH = 0.0
        if let v = UITestRegistry.shared.entry(
            id: "editor.view", instance: "-"),
           let f = v.frameInWindow() {
            viewH = Double(f.height)
        }
        // cap 与注册面 capped 判式同源：
        // max(200, viewH − 67)。
        let cap = max(200, viewH - 67)
        return .success([
            "probe": "menu_panel",
            "open": true,
            "contentH": contentH,
            "renderedH": renderedH,
            "cap": cap,
            "capped": contentH > cap,
        ])
    }

    private static func slashPanel()
        -> Result<[String: Any], BridgeToolError> {
        guard let e = UITestRegistry.shared.entry(
            id: "editor.slashPanel", instance: "-")
        else {
            return .failure(missing(
                "editor.slashPanel not registered "
                + "(no editor seated)"))
        }
        let open = e.state["open"]?() == "true"
        guard open else {
            return .success([
                "probe": "slash_panel",
                "open": false,
            ])
        }
        // slashPanelH 是面板实高的实测回写（内
        // 容超 cap 时即钳后值）——contentH 与
        // renderedH 同值是该通道的既有口径，
        // cap 经 slashPanelMaxH 同点回写单源。
        let h = Double(
            e.state["panelH"]?() ?? "") ?? 0
        let cap = Double(
            e.state["panelMaxH"]?() ?? "") ?? 0
        return .success([
            "probe": "slash_panel",
            "open": true,
            "contentH": h,
            "renderedH": h,
            "cap": cap,
            "capped": cap > 0 && h >= cap - 0.5,
        ])
    }

    // ── P5 radius_derivation ──
    // Radius 令牌表单源直读 + 在席编辑器逐块
    // faceRadius 派生回读。image 的子视图半径
    // 无行级单值（哨兵 −1），附调用点常量两值
    // （有图 = cardS、占位 = cardL，与
    // ImageBlockView 的 LiftFrame 挂点同值，
    // verify [68] 锁两处同源）。

    private static func radiusDerivation()
        -> Result<[String: Any], BridgeToolError> {
        var payload: [String: Any] = [
            "probe": "radius_derivation",
            "tokens": [
                "cardS": Double(Radius.cardS),
                "cardL": Double(Radius.cardL),
                "grid": Double(Radius.grid),
                "quote": Double(Radius.quote),
                "mdImage": Double(Radius.mdImage),
                "block": Double(Radius.block),
                "pill": Double(Radius.pill),
                "titleCapsule": Double(
                    Radius.titleCapsule),
                "liftInset": Double(
                    Radius.liftInset),
                "panel": Double(Radius.panel),
                "panelHero": Double(
                    Radius.panelHero),
                "panelS": Double(Radius.panelS),
                "controlS": Double(
                    Radius.controlS),
            ],
            "imageSubview": [
                "hasImage": Double(Radius.cardS),
                "placeholder": Double(
                    Radius.cardL),
            ],
        ]
        if let ed = seatedEditor() {
            payload["blocks"] = ed.blocks.map {
                b -> [String: Any] in
                [
                    "id": b.id,
                    "type": b.type,
                    "faceRadius": Double(
                        b.faceRadius),
                    "reported": b.faceRadius != -2,
                ]
            }
        }
        return .success(payload)
    }

    // ── P4 home_geometry ──
    // home.row 帧（window 坐标）关系式出数：
    // 左右边距 = 首行卡缘到窗缘；卡间距 = 同列
    // 相邻行帧差（缘到缘）；首卡距顶 = 最上行
    // minY（窗坐标原点起，含页眉区——原始值出
    // 数，期望式在调用方按当时页眉态选）；列数
    // = 首带内不同 minX 的行数。不写死常数。

    private static func homeGeometry()
        -> Result<[String: Any], BridgeToolError> {
        let rows = UITestRegistry.shared.all()
            .filter { $0.id == "home.row" }
            .compactMap { e -> (String, String,
                                CGRect)? in
                guard let f = e.frameInWindow()
                else { return nil }
                return (e.instance,
                        e.state["form"]?() ?? "",
                        f)
            }
            .sorted {
                $0.2.minY != $1.2.minY
                    ? $0.2.minY < $1.2.minY
                    : $0.2.minX < $1.2.minX
            }
        guard let first = rows.first else {
            return .failure(missing(
                "no home rows registered "
                + "(not on home surface)"))
        }
        let screen = UIScreen.main.bounds
        let leftMargin = rows.map {
            Double($0.2.minX)
        }.min() ?? 0
        let rightMargin = Double(screen.width)
            - (rows.map { Double($0.2.maxX) }
                .max() ?? 0)
        // 同列相邻间距：按 minX 分列（±1 归
        // 同），列内按 minY 序取相邻缘差。
        var gaps: [Double] = []
        let colKeys = Set(rows.map {
            Int($0.2.minX.rounded())
        })
        for key in colKeys {
            let col = rows.filter {
                Int($0.2.minX.rounded()) == key
            }
            for i in 1..<col.count {
                gaps.append(Double(
                    col[i].2.minY
                    - col[i - 1].2.maxY))
            }
        }
        // 首带列数：与首行同带（minY 差 < 首行
        // 高）的不同 minX 数。
        let band = rows.filter {
            $0.2.minY - first.2.minY
                < first.2.height
        }
        let columns = Set(band.map {
            Int($0.2.minX.rounded())
        }).count
        return .success([
            "probe": "home_geometry",
            "coords": "window",
            "windowW": Double(screen.width),
            "windowH": Double(screen.height),
            "rowCount": rows.count,
            "rows": rows.map { r -> [String: Any] in
                [
                    "id": r.0,
                    "form": r.1,
                    "frame": frameDict(
                        minX: r.2.minX,
                        minY: r.2.minY,
                        w: r.2.width,
                        h: r.2.height),
                ]
            },
            "leftMargin": leftMargin,
            "rightMargin": rightMargin,
            "cardGaps": gaps,
            "firstRowTop": Double(first.2.minY),
            "columns": columns,
        ])
    }
}

// ── U3 场景：drag_pickup_statemachine ──
// 经 editor.blockRow 面调 DragPress 四入口本
// 体（与识别器回调同一组方法，S3 定案）；断言
// 面 = 模型状态 + 注册面回读 + Diag 行 + 落盘
// 块序。让位量期望以 dragShift 同源公式在景内
// 由实测高推导（期望侧），注册面 rowDragOffset
// 为渲染实值（实测侧），两边对读即机制锁。

enum UITestScenarioDragPickup {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestShared.a(name, pass, expected, actual)
    }

    static func row(
        _ id: String) -> UITestSurfaceEntry? {
        UITestRegistry.shared.entry(
            id: "editor.blockRow", instance: id)
    }

    static func rowState(
        _ id: String, _ key: String) -> String? {
        row(id)?.state[key]?()
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            quotePickupFaceStep(),
            dragFlowStep(),
            dropOrderStep(),
            cancelResetStep(),
            UITestShared.closeStep(),
        ]
    }

    /// 拾起引用块（行级面）：拾起态 face 与行盒
    /// 同值断言（P2 景内自给段，EDT-27）+ 菜单
    /// 骑拾起（EDT-30）+ cancel 复位（EDT-25）。
    static func quotePickupFaceStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "pickup quote: face + menu + "
                + "cancel") { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let qid = (ctx.store[
                    "blockIdByType"] as? [String:
                        String])?["quote"],
                  let block = ed.blocks.first(
                    where: { $0.id == qid }),
                  let r = row(qid) else {
                out.ok = false
                out.note = "quote row missing"
                done(out)
                return
            }
            ctx.store["quoteId"] = qid
            r.actions["pickup"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ed.draggingId == qid
            } done: { ok in
                out.assertions.append(a(
                    "pickup_state", ok,
                    "draggingId=\(qid)",
                    ed.draggingId ?? "nil"))
                out.assertions.append(a(
                    "menu_rides_pickup",
                    rowState(qid, "menuShown")
                        == "true",
                    "true",
                    rowState(qid, "menuShown")
                        ?? "none"))
                // face 落定后对读（量测两轮一
                // 致由 poll 的连续成立近似：直
                // 读模型通道当前值，容差 0.5）。
                let faceOK =
                    abs(block.faceMinX
                        - block.frameMinX) <= 0.5
                    && abs(block.faceW
                        - block.rowW) <= 0.5
                    && abs(block.faceMinY
                        - block.frameMinY) <= 0.5
                    && abs(block.faceH
                        - block.height) <= 0.5
                out.assertions.append(a(
                    "face_equals_row",
                    faceOK,
                    "face==row ±0.5",
                    "face=(\(block.faceMinX),"
                    + "\(block.faceMinY),"
                    + "\(block.faceW),"
                    + "\(block.faceH)) row=("
                    + "\(block.frameMinX),"
                    + "\(block.frameMinY),"
                    + "\(block.rowW),"
                    + "\(block.height))"))
                out.assertions.append(a(
                    "face_radius_quote",
                    block.faceRadius
                        == Radius.quote,
                    "\(Radius.quote)",
                    "\(block.faceRadius)"))
                r.actions["cancel"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    ed.draggingId == nil
                        && ed.dragDy == 0
                } done: { ok2 in
                    out.assertions.append(a(
                        "cancel_resets", ok2,
                        "draggingId=nil dragDy=0",
                        "draggingId="
                        + (ed.draggingId ?? "nil")
                        + " dragDy=\(ed.dragDy)"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 拾起段落 → 拖动：跟手量、菜单自动收起
    /// （>10）、下邻行让位量对读（EDT-26）。
    static func dragFlowStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "pickup paragraph + drag: "
                + "follow/menu/yield") { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let pid = (ctx.store[
                    "paragraphIds"]
                    as? [String])?.first,
                  let idx = ed.blocks.firstIndex(
                    where: { $0.id == pid }),
                  idx + 1 < ed.blocks.count,
                  let r = row(pid) else {
                out.ok = false
                out.note = "paragraph row missing"
                done(out)
                return
            }
            let next = ed.blocks[idx + 1]
            let orderBefore = ed.blocks.map {
                $0.id
            }
            ctx.store["dragId"] = pid
            ctx.store["orderBefore"] = orderBefore
            // 让位期望（dragShift 同源式）：dy
            // 过下邻行半高 → 下邻行让出被拖块
            // 全高（height + 6 间隙）。
            let dragH = (ed.blocks[idx].height
                > 0 ? ed.blocks[idx].height : 40)
                + 6
            let nextH = (next.height > 0
                ? next.height : 40) + 6
            let dy: CGFloat = 160
            let expectYield: CGFloat =
                dy > nextH / 2 ? -dragH : 0
            ctx.store["expectYield"] =
                Double(expectYield)
            r.actions["pickup"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ed.draggingId == pid
                    && rowState(pid, "menuShown")
                        == "true"
            } done: { ok in
                out.assertions.append(a(
                    "pickup_menu_shown", ok,
                    "dragging + menuShown=true",
                    "dragging="
                    + (ed.draggingId ?? "nil")
                    + " menu="
                    + (rowState(pid, "menuShown")
                        ?? "none")))
                r.actions["drag"]?(Double(dy))
                ctx.poll(timeoutMs: 5000) {
                    let off = Double(
                        rowState(pid, "dragOffset")
                            ?? "")
                    let yOff = Double(
                        rowState(next.id,
                                 "dragOffset")
                            ?? "")
                    return off != nil
                        && abs(off! - Double(dy))
                            <= 0.5
                        && yOff != nil
                        && abs(yOff!
                            - Double(expectYield))
                            <= 0.5
                        && rowState(pid,
                            "menuShown") == "false"
                } done: { ok2 in
                    out.assertions.append(a(
                        "drag_follow_yield_menu", ok2,
                        "offset=\(dy) yield="
                        + "\(expectYield) "
                        + "menu=false",
                        "offset="
                        + (rowState(pid,
                            "dragOffset") ?? "none")
                        + " yield="
                        + (rowState(next.id,
                            "dragOffset") ?? "none")
                        + " menu="
                        + (rowState(pid,
                            "menuShown") ?? "none")))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 落位：drop 后块序（被拖块下移、余块相对
    /// 序不变）+ 落盘回读一致 + settle 偏移归
    /// 零（EDT-24）。
    static func dropOrderStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "drop: order + persistence + "
                + "settle") { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let pid = ctx.store["dragId"]
                    as? String,
                  let before = ctx.store[
                    "orderBefore"] as? [String],
                  let r = row(pid) else {
                out.ok = false
                out.note = "drag state missing"
                done(out)
                return
            }
            r.actions["drop"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ed.draggingId == nil
            } done: { ok in
                let after = ed.blocks.map { $0.id }
                let oldIdx = before.firstIndex(
                    of: pid) ?? -1
                let newIdx = after.firstIndex(
                    of: pid) ?? -1
                out.assertions.append(a(
                    "drop_state_cleared", ok,
                    "draggingId=nil",
                    ed.draggingId ?? "nil"))
                out.assertions.append(a(
                    "order_moved_down",
                    newIdx > oldIdx,
                    "index > \(oldIdx)",
                    "\(oldIdx)->\(newIdx)"))
                out.assertions.append(a(
                    "others_relative_order",
                    after.filter { $0 != pid }
                        == before.filter {
                            $0 != pid
                        },
                    "others unchanged",
                    "see order"))
                ctx.store["orderAfter"] = after
                // 落盘回读：库内夹具篇块序与模
                // 型序一致（persist 防抖窗内轮
                // 询落定）。
                ctx.poll(timeoutMs: 8000) {
                    guard let item = ctx.library
                        .memos.first(where: {
                            $0.id == ctx.fixtureId
                        }) else { return false }
                    return item.blocks.map {
                        $0.id
                    } == after
                } done: { ok2 in
                    out.assertions.append(a(
                        "persisted_order", ok2,
                        "library order == model",
                        "poll timeout"))
                    ctx.poll(timeoutMs: 5000) {
                        Double(rowState(
                            pid, "dragOffset")
                            ?? "") == 0
                    } done: { ok3 in
                        out.assertions.append(a(
                            "settle_zero", ok3,
                            "dragOffset=0",
                            rowState(pid,
                                "dragOffset")
                                ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            }
        }
    }

    /// 取消复位：拾起另一块 → 拖动 → cancel →
    /// 状态清零且块序不变（EDT-25）。
    static func cancelResetStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "pickup + drag + cancel: "
                + "order intact") { ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let after = ctx.store[
                    "orderAfter"] as? [String],
                  let target = ed.blocks.dropFirst()
                    .first,
                  let r = row(target.id) else {
                out.ok = false
                out.note = "cancel target missing"
                done(out)
                return
            }
            r.actions["pickup"]?(nil)
            r.actions["drag"]?(40)
            r.actions["cancel"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ed.draggingId == nil
                    && ed.dragDy == 0
            } done: { ok in
                out.assertions.append(a(
                    "cancel_state_cleared", ok,
                    "draggingId=nil dragDy=0",
                    "draggingId="
                    + (ed.draggingId ?? "nil")
                    + " dragDy=\(ed.dragDy)"))
                out.assertions.append(a(
                    "cancel_order_intact",
                    ed.blocks.map { $0.id } == after,
                    "order unchanged",
                    "order changed"))
                out.assertions.append(a(
                    "cancel_menu_cleared",
                    ed.cardMenuBlockId == nil
                        && ed.blockMenuBlockId
                            == nil,
                    "menus nil",
                    "card=\(ed.cardMenuBlockId ?? "-")"
                    + " block="
                    + (ed.blockMenuBlockId ?? "-")))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }
}

// ── U5 场景群：首页/设置/图片页回路 ──
// 注册面与手指同体口径逐面注于各注册点
// （MomentApp / MomentBridgeSettings）；场景
// 只组合注册面动作与状态读 + 模型直读，不新
// 造业务路径。行面（home.row）以 instance =
// memo.id 注册，ctx.state 只寻 "-"，故行面读
// 写经注册表直达（image.item 先例同）。

enum UITestHomeSurfaces {

    static func rowEntry(
        _ id: String) -> UITestSurfaceEntry? {
        UITestRegistry.shared.entry(
            id: "home.row", instance: id)
    }

    static func rowState(
        _ id: String, _ key: String) -> String? {
        rowEntry(id)?.state[key]?()
    }

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestShared.a(name, pass, expected, actual)
    }
}

// ── home_search_cycle（HOM-03/04 + HOM-18）──

enum UITestScenarioHomeSearch {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestHomeSurfaces.a(
            name, pass, expected, actual)
    }

    static func steps() -> [UITestStep] {
        [
            focusAndSearchStep(),
            submitExitStep(),
            // HOM-18 段：改题回首页查新鲜度
            // （共享三步 + 本景断言步）。
            UITestShared.openStep(),
            UITestShared.setLongTruncatedStep(),
            UITestShared.closeStep(),
            freshnessAssertStep(),
            blurExitStep(),
        ]
    }

    /// 展开 → 输入 → 命中集回读（HOM-03 前段）。
    static func focusAndSearchStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "focus + query + hits") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let home = ctx.surface(
                "home.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "home.view"
                done(out)
                return
            }
            ctx.store["totalBefore"] =
                ctx.state("home.view",
                          "totalCount")
            home.actions["focusSearch"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view",
                          "searchFocused") == "true"
            } done: { ok in
                out.assertions.append(a(
                    "capsule_expanded", ok,
                    "searchFocused=true",
                    ctx.state("home.view",
                        "searchFocused") ?? "none"))
                home.setText?(ctx.shortTitle)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("home.view",
                              "hitsActive") == "true"
                        && ctx.state("home.view",
                            "hitsCount") == "1"
                } done: { ok2 in
                    out.assertions.append(a(
                        "hits_exact_fixture", ok2,
                        "hits=1 (fixture only)",
                        "hits="
                        + (ctx.state("home.view",
                            "hitsCount") ?? "none")))
                    // 等发布（fix_home_row_
                    // registry）：命中集是模型级
                    // 同步量、行注册经呈现行集对
                    // 账随后一趟到达——旧式同步
                    // 直读把发布时间差记成行缺
                    // 失（0.9.64 二遍止步于此），
                    // 改与其余步同式 poll 等行面
                    // 标题落定再断言。
                    ctx.poll(timeoutMs: 5000) {
                        UITestHomeSurfaces
                            .rowState(ctx.fixtureId,
                                      "title")
                            == ctx.shortTitle
                    } done: { ok3 in
                        out.assertions.append(a(
                            "fixture_row_present",
                            ok3,
                            ctx.shortTitle,
                            UITestHomeSurfaces
                                .rowState(
                                    ctx.fixtureId,
                                    "title")
                                ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            }
        }
    }

    /// 回车收键盘 → 胶囊回缩、命中保留
    /// （HOM-03 后段：用户实报障的正形）。
    static func submitExitStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "submit: capsule retracts, "
                + "hits stay") { ctx, done in
            var out = UITestStepOutcome()
            guard let home = ctx.surface(
                "home.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "home.view"
                done(out)
                return
            }
            home.actions["submitSearch"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view",
                          "searchFocused") == "false"
            } done: { ok in
                out.assertions.append(a(
                    "capsule_retracted", ok,
                    "searchFocused=false",
                    ctx.state("home.view",
                        "searchFocused") ?? "none"))
                out.assertions.append(a(
                    "hits_retained",
                    ctx.state("home.view",
                              "hitsActive") == "true"
                        && ctx.state("home.view",
                            "hitsCount") == "1",
                    "hits=1",
                    "hits="
                    + (ctx.state("home.view",
                        "hitsCount") ?? "none")))
                let closed = ctx.windowEntries()
                    .contains {
                        $0.text.contains(
                            "APP search capsule "
                            + "close src=submit")
                    }
                out.assertions.append(a(
                    "close_src_submit", closed,
                    "close src=submit x1",
                    closed ? "found" : "none"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// HOM-18 扩展断言（前置 = steps() 中的共
    /// 享三步：开篇 → 置长标题截断态 → 关篇）：
    /// 返回首页（查询仍在）→ 命中集应即时重
    /// 算、夹具不再命中。若红即该缺陷的运行级
    /// 证据（searchHits 不随编辑返回重算）。
    static func freshnessAssertStep() -> UITestStep {
        UITestStep(
            kind: "assert",
            label: "hits recomputed after "
                + "edit return") { ctx, done in
            var out = UITestStepOutcome()
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view",
                          "hitsCount") == "0"
                    && UITestHomeSurfaces
                        .rowEntry(ctx.fixtureId)
                        == nil
            } done: { ok in
                out.assertions.append(a(
                    "hits_fresh_after_edit", ok,
                    "hits=0, fixture row gone",
                    "hits="
                    + (ctx.state("home.view",
                        "hitsCount") ?? "none")
                    + " row="
                    + (UITestHomeSurfaces
                        .rowEntry(ctx.fixtureId)
                        != nil
                        ? "present" : "gone")))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 辞焦退出（HOM-04 一路）：聚焦 → 设无命
    /// 中查询 → 辞焦 → 状态一致；收尾清查询。
    static func blurExitStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "blur exit + clear query") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let home = ctx.surface(
                "home.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "home.view"
                done(out)
                return
            }
            home.actions["focusSearch"]?(nil)
            home.setText?("自检无命中zz")
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view",
                          "hitsCount") == "0"
                    && ctx.state("home.view",
                        "emptyShown") == "true"
            } done: { ok in
                out.assertions.append(a(
                    "no_hit_empty_shown", ok,
                    "hits=0 emptyShown=true",
                    "hits="
                    + (ctx.state("home.view",
                        "hitsCount") ?? "none")))
                home.actions["blurSearch"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("home.view",
                        "searchFocused") == "false"
                } done: { ok2 in
                    out.assertions.append(a(
                        "blur_retracts", ok2,
                        "searchFocused=false",
                        ctx.state("home.view",
                            "searchFocused")
                            ?? "none"))
                    home.setText?("")
                    ctx.poll(timeoutMs: 5000) {
                        ctx.state("home.view",
                            "hitsActive") == "false"
                    } done: { ok3 in
                        out.assertions.append(a(
                            "query_cleared", ok3,
                            "hitsActive=false",
                            ctx.state("home.view",
                                "hitsActive")
                                ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        done(out)
                    }
                }
            }
        }
    }
}

// ── home_surface_roundtrip（HOM-01/02/13/14）──

enum UITestScenarioHomeSurface {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestHomeSurfaces.a(
            name, pass, expected, actual)
    }

    static func steps() -> [UITestStep] {
        [
            surfaceStateStep(),
            openRowStep(),
            UITestShared.closeStep(),
            avatarRouteStep(),
        ]
    }

    /// 头像在位 + 紧凑派生一致性（状态读两轮
    /// 一致由 poll 连续成立近似）。
    static func surfaceStateStep() -> UITestStep {
        UITestStep(
            kind: "assert",
            label: "avatar + compact derivation") {
            ctx, done in
            var out = UITestStepOutcome()
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("home.view") != nil
            } done: { _ in
                // 景自密封（fix_home_row_
                // registry）：导航态不跨 run
                // 继承——前序运行/用户手点可
                // 能把 dest 留在 settings，旧
                // 式只断言 dest 空、二遍开局
                // 即红（0.9.64 实跑）。断言
                // 前先经 home.view closeDest
                // 同体动作收 dest 并 poll 落
                // 定，本景只对密封后的状态
                // 负责；dest_home 断言保留为
                // 密封结果的验收读。
                if ctx.state("home.view", "dest")
                    != "" {
                    ctx.surface("home.view")?
                        .actions["closeDest"]?(nil)
                }
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("home.view", "dest")
                        == ""
                } done: { _ in
                out.assertions.append(a(
                    "avatar_shown",
                    ctx.state("home.view",
                              "avatarShown")
                        == "true",
                    "true",
                    ctx.state("home.view",
                        "avatarShown") ?? "none"))
                let off = Double(ctx.state(
                    "home.view", "scrollOffset")
                    ?? "") ?? -1
                let p = Double(ctx.state(
                    "home.view", "compactP")
                    ?? "") ?? -2
                let expect = Double(
                    HomeHeaderMath.compactP(
                        forOffset: CGFloat(off)))
                out.assertions.append(a(
                    "compact_derivation",
                    off >= 0
                        && abs(p - expect) <= 0.001,
                    "compactP == math(offset)",
                    "offset=\(off) p=\(p) "
                    + "expect=\(expect)"))
                out.assertions.append(a(
                    "dest_home",
                    ctx.state("home.view", "dest")
                        == "",
                    "dest empty",
                    ctx.state("home.view", "dest")
                        ?? "none"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
                }
            }
        }
    }

    /// 行点开 → 编辑器在席（HOM-13，经行面
    /// open 同体）；关篇步由共享 closeStep 承。
    static func openRowStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "row open -> seated") {
            ctx, done in
            var out = UITestStepOutcome()
            ctx.poll(timeoutMs: 5000) {
                UITestHomeSurfaces.rowEntry(
                    ctx.fixtureId) != nil
            } done: { ok in
                guard ok, let row =
                    UITestHomeSurfaces.rowEntry(
                        ctx.fixtureId) else {
                    out.ok = false
                    out.note = "fixture row "
                        + "missing"
                    done(out)
                    return
                }
                row.actions["open"]?(nil)
                ctx.poll(timeoutMs: 8000) {
                    EditorSeatRegistry.shared
                        .currentMemoId
                        == ctx.fixtureId
                } done: { ok2 in
                    ctx.expectSeat = ok2
                    out.assertions.append(a(
                        "seated_via_row", ok2,
                        "seat=\(ctx.fixtureId)",
                        EditorSeatRegistry.shared
                            .currentMemoId
                            ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 头像点按入口（HOM-01 动作腿）：同体进
    /// 设置 → 设置根面在位 → 返回。
    static func avatarRouteStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "avatar -> settings -> back") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let home = ctx.surface(
                "home.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "home.view"
                done(out)
                return
            }
            home.actions["tapAvatar"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view", "dest")
                    == "settings"
                    && ctx.surface(
                        "settings.view") != nil
            } done: { ok in
                out.assertions.append(a(
                    "settings_reached", ok,
                    "dest=settings + surface",
                    "dest="
                    + (ctx.state("home.view",
                        "dest") ?? "none")))
                home.actions["closeDest"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("home.view", "dest")
                        == ""
                } done: { ok2 in
                    out.assertions.append(a(
                        "back_home", ok2,
                        "dest empty",
                        ctx.state("home.view",
                            "dest") ?? "none"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }
}

// ── home_list_actions（HOM-07/09/10 + HOM-17）──

enum UITestScenarioHomeActions {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestHomeSurfaces.a(
            name, pass, expected, actual)
    }

    static func steps() -> [UITestStep] {
        [
            coverStep(),
            pinStep(),
            deleteUndoStep(),
        ]
    }

    /// 封面派生呈现（HOM-07）：图文行在位 +
    /// 封面 = 文档序首图（gallery 首项 fid）+
    /// 行卡圆角令牌回读（HOM-17，列表形态）。
    static func coverStep() -> UITestStep {
        UITestStep(
            kind: "assert",
            label: "cover derivation + radius") {
            ctx, done in
            var out = UITestStepOutcome()
            ctx.poll(timeoutMs: 5000) {
                UITestHomeSurfaces.rowEntry(
                    ctx.fixtureId) != nil
            } done: { _ in
                let fid = UITestHomeSurfaces
                    .rowState(ctx.fixtureId,
                              "coverFileId")
                out.assertions.append(a(
                    "cover_is_first_image",
                    UITestHomeSurfaces.rowState(
                        ctx.fixtureId, "isImage")
                        == "true"
                        && fid
                            == UITestFixtureTemplate
                                .mediaFids.first,
                    "isImage + cover="
                    + (UITestFixtureTemplate
                        .mediaFids.first ?? ""),
                    "isImage="
                    + (UITestHomeSurfaces
                        .rowState(ctx.fixtureId,
                            "isImage") ?? "none")
                    + " cover=" + (fid ?? "none")))
                let form = UITestHomeSurfaces
                    .rowState(ctx.fixtureId, "form")
                if form == "list" {
                    out.assertions.append(a(
                        "row_radius_token",
                        UITestHomeSurfaces
                            .rowState(ctx.fixtureId,
                                "radius")
                            == "\(Radius.cardL)",
                        "\(Radius.cardL)",
                        UITestHomeSurfaces
                            .rowState(ctx.fixtureId,
                                "radius") ?? "none"))
                } else {
                    out.assertions.append(a(
                        "row_radius_token", true,
                        "grid form: skipped",
                        "form=\(form ?? "none")"))
                }
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 置顶同体（HOM-09）：行面 pin 与左滑菜
    /// 单同一 togglePin；两回切换、模型回读。
    static func pinStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "pin toggle roundtrip") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let row = UITestHomeSurfaces
                .rowEntry(ctx.fixtureId) else {
                out.ok = false
                out.note = "fixture row missing"
                done(out)
                return
            }
            func pinnedModel() -> Bool {
                ctx.library.memos.first {
                    $0.id == ctx.fixtureId
                }?.pinned ?? false
            }
            let before = pinnedModel()
            row.actions["pin"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                pinnedModel() == !before
            } done: { ok in
                out.assertions.append(a(
                    "pin_flips", ok,
                    "pinned=\(!before)",
                    "pinned=\(pinnedModel())"))
                row.actions["pin"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    pinnedModel() == before
                } done: { ok2 in
                    out.assertions.append(a(
                        "pin_restores", ok2,
                        "pinned=\(before)",
                        "pinned=\(pinnedModel())"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 删除撤销链（HOM-10 UI 腿）：行面 delete
    /// （softRemove 同体）→ 撤销条在位（待删
    /// id）→ home.view undoDelete（Library
    /// .undoDeletion 同体）→ 行与模型恢复。
    static func deleteUndoStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "delete -> undo toast -> "
                + "restore") { ctx, done in
            var out = UITestStepOutcome()
            guard let row = UITestHomeSurfaces
                    .rowEntry(ctx.fixtureId),
                  let home = ctx.surface(
                    "home.view") else {
                out.ok = false
                out.note = "row/home missing"
                done(out)
                return
            }
            row.actions["delete"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view",
                          "pendingDeletionId")
                    == ctx.fixtureId
                    && UITestHomeSurfaces
                        .rowEntry(ctx.fixtureId)
                        == nil
            } done: { ok in
                out.assertions.append(a(
                    "pending_toast_state", ok,
                    "pendingDeletionId=fixture, "
                    + "row gone",
                    "pending="
                    + (ctx.state("home.view",
                        "pendingDeletionId")
                        ?? "none")))
                home.actions["undoDelete"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("home.view",
                              "pendingDeletionId")
                        == ""
                        && UITestHomeSurfaces
                            .rowEntry(ctx.fixtureId)
                            != nil
                        && ctx.library.memos
                            .contains {
                                $0.id
                                    == ctx.fixtureId
                            }
                } done: { ok2 in
                    out.assertions.append(a(
                        "undo_restores", ok2,
                        "row + memo back",
                        "pending="
                        + (ctx.state("home.view",
                            "pendingDeletionId")
                            ?? "none")))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }
}

// ── image_page_open（IMG-01/02/03/06）──

enum UITestScenarioImagePage {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestHomeSurfaces.a(
            name, pass, expected, actual)
    }

    static func steps() -> [UITestStep] {
        [
            UITestShared.openStep(),
            openFromGalleryStep(),
            titleGeometryStep(),
            closeBackStep(),
            UITestShared.closeStep(),
        ]
    }

    /// gallery 首项入口：与瓦面点按同一
    /// imageTarget 赋值（瓦面无注册动作，赋
    /// 值体即点按体，见 grades 注）。
    static func openFromGalleryStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "gallery item -> image page") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let ed = UITestShared
                    .seatedEditor(ctx),
                  let g = ed.blocks.first(where: {
                      $0.type == "gallery"
                  }),
                  let attrs = g.node["attrs"]
                    as? [String: Any],
                  let items = attrs["items"]
                    as? [[String: Any]],
                  let first = items.first else {
                out.ok = false
                out.note = "gallery fixture "
                    + "missing"
                done(out)
                return
            }
            let fid = first["fileId"] as? String
            ctx.store["imgFid"] = fid ?? ""
            ed.imageTarget = ImageTarget(
                fileId: fid,
                urlString: (first["url"]
                    as? String)
                    ?? (first["src"] as? String),
                name: (first["name"] as? String)
                    ?? Lang.t("imgpage.untitled"))
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("image.view") != nil
            } done: { ok in
                out.assertions.append(a(
                    "image_page_present", ok,
                    "image.view registered",
                    ok ? "present" : "missing"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 标题（IMG-02：清单名优先 + 超 12 字呈
    /// 现截断）与适配几何（IMG-03：contain 关
    /// 系式——fit ⊆ 可用区、小图不放大）。
    static func titleGeometryStep() -> UITestStep {
        UITestStep(
            kind: "assert",
            label: "title + contain fit") {
            ctx, done in
            var out = UITestStepOutcome()
            ctx.poll(timeoutMs: 8000) {
                ctx.state("image.view",
                          "hasImage") == "true"
            } done: { ok in
                let name = ctx.state(
                    "image.view", "name") ?? ""
                let fid = ctx.store["imgFid"]
                    as? String ?? ""
                out.assertions.append(a(
                    "image_loaded", ok,
                    "hasImage=true",
                    ctx.state("image.view",
                        "hasImage") ?? "none"))
                out.assertions.append(a(
                    "title_is_manifest_name",
                    name == fid + ".png",
                    fid + ".png", name))
                let expectTitle =
                    name.count > 12
                    ? String(name.prefix(12)) + "…"
                    : name
                out.assertions.append(a(
                    "title_present_trunc12",
                    ctx.state("image.view",
                              "title")
                        == expectTitle,
                    expectTitle,
                    ctx.state("image.view",
                        "title") ?? "none"))
                let natW = Double(ctx.state(
                    "image.view", "natW") ?? "")
                    ?? 0
                let natH = Double(ctx.state(
                    "image.view", "natH") ?? "")
                    ?? 0
                let fitW = Double(ctx.state(
                    "image.view", "fitW") ?? "")
                    ?? -1
                let fitH = Double(ctx.state(
                    "image.view", "fitH") ?? "")
                    ?? -1
                let availW = Double(ctx.state(
                    "image.view", "availW") ?? "")
                    ?? 0
                let availH = Double(ctx.state(
                    "image.view", "availH") ?? "")
                    ?? 0
                out.assertions.append(a(
                    "contain_fit",
                    fitW >= 0
                        && fitW <= availW + 0.5
                        && fitH <= availH + 0.5
                        && fitW <= natW + 0.5
                        && fitH <= natH + 0.5,
                    "fit ⊆ avail, fit ≤ nat",
                    "fit=\(fitW)x\(fitH) "
                    + "avail=\(availW)x\(availH) "
                    + "nat=\(natW)x\(natH)"))
                // 夹具图 8x8 小图：不放大 → fit
                // == nat（scale 钳 1 的正形）。
                out.assertions.append(a(
                    "small_image_not_upscaled",
                    abs(fitW - natW) <= 0.5
                        && abs(fitH - natH) <= 0.5,
                    "fit == nat (8x8)",
                    "fit=\(fitW)x\(fitH) "
                    + "nat=\(natW)x\(natH)"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 返回（IMG-06 状态腿）：关页后编辑器仍
    /// 在席、状态未清（恢复深度归人工）。
    static func closeBackStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "close -> editor intact") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let page = ctx.surface(
                "image.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "image.view"
                done(out)
                return
            }
            page.actions["close"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("image.view") == nil
            } done: { ok in
                out.assertions.append(a(
                    "page_closed", ok,
                    "image.view gone",
                    ok ? "gone" : "present"))
                out.assertions.append(a(
                    "editor_state_intact",
                    EditorSeatRegistry.shared
                        .currentMemoId
                        == ctx.fixtureId
                        && ctx.state(
                            "editor.view", "memoId")
                            == ctx.fixtureId,
                    "seat + memoId = fixture",
                    "seat="
                    + (EditorSeatRegistry.shared
                        .currentMemoId ?? "none")))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }
}

// ── settings_surface_roundtrip（SET 群 + GLB-04）──

enum UITestScenarioSettings {

    static func a(
        _ name: String, _ pass: Bool,
        _ expected: String, _ actual: String
    ) -> UITestAssertion {
        UITestHomeSurfaces.a(
            name, pass, expected, actual)
    }

    static func steps() -> [UITestStep] {
        [
            enterStructureStep(),
            weatherStep(),
            diagStep(),
            bridgeStep(),
            languageStep(),
            backupGesturesDtStep(),
            exitStep(),
        ]
    }

    /// 进设置（头像同体）+ 分组结构（SET-01）。
    static func enterStructureStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "enter settings + sections") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let home = ctx.surface(
                "home.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "home.view"
                done(out)
                return
            }
            home.actions["tapAvatar"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("settings.view")
                    != nil
                    && ctx.state("settings.view",
                                 "route") == ""
            } done: { ok in
                out.assertions.append(a(
                    "settings_root", ok,
                    "settings.view at root",
                    "route="
                    + (ctx.state("settings.view",
                        "route") ?? "none")))
                out.assertions.append(a(
                    "sections_present",
                    ctx.state("settings.view",
                              "sections")
                        == "appearance,data,"
                        + "weather,about",
                    "4 sections",
                    ctx.state("settings.view",
                        "sections") ?? "none"))
                out.assertions.append(a(
                    "version_readable",
                    !(ctx.state("settings.view",
                        "version") ?? "").isEmpty,
                    "non-empty",
                    ctx.state("settings.view",
                        "version") ?? "none"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
    }

    /// 天气 UI 路径（SET-03/04）：两槽来源读；
    /// 自填腿只在 qweather 无用户自填 key 时
    /// 跑（有则跳过写入段——不毁用户 key）：
    /// setText 假 key → custom → clear → 回
    /// 初始来源。
    static func weatherStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "weather fields roundtrip") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let settings = ctx.surface(
                "settings.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "settings.view"
                done(out)
                return
            }
            settings.actions["openWeather"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("settings.view",
                          "route") == "weather"
                    && UITestRegistry.shared
                        .entry(
                            id: "settings.weather",
                            instance: "qweather")
                        != nil
            } done: { ok in
                out.assertions.append(a(
                    "weather_page", ok,
                    "route=weather + fields",
                    "route="
                    + (ctx.state("settings.view",
                        "route") ?? "none")))
                func wstate(
                    _ inst: String, _ key: String
                ) -> String? {
                    UITestRegistry.shared.entry(
                        id: "settings.weather",
                        instance: inst)?
                        .state[key]?()
                }
                let qw0 = wstate(
                    "qweather", "source") ?? ""
                let cy0 = wstate(
                    "caiyun", "source") ?? ""
                out.assertions.append(a(
                    "sources_readable",
                    !qw0.isEmpty && !cy0.isEmpty,
                    "both sources non-empty",
                    "qw=\(qw0) cy=\(cy0)"))
                func closeRoute(
                    _ finish: @escaping () -> Void
                ) {
                    settings.actions[
                        "closeRoute"]?(nil)
                    ctx.poll(timeoutMs: 5000) {
                        ctx.state("settings.view",
                                  "route") == ""
                    } done: { _ in finish() }
                }
                guard qw0 != "custom",
                      let field = UITestRegistry
                        .shared.entry(
                            id: "settings.weather",
                            instance: "qweather")
                else {
                    out.assertions.append(a(
                        "custom_key_leg",
                        true,
                        "skipped: user custom "
                        + "key present",
                        "source=\(qw0)"))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    closeRoute { done(out) }
                    return
                }
                field.setText?(
                    "uitestdummykey0000000000000000")
                ctx.poll(timeoutMs: 5000) {
                    wstate("qweather",
                           "hasCustom") == "true"
                } done: { ok2 in
                    out.assertions.append(a(
                        "set_custom_via_ui", ok2,
                        "hasCustom=true",
                        wstate("qweather",
                            "hasCustom") ?? "none"))
                    field.actions["clear"]?(nil)
                    ctx.poll(timeoutMs: 5000) {
                        wstate("qweather",
                               "source") == qw0
                    } done: { ok3 in
                        out.assertions.append(a(
                            "clear_restores_source",
                            ok3,
                            "source=\(qw0)",
                            wstate("qweather",
                                "source")
                                ?? "none"))
                        out.ok = out.assertions
                            .allSatisfy { $0.pass }
                        closeRoute { done(out) }
                    }
                }
            }
        }
    }

    /// 诊断页（SET-05 UI 腿 + SET-11 状态腿）
    /// 与日志页抽样（SET-12）。
    static func diagStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "diag autodel + log page") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let settings = ctx.surface(
                "settings.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "settings.view"
                done(out)
                return
            }
            settings.actions["openDiag"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("settings.diag")
                    != nil
            } done: { ok in
                guard ok, let diag = ctx.surface(
                    "settings.diag") else {
                    out.ok = false
                    out.note = "diag page missing"
                    done(out)
                    return
                }
                let before = ctx.state(
                    "settings.diag", "autodel")
                    ?? ""
                out.assertions.append(a(
                    "diag_list_present",
                    (Int(ctx.state(
                        "settings.diag",
                        "todayCount") ?? "") ?? 0)
                        > 0,
                    "todayCount>0",
                    ctx.state("settings.diag",
                        "todayCount") ?? "none"))
                diag.actions["toggleAutodel"]?(
                    before == "true" ? 0 : 1)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("settings.diag",
                              "autodel")
                        == (before == "true"
                            ? "false" : "true")
                } done: { ok2 in
                    out.assertions.append(a(
                        "autodel_flips_via_ui", ok2,
                        "autodel != \(before)",
                        ctx.state("settings.diag",
                            "autodel") ?? "none"))
                    diag.actions["toggleAutodel"]?(
                        before == "true" ? 1 : 0)
                    ctx.poll(timeoutMs: 5000) {
                        ctx.state("settings.diag",
                                  "autodel")
                            == before
                    } done: { ok3 in
                        out.assertions.append(a(
                            "autodel_restored", ok3,
                            "autodel=\(before)",
                            ctx.state(
                                "settings.diag",
                                "autodel") ?? "none"))
                        diag.actions[
                            "openToday"]?(nil)
                        ctx.poll(
                            timeoutMs: 5000) {
                            ctx.state(
                                "settings.diag",
                                "route") == "today"
                                && ctx.surface(
                                    "settings.diaglog")
                                    != nil
                        } done: { ok4 in
                            out.assertions.append(a(
                                "log_page_present",
                                ok4,
                                "route=today + "
                                + "diaglog surface",
                                "route="
                                + (ctx.state(
                                    "settings.diag",
                                    "route")
                                    ?? "none")
                                + " lines="
                                + (ctx.state(
                                    "settings.diaglog",
                                    "lines")
                                    ?? "none")))
                            diag.actions[
                                "closeRoute"]?(nil)
                            settings.actions[
                                "closeRoute"]?(nil)
                            ctx.poll(
                                timeoutMs: 5000) {
                                ctx.state(
                                    "settings.view",
                                    "route") == ""
                            } done: { _ in
                                out.ok = out
                                    .assertions
                                    .allSatisfy {
                                        $0.pass
                                    }
                                done(out)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 桥区结构读（SET-06 抽样）。
    static func bridgeStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "bridge section read") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let settings = ctx.surface(
                "settings.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "settings.view"
                done(out)
                return
            }
            settings.actions["openBridge"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("settings.bridge")
                    != nil
            } done: { ok in
                out.assertions.append(a(
                    "bridge_page_present", ok,
                    "settings.bridge registered",
                    ok ? "present" : "missing"))
                out.assertions.append(a(
                    "bridge_state_readable",
                    ctx.state("settings.bridge",
                              "linkState") != nil
                        && ctx.state(
                            "settings.bridge",
                            "scopes") != nil,
                    "linkState + scopes keys",
                    "link="
                    + (ctx.state(
                        "settings.bridge",
                        "linkState") ?? "none")
                    + " scopes="
                    + (ctx.state(
                        "settings.bridge",
                        "scopes") ?? "none")))
                settings.actions[
                    "closeRoute"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("settings.view",
                              "route") == ""
                } done: { _ in
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 语言呈现腿（SET-09 UI 腿）：行本体即
    /// LangStore.apply —— 景内直调同体，切后
    /// 设置根面 lang 状态与文案查表同变，随
    /// 即按原态（跟随系统/固定）恢复。
    static func languageStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "language presentation leg") {
            ctx, done in
            var out = UITestStepOutcome()
            guard let settings = ctx.surface(
                "settings.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "settings.view"
                done(out)
                return
            }
            settings.actions["openLanguage"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("settings.view",
                          "route") == "language"
            } done: { ok in
                out.assertions.append(a(
                    "language_page", ok,
                    "route=language",
                    ctx.state("settings.view",
                        "route") ?? "none"))
                let store = LangStore.shared
                let origCode = store.code
                let origFollow = store.followSystem
                let origTitle = Lang.t(
                    "settings.title")
                let target = origCode == "en-US"
                    ? "zh-CN" : "en-US"
                store.apply(target)
                ctx.poll(timeoutMs: 5000) {
                    ctx.state("settings.view",
                              "lang") == target
                        && Lang.t("settings.title")
                            != origTitle
                } done: { ok2 in
                    out.assertions.append(a(
                        "lang_switch_renders", ok2,
                        "lang=\(target), title "
                        + "changed",
                        "lang="
                        + (ctx.state(
                            "settings.view",
                            "lang") ?? "none")
                        + " title="
                        + Lang.t(
                            "settings.title")))
                    if origFollow {
                        store.applyFollowSystem()
                    } else {
                        store.apply(origCode)
                    }
                    ctx.poll(timeoutMs: 5000) {
                        ctx.state("settings.view",
                                  "lang")
                            == origCode
                    } done: { ok3 in
                        out.assertions.append(a(
                            "lang_restored", ok3,
                            "lang=\(origCode)",
                            ctx.state(
                                "settings.view",
                                "lang") ?? "none"))
                        settings.actions[
                            "closeRoute"]?(nil)
                        ctx.poll(
                            timeoutMs: 5000) {
                            ctx.state(
                                "settings.view",
                                "route") == ""
                        } done: { _ in
                            out.ok = out.assertions
                                .allSatisfy {
                                    $0.pass
                                }
                            done(out)
                        }
                    }
                }
            }
        }
    }

    /// 备份状态腿（SET-07）+ 手势页抽样
    /// （SET-10）+ DT 现档抽样（GLB-04）。
    static func backupGesturesDtStep()
        -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "backup leg + gestures + DT "
                + "sampling") { ctx, done in
            var out = UITestStepOutcome()
            guard let settings = ctx.surface(
                "settings.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "settings.view"
                done(out)
                return
            }
            settings.actions["openBackup"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.surface("settings.backup")
                    != nil
            } done: { ok in
                out.assertions.append(a(
                    "backup_page_leg", ok,
                    "settings.backup registered",
                    "memoCount="
                    + (ctx.state(
                        "settings.backup",
                        "memoCount") ?? "none")
                    + " lastExportTs="
                    + (ctx.state(
                        "settings.backup",
                        "lastExportTs")
                        ?? "none")))
                settings.actions[
                    "closeRoute"]?(nil)
                settings.actions[
                    "openGestures"]?(nil)
                ctx.poll(timeoutMs: 5000) {
                    (Int(ctx.state(
                        "settings.gestures",
                        "rows") ?? "") ?? 0) > 0
                } done: { ok2 in
                    out.assertions.append(a(
                        "gestures_rows", ok2,
                        "rows>0",
                        ctx.state(
                            "settings.gestures",
                            "rows") ?? "none"))
                    settings.actions[
                        "closeRoute"]?(nil)
                    // GLB-04 现档抽样：类目可
                    // 读 + 设置面在该档下仍可
                    // 达（帧关系深断言归真机
                    // 大档抽样，见 grades）。
                    let cat = UITraitCollection
                        .current
                        .preferredContentSizeCategory
                    out.assertions.append(a(
                        "dt_category_sampling",
                        !cat.rawValue.isEmpty
                            && ctx.surface(
                                "settings.view")
                                != nil,
                        "category readable",
                        cat.rawValue))
                    out.ok = out.assertions
                        .allSatisfy { $0.pass }
                    done(out)
                }
            }
        }
    }

    /// 退出设置回首页。
    static func exitStep() -> UITestStep {
        UITestStep(
            kind: "invoke",
            label: "exit settings") { ctx, done in
            var out = UITestStepOutcome()
            guard let home = ctx.surface(
                "home.view") else {
                out.ok = false
                out.note = "surface_missing: "
                    + "home.view"
                done(out)
                return
            }
            home.actions["closeDest"]?(nil)
            ctx.poll(timeoutMs: 5000) {
                ctx.state("home.view", "dest")
                    == ""
            } done: { ok in
                out.assertions.append(a(
                    "back_home", ok,
                    "dest empty",
                    ctx.state("home.view",
                        "dest") ?? "none"))
                out.ok = out.assertions
                    .allSatisfy { $0.pass }
                done(out)
            }
        }
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

    /// 量测探针（U2 落地，矩阵 §6.1/§6.4）：
    /// id 校验后委托 UITestProbes（六件，几何
    /// 前提账在其头注）；未知 id 仍回
    /// invalid_params 并列出已装 id。
    static func measure(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let probe = args["probe"] as? String,
              !probe.isEmpty else {
            return .failure(.invalidParams(
                "probe required"))
        }
        guard UITestProbes.ids.contains(probe)
        else {
            return .failure(.invalidParams(
                "unknown probe: \(probe); "
                + "registered: "
                + UITestProbes.ids.joined(
                    separator: ",")))
        }
        let sub = args["args"] as? [String: Any]
            ?? [:]
        return UITestProbes.run(probe, args: sub)
    }
}
