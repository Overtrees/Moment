# 全面审计 E 片：平台与模块层（只读审计）

- 仓库：`~/workspace/Moment`，HEAD `b682d02`（`b682d02614a8f26dadc61b42566f18f91928a958`）。
- 范围：① 桥 MCP 工具面 ② 救援与自救 ③ Diag 覆盖全图 ④ 存储与数据完整性 ⑤ 冷启与滚动性能面 ⑥ i18n 五语全量 ⑦ Dynamic Type 真跟随全量 ⑧ 深色模式全量。代码面 = `rust/apps/ios/app/` 全部文件（状态栏采样面 `MomentStatusBar*.swift` 按任务书排除、未审）+ `rust/crates/{core,storage,ffi}` + 中继 `bridge/relay/worker.js` + 连接器 `custom.moment-bridge/bin/client.py`（仓外只读对账）。
- 基线必读已全读：`plan_selftest_coverage.md`、`fix_dark_mode_full.md`、`fix_dynamic_type_follow.md`、`impl_bridge_m3a.md`、`impl_bridge_reconnect.md`、`audit_native_diag_rescue.md`、`impl_gate_port_i18n.md`；另回读 `impl_rescue_r1.md`、`impl_rescue_r2r3.md`、`impl_rescue_integrity.md`、`fix_ops_effective_scope.md`、`fix_bridge_presentation_trio.md`、`audit_native_launch_crashsurface.md`、`audit_sqlite_integration.md` 与 `persist.rs` 头注（Web 观察期口径）。
- 方法：静态通读 + grep 普查 + 本机只读复算（manifestHash、语言包键数、深检脚本实跑、集合对账脚本）。**未跑构建、未跑 verify_ios.sh 全量、未动 git**；凡 verify 断言只引其脚本在位与锚文，不声称本轮实跑全绿。运行时/真机面一律标 unknown 并给取证法。
- 分级：proven = 源码/脚本/复算直接坐实；inferred = 机制成立但影响需运行时数据；unknown = 静态不可判、须 Diag/桥/真机取证。
- 排除项执行情况：appex 本体未审（仅登记开关在位，见 §2.5）；APNs/iCloud 本体未审；状态栏两文件未审（普查脚本均已剔除）。

---

## 0. 回归抽查六项（必做）总表

| # | 抽查项 | 结论 | 证据 |
|---|---|---|---|
| ① | DT 机制在位 + 0.9.58 实报三面（搜索胶囊/新建卡片/编辑器）真接入 | **通过（静态 proven，运行时终判 unknown）** | 工厂/epoch 见 §7.1；三面逐点见 §7.2 |
| ② | 深色令牌面无回潮（写死 Color 字面量分布） | **通过** | `(Color\|UIColor)(red:` 全集 8 行与 DM45-1 白名单逐行同位；`.foregroundStyle(.white)` = 0；`Color.white` 仅二维码底板 1 处。见 §8.2 |
| ③ | 桥 35 件与端上实现逐件对账 | **通过** | App `toolNames` = 中继 `TOOLS` = 连接器 `ALLOWED_TOOLS` = 35，集合差集为空；manifestHash 本机复算 `ec9fbc90890f…` 与 M3a 报告值一致；分发 switch 覆盖 34 件 + `ops_get_sources` 按设计中继侧执行（端上误达回 unknown_tool）。逐件表见 §1.2 |
| ④ | FFI 契约项数 vs 导出函数数一致 | **通过** | 导出面 23（构造子 2 + 方法 16 + 自由函数 5）= 契约断言 23 条 = verify [6] 文案 23 项。逐项表见 §4.5 |
| ⑤ | 救援白名单仅 disableSteps/forceSafeMode + 双源 URL 在位 | **通过** | `MomentOps.swift:57-66` 结构仅两字段（version 只记不判）；sanitize 逐字段类型核对；双源常量 `MomentOps.swift:84-87` 与中继 `OPS_SOURCES`（worker.js:474-477）逐字一致。见 §2.1 |
| ⑥ | i18n 429 键口径 + 深检脚本在位 | **通过** | 五包各 429 键、键集互等（本机复算）；`scripts/i18n_deep_check.py` 在位且本机实跑 exit 0（占位符齐平、动态认领 63 条、僵尸 0）；verify_ios.sh [9] 与 verify_rustweb.sh §7 同源调用。见 §6.1 |

---

## 1. 桥 MCP 工具面

### 1.1 现状 vs 应然

| 面 | 应然 | 现状 | 级别 |
|---|---|---|---|
| 清单三方一致 | App/中继/连接器逐名一致、哈希对账 | 35/35/35，差集空，哈希复算命中（§0③） | proven |
| 分发门序 | 清单门 → 受限集门 → scope 门 → 写前置门 → 两段提交 → 幂等回放 → 执行 | `MomentBridgeTools.swift:136-360` 顺序与应然逐段吻合：unknown_tool（:136）→ ops_get_sources 误达诚实回码（:145）→ safe-limited（:149）→ write/ops/uitest scope（:157/:164/:171）→ scenarios_run 声明制门（:186-245）→ dataWrite 前置门（:248）→ 两段提交（:279）→ 幂等回放（:319）→ liveLongOp 挂点（:346） | proven |
| 安全模式受限集 | 矩阵 LCH-03/BRG-07 口径 8 件 | `safeLimitedTools`（Tools.swift:84-93）恰 8 件：bridge_status/app_state/diag_tail/diag_search/ops_get_effective/ops_refresh/rescue_status/rescue_try_normal_start；且会话内新拉 forceSafeMode 亦触发受限（纵深，Tools.swift:147-148 读 `OpsDirectives.cached()`） | proven |
| 两段提交 | 高危件 dryRun→一次性令牌（60s、绑工具名+全参哈希） | `twoStageTools` 4 件（notes_delete_permanent/rescue_try_normal_start/rescue_arm_safe_mode/uitest_run，Tools.swift:69-74）+ scenarios_run 声明高危时整场入两段（:279-282）；令牌校验四项（名/哈希/未过期/一次性删除）在位（:296-312）。M3a 四景均未标高危、场级形态未行使过——与 M3a 报告 §8 口径一致（归 M3b） | proven（机制）/ unknown（高危景实跑） |
| 快照链 | 数据写先快照、失败 snapshot_failed 拒写 | `BridgeWriteSupport`（Tools.swift:986 起）：ensureSnapshot（:1071）落 `bridge-snapshots/` 独立目录 + manifest、失败回 snapshot_failed 并记 `BRIDGE snapshot failed`；写后 recordCompletion（:1203）+ docHash/libraryHash 回读（:1561-1576 等） | proven |
| 写前置门 | 库在位 + 非只读 + OPS 未禁桥，三门同序同码 | dataWriteTools 门（:248-267）三门齐；scenarios_run 与 uitest_run 各自同序复刻（:218-244、BridgeUITest.swift:3505-3525） | proven |
| 幂等 | 同 key 同参回放、同 key 异参 conflict | replay/recordCompletion 在位（:1001/:1203），回放命中带 `idempotentReplay`（:330） | proven |
| scope 集双层一致 | 中继侧与 App 侧同集拦截 | 中继 OPS/WRITE/UITEST 三集（worker.js:462-471）与 App 三集（Tools.swift:26-58）逐名一致（write 10 / ops 4 / uitest 4）；scenarios_run 中继侧不设集、App 声明制——与 M3a 定案一致 | proven |
| 续连令牌面 | 中继只存哈希、轮换、吊销清零、App 首帧呈递一次、被拒回退全量挑战 | 中继：RESUME_TTL_MS 30 天（worker.js:40）、issueResumeToken 只落 sha256（:519-520）、completeAuth 轮换（:874-898）、resume 帧常时比对 hashEqualHex（:963-977）、revoke 清哈希（:823）；App：Keychain 三件套 + clearPairing 同步清（MomentBridge.swift:190-204）、首帧 resume + challenge 持留/补答（:532、:871-909）。与 impl_bridge_reconnect 落码账逐项对上 | proven（机制）/ unknown（真机命中比，取证 = Diag `BRIDGE resume ok/fallback` 计数，报告 §四口径） |
| ping 去存储 | ping/presence 零 record 读写 | worker.js:985 注释与代码面一致（认证时收敛写）；本轮未重跑 harness，沿 impl_bridge_reconnect §三的十景实证 | inferred（沿旧实证） |

