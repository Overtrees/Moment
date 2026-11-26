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
import CoreLocation

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
    /// 块顶在 editorScroll 坐标中的位置（斜杠面板锚定
    /// 用；非 Published——滚动每帧变化不触发重演算，
    /// 面板打开时读当前值）。
    var frameMinY: CGFloat = 0
    @Published var nodeVersion = 0
    /// 图文块「编辑」信号（长按菜单 → ImgTextBlockView 开
    /// 全文编辑面板）。
    @Published var imgTextEditSignal = 0
    /// MD 预览缓存（按源码文本键，文本变即失效）：分类
    /// 标识与解析树（core 同一解析器产物）。
    var mdCacheText: String?
    var mdCacheKind = "none"
    var mdCacheBlocks: [Any] = []
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

    // ── 启动守卫（批 B，对 Web 存活标记口径）──
    // load 开始置进行中标记并逐步落面包屑（UserDefaults
    // 同步落盘），成功收尾清除；下次启动若标记仍在 =
    // 上次在加载完成前死亡（崩溃/强杀），记 LAUNCH
    // error 并累计连续次数，≥3 次出 notice 建议导出
    // 诊断/备份。打开库失败属已留痕的已知失败，清标
    // 记不计入连续次数。
    private static let kLaunchBusy = "launchInProgress"
    private static let kLaunchStep = "launchStep"
    private static let kLaunchStreak = "launchCrashStreak"

    private func launchMark(_ step: String) {
        let d = UserDefaults.standard
        d.set(true, forKey: Self.kLaunchBusy)
        d.set(step, forKey: Self.kLaunchStep)
    }

    private func launchDone() {
        let d = UserDefaults.standard
        d.set(false, forKey: Self.kLaunchBusy)
        d.set(0, forKey: Self.kLaunchStreak)
    }

    private func launchFailed() {
        UserDefaults.standard.set(
            false, forKey: Self.kLaunchBusy)
    }

    private func inspectPreviousLaunch() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.kLaunchBusy) else { return }
        let prevStep = d.string(forKey: Self.kLaunchStep)
            ?? "?"
        let streak = d.integer(
            forKey: Self.kLaunchStreak) + 1
        d.set(streak, forKey: Self.kLaunchStreak)
        DiagLog.shared.log(.error,
            "LAUNCH 上次启动未完成（停在步骤："
            + "\(prevStep)），连续第 \(streak) 次")
        if streak >= 3 {
            notice = "应用连续 \(streak) 次启动未完成，"
                + "建议到设置页导出诊断，并导出一份备份。"
        }
    }

    func load() {
        // 面包屑分步：先让首帧把当前步显示出来，再走 FFI；
        // 若某步硬崩，列表头会停在该步文案上（或下次启动
        // 能看到），不至于黑箱。开库延迟一拍同理。
        inspectPreviousLaunch()
        launchMark("开库")
        timing = "启动中 · 开库…"
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.05) {
            do {
                let lib = try MomentLibrary.open(
                    path: self.storeDir + "/moment.db")
                self.lib = lib
                self.launchMark("读数据")
                DispatchQueue.main.async {
                    self.timing = "启动中 · 已开库，读数据…"
                }
                if try lib.memoCount() == 0 {
                    self.launchMark("写种子")
                    for m in Self.seedMemos {
                        try lib.upsertMemoJson(json: m)
                    }
                    self.launchMark("读数据")
                }
                try self.reload(lib: lib)
                self.launchDone()
                let ready = Clock.ms()
                DispatchQueue.main.async {
                    self.timing = "冷启 首帧 "
                        + "\(self.firstFrameMs ?? -1)ms · 数据 "
                        + "\(ready)ms · \(self.memos.count) 篇"
                    // 真机冒烟证据行：冷启全程走完才记，
                    // 带版本号——导出日志一看便知该版在
                    // 真机冷启成功、数据篇数与耗时。
                    let ver = Bundle.main.infoDictionary?[
                        "CFBundleShortVersionString"]
                        as? String ?? "?"
                    DiagLog.shared.log(.info,
                        "SMOKE 冷启完成 v=\(ver) memos="
                        + "\(self.memos.count)"
                        + " 首帧\(self.firstFrameMs ?? -1)ms"
                        + " 数据\(ready)ms")
                }
            } catch {
                self.launchFailed()
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
        let (items, quarantined) = Self.parse(json)
        if quarantined > 0 {
            DiagLog.shared.log(.warn,
                "加载隔离：\(quarantined) 篇数据损坏已隔离"
                + "（原文保存在库内隔离区，导出备份随包附出）")
            DispatchQueue.main.async {
                self.notice = "有 \(quarantined) 篇备忘数据损坏，"
                    + "已隔离保护、其余内容正常。导出备份时"
                    + "会一并带出隔离原文。"
            }
        }
        DispatchQueue.main.async {
            self.memos = items
            self.loadFailed = false
        }
    }

    func retryLoad() {
        // 按结局置位：失败如实回到失败态并记行，不再
        // 先清标志再 try? 吞错跌落假空态。
        if lib == nil { load(); return }
        guard let lib else { return }
        do {
            try reload(lib: lib)
        } catch {
            loadFailed = true
            DiagLog.shared.log(.error,
                "重试加载失败: \(error)")
        }
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
            // 结果侧记行（批 C）：删成功才记已删除，
            // 失败记 error——不再 try? 后无条件记成功；
            // lib 为 nil 显式判失败（可选链不抛错会假
            // 成功，同 exportZip 的教训）。
            if let lib {
                do {
                    try lib.removeMemo(id: item.id)
                    DiagLog.shared.log(.info,
                        "备忘已删除（撤销窗口结束）"
                        + "id=\(item.id)")
                } catch {
                    DiagLog.shared.log(.error,
                        "删除失败 id=\(item.id): \(error)")
                }
            } else {
                DiagLog.shared.log(.error,
                    "删除失败（库未打开）id=\(item.id)")
            }
        }
        pendingDeletion = nil
    }

    /// 双形兼容：现行包装形 {"memos":[...],
    /// "quarantined":n} 与旧数组形（隔离数恒 0）。
    static func parse(_ json: String)
        -> (items: [MemoItem], quarantined: Int) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                with: data) else { return ([], 0) }
        let arr: [[String: Any]]
        var quarantined = 0
        if let wrap = obj as? [String: Any],
           let m = wrap["memos"] as? [[String: Any]] {
            arr = m
            quarantined = wrap["quarantined"] as? Int ?? 0
        } else if let a = obj as? [[String: Any]] {
            arr = a
        } else {
            return ([], 0)
        }
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
        return (items, quarantined)
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
        // 结果回路（批 A）：三段失败各自记 error 并经
        // notice 告知——不再 guard 静默 return、try? 吞
        // 错后照常更新内存列表装作已保存。写入成功后
        // 才同步内存列表（列表 = 库的镜像）。
        guard let data = try? JSONSerialization.data(
                withJSONObject: memo),
              let s = String(data: data, encoding: .utf8)
        else {
            DiagLog.shared.log(.error,
                "保存失败（序列化）id=\(it.id)")
            notice = "保存失败：这篇备忘暂时无法写入，"
                + "内容只保留在当前页面。请导出备份后"
                + "重启应用。"
            return
        }
        guard let lib else {
            DiagLog.shared.log(.error,
                "保存失败（库未打开）id=\(it.id)")
            notice = "保存失败：数据库未打开，编辑只保留"
                + "在当前页面。请重启应用。"
            return
        }
        do {
            try lib.upsertMemoJson(json: s)
        } catch {
            DiagLog.shared.log(.error,
                "保存失败（写入）id=\(it.id): \(error)")
            notice = "保存失败：写入数据库出错，编辑只"
                + "保留在当前页面。请导出备份后重启应用。"
            return
        }
        if !notice.isEmpty { notice = "" }
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
        // 结果侧（批 C）：库删成功才同步内存列表，
        // 失败记 error 并保留列表项（不造已删假象）；
        // lib 为 nil 显式判失败（可选链假成功同型）。
        guard let lib else {
            DiagLog.shared.log(.error,
                "删除失败（库未打开）id=\(item.id)")
            return
        }
        do {
            try lib.removeMemo(id: item.id)
            memos.removeAll { $0.id == item.id }
            DiagLog.shared.log(.info,
                "备忘已删除 id=\(item.id)")
        } catch {
            DiagLog.shared.log(.error,
                "删除失败 id=\(item.id): \(error)")
        }
    }

    func togglePin(_ item: MemoItem) {
        var it = item
        it.pinned.toggle()
        persist(it)
    }

    func attachmentData(_ id: String) -> Data {
        (try? lib?.attachmentData(id: id)) ?? Data()
    }

    /// 附件写入结果回路（批 A）：失败记 error 并回
    /// false 供调用点留痕——不再 try? 静默吞掉（块引
    /// 用着不存在的 fileId、附件永久缺失的源头）。
    @discardableResult
    func putAttachment(_ id: String, _ data: Data) -> Bool {
        guard let lib else {
            DiagLog.shared.log(.error,
                "附件写入失败（库未打开）id=\(id)")
            return false
        }
        do {
            try lib.putAttachment(id: id, data: data)
            return true
        } catch {
            DiagLog.shared.log(.error,
                "附件写入失败 id=\(id): \(error)")
            return false
        }
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
        // lib == nil 守卫（批 A）：旧路 try lib?. 可选
        // 链不抛错、直落成功分支记 ok 并返回不存在的
        // 文件 URL——开库失败时救援导出恰不可用。
        guard let lib else {
            recordOp(kind: "export", ok: false, detail: "")
            DiagLog.shared.log(.error, "导出失败: 库未打开")
            return nil
        }
        do {
            try lib.exportBackup(zipPath: path)
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

    // ── 反向链接（Web wiki 口径）：他篇正文（跳过代码
    // 块子树、剥反引号段）出现 [[标题]] 即引用本篇；键 =
    // 标题去 # 后缀、去空白、小写；标题空/「无标题」无链。
    static func wikiKey(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "无标题" { return "" }
        return (t.split(separator: "#").first
            .map(String.init) ?? t)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    static func wikiTargets(
        inDoc doc: [[String: Any]]) -> Set<String> {
        var texts: [String] = []
        func walk(_ node: [String: Any]) {
            let ty = (node["type"] as? String ?? "")
                .lowercased()
            if ["codeblock", "fencedcode", "inlinecode"]
                .contains(ty) { return }
            if let t = node["text"] as? String {
                texts.append(t)
            }
            if let kids = node["children"]
                as? [[String: Any]] {
                kids.forEach(walk)
            }
            if let items = (node["attrs"]
                as? [String: Any])?["items"]
                as? [[String: Any]] {
                items.forEach(walk)
            }
        }
        doc.forEach(walk)
        let joined = texts.joined(separator: "\n")
            .split(separator: "`", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.offset % 2 == 0 }
            .map { String($0.element) }
            .joined()
        var out = Set<String>()
        let chars = Array(joined)
        var i = 0
        while i + 1 < chars.count {
            if chars[i] == "[" && chars[i + 1] == "[" {
                var j = i + 2
                var inner = ""
                var closed = false
                while j + 1 < chars.count {
                    if chars[j] == "]" && chars[j + 1] == "]" {
                        closed = true
                        break
                    }
                    inner.append(chars[j])
                    j += 1
                    if inner.count > 200 { break }
                }
                if closed {
                    let key = (inner.split(separator: "#")
                        .first.map(String.init) ?? inner)
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    if !key.isEmpty { out.insert(key) }
                    i = j + 2
                    continue
                }
            }
            i += 1
        }
        return out
    }

    func backlinks(forTitle title: String,
                   excludeId: String) -> [MemoItem] {
        let key = Self.wikiKey(title)
        guard !key.isEmpty else { return [] }
        return memos.filter { m in
            m.id != excludeId
                && Self.wikiTargets(
                    inDoc: m.raw["doc"]
                        as? [[String: Any]] ?? [])
                    .contains(key)
        }
    }

    // ── 备忘头像（avatars 通道，值 = data URL 字符串，
    // 与 Web/ZIP 互通；空串缓存表示无头像） ──
    @Published var avatarCache: [String: String] = [:]

    func avatarDataURL(for id: String) -> String? {
        guard let v = avatarCache[id], !v.isEmpty else {
            return nil
        }
        return v
    }

    func loadAvatar(for id: String) {
        if avatarCache[id] != nil { return }
        let data = (try? lib?.avatarData(memoId: id))
            ?? Data()
        avatarCache[id] = String(data: data,
                                 encoding: .utf8) ?? ""
    }

    func setAvatar(for id: String, dataURL: String?) {
        let bytes = dataURL.map { Data($0.utf8) } ?? Data()
        // 结果侧（批 C）：写入成功才更新缓存/发通知/
        // 记成功行，失败记 error——不再 try? 后无条件
        // 记成功（意图冒充结果）。
        guard let lib else {
            DiagLog.shared.log(.error,
                "头像写入失败（库未打开）\(id)")
            return
        }
        do {
            try lib.setAvatar(memoId: id, data: bytes)
            avatarCache[id] = dataURL ?? ""
            NotificationCenter.default.post(
                name: .momentAvatarChanged, object: id)
            DiagLog.shared.log(.info, dataURL == nil
                ? "头像恢复默认 \(id)" : "头像已设置 \(id)")
        } catch {
            DiagLog.shared.log(.error,
                "头像写入失败 \(id): \(error)")
        }
    }

    func search(_ q: String) {
        let query = q.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { searchHits = nil; return }
        guard let lib else {
            searchHits = []
            DiagLog.shared.log(.error,
                "搜索失败（库未打开）")
            return
        }
        do {
            let json = try lib.searchIdsJson(query: query)
            let data = json.data(using: .utf8)
            var hits = Set((try? JSONSerialization.jsonObject(
                with: data ?? Data())) as? [String] ?? [])
            // 补充扫描（Web matches_search 口径）：FTS 只覆
            // 盖标题+正文 text，卡片 meta 白名单字段、attrs
            // 与条目的 url 不在其中——对已加载备忘的 raw 按
            // 同口径提取拼装文本做整串子串匹配，并入结果。
            // 注：附件文件名与卡片顶层 url Web 亦不匹配，
            // 不扩入（等价而非超过）。
            let needle = query.lowercased()
            for m in memos where !hits.contains(m.id) {
                if Self.searchHaystack(of: m).contains(needle) {
                    hits.insert(m.id)
                }
            }
            searchHits = memos.map(\.id).filter {
                hits.contains($0)
            }
            // 结果侧（批 C）：0 命中记一行（排障关键
            // 信号）；有命中不记，避免逐键刷屏。
            if searchHits?.isEmpty == true {
                DiagLog.shared.log(.info,
                    "搜索无结果 qlen=\(query.count)")
            }
        } catch {
            // FFI 失败不再静默吞成空结果（批 C）。
            searchHits = []
            DiagLog.shared.log(.error,
                "搜索失败: \(error)")
        }
    }

    /// Web walk_node/walk_value 口径的拼装文本：标题 +
    /// 节点 text（递归）+ attrs.text + attrs.url（非
    /// data:）+ attrs.items[].url/text + meta 白名单键。
    static func searchHaystack(of memo: MemoItem) -> String {
        var parts: [String] = [memo.title]
        func walkNode(_ n: [String: Any]) {
            if let t = n["text"] as? String { parts.append(t) }
            if let kids = n["children"] as? [[String: Any]] {
                kids.forEach(walkNode)
            }
            if let attrs = n["attrs"] as? [String: Any] {
                if let t = attrs["text"] as? String {
                    parts.append(t)
                }
                if let u = attrs["url"] as? String,
                   !u.hasPrefix("data:") {
                    parts.append(u)
                }
                if let items = attrs["items"]
                    as? [[String: Any]] {
                    for it in items {
                        if let u = it["url"] as? String,
                           !u.hasPrefix("data:") {
                            parts.append(u)
                        }
                        walkNode(it)
                    }
                }
            }
            if let meta = n["meta"] as? [String: Any] {
                for key in ["text", "title", "subtitle",
                            "source", "name", "label", "alt",
                            "description", "content", "url"] {
                    if let s = meta[key] as? String {
                        parts.append(s)
                    }
                }
            }
        }
        (memo.raw["doc"] as? [[String: Any]] ?? [])
            .forEach(walkNode)
        return parts.joined(separator: "\n").lowercased()
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
        applyHighlightTint(out)
        return out
    }

    /// 高亮口径（Web 定案）：==…== 是字面文本（编辑态保
    /// 留字面、渲染侧切 <mark>）；编辑面只给字面段加底色
    /// 反馈（--fill-highlight rgba(255,204,0,.25)），不改
    /// 字体——避免回读把高亮误判成加粗。不入 runs 模型。
    static func applyHighlightTint(
        _ out: NSMutableAttributedString) {
        let s = out.string
        guard s.contains("==") else { return }
        let bg = UIColor(red: 1.0, green: 0.8, blue: 0,
                         alpha: 0.25)
        var searchStart = s.startIndex
        while let open = s.range(
            of: "==", range: searchStart..<s.endIndex) {
            let afterOpen = open.upperBound
            guard let close = s.range(
                of: "==", range: afterOpen..<s.endIndex),
                close.lowerBound > afterOpen else {
                searchStart = afterOpen
                continue
            }
            let ns = NSRange(open.lowerBound..<close.upperBound,
                             in: s)
            out.addAttribute(.backgroundColor, value: bg,
                             range: ns)
            searchStart = close.upperBound
        }
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
/// 编辑器文本视图：粘贴先过分流（成卡判定），消费则
/// 不走原生粘贴（Web paste 口径）。
final class EditorTextView: UITextView {
    var onPasteText: ((String) -> Bool)?
    var onPasteImage: ((Data) -> Bool)?
    /// 硬件键盘 Shift 按压态（Shift+Enter 软换行判定；
    /// UITextViewDelegate 不带修饰键，只能在按键事件
    /// 层跟踪）。
    private(set) var shiftHeld = false

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        if let onPasteImage, let img = pb.image,
           let data = img.pngData()
               ?? img.jpegData(compressionQuality: 0.9),
           onPasteImage(data) {
            return
        }
        if let s = pb.string,
           let onPasteText, onPasteText(s) {
            return
        }
        super.paste(sender)
    }

    override func pressesBegan(_ presses: Set<UIPress>,
                               with event: UIPressesEvent?) {
        if event?.modifierFlags.contains(.shift) == true {
            shiftHeld = true
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>,
                               with event: UIPressesEvent?) {
        shiftHeld = event?.modifierFlags
            .contains(.shift) ?? false
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        shiftHeld = false
        super.pressesCancelled(presses, with: event)
    }
}

struct BlockTextView: UIViewRepresentable {
    @ObservedObject var block: BlockState
    var editor: EditorModel?
    /// 非空时本视图编辑的是该列表块的一个 list-item。
    var listParent: BlockState? = nil
    var onChange: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = EditorTextView()
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
        // 键盘收起的确定性出口：UITextView 是第一响应
        // 者时 SwiftUI 的 .keyboard toolbar 不生效（它
        // 只服务 SwiftUI 文本控件）——改挂 UIKit 的
        // inputAccessoryView「完成」钮，点击即辞焦。
        let bar = UIToolbar()
        bar.sizeToFit()
        let done = UIBarButtonItem(
            title: "完成", style: .done,
            target: tv, action: #selector(
                UIResponder.resignFirstResponder))
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                            target: nil, action: nil),
            done,
        ]
        tv.inputAccessoryView = bar
        // 粘贴分流（Web 口径）：裸 URL/内嵌媒体 URL 成卡。
        let coord = context.coordinator
        tv.onPasteText = { [weak tv] text in
            guard let tv else { return false }
            return coord.handlePaste(text: text, tv: tv)
        }
        tv.onPasteImage = { [weak tv] data in
            guard tv != nil else { return false }
            return coord.handlePasteImage(data: data)
        }
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
        // TextKit 2 惰性布局：长文本 sizeThatFits 只统
        // 计已布局片段、回报偏小高度——内容总高被算小
        // 后 ScrollView 判定无可滚、超帧文本被裁（三
        // 线审计布局线定案）。量测前强制全量布局；
        // 同一文本+宽度只做一次（签名缓存），滚动期
        // 的重复量测不再反复全量布局。
        if let lm = tv.textLayoutManager {
            let sig = "\(Int(w))|"
                + "\(tv.textStorage.string.hashValue)"
            if context.coordinator.laidOutSig != sig {
                context.coordinator.laidOutSig = sig
                lm.ensureLayout(for: lm.documentRange)
            }
        }
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
        // 已聚焦块的光标落点请求（斜杠行内命令/转块后
        // 落 token 起点）：视图已持焦点时直接落选区。
        if let ed = editor, ed.focusBlockId == block.id,
           let off = ed.pendingCaretOffset,
           tv.isFirstResponder {
            tv.selectedRange = NSRange(
                location: min(off, tv.text.count),
                length: 0)
            DispatchQueue.main.async {
                ed.pendingCaretOffset = nil
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
        /// 已做全量布局的文本签名（内容+宽度）：未变
        /// 则跳过 ensureLayout，防滚动期反复全量布局。
        var laidOutSig = ""
        init(_ p: BlockTextView) { parent = p }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.editor?.editingBlockId = parent.block.id
            // 文本编辑会话开始压一帧历史（撤销回到会话始）。
            parent.editor?.pushHistory()
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.editor?.editingBlockId == parent.block.id {
                parent.editor?.editingBlockId = nil
                // 失焦转预览时点补尾随空段（Web 口径）。
                parent.editor?.materializeMdTrails()
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
                if text == "\n",
                   (tv as? EditorTextView)?.shiftHeld
                       == true {
                    // Shift+Enter 软换行（Web 口径）：块内
                    // 换行不拆块，放行原生插入。
                    return true
                }
                // 回车拆块 / 粘贴多行拆块（E17）：统一走
                // insertLines（列表项在列表内续项）。
                let lines = text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n")
                if text == "\n" && parent.listParent == nil
                    && (parent.block.type == "heading"
                        || parent.block.type == "callout") {
                    // 标题/Callout 回车不拆文本（Web 口径）：
                    // 整段保留、其后插空段落。
                    ed.headingEnter(parent.block)
                } else if text == "\n"
                    && parent.listParent == nil {
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

        /// 粘贴图片成块（E17）：当前块后插图片块（仅顶层）。
        func handlePasteImage(data: Data) -> Bool {
            guard parent.listParent == nil,
                  let editor = parent.editor else {
                return false
            }
            editor.insertPastedImage(block: parent.block,
                                     data: data)
            return true
        }

        /// 粘贴分流入口：按当前选区切 before/after 交给
        /// EditorModel 判成卡（仅顶层文本块）。
        func handlePaste(text: String, tv: UITextView)
            -> Bool {
            guard parent.listParent == nil,
                  let editor = parent.editor else {
                return false
            }
            let base = Marks.baseFont(for: parent.block)
            let suppress = parent.block.type == "todo"
                && parent.block.checked
            let full = tv.attributedText
                ?? NSAttributedString()
            let sel = tv.selectedRange
            let beforeAttr = full.attributedSubstring(
                from: NSRange(location: 0,
                              length: sel.location))
            let afterStart = sel.location + sel.length
            let afterAttr = full.attributedSubstring(
                from: NSRange(location: afterStart,
                              length: full.length - afterStart))
            return editor.handlePaste(
                block: parent.block, text: text,
                beforeRuns: Marks.runs(
                    from: beforeAttr, base: base,
                    suppressStrikethrough: suppress),
                afterRuns: Marks.runs(
                    from: afterAttr, base: base,
                    suppressStrikethrough: suppress))
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.block.runs = Marks.runs(
                from: tv.attributedText,
                base: Marks.baseFont(for: parent.block),
                suppressStrikethrough: parent.block.type
                    == "todo" && parent.block.checked)
            parent.block.text = tv.text
            parent.onChange()
            // 斜杠面板触发/过滤跟随文本与选区（块内任意
            // 位置 token，含列表项；判定在 EditorModel）。
            parent.editor?.updateSlash(
                for: parent.block, selUTF16: tv.selectedRange)
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
                    // 加载失败结果侧记行（批 C）：附件
                    // 缺失/坏图不再只有空白占位无痕。
                    if img == nil {
                        DiagLog.shared.log(.error,
                            "图片加载失败 fid=\(fid) "
                            + "bytes=\(data.count)")
                    }
                }
            }
        } else if let s = urlString, let url = URL(string: s) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap { UIImage(data: $0) }
                DispatchQueue.main.async {
                    self.image = img
                    self.failed = img == nil
                    if img == nil {
                        DiagLog.shared.log(.error,
                            "图片加载失败 url="
                            + "\(url.host ?? "?")")
                    }
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

/// 多选选图（图库编辑态追加用）：回调按选择序逐张
/// 给数据，全部到齐后一次性回主线程。
struct MultiPhotoPicker: UIViewControllerRepresentable {
    var onPick: ([Data]) -> Void

    func makeUIViewController(
        context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(
        _ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject,
        PHPickerViewControllerDelegate {
        var parent: MultiPhotoPicker
        init(_ p: MultiPhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            var datas: [Data?] =
                Array(repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (i, r) in results.enumerated() {
                group.enter()
                r.itemProvider.loadDataRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { data, _ in
                    datas[i] = data
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.onPick(datas.compactMap { $0 })
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
            // 按天冻结（新→旧），插到既有归档之前。归
            // 档戳 = 日志当天（组内最后一条的时刻），
            // 不用冻结时刻冒充（批 C 口径修正）。
            let days = Dictionary(grouping: old) { $0.dayKey }
            let fresh = days.keys.sorted(by: >).map { day in
                let entries = (days[day] ?? [])
                    .sorted { $0.ts < $1.ts }
                return DiagArchive(
                    stamp: Fmt.fullStamp(
                        entries.last?.ts
                            ?? Date().timeIntervalSince1970),
                    entries: entries)
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

    /// 落盘节流（批 C，对 Web 1s 节流合并写口径）：
    /// 普通行 1s 内合并一写，error 行立即刷盘；结构
    /// 性变更（加载冻结/归档）仍走 persist() 直写。
    private var persistWork: DispatchWorkItem?
    private func schedulePersist(immediate: Bool) {
        if immediate {
            persistWork?.cancel()
            persistWork = nil
            persist()
            return
        }
        guard persistWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.persistWork = nil
            self?.persist()
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1, execute: work)
    }

    private func freezeToday() {
        guard !today.isEmpty else { return }
        // 戳 = 被冻结那天最后一条的时刻（日志当天）。
        let stamp = Fmt.fullStamp(
            today.map(\.ts).max()
                ?? Date().timeIntervalSince1970)
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
            self.schedulePersist(
                immediate: level == .error)
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
        @Published var levelOpen = false
        @Published var route: Route?
        @Published var shareURL: URL?
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
                    .buttonStyle(CardPressStyle())
                    .padding(.top, 24)

                    // 全量一键导出（批 C）：当天 + 全部归
                    // 档拼一个文件走系统分享，不必逐页导。
                    Button {
                        exportEverything()
                    } label: {
                        HStack {
                            Image(systemName:
                                "square.and.arrow.up")
                                .font(.system(size: 14,
                                               weight: .semibold))
                            Text("导出全部日志")
                                .font(.system(size: 14,
                                               weight: .semibold))
                            Spacer()
                            Text("当天 + 全部归档")
                                .font(.system(size: 12))
                                .foregroundStyle(T.textSecondary)
                        }
                        .foregroundStyle(T.textMain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .glassCard(radius: 20)
                    .padding(.top, 12)

                    SectionHeader(text: "历史归档")
                    if diag.archives.isEmpty {
                        Text("暂无归档——跨天后前一天的日志"
                            + "会自动冻结成归档（上限 60 份）。")
                            .font(.system(size: 13))
                            .foregroundStyle(T.textSecondary)
                            .padding(.horizontal, 4)
                    } else {
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
                                .buttonStyle(CardPressStyle())
                            }
                        }
                    }

                    // 库状态读数（真实库的实时事实，非自
                    // 检）：阶段 0 自检链的历史使命（在真
                    // 机证明 FFI 链可用）已于阶段 0 关单时
                    // 结束，且它跑临时目录、与真实库无关、
                    // 报告不入日志——按钮与报告已去除；
                    // FFI 函数本体保留给宿主 cargo test。
                    SectionHeader(text: "库状态")
                    VStack(alignment: .leading, spacing: 6) {
                        DiagLine("路径", library.storeDir)
                        DiagLine("篇数", "\(library.memos.count)")
                        DiagLine("附件数",
                                 "\(library.attachmentCount())")
                        DiagLine("库哈希", library.libraryHash())
                        DiagLine("冷启", library.timing)
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
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
    }

    /// 全量导出：归档旧→新在前、当天在后，逐段带戳
    /// 头；导出结局记一行（该行入当天日志、不入本次
    /// 文件，与 Web 导出记行同口径）。
    private func exportEverything() {
        var parts: [String] = []
        for arch in diag.archives.reversed() {
            parts.append("==== \(arch.stamp) ====")
            parts += arch.entries.map { $0.line }
        }
        parts.append("==== 今天 ====")
        parts += diag.today.map { $0.line }
        let text = parts.joined(separator: "\n")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "此刻诊断_\(f.string(from: Date())).log")
        do {
            try text.write(to: url, atomically: true,
                           encoding: .utf8)
            DiagLog.shared.log(.info,
                "导出全部日志 archives="
                + "\(diag.archives.count) today="
                + "\(diag.today.count)")
            ui.shareURL = url
        } catch {
            DiagLog.shared.log(.error,
                "导出全部日志失败: \(error)")
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

// ── 斜杠命令表（Web render.rs SLASH_CMDS 逐项移植：
// 标题/副标题取 zh-CN 语言包定稿，kw/py 为过滤全集） ──
struct SlashCmd {
    var act: String
    var oid: String
    var icon: String
    var title: String
    var sub: String
    var shortcut: String
    var group: Int  // 0 基础、1 媒体
    var kw: String
    var py: String
}

enum SlashCmds {
    static let all: [SlashCmd] = [
        .init(act: "heading1", oid: "heading", icon: "textformat.size", title: "标题 1", sub: "一级标题", shortcut: "# ", group: 0, kw: "h1 heading 标题 一级", py: "bt1"),
        .init(act: "heading2", oid: "heading2", icon: "textformat.size", title: "标题 2", sub: "二级标题", shortcut: "## ", group: 0, kw: "h2 heading2 标题 二级", py: "bt2"),
        .init(act: "heading3", oid: "heading3", icon: "textformat.size", title: "标题 3", sub: "三级标题", shortcut: "### ", group: 0, kw: "h3 heading3 标题 三级", py: "bt3"),
        .init(act: "paragraph", oid: "paragraph", icon: "text.alignleft", title: "文本", sub: "普通段落", shortcut: "", group: 0, kw: "p paragraph 文本", py: "wb"),
        .init(act: "quote", oid: "quote", icon: "quote.opening", title: "引用", sub: "引用块", shortcut: "> ", group: 0, kw: "q quote 引用", py: "yy"),
        .init(act: "todo", oid: "todo", icon: "checklist", title: "待办", sub: "任务清单", shortcut: "[ ] ", group: 0, kw: "t todo 待办", py: "db"),
        .init(act: "divider", oid: "divider", icon: "minus", title: "分割线", sub: "插入分隔符", shortcut: "---", group: 0, kw: "d divider 分割线", py: "fgx"),
        .init(act: "bold", oid: "bold", icon: "bold", title: "加粗", sub: "包裹选中文字为 **粗体**", shortcut: "** **", group: 0, kw: "b bold 加粗 粗体", py: "jc"),
        .init(act: "italic", oid: "italic", icon: "italic", title: "斜体", sub: "包裹选中文字为 *斜体*", shortcut: "* *", group: 0, kw: "i italic 斜体 倾斜", py: "xt"),
        .init(act: "highlight", oid: "highlight", icon: "highlighter", title: "高亮", sub: "包裹选中文字为 ==高亮==", shortcut: "== ==", group: 0, kw: "h highlight 高亮", py: "gl"),
        .init(act: "codeBlock", oid: "codeBlock", icon: "chevron.left.forwardslash.chevron.right", title: "代码块", sub: "插入代码块", shortcut: "```", group: 0, kw: "code codeblock 代码块", py: "dmk"),
        .init(act: "bulletList", oid: "unorderedList", icon: "list.bullet", title: "无序列表", sub: "转为 - 列表项", shortcut: "- ", group: 0, kw: "list ul 无序列表 列表", py: "wxl"),
        .init(act: "numberList", oid: "orderedList", icon: "list.number", title: "有序列表", sub: "转为 1. 列表项", shortcut: "1. ", group: 0, kw: "ol list 有序列表 列表", py: "yxl"),
        .init(act: "callout", oid: "callout", icon: "exclamationmark.bubble", title: "Callout", sub: "插入 >[!NOTE] 提示卡片", shortcut: "> [!]", group: 0, kw: "callout note tip warning 提示 警告", py: "callout"),
        .init(act: "link", oid: "link", icon: "link", title: "链接", sub: "选中文字转超链接", shortcut: "[](url)", group: 0, kw: "l link 链接 超链接", py: "lj"),
        .init(act: "code", oid: "code", icon: "chevron.left.forwardslash.chevron.right", title: "代码", sub: "内联代码包裹", shortcut: "` `", group: 0, kw: "c code 代码 内联", py: "dm"),
        .init(act: "strikethrough", oid: "strikethrough", icon: "strikethrough", title: "删除线", sub: "包裹选中文字为 ~~删除线~~", shortcut: "~~ ~~", group: 0, kw: "s strike strikethrough 删除线", py: "scx"),
        .init(act: "imgTextCard", oid: "imgTextCard", icon: "doc.richtext", title: "图文卡片", sub: "圆角上图下文卡片", shortcut: "", group: 1, kw: "image text card 图文 卡片", py: "twkp"),
        .init(act: "imageTextRow", oid: "imageTextRow", icon: "rectangle.split.2x1", title: "图文混排", sub: "图片文字左右并排", shortcut: "", group: 1, kw: "image text row 图文 混排 左右", py: "twhp"),
        .init(act: "musicCard", oid: "musicCard", icon: "music.note", title: "音乐卡片", sub: "插入音乐链接卡片", shortcut: "", group: 1, kw: "m music 音乐 卡片", py: "yykp"),
        .init(act: "image", oid: "image", icon: "photo", title: "图片", sub: "插入图片占位", shortcut: "", group: 1, kw: "i image 图片", py: "tp"),
        .init(act: "gallery", oid: "gallery", icon: "photo.on.rectangle.angled", title: "画廊", sub: "插入多图画廊", shortcut: "", group: 1, kw: "g gallery 画廊", py: "hl"),
    ]

    static func filtered(_ q: String) -> [SlashCmd] {
        let query = q.trimmingCharacters(in: .whitespaces)
            .lowercased()
        if query.isEmpty { return all }
        return all.filter { c in
            (c.title + c.sub + c.kw + c.act + c.py)
                .lowercased().contains(query)
        }
    }

    static func recents() -> [SlashCmd] {
        let ids = UserDefaults.standard
            .stringArray(forKey: "slashRecentOids") ?? []
        return ids.compactMap { oid in
            all.first { $0.oid == oid }
        }
    }

    static func recordRecent(_ act: String) {
        guard let cmd = all.first(where: { $0.act == act })
        else { return }
        var ids = UserDefaults.standard
            .stringArray(forKey: "slashRecentOids") ?? []
        ids.removeAll { $0 == cmd.oid }
        ids.insert(cmd.oid, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(6)),
                                  forKey: "slashRecentOids")
    }
}

// ── 编辑器 ─────────────────────────────────────────
struct ImageTarget: Identifiable {
    let id = UUID()
    var fileId: String?
    var urlString: String?
    var name: String
}

/// 编辑页滚动状态（独立对象）：scrollY 的发布只失效
/// 观察它的页眉子树。教训——ObservableObject 订阅是
/// 对象粒度，scrollY 与 EditorUI 共居一对象时，滚动
/// 逐帧发布会连带整个编辑页重演算（0.9.6 隔离无效
/// 的根源，三线审计定案）。
final class EditorScrollState: ObservableObject {
    @Published var scrollY: CGFloat = 0
    var maxScrollY: CGFloat = 0
    /// 静止基线（首个有效探针值捕获）与捕获时的形态；
    /// 形态切换即作废重捕。0.9.9 曾改常数 168 推算，
    /// 与真机探针实际静止值不符、页眉开篇即紧凑——
    /// 退回捕获制（0.9.7 真机形态）并加两道守卫。
    var baseY: CGFloat?
    var baseMode = -1
    /// SCROLL 轨迹打点节流（诊断用）：上次记行值与时刻。
    var traceY: CGFloat = .nan
    var traceAt: Date = .distantPast
}

final class EditorModel: ObservableObject {
    let scrollState = EditorScrollState()
    @Published var title: String
    @Published var blocks: [BlockState]
    @Published var draggingId: String?
    @Published var dragDy: CGFloat = 0
    @Published var imageTarget: ImageTarget?
    @Published var bgColor: String?
    /// 双栏布局锚（Web MemoLayout 口径）：{version, mode,
    /// left, right}，left/right 为两栏块 id 名单；persist
    /// 时写回 raw["layout"]，与 Web 互通同一字段。
    @Published var layout: [String: Any]?
    /// 双栏独立滚动模式（true=independent、false=flow）。
    /// 决议序同 Web：layout.mode 在位优先；有 layout 无
    /// mode 默认 independent（G-2）；无 layout 读用户默认。
    @Published var twoPaneIndependent = false
    /// 当前是否处于宽屏双栏呈现（EditorView 同步进来，
    /// 供拖拽栏内钳制与落锚判定）。
    var columnsActive = false
    private var anchorCaptureDone = false
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
        DiagLog.shared.log(.info,
            "EDIT card replace image \(id) fid=\(fileId)")
    }

    // ── 卡片浮层菜单 + 卡编辑态（F1/F2，Web layers.rs
    // CardMenuLayer 口径）──
    // 菜单覆盖的原子块类型（Web CARD_MENU_TYPES）；
    // 其中可进编辑态/有编辑动作的为 editCardTypes
    // （Web has_edit 名单），musicCard 的「编辑」是即时
    // 输 URL 动作、不设持续编辑态。
    static let cardMenuTypes: Set<String> = [
        "imgTextCard", "imageTextRow", "image", "gallery",
        "musicCard", "link-card", "attachment", "video",
        "divider",
    ]
    static let editCardTypes: Set<String> = [
        "imgTextCard", "imageTextRow", "image", "gallery",
        "musicCard",
    ]
    @Published var cardMenuBlockId: String?
    @Published var cardEditBlockId: String?

    func exitCardEdit(via: String) {
        guard let id = cardEditBlockId else { return }
        cardEditBlockId = nil
        DiagLog.shared.log(.info,
            "EDIT card edit exit \(id) (\(via))")
    }

    // 图库选图（编辑态）：add = 多选追加、replace =
    // 单选换指定张；状态由 EditorView 的 sheet 消费。
    @Published var showGalleryAddPicker = false
    @Published var showGalleryReplacePicker = false
    var galleryPickBlockId: String?
    var galleryReplaceIndex: Int?

    func applyGalleryAdd(blockId: String, fileIds: [String]) {
        guard let b = blocks.first(where: { $0.id == blockId }),
              !fileIds.isEmpty else { return }
        pushHistory()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        var items = attrs["items"] as? [[String: Any]] ?? []
        for fid in fileIds {
            items.append(["fileId": fid])
        }
        attrs["items"] = items
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT gallery add \(blockId) +\(fileIds.count)")
    }

    func applyGalleryReplace(blockId: String, index: Int,
                             fileId: String) {
        guard let b = blocks.first(where: { $0.id == blockId })
        else { return }
        pushHistory()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        var items = attrs["items"] as? [[String: Any]] ?? []
        guard items.indices.contains(index) else { return }
        items[index] = ["fileId": fileId]
        attrs["items"] = items
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT gallery replace \(blockId) idx=\(index)")
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
        ["image", "gallery", "video", "musicCard", "link-card",
         "attachment", "imgTextCard", "imageTextRow",
         "divider"].contains(t)
    }

    init(item: MemoItem, library: Library) {
        self.item = item
        self.library = library
        title = item.title
        blocks = item.blocks
        bgColor = item.bgColor
        // 双栏决议（Web hooks/columns.rs 口径）：mode 在位
        // 优先；有 layout 无 mode 默认 independent（G-2）；
        // 无 layout 读用户级默认（开关切换时写入）。
        let rawLayout = item.raw["layout"] as? [String: Any]
        layout = rawLayout
        if let mode = rawLayout?["mode"] as? String {
            twoPaneIndependent = (mode == "independent")
        } else if rawLayout != nil {
            twoPaneIndependent = true
        } else {
            twoPaneIndependent = UserDefaults.standard.bool(
                forKey: "editorIndependentScroll")
        }
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
        // 卡片补拉（Web hydrate 口径）：有 url、未就绪的
        // 音乐/链接卡打开时补走解析链。
        let pending = blocks.filter {
            ($0.type == "musicCard" || $0.type == "link-card")
                && ($0.node["url"] as? String)
                    .map({ !$0.isEmpty }) ?? false
                && !["ready", "input", "loading"].contains(
                    $0.node["status"] as? String ?? "")
        }
        if !pending.isEmpty {
            DispatchQueue.main.async { [weak self] in
                for b in pending {
                    var n = b.node
                    n["status"] = "loading"
                    b.node = n
                    b.nodeVersion += 1
                    self?.startResolveCard(b)
                }
            }
        }
        // MD 块级预览段的尾随空段物化（打开时先行一趟，
        // 与 Web init 口径一致）。
        materializeMdTrails()
    }

    // ── 双栏分界（Web editor/columns.rs 逐项移植） ──
    /// 块的纯文本（递归含列表项，与 Web plain_text 口径
    /// 一致，供估高折行）。
    static func plainText(of b: BlockState) -> String {
        var s = b.text
        for it in b.itemStates { s += plainText(of: it) }
        if let n = b.nestedList { s += plainText(of: n) }
        return s
    }

    /// 规范估高（Web est_block_height 回退表）：图片/画廊
    /// /图文卡 280，音乐/链接/嵌入卡 120，附件带图 280
    /// 否则 120，其余按 UTF-16 长度 44 字/行折行
    /// 28 + 行数×25。
    static func estBlockHeight(_ b: BlockState) -> Double {
        switch b.type {
        case "image", "gallery", "imgTextCard", "imageTextRow":
            return 280
        case "musicCard", "link-card", "embedCard":
            return 120
        case "attachment":
            return (b.node["image"] as? Bool) == true
                ? 280 : 120
        default:
            let len = plainText(of: b).utf16.count
            let lines = max(1.0, (Double(len) / 44.0)
                .rounded(.up))
            return 28 + lines * 25
        }
    }

    /// 无锚规范分界：在 [1, len-1] 取左右估高最接近点；
    /// 不足两块全归左栏。
    static func canonicalBoundary(
        blocks: [BlockState]) -> Int {
        if blocks.count < 2 { return blocks.count }
        let weights = blocks.map { estBlockHeight($0) }
        let total = weights.reduce(0, +)
        var running = 0.0
        var split = 1
        var best = Double.infinity
        for i in 1..<blocks.count {
            running += weights[i - 1]
            let diff = abs(total - running * 2)
            if diff < best { best = diff; split = i }
        }
        return split
    }

    /// 锚归一：right 名单第一个存活块为右栏起点；right
    /// 全灭时取 left 名单最后一个存活块之后；名单任一
    /// 缺失或两边无存活 id 返回 nil（视同无锚）。
    static func normalizeBoundary(
        blocks: [BlockState],
        layout: [String: Any]) -> Int? {
        guard let left = layout["left"] as? [String],
              let right = layout["right"] as? [String]
        else { return nil }
        let ids = blocks.map { $0.id }
        let positions = { (arr: [String]) in
            arr.compactMap { ids.firstIndex(of: $0) }
        }
        if let first = positions(right).min() { return first }
        if let last = positions(left).max() {
            return min(last + 1, blocks.count)
        }
        return nil
    }

    /// 当前有效分界：independent 走锚优先、flow 恒走
    /// 规范估高（Web 口径：flow 不读不写 layout 分界）。
    var columnBoundaryIndex: Int {
        if twoPaneIndependent, let l = layout,
           let b = Self.normalizeBoundary(
               blocks: blocks, layout: l) {
            return b
        }
        return Self.canonicalBoundary(blocks: blocks)
    }

    /// 独立双栏首次宽屏渲染且无有效锚时，按规范分界一
    /// 次性落锚写库（Web 落锚口径）；此后成员由锚决定。
    func captureAnchorIfNeeded() {
        if anchorCaptureDone { return }
        anchorCaptureDone = true
        guard twoPaneIndependent, blocks.count >= 2
        else { return }
        if let l = layout,
           Self.normalizeBoundary(
               blocks: blocks, layout: l) != nil {
            return
        }
        let b = Self.canonicalBoundary(blocks: blocks)
        let ids = blocks.map { $0.id }
        layout = ["version": 1, "mode": "independent",
                  "left": Array(ids[..<b]),
                  "right": Array(ids[b...])]
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT column anchor captured boundary=\(b)")
    }

    // ── MD 预览（E16 接线；解析走 core 同一解析器） ──
    /// 段落的 MD 分类（FFI md_classify；仅 paragraph
    /// 入判据，结果按文本缓存）。
    func mdKind(for block: BlockState) -> String {
        guard block.type == "paragraph" else { return "none" }
        if block.mdCacheText == block.text {
            return block.mdCacheKind
        }
        let kind = mdClassify(text: block.text)
        block.mdCacheText = block.text
        block.mdCacheKind = kind
        block.mdCacheBlocks = []
        return kind
    }

    /// 段落的 MD 解析树（FFI md_parse_json；元素为单键
    /// dict 或单元变体字符串如 "Divider"）。
    func mdBlocks(for block: BlockState) -> [Any] {
        if block.mdCacheText == block.text,
           !block.mdCacheBlocks.isEmpty {
            return block.mdCacheBlocks
        }
        let json = mdParseJson(text: block.text)
        let arr = (try? JSONSerialization.jsonObject(
            with: Data(json.utf8))) as? [Any] ?? []
        block.mdCacheText = block.text
        block.mdCacheBlocks = arr
        return arr
    }

    /// 点按预览回源码（Web 口径）：光标恒落源码末尾。
    func beginMdEdit(_ block: BlockState) {
        editingBlockId = block.id
        focusBlockId = block.id
        focusCaretEnd = true
    }

    /// 块级预览段判据（Web trail_judges 口径）。
    private func isBlockPreviewPara(_ b: BlockState)
        -> Bool {
        b.type == "paragraph" && mdKind(for: b) != "none"
            && mdIsBlockPreview(text: b.text)
    }

    /// 尾随空段物化（Web materialize_trails 口径）：块级
    /// 预览段（列表段除外）之后接文末/原子块/列表段/另
    /// 一预览段时，补一真实空段落（会落盘）；编辑中块
    /// 跳过、失焦时再补。重复调用幂等。
    func materializeMdTrails() {
        let atomicNext: Set<String> = [
            "image", "gallery", "imgTextCard", "imageTextRow",
            "attachment", "link-card", "musicCard",
            "embedCard", "divider",
        ]
        var inserted = 0
        var i = 0
        while i < blocks.count {
            let b = blocks[i]
            if isBlockPreviewPara(b),
               mdKind(for: b) != "list",
               editingBlockId != b.id {
                var need = false
                if i + 1 >= blocks.count {
                    need = true
                } else {
                    let next = blocks[i + 1]
                    need = atomicNext.contains(next.type)
                        || next.isList
                        || mdKind(for: next) == "list"
                        || isBlockPreviewPara(next)
                }
                if need {
                    blocks.insert(BlockState(node: [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": "paragraph",
                        "children": [["text": ""]],
                    ]), at: i + 1)
                    inserted += 1
                    i += 2
                    continue
                }
            }
            i += 1
        }
        if inserted > 0 { scheduleSave() }
    }

    /// 双栏开关（Web toggle_twopane 口径）：翻转模式、
    /// 写用户级默认、按当前分界把 layout 重写为带新
    /// mode 的名单落库（切 flow 也写锚）。
    func toggleTwoPane() {
        pushHistory()
        let b = columnBoundaryIndex
        twoPaneIndependent.toggle()
        UserDefaults.standard.set(
            twoPaneIndependent,
            forKey: "editorIndependentScroll")
        let ids = blocks.map { $0.id }
        let bb = min(b, ids.count)
        layout = ["version": 1,
                  "mode": twoPaneIndependent
                      ? "independent" : "flow",
                  "left": Array(ids[..<bb]),
                  "right": Array(ids[bb...])]
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT twoPane toggled -> "
            + (twoPaneIndependent ? "independent" : "flow"))
    }

    private func snapshot() -> [String: Any] {
        ["title": title,
         "doc": blocks.map { $0.flushedNode() },
         "layout": layout ?? NSNull()]
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
        // 历史与 doc+layout 成对回退（Web 口径）：锚随
        // 快照恢复；模式开关状态本身不入历史。
        layout = s["layout"] as? [String: Any]
        scheduleSave()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        applySnapshot(s)
        syncHistoryFlags()
        DiagLog.shared.log(.info,
            "EDIT undo 余栈 undo=\(undoStack.count) "
            + "redo=\(redoStack.count)")
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        applySnapshot(s)
        syncHistoryFlags()
        DiagLog.shared.log(.info,
            "EDIT redo 余栈 undo=\(undoStack.count) "
            + "redo=\(redoStack.count)")
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
        if let l = layout {
            it.raw["layout"] = l
        } else {
            it.raw.removeValue(forKey: "layout")
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

    /// 粘贴图片成块（E17）：存附件后在当前块后插图片
    /// 块；图后非文本块则补尾随空段并落焦（原子块收尾
    /// 口径），是文本块则落焦其首。
    func insertPastedImage(block: BlockState, data: Data) {
        let fid = "att-" + UUID().uuidString
            .prefix(12).lowercased()
        // 写失败不成块：不留引用空附件的死块。
        guard library.putAttachment(fid, data) else {
            DiagLog.shared.log(.error,
                "粘贴图片未成块（附件写入失败）fid=\(fid)")
            return
        }
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "image",
            "attrs": ["fileId": fid],
            "children": [],
        ])
        if let i = blocks.firstIndex(
            where: { $0 === block }) {
            blocks.insert(b, at: i + 1)
            if i + 2 < blocks.count, blocks[i + 2].isText {
                focusBlockId = blocks[i + 2].id
                focusCaretEnd = false
            } else {
                let p = trailingParagraph(after: b)
                focusBlockId = p.id
                focusCaretEnd = false
            }
        } else {
            blocks.append(b)
        }
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT paste image -> block \(fid)")
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

    // ── 斜杠菜单（E14） ────────────────────────────
    @Published var slashBlockId: String?
    @Published var slashQuery: String = ""
    @Published var linkFormBlockId: String?

    /// 文本变化时跟随（Web 桥 processInput 口径）：光标
    /// 前最后一个「/」起、无空白至光标为 token（块内任意
    /// 位置可触发，含列表项）；URL 形 token 抑制；查询
    /// ≤30 字。token 区间与选区以字符偏移记下，执行时
    /// 按偏移剥离/包裹（审计 C S-1/S-3）。
    func updateSlash(for block: BlockState,
                     selUTF16: NSRange) {
        let eligible = (block.isText
            || block.type == "list-item")
            && block.type != "codeBlock"
            && block.type != "callout"
        guard eligible else {
            if slashBlockId == block.id { slashBlockId = nil }
            return
        }
        let ns = block.text as NSString
        let start16 = min(selUTF16.location, ns.length)
        let end16 = min(selUTF16.location
            + selUTF16.length, ns.length)
        let selStart = ns.substring(to: start16).count
        let caret = ns.substring(to: end16).count
        let selLen = caret - selStart
        let chars = Array(block.text)
        var tokenStart: Int? = nil
        var i = caret
        while i > 0 {
            let c = chars[i - 1]
            if c == " " || c == "\n" || c == "\t" || c == "　" {
                break
            }
            if c == "/" { tokenStart = i - 1; break }
            i -= 1
        }
        func close() {
            if slashBlockId == block.id {
                slashBlockId = nil
            }
        }
        guard let ts = tokenStart else { close(); return }
        // URL 抑制：token 前是 : 或 /（scheme 内斜杠），
        // 或所在词以 www./http 起头。
        if ts > 0 && (chars[ts - 1] == ":"
            || chars[ts - 1] == "/") {
            close()
            return
        }
        var wordStart = ts
        while wordStart > 0 && chars[wordStart - 1] != " "
            && chars[wordStart - 1] != "\n" {
            wordStart -= 1
        }
        let word = String(chars[wordStart..<caret])
        if word.hasPrefix("www.") || word.hasPrefix("http") {
            close()
            return
        }
        let query = String(chars[(ts + 1)..<caret])
        guard query.count <= 30 else { close(); return }
        slashBlockId = block.id
        slashQuery = query
        slashTokenStart = ts
        slashTokenLen = caret - ts
        slashSelStart = selStart
        slashSelLen = selLen
    }

    // token 区间与触发选区（字符偏移，与 runs 同口径）。
    private var slashTokenStart = 0
    private var slashTokenLen = 0
    private var slashSelStart = 0
    private var slashSelLen = 0
    private var linkSelStart = 0
    private var linkSelLen = 0
    private var linkTokenStart = 0
    /// 音乐输入胶囊的聚焦请求（斜杠 musicCard 落点）。
    @Published var focusMusicId: String?

    /// runs 按字符区间删除（token 剥离），同步 text。
    private func removeRunRange(_ b: BlockState, start: Int,
                                len: Int) {
        guard len > 0 else { return }
        var out: [[String: Any]] = []
        var pos = 0
        for r in b.runs {
            let t = r["text"] as? String ?? ""
            let rl = t.count
            let rEnd = pos + rl
            if rEnd <= start || pos >= start + len {
                out.append(r)
            } else {
                let cutL = max(0, start - pos)
                let cutR = min(rl, start + len - pos)
                let kept = String(t.prefix(cutL))
                    + String(t.dropFirst(cutR))
                if !kept.isEmpty {
                    var nr = r
                    nr["text"] = kept
                    out.append(nr)
                }
            }
            pos = rEnd
        }
        b.runs = out
        var cs = Array(b.text)
        let lo = max(0, min(start, cs.count))
        let hi = max(lo, min(start + len, cs.count))
        cs.removeSubrange(lo..<hi)
        b.text = String(cs)
        b.nodeVersion += 1
    }

    /// runs 区间打标记（必要时在边界切分 run）。
    private func markRunRange(_ b: BlockState, start: Int,
                              len: Int, key: String,
                              value: Any = true) {
        guard len > 0 else { return }
        var out: [[String: Any]] = []
        var pos = 0
        for r in b.runs {
            let t = r["text"] as? String ?? ""
            let rl = t.count
            let segS = max(pos, start)
            let segE = min(pos + rl, start + len)
            if segS >= segE {
                out.append(r)
                pos += rl
                continue
            }
            let l = segS - pos
            let rr = segE - pos
            if l > 0 {
                var a = r
                a["text"] = String(t.prefix(l))
                out.append(a)
            }
            var mid = r
            mid["text"] = String(t.dropFirst(l)
                .prefix(rr - l))
            mid[key] = value
            out.append(mid)
            if rr < rl {
                var c = r
                c["text"] = String(t.dropFirst(rr))
                out.append(c)
            }
            pos += rl
        }
        b.runs = out
        b.nodeVersion += 1
    }

    /// runs 指定字符偏移插入一个 run，同步 text。
    private func insertRun(_ b: BlockState, at: Int,
                           run: [String: Any]) {
        let insText = run["text"] as? String ?? ""
        var out: [[String: Any]] = []
        var pos = 0
        var done = false
        for r in b.runs {
            let t = r["text"] as? String ?? ""
            let rl = t.count
            if !done && at >= pos && at <= pos + rl {
                let l = at - pos
                if l > 0 {
                    var a = r
                    a["text"] = String(t.prefix(l))
                    out.append(a)
                }
                out.append(run)
                if l < rl {
                    var c = r
                    c["text"] = String(t.dropFirst(l))
                    out.append(c)
                }
                done = true
            } else {
                out.append(r)
            }
            pos += rl
        }
        if !done { out.append(run) }
        b.runs = out
        var cs = Array(b.text)
        cs.insert(contentsOf: Array(insText),
                  at: max(0, min(at, cs.count)))
        b.text = String(cs)
        b.nodeVersion += 1
    }

    /// token 剥离后的选区修正（Web applyInline 偏移口径）。
    private func adjustedSel() -> (Int, Int) {
        var s = slashSelStart
        var l = slashSelLen
        let ts = slashTokenStart
        let te = slashTokenStart + slashTokenLen
        if s >= te {
            s -= slashTokenLen
        } else if s + l > ts {
            let overlap = min(s + l, te) - max(s, ts)
            l = max(0, l - overlap)
            if s > ts { s = ts }
        }
        return (s, l)
    }

    /// 选区首尾空白外置（Web 口径）：全空白选区不收缩。
    private func trimmedSel(_ b: BlockState, _ s: Int,
                            _ l: Int) -> (Int, Int) {
        let cs = Array(b.text)
        guard l > 0, s >= 0, s + l <= cs.count
        else { return (s, l) }
        var lead = 0
        while lead < l && cs[s + lead].isWhitespace {
            lead += 1
        }
        var trail = 0
        while trail < l - lead
            && cs[s + l - 1 - trail].isWhitespace {
            trail += 1
        }
        if lead + trail >= l { return (s, l) }
        return (s + lead, l - lead - trail)
    }

    private func trailingParagraph(after b: BlockState)
        -> BlockState {
        let p = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ])
        if let i = blocks.firstIndex(where: { $0 === b }) {
            blocks.insert(p, at: i + 1)
        } else {
            blocks.append(p)
        }
        return p
    }

    /// 列表项升格：把列表项提出为独立段落（原列表按
    /// 前/后项拆成两段，尾段有序编号续接），返回升格
    /// 后的段落状态，供块型命令按顶层口径继续转换。
    private func promoteListItem(list: BlockState,
                                 item: BlockState)
        -> BlockState {
        guard let li = blocks.firstIndex(
                where: { $0 === list }),
              let ii = list.itemStates.firstIndex(
                where: { $0 === item })
        else { return item }
        let before = Array(list.itemStates[..<ii])
        let after = Array(list.itemStates[(ii + 1)...])
        let promoted = BlockState(node: [
            "id": item.id,
            "type": "paragraph",
            "children": BlockState.childrenFrom(
                runs: item.runs),
        ])
        promoted.runs = item.runs
        promoted.text = item.text
        blocks.remove(at: li)
        var insertAt = li
        if !before.isEmpty {
            list.itemStates = before
            list.nodeVersion += 1
            blocks.insert(list, at: insertAt)
            insertAt += 1
        }
        blocks.insert(promoted, at: insertAt)
        insertAt += 1
        if !after.isEmpty {
            var n = list.node
            n["id"] = "b-" + UUID().uuidString
                .prefix(8).lowercased()
            n["children"] = [[String: Any]]()
            if list.type == "numbered-list" {
                var attrs = n["attrs"] as? [String: Any]
                    ?? [:]
                let start0 = attrs["start"] as? Int ?? 1
                attrs["start"] = start0 + before.count + 1
                n["attrs"] = attrs
            }
            let tail = BlockState(node: n)
            tail.itemStates = after
            blocks.insert(tail, at: insertAt)
        }
        return promoted
    }

    /// 行内斜杠命令（Web applyInline 口径）：剥 token 后
    /// 按修正选区包裹；无选区插入占位「文字」并打标，
    /// 光标落其后。link 转链接表单（提交时按选区挂链
    /// 或插入字面链接）。
    private func applyInlineSlash(_ act: String,
                                  on b: BlockState) {
        removeRunRange(b, start: slashTokenStart,
                       len: slashTokenLen)
        var (s, l) = adjustedSel()
        (s, l) = trimmedSel(b, s, l)
        if act == "link" {
            linkSelStart = s
            linkSelLen = l
            linkTokenStart = slashTokenStart
            linkFormBlockId = b.id
            return
        }
        if l > 0 {
            if act == "highlight" {
                insertRun(b, at: s + l, run: ["text": "=="])
                insertRun(b, at: s, run: ["text": "=="])
                pendingCaretOffset = s + l + 2
            } else {
                markRunRange(b, start: s, len: l, key: act)
                pendingCaretOffset = s + l
            }
        } else {
            let at = slashTokenStart
            if act == "highlight" {
                insertRun(b, at: at, run: ["text": "==文字=="])
                pendingCaretOffset = at + 6
            } else {
                insertRun(b, at: at,
                          run: ["text": "文字", act: true])
                pendingCaretOffset = at + 2
            }
        }
        focusBlockId = b.id
        focusCaretEnd = false
    }

    /// 斜杠命令执行（Web 分流口径）：行内命令就地标记；
    /// 图片/画廊落占位块 + 尾随空段；其余转块型。触发
    /// 块可在顶层或列表项内（块型命令先升格）。
    func applySlash(_ act: String) {
        guard let bid = slashBlockId else { return }
        var found: BlockState?
        var parentList: BlockState?
        if let b = blocks.first(where: { $0.id == bid }) {
            found = b
        } else {
            for l in blocks where l.isList {
                if let it = l.itemStates.first(
                    where: { $0.id == bid }) {
                    found = it
                    parentList = l
                    break
                }
            }
        }
        guard let target = found
        else { slashBlockId = nil; return }
        // link 例外：表单在斜杠面板内原地替换列表，
        // 会话保留到表单收口；最近使用也改到提交成功
        // 时记录（Web 口径）。
        if act != "link" {
            slashBlockId = nil
            SlashCmds.recordRecent(act)
        }
        pushHistory()
        let inlineActs: Set<String> = [
            "bold", "italic", "code", "strikethrough",
            "highlight", "link",
        ]
        if inlineActs.contains(act) {
            applyInlineSlash(act, on: target)
            scheduleSave()
            return
        }
        removeRunRange(target, start: slashTokenStart,
                       len: slashTokenLen)
        var b = target
        if let list = parentList {
            b = promoteListItem(list: list, item: target)
        }
        func convert(_ type: String,
                     level: Int? = nil) {
            var n = b.node
            n["type"] = type
            n["children"] = BlockState.childrenFrom(
                runs: b.runs)
            var attrs = n["attrs"] as? [String: Any] ?? [:]
            if let level {
                attrs["level"] = level
            }
            if type == "todo" {
                attrs["checked"] = false
            }
            n["attrs"] = attrs.isEmpty ? nil : attrs
            if type == "callout" {
                n["calloutType"] = "note"
            }
            b.node = n
            b.text = b.runs.compactMap {
                $0["text"] as? String
            }.joined()
            b.nodeVersion += 1
        }
        switch act {
        case "heading1": convert("heading", level: 1)
        case "heading2": convert("heading", level: 2)
        case "heading3": convert("heading", level: 3)
        case "paragraph": convert("paragraph")
        case "quote": convert("quote")
        case "todo": convert("todo")
        case "codeBlock": convert("codeBlock")
        case "callout": convert("callout")
        case "divider":
            b.node = ["id": b.id, "type": "divider"]
            b.nodeVersion += 1
            let p = trailingParagraph(after: b)
            focusBlockId = p.id
            focusCaretEnd = false
        case "bulletList", "numberList":
            let item = BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "list-item",
                "children": BlockState.childrenFrom(
                    runs: b.runs),
            ])
            item.runs = b.runs
            item.text = b.text
            b.node = [
                "id": b.id,
                "type": act == "bulletList"
                    ? "bulleted-list" : "numbered-list",
                "children": [],
            ]
            b.itemStates = [item]
            b.nodeVersion += 1
            focusBlockId = item.id
            focusCaretEnd = false
            pendingCaretOffset = min(slashTokenStart,
                                     item.text.count)
        case "image", "gallery":
            if act == "image" {
                b.node = ["id": b.id, "type": "image",
                          "attrs": [String: Any]()]
            } else {
                b.node = ["id": b.id, "type": "gallery",
                          "attrs": ["items":
                            [[String: Any]]()] as [String: Any]]
            }
            b.nodeVersion += 1
            // 尾随已有空段则直接落焦，不重复插（Web
            // next-empty 口径）。
            if let i = blocks.firstIndex(
                where: { $0 === b }),
               i + 1 < blocks.count,
               blocks[i + 1].type == "paragraph",
               blocks[i + 1].text.isEmpty {
                focusBlockId = blocks[i + 1].id
            } else {
                let p = trailingParagraph(after: b)
                focusBlockId = p.id
            }
            focusCaretEnd = false
        case "imgTextCard", "imageTextRow":
            // 占位文案落数据（原版口径），尾随空段承接
            // 焦点（原子卡本身无文本面可落）。
            let ph = act == "imgTextCard"
                ? "点击输入文字" : "点击输入说明文字"
            b.node = ["id": b.id, "type": act, "text": ph]
            b.text = ph
            b.nodeVersion += 1
            let p = trailingParagraph(after: b)
            focusBlockId = p.id
            focusCaretEnd = false
        case "musicCard":
            b.node = ["id": b.id, "type": "musicCard",
                      "status": "input", "url": ""]
            b.nodeVersion += 1
            _ = trailingParagraph(after: b)
            // 焦点落输入胶囊本身（Web 口径）。
            focusMusicId = b.id
        default:
            break
        }
        if act != "divider" && act != "image"
            && act != "gallery" && act != "musicCard"
            && act != "bulletList" && act != "numberList"
            && act != "imgTextCard" && act != "imageTextRow" {
            // 转块型后光标落 token 起点（Web pos 口径）。
            focusBlockId = b.id
            focusCaretEnd = false
            pendingCaretOffset = min(slashTokenStart,
                                     b.text.count)
        }
        scheduleSave()
    }

    /// 链接表单提交（Web applyLink 口径）：有选区按区
    /// 间挂链；无选区在 token 处插入字面 [链接文字](url)
    /// （URL 括号先转义）。
    @discardableResult
    func applyLink(url: String) -> Bool {
        guard let bid = linkFormBlockId else { return false }
        var found: BlockState?
        if let b = blocks.first(where: { $0.id == bid }) {
            found = b
        } else {
            for l in blocks where l.isList {
                if let it = l.itemStates.first(
                    where: { $0.id == bid }) {
                    found = it
                    break
                }
            }
        }
        guard let b = found
        else { linkFormBlockId = nil; return false }
        let trimmed = url.trimmingCharacters(
            in: .whitespaces)
        guard trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://") else { return false }
        linkFormBlockId = nil
        slashBlockId = nil
        SlashCmds.recordRecent("link")
        pushHistory()
        if linkSelLen > 0 {
            markRunRange(b, start: linkSelStart,
                         len: linkSelLen, key: "_link",
                         value: trimmed)
            markRunRange(b, start: linkSelStart,
                         len: linkSelLen, key: "underline")
            pendingCaretOffset = linkSelStart + linkSelLen
        } else {
            let esc = trimmed
                .replacingOccurrences(of: "(", with: "%28")
                .replacingOccurrences(of: ")", with: "%29")
            let literal = "[链接文字](\(esc))"
            insertRun(b, at: linkTokenStart,
                      run: ["text": literal])
            pendingCaretOffset = linkTokenStart
                + literal.count
        }
        focusBlockId = b.id
        focusCaretEnd = false
        scheduleSave()
        return true
    }

    /// 标题/Callout 回车（Web 口径）：不拆文本，整段保
    /// 留、其后插空段落并落焦。
    func headingEnter(_ block: BlockState) {
        pushHistory()
        let p = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ])
        if let i = blocks.firstIndex(
            where: { $0 === block }) {
            blocks.insert(p, at: i + 1)
        } else {
            blocks.append(p)
        }
        focusBlockId = p.id
        focusCaretEnd = false
        scheduleSave()
    }

    // ── 卡片解析链（E19，Web cards.rs 口径） ──────
    /// 从任意文本提第一个 http(s) URL；无 scheme 时整段
    /// 须是裸域名形态才补 https://（逐项移植 Web
    /// extract_card_url 的字符集与校验口径）。
    static func extractCardURL(_ candidate: String)
        -> String? {
        let lower = candidate.lowercased()
        if let r = lower.range(of: "http://")
            ?? lower.range(of: "https://") {
            var idx = r.lowerBound
            var end = candidate.endIndex
            let extra = Set<Character>("-@:%._+~#=?&/()")
            while idx < candidate.endIndex {
                let ch = candidate[idx]
                let scalar = ch.unicodeScalars.first?.value
                    ?? 0
                let ok = ch.isLetter || ch.isNumber
                    || extra.contains(ch)
                    || (0x4e00...0x9fa5).contains(scalar)
                if !ok { end = idx; break }
                idx = candidate.index(after: idx)
                end = idx
            }
            let url = String(candidate[r.lowerBound..<end])
            return URL(string: url) != nil ? url : nil
        }
        let t = candidate.trimmingCharacters(
            in: .whitespaces)
        if t.isEmpty
            || t.contains(where: { $0.isWhitespace }) {
            return nil
        }
        let host = t.split(whereSeparator: {
            "/?#".contains($0)
        }).first.map(String.init) ?? t
        let parts = host.components(separatedBy: ".")
        guard parts.count >= 2,
              let tld = parts.last, tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }),
              let name = parts.dropLast().last,
              !name.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber
                  || $0 == "-" || $0 == "." }) else {
            return nil
        }
        let url = "https://" + t
        return URL(string: url) != nil ? url : nil
    }

    static let musicHosts = ["music.163.com", "163cn.tv",
        "y.qq.com", "i.y.qq.com", "open.spotify.com",
        "music.apple.com"]

    /// 链接元数据（Web fetchLinkMeta：GET Worker /meta）。
    func fetchLinkMeta(_ url: String) async
        -> [String: Any]? {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~"))
        let enc = url.addingPercentEncoding(
            withAllowedCharacters: allowed) ?? url
        guard let u = URL(string:
            "https://mynote.overtrees.workers.dev/meta"
            + "?url=\(enc)") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await
            URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(
            with: data)) as? [String: Any]
    }

    /// 解析一张卡：拉 meta → title 非空 ready、否则
    /// error；竞态守卫 = 回写时 url 仍与发起时一致。
    func startResolveCard(_ block: BlockState) {
        guard let url = block.node["url"] as? String,
              !url.isEmpty else { return }
        Task { @MainActor in
            let meta = await self.fetchLinkMeta(url)
            guard (block.node["url"] as? String) == url
            else { return }
            var n = block.node
            if let meta,
               let t = meta["title"] as? String,
               !t.isEmpty {
                n["meta"] = meta
                n["status"] = "ready"
            } else {
                n["meta"] = NSNull()
                n["status"] = "error"
            }
            block.node = n
            block.nodeVersion += 1
            self.scheduleSave()
            DiagLog.shared.log(.info,
                "CARD resolve \(block.id) -> "
                + (n["status"] as? String ?? ""))
        }
    }

    /// 音乐输入胶囊提交（回车或粘出 URL 时）：提出 URL
    /// 才动作——节点转 loading 走公共解析；解析后光标
    /// 落卡下（下方非文本块则补空段）。
    func submitMusicInput(_ block: BlockState,
                          rawText: String) {
        guard block.type == "musicCard",
              (block.node["status"] as? String) == "input",
              let url = Self.extractCardURL(rawText)
        else { return }
        pushHistory()
        var n = block.node
        n["url"] = url
        n["meta"] = NSNull()
        n["status"] = "loading"
        block.node = n
        block.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "CARD music input resolve \(block.id) <- \(url)")
        startResolveCard(block)
        // 落点：卡下方现成文本块直接用，否则补空段。
        if let i = blocks.firstIndex(
            where: { $0 === block }) {
            if i + 1 < blocks.count,
               blocks[i + 1].isText {
                focusBlockId = blocks[i + 1].id
            } else {
                let p = trailingParagraph(after: block)
                focusBlockId = p.id
            }
            focusCaretEnd = false
        }
    }

    /// 粘贴成卡（Web op_paste_card 口径）：当前块留
    /// before 段，卡插其后（音乐域名 → musicCard、其余
    /// → link-card，status=loading 走公共解析），余文与
    /// after 段各成一段落，焦点按 Web 序落位。
    func pasteCard(block: BlockState, url: String,
                   remain: String,
                   beforeRuns: [[String: Any]],
                   afterRuns: [[String: Any]]) {
        guard let i = blocks.firstIndex(
            where: { $0 === block }) else { return }
        pushHistory()
        block.runs = beforeRuns
        block.text = beforeRuns.compactMap {
            $0["text"] as? String
        }.joined()
        block.nodeVersion += 1
        let isMusic = Self.musicHosts.contains {
            url.contains($0)
        }
        let card = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": isMusic ? "musicCard" : "link-card",
            "url": url, "status": "loading",
        ])
        var at = i + 1
        blocks.insert(card, at: at)
        at += 1
        var focus: (String, Bool)?  // (id, 落末尾?)
        let remainT = remain.trimmingCharacters(
            in: .whitespaces)
        if !remainT.isEmpty {
            let p = BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "paragraph",
                "children": [["text": remainT]],
            ])
            p.runs = [["text": remainT]]
            p.text = remainT
            blocks.insert(p, at: at)
            at += 1
            focus = (p.id, true)
        }
        let afterText = afterRuns.compactMap {
            $0["text"] as? String
        }.joined()
        if !afterText.isEmpty {
            let p = BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "paragraph",
                "children": BlockState.childrenFrom(
                    runs: afterRuns),
            ])
            p.runs = afterRuns
            p.text = afterText
            blocks.insert(p, at: at)
            at += 1
            if focus == nil { focus = (p.id, false) }
        }
        if focus == nil {
            let cardIdx = i + 1
            if cardIdx + 1 < blocks.count,
               blocks[cardIdx + 1].isText {
                focus = (blocks[cardIdx + 1].id, false)
            } else {
                let p = trailingParagraph(after: card)
                focus = (p.id, false)
            }
        }
        if let f = focus {
            focusBlockId = f.0
            focusCaretEnd = f.1
        }
        scheduleSave()
        startResolveCard(card)
    }

    /// 粘贴分流（Web paste 口径）：整段是裸 URL、或内嵌
    /// 媒体 URL 时成卡并消费粘贴；其余放行原生粘贴。
    /// before/after 由调用方按当前选区切好。
    func handlePaste(block: BlockState, text: String,
                     beforeRuns: [[String: Any]],
                     afterRuns: [[String: Any]]) -> Bool {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let mediaHosts = Self.musicHosts
            + ["b23.tv", "xiaohongshu.com", "xhslink.com"]
        // 整段裸 URL（无空白、scheme 开头、含域名点）。
        if !trimmed.contains(where: { $0.isWhitespace }),
           trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://"),
           let url = Self.extractCardURL(trimmed),
           url == trimmed {
            pasteCard(block: block, url: url, remain: "",
                      beforeRuns: beforeRuns,
                      afterRuns: afterRuns)
            return true
        }
        // 内嵌媒体 URL：提 URL 成卡，余文成段。
        if let url = Self.extractCardURL(trimmed),
           mediaHosts.contains(where: {
               url.contains($0) }) {
            let remain = trimmed.replacingOccurrences(
                of: url, with: "")
            pasteCard(block: block, url: url,
                      remain: remain,
                      beforeRuns: beforeRuns,
                      afterRuns: afterRuns)
            return true
        }
        return false
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
        // 双栏呈现时落点钳制在来源栏内（跨栏拖拽单列一
        // 步，未做）；单栏时不钳制。
        if columnsActive, blocks.count > 1 {
            let b = columnBoundaryIndex
            if from < b {
                to = min(to, b - 1)
            } else {
                to = max(to, b)
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
            DiagLog.shared.log(.info,
                "单篇导出 \(format) ok bytes="
                + "\(content.utf8.count) id=\(item.id)")
            return url
        } catch {
            DiagLog.shared.log(.error,
                "单篇导出 \(format) 失败: \(error)")
            return nil
        }
    }

    func exportPDF(completion: @escaping (URL?) -> Void) {
        let html = ExportGen.html(title: title, blocks: blocks)
        let maker = PdfMaker()
        pdfMaker = maker
        maker.make(html: html,
                   fileName: "\(exportBaseName).pdf") {
            [weak self] url in
            self?.pdfMaker = nil
            if url != nil {
                DiagLog.shared.log(.info,
                    "单篇导出 pdf ok id="
                    + "\(self?.item.id ?? "?")")
            } else {
                DiagLog.shared.log(.error,
                    "单篇导出 pdf 失败")
            }
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
        case "musicCard", "link-card":
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
        case "musicCard", "link-card":
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

/// 块拖拽拾起的 UIKit 手势安装器（滚动卡死根治）：
/// 0 尺寸寄生视图，入树后把 UILongPressGestureRecognizer
/// 挂到祖先 UIScrollView 上，delegate 按本行在滚动
/// 内容坐标系中的 frame 过滤触摸（作用域精确到行）。
/// 仲裁核心：长按 require(toFail:) 于 ScrollView 的
/// pan——手指一动 pan 先胜、长按直接失败、滚动零延
/// 迟接管；手指静止满 480ms 时 pan 未识别（无位
/// 移），长按才成功拾起。SwiftUI 的 LongPress.
/// sequenced(Drag) 挂行上时 pan 必须等它裁决，慢
/// 划/停顿划被俘获后整段触摸归拖拽、页面冻住，即
/// 用户实报「能滚一下又卡死」的形态。识别器不取消
/// 下层触摸，点按落焦与按钮照常穿透。
struct DragPickupInstaller: UIViewRepresentable {
    var enabled: Bool
    var onPickup: () -> Void
    var onDrag: (CGFloat) -> Void
    var onDrop: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        let lp = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:)))
        lp.minimumPressDuration = 0.48
        lp.allowableMovement = 10
        lp.cancelsTouchesInView = false
        lp.delegate = context.coordinator
        context.coordinator.recognizer = lp
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attachIfNeeded(from: v)
    }

    static func dismantleUIView(_ v: UIView,
                                coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject,
        UIGestureRecognizerDelegate {
        var parent: DragPickupInstaller
        var recognizer: UILongPressGestureRecognizer?
        private weak var scrollView: UIScrollView?
        private weak var hostView: UIView?
        private var startY: CGFloat = 0
        private var picked = false

        init(_ p: DragPickupInstaller) { parent = p }

        /// 找祖先 UIScrollView 并把识别器挂上去（已挂
        /// 同一个则跳过）；require(toFail: pan) 在此建
        /// 立——滚动优先于拾起的仲裁核心。
        func attachIfNeeded(from view: UIView) {
            hostView = view
            var cur: UIView? = view.superview
            var sv: UIScrollView?
            while let c = cur {
                if let s = c as? UIScrollView { sv = s; break }
                cur = c.superview
            }
            guard let sv else { return }
            if sv === scrollView { return }
            detach()
            scrollView = sv
            if let lp = recognizer {
                lp.require(toFail: sv.panGestureRecognizer)
                sv.addGestureRecognizer(lp)
            }
        }

        func detach() {
            if let lp = recognizer, let sv = scrollView {
                sv.removeGestureRecognizer(lp)
            }
            scrollView = nil
        }

        /// 只接收落在本行 frame 内的触摸：寄生视图撑
        /// 满行背景，其 bounds 换算到滚动内容坐标即
        /// 行 frame（滚动时内容坐标不变、实时换算）。
        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard parent.enabled,
                  let hv = hostView, let sv = scrollView
            else { return false }
            let rowFrame = hv.convert(hv.bounds, to: sv)
            return rowFrame.contains(
                touch.location(in: sv))
        }

        @objc func handle(_ r: UILongPressGestureRecognizer) {
            switch r.state {
            case .began:
                picked = true
                startY = r.location(in: nil).y
                parent.onPickup()
            case .changed:
                if picked {
                    parent.onDrag(
                        r.location(in: nil).y - startY)
                }
            case .ended:
                if picked { parent.onDrop() }
                picked = false
            case .cancelled, .failed:
                if picked { parent.onCancel() }
                picked = false
            default: break
            }
        }
    }
}

