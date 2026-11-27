# Moment iOS「App 内 MCP 桥」完整方案

> 状态：**方案稿，未落码、未部署、未注册连接器、未接入任何凭据。**
>
> 目标：在 Moment ipa 内置一个默认关闭、由用户在设备上配对授权的 MCP 桥，使助手能通过连接器对真机 App 做功能验证、语义操作与运维处置；每次修复或新增功能后形成固定闭环：**改 → 冒烟/出包 → 桥上跑场景 → 回读状态与 Diag → 按证据定因 → 再修**。
>
> 本方案的权限口径是**全开但分层**：配对成功后，功能面可读写；运维面使用独立能力位；少数会改变启动状态、清理缓存、下发单机运维指令或永久动数据的动作，再加两段提交或事前用户指令。权限全开不等于无鉴权、无快照、无审计，也不等于桥可以绕过安全模式、只读态与核心数据层红线。

---

## 0. 结论先行

### 0.1 推荐架构

采用 **Cloudflare 专用中继 + App 出站 WebSocket + 助手侧标准 MCP Streamable HTTP** 的双面结构：

```text
Muse 连接器 helper
  │  HTTPS, MCP Streamable HTTP, Bearer 凭据
  ▼
Cloudflare Worker（moment-bridge，专用，不复用 moment-ops）
  ├─ Durable Object：按 pairingId 建会话室，保存在线状态、请求映射、吊销状态
  ├─ 助手面：POST/GET/DELETE /mcp
  ├─ 设备面：GET /app/connect（WSS，App 主动出站）
  └─ 运维元面：回读 OPS 双源源头、保存桥运维命令的投递状态
  ▲
  │  WSS 长连接（只出站、不开入站口），承载原始 MCP JSON-RPC 帧
  │
Moment App（iPhone，前台运行）
  ├─ MomentBridge*：协议、传输、工具分发、快照、设置与配对
  ├─ 正常模式：完整工具分发器
  └─ 安全模式：受限分发器（只碰 Diag / 哨兵 / OPS 缓存 / 桥自身状态）
```

关键取舍：

1. **MCP 的标准面只放在中继对助手一侧。** MCP 官方标准传输是 stdio 与 Streamable HTTP；WebSocket 不是标准传输。因此设备侧 WSS 明确是「承载 MCP JSON-RPC 的自定义设备传输」，中继负责把 Streamable HTTP 请求与设备侧 JSON-RPC 请求/响应按 ID 桥接，不能宣传成 App 直接实现了标准远程 MCP 端点。
2. **新建专用 Worker，不复用 `moment-ops`。** OPS 是低权限、静态、白名单两字段的热修指令通道；MCP 桥是高权限交互通道。两者同账号、不同 Worker、不同凭据、不同数据域，安全域隔离。
3. **桥只在 App 前台在线时可用。** iOS 后台挂起后不能承诺长连接存活。App 不在前台、被杀或断网时，工具必须明确报 `app_offline` / `app_backgrounded`，不得排队假装已执行，更不得把「中继收到请求」说成「App 已执行」。
4. **语义操作走 App 内部模型，不做合成触摸。** 打开笔记、改块、类型转换、块重排都调用 App 的模型/文档服务；这能验证数据、状态机与持久化，不能替代真实手指对命中、识别器仲裁、键盘与动画体感的验证（纪律见 §8）。
5. **OPS 既有双源仍是正式指令真源。** M1/M2 阶段桥对 OPS 只做回读、触发刷新与生效确认，不是第三条指令源。M3 才允许增加一条**单机、限时、只能收紧不能放松**的桥运维命令投递路径；它不改写 OPS 缓存、不冒充源头指令，定位与取舍见 §6.2。
6. **正式版保留桥代码、默认关闭是可接受口径，但有前提。** 必须同时满足：未配对不联网、不生成长期凭据；配对凭据在 Keychain；中继可吊销；安全模式受限；写前快照；工具清单可审计；verify 有默认关与禁区断言。若任一前提未落地，则改为只进开发构建变体，不进正式 ipa（见 §11）。

### 0.2 分期总览

| 期 | 目标 | 工具范围 | 验收一句话 |
|---|---|---|---|
| M1 | 连通、配对、只读排查 | 状态、Diag、笔记只读、设置状态、OPS/救援只读、OPS 刷新 | 真机前台配对后，助手读到的 Diag 与 App 内导出逐行对账一致；断开/后台/安全模式的失败形态各自可判定 |
| M2 | 语义读写与场景验证底座 | 笔记新建、块增删改、类型转换、语义重排、软删/恢复、语言与白名单开关、写前快照 | 只用验收测试笔记完成全链操作，写后回读 + 重启持久化 + 快照可恢复三者同时成立 |
| M3 | 场景库与运维打通 | 场景脚本、单机桥运维命令、缓存清理（待 R3 本地动作先落地）、只读打开（待 R2）、OPS 源头发布 runbook | 历次修复场景可复跑并输出证据包；运维动作从下发、Diag 留痕到生效确认全链可追 |

---

## 1. 现行事实基础（方案落点）

本节只写 2026-11-27 调研时源码已存在的事实；凡「建议新增」均在后续章节明示，不把规划写成现状。

### 1.1 iOS 文件结构

原生应用目录：`rust/apps/ios/app/`。

| 文件 | 现行职责 | 与桥的关系 |
|---|---|---|
| `MomentApp.swift`（约 1.69 万行） | 主体：`Library`、`DiagLog`、`EditorModel`、`SettingsView`、列表/编辑器等 | 只许加接线点与只读访问器；桥实现不得继续堆进此文件 |
| `MomentLaunch.swift` | `LaunchStep` 步名集中定义；`LaunchSentinel` / `LaunchSentinelStore` 直写 `diag/launch-sentinel.json` | 桥回读哨兵必须走此真源，不另造启动状态文件 |
| `MomentOps.swift` | `OpsStep`、`OpsDirectiveSet`、`OpsDirectives`；双源拉取、白名单解析、缓存与 guard 查询 | 桥运维面复用此真源；桥不得自建第二套 OPS 解析器 |
| `MomentRescue.swift` | 安全模式 `RescueView`：尝试正常启动、导出诊断、检查热修复、库已开时导出 ZIP | 桥的救援动作必须抽共用动作服务后由页面与桥共同调用，禁止模拟点按钮 |
| `MomentDrag.swift` | `DragPressEngine` / `DragPressAnchor`，全状态 Diag 打点 | 桥只回读 DRAG 量测行与做语义重排，不驱动识别器 |
| `build-app2.sh` | 手工 Swift 编译链：每个 Swift 文件轮流作 `-primary-file` 编译，再统一链接 | 新增文件必须同步加文件名单、primary 编译遍与链接 `.o`（见 §9.7） |
| `verify_ios.sh` / `smoke_ios.sh` | 静态断言与出包前全量冒烟 | 桥须新增断言组并入冒烟门（见 §9.7） |

工作树口径注意：调研时源码版本为 0.9.49 / build 76（拖拽第三轮已落码未出包），最新已交付 ipa 为 0.9.48。桥实施动工前必须先按 `docs/WORKFLOW.md` 核 `git status` 与当前批次，不得跨批夹带。

### 1.2 可复用的内部能力

桥不新造业务真源，优先复用：

- **`Library`**：`load()` / `reload(lib:)` / `retryLoad()`、`create()`、`persist(_:)`、`remove(_:)`、`softRemove(_:)`（打 `deletedAt` 标、8 秒撤销窗口、本篇独立到期）、`undoDeletion()`（只撤销待删集中最近一篇）、`commitPendingDeletion(id:)`、`exportZip()`、`verifyStore()`（全库计数 + hash 回读）、`libraryHash()`、`memosVersion` / `manifestVersion`、CREATE 量测累计（`createTraceActive`、`createTraceListPasses`、`createTraceListMs`、`createTraceAvatarMs`）。
- **`DiagLog`**：当天 300 条环 + 按天归档上限 60；条目为 `{ts, level, text}`，呈现行格式由 `DiagEntry.line` 生成；有 `log` / `logOnce` / `logErrorOnce`；`DiagView.buildExportFile(...)` 与 `exportEverything()` 是导出真源。红线：`DiagLog` 是叶子，零依赖其他单例——桥的任何类型不得被 `DiagLog` 反向引用。
- **`EditorModel`**：`blocks`、`focusBlockId`、`editingBlockId`、`setBlockType`、`deleteBlock`、`splitBlock`、`mergeBlockBackward`、`insertLines`、`commitDrag`、`scheduleSave`、`saveNow`，以及 CREATE 分段打点（dest / claim / kb / appear / timing / settle）。注意 `EditorModel` 初始化带呈现与落盘副作用，不是纯文档模型——M2 前须抽文档变更内核（见 §5.4）。
- **UniFFI `MomentLibrary`**：`open`、`listMemosJson`、`memoCount`、`upsertMemoJson`、`removeMemo`、`searchIdsJson`、附件与头像、`exportBackup` / `importBackup`、`libraryHash`。桥 v1 不新增 FFI 导出面；若实施中确需新增，先按 UniFFI checksum 纪律重跑 bindgen、回拷 bindings 并同步契约测试，不得只改注释或只重建库。
- **OPS 现行语义**：只认 `disableSteps` 与 `forceSafeMode` 两字段，未知字段忽略、整包坏损当空指令；主源 Cloudflare Worker（`moment-ops.overtrees.workers.dev/ops.json`，no-store），备源 GitHub Pages（`overtrees.github.io/moment-ops/ops.json`，约 10 分钟 CDN 缓存）；第一个成功源为准，成功后落 `diag/ops-directives.json` 并记 `OPS directives fetched src=… steps=… forceSafe=…` 行；刷新在本次启动只备缓存，**下次启动**判定与 guard 才消费——桥的生效确认必须按这个语义设计，不得把「已拉到」说成「已生效」。
- **哨兵与救援留痕**：`LaunchSentinel` 含 `busy`、`step`、`streak`、`lastRescueAction`、`lastRescueAt`；下次启动 LAUNCH 行尾附 `lastRescue=`。`Library.recordRescueAction(_:)` 是救援动作跨启动留痕的现行入口，桥触发的救援等价动作必须走同一入口留痕。
- **天气 key 状态口径**：`WeatherService.key(_:)` 的生效序为用户自填（UserDefaults `weatherKey_qweather` / `weatherKey_caiyun`）优先、构建注入（bundle `weather-keys.json`）兜底；设置页保存打点只记 `empty` / `set`、绝不记值。桥沿用此口径（见 §5.7）。

