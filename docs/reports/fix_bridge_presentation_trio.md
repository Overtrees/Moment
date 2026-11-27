# 桥呈现小批三项根治——只读准备与设计（停门待放行）

> 状态：**落码完成**（2026-11-27，主线已批准 §2.4 行为变更；基线 HEAD cb8ff18、开工树净；未提交、未 bump，随下一组版）。落码对账见文末「落码节」。
> 出处：docs/reports/audit_home_other_deep.md §5.9(b)/§5.10/§5.11（下称审计），与 impl_bridge_m3a.md 呈现面、impl_bridge_live_keepalive.md 同源口径对账后成文。

## 0. 出处对账（范围切分）

审计「桥呈现小批」原表含五项，本批只承接其中三项，其余两项已有归属、不重复立项：

| 审计项 | 归属 |
|---|---|
| §5.5(a) 布防 reason 上屏 | 救援布防批（0.9.57 已落，RescueView 状态区附读审计 reason） |
| §5.9(c) 待配对过期呈现 | 配对二维码批（0.9.58 已落 `bridge.pair_expires` 有效期行） |
| **§5.9(b) 吊销回执不可见** | **本批 ①** |
| **§5.10 scopes 空集/未授呈现** | **本批 ②**（(a) 空集兜底与 (b) 未授负向呈现同一派生点，一并设计） |
| **§5.11 backoff reason 上屏** | **本批 ③** |

守恒前提（审计 §5.11 已证、本批不触）：状态呈现双面同源、零迟滞零缓存（主页桥行 meta 与桥设置页状态文案均直读 `Lang.t(bridge.linkStateKey)`）；呈现如实口径不许粉饰——本批三项全部只做「把已有的事实送上屏」，不新造任何状态推断。

## 1. ① 吊销回执不可见

### 现状根点（proven，源码）

- `BridgeCoordinator.disconnectAndRevoke()`（MomentBridge.swift）：中继吊销 POST 的 dataTask completion 是 `{ _, _, _ in }`——响应与错误**整段丢弃**；成功/失败/无网络在 App 侧不可区分。
- Diag 只有一行 `BRIDGE revoked via=app`（本地清除动作行），中继侧结果零留痕。
- 呈现：动作后 `isPaired` 转假，设置页落回未配对分支、只显通用 `bridge.unpaired_note`——用户无从知道中继房间是否已吊销（房间残留只在日后错房三联征时以 app_offline 显形，审计 §5.9(b)）。
- 中继契约现成（bridge/relay/worker.js）：`/pair/revoke` 转房间 DO `/revoke`，设备签名验过后置 `rec.state="revoked"`、回 **HTTP 200 + `{state:"revoked"}`**；签名不符/请求残缺回非 200。**「中继确认」有明确可判口径，本批不需动中继。**

### 根治设计（回执状态挂协调器单点，呈现只读派生）

1. **状态源**：协调器新增 `@Published private(set) var revokeOutcome`（枚举 `pending / confirmed / unconfirmed`，进程内状态、**不落盘**——语义是「本次吊销动作的回执」，重启后不陈列旧回执）。写点单点 = `disconnectAndRevoke()` 的吊销收口段，别处零写。
2. **判定收口**：吊销 dataTask completion 改为捕获 `(data, response, error)` 并回主队列（沿本文件 `httpJSON` 的回主队列式）：
   - 发起前：有 pairingId 且签名成功 → 置 `pending` 后发请求；无 pairingId 或签名失败（无请求可发）→ 直接置 `unconfirmed`，Diag 记 `relay=skipped`（见下）。
   - 回执判定：HTTP 200 且 body `state == "revoked"` → `confirmed`；其余（非 200 / 传输错误 / body 不符）→ `unconfirmed`。
3. **Diag 分行**（旧行保留，verify B16-4 的 `BRIDGE revoked via=` 锁不破）：
   - `BRIDGE revoked via=app`（本地清除，现状不变）
   - `BRIDGE revoke relay=confirmed status=200`
   - `BRIDGE revoke relay=unconfirmed status=<码|0>`
   - `BRIDGE revoke relay=skipped reason=no_pid|sign_failed`
