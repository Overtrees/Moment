# 全面排查批 C（首页形态）· 落码执行清单

2026-11-26 只读核证产出（对 `docs/reports/audit_detail_home.md` 86 条逐项复核现行 0.9.35 代码后排批）。本文件只做计划，不含落码。

口径与分级：

- 行为等价是底线；系统控件/系统形态等价更优者标「改判保留」，不列待修。
- **A 级** = 功能/形态级，用户能直接感知，本批排落码。
- **B 级** = 微差（≤2px、字重 650 vs 600 类单令牌差、chip 色等），只登记，不排落码（将来若同面有 A 级改动顺手带上，须在提交信息里注明）。
- 行号为 0.9.35 现行 `rust/apps/ios/app/MomentApp.swift` 实测行号；Web 出处为现行仓库文件行号（CSS 行号较审计时点亦有漂移，以选择器名为准）。

已销账（不在本批）：

- §七 摘要取数范围、标签取数范围 2 条 —— 0.9.32 批 A 已修，现行 `MemoItem.paraFirstTexts`（Swift:9271）全段扫描、`summary`（Swift:9343-9344）与 `tags`（Swift:9310）均走全段拼接，复核属实。
- §八 网格态空状态 1 条 —— 0.9.32 批 A 已修，现行 `gridEmpty`（Swift:10400）：标题 16、说明 13 + lineSpacing 7 + maxWidth 280、动作钮（新建/重新加载）、纵 padding 56，复核属实。

改判保留（不在本批）：搜索展开态 × 清除钮（原生增强，审计已定等价更优）；紧凑胶囊阈值切换 + 180ms 淡入（0.9.23 定案）；左滑系统 swipeActions（已定案）；notice 行（原生诊断通道，无 Web 对应物，已定案）；空状态图标 SF 替代（等价更优）；页眉悬浮结构与首卡静止位（0.9.23 定案）。

---

## A 级（9 条，按建议落码序排列见文末）

### C-A1 §六 撤销 toast 整组形态（形态 + 图标 + 文字 + 钮）

- Web 真值：`.backup-toast`（base.css `.backup-toast` 规则）：fixed、left/right 16、bottom = safe + 16、radius 28、glass-overlay、padding 14/16、gap 10；图标 = del SVG 19px（main.rs:2661 `svg_markup("del", 19, …)`）；文字 `.backup-toast-text`（base.css:677）：14 / 500 / line-height 1.35、flex:1；撤销钮 `.undo-toast-btn`（base.css:672）：14 / 600 / accent、padding 6/10。
- 原生现行：`ListView.undoToast`（Swift:10292-10309）：居中胶囊——HStack spacing 14、padding 横 18 纵 10、`glassCard(radius: 999)`（content 档）、外层 `.padding(.bottom, 14)`；无图标；文字 14 常规字重；撤销钮 14 semibold 无内距盒。呈现挂法：body ZStack 内 `.frame(maxWidth/maxHeight: .infinity, alignment: .bottom)`（Swift:10074-10079）。
- 目标值：全宽条：左右距屏缘 16、底 = safe + 16、radius 28、overlay 档、padding 14/16、内部 gap 10、图标 19、文字 14 medium、钮 padding 6/10。
- 改法：undoToast 改 HStack(spacing: 10) 全宽条（trash SF 图标 19pt 替代 del SVG，与本 app 图标 SF 替代惯例一致），容器改 `.padding(.horizontal, 16)` + 底距 16，材质换 `overlayCard(radius: 28)`。
- 占位账：条内横向 = 左 padding 16 + 图标 19 + gap 10 + 文字（flex，吃剩余） + gap 10 + 钮（文字 ≈30 + padding 20 = ≈50）+ 右 padding 16；条高 = max（图标 19、文字 14×1.35 ≈ 19、钮 14 行高 + 纵 padding 12 ≈ 31）+ 纵 padding 28 ≈ 59。纵向：条底边距 ZStack 底（= 安全区底，根 ZStack 未 ignore safe area）16。
- 风险/前提：① 底距口径以根 ZStack 底边 = safe 底为前提，落码后须真机截图核条底与 home indicator 的相对位置（若 ZStack 实际铺到物理底边，须再加 safe inset，届时以截图为准改一处常量）；② 进场动画现行 spring + move(.bottom) 已定案等价，不动；③ 图标 SF trash 与 Web del 字形不同属图标集既有替代口径，不另议。

