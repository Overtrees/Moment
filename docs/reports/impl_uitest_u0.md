# UI 自检驱动 U0 地基落码报告（桥导航通道 + 在席 EditorModel 注册表）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。基线 HEAD ec4105c（0.9.54）。
> 规格：`plan_ui_selftest_driver.md` §7.1（U0 定义）+ `impl_bridge_m2.md` §7.1（接线待办）+ `plan_app_mcp_bridge.md` §5.3（editor_open/get_state/focus_block/save_now 规格与 memo_busy 错误表）。
> 本批只做地基：无 uitest 工具、无场景、不动清单。

---

## 1. 接口清单（逐项对照 M2 代码/报告的预期）

M2 侧的「预期接口」有三处成文：`impl_bridge_m2.md` §7.1（根视图导航请求口 + EditorModel 在席注册 + memo_busy 判定）、桥方案 §5.3 的四工具规格、`MomentBridgeTools.swift` BridgeWriteTools 头部注记（在席检测须等注册表接线）。本批逐项对齐如下——**没有新发明接口名**：导航请求口、在席注册、memo_busy 三个概念名均取自上述成文口径。

| # | M2 预期 | 本批落地 | 落点 |
|---|---|---|---|
| 1 | 根视图挂桥可调用的导航请求口（memoId → pushEditor） | `BridgeNavigationChannel.shared.requestOpen(memoId:completion:)`：查册 → 建 `EditorModel` → `host.pushEditor(kind: "open", onOpenMemo:)`，等在席登记对上号才回成功 | MomentEditorTransition.swift（通道本体）；ListView 探针点 `wire(host:library:openLinked:)` 接线（MomentApp.swift） |
| 2 | 关闭/回首页（§7.1「打开/关闭」+ 驱动方案 §3.2 closeEditor 的宿主半边） | `requestClose(completion:)` → 宿主新增 `dismissSeatedEditor()`：栈内有编辑器会话时 `popToRootViewController`（图片页在上时一并退），等注销落定回成功 | 同上 |
| 3 | EditorModel 在席注册（open 登记、close 注销） | `EditorSeatRegistry.shared`：宿主在 `pushEditor` / `replaceTopEditor` 两会话点 `seat(editor:token:)`、`endSession` 时 `unseat(token:)`；存 memoId + 模型弱引用 | MomentEditorTransition.swift |
| 4 | 桥据注册表补 `memo_busy` 判定（块级写在席限制，§7.2） | `BridgeEditorSeat.seatedConflict(memoId:library:)` 已接入 `editor_delete_block` / `editor_move_block` 两工具（参数校验后、快照与落盘前） | MomentBridgeTools.swift |
| 5 | `editor_get_state` 的读源（读 EditorModel：当前篇 id/标题/focusBlockId/editingBlockId/块序/脏态/双栏） | `EditorSeatRegistry.snapshot()` → `EditorSeatSnapshot`（memoId/title/focusBlockId/editingBlockId/draggingId/blockIds/blockTypes/columnsActive；块只出 id+type 结构序，不出正文摘要——摘要属工具批入册时按 §5.3 再定）；脏态判定 `BridgeEditorSeat.isDiverged(editor:library:)`（标题/块序规范哈希/bgColor/layout 与落盘态比对） | 同上两文件 |
| 6 | `editor_focus_block` 的消费点（置 focusBlockId） | `EditorSeatRegistry.focusBlock(_:caretEnd:)`：目标块须在在席篇内存在才置 `focusCaretEnd` + `focusBlockId`（与编辑器内既有落焦同字段同路） | MomentEditorTransition.swift |
| 7 | `editor_save_now` 的消费点（调 saveNow） | `EditorSeatRegistry.saveNow()`：在席模型直调既有 `EditorModel.saveNow()` | 同上 |

**边界守恒**：四工具本身**未入册**——`BridgeProto.toolNames` 仍 22 件、manifestHash 不变、分发器无新 case（plan §7.1 明文「其入册与断言归各自批」；B16-3 的「在席 4 名零注册」断言不破，新增 B25-U0-7 反向盯住清单计数）。工具批入册时只剩三件事：分发器 case → 通道/注册表既有方法、回包组装、[16] B16-3 口径改写。

## 2. 导航通道状态机

通道是进程内单例（`BridgeNavigationChannel.shared`），状态 = 接线态 × 在席态：

```
未接线 ──ListView 探针 attach 同点 wire()──> 已接线
   ▲                                            │
   └── 安全模式（ListView 不构建）恒停此态 ────┘

requestOpen(memoId):
  未接线 → nav_unavailable 拒绝
  只读打开态 → read_only_mode 拒绝
  在席 == 目标 → 成功（already=1，不重复 push）
  在席 == 他篇 → memo_busy 拒绝（不抢导航、不代关）
  目标不存在/已软删/在待删集 → memo_not_found 拒绝
  否则 → pushEditor(kind:"open") → 100ms 轮询等 seat 对上号
         ├─ 对上 → 成功（回 EditorSeatSnapshot）
         ├─ 等期间被他篇占席 → memo_busy 拒绝
         └─ 2.5s 未对上 → nav_timeout 拒绝

requestClose():
  未接线 → nav_unavailable 拒绝
  无在席 → 成功（already=1）
  在席 → dismissSeatedEditor() pop 回根 → 轮询等注销
         ├─ 注销落定 → 成功
         └─ 2.5s 未落定 → nav_timeout 拒绝
```

