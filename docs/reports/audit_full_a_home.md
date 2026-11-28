# 全面审计 A 片：首页与列表（只读审计，2026-11-27）

> 基线：HEAD `b682d02`（0.9.61 组版后）。工作树有他线在途改动（状态栏采样线：MomentApp.swift / MomentEditorTransition.swift / build-app2.sh / verify_ios.sh 已改 + MomentStatusBar*.swift 未跟踪），本片涉及其 hunk 一律按 HEAD 已提交形态与现行文件并读、单独注明；状态栏面按任务排除不审。
> 范围：原生首页/列表面——时间流与日期分组、卡片形态、封面派生、搜索（FTS 命中集）、头像功能、横屏网格、双栏（首页网格列 / 编辑双栏仅交叉引用）、列表滚动与冷启呈现。
> 真源：Web 源码（`rust/apps/web/src/list.rs`、`main.rs`、`styles/base.css`、`editor.css`；`rust/crates/core`、`storage`）为第一真源，用户裁定（MEMORY.md / AGENTS.md 在册条目）为最高准绳。
> 基线报告：plan_selftest_coverage.md、audit_home_other_deep.md、audit_landscape_wide.md、audit_detail_home.md、audit_wide_list.md、fix_home_grid_landscape.md、fix_home_card_spacing.md、fix_home_header_vanish.md、release_0.9.61.md。
> 证据分级：proven = 源码机制实证（代码在位/缺席可 grep 复核）；inferred = 代码可读但行为后果依赖运行时/数据形态；unknown = 须桥场景/探针/真机取证，文中注明取证法。静态像似不写 proven 的行为结论。
> 纪律：只读审计，除本报告外未写任何文件、未跑构建、未动 git。

---

## 一、回归抽查（必做六项，逐项回源核对）