### C-A2 §一 紧凑小标题胶囊纵向位置

- Web 真值：`.page-title.compact`（base.css:85-104）：fixed、top = safe + 7、水平居中。
- 原生现行：`ListView.header`（Swift:10176-10221）：ZStack（`.padding(.horizontal, 20)`、`.padding(.top, 7)`、`.frame(height: 82)`），CompactTitle 钮为 ZStack 直接子视图、默认双轴居中（Swift:10203-10213）。
- 目标值：胶囊顶 = safe + 7（与头像行顶同线）。
- 改法：CompactTitle 钮加 `.frame(maxHeight: .infinity, alignment: .top)`，只改纵向对齐、不动宽度（横向仍由 ZStack 居中，与 Web 水平居中一致）。
- 占位账：header 总高 82 = 顶 padding 7 + 内容盒 75；头像 HStack 以 .top 对齐、顶在内容盒顶（= safe + 7）；胶囊高 ≈ 17pt 字行高 ≈20 + 纵 padding 12 ≈ 32，现居中于内容盒 → 顶 ≈ 7 + (75−32)/2 ≈ safe + 28.5（审计估 safe + 32，差在字行高取整，同量级）；改顶对齐后胶囊顶 = 内容盒顶 = safe + 7，消除 ≈21–25pt 下沉。
- 风险/前提：钮的命中域随 frame 纵向撑满内容盒（宽仍为胶囊宽、横向居中一列），紧凑态 allowsHitTesting 已由 compactP ≥ 1 门控，不会误挡列表滚动（滚动手势不走 hit test 拦截面）；非紧凑态 opacity 0 + 不可命中，不受影响。

### C-A3 §四 图/文子列间隔

- Web 真值：同组内 img 子列与 txt 子列之间 = img 组 margin-bottom 24 + `.gap-16` 高 16 = 40（base.css:119-125、206 `.gap-16`；main.rs 分组渲染段）。
- 原生现行：`ListView.body` 分组循环内（Swift:10057-10063）：`Color.clear.frame(height: 16)` 间隔行；相邻卡 listRowInsets 上下各 3（Swift:10785-10786）。
- 目标值：合成间隔 40。
- 改法：间隔行高度 16 → 34，其余不动。
- 占位账：合成 = 上卡 bottom inset 3 + 间隔行 34 + 下卡 top inset 3 = 40；间隔行自身无 listRowInsets（审计已按此口径算出现行 22 = 3 + 16 + 3，与代码一致）。
- 风险/前提：无（纯行高常量；该行无探针、无手势）。

### C-A4 §九 ≥1280 页眉居中约束

- Web 真值：`@media (min-width: 1280px)` 内 W-4 定案规则（base.css:618-633 注释及 `.page-title` / `.glass-search-trigger` 规则）：页眉左右内距与搜索 right 同取 (100vw − 1240) / 2，与网格容器边框盒同轴；1280 时恰为 20、与旧值无缝。紧凑胶囊走自有居中、不受此约束。
- 原生现行：`ListView.header` 恒 `.padding(.horizontal, 20)`（Swift:10219）；网格侧 `gridHome` 已 maxWidth 1240 居中 + 横 padding 24（Swift:10362-10364）。页眉量测源 `syncHomeSize`（Swift:10118-10131）已拿到容器宽但未存。
- 目标值：W ≥ 1280 时页眉横 padding = (W − 1240) / 2；W < 1280 时 20。iPad 12.9 横屏 W=1366 → 63（现差 43）。
- 改法：syncHomeSize 把 s.width 存入 NavState（如 homeW），header 的横 padding 改三元：`nav.homeW >= 1280 ? (nav.homeW - 1240) / 2 : 20`。
- 占位账：页眉总宽 = W；左内距 P 后头像左缘 = P；网格容器盒左缘 = (W − 1240)/2 —— P 取 (W−1240)/2 时头像与容器盒同轴（Web 口径是与边框盒同轴，非内容缘 24 内侧）；搜索胶囊在同一 HStack 内、右缘随右 padding 同步内移，与网格右盒缘同轴；CompactTitle 为 ZStack 居中、不受 padding 影响（与 Web「紧凑胶囊不受此规则」一致）。
- 风险/前提：① homeW 初值 0 时须回退 20（量测 onAppear 即到，首帧可能闪一帧 20 → 以 `homeW > 0` 为启用条件）；② 只动 header 一处 padding，不动 gridHome（其 1240 + 24 已对齐）；③ 分屏/台前调度下 W 变化由现行 onChange 量测覆盖。

