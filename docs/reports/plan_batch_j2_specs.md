# 修复批 J2（0.9.45）只读规格清单

- 阶段：只读准备；未改 `MomentApp.swift`、`build-app2.sh`、`verify_ios.sh` 或任何实现代码。
- 依据：`docs/reports/audit2_editor.md` §3.3、§3.4、§1.3；逐项回源现行 Web 源码，不以报告转述代替源码。
- 原生行号：本文件读取时的工作树（含 0.9.44 未提交改动）行号；落码前应以符号名复核，行号可能随 J1 收尾再漂移。
- 计数口径：浮层 31 行 + MD 9 行 = 40 行；其中 38 行可直接落码，2 行存疑（MD-05、MD-08）；MD-02 的视觉形态可直接落码，但锚点跳转动作另列存疑子项。

## 一、浮层线 31 项

| 编号 | 报告条目 | Web 真值（源文件:行号） | 原生现行值（MomentApp.swift 落点） | 目标改法（一句） | 涉及令牌新增 |
|---|---|---|---|---|---|
| J2-F01 | #3 标题胶囊 tracking 缺失 | 14/600、`letter-spacing:-0.2px`、行高 1.3（`styles/editor.css:1203`） | `titleCapsule` 8474；TextField 8477、截断 Text 8500 均为 14 semibold、无 tracking；`capsuleWidth` 8529 的量测也无 kern | 两个标题呈现分支都加 `tracking(-0.2)`，且胶囊宽量测 attributes 同步加 kern `-0.2` 防截断/溢出。 | 否 |
| J2-F02 | #10 页眉两钮字形偏小 | back、dots SVG 均为 22×22（`src/icons.rs:196`、`src/icons.rs:164`） | `EditorHeaderView.headerOverlay`：back 8355、ellipsis 8386 均为 SF 17 semibold、46×46 钮 | 两钮图标字号均改 22 semibold，46×46 玻璃钮不变。 | 否 |
| J2-F03 | #13 菜单项高亮圆角偏小 | `.menu-item` 本体 radius 17（`styles/editor.css:1241`） | `menuItem` 8895 使用 `RowPressStyle()`；默认 radius 12（11355–11356） | 只把 `menuItem` 的按压样式显式改为 `RowPressStyle(radius: 17)`，不改全局默认以免外溢。 | 否 |
| J2-F04 | #14 菜单图标偏小 | 图标槽 24×24、SVG 20（`styles/tokens.css:180-182`；`styles/editor.css:1245-1246`；调用例 `src/editor/layers.rs:728`） | `menuItem` 8866–8869：槽 24×24、SF 图标 17、accent | `menuItem` 图标字号改 20，槽 24×24 与 accent 口径不变。 | 否 |
| J2-F05 | #15 菜单标题 tracking/副距 | 标题 15/650、`letter-spacing:-0.1px`；副 11、`margin-top:2`（`styles/editor.css:1248-1249`） | `menuItem` 8870–8879：标题 15 semibold、无 tracking；文案 VStack spacing 1 | 标题加 `tracking(-0.1)`，文案列 spacing 改 2；650 继续以 semibold 近似。 | 否 |
| J2-F06 | #18 附件行上距缺失 | 附件 label 内联 `margin-top:4px`（`src/editor/layers.rs:743`） | 菜单 VStack 8684 spacing 0；附件行调用 8702 无额外顶距 | 仅给附件 `menuItem` 调用点加 `.padding(.top, 4)`。 | 否 |
| J2-F07 | #19 背景行上距缺失 | 背景 button 内联 `margin-top:4px`（`src/editor/layers.rs:785-786`） | 菜单 VStack 8684 spacing 0；背景行调用 8715 无额外顶距 | 仅给背景 `menuItem` 调用点加 `.padding(.top, 4)`。 | 否 |
| J2-F08 | #20 背景行图标色错 | palette stroke `var(--color-purple)` = `#AF52DE`（`src/editor/layers.rs:792`；`styles/tokens.css:82`） | `menuItem` 8866–8868 除 danger 外一律 `T.accent`；背景调用 8715 无图标色参数；T 无 purple | 新增 `T.purple = dyn(0xAF52DE, 0xAF52DE)`，给 `menuItem` 加图标色参数且背景行传 purple。 | 是：`T.purple` |
| J2-F09 | #29 导出返回钮字形偏小 | back SVG 22×22（`src/icons.rs:206`） | `exportPanel` 8752–8754：chevron.left SF 14 semibold、46×46 钮 | 返回钮图标字号改 22 semibold，钮盒与标题补偿不变。 | 否 |
| J2-F10 | #30 导出选项 gap/顶距缺失 | `.export-choices` gap 3、padding-top 6（`styles/editor.css:1260`；`styles/panels.css:237` 仅接管滚动布局） | `exportPanel` 8744 外层 spacing 0；三行 8772、8777、8782 直接相邻、无顶距 | 把三条 `exportChoice` 包进 `VStack(spacing: 3)` 并加 `.padding(.top, 6)`。 | 否 |
| J2-F11 | #32 导出徽章字体族/字距 | 最终覆盖：34×34、透明、radius 0、11（PDF 9）、`font-family:inherit`、`letter-spacing:-0.2px`（`styles/panels.css:239-240`；拼接序 `src/main.rs:36-38`） | `exportChoice` 8829–8834：34×34、11/9 bold、`.monospaced`、无 tracking | 徽章改系统默认字体族（删除 `design:.monospaced`）并加 `tracking(-0.2)`，尺寸/字号不变。 | 否 |
| J2-F12 | #33 导出副文案上距 | label 14/650、detail 11、`margin-top:2`（`styles/panels.css:242-243`） | `exportChoice` 8835：label/detail VStack spacing 1 | `exportChoice` 文案列 spacing 改 2。 | 否 |
| J2-F13 | #34 导出 chevron 色/左距 | chevron 19、`--color-placeholder-strong:#C0C0C6`、padding-left 4（`styles/tokens.css:84`；`styles/panels.css:244`） | `exportChoice` 8845–8847：19、`T.textSecondary`（#68686D/#98989D）、无左距；T 无 placeholderStrong | 新增 `T.placeholderStrong = dyn(0xC0C0C6, 0xC0C0C6)`，chevron 改用之并加 leading padding 4。 | 是：`T.placeholderStrong` |
| J2-F14 | #35 导出尾注边线/内距/行高 | margin 5/4/2、padding 9/5/2、顶边 0.5、10px、line-height 1.45（`styles/panels.css:245`） | `exportPanel` 8793–8804：Text 横 4、上 5、下 2，顶线 overlay 贴在含 padding 的外缘；无 lineSpacing | 尾注拆外层 margin（top 5、H 4、bottom 2）+ 内层 padding（top 9、H 5、bottom 2），顶线挂内层顶缘，文字加 `lineSpacing(4.5)`。 | 否 |
| J2-F15 | #41 背景移除区边线前距 | `.bg-remove-wrap`：顶边 0.5、`margin-top:4`、`padding-top:10`（`styles/editor.css:1279`） | `bgSheet` 8612–8641：Rectangle 前无 4 顶距，Button 已有 top padding 10 | 在移除区 Rectangle/包裹层前加 `.padding(.top, 4)`，保留边线后 Button 的 top 10。 | 否 |
| J2-F16 | #48 卡菜单随 #13/#14 | 卡菜单项与 ••• 菜单共用 `.menu-item` 度量（`styles/editor.css:1241、1245-1246`） | `cardMenuPanel` 7875 起复用同一 `menuItem`；其样式落点同 8866–8869、8895 | 不另写卡菜单数值：共享 `menuItem` 落 J2-F03/F04 后同步验收卡菜单的 radius 17 与图标 20。 | 否 |
| J2-F17 | #51 斜杠面板宽公式 | 每行估宽 = 24+10+标题字数×16+（shortcut 字数×8，存在时另 +8）+22、分组 +20，初值 240；宽 = `min(360, max(220, maxContent+12, vw-24))`（`src/editor/render.rs:637-650`） | `slashLayer` 7988：`panelW = min(360, geo.size.width - 32)`，无内容估宽 | 按 Web 公式用全部命令的当前标题/shortcut/group 实现 `slashPanelWidth(viewW:)` 并替换固定 `vw-32` 口径。 | 否 |
| J2-F18 | #53 斜杠面板横向光标锚 | `left = min(vx+vw-width-12, anchor_x-8)` 后钳 `>= vx+12`（`src/editor/render.rs:650`） | `slashLayer` 8019–8024 调 `panelLeftX(block:)`；该函数 7908–7927 以块/栏左缘为锚，无 slash 光标 X 状态 | 在 slash 更新路径保存 UITextView caretRect 换算到窗口的 X，面板 left 改按 Web 公式计算并以 `left + panelW/2` 定位。 | 否 |
| J2-F19 | #55 斜杠行图标偏小 | 图标槽 24×24、SVG 20（`styles/tokens.css:180-181`；`styles/editor.css:508-517`） | `slashRow` 8190–8193：槽 24×24、SF 图标 19 | `slashRow` 图标字号改 20，槽不变。 | 否 |
| J2-F20 | #56 斜杠行副文案距 | 文案列 gap 2；标题 14/1.25、副 12/1.35（`styles/editor.css:518-521`） | `slashRow` 8194：标题/副 VStack spacing 1 | `slashRow` 文案列 spacing 改 2。 | 否 |
| J2-F21 | #57 斜杠行间外距缺失 | `.slash-row { margin:1px 0 }`，相邻行间合成 2、首尾各 1（`styles/editor.css:1370`，同值规则亦见 484） | `slashPanel` 8061 行列 spacing 0；`slashRow` 8245 根层无纵向外距 | 给 `slashRow` 根 Button 外加 `.padding(.vertical, 1)`，同时兑现行间 2 与首尾 1。 | 否 |
| J2-F22 | #58 斜杠组头左距/首组顶距/tracking | 组头 padding 6/8/4、11/700、letter-spacing 0.035em（=0.385pt）、uppercase、opacity 0.8；非首组顶边 0.5（`styles/editor.css:522-523`） | `slashGroupHeader` 8136–8151：横 9、首组 top 2、bottom 2、无 tracking/textCase；非首组 Rectangle 纵 padding 6 | 组头改 H 8、top 6、bottom 4、`tracking(0.385)`、`textCase(.uppercase)`；非首组改顶缘 overlay 边线且不另加纵向 spacer。 | 否 |
| J2-F23 | #59 快捷键丸 opacity 缺失 | shortcut 丸 pad 3/6、radius 6、11 mono；面板内最终 `opacity:0.78 !important`（`styles/editor.css:524、872-876`） | `slashRow` 8219–8229：pad/字号/圆角已同，无 opacity | 给 shortcut 丸整体加 `.opacity(0.78)`（文字与底一起），其余度量不变。 | 否 |
| J2-F24 | #60 最近丸形态错 | base：pad 2/6、radius 999、glass-control 底、0.5 glass-control 边、glass-label 色、字 10；面板覆盖字 11（`styles/editor.css:525、866-870`） | `slashRow` 8200–8210：字 10、`T.textSecondary`、H 5/V 2、fillHover 底、radius 6、无边 | 最近丸改字 11、`T.glassLabel`、H 6/V 2、Capsule 的 `T.glassControlTint` 底 + `T.glassBorder` 0.5 边。 | 否 |
| J2-F25 | #61 斜杠空态形态错 | 容器 pad 24/12/20、主文 13/次级/行高 1.5；图标 SVG 28、opacity 0.45、下距 8；提示 11/行高 1.7/opacity 0.75，kbd 10/1.4、pad 1/5、radius 4（`src/editor/render.rs:914-936`；`styles/editor.css:527-530`） | `slashEmptyState` 8101–8123：纵 pad 24/24、图标 24、主文 14 semibold 主色、提示 12；`slashKbd` 8126–8133 为 11、pad 2/5、radius 6 | 空态改 pad 24/12/20、图标 28、主文 13 regular 次级、提示 11 次级 0.75，kbd 改 10、pad 1/5、radius 4。 | 否 |
| J2-F26 | #64 链接输入框边框/横距 | min-height 44、padding 9/11、1px `--border-color` 边、radius 10、字 14/1.4、fill-subtle 底（`styles/editor.css:1374`） | `linkFormPanel` 8262–8275：横 pad 12、无纵 pad、无边框、radius 10、fillSubtle | 输入框改 H 11/V 9，并以 `T.borderSoft` 1px 描边圆角 10（该令牌即原生 `--border-color` 对应值）。 | 否 |
| J2-F27 | #66 链接动作钮字号/最小宽 | 两钮同规：min-width 76、min-height 44、padding 0/14、1px 边、radius 999、字 600 13/1；提交钮边透明（`styles/editor.css:1377-1378`） | `linkFormPanel` 8285–8301：两钮均字 14 semibold、H 16、无 min-width、无边框 | 两钮统一改字 13 semibold、H 14、`frame(minWidth:76, minHeight:44)`；取消钮加 `T.borderSoft` 1px Capsule 边，提交钮加透明 1px 边保持同盒。 | 否 |
| J2-F28 | #72 徽章面板窄屏宽/滚动区 | 面板固定宽 320、max-height 360、padding 14、整体 overflow-y auto（`styles/base.css:692`） | `ErrBadgeOverlay` 2836–2838：宽 `min(320, vw-32)`；panel 2887 起，ScrollView 2942 独立 `maxHeight:280` | 面板宽改固定 320，panel 本体加 `frame(maxHeight: 360)`，ScrollView 改弹性占余高、不再写死 280。 | 否 |
| J2-F29 | #74 徽章标题错误态色错 | ERROR 标题色 `--color-danger-light:#FF6B6B`，WARN 用 `--color-warning`（`styles/tokens.css:79-80`；`src/errbadge.rs:156-160`） | panel 2890–2895：ERROR 标题用 `T.dangerBright`（#FF3B30/#FF453A）；T 无 dangerLight | 新增 `T.dangerLight = dyn(0xFF6B6B, 0xFF6B6B)`，仅 panel 标题 ERROR 态改用之，徽章底与条目图标仍用 dangerBright。 | 是：`T.dangerLight` |
| J2-F30 | #75 清除钮无内距/圆角 | 11px、次级色、padding 2/6、radius 6（`styles/base.css:695`） | panel 2897–2901：11、次级色，无 padding、无圆角命中形 | 清除钮加 H 6/V 2 padding 与 radius 6 的 contentShape/背景形（保持透明底）。 | 否 |
| J2-F31 | #76 徽章条目图标偏小 | 条目 gap 6、纵 pad 8、图标 SVG 14（`src/errbadge.rs:194`；`styles/base.css:696-697`） | panel 条目 2909–2914：gap 6、纵 pad 8 已同，图标 SF 12 | 条目图标字号改 14，其余条目度量不变。 | 否 |

