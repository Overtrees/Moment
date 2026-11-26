// 阶段 1 spike — Web 壳：WKWebView + moment:// scheme
// handler 加载包内 Web dist（与生产同一构建），验证三判据
// 中的 Web 路线基线：冷启（原生侧三段打点上屏）、拼音组字
// （即现行 Web 编辑器本身）、存储可用性（OPFS 探测上屏）。
import SwiftUI
import WebKit

enum LaunchClock {
    static let t0 = ProcessInfo.processInfo.systemUptime
    static func ms() -> Int {
        Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
    }
}

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let mime: [String: String] = [
        "html": "text/html", "js": "text/javascript",
        "wasm": "application/wasm", "css": "text/css",
        "json": "application/json", "png": "image/png",
        "svg": "image/svg+xml", "txt": "text/plain",
    ]

    func webView(_ webView: WKWebView,
                 start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        var rel = url.path
        if rel == "/" || rel.isEmpty { rel = "/index.html" }
        let fileURL = Bundle.main.bundleURL
            .appendingPathComponent("web" + rel)
        guard let data = try? Data(contentsOf: fileURL) else {
            let resp = HTTPURLResponse(url: url, statusCode: 404,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
            urlSchemeTask.didReceive(resp)
            urlSchemeTask.didReceive(Data())
            urlSchemeTask.didFinish()
            return
        }
        let ext = fileURL.pathExtension.lowercased()
        let resp = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": SchemeHandler.mime[ext]
                    ?? "application/octet-stream",
                "Content-Length": String(data.count),
                "Cross-Origin-Opener-Policy": "same-origin",
                "Cross-Origin-Embedder-Policy": "require-corp",
                "Cross-Origin-Resource-Policy": "same-origin",
            ])!
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView,
                 stop urlSchemeTask: WKURLSchemeTask) {}
}

final class NavDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebShellModel

    func makeCoordinator() -> NavDelegate {
        let d = NavDelegate()
        d.onFinish = { [weak model] in model?.didFinish() }
        return d
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: "moment")
        // JavaScript 默认启用（27.2 接口无 allowsContentJavaScript
        // 配置项，WKPreferences.javaScriptEnabled 已弃用且默认开）
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        model.webView = wv
        wv.load(URLRequest(url: URL(string: "moment://app/index.html")!))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class WebShellModel: ObservableObject {
    @Published var status = "启动中…"
    weak var webView: WKWebView?
    private var finished = false

    func didFinish() {
        guard !finished else { return }
        finished = true
        let navMs = LaunchClock.ms()
        // 页面侧口径：performance.now()（导航起点→当前）+
        // OPFS 可用性探测，结果一并上屏供真机判读截图。
        let js = """
        (async () => {
          let opfs = 'unknown';
          try {
            await navigator.storage.getDirectory();
            opfs = 'OPFS 可用';
          } catch (e) {
            opfs = 'OPFS 不可用: ' + (e.name || 'err');
          }
          return 'page ' + Math.round(performance.now()) + 'ms · ' + opfs;
        })()
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.webView?.evaluateJavaScript(js) { result, _ in
                let page = (result as? String) ?? "page ?"
                self.status = "冷启 原生 \(navMs)ms · \(page)"
            }
        }
    }
}

@main
struct WebShellApp: App {
    @StateObject private var model = WebShellModel()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                WebView(model: model)
                    .ignoresSafeArea()
                Text(model.status)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
            }
        }
    }
}
