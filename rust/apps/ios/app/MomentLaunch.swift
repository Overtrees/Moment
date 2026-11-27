// Moment 启动哨兵（自救机制 R1，0.9.45）：启动步名
// 集中定义（LaunchStep）+ 哨兵文件直写存储
// （LaunchSentinel / LaunchSentinelStore）。规格见
// docs/reports/plan_native_rescue.md S1/S2/S6；本
// 文件自 MomentApp.swift 拆出（拒绝上帝文件，独立
// 成文件），判定与消费仍在 Library（MomentApp）。
import Foundation

// ── 启动步名（S1 集中定义，禁止散写字面量）─────
// launchMark / markScene 的步名一律引用此处；判定
// 侧以 isLoadStep 分级：加载步未收尾 = 启动期死亡
// （计数、≥2 进安全模式）；会话/场景/首帧步未收尾
// = 前台终止（warn 留痕不计数）。
enum LaunchStep {
    static let open = "开库"
    static let openFFI = "开库·FFI"
    static let readList = "读数据·列表"
    static let readParse = "读数据·解析"
    static let seed = "写种子"
    static let rehydrate = "再水化·待删"
    static let attachNames = "附件名表"
    static let attachTypes = "附件类型"
    static let firstFrame = "首帧"
    static let session = "会话中"
    static let sceneHome = "场景·首页"
    static let sceneEditor = "场景·编辑页"
    /// 安全模式页在场步（救援完整性批）：救援页
    /// onAppear 推进至此——安全模式内被强杀时步
    /// 已非加载步，下次判定走前台终止口径、不再
    /// 虚增 streak（审计 §5.2 d 收口）。
    static let sceneRescue = "场景·救援"

    static func isLoadStep(_ s: String) -> Bool {
        !(s.hasPrefix("会话") || s.hasPrefix("场景")
            || s == firstFrame)
    }
}

/// 启动哨兵（S1）：落 diag 域文件 launch-sentinel
/// .json，每步 Data.write(.atomic) 同步直写——硬崩
/// （abort/强杀）时 UserDefaults 内存缓存可能丢最
/// 后一步，文件直写可靠。UserDefaults 三键保留只
/// 读回退一版（读序：文件优先、缺失回退旧键）。
struct LaunchSentinel: Codable {
    var busy: Bool = false
    var step: String = ""
    var streak: Int = 0
    /// streak 锚步（LCH-02 根治批）：当前 streak
    /// 计的是哪一步的连续死亡；判定只对同一步复
    /// 现递增、异步换锚重计（散射外部终止不合并，
    /// 设计 fix_launch_verdict_lch02.md §3.2）。
    /// streak == 0 时无义。
    var streakStep: String = ""
    /// 挂起墓碑（同批）：最近一次 launchSuspend
    /// 时的步名；"" = 未挂起/已恢复。加载步墓碑
    /// 在下次判定只留痕不计数（§3.3）。
    var suspendedStep: String = ""
    /// S6 跨启动留痕：上次救援动作与时刻，下次启动
    /// LAUNCH 行尾附 lastRescue=，定因一眼可见。
    var lastRescueAction: String = ""
    var lastRescueAt: Double = 0
}

extension LaunchSentinel {
    /// 兼容解码（LCH-02 根治批，承重）：新字段经
    /// decodeIfPresent 兜底——synthesized 解码对
    /// 非 Optional 缺键即失败、load() 会回退
    /// UserDefaults 并静默丢失全部哨兵证据；旧版
    /// 文件必须可读。全字段同口径兜底，编码侧仍
    /// synthesized 全字段写出。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(
            keyedBy: CodingKeys.self)
        busy = try c.decodeIfPresent(
            Bool.self, forKey: .busy) ?? false
        step = try c.decodeIfPresent(
            String.self, forKey: .step) ?? ""
        streak = try c.decodeIfPresent(
            Int.self, forKey: .streak) ?? 0
        streakStep = try c.decodeIfPresent(
            String.self, forKey: .streakStep) ?? ""
        suspendedStep = try c.decodeIfPresent(
            String.self, forKey: .suspendedStep) ?? ""
        lastRescueAction = try c.decodeIfPresent(
            String.self, forKey: .lastRescueAction) ?? ""
        lastRescueAt = try c.decodeIfPresent(
            Double.self, forKey: .lastRescueAt) ?? 0
    }
}

