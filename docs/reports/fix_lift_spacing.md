# 卡片留白根治 + 复合卡内角规矩 + 浮层内容定高（0.9.54 暂记）

2026-11-27。起因：用户在 0.9.52 真机连发四张截图判读——①图文卡拾起框与卡面间隙四边不等；②编辑页静态下图文卡右缘几乎贴屏幕边、左缘有明确边距；③图文卡图区与文本条交界的底角呈圆、露白缺口；④编辑页 ••• 菜单面板被拉到近全屏高、内容只占上半。用户三次收束口径：圆角本身没事、拾起框左右间隙没事，问题在**卡片本身的骨架留白**；并立「复合卡内角规矩」与「面板高度随内容」两条规矩，要求全面排查同类根治。本批落码完成（MomentApp.swift + verify_ios.sh [23] 组），未提交、未 bump；工作树同时有 M2 桥批与 [24] 标题批的未提交改动并行，本批只动下列段落。

## 一、定因与证据分级

### 主因（proven）：BlockRow 的 HStack 尾随幻影间距

BlockRow.rowMain 是 `HStack(spacing: todo? 10: 8) { [待办钮] [内容] Spacer}`。HStack 的 spacing 在**每一对**相邻子视图间生效，内容与尾随 Spacer 之间再吃一口：内容槽恒比行盒窄 8（todo 10），且只亏在 trailing 一侧。后果链：

- 静态：满宽卡（图文/混排/链接/音乐/视频/附件）的面 = 内容槽 → 右缘内缩 8。截图二像素实测：imgTextCard 左边距 49px ≈ 16.3pt、右边距 75px = 25pt，差 ≈ 8.7pt ≈ 列 padding 16 的应有对称被 +8 破坏（÷3 换算，1179px 宽截图）。截图三同卡复测：左 48px / 右 (1179−1106)/3 ≈ 24.3pt，同病。
- 拾起：LiftFrame 挂行盒（⊕4），面在槽内 → 右间隙 = 4 + 8 = 12 级。截图一像素实测（imageTextRow 拾起态，÷3）：左/上/下间隙 ≈ 3.3–4pt 合设计，右间隙 ≈ 11.5pt。用户判「框左右没事、问题是卡片本身」与此同根：框忠实于行盒，卡面短了 8。
- 卡编辑描边（挂行盒、−3 外扩）同享此偏，同一修复一并愈。

Web 对照：单元为块级 width:100%，内容列 `.editor-pad` 左右各 16px——卡面应与列同宽、左右缘与文本块共线。

### 次因（proven）：引用块行内条模型使文内缩漂移

引用左条原为行内子视图（宽 3），文内缩 = 行 padding 14 + 条 3 + HStack 间距 8 = **25**；Web blockquote 为 border-left 3 + padding 14 → 文左内缩 **17**、右 14。且原生 MD 预览的引用块早已是 17/14 + 面缘 overlay 条的模型——同一产品内同类口径不一（proven，代码对读）。

### 次因（proven）：混排卡文本半垂直居中

imageTextRow 的文本标签在 HStack（默认.center）内按自身高居中于 188 高的卡面；Web `.itr-text` 为整高盒、padding 10、文贴顶。截图一实测：占位文位于卡面垂直中段，上下留白悬空（proven，像素 + 代码）。

### 次因（proven）：图片空占位无面

Web `.atomic-placeholder` 是玻璃面（radius 32、padding 24）；原生 ImageBlockView 空态只是无面文案行（padding 上下 18、无底无裁切），拾起框只能在行级借位（liftFaceRadius 对空图返回 cardS 挂行盒——行盒还含 36 内缩槽与幻影间距，与「面」三重不同源）。

### 内角（现象 proven、机理 unknown）：占位子面底角在真机呈圆

截图三像素实证：图文卡空占位灰面（fillSubtle）的左右底角对称后退，曲线区 ≈ 32–50px、拟合半径约 15–17pt，缺口处露卡面白（254/255）。而 0.9.52（8a6cadb）与当前 HEAD 的源码里，该子面（Text.background / Rectangle.fill）**无任何圆角裁切**，卡级 contentCard 的 clip 只作用于外轮廓、及不到内缝。机理未能在源码层定案（候选：本工具链 SwiftUI 对 background + 容器 clip 的栅格化交互；构建产物与仓库源码的未知差）。处置按用户规矩走构造性根治：所有子面一律**显式按位裁切**（见第三节），不再依赖「无裁切即直角」的默认——显式 clip 在子面自身层级锁形，上层 clip 只能再裁外轮廓、圆不回内缝，机理无论为何都不复发。