### 1.3 目标与非目标

**目标**

1. 助手能在用户授权后，对前台真机 App 做确定性的状态读取、Diag 读取、笔记语义读写与设置读写。
2. 每次修复/新增功能后，可复跑场景并拿到机器可判定的通过/失败 + Diag 证据，而不是只靠口头描述。
3. 运维面打通：OPS 双源与生效状态可回读、可触发刷新、可确认生效；安全模式状态可回读；受控的救援等价动作可远程触发并全程留痕。
4. 桥自身可随时断开、可吊销、可被 OPS guard 停用，且不破坏自救机制的独立性。

**非目标（v1–M3 均不做，除非另行立项）**

- 不做后台常驻控制：App 不在前台时不承诺任何工具可达。
- 不做合成触摸/坐标点击：不模拟手指、不注入 UIKit 事件、不驱动手势识别器。
- 不做任意文件读写、任意 URL 抓取、任意 SQL/FFI 调用、任意 JSON 直写资料库。
- 不经桥传输附件二进制与备份 ZIP（快照 ZIP 只在设备本地生成与恢复，不上中继）。
- 不读系统崩溃日志 `.ips`：App 无权读系统崩溃库；崩溃后证据靠哨兵 + Diag + RESCUE 留痕在下次启动回读（见 §6.4）。

---

## 2. 传输层选型

### 2.1 约束

- 助手运行在云端 VM，iPhone 在用户网络后（NAT/家宽/蜂窝），两者无天然可达路径。
- iOS App 退后台即被挂起，无通用机制靠普通网络请求唤醒执行任意工作。
- 当前分发是测试签名 ipa（Team `ZP7KP7TN22`，1 台设备，零 iCloud 容器）；构建链是手工 `swift-frontend` 多遍编译 + lld 链接，加 App Extension target 的成本与签名风险都高。
- 用户已有 Cloudflare 账号与 Worker 运维经验（`moment-ops` 在产），中继放 Cloudflare 与既有运维面同栈。

### 2.2 候选对比

| 候选 | 可达性 | 主要问题 | 结论 |
|---|---|---|---|
| ① App 出站 WSS → 自有 Cloudflare 中继（Worker + Durable Object） | 云端助手与手机都只需出站连接，中继做会话汇合；NAT/蜂窝均可 | 需自建鉴权、配对、吊销；中继经手流量（靠 TLS + M2 前评估正文加密）；App 后台仍不可达 | **M1 主路** |
| ② 局域网直连（App 内 HTTP/WS 服务 + Bonjour 发现） | 仅同局域网可达；云端 VM 永远不在用户局域网 | Bonjour 只解决发现不解决路由；iOS 需局域网权限说明；IP 变化、后台挂起同样存在 | M3 可选「本地伴随模式」：将来若有同网 Mac/本地代理，可复用同一分发器加一个传输适配，不改工具语义 |
| ③ Tailscale | iPhone 装 Tailscale App 只能让手机自身入网，**不能把另一个 App 的本地端口暴露到 tailnet**（iOS 沙箱隔离）；嵌入需自带 Network Extension / PacketTunnelProvider + entitlement + 独立 target | 与当前手工构建链和测试签名冲突最大；且把 VPN 形态引入笔记 App 本身不合比例 | **v1 不做**；仅保留为远期研究项，不进 M3 承诺 |
| ④ APNs 推送唤醒 | 可达性为「尽力通知」，静默推送受系统节流且不保证拉起执行 | 需推送证书/权益与服务端；无法承载请求-响应语义 | 只可作 M3 可选「请打开 Moment」提醒，不作传输与控制面 |
| ⑤ iCloud/网盘文件邮箱（命令文件进、结果文件出） | 异步分钟级 | 当前签名零 iCloud 容器；冲突与时序不可判定，无法做交互验证 | 否决作控制面；证据文件仍走现有导出/分享链 |

### 2.3 推荐分阶段

- **M1 起只做候选 ①。** 中继端点形态（均为拟议，尚未创建）：
  - Worker 名：`moment-bridge`；域名：`moment-bridge.overtrees.workers.dev`。
  - 助手面：`POST/GET/DELETE https://moment-bridge.overtrees.workers.dev/mcp`（MCP Streamable HTTP）。
  - 设备面：`GET https://moment-bridge.overtrees.workers.dev/app/connect`（WebSocket 升级）。
  - 健康面：`GET /health`（只回中继自身存活与版本，不回任何设备/笔记信息）。
- **Durable Object 设计**：以 `pairingId` 的哈希为 DO 名，一配对一室。DO 负责：设备 socket 的 Hibernation WebSocket 管理（休眠不掉线、消息唤醒）、助手请求与设备响应的 ID 映射与截止时间、在线状态与最近心跳、吊销标记、未完成请求的失败收口。连接附属状态只放 pairingId、设备标签、连接 epoch 等小元数据（遵守 `serializeAttachment` 2,048 字节上限纪律）。
- **中继零业务存储**：不落笔记正文、不落 Diag 正文、不落工具参数与结果；只存配对元数据（凭据哈希、能力位、创建时间、最近在线、吊销状态）与调用元计数（工具名、耗时、结果码、字节数）。中继日志同样只记元数据。
- **局域网适配后补（M3 可选）**：传输层在 App 内做成协议接口（`BridgeTransport`），WSS 是其首个实现；局域网实现只替换传输，不新增工具、不改授权模型（配对与凭据同一套）。

---

## 3. 协议设计

### 3.1 两段协议面

| 段 | 协议 | 说明 |
|---|---|---|
| 助手 ↔ 中继 | MCP over Streamable HTTP（标准面） | helper 按 MCP 客户端实现 `initialize` / `tools/list` / `tools/call`；中继校验连接器凭据与能力位后转发 |
| 中继 ↔ App | MCP JSON-RPC over WSS（自定义设备传输） | 数据帧就是原始 JSON-RPC 2.0 消息（UTF-8 文本帧），不套业务信封，保证工具语义与标准面一致；控制帧用带 `moment.control` 标记的旁路消息（presence / ping / revoke-notice / ops-command-deliver），不与 JSON-RPC 混名 |

协议版本：实施时在 `2025-06-18` 与连接器模板支持的最新版之间钉死一个版本并写进工具清单哈希；App、中继、helper 三方版本不一致时以 `version_mismatch` 明确失败，不静默降级语义。

### 3.2 会话与状态纪元

- 每次 App 进程启动生成 `bootSessionId`（UUID），连接建立生成 `appSessionId`；桥的启动 Diag 行同时记两者，之后每次工具返回都带上下文 `{appSessionId, bootSessionId, bootMode, bridgeManifestHash}`。
- 中继签发的 MCP 会话与当前设备连接 epoch 绑定：App 断线即会话失效，helper 必须重新 `initialize`，防止把上一进程的迟到结果认作当前状态。
- 心跳：App 每 20 秒发控制帧 ping，中继回 pong 并更新最近在线；连续 3 次无心跳判离线。重连用指数退避（1s 起、封顶 30s、带抖动），退避状态进设置页与 `bridge_status`。

### 3.3 请求纪律

- **截止时间**：只读调用默认 15s、写调用 30s；场景运行是异步作业（`scenarios_run` 立即返回 `runId`，`scenarios_get_result` 轮询），不占长连接死等。
- **帧与分页上限**：单帧上限 1 MiB；`diag_tail` 单次 ≤200 条且结果 ≤256 KiB；`notes_get` 按块游标分页（`blockCursor` / `maxBlocks` 默认 100）；超限返回 `payload_too_large` 并给出可续读游标，不截断后假装完整。
- **幂等**：一切写工具必带 `idempotencyKey`（助手侧生成、同一逻辑操作重试不变）。App 侧操作流水（见 §9.3）按 key 去重：重复 key 且参数哈希一致 → 返回首次结果；key 同而参数不同 → `idempotency_conflict`。
- **乐观并发**：改存量笔记/块必带 `expectedDocHash`；打开着的编辑器有未落盘改动且目标相同 → `memo_busy`，不强行覆盖（全开权限也不做静默抢写）。超时后助手必须先回读状态再决定是否重试，禁止盲重试写请求。
- **哈希口径**：`docHash` = 对单篇备忘的规范化 JSON（键排序后的 flushed 文档全量）做 SHA-256；`libraryHash` 沿用 FFI 既有 `libraryHash()`（UInt64）并以字符串回传。两者用途分开：docHash 管单篇并发，libraryHash 管全库前后对账。

### 3.4 错误模型

工具执行错误统一以 MCP `isError` + 结构化错误对象返回：`{code, message, retryable, details?}`。协议层错误（未鉴权、版本不符、无会话）走 JSON-RPC error。失败码全集（helper 须逐码映射成可读结论，不许吞成一句「失败」）：

| code | 含义 | 助手侧动作 |
|---|---|---|
| `relay_unreachable` | 中继 DNS/网络/5xx | 只读可有限重试；写请求按「结果未知」处理 |
| `app_offline` | 无在线设备连接（含未启用/未配对，对外不区分以防探测） | 明确告知需打开 App，不重试 |
| `app_backgrounded` | 最近 presence 为后台或心跳过期 | 同上，提示切前台 |
| `pairing_required` / `unauthorized` / `revoked` | 未配对 / 凭据无效 / 已吊销 | 停手，走重新配对或报告吊销状态 |
| `scope_denied` | 能力位不足（如未授运维面） | 报告缺哪项能力，不绕路 |
| `confirmation_required` | 缺两段提交令牌或事前授权标记 | 先走 §7.3 的确认流程 |
| `version_mismatch` | 协议/工具清单版本不一致 | 报告三方版本，停手 |
| `safe_mode_limited` | 安全模式下调用了受限工具 | 只读救援面继续，其余停手 |
| `read_only_mode` | 只读打开态（R2 后）调用写工具 | 停手并说明当前打开模式 |
| `library_unavailable` | 库未打开/加载失败 | 回读 `app_state` 与 Diag 定因 |
| `memo_not_found` / `block_not_found` | 目标不存在 | 回读列表/文档再决策 |
| `revision_conflict` | `expectedDocHash` 不匹配 | 重新 `notes_get` 后重算操作 |
| `memo_busy` | 目标正在编辑器中且有未保存改动 | 等保存或先 `editor_save_now` |
| `snapshot_failed` | 写前快照失败 | **写操作中止**，先修快照面 |
| `write_outcome_unknown` | 已下发但结果未确认（超时/断线） | 先回读 docHash 与操作流水，再决定是否重试 |
| `payload_too_large` / `rate_limited` | 超限 / 触发中继限速 | 分页或降频，不并发轰击 |

