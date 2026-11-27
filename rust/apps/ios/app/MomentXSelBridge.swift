// ── 跨块选区桥接层·模型面（F-09 一期，定案
// plan_cross_block_selection.md §8.1 / impl_
// cross_block_selection_p1.md）──
// MomentXSel.swift 纯核心的 EditorModel 扩展：
// 选区状态机（置位/全选/收拢）、动作面（替换/
// 剪切文本）、守卫（只读禁入、失效对账、块消
// 失回退）、呈现查询与 replaceRange 模型 op
// （ops.rs 逐支移植）。仅依赖 Foundation 与同
// 模块类型；系统剪贴板等 UIKit 面留在
// MomentApp.swift 的调用点。

import Foundation

// ── EditorModel 桥接层（状态机 + 动作面 + 模型 op） ──

/// 可编辑单元（Web editable_units 同口径）：顶层
/// 文本块 + 顶层列表的直属项，文档序。嵌套列表
/// 项不入（Web find_loc 只寻一层，原生 textUnits
/// 的递归口径是方向键面、与此不同，不混用）。
struct XSelUnit {
    var block: BlockState
    var list: BlockState?
    var topIndex: Int
    var itemIndex: Int?
}

extension EditorModel {

    func xselUnits() -> [XSelUnit] {
        var out: [XSelUnit] = []
        for (t, b) in blocks.enumerated() {
            if b.isText {
                out.append(XSelUnit(block: b, list: nil,
                                    topIndex: t,
                                    itemIndex: nil))
            } else if b.isList {
                for (ii, item) in b.itemStates.enumerated() {
                    out.append(XSelUnit(block: item, list: b,
                                        topIndex: t,
                                        itemIndex: ii))
                }
            }
        }
        return out
    }

    /// 原子分类（Web is_atomic_class 同口径）：非
    /// 文本块、且不是含项列表（空列表按原子计）。
    func xselIsAtomicTop(_ b: BlockState) -> Bool {
        if b.isText { return false }
        if b.isList { return b.itemStates.isEmpty }
        return true
    }

    /// 源码态块判定（Web isSrcBlock 的原生对应：
    /// mdsrc/musicInput 无原生块型，源码态只有
    /// codeBlock）。
    func isXSelSourceBlock(_ id: String) -> Bool {
        xselUnits().first(where: { $0.block.id == id })?
            .block.type == "codeBlock"
    }

    // ── 状态机入口 ──

    /// 选区置位单点（Web setXsel 同口径）：非全文
    /// 置位先经 guardSpan 钳制；钳后锚焦重合则选
    /// 区不成立、归 nil。
    func setXSel(anchor: XSelPos, focus: XSelPos,
                 whole: (fromStart: Bool, toEnd: Bool)?) {
        var f = focus
        if whole == nil {
            let infos = xselUnits().map {
                XSelUnitInfo(
                    id: $0.block.id,
                    isSource: $0.block.type == "codeBlock",
                    utf16Length: $0.block.text.utf16.count)
            }
            f = XSelCore.guardSpan(anchor: anchor,
                                   focus: focus, units: infos)
            if anchor.id == f.id && anchor.off == f.off {
                xsel = nil
                return
            }
        }
        xsel = XSel(anchorId: anchor.id, anchorOff: anchor.off,
                    focusId: f.id, focusOff: f.off,
                    fromStart: whole?.fromStart ?? false,
                    toEnd: whole?.toEnd ?? false)
    }

    /// 全选（Web selectAllXsel 同口径）：首个可编
    /// 辑单元首 → 末单元尾，置全文标记；原生选区
    /// 收拢到锚点（placeNativeAt 同位，经既有焦点
    /// 投递面）。只读态禁入（守卫集）。
    func selectAllXSel() {
        guard !library.isReadOnly else { return }
        let units = xselUnits()
        guard let first = units.first, let last = units.last
        else { return }
        setXSel(anchor: XSelPos(id: first.block.id, off: 0),
                focus: XSelPos(
                    id: last.block.id,
                    off: last.block.text.utf16.count),
                whole: (fromStart: true, toEnd: true))
        focusBlockId = first.block.id
        focusCaretEnd = false
        pendingCaretOffset = 0
        pendingSelectionLength = 0
        DiagLog.shared.log(.info,
            "EDIT xsel select-all units=\(units.count)")
    }

