# 首页头像/搜索胶囊「偶尔不见」根治（fix_home_header_vanish）

用户真机实报（0.9.58，2026-11-27 19:35）：首页头像、搜索胶囊仍会偶尔消失。
沿革：0.9.58 的 fix_home_regressions_0957 以 HomeScrollProbe（KVO 直读
contentOffset + adjustedContentInset）替换基线捕获制并宣称根治 S2/S3。
本批结论对其改判：**直读量测本体无误、旧宣称过头**——病灶不在「读什么」
而在「读数如何进入呈现层」：出口零消毒。旧账改判已同步写入探针头注与
verify F30-17 改判注。

## 一、分型

头像与胶囊同由 compactP 门控（opacity + allowsHitTesting，compactP =
clamp(scrollOffset/30)）：

- 同没（或胶囊可见而点不动）→ compactP 路：≥15（p≥0.5）命中关死，
  ≥30（p=1）整隐。头像在 p∈[0.5,1) 时 opacity 仍 ≥0.7 但命中已关，
  用户感知同为「不见/点不动」。
- 胶囊独没（头像在且可点）→ 焦点路：searchFocused 派生的两层结构。

两条路分别盘点、分别定性如下。

## 二、compactP 路盘点

### 写点全集（scrollOffset）

| 写点 | 位置 | 说明 |
|---|---|---|
| 探针接线回调 | ListView.background(HomeScrollProbe) | 唯一动态写点，值 = 探针发布值 |
| 形态切换归零 | syncHomeSize（homeWide 翻转时） | 写 0，随后探针重挂直读新容器真值 |
| 声明初值 | NavState.scrollOffset = 0 | 冷启初值 |

读点：compactP 唯一（派生后三消费方：头像、搜索胶囊、「此刻」小标题，
逐项核对与 Web 口径一致，未动）。

### 探针读数卫生逐项判定

探针本体（0.9.58 落码）：attach 时同步首读一次 + KVO 双观察
（contentOffset / adjustedContentInset），|Δ|≥0.5 即写 @Published，
**无平滑、无迟滞、无落定门、无突变确认**——单帧读数直达呈现层。

| 候选毛刺源 | 能否产生假偏移 | 判定 |
|---|---|---|
| 冷启首帧：滚动视图已入树、首轮布局未落定，contentOffset 未落静止值（−inset.top），而 adjustedContentInset.top 已含安全区（≈59） | 首读 d = 0 + 59 ≈ 59 ≥ 30 → 整隐；或 15–29 → 命中关死 | inferred（时序竞态，见 §四） |
| 导航返回重挂：编辑器 pop 后探针 detach→re-attach，同上首读竞态 | 同上 | inferred |
| 旋转/形态切换：新滚动视图（List↔ScrollView）首读同竞态；syncHomeSize 先归零、探针随后以新容器首读覆写 | 同上（归零被假首读覆盖） | inferred |
| 内容重载钳制：搜索过滤/删除后内容骤缩，UIScrollView 布局钳制前 KVO 可先报钳制前值 | 已滚动态的钳制前值属带内移动，不产生「静止却紧凑」；静止态内容变化不移动 offset | 不成立（逐项核后排除） |
| 下拉回弹：offset.y < −inset.top | d 经 max(0,·) 钳 0 | 不成立（旧制已钳） |
| 探针目标漂移：findScroll 旧实现先序首胜，子树若出现嵌套滚动面可夺目标 | 现行首页子树无第二滚动面（逐面核：卡行/页眉/空态/toast 均无 UIScrollView），属潜在面非现行病灶 | 潜在（本批顺手硬化，见 §五） |
| 探针毛刺直达呈现 | 单帧 |Δ|≥0.5 即发布，无任何中间层 | **proven**（源码事实） |

### Diag 判读面缺口（proven）

旧打点只有 compact 0↔1 边沿一行（fix_home_regressions_0957 落）。15–29
的命中关死带迁移**零留痕**：用户复报时凭 Diag 导出无法分型「整隐」与
「命中关死」，也无法区分真滚动与假偏移。此为本批必须补的自救面。

## 三、焦点路盘点

searchFocused（@FocusState，ListView）写点全集：

| 写点 | 触发 | src 记账 |
|---|---|---|
| activateSearch 置 true | 触发层 Button 点按（手指/U5 驱动共用） | tap 行 |
| resignSearch 本体置 false | 头像/紧凑标题/新建/打开（缺省 nav） | nav |
| 同上 | EditorSeatRegistry.onSeatChange（seat 钩子，编辑器会话开始单点） | seat |
| 字段 onSubmit 置 false | 回车 | submit |
| 清除钮置 false | 清词同收 | clear |
| 系统辞焦 | .scrollDismissesKeyboard(.interactively) 双形态、离开层级 | system |

结论：**无独立缺陷（proven by 写点枚举）**。开合无第二标志（旧 searchOpen
已于 fix_search_tap_dead 退役、F30-1 锁零残留）；常驻层+触发层的
opacity/命中纯派生自 searchFocused 与 compactP；seat 钩子只在宿主真实
push/replace 时发（MomentEditorTransition seat() 调用点 2 处均在呈现路
径内，首页静止态无触发源）。静止态「胶囊独没」只能来自 compactP 命中
带（§二），归 compactP 路收口。焦点路本批零改动。

## 四、定性分级

- **proven**：出口零消毒（单帧直达呈现、无落定门/无确认/无迟滞）；
  命中带 Diag 缺口；焦点路无独立脱钩机制；写点全集如上表。
