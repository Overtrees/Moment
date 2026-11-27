# 已配对每次进入 App 仍走可见链接流程：双版本定因与机制级根治清单（2026-11-27）

> 状态：**只读定因完成、报告先行；落码未动**——落码硬门（0.9.57 组版提交落定）未满足：HEAD 仍为 fdb1a67、工作树含组版分拣中的全部未提交改动，本批领地（MomentBridge.swift / MomentBridgeTransport.swift / MomentBridgeSettings.swift / bridge/relay/worker.js）与组版、桥稳定性批 hunk 相邻，按纪律停在报告。
> 口径（用户 2026-11-27 16:57 裁定）：**不做状态 UI 迟滞**——在消费方藏文字属打补丁，已作废。状态显示继续如实反映状态机；根治对象是可见流程本身：逐个消除续连链上的可省环节，使实际状态序列短到不存在值得呈现的中间态。验收以 BRIDGE Diag 量得的「进入 App → 连通」耗时与状态机实际中间态为准。

---

## 一、用户可见形态定性

呈现面只有两处，都逐字直读协调器 `linkState`、零迟滞零缓存（grep 全仓实证）：

| 面 | 位置 | 呈现 |
|---|---|---|
| 设置主页 MCP 桥行 meta | MomentApp.swift:17336 `Lang.t(bridge.linkStateKey)` | 行右侧小字 = 当前状态文案 |
| 桥设置二级页配对卡头 | MomentBridgeSettings.swift:154 同键 | 卡内状态文案 |

状态文案（zh-CN）：`connected=已连接 / connecting=连接中 / backoff=重连中 / pairing=配对中 / unpaired=未配对 / off=未开启`。

已配对用户每次进入 App 实际经历的状态序列（两版本共同骨架）：

- **冷启**（进程被杀/被系统回收后打开）：`off → connecting → connected`。起点 = Library init 内 `DispatchQueue.main.async` 派发的 `BridgeCoordinator.start()`（MomentApp.swift:474），已配对即 `connectNow(reason:"start")`，置态 connecting 后才建连；welcome 到达才置 connected。中间态时长 = 整个建连+握手链（第三节账）。
- **温启回前台**（进程尚存）：socket 若真存活 → 无序列（仅 presence 帧，状态恒 connected）；socket 已死（长挂起后的常态，见二节）→ 死亡被发现后 `backoff（重连中）→ connecting（连接中）→ connected`，外加死亡发现前的「假已连接」窗。

即：用户看到的不是配对流程重走（配对材料完好、无任何重新配对），而是**连接状态机每次进入都把全量建连过程如实播报**，且序列长度被多个可省环节与发现延迟拉长。

## 二、定因（分版本）

### 2.1 现行 0.9.56（装机版，HEAD 代码）

| # | 机制 | 级别 |
|---|---|---|
| A1 | **每次冷启必全量握手**：配对身份只存 pairingId + 设备私钥（Keychain），协议无会话恢复概念——每条新连接必走 WSS 建连 → 挑战 → ECDSA 签名 → 中继验签 → welcome。配对凭据从未被用来「续」会话，只被用来每 次重新证明。 | proven（代码） |
| A2 | **温启死亡发现慢且被动**：旧传输层 isOpen 在挂起期恒真（回调冻结），回前台钩子（willEnterForeground）只看 isOpen 发 presence、不验活。socket 死亡要等挂起的 receive/send 在解冻后报错才翻 backoff，其后还要先睡退避首档 1–2s 才开始重连——可见序列 = 假已连接（不定长）→ 重连中 1–2s → 连接中（全量握手）→ 已连接。 | proven（代码） |
| A3 | **退避不清零放大序列**（稳定性批 D6）：backoffAttempt 只在 welcome 清零，多次失败后回前台手动路径仍背最高 30s 档，「重连中」可长达数十秒。 | proven（代码，稳定性批已定因） |
| A4 | **代次竞态可把一次续连变成循环**（稳定性批 D1）：旧连接迟到回调误杀新连接 → 连接中/重连中反复横跳、自持成环，用户感知为「一直在走流程、走不完」。 | proven（稳定性批已定因，本批不重复论证） |
| A5 | **中继侧每帧控制面带存储往返**：challenge_response 处理 = storage get（record）+ WebCrypto 验签 + storage put（saveRecord 写 epoch/lastSeenAt）+ setAlarm，全部在 welcome 之前串行等待；ping/presence 处理同样每次先 record get + saveRecord put 才回 pong/落盘——20s 心跳即每 20s 一次无谓存储读写，且每帧 pong 都被这组往返延迟。 | proven（worker.js 通读：webSocketMessage 的 challenge_response / ping / presence 三段） |