### 1.2 逐件对账表（35 件）

门归属：R=read（无 scope 门）/ W=write 集 / O=ops 集 / U=uitest 集（ops) / L=安全模式受限集成员 / 2S=两段提交 / DW=dataWriteTools（快照+幂等+前置门辖面）。

| 工具 | 中继 | 连接器 | App 分发 | 门 |
|---|---|---|---|---|
| bridge_status | ✓ | ✓ | ✓:364 | R, L |
| app_state | ✓ | ✓ | ✓:367 | R, L |
| diag_tail | ✓ | ✓ | ✓:372 | R, L |
| diag_search | ✓ | ✓ | ✓:378 | R, L |
| notes_list | ✓ | ✓ | ✓:383 | R |
| notes_search | ✓ | ✓ | ✓:389 | R |
| notes_get | ✓ | ✓ | ✓:398 | R |
| ops_get_effective | ✓ | ✓ | ✓:407 | R, L |
| ops_get_sources | ✓（中继自执行） | ✓ | 误达回 unknown_tool（设计） | R, L*（App 受限集不收，中继侧执行不受 App 分发辖） |
| ops_refresh | ✓ | ✓ | ✓:413 | O, L |
| ops_validate | ✓ | ✓ | ✓:426 | R |
| rescue_status | ✓ | ✓ | ✓:420 | R, L |
| rescue_try_normal_start | ✓ | ✓ | ✓:431 | O, L, 2S, DW*（经 dataWrite 旁路口径见 Tools.swift:60-65 注） |
| rescue_arm_safe_mode | ✓ | ✓ | ✓:440 | O, 2S, DW |
| settings_get | ✓ | ✓ | ✓:448 | R |
| settings_set_language | ✓ | ✓ | ✓:451 | W, DW |
| settings_set_toggle | ✓ | ✓ | ✓:456 | W, DW |
| settings_clear_weather_key | ✓ | ✓ | ✓:461 | W, DW |
| notes_soft_delete | ✓ | ✓ | ✓:467 | W, DW |
| notes_restore_deleted | ✓ | ✓ | ✓:476 | W, DW, liveLongOp |
| notes_delete_permanent | ✓ | ✓ | ✓:485 | O, 2S, DW, liveLongOp |
| editor_delete_block | ✓ | ✓ | ✓:494 | W, DW |
| editor_move_block | ✓ | ✓ | ✓:503 | W, DW |
| editor_open | ✓ | ✓ | ✓:512 | W, DW |
| editor_get_state | ✓ | ✓ | ✓:525 | R |
| editor_focus_block | ✓ | ✓ | ✓:534 | W, DW |
| editor_save_now | ✓ | ✓ | ✓:540 | W, DW |
| uitest_list_surfaces | ✓ | ✓ | ✓:549 | U |
| uitest_run | ✓ | ✓ | ✓:552 | U, 2S |
| uitest_get_result | ✓ | ✓ | ✓:558 | U |
| uitest_measure | ✓ | ✓ | ✓:564 | U |
| scenarios_list | ✓ | ✓ | ✓:570 | R |
| scenarios_run | ✓ | ✓ | ✓:574 | 不入任何集，逐景声明制（:186-245） |
| scenarios_get_result | ✓ | ✓ | ✓:583 | R |
| metrics_create_settle | ✓ | ✓ | ✓:589 | R |

场景注册表（MomentBridgeScenarios.swift:77-156）恰 4 景：drag_trace_review（read）/ weather_settings_flow（read）/ ops_convergence（ops, crossRestart）/ language_roundtrip（write）——与 M3a 报告 §2 目录一致；journal 环 10 run、单运行互斥与 uitest 共用（Scenarios.swift:302-346、UITest claim API）静态在位。

### 1.3 旧账状态（本片回读）

- **LCH-13（只读期桥回码一致化）**：矩阵仍登记「缺口/inferred」。现行码已闭合——dataWrite 前置门中 isReadOnly 判定（Tools.swift:252-259）位于两段提交、幂等回放与一切快照调用**之前**，只读期数据写直回 `read_only_mode`，不存在先快照后假成功路径；scenarios_run/uitest_run 同样前置。判：**已落、矩阵未回写**（proven）。
- **LCH-14（OPS 双轨表述/effectiveScope）**：主项已落（fix_ops_effective_scope §八：effectiveScopeDict 单点 MomentOps.swift:148-166、两回报各引用 1 次、B16-21/22 断言）。残余子项「ops_validate unguardable 步名拆集」仍未落——见新发现 **E-02**。
- **BRG-11/12/13（吊销回执/scopes 呈现/backoff reason）**：三项均已落（fix_bridge_presentation_trio 落码节）：revokeOutcome 三态 + 设置页呈现（MomentBridge.swift:260-261、MomentBridgeSettings.swift:322-328）、scopes_none/scopes_ungranted + 源头兜底改 `?? []`（BridgeSettings.swift:281-296）、stateReasonKey 上屏（Bridge.swift:267、356-357；BridgeSettings.swift:208-213）。矩阵 §4.9 仍标缺口，属**登记滞后**（proven 已落）。
- **BRG-04/05 运行级**（两段提交全链、写安全底座真机判读）仍归 M3b，未落——旧账维持（unknown，取证 = M3b 两景实跑）。