---

## 4. 工具面总则

### 4.1 命名与通用约定

- 工具名用 snake_case（如 `diag_tail`），与连接器 `ALLOWED_TOOLS` 逐字一致；新增工具必须先改 App 工具清单并重新过一遍连接器审单（见 §10），服务端后加的工具默认仍被 helper 拦下。
- 每个工具标注四项属性：**类别**（只读 / 语义写 / 数据写 / 运维 / 运维高危）、**模式**（正常 / 安全模式可用）、**实施期**、**实现层**（走哪个内部真源）。
- 除特别说明外，所有返回都附 §3.2 的上下文字段；下文「返回」列只写业务字段。
- 「语义操作」指走 App 内部模型 API 的操作（打开、改块、重排等），与「数据写」的区别是它经过编辑器/文档服务的校验与落盘链；两者都不是合成触摸。

### 4.2 工具总表（功能面）

功能面工具在 §5 逐个定义；运维面工具在 §6 逐个定义。此处先给全景：

| 面 | 工具 | 期 |
|---|---|---|
| 桥与状态 | `bridge_status`、`app_state` | M1 |
| Diag | `diag_tail`、`diag_search`、`diag_sessions`、`diag_snapshot_meta`、`diag_export` | M1 |
| 笔记只读 | `notes_list`、`notes_search`、`notes_get` | M1 |
| 笔记写 | `notes_create`、`notes_soft_delete`、`notes_restore_deleted`、`notes_delete_permanent` | M2（永久删除见 §5.5 限制） |
| 编辑器语义 | `editor_open`、`editor_get_state`、`editor_insert_block`、`editor_update_block`、`editor_set_block_type`、`editor_delete_block`、`editor_move_block`、`editor_focus_block`、`editor_save_now` | M2 |
| 量测 | `metrics_create_settle`、`metrics_drag_trace` | M1 读回 / M3 场景化 |
| 设置 | `settings_get`、`settings_set_language`、`settings_set_toggle`、`settings_clear_weather_key` | 读 M1 / 写 M2 |
| 场景 | `scenarios_list`、`scenarios_run`、`scenarios_get_result` | M3 |
| 运维 | 见 §6 总表（`ops_*`、`rescue_*`、`bridge_revoke_self` 等） | M1–M3 分布 |

---

## 5. 功能面工具（逐个定义）

### 5.1 桥与 App 状态（只读，M1）

| 工具 | 入参 | 返回 | 属性 / 实现层 |
|---|---|---|---|
| `bridge_status` | 无 | `enabled`（本地开关）、`pairingState`（unpaired / pairing / paired / revoked）、`transportState`（offline / connecting / connected / backoff）、`scopes`（已授能力位）、`protocolVersion`、`manifestHash`、当前 `appSessionId` / `bootSessionId`、最近一次调用的元计数（工具名/结果码，不含内容） | 只读；正常与安全模式均可用；`MomentBridge` 门面直答，不碰 Library |
| `app_state` | 无 | 版本/build、bundle id、`bootMode`（normal / safe + streak + step + source）、场景状态（前台/后台）、库状态（未开/已开/加载失败）、`memoCount`（活跃数）、待删数、全库 `libraryHash`、生效语言（偏好 + 解析码）、OPS 摘要（见 §6.1）、桥状态摘要 | 只读；安全模式下库相关字段回 `null` + `library_unavailable` 标记，不为答此工具去开库；来源为 Library 已判定状态 + 哨兵 + OPS 缓存 |

### 5.2 Diag 读取（只读，M1）

Diag 是闭环的证据面，设计原则：**按 App 内存储原样回读，不在中继侧缓存或改写**；条目字段与 `DiagEntry` 一致（`ts` 秒级 epoch、`level`、`text`），并附呈现行 `line` 便于与 App 内导出逐行对账。

| 工具 | 入参 | 返回 | 属性 / 实现层 |
|---|---|---|---|
| `diag_tail` | `scope`（today / archive）、`archiveStamp?`（scope=archive 时必填）、`limit?`（默认 100，≤200）、`minLevel?`（all / warn / error，按等级门槛过滤，与 App 内呈现口径一致）、`beforeTs?`（向前翻页游标） | `entries[]`（ts / level / text / line）、`nextBeforeTs`、`totalAvailable` | 只读；安全模式可用；直读 `DiagLog.today` / `archives` |
| `diag_search` | `query`（字面子串；可选 `regex: true` 时按正则，长度与复杂度设上限）、`scope`、`archiveStamp?`、`limit?` | 命中条目数组（附所在归档 stamp 或 today 标记） | 只读；安全模式可用；搜索在 App 内执行，正文不经中继索引 |
| `diag_sessions` | 无 | 会话列表：M1 起以桥的 `bootSessionId` + LAUNCH 行时间戳切分（每次启动一条：startedAt、条目数、是否进过安全模式、`lastRescueAction`）；桥上线前的历史会话只能按归档近似切分，返回里以 `approximate: true` 明示，不冒充精确 | 只读；安全模式可用 |
| `diag_snapshot_meta` | 无 | today 条数、归档数、最早/最晚时间戳、估算导出字节数 | 只读；安全模式可用；只回元数据 |
| `diag_export` | `cursor?`（分块游标） | 与 App 内「导出诊断」同构的全文分块：导出头 + Diag 全文 + 哨兵摘要段 + 桥状态段；`nextCursor` / `done` | 只读；安全模式可用；组装走 `DiagView.buildExportFile` 同链。**这就是桥侧的「导出诊断」等价动作**——安全模式页面的导出走系统分享、助手拿不到，故桥面用直接回读实现同一证据目的，不模拟点分享 |

**主动上报（与拉取合并设计，不另建云端日志库）**：App 前台已连接时，可用 `diag_subscribe`（入参 `minLevel`、可选前缀过滤）订阅本会话新增条目，中继以 MCP 通知帧转发；订阅只是加速通道，**证据真源仍是 App 内 Diag**。断线期间的条目靠下次连接后按 `ts` 游标补拉。出现 error 级条目或 `RESCUE` / `BRIDGEOPS` 前缀行时，App 额外发一条 `incident_hint` 通知（只带游标与级别），helper 收到后立即 `diag_tail` 拉全文。订阅与 hint 都不落中继存储。

### 5.3 笔记只读（M1）

| 工具 | 入参 | 返回 | 属性 / 实现层 |
|---|---|---|---|
| `notes_list` | `limit?`、`cursor?`、`includeDeleted?`（默认 false；true 时只回待删标记的元信息） | 摘要数组：`id`、标题、置顶、创建/更新时间、首文本块摘要、`blockCount`、`docHash`；`nextCursor` | 只读；走 `Library.memos` 镜像，不直查 FFI |
| `notes_search` | `query`、`limit?` | 命中摘要数组（同 `notes_list` 形态） | 只读；走 FFI `searchIdsJson` 后回表摘要 |
| `notes_get` | `id`、`blockCursor?`、`maxBlocks?` | 全量元信息 + `blocks[]`：每块 `id`、序号、`type`、纯文本、`runs`（行内标记段，结构同 `BlockState.runs`）、`checked`（todo）、规范节点 `node`（`flushedNode()` 产物）、原子块只回类型与 attrs 元信息（附件只回文件 id/名/大小，不回二进制）；`docHash` | 只读；块内容以 BlockState 读面为准，禁止直接拼 raw JSON 冒充解析结果 |

### 5.4 笔记与编辑器写（M2；语义操作）

**前置重构（M2 动工第一步，不是桥的补丁）**：把文档变更内核从 `EditorModel` 抽成独立的 `DocumentMutationService`（新文件，见 §9.2）——输入为备忘文档块序列 + 变更命令，输出为新块序列 + 变更摘要；`EditorModel` 与桥分发器共用它。这样桥的改块/转换/重排与用户在编辑器里的操作走同一套变换与校验，避免桥另写一份近似逻辑日后分叉。抽取须行为等价：既有编辑器路径的 Diag 行与落盘口径不变。

| 工具 | 入参 | 返回 | 属性 / 实现层 |
|---|---|---|---|
| `notes_create` | `title?`、`blocks?`（块规格数组：`type` + `text` / `runs?` / `checked?`；缺省为单个空段落）、`idempotencyKey` | 新篇 `id`、`docHash`、`snapshotId`（写前全库快照，见 §9.3） | 数据写；经 `Library.create()` 建篇后由文档服务写入初始块并 `persist`；不自动打开编辑器（打开是单独的 `editor_open`） |
| `editor_open` | `memoId` | 打开后的 `editor_get_state` | 语义写（UI 导航）；经根视图的桥导航请求通道切到编辑页，等模型 id 对上或超时；仅前台 + 正常模式 |
| `editor_get_state` | `memoId?`（缺省 = 当前打开篇） | 当前篇 id、标题、`focusBlockId`、`editingBlockId`、块序数组（id + type + 文本摘要）、脏/已保存状态、双栏在位与分界信息 | 只读语义状态；读 `EditorModel` |
| `editor_insert_block` | `memoId`、定位（`afterBlockId` / `beforeBlockId` / `index` 三选一）、块规格、`expectedDocHash`、`idempotencyKey` | 新块 `id`、插入序号、新 `docHash`、`snapshotId` | 语义写；文档服务执行 + 落盘 + 回读校验 |
| `editor_update_block` | `memoId`、`blockId`、可选 `text` / `runs` / `checked` / `attrsPatch`（按块类型的白名单键）、`expectedDocHash`、`idempotencyKey` | 更新后块的规范节点、新 `docHash` | 语义写；文本类与列表项走 runs 口径；原子块只许白名单 attrs，禁止整节点任意 JSON 覆盖 |
| `editor_set_block_type` | `memoId`、`blockId`、`toType`（段落/标题/待办/引用/提示/列表等现行可转集合）、`expectedDocHash`、`idempotencyKey` | 转换后块节点、新 `docHash`、如有信息损失（如标记段拍平）逐项列 `warnings[]` | 语义写；复用 `EditorModel.setBlockType` 同一变换 |
| `editor_delete_block` | `memoId`、`blockId`、`expectedDocHash`、`idempotencyKey` | 被删块摘要、新块序、新 `docHash`、`snapshotId` | 语义写；文档服务删除 + 落盘 |
| `editor_move_block` | `memoId`、`blockId`、目标（`beforeBlockId` / `afterBlockId` / `toIndex`）、双栏独立模式下可选 `targetColumn`、`expectedDocHash`、`idempotencyKey` | `fromIndex`、`toIndex`、新块序、新 `docHash` | 语义写；**这是拖拽的语义级等价驱动**：只改文档序（及独立双栏的栏归属数组），不产生任何触摸/识别器事件；证据边界见 §8 |
| `editor_focus_block` | `memoId`、`blockId`、`caret?`（end / offset） | `focusBlockId` 回读 + 对应 Diag 关联 id | 语义写（UI 状态）；要求目标篇已打开；只证明 App 内焦点状态机到达目标，不证明真实键盘/光标体感 |
| `editor_save_now` | `memoId` | 落盘后 `docHash` 与全库 `libraryHash` | 语义写；调 `saveNow` 并以 `verifyStore` 回读对账 |

