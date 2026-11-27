import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// Live Activity 共享属性（权限/实况批，定案
// impl_ios_entitlements_liveops.md §5.2）：此文件同时
// 编译进主 App 与实况扩展（两目标各一份同名同构类型，
// ActivityKit 以类型全名 + Codable 形态匹配）。扩展不读
// 语言包、不联网——呈现文案全部由主 App 在 start/update
// 时以当前语言定格写入属性/状态，扩展只渲染。

/// 操作类别（属性静态字段，启动后不变）。
/// bridge = 桥会话实况（impl_bridge_live_keepalive）：
/// 与操作类同栈同形态，会话级长驻、随连接态更新，
/// 不是一次性操作。
enum LiveOpKind: String, Codable, Hashable {
    case bridgeOp = "bridge-op"
    case scenario = "scenario"
    case export = "export"
    case restore = "restore"
    case bridge = "bridge"
}

/// 操作阶段（ContentState.phase 的字符串口径）。
enum LiveOpPhase: String, Codable, Hashable {
    case running = "running"
    case waiting = "waiting"
    case done = "done"
    case failed = "failed"
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct OpsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: LiveOpPhase
        var stepLabel: String
        var done: Int
        var total: Int?
        var updatedAt: Date
    }

    /// 操作类别（bridge-op / scenario / export /
    /// restore / bridge）。
    var opKind: LiveOpKind
    /// 标题：start 时由 App 以当前语言包文案定格。
    var opTitle: String
    /// 静态细节短记（可空）：桥会话放设备指纹短记
    /// （首尾组），供锁屏面区分配对轮次；只放公开
    /// 寻址信息，绝不放密钥/令牌类凭据。操作类恒空。
    var opDetail: String = ""
}
#endif
