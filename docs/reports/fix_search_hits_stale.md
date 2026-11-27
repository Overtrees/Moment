# 搜索命中集陈旧根治（P3）——设计与落码清单（停门稿）

> 状态：**只读准备完成，停门待放行**。0.9.58 组版分拣提交在途（HEAD 已见 bump 笔 4070d70），本稿只含设计与落码清单，未动任何源码；门开后按本清单落码，不提交、不 bump，随下一组版。
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
