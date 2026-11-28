# MCP 桥配对去 Safari 跳转、改 App 内确认（fix_bridge_pairing_inapp）

用户 2026-11-28 实报：桥配对页需要跳到 Safari，能不能改为在 App 里。未提交，留主线组 0.9.63；中继改动未部署（见 §二待部署项）。

## 一、定性（proven，回源实证）

**跳转点恰一处**：桥设置页待配对分支的「打开配对页」钮——`MomentBridgeSettings.swift` 经 `@Environment(\.openURL)` 打开 `bridge.pairingURL()`（中继 `/pair?pid=<配对ID>&fp=<指纹>`），https 外链由系统跳 Safari。全仓桥面 grep 仅此一处外跳。

**中继配对页承担的四项功能**（`bridge/relay/worker.js` 的 `pairPage`/`pairDonePage` 与 DO `pairConfirm` 回源）：

1. 展示设备指纹，供机主与 App 显示比对；
2. scopes 勾选：read 必选（禁用勾选框）、write/ops 可选；
3. 确认提交：表单 POST `/pair/confirm` → Worker 转 DO 内部 JSON 单点 `pair-confirm`，校验 state=pending、未过期、回呈指纹与 `pairStart` 记录一致 → 授予 scopes、生成 clientKey 秘密、**中继只存其 SHA-256 哈希**、一次性返回 clientKey；
4. 完成页一次性展示 clientKey，供机主粘贴到 Muse 安全凭据页完成连接器注册。

**App 侧所需**：App 本身不需要 clientKey（设备以自身密钥对接入中继）；配对状态收敛已有完备单点（2.5s `/pair/status` 轮询 + `revalidatePairing` 校准 + `finishPairing`）。故网页四项功能全部可原生化；中继唯一缺口是公开 JSON confirm 通道——原公开 `/pair/confirm` 仅受理表单并回 HTML，DO 内部本就是 JSON 单点。

## 二、选层：层级 2（API 原生化），不用 WebView

确认的全部语义都在 DO 的 JSON 单点上，网页只是其表单外壳，不存在不可原生化的 web 流程，故不引入 SFSafariViewController。

**中继改动（worker.js，最小加法）**：POST `/pair/confirm` 按 Content-Type 分流——`application/json` 走新分支：收 `{pairingId, fingerprint, scopes}`、按 pid 路由到同一 `room/pair-confirm` 转发、JSON 响应（含错误状态码）原样回带；表单通道逐字不变，网页配对页继续可用（二维码的另一设备通道）。`RELAY_VERSION` 1.0.0 → 1.1.0。

**待部署项（主线安排，本批未部署生产中继）**：`bridge/relay` 须经既有 `deploy.py` 部署后 App 内确认才真正可用；判据 = `GET /health` 返回 `version: 1.1.0`。部署前在 App 点确认，旧中继对 JSON POST 回非 JSON/错误 → App 如实呈报 `pair_confirm_failed`，不会假成功、不会误置 paired。

## 三、落码清单

- **MomentBridge.swift（协调器）**：新增 `confirmPairing(scopes:)`——以待配对会话 pid + 本机指纹 + 勾选 scopes 直调 POST `/pair/confirm`（JSON）；成功回带 clientKey 只置进程内 `oneTimeClientKey` 并走 `queryPairingStatus` 既有单点收敛（不自设第二收敛路径）；`expired` 按既有口径 dropPending、`already_paired`（可能经另一设备确认）按中继事实收敛、余失败落 `pairConfirmError` 呈报。新增进程内状态 `oneTimeClientKey` / `pairConfirming` / `pairConfirmError` 与 `dismissClientKey()`；`disconnectAndRevoke` 同步清密钥。
- **MomentBridgeSettings.swift（设置页）**：删 `openURL` 环境与「打开配对页」钮（外跳清零）；待配对分支新增 scopes 三行勾选（read 恒开禁用、write/ops 系统 Toggle、会话更替经 onChange 复位）+「确认配对」钮（确认在途/已过期禁用）+ 在途等待行 + 失败行；配对区后新增客户端密钥卡（标题、等宽密钥本体、一次性说明、复制钮走系统剪贴板、「我已保存」钮）；页头注释按新流程改判。二维码保留（构造点 `pairingURL()` 不变）。
- **i18n 五包（web/lang 真源）**：新增 10 键（`bridge.pair_confirm`、`pair_confirm_failed`、`pair_scope_{read,write,ops}_note`、`key_{title,note,copy,copied,saved}`）；改写 3 键（`pair_hint`、`pair_waiting`、`unpaired_note`——旧文案以「打开配对页」为前提已不实）；退役 `bridge.pair_open`（功能消失、零引用，防僵尸键复发）。键数 429 → 438。
- **verify_ios.sh**：[9] 键数期望 429 → 438（沿革注）；B16-QR-1 设置页 `pairingURL()` 引用计数 2 → 1 改判（沿革注：链接钮退役、二维码单源不变）；新增 B16-PAIRAPP-1..4（外跳清零 / 密钥卫生 / 中继 JSON 通道 / 呈现面齐）。

