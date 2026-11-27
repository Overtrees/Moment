# iOS 权限声明拉满 + Live Activity 操作期保活（2026-11-27）

> 状态：**A 段（只读审计 + 设计）完成；B 段停门未动工**——硬门未过：HEAD 仍为 fdb1a67（0.9.56），0.9.57 组版 bump 提交未落，工作树有组版波次未提交改动（17 个已改文件 + 9 份未跟踪报告）。门过（git log 见 0.9.57 bump 提交且组版改动提交干净）后按第七节清单直接落码，无需重做设计。
> 风险先验按用户 2026-11-27 16:54 更正：证书权限清单用户此前已出示，**已知实锤受限项仅 iCloud 容器**（授权数为零、卖家确认不支持）；其余能力一律按「预期可签、B 段 tree 签名实证定案」分级。预登记 parked 只留 iCloud 一类。签名实证门不变：逐条以实嵌集合为准，实证推翻先验的以实证为准并回填本报告。

---

## 一、现状审计（proven，逐项实读）

### 1.1 Info.plist 现有键

Info.plist 由 `build-app2.sh` heredoc 内嵌生成（无独立 plist 文件），现行键全集：

| 键 | 现值 | 备注 |
|---|---|---|
| CFBundleDevelopmentRegion | zh_CN | |
| CFBundleDisplayName | 此刻 | 五语显示名走 InfoPlist.strings（i18n I5 在册），现无任何 .lproj |
| CFBundleIdentifier | com.canopies.moment | |
| CFBundleShortVersionString / CFBundleVersion | 0.9.56 / 83 | 组版 bump 维护点，verify [1] 三处一致口径 |
| MinimumOSVersion | 16.0 | Live Activity 需 16.1+，代码侧须 `#available` 门（见第五节） |
| UIDeviceFamily | [1, 2] | iPhone + iPad |
| UISupportedInterfaceOrientations~ipad | 竖 + 双横 | |
| **NSLocationWhenInUseUsageDescription** | 用于显示你所在城市的天气 | **全表唯一的用途声明**，且只有中文（无本地化副本） |
| UILaunchScreen / UIStatusBarStyle / UIViewControllerBasedStatusBarAppearance | 开屏色 / LightContent / false | |
| CFBundleIcons(​~ipad) | AppIcon | Assets.car 路线 |

**缺失**：UIBackgroundModes、NSSupportsLiveActivities(​FrequentUpdates)、BGTaskSchedulerPermittedIdentifiers、其余全部用途声明、aps 相关一切。

### 1.2 Entitlements 现状

- **无 .entitlements 文件**（全仓零命中）；build / smoke / verify 三脚本无 codesign 步骤。
- 链接期以 `-Wl,-adhoc_codesign`（build-app2.sh:269）产 **adhoc 签名 + 空 entitlements**。
- 装机链：产物 ipa 由用户以全能签 + 购入证书（Team ZP7KP7TN22，TEST SIGNING，1 设备，2027-11-20 到期）重签安装（技能 package.md 口径）。重签工具通常原样保留二进制内嵌 entitlements，再由签名包内 profile 校验授权。
- **工具缺口（B 段第 0 步）**：本机与 tree 的 `~/ios-native/bin` 只有 accord / ios-clang-link / ld64.lld / xcrun（垫片）；**无 ldid / zsign / codesign**——现链路没有任何「把 entitlements 嵌进 adhoc 签名并回读核对」的工具。B 段须先在 tree 建立（ldid 或 zsign，版本钉住、装 `~/ios-native/bin`），并以回读命令（ldid -e / 等价签名 blob 解析）作实证手段。此为「缺工具先自补」红线项，不作停工理由。

### 1.3 框架与扩展现状

- 显式链接：SwiftUI / WebKit / UIKit / Foundation / CoreLocation；Swift autolink 覆盖 AVKit、PhotosUI、Network、CryptoKit、Security、ImageIO 等（各文件 import 实证）。
- **无任何 app extension**（构建不产 PlugIns/），单二进制。Live Activity 的可见呈现须新增 widget extension 目标（第五节，此为本设计对 B 段文件清单的关键补充）。