---

## 2. 救援与自救

### 2.1 OPS 通道（抽查⑤详账）

- 白名单：`OpsDirectiveSet`（MomentOps.swift:57-66）字段仅 `version/disableSteps/forceSafeMode`；`sanitize`（:113-131）逐字段类型核对（version 只记不判、disableSteps 非串元素剔除、forceSafeMode 须 Bool、未知字段忽略、整包坏损回 nil 当空指令）。中继 ops_get_sources 的 OPS_SOURCES 与端上双源逐字一致。**与应然全等（proven）**。
- 拉取：双源顺序、第一个成功为准、`?t=` 绕缓存、6s 超时、成功原子落缓存 + `OPS directives fetched src=… steps=… forceSafe=…` 行、全失败 logOnce warn（MomentOps.swift:184-247）。正常模式 didLoad 后台刷新一次（MomentApp.swift:1120 附近收尾段）。
- 生效口径：双轴已收敛单点 `effectiveScopeDict()`（MomentOps.swift:148-166），漂移文本（「本次不生效」「生效点恒为下次启动」）在 app 源码归零口径由 B16-22 锁（脚本在位，本轮未实跑）。

### 2.2 guard 点覆盖（登记六步 vs 实际消费）

OpsStep 登记六步（MomentOps.swift:22-48）。实际消费点逐个回源：

| 步名 | 消费点 | 状态 |
|---|---|---|
| 附件类型 | MomentApp.swift:1639（refreshAttachmentTypes，跳过记 `OPS skip step=` logOnce） | proven 在位 |
| Diag冻结写盘 | MomentApp.swift:4691（flushStructuralPersist，guard 判定在清脏之前——R3 真隔离） | proven 在位 |
| 天气自动刷新 | MomentApp.swift:18840（ListView.onAppear） | proven 在位 |
| MCP桥 | MomentBridge.swift:429（start 拦截）+ Tools.swift:231/:260（会话深查）+ BridgeUITest.swift:3517 | proven 在位 |
| 看门狗 | MomentApp.swift:837（armWatchdog） | proven 在位 |
| 公式预热 | **无消费点**——MathImageStore 头注（MomentApp.swift:14714）明示现无预热调用、步名先行登记、新预热必须先查 isDisabled | proven（登记态，与 R1 报告取舍 3 一致，非缺口） |

核心步（开库/读数据/解析/再水化）不设 guard、点名无效——MomentOps.swift:14-20 文件头红线与消费面一致（proven）。初始化 guard 的另一面：`DiagLog` 零依赖环由 verify [12] 锁、flushStructuralPersist 反向调用 sanitize 保持无环（MomentOps.swift:110-112 注记与代码一致）。

### 2.3 安全模式与受限集

- 进入路径四源齐：streak 同步判定（Library.init 内 judgePreviousLaunch，含 LCH-02 同一步锚定口径）/ OPS forceSafeMode（bootApplied 快照）/ 看门狗（enterRescueFromWatchdog，MomentApp.swift:873）/ 手动（enterRescueManually:892，Diag 页入口:5460 直引 `diag.enter_rescue` 键）/ 桥布防（rescue_arm_safe_mode，判定第三路）。`RESCUE enter … src=<streak|ops|watchdog|manual|bridge>` 留痕形态在位。
- 呈现分流：根 ZStack 按 bootIsSafe 分流、安全模式不构建 ListView、SplashHost 仅正常模式挂载（MomentApp.swift:21904 段）；RescueView 构建路径只依赖 DiagLog/FileManager 元数据/OpsDirectives 缓存/Library 已判定状态，不开库不调写 FFI（MomentRescue.swift:14-27 头注 + 动作五件 tryNormal:315 / openReadonly:331 / clearCaches:342 / exportDiag:354 / checkOps:374 / exportZipAction:387，ZIP 在 lib==nil 时 meta 置灰 + guard 拦截，不触发假成功）。
- 受限集：分发器 8 件（§1.1）；只读态门面拒写五 kind + 入口禁用双漏斗（writeBlocked/readonlyEntryBlocked，impl_rescue_integrity §6 清单）静态在位。
- **LCH-15（布防 reason 呈现）**：呈现三件批报告 §0 称「救援布防批 0.9.57 已落，RescueView 状态区附读审计 reason」；本轮在 MomentRescue.swift 与 MomentApp.swift 内以 rescue/arm/safe 为词根筛 reason **未命中呈现点**（grep 零行，见 §2.6 E-06 登记为待核项，不判缺口）。

### 2.4 看门狗 / 快照环 / Diag 手动入口

- 看门狗：阈值单点 `watchdogSeconds = 12`（MomentApp.swift:443）；arm 前移 Library.init 末尾（:505）+ load 起点续期；触发记 error `RESCUE watchdog fired step=<哨兵步>`（:849）+ WatchdogBar 挂根 ZStack 开屏之上（:21909-21918）、didLoad onChange 自撤（:21929）。与 R3 + 完整性批落码账一致（proven 静态）。
- 快照环：RescueSnapshot/RescueLogStore（MomentLaunch.swift:155-272），环 20、只记元数据、动作折行下次启动 drain 成 `RESCUE log actions=`；RescueView 状态区呈最新+上次两条（MomentRescue.swift:120 段、snapSummary:304）。字段黑名单（无 title/content/fileName）由 R19-8 锁（脚本在位）。
- Diag 手动入口：DiagView 库状态卡含全量导出、清缓存（天气缓存面，:5428-5433）、「进入救援模式」钮（:5460）；RescueView 内另有导出诊断/检查热修复动作。手动入口面齐（proven）。

### 2.5 已知状态登记（非发现）

- `BUNDLE_WIDGET_EXT=0` 在位（build-app2.sh:1075 恰一处定义、拷入段受 `= 1` 门控、开关关时 PlugIns 在场即 FATAL:1135；verify [52] INS52-1..3 锁）。appex 仍编译 + check-macho。按任务书仅登记，不审本体。

### 2.6 本节新发现

见 E-02（ops_validate 步名集）、E-06（布防 reason 呈现待核）。

---

## 3. Diag 覆盖全图

### 3.1 管线本体（现状 vs Web 口径）

