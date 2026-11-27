# 搜索命中集陈旧根治（P3）——设计与落码清单（停门稿）

> 状态：**已落码**（2026-11-27，落码门已开：HEAD cb8ff18、开工快照树净；未提交、未 bump，随下一组版）。落码实录见第七节。
> 出处：audit_home_other_deep.md §2.1(a)（本轮首页唯一功能性新发现，主线已复核）；覆盖矩阵 HOM-03/04/05（搜索景归 U5，本批为其前置修复）。

## 一、定性对账（proven，源码行级）

- `Library.searchHits`（MomentApp.swift:375，`@Published var searchHits: [String]?`）全仓赋值点只在 `search(_:)`（2164–2215）内：空查询置 nil、库未开/FFI 失败置 []、成功置命中 id 序。persist / 编辑返回 / reload 均不重算——与审计 §2.1(a) 逐字吻合。
- 后果链：结果中打开一篇删掉关键词、返回首页，该篇仍在结果里，下一键才自愈（Web 为每渲染反应式重滤，原生为快照式命中集，快照无失效机制即本缺陷本体）。
- 陈旧的实际咬合面（消费侧通读后收窄）：`ListView.visibleMemos`（16794）以现行 memos 按 hits 过滤——**删除/新增在 id 层天然自愈**（不在 memos 者不显、不在 hits 者不入）；真正脱节的是**内容变更**：已命中篇改到不再匹配仍显、未命中篇改到匹配仍不显（标题提交走 persist 同理）。
- 审计提案（persist 与 reload 收口处若 searchHits != nil 以现 query 重跑一次）方向正确但落点不全：① 查询串不在 Library 手里（归 ListView.NavState.query，17428 绑定逐键调 library.search），收口重跑须先把 query 沉到 Library；② 变更面不止 persist/reload 两点（见第三节），只补两点其余路径仍陈旧，属消费方逐处补刷，不取。本稿以版本失效制根治（第三节）。

## 二、搜索全链通读结论

- **赋值/计算**：search(_:) = FFI `searchIdsJson`（FTS：标题+正文）+ 对已加载 memos 的 `searchHaystack` 补充扫描（Web matches_search 口径），结果按 memos 序。`bridgeSearchIds`（2221）是同一计算的近复制体（不写 hits/不记 UI 日志）——**匹配计算现为两份**，本批顺势单点化（见落码清单 1）。
- **查询归属**：NavState.query（16761，视图侧）；Library 不持有 query，是收口重算缺失的结构原因之一。
- **消费面**：visibleMemos（16794 过滤）、groups 缓存键（16852–16857，**键已含 searchHits 本体**——hits 一换归组自动重键，消费方零改动）、空态呈现两处 `searchHits != nil` 门（17668/18330，仅决定空态文案形态）。推论：根治**不得以置 nil 失效**——会塌掉搜索态呈现且与 NavState.query 失同步；必须以现 query **重算替换**。
- **桥面**：桥写工具同走 Library 六写点（MomentBridgeTools.swift:1664 softRemove、1721 undoDeletion、1821 persist）——桥在手机搜索活跃期改库同在本失效域内，一并覆盖。

## 三、根治设计：命中集并入 memosVersion 失效制（单源）

既有基座（0.9.48）：`memosVersion`/`touchMemos()`（1387–1396）是 memos 派生数据的既定失效真值源——注释明示「版本即失效真值源，漏 bump 即归组过期」，写点全集（reload/create/persist/remove/softRemove/undoDeletion 六处 + load 清零 785）由 verify [15] 计数锁定，全部经 touchMemos() 单漏斗。searchHits 是唯一没进这套体制的 memos 派生物。本批不新建机制，把它并入：

