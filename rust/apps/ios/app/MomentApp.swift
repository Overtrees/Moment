// Moment 原生阶段 2 首版：SwiftUI + moment-ffi（Rust Core）。
// 列表（日期分组/搜索/置顶/删除/新建）+ 块编辑器（段落/
// 标题/todo 可编辑、长按拖拽重排、块增删、自动存回）。
// 现状（0.5.0）：列表/搜索/编辑/行内标记（含 link 段 url
// 保真）/图片/gallery/卡片/视频/附件/imgText 块、块类型
// 切换、ZIP 互通、Diag lite 均已入。余：双栏宽屏形态、
// 斜杠菜单。
// 工具链口径：@State 的 $ 投影不可用，状态一律走
// ObservableObject + 显式 Binding（见 spike/SPIKE.md）。
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit
import AVKit
import PhotosUI

enum Clock {
    static let t0 = ProcessInfo.processInfo.systemUptime
    static func ms() -> Int {
        Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
    }
    static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime,
                           .withFractionalSeconds]
        return f.string(from: Date())
    }
    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime,
                           .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// ── 块状态：包着原始节点字典，编辑只改 text/checked ──
final class BlockState: ObservableObject, Identifiable {
    let id: String
    var node: [String: Any]
    @Published var text: String
    @Published var checked: Bool
    @Published var height: CGFloat = 24
    @Published var nodeVersion = 0
    /// 图文块「编辑」信号（长按菜单 → ImgTextBlockView 开
    /// 全文编辑面板）。
    @Published var imgTextEditSignal = 0
    let originalText: String

    var type: String { node["type"] as? String ?? "paragraph" }
    var isText: Bool {
        type == "paragraph" || type == "heading" || type == "todo"
            || type == "quote" || type == "callout"
            || type == "codeBlock"
    }
    var isList: Bool {
        type == "bulleted-list" || type == "numbered-list"
    }
    /// 列表块的子项状态（list-item 节点逐个成状态）。
    var itemStates: [BlockState] = []
    /// 列表项内的嵌套列表（list-item 的子列表块）。
    var nestedList: BlockState?
    static func isListNode(_ n: [String: Any]) -> Bool {
        let t = n["type"] as? String ?? ""
        return t == "bulleted-list" || t == "numbered-list"
    }
    var fileId: String? {
        (node["attrs"] as? [String: Any])?["fileId"] as? String
    }
    var imageURL: String? {
        let attrs = node["attrs"] as? [String: Any]
        return attrs?["url"] as? String ?? attrs?["src"] as? String
    }
    var level: Int {
        (node["attrs"] as? [String: Any])?["level"] as? Int ?? 2
    }

    var calloutVariant: String {
        var v = node["calloutType"] as? String
        if v == nil,
           let attrs = node["attrs"] as? [String: Any] {
            v = attrs["calloutType"] as? String
        }
        let l = (v ?? "note").lowercased()
        return ["note", "warning", "tip", "important",
                "caution"].contains(l) ? l : "note"
    }
    var calloutTitle: String {
        switch calloutVariant {
        case "tip": return "提示"
        case "warning": return "警告"
        case "important": return "重要"
        case "caution": return "警示"
        default: return "注意"
        }
    }
    var calloutIcon: String {
        switch calloutVariant {
        case "tip": return "lightbulb.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "important": return "exclamationmark.circle.fill"
        case "caution": return "exclamationmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }
    var calloutAccent: Color { T.calloutAccent(calloutVariant) }
    var calloutBg: Color { T.calloutBg(calloutVariant) }

    init(node: [String: Any]) {
        self.node = node
        id = node["id"] as? String ?? UUID().uuidString
        let kids = node["children"] as? [[String: Any]] ?? []
        let joined = kids.compactMap {
            $0["text"] as? String
        }.joined()
        // 图文卡文本在 node.text/caption（core 口径），不在
        // children——读错源会让 Web 导入的图文卡显示为空。
        let ty = node["type"] as? String ?? ""
        if ty == "imgTextCard" || ty == "imageTextRow",
           let t = (node["text"] as? String)
            ?? (node["caption"] as? String) {
            text = t
            originalText = t
        } else {
            text = joined
            originalText = joined
        }
        runs = Self.runsFrom(children: kids)
        let attrs = node["attrs"] as? [String: Any]
        checked = attrs?["checked"] as? Bool ?? false
        if type == "heading" { height = 34 }
        // 列表结构：子项逐个成状态；列表项的 runs 只取
        // 行内子节点（嵌套列表单独成 nestedList 状态）。
        if isList {
            itemStates = kids.map { BlockState(node: $0) }
        } else if type == "list-item" {
            // runs/joined 天然只含行内子节点（嵌套列表节点
            // 无 text 键、非 link 型，解析时已跳过）。
            if let nested = kids.first(
                where: { Self.isListNode($0) }) {
                nestedList = BlockState(node: nested)
            }
        }
    }

    // 行内标记段：children 的文本节点序列（bool 标记键
    // bold/italic/underline/strikethrough/code）。link 子
    // 节点拍平成带下划线的文本段——未改动时走原样保留，
    // 改动后链接 url 丢失（已知口径差）。
    var runs: [[String: Any]] = []

    static func runsFrom(children: [[String: Any]])
        -> [[String: Any]] {
        var out: [[String: Any]] = []
        for c in children {
            if let t = c["text"] as? String {
                out.append(c)
            } else if c["type"] as? String == "link" {
                let lattrs = c["attrs"] as? [String: Any]
                let url = lattrs?["url"] as? String ?? ""
                let kids = c["children"] as? [[String: Any]] ?? []
                for k in kids {
                    if let t = k["text"] as? String {
                        var r = k
                        r["text"] = t
                        r["underline"] = true
                        r["_link"] = url
                        out.append(r)
                    }
                }
            }
        }
        return out
    }

    func flushedNode() -> [String: Any] {
        var n = node
        if isList {
            n["children"] = itemStates.map {
                $0.flushedNode()
            }
            return n
        }
        if type == "list-item" {
            let kids = node["children"] as? [[String: Any]]
                ?? []
            let inline = kids.filter {
                !Self.isListNode($0)
            }
            let original = Self.runsFrom(children: inline)
            var out: [[String: Any]] = Self.runsEqual(
                runs, original)
                ? inline : Self.childrenFrom(runs: runs)
            if let nl = nestedList {
                out.append(nl.flushedNode())
            } else if let orig = kids.first(
                where: { Self.isListNode($0) }) {
                out.append(orig)
            }
            n["children"] = out
            return n
        }
        guard isText else { return n }
        let original = Self.runsFrom(
            children: node["children"] as? [[String: Any]] ?? [])
        let runsChanged = !Self.runsEqual(runs, original)
        if runsChanged {
            n["children"] = Self.childrenFrom(runs: runs)
        }
        if type == "todo" {
            var attrs = n["attrs"] as? [String: Any] ?? [:]
            attrs["checked"] = checked
            n["attrs"] = attrs
        }
        return n
    }

    static func runsEqual(_ a: [[String: Any]],
                          _ b: [[String: Any]]) -> Bool {
        guard a.count == b.count else { return false }
        let keys = ["text", "bold", "italic", "underline",
                    "strikethrough", "code"]
        for i in a.indices {
            for k in keys {
                let av = a[i][k], bv = b[i][k]
                if k == "text" {
                    if (av as? String) != (bv as? String) {
                        return false
                    }
                } else if (av as? Bool ?? false)
                            != (bv as? Bool ?? false) {
                    return false
                }
            }
            if (a[i]["_link"] as? String)
                != (b[i]["_link"] as? String) {
                return false
            }
        }
        return true
    }

    /// runs → 模型 children：连续同 _link 段重组为 link
    /// 节点（attrs.url），其余段直出（剥 _link 私有键）。
    static func childrenFrom(runs: [[String: Any]])
        -> [[String: Any]] {
        var out: [[String: Any]] = []
        var i = 0
        while i < runs.count {
            let url = runs[i]["_link"] as? String
            if let url, !url.isEmpty {
                var kids: [[String: Any]] = []
                while i < runs.count
                        && (runs[i]["_link"] as? String) == url {
                    var r = runs[i]
                    r.removeValue(forKey: "_link")
                    kids.append(r)
                    i += 1
                }
                out.append([
                    "id": "l-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "link",
                    "attrs": ["url": url],
                    "children": kids,
                ])
            } else {
                var r = runs[i]
                r.removeValue(forKey: "_link")
                out.append(r)
                i += 1
            }
        }
        return out
    }
}

struct MemoItem: Identifiable {
    let id: String
    var title: String
    var pinned: Bool
    var createdAt: String
    var updatedAt: String
    var blocks: [BlockState]
    /// 原始备忘 JSON 全量：persist 时以此为底覆写已知键，
    /// bgColor/layout 等未建模字段原样带回（防编辑丢字段）。
    var raw: [String: Any] = [:]

    var bgColor: String? { raw["bgColor"] as? String }

    var snippet: String {
        blocks.first(where: { $0.isText && !$0.text.isEmpty })?.text
            ?? ""
    }
    var updatedDate: Date { Clock.parseISO(updatedAt) ?? Date() }
    var createdDate: Date { Clock.parseISO(createdAt) ?? Date() }
}

// ── 库门面 ──────────────────────────────────────────
final class Library: ObservableObject {
    @Published var memos: [MemoItem] = []
    @Published var timing = "启动中…"
    @Published var searchHits: [String]? = nil
    @Published var loadFailed = false
    /// 删除撤销（Web 口径）：软删打待删标记，8 秒窗口内
    /// 可撤销，超时才真删。
    @Published var pendingDeletion: MemoItem?
    private var deletionWork: DispatchWorkItem?
    private var lib: MomentLibrary?
    private var firstFrameMs: Int?

    func markFirstFrame() {
        if firstFrameMs == nil { firstFrameMs = Clock.ms() }
    }

    var storeDir: String {
        let d = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("library").path
        try? FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: true)
        return d
    }

    func load() {
        // 面包屑分步：先让首帧把当前步显示出来，再走 FFI；
        // 若某步硬崩，列表头会停在该步文案上（或下次启动
        // 能看到），不至于黑箱。开库延迟一拍同理。
        timing = "启动中 · 开库…"
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.05) {
            do {
                let lib = try MomentLibrary.open(
                    path: self.storeDir + "/moment.db")
                self.lib = lib
                DispatchQueue.main.async {
                    self.timing = "启动中 · 已开库，读数据…"
                }
                if try lib.memoCount() == 0 {
                    for m in Self.seedMemos {
                        try lib.upsertMemoJson(json: m)
                    }
                }
                try self.reload(lib: lib)
                let ready = Clock.ms()
                DispatchQueue.main.async {
                    self.timing = "冷启 首帧 "
                        + "\(self.firstFrameMs ?? -1)ms · 数据 "
                        + "\(ready)ms · \(self.memos.count) 篇"
                    DiagLog.shared.log(.info,
                        "冷启加载完成 memos=\(self.memos.count)"
                        + " 首帧\(self.firstFrameMs ?? -1)ms"
                        + " 数据\(ready)ms")
                }
            } catch {
                DispatchQueue.main.async {
                    self.timing = "打开库失败: \(error)"
                    self.loadFailed = true
                    DiagLog.shared.log(.error,
                        "打开库失败: \(error)")
                }
            }
        }
    }

    private func reload(lib: MomentLibrary) throws {
        let json = try lib.listMemosJson()
        let items = Self.parse(json)
        DispatchQueue.main.async {
            self.memos = items
            self.loadFailed = false
        }
    }

    func retryLoad() {
        loadFailed = false
        if lib == nil { load() }
        else if let lib { try? reload(lib: lib) }
    }

    /// 软删：先从列表摘除并挂待删，8 秒后真删（窗口内
    /// 再删别的篇则前一篇立即落删，与单 toast 口径一致）。
    func softRemove(_ item: MemoItem) {
        commitPendingDeletion()
        memos.removeAll { $0.id == item.id }
        pendingDeletion = item
        let work = DispatchWorkItem { [weak self] in
            self?.commitPendingDeletion()
        }
        deletionWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 8, execute: work)
    }

    func undoDeletion() {
        deletionWork?.cancel()
        deletionWork = nil
        if let item = pendingDeletion {
            memos.append(item)
            memos.sort {
                if $0.pinned != $1.pinned { return $0.pinned }
                return $0.updatedAt > $1.updatedAt
            }
        }
        pendingDeletion = nil
    }

    func commitPendingDeletion() {
        deletionWork?.cancel()
        deletionWork = nil
        if let item = pendingDeletion {
            try? lib?.removeMemo(id: item.id)
            DiagLog.shared.log(.info,
                "备忘已删除（撤销窗口结束）id=\(item.id)")
        }
        pendingDeletion = nil
    }

    static func parse(_ json: String) -> [MemoItem] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data)
                as? [[String: Any]] else { return [] }
        var items = arr.map { m in
            MemoItem(
                id: m["id"] as? String ?? UUID().uuidString,
                title: m["title"] as? String ?? "",
                pinned: m["pinned"] as? Bool ?? false,
                createdAt: m["createdAt"] as? String ?? "",
                updatedAt: m["updatedAt"] as? String ?? "",
                blocks: (m["doc"] as? [[String: Any]] ?? [])
                    .map { BlockState(node: $0) },
                raw: m)
        }
        items.sort {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
        return items
    }

    func persist(_ item: MemoItem) {
        // 最近编辑时刻（备份新鲜度判定：超 7 天且有新编辑）。
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: "lastEditTs")
        var it = item
        it.updatedAt = Clock.isoNow()
        // 以原始 JSON 为底覆写：未建模字段（bgColor/layout 等）
        // 原样保留，避免原生编辑一字就抹掉 Web 侧数据。
        var memo = it.raw
        memo["id"] = it.id
        memo["title"] = it.title
        memo["pinned"] = it.pinned
        memo["createdAt"] = it.createdAt
        memo["updatedAt"] = it.updatedAt
        memo["doc"] = it.blocks.map { $0.flushedNode() }
        it.raw = memo
        guard let data = try? JSONSerialization.data(
                withJSONObject: memo),
              let s = String(data: data, encoding: .utf8)
        else { return }
        try? lib?.upsertMemoJson(json: s)
        if let idx = memos.firstIndex(where: { $0.id == it.id }) {
            memos[idx] = it
            memos.sort {
                if $0.pinned != $1.pinned { return $0.pinned }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    @discardableResult
    func create() -> MemoItem {
        let now = Clock.isoNow()
        let item = MemoItem(
            id: "m-" + UUID().uuidString.prefix(12).lowercased(),
            title: "", pinned: false, createdAt: now,
            updatedAt: now,
            blocks: [BlockState(node: [
                "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
                "type": "paragraph", "children": [["text": ""]],
            ])])
        persist(item)
        if memos.firstIndex(where: { $0.id == item.id }) == nil {
            memos.insert(item, at: 0)
        }
        return item
    }

    func remove(_ item: MemoItem) {
        try? lib?.removeMemo(id: item.id)
        memos.removeAll { $0.id == item.id }
    }

    func togglePin(_ item: MemoItem) {
        var it = item
        it.pinned.toggle()
        persist(it)
    }

    func attachmentData(_ id: String) -> Data {
        (try? lib?.attachmentData(id: id)) ?? Data()
    }

    func putAttachment(_ id: String, _ data: Data) {
        try? lib?.putAttachment(id: id, data: data)
    }

    func attachmentCount() -> Int {
        guard let json = try? lib?.attachmentIdsJson(),
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(
                with: data) as? [String] else { return 0 }
        return arr.count
    }

    func libraryHash() -> String {
        if let h = try? lib?.libraryHash() { return String(h) }
        return "-"
    }

    @Published var notice = ""

    /// 导出文件名（Web 口径）：此刻备份_<UTC 日期>.zip。
    func exportZip() -> URL? {
        let dir = storeDir + "/exports"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        let path = dir + "/此刻备份_\(f.string(from: Date())).zip"
        do {
            try lib?.exportBackup(zipPath: path)
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: "lastExportTs")
            let url = URL(fileURLWithPath: path)
            recordOp(kind: "export", ok: true,
                     detail: url.lastPathComponent)
            DiagLog.shared.log(.info,
                "导出备份 \(url.lastPathComponent)")
            return url
        } catch {
            recordOp(kind: "export", ok: false, detail: "")
            DiagLog.shared.log(.error, "导出失败: \(error)")
            return nil
        }
    }

    /// 备份操作记录（Web 口径）：存 20 条、成功失败都记；
    /// 条目 = 状态 + 类型 + 时刻 + 详情（成功为文件名）。
    struct BackupOp: Codable {
        var ts: Double
        var ok: Bool
        var kind: String  // export | import
        var detail: String
    }

    func recordOp(kind: String, ok: Bool, detail: String) {
        var ops = Self.loadOps()
        ops.insert(BackupOp(ts: Date().timeIntervalSince1970,
                            ok: ok, kind: kind, detail: detail),
                   at: 0)
        if let data = try? JSONEncoder().encode(
            Array(ops.prefix(20))) {
            UserDefaults.standard.set(data, forKey: "backupOpsV2")
        }
    }

    static func loadOps() -> [BackupOp] {
        guard let data = UserDefaults.standard.data(
                forKey: "backupOpsV2"),
              let ops = try? JSONDecoder().decode(
                [BackupOp].self, from: data) else { return [] }
        return ops
    }

    /// FFI 统计行 `memos=N attachments=M` 解析。
    static func parseStats(_ s: String) -> (Int, Int)? {
        var m: Int?
        var a: Int?
        for part in s.split(separator: " ") {
            let kv = part.split(separator: "=")
            guard kv.count == 2, let v = Int(kv[1]) else {
                continue
            }
            if kv[0] == "memos" { m = v }
            if kv[0] == "attachments" { a = v }
        }
        guard let m, let a else { return nil }
        return (m, a)
    }

    private var pendingImportPath: String {
        storeDir + "/import-pending.zip"
    }

    /// 导入第一步（Web 口径）：先把所选文件暂存并整包
    /// 校验，校验通过才进入确认；失败直接报错、数据未动。
    func stageImport(from picked: URL) -> (Int, Int)? {
        let scoped = picked
            .startAccessingSecurityScopedResource()
        defer {
            if scoped {
                picked.stopAccessingSecurityScopedResource()
            }
        }
        try? FileManager.default.removeItem(
            atPath: pendingImportPath)
        do {
            try FileManager.default.copyItem(
                at: picked,
                to: URL(fileURLWithPath: pendingImportPath))
            let stats = try lib?.validateBackup(
                zipPath: pendingImportPath) ?? ""
            return Self.parseStats(stats)
        } catch {
            DiagLog.shared.log(.error,
                "导入校验失败: \(error)")
            return nil
        }
    }

    /// 导入第二步：确认后整库替换（校验已过）。
    func commitStagedImport() -> (Int, Int)? {
        do {
            let result = try lib?.importBackup(
                zipPath: pendingImportPath) ?? ""
            let stats = Self.parseStats(result)
            recordOp(kind: "import", ok: true,
                     detail: pickedImportName ?? "")
            DiagLog.shared.log(.info, "导入备份 \(result)")
            if let lib { try reload(lib: lib) }
            return stats
        } catch {
            recordOp(kind: "import", ok: false, detail: "")
            DiagLog.shared.log(.error, "导入失败: \(error)")
            return nil
        }
    }

    var pickedImportName: String?

    /// 附件计数（Web 口径）：全部备忘 doc 顶层 attachment
    /// 块引用的 fileId 去重（不含库内孤儿附件）。
    func referencedAttachmentCount() -> Int {
        var ids = Set<String>()
        for m in memos {
            for b in m.blocks where b.type == "attachment" {
                let attrs = b.node["attrs"] as? [String: Any]
                    ?? [:]
                if let f = attrs["fileId"] as? String {
                    ids.insert(f)
                }
                let items = attrs["items"]
                    as? [[String: Any]] ?? []
                for it in items {
                    if let f = it["fileId"] as? String {
                        ids.insert(f)
                    }
                }
            }
        }
        return ids.count
    }

    /// 按 fileId 在各备忘块里查真实文件名（图片页标题
    /// 口径：附件清单名优先，无名回退「图片」）。
    func attachmentName(for fid: String?) -> String? {
        guard let fid else { return nil }
        for m in memos {
            for b in m.blocks {
                let attrs = b.node["attrs"] as? [String: Any]
                    ?? [:]
                if b.type == "attachment" {
                    if attrs["fileId"] as? String == fid,
                       let n = attrs["name"] as? String {
                        return n
                    }
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items
                        where it["fileId"] as? String == fid {
                        if let n = it["name"] as? String {
                            return n
                        }
                    }
                }
                if b.type == "gallery" {
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items
                        where it["fileId"] as? String == fid {
                        if let n = it["name"] as? String {
                            return n
                        }
                    }
                }
                if b.fileId == fid,
                   let n = b.node["name"] as? String {
                    return n
                }
            }
        }
        return nil
    }

    func search(_ q: String) {
        let query = q.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { searchHits = nil; return }
        do {
            let json = try lib?.searchIdsJson(query: query) ?? "[]"
            let data = json.data(using: .utf8)
            searchHits = (try? JSONSerialization.jsonObject(
                with: data ?? Data())) as? [String] ?? []
        } catch { searchHits = [] }
    }

    static let seedMemos: [String] = [
        """
        {"id":"guide","title":"使用指南","pinned":true,
         "createdAt":"2026-11-26T00:00:00.000Z",
         "updatedAt":"2026-11-26T00:00:00.000Z",
         "doc":[
          {"id":"g1","type":"heading","attrs":{"level":2},
           "children":[{"text":"欢迎来到此刻（原生版）"}]},
          {"id":"g2","type":"paragraph",
           "children":[{"text":"这是原生阶段 2 首版：数据存在 Rust Core 的 SQLite 库里，与 Web 版同一套格式，ZIP 可互通（导入导出在后续轮）。"}]},
          {"id":"g3","type":"todo","attrs":{"checked":true},
           "children":[{"text":"列表：日期分组、搜索、下拉外手势都已接"}]},
          {"id":"g4","type":"todo","attrs":{"checked":false},
           "children":[{"text":"编辑页：点开任意一篇，试拼音组字与长按拖块排序"}]},
          {"id":"g5","type":"paragraph",
           "children":[{"text":"图片、附件等非文本块本版先只读占位，后续轮补齐。"}]}]}
        """,
        """
        {"id":"welcome","title":"第一篇备忘",
         "createdAt":"2026-11-26T00:30:00.000Z",
         "updatedAt":"2026-11-26T00:30:00.000Z",
         "doc":[
          {"id":"w1","type":"paragraph",
           "children":[{"text":"点右上角 + 新建一篇，或点开这篇直接改。所有修改自动保存。"}]}]}
        """,
    ]
}

