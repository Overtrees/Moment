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
    let originalText: String

    var type: String { node["type"] as? String ?? "paragraph" }
    var isText: Bool {
        type == "paragraph" || type == "heading" || type == "todo"
            || type == "quote" || type == "callout"
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

    init(node: [String: Any]) {
        self.node = node
        id = node["id"] as? String ?? UUID().uuidString
        let kids = node["children"] as? [[String: Any]] ?? []
        let joined = kids.compactMap {
            $0["text"] as? String
        }.joined()
        text = joined
        originalText = joined
        runs = Self.runsFrom(children: kids)
        let attrs = node["attrs"] as? [String: Any]
        checked = attrs?["checked"] as? Bool ?? false
        if type == "heading" { height = 34 }
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

    var snippet: String {
        blocks.first(where: { $0.isText && !$0.text.isEmpty })?.text
            ?? ""
    }
    var updatedDate: Date { Clock.parseISO(updatedAt) ?? Date() }
}

// ── 库门面 ──────────────────────────────────────────
final class Library: ObservableObject {
    @Published var memos: [MemoItem] = []
    @Published var timing = "启动中…"
    @Published var searchHits: [String]? = nil
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
                }
            } catch {
                DispatchQueue.main.async {
                    self.timing = "打开库失败: \(error)"
                }
            }
        }
    }

    private func reload(lib: MomentLibrary) throws {
        let json = try lib.listMemosJson()
        let items = Self.parse(json)
        DispatchQueue.main.async { self.memos = items }
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
                    .map { BlockState(node: $0) })
        }
        items.sort {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
        return items
    }

    func persist(_ item: MemoItem) {
        var it = item
        it.updatedAt = Clock.isoNow()
        let memo: [String: Any] = [
            "id": it.id, "title": it.title, "pinned": it.pinned,
            "createdAt": it.createdAt, "updatedAt": it.updatedAt,
            "doc": it.blocks.map { $0.flushedNode() },
        ]
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

    func exportZip() -> URL? {
        let dir = storeDir + "/exports"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let stamp = Clock.isoNow()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let path = dir + "/moment-backup-\(stamp).zip"
        do {
            try lib?.exportBackup(zipPath: path)
            return URL(fileURLWithPath: path)
        } catch {
            notice = "导出失败: \(error)"
            return nil
        }
    }

    func importZip(from picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let tmp = storeDir + "/import-tmp.zip"
        try? FileManager.default.removeItem(atPath: tmp)
        do {
            try FileManager.default.copyItem(
                at: picked, to: URL(fileURLWithPath: tmp))
            let result = try lib?.importBackup(zipPath: tmp) ?? ""
            notice = "导入完成: \(result)"
            if let lib { try reload(lib: lib) }
        } catch {
            notice = "导入失败: \(error)"
        }
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
    static func baseFont(for block: BlockState) -> UIFont {
        switch block.type {
        case "heading":
            let size: CGFloat = block.level <= 1 ? 24
                : block.level == 2 ? 20 : 18
            return .systemFont(ofSize: size, weight: .bold)
        default:
            return .systemFont(ofSize: 17)
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

    static func runs(from attr: NSAttributedString)
        -> [[String: Any]] {
        var out: [[String: Any]] = []
        let full = NSRange(location: 0, length: attr.length)
        attr.enumerateAttributes(in: full) { attrs, range, _ in
            let t = (attr.string as NSString)
                .substring(with: range)
            if t.isEmpty { return }
            var r: [String: Any] = ["text": t]
            if let f = attrs[.font] as? UIFont {
                let traits = f.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) {
                    r["bold"] = true
                }
                if traits.contains(.traitItalic) {
                    r["italic"] = true
                }
                if traits.contains(.traitMonoSpace) {
                    r["code"] = true
                }
            }
            if let u = attrs[.underlineStyle] as? Int, u != 0 {
                r["underline"] = true
            }
            if let s = attrs[.strikethroughStyle] as? Int,
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
        tv.attributedText = Marks.attributed(
            runs: block.runs, base: base)
        recalc(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let key = "\(block.type)-\(block.level)-"
            + "\(block.nodeVersion)"
        let typeChanged = context.coordinator.lastTypeKey != key
        if typeChanged {
            context.coordinator.lastTypeKey = key
        }
        if (tv.text != block.text || typeChanged)
            && tv.markedTextRange == nil && !tv.isFirstResponder {
            let base = Marks.baseFont(for: block)
            tv.font = base
            tv.typingAttributes = [.font: base]
            tv.attributedText = Marks.attributed(
                runs: block.runs, base: base)
            recalc(tv)
        }
    }

    private func recalc(_ tv: UITextView) {
        let w = tv.bounds.width > 0 ? tv.bounds.width
            : UIScreen.main.bounds.width - 64
        let h = tv.sizeThatFits(CGSize(
            width: w, height: .greatestFiniteMagnitude)).height
        if abs(h - block.height) > 0.5 {
            DispatchQueue.main.async { block.height = h }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var lastTypeKey = ""
        init(_ p: BlockTextView) { parent = p }
        func textViewDidChange(_ tv: UITextView) {
            parent.block.runs = Marks.runs(
                from: tv.attributedText)
            parent.block.text = tv.text
            parent.recalc(tv)
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
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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

// ── 诊断页（lite） ─────────────────────────────────
struct DiagView: View {
    @ObservedObject var library: Library
    @StateObject private var diagState = DiagState()

    final class DiagState: ObservableObject {
        @Published var report = ""
    }

    var body: some View {
        List {
            Section("库") {
                LabeledContent("路径",
                               value: library.storeDir)
                LabeledContent("篇数",
                               value: "\(library.memos.count)")
                LabeledContent("附件数",
                               value: "\(library.attachmentCount())")
                LabeledContent("库哈希",
                               value: library.libraryHash())
                LabeledContent("冷启", value: library.timing)
            }
            Section("FFI 自检") {
                Button("运行阶段 0 自检链") {
                    let dir = NSTemporaryDirectory()
                        + "phase0-diag"
                    DispatchQueue.global(qos: .userInitiated)
                        .async {
                            let r = runPhase0Checks(dir: dir)
                            DispatchQueue.main.async {
                                diagState.report = r
                            }
                        }
                }
                if !diagState.report.isEmpty {
                    Text(diagState.report)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .navigationTitle("诊断")
    }
}

// ── 编辑器 ─────────────────────────────────────────
final class EditorModel: ObservableObject {
    @Published var title: String
    @Published var blocks: [BlockState]
    @Published var draggingId: String?
    @Published var dragDy: CGFloat = 0
    let item: MemoItem
    let library: Library
    private var saveWork: DispatchWorkItem?

    init(item: MemoItem, library: Library) {
        self.item = item
        self.library = library
        title = item.title
        blocks = item.blocks
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var it = self.item
            it.title = self.title
            it.blocks = self.blocks
            self.library.persist(it)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6,
                                      execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        var it = item
        it.title = title
        it.blocks = blocks
        library.persist(it)
    }

    func addBlock(after: BlockState? = nil) {
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
        blocks.removeAll { $0.id == b.id }
        if blocks.isEmpty { addBlock() }
        scheduleSave()
    }

    func commitDrag(stride: CGFloat) {
        guard let id = draggingId,
              let from = blocks.firstIndex(where: { $0.id == id })
        else { draggingId = nil; dragDy = 0; return }
        let shift = Int((dragDy / stride).rounded())
        let to = min(max(from + shift, 0), blocks.count - 1)
        if to != from {
            let moved = blocks.remove(at: from)
            blocks.insert(moved, at: to)
            scheduleSave()
        }
        draggingId = nil; dragDy = 0
    }
}

struct BlockRow: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var block: BlockState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if block.type == "todo" {
                Button {
                    block.checked.toggle()
                    editor.scheduleSave()
                } label: {
                    Image(systemName: block.checked
                        ? "checkmark.circle.fill"
                        : "circle")
                        .foregroundStyle(block.checked
                            ? Color.accentColor : .secondary)
                }
                .padding(.top, 6)
            }
            if block.type == "image" {
                ImageBlockView(block: block, library: editor.library)
            } else if block.type == "gallery" {
                GalleryBlockView(block: block,
                                 library: editor.library)
            } else if block.type == "musicCard"
                        || block.type == "linkCard" {
                CardBlockView(block: block,
                              library: editor.library)
            } else if block.type == "video" {
                VideoBlockView(block: block,
                               library: editor.library)
            } else if block.type == "attachment" {
                AttachmentBlockView(block: block,
                                    library: editor.library)
            } else if block.type == "imgTextCard"
                        || block.type == "imageTextRow" {
                ImgTextBlockView(block: block,
                                 library: editor.library)
            } else if block.type == "divider" {
                Divider().padding(.vertical, 8)
            } else if block.isText {
                if block.type == "quote" {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3)
                }
                BlockTextView(block: block) {
                    editor.scheduleSave()
                }
                .frame(height: block.height)
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
            if block.isText {
                Menu {
                    Button("正文") {
                        editor.setBlockType(block,
                                            type: "paragraph")
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
                } label: {
                    Image(systemName: "textformat")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            Button {
                editor.deleteBlock(block)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(block.type == "callout"
                        ? Color.orange.opacity(0.12)
                        : Color(UIColor.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .scaleEffect(editor.draggingId == block.id ? 0.97 : 1)
        .shadow(radius: editor.draggingId == block.id ? 8 : 0)
        .offset(y: editor.draggingId == block.id
            ? editor.dragDy : 0)
        .zIndex(editor.draggingId == block.id ? 1 : 0)
        .gesture(dragGesture)
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
                    editor.commitDrag(stride: 56)
                }
            }
    }
}

struct EditorView: View {
    @ObservedObject var editor: EditorModel
    @StateObject private var ui = EditorUI()

    final class EditorUI: ObservableObject {
        @Published var showPhotoPicker = false
        @Published var showFilePicker = false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("标题", text: Binding(
                    get: { editor.title },
                    set: { editor.title = $0
                           editor.scheduleSave() }))
                    .font(.title2.bold())
                    .padding(.horizontal, 12)
                ForEach(editor.blocks) { block in
                    BlockRow(editor: editor, block: block)
                }
                HStack(spacing: 16) {
                    Button {
                        editor.addBlock()
                    } label: {
                        Label("段落", systemImage: "plus.circle")
                    }
                    Button {
                        ui.showPhotoPicker = true
                    } label: {
                        Label("图片", systemImage: "photo")
                    }
                    Button {
                        ui.showFilePicker = true
                    } label: {
                        Label("文件", systemImage: "paperclip")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
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
}

// ── gallery / 卡片 / 视频 / 附件块 ─────────────────
struct GalleryBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library

    var items: [[String: Any]] {
        (block.node["attrs"] as? [String: Any])?["items"]
            as? [[String: Any]] ?? []
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()),
                        id: \.offset) { _, it in
                    ItemImageView(
                        fileId: it["fileId"] as? String,
                        urlString: (it["url"] as? String)
                            ?? (it["src"] as? String),
                        library: library)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(
                            cornerRadius: 8))
                }
            }
        }
    }
}

struct CardBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library

    var attrs: [String: Any] {
        block.node["attrs"] as? [String: Any] ?? [:]
    }

    var body: some View {
        HStack(spacing: 10) {
            ItemImageView(
                fileId: attrs["fileId"] as? String,
                urlString: (attrs["cover"] as? String)
                    ?? (attrs["image"] as? String)
                    ?? (attrs["thumbnail"] as? String),
                library: library)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text((attrs["title"] as? String)
                        ?? (attrs["name"] as? String)
                        ?? block.type)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text((attrs["artist"] as? String)
                        ?? (attrs["source"] as? String)
                        ?? (attrs["desc"] as? String) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: block.type == "musicCard"
                ? "music.note" : "link")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
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
    var library: Library
    @StateObject private var shareState = ShareState()

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
                    share(fid: fid, name: name)
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
    var library: Library

    var body: some View {
        if block.type == "imgTextCard" {
            VStack(alignment: .leading, spacing: 8) {
                ItemImageView(fileId: block.fileId,
                              urlString: block.imageURL,
                              library: library)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(
                        cornerRadius: 8))
                Text(block.text)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 10) {
                ItemImageView(fileId: block.fileId,
                              urlString: block.imageURL,
                              library: library)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(
                        cornerRadius: 8))
                Text(block.text)
                    .font(.subheadline)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }
}

// ── 列表 ───────────────────────────────────────────
struct ListView: View {
    @ObservedObject var library: Library
    @StateObject private var nav = NavState()

    final class NavState: ObservableObject {
        @Published var editor: EditorModel?
        @Published var query = ""
        @Published var showImporter = false
        @Published var shareURL: URL?
        @Published var showDiag = false
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
    }

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
            if cal.isDateInToday(d) { return "今天" }
            if cal.isDateInYesterday(d) { return "昨天" }
            let days = cal.dateComponents(
                [.day], from: d, to: now).day ?? 999
            if days <= 7 { return "过去7天" }
            if days <= 30 { return "过去30天" }
            return "更早"
        }
        for name in ["今天", "昨天", "过去7天", "过去30天", "更早"] {
            let g = rest.filter { bucket($0.updatedDate) == name }
            if !g.isEmpty {
                out.append(MemoGroup(id: name, title: name,
                                     memos: g))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(library.timing)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !library.notice.isEmpty {
                        Text(library.notice)
                            .font(.system(size: 11,
                                          design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.memos) { memo in
                            Button {
                                nav.editor = EditorModel(
                                    item: memo, library: library)
                            } label: {
                                VStack(alignment: .leading,
                                       spacing: 3) {
                                    Text(memo.title.isEmpty
                                        ? "无标题" : memo.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(memo.snippet)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    library.remove(memo)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    library.togglePin(memo)
                                } label: {
                                    Label(memo.pinned ? "取消置顶"
                                            : "置顶",
                                          systemImage: memo.pinned
                                            ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("此刻")
            .searchable(text: Binding(
                get: { nav.query },
                set: { nav.query = $0
                       library.search($0) }),
                prompt: "搜索")
            .toolbar {
                Menu {
                    Button {
                        nav.shareURL = library.exportZip()
                    } label: {
                        Label("导出备份 ZIP",
                              systemImage: "square.and.arrow.up")
                    }
                    Button {
                        nav.showImporter = true
                    } label: {
                        Label("导入备份 ZIP",
                              systemImage: "square.and.arrow.down")
                    }
                    Button {
                        nav.showDiag = true
                    } label: {
                        Label("诊断", systemImage: "stethoscope")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button {
                    let item = library.create()
                    nav.editor = EditorModel(
                        item: item, library: library)
                } label: {
                    Image(systemName: "plus")
                }
            }
            .fileImporter(
                isPresented: Binding(
                    get: { nav.showImporter },
                    set: { nav.showImporter = $0 }),
                allowedContentTypes: [.zip]) { result in
                if case .success(let url) = result {
                    library.importZip(from: url)
                }
            }
            .sheet(isPresented: Binding(
                get: { nav.shareURL != nil },
                set: { if !$0 { nav.shareURL = nil } })) {
                if let url = nav.shareURL {
                    ShareSheet(url: url)
                }
            }

            .navigationDestination(isPresented: Binding(
                get: { nav.editor != nil || nav.showDiag },
                set: { if !$0 {
                    nav.editor = nil
                    nav.showDiag = false
                } })) {
                if let editor = nav.editor {
                    EditorView(editor: editor)
                } else {
                    DiagView(library: library)
                }
            }
            .onAppear {
                library.markFirstFrame()
                if library.memos.isEmpty { library.load() }
            }
        }
    }
}