| # | 抽查项 | 结论 | 证据 |
|---|---|---|---|
| ① | 日期组内图文↔文本卡上下间距 = 12（0.9.59 用户改定） | **在位（proven）** | `MomentApp.swift:18692` 分隔行 `Color.clear.frame(height: 6)` + `.listRowInsets(EdgeInsets())` 显式零 insets；合成 = 上卡 inset 3 + 6 + 下卡 inset 3 = 12。同段注释完整保留沿革账（Web 22 构成 → 0.9.57 insets 归零 → 用户 2026-11-27 改判 12，覆盖 parity）。同子列卡间距 6（insets 3+3）、网格 gap 14 未被连带改动，与裁定面一致。verify F30-14 已改锚 12（verify_ios.sh:3768-3787，本机文件含他线在途改动、锚文本在位）。运行时量距（36px@3x）仍归真机终判，见 fix_home_grid_landscape §九·3——代码面无缺口 |
| ② | 横屏日期组标题整行全跨 + 网格 3 列（0.9.59 根治，核机制非断言文本） | **在位（proven，机制级）** | `gridHome`（:19260 起）结构已按组块化重构：全跨元素（只读横幅/notice/组标题/空状态）全部移出 `LazyVGrid`、置于外层 `VStack(spacing: 14)`；每组 = `VStack { 组标题; LazyVGrid { gridSublist img; gridSublist txt } }`（:19292-19320）。`gridHome` 段内 `.gridCellColumns(` 计数 = 0——死修饰退役属实（全仓仅剩 2 处在 :14474/:14508，为编辑器 eager Grid 合法用法，非首页面）。列数推导单点 `syncHomeSize`（:18853-18868）：`wide = 宽≥768 \|\| (宽>高 且 高≤560)`、`cols = 宽≥1280 ? 4 : 3`，写点 `nav.homeCols` 唯一、消费点 `gridColumns`（:19338 `count: nav.homeCols`）唯一，与 Web base.css:371/613 逐项同构。框序亦已修：`.padding(.horizontal, 24)` 先于 `.frame(maxWidth: 1240)`（:19330 区段），1240 含内距、内容宽 1192，audit_landscape_wide L-1 销账成立。verify F30-18/F30-19 结构锁在位（verify_ios.sh:3889-3925）。真机三档形态（852 三列标题整行 / 1180 / 1366 四列）仍待用户终判，属呈现确认非机制缺口 |
| ③ | 封面派生 = doc 数据序第一张自有图、候选/排除清单与裁定一致 | **主体在位、新分叉见 A-01** | 探针 `cover(names:types:)`（:16602-16660）：对 `blocks.map { $0.node }` 按数据序深度优先（节点先于 children、同层按序）递归，首命中即返回——顺序口径与 Web `cover_source` 的 `doc.iter().find_map(cover_in_node)`（list.rs:988-990）同构。候选：image / gallery 首可用项 / imgTextCard / imageTextRow / attachment 图片项（`image` 标志或清单判图 attIsImage：MIME 优先、名兜底，与 Web `att_file_is_image_raw` 同序）；排除：musicCard/link-card 封面（switch 无此 case、meta.cover 不入探针，:15047 的 cover 仅卡内呈现）、video、MD 内嵌图、列表外封面——均无误接（proven）。图文卡判定 `hasImageShape`（:17343-17396）与封面同源 ∪ 顶层图类块，与 Web `has_image`（list.rs:674-682）同构。**分叉**：URL 白名单与 imgTextCard 取数口径与 Web 不一致，单列 A-01 |
| ④ | 搜索命中集 P3 口径（0.9.59 落） | **在位（proven）** | 计算单点 `computeSearchHits`（:2306-2333）：FTS（FFI `searchIdsJson`）∪ 已加载 memos 的 haystack 补扫，结果按 memos 序重排；`search()` / `bridgeSearchIds()` / 失效刷新三路共用。陈旧根治在位：`searchQuery` + `searchHitsVersion` 与 searchHits 三同步（:375-386 账、:2337-2380 每条置 hits 路径同步记账）；`touchMemos()` 版本 bump 后单点调 `refreshSearchHitsIfStale()`（:1465-1495，全仓唯一调用点），守卫三条件（hits 在位 / query 非空 / 版本不等），重算失败保持原集不钉死、变化才记 Diag 行。audit_home_other_deep §2.1(a)「命中集仅 search() 内赋值」的旧账**已销**。haystack 本体见 A-02 附记与 §三旧账表 |
| ⑤ | 页眉消失根治 ScrollOffsetSanitizer 在位 | **在位（proven）** | `ScrollOffsetSanitizer`（:18294-18350）：三机制齐全——未落定（bounds 任一维 0）不发布、静止带（<15）跨入命中门带须两读确认（候选制）、毛刺废弃经 `discardedPeak` 由探针记 `APP home scrollprobe spike discarded` Diag 行（:18195-18205 feed 单点）。探针本体：KVO 双观察 + attach 同步首读 + 120ms 挂载复读（:18115-18190），`findScroll` 已硬化为子树面积最大者（:18240-18260，先序首胜零残留）。`compactP` 收敛纯函数 `HomeHeaderMath.compactP(forOffset:)`（:18262-18268），ListView 委托单源（:19020-19023）。verify F30-20..23 分锁在位。真机四场景终判（冷启/往返/旋转/回弹）仍归用户，见 fix_home_header_vanish §八——机制面无缺口，发生频率分布 unknown（待新 Diag 面回收） |
| ⑥ | 首页时间流分组口径与 Web 一致 | **在位（proven）** | `assembleGroups`（:18536-18620）：置顶独立组恒首；`bucket()` 用 `Calendar.startOfDay` 日历日差：≤0 今天 / =1 昨天 / ≤7 过去7天 / ≤30 过去30天（含端点，H1 已修）/ 同年 `m-{月}` / 跨年 `y-{年}`——与 Web `section_label`（list.rs:744-757）逐档同值（Web W-2 年分量误取已在 Web 侧修、双端现一致）。归组键 `bucketDate`（:16670-16673）= createdAt 优先、解析失败回退 updatedAt，与 Web 同口径。组序 = rest（置顶剔除后库序）扫描的桶遇见序，与 Web `build_groups` 同；组内图/文分区在 MemoGroup init 一次算清（:18456-18500，同谓词同序、存量属性，非每趟重探）。跨时区漂移双端同幅、非缺陷 |

