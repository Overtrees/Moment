# 配对二维码：流向与载荷定案 + 落码清单（2026-11-27，只读设计、停门）

> 状态：**设计完成、未落码**。用户 2026-11-27 17:13 裁定「配对二维码做」（审计 audit_home_other_deep.md §5.9(a) 缺失项）。
> **双门核查**：门① 已过——0.9.57 组版提交落定（HEAD 6ce6cd8），工作树无代码改动（仅未跟踪报告）。门② **未过**——续连根治批（fix_bridge_reconnect_flow.md 的 R1 会话恢复令牌 / R2 / A1–A3）仍只有设计报告，全仓 grep `resumeToken` 代码零命中、未落码。故本批按纪律只出设计、不动 App/中继/连接器任何代码；门②过后先做第六节的前置复核，再按第五节清单落码。

---

## 一、现行配对协议实态（proven，落码设计以此为准）

| 环节 | 实态 | 出处 |
|---|---|---|
| 发起 | App `beginPairing` 铸/复用 pairingId，待配对会话落 Keychain 持久（id + expiresAtMs），设备 P-256 密钥对在 Keychain、从不出设备 | MomentBridge.swift:711-775、164-212 |
| 注册 | App POST `/pair-start` {pairingId, pubKeyB64, fingerprint, label, scopes:["read"] 请求}；已 paired 的记录再 start 回 409 | bridge/relay/worker.js:632-669 |
| 待配对寿命 | **600 秒**（铸时 `epochMs() + 600_000`），过期由状态轮询清除待配对 | MomentBridge.swift:744、823-828 |
| 确认面 | 配对页 `GET /pair?pid=&fp=`（中继托管 HTML），页面上核对指纹 + 勾选 scopes → POST `/pair/confirm` | worker.js:1083-1110、1137-1174 |
| 客户端密钥 | confirm 时由中继铸 `clientKey = mb1.<pairingId>.<secret>`，**仅在完成页显示一次**，用户自行录入 Muse 安全凭据页；App 永不持有此密钥（与设备凭据是两套不同秘密） | worker.js:711-714；custom.moment-bridge/CONNECTOR.md |
| App 侧收敛 | App 轮询 `/pair-status` → paired → `finishPairing` 落 pairingId/scopes → connectNow | MomentBridge.swift:793-852 |
| 配对页 URL 单一构造点 | `BridgeCoordinator.pairingURL()`：`relayBase + "/pair"` + query {pid, fp}，设置页「打开配对页」钮消费它（本机浏览器 openURL） | MomentBridge.swift:672-681；MomentBridgeSettings.swift:165-172 |
| 现行文案口径 | `bridge.unpaired_note` 已写明「用另一台设备打开配对页完成确认」——跨设备本就是既定流程口径，缺的只是把链接送达另一台设备的通道（现只有本机 openURL 一条路） | rust/apps/web/lang/zh-CN.json |

## 二、流向定案：App 呈现型单向（扫入方向否决）

**定案：App 在待配对分支呈现二维码，内容 = 配对页 URL；用户用另一台设备的相机扫码，在那台设备上完成核对与确认。** 与既有链接路并行，链接路保留不退役（同 URL、同构造点，二维码只是新通道）。

扫入方向（App 扫别侧的码）逐项否决：

1. **无码可扫**：pairingId 由 App 铸造，配对开始前别侧不存在任何待扫材料；倒置发起方等于另立协议，不属本批。
2. **唯一候选载荷是 clientKey，而它不许进码、App 也不许持有**：clientKey 是中继在 confirm 时铸给「客户端」（Muse 侧）的 bearer 秘密，与设备凭据是两套秘密（CONNECTOR.md 明文）；App 既不需要它，让它以二维码图像形态出现（可截图、可被相册/备份留存）是安全倒退。
3. **确认侧需要的是浏览器**（勾 scopes、看完成页的 clientKey），不是 App；扫入 App 对确认流程零增益。

## 三、载荷定案（字段白名单 + 排除论证）

载荷 = `pairingURL()` 的输出逐字，即：

```
https://moment-bridge.overtrees.workers.dev/pair?pid=<pairingId>&fp=<fingerprint>
```

| 字段 | 性质 | 入码依据 |
|---|---|---|
| scheme/host/path | 中继公开端点 | 与链接路同址，无新增暴露面 |
| pid（pairingId） | 房间标识，**非凭据**（续连报告 R1 口径同判：pairingId 本身仍非凭据；MCP 调用另需 clientKey、设备连接另需挑战签名） | 确认页寻址必需 |
| fp（fingerprint） | 设备公钥 sha256 前 16 hex 的分组呈现——由公钥单向导出、公开量 | 确认页据此显示待核对指纹，与 App 大字指纹构成双端核对；App 本就将其大字明示在同一张卡上 |

**排除清单（逐项证据）**：

