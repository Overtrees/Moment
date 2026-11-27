# 权限中心批：声明矩阵的运行时收口（impl_permission_center）

## 一、背景

权限 B 段（impl_entitlements_b.md）落了声明与嵌入：六项惰性用途串、实况两键、后台模式与 BGTask 标识符、aps-environment，五语 InfoPlist.strings 由构建生成。但弹窗口径为惰性，且多项声明根本没有对应的运行时请求代码路径——没有消费功能的声明永远不会触发系统弹窗。0.9.58 装机后用户实报：没有发现任何权限请求，点名本地网络、实况、日历等项。用户的「权限拉满」意图是这些能力真实可授、状态可见。

本批收口方式：在设置页新增「权限」页（设置族），逐项向系统真读当前授权状态，并按类给出动作——有请求 API 的在页内点按请求、无弹窗机制的如实呈现状态与去向、无授权面的已声明能力如实标注。不新造任何消费功能；既有惰性请求点（天气定位链、桥设置页通知开关、PHPicker 选择器）保持不动。

## 二、31 项三态盘点

底表 = impl_ios_entitlements_liveops.md §三声明矩阵。三态为本批落码前实测：声明（plist/entitlements 是否在）/ 请求路径（运行时是否有代码能触发系统授权）/ 消费功能（是否有功能真实使用）。「本批后」列为本批处置。