**六项总判：机制面全部在位、无回潮。** ①⑤⑥ 为完全销账；② 机制销账、余真机呈现终判；③ 主体销账、余 A-01 分叉；④ 销账、余 A-02 新发现（短查询通配符，非 P3 本体回潮）。

---

## 二、新发现（本轮首次登记）

### A-01 封面探针 URL 口径与 Web 分叉三处（缺陷，低频）｜proven（代码差）／后果 inferred

现状（原生 `cover`，MomentApp.swift:16602-16660）vs 应然（Web `cover_in_node`，list.rs:992-1045）：

1. **imgTextCard / imageTextRow 的 URL 回退**：Web 此两型只取 `file_id`（无 URL 路）；原生与 image 同支处理，fileId 缺失时回退 `attrs.url ?? attrs.src` 返回 URL 封面。导入文档中带 url 的图文卡会派生出 Web 不派生的封面（且 hasCover 同源受影响、可能改变图/文分区）。
2. **URL 白名单缺席**：Web 对 image/gallery 的 URL 一律过 `safe_image_url`（crates/core/src/inline_html.rs:83-94：http(s) 或 data:image/(png|jpeg|gif|webp|bmp|avif);base64，其余置空并**继续找下一候选**）；原生直接返回原串、无过滤。非白名单 URL（如 `file://`、非法 data:）在原生会被当封面交给 `ImageLoader`（:3770 `URL(string:)` + URLSession），Web 则跳过该候选继续下探——同数据双端封面可不同。
3. **空串 URL 截断探针**：原生 image 支 `if let u = url ?? src { return (nil, u) }`，u 为空串时仍返回；`hasCover` 以 `c.1 != nil` 判有封面（:16662-16666），空串即判「有封面」且探针不再下探后续真图。Web 空串经白名单过滤为 None、继续 find_map。gallery 支同病（首项 url 空串即返回）。

影响面：仅含上述形态节点的备忘（导入旧数据/跨端 ZIP 互通数据为主要来源，原生新建路径不产此形态，inferred 低频）。修复方向：探针 URL 出口单点过白名单等价过滤（Swift 侧实现 safe_image_url 同规则或经 FFI 复用 core）、空串视为无、imgTextCard/imageTextRow 去 URL 回退——三处同点收口，勿在消费方（卡片视图）打补丁。

### A-02 FTS 短查询 LIKE 通配符未转义，命中集可过宽（缺陷，低）｜proven（代码差）／触发 inferred

