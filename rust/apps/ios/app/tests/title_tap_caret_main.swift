// ── TitleTapCaret 数值断言（方案 plan_title_
// tap_caret.md §5.2）──
// 与 TitleTapCaret.swift 一起在 tree 上以
// swiftc 独立编译真跑：
//   swiftc TitleTapCaret.swift \
//     tests/title_tap_caret_main.swift -o /tmp/t
// 预置宽度表（模拟字形宽）：ASCII 标量 7pt、
// CJK 标量 14pt、省略号 14pt、astral 标量
// 16pt、组合附加符 0pt。期望值按算式（居中 →
// 相对偏移 → 逐前缀全扫最近、同距取较后边界）
// 逐个算定；簇内位一例只锁算式（实机期望为平
// 台吸附后的簇边界，不作红绿判据，见注释）。

import Foundation

var failures = 0
var total = 0

func check(_ name: String, _ actual: Int, _ expected: Int) {
    total += 1
    if actual == expected {
        print("PASS \(name) = \(actual)")
    } else {
        failures += 1
        print("FAIL \(name): got \(actual), want \(expected)")
    }
}

/// 模拟字形宽（pt）。
func simWidth(_ s: Unicode.Scalar) -> Double {
    if s == "…" { return 14 }
    if s.value > 0xFFFF { return 16 }
    if (0x0300...0x036F).contains(s.value) { return 0 }
    if s.value >= 0x2E80 { return 14 }
    return 7
}

/// 由全文构造显示串（前 10 标量 + …）并量其逐
/// 前缀宽——与 App 调用点的分工同形（App 侧以
/// UIKit 同源属性量测，此处以模拟表代替）。
func prefixWidths(of full: String) -> [Double] {
    var disp: [Unicode.Scalar] = Array(
        full.unicodeScalars.prefix(10))
    disp.append("…")
    var out: [Double] = []
    var acc = 0.0
    for s in disp {
        acc += simWidth(s)
        out.append(acc)
    }
    return out
}

func caret(_ full: String, tapX: Double,
           rowW: Double) -> Int {
    TitleTapCaret.caretScalarIndex(
        fullScalarCount: full.unicodeScalars.count,
        prefixWidths: prefixWidths(of: full),
        tapX: tapX, rowW: rowW)
}

// ── 例 1：ASCII 长标题（20 标量）──
// 前缀宽 [7,14,…,70,84]，dispW=84，rowW=200 →
// startX=58。
let ascii = "abcdefghijklmnopqrst"
check("left-outside", caret(ascii, tapX: 50, rowW: 200), 0)
check("at-startX", caret(ascii, tapX: 58, rowW: 200), 0)
check("beyond-right", caret(ascii, tapX: 200, rowW: 200), 20)
check("char3-center+1", caret(ascii, tapX: 76.5, rowW: 200), 3)
check("char3-center-1", caret(ascii, tapX: 74.5, rowW: 200), 2)
check("char10-center+1", caret(ascii, tapX: 125.5, rowW: 200), 10)
check("ellipsis-center", caret(ascii, tapX: 135, rowW: 200), 20)
check("midpoint-1", caret(ascii, tapX: 134, rowW: 200), 10)
check("midpoint+1", caret(ascii, tapX: 136, rowW: 200), 20)

// ── 例 2：CJK 长标题（15 标量）──
// 前缀宽 [14,28,…,140,154]，dispW=154，rowW=
// 200 → startX=23。字 5 中心 rel=63 与前后边
// 界同距 → 取较后边界 5。
let cjk = String(repeating: "标", count: 15)
check("cjk-char5-center", caret(cjk, tapX: 86, rowW: 200), 5)
check("cjk-char1-near", caret(cjk, tapX: 29, rowW: 200), 1)

// ── 例 3：astral 混排 ──
// 全文 a + 😀 + b..p（17 标量）；显示串前缀宽
// [7,23,30,37,…,79,93]，startX=53.5（rowW=
// 200）。边界 3 的 rel=30 → tapX=83.5。
let astral = "a\u{1F600}bcdefghijklmnop"
check("astral-caret3", caret(astral, tapX: 83.5, rowW: 200), 3)
let astralScalars = Array(astral.unicodeScalars)
check("utf16-of-0",
      TitleTapCaret.utf16Offset(ofScalarIndex: 0,
                                in: astralScalars), 0)
check("utf16-of-2",
      TitleTapCaret.utf16Offset(ofScalarIndex: 2,
                                in: astralScalars), 3)
check("utf16-of-3",
      TitleTapCaret.utf16Offset(ofScalarIndex: 3,
                                in: astralScalars), 4)
check("utf16-of-end",
      TitleTapCaret.utf16Offset(ofScalarIndex: 17,
                                in: astralScalars), 18)

// ── 例 4：全文恰 11 标量 ──
// 截断显示同形（10+…）；省略号中心 → 11（=
// 全文末尾，与「第 10 字后」相邻不冲突）。
let eleven = "abcdefghijk"
check("eleven-ellipsis", caret(eleven, tapX: 135, rowW: 200), 11)

// ── 例 5：簇内位（标注例，只锁算式）──
// 全文 e + 组合尖音符 + clairpluslong（15 标
// 量）；显示串前缀宽 [7,7,14,21,…,63,77]。
// tap 落 rel=7（e 的字形内）→ 算式按同距取较
// 后边界出 2（簇末标量位）。实机上 UITextField
// 对簇内选区吸附到最近簇边界，期望以平台吸
// 附为准——此例不作实机红绿判据，仅防算式漂
// 移（方案 §3.4/§5.2 标注例）。
let cluster = "e\u{301}clairpluslong"
check("cluster-formula", caret(cluster, tapX: 200, rowW: 200), 15)
check("cluster-inside",
      caret(cluster, tapX: (200 - 77) / 2 + 7, rowW: 200), 2)

print("----")
print("\(total - failures)/\(total) passed")
if failures > 0 {
    print("RESULT: FAIL")
    exit(1)
}
print("RESULT: ALL PASS")