要点：
- **呈现只走正规路径**：打开 = 宿主 `pushEditor`（首帧前置、转场门、TRANSITION 打点全套既有编排），`onOpenMemo` 由接线方（ListView.openLinkedMemo）提供，编辑器内关联打开行为与用户点开完全同路；不另起呈现栈、不设 `wantsInitialFocus`（T17-6 的置位计数不破）。
- **应答以登记事实为准**：push 已调用 ≠ 已打开——宿主在探针未登记时有界重试，应答等注册表对上号才成功（桥方案 editor_open「等模型 id 对上或超时」的原口径）。
- **关闭与手势返回同路**：pop 后收口走 EditorView 既有 `onDisappear`（saveNow）。与页眉返回钮的差异如实标注：返回钮先 `commitTitle()` 再 saveNow，通道/手势返回不代按——标题字段未提交的草稿与手势返回同命运（驱动侧由 U1 并发门「在席未脏不抢」兜住，不在本批扩围）。

## 3. 在席注册表语义

- **登记点**：`pushEditor` 与 `replaceTopEditor` 的会话建立同回合（sessions 落册的下一行），保证任何经宿主呈现的编辑器（create/open/link 三路）都在席。
- **注销点**：`endSession`（承载控制器真正离开导航栈时经 `onRemoved` 触发；交互式返回取消不误报，沿用宿主既有判定）。
- **令牌防误清**：注销须带会话 `ObjectIdentifier` 令牌且与当前登记一致才生效——关联替换的收口序是「新会话先登记、旧会话后注销」，无令牌则旧注销会把新在席清掉。
- **弱引用兜底**：模型为弱引用，`currentMemoId` 在模型已释放时回 nil（视为退席），不拿陈旧登记下结论。
- **单在席**：注册表只记栈顶会话一份（编辑器是全屏 push，同一时刻只有一份当前会话；替换即换人）。

## 4. 拒绝口径表（导航通道 + memo_busy）

| 场景 | 码 | 来源 |
|---|---|---|
| 通道未接线（安全模式/列表不在位）open/close | `nav_unavailable` | 通道内部码（新） |
| 只读打开态（R2）请求 open | `read_only_mode` | 桥方案错误表既有码 |
| open 目标不存在 / 已软删 / 在待删集 | `memo_not_found` | 既有码 |
| open 时在席被他篇占用；等在席期间被他篇占走 | `memo_busy`（消息带在席 memoId） | 既有码（语义为「在席占用」，见下注） |
| open 等登记 / close 等注销 2.5s 超时 | `nav_timeout` | 通道内部码（新） |
| 块写（删块/移块）目标篇正在席 | `memo_busy`（消息带 dirty=0/1 注记） | 既有码 |

两点须主线裁认的口径注记：
1. **memo_busy 的块写口径比桥方案错误表更严**：错误表定义为「正在编辑器中**且有未保存改动**」、补救为「等保存或先 editor_save_now」。文档路径下不成立——编辑器持有独立块副本，**干净在席**时桥写入落盘后，编辑器下一次任意保存（防抖/saveNow）仍以编辑器态整篇覆盖，写入静默丢失。故本批口径 = **在席即拒（不分脏净）**，补救 = 关编辑器（save_now 不解除在席）；dirty 只作消息注记。M2 CONNECTOR.md 的既有限制声明（「只对未打开的篇用此两件」）与此一致。若主线要回收紧口径，前提是先落 DocumentMutationService（§7.4）让块写走编辑器路径。
2. **nav_unavailable / nav_timeout 为 App 内部码**：只出现在通道结果与 Diag 中，未对外（无工具入册）。工具批入册前须把这两码登记进桥方案错误表（或映射到既有码），不要直接带出。

相邻隐患（观察、未扩围）：`notes_soft_delete` 对在席篇同样有「编辑器下一次保存以其副本落盘」的复活面——M2 §7.2 的在席限制只点名块级两件，本批按点名范围接线；软删面是否同拒，留主线裁定后另批。

## 5. Diag 打点（与既有 BRIDGE 打点同风格）

