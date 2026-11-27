// ── MCP 桥运维面（M1 只读回读 + M2 动作）──
// OPS 三层回读（bootApplied/本启判定消费快照、
// currentCache/当前缓存文件、lastFetch/最近拉取
// 结果）+ 收敛判定；ops_refresh 只触发既有双源
// 拉取链落缓存，生效点恒为下次启动
// （effectiveFrom=next_launch）——桥不改 OPS 消
// 费语义，源头内容由中继侧 ops_get_sources 证明。
// M2 增：ops_validate（发布前纯校验、不落盘不
// 下发）与 rescue_try_normal_start（运维高危、
// 两段提交；与 RescueView 主按钮同一调用序列，
// 经公开 Library API 落地，不模拟点按钮）。
// rescue_status 与救援页同源组装（哨兵/DB/Diag
// 计数/启动模式），救援页独立性不破。
// 布防批增（M2 §7.3 接线）：rescue_arm_safe_
// mode——diag 域一次性布防标记（BridgeSafeMode
// ArmStore，本文件尾）+ 启动判定第三路消费
// （Library.judgePreviousLaunch，消费恰一次转
// 审计留痕）；与 OPS forceSafeMode 分工：源头
// 指令是持续型（改源头才放松），桥布防是一次
// 型（下次启动消费即清），互不覆盖、并存取并。

import Foundation

enum BridgeOpsFormat {
    static func setDict(
        _ set: OpsDirectiveSet) -> [String: Any] {
        [
            "version": set.version,
            "disableSteps": set.disableSteps,
            "forceSafeMode": set.forceSafeMode,
        ]
    }
}

enum BridgeOpsTools {

    static func opsGetEffective(
        library: Library) -> [String: Any] {
        let boot = library.bootAppliedOps
        let cache = OpsDirectives.cached()
        let current = OpsDirectives.shared.current
        var cacheInfo: [String: Any] = [
            "exists": false,
            "set": BridgeOpsFormat.setDict(cache),
        ]
        let path = OpsDirectives.cachePath
        if let attrs = try? FileManager.default
            .attributesOfItem(atPath: path) {
            cacheInfo["exists"] = true
            if let mtime = attrs[.modificationDate]
                as? Date {
                cacheInfo["mtimeMs"] = Int64(
                    mtime.timeIntervalSince1970 * 1000)
            }
            if let data = try? Data(contentsOf:
                URL(fileURLWithPath: path)) {
                cacheInfo["sha256"] =
                    BridgeHash.sha256Hex(data)
            }
        }
        return [
            "bootApplied": BridgeOpsFormat.setDict(boot),
            "currentCache": cacheInfo,
            "lastFetch": [
                "set": BridgeOpsFormat.setDict(current),
                "source": OpsDirectives.shared.lastSource,
            ],
            "converged": boot == cache && cache == current,
        ]
    }

    static func opsRefresh(
        completion: @escaping (
            Result<[String: Any], BridgeToolError>) -> Void) {
        OpsDirectives.shared.fetchWithOutcome { outcome in
            DispatchQueue.main.async {
                var payload: [String: Any] = [
                    "successSource": outcome.successSource,
                    "failures": outcome.failures,
                    "effectiveFrom": "next_launch",
                ]
                if let data = try? Data(contentsOf:
                    URL(fileURLWithPath:
                        OpsDirectives.cachePath)) {
                    payload["cacheSha256"] =
                        BridgeHash.sha256Hex(data)
                }
                if let line = DiagLog.shared.today.last(
                    where: {
                        $0.text.hasPrefix(
                            "OPS directives fetched")
                    }) {
                    payload["fetchedLine"] = line.text
                }
                DiagLog.shared.log(.info,
                    "BRIDGE ops_refresh source="
                    + (outcome.successSource.isEmpty
                       ? "-" : outcome.successSource)
                    + " failures=\(outcome.failures.count)")
                completion(.success(payload))
            }
        }
    }

