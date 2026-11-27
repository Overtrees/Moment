# 桥稳定性全面根治：偶发连不上定因与全链修复（2026-11-27）

> 状态：**中继已部署生效 + 连接器已生效；App 侧落码未提交、未 bump**（随 0.9.57）。基线 HEAD fdb1a67（0.9.56）。
> 领地：`MomentBridgeTransport.swift`（整体重写记账方式）/ `MomentBridge.swift`（协调器稳定性段）/ `bridge/relay/worker.js`（BridgeRoom 连接管理段）/ 连接器 `bin/client.py` + `CONNECTOR.md` / verify [16] 新增 B16-18、B16-19。
> 在途纪律：动工前快照全树 diff（1932 行），完工以逐行多重集口径复验——在途各批（布防/圆角/回归三线/U4a/天气）的改动行零丢失；worker.js 与 verify_ios.sh 仅在本人段内增改（两处 diff hunk 合并报警经逐行复核为假象）。

---

## 一、故障谱逐个定因（证据分级）

| # | 现象（2026-11-27 主线亲历） | 定因 | 级别 |
|---|---|---|---|
| F1 | 15:07 前后 diag_tail / app_state 调用成功 | 健康路径本身无病：配对、挑战签名、转发、回帧全链可用 | proven（实测） |
| F2 | 16:24 `no live device connection`（retryable=false） | 中继房间内无 authed socket——该错误码的唯一产生路径即 `deviceSocket()` 返回 null。当时 App 处于后台/被挂起，socket 已在中继侧消亡，与平台行为一致；但 retryable=false 把它变成调用方的终局失败，且无任何等候/重试机制兜底 | 机制 proven；该实例的设备状态 inferred（当时无端内日志可读） |
| F3 | 其后多轮 `device did not answer in time`（retryable=true） | socket 被选中但限期内无回帧。代码级 proven 的产生机制共四条，见第二节 D2/D3/D4/D6，任一成立即出此码 | 机制 proven |
| F4 | 两轮重试环（8 次、10 次，间隔 12–15s）全败；第二轮用户明示已去前台仍全败——**前台不应答** | 见第二节 D1（传输层代次竞态造僵尸连接）+ D5（前台钩子从不探活/重连）：两者叠加时，App 在前台、协调器自认在线、中继见 socket 在册，但挑战/工具帧的应答发不出来或路由喂给僵尸连接，重连越频繁越容易复发、自持成环。「iOS 后台挂起属设计行为」对 F4 不成立——该窗内 App 在前台 | 机制 proven（代码通读 + interleaving 构造）；该窗的具体 interleaving inferred（端内日志未及读取；新打点上线后此型故障可由日志直接定案，见第六节） |

## 二、全链缺陷清单（通读三方源码后成立）

### App 侧

- **D1 传输层无连接代次（结构性缺陷，头号）**：`BridgeWssTransport` 的全部回调只读共享的 `task`/`isOpen`。`connect()` 先 `close()` cancel 旧 task 再建新 task 并置 `isOpen=true`；旧 task 挂起的 receive 完成回调由 URLSession 异步迟到投递，落点只看 `isOpen`——新连接已置真，于是迟到的失败回调执行 `handleDown()`：把**新连接**判 down、`task=nil`。后果链：新 socket 实际连在中继侧、挑战帧经其 receive 正常到达协调器，但协调器回挑战应答时 `send` 的 `guard let task` 先失败——**socket 活着、帧收得到、永远发不出应答**；中继侧该 socket 永不 authed（回 F2 型）或已 authed 的孤儿连接收下工具请求后 App 无法回帧（回 F3/F4 型）。`send` 的错误完成回调同病（旧 task 的迟到 send 失败同样误杀新代）。每次重连都掷一次骰子，退避重连越勤、命中越密。
- **D5 前台无快速通道**：`willEnterForeground` 钩子在 `transport.isOpen` 为真时只发 presence 帧——而 isOpen 是 `resume()` 时乐观置真、半死连接下永不翻假的量。半死连接（挂起期底层链路已断、URLSession 未报失败）回到前台后，唯一自愈路径是心跳：20s Timer + pong 陈旧阈值 50s，最长约 70s 才触发重连，且 Timer 在主 runloop `.default` 模式下滚动期不触发。前台数秒内必连通无从谈起。
- **D6 退避计数不清零**：`backoffAttempt` 只在 welcome 清零。用户可见触发（回前台/开关/配对完成）走 `connectNow` 失败后，下一轮退避仍从旧计数（最高 30s 档）续算，用户盯着界面干等。
- **D7 无网络路径感知**：无 NWPathMonitor。Wi-Fi/蜂窝切换、断网恢复全靠 socket 自己报错——半开连接可以长时间不报错。
- 附带：`sendPing()`（协议级 ping）存在但全仓零消费方，且其 pong 错误回调被吞（`{ _ in }`）——按红线 5 本次一并删除，不留死代码。

