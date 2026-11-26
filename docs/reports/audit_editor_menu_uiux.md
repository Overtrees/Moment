# 审计线 A：编辑页与菜单 UIUX 全面差异排查（2026-11-26）

基准链：原版归档（`~/workspace/.scratch/moment-original-archive-2026-11-25/`）→ Rust Web 现行（`rust/apps/web/`）→ 原生 iOS（`rust/apps/ios/app/MomentApp.swift`，下称 Swift）。
范围：编辑页页眉/标题坞、••• 菜单、导出面板、背景色底表、斜杠面板、链接表单、卡片长按菜单、图文全文编辑面，及正文行面中与菜单/块操作直接相关的渲染细节。
与 `audit_native_parity.md` 的关系：该清单的 E1–E23 为功能级对齐（已落地）；本报告只报**细节度量级与形态级剩余差异**（字号/间距/圆角/图标/材质/状态/文案），不重复已关单的功能项。
定性：缺失 / 近似 / 走样 / 自创附加。证据等级：proven（源码逐行可证）/ inferred（代码可推、需真机量测确认）/ unknown（证据不足，注明缺口）。

## 汇总（33 条）

| # | 面 | 差异 | 定性 | 严重度 | 等级 |
|---|---|---|---|---|---|
| A1 | •••菜单/导出/斜杠/卡菜单 | 面板材质用错档：原生统一 GlassCard（content 档），Web 四浮层均用 overlay 档 | 走样 | 中 | proven |
| A2 | ••• 菜单 | 多「删除备忘」项 + 两条 Divider；Web 六项无删除、无分隔线 | 自创附加 | 中 | proven |
| A3 | ••• 菜单 | 撤销/重做副文案与 i18n 不符（缺「快捷键→」、分隔符不同） | 走样 | 低 | proven |
| A4 | ••• 菜单 | 禁用态 opacity 0.45 且按钮仍可点；Web 0.3 + disabled | 近似 | 低 | proven |
| A5 | ••• 菜单 | 行图标 SF 字形 17pt；Web SVG 20px（24 槽） | 近似 | 低 | proven |
| A6 | ••• 菜单/导出 | 按下高亮圆角 12；Web 菜单行 17、导出行 17（panels 覆盖 14） | 近似 | 低 | proven |
| A7 | 双栏开关行 | 系统 Toggle（51×31）+ 行高 50；Web 自绘轨道 42×26 + 行高 56 | 走样 | 中 | proven |
| B1 | 导出面板 | 返回钮 30×30 平钮；Web 46×46 玻璃控制圆钮 | 走样 | 中 | proven |
| B2 | 导出面板 | 标题左对齐、无头部下边线；Web 标题居中 + 0.5px 下边线 | 走样 | 低 | proven |
| B3 | 导出面板 | 格式徽章 30×30/r8/玻璃控制底；Web 34×34 透明无底（base 规则为 40/r12/accent-10 底） | 走样 | 中 | proven |
| B4 | 导出面板 | 行高 50、label 15；Web 行高 56（panels 覆盖 54）、label 14/650 | 近似 | 低 | proven |
| B5 | 导出面板 | 尾注 11px 无顶边线、文案自撰；Web 10px + 顶边线、文案走 i18n | 走样 | 低 | proven |
| C1 | 背景色底表 | 系统 .sheet 定高 300 + 实色页底；Web/原版为浮动玻璃底表（max 600、radius 28、底距 safe+14、左右 14） | 走样 | 中 | proven |
| C2 | 背景色底表 | 标题左对齐 17 semibold、副文 12 次级色；原版居中 20/700、副文 13 主色 70% | 走样 | 中 | proven |
| C3 | 背景色底表 | 文案三处与 i18n 不符（底色/移除/恢复文案） | 走样 | 低 | proven |
| C4 | 背景色底表 | 选中色点只有对勾、无 2px accent 环；原版环 + 对勾并存 | 缺失 | 中 | proven |
| C5 | 背景色底表 | 色点网格间距 14；原版 12 | 近似 | 低 | proven |
| D1 | 斜杠面板 | 定位满宽挂页眉下（top 160）；Web 锚定触发块、动态宽 220–360、放不下上翻 | 走样 | 中 | proven |
| D2 | 斜杠面板 | 圆角 20 + 无面板内距；Web 圆角 22 + padding 8 | 近似 | 低 | proven |
| D3 | 斜杠面板 | 行图标主文字色、字形 15pt；Web 图标 accent 色、SVG 20px | 走样 | 低 | proven |
| D4 | 斜杠面板 | 副标题 11；Web 12 | 近似 | 低 | proven |
| D5 | 斜杠面板 | 快捷键纯文本无底；Web 为 fill-hover 胶囊（r6、padding 3/6、mono 11） | 走样 | 低 | proven |
| D6 | 斜杠面板 | 最近使用未从基础/媒体组去重（同命令出现两次）；Web 分组排除已入最近组者 | 走样 | 中 | proven |
| D7 | 斜杠面板 | 查询态无命中高亮、无首行选中底；Web 有 .slash-match 高亮 + 首行 .sel 底 | 缺失 | 低 | proven |
| D8 | 斜杠面板 | 空态左对齐双行自撰文案；Web 居中 28px 搜索图标 + i18n 文案 + kbd 拼音提示行 | 走样 | 低 | proven |
| D9 | 斜杠面板 | 行无按下态（.plain）；Web :active scale 0.99 + fill-hover-strong | 缺失 | 低 | proven |
| E1 | 链接表单 | 系统 .alert 形态；Web 为斜杠面板内嵌表单（标题/输入框/双胶囊钮） | 走样 | 高 | proven |
| E2 | 链接表单 | 无效 URL 静默关窗、无行内错误；且 alert 常显「请输入有效的…」冒充说明。Web 校验失败留窗 + 红字错误行 | 缺失 | 高 | proven |
| E3 | 链接表单 | 无 `https://` 预填与聚焦全选；Web 预填并 select | 缺失 | 低 | proven |
| F1 | 卡片长按菜单 | 系统 contextMenu 形态；Web 为贴卡 216px 玻璃浮层（锚卡下/上翻、带阴影） | 走样 | 中 | proven |
| F2 | 卡片长按菜单 | image/gallery 无「编辑」项 → 已有图片块无任何换图路径；Web 编辑进卡编辑态（accent 描边、点图换图） | 缺失 | 高 | proven |
| F3 | 卡片长按菜单 | link-card 多「编辑」项；Web 卡菜单对 link-card 只有删除 | 自创附加 | 低 | proven |
| F4 | 卡片长按菜单 | 文本块多出类型转换菜单（正文/标题 1–3/待办/引用/提示）；Web 无此菜单（转换走斜杠/MD） | 自创附加 | 中 | proven |
| F5 | 块手势 | contextMenu 与长按拖拽拾起（0.48s）同挂一行，唤起竞争 | 近似 | 中 | inferred |
| G1 | 页眉 | 返回/更多钮图标 accent 蓝；Web .editor-fab 无色声明、图标为主文字色 | 走样 | 中 | proven |
| G2 | 标题坞紧凑态 | 原生自创 32 头像 + 46 高小胶囊；Web 紧凑态仅横排 + 隐藏 meta，头像 72、胶囊 66 不变 | 走样 | 中 | proven |
| G3 | 标题坞 | 标题缺 letter-spacing −0.2 | 近似 | 低 | proven |
| G4 | 标题坞 | 原版标题 >5 字降字号 11px；Web 已改判恒 14px、原生随 Web。此为原版→Web 分叉，是否有意未见登记 | 走样 | 低 | unknown |
| H1 | 引用块 | 缺四边 1px 边框、文字非 muted 色；Web .blk-quote 有边框 + --md-text-muted | 走样 | 中 | proven |
| H2 | embedCard 块 | 原生落 fallback 占位「embedCard 块 · 后续轮支持」（开发文案外露）；Web 有完整渲染 | 缺失 | 高 | proven |
| H3 | 代码块 | 字号 13.5 vs Web 13；缺 1px 边框 | 近似 | 低 | proven |
| H4 | 分隔线 | 系统 Divider 直线；Web 为渐变线（两端透明） | 近似 | 低 | proven |
| H5 | 图文全文编辑面 | 系统导航 sheet（TextEditor + 工具栏）；Web 为浮动底表 ImageTextSheet（max 600/r28/p20、16px 编辑器、104×44 动作钮） | 走样 | 中 | proven |
| H6 | 添加附件 | 原生多一步 confirmationDialog（图片/文件二选）；Web 菜单项直达文件选择 | 近似 | 低 | inferred |
| H7 | 正文底部 | addBar 为原生自创添加条（文/图/附件三钮玻璃胶囊）；Web 编辑页无此件 | 自创附加 | 低 | proven |
| H8 | 待办/段落间距 | 勾选钮 −22 trailing 偏移 hack、段落/标题间距与 Web margin 口径的像素差 | 近似 | 低 | inferred |

