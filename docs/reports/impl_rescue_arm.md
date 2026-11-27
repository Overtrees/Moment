# rescue_arm_safe_mode 布防消费点落码报告（M2 §7.3 接线批 / M3c 开工前置）

> 状态：**落码完成、未提交、未 bump**（基线 HEAD 297ad13 / 0.9.56 组版后；开工门已核：组版六笔已落、HEAD 已越过 9d9dd9f、工作树无并行批在途改动）。规格源：`plan_app_mcp_bridge.md` §6.3（工具规格）/ §3.4（错误表）/ §9.6（受限集）、`impl_bridge_m2.md` §7.3（接线待办第 3 项）。
> 一句话：布防标记的**写入方（工具入册）+ 持久化（diag 域单文件）+ 启动期消费点（判定第三路）**整环落地，M3c `safe_mode_drill` 的前置就此解除。

---

## 1. 现状考古（落码前）

| 面 | 落码前状态 |
|---|---|
| 工具入册 | **零注册**：`rescue_arm_safe_mode` 只出现在 BPROTO / worker.js / client.py / CONNECTOR.md 的注释与「待评审」注记里，verify B16-3 以断言锁其在桥文件与中继代码行**零出现** |
| 写入方 | 无。`MomentBridgeOps.swift` 只有 OPS 三层回读、ops_validate、rescue_try_normal_start |
| 持久化 | 无标记文件、无格式定义（§7.3 只给建议格式 `diag/bridge-safe-mode-arm.json`） |
| 启动消费 | 无。`Library.judgePreviousLaunch` 只有两路：哨兵 streak（≥2 定源 `streak`）、OPS 缓存 forceSafeMode（定源 `ops`） |
| 兄弟工具 | `rescue_try_normal_start` 已于 M2 完整落地（ops + 两段提交 + 受限集在册），其 `forceSafeStillArmed` 只读 bootAppliedOps 与 OPS 缓存——布防消费后不残留，与本批天然兼容（见 §4） |

结论：缺口与 §7.3 记载逐字一致——消费点未落、故未入册。本批按「消费点落地与入册同批」的 §7.3 口径整环补齐。

## 2. 落码清单

| 文件 | 改动 |
|---|---|
| `MomentBridgeOps.swift` | 新增 `BridgeSafeModeArm` / `BridgeSafeModeArmAudit` / `BridgeSafeModeArmStore`（diag 域双文件：活动标记 `bridge-safe-mode-arm.json` + 审计 `bridge-safe-mode-arm-audit.json`，均 `.atomic` 直写、叶子层纯文件 IO）；新增处理器 `BridgeOpsTools.rescueArmSafeMode`；`rescue_status` 回包增 `safeModeArm` 段（活动标记 + 最近审计回读） |
| `MomentBridgeTools.swift` | 分发器三集登记：`opsScopeTools`（ops 能力门）、`twoStageTools`（两段提交）、`dataWriteTools`（幂等管线，见 §5 裁定）；switch 新增 case；头部注记「高危两件」改「三件」 |
| `MomentBridgeProtocol.swift` | `toolNames` +1（合计 **31 件**）；未入册注记删布防名、增入册注记 |
| `MomentApp.swift` | `judgePreviousLaunch` 在 OPS 路之后、RESCUE enter 记行之前加**第三路消费**（take → 定源/只消费 → recordAudit → 双行 Diag）；`BootMode` source 注记与判定函数文档注记同步补 `bridge` 路 |
| `bridge/relay/worker.js` | TOOLS +1 条目（reason/idempotencyKey 必填 + dryRun/actionToken）；`OPS_SCOPE_TOOLS` +1；清单注记 30→31 |
| 连接器 `bin/client.py` / `CONNECTOR.md` | ALLOWED_TOOLS +1 与注记；CONNECTOR 的 ops 集/两段集清单同步、held-back 段删布防名、新增布防语义条目与 31 件哈希注记 |
| `docs/reports/plan_app_mcp_bridge.md` | §3.4 错误表登记新码 `arm_write_failed`（retryable）一行 |
| `verify_ios.sh` | B16-3 改写（31 件 + 禁注集删布防名）、B16-15 改写（31 件 + 哈希注记 `a52116c3…`）、新 **B16-17**（入册三集 + 处理器 + 中继同表 + 受限集负查）、新 **R13-9**（第三路消费机制锁）。[25]/[27]/[31] 等并行批段未碰 |

新 manifestHash（31 件）：`a52116c38d2f70966de8de41df102a5aab10a38c87e3dbd7e64ce229eafc6da9`（本地按 BPROTO 同算法核算）。**中继 redeploy 随下一组版执行**（代码三方已同步、线上仍服务 30 件，与 U1 批的 staging 态同例）。

## 3. 状态机（布防 → 重启 → 消费 → 清除）

```
[无标记] ──rescue_arm_safe_mode（ops + 两段提交 + 幂等键）──▶ [标记 pending]
   ▲            Diag: RESCUE arm set id=<commandId> reason=<…>     │（diag 域单文件，至多一份；
   │                                                                │ 后到覆盖先到，Diag 记 replaced=1）
   │                                                                ▼
   │                                          下次冷启 Library.init → judgePreviousLaunch
   │                                          ① streak 路 ② OPS 路 ③ 布防路 take()
   │                                          take = 读 + 立即删文件（取走即清）
   │                                          ├─ 前两路未定 safe → 定源 source="bridge"（applied=1）
   │                                          └─ 已 safe → 只消费不改源（applied=0，效果已达）
   │                                          recordAudit → 审计文件（最近一次消费全记录）
   │                                          Diag: RESCUE arm consumed id=… applied=<0|1>
   │                                                RESCUE arm cleared  id=… audit=<0|1>
   │                                                                ▼
   └──────────────────── [无标记 + 审计留痕] ◀── rescue_status.safeModeArm 可回读
```