// ── 行内标记 ⇄ NSAttributedString ─────────────────
enum Marks {
    /// 文字大小跟随系统（Dynamic Type）：Web 的 14/16/19
    /// 分级是接不到系统设置时的替代口径；原生有系统 API
    /// 则走更优路——UIFontMetrics 按文本样式缩放基准字。
    static func dynFont(size: CGFloat,
                        weight: UIFont.Weight = .regular,
                        style: UIFont.TextStyle = .body,
                        mono: Bool = false) -> UIFont {
        let base = mono
            ? UIFont.monospacedSystemFont(ofSize: size,
                                          weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style)
            .scaledFont(for: base)
    }

    static func baseFont(for block: BlockState) -> UIFont {
        switch block.type {
        case "heading":
            // Web --md-heading 尺度：28 / 23 / 20，字重 750。
            let size: CGFloat = block.level <= 1 ? 28
                : block.level == 2 ? 23 : 20
            let style: UIFont.TextStyle = block.level <= 1
                ? .title1 : block.level == 2 ? .title2 : .title3
            return dynFont(size: size, weight: .bold,
                           style: style)
        case "quote", "callout":
            return dynFont(size: 14, style: .subheadline)
        case "codeBlock":
            return dynFont(size: 13.5, mono: true)
        default:
            return dynFont(size: 16)
        }
    }

    /// 阅读节奏（Web .editor-body 口径）：正文行高 1.75、
    /// 引用/提示 1.6、标题 1.28——以段落样式覆到整串。
    static func withRhythm(_ attr: NSAttributedString,
                           block: BlockState)
        -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        switch block.type {
        case "heading": ps.lineHeightMultiple = 1.28
        case "quote", "callout": ps.lineHeightMultiple = 1.6
        default: ps.lineHeightMultiple = 1.75
        }
        let out = NSMutableAttributedString(attributedString: attr)
        out.addAttribute(.paragraphStyle, value: ps,
                         range: NSRange(location: 0,
                                        length: out.length))
        return out
    }

    static func font(base: UIFont, bold: Bool, italic: Bool,
                     code: Bool) -> UIFont {
        if code {
            return .monospacedSystemFont(
                ofSize: base.pointSize,
                weight: bold ? .bold : .regular)
        }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let d = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: d, size: base.pointSize)
        }
        return base
    }

    static func attributed(runs: [[String: Any]],
                           base: UIFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for r in runs {
            let t = r["text"] as? String ?? ""
            if t.isEmpty { continue }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font(base: base,
                            bold: r["bold"] as? Bool ?? false,
                            italic: r["italic"] as? Bool ?? false,
                            code: r["code"] as? Bool ?? false),
            ]
            if r["underline"] as? Bool ?? false {
                attrs[.underlineStyle] = NSUnderlineStyle
                    .single.rawValue
            }
            if r["strikethrough"] as? Bool ?? false {
                attrs[.strikethroughStyle] = NSUnderlineStyle
                    .single.rawValue
            }
            if let link = r["_link"] as? String, !link.isEmpty,
               let u = URL(string: link) {
                attrs[.link] = u
            }
            out.append(NSAttributedString(string: t,
                                          attributes: attrs))
        }
        if out.length == 0 {
            return NSAttributedString(
                string: "", attributes: [.font: base])
        }
        return out
    }

    static func runs(from attr: NSAttributedString,
                     base: UIFont,
                     suppressStrikethrough: Bool = false)
        -> [[String: Any]] {
        // 标记判定须扣除块基础字重：标题块 base 本身 bold，
        // 不扣会把全段误标 bold 写回数据（样式层≠标记层）。
        let baseTraits = base.fontDescriptor.symbolicTraits
        var out: [[String: Any]] = []
        let full = NSRange(location: 0, length: attr.length)
        attr.enumerateAttributes(in: full) { attrs, range, _ in
            let t = (attr.string as NSString)
                .substring(with: range)
            if t.isEmpty { return }
            var r: [String: Any] = ["text": t]
            if let f = attrs[.font] as? UIFont {
                let traits = f.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold)
                    && !baseTraits.contains(.traitBold) {
                    r["bold"] = true
                }
                if traits.contains(.traitItalic)
                    && !baseTraits.contains(.traitItalic) {
                    r["italic"] = true
                }
                if traits.contains(.traitMonoSpace) {
                    r["code"] = true
                }
            }
            if let u = attrs[.underlineStyle] as? Int, u != 0 {
                r["underline"] = true
            }
            if !suppressStrikethrough,
               let s = attrs[.strikethroughStyle] as? Int,
               s != 0 {
                r["strikethrough"] = true
            }
            if let link = attrs[.link] {
                if let u = link as? URL {
                    r["_link"] = u.absoluteString
                } else if let s = link as? String {
                    r["_link"] = s
                }
            }
            out.append(r)
        }
        return out
    }
}

// ── 自适应高度 UITextView（系统输入法组字） ─────────
struct BlockTextView: UIViewRepresentable {
    @ObservedObject var block: BlockState
    var editor: EditorModel?
    /// 非空时本视图编辑的是该列表块的一个 list-item。
    var listParent: BlockState? = nil
    var onChange: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(
            top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        let base = Marks.baseFont(for: block)
        tv.font = base
        tv.typingAttributes = [.font: base]
        if block.type == "quote" {
            tv.textColor = T.quoteTextUI
        }
        tv.attributedText = Marks.withRhythm(
            Marks.attributed(runs: block.runs, base: base),
            block: block)
        applyDoneStyle(tv)
        return tv
    }

    /// 尺寸口径根治：按提议宽度量高并回告该宽度——旧路
    /// 靠外部 .frame(height:) + bounds 猜宽，UITextView
    /// 会按未折行文本报固有宽，把整页撑出屏幕（真机截
    /// 图实证：正文居中溢出、两侧被裁）。
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView tv: UITextView,
                      context: Context) -> CGSize? {
        let w = proposal.width
            ?? (UIScreen.main.bounds.width - 32)
        let h = tv.sizeThatFits(CGSize(
            width: w, height: .greatestFiniteMagnitude)).height
        if abs(h - block.height) > 0.5 {
            DispatchQueue.main.async { block.height = h }
        }
        return CGSize(width: w, height: h)
    }

    /// 待办完成态（Web 口径）：文字删除线 + 变灰——仅显
    /// 示层，回写时由 suppressStrikethrough 扣除，不落盘。
    private func applyDoneStyle(_ tv: UITextView) {
        guard block.type == "todo", block.checked,
              tv.attributedText.length > 0 else { return }
        let m = NSMutableAttributedString(
            attributedString: tv.attributedText)
        let full = NSRange(location: 0, length: m.length)
        m.addAttribute(.strikethroughStyle, value: 1,
                       range: full)
        m.addAttribute(.foregroundColor,
                       value: UIColor.secondaryLabel,
                       range: full)
        tv.attributedText = m
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let key = "\(block.type)-\(block.level)-"
            + "\(block.nodeVersion)"
        let typeChanged = context.coordinator.lastTypeKey != key
        if typeChanged {
            context.coordinator.lastTypeKey = key
        }
        // 拆/并块后 nodeVersion 变化：即便本视图还持焦点
        // 也要按新 runs 重载（否则旧全文残留在已拆块里）。
        let versionChanged =
            context.coordinator.lastVersion != block.nodeVersion
        if versionChanged {
            context.coordinator.lastVersion = block.nodeVersion
        }
        // 聚焦请求消费（拆块落新块、并块落接合处等）。
        if let ed = editor, ed.focusBlockId == block.id,
           !tv.isFirstResponder {
            tv.becomeFirstResponder()
            let caret: Int
            if let off = ed.pendingCaretOffset {
                caret = min(off, tv.text.count)
                DispatchQueue.main.async {
                    ed.pendingCaretOffset = nil
                }
            } else if ed.focusCaretEnd {
                caret = tv.text.count
            } else {
                caret = 0
            }
            tv.selectedRange = NSRange(location: caret,
                                       length: 0)
            DispatchQueue.main.async {
                if ed.focusBlockId == block.id {
                    ed.focusBlockId = nil
                }
            }
        }
        if (tv.text != block.text || typeChanged)
            && tv.markedTextRange == nil
            && (!tv.isFirstResponder || versionChanged) {
            let base = Marks.baseFont(for: block)
            tv.font = base
            tv.typingAttributes = [.font: base]
            if block.type == "quote" {
                tv.textColor = T.quoteTextUI
            } else {
                tv.textColor = .label
            }
            tv.attributedText = Marks.withRhythm(
                Marks.attributed(runs: block.runs, base: base),
                block: block)
            applyDoneStyle(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var lastTypeKey = ""
        var lastVersion = -1
        init(_ p: BlockTextView) { parent = p }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.editor?.editingBlockId = parent.block.id
            // 文本编辑会话开始压一帧历史（撤销回到会话始）。
            parent.editor?.pushHistory()
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.editor?.editingBlockId == parent.block.id {
                parent.editor?.editingBlockId = nil
            }
        }

        func textView(_ tv: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard let ed = parent.editor,
                  tv.markedTextRange == nil,
                  parent.block.isText
                    || parent.block.type == "list-item"
            else { return true }
            let full = tv.attributedText
                ?? NSAttributedString()
            let loc = min(range.location, full.length)
            let end = min(range.location + range.length,
                          full.length)
            let before = full.attributedSubstring(
                from: NSRange(location: 0, length: loc))
            let after = full.attributedSubstring(
                from: NSRange(location: end,
                              length: full.length - end))
            if text.contains("\n") {
                if parent.block.type == "codeBlock" {
                    return true  // 代码块内换行是正文
                }
                // 回车拆块 / 粘贴多行拆块（E17）：统一走
                // insertLines（列表项在列表内续项）。
                let lines = text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n")
                if text == "\n" && parent.listParent == nil {
                    ed.splitBlock(parent.block, before: before,
                                  after: after)
                } else if text == "\n",
                          let list = parent.listParent,
                          parent.block.text.isEmpty {
                    // 空项回车 = 退出列表（Web 口径）。
                    ed.exitListItem(list: list,
                                    item: parent.block)
                } else {
                    ed.insertLines(parent.block,
                                   listParent: parent.listParent,
                                   before: before, lines: lines,
                                   after: after)
                }
                return false
            }
            if text.isEmpty && range.location == 0
                && range.length == 0 {
                // 段首退格并块（列表项走列表口径）。
                if let list = parent.listParent {
                    ed.mergeListItemBackward(
                        list: list, item: parent.block)
                } else {
                    ed.mergeBlockBackward(parent.block)
                }
                return false
            }
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.block.runs = Marks.runs(
                from: tv.attributedText,
                base: Marks.baseFont(for: parent.block),
                suppressStrikethrough: parent.block.type
                    == "todo" && parent.block.checked)
            parent.block.text = tv.text
            parent.onChange()
        }
    }
}

// ── 图片块：fileId 走 FFI 附件字节，URL 走网络 ──────
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false
    private var started = false

    func load(block: BlockState, library: Library) {
        load(fileId: block.fileId, urlString: block.imageURL,
             library: library)
    }

    func load(fileId: String?, urlString: String?,
              library: Library) {
        guard !started else { return }
        started = true
        if let fid = fileId {
            DispatchQueue.global(qos: .userInitiated).async {
                let data = library.attachmentData(fid)
                let img = UIImage(data: data)
                DispatchQueue.main.async {
                    self.image = img
                    self.failed = img == nil
                }
            }
        } else if let s = urlString, let url = URL(string: s) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap { UIImage(data: $0) }
                DispatchQueue.main.async {
                    self.image = img
                    self.failed = img == nil
                }
            }.resume()
        } else {
            failed = true
        }
    }
}

struct ItemImageView: View {
    let fileId: String?
    let urlString: String?
    var library: Library
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: loader.failed
                            ? "photo.badge.exclamationmark"
                            : "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipped()
        .onAppear {
            loader.load(fileId: fileId, urlString: urlString,
                        library: library)
        }
    }
}

struct ImageBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            if block.fileId == nil && block.imageURL == nil {
                // 空图占位（Web 口径）：点击添加图片。
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                    Text("点击添加图片")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if loader.failed {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("图片不可用")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .onAppear { loader.load(block: block, library: library) }
    }
}