/// 卡编辑态的选图/输链接面打包（图库加图多选、图库
/// 换图单选、音乐卡 URL 编辑）：独立 modifier 承载，
/// 避免 EditorView body 修饰链类型检查超时。
struct CardEditSheets: ViewModifier {
    @ObservedObject var editor: EditorModel
    @ObservedObject var ui: EditorView.EditorUI

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { editor.showGalleryAddPicker },
                set: { editor.showGalleryAddPicker = $0 })) {
                MultiPhotoPicker { datas in
                    guard let bid = editor.galleryPickBlockId
                    else { return }
                    var fids: [String] = []
                    for data in datas {
                        let fid = "att-" + UUID().uuidString
                            .prefix(12).lowercased()
                        guard editor.library.putAttachment(
                            fid, data) else {
                            DiagLog.shared.log(.error,
                                "图库加图未成（附件写入失败）"
                                + "fid=\(fid)")
                            continue
                        }
                        fids.append(fid)
                    }
                    editor.applyGalleryAdd(blockId: bid,
                                           fileIds: fids)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { editor.showGalleryReplacePicker },
                set: { editor.showGalleryReplacePicker = $0 })) {
                PhotoPicker { data in
                    guard let bid = editor.galleryPickBlockId,
                          let ix = editor.galleryReplaceIndex
                    else { return }
                    let fid = "att-" + UUID().uuidString
                        .prefix(12).lowercased()
                    guard editor.library.putAttachment(
                        fid, data) else {
                        DiagLog.shared.log(.error,
                            "图库换图未生效（附件写入失败）"
                            + "fid=\(fid)")
                        return
                    }
                    editor.applyGalleryReplace(blockId: bid,
                                               index: ix,
                                               fileId: fid)
                }
                .ignoresSafeArea()
            }
            .alert("编辑链接", isPresented: Binding(
                get: { ui.musicEditBlockId != nil },
                set: { if !$0 { ui.musicEditBlockId = nil } })) {
                TextField("https://…", text: Binding(
                    get: { ui.musicURLDraft },
                    set: { ui.musicURLDraft = $0 }))
                Button("取消", role: .cancel) {}
                Button("保存") {
                    guard let bid = ui.musicEditBlockId,
                          let b = editor.blocks.first(
                            where: { $0.id == bid })
                    else { return }
                    let url = ui.musicURLDraft
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { return }
                    editor.pushHistory()
                    var n = b.node
                    n["url"] = url
                    n["meta"] = nil
                    n["status"] = "loading"
                    b.node = n
                    b.nodeVersion += 1
                    editor.scheduleSave()
                    editor.startResolveCard(b)
                    DiagLog.shared.log(.info,
                        "EDIT music url set \(bid)")
                }
            }
    }
}