### C-A5 §九 网格新建方卡天气排布

- Web 真值：网格新建卡 = `.list-item` 方卡化，天气块经 `.list-item > div:last-child` 宽屏规则排**底部整行**（base.css:508-512）：flex row、space-between——温度左、城市右、同行（`.newcard-weather` 基线形态 base.css:192-194）。
- 原生现行：`newCardSquare`（Swift:10446-10489）：天气为 HStack { Spacer; VStack(alignment: .trailing, spacing: 2) { 温度； 城况 } } —— 右下两行堆叠。
- 目标值：底部一整行：温度在左、城况在右、同行同基线带。
- 改法：天气块改 HStack { 温度 Text；Spacer()；城况 Text }、`.frame(maxWidth: .infinity)`，删内层 VStack 与前置 Spacer；其上方 Spacer(minLength: 0) 推底保持不动。
- 占位账：方卡边 = 栏宽（3 列时 (min(W,1240) − 48 − 28) / 3），卡内 padding 14；天气行高 = max（温度 16×1.1 ≈ 18、城况 12×1.2 ≈ 14）≈ 18（现两行堆叠 ≈ 18 + 2 + 14 ≈ 34，改后卡内纵向多出 ≈16 空间由推底 Spacer 吸收，标题区位置不变）；行内横向 = 温度（左缘 = 卡内 14）+ Spacer + 城况（右缘 = 卡内宽 − 14）。
- 风险/前提：温度字重 650 差属 C-B1，不在本条动；城况文形「{city} {text}」已对齐（0.8.6 定案），只搬位置不改文形。

### C-A6 §三 展开/收起钮玻璃药丸

- Web 真值：`.expand-btn`（base.css:199-205）：glass-control 底、font 11、padding 4/10、radius 14、1px 边（--glass-control-border）、色 --glass-label-color（#48494F / 深 #D1D1D6，tokens.css:53、250），位于 meta 行右端（list.rs:1362、1477 两处渲染）。
- 原生现行：`metaRow`（Swift:10838-10866）：HStack(spacing: 6) 内 meta 文本后紧随纯文字钮——font 12、T.accent 蓝、无底无边无内距；方卡侧同型钮在 `squareFoldRow` / `squareImageCard`（不在本条范围，见风险）。
- 目标值：font 11、glass-control 药丸（padding 4/10、radius 14、1px 边）、色 glass-label、恒居 meta 行右端。
- 改法：metaRow 在有 hint 时于文本与钮之间插入 Spacer(minLength: 8)，钮改 `.padding(.horizontal, 10).padding(.vertical, 4)` + `glassControl(radius: 14)`，字号 12 → 11、色改新令牌 T.glassLabel（见前提）。
- 占位账：meta 行总宽 = 卡内宽（行卡 inset 16×2 + 卡 padding 16×2，行内容 = W − 64）；文本 flex 吃剩余并单行截断；钮宽 = 文案（「▼ 展开 N 条」≈ 11pt × 7 字 ≈ 62）+ 横 padding 20 + 边 2 ≈ 84；钮高 = 11pt 行高 ≈13 + 纵 padding 8 + 边 2 ≈ 23（现纯文字 ≈16，行高由 meta 文本 12pt 行 ≈17 与钮 23 取大，卡高 +≈6，属形态对齐的预期变化）。
- 风险/前提：① **T 令牌缺口**：原生 T 无 --glass-label-color 对应令牌（线 4 审计 C2 同面问题），本条须新增 `T.glassLabel = dyn(0x48494F, 0xD1D1D6)`——新增令牌与「优先复用既有变量」规矩的边界：既有 T.textSecondary（#68686D）色值不同、不可代用，新增属必要，落码提交信息须写明；② meta 文本加 Spacer 后须保持 lineLimit 1 截断（Spacer 不压缩文本，HStack 内 Text 默认可截断，落码后核长摘要卡）；③ 方卡折叠钮（squareFoldRow）Web 无同名对应物（网格折叠走整卡点按），本条不动方卡侧。