| Web 口径（audit_native_diag_rescue §一） | 原生现状 | 级别 |
|---|---|---|
| 300 行环 + 落盘 | DiagLog today 环 300（MomentApp.swift:4815-4816） | proven |
| 1s 节流合并写、ERR 立即刷 | schedulePersist 同口径（:4716-4721 注记与实现）；error 行立即 | proven |
| 按天冻结归档、上限 60、戳为日志当天 | freezeToday + prefix(60)（:4748-4761），戳取 entries 最大 ts | proven |
| logOnce 去重 / logErrorOnce |:4830 /:4848 在位 | proven |
| 导出全量一键 + 动作记行 | DiagView.buildExportFile 静态共用链（DiagView 与 RescueView 共用）+ RESCUE/DIAG 动作行 | proven |
| 行格式 `[HH:MM:SS] TAG msg` + W/E | DiagEntry/DiagLevel 同形态 | proven |
| 落盘原子写 | **未达**——见 E-03 | proven（缺口） |

打点总量：全 app 源码 `DiagLog` 引用 347 处（MomentApp.swift 232、MomentBridge.swift 32、Scenarios 19、LiveOps 14、Transition 14、UITest 11、BridgeOps/BridgeTools 各 10、Drag 10、Rescue 9、Ops 6、XSelBridge 5、Permissions 4、其余零星）——较 audit_native_diag_rescue 记账的 27 处已数量级补齐（批 C 及后续各批）。

### 3.2 逐面覆盖表（页面/模块 → 打点）

| 面 | 直接打点 | 判读 |
|---|---|---|
| Library（启动/持久/导入/只读/看门狗） | 68 refs，LAUNCH/SMOKE/BOOT/RESCUE/READONLY/CREATE 行族齐 | ✓ proven |
| EditorModel（编辑语义/撤销/斜杠/转换） | 59 refs，EDIT/CREATE settle/SCROLL open-close | ✓ proven |
| 首页 ListView | 11 refs（搜索胶囊迁移、行展开/收起、OPS 天气 guard） | ✓ proven |
| EditorView / EditorHeaderView | 11 / 12 refs（TRANSITION、标题会话） | ✓ proven |
| 桥全家（Bridge/Tools/Ops/Scenarios/UITest/Settings） | 合计 83 refs，BRIDGE/SCENARIO/UITEST 行族齐 | ✓ proven |
| Drag / EditorTransition | 10 / 14 refs，DRAG 链完整（drag_trace_review 景的判读源） | ✓ proven |
| WeatherService | 10 refs，WEATHER 全链（双源/兜底/失败分行） | ✓ proven |
| DiagView/DiagLogPage | 15 / 3 refs（导出结局、cache cleared） | ✓ proven |
| ImageLoader（图片加载） | 失败 logErrorOnce 结果侧行（批 C） | ✓ proven |
| MathImageStore | 2 refs（快照失败行） | ✓ proven |
| Permissions / LiveOps / SvgRaster / FontFactory | 4 / 14 / 1（logOnce 光栅失败）/ 1（FONT category epoch 行） | ✓ proven |
| 设置族各页（Settings/Backup/Weather/Language/Gestures） | 每页 1-2 refs + Library/桥侧结果行（LANG applied、备份结局在 Library/DiagView 面） | △ 薄但有果侧行，见 E-05 |
| **纯呈现段零直接打点**（MomentApp.swift 内 struct 段 grep DiagLog = 0）：BlockState、Marks、EditorTextView、ZoomableImageView、ItemImageView、ImageBlockView、PhotoPicker、ListBlockView、SlashCmds、GalleryBlockView、MusicPillView、MdRender、MdImageView、MdSegsView、MdCalloutView、MdMathView、MdPreviewView、CardBlockView、VideoHolder/VideoBlockView、AttachmentRow/AttachmentBlockView、ImgTextBlockView、AvatarHolder、PdfMaker、ExportGen | 见 E-05 分层判读 | proven（零命中事实） |
| **整文件零 DiagLog**：MomentUndo.swift、MomentXSel.swift、TitleTapCaret.swift、MomentBridgeProtocol.swift、MomentBridgeTransport.swift、MomentBridgeQR.swift、MomentLiveOpsWidget.swift（appex，排除面）、MomentLiveOpsAttributes.swift | 见 E-05 | proven（零命中事实） |

### 3.3 判读（与用户硬规矩「每模块必备 Diag」的对照）

- 批 C 当年的取舍（audit_native_diag_rescue 完成注记：「块型视图逐块打点不加，Diag 是排障工具」）解释了呈现段零打点的**大半**：块型视图的结果侧证据由 EditorModel（59 refs，模型单点）与 ImageLoader（加载失败）承接，逐 View 再打点属噪音面。此口径下列为**已定案取舍**、不判违规。
- 但有三处不落在此取舍内，登记为新发现 **E-05**：① MomentUndo.swift（撤销引擎本体零打点，结果行由 EditorModel 调用点代记 `EDIT undo …`:6837-6980——代记在位，引擎内部去重/钳制分支无独立行，属「模块本体无打点、靠消费方代记」，与规范⑤『不在消费方打补丁』的精神相邻，定 inferred）；② VideoHolder/VideoBlockView（视频打开/播放失败零行——播放面归人工终判，但**失败**结果侧无痕与图片面不对称，proven 零命中）；③ PdfMaker/ExportGen（PDF 生成失败只 ErrBadge 硬编码文案 `PDF 导出失败`（:9615），无 Diag 结果行；MD/HTML 导出结局行在 EditorModel 面有记，PDF 面未见对等行，inferred）。
- MomentBridgeTransport 零打点：传输层断因经协调器 onSocketDown reason → Bridge.swift 的 BRIDGE state 行承接（呈现三件批 §3 已证 reason 全集自传输层两调用点钉死），属分层承接，不判缺口。MomentBridgeQR 生成失败回 nil、调用点（BridgeSettings）无失败行——影响仅「二维码不出图且无痕」，低危，记入 E-05 附带项。
- FFI 静默面残量：MomentApp.swift 内 `try?` 66 处。批 A 已治 persist/exportZip/putAttachment/retryLoad 四处会丢数据面；余下抽查点均为读面兜底（attachmentData 缺失回空 Data:1601、attachmentNames/Types 回旧缓存、libraryHash 回退:1702、avatarData:2257）——失败形态是「呈现降级」而非丢数据，且图片面有 ImageLoader 失败行兜底。判：无新增会丢数据级静默面（proven 抽查范围内）。

---

## 4. 存储与数据完整性

### 4.1 口径先行（任务书「SQLite 观察期/双写对账/IDB 副本面」的归属校正）

观察期口径属 **Web 端**（audit_sqlite_integration 阶段三）：`rust/apps/web/src/persist.rs` 三形态 Idb/Dual/Sqlite，Dual = SQLite 主写 + IDB 差量镜像、冷启逐篇哈希对账、SQLite 为准单向收敛（persist.rs:11-14、:457-467）；出口判据 ≥14 天且 ≥30 次冷启对账全等才切纯 SQLite（MEMORY.md 定案，矩阵 DAT-06 进行中）。**原生端自始即纯 SQLite 单库**（`Application Support/library/moment.db`，MomentApp.swift:481/:633），无 IDB 副本面、无双写——任务书该组口径在原生侧的对应物是：逐篇隔离、libraryHash 对账（桥卫生链/快照链真源）、ZIP validate-then-swap。以下按此对应面审，不把 Web 观察期未出口判为原生缺口。