### 2.2 桥稳定性批新传输层（0.9.57 在途，工作树代码）

已消除：D1 代次竞态（代次作用域记账）、D6 退避不清零（connectNow 对非 backoff 触发清零）、无路径感知（NWPathMonitor 看门狗）、中继选连僵尸/pending 误杀/无等设备窗（中继侧已部署）。

**仍然成立、本症状不因该批消失的机制：**

| # | 机制 | 级别 |
|---|---|---|
| B1 | **全量握手未动**：A1 在新层原样保留——每次连接仍是挑战-签名-验签-落盘全套。可省环节（会话恢复）该批未触及（不在其故障谱内）。 | proven（代码对照） |
| B2 | **前台探活的 5s 判定窗即新的可见延迟源**：didBecomeActive → probeLiveness 发 ping，但结论 work 固定在 +5s 才执行。socket 已死时：前 5s 状态仍显示已连接（假在线），5s 到点才 forceReconnect → 重连中（退避 1–2s）→ 连接中（全量握手 ~1s）→ 已连接。**回前台后约 7–8s 才真连通**，且中间态一个不少。pong 提前到达也不能提前结案（work 只在 5s 时跑一次检查）。 | proven（MomentBridge.swift probeLiveness 通读） |
| B3 | **探活可误杀冷启在飞连接**：didBecomeActive 在冷启同样触发，此时状态为 connecting、isOpen 已被乐观置真，探活照跑；其判定要求 5s 内 state==connected——慢网络/DO 冷唤醒下首连超过 5s 时，探活会 forceReconnect 一条健康的在飞连接，平添一整轮 backoff+connecting。该窗具体命中率 inferred（取决于首连耗时分布），机制 proven。注：探活的预认证 ping 本身可达——中继 ping 处理无 authed 门（已核 worker.js），且 startHeartbeat 在 welcome 时重置 lastPongAt，故「5s 内完成首连」时探活判 ok，不误杀；误杀域 = 首连 >5s。 | 机制 proven / 命中率 inferred |
| B4 | **中继 ping 的存储往返未动**（A5 后半）：新层探活/心跳的每一帧 pong 仍排在 record get + saveRecord put 之后，pong 时延被存储往返放大（量级见三节），探活判定随之变慢、变贵。稳定性批已把选连新鲜度改走逐 socket attachment（lastSeenAt ≥5s 节流），rec.lastSeenAt 已降为元数据——ping 路径的全量读写属可整删的重复同步。 | proven（worker.js 通读） |
| B5 | **welcome 的 scopes 回写 Keychain 每连一次**：welcome 处理无条件 `identity.scopes = granted`（kcSet = SecItemDelete + SecItemAdd）。毫秒级，但属每连必做的重复同步，可改「变化才写」。 | proven（代码） |

### 2.3 中继侧其余核查结论

- **挑战下发已是最优**：DO 的 fetch 对 Upgrade 请求直入 handleConnect，acceptWebSocket 后立即 send(challenge)，其间零存储读——挑战与 101 同程，无多余往返。proven。
- **DO 唤醒**：房间 DO 以 idFromName(pairingId) 寻址，休眠/驱逐后首个请求（即升级请求）触发重实例化，成本计入升级 RTT；DO 构造器无存储预读（constructor 只建内存态），唤醒后第一笔存储读在 challenge_response 的 record()。唤醒量级本机不可测，inferred 约 100–1000ms（Cloudflare DO 冷启经验值），列入不可省账并给量测法（第五节）。
- **等设备窗（4s）与本症状无关**：该窗只作用于 MCP 客户端调用在无设备 socket 时的等待，不参与 App 建连路径，不拉长 App 侧任何状态；反而在客户端侧掩盖续连间隙。已核查、排除。proven。