### C-A7 §三 标签布局（标题 60% 上限 + 标签右对齐）

- Web 真值：`.item-title-text` max-width 60%（base.css:175-180）；`.item-tag-list` flex:1、justify-content: flex-end、overflow hidden（base.css:181）。
- 原生现行：`titleRow`（Swift:10809-10830）：HStack(spacing: 6) 内标题 Text（lineLimit 1、无宽上限）后左排 chips prefix(3)，长标题时标签被顶至行尾溢出、无 60% 截断点。
- 目标值：标题占行宽 ≤60% 后截断；标签组占剩余区、右对齐。
- 改法：titleRow 外包 GeometryReader 取行宽：标题 `.frame(maxWidth: geo.size.width * 0.6, alignment: .leading)`，其后 Spacer(minLength: 4)，chips 保持 prefix(3) 左起排于右区。
- 占位账：行宽 = W − 64（同 C-A6 口径）；置顶点 6 + gap 6（有置顶时先扣）；标题 ≤ 0.6 × 行宽；标签区 = 行宽 − 标题实宽 − gap，右对齐贴行右缘。
- 风险/前提：① GeometryReader 高度须由内容驱动——用 `.frame(height:)` 写死会与 Dynamic Type 冲突（titleFontScale 现为常量 1.0、meta/title 字号为固定 pt，行高 ≈ max（标题 16pt 行 ≈19、chip 高 16）≈ 19；落码时以 chip 目标高 18 与标题行高取大设 minHeight、不设固定高，宁可让 GeometryReader 以 `.fixedSize` 外包一层常规 HStack 量宽——实现细节落码时二选一并在提交信息注明）；② 本条与 C-B2 chip 高同在 titleRow，排序上先 A 后 B 顺手带。

### C-A8 §四 列表底部留白

- Web 真值：`.container` padding-bottom = 20 + safe（base.css:116）。
- 原生现行：窄屏 List 无尾部留白，末卡 bottom inset 仅 3（Swift:10785-10786）；网格态已有 `.padding(.bottom, 20)`（Swift:10365，与 Web 一致，不动）。
- 目标值：末卡底缘距 safe 底 20。
- 改法：分组循环后、emptyRow 判定前加尾部透明行（height 17、listRowInsets 零、分隔隐藏，镜像 spacerRow 写法），仅 visibleMemos 非空时出现。
- 占位账：末卡 bottom inset 3 + 尾行 17 = 20。
- 风险/前提：尾行不可带 swipe/手势（Color.clear 纯行，与 spacerRow 同型已验证）；滚动探针挂 spacerRow（首行），尾行不影响基线。

### C-A9 §八 文案两条（加载失败 / 搜索零结果说明）

- Web 真值：`empty.load_error_sub` = 「本地数据读取出错。重新加载试试；若反复失败，可在设置页查看诊断日志」（lang/zh-CN.json:105）；`empty.search_sub` = 「换个关键词试试，或清除搜索查看全部备忘」（lang/zh-CN.json:102）。
- 原生现行：`emptyRow` 状态元组（Swift:10876、10884）：分别为「本地数据读取出错，重新加载试试」「换个关键词试试，或清除搜索查看全部」——前者截短且丢诊断指引，后者尾缺「备忘」。
- 目标值：与语言包逐字一致（上引两串）。
- 改法：两处字符串字面量替换，无结构改动。注：gridEmpty 的加载失败说明（Swift:10416）现为短版同串——Web 网格态与窄屏共用同一 EmptyState 组件、同一文案，本条一并替换 gridEmpty 那处，保持两形态一致。
- 风险/前提：无（纯文案；原生无 i18n 运行时、硬编码中文为既有形态，语言包立项时统一收编）。

