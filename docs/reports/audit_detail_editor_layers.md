# 数值级对齐排查 · 线 2：编辑页页眉与全部浮层（原生 iOS vs Rust Web）

审计时间：2026-11-26。只读审计，未改任何已有文件。
Web 真值来源：`rust/apps/web/styles/{tokens,base,editor,panels}.css`、`rust/apps/web/src/editor/layers.rs`、`rust/apps/web/src/editor/render.rs`（SlashPanel）、`rust/apps/web/src/icons.rs`、`rust/apps/web/src/errbadge.rs`。
原生现行：`rust/apps/ios/app/MomentApp.swift`（下称 Swift 文件，行号以审计时为准）。
口径：等价是底线、原生更优才用原生形态；Web 字重 650 在 SwiftUI 无对应字阶，原生一律以 semibold（600）近似，此系统性近似只在首现处标注，不逐行重复计差。
分类：缺陷待修（附严重度：中/小/微）/ 系统等价更优 / 已定案偏离 / 一致。

## 一、标题坞 EditorHeaderView（Swift 6431–6685）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 1 | 头像钮 | 72×72 圆、glass-control 档（editor.css:1195） | AvatarView size 72（6590） | 0 | 一致 |
| 2 | 标题胶囊 | 高 66、radius 33、padding 0 20、内 gap 3（editor.css:1198） | frame 高 66、glassControl radius 33、pad H20、VStack spacing 3（6636–6647） | 0 | 一致 |
| 3 | 标题文字 | 14px/600、居中、letter-spacing −0.2px、line-height 1.3（editor.css:1203） | 14 semibold、居中、无 tracking（6607–6612） | 字距 −0.2 缺失 | 缺陷待修（微） |
| 4 | meta 行 | 10px、次级色、line-height 1.2（editor.css:1213） | 10、T.textSecondary（6630–6634） | 0 | 一致 |
| 5 | 坞两态 gap | 列态 6 / 横排态 8（editor.css:1193–1194） | VStack spacing 6 / HStack spacing 8（6465–6480） | 0 | 一致（紧凑横排为已定案形态） |
| 6 | 胶囊最大宽钳制 | 坞左右各 62 → 最大宽 = 视口宽 −124（editor.css:1193） | maxW = headerW −108；紧凑态 −188（Web 为 −204）（6666–6683） | 原生宽 16（两态同） | 缺陷待修（小） |
| 7 | 胶囊最小宽 | min-width 66（editor.css:1198） | max(…, 66)（6683） | 0 | 一致 |
| 8 | 坞顶距 | top = safe-area + 7（editor.css:1193） | 安全区内 padding top 7（6485） | 0 | 一致 |
| 9 | 两侧悬浮钮 | 46×46、left/right 16、top safe+7、radius 50%（editor.css:209–231） | 46×46、HStack 横距 16、glassControl radius 999（6449–6463、6497–6510） | 0 | 一致 |
| 10 | 悬浮钮图标字形 | back/dots SVG 22×22（icons.rs:164、206） | SF Symbol font 17 semibold（6453、6501） | 字形约 −5 | 缺陷待修（微） |
| 11 | 动效时长 | 坞切换 transition all 0.25s、胶囊变宽 0.2s（editor.css:1193、1198） | animation 0.25 / 0.2 easeInOut（6443、6648） | 0 | 一致 |

