# 桥 M3（场景库）实施方案

> 状态：**方案稿，未落码。** 基线事实：M1（11 件只读）已出货并真机接通
> （0.9.52 实测）；M2（清单 22 件）已落码、随 0.9.54 组版与中继 redeploy
> 同批生效；U 批（桥内 UI 自检驱动）方案已出（plan_ui_selftest_driver.md）、
> 未落码。当前设备配对 scopes = **read + ops**（write 未授）。
>
> 本方案只覆盖 M3 的**场景库**部分（`scenarios_list / scenarios_run /
> scenarios_get_result` 与场景引擎）。M3 名下的其余交付——桥运维命令四件
> （原方案 §6.2b）、`backup_restore_snapshot`（§9.3）、`rescue_clear_caches`
> （待 R3）/ `rescue_open_readonly`（待 R2）、OPS 源头发布 runbook——按原方案
> 口径继续有效，本文只在与场景的依赖/排期关系处引用，不重复设计。
>
> 与 U 批的关系（按任务钉子 + U 方案 §2.4 对齐）：**场景可单向调用驱动**
> （`scenarios_run` 的场景可把一次 `uitest_run` 作子步），**驱动不依赖场景**；
> 两者共用异步作业信封与 U0 地基，互不阻塞。

---

## 0. 结论先行

1. **执行位置裁定：场景库内置于 App**（编译期场景注册表 + App 内引擎 +
   本地 run 日志），`scenarios_run` 异步作业模型沿用原方案 §3.3。连接器侧
   只保留 runbook 级编排（OPS 源头发布、safe_mode_drill 的安全模式外腿），
   中继侧不放任何场景逻辑。裁定理由见 §3——决定性一条：**写场景的夹具
   必须在 App 内建（正文不出设备），连接器/中继编排绕不开被冻结的
   `notes_create`**。
2. **首批场景 10 个、分三期**（§2）：M3a 引擎 + 只读/低危四景；
   M3b 写场景四景（依赖 §7 接线批与 write 重配对）；M3c 运维打通两景
   （依赖桥运维命令与 R2/R3 前置）。
3. **能力门 = 场景声明制**：每场景在注册表声明 `requiredScopes`，
   `scenarios_run` 受理时一次验足（缺层回 `scope_denied` 并点名）；
   含高危段的场景整场入两段提交；`scenarios_list` 按当前配对与启动
   模式逐景回可用性，**不可用的场景在清单里就现形，不等跑起来才拒**。
4. **正文红线写成禁令**（§5.3）：加密专项评审（原方案 §12.1 / 附录 B.3）
   结论落地前，任何场景不得直接或间接开放正文级四件工具；场景参数
   只许标量/id/哈希，夹具正文只许 App 内置模板，证据包不载正文。
   此禁令有 verify 断言守（§7 B27-4）。
5. **跨重启挂起是引擎的一等状态**：`ops_convergence` 与
   `safe_mode_drill` 天然跨「用户手动重开」边界，run 状态落盘为日志
   （journal），新启动/模式翻转时自动续跑收尾——这是只有 App 内置
   形态能成立的形态，也是裁定的一条硬依据。

---

## 1. 事实基线（方案落点，只写已落地事实）

### 1.1 已落地工具面（22 件，M2 口径）

- 只读/控制（现配对 read+ops 可用）：`bridge_status`、`app_state`、
  `diag_tail`、`diag_search`、`notes_list`、`notes_search`、`notes_get`、
  `ops_get_effective`、`ops_get_sources`（中继侧执行）、`ops_refresh`
  （ops）、`ops_validate`、`rescue_status`、`settings_get`。
- write 层 7 件（现配对未授、回 `scope_denied`，须用户重配对勾选
  write）：`settings_set_language`、`settings_set_toggle`、
  `settings_clear_weather_key`、`notes_soft_delete`、
  `notes_restore_deleted`、`editor_delete_block`、`editor_move_block`。
- ops 高危 2 件（两段提交）：`notes_delete_permanent`（仅待删集内 +
  `confirmMemoId` 逐字）、`rescue_try_normal_start`（仅安全模式）。
- 写安全底座已在位：`BridgeWriteSupport`（写前快照直调只读 FFI
  `exportBackup` → `Application Support/bridge-snapshots/`、幂等回放、
  operations.jsonl 流水、docHash 守卫 + 写后回读）。场景引擎的写步
  复用它，不另起底座。
- 安全模式受限集已按原方案 §9.6 扩为 8 件（M2 落码）；场景三件
  **不在**受限集内（§5.4）。

### 1.2 尚未落地的相关面（场景的依赖账）