4. **呈现**：未配对分支在 `bridge.unpaired_note` 上方加一行回执文案（`revokeOutcome != nil` 才显）：pending → `bridge.revoke_pending`（次级色）；confirmed → `bridge.revoke_confirmed`（次级色）；unconfirmed → `bridge.revoke_unconfirmed`（`T.warning` 色——如实示警，不粉饰为已断开干净）。回执**不随设置页关闭清除**（现行 onDisappear 只复位 confirmRevoke 的行为不变），清除点单点化：`beginPairing()` 起新一轮时与 `finishPairing()` 成功时置 nil。
5. **安全姿态零改动**：本地先行清除的顺序与时机不变（签名在删设备钥之前算、本地清除不等回执）；回执纯属事后可见性，不引入任何等待或重试。

## 2. ② scopes 空集误显「只读」

### 现状根点（proven，源码）

- 呈现兜底在 MomentBridgeSettings.swift 已配对分支：`bridge.scopes.isEmpty ? Lang.t("bridge.scope_read") : 拼接已授名`——空集被断言成「只读」。
- 空集的真实语义是「无授权信息」：协调器 `scopes` 初值 `[]`（start 时由 Keychain 载入，空串即 `[]`）；welcome 仅在回带 `scopes` 字段时覆盖（MomentBridge.swift welcome 分支）；`finishPairing` 的入参来自轮询 status，status 缺 `scopes` 字段时现行兜底 `?? ["read"]`（pollPairing paired 分支）——**契约兜底在源头虚构 read 授权**，与呈现兜底叠加后真值更不可辨（审计 §5.10(a)）。
- 未授项无负向呈现（审计 §5.10(b)）：已配对分支只列已授名，用户在 App 内无法区分「未授 write」与「无此能力」，与错房排查（BRG-02）的判读需求相悖。
- 规范 scope 集现行无单点定义：`read/write/ops` 三名散见于分发器 `contains` 检查（MomentBridgeTools.swift）与五语键 `bridge.scope_<name>`。

### 根治设计（规范集单点 + 协调器派生，呈现层零推断）

1. **规范集单点**：MomentBridge.swift 协调器处新增 `static let scopeUniverse = ["read", "write", "ops"]`（顺序即呈现顺序；与分发器能力门的检查名集同名同集，注释互指）。
2. **派生单点**：协调器计算属性 `ungrantedScopes: [String]` = `scopeUniverse` 中不在 `scopes` 内的项。设置页只渲染派生结果，不在 View 内做集合运算。
3. **呈现规则（如实语义，空集 ≠ 全未授）**：
   - `scopes.isEmpty` → 值行显新键 `bridge.scopes_none`（「未回带授权」），且**不显未授行**——空集是未知态，把三项全列为「未授权」是另一种虚构。
   - `scopes` 非空 → 已授名拼接（现行式不变）；`ungrantedScopes` 非空时其下加一行 caption 次级文案：`Lang.tf("bridge.scopes_ungranted", ["names": 未授本地化名拼接])`（如「未授权：功能写 · 运维」）。
4. **源头兜底改判（行为变更点，放行时请过目）**：pollPairing paired 分支 `obj?["scopes"] as? [String] ?? ["read"]` 改为 `?? []`——status 缺字段时不再虚构 read，落入空集如实呈现；连接建立后 welcome 以中继实授覆盖（现行路径不变）。分发器能力门以 `contains` 判定，`[]` 天然全闭（fail-closed），比虚构 read 更安全；影响面仅限「status 已报 paired 却缺 scopes 字段」的中继异常回带，正常配对回带恒含 scopes（中继 pair-status 现行实现回带 granted scopes，M3a 已验通链路）。

## 3. ③ backoff reason 上屏

### 现状根点（proven，源码）