**S2 更正**：0.9.52 圆角批报告（fix_card_radius.md）S2 记「原生出血直角 + 卡裁外角为同心正形……本批保留原生形态」。本次用户明确判错并立规矩，且截图三证明占位子面的交界角在真机上并非直角呈现——S2 结论推翻，以本报告第三节的按位取角为准。

### 浮层（proven）：••• 菜单面板被同级占位撑满

menuPanel 的 ScrollView 与全屏 Color.clear 同处 ZStack：ScrollView 被同级贪婪占位撑到 `.frame(maxHeight:)` 的上限（viewH − 67 ≈ 近全屏），maxHeight 只是上限不是内容高。截图四实测面板高 ≈ 740pt 级、5 项内容（构成高 ≈ 272）只占上半（proven，像素量级 + 代码结构）。

## 二、截图逐项对应

| 截图 | 用户判读 | 定因 | 修复 |
|---|---|---|---|
| 一（拾起态） | 框右间隙大、右半文区留白怪 | 幻影间距（右间隙 4+8）；混排文居中 | 间距恒 0；文半整高贴顶 |
| 二（静态编辑页） | 卡右缘贴边、左右不对齐 | 幻影间距（右 25 vs 左 16.3） | 间距恒 0，卡面 = 列全宽 |
| 三（静态图文卡） | 图区底角圆、交界露缺口 | 占位子面底角真机呈圆（机理 unknown） | 子面显式按位取角（内角规矩） |
| 四（••• 菜单） | 面板近全屏、下半空白 | ScrollView 被 ZStack 同级撑到 cap | 内容实测高回写、帧高 = min(内容, cap) |

## 三、根治机制（三项，均为构造性单源）

1. **内容槽 ≡ 行盒**：BlockRow HStack spacing 恒 0；语义间隙就地归属——todo 钮文间隙 10 挂文侧 leading padding（文起点 8+44+10 = 62 不变）；引用条改面左缘 overlay（与 MD 引用块同形态），文内缩由行 leading padding 一处给出（17 = 条 3 + padding 14；trailing 14）。此后任何满宽卡的面按构造与行盒重合，拾起框（行盒 ⊕4）与卡编辑描边（行盒 ⊕−3）自动四边等距，不再有第二几何来源。image/gallery 的 36 对称内缩保留（Web margin 36 原样），其面框本来就在子视图内派生（图本体/grid 的 background LiftFrame），不受影响。
2. **子面按位取角 CornerRect**：新增纯 Path 形状（四角独立半径，二次 Bézier 构造、控制点即角点，方向约定零歧义；与真圆弧偏差 ≤0.06r 且只在外轮廓角出现、恒被父级卡裁切遮蔽）。复合卡每个子面按位置显式取角：贴顶只圆上角、贴左只圆左角、网格瓦只有外轮廓四角取半径。图片空占位补成真面（glassCard cardL + padding 24），其 LiftFrame 移入子视图（face cardL），liftFaceRadius 的 image 分支恒 nil——图片面框自此全在子视图内派生，与 gallery 同构。
3. **面板内容定高**：••• 菜单内 VStack 以 onGeometryChange 实测高回写 ui.menuPanelH（与 slashPanelH 同机制），面板帧高 = min(实测高, 旧 cap max(200, viewH−67))，首帧走构成估高（宽屏 322 / 窄屏 272 = 内距 14 + 项数×50 + 项距 8）。超出上限时 ScrollView 内滚，与 Web `.editor-menu-panel` 的 max-height + overflow 口径一致。

## 四、全量留白账（编辑页，逐块型；Web 值出自 editor.css / panels.css / render 规格）

记号：面内缩 = 面在行盒内四边内缩；✓ = 对账无误；= 本批已改；= 登记未改（见第七节）。

**内容列**：Web `.editor-pad` 左右 16；原生 ScrollView VStack padding 横 16 ✓ 对称。双栏栏距 gap clamp(28, 3.2vw, 52)、分隔两侧 half 对称 ✓。

