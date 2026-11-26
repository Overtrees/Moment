# 大屏（PC / 平板 / 横屏）适配审计（审计线 E）

审计日期：2026-11-26。只审计、不改代码。
基准：原版归档 `~/workspace/.scratch/moment-original-archive-2026-11-25/src/` 与 Rust Web 现行实现（两者宽屏口径经抽查一致，如首页三列网格原版 `src/styles/base.css:289` 与 Rust `styles/base.css:371` 同文）。
对象：原生 `rust/apps/ios/app/MomentApp.swift`（0.9.0 双栏落地后、含 0.9.3 卡片批的工作树）。
宽屏判定（两端一致）：`(min-width:768px 且 min-height:600px) 或 min-width:1100px`（Web `editor/hooks/columns.rs:56-68`；原生 `MomentApp.swift:5004-5014` syncWide 同式）。

结论速览：原生编辑页双栏的「骨架」（两物理栏、flow/independent 分流、落锚、菜单开关行）已按 Web 落地，但 Web 宽屏下的一整套**细节度量层**（72ch 文本宽、标题字号 vw 缩放、栏距 vw 缩放、宽屏专属块度量）原生基本未移植，宽屏正文实际是「竖屏渲染器横向拉成两栏」。首页（子题 2）则**完全没有大屏形态**：Web/原版在 ≥768px 或横屏时切换为三列（≥1280 四列）方形卡网格 + 叠卡折叠，原生在任何宽度下都是竖屏单列时间流。

---

## 子题 1：编辑页双栏全模块适配

### 1.0 Web 宽屏度量总表（基准）

| 项 | Web 口径 | 出处 |
|---|---|---|
| 内容总宽 | `.editor-spread` max-width 1440、居中 | editor.css:632-638 |
| 栏距 | 两模式同：gap clamp(28px, 3.2vw, 52px) | editor.css:683、975、1067 |
| flow 形态 | 两物理栏网格、整页滚动、栏内无内边距、分隔线为居中于栏距的渐变线 | editor.css:1063-1080 |
| independent 形态 | 栏高 = 100dvh − 187px − 上下安全区、栏内独立滚动；左栏 padding-right 16 + 右边框、右栏 padding-left 16；栏顶 padding 4、底 24、scroll-padding 12/24 | editor.css:972-1005 |
| 文本行宽（≥900px） | 两模式同：栏内文本类块（段落/标题/引用/列表/代码/表格/待办/MD 块级预览）width min(100%, 72ch) 居中；媒体/卡片仍满栏宽 | editor.css:1132-1190 |
| 标题字号 | h1–h4 按 vw clamp 缩放（如 h1 = clamp(h2, 2.4vw, h1)） | editor.css:397-400 |
| 正文行高 | 宽屏 1.72 | editor.css:684 |
| 图片/图库边距 | 宽屏 margin 8px 0（取消窄屏 36px 两侧内缩） | editor.css:698-700、1029-1032、1099-1102 |
| 附件文件行 | 宽屏 padding 12px 14px、radius 22、gap 8（窄屏 16/20、r32） | editor.css:726-745 |
| 代码块 | 宽屏 pre padding 10px 12px、code padding 0 | editor.css:801-810 |
| 表格 | 宽屏 th/td min-width 5rem、padding 7px 9px | editor.css:813-822 |
| 引用 | 宽屏 padding 9px 12px | editor.css:824-829 |
| 浮层 | 菜单/导出/斜杠面板 fixed 于视口、不入分栏流；菜单/导出宽 246、右 16、top = 安全区+59；斜杠面板按光标定位、max-height 320；底表 max-width 600 居中 | editor.css:833-846、1229、1283、1368 |
| 标题坞 | fixed、left/right 62px（宽窄同值） | editor.css:1200 |
| 反向链接区 | width min(100%, 720px) 居中 | editor.css:1413 |
| 双栏开关行 | 仅宽屏显示（display:none 基础态 + 宽屏 flex） | editor.css:885、973 |

### 1.1 已对齐项（原生有对应实现）