---

## 二、权限使用点对账（grep 全仓实证）

| 能力 | 代码使用点 | 结论 |
|---|---|---|
| 定位 WhenInUse | `WeatherService`（MomentApp.swift:14984 起）：CLLocationManager + `requestWhenInUseAuthorization()`（:15376），一次性取经纬度 → 天气链；**无 requestAlways、无后台定位** | 已声明已用，唯缺五语本地化 |
| 相册读取 | PHPicker（MomentApp.swift:3336 起，PHPickerViewController）——进程外选择器，**不需要** NSPhotoLibraryUsageDescription；全仓无 PHPhotoLibrary / PHAsset 直读、无保存到相册 | 声明与现行路径无关（惰性就绪，见矩阵） |
| 视频播放 | AVPlayer / AVPlayerViewController（:12965 起）行内前台播放 | 前台行为，无后台音频诉求 |
| 音乐 | musicCard = 链接解析成元数据卡（submitMusicInput / startResolveCard），**无应用内音频播放引擎** | 见 UIBackgroundModes audio 裁定 |
| 音频会话 | **AVAudioSession 全仓零命中** | 无后台音频实际用途（决定性证据） |
| 相机 / 麦克风 / 语音 | AVCaptureDevice、UIImagePicker、AVAudioRecorder、SFSpeechRecognizer 全零命中 | 无消费点 |
| Face ID | LocalAuthentication / LAContext 零命中 | 无消费点 |
| 通知 | UNUserNotificationCenter、registerForRemoteNotifications 零命中 | 无消费点（推送/实况的未来面） |
| 后台任务 | beginBackgroundTask、BGTaskScheduler 零命中；桥仅有 UIApplication 生命周期观察（MomentBridge.swift:528–559）+ 稳定性批前台探活 | 无消费点，B 段 LiveOps 组合点已定位 |
| 本地网络 | NWBrowser / NWListener / Bonjour 零命中；桥走公网 WSS 中继（非局域网，iOS 本地网络门禁不适用） | 无消费点 |
| 蓝牙 / 运动 / 日历 / 提醒 / 通讯录 / 健康 | CBCentralManager、CMMotionManager、EKEventStore 等全零命中 | 无消费点 |
| 分享 / 文件 | UIActivityViewController（:3453）；文件导入走系统选择器 / UTI | 系统托管，无需声明 |
| 长操作面（保活挂点） | 桥快照（MomentBridgeTools.swift:901–942，只读 FFI 直调 exportBackup）、恢复路径（同文件 :1100 起）、两段提交分发（同文件 :88–217，actionToken 记录 = 工具+参数哈希+60s 一次性）、uitest_run 驱动核（MomentBridgeUITest.swift `begin(scenario:)` :427、运行生命周期 :470–509）、App 侧 `Library.exportZip()`（MomentApp.swift:1530）/ `importBackup`（:1654）、救援页 exportZipAction（MomentRescue.swift:352） | 第五节挂点逐个落在此表 |

---

## 三、声明矩阵

分级口径：**A** = 纯 Info.plist 声明，零签名风险；**B** = entitlement 或行为性声明，预期可签、B 段 tree 签名实证定案；**P** = parked，本期不嵌，待用户 Developer Program（**仅 iCloud 一类**，按更正先验）。
总原则：**用途文案（plist 字符串）拉满**——字符串零签名风险、永不主动触发弹窗（仅当代码真调用对应 API 时才弹），且缺串时调用 API 是硬崩溃，预声明是防未来功能落码即崩的保险；**entitlement 与后台模式按用途与实证收敛**——它们有签名/行为后果，不无脑全加。无用途且无功能面的逐行给不声明理由。

### 3.1 用途文案（Info.plist Usage Description，全部 A 级）