    func clearXSel() { xsel = nil }

    /// 收拢到焦点端（Web collapseXsel 同口径：Esc
    /// / 组字开始 / Shift+方向未扩展时共用）。
    func collapseXSel() {
        guard let sel = xsel else { return }
        xsel = nil
        placeXSelCaret(XSelPos(id: sel.focusId,
                               off: sel.focusOff))
    }

    /// 收拢到有序起/止端（Web 无修饰方向键支：左/
    /// 上 → 起点、右/下 → 止点）。
    func collapseXSel(toOrderedStart: Bool) {
        guard let sel = xsel else { return }
        let units = xselUnits()
        xsel = nil
        guard let ord = XSelCore.ordered(
            sel, unitIds: units.map { $0.block.id })
        else { return }
        placeXSelCaret(toOrderedStart ? ord.s : ord.e)
    }

    /// Shift+方向端点扩展（二期，Web xselExtend
    /// 同构）：锚不动、焦点步进一格（左右 = 字符
    /// 步进、上下 = 视觉行几何换算）。端点源——
    /// xsel 在位取其锚/焦；不在位取入参的原生选
    /// 区两端（活动端推定在 EditorTextView 侧，
    /// 本层只收两端值）。接管判定与步进决策全在
    /// 纯核心（XSelCore.extendHorizontal /
    /// verticalFocus，表驱动锁）：块内步进/非边
    /// 缘行内移动在原无选区时不接管（返回 false，
    /// 调用方放行原生扩展、保原生粒度）。接管成
    /// 立后经 setXSel 单点置位（guardSpan 钳制 +
    /// 钳后重合归 nil = 选区步回收拢），原生选区
    /// 随之收拢到锚点（placeNativeAt 同位，经落点
    /// 投递面）——双选区不同显、失效对账不误清。
    /// 端点已消失（陈旧跨度）→ 清选作废、不接管
    /// （失效对账的扩展面兜底）。
    func xselExtend(
        dir: XSelDirection,
        native: (blockId: String, loc: Int, len: Int,
                 focusAtEnd: Bool)? = nil) -> Bool {
        let units = xselUnits()
        guard !units.isEmpty else { return false }
        let texts = units.map {
            (id: $0.block.id, text: $0.block.text)
        }
        let hadSel = xsel != nil
        let anchor: XSelPos
        let focus: XSelPos
        if let sel = xsel {
            anchor = XSelPos(id: sel.anchorId,
                             off: sel.anchorOff)
            focus = XSelPos(id: sel.focusId,
                            off: sel.focusOff)
            guard texts.contains(where: {
                    $0.id == anchor.id }),
                  texts.contains(where: {
                    $0.id == focus.id })
            else {
                clearXSel()
                return false
            }
        } else if let n = native {
            if n.len > 0 && !n.focusAtEnd {
                anchor = XSelPos(id: n.blockId,
                                 off: n.loc + n.len)
                focus = XSelPos(id: n.blockId, off: n.loc)
            } else {
                anchor = XSelPos(id: n.blockId, off: n.loc)
                focus = XSelPos(id: n.blockId,
                                off: n.loc + n.len)
            }
        } else { return false }
        guard let fi = texts.firstIndex(
            where: { $0.id == focus.id }) else { return false }

        let nf: XSelPos
        switch dir {
        case .left, .right:
            guard let pair = XSelCore.extendHorizontal(
                anchor: anchor, focus: focus,
                hadSel: hadSel,
                dir: dir == .left ? -1 : 1, units: texts)
            else { return false }
            nf = pair.focus
        case .up, .down:
            let up = dir == .up
            // 焦点行几何（量测面 = crossBlockArrow
            // 同源的 lineBoxes/hitOffset，窗口系）：
            // 焦点视图未注册/落点不可测 → 不接管。
            guard let tvF = tvForBlock(focus.id),
                  let caretPos = tvF.position(
                    from: tvF.beginningOfDocument,
                    offset: min(max(focus.off, 0),
                                texts[fi].text.utf16.count))
            else { return false }
            let caretWin = tvF.convert(
                tvF.caretRect(for: caretPos), to: nil)
            let lines = lineBoxes(tvF)
            var li = lines.count - 1
            for (i, l) in lines.enumerated()
            where caretWin.minY >= l.rect.minY - 1
                && caretWin.minY < l.rect.maxY + 1 {
                li = i
                break
            }
            if lines.isEmpty { li = 0 }
            // 边缘判定：焦点行即焦点单元的首/末视
            // 觉行（Web 以光标矩形对块矩形的边缘近
            // 似判定，原生行盒直判——决策等值、量
            // 测更准，见 XSelCore.verticalFocus 注）。
            let onEdge = lines.isEmpty
                || (up ? li == 0 : li == lines.count - 1)
            var sameHit: XSelPos? = nil
            var crossHit: XSelPos? = nil
            var docClamp: XSelPos? = nil
            if !onEdge {
                if hadSel {
                    let target = lines[up ? li - 1 : li + 1]
                    sameHit = XSelPos(
                        id: focus.id,
                        off: hitOffset(tv: tvF, line: target,
                                       xWindow: caretWin.minX
                                           + 1))
                }
            } else {
                let ti = up ? fi - 1 : fi + 1
                if ti < 0 || ti >= units.count {
                    docClamp = up
                        ? XSelPos(id: texts[0].id, off: 0)
                        : XSelPos(
                            id: focus.id,
                            off: texts[fi].text.utf16.count)
                } else {
                    let tu = units[ti]
                    // Web pointFromXY 无果的兜底位：
                    // ↑ 目标单元尾 / ↓ 目标单元首；
                    // 目标视图未注册/无行量测同走兜
                    // 底（Web 对不可测目标同形）。
                    let fallback = XSelPos(
                        id: tu.block.id,
                        off: up ? texts[ti].text.utf16.count
                            : 0)
                    if let tvT = tvForBlock(tu.block.id) {
                        let linesT = lineBoxes(tvT)
                        if linesT.isEmpty {
                            crossHit = fallback
                        } else {
                            let target = up
                                ? linesT[linesT.count - 1]
                                : linesT[0]
                            crossHit = XSelPos(
                                id: tu.block.id,
                                off: hitOffset(
                                    tv: tvT, line: target,
                                    xWindow: caretWin.minX
                                        + 1))
                        }
                    } else {
                        crossHit = fallback
                    }
                }
            }
            guard let v = XSelCore.verticalFocus(
                hadSel: hadSel, focus: focus,
                onEdge: onEdge, sameHit: sameHit,
                crossHit: crossHit, docClamp: docClamp)
            else { return false }
            nf = v
        }

        setXSel(anchor: anchor, focus: nf, whole: nil)
        let arrow: String
        switch dir {
        case .left: arrow = "←"
        case .right: arrow = "→"
        case .up: arrow = "↑"
        case .down: arrow = "↓"
        }
        if let sel = xsel {
            // 原生选区收拢到锚点（Web setXsel 尾
            // placeNativeAt 同位）：投递后对账面读
            // 到的恒是锚点收拢态，不误清。
            placeXSelCaret(XSelPos(id: sel.anchorId,
                                   off: sel.anchorOff))
            DiagLog.shared.log(.info,
                "EDIT xsel extend \(arrow) "
                + "a=\(sel.anchorId)@\(sel.anchorOff) "
                + "f=\(sel.focusId)@\(sel.focusOff)")
        } else {
            // 步进恰回收拢点（钳后锚焦重合）：选区
            // 不成立、原生选区保持原位（Web setXsel
            // 同支不另落点）。
            DiagLog.shared.log(.info,
                "EDIT xsel extend \(arrow) collapsed")
        }
        return true
    }