### 5.5 删除与恢复（M2，数据写高危子集）

| 工具 | 入参 | 返回 | 属性 / 限制 |
|---|---|---|---|
| `notes_soft_delete` | `memoId`、`expectedDocHash`、`idempotencyKey` | `deletedAtMs`、撤销窗口到期时刻、`snapshotId` | 走现行 `Library.softRemove`：打标落盘 + 列表摘除 + 8 秒后本篇独立真删。桥不得绕过撤销窗口直接真删活跃笔记 |
| `notes_restore_deleted` | `memoId`、`idempotencyKey` | 恢复后摘要与 `docHash` | 只支持恢复**待删集中**的目标（现行 `undoDeletion` 只认最近一篇——实施时须把待删集做成可按 id 撤销，或明确此工具只恢复最近一篇并在使用前回读确认目标）；窗口已过、已真删的笔记只能走快照恢复（M3） |
| `notes_delete_permanent` | `memoId`、`expectedDocHash`、`confirmMemoId`（须与 `memoId` 逐字一致的两段提交字段）、`idempotencyKey` | 删除结果 + 删除前 `snapshotId` | **数据高危**：仅允许对已软删（待删集内）或验收夹具笔记执行；执行前强制全库快照且快照失败即中止；不提供「批量永久删除」工具 |

### 5.6 量测回读（只读，M1）

量测工具只做**解析与回读**，不新造量测口径：数据源就是既有 Diag 行。

| 工具 | 入参 | 返回 |
|---|---|---|
| `metrics_create_settle` | `memoId?`（缺省取最近一条 CREATE settle）、`waitMs?`（等待 settle 行出现的上限） | 解析 `CREATE settle` 行的各段：create / model / dest / appear / claim / kb（ms）、`listpass` 趟数与总 ms、avatar ms、bodypass 轮数；附原始行文本与行时间戳；未 settle 时回 `status: pending`，不拿半成品数字下结论 |
| `metrics_drag_trace` | `sinceTs?`、`blockId?`、`limit?` | `DRAG` 行按事件归组回读：engine attached、press target / reject / disarmed、press state 全状态、pickup、converge、menu show、drop、cancel；只回事实行与计数，**不在工具层做「拖拽已修好」的推断**（推断留给场景判定与真机终判，见 §8） |

### 5.7 设置读写

| 工具 | 入参 | 返回 | 属性 / 期 |
|---|---|---|---|
| `settings_get` | 无 | 语言：偏好值（system / 具体码）+ 生效码；开关注册表内各开关现值；天气：`qweather` 与 `caiyun` 各回 `{state: set \| empty, source: user \| bundle \| none}`；桥自身状态摘要 | 只读，M1。**天气 key 只报状态与来源，绝不回值、不回哈希、不回指纹**——哈希/指纹可被离线比对，同样按凭据处理 |
| `settings_set_language` | `code`（五语码或 `system`）、`idempotencyKey` | 生效码回读 | 语义写，M2；走 `LangStore.apply` / `applyFollowSystem` 同一入口 |
| `settings_set_toggle` | `key`（注册表白名单）、`value`（bool）、`idempotencyKey` | 改后回读值 | 语义写，M2。注册表首批只入低风险项：`diagAutodel`（Diag 30 天自动删除）。桥自身开关、哨兵相关键、备份时间戳键永不入表；新增开关入表须随版本评审并更新工具清单 |
| `settings_clear_weather_key` | `provider`（qweather / caiyun）、`idempotencyKey` | 清除后该 provider 的生效状态（若 bundle 注入仍在，`source` 回 bundle、`state` 仍为 set，如实回） | 语义写，M2。只清用户自填覆盖，**不提供经桥写入天气 key 的工具**：凭据不经 MCP 传输、不经中继；用户自填仍走设置页本地输入 |

---

## 6. 运维面（独立章节）

运维面与功能面分开设计、分开授权（§7.2）：功能面解决「功能对不对」，运维面解决「App 起不来、指令没生效、证据拿不到时怎么办」。运维面的每一条都必须与现行自救体系对齐：

- **白名单纪律**：运维指令永远只有 `disableSteps` + `forceSafeMode` 两字段，步名只能出自 `OpsStep` / `LaunchStep` 已登记集合；桥不引入第三种指令字段。
- **核心数据层不入热修面**：开库、读数据、解析、再水化等核心步不设 guard，任何运维指令点名也无效；桥的任何运维动作不直接改写资料库文件、附件与 Diag 归档。
- **救援独立性**：安全模式页与受限分发器只依赖 DiagLog、FileManager 元数据、OPS 缓存与 Library 已判定状态，不为桥去开库、不调 FFI 写。

### 6.1 OPS 回读：生效、缓存与双源源头（三层分开）

OPS 状态必须分三层回，混在一起就会把「源头已改」误报成「App 已生效」：

| 工具 | 入参 | 返回 | 属性 / 期 / 执行方 |
|---|---|---|---|
| `ops_get_effective` | 无 | 三份并列：`bootApplied`（本次启动判定实际消费的指令集——实施时在 Library 启动判定处留快照）、`currentCache`（现行 `diag/ops-directives.json` 内容 + 文件 mtime + 内容哈希）、`lastFetch`（`OpsDirectives.current` + `lastSource`）；每份含 `version`、`disableSteps`、`forceSafeMode`，并回三者是否一致的 `converged` 布尔 | 只读，M1；App 执行。现行代码只有 current 与缓存两面，`bootApplied` 快照是本工具的实施前置（小改：判定处把消费的那一份留一份只读副本） |
| `ops_get_sources` | 无 | 双源各一份：`worker` 与 `github` 各自的原始白名单 JSON（经同一 `sanitize` 口径校验后的规范形）、内容哈希、抓取时刻、HTTP 状态、是否与 `currentCache` 一致 | 只读，M1；**中继执行**（App 离线也可回），但返回必须标 `origin: relay`——它证明源头内容，不证明 App 已拉取或已生效 |
| `ops_refresh` | 无 | 每源尝试结果（成功源、失败原因）、新缓存哈希、关联 Diag 行的时间戳与行文本（`OPS directives fetched src=…`） | 运维（控制类，不动数据），M1；App 执行：调 `OpsDirectives.fetch` 并等其完成（现行 fetch 的 completion 只回「结束」，实施时须补结果结构以便逐源回报）；完成后明确回 `effectiveFrom: next_launch`，与现行「下次启动生效」语义一致 |
| `ops_validate` | `directive`（待校验的指令 JSON） | 白名单校验结果：被接受的字段、被忽略的未知字段、非法步名清单、规范形 + 哈希 | 只读，M2；纯校验不落盘、不下发，供发布前预检 |

**生效确认的固定读法**（写进助手侧 runbook）：改源头 → `ops_get_sources` 确认双源内容 → App 前台时 `ops_refresh` → 用户下次启动后 `ops_get_effective` 看 `bootApplied` 与源头哈希一致 + `diag_search` 查到对应 `fetched` 行与 LAUNCH 行。三步齐才叫「指令已生效」，缺一环只能报到实际到达的那一环。

### 6.2 经桥下发新指令：桥是不是第三条源？

**裁定：分两层回答。**

**(a) 正式指令：桥不是第三条源（M1/M2 口径，长期有效）。**

既有两条源头路径保持唯一真源地位：

1. 主源：改 Cloudflare Worker 内 OPS 常量并重部署（即时生效、无缓存）。
2. 备源：向 GitHub Pages 公开仓 `Overtrees/moment-ops` 推提交（约 10 分钟 CDN 缓存）。

桥对正式指令只提供 §6.1 的回读、预检（`ops_validate`）、触发刷新与生效确认。理由：源头路径有独立的账号鉴权、变更历史与审计（Worker 部署记录 / git 提交）；若允许桥把任意指令直接写进 App 缓存，等于新开一条无审计、可单机漂移的第三源，且会绕过 `MomentOps` 的双源收敛语义，出问题时无法回答「这条指令是谁、何时、从哪来的」。**经桥发布正式指令的正确形态是助手侧编排（runbook），不是 App 工具**：助手用 `ops_validate` 预检 → 经既有 Cloudflare 连接器改 Worker 常量并部署（或经 GitHub 连接器推 Pages 仓）→ 回桥走 §6.1 确认链。这条编排用的是 Cloudflare/GitHub 各自的既有授权，与桥配对授权互相独立，发布动作每次须有用户当次指令（见 §7.3 清单）。

**(b) 单机急救命令：M3 增加第三条「投递路径」，但不是第三条「源」。**

场景：某台设备正在闪退/卡死，需要立刻让它下次启动进安全模式或跳过某个非核心步，等源头发布 + 用户重启拉取太慢（且坏到拉不到时源头路径根本到不了）。为此 M3 增加桥运维命令，边界逐项钉死：

