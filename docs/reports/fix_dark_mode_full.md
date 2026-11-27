# 深色模式适配全面排查根治（fix_dark_mode_full）

用户真机实报 + 截图（2026-11-27 19:14，证据图 `~/workspace/user/files/09917983-…-FC210D7E6C5F.jpg`，0.9.58）：编辑页上顶部整片深色、正文却黑字；待办完成文过淡、未选圈几乎不可见；并点名排查斜杠菜单每一项的深色适配。本批先定性、后根治，颜色一律收敛自适应令牌单源；与 DT 批（fix_dynamic_type_follow）划界：本批只管颜色、不动字体/量测，交叉点仅 `updateUIView` epoch 支的 typingAttributes 字典（彼批所建、本批只加颜色一项）。

## 一、截图定点定性（线 A）

**设备当时处于深色外观——proven。** 同页多处彼此独立的动态面一致解析为深色值，互为对照：状态栏白字；标题字段白字（TitleTextField 的 `textColor = T.textMainUI` 动态色）；页眉玻璃件呈深色令牌值（`glassControlTint` 深 #38383C@0.96）；待办已选圈为深色值 #0A84FF（浅值 #0066CC 更暗，图中为亮蓝）；待办完成文呈 #B4B4B9 浅灰（其浅色值 #626267 为深灰，图中明显发白）。

逐元素辨认图中「整片深色」到底是谁：

| 图中元素 | 组件 | 颜色来源 | 深色下是否正确 |
|---|---|---|---|
| 返回钮 / 头像圈 / 标题胶囊 / ••• 钮 | 编辑页眉玻璃件（GlassCard：ultraThinMaterial + `T.glassControlTint` + `T.glassBorder`；标题走 TitleTextField） | 令牌 + 动态 UIColor | ✓ 正确（深色玻璃本该如此） |
| 页眉下整片深色大卡 | 首块 **imgTextCard**（上图下文）：`.contentCard` = `T.contentBg`（深 #202024）；图区是深色调图片本体；下沿「点击查看完整文本」是其 textLabel（`T.textSecondary` 深值 #98989D） | 令牌 | ✓ 正确 |
| 页底鼠尾草色 | 该备忘自定义底色经 `T.memoBg` 深色压暗（×0.55；Web `darken_hex` 同口径，editor.rs:108） | 令牌（数据色工厂） | ✓ 设计内（双外观下都呈中明度，是整页「看着像浅色」的来源之一） |
| 标题/引用/待办文/正文（黑字） | **BlockTextView**（UITextView 桥） | 见下，**坏** | ✗ 深色下恒黑 |
| 图底另一张图文卡（左图右文「点击输入说明文字」） | imageTextRow：`T.contentBg` + SwiftUI Text（`T.textMain`） | 令牌 | ✓ 正确（白字深底即深色正解） |

**真故障只有一个面：编辑器正文（及同源的 MD 预览文本组）。** 机制（observable 层 proven、UIKit 内部层 inferred）：

- `Marks.attributed(runs:base:)` 构建的属性串里，普通 run **不带 `.foregroundColor`**（只有链接 run 与公式失败 run 显式给色）；正文颜色的唯一通道是承载视图的 `tv.textColor`（非引用 `.label`、引用 `T.quoteTextUI`）。
- 真机实证该通道不达渲染：同页同视图上，`applyDoneStyle` 以**显式属性**写入的动态色（完成文）随外观翻到了深色值，而靠 textColor 兜底的正文恒黑。浅色下默黑恰与正色 #1A1A1A 近同值，故此病只在深色暴露。
- 内部解释（inferred）：TextKit 2 承载下 `UITextView.textColor` 与已设置的 `attributedText` 渲染解耦，无显式前景的 run 取属性串默黑。修复不依赖此解释成立——把动态色显式写进串里即绕开整条通道，且有完成文的同页先例证明显式动态色在串内会随 trait 重解析（绘制时以视图当前 trait 解析 provider，非构建快照；故外观切换无需整串重建，与字体快照须 epoch 重建分工不同）。

**待办两症的定性：**

- 未选圈几乎不可见——**令牌值写错，proven**：`T.checkBorder` 两态同写 #73737A，其注释只引了 Web 浅色值；Web `tokens.css:227` 深色值为 **#B5B5BB**。深色下圈边恒中灰，压在压暗后的彩色备忘底上对比殆尽。
- 完成文过淡——**色值与 Web 逐值同账**（`--md-text-muted` 浅 #626267 / 深 #B4B4B9，tokens.css:25/224，原生 applyDoneStyle 内联闭包同值）。其观感过淡（inferred）主因是整页明暗错乱（正文恒黑使页面读作浅色，浅灰完成文随之读作「浅底上的淡字」）叠加中明度备忘底的天然低对比；不擅改 parity 值，根治正文后列入终判复核。

