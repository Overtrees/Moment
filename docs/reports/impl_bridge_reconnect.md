# 桥续连根治落码：会话恢复令牌 + ping 去存储 + 探活三修正（2026-11-27）

> 状态：**落码完成**——App 侧未提交、未 bump（随下一组版，基线 HEAD 6ce6cd8）；**中继已部署生效**（对现行装机版亦生效的部分见第三节）。依据 fix_bridge_reconnect_flow.md 根治清单 + fix_bridge_stability.md 已落形态。用户裁定（2026-11-27 16:57）执行口径：状态显示保持如实、不做呈现层迟滞；根治只走机制压成本，验收以 Diag 时戳为准。
>
> **配对二维码批门②放行点**：本批即二维码批的第二道门。本报告落盘 + 工作树含本批全部改动（MomentBridge.swift / bridge/relay/worker.js / verify_ios.sh B16-20）即为落定点；组版提交时以包含上述文件的提交为准。R1 对配对面的影响为零：resumeToken 是**已配对之后**的会话材料，不进配对载荷（pairingURL/pair-start/pair-confirm 形态全未动），二维码批按其既定设计（impl_pairing_qr.md，载荷 = pairingURL 逐字、resumeToken 红线排除）可直接照单落码，无需重做设计。

---

## 一、逐项落码

### R1 会话恢复令牌（中继 worker.js + App MomentBridge.swift）

**中继**
- 新增常数 `RESUME_TTL_MS`（30 天滑动）；record 新增 `resumeTokenHash` / `resumeExpMs` 两字段（pairStart 建档即带空值）。
- `issueResumeToken(rec)`：32B 随机 → base64url 明文仅经 welcome 一帧下发；record 只落 sha256 哈希与到期时刻。`hashEqualHex` 等长常时比对校验。
- 认证收口抽为共用 `completeAuth(ws, att, rec)`（挑战应答与恢复两路同走）：顶替旧连接（4002 + failPendingFor）→ epoch+1 → 轮换令牌 → 置 att → **先发 welcome**（带 `resumeToken`/`resumeExpMs`/`scopes`）→ **后落盘 saveRecord** → ensureAlarm。epoch/令牌哈希的持久化整体移出 welcome 关键路径。
- 新增控制帧 `resume`（连接后首帧，含 `token`）：校验 = **1 次 record 读** + 状态 paired + pairingId 一致 + 哈希常时比对 + 未过期；命中 → completeAuth；未命中/过期/已吊销 → 回 `resume_rejected`。已 authed 的 socket 重发 resume 直接忽略。
- 吊销（revoke）同步清 `resumeTokenHash`/`resumeExpMs` 后落盘；pairStart 重建档天然清零。

**App**
- `BridgeIdentity` 新增 `resumeToken` / `resumeExpMs` 两 Keychain 项（与 pairingId 同 service、kcSet 统一的 AfterFirstUnlockThisDeviceOnly 口径）；`clearPairing()` 同步 `clearResumeToken()`——吊销（本地 disconnectAndRevoke 与中继 revoke-notice 两路都经 clearPairing）本地副本一并清零。
- `connectNow`：建连后、本地令牌未过期时首帧发 `resume`（URLSession 于连接建立前排队，帧序不乱），置 `resumeInFlight`；无令牌/已过期不发，照旧走挑战。
- challenge 持留协议：`resumeInFlight` 期间到达的 challenge 只存 `heldChallengeNonce` 不作答——中继裁决在同一 socket 有序到达：命中回 welcome（持留 challenge 自然作废）；未命中回 `resume_rejected` → 记 `BRIDGE resume fallback` 并以 `answerChallenge(nonce:)` 补答持留 challenge（应答逻辑抽为单点，直答/补答共用）。回退不白付任何额外往返。
- welcome 处理（两路）：落盘新令牌（`resumeExpMs` 按 NSNumber 读取）；本连接走恢复路时记 `BRIDGE resume ok`。

### R2 ping/presence 整删存储读写（中继）

