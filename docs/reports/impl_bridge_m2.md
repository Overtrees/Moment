# MCP 桥 M2 落码报告（语义读写 + 运维动作）

> 状态：**落码完成、未提交**。基线 HEAD 78bac65（0.9.53 组版中），本批随 0.9.54 出（落版主线定）。
> 规格：`plan_app_mcp_bridge.md` §5/§6/§7/§9。本报告含：工具清单与能力门账、正文开放的裁定状态、快照链验证、待补 verify 断言清单、中继改动与部署待办、接线待办（MomentApp 侧）。

---

## 1. 落地工具清单（manifest 11 → 22 件）

新增 11 件，三方清单（App `BridgeProto.toolNames` / 中继 `worker.js` TOOLS / 连接器 `ALLOWED_TOOLS`）已逐名对账一致（脚本比对 app-only 与 relay-only 均为空集）。新 manifestHash = `05bff500af70116f970f42687eb9454a99dd74ee887edc83fb8708e58c4a7035`（sha256("2025-06-18|" + 22 名排序逗号连接)，本地计算）。

| 工具 | 层 | 落点 | 说明 |
|---|---|---|---|
| `settings_get` | read | BridgeSettingsTools | 方案 M1 清单内但 M1 未出货，本批补齐（是设置写的回读半边）：语言偏好/生效码、开关注册表现值、天气 key 状态+来源（绝不回值）、桥状态摘要 |
| `settings_set_language` | write | BridgeSettingsTools | 走 `LangStore.apply`/`applyFollowSystem` 同一入口；非法码回 invalid_params |
| `settings_set_toggle` | write | BridgeSettingsTools | 注册表白名单仅 `diagAutodel`，表外一律 invalid_params；开启时同步触发 `DiagLog.applyAutodelete` |
| `settings_clear_weather_key` | write | BridgeSettingsTools | 只删 UserDefaults `weatherKey_<provider>` 自填覆盖；回清后状态/来源（bundle 兜底如实回 set/builtin）。**无经桥写入天气 key 的工具** |
| `ops_validate` | read | BridgeOpsTools | 纯校验：以 `OpsDirectives.sanitize` 同口径解析，回 acceptedFields/ignoredFields/invalidSteps（步名全集 = LaunchStep ∪ OpsStep）/规范形/sha256；不落盘不下发 |
| `notes_soft_delete` | write | BridgeWriteTools | docHash 守卫 + 快照先行 + `Library.softRemove` 同路（打标落盘 + 8 秒撤销窗口）；回 deletedAtMs/undoExpiresAtMs/snapshotId |
| `notes_restore_deleted` | write | BridgeWriteTools | 只恢复待删集**最近一篇**（现行 `Library.undoDeletion` 口径，方案 §5.5 明示的受限形态）；在册非最近回 `restore_unsupported` |
| `notes_delete_permanent` | ops + 两段提交 | BridgeWriteTools | 仅限待删集内；`confirmMemoId` 须逐字一致；expectedDocHash 必填（待删态哈希含 deletedAt 键，须以待删态回读为准）；强制单独快照；真删走 `Library.commitPendingDeletion` 同路 |
| `editor_delete_block` | write | BridgeWriteTools | 结构写：flushedNode 规范形删块 → `Library.persist` → 回读校验块已消失；参数只有 id 三件套 + 守卫，无正文 |
| `editor_move_block` | write | BridgeWriteTools | 语义重排：beforeBlockId/afterBlockId/toIndex 三选一；回 fromIndex/toIndex/新块序；回读块序逐字校验。`targetColumn` 暂不支持（回 invalid_params 并明示） |
| `rescue_try_normal_start` | ops + 两段提交 | BridgeOpsTools | 仅安全模式可调（受限集成员）；动作序列与 `RescueView.tryNormal` 逐点一致（`RESCUE action normal-retry via=bridge` + `recordRescueAction("normal-retry")` + `prepareNormalStart()` + `bootMode = .normal`）；forceSafeMode 仍在位时回 `forceSafeStillArmed: true` + note，不报假成功；回 `normalLoadSemantics: true` |

