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
}