## 分面详述

### 1. 浮层材质（A1）——系统性根因

- Web 真值：菜单/导出/斜杠/卡菜单四浮层统一 `background: var(--glass-overlay-bg)` + `border: 0.5px solid var(--glass-overlay-border)`（editor.css:1230、1368、1342）。tokens.css:44–45 浅色 overlay-bg = #FFFFFF（实色）、border = rgba(0,0,0,0.18)；dark（:241）= #1C1C1E / rgba(255,255,255,0.2)；玻璃变体段（:271、277）= rgba(255,255,255,0.84) / rgba(28,28,30,0.94)。卡菜单另带 `box-shadow: var(--glass-overlay-shadow)`（editor.css:1342）。
- 原生：四浮层统一走 `GlassCard`/`glassCard`（MomentApp.swift:6388）= ultraThinMaterial + `T.glassTint`（content 档：白 0.74 / 深 #202024 0.86）+ `T.glassBorder`（0.16）。
- 差异：浅色下原生面板半透灰、透出正文，Web 为实白；深色下原生底色 #202024 vs Web #1C1C1E；边框透明度 0.16 vs 0.18/0.20；原生全无阴影，浮层与正文分层感弱。
- 建议：令牌层新增 overlay 档（bg/border 双写 + 阴影），菜单/导出/斜杠/卡菜单/底表五浮层统一改用；GlassCard 保留给内容卡。口径依据：tokens.css overlay 与 content 是两个既有变量，用户样式规矩「优先复用已有变量」。