    /// 落点投递（既有焦点面：focusBlockId + pending
    /// CaretOffset；UTF-16 → 字符口径经 charOffset
    /// 单点换算，与 E2 选区恢复同链）。
    private func placeXSelCaret(_ pos: XSelPos) {
        guard let unit = xselUnits().first(
            where: { $0.block.id == pos.id }) else { return }
        focusBlockId = unit.block.id
        focusCaretEnd = false
        pendingCaretOffset = EditorModel.charOffset(
            text: unit.block.text, utf16Offset: pos.off)
        pendingSelectionLength = 0
    }

    // ── 动作面 ──

    /// 选区文本（复制面）：xsel 不在位返回 nil。
    func xselClipboardText() -> String? {
        guard let sel = xsel else { return nil }
        return XSelCore.selectedText(
            sel, units: xselUnits().map {
                (id: $0.block.id, text: $0.block.text)
            })
    }

    /// 剪切 = 复制文本（调用方写剪贴板）+ 整段替
    /// 换为空（Web Cmd+X 同序）。
    func cutXSelText() -> String? {
        let t = xselClipboardText()
        replaceXSel(text: "", enter: false)
        return t
    }

    /// 选区替换单点（Web sendReplace 同序）：先清
    /// 选区、再经模型 op 落地；端点已消失（块删
    /// 除后的陈旧跨度）则只清选作废——防陈旧跨度
    /// 被误替换（失效对账的动作面兜底）。只读态
    /// 禁入。
    func replaceXSel(text: String, enter: Bool) {
        guard let sel = xsel else { return }
        guard !library.isReadOnly else {
            clearXSel()
            return
        }
        let units = xselUnits()
        guard let ord = XSelCore.ordered(
            sel, unitIds: units.map { $0.block.id }) else {
            clearXSel()
            DiagLog.shared.log(.info,
                "EDIT xsel stale cleared (endpoint gone)")
            return
        }
        let rawA = XSelPos(id: sel.anchorId, off: sel.anchorOff)
        let rawF = XSelPos(id: sel.focusId, off: sel.focusOff)
        xsel = nil
        replaceRangeUnits(sIdx: ord.sIdx, eIdx: ord.eIdx,
                          sOff: ord.s.off, eOff: ord.e.off,
                          text: text, enter: enter,
                          fromStart: sel.fromStart,
                          toEnd: sel.toEnd,
                          rawA: rawA, rawF: rawF)
    }

