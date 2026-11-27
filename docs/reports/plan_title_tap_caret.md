# 截断标题点按落点映射（审计 B-4）——根治实施方案

时间：2026-11-27。性质：只出方案、不落码。对象：原生 iOS 标题胶囊截断态点按落点（审计项 B-4，audit_title_input.md 定性 proven：长标题点按落点映射未实现，光标落位交 UIKit 默认）。

依据通读：audit_title_input.md（B-4 原始审计）、fix_title_capsule_reedit.md（字段常驻结构，本方案建在其上）、MomentApp.swift EditorHeaderView 现行实现（:9787-10069）、Web title_controller.rs（tap_caret_target :228-278、pointerdown 捕获 :842-852、on_focus :558-593、place_caret_next_frame :753-773、utf16_of_char :205-208）与 title.rs display_title_of（:23-31）、plan_ui_selftest_driver.md（U1 抽取点与 S1 场景）。

用户口径来源：2026-11-22 拍板（沿旧代）——截断态长标题点按落点映射到全文对应处，键盘/程序聚焦仍落文末（不干预）。Web 已按此口径实现且审计逐项核对正确；原生缺失，本方案即把该行为等价搬到原生并锁死。

---

## 一、Web 规格逐项提取（行为基准，逐项对源码）

### 1.1 介入条件（四条全满足才映射，否则不干预原生落点）

`tap_caret_target` 返回 Some 的前提（title_controller.rs:238-249）：

1. 全文长度 > 10（`full.chars().count()`；Rust `char` = Unicode 标量值）；
2. 当前显示值恰为 11 个 char；
3. 显示值以 `…` 结尾；
4. 显示值前 10 char 与全文前 10 char 一致（前缀同一性校验，防显示值过期/异源时误映射）。

显示串生成口径（title.rs:23-31 `display_title_of`）：空 → 「无标题」；>10 char → 前 10 char + `…`；否则原文。截断只在 Idle（呈现）态存在，编辑态 input 恒持全文。

### 1.2 记号捕获与生命周期

- 捕获点：`pointerdown` 监听（:842-852），**仅 Idle 态**捕获（编辑中点按的原生落点不干预）；记号 = (char 位, 时间戳)。
- 消费点：`on_focus`（:576-585）取记号，**2000ms 过期作废**；消费后即清。
- 无记号时（:586-589）：换值了（展示值→全文）→ 落文末；未换值（短标题点按）→ 不调落点函数、不干预原生落点。键盘/程序聚焦无记号，走同一「换值落文末」口径。

### 1.3 映射算法（:250-278）

```
rect   = input 布局矩形
disp_w = 镜像实测显示串宽          // 镜像与 input 同字体（见 1.5）
start_x = rect.left + (rect.width − disp_w) / 2     // 显示串居中
rel = x − start_x
rel ≤ 0 → 0
逐前缀 b = 1..=11 实测宽 w_b，取 |w_b − rel| 最小者 best
    （前缀宽单调，w 越过 rel 且距离变大即提前停）
best ≤ 10 → 全文第 best char 位；best = 11 → 全文末尾
char 位 → UTF-16 单位（utf16_of_char，前缀各 char 的 len_utf16 求和）
    → set_selection_range
```

要点：落点是**最近字符边界**（不是字符内部位置）——点在某字字形范围内，落其前缘还是后缘由与相邻前缀宽的中点决定。

### 1.4 落点应用时机（:753-773 place_caret_next_frame）

- 换值（set_value 全文）与定宽在 on_focus 同步完成，**选区延后一帧（rAF）才施加**——focus 事务内同步设选区会被 WebKit 自身落点计算冲掉（Web 侧实测口径，注释明示）。
- 帧内复查：元素仍连接且仍是 activeElement 才动作，否则弃置；落点钳到当前 value 长度。
- Diag 留痕：`EDIT title caret tap -> {m}`（m 为 char 位）。

### 1.5 字体度量来源

离屏镜像 span（attach 时建，:805-841）：`position:fixed; left:-9999px; visibility:hidden; white-space:nowrap`，字体五属性（font-family / font-size / font-weight / font-style / **letter-spacing**）在 attach 时从 input 的 computed style **拷一次**——量测与呈现同源由构造保证，字体两态恒定故不需逐次同步。胶囊现行字号 14、字距 −0.2px（editor.css 与原生 capsuleWidth 注释互证）。

