# fix_home_row_registry — 首页 home.row 注册面发布/注销可靠性定案 + 根治

日期：2026-11-28。触发：0.9.64 真机桥自办 U5 三景 + home_geometry 探针实跑证据。
基线 HEAD 3259529（作业中 HEAD 前进至 94c9ab2，本批提交叠其上）。

## 一、实跑证据（0.9.64 真机）

- home_search_cycle（3122cd33 / 7ea4dcaa）：一遍止步 6 `hits_fresh_after_edit`——
  hits=0 正确，但夹具行在标题编辑后仍 present；二遍止步 1 `fixture_row_present`——
  新建夹具行未注册（rowState 读 "none"），而同一步命中集断言已过（hits=1）。
- home_surface_roundtrip（dd91f514 / 1c8cd99c）：一遍止步 2「fixture row missing」
  （poll 5s 无行）；二遍止步 1 `dest_home`（act=dest=settings，前序导航态残留）。
- home_list_actions（43259bdb / 8db38c92）：两遍同值止步 1 `cover_is_first_image`——
  poll 5s 后夹具行状态全空（form/isImage/cover 皆 "none"，即条目不存在）；
  旁证 image_page_open 的 gallery 链全过，封面派生函数本身嫌疑低（本批回源复核：
  coverPair/hasImageShape 口径无异常，见三·①）。
- home_geometry 被动旁证：两次读到已删夹具的幽灵行（与真实行同帧、cardGaps 出
  −66.3 重叠值）；收尾复查旧幽灵消失、最新夹具又成幽灵——注销滞后、最终一致。

## 二、触发链对账（回源，proven）

旧制下 home.row 的注册面与模型成员完全脱钩，真值源是 UIKit 细胞生命周期：

- **注册**：条目只由行视图 `.background(UITestAnchor)` 的 `updateUIView` 写入
  `UITestRegistry`。触发条件 = 行视图被实现（realize）——折叠外（sublist/
  gridSublist 的 shown 之外）的行、未滚入实现窗的行根本没有视图、没有条目。
  状态闭包捕获 body 求值时刻的 `memo`/`isImage` 快照，仅在 updateUIView 再跑
  时保鲜。
- **帧**：`RowFrameStore.frames` 由行 GeometryReader 的 onAppear/onChange
  写，**全仓无删除点**——行消失后帧永久残留。
- **注销**：只由锚点 `dismantleUIView` → `unregister(owner:)` 触发，即细胞拆卸
  时机（删除动画/复用节奏由系统决定，无时限保证）。
- **模型侧对照**：`Library.softRemove` 同步摘 memos + `touchMemos()`（版本
  bump + 命中集刷新）；create/persist 同经 touchMemos 漏斗。模型真值即时，
  滞后只在注册面。

结论：注册面契约是「行在位 ⇔ 备忘在呈现行集内」，实现却把真值押在细胞
实现/拆卸上——新建行在场景时间窗内未注册、删行条目跨 run 残留，均为该脱钩
的必然表现（覆盖态下 List 更新是否被系统推迟属 inferred 子因，不影响定案：
真值源选错本身即缺陷）。

## 三、三类归属定案

### ① app 注册面真缺陷（根治对象）

注册/注销触发面缺失「跟随呈现行集」这一笔，帧又只写不清。与 HOM-18 的衔接：
HOM-18（矩阵行，源 audit_home_other_deep §2.1a）登记的缺陷本体是命中集陈旧
（searchHits 不随 persist/编辑返回重算）——该半边已由 P3 收口（touchMemos
单点漏斗 `refreshSearchHitsIfStale`，六写点与桥写同经），源码 + 本轮实跑
hits=0 双证；0.9.64 实跑复合断言红的是行半边，属本节注册面缺陷、不与
HOM-18 本体混同。矩阵 HOM-18 行已回写更正（本批同笔）。

产品面等价症状（用户删篇后行滞留等）：**未证、不升级表述**——注册面是自检
专用面，用户可见列表由 SwiftUI 依 groups 直接渲染、不经注册表；本缺陷的
影响面限于桥自检/探针证据的可信度。

### ② 场景时间窗竞态（景侧修）

home_search_cycle 步 1 的 `fixture_row_present` 在命中集 poll（模型级同步量）
成立后**同步直读**行面，无等发布过程——二遍 614ms 内止步于此。注册面改对账
制后发布仍隔一趟呈现派生，景侧按其余步同式改 poll 等发布（见五）。

### ③ 景非密封（景侧修）

home_surface_roundtrip 首步只断言 dest 为空、不收敛导航态，前序运行/用户
手点留下的 dest=settings 被整景继承、二遍开局即红。景侧自密封（见五）。

