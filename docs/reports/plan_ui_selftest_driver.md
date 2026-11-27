# 桥内 UI 自检驱动方案（App 内脚本化回路 + 几何量测 + Diag 证据）

> 状态：**方案稿，未落码。** 基线：HEAD 78bac65（0.9.53），工作树含 M2 桥批与
> 0.9.54 批（留白/内角/浮层 + 标题胶囊根治）未提交改动——本方案的事实引用以
> 该工作树为准，落码须排在 0.9.54 组版收口之后，不得与在飞批次抢同一文件段。
>
> 起因：用户 2026-11-27 要求这类 UI 问题（标题胶囊二次编辑点不动、卡片留白
> 不等距、复合卡内角、菜单面板高度）能**自动化验证、包括模拟点击**。外部遥控
> iPhone 不可行（无 Mac、无模拟器、设备在用户网络后），但桥运行在 App 进程
> 内——本方案的核心是把「场景回路」搬进 App：桥工具下指令，App 在主线程走
> **与手指相同的 handler 路径**执行脚本化步骤，把状态、几何量测与 Diag 证据
> 经桥回传，由助手侧判读。
>
> 与桥方案（plan_app_mcp_bridge.md）的关系：本方案是其验证面的延伸，不改其
> 传输、配对、能力分层与错误模型；与 §8 验证纪律的关系是**细化而非突破**——
> 驱动能把证据层从「数据/状态层」推进到「handler 以内 + 布局几何层」，但
> §8 钉死的真机终判面（真实触摸命中投递、识别器仲裁、键盘与体感）不因驱动
> 存在而降级。逐场景的能证/不能证边界见本文 §6。

---

## 0. 结论先行

1. **形态**：新增一组桥工具 `uitest_*`（清单见 §2），执行体是 App 内的
   「自检驱动」：命名场景（编译期内置脚本，不接受桥上传任意步骤）+ 视图
   注册表（可测面以 id 注册 frame 与动作入口）+ 主线程串行步进引擎
   （异步作业模型，沿用桥方案 §3.3 的 runId/轮询形态）。
2. **「模拟点击」的口径**：不构造 `UITouch`、不注入 UIKit 事件、不碰私有
   API。驱动调用的是**与手势 handler 同一个闭包**——注册动作的前提是把该
   面手势/按钮的动作体抽成具名入口，手指与驱动共用一份（单一来源规则，
   §3.2）。等价面是 handler 以内的全部状态机与呈现；不等价面是 handler
   以外的命中投递与识别器仲裁，逐项标明（§3.5、§6）。
3. **能力门**：全部 `uitest_*` 归 **ops 层**（现配对已授 read+ops，落地即
   可用，不必为新能力位重新配对）；`uitest_run` 另加两段提交令牌（与
   `rescue_try_normal_start` 同级）。安全模式受限集**不收** uitest（编辑器
   在安全模式下根本不在位），一律 `safe_mode_limited`。
4. **与 M3 的关系**：**独立一批（下称 U 批），不并入 M3**。M3 场景库是语义
   层（文档/数据/运维收敛），驱动是视图层（焦点/呈现/几何），执行层、风险
   面、前置各不相同；两者共用异步作业信封，M3 落地后其场景可把驱动运行
   作子步组合，但互不阻塞（§2.4）。
5. **前置**：驱动与 M2 报告 §7.1 的接线待办（桥导航通道 + 在席 EditorModel
   注册表）是**同一块地基**——先落这块（U0），`editor_open` 等 M2 在席工具
   与驱动共用它，避免两套在席口径。
6. **首批场景**：S1 标题胶囊二次编辑回路（本次报障的正主）、S2 几何量测
   探针（卡面对齐/拾起间隙/菜单面板高，回数值不回截图）、S3 拖拽拾起回路
   （可行性评估结论：状态机与呈现层可驱动，识别器仲裁不可——见 §4.3）。

---

## 1. 现行事实基础（方案落点）

只写基线源码已存在的事实；「建议新增」在后续章节明示。

### 1.1 桥的现状（M1 + M2 已落码）

- 分发器 `BridgeDispatcher`（MomentBridgeTools.swift）：主线程经协调器
  `handleFrameOnMain` 进入；能力门三层集合字面量——`writeScopeTools`（7）、
  `opsScopeTools`（3：ops_refresh / notes_delete_permanent /
  rescue_try_normal_start）、`dataWriteTools`（写全集，辖快照/幂等/只读门/
  OPS 禁桥深查）；两段提交 `twoStageTools`（dryRun 发一次性 actionToken、
  绑定工具名 + 规范参数哈希、60 秒）；受限集 `safeLimitedTools`（8 件，
  plan §9.6 口径）。清单外一律 `unknown_tool`。
- 工具清单 22 件在 `BridgeProto.toolNames`，manifestHash 三方（App/中继
  worker.js TOOLS/连接器 ALLOWED_TOOLS）对账；**清单增删必同步四处**
  （App 清单、中继 TOOLS 与其 scope 表、连接器 ALLOWED_TOOLS、verify
  [16] B16-3 的逐名枚举）。
- 写安全底座 `BridgeWriteSupport`：写前快照（临时只读 FFI 句柄直调
  `exportBackup` → `Application Support/bridge-snapshots/`，不走
  `exportZip()`、不污染备份新鲜度）、幂等回放、operations.jsonl 流水、
  `BRIDGE write/snapshot` 结果行。驱动的夹具卫生链复用它（§5.1）。
- 设备当前授权 scopes = **read + ops**（write 未授）：M2 的 write 层 7 件
  现被正确拒（`scope_denied`）。驱动归 ops 层的现实收益即在此——不依赖
  write 授权变更。
- 桥只在前台在线：后台挂起即断连、回前台 backoff 重连（设计行为）。
  驱动运行天然只可能发生在前台，这与 §5.2 的并发门同向。

### 1.2 尚不存在、驱动必须先补的地基

- **桥无从触达视图层**：协调器只持有 `weak var library: Library?`；打开
  编辑器走 ListView 局部的 `nav.editorHost.pushEditor`（EditorTransition
  Host，0.9.50 转场宿主），桥没有导航通道，也没有「当前在席 EditorModel」
  的注册表——此即 M2 报告 §7.1 的接线待办第 1 项，`editor_open /
  editor_get_state / editor_focus_block / editor_save_now` 与本驱动共用。
- **手势 handler 是视图内闭包**：如标题胶囊截断覆盖层的 `onTapGesture`
  闭包（EditorHeaderView.titleCapsule）、行拾起的 `DragPressAnchor`
  回调——外部不可调用，须按 §3.2 抽具名入口后注册。