/// 条件长按手势：只给卡片类块挂（长按出贴卡浮层
/// 菜单）；非卡类不挂，避免多一层手势干扰拾起/选择。
struct CardMenuGesture: ViewModifier {
    let active: Bool
    let action: () -> Void
    func body(content: Content) -> some View {
        if active {
            content.onLongPressGesture(
                minimumDuration: 0.48, perform: action)
        } else {
            content
        }
    }
}

struct BlockRow: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var block: BlockState

    /// 卡片类块（Web CARD_MENU_TYPES）：长按走贴卡
    /// 浮层菜单（EditorView 呈现层），不走系统
    /// contextMenu、不参与拖拽拾起（菜单优先，iOS
    /// 原生惯例；Web 的拾起出菜单与原生仲裁形态不同，
    /// 按行为等价取菜单路）。
    private var isCardType: Bool {
        EditorModel.cardMenuTypes.contains(block.type)
    }

    // 行面口径（Web editor.css）：常态无底无框；引用 =
    // 淡底+3px 蓝竖条+10 圆角，提示 = 语义淡底+12 圆角；
    // 块操作收进长按菜单（与原版一致，常驻按钮已撤）。
    var body: some View {
        if isCardType {
            rowMain
        } else {
            rowMain.contextMenu {
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
    }

    private var rowMain: some View {
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
                        if editor.cardEditBlockId == block.id {
                            // 卡编辑态点图 = 换图（Web
                            // cardPick kind=set 同口径）。
                            editor.replaceImageBlockId = block.id
                            editor.showReplacePicker = true
                        } else if block.fileId == nil
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
                // Web 口径：图库左右内缩 36（与图片块同）。
                GalleryBlockView(block: block, editor: editor)
                    .padding(.horizontal, 36)
            } else if block.type == "musicCard",
                      (block.node["status"] as? String)
                        == "input" {
                MusicPillView(editor: editor, block: block)
            } else if block.type == "musicCard"
                        || block.type == "link-card" {
                CardBlockView(block: block,
                              editor: editor)
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
            } else if block.type == "paragraph",
                      editor.editingBlockId != block.id,
                      editor.focusBlockId != block.id,
                      editor.mdKind(for: block) != "none" {
                // MD 源段落失焦预览（Web 口径）：未编辑时
                // 渲染解析树，点按回源码、光标落末尾。
                MdPreviewView(editor: editor, block: block)
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
            } else if block.type == "embedCard" {
                // embedCard 无专门卡渲染（原版只读渲染
                // 与 Rust Web 均为兜底段落）：显示
                // children 文本拼接，不露开发文案。
                Text(block.text)
                    .font(.system(size: 14))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(.vertical, 2)
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
            // UITextView recalc 回报）。块顶位置一并回报
            // （斜杠面板锚定；非 Published 不触发重演算）。
            Color.clear
                .onAppear {
                    if !block.isText {
                        block.height = geo.size.height
                    }
                    block.frameMinY = geo.frame(
                        in: .named("editorScroll")).minY
                }
                .onChange(of: geo.size.height) { h in
                    if !block.isText { block.height = h }
                }
                .onChange(of: geo.frame(
                    in: .named("editorScroll")).minY) { y in
                    block.frameMinY = y
                }
        })
        .background(DragPickupInstaller(
            enabled: dragAllowed,
            onPickup: {
                if editor.draggingId == nil {
                    editor.draggingId = block.id
                    DiagLog.shared.log(.info,
                        "DRAG pickup id=\(block.id) "
                        + "type=\(block.type)")
                }
            },
            onDrag: { dy in
                if editor.draggingId == block.id {
                    editor.dragDy = dy
                }
            },
            onDrop: {
                if editor.draggingId == block.id {
                    editor.commitDrag()
                }
            },
            onCancel: {
                if editor.draggingId == block.id {
                    editor.draggingId = nil
                    editor.dragDy = 0
                }
            }))
        .scaleEffect(editor.draggingId == block.id ? 0.97 : 1)
        .offset(y: editor.draggingId == block.id
            ? editor.dragDy : 0)
        .zIndex(editor.draggingId == block.id ? 1 : 0)
        .onDisappear {
            // 手势被系统取消时 onEnded 不触发：行卸载即
            // 无条件复位拖拽态，防 draggingId 残留锁死
            // 全篇拾起（三线审计定案）。
            if editor.draggingId == block.id {
                editor.draggingId = nil
                editor.dragDy = 0
            }
        }
        .modifier(CardMenuGesture(active: isCardType) {
            editor.cardMenuBlockId = block.id
            DiagLog.shared.log(.info,
                "EDIT card menu open \(block.id) "
                + "type=\(block.type)")
        })
        .overlay {
            // 卡编辑态描边（Web .card-editing：2px
            // accent、offset 3；图文 radius 22、余 32）。
            if editor.cardEditBlockId == block.id {
                RoundedRectangle(cornerRadius:
                    block.type == "imgTextCard"
                        || block.type == "imageTextRow"
                        ? 22 : 32)
                    .stroke(T.accent, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
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

    /// 编辑中的文本块长按 = 文本选择，永不拾起（Web 口径）；
    /// 卡片类块长按走浮层菜单，同样不拾起。
    private var dragAllowed: Bool {
        if isCardType { return false }
        return !(block.isText && editor.editingBlockId == block.id)
    }

}

struct EditorView: View {
    @ObservedObject var editor: EditorModel
    var onOpenMemo: ((MemoItem) -> Void)? = nil
    @StateObject private var ui = EditorUI()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var linkFieldFocused: Bool

    final class EditorUI: ObservableObject {
        @Published var showPhotoPicker = false
        @Published var showFilePicker = false
        @Published var showMenu = false
        @Published var showExport = false
        @Published var showBgSheet = false
        /// 背景底表出场态（Web .sheet-wrap.is-closing）：
        /// 关闭先播 220ms 出场（opacity→0 + 下移 20），
        /// 卸载时点才应用待生效颜色（原版 closeWithAnim
        /// 口径）；gen 防快速重入时旧回调误卸载新开的表。
        @Published var bgClosing = false
        var bgGen = 0
        var bgPendingApply = false
        var bgPendingColor: String? = nil
        /// 底安全区（body 的 GeometryReader 喂入，背景
        /// 底表悬浮间距与卡内底距按 Web 口径含 safe）。
        var safeBottom: CGFloat = 0

        /// 发起背景底表关闭：只置出场态，实际卸载与
        /// 颜色生效由 EditorView 的 onChange 编排。
        func beginBgClose(apply: Bool, color: String?) {
            if bgClosing { return }
            bgGen += 1
            bgPendingApply = apply
            bgPendingColor = color
            bgClosing = true
        }
        @Published var showAttachChoice = false
        /// 音乐卡「编辑」即时动作（Web 口径：输 URL 重
        /// 解析，无持续编辑态）：EditorView 层 alert 承载。
        @Published var musicEditBlockId: String?
        @Published var musicURLDraft = ""
        @Published var titleDraft = ""
        @Published var linkError = false
        var viewW: CGFloat = 0
        var viewH: CGFloat = 0
        /// 标题编辑会话起点快照（Esc 还原源）。
        @Published var titleBase = ""
        @Published var shareURL: URL?
        @Published var linkDraft = ""
        @Published var backlinks: [MemoItem] = []
        @Published var showAvatarChoice = false
        @Published var showAvatarPicker = false
        /// 宽屏判定（Web 媒体查询口径）：(宽≥768 且 高≥600)
        /// 或 宽≥1100。由 EditorView 的 GeometryReader 喂入。
        @Published var wide = false
        /// 页眉实际可用宽（标题胶囊动态量宽用，替代写死
        /// 屏幕宽口径；审计 B-2）。
        @Published var headerW: CGFloat = 0
    }

    // 编辑页口径（Web .detail/.editor-fab/.editor-title-dock）：
    // 悬浮玻璃圆钮（左返回/右更多，46px，top=安全区+7）+
    // 居中标题坞（72 头像圆 + 66 高标题胶囊，标题 14/600
    // 居中、副行 10px 日期·字数）；正文上距 155 口径。
    var body: some View {
        ZStack(alignment: .top) {
            contentArea
                .onTapGesture {
                    // 卡编辑态：点按任意处先退出（Web
                    // 点卡外退出编辑态的近似——容器级
                    // tap 与子点按共存触发，编辑卡图区
                    // 的换图动作已先行置位、不受影响）。
                    if editor.cardEditBlockId != nil {
                        editor.exitCardEdit(via: "tap")
                    }
                }
            EditorHeaderView(editor: editor, ui: ui,
                             scroll: editor.scrollState)
            if editor.slashBlockId != nil {
                // 斜杠面板锚定触发块（Web 口径）：块下 8px、
                // 放不下上翻；宽 220–360、左对齐正文列。
                GeometryReader { geo in
                    let blk = editor.blocks.first {
                        $0.id == (editor.linkFormBlockId
                            ?? editor.slashBlockId)
                    }
                    let top = (blk?.frameMinY ?? 160)
                        + (editor.twoPaneIndependent
                            ? 168 : 0)
                    let bh = blk?.height ?? 24
                    let panelW = min(360,
                                     geo.size.width - 32)
                    let panelH: CGFloat = 320
                    let below = top + bh + 8
                    let centerY = below + panelH
                        > geo.size.height - 12
                        ? max(panelH / 2 + 8,
                              top - 8 - panelH / 2)
                        : below + panelH / 2
                    Group {
                        if editor.linkFormBlockId != nil {
                            linkFormPanel
                        } else {
                            slashPanel
                        }
                    }
                    .frame(width: panelW)
                    .position(
                        x: 16 + panelW / 2,
                        y: centerY)
                }
                .transition(.opacity)
            }
            if editor.cardMenuBlockId != nil {
                cardMenuLayer
                    .transition(.opacity)
            }
            // ••• 菜单进出场（M13）：右上锚点 scale 0.92 +
            // 上移 10 + 淡入，220ms 弹簧；常驻挂载、隐藏
            // 时禁命中（Web 关闭播满再卸载的等价处理）。
            menuPanel
                .opacity(ui.showMenu ? 1 : 0)
                .scaleEffect(ui.showMenu ? 1 : 0.92,
                             anchor: .topTrailing)
                .offset(y: ui.showMenu ? 0 : -10)
                .allowsHitTesting(ui.showMenu)
                .animation(.spring(response: 0.22,
                                   dampingFraction: 0.82),
                           value: ui.showMenu)
            // 背景色浮动底表（Web .sheet-wrap + .bg-sheet
            // 全形态）：悬浮卡（左右 14、底 = 安全区+14、
            // 全角 radius 28、上限 600 居中）+ 进出场
            // （opacity 200ms / 下移 20px + 250ms 弹簧
            // timingCurve(0.34,1.56,0.64,1)，出场 220ms
            // 后卸载且颜色在卸载时才生效）。不用系统
            // sheet（detent 几何两度翻车）、不用贴底全
            // 宽（那是上版自创形态、且丢了动画）。
            if ui.showBgSheet {
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ui.beginBgClose(
                                    apply: false, color: nil)
                            }
                        bgSheet
                            .frame(maxWidth: 600)
                            .padding(.horizontal, 14)
                            .padding(.bottom,
                                     geo.safeAreaInsets.bottom
                                        + 14)
                            .offset(y: ui.bgClosing ? 20 : 0)
                            .opacity(ui.bgClosing ? 0 : 1)
                            .animation(.timingCurve(
                                0.34, 1.56, 0.64, 1,
                                duration: 0.25),
                                       value: ui.bgClosing)
                    }
                }
                .onAppear { ui.bgClosing = false }
            }
        }
        .onChange(of: ui.bgClosing) { closing in
            // 出场编排：220ms 后（gen 仍有效且仍在出场
            // 态）才应用待生效颜色并卸载底表。
            guard closing else { return }
            let gen = ui.bgGen
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.22) {
                guard ui.bgGen == gen, ui.bgClosing else {
                    return
                }
                if ui.bgPendingApply {
                    editor.setBgColor(ui.bgPendingColor)
                }
                ui.showBgSheet = false
                ui.bgClosing = false
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    syncWide(geo.size)
                    ui.safeBottom =
                        geo.safeAreaInsets.bottom
                }
                .onChange(of: geo.size) { newSize in
                    syncWide(newSize)
                }
                .onChange(of: geo.safeAreaInsets.bottom) {
                    sb in
                    ui.safeBottom = sb
                }
        })
        .toolbar {
            // 键盘收起的确定性出口（系统口径）：滚动交
            // 互收起之外，键盘上方工具栏再给一枚「完成」。
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder
                            .resignFirstResponder),
                        to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            DiagLog.shared.log(.info,
                "SCROLL open blocks=\(editor.blocks.count) "
                + "types=\(editor.blocks.map { $0.type }.joined(separator: ","))")
            ui.titleDraft = editor.title
            ui.backlinks = editor.library.backlinks(
                forTitle: editor.title,
                excludeId: editor.item.id)
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
        .onChange(of: editor.linkFormBlockId) { id in
            if id != nil {
                ui.linkDraft = "https://"
                ui.linkError = false
            }
        }
        .onDisappear {
            let estH = editor.blocks.reduce(0) {
                $0 + $1.height
            } + CGFloat(max(0, editor.blocks.count - 1)) * 6
                + 168 + 220 + 40
            DiagLog.shared.log(.info,
                "SCROLL close maxY=\(Int(editor.scrollState.maxScrollY)) "
                + "estContentH=\(Int(estH)) "
                + "viewH=\(Int(ui.viewH)) "
                + "heights=\(editor.blocks.map { Int($0.height) })")
            editor.saveNow()
        }
        .animation(.easeOut(duration: 0.18),
                   value: editor.slashBlockId ?? "")
        .confirmationDialog("头像",
            isPresented: Binding(
                get: { ui.showAvatarChoice },
                set: { ui.showAvatarChoice = $0 }),
            titleVisibility: .visible) {
            Button("更换头像") { ui.showAvatarPicker = true }
            Button("恢复默认头像", role: .destructive) {
                editor.library.setAvatar(
                    for: editor.item.id, dataURL: nil)
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { ui.showAvatarPicker },
            set: { ui.showAvatarPicker = $0 })) {
            PhotoPicker { data in
                // 统一转 JPEG data URL 存 avatars 通道
                // （与 Web 文件直读形同为 data URL）。
                if let img = UIImage(data: data),
                   let jpg = img.jpegData(
                    compressionQuality: 0.85) {
                    editor.library.setAvatar(
                        for: editor.item.id,
                        dataURL: "data:image/jpeg;base64,"
                            + jpg.base64EncodedString())
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { ui.showPhotoPicker },
            set: { ui.showPhotoPicker = $0 })) {
            PhotoPicker { data in
                let fid = "att-" + UUID().uuidString
                    .prefix(12).lowercased()
                guard editor.library.putAttachment(
                    fid, data) else {
                    DiagLog.shared.log(.error,
                        "选图未成块（附件写入失败）fid=\(fid)")
                    return
                }
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
                guard editor.library.putAttachment(
                    fid, data) else {
                    DiagLog.shared.log(.error,
                        "换图未生效（附件写入失败）fid=\(fid)")
                    return
                }
                editor.replaceImage(fileId: fid)
            }
            .ignoresSafeArea()
        }
        .modifier(CardEditSheets(editor: editor, ui: ui))
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
                    guard editor.library.putAttachment(
                        fid, data) else {
                        DiagLog.shared.log(.error,
                            "附件未成块（写入失败）fid=\(fid)")
                        return
                    }
                    editor.addAttachmentBlock(
                        fileId: fid,
                        name: url.lastPathComponent,
                        size: data.count)
                }
            }
        }
    }

    // 斜杠面板（Web 口径）：空查询 = 最近使用 + 基础块 +
    // 媒体块分组；有查询 = 拼音/关键词/中文过滤平铺；
    // 无匹配出提示行。点选即执行（Editor 作用域）。
    /// 卡片浮层菜单呈现层（Web CardMenuLayer 口径）：
    /// 贴卡下 8px、放不下上翻、宽 216、高按项数（有
    /// 编辑 114 / 无 64）；点遮罩关闭（并退出可能残
    /// 留的卡编辑态，Web 口径）。独立成段避免 EditorView
    /// body 类型检查超时。
    private var cardMenuLayer: some View {
        GeometryReader { geo in
            let menuBid = editor.cardMenuBlockId ?? ""
            let blk = editor.blocks.first { $0.id == menuBid }
            let top = (blk?.frameMinY ?? 160)
                + (editor.twoPaneIndependent ? 168 : 0)
            let bh = blk?.height ?? 24
            let hasEdit = blk.map {
                EditorModel.editCardTypes.contains($0.type)
            } ?? false
            let panelH: CGFloat = hasEdit ? 114 : 64
            let below = top + bh + 8
            let panelTop = below + panelH
                > geo.size.height - 12
                ? max(12, top - 8 - panelH)
                : below
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    editor.cardMenuBlockId = nil
                    editor.exitCardEdit(via: "scrim")
                }
            cardMenuPanel(block: blk, hasEdit: hasEdit)
                .frame(width: 216)
                .position(x: 16 + 108,
                          y: panelTop + panelH / 2)
        }
    }

    /// 卡片浮层菜单本体（Web .card-menu-panel：项与
    /// ••• 菜单同 menuItem 度量，浮层档、radius 22）。
    private func cardMenuPanel(block: BlockState?,
                               hasEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasEdit, let block {
                menuItem(icon: "pencil", title: "编辑") {
                    editor.cardMenuBlockId = nil
                    if block.type == "musicCard" {
                        // 音乐卡编辑 = 即时输 URL 动作
                        // （Web 口径，无持续编辑态）。
                        ui.musicURLDraft =
                            block.node["url"] as? String ?? ""
                        ui.musicEditBlockId = block.id
                    } else {
                        editor.cardEditBlockId = block.id
                        DiagLog.shared.log(.info,
                            "EDIT card edit enter \(block.id) "
                            + "(\(block.type))")
                    }
                }
            }
            if let block {
                menuItem(icon: "trash", title: "删除此块",
                         danger: true) {
                    editor.cardMenuBlockId = nil
                    if editor.cardEditBlockId == block.id {
                        editor.cardEditBlockId = nil
                    }
                    editor.deleteBlock(block)
                    DiagLog.shared.log(.info,
                        "EDIT card menu delete \(block.id)")
                }
            }
        }
        .padding(7)
        .overlayCard(radius: 22)
    }

    private var slashPanel: some View {
        let q = editor.slashQuery
        let filtered = SlashCmds.filtered(q)
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if q.isEmpty {
                        let recents = SlashCmds.recents()
                        let recentActs = Set(
                            recents.map(\.act))
                        if !recents.isEmpty {
                            slashGroupHeader("最近使用",
                                             first: true)
                            ForEach(recents, id: \.act) {
                                slashRow($0, recent: true)
                            }
                        }
                        slashGroupHeader(
                            "基础块",
                            first: recents.isEmpty)
                        ForEach(SlashCmds.all.filter {
                            $0.group == 0
                                && !recentActs.contains(
                                    $0.act)
                        }, id: \.act) { slashRow($0) }
                        slashGroupHeader("媒体块",
                                         first: false)
                        ForEach(SlashCmds.all.filter {
                            $0.group == 1
                                && !recentActs.contains(
                                    $0.act)
                        }, id: \.act) { slashRow($0) }
                    } else if filtered.isEmpty {
                        slashEmptyState
                    } else {
                        ForEach(filtered, id: \.act) {
                            slashRow($0)
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(maxHeight: 320)
        .overlayCard(radius: 22)
    }

    /// 斜杠空态（Web .slash-empty-state）：居中搜索图标
    /// + 未找到匹配命令 + 拼音首字母 kbd 提示行。
    private var slashEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(
                    T.textSecondary.opacity(0.45))
            Text("未找到匹配命令")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
            HStack(spacing: 4) {
                Text("试试拼音首字母：")
                slashKbd("bt")
                Text("标题 ·")
                slashKbd("tp")
                Text("图片 ·")
                slashKbd("yykp")
                Text("音乐")
            }
            .font(.system(size: 12))
            .foregroundStyle(T.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func slashKbd(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(T.fillHover,
                        in: RoundedRectangle(
                            cornerRadius: 6))
    }

    private func slashGroupHeader(_ t: String,
                                  first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first {
                Rectangle()
                    .fill(T.glassBorder)
                    .frame(height: 0.5)
                    .padding(.vertical, 6)
            }
            Text(t)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    T.textSecondary.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.top, first ? 2 : 0)
                .padding(.bottom, 2)
        }
    }

    private func slashRow(_ cmd: SlashCmd,
                          recent: Bool = false) -> some View {
        Button {
            editor.applySlash(cmd.act)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cmd.icon)
                    .font(.system(size: 19))
                    .foregroundStyle(T.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(cmd.title)
                            .font(.system(
                                size: 14,
                                weight: .semibold))
                            .foregroundStyle(T.textMain)
                        if recent {
                            Text("最近")
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    T.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    T.fillHover,
                                    in: RoundedRectangle(
                                        cornerRadius: 6))
                        }
                    }
                    Text(cmd.sub)
                        .font(.system(size: 12))
                        .foregroundStyle(T.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if !cmd.shortcut.isEmpty {
                    Text(cmd.shortcut)
                        .font(.system(size: 11,
                                      design: .monospaced))
                        .foregroundStyle(T.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            T.fillHover,
                            in: RoundedRectangle(
                                cornerRadius: 6))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: 14))
    }

    /// 链接表单（Web .slash-link-form 口径）：面板内原
    /// 地替换列表——标题、预填 https:// 的输入框、校验
    /// 失败才出现的错误行、右对齐双胶囊钮。
    private var linkFormPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("链接地址")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
            TextField("https://example.com",
                      text: Binding(
                        get: { ui.linkDraft },
                        set: { ui.linkDraft = $0
                               ui.linkError = false }))
                .font(.system(size: 14))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(T.fillSubtle,
                            in: RoundedRectangle(
                                cornerRadius: 10))
                .focused($linkFieldFocused)
                .onSubmit { submitLinkForm() }
            if ui.linkError {
                Text("请输入有效的 http 或 https 链接")
                    .font(.system(size: 12))
                    .foregroundStyle(T.danger)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("取消") {
                    // 回命令列表（Web 口径，与 Esc 同）。
                    editor.linkFormBlockId = nil
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(T.fillHover,
                            in: Capsule())
                Button("插入链接") { submitLinkForm() }
                    .font(.system(size: 14,
                                  weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(T.accent, in: Capsule())
            }
        }
        .padding(12)
        .overlayCard(radius: 22)
        .onAppear { linkFieldFocused = true }
    }

    private func submitLinkForm() {
        if editor.applyLink(url: ui.linkDraft) {
            ui.linkDraft = ""
            ui.linkError = false
        } else {
            ui.linkError = true
        }
    }

    // 页眉结构（根治）：单行 HStack = 返回钮 / 坞 / 更多
    // 钮，两侧等宽 Spacer 使坞居中、三者同顶线。旧
    // ZStack 叠层形态在真机上两钮不呈现（用户截图实
    // 证），弃用叠层、改流式同行布局，构造上不可能丢钮。
/// 编辑页页眉（独立视图结构体）：滚动偏移的观察隔离
/// 在此——scrollY 每帧变化只重演算页眉子树，不再连带
/// 整个块列表（长笔记滚动卡死/掉帧的根治；审计外
/// 用户实报「有些笔记滚动不了」）。
struct EditorHeaderView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var ui: EditorView.EditorUI
    @ObservedObject var scroll: EditorScrollState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            headerOverlay
            // Esc 收口的键盘入口（隐形钮，仅硬件键盘）。
            Button("") { handleEscape() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        // 紧凑态切换（Web 口径）：0.25s 缓动。动画值在
        // 本视图内读 scrollY，滚动重演算不外溢。
        .animation(.easeInOut(duration: 0.25),
                   value: scroll.scrollY > 30)
    }

private var headerOverlay: some View {
    HStack(alignment: .top, spacing: 0) {
        Button {
            commitTitle()
            editor.saveNow()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(T.textMain)
                .frame(width: 46, height: 46)
                .glassControl(radius: 999)
        }
        Spacer(minLength: 8)
        if scroll.scrollY > 30 {
            // 紧凑态（Web .editor-title-dock.scrolled
            // 真值）：同一坞转横排——头像 72 不变、胶囊
            // 66 不变、gap 8、仅 meta 行 display:none。
            // 旧自创小胶囊（头像 32 + 高 46）与 Web 两
            // 模两样，整套弃用、两态共用同一坞组件。
            HStack(spacing: 8) {
                avatarButton
                titleCapsule(compact: true)
            }
        } else {
            VStack(spacing: 6) {
                avatarButton
                titleCapsule(compact: false)
            }
        }
        Spacer(minLength: 8)
        Button {
            ui.showMenu.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(T.textMain)
                .frame(width: 46, height: 46)
                .glassControl(radius: 999)
        }
    }
    .padding(.horizontal, 16)
    .padding(.top, 7)
    .background {
        GeometryReader { geo in
            Color.clear
                .onAppear { ui.headerW = geo.size.width }
                .onChange(of: geo.size.width) { w in
                    ui.headerW = w
                }
        }
    }
}

/// 标题提交（Web 口径）：仅失焦/回车提交，编辑中不落
/// 盘；非编辑态超 10 字截断显示。
/// Esc 收口（E5，Web 口径）：硬件键盘 Esc 按浮层
/// 优先级关闭——链接表单 > 斜杠面板 > 背景色底表 >
/// 菜单/导出面板 > 标题编辑（还原草稿并失焦，标题
/// Esc 还原为 Web 标题控制器口径）。
private func handleEscape() {
    if editor.linkFormBlockId != nil {
        editor.linkFormBlockId = nil
        return
    }
    if editor.slashBlockId != nil {
        editor.slashBlockId = nil
        return
    }
    if ui.showBgSheet {
        ui.beginBgClose(apply: false, color: nil)
        return
    }
    if ui.showMenu || ui.showExport {
        ui.showMenu = false
        ui.showExport = false
        return
    }
    if titleFocused {
        ui.titleDraft = ui.titleBase
        titleFocused = false
    }
}

private func commitTitle() {
    // Web 口径：提交时 trim、空回退「无标题」（落盘
    // 值即回退值，与 Web 数据口径一致；审计 B-1）。
    let trimmed = ui.titleDraft.trimmingCharacters(
        in: .whitespacesAndNewlines)
    let final = trimmed.isEmpty ? "无标题" : trimmed
    if final != editor.title {
        editor.pushHistory()
        editor.title = final
        editor.scheduleSave()
        ui.backlinks = editor.library.backlinks(
            forTitle: editor.title,
            excludeId: editor.item.id)
    }
    if ui.titleDraft != final {
        ui.titleDraft = final
    }
}

/// 标题坞头像钮（两态共用，Web .editor-avatar-button
/// 口径）：72 圆、本篇头像、点按换图——有自定义头像
/// 时先出选择、无则直接选图。
private var avatarButton: some View {
    Button {
        if editor.library.avatarDataURL(
            for: editor.item.id) != nil {
            ui.showAvatarChoice = true
        } else {
            ui.showAvatarPicker = true
        }
    } label: {
        AvatarView(size: 72,
                   memoId: editor.item.id,
                   library: editor.library)
    }
    .buttonStyle(.plain)
}

private func titleCapsule(compact: Bool) -> some View {
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
                .onSubmit {
                    // Enter 提交并辞焦（审计 B-3）。
                    commitTitle()
                    titleFocused = false
                }
                .onChange(of: titleFocused) { f in
                    if f {
                        // 聚焦快照：Esc 还原以会话起点
                        // 为准（审计 B-3）。
                        ui.titleBase = editor.title
                    } else {
                        commitTitle()
                    }
                }
        } else {
            Text(String(ui.titleDraft.prefix(10)) + "…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
                .onTapGesture { titleFocused = true }
        }
        // meta 行：紧凑态整行不渲染（Web .scrolled 下
        // display:none 的等价），不留占位、不外漏。
        if !compact {
            Text(metaLine)
                .font(.system(size: 10))
                .foregroundStyle(T.textSecondary)
                .lineLimit(1)
        }
    }
    .padding(.horizontal, 20)
    .frame(width: capsuleWidth, height: 66)
    .glassControl(radius: 33)
    .animation(.easeInOut(duration: 0.2),
               value: capsuleWidth)
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
    // 被截断成「2026年1...」，真机截图实证）；紧凑
    // 态 meta 不渲染、不计宽（Web display:none）。
    let compact = scroll.scrollY > 30
    let metaFont = UIFont.systemFont(ofSize: 10)
    let metaW = compact ? 0 : metaLine.size(
        withAttributes: [.font: metaFont]).width
    // 最大宽按页眉实测可用宽动态算（两侧钮各 46 +
    // 间隔 16），不再写死屏幕宽——iPad 双栏/横屏/
    // 分屏下同样成立（审计 B-2）。紧凑态再扣坞内
    // 头像 72 + 横排 gap 8。
    let chrome: CGFloat = compact ? 80 : 0
    let avail = ui.headerW > 0
        ? ui.headerW - 46 - 46 - 16 - chrome : 240
    let maxW = max(avail, 66)
    return min(max(max(titleW, metaW) + 40, 66), maxW)
}