| 缺口 | 状态 | 影响场景 |
|---|---|---|
| 正文级四件（`notes_create` / `editor_insert_block` / `editor_update_block` / `editor_set_block_type`） | **冻结**：待端到端加密专项评审（§12.1/B.3），三方清单均无 | 场景不得依赖；夹具一律 App 内建（§5.3） |
| 编辑器在席四件（`editor_open` / `editor_get_state` / `editor_focus_block` / `editor_save_now`）+ `memo_busy` | 未落：缺桥导航通道 + 在席 EditorModel 注册表（M2 报告 §7.1）——即 U 批的 **U0 地基**，同批还有 `rescue_arm_safe_mode` 的布防消费点（§7.3） | `create_transition`、`drag_semantic_reorder`、`safe_mode_drill` |
| 量测两件（`metrics_create_settle` / `metrics_drag_trace`） | M1/M2 均顺延未出货；U 批 U3 计划补 `metrics_drag_trace` | 两景的解析先在引擎内直读 Diag（与工具共用同一解析器、单一来源）；`metrics_create_settle` 建议随 M3a 顺手补出（§6） |
| `DocumentMutationService` 抽取 | 未做（M2 §7.4）；正文工具解禁时才需要 | M3 不依赖（场景结构写只用已落地的删/移同路） |
| `backup_restore_snapshot` | 未落（原方案 §9.3 已设计） | `snapshot_restore_drill`（M3b 随工具同批） |
| 桥运维命令四件、R2 只读打开、R3 缓存清理 | 未落 | `ops_command_drill` 等（M3c） |

### 1.3 可复用的既有机制（引擎不新造口径）

- **异步作业信封**：原方案 §3.3 已定 `scenarios_run` 立即回 `runId`、
  `scenarios_get_result` 轮询；证据包四件套（工具结果 / 状态回读 /
  Diag 行 / 证据等级）由原方案 §8 第 4 条钉死。U 批 §3.4 已把该信封
  结构化（runId/scenario/code/steps[]/measurements/grades）——M3 晚于
  U1 落地，**证据格式向 U 信封看齐**（U 方案 §8.5 的合并规则：后落
  者向先落者对齐，只动格式层）。
- **夹具纪律**：U 方案 §5.1 已立（App 内建模板、双标记、登记集、
  软删+真删清理链、libraryHash 前后对账、卫生不过全场降格）。M3 与
  U **共用同一夹具登记集与孤儿清扫口径**（§4.3），不各造一份。
- **分发器门形态**：能力门集合字面量 + 执行前拦截、两段提交
  `twoStageTools`（dryRun 发一次性 actionToken、绑工具名+参数哈希、
  60 秒）、数据写前置门（`library_unavailable` / `read_only_mode` /
  `ops_disabled`）均已在 `BridgeDispatcher` 落地，场景门接同一形态。

---

## 2. 场景清单（首批 10 景，分三期）

场景描述符（注册表条目，`scenarios_list` 回读源）：

```text
ScenarioDescriptor {
  id: String                 // 稳定 id（下表）
  requiredScopes: [String]   // read / write / ops 的子集，run 受理时一次验足
  containsHighRisk: Bool     // true → scenarios_run 整场入两段提交
  requiresUserDirective: Bool// true → 含 §7.3「事前用户指令」段（程序纪律，见 §5.2）
  phases: single | crossRestart
  fixture: none | template   // 是否建夹具（模板名）
  grades: { ... }            // 证据等级上限声明（原方案 §8，报告不得升级）
}
```

可用性由 `scenarios_list` 按当前（scopes、bootMode、库状态、接线
是否在位）逐景计算：`available | scope_missing(<层>) |
wiring_missing | safe_mode_limited | library_unavailable`。

### 2.1 M3a（引擎 + 只读/低危，现配对即可跑或只差 ops）

| 场景 | scopes | 形态 | 一句话 |
|---|---|---|---|
| `drag_trace_review` | read | 单会话、无夹具 | 用户真机拖一次后回读 DRAG 归组行判链路完整性 |
| `weather_settings_flow` | read | 单会话、无夹具 | 天气 key 状态前后回读 + 内部触发刷新验状态迁移 |
| `ops_convergence` | ops | **跨重启**、无夹具 | OPS 三步确认链自动化（拉源→刷新→挂起→重开后续验 bootApplied） |
| `language_roundtrip` | write | 单会话、无夹具 | 切语言→验生效码→切回（现配对缺 write，清单里标 scope_missing） |

**`drag_trace_review`**
- 输入：`sinceTs?`、`blockId?`、`limit?`（均可选过滤）。
- 步骤：引擎内直读 `DiagLog` 的 DRAG 行 → 按事件归组（engine
  attached → press target/reject → press 全状态 → pickup →
  converge/menu → drop/cancel）→ 链路完整性判定（成链/缺环点名）→
  附原始行。`metrics_drag_trace`（U3）出货后，归组解析切到与工具
  同一解析器（单一来源），本景步骤不变。
- 失败回滚：纯读，无回滚面；无 DRAG 行时回「窗口内无拖拽记录」
  的空结论，不判失败。
- 证据回传：归组链 + 原始行 + 完整性判定。等级：行在 = proven
  到打点层；手感/仲裁过程 unknown（原方案场景表既定口径）。

**`weather_settings_flow`**
- 输入：无（可选 `provider` 过滤）。
- 步骤：`settings_get` 同路前读（双 key 的 state/source）→ 引擎内
  调 `WeatherService` 既有刷新路径触发一次刷新 guard 点（key 值
  不经桥、不入参数）→ 等天气 Diag 行/状态迁移落定 → 后读对比。
- 失败回滚：无数据写；刷新失败（如彩云免费额度耗尽、网络失败）
  如实回失败签名并区分结论——「状态回读链 proven」与「本次刷新
  是否成功」分开判，不因外部额度把整场判红。
- 证据回传：前后 settings 摘要 + 天气 Diag 行；**任何字段不含
  key 值/哈希/指纹**（沿 settings_get 既定口径）。

