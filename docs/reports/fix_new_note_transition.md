# 新建笔记过渡卡顿：排查与根治（0.9.44 真机实报）

用户实报：点新建后，过渡中间明显卡顿一下才进入编辑页。本报告只管「新建 → 编辑页打开」一段（编辑器滚动卡顿是另一条战线，不在此扩散）。落码在 `rust/apps/ios/app/MomentApp.swift` 本地工作树（叠在 0.9.45 自救批之上，未提交、未构建，待主线收口）。

## 一、全链路时序账（点按 → 编辑页首帧落焦）

入口共 4 处，形态一致：`library.create()` → `EditorModel(item:library:)` → `ed.wantsInitialFocus = true` → `nav.dest = .editor(ed)`（gridEmpty :13669 一带、新建卡 :13709、窄屏新建行 :13991、宽屏新建卡 :14292，行号为落码后现值附近）。

| 环 | 做什么 | 主线程量级 | 证据 |
|---|---|---|---|
| 1. `Library.create()`（:922） | 构造 MemoItem（1 空段）+ `persist()`：raw 字典覆写、JSONSerialization、**同步 FFI `upsertMemoJson`**、`memos.insert(at: 0)` | 构造/序列化 O(1)；FFI 为单行事务（FTS 行删+插，crates/storage/src/lib.rs:673-686），**与库量无关**，仅 WAL 提交延迟（典型 1–5ms） | proven（代码） |
| 2. `EditorModel.init`（:4583 起） | 标题/块引用直取、双栏决议（UserDefaults 一读）、尾随空段/MD 尾段物化——对新建空篇均为 O(1) | 微秒级 | proven（代码） |
| 3. `nav.dest` 置位 → **ListView body 重演算** | `groups`（:13257）归组一趟 O(N)（每篇一次 Calendar 日期分桶）；随后每组 `images`/`texts` 被 body 访问：窄屏各 2 次（sublist 实参 + isEmpty 检查，:13230-13243 一带）、宽屏各 1 次。**每次访问 = 对全组备忘重跑一遍 `hasImageShape`**——块扫描，未命中图时再落 `hasCover` 全树递归探针（[String: Any] 字典遍历）。即单次 body 求值 ≈ **窄屏 4 趟 / 宽屏 2 趟全库节点遍历**；每个渲染行/卡再各自重探：`memoRow`/`squareCard` 各 1 次 hasImageShape、图文卡 `coverFileId`+`coverURL` 各 1 趟全树探针 | 随库量线性增长：节点总数 × 趟数。以百篇量级、篇均十余节点估算为**数毫秒至数十毫秒**，且恰好落在点按同轮更新里、push 首帧之前 | 结构与倍数 proven（代码）；绝对毫秒 inferred（待 CREATE timing 实测） |
| 4. push 转场开始（NavigationStack 原生转场 ~0.35s） | EditorView 首帧构建：contentArea（新建篇仅 1 个 BlockRow → UITextView 创建）、EditorHeaderView（标题胶囊 NSString 量宽）、menuPanel 常驻挂载（ScrollView + 约 10 个菜单项整树构建）、多组 sheet/dialog 修饰脚手架；背景 GeometryReader onAppear 回写 ui 尺寸触发紧接着的第二次 body 求值 | 一次性数毫秒级 | proven（代码） |
| 5. EditorView.onAppear（转场进行中触发） | 两行 Diag（内存追加，便宜）；`backlinks(forTitle:)` 对空标题早退 O(1)（:1495）；**旧路径在此置 `focusBlockId`** → EditorModel @Published → 下一轮更新才轮到 BlockTextView.updateUIView 消费 | 前两项可忽略；落焦认领被推迟一整轮状态往返 | proven（代码） |
| 6. 落焦认领（旧路径在转场中段） | `tv.becomeFirstResponder()`（BlockTextView.updateUIView :2201 一带）在 push 进行中被调用 → 键盘升起动画与转场动画同帧竞争，键盘帧变化又触发编辑区（ScrollView）二次布局 → 视觉上即「滑到一半卡顿一下，然后才到编辑页」 | 键盘/转场竞争为系统级编排冲突，非单点耗时 | 机制 inferred（与症状形态、新建独有性互证：打开既有篇不置初始落焦、无此一步、无此报障） |

**被排除项**：FFI 写入（单行事务，见环 1）；草稿构造/EditorModel init（O(1)，环 2）；backlinks（空标题早退，环 5）；Diag 记行（1s 节流合并落盘、info 行仅内存追加）；图片解码（新建篇无图、列表新行是空卡）。

## 二、定因（证据分级）

