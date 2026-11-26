import SwiftUI

/// Moment 原生阶段 0 探针壳：启动后在后台线程对应用支持
/// 目录跑 FFI 自检链（runPhase0Checks：建库 → 写入 →
/// 读回 → FTS 检索 → ZIP 导出 → 另一库导入 → 哈希对账
/// → 删除），报告原文整页展示，真机判读末行
/// PHASE0 ALL PASS。
@main
struct MomentPhase0App: App {
    var body: some Scene {
        WindowGroup {
            Phase0View()
        }
    }
}

final class Phase0Model: ObservableObject {
    @Published var report = "自检运行中…"

    func run() {
        DispatchQueue.global(qos: .userInitiated).async {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0]
            let dir = base.appendingPathComponent("phase0", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let text = runPhase0Checks(dir: dir.path)
            DispatchQueue.main.async { self.report = text }
        }
    }
}

struct Phase0View: View {
    @StateObject private var model = Phase0Model()

    var body: some View {
        ScrollView {
            Text(model.report)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .onAppear { model.run() }
    }
}
