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

// ── 标题胶囊定宽 + 居中布局模型（预览态居中
// 根治，fix_title_capsule_center.md）──
// 定宽算式与居中量测的纯核心：视图（Editor-
// HeaderView.capsuleWidth）只备量测入参
// （shown 串选定、UIKit 字形宽、avail 换
// 算），算式委托本处单点，与落点映射同文件
// 同纪律（Foundation-only、宿主可测）。
//
// 居中前提（与 verify [24] 机制锁分工）：
//  P1 内距对称：胶囊 .padding(.horizontal,
//     20) 左右同值 → 标题行宽 = 胶囊宽 − 40、
//     行中心 ≡ 胶囊中心。
//  P2 行内占满与居中放置：覆盖层 frame
//     (maxWidth: .infinity) 自占行宽；字
//     段帧宽由胶囊自身定宽值派生钉死——
//     视图侧 .frame(width: 胶囊宽 − 40)
//     （fix_title_center_short_text 四
//     修）。沿革：初版按 representable
//     尺寸契约意图断言（帧宽恒 = 行宽），
//     0.9.63 真机证伪（shown 态字段有效
//     帧为内容宽且坐行左缘、短标题 ×
//     宽 meta 偏差 = (行宽 − 标题宽)/2）；
//     二修改显式弹性帧 (maxWidth:
//     .infinity) 并以 T24-10 锁其在位，
//     但弹性帧的提议经父级提议透传、决
//     定性量测仍落内容宽一档，0.9.65
//     真机复报真实短标题仍不居中——弹
//     性帧证伪。定宽帧不经协商：帧布局
//     对子视图恒以定值提议，represen-
//     table 的 sizeThatFits 决定性一读
//     必走 definite 分支回告行宽，平台
//     视图帧随之 = 行宽（桥的帧随
//     sizeThatFits 回告值一事，恰由
//     0.9.63 内容宽帧实况反证）。帧构
//     型在位由 T24-10/12 锁、实效由设
//     备探针 title_geometry 量测守。
//  P3 字形居中指令：字段 textAlignment =
//     .center、覆盖层 multilineTextAlign-
//     ment = .center。后者于居中初版补齐
//     ——此前覆盖层无任何自身居中指令，
//     字形在其全行宽帧内按缺省 .leading
//     排布（当时定性为唯一层位；字段形
//     态的帧宽前提后被真机证伪，见 P2）。
//     三修补第三呈现者（fix_title_center_
//     short）：空标题时呈现者是字段占位串
//     ——其绘制对齐只认属性串自带的段落样
//     式，textAlignment 不及；构造单点
//     （TitleTextField.applyFont）钉段落
//     样式 .center，由 T24-11 锁。前两修
//     的量测模型把量测串当呈现文本建模、
//     占位呈现者不在模型内，故 0.9.65 空
//     标题截图（偏差 −14.7pt）能逃过
//     T24-8/T24-9/T24-10 全部断言。
// P1–P3 成立时文本中心 ≡ 胶囊中心。偏差模
// 型（inkCenterDeviation）以字段帧构型为入
// 参、不预设排布：喂定宽帧构型归 0、喂坏构
// 型（内容宽帧坐行左缘）复现设备实测偏差
// ——宿主断言（verify T24-9）以此双向锁模
// 型；构型本身由 T24-10/12 结构锁与设备探
// 针守（四修改判：旧 centerDeviation 把居
// 中原点写死进算式、偏差按定义恒 0 自证，
// 已废除）。
enum TitleCapsuleLayout {

    /// 横内距（单侧）：与视图 .padding
    /// (.horizontal, 20) 同值（Web .editor-
    /// title-dock padding 0 20px 口径）。
    static let hPad: Double = 20

    /// 定宽公式（Web sync_width，AUD-B-02
    /// 对齐）：max(标题宽, meta 宽) + 内距 40
    /// + 边框 1，钳 [66, max(avail, 66)]。
    /// titleW / metaW 为视图以呈现同源属性
    /// 量得的宽；avail 为坞口径可用宽（未钳
    /// 下限的原值）。
    static func capsuleWidth(
        titleW: Double, metaW: Double,
        avail: Double
    ) -> Double {
        min(max(max(titleW, metaW) + 41, 66),
            max(avail, 66))
    }

    /// 居中模型下文本中心 x（胶囊坐标系）：
    /// 前提 P1–P3 下恒为胶囊中心。
    static func textCenterX(
        capsuleWidth: Double
    ) -> Double {
        capsuleWidth / 2
    }

    /// 字段帧宽（行宽）：胶囊宽 − 左右内距。
    /// 视图侧字段定宽帧与落点映射的 rowW 同
    /// 出此式（两处代码以胶囊宽 − 40 字面同
    /// 源，T24-12 跨点一致性锁守）。
    static func fieldFrameWidth(
        capsuleWidth: Double
    ) -> Double {
        capsuleWidth - 2 * hPad
    }

    /// 字形块中心偏差（帧链模型）：入参是字
    /// 段帧构型（原点 x 与宽，胶囊坐标系）——
    /// 字形块在字段帧内按居中语义排布（字段
    /// textAlignment .center / 占位段落样式
    /// .center 的 UIKit 语义：块宽 ≤ 帧宽时
    /// 块居帧中、超宽时充满帧），故块中心恒
    /// = 帧中心，偏差 = |帧中心 − 胶囊中心|，
    /// 与文本宽无关。本式不预设构型：构型是
    /// 外部输入（设备实测或构造设定），喂定
    /// 宽帧构型（原点 = hPad、帧宽 = 行宽）
    /// 归 0；喂 0.9.63/0.9.65 设备坏构型
    /// （原点 = hPad、帧宽 = 内容进距宽）复
    /// 现实测偏差（容差含墨迹/进距口径差）。
    /// 旧 centerDeviation 把居中原点写死进
    /// 算式（originX 按居中排布构造）、偏差
    /// 恒 0 自证，四修废除并由本式取代。
    static func inkCenterDeviation(
        capsuleWidth: Double,
        fieldFrameX: Double,
        fieldFrameWidth: Double
    ) -> Double {
        let frameCenter = fieldFrameX
            + fieldFrameWidth / 2
        return abs(frameCenter - textCenterX(
            capsuleWidth: capsuleWidth))
    }
}