- **inferred**：具体毛刺源为首帧/重挂/旋转三处的布局未定瞬间首读
  （d 可达 inset.top 全量）。机理与读数构成逐项吻合（offset 未落静止值
  时 d = inset.top ≈ 59，恰跨整隐线；部分落定时恰入命中带），但属
  子布局帧级时序竞态，桥自检驱动（应用层动作）无法确定性复现——按
  纪律不写 proven。根治落点不依赖单一毛刺源定性：消毒机制对全部
  「孤立假偏移」同构成立（见 §五），再犯时凭新 Diag 行可事后定因。
- **unknown**：真机上各毛刺源的实际发生频率分布（待新 Diag 面回收）。

## 五、根治落点（机制单点，无消费方补丁）

1. **出口消毒单点 ScrollOffsetSanitizer**（MomentApp.swift，探针与
   ListView 之间新设纯状态机）：全部原始读数经它才许发布。
   - 未落定不发布：bounds 任一维为 0 的读数整批丢弃；
   - 两读确认：已发布值在静止带（<15）时，单读跨入命中门带（≥15）
     只记候选，须下一读（KVO 续报或挂载 120ms 复读）仍在带内才发布；
     真滚动 KVO 序列稠密、确认只迟一读；带内移动与回落发布不设确认
     （迟滞只加在「关门」方向）；
   - 钳零收归消毒器内（raw = offset.y + inset.top，d = max(0, raw)）；
   - 候选被回落读废弃 = 孤立毛刺定性事件，探针记 Diag
     `APP home scrollprobe spike discarded raw=<峰值> pub=<现值>`。
2. **挂载复读**：attach 后 120ms 以同一滚动视图复读一次，作为两读
   确认的第二读来源之一（挂载时已滚动态靠它确认发布，不必等用户
   再滚动）。
3. **compactP 纯函数单源 HomeHeaderMath.compactP(forOffset:)**：
   ListView.compactP 改为委托；硬不变量「真实距顶 ≤0 ⇒ compactP
   恒 0」由纯函数 + 消毒后发布值（恒 ≥0）构造性成立。
4. **findScroll 硬化**：子树内面积最大者为目标（承载面恒全屏；全员
   未定时先序首胜、与旧语义同结果），嵌套小滚动面不得夺目标。
5. **Diag 判读面补全**：新增静止带边沿行 `.onChange(of: compactP == 0)`
   记 `APP home compactband 0->p / ->0 offset=<源值>`。

呈现层（头像/胶囊/小标题三消费方的 opacity/命中公式）零改动；
scrollOffset 写点仍恰 2（F30-17 计数不变）。

## 六、纯函数执行实证（tree，Swift 6.4.2）

HomeHeaderMath 与 ScrollOffsetSanitizer 为 Foundation-only 纯类型，
从 MomentApp.swift 原文抽取 + 表驱动断言在 tree 编译执行：

- compactP 逐档：(−10,0) (0,0) (7.5,0.25) (15,0.5) (30,1) (90,1)；
- 消毒序列（发布列）：[0,59,0]→{0}+废弃 59；[0,8,25,60,120]→{8,60,120}；
  [0,5,10,14,16,20,40]→{5,10,14,20,40}；[200,200]→{200}（复读确认）；
  带内 [60,80,0]→{80,0}（回落即时）；未落定 [59,59]→{}；负偏移 [−40]→{}。

执行结果（2026-11-27，tree Swift 6.4.2，抽取文本与仓内原文逐字一致）：
17 项断言全 ok、终行 `ALL PASS`。另：当前 MomentApp.swift 全文经 tree
`swiftc -parse` 零诊断（md5 b26e82d0 与本机一致，含同树在途批合并态）；
全文类型检查归组版 tree 冒烟。

## 七、断言（verify [30] 组）

- F30-20 compactP 纯函数单源（委托在位 + 定义恰 1 + 旧内联公式零残留）；
- F30-21 出口消毒机制（带常量 15/候选/落定门/毛刺 Diag 行/feed 调用
  恰 1/onScroll 发布恰 1——第二发布路即红）；
- F30-22 静止带边沿 Diag 在位；
- F30-23 findScroll 面积最大选取（先序首胜实现零残留）；
- F30-17 改判注：量测本体与写点计数不变，「直读即充分」旧结论作废。
- 本机实跑 [30] 组 27 条全绿（F30-1..23 + SH-1..4）。

## 八、真机终判点

四场景各走一遍（0.9.59 装后）：

1. 冷启：首屏头像 + 搜索胶囊在位且可点（重点看冷启慢帧时有无一闪
   消失/迟迟不回）；
2. 导航往返：进编辑器再返回 ×数次（其一在首页先滚动少许再进），
   返回瞬间页眉与真滚动位置一致；
3. 旋转：竖→横→竖各停留数秒，横屏网格与竖屏列表页眉均随真位置；
4. 回弹滚动：顶部下拉过冲松手、快速上滑下滑交替，静止于顶时页眉
   恒在位可点。

再犯时 Diag 判读法（导出即可定因，不必抓现行）：

- 有 `spike discarded` 行 → 毛刺已被消毒挡下：若同窗呈现仍异常，
  病灶不在探针路，转查呈现/焦点（对 `APP search capsule close src=`）；
- 无 spike 行、却有 `compactband 0->p offset=<大值>` 且当时并未滚动
  → 探针目标或读数源漂移，看同窗 `scrollprobe attach inset=` 行的
  挂载时点与 inset 值定性；
- 只有 `compact 1` 而无 compactband 前行 → 查 scrollOffset 写点外路
  （写点全集已锁 2，出现即新写点回潮）。