| 工具 | 入参 | 返回 | 属性 |
|---|---|---|---|
| `ops_command_preview` | `directive`（仅两字段）、`ttlMinutes`（≤1440） | 规范形、哈希、到期时刻、与当前生效指令的差异（将新增禁用哪些步 / 是否新增 forceSafe） | 只读预检，M3 |
| `ops_command_issue` | `directive`、`ttlMinutes`、`idempotencyKey`、两段提交令牌（§7.3） | `commandId`、到期时刻、投递状态（pending / delivered / applied） | 运维高危，M3；中继保存待投递命令，App 在已连接时立即收、或下次连接/启动时取 |
| `ops_command_revoke` | `commandId`、两段提交令牌 | 撤销结果 | 运维高危，M3 |
| `ops_command_status` | `commandId?` | 活动命令清单：内容、签发 pairing、签发/到期时刻、状态、被消费的启动次数 | 只读，M3 |

桥命令的生效规则（与 OPS 合并口径，实施时落成单一真源函数）：

- 存储隔离：命令落 `diag/bridge-ops-command.json`，**永不改写** `ops-directives.json`；文件由中继签名（配对级密钥）、App 验签 + 验 pairing + 验到期后才接受，验不过记 `BRIDGEOPS reject …` 行并丢弃。
- **只能收紧、不能放松**：生效指令 = 源头指令 ∪ 桥命令（`disableSteps` 取并集、`forceSafeMode` 取或）。桥命令无法抵消源头已下达的禁用或强制安全模式；想放松只能改源头。
- **只辖既有 guard 点**：命令只能点名已登记步名；核心步点名无效（与 OPS 同规则）。新增桥自身步名 `OpsStep.bridge`（「MCP桥」）后，源头与桥命令都可以禁用桥的启动——这是桥的远程 kill switch，但注意它下次启动才生效，立即断开仍靠 App 内一键断开与中继吊销。
- **限时与留痕**：TTL ≤24 小时、同一设备最多一条活动命令、到期自动失效；签发、投递、应用、到期、撤销各记一行 `BRIDGEOPS …` Diag；下次启动 LAUNCH 行附 `bridgeOps=<commandId>` 摘要，与 `lastRescue=` 并列可查。
- **消费点前移**：启动判定读合并指令（源头缓存 ∪ 未到期桥命令），与现行判定同点位、同文件域（diag 域），不引入网络依赖——命令文件已在本地时，断网启动照样生效。

### 6.3 安全模式与救援面

| 工具 | 入参 | 返回 | 属性 / 期 |
|---|---|---|---|
| `rescue_status` | 无 | `bootMode` 全量：模式、safe 的 streak / step / source（streak / ops）；哨兵：文件是否存在、`busy`、`step`、`streak`、解析是否成功、文件 mtime；`lastRescueAction` + 时刻；DB 文件字节数（只读元数据）；Diag today/归档计数；桥当前分发器形态（full / limited / disabled）；只读打开态（R2 落地后） | 只读，M1；安全模式可用；数据源与 RescueView 状态区完全同源（哨兵文件 + FileManager 元数据 + OPS 缓存），不开库 |
| `rescue_arm_safe_mode` | `reason`（短文本，进 Diag）、`idempotencyKey`、两段提交令牌 | `armed: true`、预计生效点（next_launch）、哨兵回读 | 运维高危，M2。**单机版 forceSafeMode**：在 diag 域写桥专用一次性标记（不碰 OPS 缓存、不碰哨兵 streak），启动判定在现行两路（streak / OPS）之外加第三路消费它；标记被消费一次后转为审计留痕（保留 commandId 与时刻，不再持续强制）。App 不能被远程重启——本工具只「布防」，生效要等用户下次打开 App，返回与 Diag 都必须如实写明这一点 |
| `rescue_try_normal_start` | 两段提交令牌 | 动作结果 + 转入正常加载后的 `app_state` 摘要（或失败原因） | 运维高危，M2；**仅当前已在安全模式时可调**；与 RescueView 主按钮走同一动作服务（记 `RESCUE action normal-retry` + `recordRescueAction` + 切 bootMode 走常规 load）。若源头/桥命令的 forceSafeMode 仍在位，返回里明示「下次启动仍回安全模式」，不许报假成功。注意正常加载自带既定语义（待删过期真删、空库写种子）会在此路径发生，属正常加载本体行为、非桥新增写面，返回中以 `normalLoadSemantics: true` 标明 |
| `rescue_clear_caches` | 两段提交令牌 | 清前/清后字节数、逐项结果 | 运维高危，**M3 且以 R3 本地动作先落地为前置**：清理清单与 `plan_native_rescue.md` S7 逐字一致——仅 `URLCache.shared`、 `Library/Caches`、tmp 内本 App 导出残留；桥不得自行扩大清单。本地动作未落地前此工具不注册（不许桥先行自创清理实现） |
| `rescue_open_readonly` | 两段提交令牌 | 打开模式（direct / copy）、只读态确认 | 运维，**M3 且以 R2 只读打开落地为前置**；走 S4 的 FFI 只读句柄/副本模式；进入只读态后全部写工具回 `read_only_mode`。R2 未落地前不注册 |

**救援面禁区（桥永不可达，逐项列明）**：

1. 删除、改写、移动 `moment.db` 及其 `-wal` / `-shm`；任何「重置资料库 / 恢复出厂 / 清空数据」动作。
2. 清除 Application Support 全域、Diag 归档、UserDefaults 全量偏好（与 Web「绝不轻易清站点数据」同一条红线的原生形态）。
3. 导入/恢复备份 ZIP（恢复走 M3 快照工具有独立前置校验，见 §9.3；救援面不提供恢复入口）。
4. 删除附件、头像或任何用户文件；改动天气 key、配对凭据等凭据面（凭据只能本地管理）。
5. 在安全模式内远程解除安全模式布防、撤销桥命令、放松 OPS 指令（放松只能改源头或本地操作）。
6. 强杀进程 / 远程重启 App（iOS 无此能力，不许用任何手段冒充）。
7. 只读态下的一切写工具；安全模式下的一切笔记写工具。

### 6.4 崩溃后留痕回读

桥读不到系统 `.ips`，崩溃闭环靠既有留痕三件套在**下次启动**回读，这也是桥在闪退场景下的核心价值：

- 哨兵：`rescue_status` 回上次停步与 streak——崩在哪一步先看它。
- Diag：`diag_search` 查 `LAUNCH`（含 `lastRescue=` 与 M3 的 `bridgeOps=`）、`RESCUE`、`BRIDGE`、`BRIDGEOPS` 前缀行，还原「上次试过什么、桥做过什么、之后还崩没崩」。
- 救援动作留痕：`lastRescueAction` / `lastRescueAt` 经哨兵跨启动保存，`rescue_status` 与 `app_state` 都带回。
- 纪律：以上证据能定位启动步与动作序列，但不能替代 `.ips` 的符号化堆栈；方案不承诺桥能给出崩溃堆栈，定因等级按 §8 标注。

### 6.5 运维面分期落点（汇总）

| 期 | 运维工具 |
|---|---|
| M1 | `ops_get_effective`、`ops_get_sources`、`ops_refresh`、`rescue_status`、Diag 全套（含 `diag_export`）、`bridge_status` |
| M2 | `ops_validate`、`rescue_arm_safe_mode`、`rescue_try_normal_start` |
| M3 | `ops_command_preview` / `issue` / `revoke` / `status`、`rescue_clear_caches`（待 R3）、`rescue_open_readonly`（待 R2）、OPS 源头发布 runbook（助手侧编排，非 App 工具） |

---

## 7. 安全与授权模型

### 7.1 默认关闭与本地开关

- 设置页新增「MCP 桥」行（形态见 §9.4），桥开关**默认关**。关时：不建连接、不生成长期凭据、不开任何监听、不注册后台任务。
- 开关打开 ≠ 已授权：打开只允许进入配对流程；未完成配对前不接受任何工具调用。
- 桥开关只能在 App 内本地切换，**没有任何工具可以远程打开桥**（`settings_set_toggle` 注册表永不收录桥开关）。

### 7.2 三道授权门与能力分层

接入必须依次过三道门，缺一不可：

1. **实施授权门（动工前）**：真正落码、部署中继、注册连接器之前，主代理向用户说明接入范围并取得同意——本方案只是设计稿，不构成已授权。
2. **设备配对门（用户在 iPhone 上）**：用户在 App 内打开桥、点「开始配对」，核对配对页上的设备指纹后确认能力范围（见下表），这一步是设备侧同意。
3. **连接器凭据门（用户在 Muse 安全页）**：中继签发的客户端访问密钥只经 Muse 的安全凭据页录入（`credentials.request_api_access` 流程），**不进聊天、不进仓库、不进 Diag、不进命令行参数**；App 侧凭据存 Keychain，中继只存哈希。

配对时授予的能力位分三层，配对页逐项展示、分别勾选，**远程不可自我提权**（加能力位必须回 App 本地重新确认）：

| 能力层 | 覆盖 | 默认建议 |
|---|---|---|
| `read` 只读 | 状态、Diag、笔记读、设置状态、OPS/救援只读 | 配对必选（无此层配对无意义） |
| `write` 功能写 | 笔记/编辑器语义写、语言与白名单开关、软删/恢复 | 用户明确全开时勾选 |
| `ops` 运维 | OPS 刷新、救援动作、桥运维命令、永久删除、快照恢复 | 单独勾选，与功能写分开计数与审计 |

### 7.3 二次确认清单

配对授权覆盖常规调用；下列动作在能力位之外再加一道确认，防误触与重放。确认形态分两种：**两段提交**（helper 先以 `dryRun` 取得绑定工具名 + 参数哈希的一次性 `actionToken`，60 秒内回带执行；纯协议防呆，不打扰用户）与**事前用户指令**（该动作必须出现在用户当次任务里，助手不得在自主场景中自行发起）。