/// meta（Web 口径）：相对更新时间 · 正文字数。
private var metaLine: String {
    "\(editor.item.ago) · 共 \(editor.wordCount) 字"
}

}

    /// 背景色底表（Web BgSheet 口径）：8 色点 + 移除行。
    private var bgSheet: some View {
        // Web .bg-sheet 全度量：padding 20（底 = 20 +
        // 安全区）、head 居中（标题 20/700 tracking
        // -0.3、副 13 主色 70%、间距 4、head 下 16）、
        // 网格 gap 12、色点 44（选中 = 2px accent 边
        // + 20 号对勾）、移除区顶发丝线 + 居中两行
        // （图标 20 与 15/650 同行、注 11 次级色居其
        // 下）。容器形态（悬浮卡 + 进出场动画）在呈现
        // 段，见 body 的 bgSheet 呈现处。
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                Text("背景色")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(T.textMain)
                Text("为当前笔记设置底色")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        T.textMain.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible()), count: 4),
                      spacing: 12) {
                ForEach(Self.bgColors, id: \.self) { hex in
                    Button {
                        ui.beginBgClose(
                            apply: true, color: hex)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(T.colorOf(hex))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(
                                    editor.bgColor == hex
                                        ? T.accent
                                        : T.dotBorder,
                                    lineWidth:
                                        editor.bgColor == hex
                                            ? 2 : 0.5))
                            if editor.bgColor == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(
                                        size: 20,
                                        weight: .semibold))
                                    .foregroundStyle(T.accent)
                            }
                        }
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
            .padding(.bottom, 16)
            if editor.bgColor != nil {
                Rectangle()
                    .fill(T.borderSoft)
                    .frame(height: 0.5)
                Button(role: .destructive) {
                    ui.beginBgClose(
                        apply: true, color: nil)
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                            Text("移除背景")
                                .font(.system(
                                    size: 15,
                                    weight: .semibold))
                                .tracking(-0.1)
                        }
                        Text("（恢复默认背景）")
                            .font(.system(size: 11))
                            .foregroundStyle(T.textSecondary)
                    }
                    .foregroundStyle(T.dangerBright)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle(radius: 16))
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20 + ui.safeBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.overlayBg)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28)
            .stroke(T.overlayBorder, lineWidth: 0.5))
    }

    static let bgColors = ["#eaeef2", "#e8e0d4", "#d4e8d0",
                           "#d0e0e8", "#e8d0d4", "#fff3e0",
                           "#e8e0f0", "#f0e8d0"]

    // ••• 面板（Web .editor-menu-panel 度量：宽 246、radius
    // 22、浮层 overlay 档、行高 50、图标 accent）。条目 =
    // Web 六项口径、无分隔线（双栏开关仅宽屏显示，
    // iPhone 竖屏同 Web 的 display:none 不呈现；删除
    // 备忘项与分隔线已按用户 2026-11-26 裁定移除）。
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
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    if ui.wide {
                        twoPaneRow
                    }
                    menuItem(icon: "arrow.uturn.backward",
                             title: "撤销",
                             sub: "快捷键→ Cmd+Z / 三指左滑",
                             dimmed: !editor.canUndo) {
                        editor.undo()
                        ui.showMenu = false
                    }
                    menuItem(icon: "arrow.uturn.forward",
                             title: "重做",
                             sub: "快捷键→ Cmd+Shift+Z / 三指右滑",
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
                        // 进场从出场态起播（Web sheet-wrap
                        // 首帧 is-closing 的等价处理）。
                        ui.bgClosing = true
                        ui.showBgSheet = true
                    }
                }
                .padding(7)
                .frame(width: 246)
                .overlayCard(radius: 22)
                .padding(.top, 59)
                .padding(.trailing, 16)
                .transition(.opacity)
            }
        }
        // 菜单 ↔ 导出面板切换（M14）：同浮层淡入切换。
        .animation(.easeInOut(duration: 0.18),
                   value: ui.showExport)
    }

    /// 导出面板（Web 口径）：返回钮 + 三格式行 + 尾注。
    private var exportPanel: some View {
        VStack(spacing: 0) {
            // 头（Web .export-head 口径）：min-height 46、
            // 返回钮 46×46 圆形玻璃钮、标题 15/650 居中
            // （右侧等宽占位补偿）、下边线 0.5。
            HStack(spacing: 0) {
                Button {
                    ui.showExport = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
                }
                Text("导出笔记")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 46, height: 46)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 5)
            .frame(minHeight: 46)
            .overlay(alignment: .bottom) {
                Rectangle().fill(T.glassBorder)
                    .frame(height: 0.5)
            }
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
            // 尾注（Web 口径）：10px、顶边线、margin
            // 5/4/2；文案为 iOS 口径改写（Web 原文是浏
            // 览器打印口径、不适用，已登记改判）。
            Text("PDF 将生成文件，可通过分享存储或打印。")
                .font(.system(size: 10))
                .foregroundStyle(T.textSecondary)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 5)
                .padding(.bottom, 2)
                .overlay(alignment: .top) {
                    Rectangle().fill(T.glassBorder)
                        .frame(height: 0.5)
                }
        }
        .padding(7)
        .frame(width: 246)
        .overlayCard(radius: 22)
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
            // 行度量（Web panels.css 覆盖口径）：min-height
            // 54、padding 6/9、radius 14；徽章 34×34 透
            // 明无底、mono 11/700（PDF 小徽章 9）；label
            // 14/650、detail 11；chevron 19 次级色。
            HStack(spacing: 11) {
                Text(badge)
                    .font(.system(size: badge == "PDF"
                        ? 9 : 11, weight: .bold,
                        design: .monospaced))
                    .foregroundStyle(T.accent)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 14,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(T.textSecondary)
                }
                Spacer()
                Text("›")
                    .font(.system(size: 19))
                    .foregroundStyle(T.textSecondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: 14))
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
            .opacity(dimmed ? 0.3 : 1)
        }
        .buttonStyle(RowPressStyle())
        .disabled(dimmed)
    }

    /// 正文区（单列/双栏分流；从 body 拆出以免
    /// 编译器类型检查超时）。
    @ViewBuilder
    private var contentArea: some View {
        Group {
        if ui.wide {
            wideColumns
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                scrollProbe
                ForEach(editor.blocks) { block in
                    BlockRow(editor: editor, block: block)
                }
                focusHotZone
                backlinksSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 168)
            .padding(.bottom, 40)
        }
        .coordinateSpace(name: "editorScroll")
        .scrollDismissesKeyboard(.interactively)
        }
        }
        .background(T.memoBg(editor.bgColor))
    }

    // ── 编辑页共享段（单列/双栏共用） ──────────────
    /// 滚动偏移回报：基线 = 当前形态下首个有效探针
    /// 值（捕获制）。守卫一：形态（单列/flow/
    /// independent）切换即作废重捕，防跨形态污染；
    /// 守卫二：单列/flow 下探针真实静止值远大于 0，
    /// 首帧的偏好默认值 0 不作数、防竞态锁错基线。
    /// 写入独立 scrollState，发布只失效页眉子树。
    private func updateScrollY(_ y: CGFloat) {
        let s = editor.scrollState
        let mode = ui.wide
            ? (editor.twoPaneIndependent ? 2 : 1) : 0
        if s.baseMode != mode {
            s.baseMode = mode
            s.baseY = nil
        }
        if s.baseY == nil {
            if mode != 2 && y == 0 { return }
            s.baseY = y
            DiagLog.shared.log(.info,
                "SCROLL base mode=\(mode) y=\(Int(y))")
        }
        let v = max(0, (s.baseY ?? y) - y)
        // SCROLL 轨迹（诊断）：探针原始值变化 ≥24pt
        // 且距上行 ≥0.3s 才记一行——一次滚动尝试的完
        // 整轨迹（起点/行程/是否回弹）据此定案。
        if s.traceY.isNaN
            || (abs(y - s.traceY) >= 24
                && Date().timeIntervalSince(s.traceAt) >= 0.3) {
            s.traceY = y
            s.traceAt = Date()
            DiagLog.shared.log(.info,
                "SCROLL y=\(Int(y)) base=\(Int(s.baseY ?? -1)) "
                + "v=\(Int(v))")
        }
        if v > s.maxScrollY { s.maxScrollY = v }
        if abs(v - s.scrollY) > 0.5 {
            s.scrollY = v
        }
    }

    /// 滚动偏移探针（页眉紧凑态口径）：1pt 哨兵 +
    /// onGeometryChange 直读坐标。旧路（0 高视图挂
    /// 背景 GeometryReader 发 preference）在真机恒
    /// 报 0——0.9.9/0.9.13 两版日志合证：base 永不
    /// 捕获、轨迹全灭、maxY 恒定——观测链整体换代。
    private var scrollProbe: some View {
        Color.clear
            .frame(height: 1)
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.frame(in: .named("editorScroll")).minY
            } action: { y in
                updateScrollY(y)
            }
    }

    /// 正文下方空白点按落焦末个文本块末尾（Web 落焦
    /// 热区口径：header 以下整页）。
    private var focusHotZone: some View {
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

    /// 反向链接区（Web 口径）：引用本篇的备忘。
    @ViewBuilder
    private var backlinksSection: some View {
        if !ui.backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("反向链接")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.textSecondary)
                ForEach(ui.backlinks) { memo in
                    Button {
                        onOpenMemo?(memo)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 12))
                                .foregroundStyle(T.accent)
                            Text(memo.title.isEmpty
                                 ? "无标题" : memo.title)
                                .font(.system(size: 14))
                                .foregroundStyle(T.textMain)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCard(radius: 14)
                }
            }
            .padding(.top, 8)
        }
    }

    /// 一栏块列（双栏渲染单元）：extras = 栏尾挂落焦
    /// 热区/反向链接（挂在末栏，即文档尾所在栏）。
    @ViewBuilder
    private func blockColumn(_ range: Range<Int>,
                             extras: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(editor.blocks[range])) { block in
                BlockRow(editor: editor, block: block)
            }
            if extras {
                focusHotZone
                backlinksSection
            }
        }
    }

    /// 宽屏判定同步（Web 媒体查询口径）：进入宽屏且为
    /// 独立模式时触发一次性落锚。
    private func syncWide(_ size: CGSize) {
        ui.viewW = size.width
        ui.viewH = size.height
        let w = (size.width >= 768 && size.height >= 600)
            || size.width >= 1100
        editor.columnsActive = w
        if w != ui.wide {
            ui.wide = w
            if w { editor.captureAnchorIfNeeded() }
        }
    }

    /// 双栏呈现（Web 口径）：恒两物理栏；flow 整页滚动
    /// + 规范分界，independent 锚分界 + 栏内独立滚动
    /// （栏高 = 视口余高，不照抄 Web 的 187px 页头数）。
    @ViewBuilder
    private var wideColumns: some View {
        let b = min(editor.columnBoundaryIndex,
                    editor.blocks.count)
        let n = editor.blocks.count
        if editor.twoPaneIndependent {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        scrollProbe
                        blockColumn(0..<b, extras: b >= n)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 40)
                }
                .coordinateSpace(name: "editorScroll")
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: .infinity)
                Rectangle()
                    .fill(T.glassBorder)
                    .frame(width: 1)
                ScrollView {
                    blockColumn(b..<n, extras: b < n)
                        .padding(.leading, 16)
                        .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 168)
            .padding(.bottom, 8)
            .frame(maxWidth: 1440)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    scrollProbe
                    HStack(alignment: .top, spacing: 0) {
                        blockColumn(0..<b, extras: false)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                        Rectangle()
                            .fill(T.glassBorder)
                            .frame(width: 1)
                            .padding(.horizontal, 20)
                        blockColumn(b..<n, extras: false)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                    }
                    focusHotZone
                    backlinksSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 168)
                .padding(.bottom, 40)
                .frame(maxWidth: 1440)
            }
            .coordinateSpace(name: "editorScroll")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// 双栏开关行（Web 菜单首行口径）：仅宽屏呈现。
    private var twoPaneRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 17))
                .foregroundStyle(T.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("双栏独立滚动")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text("平板与 PC 可分别滚动两栏")
                    .font(.system(size: 11))
                    .foregroundStyle(T.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { editor.twoPaneIndependent },
                set: { _ in editor.toggleTwoPane() }))
                .labelsHidden()
                .tint(T.accent)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
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
        // Web 口径：两列网格（间距 4）、方瓦圆角 22、
        // 点任一图进图片页；空图库出占位瓦。
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 4),
            GridItem(.flexible(), spacing: 4),
        ], spacing: 4) {
            if items.isEmpty {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 22)
                        .fill(T.pressBg)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    T.textSecondary
                                        .opacity(0.4))
                        }
                        .onTapGesture {
                            // 编辑态点空瓦 = 加图（Web
                            // cardPick galleryAdd 同口径）。
                            if editor.cardEditBlockId
                                == block.id {
                                editor.galleryPickBlockId =
                                    block.id
                                editor.showGalleryAddPicker =
                                    true
                            }
                        }
                }
            }
            ForEach(Array(items.enumerated()),
                    id: \.offset) { ix, it in
                    GeometryReader { geo in
                        ItemImageView(
                            fileId: it["fileId"] as? String,
                            urlString: (it["url"] as? String)
                                ?? (it["src"] as? String),
                            library: editor.library)
                            .frame(width: geo.size.width,
                                   height: geo.size.height)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(
                        cornerRadius: 22))
                    .onTapGesture {
                        if editor.cardEditBlockId == block.id {
                            // 编辑态点图 = 换该张（Web
                            // cardPick galleryItem 同口径）。
                            editor.galleryPickBlockId = block.id
                            editor.galleryReplaceIndex = ix
                            editor.showGalleryReplacePicker =
                                true
                        } else {
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
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// 音乐输入胶囊（Web MusicInputPill 口径）：单行 URL
/// 入口，粘出/回车即解析。原生以 TextField 承载（提示
/// 作文案占位，不入数据——Web 的 hint 是胶囊初始内容、
/// 提交时剥除，等价处理）。
struct MusicPillView: View {
    @ObservedObject var editor: EditorModel
    var block: BlockState
    @StateObject private var state = PillState()
    @FocusState private var fieldFocus: Bool

    final class PillState: ObservableObject {
        @Published var text = ""
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(
                get: { state.text },
                set: { newValue in
                    state.text = newValue
                    // 粘入即检：含可提 URL 立即解析
                    // （Web 输入复检同口径）。
                    if EditorModel.extractCardURL(
                        newValue) != nil {
                        editor.submitMusicInput(
                            block, rawText: newValue)
                    }
                }),
                prompt: Text("粘贴音乐链接到这里，回车解析...")
                    .foregroundColor(T.textSecondary))
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($fieldFocus)
                .onSubmit {
                    editor.submitMusicInput(
                        block, rawText: state.text)
                }
                .onChange(of: editor.focusMusicId) { id in
                    // 斜杠 musicCard 落点：焦点落胶囊本身。
                    if id == block.id {
                        fieldFocus = true
                        editor.focusMusicId = nil
                    }
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassControl(radius: 999)
    }
}

/// MD 预览渲染（E16）：core 解析树（serde 外部标签
/// JSON）→ SwiftUI。行内段先转 runs 字典走 Marks 既有
/// 标记管线（粗/斜/下划线/删除/行内码/链接/高亮 == 包
/// 裹由 withRhythm 侧切）；公式暂以行内码样式源码呈现
/// （MathML 原生渲染为后续阶段，Web 走 core MathML）。
enum MdRender {
    static func runs(_ segs: [Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func push(_ text: String,
                  _ extra: [String: Any] = [:]) {
            guard !text.isEmpty else { return }
            var r: [String: Any] = ["text": text]
            for (k, v) in extra { r[k] = v }
            out.append(r)
        }
        func styled(_ v: Any, key: String) {
            for r in runs(v as? [Any] ?? []) {
                var r = r
                r[key] = true
                out.append(r)
            }
        }
        for s in segs {
            guard let d = s as? [String: Any],
                  let k = d.keys.first, let v = d[k]
            else { continue }
            switch k {
            case "Text": push(v as? String ?? "")
            case "Code": push(v as? String ?? "",
                              ["code": true])
            case "Strong": styled(v, key: "bold")
            case "Em": styled(v, key: "italic")
            case "Underline": styled(v, key: "underline")
            case "Del": push(v as? String ?? "",
                             ["strikethrough": true])
            case "Highlight":
                push("==" + (v as? String ?? "") + "==")
            case "Sup", "Sub": push(v as? String ?? "")
            case "Link":
                let lv = v as? [String: Any] ?? [:]
                let href = lv["href"] as? String ?? ""
                for r in runs(lv["children"] as? [Any]
                                ?? []) {
                    var r = r
                    r["_link"] = href
                    r["underline"] = true
                    out.append(r)
                }
            case "Wiki":
                let lv = v as? [String: Any] ?? [:]
                push(lv["label"] as? String ?? "",
                     ["_link": "wiki:"
                        + (lv["target"] as? String ?? "")])
            case "FootRef":
                let lv = v as? [String: Any] ?? [:]
                push("[\(lv["number"] as? Int ?? 0)]")
            case "Math":
                let lv = v as? [String: Any] ?? [:]
                push(lv["tex"] as? String ?? "",
                     ["code": true])
            case "Break": push("\n")
            default: break  // Image 由 MdSegsView 分段处理
            }
        }
        return out
    }

    static func attributed(_ segs: [Any], base: UIFont,
                           block: BlockState)
        -> NSAttributedString {
        Marks.withRhythm(
            Marks.attributed(runs: runs(segs), base: base),
            block: block)
    }
}

/// 行内段序列：文本段聚成 Text，Image 段独立成图（纵排）。
struct MdSegsView: View {
    var segs: [Any]
    var base: UIFont
    var block: BlockState
    var library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(groups.enumerated()),
                    id: \.offset) { _, g in
                if let src = g.image {
                    ItemImageView(fileId: nil,
                                  urlString: src,
                                  library: library)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                } else {
                    Text(AttributedString(
                        MdRender.attributed(
                            g.segs, base: base, block: block)))
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                }
            }
        }
    }

    private struct Group {
        var segs: [Any] = []
        var image: String?
    }

    private var groups: [Group] {
        var out: [Group] = []
        var cur = Group()
        for s in segs {
            if let d = s as? [String: Any],
               let src = (d["Image"] as? [String: Any])?["src"]
                   as? String {
                if !cur.segs.isEmpty {
                    out.append(cur)
                    cur = Group()
                }
                out.append(Group(image: src))
            } else {
                cur.segs.append(s)
            }
        }
        if !cur.segs.isEmpty { out.append(cur) }
        return out
    }
}

/// 解析树单块渲染（递归：Quote/Callout/List 子块）。
struct MdBlockView: View {
    var raw: Any
    var block: BlockState
    var library: Library

    var body: some View {
        if let name = raw as? String {
            // 单元变体（serde 外部标签为纯字符串）。
            if name == "Divider" { Divider() }
        } else if let d = raw as? [String: Any],
                  let k = d.keys.first, let v = d[k] {
            content(kind: k, v: v)
        }
    }

    @ViewBuilder
    private func content(kind k: String, v: Any)
        -> some View {
        let lv = v as? [String: Any] ?? [:]
        switch k {
        case "Heading":
            let level = lv["level"] as? Int ?? 2
            let size: CGFloat = level <= 1 ? 28
                : level == 2 ? 23 : 20
            MdSegsView(
                segs: lv["segs"] as? [Any] ?? [],
                base: Marks.dynFont(
                    size: size, weight: .bold,
                    style: level <= 1 ? .title1
                        : level == 2 ? .title2 : .title3),
                block: block, library: library)
        case "Para":
            MdSegsView(segs: lv["segs"] as? [Any] ?? [],
                       base: Marks.dynFont(size: 16),
                       block: block, library: library)
        case "Code":
            Text(lv["code"] as? String ?? "")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(10)
                .background(T.codeBg,
                            in: RoundedRectangle(
                                cornerRadius: 8))
        case "Math":
            Text(lv["tex"] as? String ?? "")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .center)
                .padding(.vertical, 6)
        case "Quote":
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(T.quoteBar)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(
                        (lv["blocks"] as? [Any] ?? [])
                            .enumerated()), id: \.offset) {
                        _, sub in
                        MdBlockView(raw: sub, block: block,
                                    library: library)
                    }
                }
            }
        case "Callout":
            let style = lv["style"] as? String ?? "note"
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: calloutIcon(style))
                        .font(.system(size: 14,
                                      weight: .semibold))
                    Text(lv["title"] as? String ?? "")
                        .font(.system(size: 13,
                                      weight: .semibold))
                }
                .foregroundStyle(T.calloutAccent(style))
                ForEach(Array(
                    (lv["blocks"] as? [Any] ?? [])
                        .enumerated()), id: \.offset) {
                    _, sub in
                    MdBlockView(raw: sub, block: block,
                                library: library)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.calloutBg(style),
                        in: RoundedRectangle(
                            cornerRadius: 12))
        case "List":
            let ordered = lv["ordered"] as? Bool ?? false
            let start = lv["start"] as? Int ?? 1
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(
                    (lv["items"] as? [Any] ?? [])
                        .enumerated()), id: \.offset) {
                    idx, itemAny in
                    let item = itemAny as? [String: Any]
                        ?? [:]
                    HStack(alignment: .top, spacing: 8) {
                        if let checked = item["checked"]
                            as? Bool {
                            Image(systemName: checked
                                ? "checkmark.square.fill"
                                : "square")
                                .font(.system(size: 15))
                                .foregroundStyle(checked
                                    ? T.checkChecked
                                    : T.textSecondary)
                        } else {
                            Text(ordered
                                 ? "\(start + idx)."
                                 : "•")
                                .font(.system(size: 15))
                                .foregroundStyle(
                                    T.textSecondary)
                                .frame(width: 18,
                                       alignment: .trailing)
                        }
                        VStack(alignment: .leading,
                               spacing: 4) {
                            MdSegsView(
                                segs: item["segs"] as? [Any]
                                    ?? [],
                                base: Marks.dynFont(
                                    size: 16),
                                block: block,
                                library: library)
                            ForEach(Array(
                                (item["sub"] as? [Any] ?? [])
                                    .enumerated()),
                                    id: \.offset) { _, sub in
                                MdBlockView(
                                    raw: sub, block: block,
                                    library: library)
                            }
                        }
                    }
                }
            }
        case "Table":
            let head = lv["head"] as? [[Any]] ?? []
            let rows = lv["rows"] as? [[[Any]]] ?? []
            Grid(alignment: .leading,
                 horizontalSpacing: 12,
                 verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(head.enumerated()),
                            id: \.offset) { _, cell in
                        Text(AttributedString(
                            MdRender.attributed(
                                cell,
                                base: Marks.dynFont(
                                    size: 14, weight: .bold),
                                block: block)))
                    }
                }
                ForEach(Array(rows.enumerated()),
                        id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()),
                                id: \.offset) { _, cell in
                            Text(AttributedString(
                                MdRender.attributed(
                                    cell,
                                    base: Marks.dynFont(
                                        size: 14),
                                    block: block)))
                        }
                    }
                }
            }
        case "Footnotes":
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(
                    (lv["items"] as? [Any] ?? [])
                        .enumerated()), id: \.offset) {
                    _, itemAny in
                    let item = itemAny as? [String: Any]
                        ?? [:]
                    HStack(alignment: .top, spacing: 6) {
                        Text("[\(item["id"] as? String ?? "")]")
                            .font(.system(size: 12))
                            .foregroundStyle(T.textSecondary)
                        VStack(alignment: .leading,
                               spacing: 4) {
                            ForEach(Array(
                                (item["blocks"] as? [Any]
                                    ?? []).enumerated()),
                                    id: \.offset) { _, sub in
                                MdBlockView(
                                    raw: sub, block: block,
                                    library: library)
                            }
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func calloutIcon(_ style: String) -> String {
        switch style {
        case "tip": return "lightbulb.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "important": return "exclamationmark.circle.fill"
        case "caution": return "exclamationmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }
}

/// MD 源段落的预览面：整块点按回源码编辑。
struct MdPreviewView: View {
    @ObservedObject var editor: EditorModel
    var block: BlockState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editor.mdBlocks(for: block).isEmpty {
                // 解析为空（如全文是未被引用的定义行）：
                // 原文兜底呈现，避免空白块被误认内容
                // 丢失（审计 D-R1；Web 有原文兜底）。
                Text(block.text)
                    .font(.system(size: 16))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
            }
            ForEach(Array(editor.mdBlocks(for: block)
                .enumerated()), id: \.offset) { _, raw in
                MdBlockView(raw: raw, block: block,
                            library: editor.library)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { editor.beginMdEdit(block) }
    }
}

struct CardBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @Environment(\.openURL) private var openURL
    @StateObject private var pulse = PulseState()

    final class PulseState: ObservableObject {
        @Published var on = false
    }

    var library: Library { editor.library }

    // 卡数据在 node 顶层 url + meta{title,subtitle,cover,
    // source}（core 口径）；attrs 读法只对旧形兜底。
    var meta: [String: Any] {
        block.node["meta"] as? [String: Any] ?? [:]
    }
    var cardURL: String {
        (block.node["url"] as? String) ?? ""
    }
    var status: String {
        block.node["status"] as? String ?? ""
    }
    var isMusic: Bool { block.type == "musicCard" }
    var title: String { meta["title"] as? String ?? "" }
    var cover: String {
        let c = (meta["cover"] as? String)
            ?? (meta["image"] as? String) ?? ""
        if c.hasPrefix("data:") { return c }
        let u = EditorModel.extractCardURL(c) ?? ""
        // mzstatic 封面归一（Web proxy_img 同口径）：
        // Apple 的 og 图是带大面积透明留白的画布、艺
        // 术图只占中心一小块（他平台为紧图、独 Apple
        // 中招，用户实证）；尺寸段改 600x600bb 取紧
        // 方图后再满幅裁切。
        if u.contains("mzstatic.com") {
            return u.replacingOccurrences(
                of: #"\d+x\d+bb\."#,
                with: "600x600bb.",
                options: .regularExpression)
        }
        return u
    }
    var host: String {
        guard let u = URL(string: cardURL),
              let h = u.host else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    var body: some View {
        Group {
            if block.fileId != nil {
                // 带 fileId 的音乐卡 = 音频附件，走文件行。
                fileRow
            } else if isMusic, status == "loading" {
                skeleton
            } else if isMusic, status == "error",
                      !cardURL.isEmpty {
                errorCard
            } else if !title.isEmpty {
                readyCard
            } else if !isMusic {
                errCard
            } else if !cardURL.isEmpty {
                urlPill
            } else {
                EmptyView()
            }
        }
    }

    // ── ready 卡（Web .link-card-block 口径） ──────
    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !cover.isEmpty {
                // 封面整幅出血（Web .lkc-cover 口径）：
                // 2.4:1 盒定几何、图满幅 cover、直角
                // （卡面裁外角）。
                GeometryReader { geo in
                    ItemImageView(fileId: nil,
                                  urlString: cover,
                                  library: library)
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                }
                .aspectRatio(2.4, contentMode: .fit)
                .clipped()
                .background(T.borderSoft)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineSpacing(14 * 0.4)
                    .lineLimit(2)
                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.system(size: 12))
                        .foregroundStyle(T.textSecondary)
                        .lineSpacing(12 * 0.3)
                        .lineLimit(2)
                        .padding(.top, 3)
                }
                sourceRow
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, cover.isEmpty ? 10 : 6)
            .padding(.bottom, 12)
        }
        .contentCard(radius: 32)
        .contentShape(Rectangle())
        .onTapGesture { openCard() }
    }

    private var subtitleText: String {
        // 副标题只认 meta.subtitle（Web 口径，description
        // 不兜底）；哔哩哔哩链接卡不显示副标题。
        let s = meta["subtitle"] as? String ?? ""
        if !isMusic, sourceText == "哔哩哔哩" { return "" }
        return s
    }

    private var sourceText: String {
        if isMusic {
            let s = meta["source"] as? String ?? ""
            return s.isEmpty ? "音乐" : s
        }
        let s = (meta["source"] as? String)
            ?? (meta["siteName"] as? String) ?? ""
        return s.isEmpty ? host : s
    }

    private var sourceIcon: String {
        if isMusic { return "music.note" }
        switch meta["type"] as? String {
        case "music": return "music.note"
        case "video": return "play.rectangle"
        default: return "link"
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 5) {
            Image(systemName: sourceIcon)
                .font(.system(size: 12))
            Circle()
                .fill(T.textSecondary.opacity(0.4))
                .frame(width: 3, height: 3)
            Text(sourceText)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(T.textSecondary)
    }

    // ── link-card 无标题 err 卡（Web 口径） ────────
    private var errCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(host.isEmpty ? cardURL : host)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
                .lineLimit(2)
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                Circle()
                    .fill(T.textSecondary.opacity(0.4))
                    .frame(width: 3, height: 3)
                Text(cardURL)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.textSecondary)
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(radius: 32)
        .contentShape(Rectangle())
        .onTapGesture { openCard() }
    }

    // ── 音乐 loading 骨架（封面 + 三行，整体脉冲） ──
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(T.borderSoft)
                .aspectRatio(2.4, contentMode: .fit)
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(T.borderSoft)
                        .frame(width: geo.size.width * 0.75,
                               height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(T.borderSoft)
                        .frame(width: geo.size.width * 0.50,
                               height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(T.borderSoft)
                        .frame(width: geo.size.width * 0.35,
                               height: 12)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .contentCard(radius: 32)
        .opacity(pulse.on ? 0.55 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7)
                .repeatForever(autoreverses: true)) {
                pulse.on = true
            }
        }
    }

    // ── 音乐 error 卡（图标 + URL + 重试钮） ───────
    private var errorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundStyle(T.textMain)
            Text(cardURL)
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
            Button {
                var n = block.node
                n["status"] = "loading"
                block.node = n
                block.nodeVersion += 1
                editor.scheduleSave()
                editor.startResolveCard(block)
            } label: {
                Text("重试")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(T.fillHoverStrong,
                                in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentCard(radius: 32)
    }

    // ── 音乐兜底胶囊（有 URL 无标题/状态） ─────────
    private var urlPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
            Text(status == "error" ? "预览不可用" : cardURL)
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentCard(radius: 999)
        .contentShape(Rectangle())
        .onTapGesture { openCard() }
    }

    // ── 音频附件文件行 ───────────────────────────
    @StateObject private var shareState = ShareState()

    private var fileRow: some View {
        let name = library.attachmentName(for: block.fileId)
            ?? (block.node["name"] as? String)
            ?? (block.node["title"] as? String)
            ?? "音频"
        return AttachmentRow(icon: "music.note", name: name,
                             hint: "音乐")
            .contentShape(Rectangle())
            .onTapGesture {
                if let fid = block.fileId {
                    shareAttachment(fid: fid, name: name)
                }
            }
            .sheet(isPresented: Binding(
                get: { shareState.url != nil },
                set: { if !$0 { shareState.url = nil } })) {
                if let url = shareState.url {
                    ShareSheet(url: url)
                }
            }
    }

    private func shareAttachment(fid: String, name: String) {
        let lib = library
        DispatchQueue.global(qos: .userInitiated).async {
            let data = lib.attachmentData(fid)
            let safe = name.replacingOccurrences(
                of: "/", with: "_")
            let path = NSTemporaryDirectory() + safe
            try? data.write(to: URL(fileURLWithPath: path))
            DispatchQueue.main.async {
                shareState.url = URL(fileURLWithPath: path)
            }
        }
    }

    private func openCard() {
        let s = cardURL
        guard s.hasPrefix("http://") || s.hasPrefix("https://"),
              let u = URL(string: s) else { return }
        openURL(u)
    }
}