| 行 | 时点 |
|---|---|
| `BRIDGE nav wire` | 通道首次接线（进程内一行） |
| `BRIDGE seat register memo=<id>` | 每次会话登记 |
| `BRIDGE seat unregister memo=<id>` | 每次会话注销（令牌匹配时） |
| `BRIDGE nav request open memo=<id>` | 每次打开请求 |
| `BRIDGE nav open ok memo=<id>`（同篇带 `already=1`） | 打开成功 |
| `BRIDGE nav open rejected memo=<id> code=<码>` | 打开拒绝（warn） |
| `BRIDGE nav request close` | 每次关闭请求 |
| `BRIDGE nav close ok memo=<id>`（无在席为 `memo=- already=1`） | 关闭成功 |
| `BRIDGE nav close rejected code=<码>` | 关闭拒绝（warn） |
| `BRIDGE nav error seat_inconsistent memo=<id>` | 注册表称在席但宿主栈内无此会话（error；结论仍以等注销结果为准） |

## 6. verify 断言（[25] 组，U0 条目）

新增 **[25] 组「桥内 UI 自检驱动」**，本批落 U0 条目 7 条（编号 `B25-U0-*`，与方案 §7.3 的 B25-1..9 分开编号以免撞号）；方案 §7.3 的 B25-1..9 属 U1–U3，已在组头注释留位注明、落码时按原编号补入，不预设空断言。

| 条目 | 锁的机制 |
|---|---|
| B25-U0-1 | 注册表定义在位；`seat(` 调用恰 2 处（push/替换）；`unseat(` 在收口点 |
| B25-U0-2 | 通道四口（wire/requestOpen/requestClose/dismissSeatedEditor）+ `popToRootViewController` + 打开走 `kind: "open"` 正规路径 |
| B25-U0-3 | 根视图（ListView）接线点在位 |
| B25-U0-4 | 拒绝五码字面齐全 |
| B25-U0-5 | `seatedConflict(` 调用恰 2 处（删块/移块）+ 判定枚举与分叉比对在位 + `memo_busy` 码 |
| B25-U0-6 | Diag 打点九行齐全 |
| B25-U0-7 | 边界守恒：BPROTO 中 `"editor_` 计数仍为 2（在席四工具未混入清单） |

本机自跑结果：**[25] 七条全绿**；全脚本仅剩 2 条 ✗——`ipa 陈旧` 与 `产物语言包缺失或与 Web 源不一致`，均为产物类（本机无新构建，tree 构建后自解），与前批本机自跑的已知项一致，非本批引入。Swift 编译级验证随主线 tree 冒烟（本机无 swiftc；已做括号平衡自查与逐段复读）。

## 7. 改动清单

| 文件 | 改动 |
|---|---|
| MomentEditorTransition.swift | 宿主三处会话点接注册表（push/替换登记、endSession 注销）；新增 `dismissSeatedEditor()`；文件尾新增 `EditorSeatSnapshot` / `EditorSeatRegistry` / `BridgeNavError` / `BridgeNavigationChannel`（约 +320 行） |
| MomentApp.swift | 仅 ListView 探针点一处：attach 同点加通道 `wire(...)`（约 +9 行） |
| MomentBridgeTools.swift | 新增 `BridgeEditorSeat`（seatedConflict + isDiverged）；删块/移块各加一处在席判定；BridgeWriteTools 头部注记按接线完成更新 |
| verify_ios.sh | 新增 [25] 组（B25-U0-1..7 + 组头留位注记） |

未碰：桥清单/协议/传输/协调器/运维/设置文件、设置区、卡片渲染段、build 脚本（无新文件，无需改构建名单）。

## 8. U1 接续点

- 驱动（MomentBridgeUITest.swift）的开篇/关篇步直接调 `BridgeNavigationChannel.requestOpen/requestClose`，在席状态读走 `EditorSeatRegistry.snapshot()`——S1 场景步 1/步 7 的地基已就位。
- 驱动并发门（plan §5.2）需要的「在席篇 + 脏态」判定源 = `EditorSeatRegistry.currentMemoId` + `BridgeEditorSeat.isDiverged`（本批已落，U1 复用不另造）。
- 工具批（editor_open 等四件入册）与 U1 的先后不冲突：入册时把 §1 表的 5/6/7 号地基方法组装成回包即可；入册批须同步：清单 22→26、中继 TOOLS/scope、连接器 ALLOWED_TOOLS、B16-3 改写、错误表登记 nav 两码（或映射）。
- 本批未落的 M2 §7 余项（与 U0 无关、仍待排批）：rescue_arm_safe_mode 的布防消费点（§7.3）、DocumentMutationService 抽取（§7.4，随正文级工具解禁）。

## 9. 工作树注记（防误账）

开工时工作树并非全净：MomentApp.swift 与 verify_ios.sh 内已有一批未提交改动（附件行宽屏半径恢复 `Radius.attachmentFile` + [21] R21-9 口径更新，报告 `fix_attachment_radius_wide.md`，属 0.9.54 组版 S1 复核的后续小批）——与本批同文件不同段落，本批未触碰、未回退；主线提交时须按批分拣（本批在 MomentApp.swift 的增量只有 ListView 接线一处、verify 只有 [25] 一组）。