**`ops_convergence`**
- 输入：`expectedHash?`（可选；不给则以 App 内现拉双源为准）。
- 步骤：① 引擎内直拉双源（与 `OpsDirectives.fetchFrom` 同
  sanitize 口径，origin 标 `app`；中继侧 `ops_get_sources` 仍可
  由助手并行旁证）→ 与 currentCache 对比；② 走 `ops_refresh`
  内部同路刷新，校验 `OPS directives fetched` Diag 行与成功源；
  ③ journal 置 `awaiting_manual_reopen` 挂起并落盘，run 回到此
  即返回挂起态；④ 用户下次启动后，桥启动链扫 journal 自动续跑：
  读 `bootApplied` 哈希与源头哈希比对 + `converged` + LAUNCH 行
  回读 → 收尾关单。
- 失败回滚：刷新只写 OPS 缓存（既有语义，非数据面），无回滚
  面；挂起超 7 天自动过期关单（journal 清扫），结论标 expired。
- 证据回传：三层（源头/缓存/bootApplied）哈希对照表 + fetched
  行 + LAUNCH 行。等级：proven 到 bootApplied 哈希一致（三步
  缺一环只能报到实际到达环，沿 §6.1 固定读法）。

**`language_roundtrip`**
- 输入：`code`（五语码之一；缺省取 zh-CN），收尾固定切回原码。
- 步骤：前读偏好/生效码 → `settings_set_language` 内部同路切
  目标码 → `app_state` 同路验生效码 → 切回原码 → 再验。
- 失败回滚：任一步失败立即尝试切回原码；切回亦失败 → 证据包
  红标 `language_left_changed` + 当前码，提示用户在设置页手动
  切回（不静默留改动）。
- 证据回传：三段生效码回读 + `BRIDGE write` 行。等级：proven
  到偏好与解析层。

### 2.2 M3b（写场景；前置 = §7 接线批落地 + write 重配对）

| 场景 | scopes | 形态 | 一句话 |
|---|---|---|---|
| `delete_restore_roundtrip` | write（永删段另 +ops/两段/用户指令） | 单会话、夹具 | 软删→窗口内恢复→再软删→窗口后确认真删 |
| `drag_semantic_reorder` | write | 单会话、夹具 | 多块夹具语义重排→回读→重开再回读 |
| `create_transition` | write | 单会话、夹具 | 经「+」同路新建打开，解析 CREATE settle 对基线 |
| `snapshot_restore_drill` | ops + 两段 + 用户指令 | 单会话、夹具 | 快照→变更→恢复→verifyStore 对账（随 `backup_restore_snapshot` 工具同批） |

**`delete_restore_roundtrip`**
- 输入：`includePermanent?: Bool`（默认 false；true 时永删段启
  用，整场转两段提交且该段须事前用户指令）。
- 步骤：建夹具（内置空模板篇）→ `notes_soft_delete` 内部同路
  软删 → **恢复守卫**：回读待删集，确认最近一篇 id == 夹具 id
  才调恢复（`undoDeletion` 只认最近一篇——用户若在场景间隙软
  删了自己的笔记，恢复目标会被抢，守卫不过即中止该段并降格
  收尾，绝不替用户恢复错篇）→ 恢复后回读 docHash → 再软删 →
  场景内等 8 秒窗口过 → 回读全集确认真删 →（可选）永删段：
  另一夹具软删后走 `notes_delete_permanent` 内部同路
  （confirmMemoId 由引擎以夹具 id 一致回带，强制单独快照沿
  工具既定纪律）→ 卫生对账。
- 失败回滚：中途失败走夹具清理链（仍在窗口则恢复后清理、已
  真删则只剩对账）；快照底座兜底全程。
- 证据回传：每步 deletedAt/undoExpires/docHash、待删集回读、
  前后 libraryHash。等级：数据/持久化 proven。

**`drag_semantic_reorder`**（依赖 U0：重开腿走桥导航通道）
- 输入：无（夹具块构成由模板定：≥4 块、多类型、纯结构块 +
  模板文本块——文本为 App 内置模板，不经中继，见 §5.3）。
- 步骤：建多块夹具 → 记初始块序（id+type 序列）→
  `editor_move_block` 内部同路执行两次移动（首块→尾、中间
  两块互换）→ `notes_get` 同路回读块序逐字断言 → 关编辑器
  → `editor_open` 内部同路重开 → 再回读块序 → 清理对账。
- 失败回滚：块序断言失败即停、清理夹具；写前快照兜底。
- 证据回传：三段块序对照 + docHash 链。等级：语义序与持久
  化 proven；真实拾起/识别器 unknown（注明，不在此景证据内）。

**`create_transition`**（依赖 U0：与「+」钮同一导航路径）
- 输入：无。
- 步骤：经 U0 导航通道走新建并打开（内部 create + pushEditor
  同路）→ 等 `CREATE settle` 行落定 → 引擎内解析各段
  （create/model/dest/appear/claim/kb、listpass 趟数与 ms、
  avatar ms、bodypass 轮数）→ 与基线阈值表比对（阈值 = 场景
  内置常量，来源注明为既往真机量测基线、随版本修订）→ 关
  编辑器 → 清理夹具 → 卫生对账。
- 判定分级：settle 行缺失/超时 = 场景失败；分段超阈 = 结论
  `degraded` 并逐段列明（不整场判红，判读归助手侧结合当版
  背景）。`metrics_create_settle` 随 M3a 补出后，解析切到共用
  解析器（单一来源）。