## 二、全面排查逐面三态表（线 B）

来源记法：令牌 = `T.*` 动态色；动态UI = trait 闭包 UIColor；系统 = SwiftUI/UIKit 系统动态色/材质；字面 = 裸字面（须归令或白名单）。

### 2.1 斜杠菜单（用户点名，逐项列全）

24 项全部经 `slashRow` 单点渲染（`SlashCmds.all`，面板底 = `overlayCard` → `T.overlayBg`），无逐项自带色：

- 基础组 19 项：标题 1（textformat.size）/ 标题 2 / 标题 3 / 文本（text.alignleft）/ 引用（quote.opening）/ 待办（checklist）/ 分割线（minus）/ 加粗（bold）/ 斜体（italic）/ 高亮（highlighter）/ 代码块（chevron.left.forwardslash.chevron.right）/ **公式块（sum）** / 无序列表（list.bullet）/ 有序列表（list.number）/ Callout（exclamationmark.bubble）/ 链接（link）/ 代码（同代码块图标）/ **行内公式（function）** / 删除线（strikethrough）。
- 媒体组 5 项：图文卡片（doc.richtext）/ 图文混排（rectangle.split.2x1）/ 音乐卡片（music.note）/ 图片（photo）/ 画廊（photo.on.rectangle.angled）。

行内各面：图标 `T.accent`；标题 `T.textMain`（命中段同色 + `T.fillAccent18` 底）；副文 `T.textSecondary`；快捷键丸 `T.textSecondary` / `T.fillHover` 底（整丸 opacity 0.78）；选中行底 `T.fillHover`；最近丸 `T.glassLabel` / `T.glassControlTint` 底 / `T.glassBorder` 边；组头 `T.textSecondary`@0.8 + `T.borderSoft` 分隔线；空态 `T.textSecondary`（图标 @0.45）+ kbd 丸 `T.fillHover`；链接表单：标题/取消钮 `T.textMain`、输入框 `T.fillSubtle` 底 + `T.borderSoft` 边、错误行 `T.danger`、提交钮白字（原 `.white` 字面 → 已归令 `T.onAccent`）/ `T.accent` 底。

结论：**斜杠菜单全项双外观成立、无逐项缺口**；唯一字面（提交钮 .white）已归令。禁用态：原生与 Web 均无此设计（行恒可点，作用于选区的命令在无选区时走占位口径），无可适配面——如实登记，不造态。

### 2.2 编辑器全部块型

| 块型 | 文字面 | 底/边/标记面 | 结论 |
|---|---|---|---|
| 正文 / 标题 / 列表项 | BlockTextView ← Marks.attributed | — | ✗ 本批根治（显式基准色） |
| 待办 | 同上 + applyDoneStyle（`T.doneTextUI` 归令后） | 勾选圈 SwiftUI：`T.checkChecked` ✓ / 未选 `T.checkBorder`（深值已归正） | ✗→✓ 两处已修 |
| 引用 | BlockTextView（quote 支基准色） | `T.quoteBg` / `T.quoteBar` / `T.quoteText(UI)` 令牌 | ✗→✓ 随基准色修 |
| 提示 callout | BlockTextView | `T.calloutBg` / `T.calloutAccent` 五变体令牌 | ✗→✓ 随基准色修 |
| 代码块 | BlockTextView（mono） | `T.codeBg` 令牌；行内码底 `T.codeBgUI`（归令后） | ✗→✓ 随基准色修 |
| MD 块（预览） | MdTextGroupView ← MdRender.attributed ← Marks.attributed | 表格 `T.cardBg` 等令牌；任务未选标记原误用 `T.textSecondary` → 已归 `T.checkBorder`；表头文字经视图 textColor 传 `T.quoteTextUI`（构建器已同喂） | ✗→✓ 已修 |
| 公式（行内/块） | MathImageStore 快照（WKWebView 按 job 以 `overrideUserInterfaceStyle` 钉外观渲图，深浅各渲一份） | 失败原码 `T.mathFail(UI)` | ✓ 设计内（白名单：逐 job 钉外观） |
| 图片 / gallery | — | 占位 `T.fillSubtle` + `T.textSecondary`；删项角标 palette（白 / 黑 0.55，压在图片上） | ✓（角标白名单：图上控件、与外观无关） |
| 图文卡 / 图文混排 | SwiftUI Text：`T.textMain` / `T.textSecondary` | `.contentCard` = `T.contentBg` | ✓（截图实证正确） |
| 音乐卡 / 链接卡 / 视频 / 附件 | SwiftUI Text 令牌面 | `.contentCard` 令牌 | ✓（字面普查零命中其区域） |
| 分隔线 | — | `T.borderSoft` | ✓ |

