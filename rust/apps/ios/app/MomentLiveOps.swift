import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// Live Activity 操作期保活封装（权限/实况批，定案
// impl_ios_entitlements_liveops.md §五）：长操作（场景
// 运行 / 桥长操作 / 导出导入）的可见存在感 + 一键回
// 前台 + 切后台数十秒宽限。实况不是进程永生手段：
// 挂起期不可达是平台事实，本文件不扩张稳定性批的
// 保证域（§六诚实口径）。
//
// 桥会话实况（impl_bridge_live_keepalive 扩）：同一
// 封装同栈再承一种会话级形态（kind=bridge）——桥连
// 通期间长驻、锁屏呈现连接态（文案由协调器以语言包
// 定格、与设置页同源、如实反映状态机）。它只做三件
// 真事：短暂切后台时以在位实况申得后台宽限窗护在飞
// 作业收口、状态在锁屏可见、回前台刷新即收敛；不改
// 变连通语义、不延长挂起后的套接字寿命。
//
// 节制口径（§5.5）：步进更新最小间隔 5s、间隔内只留
// 最新一帧；终态与 phase 翻转不节流；staleDate =
// start +10min；成功 15s 消退、失败留 10min。
// Diag 五式：OPS live start/update/end/skip/grace。

enum LiveOpResult {
    case ok, failed, aborted
    var diagWord: String {
        switch self {
        case .ok: return "ok"
        case .failed: return "failed"
        case .aborted: return "aborted"
        }
    }
    var phase: LiveOpPhase {
        switch self {
        case .ok: return .done
        case .failed, .aborted: return .failed
        }
    }
}

final class MomentLiveOps {
    static let shared = MomentLiveOps()

    static let processingTaskId = "com.canopies.moment.bg.processing"
    static let refreshTaskId = "com.canopies.moment.bg.refresh"

    private struct Session {
        var kind: LiveOpKind
        var title: String
        var lastSentAt: Date
        var lastSentState: (phase: LiveOpPhase, step: String,
                            done: Int, total: Int?)?
        var pending: (phase: LiveOpPhase, step: String,
                      done: Int, total: Int?)?
        var flushWork: DispatchWorkItem?
    }

    private var sessions: [String: Session] = [:]
    private var graceTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // ── 可用性 ──────────────────────────────────────

