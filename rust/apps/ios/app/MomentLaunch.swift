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
    /// S6 跨启动留痕：上次救援动作与时刻，下次启动
    /// LAUNCH 行尾附 lastRescue=，定因一眼可见。
    var lastRescueAction: String = ""
    var lastRescueAt: Double = 0
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
}