连带小修：`rescue_status.readOnlyOpen` 由 M1 的写死 `false` 改为 `library.isReadOnly` 实值（R2 落地后原写死值已失真）。

## 2. 能力门账（分发器 + 中继双层）

- App 分发器（`BridgeDispatcher`）：`writeScopeTools`（7 件）须 `write`、`opsScopeTools`（ops_refresh/notes_delete_permanent/rescue_try_normal_start）须 `ops`，未授一律 `scope_denied` 并在执行前拦截——不静默放行、不降级执行。
- 中继（worker.js）：新增 `WRITE_SCOPE_TOOLS` 门与 App 侧同表；`OPS_SCOPE_TOOLS` 扩入两件高危；写面超时 30s（方案 §3.3 写调用口径），ops 控制类维持 20s、只读 15s。
- **当前设备授权只有 read+ops**：write 层 7 件在现配对下会正确回 `scope_denied`（端内与中继双层），须用户回 App 重新配对勾选 write 后才可用；ops 层三件现即可用（permanent/try_normal 另有两段提交）。
- 两段提交（方案 §7.3）：分发器内实现——`dryRun: true` 发一次性 `actionToken`（绑定工具名 + 规范参数哈希，60 秒），执行须原样回带，缺/错/过期回 `confirmation_required`；令牌校验先于幂等回放（令牌一次性，丢响应后以新令牌 + 同幂等键重试得首次结果）。
- 数据写前置门（分发器统一）：库未开回 `library_unavailable`；只读打开态回 `read_only_mode`；当前缓存指令点名禁桥（`OpsStep.bridge`）回 `ops_disabled`（会话中途收紧的纵深防御，方案 §9.6）。
- 受限分发器（安全模式）：可用集按方案 §9.6 扩为 8 件（bridge_status/app_state/diag_tail/diag_search/ops_get_effective/ops_refresh/rescue_status/rescue_try_normal_start），其余 `safe_mode_limited`。**与 M1 出货口径的差异如实记账**：M1 实装只放行 bridge_status 一件，本批按方案 §9.6 的受限集定义对齐（否则 rescue_try_normal_start 在其唯一有意义的状态下永远不可达）；另加一条同源收紧——当前会话新拉到的缓存指令含 forceSafeMode 时，分发器同样转受限形态（方案 §9.6「写面先于读面被收紧」）。此两点须主线在改 [16] 断言时一并裁认（见 §5 清单 B16-3/B16-14）。
- Diag 打点：每次调用仍走协调器 `recordCall` 的 `BRIDGE tool <name> ms=<n> code=<…>`（含 dry_run/confirmation_required/scope_denied 等结果码）；写成功另记 `BRIDGE write tool=… target=… pre=<hash12> post=<hash12> snap=…` 与 `BRIDGE snapshot id=… reason=… bytes=…`。

## 3. 正文开放的裁定状态（待裁定、暂不开放）

方案 §12.1 与附录 B.3 定案：**M2 开放正文读写前，须先就设备段端到端信封加密（DO 只路由密文）做专项评审并把结论写回方案**；评审未落地前正文经中继为 TLS 明文路由。本批不自行拍板，以下正文级工具**不入 manifest**（App/中继/连接器三方均无，调用回 unknown_tool）：

- `notes_create`（块规格载正文）
- `editor_insert_block`（块规格载正文）
- `editor_update_block`（text/runs 载正文）
- `editor_set_block_type`（变换作用于正文且回包载规范节点）

已入册的块级工具（delete/move）参数与回包只有 id/类型/序号/哈希，不载正文。注记：`notes_get` 的正文回读是 M1 已出货口径（M1 验收范围），本批未动；其与上述裁定的关系（评审时是否一并收口）留评审定夺，本批不擅自回滚已出货面。

## 4. 快照链（写安全底座，方案 §9.3）

实现于 `BridgeWriteSupport`（MomentBridgeTools.swift 内；方案原规划独立文件 MomentBridgeSnapshots.swift，因本轮并行边界只许动桥六文件先并入本文件，拆分随主线组版批处理）：

