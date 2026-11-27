# 新建笔记过渡卡顿：第二轮全面排查（事件机制层）

用户实报：0.9.46（已含第一轮两处根治：列表 MemoGroup 分类单趟化、落焦认领前移到文本块安装帧）真机卡顿依旧。本轮按「前结论不完整」处理，排查范围放大到焦点状态机、键盘监听、光标/选区、编辑页首帧构建全账、转场机制本身五面，逐项通读现行源码（`rust/apps/ios/app/MomentApp.swift`，16473 行；行号为本轮排查时现值）。**本轮只排查，不落码。**

前轮报告：`docs/reports/fix_new_note_transition.md`。本轮对其两处定因的复核结论：A（列表分类倍乘探针）已被根治且复核属实（`MemoGroup` 分区确为组装时单趟，:13228–13252）；B（认领时机）落码属实（认领确在 `BlockTextView.updateUIView` 首轮，:2225–2281）。但卡顿依旧，说明剩余主因不在那两处——本轮在事件机制层找到三处此前未入账的机制（见嫌疑表 S1–S3），其中 S1 是结构 proven、只差真机分段数据坐实量级与时点。

## 一、全链时序账（事件级，点按 → 键盘落定）

入口四处形态一致（gridEmpty :13793、新建卡 :13833、窄屏新建行 :14115、宽屏新建卡 :14417），同一主线程回合内同步完成：

| # | 事件 | 主线程工作 | 证据 |
|---|---|---|---|
| T0 | 点按 → `Library.create()`（:922） | 构造 MemoItem + `persist()` 同步 FFI upsert（单行事务）+ `memos.insert(at: 0)`（@Published 写）+ CREATE trace 存痕（:938） | proven（代码；量级同前轮，1–5ms 级） |
| T1 | `EditorModel(item:library:)` init（:4683） | 标题/块直取、双栏决议、`materializeMdTrails()`（空篇 O(1)）、CREATE trace 认领（:4730 一带） | proven |
| T2 | `ed.wantsInitialFocus = true` → `nav.dest = .editor(ed)`（NavState @Published，:13174） | 同回合内 Library 与 NavState 两次发布。SwiftUI 在下一更新周期合并处理：**ListView body 演算一趟**（`groups` 全量重算，见 S1）+ List 差分插入新行 + NavigationStack 启动 push、构建目标页 | proven（机制） |
| T3 | 目标页首帧构建（push 起始帧） | EditorView body 第 1 轮：contentArea（ScrollView + VStack + 1 个 BlockRow + scrollProbe + focusHotZone + backlinksSection 空）、EditorHeaderView（capsuleWidth 两次 NSString 量宽 + wordCount）、menuPanel 常驻整树（隐藏态仍构建，见 S3）、6 处 sheet/dialog 脚手架、toolbar。BlockTextView.makeUIView 建 UITextView + inputAccessoryView 工具栏（sizeToFit） | proven（构成）；单轮毫秒 inferred |
| T4 | 页眉量宽回写（首帧布局内） | EditorHeaderView 背景 GeometryReader onAppear 写 `ui.headerW`（EditorUI @Published）→ **EditorView body 第 2 轮**；同轮 contentArea 的 VStack minHeight 才从 0（ui.viewH 首轮为 0）跳到 viewH−208——内容几何在转场起始帧内发生一次跳变（布局级，非 body 级） | proven（代码） |
| T5 | EditorView.onAppear（:7924，push 起始、转场进行中触发） | 两行 Diag（内存追加，便宜）+ `ui.titleDraft = editor.title`（@Published 写）+ `ui.backlinks = library.backlinks(...)`（@Published 写；新篇空标题在 `wikiKey` 处早退 O(1)，:1517）+ `markCreateAppear()` → **EditorView body 第 3 轮**（两次写大概率合并为一轮） | proven |
| T6 | 落焦认领（BlockTextView.updateUIView 首轮，与 T3 同属首帧布局） | `initialClaim` 判定（每块每轮 updateUIView 都算一次 `blocks.first(where: isText)`）→ 清 `wantsInitialFocus` → `tv.becomeFirstResponder()`（:2243，**返回值被丢弃**）→ 同步设 `selectedRange` → `logCreateFocusTiming()`。键盘动画自此启动，与 push 动画（~0.35s）几乎全程重叠 | proven（代码）；认领与 onAppear 的先后随 SwiftUI 调度而定（见六） |
| T7 | 头像加载（转场窗内，时点二选一） | 新篇头像必未缓存：列表新行 AvatarView.onAppear 或编辑页页眉 AvatarView.onAppear（先到者）→ `AvatarHolder.refresh`（:12759）→ `Library.loadAvatar`（:1545）**主线程同步 FFI `avatarData` 查询** + 写 `avatarCache`（Library @Published，:1537）→ **ListView body 再演算一趟（`groups` 全量重算）+ 根 ZStack 演算**，落在 push 进行中 | proven（机制）；时点与量级 inferred |
| T8 | 键盘开始呈现 → `textViewDidBeginEditing`（:2313） | `editor.editingBlockId = block.id`（EditorModel @Published）+ `pushHistory()`（:4955）：snapshot = 全块 `flushedNode()` 映射（空篇 1 块、微秒级）+ `syncHistoryFlags` 写 `canUndo`（@Published，false→true）→ **EditorView body 第 4 轮**（含 menuPanel 等整树重构）+ BlockRow 重演算。发生在键盘升起初期、转场中段 | proven（机制）；单轮成本 inferred |
| T9 | 键盘动画全程（~0.3s，与 push 后半重叠） | 无应用级键盘监听（见二·2）。框架侧：编辑页未对键盘安全区免疫（无 `.ignoresSafeArea(.keyboard)`），宿主视图安全区随键盘动画连续变化 → 编辑区 ScrollView 框高连续重排；scrollProbe 的 onGeometryChange 持续回报（updateScrollY :9258，守卫后只写独立 scrollState，页眉子树重演算——设计内隔离）；BlockRow 背景 GeometryReader 的 4 个 onChange 随行框变化逐帧触发（只写非 Published 量测值，便宜） | proven（机制）；感知贡献 inferred |
| T10 | 块高回写（首帧后异步一拍） | BlockTextView.sizeThatFits（:2168）：首轮签名未命中 → TextKit 全量布局（空篇 trivial）→ 若量得高与默认 24 差 >0.5，`DispatchQueue.main.async` 写 `block.height`（BlockState @Published）→ BlockRow 一轮重演算 + updateUIView 复跑（守卫便宜） | proven |

