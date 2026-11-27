# 宽屏批落码报告（横屏/宽屏审计修复 + 宽屏收窄）

日期：2026-11-27。依据：docs/reports/audit_landscape_wide.md（L-1…L-8、E-1、E-2）；用户 2026-11-27 17:13 裁定（宽屏收窄、图片页公式都做）。硬门：0.9.57 组版提交全落定（HEAD 6ce6cd8）且开工时工作树净——已过门后落码。落码面：rust/apps/ios/app/MomentApp.swift、MomentBridgeSettings.swift（E-1 一页）、MomentRescue.swift（E-2）、verify_ios.sh（断言 10 新 + 2 同步改判）。**不提交、不 bump**，随下一组版。证据分级沿审计口径：代码/算式级 = proven；涉真机呈现的关账依赖见文末清单。

## 逐项落码与量测复核

### L-1 ≥1288 首页网格框序（中）✓
gridHome 链 `.frame(maxWidth: 1240)` 与 `.padding(.horizontal, 24)` 换序为内距先行：1240 含内距、内容宽 1192 = Web（max-width 1240 + border-box + padding 0 24），框缘 (W−1240)/2 与页眉收轴同轴（D8 回归）。<1288 档框不生效、内距照旧，窄屏零变化。断言 F30-15（段内行序锁）。

### L-2 independent 双栏净间距（中）✓
Web editor.css:1006-1011 回源实证：左栏 `padding-right: 16px` + `border-right: 1px`、右栏 `padding-left: 16px`，gap 为 clamp(28, 3.2vw, 52)。原生改：左栏 trailing half→16、右栏 leading half→gap+15（栏宽 = contentW − gap 不变；净距 gap+32、线贴左栏右缘——与 Web 逐项同构）。菜单原点 panelLeftX 右栏账同步改写：colW = (contentW − 32 − 1)/2、x = margin + colW + 1 + gap + 15 + frameMinX；与旧账代数等价已验（旧 colW=(contentW−32−gap)/2 + x=margin+colW+gap ≡ 新式在 gap=32 处恒等、任意 gap 下与新布局几何一致——新布局下右栏内容原点 = margin + colW + 1（线） + gap + 15（右内距），式即几何本身）。flow 模式 half 居中口径不动（Web 流式栏杆在栏外、无内侧 padding）。断言 T17-11。

### L-7 编辑正文顶 padding 168→155（低）✓
Web .detail-body padding-top 155 回源一致。五处联动全改：单列/independent/flow 三处 `.padding(.top, 155)`；三形态占位账同步（单列 minHeight viewH−208→−195、independent colMinH viewH−200→−187、flow viewH−192→−179，账式注释逐处改写）；cardMenuLayer/blockMenuLayer/slashLayer 三处 independent 顶偏移 `? 168: 0`→`? 155: 0`；onDisappear 的 estH 基线 `+168`→`+155`。残留 168 仅 :5183 历史叙述注释（0.9.9 基线推算记录，非现行几何）与无关命中。断言 T17-12 + J1-2 同步改判（见下）。

### L-4 图片页可用区公式对齐 Web（低）✓
availH = 全高 − 126 − 40 − safeAreaInsets.bottom；呈现同步：顶 padding 66→126、新增底 padding 40 + safeBottom。**与 0.9.34 落点的关系**：0.9.34 修的是「判定高与呈现高不一致」（判定用 −66、呈现曾用别的口径）——本批保留其同源结构（判定与呈现同用 availH 一个量），只把让位数值换成 Web 口径（Web .image-page-body top:126 + padding-bottom: calc(40px + safe)）；注释已在落点写明此关系。verify [7]「图片页判定高」断言随之同步改判（字面 −66→−126 系，注释注明同源性不变）。断言 K22-12。

### L-3 斜杠面板横屏下限（中·风险）✓
与 Web 对账：Web .slash-panel 只有 max-height 320 硬顶、**无锚位相关下限**（面板不随锚点收缩）——原生上翻式的 maxH 本就是呈现等价的派生量，下限取向应保「面板可用性」而非抄 Web。落值：上翻支 `max(top − 10 − 12, 48)`→下限 **120**（约 2.3 行菜单项，横屏 393 高下靠顶锚点不再被压至约 78 的 1.5 行）；下翻支公式与 320 顶不变；h = min(hRaw, maxH) 恒 ≤ 内容高、下限只抬可用高不凭空增高。发生率关账依赖 V-6（见文末）。断言 J20-13。