// PHPicker（UIKit 口径；SwiftUI 的 PhotosPicker 在本
// 工具链的 27.2 SwiftUI 模块里不可见）。
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (Data) -> Void

    func makeUIViewController(
        context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(
        _ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject,
        PHPickerViewControllerDelegate {
        var parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider
            else { return }
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, _ in
                if let data {
                    DispatchQueue.main.async {
                        self.parent.onPick(data)
                    }
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(
        context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url],
                                 applicationActivities: nil)
    }
    func updateUIViewController(
        _ vc: UIActivityViewController, context: Context) {}
}

// ── 时间格式化（Web 口径：随系统 12/24 时制） ──────
enum Fmt {
    static func timeOfDay(_ d: Date) -> String {
        let tmpl = DateFormatter.dateFormat(
            fromTemplate: "j", options: 0,
            locale: Locale.current) ?? ""
        let f = DateFormatter()
        if tmpl.contains("a") {
            let h = Calendar.current.component(.hour, from: d)
            f.dateFormat = h < 12 ? "'上午' h:mm" : "'下午' h:mm"
        } else {
            f.dateFormat = "HH:mm"
        }
        return f.string(from: d)
    }

    /// 备份时刻文案：今天/昨天 + 时刻，或 M/D + 时刻。
    static func backupWhen(_ ts: Double) -> String {
        if ts <= 0 { return "尚未备份" }
        let d = Date(timeIntervalSince1970: ts)
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return "今天 \(timeOfDay(d))"
        }
        if cal.isDateInYesterday(d) {
            return "昨天 \(timeOfDay(d))"
        }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "\(f.string(from: d)) \(timeOfDay(d))"
    }

    static func fullStamp(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}

// ── 诊断日志管线（Web 口径：300 行环 + 落盘持久 +
// 按天冻结归档上限 60 + 等级只过滤呈现不滤导出） ────
enum DiagLevel: String {
    case info, warn, error
}

struct DiagEntry: Codable {
    var ts: Double
    var level: String
    var text: String

    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    var line: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let t = f.string(from: Date(timeIntervalSince1970: ts))
        switch level {
        case "warn": return "[\(t) W] \(text)"
        case "error": return "[\(t) E] \(text)"
        default: return "[\(t)] \(text)"
        }
    }
}

struct DiagArchive: Codable, Identifiable {
    var stamp: String  // 归档标 "YYYY-MM-DD HH:mm"
    var entries: [DiagEntry]
    var id: String { stamp }
    var lines: [String] { entries.map { $0.line } }
}

final class DiagLog: ObservableObject {
    static let shared = DiagLog()
    @Published var today: [DiagEntry] = []
    @Published var archives: [DiagArchive] = []
    private var loaded = false

    private var dir: String {
        let d = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)[0]
            .appendingPathComponent("diag").path
        try? FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: true)
        return d
    }
    private var todayPath: String { dir + "/today.json" }
    private var archivePath: String { dir + "/archives.json" }

    private func read<T: Decodable>(_ path: String) -> T? {
        guard let data = try? Data(
                contentsOf: URL(fileURLWithPath: path))
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to path: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let stored: [DiagEntry] = read(todayPath) ?? []
        let archs: [DiagArchive] = read(archivePath) ?? []
        archives = archs
        let todayKey = DiagEntry(
            ts: Date().timeIntervalSince1970, level: "info",
            text: "").dayKey
        let old = stored.filter { $0.dayKey != todayKey }
        today = stored.filter { $0.dayKey == todayKey }
        if !old.isEmpty {
            // 按天冻结（新→旧），插到既有归档之前。
            let days = Dictionary(grouping: old) { $0.dayKey }
            let stamp = Fmt.fullStamp(
                Date().timeIntervalSince1970)
            let fresh = days.keys.sorted(by: >).map { day in
                DiagArchive(stamp: stamp,
                            entries: (days[day] ?? [])
                                .sorted { $0.ts < $1.ts })
            }
            archives = Array((fresh + archives).prefix(60))
        }
        applyAutodelete()
        persist()
    }

    private func persist() {
        write(today, to: todayPath)
        write(archives, to: archivePath)
    }

    private func freezeToday() {
        guard !today.isEmpty else { return }
        let stamp = Fmt.fullStamp(Date().timeIntervalSince1970)
        archives.insert(
            DiagArchive(stamp: stamp, entries: today), at: 0)
        archives = Array(archives.prefix(60))
        today = []
    }

    /// 自动删除（Web 口径）：开启后日志超 30 天自动删除。
    func applyAutodelete() {
        guard UserDefaults.standard.bool(
            forKey: "diagAutodel") else { return }
        let cutoff = Date().timeIntervalSince1970
            - 30 * 86400
        archives.removeAll { arch in
            (arch.entries.last?.ts ?? 0) < cutoff
        }
        today.removeAll { $0.ts < cutoff }
    }

    func log(_ level: DiagLevel, _ text: String) {
        let entry = DiagEntry(
            ts: Date().timeIntervalSince1970,
            level: level.rawValue, text: text)
        let work = { [weak self] in
            guard let self else { return }
            self.loadIfNeeded()
            if let first = self.today.first,
               first.dayKey != entry.dayKey {
                self.freezeToday()
            }
            self.today.append(entry)
            if self.today.count > 300 {
                self.today.removeFirst(self.today.count - 300)
            }
            self.persist()
        }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async(execute: work) }
    }
}

/// 日志呈现过滤（只影响本页与视窗页，导出全量）。
func diagFiltered(_ entries: [DiagEntry],
                  level: String) -> [DiagEntry] {
    switch level {
    case "info": return entries.filter { $0.level == "info" }
    case "warn": return entries.filter { $0.level == "warn" }
    case "error": return entries.filter { $0.level == "error" }
    default: return entries
    }
}

// ── 诊断页（Web 口径：设置卡 + 当天卡 + 历史归档） ──
struct DiagView: View {
    @ObservedObject var library: Library
    @ObservedObject private var diag = DiagLog.shared
    @StateObject private var ui = DiagUI()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("diagAutodel") private var autodel = false
    @AppStorage("diagLevel") private var level = "all"

    final class DiagUI: ObservableObject {
        @Published var report = ""
        @Published var levelOpen = false
        @Published var route: Route?
        enum Route: Identifiable {
            case today
            case archive(Int)
            var id: String {
                switch self {
                case .today: return "today"
                case .archive(let i): return "a\(i)"
                }
            }
        }
    }

    private var levelName: String {
        switch level {
        case "info": return "信息"
        case "warn": return "警告"
        case "error": return "错误"
        default: return "全部"
        }
    }

    var body: some View {
        ChromeView(title: "诊断日志", onBack: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading,
                                   spacing: 2) {
                                Text("自动删除日志")
                                    .font(.system(
                                        size: 16,
                                        weight: .semibold))
                                    .foregroundStyle(T.textMain)
                                Text("开启后日志超过30天自动删除")
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        T.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { autodel },
                                set: { autodel = $0
                                       DiagLog.shared
                                           .applyAutodelete() }))
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        Rectangle()
                            .fill(T.glassBorder.opacity(0.5))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                        Button {
                            ui.levelOpen.toggle()
                        } label: {
                            HStack {
                                Text("日志等级")
                                    .font(.system(
                                        size: 16,
                                        weight: .semibold))
                                    .foregroundStyle(T.textMain)
                                Spacer()
                                Text(levelName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(
                                        T.textSecondary)
                                Text("›")
                                    .font(.system(size: 18))
                                    .foregroundStyle(T.textSecondary
                                        .opacity(0.45))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        if ui.levelOpen {
                            Picker("日志等级", selection: Binding(
                                get: { level },
                                set: { level = $0 })) {
                                Text("全部").tag("all")
                                Text("信息").tag("info")
                                Text("警告").tag("warn")
                                Text("错误").tag("error")
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    }
                    .glassCard(radius: 28)

                    // 当天日志卡：绿字黑底，整卡进视窗页。
                    Button {
                        ui.route = .today
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            let lines = diagFiltered(
                                diag.today, level: level)
                            if lines.isEmpty {
                                Text("（暂无日志）")
                                    .foregroundStyle(
                                        Color.green.opacity(0.7))
                            } else {
                                ForEach(
                                    Array(lines.suffix(8)
                                        .enumerated()),
                                    id: \.offset) { _, e in
                                    Text(e.line)
                                        .frame(maxWidth: .infinity,
                                               alignment: .leading)
                                }
                            }
                        }
                        .font(.system(size: 11,
                                      design: .monospaced))
                        .foregroundStyle(Color.green)
                        .padding(14)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .background(Color.black,
                                    in: RoundedRectangle(
                                        cornerRadius: 20))
                    }
                    .padding(.top, 24)

                    if !diag.archives.isEmpty {
                        SectionHeader(text: "历史归档")
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(diag.archives
                                .enumerated()), id: \.offset) {
                                idx, arch in
                                Button {
                                    ui.route = .archive(idx)
                                } label: {
                                    Text(arch.stamp)
                                        .font(.system(
                                            size: 13,
                                            weight: .medium))
                                        .foregroundStyle(T.textMain)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassCard(radius: 999)
                                }
                            }
                        }
                    }

                    SectionHeader(text: "设备自检")
                    VStack(alignment: .leading, spacing: 6) {
                        DiagLine("路径", library.storeDir)
                        DiagLine("篇数", "\(library.memos.count)")
                        DiagLine("附件数",
                                 "\(library.attachmentCount())")
                        DiagLine("库哈希", library.libraryHash())
                        DiagLine("冷启", library.timing)
                        Button("运行阶段 0 自检链") {
                            let dir = NSTemporaryDirectory()
                                + "phase0-diag"
                            DispatchQueue.global(
                                qos: .userInitiated).async {
                                let r = runPhase0Checks(dir: dir)
                                DispatchQueue.main.async {
                                    ui.report = r
                                }
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.accent)
                        .padding(.top, 4)
                        if !ui.report.isEmpty {
                            Text(ui.report)
                                .font(.system(
                                    size: 11, design: .monospaced))
                                .foregroundStyle(T.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(16)
                    .glassCard(radius: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 126)
                .padding(.bottom, 32)
            }
        }
        .onAppear { DiagLog.shared.loadIfNeeded() }
        .navigationDestination(isPresented: Binding(
            get: { ui.route != nil },
            set: { if !$0 { ui.route = nil } })) {
            switch ui.route {
            case .today:
                DiagLogPage(
                    stamp: Fmt.fullStamp(
                        Date().timeIntervalSince1970),
                    entries: diag.today)
            case .archive(let idx)
                where idx < diag.archives.count:
                DiagLogPage(
                    stamp: diag.archives[idx].stamp,
                    entries: diag.archives[idx].entries)
            default:
                EmptyView()
            }
        }
    }

    private func DiagLine(_ k: String, _ v: String)
        -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(T.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(v)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(T.textMain)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

// ── 日志视窗页（Web 口径：标题 = 文件名，右上导出全量
// 未过滤行走系统分享） ─────────────────────────────
struct DiagLogPage: View {
    var stamp: String
    var entries: [DiagEntry]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = PageUI()
    @AppStorage("diagLevel") private var level = "all"

    final class PageUI: ObservableObject {
        @Published var shareURL: URL?
    }

    private var fileName: String { "\(stamp).log" }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    let lines = diagFiltered(entries,
                                              level: level)
                    if lines.isEmpty {
                        Text("（无符合等级的日志）")
                            .font(.system(size: 12))
                            .foregroundStyle(T.textSecondary)
                    } else {
                        ForEach(Array(lines.enumerated()),
                                id: \.offset) { _, e in
                            Text(e.line)
                                .font(.system(
                                    size: 11, design: .monospaced))
                                .foregroundStyle(
                                    e.level == "error"
                                        ? T.danger : T.textMain)
                                .frame(maxWidth: .infinity,
                                       alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 126)
                .padding(.bottom, 32)
            }
            HStack(alignment: .top) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
                }
                Spacer()
                CompactTitle(text: fileName)
                    .padding(.top, 4)
                Spacer()
                Button(action: exportAll) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
        }
        .background(T.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
    }

    private func exportAll() {
        let text = entries.map { $0.line }
            .joined(separator: "\n")
        let safe = fileName.replacingOccurrences(
            of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
        try? text.write(to: url, atomically: true,
                        encoding: .utf8)
        ui.shareURL = url
    }
}

// ── 列表块（Web 口径：• / N. 标记 + 子项逐项编辑，
// 嵌套列表缩进续排；回车续项、空项回车退出、段首退格
// 并项走 EditorModel 的列表口径） ──────────────────
struct ListBlockView: View {
    @ObservedObject var block: BlockState
    var editor: EditorModel
    var depth: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(block.itemStates.enumerated()),
                    id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(marker(i))
                            .font(.system(size: 15))
                            .foregroundStyle(T.textSecondary)
                            .frame(width: 20,
                                   alignment: .trailing)
                            .padding(.top, 3)
                        BlockTextView(
                            block: item, editor: editor,
                            listParent: block) {
                            block.nodeVersion += 1
                            editor.scheduleSave()
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                    }
                    if let nl = item.nestedList {
                        ListBlockView(block: nl, editor: editor,
                                      depth: depth + 1)
                            .padding(.leading, 26)
                    }
                }
            }
        }
    }

    private func marker(_ i: Int) -> String {
        if block.type == "numbered-list" {
            let attrs = block.node["attrs"] as? [String: Any]
            let start = attrs?["start"] as? Int ?? 1
            return "\(start + i)."
        }
        return "•"
    }
}

// ── 编辑器 ─────────────────────────────────────────
struct ImageTarget: Identifiable {
    let id = UUID()
    var fileId: String?
    var urlString: String?
    var name: String
}

final class EditorModel: ObservableObject {
    @Published var title: String
    @Published var blocks: [BlockState]
    @Published var draggingId: String?
    @Published var dragDy: CGFloat = 0
    @Published var imageTarget: ImageTarget?
    @Published var bgColor: String?
    @Published var focusBlockId: String?
    @Published var focusCaretEnd = false
    @Published var editingBlockId: String?
    /// 空图占位点按 → 选图替换该块（EditorView 呈现）。
    @Published var showReplacePicker = false
    var replaceImageBlockId: String?

    func replaceImage(fileId: String) {
        guard let id = replaceImageBlockId,
              let b = blocks.first(where: { $0.id == id })
        else { return }
        pushHistory()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        attrs["fileId"] = fileId
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        replaceImageBlockId = nil
        scheduleSave()
    }
    let item: MemoItem
    let library: Library
    private var saveWork: DispatchWorkItem?

    // 撤销/重做历史栈（Web 口径）：doc 快照（flushed
    // 节点 + 标题），结构操作与文本编辑会话开始时压栈。
    private var undoStack: [[String: Any]] = []
    private var redoStack: [[String: Any]] = []
    @Published var canUndo = false
    @Published var canRedo = false

    /// 新建篇初始落焦（EditorView onAppear 消费一次）。
    var wantsInitialFocus = false

    static func isAtomicType(_ t: String) -> Bool {
        ["image", "gallery", "video", "musicCard", "linkCard",
         "attachment", "imgTextCard", "imageTextRow",
         "divider"].contains(t)
    }