现状：`rust/crates/storage/src/lib.rs:588-613` `search()`——查询 <3 字符时回退 `title LIKE %q% OR plain_text LIKE %q%`，q 未转义 LIKE 通配符：q 含 `%` 时匹配全库、含 `_` 时单字通配。Web `matches_search`（list.rs:758-766）为小写子串 `contains`、无通配 semantics。原生命中集 = FTS/LIKE ∪ haystack 补扫（computeSearchHits），LIKE 的过宽结果直接进呈现集，haystack 的字面包含救不回过宽侧。
影响面：1–2 字符查询且含 `%`/`_` 时（多为误输入），结果集大于 Web；≥3 字符走 FTS 短语查询、引号已转义、无此问题。修复方向：LIKE 路径对 `\ % _` 转义 + `ESCAPE '\'`，一行级、加 storage 层测试样本（`%`、`_`、`\` 三样本）。

附记（同族微差，登记不单列）：原生 haystack 的 meta.url 未做 data: 过滤（:2428-2436 白名单键含 "url" 直取），Web walk 对 url 类字段滤 data: 前缀——仅当用户以 data: 载荷片段为查询词时过命中，无实际场景，归 A-02 修复时顺手对齐即可。

### A-03 文档漂移：矩阵 HOM-16 仍记「卡间距账 22」与现行裁定 12 相左（文档缺陷）｜proven

`plan_selftest_coverage.md:147`（HOM-16 行）仍写「卡间距账已改锚 22 改定（0.9.58…分隔行高 16）」，而现行代码与用户 0.9.59 改定为分隔行高 6 / 合成 12（抽查 ①）。矩阵是覆盖状态的权威索引，此行会误导后续探针按 22 量距。提案：HOM-16 行改锚 12 并注改判出处（fix_home_grid_landscape §五）。

---

## 三、旧账未销（自基线报告继承，逐项回源复核仍在）

### A-04 页眉命中死区 p∈[0.5,1) 仍在（audit_home_other_deep §2.8a / 矩阵 HOM-21）｜proven

`header`（:19030-19090）：头像与搜索胶囊 `.allowsHitTesting(compactP < 0.5)`、紧凑标题胶囊 `.allowsHitTesting(compactP >= 1)`——p∈[0.5,1)（距顶 15–30pt 行程）三件皆不可点。Web 头像 pointer-events 至 p≥1 才关。ScrollOffsetSanitizer 的命中门带（15）正是按此 0.5 阈值定义，两处联动：若按旧提案把阈值对齐 p<1，消毒带常量须同步改判，勿只改呈现层。影响：15pt 行程内的点按落空，低频但属用户可感知面。

### A-05 网格组头缺 uppercase（audit_home_other_deep §2.12b / 矩阵 HOM-22 半项）｜proven

网格组头（:19302-19312）有 `.tracking(0.3)`、glassLabel 色、负底距，**无 `.textCase(.uppercase)`**；窄屏组头（:19795）与 SectionHeader（:20186）均有。Web `.section-header` 的 uppercase 对两形态同适用。中文组名无感，en-US 等语境下「November」类组名与 Web 形态差。一行补齐，无连带。

### A-06 网格图文方卡折叠态无展开药丸（audit_home_other_deep §2.12a / 矩阵 HOM-22 半项）｜proven

`squareCard`（:19476 起）：`expand` 闭包只下传 `squareTextCard`（其 meta 行有 squareFoldPill，:19581）；图文方卡 `squareImageCard(memo, collapse:)`（:19508 调用点）不收 expand——折叠态（>2 未展开）图文方卡只有整卡点按展开 + 幽灵叠卡，无「展开 N 条」药丸；其**收起**药丸已在 meta 行在位（:19630，小差 9 已修）。即旧账半销：收起侧已补、展开侧仍缺。功能可达，属呈现冗余缺一。

### A-07 左滑 / 网格菜单动作不辞焦（audit_home_other_deep §2.1c / 矩阵 HOM-04 登记）｜proven

窄屏 swipeActions（:19882-19901）删除/置顶、网格 contextMenu（squareCard 内）打开/置顶/删除，均未调 `resignSearch()`；其余离开路径（头像/新建/打开/紧凑标题）均经 resignSearch 收敛。搜索展开态下滑动删改后胶囊仍持焦，与 Web 失焦收起口径微分叉。已登记多轮未落，属收口批存量。

### A-08 横幅/notice 在位时首组头合成距（audit_home_other_deep §2.9 / 矩阵 HOM-23）｜已裁已落（动态适应）

窄屏：横幅/notice 行底 inset 6 + 组头 top 25 = 31 vs 常态 28；网格：notice 为 VStack(spacing:14) 内一行纯 Text、组块同距 14，无 Web 对应行可对齐。旧报告提案（横幅/notice bottom 改 3 回 28）未落。**2026-11-28 用户裁定：不取写死 28（横幅在位反更挤），改动态适应**——已落码（0.9.63）：组头 top 收敛为单点规则 HomeHeaderMath.firstGroupTopInset（按紧邻行 bottom 反推、四邻居态含 loadFailed 态间隔恒 28 且不低于基准、常态 top 25 零变化），verify [57] HG57 量测锁（提取各行实测几何喂宿主实跑、锁量测值）；网格侧统一 spacing 构造两态恒等 22、同批登记。定案见 fix_home_header_gap_adaptive.md。

---

## 四、达标面回源确认（简列，均 proven 代码在位）

- **卡片形态**：文本卡 radius 32 / padding 14·16 / 标题 16 单行 / meta 同段截断（摘要 prefix 80）；图文卡封面 16:9、体 padding 10/16/12、标题 15、摘要 prefix 60；方卡 aspect 1/1、radius 26（`Radius.grid` 令牌）、幽灵叠卡双层同值（0.94/+7/0.68、0.97/+4/0.86）；chip 走 glass-tag 口径（accent 蓝字 + control 底，方卡前 2 + 「+N」）。audit_detail_home 的系统性小差（字重 650→semibold 近似、chip 色/高、展开钮形态）已在历批收口，现行以令牌（T.* / Radius.*）与 ScaledMetric 喂点表达，ListView 段内无裸 `.system(size: <字面量>)` 残留（grep 零命中，字号全经 f* ScaledMetric 或 groupFontSize/metaFontSize）。
- **文字大小跟随系统（首页面）**：ListView 已补齐 ScaledMetric 全套（:18410-18445 区段，group/meta/titleScale + f10–f17 多档），audit_home_other_deep P2-1 在**首页面**已实装销账；设置族/编辑器面属他片，不在本片判读。
- **头像功能**：首页头像 = 真 Button（:19033-19040），resignSearch 后 `nav.dest = .settings`，满足「头像有实际功能」红线；回退 = glassControl 圆 + DinoView(size−8) 底对齐（:17520-17530），audit_detail_home 的恐龙尺寸/对齐差已修。编辑页头像（per-memo 自定义头像经 .momentAvatarChanged 刷新）属编辑片交叉面，本片仅核首页入口。
- **搜索呈现链**：胶囊常驻层 + 触发层结构（:19100-19190），字段恒在层级、宽由焦点派生 0↔140；activateSearch/resignSearch 单点收敛，src 记账齐全；空结果三态双形态同源（emptyRow / gridEmpty :19360 起，含搜索态标题带 query、动作「清除搜索」）。
- **折叠组**：双形态同口径——子列 >2 未展开只显首卡、N = 子列总数、展开键 `{group.id}-{kind}` 语言无关（定案偏离、原生更优，不翻案）、展开后末卡收起；存储域为会话内存集，与 Web use_signal 等价。
- **置顶/左滑/撤销**：togglePin 无条件刷新 updatedAt 并全表重排；swipeActions(edge:.trailing, allowsFullSwipe:false) 删除（destructive 最外）+ 置顶（orange），系统实现定案；softRemove 打标落盘 + 8 秒独立 armDeletion、undo 回插按 (pinned, updatedAt) 全序回原位；toast 已改 Web 全宽条形态（C-A1，:19200 区段）。
- **列表滚动**：窄屏 List 无 Section（梯子禁区守恒）、全行显式 listRowInsets（F30-13 计数锁口径，抽查 ① 段复核分隔行/底部行/空行均带声明）；归组结果按 (memosVersion, manifestVersion, searchHits, lang) 缓存（:18505-18530），body 重演算不重跑封面探针——冷启/新建转场的主线程长尾治理在位。
- **冷启呈现**：根 ZStack 分流（MomentApp.swift:21885-21920）——安全模式不构建 ListView、不挂开屏宿主；正常模式 SplashHostView 在 resourcesReady 时挂载、didLoad 后消散口径与 LCH-01 清单一致；判定前移 Library.init、load 步序与 SMOKE 行（含失败路径同前缀行，LCH-11 已由救援完整性批落）属启动片交叉面，本片仅核首页侧呈现分流无回潮。
- **双栏（交叉引用）**：编辑页双栏本体属编辑片；与本片相关的仅两点回源确认——independent 栏内距已按 Web 补齐（左栏 trailing 16 + 线贴左栏右缘 + 右栏 leading = gap+15，:13450-13500 区段，audit_landscape_wide L-2 销账）、flow 恒两物理栏整页滚动 + 规范分界，与「宽屏流式不跨栏」裁定一致。首页侧「双栏」即网格列形态，已在抽查 ② 覆盖。

---

## 五、unknown 清单（运行时才能定，附取证法）

| # | 项 | 取证法 |
|---|---|---|
| U-A1 | 横屏首卡左缘 x（系统安全区承接是否成立，audit_landscape_wide V-1） | 真机横屏截图量测：≈83（59+24）成立 / ≈24 须补横向 inset |
| U-A2 | 间距 12 与网格三列/标题全跨的真机呈现（抽查 ①② 的呈现侧） | 真机：竖屏量交界背景段 ≈36px@3x；横屏三档（852/1180/1366）各截一屏 |
| U-A3 | Sanitizer 毛刺源频率分布（首帧/重挂/旋转三源各占几何） | 0.9.59+ 真机 Diag 导出按 `spike discarded` / `compactband` 行统计（fix_home_header_vanish §八判读法） |
| U-A4 | 左滑与整卡点按、网格长按菜单与点按的系统仲裁手感 | 真机手势走查（合成事件不算，AGENTS.md 验证清单） |
| U-A5 | 冷启首帧耗时与开屏消散时序（firstFrameMs 量级、大库冷启） | 桥场景 app_state/diag_tail 抽样 + 真机冷启走查 |
| U-A6 | 搜索清除/回车后焦点去向与键盘收起手感 | 真机（HOM-03/04 的 U5 场景建成后可半自动判读） |
| U-A7 | A-01 三分叉的实际数据命中率（存量/导入数据中带 url 的 imgTextCard、非白名单 URL 首图占比） | 桥只读抽样：notes_list 后按 doc 形态统计，或 Diag 侧封面派生落空行抽样 |

---

## 六、修复分批建议（仅建议，本片不落码）

| 批 | 内容 |
|---|---|
| 封面/搜索收口批 | A-01（探针 URL 单点过滤 + imgTextCard 去 URL 回退 + 空串不截断）、A-02（LIKE 转义 + storage 测试样本 + haystack meta.url data: 过滤顺手对齐） |
| 首页微差批 | A-05 网格组头 uppercase（一行）；A-06 图文方卡展开药丸（expand 下传 squareImageCard、meta 行同位）；A-07 左滑/菜单辞焦收口 |
| 须裁后落 | A-04 命中阈值 p<1（与 Sanitizer 门带常量 15 联动改判，须同批动两处并改 F30-21 锚）；A-08 横幅/notice 组头距（调优裁决） |
| 文档批 | A-03 矩阵 HOM-16 改锚 12 |
| 真机一轮 | U-A1/A2/A4/A6 随下版装机走查关账；U-A3/U-A5 随 Diag 回收判读 |

## 七、矩阵增补候选（对 plan_selftest_coverage.md）

1. HOM-07 增补样本：封面派生三分叉样本（url 形 imgTextCard、非白名单 URL 首图、空串 url 后跟真图）——双端封面一致性断言（BK 桥回读可判）。
2. HOM-05/DAT-03 增补样本：短查询通配符（`%`、`_`、`\`）命中集与 Web 子串口径一致（BK，storage 测试 + 桥 notes_search）。
3. HOM-16 行改锚（见 A-03，非新增行）。
4. HOM-22 状态更新注记：收起药丸已在位、仅余展开药丸 + uppercase 两半项（A-05/A-06）。