enum LaunchSentinelStore {
    static var filePath: String {
        DiagLog.diagDirPath() + "/launch-sentinel.json"
    }

    static func load() -> LaunchSentinel {
        if let data = try? Data(
                contentsOf: URL(fileURLWithPath: filePath)),
           let s = try? JSONDecoder().decode(
                LaunchSentinel.self, from: data) {
            return s
        }
        let d = UserDefaults.standard
        var s = LaunchSentinel()
        s.busy = d.bool(forKey: "launchInProgress")
        s.step = d.string(forKey: "launchStep") ?? ""
        s.streak = d.integer(forKey: "launchCrashStreak")
        return s
    }

    @discardableResult
    static func save(_ s: LaunchSentinel) -> Bool {
        guard let data = try? JSONEncoder().encode(s)
        else { return false }
        do {
            try data.write(
                to: URL(fileURLWithPath: filePath),
                options: .atomic)
            return true
        } catch { return false }
    }

    /// 串行化读-改-写（救援完整性批，审计 §5.2 c）：
    /// 既有各写点自做 load→改→save 无锁交错——后台
    /// load 步写与主线程场景标记并发时步名可回退/
    /// 丢失。全部改写点收敛经此：锁内读改写一次完
    /// 成，写仍是 .atomic 直写、返回前已落盘（哨兵
    /// 的硬崩可靠性语义不变）。纯读仍走 load()（原
    /// 子写保证读不见撕裂）。
    private static let updateLock = NSLock()

    @discardableResult
    static func update(
        _ mutate: (inout LaunchSentinel) -> Void
    ) -> Bool {
        updateLock.lock()
        defer { updateLock.unlock() }
        var s = load()
        mutate(&s)
        return save(s)
    }
}

// ── 状态快照环（S5，R3）──────────────────────────
// 每次冷启一条结构化元数据快照，环形保留 20 条，
// 落 diag 域 rescue-log.json（与哨兵同隔离域）。
// 字段纪律（总红线）：只记元数据——时刻/版本/哨
// 兵判定/库字节/Diag 计数/磁盘余量/篇数计数；绝
// 不记任何备忘的标题、正文或附件的文件名。消费
// 面：RescueView 状态区（最新 + 上次两条并列）、
// 导出诊断整环附入。救援动作经 markAction 记到
// 「发生那次启动」的快照上，下次启动由 Library
// 折一条 RESCUE log 摘要行后清标（对位 Web W8 的
// drain 口径：纯快照静默、含动作才留痕）。
struct RescueSnapshot: Codable {
    var ts: Double = 0
    var appVersion: String = ""
    var systemVersion: String = ""
    var prevStep: String = ""
    var streak: Int = 0
    /// 判定点 streak 锚步（LCH-02 根治批）：与哨兵
    /// streakStep 同源同点记账，导出/救援页呈现
    /// 「连续死亡是否同一步」的销账面。
    var streakStep: String = ""
    var bootMode: String = "normal"
    var dbBytes: Int64 = -1
    var diagToday: Int = -1
    var diagArchives: Int = -1
    var diskFreeBytes: Int64 = -1
    /// 开库成功后补写（判定点尚不可知，nil = 未补）。
    var memoCount: Int? = nil
    var attachCount: Int? = nil
    /// 本次启动内发生的救援动作名（下次启动折行
    /// 后清空；快照本体保留在环内供导出）。
    var actions: [String] = []
}