## 三、成本账（已配对冷启续连，现行全量握手）

以大陆→Cloudflare 海外边缘 RTT 155–244ms（既有实测口径）为基，逐环节：

| 环节 | 成本 | 可省性 |
|---|---|---|
| App 内触发（Library init → async 派发 start → connectNow） | ~0–50ms | 已近最早点；async 一跳可改为启动链同步首帧后触发，收益小，列可选 |
| DNS + TCP + TLS | 2–3 RTT ≈ 310–730ms | **平台/网络给定，不可省**（TLS 会话复用由 URLSession 系统层管理） |
| WSS 升级（含 DO 唤醒） | 1 RTT ≈ 155–244ms（+唤醒 100–1000ms，inferred） | 往返本身不可省；唤醒为平台成本 |
| 挑战下发 | 0（随 101 同程） | 已最优 |
| 挑战应答往返 | 1 RTT ≈ 155–244ms | **可省**：会话恢复令牌随升级请求呈递，welcome 作升级后首帧下发，整段消除 |
| 中继验签 + record 读 + saveRecord 写 + setAlarm（welcome 前串行） | 约 20–100ms（存储 get+put 为主，ECDSA 验签 ~ms 级） | **大部可省**：恢复路径只读一次 record 验令牌哈希；epoch 持久化移出 welcome 前关键路径（先发 welcome，后落盘/或仅 attachment 记） |
| App 侧 ECDSA 签名 | ~1–10ms | 随恢复路径一并消除（回退时才走） |
| scopes 回写 Keychain | ~ms 级 ×每连 | 可省为「变化才写」 |
| **合计（典型）** | **约 0.8–1.6s**；DO 冷唤醒/弱网坏 case 2–3s+ | 恢复路径后典型约 **0.5–1.2s**，且状态序列只剩单段 connecting |

温启（新层）：现行 = 探活盲窗 5s + 退避 1–2s + 全量握手 0.8–1.6s ≈ **7–9s**；根治后 = 探活判定 ≤2s（或 pong/错误事件提前结案）+ 退避首档 + 恢复路径握手 ≈ **2.5–4s**，其中退避首档对「socket 刚死」场景可再议（见落码 L2 注）。

不可省项交代：TCP/TLS/升级的 3–4 个 RTT 与 DO 唤醒是网络与平台事实，本批不动、也不用呈现层手段遮盖；其量级随用户网络环境浮动，以 Diag 实测为准（第五节）。

## 四、落码清单（组版门后执行；文件领地与组版/权限批逐 hunk 避让）

**中继（bridge/relay/worker.js，部署走既有 deploy.py + 逐字节复核）：**

- **R1 会话恢复协议**：welcome（全量与恢复两路）下发 `resumeToken`（32B 随机、明文仅此一帧）+ `resumeExpMs`（30 天滑动）；record 只存其 sha256 哈希。新增控制帧 `resume`（连接后首帧，含 pairingId + token）：校验 = 1 次 record 读 + 哈希常时比对，命中即置 authed、epoch+1、轮换新令牌、回 welcome；epoch/lastSeenAt 的 saveRecord 移到 welcome 之后不阻塞（或仅更新 attachment，落盘合并到下一次既有写点）。未命中/过期/已吊销 → 回 `challenge` 走现行全量路径（App 无感回退）。吊销（revoke）与配对重置时同步清令牌哈希。
  - 安全口径：令牌与设备私钥同存 Keychain（AfterFirstUnlockThisDeviceOnly）；中继只存哈希；每次恢复即轮换，旧令牌立即失效；强度模型与现行 MCP 客户端 bearer secret 同级（pairingId 本身仍非凭据，令牌为唯一新增凭据面，256-bit 熵）。全量挑战路径永久保留为回退与高敏操作面。
- **R2 ping/presence 去存储往返**：删 ping 与 presence 段的 record get + saveRecord put（新鲜度已由逐 socket attachment 承担，稳定性批口径）；pong 立即回。rec.lastSeenAt 若仍有消费方（bridge_status 展示），改由认证/alarm 路径低频更新，逐个点名后再删，不留悬空读方。