## 四、安全语义：保留与变化（如实登记）

**逐项保留**：DO 校验单点与全部判据（pending/过期/指纹一致）；scopes 授予规则（read 恒授、write/ops 须显式勾选、DO 侧再钳制）；clientKey 中继只存哈希、只回带一次；两段提交 actionToken、会话恢复令牌轮换（连接面，本批未触碰）；配对收敛五断点与状态轮询单点；scopes 呈现口径（空集不兜底、未授负向行）；Diag 可辨识（新增 `BRIDGE pairing_confirmed scopes=…`、`BRIDGE error code=pair_confirm_failed …`、`BRIDGE client_key_dismissed`，均不含密钥本体）。

**变化点（本批取舍，终判时请主线确认接受面）**：

1. 确认动作的执行面从浏览器移入 App——确认者仍是机主本人的显式点按，授权三道门不变（启用开关 → 开始配对 → 本页勾选后确认），页面不自动完成任何授权；
2. 指纹的人工跨面比对消失，改为 App 回呈自身指纹、由中继强制校验——App 只能确认自己 Keychain 中的待配对 pid，他人 pid 无法经此路确认，钓鱼面反而收窄；
3. clientKey 一次性经过 App 进程内存展示（旧路 App 永不持有）——缓解：仅 `@Published` 内存态，Keychain/UserDefaults/文件零写、Diag 零密钥（B16-PAIRAPP-2 锁），点「我已保存」或吊销即清，进程退出即失；代价是进程存活期间解锁手机 + 打开本页可见密钥卡，与旧路浏览器页签的暴露面同级。

## 五、自检（本机止步，tree 冒烟组版统一）

- `swiftc -parse` 两 Swift 文件过；`node --check worker.js` 过。
- verify_ios.sh 全跑 582 ✓；本批相关全绿：[9] 五语键集合一致 / 键数 438 / Swift 引用键齐全、B16-QR-1..4、B16-PAIRAPP-1..4、桥 35 件契约组（B16-*）无红。余红 4 项均非本批：产物红 2（ipa 陈旧、产物语言包与源不一致——tree 重建归零）+ SB-4/SB-7（状态栏二轮批在途中间态，非本批文件面）。
- `scripts/i18n_deep_check.py`：438 键零僵尸、新键引用面齐（仅既有疑似漏译警告，与本批无关）。
- 残留 grep：代码面 `bridge.pair_open` 引用 0、设置页 `openURL` 0。

## 六、真机终判点

前置：中继部署至 1.1.0（`/health` 判读）后验 1–3；未部署时确认应如实报失败、不假成功（此态本身即一项判读）。

1. **全程不离 App 完成新配对**：开始配对 → 勾选 write/ops → 确认配对 → 密钥卡出现 → 复制 → 粘贴 Muse 安全凭据页 → 连接器连通且实授 scopes 与勾选一致；
2. **只授 read**：不勾选直接确认 → 客户端仅 read，App 已配对分支呈现一致；
3. **密钥卡纪律**：点「我已保存」后卡消失、无任何面可再显示；杀进程重开不出现旧卡；
4. **过期态**：待配对过期后确认钮禁用、`pair_expired` 呈现如旧；
5. **另一设备通道不回归**：扫码在浏览器打开配对页确认 → App 经轮询收敛 paired；
6. **失败如实**：断网点确认 → 失败行呈报、状态不误翻。