### 2. ••• 菜单（A2–A7）

- 项集：Web 六项（双栏开关/撤销/重做/添加附件/导出笔记/更换背景色），render.rs 菜单段 + i18n menu.*（zh-CN.json:141–152）；原版同六项（editor.js:2788 面板宽 246 内联样式）。原生 menuPanel（Swift:4680–4750）在六项外加「删除备忘」（trash，danger）并在双栏行后、删除行前各插一条 Divider（Swift:4696、4740）。Web 菜单内无任何分隔线（.menu-inner 仅 padding 7，editor.css:1240）。
- 副文案：i18n `menu.undo_sub` = 「快捷键→ Cmd+Z / 三指左滑」、`menu.redo_sub` = 「快捷键→ Cmd+Shift+Z / 三指右滑」（zh-CN.json:148、152）；原生硬编码「Cmd+Z · 三指左滑」「Cmd+Shift+Z · 三指右滑」（Swift:4702、4710）。
- 禁用态：Web `.menu-item.dis { opacity: 0.3; cursor: default }`（editor.css:1245）；原生 dimmed = opacity 0.45（Swift:4880），且 Button 未 `.disabled()`，点按仍触发（undo/redo 内部 no-op，用户无反馈差异但形态不符）。
- 图标：Web `.menu-icon` 槽 24、SVG 20px、色 accent（editor.css:1247–1248；tokens.css:180–182）；原生 SF 符号 `.font(.system(size: 17))` 置 24 槽（Swift:4868）——字形视觉约小 3px。
- 按下态：Web .menu-item 圆角 17、:active 背景 fill-hover-strong（editor.css:1241、1244）；原生 RowPressStyle 默认 radius 12（Swift:6441）。
- 双栏开关行：Web `.editor-column-mode-toggle` min-height 56、radius 17（editor.css:896 起），开关为自绘轨道 `.editor-column-toggle-track` 42×26 + knob 位移（editor.css:943–965，Diag 页注释亦引「视觉沿用编辑器开关轨道（42x26）」）；原生 twoPaneRow（Swift:5085–5113）行高 50 + 系统 Toggle（51×31，tint accent）。

### 3. 导出面板（B1–B5）

