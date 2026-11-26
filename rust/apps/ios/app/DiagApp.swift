// 阶段 2 启动闪退定位梯子（临时诊断包，定案后删）：
// 根 = 已在真机证明可跑的极简列表，四个探针页逐个点：
// 哪个点开崩，陷阱就在哪个子树。全部用未开库的 Library
// （FFI 调用走 nil 安全路径），与数据/开库无关。
import SwiftUI

struct DiagRoot: View {
    @StateObject private var library = Library()

    var sampleItem: MemoItem {
        MemoItem(
            id: "sample", title: "样本", pinned: false,
            createdAt: "2026-11-26T00:00:00.000Z",
            updatedAt: "2026-11-26T00:00:00.000Z",
            blocks: [
                ["id": "s1", "type": "heading",
                 "attrs": ["level": 2],
                 "children": [["text": "标题块"]]],
                ["id": "s2", "type": "paragraph",
                 "children": [["text": "正文 "],
                              ["text": "加粗", "bold": true],
                              ["id": "s2l", "type": "link",
                               "attrs": ["url":
                                   "https://example.com"],
                               "children": [["text": "链接"]]]]],
                ["id": "s3", "type": "todo",
                 "attrs": ["checked": true],
                 "children": [["text": "待办"]]],
                ["id": "s4", "type": "image",
                 "attrs": ["fileId": "att-missing"],
                 "children": []],
                ["id": "s5", "type": "gallery",
                 "attrs": ["items": [["fileId": "att-missing"]]],
                 "children": []],
                ["id": "s6", "type": "musicCard",
                 "attrs": ["title": "歌", "artist": "手"],
                 "children": []],
                ["id": "s7", "type": "divider",
                 "children": []],
                ["id": "s8", "type": "quote",
                 "children": [["text": "引用"]]],
                ["id": "s9", "type": "callout",
                 "children": [["text": "提示"]]],
                ["id": "s10", "type": "imgTextCard",
                 "attrs": ["fileId": "att-missing"],
                 "children": [["text": "图文"]]],
            ].map { BlockState(node: $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("1 · 纯文本（对照）") {
                    Text("ok")
                }
                NavigationLink("2 · 真实列表页") {
                    ListView(library: library)
                }
                NavigationLink("3 · 编辑器样本页") {
                    EditorView(editor: EditorModel(
                        item: sampleItem, library: library))
                }
                NavigationLink("4 · 诊断页") {
                    DiagView(library: library)
                }
            }
            .navigationTitle("定位梯子")
        }
    }
}

@main
struct DiagApp: App {
    var body: some Scene {
        WindowGroup { DiagRoot() }
    }
}