| 排除项 | 排除理由 |
|---|---|
| 设备私钥 | 永不出 Keychain/设备；`pairingURL()` 不引用它（MomentBridge.swift:672-681 通读实证）。落码断言 B16-QR-2 锁其在二维码链零出现 |
| 设备公钥 pubKeyB64 | 无需入码：已由 App 经 `/pair-start` API 注册到中继记录，确认页按 pid 取记录即可 |
| clientKey | 二维码呈现时**尚不存在**（confirm 才铸）；且属客户端秘密、App 永不持有（见二节第 2 条） |
| resumeToken（R1 落码后） | 定位是**已配对会话的续连凭据**，welcome 帧下发、Keychain 与私钥同级存放——不是配对材料；配对时点亦不存在。将其放进可视图像等于把活凭据贴出，红线排除；落码断言 B16-QR-2 一并锁零出现 |
| scopes 请求 | 无需入码：请求 scopes 由 `/pair-start` 已报中继，授权勾选在确认页完成 |

**R1 不变性论证**：R1 的落码面是 welcome/新增 `resume` 帧、令牌落盘与轮换、ping 去往返、探活与 scopes 条件写（fix_bridge_reconnect_flow.md 第四节逐项）——不触 `/pair-start`、`/pair-confirm`、`pairingURL()` 与指纹定义。故载荷格式对 R1 落码形态不变，本设计不因门②未过而悬置；门②的意义是领地避让（MomentBridge.swift / MomentBridgeSettings.swift 同文件）与「以落定形态为准」的复核义务，复核动作见第六节。

## 四、安全论证

- **暴露面不新增类别**：二维码与链接是同一 URL 的两个通道；能拿到 URL 的人在 600 秒待配对窗内本就可达确认页（链接可被转发、URL 可被抄录）。二维码新增的只是「同场肩窥/拍照」这一物理通道。
- **确认能力 = 窗内持有 pid**，此性质先于二维码存在（链接路同）。既有约束逐项仍成立：① 会话只能由设备侧发起（`/pair-start` 须先注册公钥记录，别侧无法凭空铸会话）；② 600 秒过期、轮询清除；③ 指纹双端核对面不变（App 大字指纹 + 确认页 fp 显示，`bridge.pair_hint` 已要求核对一致再确认）。
- **残余风险（如实登记）**：待配对窗内二维码被拍下且抢先确认，对方可选 scopes 并看到一次性 clientKey。检测面：App 会翻到已配对态（用户未操作却已配对即可见异常）、授权 scopes 在已配对分支明示；处置面：断开并吊销一键可达、吊销后 clientKey 立即失效。此残余与链接路同级，定案为**接受并靠检测+吊销收口**，不在本批加新机制（如确认码二次输入属协议变更，收益不抵其对既有手动路的扰动，明确不采）。
- **呈现纪律（落码约束）**：二维码只存在于待配对分支；取消/过期/配对成功任一发生即随分支消失（与指纹、链接钮同生命周期）；已配对分支零二维码。

## 五、落码清单（门②过后执行）

### App（仓库 Moment）

1. **新文件 `MomentBridgeQR.swift`**（独立文件，不塞上帝文件）：纯函数 `makePairingQRImage(_ urlString: String) -> UIImage?`——CoreImage `CIQRCodeGenerator`，`inputMessage` = URL UTF-8、`inputCorrectionLevel = "M"`；输出经 `CGAffineTransform` 放大 + `CIContext` 出图。无状态、无 Diag 依赖。落码时按 build-app2.sh 惯例加入构建名单（16 遍 + primary 遍）。
2. **MomentBridgeSettings.swift 待配对分支**（`pairingSection` 的 `if let pending` 段内，指纹/提示之下、按钮行之上）：
   - 二维码视图：`if let url = bridge.pairingURL(), let img = makePairingQRImage(url.absoluteString)` 呈现，固定边长约 148pt；**必须置于白色圆角底板上**（深色模式下二维码对比度是功能要求，非装饰）；缩放重采样关插值由生成侧放大倍数保证，不在视图层处理。
   - 码下说明行：`Lang.t("bridge.pair_qr_hint")`，12pt 次级色，与 pair_hint 同级。
   - **过期呈现（审计 §5.9(c) 并入本批，理由见七节）**：同分支加一行 `Lang.t("bridge.pair_expires", …)` 显示本轮有效期至时刻（数据源 = `pending.expiresAtMs`，已落盘现成；时刻格式用 App 既有时刻格式化口径）；过期态文案键 `bridge.pair_expired` 备用——注：现行轮询在过期时即清 pending、分支整体消失，故 expired 文案的实际出场面是「页面停留期间刚过期的边界瞬间」，落码时以轮询清除行为实读为准决定是否接线，不为接线而改轮询。
   - 链接钮、取消钮、指纹行一字不动（手动路保留）。