| # | 键 | 解锁什么 | 消费点现状 | 裁定 |
|---|---|---|---|---|
| 1 | NSLocationWhenInUseUsageDescription | 前台定位授权弹窗 | **在用**（天气） | **声明**（已有中文，五语本地化补齐，§四） |
| 2 | NSLocationAlwaysAndWhenInUseUsageDescription / NSLocationAlwaysUsageDescription | 后台定位 | 无；天气为前台一次性取位 | **不声明**：无后台定位功能面；声明 Always 须同时配 UIBackgroundModes location 并接受系统二次复核弹窗，纯增负担。触发条件：出现持续定位功能再议 |
| 3 | NSCameraUsageDescription | 相机拍摄 | 无（附件现走选择器） | **声明（惰性就绪）**：用户点名项；附件拍摄是本 App 功能面内的自然扩展，预声明防落码即崩 |
| 4 | NSPhotoLibraryUsageDescription | 相册直读（PHPhotoLibrary） | 无（PHPicker 不需要） | **声明（惰性就绪）**：用户点名项；现行选择器路径不会触发它 |
| 5 | NSPhotoLibraryAddUsageDescription | 保存到相册 | 无 | **声明（惰性就绪）**：导出图片存相册是导出功能面的自然扩展 |
| 6 | NSMicrophoneUsageDescription | 麦克风录音 | 无 | **声明（惰性就绪）**：用户点名项；语音备忘在笔记类功能面内 |
| 7 | NSFaceIDUsageDescription | Face ID 评估弹窗文案 | 无（LAContext 未用） | **声明（惰性就绪）**：用户点名项；应用锁是笔记类功能面；字符串本身永不触发弹窗 |
| 8 | NSLocalNetworkUsageDescription | 局域网访问授权 | 无（桥为公网 WSS，不受此门禁） | **声明（惰性就绪）**：用户点名项；局域网直连（如将来本地同步/直连设备）时才触发 |
| 9 | NSBonjourServices | Bonjour 服务发现 | 无 | **不声明**：无服务类型可填；乱填不存在的服务类型比不填更糟。随具体 LAN 功能与 #8 一并补 |
| 10 | NSBluetoothAlwaysUsageDescription | 蓝牙 | 无 | **不声明**：全 App 无 BLE 功能面（无外设同步/导入路径，现行及在册方案均无） |
| 11 | NSMotionUsageDescription | 运动与健身 | 无 | **不声明**：无 CoreMotion 功能面 |
| 12 | NSCalendarsUsageDescription / NSCalendarsFullAccessUsageDescription / NSRemindersUsageDescription / NSRemindersFullAccessUsageDescription | 日历/提醒读写 | 无 | **不声明**（任务明示口径）：待办是 App 内数据，无系统日历/提醒同步功能面；将来真做同步再按 iOS 17 全访问口径补 |
| 13 | NSContactsUsageDescription | 通讯录 | 无 | **不声明**：无联系人功能面 |
| 14 | NSHealthShareUsageDescription / NSHealthUpdateUsageDescription | 健康数据 | 无 | **不声明**：无健康功能面（且 HealthKit 另需 entitlement，不在本期） |
| 15 | NSSpeechRecognitionUsageDescription | 语音识别 | 无 | **不声明**：无识别功能面；语音备忘若只录不转写只需 #6。触发条件：落语音转写功能时与 #6 同批补 |
| 16 | NSAppleMusicUsageDescription | 媒体库 | 无 | **不声明**：音乐卡走外链解析，不读系统媒体库 |
| 17 | NSHomeKitUsageDescription / NSNFCReaderUsageDescription / NSSiriUsageDescription | 家庭/NFC/Siri | 无 | **不声明**：无功能面（NFC/Siri 另需 entitlement，不在本期） |

### 3.2 能力键与后台模式（Info.plist）