### 1.6 边界情形（Web 口径逐项）

| 情形 | Web 行为 |
|---|---|
| 点在文本左缘外（居中留白区） | rel ≤ 0 → 落点 0（全文首） |
| 点在第 k 字（1..10）字形范围 | 最近边界：近前缘落 k−1、近后缘落 k |
| 点在第 10 字后缘与省略号之间 | 由距离定：近 10 字后缘 → 10；近省略号 → 全文末尾。省略号是完整字形（宽 ≈ 字号），其与第 10 字后缘的中点即分界，**不存在省略号内部落点** |
| 点在省略号上 / 其右侧留白 | best = 11 → 全文末尾 |
| CJK 标题 | 标量即字，逐前缀实测天然处理（每字宽 ≈ 字号），无特殊分支 |
| 混排 / astral（emoji 等） | 计数与映射全程标量口径；astral 标量算 1 char、宽度按实测；UTF-16 换算只在最后施加一步，标量位不串位 |
| 字素簇（组合符、ZWJ 序列） | 标量边界可落在簇内，浏览器接受——Web 既有口径如此，原生侧差异见 §3.4 |
| 全文恰 11 标量 | 截断显示同形（10+…）；省略号点 → 末尾 = 第 11 位，与「第 10 字后」相邻不冲突 |
| 点按后 2000ms 内未聚焦 | 记号过期作废，下次聚焦不干预 |

---

## 二、原生现状与缺口（对现行代码）

现行结构（fix_title_capsule_reedit.md 落地后，MomentApp.swift:9960-10035）：

- 字段 = SwiftUI `TextField`，恒常驻层级，绑定 `ui.titleDraft`（**恒持全文**，截断只是呈现层的事——与 Web「input 展示态持截断串」不同，原生无换值动作）；
- 截断态（`!titleFocused && titleDraft.unicodeScalars.count > 10`）：字段 `.opacity(0)`，覆盖层 `Text(scalarPrefix(draft,10) + "…")`（同字体 14 semibold、tracking −0.2、单行、`frame(maxWidth:.infinity)`、`contentShape(Rectangle())`）以 `.onTapGesture`（**不带坐标**）置 `titleFocused = true`；
- `capsuleWidth` 量测 `shown` 用 `UIFont.systemFont(14, .semibold)` + `.kern: −0.2`（:10037-10047）——量测口径与呈现同源已在仓内成立。

缺口有二，缺一不可：

1. **点按坐标根本没被捕获**：`onTapGesture` 不提供 location，x 无从谈起。
2. **字段没有选区编程面**：SwiftUI `TextField` 不暴露选区（无 `selectedTextRange`、无选区绑定；`TextEditor` 的 TextSelection 亦不适用于 TextField，截至 iOS 27 SDK 仍然）。聚焦后落点完全交 UIKit 对 SwiftUI 字段的默认处理——这正是 B-4 的 proven 结论。

计数基已对齐、无需处理：原生截断与落点全程 `unicodeScalars`（scalarPrefix + 计数，B-6 已按 Web 标量口径收敛），与 Web `chars()` 同义。

---

## 三、实现路径评估与裁定

### 3.1 路径 A：纯 SwiftUI（捕获坐标 + 设法施加选区）

捕获坐标本身可行（`SpatialTapGesture`，部署目标 16.0 起可用），但**施加选区无任何公开 API**——捕获了也无处落。此路不通，否决。

### 3.2 路径 B：字段换 UITextField 的 UIViewRepresentable（**裁定：采用**）

仓内同型基建已实证：`BlockTextView`（UITextView representable + Coordinator delegate + claimInitialFocus 的延后落焦纪律）、`MdTextGroupView`、`ZoomableImageView`——representable 的建、拆、delegate 收敛在本仓不是新造轮子，本路径按 BlockTextView 的 Coordinator 纪律建模。

能力面：`selectedTextRange` 全控；`becomeFirstResponder` / `resignFirstResponder` 与状态位双向同步；return 键经 delegate `textFieldShouldReturn` 收口；组字（marked text）是 UITextField 原生路径，映射只在会话开始瞬间施加一次、不与组字相交。

与既有结构逐项兼容：