- **宽屏判定与两物理栏**：`MomentApp.swift:4891-4925` contentArea 按 `ui.wide` 分流；`5018-5083` wideColumns 两模式均为物理双栏（flow 整页滚动、independent 双 ScrollView），与 Web 现行口径一致（非 CSS 多列）。
- **总宽上限 1440**：independent 分支 `.frame(maxWidth: 1440)`（`MomentApp.swift:5039` 附近）、flow 分支内层 VStack 同挂（5078 附近）。注意 flow 的上限挂在 ScrollView 内层，未见显式水平居中约束，超宽时是否居中需真机核（inferred 风险项）。
- **分界/落锚/开关行**：分界三函数与落锚为 Web 逐项移植（0.9.0）；菜单首行 twoPaneRow 仅 `ui.wide` 时呈现（`MomentApp.swift:4693-4694`、5085-5115），与 Web 开关行同门槛。
- **••• 菜单 / 导出面板**：宽 246、右 16、top 59、radius 22（`MomentApp.swift:4740、4799` 及 menuPanel 帧），与 Web 固定值一致，宽屏下同样锚右上、不入栏流 ✓。
- **标题坞**：headerOverlay 为浮层 HStack（`MomentApp.swift:4450-4505`），宽窄共用、居中胶囊，行为与 Web fixed 坞等价 ✓（坞距两侧：Web 62px、原生 16px 内边距 + 46 钮，几何近似，非宽屏专项差异）。
- **图片页**：ImagePageView contain 呈现（`MomentApp.swift:8443` 起，scaledToFit + 整幅约束），与 Web panels.css 图片页口径一致 ✓。

### 1.2 差异项（未适配 / 走样）

**E-W1-1** Web ≥900px 时两模式栏内文本类块一律 min(100%,72ch) 居中（editor.css:1132-1190）。原生 blockColumn（`MomentApp.swift:4963-4980`）对所有块一视同仁满栏宽渲染，无任何 per-type 宽度约束。1440 宽下单栏约 660px ≈ 82ch，正文行长明显超过 Web，阅读节奏走样。建议：blockColumn 内对文本类块（paragraph/heading/quote/list/codeBlock/todo/MD 预览）加 maxWidth 72ch 等价宽（约 576pt @16pt）并居中，媒体/卡片块保持满栏。

**E-W1-2** Web 宽屏 h1–h4 走 clamp(vw) 缩放（editor.css:397-400）。原生 Marks.baseFont（`MomentApp.swift:945-961`）字号恒 28/23/20（仅随 Dynamic Type），wide 标志不参与字号决策。建议：baseFont 或 BlockRow 标题路径读 editor.columnsActive，宽屏按 Web clamp 比例放大（h1 约 ×1.15–1.3 区间随宽）。

**E-W1-3** Web 两模式栏距同为 clamp(28px,3.2vw,52px)（1440 宽时 ≈46px）。原生 flow 为分隔线两侧各 20px + 1px 线 = 41px 固定（`MomentApp.swift:5060`）；independent 为左右各 16px 内边距 + 1px 线 = 33px 固定（5022-5040 段），且 33px 在所有宽屏宽度下恒定，iPad 竖屏（768）时 Web 为 28px、原生 33px 反而偏宽，桌面级宽度时又偏窄。建议：栏距改为按容器宽计算 clamp(28, 宽×0.032, 52)，两模式同值。

**E-W1-4** Web 栏分隔线用 --border-color（浅色 rgba(0,0,0,0.05)）。原生两模式均用 T.glassBorder（rgba 0.16，`MomentApp.swift:5033、5057` 附近 Rectangle fill），线条明显更重。建议：改用 T.borderSoft（0.05/0.10，与 Web --border-color 同值）。

**E-W1-5** Web 宽屏图片/图库 margin 8px 0、取消 36 内缩（editor.css:698-700）。原生 BlockRow 对 image/gallery 恒 `.padding(.horizontal, 36)`（`MomentApp.swift:3906、3923`），双栏下每栏再窄 72px，图片显著小于 Web。建议：columnsActive 时该内缩置 0。

**E-W1-6** Web 宽屏附件行 padding 12/14、radius 22（editor.css:726-733）。原生 AttachmentRow（`MomentApp.swift:6002` 起）恒 padding 16/20、radius 32，宽窄共用。建议：宽屏时切 12/14 + radius 22。

**E-W1-7** Web 宽屏 th/td min-width 5rem、padding 7/9（editor.css:819-822）。原生 MD 表格渲染（MdBlockView "Table"，`MomentApp.swift:5517`）为 Grid + 固定 horizontalSpacing 12，无单元格最小宽与内边距概念，窄栏内长表易挤压。建议：单元格加 minWidth 80 + padding 7/9 的宽屏分支（窄屏口径另与 Web 窄屏值对齐不在本线范围）。

**E-W1-8** Web 斜杠面板 fixed 按光标定位（editor.css:1368），宽约内容宽、max-height 320。原生斜杠面板挂在编辑页顶部 VStack（top 160、左右 16，`MomentApp.swift:4171-4179`），slashPanel 本体（4349-4397）只有 maxHeight 320、无宽度上限——宽屏下被拉成近全屏宽（1440 时约 1400px），且位置与光标所在栏无关（右栏打「/」面板仍横贯全屏顶部）。建议：宽屏时面板宽钳至约 320–360 并锚向当前编辑块所在栏的左缘；窄屏维持现行。

