# 桥连接实况保活：桥会话 Live Activity + 驻留成对量测（2026-11-27）

> 用户指示：使用实况（Live Activities）解决桥连接掉线问题。基线：impl_entitlements_b.md（权限 B 段，LiveOps 封装已落）、impl_bridge_reconnect.md（续连根治已落、中继已部署）、fix_bridge_reconnect_flow.md（平台边界账）。
> 状态：**落码完成**——未提交、未 bump；动工时 HEAD = d540d89（0.9.57）、组版未开工，**本批随 0.9.58 组版**。

---

## 一、平台边界（先说清，不许升级表述）

- iOS 后台挂起不可达是平台事实；Live Activity 是保活辅助、非进程永生——它本身不直接延长 WSS 套接字寿命。本批不宣称挂起后仍可达、不宣称远程唤醒。
- 推送口径订正（用户 2026-11-27 18:07）：**推送权限（aps-environment）在签名证书的 44 项权限内、确实有**，B 段已嵌入并在 tree 实证可签可回读——不是「无推送权限」。准确的缺口是**发送方凭据**：APNs 密钥（.p8）/推送证书由 App ID 所属团队的开发者账号签发；现行签名证书来自卖家团队，我方未持有该团队的 APNs 密钥，故无人能向 APNs 发送。平台边界结论不变：本批无远程唤醒、无推送驱动的实况更新（实况更新只发生在前台与回前台机会点）；待用户个人 Developer 账号就绪、APNs 密钥可签发后，远程唤醒才成为可立项面（与 iCloud 同门）。
- 本批目标（收敛定义）：掉得晚一点（真实操作期与短暂切后台不掉）、掉后回得快且可见（沿用续连批机制、回前台即收敛）、状态在锁屏可见——全部以量测说话（第二节）。

## 二、基线量测口径（先量测后落码）

现行 Diag 已有原料：`BRIDGE presence state=background/foreground`（带时戳）、`BRIDGE session down reason= dur=`、`BRIDGE session up`、`BRIDGE probe ok/fail`、`BRIDGE state a->b`。0.9.57 口径下两数要跨行夹算：

- **入后台后套接字存活时长** = session down 行时戳 − 同次 presence background 行时戳；驻留全程无 down 行且回前台 probe ok ⇒ 全程存活（下限 = 驻留时长）。
- **回前台恢复时长** = presence foreground 行 → 其后首条 session up（已死重连）或 probe ok（存活结案）之差。

本批增量（把夹算变直读）：

| 新行 | 出处 | 内容 |
|---|---|---|
| `BRIDGE bg return dur=<s> socket=up\|down live=on\|off` | 协调器 willEnterForeground（presence 行后、既有收敛逻辑前） | 驻留时长 × 驻留期间有无 session down 落账 × 实况是否在位。socket=up 只陈述「无 down 落账」，真伪由紧随的 probe ok/fail 结案——三元组判读：up+probe ok = 存活；up+probe fail = 半死（发现延迟段）；down = 已死，存活时长由 session down 与 presence background 两行夹出 |
| `BRIDGE live start fp=<指纹短记>` / `start adopted=1` / `end state=<状态词>` / `unavailable` | MomentLiveOps.bridgeLiveSync | 实况在位区间与降级留痕；与既有 `OPS live start/update/end/skip`（kind=bridge）同批对读 |
| `BRIDGE live …` 之外的既有行 | 不动 | session up/down、probe、resume ok/fallback 口径全沿用续连批 |

无量测不宣称改善：第五节的量测表以 0.9.57 现行行为（无实况、宽限只覆盖操作期）为对照基线，结论以实测分布为准。

## 三、落码面