extension RescueSnapshot {
    /// 兼容解码（LCH-02 根治批，同哨兵 §3.1 纪
    /// 律）：streakStep 为后加字段，旧版快照环文
    /// 件缺键不得整环解码失败（load() 失败即整环
    /// 丢失）。全字段 decodeIfPresent 兜底，编码
    /// 侧仍 synthesized 全字段写出。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(
            keyedBy: CodingKeys.self)
        ts = try c.decodeIfPresent(
            Double.self, forKey: .ts) ?? 0
        appVersion = try c.decodeIfPresent(
            String.self, forKey: .appVersion) ?? ""
        systemVersion = try c.decodeIfPresent(
            String.self, forKey: .systemVersion) ?? ""
        prevStep = try c.decodeIfPresent(
            String.self, forKey: .prevStep) ?? ""
        streak = try c.decodeIfPresent(
            Int.self, forKey: .streak) ?? 0
        streakStep = try c.decodeIfPresent(
            String.self, forKey: .streakStep) ?? ""
        bootMode = try c.decodeIfPresent(
            String.self, forKey: .bootMode) ?? "normal"
        dbBytes = try c.decodeIfPresent(
            Int64.self, forKey: .dbBytes) ?? -1
        diagToday = try c.decodeIfPresent(
            Int.self, forKey: .diagToday) ?? -1
        diagArchives = try c.decodeIfPresent(
            Int.self, forKey: .diagArchives) ?? -1
        diskFreeBytes = try c.decodeIfPresent(
            Int64.self, forKey: .diskFreeBytes) ?? -1
        memoCount = try c.decodeIfPresent(
            Int.self, forKey: .memoCount) ?? nil
        attachCount = try c.decodeIfPresent(
            Int.self, forKey: .attachCount) ?? nil
        actions = try c.decodeIfPresent(
            [String].self, forKey: .actions) ?? []
    }
}

enum RescueLogStore {
    static let ringLimit = 20
    static var filePath: String {
        DiagLog.diagDirPath() + "/rescue-log.json"
    }

    static func load() -> [RescueSnapshot] {
        guard let data = try? Data(
                contentsOf: URL(fileURLWithPath: filePath)),
              let ring = try? JSONDecoder().decode(
                [RescueSnapshot].self, from: data)
        else { return [] }
        return ring
    }

    static func save(_ ring: [RescueSnapshot]) {
        guard let data = try? JSONEncoder().encode(
            Array(ring.suffix(ringLimit))) else { return }
        try? data.write(
            to: URL(fileURLWithPath: filePath),
            options: .atomic)
    }

    /// 追加一条（冷启判定后由 Library 调），环满
    /// 丢最旧。
    static func append(_ snap: RescueSnapshot) {
        var ring = load()
        ring.append(snap)
        save(ring)
    }

    /// 补写最新一条（开库成功后回填计数）。
    static func updateLatest(
        _ mutate: (inout RescueSnapshot) -> Void) {
        var ring = load()
        guard !ring.isEmpty else { return }
        var last = ring[ring.count - 1]
        mutate(&last)
        ring[ring.count - 1] = last
        save(ring)
    }

    /// 救援动作打标：记到最新一条快照的 actions
    /// （Library.recordRescueAction 单点调用）。环
    /// 为空（本次启动快照尚未写）时无操作——哨兵
    /// lastRescueAction 仍有留痕，不丢信息。
    static func markAction(_ action: String) {
        updateLatest { $0.actions.append(action) }
    }

    /// 下次启动折行：取走最新一条的动作标（取后
    /// 清标落盘），并返回该条供摘要。无标返回 nil
    /// 动作数组。
    static func drainActionMarks()
        -> (actions: [String], snap: RescueSnapshot?) {
        var ring = load()
        guard let last = ring.last else {
            return ([], nil)
        }
        if last.actions.isEmpty { return ([], last) }
        let acts = last.actions
        ring[ring.count - 1].actions = []
        save(ring)
        return (acts, last)
    }

    /// 导出诊断附段：整环逐条摘要（数据行口径，
    /// 不本地化；只含快照元数据字段）。
    static func exportText() -> String {
        let ring = load()
        guard !ring.isEmpty else {
            return "==== RESCUE log ====\n(empty)"
        }
        var lines = ["==== RESCUE log ===="]
        for s in ring {
            lines.append(
                "snap ts=\(Int(s.ts)) v=\(s.appVersion) "
                + "mode=\(s.bootMode) "
                + "prevStep=\(s.prevStep.isEmpty ? "-" : s.prevStep) "
                + "streak=\(s.streak) "
                + "streakStep=\(s.streakStep.isEmpty ? "-" : s.streakStep) "
                + "db=\(s.dbBytes) "
                + "diag=\(s.diagToday)/\(s.diagArchives) "
                + "memos=\(s.memoCount.map(String.init) ?? "-") "
                + "attach=\(s.attachCount.map(String.init) ?? "-") "
                + "actions=\(s.actions.joined(separator: ","))")
        }
        return lines.joined(separator: "\n")
    }
}
