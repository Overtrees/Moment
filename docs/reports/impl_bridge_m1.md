# MCP 桥 M1 落码报告（连通 + 只读）

日期：2026-11-27。依据：`plan_app_mcp_bridge.md`（M1 范围钉子优先于
方案全集）。状态：**落码完成、未提交、未在 tree 构建**（0.9.49 冒烟
占用 tree，构建由主线在本批落版时统一跑）。本机自检：新增 Swift 六
文件 swift-frontend -parse 全过；verify_ios.sh 本机跑 [16] 组七项全
绿、[9] 源侧全绿；全量 verify 仅剩两条「本机无构建产物」红（ipa 陈
旧、产物语言包缺失），tree 构建后自然消除。

## 一、中继（已部署上线）

- 代码：`bridge/relay/worker.js`（模块格式单文件，含 Durable Object
  类 `BridgeRoom`）+ `bridge/relay/deploy.py`（部署脚本）。
- 部署坐标：Cloudflare 账号 Overtrees
  （`4c3178949cce0a3db4f993a3e14712a6`），Worker 名 `moment-bridge`，
  workers.dev 子域已启用，地址
  **https://moment-bridge.overtrees.workers.dev**。
- 部署方式：cf.py 的 `workers put` 以 application/javascript 裸传、
  无 metadata，部署不了 DO 绑定——deploy.py 复用同一凭据代理
  （dynamic_credentials surrogate，令牌不落文件/日志）走 multipart
  模块上传（metadata 含 main_module + durable_object_namespace
  绑定）。免费计划要求 SQLite 后端命名空间，迁移以
  `new_sqlite_classes: ["BridgeRoom"]`（tag v1）建成（首轮 403 错误
  10097 即此口径，脚本已内置自动重试）。
- 端点：`GET /health`、`POST /pair/start`、`GET /pair/status`、
  `GET /pair`（配对确认页）、`POST /pair/confirm`、
  `POST /pair/revoke`、`GET /app/connect`（WSS，挑战-应答鉴权）、
  `POST /mcp`（助手面 Streamable HTTP，Bearer
  `mb1.<pairingId>.<secret>`，中继只存 sha256(secret)）。
- DO 一配对一室（pairingId 的 sha256 命名）：配对记录（设备公钥、
  指纹、能力位、凭据哈希、状态、epoch、调用计数）、Hibernation
  WebSocket、请求 id 映射与截止（只读 15s / ops_refresh 20s）、
  单活连接顶替、按配对限速 120 次/分钟。中继零业务存储。
- 已实测：`/health` 回 `{ok:true, service:"moment-bridge"}`；
  `/pair` 页渲染正常（指纹 + 三档能力勾选）；未知配对
  `/pair/status` 回 404。带凭据的 MCP 全链（initialize/tools/list/
  tools/call 转发）须待 App 侧配对完成后做首轮连通验证（见第四
  节待办），本轮未替用户配对、无从实测。