### 4.2 原生存储逐项

| 项 | 应然 | 现状 | 级别 |
|---|---|---|---|
| 单篇坏数据不整库不可见 | 逐行容错 + 隔离落盘、失败宁阻断 | `list_memos_tolerant_impl`（storage/src/lib.rs:376-423）：坏行原文并入 meta `quarantine_json`（merge_quarantine 合并去重、原行不删不改），落盘失败整体报错；只读句柄跳过落盘（原文在源库行内保全） | proven |
| ZIP 导入 validate-then-swap | 全包解析校验毕才动库、单事务换库、坏包不污染 | FFI validate_backup 只校验不落库（ffi/src/lib.rs:194-209）；import 走 `read_backup_zip_migrated` 全量解析（上限 50MiB/3000 条/解压 200MiB，backup_zip.rs:14-17）→ `apply_package` 单事务 DELETE+逐篇插入+附件+manifest+归一戳同事务 commit（storage:233-285） | proven |
| 附件 manifest | put 带名同步登记、清单为文件名真值源 | `put_attachment`（storage:443-475）name 非空同步写 manifest_json；attachment_names/types 按清单出表（:478-516）；FFI put_attachment 带名参（ffi:133-145）。0.9.36 根治面无回潮 | proven |
| 附件本体 | 原生入 SQLite BLOB（与 Web 文件式分工，阶段二定案） | attachments 表 BLOB（storage:140-143）；导出全量回读入包（:640-660） | proven |
| 导出完整性 | 坏篇隔离随包、待删项排除、manifest 模型直出 | export_backup（storage:618-672）：容错序导出 + quarantine.json 附包 + deletedAt 排除 + manifest lenient 兜底 | proven |
| 差量同步/对账原语 | sync_library 差量 + 逐篇哈希 | storage:746-868（sync_library/SyncStats）+ fnv1a_64/library_hash（:95-107），phase2_sync.rs 测试在位；Swift 侧 libraryHash 经 FFI 供桥卫生链 | proven |
| 只读打开 | 不建表不写盘、探针拒非 Moment 库 | open_readonly（storage:186-213）READ_ONLY + sqlite_master 探针；FFI 第二构造子（ffi:78） | proven |
| 归一版本戳 | 开库戳低先整库归一 | NORMALIZE_VERSION + meta 戳（storage:82-95、apply_package 同步落戳） | proven |
| FTS | trigram CJK、短查回退 LIKE | storage search（:580-607）：≥3 字 FTS5 trigram 短语、<3 字 LIKE | proven |

### 4.3 Web 观察期面（顺带核，非原生领地）

persist.rs 的 Dual 形态、冷启对账（reconcile_if_needed 仅 dual 且未迁移/未导入/未降级时执行、SQLite→IDB 单向）、drift_counts 纯函数 + 测试、硬失败降级只读 + 横幅——代码面与阶段三设计一致（proven 静态）。**出口未达**：矩阵 DAT-06 仍「进行中」，本轮无 Diag 判读材料可证 ≥14 天/≥30 次全等——unknown，取证 = Web Diag 的 SQLITE backend/reconcile 行长期判读（发版清单面，非本片可代判）。

### 4.4 数据面残余风险（静态）

- `list_memos`（非容错版，storage:352-363）仍在 crate 内：一行坏全表抛错。其消费面须恒走 tolerant 版——FFI list_memos_json 已走包装形 tolerant（ffi 测试:540-550 断言包装形 + quarantined 计数）；crate 内旧函数属内部面，Swift 不可达。判：无端上风险，登记备查（inferred）。
- 导入两段（validate 与 import 之间文件被替换）无 TOCTOU 守卫：import 自身重走全量校验后才换库，坏包仍不污染——最坏结果是「校验 A 包、导入 B 包（仍合法）」，数据完整性不破。判：不成立为缺口，不登记。

### 4.5 FFI 契约逐项（抽查④详账）

导出面（rust/crates/ffi/src/lib.rs）：构造子 2（open:65、open_readonly:78）+ 方法 16（memo_count、list_memos_json、upsert_memo_json、remove_memo、attachment_data、put_attachment、attachment_names_json、attachment_types_json、avatar_data、set_avatar、attachment_ids_json、search_ids_json、validate_backup、import_backup、export_backup、library_hash，:85-228）+ 自由函数 5（md_classify:293、md_is_block_preview:311、md_parse_json:319、render_mathml:328、run_phase0_checks:338）= **23**。
契约测试 `checksum_contract_matches_bindings`（ffi:552-587）断言恰 **23** 条，与导出面逐名对应、无多无漏；verify [6] 以 bindings 期望值与 ffi 断言表双向比对、文案「23 项」。**三方一致（proven）**。checksum 含文档注释的红线口径在契约测试头注（:553-561）明文在位。

---

## 5. 冷启与滚动性能面（静态审；运行时一律 unknown + 取证法）

### 5.1 冷启链

- 结构：Library.init 同步只做判定 + 快照 + arm 看门狗（不开库）；load() 经 ListView.onAppear 触发、+0.05s 后台队列开库（MomentApp.swift:1048-1055）、reload 后台解析、主队列回填；refreshAttachmentTypes 延后 didLoad 后 +0.3s（deferRefreshAttachmentTypes 口径，:1630 段守卫注释）；种子仅空库；Diag 结构写盘延后（S9）。与应然（首帧前只做渲染与开库两件事）基本同构（proven 静态）。
- 残余静态点：① DiagLog.loadIfNeeded 在首个 log 调用点（LangStore.init 内）同步解码 today + 至多 60 份归档——audit_native_launch_crashsurface F-7/§四.4 当年列「应延后」，现行 loadIfNeeded（:4611 起）仍为同步直读形态，**未见异步化落码**（proven 未落；影响量级 unknown，取证 = 冷启 Diag `SMOKE 冷启完成 … 数据<ms>` 行与首帧 ms 的版本间对比）。② 开库步前 0.05s 人为延迟属面包屑定案口径，不判。
- 量测面：SMOKE 成功/失败双行、BOOT snap、CREATE settle 九段、TRANSITION build 段——量测仪器齐（proven）；实际耗时数值 unknown（取证 = 桥 diag_search `SMOKE|CREATE settle` 或 Diag 导出）。

### 5.2 编辑器构建与滚动