**一句话账**：转场窗（约 0.35s）内主线程共发生——ListView 全量演算 **2 趟**（T2、T7，其中 T7 那趟纯属头像缓存发布捎带）、EditorView 全量 body **约 4 轮**（T3、T4、T5、T8）、编辑区随键盘安全区的连续重排（T9）。前轮只治理了 T2 趟内的倍乘系数（4 趟探针 → 1 趟）与 T6 的认领位置，未触及「趟数」本身与 T7/T8 两趟的触发源。

## 二、逐面排查结论

### 1. 焦点状态机

- 状态点：`EditorModel.focusBlockId`（@Published，:4503）全文件约 40 处写点，均为编辑期导航/拆并块/菜单路径；新建路径不经它（走 `wantsInitialFocus` 普通 var，:4614，非发布——写它不触发任何演算，口径正确）。
- 认领链（T6）：`updateUIView` 内 `initialClaim` = `wantsInitialFocus && 本块 == blocks.first(isText)`。每块每轮 updateUIView 都重算一次 `first(where:)`（O(块数)，新建篇 1 块可忽略；长文档每轮全块 × O(N) 是编辑期既有成本，不在本症状内）。
- **认领无成功校验、无重试（proven）**：`wantsInitialFocus` 在认领尝试**之前**即被清旗（:2238），`becomeFirstResponder()` 返回值被丢弃（:2243）。若首轮 updateUIView 时视图尚未入窗（SwiftUI 预构建目标页的调度差异可致），认领静默丢失且永不重试——失败形态应为「打开新篇无键盘」，与本轮症状（有键盘、只是卡）不符，**判为脆弱点而非本症主因**（inferred）；但 CREATE 打点必须能区分它（见六·建议 5）。
- 无认领失败重试、无焦点往返：认领后 `focusBlockId` 恒为 nil（初始路径从不写它，:2259 的异步清旗在初始路径是空转）；`editingBlockId` 在 T8 写一次后稳定；标题 TextField 的 `@FocusState titleFocused` 与块落焦无互抢（标题聚焦只由点按胶囊触发）。焦点二次改写路径：**不存在**（proven，写点全查）。
- 另一处 `becomeFirstResponder` 在 :5665（跨块方向键导航直达目标视图），与首帧无关。