- 失败回滚：清理链 + 对账。
- 证据回传：settle 原始行 + 分段解析表 + 阈值对照。等级：
  数据/状态层 proven；顺滑体感 unknown。

**`snapshot_restore_drill`**（随 `backup_restore_snapshot` 同批）
- 输入：无（恢复目标恒为本景触发的快照，id 由引擎内定，不
  接受桥传 snapshotId——防把恢复面变成任意回滚入口）。
- 步骤：建夹具 → 一次夹具写触发快照（记 snapshotId 与
  libraryHash A）→ 再变更夹具（删块/软删）记 hash B（须 ≠A）
  → **恢复守卫**：执行前校验当前 libraryHash == B（即快照后
  除本景外无任何变更——恢复是全库替换语义，用户在演练间隙
  的真实编辑也会被回滚，守卫不过坚决拒跑）→ 调
  `backup_restore_snapshot` 内部同路（恢复前强制再快照、
  清单/zip 校验、FFI importBackup 换库、reload、verifyStore
  对账）→ 断言计数/哈希与快照清单一致、夹具回到 A 态 → 清
  理对账（清理在恢复后的库上执行）。
- 失败回滚：恢复前快照即回滚路（可再恢复回 B 态，须用户指
  令）；守卫不过不执行、无回滚面。
- 证据回传：快照清单 vs verifyStore 对账表 + 三段哈希
  （A/B/恢复后）。等级：持久化 proven。

### 2.3 M3c（运维打通；前置 = 桥运维命令落地，R2/R3 项各自前置）

| 场景 | scopes | 形态 | 一句话 |
|---|---|---|---|
| `safe_mode_drill` | ops + 两段 + 用户指令（布防段） | **跨模式**、无夹具 | 布防→人工重开→受限面自检→尝试正常启动→留痕回读 |
| `ops_command_drill` | ops + 两段 + 用户指令 | 跨重启（可选段） | 桥运维命令 签发→投递→状态→撤销 全链演练 |

**`safe_mode_drill`**（依赖 §7 接线批的 `rescue_arm_safe_mode` 消费点）
- 步骤：① `rescue_arm_safe_mode` 内部同路布防（标记格式按
  M2 §7.3 定案：`diag/bridge-safe-mode-arm.json`）→ journal
  置 `awaiting_manual_reopen`；② 用户重开进安全模式后，**安
  全模式内的自检腿是助手侧编排**（引擎在安全模式不执行，
  §5.4）：助手以受限集工具逐个调 bridge_status / app_state /
  rescue_status / diag_tail 并记录；③ 助手调
  `rescue_try_normal_start`（ops + 两段）回正常模式；④ 模式
  翻转回 normal 后引擎续跑收尾：回读 arm 消费留痕、RESCUE
  via=bridge 行、`lastRescueAction`、哨兵状态 → 关单。
  forceSafeMode 仍在位时，续跑段如实标「下次启动仍回安全
  模式」（沿 try_normal 的既定回读口径，不报假成功）。
- 失败回滚：try_normal 本身即回滚路；布防标记被消费一次后
  转审计留痕（既定口径），无残留强制。
- 证据回传：布防/消费/RESCUE 行 + lastRescueAction + 两段
  bootMode 回读。等级：启动状态机 proven 到留痕层。

**`ops_command_drill`**（依赖桥运维命令四件先落地）
- 步骤：`ops_command_preview` 内部同路预检（点名对象选对当
  前验证无影响的非核心步）→ `ops_command_issue` 签发短 TTL
  命令 → `ops_command_status` 回读投递态 →（可选段）用户
  重开后验合并口径：LAUNCH 行 `bridgeOps=` 摘要 +
  bootApplied ∪ 命令的生效回读 → `ops_command_revoke` 撤销
  → status 再读确认失效。
- 失败回滚：revoke + TTL 到期双兜底；命令只能收紧不能放松
  （既定口径），演练命令到期自动失效。
- 证据回传：BRIDGEOPS 全程行（issued/applied/revoked/
  expired）+ status 三态对照。等级：运维链 proven 到留痕层。

**M3c 条件项**（不单列场景，随 R2/R3 工具落地各补一条简景）：
`rescue_open_readonly` 落地后给 `safe_mode_drill` 加只读打开
腿；`rescue_clear_caches` 落地后补 `cache_clear_drill`（清前/
清后字节数回读，清单与 S7 逐字一致）。两项均 ops + 两段 +
用户指令。

---

## 3. 存放与执行位置裁定

### 3.1 三候选逐项比较