    static func rescueStatus(
        library: Library,
        coordinator: BridgeCoordinator) -> [String: Any] {
        let sentinel = LaunchSentinelStore.load()
        var sentinelInfo: [String: Any] = [
            "exists": FileManager.default.fileExists(
                atPath: LaunchSentinelStore.filePath),
            "busy": sentinel.busy,
            "step": sentinel.step,
            "streak": sentinel.streak,
            "lastRescueAction": sentinel.lastRescueAction,
            "lastRescueAtMs": Int64(
                sentinel.lastRescueAt * 1000),
        ]
        if let attrs = try? FileManager.default
            .attributesOfItem(
                atPath: LaunchSentinelStore.filePath),
           let mtime = attrs[.modificationDate] as? Date {
            sentinelInfo["mtimeMs"] = Int64(
                mtime.timeIntervalSince1970 * 1000)
        }
        var dbBytes: Int64 = -1
        let dbPath = library.storeDir + "/moment.db"
        if let attrs = try? FileManager.default
            .attributesOfItem(atPath: dbPath),
           let size = attrs[.size] as? NSNumber {
            dbBytes = size.int64Value
        }
        DiagLog.shared.loadIfNeeded()
        return [
            "bootMode": BridgeReadTools.bootModeDict(library),
            "safeModeArm": BridgeSafeModeArmStore
                .statusDict(),
            "sentinel": sentinelInfo,
            "dbOpen": library.isDbOpen,
            "dbBytes": dbBytes,
            "diagTodayCount": DiagLog.shared.today.count,
            "diagArchiveCount":
                DiagLog.shared.archives.count,
            "dispatcherForm": coordinator.dispatcherForm,
            "readOnlyOpen": library.isReadOnly,
        ]
    }

    // ── M2：指令预检 ──

    /// 已登记步名全集（LaunchStep ∪ OpsStep）：
    /// ops_validate 判非法步名的唯一口径。
    static let knownOpsSteps: Set<String> = [
        LaunchStep.open, LaunchStep.openFFI,
        LaunchStep.readList, LaunchStep.readParse,
        LaunchStep.seed, LaunchStep.rehydrate,
        LaunchStep.attachNames, LaunchStep.attachTypes,
        LaunchStep.firstFrame, LaunchStep.session,
        LaunchStep.sceneHome, LaunchStep.sceneEditor,
        OpsStep.diagFreezePersist,
        OpsStep.weatherRefresh, OpsStep.mathPreheat,
        OpsStep.bridge, OpsStep.watchdog,
    ]

    /// 发布前预检（纯校验）：以 OpsDirectives
    /// .sanitize 同口径解析待校验指令，回被接受
    /// 字段/被忽略的未知字段/非法步名/规范形与
    /// 哈希。不落盘、不下发、不改缓存。
    static func opsValidate(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let directive = args["directive"]
                as? [String: Any] else {
            return .failure(.invalidParams(
                "directive object required"))
        }
        guard let data = try? JSONSerialization.data(
                withJSONObject: directive),
              let set = OpsDirectives.sanitize(data)
        else {
            return .success([
                "valid": false,
                "reason": "unparseable directive",
            ])
        }
        let whitelist: Set<String> = [
            "version", "disableSteps", "forceSafeMode",
        ]
        let keys = Set(directive.keys)
        let invalidSteps = set.disableSteps.filter {
            !knownOpsSteps.contains($0)
        }
        let normalized = BridgeOpsFormat.setDict(set)
        return .success([
            "valid": invalidSteps.isEmpty,
            "acceptedFields": keys
                .intersection(whitelist).sorted(),
            "ignoredFields": keys
                .subtracting(whitelist).sorted(),
            "invalidSteps": invalidSteps,
            "normalized": normalized,
            "sha256": BridgeCanonical
                .sha256Hex(normalized) ?? "",
        ])
    }

    // ── M2：救援动作 ──

