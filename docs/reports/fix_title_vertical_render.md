# 编辑页标题胶囊竖排渲染异常根治（0.9.56 真机回归二）

> 状态：**落码完成、未提交、未 bump**（基线 HEAD fdb1a67 / 0.9.56）。
> 涉事批：U1 的 B-4（提交 ab3c96e）——标题字段由 SwiftUI TextField 换为
> UITextField 的 UIViewRepresentable（TitleTextField.swift）。
> 用户原话只有「渲染异常」四字、且只报竖排（非紧凑坞）、横排未报；
> 本报告先把异常形态推定到具体几种并给出判别法，再以代码机制 proven 的一条定案。

---

## 1. 异常定性：候选形态与判别法

胶囊壳（VStack + padding + `.frame(width: capsuleWidth, height: 66)` +
glassControl）在 B-4 前后逐行同构（git 对照 9d9dd9f ↔ ab3c96e 实证），
两分支（VStack 竖排 / HStack 横排）调用的是同一个 titleCapsule，
B-4 在胶囊内的唯一呈现改动是字段本体。故候选只从字段语义里出：

| 形态 | 描述 | 若成立的成因 | 真机判别（一眼） |
|---|---|---|---|
| **A（定案）** | 竖排下 meta 小字行（时间 · 共×字）几乎贴到胶囊底边，与标题之间裂开一大截空档；标题位置大体正常 | 字段纵向灵活吞余高（§2） | 打开任意一篇、不滚动，看胶囊内下行小字是否贴底、与标题间距是否明显大于横排滚动后的紧凑感 |
| B | 标题文字左右不居中 / 被裁 / 胶囊内文字窄成一团 | representable 宽按内容宽回报（sizeThatFits 内容语义） | 短标题时横排也应同样不居中——横排未报，与此形态矛盾（降为 inferred 不成立） |
| C | 空标题时「无标题」三字呈正文强度（过黑） | 占位色漏复刻（§4 对账 #7） | 新建一篇空标题笔记看胶囊占位字深浅；**与 A 并存的独立缺陷，本批一并修** |
| D | 标题文字整体偏上/偏下数 pt | 字段固有高与旧 SwiftUI 字段行高差 | 与 A 同源（高度未钉），修复后同归零；单独出现时看标题与胶囊上下边距是否对称 |

请用户对图确认的一眼 = **形态 A**：竖排打开一篇笔记，盯胶囊里那行
小字——它离胶囊底边是不是几乎没缝、离标题是不是远得反常。

## 2. 定因（proven：代码 + 框架语义 + 本仓先例三方一致）

**机制链**：

1. `TitleTextField` 未实现 `sizeThatFits`（代码实证，初版全文件无此
   方法）。representable 缺此契约时，SwiftUI 按缺省口径协商尺寸：
   字段成为**纵向可伸缩的灵活视图**（接受提议尺寸；UIKit 文本字段的
   纵向 hugging 为低优先级，本仓 BlockTextView 在同一工具链下已实证
   同类缺省语义会把文本视图的尺寸协商带偏、必须显式 sizeThatFits 钉
   住——其注释即根治记录）。
2. 胶囊内层是 `VStack(spacing: 3)`，外层帧高恒 66。栈在定高内的分
   配规则：定高行取理想高，**余高全归灵活行**。
3. **横排**：VStack 只有字段一行（meta 不渲染）。字段行独占 66 也无
   第二行可挤，字段内文字纵向居中于 66、与旧版「20 高的行成组居中
   于 66」（中心同为 33）视觉等价——**横排无异常，与实报吻合**。
4. **竖排**：字段行与定高的 meta 行（10pt，≈13）共居 66。灵活的字
   段行吞掉全部余高（66 − 3 − 13 ≈ 50，而非旧字段的 ≈20）：两行组
   不再成组居中，meta 行被顶到胶囊最底（底边距 ≈0，旧 ≈15），标
   题文字居中于被撑高的字段行（中心 ≈25，与旧同位——故「标题看
   着正常、只有下行小字掉到底边」正是此形态的指纹）。截断态同理：
   隐形字段（opacity 0）仍在层级参与量测、同样灵活，覆盖层文字居
   中于 50 高的 ZStack，meta 照样掉底。

**证据分级**：胶囊壳同构、字段缺 sizeThatFits、两分支入参差异只有
meta 行与 capsuleWidth 入参——均为代码 proven；「缺省协商 = 纵向灵
活、栈余高归灵活行」为框架文档语义 + 本仓 BlockTextView 先例，两
方一致，机制判 proven；具体像素数（50/15/0 等）为按 10pt meta 行高
与 14pt 字段行高的推演值，标 inferred，不影响机制成立。

**附带排除**：capsuleWidth 公式 B-4 未动（两分支入参：竖排计 metaW、
chrome=0；横排反之——系既有定案口径，非本回归）；glassControl 为尺
寸中性修饰器（background/overlay/clip，无量测参与）；DockSession 锁
存只决定分支选择、不参与胶囊内布局；驱动锚点在 .background，不影
响布局。

## 3. 根治落码（TitleTextField.swift，两分支同构）

修点只在 representable 本体——两分支共用同一字段宿主，契约对两分
支同时生效，不在竖排分支打任何局部补丁：

1. **新增 `sizeThatFits` 尺寸契约**（与 BlockTextView 同门纪律）：
   - 宽：提议宽 definite 时回告提议宽（= 旧 SwiftUI TextField 横向
     灵活、填满标题行的行为）；缺失时以字段内容宽兜底。
   - 高：恒回告字段自身按定格之宽量得的一行自然高
     （`f.sizeThatFits` 即字段本体的内容量测，**量测源与渲染源同
     体**）；纵向提议一律不采。
   - 效果：字段恢复「横向填满、纵向定高」的旧尺寸行为，VStack 余
     高回到成组居中，竖排 meta 行归位、横排同构零变化。此契约同
     时消解形态 B 的不确定性（无论缺省宽语义是哪一支，宽已被钉
     为提议宽）。
