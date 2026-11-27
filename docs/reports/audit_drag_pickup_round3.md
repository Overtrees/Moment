# 拖拽拾起第三轮排查报告（0.9.47 真机证据定因）

- 日期：2026-11-27
- 性质：只排查、未落码。证据 = 用户 0.9.47 真机 Diag 导出
  （`~/workspace/user/files/2026-11-27_11-23.log`，0.9.47 会话自
  [11:21:42] `SMOKE v=0.9.47` 起）+ 现行源码通读
  （MomentDrag.swift 全文、MomentApp.swift 行侧/文本视图相关段、
  Web 移植版 editor.js 按压状态机与 pickup 全文）。
- 前轮报告：fix_drag_pickup_round2.md（0.9.47 落码依据）。

## 结论先行

0.9.47 的引擎接线无误：识别器挂载、触摸认领（shouldReceive）两次
真机命中并留痕，断点确认在「认领成功 → 识别器从未 began」之间。
参数层与 Web 原版**逐项等值**（触摸 480ms / 按压期移动容忍 10px，
已证伪「Web 容忍更高」一说）；真正的结构差不在参数，而在**仲裁
豁免权**：Web 的按压计时器除三条明文清除路径外没有任何东西能让
它失败，原生引擎却只对宿主 pan 一家开了并行、对触点路径上其余
全部识别器维持默认互斥——而第二轮报告自己点名、却无从移除的
UITextView 内部识别器组（选区长按 + 文本拖放 lift），恰好还在这
个互斥面里。两次失败尝试全部落在 UITextView 承载的文本块上，
同一会话内六次合规静止长按全部落在非文本的卡片行上并全部成功
（走的是另一枚 SwiftUI 识别器）——这是本轮最强的对照证据。
手势形状（认领后在 0.48s 内即大幅移动）与上述结构因在现有日志
的 1 秒分辨率下不可完全分离，故主因归因标 inferred；两者由同一
组落码动作覆盖（并行姿态放开 + 打点补全），且补全后的打点能让
下一包一句话指认死点（见第五、六节）。

## 一、真机时序复盘（0.9.47 会话）

日志时间戳分辨率 1 秒——同秒内的先后与亚秒时长不可分辨，此点
贯穿全篇评级。

### 尝试 A：11:22:04，目标 g3

- [11:22:04] `APP row open guide` → `DRAG engine attached` →
  `DRAG press target id=g3`。
- 同秒 SCROLL 三行：y=120 v=47 → y=−204 v=372 → y=−382 v=550；
  [11:22:05] y=−496 v=664。内容位移同秒内 ≥500pt、速度单调上
  升 = 手指驱动的滚动在按压窗内已经发生（动量衰减应为速度递
  减，可排除「触摸落在既有动量上」为同秒滚动的解释）。
- g3 的身份（proven）：种子指南块 id（MomentApp.swift:1779 种
  子 JSON `{"id":"g3","type":"todo","checked":true}`，文案「列表：
  日期分组、搜索、下拉外手势都已接」）。即一个 **todo 块**：
  行内左侧 44pt 勾选钮（UIButton）+ 右侧 UITextView 文本区。
  press target 既已记，触点必不在勾选钮上（shouldReceive 对
  UIButton 命中先行 return false 且不记 target）——触点落在
  文本区（UITextView）或行内边距，主体概率在 UITextView 上。
- 结果：无 pickup / drop / cancel 行。

### 尝试 B：11:22:23，目标 b-453d26c4

- [11:22:23] `DRAG press target id=b-453d26c4`；同秒 SCROLL
  y=−465 v=633 → y=−780 v=948，[11:22:24] y=−733 → −440 →
  [11:22:25] y=125 → 196 v=0。与尝试 A 同型：认领同秒内大幅
  滚动。
- 该 id 的块型：日志内无其他行可直接对型（unknown）；但会话流
  可证其为 guide 篇内块（11:22:04 打开 guide、11:22:29 才
  SCROLL close），而 guide 的 16 块中武装（非卡片）类型只有
  heading / quote / todo / paragraph——**全部为 UITextView 承
  载的文本块**（按库存交集推定，inferred 上限、接近 proven）。

### 对照组：同会话六次卡片行长按全部成功

- image 卡 b-fd2e9489：[11:22:05] `press disarmed` →
  [11:22:06] `EDIT card menu open`，其后 [11:22:12]、[11:22:17]
  又各开一次；
- gallery 卡 b-10dbbb60（新篇内）：[11:22:34] disarmed →
  [11:22:35]、[11:22:38]、[11:22:45] 三次 menu open。
