# 首页搜索胶囊点按无反应根治：字段常驻（2026-11-27）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。基线 HEAD fdb1a67（0.9.56）。
> 涉事批：`fix_home_search_layout.md` 线 A（搜索胶囊改 @FocusState 单一真相）。
> 领地：`ListView` 搜索段（`searchCapsule` + `activateSearch`）+ verify [30]（F30-1 改写、F30-10..12 追加）。本机 verify 自跑：**[30] 十二条全绿，全脚本 272 ✓**，仅剩 2 条既有产物类 ✗（ipa 陈旧、产物语言包，tree 构建自解），无其他组回退。Swift 编译级随主线 tree 冒烟（本机无 swiftc）。

---

## 一、定因（证据分级）

**结构根因 = proven（代码通读 + 同型 proven 先例 + 用户实报三方合拢）**：线 A 落码后的胶囊是自指涉结构——

- 分支条件即焦点本身：`searchCapsule` 为 `if searchFocused { 展开面（含 TextField）} else { 触发钮 }`，字段只存在于「已聚焦」分支里；
- 唯一的置焦请求是触发钮动作 `searchFocused = true`，在字段**尚不在层级**的同一事务里发出；
- 全仓再无第二条置焦路（无 `onAppear` 复请、无常驻字段；`searchFocused = true` 字面全仓恰一处）。

@FocusState 不是哑标志：它是向焦点引擎的请求，须有活目标承接。目标缺席时请求被吞、引擎把状态回滚到 false，分支随之塌回触发态——点按的净可见效果为零，与用户实报「点不了、没反应」逐项对应。触发钮被按下时的压感缩放（CardPressStyle）即便闪现，也无后续展开。

**同型先例 = proven（本 App 内、同一设备/OS）**：标题胶囊在 0.9.54 前正是同一结构（点按同事务置 `titleFocused=true` 并条件插入字段），真机定因「焦点请求被吞、FocusState 回滚」，根治为字段常驻（ZStack 常驻字段 + 覆盖层接点按），0.9.54/0.9.55 真机验证通过。线 A 等于把刚被定罪并拆除的反模式又装回了搜索胶囊——区别只在标题那例另有 onChange 写 @Published 的整树重演算助燃，本例没有，但自指涉本身已足够致病：展开的存在以持焦为前提，持焦的获得又以展开（字段在场）为前提。

**微观时序 = inferred**：请求究竟是「校验即回滚」还是「插入时在动画事务内被作废」，本机无设备插桩不可分型；但所有微观变体共享同一必要条件——置焦时目标缺席——根治拆除该条件后各变体同时失效，不依赖分型结论。

**旧版为何可点 = proven（git 对照）**：线 A 之前触发钮写的是哑 @Published 标志 `nav.searchOpen`，无校验、无回滚，面板必展开（代价是与焦点脱钩、回车不回缩，即线 A 要治的原病）。线 A 的「焦点单源派生」方向本身正确，错在把置焦与条件插入绑成同一步。

## 二、命中链逐环证据（点按为何不是「没点到」）

| 环 | 证据 | 结论 |
|---|---|---|
| 触发钮存在且形态与旧版同 | 收起分支为真 Button + CardPressStyle（纯 scaleEffect，无手势）；面材 glassControl 与可点旧版逐字同 | 非钮本身问题 |
| 层级与覆盖 | 页眉在 ListView 的 ZStack 顶层（List 之后、仅 undoToast 条件覆盖）；`.overlay` 量测层 allowsHitTesting(false)；DragPressAnchor/UITestAnchor 只挂编辑器行与编辑页，首页页眉区无锚点覆盖 | 无透明层抢命中 |
| 命中开关 | 胶囊 `.allowsHitTesting(compactP < 0.5)`，静止位 compactP=0 → 可命中、opacity 1；同页眉的头像钮（同开关）用户未报死 | 命中门开 |
| 动作体 | 触发钮唯一动作 `searchFocused = true`——哑写改为引擎请求后，断点在此一环的下游（置焦成立性），不在到达 | 点到达、断在置焦 |

