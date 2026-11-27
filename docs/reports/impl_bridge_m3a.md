# 桥 M3a 落码报告：场景与指标四件工具（清单 31→35）

依据：plan_bridge_m3.md（§3 门归属、§4 场景引擎与 journal、§5 场景目录与红线）+ plan_selftest_coverage.md §5（矩阵裁定 metrics_create_settle 随 M3a 补出）。落码门：组版提交 HEAD 6ce6cd8 落定后开工；多批同树在途，动工前 git diff 全量快照、逐 hunk 避让，完工复验他人 hunk 完好（见 §6）。App 侧未提交、未 bump；中继已部署并逐字节复核。

## 1. 四件契约

| 工具 | scope 面 | 形态 |
|---|---|---|
| scenarios_list | read | 注册表全景：每景 id/名称/相位/声明 scopes/高危位/须指令位/参数表/证据分级 + 按当前配对实时计算的 availability（可跑或点名缺层） |
| scenarios_run | **不入任何 scope 集**（中继与 App 两侧同） | 受理即回 runId 异步跑；逐景 scope 由 App 注册表声明、分发器受理时一次性验足（scope_denied 点名缺层）；参数面 = 注册表声明的标量键，表外键/类型错/必填缺 → invalid_params；与 uitest 共用单运行互斥，占用中回 run_conflict；高危景（M3a 无）走既有两段提交 |
| scenarios_get_result | read | 按 runId 回证据包：状态/终局 code、逐歩断言、量测、结论（全程只有 id/哈希/计数/Diag 行，零正文）；journal 已清理回 run_not_found |
| metrics_create_settle | read | 解析端上 CREATE settle Diag 行（create/model/dest/appear/listpass/avatar/bodypass/claim/kb 九段，na → null），参数 memoId/limit/sinceTs；只出数与原始行，不下阈值结论 |

错误域注记：run_conflict、journal_write_failed 为工具级错误码；hygiene_failed、language_left_changed、resume_condition_mismatch 只作 get_result 证据包的 code/conclusion 字段值，不是工具错误（已同步 MomentBridgeProtocol.swift 头部注记）。

## 2. 场景目录（M3a 首批四景，注册表 = MomentBridgeScenarios.swift）

- **drag_trace_review**（read，single）：DRAG Diag 行按 press 尝试切分链路，逐链判 pickup/drop/cancel 完整性、缺环点名，reject/disarmed/norow 只入汇总；空窗回空结论不判失败。证明的是打点链，拖拽手感仍归真机终判。解析器 BridgeDragTraceParser 即矩阵 §5「同一解析器两期接入」中 U3 metrics_drag_trace 的共用解析器先行形态，U3 期只做 Diag→工具面的薄封装，禁双轨。
- **weather_settings_flow**（read，single）：双 key 状态（仅状态/来源、零值）读取 → 走 App 既有 refreshIfNeeded 触发一次 → 状态复读断言不变；缓存命中与网络终局（WEATHER 行）双路判读；provider 失败（额度/网络）是证据结论 refreshOutcome，不判整场红。
- **ops_convergence**（ops，crossRestart）：A 段拉双源（fetchWithOutcome）、缓存收敛断言（cache 哈希 == sourceHash，可选 expectedHash 钉死）、挂起 awaiting_manual_reopen；B 段（重开后钩子续跑）断言 bootApplied 与 cache 两哈希均等 sourceHash，结论 converged/diverged + LAUNCH 行附证。
- **language_roundtrip**（write，single）：写前快照（ensureSnapshot，idempotencyKey=scenario:<runId>）→ 切 code（默认 zh-CN）验生效 → 切回原 preference 验恢复；切回失败不静默，终局强制 language_left_changed 红标 + 当前 code 与手动切回提示。

## 3. 引擎与 journal

- 引擎 BridgeScenarioEngine：单会话段 120s 硬顶（挂起段不计时，靠 7 天过期）；步进串行、每歩落 journal（Application Support/bridge-scenarios/runs.json，保留最近 10 个 run，steps/evidence 以 JSON 串存）；收尾做卫生对账——仅 single 相位景做 pre/post libraryHash 对账，不等降格 hygiene_failed（跨重启景挂起窗含用户正常使用，只记账不降格）。
- 续跑双钩子：钩子一 = BridgeCoordinator.start 尾（opsDisabled 早退之后、正常路末尾）resumePendingRuns(via:"boot")，续跑条件 originBootSessionId ≠ 当前 boot；钩子二 = MomentBridgeOps.rescueTryNormalStart 在 prepareNormalStart()+bootMode=.normal 后 noteModeFlippedToNormal，条件为同 boot。boot 落安全模式 → failed/resume_condition_mismatch 并在结论注明；场景已删 → scenario_missing；互斥被占 → 2s×15 重试后留待下个钩子（SCENARIO resume deferred 打点）。
- 互斥单点归 UITestDriver（tryClaimExternalRun/releaseExternalRun），场景与 uitest_run 共用，挂起/收尾即释放（挂起窗不占锁）。
- 写景夹具守卫（UITestFixture.isFixture）已在引擎 ctx 备好供 M3b；M3a 四景 fixture 均为 none，本批不造夹具代码孤儿面。
- SCENARIO Diag 模板六件：run begin/step/suspend/resume/hygiene/run end（B27-8 守）。