    // ── 守卫：失效对账 ──

    /// 原生选区对账（Web selectionchange 同位）：
    /// 组字中先收拢；原生选区展开（长度 > 0）或落
    /// 点离开锚点 → 虚拟选区作废。桥自身落点恒在
    /// 锚点（收拢投递的回读恰合锚点），不误清。
    func noteXSelNativeSelection(blockId: String,
                                 location: Int, length: Int,
                                 marked: Bool) {
        guard xsel != nil else { return }
        if marked {
            collapseXSel()
            return
        }
        guard let sel = xsel else { return }
        if length > 0 {
            clearXSel()
        } else if blockId != sel.anchorId
                    || location != sel.anchorOff {
            clearXSel()
        }
    }

    // ── 呈现查询 ──

    /// 行面覆盖（Web paintXsel 的原子面口径）：
    /// 仅端点容器之间的原子顶层行整行覆盖（Web
    /// 对端点间非可编辑单元整块着色同面）；文本
    /// 单元（含端点块与中间文本块）一律走段内分
    /// 段着色（xselSegment + 属性层），不在行面
    /// ——一期端点恒全文首尾时行面整行与段级等
    /// 价、二期任意端点后按方案分工（分段计算在
    /// XSelCore.segmentRange）。端点失效时不覆盖
    /// （陈旧选区由动作面/对账面收口）。
    func xselRowCovered(_ block: BlockState) -> Bool {
        guard let sel = xsel,
              let t = blocks.firstIndex(
                where: { $0 === block }),
              xselIsAtomicTop(block) else { return false }
        let units = xselUnits()
        guard let ord = XSelCore.ordered(
            sel, unitIds: units.map { $0.block.id })
        else { return false }
        return t > units[ord.sIdx].topIndex
            && t < units[ord.eIdx].topIndex
    }

    /// 段内分段查询（Web paintXsel 段级口径）：
    /// 文本单元在选区内的 UTF-16 段（端点单元取
    /// 端点侧、中间单元整段、同单元取两端点
    /// 间）；非选区单元/选区不在位返回 nil。呈
    /// 现层（BlockTextView 属性层）据此逐单元涂
    /// 段，计算本体在 XSelCore.segmentRange。
    func xselSegment(forBlockId id: String)
        -> (from: Int, to: Int)? {
        guard let sel = xsel else { return nil }
        let units = xselUnits()
        guard let idx = units.firstIndex(
            where: { $0.block.id == id }) else { return nil }
        return XSelCore.segmentRange(
            sel: sel, unitIds: units.map { $0.block.id },
            unitLens: units.map { $0.block.text.utf16.count },
            idx: idx)
    }

