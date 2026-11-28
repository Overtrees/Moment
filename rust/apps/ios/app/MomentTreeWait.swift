import UIKit

// ── 入树等待共享工具（补丁债偿还批一 A-5）────────
// 「等视图/目标入树」此前三处各写一份定时重试：
// 转场宿主等导航探针登记（0.05s×20）、首页滚动
// 探针等滚动视图入子树（0.05s×20）、拖拽锚点等
// 祖先滚动视图（单次主队列异步重试）——参数同
// 而实现异、三链首帧可靠性各自为政（audit_patch
// _debt A-5）。本工具收口为单一机制：等待者以
// （条件 + 动作 + 到期回调）注册，由一枚
// CADisplayLink 逐帧复查。复查节拍与布局生产
// 同源——视图入树必发生在帧生产过程中，无帧
// 即无入树、链自动闲置不空转；条件满足即执行
// 动作并注销，到期（deadline，秒）未满足则执
// 行 onTimeout 并注销。到期语义归各消费点自持
// （留痕放弃 / 静默降级不一，本工具不代决）。
// 条件与动作恒在主队列执行（DisplayLink 挂主
// runloop .common 模式）。

final class ViewTreeWait: NSObject {
    static let shared = ViewTreeWait()

    struct Token: Hashable {
        let raw = UUID()
    }

    private struct Entry {
        let token: Token
        let expiry: CFAbsoluteTime
        let condition: () -> Bool
        let action: () -> Void
        let onTimeout: (() -> Void)?
    }

    private var entries: [Entry] = []
    private var link: CADisplayLink?

    /// 注册一次性等待。注册当下不复查（调用方
    /// 恒先行即时尝试、失败才注册），首查在下
    /// 一帧；同批注册的等待按注册序逐个裁决。
    @discardableResult
    func wait(deadline: TimeInterval = 1.0,
              condition: @escaping () -> Bool,
              action: @escaping () -> Void,
              onTimeout: (() -> Void)? = nil) -> Token {
        let token = Token()
        entries.append(Entry(
            token: token,
            expiry: CFAbsoluteTimeGetCurrent() + deadline,
            condition: condition,
            action: action,
            onTimeout: onTimeout))
        if link == nil {
            let l = CADisplayLink(
                target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        return token
    }

    /// 注销等待（消费点生命周期收口：视图离窗、
    /// 或目标已由他路达成时调用）。
    func cancel(_ token: Token) {
        entries.removeAll { $0.token == token }
        stopLinkIfIdle()
    }

    @objc private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        var ready: [Entry] = []
        var expired: [Entry] = []
        entries = entries.filter { e in
            if e.condition() {
                ready.append(e)
                return false
            }
            if now >= e.expiry {
                expired.append(e)
                return false
            }
            return true
        }
        stopLinkIfIdle()
        for e in ready { e.action() }
        for e in expired { e.onTimeout?() }
    }

    private func stopLinkIfIdle() {
        if entries.isEmpty {
            link?.invalidate()
            link = nil
        }
    }
}
