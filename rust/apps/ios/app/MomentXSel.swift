// ── 跨块选区桥接层（F-09 一期，定案 plan_cross_
// block_selection.md §8.1 / impl_cross_block_
// selection_p1.md）──
// 与 Web 桥内虚拟选区 xsel 同构：原生每块一个
// UITextView、系统选区被钳在宿主内，故在模型层
// 维护虚拟选区（端点 = 块 id + UTF-16 偏移，与
// Web caretInfo 同口径），编辑动作经 replaceRange
// 模型 op 落地，原生选区同时收拢到锚点避免双重
// 显示。一期范围 = 全选动作面（Cmd+A / 系统菜单
// 全选建立全文选区）+ 动作面（复制/剪切/删除/
// 回车/覆打/粘贴替换）+ replaceRange op（含 K5
// 原子存活分段、列表 start 修正）+ 守卫集（只读
// 禁入、组字收拢、失效对账、块消失回退）；二期
// （本文件尾段）= Shift+方向任意端点扩展的纯决
// 策（stepChar/横向接管判定/纵向几何决策/段内
// 分段计算），量测与状态机在桥接层；触摸跨块
// 拖选缓做（Web 触摸端亦无，两端等价）。
// 本文件仅依赖 Foundation：纯核心 XSelCore（端
// 点排序/守卫钳制/选区文本/行内劈分/结果列计
// 算）可独立编译做表驱动断言（verify [50]
// X50-2，沿 E47-3 先例）；状态机与模型 op 在伴
// 生文件 MomentXSelBridge.swift（EditorModel 扩
// 展）；系统剪贴板等 UIKit 面留在 MomentApp.
// swift 的调用点，模型层不碰。

import Foundation

/// 虚拟选区（Web xsel 同形）：锚/焦端点 + 全文
/// 标记（Cmd+A 建立时置位，replaceRange 的首尾
/// 外侧处置口径）。
struct XSel: Equatable {
    var anchorId: String
    var anchorOff: Int
    var focusId: String
    var focusOff: Int
    var fromStart: Bool
    var toEnd: Bool
}

/// 选区端点（块 id + UTF-16 偏移）。
struct XSelPos: Equatable {
    var id: String
    var off: Int
}

/// 扩展方向（二期 Shift+方向的桥接层入参口径）。
enum XSelDirection {
    case left, right, up, down
}

/// 守卫/排序用的单元信息（纯值）。
struct XSelUnitInfo: Equatable {
    var id: String
    var isSource: Bool
    var utf16Length: Int
}

enum XSelCore {

    // ── 行内 runs 基础 ──
    // 原生 runs 是拍平的行内段列（link 段以 _link
    // 键保真，与 Web 行内节点列同构）：劈分保留每
    // 段全部标记键，落盘时由 childrenFrom 重组。

    static func runText(_ r: [String: Any]) -> String {
        r["text"] as? String ?? ""
    }

    static func runsText(_ runs: [[String: Any]]) -> String {
        runs.map { runText($0) }.joined()
    }

    static func runsUTF16Length(_ runs: [[String: Any]]) -> Int {
        runs.reduce(0) { $0 + runText($1).utf16.count }
    }

    static func textRun(_ s: String) -> [String: Any] {
        ["text": s]
    }

    /// UTF-16 偏移 → String.Index（Web utf16_byte_
    /// index 同口径：按 Unicode 标量累加，偏移落
    /// 在标量内部时进到该标量之后——光标偏移恒在
    /// 边界上，此为防御钳制）。
    static func utf16Index(_ s: String, _ off: Int)
        -> String.Index {
        if off <= 0 { return s.startIndex }
        var acc = 0
        var i = s.unicodeScalars.startIndex
        while i < s.unicodeScalars.endIndex {
            if acc >= off { return i }
            acc += s.unicodeScalars[i].value >= 0x10000
                ? 2 : 1
            i = s.unicodeScalars.index(after: i)
        }
        return s.endIndex
    }

    static func utf16Slice(_ s: String, from: Int, to: Int)
        -> String {
        let lo = utf16Index(s, max(from, 0))
        let hi = utf16Index(s, max(to, 0))
        guard lo < hi else { return "" }
        return String(s[lo..<hi])
    }