## 二、MD 微差组与 #46/#52

| 编号 | 报告条目 | Web 真值（源文件:行号） | 原生现行值（MomentApp.swift 落点） | 目标改法（一句） | 涉及令牌新增 |
|---|---|---|---|---|---|
| J2-M01 | §3.4 预览链接/Wiki 色与线型缺失 | 普通链接：`--md-link-color` #005BBB/#72B7FF、下划线 0.08em、offset 0.16em（`styles/editor.css:116-118`；`styles/tokens.css:18、221`）；Wiki 同色 + 虚线、offset 0.18em（`styles/editor.css:294-295`）；渲染支 `src/blocks.rs:1469-1500` | `MdRender.runs` 9470–9495：Link 有 `_link`+underline，Wiki 只塞 `wiki:` URL、无 wiki 标记；`Marks.attributed` 1731–1733 只设 `.link`，不设前景色/线型 | MdRender 给 Wiki run 加 `wiki:true`，Marks 对所有 `_link` 设 `T.linkBlueUI` 前景 + 单线，Wiki 另设 dashed underline pattern（线宽/offset 在 NSAttributedString 无对应面，登记近似）。 | 是：`T.linkBlueUI`（既有 `T.linkBlue` 的 UIColor 伴生） |
| J2-M02 | §3.4 脚注回链缺失 | 每项按 `ref_ids` 输出 ↩ 回链；容器 margin-left 0.35em、gap 4，回链最小 32×32、link 色、radius 6（`src/blocks.rs:2047-2065`；`styles/editor.css:308-311`） | `MdBlockView` 的 `Footnotes` 9879 起只渲染序号 + blocks，未消费 item 的 `ref_ids`、无 ↩ | 读取 `item["ref_ids"]`，在该项 blocks 后以 gap 4、leading 4.6 的行追加每个 ↩ 的 32×32 `T.linkBlue` 命中盒；锚点跳转动作见存疑子项。 | 否 |
| J2-M03 | §3.4 删除线底色缺失 | Del 渲染为 `.moment-strikethrough`（`src/blocks.rs:1460-1462`）；底 `--fill-hover`、padding 0 2px（`styles/editor.css:375`） | `Marks.attributed` 1727–1730：strikethrough run 只设删除线，无 backgroundColor | strikethrough 分支同步设 `.backgroundColor = T.fillHoverUI`；横 2px padding 在 NSAttributedString 无对应面，沿既有行内标记近似口径登记。 | 是：`T.fillHoverUI`（既有 `T.fillHover` 的 UIColor 伴生） |
| J2-M04 | §3.4 表格外框/横滚/单元格距 | table：横滚、width max-content、min 160/max 100%、`--card-bg`、1px 边、radius 12；th/td 横 pad 12、td max-width 18rem=288（`src/blocks.rs:2018-2045`；`styles/editor.css:2-16`） | `MdBlockView` 的 `Table` 9829–9877：Grid 横 spacing 12、cell 无横 pad、无底/边/圆角/横滚/288 上限 | Table 包进横向 ScrollView：cell 改 H 12 且 Grid 横 spacing 0、cell maxW 288，整体加 `T.cardBg` + `T.borderSoft` 1px + radius 12 裁切。 | 是：`T.cardBg`（#FFFFFF/#1C1C1E） |
| J2-M05 | §3.4 长代码横滚（待裁） | pre：`white-space:pre`、`overflow-x:auto`、pad 12/14、13/1.6、codeBg、1px 边、radius 12（`src/blocks.rs:1897-1904`；`styles/editor.css:36`） | `MdBlockView` 的 `Code` 9722–9738：普通 SwiftUI Text，软换行；pad/底/边/圆角已同 | **存疑不直接落码**：若裁定跟 Web，则包横向 ScrollView + Text `lineLimit(1)`/`fixedSize(horizontal:true)`；若裁定手机软换行等价更优，则本项销账保留。 | 否 |
| J2-M06 | §3.4 Callout 五变体图标色非令牌 | 图标 markup 统一引 `--md-callout-*-icon`（`src/icons.rs:179-189`）；浅色 note/warning/tip/important/caution = #005BBB/#AD5F00/#1C7A34/#8436AA/#B3261E（`styles/tokens.css:37-41`），深色 = #72B7FF/#FFBD66/#75E29A/#D39BED/#FF8178（`styles/tokens.css:236-240`） | `T.calloutAccent` 11203–11210：#007AFF/#D97706/#2EA043/#8250DF/#E0433A 及另一组系统色深色值，均非 Web 令牌 | 直接替换 `calloutAccent` 五个 dyn 对为 Web 浅/深十值，函数与调用点不变。 | 否（既有函数改值） |
| J2-M07 | §1.3 #46 标题前距未修满 | 标题 margin-top 1.25em、字号 h1–h4 = 28/23/20/17，故净前距 35/28.75/25/21.25；正文段下距 0.65em=10.4 被标题上距压过（`styles/editor.css:87-98`；`styles/tokens.css:15-20`） | `MdPreviewView` 10301 统一 spacing 10；`headingExtraTop` 10290–10297 现补 15/11/9/7，合成 25/21/19/17 | `headingExtraTop` 的 h1–h4 改补 25/18.75/15/11.25，使 spacing 10 合成净距恰为 35/28.75/25/21.25（h5/h6 不在本项）。 | 否 |
| J2-M08 | §1.3 #46 附带：非标题块前距（报告口径需更正） | 各块自身 margin-top 按自身字号：pre 0.75em×13=9.75、quote/callout 0.75em×14=10.5、table 0.8em×14=11.2、list 0.4em×16=6.4；段下距 10.4，CSS 相邻边距折叠取较大者（`styles/editor.css:2-8、20-24、36、98-106`） | `MdPreviewView` 10301 对所有块统一 spacing 10，无按前后块组合的折叠边距函数 | **存疑不直接落码**：报告的统一“12–12.8 / 列表 +3.6”不是净距真值，落码前须先按前后块组合建立折叠边距矩阵，再实现 pair-wise spacing。 | 否 |
| J2-M09 | §1.3 #52 列表文起点残差 | ul/ol `padding-left` = 1.2em/1.4em，正文基字 16，故文起点 19.2/22.4；li 纵 pad 2（`styles/editor.css:20-22、83-85`；渲染支 `src/blocks.rs:1954-2017`） | `MdBlockView` 的 `List` 9788、9798–9805：非任务项 HStack spacing 8 + 标记框宽 18，文起点 26（ul +6.8、ol +3.6）；嵌套子列表递归同差 | 非任务标记支保留框宽 18，HStack spacing 改为 ul 1.2 / ol 4.4，使文起点为 19.2/22.4；嵌套列表递归自动逐层同值，任务勾选支不动。 | 否 |