| 块型 | 面内缩（改前 → 改后） | 卡内 padding / 子元素距缘 | Web 对照 | 判定 |
|---|---|---|---|---|
| imgTextCard | 右 +8 → 四边 0 | 图区整幅；文 padding 12/14、min-height 44 ✓ | `.img-text-card` width 100%、`.itc-text` 12/14 | 幻影间距；内角见第五节 |
| imageTextRow | 右 +8 → 0 | 图半 50% + gap 10 + 文半（截图一接缝实测 50.1% ✓）；文 padding 10/14 ✓；文垂直 居中 → 贴顶 | `.img-text-row` flex、`.itr-text` 整高贴顶 | 幻影间距 + 文贴顶；卡高固定 188 vs Web 181–196 内容驱动 |
| image（有图） | 左右 36 对称 ✓（槽内图按自然宽居中、不放大 ✓） | 无内 padding | margin 8/36 | ✓；空态补面（第五节外） |
| gallery | 左右 36 对称 ✓ | 网格 gap 内容 4 ✓ / 空态 4 → 6 | `.gallery-grid` gap 4、`.gallery-empty` gap 6 | 空态 gap；瓦角见第五节 |
| link-card / musicCard ready | 右 +8 → 0 | 正文 padding 上 10（有封面 6）/ 14 / 下 12 ✓；副标题上距 3 ✓；来源行上距 4、gap 5 ✓（Web `.lkc-source` margin-top 4、gap 5） | `.lkc-body` 10/14/12 | 幻影间距 |
| music 骨架 | 右 +8 → 0 | 封面 2.4:1 ✓；正文 10/14/12 ✓；线 gap 8 ✓；线宽 75/50/35% 阶梯 vs Web 三线同宽（块级 div 通宽） | `.link-card-skeleton` | 线宽为视觉差、非留白，不动 |
| music error 卡 | 右 +8 → 0 | padding 8/10、gap 10 ✓；重试钮 min 44×44、padding 0/12 ✓ | `.music-card-error` | 幻影间距 |
| music input 胶囊（MusicPillView） | 右 +8 → 0 | padding 12/18 ✓ | `.music-input-pill` 12/18 | 幻影间距 |
| music 空态/url 胶囊 | 右 +8 → 0 | padding 12/16、gap 10 ✓ | `.music-pill` 12/16 | 幻影间距 |
| video | 右 +8 → 0 | 16:9 整幅、无 padding ✓ | `<video>` 单元通宽 | 幻影间距 |
| attachment 文件行 | 右 +8 → 0 | 常态 padding 16/20、gap 10 ✓；宽屏 12/14、gap 8 ✓；图标 24（Web 1.5rem）✓；提示胶囊 padding 2/10 ✓ | `.attachment-file` 及 spread 变体 | 幻影间距；多行间 gap 8 与 Web 边距折叠推定一致 ✓ |
| attachment 图片 | 右 +8 → 0 | 整幅、无 padding ✓ | `.atomic.attachment img` 通宽 | 幻影间距 |
| quote | 文内缩 左 25/右 22 → 左 17/右 14 | 面 padding 上下 10 ✓ | blockquote 10/14 + border-left 3 | 条面缘化（与 MD 引用块同口径收敛） |
| callout | 文内缩右 +8 → 对称 | 面 padding 12/14 ✓；头行 gap 8、图标 18、头文距 5 ✓ | `.callout` 12/14 | 幻影间距 |
| codeBlock | 同 callout | 面 padding 12/14 ✓ | `pre` 12/14 | 幻影间距 |
| todo | 文右 +10 → 对称；文起点 62 ✓ 不变 | 行 padding 左 8 ✓（Web `[data-type=todo]` padding 4/8；纵向由 44 钮域主导） | flex gap 10、钮 44 | 间隙就地 |
| paragraph/heading/embed | 文右 +8 → 对称（不可见但折行点漂移同源） | heading 顶距 24/20/18 为既有纵向口径 | — | 幻影间距（随行盒） |
| list | 文起点 28（marker 20 + gap 8） | 嵌套缩进 19/22 已按 Web 移植 | ul 文起点 1.2em ≈ 17、ol 1.4em ≈ 20 | 顶层 marker 列与 Web 差 ≈ +8–11，改动牵动编号 marker 宽与既有审计，本批不动、登记待裁（第七节） |
| divider | 通宽 ✓ | 纵 padding 16 ≈ Web margin 1em | `.blk-hr` margin 1em 0 | ✓ |
| MD 预览（表格/引用/代码） | —（只读面） | 表格单元格 9/12 ✓；MD 引用 17/14 ✓（本批编辑器引用的对齐源）；MD 代码 12/14 ✓ | th/td 9/12、blockquote、pre | ✓ |

