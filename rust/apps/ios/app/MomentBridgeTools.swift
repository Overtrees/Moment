// ── MCP 桥工具分发 + 工具集（M1 只读 + M2 写面）──
// 分发器边界（方案 §4/§7）：能力分层判定（write
// /ops 未授回 scope_denied、绝不静默放行）；数据
// 写一律经快照先行 + 幂等去重 + docHash 乐观并
// 发（BridgeWriteSupport/BridgeWriteTools）；高
// 危三件（永久删除/尝试正常启动/布防安全模式）
// 另加两段提交。
// 安全模式下分发器转受限形态（可用集见 safe
// LimitedTools），其余一律 safe_mode_limited，
// 不假成功。全部工具走 App 内部模型（Library/
// DiagLog/Ops），不做合成触摸（搜索走只读访问
// 器；块级结构写走 Library 文档路径，见
// BridgeWriteTools 的口径注记）。

import Foundation
import UIKit

final class BridgeDispatcher {
    static let shared = BridgeDispatcher()

    /// write 层工具（方案 §7.2：write 层覆盖笔
    /// 记/编辑器语义写）：须 write 能力位。在席
    /// 三件（open/focus_block/save_now）为编辑
    /// 器语义写、同层；editor_get_state 为只读
    /// 语义状态，不入此集。
    static let writeScopeTools: Set<String> = [
        "settings_set_language",
        "settings_set_toggle",
        "settings_clear_weather_key",
        "notes_soft_delete",
        "notes_restore_deleted",
        "editor_delete_block",
        "editor_move_block",
        "editor_open",
        "editor_focus_block",
        "editor_save_now",
    ]
    /// ops 层工具：须 ops 能力位。
    static let opsScopeTools: Set<String> = [
        "ops_refresh",
        "notes_delete_permanent",
        "rescue_try_normal_start",
        "rescue_arm_safe_mode",
    ]
    /// UI 自检驱动工具（U 批，方案
    /// plan_ui_selftest_driver.md §2.2）：全件
    /// 归 ops 层（现配对已授，落地即用）；安全
    /// 模式受限集不收（编辑器不在位，一律
    /// safe_mode_limited）。
    static let uiTestScopeTools: Set<String> = [
        "uitest_list_surfaces",
        "uitest_run",
        "uitest_get_result",
        "uitest_measure",
    ]
    /// 数据写全集（快照/幂等/只读门/OPS 禁桥深查
    /// 的辖面）。布防安全模式不写库、不走快照，
    /// 入集只取幂等回放 + 只读门 + 禁桥门三项辖
    /// 面（与永删同为 ops 高危两段件的管线口径）。
    static let dataWriteTools: Set<String> =
        writeScopeTools.union([
            "notes_delete_permanent",
            "rescue_arm_safe_mode",
        ])
    /// 两段提交工具（方案 §7.3）：先 dryRun 取得
    /// 绑定工具名 + 参数哈希的一次性 actionToken，
    /// 60 秒内回带执行；缺/错/过期一律
    /// confirmation_required。
    static let twoStageTools: Set<String> = [
        "notes_delete_permanent",
        "rescue_try_normal_start",
        "rescue_arm_safe_mode",
        "uitest_run",
    ]
    /// 受限分发器可用集（方案 §9.6）。
    static let safeLimitedTools: Set<String> = [
        "bridge_status",
        "app_state",
        "diag_tail",
        "diag_search",
        "ops_get_effective",
        "ops_refresh",
        "rescue_status",
        "rescue_try_normal_start",
    ]

    private var actionTokens: [String: (
        tool: String, hash: String, expiresAt: Date)] = [:]

    /// 参数哈希（两段提交与幂等共用口径）：规范
    /// JSON 的 sha256，剔除 dryRun/actionToken 两
    /// 个流程字段，其余参数全量入哈希。
    static func paramsHash(_ args: [String: Any]) -> String {
        var a = args
        a.removeValue(forKey: "dryRun")
        a.removeValue(forKey: "actionToken")
        return BridgeCanonical.sha256Hex(a) ?? ""
    }

