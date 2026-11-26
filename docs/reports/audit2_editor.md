# 全面排查第二轮 · 编辑器线审计（只审计，未改代码）

- 基线：HEAD 17d3c79；原生 `rust/apps/ios/app/MomentApp.swift` 13773 行；Web 真源 = 现行 `rust/apps/web`（styles/editor.css、styles/tokens.css、src/blocks.rs、src/editor/render.rs、src/editor/js/editor.js、src/editor/hooks/）。
- 方法：先读原版弄清意图再对照原生；前轮三报告（blocks 55 项 / layers 80 项 / motion M1–M32）与批 B（0.9.33/0.9.35）、批 D（0.9.37）已修项不重报，只查回潮、未覆盖面与合成误差。
- 判定口径：已对齐 / 等价更优保留 / 待修（感知级 = 正常使用可直接感知；小/微 = 数值差或边缘场景）。

## 总判

- **回潮：有一处未修满**——0.9.35 的 MD #46 标题前距只修到约 2/3（见 §1.3）；#52 列表缩进残差未随该批修。批 B 其余抽查项、批 D 四项、动效批抽查项全部仍在位，无真回潮。
- **待修感知级 10 项**（§2），最严重三项：跨块方向键导航整体缺失、落焦热区仅 220pt 致短篇大面积死区、MD 预览公式双缺（行内公式渲成代码、块级公式不可横滚）。
- 微差成簇未收两处：浮层线前轮 31 项（图标字形系统性偏小、纵向小距两簇）、MD 线新查微差一组——按既定口径（微差整批搁置）只登记，不逐项催修。

---

## 1 回潮核查（已修项是否仍在位）

### 1.1 批 B（0.9.33）编辑态块几何抽查 —— 全部在位

| 项 | 现行证据 |
|---|---|
| #1 段间净留白 ≈10 | 栏 spacing 6 + 文本行 padding 0 + UITextView inset 2（BlockRow/BlockTextView 现行值） |
| #10 行内链接色 | linkTextAttributes #005BBB/#72B7FF（Swift:1576） |
| #13 待办文起点 62 | 行左 pad 8 + 圈域 44 + gap 10，行 pad H8、.center 对齐 |
| #23/#24 代码块 | 13/1.6；T.codeBg 实色 #F4F4F5/#2C2C2E（Swift:9941） |
| #31/#32 图片块 | 圆角 22、自然宽居中不放大、限高 668 contain（Swift:2171-2189） |
| #33/#34 Gallery | 瓦高 366、两列 gap 4、空瓦双占位（Swift:8341-8429） |
| #37 音乐播放字形 17 | CardBlockView 内 font 17（Swift:9429） |
| #43 图文卡占位底 | T.fillSubtle（Swift:9745）；行形态残差见 §3.5 |

标题字重.heavy≈750、H4 17、H1 行高 1.2、kern −0.02em、分割线渐变、Callout/引用/H1 边线度量、列表标记与嵌套缩进（编辑态）、拖拽全套（删 require、拾起锁滚动、LiftFrame、liftScale、dragShift、settle、触觉、reduceMotion 降级）均复核在位。

### 1.2 批 D（0.9.37）浮层四项 —— 在位（两处残项）

| 项 | 现行证据 | 残项 |
|---|---|---|
| #52 斜杠面板实测高定位 | slashLayer 7133-7185：实测回写 + 锚底 +10 + 实测高上翻 + 动态限高 min(320,…)；verify_ios.sh:78 有防回潮断言 | 无 |
| #25 菜单限高滚动 | menuPanel 7794-7855：ScrollView + maxHeight = viewH−67 | 无 |
| #22 双栏行高 56 | twoPaneRow 8286-8315：minHeight 56、pad H10 | 纵向 padding 8 仍无（靠 minHeight 主导，同普通菜单项形态） |
| #23 双栏行标题 14 | 标题 14 semibold、副 11（8294-8300） | 图标仍 font 17（8290），Web SVG 20，−3 |

### 1.3 0.9.35 MD 预览组（#46–#55）—— 主体在位，#46 前距未修满、#52 残差

