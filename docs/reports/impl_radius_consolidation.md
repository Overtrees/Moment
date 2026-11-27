# 圆角收口 R1+R2 落码报告（令牌单源全覆盖 + 嵌套派生复审）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。方案：`plan_dynamic_radius.md` §3.1/§3.2/§3.5，用户 2026-11-27 已批。
> 基线：HEAD 297ad13（0.9.56）。开工门核查：0.9.56 组版分拣已提交完毕（HEAD 已越过 9d9dd9f）；动工时树内另有并行批在途改动（M3a/救援布防：worker.js、桥三文件、plan_app_mcp_bridge.md 全量 + MomentApp.swift 三 hunk（MemoItem/Library 段）+ verify [13]/[16] 段）——已先快照其 diff（577 行），逐 hunk 映射确认与本批领地（MomentApp 3795 行后各段 + Radius 枚举 + verify S4/S5、[29]、[30] 断言行与尾部）零交叠；完工后复验：其 5 个独占文件 diff 逐字节一致、两共享文件中其 37+60 行新增内容逐行完好。

---

## 1. R1 收口对账（逐处：文件:行 前值 → 令牌，行号为落码后现态）

`Radius` 扩表四枚（MomentApp.swift:13700 区段）：`panel 28`（--radius-28 面板卡）、`panelHero 30`（备份 hero）、`panelS 20`（小面板）、`controlS 14`（小方钮）；枚举头注释加 R3 政策指针一行（displayFlush 定值令牌 + concentric 派生、机型表不采纳、屏角 SPI 永久排除——注释未写 SPI 符号原文，使 R31-6 全源零出现守卫保持满格，见 §4）。

### MomentApp.swift（51 处）

| 前值 | 令牌 | 行 |
|---|---|---|
| glassCard 28 | `Radius.panel` | 4490、4672、17274、17295、17332、17531、17564、17777、17915 |
| glassCard 20 | `Radius.panelS` | 4582 |
| glassCard 30 | `Radius.panelHero` | 17476 |
| glassCard 32（显式重述） | `Radius.cardL` | 17232、18070、18220、18323 |
| glassControl 999 | `Radius.pill` | 4610、4882、4898、10014、10123、10704、14903、16016、16506、16515、16780、16953 |
| glassControl 14 | `Radius.controlS` | 16473、16539、16547、16823、16832 |
| overlayCard 28 | `Radius.panel` | 16076（首页吐司）、17600（备份吐司） |
| overlayCard 20 | `Radius.panelS` | 3795（Diag 面板）、16935（紧凑标题胶囊） |
| overlayCard 999 | `Radius.pill` | 15999（搜索胶囊展开面） |
| overlayCard 22（冗余重述） | 删实参走默认 cardS | 9300、9406、9569、9831、10659、10766 |
| RR cornerRadius 28（Diag 卡内幅面/终端底） | `Radius.panel` | 4555、4867 |
| RR cornerRadius 30（hero 内横幅底+描边） | `Radius.panelHero` | 17494、17497 |
| RR cornerRadius 999（备份动作钮底） | `Radius.pill` | 17749、17766 |
| RR cornerRadius 20 continuous（开屏图标 clip） | `Radius.panelS` | 19168 |
| 背景色底表手搓对（10516–10517 旧账） | `.overlayCard(radius: Radius.panel)` 单修饰器 | 10549（原 `.background(T.overlayBg)` + clipShape RR28 + overlay RR28 描边三件套整体替换） |

### MomentBridgeSettings.swift（4 处）

glassCard 28 → `Radius.panel`：62、78、126、220。

### MomentRescue.swift（4 处）

glassCard 20 → `Radius.panelS`：76、111、449；glassCard 28 → `Radius.panel`：195。

**合计 59 个收口点**（方案估约 50，实收 59：含方案表外同类三处——Diag 卡内幅面 RR 28（4555）、备份 hero 内横幅 RR 30 对、备份动作钮 RR 999 对，均为同面同值、按同令牌收口）。全部为字面→同值令牌的等值替换，**无一处收口前后数值不同**（逐点以方案盘点表与落码后 grep 双向核对）。

一处渲染等价性说明（诚实标注）：底表手搓对原用 `.stroke`（描边骑边线、内外各 0.25），OverlayCard 修饰器用 `.strokeBorder`（描边全在内侧）——半径值同为 28、底色/边色/0.5 线宽/裁切四项同，此 0.25pt 描边落位差为方案 §3.1 明定的改走修饰器口径（配方归一），非本批自创变更；真机终判时与改前对照一眼即可（见 §5）。

计数对账附记：`glassControl(radius: Radius.pill)` 全文件 14 处 = 本批收口 12 + 既有令牌用法 2（11412、12822，非本批点）；`glassCard(radius: Radius.cardL)` 5 处 = 本批 4 + 既有 1（3295）。

## 2. R2 嵌套派生复审（逐面结论）

按 fix_card_radius + fix_lift_spacing 两账复合面清单逐面核子面来源（0 / 令牌 / 派生三选一）：