## 二、••• 菜单 menuPanel / menuItem（Swift 6763–6795、6945–6990）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 12 | 面板 | 宽 246、radius 22、内距 7（.menu-inner）、right 16、top = safe+7+46+6 = safe+59（editor.css:1230、1240） | 宽 246、radius 22、padding 7、trailing 16、安全区内 top 59（6790–6794） | 0 | 一致 |
| 13 | 菜单项盒 | min-height 50、padding 8px 10px、radius 17（editor.css:1241） | minHeight 50、pad H10、无纵向 padding（内容高 ≈34 由 minHeight 主导）、按压高亮 RowPressStyle() 默认 radius 12（6978–6984；8954） | 按压高亮圆角 −5 | 缺陷待修（微） |
| 14 | 菜单项图标 | slot 24×24、SVG 20、stroke 2.5、accent（editor.css:1245–1246；layers.rs:728 等） | slot 24×24、SF Symbol font 17（6955–6958） | 字形 −3 | 缺陷待修（微） |
| 15 | 菜单项文字 | 标题 15/650、letter-spacing −0.1；副 11、margin-top 2（editor.css:1248–1249） | 标题 15 semibold、无 tracking；副 11、spacing 1（6960–6970） | 字距缺失、副距 −1（字重 650→600 为字阶近似） | 缺陷待修（微） |
| 16 | chevron | 18px、opacity 0.45、次级色（editor.css:1250） | 18、opacity 0.45、textSecondary（6973–6977） | 0 | 一致 |
| 17 | 撤销/重做置灰行为 | .dis 仅 opacity 0.3、**仍可点**（点按关菜单、动作 no-op；layers.rs:720–724 注释引审计 E-4） | opacity 0.3 且 `.disabled(dimmed)`：点按无响应、菜单不关（6985–6988） | 行为差（非数值） | 缺陷待修（小） |
| 18 | 附件行上距 | margin-top 4（layers.rs:743 内联） | 无（VStack spacing 0） | −4 | 缺陷待修（微） |
| 19 | 背景行上距 | margin-top 4（layers.rs:788 内联） | 无 | −4 | 缺陷待修（微） |
| 20 | 背景行图标色 | stroke var(--color-purple) #AF52DE（layers.rs:792；tokens.css:82） | T.accent（蓝色）（6957） | 色差 | 缺陷待修（微） |
| 21 | 导出分节 | .menu-section：border-top 0.5 + margin-top 3 + padding 10px 0 7px 包住导出行（editor.css:1400；layers.rs:772） | 无分节、六项平铺 | 分节缺失（连带导出行纵向距 −17） | 已定案偏离（六项无分隔线，2026-11-26 裁定） |
| 22 | 双栏行盒 | min-height 56、padding 8px 10px、radius 17（editor.css:896–912） | minHeight 50、pad H10（7242–7267） | 行高 −6 | 缺陷待修（小） |
| 23 | 双栏行文字/图标 | 标题 14/650、副 11、图标 slot 24 / SVG 20 / stroke 1.8（editor.css:918–935；layers.rs:706–716） | 标题 15 semibold、副 11、图标 font 17（7244–7256） | 标题 +1、字形 −3 | 缺陷待修（小） |
| 24 | 双栏开关 | 自绘轨道 42×26、钮 20、内距 3、行程 16（tokens.css:183–187） | 系统 Toggle（约 51×31）（7260–7264） | — | 系统等价更优（已定案：系统 Toggle 口径） |
| 25 | 面板最大高 | max-height = 100dvh − safe − 64、超出滚动（editor.css:1230） | 无上限（固定 5–6 行 ≈ 364） | 矮屏/横屏下可溢出 | 缺陷待修（微） |

