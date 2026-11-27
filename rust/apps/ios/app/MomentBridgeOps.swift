// ── MCP 桥运维只读回读（M1）──
// OPS 三层回读（bootApplied/本启判定消费快照、
// currentCache/当前缓存文件、lastFetch/最近拉取
// 结果）+ 收敛判定；ops_refresh 只触发既有双源
// 拉取链落缓存，生效点恒为下次启动
// （effectiveFrom=next_launch）——桥不改 OPS 消
// 费语义，源头内容由中继侧 ops_get_sources 证明。
// rescue_status 与救援页同源组装（哨兵/DB/Diag
// 计数/启动模式），救援页独立性不破：本文件只
// 读、不触发救援动作（动作类工具 M2）。

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
            "readOnlyOpen": false,
        ]
    }
}