### L-5 图片页旋转复位（低）✓
ZoomableImageView.Coordinator 增 lastViewport 记账：fit() 检出视口尺寸变化（旋转/分屏）时倍率直接钳回 base（不再只按下限抬回）、居中 insets 重算后 contentOffset 复位至居中原点；视口未变的 fit 路径（换图 zoomScale=0、双击/捏合后的 fit(allowUpscale) 调用）行为逐字不变——双击缩放走 toggleZoom 不经此分支、Coordinator 的 fit 仅由 updateUIView 触发。断言 K22-13。效果关账 = 真机旋转复验（IMG-04）。

### L-6 背景色底表横屏（低）✓
bgSheet 色点网格列数改 `ui.viewH < 500 ? 8 : 4`：横屏（393 高档）底表高约 311+safe、8 色 1 行（列宽 (560−84)/8 ≈ 59 ≥ 色点 44，底表宽 600 不变）；竖屏 4 列 2 行原样。审计的高度账（不超高、余量 59–80）复核成立，本项只改行数形态。断言 J20-14。

### L-8 MD 宽屏残余（低·残余）✓
Web 宽屏段（editor.css @media (min-width:768px) and (min-height:600px) 及 1100 段）回源：th/td `min-width: 5rem; padding: 7px 9px`、pre `padding: 10px 12px`、blockquote `padding: 9px 12px`（基础 blockquote = 10px 14px + border-left 3px）。原生 MdBlockView 增 `topLevel` 标记（MdPreviewView 直子单点接线、递归子块不传）+ `wideTop = topLevel && Marks.spreadWidth > 0` 派生（宽屏信号与 EditorModel.baseFont 同源 syncWide）：顶层宽屏时 Code 纵 10/横 12、Quote 纵 9/左 15（3 条 + 12）/右 12、Table 单元格 minWidth 80（=5rem）+ 横 9/纵 7；窄屏与嵌套块（引用/列表内）保持现行值。断言 J20-15。

### E-1 设置族宽屏收窄（增强，用户裁定）✓
抽统一容器：View 扩展 `settingsContentFrame()`（横 20 / 顶 126 / 底 40 → `.frame(maxWidth: 720)` → 全宽居中框），即审计提案的 SettingsContainer 以扩展形态落地（六页调用面同为单行修饰、无状态可收，扩展比新 struct 更省且单源等价）。六页手抄三行全收敛：SettingsView、BackupView、GesturesView、WeatherView、LanguageView（MomentApp.swift）+ BridgeSettingsView（MomentBridgeSettings.swift）。窄屏（<760）框不生效、呈现零变化；宽屏内容 720 居中。DiagView 两处同式 padding **不在六页范围、刻意不动**（诊断页非设置族）。断言 W18-8（定义 1 + 调用 5+1 计数单源锁 + 手抄值残留计数）。

### E-2 救援页/看门狗浮条宽屏收窄（增强，用户裁定）✓
RescueView 内容 VStack 加 `.frame(maxWidth: 720)` + 全宽居中框（根背景仍在 ZStack 底层全屏满铺，V-5 口径不受影响）；WatchdogBar 在 glassCard 后加 `.frame(maxWidth: 600)`（呈现处底对齐框含横居中）。与 E-1 同口径（720/600 = 审计提案值）。断言 R19-14（编号顺延：并行救援批已占 R19-13）。

## 断言同步改判（本批改值引起的既有断言失效，逐条登记）

- verify [7]「图片页判定用可用高」：锁字面 `geo.size.height - 66` → 改判 `- 126` 系新公式；注释写明同源口径不变、只换让位数值（L-4）。
- verify [11] J1-2：三形态占位账 208/192/200 → 改判 195/179/187（L-7）；注释同步。
- 本批新增：T17-11、T17-12、J20-13、J20-14、J20-15、K22-12、K22-13、F30-15、W18-8、R19-14，共 10 条。本机自跑：10 条全绿 + 2 条改判转绿；剩余红仅既有产物类 2 条（ipa 陈旧、产物语言包——tree 构建自解，与各批本机基线同）。本机无 swiftc，App 编译级自检随 tree 冒烟（smoke_ios.sh）。

## 并发说明（纪律留痕）

