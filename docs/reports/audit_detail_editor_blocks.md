# 数值级对齐排查 · 线 1：编辑页块级渲染（原生 iOS vs Rust Web）

方法：逐块读 Web 真值（`rust/apps/web/styles/{tokens,editor}.css`、`rust/apps/web/src/blocks.rs`）与原生实现（`rust/apps/ios/app/MomentApp.swift`，下称 Swift 文件，行号为审计时点行号），只记有代码证据的数值差。口径：等价是底线、原生更优才用原生形态；已定案项只登记不报缺陷。字号基准：Web 正文 `--md-font-body: 1rem = 16px`、行高 `--md-line-height: 1.75`（tokens.css:17-18）；原生正文以 Dynamic Type 缩放 16 基准（已定案），下表 Web 字号即核对比例用。

## 一、全局 / 文本基础

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 1 | 段落块间留白 | `.blk-p { margin: 0 0 0.65em }`（editor.css:1296），段间净留白 10.4px（边距折叠后） | 栏 VStack spacing 6（Swift:7128）+ 行上下 padding 3+3（Swift:5394 区）+ UITextView 内边距 4+4（Swift:1431-1432），段间净留白 ≈20px | +9.6px（近 2 倍） | 缺陷待修（系统性节奏差，所有文本块同源） |
| 2 | 正文字号/行高 | 16px / 1.75（tokens.css:17-18） | dynFont 16 / lineHeightMultiple 1.75（Swift:1206、1220） | 0 | 已定案（Dynamic Type） |
| 3 | 标题字重 | 750（h1-h3，editor.css:1297-1299）；h4 700 | UIFont `.bold` = 700（Swift:1199） | h1-h3 −50 | 缺陷待修（轻微，SF 无 750 档，可用 .heavy 近似或接受后改判） |
| 4 | 标题字距 | letter-spacing −0.02em（editor.css:1297-1300） | UITextView 未设 kern | +0.02em | 缺陷待修（轻微） |
| 5 | H1 行高 | 1.2（editor.css:1297） | 1.28（Swift:1217，标题统一） | +0.08 | 缺陷待修 |
| 6 | H1 下边线 | border-bottom 1px solid `--border-color` rgba(0,0,0,0.05)，padding-bottom 0.25em=7px（editor.css:1297） | Rectangle 高 0.5、色 T.glassBorder rgba(0,0,0,0.16)、距文 6（Swift:5346-5352） | 线粗 −0.5px、色深 +0.11 alpha、距 −1px | 缺陷待修 |
| 7 | 标题上距 | margin-top 1.25em：L1 35 / L2 28.75 / L3 25px（editor.css:1297-1299） | 行内顶 padding L1 14 / L2 10 / L3 8（Swift:5354-5356），叠 #1 的基础留白 ≈ 34 / 30 / 28px | 近似抵消（L1 −1、L2 +1.25、L3 +3） | 已对齐（经 #1 基础留白合成后接近；若修 #1 须同步重算此项） |
| 8 | 编辑标题 L4+ 字号 | h4 17px（`--md-heading-h4`，tokens.css:22） | level ≥3 一律 20（Swift:1192-1194） | L4 +3px | 缺陷待修（斜杠菜单只出 L1-L3，但存量/导入数据可含 L4） |
| 9 | 行内代码 | 0.85em、mono、`--code-bg` 底、padding 0.15em/0.45em、radius 6、1px 边（editor.css:107-110） | mono 同字号（1.0em）、无底色/无边（Swift:1257-1262 的 `Marks.font` 只换字体，`attributed` 未给 code 段加 backgroundColor） | 字号 +0.15em、底与边缺失 | 缺陷待修 |
| 10 | 行内链接色 | `--md-link-color` #005BBB（浅）/ #72B7FF（深），下划线 0.08em（editor.css:116-118；tokens.css:23） | `.link` 属性已设，但全仓未设 `linkTextAttributes`，UITextView 用系统链接蓝（inferred：≈#007AFF） | 色值不同 | 缺陷待修（inferred，轻微） |
| 11 | 高亮 == | 字面 + `--fill-highlight` rgba(255,204,0,0.25) 底、字重 600（editor.css:374） | 编辑面只加底色不改字重（Swift:1229-1255 注释明示口径） | 字重差 | 已定案（编辑面口径；渲染侧切 mark） |