| 动作 | 能力 | 额外确认 |
|---|---|---|
| `ops_refresh`、`ops_validate`、全部只读 | read / ops | 无 |
| 常规语义写、软删、语言/开关 | write | 无（幂等键 + docHash + 快照即防呆） |
| `rescue_try_normal_start` | ops | 两段提交 |
| `rescue_arm_safe_mode` | ops | 两段提交 + 事前用户指令 |
| `ops_command_issue` / `ops_command_revoke` | ops | 两段提交 + 事前用户指令 |
| `rescue_clear_caches` | ops | 两段提交 + 事前用户指令 |
| `notes_delete_permanent` | ops | 两段提交（`confirmMemoId` 逐字回带）+ 事前用户指令 |
| 快照恢复（M3 `backup_restore_snapshot`） | ops | 两段提交 + 事前用户指令 + 恢复前强制再快照 |
| OPS 源头发布（Worker 改常量 / Pages 推送） | 非桥能力（Cloudflare/GitHub 各自授权） | 每次发布须用户当次指令，不并入桥配对授权 |

### 7.4 配对与凭据生命周期

- **设备身份**：App 首次启用桥时在 Keychain 生成设备密钥对（P-256，私钥不出设备）；设备向中继出示公钥指纹并对连接挑战签名，WS 连接不靠一条可复制的长效 bearer 单独鉴权。
- **配对流程**：App 生成 10 分钟一次性配对会话（会话 id + 指纹 + 待授能力清单）→ App 显示配对链接/二维码与指纹 → 用户在中继配对页核对指纹并确认 → 中继生成**客户端访问密钥**（256 位随机，只显示一次）→ 用户把该密钥粘进 Muse 安全凭据页完成连接器注册 → helper 以 `bridge_status` 只读调用验通，配对完成。三方（App 配对页、中继页、安全页）指纹必须一致，不一致即中止。
- **凭据分离**：设备凭据（App↔中继）与客户端凭据（连接器↔中继）是两条独立凭据，绑定同一 pairing 记录但不可互换；任一泄露只吊销其一侧并轮换。
- **中继存储**：只存凭据的加盐哈希、公钥、能力位、创建时间、最近在线与吊销位；明文凭据在中继侧只出现于签发响应一次。
- **随时可断**（三条独立路径，任一生效即断）：
  1. App 内「断开并吊销」：删本地 Keychain 凭据、关连接、向中继发吊销（离线时本地先删，中继侧凭据在下次出现时亦被拒——吊销位由用户经路径 3 补齐）；
  2. Muse 侧断开连接器（凭据失效于客户端）；
  3. 中继侧吊销：用户经 Cloudflare 账号在 Worker 管理面把 pairing 置 revoked，DO 立即踢下线并拒绝后续一切调用。
- **轮换**：App 内「轮换客户端密钥」生成新密钥、旧密钥即刻失效；轮换后须回 Muse 安全页更新凭据，旧值不留任何副本。

### 7.5 中继侧防护

- 全部端点 HTTPS/WSS；`/mcp` 校验客户端凭据哈希 + pairing 状态 + 能力位；`/app/connect` 校验设备签名 + pairing 状态。
- 限速与配额：按 pairing 限连接数（单设备单活连接，新连接顶旧连接并记行）、限调用速率与并发（写调用串行）；超限回 `rate_limited`。
- 中继不信任 App 回传的身份字段：设备身份以签名为准；不信任 helper 的自报能力：能力位以 pairing 记录为准。
- 中继代码与 `moment-ops` Worker 完全独立仓库目录/部署单元；部署凭据沿用 Cloudflare 连接器既有规矩，不新存明文 token。

---

## 8. 验证纪律（证据边界）

桥让验证变快，但不改变证据等级。以下纪律写进工具与场景的判定口径，任何场景报告必须逐项标注 `proven` / `inferred` / `unknown`：

1. **语义操作 ≠ 真实手指。** `editor_move_block` 通过只证明文档序变更、落盘与回读一致（proven 到数据层）；长按拾起是否触发、识别器仲裁谁赢、拾起浮层与滚动的真实交互，桥**测不到**（unknown），仍以用户 iPhone 真机操作 + DRAG Diag 行回读为终判。
2. **焦点/键盘同理。** `editor_focus_block` 与 `editor_open` 证明状态机到达（proven 到状态层）；真实键盘弹起、光标落点、拼音组字、动画体感属真机终判面。
3. **量测行是结果侧证据。** CREATE settle 各段与 DRAG 状态行来自 App 既有打点，桥只是搬运与解析；解析器版本变化不得改变原始行，报告须附原始行。
4. **每个场景结论必须四件套**：工具调用结果、操作后状态回读、对应 Diag 行、证据等级。缺回读或缺 Diag 的结论只能报 `inferred` 以下。
5. **写后必验持久化**：M2 起写场景的收尾固定包含「回读 docHash → 重启 App（用户手动重开）→ 再回读」一段；桥不能远程重启，此段以 `awaiting_manual_reopen` 状态挂起，不许跳过后报全绿。
6. **失败先读日志再下结论**：场景失败时先拉 `diag_tail` / 相关前缀行再定因，禁止在无 Diag 的情况下猜根因或直接重试写操作。

---

## 9. 构建集成

### 9.1 原则

- 桥按作用独立成文件，**不往 `MomentApp.swift` 堆实现**；既有文件只加接线点、只读访问器与共用动作抽取。
- 桥不得成为 `DiagLog`、`OpsDirectives.sanitize` 等叶子/无环模块的依赖源；依赖方向永远是桥 → 既有模块。
- 桥的启动不进首帧关键路径：根视图判定 bootMode 后异步启动（正常模式启完整分发器，安全模式启受限分发器），启动失败只记 Diag、不挡 App 使用。

### 9.2 新增文件清单

目录仍为 `rust/apps/ios/app/`：

| 文件 | 职责 |
|---|---|
| `MomentBridge.swift` | 桥门面与生命周期：`BridgeCoordinator`（ObservableObject）、开关状态机（off / unpaired / pairing / connected / backoff / revoked / opsDisabled）、分发器形态切换（full / limited）、启动/停止、与根视图的接线 |
| `MomentBridgeTransport.swift` | WSS 传输实现：连接、签名挑战、心跳、退避重连、帧大小守卫；实现 `BridgeTransport` 协议，为 M3 局域网适配留口 |
| `MomentBridgeProtocol.swift` | JSON-RPC / MCP DTO、协议版本常量、工具清单（manifest）与清单哈希、错误码、规范化 JSON 与 docHash 计算 |
| `MomentBridgeTools.swift` | 功能面分发器：工具注册表、参数校验、主线程串行调度、只读工具与语义写工具到 Library / 文档服务 / 量测解析的适配 |
| `MomentBridgeOps.swift` | 运维面：OPS 三层回读与刷新适配、桥运维命令存储/验签/合并口径（`bridge-ops-command.json`）、救援状态组装、救援动作适配（调共用动作服务）、单机安全模式布防标记 |
| `MomentBridgeSnapshots.swift` | 写前快照与操作流水：快照生成/清单/保留策略/恢复，幂等键去重表，操作审计记录（只记元数据） |
| `MomentBridgeSettings.swift` | 设置二级页（状态卡、配对流、能力展示、断开/轮换/吊销）、配对会话管理、Keychain 凭据存取 |
| `MomentBridgeDocumentService.swift`（M2） | 文档变更内核：从 `EditorModel` 抽出的块增删改/类型转换/重排纯变换 + 活跃编辑器适配（目标篇正打开时经其 EditorModel 落地，未打开时经 Library 文档路径落地），编辑器与桥共用 |

既有文件的配套改动（只列接线级）：

- `MomentApp.swift`：根视图挂 `BridgeCoordinator` 并按 bootMode 选分发器形态；`Library` 加 `bootApplied` OPS 快照留存、桥导航请求通道（`editor_open` 用）、设置路由加 `.bridge` 一例；`SettingsView.Sub` 加 `bridge`。
- `MomentOps.swift`：`OpsStep` 加桥步名（`MCP桥`）；`OpsDirectives.fetch` 补逐源结果回调（供 `ops_refresh` 回报）；guard 消费点改读合并口径的单一入口（源头 ∪ 桥命令，M3）。
- `MomentRescue.swift`：把尝试正常启动、检查热修复的动作体抽为共用 `RescueActions`（页面与桥共用），页面行为不变；状态区加一行桥状态 + 本地「断开桥」入口（仅在桥已配对时出现）。
- `MomentLaunch.swift`：不改结构；桥命令与布防标记的消费在 Library 启动判定处与哨兵/OPS 同点位读取（文件本身只在确需新增步名时动）。

### 9.3 快照与操作流水（写安全底座，M2 前置）

- **快照目录**：`Application Support/bridge-snapshots/`（与资料库同域但独立目录，不进用户备份 ZIP、不进 Diag 域）。
- **生成方式**：直调 FFI `exportBackup(zipPath:)` 写到快照目录，**不走** `Library.exportZip()`——后者会更新 `lastExportTs` 与备份操作记录，桥快照不得污染用户备份新鲜度口径。快照清单 `manifest.json` 记：snapshotId、时刻、触发工具、操作前 `libraryHash`、memoCount、字节数。
- **触发点**：每个「写会话」首个写操作前生成一份（会话 = 一次场景运行或一批连续调用，以 `idempotencyKey` 前缀/场景 runId 界定）；`notes_delete_permanent` 与快照恢复前**每次强制**单独生成。生成失败 → 写操作中止（`snapshot_failed`）。
- **保留**：最近 10 份且不超过 7 天，超限删旧并记 Diag；设置桥页面可见快照清单与占用。
- **恢复工具**（M3，`backup_restore_snapshot`）：入参 snapshotId + 两段提交；恢复前先对当前库再快照 → 校验目标快照清单与 zip 完整性 → 走 FFI `importBackup` 换库 → `Library.reload` → `verifyStore` 对账（计数与哈希须与快照清单一致，不一致报 `snapshot_failed` 并保留恢复前快照供回滚）。恢复是全库替换语义，返回中必须明示。
- **操作流水**：`bridge-snapshots/operations.jsonl`（或同域等价存储）逐条记 `{ts, requestId 短哈希, tool, idempotencyKey 哈希, targetId, preDocHash, postDocHash, resultCode}`；**不记正文、不记参数全文**。它同时是幂等去重与 `write_outcome_unknown` 后对账的依据。

### 9.4 设置页入口形态

与设置家族体例一致，不新造视觉语言：