1. **计算单点**：抽 `computeSearchHits(query:) -> [String]?`（FTS + haystack 补充扫描 + memos 序；库未开/FFI 失败回 nil），search(_:) 与 bridgeSearchIds 改为共用，匹配逻辑全仓一份。search(_:) 的既有日志/徽标口径（0 命中记行、logOnce、ErrBadge）留在 search(_:) 层，不随计算下沉。
2. **状态沉淀**：Library 新增 `private(set) var searchQuery: String?` 与 `private(set) var searchHitsVersion: Int = -1`。search(_:) 每次调用同步三者：成功/失败置 hits 时记 query 与当时 memosVersion；空查询三者同清（hits=nil、query=nil、version=-1）。
3. **失效触发单点**：新增 `refreshSearchHitsIfStale()`，唯一调用点 = **touchMemos() 内部**（版本 bump 之后）。守卫：`searchHits != nil && searchQuery 非空 && searchHitsVersion != memosVersion` 才重算；重算经 computeSearchHits 替换 hits 并对齐 version。触发面自动覆盖六写点 + 导入（经 reload）+ 桥写（同漏斗），无一处消费方补刷。
4. **日志口径**：刷新不复用逐键日志；仅当命中集实际变化时记一行 `APP search refresh hits=<n> src=libchange`（结果侧量测，静默无变化刷新不记行）。
5. **守恒项**：
   - 空查询/未搜索：hits=nil ⇒ 刷新恒空转（守卫首条），load/reload 早期 touchMemos 零副作用。
   - 只读态：写点被 writeBlocked 拦、版本不动，无刷新；只读 reload 的版本 bump 触发一次只读 FFI 重算，结果与新镜像一致，正确。
   - 成本：刷新 = 一次 searchIdsJson + 全量 haystack 扫描，与逐键 search 同成本类，仅在「搜索活跃 ∧ 库刚变更」时发生（编辑保存回首页即此场景，一次/保存），可接受。
   - 顺序前提（落码时逐点复核）：现行各 touchMemos() 调用点均在 memos 赋值完成之后（reload 1139 在 async 块内 memos 赋值后、persist 1378 在 memos[idx] 更新后）；余下点（785/1235/1257/1447/1470）在落码时逐一核「先赋值后 touch」序，不成立的点先调序再挂触发。
   - @Published 时序：touchMemos 调用均出自主线程动作/回调链（persist、reload 的 main.async 块等），刷新内写 searchHits 不引入新的跨线程发布。

## 四、落码清单（门开后执行）

1. MomentApp.swift：抽 computeSearchHits（search/bridgeSearchIds 共用，删复制体）；Library 增 searchQuery/searchHitsVersion 两字段与 search(_:) 三同步；新增 refreshSearchHitsIfStale 并在 touchMemos() 内单点调用（bump 后）；刷新变化记 Diag 一行。
2. 逐点复核 touchMemos 七调用点（785/1139/1235/1257/1378/1447/1470）的赋值-调用序，必要处调序并在报告落码节记录。
3. verify 断言（并入 [30] 首页组续号，锁机制不锁表象）：
   - SH-1：searchHits 赋值点全集 == {search(_:)、refreshSearchHitsIfStale}（计数锁，含三同步字段同点）；
   - SH-2：touchMemos() 内 refresh 调用恰 1 处，全仓 refresh 调用点 == 1；
   - SH-3：computeSearchHits 定义恰 1 处、调用点 == {search、bridgeSearchIds、refresh} 3 处；
   - SH-4：refresh 守卫三条件（hits 非 nil / version 不等 / query 非空）在位。
4. 本机自跑 [30]/[15] 组全绿 + MomentApp primary 遍类型检查零错误。

## 五、不在本批

- 审计 §2.1(b) haystack walk 三处细差（候选待裁）、(c) 左滑/网格菜单动作不辞焦（已登记微分叉）——均不在本批，勿顺手带。

## 六、真机终判口径（落码后随组版）

- 搜关键词 → 打开命中篇 → 删掉该关键词 → 返回：该篇立即消失于结果（不按键）；反向：未命中篇改入关键词 → 返回后出现。
- 搜索活跃置于首页时，桥侧改一篇标题/正文，命中集随之更新（Diag 见 refresh 行）。
- U5 home_search_cycle 建景时可把上两条的状态机侧落为景断言（HOM-03/04）。

## 七、落码节（2026-11-27）

### 实际落点（MomentApp.swift，行号为落码后现行值）