## 三、回源更正与存疑汇总

### 更正（报告读数与现行源码不符，以源码为准）

1. **Callout 图标色不止浅色五值**：audit2 §3.4 只列浅色令牌；`styles/tokens.css:236-240` 另有深色五值。J2-M06 已按浅/深十值落账，不得把浅色值双写冒充深色。
2. **#46 附带的统一前距读数不成立**：audit2 §1.3 的“pre/quote/callout/table 12–12.8、列表前距 6.4 vs 10（+3.6）”混用了自身 margin 与折叠后净距。CSS `em` 按元素自身字号计算，且相邻纵边距折叠取较大者；例如列表在普通段落之后时，段下距 10.4 会压过列表上距 6.4，净距不是 6.4。故 J2-M08 不得按报告数字直接补统一 spacing。
3. **导出徽章的原生注释已过时**：原生 `exportChoice` 注释写“mono 11/700”，但 Web 最终级联（`src/main.rs:36-38` 的 tokens→base→editor→panels 拼接序）以 `styles/panels.css:239-240` 覆盖为 inherit 字体族 + tracking -0.2；J2-F11 以 panels 为准。
4. **表格 td 字号另有报告冲突（不计入 40 行）**：audit2 §1.3 #53 称 td 16，但现行 `styles/editor.css:7` 的 table 字号为 14，td 无独立字号覆盖、计算值继承 14；原生 `Table` 9861–9865 现用 16。此点与 J2-M04 的外框/横滚同落点但不在 §3.4 条目内，落码阶段须先裁定是把 td 16→14 并入 M04，还是另开更正项，不得继续以“#53 已在位”表述。