3. **语言包五包各 +2~3 键**（360 → 362/363，五包守恒、既有 [9] 键对账断言覆盖）：
   - `bridge.pair_qr_hint`：zh-CN「用另一台设备的相机扫码，在那台设备上打开配对页」/ zh-TW「用另一台裝置的相機掃碼，在該裝置上開啟配對頁」/ en-US「Scan with another device's camera to open the pairing page on that device」/ ja-JP「別のデバイスのカメラでスキャンすると、そのデバイスでペアリングページが開きます」/ ko-KR「다른 기기의 카메라로 스캔하면 해당 기기에서 페어링 페이지가 열립니다」
   - `bridge.pair_expires`（模板 `{time}`，沿包内 `{n}`/`{when}` 既有约定）：zh-CN「本轮配对有效期至 {time}」/ zh-TW「本輪配對有效期至 {time}」/ en-US「This pairing round expires at {time}」/ ja-JP「このペアリングの有効期限は {time} までです」/ ko-KR「이번 페어링은 {time}까지 유효합니다」
   - `bridge.pair_expired`：zh-CN「本轮配对已过期，请重新开始配对」/ zh-TW「本輪配對已過期，請重新開始配對」/ en-US「This pairing round has expired — start pairing again」/ ja-JP「このペアリングは期限切れです。もう一度開始してください」/ ko-KR「이번 페어링이 만료되었습니다. 다시 시작해 주세요」
4. **Diag**：不新增行——纯呈现增补，配对生命周期既有打点足够（终判靠真扫）。

### 中继（bridge/relay）

**零改动**：确认页 `GET /pair` 已消费 pid/fp query（worker.js:1137-1138），载荷即现行 URL。无部署、无工具面变化，list-tools 件数与 manifestHash 天然不漂移。

### 连接器（custom.moment-bridge）

5. **client.py 加 `parse-pair-url` 子命令**（纯本地解析、不发网络）：入参为扫码/复制得到的字符串，校验 scheme=https、host=moment-bridge.overtrees.workers.dev、path=/pair、pid/fp 齐备 → 打印 pairingId 与指纹并提示「与 App 内指纹核对一致后再在该页确认」；格式不符/异 host 以非零码拒绝并说明。用途：用户把二维码内容以文本形式带回时，喂入即得结构化核对面（此即「扫码字符串可直接喂入」的落点——完成配对的动作仍在确认页，解析入口只做校验与核对，不代行确认）。
6. **CONNECTOR.md**：Connect 节补一小段二维码路说明（呈现位置、载荷只有 pid+fp、clientKey 仍只在完成页出现一次、parse-pair-url 用法）。

### verify 增补（归属组 [16]，落码时编号顺延）

- **B16-QR-1 载荷单源锁**：二维码视图只消费 `pairingURL()`（设置文件内 `pairingURL()` 引用计数 +1 且生成器入参为其 absoluteString）；`pairingURL()` 的 queryItems 恒为 pid+fp 两项（字面锚）。
- **B16-QR-2 排除锁**：`MomentBridgeQR.swift` 全文 + `pairingURL()` 函数体范围内，`clientKey` / `resumeToken` / 私钥存取标识（以落码时 Keychain 私钥键名为准）零出现（grep 断言）。
- **B16-QR-3 呈现面生命周期锁**：二维码视图引用在设置文件中恰一处且位于待配对分支锚点之间（以分支起止字面为界的顺序断言）；已配对分支段内零出现。
- **B16-QR-4 过期行锁**：待配对分支内 `bridge.pair_expires` 引用在位 + 数据源 `expiresAtMs` 同段出现。
- 连接器自测留痕：落码后以一条合成 URL 跑 `parse-pair-url` 正例 + 异 host/缺 fp 两条负例，输出贴入本报告落码补记。

## 六、落码前置复核（门②过后、动工前唯一复核项）

R1 落码后，对 `pair-start` / `pair-confirm` / `pairingURL()` / 指纹定义四处做 diff 复核：若与第三节假设一致（预期一致），本设计直接落码；若 R1 顺带改了配对材料（如指纹定义或 pid 语义），载荷节须先修订再落码。此复核是门②在本批的全部剩余义务，不重做设计。

## 七、审计 §5.9 另两条 P3 的处置分工

- **(c) 待配对过期不呈现 → 并入本批**：与二维码同在待配对分支、同一次 hunk 领地；分开排批等于两批先后改同一视图段，合并处置更省且账面完整。落码项见五节 App 第 2 条。
- **(b) 吊销回执不可见 → 不在本批，留桥呈现小批**：其面在已配对分支/断开流程与 Diag 分账（审计 §7 已将其归桥呈现小批），与待配对分支无交叠；本批不顺手扩围，归属在审计分批表已有登记，不丢账。

## 八、真机终判点（落码出包后）

1. 开始配对 → 待配对卡出现二维码（深色模式下底板为白、码清晰可扫）。
2. 用**另一台设备**扫码 → 配对页打开、页内指纹与 App 大字指纹一致 → 勾选 scopes 确认 → App 翻已配对、已授列表与勾选一致。
3. 完成页 clientKey 录入凭据页 → `bridge_status` 活通（fingerprint 对版）。
4. 已配对态回设置页：二维码不存在；断开重配一轮，二维码随新一轮待配对再现。
5. 待配对卡有效期行时刻与铸时 +600 秒一致；放任过期后分支按既有轮询口径收敛（不残留死码）。
6. 本机链接路回归：点「打开配对页」仍在本机浏览器打开同一 URL 完成配对（手动路未退役的实证）。