    /// 尝试正常启动（运维高危；分发器已验 ops
    /// 能力位与两段提交令牌）。仅当前处于安全模
    /// 式时可调；动作序列与 RescueView.tryNormal
    /// 逐点一致（RESCUE action 行 + recordRescue
    /// Action 留痕 + prepareNormalStart 复位 +
    /// bootMode 切回 normal 触发常规 load），远
    /// 程动作以 via=bridge 标记区分来源。源头/
    /// 缓存的 forceSafeMode 仍在位时如实回
    /// forceSafeStillArmed，不报假成功。
    static func rescueTryNormalStart(
        library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard library.bootIsSafe else {
            return .failure(BridgeToolError(
                code: "not_in_safe_mode",
                message: "rescue_try_normal_start is "
                    + "only callable in safe mode"))
        }
        let forceArmed = library.bootAppliedOps
            .forceSafeMode
            || OpsDirectives.cached().forceSafeMode
        DiagLog.shared.log(.info,
            "RESCUE action normal-retry via=bridge")
        Library.recordRescueAction("normal-retry")
        DiagLog.shared.log(.info,
            "RESCUE exit to=normal")
        library.prepareNormalStart()
        library.bootMode = .normal
        var payload: [String: Any] = [
            "attempted": true,
            "normalLoadSemantics": true,
            "forceSafeStillArmed": forceArmed,
            "appState": BridgeReadTools.appState(
                library: library),
        ]
        if forceArmed {
            payload["note"] = "forceSafeMode still "
                + "armed (bootApplied or cache); the "
                + "next launch returns to safe mode"
        }
        return .success(payload)
    }

    /// 布防下次启动进安全模式（运维高危；分发器
    /// 已验 ops 能力位、两段提交令牌与幂等管线）。
    /// 单机版 forceSafeMode：在 diag 域写桥专用
    /// 一次性标记（不碰 OPS 缓存、不碰哨兵
    /// streak），启动判定在 streak / OPS 两路之
    /// 外以第三路消费（Library.judgePrevious
    /// Launch）。App 不能被远程重启——本工具只
    /// 布防，生效等用户下次打开 App，返回与
    /// Diag 均如实写明。已有未消费标记时以后到
    /// 者为准（同一权威通道，Diag 记 replaced）。
    static func rescueArmSafeMode(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        let reason = (args["reason"] as? String ?? "")
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= 120
        else {
            return .failure(.invalidParams(
                "reason required (1-120 chars)"))
        }
        let key = (args["idempotencyKey"] as? String)
            ?? ""
        let commandId = key.isEmpty
            ? UUID().uuidString : key
        let previous = BridgeSafeModeArmStore.load()
        let arm = BridgeSafeModeArm(
            commandId: commandId,
            armedAtMs: Library.epochMs(),
            reason: reason)
        guard BridgeSafeModeArmStore.arm(arm) else {
            return .failure(BridgeToolError(
                code: "arm_write_failed",
                message: "arm marker write failed",
                retryable: true))
        }
        let diagReason = reason
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        DiagLog.shared.log(.info,
            "RESCUE arm set id=\(commandId) "
            + "reason=\(diagReason)"
            + (previous != nil ? " replaced=1" : ""))
        let sentinel = LaunchSentinelStore.load()
        var payload: [String: Any] = [
            "armed": true,
            "commandId": commandId,
            "armedAtMs": arm.armedAtMs,
            "effectiveFrom": "next_launch",
            "note": "takes effect at the next app "
                + "launch; the app cannot be "
                + "restarted remotely",
            "sentinel": [
                "busy": sentinel.busy,
                "step": sentinel.step,
                "streak": sentinel.streak,
            ],
        ]
        if let previous {
            payload["replacedCommandId"] =
                previous.commandId
        }
        return .success(payload)
    }
}