### 2. 键盘监听面

- **应用级键盘监听为零（proven）**：全部 5 个 Swift 文件（MomentApp/MomentDrag/MomentLaunch/MomentOps/MomentRescue）grep `keyboardWill*/Did*` 通知订阅 **零命中**；无 willShow/didShow/willChangeFrame/didChangeFrame/willHide 任一观察者。因此不存在「每次键盘帧变化触发全量重排」的应用级代码——键盘帧变化的应用侧成本为零。
- 实际键盘耦合面只有四处：① 框架安全区动画（T9，宿主视图层，非 body 重演算）；② 编辑 ScrollView 的 `.scrollDismissesKeyboard(.interactively)`（:9244，手势口径，无首帧成本）；③ 每块 UITextView 在 makeUIView 时建的 inputAccessoryView 工具栏（:2114–2129，建于 T3，1 块 1 件，sizeToFit 一次性小成本）；④ EditorView 的 `.toolbar(placement: .keyboard)`「完成」组（:7905，服务 SwiftUI 响应者即标题 TextField；块编辑时由 ③ 接管）。另 EditorView 背景 GeometryReader 订阅 `safeAreaInsets.bottom` 变化写 `ui.safeBottom`（普通 var，无发布，:7900 一带）——键盘升降各触发一次写值，不引发 body。
- 结论：键盘侧没有可治理的「监听过重」；键盘的角色是**动画编排者**——它与 push 全程重叠（T6 起动），并经安全区让编辑区在动画期连续重排（T9）。若真机分段数据最终指向这一段，治理方向是呈现结构（内容层对键盘安全区免疫、底距内部吸收），不是删监听。

### 3. 光标 / 选区面

- `textViewDidChangeSelection` **未实现**（全文件零命中，proven）：选区变化无应用侧处理，落焦设选区不产生 delegate 级连锁。
- 认领路径**无光标几何量测**（proven）：`caretRect` 全部调用点只在跨块方向键导航（:5587、:5675–5728）；全文件无 `scrollRectToVisible`/`scrollToCaret`。认领只同步设一次 `selectedRange`（:2263），UITextView 内部选区呈现为框架成本。
- `textViewDidChange`（:2452）只由用户编辑触发（程序化设 text/selectedRange/becomeFirstResponder 均不触发），首帧窗内不跑。其单次成本（全块 `Marks.runs` 重转 + `updateSlash`）是编辑期成本，不在本症状内。
- `shouldChangeTextIn`（:2325）的 before/after 全文切分只在真实键入时跑，不在窗内。
- 结论：光标/选区面**清白**（proven），前轮与本轮均无嫌疑。

### 4. 编辑页首帧构建全账（新建空篇口径）

EditorView body 单轮构成（:7805 起）与成本分级：

| 构成 | 内容 | 量级 |
|---|---|---|
| contentArea（:9220） | ScrollView + VStack{scrollProbe、1 × BlockRow、focusHotZone、backlinksSection（空→不出）} + minHeight 帧 | 主项在 BlockRow：HStack + BlockTextView（UIViewRepresentable）+ 背景 GeometryReader（4 个 onChange 订阅）+ DragPressAnchor 背景 + 缩放/偏移修饰链 |
| EditorHeaderView（:8642） | 两钮 + 头像（AvatarView，onAppear 触发 T7 的一端）+ 标题胶囊：`capsuleWidth`（:8845）每轮 body 做标题与 meta 两次 NSString 量宽 + `wordCount`（:5001，O(文本块)） | 量宽 µs 级（空标题）；头像见 T7 |
| menuPanel（:8979） | **常驻整树**：ZStack + 全屏 Color.clear 点按层 + ScrollView + VStack{5 × menuItem}（撤销/重做/附件/导出/背景色；宽屏另加 twoPaneRow），隐藏靠 opacity 0 + 禁命中 | 值构建约百个视图节点量级；**每轮 EditorView body 都重构**（它是 body 内联计算属性，无独立观察边界） |
| 条件层 | slashLayer / cardMenuLayer / blockMenuLayer 均以对应 @Published 为 nil 门控，首帧不出；bgSheet 以 showBgSheet 门控不出 | ≈0 |
| 呈现脚手架 | 6 处 sheet/confirmationDialog/alert + imageTarget 的 navigationDestination（:7939）+ keyboard toolbar 组 | 每轮参与 body 图构建，常量级 |
| 背景 GeometryReader | onAppear/onChange 写 ui.viewW/viewH（普通 var）与 ui.wide（变化才写） | 写值便宜；其 onAppear 是 T4 第二轮的同谋（与 headerW 写同周期） |