| 既有口径 | 路径 B 下的落点 |
|---|---|
| 字段常驻（根治批不变量） | `makeUIView` 只建一次、字段恒在层级；身份由 UIView 实例承载，常驻比 SwiftUI 字段更硬。不变量保持，[24] 的结构锁改写为锁 representable（见 §5） |
| 截断覆盖层 | 不动（仍 SwiftUI Text）；手势由 `onTapGesture` 换 `SpatialTapGesture` 取 `location`；闭包抽为具名入口（与 U1 方案的抽取点 1 合流，见 §5.3） |
| 坞态冻结 `dockCompact` | 仍读 `titleFocused` Bool 单一派生；状态位保留为单一真相，representable 只做执行器（true → become；delegate 回调回写），派生口径零改动 |
| 会话状态机（onChange of titleFocused） | 快照支路（titleBase = editor.title、Diag session begin）与失焦支路（commitTitle）原样保留——状态位仍是同一 Bool，onChange 照常触发 |
| commitTitle / Esc / Enter | commitTitle 零改动（仍读 ui.titleDraft）；Esc 仍由 handleEscape 置 `titleFocused = false` → 执行器 resign；Enter 由 `textFieldShouldReturn` 调 commitTitle + 置 false（与现行 onSubmit 等价） |
| 草稿同步 | delegate 文本变更回调单向写 `ui.titleDraft`（与现行 Binding setter 等价）；`updateUIView` **编辑/组字期禁反写** field.text（BlockTextView 同款纪律），仅非编辑态或外部变更（如 Esc 还原写草稿、切换笔记）时同步——断开「每键 @Published 发布 → 整树重演算 → updateUIView」回写环，防组字打断（B-11 同源风险） |
| 呈现对齐 | `textAlignment = .center`、font = system 14 semibold、`.kern: −0.2` 经 `defaultTextAttributes`、placeholder「无标题」同字体——与现行 SwiftUI 字段逐项对齐；截断态容器 `.opacity(0)` 施加位置由字段修饰器移到 representable 容器，覆盖层关系不变 |
| Diag | 新增 `EDIT title caret -> {caret}`（与 Web 日志同文同义，跨端判读一致），记于施加点 |

风险与处置：

- **R1 状态位与真实第一响应者漂移**：`titleFocused` 由 `@FocusState` 改普通 `@State Bool` 后（FocusState 管不了 representable），定两条收敛律——置 true 的入口只有覆盖层具名入口与程序化入口；`textFieldDidEndEditing` 无条件回写 false（其 commitTitle 与现行 onChange 失焦支路等价合流，防双重提交：commitTitle 幂等——final == editor.title 时只收敛草稿，既有实现已然）。
- **R2 updateUIView 重入**：靠 R-纪律「编辑期不反写」断环，与 BlockTextView 现行运行实证同型。
- **R3 细节映射**：`submitLabel(.done)` → `returnKeyType = .done`；`.focused` 修饰器退场后，键盘升起的事实源 = didBeginEditing；逐项在改动清单中对表，无缺口。

代价：新文件 1（TitleTextField representable + Coordinator，约 150–200 行）+ 胶囊段改接线（约 50 行）+ [24] 两条断言改写 + 新增断言组（§5）。无 FFI、无数据层、无桥协议变更。

### 3.3 路径 C：保留 SwiftUI TextField + 层级内省找底层 UITextField

依赖 SwiftUI 私有视图层级结构，属在消费方打补丁（开发红线③）、系统升级即碎，且内省到的字段身份与常驻不变量无契约关系。**明确否决，记录理由防后人重提。**

### 3.4 原生特有边界：字素簇吸附

算式全程标量口径（与 Web 一致），caret 标量位可能落在字素簇内部（组合附加符、emoji ZWJ 序列、区域指示符对）。UITextField 对簇内选区通常吸附到最近簇边界——与 Web（浏览器接受簇内位）有细微差。处置：**不做簇对齐预处理**（保持算式与 Web 同源），簇吸附列为平台行为；在断言边界表中单列一例，期望值标注「平台吸附后的簇边界」，由驱动回读实证后回填（§5.2）。RTL 标题：居中几何与 Web 同一 LTR 假设，同为既有口径外，不在本批。

---

## 四、几何前提清单（先占位与前提，后算式）

### 4.1 占位（量）