---

## B 级（10 条，只登记不排落码）

### C-B1 标题字重 650 系统性（5 处）

- Web：650（base.css:171 行卡标题、:200 图文卡标题、:193 天气温度、:447-458 方卡标题、:531-539 图文方卡标题）。
- 原生：全为 semibold（600）——`titleRow`（Swift:10821，两卡共用）、`squareTextCard` 标题（Swift:10580）、`squareImageCard` 标题（Swift:10616）、`newCardRow`/`newCardSquare` 温度（Swift:10703、10471）。
- 登记理由：SF 无 650 档，.semibold（600）与 .bold（700）各差 50，改任一档都是单令牌替换、无结构风险，但视觉收益临界；审计原评级即「小」。若将来改，倾向 .bold 一次五处同改，不在本批。

### C-B2 标签 chip 系统性（色 + 三处高）

- Web：`.glass-tag`（base.css:354-358）：文字 --glass-label-accent（#005BBB / 深 #72B7FF）、glass-control 底、1px 边；高：行卡 chip 18（list.rs:1164-1172，font 10 / line-height 18 / padding 0/5）、方卡 chip 20（base.css:474-495，font 11 / lh 20 / padding 0/7）、图文方卡 chip 18（base.css:546-556，font 10 / lh 18 / padding 0/6、max-width calc(50%−2px)）。
- 原生：三处均 T.textSecondary 灰字 + glassControlTint 底、无边——`titleRow` chips（Swift:10824-10829，padding 横 6 纵 2、高 ≈16）、`squareTags`（Swift:10651-10676，大：纵 2.5、高 ≈18.2；小：纵 1、高 ≈14）。
- 登记理由：色为单令牌差（且需新增 T 令牌 dyn(0x005BBB, 0x72B7FF)，与 C-A6 的 glassLabel 令牌同属「T 缺 glass-label 族」缺口，建议随 A6 落码时一并把该令牌族补齐、B2 的色替换顺手带上）；高差 ≤4 且图文方卡 −4 略超微差线，但同属 chip 体系，与色一并登记。

### C-B3 §一 头像回退恐龙尺寸/对齐

- Web：无自定义头像时恐龙线稿 size − 8 = 64、底对齐（list.rs:1638-1652）。
- 原生：`AvatarView`（Swift:9570）：DinoView(size × 0.72 ≈ 51.8)、居中。
- 差：−12.2 且对齐不同。登记理由：单点数值差、改法明确（size − 8 + .bottom 对齐），但属回退态装饰面，排在 A 后。

### C-B4 §一 紧凑胶囊材质档

- Web：glass-overlay（base.css:89-111）。
- 原生：`CompactTitle`（Swift:10924-10935）用 glassCard（content 档）。
- 差：材质档一档。登记理由：CompactTitle 与子页 ChromeView 共用，改 overlayCard 影响全部子页页头（Web .page-title.compact 在各页同为 overlay，方向一致），但属观感细差；与 C-A2 同视图，A2 落码时可顺手评估，不单列。

### C-B5 §二 搜索胶囊四小差

- 触发图标 17 vs SVG 20（Swift:10252）；展开图标 15 vs 18（Swift:10233）；触发文字色 T.textSecondary vs --glass-label-color（Swift:10256，同 C-B2 令牌缺口）；展开态材质 glassCard vs glass-overlay（Swift:10248）。
- 登记理由：图标 ±3 为 SF/SVG 字形度量差（全 app 同型）、色与材质各一档，均单点微差。

### C-B6 §四 分组头 tracking 与组间合成距