| # | 键 | 值 | 解锁什么 | 级 | 裁定 |
|---|---|---|---|---|---|
| 18 | NSSupportsLiveActivities | true | ActivityKit 启动实况 | A | **声明**（实况本体，无 entitlement 要求） |
| 19 | NSSupportsLiveActivitiesFrequentUpdates | true | 提高本地更新预算额度 | A | **声明**（iOS 17+ 语义，低版本惰性；App 侧仍自节流，§五） |
| 20 | UIBackgroundModes: remote-notification | 数组成员 | 静默推送唤醒处理 | A（键）/ 与 #24 配对 | **声明**：与 aps 配对的唤醒面；当前无推送发送方，声明先行、通道后建（发送方缺口记 §八） |
| 21 | UIBackgroundModes: processing | 数组成员 | BGProcessingTask 长任务调度 | A | **声明** + #22 标识符；诚实消费点 = 快照清理（现行已有 `BRIDGE snapshot pruned` 逻辑）与 OPS 指令拉取（现行已有 fetch 链）均可注册为真实后台任务，不造假活 |
| 22 | BGTaskSchedulerPermittedIdentifiers | [com.canopies.moment.bg.processing, com.canopies.moment.bg.refresh] | 上两行任务的注册白名单 | A | **声明**（与 #21/#23 同批，缺此键注册即崩） |
| 23 | UIBackgroundModes: fetch | 数组成员 | BGAppRefreshTask 周期刷新 | A | **声明**：消费点 = OPS 指令周期拉取（救援通道的真实需求）；与 processing 同批落注册代码 |
| 24 | UIBackgroundModes: audio | — | 后台音频播放 | — | **不声明（以实际用途裁定）**：AVAudioSession 全仓零命中、视频为行内前台播放、音乐为元数据卡无播放引擎——声明即虚假声明。触发条件：某批落 AVAudioSession `.playback` + 可后台的音乐播放后同批补 |
| 25 | UIBackgroundModes: location / bluetooth-central / bluetooth-peripheral / voip / external-accessory / nearby-interaction | — | 各对应后台模式 | — | **不声明**：逐项无功能面（与 #2/#10 同因）；voip 另涉推送类型合规，不碰 |

### 3.3 Entitlements（B 段生成 Moment.entitlements 并嵌入）

| # | Entitlement | 值 | 解锁什么 | 级 | 裁定 |
|---|---|---|---|---|---|
| 26 | aps-environment | development（嵌入实证值；最终值以用户签名包 profile 为准，重签工具可改写） | APNs 远程推送（含实况推送更新通道） | B | **预期可签，实证定案**：按更正先验不在 parked 之列 |
| 27 | com.apple.security.application-groups | — | App 与扩展共享容器 | B | **本期不声明**：实况设计刻意不依赖共享容器（属性/状态经 ActivityKit 本身传递，扩展只凭 ContentState 渲染，§五），无组即无此风险；将来扩展需共享图片/文件时再加 |
| 28 | keychain-access-groups | — | 钥匙串组共享 | B | **不声明**：桥身份用默认组工作正常，无跨目标共享需求 |
| 29 | get-task-allow | — | 调试附加 | — | **不声明**：调试专用，嵌入会破坏分发式安装，明确禁入 |
| 30 | com.apple.developer.icloud-container-identifiers / com.apple.developer.icloud-services / com.apple.developer.ubiquity-kvstore-identifier / com.apple.developer.ubiquity-container-identifiers | — | iCloud 容器 / CloudKit / iCloud 文档 | **P** | **PARKED（全矩阵唯一 parked 类）**：授权数为零、卖家确认不支持（实锤）；待用户自开 Developer Program 后启用，届时与原生 iCloud 备份接入同批落 |
| 31 | com.apple.developer.associated-domains / networking.wifi-info / HealthKit / NFC / Siri | — | 各对应能力 | B | **不声明**：无功能面（与 3.1 对应行同因），非 parked——将来有功能面按 B 级实证流程加 |

### 3.4 运行时授权（非声明，B 段代码点备案）

| 项 | 口径 |
|---|---|
| 通知授权（UNUserNotificationCenter.requestAuthorization） | 无 plist 串要求；**禁止启动时索取**——在桥设置页加开关、用户开启推送/实况相关功能时才请求（与现行设置页模式一致） |
| 实况开关（ActivityAuthorizationInfo.areActivitiesEnabled） | 系统设置面，用户可关；代码侧只读检测、关时挂点静默 no-op + Diag 一行（§五） |

---

## 四、五语用途文案（InfoPlist.strings）