- **量测回读两件未出货**：桥方案 §5.6 的 `metrics_create_settle /
  metrics_drag_trace` 在 M1/M2 均顺延未落，清单中不存在。驱动的证据回
  传不依赖它们（驱动自带 Diag 窗口抓取，§3.4），但 S3 的真机拖拽轨迹
  复核仍指向这两件，建议随 U 批顺手补齐或单列（§7）。

### 1.3 可复用的量测与状态通道（驱动不新造口径）

| 通道 | 现状 | 驱动用途 |
|---|---|---|
| `BlockState.frameMinX / frameMinY` | BlockRow 的 background GeometryReader 持续回写（`editorScroll` 命名坐标系，非 @Published 不触发重演算） | 块行盒在编辑列内的位置（S2 行盒缘） |
| `BlockState.rowW / height` | 同上（rowW 随宽变、height 原子块实测/文本块由 UITextView 回报） | 行盒宽高、拾起缩放口径 |
| `EditorUI.menuPanelH / slashPanelH` | 面板内容 VStack 的 `onGeometryChange` 实测回写（>0.5pt 才写）；面板帧高 = min(实测, cap)，0 = 未量得走估高 | S2 菜单面板「内容高 vs 渲染高」双读 |
| `EditorUI.viewW / viewH`、`EditorScrollState.scrollY` | EditorView GeometryReader 喂入 | 列宽基准、滚动位 |
| `Radius` 令牌 + `Radius.lift(face:)` | 0.9.52 单源：面半径唯一入口、拾起框 = 面 ⊕ liftInset 4 同心派生 | S2 间隙期望值的**计算源**（断言用派生式不用写死数） |
| `EditorModel` 的 @Published 面 | `focusBlockId / editingBlockId / draggingId / dragDy / settleId / blockMenuBlockId / cardMenuBlockId`、blocks 序 | 驱动状态等待与回读断言 |
| `DiagLog.today` | 当天 300 条内存环（条目 {ts, level, text}），`log/logOnce/logErrorOnce` 主队列入环 | 步进等待判据（等行出现）+ 证据窗口抓取 |
| CREATE / TRANSITION / DRAG 打点 | settle 分段行、转场 `TRANSITION … claim/kb` 行、DRAG 全状态行（state/ms/disp） | 开篇落定判据、S3 对照 |

### 1.4 本次三个报障面的结构事实（场景设计的依据）

- **标题胶囊**（fix_title_capsule_reedit.md）：根治后字段恒常驻，截断态
  覆盖层 `onTapGesture` 闭包 = { 记 `EDIT title focus via=capsule`；
  `titleFocused = true` }；会话真开始的权威信号是 `onChange(of:
  titleFocused)` 里的 `EDIT title session begin len=` 行；提交走
  `commitTitle()`（trim + 空回退），Enter 辞焦、失焦自动 commit、Esc 还
  原 `titleBase` 快照。判读规则现成：两行齐现 = 进入成功；只有前者 =
  置焦未落（复发信号）；皆无 = 命中未达入口——驱动 S1 即把这条人工判
  读自动化。注意：原 bug 位于 handler **以内**（置焦与字段入层级同事务
  竞态），驱动调用同一 setter 路径**可以复现/证伪这一类**；命中投递类
  不在此列（§6）。
- **留白/内角**（fix_lift_spacing.md）：主因是行盒 HStack 尾随幻影间距
  （内容槽恒窄 8、只亏右侧），根治后内容槽 ≡ 行盒成构造事实；面框
  （LiftFrame）挂行盒 background ⊕4，image/gallery 的面在子视图内。
  S2 的断言因此写成**几何关系式**（面缘与列缘差、框面四边差），数值由
  运行时量测回传，不写死期望像素。
- **菜单面板**（同上）：帧高已改实测回写口径，S2 只需双读
  `menuPanelH` 与面板实际帧高作差，并断言内容未达 cap 时差 ≈ 0。

---

## 2. 工具面

### 2.1 拟新增工具清单

执行模型：`uitest_run` 是异步作业（桥方案 §3.3 场景口径同型）——立即
返回 `runId`，`uitest_get_result` 轮询取全量证据包；`uitest_measure`
是同步快探（只读量测、无动作、单帧上限内完成）。

| 工具 | 入参 | 返回 | 属性 |
|---|---|---|---|
| `uitest_list_surfaces` | 无 | 当前已注册面清单：`surfaces[]`（id、kind、是否有 frame、动作名集、状态键集）+ 编辑器在席信息（memoId、脏态） | ops；只读语义（回 UI 结构与状态键名，不回正文） |
| `uitest_run` | `scenario`（内置场景 id）、`params?`（场景声明的有限参数）、`dryRun/actionToken`（两段提交） | `runId`、场景 id、受理时刻 | ops + 两段提交；驱动夹具与 UI 状态 |
| `uitest_get_result` | `runId` | 作业状态（running / done / failed / aborted）+ 证据包（§3.4 格式） | ops；只读 |
| `uitest_measure` | `probe`（内置探针 id，如 `card_alignment` / `lift_gaps` / `menu_panel`）、`target?`（blockId 等） | 量测数值集（§4.2 各探针定义）+ 量测时刻的在席上下文 | ops；只读量测（lift_gaps 需拾起态在位——由用户真机拾起或 S3 驱动拾起后调用，工具本身不触发动作） |

**场景与探针都必须是编译期内置、按 id 索引的注册项**，桥参数只许选
id 与场景声明的标量参数（超时、循环次数等有界项）。不接受桥上传任意
步序列/任意代码/任意方法名——驱动的动作面恒等于注册表内已审的动作
集，这是本方案的安全基线（与桥「不做任意 JSON 直写」同精神）。

### 2.2 能力门与分发器落点

- 新增分发器集合 `uiTestScopeTools`（4 件），门 = `ops` 能力位；未授
  回 `scope_denied`（与既有门同形态、执行前拦截）。
- `uitest_run` 入 `twoStageTools`：dryRun 取令牌 → 回带执行，缺/错/
  过期回 `confirmation_required`。理由：它会当着用户的面驱动 UI 并
  建/删夹具篇，属「设备呈现面动作」，与 `rescue_try_normal_start`
  同级；令牌由助手侧程序化取得，不打扰用户。
- 数据门复用：`uitest_run` 执行前过与 `dataWriteTools` 相同的前置门
  （库在位、非只读打开态、OPS 未点名禁桥），回码同名
  （`library_unavailable` / `read_only_mode` / `ops_disabled`）。
