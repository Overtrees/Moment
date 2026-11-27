# 配对二维码：落码篇（2026-11-27）

> 状态：**落码完成**——App 侧未提交、未 bump（随下一组版）；中继零改动、未部署；连接器已落码即生效。设计与清单见 impl_pairing_qr.md（本篇为其落码补记，不重做设计）。门②放行依据：impl_bridge_reconnect.md 落定（R1 已落码、中继已部署）。

---

## 一、前置复核（门②剩余义务，动工前完成）

对配对四处以落定形态逐字复核，与设计基线（impl_pairing_qr.md 第一、三节）一致，**无一处被 R1 改动**：

| 复核点 | 落定形态实证 | 结论 |
|---|---|---|
| `pairingURL()`（MomentBridge.swift:806） | queryItems 恒 `pid` + `fp` 两项、host = relayBase + `/pair`，函数体不引用任何凭据 | 与设计逐字一致 |
| 指纹定义（MomentBridge.swift:71） | sha256(公钥原始表示) 前 16 hex、大写、四位分组 | 一致 |
| `/pair-start`（App 发起 + worker.js pairStart） | App POST {pairingId, pubKeyB64, fingerprint, label, scopes:["read"]}；中继 diff 的 7 个 hunk 全在 R1/R2 面（completeAuth/ping/presence/resume），pairStart/pairConfirm 本体零改动 | 一致 |
| `/pair-confirm`（worker.js pairConfirm + 确认页 GET /pair） | 路由与页面消费 pid/fp 的形态未动 | 一致 |

载荷口径不变（pairingURL 逐字），照单落码。

## 二、逐项落码

### App（仓库 Moment）

1. **新文件 `MomentBridgeQR.swift`**：纯函数 `makePairingQRImage(_:) -> UIImage?`——`CIQRCodeGenerator`，`inputMessage` = URL UTF-8、`inputCorrectionLevel = "M"`，整数倍（×8）放大后 `CIContext` 出图。无状态、无 Diag、无凭据词（B16-QR-2 锁）。
2. **build-app2.sh 接线**：QR 文件入全部 19 遍主 App 编译的次级输入 + 新增第 20 遍 `-primary-file` 出 `bridge_qr.o` + 链接行入 `bridge_qr.o`（`grep -c MomentBridgeQR.swift` = 20、bridge_qr.o 出现 2 处 = primary 遍 + 链接行）。**并发注记**：落码期间 M3a 批把 MomentBridgeScenarios 接进同一脚本（新增 bridge_scenarios 遍、尾部与链接行结构变化），本批最后两处（liveops_attr 遍、链接行）按变化后形态重锚落码，两批接线共存、互不覆盖（完工复验 Scenarios 计数 20 在位）。
3. **push_small.py 名单**：app 文件元组加 `MomentBridgeQR.swift`。
4. **MomentBridgeSettings.swift 待配对分支**（`pairingSection` 的 `if let pending` 段，pair_waiting 之下、按钮行之上）：
   - 二维码块：`if let url = bridge.pairingURL(), let qr = makePairingQRImage(url.absoluteString)` 呈现，148×148、`.interpolation(.none)`、padding 10 置于白色圆角底板（`Color.white` + `Radius.controlS`）——深色模式可扫性为功能要求。
   - 码下说明行：`bridge.pair_qr_hint`（.caption 次级色，与 pair_hint 同级）。
   - 有效期行（审计 §5.9(c) 并入项）：`Lang.tf("bridge.pair_expires", ["time": timeText(pending.expiresAtMs)])`，时刻格式沿本页既有 `timeText`（HH:mm:ss）口径，数据源 = `pending.expiresAtMs` 现成字段。
   - 链接钮、取消钮、指纹行一字未动（手动路保留）。
   - `bridge.pair_expired` 键已入包备用、**未接线**：现行轮询在过期时即清 pending、分支整体消失，无出场面（按设计口径以轮询实读为准决定，不为接线改轮询）。
5. **Diag**：不新增行（设计口径，纯呈现增补）。

### 语言包（五包各 +3，367 → 370，键集五包一致）

`bridge.pair_qr_hint` / `bridge.pair_expires`（`{time}` 模板）/ `bridge.pair_expired`，键文逐字按设计 §5.3 五语表。verify [9] 期望已由在途批先行同步为 370（含完整注释账），本批落码后 [9] 双断言转绿（见第四节）。

### 中继（bridge/relay）

