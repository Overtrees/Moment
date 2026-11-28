# 桥快照恢复工具 backup_restore_snapshot 落地（impl）

> 补完 M3b 第四景 snapshot_restore_drill 的前置缺口（留账出处：
> impl_bridge_m3b_scenarios.md §3——该文件 §3 在落盘时被截断、
> 正文只剩首条，缺口定义实际以 plan_bridge_m3.md §2.2/§6.3 与
> plan_app_mcp_bridge.md §9.3/§7.3 为准，本批按此回源落码）。
> 矩阵行：DAT-04 运行腿（plan_selftest_coverage.md §5 对账行 +
> §4.10），验收口径 = 快照→变更→恢复→verifyStore 对账。

## 1. 工具语义与安全面

`backup_restore_snapshot`（清单第 37 件）：入参 `snapshotId` +
`idempotencyKey`，按快照 id 把**全库**恢复到该快照点（全库替换
语义，回执以 `fullReplace: true` 明示）。安全面按既有运维工具
最高规格逐项对齐（分发器 MomentBridgeTools 集合单点）：

| 面 | 落点 |
|---|---|
| ops scope 门 | `opsScopeTools`（App + 中继 OPS_SCOPE_TOOLS 双层） |
| 两段确认 | `twoStageTools`：dryRun 取绑定工具名+参数哈希的 actionToken，60 秒一次性 |
| 事前用户指令 | 方案 §7.3 登记（执行者纪律面，工具描述与 CONNECTOR 同步明示） |
| 恢复前强制再快照 | 本体内 `takeSnapshot(reason: "backup_restore_snapshot:pre")` 直取（每次单独、不走会话复用），回执回 `preRestoreSnapshotId`——恢复本身可逆，失败/对账不一致时回滚路即此快照 |
| 幂等键 | `dataWriteTools` 管线：同 key 同参回放首次结果、异参回 `idempotency_conflict`；本体内亦强制要求 key 在位 |
| 数据写前置门 | 库在位/非只读/OPS 禁桥深查（dataWriteTools 同辖面）；安全模式受限集**不收**（§9.6，快照恢复一律 safe_mode_limited） |
| 在席守卫 | 任一备忘在编辑器在席即回 `memo_busy`：全库替换下在席活态副本的下一次保存会以旧库态整篇覆写恢复结果，与块写 memo_busy 同理（本批新增守卫，方案未明文、按同型风险补齐） |
| 实况长操作 | `liveLongOpTools` 入集（与永删/恢复删除同列） |
| 目标不存在/过期 | 清单查册 + zip 实体双在才算存在（`BridgeWriteSupport.snapshotRecord`，查册单点）；保留策略（10 份/7 天）清掉的旧快照同归新码 `snapshot_not_found`，如实失败不假成功 |
| 校验/换库/对账失败 | 复用既有码 `snapshot_failed`（§9.3 定名），消息带恢复前快照 id 供回滚 |

Diag 打点（只记结果侧，永不记正文）：`BRIDGE restore begin
target=<id> rollback=<id> preHash=<短> expectCount/expectHash`、
`BRIDGE restore verify … count=<后>/<清单> hash=<短> match=<0|1>`、
失败 error 行带 reason 阶段名；另走分发器既有 `BRIDGE tool` 行与
操作流水（recordCompletion 同管线）。

## 2. 复用点（禁另起恢复管线）

- 换库链与用户导入**同一条**：Library 新增提交点
  `bridgeRestoreFromSnapshot(zipPath:)`（MomentApp.swift，紧邻
  commitStagedImport）= `validateBackup` 整包校验 → FFI
  `importBackup`（storage validate-then-swap 单事务，DAT-04
  构建期已覆盖）→ `reload` 呈现重载 → FFI 直读对账。成败口径
  沿 BK-1：换库成功即已恢复，reload 失败只记行不反转（对账走
  FFI 直读不依赖内存镜像）。与 commitStagedImport 的分工仅在
  入口（暂存路径+备份页记账 vs 桥快照路径+recordOp 同账留痕）。
- 对账口径同源：恢复后计数 = FFI 直读全集里 `deletedAtMs ==
  nil` 的篇数，与快照清单 appendManifest 的记账口径（在册未删
  篇数）同定义；哈希 = `libraryHash()` 与清单 preHash 比对。
- 快照生成/清单/保留全走既有 BridgeWriteSupport（takeSnapshot
  只读句柄直调 exportBackup，不污染用户备份新鲜度口径）；
  本批只为其新增查册入口 `snapshotRecord(id:)`。
- 场景内部同路：drill 直接调 `BridgeBackupTools.restoreSnapshot`
  本体（与分发器 case 背后同一函数，禁双轨）；场级两段在
  scenarios_run 受理时已按 containsHighRisk 验足。

## 3. 落点清单

- **新文件** `MomentBridgeRestore.swift`：`BridgeBackupTools.
  restoreSnapshot` 本体（查册→在席守卫→强制再快照→Library
  同路→对账组装）。按红线④独立成文件，不塞 MomentBridgeTools。
- `MomentBridgeTools.swift`：分发器四集合入册 + switch case +
  `BridgeWriteSupport.snapshotRecord` 查册点。
- `MomentApp.swift`：`Library.bridgeRestoreFromSnapshot` +
  `BridgeRestoreOutcome`（仅此一处，约 70 行）。
- `MomentBridgeProtocol.swift`：toolNames 36→37 + 登记注释
  （新码 snapshot_not_found、受限集不收）。