1. **状态沉淀**（375 后）：`searchHits` 声明下新增 `private(set) var searchQuery: String?` 与 `private(set) var searchHitsVersion: Int = -1`，附失效账注释（记三同步口径与「不得置 nil 失效」的理由）。
2. **计算单点**（2312）：`computeSearchHits(query:) throws -> [String]?`——FTS + haystack 补充扫描 + memos 序整段自 search 本体移入（补充扫描口径注释随迁、逐字保留）；`search(_:)`（2335）与 `bridgeSearchIds`（2394）改共用，桥内嵌复制体整段删除（桥口径不变：空查询回 []、库未开/FFI 失败回 nil，经 try? 收口）。
3. **三同步**：search 四条置 hits 路径全同步记 query 与当时 memosVersion（空查询三者同清：hits=nil、query=nil、version=-1；lib 未开/成功/FFI 失败三路同记）。search 既有日志/徽标逐字保留（「搜索失败（库未打开）」/「搜索失败：\(error)」/0 命中行/logOnce/两处 ErrBadge 含 detail 均未动）。
4. **失效触发单点**（1463/1481）：`touchMemos()` 改多行体，版本 bump 后调 `refreshSearchHitsIfStale()`；刷新守卫三条件（hits 非 nil、query 非空、version 不等）同在函数体内；重算成功才替换 hits 并对齐 version，实际变化记一行 `APP search refresh hits=<n> src=libchange`，无变化静默。
5. **刷新失败口径**（设计未明示项，按守恒取向定）：重算失败（库未开/FFI 错）保持原集且**不对齐 version**——下个写点自动重试，不把暂态失败钉成陈旧集；失败不记行（§三.4 只记实际变化）。

### touchMemos 七调用点赋值-调用序复核（设计 §三.5 顺序前提）

七点全数「先赋值后 touch」成立，**无一处需调序**：prepareNormalStart（memos 置空后）、reload 的 main.async 块（memos 赋 visible 后）、softRemove（removeAll 后）、undoDeletion（append+sort 后）、persist（memos[idx] 更新+sort 后，仅 idx 命中时；新建路径由 create 自身 touch 覆盖）、create（insert 后）、remove（removeAll 后）。

### 断言实跑

- verify [30] 组续号 **SH-1..4 已并入并全绿**：SH-1 写点全集（`searchHits = ` 恰 5 = search 4 + refresh 1；`searchQuery = query` 恰 3、`searchQuery = nil` 恰 1）；SH-2 触发单点（`refreshSearchHitsIfStale()` 恰 2 行 = 定义 1 + touchMemos 内调用 1）；SH-3 计算单点（`computeSearchHits(query:` 恰 4 行 = 定义 1 + 调用 3）；SH-4 守卫三条件取段核在位。
- 本机全量 verify：402 ✓；[15] T15-1 保持绿（`touchMemos()` 计数恒 8——定义改多行体不增行数，注释刻意避用带括号字面防误计）；[30] 组 21 条全绿（F30 17 + SH 4）。余红仅既有产物两项（ipa 陈旧、产物语言包，构建自解），与开工基线同集（基线另有 BK40 两红系同期桥呈现批在途形态，落码期间已转绿，非本批面）。
- MomentApp primary 遍类型检查（build-app2.sh 同旗标、本机 swift-frontend）：exit 0、error 0、.o 产出。
- 同树对账：开工快照的他人在途改动（MomentOps.swift / MomentBridgeOps.swift）完工 diffstat 与开工时逐字一致、零损伤；本批落点计数完工复测恒定（六项计数与断言期望全等）。

### 与设计的偏差（一处，签名级）

设计 §三.1 草签 `computeSearchHits(query:) -> [String]?`（库未开/FFI 失败同归 nil）。落码作 `throws -> [String]?`：nil 只表库未开，FFI 失败抛错。理由：设计同时要求 search 既有日志/徽标口径留在 search 层（§三.1 末句），其中 FFI 失败行与徽标 detail 须带 `\(error)`（批 C 定案口径）——草签下 error 在计算层被吞、search 层无从记全，两条设计要求不可兼得，故以抛错保全两者。桥与刷新两路仍按设计同归静默（try? 收口：桥回 nil、刷新保持原集）。失效架构、三同步、守卫、断言计数均未受影响（SH-3 计数按定义 1 + 调用 3 不变）。

### 真机终判（沿第六节，随下一组版）

搜关键词 → 打开命中篇 → 删掉该关键词 → 返回：该篇立即消失（不按键）；反向改入关键词返回后出现；搜索活跃时桥侧改标题/正文，Diag 见 `APP search refresh … src=libchange` 行且命中集随之更新。
