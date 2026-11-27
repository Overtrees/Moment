// ── 标题字段执行器（审计 B-4，方案
// plan_title_tap_caret.md 路径 B）──
// 标题胶囊的输入字段由 SwiftUI TextField 换为
// UITextField 的 UIViewRepresentable：SwiftUI
// TextField 无选区编程面，截断点按的落点映射
// 无处施加（B-4 proven）。建模照 BlockTextView
// 的 Coordinator 纪律。
//
// 分工钉死：titleFocused 的单一真相是
// TitleFieldControl.focused（普通 Bool 状态，
// 由 EditorHeaderView 持有）；本文件只做执行
// 器——true → becomeFirstResponder、false →
// resignFirstResponder，会话的开始/结束语义
// （快照/提交/Diag）经 onBeginEditing /
// onEndEditing 回到 EditorHeaderView 单点处
// 理，不在此复制第二份。
//
// 收敛律（方案 R1）：textFieldDidEndEditing 无
// 条件回写 focused = false——真实第一响应者
// 才是会话事实源，状态位与之漂移时以委托回
// 调为准合流（其提交与失焦支路等价，
// commitTitle 幂等防双重提交）。
//
// 尺寸契约（0.9.56 竖排渲染异常根治，定案
// fix_title_vertical_render.md）：representable
// 不实现 sizeThatFits 时，SwiftUI 按缺省口径
// 协商尺寸——字段成为纵向可伸缩的灵活视图。
// 胶囊内 VStack 总高恒 66：横排只有字段一行，
// 伸缩被自身居中吸收、无可见后果；竖排字段
// 行与定高的 meta 行共居 66，灵活行吞掉全部
// 余高（≈50），两行组不再成组居中——meta 被
// 顶到胶囊底边贴边、标题与 meta 间裂开大空
// 档（用户实报）。旧 SwiftUI TextField 横向灵
// 活、纵向定高，故无此象。契约钉死：宽随提
// 议（definite 时回告提议宽，与旧字段填满标
// 题行同义）、高恒回告字段自身按该宽量得的
// 一行自然高（量测与渲染同体、纵向提议不
// 采）——与 BlockTextView 的 sizeThatFits 纪
// 律同门。两分支共用同一 representable，契
// 约对两分支同构生效，不在分支处打补丁。

import SwiftUI
import UIKit

/// 标题字段控制面：焦点状态位（单一真相）+
/// 待施加落点记号 + 选区回读面。
final class TitleFieldControl: ObservableObject {
    /// 焦点状态位：置 true 的入口只有胶囊具名
    /// 入口（activateTitleFromCapsule）与驱动注
    /// 册动作；置 false 经 Enter/Esc/点外辞焦
    /// 与 didEndEditing 收敛回写。
    @Published var focused = false
    /// 待施加落点记号（方案 P5）：点按时刻以呈
    /// 现态几何定格（标量位 + UTF-16 偏移），聚
    /// 焦落定后只施加、不重算；消费或弃置后即
    /// 清，不跨会话残留（didEndEditing 亦清）。
    var pendingCaret: (scalar: Int, utf16: Int)?
    /// 当前选区起点 UTF-16 偏移回读（Coordinator
    /// 在选区变化与落点施加后维护）：方案 P7 的
    /// 单位实证面 + 驱动状态读的来源。
    var caretUTF16 = 0
    /// 组字态（m-01）：Coordinator 在 editingChanged
    /// / 选区变化时按字段 markedTextRange 维护、
    /// 会话结束清零；EditorView 的 handleEscape 标
    /// 题支据此让行（组字中 Esc 归输入法）。
    var composing = false
}

/// 标题字段本体（E2/F-12）：与正文视图同轨——
/// 系统 undoManager 钉 nil（标题编辑不入系统撤
/// 销轨，文档撤销只走 EditorModel 漏斗）；硬件
/// 键盘 Cmd+Z / Cmd+Shift+Z 在 pressesBegan 拦
/// 截、经 onUndoKey 回到模型漏斗并消费（不调
/// super、不触发系统撤销）。
final class TitleField: UITextField {
    var onUndoKey: ((Bool) -> Void)?