- ping 段：删 record get + saveRecord put，pong 立即回。
- presence 等其余控制帧：删 record get + saveRecord put，只作在线信号。
- 删前逐个点名读方（通读全仓实证）：`rec.lastSeenAt` **无任何读方**——选连与 alarm 僵尸判定均读逐 socket attachment（稳定性批口径），pairStatus/mcp 回读面不暴露该字段。故其更新收敛到 completeAuth 一处低频写（认证时），字段本身保留为元数据。逐 socket att 刷新段（webSocketMessage 入口，≥5s 节流）原样不动，新鲜度语义零变化。

### A2 探活三修正（App，针对稳定性批新层的三笔账）

1. **connected 门**：`probeLiveness` 入口加 `linkState == "connected"`——connecting 在飞连接不归探活管（其自身有 15s 请求超时与 socket-down 路径）；冷启 didBecomeActive 误杀健康首连的路径就此关闭。
2. **pong 即结案**：探活基线存 `probePongBaseline`；pong 到达（handleControl "pong"）即调 `finishProbeIfSatisfied()`——基线后 lastPongAt 有推进即取消待判 work 并记 `BRIDGE probe ok`（心跳 pong 同算活证）。判定不再等满窗。
3. **判定窗 5s → 2s**：2s 无 pong 推进才记 `BRIDGE probe fail` 并 forceReconnect(probe_timeout)。温启死亡发现由 ~5s+ 压到 ≤2s。

### A3 scopes 变化才写（App）

welcome 处理改 `if granted != identity.scopes { identity.scopes = granted }`，每连必走的 SecItemDelete+Add 在值不变时整段跳过。

### A4 未采纳（按报告自身条件裁定）

报告口径为「是否采纳以 Diag 量测（重连首档命中频次）定」。0.9.57 尚未装机，稳定性批 + 本批的 Diag 新行（connect reason 分布、reconnect_scheduled）还没有真机数据可量——无量测不落码，本批不采纳「温启直连跳首档」。待装机后按 Diag 账复议，账面影响上限即退避首档 ~1–2s。

### 未动项（与报告一致）

- `start()` 的 async 派发点维持现行（启动链 init 纪律优先，不为 ~10ms 改触发点）。
- 挑战下发路径、中继等设备窗、选连/pending/alarm 等稳定性批形态：零改动（harness 复跑见第三节）。

---

## 二、断言（verify [16] 新增 B16-20）

B16-20 单条聚合本批全部机制锚：App 侧（kcGet("resumeToken") / clearResumeToken / resume 首帧字面 / resumeInFlight / heldChallengeNonce / answerChallenge 单点 / `BRIDGE resume ok` / `BRIDGE resume fallback` / scopes 条件写 / finishProbeIfSatisfied / probeLiveness 函数段内 connected 门与 `.now() + 2`）+ 中继侧（RESUME_TTL_MS / resumeTokenHash / hashEqualHex / completeAuth / resume 帧处理 / resume_rejected）+ R2 静态查（ping 段与 presence 段抽段后 `this.record()`/`saveRecord` 零命中）。本机 [16] 组全绿（B16-1…B16-20）；全量 verify 仅剩产物类 3 条既有 ✗（ipa 陈旧、产物语言包、五语键数期望——归加键的并发批与 tree 构建，本批零涉）。

## 三、实证记录

- **中继 harness（本机 Node 24，真实 BridgeRoom + 假 DO state/socket + 真实 ECDSA P-256 配对）十景全过**：
  - 稳定性五景复跑：S1 顶替关旧（4002）+ 选连取新；S2 无关 socket error 不冲在飞 pending、本连接 error 立即结清；S3 僵尸选连排除 + ping 刷新复活 + 调用完成；S4 无设备等满 4s（回 app_offline）；S5 alarm 关僵尸（stale_socket/auth_timeout）。
  - 新增 resume 五景：R1 全量 welcome 下发令牌、中继只存哈希（明文不落盘断言）、命中直达 welcome、**命中路径 record 只读恰 1 次**、轮换新旧不等、旧令牌重放被拒、被拒后 challenge 回退仍达 welcome；R2 垃圾令牌被拒 + 回退成功；R3 过期令牌被拒；R4 吊销后哈希清零 + resume 被拒；R5 ping 回 pong 且 record 读/写计数为零、presence 同为零。