防循环三重锁：① 消费发生在判定点、且 take 先删后判——同一标记物理上不可能被第二次启动读到；② 布防→进安全→`rescue_try_normal_start` 回正常（会话内）→下次冷启无标记、回正常，不会被旧布防拽回；③ 已被 streak/OPS 定 safe 的启动同样消费掉标记（applied=0），不让它跨启动残留到「下一次」才发作。

边缘口径：标记文件损坏（解码失败）时 `load()` 回 nil、视为无布防——损坏标记不强制任何事，后续 arm 覆盖即愈（写入走 `.atomic`，损坏本不可达，此为兜底语义而非新增行为）。

## 4. 与 forceSafeMode 的分工表

| 维度 | OPS `forceSafeMode`（源头指令） | 桥布防 `rescue_arm_safe_mode`（本批） | 哨兵 streak（参照） |
|---|---|---|---|
| 触发方 | 用户在源头（Worker/GitHub Pages）发布指令 | 助手经桥（ops 能力位 + 两段提交 + 事前指令） | App 自身连续启动失败 ≥2 |
| 载体 | OPS 缓存文件（双源拉取） | diag 域标记文件（本地写、不经网络） | diag 域哨兵文件 |
| 持续性 | **持续型**：每启必读，指令在位每启必 safe | **一次型**：下次启动消费恰一次即清 | 计数型：成功启动清零 |
| 定源标记 | `src=ops` | `src=bridge`（仅当它为定源路径） | `src=streak` |
| 放松路径 | 只能改源头（桥永不能抵消，方案「只能收紧不能放松」） | 无需放松（自清）；**远程解除布防不存在**（禁区 #5） | 正常启动成功自清 |
| 并存规则 | 三路取并（任一成立即 safe），互不覆盖；定源按判定序 streak → ops → bridge，布防非定源时以 applied=0 留痕 | 同左 | 同左 |
| 在位回读 | `ops_get_effective` 三层 | `rescue_status.safeModeArm`（pending + lastConsumed） | `rescue_status.sentinel` |

与 `rescue_try_normal_start` 的衔接：其 `forceSafeStillArmed` 只查 OPS 两读数——布防在进入安全模式的那次启动已被消费，故 try_normal 不会因布防误报「仍被布防」，返回口径无需改动。

## 5. 两处口径裁定（本批内定格）

1. **安全模式内可用性：不入受限集**。`safeLimitedTools` 维持 §9.6 八件精确集（B16-14 断言守恒、B16-17 显式负查）。理由：已在安全模式时布防无语义；救援面禁区 #5 的精神是安全模式内不做模式面远程变更（解除尚且禁止，叠加布防同理从严）；`safe_mode_drill` 的布防步发生在正常模式，不受影响。安全模式内调用回 `safe_mode_limited`（分发器受限形态前置拦截，诚实回码）。
2. **入 `dataWriteTools` 幂等管线**：工具规格（§6.3）明列 `idempotencyKey` 入参，故入集取「幂等回放 + operations.jsonl 留痕 + 只读门 + OPS 禁桥门」四项辖面，与永删同口径；它**不写库、不取快照**（快照是 BridgeWriteTools 处理器内行为，非分发器集成员义务），集定义注记已写明此边界。副作用如实记：只读打开态下布防回 `read_only_mode`——只读态本身即救援流程在场（本地操作优先），可接受。

Diag 三行汇总：登记 `RESCUE arm set id=… reason=…`（BOPS 处理器）、消费 `RESCUE arm consumed id=… applied=…`、清除 `RESCUE arm cleared id=… audit=…`（判定点）。

## 6. 验证

- 本机 verify：**256 ✓**（基线 254 + 新 2 条），仅剩 2 条既有产物类 ✗（ipa 陈旧、产物语言包——tree 构建自解）；B16-3 / B16-14 / B16-15 / B25-10 镜像断言全绿。
- 本机 Swift 编译级：以 build-app2.sh 同旗标对四个改动文件各跑一遍 primary-file 全模块编译（BOPS / BTOOLS / BPROTO / MomentApp），**零错误**（MomentApp 两处 warning 为既有、与本批无关）。全量 16 遍 + 链接随组版 tree 冒烟。
- worker.js `node --check`、client.py `py_compile` 均过。
- 领地核对：未碰数据层、未改救援页 UI（RescueView 的 source 是数据行直出，`bridge` 无需新文案——本批零改 MomentRescue.swift，与圆角批无撞段）；MomentLaunch.swift 按方案 §7 文件图「不改结构」未动。

## 7. 真机终判点（装含本批的下一版后）

1. 正常模式下走桥布防（dryRun 取令牌 → 回带执行）：回 `armed: true` + `effectiveFrom: next_launch`；Diag 有 `RESCUE arm set` 行；`rescue_status.safeModeArm.armed = true`。
2. 强杀 App 重开：直进安全模式页，状态区 mode 行 `src=bridge`；Diag 依次有 `RESCUE arm consumed … applied=1`、`RESCUE arm cleared … audit=1`、`RESCUE enter … src=bridge`。
3. 安全模式内调 `rescue_try_normal_start`：回正常模式（`forceSafeStillArmed` 应为 false——布防已消费、不误报）。
4. **防循环终判**：再次强杀重开——必须正常启动、不回安全模式。
5. 安全模式内调 `rescue_arm_safe_mode`：回 `safe_mode_limited`。
6. （选验）OPS forceSafeMode 同时在位时布防：启动以 `src=ops` 进安全模式，Diag 有 `applied=0` 的消费/清除行，标记不残留。