- Web：`.export-head` min-height 46、padding 0 4 5、下边线 0.5（editor.css:1257）；返回钮 `.export-back` 46×46 圆形玻璃控制钮（editor.css:1258）；标题 `.export-title` 15/650 居中（padding-right 46 补偿，editor.css:1259）；选项行 min-height 56、radius 17、padding 8/10（editor.css:1261），panels.css:238–239 覆盖为 min-height 54、padding 6/9、radius 14；徽章 base 为 40×40、radius 12、fill-accent-10 底、mono 12/700（editor.css:1264），panels.css:240 覆盖为 34×34、透明无底、字号 11（.sm 为 9）；label 14/650、detail 11（panels.css:243–244）；chevron 19px placeholder-strong（panels.css:245）；尾注 10px、顶边线、margin 5/4/2（panels.css:246），文案 i18n `export.pdf_note`（zh-CN.json:79）。
- 原生 exportPanel + exportChoice（Swift:4753–4845）：返回钮 30×30 无底平钮；标题左对齐 15 semibold、无下边线；徽章 30×30、radius 8、glassControlTint 底、字号 12（PDF 为 10）；行 minHeight 50、label 15 semibold；尾注 11px 无边线、文案自撰「PDF 将生成文件，可通过分享存储或打印。」（与 i18n 文案不同——Web 文案为浏览器打印口径，iOS 不适用，文案改写本身可议，但未在 parity 清单登记，标走样待裁定）。

### 4. 背景色底表（C1–C5）

- 原版真值（BgSheet.js 全文）：浮动层 bottom = safe+14、左右 padding 14、面板 max-width 600、glass-overlay、radius 28、padding 20（+safe 底）；标题居中 20/700 letter-spacing −0.3、副文 13 主色 opacity 0.7 margin-top 4；网格 4 列 gap 12、margin-bottom 16；色点 44×44 radius 22、边 0.5 black-12，选中 = 2px accent 边 **且**内含 20px accent 对勾 SVG；移除行仅 currentColor 非空时出现，文案「移除背景」15/650 + 注「（恢复默认背景）」11 次级，居中列式、顶部 0.5 边线；出场 opacity 200ms + translateY(20) 250ms 弹簧。Rust Web sheets.rs/editor.css:1271–1290 与此一致；i18n bg.* 在 zh-CN.json:32–43（标题「背景色」、副文「为当前笔记设置底色」、移除「移除背景」、注「（恢复默认背景）」）。
- 原生 bgSheet（Swift:4607–4678）：系统 `.sheet` + `presentationDetents([.height(300)])`、背景 `T.bg`（页面实色）；标题左对齐 17 semibold、副文 12 textSecondary；网格 spacing 14；色点 Circle 44、边 glassBorder 0.5，选中仅 17pt accent 对勾、**无 accent 环**；移除行左对齐 HStack、文案「移除背景色」15 + 「恢复为默认底色」11、色 T.danger（Web 为 --color-danger-bright）。
- 文案三处：副文「为当前笔记设置专属底色」（实为 menu.bg_sub 的文案串用）、「移除背景色」、「恢复为默认底色」均与 i18n 不符。

### 5. 斜杠面板（D1–D10）

