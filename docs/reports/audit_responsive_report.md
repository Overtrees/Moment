# 多端/多场景 UIUX 自适应审计（Rust Web vs 原版）

方法：四份文档通读（docs/mynote-visual-language.md、docs/engineering-notes.md、README.md、CHANGELOG.md）+ 原版 src/styles/*.css 全部 @media/@supports 与场景 JS（matchMedia/visualViewport/standalone）通读 + Rust styles/*.css 与 src/*.rs 对照 + 无头多视口双边实测（探针 probe_responsive*.mjs，视口 360×740 / 393×852 / 852×393 / 768×1024 / 1024×768 / 1280×800 / 1920×1080，外加 800×500 矮横屏专项、深色+减少动态模拟）。Rust 侧服务为开测时刻的 dist（wasm md5 0d45051f59f9，QQ 封面修复版；主线在并行改 editor.rs，本报告度量以该 dist 为准）。全程只读，未改应用代码。

## 结论计数

- **响应式专属分叉：2 条**（1 中：双栏开关可见性门槛；1 低：CSS 重复规则）。
- **跨审计交叉引用：1 组**（键盘弹起/visualViewport 三项行为缺失，与滚动审计 S3/S6/S8 同源，已在修复队列）。
- **已对齐：断点体系全部 7 档实测同值**；样式层为逐字移植（base.css、tokens.css 与原版 diff 仅有 Rust 脚手架新增段；编辑器 spread/独立双栏/72ch 三大块 diff 为空）。
- **文档功能核对表：28 项**——已实现且对齐 24 项、已实现但有差异 2 项（独立双栏开关门槛、列宿主架构）、缺失 2 项（KaTeX、脚注/上下标，均属 Markdown 渲染面且已有审计在案，非响应式问题）。

总体判断：这是目前各审计维度里对齐度最高的一块——原版样式被整文件移植，断点行为经实测逐档一致；真正的缺口不在 CSS，而在两处 JS 场景行为（开关门槛的 CSS 实现方式、键盘视口监听）。

## 一、断点对照表（全部实测）

| 视口 | 列表（双边同值） | 编辑器（双边同值） | 依据 |
|---|---|---|---|
| 360×740 竖屏 | block 单列，卡 328×75 胶囊 | 单栏 bodyW 328 | base.css:289 不触发 |
| 393×852 竖屏 | block 单列，卡 361×75 | 单栏 bodyW 361 | 同上 |
| 852×393 手机横屏 | **grid 3 列**，卡 259×259（1:1） | columnCount 1（横屏覆盖） | base.css:289（landscape 且 h≤560）；editor-shell.css:226 |
| 768×1024 平板 | grid 3 列，卡 231×231，maxW 1240 | **双栏** columnCount 2，spread maxW 1440 | base.css:289；editor-shell.css:187 |
| 1024×768 | grid 3 列，卡 316×316 | 双栏，bodyW 992 | 同上 |
| 1280×800 桌面 | **grid 4 列**，卡 288×288 | 双栏，bodyW 1248 | base.css:531 |
| 1920×1080 | grid 4 列（maxW 1240 封顶，卡仍 288） | 双栏，bodyW 1408（spread 1440 封顶） | 同上 |
| 800×500 矮横屏 | grid 3 列 | columnCount 1（双边同） | editor-shell.css:226 |

代码证据：Rust base.css:289/531 与原版同行号同内容（289–537 整段 diff 为空）；Rust editor.css:590–823 = 原版 editor-shell.css:187–420（diff 为空）；独立双栏块 Rust editor.css:930–1038 = editor-shell.css:527–637（diff 为空）；900px 72ch 居中两变体（editor-shell.css:131、605）= Rust editor.css:534、1008（diff 为空）；大屏标题字号 clamp（原版 editor.css:379）= Rust editor.css:379。独立双栏实测（1280×800）：双边均为 2 列、列高 613、display grid、overflowY auto。

编辑器宽屏判定 JS：Rust editor.rs:1324 用与 CSS 完全相同的 matchMedia 查询 `(min-width: 768px) and (min-height: 600px), (min-width: 1100px)` 并监听 change，与样式同源，无漂移。

## 二、场景逐项

### 1.（中）独立双栏开关的可见性门槛与原版不一致——矮横屏误显示一个点了没反应的开关

- 原版：`.editor-column-mode-toggle` 基础规则 `display: none !important`（src/styles/editor-shell.css:443-460），仅在宽屏媒体查询 `(min-width: 768px) and (min-height: 600px), (min-width: 1100px)` 内 `display: flex !important`（editor-shell.css:527-528）——与双栏生效条件严格同门槛。
- Rust：开关是菜单行 `.twopane-row`，只在 `@media (max-width: 767px)` 时隐藏（rust/apps/web/styles/editor.css:1082），其余宽度一律显示。
- 实测（800×500，宽 800≥768、高 500<600、宽<1100）：原版开关 display **none**；Rust 开关 display **flex**，且点击后无任何效果（wide 信号为假，列数 0、正文 block）——文档明示「窄屏手机竖屏与横屏维持单栏，且不显示该开关」（visual-language.md 编辑器大屏布局节），Rust 在 768–1099 宽且高<600 的设备（横屏平板/大屏手机横屏）上违反此条。
- 其余档位双边一致（≥1100 或 ≥768&≥600 均显示；<768 均隐藏）。

### 2.（中，交叉引用）键盘弹起（visualViewport）场景行为缺失

原版有三处 visualViewport 驱动行为，Rust 编辑桥内没有任何 visualViewport 监听（rust/apps/web/src/main.rs:60 的 SAFE 探针只是读一次做诊断）：

- 标题光标跟随：原版 editor.js:1107-1116 监听 vv resize/scroll + selectionchange 驱动 scheduleTitleCaretSync，键盘弹起/视口变化时把标题光标保在胶囊内（editor.js:1028-1122）→ 滚动审计 **S6**。
- 斜杠面板跟随：原版 use-slash.js:680-691 监听 vv scroll/resize 重定位面板 → 滚动审计 **S3**（另 S2 菜单/导出面板滚动关闭亦同组）。
- 失焦回顶：原版 use-editor-dom.js:436 失焦时 `visualViewport` 存在则 scrollTo(0,0) → 滚动审计 **S8**。

此三项已在统一修复队列，本报告不重复计数，仅标注其场景归属：手机键盘弹起时 Rust 的标题坞/面板表现与原版分叉。

### 3. 深色模式——对齐（实测）

tokens.css 深色令牌块（原版 tokens.css:193）与 Rust tokens.css:193 逐字一致；玻璃 @supports 半透明升级块（tokens.css:250-263）一致。实测（393×852 colorScheme dark）：双边 --primary-bg 均为 #000000、body 背景 rgb(0,0,0)。编辑器侧原版 editor.js:596-644 的 isDarkMode 状态与背景色深色适配（自定义背景 ×0.35）已在先前批次移植（editor.rs:971-974 渲染期读 matchMedia + scheme_tick 重渲染）。

### 4. 减少动态 / 减少透明 / 无 backdrop-filter——对齐（实测+逐字）

- reduced-motion：base.css:539 全局时长压零块逐字一致；实测模拟下双边 --motion-page-transition 均为 0ms、.list-item transitionDuration 均为 1e-05s。原版 JS 侧 BackupView.js:17 / SettingsView.js:8 的「reduce 时转场时长取 0」在 Rust 由同一 CSS 变量驱动转场（.page-enter 用 var(--motion-page-transition)），等效对齐。各组件级 reduce 块（slash 行、导出项、双栏开关、骨架 spinner、启动页 dino）均在移植范围内：cards.css:110 → Rust editor.css:431；launch.css:74 的 no-preference 门 → Rust index.html 内联 splash 同门。
- reduced-transparency：base.css:232 实色回退块逐字一致。
- 不支持 backdrop-filter：base.css:212 `@supports not` 实色回退块逐字一致。

### 5. 安全区（刘海）——对齐，全程 env() 动态取值，无写死机型值

双边均以 env(safe-area-inset-*) 运行时取值：原版分布于 base.css（body padding-bottom、header padding-top、.page-title.compact top、.container padding）、tokens.css:173（--safe-bottom）、editor.js 内联（编辑器根 paddingBottom、菜单/导出面板 top 与 maxHeight 公式）。Rust 对应面：base.css 7 处、editor.css 11 处、panels.css 3 处、tokens.css 1 处，公式逐字同源——含独立双栏高度 `calc(100dvh - 187px - env(top) - env(bottom))`（187px 为原版自身的布局常量，非机型值）、菜单面板 `max-height: calc(100dvh - env(safe-area-inset-top) - 64px)`（Rust editor.css:1063 = 原版 editor.js:2796）、导出面板同理（Rust editor.css:1065 = editor.js:3178）。Rust main.rs:60 的 SAFE 探针运行时回读 env 实测值入诊断，与红线「动态适配、禁止写死」一致。用户设备标签页模式 env 恒 0 的平台事实双边同受影响，非实现差异。

### 6. standalone 与浏览器标签页——对齐（等效）

- 元信息：Rust index.html viewport（viewport-fit=cover、maximum-scale=1、user-scalable=no）、双 theme-color media、apple-mobile-web-app-capable、manifest 链接与原版 Moment.html:6-8 对齐；manifest.json display=standalone、图标、theme_color 与原版一致（start_url 原版 ./index.html、Rust ./，各自对应其入口，等效）。
- 原版 src/app/standalone.js 在 standalone 下接管站内链接点击防跳出；Rust 为单页应用、无多页站内链接，该机制不适用；笔记内外部链接以真实锚点新开（与原版渲染口径同），无等价缺口。
- body::before 顶部安全区渐变（base.css:17-45，@supports env + 深色变体）在 Rust base.css 同位置逐字存在。

### 7. hover / 触控差异——对齐（代码）

原版唯一的 hover 媒体规则 `.block:hover`（editor.css:189，仅 hover 可用设备）与 Rust editor.css:189 逐字一致；待办行 hover/active 背景（editor-shell.css:5-6）在 Rust editor.css 对应段一致；菜单按钮 hover/active（editor-shell.css 尾段）一致。待办触控区 44×44（todo 行 min-height 44 + checkbox 44px 命中区，editor-shell.css:4-7）逐字移植。无头环境无法模拟 hover 能力差异，以代码逐字为准。

### 8.（低）.editor-pad 的 430px 规则在 Rust 重复声明

Rust editor.css:1039 `@media (max-width: 430px) { .editor-pad { padding-left/right: 16px } }` 连续出现两次（内容相同，无视觉后果）。原版 430px 断点（editor-shell.css:435）只约束三面板 max-width，Rust 该部分也有（editor.css:838-845）；.editor-pad 规则属 Rust 自身脚手架，重复一条为代码卫生问题，建议随规范整改顺手删。

### 9. 列宿主架构差异（记录，非布局问题）

独立双栏下原版左右列元素本身是 contenteditable 宿主（实测 ce="true"）；Rust 列是滚动容器、可编辑性由列内逐块 contenteditable 承担（实测列 ce=null）。布局度量（列高、滚动、顺序）双边同值；编辑行为面（跨列选区、列宿主级粘贴/斜杠作用域）的差异归编辑态/斜杠审计，本报告只记录架构事实。

## 三、文档功能核对表

出处：VL=docs/mynote-visual-language.md，EN=docs/engineering-notes.md，RM=README.md，CL=CHANGELOG.md。

| # | 功能/模块 | 出处 | Rust 状态 |
|---|---|---|---|
| 1 | 手机竖屏时间线胶囊列表 | VL/CL 2.2.5 | 已实现且对齐（实测 360/393） |
| 2 | 手机横屏（h≤560）三列网格、分组标题跨满 | VL | 已实现且对齐（实测 852×393） |
| 3 | 平板 ≥768 三列、内容 maxW 1240、留白 24、gap 14 | VL | 已实现且对齐（实测） |
| 4 | 宽桌面 ≥1280 四列、不缩字提密度 | VL | 已实现且对齐（实测 1280/1920） |
| 5 | 卡片 1:1、圆角 --radius-26、无外投影分层 | VL | 已实现且对齐（实测 W=H；tokens 逐字） |
| 6 | 正文卡标题优先/限行、标签前两项+剩余数 | VL | 已实现且对齐（base.css 网格块逐字） |
| 7 | 图片卡封面填充+底部 78px 固定信息区 | VL | 已实现且对齐（同上，.img-body flex 0 0 78px） |
| 8 | 折叠分组错层卡入口（无投影叠放） | VL | 已实现且对齐（card-expand-wrapper 伪元素在逐字块内） |
| 9 | 长 URL/连续字符 overflow-wrap 内容边界 | VL/EN | 已实现且对齐 |
| 10 | 玻璃三层（overlay/content/control）+ 明暗各自表面色 | VL | 已实现且对齐（tokens 逐字+实测深色） |
| 11 | 减少透明效果 → 实色面板回退 | VL | 已实现且对齐（base.css:232 逐字） |
| 12 | 无 backdrop-filter → 实色回退 | VL/EN | 已实现且对齐（base.css:212 逐字） |
| 13 | 减少动态 → 时长近零、关闭不等待原时长 | VL/EN | 已实现且对齐（实测 0ms/1e-05s；CSS 变量等效 JS 判断） |
| 14 | 键盘焦点可见、待办触控 ≥44×44 | VL | 已实现且对齐（focus-visible 组+todo 44px 逐字） |
| 15 | 编辑器大屏双栏书页（768&600 或 1100、maxW 1440、书脊线、原子卡不拆栏、媒体卡跨栏） | VL/EN/CL 2.2.7 | 已实现且对齐（CSS 逐字+实测双栏） |
| 16 | 窄屏横屏保持单栏（<1100 且 h<600） | VL/EN | 已实现且对齐（实测 852×393、800×500 columnCount 1） |
| 17 | 独立双栏模式（更多菜单开关、双列独立编辑+滚动、布局随笔记保存、导出维持左右序） | VL/EN/CL Unreleased | 已实现但有差异：布局/滚动/保存实测对齐；开关可见性门槛分叉（本报告 §二.1）；列非 contenteditable 宿主（§二.9） |
| 18 | 窄屏不显示双栏开关 | VL | **有差异**：768–1099 宽且高<600 时 Rust 误显示且点击无效（§二.1） |
| 19 | 标题胶囊滚动自适应（横竖排切换） | RM | 已实现且对齐（标题坞三档在先前批次实测同值） |
| 20 | 长表格/代码块窄屏容器内横向滚动、不整页溢出 | EN/CL 2.2.2 | 已实现且对齐（md 预览 CSS 逐字；本轮未单独实测） |
| 21 | HTML/PDF 导出 = 当前编辑器 DOM/CSS 快照 + 共用编辑器式页眉 | VL/EN | 已实现且对齐（差距批次 V4 已按 export.js 重写导出文档并冒烟；本轮未重测） |
| 22 | Markdown 始终语义导出（不含快照） | VL/EN | 已实现且对齐 |
| 23 | 导出选择面板短屏适配（maxHeight dvh 公式） | CL 2.2.7 | 已实现且对齐（editor.css:1065 = editor.js:3178） |
| 24 | 字号切换（根字号缩放全局） | RM | 已实现且对齐（main.rs:224 = SettingsView.js:25 同口径） |
| 25 | 笔记背景色 8 色 + 顶部渐变自适应 + 深色变暗 | RM | 已实现且对齐（先前批次移植 body::before 渐变与编辑器背景系统） |
| 26 | 返回/页面转场（--motion-page-transition、列表滑入） | CL 2.0.2/VL | 已实现且对齐（.page-enter + 变量逐字） |
| 27 | KaTeX 数学公式（行内/块级、本地资源） | RM/CL 2.2.6 | **缺失**（已知待评估项，非响应式；原版实现 src/editor/editor.md.js:241-242） |
| 28 | 脚注、上标、下标渲染 | RM/CL 2.2.6 | **缺失**（斜杠/MD 审计 M7 已在案；原版 editor.md.js renderMarkdownHtml） |

不计入缺失的两项已知待定：Google Drive 云备份（用户决定待定，UI 诚实标注未连接）、天气（原版部署 key 为空、自身从不显示，双边同为无操作）。

## 四、修复优先级建议（并入统一修复队列）

1. **双栏开关可见性门槛**（中）：把 Rust editor.css:1082 的隐藏规则改为与原版同门槛——开关默认隐藏、仅在 `(min-width: 768px) and (min-height: 600px), (min-width: 1100px)` 显示；或在 editor.rs 里按已有 wide 信号条件渲染该菜单行（信号已存在，成本更低且与生效条件天然同源）。验收：800×500 菜单内无该行、1280×800 有该行且可切换。
2. **键盘/visualViewport 三项**（中）：已在队列（滚动审计 S3/S6/S8），本报告确认其场景归属，不必新开条目。
3. **.editor-pad 重复规则清理**（低）：删一条重复声明，随规范整改批次顺手处理。

探针脚本留仓库根可复跑：probe_responsive.mjs（七视口+深色/减少动态）、probe_responsive_orig.mjs（原版编辑器真实点击）、probe_responsive_twopane*.mjs（独立双栏与 800×500 开关）。自起服务（8106/8107）已关闭，未动 8096 与 dist。
