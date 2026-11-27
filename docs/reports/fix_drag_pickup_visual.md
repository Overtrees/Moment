# 拖拽拾起渲染根治报告（0.9.50）：卡片拾起多出白色背景块

- 日期：2026-11-27
- 依据：用户 2026-11-27 真机判读——0.9.49 拾起与拖
  动态已正常（三轮仲裁收官），但卡片块拾起时在原有
  样式基础上多出一层白色背景块；证据截图
  ~/workspace/user/files/F21A1EA4-AA7C-48D7-AAF9-
  FD09645CBEF2-photo-DF07954E-03E6-48C5-9CB4-
  D0779FD0AAAB.jpg（gallery 空图库卡被拾起、卡菜单
  骑拾起呈现中，卡身后多出一块更大的白色圆角板，
  用户红箭头标其左侧外凸缘）。
- 范围：MomentApp.swift（BlockRow.rowBackground 一
  处）、verify_ios.sh（[14] 新增 J14-12）。未碰导航/
  呈现区（过渡重构线）与设置区（MCP 桥线）。
- 状态：落码完成，未提交、未构建（版本与构建由主
  线统一收口，随 0.9.50 出）。本机 verify [14] 组
  十二项全绿；全量仅剩两条既有「本机无构建产物」
  红（ipa 陈旧 / 产物语言包），与本修无关、tree 构
  建后消。本机无 Swift 工具链，语法级校验随 tree
  冒烟。

## 一、定因（证据分级）

**根因（proven，代码级）**：`BlockRow.rowBackground`
在拾起期把行盒底色整体换成 `T.glassTint`（白色
74% 不透明，令牌定义 dynA(0xFFFFFF, 0.74, …)）：

```swift
private var rowBackground: Color {
    if editor.draggingId == block.id { return T.glassTint }
    ...
}
```

该底经 `.background(rowBackground, in:
RoundedRectangle(cornerRadius: 12))` 绘于**行盒**
全框。行盒 ≠ 视觉面：image / gallery 两型的视觉
面在行盒内左右各内缩 36pt（Web 口径，行内
`.padding(.horizontal, columnsActive ? 0 : 36)`），
行盒底遂在面的左右各外凸 36pt、高与行齐——正是
截图里那块「比卡大、向两侧探出」的白色圆角板。

**几何对账（proven，量测）**：截图视觉量测（归一
化 0–1000）——内容列（顶部图片块与图库瓦面同宽）
x 130–850；白板 x 48–951。白板比面宽出左侧 ≈82、
右侧 ≈101 单位（≈32–39pt，量测噪声内与 36pt 内
缩量吻合）；纵向白板 y 518–943 与瓦面 516–949 近
齐（内缩只在横向，行高即面高）——与「行盒底」假
设逐项吻合。用户所述「向左下偏移」即横向外凸在
左侧最显（红箭头标处）+ 板缘在卡下沿露出的观感。

**排除项（逐一对源码核）**：

- 拾起快照自带白底——不存在快照：原生拾起是行本
  体经 scaleEffect + offset 跟手（与 Web「单元本
  体即浮块」同构），无 snapshot 视图参与。
- 玻璃框被做成实心填充——LiftFrame 是
  `.glassCard`（ultraThinMaterial + glassTint 叠
  + 0.5 描边）绘于视觉面 ⊕4 处，是 Web
  `.mn-lifted::before` 的规格内对应物，截图中瓦
  面四周的细框即它，保留不动。
- 原位占位渲染成白块——原生无原位占位渲染：行本
  体即浮块、原位只余兄弟让位（dragShift），与
  Web 一致（Web 拾起期原单元本体抬升跟指、无占
  位克隆）。白板随行同移、非留在原位之物。

## 二、Web 规格对账（editor.css / editor.js 口径）

- `.mn-lifted` 本体只加 `position: relative;
  z-index: 30`——**不给单元加底、不换底**，单元保
  持自身外观被抬升。
- 拾起框由 `::before` 按 resolveLiftSurface 的视
  觉面几何（面 ⊕ LIFT_INSET 4、半径 = 面半径 + 4
  同心）绘制，材质 glass-content，z-index -1 居
  内容之下。
- 缩放 liftScaleFor 由桥内联驱动单元 transform，
  单元自身底色全程不变。

原生现状对账：LiftFrame（面 ⊕4、半径 +4、玻璃材
质、挂面 background 层随行缩放）与缩放口径均已
合规格；唯一越界者就是行盒底的拖动态换色——它既
不是框也不是面自身底，是规格外多出的一层。

## 三、改动清单

1. **MomentApp.swift · BlockRow.rowBackground**：
   删除 `if editor.draggingId == block.id { return
   T.glassTint }` 一行——行底恒返回块自身常态底
   （callout 语义底 / quote 淡底 / codeBlock 代码
   底 / 余皆 .clear），拾起与否同值。拾起反馈自
   此由 LiftFrame + liftScale 缩放 + zIndex 专责，
   与 Web 分工一致。函数头补定案注释（根因、波及
   面、清零口径）。
2. **verify_ios.sh [14] 新增 J14-12**：抽取
   rowBackground 函数体，断言其中零 `draggingId`、
   零 `glassTint`——锁「拾起行底恒常态」，防拖动态
   换底写法以任何形式回潮。本机自跑 [14] 组
   J14-1…J14-12 全绿。

尾巴清零核查：`T.glassTint` 落码后仅剩令牌定义与
GlassCard（浮层/框材质）的正当消费，无孤儿、无其
他按 draggingId 换底的消费方（全文件 grep 已核）。

## 四、文本块影响面

同根同修，无需另动代码：

- 文本系（paragraph / heading / todo / list /
  divider / embedCard 等）：面即行盒，白板不外
  凸，但拾起期文字背后凭空多一层 74% 白板（常
  态为 .clear）——与 Web「文本块拾起保持透明
  底」不符，同属本缺陷，删行后一并消失。
- quote / callout / codeBlock：面即行盒，但拾起
  期自身淡底（quoteBg / calloutBg / codeBg）被
  glassTint 整块覆盖，属换底型同根问题，删行后
  拾起期保持自身淡底。
- 卡系（musicCard / link-card / imgTextCard /
  imageTextRow）：面即行盒且自带实色卡面，行盒
  底被卡面遮住大部，仅角部（行底半径 12 vs 卡
  面半径 32）可能露白边，同根删行后清零。
- image（有图）：面是图本体（居中、宽 ≤ 自然
  宽），行盒底在图两侧及上下留白区成板，外凸
  形态与 gallery 同型（横向尤甚），删行后清零；
  image 无图占位面即行盒，同文本系。

## 五、真机判读口径（下一包）

装 0.9.50 后拾起任一 gallery / image 块：卡身后
应只有规格内的玻璃框（面外扩 4 的细玻璃边），不
再有行盒级白板；拾起文本块应保持透明底。截图对
照本报告第一节量测口径即可判。