- Web：面板锚定触发块（render.rs:640–667 按行宽算 220–360 宽、贴块下 10px、放不下上翻、max-height min(320, 视口余量)）；壳 glass-overlay、radius 22、padding 8、进场 slashIn 140ms（editor.css:1368、tokens.css:203）。行：min-height 48、padding 7/9、radius 14、gap 10（editor.css:1370）；图标槽 24、SVG 20、色 = --editor-menu-icon-color = accent（tokens.css:181–182）；标题 14/650、副标题 12（editor-shell.css:91–93，与原版同值）；快捷键胶囊 fill-hover 底、radius 6、padding 3/6、mono 11（editor-shell.css:96）；最近行标题旁带「最近」胶囊（render.rs:898–900）；分组规则：最近组置顶且**基础/媒体组排除已入最近组者**（render.rs:745–758 注释与实现）；查询态标题/副标题走 SlashHl 命中高亮（render.rs:896、903；.slash-match accent-18 底）；首行 .sel 底 fill-hover（editor.css:1371）；行 :active scale 0.99 + fill-hover-strong（editor.css:506）；空态居中：28px 搜索 SVG（opacity .45）+ `slash.no_match` + kbd 提示行（render.rs:911–940；.slash-empty-state editor.css:535–539）。分组头：11/700、uppercase、letter-spacing .035em、opacity .8、非首组带顶边线（editor-shell.css:94–95）。
- 原生 slashPanel/slashRow/slashGroupHeader（Swift:4349–4441）：面板挂页眉下 top 160、左右 16 满宽、glassCard radius 20、无面板内距、maxHeight 320；行 padding 14/7、图标 SF 15pt 主文字色 24 槽、标题 14 semibold、副标题 11、快捷键纯 mono 文本无底；空查询时最近组与基础/媒体全组并列（**未去重**，Swift:4360–4375）；空态为左对齐两行自撰文案（「未找到匹配命令」14 semibold + 「试试拼音首字母：标题 / 图片 / 音乐」12）；行 ButtonStyle 为 .plain 无按下态；分组头 11 semibold、无边线、padding 14/10/2。
- 链接表单（E1–E3）：Web 表单在面板内原地替换列表（render.rs:669–745）：标题 14/650、输入框 min-height 44、radius 10、fill-subtle 底、预填 `https://` 并聚焦全选、错误行 12px danger（仅校验失败后出现）、动作行右对齐双胶囊钮（min 76×44，取消 fill-hover、提交 accent 底白字）（editor.css:531–545 对应 .slash-link-*）。原生为系统 .alert（Swift:4235–4253）：TextField 占位「https://…」无预填；message 常显「请输入有效的 http 或 https 链接」（此为 Web 的**错误**文案，被用作常驻说明）；applyLink（Swift:3161–3177）对非 http(s) 直接 return，alert 已关闭、无任何错误反馈。

### 6. 卡片长按菜单（F1–F6）

- Web：长按/右键原子卡出 `.card-menu-panel` 贴卡浮层：宽 216、glass-overlay、radius 22、带阴影，定位锚卡下 8px、放不下上翻、横向 12 钳制（layers.rs:104–140；editor.css:1342）；行与 ••• 菜单同 .menu-item 度量；项集 = 「编辑」（仅 imgTextCard/imageTextRow/image/gallery/musicCard 有）+「删除此块」（danger）（layers.rs:126–128、157+）。点「编辑」进卡编辑态：`.blk-wrap.card-editing` 2px accent 描边 offset 3（图文卡 radius 22、余 32，editor.css:1330–1340），编辑态点图区 = 换图、点文区 = 编辑。文本块无长按菜单（长按为拖拽拾起）。
- 原生 BlockRow（Swift:4047–4112）：全块统一系统 `.contextMenu`（系统形态、系统定位与预览行为）；imgText 有「编辑」✓；musicCard/link-card 有「编辑」（URL 编辑 alert——其中 link-card 在 Web 卡菜单中**没有**编辑项）；image/gallery **无「编辑」项**，非空图点按进图片页、空图点按才换图 → 已有图片/图库无换图路径，卡编辑态整缺失；文本块另有自创类型转换菜单 7 项（正文/标题 1/标题 2/标题 3/待办/引用/提示）+ 删除块，Web 无此菜单（parity 清单曾记「块类型 contextMenu」为原生更优可留——但那是斜杠落地前的替代，斜杠已于 0.8.2 落地，此留置理由已失效，建议重新裁定）。
- 手势竞争（F5，inferred）：同一行同时挂 `.contextMenu` 与 `LongPressGesture(0.48).sequenced(DragGesture)`（Swift:4029、4108–4133），系统菜单唤起与拖拽拾起同为长按触发，实际胜出方与是否互相吞噬需真机验证；Web 口径为卡→菜单、块→拾起的显式分工，无此竞争。

### 7. 页眉与标题坞（G1–G4）

- 页眉钮：Web `.editor-fab` 46×46 玻璃控制圆钮、无 color 声明（editor.css:209–224），图标 stroke currentColor = 主文字色；原版同（editor.js 页眉钮 SVG 无 accent 着色）。原生返回/更多钮图标为 T.accent 蓝（Swift:4453、4500）。
- 紧凑态：Web `.editor-title-dock.scrolled` 仅 flex-direction 改 row、gap 8、meta 隐藏（editor.css:1194、1220），头像钮恒 72、胶囊恒高 66，无缩小规则；原版 editor.js:2512 起同口径（editorScrolled 只切 flexDirection/gap）。原生紧凑态（Swift:4464–4480）为自创：头像 32 + 高 46 胶囊 + 标题 14。
- 胶囊本体：高 66、min 宽 66、radius 33、padding 0 20、gap 3、宽 transition 0.2s（editor.css:1198）——原生 titleCapsule（Swift:4555–4581）逐值一致 ✓；仅标题 input 缺 letter-spacing −0.2（editor.css:1204）。
- G4（unknown）：原版 editor.js:2507 `capsuleFontSize = styleIsLong ? 11 : 14`（标题 >5 字降至 11px）；Rust Web 标题 input 注释明示「字号两态恒 14px」（editor.css:1200–1204），原生随 Web 恒 14。原版→Web 此分叉未见裁定登记，缺证据判是否有意改判。