- 分组头：Web 14/600 + letter-spacing 0.3（editor.css:139-146）；原生 `groupHeader`（Swift:10726-10735）14 semibold、无 tracking。
- 组间合成：Web 文本上 28 / 下 6；原生 27 / 9（差 −1 / +3，成因 = 卡 inset 3 叠组头 insets）。
- 登记理由：tracking 0.3 中文标签无感、合成距差 ≤3，均微差。

### C-B7 §五 窄屏新建卡天气两小差

- 位置距：Web 天气块与左列最小间隔 = item gap 12 + .newcard-weather padding-left 12 = 24（base.css:161、192）；原生 `newCardRow`（Swift:10692-10714）HStack spacing 10 + Spacer(minLength: 0)，最小间隔 = 10（Spacer 两侧各 10 中的近侧一段 + 0 = 实际下限 20，审计按 10 计，同量级微差）。
- 城/况行 gap：Web 列内 gap 4（base.css:192）；原生 VStack spacing 2（Swift:10701）。
- 登记理由：仅左列文案长到顶格时才显形，微差。

### C-B8 §八 窄屏空状态度量组

- 内距：Web padding 56/24（editor.css:132）；原生 `emptyRow` 纵 48、无横向约束（Swift:10912）。
- 说明：Web 13 / line-height 1.55 / max-width 280（editor.css:137）；原生 13、无 lineSpacing、无 maxWidth（Swift:10902-10904）。
- 动作钮：Web padding 9/22、margin-top 10（editor.css:138）；原生 横 16 纵 8、top 6（Swift:10905-10911，与 VStack spacing 8 合成 14 vs Web 18）。
- 登记理由：数值模板现成（gridEmpty 已按 Web 值落地，可直接抄其常量），但空状态为低频面，整组 ≤8 差，登记待排。

### C-B9 §九 网格组头

- Web：13/600、padding 8/2/0、margin-bottom −6（与网格 spacing 14 合成距首卡 8）、色 --glass-label-color、letter-spacing .02em（base.css:390-401）。
- 原生：gridHome 组头（Swift:10342-10349）：13 semibold、T.textSecondary、padding top 8、无负下距 → 距首卡 14（+6）。
- 登记理由：合成距 +6 略超微差线，但实现需负 padding/offset 动网格行距体系，与色令牌缺口同面，整组登记；若 C-A4 落码时同文件顺手，可评估把 −6 以 `.padding(.bottom, -6)` 带上（LazyVGrid 行距对负 padding 的响应须落码时实测，不在本登记内预断）。

### C-B10 §九 图文方卡 meta 行高

- Web：12 / line-height 1.35（base.css:557）。
- 原生：`squareImageCard` meta（Swift:10625-10627）12、无 lineSpacing（默认 ≈1.2）。
- 登记理由：单行截断（lineLimit 1）下行高差不可见，纯登记。

---

## 建议落码序（A 级在前）

1. **C-A1 撤销 toast 整组** —— 形态差最大、独立视图、无几何联动，单独成版可真机判读。
2. **C-A3 子列间隔 34** + **C-A8 列表底部尾行** —— 同为 List 行体系常量/增行，互不干扰，一笔落。
3. **C-A2 胶囊顶对齐** —— 一行修饰符，前提是 A1 版已判读页眉无回归后再动页眉。
4. **C-A4 ≥1280 页眉约束** —— 依赖 NavState 新增 homeW，与 A2 同属页眉面，紧随 A2、同一版内分两笔提交（出问题可单独回退）。
5. **C-A6 展开钮药丸**（含新增 T.glassLabel 令牌）+ **C-A7 标签布局** —— 同在 metaRow/titleRow 相邻面，一版落；C-B2 的 chip 色替换可在此版顺手带（令牌族同批补齐），提交信息注明含 B 级顺手项。
6. **C-A5 网格天气排布** —— 网格面独立，最后落。
7. **C-A9 文案两条** —— 任意一版顺手带，不单独成版。

B 级余项（C-B1、B3、B4、B5、B6、B7、B8、B9、B10 及 B2 的高差部分）维持登记，待 A 级全清后由用户决定是否再排一轮微差批。