- 卡片菜单走 CardMenuGesture = SwiftUI `onLongPressGesture(
  minimumDuration: 0.48)`（MomentApp.swift:7459），其
  maximumDistance 用 SwiftUI 默认值 10pt。即：**同一会话、同
  一滚动视图下，一枚 0.48s/10pt 的长按识别器在卡片行上六次
  全部完成**——证明（proven）：① 用户在本会话内的静止长按
  手势能够满足 0.48s/10pt 口径；② 滚动视图环境本身不妨碍
  长按完成。引擎的两次失败因此不能归因于「用户不会静止长
  按」或「滚动视图有毒」这类全局因素；差异变量收敛到两点：
  目标行类型（文本 vs 卡片）与识别器仲裁姿态（引擎 vs
  SwiftUI 长按的接法不同）。

### 注册面核查（对应排查项 ⑤）

- 全仓 DragPressAnchor 只有一个注册点：BlockRow 的
  `.background(DragPressAnchor(blockId: block.id, enabled:
  dragAllowed, …))`（MomentApp.swift:7717）。无 gallery 子项
  锚点、无组锚点混入——g3 不是画廊子项，它就是 todo 块本身
  的块 id（proven）。
- 武装口径 dragAllowed（MomentApp.swift:7960）：卡片类恒
  false（走菜单）；文本块仅「本块正处编辑态」时 false，其
  余恒 true。故卡片 disarmed、g3/b-453d26c4 armed 是设计内
  结果，注册面无污染（proven）。

## 二、Web 原版按压引擎精确语义（editor.js:2760–2842、2527–2585）

移植版 editor.js 的按压状态机即原版语义的现行载体，逐项如下
（触摸口径为准，鼠标口径附注）：

| 项 | Web 触摸/笔 | Web 鼠标 | 原生引擎（MomentDrag.swift） |
|---|---|---|---|
| 拾起时长 | 480ms 定时器（全块型一律） | 文本块静止 hold 280ms；原子/组合块无 hold | minimumPressDuration = 0.48s |
| 按压期移动容忍 | 位移² > 100（即 >10px 欧氏）→ clearPress 放弃本次按压 | 文本块 >6px 放弃（判选词）；非文本块 ≥6px **立即拾起** | allowableMovement = 10（识别前位移上限，超限 .failed） |
| 移动先于拾起 | 超 10px 即取消武装，页面照常滚动；不接续、不补拾 | 非文本块是「接续拾起」（见上行）；文本块永久放弃 | 超 10pt 即失败、页面滚动；与 Web 触摸同构 |
| 文本块武装条件 | 光标在本块内 → **不武装**（选词接管）；不在 → 武装并临时 user-select:none 防选区抢跑 | 同左（hold 路径） | 本块处编辑态 → 不武装（editingBlockId 近似光标口径） |
| 排除面 | button/input/textarea/select/label/.todo-checkbox 命中不武装；composing 中不武装 | 同左 + 非左键不武装 | UIButton 命中不接管；余靠行 enabled |
| 拾起后接管 | pickup() 以**按下点**为 drag.sx/sy，window 捕获级 pointermove/up/cancel 全程所有；拖动期 touchmove preventDefault 止滚 | 同左 | began 后行回调接管，dy 相对窗口起点 Y；拾起即锁 isScrollEnabled 止滚 |
| **可被谁强制失败** | **无**：除 pointermove 超限、pointerup、pointercancel、新 pointerdown 四条明文路径外，没有任何机制能杀掉一个已武装的 press；选区/滚动都不构成仲裁方 | 同左 | **有**：默认互斥下，任一非并行识别器先认出即可把本识别器打入 .failed（见第三节 ③④） |

对差判定（proven）：**触摸参数三项（480ms、10px、超限即弃）逐
项等值**，「Web 容忍更高/口径不同」的假设证伪。唯一的实质差
是最后一行——仲裁豁免权。Web 的 user-select:none 临时抑制说
明原版明确意识到「选区会抢跑」并在源头压住；原生侧对应的压
制手段不在参数里，在识别器关系里（第三节）。

## 三、began 失败候选逐项验

前提事实（proven）：shouldReceive 两次返回 true 并记 target，
故触摸已交付引擎识别器；handle() 的 .failed/.cancelled 分支在
picked==false 时不记任何日志——识别器无论以何种方式死在
began 之前，日志都必然是现在这副样子（零行）。以下候选解释
的都是「死法」，现有日志对死法本身无分辨力，分辨靠机制与对
照证据。

### ① allowableMovement 超限失败

- 机制：按压期位移 >10pt → UILongPressGestureRecognizer 在计
  时未满时转 .failed。两
...[truncated 6593 chars]