- **部署对账**：deploy.py 部署 200；经 API 下载线上脚本与仓库 worker.js **逐字节一致**（50,713 B，sha256 905301bc…）；线上 list-tools 回 **31 件**、manifestHash 重算 = `a52116c3…`，与部署前基线一致、**工具面零漂移**。
- **App 侧编译**：本机无 swiftc（既定分工），编译级自检随下一组版的 tree 全量冒烟把关；改动已逐行自审（持留/补答状态机、NSNumber 读取、探活基线三处为新增代码，其余为等值重构）。
- **在途纪律**：动工前全树 diff 快照（1943 行）；完工复验——他人文件 diff 内容行零丢失（verify_ios.sh 的差异仅 diff hunk 偏移元数据，本批只在 [16] 段内尾插 B16-20）；本批只动 MomentBridge.swift、worker.js、verify_ios.sh 三文件。

**已生效范围**：中继侧 R1/R2 已线上生效，但 App 侧令牌客户端随下一组版装机后才有恢复流量；在那之前现行 App 继续走全量挑战（中继对其完全兼容，welcome 多带的令牌字段被旧版忽略）。R2 的 pong 提速对现行装机版立即生效。

## 四、耗时验收口径（装机后，Diag 时戳账）

量测法（diag_tail / diag_search 搜 `BRIDGE`）：

- **冷启**：`LAUNCH`（或进程首行）→ 首条 `BRIDGE session up` 之差；状态序列应只有一段 connecting。恢复命中时目标 **0.5–1.2s**（Wi-Fi 典型 ≤1s），且该次 session up 前应有一条 `BRIDGE resume ok`。
- **温启**：`BRIDGE presence state=foreground` → 其后 `session up` 或 `probe ok` 之差。socket 尚活 = probe ok 即结案（≈1 个 RTT）；socket 已死 = 探活 ≤2s 判死 + 退避首档 + 恢复握手，目标 **2.5–4s**。
- **命中比**：`BRIDGE resume ok` 应占绝大多数续连；`BRIDGE resume fallback` 只应见于令牌过期（30 天未用）/吊销后首连/中继记录重置。fallback 频发即新回归证据。
- **旧病签名复查**：`BRIDGE probe fail state=connecting` 应绝迹（connected 门）；connect 高频循环伴 session up 缺失（代次竞态旧签名）不应复现。

**地板账（如实登记，不遮盖）**：TCP+TLS+WSS 升级 3–4 个 RTT（大陆→海外边缘 155–244ms/RTT）+ DO 冷唤醒（inferred 100–1000ms）为网络与平台事实，本批不动、也不用呈现层手段掩盖——此量级下单段短暂的 connecting 必然存在，属协议事实。恢复路相对全量路的节省 = 挑战往返 1 RTT + 验签/record 读写串行（约 20–100ms）+ App 侧签名，冷启典型压缩约 30–45%。

## 五、真机终判点

1. **一眼判读**：进入 App 后立刻打开设置——MCP 桥行 meta 应已是「已连接」或约一秒内落定；温启回前台不应再见「重连中」长时间停留（状态显示仍如实，耗时不达标按 Diag 账追机制，不回头做呈现处理——用户裁定）。
2. **长挂起后回前台**：App 挂起数小时后打开，桥应在数秒内恢复已连接（Diag 应见 probe fail→connect→resume ok→session up 链，或 probe ok 直接结案）。
3. **吊销收口**：App 内断开并吊销后，旧令牌不可恢复（中继侧哈希已清）；重新配对后首连走全量挑战（Diag 见 fallback 或无 resume 行），第二连起恢复命中。