三类问题归属：应等不等 = 幻影间距（全块型右侧单边）；与 Web 漂移 = quote 文内缩、imageTextRow 文垂直、gallery 空态 gap、图片空占位无面；同类口径不一 = 编辑器引用 vs MD 引用（已收敛）。

## 五、复合卡内角账（逐卡型逐子面；规矩：只有外轮廓四角取卡半径、交界角恒直角）

| 卡 | 子面 | 位置 | 改前 | 改后（CornerRect 取角） |
|---|---|---|---|---|
| imgTextCard | 图（有图） | 贴顶 |.clipped() 直角（意图对、无显式锁形） | 上角 cardS、下角 0 |
| imgTextCard | 加载占位 | 贴顶 | Rectangle 无裁切 | 同上（形状本体） |
| imgTextCard | 空占位 | 贴顶 | Text.background 无裁切（**真机底角呈圆、露缺口**） | clipShape 上角 cardS、下角 0 |
| imgTextCard | 文条 | 贴底 | 无自有填充（卡底即面） | —（构造直角） |
| imageTextRow | 图/加载/空占位 | 贴左 |.clipped() / 无裁切 | 左角 cardS、右角 0 |
| imageTextRow | 文半 | 贴右 | 无自有填充 | — |
| link/music ready | 封面 | 贴顶 |.clipped() | 上角 cardL、下角 0 |
| music 骨架 | 封面占位 | 贴顶 | Rectangle 无裁切 | 上角 cardL、下角 0 |
| gallery | 每瓦 | 按格位 | 全瓦 RoundedRectangle cardS（**交界角全圆**） | 仅网格外轮廓四角 cardS、余 0（tileCorners 按行列派生）；格网外层 clip 不变 |
| gallery 空态 | 双瓦 | 左右各一 | 全角 cardS | 外侧角 cardS、交界角 0 |
| 首页图卡（squareImageCard） | 图区 | 贴顶 |.clipped() | 上角 Radius.grid、下角 0 |
| attachment 图片 / video / image 图本体 | 单面 | 整卡 | 全角裁切即外轮廓 | ✓ 不动（无交界） |
| quote/callout/codeBlock/MD 各面 | 单面 | 整卡 | 行面/MD 面全角 | ✓ 不动（无拼合子面） |

注：gallery 瓦角与 Web 现状不同（Web `.gallery-grid img` 每瓦全圆 22）——按用户本次规矩（明示含 gallery）执行，属用户裁定偏离，已在此明示。

## 六、浮层几何账（逐面板：高度来源与内容关系）

| 面板 | 高度来源（改前） | 判定 |
|---|---|---|
| ••• 菜单 | ScrollView 被 ZStack 同级 Color.clear 撑到 cap（viewH−67） | 内容实测高（第三节 3） |
| 导出面板 | VStack 内容定高、宽 246 与菜单同位 | ✓ |
| 块菜单（blockMenuLayer） | 公式高 = 项数×50 + 14、上限 340 内滚；menuItem 实高 minHeight 50 已核 | ✓ 内容派生 |
| 卡菜单（cardMenuLayer） | 公式高 114/64 = 项数×50 + 14，面板本体 VStack 内容定高 | ✓ |
| 斜杠/链接面板 | 实测高回写（slashPanelH）定顶边 + 上限 320；与菜单同为「ScrollView + 上限」结构，但已有实测回写定位、J2 已验着陆、无悬空报告 | ✓ 本批不动、登记结构同型（若日后现悬空，同法收） |
| 链接表单（linkFormPanel） | VStack 内容定高（随斜杠层实测） | ✓ |
| 更换背景色底表 | VStack 内容定高（底部贴边） | ✓ |
| ErrBadge 详情面板 | ScrollView + maxHeight 360（J2-F28 既定「限高内滚」形态） | ✓ 本批不动、登记同型观察 |
| 备份确认底表 / 各 toast | VStack/HStack 内容定高（设置区，本批边界外，仅核形态） | ✓ |

## 七、登记未改项（待主线/用户裁）