- **全量实例化、无窗口化（proven 静态）**：编辑器内容层 ScrollView + VStack + ForEach 全块（MomentApp.swift:13200-13205），无 LazyVStack；EditorModel census 头注自陈「呈现层全量 VStack 实例化、无窗口化」（:6502-6505）。长文档（500/1000 块）的打开耗时与滚动帧率因此无结构性护栏——矩阵 EDT-58 已登记「量测已落、虚拟化护栏未立（阈值：1000 块 build ≳1000ms 或滚动掉帧成串再立项）」。本片判：**旧账维持，非新发现**；运行时定级 unknown，取证 = `EDIT open census`（blocks/chars/init ms）与同 id `TRANSITION build=` 对读、桥 metrics/Diag 均可达。
- 滚动健康：SCROLL 行族在位（open/close/base/轨迹节流 ≥24pt，:11165/:11204/:13261-13273）；编辑器间歇卡顿历史多轮未终判（矩阵 EDT-10），静态面无新证据——unknown，取证 = 真机卡顿时段 Diag SCROLL 行完整性 + SCENARIO drag_trace_review 同族判读法。
- 首页：窄屏 List（原生惰性）、宽屏 LazyVGrid（:19286/:19312），归组 GroupsCache 按 key 缓存（:18375-18530）、头像异步缓存（avatarCache:2225-2295）——列表面惰性口径成立（proven 静态）。

### 5.3 MD 解析与图片解码

- MD 下沉：分类/解析/块预览判定/公式 MathML 全走 FFI 四函数（MomentApp.swift:6659/:6677/:6697/:8588、renderMathml:14750/:14894），Swift 侧无第二解析器（proven）；解析结果按文本缓存于 BlockState（mdCache*:84-98），失效单点 invalidateMdCache 与 fix_md_cache_stale 不变量（done ⟹ blocks 是当前 text 的解析）在位。
- 公式图：MathImageStore 按 (字号×2, 明暗, tex) 缓存、串行单 webview（:14702 头注）；类别变更经点数变键自动换档（fix_dynamic_type_follow §5 注记口径，静态自洽）。
- **图片解码无降采样、无共享缓存（proven 静态，登记 E-04）**：`decodeImage`（:3719-3758）以 `CGImageSourceCreateImageAtIndex(src, i, nil)` 全尺寸逐帧解码，GIF 全帧组装 animatedImage；全仓 grep `kCGImageSourceThumbnail/CreateThumbnail/maxPixel` **零命中**；ImageLoader 为每视图 @StateObject 自持（ItemImageView:3955），无 NSCache/共享解码缓存（全仓 NSCache 零命中）——同图在列表/编辑/图片页多处出现时各自全尺寸解码。影响（大图/GIF 的内存峰值与滚动重解码成本）定 inferred，取证 = 真机大图备忘滚动时 Diag 无直接行，需以 Instruments/桥 app_state 内存面另行取证，或构造大 GIF 夹具经 uitest 场景量测。

---

## 6. i18n 五语全量

### 6.1 键数与深检（抽查⑥详账）

- 五包（rust/apps/web/lang/{zh-CN,zh-TW,en-US,ja-JP,ko-KR}.json）各 **429** 键、键集互等——本机 python 复算坐实（proven）。verify [9] 键数期望 429 的逐批账（307 基线 → … → 381 + 权限中心 48）在脚本注释内完整（verify_ios.sh:323-337 段）。
- 深检共源：`scripts/i18n_deep_check.py` 在位（文件头明示两脚本共读、禁抄副本）；verify_ios.sh [9]（:530-560 段）与 verify_rustweb.sh §7（:323-328）同源调用、fail-closed。本机实跑（`python3 scripts/i18n_deep_check.py rust/apps/web.`）**exit 0**：占位符 429 键五包齐平、动态认领 63 条（D1-D6，含 perm.* D4 四十条）、**僵尸键 0**、疑似漏译警告 2 行（ja-JP 16 键、zh-TW 55 键与 zh-CN 同值含汉字——7c 仅警告口径，繁简同形/专名为主，不判漏译）（proven，本轮实跑）。
- 同值抽查（参考数，非门禁）：en-US/ko-KR 与 zh-CN 全同值各 6 键（export.html/md/pdf 等格式名与专名）、ja-JP 22 键——均为专名/格式名形态，无整段未译迹象（inferred）。

### 6.2 未竟面（旧账）

- **I4 编辑器全域换键未落（proven）**：SlashCmds.all 24 条命令 title/sub 仍 zh-CN 字面直写（MomentApp.swift:5834-5858，如 title: "标题 1"、sub: "一级标题"）；同面硬编码用户文案约 35 处 Text/Button 字面（本轮普查：图片块「点击添加图片」:4004、「图片不可用」:4036；CardEditSheets「取消/保存」:9967-9968；头像菜单:11217-11222；附件入口:11300-11302；斜杠空态/链接表单:11737-11980；背景底表:12746-12812；导出面板:13009/:13050；反链:13339；双栏行:13555-13558；音乐 prompt:13816；附件行:15706；图文卡 sheet:15793/:15913-15916；PDF 失败徽章:9615）。包内 slash.* 59 键已备且被 Web 消费（深检不报僵尸的原因在此），原生未消费。矩阵 EDT-59/GLB-02/SET-15 已登记（I4 批）——**旧账维持，不另编号**；影响：非中文语言下编辑器面恒中文（proven）。
- EditorView 本体未声明 langStore 观察（段内 Lang.t = 0、langStore = 0）：桥远程切语言时编辑器内已换键文案的即时刷新面与 SET-15 登记一致（旧账）。
- 语言切换本体：LangStore 监听 locale 变更（followSystem 重解析，T-4 锚）、LanguageView apply/applyFollowSystem + LANG 行族——在位（proven 静态）。

---

## 7. Dynamic Type 真跟随全量

### 7.1 机制（抽查①前半）

- FontHub：`UIContentSizeCategory.didChangeNotification` 单点监听、category + 单调 epoch、变更记 `FONT category -> … epoch=…` 行（MomentFontFactory.swift:34-78）——在位（proven）。
- FontFactory：UIFontMetrics 以 hub 显式 traits 计算、UIFont 构造单点（同文件:80-127）；Marks.dynFont 委托工厂（MomentApp.swift:2484）。白名单 2 处未缩放基准（capsuleHeight 参照字体，:12676-12683 的 `UIFont.systemFont(ofSize: 14/10)`）与 DT36-1 在册口径逐值吻合——本轮普查数字字面字号全集恰此 2 处（`UIFont.systemFont(ofSize: 10)` 另一命中在同段 m0 基准，同属白名单两式之内；`.system(size: <数字>)` 字面 **0** 处，其余全为 `.system(size: f<变量>)` 喂点）（proven）。
- UIKit 三面 adjustsFont 置真：BlockTextView（:3040）、MdTextGroupView（:14038）、TitleTextField（TitleTextField.swift:162）；epoch 重刷门：BlockTextView updateUIView epoch 支（:3331-3360，持焦只换 font/typingAttributes + pendingFontRefresh、组字中不消费 epoch）、EditorView/EditorHeaderView/MdBlockView 三点观察 FontHub（:10701/:12077/:14219）（proven 静态）。
- 语义样式残留普查：四文件（MomentApp/MomentRescue/MomentBridgeSettings/MomentPermissions）+ TitleTextField 的 `.font(.<语义样式>)` **0** 处；MomentLiveOpsWidget.swift 8 处语义样式——appex 目标、按 fix_dynamic_type_follow §2 范围外定案（排除面，仅登记）。