## 二、待办 / 引用 / Callout / 代码块 / 分割线（编辑态）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 12 | 待办行内边距 | padding 4px 8px、min-height 44、radius 10（editor.css:1305） | 无水平 padding（行 padding 仅 callout/quote/codeBlock 为 14，其余 0，Swift:5390-5393）；无 min-height | 左缩进 −8px | 缺陷待修 |
| 13 | 待办勾选圈 | 视觉圈 22×22、边 1.75px `--md-checkbox-border` #73737A；选中底 `--md-checkbox-checked` #0066CC + 白勾 5×9/线 2（editor.css:1308-1310）；点击域 44×44、与文 gap 10 | SF Symbol `circle`/`checkmark.circle.fill` 22 号、44×44 域（Swift:5228-5246）；未选色 T.textSecondary #68686D；选中色 T.checkChecked #0066CC/#0A84FF（与 Web 令牌逐值同）；布局以 trailing −22 压缩，文起点 = 22+8 = 30px | 圈色 #68686D vs #73737A；文起点 30 vs Web 8+44+10 = 62px（自块左缘） | 缺陷待修（文起点差 32px 最显眼；圈色差轻微） |
| 14 | 待办勾选垂直对齐 | align-items: center（多行时圈居中，editor.css:1305） | HStack .top + 圈顶 padding 2（Swift:5217、5245） | 多行待办圈位置不同 | 缺陷待修（轻微） |
| 15 | 待办完成态文字色 | `--md-text-muted` #626267 + 删除线（editor.css:1313） | 删除线 + `UIColor.secondaryLabel`（浅色 ≈ rgba(60,60,67,0.6)，Swift:1497-1509） | 色不同（原生更浅） | 缺陷待修（轻微） |
| 16 | 引用块边框 | 左 3px `--md-quote-border` + 其余三边 1px `--border-color`，radius 10，padding 10/14，底 `--md-quote-bg`（editor.css:1301） | 左条 3px T.quoteBar（逐值同 Web，Swift:8795-8797）、底 T.quoteBg（逐值同）、padding 10/14、radius 10；无三边描边（Swift:5330-5344、5577） | 缺三边 1px 线 | 缺陷待修（轻微） |
| 17 | 引用文字 | 14px / 1.6 / `--md-text-muted`（editor.css:1301） | 14 / 1.6 / T.quoteText #626267（Swift:1202、1218、8798-8800） | 0 | 已对齐 |
| 18 | Callout 头部图标 | 18px（editor.css:256） | 14 号 semibold SF Symbol（Swift:5310-5312） | −4px | 缺陷待修 |
| 19 | Callout 标题 | 15px / 700 / `--text-main` 色、字距 −0.1px（editor.css:258） | 13 号 semibold、色 = 变体 accent 色（Swift:5313-5318） | 字号 −2、字重 −100、颜色口径不同（Web 标题主色、原生变体色） | 缺陷待修 |
| 20 | Callout 头部间距 | 图标-标题 gap 8、头-正文 margin-bottom 5（editor.css:255、30） | gap 6、VStack spacing 4（Swift:5309、5308） | −2 / −1px | 缺陷待修（轻微） |
| 21 | Callout 本体 | padding 12/14、radius 12、1px 边 `--border-color`、正文 14 / 1.65（editor.css:237-259） | padding 12/14、radius 12（Swift:5394-5396、背景圆角）；无 1px 边；正文经 BlockTextView 走 quote/callout 节奏 = 14 / 1.6（Swift:1218） | 缺边框；正文行高 −0.05 | 缺陷待修（轻微） |
| 22 | Callout 五变体底色 | rgba 染：note rgba(0,122,255,0.07)、tip rgba(52,199,89,0.09)、warning rgba(255,149,0,0.09)、important rgba(175,82,222,0.08)、caution rgba(224,67,58,0.07)（tokens.css:31-35） | 实色近似：#EAF2FE / #EAF7EE / #FFF4E0 / #F1EAFB / #FDECEA（Swift:8833-8841），白底合成下比 Web 更浓 | 色浓度差 | 已定案（五变体口径已定；数值近似登记） |
| 23 | 代码块字号/行高 | 13px / 1.6（editor.css:1302） | 13.5 mono / 1.75（Swift:1204；withRhythm 默认分支 1220） | 字号 +0.5、行高 +0.15 | 缺陷待修 |
| 24 | 代码块边框与底 | 1px 边 `--border-color`、底 `--code-bg` #F4F4F5（浅）/ #2C2C2E（深）、padding 12/14、radius 12（editor.css:1302） | 无描边；底 T.codeBg = rgba(0,0,0,0.045) / rgba(255,255,255,0.07) 中性染（Swift:8769-8771，注释自述「近似」）；padding 12/14、radius 12 同 | 缺边；底色在备忘底色/深色下分叉 | 缺陷待修 |
| 25 | 分割线 | 1px 渐变线（transparent→`--border-color`→transparent）、margin 1em 0（上下各 16px）（editor.css:1303） | SwiftUI `Divider()` 系统实线（全宽、系统分隔色）+ 上下 padding 各 8（Swift:5299） | 形态（实线 vs 渐变）、上下距 −8px | 缺陷待修 |