### 中继侧（BridgeRoom）

- **D2 选连取「第一个 authed」**：`deviceSocket()` 按 `getWebSockets` 顺序返回首个 authed socket，不看 epoch、不看新鲜度。僵尸连接（对端进程已死/半开、边缘侧仍在册）排在前面时，请求被持续喂给它直至各自超时（F3 的稳定产生器）。
- **D3 pending 无连接归属**：任一 authed socket 的 `webSocketClose` 无条件结清**全室** pending——新连接已顶替上线、在飞调用正等回帧时，旧连接迟到的 close 事件把新调用误杀为 app_offline（重连 churn 期的偶发失败源）。
- **D4 无 `webSocketError` 处理器**：异常断链（无 close 握手）不触发 close 语义，在飞请求只能干等各自 15–30s 超时。
- **D8 无等设备窗**：无可用 socket 时立即回 app_offline。设备常在调用到达的同一秒内重连落地（退避到点/前台探活），这类调用被全数误杀。
- **D9 无僵尸回收**：authed socket 无任何新鲜度判定；未认证 socket（挑战永不应答）同样无限滞留。`rec.lastSeenAt` 是全室共享量，多连接并存时被活连接的心跳持续刷新，掩盖僵尸连接的存在——新鲜度必须逐 socket 记（attachment）。
- 注：中继已用 hibernation API（`acceptWebSocket`），socket 可跨 DO 休眠/驱逐存续，此点无病；新连接顶替旧连接（4002 superseded）在认证成功时已执行，保留。

### 客户端（client.py）

- **D10 零重试**：任何错误一概抛 `McpError`。中继回的 retryable 标志从未被消费——F2/F3 在调用方一律终局。

## 三、落码清单（缺陷 → 修复 → 针对故障）

### App 侧（随 0.9.57 出货）

| 修复 | 内容 | 针对 |
|---|---|---|
| 传输层代次作用域（整体替换记账，非叠加特判） | `generation` 每次 connect/close 递增；receive/send 完成回调捕获所属代次与 task 本体，入口先验 `gen == generation`，旧代迟到回调静默丢弃、绝不触碰新连接状态；`handleDown(gen:reason:)` 同验代次；`onSocketDown` 带 reason（receive_error/send_error）。`suppressDown` 标记整删（代次语义下主动关闭本就不产生 down 事件）、`sendPing` 死方法删除 | D1（F3/F4 头号机制） |
| 前台探活 | `didBecomeActive` 且 socket 名义在位 → `probeLiveness()`：发一帧 app 级 ping，5s 内 pong 未推进 `lastPongAt` 或未达 connected 即 `forceReconnect(reason: probe_timeout)` 硬重连；探活带令牌（probeToken），新连接/新探活使旧结论失效 | D5（F4） |
| 路径看门狗 | NWPathMonitor 常驻：路径签名（接口类型集 + 可达）变化且恢复可达时——已连先探活、未连立即 `connectNow(reason: "path")`；首报只建基线 | D7 |
| 硬重连单点 | `forceReconnect(reason:)` 收敛心跳超时与探活失败两路（关连接 + 断开处置），心跳超时 reason 由旧 `socket_down` 细化为 `heartbeat_timeout` | D5 |
| 退避重置 | `connectNow` 对一切非 backoff 触发先 `backoffAttempt = 0`，用户可见触发永远从首档（1s）起 | D6 |
| 生命周期打点 | 新增 `BRIDGE connect reason=<r> attempt=<n>`、`BRIDGE session down reason=<r> dur=<s>s`（welcome 记 sessionUpAt、断开消费）、`BRIDGE probe ok` / `BRIDGE probe fail state=<s>`、`BRIDGE path changed sig=<…>`；既有 state/session up/reconnect_scheduled 行不动 | 量测（第六节） |