- 协议版本钉 `2025-06-18`；工具清单 11 件与 App 侧 manifest 逐字
  对齐，manifestHash = sha256(`2025-06-18|` + 工具名排序逗号连接）
  三方（中继/App/连接器）同算式。
- `ops_get_sources` 由中继侧执行（双源拉取 + 白名单清洗 + 规范
  JSON 哈希 + 双源一致判定，标 `origin:"relay"`）。一处口径说明：
  该工具不回「与 App currentCache 是否一致」——中继无从知晓 App
  缓存，该问题由 `ops_get_effective` 的 `converged` 字段承接回答。

## 二、App 侧（六新文件 + 四处接线）

新文件（`rust/apps/ios/app/`，方案 §9.2 划分中 M1 的六个；
MomentBridgeSnapshots / MomentBridgeDocumentService 属 M2，未建）：

- `MomentBridgeProtocol.swift`：常量（中继域、协议版本、帧上限
  1MiB、Diag 回读 256KiB 上限）、11 件工具清单与 manifestHash、
  规范 JSON（sortedKeys）与 sha256、MCP 结果/错误构造。
- `MomentBridgeTransport.swift`：出站 WSS（URLSessionWebSocket
  Task）、收帧循环、帧上限守卫、断开上报。不做后台保活假象。
- `MomentBridge.swift`：设备身份（Keychain P-256 密钥对，指纹 =
  sha256(公钥 X9.63 原始表示) 前 16 hex 分组，挑战签名 DER）+
  协调器状态机（off/unpaired/pairing/connecting/connected/
  backoff/revoked/opsDisabled）、配对客户端（生成 pairingId →
  /pair/start → 轮询 /pair/status → 落 Keychain 并连接）、心跳
  20s/50s 超时重连、退避 1s→30s 带抖动、前后台在场帧、断开并吊
  销（本地删配对记录与设备密钥 + 设备签名向中继吊销）、最近调
  用环形留痕（20 条，只记工具名/结果码/耗时）。配对元数据与私
  钥只进 Keychain；UserDefaults 只存开关 `bridgeEnabled`（默认
  关，verify B16-2 锁凭据零 UserDefaults）。
- `MomentBridgeTools.swift`：分发器 + 只读工具。边界：清单外工
  具回 unknown_tool；安全模式受限形态（仅 bridge_status，其余
  safe_mode_limited）；ops_refresh 需 ops 能力位。工具实现：
  bridge_status、app_state、diag_tail（scope/limit/minLevel/
  beforeTs 游标 + 字节守卫）、diag_search（字面子串/正则，App 内
  执行）、notes_list（游标分页，默认不含待删）、notes_search
  （走 Library 只读访问器，同 App 搜索口径、不扰动 UI）、
  notes_get（块分页；文本块回正文/runs/勾选，原子块只回类型 +
  attrs 元信息）。docHash = persist 同构落盘文档（raw 为底 +
  doc 键换 flushedNode 序）的规范 JSON sha256。
- `MomentBridgeOps.swift`：ops_get_effective（三层：bootApplied /
  currentCache 含文件 mtime+sha256 / lastFetch + converged）、
  ops_refresh（回逐源成败、缓存哈希、Diag fetched 行、
  effectiveFrom=next_launch）、rescue_status（与救援页同源：哨
  兵文件/DB 字节/Diag 计数/启动模式/分发器形态）。
- `MomentBridgeSettings.swift`：设置二级页（ChromeView +
  glassCard 家族体例；系统 Toggle 默认关；状态行；配对区三态：
  未配对→开始配对、配对中→大字指纹 + 配对页入口 + 等待/取消、
  已配对→能力位 + 两段确认的断开并吊销；最近调用列表）。

既有文件接线（均为外科编辑；MomentApp.swift 只动 Library 区与
设置区，未碰导航呈现/编辑器入口——与并行过渡线区域不重叠）：

- `MomentApp.swift`：① Library 新增 `bootAppliedOps` 快照，判定
  入口落点、forceSafeMode 改消费快照（行为等价，R13-7 断言已同
  步改判快照形态）；② Library.init 尾异步派发
  `BridgeCoordinator.shared.start(library:)`（不进 init 同步链；
  安全模式下亦启动以便 rescue_status 可达）；③ Library 新增只
  读访问器 `bridgeSearchIds(_:)`；④ SettingsView：Sub 加
  `.bridge`、数据卡 diag 行后加桥 SetRow（meta = 链路状态文
  案）、destination 加 BridgeSettingsView。
- `MomentOps.swift`：OpsStep 登记桥步名 `"MCP桥"`（协调器启动时
  以 `isDisabled(OpsStep.bridge)` 守卫，点名禁用则桥不启动、不
  分发并记 tools_rejected）；`fetchFrom` 改为回带 `OpsFetchOutcome`
  （成功来源 + 逐源失败签名 net/http<码>/parse/url），新增
  `fetchWithOutcome`，原 `fetch` 行为不变。
- 语言包：五包各 +27 键（bridge.* 26 + settings.bridge 1，五语
  齐全、键集一致），键数基线 324 → **351**，verify [9] 期望已同
  步。**连带影响**：天气设置批（plan_weather_settings.md）原记
  「324→333」的键数增补以 351 为新基线顺延对账（verify [9] 注
  释已记明）。
- BRIDGE 打点（方案 §9.5）：start/state 迁移/pairing_started/
  paired/session up/tool（名+耗时+结果码）/tools_rejected/
  ops_refresh/presence/revoked/error(code+where) 已按清单落，
  verify B16-4 锁齐全性。

## 三、构建集成

- `build-app2.sh`：既有六遍各补桥六文件为次级输入；新增桥六遍
  （各以一桥文件为 -primary-file 出 .o）；链接行补六个桥 .o。
  **版本号未动**（见第五节 bump 点位）。
- `verify_ios.sh`：新增 [16] 组七项断言（B16-1 文件/中继/构建名
  单、B16-2 默认关与凭据落点、B16-3 工具集边界——写工具名在桥
  Swift 文件零出现、B16-4 打点齐全、B16-5 OPS guard + 受限分
  发、B16-6 三层回读源、B16-7 设置接线）；[9] 键数期望改 351；
  R13-7 判定消费断言改判 bootAppliedOps 快照形态（注释已记）。
- `~/workspace/tree-sync/push_small.py`：同步名单加桥六文件。
- 顺延未落（按父任务 M1 钉子）：方案全集里的 settings_get、界面
  量测两件、diag_sessions / diag_snapshot_meta / diag_export /
  diag_subscribe，以及全部写工具与运维动作（M2）、快照文件
  （MomentBridgeSnapshots，M2）。分发器对清单外工具一律
  unknown_tool，不留半成品入口。

## 四、配对授权待办（主线交付时执行，本轮未替用户授权）

桥的授权三道门本轮只做到「流程就绪」：App 内能开开关、能开始
配对、能看到指纹与配对页入口。剩下需要主线向用户申请/由用户
亲手完成的：

1. **实施授权**：主线向用户确认本桥正式启用（用户此前已指示接
   入并称权限全开，此项为落版交付时的正式确认）。
2. **设备配对（用户在 iPhone 上操作）**：装 0.9.50 后打开
   设置 → MCP 桥 → 开启开关 → 点「开始配对」；用常用浏览器打
   开页面上的配对页（或在 App 内点「打开配对页」）；**核对页
   面指纹与 App 显示的完全一致**；勾选能力（read 必选，write /
   ops 按意愿——M1 实际只用 read + ops 的 ops_refresh）；点确
   认配对。页面随后**一次性显示客户端访问密钥**。
3. **连接器凭据（用户在 Muse 安全凭据页操作）**：主线发起
   custom.moment-bridge 的凭据注册（bearer_header、host
   moment-bridge.overtrees.workers.dev），用户把上一步的密钥粘
   贴到安全凭据页——不要发到聊天里、不要存仓库。
4. **首轮连通验证（主线操作）**：凭据就绪后主线跑连接器
   list-tools 与 call-tool bridge_status（需 App 在前台且桥显
   示已连接），核对 manifestHash 三方一致，再逐个冒烟只读工
   具，形成 M1 验收闭环。

连接器骨架现状：`~/workspace/custom-connectors/custom.moment-bridge/`
已建 connector.yaml + CONNECTOR.md + `bin/client.py`（由
custom_connector_setup 的 mcp_client 模板配置：PROVIDER=
custom.moment-bridge、ENDPOINT=中继 /mcp、ALLOWED_TOOLS=M1
11 件、协议默认 2025-06-18）。**未实际注册、未填任何凭据**，
待第四节第 3 步由主线走 credentials 流程激活。

## 五、版本与 bump 点位（待 0.9.49 交付后以 0.9.50 落版）

本批不 bump。主线落版时改三处（verify [1] 自动对账）：

- `build-app2.sh`：CFBundleShortVersionString 0.9.49 → 0.9.50；
  CFBundleVersion 76 → 77。
- `MomentApp.swift` 设置页关于行：Text("0.9.49") → Text("0.9.50")。

原排 0.9.50 的天气设置批顺延 0.9.51（键数基线改以 351 起算）。

## 六、风险与待验证（主线落版冒烟关注）

- 本机只有 -parse 级语法自查；类型级错误（如 Keychain CF 桥接
  细节、SwiftUI 组合形态）只能在 tree 首轮构建暴露——桥六遍是
  新增编译面，冒烟红时优先看 last-build.log 中桥文件报错。
- 中继 MCP 全链与 App WSS 挑战应答未做端到端实测（须真实配
  对，属用户授权动作）：首轮验证按第四节第 4 步执行；若挑战验
  签失败，先查 DER→raw 转换与 nonce base64 口径（中继
  worker.js 的 derToRaw 与 App SecKeyCreateSignature 输出）。
- 工作树注意：MomentApp.swift 同时有并行「新建过渡重构」线的
  未提交改动（含未跟踪的 MomentEditorTransition.swift，该文件
  尚未进 build-app2.sh / push_small 名单——其构建集成归该线收
  口）；提交时主线统一对账，勿把对方改动误并入本批提交。
