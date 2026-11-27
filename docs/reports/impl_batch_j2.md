# 修复批 J2 落码对账（浮层 31 + MD 9 = 40 项）

- 阶段：落码完成（未提交、未 bump；落版号由主线统一排）。
- 依据：`plan_batch_j2_specs.md`（40 项账）；逐项回源现行 Web 源码复核（`styles/editor.css`、`styles/panels.css`、`styles/base.css`、`styles/tokens.css`、`src/editor/render.rs`、`src/editor/layers.rs`、`rust/crates/core/src/md.rs`），规格与源码无冲突项；一处裁定见 M04。
- 改动面：仅 `rust/apps/ios/app/MomentApp.swift`（编辑器浮层与 MD 呈现区）+ `verify_ios.sh` 新增 [20] 组。未碰设置区、救援/启动文件、FFI（并行天气线与自救线的同树改动区域错开、互不覆盖，diff hunk 已核）。
- 结果：38 项可落码项全部已修；2 项存疑（M05、M08）按规格未落码；M02 视觉已落、锚点跳转动作子项仍存疑。

## 一、浮层 31 项逐项对账

| 编号 | 状态 | 落点与说明 |
|---|---|---|
| J2-F01 | 已修 | `titleCapsule` 两呈现分支（TextField/截断 Text）加 `tracking(-0.2)`；`capsuleWidth` 量测 attributes 同步加 `.kern: -0.2`，防宽量测与呈现字距不一致导致的溢出/误截。 |
| J2-F02 | 已修 | `headerOverlay` back/ellipsis 字形 17→22 semibold，46×46 玻璃钮不变。 |
| J2-F03 | 已修 | `menuItem` 按压样式显式 `RowPressStyle(radius: 17)`；全局默认 12 未动。 |
| J2-F04 | 已修 | `menuItem` 图标字号 17→20，槽 24×24 不变。 |
| J2-F05 | 已修 | `menuItem` 标题加 `tracking(-0.1)`，文案列 spacing 1→2。 |
| J2-F06 | 已修 | 附件 `menuItem` 调用点加 `.padding(.top, 4)`。 |
| J2-F07 | 已修 | 背景 `menuItem` 调用点加 `.padding(.top, 4)`。 |
| J2-F08 | 已修 | 新增令牌 `T.purple = dyn(0xAF52DE, 0xAF52DE)`；`menuItem` 加 `iconColor` 参数（默认 nil 回落 accent、danger 优先），背景行传 `T.purple`。 |
| J2-F09 | 已修 | `exportPanel` 返回钮 chevron 字号 14→22 semibold。 |
| J2-F10 | 已修 | 三条 `exportChoice` 包进 `VStack(spacing: 3)` 并加 `.padding(.top, 6)`。 |
| J2-F11 | 已修 | 徽章删 `design: .monospaced`（回落系统默认字体族 = Web inherit 最终级联）、加 `tracking(-0.2)`；过时注释已按 panels.css:239-240 更正。 |
| J2-F12 | 已修 | `exportChoice` 文案列 spacing 1→2。 |
| J2-F13 | 已修 | 新增令牌 `T.placeholderStrong = dyn(0xC0C0C6, 0xC0C0C6)`；chevron 改用之并加 `.padding(.leading, 4)`。 |
| J2-F14 | 已修 | 尾注拆两层：外层 margin（top 5 / H 4 / bottom 2）+ 内层 padding（top 9 / H 5 / bottom 2），顶线 overlay 挂内层顶缘，文字加 `lineSpacing(4.5)`（= 10 × 1.45 − 10）。 |
| J2-F15 | 已修 | `bgSheet` 移除区 Rectangle（边线）前加 `.padding(.top, 4)`；线后 Button 既有 top 10 保留。 |
| J2-F16 | 已修 | 卡菜单（`cardMenuPanel`）与块转换菜单（`blockMenuPanel`）均复用同一 `menuItem`，F03/F04 落码后 radius 17 与图标 20 同步生效，无另写数值。 |
| J2-F17 | 已修 | 新增 `slashPanelWidth(viewW:)`：逐项移植 render.rs:637-650 公式（行估宽 24+10+标题字数×16+(shortcut 时 8+字数×8)+22、group>0 再 +20、初值 240；宽 = min(360, max(220, maxContent+12, viewW−24))），遍历 `SlashCmds.all` 全命令；`slashLayer` 弃 `min(360, vw−32)` 改用之。标题取当前呈现串（SlashCmds 数据表即呈现源，与 Web `i18n::t()` 同源口径，I4 换键后自动跟随）。 |
| J2-F18 | 已修 | 新增锚点链：`EditorModel.slashAnchorX`（@Published）；`textViewDidChange` 以选区末端 `caretRect` 换算窗口 X，随 `updateSlash(for:selUTF16:caretX:)` 写入；`slashPanelLeft` 按 Web 公式 left = min(viewW−panelW−12, anchorX−8) 钳 ≥12 定位（编辑器整屏呈现，窗口 X 与面板层坐标同源，vx=0）。Diag 同步：面板新开记 `SLASH open id= anchorX=` 一行供结果侧判读。 |
| J2-F19 | 已修 | `slashRow` 图标字号 19→20，槽 24×24 不变。 |
| J2-F20 | 已修 | `slashRow` 文案列 spacing 1→2。 |
| J2-F21 | 已修 | `slashRow` 根 Button 加 `.padding(.vertical, 1)`（行间合成 2、首尾各 1）。 |
| J2-F22 | 已修 | `slashGroupHeader` 重构：H 8 / top 6 / bottom 4、`tracking(0.385)`、`textCase(.uppercase)`、次级色 opacity 0.8 保留；非首组改顶缘 overlay 边线（`T.borderSoft` = --border-color 对应令牌）贴组头盒顶，删旧 Rectangle + 纵向 padding 6 的 spacer 形态。 |
| J2-F23 | 已修 | shortcut 丸整体加 `.opacity(0.78)`（文字与底一起，挂在 background 之后）。 |
| J2-F24 | 已修 | 最近丸改：字 10→11、色 `T.textSecondary`→`T.glassLabel`、pad H 5→6 / V 2、底 `T.fillHover`→`T.glassControlTint`（Capsule）、加 `T.glassBorder` 0.5 胶囊边。 |
| J2-F25 | 已修 | `slashEmptyState` 重构：padding 改 top 24 / H 12 / bottom 20（弃纵 24 对称）、图标 24→28（opacity 0.45 保留、下距 8）、主文 14 semibold 主色→13 regular 次级色、提示行字 12→11 + opacity 0.75 + 上距 8；`slashKbd` 改字 10、pad V 1、radius 4。 |
| J2-F26 | 已修 | 链接输入框改 H 11 / V 9，加 `T.borderSoft` 1px 圆角 10 描边（overlay），fillSubtle 底与 min-height 44 不变。 |
| J2-F27 | 已修 | 两钮统一：字 14→13 semibold、H pad 16→14、`.frame(minWidth: 76, minHeight: 44)`；取消钮加 `T.borderSoft` 1px Capsule 边，提交钮加透明 1px Capsule 边同盒。 |
| J2-F28 | 已修 | `ErrBadgeOverlay` 面板宽 `min(320, vw−32)`→固定 320；panel 本体加 `.frame(maxHeight: 360)`；ScrollView 删写死 `maxHeight: 280`、弹性占余高。 |
| J2-F29 | 已修 | 新增令牌 `T.dangerLight = dyn(0xFF6B6B, 0xFF6B6B)`；仅 panel 标题 ERROR 态改用之，徽章底与条目图标仍 `T.dangerBright`。 |
| J2-F30 | 已修 | 清除钮加 H 6 / V 2 padding + radius 6 `contentShape`，保持透明底、无背景填充。 |
| J2-F31 | 已修 | 条目图标字号 12→14，gap 6 / 纵 pad 8 不变。 |