落位：B 段在 build-app2.sh 内生成五份 `.lproj/InfoPlist.strings`（en.lproj / zh-Hans.lproj / zh-Hant.lproj / ja.lproj / ko.lproj）拷入 .app；键名即 plist 键，另含 CFBundleDisplayName（与 i18n 定案显示名一致：zh-CN 此刻 / en-US Moment / zh-TW 此刻 / ja-JP 瞬間 / ko-KR 순간）。**与 I5 的接缝**：I5 原计划「InfoPlist.strings 五语显示名」由本批提前落地（显示名 + 用途串同文件），I5 后续只做残余清零与通查，不再重复建文件——本报告即接缝备案。
plist 主文件内的字符串保留 zh-CN 为默认值（现行 NSLocationWhenInUseUsageDescription 中文值不动），.strings 按系统语言覆盖。术语对齐语言包（如 settings.weather_sub = 天气数据源令牌配置的用词风格）。

| 键 | zh-CN（= 主 plist 值） | zh-TW | en-US | ja-JP | ko-KR |
|---|---|---|---|---|---|
| NSLocationWhenInUseUsageDescription | 用于显示你所在城市的天气（现行值沿用） | 用於顯示你所在城市的天氣 | Show the weather for the city you are in | 現在いる都市の天気を表示するために使用します | 현재 계신 도시의 날씨를 표시하는 데 사용됩니다 |
| NSCameraUsageDescription | 用于拍摄照片并添加到备忘 | 用於拍攝照片並加入備忘 | Take photos and add them to your notes | 写真を撮影してメモに追加するために使用します | 사진을 촬영해 메모에 추가하는 데 사용됩니다 |
| NSPhotoLibraryUsageDescription | 用于从相册选取照片和视频添加到备忘 | 用於從相簿選取照片和影片加入備忘 | Pick photos and videos from your library to add to your notes | ライブラリから写真やビデオを選んでメモに追加するために使用します | 보관함에서 사진과 동영상을 선택해 메모에 추가하는 데 사용됩니다 |
| NSPhotoLibraryAddUsageDescription | 用于把备忘中的图片保存到相册 | 用於把備忘中的圖片儲存到相簿 | Save images from your notes to your photo library | メモの画像をフォトライブラリに保存するために使用します | 메모의 이미지를 사진 보관함에 저장하는 데 사용됩니다 |
| NSMicrophoneUsageDescription | 用于录制语音并添加到备忘 | 用於錄製語音並加入備忘 | Record voice and add it to your notes | 音声を録音してメモに追加するために使用します | 음성을 녹음해 메모에 추가하는 데 사용됩니다 |
| NSFaceIDUsageDescription | 用于通过面容 ID 解锁应用 | 用於透過面容 ID 解鎖應用程式 | Unlock the app with Face ID | Face IDでアプリのロックを解除するために使用します | Face ID로 앱 잠금을 해제하는 데 사용됩니다 |
| NSLocalNetworkUsageDescription | 用于在局域网内发现并连接你的其他设备 | 用於在區域網路內尋找並連接你的其他裝置 | Discover and connect to your other devices on the local network | ローカルネットワーク上の他のデバイスを検出して接続するために使用します | 로컬 네트워크에서 다른 기기를 찾아 연결하는 데 사용됩니다 |

---

## 五、Live Activity 保活设计

### 5.1 前置事实（官方文档实证）

- 实况的锁屏/灵动岛呈现由 **widget extension** 内的 `ActivityConfiguration` 绘制；主 App 无扩展时 `Activity.request` 无可见产物——**可见存在感与点击回前台路径都依赖扩展**，故扩展是本设计的必需件，不是可选装饰。
- 扩展进程不能联网、不能取定位；状态只能由主 App 经 ActivityKit 本地更新，或由 APNs 推送更新（发送方基建本期不建，§八）。
- 单个实况最长存活 8 小时（系统上限）；属性+状态合计 < 4KB（本设计数据量远低于此）。
- 部署目标 16.0 与 ActivityKit 16.1+ 的差：全部 ActivityKit 调用以 `if #available(iOS 16.1, *)` 门控，16.0 上挂点整体 no-op。

### 5.2 结构