### 8. 正文行面相关（H1–H8）

- 引用：Web `.blk-quote` padding 10/14、左 3px 竖条 + 四边 1px border-color、radius 10、字号 14、色 --md-text-muted（editor.css:1314）。原生 quote（Swift:3989–3995 + 行 padding 4030–4037）只有 3px 竖条 + quoteBg 淡底，无边框，正文色走 BlockTextView 主色。
- embedCard：Web 有完整卡渲染（cards.rs，E19 解析链同域）；原生 BlockRow 无 embedCard 分支，落尾部 fallback（Swift:4014–4022）显示 SF 图标 + 「embedCard 块 · 后续轮支持」subheadline——开发占位文案直接外露给用户。
- 代码块：Web `.blk-code` 字号 13、padding 12/14、radius 12、1px 边框（editor.css:1315）；原生 baseFont codeBlock 13.5、行 padding 14/12、radius 12、无边框。
- 分隔线：Web `.blk-hr` 为 linear-gradient 横线（中实两端透明）、margin 1em（editor.css:1316）；原生系统 Divider + 纵 padding 8（Swift:3922）。
- 图文全文编辑：Web ImageTextSheet 为浮动底表（editor.css:551–560）：max-width 600、radius 28、padding 20、头居中、内容 16px、编辑器 min-height 160/radius 12/fill-subtle、页脚动作钮 min 104×44 accent-10 底。原生 ImgTextBlockView 编辑面为 NavigationStack 系统 sheet + TextEditor（默认字号）+ 工具栏取消/保存（Swift:6129 起）。
- 添加附件（H6，inferred）：Web 菜单「添加附件」点击直达文件选择（dispatch.rs attach 分支触发隐藏 input）；原生先弹 confirmationDialog 二选（图片 → PHPicker / 文件 → fileImporter）（Swift:4312–4321），多一步且图片被限定为相册来源（Web 文件选择可取任意图片文件）。
- addBar（H7）：原生正文底部常驻添加条（文本/图片/附件三钮、52×40、玻璃胶囊，Swift:5115–5145）；Web 编辑页无对应件（加块走回车/斜杠）。属自创附加，未在 parity 清单登记。
- H8（inferred）：待办勾选钮以 `.padding(.trailing, -22)` 负边距拼凑文本偏移（Swift:3905），与 Web .todo-row（gap 10、padding 4/8、勾选 44 命中/22 视觉，editor.css:1319–1323）的像素对齐需真机量测；段落 margin-bottom 0.65em、标题 margin 1.25em/0.4em（editor.css:1310–1313）与原生行间 padding 3 + 标题顶 padding 14/10/8（Swift:4030–4046）的累积间距差同需量测。

## 修复建议总序（按口径依据）

1. 先令牌后形态：新增 overlay 玻璃档（一处定义、五浮层共用）——A1 是其余面板差异的共同根因。
2. 功能性缺失优先：F2（image/gallery 换图路径）、H2（embedCard 渲染）、E2（链接表单错误态）。
3. 形态照抄批：C1/C2/C4（BgSheet 浮动底表化）、B1/B3（导出钮与徽章）、D1（斜杠锚定定位）、G2（紧凑态回 Web 形态）、A7（自绘开关轨道）。
4. 文案回 i18n：A3、C3、B5（B5 的 PDF 尾注需先裁定 iOS 版文案再入包）。
5. 待裁定项：A2 删除项去留、F4 类型转换菜单去留（斜杠已落地、原留置理由失效）、H7 addBar 去留、G4 原版长标题降字号是否恢复。
6. 需真机量测后定：F5 手势竞争、H8 间距/偏移、A4 点按反馈。