    init(item: MemoItem, library: Library) {
        self.item = item
        self.library = library
        title = item.title
        blocks = item.blocks
        bgColor = item.bgColor
        // 原子块收尾时物化尾随空段（Web 口径）：末尾恒有
        // 可落焦的文本段，不必点原子块才能续写。
        if let last = blocks.last,
           Self.isAtomicType(last.type) {
            blocks.append(BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "paragraph",
                "children": [["text": ""]],
            ]))
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSave()
            }
        }
    }

    private func snapshot() -> [String: Any] {
        ["title": title,
         "doc": blocks.map { $0.flushedNode() }]
    }

    func pushHistory() {
        undoStack.append(snapshot())
        if undoStack.count > 50 {
            undoStack.removeFirst(
                undoStack.count - 50)
        }
        redoStack.removeAll()
        syncHistoryFlags()
    }

    private func syncHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func applySnapshot(_ s: [String: Any]) {
        title = s["title"] as? String ?? title
        let doc = s["doc"] as? [[String: Any]] ?? []
        blocks = doc.map { BlockState(node: $0) }
        scheduleSave()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        applySnapshot(s)
        syncHistoryFlags()
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        applySnapshot(s)
        syncHistoryFlags()
    }

    /// 正文字数（Web 口径：只计正文文本块，不含标题）。
    var wordCount: Int {
        blocks.filter { $0.isText }
            .reduce(0) { $0 + $1.text.count }
    }

    private func preparedItem() -> MemoItem {
        var it = item
        it.title = title
        it.blocks = blocks
        if let bg = bgColor {
            it.raw["bgColor"] = bg
        } else {
            it.raw.removeValue(forKey: "bgColor")
        }
        return it
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.library.persist(self.preparedItem())
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6,
                                      execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        library.persist(preparedItem())
    }

    func setBgColor(_ hex: String?) {
        pushHistory()
        bgColor = hex
        scheduleSave()
    }

    func addBlock(after: BlockState? = nil) {
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
            "type": "paragraph", "children": [["text": ""]],
        ])
        if let after, let i = blocks.firstIndex(
            where: { $0.id == after.id }) {
            blocks.insert(b, at: i + 1)
        } else {
            blocks.append(b)
        }
        scheduleSave()
    }

    func setBlockType(_ b: BlockState, type: String,
                      level: Int = 2) {
        pushHistory()
        var n = b.node
        n["type"] = type
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        if type == "heading" { attrs["level"] = level }
        if type == "todo" && attrs["checked"] == nil {
            attrs["checked"] = false
            b.checked = false
        }
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
    }

    func addImageBlock(fileId: String) {
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
            "type": "image",
            "attrs": ["fileId": fileId],
            "children": [],
        ])
        blocks.append(b)
        scheduleSave()
    }

    func addAttachmentBlock(fileId: String, name: String,
                            size: Int) {
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
            "type": "attachment",
            "attrs": ["fileId": fileId, "name": name,
                      "size": size],
            "children": [],
        ])
        blocks.append(b)
        scheduleSave()
    }

    func deleteBlock(_ b: BlockState) {
        pushHistory()
        blocks.removeAll { $0.id == b.id }
        if blocks.isEmpty {
            blocks.append(BlockState(node: [
                "id": "b-" + UUID().uuidString.prefix(8)
                    .lowercased(),
                "type": "paragraph",
                "children": [["text": ""]],
            ]))
        }
        scheduleSave()
    }

    /// 回车拆块（Web 口径）：当前块留 before，新块承
    /// after 并聚焦（光标落新块首）。
    func splitBlock(_ b: BlockState,
                    before: NSAttributedString,
                    after: NSAttributedString) {
        pushHistory()
        let base = Marks.baseFont(for: b)
        b.runs = Marks.runs(from: before, base: base)
        b.text = before.string
        b.nodeVersion += 1
        var node: [String: Any] = [
            "id": "b-" + UUID().uuidString.prefix(8)
                .lowercased(),
            "type": b.type == "heading" ? "paragraph" : b.type,
            "children": [["text": after.string]],
        ]
        if b.type == "todo" {
            node["attrs"] = ["checked": false]
        }
        let nb = BlockState(node: node)
        nb.runs = Marks.runs(from: after, base: base)
        nb.text = after.string
        if let i = blocks.firstIndex(where: { $0.id == b.id }) {
            blocks.insert(nb, at: i + 1)
        } else {
            blocks.append(nb)
        }
        focusBlockId = nb.id
        focusCaretEnd = false
        scheduleSave()
    }

    /// 并块后光标落点（字符偏移），BlockTextView 消费。
    var pendingCaretOffset: Int?

    /// 段首退格并块（Web 口径）：并入上一文本块，光标
    /// 落接合处；当前块为空时直接删块聚焦上一块末尾。
    func mergeBlockBackward(_ b: BlockState) {
        guard let i = blocks.firstIndex(
            where: { $0.id == b.id }), i > 0 else { return }
        let prev = blocks[i - 1]
        if b.text.isEmpty {
            pushHistory()
            blocks.remove(at: i)
            if prev.isText {
                focusBlockId = prev.id
                focusCaretEnd = true
            }
        } else if prev.isText {
            pushHistory()
            let junction = prev.text.count
            prev.runs = prev.runs + b.runs
            prev.text = prev.text + b.text
            prev.nodeVersion += 1
            blocks.remove(at: i)
            focusBlockId = prev.id
            focusCaretEnd = false
            pendingCaretOffset = junction
        } else {
            return
        }
        scheduleSave()
    }

    /// 多行文本插入（回车于列表项 / 粘贴多行共用，E17）：
    /// 当前块保留 before+首行，其余行逐行成新块（列表项
    /// 或同类文本块，heading 降段落），末行拼 after。
    func insertLines(_ b: BlockState,
                     listParent: BlockState?,
                     before: NSAttributedString,
                     lines: [String],
                     after: NSAttributedString) {
        guard !lines.isEmpty else { return }
        pushHistory()
        let base = Marks.baseFont(for: b)
        func plainRuns(_ s: String) -> [[String: Any]] {
            s.isEmpty ? [] : [["text": s]]
        }
        let beforeRuns = Marks.runs(from: before, base: base)
        let afterRuns = Marks.runs(from: after, base: base)
        b.runs = beforeRuns + plainRuns(lines[0])
        b.text = before.string + lines[0]
        b.nodeVersion += 1
        var lastBlock = b
        if lines.count > 1 {
            for k in 1..<lines.count {
                let isLast = k == lines.count - 1
                let segRuns = plainRuns(lines[k])
                    + (isLast ? afterRuns : [])
                let segText = lines[k]
                    + (isLast ? after.string : "")
                if let list = listParent {
                    let node: [String: Any] = [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": "list-item",
                        "children": [["text": segText]],
                    ]
                    let nb = BlockState(node: node)
                    nb.runs = segRuns
                    nb.text = segText
                    if let i = list.itemStates.firstIndex(
                        where: { $0 === lastBlock }) {
                        list.itemStates.insert(nb, at: i + 1)
                    } else {
                        list.itemStates.append(nb)
                    }
                    lastBlock = nb
                } else {
                    var node: [String: Any] = [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": b.type == "heading"
                            ? "paragraph" : b.type,
                        "children": [["text": segText]],
                    ]
                    if b.type == "todo" {
                        node["attrs"] = ["checked": false]
                    }
                    let nb = BlockState(node: node)
                    nb.runs = segRuns
                    nb.text = segText
                    if let i = blocks.firstIndex(
                        where: { $0 === lastBlock }) {
                        blocks.insert(nb, at: i + 1)
                    } else {
                        blocks.append(nb)
                    }
                    lastBlock = nb
                }
            }
        } else {
            b.runs = b.runs + afterRuns
            b.text = b.text + after.string
            b.nodeVersion += 1
        }
        listParent?.nodeVersion += 1
        focusBlockId = lastBlock.id
        focusCaretEnd = lines.count == 1
        if lines.count > 1 {
            pendingCaretOffset = nil
            focusCaretEnd = false
            // 光标落末块 = 末行文本长度（不含 after 时为行末）
            pendingCaretOffset = lines[lines.count - 1].count
        }
        scheduleSave()
    }

    /// 空项回车退出列表（Web 口径）：该项转空段落落到
    /// 列表后，其后子项自成新列表（列表被劈开）。
    func exitListItem(list: BlockState, item: BlockState) {
        guard let idx = list.itemStates.firstIndex(
            where: { $0 === item }) else { return }
        pushHistory()
        let trailing = Array(
            list.itemStates.dropFirst(idx + 1))
        list.itemStates.removeSubrange(idx...)
        let p = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ])
        if let li = blocks.firstIndex(where: { $0 === list }) {
            if list.itemStates.isEmpty && trailing.isEmpty {
                blocks[li] = p
            } else if list.itemStates.isEmpty {
                blocks[li] = p
                let nl = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": list.type,
                    "children": [],
                ])
                nl.itemStates = trailing
                blocks.insert(nl, at: li + 1)
            } else {
                blocks.insert(p, at: li + 1)
                if !trailing.isEmpty {
                    let nl = BlockState(node: [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": list.type,
                        "children": [],
                    ])
                    nl.itemStates = trailing
                    blocks.insert(nl, at: li + 2)
                }
            }
        }
        list.nodeVersion += 1
        focusBlockId = p.id
        focusCaretEnd = false
        scheduleSave()
    }

    /// 列表项段首退格（Web 口径）：空项删项；首项转段落
    /// 移到列表前；其余并入上一项、光标落接合处。
    func mergeListItemBackward(list: BlockState,
                               item: BlockState) {
        guard let idx = list.itemStates.firstIndex(
            where: { $0 === item }) else { return }
        pushHistory()
        if item.text.isEmpty {
            list.itemStates.remove(at: idx)
            if list.itemStates.isEmpty {
                let p = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "paragraph",
                    "children": [["text": ""]],
                ])
                if let li = blocks.firstIndex(
                    where: { $0 === list }) {
                    blocks[li] = p
                }
                focusBlockId = p.id
                focusCaretEnd = true
            } else {
                let target = list.itemStates[
                    min(idx, list.itemStates.count - 1)]
                focusBlockId = target.id
                focusCaretEnd = true
            }
        } else if idx == 0 {
            list.itemStates.remove(at: idx)
            let p = BlockState(node: [
                "id": item.id,
                "type": "paragraph",
                "children": [["text": item.text]],
            ])
            p.runs = item.runs
            p.text = item.text
            if let li = blocks.firstIndex(
                where: { $0 === list }) {
                blocks.insert(p, at: li)
                if list.itemStates.isEmpty {
                    blocks.remove(at: li + 1)
                }
            }
            focusBlockId = p.id
            focusCaretEnd = true
        } else {
            let prev = list.itemStates[idx - 1]
            let junction = prev.text.count
            prev.runs = prev.runs + item.runs
            prev.text = prev.text + item.text
            prev.nodeVersion += 1
            list.itemStates.remove(at: idx)
            focusBlockId = prev.id
            focusCaretEnd = false
            pendingCaretOffset = junction
        }
        list.nodeVersion += 1
        scheduleSave()
    }

    /// 拖拽落点按各块实测高累加（Web 口径；固定步距对
    /// 高块必错位）。行间隙 6 与 BlockRow 排版一致。
    func commitDrag() {
        guard let id = draggingId,
              let from = blocks.firstIndex(where: { $0.id == id })
        else { draggingId = nil; dragDy = 0; return }
        let gap: CGFloat = 6
        var to = from
        if dragDy > 0 {
            var acc: CGFloat = 0
            var j = from
            while j + 1 < blocks.count {
                let h = (blocks[j + 1].height > 0
                    ? blocks[j + 1].height : 40) + gap
                if dragDy > acc + h / 2 {
                    acc += h
                    j += 1
                    to = j
                } else { break }
            }
        } else if dragDy < 0 {
            var acc: CGFloat = 0
            var j = from
            while j - 1 >= 0 {
                let h = (blocks[j - 1].height > 0
                    ? blocks[j - 1].height : 40) + gap
                if -dragDy > acc + h / 2 {
                    acc += h
                    j -= 1
                    to = j
                } else { break }
            }
        }
        if to != from {
            pushHistory()
            let moved = blocks.remove(at: from)
            blocks.insert(moved, at: to)
            scheduleSave()
        }
        draggingId = nil; dragDy = 0
    }

    // ── 单篇导出（Web 口径：MD/HTML/PDF 三路） ──
    private var pdfMaker: PdfMaker?

    private var exportBaseName: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = t.components(separatedBy: bad)
            .joined(separator: "_")
        return cleaned.isEmpty ? "无标题" : cleaned
    }

    func exportFile(format: String) -> URL? {
        let content = format == "md"
            ? ExportGen.markdown(title: title, blocks: blocks)
            : ExportGen.html(title: title, blocks: blocks)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(exportBaseName).\(format)")
        do {
            try content.write(to: url, atomically: true,
                              encoding: .utf8)
            return url
        } catch { return nil }
    }

    func exportPDF(completion: @escaping (URL?) -> Void) {
        let html = ExportGen.html(title: title, blocks: blocks)
        let maker = PdfMaker()
        pdfMaker = maker
        maker.make(html: html,
                   fileName: "\(exportBaseName).pdf") {
            [weak self] url in
            self?.pdfMaker = nil
            completion(url)
        }
    }
}

/// HTML → PDF（离屏 WKWebView + createPDF，原生等价路）。
final class PdfMaker: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var fileName = "export.pdf"
    private var done: ((URL?) -> Void)?

    func make(html: String, fileName: String,
              completion: @escaping (URL?) -> Void) {
        self.fileName = fileName
        done = completion
        let wv = WKWebView(frame: CGRect(
            x: 0, y: 0, width: 612, height: 792))
        wv.navigationDelegate = self
        web = wv
        wv.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ wv: WKWebView,
                 didFinish navigation: WKNavigation!) {
        wv.createPDF(configuration: WKPDFConfiguration()) {
            [weak self] result in
            guard let self else { return }
            var out: URL?
            if case .success(let data) = result {
                let url = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(self.fileName)
                if (try? data.write(to: url)) != nil {
                    out = url
                }
            }
            self.web = nil
            self.done?(out)
            self.done = nil
        }
    }

    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        web = nil
        done?(nil)
        done = nil
    }
}

/// 导出生成（MD/HTML）：块集映射，行内标记转对应语法。
enum ExportGen {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func mdRuns(_ runs: [[String: Any]]) -> String {
        runs.map { r in
            var t = r["text"] as? String ?? ""
            if r["code"] as? Bool == true { t = "`\(t)`" }
            if r["bold"] as? Bool == true { t = "**\(t)**" }
            if r["italic"] as? Bool == true { t = "*\(t)*" }
            if r["strikethrough"] as? Bool == true {
                t = "~~\(t)~~"
            }
            if let u = r["_link"] as? String {
                t = "[\(t)](\(u))"
            }
            return t
        }.joined()
    }

    static func htmlRuns(_ runs: [[String: Any]]) -> String {
        runs.map { r in
            var t = esc(r["text"] as? String ?? "")
            if r["code"] as? Bool == true {
                t = "<code>\(t)</code>"
            }
            if r["bold"] as? Bool == true {
                t = "<strong>\(t)</strong>"
            }
            if r["italic"] as? Bool == true {
                t = "<em>\(t)</em>"
            }
            if r["underline"] as? Bool == true {
                t = "<u>\(t)</u>"
            }
            if r["strikethrough"] as? Bool == true {
                t = "<s>\(t)</s>"
            }
            if let u = r["_link"] as? String {
                t = "<a href=\"\(esc(u))\">\(t)</a>"
            }
            return t
        }.joined()
    }

    static func markdown(title: String,
                         blocks: [BlockState]) -> String {
        var out: [String] = []
        if !title.isEmpty { out.append("# \(title)") }
        for b in blocks {
            out.append(mdBlock(b))
        }
        return out.joined(separator: "\n\n")
    }

    private static func mdBlock(_ b: BlockState) -> String {
        let attrs = b.node["attrs"] as? [String: Any] ?? [:]
        switch b.type {
        case "heading":
            return String(repeating: "#", count: b.level + 1)
                + " " + mdRuns(b.runs)
        case "todo":
            return "- [\(b.checked ? "x" : " ")] "
                + mdRuns(b.runs)
        case "quote":
            return "> " + mdRuns(b.runs)
        case "callout":
            return "> [!\(b.calloutVariant.uppercased())] "
                + mdRuns(b.runs)
        case "codeBlock":
            return "```\n\(b.text)\n```"
        case "divider":
            return "---"
        case "image":
            if let u = b.imageURL { return "![图片](\(u))" }
            if let f = b.fileId {
                return "![图片](attachment://\(f))"
            }
            return ""
        case "gallery":
            let items = attrs["items"] as? [[String: Any]]
                ?? []
            return items.map {
                if let u = $0["url"] as? String {
                    return "![图片](\(u))"
                }
                if let f = $0["fileId"] as? String {
                    return "![图片](attachment://\(f))"
                }
                return ""
            }.joined(separator: "\n")
        case "musicCard", "linkCard":
            let meta = b.node["meta"] as? [String: Any] ?? [:]
            let t = (meta["title"] as? String) ?? b.type
            let u = (b.node["url"] as? String) ?? ""
            return "[\(t)](\(u))"
        case "video":
            let u = b.imageURL ?? ""
            return "[视频](\(u))"
        case "attachment":
            let name = (attrs["name"] as? String) ?? "附件"
            if let f = b.fileId {
                return "[\(name)](attachment://\(f))"
            }
            return name
        case "imgTextCard", "imageTextRow":
            var s = ""
            if let f = b.fileId {
                s = "![图片](attachment://\(f))\n\n"
            } else if let u = b.imageURL {
                s = "![图片](\(u))\n\n"
            }
            return s + b.text
        case "bulleted-list", "numbered-list":
            let kids = b.node["children"] as? [[String: Any]]
                ?? []
            return kids.enumerated().map { i, k in
                let sub = k["children"] as? [[String: Any]]
                    ?? []
                let t = sub.compactMap {
                    $0["text"] as? String
                }.joined()
                return b.type == "numbered-list"
                    ? "\(i + 1). \(t)" : "- \(t)"
            }.joined(separator: "\n")
        default:
            return mdRuns(b.runs)
        }
    }

    static func html(title: String,
                     blocks: [BlockState]) -> String {
        var body: [String] = []
        if !title.isEmpty {
            body.append("<h1>\(esc(title))</h1>")
        }
        for b in blocks {
            body.append(htmlBlock(b))
        }
        return """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(title))</title>
        <style>body{font-family:-apple-system,'PingFang SC',sans-serif;line-height:1.75;max-width:720px;margin:24px auto;padding:0 16px;color:#1a1a1a}img{max-width:100%}blockquote{border-left:3px solid #005bbb62;margin:0;padding:4px 14px;background:#00000006}code{background:#0000000d;padding:1px 5px;border-radius:5px}pre code{display:block;padding:12px;overflow:auto}</style>
        </head><body>
        \(body.joined(separator: "\n"))
        </body></html>
        """
    }

    private static func htmlBlock(_ b: BlockState) -> String {
        let attrs = b.node["attrs"] as? [String: Any] ?? [:]
        switch b.type {
        case "heading":
            return "<h\(b.level + 1)>"
                + htmlRuns(b.runs) + "</h\(b.level + 1)>"
        case "todo":
            return "<p>\(b.checked ? "☑" : "☐") "
                + htmlRuns(b.runs) + "</p>"
        case "quote":
            return "<blockquote>" + htmlRuns(b.runs)
                + "</blockquote>"
        case "callout":
            return "<blockquote><strong>"
                + b.calloutTitle + "</strong><br>"
                + htmlRuns(b.runs) + "</blockquote>"
        case "codeBlock":
            return "<pre><code>" + esc(b.text)
                + "</code></pre>"
        case "divider":
            return "<hr>"
        case "image":
            if let u = b.imageURL {
                return "<p><img src=\"\(esc(u))\"></p>"
            }
            if let f = b.fileId {
                return "<p><img src=\"attachment://\(f)\"></p>"
            }
            return ""
        case "gallery":
            let items = attrs["items"] as? [[String: Any]]
                ?? []
            return items.map {
                if let u = $0["url"] as? String {
                    return "<p><img src=\"\(esc(u))\"></p>"
                }
                if let f = $0["fileId"] as? String {
                    return "<p><img src=\"attachment://\(f)\"></p>"
                }
                return ""
            }.joined(separator: "\n")
        case "musicCard", "linkCard":
            let meta = b.node["meta"] as? [String: Any] ?? [:]
            let t = (meta["title"] as? String) ?? b.type
            let u = (b.node["url"] as? String) ?? ""
            return "<p><a href=\"\(esc(u))\">\(esc(t))</a></p>"
        case "video":
            let u = b.imageURL ?? ""
            return "<p><a href=\"\(esc(u))\">视频</a></p>"
        case "attachment":
            let name = (attrs["name"] as? String) ?? "附件"
            return "<p>📎 \(esc(name))</p>"
        case "imgTextCard", "imageTextRow":
            var s = ""
            if let f = b.fileId {
                s = "<p><img src=\"attachment://\(f)\"></p>"
            } else if let u = b.imageURL {
                s = "<p><img src=\"\(esc(u))\"></p>"
            }
            return s + "<p>" + esc(b.text) + "</p>"
        case "bulleted-list", "numbered-list":
            let kids = b.node["children"] as? [[String: Any]]
                ?? []
            let tag = b.type == "numbered-list" ? "ol" : "ul"
            let lis = kids.map { k in
                let sub = k["children"] as? [[String: Any]]
                    ?? []
                let t = sub.compactMap {
                    $0["text"] as? String
                }.joined()
                return "<li>" + esc(t) + "</li>"
            }.joined()
            return "<\(tag)>\(lis)</\(tag)>"
        default:
            return "<p>" + htmlRuns(b.runs) + "</p>"
        }
    }
}