| 符号 | 定义 | 来源 |
|---|---|---|
| `full` | 全文（呈现态下 = editor.title） | tap 时刻读 ui.titleDraft |
| `disp` | 显示串 = `scalarPrefix(full, 10) + "…"`（11 标量） | 与覆盖层渲染同一表达式现算 |
| `rowW` | 标题行宽 = `capsuleWidth − 40` | 胶囊横向 padding 20×2；覆盖层 frame 即此宽 |
| `tapX` | 点按 x（覆盖层坐标系，原点在行左缘） | SpatialTapGesture 的 `location`（手势挂在覆盖层上，其 frame 满行宽） |
| `W(s)` | 字符串在规范量测属性下的宽 | §4.2 P2 的属性集 |
| `startX` / `rel` / `best` / `caret` / `caretUTF16` | 文本左缘 / 相对偏移 / 最近前缀长 / 落点标量位 / 落点 UTF-16 偏移 | §4.3 算式 |

### 4.2 前提（成立才许用算式；每条注明依据与失效条件）

- **P0 呈现态一致性**：未聚焦时 `ui.titleDraft == editor.title`。依据：失焦 commitTitle 把草稿收敛到 final 并写回 titleDraft、聚焦快照 titleBase = editor.title（现行 :9913-9937、:9990-10000）。映射在 tap 时刻现读现算、不缓存全文。
- **P1 显示串同一性**：映射消费的 `disp` 与覆盖层实际渲染的串同值——同一表达式、同一输入（full）、在 tap 处理内现算。呈现态无写入路径改草稿（字段 opacity 0 不可达；外部改标题必伴随重渲染），故渲染与 tap 之间 full 不变。
- **P2 量测口径同一性**：`W` 的属性集 = 呈现属性集 = capsuleWidth 现行量测属性集：`UIFont.systemFont(ofSize: 14, weight: .semibold)` + `.kern: −0.2`（即 `.font(.system(size:14, weight:.semibold)).tracking(−0.2)` 的 UIKit 等价，:10008、:10042-10047 已互证）。**耦合钉子**：标题字号现行写死 14、不随 Dynamic Type 缩放，写死量测恒与渲染一致；将来若标题改随系统字号，本前提失效、量测须同步改——此耦合须写进实现注释与断言（§5 T26-6 附带检查量测属性字面与呈现字面同源）。
- **P3 居中几何**：覆盖层 Text 在 rowW 内居中（`frame(maxWidth:.infinity)` + 单行 Text 居中呈现），故 `startX = (rowW − W(disp)) / 2`。极端窄屏下 capsuleWidth 被上限钳制可致 W(disp) > rowW、startX 为负——公式与 Web 同式同域、不另加钳，映射仍单调可用；该情形的视觉裁切是既有口径，与本批无关。
- **P4 前缀宽弱单调**：`W(disp 前 b 标量)` 随 b 大体单调；kern −0.2 在零宽标量（组合附加符）处可造成 ≤0.2pt 局部回退。故原生**不沿用 Web 的提前退出优化，全扫 11 个前缀取最近**（11 次量测成本可忽略），最近边界规则不依赖严格单调——与 Web 结果等价或更稳，属实现更优而非口径分叉。
- **P5 几何在 tap 时刻定格（结构律，最关键）**：capsuleWidth 依赖 titleFocused——聚焦后 shown 切全文、宽度 0.2s 动画展开，呈现态几何随即失效。故映射必须在**置焦之前**用呈现态几何算完、存为待施加记号 `pendingCaret`，聚焦落定后只施加、不重算。与 Web「pointerdown 捕获记号、on_focus 消费」同构。对应地，原生记号不需要 Web 的 2000ms 过期：原生的 tap 与置焦是同一手势的同一入口（不存在 pointerdown 与 focus 分离的两段），记号在入口内产生、在本次会话开始时消费或弃置；程序化置焦（无 tap）天然无记号。
- **P6 施加时机与复查**：选区延后到字段成为第一响应者之后一拍施加（didBeginEditing 内下一轮 runloop，与 Web rAF 延后同理——聚焦事务内同步设选区会被 UIKit 自身落焦落点覆盖）；施加前复查：字段仍是第一响应者、`markedTextRange == nil`（不在组字中）、记号未被消费；不满足则弃记号、不重试。
- **P7 偏移单位**：标量位 → UITextField 偏移按 UTF-16 单位换算（`utf16OfScalarIndex`，与 Web utf16_of_char 同义）。UITextField `position(from:offset:)` 偏移为 UTF-16 单位是平台通行口径，但列为**待实证前提**：由施加后回读断言锁定（回读 `offset(from: beginningOfDocument, to: caret)` 与期望 UTF-16 值比对，不符记 Diag 异常行）——见 §5.2 驱动步与 §5.1 T26-4。

