// ── 撤销历史状态机（E2 撤销体系根治，审计
// F-10/F-11/F-12；定案 impl_editor_undo_e2.md）──
// 编辑器撤销的全部记账单点：返回点记录（去重 +
// 上限 100）、文本爆发合并（600ms 窗）、撤销/重
// 做步进与条目所附选区。纯状态机（仅 Foundation、
// 无 UIKit/SwiftUI 依赖）：载荷由调用方泛型注入
// （应用侧 = doc 快照字典 + 其规范键），时刻由调
// 用方传入——故可独立编译做表驱动断言（verify
// [47] E47-3），规则与 Web hist_push/step_undo
// 逐项对齐（diagnose_batch4_undo：600ms 合并/
// 上限 100/去重/撤销后断链）。
//
// 模型口径（原生既有两栈「返回点」形态，与 Web
// 后态快照 + 指针模型同构）：undoStack 内存各步
// 的「变更前状态」，undo 弹栈顶应用之、当前态压
// redoStack。条目以 key（快照规范序列化）判等。

import Foundation

/// 选区记录（F-11）：历史条目所附的操作前选区，
/// 偏移为字符口径（与 EditorModel.pendingCaret-
/// Offset 的消费面 tv.text.count 同单位）。
struct UndoSel: Equatable {
    var blockId: String
    var location: Int
    var length: Int
}

/// 历史条目：载荷 + 规范键 + 附带选区。
struct UndoEntry<Payload> {
    var payload: Payload
    var key: String
    var sel: UndoSel?
}

/// 馈入结果（Diag 与调用方分流用）。
enum UndoFeedResult: Equatable {
    /// 新返回点已入栈。
    case pushed
    /// 与栈顶同键、未入栈（幻影步去重）。
    case deduped
    /// 爆发窗内连续键入、只更新合并时钟。
    case withinBurst
}

/// 爆发合并窗（Web hist_push coalesce 600ms 同值）。
let undoBurstWindow: Double = 0.6
/// 栈深上限（Web 上限 100 同值；旧原生 50 退役）。
let undoStackCap = 100

struct UndoHistoryCore<Payload> {
    private(set) var undoStack: [UndoEntry<Payload>] = []
    private(set) var redoStack: [UndoEntry<Payload>] = []
    /// 合并链时钟：最近一次文本馈入的时刻（调用方
    /// 时钟口径，秒）；nil = 无链（结构记录/撤销/
    /// 重做后恒断链，Web hist_clock 归零同义）。
    private var lastTextAt: Double?
    private var chainLive = false
    /// 结果量计数（Diag 判读面）：窗内合并的键入
    /// 馈入数、去重跳过的记录数、上限钳制逐出的
    /// 条目数。
    private(set) var mergedCount = 0
    private(set) var dedupedCount = 0
    private(set) var clampedCount = 0

    /// 引擎本体事件出口（AUD-E-05）：去重/钳制/
    /// 空栈步进等引擎内部分支在此自记，不再靠消
    /// 费方代记。引擎保持 Foundation-only——只回
    /// 吐分支事实短文，Diag 词形与落盘由注入方
    /// （EditorModel）承接；nil = 不记（宿主测试
    /// 捕获本出口断言分支事件序列）。
    var eventSink: ((String) -> Void)?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoDepth: Int { undoStack.count }
    var redoDepth: Int { redoStack.count }

    /// 入撤销栈（去重 + 钳制单点）：与栈顶同键不
    /// 入栈（连续重复返回点 = 幻影步，见定案报告
    /// 的同构论证）；超上限逐最旧。
    @discardableResult
    private mutating func appendUndo(
        _ e: UndoEntry<Payload>) -> Bool {
        if undoStack.last?.key == e.key {
            dedupedCount += 1
            eventSink?("dedup side=undo total="
                       + "\(dedupedCount)")
            return false
        }
        undoStack.append(e)
        if undoStack.count > undoStackCap {
            let n = undoStack.count - undoStackCap
            undoStack.removeFirst(n)
            clampedCount += n
            eventSink?("clamp side=undo n=\(n) "
                       + "total=\(clampedCount) "
                       + "depth=\(undoStack.count)")
        }
        return true
    }