- 中继侧同步：worker.js TOOLS +4、新增 `UITEST_SCOPE_TOOLS` 门（ops）
  与超时口径（run 受理 15s、get_result 15s、measure 15s；作业本身在
  App 内跑，不占中继长连接）。连接器 ALLOWED_TOOLS +4，须按桥方案
  §10 纪律逐项审单后才放行（服务端先加默认仍被 helper 拦下）。
- manifestHash 随清单变化（22 → 26），三方对账机制现成，`bridge_
  status` 会现形中间态——部署须与 App 同批（与 M2 同纪律）。

### 2.3 安全模式受限集下的可用性

**全部不可用。** `safeLimitedTools` 不加 uitest 任何一件，安全模式
（含会话中途 forceSafeMode 收紧的纵深防御路径）下调用一律
`safe_mode_limited`。理由：安全模式的定义就是库不开、编辑器不在
位、只碰 Diag/哨兵/OPS/桥自身状态；驱动的前提（在席编辑器、夹具
写、视图注册）全部不成立，硬塞只读量测也没有对象。救援面需要的是
`rescue_status` 那类同源状态组装，与驱动无关。

同理，只读打开态（R2）下 `uitest_run` 回 `read_only_mode`；
`uitest_list_surfaces / uitest_measure` 在只读态可回（纯读），但编
辑器在席与否如实回，不假装可测。

### 2.4 与 M2 / M3 的关系（裁定：独立 U 批）

| 维度 | M2（已落码） | M3（未开） | U 批（本方案） |
|---|---|---|---|
| 执行层 | Library/文档路径（数据与结构） | 语义场景编排（组合 M1/M2 工具） | 视图层（焦点/呈现/几何） |
| 碰 MomentApp.swift | 仅接线待办（§7） | 少量（场景挂点） | 注册锚点 + 动作抽取（编辑器呈现段为主） |
| 前置 | 快照底座（已落） | M2 + R2/R3 部分项 | U0 在席注册表（与 M2 §7.1 共用） |
| 风险面 | 数据写（有快照兜底） | 运维命令（只能收紧） | 呈现面扰动（有并发门 + 复原链兜底，§5） |

- **不并入 M3** 的理由：M3 的核心交付是场景库与运维打通，其场景全
  是语义级；把视图驱动塞进去会让 M3 同时背「文档内核/运维命令」与
  「视图注册/焦点驱动」两套完全不同的风险与验收口径，且 M3 还压着
  R2/R3 前置，驱动会被无谓拖住。反之驱动也不该等 M3。
- **共用件**：异步作业信封（runId/轮询/证据包四件套格式与桥方案 §8
  第 4 条对齐）；U0 地基（下节）；Diag 前缀纪律。M3 落地后，
  `scenarios_run` 的场景可以把一次 `uitest_run` 作子步（组合方向
  单向：语义场景调驱动，驱动不调场景）。
- **排期建议**：U0 随 M2 的 §7 接线批一起落（本来就要动根视图与
  EditorModel 在席口径）；U1（驱动核 + S1）在 U0 后独立成批；U2
  （S2 探针）在 U1 后；U3（S3）只做评估结论落地与轨迹复核补齐，
  是否实装驱动拾起由 U2 验收后另行裁定（§4.3）。

---

## 3. 驱动机制

### 3.1 视图注册表（UITestRegistry）

新文件 `MomentBridgeUITest.swift`（驱动核 + 注册表 + 场景/探针实
装；桥六文件之外的新增文件，构建集成见 §7.3）。注册表是进程内单
例、主线程限定（一切注册/注销/读取只在主队列，与分发器同线程模
型，不引入锁）。

条目结构（设计级）：

```text
SurfaceEntry {
  id: String            // 稳定 id，如 "editor.titleCapsule"
  kind: String          // capsule / blockRow / cardFace / panel / editor
  instance: String      // 实例键（块面 = blockId；单例面 = "-")
  frameInEditor: () -> CGRect?   // editorScroll 坐标系（编辑页内面）
  frameInWindow: () -> CGRect?   // window 坐标系（浮层/页眉面）
  actions: [String: () -> Void]  // 具名动作（§3.2 单一来源）
  state:   [String: () -> String] // 具名状态读（字符串化，避免类型外泄）
}
```

注册方式**照搬本仓已实证的 DragPressAnchor 模式**：一个 0 尺寸、
`isUserInteractionEnabled = false` 的 UIViewRepresentable 锚点
（`UITestAnchor`），其 `updateUIView` 在每次视图更新时以当前 body
闭包刷新注册（回调随渲染保鲜），`dismantleUIView` 注销。同构先例
的三个性质直接继承：注册失败不静默（首帧无祖先时有界重试 +
logOnce 留痕的口径可移植）、行回收时条目随之注销、条目恒反映最
新一轮 body 的闭包捕获。

分面注册计划（首批）：

| 面 id | 注册点 | frame 源 | 动作 | 状态读 |
|---|---|---|---|---|
| `editor.titleCapsule` | EditorHeaderView.titleCapsule | 胶囊本体 GeometryReader（新增一处背景量测，与既有 headerW 量测同模式） | `tap`（§3.2 抽取后入口）、`resign`（= onSubmit 同路：commitTitle + 辞焦） | `focused`（注册闭包读当轮 titleFocused）、`truncated`、`draftLen` |
| `editor.view` | EditorView | viewW/viewH 既有量测 | `close`（= 返回钮同路：commitTitle + saveNow + onBack） | `memoId`、`dirty`、`focusBlockId`、`draggingId` |
| `editor.menuPanel` | ••• 菜单面板呈现处 | 面板帧 GeometryReader（新增） | `open` / `close`（= ••• 钮同路 toggle 的两向显式版） | `renderedH`、`contentH`（读 ui.menuPanelH）、`capped` |
| `editor.block.<id>`（行盒） | BlockRow（DragPressAnchor 同点位） | 读 BlockState.frameMinX/Y + rowW/height（已量测，不新挂） | `pickup` / `dragBy` / `drop` / `cancel`（U3，前置评估 §4.3） | `type`、`dragging` |
| `editor.face.<id>`（卡面） | 各卡面子视图（image 图本体/gallery 格网/各卡面根视图） | 子视图 GeometryReader 回写 BlockState 的新增 face 通道（faceMinX/faceW，editorScroll 系） | —（纯量测面） | `faceKind`、`faceRadius`（Radius 派生值回读） |

块行盒一栏说明：行盒几何已由 BlockState 通道现成供给，注册表对
块面只登记「在席块 id 集 + 类型」，frame 读直走 BlockState，避免
第二套量测口径；只有**卡面**需要新通道，因为面在子视图内、与行
盒的相对关系正是 S2 要测的量。