EditorView 观察面：`@ObservedObject editor`（EditorModel 约 21 个 @Published）+ `@StateObject ui`（EditorUI，含 headerW/titleDraft/backlinks/wide 等 @Published）。**任一发布都整页 body 重演算**——首帧窗内确定的发布源有四个（T4 headerW、T5 titleDraft/backlinks、T8 editingBlockId/canUndo），对应约 4 轮全量 body（见时序账）。单轮绝对成本 inferred（值构建为主，估 0.3–2ms/轮），单独不足以成可见卡顿，但与 S1 的列表趟叠加在同一 0.35s 窗内时共同吃帧。

### 5. 转场机制本身

- 机制：NavigationStack + `navigationDestination(isPresented:)`（:13410），系统 push（~0.35s），无自研转场。目标页在 push 起始即构建并保留在层级内；源页 ListView 在转场全程**存活且保持观察**（`@ObservedObject library`，:13149；Library 共 13 个 @Published，任一写都通知 ListView 与根 ZStack）。
- 源页每趟 body 的固定成本 = `groups`（:13254）全量重算：`visibleMemos` 双 filter + 每篇 `bucketDate`（→ `Clock.parseISO`，:31——**每次调用新建一个 ISO8601DateFormatter 并解析**，formatter 构造是已知贵操作）+ 每篇 Calendar `dateComponents` 日差 + 每组 MemoGroup 组装（含每篇 `hasImageShape` 块扫描，:12623；文本篇落 `hasCover` 对 raw doc 的递归全树字典探针，:11939）。前轮根治把「每趟 4 次探针」降为 1 次，但**每趟的基数仍是全库一趟**，且趟数由发布次数决定（窗内 2 趟：T2、T7）。
- 目标页侧的发布源与轮次见二·4。两页的演算都跑在主线程、都落在转场动画的帧预算内——这是「过渡期间卡顿」的结构温床：转场本身没有给首帧工作留出任何隔离，任何一趟几 ms 以上的同步演算都直接掉帧。
- List 插入新行（T2 同周期）：新篇入「今天」组首行，List 做一次差分插入 + 可见行布局；行体本身已由前轮改为 kind 下传 + coverPair 单探针，便宜。非主项。

### 6. CREATE 计时复盘（现行两行能切分什么、不能切分什么）

现行打点：create 两端（Library，:906–919）→ EditorModel init 认领（traceInitEnd）；`markCreateAppear`（:4638，EditorView.onAppear 调用）出 `CREATE appear … create=… pre=…`；认领点 `logCreateFocusTiming`（:4658）出 `CREATE timing … create/model/appear/focus`。

- **能切分的**：create 段（T0）干净；pre 段 = createEnd → onAppear，混合了 EditorModel init 尾段、dest 置位、ListView T2 趟、目标页构建与首帧布局——只能看总量，无法归因到列表趟/编辑趟/哪一轮 body。
- **不能切分的（本症关键段全在盲区）**：onAppear 之后的一切——T7 头像趟、T8 begin-editing 趟、键盘动画段、转场落定——没有任何时刻点。用户感知的「中段卡顿」恰在 onAppear 之后，现行两行对它零分辨。
- **focus 段语义缺陷（proven，代码）**：`logCreateFocusTiming` 在认领点（T6）被调用，此时 `traceAppear` 可能尚未被 `markCreateAppear` 写入（认领与 onAppear 的先后取决于 SwiftUI 调度）。`ms(traceAppear, now)` 在 traceAppear == 0 时因 `b > a` 成立而返回 `Int(now × 1000)` 量级的**巨值**，而非前轮报告所称的 −1；若 onAppear 先行，则 focus 段只是 appear→认领的小差、且认领成功与否（becomeFirstResponder 返回值）无从分辨。**现行 focus 段不可作判据使用。**
- 结论：现行 CREATE 两行不足以定案本轮任何嫌疑；须按第七节一次补齐分段点，下一轮真机导出即可按段定案。