### 中继侧（已部署，见第四节）

| 修复 | 内容 | 针对 |
|---|---|---|
| 选连口径 | `deviceSocket()` 只认 authed 且 `att.lastSeenAt` 在 120s 窗内的 socket，多条取 epoch 最大、同 epoch 取最新 lastSeenAt | D2/D9（F3） |
| 逐 socket 新鲜度 | attachment 新增 `lastSeenAt`（认证时写、任一入站帧 ≥5s 节流刷新）与 `connectedAt`；原全室 `rec.lastSeenAt` 保留为元数据但不再作选连依据 | D9 |
| pending 按连接打标 | 转发时 `pending.set(id, {…, ws})`；`webSocketClose`/`webSocketError`/顶替循环只结清挂在该 socket 上的条目（`failPendingFor`），顶替时立即结清不等超时 | D3/D4（F3） |
| webSocketError 处理器 | 与 close 同处置 + 主动关连接 | D4 |
| 等设备短窗 | 无可用 socket 时 200ms 轮询至多 4s，落地即转发；窗尽回 `app_offline` 且 **retryable=true**（原 false 一并修正——等窗已尽仍无设备属可重试态，只读工具由客户端安全重发） | D8/D10（F2） |
| alarm 僵尸回收 | 认证/帧活动时 `ensureAlarm` 把闹钟定在最近连接的僵尸时刻 +1s；`alarm()` 逐条关僵尸 authed（4000 stale_socket）与超时未认证（4000 auth_timeout）连接并续定 | D9 |

常数口径：App 前台心跳 20s 一帧 → 中继僵尸阈值 120s = 6 帧余量；后台 App 不能发心跳也无法应答，超阈值按离线处理与语义一致，前台回来探活/重连即刷新。**未动工具面**：TOOLS/能力集/manifest 零改动（本批 hunk 与布防批的入册 hunk 相邻但内容零交叠）。

### 客户端（已生效）

- 只读白名单（`READ_RETRY_TOOLS` 15 件：状态/Diag/笔记读/设置读/在席读/uitest 读等纯读面）遇 `app_offline && retryable=true` 自动重试：共 3 次尝试，间隔 2s/5s，stderr 留 note。写/运维/uitest_run 永不自动重放（docstring 与 CONNECTOR.md 已同步改口径）。
- 与中继 4s 等窗叠加的最坏阻塞：单次只读调用 ≈ 3×(4s 等窗 + 限期) + 7s 间隔 ≈ 21s（实测见第四节），不达分钟级。

## 四、实证记录

- **中继机制模拟（本机 Node 24，真实 BridgeRoom 代码 + 假 DO state/假 socket + 真实 ECDSA 配对）五景全过**：S1 顶替关旧（4002）+ 选连取新；S2 无关 socket 的 webSocketError 不冲在飞 pending、本连接 error 立即结清不等超时；S3 僵尸 socket 被选连排除、心跳帧刷新后在等设备窗内复活并完成调用；S4 无设备等满 4s（实测 4010ms）回 app_offline(retryable=true)；S5 认证时闹钟已定、alarm 到点关僵尸（4000 stale_socket）。
- **部署对账**：deploy.py 部署 200；经 API 下载线上脚本与仓库 worker.js **逐字节一致**（47,337 B）；线上 list-tools 回 **31 件**、按公式重算 manifestHash = `a52116c3…`，与 0.9.56 基线一致、零漂移。
- **客户端实测（对线上、App 离线场景）**：`bridge_status`（只读）3 次尝试、stderr 两行 retry note、总时 21.4s 后回 app_offline；`ops_refresh`（非白名单）恰 1 次尝试、5.8s（单个等设备窗）返回，无重试。
- **verify**：新增 B16-18（App 侧：代次/探活/路径/退避重置/打点/sendPing 零残留）与 B16-19（中继侧：选连/新鲜度/pending 打标/error 处理器/等窗/alarm/retryable 回码）全绿；本机全量 275 ✓，仅剩 ipa 陈旧 + 产物语言包 2 条既有产物类 ✗（tree 构建自解，与各批本机基线一致）。
- **App 侧编译**：本机无 swiftc，编译级自检随 0.9.57 的 tree 全量冒烟（smoke_ios.sh）把关；改动已逐行自检（代次校验点、探活令牌、路径签名三处为新增代码，其余为签名线程化替换）。