final class VideoHolder: ObservableObject {
    @Published var player: AVPlayer?
}

/// 内嵌播放器面（本工具链 AVKit 的 SwiftUI VideoPlayer
/// 不可见，改用 AVPlayerViewController 承载，与 Web
/// <video controls> 等价）。
struct InlinePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(
        context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(
        _ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

/// 视频块（Web 口径）：整幅视频面内嵌播放器（原生
/// VideoPlayer 即 Web <video controls> 的等价更优形
/// 态），16:9 占位、圆角 22。
struct VideoBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    @StateObject private var holder = VideoHolder()

    var body: some View {
        Group {
            if let player = holder.player {
                InlinePlayerView(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(
                        cornerRadius: 22))
            } else {
                RoundedRectangle(cornerRadius: 22)
                    .fill(T.borderSoft)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(T.textSecondary)
                    }
            }
        }
        .onAppear { prepare() }
    }

    private func prepare() {
        guard holder.player == nil else { return }
        if let s = (block.node["url"] as? String)
            ?? block.imageURL,
           let u = URL(string: s) {
            holder.player = AVPlayer(url: u)
            return
        }
        if let fid = block.fileId {
            let lib = library
            DispatchQueue.global(qos: .userInitiated).async {
                let data = lib.attachmentData(fid)
                let path = NSTemporaryDirectory()
                    + "video-\(fid).mov"
                try? data.write(
                    to: URL(fileURLWithPath: path))
                DispatchQueue.main.async {
                    holder.player = AVPlayer(
                        url: URL(fileURLWithPath: path))
                }
            }
        }
    }
}