注册纪律：

- 注册表只存弱引用语义的闭包（闭包捕获视图状态对象，不捕获视图
  本体）；条目 frame 闭包返回 nil = 面已离场，驱动据此判
  `surface_missing`，不拿陈旧 frame 下结论。
- 同 id + instance 重复注册以后到为准（updateUIView 刷新语义）；
  注销只认同 instance 的条目，防行回收误注销新实例。
- 注册表内容经 `uitest_list_surfaces` 回读时只出 id/kind/动作名/
  状态键名与 frame 是否可得，**不出 frame 数值本身**（数值只经
  measure/场景证据包出，带场景上下文才可判读）。

### 3.2 「模拟点击」的实现口径（单一来源规则）

**规则：一个面只有当它的手势/按钮动作体被抽成具名入口、且手指
路径与注册动作指向同一入口时，才可注册为可驱动面。** 抽取是行
为等价重构（闭包体原样搬家），不是给驱动另开一条近似路径——这
保证驱动测的就是用户用的那份逻辑，日后改 handler 驱动自动跟
随，不存在「测试路径与真实路径分叉」的维护债。

首批抽取点（均为小范围、行为等价）：

1. 标题胶囊覆盖层：`onTapGesture` 闭包体（记行 + 置
   `titleFocused = true`）抽为 EditorHeaderView 内的
   `activateTitleFromCapsule()`，手势与注册动作共用。
2. ••• 钮：`ui.showMenu.toggle()` 抽为 `toggleEditorMenu()`，
   注册动作 `open/close` 是其显式两向版（置 true/false 后走同一
   状态位，呈现链无第二入口）。
3. 编辑器关闭：返回钮动作体（commitTitle + saveNow + onBack/
   dismiss）抽为 `closeEditor()`，驱动 `editor.view/close` 与列表
   侧打开（pushEditor）共用转场宿主入口。
4. （U3）行拾起四回调：DragPressAnchor 的 onPickup/onDrag/
   onDrop/onCancel 已是 EditorModel 状态操作闭包，注册动作直接
   引用同一组闭包——但触发源不同（识别器 vs 驱动），边界见
   §4.3。

文本注入的口径（S1 改标题用）：驱动经注册动作置 `ui.titleDraft`
（即 TextField Binding 的 setter 同路）后调 `resign` 入口提交。
它等价于「用户已输入完毕后的提交链」，**不等价于逐字输入**：
拼音组字、连打、粘贴分段等 IME 路径不在驱动面内（§6 明示）。

### 3.3 步进引擎（UITestDriver）

- **执行线程**：全程主队列。分发器收到 `uitest_run` 后把作业挂
  起即返回 runId；引擎以 async 步进（每步后让出 runloop 一帧再
  续）执行，避免长占主线程饿死桥心跳与 UI。
- **步模型**（场景 = 编译期步数组，步类型封闭集）：
  - `invoke(surface, action)`：查注册表取动作闭包执行；面不在
    位 → 步失败 `surface_missing`。
  - `setText(surface, value)`：仅标题胶囊面，置草稿（值由场景
    在 App 内生成，见 §5.1，不由桥参数传入正文）。
  - `waitDiag(pattern, timeoutMs)`：等 Diag 窗口内出现匹配行
    （§3.4 窗口定义）。
  - `waitState(surface, key, equals, timeoutMs)`：轮询状态读直
    至相等。
  - `waitLayout(probe, timeoutMs)`：等量测落定（§3.4 落定判
    据）。
  - `measure(probe, target)`：取量测快照入证据包。
  - `assert(name, expr)`：expr 是场景内编译期的关系式（读已取
    得的状态/量测/Diag 计数），结果入证据包；断言失败 = 场景
    失败（不是引擎错误），证据照常回全。
  - `callToolInternal(name, args)`：场景内直调分发器同层的已
    有工具实现（如 notes_get 回读、notes_soft_delete 清理）——
    走同一实现函数、不经中继往返，结果并入证据包。
- **落定判据（settle）**，按步类型钉死，不许场景自创：
  - Diag 类：目标行 ts ≥ 本步起始时刻且入环可见（DiagLog 入环
    在主队列，引擎同队列轮询，天然有序）。
  - 状态类：谓词连续两轮（间隔 ≥100ms）成立，防读到过渡帧。
  - 布局类：同一量测连续两次（间隔 ≥100ms）差 ≤0.5pt（与
    menuPanelH 回写的 0.5 阈值同口径），且量测通道非初始值
    （如 menuPanelH > 0 才算已量得，0 是「未量得」不是高度）。
  - 转场类：开篇等 `TRANSITION` 完成行或 focusGateOpen 状态
    （转场宿主既有信号），不写死毫秒睡眠冒充落定。
- **超时与失败回收**：每步默认超时 5s（场景可声明至 15s）；
  步失败 → 作业转入**复原链**（§5.3）→ 结果码 `step_failed`
  并附失败步与已抓证据；作业总超时 90s 硬顶，超时同走复原链、
  结果码 `run_timeout`。引擎同一时刻只跑一个作业（驱动是串行
  资源），已有作业在跑时新 `uitest_run` 回 `driver_busy`。
- **作业留存**：结果在进程内保留最近 5 个 runId 供轮询；进程
  重启即失（证据真源是 Diag 与 operations 流水，作业结果只是
  呈现层——与桥「证据真源在 App 内 Diag」同口径）。

### 3.4 证据包格式（回传判读的唯一形态）

沿用桥方案 §8 第 4 条四件套，结构化为：

```json
{
  "runId": "…", "scenario": "title_capsule_reedit",
  "code": "ok | step_failed | run_timeout | aborted_user_active | hygiene_failed",
  "startedAtMs": 0, "finishedAtMs": 0,
  "fixture": { "memoId": "m-…", "preLibraryHash": "…",
               "postLibraryHash": "…", "cleaned": true },
  "steps": [
    { "n": 1, "kind": "invoke", "surface": "editor.titleCapsule",
      "action": "tap", "waitMs": 132, "ok": true,
      "assertions": [
        { "name": "session_begin_seen", "pass": true,
          "expected": "EDIT title session begin ×1",
          "actual": "EDIT title session begin len=21" }
      ],
      "diag": ["14:41:02.113 EDIT title focus via=capsule",
               "14:41:02.246 EDIT title session begin len=21"]
    }
  ],
  "measurements": { },
  "grades": { "stateMachine": "proven", "hitDelivery": "unknown",
              "note": "…" }
}
```

- `diag` 只收本步时间窗内、与场景相关的行（按前缀/模式过滤），
  附呈现行原文（与 App 内导出同格式，便于对账）；全量仍可经
  `diag_tail` 复核，证据包不冒充全量。