## 三、导出面板 exportPanel / exportChoice（Swift 6831–6951）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 26 | 面板 | 宽 246、radius 22、内距 7、right 16、top safe+59（editor.css:1230）；max-width 经 panels.css:232 改为 100vw−32 | 宽 246、radius 22、padding 7、trailing 16、top 59（6902–6906） | 0（max-width 仅屏宽 <278 时有别） | 一致 |
| 27 | 面板头 | min-height 46、padding 0 4px 5px、下边线 0.5（editor.css:1257） | minHeight 46、pad H4 B5、边线 0.5（6851–6870） | 0 | 一致 |
| 28 | 返回钮/标题 | 钮 46×46 圆玻璃（editor.css:1258）；标题 15/650 居中、padding-right 46 补偿（editor.css:1259） | 钮 46 glassControl 999；标题 15 semibold + 右侧 46 占位补偿（6853–6868） | 0（补偿实现等价） | 一致 |
| 29 | 返回钮图标 | back SVG 22×22（icons.rs:206） | chevron SF font 14（6856） | 字形 −8 | 缺陷待修（微） |
| 30 | 选项区间距 | .export-choices：gap 3、padding-top 6（editor.css:1260） | 选项直接置于 VStack spacing 0、无顶距（6871–6891） | 行间 −3、顶 −6（面板总高 −12） | 缺陷待修（小） |
| 31 | 选项行 | min-height 54、padding 6px 9px、radius 14、gap 11（panels.css:238 覆盖 editor.css 的 56/17） | minHeight 54、pad V6 H9、radius 14、spacing 11（6922–6950） | 0 | 一致 |
| 32 | 格式徽章 | 34×34、透明无底、radius 0、字 11（PDF .sm 为 9）、letter-spacing −0.2、font-family inherit（panels.css:239–240） | 34×34、透明、11/9、design .monospaced、无字距（6924–6930） | 字体族差（等宽 vs 继承字体） | 缺陷待修（微） |
| 33 | 选项文字 | label 14/650；detail 11、margin-top 2（panels.css:242–243） | label 14 semibold；detail 11、spacing 1（6931–6940） | 副距 −1 | 缺陷待修（微） |
| 34 | 选项 chevron | 19px、色 --color-placeholder-strong #C0C0C6、padding-left 4（panels.css:244） | 19、色 T.textSecondary #68686D、无左距（6943–6945） | 色明显偏深、距 −4 | 缺陷待修（微） |
| 35 | 尾注 | margin 5px 4px 2px + padding 9px 5px 2px、顶边线 0.5、字 10、line-height 1.45（panels.css:245） | 边线贴选项区（margin 0）、padding T5 H4 B2、字 10（6893–6913） | 边线 −5、注文 −9 | 缺陷待修（小）；注文文案差为已定案改判（iOS 口径，原生代码注释已登记） |

## 四、背景色底表 bgSheet（Swift 6658–6761；呈现 5760–5798）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 36 | 卡片 | max-width 600、radius 28、padding 20（底 = 20 + safe）（editor.css:1272） | maxWidth 600、radius 28、pad T20 H20 B(20+safeBottom)（6752–6760） | 0 | 一致 |
| 37 | 呈现位 | wrap：左右 14、bottom = safe + 14（editor.css:1267） | pad H14、bottom = safeAreaInsets.bottom + 14（5787–5790） | 0 | 一致 |
| 38 | 表头 | 标题 20/700、letter-spacing −0.3；副 13、主色 opacity 0.7、margin-top 4；头下 margin-bottom 16（editor.css:1273–1275） | 20 bold tracking −0.3；13 opacity 0.7；spacing 4；padding-bottom 16（6671–6683） | 0 | 一致 |
| 39 | 色点网格 | 4 列、gap 12、网格下 margin-bottom 16（editor.css:1276） | LazyVGrid 4 列、spacing 12、padding-bottom 16（6684–6719） | 0 | 一致 |
| 40 | 色点 | 44×44、radius 22、未选边 0.5 黑 12%、选中边 2px accent、对勾 SVG 20 accent（editor.css:1277–1278；layers.rs:872） | 44 Circle、边 0.5/2、对勾 font 20 accent（6690–6713） | 0 | 一致 |
| 41 | 移除区上距 | .bg-remove-wrap：border-top 0.5 + margin-top 4 + padding-top 10（editor.css:1279） | 边线 + 钮 padding-top 10、无 margin-top（6720–6750） | 边线位置 −4 | 缺陷待修（微） |
| 42 | 移除行 | min-height 44、padding 8px 0、radius 16、图标 SVG 20、文 15/650 line-height 24、danger-bright、注 11 次级、行 gap 6、列 gap 2（editor.css:1280–1284；layers.rs:885–889） | minHeight 44、pad V8、RowPressStyle radius 16、图标 font 20、文 15 semibold、注 11、gap 6/2（6725–6748） | 0（字重近似除外） | 一致 |
| 43 | 移除行呈现条件 | 仅当前有背景色时（layers.rs:876 `bg_state.is_some()`） | if bgColor != nil（6720） | 0 | 一致 |
| 44 | 选色生效时点 | 关闭动画 220ms 后经 BgAfter::Apply 生效（layers.rs:824–838） | onChange(of: bgClosing) 220ms 后 setBgColor（5800–5816） | 0 | 已定案（按裁定口径实现） |