    /// 入重做栈（同去重 + 钳制单点）。
    @discardableResult
    private mutating func appendRedo(
        _ e: UndoEntry<Payload>) -> Bool {
        if redoStack.last?.key == e.key {
            dedupedCount += 1
            eventSink?("dedup side=redo total="
                       + "\(dedupedCount)")
            return false
        }
        redoStack.append(e)
        if redoStack.count > undoStackCap {
            let n = redoStack.count - undoStackCap
            redoStack.removeFirst(n)
            clampedCount += n
            eventSink?("clamp side=redo n=\(n) "
                       + "total=\(clampedCount) "
                       + "depth=\(redoStack.count)")
        }
        return true
    }

    private mutating func breakChain() {
        chainLive = false
        lastTextAt = nil
    }

    /// 操作边界记录（结构 op 与文本编辑会话开始，
    /// 一律在变更前调）：恒清重做尾（新分支起步，
    /// 与旧 pushHistory 口径一致）、断合并链、去
    /// 重入栈。
    mutating func recordOpBoundary(
        payload: Payload, key: String,
        sel: UndoSel?) -> UndoFeedResult {
        redoStack.removeAll()
        breakChain()
        return appendUndo(UndoEntry(
            payload: payload, key: key, sel: sel))
            ? .pushed : .deduped
    }

    /// 文本变更前馈入（爆发合并）：链活着且距上一
    /// 键 <600ms 时只续链（本键的变更前态已被爆发
    /// 起点的返回点覆盖）；否则落一个新返回点
    /// （= 本次爆发开始前的文档态）、起链。去重
    /// 同 appendUndo（与栈顶同键不起新步，但链照
    /// 起——后续键入据此合并）。entry 为惰性工
    /// 厂：仅在真要落返回点时求值一次——窗内合
    /// 并的逐键馈入不付快照/序列化成本。
    mutating func noteTextWillChange(
        entry: () -> (payload: Payload, key: String),
        sel: UndoSel?, now: Double) -> UndoFeedResult {
        if chainLive, let last = lastTextAt,
           now - last < undoBurstWindow {
            lastTextAt = now
            mergedCount += 1
            return .withinBurst
        }
        redoStack.removeAll()
        let e = entry()
        let r = appendUndo(UndoEntry(
            payload: e.payload, key: e.key, sel: sel))
            ? UndoFeedResult.pushed : .deduped
        lastTextAt = now
        chainLive = true
        return r
    }

    /// 撤销一步：弹撤销栈顶为应用目标，当前态压
    /// 重做栈（去重/钳制同 appendRedo）；断链。
    /// 栈空返回 nil（调用方无操作）。
    mutating func performUndo(
        currentPayload: Payload, currentKey: String,
        currentSel: UndoSel?) -> UndoEntry<Payload>? {
        guard let target = undoStack.popLast()
        else {
            eventSink?("step-empty side=undo")
            return nil
        }
        appendRedo(UndoEntry(payload: currentPayload,
                             key: currentKey,
                             sel: currentSel))
        breakChain()
        return target
    }

    /// 重做一步：弹重做栈顶为应用目标，当前态压
    /// 撤销栈（去重/钳制同 appendUndo）；断链。
    mutating func performRedo(
        currentPayload: Payload, currentKey: String,
        currentSel: UndoSel?) -> UndoEntry<Payload>? {
        guard let target = redoStack.popLast()
        else {
            eventSink?("step-empty side=redo")
            return nil
        }
        appendUndo(UndoEntry(payload: currentPayload,
                             key: currentKey,
                             sel: currentSel))
        breakChain()
        return target
    }
}
