// ── 标题截断点按落点映射（审计 B-4，方案
// plan_title_tap_caret.md）──
// 映射核心抽为 Foundation-only 纯函数：不碰
// UIKit 量测（量测在调用点以呈现同源属性集完
// 成后把逐前缀宽喂进来），使数值表可在 tree 上
// 以 swiftc 独立编译真跑断言（verify [26]）。
// 算式与 Web title_controller.rs 的
// tap_caret_target 同式：显示串居中 → 相对偏移
// → 逐前缀最近边界；落在省略号上/后 → 全文末
// 尾。标量口径全程（Web chars() 同义）。

import Foundation

enum TitleTapCaret {

    /// 显示串标量数：截断显示恒为前 10 标量 + 省
    /// 略号 = 11（Web display_title_of 口径）。
    static let displayScalarCount = 11

    /// 落点映射：返回全文中的标量位（0...全文标
    /// 量数）。
    /// - fullScalarCount：全文标量数（>10 才有截
    ///   断态；调用点已按介入条件把关，本函数只
    ///   做算式）。
    /// - prefixWidths：显示串逐前缀宽（下标 b-1
    ///   = 前 b 个标量的宽，共 11 个），量测属性
    ///   集须与呈现同源（方案 P2）。
    /// - tapX：点按 x（覆盖层坐标系，原点在标题
    ///   行左缘）；rowW：标题行宽（胶囊宽 − 40）。
    /// 前缀宽弱单调（kern 在零宽标量处可有 ≤0.2pt
    /// 局部回退），故全扫 11 个前缀取最近，不沿
    /// 用 Web 的提前退出优化（方案 P4）。同距时
    /// 取较后边界——方案 §5.2 期望表据此定（省
    /// 略号中心 → 全文末尾）。
    static func caretScalarIndex(
        fullScalarCount: Int,
        prefixWidths: [Double],
        tapX: Double, rowW: Double
    ) -> Int {
        guard prefixWidths.count == displayScalarCount,
              fullScalarCount > 0 else {
            // 入参不合截断形态：不映射，落文末（与
            // Web 无记号换值落文末同向的保守缺省）。
            return max(fullScalarCount, 0)
        }
        let dispW = prefixWidths[displayScalarCount - 1]
        let startX = (rowW - dispW) / 2
        let rel = tapX - startX
        if rel <= 0 { return 0 }
        var best = 1
        var bestDist = abs(prefixWidths[0] - rel)
        for b in 2...displayScalarCount {
            let d = abs(prefixWidths[b - 1] - rel)
            if d <= bestDist {
                bestDist = d
                best = b
            }
        }
        return best <= 10 ? best : fullScalarCount
    }

    /// 标量位 → UTF-16 偏移（Web utf16_of_char
    /// 同义：前缀各标量的 UTF-16 长度和；astral
    /// 标量占 2，其余占 1）。UITextField 的
    /// position(from:offset:) 以 UTF-16 为单位
    /// （方案 P7，施加后回读比对实证锁定）。
    static func utf16Offset(
        ofScalarIndex index: Int,
        in scalars: [Unicode.Scalar]
    ) -> Int {
        var sum = 0
        for s in scalars.prefix(max(index, 0)) {
            sum += s.value > 0xFFFF ? 2 : 1
        }
        return sum
    }
}
