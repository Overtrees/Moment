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

    /// M1 工具清单（只读集 + ops_refresh 控制类；
    /// ops_get_sources 由中继侧执行、清单在册是为
    /// 哈希对齐）。与中继 worker.js 的 TOOLS、连接
    /// 器 manifest 逐字一致——manifestHash 三方对
    /// 账，任一处改名/增删都会在桥状态里现形。
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
        "rescue_status",
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