    func dispatch(
        name: String, args: [String: Any],
        library: Library?,
        coordinator: BridgeCoordinator,
        completion: @escaping ([String: Any]) -> Void) {
        let t0 = Date()
        func done(_ result: [String: Any], code: String) {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            coordinator.recordCall(tool: name, code: code,
                                   ms: ms)
            completion(result)
        }
        func fail(_ e: BridgeToolError) {
            done(BridgeResult.error(e), code: e.code)
        }
        guard BridgeProto.toolNames.contains(name) else {
            fail(BridgeToolError(
                code: "unknown_tool",
                message: "tool not in manifest: \(name)"))
            return
        }
        // ops_get_sources 由中继侧执行（origin=relay）；
        // 若帧误达 App，诚实回 unknown_tool。
        if name == "ops_get_sources" {
            fail(BridgeToolError(
                code: "unknown_tool",
                message: "ops_get_sources is relay-executed"))
            return
        }
        // 受限形态：安全模式，或当前会话新拉到的指
        // 令已置 forceSafeMode（写面先于读面收紧，
        // 方案 §9.6 纵深防御）。
        let limited = (library?.bootIsSafe ?? false)
            || OpsDirectives.cached().forceSafeMode
        if limited, !Self.safeLimitedTools.contains(name) {
            fail(BridgeToolError(
                code: "safe_mode_limited",
                message: "safe mode: tool not in the "
                    + "limited dispatcher set"))
            return
        }
        // 能力门（分层、明确回码，不静默放行）。
        if Self.writeScopeTools.contains(name),
           !coordinator.scopes.contains("write") {
            fail(BridgeToolError(
                code: "scope_denied",
                message: "\(name) requires write scope"))
            return
        }
        if Self.opsScopeTools.contains(name),
           !coordinator.scopes.contains("ops") {
            fail(BridgeToolError(
                code: "scope_denied",
                message: "\(name) requires ops scope"))
            return
        }
        if Self.uiTestScopeTools.contains(name),
           !coordinator.scopes.contains("ops") {
            fail(BridgeToolError(
                code: "scope_denied",
                message: "\(name) requires ops scope"))
            return
        }
        let ctx: [String: Any] = [
            "appSessionId": coordinator.appSessionId,
            "bootSessionId": coordinator.bootSessionId,
            "bootMode": (library?.bootIsSafe ?? false)
                ? "safe" : "normal",
            "manifestHash": BridgeProto.manifestHash,
        ]
        // 数据写前置门：库在位、非只读打开态、桥未
        // 被 OPS 指令点名禁用（当前会话深查）。
        if Self.dataWriteTools.contains(name) {
            guard let library else {
                fail(.libraryUnavailable); return
            }
            if library.isReadOnly {
                fail(BridgeToolError(
                    code: "read_only_mode",
                    message: "library is open read-only; "
                        + "write tools are unavailable"))
                return
            }
            if OpsDirectives.cached()
                .isDisabled(OpsStep.bridge) {
                fail(BridgeToolError(
                    code: "ops_disabled",
                    message: "bridge disabled by ops "
                        + "directive in current cache"))
                return
            }
        }
        // 两段提交（先于幂等回放：令牌一次性，丢失
        // 响应后以新令牌 + 同幂等键重试得首次结果）。
        if Self.twoStageTools.contains(name) {
            let hash = Self.paramsHash(args)
            if (args["dryRun"] as? Bool) == true {
                let token = UUID().uuidString
                actionTokens[token] = (
                    tool: name, hash: hash,
                    expiresAt: Date()
                        .addingTimeInterval(60))
                var p: [String: Any] = [
                    "dryRun": true,
                    "tool": name,
                    "actionToken": token,
                    "paramsHash": hash,
                    "expiresInSec": 60,
                ]
                p["ctx"] = ctx
                done(BridgeResult.ok(p), code: "dry_run")
                return
            }
            guard let token = args["actionToken"]
                    as? String,
                  let rec = actionTokens[token],
                  rec.tool == name, rec.hash == hash,
                  Date() < rec.expiresAt else {
                fail(BridgeToolError(
                    code: "confirmation_required",
                    message: "two-stage confirmation "
                        + "required: dryRun first to "
                        + "obtain an actionToken bound "
                        + "to these params"))
                return
            }
            actionTokens.removeValue(forKey: token)
        }
        // 幂等回放（数据写）：同 key 同参数回首次
        // 结果；同 key 异参数回 idempotency_conflict。
        var idemKey: String? = nil
        var idemHash = ""
        if Self.dataWriteTools.contains(name),
           let key = args["idempotencyKey"] as? String,
           !key.isEmpty {
            idemKey = key
            idemHash = Self.paramsHash(args)
            switch BridgeWriteSupport.shared.replay(
                key: key, hash: idemHash) {
            case .hit(let prior):
                var p = prior
                p["ctx"] = ctx
                p["idempotentReplay"] = true
                done(BridgeResult.ok(p), code: "ok")
                return
            case .conflict:
                fail(BridgeToolError(
                    code: "idempotency_conflict",
                    message: "same idempotencyKey with "
                        + "different params"))
                return
            case .miss:
                break
            }
        }
        func ok(_ payload: [String: Any]) {
            var p = payload
            p["ctx"] = ctx
            if Self.dataWriteTools.contains(name) {
                BridgeWriteSupport.shared
                    .recordCompletion(
                        tool: name, idemKey: idemKey,
                        idemHash: idemHash, payload: payload)
            }
            done(BridgeResult.ok(p), code: "ok")
        }
        switch name {
        case "bridge_status":
            ok(BridgeReadTools.bridgeStatus(
                coordinator: coordinator))
        case "app_state":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            ok(BridgeReadTools.appState(library: library))
        case "diag_tail":
            if let p = BridgeReadTools.diagTail(args) {
                ok(p)
            } else {
                fail(.invalidParams("archive not found"))
            }
        case "diag_search":
            switch BridgeReadTools.diagSearch(args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "notes_list":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            ok(BridgeReadTools.notesList(
                args, library: library))
        case "notes_search":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeReadTools.notesSearch(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "notes_get":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeReadTools.notesGet(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "ops_get_effective":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            ok(BridgeOpsTools.opsGetEffective(
                library: library))
        case "ops_refresh":
            BridgeOpsTools.opsRefresh { result in
                switch result {
                case .success(let p): ok(p)
                case .failure(let e): fail(e)
                }
            }
        case "rescue_status":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            ok(BridgeOpsTools.rescueStatus(
                library: library, coordinator: coordinator))
        case "ops_validate":
            switch BridgeOpsTools.opsValidate(args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "rescue_try_normal_start":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeOpsTools.rescueTryNormalStart(
                library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "rescue_arm_safe_mode":
            // 库在位已由 dataWriteTools 前置门守
            // （布防标记落 diag 域，不经库）。
            switch BridgeOpsTools.rescueArmSafeMode(
                args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "settings_get":
            ok(BridgeSettingsTools.settingsGet(
                coordinator: coordinator))
        case "settings_set_language":
            switch BridgeSettingsTools.setLanguage(args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "settings_set_toggle":
            switch BridgeSettingsTools.setToggle(args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "settings_clear_weather_key":
            switch BridgeSettingsTools
                .clearWeatherKey(args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "notes_soft_delete":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeWriteTools.softDelete(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "notes_restore_deleted":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeWriteTools.restoreDeleted(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "notes_delete_permanent":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeWriteTools.deletePermanent(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "editor_delete_block":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeWriteTools.deleteBlock(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "editor_move_block":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeWriteTools.moveBlock(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "editor_open":
            // 导航通道自持接线与只读判定，错误走
            // nav 错误域（nav_unavailable /
            // read_only_mode / memo_not_found /
            // memo_busy / nav_timeout，均已登记
            // 进错误表）。
            BridgeEditorTools.open(
                args, library: library) { result in
                switch result {
                case .success(let p): ok(p)
                case .failure(let e): fail(e)
                }
            }
        case "editor_get_state":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeEditorTools.getState(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "editor_focus_block":
            switch BridgeEditorTools.focusBlock(
                args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "editor_save_now":
            guard let library else {
                fail(.libraryUnavailable); return
            }
            switch BridgeEditorTools.saveNow(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "uitest_list_surfaces":
            ok(BridgeUITestTools.listSurfaces(
                library: library))
        case "uitest_run":
            switch BridgeUITestTools.run(
                args, library: library) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "uitest_get_result":
            switch BridgeUITestTools.getResult(
                args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        case "uitest_measure":
            switch BridgeUITestTools.measure(
                args) {
            case .success(let p): ok(p)
            case .failure(let e): fail(e)
            }
        default:
            fail(BridgeToolError(
                code: "unknown_tool",
                message: "unhandled tool: \(name)"))
        }
    }
}

// ── 只读工具实现 ──

enum BridgeReadTools {

    static func bootModeDict(
        _ library: Library) -> [String: Any] {
        switch library.bootMode {
        case .normal:
            return ["mode": "normal"]
        case .safe(let streak, let step, let source):
            return ["mode": "safe", "streak": streak,
                    "step": step, "source": source]
        }
    }

    static func bridgeStatus(
        coordinator: BridgeCoordinator) -> [String: Any] {
        [
            "enabled": coordinator.enabled,
            "linkState": coordinator.linkState,
            "paired": coordinator.isPaired,
            "scopes": coordinator.scopes,
            "protocolVersion": BridgeProto.protocolVersion,
            "manifestHash": BridgeProto.manifestHash,
            "appSessionId": coordinator.appSessionId,
            "bootSessionId": coordinator.bootSessionId,
            "dispatcherForm": coordinator.dispatcherForm,
            "opsDisabled": coordinator.opsDisabled,
            "relayHost": BridgeProto.relayHost,
            "fingerprint": coordinator.deviceFingerprint ?? "",
        ]
    }

    static func appState(library: Library) -> [String: Any] {
        // 驱动夹具残留顺手扫（只报不删，方案
        // plan_ui_selftest_driver.md §5.1）。
        UITestFixtureSweep.noteOrphans(in: library)
        let info = Bundle.main.infoDictionary ?? [:]
        let scene: String
        switch UIApplication.shared.applicationState {
        case .active: scene = "active"
        case .background: scene = "background"
        case .inactive: scene = "inactive"
        @unknown default: scene = "unknown"
        }
        let activeCount = library.memos
            .filter { $0.deletedAtMs == nil }.count
        return [
            "appVersion": info[
                "CFBundleShortVersionString"] as? String ?? "?",
            "build": info["CFBundleVersion"] as? String ?? "?",
            "bootMode": bootModeDict(library),
            "scene": scene,
            "dbOpen": library.isDbOpen,
            "didLoad": library.didLoad,
            "loadFailed": library.loadFailed,
            "memoCount": activeCount,
            "pendingDeletionCount":
                library.pendingDeletions.count,
            "uitestFixtureOrphans":
                UITestFixtureSweep.orphans(
                    in: library).count,
            "libraryHash": library.libraryHash(),
            "lang": LangStore.shared.code,
            "opsBootApplied": BridgeOpsFormat.setDict(
                library.bootAppliedOps),
        ]
    }

    // ── Diag 读 ──

    private static func levelRank(_ level: String) -> Int {
        switch level {
        case "warn": return 1
        case "error": return 2
        default: return 0
        }
    }

    private static func entryDict(
        _ e: DiagEntry) -> [String: Any] {
        ["ts": Int64(e.ts * 1000), "level": e.level,
         "text": e.text]
    }

    /// scope 解析：today 或指定 stamp 的归档；归档
    /// 不存在回 nil（调用方转 invalid_params）。
    private static func scopedEntries(
        _ args: [String: Any]) -> [DiagEntry]? {
        DiagLog.shared.loadIfNeeded()
        let scope = args["scope"] as? String ?? "today"
        if scope == "archive" {
            guard let stamp = args["archiveStamp"]
                    as? String,
                  let arc = DiagLog.shared.archives
                    .first(where: { $0.stamp == stamp })
            else { return nil }
            return arc.entries
        }
        return DiagLog.shared.today
    }

    /// 字节守卫：整包超上限时从最旧端裁（尾读语义
    /// 保最新），至少留 1 条。
    private static func byteGuard(
        _ entries: [DiagEntry]) -> [DiagEntry] {
        var out = entries
        while out.count > 1 {
            let payload: [String: Any] = [
                "entries": out.map(entryDict),
            ]
            let size = BridgeCanonical.data(payload)?
                .count ?? 0
            if size <= BridgeProto.maxDiagBytes { break }
            out.removeFirst()
        }
        return out
    }

    static func diagTail(
        _ args: [String: Any]) -> [String: Any]? {
        guard let all = scopedEntries(args) else {
            return nil
        }
        let minRank = levelRank(
            args["minLevel"] as? String ?? "all")
        var filtered = all.filter {
            levelRank($0.level) >= minRank
        }
        if let before = (args["beforeTs"] as? NSNumber)?
            .doubleValue {
            filtered = filtered.filter {
                $0.ts * 1000 < before
            }
        }
        let limit = min(200, max(1,
            (args["limit"] as? NSNumber)?.intValue ?? 50))
        let tail = Array(filtered.suffix(limit))
        let guarded = byteGuard(tail)
        var payload: [String: Any] = [
            "scope": args["scope"] as? String ?? "today",
            "entries": guarded.map(entryDict),
            "returned": guarded.count,
        ]
        if guarded.count < filtered.count,
           let first = guarded.first {
            payload["nextBeforeTs"] =
                Int64(first.ts * 1000)
        }
        if let stamp = args["archiveStamp"] as? String {
            payload["archiveStamp"] = stamp
        }
        return payload
    }

    static func diagSearch(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let query = args["query"] as? String,
              !query.isEmpty else {
            return .failure(.invalidParams("query required"))
        }
        guard let all = scopedEntries(args) else {
            return .failure(.invalidParams(
                "archive not found"))
        }
        let limit = min(200, max(1,
            (args["limit"] as? NSNumber)?.intValue ?? 50))
        var matched: [DiagEntry] = []
        if args["regex"] as? Bool == true {
            guard query.count <= 200,
                  let re = try? NSRegularExpression(
                    pattern: query) else {
                return .failure(.invalidParams(
                    "bad regex"))
            }
            matched = all.filter {
                re.firstMatch(
                    in: $0.text,
                    range: NSRange(
                        location: 0,
                        length: $0.text.utf16.count)) != nil
            }
        } else {
            matched = all.filter { $0.text.contains(query) }
        }
        let total = matched.count
        let page = byteGuard(Array(matched.suffix(limit)))
        return .success([
            "scope": args["scope"] as? String ?? "today",
            "query": query,
            "totalMatched": total,
            "entries": page.map(entryDict),
            "returned": page.count,
        ])
    }

    // ── 笔记读 ──

    /// 全集（memos + 待删集补遗，按 id 去重）。
    /// 写面（BridgeWriteTools，同文件）共用。
    static func allMemos(
        _ library: Library) -> [MemoItem] {
        var out: [MemoItem] = []
        var seen = Set<String>()
        for m in library.memos
        where seen.insert(m.id).inserted {
            out.append(m)
        }
        for (_, pair) in library.pendingDeletions
        where seen.insert(pair.item.id).inserted {
            out.append(pair.item)
        }
        return out
    }

    static func memoSummary(
        _ item: MemoItem) -> [String: Any] {
        var s: [String: Any] = [
            "id": item.id,
            "title": item.title,
            "pinned": item.pinned,
            "createdAt": item.createdAt,
            "updatedAt": item.updatedAt,
            "blockCount": item.blocks.count,
            "snippet": item.snippet,
            "docHash": BridgeDocHash.of(item) ?? "",
        ]
        if let d = item.deletedAtMs {
            s["deletedAt"] = d
        }
        return s
    }

    static func notesList(
        _ args: [String: Any],
        library: Library) -> [String: Any] {
        let includeDeleted = args["includeDeleted"]
            as? Bool ?? false
        var items = allMemos(library)
        if !includeDeleted {
            items = items.filter {
                $0.deletedAtMs == nil
                    && library.pendingDeletions[$0.id] == nil
            }
        }
        let limit = min(100, max(1,
            (args["limit"] as? NSNumber)?.intValue ?? 20))
        let offset = max(0, Int(
            args["cursor"] as? String ?? "0") ?? 0)
        let page = Array(items.dropFirst(offset)
            .prefix(limit))
        var payload: [String: Any] = [
            "items": page.map(memoSummary),
            "total": items.count,
        ]
        if offset + page.count < items.count {
            payload["nextCursor"] =
                String(offset + page.count)
        }
        return payload
    }

    static func notesSearch(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let query = args["query"] as? String,
              !query.trimmingCharacters(
                in: .whitespaces).isEmpty else {
            return .failure(.invalidParams("query required"))
        }
        guard let ids = library.bridgeSearchIds(query)
        else {
            return .failure(.libraryUnavailable)
        }
        let limit = min(100, max(1,
            (args["limit"] as? NSNumber)?.intValue ?? 20))
        let byId = Dictionary(
            uniqueKeysWithValues: allMemos(library)
                .map { ($0.id, $0) })
        let items = ids.prefix(limit)
            .compactMap { byId[$0] }
        return .success([
            "items": items.map(memoSummary),
            "totalMatched": ids.count,
        ])
    }

    static func notesGet(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let id = args["id"] as? String,
              !id.isEmpty else {
            return .failure(.invalidParams("id required"))
        }
        guard let item = allMemos(library)
            .first(where: { $0.id == id }) else {
            return .failure(BridgeToolError(
                code: "note_not_found",
                message: "no memo with id \(id)"))
        }
        let offset = max(0,
            (args["blockCursor"] as? NSNumber)?.intValue ?? 0)
        let maxBlocks = min(100, max(1,
            (args["maxBlocks"] as? NSNumber)?.intValue ?? 50))
        let blocks = Array(item.blocks.dropFirst(offset)
            .prefix(maxBlocks))
        var payload = memoSummary(item)
        payload["blocks"] = blocks.enumerated().map {
            (i, b) in blockDict(b, index: offset + i)
        }
        if offset + blocks.count < item.blocks.count {
            payload["nextBlockCursor"] =
                offset + blocks.count
        }
        return .success(payload)
    }

    /// 块回读形态：文本块回正文/runs/勾选；列表块
    /// 回子项文本；原子块只回类型 + attrs 元信息
    /// （附件只到 fileId/url/name 一层，不回字节）。
    private static func blockDict(
        _ b: BlockState, index: Int) -> [String: Any] {
        var d: [String: Any] = [
            "id": b.id, "index": index, "type": b.type,
        ]
        if b.isText {
            d["text"] = b.text
            if b.type == "todo" { d["checked"] = b.checked }
            if b.type == "heading" { d["level"] = b.level }
            let flushed = b.flushedNode()
            if let runs = flushed["runs"] {
                d["runs"] = runs
            }
        } else if b.isList {
            d["items"] = b.itemStates.map {
                ["id": $0.id, "text": $0.text,
                 "checked": $0.checked] as [String: Any]
            }
        } else {
            let flushed = b.flushedNode()
            let attrs = flushed["attrs"]
                as? [String: Any] ?? [:]
            d["attrs"] = attrs
            if let items = attrs["items"]
                as? [[String: Any]] {
                d["items"] = items.map { it in
                    var m: [String: Any] = [:]
                    for k in ["fileId", "url", "name"]
                    where it[k] is String {
                        m[k] = it[k]
                    }
                    return m
                }
            }
        }
        return d
    }
}

/// docHash：persist 同构的落盘文档（raw 为底、
/// 已知键覆写、doc 键 = flushedNode 序）作规范
/// JSON 的 sha256——与 App 内实际落盘字节口径一
/// 致，写前校验（M2 expectedDocHash）同源。
enum BridgeDocHash {
    static func of(_ item: MemoItem) -> String? {
        var doc = item.raw
        doc["id"] = item.id
        doc["title"] = item.title
        doc["pinned"] = item.pinned
        doc["createdAt"] = item.createdAt
        doc["updatedAt"] = item.updatedAt
        doc["doc"] = item.blocks.map { $0.flushedNode() }
        return BridgeCanonical.sha256Hex(doc)
    }
}

// ── 写安全底座：快照 + 幂等 + 操作流水（M2）──
// 方案 §9.3 的落点（原规划独立文件 MomentBridge
// Snapshots.swift；本轮并行边界只许动桥六文件，
// 先并入本文件，拆分随主线组版批处理，见
// impl_bridge_m2.md）。

final class BridgeWriteSupport {
    static let shared = BridgeWriteSupport()

    private var replayStore: [String: (
        hash: String, result: [String: Any])] = [:]
    /// 写会话快照复用（会话 = 同一 idempotencyKey
    /// 前缀的一批连续调用，方案 §9.3 触发点口径）。
    private var sessionSnapshots: [String: String] = [:]

    enum Replay {
        case hit([String: Any])
        case conflict
        case miss
    }

    func replay(key: String, hash: String) -> Replay {
        guard let rec = replayStore[key] else {
            return .miss
        }
        return rec.hash == hash
            ? .hit(rec.result) : .conflict
    }

    /// 快照目录：Application Support/bridge-
    /// snapshots/（与资料库同域、独立目录，不进
    /// 用户备份 ZIP、不进 Diag 域）。
    var snapshotsDir: String {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)[0]
        let d = base.appendingPathComponent(
            "bridge-snapshots").path
        try? FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: true)
        return d
    }

    /// 写前快照：以只读 FFI 句柄直调 exportBackup
    /// （存储层导出是纯读查询 + 写 zip 文件，不触
    /// 碰库写面；与在席写句柄并存安全）——不走
    /// Library.exportZip，不更新 lastExportTs、
    /// 不记备份操作记录，不污染用户备份新鲜度口
    /// 径（方案 §9.3）。失败回 snapshot_failed，
    /// 调用方必须中止写。
    func takeSnapshot(
        library: Library, reason: String
    ) -> Result<String, BridgeToolError> {
        guard library.isDbOpen else {
            return .failure(.libraryUnavailable)
        }
        let dir = snapshotsDir
        let id = "snap-\(Library.epochMs())-"
            + String(UUID().uuidString.prefix(6))
                .lowercased()
        let path = dir + "/" + id + ".zip"
        do {
            let ro = try MomentLibrary.openReadonly(
                path: library.storeDir + "/moment.db")
            try ro.exportBackup(zipPath: path)
        } catch {
            DiagLog.shared.log(.error,
                "BRIDGE snapshot failed reason=\(reason) "
                + "err=\(error)")
            return .failure(BridgeToolError(
                code: "snapshot_failed",
                message: "pre-write snapshot failed: "
                    + "\(error)"))
        }
        var bytes: Int64 = -1
        if let attrs = try? FileManager.default
            .attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            bytes = size.int64Value
        }
        appendManifest(id: id, reason: reason,
                       library: library, bytes: bytes)
        pruneSnapshots()
        DiagLog.shared.log(.info,
            "BRIDGE snapshot id=\(id) reason=\(reason) "
            + "bytes=\(bytes)")
        return .success(id)
    }

    /// 会话级快照：同前缀只在首个写操作前生成一
    /// 份；force 时（如永久删除）每次强制新生成。
    func ensureSnapshot(
        library: Library, args: [String: Any],
        reason: String, force: Bool
    ) -> Result<String, BridgeToolError> {
        if !force,
           let key = args["idempotencyKey"] as? String,
           !key.isEmpty {
            let prefix = String(key.split(
                separator: ":", maxSplits: 1).first
                ?? Substring(key))
            if let existing = sessionSnapshots[prefix] {
                return .success(existing)
            }
            let r = takeSnapshot(
                library: library, reason: reason)
            if case .success(let id) = r {
                sessionSnapshots[prefix] = id
            }
            return r
        }
        return takeSnapshot(library: library,
                            reason: reason)
    }

    private struct SnapshotEntry {
        var id: String
        var atMs: Int64
        var reason: String
        var preHash: String
        var memoCount: Int
        var bytes: Int64
    }

    private var manifestPath: String {
        snapshotsDir + "/manifest.json"
    }

    private func loadManifest() -> [SnapshotEntry] {
        guard let data = try? Data(contentsOf:
                URL(fileURLWithPath: manifestPath)),
              let obj = try? JSONSerialization
                .jsonObject(with: data)
                as? [String: Any],
              let arr = obj["snapshots"]
                as? [[String: Any]]
        else { return [] }
        return arr.map {
            SnapshotEntry(
                id: $0["id"] as? String ?? "",
                atMs: ($0["atMs"] as? NSNumber)?
                    .int64Value ?? 0,
                reason: $0["reason"] as? String ?? "",
                preHash: $0["preHash"] as? String ?? "",
                memoCount: ($0["memoCount"]
                    as? NSNumber)?.intValue ?? 0,
                bytes: ($0["bytes"] as? NSNumber)?
                    .int64Value ?? 0)
        }
    }

    private func saveManifest(_ entries: [SnapshotEntry]) {
        let obj: [String: Any] = ["snapshots": entries
            .map {
                [
                    "id": $0.id, "atMs": $0.atMs,
                    "reason": $0.reason,
                    "preHash": $0.preHash,
                    "memoCount": $0.memoCount,
                    "bytes": $0.bytes,
                ] as [String: Any]
            }]
        if let data = try? JSONSerialization.data(
            withJSONObject: obj) {
            try? data.write(
                to: URL(fileURLWithPath: manifestPath),
                options: .atomic)
        }
    }

    private func appendManifest(
        id: String, reason: String,
        library: Library, bytes: Int64) {
        var entries = loadManifest()
        entries.append(SnapshotEntry(
            id: id, atMs: Library.epochMs(),
            reason: reason,
            preHash: library.libraryHash(),
            memoCount: library.memos.filter {
                $0.deletedAtMs == nil
            }.count,
            bytes: bytes))
        saveManifest(entries)
    }

    /// 保留策略：最近 10 份且不超过 7 天，超限删
    /// 旧（zip + 清单条目）并记 Diag。
    private func pruneSnapshots() {
        var entries = loadManifest()
        let cutoff = Library.epochMs() - 7 * 86_400_000
        var kept: [SnapshotEntry] = []
        var dropped: [SnapshotEntry] = []
        let sorted = entries.sorted {
            $0.atMs > $1.atMs
        }
        for (i, e) in sorted.enumerated() {
            if i < 10 && e.atMs >= cutoff {
                kept.append(e)
            } else {
                dropped.append(e)
            }
        }
        guard !dropped.isEmpty else { return }
        for e in dropped {
            try? FileManager.default.removeItem(
                atPath: snapshotsDir + "/" + e.id
                    + ".zip")
            DiagLog.shared.log(.info,
                "BRIDGE snapshot pruned id=\(e.id)")
        }
        entries = kept.sorted { $0.atMs < $1.atMs }
        saveManifest(entries)
    }

    /// 写完成收口：幂等结果登记 + 操作流水追加
    /// （只记元数据，不记正文/参数全文）+ BRIDGE
    /// write 结果行（方案 §9.5 口径）。
    func recordCompletion(
        tool: String, idemKey: String?,
        idemHash: String, payload: [String: Any]) {
        if let idemKey {
            replayStore[idemKey] = (
                hash: idemHash, result: payload)
        }
        var line: [String: Any] = [
            "ts": Library.epochMs(),
            "tool": tool, "code": "ok",
        ]
        if let idemKey {
            line["keyHash"] = String(BridgeHash
                .sha256Hex(Data(idemKey.utf8))
                .prefix(16))
        }
        if let t = payload["targetId"] as? String {
            line["target"] = t
        }
        if let p = payload["preDocHash"] as? String {
            line["pre"] = String(p.prefix(12))
        }
        if let p = payload["postDocHash"] as? String {
            line["post"] = String(p.prefix(12))
        }
        if let s = payload["snapshotId"] as? String {
            line["snap"] = s
        }
        if let text = BridgeJSON.stringify(line) {
            let path = snapshotsDir
                + "/operations.jsonl"
            let data = Data((text + "\n").utf8)
            if let fh = FileHandle(
                forWritingAtPath: path) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
            } else {
                try? data.write(
                    to: URL(fileURLWithPath: path))
            }
        }
        if let target = payload["targetId"] as? String {
            let pre = (payload["preDocHash"]
                as? String).map {
                    String($0.prefix(12)) } ?? "-"
            let post = (payload["postDocHash"]
                as? String).map {
                    String($0.prefix(12)) } ?? "-"
            let snap = payload["snapshotId"]
                as? String ?? "-"
            DiagLog.shared.log(.info,
                "BRIDGE write tool=\(tool) "
                + "target=\(target) pre=\(pre) "
                + "post=\(post) snap=\(snap)")
        }
    }
}

// ── 数据/结构写工具（M2）──
// 删除系走 Library 现行软删/撤销/到期真删同路；
// 块级结构写（删块/移块）走 Library 文档路径：
// 以 flushedNode 规范形重组块序 → Library
// .persist 落盘 → 回读校验。口径注记：目标篇正
// 在编辑器中打开时，编辑器持有独立的块状态副
// 本，其下一次保存会以编辑器态为准覆盖本路径
// 结果——在席检测（memo_busy）已随 U0 地基接
// 线（EditorSeatRegistry，见 BridgeEditorSeat
// .seatedConflict：在席即拒），docHash 守卫 +
// 写后回读仍作第二道保底；U0 定案 impl_uitest
// _u0.md。正文级写（新建/插块/改块/类型转换）
// 不在本批：待端到端加密专项评审裁定。

// ── 在席冲突判定（U0 地基的消费点）──
// 目标篇正在编辑器中打开时，编辑器持有独立的块
// 状态副本，其后任何一次保存（防抖/saveNow）都
// 以编辑器态整篇落盘——文档路径此刻的写入必然
// 被覆盖，故在席即回 memo_busy（不分脏净；补救
// 是关编辑器，不是 editor_save_now：在席不因落
// 盘而解除）。消费点三处：删块/移块（文档路径
// 写被覆盖）、软删（U1 补齐：在席篇被软删后，
// 编辑器下一次保存以其副本 persist 回列表 =
// 复活面，与块写同型）。恢复/永删不设守卫：其
// 目标恒在待删集，而待删集与在席恒不相交——
// softRemove 把篇移出 memos，在席登记只可能源
// 于 memos 在册篇的打开路径（列表/关联/导航通
// 道查册同口径），且一切软删路径（列表滑动、
// 本守卫后的桥软删、驱动清理[先关编辑器]）都
// 不会在篇在席时把它送进待删集（U1 逐路核
// 对，见 impl_uitest_u1.md）。dirty 只作消息注
// 记：编辑器活态与落盘态的规范形比对（标题/块
// 序/bgColor/layout，与 docHash 同口径）。
enum BridgeEditorSeat {

    static func seatedConflict(
        memoId: String, library: Library,
        purpose: String
    ) -> BridgeToolError? {
        let seat = EditorSeatRegistry.shared
        guard let editor = seat.currentEditor,
              seat.currentMemoId == memoId else {
            return nil
        }
        let dirty = isDiverged(editor: editor,
                               library: library)
        return BridgeToolError(
            code: "memo_busy",
            message: "memo \(memoId) is open in the "
                + "editor (dirty=\(dirty ? 1 : 0)); "
                + "close the editor before "
                + "\(purpose)")
    }

    /// 编辑器活态 vs 落盘态分叉判定（规范 JSON 哈
    /// 希比对）。落盘态以 Library 当前在册条目为
    /// 准（persist 后同步更新）。
    static func isDiverged(editor: EditorModel,
                           library: Library) -> Bool {
        guard let stored = library.memos.first(
            where: { $0.id == editor.item.id })
        else { return true }
        if editor.title != stored.title { return true }
        let liveBg = editor.bgColor ?? ""
        let storedBg = stored.raw["bgColor"]
            as? String ?? ""
        if liveBg != storedBg { return true }
        let liveNodes = editor.blocks.map {
            $0.flushedNode()
        }
        let storedNodes = stored.blocks.map {
            $0.flushedNode()
        }
        if BridgeCanonical.sha256Hex(liveNodes)
            != BridgeCanonical.sha256Hex(storedNodes) {
            return true
        }
        let liveLayout = editor.layout.flatMap {
            BridgeCanonical.sha256Hex($0)
        } ?? ""
        let storedLayout = (stored.raw["layout"]
            as? [String: Any]).flatMap {
            BridgeCanonical.sha256Hex($0)
        } ?? ""
        return liveLayout != storedLayout
    }
}

// ── 编辑器在席工具（U1 入册）──
// 地基是 U0 的在席注册表 + 导航通道（见
// impl_uitest_u0.md），本批只做分发组装：
// open 走导航通道（错误原样带出 nav 错误域，
// 两码 nav_unavailable/nav_timeout 随本批正
// 式登记进错误表——BPROTO 登记注记、中继描
// 述、连接器 CONNECTOR.md 三方同步）；
// get_state 只出结构（块 id+type 序）不出正
// 文摘要——桥方案 §5.3 的「文本摘要」与 M2
// 期定下的正文红线（块级工具只载 id/序号/哈
// 希）冲突时以后者为准，摘要不入回包（主线
// 裁认口径，见 impl_uitest_u1.md）。
enum BridgeEditorTools {

    static func navError(
        _ e: BridgeNavError) -> BridgeToolError {
        switch e {
        case .navUnavailable:
            return BridgeToolError(
                code: "nav_unavailable",
                message: "navigation channel not "
                    + "wired (list not in the "
                    + "hierarchy / safe mode)",
                retryable: true)
        case .readOnlyMode:
            return BridgeToolError(
                code: "read_only_mode",
                message: "library is open "
                    + "read-only; editor cannot "
                    + "persist")
        case .memoNotFound(let id):
            return BridgeToolError(
                code: "memo_not_found",
                message: "no memo with id \(id) "
                    + "(or soft-deleted / pending)")
        case .seatOccupied(let id):
            return BridgeToolError(
                code: "memo_busy",
                message: "memo \(id) is open in "
                    + "the editor")
        case .seatTimeout:
            return BridgeToolError(
                code: "nav_timeout",
                message: "timed out waiting for "
                    + "the editor seat to settle",
                retryable: true)
        }
    }

    /// 在席状态回包（editor_open 的返回即
    /// editor_get_state 形态，方案 §5.3）。
    static func seatDict(
        _ snap: EditorSeatSnapshot,
        library: Library?) -> [String: Any] {
        var d: [String: Any] = [
            "seated": true,
            "memoId": snap.memoId,
            "title": snap.title,
            "focusBlockId": snap.focusBlockId
                ?? NSNull(),
            "editingBlockId": snap.editingBlockId
                ?? NSNull(),
            "draggingId": snap.draggingId
                ?? NSNull(),
            "blocks": zip(snap.blockIds,
                          snap.blockTypes).map {
                ["id": $0.0, "type": $0.1]
                    as [String: Any]
            },
            "columnsActive": snap.columnsActive,
        ]
        if let library,
           let editor = EditorSeatRegistry.shared
            .currentEditor {
            d["dirty"] = BridgeEditorSeat
                .isDiverged(editor: editor,
                            library: library)
        }
        return d
    }

    static func open(
        _ args: [String: Any], library: Library?,
        completion: @escaping (
            Result<[String: Any], BridgeToolError>)
            -> Void) {
        guard let memoId = args["memoId"]
                as? String, !memoId.isEmpty else {
            completion(.failure(.invalidParams(
                "memoId required")))
            return
        }
        BridgeNavigationChannel.shared.requestOpen(
            memoId: memoId) { result in
            switch result {
            case .success(let snap):
                completion(.success(seatDict(
                    snap, library: library)))
            case .failure(let e):
                completion(.failure(navError(e)))
            }
        }
    }

    static func getState(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        let seat = EditorSeatRegistry.shared
        guard let snap = seat.snapshot() else {
            if let want = args["memoId"] as? String,
               !want.isEmpty {
                return .failure(BridgeToolError(
                    code: "nav_unavailable",
                    message: "no editor is open"))
            }
            return .success(["seated": false])
        }
        if let want = args["memoId"] as? String,
           !want.isEmpty, want != snap.memoId {
            return .failure(BridgeToolError(
                code: "memo_busy",
                message: "memo \(snap.memoId) is "
                    + "open in the editor, not "
                    + "\(want)"))
        }
        return .success(seatDict(
            snap, library: library))
    }

    /// 在席归属校验（focus_block/save_now 共
    /// 用）：无在席 → nav_unavailable；在席他篇
    /// → memo_busy（消息点名在席篇）。
    private static func requireSeat(
        _ memoId: String) -> BridgeToolError? {
        let seat = EditorSeatRegistry.shared
        guard let cur = seat.currentMemoId else {
            return BridgeToolError(
                code: "nav_unavailable",
                message: "no editor is open")
        }
        guard cur == memoId else {
            return BridgeToolError(
                code: "memo_busy",
                message: "memo \(cur) is open in "
                    + "the editor, not \(memoId)")
        }
        return nil
    }

    static func focusBlock(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let memoId = args["memoId"]
                as? String, !memoId.isEmpty else {
            return .failure(.invalidParams(
                "memoId required"))
        }
        guard let blockId = args["blockId"]
                as? String, !blockId.isEmpty else {
            return .failure(.invalidParams(
                "blockId required"))
        }
        if let e = requireSeat(memoId) {
            return .failure(e)
        }
        // caret 口径（方案 §5.3 的 end/offset）：
        // 在席落焦地基只有块尾/块首两态（编辑器
        // 内既有落焦同字段 focusCaretEnd），
        // offset 数值位不设第二口径——缺省与
        // "end" 落块尾、"start" 落块首，其余值
        // 明确拒绝不假装。
        let caretEnd: Bool
        switch args["caret"] as? String {
        case nil, "end": caretEnd = true
        case "start": caretEnd = false
        default:
            return .failure(.invalidParams(
                "caret must be end or start"))
        }
        guard EditorSeatRegistry.shared.focusBlock(
            blockId, caretEnd: caretEnd) else {
            return .failure(BridgeToolError(
                code: "block_not_found",
                message: "no block with id "
                    + "\(blockId) in the open memo"))
        }
        return .success([
            "memoId": memoId,
            "focusBlockId": blockId,
            "caretEnd": caretEnd,
        ])
    }

    static func saveNow(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let memoId = args["memoId"]
                as? String, !memoId.isEmpty else {
            return .failure(.invalidParams(
                "memoId required"))
        }
        if let e = requireSeat(memoId) {
            return .failure(e)
        }
        guard EditorSeatRegistry.shared.saveNow()
        else {
            return .failure(BridgeToolError(
                code: "nav_unavailable",
                message: "no editor is open"))
        }
        // 落盘后回读对账（方案 §5.3）：以资料
        // 库镜像的 docHash/libraryHash 为准，
        // verifyStore 计数对照附带回读。
        guard let after = library.memos.first(
            where: { $0.id == memoId }) else {
            return .failure(BridgeToolError(
                code: "write_outcome_unknown",
                message: "memo missing from the "
                    + "library mirror after save",
                retryable: true))
        }
        var payload: [String: Any] = [
            "memoId": memoId,
            "targetId": memoId,
            "docHash": BridgeDocHash.of(after)
                ?? "",
            "libraryHash": library.libraryHash(),
        ]
        if let editor = EditorSeatRegistry.shared
            .currentEditor {
            payload["dirty"] = BridgeEditorSeat
                .isDiverged(editor: editor,
                            library: library)
        }
        if let store = library.verifyStore() {
            payload["storeMemoCount"] = store.count
        }
        return .success(payload)
    }
}

enum BridgeWriteTools {

    static func memoNotFound(
        _ id: String) -> BridgeToolError {
        BridgeToolError(code: "memo_not_found",
                        message: "no memo with id \(id)")
    }

    /// doc 守卫三件套：memoId/idempotencyKey/
    /// expectedDocHash 必填校验 + 目标查找 +
    /// 哈希比对（不匹配回 revision_conflict）。
    private static func guardedMemo(
        _ args: [String: Any], library: Library
    ) -> Result<(MemoItem, String), BridgeToolError> {
        guard let id = args["memoId"] as? String,
              !id.isEmpty else {
            return .failure(.invalidParams(
                "memoId required"))
        }
        guard let key = args["idempotencyKey"]
                as? String, !key.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        guard let expected = args["expectedDocHash"]
                as? String, !expected.isEmpty else {
            return .failure(.invalidParams(
                "expectedDocHash required"))
        }
        guard let item = BridgeReadTools.allMemos(
            library).first(where: { $0.id == id })
        else { return .failure(memoNotFound(id)) }
        let pre = BridgeDocHash.of(item) ?? ""
        guard expected == pre else {
            return .failure(BridgeToolError(
                code: "revision_conflict",
                message: "expectedDocHash mismatch; "
                    + "re-read with notes_get first"))
        }
        return .success((item, pre))
    }

    static func softDelete(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        let item: MemoItem
        let pre: String
        switch guardedMemo(args, library: library) {
        case .success(let v): (item, pre) = v
        case .failure(let e): return .failure(e)
        }
        if item.deletedAtMs != nil
            || library.pendingDeletions[item.id] != nil {
            return .failure(.invalidParams(
                "memo already soft-deleted: \(item.id)"))
        }
        // 在席守卫（U1 补齐，主线裁定在席即拒）：
        // 在席篇软删后，编辑器下一次保存会以其
        // 副本整篇 persist 回列表——软删被静默
        // 复活，与块写的覆盖面同型、同守卫。
        if let busy = BridgeEditorSeat.seatedConflict(
            memoId: item.id, library: library,
            purpose: "soft-deleting a memo the "
                + "editor holds") {
            return .failure(busy)
        }
        let snap: String
        switch BridgeWriteSupport.shared.ensureSnapshot(
            library: library, args: args,
            reason: "notes_soft_delete", force: false) {
        case .success(let s): snap = s
        case .failure(let e): return .failure(e)
        }
        library.softRemove(item)
        guard let pending = library
            .pendingDeletions[item.id] else {
            return .failure(BridgeToolError(
                code: "write_outcome_unknown",
                message: "soft delete did not register "
                    + "in the pending set",
                retryable: true))
        }
        return .success([
            "id": item.id, "targetId": item.id,
            "deletedAtMs": pending.atMs,
            "undoExpiresAtMs": pending.atMs
                + Library.undoWindowMs,
            "snapshotId": snap,
            "preDocHash": pre,
            // 待删态哈希含 deletedAt 键，与 pre 不同
            // （同 deletePermanent 的口径注记）。
            "postDocHash": BridgeDocHash
                .of(pending.item) ?? pre,
        ])
    }

    /// 恢复：只支持待删集中最近一篇（现行
    /// Library.undoDeletion 口径，方案 §5.5 明示
    /// 的受限形态）；在册但非最近一篇回
    /// restore_unsupported，不假成功。
    static func restoreDeleted(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let id = args["memoId"] as? String,
              !id.isEmpty else {
            return .failure(.invalidParams(
                "memoId required"))
        }
        guard let key = args["idempotencyKey"]
                as? String, !key.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        guard library.pendingDeletions[id] != nil
        else { return .failure(memoNotFound(id)) }
        guard library.pendingDeletion?.id == id else {
            return .failure(BridgeToolError(
                code: "restore_unsupported",
                message: "only the most recent pending "
                    + "deletion can be restored; "
                    + "target is pending but not latest"))
        }
        let snap: String
        switch BridgeWriteSupport.shared.ensureSnapshot(
            library: library, args: args,
            reason: "notes_restore_deleted",
            force: false) {
        case .success(let s): snap = s
        case .failure(let e): return .failure(e)
        }
        library.undoDeletion()
        guard library.pendingDeletions[id] == nil,
              let after = library.memos.first(
                where: { $0.id == id }) else {
            return .failure(BridgeToolError(
                code: "write_outcome_unknown",
                message: "restore did not take effect",
                retryable: true))
        }
        var payload = BridgeReadTools.memoSummary(after)
        payload["targetId"] = id
        payload["snapshotId"] = snap
        payload["postDocHash"] =
            BridgeDocHash.of(after) ?? ""
        return .success(payload)
    }

    /// 永久删除（ops + 两段提交，分发器已验令
    /// 牌）：仅限待删集内备忘；强制单独快照；
    /// 真删走 Library.commitPendingDeletion 同路。
    static func deletePermanent(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let id = args["memoId"] as? String,
              !id.isEmpty else {
            return .failure(.invalidParams(
                "memoId required"))
        }
        guard let key = args["idempotencyKey"]
                as? String, !key.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        guard args["confirmMemoId"] as? String == id
        else {
            return .failure(BridgeToolError(
                code: "confirmation_required",
                message: "confirmMemoId must repeat "
                    + "memoId verbatim"))
        }
        guard let pending = library
            .pendingDeletions[id] else {
            if BridgeReadTools.allMemos(library)
                .contains(where: { $0.id == id }) {
                return .failure(.invalidParams(
                    "memo is active; permanent delete "
                    + "only accepts memos already "
                    + "soft-deleted (pending set)"))
            }
            return .failure(memoNotFound(id))
        }
        // 待删态的 docHash 含 deletedAt 键，与软删
        // 前的哈希不同——调用方须以待删态回读值
        // 为准（notes_list includeDeleted/notes_get）。
        let pre = BridgeDocHash.of(pending.item) ?? ""
        guard let expected = args["expectedDocHash"]
                as? String, !expected.isEmpty else {
            return .failure(.invalidParams(
                "expectedDocHash required"))
        }
        guard expected == pre else {
            return .failure(BridgeToolError(
                code: "revision_conflict",
                message: "expectedDocHash mismatch; "
                    + "re-read the pending memo first"))
        }
        let snap: String
        switch BridgeWriteSupport.shared.ensureSnapshot(
            library: library, args: args,
            reason: "notes_delete_permanent",
            force: true) {
        case .success(let s): snap = s
        case .failure(let e): return .failure(e)
        }
        library.commitPendingDeletion(id: id)
        guard library.pendingDeletions[id] == nil,
              !BridgeReadTools.allMemos(library)
                .contains(where: { $0.id == id }) else {
            return .failure(BridgeToolError(
                code: "write_outcome_unknown",
                message: "permanent delete did not "
                    + "take effect", retryable: true))
        }
        return .success([
            "id": id, "targetId": id,
            "deleted": true,
            "snapshotId": snap,
            "preDocHash": pre, "postDocHash": "",
        ])
    }

    /// 块级结构写的重组落盘共用路：规范节点数组
    /// 经变换后以 BlockState 重建、Library
    /// .persist 落盘、回读块序校验。
    private static func persistBlocks(
        item: MemoItem, nodes: [[String: Any]],
        library: Library
    ) -> Result<(MemoItem, String), BridgeToolError> {
        var newItem = item
        newItem.blocks = nodes.map { BlockState(node: $0) }
        library.persist(newItem)
        guard let after = library.memos.first(
            where: { $0.id == item.id }) else {
            return .failure(BridgeToolError(
                code: "write_outcome_unknown",
                message: "persist did not reflect in "
                    + "the library mirror",
                retryable: true))
        }
        let post = BridgeDocHash.of(after) ?? ""
        return .success((after, post))
    }

    static func deleteBlock(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        let item: MemoItem
        let pre: String
        switch guardedMemo(args, library: library) {
        case .success(let v): (item, pre) = v
        case .failure(let e): return .failure(e)
        }
        guard item.deletedAtMs == nil else {
            return .failure(.invalidParams(
                "memo is soft-deleted: \(item.id)"))
        }
        guard let blockId = args["blockId"] as? String,
              !blockId.isEmpty else {
            return .failure(.invalidParams(
                "blockId required"))
        }
        if let busy = BridgeEditorSeat.seatedConflict(
            memoId: item.id, library: library,
            purpose: "block writes on the library "
                + "path") {
            return .failure(busy)
        }
        var nodes = item.blocks.map { $0.flushedNode() }
        guard let idx = nodes.firstIndex(where: {
            ($0["id"] as? String) == blockId
        }) else {
            return .failure(BridgeToolError(
                code: "block_not_found",
                message: "no block with id \(blockId)"))
        }
        let removed = nodes.remove(at: idx)
        let snap: String
        switch BridgeWriteSupport.shared.ensureSnapshot(
            library: library, args: args,
            reason: "editor_delete_block", force: false) {
        case .success(let s): snap = s
        case .failure(let e): return .failure(e)
        }
        switch persistBlocks(item: item, nodes: nodes,
                             library: library) {
        case .failure(let e):
            return .failure(e)
        case .success(let (after, post)):
            guard !after.blocks.contains(
                where: { $0.id == blockId }) else {
                return .failure(BridgeToolError(
                    code: "write_outcome_unknown",
                    message: "block still present "
                        + "after delete",
                    retryable: true))
            }
            return .success([
                "memoId": item.id, "targetId": item.id,
                "deletedBlock": [
                    "id": blockId,
                    "type": removed["type"]
                        as? String ?? "",
                    "index": idx,
                ],
                "blockOrder": after.blocks.map { $0.id },
                "docHash": post,
                "preDocHash": pre, "postDocHash": post,
                "snapshotId": snap,
            ])
        }
    }

    static func moveBlock(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        let item: MemoItem
        let pre: String
        switch guardedMemo(args, library: library) {
        case .success(let v): (item, pre) = v
        case .failure(let e): return .failure(e)
        }
        guard item.deletedAtMs == nil else {
            return .failure(.invalidParams(
                "memo is soft-deleted: \(item.id)"))
        }
        guard let blockId = args["blockId"] as? String,
              !blockId.isEmpty else {
            return .failure(.invalidParams(
                "blockId required"))
        }
        if let busy = BridgeEditorSeat.seatedConflict(
            memoId: item.id, library: library,
            purpose: "block writes on the library "
                + "path") {
            return .failure(busy)
        }
        if args["targetColumn"] != nil {
            return .failure(.invalidParams(
                "targetColumn is not supported on "
                + "the library document path"))
        }
        var nodes = item.blocks.map { $0.flushedNode() }
        guard let from = nodes.firstIndex(where: {
            ($0["id"] as? String) == blockId
        }) else {
            return .failure(BridgeToolError(
                code: "block_not_found",
                message: "no block with id \(blockId)"))
        }
        let moving = nodes.remove(at: from)
        let insertAt: Int
        if let to = (args["toIndex"] as? NSNumber)?
            .intValue {
            insertAt = min(max(0, to), nodes.count)
        } else if let before = args["beforeBlockId"]
            as? String {
            guard let t = nodes.firstIndex(where: {
                ($0["id"] as? String) == before
            }) else {
                return .failure(BridgeToolError(
                    code: "block_not_found",
                    message: "no block with id \(before)"))
            }
            insertAt = t
        } else if let after = args["afterBlockId"]
            as? String {
            guard let t = nodes.firstIndex(where: {
                ($0["id"] as? String) == after
            }) else {
                return .failure(BridgeToolError(
                    code: "block_not_found",
                    message: "no block with id \(after)"))
            }
            insertAt = t + 1
        } else {
            return .failure(.invalidParams(
                "one of toIndex/beforeBlockId/"
                + "afterBlockId is required"))
        }
        nodes.insert(moving, at: insertAt)
        let expectedOrder = nodes.map {
            $0["id"] as? String ?? ""
        }
        let snap: String
        switch BridgeWriteSupport.shared.ensureSnapshot(
            library: library, args: args,
            reason: "editor_move_block", force: false) {
        case .success(let s): snap = s
        case .failure(let e): return .failure(e)
        }
        switch persistBlocks(item: item, nodes: nodes,
                             library: library) {
        case .failure(let e):
            return .failure(e)
        case .success(let (after, post)):
            let order = after.blocks.map { $0.id }
            guard order == expectedOrder else {
                return .failure(BridgeToolError(
                    code: "write_outcome_unknown",
                    message: "block order mismatch "
                        + "after move", retryable: true))
            }
            return .success([
                "memoId": item.id, "targetId": item.id,
                "blockId": blockId,
                "fromIndex": from,
                "toIndex": insertAt,
                "blockOrder": order,
                "docHash": post,
                "preDocHash": pre, "postDocHash": post,
                "snapshotId": snap,
            ])
        }
    }
}

// ── 设置读/写工具（M2）──
// 天气 key 只报状态与来源、绝不回值（方案
// §5.7）；语言走 LangStore 同一入口；开关只许
// 注册表白名单（首批 diagAutodel，桥自身开关与
// 哨兵/备份键永不入表）。

enum BridgeSettingsTools {

    static func settingsGet(
        coordinator: BridgeCoordinator) -> [String: Any] {
        let lang = LangStore.shared
        var weather: [String: Any] = [:]
        for name in ["qweather", "caiyun"] {
            let src = WeatherService.keySource(name)
            weather[name] = [
                "state": src.rawValue == "none"
                    ? "empty" : "set",
                "source": src.rawValue,
            ]
        }
        return [
            "language": [
                "preference": lang.followSystem
                    ? "system" : lang.code,
                "resolved": lang.code,
            ],
            "toggles": [
                "diagAutodel": UserDefaults.standard
                    .bool(forKey: "diagAutodel"),
            ],
            "weather": weather,
            "bridge": BridgeReadTools.bridgeStatus(
                coordinator: coordinator),
        ]
    }

    static func setLanguage(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let code = args["code"] as? String,
              !code.isEmpty else {
            return .failure(.invalidParams(
                "code required"))
        }
        guard let key = args["idempotencyKey"]
                as? String, !key.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        if code == "system" {
            LangStore.shared.applyFollowSystem()
        } else if LangStore.codes.contains(code) {
            LangStore.shared.apply(code)
        } else {
            return .failure(.invalidParams(
                "unknown language code: \(code)"))
        }
        let lang = LangStore.shared
        return .success([
            "preference": lang.followSystem
                ? "system" : lang.code,
            "resolved": lang.code,
        ])
    }

    /// 开关注册表（白名单）：首批仅 diagAutodel。
    static let toggleRegistry: Set<String> = [
        "diagAutodel",
    ]

    static func setToggle(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let key = args["key"] as? String,
              let value = args["value"] as? Bool else {
            return .failure(.invalidParams(
                "key and value(bool) required"))
        }
        guard let idem = args["idempotencyKey"]
                as? String, !idem.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        guard toggleRegistry.contains(key) else {
            return .failure(.invalidParams(
                "toggle not in bridge registry: \(key) "
                + "(registry: diagAutodel)"))
        }
        UserDefaults.standard.set(
            value, forKey: "diagAutodel")
        if value {
            DiagLog.shared.loadIfNeeded()
            DiagLog.shared.applyAutodelete()
        }
        return .success([
            "key": key,
            "value": UserDefaults.standard.bool(
                forKey: "diagAutodel"),
        ])
    }

    /// 只清用户自填覆盖（UserDefaults），不提供
    /// 经桥写入天气 key 的工具（凭据不经 MCP）。
    static func clearWeatherKey(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let provider = args["provider"]
                as? String,
              ["qweather", "caiyun"].contains(provider)
        else {
            return .failure(.invalidParams(
                "provider must be qweather or caiyun"))
        }
        guard let key = args["idempotencyKey"]
                as? String, !key.isEmpty else {
            return .failure(.invalidParams(
                "idempotencyKey required"))
        }
        UserDefaults.standard.removeObject(
            forKey: "weatherKey_" + provider)
        let src = WeatherService.keySource(provider)
        return .success([
            "provider": provider,
            "state": src.rawValue == "none"
                ? "empty" : "set",
            "source": src.rawValue,
        ])
    }
}
