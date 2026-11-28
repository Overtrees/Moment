import Foundation

// ── 状态栏字色·背景采样纯核心（fix_statusbar_sampling）──
// 用户 2026-11-27 22:30 定案口径：状态栏字色不许恒
// 白/恒黑、也不许只按外观 trait 固定映射——按状态栏
// 后方当前生效的背景色采样、感知明暗决定字色（深底
// 白字/浅底黑字），全局各页一致（增强机制）。本文件
// 只做纯数值决策（感知亮度/阈值/判定/带区几何/渐变
// 采样），不碰 UIKit：判定与送达在 MomentStatusBar
// Bridge.swift、带区实渲染采样在 MomentStatusBar
// Render.swift（三轮统一采样器，含图片带区几何覆
// 盖率）；决策无状态——同一输入在任意调用序列
// 下恒同输出，结构性无闩锁（闩锁成因与决定链见
// docs/reports/diag_statusbar_dark.md、采样源逐页清
// 单见 fix_statusbar_sampling.md、二轮动态化见
// fix_statusbar_dynamic.md、三轮渲染收口见
// fix_statusbar_render_sample.md）。
enum StatusBarCore {
    /// 决策阈值（CIELAB L*）：二轮根治（fix_statusbar
    /// _dynamic）换感知亮度——旧 WCAG 相对亮度阈值
    /// 0.1791 是「哪种字色对比度更高」的比率中点，
    /// 对高饱和蓝感知失真：开屏品牌蓝带区实色
    /// (52,146,243) 的 WCAG Y=0.278 被判浅底黑字，
    /// 与用户感知（深色类）及开屏 artwork 自身白字
    /// 标语的设计判定双双相悖（用户 2026-11-28 实
    /// 报）。新阈值推导：L* 是 CIE 感知明度（用户口
    /// 径「实际感知明暗」的度量本体）；分界取白字
    /// WCAG 对比度恰 3.0（大字/图形级下限）的那一
    /// 点——1.05/(Y+0.05) = 3 解得 Y = 0.30，换算
    /// L* = 116·0.30^(1/3) − 16 ≈ 61.65：感知明度
    /// 低于它（白字仍保 3:1 可读）的表面归深色类用
    /// 白字、高于它用黑字。全色表（品牌蓝/渐变带区/
    /// 根背景/备忘八色双形态/灰阶边界）由 verify
    /// [53] SB-2 表驱动锁定，账目见 fix_statusbar_
    /// dynamic.md §二。
    static let lightnessThreshold: Double = 61.65