### 存疑项

- **J2-M05（长代码横滚）**：Web 真值明确为不换行 + 横滚，但 audit2 自身标注“手机端换行可议等价更优，先登记待裁”；需先裁定跟 Web 还是保留原生软换行，未裁定前不计可落码。
- **J2-M08（非标题块折叠边距）**：目标净距随前后块组合变化，单一常数无法成立；需先产出组合矩阵（至少 Para/Heading/Code/Quote/Callout/Table/List/Divider 两两相邻）或浏览器量测表，再定 pair-wise spacing 函数。
- **J2-M02 动作子项**：↩ 的 32×32 视觉形态可直接落；但 Web 点击回链是锚点跳转，原生 MD 预览当前整块点按回源码、无预览内锚点滚动面，跳转行为不能冒充已对齐，须另定交互口径。

## 四、汇总

- **总项数：40 行**（浮层 31 + MD 9）。
- **可直接落码：38 行**（浮层 31 + MD 7：M01、M02 视觉、M03、M04、M06、M07、M09）。
- **存疑：2 行**（M05、M08），另 M02 的锚点跳转为动作子项存疑。
- **涉及令牌新增：6 行**（F08 `T.purple`、F13 `T.placeholderStrong`、F29 `T.dangerLight`、M01 `T.linkBlueUI`、M03 `T.fillHoverUI`、M04 `T.cardBg`）。
- **落码顺序建议**：先共享落点（F03/F04/F05 的 `menuItem`，连带 F16 卡菜单）→ 各面板局部数值 → 斜杠宽度/锚点（F17/F18 需与 J1 已落的 caret 设施对接复核）→ MD 行内标记（M01/M03）→ MD 块容器（M04/M06/M07/M09）。