- 设置主页在「数据」组之后加一行 `SetRow`：「MCP 桥」，meta 为状态短文（未启用 / 未配对 / 已连接 / 已断开 / 安全模式受限），点击进二级页。文案走五语包 `bridge.*` 键（键数在落码时按当时基线重算并同步 verify [9]，不沿用任何旧计数）。
- 二级页自上而下：状态卡（开关、连接状态、能力位、当前会话 id 短形）→ 配对卡（未配对时「开始配对」+ 指纹与倒计时；已配对时配对时间与中继域名）→ 会话与安全（断开、轮换客户端密钥、吊销配对——吊销为破坏性样式 + 本地确认）→ 快照（清单、占用、保留策略说明）→ 最近调用（只读元数据列表：时刻、工具名、结果码）。
- 开关用系统 `Toggle`（行为等价且系统更优的既定口径）；桥页全部交互留 Diag 行（`BRIDGE settings …`，只记动作与状态、不记凭据）。

### 9.5 Diag 打点面（桥全程留痕）

新增打点统一前缀 `BRIDGE` / `BRIDGEOPS`，逐项如下（全部只记元数据，**绝不记参数正文、笔记内容、凭据与完整令牌**；requestId 只记短哈希）：

| 时机 | 行模板（口径） |
|---|---|
| 桥状态变化 | `BRIDGE state <from>-><to> reason=<…>` |
| 连接建立/断开 | `BRIDGE session start id=<短> boot=<短>` / `BRIDGE session end reason=<…>` |
| 鉴权拒绝 | `BRIDGE reject code=<…> tool=<…>`（warn；同类刷屏走 logOnce） |
| 每次工具调用 | `BRIDGE call tool=<…> req=<短哈希> ms=<n> code=<ok\|…>`（结果行口径：记耗时与结果码） |
| 写操作 | `BRIDGE write tool=<…> target=<id> pre=<docHash短> post=<docHash短> snap=<snapshotId>` |
| 快照 | `BRIDGE snapshot id=<…> reason=<tool> bytes=<n>` / 失败 error 行 |
| OPS 桥命令 | `BRIDGEOPS issued/applied/expired/revoked/reject …`（含 commandId 与哈希短形） |
| 救援远程动作 | 复用 `RESCUE action …` 既有模板并加 `via=bridge` 标记；同时走 `recordRescueAction` |
| 安全模式受限拒绝 | `BRIDGE reject code=safe_mode_limited tool=<…>` |

### 9.6 与自救机制的关系

- **安全模式下桥的行为**：桥照常可启动（它不依赖开库），但只挂**受限分发器**：可用工具仅限 `bridge_status`、`app_state`（库字段降级）、Diag 全套、`ops_get_effective`、`ops_refresh`、`rescue_status`、`rescue_try_normal_start` 与本地断开。笔记读写、设置写、快照恢复一律 `safe_mode_limited`。受限分发器的实现不得引用 Library 的写面与 FFI 写入口——由 verify 断言扫描守住（§9.7）。
- **救援页独立性不破**：`RescueView` 渲染不依赖桥已连接；桥挂了、被吊销或被 OPS 禁用，救援页照常工作。救援页只**读**桥状态做呈现，并提供本地断开——这是单向依赖（救援页 → 桥状态），桥不得反向成为救援页的前置条件。
- **OPS guard 覆盖桥**：新增步名后，源头指令与桥命令都能以 `disableSteps: ["MCP桥"]` 停桥（下次启动生效，符合 OPS 既有语义）；此外写/运维工具在分发前复查合并指令作纵深防御（拉取到新指令的当前会话，写面先于读面被收紧）。`forceSafeMode` 在位时桥自动降为受限分发器。
- **桥不进启动关键路径**：桥连接失败、签名失败、中继不可达，都不得影响 bootMode 判定与正常加载；桥的任何代码不得出现在 `DiagLog` 与 `OpsDirectives.sanitize` 的依赖链上。

### 9.7 构建与断言增补

- **`build-app2.sh`**：新增 8 个 Swift 文件须同步三处——(1) 每一遍 `swift-frontend` 调用的文件名单（含既有各遍）都加全部新文件；(2) 每个新文件各加一遍以其为 `-primary-file` 的编译（产物 `bridge.o`、`bridge_transport.o`、`bridge_protocol.o`、`bridge_tools.o`、`bridge_ops.o`、`bridge_snapshots.o`、`bridge_settings.o`、`bridge_docsvc.o`）；(3) 链接行加全部新 `.o`。同步 `~/workspace/tree-sync/push_small.py` 传输名单与 tree overlay 拷入名单（三处名单一致性由 verify 断言核对源码侧两处，传输名单人工核对并记入落码报告）。
- **Info.plist**：M1/M2 无新增项（出站 WSS 不需局域网说明、不加任何后台模式——**明确不申请 `UIBackgroundModes`**，不以桥为由争取后台执行）。M3 若做局域网适配，再单独评审 `NSLocalNetworkUsageDescription` 与 Bonjour 服务声明。
- **`verify_ios.sh` 新增 [16] 组「MCP 桥」**（口径示例，落码时逐条写实）：桥默认关常量在位；源码零令牌/零密钥字面量；Keychain 存取符号在位且 UserDefaults 无桥凭据键；工具 manifest 计数与 `MomentBridgeProtocol` 清单一致；受限分发器源码段零 FFI 写符号（`upsertMemoJson` / `removeMemo` / `importBackup` / `putAttachment`）；`OpsStep` 桥步名在位；快照目录常量与 `exportBackup` 直调点在位且桥代码段零 `exportZip()` 调用；构建脚本八文件三处名单齐全；`bridge.*` 五语键齐备（并入 [9] 对账）。
- **冒烟**：桥批次出包前照常跑 `smoke_ios.sh` 全量；另加桥专项真机前检查（本机可做的）：manifest 哈希与连接器 ALLOWED_TOOLS 对账脚本、协议 DTO 的往返序列化单测（随桥文件附带，不进 App 运行时）。

---

## 10. 助手侧连接器

### 10.1 形态（按 custom_connector_setup 技能）

拟议目录（尚未创建）：

```text
~/workspace/custom-connectors/custom.moment-bridge/
├─ connector.yaml        # slug: custom.moment-bridge；api_hosts 只含中继域名；auth: bearer_header
├─ CONNECTOR.md          # 用途、端点、工具分层、失败码处置、授权与吊销流程
└─ bin/
   └─ moment_bridge.py   # 基于 MCP 客户端模板的 helper：固定端点、禁重定向、写不自动重放
```

- 端点钉死 `https://moment-bridge.overtrees.workers.dev/mcp`，`api_hosts` 只此一域；helper 不接受调用方自带 URL。
- 凭据走 `credentials.request_api_access` 安全流程注册（provider = moment-bridge、bearer header），助手全程不接触明文。
- helper 行为纪律：先 `list-tools` 拉清单并与 App manifest 哈希对账，对账不过即停；`ALLOWED_TOOLS` 只收录逐项审过的确切工具名（服务端新增工具默认拦截）；写工具超时/断线不自动重试，先回读对账（§3.3）；每次调用把工具名、结果码、耗时记入助手侧任务记录（不记正文）。

### 10.2 注册与授权流程（时点钉死）

1. **实施前**：主代理向用户报告将部署中继 + 注册连接器 + 在 ipa 内置桥，取得实施授权（本方案获批 ≠ 自动开工，仍以用户当次指令为准）。
2. 部署中继（配对功能先关），构建带桥 ipa，用户**覆盖安装**（不删旧 App——笔记在 App 数据内）。
3. 用户在 App 内打开桥开关 → 开始配对 → 核对指纹与能力勾选 → 生成配对会话。
4. 主代理调用 `credentials.request_api_access` 发起连接器注册 → 用户在 Muse 安全页待录入状态下，按 App/中继配对页指引把**中继签发的客户端访问密钥**粘入安全页（全程不经聊天）。
5. helper 首验：`list-tools` 对账 manifest → `bridge_status` → `app_state` → `diag_tail` 三个无害只读调用；App 侧 Diag 出现对应 `BRIDGE call` 行，视为配对闭环完成，向用户报告「已接入」。
6. 任一步失败：中止并按 §3.4 失败码报告；已生成的配对会话由用户在 App 内撤销或等其 10 分钟过期，不留半成品凭据。

### 10.3 失败形态（助手侧统一口径）

App 未打开 / 在后台 / 被杀 → 中继无活连接 → helper 得 `app_offline` / `app_backgrounded`：结论写明「需用户把 Moment 切到前台」，不重试轰击、不改走其他通道。桥被 OPS 禁用 → `bridge_status` 不可达且中继回 pairing 的 `opsDisabled` 标记（最后一次会话留痕）：报告为「桥已被运维指令停用」。凭据被吊销 → `revoked`：报告吊销事实并停手，重新接入必须重新走 §10.2 全流程。

---

## 11. 分期与验收

### M1 — 连通 + 只读排查（含运维只读）

**范围**：专用中继（Worker + DO + 配对/吊销）；App 出站 WSS；三道授权门与 Keychain 凭据；连接器注册；工具：`bridge_status`、`app_state`、Diag 全套（含订阅/hint 与 `diag_export`）、`notes_list` / `notes_search` / `notes_get`、`settings_get`、量测回读两件、`ops_get_effective`（含 `bootApplied` 前置）、`ops_get_sources`、`ops_refresh`、`rescue_status`；设置桥二级页（状态/配对/断开/吊销）；Diag 打点与 verify [16] 基础断言（默认关、凭据存储、受限分发器禁区）。

**验收口径**：

1. 配对全流程真机走通，指纹三方一致；错指纹/过期会话被拒且有 Diag 行。
2. `diag_tail` 与 App 内导出诊断逐行对账一致（同 scope 同过滤）；断网重连后按游标补拉无缺行（以行时间戳序列核对）。
3. App 切后台/被杀/关桥三种状态下，工具分别回 `app_backgrounded` / `app_offline` / `app_offline`，无一假成功。
4. 安全模式下受限清单逐个验：只读面可用、任一写工具回 `safe_mode_limited`；救援页在桥断开时照常可用。
5. OPS 链：改测试指令 → `ops_get_sources` 双源可见 → `ops_refresh` 成功源正确 → 重启后 `bootApplied` 与源头哈希一致且 Diag 有 fetched 行。
6. 吊销三路任选其一验通：吊销后一切调用回 `revoked`，App 内状态同步为已吊销。

