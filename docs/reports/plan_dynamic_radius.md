# 动态圆角适配：可行性核查 + 全量盘点 + 方案（只出方案，未落码）

> 起因：用户 2026-11-27 问——所有页面的卡片圆角、分组圆角等，能否按 iPhone 不同型号动态适配屏幕圆角大小，以达到最优体验。
> 基线：HEAD 9d9dd9f（0.9.55）+ 工作树在途批次（U1 / 完成胶囊 / 首页线）；盘点覆盖 `rust/apps/ios/app/*.swift` 全部源文件的工作树现态。
> 前置机制：`Radius` 令牌单源 + `concentric`/`lift` 派生（0.9.52，fix_card_radius.md）、复合卡内角规矩与 `CornerRect` 按位取角（0.9.54，fix_lift_spacing.md 第三节）。

## 结论先行

1. **iOS 27 没有给第三方 App 读「显示屏物理圆角半径」的公开 API**（SDK 全域实证，见第一节）。这个值在系统内真实存在（`displayCornerRadius`），但只以 SPI 形态存在于二进制符号表、不出现在任何公开头文件与 Swift 接口中——走它即私有 API 路线，**排除**。
2. **本 App 当前没有任何一块自绘带角面贴着物理屏角**：系统面（原生 sheet/弹窗）的角由 UIKit 绘制、天然随设备；自绘的底表/面板/吐司/坞全部悬浮（16–20pt 边距，Web 设计语言）；满屏页（编辑画布/图片页/开屏底）不设圆角、屏角即窗角，无可画之角。**「按机型适配屏角」在本 App 当前形态下没有作用面。**
3. 用户要的「圆角看起来最优/协调」，在本 App 的几何里由两件事决定：**半径阶梯一致**（设计令牌）与**嵌套同心**（子面半径由外半径 − 内距派生）。这两件 0.9.52 已立机制，但还有收尾账：设置族/救援/桥设置等页面的圆角仍是调用点裸值（值都对、未入令牌），个别面手搓了重复字面对（底表）。方案 = 把同心派生与令牌单源**全覆盖收尾**（R1/R2），贴边面只立政策不落码（R3）。
4. **机型表不采纳**：与「禁写死单机数值」红线的边界论证见第四节——形式上不犯条文（三者皆「全型号数据」），但数据无权威来源、随新机型腐烂、且在本项目单设备交付下不可验证，犯该规矩的实质。

---

## 一、运行时信号实证（必查一）

方法：对本机 iOS 27.2 SDK 克隆（`~/ios-native/sdks272/repo/iPhoneOS27.2.sdk`）做三层 grep——公开头文件（`*.h`）、公开 Swift 接口（`*.swiftinterface`）、二进制符号表（`*.tbd`）。同法正对照成立：`displayScale`、`ConcentricRectangle` 都能被同一套 grep 命中，排除「grep 方法失效」的假阴性。

### 1.1 公开面逐项核查

| 入口 | 结果 | 证据 |
|---|---|---|
| `UIScreen` | **无圆角属性** | UIScreen.h 全属性表逐项读毕：bounds / scale / nativeBounds / nativeScale / EDR / maximumFramesPerSecond 等，无 corner 项 |
| `UIScene` / `UIWindow` | **无圆角 API** | 两头文件 `corner`（不分大小写）零命中（仅 UIView.h 有，见下行） |
| `UITraitCollection` | **无圆角 trait** | UITraitCollection.h `corner` 零命中 |
| `UIView (CornerConfiguration)` | 有，但**是容器相对** | UIView.h:773–785：`cornerConfiguration` 属性 + `effectiveRadiusForCorner:`——解析的是「该视图按其配置、相对其容器」的有效半径，不读显示屏 |
| `UICornerRadius`（iOS 26+ 公开） | 有，但**是容器相对** | UICornerRadius.h：`fixedRadius` / `containerConcentricRadius` / `containerConcentricRadiusWithMinimum:`——注释原文「calculated using the geometry of the view and its **container**」 |
| `UICornerConfiguration`（iOS 26+ 公开） | 同上 | UICornerConfiguration.h：逐角/uniform/capsule 配置，配合上行解析 |
| SwiftUI `ConcentricRectangle`（iOS 26+ 公开） | 有，但**是容器相对** | SwiftUICore.swiftinterface:17260–17261：`@available(iOS 26.0)`，各角默认 `.concentric`——向**容器**的角处理对齐，不是向显示屏 |

### 1.2 那个值确实存在——但是 SPI

`displayCornerRadius` 在整个 SDK 中只出现在两处 `.tbd` 符号表：