    /// 按 UTF-16 偏移劈行内段列（Web split_inlines_
    /// at 的拍平形）：整段归侧按 rest 与段长比较逐
    /// 支同构；段内劈点克隆段分置两侧、空半段不
    /// 留（Web 同口径）。
    static func splitRuns(_ runs: [[String: Any]],
                          atUTF16 off: Int)
        -> (head: [[String: Any]], tail: [[String: Any]]) {
        var head: [[String: Any]] = []
        var tail: [[String: Any]] = []
        var rest = max(off, 0)
        var done = false
        for r in runs {
            if done { tail.append(r); continue }
            let t = runText(r)
            let l = t.utf16.count
            if rest > l {
                head.append(r)
                rest -= l
                continue
            }
            if rest == l {
                head.append(r)
                done = true
                continue
            }
            if rest == 0 {
                tail.append(r)
                done = true
                continue
            }
            // 0 < rest < l：段内劈（l > 0 保证文本在位）。
            let idx = utf16Index(t, rest)
            let h = String(t[..<idx])
            let tl = String(t[idx...])
            if !h.isEmpty {
                var hr = r
                hr["text"] = h
                head.append(hr)
            }
            if !tl.isEmpty {
                var tr = r
                tr["text"] = tl
                tail.append(tr)
            }
            done = true
        }
        return (head, tail)
    }

    // ── 端点排序与守卫 ──

    /// 有序端点（Web xselOrder 同口径）：按单元序
    /// 排，端点块已消失返回 nil（调用方据此作废
    /// 选区——块消失回退守卫）。
    static func ordered(_ sel: XSel, unitIds: [String])
        -> (s: XSelPos, e: XSelPos, sIdx: Int, eIdx: Int)? {
        guard let ai = unitIds.firstIndex(of: sel.anchorId),
              let fi = unitIds.firstIndex(of: sel.focusId)
        else { return nil }
        if ai < fi
            || (ai == fi && sel.anchorOff <= sel.focusOff) {
            return (XSelPos(id: sel.anchorId,
                            off: sel.anchorOff),
                    XSelPos(id: sel.focusId,
                            off: sel.focusOff), ai, fi)
        }
        return (XSelPos(id: sel.focusId, off: sel.focusOff),
                XSelPos(id: sel.anchorId, off: sel.anchorOff),
                fi, ai)
    }

    /// 源码态禁区钳制（Web guardSpan 逐支同构）：
    /// 选区不得跨越源码态块——焦点端钳到首个源码
    /// 块的近侧边界（前行块尾 / 后行块首）。一期
    /// 全选走 whole 路径不经此钳（Web setXsel 同口
    /// 径），二期任意端点扩展经此入。
    static func guardSpan(anchor: XSelPos, focus: XSelPos,
                          units: [XSelUnitInfo]) -> XSelPos {
        guard let ai = units.firstIndex(
                where: { $0.id == anchor.id }),
              let fi = units.firstIndex(
                where: { $0.id == focus.id }),
              ai != fi
        else { return focus }
        let step = ai < fi ? 1 : -1
        var i = ai + step
        while step > 0 ? i <= fi : i >= fi {
            if units[i].isSource {
                let nb = units[i - step]
                return step > 0
                    ? XSelPos(id: nb.id, off: nb.utf16Length)
                    : XSelPos(id: nb.id, off: 0)
            }
            i += step
        }
        return focus
    }

    /// 选区文本（Web xselText 同口径）：逐单元切
    /// 片、块间以 \n\n 连接（原子块不入文本面，
    /// Web 同口径）。
    static func selectedText(
        _ sel: XSel,
        units: [(id: String, text: String)]) -> String? {
        guard let ord = ordered(sel,
                                unitIds: units.map { $0.id })
        else { return nil }
        var parts: [String] = []
        for i in ord.sIdx...ord.eIdx {
            let t = units[i].text
            let from = i == ord.sIdx ? ord.s.off : 0
            let to = i == ord.eIdx ? ord.e.off
                : t.utf16.count
            parts.append(utf16Slice(t, from: from, to: to))
        }
        return parts.joined(separator: "\n\n")
    }