    private var activitiesEnabled: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo()
                .areActivitiesEnabled
        }
        #endif
        return false
    }

    private var osSupportsLive: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) { return true }
        #endif
        return false
    }

    // ── 起 / 更 / 止 ─────────────────────────────────

    /// 启动实况。返回 activityId（不可用时 nil 并记
    /// skip 行）。调用方只在长操作集成员资格下调用
    /// （短操作不启的判据在挂点侧，见各挂点注释）。
    @discardableResult
    func start(kind: LiveOpKind, title: String,
               step: String, total: Int?,
               detail: String = "") -> String? {
        guard osSupportsLive else {
            DiagLog.shared.log(.info,
                "OPS live skip reason=unsupported-os")
            return nil
        }
        guard activitiesEnabled else {
            DiagLog.shared.log(.info,
                "OPS live skip reason=disabled")
            return nil
        }
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            let attrs = OpsActivityAttributes(
                opKind: kind, opTitle: title,
                opDetail: detail)
            let state = OpsActivityAttributes.ContentState(
                phase: .running, stepLabel: step, done: 0,
                total: total, updatedAt: Date())
            do {
                // ActivityContent 是 16.2+ API；16.1 走
                // contentState 旧式（编译实证纠 A 段
                // 「16.1 起」的版本口径）。
                let activity: Activity<OpsActivityAttributes>
                if #available(iOS 16.2, *) {
                    activity = try Activity.request(
                        attributes: attrs,
                        content: ActivityContent(
                            state: state,
                            staleDate: Date()
                                .addingTimeInterval(600)),
                        pushType: nil)
                } else {
                    activity = try Activity.request(
                        attributes: attrs,
                        contentState: state,
                        pushType: nil)
                }
                let id = activity.id
                sessions[id] = Session(
                    kind: kind, title: title,
                    lastSentAt: Date(),
                    lastSentState: (.running, step, 0, total),
                    pending: nil, flushWork: nil)
                DiagLog.shared.log(.info,
                    "OPS live start kind=\(kind.rawValue) "
                    + "id=\(String(id.prefix(8)))")
                return id
            } catch {
                DiagLog.shared.log(.warn,
                    "OPS live skip reason=request-failed")
                return nil
            }
        }
        #endif
        return nil
    }

    /// 步进更新（5s 节流合并；phase 翻转立即发）。
    func update(id: String?, step: String, done: Int,
                total: Int?, phase: LiveOpPhase = .running) {
        guard let id, var s = sessions[id] else { return }
        let frame = (phase: phase, step: step, done: done,
                     total: total)
        let phaseFlip = s.lastSentState != nil
            && s.lastSentState!.phase != phase
        if phaseFlip
            || Date().timeIntervalSince(s.lastSentAt) >= 5 {
            send(id: id, frame: frame)
        } else {
            s.pending = frame
            sessions[id] = s
            if s.flushWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.flushPending(id: id)
                }
                s.flushWork = work
                sessions[id] = s
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 5, execute: work)
            }
        }
    }

    private func flushPending(id: String) {
        guard var s = sessions[id] else { return }
        s.flushWork = nil
        sessions[id] = s
        if let p = s.pending {
            s.pending = nil
            sessions[id] = s
            send(id: id, frame: p)
        }
    }

    private func send(id: String,
                      frame: (phase: LiveOpPhase, step: String,
                              done: Int, total: Int?)) {
        guard var s = sessions[id] else { return }
        s.lastSentAt = Date()
        s.lastSentState = frame
        s.pending = nil
        sessions[id] = s
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            let state = OpsActivityAttributes.ContentState(
                phase: frame.phase, stepLabel: frame.step,
                done: frame.done, total: frame.total,
                updatedAt: Date())
            Task {
                for activity in Activity<
                    OpsActivityAttributes
                >.activities where activity.id == id {
                    if #available(iOS 16.2, *) {
                        await activity.update(
                            ActivityContent(
                                state: state,
                                staleDate: Date()
                                    .addingTimeInterval(600)))
                    } else {
                        await activity.update(using: state)
                    }
                }
            }
        }
        #endif
        DiagLog.shared.log(.info,
            "OPS live update id=\(String(id.prefix(8))) "
            + "step=\(frame.step) "
            + "done=\(frame.done)/"
            + (frame.total.map(String.init) ?? "-"))
    }

    /// 终态收口（不节流）：成功 15s 消退、失败留
    /// 10min（§5.5 结束策略）。linger 非空时覆盖
    /// 消退时长（桥会话收口用：终态短留即可，不按
    /// 操作失败的 10min 口径挂锁屏）。
    func end(id: String?, result: LiveOpResult,
             step: String,
             linger: TimeInterval? = nil) {
        guard let id, let s = sessions[id] else { return }
        s.flushWork?.cancel()
        sessions[id] = nil
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            let state = OpsActivityAttributes.ContentState(
                phase: result.phase, stepLabel: step,
                done: s.lastSentState?.done ?? 0,
                total: s.lastSentState?.total,
                updatedAt: Date())
            let dismissal: ActivityUIDismissalPolicy =
                linger.map {
                    .after(Date().addingTimeInterval($0))
                } ?? (result == .ok
                ? .after(Date().addingTimeInterval(15))
                : .after(Date().addingTimeInterval(600)))
            Task {
                for activity in Activity<
                    OpsActivityAttributes
                >.activities where activity.id == id {
                    if #available(iOS 16.2, *) {
                        await activity.end(
                            ActivityContent(
                                state: state, staleDate: nil),
                            dismissalPolicy: dismissal)
                    } else {
                        await activity.end(
                            using: state,
                            dismissalPolicy: dismissal)
                    }
                }
            }
        }
        #endif
        DiagLog.shared.log(.info,
            "OPS live end id=\(String(id.prefix(8))) "
            + "result=\(result.diagWord)")
    }

    // ── 桥会话实况（impl_bridge_live_keepalive）──
    //
    // 与操作类共用 sessions 栈与节流口径（步进 5s
    // 合并、phase 翻转立即发、staleDate +10min），
    // 不另起第二套实况栈。协调器在每次状态迁移与
    // 回前台时调 bridgeLiveSync 收敛：want 与在位
    // 状态不一致才动——起（含认领上个进程残留的
    // 一条）、刷新当前连接态、止（终态短留 15s）。
    // 实况被系统设置关闭/系统不支持时 start 返回
    // nil：本段静默无实况运行，桥功能零依赖于它
    // （降级口径，Diag 以 BRIDGE live unavailable
    // 与 OPS live skip 成对留痕）。
    // 桥会话同在 sessions 内，hasActive 恒含它：
    // 切后台时 appDidEnterBackground 的宽限组合
    // 自动覆盖桥会话——宽限窗（约 30s、系统给定）
    // 内进程未挂起、套接字存活，在飞调用与场景
    // journal 得以收口落盘；宽限过后照常挂起，
    // 本段不宣称宽限窗之外的任何存活。

    private var bridgeLiveId: String?

    var bridgeLiveActive: Bool { bridgeLiveId != nil }

    /// 收敛单点（协调器调用）：want = 桥开启 + 已
    /// 配对 + 未被 OPS 禁用 + 处于连接态族
    /// （connected / connecting / backoff）。
    /// step/stateWord/phase 均为调用方按当前状态机
    /// 定格的如实值，本段不加工不粉饰。
    func bridgeLiveSync(want: Bool, title: String,
                        detail: String, step: String,
                        stateWord: String,
                        phase: LiveOpPhase) {
        if want {
            if let id = bridgeLiveId,
               sessions[id] != nil {
                update(id: id, step: step, done: 0,
                       total: nil, phase: phase)
            } else if let adopted =
                        adoptBridgeActivity(
                            step: step, phase: phase) {
                bridgeLiveId = adopted
                DiagLog.shared.log(.info,
                    "BRIDGE live start adopted=1 "
                    + "fp=\(detail)")
            } else if let id = start(
                kind: .bridge, title: title, step: step,
                total: nil, detail: detail) {
                bridgeLiveId = id
                DiagLog.shared.log(.info,
                    "BRIDGE live start fp=\(detail)")
            } else {
                DiagLog.shared.log(.info,
                    "BRIDGE live unavailable")
            }
            sweepStaleBridgeActivities(
                step: step, keeping: bridgeLiveId)
        } else {
            let ended = bridgeLiveId
            if let id = ended {
                bridgeLiveId = nil
                end(id: id, result: .aborted, step: step,
                    linger: 15)
                DiagLog.shared.log(.info,
                    "BRIDGE live end state=\(stateWord)")
            }
            sweepStaleBridgeActivities(
                step: step, keeping: ended)
        }
    }

    /// 认领上个进程残留的桥实况（App 被杀时实况不
    /// 随进程消亡）：登记进 sessions 并立即刷新为
    /// 当前态，避免重复 request 出第二条。
    private func adoptBridgeActivity(
        step: String, phase: LiveOpPhase) -> String? {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            for activity in Activity<
                OpsActivityAttributes
            >.activities
            where activity.attributes.opKind == .bridge {
                let id = activity.id
                sessions[id] = Session(
                    kind: .bridge,
                    title: activity.attributes.opTitle,
                    lastSentAt: .distantPast,
                    lastSentState: nil, pending: nil,
                    flushWork: nil)
                update(id: id, step: step, done: 0,
                       total: nil, phase: phase)
                return id
            }
        }
        #endif
        return nil
    }

    /// 收口非本会话的桥实况残留（重复条/已不该在
    /// 的条）：临时登记后走同一 end 收口。
    private func sweepStaleBridgeActivities(
        step: String, keeping: String?) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            for activity in Activity<
                OpsActivityAttributes
            >.activities
            where activity.attributes.opKind == .bridge
                && activity.id != keeping {
                let id = activity.id
                if sessions[id] == nil {
                    sessions[id] = Session(
                        kind: .bridge,
                        title: activity.attributes.opTitle,
                        lastSentAt: Date(),
                        lastSentState: nil, pending: nil,
                        flushWork: nil)
                }
                end(id: id, result: .aborted, step: step,
                    linger: 15)
            }
        }
        #endif
    }

    var hasActive: Bool { !sessions.isEmpty }

    // ── 后台宽限（§5.4）────────────────────────────

    /// App 进后台时的组合点（桥生命周期观察调用）：
    /// 有 active 实况才申请一次 beginBackgroundTask，
    /// 过期回调里做最后一次 waiting 更新并结束断言；
    /// 同时提交下一轮 BGTask 调度。
    func appDidEnterBackground() {
        Self.scheduleBackgroundTasks()
        guard hasActive, graceTask == .invalid else { return }
        graceTask = UIApplication.shared.beginBackgroundTask(
            withName: "moment.liveops.grace") { [weak self] in
            self?.expireGrace()
        }
        if graceTask != .invalid {
            DiagLog.shared.log(.info, "OPS live grace begin")
        }
    }

    private func expireGrace() {
        for (id, s) in sessions {
            // 桥会话不打 waiting：它的状态词就是连接
            // 态本身，宽限到期不构成状态迁移；其陈旧
            // 由 staleDate + 回前台刷新收口。
            if id == bridgeLiveId { continue }
            update(id: id, step: s.lastSentState?.step ?? "",
                   done: s.lastSentState?.done ?? 0,
                   total: s.lastSentState?.total,
                   phase: .waiting)
        }
        endGrace()
    }

    func endGrace() {
        guard graceTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceTask)
        graceTask = .invalid
        DiagLog.shared.log(.info, "OPS live grace end")
    }

    // ── BGTask 注册与调度（矩阵 #21/#22/#23）────────

    /// 启动期注册（App.init 调用，须在启动完成前）。
    /// handler 做真实活：processing = 快照清理
    /// （BridgeWriteSupport 保留策略）；refresh =
    /// OPS 指令拉取（救援通道周期刷新）。
    static func registerBackgroundTasks() {
        #if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskId,
            using: nil) { task in
            scheduleBackgroundTasks()
            let work = DispatchWorkItem {
                BridgeWriteSupport.shared
                    .pruneForBackground()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
            DispatchQueue.global(qos: .background)
                .async(execute: work)
            DiagLog.shared.log(.info,
                "OPS bg processing run")
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskId,
            using: nil) { task in
            scheduleBackgroundTasks()
            OpsDirectives.refreshInBackground()
            task.setTaskCompleted(success: true)
            DiagLog.shared.log(.info, "OPS bg refresh run")
        }
        #endif
    }

    static func scheduleBackgroundTasks() {
        #if canImport(BackgroundTasks)
        let processing = BGProcessingTaskRequest(
            identifier: processingTaskId)
        processing.requiresNetworkConnectivity = false
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date()
            .addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(processing)
        let refresh = BGAppRefreshTaskRequest(
            identifier: refreshTaskId)
        refresh.earliestBeginDate = Date()
            .addingTimeInterval(1800)
        try? BGTaskScheduler.shared.submit(refresh)
        #endif
    }

    // ── 通知授权（矩阵 §3.4）────────────────────────

    /// 桥设置页开关：开启时才请求通知授权（禁止启动
    /// 时索取）；关闭只记偏好（系统级授权由用户在
    /// 系统设置收回，本开关不再弹）。
    static let notifyPrefKey = "bridgeNotifyEnabled"

    static func setNotifyEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: notifyPrefKey)
        if on {
            #if canImport(UserNotifications)
            UNUserNotificationCenter.current()
                .requestAuthorization(
                    options: [.alert, .sound, .badge]) { _, _ in
                }
            #endif
        }
    }

    static var notifyEnabled: Bool {
        UserDefaults.standard.bool(forKey: notifyPrefKey)
    }
}