**已生效范围**：中继新选连/等窗/pending 隔离/alarm 对**现行 0.9.56 App 立即生效**（新鲜度刷新是中继侧逻辑，旧 App 的 20s 心跳帧即触发）；客户端重试即时生效。App 侧代次/探活/路径/退避随 0.9.57 装机后生效——F4 的 App 侧一半在装机前仍可能复现，中继侧已先行堵住 D2/D3/D8 三条产生路径。

## 五、平台边界（如实划界）

- **后台不可达是平台事实**：iOS 挂起即冻结进程与 socket，本批的「稳定在线」保证域 = **前台**（回前台 5s 探活定生死、失败立即硬重连、退避从 1s 首档起）。后台远程唤醒需要 APNs 推送通道——当前签名为 TEST SIGNING（无推送权益配置）且无推送基建，本批不假装解决，登记为边界项：缺 APNs 证书/权益 + 服务端推送发送方。
- **半开连接无系统级探针**：URLSession 不提供 TCP 真存活查询，探活只能走应用级 ping/pong（中继对 app 级 ping 必回 pong，已核）；5s 窗是「前台必达」与「不误杀慢网络」的折中，弱网下偶发探活误判的代价仅是一次无害重连。
- **DO 驱逐与 pending**：在飞请求会钉住 DO 不被驱逐，pending（内存态）在请求生命周期内安全；驱逐只影响空闲期，而空闲期无 pending。此点经代码路径核对成立，无需落盘化。
- **部署迁移一次性收敛**：部署瞬间已 authed 的旧 attachment 无 lastSeenAt，按僵尸论处直至其首帧到达刷新（旧 App 心跳 ≤20s 一帧）——部署后至多一个心跳周期内选连可能短暂落空，等设备窗 + 客户端重试已覆盖该窗。

## 六、真机量测判读法（0.9.57 装机后）

Diag 中 `BRIDGE` 行即连接生命周期账本（diag_tail / diag_search 搜 `BRIDGE`）：

- **前台→连通耗时**：取 `BRIDGE presence state=foreground`（或 `BRIDGE probe fail`）时刻 → 其后第一条 `BRIDGE state …->connected` / `BRIDGE session up` 时刻之差。目标：已连且活 = 一行 `BRIDGE probe ok`（≤5s）；半死 = probe fail 后 ≤ 退避首档（~1–2s）+ 握手 ≈ 数秒内 session up。
- **断连原因分布**：`BRIDGE session down reason=` 计数——`receive_error`（对端/网络真断）、`send_error`、`heartbeat_timeout`（稳态半死被心跳抓获）、`probe_timeout`（前台探活抓获）；只有 connect 无 session up 且反复 `session down` 缺席 = 握手期失败（看 `BRIDGE connect reason=` 的触发源分布：start/foreground/path/backoff/paired）。
- **代次竞态的旧病签名**（应绝迹）：高频 connect 循环伴随 session up 缺失、或 connected 后数秒内无故 backoff。新实现下迟到回调被代次吞掉，此签名再现即为新回归证据。
- **中继侧旁证**：调用方耗时分布——命中等设备窗的调用 ≈ +4s 后成功；僵尸被回收后（alarm 4000 关连接）App 侧应见一条 receive_error 的 session down 并自动重连。