| # | 判定 | 证据 |
|---|---|---|
| 46a 段间 10.4 | 在位 | MdPreviewView spacing 10（Swift:9134） |
| **46b 标题前距** | **未修满** | Web 边距折叠后净距 h1 35 / h2 28.75 / h3 25 / h4 21.25（editor.css:87-97）；原生 spacing 10 + headingExtraTop 15/11/9/7（9123-9132）= 实距 25/21/19/17，**−10 / −7.75 / −6 / −4.25**。附带：pre/quote/callout/table 前距 Web 12–12.8 vs 统一 10（−2~−2.8）；列表前距 Web 6.4 vs 10（+3.6） |
| 47 标题梯/字重/h1 边线 | 在位 | 28/23/20/17（8699-8703）；字重.heavy≈800 近似 750（SF 无 750 档，登记保留）；h1 边线 1px T.borderSoft + 距 7 |
| 48 代码块 | 在位 | pad 12/14、radius 12、1px 边、codeBg 逐值同、13 mono、lineSpacing 7.8（8733-8755） |
| 49/50 引用字号与几何 | 在位 | baseSize 14 递归；leading 17、三边 1px、pad 10/14、radius 10、左条 3px |
| 51 Callout 度量 | 在位 | pad 12/14、图标 18、标题 15、gap 8、正文距 5、radius 12（8931-9012）；底色实色近似为 #22 已定案 |
| **52 列表缩进** | **残差** | 色/字号/项距已修；文起点 = 标记列 18+8 = 26 vs Web ul 19.2 / ol 22.4，**+6.8 / +3.6**（8789-8840）；嵌套每层同差递增（§3.4） |
| 53 表格 th/td | 在位 | th 12 semibold #626267、td 16、cell 纵 9、行线 1px（8840-8895）；外框/横滚见 §3.4 |
| 54 脚注区 | 在位 | 13 次级、上边线 1px、总距 ≈20、项距 3（8896-8940）；回链见 §3.4 |
| 55 分割线 | 在位 | 渐变 1px、合成总距 32 = Web 16+16（8672-8681） |

### 1.4 动效批抽查 —— 在位

M5 标题胶囊布局动画、M13 菜单进出场、M18–M22 拖拽呈现整套、M24 bgSheet 220ms 出场编排、M27/M28 列表折叠均在现行代码可证。M1/M2 系统转场为 2026-11-26 裁定改判保留，不报。

---

## 2 待修 · 感知级（10 项）

### E1 跨块方向键导航整体缺失
- Web：editor.js:241-302 `crossBlockArrow` +:776 目标列会话 +:830/:866 左右键块界跨越——首/末视觉行 ↑/↓ 保持目标列跨到相邻文本块（钳行尾），块首/尾 ←/→ 跨块；probe_bridge_input B-12 即测此机制，Web 已 proven。
- 原生：全文无 keyCommands/方向键处理，EditorTextView 仅 pressesBegan/Ended 跟踪 Shift（Swift:1548-1565）；每块独立 UITextView，块首行 ↑、块尾行 ↓、块首 ←、块尾 → 皆为死键。iPad 已放开（0.9.0），硬件键盘场景直接可感。

### E2 落焦热区仅 220pt，短篇大面积死区
- Web/定规：落焦受理 = 标题胶囊坞下缘以下全屏（.editor-body +.detail 背景区，含反链区背景），editor.js:1240-1340 canvasTap 路由（pointerup 位移 ≤10px、手势内同步落焦、触摸兼容回声整串抑制、跨块选区守卫）；.detail min-height 100dvh、底距 46vh，整屏无死区，落点 X 解析栏、内容下方落末段末尾。
- 原生：focusHotZone = 内容后固定 220 高的 Color.clear（Swift:8129-8143，注释自称「header 以下整页」而实现为定高条），底 padding 40。短篇在高屏机上热区以下数百 pt 点按无响应（15 Pro 852pt 屏、3 行短篇死区约 350pt 量级）；且落点恒为末个文本块末尾，不按点位/栏解析（双栏点短栏空白亦跳文档尾）。

### E3 反向链接区形态整组未对齐
- Web（editor.css:376-382）：宽 min(720,100%) 居中、margin-top 24、border-top 1px --border-color、padding-top 14；标题 12/650 次级、距 6；列表 gap 2；行透明底、min-height 44、padding 6/8、radius 10、hover fill-hover、行首「↗」次级字形、文字 --md-link-color。
- 原生（Swift:8146-8188）：padding-top 8、无顶边线、无 24 上距；标题「反向链接」13 semibold；行 = glassCard 浮层卡（radius 14、padding 12/9、行高 ≈35 < 44、行距 8）、SF link 图标 12 accent、文字 14 textMain。整区形态语言不同（卡片化 vs 文本列表）。