### 2.3 其余各面

| 面 | 来源 | 结论 |
|---|---|---|
| 首页列表 / 网格 | 全 `T.*`（组头 `T.glassLabel`、卡面玻璃令牌、备忘底 `T.memoBg`） | ✓ |
| 编辑页眉（返回/头像/标题胶囊/•••/完成胶囊） | GlassCard 材质 + 玻璃令牌；TitleTextField 动态 UI + `UIColor.placeholderText`（系统动态） | ✓（截图实证） |
| 设置族各页 | 全 `T.*`（SetRow 家族） | ✓ |
| 图片页 | 全 `T.*`（页头玻璃 + 标题令牌） | ✓ |
| 救援页 | glassCard + `T.*`；主钮白字原字面 → `T.onAccent` | ✓ 已归令 |
| 浮层面板/菜单（卡菜单、••• 菜单、导出、备份底表） | `OverlayCard` / `GlassCard` 令牌；菜单项 `T.glassLabel` | ✓ |
| toast（撤销条/状态条） | `T.textMain` / `T.accent` / overlay 档令牌 | ✓ |
| 错误徽章 | 底 `T.dangerBright` / `T.warning`，字原 `.white` → `T.onAccent` | ✓ 已归令 |
| 桥设置页 | 全 `T.*`；配对二维码 `Color.white` 底板 | ✓（白名单：深色下可扫性功能要求，注释在位） |
| Diag（诊断卡 + 全屏日志页） | 终端绿字/深底原 4 处字面 → `T.termText` / `T.termBg`（明暗同值的固定终端调色） | ✓ 已归令 |
| 权限页（在途新页） | 全 `T.*`（含 statusTint 返回令牌色） | ✓ |
| 实况 Widget | `.secondary` 系统动态样式 | ✓ |
| 开屏（SplashHost / NativeMomentSplash / Canvas） | 艺术常量 + `colorScheme` 显式双支（底色深 #1F1F21 / 浅 #2379DC 等） | ✓（白名单：艺术面、双支按构造正确） |
| 图文卡编辑 sheet 的 TextEditor | 系统编辑器默认动态色 | ✓ |
| PHPicker / ShareSheet | 系统 UI | ✓ 不适用 |

### 2.4 裸色字面普查（全集）

`MomentApp.swift` 代码行内 `(UIColor|Color)(red:` 恒 8 行，逐个点名：T 工厂 2（memoBg 浅支 UIColor、colorOf 的 Color）+ T 令牌定义 2（fillHighlightUI、fillAccent18UI——令牌本体即字面归宿）+ 开屏艺术 4（splashColor 深浅、开屏底深浅）。`.foregroundStyle(.white)` 全仓归零（6 用点归令 onAccent）；`Color.white` 仅桥设置二维码底板 1 处；`Color.black` 仅 gallery 角标 palette 1 处 + 开屏 Canvas 渐变 2 处。其余文件（Bridge/Launch/Ops/Drag/Transition/LiveOps/Permissions/SvgRaster/TitleTextField）字面零命中或全令牌。`T.colorOf/rgbOf` 为数据色工厂（用户备忘底色/色板数据），非 chrome 字面，白名单。

## 三、根治落点（全部单点，无逐面补丁）