struct BlockRow: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var block: BlockState
    @StateObject private var rowUI = RowUI()

    final class RowUI: ObservableObject {
        @Published var showURLEdit = false
        @Published var urlDraft = ""
    }

    // 行面口径（Web editor.css）：常态无底无框；引用 =
    // 淡底+3px 蓝竖条+10 圆角，提示 = 语义淡底+12 圆角；
    // 块操作收进长按菜单（与原版一致，常驻按钮已撤）。
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if block.type == "todo" {
                Button {
                    editor.pushHistory()
                    block.checked.toggle()
                    var n = block.node
                    var attrs = n["attrs"] as? [String: Any]
                        ?? [:]
                    attrs["checked"] = block.checked
                    n["attrs"] = attrs
                    block.node = n
                    block.nodeVersion += 1
                    editor.scheduleSave()
                } label: {
                    Image(systemName: block.checked
                        ? "checkmark.circle.fill"
                        : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(block.checked
                            ? T.checkChecked : T.textSecondary)
                        .frame(width: 44, height: 44,
                               alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .padding(.trailing, -22)
            }
            if block.type == "image" {
                ImageBlockView(block: block, library: editor.library)
                    .padding(.horizontal, 36)
                    .onTapGesture {
                        if block.fileId == nil
                            && block.imageURL == nil {
                            editor.replaceImageBlockId = block.id
                            editor.showReplacePicker = true
                        } else {
                            editor.imageTarget = ImageTarget(
                                fileId: block.fileId,
                                urlString: block.imageURL,
                                name: block.node["name"] as? String
                                    ?? "图片")
                        }
                    }
            } else if block.type == "gallery" {
                GalleryBlockView(block: block, editor: editor)
            } else if block.type == "musicCard"
                        || block.type == "linkCard" {
                CardBlockView(block: block,
                              library: editor.library)
            } else if block.type == "video" {
                VideoBlockView(block: block,
                               library: editor.library)
            } else if block.type == "attachment" {
                AttachmentBlockView(block: block,
                                    editor: editor)
            } else if block.type == "imgTextCard"
                        || block.type == "imageTextRow" {
                ImgTextBlockView(block: block, editor: editor)
            } else if block.type == "divider" {
                Divider().padding(.vertical, 8)
            } else if block.type == "callout" {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: block.calloutIcon)
                            .font(.system(size: 14,
                                          weight: .semibold))
                        Text(block.calloutTitle)
                            .font(.system(size: 13,
                                          weight: .semibold))
                    }
                    .foregroundStyle(block.calloutAccent)
                    BlockTextView(block: block, editor: editor) {
                        editor.scheduleSave()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if block.isList {
                ListBlockView(block: block, editor: editor)
            } else if block.isText {
                if block.type == "quote" {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(T.quoteBar)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 0) {
                    BlockTextView(block: block, editor: editor) {
                        editor.scheduleSave()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if block.type == "heading"
                        && block.level == 1 {
                        Rectangle()
                            .fill(T.glassBorder)
                            .frame(height: 0.5)
                            .padding(.top, 6)
                    }
                }
                .padding(.top, block.type == "heading"
                    ? (block.level == 1 ? 14
                        : block.level == 2 ? 10 : 8) : 0)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text("\(block.type) 块 · 后续轮支持")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal,
                 block.type == "callout" || block.type == "quote"
                    || block.type == "codeBlock"
                    ? 14 : 0)
        .padding(.vertical, block.type == "callout" ? 12
                    : block.type == "quote" ? 10
                    : block.type == "codeBlock" ? 12 : 3)
        .background(rowBackground,
                    in: RoundedRectangle(cornerRadius:
                        block.type == "quote" ? 10 : 12))
        .background(GeometryReader { geo in
            // 原子块实测高回报（拖拽落点累加用；文本块由
            // UITextView recalc 回报）。
            Color.clear
                .onAppear {
                    if !block.isText {
                        block.height = geo.size.height
                    }
                }
                .onChange(of: geo.size.height) { h in
                    if !block.isText { block.height = h }
                }
        })
        .scaleEffect(editor.draggingId == block.id ? 0.97 : 1)
        .offset(y: editor.draggingId == block.id
            ? editor.dragDy : 0)
        .zIndex(editor.draggingId == block.id ? 1 : 0)
        .gesture(dragGesture, including: dragAllowed
            ? .all : .none)
        .alert("编辑链接", isPresented: Binding(
            get: { rowUI.showURLEdit },
            set: { rowUI.showURLEdit = $0 })) {
            TextField("https://…", text: Binding(
                get: { rowUI.urlDraft },
                set: { rowUI.urlDraft = $0 }))
            Button("取消", role: .cancel) {}
            Button("保存") {
                editor.pushHistory()
                var n = block.node
                n["url"] = rowUI.urlDraft
                block.node = n
                block.nodeVersion += 1
                editor.scheduleSave()
            }
        }
        .contextMenu {
            if block.type == "imgTextCard"
                || block.type == "imageTextRow" {
                Button("编辑") {
                    block.imgTextEditSignal += 1
                }
            }
            if block.type == "musicCard"
                || block.type == "linkCard" {
                Button("编辑") {
                    rowUI.urlDraft = block.node["url"]
                        as? String ?? ""
                    rowUI.showURLEdit = true
                }
            }
            if block.isText {
                Button("正文") {
                    editor.setBlockType(block, type: "paragraph")
                }
                Button("标题 1") {
                    editor.setBlockType(block, type: "heading",
                                        level: 1)
                }
                Button("标题 2") {
                    editor.setBlockType(block, type: "heading",
                                        level: 2)
                }
                Button("标题 3") {
                    editor.setBlockType(block, type: "heading",
                                        level: 3)
                }
                Button("待办") {
                    editor.setBlockType(block, type: "todo")
                }
                Button("引用") {
                    editor.setBlockType(block, type: "quote")
                }
                Button("提示") {
                    editor.setBlockType(block, type: "callout")
                }
            }
            Button(role: .destructive) {
                editor.deleteBlock(block)
            } label: {
                Label("删除块", systemImage: "trash")
            }
        }
    }

    private var rowBackground: Color {
        if editor.draggingId == block.id { return T.glassTint }
        switch block.type {
        case "callout": return block.calloutBg
        case "quote": return T.quoteBg
        case "codeBlock": return T.codeBg
        default: return .clear
        }
    }

    /// 编辑中的文本块长按 = 文本选择，永不拾起（Web 口径）。
    private var dragAllowed: Bool {
        !(block.isText && editor.editingBlockId == block.id)
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.48)
            .sequenced(before: DragGesture())
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if editor.draggingId == nil {
                        editor.draggingId = block.id
                    }
                    if editor.draggingId == block.id {
                        editor.dragDy = drag.translation.height
                    }
                default: break
                }
            }
            .onEnded { _ in
                if editor.draggingId == block.id {
                    editor.commitDrag()
                }
            }
    }
}

struct EditorView: View {
    @ObservedObject var editor: EditorModel
    @StateObject private var ui = EditorUI()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    final class EditorUI: ObservableObject {
        @Published var showPhotoPicker = false
        @Published var showFilePicker = false
        @Published var showMenu = false
        @Published var showExport = false
        @Published var showBgSheet = false
        @Published var showAttachChoice = false
        @Published var titleDraft = ""
        @Published var scrollY: CGFloat = 0
        @Published var shareURL: URL?
        var firstRowMinY: CGFloat?
    }

    // 编辑页口径（Web .detail/.editor-fab/.editor-title-dock）：
    // 悬浮玻璃圆钮（左返回/右更多，46px，top=安全区+7）+
    // 居中标题坞（72 头像圆 + 66 高标题胶囊，标题 14/600
    // 居中、副行 10px 日期·字数）；正文上距 155 口径。
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Color.clear
                        .frame(height: 0)
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: ListScrollKey.self,
                                value: geo.frame(
                                    in: .named("editorScroll"))
                                    .minY)
                        })
                    ForEach(editor.blocks) { block in
                        BlockRow(editor: editor, block: block)
                    }
                    addBar
                    // 正文下方空白点按落焦末个文本块末尾
                    // （Web 落焦热区口径：header 以下整页）。
                    Color.clear
                        .frame(height: 220)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let last = editor.blocks
                                .last(where: { $0.isText }) {
                                editor.focusBlockId = last.id
                                editor.focusCaretEnd = true
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.top, 168)
                .padding(.bottom, 40)
            }
            .coordinateSpace(name: "editorScroll")
            .onPreferenceChange(ListScrollKey.self) { y in
                if ui.firstRowMinY == nil {
                    ui.firstRowMinY = y
                }
                ui.scrollY = max(0, (ui.firstRowMinY ?? y) - y)
            }
            .background(T.memoBg(editor.bgColor))
            headerOverlay
                // 紧凑态切换（Web 口径）：0.25s 缓动。
                .animation(.easeInOut(duration: 0.25),
                           value: ui.scrollY > 30)
            if ui.showMenu {
                menuPanel
            }
        }
        .onAppear {
            ui.titleDraft = editor.title
            // 新建篇自动落焦首个文本块（Web 口径）。
            if editor.wantsInitialFocus {
                editor.wantsInitialFocus = false
                if let first = editor.blocks
                    .first(where: { $0.isText }) {
                    editor.focusBlockId = first.id
                    editor.focusCaretEnd = false
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { editor.imageTarget != nil },
            set: { if !$0 { editor.imageTarget = nil } })) {
            if let target = editor.imageTarget {
                ImagePageView(fileId: target.fileId,
                              urlString: target.urlString,
                              name: target.name,
                              library: editor.library)
            }
        }
        .onDisappear { editor.saveNow() }
        .sheet(isPresented: Binding(
            get: { ui.showPhotoPicker },
            set: { ui.showPhotoPicker = $0 })) {
            PhotoPicker { data in
                let fid = "att-" + UUID().uuidString
                    .prefix(12).lowercased()
                editor.library.putAttachment(fid, data)
                editor.addImageBlock(fileId: fid)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { editor.showReplacePicker },
            set: { editor.showReplacePicker = $0 })) {
            PhotoPicker { data in
                let fid = "att-" + UUID().uuidString
                    .prefix(12).lowercased()
                editor.library.putAttachment(fid, data)
                editor.replaceImage(fileId: fid)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { ui.showBgSheet },
            set: { ui.showBgSheet = $0 })) {
            bgSheet
        }
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
        .confirmationDialog("添加附件",
            isPresented: Binding(
                get: { ui.showAttachChoice },
                set: { ui.showAttachChoice = $0 }),
            titleVisibility: .visible) {
            Button("图片") { ui.showPhotoPicker = true }
            Button("文件") { ui.showFilePicker = true }
            Button("取消", role: .cancel) {}
        }
        .fileImporter(isPresented: Binding(
            get: { ui.showFilePicker },
            set: { ui.showFilePicker = $0 }),
            allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                if let data = try? Data(contentsOf: url) {
                    let fid = "att-" + UUID().uuidString
                        .prefix(12).lowercased()
                    editor.library.putAttachment(fid, data)
                    editor.addAttachmentBlock(
                        fileId: fid,
                        name: url.lastPathComponent,
                        size: data.count)
                }
            }
        }
    }

    // 页眉结构（根治）：单行 HStack = 返回钮 / 坞 / 更多
    // 钮，两侧等宽 Spacer 使坞居中、三者同顶线。旧
    // ZStack 叠层形态在真机上两钮不呈现（用户截图实
    // 证），弃用叠层、改流式同行布局，构造上不可能丢钮。
    private var headerOverlay: some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                commitTitle()
                editor.saveNow()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .frame(width: 46, height: 46)
                    .glassControl(radius: 999)
            }
            Spacer(minLength: 8)
            if ui.scrollY > 30 {
                // 紧凑态（Web 口径）：坞收成一行，meta 隐藏。
                HStack(spacing: 8) {
                    AvatarView(size: 32)
                    Text(editor.title.isEmpty
                        ? "无标题" : editor.title)
                        .font(.system(size: 14,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .glassControl(radius: 999)
            } else {
                VStack(spacing: 6) {
                    AvatarView(size: 72)
                    titleCapsule
                }
            }
            Spacer(minLength: 8)
            Button {
                ui.showMenu.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .frame(width: 46, height: 46)
                    .glassControl(radius: 999)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
    }

    /// 标题提交（Web 口径）：仅失焦/回车提交，编辑中不落
    /// 盘；非编辑态超 10 字截断显示。
    private func commitTitle() {
        if ui.titleDraft != editor.title {
            editor.pushHistory()
            editor.title = ui.titleDraft
            editor.scheduleSave()
        }
    }

    private var titleCapsule: some View {
        VStack(spacing: 3) {
            if titleFocused || ui.titleDraft.count <= 10 {
                TextField("无标题", text: Binding(
                    get: { ui.titleDraft },
                    set: { ui.titleDraft = $0 }))
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(T.textMain)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { f in
                        if !f { commitTitle() }
                    }
            } else {
                Text(String(ui.titleDraft.prefix(10)) + "…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineLimit(1)
                    .onTapGesture { titleFocused = true }
            }
            Text(metaLine)
                .font(.system(size: 10))
                .foregroundStyle(T.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(width: capsuleWidth, height: 66)
        .glassControl(radius: 33)
        .animation(.easeInOut(duration: 0.2),
                   value: ui.titleDraft)
    }

    private var capsuleWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let shown = ui.titleDraft.isEmpty
            ? "无标题"
            : (ui.titleDraft.count > 10 && !titleFocused
                ? String(ui.titleDraft.prefix(10)) + "…"
                : ui.titleDraft)
        let titleW = shown.size(
            withAttributes: [.font: font]).width
        // 胶囊宽须同时容下 meta 行（旧版只量标题，meta
        // 被截断成「2026年1...」，真机截图实证）。
        let metaFont = UIFont.systemFont(ofSize: 10)
        let metaW = metaLine.size(
            withAttributes: [.font: metaFont]).width
        let maxW = UIScreen.main.bounds.width - 124
        return min(max(max(titleW, metaW) + 40, 66), maxW)
    }

    /// meta（Web 口径）：相对更新时间 · 正文字数。
    private var metaLine: String {
        "\(editor.item.ago) · 共 \(editor.wordCount) 字"
    }

    /// 背景色底表（Web BgSheet 口径）：8 色点 + 移除行。
    private var bgSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("背景色")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text("为当前笔记设置专属底色")
                    .font(.system(size: 12))
                    .foregroundStyle(T.textSecondary)
            }
            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible()), count: 4),
                      spacing: 14) {
                ForEach(Self.bgColors, id: \.self) { hex in
                    Button {
                        editor.setBgColor(hex)
                        ui.showBgSheet = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(T.colorOf(hex))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(
                                    T.glassBorder,
                                    lineWidth: 0.5))
                            if editor.bgColor == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(
                                        size: 17,
                                        weight: .semibold))
                                    .foregroundStyle(T.accent)
                            }
                        }
                    }
                }
            }
            if editor.bgColor != nil {
                Button(role: .destructive) {
                    editor.setBgColor(nil)
                    ui.showBgSheet = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("移除背景色")
                                .font(.system(size: 15))
                            Text("恢复为默认底色")
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    T.textSecondary)
                        }
                    }
                    .foregroundStyle(T.danger)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.bg)
        .presentationDetents([.height(300)])
    }

    static let bgColors = ["#eaeef2", "#e8e0d4", "#d4e8d0",
                           "#d0e0e8", "#e8d0d4", "#fff3e0",
                           "#e8e0f0", "#f0e8d0"]

    // ••• 面板（Web .editor-menu-panel 度量：宽 246、radius
    // 22、玻璃 overlay、行高 50、图标 accent）。条目 =
    // Web 六项口径（双栏开关仅宽屏显示，iPhone 竖屏同
    // Web 的 display:none 不呈现）+ 末尾删除（走列表同
    // 一 8 秒撤销口径）。
    private var menuPanel: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    ui.showMenu = false
                    ui.showExport = false
                }
            if ui.showExport {
                exportPanel
            } else {
                VStack(spacing: 0) {
                    menuItem(icon: "arrow.uturn.backward",
                             title: "撤销",
                             sub: "Cmd+Z · 三指左滑",
                             dimmed: !editor.canUndo) {
                        editor.undo()
                        ui.showMenu = false
                    }
                    menuItem(icon: "arrow.uturn.forward",
                             title: "重做",
                             sub: "Cmd+Shift+Z · 三指右滑",
                             dimmed: !editor.canRedo) {
                        editor.redo()
                        ui.showMenu = false
                    }
                    menuItem(icon: "paperclip",
                             title: "添加附件",
                             sub: "图片、PDF 或文本文件",
                             chevron: true) {
                        ui.showMenu = false
                        ui.showAttachChoice = true
                    }
                    menuItem(icon: "square.and.arrow.up",
                             title: "导出笔记",
                             sub: "Markdown · HTML · PDF",
                             chevron: true) {
                        ui.showExport = true
                    }
                    menuItem(icon: "paintpalette",
                             title: "更换背景色",
                             sub: "为当前笔记设置专属底色",
                             chevron: true) {
                        ui.showMenu = false
                        ui.showBgSheet = true
                    }
                    Divider().padding(.vertical, 4)
                    menuItem(icon: "trash", title: "删除备忘",
                             danger: true) {
                        ui.showMenu = false
                        editor.library.softRemove(editor.item)
                        dismiss()
                    }
                }
                .padding(7)
                .frame(width: 246)
                .glassCard(radius: 22)
                .padding(.top, 59)
                .padding(.trailing, 16)
            }
        }
    }

    /// 导出面板（Web 口径）：返回钮 + 三格式行 + 尾注。
    private var exportPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    ui.showExport = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 30, height: 30)
                }
                Text("导出笔记")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            exportChoice(badge: "MD", label: "Markdown",
                         detail: "保存为 .md 文件") {
                shareExported(editor.exportFile(
                    format: "md"))
            }
            exportChoice(badge: "<>", label: "HTML",
                         detail: "保存为独立网页") {
                shareExported(editor.exportFile(
                    format: "html"))
            }
            exportChoice(badge: "PDF", label: "PDF",
                         detail: "打印或存储为 PDF") {
                ui.showMenu = false
                ui.showExport = false
                editor.exportPDF { url in
                    if let url { ui.shareURL = url }
                }
            }
            Text("PDF 将生成文件，可通过分享存储或打印。")
                .font(.system(size: 11))
                .foregroundStyle(T.textSecondary)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 6)
        }
        .padding(7)
        .frame(width: 246)
        .glassCard(radius: 22)
        .padding(.top, 59)
        .padding(.trailing, 16)
    }

    private func shareExported(_ url: URL?) {
        ui.showMenu = false
        ui.showExport = false
        if let url { ui.shareURL = url }
    }

    private func exportChoice(badge: String, label: String,
                              detail: String,
                              action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(badge)
                    .font(.system(size: badge == "PDF"
                        ? 10 : 12, weight: .bold))
                    .foregroundStyle(T.accent)
                    .frame(width: 30, height: 30)
                    .background(T.glassControlTint,
                                in: RoundedRectangle(
                                    cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 15,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(T.textSecondary)
                }
                Spacer()
                Text("›")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        T.textSecondary.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
    }

    private func menuItem(icon: String, title: String,
                          sub: String? = nil,
                          chevron: Bool = false,
                          dimmed: Bool = false,
                          danger: Bool = false,
                          action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(danger ? T.danger : T.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15,
                                      weight: .semibold))
                        .foregroundStyle(danger ? T.danger
                                         : T.textMain)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(T.textSecondary)
                    }
                }
                Spacer()
                if chevron {
                    Text("›")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            T.textSecondary.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.45 : 1)
        }
    }

    private var addBar: some View {
        HStack(spacing: 4) {
            Button {
                editor.addBlock()
            } label: {
                Image(systemName: "text.alignleft")
                    .frame(width: 52, height: 40)
            }
            Button {
                ui.showPhotoPicker = true
            } label: {
                Image(systemName: "photo")
                    .frame(width: 52, height: 40)
            }
            Button {
                ui.showFilePicker = true
            } label: {
                Image(systemName: "paperclip")
                    .frame(width: 52, height: 40)
            }
        }
        .font(.system(size: 17))
        .foregroundStyle(T.textMain)
        .glassControl(radius: 999)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}