### 7.2 0.9.58 实报三面逐点（抽查①后半）

| 实报面 | 接入证据 | 级别 |
|---|---|---|
| 搜索胶囊·触发层 | 图标 `.system(size: f17)`、文字 groupFontSize（ListView @ScaledMetric f14 同源，:18382），MomentApp.swift:19146-19155 | proven 静态 |
| 搜索胶囊·展开层 | 图标与字段同走 f15（:19112/:19121），ListView ScaledMetric 声明:18399-18410 段（f15 relativeTo.subheadline） | proven 静态 |
| 新建卡片（行/方卡） | newCardRow（:19734）与 newCardSquare（:19432）均 f16 标题 / f12 meta / 天气 f16+f12——两形态同账 | proven 静态 |
| 编辑器 | 正文 epoch 重刷（上行）+ EditorView ScaledMetric 喂点组（:10710 段）+ 标题字段 adjustsFont + EditorHeaderView 观察 hub 驱动胶囊量测重算 | proven 静态 |

运行时终判（改系统字号 L→XXXL→AX2 逐面随动）仍归真机清单（fix_dynamic_type_follow §6 十一项），本片不升级表述——unknown（取证 = 真机改档 + Diag `FONT category` 行核对）。

### 7.3 残余

- 字形封顶 9 点（DT36-2 八类计数 + 手势图示 min(f25,25) 全程压平）：封顶值本轮未逐个复核（沿 fix_dynamic_type_follow §3 给数表）；手势图示压平与头像不跟随（AvatarView 72 固定）两项为**待用户终判的设计决定**（旧账，报告 §6 单列），不判缺陷。
- 固定尺寸文字容器白名单（DT36-7 五类）计数锁在脚本内，本轮未实跑 verify，不复述结论。

---

## 8. 深色模式全量

### 8.1 机制

- 令牌单源：`enum T`（MomentApp.swift:15962 起）以 `dyn(light, dark)` trait 闭包 UIColor 为唯一色源（:15963-15968），与 Web tokens.css 逐值对齐（段头注:15961）；数据色工厂 memoBg/colorOf 为在册白名单（用户备忘底色，非 chrome）。
- 正文显式前景：Marks.attributed 与 MdRender.attributed 双构建器 `baseColor` 同签名、普通 run 恒带 `.foregroundColor: baseColor`、BlockTextView.baseColorUI 单点三面同喂（attributed/typingAttributes/textColor）、`tv.textColor =.label` 死通道 0 处——DM45-3/4 锚文在本轮 grep 下逐项命中（proven 静态）。
- checkBorder 深值 `dyn(0x73737A, 0xB5B5BB)`（:16064）与 tokens.css:227 对正；onAccent/termText/termBg/doneTextUI/codeBgUI/linkBlueUI 归令定义齐（:16069-16243）。

### 8.2 裸字面普查（抽查②详账，本轮实测）

- `(Color|UIColor)(red:` 代码行全集 **8 行**，逐行定位：T 工厂 2（:16130 colorOf 的 UIColor 支、:16148 rgbOf 的 Color 支）+ 令牌定义 2（:16217 fillHighlightUI、:16225 fillAccent18UI）+ 开屏艺术 4（:21800-21802 splashColor 双支、:21982-21983 开屏底双支）——与 DM45-1 白名单**逐行同位、无新增**（proven）。
- `.foregroundStyle(.white)` 全仓 **0**；`T.onAccent` 用点 MomentApp 5 + MomentRescue 1（:4429/:11982/:19421/:20082/:21020 + Rescue:144），与 DM45-2 计数吻合。
- `Color.white` 残量：MomentBridgeSettings.swift:240 二维码白底板 1 处（在册白名单，深色下可扫性）；余皆开屏 Canvas 艺术渐变（:22039-22513，colorScheme 双支显式构造，白名单艺术面）与 gallery 角标 palette（:13731 `.white / Color.black.opacity(0.55)`，图上控件白名单）。
- `Color(hex:` 命中均为数据面（备忘底色板 bgColors:12848、开屏资源 tagline/stops 数据驱动:22090/:22153/:22394-22422）——非 chrome 写死色。
- HTML 导出模板内联色（:9815 `<style>…color:#1a1a1a…`）：导出文档自带样式、与 app 外观无关，不判残留（备查）。

### 8.3 残余

- 外观热切换运行时终判（编辑页开着切深/浅、正文即时翻转、持焦新键入色）仍归真机（fix_dark_mode_full §五清单）——unknown，本片静态面无回潮证据。
- 待办完成文观感（深色下是否仍判过淡）为该报告遗留的终判复核项，非静态可判——unknown。

---

## 9. 新发现登记（E-01…，与旧账分开）

### E-01 开屏资源解码 fatalError + 渐变下标无守卫 + verify [8] 只查存在性
- 证据：`NativeSplashArtwork.load` 解码失败走 `fatalError`（MomentApp.swift:22066-22073）；`NativeSplashGradient.init` 对 `resource.start[0]/[1]、end[0]/[1]` 直接下标（:22150-22151），Decodable 不保证长度 ≥2；`SplashHostView.resourcesReady` 只验文件存在（:21787-21793）；verify [8] 对两份矢量 JSON 只查在位（verify_ios.sh [8] 段），无解码级断言。
- 沿革：此即 audit_native_launch_crashsurface（0.9.43）F-2/F-3 与 §四.1/2 的隔离建议——该报告当年以「交付 ipa 资源已静态验合」排除当版触发，但**结构根治（降级 artwork + count 守卫 + 构建期解码断言）至今未落**，现行树仍同形态。
- 影响面：bundle 内任一矢量 JSON 漂移（字段/数组长度）→ 首帧画布求值即 trap、点开即闪退且 Diag 零行（哨兵步停在场景前）。触发概率低（资源随包静态），后果为启动级。建议按原报告 §四.1/2 落降级 + 守卫 + [8] 解码断言。