| 文件 | 改动 |
|---|---|
| MomentLiveOpsAttributes.swift | `LiveOpKind` 增 `bridge`；`OpsActivityAttributes` 增 `opDetail`（静态短记、默认空）。双目标同编同文件、类型全名不变 |
| MomentLiveOps.swift | ① 文件头口径扩桥会话段；② `start` 增 `detail` 形参（默认空、既有调用零改动）写入 opDetail；③ `end` 增 `linger` 覆盖形参（默认 nil = 旧口径，桥收口传 15s）；④ `expireGrace` 跳过桥会话（不打 waiting——其状态词即连接态本身）；⑤ 新增桥会话段：`bridgeLiveId/bridgeLiveActive/bridgeLiveSync/adoptBridgeActivity/sweepStaleBridgeActivities` |
| MomentBridge.swift | ① `backgroundAt` 驻留起表点（didEnterBackground 观察头部）；② `syncBridgeLive()` 收敛单点 + `setState` 迁移后调用；③ willEnterForeground 增 `BRIDGE bg return` 行 + 末尾 `syncBridgeLive()` 刷新调用 |
| MomentLiveOpsWidget.swift | 锁屏面标题行右侧呈现 opDetail（非空才现；操作类恒空、呈现与旧版一致）。零新增文案、零硬编码串 |
| lang ×5 | 新键 `liveops.bridge_session`（桥连接/橋連接/Bridge connection/ブリッジ接続/브리지 연결）；键数 370 → 371 |
| verify_ios.sh | 键数期望 371 + 注释链；新组 **[38]** B38-1…B38-6 |

无新文件——构建名单（build-app2.sh）零改动，B34-5 接线断言不受影响。

### 3.1 桥会话实况形态

- **起**：协调器状态迁移到连接态族（connected/connecting/backoff）且开启+已配对+未被 OPS 禁用 ⇒ 经 `bridgeLiveSync(want=true)` 起一条 kind=bridge 实况。连接中即起（步文案 = 当前状态词、如实），随状态迁移刷新为已连接/重连中。
- **呈现**：标题 = `liveops.bridge_session`（当前语言定格）；步文案 = `Lang.t(linkStateKey)`——与设置页 MCP 桥行、桥设置页卡头**同一文案源**，锁屏所见即设置页所见；灵动岛 expanded 底区同呈步文案，compact 呈标题。opDetail = 设备指纹首尾组短记（如 `D5F7…3E3C`），只放公开寻址信息，绝不放密钥/令牌。
- **更新**：复用封装节流口径——phase 翻转（已连接 ↔ 非已连接）立即发；同 phase 内步文案变化（连接中 ↔ 重连中）按 5s 合并。锁屏文案相对状态机的最大滞后 = 同 phase 子态间 ≤5s，精确口径以 Diag `BRIDGE state` 行为准（呈现不反超事实、无粉饰）。
- **止**：关闭桥/解配对/吊销/OPS 禁用 ⇒ want=false，终态帧（当前状态词）+ 15s 短留消退。App 被杀残留的一条在下次 sync 时**认领**（adopt）刷新而非重复 request；多余残留由 sweep 走同一 end 收口。
- **staleDate**：沿用封装 +10min；回前台刷新机会点重发当前态续期。挂起超过 10min 后锁屏面按系统口径显陈旧——那正是事实（状态未知），回前台即刷新，不以本地推测续命文案。

### 3.2 保活挂点（只挂真实机制）

1. **前台连通期操作**：沿用 B 段四挂点（场景运行/桥长操作/导出/导入），零改动。
2. **切后台宽限覆盖桥会话**：桥会话同在 `sessions` 内，`hasActive` 恒含它——didEnterBackground 时 `appDidEnterBackground()` 的既有组合（beginBackgroundTask + BGTask 续提）自动覆盖桥。宽限窗（约 30s、系统给定）内进程未挂起、套接字真实存活：在飞的桥调用得以回执、场景 journal 得以落盘收口；短于宽限窗的切后台（如看一眼通知再回来）套接字可能根本不断。**边界如实**：宽限过后照常挂起，本机制不延长其后寿命；驻留超过宽限窗的存活与否由量测表判读，不预设。
3. **回前台/刷新机会点收敛**：willEnterForeground 既有链（presence/connectNow）+ didBecomeActive 探活 + 恢复令牌路径全不动；新增仅 `syncBridgeLive()` 一次实况刷新（当前态 + staleDate 续期）。不新造第二条重连链（B38-5 以「connectNow→handleSocketDown 段零 bridgeLive 引用」静态锁此界）。

### 3.3 边界守恒