**E-W1-9** Web 为底部浮动底表：bottom = 安全区+14、max-width 600 居中、radius 28 玻璃面（editor.css:1278-1284）。原生为系统.sheet（detent 300，`MomentApp.swift:4607-4668`）：iPad 上呈系统居中模态卡、底色用 T.bg 而非玻璃 overlay 面，宽屏下位置/材质/宽度均由系统决定而非 600 居中底表。建议：宽屏（及全形态）改自绘底部浮层以对齐 600 居中口径，或至少在报告后续裁定中确认 sheet 形态为有意原生化。

**E-W1-10** Web.wiki-backlinks width min(100%,720px) 居中（editor.css:1413）。原生 backlinksSection（`MomentApp.swift:4930-4961`）无 maxWidth，flow 宽屏下随容器拉到 1440。建议：加 maxWidth 720 居中（单列窄屏不受影响）。

**E-W1-11** Web independent 栏：padding-top 4、padding-bottom 24、scroll-padding-block 12/24、左栏以 border-right 分隔且栏距由 grid gap 承担（栏内 16 是 padding 而非 gap 的一部分）。原生：两栏共用外层 top padding 168（页头预留，非宽屏专项）、栏底 padding 40、左栏 trailing 16 / 右栏 leading 16 与 1px Rectangle 分隔——总栏距与 Web 不同（见 E-W1-3），且左栏滚动探针只挂左栏、右栏滚动不驱动页眉紧凑态（Web 页眉紧凑由整页滚动驱动，independent 下 Web 本身亦无整页滚动，此项为 inferred 待核，不计硬差异）。

**E-W1-12** Web 双栏可跨栏拖拽（提交 = 文档序 remove+insert + 分界重写）。原生 commitDrag 在 columnsActive 时把落点钳制在来源栏内（`MomentApp.swift:3528`），0.9.0 已定「单列一步、待真机验收后议」。本线仅登记，不重复建议。

**E-W1-13** Web 宽屏 pre padding 10/12（editor.css:801-806）、blockquote 9/12（824-829）。原生 MD 预览代码块 padding 恒 10（MdBlockView "Code"），引用块走 BlockRow quote 分支的既有内边距，均无宽屏分支。量级小，建议随 E-W1-7 一并处理。

**E-W1-14** Web 侧未见设置/Diag 页的专门宽屏容器规则（panels.css 仅备份弹窗 max-width 600）；原生 SettingsView/DiagView（`MomentApp.swift:7830、1785`）为全宽 List/Form，iPad 上行宽拉满。两端均无宽屏适配，**不计原生差异**，仅备注：若后续做大屏优化，设置类页面宜加 720–800 居中上限（属增强、非 parity）。

---

## 子题 2：大屏时间流 / 首页适配

### 2.0 Web/原版宽屏首页口径（基准）

出处：Rust `styles/base.css:371-629`，与原版 `src/styles/base.css:289` 起同文（已抽查核对）。

- **触发**：`@media (min-width: 768px), (orientation: landscape) and (max-height: 560px)`——比编辑页门槛宽：**手机横屏也触发**（base.css:371）。
- **网格**：.container 变 3 列网格，gap 14，max-width 1240 居中，左右 padding 24（base.css:372-382）。
- **分组溶解**：.list-group 与中间层 display:contents，卡片直接进网格流；分组标题（section-header）横跨整行（grid-column 1/-1），字号 13/600（base.css:383-397）。
- **方卡**：所有卡 aspect-ratio 1/1、radius 26、纵向布局（base.css:404-425）；文本卡标题改多行（line-clamp 3、行高 1.35），标签字号 11、最多显示 2 个 + 「更多」，meta 字号 12、摘要 clamp 3 行（base.css:446-507）。
- **图文卡**：封面占卡上部弹性高、底部信息区固定 78px（padding 10/12），标题单行省略、标签字号 10（base.css:518-572）。
- **叠卡（折叠组）**：同组子列 >2 折叠时呈 card-expand-wrapper——主卡后两层幽灵卡（translateY 7px scale 0.94 opacity 0.68 / translateY 4px scale 0.97 opacity 0.86），方卡同尺寸（base.css:574-610）。这是用户所指「多条笔记按时间归类成卡片叠加」的出处。
- **≥1280px**：升 4 列；页眉（头像行左右内距）与搜索胶囊/面板的 right 同步收到 1240 居中轴（base.css:613-629，含一条「有意偏离原版」的 W-4 注记，属 Web 侧增强）。
- 新建卡与天气块在网格中即普通一格（随.container 网格流），无独立宽屏规则。

### 2.1 原生现状

ListView（`MomentApp.swift:7170` 起）**通篇无任何宽度感知**：无 GeometryReader、无 sizeClass、无 wide 标志（全文件 "wide" 命中仅 EditorView/EditorModel 段）。结构恒为：页眉（72 头像 + 搜索胶囊）→ 单列 List（newCardRow + 每组 groupHeader + 图片/文本子列 + 折叠展开钮）。行宽由 listRowInsets 左右 16 决定，卡片.frame(maxWidth:.infinity) 拉满（memoRow `MomentApp.swift:7547-7620`、newCardRow 7485-7545）。