## 二、MD 9 项逐项对账

| 编号 | 状态 | 落点与说明 |
|---|---|---|
| J2-M01 | 已修 | `MdRender.runs` 的 Wiki 支加 `"wiki": true` 标记；`Marks.attributed` 的 `_link` 支统一设 `.foregroundColor = T.linkBlueUI`（新增 UIColor 伴生令牌，与 `T.linkBlue` 同值）+ 单线下划线，Wiki 另或上 `patternDash`。线厚 0.08em / offset 0.16em（Wiki 0.18em）在 NSAttributedString 无对应面，沿行内代码 padding 先例登记近似（注释在位）。编辑面 runs 若带 _link 同受此规则，与 Web `.editor-body a` 同 CSS 规则一致、非外溢。 |
| J2-M02 | 视觉已修 / 动作存疑 | `MdBlockView.Footnotes` 消费 core JSON 的 `ref_ids`（键名经 `rust/crates/core/src/md.rs:2081` 核实），每项 blocks 后以 HStack（gap 4、leading 4.6 = 0.35em×13）逐个出 ↩ 的 32×32 `T.linkBlue` 命中盒。锚点跳转动作仍存疑：原生预览整块点按回源码、无预览内锚点滚动面，本项不冒充已对齐，待另定交互口径。 |
| J2-M03 | 已修 | `Marks.attributed` 删除线支同步设 `.backgroundColor = T.fillHoverUI`（新增 UIColor 伴生，与 `T.fillHover` 同值 0x7F7F7F@0.06）；横 2px padding 无对应面，登记近似。 |
| J2-M04 | 已修（含字号更正裁定） | `Table` 包横向 ScrollView：Grid 横 spacing 12→0、cell 加 H pad 12、cell `.frame(maxWidth: 288)`、整体加 `T.cardBg`（新增令牌 #FFFFFF/#1C1C1E）+ `T.borderSoft` 1px + radius 12 裁切、`.frame(minWidth: 160)`。**更正项裁定（规格 §三.4）**：Web `editor.css:7` 表格字号 14、td 无独立覆盖继承 14，audit2 #53 的「td 16」系误读——因与本项同落点、同规则块，裁定并入 M04 一并改：td 字号 16→14，不另开更正项。行间 Divider 分隔为既有原生形态、本项未动。 |
| J2-M05 | 存疑未落码 | 长代码横滚：Web 真值（pre 不换行 + 横滚）与「手机软换行等价更优」未裁定，按规格不落码、不销账。 |
| J2-M06 | 已修 | `T.calloutAccent` 五变体 dyn 对整组替换为 Web 图标令牌十值：note #005BBB/#72B7FF、tip #1C7A34/#75E29A、warning #AD5F00/#FFBD66、important #8436AA/#D39BED、caution #B3261E/#FF8178（tokens.css:37-41 / 236-240 回源核实）；函数签名与调用点不变。注：`calloutBg` 不在本项范围，未动。 |
| J2-M07 | 已修 | `headingExtraTop` h1–h4 改补 25/18.75/15/11.25，与统一 spacing 10 合成净距恰 35/28.75/25/21.25；h5/h6 不在本项——原三元链 else 分支本含 h4+，已显式拆分：level==4 才给 11.25，h5/h6 维持旧值 7 不变。 |
| J2-M08 | 存疑未落码 | 非标题块折叠边距：报告统一读数已被规格更正证伪，须先产出前后块组合折叠矩阵再定 pair-wise spacing，未落码、不销账。 |
| J2-M09 | 已修 | `MdBlockView.List` 非任务支 HStack spacing 改公式 `max(0, (ordered ? 1.4 : 1.2) × baseSize − 18)`：基字 16 时 ul 1.2 / ol 4.4，文起点恰 19.2/22.4；em 按容器字号缩放（quote 14 / 脚注 13 同理），嵌套子列表递归逐层同值；任务勾选支 spacing 恒 8 不动；小字号下钳 0（标记框 18 为既有原生几何，负距无意义）。 |