| 维度 | App 内置（编译期场景库） | 连接器侧编排（helper/助手逐调用拼） | 中继侧执行（Worker 内脚本） |
|---|---|---|---|
| 跨重启/离线韧性 | run 状态与证据都在设备本地 journal；断线、App 被杀、用户隔天重开都能续跑/回读 | 每步都是实时往返；连接断、对话结束、App 重启即丢场景中态，跨重启景（convergence/drill）**无处挂起** | DO 可存中态，但 App 重启后仍靠 App 侧配合，且状态真源与证据真源分离 |
| 正文加密裁定的影响 | **零影响**：夹具正文是 App 内置模板、永不出设备；参数只标量/id/哈希；评审未落地前即可出货 | **致命**：建夹具必须走 `notes_create`（正文经中继）——要么等评审、要么逼出例外，两者都不可接受 | 同左列问题：命令下发仍要把正文参数送进 App |
| 无工具步骤的覆盖 | 可直调内部服务（天气刷新触发、夹具建篇、settle/DRAG 内部解析） | 只能拼已有工具；无工具的步骤（刷新触发、内部解析）拼不出来 | 同连接器侧，且 Worker 无从调 App 内部服务 |
| 版本耦合 | 场景随 App 版本走（回归库本就该与被测版本同版）；清单哈希使版本现形 | 迭代最快，但「场景」实际是助手每次临场拼序列——不可复现、不可审计，不是库 | 最差：中继是线上部署单元，为改场景要动部署面，三方耦合 |
| 证据组装 | 证据在源头组装（Diag 直读、哈希直算），四件套一次成型 | 证据散在多次调用结果里，靠助手事后拼，缺环不自知 | 证据须从 App 回传后在中继拼，违背「证据真源在 App」 |
| 中继纪律 | 不动中继（只加 TOOLS 名单与门） | 不动中继 | **破坏「中继零业务存储/零业务逻辑」既定纪律**，否决 |

### 3.2 裁定

**场景库内置于 App**，新增独立文件 `MomentBridgeScenarios.swift`
（引擎 + 注册表 + 场景实装；分发器仍在 MomentBridgeTools.swift，
沿「拒绝上帝文件」与 U 批 MomentBridgeUITest.swift 的先例）。

两条例外（不是场景、是编排，留在助手侧并写入 CONNECTOR.md）：

1. **OPS 源头发布 runbook**（原方案 §6.2a 既定）：ops_validate
   预检 → Cloudflare/GitHub 既有授权改源 → 回桥确认链。它用的
   是源头侧授权、每次须用户当次指令，形态上就不该是 App 工具
   或 App 场景。
2. **safe_mode_drill 的安全模式内自检腿**（§2.3）：安全模式下
   引擎不执行，该腿由助手以受限集工具逐个调用完成，场景
   journal 只记「外腿待检/已检」状态位，证据由续跑段回读
   Diag/留痕补齐。

与 U 批的组合方向按钉子执行：M3 场景可把一次 `uitest_run`
作子步（如将来的组合回归景），经引擎内直调驱动入口（不经
中继往返）；驱动永不反调场景。此组合是 M3 落地后的增量，
不进首批 10 景。

---

## 4. 引擎设计要点

### 4.1 注册表与步骤模型

- 场景 = 编译期注册条目（描述符 + 步数组），步类型封闭集：
  `callInternal`（调已有工具的**内部实现函数**——即分发器
  case 背后同一函数，不经中继往返、不重复过门，门在 run 受
  理时按描述符一次验足）、`invokeService`（调内部服务：天气
  刷新、夹具建篇、导航通道）、`waitDiag`、`assert`（关系式，
  读已回读的状态/哈希/块序）、`suspend`（置挂起态结束本段）、
  `measureInternal`（settle/DRAG 内部解析）。**不接受桥上传
  任意步序列/代码/方法名**（与 U 批 §2.1 同一安全基线）。
- 步失败 = 场景失败（非引擎错误）：停步、走收尾链（夹具清理
  + 对账）、证据照常回全。引擎错误（journal 写失败等）单独
  回码，不与场景结论混。

### 4.2 run 日志（journal）与跨重启续跑

- 落点：`Application Support/bridge-scenarios/runs.json`（与
  快照同域、独立目录；不进用户备份 ZIP、不进 Diag 域）。
  每 run 一条：runId、scenarioId、参数哈希、状态机
  （running / awaiting_manual_reopen / done / failed /
  aborted / expired）、步游标、夹具 id 集、pre/post
  libraryHash、证据包累积体、创建/更新时间。
- 续跑触发两路：① **新启动**——桥启动链（Library.init 尾异步
  派发处，与协调器同点）扫 journal，对 awaiting 且续跑条件
  满足（bootSessionId 已变、bootMode 与场景预期相符）的 run
  在库就绪后自动续跑收尾段；条件不符（如 drill 预期安全模式
  却正常启动）→ 标 failed 并注明原因，证据保留待回读。
  ② **进程内模式翻转**——`safe_mode_drill` 的 try_normal 在
  同进程把 bootMode 翻回 normal 并完成常规加载后，由该动作
  的完成点通知引擎续跑。
- `scenarios_get_result` 只读 journal 组装证据包（进程重启后
  仍可回读最近 run——比 U 驱动的进程内留存更强，这是跨重启
  景的必需口径）；journal 保留最近 10 个 run，超限清旧
  （Diag 记一行）。
- 引擎串行：同一时刻只跑一个 run（与驱动共用互斥——有
  uitest run 或 scenario run 在跑时，新 `scenarios_run` 回
  `run_conflict`）。单 run 总时长上限：单会话景 120 秒硬顶；
  跨重启景的挂起段不计时（靠 7 天过期兜底）。

### 4.3 夹具与卫生（与 U 共用一套）

- 夹具登记集与孤儿清扫**与 U 批共用同一实现**（登记文件同
  放 `bridge-scenarios/` 域）：谁先落地谁建，另一方复用——
  按 §6 排期 U1 在前，由 U1 建、M3 复用；若排期翻转则反之，
  落码报告须注明归属。场景的一切写步先验目标 id ∈ 登记集，
  不在集内回 `fixture_guard` 中止——**结构上够不到用户既有
  笔记的写面**。