| # | 项 | 声明 | 请求路径（批前） | 消费功能 | 本批后 |
|---|---|---|---|---|---|
| 1 | 定位 WhenInUse | 在 | 有：天气链 CLLocationManager.requestWhenInUseAuthorization（仅天气触发时） | 有：天气 | 进权限页：状态真读 + 未定时可请求（与天气链同一授权，互不重复触发） |
| 2 | 定位 Always | 不声明（A 矩阵裁定：无后台定位功能面） | — | 无 | 不入页，维持裁定 |
| 3 | 相机 | 在 | 无（附件走选择器，无 AVCaptureDevice 调用） | 无 | 进页 (a) 类：AVCaptureDevice 状态真读 + 请求 |
| 4 | 相册读取 | 在 | 无（PHPicker 进程外，不需要授权；全仓无 PHPhotoLibrary 直读） | 无 | 进页 (a) 类：PHPhotoLibrary readWrite 状态真读 + 请求 |
| 5 | 相册保存 | 在 | 无 | 无 | 进页 (a) 类：addOnly 状态真读 + 请求 |
| 6 | 麦克风 | 在 | 无（全仓无录音面） | 无 | 进页 (a) 类：AVAudioApplication/AVAudioSession 状态真读 + 请求 |
| 7 | Face ID | 在 | 无（LAContext 未用） | 无 | 进页 (a) 类：canEvaluatePolicy 读可用性；请求 = evaluatePolicy 触发系统同意（Face ID 无独立请求 API，见 §五） |
| 8 | 本地网络 | 在 | 无 | 无 | 进页 (b) 类：NWBrowser 浏览自有服务触发弹窗，探针结果如实呈现（见 §五） |
| 9 | NSBonjourServices | 不声明（A 矩阵裁定：无服务类型可填） | — | 无 | **本批扩展**：加 `_moment._tcp`（自有服务名），使 #8 的浏览探针合法触发；备案见 §三 |
| 10 | 蓝牙 | 不声明（无 BLE 功能面） | — | 无 | 不入页，维持裁定 |
| 11 | 运动 | 不声明（无 CoreMotion 功能面） | — | 无 | 不入页，维持裁定 |
| 12 | 日历 / 提醒四键 | 不声明（A 矩阵裁定：无同步功能面） | 无 | 无 | **本批扩展**：补四键声明 + 五语串，EventKit 请求路径进页；无消费功能不变，行注如实标注；备案见 §三 |
| 13 | 通讯录 | 不声明（无联系人功能面） | — | 无 | 不入页，维持裁定 |
| 14 | 健康 | 不声明（无健康功能面） | — | 无 | 不入页，维持裁定 |
| 15 | 语音识别 | 不声明（无识别功能面） | — | 无 | 不入页，维持裁定 |
| 16 | Apple Music | 不声明（音乐卡走外链解析） | — | 无 | 不入页，维持裁定 |
| 17 | HomeKit / NFC / Siri | 不声明（无功能面） | — | 无 | 不入页，维持裁定 |
| 18 | 实况 SupportsLiveActivities | 在 | 无弹窗机制（iOS 无实况授权弹窗） | 有：桥长操作/场景实况（LiveOps 单栈） | 进页 (c) 类：areActivitiesEnabled 真读 + 「去系统设置」深链 |
| 19 | 实况频繁更新 | 在 | 同 #18 | 有：同 #18 | 与 #18 合一行呈现 |
| 20 | UIBackgroundModes remote-notification | 在 | 通知授权请求在桥设置页开关（MomentLiveOps.setNotifyEnabled → requestAuthorization） | 部分：通知授权有请求面；推送发送方未建 | 与 #26 合并为权限页「远程推送」行：(d) 类已声明标注；通知授权本身单列 #通知行（见下） |
| 21 | UIBackgroundModes processing | 在 | 无用户授权面（系统调度） | 有：BGProcessingTask 已注册（快照清理 + OPS 拉取，MomentLiveOps 注册/提交在位） | 进页 (d) 类：与 #22/#23 合一行「后台任务」，标已声明·系统调度 |
| 22 | BGTaskSchedulerPermittedIdentifiers | 在 | 同 #21 | 有：同 #21 | 同 #21 行 |
| 23 | UIBackgroundModes fetch | 在 | 同 #21 | 有：BGAppRefreshTask 已注册（OPS 周期拉取） | 同 #21 行 |
| 24 | UIBackgroundModes audio | 不声明（A 矩阵裁定：无后台音频用途，声明即虚假声明） | — | 无 | 不入页，维持裁定 |
| 25 | 其余后台模式 | 不声明（逐项无功能面） | — | 无 | 不入页，维持裁定 |
| 26 | aps-environment | 在（已嵌入实证） | 通知授权同 #20；APNs 注册/发送方未建 | 无发送面 | 与 #20 合一行 (d) 类：行注写明发送通道尚未建立 |
| 27 | application-groups | 不声明（实况设计不依赖共享容器） | — | 无 | 不入页，维持裁定 |
| 28 | keychain-access-groups | 不声明（默认组工作正常） | — | 无 | 不入页，维持裁定 |
| 29 | get-task-allow | 禁入（调试专用） | — | — | 不入页，维持禁入 |
| 30 | iCloud 四键 | PARKED（全矩阵唯一 parked：等用户个人 Developer 账号） | — | 无 | 不入页，维持 parked |
| 31 | 关联域 / wifi-info / HealthKit / NFC / Siri entitlements | 不声明（无功能面） | — | 无 | 不入页，维持裁定 |

权限页行集（13 行）：「需要授权」组 11 行——通知（#20 的授权面单列：UN 授权状态真读 + 请求，与桥设置页开关同一授权、页面请求不改桥 pref）、定位（#1）、相机（#3）、相册读取（#4）、相册保存（#5）、麦克风（#6）、Face ID（#7）、本地网络（#8+#9）、日历（#12）、提醒事项（#12）、实况（#18+#19）；「已声明的能力」组 2 行——后台任务（#21+#22+#23）、远程推送（#20+#26）。

## 三、两处矩阵扩展备案

1. **#9 NSBonjourServices**：A 矩阵原裁不声明，理由是无服务类型可填。本批 (b) 类探针需要一个自有服务类型才能合法触发本地网络弹窗，故声明 `_moment._tcp`（本 App 自有命名，非第三方服务）。这是为权限请求面服务的声明，不是 LAN 功能落码；无任何浏览/发布消费方（探针除外）。
2. **#12 日历/提醒**：A 矩阵原裁不声明，理由是无系统日历/提醒同步功能面，且当时的任务口径明示不声明。本批用户在权限中心指令中点名日历，要求声明项在权限页可见可授。故补 NSCalendarsUsageDescription / NSCalendarsFullAccessUsageDescription / NSRemindersUsageDescription / NSRemindersFullAccessUsageDescription 四键（plist 主值 zh-CN + 五语 .strings）。边界不变：不落任何日历/提醒消费功能，权限页行注如实写「不读写你的日历/提醒事项」。