final class ShareState: ObservableObject {
    @Published var url: URL?
}

/// 附件文件行（Web .attachment-file 口径）：内边距
/// 16/20、图标 26、名 14 中粗单行省略、右侧提示胶囊
/// （11 号次级字 + 强悬停底 + 2/10 内边距）。
struct AttachmentRow: View {
    var icon: String
    var name: String
    var hint: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(T.textMain)
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(T.fillHoverStrong, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentCard(radius: 32)
    }
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
        VStack(alignment: .leading, spacing: 8) {
            if isImageAttachment, let first = files.first {
                // 图片附件（node.image）：整幅图呈现，圆角
                // 32，点按进图片页（Web 口径）。
                ItemImageView(fileId: first.0,
                              urlString: nil,
                              library: library)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(
                        cornerRadius: 32))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editor.imageTarget = ImageTarget(
                            fileId: first.0, urlString: nil,
                            name: first.1)
                    }
            } else {
                ForEach(files, id: \.0) { fid, name in
                    AttachmentRow(
                        icon: "paperclip",
                        name: name, hint: "打开")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 图片类文件进图片页，其余走
                            // 分享（Web 文件行分发口径）。
                            if Self.imageExts.contains(
                                (name as NSString)
                                    .pathExtension.lowercased()) {
                                editor.imageTarget =
                                    ImageTarget(
                                        fileId: fid,
                                        urlString: nil,
                                        name: name)
                            } else {
                                share(fid: fid, name: name)
                            }
                        }
                }
                if files.isEmpty {
                    Text("附件（无文件）")
                        .font(.system(size: 14))
                        .foregroundStyle(T.textSecondary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareState.url != nil },
            set: { if !$0 { shareState.url = nil } })) {
            if let url = shareState.url { ShareSheet(url: url) }
        }
    }

    /// Web 口径：node.image == true 的单文件附件整幅
    /// 呈现（多文件形态仍走文件行）。
    private var isImageAttachment: Bool {
        (block.node["image"] as? Bool) == true
            && files.count == 1
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
    @StateObject private var loader = ImageLoader()

    final class ImgTextUI: ObservableObject {
        @Published var editing = false
        @Published var draft = ""
    }

    var body: some View {
        Group {
            if block.type == "imgTextCard" {
                // Web .img-text-card 口径：圆角 22 内容
                // 卡，上图（整幅、高上限 468）下文（内边
                // 距 12/14、14 号、行高 1.7）。
                VStack(alignment: .leading, spacing: 0) {
                    if block.fileId != nil
                        || block.imageURL != nil {
                        if let img = loader.image {
                            // 整幅出血、直角（卡面裁外
                            // 角）：自然高、上限 468 裁切。
                            Color.clear
                                .aspectRatio(
                                    img.size.width
                                        / max(img.size.height,
                                              1),
                                    contentMode: .fit)
                                .frame(maxHeight: 468)
                                .overlay {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    tapImageArea()
                                }
                        } else {
                            Rectangle()
                                .fill(T.pressBg)
                                .frame(height: 160)
                        }
                    } else {
                        Text("点击添加图片")
                            .font(.system(size: 13))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .background(T.pressBg)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tapImageArea()
                            }
                    }
                    textLabel
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .contentCard(radius: 22)
            } else {
                // Web .img-text-row 口径：左图占半幅整高、
                // 右文 10/14 内边距、14 号行高 1.7、最多
                // 6 行；整卡高 181–196。
                GeometryReader { geo in
                    HStack(spacing: 10) {
                        if block.fileId != nil
                            || block.imageURL != nil {
                            if let img = loader.image {
                                // 图区整幅出血、直角（卡面
                                // 裁外角），占半幅整高。
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: geo.size.width
                                            * 0.5,
                                        height: geo.size
                                            .height)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        tapImageArea()
                                    }
                            } else {
                                Rectangle()
                                    .fill(T.pressBg)
                                    .frame(
                                        width: geo.size.width
                                            * 0.5)
                            }
                        } else {
                            ZStack {
                                Rectangle()
                                    .fill(T.fillSubtle)
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundStyle(
                                        T.textSecondary
                                            .opacity(0.3))
                            }
                            .frame(width: geo.size.width
                                * 0.5)
                        }
                        textLabel
                            .lineLimit(6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                    }
                }
                .frame(height: 188)
                .contentCard(radius: 22)
            }
        }
        .onAppear {
            loader.load(fileId: block.fileId,
                        urlString: block.imageURL,
                        library: editor.library)
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

    /// 图区点按分流（Web card-editing 口径）：编辑态
    /// 点图区 = 换图（cardPick kind=set）；常态有图
    /// 进图片页、无图不动作（占位文案即引导走编辑态）。
    private func tapImageArea() {
        if editor.cardEditBlockId == block.id {
            editor.replaceImageBlockId = block.id
            editor.showReplacePicker = true
        } else if block.fileId != nil || block.imageURL != nil {
            openImagePage()
        }
    }

    private var textLabel: some View {
        Text(block.text.isEmpty ? "点击查看完整文本" : block.text)
            .font(.system(size: 14))
            .lineSpacing(14 * 0.7)
            .foregroundStyle(block.text.isEmpty
                ? T.textSecondary : T.textMain)
            .frame(minHeight: 44, alignment: .topLeading)
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
    /// 浮层档底（Web --glass-overlay-bg：实白/深 #1C1C1E；
    /// 菜单/导出/斜杠/卡菜单四浮层专用，与内容档分开）。
    static var overlayBg: Color { dyn(0xFFFFFF, 0x1C1C1E) }
    /// 色点未选边（Web --color-black-12）。
    static var dotBorder: Color {
        dynA(0x000000, 0.12, 0xFFFFFF, 0.14)
    }
    /// 亮危险色（Web --color-danger-bright #FF3B30）。
    static var dangerBright: Color { dyn(0xFF3B30, 0xFF453A) }
    /// 浮层档边（Web --glass-overlay-border）。
    static var overlayBorder: Color {
        dynA(0x000000, 0.18, 0xFFFFFF, 0.20)
    }
    static var quoteBg: Color {
        dynA(0x000000, 0.025, 0xFFFFFF, 0.045)
    }
    /// 代码块底（Web --code-bg 口径近似：中性淡染）。
    static var codeBg: Color {
        dynA(0x000000, 0.045, 0xFFFFFF, 0.07)
    }
    /// 按下态背景（Web :active/--fill-hover 口径）。
    static var pressBg: Color {
        dynA(0x000000, 0.05, 0xFFFFFF, 0.09)
    }
    /// 内容卡底（Web --glass-content-bg：实色白/深灰，
    /// 编辑器内卡片专用，与浮层玻璃的半透底分开）。
    static var contentBg: Color { dyn(0xFFFFFF, 0x202024) }
    /// 骨架/封面占位底（Web --border-color）。
    static var borderSoft: Color {
        dynA(0x000000, 0.05, 0xFFFFFF, 0.10)
    }
    /// 强悬停填充（Web --fill-hover-strong：中灰 10%）。
    static var fillHoverStrong: Color {
        dynA(0x7F7F7F, 0.10, 0x7F7F7F, 0.10)
    }
    /// 悬停填充（Web --fill-hover：快捷键/kbd 胶囊底）。
    static var fillHover: Color {
        dynA(0x7F7F7F, 0.06, 0x7F7F7F, 0.06)
    }
    /// 微填充（Web --fill-subtle：图文行图区/空瓦底）。
    static var fillSubtle: Color {
        dynA(0x000000, 0.03, 0xFFFFFF, 0.04)
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

/// 内容卡面（Web .link-card-block 等编辑器内卡片口径）：
/// 实色 content 底 + 0.5 边 + 圆角裁切（不用浮层玻璃
/// 的材质半透底——那是菜单/底表的面）。
struct ContentCard: ViewModifier {
    var radius: CGFloat = 32
    func body(content: Content) -> some View {
        content
            .background(T.contentBg)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(T.glassBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// 浮层面（Web --glass-overlay 口径）：实色底 + 0.5 边
/// + 圆角裁切。菜单/导出/斜杠/卡菜单专用；Web 的
/// --glass-overlay-shadow 变量从未定义、实际无阴影，
/// 故此处同样无阴影。
struct OverlayCard: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(T.overlayBg)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(T.overlayBorder,
                                  lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func overlayCard(radius: CGFloat = 22) -> some View {
        modifier(OverlayCard(radius: radius))
    }
    func contentCard(radius: CGFloat = 32) -> some View {
        modifier(ContentCard(radius: radius))
    }
    func glassCard(radius: CGFloat = 32) -> some View {
        modifier(GlassCard(radius: radius))
    }
    func glassControl(radius: CGFloat) -> some View {
        modifier(GlassCard(radius: radius, control: true))
    }
}

/// 按下态体系（M25，Web :active 口径）：行/菜单项给背景
/// 按下态，胶囊/卡片类给 0.975 缩放，过渡 0.15s。
struct RowPressStyle: ButtonStyle {
    var radius: CGFloat = 12
    func makeBody(
        configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(configuration.isPressed
                          ? T.pressBg : Color.clear))
            .animation(.easeOut(duration: 0.15),
                       value: configuration.isPressed)
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(
        configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed
                         ? 0.975 : 1)
            .animation(.easeOut(duration: 0.15),
                       value: configuration.isPressed)
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

/// 头像面：玻璃圆 + 恐龙线稿；备忘有自定义头像
/// （avatars 通道，data URL）时整圆贴图（Web 同口径）。
final class AvatarHolder: ObservableObject {
    @Published var custom: UIImage?

    func refresh(memoId: String?, library: Library?) {
        guard let id = memoId, let library else {
            custom = nil
            return
        }
        library.loadAvatar(for: id)
        if let url = library.avatarDataURL(for: id) {
            custom = AvatarView.image(fromDataURL: url)
        } else {
            custom = nil
        }
    }
}

struct AvatarView: View {
    var size: CGFloat
    var memoId: String? = nil
    var library: Library? = nil
    @StateObject private var holder = AvatarHolder()

    static func image(fromDataURL s: String) -> UIImage? {
        guard s.hasPrefix("data:"),
              let comma = s.firstIndex(of: ","),
              s[..<comma].contains("base64") else { return nil }
        let b64 = String(s[s.index(after: comma)...])
        guard let d = Data(base64Encoded: b64) else {
            return nil
        }
        return UIImage(data: d)
    }

    var body: some View {
        Group {
            if let custom = holder.custom {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                DinoView(size: size * 0.72)
                    .frame(width: size, height: size)
                    .glassControl(radius: 999)
            }
        }
        .onAppear {
            holder.refresh(memoId: memoId, library: library)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .momentAvatarChanged)) { note in
            if (note.object as? String) == memoId {
                holder.refresh(memoId: memoId,
                               library: library)
            }
        }
    }
}

extension Notification.Name {
    static let momentAvatarChanged =
        Notification.Name("momentAvatarChanged")
}

// ── 天气（Web weather.rs 口径原生化） ──────────────
// 链：列表可见后 1.5s 触发 → 30 分钟缓存 → GPS 定位
// （5s 超时）→ ipapi IP 兜底 → 和风主链 → 彩云兜底。
// key 优先序（用户裁定）：设置页自填 > 构建注入的
// bundle weather-keys.json；和风 key 为空整链不发请求。
final class WeatherService: NSObject, ObservableObject,
    CLLocationManagerDelegate {
    static let shared = WeatherService()

    struct Now {
        var temp: Int
        var city: String
        var text: String
    }

    @Published var now: Now?
    private let manager = CLLocationManager()
    private var inFlight = false
    private var locContinuation:
        CheckedContinuation<(Double, Double)?, Never>?
    private var locResumed = false

    static func key(_ name: String) -> String {
        let user = UserDefaults.standard
            .string(forKey: "weatherKey_" + name) ?? ""
        if !user.isEmpty { return user }
        if let url = Bundle.main.url(
            forResource: "weather-keys", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj = (try? JSONSerialization.jsonObject(
            with: data)) as? [String: String] {
            return obj[name] ?? ""
        }
        return ""
    }

    private func readCache() -> (Now, Double)? {
        guard let raw = UserDefaults.standard
            .string(forKey: "weatherCacheV1"),
              let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(
                with: data)) as? [String: Any],
              let temp = obj["temp"] as? Int,
              let ts = obj["ts"] as? Double else {
            return nil
        }
        return (Now(temp: temp,
                    city: obj["city"] as? String ?? "",
                    text: obj["text"] as? String ?? ""), ts)
    }

    private func writeCache(_ w: Now) {
        let obj: [String: Any] = [
            "temp": w.temp, "city": w.city, "text": w.text,
            "ts": Date().timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: obj),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s,
                forKey: "weatherCacheV1")
        }
    }

    func refreshIfNeeded() {
        if let (w, ts) = readCache(),
           Date().timeIntervalSince1970 - ts < 1800 {
            now = w
            return
        }
        guard !inFlight else { return }
        inFlight = true
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 1_500_000_000)
            await self.fetch()
            self.inFlight = false
        }
    }

    private func fetch() async {
        var ipCity = ""
        var coords = await gpsCoords()
        if coords == nil {
            if let ip = await fetchJSON(
                "https://ipapi.co/json/") {
                if let c = ip["city"] as? String {
                    let region = ip["region"] as? String ?? ""
                    ipCity = region.isEmpty ? c
                        : "\(c) \(region)"
                }
                if let la = ip["latitude"] as? Double,
                   let lo = ip["longitude"] as? Double {
                    coords = (la, lo)
                }
            }
        }
        guard let (lat, lng) = coords else {
            DiagLog.shared.log(.info,
                "WEATHER locate failed (gps + ip)")
            return
        }
        let qwKey = Self.key("qweather")
        if qwKey.isEmpty {
            DiagLog.shared.log(.warn,
                "WEATHER no api key, skip")
            return
        }
        if let w = await fetchQWeather(
            lat: lat, lng: lng, key: qwKey,
            ipCity: ipCity) {
            await MainActor.run {
                self.now = w
            }
            return
        }
        if let w = await fetchCaiyun(
            lat: lat, lng: lng, ipCity: ipCity) {
            await MainActor.run {
                self.now = w
            }
            return
        }
        DiagLog.shared.log(.info,
            "WEATHER provider=fail (qweather + caiyun)")
    }

    private func fetchJSON(_ urlStr: String) async
        -> [String: Any]? {
        guard let url = URL(string: urlStr) else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared
            .data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(
            with: data)) as? [String: Any]
    }

    private func fetchQWeather(lat: Double, lng: Double,
                               key: String, ipCity: String)
        async -> Now? {
        let nowURL = "https://jq3dna235e.re.qweatherapi.com"
            + "/v7/weather/now?location=\(lng),\(lat)"
            + "&key=\(key)"
        guard let qw = await fetchJSON(nowURL),
              (qw["code"] as? String) == "200",
              let n = qw["now"] as? [String: Any],
              let text = n["text"] as? String else {
            DiagLog.shared.log(.info,
                "WEATHER qweather now failed")
            return nil
        }
        let temp: Int?
        if let s = n["temp"] as? String {
            temp = Int(s)
        } else if let v = n["temp"] as? Int {
            temp = v
        } else { temp = nil }
        guard let temp else { return nil }
        var city = await geocoderCity(lat: lat, lng: lng)
            ?? ""
        if city.isEmpty {
            let geoURL = "https://jq3dna235e.re"
                + ".qweatherapi.com/geo/v2/city/lookup"
                + "?location=\(lng),\(lat)&key=\(key)"
            if let geo = await fetchJSON(geoURL),
               (geo["code"] as? String) == "200",
               let loc = (geo["location"]
                as? [[String: Any]])?.first {
                let name = loc["name"] as? String ?? ""
                let adm2 = loc["adm2"] as? String ?? ""
                city = adm2.isEmpty ? name : adm2 + name
            }
        }
        if city.isEmpty { city = ipCity }
        let w = Now(temp: temp, city: city, text: text)
        writeCache(w)
        DiagLog.shared.log(.info,
            "WEATHER fetched provider=qweather "
            + "\(temp)° \(city) \(text)")
        return w
    }

    private func geocoderCity(lat: Double, lng: Double)
        async -> String? {
        let geo = CLGeocoder()
        let loc = CLLocation(latitude: lat, longitude: lng)
        let places = try? await geo.reverseGeocodeLocation(
            loc, preferredLocale: Locale(
                identifier: "zh_CN"))
        guard let p = places?.first else { return nil }
        let city = p.locality ?? p.administrativeArea ?? ""
        return city.isEmpty ? nil : city
    }

    private func fetchCaiyun(lat: Double, lng: Double,
                             ipCity: String) async -> Now? {
        let key = Self.key("caiyun")
        if key.isEmpty {
            DiagLog.shared.log(.info,
                "WEATHER caiyun skipped (no key)")
            return nil
        }
        let urlStr = "https://api.caiyunapp.com/v2.6/"
            + "\(key)/\(lng),\(lat)/weather.jsonp"
            + "?callback=MYCALLBACK"
        guard let url = URL(string: urlStr) else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared
            .data(for: req),
              var raw = String(data: data, encoding: .utf8)
        else {
            DiagLog.shared.log(.info,
                "WEATHER caiyun fallback failed")
            return nil
        }
        if raw.hasPrefix("MYCALLBACK(") {
            raw = String(raw.dropFirst("MYCALLBACK(".count))
        }
        if raw.hasSuffix(")") {
            raw = String(raw.dropLast())
        }
        guard let jdata = raw.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(
                with: jdata)) as? [String: Any],
              (j["status"] as? String) == "ok",
              let rt = (j["result"] as? [String: Any])?[
                "realtime"] as? [String: Any],
              let t = rt["temperature"] as? Double else {
            DiagLog.shared.log(.info,
                "WEATHER caiyun fallback failed")
            return nil
        }
        let temp = Int((t + 0.5).rounded(.down))
        let skycon = rt["skycon"] as? String ?? ""
        let w = Now(temp: temp, city: ipCity,
                    text: Self.caiyunCondition(skycon))
        writeCache(w)
        DiagLog.shared.log(.info,
            "WEATHER fetched provider=caiyun-fallback "
            + "\(temp)° \(ipCity) \(w.text)")
        return w
    }

    static func caiyunCondition(_ skycon: String) -> String {
        switch skycon {
        case "CLEAR_DAY", "CLEAR_NIGHT": return "晴"
        case "PARTLY_CLOUDY_DAY", "PARTLY_CLOUDY_NIGHT":
            return "多云"
        case "CLOUDY": return "阴"
        case "LIGHT_RAIN": return "小雨"
        case "MODERATE_RAIN": return "中雨"
        case "HEAVY_RAIN": return "大雨"
        case "STORM_RAIN": return "暴雨"
        case "THUNDER_SHOWER": return "雷阵雨"
        case "SLEET": return "雨夹雪"
        case "LIGHT_SNOW": return "小雪"
        case "MODERATE_SNOW": return "中雪"
        case "HEAVY_SNOW": return "大雪"
        case "STORM_SNOW": return "暴雪"
        case "HAIL": return "冰雹"
        case "LIGHT_HAZE": return "薄雾"
        case "MODERATE_HAZE": return "中度雾"
        case "HEAVY_HAZE": return "浓雾"
        case "FOG": return "雾"
        case "DUST": return "沙尘"
        case "WIND": return "大风"
        default: return skycon
        }
    }

    // GPS：WhenInUse 授权 + 单次定位，5s 超时回 nil。
    private func gpsCoords() async -> (Double, Double)? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }
        return await withCheckedContinuation { cont in
            locContinuation = cont
            locResumed = false
            manager.delegate = self
            manager.desiredAccuracy =
                kCLLocationAccuracyKilometer
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: 5_000_000_000)
                self.resumeLoc(nil)
            }
        }
    }

    private func resumeLoc(_ v: (Double, Double)?) {
        guard !locResumed, let c = locContinuation else {
            return
        }
        locResumed = true
        locContinuation = nil
        c.resume(returning: v)
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations
                         locations: [CLLocation]) {
        if let l = locations.first {
            resumeLoc((l.coordinate.latitude,
                       l.coordinate.longitude))
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError
                         error: Error) {
        resumeLoc(nil)
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied
            || manager.authorizationStatus == .restricted {
            resumeLoc(nil)
        }
    }
}

