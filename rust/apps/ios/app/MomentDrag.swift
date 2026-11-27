import SwiftUI
import UIKit

// ── 块拖拽按压引擎（0.9.47 第二轮根治，独立成文件）──
// 职责：编辑页块排序的长按拾起——每滚动视图一个
// 引擎、一枚 UILongPressGestureRecognizer 全程所有
// 按压序列；行只注册命中锚点与回调，不再各自持识别器。
//
// 仲裁沿革（定案记录）：
// 0.9.14 初版：SwiftUI LongPress.sequenced(Drag) 挂行，
//   pan 须等其裁决、慢划被俘获整页冻住——弃。
// 0.9.14 改版：UIKit 长按挂滚动视图、每行一枚识别器、
//   长按 require(toFail: pan)——静止手指下 pan 永不判
//   失败，拾起永不发生（2026-11-26 真机实报）。
// 0.9.36：删 require + 拾起锁滚动 + attach 打点，代码
//   级判修；2026-11-27 真机裁定依旧拾不起——上行定
//   因至多不完整。复核（fix_drag_pickup_round2）：
//   0.9.36 落码与现行代码逐行一致（require 确删、锁滚
//   确在拾起路），病灶在结构：每行三个长按消费者叠压
//   同一触点——行级 SwiftUI .contextMenu（UIContext-
//   MenuInteraction 自带长按识别）、卡片行 onLongPress-
//   Gesture、文本块 UITextView 内部选区识别——外加每
//   行一枚 UIKit 长按挂在祖先滚动视图上做最弱 claimant，
//   仲裁全在平台内部、无从控制，且 attach 失败静默无痕。
// 本轮按 Web 压引擎形态重构（editor.js 单一 pointer-
//   down 引擎全程所有、菜单骑拾起）：滚动视图级单识别
//   器 + 行注册表命中过滤 + 与 pan 显式并行（拾起靠锁
//   滚动让行，不靠 require）；行级长按消费者清零——
//   .contextMenu 已删（类型转换菜单改由拾起呈现，见
//   EditorView.blockMenuLayer），卡片行菜单保留其
//   SwiftUI 长按（引擎对其 disarmed、不与之争）。
// 全链打点：engine attached / press target / press
//   disarmed / pickup（行侧）/ menu show（行侧）/
//   drop / cancel——真机一次导出即可定位死点。

/// 每滚动视图一个的按压引擎（经关联对象挂在宿主
/// UIScrollView 上，随其生命周期）。行命中沿用旧路
/// 已证的换算：锚点视图 bounds 换算到滚动视图坐标
/// 系与触点同系比对（旧实现唯一一次真机 pickup 即
/// 走此换算，见 2026-11-26 Diag 导出）。
final class DragPressEngine: NSObject,
    UIGestureRecognizerDelegate {

    struct Row {
        weak var hostView: UIView?
        var enabled: () -> Bool
        var onPickup: () -> Void
        var onDrag: (CGFloat) -> Void
        var onDrop: () -> Void
        var onCancel: () -> Void
    }

    private static var engineKey: UInt8 = 0

    private weak var scrollView: UIScrollView?
    private(set) var recognizer: UILongPressGestureRecognizer!
    private var rows: [String: Row] = [:]
    private var targetId: String?
    private var picked = false
    private var startY: CGFloat = 0

    /// 取（或建）某滚动视图的引擎：全程恰一枚识别器。
    static func engine(for sv: UIScrollView)
        -> DragPressEngine {
        if let e = objc_getAssociatedObject(
            sv, &engineKey) as? DragPressEngine {
            return e
        }
        let e = DragPressEngine(scrollView: sv)
        objc_setAssociatedObject(sv, &engineKey, e,
                                 .OBJC_ASSOCIATION_RETAIN)
        return e
    }

    private init(scrollView sv: UIScrollView) {
        super.init()
        scrollView = sv
        let lp = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handle(_:)))
        lp.minimumPressDuration = 0.48
        lp.allowableMovement = 10
        lp.cancelsTouchesInView = false
        lp.delegate = self
        recognizer = lp
        sv.addGestureRecognizer(lp)
        DiagLog.shared.log(.info, "DRAG engine attached")
    }

    func register(id: String, row: Row) {
        rows[id] = row
    }

    func unregister(id: String) {
        guard let row = rows.removeValue(forKey: id)
        else { return }
        if picked, targetId == id {
            // 拾起中行被卸载：按取消收尾并恢复滚动
            // （与行 onDisappear 的状态复位互补）。
            picked = false
            targetId = nil
            scrollView?.isScrollEnabled = true
            row.onCancel()
        }
    }

    /// 命中过滤：触点落在某已注册行 frame 内且该行
    /// 武装时才接管本次触摸（编辑中文本块 disarmed
    /// → 触摸归文本选择；卡片行 disarmed → 归其菜单
    /// 长按）。按钮类子视图不武装（Web 按压引擎同
    /// 口径：勾选钮等点按控件优先）。
    func gestureRecognizer(
        _ gr: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gr === recognizer, let sv = scrollView
        else { return false }
        let pt = touch.location(in: sv)
        if let hit = sv.hitTest(pt, with: nil),
           hit is UIButton {
            return false
        }
        var disarmedId: String?
        for (id, row) in rows {
            guard let hv = row.hostView else { continue }
            let f = hv.convert(hv.bounds, to: sv)
            guard f.contains(pt) else { continue }
            if row.enabled() {
                targetId = id
                DiagLog.shared.log(.info,
                    "DRAG press target id=\(id)")
                return true
            }
            disarmedId = id
        }
        if let disarmedId {
            DiagLog.shared.logOnce(
                "drag-disarmed-\(disarmedId)", .info,
                "DRAG press disarmed id=\(disarmedId)")
        }
        targetId = nil
        return false
    }

    /// 与宿主 pan 显式并行：pan 不得再取消本识别器
    /// （0.9.36 删 require 后的正向接法）；滚动的实
    /// 际让行靠拾起即锁 isScrollEnabled，手指先行移
    /// 动 >10pt 则本识别器以 allowableMovement 自然
    /// 失败、滚动零延迟（Web 口径同构）。
    func gestureRecognizer(
        _ gr: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            other: UIGestureRecognizer
    ) -> Bool {
        if let sv = scrollView,
           other === sv.panGestureRecognizer {
            return true
        }
        return false
    }

    @objc func handle(_ r: UILongPressGestureRecognizer) {
        switch r.state {
        case .began:
            guard let id = targetId, let row = rows[id]
            else { return }
            picked = true
            startY = r.location(in: nil).y
            // 拾起即锁滚动：跟指期间内容不再被 pan
            // 带走（落位/取消/失败统一恢复）。
            scrollView?.isScrollEnabled = false
            row.onPickup()
        case .changed:
            if picked, let id = targetId,
               let row = rows[id] {
                row.onDrag(r.location(in: nil).y - startY)
            }
        case .ended:
            if picked, let id = targetId,
               let row = rows[id] {
                DiagLog.shared.log(.info,
                    "DRAG drop id=\(id)")
                row.onDrop()
            }
            picked = false
            scrollView?.isScrollEnabled = true
        case .cancelled, .failed:
            if picked, let id = targetId,
               let row = rows[id] {
                DiagLog.shared.log(.info,
                    "DRAG cancel id=\(id) "
                    + "state=\(r.state.rawValue)")
                row.onCancel()
            }
            picked = false
            scrollView?.isScrollEnabled = true
        default: break
        }
    }
}