- UIKit.tbd：`UIMutableTraits.displayCornerRadius: CGFloat`（trait 的可变侧存取符号）；
- SwiftUICore.tbd：`EnvironmentValues.displayCornerRadius: CGFloat?`（SwiftUI 环境值存取符号）。

而在**全部公开头文件与全部公开 swiftinterface 中，该字符串零出现**（全 SDK `--include="*.h" --include="*.swiftinterface"` 递归 grep 实证）。定性：

- 这是苹果自家框架内部使用的 SPI：系统用它把屏角喂给 SwiftUI 内部（`ConcentricRectangle` 与系统组件在贴边场景下与屏角同心，靠的就是这条内线）。
- 对第三方 App：`@Environment(\.displayCornerRadius)` 在公开接口下**根本无法编译**（键路径无公开声明可解析）；要够到它只能 `@_silgen_name` 直引符号、动态查找或运行时 spelunking——即私有 API 路线。**按任务口径与项目卫生直接排除，本方案不设计任何基于它的落点。**（App Store 审核 2.5.1 式风险之外，本项目工具链只对公开接口编译，此路在工程上也不成立。）

证据分级：**「iOS 27.2 公开面无屏角读取 API」= proven**（三层实证 + 正对照）；**「该 SPI 在真机上返回何值」= unknown**（不走排除路线即无从测，且与结论无关）。

### 1.3 候选替代信号（逐个评估）

| 信号 | 合法性 | 给得出什么 | 维护成本 | 失效模式 | 裁定 |
|---|---|---|---|---|---|
| utsname 机型表 | 公开（App 内已在用：MomentApp.swift:4674–4685，Diag 显示机型串） | 机型标识 → 查表得半径 | **高**：半径值苹果从不公布，社区实测表来源互异、同机型差数 pt；每年新机型须补表； iPad 全系另表 | 未知机型（新机首发、表未更新）静默落兜底值；Stage Manager/分屏下窗角 ≠ 屏角、前提不成立；值错不报错、无从自检 | **不采纳**（论证见 §4.3） |
| 屏幕 bounds+scale 指纹 | 公开（UIScreen.bounds/scale） | 以点尺寸+倍率反推机型 | 同机型表，且更糟 | 多机型同点尺寸（一代一尺寸复用）；显示缩放（Display Zoom）改 bounds → 误判；本质是伪装成信号的机型表 | 排除 |
| 安全区推导 | 公开 | **推不出** | — | safeAreaInsets 是矩形距离量：底部 34pt 横跨多代机型而屏角各不相同，inset 里不含角信息 | 排除（信号不存在） |
| 容器同心 API（ConcentricRectangle / UICornerConfiguration） | 公开（iOS 26+） | 嵌套同心（真信号、运行时） | 低 | 与屏角无关；本项目部署目标 16.0 须可用性分叉；且本工具链有新版 SwiftUI 类型模块可见性前科（CornerRect 注释明载：纯 Path 实现、不依赖新版形状类型） | 不引入：其数学与已部署的 `Radius.concentric(outer:inset:)` 等价（同式、显式入参、零版本门槛），换它无收益有风险 |

---

## 二、全量盘点（必查二）

### 2.1 令牌单源现状

`enum Radius`（MomentApp.swift:13638）：`cardS 22 / cardL 32 / grid 26 / quote 10 / mdImage 10 / block 12 / pill 999 / titleCapsule 33 / liftInset 4`，派生 `concentric` / `lift` / `attachmentFile(wide:)`；修饰器 `GlassCard`（默认 cardL）、`ContentCard`（默认 cardL）、`OverlayCard`（默认 cardS）默认值全走令牌。MomentApp.swift 内 `Radius.` 引用 87 处；`CornerRect` 调用 10 处、入参全为令牌（抽查 12580/12701/13212/13274/16402 等，无裸值）。

### 2.2 第一类：贴屏幕边的全幅面（与物理屏角真正相关）

| 面 | 谁画角 | 与屏角关系 | 处置 |
|---|---|---|---|
| 原生 `.sheet()` 呈现（全 App 14 处调用） | **UIKit** | 系统 sheet 的角由系统按设备绘制；App 未设任何 presentationCornerRadius（grep 0） | 已天然动态适配，零工作、零控制权 |
| 系统弹窗/菜单 | UIKit | 同上 | 同上 |
| 编辑画布满屏底（ignoresSafeArea 垫层） | 无角 | 满幅矩形、屏角即窗角 | 无面可适 |
| 图片页（整页图） | 无角 | 同上（fix_card_radius 账：「无面」） | 同上 |
| 开屏（满屏底 + 居中图标） | 底无角；图标 clip 20 continuous（MomentApp.swift:19123，90×90 居中） | 图标是居中自有面、与屏角无关 → 归第二类 | — |
| 救援页 / 安全模式页 | 整页无角；页内卡悬浮（见第二类） | 页本身无角 | — |
| **自绘且贴物理屏角的带角面** | — | **不存在** | 本类无待办 |