## 三、新增令牌（6）

`T.purple`（F08）、`T.placeholderStrong`（F13）、`T.dangerLight`（F29）、`T.cardBg`（M04）、`T.linkBlueUI`（M01，既有 linkBlue 的 UIColor 伴生）、`T.fillHoverUI`（M03，既有 fillHover 的 UIColor 伴生）。值全部回源 tokens.css 核实，明暗同值项已查深色段无覆盖。

## 四、Diag 打点

新增 1 处：`SLASH open id=<块id> anchorX=<int>`——斜杠面板新开时记一行（`updateSlash` 内、slashBlockId 变更点），供真机判读 F18 锚点链路是否在位（结果侧量测）。其余 37 项为纯呈现度量变更，无新行为面，不加打点。

## 五、verify 断言（新增 [20] 组，12 项，本机自跑全绿）

J20-1 menuItem 共享度量 / J20-2 新令牌四件 / J20-3 标题字距双落点 / J20-4 斜杠宽公式 + 锚 + 打点 / J20-5 斜杠组头·快捷键丸·最近丸 / J20-6 MD 链接色·虚线 + 删除线底 / J20-7 calloutAccent 令牌值（旧值零残留） / J20-8 标题前距补满值 / J20-9 表格横滚·外框·td 14·288 / J20-10 脚注回链 / J20-11 徽章面板宽·限高·标题色（旧 280 写死零残留） / J20-12 列表文起点公式。

既有组等价更新：无（本批改动未迫使任何既有断言改判；[11] J1 组斜杠断言、[14]/[15]/[16]/[17] 全绿）。

本机自跑全量结果：[20] 12/12 绿；其余红仅三条且均非本线——
- `[5] ipa 陈旧`、`[9] 产物语言包`：本机无构建产物（已知口径，tree 构建后消）；
- `[10] S1 组头 topPad 分档缺失`：并行天气线设置区在途改动（其 [18] 组已入库且自绿），非本批落点。

语法自检：本机 swift-frontend 对 MomentApp.swift 单文件及全 app Swift 文件组 `-parse` 均零错误。类型级检查随主线 tree 冒烟（本批未在本机跑全量构建）。

## 六、残余与待裁

1. M05（长代码横滚）、M08（非标题块折叠边距矩阵）、M02 锚点跳转动作：三项存疑维持原状，待裁定后另批。
2. F18 锚点坐标系前提：编辑器经转场宿主整屏 push，窗口 X 与 slashLayer 的 GeometryReader 局部 X 同源；若未来呈现形态改为非整屏（如分栏内嵌），锚点须改走坐标转换，届时以 `SLASH open` 打点 + 面板落位判读为准。
3. M04 表格在 Quote/Callout 等窄容器内的横滚行为与 Web 同构（容器内横滚），真机判读时留意嵌套滚动手势竞争（与既有横滚面同风险级）。