- **生成方式**：直调 FFI——以 `MomentLibrary.openReadonly(path: storeDir/moment.db)` 开只读句柄调 `exportBackup(zipPath:)`。已核存储层源码：`export_backup` 是纯读查询（list_memos/meta/attachments SELECT）+ 写 zip 文件，不触碰库写面，与在席写句柄并存安全；且待删项按存储口径自动排除。**不走 `Library.exportZip()`**：不更新 `lastExportTs`、不记备份操作记录、不污染备份新鲜度口径。桥六文件内 `exportZip(` 调用为零（待 [16] 断言锁，见 §5）。
- **落点**：`Application Support/bridge-snapshots/`（与资料库同域、独立目录，不进用户备份 ZIP、不进 Diag 域）；`manifest.json` 记 snapshotId/时刻/触发工具/写前 libraryHash/memoCount/字节数；`operations.jsonl` 逐条记写操作元数据（ts/tool/keyHash 前 16/target/pre/post 短哈希/snap/code，不记正文与参数全文）。
- **触发点**：写会话（同一 idempotencyKey 前缀）首个写操作前一份；`notes_delete_permanent` 每次强制单独一份。快照失败回 `snapshot_failed` 且写中止（分发器/工具层双保：工具在变更前先取快照）。
- **保留**：最近 10 份且 ≤7 天，超限删 zip + 清单条目并记 `BRIDGE snapshot pruned` 行。
- **幂等**：分发器层回放表（key → 参数哈希 + 首次结果）；同 key 同参回首次结果并标 `idempotentReplay`，同 key 异参回 `idempotency_conflict`。回放表为进程内态（流水 jsonl 落盘供 `write_outcome_unknown` 后对账）。
- **docHash**：沿用 M1 的 `BridgeDocHash`（与 persist 落盘字节同构），守卫不匹配回 `revision_conflict`；写后回读校验（软删查待删集登记、删块查块消失、移块查块序逐字、永删查全集消失），校验不过回 `write_outcome_unknown`（retryable），不假成功。

## 5. 待补 verify 断言清单（[16] 组，主线通知后落）

本轮未动 verify_ios.sh（0.9.53 冒烟在途）。以下为 M2 须补/须改的 [16] 断言，逐条可直接落码：

- **B16-3 必须改写**（现断言是 M1 边界：清单 11 件 + 写工具名零出现——M2 落码后必然转红，属预期）：改为「清单 22 件逐名在 BPROTO」+「正文级 4 名（notes_create/editor_insert_block/editor_update_block/editor_set_block_type）、在席 4 名（editor_open/editor_get_state/editor_focus_block/editor_save_now）、rescue_arm_safe_mode 在桥六文件与 worker.js 零出现」。
- **B16-10 能力门**：BTOOLS 含 `writeScopeTools`/`opsScopeTools` 集合字面量与两条 `scope_denied` 分支；RELAY 含 `WRITE_SCOPE_TOOLS` 与 `WRITE_TIMEOUT_MS`。
- **B16-11 两段提交**：BTOOLS 含 `twoStageTools`、`actionToken`、`confirmation_required`；deletePermanent 段内含 `confirmMemoId` 校验。
- **B16-12 快照先行**：BTOOLS 含 `openReadonly` + `exportBackup` 直调与 `bridge-snapshots` 目录常量；桥六文件 `exportZip(` 零出现（快照不污染备份新鲜度）。
- **B16-13 幂等与守卫**：BTOOLS 含 `paramsHash`、`idempotency_conflict`、`revision_conflict`、`guardedMemo`。
- **B16-14 受限集**：BTOOLS 的 `safeLimitedTools` 集合与 §9.6 八件逐名一致；BOPS 含 `not_in_safe_mode` 与 `via=bridge` 标记行、`recordRescueAction("normal-retry")`。
- **B16-15 三方清单一致**：脚本抽 BPROTO `toolNames` 与 RELAY `TOOLS` 名集合做 diff 应为空；manifestHash 注记更新为 `05bff500…`（仅注记，哈希由两边运行时计算对账）。
- **B16-16 设置写白名单**：BTOOLS 含 `toggleRegistry` 且其集合字面量只含 `diagAutodel`；`removeObject(forKey: "weatherKey_"` 在位且桥六文件零 `set(` 写 `weatherKey_`（无经桥写天气 key 的路径）。
- [9] 五语键：本批**零新增语言键**（工具面不经 UI 文案），[9] 期望数不变，无需同步。