| 件 | 内容 |
|---|---|
| `MomentLiveOpsAttributes.swift`（共享文件） | `OpsActivityAttributes: ActivityAttributes`：静态属性 `opKind`（bridge-op / scenario / export / restore）、`opTitle`（启动时由 App 以当前语言包文案定格传入——扩展不读语言包文件，免 app group）；`ContentState: Codable, Hashable`：`phase`（running / waiting / done / failed）、`stepLabel`、`done`、`total`（可空）、`updatedAt`。此文件**同时编译进主 App 与扩展**（两遍各自包含，类型同名同构为 ActivityKit 匹配口径） |
| `MomentLiveOps.swift`（主 App，新文件） | ActivityKit 封装：`start(kind:title:total:)` / `update(step:done:)`（内含节流）/ `end(result:)` / `activeId` 查询；`areActivitiesEnabled` 检测；`withBackgroundGrace`（beginBackgroundTask 组合，见 5.4）；全部 Diag 打点收口于此 |
| `MomentLiveOpsWidget.swift`（扩展，新目标） | `ActivityConfiguration`：锁屏呈现（标题 + 阶段 + 步名 + 进度条）+ 灵动岛 expanded / compact（leading 标题缩写、trailing 进度）/ minimal（图标点）。文案全部来自属性/状态（App 侧定格），扩展内零硬编码语言串 |
| 扩展构建 | build-app2.sh 新增一段：以同 COMMON 旗标单独编译扩展源（primary 遍 + WidgetKit/ActivityKit 链接）→ `MomentLiveOpsWidget.appex`（自有 Info.plist：CFBundleIdentifier = com.canopies.moment.liveops、NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension）→ adhoc 签 → 置入 `Moment.app/PlugIns/` 后再封 ipa。扩展 entitlements = 空集（无 app group 设计，见矩阵 #27） |

### 5.3 挂点（全部落在第二节长操作面实址）

| 场景 | 起 | 更 | 止 |
|---|---|---|---|
| 场景运行 uitest_run | 驱动核执行开始（MomentBridgeUITest.swift 运行生命周期入口，**非**两段提交发 token 时） | 每步证据落点 → stepLabel = 步名、done = 步序（节流见 5.5） | 全部终态码（ok / step_failed / run_timeout / aborted_* / restore_failed / hygiene_failed）→ end，phase = done/failed |
| 桥长操作（写前快照 + 执行 + 恢复） | 两段提交第二段执行开始（MomentBridgeTools.swift 分发执行点），仅限长操作集：快照创建、restore 类、硬删类 | 快照落盘完成 → stepLabel 推进一格 | 执行回执产生时 end |
| App 侧导出/导入 | `Library.exportZip()`（MomentApp.swift:1530）/ `importBackup`（:1654）/ 救援页 exportZipAction 入口 | FFI 调用前后两格 | 函数返回（成功/失败）时 end |

**短操作门槛**：仅上表命名集启动实况；其余桥工具（读类、短写类）一律不启——判据是「操作集成员资格」，不以运行时长猜测（避免阈值抖动）。桥操作会话本身（连接存续期）**不**单独起实况：连接是常驻态、非操作，起之即成 8 小时常驻噪声；会话的可见性由「会话内发生的长操作」承担。

### 5.4 与 beginBackgroundTask 的组合

- 挂点启动实况的同时不自动申请后台时间；仅当 App 在操作进行中收到 `didEnterBackground`（桥已有生命周期观察点，MomentBridge.swift:528）且存在 active 实况时，LiveOps 申请一次 beginBackgroundTask（名 `moment.liveops.grace`），过期回调里做最后一次状态更新（phase = waiting）并结束任务断言。
- 语义边界：该断言只保「进行中的操作跑完当前步/落盘」的系统宽限（量级为数十秒），不承诺更多（§六）。

### 5.5 频率节制

- 内容更新最小间隔 **5s**：步进类更新（stepLabel/done 变化）在间隔内合并，只保留最新一帧；**终态（end）与 phase 翻转不受节流**，立即发。
- `staleDate` = 启动 +10min：App 若被杀，残留实况自动转陈旧态、不长期冒充进行中；`relevanceScore` 50。
- 结束策略：成功 → dismissal `.after(now + 15s)`（用户瞥一眼结果即逝）；失败 → `.after(now + 10min)` 或用户手动划掉（失败需留痕给用户看）。
- FrequentUpdates 已声明（#19）但自节流远低于系统预算——声明是额度上限，节流是自律，两者不冲突。