### 幽灵行污染 home_geometry（cardGaps −66.3）的单独结论

归 **app 修、探针不改**。根源在注册面：幽灵条目未注销 + 其帧从不清，探针
（枚举注册表条目 × frameInWindow）必然读出。探针侧加成员过滤是消费方打
补丁——且会掩盖注册面缺陷、令其他消费方（各 U5 景）继续吃假真值，违根治
口径。本批 app 侧注销连帧清后，探针读面自净（探针代码零改动）。

## 四、改动（MomentApp.swift，ListView 内）

1. **折叠派生单点** `shownInSublist(group:kind:memos:)`：shown/folded 唯一
   出处，List 子列、网格子列、注册对账三方同消费（旧三处逐字同式收口为一，
   行为等价）。
2. **呈现行集** `shownRows`：与 body 渲染逐项同序同集（组序 → 图子列 →
   文子列、折叠同点收窄），为对账唯一真值源；`rowSyncSignature` = 行
   id/形态/判图串。
3. **对账单点** `syncRowRegistry()`：管辖集与呈现行集对齐——集外经
   `unregisterRow` 注销（注册摘除与帧清同笔，帧不再有独立寿命）、集内以
   稳定 owner 重注册（闭包保鲜）；增减非空记一行 Diag（结果侧量测）。
   触发三面：根视图 `.onAppear`、`.onChange(of: rowSyncSignature)`、
   `.onDisappear { clearRowRegistry() }`。
4. **条目构造单点** `makeRowEntry`：`id: "home.row"` 全仓恰一构造点；动作
   与左滑/网格菜单同体（resignSearch + 模型单点、open 经 openMemo），状态
   与动作改经 `liveMemo(id)` 现查模型（title/pinned/isImage/cover 恒新鲜，
   注册时刻快照退役）；frameInWindow 仍读行帧通道；radius 键仅 list 形态
   （与旧条目键集逐项等价）。
5. **行锚点摘除**：memoRow / squareCard 的 UITestAnchor 注册块删除（帧
   GeometryReader 通道保留）；`RowRegistryStore` 纯存储盒持管辖 owner 表。

## 五、景侧改动（MomentBridgeUITest.swift）

- home_search_cycle 步 1：`fixture_row_present` 改 poll 等发布（5s 内等行面
  标题落定再断言，注记「等发布（fix_home_row_registry」）。
- home_surface_roundtrip 首步：自密封——断言前若 dest 非空经 home.view
  closeDest 同体动作收敛并 poll 落定（注记「景自密封（fix_home_row_registry」），
  dest_home 断言保留为密封验收读。

## 六、断言（verify_ios.sh 新增 [69] 组 HR69-1..6）

锁机制面：① home.row 构造恰一处 + 对账单点/存储盒在位；② 对账三触发齐全；
③ unregisterRow 内注销连帧清同笔；④ liveMemo 现查漏斗（调用点 ≥4）；
⑤ shownInSublist 定义 1 + 消费 4（渲染/注册折叠同源）；⑥ 景侧等发布 +
自密封标记在位。汇总行改 ALL PASS (incl [65][66][67][68][69])。

本机自检实账：
- [69] 组独立抽跑（脚本原码）：**6/6 全绿**。
- cargo test --workspace：**全绿**（126 过、0 败；本批纯 Swift 改动，此项
  为程式登记）。
- verify 全量：作业窗内并行线（状态栏采样拆除线）正在删改
  MomentStatusBar*.swift / build-app2.sh / verify 多组，首轮全量跑被其
  中途删文件污染（SB 组红 + 一处解析中断，皆非本批面）；本批面以 [69]
  抽跑 + 逐项 grep 复核为准，全量复跑随下版组版在 tree 冒烟收口。
- 断言自检一笔：HR69-3 初版模式把帧存储属性名误锁为 names（实为
  frames）——系作者读渲染输出误认标识符所致，字节级复核（od/字符码）
  抓出并改判为点式模式；教训与 AGENTS.md「标识符须逐字回源」同宗，
  本报告留痕。

## 七、留账

- Swift 首次编译门 + 装机复跑（U5 三景各两遍 + home_geometry 探针复读
  应无幽灵行/cardGaps 负值）随下版组版（tree smoke_ios.sh）在主线收口；
  本批本机无 Swift 编译器，未过编译门一事如实登记。
- home_list_actions 的封面断言在注册面修复后应直接读到 live coverPair
  结果；若装机复跑仍红，再按封面派生面另行定案（本批回源未见其异常）。
- HOM-20（折叠组全语义）与本批同消费 shownInSublist 单点，后续景扩展
  不再另起折叠派生。