    /// sRGB 分量线性化（WCAG 相对亮度定义式）。
    static func linearized(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92
            : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG 相对亮度（入参为 0...1 的 sRGB 分量）：
    /// 现为 L* 的中间量（Y），不再直接作判定面。
    static func relativeLuminance(r: Double, g: Double,
                                  b: Double) -> Double {
        0.2126 * linearized(r)
            + 0.7152 * linearized(g)
            + 0.0722 * linearized(b)
    }

    /// CIELAB L*（D65，Yn=1）：由相对亮度 Y 经 CIE
    /// 立方根分段函数换算的感知明度，0（黑）–100
    /// （白）。δ=6/29 分段点与斜率按 CIE 15 定义。
    static func labLightness(y: Double) -> Double {
        let d = 6.0 / 29.0
        let f = y > d * d * d
            ? pow(y, 1.0 / 3.0)
            : y / (3 * d * d) + 4.0 / 29.0
        return 116 * f - 16
    }

    /// 颜色的感知明度 L*（入参为 0...1 的 sRGB 分量）。
    static func lightness(r: Double, g: Double,
                          b: Double) -> Double {
        labLightness(y: relativeLuminance(
            r: r, g: g, b: b))
    }

    /// 深底用白字（.lightContent）当且仅当感知明度
    /// 低于阈值。纯函数：无缓存、无历史，往返切换
    /// （深→浅→深）逐次现算、恒回初值。
    static func prefersLightContent(r: Double, g: Double,
                                    b: Double) -> Bool {
        lightness(r: r, g: g, b: b)
            < lightnessThreshold
    }

    /// 已采样感知明度的判定（图片带区像素采样等外
    /// 部已算出 L* 的路径与颜色路径共用同一阈值）。
    static func prefersLightContent(
        lightness: Double) -> Bool {
        lightness < lightnessThreshold
    }

    // ── 带区几何（纯函数，Double 矩形）────────────
    // 图片页动态采样：带区矩形与图片可见矩形（均
    // 为 window 坐标）求交叠覆盖率；覆盖部分取图
    // 像感知明度、未覆盖部分取根背景感知明度，覆
    // 盖率线性合成即带区有效明度（模型见 fix_
    // statusbar_dynamic.md §三；像素侧的实际合成
    // 由生效层渲染带区条带完成，本组函数为其几何
    // 账与断言面）。

    struct SBRect {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var area: Double { max(w, 0) * max(h, 0) }
    }

    static func intersection(_ a: SBRect, _ b: SBRect)
        -> SBRect {
        let x0 = max(a.x, b.x), y0 = max(a.y, b.y)
        let x1 = min(a.x + a.w, b.x + b.w)
        let y1 = min(a.y + a.h, b.y + b.h)
        return SBRect(x: x0, y: y0,
                      w: max(x1 - x0, 0),
                      h: max(y1 - y0, 0))
    }

    /// 内容矩形对带区的覆盖率（0...1）：交叠面积
    /// 占带区面积之比；带区面积为零时回 0。
    static func coverage(band: SBRect, content: SBRect)
        -> Double {
        guard band.area > 0 else { return 0 }
        let c = intersection(band, content).area
            / band.area
        return min(max(c, 0), 1)
    }

    /// 有效明度合成：覆盖部分取内容明度、其余取
    /// 背景明度，按覆盖率线性混合（L* 空间）。
    static func blendedLightness(coverage: Double,
                                 content: Double,
                                 background: Double)
        -> Double {
        let c = min(max(coverage, 0), 1)
        return c * content + (1 - c) * background
    }

    // ── 线性渐变采样（纯函数）────────────────────
    // 开屏背景为源画布坐标系内的线性渐变：带区实
    // 色 = 渐变在带区对应源矩形内的平均色。本组
    // 函数与 NativeSplashCanvas 的绘制同式（cover
    // 缩放 + 居中平移 + 轴投影插值），供承载层在
    // 查询时现算、宿主单测以资源原表锁定。

    struct SBStop {
        var offset: Double
        var r: Double
        var g: Double
        var b: Double
    }

    /// 渐变在源坐标点 (px, py) 的颜色：点投影到
    /// start→end 轴得 t（钳 [0,1]），相邻 stops
    /// 线性插值；stops 空回黑、单 stop 回其色、轴
    /// 退化（起终点重合）回首 stop。
    static func gradientColor(
        stops: [SBStop],
        start: (x: Double, y: Double),
        end: (x: Double, y: Double),
        atX px: Double, atY py: Double)
        -> (r: Double, g: Double, b: Double) {
        guard let first = stops.first else {
            return (0, 0, 0)
        }
        guard stops.count > 1 else {
            return (first.r, first.g, first.b)
        }
        let ax = end.x - start.x, ay = end.y - start.y
        let l2 = ax * ax + ay * ay
        var t = 0.0
        if l2 > 0 {
            t = ((px - start.x) * ax
                + (py - start.y) * ay) / l2
            t = min(max(t, 0), 1)
        }
        for i in 0..<(stops.count - 1) {
            let s0 = stops[i], s1 = stops[i + 1]
            if t <= s1.offset || i == stops.count - 2 {
                let span = s1.offset - s0.offset
                let f = span > 0
                    ? min(max((t - s0.offset) / span, 0), 1)
                    : 0
                return (s0.r + (s1.r - s0.r) * f,
                        s0.g + (s1.g - s0.g) * f,
                        s0.b + (s1.b - s0.b) * f)
            }
        }
        let last = stops[stops.count - 1]
        return (last.r, last.g, last.b)
    }

    /// 带区平均色：视图 (viewW × viewH) 内高 bandH
    /// 的顶部带区，按 cover 变换（scale = max(视
    /// 图/源) + 居中）映射回源坐标，网格采样渐变
    /// 取平均。与 NativeSplashCanvas 的背景填充
    /// 变换逐项同式（canvasScale/平移同源）。
    static func bandAverageColor(
        stops: [SBStop],
        start: (x: Double, y: Double),
        end: (x: Double, y: Double),
        sourceW: Double, sourceH: Double,
        viewW: Double, viewH: Double,
        bandH: Double)
        -> (r: Double, g: Double, b: Double) {
        guard viewW > 0, viewH > 0, bandH > 0,
              sourceW > 0, sourceH > 0 else {
            return gradientColor(
                stops: stops, start: start, end: end,
                atX: start.x, atY: start.y)
        }
        let scale = max(viewW / sourceW,
                        viewH / sourceH)
        let offX = (viewW - sourceW * scale) / 2
        let offY = (viewH - sourceH * scale) / 2
        let cols = 12, rows = 4
        var sr = 0.0, sg = 0.0, sb = 0.0
        for i in 0..<cols {
            for j in 0..<rows {
                let vx = (Double(i) + 0.5)
                    / Double(cols) * viewW
                let vy = (Double(j) + 0.5)
                    / Double(rows) * bandH
                let c = gradientColor(
                    stops: stops, start: start, end: end,
                    atX: (vx - offX) / scale,
                    atY: (vy - offY) / scale)
                sr += c.r; sg += c.g; sb += c.b
            }
        }
        let n = Double(cols * rows)
        return (sr / n, sg / n, sb / n)
    }
}
