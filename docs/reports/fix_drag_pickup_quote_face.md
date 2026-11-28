# fix_drag_pickup_quote_face — drag_pickup_statemachine 步 2 face_equals_row 定案与根治

## 一、实跑证据（0.9.64 真机桥自办）

场景 `drag_pickup_statemachine` 步 2（pickup quote）两遍逐字同值失败
（runId beedac98-fb65 / 4372deb9-243d，本机证据包
/tmp/evidence_drag_pickup_statemachine.json）：

- `face=(16.0, 338.0, 361.0, 51.0)`、`row=(16.0, 338.0, 361.0, 31.0)`，
  仅高度差 **20pt**，超 ±0.5 容差；步 2 其余四断言（pickup_state /
  menu_rides_pickup / face_radius_quote=10 / cancel_resets）全过。
- 运行止于步 2，后续块型未及执行；夹具两遍 cleaned、库哈希零变化。

## 二、拆账（归属 proven：代码路径逐项对账 + 算术恒等）

| 量 | 值 | 通道与构成 |
|---|---|---|
| faceH | 51 | BlockRow 行盒 GeometryReader 的 `geo.size.height`，经 face 分支（`liftFaceRadius != nil`）回报。该 reader 挂在修饰链 `.padding(.vertical, …)` 与 `.background(rowBackground, in: RoundedRectangle(Radius.quote))` **之后**——量的是含 padding 的整行槽 |
| row 高（景侧取 `block.height`） | 31 | 文本块的 height 由 BlockTextView.sizeThatFits 喂入 = UITextView 自身适配高（纯文面）：单行行高 ≈27（quote 14pt × Marks.withRhythm 行高倍率 1.6）+ textContainerInset 上下各 2 = 31 |
| 差 | **20** | 恰 = BlockRow 单点 `.padding(.vertical, quote ? 10)` 的上下和（10 + 10），无其他成分 |

quote 的**视觉面**判定：可见面 = rowBackground 圆角矩形（淡底 +
1px 描边 + 左条 overlay 全高），其 background 挂在竖 padding 之后
→ 覆盖含 padding 的整 51；拾起玻璃框 LiftFrame 挂同一帧 ⊕
LIFT_INSET 4；faceRadius 回读 10 = Radius.quote 实测通过互证。
**face 通道回报的正是该视觉面，符合拾起规格定案（玻璃框 = 视觉
面 ⊕4），face 侧无错。**

景期望判定：景自述「拾起态 face 与行盒同值」，row 元组另三元
（frameMinX / frameMinY / rowW）全出行盒 GeometryReader，唯高度
取 block.height——而 height 的全仓契约本就是行盒高：字段消费面
commitDrag / dragShift 以 `height + 6` 为行 pitch（6 = 块列
VStack spacing，排版实证）、三处面板层（cardMenuLayer /
blockMenuLayer / slashLayer 回退路）以 `frameMinY + height`
为块底贴面定位、UITest `rowFrame` 以 (frameMinX, frameMinY,
rowW, height) 为行帧。**违约者是 app 侧 height 的文本喂入**：
非文本块由行盒 reader 喂行盒高、文本块由 UITextView 喂内容高，
双喂同名。景不改判。

波及面（同根、此前无断言抓到，本批一并归正）：含竖 padding 或
块内非文构件的文本块型，其 height 恒少算——

- quote：少 20（竖 padding 10×2）
- codeBlock：少 24（竖 padding 12×2）
- callout：少 24（竖 padding）+ 标题行与 spacing（内容高只含
  BlockTextView 本体，连块内标题行都不含）
- heading：少顶 padding 18 / 20 / 24（H3 / H2 / H1，文前 `.padding(.top)` 在行盒内）

受此影响的消费面：拖拽 pitch 累加（跨上述块型落位/让位阈值少
算）、拾起菜单面板贴面定位（面板顶入面下缘 padding 带，quote
约 12pt 交叠）、liftScale 纵轴输入（矩阵 EDT-27 登记口径为
「按行盒取 dim」，输入此前名不副实）、SCROLL close 的
estContentH 估算。

## 三、根治落码（单点、无逐块型特判）

MomentApp.swift 三处：

1. **行盒 GeometryReader 改全块型单点喂入**：onAppear 与
   onChange(of: geo.size.height) 两处去掉 `if !block.isText`
   守卫，`block.height` 恒 = 行盒高。该 reader 本就是行盒的
   单点量测者（frameMinX / frameMinY / rowW / face 同出于
   此），height 归队后全通道同盒。
2. **BlockTextView.sizeThatFits 记录改投 contentH**：返回值
   （布局驱动）一字未动；其变更守卫的记录写由 `block.height`
   改为新字段 `BlockState.contentH`（UITextView 内容高，仅自
   守卫用），双喂自此断源。
3. **BlockState 字段注归正**：height 注明行盒高单点口径与全
   仓消费面；contentH 注明与 height 的分工及混喂禁令。

行为等价核对：布局零改动（sizeThatFits 返回值、行盒 reader
的 background 性质均不变，height 非布局输入）；无 padding 文
本块（paragraph / todo / list 文项等）与全部非文本块的 height
值与旧喂入逐值相同——变化仅落在旧值本就违约的块型，且各消费
方（pitch / 面板 / liftScale / 估算）的设计意图均为行盒高。

## 四、断言

verify_ios.sh [68] 新增 **U68-8**（锁机制）：height 全仓恰两
写、同出行盒 GeometryReader（`block.height = geo.size.height`
在位）、`contentH` 字段与 `async { block.contentH = h }` 分流
在位、旧形 `block.height = h }` 零命中、景侧
`- block.height) <= 0.5` 对读式在位（防后人改景迁就）。
矩阵 plan_selftest_coverage.md U2 地基段已登记行盒高口径。

## 五、自检与留账

- 本机实跑（2026-11-28）：verify_ios.sh 全量 688 ✓ / 3 ✗，
  其中 U68-8 ✓、本批源码面零新增红；3 红定性与本批 diff 不
  相交——「ipa 陈旧」「产物语言包与 Web 源 md5 不一致」为产
  物陈旧红（本机 build 产物早于现行源码，重构建消除，历批
  同口径），「J12-2 Diag 当天环容量」为并行 Diag 线在途改
  动（rust/apps/web/src/diag.rs 未提交、工作区中态）所致、
  非本批面。cargo test --workspace 239 passed / 0 failed。
- Swift 本机无编译门：本批改动为守卫删除 + 字段改投 + 注释，
  无新符号引用面（contentH 为新增存储字段）；首次编译门 =
  下一版组版 tree 冒烟。
- 装机后留账：drag_pickup_statemachine 全景复跑两遍（步 2 过
  后步 3–5 的 heading / callout / codeBlock 段一并首验）、
  lift_gaps 探针在 quote 上的 faceInsets 复读（bottom 应由
  −20 归 0）。
- 证据分级：量测 proven（两遍同值）；层归属本批已由代码路径
  逐项对账 + 差值算术恒等做到 proven；修复效果待装机后景复
  跑终判（本机不升级表述）。
