# 完成胶囊不回缩根治报告（0.9.56 真机回归三）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。基线 HEAD fdb1a67（0.9.56）+ 在途三批（圆角/布防/U4a）工作树之上，领地零交叠（见 §6）。
> 症状（用户实报）：编辑页点完成钮后键盘收了，但打勾图标没有自动回缩消失，竖向胶囊停在展开态。

---

## 1. 定因（证据分级）

**根因（proven，代码与口径双证）**：完成胶囊的触发位 `EditorUI.kbVisible` 由一条**量测派生**喂入——EditorView 背景 GeometryReader 的 `onChange(of: geo.safeAreaInsets.bottom)` 写 `kbVisible = sb > 0`。而 `sb`（safeBottom）按其自身定案是**含设备安全区的量**（声明注释明言「按 Web 口径含 safe」；消费方全是「基距 + 安全区」口径：背景底表 `20 + ui.safeBottom`、各浮层 `geo.safeAreaInsets.bottom + 14`）。Face ID 机型上其**静息值 = 主屏指示条高 34，而非 0**：

- 键盘升起：sb 由 34 跳至键盘高（≈330+），`> 0` 成立 → kbVisible = true，胶囊展开 ✓（与用户所见一致）。
- 键盘落下（**任意路径**：点完成辞焦、滑动收起、失焦、字段转移后落下）：sb 只回落到 34，`34 > 0` 恒真 → **kbVisible 永不回 false**，自首次升起即闩锁。
- `doneExpanded = kbVisible ∧ 六抑制全空`：抑制格只能强制收、不能钉住展开；上游不翻，派生无从翻，胶囊永停展开态。

即：**喂入量（安全区）与被测事实（键盘可见性）不是同一个量，阈值 0 与静息值 34 结构性错位**——升沿能跨阈、降沿永不跨回。完成钮路径不特殊，它只是用户验回缩契约的点；其余各收起路径同病（胶囊自首次键盘升起后实际从不回缩）。

**分级注记**：静息值 34 的具体数字为 inferred-strong（Face ID 机型指示条标准值；本仓多处已真机定案的悬浮面以 `safeAreaInsets.bottom + 14` 为「浮在指示条上方」口径，与之自洽）；闩锁机理本身不依赖该数字的精确值——只要静息值 > 0 即成立，而静息非零是 safeBottom 的设计前提（proven）。

## 2. 四段链逐段证据

| 段 | 判读 | 证据 |
|---|---|---|
| ① 键盘事实 | ✓ 无病 | `finishEditing()` 的 `sendAction(resignFirstResponder, to: nil)` 沿响应链可达全部第一响应者：块 UITextView（didEndEditing 清 editingBlockId）、标题 UITextField（didEndEditing 无条件回写 focused=false）。块焦点是 `focusBlockId` 一次性消费（认领后异步清），无辞焦后重抢；用户目击键盘收起与此链自洽——不存在「换了宿主假收」（若真换宿主，键盘不会落下）。 |
| ② 状态位 | ✗ **断点** | kbVisible 全仓唯一写点即上述 onChange（grep 实证：声明 1、旧写 1、读 1）；写值 `sb > 0` 对静息 34 恒真，落下边沿无任何其他写点能清它。 |
| ③ 派生 | ✓ 无病（被上游钉死） | `doneExpanded` 公式逐项核：六抑制输入全为「在位即抑制」的负向格，只能把展开压成收起；kbVisible 为真时其余格皆空即展开——公式忠实于输入。 |
| ④ 呈现 | ✓ 无病 | EditorHeaderView 以 `@ObservedObject` 观察 ui；moreCapsule 帧高 46↔92、勾 opacity、两段 animation 全挂 `expanded`；`.onChange(of: expanded)` 的 Diag 行（expand/collapse）与派生同源——派生不翻，呈现无独立断裂点。 |

## 3. 同型排查（共用喂入点的其他消费方总判）

- `kbVisible` 的消费方**只有完成胶囊一处**（全仓 grep 实证），无其他模块共病。
- 与 kbVisible 共用同一 onChange 的另外三件——`safeBottom` 本身、`kbPad`（settleKbPad 去抖）、CREATE kb 计时边沿——都是**量测类消费**：数值本身即语义（底距要含安全区、kbPad 静息落 34 正是 0.9.48 定案口径），不共「布尔事实被量测闩锁」之病，本批一字未动。
- CREATE 边沿的 `ui.safeBottom == 0 && sb > 0` 前提与本次废弃的派生同源假设（静息为 0）——如实登记：其用途是一次性计时打点、另有 CREATE trace 在位守卫，属既有口径；是否随其自身证据另行治理不在本批范围，不顺手改动以免动 CREATE 计时链。

## 4. 根治落码（MomentApp.swift 两处 + verify [29]）