- 清理与对账沿 U §5.1：关编辑器 → 软删 → 立即真删 → 回读
  消失断言 → libraryHash 前后对账；卫生不过回
  `hygiene_failed` 且全场结论降格。
- 写前快照沿数据写纪律：run 内首个写步前经
  BridgeWriteSupport 取一份（reason 记 scenario id），
  operations.jsonl 以 tool=`scenarios_run`、target=夹具 id
  记账，与工具写流水同账可查。

### 4.4 Diag 打点

新增前缀 `SCENARIO`（只记元数据，不记正文/参数全文）：
`run begin run=<短> scenario=…`、每步 `step run=<短> n=…
ok=<0|1> ms=…`、`suspend run=<短> phase=…`、`resume
run=<短> via=<boot|modeflip>`、夹具 `fixture create/cleanup
id=…`、卫生 `hygiene run=<短> hashMatch=<0|1>`、收尾 `run
end run=<短> code=…`。工具调用本身仍走协调器 recordCall 的
`BRIDGE tool …` 行。

---

## 5. 能力门与安全

### 5.1 scope 归属总表

| 工具 | 门 |
|---|---|
| `scenarios_list` | read（只回描述符与可用性，不回任何笔记内容） |
| `scenarios_get_result` | read（证据包只含 id/哈希/计数/Diag 行/量测，不含正文——见 §5.3） |
| `scenarios_run` | **场景声明制**：受理时验 pairing scopes ⊇ 描述符 `requiredScopes`，缺层回 `scope_denied` 并在 details 点名缺哪层与哪景；另过数据写前置门（库/只读/OPS 禁桥）与引擎互斥门 |

现配对（read+ops）下的可用面如实标注：M3a 四景中
drag_trace_review / weather_settings_flow / ops_convergence
可跑；language_roundtrip 与全部 M3b 写景须用户先重配对勾选
write——**这是排期前置（用户动作），不是代码缺口**，方案与
交付报告都须明示，不得把 scope_denied 包装成故障。

### 5.2 两段确认与事前用户指令的继承

- **两段提交**：描述符 `containsHighRisk == true` 的场景，
  `scenarios_run` 整场入分发器 `twoStageTools`（dryRun 取
  actionToken，绑 `scenarios_run` + 场景 id + 参数哈希，60
  秒）。首批中标：`snapshot_restore_drill`、
  `safe_mode_drill`、`ops_command_drill`、以及
  `includePermanent=true` 的 `delete_restore_roundtrip`。
  场景内含的两段工具（permanent、try_normal、restore、
  ops_command_issue）不再逐个取令牌——场级令牌即其继承形
  态，内部步以场级令牌上下文执行并在证据包逐项列明。
- **事前用户指令**：含 §7.3 清单段的场景（布防、永删段、
  快照恢复、运维命令签发）在描述符标
  `requiresUserDirective: true`，`scenarios_list` 与
  CONNECTOR.md 场景目录都现形此标记。此约束的执行者是助手
  侧纪律（App 无从验用户意图）——与原方案 §7.3 对
  rescue_arm_safe_mode 等工具的口径一致：**App 强制的是
  scope + 令牌，用户指令由助手按标记逐景把关，标记让这件
  事机器可见、不靠记忆**。
- 场景不得放大任何工具的既有限制：恢复只认最近一篇的守卫
  （§2.2）、永删只认待删集内、快照恢复只认本景快照——逐条
  写进场景步骤，引擎不提供绕过口。

### 5.3 正文红线（禁令，明文钉死）

> **禁令**：端到端加密专项评审（原方案 §12.1 / 附录 B.3）结
> 论落地并写回桥方案之前，任何场景不得直接或间接使正文级
> 四件（`notes_create`、`editor_insert_block`、
> `editor_update_block`、`editor_set_block_type`）被调用、
> 被注册进清单、或以等价旁路被实现。具体含三条：
> ① 场景步不得直调文档变更内核去写入**由中继传入的**正文
> 内容（参数面禁正文，见下）；② 夹具正文只许 App 内置模板
> （代码内写死），其生成在设备内完成、永不经中继；③ 证据
> 包不得回传笔记正文（块级验证在 App 内完成，只回 id/type
> 块序、计数与哈希——与已落地 editor_delete_block /
> editor_move_block 的回包口径一致）。
>
> 配套参数面纪律：`scenarios_run` 的 params 只许场景声明的
> 标量（布尔、枚举、时间戳、id、哈希），注册表逐景声明参数
> 表，表外键一律 `invalid_params`；**任何场景的参数表不得
> 出现 text/blocks/runs 类正文键**（断言守，§7 B27-4）。
>
> 注记：`notes_get` 正文回读是 M1 已出货口径，与本禁令的关
> 系（评审时是否一并收口）留评审定夺——场景层不新增正文
> 暴露面即不扩大既有口径。

### 5.4 安全模式与只读态

- 安全模式下场景三件**全部**回 `safe_mode_limited`（不入
  M2 已定的 8 件受限集）：引擎的前提（库开、夹具写、内部服
  务）与安全模式定义相斥；`safe_mode_drill` 的安全模式内自
  检腿按 §3.2 例外由助手侧编排完成，不构成引擎在安全模式
  执行。只读打开态（R2 后）下 `scenarios_run` 回
  `read_only_mode`；list/get_result 可回（纯读 journal）。