## 4. 落码清单

- 新增 rust/apps/ios/app/MomentBridgeScenarios.swift（1,911 行：描述符/注册表/参数面校验/可用性/journal/引擎/四景/两解析器/四件工具面）。
- MomentBridgeProtocol.swift：toolNames +4、头部注记改 35 件与错误域归属。
- MomentBridgeTools.swift：scenarios_run 受理门块（注册表查 → validateParams → 逐景 scope 验足 → 库在位 → read_only → ops_disabled，与 uitest_run 同序同码）；两段提交条件扩为「声明高危的场景」；switch +4 case。
- MomentBridgeUITest.swift：+tryClaimExternalRun/releaseExternalRun。
- MomentBridge.swift：start 尾钩子一。MomentBridgeOps.swift：try_normal 翻转点钩子二（按布防批落地后现行形态接入）。
- build-app2.sh：新文件进全部 18 处编译遍名单 + 专属 primary 遍 + 链接行 bridge_scenarios.o。tree-sync/push_small.py 名单 +1。
- verify_ios.sh：B16-3/B16-15 改 35 件口径；新增 [27] 组 B27-1…B27-9（构建名单/注册表/声明制门/正文红线/journal 与卫生/快照纪律/受限集排除/双钩子与打点/描述符完整性）。B25-10 镜像断言随 B16-3 枚举同步自动覆盖新四名，已实测绿。
- bridge/relay/worker.js：TOOLS +4（scenarios_run 不入 OPS/WRITE/UITEST 任一集，超时走默认 READ 15s——受理即回 runId 足够）+ 头部注记。已部署（见 §5）。
- 连接器 bin/client.py：ALLOWED_TOOLS +4；READ_RETRY_TOOLS +3（scenarios_run 不入——有副作用）。CONNECTOR.md 补 M3a 段。

## 5. 清单哈希三方对账（31→35）

- 公式 sha256("2025-06-18|" + 工具名排序逗号连接)：31 名复算 = a52116c38d2f…（与现行一致，公式先证）；35 名 = **ec9fbc90890f1f2751ab6fecc7cf856472371cc727b0bb3f6950c1103a6beb32**（34 名旧算作废，不采用）。
- 中继：部署走 bridge/relay/deploy.py（PUT 200）；部署前拉线上脚本与仓库版 diff = 58 行、全部为本批 M3a 增量（续连批的中继改动此前已上线）；部署后拉取逐字节比对 = 一致（53,288 B）。
- 连接器：线上 list-tools 实回 35 件，按回读名集复算哈希 = ec9fbc90… 命中。
- App 侧：BPROTO toolNames 35 名与中继名集 diff 空（verify B16-15 绿、B25-10 镜像绿）。现行装机 App 仍为 0.9.57（31 件清单、哈希 a52116c3…），App 侧哈希切换随下一组版生效——此为预期状态，不是漂移。

## 6. 验证（本机编译级自检，全量冒烟归 tree 组版流程）

- Swift primary 遍编译：MomentBridgeScenarios.swift 及另五个改动桥文件逐个以 build-app2.sh 同旗标编译，零诊断（MomentBridge.swift 一条 warning 为既有 kcGet 代码，非本批）。其后 U4a/续连批并发落码改变 UITest/Bridge 文件，再以当前树全量文件集重编场景文件 primary 遍，仍零诊断。
- verify_ios.sh：340 ✓；[27] 九条与 [16] 相关条全绿。仅剩 2 红为产物陈旧类（本机 ipa 早于在途他批源码、语言包未随构建刷新），组版在 tree 重建后自然消除，非本批引入。
- B27-4 反证：在场景文件副本的代码行注入 key:"text" 参数声明，断言 grep 口径命中（红线可抓）✓。
- 并发完整性：完工时复验——钩子一在 start 尾位置正确、钩子二在位、UITest claim API 与 U4a 新增六景共存、续连批 resumeToken 代码完好；build-app2.sh 中权限批 liveops 遍与 verify [32]/[33] 组均在位未损。
- 桥活验：部署后 bridge_status 路由正常（回 app_offline——App 后台挂起断连属设计行为，且装机 App 尚无新四件）；设备侧实跑归 §7 终判点。

## 7. 真机/桥终判点（新包上线 + App 前台时执行）

1. scenarios_list 回读：四景在册；language_roundtrip 在现配对（read+ops）下 availability 应标 scope_missing:write（见 §8），余三景可跑。
2. drag_trace_review、weather_settings_flow、ops_convergence 各跑一遍，证据包逐项判读（ops_convergence 须走完挂起 → 手动重开 → 钩子续跑 → converged 关单全程）。
3. metrics_create_settle 在有新建备忘操作后回读，九段数值与 CREATE settle Diag 行逐项对账。
4. §6.8 出包回归子集随组版流程执行。

## 8. 明示：write 级场景实跑验收归 M3b

language_roundtrip 声明 write scope，现配对为 read+ops——清单与可用性口径已按预期标 scope_missing，**这不是故障**。该景（及 M3b 全部写景）的实跑验收必须等用户以 write 档重新配对后进行，归 M3b 批次；本批交付不阻塞于此。场级两段提交机制本批已随分发器落码，但 M3a 四景无高危景，首次行使同样在 M3b。