- `measurements` 的数值一律带单位（pt）与坐标系标注
  （editorScroll / window），小数值原样回传不四舍五入到整数。
- `grades` 由场景模板声明（§6 的逐场景表落进代码常量），报告
  侧引用时不得升级。

### 3.5 等价 / 不等价总表（「模拟点击」诚实边界）

| 环节 | 手指路径 | 驱动路径 | 等价性 |
|---|---|---|---|
| 触点命中（hitTest、z 序、allowsHitTesting、contentShape 区域） | UIKit 命中链决定 handler 是否被叫 | **不经过**——直接调 handler | ✗ 不等价（驱动恒「命中」） |
| 手势识别器仲裁（tap vs pan、长按计时、并行豁免） | 平台仲裁 | **不经过** | ✗ 不等价 |
| handler 动作体（置状态位、记 Diag、调模型） | 闭包本体 | 同一闭包（§3.2） | ✓ 等价（构造保证） |
| handler 后的框架反应（FocusState 落定、@Published 重演算、转场、动画排程） | SwiftUI/UIKit 运行时 | 同一运行时、同一主线程 | ✓ 等价（动画的**时间过程**不等价于体感，落点状态等价） |
| 落盘与数据链（commit/persist/回读） | 模型真源 | 同一真源 | ✓ 等价 |
| 键盘升起、光标落点、IME 组字 | 系统键盘与字段委托 | 驱动只置焦点状态与草稿值 | ✗ 不等价（焦点**状态机**等价，键盘**呈现与输入过程**不等价） |
| 触觉反馈、视觉动效手感 | 设备呈现 | 触发同代码但无人眼判读 | ✗ 不可判（不在证据面） |

推论（写进判读规矩）：驱动绿 = 「handler 以内的逻辑在真机、在
真实数据与真实运行时上成立」；驱动绿**永远不能**推出「用户点
得动」——命中与仲裁两环仍须真机手指 + Diag 判读（这正是标题胶
囊报告里「两者皆无 = 命中未达入口」那一档，驱动结构上到不了
那一档）。

---

## 4. 首批场景

### 4.1 S1 标题胶囊二次编辑回路（scenario: `title_capsule_reedit`）

前置：并发门通过（§5.2）；夹具篇已建（§5.1，初始标题为 App 内
模板短标题）。全程只动夹具篇。

| 步 | 动作 | 等待/断言 | 证据 |
|---|---|---|---|
| 1 | 经 U0 导航通道打开夹具篇（pushEditor 同路） | waitState editor 在席且 memoId = 夹具；TRANSITION 完成行入窗 | 在席状态读 |
| 2 | `invoke(editor.titleCapsule, tap)`（短标题态：字段本体点按路径——注：短标题态手指走原生落焦，驱动 tap 动作在此态定义为「置 titleFocused」入口，与覆盖层共用同一置焦结果） | waitDiag `EDIT title session begin`（≤5s） | Diag 窗口行 |
| 3 | `setText` 置草稿为长标题模板（>10 标量，App 内生成 + run 序号后缀）→ `invoke(editor.titleCapsule, resign)` | waitState editor.title = 模板值；断言 commit 后 `notes_get`（内部直调）标题一致 | 标题回读 |
| 4 | 断言呈现态：状态读 `truncated == true`（长标题 + 未聚焦 → 截断覆盖层在位——**这是原 bug 的发作态**，回路必须在此态做第二次进入） | waitLayout 胶囊帧稳定 | 状态读 + 帧 |
| 5 | `invoke(editor.titleCapsule, tap)`（覆盖层入口，与手指同一闭包） | waitDiag 两行成对：`EDIT title focus via=capsule` 与 `EDIT title session begin` 各 ×1 且时序 focus 在前（≤5s）——**核心断言** | Diag 窗口行（原文） |
| 6 | 再置短标题 → resign → 断言 title 回读一致；再重复步 5 一次（长标题态第二次循环，防「修一次好一次」式假绿） | 同步 5 的成对断言 | Diag + 回读 |
| 7 | 关闭编辑器（editor.view/close）→ 夹具清理链（§5.1）→ 断言 postLibraryHash == preLibraryHash | 卫生断言 | 哈希对账 |

失败判读映射（场景结果自带）：步 5 只有 via 行无 begin 行 =
置焦未落（原 bug 复发形态）；两行皆无 = 注册动作未达（驱动侧
问题，先查注册表）；begin 行有但回读标题不对 = 提交链问题。

### 4.2 S2 几何量测探针（probes，同步工具 `uitest_measure`）

探针不做动作，只读注册表与量测通道；调用前置 = 编辑器在席
（用户手动打开或 S1/S3 类场景开好），目标篇内容由调用方负责
（探针只测「当前在席编辑器里指定块」的几何）。

**P1 `card_alignment`（卡面与正文列对齐）**：入参 blockId。
回：行盒 frame（minX / maxX，editorScroll 系）、卡面 frame
（faceMinX / faceMaxX）、正文列基准（列左 = 内容区左缘、列右 =
左缘 + 列宽，由 EditorView 量测与列 padding 派生）、四值差：
`leftDelta = faceMinX − colMinX`、`rightDelta = colMaxX −
faceMaxX`。判读基线：满宽卡应 leftDelta ≈ rightDelta ≈ 0
（±0.5）；image/gallery 应 ≈ 36 对称（Web margin 口径，由场景
按块型选期望式，探针只出数）。这正是截图二的人工像素量测
（左 16.3 / 右 25）的自动化形态——从「÷3 估算截图」升级为
「布局真值直读」。

**P2 `lift_gaps`（拾起态四边间隙）**：前置 = 目标块处于拾起
态（draggingId == blockId；来源可以是用户真机长按——助手侧
读 Diag 确认拾起后立即调探针，也可以是 U3 驱动拾起）。回：
行盒 frame、卡面 frame、框几何（由行盒 ⊕ Radius.liftInset
派生，与 LiftFrame 渲染同式）、四边间隙实测 = 面缘与框缘差：
left/top/right/bottom 四值 + 期望 4（每边，派生式给出）。判
读基线：四边两两差 ≤0.5（截图一的人工读数是右 11.5 vs 余
≈4，驱动口径下这类偏差无所遁形）。

**P3 `menu_panel`（••• 菜单面板高）**：前置 = 菜单打开。回：
`contentH`（ui.menuPanelH 实测回写值）、`renderedH`（面板注
册帧高）、`cap`（max(200, viewH−67) 现行上限式）、`capped`
（contentH > cap）。判读基线：未 capped 时 |renderedH −
contentH| ≤ 1；capped 时 renderedH == cap 且内容内滚（滚
动态不在探针面，只出三值）。截图四的「740 vs 272」在此口径
下是一次调用的三个数。