// ── 布防标记存储（M2 §7.3 接线批）─────────────
// diag 域文件直写（与哨兵同隔离域、同 .atomic
// 口径）：bridge-safe-mode-arm.json 为活动标记
// （至多一份），启动判定 take() 取走即清、随后
// recordAudit 转审计留痕 bridge-safe-mode-arm-
// audit.json（只记最近一次消费，含 commandId 与
// 双时刻，不再强制）。本存储只做文件 IO（叶子
// 层，无单例回读），供 Library.init 判定链与桥
// 分发器共用。
struct BridgeSafeModeArm: Codable {
    var commandId: String = ""
    var armedAtMs: Int64 = 0
    var reason: String = ""
}

struct BridgeSafeModeArmAudit: Codable {
    var commandId: String = ""
    var armedAtMs: Int64 = 0
    var consumedAtMs: Int64 = 0
    var reason: String = ""
    /// 本次消费是否即为定源路径（前两路未定
    /// safe 时 true；已 safe 时只消费不改源）。
    var applied: Bool = false
}

enum BridgeSafeModeArmStore {
    static var markerPath: String {
        DiagLog.diagDirPath()
            + "/bridge-safe-mode-arm.json"
    }
    static var auditPath: String {
        DiagLog.diagDirPath()
            + "/bridge-safe-mode-arm-audit.json"
    }

    static func load() -> BridgeSafeModeArm? {
        guard let data = try? Data(contentsOf:
                URL(fileURLWithPath: markerPath)),
              let arm = try? JSONDecoder().decode(
                BridgeSafeModeArm.self, from: data)
        else { return nil }
        return arm
    }

    @discardableResult
    static func arm(
        _ arm: BridgeSafeModeArm) -> Bool {
        guard let data = try? JSONEncoder()
            .encode(arm) else { return false }
        do {
            try data.write(
                to: URL(fileURLWithPath: markerPath),
                options: .atomic)
            return true
        } catch { return false }
    }

    /// 消费第一步：读标记并立即删文件（取走即
    /// 清——进程在审计落盘前死掉也至多丢审计，
    /// 绝不二次强制）。无标记回 nil。
    static func take() -> BridgeSafeModeArm? {
        guard let arm = load() else { return nil }
        try? FileManager.default.removeItem(
            atPath: markerPath)
        return arm
    }

    /// 消费第二步：审计留痕（最近一次消费的
    /// commandId/双时刻/原因/定源与否）。
    @discardableResult
    static func recordAudit(
        _ arm: BridgeSafeModeArm,
        applied: Bool) -> Bool {
        let audit = BridgeSafeModeArmAudit(
            commandId: arm.commandId,
            armedAtMs: arm.armedAtMs,
            consumedAtMs: Library.epochMs(),
            reason: arm.reason,
            applied: applied)
        guard let data = try? JSONEncoder()
            .encode(audit) else { return false }
        do {
            try data.write(
                to: URL(fileURLWithPath: auditPath),
                options: .atomic)
            return true
        } catch { return false }
    }

    static func loadAudit()
        -> BridgeSafeModeArmAudit? {
        guard let data = try? Data(contentsOf:
                URL(fileURLWithPath: auditPath)),
              let audit = try? JSONDecoder().decode(
                BridgeSafeModeArmAudit.self, from: data)
        else { return nil }
        return audit
    }

    /// rescue_status 回读面：活动标记 + 最近审
    /// 计（均为元数据，不含笔记内容）。
    static func statusDict() -> [String: Any] {
        let pending = load()
        var dict: [String: Any] = [
            "armed": pending != nil,
        ]
        if let pending {
            dict["pending"] = [
                "commandId": pending.commandId,
                "armedAtMs": pending.armedAtMs,
                "reason": pending.reason,
            ]
        }
        if let audit = loadAudit() {
            dict["lastConsumed"] = [
                "commandId": audit.commandId,
                "armedAtMs": audit.armedAtMs,
                "consumedAtMs": audit.consumedAtMs,
                "reason": audit.reason,
                "applied": audit.applied,
            ]
        }
        return dict
    }
}