## 四、落码面

- **新文件 `rust/apps/ios/app/MomentPermissions.swift`**（独立成文件，不入上帝文件）：
  - `PermKind`（13 值，grant 11 + declared 2；每值含 Diag token 与文案键派生）、`PermStatus`（14 值，呈现键与 Diag token 同源派生）。
  - `PermCenter`（NSObject + ObservableObject + CLLocationManagerDelegate）：全 App 唯一权限请求面。`refreshOne` 为每项唯一状态读点（通知走 getNotificationSettings 异步读面单列于 refreshAll）；`request(_:)` 为唯一请求分发；状态写入经 `apply` 主线程收口。定位请求以 pendingLocRequest 旗守卫，委托回调里状态脱离未定才记结果行（进页读状态不误记为请求结果）。
  - 本地网络探针：NWBrowser 浏览 `_moment._tcp`；.ready 或收到浏览结果 = 浏览可用；DNS 策略拒绝错误码（kDNSServiceErr_PolicyDenied）= 已拒绝；8 秒超时或其余失败 = 未能确定；探针进行中禁重入，终态统一 cancel 并记 Diag。
  - `PermissionsView`：ChromeView + settingsContentFrame + SectionHeader 两组 + glassCard 行卡，行形态与 SetRow 家族同令牌（标题 .callout semibold、行注 .caption glassLabel、尾部状态词 + 条件动作钮）。进页记 `SET permissions enter` 并全量重读；回前台（scenePhase .active）重读。
  - Diag：每项请求收口记一行 `SET perm request kind=<token> result=<status-token>`（三处同式：通用收口/定位委托/探针收口），不记任何敏感值。
- **MomentApp.swift 三处小 hunk**：SettingsView.Sub 加 `permissions`（含 id 映射）；数据组卡桥行后加权限行（SetRow，标题 perm.title、meta perm.settings_sub）；navigationDestination switch 加 `case .permissions: PermissionsView()`。
- **build-app2.sh**：新文件进全部编译遍次级输入名单 + 自有 primary 遍（permissions.o）+ 链接行；plist heredoc 加日历/提醒四键 + NSBonjourServices 数组；write_infoplist_strings 扩 4 条 printf（参数 $10–$13），五个 locale 调用各补 4 参（旧/全访问同文）。
- **语言包 +48 键（381 → 429）**：perm.* 五包齐——页题/入口行 meta/说明/两组节题/请求/去系统设置（7）+ 状态词 14 + Face ID 评估理由 1 + item_/note_ ×13（26）。无功能使用的行注统一以「已声明 · 暂无功能使用」开头并给一句原因（选图走系统选择器、暂无录音功能等），不假装集成。
- **verify_ios.sh**：[9] 键数期望 381 → 429（续账注释补本批一行）；尾部新增 [44] 组 PC44-1..8（构建接线/状态真读 API 逐项恰一/请求 API 与权限项对应/深链仅限实况一类/Diag 单点/设置接线/plist 新声明与探针常量/perm 键五包齐 + 新文件引用键齐全）。

## 五、口径与折入