### E4 斜杠过滤行为四缺：排序、高亮、选中态、键盘导航
- Web：render.rs:775-808 query 命中重排（标题/kw 前缀或 py 前缀优先 → 其余按标题 localeCompare zh-Hans-CN），hay = 本地化 title+sub+kw+ty+py；标题/副内查询串高亮（SlashHl）；首行 sel 选中态；editor.js:776-790 硬件键盘 ↑↓ 移选 + Enter 执行。空查询构成（最近置顶 6、组内剔除）两侧一致。
- 原生：SlashCmds.filtered（Swift:3662-3670）仅 contains 保持表序（字段 title+sub+kw+act+py）；slashRow（7332-7382）无选中态、无高亮；全文无键盘导航。触摸点选本身一致。

### E5 行内公式未渲染
- Web：MathSpan 以 MathML 渲染，失败回退红色原码（blocks.rs:1597-1625；editor.css:326-330）。
- 原生：MdRender "Math" 分支只 push tex + code:true（Swift:8558-8561）→ 呈行内代码样（mono 0.85em + 代码底），无 MathML、无失败红态、display 公式不独立成块。

### E6 块级公式不可横滚
- Web：.math-block margin 0.75em 0、padding 2px 0、overflow-x auto 居中；失败原码色 #CC0000（editor.css:326-330）。
- 原生：MdMathView + MathWebView（Swift:9024-9108）：WKWebView 滚动禁用（isScrollEnabled=false）、body 17px、高 = scrollHeight+4、无独立 margin（靠预览 spacing 10）；长公式被截不可达。失败态色 T.danger #E0433A vs #CC0000（微差附带）。

### E7 高亮标记 == 字面露出
- Web：span.moment-highlight 只渲正文、字重 600、底 --fill-highlight、padding 0 0.28em、radius 4（blocks.rs:1470；editor.css:374）。
- 原生：MdRender Highlight push 字面 "=="+v+"=="（Swift:8512-8513），applyHighlightTint 只加底 rgba(255,204,0,0.25)（1362-1388）→ 预览中 == 符号可见、无 600 字重。

### E8 MD 预览内图片无圆角且填充裁切
- Web：img max-width 100%、height auto（自然比例）、radius 10、margin 0.4em 0（editor.css:128-129）。
- 原生：MdSegsView 图片段走 ItemImageView（Swift:8592-8598 → 2106-2132）：resizable + scaledToFill + clipped、无 cornerRadius、不保自然比例。组间 spacing 6 ≈ 0.4em ✓。

### E9 MD 容器内标题行高/字距按宿主段落计算
- Web：MD 标题行高 h1 1.2 / 余 1.28、字距 −0.02em（editor.css:87-97）。
- 原生：MdRender.attributed 经 Marks.withRhythm 按**宿主块** type 计算（Swift:8553-8559 → 1327-1352）：宿主恒 paragraph → 全部子块 lineHeightMultiple 1.75、kern 只对 heading 宿主生效（预览恒不触发）。多行标题行高 +0.47~0.55。附带微差：引用正文行高 1.75 vs 1.6、文字色 textMain vs --md-text-muted #626267；Callout 正文 1.75 vs 1.65。

### E10 图文「全文」底表改为保存提交制
- Web（layers.rs:901-1040；editor.css:548-557）：底部浮层 max-width 600、radius 28、pad 20，阅读态⇄编辑态同表切换，textarea 逐键写回落盘、无保存钮。
- 原生（Swift:9832-9858）：系统.sheet + NavigationStack，标题「图文文本」，TextEditor pad 12，「取消/保存」——点保存才写回，无阅读态。系统 sheet 形态可议等价，但生效时点（逐键 vs 提交）为行为差。

---

## 3 待修 · 小/微（成组登记）

### 3.1 纵向节奏合成误差（编辑态）
- quote/callout/codeBlock 相邻间隙 ≈8（栏 spacing 6 + inset 2）vs Web margin 0.75em = 12，−4。段落间 ≈10 ✓。
- 分割线总留白 ≈24（内 pad 16 + spacing 6 + 文本 inset 2）vs Web 折叠后 16，+8——批 B 按 CSS 字面设 pad 16 时未扣合成项，属双计。

### 3.2 斜杠触发面比 Web 宽（小）
Web 于 heading/quote 内不弹（hooks/slash.rs + editor.js blockquote 守卫）；原生 updateSlash（Swift:4600-4607）仅排除 codeBlock/callout，heading/quote/todo 均可弹。链接表单触发/预填 "https://"/取消回列表已逐点对齐（余差仅 §3.3 的 #64/#66 度量）。