    override var undoManager: UndoManager? { nil }

    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key,
                  key.modifierFlags.contains(.command),
                  key.keyCode == .keyboardZ
            else { continue }
            onUndoKey?(
                key.modifierFlags.contains(.shift))
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

/// 标题 UITextField 承载：字段在 makeUIView 只
/// 建一次、恒在层级（[24] 字段常驻不变量的新
/// 结构形态——身份由 UIView 实例承载，常驻比
/// SwiftUI 字段更硬）。
struct TitleTextField: UIViewRepresentable {
    @ObservedObject var control: TitleFieldControl
    var text: Binding<String>
    /// 会话开始（didBeginEditing）：快照 + 记
    /// session begin 行（EditorHeaderView 提供）。
    var onBeginEditing: () -> Void
    /// 会话结束（didEndEditing）：记 session end
    /// 行 + commitTitle（EditorHeaderView 提供）。
    var onEndEditing: () -> Void
    /// 撤销键回调（E2/F-12）：true = 重做
    /// （Cmd+Shift+Z）；构造点接 EditorModel 的
    /// undo/redo 漏斗。
    var onUndoKey: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(control: control)
    }

    /// 标题字体单源：14 semibold 经 UIFontMetrics
    /// 按 .body 样式缩放（文字大小跟随系统
    /// Dynamic Type，impl_dynamic_type_full）——
    /// 与 capsuleWidth / titlePrefixWidths 的量测
    /// 字体同为 Marks.dynFont(size: 14, weight:
    /// .semibold)，三方恒同源（T26-6 耦合钉子）。
    static func fieldFont() -> UIFont {
        Marks.dynFont(size: 14, weight: .semibold)
    }

    /// 字体三面（本体/缺省属性/占位）在建场与每
    /// 次 updateUIView 同步刷新：系统字号变更时
    /// 宿主因 @ScaledMetric 重演算、representable
    /// 随之 update，字段字体在此跟上新档。
    static func applyFont(_ f: UITextField) {
        let font = fieldFont()
        f.font = font
        f.defaultTextAttributes = [
            .font: font,
            .kern: -0.2,
            .foregroundColor: T.textMainUI,
        ]
        f.attributedPlaceholder = NSAttributedString(
            string: "无标题",
            attributes: [
                .font: font,
                .kern: -0.2,
                // 占位色逐项对旧 SwiftUI 字段：
                // 其占位走系统占位色（placeholder-
                // Text），非正文主色——初版误填主
                // 色，空标题时「无标题」呈正文强度
                // （fix_title_vertical_render.md
                // 呈现对账）。
                .foregroundColor: UIColor.placeholderText,
            ])
    }