// ── gallery / 卡片 / 视频 / 附件块 ─────────────────
struct GalleryBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel

    var items: [[String: Any]] {
        (block.node["attrs"] as? [String: Any])?["items"]
            as? [[String: Any]] ?? []
    }

    var body: some View {
        // Web 口径：网格平铺全部图，点任一图进图片页。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100),
                                     spacing: 6)],
                  spacing: 6) {
            ForEach(Array(items.enumerated()),
                    id: \.offset) { _, it in
                ItemImageView(
                    fileId: it["fileId"] as? String,
                    urlString: (it["url"] as? String)
                        ?? (it["src"] as? String),
                    library: editor.library)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(
                        cornerRadius: 8))
                    .onTapGesture {
                        editor.imageTarget = ImageTarget(
                            fileId: it["fileId"] as? String,
                            urlString: (it["url"] as? String)
                                ?? (it["src"] as? String),
                            name: (it["name"] as? String)
                                ?? "图片")
                    }
            }
        }
    }
}

struct CardBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    @Environment(\.openURL) private var openURL

    // 卡数据在 node 顶层 url + meta{title,subtitle,cover,
    // source}（core 口径）；attrs 读法只对旧形兜底。
    var meta: [String: Any] {
        block.node["meta"] as? [String: Any] ?? [:]
    }
    var attrs: [String: Any] {
        block.node["attrs"] as? [String: Any] ?? [:]
    }
    var cardURL: String? {
        (block.node["url"] as? String)
            ?? (attrs["url"] as? String)
    }
    var status: String {
        block.node["status"] as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            ItemImageView(
                fileId: attrs["fileId"] as? String,
                urlString: (meta["cover"] as? String)
                    ?? (attrs["cover"] as? String)
                    ?? (attrs["image"] as? String)
                    ?? (attrs["thumbnail"] as? String),
                library: library)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text((meta["title"] as? String)
                        ?? (attrs["title"] as? String)
                        ?? (attrs["name"] as? String)
                        ?? (block.type == "musicCard"
                            ? "音乐卡片" : "链接卡片"))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if status == "loading" {
                ProgressView()
            } else if status == "error" {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(T.danger)
            } else {
                Image(systemName: block.type == "musicCard"
                    ? "music.note" : "link")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if status != "loading", let s = cardURL,
               let u = URL(string: s) {
                openURL(u)
            }
        }
    }

    private var subtitle: String {
        if status == "loading" { return "解析中…" }
        if status == "error" { return "解析失败" }
        return (meta["subtitle"] as? String)
            ?? (meta["source"] as? String)
            ?? (attrs["artist"] as? String)
            ?? (attrs["source"] as? String)
            ?? (attrs["desc"] as? String) ?? ""
    }
}

final class PlayerState: ObservableObject {
    @Published var url: URL?
}

struct VideoBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    @StateObject private var player = PlayerState()

    var body: some View {
        Button {
            play()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title3)
                Text("视频 · 点按播放")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
        .sheet(isPresented: Binding(
            get: { player.url != nil },
            set: { if !$0 { player.url = nil } })) {
            if let url = player.url {
                PlayerView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    private func play() {
        if let s = block.imageURL, let u = URL(string: s) {
            player.url = u
        } else if let fid = block.fileId {
            DispatchQueue.global(qos: .userInitiated).async {
                let data = library.attachmentData(fid)
                let path = NSTemporaryDirectory()
                    + "video-\(fid).mov"
                try? data.write(to: URL(fileURLWithPath: path))
                DispatchQueue.main.async {
                    player.url = URL(fileURLWithPath: path)
                }
            }
        }
    }
}

struct PlayerView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(
        context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.player?.play()
        return vc
    }
    func updateUIViewController(
        _ vc: AVPlayerViewController, context: Context) {}
}

final class ShareState: ObservableObject {
    @Published var url: URL?
}

struct AttachmentBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @StateObject private var shareState = ShareState()

    var library: Library { editor.library }

    static let imageExts: Set<String> = ["png", "jpg", "jpeg",
        "gif", "webp", "heic", "heif", "bmp"]

    var files: [(String, String)] {
        let attrs = block.node["attrs"] as? [String: Any] ?? [:]
        if let items = attrs["items"] as? [[String: Any]] {
            return items.compactMap { it in
                guard let fid = it["fileId"] as? String
                else { return nil }
                return (fid, (it["name"] as? String) ?? fid)
            }
        }
        if let fid = attrs["fileId"] as? String {
            return [(fid, (attrs["name"] as? String) ?? fid)]
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files, id: \.0) { fid, name in
                Button {
                    // 图片类附件进图片页，其余走分享（Web
                    // 文件行分发口径）。
                    if Self.imageExts.contains(
                        (name as NSString).pathExtension
                            .lowercased()) {
                        editor.imageTarget = ImageTarget(
                            fileId: fid, urlString: nil,
                            name: name)
                    } else {
                        share(fid: fid, name: name)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperclip")
                        Text(name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName:
                            "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if files.isEmpty {
                Text("附件（无文件）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: Binding(
            get: { shareState.url != nil },
            set: { if !$0 { shareState.url = nil } })) {
            if let url = shareState.url { ShareSheet(url: url) }
        }
    }

    private func share(fid: String, name: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let data = library.attachmentData(fid)
            let safe = name.replacingOccurrences(of: "/",
                                                 with: "_")
            let path = NSTemporaryDirectory() + safe
            try? data.write(to: URL(fileURLWithPath: path))
            DispatchQueue.main.async {
                shareState.url = URL(fileURLWithPath: path)
            }
        }
    }
}

struct ImgTextBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @StateObject private var ui = ImgTextUI()

    final class ImgTextUI: ObservableObject {
        @Published var editing = false
        @Published var draft = ""
    }

    var body: some View {
        Group {
            if block.type == "imgTextCard" {
                VStack(alignment: .leading, spacing: 8) {
                    ItemImageView(fileId: block.fileId,
                                  urlString: block.imageURL,
                                  library: editor.library)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(
                            cornerRadius: 8))
                        .onTapGesture { openImagePage() }
                    textLabel
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 10) {
                    ItemImageView(fileId: block.fileId,
                                  urlString: block.imageURL,
                                  library: editor.library)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(
                            cornerRadius: 8))
                        .onTapGesture { openImagePage() }
                    textLabel
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
        .onChange(of: block.imgTextEditSignal) { _ in
            ui.draft = block.text
            ui.editing = true
        }
        .sheet(isPresented: Binding(
            get: { ui.editing },
            set: { ui.editing = $0 })) {
            NavigationStack {
                TextEditor(text: Binding(
                    get: { ui.draft },
                    set: { ui.draft = $0 }))
                    .padding(12)
                    .navigationTitle("图文文本")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { ui.editing = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                block.node["text"] = ui.draft
                                block.text = ui.draft
                                editor.scheduleSave()
                                ui.editing = false
                            }
                        }
                    }
            }
        }
    }

    private func openImagePage() {
        editor.imageTarget = ImageTarget(
            fileId: block.fileId, urlString: block.imageURL,
            name: (block.node["name"] as? String) ?? "图片")
    }

    private var textLabel: some View {
        Text(block.text.isEmpty ? "点击查看完整文本" : block.text)
            .font(.system(size: 14))
            .foregroundStyle(block.text.isEmpty
                ? T.textSecondary : T.textMain)
            .lineLimit(3)
            .contentShape(Rectangle())
            .onTapGesture {
                ui.draft = block.text
                ui.editing = true
            }
    }
}

// ── 设计令牌（与 Web tokens.css 逐值对齐，明暗双写） ──
enum T {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? dark : light)
        })
    }
    static var bg: Color { dyn(0xF2F2F7, 0x000000) }
    static var textMain: Color { dyn(0x1A1A1A, 0xFFFFFF) }
    static var textSecondary: Color { dyn(0x68686D, 0x98989D) }
    static var accent: Color { dyn(0x007AFF, 0x007AFF) }
    static var warning: Color { dyn(0xFF9500, 0xFF9500) }
    static var danger: Color { dyn(0xE0433A, 0xE0433A) }
    static var glassTint: Color {
        dynA(0xFFFFFF, 0.74, 0x202024, 0.86)
    }
    static var glassControlTint: Color {
        dynA(0xFFFFFF, 0.90, 0x38383C, 0.96)
    }
    static var glassBorder: Color {
        dynA(0x000000, 0.16, 0xFFFFFF, 0.16)
    }
    static var quoteBg: Color {
        dynA(0x000000, 0.025, 0xFFFFFF, 0.045)
    }
    /// 代码块底（Web --code-bg 口径近似：中性淡染）。
    static var codeBg: Color {
        dynA(0x000000, 0.045, 0xFFFFFF, 0.07)
    }
    static var quoteBar: Color {
        dynA(0x005BBB, 0.62, 0x72B7FF, 0.72)
    }
    static var quoteText: Color { dyn(0x626267, 0xB4B4B9) }
    static var iconMuted: Color { dyn(0x8A9BB0, 0xE5E7EB) }

    /// 备忘专属底色（Web bgColor 口径）：浅色原色、深色
    /// 压暗；无色回根背景。
    static func memoBg(_ hex: String?) -> Color {
        guard let hex, let rgb = rgbOf(hex) else { return bg }
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(
                    red: rgb.0 * 0.55, green: rgb.1 * 0.55,
                    blue: rgb.2 * 0.55, alpha: 1)
            }
            return UIColor(red: rgb.0, green: rgb.1,
                           blue: rgb.2, alpha: 1)
        })
    }

    static func rgbOf(_ hex: String)
        -> (CGFloat, CGFloat, CGFloat)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16)
        else { return nil }
        return (CGFloat((v >> 16) & 0xFF) / 255,
                CGFloat((v >> 8) & 0xFF) / 255,
                CGFloat(v & 0xFF) / 255)
    }

    static func colorOf(_ hex: String) -> Color {
        guard let rgb = rgbOf(hex) else { return .clear }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// Callout 五变体（Web editor.css .callout-* 口径）。
    static func calloutBg(_ v: String) -> Color {
        switch v {
        case "tip": return dyn(0xEAF7EE, 0x14301C)
        case "warning": return dyn(0xFFF4E0, 0x3A2A10)
        case "important": return dyn(0xF1EAFB, 0x2A1E44)
        case "caution": return dyn(0xFDECEA, 0x3D1713)
        default: return dyn(0xEAF2FE, 0x12283F)
        }
    }
    static func calloutAccent(_ v: String) -> Color {
        switch v {
        case "tip": return dyn(0x2EA043, 0x3FB950)
        case "warning": return dyn(0xD97706, 0xFF9500)
        case "important": return dyn(0x8250DF, 0xA371F7)
        case "caution": return dyn(0xE0433A, 0xFF6961)
        default: return dyn(0x007AFF, 0x0A84FF)
        }
    }
    static var quoteTextUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0xB4B4B9 : 0x626267)
        }
    }
    static var calloutNote: Color {
        dynA(0x007AFF, 0.07, 0x0A84FF, 0.18)
    }
    static var checkChecked: Color { dyn(0x0066CC, 0x0A84FF) }
    static var linkBlue: Color { dyn(0x005BBB, 0x72B7FF) }
    static func dynA(_ light: UInt32, _ la: Double,
                     _ dark: UInt32, _ da: Double) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(da)
                : UIColor(rgb: light).withAlphaComponent(la)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// 玻璃面（Web --glass-content 口径：材质模糊 + 染色 +
/// 0.5px 边；无投影，与原版一致）。
struct GlassCard: ViewModifier {
    var radius: CGFloat = 32
    var control: Bool = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(control ? T.glassControlTint
                                  : T.glassTint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(T.glassBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func glassCard(radius: CGFloat = 32) -> some View {
        modifier(GlassCard(radius: radius))
    }
    func glassControl(radius: CGFloat) -> some View {
        modifier(GlassCard(radius: radius, control: true))
    }
}

// ── 首页派生（封面/摘要/相对时间/标签，口径同 Web list） ──
extension MemoItem {
    var coverFileId: String? { cover.0 }
    var coverURL: String? { cover.1 }

    private var cover: (String?, String?) {
        func probe(_ nodes: [[String: Any]])
            -> (String?, String?)? {
            for n in nodes {
                let ty = n["type"] as? String ?? ""
                let attrs = n["attrs"] as? [String: Any] ?? [:]
                switch ty {
                case "image", "imgTextCard", "imageTextRow":
                    if let f = attrs["fileId"] as? String,
                       !f.isEmpty { return (f, nil) }
                    if let u = (attrs["url"] as? String)
                        ?? (attrs["src"] as? String) {
                        return (nil, u)
                    }
                case "gallery":
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items {
                        if let f = it["fileId"] as? String,
                           !f.isEmpty { return (f, nil) }
                        if let u = it["url"] as? String {
                            return (nil, u)
                        }
                    }
                case "attachment":
                    if attrs["image"] as? Bool ?? false,
                       let f = attrs["fileId"] as? String,
                       !f.isEmpty { return (f, nil) }
                default:
                    break
                }
                if let kids = n["children"] as? [[String: Any]],
                   let hit = probe(kids) {
                    return hit
                }
            }
            return nil
        }
        return probe(blocks.map { $0.node }) ?? (nil, nil)
    }

    var hasCover: Bool { coverFileId != nil || coverURL != nil }

    /// 归组日期：createdAt 优先（Web 口径），解析失败回退
    /// updatedAt——按更新时间归组会让老备忘一编辑就跳组。
    var bucketDate: Date {
        Clock.parseISO(createdAt) ?? updatedDate
    }

    /// 段落首块的首个文本段（Web summarize/scan_tags 的
    /// 取材口径：只取段落块第一个子节点的文本）。
    var firstParaText: String {
        guard let para = blocks.first(
            where: { $0.type == "paragraph" }) else { return "" }
        let kids = para.node["children"] as? [[String: Any]]
            ?? []
        for k in kids {
            if let t = k["text"] as? String { return t }
            if k["type"] as? String == "link" {
                let lk = k["children"] as? [[String: Any]] ?? []
                if let t = lk.first?["text"] as? String {
                    return t
                }
            }
        }
        return ""
    }

    /// 字符级标签扫描（Web scan_tags）：任意位置的 #词，
    /// 标签字符 = 字母数字/_/-/CJK 等 alphanumerics。
    var tags: [String] {
        var out: [String] = []
        var cur = ""
        var inTag = false
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "_-"))
        for ch in firstParaText {
            if ch == "#" {
                if inTag, !cur.isEmpty, !out.contains(cur) {
                    out.append(cur)
                }
                cur = ""
                inTag = true
            } else if inTag {
                if ch.unicodeScalars.allSatisfy(
                    { allowed.contains($0) }) {
                    cur.append(ch)
                } else {
                    if !cur.isEmpty, !out.contains(cur) {
                        out.append(cur)
                    }
                    cur = ""
                    inTag = false
                }
            }
            if out.count >= 3 { break }
        }
        if inTag, !cur.isEmpty, !out.contains(cur),
           out.count < 3 {
            out.append(cur)
        }
        return out
    }