- OPS 点名禁桥（`OpsStep.bridge`）时桥不启动，场景面自然
  不在位——沿既定 kill switch 口径，不另设场景级步名。

---

## 6. 与 U 批的时序与分期排期

### 6.1 逐景依赖表

| 场景 | 依赖 U0（§7 接线） | 依赖 U1/U2/U3 | 其他前置 |
|---|---|---|---|
| `drag_trace_review` | 否 | 否（U3 的 metrics_drag_trace 出货后切共用解析器，非前置） | 无 |
| `weather_settings_flow` | 否 | 否 | 无 |
| `ops_convergence` | 否 | 否 | ops scope（已有） |
| `language_roundtrip` | 否 | 否 | **write 重配对（用户动作）** |
| `delete_restore_roundtrip` | 否 | 否（夹具登记集与 U 共用，谁先谁建） | write 重配对 |
| `drag_semantic_reorder` | **是**（重开腿 + memo_busy） | 否 | write 重配对 |
| `create_transition` | **是**（「+」导航通道） | 否 | write 重配对 |
| `snapshot_restore_drill` | 否 | 否 | `backup_restore_snapshot` 工具同批落地 |
| `safe_mode_drill` | 同批（arm 消费点在 §7 接线批） | 否 | ops（已有） |
| `ops_command_drill` | 否 | 否 | 桥运维命令四件（M3c 本体） |

**没有任何首批场景依赖 U1/U2/U3 的驱动本体**——驱动与场景
是同地基（U0）上的两棵树；组合（场景调 uitest 子步）是双
方都落地后的增量，不进首批。

### 6.2 分期与建议排期位置

排期链（承 U 方案 §2.4/§7.1 与现行队列）：

```text
0.9.54 组版（M2 生效）
  → §7 接线批 = U0（导航通道 + 在席注册表 + 在席四件入册
    + rescue_arm_safe_mode 入册 + memo_busy）
  → U1（驱动核 + S1）
  → M3a（引擎 + 四景 + metrics_create_settle 补出）
  → U2（几何探针）
  → M3b（写景四景，含 backup_restore_snapshot）
  → U3 ∥ M3c（拖拽半面 / 运维命令 + 两景 + R2/R3 条件项
    + OPS 发布 runbook 入 CONNECTOR.md）
```

- M3a 排在 U1 之后的理由：两者同动分发器与清单
  （MomentBridgeTools.swift / Protocol / 中继 TOOLS / 连接器
  名单），串行落地免清单合并冲突；且证据信封按「后落向先
  落对齐」规则由 M3 向 U 对齐（§1.3），U1 先行使格式真源
  先定。M3a 引擎本体（新文件）与 U1 无文件冲突，若人力并
  行，M3a 的引擎/场景实装可与 U1 并行开发、串行入册。
- M3b 的真实瓶颈是 write 重配对（用户动作）而非代码：建议
  在 M3a 交付时一并请用户重配对勾选 write，使 M3b 与 M2 写
  层同时解禁、一并验收。
- 清单计数账（每批入册后三方同步 + manifestHash 重算，绝对
  数随落地顺序浮动，只记增量）：现行 22 → §7/U0 批 +5
  （在席四件 + arm）→ U1 +4（uitest）→ M3a +4（scenarios
  三件 + metrics_create_settle）→ M3b +1
  （backup_restore_snapshot）→ M3c +6（ops_command 四件 +
  clear_caches + open_readonly）。

### 6.3 每期改动面（估）

| 文件 | M3a | M3b | M3c |
|---|---|---|---|
| `MomentBridgeScenarios.swift`（新） | 主体（引擎/journal/注册表/四景，约 800 行） | +四景（约 500 行） | +两景（约 300 行） |
| `MomentBridgeTools.swift` | 分发器三 case + 场景门集合（约 80 行） | 场级两段接入（小） | — |
| `MomentBridgeProtocol.swift` | 清单 +4、错误码补 `run_conflict`/`hygiene_failed` 等 | 清单 +1 | 清单 +6 |
| `MomentBridgeOps.swift` / 快照文件 | — | `backup_restore_snapshot` 实装（按 §9.3） | 运维命令四件（按 §6.2b，另批口径） |
| `bridge/relay/worker.js` + 连接器 | TOOLS/scope/超时同步；ALLOWED_TOOLS +4；CONNECTOR.md 增场景目录 | 同步 +1 与场景目录更新 | 同步 +6 与 runbook 附录 |
| `build-app2.sh` / `push_small.py` | 新文件三处名单 + 传输名单 | 核对 | 核对 |
| `verify_ios.sh` | 新组 [27] 首批（§7）+ [16] 清单同步 | [27] 扩写景项 | [27] 扩运维景项 |

五语键：场景面不进设置 UI，**零新增语言键**，[9] 不动
（若将来设置页加场景呈现再另算）。

---

## 7. verify 断言面

新增 **[27] 组「桥场景库」**（不塞进 [16]：[16] 锁桥的协议/
授权/禁区，[27] 锁场景的注册/门/卫生/红线，分工与 U 批
[25] 先例一致；两组交叉只有清单名集一致一条镜像断言）：