**App（MomentBridge.swift / MomentBridgeTransport.swift）：**

- **A1 令牌客户端**：Keychain 增 `resumeToken` / `resumeExpMs` 两项（BridgeIdentity 内，与 pairingId 同级）；transport.connect 后（resume() 之后立即可 send，URLSession 排队至连接建立）由协调器首帧发 `resume`；收 `challenge` 则走现行签名应答（回退）；welcome 时落盘新令牌。连接触发点维持 start() 现行位置（已近最早），仅把 start 的 async 派发改为启动链既有同步点后直调（若与 0.9.43 init 纪律冲突则保留 async——落码时以 init 链实读定案，不为 ~10ms 冒险）。
- **A2 探活修正（新层 B2/B3）**：① probeLiveness 入口加 `linkState == "connected"` 门——connecting 在飞连接不归探活管（其自身有 15s 请求超时与 socket-down 路径）；② 判定改事件提前结案：pong 到达（lastPongAt 推进）即取消待判 work 并记 probe ok；③ 判定窗 5s → 2s（弱网误判代价仅一次无害重连，口径与稳定性批报告一致）。改后温启死亡发现 ≤2s。
- **A3 welcome scopes 变化才写**：`if granted != identity.scopes` 才 kcSet。
- **A4（可选、落码时裁）**：温启 socket 已死且由 willEnterForeground/didBecomeActive 明确触发的重连，退避首档可由 forceReconnect 路径直连（跳过 1s 首档）——用户在场等待与后台退避的语义不同；与稳定性批「退避重置」口径不冲突（那条管计数清零）。是否采纳在落码报告中以 Diag 量测（重连首档命中频次）定。

**verify**：归属组 [16] 增补——恢复帧/令牌落盘与轮换锚、challenge 回退路径在位、ping 段存储调用零残留（worker.js 静态查）、探活 connected 门与窗值锚、scopes 条件写锚。

**Diag**：既有行足够量测（connect reason / state 跃迁 / session up 均带时戳）；恢复路径新增一行 `BRIDGE resume ok|fallback` 以区分两路命中。

## 五、真机终判与量测法（装机后，桥侧自办为主）

量测（Diag 时戳账，diag_tail 搜 `BRIDGE`）：
- 冷启耗时 = `LAUNCH`（或进程首行）→ 首条 `BRIDGE session up` 之差；状态序列应只有 `off->connecting->connected` 一段中间态。目标：Wi-Fi 典型 ≤1s（恢复路径命中时）。
- 温启耗时 = `BRIDGE presence state=foreground` → 其后 `session up`（或 `probe ok`）之差；死 socket 场景目标 ≤4s，且 `resume ok` 占绝大多数、fallback 仅见于令牌过期/吊销后首连。
- 旧病签名复查：connect 高频循环、probe fail 伴随 state=connecting（A2 后应绝迹）。

用户终判点（只需一眼）：进入 App 后立刻打开设置——MCP 桥行 meta 应已是「已连接」或在约一秒内落定，全程不应再看到「重连中」长时间停留；桥设置页状态文案同口径。**注意**：状态显示仍如实反映状态机，若实测耗时未达标，按 Diag 账追机制，不回头做呈现层处理（用户裁定）。

## 六、结论分层小结

- 必然成本（不可省）：TCP/TLS/升级 3–4 RTT + DO 唤醒，典型 0.5–1.2s——此量级下 connecting 中间态必然短暂存在，属协议事实，已如实入账交裁。
- 可见性缺陷（呈现层）：**无**——呈现如实，问题不在呈现（迟滞方案已按用户裁定作废，不采用）。
- 真多余环节（可省，已点名）：全量挑战往返一段 RTT + 验签/落盘串行（→R1 恢复令牌）、ping/presence 每帧存储读写（→R2）、scopes 每连回写（→A3）、探活 5s 盲窗与冷启误杀（→A2）。四项落码后，冷启续连典型耗时预计压缩约 30–45%，温启从约 7–9s 压到约 2.5–4s，且两路状态序列都只剩至多一段短 connecting。