## 三、列表块（编辑态）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 26 | 列表标记色 | `--text-main` #1A1A1A（editor.css:1316） | T.textSecondary #68686D（Swift:2643） | 色差 | 缺陷待修 |
| 27 | 列表标记对齐/宽 | flex 0 0 1.2em ≈ 19.2px、text-align: center（editor.css:1316） | 宽 20、右对齐（Swift:2644-2646） | 对齐不同（序号右对齐 vs 居中） | 缺陷待修（轻微；右对齐对多位序号更稳，可议改判） |
| 28 | 列表行距与间隙 | .list-row gap 8、padding 2px 0（editor.css:1315）；.list-wrap margin 0.4em 0 | HStack spacing 6、项间 VStack spacing 2（Swift:2639-2640），项内另有 UITextView 上下内边距 4+4 | gap −2；纵向节奏与 Web 不同源（同 #1） | 缺陷待修（轻微） |
| 29 | 嵌套列表缩进 | ul padding-left 1.2em ≈ 19.2px、ol 1.4em ≈ 22.4px（editor.css:20-21） | 统一 leading 26（Swift:2656-2658） | +3.6 ~ +6.8px | 缺陷待修（轻微） |
| 30 | 列表标记字号 | 继承正文 16px（editor.css:1316 无独立字号） | 15 号（Swift:2642） | −1px | 缺陷待修（轻微） |

## 四、图片 / Gallery / 视频

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 31 | 图片块圆角 | 22（editor.css:1405） | 10（Swift:1862） | −12 | 缺陷待修 |
| 32 | 图片块尺寸口径 | 自然宽（max-width 100%）、max-height 668、margin 8px auto 居中、object-fit contain（editor.css:1405）；外层 margin 8px 36px（editor.css:424-425） | resizable + scaledToFit 满宽（小图被放大至栏宽）、无高度上限；左右内缩 36 已对齐（Swift:1859-1863、5251-5253） | 小图放大、超长图不限高 | 缺陷待修 |
| 33 | Gallery 瓦高 | 图高固定 366px、2 列、gap 4、radius 22（editor.css:1356-1357） | 正方形瓦（aspectRatio 1，Swift:7279-7330），窄屏栏宽内缩 36 后瓦高 ≈160px 量级 | 瓦高 −200px 量级 | 缺陷待修（形态差最显著项之一） |
| 34 | Gallery 空态 | 双瓦高 366、gap 6、上下 padding 6/14、底 `--fill-subtle` 与 `--fill-subtle-2` 交替、图标 18、标签 11（editor.css:1360-1367） | 正方形瓦、底 T.pressBg（rgba(0,0,0,0.05)）单色、图标 18、无文字标签（Swift:7285-7310） | 高/底色/标签缺失 | 缺陷待修 |
| 35 | 视频块 | `<video controls>` .blk-media width 100%、固有比例、无圆角规则（blocks.rs:1048-1060；editor.css:1399） | 固定 16:9 + radius 22 裁切（Swift:8363-8376） | 非 16:9 源被裁/留边口径不同；圆角为原生自加 | 系统等价更优（AVPlayerViewController 承载已定案；16:9 占位与圆角属呈现近似，登记） |

