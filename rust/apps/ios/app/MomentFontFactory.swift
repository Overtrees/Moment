// ── 字体缩放单源工厂（fix_dynamic_type_follow）──
// 背景：0.9.58 的 DT 全量批把字面字号换成 SwiftUI
// 语义样式 / @ScaledMetric / Marks.dynFont 三路，真
// 机（0.9.58）实报只有 @ScaledMetric 喂点跟随、语义
// 样式面与 UIKit 快照面纹丝不动；且全应用没有任何
// 内容尺寸类别变更的传播机制（无 didChange 监听、
// 无 trait 重刷），UIKit 面的字体在 attributed
// string 构建时定格、重建门只认内容变化。
//
// 本文件收口为单源：
// - FontHub：类别变更的唯一发布源——监听
//   UIContentSizeCategory.didChangeNotification
//   （UIKit 通道，不经 SwiftUI 环境），发布
//   category 与单调递增 epoch；变更记 Diag 一行，
//   下次同类回归在日志里可见。
// - FontFactory：缩放数学唯一出处——UIFontMetrics
//   以 hub 的显式 trait collection 计算（不依赖
//   调用点当时的环境 trait），UIFont 构造全应用
//   只此一处（MomentApp.capsuleHeight 的两处未缩
//   放基准字体为 DT36-1 在册白名单：缩放基准本身
//   不可缩放）。
// SwiftUI 路同账：各视图 @ScaledMetric(relativeTo:)
// 与本工厂共用 UIFontMetrics 的分样式缩放表；语
// 义样式字体已全量改走 ScaledMetric 喂点（见报告
// fix_dynamic_type_follow.md）。

import SwiftUI
import UIKit

/// 内容尺寸类别中枢：当前类别 + 变更代次（epoch）。
/// UIKit representable 面以 epoch 为字体失效键：
/// 类别一变 epoch 必增，持有快照字体的视图据此重
/// 刷（BlockTextView / MdTextGroupView 链）。
final class FontHub: ObservableObject {
    static let shared = FontHub()

    @Published private(set) var category: UIContentSizeCategory
    /// 字体代次：每次类别变更 +1。初值 0 与各视图
    /// 协调器的初始登记值（-1）恒不同，首帧即对齐
    /// 一次现行类别。
    @Published private(set) var epoch: Int = 0

    private var observer: NSObjectProtocol?

    private init() {
        category = UIApplication.shared
            .preferredContentSizeCategory
        observer = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory
                .didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            // 通知到达时应用级类别已是新值（不依
            // 赖 userInfo 键名口径）。
            let new = UIApplication.shared
                .preferredContentSizeCategory
            guard new != self.category else { return }
            self.category = new
            self.epoch += 1
            DiagLog.shared.log(
                .info,
                "FONT category -> \(new.rawValue) "
                    + "epoch=\(self.epoch)")
        }
    }

    /// 当前类别的显式 trait collection：工厂全部
    /// 缩放计算以此为准，调用点环境不参与。
    var traits: UITraitCollection {
        UITraitCollection(
            preferredContentSizeCategory: category)
    }
}

/// 缩放字体工厂：UIFontMetrics 分样式缩放表的单
/// 一消费点。SwiftUI 侧的 @ScaledMetric 与此处共
/// 用同一张系统缩放表（同账），数值口径恒一致。
enum FontFactory {
    /// 基准字号按样式缩放后的点数（SwiftUI 侧需
    /// 要纯数值时用；视图内优先 @ScaledMetric）。
    static func scaledSize(_ base: CGFloat,
                           style: UIFont.TextStyle)
        -> CGFloat {
        UIFontMetrics(forTextStyle: style)
            .scaledValue(for: base,
                         compatibleWith: FontHub.shared.traits)
    }

    /// 未缩放基准字体构造（全应用 UIFont 构造单
    /// 点）：缩放由 uiFont 的 metrics 段施加，基准
    /// 本身不带类别信息。
    static func baseFont(size: CGFloat,
                         weight: UIFont.Weight = .regular,
                         mono: Bool = false) -> UIFont {
        mono
            ? UIFont.monospacedSystemFont(ofSize: size,
                                          weight: weight)
            : UIFont.systemFont(ofSize: size,
                                weight: weight)
    }

    /// 派生等宽字体：输入已是缩放后的点数（由工厂
    /// 字体的 pointSize 派生，如公式源码回退 = 基
    /// 字 × 0.85）——不再过 metrics 二次缩放，仅
    /// 收口构造点。
    static func derivedMono(pointSize: CGFloat,
                            weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: pointSize,
                                    weight: weight)
    }

    /// 随系统缩放的 UIFont：基准字号经 UIFont-
    /// Metrics 按 style 的缩放表、以 hub 类别显式
    /// 计算——构建时机与调用点 trait 无关，类别变
    /// 更后重算即得新档（重刷触发由 FontHub.epoch
    /// 驱动，见 BlockTextView）。
    static func uiFont(size: CGFloat,
                       weight: UIFont.Weight = .regular,
                       style: UIFont.TextStyle = .body,
                       mono: Bool = false) -> UIFont {
        UIFontMetrics(forTextStyle: style)
            .scaledFont(
                for: baseFont(size: size, weight: weight,
                              mono: mono),
                compatibleWith: FontHub.shared.traits)
    }
}