### 4.3 算式（前提齐备后）

```
rel = tapX − (rowW − W(disp)) / 2
rel ≤ 0            → caret = 0
best = argmin_{b ∈ 1..11} |W(disp 前 b 标量) − rel|        // 全扫，见 P4
caret = best ≤ 10 ? best : full.unicodeScalars.count
caretUTF16 = full 前 caret 个标量的 UTF-16 长度和
施加: field.selectedTextRange = [pos(caretUTF16), pos(caretUTF16))
留痕: Diag "EDIT title caret -> {caret}"
```

**无记号路径（不干预清单）**：非截断态点按（字段本体原生落焦）、键盘/程序聚焦、驱动程序化置焦未带 atX——一律不写选区，落点交 UIKit 默认。如实标注一处细微差：Web 键盘聚焦在「换值时落文末」；原生字段恒持全文、无换值动作，UIKit 程序化聚焦默认落点通常即文末——实际等价，不另造落文末代码（造了反而多一处与 P6 冲突的施加点）。

**覆盖层行外**：覆盖层只占标题行；胶囊上下留白区点按不达覆盖层、不落焦——与 Web B-9 同形态（原版亦然），不在本批范围。

---

## 五、断言设计

组号建议 **[26]**（[24] 标题根治、[25] 自检驱动已占；最终以组版时主线分配为准）。

### 5.1 verify 结构锁（锁机制，不锁数值）

- **T26-1 常驻不变量（新结构版）**：胶囊段 SwiftUI `TextField(` 零残留；`TitleTextField` representable 在位；`makeUIView` 内无以 truncated/titleFocused 为条件的字段插入分支。与 [24] T24-1 联动改写（同一批提交，不留两套口径）。
- **T26-2 入口单一来源**：覆盖层手势为 `SpatialTapGesture`；具名入口 `activateTitleFromCapsule(atX:)` 在位（签名见 §5.3）；覆盖层手势体与驱动注册动作都只调该入口（grep 入口调用点 ≥2 且无第二处直接置 `titleFocused = true` 的胶囊路径）。
- **T26-3 时序锁（锁 P5）**：入口源码内「计算 pendingCaret」行序在「titleFocused = true」行序之前；且全文无第二处计算映射的代码（映射纯函数单点）。
- **T26-4 施加锁（锁 P6/P7）**：选区施加点位于 didBeginEditing 的延后块内、带 `markedTextRange` 守卫与第一响应者复查、带施加后回读比对与异常 Diag；`EDIT title caret ->` 日志行在位。
- **T26-5 无记号不干预锁**：施加块以 `pendingCaret != nil` 为唯一进入条件；EditorHeaderView 全段除施加点外无第二处写 `selectedTextRange`。
- **T26-6 同步纪律锁**：`updateUIView` 内编辑期不反写守卫在位（grep 守卫式：编辑态/组字态判断在 text 赋值之前）。
- **T26-7 既有行为锚（防回退，与 T24-5 并行）**：commitTitle 的 trim+空回退式、titleBase 快照行、Enter 收口（shouldReturn 调 commitTitle 并辞焦）在位。

### 5.2 数值断言（真断言，非结构锁）

映射核心抽为 **Foundation-only 纯函数文件 `TitleTapCaret.swift`**：入参 = 全文标量数组、显示串逐前缀宽度数组（量测在调用点完成、函数不碰 UIKit 量测）、tapX、rowW；出参 = caret 标量位；另含 `utf16OfScalarIndex` 纯函数。此形态使数值表可在 tree 冒烟环境以 `swiftc` 独立编译该文件 + 测试主文件真跑：

预置宽度表（等宽字形模拟：ASCII 标量 7pt、CJK 标量 14pt、省略号 14pt、astral 标量 16pt）：