## 五、卡片类（链接卡 / 音乐卡 / 附件 / 图文卡）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 36 | 链接卡/音乐卡 ready 本体 | margin 8px 0、radius 32、封面 2.4:1、body padding 10/14/12（有封面 top 6）、标题 14/600 行高 1.4 两行截、副标 12 行高 1.3 距标题 3、来源行 11 距上 4、图标 14、gap 5、圆点 3（editor.css:434、463-472；blocks.rs:1096-1130） | CardBlockView.readyCard 逐项同值（Swift:8079-8124、8152-8169）；唯来源行图标 SF Symbol 12 号 vs Web SVG 14 | 图标 −2px | 已对齐（图标差轻微，登记） |
| 37 | 音乐兜底胶囊 | .music-pill padding 12/16、gap 10、图标 17、字 14、radius 999（editor.css:462） | padding 12/16、gap 10、字 14、radius 999；图标 14 号（Swift:8269-8287） | 图标 −3px | 缺陷待修（轻微） |
| 38 | 音乐错误卡 | 图标 20、gap 10、padding 8/10、重试钮 13/600 accent、min 44×44、padding 0/12、底 `--fill-hover-strong`、radius 999（editor.css:437-442） | 逐项同值（Swift:8238-8267） | 0 | 已对齐 |
| 39 | 音乐输入胶囊 | padding 12/18、字 14、radius 999、glass-control 档（editor.css:458） | padding 12/18、字 14、glassControl 999（Swift:7399-7402） | 0 | 已对齐 |
| 40 | 音乐骨架 | 封面 2.4:1 + 三行（75%/50%/35%、行高 12、radius 6）、body padding 10/14/12、行 gap 8、脉冲 1.4s（editor.css:445-456） | 同构（Swift:8173-8225，帧高 52 近似三行+gap=52 实际 12×3+8×2=52 ✓）；脉冲以整卡 opacity 代替底色脉冲 | 0（脉冲形态近似） | 已对齐 |
| 41 | 附件文件行 | padding 16/20、radius 32、gap 10、图标 1.5rem=24、名 14/500 单行省略、提示 11 + 底 `--fill-hover-strong` + padding 2/10 + radius 999（editor.css:428-432） | AttachmentRow 逐项同值（Swift:8412-8440）；多文件同块时项间 spacing 8（Web 一块一文件、无对应口径，inferred） | 0 | 已对齐 |
| 42 | 图片附件（node.image） | .atomic.attachment radius 32、margin 8px 0（editor.css:423-427） | radius 32（Swift:8459-8471） | 0 | 已对齐 |
| 43 | 图文卡（imgTextCard） | radius 22、图 max-height 468、文 padding 12/14、14 / 1.7、min-height 44；占位区高 160、底 `--fill-subtle`、文 13（editor.css:37-46） | radius 22、图上限 468、文 12/14、14 / 1.7（lineSpacing 9.8）、minHeight 44（Swift:8560-8615）；占位/加载区底用 T.pressBg（0.05）而非 T.fillSubtle（0.03） | 占位底色令牌错位 | 缺陷待修（轻微） |
| 44 | 图文行（imageTextRow） | 高 181–196 内容驱动、图占 50%、gap 10、文 padding 10/14、14 / 1.7、6 行截（editor.css:47-51） | 固定高 188、图 50%、gap 10、文 10/14、lineLimit 6（Swift:8617-8667） | 高度固定 vs 区间（188 在区间内） | 已对齐（近似登记） |
| 45 | 卡片上下外距 | 卡类 margin 8px 0（editor.css:37、47、434、424-425） | 无块级外距，靠栏 spacing 6（Swift:7128） | −2px | 已对齐（近似；与 #1 同源，修 #1 时一并核） |