    /// Web summarize：段落首段文本 → 剥 MD 语法 → 剥标签
    /// → 截断（文本卡 80 / 图文卡 60）；为空回退首个标签
    /// 名，再回退「无更多文本」。
    func summary(isImage: Bool) -> String {
        var t = firstParaText
        // 链接 [文](址) → 文
        while let lb = t.firstIndex(of: "["),
              let rb = t[lb...].firstIndex(of: "]"),
              t[rb...].hasPrefix("]("),
              let rp = t[rb...].firstIndex(of: ")") {
            let inner = t[t.index(after: lb)..<rb]
            t.replaceSubrange(lb...rp, with: inner)
        }
        var lines: [String] = []
        for rawLine in t.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(
                in: .whitespaces)
            while line.hasPrefix("#") || line.hasPrefix(">") {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ")
                || line.hasPrefix("+ ") {
                line = String(line.dropFirst(2))
            }
            lines.append(line)
        }
        t = lines.joined(separator: " ")
        for ch in ["**", "__", "==", "~~", "`", "*"] {
            t = t.replacingOccurrences(of: ch, with: "")
        }
        // 剥 #标签词
        for tag in tags {
            t = t.replacingOccurrences(of: "#\(tag)", with: "")
        }
        t = t.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        if t.isEmpty {
            return tags.first ?? "无更多文本"
        }
        return String(t.prefix(isImage ? 60 : 80))
    }

    /// Web time_ago 四分支：今天→时刻（随系统 12/24 时
    /// 制）、昨天→「昨天」、同年→M/D、跨年→Y/M/D。
    var ago: String {
        let d = updatedDate
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) {
            let tmpl = DateFormatter.dateFormat(
                fromTemplate: "j", options: 0,
                locale: Locale.current) ?? ""
            if tmpl.contains("a") {
                let h = cal.component(.hour, from: d)
                f.dateFormat = h < 12 ? "'上午' h:mm" : "'下午' h:mm"
            } else {
                f.dateFormat = "HH:mm"
            }
            return f.string(from: d)
        }
        if cal.isDateInYesterday(d) { return "昨天" }
        if cal.component(.year, from: d)
            == cal.component(.year, from: Date()) {
            f.dateFormat = "M/d"
        } else {
            f.dateFormat = "yyyy/M/d"
        }
        return f.string(from: d)
    }

    /// 图文卡判定（Web has_image 按块形）：含图类块或
    /// 图片附件即图文卡，与封面能否派生无关。
    var hasImageShape: Bool {
        for b in blocks {
            switch b.type {
            case "image", "gallery", "imgTextCard",
                 "imageTextRow":
                return true
            case "attachment":
                let attrs = b.node["attrs"] as? [String: Any]
                if attrs?["image"] as? Bool == true {
                    return true
                }
                let items = attrs?["items"]
                    as? [[String: Any]] ?? []
                let single = attrs?["fileId"] as? String
                let names = items.compactMap {
                    ($0["name"] as? String)
                        ?? ($0["fileName"] as? String)
                } + [attrs?["name"] as? String].compactMap { $0 }
                let exts = ["png", "jpg", "jpeg", "gif",
                            "webp", "heic", "heif", "bmp"]
                if single != nil || !items.isEmpty {
                    if names.contains(where: { n in
                        exts.contains(
                            (n as NSString).pathExtension
                                .lowercased())
                    }) { return true }
                }
            default:
                break
            }
        }
        return false
    }
}

// ── 恐龙线稿头像（与 Web icons.rs DINO_PATHS 同一份
// path 数据，viewBox 512，描边 icon-muted/22/圆头） ──
struct DinoView: View {
    var size: CGFloat

    static let paths: [String] = [
        "M 90,460 L 90,170 C 90,110 140,70 210,70 L 380,95 C 440,95 470,130 470,185 C 470,225 450,240 410,245 C 350,250 280,230 210,265 C 190,275 190,295 210,310 C 270,350 350,380 410,360 C 435,350 440,325 410,315",
        "M 160,330 C 180,380 230,440 280,460",
        "M 240,365 C 220,400 240,440 310,460",
        "M 90,460 L 310,460",
        "M 415,135 C 425,140 435,150 435,160",
        "M 230,115 C 260,95 310,120 355,140",
        "M 255,140 C 255,170 290,195 320,185 C 345,175 350,150 335,135",
        "M 290,145 C 290,165 315,165 315,150",
        "M 250,243 L 255,265 L 265,243 M 275,245 L 282,270 L 292,245 M 302,246 L 310,273 L 320,247 M 330,248 L 340,275 L 350,248 M 360,249 L 370,274 L 380,248 M 390,248 L 400,270 L 408,246 M 415,244 L 425,263 L 432,240 M 438,235 L 448,252 L 452,228",
        "M 250,323 L 255,305 L 263,326 M 273,329 L 280,308 L 288,333 M 298,336 L 306,313 L 314,340 M 324,343 L 333,318 L 341,346 M 351,348 L 361,323 L 369,351 M 379,352 L 389,328 L 396,353 M 404,351 L 413,330 L 418,348",
    ]