    // ── replaceRange 结果列计算（ops.rs 双路径） ──

    /// 普通路径结果列（Web op_replace_range 非 K5
    /// 段）：头 + 插入文本逐行成列、尾行内并入末
    /// 列；光标落插入末尾（回车时落尾列首）。
    struct PlainResult {
        var cols: [[[String: Any]]]
        var caretCol: Int
        var caretOff: Int
    }

    static func plainResultColumns(
        head: [[String: Any]], tail: [[String: Any]],
        text: String, enter: Bool) -> PlainResult {
        let headLen = runsUTF16Length(head)
        if enter {
            return PlainResult(cols: [head, tail],
                               caretCol: 1, caretOff: 0)
        }
        let lines = text.components(separatedBy: "\n")
        var cols: [[[String: Any]]] = []
        var first = head
        if !lines[0].isEmpty {
            first.append(textRun(lines[0]))
        }
        cols.append(first)
        if lines.count > 2 {
            for mid in lines[1..<(lines.count - 1)] {
                cols.append(mid.isEmpty
                    ? [] : [textRun(mid)])
            }
        }
        if lines.count > 1 {
            let last = lines[lines.count - 1]
            var lastKids: [[String: Any]] = []
            if !last.isEmpty {
                lastKids.append(textRun(last))
            }
            lastKids.append(contentsOf: tail)
            cols.append(lastKids)
            return PlainResult(
                cols: cols, caretCol: cols.count - 1,
                caretOff: last.utf16.count)
        }
        cols[0].append(contentsOf: tail)
        return PlainResult(
            cols: cols, caretCol: 0,
            caretOff: headLen + text.utf16.count)
    }

    /// K5 分段路径列（Web 同段）：首段承接 head +
    /// 插入文本逐行成列（尾行内不并入首段、由末
    /// 段新块承接）；非回车且尾为空时不立尾块
    /// （全选清空后只留首段一个空段承载光标）。
    struct K5Result {
        var segCols: [[[String: Any]]]
        var tailCol: [[String: Any]]?
        var caretInTail: Bool
        var caretCol: Int
        var caretOff: Int
    }

    static func k5SegmentColumns(
        head: [[String: Any]], tail: [[String: Any]],
        text: String, enter: Bool) -> K5Result {
        let headLen = runsUTF16Length(head)
        var segCols: [[[String: Any]]] = []
        var caretInTail = false
        var caretCol = 0
        var caretOff = 0
        if enter {
            segCols = [head]
            caretInTail = true
        } else {
            let lines = text.components(separatedBy: "\n")
            var first = head
            if !lines[0].isEmpty {
                first.append(textRun(lines[0]))
            }
            segCols.append(first)
            for mid in lines.dropFirst() {
                segCols.append(mid.isEmpty
                    ? [] : [textRun(mid)])
            }
            caretCol = segCols.count - 1
            caretOff = lines.count > 1
                ? lines[lines.count - 1].utf16.count
                : headLen + text.utf16.count
        }
        let tailCol: [[String: Any]]?
        if enter {
            tailCol = tail
        } else if tail.allSatisfy({ runText($0).isEmpty }) {
            tailCol = nil
        } else {
            tailCol = tail
        }
        return K5Result(segCols: segCols, tailCol: tailCol,
                        caretInTail: caretInTail,
                        caretCol: caretCol,
                        caretOff: caretOff)
    }

    // ── 二期：Shift+方向端点扩展（Web xselExtend
    // 逐支同构；几何量测在桥接层，决策在此纯算） ──