- **状态折入**：相册 `.limited`（部分照片授权）折入「已授权」——状态词只表已获授权，不宣称全库访问；通知 `.provisional`/`.ephemeral` 同折入已授权。EventKit iOS 17 `.writeOnly` 单列「仅写入」。
- **Face ID**：无独立授权请求 API。状态 = canEvaluatePolicy 读面（可用/不可用；不可用含未录入面容与未定同意，行注已写明）；「请求」钮仅在不可用时出现，动作 = evaluatePolicy 触发系统同意评估，评估理由走语言包键 perm.faceid_reason。本批不落应用锁，行注如实标注。
- **本地网络**：iOS 无状态查询 API，页面状态是探针结论而非系统状态接口，行注明示来源（Bonjour 浏览探针）。探针钮恒可重探（进行中除外）。
- **请求钮显隐**：(a) 类仅未定状态出钮——已授权不需再请求、已拒绝系统不会再弹（点按无意义），均不出钮，满足「已授权项点按无副作用」；(c) 实况恒出「去系统设置」（其开关只在系统设置内）；(d) 类无钮。
- **状态色**：已授权/已开启/可用/浏览可用 = 强调色；已拒绝 = 警告色；余为次级文字色。全部走既有令牌，无裸值；字号只用语义字体。
- **不自动索取**：进页只读状态，绝不自动发起任何请求（与 A 报告 §3.4 口径一致）；请求只发生在用户点按。
- **既有惰性点不动**：天气定位链、桥设置页通知开关、PHPicker 路径零改动；权限页与它们共享同一系统授权，状态互通、无重复弹窗风险（系统对已定状态不重复弹窗）。

## 六、自检结果（本机）

- verify [44] 八条全绿；[9] 源级检查全绿（五语键集合一致、键数 429、Swift 引用键齐全——含新文件补扫 PC44-8）。全量 verify 仅余 2 红，均为产物陈旧类（ipa 早于源码、产物语言包与新源 md5 不一致），多批在途同型基线，下一组版重建后自解。
- 类型检查（本机 swift-frontend，iPhoneOS 27.2 SDK）：MomentPermissions.swift primary 遍零错误；MomentApp.swift primary 遍零错误（需将在途批的 MomentFontFactory.swift 一并入列表——该文件已在现行构建名单内）。
  - 类型检查实证修正一处：`AVAudioApplication.requestRecordPermission` 在本 SDK 为类方法而非实例方法，初稿按实例调用被编译抓出，已改类调用；`recordPermission` 状态读面仍为 `.shared` 实例属性。
  - 本机资源受限：App primary 遍首跑曾 SIGBUS 中断并伴级联幻影错误（均为未触碰的既有代码行），重跑后结论如上；全量构建与冒烟按既定分工在 tree 于组版时执行。
- 构建脚本：bash -n 通过；write_infoplist_strings 干跑实证五份 .strings 各 12 条（显示名 + 11 用途串）键值正确。
- 同树避让：开工全量 diff 快照在案；本批改动全为锚点外科插入（MomentApp 三处、build 名单/新遍/plist/strings、verify [9] 一处 + 尾部新组、语言包尾部追加 48 键各一行逗号变更），完工逐文件复核删除行集合与预期一致，他批 hunk 零丢失。

## 七、逐项真机终判点（下一组版装机后）

前置：全新安装或在系统设置中重置各权限至未定状态；进设置页 → 权限页，先核每行状态词与系统实际一致，再逐项点「请求」：

1. **通知**：应弹系统通知授权弹窗；允许后行状态变「已授权」；与桥设置页通知开关状态互通（同一授权）。
2. **定位**：应弹定位授权弹窗（使用 App 期间允许）；允许后变「已授权」；天气页取位不受影响。
3. **相机**：应弹相机授权弹窗；允许后变「已授权」。
4. **相册（读取）**：应弹相册授权弹窗（含「选择照片/允许全部」系统选项）；选任一后变「已授权」（.limited 折入口径）。
5. **相册（保存）**：应弹保存授权弹窗；允许后变「已授权」。
6. **麦克风**：应弹麦克风授权弹窗；允许后变「已授权」。
7. **Face ID**：状态先显「可用」或「不可用」；不可用时点请求应起 Face ID 系统评估界面；行注「暂无应用锁」属实。
8. **本地网络**：点请求应弹本地网络授权弹窗（提及在局域网内发现设备）；允许后探针应回「浏览可用」，拒绝应回「已拒绝」；无弹窗直接出结果或恒「检测中」为异常。
9. **日历**：应弹日历全访问授权弹窗（iOS 17+ 文案）；允许后变「已授权」。
10. **提醒事项**：应弹提醒事项全访问授权弹窗；允许后变「已授权」。
11. **实况**：无弹窗（预期行为）；状态词与「设置 · 此刻 · 实况」系统开关一致；点「去系统设置」应跳到本 App 系统设置页。
12. **后台任务 / 远程推送**：两行恒显「已声明」且无请求钮（预期行为）；远程推送行注「发送通道尚未建立」属实。
13. **通用**：已授权行无请求钮、点按无任何弹窗；杀进程重进后状态与系统设置内一致；回前台后状态自动刷新；Diag 应见每项请求各一行 `SET perm request kind=… result=…` 与进页行 `SET permissions enter`。