三探针共同纪律：量测前先过布局落定判据（§3.4 布局类）；量
测值标注坐标系与时刻；在席编辑器被用户切走/关闭时回
`surface_missing`，不回旧值。

### 4.3 S3 拖拽拾起回路（可行性评估）

**结论：分两半——拾起后的状态机与呈现可驱动、可断言；拾起
的触发（识别器仲裁）不可驱动、且恰是历史故障点，必须明示
不覆盖。**

可驱动面（评估 proven 到设计层）：DragPressAnchor 的四回调
本身就是纯 EditorModel 状态操作——onPickup 置 draggingId +
收敛选区 + 骑菜单、onDrag(dy) 喂 dragDy 与让位计算、onDrop
走 commitDrag 重排落盘、onCancel 复位。驱动按 §3.2 注册同一
组闭包后，可以：拾起指定块 → 断言 draggingId 与 `DRAG
pickup` 行 → 以合成 dy 步进（如 +30/+80）断言兄弟让位量
（dragShift 派生）与菜单收起（>10 自动收菜单）→ drop → 断
言块序变更 + persist 回读 + settle 收口 → 中途 cancel 路径
另跑一轮断言状态清零。拾起态顺带喂 P2 探针测间隙（S2/S3
在此合流）。

不可驱动面（结构性）：`DragPressEngine.gestureRecognizer
(shouldReceive:)` 的命中过滤、`shouldRecognizeSimultaneously`
的全并行豁免、0.48s/10pt 的识别器计时与失败路径——三轮拖拽
战（0.9.47/0.9.49）的故障全数出在这一层（识别器从未 began、
UITextView 内部识别器互斥强杀），驱动绕过识别器直调回调，
对这一层**零证据**。若把 S3 结果报成「拖拽已验证」就是重
演当年「代码级判修、真机仍败」的覆辙。

落地建议：U3 只落两件——(1) 上述状态机场景（命名
`drag_pickup_statemachine`，证据包 grades 里 `recognizer:
unknown（by construction）` 钉死）；(2) 真机轨迹复核补齐：
把桥方案 §5.6 的 `metrics_drag_trace` 补出货（DRAG 行归组
回读），形成「用户真机拖一次 → 助手回读全链行判完整性」
的固定收尾，与驱动场景互为补充。是否给引擎加「可编程喂
触点」的口子（向识别器发合成 touches）**明确否决**：那需
要构造 UIKit 事件或私有 API，违背 §3.2 口径且在本工具链/
签名形态下不可靠。

---

## 5. 隔离与安全

### 5.1 夹具卫生链（驱动只碰自建草稿）

- **创建**：场景开始先经 BridgeWriteSupport 取写前快照（与数
  据写同纪律，快照失败即中止、回 `snapshot_failed`），再由
  **App 内**调 `Library.create()` 建篇——注意这不经桥的
  `notes_create` 工具（正文级工具待加密评审的是「正文经中
  继传输」，夹具内容是 App 内置模板、不出设备、不经中继，
  与该裁定无冲突；模板文本在代码内写死，如长/短标题模板与
  若干段落/卡块规格）。
- **标记**：夹具篇在 App 内打驱动标记（标题前缀
  `「自检」` + runId 短哈希，且在 Library 层以进程内集合登
  记 fixture id 集）——双保险：肉眼可辨 + 程序只认登记集。
  驱动的一切写路径（开篇、改标题、删块、清理）先验目标 id
  ∈ 登记集，不在集内即拒（`fixture_guard`），**结构上够不到
  用户既有笔记**。
- **清理**：场景收尾（成功/失败/超时同路）固定执行：关编
  辑器 → `Library.softRemove` 夹具 → 立即
  `commitPendingDeletion` 真删（夹具是驱动自建、内容为模
  板，绕 8 秒撤销窗口的理由与 notes_delete_permanent 的受
  限形态同理：目标恒为待删集内自有夹具；此动作在 App 内
  发生、不经桥工具面）→ 回读断言夹具 id 在全集消失。
- **对账**：清理后断言 `libraryHash == 场景前哈希`（创建前
  快照所记）；不等 → 结果码 `hygiene_failed`（最高优先级
  报告，附前后哈希与夹具 id），且该次运行的其余结论一律降
  格为不可信——卫生没过，场景成绩不作数。
- **残留兜底**：进程在运行中被杀/崩溃时夹具可能残留——下
  次 App 启动时桥启动链顺手扫一遍：标题带自检标记且不在
  任何活动 run 中的篇，记 `UITEST fixture orphan id=…`
  行并列入 `app_state` 的一个计数（只报不删：删用户数据
  面不由启动链自动执行；由助手侧在下次会话以桥工具按受
  限形态处理，或用户手动删）。

### 5.2 并发门（用户正在用 App 时）

`uitest_run` 受理前逐项查（任一不过即拒，回码注明哪项）：

1. 场景态：App 处于前台 active（后台桥本就离线，此为双
  保）。
2. 在席编辑器：无在席编辑器，或在席的就是本 run 的夹具
  且未脏——用户正编辑真实笔记（尤其有未落盘改动）时回
  `device_busy`，绝不抢导航、不代保存。
3. 浮层静默：菜单/底表/面板类浮层无一打开（注册表状态读
  判读）。
4. 无其他 run 在跑（`driver_busy`）；桥未被 OPS 禁用、非
  只读态、非安全模式（§2.2/2.3 的门先行）。
5. 用户当次任务授权：uitest_run 属 ops 层 + 两段提交，
  沿桥方案 §7.3 口径——它不在「事前用户指令」清单内（不
  删真数据、不动启动状态），但场景库新增场景时须逐个评
  审其动作面，凡场景开始触及夹具以外对象即出局。

运行中用户介入的处置：每步开始前复查在席 memoId 与关键
状态位是否仍与场景预期一致（状态漂移检测）；用户手指操
作造成的漂移（切篇、开浮层、改焦点）→ 作业 `aborted_
user_active` 走复原链收尾，不与用户抢 UI。诚实标注：漂移
检测是步边界级（≤每步一次），不是逐帧抢占——用户在一步
之内点中夹具篇的概率窗存在但后果限于夹具篇自身，且复原
链会把夹具清掉。

### 5.3 失败复原要求（run 结束态定义）

任何非 ok 收尾必须回到「run 前呈现态」，复原链固定序：