- **主因 A（proven 结构 / inferred 绝对量级）**：列表派生在点按同轮做**倍乘重复功**——`MemoGroup.images/texts` 是计算属性，body 每求值一轮就对全库重跑 4 趟（窄屏）图文分类探针，行/卡渲染再逐个重探。这笔账与库量线性相关、且精确地压在转场首帧前，是转场起步顿挫的来源之一。它不是新建独有（搜索输入、置顶切换同样中招），但新建路径与置位导航同轮发生，用户在此感知最强。
- **主因 B（inferred，机制与症状互证）**：初始落焦的**认领时机落在转场中段**——onAppear 置位 + 下一轮更新消费的状态往返，使 becomeFirstResponder 发生在 push 已进行约 1/3 时：键盘动画错过与转场同步编排的窗口，中途抢帧并引发编辑区二次布局，呈「中段卡顿」。新建独有（既有篇打开不落焦），与实报范围吻合。
- 两因叠加的感知 = 点按后先顿（A）→ 滑动中段再卡（B）→ 到达编辑页，与用户描述的「过渡期间卡顿后才到」一致。

**最小验证办法**（已随本次落码内置）：新增 CREATE timing 分段行（见四），真机新建一篇即读四段毫秒数——create 段验环 1、appear 段验 A 的消除效果、focus 段验 B 的认领点前移（认领回到安装帧后 focus 与 appear 同帧量级、且转场体感应平顺）。若后续数据推翻本定因，按数据再修。

## 三、根治落点（全部在源头，无转场/消费方补丁）

1. **组分区一次算清**（MemoGroup :13209）：`images`/`texts` 由计算属性改为**组装时单趟分区**的存量属性（init 内一次遍历、同谓词 `hasImageShape`、同清单、同序）。body 访问任意次都是 O(1) 读。行为等价：谓词、顺序、分组口径逐项不变；构造点 2 处签名不变。
2. **分类下传、行/卡不再重探**：`sublist`/`gridSublist` 把已知的 `kind` 以 `isImage: kind == "img"` 传给 `memoRow`/`squareCard`（组分区同一次判定的结果），删去行/卡内的 `hasImageShape` 重探。
3. **封面一次探针**：MemoItem 新增 `coverPair`（:11844），两个图文卡调用点（squareImageCard、memoRow 图文支）由 `coverFileId`+`coverURL` 两趟全树探针合为一趟。
4. **落焦认领点前移至视图安装帧**（BlockTextView.updateUIView :2225 起）：首个文本块的视图在自身首轮 updateUIView（push 起始的布局帧）直接凭 `wantsInitialFocus` 认领并清旗，删去 EditorView.onAppear 的 `focusBlockId` 状态往返（:8045 一带只留计时出现点）。落点口径不变：首个文本块、光标块首（focusCaretEnd 默认 false，与旧路径显式置 false 等价）。这是把认领放回平台能同步编排键盘与转场的位置，不是延时/预热类遮掩——没有任何定时器与帧数调整。

## 四、CREATE timing 行（新增量测）

- 打点链：`Library.create()` 两端记 `createTrace`（:906，按 id 存、EditorModel init 认领即清 :4721）；EditorModel 记 init 止；EditorView.onAppear 记出现点（`markCreateAppear` :4623）；初始落焦认领点收口（`logCreateFocusTiming` :4640）。纯读时钟，不改业务时序；普通打开零命中（guard 按 trace 在位）。
- 样例（字段为毫秒）：

```
CREATE appear id=m-xxxx create=3ms pre=41ms
CREATE timing id=m-xxxx create=3ms model=1ms appear=38ms focus=-1ms
```

- 读法：`create` = 建篇（落盘+入列）；`model` = create 返回 → EditorModel init 毕；`appear` = init 毕 → EditorView.onAppear（列表 body + push + 编辑首帧构建都在此段，A 的治理效果看此段回落）；`focus` = 出现 → 落焦认领（认领在安装帧、早于 onAppear 戳时记 -1，属预期形态）。

## 五、残余风险与后续

- A/B 的绝对量级均为 inferred：需 0.9.46 出包后真机以 CREATE timing 两行定案；若 appear 段仍大，下一嫌疑是 EditorView 首帧构建本身（menuPanel 常驻整树），届时按懒挂载口径另治，不在本批预支。
- `groups` 归组本身仍每轮 body 一趟 O(N)（日期分桶）——已是单趟、无倍乘，本批不动；若 timing 显示仍显著，再议按 memos 版本号缓存（结构性改动，另立项）。
- 落焦认领前移后，若首个文本块不在首屏（如宽屏双栏右栏深处），其视图安装帧略晚于左栏——仍在转场起始布局内（VStack 非懒构建、两栏同帧建），不构成中段认领；真机双栏形态需顺带一眼。
- 全文无文本块的文档 `wantsInitialFocus` 不会被清旗（新建篇恒有种子段、原子块结尾文档 init 已物化尾随段，实际不可达）；flag 残留只多一次短扫描/更新，无行为影响。
- 自验：大括号配平 3039/3039；verify_ios.sh 源码组全绿（仅 [5] ipa 陈旧、[9] 产物语言包两条已知产物红，构建后消除，非本次回归）。