// ── 列表 ───────────────────────────────────────────
struct ListView: View {
    @ObservedObject var library: Library
    @ObservedObject private var weather =
        WeatherService.shared
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
                    EditorView(editor: editor) { item in
                        nav.dest = .editor(EditorModel(
                            item: item, library: library))
                    }
                case .settings:
                    SettingsView(library: library)
                case nil:
                    EmptyView()
                }
            }
            .onAppear {
                library.markFirstFrame()
                if library.memos.isEmpty { library.load() }
                WeatherService.shared.refreshIfNeeded()
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
                    // 搜索展开/收起交叉淡入（M5）。
                    .animation(.easeInOut(duration: 0.2),
                               value: nav.searchOpen)
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
        .background(alignment: .top) {
            // 顶栏渐变模糊带（系统材质）：静止时透明
            // （Web sticky 透明口径），滚动后随进度渐
            // 入；材质下缘经渐变 mask 渐隐——列表内容
            // 在页眉下柔和淡出，不再被硬边切断。溢出
            // 页眉高的 36pt 盖住列表顶部作过渡带。
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 118)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.55),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
                .opacity(min(max(nav.scrollOffset / 48, 0), 1))
                .allowsHitTesting(false)
        }
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
            .transition(.opacity)
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
            .buttonStyle(CardPressStyle())
            .transition(.opacity)
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
                .buttonStyle(CardPressStyle())
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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新建笔记")
                        .font(.system(size: 16,
                                      weight: .semibold))
                        .foregroundStyle(T.textSecondary)
                    Text("现在  点击记录你的瞬间")
                        .font(.system(size: 12))
                        .foregroundStyle(T.textSecondary)
                }
                Spacer(minLength: 0)
                // 天气块（Web 口径）：有数才渲染、缺数
                // 整块不出现（无占位无报错）。
                if let w = weather.now {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(w.temp)°")
                            .font(.system(size: 16,
                                          weight: .semibold))
                            .foregroundStyle(T.textMain)
                        Text([w.city, w.text]
                            .filter { !$0.isEmpty }
                            .joined(separator: " "))
                            .font(.system(size: 12))
                            .foregroundStyle(T.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard()
        }
        .background {
            // 滚动探针（换代，与编辑页同法）：首行背景
            // 哨兵 onGeometryChange 直读命名空间 minY，
            // 连续量测——旧 preference 探针更新跳变是
            // 顶栏紧凑切换「硬切」的主因。
            Color.clear
                .frame(width: 1, height: 1)
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.frame(in: .named("momentList")).minY
                } action: { y in
                    if nav.firstRowMinY == nil {
                        nav.firstRowMinY = y
                    }
                    let base = nav.firstRowMinY ?? y
                    nav.scrollOffset = max(0, base - y)
                }
        }
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
                    GeometryReader { geo in
                        ItemImageView(
                            fileId: memo.coverFileId,
                            urlString: memo.coverURL,
                            library: library)
                            .frame(width: geo.size.width,
                                   height: geo.size.height)
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
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
        .buttonStyle(RowPressStyle(radius: 0))
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

    /// 天气 key 自填（用户裁定：默认构建注入，设置页
    /// 可自填覆盖；只存本机 UserDefaults，不入备份）。
    final class WeatherKeyUI: ObservableObject {
        @Published var qweather: String =
            UserDefaults.standard.string(
                forKey: "weatherKey_qweather") ?? ""
        @Published var caiyun: String =
            UserDefaults.standard.string(
                forKey: "weatherKey_caiyun") ?? ""
        @Published var saved = false

        func save() {
            UserDefaults.standard.set(
                qweather.trimmingCharacters(
                    in: .whitespaces),
                forKey: "weatherKey_qweather")
            UserDefaults.standard.set(
                caiyun.trimmingCharacters(
                    in: .whitespaces),
                forKey: "weatherKey_caiyun")
            // key 变更后清天气缓存，下次进列表重拉。
            UserDefaults.standard.removeObject(
                forKey: "weatherCacheV1")
            saved = true
        }
    }
    @StateObject private var weatherUI = WeatherKeyUI()

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

    private func weatherKeyRow(
        title: String, placeholder: String,
        text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(T.textMain)
            SecureField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
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

                    SectionHeader(text: "天气")
                    VStack(alignment: .leading, spacing: 10) {
                        weatherKeyRow(
                            title: "和风天气 Key",
                            placeholder: WeatherService.key(
                                "qweather").isEmpty
                                ? "未设置" : "已生效（可自填覆盖）",
                            text: Binding(
                                get: { weatherUI.qweather },
                                set: { weatherUI.qweather = $0
                                    weatherUI.saved = false }))
                        weatherKeyRow(
                            title: "彩云天气 Key",
                            placeholder: WeatherService.key(
                                "caiyun").isEmpty
                                ? "未设置" : "已生效（可自填覆盖）",
                            text: Binding(
                                get: { weatherUI.caiyun },
                                set: { weatherUI.caiyun = $0
                                    weatherUI.saved = false }))
                        HStack {
                            Text("默认使用构建注入的 key；自填后优先，只存本机。")
                                .font(.system(size: 12))
                                .foregroundStyle(T.textSecondary)
                            Spacer()
                            Button(weatherUI.saved
                                   ? "已保存" : "保存") {
                                weatherUI.save()
                            }
                            .font(.system(size: 14,
                                          weight: .semibold))
                            .foregroundStyle(T.accent)
                        }
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
                            Text("0.9.20")
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
            DiagLog.shared.log(.info,
                "图片页打开 name=\(displayName) "
                + "fid=\(fileId ?? "-")")
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