    func makeUIView(context: Context) -> UITextField {
        let f = TitleField()
        f.onUndoKey = onUndoKey
        // 字体类别自适应（fix_dynamic_type_follow）：
        // 与 applyFont 的每次 update 刷新双保险——
        // 类别变更时字段字体即时换档，不等下一轮
        // 宿主重演算。
        f.adjustsFontForContentSizeCategory = true
        // 呈现与现行 SwiftUI 字段逐项对齐：居中、
        // 14 semibold（经 fieldFont 随系统字号缩
        // 放）、字距 −0.2（经 typing 属性与缺省属
        // 性）、占位「无标题」同字体。
        Self.applyFont(f)
        f.textAlignment = .center
        f.textColor = T.textMainUI
        f.returnKeyType = .done
        f.delegate = context.coordinator
        f.addTarget(context.coordinator,
                    action: #selector(
                        Coordinator.editingChanged(_:)),
                    for: .editingChanged)
        f.text = text.wrappedValue
        context.coordinator.control = control
        return f
    }

    func updateUIView(_ f: UITextField,
                      context: Context) {
        // 系统字号变更经宿主重演算传到此处，字
        // 体三面随之刷新到新档（applyFont 注释）。
        Self.applyFont(f)
        (f as? TitleField)?.onUndoKey = onUndoKey
        let coord = context.coordinator
        coord.control = control
        coord.text = text
        coord.onBeginEditing = onBeginEditing
        coord.onEndEditing = onEndEditing
        // 焦点执行：状态位与真实第一响应者的差
        // 异步一拍收敛（窗口未挂载时同步 become
        // 会被拒；执行时重读状态位防过期动作）。
        if control.focused, !f.isFirstResponder {
            DispatchQueue.main.async { [weak f] in
                guard let f,
                      self.control.focused,
                      !f.isFirstResponder,
                      f.window != nil else { return }
                f.becomeFirstResponder()
            }
        } else if !control.focused, f.isFirstResponder {
            DispatchQueue.main.async { [weak f] in
                guard let f,
                      !self.control.focused,
                      f.isFirstResponder else { return }
                f.resignFirstResponder()
            }
        }
        // 文本同步（方案同步纪律，verify T26-6）：
        // 编辑/组字期禁反写 field.text——每键回写
        // 会断开「@Published 发布 → 整树重演算 →
        // updateUIView」环、打断组字（B-11 同源
        // 风险）；仅非编辑态或外部变更（Esc 还原
        // 写草稿、切换笔记）时同步。
        let editing = f.isFirstResponder
            || f.markedTextRange != nil
        if !editing, f.text != text.wrappedValue {
            f.text = text.wrappedValue
        }
    }

    /// 尺寸契约（文件头注）：宽随提议、高恒为
    /// 字段自身量测的一行自然高。提议宽缺失
    /// （理想尺寸量测）时以字段内容宽兜底；高
    /// 按定格之宽向字段本体量取（sizeThatFits
    /// 为单行文本字段的内容量测，与渲染同
    /// 体），纵向提议一律不采——字段在胶囊
    /// VStack 里就此恢复旧 SwiftUI TextField
    /// 的尺寸行为：横向填满标题行、纵向定高，
    /// 余高留给 VStack 成组居中（竖排 meta 行
    /// 回到组内位置、横排同构无变化）。
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView f: UITextField,
                      context: Context) -> CGSize? {
        let w = proposal.width
            ?? f.sizeThatFits(CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat
                    .greatestFiniteMagnitude)).width
        let h = f.sizeThatFits(CGSize(
            width: w,
            height: CGFloat
                .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: h)
    }

    final class Coordinator: NSObject,
        UITextFieldDelegate {
        var control: TitleFieldControl
        var text: Binding<String>?
        var onBeginEditing: (() -> Void)?
        var onEndEditing: (() -> Void)?

        init(control: TitleFieldControl) {
            self.control = control
        }

        /// 键入回写：单向写草稿绑定（与现行
        /// Binding setter 等价），不在此触发提
        /// 交。
        @objc func editingChanged(_ f: UITextField) {
            control.composing = f.markedTextRange != nil
            text?.wrappedValue = f.text ?? ""
        }

        func textFieldDidBeginEditing(
            _ f: UITextField) {
            if !control.focused {
                control.focused = true
            }
            onBeginEditing?()
            applyPendingCaret(f)
        }

        func textFieldDidEndEditing(
            _ f: UITextField) {
            // 收敛律：无条件回写 false + 清记号。
            control.composing = false
            control.pendingCaret = nil
            if control.focused {
                control.focused = false
            }
            onEndEditing?()
        }

        func textFieldShouldReturn(
            _ f: UITextField) -> Bool {
            // Enter 收口：辞焦即触发 didEndEditing
            // 的提交支路（与现行 onSubmit 的
            // commitTitle + 辞焦等价合流）。
            if control.focused {
                control.focused = false
            } else {
                f.resignFirstResponder()
            }
            return false
        }

        func textFieldDidChangeSelection(
            _ f: UITextField) {
            control.composing = f.markedTextRange != nil
            if let r = f.selectedTextRange {
                control.caretUTF16 = f.offset(
                    from: f.beginningOfDocument,
                    to: r.start)
            }
        }

        /// 落点施加（方案 P6）：延后一拍（聚焦事
        /// 务内同步设选区会被 UIKit 自身落焦落点
        /// 覆盖，与 Web rAF 延后同理）；施加前复
        /// 查第一响应者/组字态/记号未消费，不满
        /// 足弃记号不重试。施加后回读 UTF-16 偏
        /// 移与期望比对（P7 单位实证），不符记异
        /// 常行。
        private func applyPendingCaret(
            _ f: UITextField) {
            guard control.pendingCaret != nil
            else { return }
            DispatchQueue.main.async { [weak f] in
                guard let f else { return }
                guard let pending =
                        self.control.pendingCaret
                else { return }
                self.control.pendingCaret = nil
                guard f.isFirstResponder,
                      f.markedTextRange == nil,
                      let pos = f.position(
                        from: f.beginningOfDocument,
                        offset: pending.utf16),
                      let range = f.textRange(
                        from: pos, to: pos)
                else { return }
                f.selectedTextRange = range
                DiagLog.shared.log(.info,
                    "EDIT title caret -> "
                    + "\(pending.scalar)")
                let readback = f.offset(
                    from: f.beginningOfDocument,
                    to: range.start)
                self.control.caretUTF16 = readback
                if readback != pending.utf16 {
                    DiagLog.shared.log(.error,
                        "EDIT title caret readback "
                        + "mismatch want="
                        + "\(pending.utf16) got="
                        + "\(readback)")
                }
            }
        }
    }
}
