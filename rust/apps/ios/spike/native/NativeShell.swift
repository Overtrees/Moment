// 阶段 1 spike — 原生壳：SwiftUI 列表 + UITextView 编辑。
// 数据经 moment-ffi 走 Rust Core（与 Web 同一存储），验证
// 三判据中的原生路线：拼音组字（UITextView 系统输入法）、
// 长按拖拽跟手（0.48s 拾起 + 跟手位移 + 兄弟让位）、冷启
// （首帧/数据就绪打点上屏）。
import SwiftUI
import UIKit

enum LaunchClock {
    static let t0 = ProcessInfo.processInfo.systemUptime
    static func ms() -> Int {
        Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
    }
}

struct MemoItem: Identifiable {
    let id: String
    var title: String
    var body: String
}

final class NativeModel: ObservableObject {
    @Published var memos: [MemoItem] = []
    @Published var timing = "启动中…"
    @Published var draggingId: String?
    @Published var dragDy: CGFloat = 0

    func commitDrag() {
        guard let id = draggingId,
              let from = memos.firstIndex(where: { $0.id == id })
        else { draggingId = nil; dragDy = 0; return }
        let shift = Int((dragDy / 96).rounded())
        let to = min(max(from + shift, 0), memos.count - 1)
        if to != from {
            let moved = memos.remove(at: from)
            memos.insert(moved, at: to)
        }
        draggingId = nil; dragDy = 0
    }
    private var lib: MomentLibrary?
    private var firstFrameMs: Int?

    func markFirstFrame() {
        if firstFrameMs == nil { firstFrameMs = LaunchClock.ms() }
    }

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let dir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0].appendingPathComponent("spikenative").path
            try? FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            do {
                let lib = try MomentLibrary.open(path: dir + "/lib.db")
                _ = lib
                self.lib = lib
                if try lib.memoCount() == 0 {
                    for m in Self.seeds {
                        try lib.upsertMemoJson(json: m)
                    }
                }
                let listJson = try lib.listMemosJson()
                let items = Self.parse(listJson)
                let ready = LaunchClock.ms()
                DispatchQueue.main.async {
                    self.memos = items
                    self.timing = "冷启 首帧 \(self.firstFrameMs ?? -1)ms"
                        + " · 数据就绪 \(ready)ms · \(items.count) 篇"
                }
            } catch {
                DispatchQueue.main.async {
                    self.timing = "FFI 打开失败: \(error)"
                }
            }
        }
    }

    func save(_ item: MemoItem) {
        let doc: [[String: Any]] = [[
            "id": "nb1", "type": "paragraph",
            "children": [["text": item.body]],
        ]]
        let memo: [String: Any] = [
            "id": item.id, "title": item.title, "doc": doc,
            "createdAt": "2026-11-26T04:00:00.000Z",
            "updatedAt": "2026-11-26T04:00:00.000Z",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: memo),
           let s = String(data: data, encoding: .utf8) {
            try? lib?.upsertMemoJson(json: s)
        }
        if let idx = memos.firstIndex(where: { $0.id == item.id }) {
            memos[idx] = item
        }
    }

    static func parse(_ json: String) -> [MemoItem] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data)
                as? [[String: Any]] else { return [] }
        return arr.map { m in
            var body = ""
            if let doc = m["doc"] as? [[String: Any]] {
                body = doc.compactMap { node in
                    (node["children"] as? [[String: Any]])?
                        .compactMap { $0["text"] as? String }
                        .joined()
                }.joined(separator: "\n")
            }
            return MemoItem(id: m["id"] as? String ?? UUID().uuidString,
                            title: m["title"] as? String ?? "(无标题)",
                            body: body)
        }
    }

    static let seeds: [String] = (1...8).map { i in
        """
        {"id":"spike-\(i)","title":"原生 spike 示例 \(i)",
         "createdAt":"2026-11-26T0\(i):00:00.000Z",
         "updatedAt":"2026-11-26T0\(i):00:00.000Z",
         "doc":[{"id":"sb\(i)","type":"paragraph",
           "children":[{"text":"第 \(i) 篇正文：长按卡片 0.48 秒拾起拖动排序；点开编辑页用拼音输入法组字试打。"}]}]}
        """
    }
}

// UITextView 包装：系统输入法 marked-text 组字为原生口径。
struct BodyEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 17)
        tv.text = text
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text && uiView.markedTextRange == nil {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BodyEditor
        init(_ p: BodyEditor) { parent = p }
        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }
    }
}

// 编辑态走 ObservableObject：本工具链下 @State 的 $ 投影
// 不可用（27.2 接口编出的 SwiftUI 模块），@Published /
// @ObservedObject 已实证可编（阶段 0 与 Web 壳）。
final class EditorModel: ObservableObject {
    @Published var title: String
    @Published var bodyText: String
    init(item: MemoItem) {
        title = item.title
        bodyText = item.body
    }
}

struct EditorView: View {
    @ObservedObject var model: NativeModel
    @ObservedObject var editor: EditorModel
    let memoId: String

    init(model: NativeModel, item: MemoItem) {
        self.model = model
        self.memoId = item.id
        self.editor = EditorModel(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("标题", text: Binding(
                get: { editor.title },
                set: { editor.title = $0 }))
                .font(.title3.bold())
            Text("正文（拼音组字试打区）")
                .font(.caption).foregroundStyle(.secondary)
            BodyEditor(text: Binding(
                get: { editor.bodyText },
                set: { editor.bodyText = $0 }))
                .border(Color.secondary.opacity(0.3))
            Text("组字提示：切拼音输入法，连续打一串拼音看候选与上屏；编辑会自动存回 Rust Core。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle("编辑")
        .onDisappear {
            model.save(MemoItem(id: memoId, title: editor.title,
                                body: editor.bodyText))
        }
    }
}

struct CardRow: View {
    let item: MemoItem
    let isDragging: Bool
    let dragOffset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline).lineLimit(1)
            Text(item.body).font(.subheadline)
                .foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: isDragging ? 10 : 2)
        .scaleEffect(isDragging ? 0.97 : 1)
        .offset(y: dragOffset)
        .zIndex(isDragging ? 1 : 0)
    }
}

struct ListView: View {
    @StateObject private var model = NativeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(model.timing)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                    ForEach(model.memos) { item in
                        NavigationLink {
                            EditorView(model: model, item: item)
                        } label: {
                            CardRow(
                                item: item,
                                isDragging: model.draggingId == item.id,
                                dragOffset: model.draggingId == item.id
                                    ? model.dragDy : 0)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(dragGesture(for: item))
                    }
                }
                .padding()
            }
            .navigationTitle("此刻 · 原生 spike")
            .onAppear {
                model.markFirstFrame()
                if model.memos.isEmpty { model.load() }
            }
        }
    }

    private func dragGesture(for item: MemoItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.48)
            .sequenced(before: DragGesture())
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if model.draggingId == nil {
                        model.draggingId = item.id
                    }
                    if model.draggingId == item.id {
                        model.dragDy = drag.translation.height
                    }
                default: break
                }
            }
            .onEnded { _ in
                if model.draggingId == item.id {
                    model.commitDrag()
                }
            }
    }
}

@main
struct NativeShellApp: App {
    var body: some Scene {
        WindowGroup { ListView() }
    }
}