即：点按到达并执行，死在「请求无活目标」。本次补的 tap 到达行（见 §四）使下一轮同类问题可在桥侧直接分段判读，不必再靠代码考古推断到达性。

## 三、根治（字段常驻，与标题胶囊同型）

`searchCapsule` 改为 ZStack 两层，胶囊视图身份恒定、字段永不跨分支：

- **常驻层（展开面）**：图标 + TextField + 清除钮的 HStack，恒在层级；`.overlayCard(radius: Radius.pill)` 面与旧展开面逐字同；`.opacity(searchFocused ? 1 : 0)` + `.allowsHitTesting(searchFocused)`——收起态不可见不可命中，展开态才可命中；字段宽由焦点派生 `.frame(width: searchFocused ? 140 : 0, height: 40)`（收起时字段以 0 宽在场——第一响应者资格不依赖帧尺寸、只依赖在窗在层级且未隐藏，与标题常驻字段 opacity 0 在同设备已 proven 的口径一致）；字段补 `.accessibilityHidden(!searchFocused)` 防无障碍读到隐形字段。
- **触发层（收起面）**：`if !searchFocused` 的真 Button（原触发钮整块平移：glassControl 面、CardPressStyle、transition 全保留），动作改走具名入口 `activateSearch()`。字段不在此分支内——这是与病灶的本质区别：条件分支里只剩可丢弃的触发面。
- 间距守恒：常驻层 HStack spacing 改 0 + 图标尾距 8 / 清除钮首距 8 显式补回，与旧展开面 gap 8 逐项等值；容器横 padding 14、 高 66 不变；页眉侧 `.animation(value: searchFocused)` 不动，展开/收起仍是 M5 交叉淡入 + 宽动画（字段宽动画即展开动画的一部分）。
- 线 A 的其余成果全保留：展开 ⟺ 持焦的单源派生、onSubmit/clear/nav/system 四路辞焦与来源记账、双形态 scrollDismissesKeyboard、query 保留口径——一行未动。

## 四、Diag 合同（增量，不改名）

新增一行：`APP search capsule tap`（`activateSearch()` 入口首行记，到达即记、在置焦之前）。

与既有两行构成三段定位：**无 tap** = 命中未达（查命中链）；**有 tap 无 open** = 置焦未立（查焦点链）；**有 open 无 close** = 辞焦链断（查 src 路径）。

**合同稳定性**：既有 `APP search capsule open` / `APP search capsule close src=<submit|clear|nav|system>` 的格式与 src 枚举**一字未改**，新行纯增量——U5 的 home_search_cycle 景按既有口径判读不受影响，无 delta 需同步。

## 五、为什么 [30] 全绿却真机没反应——断言补法

线 A 的 [30] 锁的是**源码文本在位**：F30-1 锁 `@FocusState` 声明 + `if searchFocused {` 字面 + 旧标志零残留；F30-2/3 锁 `.focused` 绑定与辞焦路径字面。这些断言全数属实、且全数与故障相容——最刺眼的是 F30-1：它把病灶结构本身（分支条件即焦点）当作正确性证据锁了进去。断言锁文本 ≠ 链路成立，此为同型复发（标题批 [24]、圆角批均有前科），本批把 [30] 补到机制层：