## 五、卡片浮层菜单 cardMenuLayer（Swift 6105–6198）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 45 | 面板 | 宽 216、radius 22、内距 7（.menu-inner 复用）、glass-overlay（editor.css:1342、1240） | 宽 216、radius 22、padding 7、overlayCard（6143、6196–6197） | 0 | 一致 |
| 46 | 面板高 | 项 50 × n + 内距 14：有编辑 114 / 无编辑 64（editor.css:1240–1241 推得；layers.rs:168–248） | panelH = hasEdit ? 114 : 64（6117） | 0 | 一致 |
| 47 | 锚点与钳制 | 贴卡下 8、放不下上翻至卡上 8、横向视口 12 钳制（layers.rs:104–150 渲染侧口径） | below = top+bh+8；上翻 top−8−panelH；panelLeftX 钳 12（6119–6124、6131–6152） | 0 | 一致 |
| 48 | 菜单项度量 | 与 ••• 菜单同 .menu-item（editor.css:1241） | 复用同一 menuItem（6170–6195） | 同 #13/#14（高亮圆角 −5、图标字形 −3） | 缺陷待修（微，随 menuItem 一并修） |
| 49 | 项构成 | 编辑（has_edit 类）+ 删除此块（danger）（layers.rs:168–248） | 同（6170–6195） | 0 | 一致 |

## 六、斜杠面板 slashPanel / slashRow（Swift 6199–6410；呈现 5686–5724）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 50 | 面板本体 | radius 22、padding 8、max-height 320、glass-overlay（editor.css:1368） | radius 22、内容 padding 8、maxHeight 320、overlayCard（6239–6247） | 0 | 一致 |
| 51 | 面板宽 | min(360, max(220, 内容估宽+12, vw−24))（render.rs:626–652） | min(360, vw−32)（5702） | 典型机 −2、窄屏（360 宽）−8 | 缺陷待修（微） |
| 52 | 面板纵向锚 | top = 锚底 + 10；放不下按 260 估高上翻，且 max-height 随锚位动态收缩（render.rs:653–663） | 块下 +8；按固定 320 估高以 .position 定中心（5704–5716） | 间距 −2；**实际高 <320 时（过滤/最近态）面板中心下移 (320−实际高)/2，短列表可达约 100** | 缺陷待修（中） |
| 53 | 面板横向锚 | left = min(视口右对齐, anchor_x−8)、钳 12（render.rs:652） | 栏左缘锚 panelLeftX（5718–5722） | 锚法不同（靠右输入时 Web 随光标右移、原生恒左） | 缺陷待修（微；0.9.22 实现选择，非用户裁定） |
| 54 | 行盒 | min-height 48、padding 7px 9px、gap 10、radius 14、margin 1px 0（editor.css:486–503） | minHeight 48、pad V7 H9、spacing 10、RowPressStyle radius 14（6392–6408） | 0（行间 margin 见 #57） | 一致 |
| 55 | 行图标 | slot 24×24、SVG 20（editor.css:509–517） | slot 24×24、SF font 19（6355–6358） | 字形 −1 | 缺陷待修（微） |
| 56 | 行文字 | 标题 14/650 line-height 1.25；副 12 line-height 1.35；文案列 gap 2（editor.css:518–521） | 标题 14 semibold；副 12；VStack spacing 1（6359–6385） | 副距 −1 | 缺陷待修（微） |
| 57 | 行间外距 | margin 1px 0（相邻行间 2）（editor.css:491） | VStack spacing 0 | 行间 −2 | 缺陷待修（微） |
| 58 | 分组头 | padding 6px 8px 4px、11/700、letter-spacing 0.035em、opacity 0.8、非首组 border-top 0.5（editor.css:522） | 边线 + 纵向 padding 6、文字 pad H9 / 首组 top 2、11 bold、opacity 0.8、无字距（6318–6348） | 左距 +1、首组顶距 −4 | 缺陷待修（微） |
| 59 | 快捷键丸 | padding 3px 6px、radius 6、11 mono、面板内 opacity 0.78（editor.css:524、872–876） | pad V3 H6、radius 6、11 mono、无 0.78（6395–6405） | 不透明度差 | 缺陷待修（微） |
| 60 | 最近使用丸 | padding 2px 6px、radius 999、面板内字 11（!important）、glass-control 底 + 0.5 边（editor.css:525、866–870） | pad V2 H5、radius 6、字 10、fillHover 底无边（6378–6390） | 圆角 999→6、字 −1、底/边差 | 缺陷待修（微） |
| 61 | 空态 | padding 24px 12px 20px、图标 SVG 28、主文 13 次级色、提示 11（editor.css:526–528；render.rs:911–930） | pad V24、图标 font 24、主文 14 semibold 主色、提示 12（6252–6278） | 图标 −4、主文 +1 且色/字重差、提示 +1 | 缺陷待修（小） |