- `build-app2.sh`：新文件进全部 30 遍次级名单 + 自有 primary
  遍（bridge_restore.o）+ 主链接行。
- `bridge/relay/worker.js`：TOOLS 条目（schema/描述）、
  OPS_SCOPE_TOOLS 入集、长操作超时分支同永删口径、头部注释
  计数。**本批不部署中继**（见留账）。
- 连接器（仓外，同批编辑）：client.py ALLOWED_TOOLS 入册
  （**不入** READ_RETRY_TOOLS——写/运维永不自动重放，既有口
  径）；CONNECTOR.md 计数 36→37、新哈希、工具条目、M3b 景
  条目改判。仓外传输名单 tree-sync/push_small.py 同步加新
  文件（组版同步 tree 时不漏传）。

## 4. 场景接线（snapshot_restore_drill）

- 描述符摘 `wiringMissing: true`，summary 改真接线口径；
  wiring 通用机制（字段/可用性分支/run 拒绝）保留在位供未来
  未落景使用，本景不再命中（verify B67-1 改判锁此形态）。
- **武装门**（plan §8 风险 3 的第三重门）：可用性对本景恒回
  `arm_required`（永不标 plain available）；scenarios_run 未带
  `params.armRestore == true` 受理即拒（新码 `arm_required`）。
  与整场两段（containsHighRisk）、事前用户指令
  （requiresUserDirective）三重叠加。
- 步表 6 步（BridgeScenarios.snapshotRestoreDrillSteps）：
  建夹具 → **自取快照**（takeSnapshot 强制新取——不用共用
  snapshotStep 的会话复用：会话快照按 idempotencyKey 前缀
  "scenario" 跨 run 复用，A 态会错指更早快照；本景 A 必须恰
  为夹具建成后的库态）+ 清单对账断言（record.preHash ==
  当时 libraryHash）→ 软删夹具变更（断言 hash B ≠ A）→
  **恢复守卫**（当前 libraryHash 须恰为 B，否则拒跑——快照后
  除本景外的任何变更都会被全库替换一并回滚，守卫不过坚决不
  执行）→ 内部同路恢复（目标 id 引擎内定，**不接受桥传
  snapshotId**——防恢复面变任意回滚入口）+ 三面断言（哈希回
  A/计数与清单一致/夹具回列表）→ 结论组装（三段哈希 A/B/恢
  复后入 detail）。清理在恢复后的库上执行（引擎收尾链既有
  行为，plan 口径兑现）。

## 5. 清单同步状态（三处 + 哈希）

- App：toolNames 37 件，manifestHash = `1c2fe22e…`
  （sha256("2025-06-18|" + 37 名排序连接），本机 python 复算
  与协议注释一致）。
- 中继：TOOLS 37 件同名集（verify B16-15 以 diff 空 + 计数
  37 在本机实测绿）；**未部署**（留账）。
- 连接器：ALLOWED_TOOLS 37 件 + CONNECTOR.md 已同步（仓外
  文件，非本仓提交面，组版报告须注明其已先行）。

## 6. verify 与自检（本机，证据上限）

- 新增/改判断言：B16-23（新组项，锁机制面：三集入册/受限集
  不收/强制再快照直取/双码/在席守卫/内部同路/中继同表/构建
  接线计数——文本锚只作机制在位证据）、B67-7（景步表面）、
  B67-1 改判、B16-3/B16-15 计数 36→37 与哈希注记、B27-2 注
  释同步；新 primary 遍使全文件提及计数 +1，精确计数锁同批
  改判：SB-5（30→31）、E47-8（30→31）、X50-7（30→31）、
  DT46-6（29→30）；IMG55-7 等式锁自动守恒（31=31）。
- 本机 verify_ios.sh 全量：**692 ✓**，红 2 = 产物陈旧两条
  （ipa 早于源码、产物语言包未重建）——产物面红、非源码红，
  待 tree 重建后自清；本批相关组（[16]/[27]/[67] 与全部计数
  锁）全绿。
- cargo test --workspace：全绿（各套件 0 failed；本批未动
  Rust 面，回归口径）。
- 语法旁证：worker.js 经 node --check 通过；build/verify 脚
  本 bash -n 通过；Swift 本机无编译器，括号平衡与 HEAD 同口
  径（字面量不平衡为存量）。
- **证据上限（明说）**：本批 Swift 代码**未过任何编译门**——
  tree smoke_ios.sh 是其首次编译门，留下版组版执行；场景与
  工具的桥实跑（两遍口径）留下版装机后。不得表述为已验。

## 7. 留账

1. **中继部署**：worker.js 已改未部署——按下版组版笔随
   bridge/relay/deploy.py 部署（勿用 cf.py），部署后三方
   manifestHash 对账（bridge_status 实读 1c2fe22e…）。
2. **tree 编译门**：smoke_ios.sh 全量（本批 Swift 首次编译），
   红回源根治不打补丁。
3. **装机后桥实跑**：backup_restore_snapshot 直调一轮（dryRun
   → 执行 → 回读对账 + 恢复前快照回滚演练）与
   snapshot_restore_drill 连跑两遍（armRestore: true + 整场
   两段），Diag 补读 BRIDGE restore 行核对。
4. 矩阵 DAT-04 行已就地回写为「已落码转正」（运行验收待
   装机后行）；impl_bridge_m3b_scenarios.md §3 的截断缺口由
   本报告承接定义，不回改旧报告（历史件）。