    /// 字符步进（Web stepChar 逐支同构）：按
    /// Unicode 标量步进、不劈代理对（偏移恒
    /// UTF-16）——块内步进一格、块界跨到相邻单
    /// 元的邻界、文档首尾原地钳住。
    static func stepChar(
        units: [(id: String, text: String)],
        idx: Int, off: Int, dir: Int) -> XSelPos {
        let u = units[idx]
        let t = u.text as NSString
        let len = t.length
        if dir > 0 {
            if off < len {
                let c = t.character(at: off)
                return XSelPos(
                    id: u.id,
                    off: off + ((c >= 0xD800 && c <= 0xDBFF)
                        ? 2 : 1))
            }
            if idx + 1 < units.count {
                return XSelPos(id: units[idx + 1].id, off: 0)
            }
            return XSelPos(id: u.id, off: len)
        }
        if off > 0 {
            let c = t.character(at: off - 1)
            return XSelPos(
                id: u.id,
                off: off - ((c >= 0xDC00 && c <= 0xDFFF)
                    ? 2 : 1))
        }
        if idx > 0 {
            let p = units[idx - 1]
            return XSelPos(id: p.id,
                           off: (p.text as NSString).length)
        }
        return XSelPos(id: u.id, off: 0)
    }

    /// 横向扩展决策（Web xselExtend 左右支）：步
    /// 进结果——原无选区且步进未跨出焦点单元 →
    /// nil（放行原生块内扩展，保原生选区粒度）；
    /// 已有选区或已跨界 → 新端点对（锚不动、焦
    /// 点取步进结果，其后经 setXSel 的 guardSpan
    /// 与重合归 nil 口径）。焦点单元不在表中 →
    /// nil（不接管）。
    static func extendHorizontal(
        anchor: XSelPos, focus: XSelPos, hadSel: Bool,
        dir: Int,
        units: [(id: String, text: String)])
        -> (anchor: XSelPos, focus: XSelPos)? {
        guard let fi = units.firstIndex(
            where: { $0.id == focus.id }) else { return nil }
        let nf = stepChar(units: units, idx: fi,
                          off: focus.off, dir: dir)
        if !hadSel && nf.id == focus.id { return nil }
        return (anchor, nf)
    }

    /// 纵向扩展决策（Web xselExtend 上下支）：几
    /// 何量测由桥接层给——onEdge = 焦点行是焦点
    /// 单元的首/末视觉行（Web 以光标矩形与块矩
    /// 形的边缘判定近似之，原生以 TextKit 行盒
    /// 直判，决策等值而量测更准）；sameHit = 非
    /// 边缘时块内相邻行的 hit-test 结果；crossHit
    /// = 边缘且相邻单元存在时其边行 hit-test 结
    /// 果（量测无果时桥接层已折入 Web 兜底位：
    /// ↑ 目标尾 / ↓ 目标首）；docClamp = 边缘且
    /// 无相邻单元时的文档端钳位（↑ 首单元首 /
    /// ↓ 焦点单元尾）。
    /// 决策：非边缘——原无选区 → nil（放行原
    /// 生），已有选区 → sameHit（无果 → nil，
    /// 与 Web pointFromXY 无果同支）；边缘——
    /// crossHit 优先；仅 docClamp 时原无选区且
    /// 钳位恰合焦点 → nil（Web 同支的等值判
    /// 定），余皆取钳位。
    static func verticalFocus(
        hadSel: Bool, focus: XSelPos, onEdge: Bool,
        sameHit: XSelPos?, crossHit: XSelPos?,
        docClamp: XSelPos?) -> XSelPos? {
        if !onEdge {
            guard hadSel else { return nil }
            return sameHit
        }
        if let crossHit { return crossHit }
        guard let docClamp else { return nil }
        if !hadSel && docClamp == focus { return nil }
        return docClamp
    }

    /// 段内分段（Web paintXsel 段级口径）：第
    /// idx 个单元在选区内的 UTF-16 段——起单元
    /// 取 [起端点, 尾]、止单元取 [首, 止端点]、
    /// 同单元取两端点间、中间单元整段；不在有
    /// 序跨度内（或端点已消失）→ nil。呈现层据
    /// 此逐单元涂段（原子行整行着色另经行面判
    /// 定，不在此）。
    static func segmentRange(
        sel: XSel, unitIds: [String], unitLens: [Int],
        idx: Int) -> (from: Int, to: Int)? {
        guard let ord = ordered(sel, unitIds: unitIds),
              idx >= ord.sIdx, idx <= ord.eIdx
        else { return nil }
        let from = idx == ord.sIdx ? ord.s.off : 0
        let to = idx == ord.eIdx ? ord.e.off : unitLens[idx]
        return (from, to)
    }
}