    /// 极简 SVG path 解析（仅 M/L/C，与 DINO_PATHS 实际
    /// 用到的命令集一致），坐标按 viewBox 512 缩放。
    static func parse(_ d: String, scale s: CGFloat) -> Path {
        var path = Path()
        let tokens = d.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
        var i = 0
        var cmd = ""
        func num() -> CGFloat {
            defer { i += 1 }
            return (CGFloat(Double(tokens[i]) ?? 0)) * s
        }
        while i < tokens.count {
            if tokens[i].allSatisfy({ $0.isLetter }) {
                cmd = tokens[i]
                i += 1
                if cmd == "M" {
                    let x = num(), y = num()
                    path.move(to: CGPoint(x: x, y: y))
                    cmd = "L"
                }
                continue
            }
            switch cmd {
            case "L":
                let x = num(), y = num()
                path.addLine(to: CGPoint(x: x, y: y))
            case "C":
                let x1 = num(), y1 = num()
                let x2 = num(), y2 = num()
                let x = num(), y = num()
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: x1, y: y1),
                    control2: CGPoint(x: x2, y: y2))
            default:
                i += 1
            }
        }
        return path
    }

    var body: some View {
        let s = size / 512
        ZStack {
            ForEach(0..<Self.paths.count, id: \.self) { i in
                Self.parse(Self.paths[i], scale: s)
                    .stroke(T.iconMuted,
                            style: StrokeStyle(
                                lineWidth: 22 * s,
                                lineCap: .round,
                                lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 头像面：玻璃圆 + 恐龙线稿（自定义头像图 E13 后续）。
struct AvatarView: View {
    var size: CGFloat
    var body: some View {
        DinoView(size: size * 0.72)
            .frame(width: size, height: size)
            .glassControl(radius: 999)
    }
}

// ── 列表 ───────────────────────────────────────────
struct ListScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat,
                       nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ListView: View {
    @ObservedObject var library: Library
    @StateObject private var nav = NavState()
    // 文字大小跟随系统 Dynamic Type（Web 分级是无系统
    // API 时的替代口径，原生走更优路）。
    @ScaledMetric(relativeTo: .body)
    private var groupFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body)
    private var metaFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body)
    private var titleFontScale: CGFloat = 1.0

    final class NavState: ObservableObject {
        @Published var dest: Dest?
        @Published var query = ""
        @Published var searchOpen = false
        @Published var expandedKeys: Set<String> = []
        @Published var scrollOffset: CGFloat = 0
        var firstRowMinY: CGFloat?
    }

    enum Dest: Identifiable {
        case editor(EditorModel)
        case settings
        var id: String {
            switch self {
            case .editor(let e): return "editor-\(e.item.id)"
            case .settings: return "settings"
            }
        }
    }

    var visibleMemos: [MemoItem] {
        guard let hits = library.searchHits else {
            return library.memos
        }
        return library.memos.filter { hits.contains($0.id) }
    }

    struct MemoGroup: Identifiable {
        let id: String
        let title: String
        let memos: [MemoItem]
        var images: [MemoItem] { memos.filter { $0.hasImageShape } }
        var texts: [MemoItem] {
            memos.filter { !$0.hasImageShape }
        }
    }

    /// 归组按 createdAt（Web 口径）：置顶/今天/昨天/过去
    /// 7天/过去30天/{m}月（同年）/{y}年（跨年）。
    var groups: [MemoGroup] {
        let pinned = visibleMemos.filter { $0.pinned }
        let rest = visibleMemos.filter { !$0.pinned }
        var out: [MemoGroup] = []
        if !pinned.isEmpty {
            out.append(MemoGroup(id: "置顶", title: "置顶",
                                 memos: pinned))
        }
        let cal = Calendar.current
        let now = Date()
        func bucket(_ d: Date) -> String {
            let days = cal.dateComponents(
                [.day], from: cal.startOfDay(for: d),
                to: cal.startOfDay(for: now)).day ?? 999
            if days <= 0 { return "今天" }
            if days == 1 { return "昨天" }
            if days < 7 { return "过去7天" }
            if days < 30 { return "过去30天" }
            let y = cal.component(.year, from: d)
            if y == cal.component(.year, from: now) {
                return "\(cal.component(.month, from: d))月"
            }
            return "\(y)年"
        }
        var byBucket: [String: [MemoItem]] = [:]
        var bucketNewest: [String: Date] = [:]
        for m in rest {
            let b = bucket(m.bucketDate)
            byBucket[b, default: []].append(m)
            if m.bucketDate > (bucketNewest[b] ?? .distantPast) {
                bucketNewest[b] = m.bucketDate
            }
        }
        let fixed = ["今天", "昨天", "过去7天", "过去30天"]
        var names = fixed.filter { byBucket[$0] != nil }
        let far = byBucket.keys.filter { !fixed.contains($0) }
            .sorted {
                (bucketNewest[$0] ?? .distantPast)
                    > (bucketNewest[$1] ?? .distantPast)
            }
        names += far
        for name in names {
            if let g = byBucket[name], !g.isEmpty {
                out.append(MemoGroup(id: name, title: name,
                                     memos: g))
            }
        }
        return out
    }

    // 首页形态对齐 Web 原版：自定义页眉（右上玻璃动作钮 +
    // 34/800 大标题）+ 玻璃搜索胶囊 + 新建卡 + 分组胶囊卡。
    // 滚动/左滑用原生 List（无 Section，梯子定案禁区）。
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if !library.notice.isEmpty {
                    Text(library.notice)
                        .font(.system(size: 12))
                        .foregroundStyle(T.textSecondary)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                List {
                    if !library.loadFailed {
                        newCardRow
                    }
                    ForEach(groups) { group in
                        groupHeader(group.title)
                        sublist(group: group, kind: "img",
                                memos: group.images)
                        if !group.images.isEmpty
                            && !group.texts.isEmpty {
                            Color.clear
                                .frame(height: 16)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        sublist(group: group, kind: "txt",
                                memos: group.texts)
                    }
                    if visibleMemos.isEmpty {
                        emptyRow
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .coordinateSpace(name: "momentList")
                .onPreferenceChange(ListScrollKey.self) { y in
                    if nav.firstRowMinY == nil {
                        nav.firstRowMinY = y
                    }
                    let base = nav.firstRowMinY ?? y
                    nav.scrollOffset = max(0, base - y)
                }
                if library.pendingDeletion != nil {
                    undoToast
                }
            }
            .animation(.spring(response: 0.28,
                               dampingFraction: 0.86),
                       value: library.pendingDeletion?.id ?? "")
            .background(T.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { nav.dest != nil },
                set: { if !$0 { nav.dest = nil } })) {
                switch nav.dest {
                case .editor(let editor):
                    EditorView(editor: editor)
                case .settings:
                    SettingsView(library: library)
                case nil:
                    EmptyView()
                }
            }
            .onAppear {
                library.markFirstFrame()
                if library.memos.isEmpty { library.load() }
            }
        }
    }

    /// 紧凑进度：scrollY/30（Web 口径）。
    private var compactP: CGFloat {
        min(max(nav.scrollOffset / 30, 0), 1)
    }

    // 页眉（Web 口径）：左侧 72 头像即标题区（点进设置，
    // 无大文本标题）+ 右侧 66 高两态搜索胶囊；滚动紧凑
    // 时头像渐缩淡出、搜索隐藏、中央出现「此刻」胶囊。
    private var header: some View {
        ZStack {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    nav.dest = .settings
                } label: {
                    AvatarView(size: 72)
                }
                .scaleEffect(1 - 0.45 * compactP,
                             anchor: .leading)
                .opacity(1 - compactP)
                .allowsHitTesting(compactP < 0.5)
                Spacer()
                searchCapsule
                    .opacity(1 - compactP)
                    .allowsHitTesting(compactP < 0.5)
            }
            Button {
                nav.dest = .settings
            } label: {
                CompactTitle(text: "此刻")
            }
            .opacity(compactP)
            .allowsHitTesting(compactP >= 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 7)
        .frame(height: 82)
        .animation(.easeOut(duration: 0.18),
                   value: compactP >= 1)
    }

    @ViewBuilder
    private var searchCapsule: some View {
        if nav.searchOpen {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(T.textSecondary)
                TextField("搜索笔记...", text: Binding(
                    get: { nav.query },
                    set: { nav.query = $0
                           library.search($0) }))
                    .font(.system(size: 15))
                    .frame(width: 140, height: 40)
                if !nav.query.isEmpty {
                    Button {
                        nav.query = ""
                        library.search("")
                        nav.searchOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(T.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .glassCard(radius: 999)
        } else {
            Button {
                nav.searchOpen = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                    Text("搜索")
                        .font(.system(size: 14))
                }
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 18)
                .frame(height: 66)
                .glassControl(radius: 999)
            }
        }
    }

    /// 组内子列（先图后文）：>2 折叠——首卡 meta 带
    /// 「▼ 展开 N 条」、展开后末卡带「▲ 收起」（Web 口径）。
    @ViewBuilder
    private func sublist(group: MemoGroup, kind: String,
                         memos: [MemoItem]) -> some View {
        let key = "\(group.id)-\(kind)"
        let expanded = nav.expandedKeys.contains(key)
        let folded = memos.count > 2 && !expanded
        let shown = folded ? Array(memos.prefix(1)) : memos
        ForEach(shown) { memo in
            memoRow(memo,
                    expandHint: folded && memo.id == shown.first?.id
                        ? (memos.count, {
                            nav.expandedKeys.insert(key)
                        }) : nil,
                    collapseHint: !folded && memos.count > 2
                        && memo.id == shown.last?.id
                        ? { nav.expandedKeys.remove(key) }
                        : nil)
        }
    }

    private var undoToast: some View {
        HStack(spacing: 14) {
            Text("备忘已删除")
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
            Button("撤销") { library.undoDeletion() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassCard(radius: 999)
        .padding(.bottom, 14)
        // 进场（Web 口径）：220ms 弹簧上滑 + 淡入。
        .transition(.move(edge: .bottom)
            .combined(with: .opacity))
    }

    private var newCardRow: some View {
        Button {
            let item = library.create()
            let ed = EditorModel(item: item, library: library)
            ed.wantsInitialFocus = true
            nav.dest = .editor(ed)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("新建笔记")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(T.textSecondary)
                Text("现在  点击记录你的瞬间")
                    .font(.system(size: 12))
                    .foregroundStyle(T.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard()
        }
        .background(GeometryReader { geo in
            Color.clear.preference(
                key: ListScrollKey.self,
                value: geo.frame(in: .named("momentList")).minY)
        })
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16,
                                  bottom: 3, trailing: 16))
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: groupFontSize,
                          weight: .semibold))
            .foregroundStyle(T.textSecondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 24, leading: 20,
                                      bottom: 6, trailing: 16))
    }

    @ViewBuilder
    private func memoRow(
        _ memo: MemoItem,
        expandHint: (Int, () -> Void)? = nil,
        collapseHint: (() -> Void)? = nil
    ) -> some View {
        // 整卡点按走手势而非 Button 包裹：折叠提示钮在
        // meta 行内需要独立命中，Button 嵌套会吞掉它。
        Group {
            if memo.hasImageShape {
                VStack(spacing: 0) {
                    ItemImageView(fileId: memo.coverFileId,
                                  urlString: memo.coverURL,
                                  library: library)
                        .aspectRatio(16 / 9,
                                     contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    VStack(alignment: .leading, spacing: 3) {
                        titleRow(memo, size: 15)
                        metaRow(memo, isImage: true,
                                expandHint: expandHint,
                                collapseHint: collapseHint)
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .glassCard()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    titleRow(memo, size: 16)
                    metaRow(memo, isImage: false,
                            expandHint: expandHint,
                            collapseHint: collapseHint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassCard()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            nav.dest = .editor(EditorModel(
                item: memo, library: library))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16,
                                  bottom: 3, trailing: 16))
        .swipeActions(edge: .trailing,
                      allowsFullSwipe: false) {
            Button(role: .destructive) {
                library.softRemove(memo)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(T.danger)
            Button {
                library.togglePin(memo)
            } label: {
                Label(memo.pinned ? "取消" : "置顶",
                      systemImage: memo.pinned
                        ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    private func titleRow(_ memo: MemoItem,
                          size: CGFloat) -> some View {
        HStack(spacing: 6) {
            if memo.pinned {
                Circle()
                    .fill(T.warning)
                    .frame(width: 6, height: 6)
            }
            Text(memo.title.isEmpty ? "无标题" : memo.title)
                .font(.system(size: size * titleFontScale,
                              weight: .semibold))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            ForEach(memo.tags.prefix(3), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 10))
                    .foregroundStyle(T.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(T.glassControlTint,
                                in: Capsule())
            }
        }
    }

    /// meta 行（Web 口径）：文本卡「{ago}␣␣{摘要}」双空
    /// 格同段截断；图文卡「{ago} · {摘要}」；折叠提示附尾。
    private func metaRow(
        _ memo: MemoItem, isImage: Bool,
        expandHint: (Int, () -> Void)?,
        collapseHint: (() -> Void)?
    ) -> some View {
        HStack(spacing: 6) {
            Text(isImage
                 ? "\(memo.ago) · \(memo.summary(isImage: true))"
                 : "\(memo.ago)  \(memo.summary(isImage: false))")
                .lineLimit(1)
            if let hint = expandHint {
                Button("▼ 展开 \(hint.0) 条") { hint.1() }
                    .font(.system(size: 12))
                    .foregroundStyle(T.accent)
                    .buttonStyle(.plain)
            }
            if let collapse = collapseHint {
                Button("▲ 收起") { collapse() }
                    .font(.system(size: 12))
                    .foregroundStyle(T.accent)
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: metaFontSize))
        .foregroundStyle(T.textSecondary)
    }

    /// 空状态三态（Web EmptyState 口径：44 图标 @55% +
    /// 标题 + 说明 + accent 胶囊动作钮）。
    @ViewBuilder
    private var emptyRow: some View {
        let state: (icon: String, title: String, desc: String,
                    action: String, run: () -> Void) = {
            if library.loadFailed {
                return ("exclamationmark.triangle",
                        "备忘加载失败",
                        "本地数据读取出错，重新加载试试",
                        "重新加载", { library.retryLoad() })
            }
            if library.searchHits != nil {
                return ("magnifyingglass",
                        "未找到「\(nav.query)」",
                        "换个关键词试试，或清除搜索查看全部",
                        "清除搜索", {
                            nav.query = ""
                            library.search("")
                        })
            }
            return ("note.text", "还没有备忘",
                    "暂无笔记，点击上方新建",
                    "新建备忘", {
                        let item = library.create()
                        let ed = EditorModel(
                            item: item, library: library)
                        ed.wantsInitialFocus = true
                        nav.dest = .editor(ed)
                    })
        }()
        VStack(spacing: 8) {
            Image(systemName: state.icon)
                .font(.system(size: 44))
                .foregroundStyle(T.textSecondary.opacity(0.55))
            Text(state.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(T.textMain)
            Text(state.desc)
                .font(.system(size: 13))
                .foregroundStyle(T.textSecondary)
            Button(state.action) { state.run() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(T.accent, in: Capsule())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// ── 子页骨架（Web 口径：左上玻璃返回圆钮 + 居中紧凑标题
// 胶囊 + 内容 126 顶距） ─────────────────────────────
struct CompactTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.3)
            .foregroundStyle(T.textMain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .glassCard(radius: 20)
    }
}

struct ChromeView<Content: View>: View {
    var title: String
    var onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            content()
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            CompactTitle(text: title)
                .padding(.top, 11)
        }
        .background(T.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SectionHeader: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(T.textSecondary)
            .tracking(0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 24)
            .padding(.bottom, 6)
    }
}

struct SetRow: View {
    var title: String
    var meta: String? = nil
    var metaWarn: Bool = false
    var icon: String? = nil
    var chevron: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(T.accent)
                        .frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(T.textMain)
                    if let meta {
                        Text(meta)
                            .font(.system(size: 12))
                            .foregroundStyle(metaWarn
                                ? T.warning : T.textSecondary)
                    }
                }
                Spacer()
                if chevron {
                    Text("›")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            T.textSecondary.opacity(0.45))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}

// ── 设置页（对齐 Web SettingsView） ─────────────────
struct SettingsView: View {
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nav = SettingsNav()
    @AppStorage("lastExportTs") private var lastExportTs: Double = 0
    @AppStorage("lastEditTs") private var lastEditTs: Double = 0

    final class SettingsNav: ObservableObject {
        @Published var route: Sub?
    }

    enum Sub: Identifiable {
        case backup, gestures, language, diag
        var id: String {
            switch self {
            case .backup: return "backup"
            case .gestures: return "gestures"
            case .language: return "language"
            case .diag: return "diag"
            }
        }
    }

    /// 新鲜度（Web 口径）：上次备份 {when}；≥2 天追加
    /// 「· {n} 天前」；超 7 天且期间有编辑 → 警示。
    private var backupStale: Bool {
        guard lastExportTs > 0 else { return false }
        let age = Date().timeIntervalSince1970 - lastExportTs
        return age > 7 * 86400 && lastEditTs > lastExportTs
    }

    private var freshness: String {
        if lastExportTs <= 0 { return "尚未备份" }
        var s = "上次备份 " + Fmt.backupWhen(lastExportTs)
        let days = Int((Date().timeIntervalSince1970
            - lastExportTs) / 86400)
        if days >= 2 { s += " · \(days) 天前" }
        if backupStale {
            s += " · 已超 7 天且有新编辑，建议重新备份"
        }
        return s
    }

    var body: some View {
        ChromeView(title: "设置", onBack: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(text: "外观")
                    // 文字大小跟随系统（Dynamic Type）：Web
                    // 的分级是接不到系统设置时的替代，原生
                    // 有系统 API 走更优路，不再自设分级。
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("文字大小")
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text("在系统「显示与亮度 · 文字大小」中调整")
                                .font(.system(size: 12))
                                .foregroundStyle(T.textSecondary)
                        }
                        Spacer()
                        Text("跟随系统")
                            .font(.system(size: 13))
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: 32)

                    SectionHeader(text: "数据")
                    VStack(spacing: 0) {
                        SetRow(title: "备份与恢复",
                               meta: freshness,
                               metaWarn: backupStale) {
                            nav.route = .backup
                        }
                        rowDivider
                        SetRow(title: "语言",
                               meta: "简体中文") {
                            nav.route = .language
                        }
                        rowDivider
                        SetRow(title: "手势速览",
                               meta: "左滑 · 长按 · 斜杠 · 双栏") {
                            nav.route = .gestures
                        }
                        rowDivider
                        SetRow(title: "诊断日志") {
                            nav.route = .diag
                        }
                    }
                    .glassCard(radius: 28)

                    SectionHeader(text: "关于")
                    VStack(spacing: 0) {
                        HStack {
                            Text("版本")
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Spacer()
                            Text("0.8.1")
                                .foregroundStyle(T.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        rowDivider
                        HStack {
                            Text("联系我们")
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Spacer()
                            Text("overcanopies@gmail.com")
                                .font(.system(size: 13))
                                .foregroundStyle(T.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .glassCard(radius: 28)

                    Text("此刻，值得被记住。")
                        .font(.system(size: 12).italic())
                        .foregroundStyle(
                            T.textSecondary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 126)
                .padding(.bottom, 32)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { nav.route != nil },
            set: { if !$0 { nav.route = nil } })) {
            switch nav.route {
            case .backup:
                BackupView(library: library)
            case .gestures:
                GesturesView()
            case .language:
                LanguageView()
            case .diag:
                DiagView(library: library)
            case nil:
                EmptyView()
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(T.glassBorder.opacity(0.5))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}

// ── 备份页（Web 口径：导出先确认、导入先选文件校验
// 后确认、页内 toast、最近操作结构化、新鲜度横幅） ──
struct BackupView: View {
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = BackupUI()
    @AppStorage("lastExportTs") private var lastExportTs: Double = 0
    @AppStorage("lastEditTs") private var lastEditTs: Double = 0

    final class BackupUI: ObservableObject {
        @Published var confirmExport = false
        @Published var showImporter = false
        @Published var confirmImport = false
        @Published var stagedStats: (Int, Int)?
        @Published var shareURL: URL?
        @Published var toast: Toast?
        struct Toast: Identifiable {
            let id = UUID()
            var text: String
            var isError: Bool
        }
    }

    private var stale: Bool {
        guard lastExportTs > 0 else { return false }
        let age = Date().timeIntervalSince1970 - lastExportTs
        return age > 7 * 86400 && lastEditTs > lastExportTs
    }

    private var ops: [Library.BackupOp] {
        Library.loadOps()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ChromeView(title: "备份与恢复",
                       onBack: { dismiss() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备份状态总览")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(T.textMain)
                            Text("上次备份 "
                                 + Fmt.backupWhen(lastExportTs)
                                 + " · \(library.memos.count) 条笔记"
                                 + " · \(library.referencedAttachmentCount()) 个附件")
                                .font(.system(size: 13))
                                .foregroundStyle(T.textSecondary)
                            if stale {
                                Text("距上次成功备份已超过 7 天，"
                                     + "期间备忘有过编辑，建议导出一份新备份。")
                                    .font(.system(size: 13))
                                    .foregroundStyle(T.warning)
                            }
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .padding(16)
                        .glassCard(radius: 28)

                        SectionHeader(text: "本地备份")
                        VStack(spacing: 0) {
                            SetRow(title: "导出备份",
                                   meta: "分享 zip 到系统文件 App",
                                   icon: "square.and.arrow.up") {
                                ui.confirmExport = true
                            }
                            Rectangle()
                                .fill(T.glassBorder.opacity(0.5))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                            SetRow(title: "导入备份",
                                   meta: "从文件 App 选择 zip 恢复",
                                   icon: "square.and.arrow.down") {
                                ui.showImporter = true
                            }
                        }
                        .glassCard(radius: 28)

                        Text("导出时在分享面板中选择『存储到文件』，"
                             + "即可把备份存入 iCloud Drive；"
                             + "导入时也可从 iCloud Drive 选择备份文件恢复。")
                            .font(.system(size: 13))
                            .foregroundStyle(T.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 16)

                        if !ops.isEmpty {
                            SectionHeader(text: "最近操作")
                            VStack(spacing: 0) {
                                ForEach(Array(ops.prefix(6)
                                    .enumerated()), id: \.offset) {
                                    idx, op in
                                    opRow(op)
                                    if idx < min(ops.count, 6) - 1 {
                                        Rectangle()
                                            .fill(T.glassBorder
                                                .opacity(0.5))
                                            .frame(height: 0.5)
                                            .padding(
                                                .horizontal, 16)
                                    }
                                }
                            }
                            .glassCard(radius: 28)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 126)
                    .padding(.bottom, 32)
                }
            }
            if let toast = ui.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.isError
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError
                            ? T.danger : T.accent)
                    Text(toast.text)
                        .font(.system(size: 13))
                        .foregroundStyle(T.textMain)
                        .lineLimit(3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(radius: 999)
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom)
                    .combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28,
                           dampingFraction: 0.86),
                   value: ui.toast?.id.uuidString ?? "")
        .task(id: ui.toast?.id) {
            guard ui.toast != nil else { return }
            let secs = (ui.toast?.isError ?? false) ? 6.0 : 3.0
            try? await Task.sleep(
                for: .seconds(secs))
            ui.toast = nil
        }
        .alert("确认导出备份", isPresented: Binding(
            get: { ui.confirmExport },
            set: { ui.confirmExport = $0 })) {
            Button("确认导出") {
                if let url = library.exportZip() {
                    ui.shareURL = url
                    showToast("备份已导出", isError: false)
                } else {
                    showToast("导出失败，请重试", isError: true)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将当前全部备忘与附件导出为一个 ZIP 备份文件。")
        }
        .alert("确认恢复备份", isPresented: Binding(
            get: { ui.confirmImport },
            set: { ui.confirmImport = $0 })) {
            Button("确认恢复") {
                if let stats = library.commitStagedImport() {
                    showToast(
                        "已导入：\(stats.0) 条备忘"
                        + " · \(stats.1) 个附件（已存本机）",
                        isError: false)
                } else {
                    showToast("导入失败，请重试", isError: true)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("导入将覆盖当前全部数据，此操作不可撤销。")
        }
        .fileImporter(isPresented: Binding(
            get: { ui.showImporter },
            set: { ui.showImporter = $0 }),
            allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                library.pickedImportName =
                    url.lastPathComponent
                if let stats = library.stageImport(from: url) {
                    ui.stagedStats = stats
                    ui.confirmImport = true
                } else {
                    library.recordOp(kind: "import", ok: false,
                                     detail: "")
                    showToast(
                        "导入失败：所选文件不是有效的备份 zip"
                        + "（现有数据未动）",
                        isError: true)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
    }

    private func showToast(_ text: String, isError: Bool) {
        ui.toast = BackupUI.Toast(text: text, isError: isError)
    }

    private func opRow(_ op: Library.BackupOp) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(op.ok ? Color.green : T.danger)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(op.ok
                     ? (op.kind == "export" ? "导出成功" : "导入成功")
                     : (op.kind == "export" ? "导出失败" : "导入失败"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                if !op.detail.isEmpty {
                    Text(op.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(T.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(op.kind == "export" ? "导出" : "恢复")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(T.glassControlTint, in: Capsule())
            Text(Fmt.fullStamp(op.ts))
                .font(.system(size: 11))
                .foregroundStyle(T.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// ── 手势速览页（文案同 Web 语言包） ─────────────────
struct GesturesView: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(String, String, String)] = [
        ("hand.draw", "左滑列表行",
         "在备忘列表左滑一行，可置顶或删除；删除后 8 秒内可撤销"),
        ("hand.tap", "长按拖拽",
         "编辑页长按一块约半秒拾起，拖到目标位置放下排序；正在编辑的块长按是选择文字"),
        ("text.cursor", "斜杠命令",
         "在空段落输入 / ，插入标题、待办、图片、卡片等块"),
        ("rectangle.split.2x1", "双栏编辑",
         "宽屏下在编辑菜单开启双栏，左右两栏可各自混排、独立滚动"),
        ("magnifyingglass", "快速搜索",
         "点列表顶部的搜索胶囊，按标题与正文查找备忘"),
    ]

    var body: some View {
        ChromeView(title: "手势速览", onBack: { dismiss() }) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()),
                            id: \.offset) { idx, row in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: row.0)
                                .font(.system(size: 19))
                                .foregroundStyle(T.accent)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading,
                                   spacing: 3) {
                                Text(row.1)
                                    .font(.system(
                                        size: 15, weight: .semibold))
                                    .foregroundStyle(T.textMain)
                                Text(row.2)
                                    .font(.system(size: 13))
                                    .foregroundStyle(T.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        if idx < rows.count - 1 {
                            Rectangle()
                                .fill(T.glassBorder.opacity(0.5))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .glassCard(radius: 28)
                .padding(.horizontal, 16)
                .padding(.top, 126)
            }
        }
    }
}

// ── 语言页（Web 口径：五语全集 = 本名 + 英文名副文案
// + 状态标签；切换行为待原生 i18n 落地后接通） ──────
struct LanguageView: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(name: String, en: String,
                         tag: String, current: Bool)] = [
        ("简体中文", "Simplified Chinese", "使用中", true),
        ("繁體中文", "Traditional Chinese", "内置", false),
        ("English", "English", "内置", false),
        ("日本語", "Japanese", "内置", false),
        ("한국어", "Korean", "内置", false),
    ]

    var body: some View {
        ChromeView(title: "语言", onBack: { dismiss() }) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()),
                            id: \.offset) { idx, row in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading,
                                   spacing: 2) {
                                Text(row.name)
                                    .font(.system(
                                        size: 16,
                                        weight: .semibold))
                                    .foregroundStyle(T.textMain)
                                Text(row.en)
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        T.textSecondary)
                            }
                            Spacer()
                            Text(row.tag)
                                .font(.system(
                                    size: 11, weight: .semibold))
                                .foregroundStyle(row.current
                                    ? T.accent : T.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(row.current
                                    ? T.accent.opacity(0.10)
                                    : T.glassControlTint,
                                    in: Capsule())
                            if row.current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(T.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        if idx < rows.count - 1 {
                            Rectangle()
                                .fill(T.glassBorder.opacity(0.5))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .glassCard(radius: 28)
                .padding(.horizontal, 16)
                .padding(.top, 126)
            }
        }
    }
}

// ── 图片页（对齐 Web：页头返回+文件名标题，图 contain
// 适配可用区、大图只缩、小图不放大、区内居中） ──────
struct ImagePageView: View {
    var fileId: String?
    var urlString: String?
    var name: String
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = ImageLoader()

    /// 标题（Web 口径）：按 fileId 查附件清单真实文件名，
    /// 无名回退「图片」。
    private var displayName: String {
        if name != "图片" { return name }
        return library.attachmentName(for: fileId) ?? name
    }

    var body: some View {
        ChromeView(title: displayName, onBack: { dismiss() }) {
            GeometryReader { geo in
                Group {
                    if let img = loader.image {
                        if img.size.width <= geo.size.width
                            && img.size.height <= geo.size.height {
                            Image(uiImage: img)
                                .frame(maxWidth: .infinity,
                                       maxHeight: .infinity)
                        } else {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity,
                                       maxHeight: .infinity)
                        }
                    } else if loader.failed {
                        Text("图片加载失败")
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    }
                }
                .padding(.top, 66)
            }
        }
        .onAppear {
            loader.load(fileId: fileId, urlString: urlString,
                        library: library)
        }
    }
}

@main
struct MomentApp: App {
    @StateObject private var library = Library()

    var body: some Scene {
        WindowGroup { ListView(library: library) }
    }
}
