// ── MCP 桥协议层（M1，方案 plan_app_mcp_bridge.md）──
// 常量、工具清单、清单哈希、规范 JSON 与哈希、
// JSON-RPC 编解码小工具。纯函数层：不碰 UI、不碰
// Library；Diag 只经协调器/分发器记（本文件不记）。
// 设备面承载原始 MCP JSON-RPC 帧（自定义设备传
// 输，非标准 MCP 传输）；协议版本钉 2025-06-18。

import Foundation
import CryptoKit

enum BridgeProto {
    /// 中继（Cloudflare Worker + DO 会话室，与
    /// moment-ops 不同域、互不复用）。
    static let relayHost = "moment-bridge.overtrees.workers.dev"
    static let relayBase = "https://" + relayHost
    static let protocolVersion = "2025-06-18"
    /// 单帧上限 1MiB（收发双向守卫）。
    static let maxFrameBytes = 1 << 20
    /// Diag 回读字节上限（diag_tail/diag_search）。
    static let maxDiagBytes = 256 << 10

    /// 工具清单（M1 只读集 + M2 落地集；ops_get_
    /// sources 由中继侧执行、清单在册是为哈希对
    /// 齐）。与中继 worker.js 的 TOOLS、连接器
    /// manifest 逐字一致——manifestHash 三方对
    /// 账，任一处改名/增删都会在桥状态里现形。
    /// 未入册（有意不在清单、调用回 unknown_
    /// tool）：正文级工具（notes_create、editor_
    /// insert_block、editor_update_block、editor_
    /// set_block_type）待端到端加密专项评审裁定
    /// （方案 §12.1/附录 B.3）；rescue_arm_safe_
    /// mode 待两段确认 + 端内呈现单独评审。
    /// U1 批入册：编辑器在席四件（editor_open、
    /// editor_get_state、editor_focus_block、
    /// editor_save_now，接 U0 在席注册表 + 导航
    /// 通道）；UI 自检驱动四件（uitest_list_
    /// surfaces、uitest_run、uitest_get_result、
    /// uitest_measure，归 ops 层另账）——清单
    /// 合计 30 件。
    /// 导航错误域（U1 正式登记，桥方案 §3.4 错
    /// 误表同步补行、三方同名）：nav_unavailable
    /// （导航通道未接线/编辑器不在位，
    /// retryable）、nav_timeout（等在席落定超
    /// 时，retryable）——由 BridgeNavError 映射
    /// （MomentBridgeTools 的 BridgeEditorTools.
    /// navError）；在席他篇复用 memo_busy，通道
    /// 只读拒绝复用 read_only_mode，目标篇不在
    /// 册复用 memo_not_found。
    static let toolNames: [String] = [
        "bridge_status",
        "app_state",
        "diag_tail",
        "diag_search",
        "notes_list",
        "notes_search",
        "notes_get",
        "ops_get_effective",
        "ops_get_sources",
        "ops_refresh",
        "ops_validate",
        "rescue_status",
        "rescue_try_normal_start",
        "settings_get",
        "settings_set_language",
        "settings_set_toggle",
        "settings_clear_weather_key",
        "notes_soft_delete",
        "notes_restore_deleted",
        "notes_delete_permanent",
        "editor_delete_block",
        "editor_move_block",
        "editor_open",
        "editor_get_state",
        "editor_focus_block",
        "editor_save_now",
        "uitest_list_surfaces",
        "uitest_run",
        "uitest_get_result",
        "uitest_measure",
    ]

    /// manifestHash = sha256(protocolVersion + "|"
    /// + 工具名排序后逗号连接)，小写 hex。
    static var manifestHash: String {
        let joined = toolNames.sorted().joined(separator: ",")
        return BridgeHash.sha256Hex(
            Data((protocolVersion + "|" + joined).utf8))
    }
}

enum BridgeHash {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// 规范 JSON：键排序序列化（docHash/集合比较的唯
/// 一口径）。值域须为 JSON 安全类型（字典/数组/
/// 字符串/数字/布尔/NSNull）——备忘 raw 与
/// flushedNode 天然满足（源头即 JSON 解析产物）。
enum BridgeCanonical {
    static func data(_ obj: Any) -> Data? {
        try? JSONSerialization.data(
            withJSONObject: obj, options: [.sortedKeys])
    }

    static func sha256Hex(_ obj: Any) -> String? {
        guard let d = data(obj) else { return nil }
        return BridgeHash.sha256Hex(d)
    }
}

/// JSON 小工具（桥帧编解码）。
enum BridgeJSON {
    static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization
                .jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    static func stringify(_ obj: Any) -> String? {
        guard let data = try? JSONSerialization
            .data(withJSONObject: obj) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// 工具错误（回 MCP isError 结果的载荷口径）：
/// code 取方案错误码全集，message 人读，retryable
/// 标可重试性。
struct BridgeToolError: Error {
    let code: String
    let message: String
    var retryable: Bool = false

    static func invalidParams(_ what: String) -> BridgeToolError {
        BridgeToolError(code: "invalid_params",
                        message: "invalid params: \(what)")
    }
    static let libraryUnavailable = BridgeToolError(
        code: "library_unavailable",
        message: "library not open", retryable: true)
}

/// MCP 结果构造（App 侧产物与中继/标准 MCP 同形）：
/// content[0].text 为 JSON 字符串。
enum BridgeResult {
    static func ok(_ payload: [String: Any]) -> [String: Any] {
        [
            "content": [[
                "type": "text",
                "text": BridgeJSON.stringify(payload) ?? "{}",
            ]],
            "isError": false,
        ]
    }

    static func error(_ e: BridgeToolError) -> [String: Any] {
        let payload: [String: Any] = [
            "code": e.code,
            "message": e.message,
            "retryable": e.retryable,
        ]
        return [
            "content": [[
                "type": "text",
                "text": BridgeJSON.stringify(payload) ?? "{}",
            ]],
            "isError": true,
        ]
    }
}
