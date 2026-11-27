// ── MCP 桥传输层（M1）──
// App 出站 WSS 长连接（URLSessionWebSocketTask）：
// 只负责连接/收发/存活原始事件，控制帧语义（挑
// 战应答/心跳/在场）与 JSON-RPC 分发归协调器。
// iOS 无后台长连接：进后台系统挂起 socket，本层
// 不假装在线——断开即经 onSocketDown 上报，协调
// 器转 backoff/离线语义。

import Foundation

final class BridgeWssTransport {
    /// 收到一帧文本（任意线程，协调器自行切主线）。
    var onText: ((String) -> Void)?
    /// socket 断开（对端关闭/网络错/主动 close 后
    /// 的收尾回调不触发——见 close 的 suppress 标记）。
    var onSocketDown: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiving = false
    private var suppressDown = false
    private(set) var isOpen = false

    func connect(pairingId: String) {
        close(suppressNotify: true)
        var comps = URLComponents()
        comps.scheme = "wss"
        comps.host = BridgeProto.relayHost
        comps.path = "/app/connect"
        comps.queryItems = [
            URLQueryItem(name: "pid", value: pairingId),
        ]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let t = URLSession.shared.webSocketTask(with: req)
        task = t
        suppressDown = false
        isOpen = true
        t.resume()
        receiveLoop()
    }

    func close(suppressNotify: Bool = false) {
        suppressDown = suppressNotify
        receiving = false
        isOpen = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    /// 发一帧文本；超 1MiB 帧上限直接丢弃并回报
    /// false（调用方记 Diag）。
    @discardableResult
    func send(_ text: String) -> Bool {
        guard let task, isOpen else { return false }
        guard text.utf8.count <= BridgeProto.maxFrameBytes
        else { return false }
        task.send(.string(text)) { [weak self] error in
            if error != nil {
                self?.handleDown()
            }
        }
        return true
    }

    func sendPing() {
        task?.sendPing { _ in }
    }

    private func receiveLoop() {
        guard let task, !receiving else { return }
        receiving = true
        task.receive { [weak self] result in
            guard let self else { return }
            self.receiving = false
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.onText?(text)
                }
                // 二进制帧不在协议内，忽略后续行。
                if self.isOpen { self.receiveLoop() }
            case .failure:
                self.handleDown()
            }
        }
    }

    private func handleDown() {
        guard isOpen else { return }
        isOpen = false
        receiving = false
        task = nil
        if !suppressDown {
            onSocketDown?()
        }
    }
}
