// Moment 原生阶段 2 首版：SwiftUI + moment-ffi（Rust Core）。
// 列表（日期分组/搜索/置顶/删除/新建）+ 块编辑器（段落/
// 标题/todo 可编辑、长按拖拽重排、块增删、自动存回）。
// 已知 v1 简化（后续轮处理）：编辑文本块时 children 归一为
// 单文本节点（行内标记待保真轮）；图片等非文本块只读占位；
// ZIP 导入导出与 Diag 页未入本版。
// 工具链口径：@State 的 $ 投影不可用，状态一律走
// ObservableObject + 显式 Binding（见 spike/SPIKE.md）。
import SwiftUI
import UIKit

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

    var type: String { node["type"] as? String ?? "paragraph" }
    var isText: Bool {
        type == "paragraph" || type == "heading" || type == "todo"
    }
    var level: Int {
        (node["attrs"] as? [String: Any])?["level"] as? Int ?? 2
    }

    init(node: [String: Any]) {
        self.node = node
        id = node["id"] as? String ?? UUID().uuidString
        let kids = node["children"] as? [[String: Any]] ?? []
        text = kids.compactMap { $0["text"] as? String }.joined()
        let attrs = node["attrs"] as? [String: Any]
        checked = attrs?["checked"] as? Bool ?? false
        if type == "heading" { height = 34 }
    }

    func flushedNode() -> [String: Any] {
        var n = node
        if isText {
            n["children"] = [["text": text]]
            if type == "todo" {
                var attrs = n["attrs"] as? [String: Any] ?? [:]
                attrs["checked"] = checked
                n["attrs"] = attrs
            }
        }
        return n
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
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let lib = try MomentLibrary.open(
                    path: self.storeDir + "/moment.db")
                self.lib = lib
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
        applyFont(tv)
        tv.text = block.text
        recalc(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != block.text && tv.markedTextRange == nil {
            tv.text = block.text
            recalc(tv)
        }
    }

    private func applyFont(_ tv: UITextView) {
        switch block.type {
        case "heading":
            let size: CGFloat = block.level <= 1 ? 24
                : block.level == 2 ? 20 : 18
            tv.font = .systemFont(ofSize: size, weight: .bold)
        default:
            tv.font = .systemFont(ofSize: 17)
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
        init(_ p: BlockTextView) { parent = p }
        func textViewDidChange(_ tv: UITextView) {
            parent.block.text = tv.text
            parent.recalc(tv)
            parent.onChange()
        }
    }
}

// ── 编辑器 ─────────────────────────────────────────
final class EditorModel: ObservableObject {
    @Published var title: String
    @Published var blocks: [BlockState]
    @Published var draggingId: String?
    @Published var dragDy: CGFloat = 0
    let item: MemoItem
    private let library: Library
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
            if block.isText {
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
        .background(.background,
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
                Button {
                    editor.addBlock()
                } label: {
                    Label("添加段落", systemImage: "plus.circle")
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { editor.saveNow() }
    }
}

// ── 列表 ───────────────────────────────────────────
struct ListView: View {
    @ObservedObject var library: Library
    @StateObject private var nav = NavState()

    final class NavState: ObservableObject {
        @Published var editor: EditorModel?
        @Published var query = ""
    }

    var visibleMemos: [MemoItem] {
        guard let hits = library.searchHits else {
            return library.memos
        }
        return library.memos.filter { hits.contains($0.id) }
    }

    var groups: [(String, [MemoItem])] {
        let pinned = visibleMemos.filter { $0.pinned }
        let rest = visibleMemos.filter { !$0.pinned }
        var out: [(String, [MemoItem])] = []
        if !pinned.isEmpty { out.append(("置顶", pinned)) }
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
            if !g.isEmpty { out.append((name, g)) }
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
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { memo in
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
                Button {
                    let item = library.create()
                    nav.editor = EditorModel(
                        item: item, library: library)
                } label: {
                    Image(systemName: "plus")
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { nav.editor != nil },
                set: { if !$0 { nav.editor = nil } })) {
                if let editor = nav.editor {
                    EditorView(editor: editor)
                }
            }
            .onAppear {
                library.markFirstFrame()
                if library.memos.isEmpty { library.load() }
            }
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