| 复合面 | 子面来源 | 结论 |
|---|---|---|
| 图文卡 imgTextCard | 图/占位/文条 CornerRect 按位取角（cardL/cardS 令牌、交界 0） | ✓ 无孤儿 |
| 混排卡 imageTextRow | 图半 CornerRect（tl/bl 令牌）、文半直角 | ✓ 无孤儿 |
| gallery | 每瓦 CornerRect 按格位（cardS/0，11228 函数）；瓦与格网同值 22 为 Web 自身口径（成文例外） | ✓ 无孤儿 |
| 链接卡 / 音乐卡 | 封面 CornerRect 按位取角；面走 contentCard 默认 cardL | ✓ 无孤儿 |
| 首页图卡 | 图区 CornerRect（grid 令牌，16402） | ✓ 无孤儿 |
| 视频/图片面 | RR `Radius.cardS` 令牌 | ✓ 无孤儿 |
| 附件行/图片面 | `attachmentFile(wide:)` 双面同源派生；图片面恒 cardL | ✓ 无孤儿（本批未动） |
| 拾起框全族 | `Radius.lift(face:)` 单点派生（13845） | ✓ 无孤儿 |
| 完成胶囊 moreCapsule | 单容器、两段同挂 glassControl `Radius.pill`（本批收口后同令牌贯通、无交界角） | ✓ 无孤儿 |
| 搜索胶囊 | 收起 glassControl pill / 展开 overlayCard pill，本批后两态同令牌 | ✓ 无孤儿 |
| 背景色底表 | 本批由手搓对改走 overlayCard(panel)，配方单源 | ✓ R1 已收 |
| 备份 hero 内横幅 | 本批收 `Radius.panelHero`（与卡同值 30）——此值系批 C3 定案口径（横幅自有半径规格，非同心递减面），属「令牌」来源合法；改 concentric 派生（30−18=12）会变更视觉值，超出本批值等价红线，不动 | ✓ 令牌合法、非孤儿 |

**R2 孤儿修复量：0 处**（与方案「预期 0–3」下限一致）。成文例外与微装饰保留字面（骨架 6、引用条 1.5、eb-clear 6、ErrBadge 18、kbd 4、shortcut 6、link 输入 10、斜杠行按下 14、RowPressStyle 各值、Capsule 12/Circle 8）全部维持原定案，本批只在 [31] 登记计数锚。

## 3. verify [31] 与既有断言联动

新增 **[31] 组 R31-1..9**（尾部追加于 [30] 后）：令牌四枚在表 + 三文件修饰器数字半径零残留；手搓 28/30/999/20 字面全清 + 底表 overlayCard(panel) 计数 3；glassControl 令牌计数锚（pill 14 / controlS 5）；overlayCard(22) 重述清零；CornerRect 10 处入参合法集；反 SPI 守卫 + utsname 单点锚；ConcentricRectangle/UICornerConfiguration 零引入；Capsule/Circle 12/8 锚；微装饰字面集计数锚（1.5×2、4×1、6×5、10×3、14×1、18×1，落码后实测值）。

既有断言三处字面联动（仅改 grep 字面至令牌拼写、所锁机制不变，承 R21-9 改写先例）：S4/S5（overlayCard 28 / glassCard 30 → panel / panelHero）、F29-1（glassControl 999 计数 → Radius.pill 计数 2）、F30-9（overlayCard 20 / 999 → panelS / pill）。

**本机自跑：265 ✓，[31] 九条全绿；仅剩 2 条既有产物类 ✗**（ipa 陈旧、产物语言包——tree 构建自解，与前批本机基线同型）。Swift 编译级验证随主线 tree 冒烟（本机无 swiftc；已逐段复读 + 括号平衡自查）。

## 4. 改动清单

| 文件 | 改动 |
|---|---|
| MomentApp.swift | Radius 扩表四枚 + 头注释 R3 政策指针一行；51 处收口（含底表手搓对改走 overlayCard） |
| MomentBridgeSettings.swift | glassCard 28 ×4 → Radius.panel |
| MomentRescue.swift | glassCard 20 ×3 → Radius.panelS、28 ×1 → Radius.panel |
| verify_ios.sh | 新增 [31] 组（R31-1..9）；S4/S5、F29-1、F30-9 三处 grep 字面联动改令牌拼写 |

未碰：并行批全部文件与段落（见文首核查）、FFI、Web、build 脚本（无新文件）。

## 5. 真机终判点（等值收口、观感须与改前逐一相同，任一可见变化即回归）

1. 设置页各卡、Diag 页（面板/卡/终端底）、桥设置页、救援页各卡圆角与改前一致。
2. 背景色底表圆角与描边观感与改前一致（§1 描边落位 0.25pt 说明项，重点看底表边缘）。
3. 吐司（首页/备份各一）、备份 hero 卡与内横幅、备份动作钮圆角一致。
4. 开屏图标圆角一致；紧凑标题胶囊、搜索胶囊两态圆角一致。
5. iPad 抽查一眼：无机型分支，圆角不应有任何变化。