1. 若驱动开过标题会话：按 Esc 口径还原草稿（titleBase 快
  照）并辞焦——不把半截草稿留给 commit 机会。
2. 关驱动开过的浮层（菜单等状态位复位）。
3. 若处于驱动拾起态：走 onCancel 复位（draggingId/dragDy
  清零、滚动锁恢复）。
4. 关驱动打开的编辑器（走 closeEditor 同路；夹具篇的保
  存与否无所谓，它将被清掉）。
5. 执行 §5.1 清理链 + 哈希对账。
6. 复原任一步失败 → 结果码 `restore_failed` 并在 Diag 记
  error 行逐项列明未复原项——这是唯一允许「带着状态结
  束」的码，且必须向用户报告，不许静默。

### 5.4 留痕与记账

- Diag 前缀 `UITEST`：`run begin run=<短> scenario=…`、
  每步 `step n=… kind=… ok=<0|1> ms=…`、断言失败
  `assert fail name=…`（warn）、夹具
  `fixture create/cleanup id=…`、卫生
  `hygiene hashMatch=<0|1>`、复原 `restore …`、收尾
  `run end run=<短> code=…`。只记元数据（id/哈希短形/
  计数/毫秒），**不记夹具正文以外的用户内容**（夹具标题
  模板本身可记，它不是用户数据）。
- 桥记账复用现行面：每次 uitest 工具调用走协调器
  `recordCall` 的 `BRIDGE tool …` 行；run 的写动作（建/
  删夹具）在 operations.jsonl 以 tool=`uitest_run` 记一
  条（target=夹具 id、pre/post 哈希），与数据写流水同账
  可查。
- 设置页桥「最近调用」列表天然覆盖 uitest 调用（同一
  recordCall 环），不另做呈现。

---

## 6. 证据分级口径（判读规矩，主线引用以本节为准）

总规矩（承桥方案 §8）：驱动结论逐项标 proven / inferred /
unknown；证据包 grades 字段是场景的**上限声明**，助手侧报
告只能引用、不能升级。驱动把可证面从数据层推进两格：

| 结论层 | 驱动可达等级 | 说明 |
|---|---|---|
| 数据与持久化（标题/块序/落盘/回读） | **proven** | 与 M2 语义工具同级（同一模型真源） |
| 焦点/编辑会话状态机（handler 以内：置焦→会话开始→提交→辞焦的循环） | **proven** | S1 的核心增量：0.9.53 事故类（置焦竞态、状态位残留）在此层可复现可证伪 |
| 布局几何（帧/间隙/面板高的数值关系） | **proven**（落定后量测） | 数字是 App 自身布局结果，与渲染同源；动画进行中的帧不在此列 |
| 呈现结构（某面在不在层级、截断覆盖层是否在位） | **proven** | 注册表状态读即结构事实 |
| 真实触摸命中投递（点得到/点不到、被谁吞） | **unknown** | 驱动不经命中链；仍靠真机手指 + Diag 三档判读（皆无=命中未达） |
| 手势识别器仲裁（长按拾起触发、并行豁免谁赢） | **unknown** | S3 结构性绕过；仍靠真机 + DRAG 全状态行 |
| 键盘呈现/光标落点/拼音组字 | **unknown** | 焦点状态机 proven 不外溢到此层 |
| 动画与体感（顺滑、跟手、弹簧） | **unknown** | 量测可证落点，不证过程手感 |
| 像素级栅格化（内角在真机呈圆那类机理 unknown 的呈现差） | **unknown** | 几何探针证 clip 形状与帧，不证栅格化像素；仍靠真机截图 |

逐场景落格：

- **S1**：stateMachine proven、persistence proven、
  hitDelivery unknown、keyboard unknown。报告措辞范式：
  「标题胶囊二次编辑的**状态机回路**经驱动 proven；用户
  手指点按能否到达入口仍以真机点按 + Diag 成对行终判
  （驱动已把后者的判读成本降为读两行）。」
- **S2**：geometry proven（落定量测）、rasterization
  unknown。范式：「留白/间隙/面板高的**布局数值**经探
  针 proven；内角的像素呈现仍以真机同位复拍终判。」
- **S3**：pickupStateMachine proven、geometry proven
  （拾起态间隙）、recognizer unknown（by construction，
  证据包钉死）。范式：「拾起后的状态与几何 proven；
  **长按能否拾起**不在本场景证据内，仍以真机拖拽 +
  metrics_drag_trace 归组行终判。」

---

## 7. 落地分期与改动面

### 7.1 分期清单

| 期 | 内容 | 前置 |
|---|---|---|
| **U0 地基**（与 M2 §7 接线批合并） | 根视图桥导航通道（memoId → pushEditor 同路打开/关闭）+ 在席 EditorModel 注册表（open 登记/close 注销 + memo_busy 判定源）；M2 在席四工具（editor_open/get_state/focus_block/save_now）与驱动共用此地基，其入册与断言归各自批 | M2 已落码（现状态） |
| **U1 驱动核 + S1** | MomentBridgeUITest.swift（注册表 + 锚点 + 引擎 + S1 + 夹具卫生链 + 并发/复原）；分发器四集合接线；EditorHeaderView 动作抽取（胶囊 tap/resign、••• toggle、返回 close 三处具名入口）；manifest 22→26、中继、连接器同步；verify [25] 首批断言 | U0 |
| **U2 几何探针** | 卡面 face 量测通道（BlockState 扩 faceMinX/faceW + 各卡面子视图回写）；菜单面板注册；uitest_measure + P1/P2/P3（P2 此时只能配合用户真机拾起用） | U1 |
| **U3 拖拽半面** | 行四回调注册 + `drag_pickup_statemachine` 场景（喂 P2）；`metrics_drag_trace` 补出货（清单 26→27，归 [16] 账）；S3 评估结论复核（是否到此为止，U2/U3 验收后裁） | U2 |

### 7.2 每期触碰文件与规模（估）

| 文件 | U0 | U1 | U2 | U3 |
|---|---|---|---|---|
| `MomentApp.swift` | 根视图接线 + 注册表挂点（~80 行） | EditorHeaderView 三处抽取 + 注册锚点（~120 行） | 卡面子视图 face 回写（~100 行，分散于各卡面） | DragPressAnchor 注册接线（~30 行） |
| `MomentBridgeUITest.swift`（新） | — | 主体（~700 行：注册表/锚点/引擎/S1/卫生链） | 探针实装（+~250 行） | S3 场景（+~150 行） |
| `MomentBridgeTools.swift` | — | 分发器集合 + 4 工具 case（~120 行） | measure case 并入 | metrics case（若归桥文件） |
| `MomentBridgeProtocol.swift` | — | 清单 +4 | — | 清单 +1（metrics_drag_trace） |
| `bridge/relay/worker.js` + 连接器 | — | TOOLS/scope/超时 + ALLOWED_TOOLS | — | 清单同步 |
| `build-app2.sh` / `push_small.py` | — | 新文件三处名单（文件名单/primary 编译遍/链接 .o）+ 传输名单 | 同步核对 | 同步核对 |
| `verify_ios.sh` | — | 新组 [25]（下节）+ [16] B16-3 清单同步 | [25] 扩探针项 | [25] 扩 S3 项 + [16] 同步 |

