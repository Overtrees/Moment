// ── MCP 桥工具分发 + 只读工具集（M1）──
// 分发器边界（方案 §4/§7）：M1 只有只读集 +
// ops_refresh（控制类，另有文件承接）；写工具名
// 不在本分发器内出现（verify [16] 锁）。安全模
// 式下分发器转受限形态：仅 bridge_status 可用，
// 其余一律 safe_mode_limited，不假成功。全部工
// 具走 App 内部模型（Library/DiagLog/Ops），不
// 做合成触摸、不扰动 UI 状态（搜索走只读访问器）。

import Foundation
import UIKit

final class BridgeDispatcher {
    static let shared = BridgeDispatcher()

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
                message: "tool not in M1 manifest: \(name)"))
            return
        }
        // ops_get_sources 由中继侧执行（origin=relay）；
        // 若帧误达 App，诚实回 not_implemented_here。
        if name == "ops_get_sources" {
            fail(BridgeToolError(
                code: "unknown_tool",
                message: "ops_get_sources is relay-executed"))
            return
        }
        if let library, library.bootIsSafe,
           name != "bridge_status" {
            fail(BridgeToolError(
                code: "safe_mode_limited",
                message: "safe mode: only bridge_status "
                    + "is available"))
            return
        }
        if name == "ops_refresh",
           !coordinator.scopes.contains("ops") {
            fail(BridgeToolError(
                code: "scope_denied",
                message: "ops_refresh requires ops scope"))
            return
        }
        let ctx: [String: Any] = [
            "appSessionId": coordinator.appSessionId,
            "bootSessionId": coordinator.bootSessionId,
            "bootMode": (library?.bootIsSafe ?? false)
                ? "safe" : "normal",
            "manifestHash": BridgeProto.manifestHash,
        ]
        func ok(_ payload: [String: Any]) {
            var p = payload
            p["ctx"] = ctx
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
    private static func allMemos(
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