### E-02 ops_validate 把不可 guard 的核心步名报为合法
- 证据：`knownOpsSteps`（MomentBridgeOps.swift:166-176）= LaunchStep 全集（含 open/openFFI/readList/readParse/seed/rehydrate/firstFrame/session/scene* 等核心步）∪ OpsStep 全集；opsValidate 以此集判 `invalidSteps`（:203-213）。而 MomentOps.swift:14-20 红线明示核心步不设 guard、点名无效，sanitize 亦不校验步名。
- 影响面：发布者以 ops_validate 预检「点名开库步」会得 valid=true 的错误预期，指令上线后该步永不跳过且无任何报错面（guard 精确匹配、惰性无害——数据面无损，失真在预检口径）。矩阵 LCH-08/LCH-14 已登记此子项方向（「合法步名给发布者错误预期」），本条为其现行码坐实：应拆 guardable/unguarded 两集回读（unguarded 单列字段），或至少在回报中标注核心步不可禁。

### E-03 DiagLog 落盘非原子写，崩中可写坏整日日志
- 证据：DiagLog.write 以 `try? data.write(to:)` 无 `.atomic`（MomentApp.swift:4604-4609），persist/persistToday 均经此写 today.json/archives.json（:4704-4714）；read 侧 try? 解码失败即整表丢弃（:4596-4602）。对照：哨兵 LaunchSentinelStore 与 ops 缓存均 `.atomic` 直写（MomentLaunch/MomentOps 在位），Diag 为全家唯一非原子落盘面。
- 沿革：audit_native_launch_crashsurface F-7/§四.7 已建议原子化，未落；R3 分文件拆分只拆出口、未动 write 本体。
- 影响面：进程恰在写盘中被杀 → today.json 半写损坏 → 下次启动整日 Diag 蒸发（恰是最需要日志的崩溃场景）。修复面小（write 加.atomic），建议随下批落。

### E-04 图片全尺寸解码 + 无共享缓存
- 证据见 §5.3：decodeImage 全尺寸逐帧（:3719-3758）、缩略图 API 零命中、NSCache 零命中、ImageLoader 每视图自持。
- 影响面：大图/多帧 GIF 在列表+编辑+图片页重复全尺寸解码，内存峰值与滚动成本无上限护栏；与 EDT-58 长文档护栏同属「量测在位、护栏未立」族。取证 = 大 GIF/大图夹具 + Instruments allocations，或桥 app_state 前后内存面对比。

### E-05 Diag 本体零打点模块三处（Undo 引擎 / 视频面 / PDF 导出面）
- 证据见 §3.3：MomentUndo.swift 全文 DiagLog 0（结果行靠 EditorModel 消费方代记）；VideoHolder/VideoBlockView 段 DiagLog 0（播放失败无结果行，与图片面 ImageLoader 失败行不对称）；PdfMaker/ExportGen 段 DiagLog 0 且失败仅 ErrBadge 硬编码文案（:9615）。附带：MomentBridgeQR 生成失败回 nil 无行（低危）。
- 对照：用户硬规矩「每模块必备 Diag」与规范⑤（不在消费方打补丁）。呈现段零打点的大半有批 C 定案取舍承接（§3.3），此三处不在取舍内。建议：Undo 引擎关键分支（去重跳过/钳制/恢复失败）自记 EDIT undo 行、视频打开失败与 PDF 生成结局各补一条结果行，代记面随之收敛。

### E-06 安全模式布防 reason 呈现——报告称已落、现行码未检出
- 矛盾：fix_bridge_presentation_trio §0 表称「§5.5(a) 布防 reason 上屏：救援布防批 0.9.57 已落，RescueView 状态区附读审计 reason 一行」；矩阵 LCH-15 仍登记为缺口待「桥呈现小批」；本轮在 MomentRescue.swift/MomentApp.swift 以 reason 为词根筛 rescue/arm/safe 呈现点**零命中**。
- 判：三方口径不一致，静态无法定案（可能落在审计文件读面而词根不同）。取证 = 桥 rescue_arm_safe_mode 布防 → 下次启动进安全模式 → RescueView 状态区是否有一行 reason；或回读救援布防批报告原文核对落点文件。定案前不判缺口、不判已落。

---

## 10. 旧账汇总（已登记、本片只回状态，不重复编号）

| 旧账 | 来源 | 本片回读状态 |
|---|---|---|
| M3b 写景运行级验收（BRG-04/05、language_roundtrip write 配对） | impl_bridge_m3a §8、矩阵 §4.9 | 未落，维持 |
| M3c safe_mode_drill / cache_clear_drill（LCH-03/06） | 矩阵 §4.8 | 未落，维持 |
| LCH-13 只读桥回码 | 矩阵 §4.8 | **已落**（§1.3），矩阵待回写 |
| LCH-14 effectiveScope 主项 | fix_ops_effective_scope | **已落**；残余 = E-02 |
| LCH-15 布防 reason | 矩阵 §4.8 | 口径矛盾 → E-06 待核 |
| BRG-11/12/13 呈现三项 | fix_bridge_presentation_trio | **已落**（§1.3），矩阵待回写 |
| I4 编辑器换键（EDT-59/GLB-02/SET-15） | 矩阵 §4.10 | 未落，硬编码面清单见 §6.2 |
| EDT-58 长文档虚拟化护栏 | 矩阵 §4.3 | 量测在位、护栏未立（§5.2） |
| EDT-10 编辑器滚动健康终判 | 矩阵 §4.2 | unknown，取证法见 §5.2 |
| DAT-06 Web 观察期出口（≥14 天/≥30 次） | 矩阵 §4.10 | 进行中，Web Diag 长期判读（§4.3） |
| DT 头像不跟随 / 手势图示压平 | fix_dynamic_type_follow §6 | 待用户终判的设计决定 |
| 深色/DT 运行时终判清单 | fix_dark_mode_full §五、fix_dynamic_type_follow §6 | 归真机，本片静态无回潮 |
| appex 去捆绑过渡（BUNDLE_WIDGET_EXT=0） | release_0.9.61 | 已知状态（§2.5），等个人 Developer 账号 |

---

## 11. 审计边界声明

- 本片为静态只读审计：未跑构建/冒烟/verify 全量，未连桥实跑，未上真机。凡标 proven 者均为源码/脚本/复算层证据；运行时行为（DT 随动、深色热切换、续连命中比、OPS 收敛实跑、看门狗触发、滚动帧率）一律 unknown 并已逐项给取证法（Diag 行名/桥工具/场景 id）。
- verify 断言只核「脚本在位 + 锚文与现行码对得上」，未实跑的组不声称绿。
- 状态栏采样面（MomentStatusBar.swift / MomentStatusBarBridge.swift）与 appex 本体、APNs/iCloud 本体按任务书排除，未审、未计入任何普查（普查脚本已剔除两文件；DT 语义样式普查中 Widget 文件的 8 处按既有范围外定案仅登记）。