### M2 — 语义读写 + 运维动作

**范围**：文档变更内核抽取（`MomentBridgeDocumentService`，编辑器共用）；快照与操作流水底座；笔记/编辑器写工具全套、软删/恢复、永久删除（受限形态）；`settings_set_language`、`settings_set_toggle`（首批仅 `diagAutodel`）、`settings_clear_weather_key`；`ops_validate`、`rescue_arm_safe_mode`、`rescue_try_normal_start`；verify [16] 补齐写面断言（快照直调 FFI、幂等、docHash 守卫）。

**验收口径**：

1. 全部写场景只对验收夹具笔记执行：新建 → 插块 → 改块（含 runs）→ 类型转换 → 语义重排 → 保存 → 软删 → 恢复，每步写后回读 docHash 与块序，逐步对账。
2. 并发守卫：拿旧 `expectedDocHash` 重放写请求得 `revision_conflict`；同 `idempotencyKey` 重发得首次结果且库无二次变更（libraryHash 不变）。
3. 快照：任选一写场景，在 App 内以快照恢复演练（本地触发）回滚到写前状态，计数与哈希对齐快照清单。
4. 持久化：夹具笔记写完后由用户手动重开 App，回读内容与写后一致（§8 第 5 条流程）。
5. 运维动作：布防安全模式 → 用户重开 App 进安全模式（Diag 有布防与消费行）→ 桥在受限面调 `rescue_try_normal_start` 回正常模式；全程 `lastRescueAction` 留痕可回读。
6. 回归不破：编辑器既有行为冒烟全绿（文档内核抽取的行为等价由既有 verify 组 + tree 冒烟证明）。

### M3 — 场景脚本库 + 运维打通

**范围**：`scenarios_list` / `scenarios_run` / `scenarios_get_result` 与场景库首批（下表）；桥运维命令四件（§6.2b）；`backup_restore_snapshot`；`rescue_clear_caches`（R3 落地后）、`rescue_open_readonly`（R2 落地后）；OPS 源头发布 runbook（助手侧编排文档，落 `CONNECTOR.md` 附录）；局域网传输适配（可选，不阻塞其余项）。

**场景库首批**（每场景固定输出 §8 的四件套证据包）：

| 场景 | 内容 | 证据边界标注 |
|---|---|---|
| `create_transition` | 经与「+」钮同一导航路径新建并打开，等待并解析 CREATE settle 各段，与基线阈值比对 | 数据/状态层 proven；顺滑体感仍真机终判 |
| `drag_semantic_reorder` | 夹具多块笔记语义重排 → 回读块序 → 重开再回读 | 只证语义序与持久化；真实拾起不在此场景 |
| `drag_trace_review` | 用户真机完成一次拖拽后，回读 DRAG 归组行并判定链路完整性（attached → target → pickup → drop/cancel） | 行在即 proven 到打点层；手感真机终判 |
| `weather_settings_flow` | `settings_get` 回读双 key 状态/来源 → 触发天气刷新 guard 点状态确认（key 的本地录入由用户在设置页完成，场景只验状态迁移） | 不经桥碰 key 值 |
| `language_roundtrip` | 切语言 → `app_state` 验生效码 → 切回 | proven 到偏好与解析层 |
| `ops_convergence` | §6.1 三步确认链自动化 | proven 到 bootApplied 哈希一致 |
| `safe_mode_drill` | 布防 → 人工重开 → 受限面自检 → 尝试正常启动 → 留痕回读 | 需用户配合重开，场景以挂起态等待 |
| `delete_restore_roundtrip` | 夹具软删 → 窗口内恢复 → 再软删 → 窗口后确认真删（可选永久删除段） | 真删段须事前用户指令 |

**验收口径**：每场景在真机连跑两遍结论一致；失败场景能凭其证据包独立定因（不需再向用户索要截图/日志）；场景产生的夹具笔记有清单、有清理结果报告，绝不混入用户真实笔记的判定。

---

## 12. 风险与红线对齐

### 12.1 全开读写的数据风险与兜底（按风险逐项）

| 风险 | 兜底 |
|---|---|
| 助手误写/误改真实笔记 | 写前快照（§9.3）+ docHash 乐观并发 + 幂等去重 + 操作流水可对账；场景纪律：写场景只对夹具笔记，真实笔记写操作须出自用户当次任务 |
| 误删 | 活跃笔记只许软删（8 秒撤销窗口与现行 UI 同一机制）；永久删除受限形态 + 强制快照 + 两段提交（§5.5） |
| 写一半断线、结果未知 | `write_outcome_unknown` 口径 + 流水对账，先回读再决策，禁止盲重试 |
| 中继被攻破或凭据泄露 | 中继只存哈希、设备签名鉴权、能力分层、单活连接、限速；吊销三路；M2 开放正文读写前，须就是否给设备段加端到端信封加密（DO 只路由密文）做一次专项评审并把结论写回本方案——在评审结论落地前，正文经中继为 TLS 明文路由，此事实须在配对页明示给用户 |
| 桥成为启动崩溃源 | 桥不在首帧关键路径、叶子依赖纪律、OPS 可禁桥、受限分发器与救援页解耦；桥代码异常只许降级桥自身（记 error 行后停桥），不许带崩 App |
| 快照占空间 / 含全量数据 | 本地保留上限 10 份 / 7 天；快照不出设备；设置页可见可清（本地清理入口） |
| 运维命令被滥用 | 只能收紧、TTL ≤24h、单条活动、签名 + pairing 绑定、全程 BRIDGEOPS 留痕、源头放松权不在桥 |

### 12.2 与既有红线的关系

- **「绝不轻易清站点数据」类红线**：原生对应物是「不删 App、不清 Application Support」。桥的任何工具不提供清数据入口；`rescue_clear_caches` 的清单与 S7 逐字一致且明示其定位只是排查项、不冒充修复。ipa 交付口径不变：覆盖安装，不删旧 App。
- **自救红线**：核心数据层不入热修面（桥命令与 OPS 同守）；救援页零 FFI 写（桥不改变之）；DiagLog 叶子纪律（桥不反向污染）。
- **工程红线**：改前通读、行为等价、根治不打补丁（文档内核抽取即按此）、独立文件、尾巴零残留（桥若将来退役，须连同中继、连接器、设置行、语言键、verify 断言一并清零，grep 为据）。
- **凭据红线**：令牌不进聊天/仓库/Diag/日志/命令行；天气 key 不经桥读写值；钥匙串文件规矩不因桥改变（桥凭据走 Keychain + Muse 安全页，不入 `1.txt`）。

### 12.3 正式版去留口径

**推荐：桥常驻正式 ipa、默认关闭 + 配对制。** 理由：桥的价值恰在出问题时可用，事后另发「带桥版」重装会丢现场（且覆盖安装虽保数据，但闪退类问题要的就是问题版本上的桥）。常驻成立的前提（缺一即改走构建变体）：

1. 默认关、未配对零网络行为（verify 断言 + 真机抓包抽查）；
2. 凭据 Keychain + 中继哈希存储 + 吊销三路全部落地；
3. 安全模式受限分发器与禁区断言全绿；
4. 写前快照与操作流水落地（M2 起）；
5. 工具 manifest 与连接器 ALLOWED_TOOLS 对账机制在位，后加工具默认不通。

**备选：构建变体**（`MOMENT_BRIDGE=off` 时桥文件不参与编译、设置行不出现）。保留为兜底开关：若将来分发渠道（上架审核等）对远程控制面有合规要求，或前提条件任一被破坏，用变体出不带桥的包，而不是临时删代码。变体切换须经 verify 断言证明桥符号零残留。

---

## 附录 A. 工具索引（名称 / 属性 / 期）

| 工具 | 属性 | 期 |
|---|---|---|
| `bridge_status` | 只读 | M1 |
| `app_state` | 只读 | M1 |
| `diag_tail` / `diag_search` / `diag_sessions` / `diag_snapshot_meta` / `diag_export` | 只读 | M1 |
| `diag_subscribe` | 只读（会话订阅） | M1 |
| `notes_list` / `notes_search` / `notes_get` | 只读 | M1 |
| `metrics_create_settle` / `metrics_drag_trace` | 只读 | M1 |
| `settings_get` | 只读 | M1 |
| `ops_get_effective` / `ops_get_sources` | 只读 | M1 |
| `ops_refresh` | 运维 | M1 |
| `rescue_status` | 只读 | M1 |
| `notes_create` | 数据写 | M2 |
| `editor_open` / `editor_get_state` | 语义（开为写、读为只读） | M2 |
| `editor_insert_block` / `editor_update_block` / `editor_set_block_type` / `editor_delete_block` / `editor_move_block` / `editor_focus_block` / `editor_save_now` | 语义写 | M2 |
| `notes_soft_delete` / `notes_restore_deleted` | 数据写 | M2 |
| `notes_delete_permanent` | 数据高危（ops） | M2 |
| `settings_set_language` / `settings_set_toggle` / `settings_clear_weather_key` | 语义写 | M2 |
| `ops_validate` | 只读 | M2 |
| `rescue_arm_safe_mode` / `rescue_try_normal_start` | 运维高危 | M2 |
| `scenarios_list` / `scenarios_run` / `scenarios_get_result` | 场景（内含读写按场景声明） | M3 |
| `ops_command_preview` / `ops_command_status` | 只读 | M3 |
| `ops_command_issue` / `ops_command_revoke` | 运维高危 | M3 |
| `backup_restore_snapshot` | 数据高危（ops） | M3 |
| `rescue_clear_caches` | 运维高危（待 R3） | M3 |
| `rescue_open_readonly` | 运维（待 R2） | M3 |

## 附录 B. 实施前待用户裁定的点（不阻塞方案成立）

1. 中继域名与 Worker 名（拟议 `moment-bridge.overtrees.workers.dev`）是否照此。
2. 配对时三层能力是否一次全授（用户已定全开口径，建议按 §7.2 分层展示、由用户在配对页一次确认）。
3. M2 前的正文端到端加密专项评审排期（§12.1）。
4. 桥批次与现有版本队列（拖拽三轮 0.9.49、天气设置重构、J2/K/I4/I5）的先后——建议 M1 插在当前已落码批次出包之后、与后续批次错峰，避免同批既改编辑器又加桥面。