| 例 | 输入概要 | 期望 caret |
|---|---|---|
| 左缘外 | rel < 0 | 0 |
| 第 k 字中心（k=1..10，ASCII 与 CJK 各一组） | tapX = startX + (w_{k−1}+w_k)/2 | k 与 k−1 的近者（按表值算定） |
| 省略号中心 | tapX = startX + (w_10 + w_11)/2 | fullLen |
| 第 10 字后缘/省略号中点两侧 | 中点 ±1pt | 10 / fullLen |
| astral 混排 | 全文含 emoji，caret 标量位 3（其前含 1 个 astral） | caret=3 且 caretUTF16=4 |
| 恰 11 标量全文 | 省略号中心 | 11（= fullLen） |
| 簇内位（标注例） | 组合序列标题，tap 落簇内标量边界 | 算式值照出；**实机期望 = 平台吸附簇边界**，此例只锁算式、实机值由 §5.3 回读回填记录，不作红绿判据 |

若独立编译在组版时遇阻（构建文件清单等），降级为结构锁 + §5.3 驱动回读，并在落地报告中如实标注降级，不冒充数值已验。

### 5.3 与自检驱动 S1 的关系（能验到哪层）

衔接点：plan_ui_selftest_driver.md 的 U1 抽取点 1 已定把覆盖层闭包抽为 `activateTitleFromCapsule()`。本方案要求该入口**一次定死签名**为 `activateTitleFromCapsule(atX: CGFloat?)`（nil = 无记号；手指路径传 SpatialTapGesture 的 location.x，U1 的 S1 步 5 传 nil 或指定值）——避免 U1 与本批各抽一次、各改一次签名。

驱动新增可选步 **S1-C（落点回读）**，挂在 S1 步 5 之后（截断态、夹具长标题已知）：

1. 场景按夹具标题 + `uitest_measure` 实测逐前缀宽（或 App 内量测通道直读 W 表）算定期望 caret；
2. 以指定 atX 调具名入口 → waitDiag `EDIT title caret -> {期望值}`；
3. 经注册面状态读回读字段选区 UTF-16 偏移，断言与 caretUTF16 一致。

**验到的层**：映射算式（真机真实字体度量下）、记号定格时序、延后施加、UTF-16 单位换算（P7 在此被实证锁定）、与 S1 既有状态机回路同层 proven。**验不到的层**：真实手指下 SpatialTapGesture 的 location 投递精度（驱动直传 x、不经手势识别器）——该层仍属真机人工终判，一例即可（长标题点第 3 字附近，目视光标落位）。证据表述规矩与驱动方案 §6 一致：汇报时写作「映射+施加 proven（驱动）／手势坐标投递待真机一例」，不升级。

---

## 六、排期建议

**规模**：小到中。新文件 2（`TitleTextField.swift` 约 150–200 行、`TitleTapCaret.swift` 约 60 行）+ 胶囊段改接线约 50 行 + verify [26] 约 7 条 + [24] T24-1/T24-2 改写 + Diag 一行。无 FFI、无数据层、无桥协议变更。

**建议：并入 U 批、随 U1 同批落地。** 理由：

1. **同一手术面只开一次**：U1 本就要抽覆盖层入口并改胶囊段；本批要给同一入口加 atX 并换字段类型。分两批 = 对 EditorHeaderView 胶囊段连做两次结构手术，[24] 断言要改两轮，中间态还要单独冒烟一轮。
2. **验收合流**：本批数值正确性的最强验收是 S1-C 在真机度量下的回读（§5.3）；同批落地即出厂带自动化验收，正合用户「这类问题要能自动化验」的要求。单独先行只能靠结构锁 + §5.2 独立编译数值表 + 人工一例，强度低一档。
3. **耦合点只有一个且可预先冻结**：驱动经注册动作调入口，不依赖字段类型；字段替换不改变驱动接口。唯一耦合 = 入口签名，本方案已定死（§5.3），U1 按此实现即可零返工。

**备选（独立小批先行）**：若 U 批启动明显后延而用户想先要落点，本批可独立成版（断言走 §5.1 + §5.2，真机人工一例终判），代价即理由 1 的重复手术。裁断口径建议：U 批在两版内启动 → 并入；否则独立先行。此口径供主线按 U 批实际启动时间定夺。

**不在本批**：B-9 留白区命中面（与原版同形态）、RTL 标题几何、标题随 Dynamic Type（P2 耦合钉子只留注释与检查，不动现行写死 14 口径）。