1. **正文显式前景（核心）**：`Marks.attributed(runs:base:baseColor:)` 新增基准色形参（默认 `T.textMainUI`），普通 run 在属性字典初值即带 `.foregroundColor: baseColor`；链接/公式失败 run 的后赋值覆写不变。编辑器与 MD 预览共用此构建器，一处修两面全集（正文/标题/待办/引用/提示/代码/MD 文本组/表格）。
2. **基准色单点三面同喂**：`BlockTextView.baseColorUI(for:)`（引用 → quoteTextUI、余 → textMainUI）同时喂 attributed 串、typingAttributes（键入新字前景——旧形态键入字同样无色可依）、textColor（兜底面）；非引用 textColor 旧值 `.label` 退役归一 textMainUI（与 Web --text-main 同账）。`updateUIView` epoch 持焦支的 typingAttributes 同步同构成（与 DT 批交叉点，仅加颜色项）。
3. **MD 侧同喂**：`MdRender.attributed` 增 `baseColor` 形参转发；表格头调用点把 `T.quoteTextUI` 同时喂构建器与视图（此前只喂视图、串内无色）。
4. **令牌值归正**：`T.checkBorder` 深值 #73737A → **#B5B5BB**（tokens.css:227），注释改引双值出处。
5. **新令牌五件 + 散写归令**：`T.onAccent`（白，6 用点：徽章/链接提交/网格空态/窄屏空态/备份确认/救援主钮）、`T.termText`+`T.termBg`（Diag 两页 4 用点）、`T.doneTextUI`（applyDoneStyle 内联闭包 → 令牌）、`T.codeBgUI`（Marks.inlineCodeBg 自持闭包 → 令牌转发）、链接属性内联闭包 → `T.linkBlueUI`、applyHighlightTint 内联色 → `T.fillHighlightUI`。
6. **MD 任务标记归一**：预览面未选方框 `T.textSecondary` → `T.checkBorder`，与编辑面同一 checkbox 令牌单源（浅值 #68686D→#73737A 近似归一、深值归正）。

浅色行为等价核对：本批所有改动的浅色值与旧值逐一同值（基准色 #1A1A1A = textMain 浅值；typingAttributes 新增前景不改既有渲染路径的浅色结果；checkBorder 浅值未动；onAccent/term 色同值替换）。

## 四、断言（verify_ios.sh 新组 [45]，DM45-1..7，本机自跑全绿）

- DM45-1 裸色字面普查计数锁（8 行 + 点名子锚 35.0/255×2、31.0/255×2、UIColor(red:×3）——新增字面必破。
- DM45-2 `.foregroundStyle(.white)` 全仓 = 0 + onAccent 用点 6 + 二维码白底板 = 1。
- DM45-3 双构建器 `baseColor` 同签名 = 2 + run 前景锚 + baseColorUI 单点 + 表格头 quoteTextUI 同喂锚。
- DM45-4 `tv.textColor = .label` = 0（死通道退役锁）+ textColor 由 baseColor 同喂锚。
- DM45-5 checkBorder 深值字面锁 + 新令牌定义/消费计数。
- DM45-6 斜杠单点：slashRow 段四令牌锚齐 + 段内无 `Color(red:` + 面板 overlayCard 锚。
- DM45-7 checkBorder 双面用点 = 2。

全量自跑：422 ✓ / 5 ✗，红项归属如实登记——ipa 陈旧、产物语言包（产物类，tree 构建自解）；J20-12、DT36-4 为 DT 批在其 `scaledBase` 改写区的断言待改锚（非本批面；本批 checkBorder hunk 位于同区、与其改写并存完好）；PC44-5 为权限批在途。类型检查（源码快照）：MomentApp primary 遍仅 3 个 error，全为菜单区 `f15` 未声明（DT 批语义量测转换在途、非本批领地），本批各区零 error；MomentRescue primary 遍 exit 0、零 error。组版 tree 冒烟为正式收口。

## 五、双外观终判清单（真机，深 / 浅各走一遍）

1. **截图同款编辑页**（自定义底色备忘、深色）：正文/标题/引用/代码文字白系分明；页眉玻璃与首块图文卡保持深色（正确态、勿误判为病）；浅色下与旧版一致。
2. **待办两态**：未选圈深色下清晰可见；完成项删除线文字可读（正文根治后复核其观感，若仍判过淡再议 parity 值）；已选蓝圈两外观各验。
3. **斜杠菜单全项**：深/浅各开一次逐项扫 24 项（图标/标题/副文/快捷键丸/最近丸/选中行/组头），公式块与行内公式在内；空态、链接表单（提交钮白字）一并。
4. **MD 预览**：含表格（表头字）、任务列表（未选方框）、代码段、链接段的 MD 块，深色下文字全白系、方框可见。
5. **外观热切换**：编辑页开着时切系统深/浅，正文颜色即时翻转、不重进页面；持焦块新键入文字颜色正确（typingAttributes 面）。
6. **Diag 两页**：终端绿字深底在两外观下保持不变（设计如此）；错误徽章红/橙底白字两外观可读。
