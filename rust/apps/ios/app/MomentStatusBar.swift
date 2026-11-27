import Foundation

// ── 状态栏字色·背景采样纯核心（fix_statusbar_sampling）──
// 用户 2026-11-27 22:30 定案口径：状态栏字色不许恒
// 白/恒黑、也不许只按外观 trait 固定映射——按状态栏
// 后方当前生效的背景色采样、相对亮度决定字色（深底
// 白字/浅底黑字），全局各页一致（增强机制）。本文件
// 只做纯数值决策（亮度/阈值/判定），不碰 UIKit：采
// 样与送达在 MomentStatusBarBridge.swift；决策无状态
// ——同一输入在任意调用序列下恒同输出，结构性无闩锁
// （闩锁成因与决定链见 docs/reports/diag_statusbar_
// dark.md、采样源逐页清单见 fix_statusbar_sampling
// .md）。
enum StatusBarCore {
    /// 决策阈值：WCAG 对比度公式下白字与黑字对比度
    /// 相等的那一点——(L+0.05)² = 1.05×0.05 解得
    /// L = √0.0525 − 0.05 ≈ 0.1791，即「哪种字色对比
    /// 度更高」的决策中点：背景亮度低于它时白字对比
    /// 度占优、高于它时黑字占优。取舍账（全调色板计
    /// 算表）在 fix_statusbar_sampling.md §三：根背景
    /// 两值（0.891/0）与备忘八色浅色形态（0.75–0.89）
    /// 远离阈值、判定稳健；八色深色形态（×0.55 压
    /// 暗后 0.20–0.24）落在阈值上方近旁，按对比度口
    /// 径黑字占优（CR 5.0–5.7 对白字 3.7–4.2）——采
    /// 样机制的应然结果，不是 trait 一致性问题。
    static let luminanceThreshold: Double = 0.1791

    /// sRGB 分量线性化（WCAG 相对亮度定义式）。
    static func linearized(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92
            : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG 相对亮度（入参为 0...1 的 sRGB 分量）。
    static func relativeLuminance(r: Double, g: Double,
                                  b: Double) -> Double {
        0.2126 * linearized(r)
            + 0.7152 * linearized(g)
            + 0.0722 * linearized(b)
    }

    /// 深底用白字（.lightContent）当且仅当相对亮度
    /// 低于阈值。纯函数：无缓存、无历史，往返切换
    /// （深→浅→深）逐次现算、恒回初值。
    static func prefersLightContent(r: Double, g: Double,
                                    b: Double) -> Bool {
        relativeLuminance(r: r, g: g, b: b)
            < luminanceThreshold
    }
}
