// ── MCP 桥快照恢复工具（M3，方案 plan_app_mcp
// _bridge.md §9.3 恢复工具 + §7.3 二次确认表）──
// backup_restore_snapshot：按快照 id 把全库恢
// 复到该快照点（全库替换语义）。门面在分发器
// （MomentBridgeTools）：ops 层 + 两段提交 +
// 数据写前置门 + 幂等管线 + 实况长操作集；本
// 文件只做工具本体——目标快照查册、编辑器在
// 席守卫、恢复前强制再快照（使恢复本身可逆）、
// 校验/换库/重载/对账经 Library 内部同路
// （bridgeRestoreFromSnapshot，与用户导入同
// 一条 validate-then-swap 链，不另起恢复管
// 线）。场景 snapshot_restore_drill 经内部同
// 路复用本实现（场级两段在 run 受理时已验
// 足，见 MomentBridgeScenarios）。
// 新增错误码（本批登记，中继/连接器同名）：
// snapshot_not_found（清单无此 id 或 zip 已被
// 保留策略清掉——不存在/过期同归此码，如实
// 失败不假成功）；恢复链失败复用既有
// snapshot_failed（§9.3 定名：校验不过/换库
// 失败/对账不一致）。
// Diag 口径（方案 §9.5）：只记快照 id、恢复前
// 后计数与哈希短形，永不记正文。

import Foundation

enum BridgeBackupTools {

    /// 快照恢复本体（分发器 case 与场景内部同
    /// 路共用单一实现，禁双轨）。
    static func restoreSnapshot(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let snapshotId = args["snapshotId"]
                as? String, !snapshotId.isEmpty else {
            return .failure(.invalidParams(
                "snapshotId required"))
        }
        guard let key = args["idempotencyKey"]
                as? String, !key.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        // 目标查册：清单条目与 zip 实体都在才算
        // 存在；保留策略（10 份/7 天）清掉的旧快
        // 照在此如实回 not_found。
        guard let record = BridgeWriteSupport.shared
            .snapshotRecord(id: snapshotId) else {
            return .failure(BridgeToolError(
                code: "snapshot_not_found",
                message: "no snapshot with id "
                    + "\(snapshotId) (unknown or "
                    + "already pruned)"))
        }
        // 在席守卫（全库替换专有）：任一备忘正在
        // 编辑器在席时，其活态副本的下一次保存会
        // 以旧库态整篇覆写恢复结果——与块写
        // memo_busy 同理，在席即拒（不分哪篇、
        // 不分脏净；补救是先关编辑器）。
        if let seated = EditorSeatRegistry.shared
            .currentMemoId {
            return .failure(BridgeToolError(
                code: "memo_busy",
                message: "memo \(seated) is open in "
                    + "the editor; close the editor "
                    + "before a full-library restore"))
        }
        let preHash = library.libraryHash()
        // 恢复前强制再快照（方案 §9.3/§7.3：每
        // 次单独生成，不走会话复用）——恢复本身
        // 可逆的唯一回滚路；失败即中止、数据未
        // 动。
        let rollbackId: String
        switch BridgeWriteSupport.shared.takeSnapshot(
            library: library,
            reason: "backup_restore_snapshot:pre") {
        case .success(let s): rollbackId = s
        case .failure(let e): return .failure(e)
        }
        DiagLog.shared.log(.info,
            "BRIDGE restore begin target=\(snapshotId) "
            + "rollback=\(rollbackId) "
            + "preHash=\(String(preHash.prefix(12))) "
            + "expectCount=\(record.memoCount) "
            + "expectHash=\(String(record.preHash.prefix(12)))")
        // 校验 → 换库 → 重载 → 对账（Library 内
        // 部同路；成败口径见其注释）。
        switch library.bridgeRestoreFromSnapshot(
            zipPath: record.path) {
        case .failed(let reason):
            DiagLog.shared.log(.error,
                "BRIDGE restore failed target="
                + "\(snapshotId) reason=\(reason) "
                + "rollback=\(rollbackId)")
            return .failure(BridgeToolError(
                code: "snapshot_failed",
                message: "restore failed (\(reason)); "
                    + "pre-restore snapshot "
                    + "\(rollbackId) retained for "
                    + "rollback"))
        case .restored(let post):
            // 对账（§9.3）：恢复后计数与哈希须与
            // 快照清单一致（计数同 appendManifest
            // 口径 = 在册未删篇数；哈希 =
            // libraryHash）。不一致报 snapshot_
            // failed——数据已换，但恢复前快照在
            // 位可回滚，不假成功。
            let countOk = post.count == record.memoCount
            let hashOk = post.hash == record.preHash
            DiagLog.shared.log(
                countOk && hashOk ? .info : .error,
                "BRIDGE restore verify target="
                + "\(snapshotId) count=\(post.count)/"
                + "\(record.memoCount) "
                + "hash=\(String(post.hash.prefix(12))) "
                + "match=\(countOk && hashOk ? 1 : 0)")
            guard countOk && hashOk else {
                return .failure(BridgeToolError(
                    code: "snapshot_failed",
                    message: "post-restore verify "
                        + "mismatch (count "
                        + "\(post.count)/"
                        + "\(record.memoCount), hash "
                        + "match=\(hashOk ? 1 : 0)); "
                        + "pre-restore snapshot "
                        + "\(rollbackId) retained for "
                        + "rollback"))
            }
            return .success([
                "snapshotId": snapshotId,
                "targetId": snapshotId,
                "restored": true,
                // 全库替换语义明示（§9.3）。
                "fullReplace": true,
                "preRestoreSnapshotId": rollbackId,
                "preLibraryHash": preHash,
                "postLibraryHash": post.hash,
                "memoCount": post.count,
                "expectedMemoCount": record.memoCount,
                "expectedLibraryHash": record.preHash,
            ])
        }
    }
}