**零改动、未部署**：git diff 中 worker.js 的 hunk 全属续连批，本批未触。完工线上复核：`list-tools` 回 **31 件**，与本批开工前基线（续连批部署后口径）一致、**零漂移**。注：任务简报所称 35 件是 M3a 的目标清单，其 App 侧尚在落码、中继未 redeploy，线上现行仍 31 件——此为 M3a 批次自身进度，非本批账面。

### 连接器（custom.moment-bridge）

6. **client.py 新增 `parse-pair-url` 子命令**（纯本地、零网络、先于 Client 构造处理）：校验 scheme=https、host=moment-bridge.overtrees.workers.dev（端口仅 None/443、无 userinfo）、path=/pair、pid/fp 齐备 → 打印 pairingId 与指纹 + 核对提示；任一不符以 McpError 非零码拒绝并说明。不代行确认（确认仍在配对页）。
7. **CONNECTOR.md**：Connect 节补二维码段（呈现位置、载荷只有 pid+fp、clientKey 仍只在完成页出现一次、有效期 600 秒、parse-pair-url 用法）；helper 能力行同步加 parse-pair-url。

## 三、连接器自测留痕（设计 §5 要求）

```
$ client.py parse-pair-url 'https://moment-bridge.overtrees.workers.dev/pair?pid=3F2504E0-…&fp=156E%208166%201ED7%20642F'
pairingId: 3F2504E0-4F89-41D3-9A0C-0305E82C3301
fingerprint: 156E 8166 1ED7 642F
核对：与 App 配对卡上的大字指纹完全一致后，再在打开配对页的那台设备上确认配对。
exit=0

$ client.py parse-pair-url 'https://evil.example.com/pair?pid=X&fp=Y'
error: pair URL host must be moment-bridge.overtrees.workers.dev
exit=1

$ client.py parse-pair-url 'https://moment-bridge.overtrees.workers.dev/pair?pid=X'
error: pair URL must carry both pid and fp
exit=1
```

（正例中的 pid 为合成值；fp 的 %20 解码与分组呈现均正确。）

## 四、断言与自跑

- verify 新增 **B16-QR-1..4**（[16] 组尾，B16-20 之后）：
  - QR-1 载荷单源锁：pairingURL 函数段 queryItems 恰 pid+fp 两项、设置页 `pairingURL()` 引用恰 2 处、设置页消费 `makePairingQRImage(url.absoluteString)`、build 名单含 bridge_qr.o。
  - QR-2 排除锁：MomentBridgeQR.swift 全文 + pairingURL 函数体段内 `clientKey` / `resumeToken` / `privateKey` / `keyTag` 零出现。
  - QR-3 生命周期锁：设置页 `makePairingQRImage` 恰 1 处且位于待配对分支段内（分支外即已配对段零出现由段界保证）。
  - QR-4 过期行锁：待配对分支段内 `bridge.pair_expires` 与 `pending.expiresAtMs` 同在。
- 本机自跑 verify 全量：**337 ✓**；本批相关 [9] 两条（键集一致、键数 370）✓、B16-QR-1..4 全 ✓、[16] 既有条目零回潮。剩余 ✗ 5 条全非本批：产物类 2 条（ipa 陈旧、产物语言包——tree 构建自解）+ B27-3/5/9 三条（M3a 批自家断言对其半落码状态的如实读数，归 M3a 收口）。
- 本机无 swiftc（既定分工）：Swift 编译级自检随下一组版 tree 全量冒烟把关；落码段已逐行自审（设置页待配对分支成型形态目检无误）。
- 并发账：动工前全树 diff 快照（6497 行）留底；完工复验——他人 hunk 逐项在位（M3a 的 Scenarios 构建接线与 B27 断言、权限批 [9] 370 同步与 [33] 组、续连批 B16-20 均完好），本批 hunk 与之逐段错开。

## 五、真机终判点（出包后，按设计 §8）

1. 开始配对 → 待配对卡出现二维码（深色模式下底板为白、码清晰可扫）。
2. 用**另一台设备**扫码 → 配对页打开、页内指纹与 App 大字指纹一致 → 勾选 scopes 确认 → App 翻已配对、已授列表与勾选一致。
3. 完成页 clientKey 录入凭据页 → `bridge_status` 活通（fingerprint 对版）。
4. 已配对态回设置页：二维码不存在；断开重配一轮，二维码随新一轮待配对再现。
5. 待配对卡有效期行时刻与铸时 +600 秒一致；放任过期后分支按既有轮询口径收敛（不残留死码）。
6. 本机链接路回归：点「打开配对页」仍在本机浏览器打开同一 URL 完成配对（手动路未退役的实证）。