关键事实：本 App 全部自绘浮层都是**悬浮式**——背景色底表四周距 20（横 20、底 20+safe）、吐司横 16/底 16、菜单面板右 16/顶 59、编辑坞与完成胶囊皆悬浮。这是 Web 原版的设计语言（浮层悬浮），不是遗漏。**屏角动态适配在本 App 无作用面，是本盘点最重要的结论。**

### 2.3 第二类：有边距的卡片/分组/浮层（设计令牌，与屏角无几何关系）

已全令牌化（值与 Web tokens.css 逐值同源，见第三节）：编辑器块卡全族（图文/混排/gallery/图片/视频/链接/音乐/附件，含拾起框派生）、首页行卡/方卡、标题胶囊、搜索胶囊、音乐丸、引用/代码/callout/MD 面。

**未入令牌的裸值残留**（值都经各批审计与 Web 对齐、只是没收口到 `Radius`，本方案 R1 的对象）：

| 值 | 消费点（文件:行，工作树现态） | 来源 |
|---|---|---|
| 28 | 设置族 glassCard ×约 10（MomentApp.swift:4456/4638/17187 区段等）、Diag 卡（4456 区）+ Diag 终端底 RoundedRectangle 对（4833）、桥设置 glassCard ×4（MomentBridgeSettings.swift:62/78/126/220）、救援 glassCard ×1（MomentRescue.swift:195）、吐司 overlayCard（17555）、备份相关卡 | Web panels.css（backup-card/diag-body 等 28） |
| 30 | 备份 hero 卡（17431） | Web backup-hero 30 |
| 32（显式） | 设置 glassCard ×3（17187/18025/18175/18278 区段） | 即 cardL、显式重述 |
| 20 | Diag 面板 overlayCard（3761）、救援 glassCard ×3（MomentRescue.swift:76/111/449）、子页紧凑标题胶囊 overlayCard（16890）、设置 glassCard ×1（4548） | 各 Web 面板源 |
| 28（手搓对） | 背景色底表：`.clipShape(RoundedRectangle(28))` + overlay 同值描边（10516–10517）——与 OverlayCard 的配方（底+0.5 边+裁）逐字重复、未走修饰器 | Web .bg-sheet |
| 22（冗余重述） | overlayCard(radius: 22) ×6（9266/9372/9535/9797/10628/10735） | 即修饰器默认值 cardS |
| 999（裸值） | glassControl(radius: 999) ×约 11（4576/4848/4864/9980/10089/10673/14858/15971/16461/16470/16735/16908）、搜索胶囊 overlayCard(radius: 999)（15954） | 即 pill |
| 14 | glassControl(radius: 14) ×5（16428/16494/16502/16778/16787，小方钮） | 原生按钮面 |
| 14/16/17/0 | RowPressStyle(radius:) 多处（9711/10507/10785/10832/17018/17063 等） | 按下态背景、非面半径（fix_card_radius 已定性保留，本方案不动其性质、仅登记） |
| 20 continuous | 开屏图标 clip（19123） | 原生自有面 |

另：`Capsule()` ×12、`Circle()` ×8——隐式全圆形状（圆钮/头像/点），半径 = 自身尺寸一半、构造上自适应，无需令牌化，登记在账即可。

### 2.4 第三类：嵌套子面（同心派生覆盖度）

现行规矩（用户 2026-11-27 裁定，fix_lift_spacing 第三节）：复合卡只有外轮廓四角取卡半径、内部交界角一律直角，子面按位置显式 `CornerRect` 取角，不靠默认。覆盖现状：

- **已派生/已锁形**：图文卡（图/占位/文条）、混排卡（图半/文半）、链接/音乐卡封面、gallery 每瓦按格位、首页图卡图区——CornerRect 10 处全令牌入参；拾起框 `Radius.lift` 全派生；附件宽屏/常态 `attachmentFile(wide:)` 双面同源。
- **成文例外（非孤儿）**：gallery 瓦与格网同值 22（Web 自身即同值、非同心递减）；卡编辑描边 32 罩 22 面（Web 自身两档规则，是外扩 3 的轮廓光晕、非嵌套面）。
- **微装饰保留字面（0.9.52 已评估定案）**：骨架条 6 ×3（12706–12714）、引用左条 1.5 ×2（8313/11838）、eb-clear 6、ErrBadge 18、kbd 4、shortcut 6、link 输入 10（9751）、斜杠行按下 14（9706）。皆单元素、无嵌套关系、无同心可派生——维持字面，仅在 [31] 里登记计数锚防无声增殖。
- **本轮新面复核**：完成胶囊 moreCapsule 为单容器（999 一值贯通两段、无交界角问题）；首页搜索胶囊单面。未发现新孤儿。