/// 行级注册锚点（DragPressInstaller 的后继，旧路整
/// 段已删）：0 尺寸寄生视图撑满行背景，只负责把本
/// 行（命中视图 + 武装判定 + 四回调）注册进其祖先
/// 滚动视图的按压引擎；自身不持任何识别器。
struct DragPressAnchor: UIViewRepresentable {
    var blockId: String
    var enabled: Bool
    var onPickup: () -> Void
    var onDrag: (CGFloat) -> Void
    var onDrop: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.attach(anchor: self, view: v)
    }

    static func dismantleUIView(_ v: UIView,
                                coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var engine: DragPressEngine?
        private weak var scrollView: UIScrollView?
        private var blockId: String?
        private var asyncRetried = false

        /// 找祖先 UIScrollView 并把本行注册进其引擎
        /// （引擎不存在则建）。每次 update 刷新注册
        /// （回调闭包随行渲染保鲜）；滚动视图变更时
        /// 先从旧引擎注销。
        func attach(anchor: DragPressAnchor, view: UIView) {
            var cur: UIView? = view.superview
            var sv: UIScrollView?
            while let c = cur {
                if let s = c as? UIScrollView { sv = s; break }
                cur = c.superview
            }
            guard let sv else {
                // 首帧 update 可能早于入树（寄生视图尚
                // 无祖先）：主队列尾重试一次，不静默丢
                // 注册（旧路 attach 失败无痕的教训）。
                if !asyncRetried {
                    asyncRetried = true
                    DiagLog.shared.logOnce(
                        "drag-anchor-nosv", .warn,
                        "DRAG anchor attach deferred "
                        + "(no sv ancestor yet)")
                    DispatchQueue.main.async {
                        [weak self, weak view] in
                        guard let self, let view else { return }
                        self.attach(anchor: anchor, view: view)
                    }
                }
                return
            }
            asyncRetried = false
            if sv !== scrollView {
                detach()
                scrollView = sv
                engine = DragPressEngine.engine(for: sv)
            }
            blockId = anchor.blockId
            engine?.register(id: anchor.blockId,
                row: DragPressEngine.Row(
                    hostView: view,
                    enabled: { anchor.enabled },
                    onPickup: anchor.onPickup,
                    onDrag: anchor.onDrag,
                    onDrop: anchor.onDrop,
                    onCancel: anchor.onCancel))
        }

        func detach() {
            if let id = blockId {
                engine?.unregister(id: id)
            }
            blockId = nil
            engine = nil
            scrollView = nil
        }
    }
}