- 每次状态迁移的 reason 已齐备在写点：`setState(_:reason:)`（MomentBridge.swift）是唯一迁移点，reason 只入 Diag 行 `BRIDGE state <from>-><to> reason=<token>`，**不留存**，呈现层无从取。
- 能落到 backoff 的 reason 全集可枚举：传输层 `onSocketDown` 的 `receive_error / send_error`（MomentBridgeTransport.swift 注释与两处调用钉死）+ 硬重连单点 `forceReconnect` 的 `heartbeat_timeout / probe_timeout`。
- 用户在设置页只见状态词「重连中」，断网与被吊销与无响应不可分辨（revoked/opsDisabled 有专属态、唯 backoff 不带因，审计 §5.11）。

### 根治设计（setState 单点留存 + 映射派生单点）

1. **留存单点**：`setState` 内增写 `@Published private(set) var lastStateReason: String = ""`——每次调用都更新（含同态重复进入 backoff 的新 reason，如首断 receive_error、次断 probe_timeout，呈现恒取最近一次）；Diag 现行行为一字不变。赋值点全文件恒 1（声明初始化除外），断言锁。
2. **映射派生单点**：协调器计算属性 `stateReasonKey: String?`——仅当 `linkState ∈ {backoff, connecting}` 且 reason 非空时映射：`receive_error/send_error → bridge.reason_network`（连接中断）；`heartbeat_timeout/probe_timeout → bridge.reason_timeout`（连接无响应）；其余 token → `bridge.reason_unknown`（连接异常，兜底不露原始 token、不臆测细分）。其余状态（connected/off/unpaired 等）返回 nil——已连接显断开原因才是粉饰性噪音，不显。
3. **呈现落点**：桥设置页 pairingSection 头部状态行（`Lang.t(bridge.linkStateKey)` 行）下加一行 caption 次级文案，`stateReasonKey` 有值才显。主页设置桥行维持只显状态词（紧凑行形态守恒，判读面收敛在桥设置页，与审计提案落点一致）。
4. **与实况保活的同源对账**：`syncBridgeLive()` 的 step 文案仍只取 `Lang.t(linkStateKey)`，**不带 reason**——锁屏是摘要面且实况步文案有 5s 合并节流，reason 的即时判读面是设置页与 Diag；reason 与状态词同出 `setState` 一个写点、同一时刻定格，无第二状态源、无口径分叉。实况批文件（MomentLiveOps*）零改动。

## 4. 五语键账（371 → 379，+8）

语言包 = rust/apps/web/lang/{zh-CN,zh-TW,en-US,ja-JP,ko-KR}.json（五包同构、verify [9] 锁键数）。新增 8 键（zh-CN 文案如下，其余四语同批同流程翻译落键）：

| 键 | zh-CN 文案 | 用途 |
|---|---|---|
| bridge.revoke_pending | 已在本地断开，正在向中继确认吊销… | ① 回执·待确认 |
| bridge.revoke_confirmed | 已断开，中继已确认吊销 | ① 回执·已确认 |
| bridge.revoke_unconfirmed | 已在本地断开，但中继未确认吊销（可能网络未达，中继侧配对可能仍在） | ① 回执·未确认 |
| bridge.scopes_none | 未回带授权 | ② 空集如实值 |
| bridge.scopes_ungranted | 未授权：{names} | ② 未授负向行（Lang.tf） |
| bridge.reason_network | 连接中断 | ③ reason 映射 |
| bridge.reason_timeout | 连接无响应 | ③ reason 映射 |
| bridge.reason_unknown | 连接异常 | ③ reason 映射兜底 |

落码时 verify [9] 键数期望 371 → 379 同步改判（沿「补键须同步改此期望」的既有纪律），五包逐包对账。

## 5. 落码清单（放行后执行，本轮未动）