- **状态如实**：实况文案逐字取状态机当前词（同源 linkStateKey），断开显断开、重连中显重连中；实况起落不写 linkState、不触发或抑制任何重连（连通路径与实况零耦合，B38-5 锁）。
- **降级零影响**：实况被用户在系统设置关闭（areActivitiesEnabled=false）或系统不支持时，`start` 返回 nil、记 `BRIDGE live unavailable` + `OPS live skip` 成对行，桥功能全量照常；want 条件每次迁移重评，用户重开系统实况后下一次状态迁移自动起。
- **OPS 禁用/安全模式**：want 含 `!opsDisabled`——运维禁用桥时实况同止，不留「桥已禁用但锁屏显已连接」的假面。

## 四、断言与自检

- verify 新组 **[38]**（B38-1 形态 / B38-2 request 单点复用单栈 / B38-3 起落收敛单点 / B38-4 成对量测面 / B38-5 边界守恒 / B38-6 呈现与五语键）**六条全绿**；[34] 九条、[16] 桥组、键数 371 全绿守恒；B34-6 挂点计数不受影响（桥同步不经 `.start/.end/.update` 挂点面计数文件）。
- 全量 verify：**360 ✓ / 2 ✗**，2 ✗ 为各批基线同款产物陈旧项（ipa 陈旧、产物语言包待构建），组版 tree 构建自解。
- 类型检查：本机 swift-frontend 同旗标（$COMMON 全量文件列表）主 pass + Widget pass（Widget+Attributes）**零 error**。
- 在途纪律：动工前全树 diff 快照（10,666 行）留档；完工以删除行集差集复验——我动过的已跟踪文件（MomentBridge.swift / verify_ios.sh / lang ×5）相对快照**零删除行增减**（我的改动对 HEAD 全为增行：370 计数块本身即在途未提交内容），DT 韧性批与标题传播批 hunk 零丢失；LiveOps 三文件为本波次新文件、无他人在途 hunk。

## 五、真机量测表（0.9.58 装后填，桥侧自办为主）

方法：桥开启+已配对+实况在位（Diag 见 `BRIDGE live start`）后，分别切后台静置 **1 / 5 / 15 分钟**三档、每档 ≥3 次；回前台后以 diag_tail 取 `BRIDGE bg return` 行为主、辅以 session down / probe / session up / resume 行夹算。对照基线 = 0.9.57 现行行为（无桥实况；同法以既有行夹算，历史 Diag 或装后回滚测均可，来源在表中注明）。

| 档 | 次数 | bg return（dur/socket/live） | 存活时长（down−bg，无 down 记 ≥dur） | 恢复时长（fg→probe ok 或 session up） | resume ok/fallback |
|---|---|---|---|---|---|
| 1 min | – | 待填 | 待填 | 待填 | 待填 |
| 5 min | – | 待填 | 待填 | 待填 | 待填 |
| 15 min | – | 待填 | 待填 | 待填 | 待填 |
| 基线 0.9.57（同三档） | – | 无此行（夹算） | 待填 | 待填 | 待填 |

判读口径：

- **1 分钟档**是宽限窗机制的主判面：socket=up + probe ok 占多数 ⇒ 「短暂切后台不断线」成立；若仍普遍 down，宽限未实际覆盖（查 grace begin/end 行是否成对），按机制追因、不改叙事。
- **5/15 分钟档**预期多数已挂起掉线：判读点不在存活（平台事实），在**恢复时长**与续连批目标（温启 2.5–4s）的一致性、及锁屏状态文案与 Diag 状态序列的一致性（回前台前锁屏所显应为最后已知态、回前台数秒内刷新为已连接）。
- **诚实结论条款**：若三档实测显示实况对套接字存活时长无显著延长（宽限窗外分布与基线同），如实写明——本批保留其状态呈现与短驻留收口价值，不硬凑改善叙事；显著性以同档 ≥3 次的分布对比为准，不以单次个案下结论。
- 降级抽验：系统设置关闭实况后重复一档——桥连通/恢复行为与开启时同口径（Diag 多 `BRIDGE live unavailable`、无 live 行），功能零差。

## 六、真机终判点（用户侧只需一眼的部分）

1. 桥连通后锁屏：出现「桥连接」实况，文案与设置页桥状态同词，右侧指纹短记与桥设置页指纹首尾组一致。
2. 切后台 30s 内回前台：桥不应经历一轮可见的断开-重连（设置页状态恒已连接或仅瞬时探活行）。
3. 系统设置关掉本 App 实况后再用桥：一切照常，仅锁屏无实况。
