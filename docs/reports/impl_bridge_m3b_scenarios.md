# 桥 M3b 写景四景落码注册（impl）

> 起点实证：桥自办在 0.9.63 上实测 `scenarios_list` 只有 M3a 四景
> （drag_trace_review / weather_settings_flow / ops_convergence /
> language_roundtrip），M3b 四景在注册表与分发开关中均不存在——本体
> 未随版落地。本批按 plan_bridge_m3.md §2.2 定义逐景补落。
> 定义出处：plan_bridge_m3.md §2.2（逐景步表）/§5（门与红线）/
> §6.1（依赖表）；plan_selftest_coverage.md §6.6 与逐景归属行
> （delete_restore = HOM-10 数据腿 + BRG-04/05 运行验；
> drag_semantic_reorder = EDT-24 数据面 + BRG-08；
> create_transition = EDT-02 + HOM-12 桥腿；
> snapshot_restore_drill = DAT-04 运行腿）。

## 1. 前置核查（开工时点能力面，逐项回源）

| 前置 | 状态 | 证据 |
|---|---|---|
| U0 地基（在席四件 + memo_busy + 导航通道） | 已落 | Protocol 清单含 editor_open/get_state/focus_block/save_now；BridgeNavigationChannel 有 requestOpen/requestClose（MomentEditorTransition.swift） |
| write 重配对（用户动作前置） | 已解除 | 现配对 scopes = read+write+ops（桥自办实测 bridge_status） |
| metrics_create_settle + 共用解析器 | 已落（M3a） | BridgeCreateSettleParser 在场景文件内，create_transition 直接复用（单一来源） |
| 夹具登记集 + 多块模板 | U 批先建、本批复用 | UITestFixture（登记集）/ UITestFixtureTemplate.build(.blocks)（≥4 块多类型，矩阵 §6.6 定 drag 景复用同一模板） |
| backup_restore_snapshot 工具 | **未落** | 全仓零命中：Protocol 清单无、分发器无 case、无内部恢复实现（BridgeWriteSupport 只有快照「取」无「恢复」入口） |

## 2. 逐景落点

改动面：`MomentBridgeScenarios.swift` 单文件（+约 1190 行）+
verify [27]/[67]。无新增文件（场景文件已在构建/传输名单，B27-1 守）。

### 2.1 delete_restore_roundtrip —— 实装

- 描述符：requiredScopes=[write]、containsHighRisk=true、
  requiresUserDirective=true、phases=single、fixture=template、
  参数 includePermanent: bool（可选）。
- 步表（10 步）：写前快照 → 建夹具（create() 空模板 + 自检标题
  标记 + 登记）→ 软删（BridgeWriteTools.softDelete 内部同路，
  docHash 守卫以调用前回读组装）→ **恢复守卫**（待删集最近一篇
  id == 夹具 id 才进恢复段；不过即 step_failed 收尾并在结论标
  restoreGuard=blocked，绝不替用户恢复错篇）→ 恢复
  （restoreDeleted 内部同路）+ docHash 回到删前值双路断言 →
  再软删 → 轮询等 8 秒窗口（Library.undoWindowMs）自动真删 →
  回读全集确认消失 → 永删段三步（默认跳过并留 note）→ 结论组装。
- 永删段（includePermanent=true）：另一夹具软删后走
  deletePermanent 内部同路（confirmMemoId 由引擎以夹具 id 回带、
  expectedDocHash 取待删态回读、工具内强制单独快照沿既定纪律）；
  **段内另验 ops scope**（协调器 scopes 直查，缺 ops 该步失败，
  不静默跳过装作全过）。
- 证据：每步 deletedAtMs/undoExpiresAtMs/postDocHash、待删集
  回读、前后 libraryHash（引擎卫生对账）；等级 data/persistence
  = proven（描述符 grades 声明）。

### 2.2 drag_semantic_reorder —— 实装

- 描述符：requiredScopes=[write]、非高危、fixture=template、
  无参数；grades 块序/落盘 proven、手感 unknown。
- 步表（9 步）：写前快照 → 建多块夹具（复用 .blocks 模板）→
  移块①首块→尾（moveBlock 内部同路，toIndex）→ 移块②中间相邻
  两块互换（把第 3 块移到第 2 块之前，一次移动成互换）→ 库镜像
  回读块序逐字断言 → 关编辑器（保未在席）→ 导航通道重开
  （BridgeEditorTools.open）→ 在席块序（seatDict 的 id/type 序）
  再断言 → 关编辑器 → 结论（三段块序对照存 detail）。
- 块序证据只走库镜像的 id/type 序列（B27-4 红线：场景文件零
  notes 正文回读符号，本批保持 0 命中）。

### 2.3 create_transition —— 实装

- 描述符：requiredScopes=[write]、非高危、fixture=template、
  无参数；grades settle 数据 proven、顺滑体感 unknown。
- 步表（5 步）：写前快照 → 经新建同路建夹具（create() 开
  CREATE 量测账并留计时痕，标题标记 persist 与驱动 setup 同
  序）→ 导航通道打开（EditorModel 按 id 认领计时痕）→ 轮询
  ≤15s 等本夹具 CREATE settle 行 → 共用解析器逐段解析 →
  关编辑器。
- 基线护栏（场景内置常量，判读口径沿方案 §2.2）：单段 ms
  ≤2000、listpass 趟数 ≤5、bodypass ≤10。来源 =
  fix_transition_refactor.md 真机十连实测（create 1–6ms、
  listpass 1×3–8ms、avatar 0ms）与 round2 定案期望（趟数 1、
  bodypass ≤3）——护栏取实测宽放量级，只抓病理级回退；超护栏
  = 结论 degraded + 逐段列明，**不整场判红**；settle 缺失/
  超时或核心四段（create/model/dest/appear）非数值 = 场景失败。

### 2.4 snapshot_restore_drill —— 只注册，留账（见 §3）

描述符已注册：requiredScopes=[ops]、containsHighRisk=true、
requiresUserDirective=true、参数 armRestore: bool（方案 §8.3
的显式武装位，先行声明）、wiringMissing=true。可用性计算回
`wiring_missing`（清单现形）；scenarios_run 受理在
BridgeScenarioTools.run 即拒（新错误码 wiring_missing），步表
恒不建——工具未落不空跑假成功。

## 3. snapshot_restore_drill 缺口（留账，勿臆造）

- 缺口本体：`backup_restore_snapshot` 工具未落。按方案 §6.3，
  其
...[truncated 3072 chars]