## 六、MD 渲染块（失焦预览 MdBlockView / MdPreviewView）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 46 | 预览块间节奏 | 各块按自身 margin（p 下 0.65em、标题上 1.25em、pre/quote/callout 0.75em 等，editor.css:83-128） | MdPreviewView 统一 spacing 6（Swift:7969） | 标题前距、段距均被压平 | 缺陷待修 |
| 47 | MD 标题 | h1 28/1.2 + 下边线、h2 23、h3 20、h4 17、字重 750、margin 1.25em 0 0.4em（editor.css:87-97） | 字号梯 28/23/20/17/13/11 ✓（Swift:7598-7612）；字重 .bold 700；无下边线、无独立边距（受 #46 约束） | 字重 −50、h1 边线缺失 | 缺陷待修（轻微） |
| 48 | MD 代码块 | pre：padding 12/14、字 13 / 1.6、radius 12、1px 边、底 `--code-bg`（editor.css:36） | padding 10、radius 8、无行高设定（SwiftUI 默认单倍）、无边、底 T.codeBg（Swift:7627-7637） | padding −2/−4、radius −4、行高差 | 缺陷待修 |
| 49 | MD 引用正文字号 | blockquote 14px（子块继承，editor.css:99-105） | 子 Para 以 16 渲染（Swift:7620-7625 的 Para 分支固定 16；Quote 分支 Swift:7639-7667 未降字号） | +2px | 缺陷待修（与既有登记「Quote 子块字号近似」同项） |
| 50 | MD 引用内部几何 | 左边条在盒边、文距盒左缘 3+14 = 17px（editor.css:99-105） | padding 左 14 内再置 3px 条 + spacing 8，文距左缘 25px（Swift:7644-7660）；描边 0.5 T.borderSoft 近似三边 1px | 文缩进 +8px | 缺陷待修（轻微） |
| 51 | MD Callout | padding 12/14、图标 18、标题 15/700、头 gap 8、头下距 5、正文 14 / 1.65、1px 边（editor.css:24-35） | MdCalloutView：padding 10、图标 14、标题 13/600、gap 6、VStack spacing 6、正文子块 16、无边（Swift:7830-7879） | 多项同 #18/#19/#21 | 缺陷待修 |
| 52 | MD 列表标记 | 标记随正文色 `--text-main`；ul 缩进 1.2em、ol 1.4em；li padding 2px 0（editor.css:20-22） | 标记 T.textSecondary、宽 18 右对齐、项间 spacing 4、任务勾选为 SF 方框符号 15 号（Swift:7670-7720） | 同 #26/#27 | 缺陷待修（轻微） |
| 53 | MD 表格 | th 12/600、`--md-text-muted` #626267、padding 9/12；td 16（继承正文）、padding 9/12；行线 1px `--border-color`（editor.css:14-16） | th 12 semibold 但色 T.textSecondary #68686D；td 14；cell 纵 padding 5；行线为系统 Divider（Swift:7722-7770） | td 字号 −2、th 色差、纵 padding −4 | 缺陷待修 |
| 54 | MD 脚注区 | 字 13、`--text-secondary`、上边 1px 线、margin-top 1.2em、项 padding 0.2em 0（editor.css:302-307） | 标签 12、正文子块 16、无上边线（Swift:7772-7798） | 正文字号 +3、无分隔线 | 缺陷待修（轻微） |
| 55 | MD 分割线 | hr 渐变 1px、margin 1em 0（editor.css:123-125） | SwiftUI Divider()（Swift:7582） | 同 #25 | 缺陷待修（轻微） |

## 汇总

- 条目 55 项：已对齐/已定案 13 项（#2、#7、#11、#17、#22、#35、#36、#38、#39、#40、#41、#42、#44、#45 中取主要者），缺陷待修 42 项，其中多数为轻微（≤2px 或单令牌色差）。
- 最显著五项：#33 Gallery 瓦高（366px vs 正方形）、#1 段间留白系统性近 2 倍、#31+#32 图片块圆角与尺寸口径、#13 待办文起点左移 32px、#23+#24 代码块字号/行高/边框/底色四差。
- 同源项提示：#1 是 #7、#28、#45、#46 的共同根源（原生以固定 spacing + UITextView 内边距合成块距，Web 以逐块 margin 折叠），修 #1 须整组重算，不宜逐项打补丁。
