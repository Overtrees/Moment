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
//
// 0.9.49 第三轮根治（定案 audit_drag_pickup_round3）：
// 0.9.47 真机定案——认领两次命中、识别器从未 began，
// 且未拾起前的 failed/cancelled 零日志（留痕洞）。
// Web 参数逐项等值（480ms/10px 已证），真差在仲裁豁
// 免权：Web 的按压计时器除明文路径外无可被强制失败，
// 0.9.47 却只豁免宿主 pan，UITextView 内部识别器组
// （选区长按 + 文本拖放 lift）仍互斥强杀，两败俱在
// 文本块。本轮：① 并行姿态全放开（对全部识别器返回
// true），引擎降为纯计时 + 位移判定；② 拾起收敛选
// 区（行侧 convergeSelectionOnPickup，Web pickup 的
// removeAllRanges 对应）+ 文本视图 dragInteraction
// 关闭（BlockTextView 侧）；③ 打点补全——handle 入
// 口无条件记全部状态变迁（state/ms/disp），began 无
// 目标显式 orphan，shouldReceive 拒绝路径补齐；
// ④ 卡片块武装（用户 2026-11-27 纠正：Web pickup 对
// 全部块单元一视同仁、原子块全可拖、卡菜单骑拾起；
// 原生 0.9.19 起卡片行 disarmed 是范围裁剪、已废）
// ——CardMenuGesture 退役，卡菜单改骑拾起（行侧）。

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
    // 打点补全（0.9.49）：认领时刻与起点（滚动视图
    // 坐标），供 handle 的状态行算 ms（距认领）与
    // disp（位移）；.changed 防刷屏两旗。
    private var pressStart: CFAbsoluteTime = 0
    private var pressOrigin: CGPoint = .zero
    private var changedLoggedFirst = false
    private var changedLoggedOver = false

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
    /// → 触摸归文本选择，是仅剩的行级守卫；卡片块
    /// 0.9.49 起与文本块同武装）。按钮类子视图不接
    /// 管（Web 按压引擎同口径：勾选钮等点按控件优
    /// 先）。拒绝路径 0.9.49 起全留痕（按钮命中 /
    /// 无行命中各 logOnce——DiagLevel 无 verbose 档，
    /// 以 logOnce 信息级代之，防高频触摸刷屏）。
    func gestureRecognizer(
        _ gr: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gr === recognizer, let sv = scrollView
        else { return false }
        let pt = touch.location(in: sv)
        if let hit = sv.hitTest(pt, with: nil),
           hit is UIButton {
            DiagLog.shared.logOnce(
                "drag-press-button", .info,
                "DRAG press reject button")
            return false
        }
        var disarmedId: String?
        for (id, row) in rows {
            guard let hv = row.hostView else { continue }
            let f = hv.convert(hv.bounds, to: sv)
            guard f.contains(pt) else { continue }
            if row.enabled() {
                targetId = id
                pressStart = CFAbsoluteTimeGetCurrent()
                pressOrigin = pt
                changedLoggedFirst = false
                changedLoggedOver = false
                DiagLog.shared.log(.info,
                    "DRAG press target id=\(id) "
                    + "x=\(Int(pt.x)) y=\(Int(pt.y))")
                return true
            }
            disarmedId = id
        }
        if let disarmedId {
            DiagLog.shared.logOnce(
                "drag-disarmed-\(disarmedId)", .info,
                "DRAG press disarmed id=\(disarmedId)")
        } else {
            DiagLog.shared.logOnce(
                "drag-press-norow", .info,
                "DRAG press norow "
                + "x=\(Int(pt.x)) y=\(Int(pt.y))")
        }
        targetId = nil
        return false
    }

    /// 并行姿态全放开（0.9.49 第三轮根治）：对全部
    /// 其他识别器返回 true——引擎降为纯计时 + 位移
    /// 判定，不再参与平台互斥仲裁（与 Web 按压计时
    /// 器同构：除 move 超限 / up / cancel / 新 down
    /// 四条明文路径外，无可被强制失败）。0.9.47 只
    /// 豁免宿主 pan，UITextView 内部识别器组（选区
    /// 长按 + 文本拖放 lift）仍互斥强杀、两败俱在
    /// 文本块（真机定案）。滚动的实际让行仍靠拾起
    /// 即锁 isScrollEnabled；手指先行移动 >10pt 则
    /// 本识别器以 allowableMovement 自然失败、滚动
    /// 零延迟，此点不变。
    func gestureRecognizer(
        _ gr: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            other: UIGestureRecognizer
    ) -> Bool {
        return gr === recognizer
    }

    /// 状态行（0.9.49 打点补全）：state 全名 + 目标
    /// id + ms（距认领毫秒，未认领 -1）+ disp（距认
    /// 领点位移 pt，未认领 -1）——下一包真机导出按
    /// 此一行即可指认死法（判读表见
    /// fix_drag_pickup_round3.md）。
    private func logState(
        _ r: UILongPressGestureRecognizer,
        id: String, ms: Int, disp: Int
    ) {
        let name: String
        switch r.state {
        case .possible: name = "possible"
        case .began: name = "began"
        case .changed: name = "changed"
        case .ended: name = "ended"
        case .cancelled: name = "cancelled"
        case .failed: name = "failed"
        @unknown default: name = "other"
        }
        DiagLog.shared.log(.info,
            "DRAG press state=\(name) id=\(id) "
            + "ms=\(ms) disp=\(disp)")
    }

    @objc func handle(_ r: UILongPressGestureRecognizer) {
        // 入口无条件记状态变迁（0.9.49 补 0.9.47 的
        // 留痕洞：未拾起即 failed/cancelled 时旧实现
        // 零日志，真机只能定位断点、不能指认死法）。
        // .changed 防刷屏：只记首条与首次越 10pt。
        let ms = pressStart > 0
            ? Int((CFAbsoluteTimeGetCurrent()
                   - pressStart) * 1000)
            : -1
        var disp = -1
        if let sv = scrollView {
            let p = r.location(in: sv)
            disp = Int(hypot(p.x - pressOrigin.x,
                             p.y - pressOrigin.y))
        }
        let idForLog = targetId ?? "-"
        if r.state == .changed {
            if !changedLoggedFirst {
                changedLoggedFirst = true
                logState(r, id: idForLog, ms: ms,
                         disp: disp)
            } else if disp > 10, !changedLoggedOver {
                changedLoggedOver = true
                logState(r, id: idForLog, ms: ms,
                         disp: disp)
            }
        } else {
            logState(r, id: idForLog, ms: ms, disp: disp)
        }
        switch r.state {
        case .began:
            guard let id = targetId, let row = rows[id]
            else {
                // began 却无目标/行缺失：显式留痕，
                // 不再静默 return（旧洞同源）。
                DiagLog.shared.log(.warn,
                    "DRAG began orphan")
                return
            }
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