## 七、链接表单 linkFormPanel（Swift 6362–6430）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 62 | 表单盒 | 面板内原地替换：form padding 5px 4px 3px、gap 10（editor.css:530）；叠面板 padding 8 后合计横 12 / 顶 13 | 独立面板 padding 12、spacing 10（6410–6460） | ≈0（合计口径近同） | 一致 |
| 63 | 表单标题 | 14/650（editor.css:531） | 14 semibold（6412） | 0（字阶近似） | 一致 |
| 64 | 输入框 | min-height 44、padding 9px 11px、border 1px、radius 10、字 14/1.4（editor.css:532） | minHeight 44、pad H12、无边框、radius 10、字 14（6425–6445） | 横距 +1、边框缺失 | 缺陷待修（微） |
| 65 | 错误行 | 12、danger、line-height 1.4（editor.css:534） | 12、T.danger（6447–6450） | 0 | 一致 |
| 66 | 动作钮 | min-width 76、min-height 44、padding 0 14、radius 999、字 600 13/1（editor.css:536） | minHeight 44、pad H16、无 min-width、字 14 semibold（6453–6472） | 字 +1、横距 +2、取消钮宽约 −16 | 缺陷待修（微） |
| 67 | 动作行 | gap 8、右对齐、padding-top 2（editor.css:535） | gap 8、右对齐（顶距由表单 spacing 10 承担）（6452） | ≈0 | 一致 |