### 2.5 Web 侧口径

tokens.css 半径阶梯为**定值**：`--radius-2/3/4/6/8/10/12/14/16/17/18/20/22/23/26/28/30/32/33/999` + `--radius-circle: 50%`；原生每个令牌都标注了对应 Web 令牌名、逐值同源。Web 无「设备」概念（浏览器窗角不归页面管）。**故本想法整体定位 = 原生增强型调优，不是与原版对齐的工作**；且对第二类面而言，跟随屏角反而会破坏阶梯与 Web 一致性（如 cardL 32 若随屏角涨到 ~55，卡片形态与 Web 完全脱钩）——增强的价值论证只能落在第一类面上，而第一类是空的。

---

## 三、方案（必查三）

骨架：**同心派生全覆盖**——不追屏角（无面、无公开信号），把已立的「令牌单源 + 同心派生」覆盖到全 App 每一块带角面，使任何一处圆角都只剩两种合法来源：令牌、或由令牌派生。

### 3.1 R1：裸值收口（值等价、零视觉变化）

`Radius` 扩表（按值+角色命名，不并不同源值）：

| 新令牌 | 值 | 收口对象 |
|---|---|---|
| `panel` | 28 | 设置族/Diag/桥设置/救援的 28 卡、吐司 |
| `panelHero` | 30 | 备份 hero |
| `panelS` | 20 | Diag 面板、救援 20 卡、紧凑标题胶囊、设置 20 卡 |
| `controlS` | 14 | glassControl 小方钮 ×5 |

连带落法：
- 背景色底表手搓对（10516–10517）改走 `.overlayCard(radius: Radius.panel)`，删重复配方（行为等价：底色/0.5 边/裁切三件与现行逐项同）。
- `overlayCard(radius: 22)` ×6 删实参（走默认 cardS）；设置显式 `glassCard(radius: 32)` 改 `Radius.cardL` 或删实参（默认值即 cardL 的点删、语义需显式处留令牌）。
- `glassControl(radius: 999)` 全改 `Radius.pill`。
- MomentRescue.swift / MomentBridgeSettings.swift 与 MomentApp.swift 同模块同 target，`Radius` 直接可见，无需搬家。
- RowPressStyle 各值、微装饰字面、Capsule/Circle **不动**（性质已定案，[31] 只登记锚）。

量级：3 个文件、约 50 处，全为字面→令牌的等值替换；风险低（[21] 既有断言网 + tree 冒烟兜底）。

### 3.2 R2：嵌套派生复审（审计先行）

按 fix_card_radius + fix_lift_spacing 两账的复合面清单逐面复核子面半径来源（0 / 令牌 / concentric 派生三选一），含 0.9.54 之后新增面（完成胶囊、搜索胶囊、首页新面）。预期修复量小（可能为零），产出逐面派生表入报告；发现孤儿才落码。

### 3.3 R3：贴边面政策（只立规矩、不落码）

将来若真出现自绘贴边面（如改为真·贴底全宽底表），当时的选项对比：

| 选项 | 做法 | 代价/风险 | 
|---|---|---|
| A 定值令牌（**推荐**） | `Radius` 加 `displayFlush` 一令牌、按当期主流机型屏角量级定值，其下嵌套面 concentric 派生 | 与全 App 令牌纪律同构；新机型屏角漂移时改一值；值不准时只是「不够贴合」、不崩不锁死 |
| B 机型表 | utsname → 表 → 半径 | 见 §4.3：数据无权威源、逐年腐烂、单设备项目不可验证 |
| C SPI `displayCornerRadius` | 直引符号/动态查找 | 私有 API，**永久排除** |

政策落点：本报告 + 在 `Radius` 枚举注释里留一行指针（随 R1 一并落），防将来重议。

### 3.4 机型表与红线的边界（专节论证，不含糊）

用户成文规矩：**安全区必须动态适配、一律运行时取值，禁止写死某台机器的数值（单机调参多设备即废）**。