### 5.6 Diag（入册备案）

域 `OPS live`（与现行 `OPS directives …`、`BRIDGE snapshot …` 的域口径一致）：

- `OPS live start kind=<kind> id=<activityId 前 8 位>`
- `OPS live update id=<…> step=<stepLabel> done=<n>/<total|->`（节流合并后实际发出的才记）
- `OPS live end id=<…> result=<ok|failed|aborted>`
- `OPS live skip reason=<disabled|unsupported-os|short-op>`
- `OPS live grace begin/end`（后台宽限断言起止）

---

## 六、效能边界（诚实口径，与稳定性批的互补关系）

**实况不是进程永生手段，以下逐条写死，不许在任何后续文案里升级表述：**

1. App 被系统挂起后进程冻结——实况**不能**让冻结进程继续跑、不能让桥的 WSS 在挂起期收发帧。挂起期不可达是平台事实，本批不改变它（与 fix_bridge_stability.md §八边界项同口径）。
2. 扩展进程不能联网，实况呈现的是「App 最后一次更新的状态」，不是实时状态；App 已死时呈现靠 staleDate 自行陈旧化。
3. beginBackgroundTask 宽限量级为数十秒，只够「当前步落盘」，不够「等用户回来」。
4. 远程更新实况（APNs 推送唤醒/更新）需要推送发送方基建，本期不存在（§八）。

**实况真正提供的三件东西（保活辅助的实义）：**

1. **可见存在感**：长操作（场景运行数分钟级、整库导出/恢复）在锁屏/灵动岛持续可见，用户不会因「切出去看一眼」而误判操作已死、更不会顺手杀 App——杀 App 是长操作失败的现实头号人为原因，实况直接压这一类。
2. **一键回前台的最短路径**：点实况即回 App 前台 → 立刻进入 fix_bridge_stability.md 的保证域（回前台 5s 探活定生死、半死硬重连、中继 4s 等设备窗、客户端只读重试）。**互补关系一句话：稳定性批保证「前台必连通」，实况负责「把用户和操作尽快带回前台」并让等待发生在看得见进度的界面上，而不是把保证域扩张到挂起期。**
3. **短暂切走的覆盖**：操作中切走数十秒（回消息、看通知）时，后台宽限 + 实况状态让操作大概率在用户回来前跑完当前阶段，且全程有状态可查；切走期间桥若断连，回前台仍走稳定性批的探活/重连链，实况状态与桥状态互不冒充（实况 phase 只报操作进度，不报连接态）。

---

## 七、B 段执行清单（门过后照单落码）

**硬门**：`git log` 见 0.9.57 bump 提交、组版改动已提交、工作树无组版未提交残留。动工前快照 `git diff` 映射在途批（届时 U4a / M3a 可能同期），逐 hunk 避让，完工复验他人 hunk 完好。

0. **工具建立（tree）**：装 ldid 或 zsign 到 `~/ios-native/bin`（版本钉住、来源记入技能 toolchain 备忘）；以现行 0.9.57 产物先行演练：嵌一个测试 entitlement → 回读核对 → 撤下，证明链路通。
1. **build-app2.sh 接线**：
   - heredoc Info.plist 增键：§3.1 声明行（#1 沿用、#3–#8 新增 zh-CN 值）、#18/#19、UIBackgroundModes（remote-notification / processing / fetch）、BGTaskSchedulerPermittedIdentifiers。**注意 verify [1] 版本三处一致**：只加键、不动版本行。
   - 生成 `Moment.entitlements`（仓内文件，内容仅 #26 aps-environment）并在链接后以第 0 步工具嵌入 + 回读断言（构建日志留一行实嵌集合）。
   - 生成五份 `.lproj/InfoPlist.strings`（§四全表 + CFBundleDisplayName 五语）拷入 .app。
   - 新文件入构建：`MomentLiveOps.swift` + `MomentLiveOpsAttributes.swift` 进全部 16 遍名单 + 各自 primary 遍（+2 遍）+ 链接行 .o；扩展段按 5.2 单独成段（编译 → 自有 plist → adhoc 签 → PlugIns/ 置入）。
