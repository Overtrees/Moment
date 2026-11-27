# 桥配对状态根治：中继已 paired、App 仍显示未配对

2026-11-27。用户实报：中继侧配对确认成功、客户端密钥已发、Muse 侧连接器注册成功（list-tools 可达），但 App 设置页仍显示未配对，工具调用回 `app_offline`。本报告为定因与根治记录。

## 一、事实链（实测基线）

- 中继 pair 全链主线已实测通：start → pending、confirm → 发钥、status → paired（路由前缀坑 efe5e5e 修复后）。
- Muse 侧连接器凭据有效（list-tools 返回清单），调用工具回 `app_offline`（中继无设备活连接）。
- App 设置页显示未配对（设置页数据源 = `bridge.isPaired`，即 Keychain 中 `pairingId` 是否存在 + `linkState` 状态机字符串）。

## 二、定因（逐环查实，证据分级）

### 无断点的一环（proven）

中继 ↔ App 口径对齐：中继 `pairStatus` 回 `{state, expiresAt[, scopes, pairedAt]}`，state 枚举 pending / expired / paired / revoked / unknown(404)；App 轮询解析 `state`、`scopes` 字段逐字一致；指纹算式两侧同源（sha256(公钥) 前 16 hex 大写四位分组），且 `pairStart` 在中继侧强制校验、实测通过。此环无问题。

### 断点 1：待配对会话只存内存（proven）

旧 `BridgeCoordinator.pendingPairing` 是纯内存 `@Published` 变量，`beginPairing` 铸出的 pid 从不落盘。而配对流程按设计大部分时间用户在 App 之外：点「打开配对页」→ Safari 打开配对页（App 切后台）→ 核对指纹、勾选、确认 → 去 Muse 录入一次性密钥 → 再回 App。期间 App 被系统挂起，时间长了可被杀死。进程一死，会话无迹可寻；冷启 `start()` 只读 `identity.pairingId`（仅配对收官时才写），无任何恢复路径。

### 断点 2：收敛只靠前台轮询单点（proven）

把中继 paired 事实搬进本地的唯一路径是 `startPairingPoll` 的 2.5 秒定时器，且仅在 `beginPairing` 的 pair/start 成功回调里启动。其余时点全部不校准：

- 设置页 `onAppear` 只记一行 `SET bridge enter` 日志；
- `willEnterForeground` 处理里只有 `isPaired` 已为真时才 `connectNow`，未配对时什么都不做；
- `start()` 不恢复、不查询待配对会话。

即收敛被押在「用户离开 App 完成确认的那段时间里，App 还活着且轮询还在跑」这一根独苗上，与断点 1 叠加即必败。

### 断点 3：本地过期先于中继事实，误杀已成配对（proven）

旧轮询 tick 的第一件事是判本地时钟：`epochMs() > p.expiresAtMs` 即清会话、置未配对，**连中继都不问**。而中继侧 record 一旦被 confirm 即恒为 paired（`pairStatus` 对 paired 不设过期；对 pending 的过期也是在 status 读取时才翻转并回 expired）。所以哪怕 App 在第 11 分钟回前台、轮询复活，第一 tick 也会先按本地时钟把一桩已成功的配对扔掉。此后设置页显示未配对，且再无任何机制能把它找回来。

### 断点 4：beginPairing 无条件新铸 pid（proven）

旧 `beginPairing` 每次调用都 `UUID().uuidString` 新铸 pid：不复用未过期的 pending 会话，对已 paired 状态也不设防（仅靠设置页视图层的分支挡着）。用户看到「未配对」再点一次开始配对，即把中继里已 paired、且客户端密钥已注册到 Muse 的旧 pid 彻底孤儿化——新 pid 在中继只是 pending，旧 pid 的密钥永远等不到设备上线。与实测事实严丝合缝。

### 断点 5：WSS 未连与未配对同源（proven）

`connectNow` 的入口条件是 `identity.pairingId != nil`，该值仅由轮询路径里的 `finishPairing` 写入。断点 1–3 任一命中，pairingId 永不落 Keychain → WSS 永不拉起 → 中继侧恒无设备连接 → 工具调用恒 `app_offline`。两个症状是同一个断点的两面，不是两个 bug。