- **F30-1 改写**：保留单源派生 + 旧标志零残留两锁；把 `if searchFocused {` 的「存在」锁反转为「零出现」锁，并加 TextField 恰一处。改写理由随注记写入脚本（原锁结构即病灶）。
- **F30-10（新）字段常驻机制**：字段宽派生字面（140/0）、常驻层命中与焦点同源、置焦字面全仓恰一处（第二处直接置焦即红——防绕开具名入口与常驻前提）。
- **F30-11（新）点按具名入口**：`activateSearch` 函数体内 tap 行与置焦同在（到达与置焦同闭包）；触发层 Button 动作即此入口、CardPressStyle 在位。
- **F30-12（新）层级顺序锁**：CAP30 内 TextField 行号必须在触发分支 `if !searchFocused {` 之前（字段居常驻层）——字面锁之外的结构锁，防字段日后被挪进任一焦点键控分支而常驻前提静默破。
- F30-2..9 不动（F30-9 的面板 overlay 档锁因常驻层逐字保留 `.overlayCard(radius: Radius.pill)` 继续成立；其 CompactTitle 条款含圆角批在途改字，未触碰）。

本机自跑：[30] 十二条全绿；全脚本 272 ✓（含并行批在途新增），✗ 仅 ipa 陈旧 + 产物语言包 2 条既有产物类。

## 六、同型排查（首页及全仓焦点/手势面）

| 面 | 形态 | 判定 |
|---|---|---|
| 头像钮 / 紧凑标题钮（首页页眉） | 真 Button 写哑状态（nav.dest），目标页不由该值条件插入 | 非同型 ✓ |
| 搜索胶囊（本批） | 分支条件即焦点 + 同事务置焦 | **同型，已根治** |
| 编辑器标题胶囊 | 0.9.54 已改字段常驻 + B-4 representable 执行器 | 已治 ✓ |
| 编辑器链接字段（linkFieldFocused） | 存储标志插面板 + 字段 `.onAppear` 置焦（插入后复请）——全仓正例 | 非同型 ✓ |
| 音乐卡链接字段（fieldFocus）/ 天气设置字段（focusedField） | 字段随其表单常驻、入口为用户直点字段本身，无程序化同事务置焦 | 非同型 ✓ |

结论：全仓「分支条件 == 焦点值 + 同事务程序化置焦」仅此一处，已清零。

## 七、领地与在途批完整性

动工前快照全树 diff 并逐 hunk 映射：搜索段不在任何在途 hunk 内（圆角/布防/U4a 的改动分布在桥文件、EditorView、ListView 布局行与 verify [31] 等处）。落码期间在途批仍在并发落码（文件行号中途偏移 +53，已复核偏移源为他人段落增行、搜索段内容未被触碰）。完工复验：其余 7 个在途文件的 diff 与开工快照逐字节一致；MomentApp/verify 内他人 hunk 内容全数存续（verify 快照行零丢失；MomentApp 仅 moreCapsule 段 1 行计数差，经核该行在当前 diff 中仍在、属其批次自身在途调整、非本批领地）。本批 hunk 仅：MomentApp 的 activateSearch 新增段 + searchCapsule 整块、verify [30] 的 F30-1 段 + F30-9 后追加段。

## 八、真机终判点

1. 静止位点搜索胶囊 → 键盘升起、胶囊展开为搜索面板（无闪烁回落）；桥 diag_tail 应见 `APP search capsule tap` → `APP search capsule open` 两行成对、时序相邻。
2. 输词点回车 → 键盘收、胶囊回缩成触发钮、列表仍按词过滤；Diag 见 `close src=submit`（线 A 判读点不变）。
3. 点 × 清除 → 词清、胶囊收；Diag 见 `close src=clear`。
4. 展开态上滑列表 → 键盘交互收起、胶囊回缩；Diag 见 `close src=system`。
5. 展开态点开一篇备忘 → 进编辑器；返回首页胶囊为触发态、词保留；Diag 见 `close src=nav`。
6. 宽屏（网格）形态重复第 1 项（两形态共用同一胶囊实现，终判抽验一形态即可，另一形态以代码同源为据）。
7. 若第 1 项仍不成：按 tap/open 两行的有无直接分段（无 tap 查命中、有 tap 无 open 查焦点），Diag 证据回传主线，不再靠体感描述。