### 3.3 浮层线前轮微差簇（31 项未收，数值与前轮逐值未动）
已销项：#6 胶囊宽（0.9.35 修，列态 −124 / 紧凑 −204 / 下限 66 逐值一致）、#17 置灰仍可点（0.9.32 顺带修）。
仍待修（Web 真值 → 原生现状，Swift 行号）：
- #3 胶囊标题 tracking −0.2 缺（7598-7612）；#10 页眉两钮字形 17 vs SVG 22；#13 菜单项高亮 radius 12 vs 17（RowPressStyle 默认 10133）；#14 菜单图标 17 vs 20（8001-8004）；#15 菜单标题 tracking/副距（8005-8015）；#18/#19 附件/背景行上距 4 缺（7821-7845）；#20 背景行图标应紫 #AF52DE，原生一律 accent 且无该令牌（8003）；#29 导出返回钮 14 vs 22（7869-7876）；#30 导出选项 gap 3 + 顶距 6 缺（7891-7906）；#32 徽章字体族 monospaced vs inherit（7950-7955）；#33 导出副距 1 vs 2；#34 导出 chevron 色 #68686D vs #C0C0C6、左距缺（7967-7969）；#35 导出尾注边线/内距（7910-7925）；#41 背景移除区边线前距 4 缺（7745-7772）；#48 卡菜单随 #13/#14；#51 斜杠面板宽 min(360, vw−32) vs Web 内容估宽/vw−24（7143）；#53 斜杠面板左缘栏锚 vs 光标锚 −8 钳 12（7175-7180）；#55 斜杠行图标 19 vs 20；#56 斜杠副距 1 vs 2；#57 斜杠行间 0 vs 2（7232）；#58 组头左距/首组顶距/tracking（7310-7330）；#59 快捷键丸 opacity 0.78 缺（7368-7380）；#60 最近丸 radius 6/字 10/无边 vs 999/11/glass+0.5 边（7350-7362）；#61 斜杠空态图标 24/主文 14 主色/提示 12 vs 28/13 次级/11（7272-7298）；#64 链接输入框 1px 边缺、横距 12 vs 11（7407-7425）；#66 链接钮字 14、无 min-width 76 vs 13（7432-7452）；#72 诊断徽章面板窄屏宽/滚动区（2455-2600）；#74 徽章错误态色 #FF3B30 vs #FF6B6B、无该令牌（2550-2554）；#75 清除钮无内距圆角（2556-2558）；#76 徽章条目图标 12 vs 14（2562-2595）。
成因归纳：SF 字形系统性比 Web SVG 小 1–5px；纵向小距（margin-top 4 一簇、gap 2/3 一簇）在 VStack spacing 0/统一合成下成组丢失。

### 3.4 MD 线微差簇
- 预览链接色缺失：MdRender Link 有 underline+_link 标记（8529-8535），但 Marks.attributed 不给 _link 段设前景色、MdSegsView 无 tint → 外链呈系统默认蓝；Wiki 段（8538-8547）无色且无虚线下划线（Web editor.css:116-118、301-303：#005BBB/#72B7FF + 下划线，wiki 加虚线）。编辑面修复（1576）只及 UITextView。
- 脚注回链缺失：Web 脚注区每项带 ↩ 回链、最小 32×32（blocks.rs:2048-2065）；原生 Footnotes 区无回链（8896-8940）。序号不可点因「点按整块回编辑」口径可议保留。
- 删除线底色缺失：Web del 另带 --fill-hover 底 + padding 0 2px（editor.css:375）；原生只有删除线（8509-8511 → 1433-1436）。
- 表格外框/横滚：Web 外框 1px + radius 12 + --card-bg 底、overflow-x auto、cell 横 padding 12、td max-width 18rem（editor.css:2-16）；原生 Grid 无底/边/radius/横滚，列间合计 12 vs 24、左右缘 0 vs 12（8840-8895）——宽表被压缩，窄屏可至感知级。
- 长代码横滚：Web pre 不换行 + overflow-x auto（editor.css:36）；原生普通 Text 软换行（8733-8755）。手机端换行可议等价更优，先登记待裁。
- Callout 图标 accent 五变体色值皆非 Web 令牌：Web #005BBB/#1C7A34/#AD5F00/#8436AA/#B3261E（tokens.css:37-41）vs 原生系统色系 #007AFF/#2EA043/#D97706/#8250DF/#E0433A（Swift:10004-10011）。

### 3.5 令牌与占位残差
- T.checkBorder 深色 = #73737A（Swift:9945），Web 深色 --md-checkbox-border #B5B5BB——深色未选圈偏暗（浅色 ✓、checkChecked 双色 ✓）。
- imageTextRow 加载占位底仍 T.pressBg 0.05（Swift:9797），Web --fill-subtle 0.03；卡形态 #43 已修、行形态漏改。
- imgTextCard 空占位缺 camera 图标 30（Web blocks.rs 图文卡占位），原生仅 13 号文字（Swift:9756-9768）。
- 空图片块占位：Web.img-placeholder 虚线边 1.5px、radius 22、pad 28/16、gap 8、图标 30、文 14（editor.css:331-339）；原生无边框、图标默认号、文 subheadline、pad V18（Swift:2155-2165）。前轮未单列。