- **B27-1 文件与构建**：MomentBridgeScenarios.swift 在位且
  进 build-app2.sh 三处名单（文件名单/primary 编译遍/链接
  .o）与 push_small 名单（与 B16-1/B25-1 同式）。
- **B27-2 清单与三方一致**：Protocol 清单含 scenarios 三件；
  抽 Protocol / 中继 TOOLS / 连接器 ALLOWED_TOOLS 三方名集
  做 diff 应为空（沿 B16-15 口径扩到场景名）；manifestHash
  注记随当批更新。
- **B27-3 场景门**：分发器含场景 scope 声明表与受理时验足
  分支（`scope_denied` 点名形态）；`containsHighRisk` 标记的
  场景 id 集与 `twoStageTools` 中 scenarios_run 的场级令牌
  校验在位。
- **B27-4 正文红线**（本组核心）：① 正文级四件名在
  MomentBridgeScenarios.swift 中**零出现**，且在 Protocol
  清单中持续零出现（评审落地前此断言不得删改，评审改判时
  须连同桥方案 §12.1 结论一并修订本断言并在落码报告注明）；
  ② 场景参数表声明中零 `text`/`blocks`/`runs` 键字面；
  ③ 证据组装段零 `notes_get` 正文回读符号（块序证据只走
  id/type 序列符号）。
- **B27-5 夹具守卫与卫生**：场景文件含登记集校验与
  `fixture_guard` 回码；清理链三件（softRemove +
  commitPendingDeletion + libraryHash 对账）字面在位；
  `hygiene_failed` 回码在位；恢复守卫（待删集最近一篇 id
  比对）与快照恢复守卫（当前哈希 == 变更后哈希比对）的判
  定式在位。
- **B27-6 快照纪律**：场景文件含 BridgeWriteSupport 快照
  入口引用；零 `exportZip(`（同 B16-12 口径）。
- **B27-7 受限集排除**：`safeLimitedTools` 集合字面量与
  scenarios 三名交集为空（逐名查，同 B25-3 式）。
- **B27-8 journal 与打点**：journal 文件名常量与状态枚举
  （含 `awaiting_manual_reopen`）在位；续跑双触发（启动扫
  描 + 模式翻转通知）符号在位；`SCENARIO run begin / step /
  suspend / resume / hygiene / run end` 模板行齐备（同
  B16-4 式）。
- **B27-9 描述符完整性**：注册表条目数与内置场景数常量一
  致；每条目含 requiredScopes 与 grades 声明（结构扫描：
  条目构造点逐个含两字段名）。
- **[16] 同步项**：B16-3 的逐名枚举随各期入册扩名（M3a
  +4、M3b +1、M3c +6，与 §6.2 计数账一致）；B16-15 三方
  diff 若按名集实现则自动覆盖新名，只需核注记。M2 待补的
  B16-10…16 与本组无重叠，仍归组版协调，M3 不动。
- **冒烟与验收**（每期）：smoke_ios.sh 全量（tree）+ [27]
  全绿才出包；真机验收每景连跑两遍结论一致（原方案 M3 验
  收口径）；失败景须能凭证据包独立定因；M3a 验收加一条反
  证：人为给某景参数表塞入正文键，run 应回 invalid_params
  且断言 B27-4 在构建期先红——红线要能被断言抓住才算落地。

---

## 8. 风险与未决点

1. **write 重配对是用户动作前置**：M3b 全部场景与 M2 写层
   同命。建议随 M3a 交付一并办理（§6.2），避免 M3b 出包后
   卡在 scope_denied 空转。
2. **跨重启续跑的边界**：用户重开后若先手动改了库（如删了
   夹具标记篇），续跑段的预期条件可能不符——journal 续跑
   前先验条件（bootMode/夹具在位/哈希链），不符即标 failed
   并保留证据，不强行收尾出假结论。
3. **全库恢复的演练风险**：`snapshot_restore_drill` 的恢复
   守卫（当前哈希须恰为本景变更后哈希）是硬 precondition；
   守卫之外再加一条：该景默认不在场景目录里标 available，
   须 params 显式 `armRestore: true` 才可跑（与两段提交、
   用户指令三重叠加）。
4. **场景增长的评审纪律**（与 U 方案 §8.4 同口径）：每个新
   场景 = 新的设备动作面，上线前逐景评审其
   requiredScopes / 夹具面 / 红线面，并同步 CONNECTOR.md
   场景目录；场景只许碰夹具的红线不因场景增多而松动。
5. **引擎与驱动的互斥实现归属**：run 互斥锁（§4.2）是 U/M3
   共用件，归先落地的一方（按排期为 U1 的驱动核或 M3a 的
   引擎，落码报告注明），另一方只许引用不许再造第二把锁。
6. **未决：`metrics_create_settle` 归批**——本文建议随 M3a
   补出（create_transition 的解析与之共用单一解析器）；
   若主线倾向把它并入 U3 与 metrics_drag_trace 同批，
   create_transition 在 M3b 落地时解析器已有工具版可用，
   亦可成立。留主线裁。
7. **未决：挂起 run 的用户可见性**——awaiting 态目前只经
   bridge_status 的最近调用与 get_result 呈现；是否在设置
   桥页面加一行「待续跑场景」呈现，留 M3a 落码时按设置页
   既有体例裁，不阻塞引擎。