1. **列表 marker 列**：原生顶层文起点 28（marker 框 20 + gap 8），Web ul ≈ 17 / ol ≈ 20；嵌套层同差。改动需同时定编号 marker（"100." 等宽数）的框宽口径，且触既有 #29 审计结论，本批不动。
2. **imgTextRow 卡高**：原生固定 188，Web 为 181–196 内容驱动（min/max-height）。在区间内、非不对称问题，不动。
3. **music 骨架线宽**：原生 75/50/35% 阶梯、Web 三线通宽。属形态差、非留白，不动。
4. **附件行宽屏半径旁注**：圆角批 S1 裁断记「附件宽屏 22 缺 Web 实据、统一 32」；本批查账见 editor.css 宽屏段存在 `.attachment-file` 的 radius-22 规则（spread 变体），与 S1 表述有出入。属圆角面、用户已判圆角无事，本批不动，仅登记请主线复核 S1。
5. **slash / ErrBadge 面板**：与 ••• 菜单同为「ScrollView + 限高」结构，前者有实测回写、后者为 J2 既定限高内滚，均无悬空实报，不动（第六节已登记）。

## 八、改前改后对账（行为等价核查）

- 满宽卡左右边距：16 / 24（+todo 26）→ **16 / 16**，与文本块左右缘共线（Web 口径）。
- 拾起框四边间隙：左/上/下 4、右 ≈ 11.5 → **四边 4**（框与面同源于行盒；image/gallery/空占位面框在子视图内 ⊕4 不变）。
- todo：文起点 62 不变、钮文距 10 不变；文右缘 +10 回到列右缘。
- quote：文左内缩 25 → 17、右 22 → 14（Web/MD 值）；条视觉位由行内 x=14 移至面左缘 x=0（Web border 位）。
- callout/codeBlock/文本：仅右缘回正，左与纵向零变化。
- imageTextRow：图半 50% 与接缝不变；文由垂直居中改贴顶（Web 口径，长文 6 行截断行为不变）。
- gallery：内容态 gap 4 不变、瓦高 366 不变；空态 gap 4 → 6；瓦交界角圆 → 直。
- ••• 菜单：宽 246、顶距 59、右距 16、上限与内滚不变；高 填充式（≈viewH−67）→ 内容高（窄屏 ≈ 272）。
- 图片空占位：无面文案行 → 玻璃面（高由 ≈56 变 ≈68 = padding 24 + 文行，Web 口径）；点按行为不变（行级 onTapGesture 覆盖全行）。

## 九、断言（verify [23]，锁机制不锁数值）

S23-1 间距恒 0 + 旧三元零残留 + 间隙就地；S23-2 行内横向 padding 只剩图/gallery 两处对称 36 + image 行级出框恒 nil；S23-3 引用 leading 17 + 条 overlay 化 + 段内 quoteBar 仅一处；S23-4 CornerRect 在位 + 图文六子面/链接音乐封面骨架/gallery 瓦/首页图卡全点位按位取角；S23-5 gallery gridGap 派生（4/6）+ 写死零残留；S23-6 混排文整高贴顶；S23-7 图片空占位成面 + 面内 LiftFrame；S23-8 菜单 menuPanelH 回写 + 帧高 min(内容, cap) + 旧撑满帧零残留。

本机自跑：[23] 八项全绿；全量 202 项 ✓。余下 3 项失败均非本批：ipa 陈旧 ×2（产物早于源码、随 tree 重建消解）、B16-3（只查桥文件、M2 批在飞未同步其断言）。[21]/[22]/[24] 全绿，本批未破坏既有组。

## 十、真机终判点（待用户）

1. 静态编辑页：任一满宽卡左右缘与正文/标题左右缘共线（截图二复拍同位）。
2. 拾起任一满宽卡：框四边间隙等距（截图一复拍同位）。
3. 图文卡空态：占位灰面底角为直角、与文条交界无白缺口（截图三复拍同位）；有图态同核。
4. gallery 多瓦：瓦间交界角为直角、十字缝干净；首页图卡图区底角直角。
5. ••• 菜单：面板高 ≈ 内容（5 项贴合、无下半空白，截图四复拍同位）；宽屏下含双栏行时同核。
6. 引用块：左条贴面左缘、文左内缩与 MD 预览引用一致；todo 点按钮域与文落焦无回归。