## 6. 中继改动与部署待办

- worker.js 已改（本地）：TOOLS +11 件及 schema、WRITE_SCOPE_TOOLS 门、OPS_SCOPE_TOOLS 扩 2 件、WRITE_TIMEOUT_MS 30s、unknown_tool 文案去 M1 字样、头部注释更新。`node --check` 通过。
- **部署待主线安排**：经 `bridge/relay/deploy.py` 重新部署 moment-bridge 后，中继 tools/list 才含 M2 集；部署与 App 0.9.54 须同批生效——只部署一边时 manifestHash 对账会现形（bridge_status 的 manifestHash 与 list-tools 清单不一致），这是预期的中间态判据，不是故障。
- 连接器已同步：`client.py` ALLOWED_TOOLS 扩至 22 件（ast 解析通过）；`CONNECTOR.md` 增 M2 章节（能力层、两段提交、快照/幂等纪律、暂缓面与原因）与错误处置三条。

## 7. 接线待办（MomentApp 侧，本轮边界外，须主线排批）

以下四项的消费/通道点都在 MomentApp.swift（本轮冻结），本批只在报告中钉死接口需求，不注册假工具：

1. **editor_open / editor_get_state / editor_focus_block / editor_save_now**：缺桥导航通道与在席 EditorModel 注册表（现开篇走 ListView 局部 `nav.editorHost.pushEditor`，桥无从触达）。接线需求：根视图挂一个桥可调用的导航请求口（memoId → pushEditor）+ EditorModel 在席注册（open 时登记、close 时注销），桥据此实现四件并补 `memo_busy` 判定。
2. **块级写的在席限制**：editor_delete_block/editor_move_block 现走 Library 文档路径；目标篇正在编辑器中打开时，编辑器持有独立块状态副本，其下一次保存以编辑器态为准——在注册表（第 1 项）落地前无法回 `memo_busy`。当前保底 = docHash 守卫 + 写后回读；验收场景应只对未打开的夹具篇用此两件。此限制已同步写入 CONNECTOR.md。
3. **rescue_arm_safe_mode**：布防标记的消费点在 Library 启动判定（与哨兵/OPS 同点位读 diag 域标记文件），属 MomentApp.swift 改动；标记格式建议随接线批定（`diag/bridge-safe-mode-arm.json`：{armedAtMs, reason, commandId}，消费一次后转审计留痕）。消费点落地前不入册。
4. **DocumentMutationService 抽取**（方案 §5.4）：正文级工具解禁（待加密评审）时与 editor_set_block_type 一并依赖此内核；本批块级结构写未复刻 EditorModel 变换（只做节点数组的删/移 + persist 同路），无第二份变换逻辑分叉。

## 8. 自检

- Swift：本机无 swiftc（工具链在 tree），已做括号/引号平衡检查与逐段复读；编译级验证随主线 tree 冒烟（0.9.54 组版时 [16] 断言按 §5 落齐后一并把关）。风险点自查：`MomentLibrary.openReadonly`/`exportBackup` 签名与 bindings 一致；`Library.undoWindowMs`/`pendingDeletions` 元组字段、`LangStore.codes`、`WeatherService.keySource`、`OpsDirectives.sanitize`、`LaunchStep`/`OpsStep` 步名常量均回源核对。
- worker.js：`node --check` 通过；三方清单脚本对账一致（22 = 22 = 22）。
- 五语键：零新增，净账 0，[9] 不动。
- 改动文件：`MomentBridgeProtocol.swift`、`MomentBridgeTools.swift`、`MomentBridgeOps.swift`、`MomentBridge.swift`（仅注释一句）、`bridge/relay/worker.js`、连接器 `bin/client.py` + `CONNECTOR.md`。未碰 MomentApp.swift / verify_ios.sh / MomentBridgeSettings.swift / MomentBridgeTransport.swift / build 脚本。（工作树内 `docs/WORKFLOW.md` 的改动属并行沉淀线，非本批。）