- **条文层面**：机型表不是「写死某台机器的数值」——它是一张覆盖全型号的数据库，运行时按当前设备查表。就字面而言，不犯规。
- **实质层面**：该规矩要防的失效模式是「数值与真实硬件脱钩、且脱钩时静默错误」。机型表在三点上重蹈这一模式：① **数据来源**——苹果从不公布各机型屏角半径，表值只能来自社区实测（多源互差数 pt），等于把「别台机器上的单机实测值」批量写死；② **时间维度**——表在发布时冻结，新机型（每年九月）必然不在表中、静默落兜底，与「运行时取值、新硬件免更新即正确」的规矩目的正相反；③ **可验证性**——本项目签名为 TEST SIGNING 单设备，表中其他机型的条目在本项目的真机标准下永远无法验证，等于发布不可验证的适配声明。
- **结论**：机型表与红线是「条文不犯、实质相悖」。不采纳。若苹果将来把该 trait 转正为公开 API，采纳只需在 `Radius` 内换一个信号源（一处），本方案的单源架构已为这一可能性留好位置——这也是先把单源做全覆盖的额外理由。

### 3.5 verify [31] 组预留断言清单（锁机制，不只锁值）

| 条目 | 锁什么 |
|---|---|
| R31-1 | 令牌完备：MomentRescue.swift / MomentBridgeSettings.swift / MomentApp.swift 设置段内 `radius: <数字>` 字面零残留（仅令牌引用） |
| R31-2 | 底表/Diag 终端面走修饰器：手搓 `RoundedRectangle(cornerRadius: 28)` 字面对全文件零残留 |
| R31-3 | glassControl 调用点无数字字面（pill/controlS 令牌only） |
| R31-4 | overlayCard 不重述默认值：`overlayCard(radius: 22)` 零残留 |
| R31-5 | CornerRect 入参合法集：仅 `0` / `Radius.*` / `Radius.concentric(...)`（grep 模式锁，承 [23]） |
| R31-6 | 反 SPI 守卫：`displayCornerRadius` / `_displayCornerRadius` 全源零出现；utsname 使用点恒为 Diag 机型串一处（计数锚，防机型表偷渡） |
| R31-7 | 未引入 ConcentricRectangle / UICornerConfiguration（grep 零；将来引入须显式改断言 = 显式评审） |
| R31-8 | 隐式形状计数锚：Capsule() / Circle() 计数与盘点值（12/8）对账，增减须改锚即须过目 |
| R31-9 | 微装饰字面集封闭：6/1.5/18/4/10 等保留字面的出现点计数锚（承 0.9.52 定案，防无声增殖） |

### 3.6 分批与工作量

| 批 | 内容 | 量级 | 风险 |
|---|---|---|---|
| R1 | 令牌扩表 + 约 50 处等值收口（3 文件）+ [31] 的 R31-1..4、6..8 | 一批（半日级） | 低：纯等值替换，[21] 回归网 + tree 冒烟 |
| R2 | 复合面逐面派生复审表 + 孤儿修复（预期 0–3 处）+ R31-5、9 | 半批 | 低 |
| R3 | 政策入注释一行（随 R1） | 零批 | 无 |

不涉 FFI、不动 Web、不单独发版（随常规版本搭车）。

### 3.7 真机终判点（用户 iPhone 15 Pro）

- R1/R2 是**等值**收口：设置页、Diag 页、救援页、桥设置页、背景色底表、吐司、开屏图标——圆角观感必须与改前**逐一相同**；任何可见变化即回归，不是「适配效果」。
- 「圆角是否最优」这一体验判断本身只能由用户在现阶梯上判：若某块悬浮面与屏角的视觉关系让用户觉得不协调（最可能的候选是悬浮底表），点名该面即可——那是单面设计调整（改其令牌值或改悬浮为贴边 + R3 政策），不需要全 App 机制。
- iPad（UIDeviceFamily 含 2）：本方案无任何按机型分支，首页网格/宽屏编辑圆角不变，至多抽查一眼即可；不存在「换一台机器验适配」的可验项——这正是机型表路线在本项目里立不住的另一面。

---

## 四、边界与未决

- 本报告只出方案：未落码、未动 verify、未 bump。
- SDK 实证基于本机 27.2 克隆（第三方 sparse clone）；结论以「公开接口面」为准——若苹果在后续 SDK 转正 `displayCornerRadius`，§3.4 结论按新事实重议，架构不受影响。
- S1 遗留（附件宽屏 22 的 Web 实据）已于后续批次裁定为 Web 宽屏计算值确为 22（fix_attachment_radius_wide.md），与本盘点不冲突，`attachmentFile(wide:)` 维持现行派生。