**原则**：状态必须由事实源派生自动收，不在完成钮点击处写「顺手收胶囊」的消费方补丁（红线禁）。`finishEditing()`、`doneExpanded`、`moreCapsule`、donecapsule 三行 Diag 格式**一字未动**（合同稳定：U4a 完成胶囊景的行序判读 expand→done→collapse 不变）。

1. **EditorUI 喂入换源**：kbVisible 改由 UIKit 键盘通知单点喂入——`init` 注册 `keyboardWillShowNotification` / `keyboardWillHideNotification`（主队列），`deinit` 逐 token 注销（`kbTokens`）；写点收敛于 `setKbVisible(_:height:)` 一处，翻转才写。EditorUI 随编辑会话生灭（EditorView 的 @StateObject），观察生命周期与会话同界，无全局跟踪器。声明处注释整段改写：写明旧源废弃机理与「键盘可见性是事实、不是量测，只许通知喂入」的防回潮口径。
2. **背景 onChange 瘦身**：删 kbVisible 三行写，留指针注释指向新源与本报告；safeBottom / CREATE / kbPad 三件原样保留。
3. **Diag 补行**：`EDIT kb visible=<0|1> src=notify h=<键盘端帧高>`（show 取通知 userInfo 的 keyboardFrameEnd 高、hide 恒 0），只在翻转时记。桥侧判读链：点完成后应见 `EDIT kb visible=0` → `EDIT donecapsule collapse`（done 行在前）；若 kb 行翻而 collapse 不至，断在派生/呈现；若 kb 行不翻，断在事实/喂入——四段可分段定责。

**行为等价与边沿**：通知的 willShow/willHide 与键盘升/落动画同拍起步，与旧边沿的感知时序一致；交互式滑动收起时 willHide 在收起动画起点发出、反悔上滑有 willShow 回正，布尔语义与可见性一致；外接硬件键盘无软件键盘时不展开（与旧源同口径：无键盘可收，完成段无意义）；编辑器被系统 sheet（选图器等）覆盖期间的键盘通知会短暂置位，但胶囊同被覆盖不可见，sheet 退场后由 hide 通知归位，终态恒正确。

## 5. 断言补强（verify [29]，本机自跑 [29] 七条全绿、全量 266 ✓，余 2 条既有产物类 ✗ 待 tree 构建自解）

- **F29-2 改写**（锁源的种类）：声明恰一处 + 通知两名各恰一处 + 写点字面 `kbVisible = visible` 恰一处 + 旧写 `ui.kbVisible = kbVis` **零残留** + 派生仍以 ui.kbVisible 为首项。**旧断言为何没拦住**：旧 F29-2 只锁接线拓扑（声明一处、写点一处、派生一处），从不问被测量的值语义——拓扑再单源，源量静息不回假照样闩锁。本条改锁「源的种类 + 旧源零残留」，任何几何量派生回潮即红（组内注释已写明此教训）。
- **F29-7 新增**（事实链可判读 + 生命周期 + 派生基数）：`EDIT kb visible=` 恰一处；`kbTokens` 恰 4 点（声明/两注册/deinit 遍历）；`removeObserver` 全文件恰一处（deinit 注销，防观察泄漏与第二注销点）；doneExpanded 合取行基数 = 5（首行并两格、共六抑制格，字面由 F29-5 逐个锁）——派生全输入清单以「字面（F29-5）+ 基数（F29-7）」双锁，增删任一输入即红。
- F29-1/3/4/5/6 不动（F29-1 含圆角批的 `Radius.pill` 口径，保持原样）。

## 6. 领地纪律

动工前快照在途 diff（1281 行）逐 hunk 映射：本批三段（EditorUI 声明区、背景 onChange 段、verify [29] 的 F29-2/F29-7）与圆角批（moreCapsule 半径行、EditorView/设置/Diag 各段）、布防批（桥文件）、U4a 的在途改动零交叠。完工复验：快照全部新增行在当前 diff 中逐字保留（集合差 = 0），moreCapsule 的 `.glassControl(radius: Radius.pill)` 未回退。Swift 编译级随主线 tree 冒烟（本机无 swiftc，已逐段复读 + 字面账核对）。

## 7. 真机终判点

1. 块编辑键盘升起：胶囊展开（Diag 应见 `EDIT kb visible=1 src=notify h≈330+` → `donecapsule expand`）。
2. **点勾：键盘落下、胶囊自动缩回圆钮、勾消失**（Diag 应见 `donecapsule done` → `EDIT kb visible=0` → `donecapsule collapse` 三行序）——本批头号终判。
3. 滑动收起键盘：胶囊同步缩回（visible=0 → collapse）。
4. 标题会话点勾：commitTitle 生效且胶囊缩回。
5. 字段间转移焦点（键盘不落）：胶囊保持展开不闪（无 visible 翻转行）。
6. 反复升/落键盘多轮：每轮 expand/collapse 各一行、无闩锁残留（第二次升起仍能正常展开并回缩）。