## 八、错误徽章 errBadgeLayer（Swift 5986–6104；本轮刚移植，核对）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 68 | 徽章盒 | 36×36、radius 18、right 16、bottom = safe + 64（base.css:687） | 36×36、radius 18、trailing 16、bottom = safeBottom + 64（6028–6046） | 0 | 一致 |
| 69 | 徽章内文 | 「!」12/700 + 计数 10/600、gap 2、白色（base.css:689–691） | 12 bold + 10 semibold、spacing 2、白（6018–6030） | 0 | 一致 |
| 70 | 徽章底色 | 有非 WARN 条目红 --color-danger-bright #FF3B30、纯 WARN 黄 --color-warning #FF9500（base.css:680–687 注释；errbadge.rs:141–148） | T.dangerBright #FF3B30 / T.warning #FF9500（6042–6044；8739–8760 区令牌） | 0 | 一致 |
| 71 | 徽章进场 | ebFadeIn 0.2s（挂载淡入）（base.css:687–688） | opacity transition + 0.2s animation（按 entries.count 变化触发，后续新增亦重播）（6052–6056） | 近同（重播范围略宽） | 一致 |
| 72 | 面板盒 | 宽 320、right 16、bottom = safe + 108、radius 20、padding 14、max-height 360（base.css:692） | 宽 min(320, vw−32)、底 = 64+36+8 = safe+108、radius 20、padding 14、滚动区 maxHeight 280（总高 ≈341）（5990–5996、6096–6103） | 窄屏宽 −8、滚动区 −19 | 缺陷待修（微） |
| 73 | 面板头 | 标题 13/700、头下 margin-bottom 10（base.css:693–694） | 13 bold、padding-bottom 10（6061–6072） | 0 | 一致 |
| 74 | 面板标题色 | 有错误 --color-danger-light #FF6B6B / 纯警告 --color-warning（errbadge.rs:150–158；tokens.css:79–80） | T.dangerBright #FF3B30 / T.warning（6064–6066） | 错误态色差 | 缺陷待修（微） |
| 75 | 清除钮 | 11px、padding 2px 6px、radius 6、次级色（base.css:695） | 11、次级色、无内距无圆角底（6068–6070） | 命中区偏小 | 缺陷待修（微） |
| 76 | 条目 | padding 8px 0、gap 6、图标 SVG 14、消息 12/600、meta 10 margin-top 3、条间 0.5 线（base.css:696–701） | pad V8、spacing 6、图标 font 12、消息 12 semibold、meta 10 spacing 3、0.5 线（6076–6100） | 图标字形 −2 | 缺陷待修（微） |
| 77 | 条目 loc/stack | 有 loc 与 stack（9px、上限高 60）（base.css:701–703；errbadge.rs 条目结构） | 无（仅消息 + 时间，详情由 Diag 承接） | 内容面缺失 | 已定案偏离（移植口径：原生投递点无堆栈来源） |

## 九、音乐胶囊 MusicPillView（Swift 7354–7401）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 78 | 输入胶囊 | padding 12px 18px、radius 999、字 14、glass-control 档（editor.css:457） | pad V12 H18、glassControl radius 999、字 14（7396–7400） | 0 | 一致 |
| 79 | 胶囊内 gap | gap 10（editor.css:457） | HStack spacing 8，内仅输入框一元素、gap 无作用对象（7366） | — | 一致（无对象） |

## 十、键盘上方栏

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|------|----------|----------|------|------|
| 80 | 键盘上方「完成」 | Web 无对应（浏览器环境无键盘附件栏概念） | 两路并存：UITextView 块走 inputAccessoryView UIToolbar + 「完成」（1451–1462）；SwiftUI 标题框走 .toolbar(.keyboard)「完成」（5809–5817），按第一响应者类型分工 | — | 系统等价更优（原生专属机制，无 Web 数值真值可对） |

## 汇总

- 总条数 80：一致 38、缺陷待修 37（中 1 / 小 7 / 微 29）、系统等价更优 2（#24、#80）、已定案偏离 3（#21、#44、#77；#5、#24 另含定案形态注记不重复计）。
- 缺陷集中形态：① 图标字形系统性偏小（SF Symbol font 号 < Web SVG 号，#10/#14/#23/#29/#55/#76，−1～−8）；② 纵向小距成组缺失（#18/#19/#30/#35/#41/#57，多为 2–9px）；③ 个别行为差（#17 置灰禁用、#52 斜杠面板估高定位）。
- 数值全对齐面：标题坞主体（除字距/最大宽钳制）、bgSheet 全面、卡菜单几何、导出行本体、错误徽章主体、音乐胶囊。