### 归因小结

断点在链的 **App 侧配对状态收敛环**：中继事实（paired 记录 + 已发密钥）完好，App 侧既没有把待配对身份持久化，也没有在轮询窗口之外的任何时点向中继校准，还叠加了本地过期抢判与开始动作换身份两个放大器。

## 三、根治落码

文件：`rust/apps/ios/app/MomentBridge.swift`、`MomentBridgeSettings.swift`（仅动桥文件与设置页桥段；用户可见配对步骤不变）。

1. **待配对会话落 Keychain**（与 pairingId 同级凭据面，守 B16-2 口径）：`BridgeIdentity` 新增 `pendingPairingId` / `pendingExpiresAtMs` 存取与 `clearPendingPairing()`；`clearPairing()` 一并清 pending。协调器加 `persistPending` / `restorePendingIfNeeded` / `dropPending` 三件套（内存 + 落盘 + 轮询三处同清同写）。
2. **beginPairing 收敛式**：
   - 已 paired → `connectNow(reason: "begin_guard")` 直接返回，绝不铸新 id；
   - 已有待配对会话（内存或落盘恢复）→ 复用同一 pid：未过期续轮询、已过期先校准定夺（`begin_recheck`）；
   - 都没有才铸新 pid，且先落盘再 POST /pair/start。
3. **状态校准单点 `revalidatePairing()`**：未配对且有待配对会话时向中继查一次并按事实收敛（paired → 收官；expired/revoked/unknown → 清会话；pending → 恢复轮询）。调用时点：`start()` 收尾（冷启恢复落盘会话）、`setEnabled(true)`、`willEnterForeground`、设置页 `onAppear`、beginPairing 复用分支。
4. **轮询改序**：轮询 tick 与校准共用 `queryPairingStatus` —— 先问中继、按中继 state 处置；本地过期只保留为「中继无答复且本地已过期」的停轮询兜底，且该兜底不清落盘记录（留待下次校准定夺），不凭本地时钟单独判死。
5. **收官同源同点**：`finishPairing` 保持唯一落盘点 —— 同点清 pending（内存 + 落盘）、写 `identity.pairingId` 与 scopes、拉起 `connectNow(reason: "paired")`。WSS 拉起与配对落盘同源于此，无第二路径。
6. 打点：校准入口记 `BRIDGE revalidate` 行，收敛结果由既有 state/paired/expired 行承接。

## 四、断言（verify [16] 组内新增，本机自跑全绿）

- **B16-8** 待配对会话落盘 + 身份不轮换守卫：`pendingPairingId` Keychain 落点、`persistPending(session)` 落盘调用、`begin_guard` 已配对守卫、`begin_resume` 复用分支、`dropPending`/`clearPendingPairing` 在位。
- **B16-9** 校准时点 + 先问中继 + 同点落盘：`revalidatePairing` 定义在位、设置页接线、`revalidatePairing()` 调用行 ≥4（启动/开关/回前台/开始配对各点 + 定义行）；`queryPairingStatus` 函数段内 `pair/status` 查询行号必须小于 `BRIDGE pairing_expired` 行号（本地过期不得抢先）；`finishPairing` 的 pairingId 落盘与 `connectNow(reason: "paired")` 在位。

本机全量 verify：170 项 ✓，仅剩既有两红（ipa 陈旧、产物语言包——本机无新构建产物，tree 构建后自解，与本批无关）。两改动文件 swift-frontend -parse 零错误；类型级检查随下一版 tree 冒烟。

## 五、用户侧恢复口径（本版出包后）

装新版后无需重新配对操作：冷启即恢复落盘的待配对会话并向中继校准——若中继记录仍 paired，设置页自动转为已配对并拉起连接（前提是当时铸 pid 的那轮会话有落盘；本修复出包前的旧版本从未落盘 pending，故对修复前已确认的那一桩，中继 paired 的 pid 在 App 侧无记录可恢复，仍需在新版里重新开始一次配对——新版开始动作先校准的口径下，这次配对的确认无论耗时多久、App 是否被杀，回来都能收敛）。
