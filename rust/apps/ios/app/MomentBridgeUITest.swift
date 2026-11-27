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

final class UITestDriver {
    static let shared = UITestDriver()

    private var jobs: [String: UITestJob] = [:]
    private var jobOrder: [String] = []
    private var activeRunId: String?

    var isBusy: Bool { activeRunId != nil }

    func job(_ runId: String) -> UITestJob? {
        jobs[runId]
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
        guard scenario == "title_capsule_reedit"
        else {
            return .failure(.invalidParams(
                "unknown scenario: \(scenario) "
                + "(registered: "
                + "title_capsule_reedit)"))
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
        job.grades = [
            "stateMachine": "proven",
            "persistence": "proven",
            "hitDelivery": "unknown",
            "keyboard": "unknown",
            "note": "S1 证标题胶囊二次编辑的状态"
                + "机回路与落盘回读（handler 以"
                + "内）；手指点按能否到达入口、键"
                + "盘呈现与光标落点不在证据面，仍"
                + "以真机点按 + Diag 成对行终判。",
        ]
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
        setup(job: job, library: library)
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
                       library: Library) {
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
            runSteps(job: job, ctx: ctx,
                     steps: UITestScenarioS1.steps(),
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