### 3.6 未知块类型降级形态（边缘）
Web 默认支静默降级纯文本段 + Diag log_once（blocks.rs:1419）；原生 BlockRow 兜底行明示「{type} 块 · 后续轮支持」开发文案（Swift:6655 附近），无降级文本、无日志。现行 17 种类型（paragraph/heading/quote/todo/divider/callout/codeBlock/bulleted-list/numbered-list/list-item/image/gallery/video/musicCard/attachment/link-card/imgTextCard/imageTextRow/embedCard）原生全覆盖，仅外部/未来数据可达。

### 3.7 Callout 折叠形态未实现（待定性）
Web 有.callout-collapsible（details/summary，editor.css:262-285）；原生 grep collaps 仅列表折叠，编辑态 callout 与 MdCalloutView 均无折叠呈现。是否由 MD 语法（> [!note]-）驱动、存量数据是否含此形态，未在本轮定性，登记待查。

---

## 4 等价更优保留 / 已定案（不修）

- **块长按转换菜单**（BlockRow 系统 contextMenu，Swift:6199-6233）：Web 无此浮层（转换走斜杠 op_convert），为用户 2026-11-26 裁定保留的原生形态。注记：项序与 Web 斜杠序差两处（正文提前、待办/引用互换）、多一项「删除块」、仅非编辑态可达（Web 斜杠转换在编辑中可用）——属行为差待裁，不作几何缺陷。
- **MD 任务勾选框**：原生 SF square/checkmark.square.fill 15pt + checkChecked 色，与 Web UA checkbox（方框约 16px、UA 蓝填充）形态等价、色值同源（MD 线 N3 判等价更优保留）。
- **附件触发两步**：Web 菜单项即文件 label 一步直达；原生经系统 confirmationDialog 分图片/文件两步（Swift:6997-7005）。系统等价形态可议，登记备查。
- **embedCard 降级**：两侧均降级纯文本（Web blocks.rs 默认支、原生文本拼接），对齐。
- **近似登记**：MD 标题字重.heavy 近似 750；sup/sub ×0.75 + baselineOffset 近似 0.76em；行内代码 padding/radius/边在 NSAttributedString 无对应面（Swift:1425-1426 注释已登记），底与字号在位。
- 斜杠命令集本体：Web render.rs:26-48 与原生 SlashCmds.all 同为 22 个 act，顺序/kw/py/shortcut 全同；空查询分组构成（最近 6 + 基础 + 媒体、组内剔除）一致。

---

## 5 i18n I4 现状基线（只记范围，硬编码不算缺陷）

编辑器面未接语言包的硬编码中文盘点（I4 接法按 plan_native_i18n.md：复用 Web 五语 JSON 同键查表）：
- 页眉菜单/导出/背景/双栏文案（Swift:7833-7925 段）；标题占位「无标题备忘」（titleCapsule 7598 段）。
- 斜杠：命令 title/sub 即 SlashCmds 数据表（3620-3676，22 项——此表本身即 I4 数据真源）、组头「最近使用」、空态文案（7236-7298）。
- 链接表单（7407-7452）；反链标题「反向链接」与「无标题」（8146-8188）。
- 音乐胶囊 prompt（8470 附近）；图文「点击添加图片」系（9756 段）；图片块占位「点击添加图片/图片不可用」（2155-2180）；Gallery 空瓦「点击添加/长按编辑添加/多张图片」（8360-8385）。
- 转换菜单与删除块、全文底表「图文文本/取消/保存」（6199-6233、9832-9858）。
（Diag/救援文案不在本线范围。）

---

## 附：本轮覆盖面声明

已逐项过：编辑态块几何/字号字重行高/颜色令牌/段距合成、行内标记全集、回车/退格/Shift+Enter/粘贴分流/组字守卫、拖拽全套、斜杠（命令集/触发/过滤/三场景/面板定位）、卡菜单与 ••• 菜单、页眉与标题胶囊、双栏（分界/独立滚动/栏宽/落锚）、MD 预览（块全集/行内全集/公式/脚注/表格/图片）、反向链接、图文底表、附件路径、未知类型降级、i18n 基线。
未覆盖：EditorHeaderView 中与浮层线重叠的菜单触发时序（浮层线已核数值面）；真机手感类（拾起时序、滚动帧率）不在静态审计范围。