规模口径：U1 是主体期（约千行级，与 M1 一期相当）；U0 的
大头其实是 M2 §7 本来就要付的接线成本，驱动只是共用，不
重复计。MomentApp.swift 的改动全部落在编辑器呈现段与根
视图接线点，与「桥实现不堆主文件」的既有纪律一致——驱动
本体独立成文件，主文件只加注册锚点与动作抽取。

### 7.3 verify 断言（新组 [25]，与 [16] 的关系）

新增 **[25] 组「桥内 UI 自检驱动」**（不塞进 [16]：[16] 锁
桥的协议/授权/禁区，[25] 锁驱动的注册/门/卫生，分工清晰；
但两组有两处交叉引用，见末尾）：

- B25-1 文件与构建：MomentBridgeUITest.swift 在位且进
  build-app2.sh 三处名单与 push_small 名单（与 B16-1 同
  式）。
- B25-2 能力门：分发器含 `uiTestScopeTools` 四件集合与
  ops 门分支；`uitest_run` 在 `twoStageTools` 内。
- B25-3 受限集排除：`safeLimitedTools` 集合字面量与
  uitest 任一名交集为空（逐名查）。
- B25-4 单一来源：胶囊覆盖层 `onTapGesture` 的动作体只
  剩对具名入口的调用（旧内联「记行 + 置 true」字面在
  EditorHeaderView 段内只出现于入口定义处一份）；
  toggle/close 同式各一份。
- B25-5 注册点齐全：UITestAnchor 定义在位；titleCapsule/
  menuPanel/editor.view 三个注册 id 字面在位（U2/U3 期
  扩 face/block 注册 id）。
- B25-6 夹具守卫：驱动文件含 fixture 登记集校验与
  `fixture_guard` 回码；清理链三件（softRemove +
  commitPendingDeletion + 哈希对账）字面在位；
  `hygiene_failed` 回码在位。
- B25-7 禁区零触碰：驱动文件零 `UITouch` / `UIEvent(`
  构造、零 `performSelector` / 私有 API 特征串；零
  `exportZip(`（快照纪律同 B16 口径）；驱动对 Library
  的写调用只许 create/softRemove/commitPendingDeletion
  三个符号（白名单扫描）。
- B25-8 打点齐全：`UITEST run begin/step/assert fail/
  fixture/hygiene/run end` 模板行齐备（与 B16-4 同式）。
- B25-9 并发门：`device_busy` / `driver_busy` /
  `aborted_user_active` / `restore_failed` 四码在位且
  受理前检查序（安全/只读/OPS 门先于并发门）在位。

与 [16] 的交叉：① 清单变化时 B16-3 的逐名枚举必须同步
+uitest 四名（U1）与 +metrics 一名（U3）——在 [25] 里加
一条镜像断言盯 B16-3 的名集与 Protocol 清单差集为空，
防两组各说各话（即 M2 报告 §5 的 B16-15 三方一致口径扩
到四方：Protocol/中继/连接器/verify 名集）；② M2 报告
§5 待补的 B16-10…B16-16 与本组无重叠，仍归主线协调，
U 批不动它们。

### 7.4 冒烟与验收（每期）

- 照常 `smoke_ios.sh` 全量（tree）+ [25] 全绿才出包。
- U1 真机验收：桥连通后助手侧跑 S1 两遍结论一致；人为
  回退一版旧胶囊结构（仅测试构建）跑 S1 应红在步 5 且
  判读映射命中「只有 via 无 begin」——**驱动的验收标准
  是它能抓住原 bug**，不只是新代码下跑绿。
- U2 验收：P1 对留白批已修卡型回 0 差、对一块人为留
  +8 的测试构建回 ≈8；P3 在菜单修复前后两版各测一次，
  数值与截图量级对得上（272 级 vs 740 级）。
- 每期场景证据包留档进当期落码报告（与桥 M1/M2 报告同
  体例）。

---

## 8. 风险与未决点

1. **注册锚点的渲染开销**：UITestAnchor 仿 DragPressAnchor
   每 update 刷新注册——行级注册（U3）会给每行加一个 0 尺
   寸寄生视图，DragPressAnchor 已证此形态可行，但双锚点
   同行共存的开销要在 U3 冒烟时以 CREATE settle/滚动量测
   对照确认无回归；若有，行面注册改挂 DragPressAnchor 的
   同一锚点（合并注册回调）而非另起一个。
2. **@FocusState 的注册闭包新鲜度**：titleFocused 是视图
   本地 @FocusState，注册闭包靠 updateUIView 时机刷新；
   body 未重演算的窗口里状态读可能滞后一帧——S1 的权威
   判据因此定在 Diag 行（入环即事实）而非状态读，状态读
   只作辅助（已在 §4.1 步 5 如此设计）。
3. **驱动与 OPS guard 的关系**：OPS 可禁桥（OpsStep.
   bridge）已覆盖驱动（桥不启则驱动不在）；是否给驱动单
   独的 OpsStep 步名（可单独禁驱动不禁桥）——建议 U1 不
   加（少一个步名少一份三方对账），若日后出现「桥要留、
   驱动要停」的真实场景再加。
4. **场景库增长的评审纪律**：每个新场景 = 新的设备动作
   面，上线前按 §5.2 第 5 条逐个评审并同步 CONNECTOR.md
   的场景清单；场景只许碰夹具的红线不因场景增多而松动。
5. **与 M3 的信封合并时点**：若 M3 先于 U2 落地，U2 起
   的证据包格式向 M3 的场景证据包看齐合并（字段同名同
   义），避免助手侧两套解析；U1 先行则反之。合并只动格
   式层，不动各自结论口径。
6. **未决：uitest_measure 是否单开同步工具**——本文按
   单开设计（探针是高频轻量读，塞进 run 作业信封会让
   「读个数」也要走两段提交+轮询，得不偿失）；若主线倾
   向工具面收敛，可降级为 uitest_run 的一个内置「场景」
   `probe_only`，代价是每次量测都建/清夹具（探针并不需
   要夹具）。留主线裁。