—— 本批不提交、不 bump，随下一组版。

## 八、文案微调：无功能行注收敛为单句（用户两段裁定，2026-11-27 19:22 / 19:23）

**裁定沿革**：原落码行注为「已声明 · 暂无功能使用（原因……）」。19:22 第一裁定：只用「暂无功能使用」、不加「已声明」前缀（原因部分保留）。19:23 追加裁定覆盖第一裁定的保留部分：「暂无功能使用」本身就是原因——行注只写这一句，后面不再附任何原因说明，原行注的原因部分整段删除。终态以 19:23 裁定为准。

**改动键清单（9 键 × 五包 = 45 处，全部只改值、不动键）**：perm.note_camera、perm.note_photo_read、perm.note_photo_add、perm.note_microphone、perm.note_faceid、perm.note_local_network、perm.note_calendar、perm.note_reminders、perm.note_push_env。终态值（各语等义短句、独立成文）：zh-CN「暂无功能使用」/ zh-TW「暫無功能使用」/ en-US "No feature uses it yet" / ja-JP「まだ使う機能はありません」/ ko-KR「아직 사용하는 기능이 없습니다」。随原因整段删除的附带说明在此留痕：Face ID 的「不可用也可能是设备未录入面容」、本地网络的探针来源说明、日历/提醒的「不读写」说明，均按裁定一并删除（§五、§七中涉及这些行注原文的表述以本节为准；§七.12 的远程推送行注口径同步改为仅「暂无功能使用」）。

**(d) 类处理结论**：
- 远程推送（perm.note_push_env）：与本族同一构造——同为独立 note 键、同带「已声明 ·」前缀与「暂无功能使用」语，拆不开，按同一口径一并处理（已含在上述 9 键内）。
- 后台任务（perm.note_background）：不属本族，未动——该项有真实消费功能（BGProcessingTask / BGAppRefreshTask 已注册），其行注是「已声明，系统调度：……」的调度说明、不含「暂无功能使用」语。
- (d) 两行尾部的状态词「已声明」（perm.status_declared）与组节题「已声明的能力」（perm.section_declared）属状态/分组标签，不在本批范围，未动。

**其余口径**：Swift 侧行注全经 noteKey 查语言包、无拼接/回退字面，本批未动任何 Swift 文件。断言面：[44] 组无条目锚定行注文本（PC44-8 只锁 perm.* 48 键五包齐 + 引用键齐全），故无改锚对象。键数复核：五包各 429 键、键集全等（脚本实测），与 [9] 续账一致。

**自跑结果**：verify 全量 422 ✓。[9] 组源级全绿（键数 429、键集一致、引用键齐全），仅产物语言包陈旧一红（组版重建自解，既有基线）。[44] 组 7/8 绿（PC44-8 在内）；PC44-5 一红与本批无关——DT 批在途把 MomentPermissions.swift 字体改走其缩放变量（f12/f16 共 5 处 `.system(size:`），触发该条的字面计数，归 DT 批收口；同轮 J20-12、DT36-4 两红同为 DT 批在途面，ipa 陈旧为既有基线。本节改动不提交、不 bump，随下一组版。