## 三、嫌疑表

| # | 机制 | 成本量级 | 证据等级 | 与症状吻合度 |
|---|---|---|---|---|
| S1 | `groups` 全量重算被**头像缓存发布**在转场中段二次触发（T7）：loadAvatar 主线程同步 FFI + 写 Library.avatarCache → ListView 整趟重算（每篇 parseISO 新建 formatter + dateComponents + hasImageShape/hasCover 全树探针）。点击轮首趟（T2）同账、推迟转场起步 | 单趟 inferred 数 ms–数十 ms（随库量与篇幅线性，N≈100 时估 5–30ms）；趟数与触发链 proven | 结构/机制 proven；量级与确切落点 inferred | **高**：中段一趟同步长尾正对应「滑到一半卡一下」；且与库量相关——库越大越明显，可由用户库量级旁证 |
| S2 | EditorView 首帧约 4 轮全量 body（T3/T4/T5/T8 发布源驱动），每轮含 menuPanel 常驻整树 + 头部量宽 + 全部呈现脚手架 | 单轮 inferred 0.3–2ms，合计约 1–8ms 分散在窗内 | 发布点与轮次 proven；单轮成本 inferred | 中：单独或不足以成可见卡顿，与 S1 叠加吃帧；T8 那轮落在键盘升起初期（转场中段），时点吻合 |
| S3 | 落焦认领与键盘动画的编排：认领在安装帧（转场第 0 帧）启动键盘，键盘动画与 push 几乎全程重叠；编辑区未对键盘安全区免疫，ScrollView 框高随键盘动画连续重排（T9） | 无单点耗时；为动画期连续布局 | 机制 proven（无 ignoresSafeArea、认领点位）；感知贡献 inferred | 中：可解释「全程不顺」而非单点卡；若 S1/S2 被数据排除则升为主因 |
| S4 | 认领单次尝试、无成功校验、旗先清（T6） | — | 代码 proven | 低：失败形态是无键盘而非卡顿；列为脆弱点待打点排除 |
| S5 | VStack minHeight 首帧 0 → viewH−208 的几何跳变（T4） | 一次布局 | proven（代码） | 低：跳变的是透明热区高度，块位不动，视觉上近乎不可见 |
| — | 已排除：键盘监听（为零）、选区 delegate（未实现）、认领路径光标量测（无）、textViewDidChange（窗内不触发）、Diag 记行（内存追加+节流落盘）、FFI 建篇（单行事务）、backlinks（空标题早退）、wordCount/量宽（空篇 µs 级）、scrollProbe 发布（隔离至页眉子树） | — | proven | — |

## 四、主因判定

- **主因（结构 proven、归因 inferred）**：S1——转场窗内的主线程长尾不在编辑页，而在**源页 `groups` 的全量重算被触发了两趟**：点击趟（与建篇/置位同周期，推迟起步）与头像趟（`loadAvatar` 的同步 FFI + `avatarCache` 发布在转场中段引爆第二趟）。前轮把每趟的探针系数从 4 降到 1，但每趟基数（全库 ×（ISO 解析 + 日历差 + 封面探针））未动、趟数未动——这是「修了仍卡」的最合理解释，且其量级随库量增长，与「新建独有感知最强」（只有新建同时触发建篇发布 + 新行/新头像加载 + 落焦键盘）自洽。
- **共犯（proven 机制、量级 inferred）**：S2 的编辑页多轮 body 与 S3 的键盘/安全区编排，二者在同一窗内叠加吃帧。
- **还差哪份真机数据才能定案**：现行 CREATE 两行切分不到 onAppear 之后（见二·6），S1 的第二趟是否真落在转场中段、单趟多少 ms，S2 每轮多少 ms，目前都无端内证据。按下节补齐打点后，真机新建一篇的导出即可逐段定案——在此之前主因判定维持「结构 proven、归因 inferred」，不冒充 proven。

## 五、根治方向（落源头，不在转场消费方打补丁）