| 文件 | 改动 |
|---|---|
| MomentBridge.swift | revokeOutcome 状态 + 吊销 completion 收口 + Diag 三分行；scopeUniverse + ungrantedScopes 派生；pollPairing 兜底 `?? ["read"]` → `?? []`；lastStateReason 留存 + stateReasonKey 映射；beginPairing/finishPairing 清回执两点 |
| MomentBridgeSettings.swift | 未配对分支回执行；已配对分支 scopes 呈现改派生（空集 scopes_none / 未授行）；状态行下 reason 次级行 |
| rust/apps/web/lang/*.json ×5 | +8 键/包 |
| verify_ios.sh | [9] 键数改判 379；新组 **[40]** BRP40-1..7（见下） |
| 中继 / 连接器 / MomentLiveOps* | **零改动** |

verify [40] 断言设计（锁机制不锁表象）：
- BRP40-1 回执写点单点：`revokeOutcome` 赋值只在 disconnectAndRevoke 收口段与两清除点；吊销 dataTask 空闭包 `{ _, _, _ in }` 全文件零命中。
- BRP40-2 Diag 三分行齐（relay=confirmed/unconfirmed/skipped）+ 旧行 `BRIDGE revoked via=app` 在位。
- BRP40-3 空集呈现：已配对分支含 `bridge.scopes_none` 渲染点，且旧三元兜底式（`scopes.isEmpty ? Lang.t("bridge.scope_read")`）零残留。
- BRP40-4 规范集与派生：`scopeUniverse` 单点定义、`ungrantedScopes` 派生式在位、`?? ["read"]` 全文件零残留。
- BRP40-5 reason 留存单点：`lastStateReason` 赋值点计数 = 1（setState 内，声明行除外）。
- BRP40-6 映射四路：network 两 token / timeout 两 token / unknown 兜底 / 非 {backoff, connecting} 返 nil 的门在位。
- BRP40-7 五语 8 新键逐包齐 + 键数 379（与 [9] 改判互锁）。

自检口径（放行后）：本机 verify 全量 + MomentBridge/MomentBridgeSettings 两 primary 遍类型检查零错误；正式把关随下一组版 tree 冒烟。

## 6. 真机终判点（装后）

1. **吊销回执**：设置页真吊销一次——回执行先显「正在向中继确认」、数秒内翻「中继已确认吊销」；Diag 见 `revoke relay=confirmed`。飞行模式下再配对再吊销——回执如实显「中继未确认」（warning 色），Diag 见 `relay=unconfirmed`。
2. **scopes 呈现**：全授态已授行三名齐、无未授行；只授 read 的配对下未授行显「功能写 · 运维」。空集态真机难构造（需中继异常回带），以断言 + 代码审为准、不列真机点。
3. **backoff reason**：已连接后开飞行模式——状态翻「重连中」、其下显「连接中断」；关飞行模式恢复「已连接」后 reason 行消失。

---

## 落码节（2026-11-27，基线 HEAD cb8ff18）

按 §5 清单照单施工，三项全部落码，中继 / 连接器 / MomentLiveOps* 零改动。

### 逐项落点

- **① 吊销回执**：`BridgeRevokeOutcome` 枚举（pending/confirmed/unconfirmed）+ 协调器 `@Published private(set) var revokeOutcome`（进程内、不落盘）。`disconnectAndRevoke()` 收口重写：有 pid 且签名成功 → 置 pending 发请求，completion 捕获 `(data, resp, _)` 回主队列判定（200 且 body `state == "revoked"` → confirmed + Diag `BRIDGE revoke relay=confirmed status=200`；其余 → unconfirmed + `BRIDGE revoke relay=unconfirmed status=<码|0>`）；无 pid/签名失败 → 直接 unconfirmed + `BRIDGE revoke relay=skipped reason=no_pid|sign_failed`。旧行 `BRIDGE revoked via=app` 保留。本地先行清除的顺序与时机一字未动（签名在删钥之前算、清除不等回执、无等待无重试）。清除点：`beginPairing()` 首行与 `finishPairing()` 成功段各置 nil。设置页未配对分支在 `bridge.unpaired_note` 上方加回执行（有值才显；pending/confirmed 次级色、unconfirmed 走 `T.warning`），文案键映射 helper `revokeOutcomeKey` 在 View 内。
- **② scopes 呈现**：协调器 `static let scopeUniverse = ["read", "write", "ops"]` 单点 + `ungrantedScopes` 派生（呈现顺序即规范集序）。设置页已配对分支：空集显 `bridge.scopes_none` 且不显未授行；非空显已授名拼接 + 未授 caption 行（`Lang.tf("bridge.scopes_ungranted", names=未授本地化名拼接)`）。**源头兜底改判已照批准落码**：queryPairingStatus paired 分支 `?? ["read"]` → `?? []`（fail-closed），全文件 `?? ["read"]` 零残留（BRP40-4 锁）。
- **③ backoff reason**：`setState` 内单点留存 `@Published private(set) var lastStateReason`（每次调用都更新，Diag 行为不变）+ 派生 `stateReasonKey`（仅 backoff/connecting 且 reason 非空时映射：receive_error/send_error → reason_network；heartbeat_timeout/probe_timeout → reason_timeout；其余 → reason_unknown；他态返 nil）。设置页 pairingSection 头部状态行下加 caption 次级行、有值才显；主页桥行与实况步文案零改动（同源对账守恒）。

### 五语键账对账（合并口径）

- 本批 +8 键/包（§4 表全数：revoke_* 3 + scopes_none/scopes_ungranted 2 + reason_* 3），五包逐包落键、键集合一致。
- **最终键数 = 381/包**。对账链：371（组版基线）+ 1（i18n 收尾批 imgpage.load_failed）+ 1（备份小批 notice.import_reload_failed）+ 8（本批）= 381。verify [9] 期望已由本批在兄弟批 373 的账上续改为 **381**，注释链逐笔在册（i18n 批的 372 改判与备份批的 373 改判均保留、本批续接），无两批各写一数打架。BRP40-7 只锁「8 新键逐包齐 + 五包互等」，绝对总数由 [9] 单点锁——避免并行批次再撞数。
- 注记：[38] B38-6 注释中「恒由 [9] 另锁 371」一语已随键数演进过时（其断言本体只查键在位、不锁数，不受影响），留待该组下次改判时顺手更新，本批未动他人注释。

### verify 组号顺延说明

设计原定新组 [40] BRP40-1..7；落码时 [40] 已被同波备份小批（BK40）占用，本批顺延为 **[41]** 组、断言名 BRP40-1..7 沿设计不变（文件内组序 [40] 备份 → [41] 桥呈现 → [42] SVG 连续无撞）。

### 自检结果

- **verify [41] 组 BRP40-1..7 全绿**（单组抽段实跑）；[9] 组键数 381 ✓、键集合一致 ✓。
- **verify 本机全量**：401 ✓ / 3 ✗。三红定性：ipa 陈旧、产物语言包与 Web 源不一致——既有产物类两红（构建自解，与各批基线同）；**B25-E3-1 一红不在本批领地**：MomentApp.swift:8042 新增第三处 `convertNodeType(b` 调用点（断言期望 2），系同波在 MomentApp 内施工的兄弟批 hunk（本批未触 MomentApp.swift 一行），留主线转该批对账。
- **类型检查**：MomentBridge.swift / MomentBridgeSettings.swift 两 primary 遍（swift-frontend 同旗标全量文件列表）**零 error**。
- **同树复验**：完工 diff 删除行集核对——MomentBridge.swift 删除行仅两行（`?? ["read"]` 旧兜底与 `_, _, _ in` 空闭包，均为设计内退役）；MomentBridgeSettings.swift 删除行仅旧 scopes 三元式；他人在途 hunk（MomentApp/MomentOps/MomentRescue/build-app2.sh 等）完好。落码期间 verify_ios.sh 被兄弟批并发编辑（一度撕裂读致全量跑中断于 [20]），待文件稳定后重跑得上述全量结果，本批 [41] 段未受损。
- 真机终判点沿 §6 三项不变，随下一组版装后判读。