- 落码期间发生一次整树瞬时回滚（四文件 mtime 同秒回到基线），约 16 秒后树面恢复为含各在途批改动的版本；本批全部落点已逐项 grep 复验在位（L-1 框序行序、L-2 三字面、155 计数 3+3、L-3 120、L-6 条件式、L-5 lastViewport×3、L-8 wideTop×12、E-1 计数 6+1、E-2 720/600 各一），终局 diff 快照与基线快照可对账。
- 与在途批（文字大小/救援小批/只读入口/配对二维码等，同动 MomentApp.swift 与 verify_ios.sh）逐 hunk 错开：本批落点均在编辑几何/首页网格/图片页/MD/设置页段，与各批领地无同段冲突；verify 追加均在各组尾部。W18-8 计数曾因漏算本批 L-4 的呈现顶让 126 而误红，已按四处构成（定义 1 + Diag 2 + 图片页 1）修正断言，非源码问题。

## M-11 定案登记（主线追加，用户 2026-11-27 确认）

**裁定**：图文卡（imgTextCard / imageTextRow）图区点按进图片页为**定案增强**，保留现行行为，后续审计不再列报为差异。

**接入面现状**（CardBlockView，代码级 proven）：图区点按走 `tapImageArea()` 分流——编辑态（cardEditBlockId == 本块）点图区 = 换图（Web cardPick kind=set 口径）；**常态点按且有图（fileId 或 imageURL 任一在）→ `openImagePage()`**：置 `editor.imageTarget = ImageTarget(fileId, urlString, name: 节点 name ?? "图片")`，由编辑器宿主 push ImagePageView；常态无图不动作（占位文案引导走编辑态）。image 块本体（常态点按同路置 imageTarget）与 gallery 项点按为既有接入面，与本条并列。

**与图片页接入清单的衔接**：2026-11-24 定案的可开范围（URL 形 image 块、gallery Url 项、附件文件行图片类）与不接入名单（musicCard/link-card 封面、MD 预览内嵌图、video、列表封面、头像、非图片附件行）均未含图文卡本体图区——本条是对该定案的**增补**而非修订：不接入名单维持不变；图文卡在首页封面派生中的候选地位（2026-11-24 封面定案含 imgTextCard/imageTextRow）是另一面，与本条无关、勿混。图片页本体对入口无差别：各入口共用同一 ImagePageView 与同一可用区公式；本批 L-4 只动页内公式与呈现让位，未触 imageTarget 置位链与 tapImageArea 分流，M-11 入口经复验不受影响。

**补登记文本（供主线并入图片页接入清单本体）**：

> 图文卡图区（定案增强 M-11，用户 2026-11-27 确认）：imgTextCard / imageTextRow 的图区——编辑态点按 = 换图（cardPick kind=set）；常态点按（有图）→ 进图片页（openImagePage → editor.imageTarget，fileId/URL 双源，标题取节点 name、兜底「图片」）；常态无图不动作。本条增补 2026-11-24 可开范围定案；原「不接入」名单（musicCard/link-card 封面、MD 预览内嵌图、video、列表封面、头像、非图片附件行）不含图文卡本体图区、维持不变。

## 关账依赖与真机终判点

- **代码级关账（不依赖 V 项）**：L-1（框序算式）、L-2（栏距算式 + 菜单原点代数等价）、L-7（五处联动账）、E-1、E-2（容器算式；V-5 救援页横屏背景满铺仅旁证——收窄只动内容框、根背景全屏层未触）。
- **关账依赖真机量测**：L-3 依赖 V-6（横屏靠顶光标时斜杠面板实高与可滚性）；L-5 依赖 IMG-04 真机旋转复验（旋转后倍率/偏移实态）；L-4 呈现观感（iPad 大图底边距 40+safe 的实际留白）随宽屏真机批一条；L-6 横屏底表单行形态真机一条；L-8 宽屏 MD（表格不再挤压、pre/引用内距）随宽屏真机批一条；L-1 的 V-1（横屏首页首卡左缘）若量得 ≈24 而非 ≈83，属 SwiftUI 横向安全区承接的独立缺陷、与框序无关，另立项。
- 覆盖矩阵映射：L-1→HOM-15、L-2→EDT-31/32、L-3→EDT-36（建议扩横屏变体）、L-4→IMG-03、L-5→IMG-04、L-6→EDT-38；审计建议的「横屏矮高档」矩阵新行仍待主线并入覆盖矩阵时一并处理。
