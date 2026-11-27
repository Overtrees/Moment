import Foundation

// ── 图片加载身份键控（fix_image_card_load）──
//
// 根因（diag_image_card_load.md）：ImageLoader 旧
// 实现以 started 布尔一次性闩锁 + 仅 onAppear 调
// 用一次——图片块/图文卡的选图流是「先出空块、
// 后经 replaceImage 原位塞 fileId」，块视图在
// fileId 为 nil 时已把闩锁打死，选图成功后
// loader 永不重跑、图片会话内永不显示。本文件
// 是键控决策的纯核心（Foundation-only、宿主单
// 测可直跑，沿 MomentUndo/MomentStatusBar 先
// 例）：loader 每次被调用都把当前源键呈给
// gate，gate 只回答「跳过 / 首载 / 重载」；实际
// 加载、发布与 Diag 归 MomentApp 的 ImageLoader
// 单点，视图侧以 onChange 钩子在键变时再呈。

/// 图片源键：fileId 与 url 两路原值（loader 内
/// 部沿既有次序选路，键只记原值供比对）。
struct ImageSourceKey: Equatable {
    var fileId: String?
    var urlString: String?

    /// 有可加载的源（两路皆 nil = 占位态）。
    var hasSource: Bool {
        fileId != nil || urlString != nil
    }

    /// Diag 描述：fid 优先、其次 url host、无源
    /// 记 none（有界标识，不拼用户正文）。
    var diagTag: String {
        if let fileId { return "fid=\(fileId)" }
        if let urlString,
           let host = URL(string: urlString)?.host {
            return "url=\(host)"
        }
        return "none"
    }
}

/// 一次呈键的裁定。
enum ImageLoadDecision: Equatable {
    /// 键未变：不重载（onAppear 重入/滚动复现
    /// 走此路，零副作用）。
    case skip
    /// 本 loader 首次呈键：照常加载。
    case start
    /// 键已变：复位已发布图与失败态后重载，
    /// 并记 IMG reload 行。
    case reload
}

/// 键控闸门（值类型、纯函数面）：当前键单点
/// 持有，比对与推进同在此，杜绝消费方各自缓存
/// 「已加载」布尔再分叉（旧 started 即此病）。
struct ImageLoadGate {
    private var current: ImageSourceKey?

    /// 当前键（loader 发布时据此做代际守卫：
    /// 旧键的在途加载回主线程时若键已变，弃其
    /// 结果、防换图后旧图回闪/覆新）。
    var currentKey: ImageSourceKey? { current }

    mutating func offer(fileId: String?,
                        urlString: String?)
        -> ImageLoadDecision {
        let key = ImageSourceKey(fileId: fileId,
                                 urlString: urlString)
        guard let cur = current else {
            current = key
            return .start
        }
        if cur == key { return .skip }
        current = key
        return .reload
    }
}
