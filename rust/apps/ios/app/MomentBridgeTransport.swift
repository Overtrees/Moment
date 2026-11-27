// ── MCP 桥传输层（M1；稳定性重写
// fix_bridge_stability）──
// App 出站 WSS 长连接（URLSessionWebSocketTask）：
// 只负责连接/收发/存活原始事件，控制帧语义（挑
// 战应答/心跳/在场）与 JSON-RPC 分发归协调器。
// iOS 无后台长连接：进后台系统挂起 socket，本层
// 不假装在线——断开即经 onSocketDown 上报，协调
// 器转 backoff/离线语义。
//
// 代次（generation）纪律：每次 connect/close 都
// 递增代次，所有 task 回调（receive/send 完成）
// 捕获所属代次与 task 本体，迟到回调先验代次、
// 不符即静默丢弃。旧实现无代次概念：connect 里
// cancel 旧 task 后，其挂起的 receive 以错误迟到
// 完成时只看共享 isOpen（已被新连接置真），会把
// 新连接误判 down 并把 task 引用置 nil——新
// socket 在中继侧连着、挑战帧也收得到，却永远
// 发不出应答（send 的 guard 先失败），形成「中
// 继见 socket 在、App 永不应答」的僵尸连接，且
// 每次重连都有概率复发、自持成环。本重写以代次
// 作用域整体替换该记账方式，不留特判。

import Foundation

final class BridgeWssTransport {
    /// 收到一帧文本（任意线程，协调器自行切主线）。
    var onText: ((String) -> Void)?
    /// socket 断开（仅当前代连接的真实失败才触
    /// 发，reason = receive_error | send_error；
    /// 主动 close 的代次被代次校验吞掉，不触发）。
    var onSocketDown: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiving = false
    private var generation = 0
    private(set) var isOpen = false

    func connect(pairingId: String) {
        close()
        generation += 1
        let gen = generation
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
        isOpen = true
        t.resume()
        receiveLoop(gen: gen, task: t)
    }

    /// 关当前代并使其全部在途回调失效（代次递
    /// 增）。suppressNotify 形参保留旧签名兼容调用
    /// 点：代次语义下主动关闭本就不产生 onSocketDown。
    func close(suppressNotify: Bool = false) {
        generation += 1
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
        let gen = generation
        task.send(.string(text)) { [weak self] error in
            if error != nil {
                self?.handleDown(gen: gen,
                                 reason: "send_error")
            }
        }
        return true
    }

    private func receiveLoop(gen: Int,
                             task: URLSessionWebSocketTask) {
        guard gen == generation, !receiving else { return }
        receiving = true
        task.receive { [weak self] result in
            guard let self else { return }
            // 旧代迟到回调：不碰新连接的任何状态。
            guard gen == self.generation else { return }
            self.receiving = false
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.onText?(text)
                }
                // 二进制帧不在协议内，忽略后续行。
                if self.isOpen {
                    self.receiveLoop(gen: gen, task: task)
                }
            case .failure:
                self.handleDown(gen: gen,
                                reason: "receive_error")
            }
        }
    }

    private func handleDown(gen: Int, reason: String) {
        guard gen == generation, isOpen else { return }
        isOpen = false
        receiving = false
        task = nil
        onSocketDown?(reason)
    }
}