    // ── 模型 op：replaceRange（ops.rs 逐支移植） ──

    private func applyXSelRuns(_ b: BlockState,
                               _ runs: [[String: Any]]) {
        b.runs = runs
        b.text = XSelCore.runsText(runs)
        b.nodeVersion += 1
    }

    private func newXSelBlock(item: Bool,
                              runs: [[String: Any]])
        -> BlockState {
        let nb = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8)
                .lowercased(),
            "type": item ? "list-item" : "paragraph",
            "children": [["text": ""]],
        ])
        nb.runs = runs
        nb.text = XSelCore.runsText(runs)
        return nb
    }

    /// 跨块替换（Web op_replace_range）：起止单元
    /// 各取选区外侧 head/tail 行内，中间文本块整
    /// 块删除，head + 插入文本 + tail 并成结果块
    /// 列置于起始单元处；光标落插入末尾（回车落
    /// 尾块首）。K5 分段：端点顶层位之间有原子块
    /// 时按原子边界分段、原子全程存活原位（全选
    /// 时首尾外侧原子同口径存活——ops 注释与方案
    /// §1.5 的定案语义；Web 非 K5 支在 from/to 标
    /// 记下丢外侧原子属其未覆盖边角，本 op 按定
    /// 案语义在双路径外侧支统一保原子，见报告对
    /// 账表）。落盘/撤销经文档正路：pushHistory
    /// 恰一次（单个撤销步，E2 漏斗衔接）+ 排存。
    func replaceRangeUnits(sIdx: Int, eIdx: Int,
                           sOff: Int, eOff: Int,
                           text: String, enter: Bool,
                           fromStart: Bool, toEnd: Bool,
                           rawA: XSelPos, rawF: XSelPos) {
        let units = xselUnits()
        guard units.indices.contains(sIdx),
              units.indices.contains(eIdx) else { return }
        let sU = units[sIdx]
        let eU = units[eIdx]
        let (head, _) = XSelCore.splitRuns(
            sU.block.runs, atUTF16: sOff)
        let (_, tail) = XSelCore.splitRuns(
            eU.block.runs, atUTF16: eOff)
        let sTop = sU.topIndex
        let eTop = eU.topIndex
        let atomsKept = blocks.indices.filter {
            $0 > sTop && $0 < eTop
                && xselIsAtomicTop(blocks[$0])
        }.count

        pushHistory()

        var caretBlock: BlockState = sU.block
        var caretOff16 = 0

        if atomsKept > 0 {
            // ── K5 分段路径 ──
            let seg = XSelCore.k5SegmentColumns(
                head: head, tail: tail, text: text,
                enter: enter)
            applyXSelRuns(sU.block, seg.segCols[0])
            var segBlocks: [BlockState] = [sU.block]
            for col in seg.segCols.dropFirst() {
                segBlocks.append(newXSelBlock(
                    item: sU.itemIndex != nil, runs: col))
            }
            let tailBlock: BlockState? = seg.tailCol.map {
                newXSelBlock(item: eU.itemIndex != nil,
                             runs: $0)
            }
            var out: [BlockState] = []
            for (t, block) in blocks.enumerated() {
                if t < sTop {
                    if !fromStart
                        || xselIsAtomicTop(block) {
                        out.append(block)
                    }
                    continue
                }
                if t > eTop {
                    if !toEnd || xselIsAtomicTop(block) {
                        out.append(block)
                    }
                    continue
                }
                if t == sTop {
                    if sU.itemIndex == nil {
                        out.append(block)
                        out.append(contentsOf:
                            segBlocks.dropFirst())
                    } else if let list = sU.list,
                              let sItem = sU.itemIndex {
                        var kids: [BlockState] = []
                        if !fromStart {
                            kids += list.itemStates[..<sItem]
                        }
                        kids.append(sU.block)
                        kids.append(contentsOf:
                            segBlocks.dropFirst())
                        if fromStart {
                            shiftListStart(list, by: sItem)
                        }
                        list.itemStates = kids
                        list.nodeVersion += 1
                        out.append(list)
                    }
                    continue
                }
                if t == eTop {
                    if let eItem = eU.itemIndex,
                       let list = eU.list {
                        var kids: [BlockState] = []
                        if let tb = tailBlock {
                            kids.append(tb)
                        }
                        if !toEnd {
                            kids += list.itemStates[(eItem + 1)...]
                        }
                        if !kids.isEmpty {
                            shiftListStart(
                                list,
                                by: tailBlock != nil
                                    ? eItem : eItem + 1)
                            list.itemStates = kids
                            list.nodeVersion += 1
                            out.append(list)
                        }
                    } else if let tb = tailBlock {
                        out.append(tb)
                    }
                    continue
                }
                // sTop < t < eTop：原子块存活、其余丢弃。
                if xselIsAtomicTop(block) {
                    out.append(block)
                }
            }
            blocks = out
            if seg.caretInTail, let tb = tailBlock {
                caretBlock = tb
                caretOff16 = seg.caretOff
            } else {
                caretBlock = segBlocks[seg.caretCol]
                caretOff16 = seg.caretOff
            }
        } else {
            // ── 普通路径 ──
            let res = XSelCore.plainResultColumns(
                head: head, tail: tail, text: text,
                enter: enter)
            applyXSelRuns(sU.block, res.cols[0])
            var resBlocks: [BlockState] = [sU.block]
            for col in res.cols.dropFirst() {
                resBlocks.append(newXSelBlock(
                    item: sU.itemIndex != nil, runs: col))
            }
            var out: [BlockState] = []
            for (t, block) in blocks.enumerated() {
                if t < sTop {
                    if !fromStart
                        || xselIsAtomicTop(block) {
                        out.append(block)
                    }
                    continue
                }
                if t > eTop {
                    if !toEnd || xselIsAtomicTop(block) {
                        out.append(block)
                    }
                    continue
                }
                if t == sTop {
                    if sU.itemIndex == nil {
                        out.append(block)
                        out.append(contentsOf:
                            resBlocks.dropFirst())
                    } else if let list = sU.list,
                              let sItem = sU.itemIndex {
                        var kids: [BlockState] = []
                        if !fromStart {
                            kids += list.itemStates[..<sItem]
                        }
                        kids.append(sU.block)
                        kids.append(contentsOf:
                            resBlocks.dropFirst())
                        if fromStart {
                            shiftListStart(list, by: sItem)
                        }
                        if sTop == eTop,
                           let eItem = eU.itemIndex, !toEnd {
                            kids += list.itemStates[(eItem + 1)...]
                        }
                        list.itemStates = kids
                        list.nodeVersion += 1
                        out.append(list)
                    }
                    continue
                }
                if t == eTop {
                    // 止容器（与起始不同）：止项保留其
                    // 后未覆盖项（头部摘除数 = eItem+1，
                    // start 递增同口径）；顶层止块的尾
                    // 行内已抽入结果列、整块丢弃。
                    if let eItem = eU.itemIndex,
                       let list = eU.list, !toEnd {
                        let rest = Array(
                            list.itemStates[(eItem + 1)...])
                        if !rest.isEmpty {
                            shiftListStart(list, by: eItem + 1)
                            list.itemStates = rest
                            list.nodeVersion += 1
                            out.append(list)
                        }
                    }
                    continue
                }
                // sTop < t < eTop：整块在选区内，丢弃。
            }
            blocks = out
            caretBlock = resBlocks[res.caretCol]
            caretOff16 = res.caretOff
        }

        // 原子选中态若指向已删块，随之作废（delete
        // Block 同口径）。
        if let sb = selectedBlockId,
           !blocks.contains(where: { $0.id == sb }) {
            selectedBlockId = nil
        }
        // 光标回落（Web focus_req 同位）：UTF-16 →
        // 字符口径经 charOffset 单点投递既有焦点面。
        focusBlockId = caretBlock.id
        focusCaretEnd = false
        pendingCaretOffset = EditorModel.charOffset(
            text: caretBlock.text, utf16Offset: caretOff16)
        pendingSelectionLength = 0
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT replace range \(rawA.id)@\(rawA.off)"
            + "..\(rawF.id)@\(rawF.off) "
            + "ins=\(text.utf8.count)B enter=\(enter)"
            + (atomsKept > 0
                ? " atoms kept=\(atomsKept)" : ""))
    }
}