2. **占位色复刻**（形态 C）：attributedPlaceholder 的前景色由误填
   的正文主色 `T.textMainUI` 改为 `UIColor.placeholderText`（旧
   SwiftUI 字段占位的系统色）。

合同稳定：`activateTitleFromCapsule(atX:)` 签名未动；`EDIT title *`
Diag 行格式未动（U4a 景的消费面无感）。

## 4. 呈现参数逐项对账（旧 SwiftUI TextField ↔ representable）

| # | 参数 | 旧版 | representable 初版 | 判定 |
|---|---|---|---|---|
| 1 | 字号/字重 | 14 semibold | UIFont 14 semibold（font + defaultTextAttributes） | 等价 ✓ |
| 2 | 字距 | .tracking(−0.2) | defaultTextAttributes kern −0.2 | 等价 ✓（与 capsuleWidth/titlePrefixWidths 量测同源，T26-6 锁） |
| 3 | 对齐 | multilineTextAlignment .center | textAlignment .center | 等价 ✓ |
| 4 | 正文色 | T.textMain | textColor = T.textMainUI（同令牌的 UI 变体） | 等价 ✓ |
| 5 | 宽度行为 | 横向灵活、填满标题行 | 缺省协商（未钉） | **不等价 → sizeThatFits 钉提议宽** |
| 6 | 高度行为 | 纵向定高（一行理想高） | 缺省协商（纵向灵活） | **不等价 → 本回归定因，sizeThatFits 钉自身量测高** |
| 7 | 占位色 | 系统占位色（SwiftUI 缺省） | 误填 T.textMainUI（正文强度） | **漏复刻 → 改 UIColor.placeholderText** |
| 8 | 占位字形 | 字段同字体 14 semibold + 字距 | attributedPlaceholder 同参 | 等价 ✓ |
| 9 | 回车键 | .submitLabel(.done) | returnKeyType .done | 等价 ✓（收口链在 Coordinator，T24-5 锁） |
| 10 | 光标/选区色 | 环境 tint 传播 | SwiftUI 同样向 representable 宿主视图传播 tint | 同源（inferred，未单独设 tintColor——避免与环境传播双写） |

## 5. 断言补强与旧断言为何没拦住

**没拦住的原因**：[24]/[26] 均为源码形态断言，锁的是「在位」——
字段常驻、覆盖层、落点算式、入口签名、量测同源。本缺陷是「**缺席**
」：一个没写的方法。缺省尺寸语义是框架协商性质，不出现在任何源码
行里，存在性 grep 天然看不见；且本仓 BlockTextView 早有同类根治，
但当时没有把「新 representable 必须带尺寸契约」沉淀为跨文件的断
言纪律，B-4 落码时便无人拦。

**本批新增**（verify_ios.sh）：
- **T26-8**（[26]）：尺寸契约本身入断言——TFIELD 段内 sizeThatFits
  函数体须含 `proposal.width` 与字段自身 `sizeThatFits(CGSize(` 量
  测、且 `proposal.height` 零出现（纵向提议不采的机制锁）。
- **T26-9**（[26]）：占位色对账锚——`UIColor.placeholderText` 在位。
- **T24-6**（[24]）：两分支同构锚——titleCapsule 定义恰一处、两分
  支各调一次，禁分支内另起胶囊构造（根治同构性的前提锁）。

本机自跑：[24] 6/6、[26] 9/9 全绿；全脚本仅剩 2 条既有产物类 ✗
（ipa 陈旧 / 产物语言包，tree 构建自解），与基线一致。Swift 编译级
随主线 tree 冒烟（本机无 swiftc；已做括号平衡自查 + 逐段复读）。

## 6. 真机终判点（请用户看的眼）

1. **竖排（主判）**：打开任意一篇笔记、不滚动——胶囊内标题与 meta
   小字应成紧凑一组居中于胶囊：meta 行回到标题下方 3pt 组内位
   置、距胶囊底边留有与上方对称的空档，不再贴底（形态 A 消失）。
2. 竖排截断态（长标题）：覆盖层标题与 meta 的相对位置同上归位。
3. 横排（滚动后）：与 0.9.56 观感一致、零变化（同构回归哨）。
4. 空标题（新建）：「无标题」占位呈系统灰、不再与正文一样黑
   （形态 C）。
5. 编辑态：点胶囊进编辑，标题文字纵向位置与呈现态一致、不跳位；
   落点（点截断标题任意字）行为不变（B-4 原功能回归哨）。

## 7. 改动清单与纪律

| 文件 | 改动 |
|---|---|
| TitleTextField.swift | 文件头补尺寸契约注释；makeUIView 占位色改 placeholderText；新增 sizeThatFits（宽随提议 / 高为字段自身量测） |
| verify_ios.sh | [24] +T24-6；[26] +T26-8、T26-9 |

- 动工前已快照 git diff 并逐 hunk 映射在途批（圆角批的 MomentApp /
  verify 段、布防批的桥文件段、U4a 的 EditorView 段）：本批领地
  （TitleTextField.swift 全文 + verify [24]/[26] 段）与之零交叠；
  完工复验：在途各文件 diff 逐字节一致或仅其自有新 hunk 增长，
  本批未触碰、未回退任何他人 hunk。
- 未提交、未 bump；HEAD 仍 fdb1a67。