1. **归组结果离开 body 计算**（治 S1 的趟基数）：`groups` 改为按 `memos` 版本缓存——memos 未变时 body 直接读上次组装结果；或更彻底：归组+分区在 Library 侧随 memos 变更增量维护，ListView 只读。视图层每轮重算全库派生数据本身就是源头问题，缓存/下沉二选一，勿在转场处做延时或预热遮掩。
2. **日期解析离开热路径**（治 S1 的单价）：`Clock.parseISO` 改共享静态 formatter（或 ISO8601 解析结果在 MemoItem 构造时一次算清缓存 `bucketDate`/Date 字段，值对象层解决），禁止每篇每趟新建 formatter。
3. **头像加载离开首帧同步路径**（治 S1 的触发源）：`loadAvatar` 的 FFI 读 + 缓存发布改异步（后台读、主线程回写），或至少不让编辑页页眉与列表新行在转场窗内同步做未缓存头像的首读。此为数据加载口径问题，在 Library/AvatarHolder 层治，不在导航处绕。
4. **EditorView 首帧发布收敛**（治 S2）：`titleDraft`/`backlinks` 的初值改由 EditorUI 初始化时种子化（不在 onAppear 后逐个发布）；`headerW` 量测回写改走非发布通道或独立观察对象由页眉自消费（与 scrollState 的隔离口径同理：量测发布只失效消费它的子树，不整页）。
5. **认领补成功校验**（治 S4 脆弱点）：`becomeFirstResponder` 返回值入账；失败时不清旗、待下一轮 updateUIView 有界重试。落点口径不变。
6. **键盘编排（S3）暂不动结构**：待分段数据定案后再议；若坐实，方向是编辑内容层对键盘安全区免疫（框高不随键盘动画变、底距由内容内部吸收），属呈现结构调整，须另行对 Web 口径评估，不预支。

## 六、建议新增分段打点（CREATE 家族扩展，落码批一次补齐）

全部为 CFAbsoluteTime 读时钟 + DiagLog 一行，guard `traceCreateStart > 0` 才记，不改任何业务时序：

1. **`CREATE dest`**：四入口收敛处（或各入口）在 `nav.dest` 置位后记一行（dest 置位时刻）——把现行 pre 段切成「点按处理（create+init）」与「置位→出现（系统侧构建）」两段。
2. **`CREATE listpass n=<趟序> ms=<耗时>`**：`groups` 计算起止自记（仅 trace 在位时）——直接量 S1 每趟成本与窗内趟数，定案/排除 S1 的第一证据。
3. **`CREATE avatar ms=<耗时>`**：`loadAvatar` 未命中缓存、实际走 FFI 的分支记时刻与耗时——判定 T7 是否落在转场窗内及其单价。
4. **`CREATE bodypass n=<轮序>`**：EditorView body 入口计数（trace 在位时每轮记一行或在 settle 行汇总轮数）——量 S2 的轮次（单轮成本由 settle 总账反推）。
5. **`CREATE claim ok=<0/1> inwindow=<0/1>`**：认领点记 `becomeFirstResponder()` 返回值与 `tv.window != nil`——区分「一次成功」「静默丢失」（S4）。
6. **`CREATE kb`**：借现成位点——EditorView 背景 GeometryReader 的 `safeAreaInsets.bottom` 首次由 0 变非零的 onChange 时刻记一行，近似键盘落定——切分 T9 的键盘重叠段。
7. **`CREATE settle`**：onAppear 后 0.5s 一次性汇总行：create/model/dest/listpass（趟数与总 ms）/bodypass（轮数）/claim/kb 各段总账，一行定案；同时**修复现行 focus 段缺陷**：traceAppear 未记时输出 `focus=na` 而非巨值，claim 段改以 claim 时刻 − dest 时刻计（语义明确）。

补齐后下一轮真机只需新建一篇并导出 Diag：S1 看 listpass 第二趟的时点与 ms，S2 看 bodypass 轮数与 settle 总账，S3 看 kb 与转场段的重叠，S4 看 claim ok 位——四嫌疑同篇数据内全部分辨。

## 七、本轮未改动声明

本轮未修改任何源码；行号与结论均对现行工作树（含 0.9.46 已落两处根治与 0.9.47 拖拽第二轮的 BlockRow 形态）核读。编辑器滚动卡顿、长文档打开路径不在本轮范围（本轮口径为新建空篇；S1 的 groups 账对打开既有篇同样存在列表侧成本，但不在用户本轮实报内，未展开）。