2. **挂点落码**：按 5.3 表逐点接 MomentLiveOps（驱动核、桥分发执行点、export/import）；BGTask 注册（processing/fetch 两个 identifier，handler 做快照清理与 OPS 拉取的真实活，启动期注册、带 Diag 行）；通知授权开关入桥设置页（3.4 口径）。
3. **签名实证门（tree）**：构建后回读主 App 与扩展的实嵌 entitlements 逐条对矩阵 #26 打勾；任一条签不进或构建/签名因此失败 → 该条降级 parked-for-this-release 并从实嵌集撤下、回填本报告矩阵，**不带病出包**。plist 侧键以 verify [32] 静态断言 + tree 产物 PlistBuddy 式回读双核。
4. **verify 增补**：新组 **[32] 权限与实况**（组号顺延，[31] 为圆角组）：plist 声明键在位集（逐键）、.strings 五份在位 + 键集一致、entitlements 文件内容集 == 矩阵 B 级集、LiveOps 挂点计数（start/end 调用点数与 5.3 表一致）、扩展产物在位（PlugIns/ + 扩展 plist 标识符）、禁区项零出现（icloud-* / get-task-allow / UIBackgroundModes audio|location 字面零命中）。
5. **不提交、不 bump**（随下一组版）；冒烟随组版 tree 全量走（smoke_ios.sh 构建含扩展段后须全绿，verify 总数相应增加）。

---

## 八、待用户 Developer Program / 基建清单

| 项 | 缺什么 | 性质 |
|---|---|---|
| iCloud 容器（CloudKit / iCloud 文档） | 用户个人 Developer Program 的容器授权（现证书授权数为零） | **唯一 entitlement 类 parked**；与原生 iCloud 备份接入同批启用 |
| APNs 推送发送方 | 服务端发送方（可挂中继 Worker）+ 推送证书/密钥（随 Developer Program 签发） | 基建缺口，非 entitlement parked：aps-environment 本期按预期可签嵌入（#26）；发送方建成后才谈「挂起期远程唤醒/实况推送更新」，在此之前不许宣称该能力 |
| 实况推送更新（ActivityKit push token 通道） | 同上发送方 | 同上 |

---

## 九、真机终判点（B 段交付后）

1. **授权弹窗逐项**：定位（已有，回归确认文案五语随系统语言切换正确显示）；相机/相册/麦克风/Face ID/本地网络为惰性声明——**不应**在任何现行流程中弹出（若弹出即说明有未对账的 API 调用点，记缺陷）。
2. **实况起止与呈现**：跑一次 uitest_run 场景：锁屏出现实况（标题/步名/进度推进）、灵动岛 compact 呈现、点实况回 App 前台；结束 15s 后自动消失；失败场景实况留痕 10min 口径。
3. **长操作保活对比**：整库导出/恢复期间切后台 30s 再回——操作完成或进度连续（对照组：本批前同操作切后台的结局）；Diag `OPS live …` 行序完整（start → update* → end），桥侧 `BRIDGE session` 行与稳定性批判读法对读。
4. **重签安装**：全能签重签后安装成功、首次启动无 entitlement 相关崩溃；设置页桥配对、天气定位授权回归各过一遍。

---

## 附：本批文件预告（B 段新增/改动）

- 新增：`Moment.entitlements`、`MomentLiveOps.swift`、`MomentLiveOpsAttributes.swift`、`MomentLiveOpsWidget.swift`（+ 扩展 Info.plist 模板，置 icon-src 同级或 app 目录内）。
- 改动：`build-app2.sh`（plist 键、entitlements 嵌入、.strings 生成、两遍新增、扩展段）、`verify_ios.sh`（[32] 组）、`MomentBridgeUITest.swift` / `MomentBridgeTools.swift` / `MomentApp.swift`（挂点，各数行）、桥设置页（通知开关一行）。
- 本报告文件在 B 段完工时回填：实证结果列、实际落码行数、verify [32] 条目数。