### 2.2 差异项

**E-W2-1** iPad/桌面宽下原生仍是单列时间流：1366 宽时文本卡被拉至约 1330px 一行，标题单行、摘要单行（titleRow lineLimit 1、metaRow lineLimit 1），与 Web 的 3 列方卡（单卡约 390px、标题 3 行、摘要 3 行）完全两种形态。建议：ListView 引入宽屏分支——LazyVGrid 3 列（≥1280 为 4 列）、容器 maxWidth 1240 居中、gap 14、padding 24，分组标题整行横跨。

**E-W2-2** Web 方卡：aspect 1/1、radius 26（原生 glassCard 恒 radius 32）、内边距 14；标题 clamp 3（原生恒 1 行）；标签 11px 最多 2 个 + 更多（原生恒 10px、prefix(3)，`MomentApp.swift:7631`）；meta 12px 摘要 clamp 3（原生 1 行截断）。图文卡：Web 封面弹性高 + 78px 底栏、标题 13；原生图文卡封面恒 16/9 + 常规 meta 行（`MomentApp.swift:7555-7580`）。建议：宽屏方卡单独一套卡面布局（与窄屏卡面分开实现，勿改窄屏值）。

**E-W2-3** Web 折叠组在宽屏呈三层叠卡（base.css:574-610）。原生 sublist 折叠（`MomentApp.swift:7447` 段）在任何宽度下都是「首卡 + meta 行内 ▼ 展开 N 条按钮」，无叠层视觉。建议：宽屏网格中折叠组渲染为叠卡（两层偏移幽灵卡垫底），点按展开为网格内平铺；窄屏维持现行。

**E-W2-4** Web ≥1280 时页眉左右内距与搜索胶囊/面板 right 按 (100vw−1240)/2 收至与网格同轴（base.css:613-629）。原生页眉恒左右 16/20 内边距全宽排布（header `MomentApp.swift:7361` 起），宽屏下头像与搜索胶囊贴屏幕两极、与下方卡片网格（若按 E-W2-1 实现）不对轴。建议：宽屏时页眉与列表容器同取 maxWidth 1240 居中。

**E-W2-5** Web 中新建卡是网格第一格、天气块随新建卡同格呈现。原生 newCardRow 为整行玻璃卡（`MomentApp.swift:7485-7545`），宽屏改造时需随 E-W2-1 一并入格：建议新建卡占网格首格（方卡形态，天气块保留在其内右上/底部），勿留整行。

**E-W2-6** Web 首页网格在横屏低高（landscape 且 max-height 560）即触发，含 iPhone 横屏；编辑页双栏则不触发（需高 ≥600 或宽 ≥1100）。原生首页无任何横屏处理，iPhone 横屏下仍竖屏单列。建议：首页宽屏判定独立于编辑页——以「宽 ≥768 或 横屏」为准实现，勿直接复用 syncWide 式。

**E-W2-7** Web 宽屏组标题 13px/600、横跨整行、上 padding 8、下 −6（base.css:389-397）。原生 groupHeader 恒 14px（Dynamic Type 缩放）、top 24/bottom 6 的单列行（`MomentApp.swift:7535` 段）。宽屏网格实现时按 Web 值另设。

**E-W2-8** Web 宽屏方卡无左滑（鼠标/触控点按为主，删除走卡面菜单路径——此点未逐行取证，inferred）。原生宽屏若改网格，List 的 swipeActions 随之失效，需为方卡备点按删除/置顶入口（如长按菜单）。建议在 E-W2-1 设计时一并定，勿等网格落地后再补。

---

## 修复优先级建议（供主线排批）

1. **子题 2 整体**（E-W2-1/2/3/5/7）：首页大屏是「形态缺失」级差异，用户点名项（时间流分组移植 + 叠卡）在此，建议作为独立一批做宽屏网格形态。
2. **子题 1 度量层**（E-W1-1/3/5）：72ch 行宽、栏距 vw 缩放、图片去内缩——三项决定双栏正文观感，改动集中在 blockColumn/wideColumns/BlockRow。
3. **单项小修**：E-W1-4 分隔线色、E-W1-10 反向链接 720 上限、E-W1-2 标题字号、E-W1-6/7/13 块度量宽屏分支。
4. **形态裁定类**：E-W1-8 斜杠面板定位（涉及与光标锚定的整体设计）、E-W1-9 底表形态（系统 sheet vs 自绘浮层，需先裁定是否保留原生 sheet 路线）。
5. E-W1-12 跨栏拖拽、E-W1-14 设置页居中上限：已知/增强类，排后。
