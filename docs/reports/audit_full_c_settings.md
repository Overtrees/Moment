# 全面审计 · C 片：设置族与系统页（只读审计）

> 状态：**只读审计完成，未落任何代码、未跑构建、未动 git**。
> 基线：仓库 `~/workspace/Moment`，HEAD `b682d02`。
> 工作树注记：审计时点工作树有他线在途未提交 diff（状态栏采样线：
> `MomentApp.swift`/`MomentEditorTransition.swift`/`build-app2.sh`/
> `verify_ios.sh` 的状态栏 hunk + 新增 `MomentStatusBar*.swift`）——
> 按任务排除面**不审、不动**；本报告涉案行号为审计时点工作树行号，
> 与 HEAD 已提交内容的差异仅在该线 hunk 内，设置族段落经逐 hunk
> 核对不在其改动范围内。
> 范围：设置主页全量、备份导入/导出、语言与 i18n 设置面、权限中心、
> 天气设置、桥设置页、外观/文字大小、关于/版本、诊断导出入口、
> 设置内手动救援入口、设置族宽屏收窄。
> 排除（按任务）：小组件 appex、状态栏采样、APNs 发送凭据/iCloud
> 容器本体（等用户个人 Developer 账号，只登记边界，见 §13）。
> 真源序：Web 源码（`rust/apps/web/src/settings.rs` 等 + 五语包）
> 为第一真源；用户裁定（`~/AGENTS.md`、`~/MEMORY.md`、各 impl/audit
> 报告定案）为第二真源。
> 证据分级：**proven**（源码/语言包/脚本实测）/ **inferred**（代码
> 可读但结论依赖运行时或系统行为）/ **unknown**（代码不可判，附
> 取证法）。运行时项一律不升级表述，终判归真机 + Diag。

---

## 1. 总判

设置族主体健康：0.9.58–0.9.61 各批（权限中心、备份 BK-1..3、桥呈现
小批、配对二维码、天气 W-T1、DT 真跟随、i18n 收尾 T-1..T-4、救援
完整性批）在本轮逐项回源复核**全部在位、无回潮**（§12 回归抽查
六项全过或注明边界）。六项必查回归中五项全过；一项部分过——宽屏
720 收窄的在位面为 7 页 + 救援页，诊断页与日志视窗页不在收敛面
（其中诊断页的排除是 verify 注释明示的既定口径，但与「设置族」
全称不符，登记 C-02 待裁）。

新发现 3 项（C-01..C-03，均 P3）：导入链 `lib == nil` 可选链假成功
（机制 proven、可达性 inferred）、诊断两页未入 720 收窄（proven、
意图 unknown）、权限文件注释与行注单句口径漂移（proven、仅文档面）。
旧账 5 项单列（§14），其中 I4 边界两项为最大未落面（编辑器换键与
EditorView 语言观察），均已在册归 I4，非本片新欠。

---

## 2. 设置主页全量盘点（vs Web）

原生 `SettingsView`（MomentApp.swift:20344 起，`Sub` 路由枚举
:20372-20385 共 7 子页：backup/gestures/language/diag/bridge/
weather/permissions）。Web 对照 `settings.rs:219-372`。

| 组 | 原生行（顺序） | Web 对应 | 判读 |
|---|---|---|---|
| 外观 | 文字大小行：副文案 `settings.font_system_note` + 右值「跟随系统」，无分段钮（:20462-20484） | 分段钮 小/中/大 + 「跟随浏览器缩放」（settings.rs:283-303） | **定案偏离**（Dynamic Type 改判，B1 定案；实效面见 §9）proven |
| 数据 | 备份行：meta = 新鲜度主文案、警示后缀仅后缀段着 warning 色、空格续接（:20486-20503；freshnessMain/freshnessWarn :20414-20441） | 同组同口径（settings.rs:306-322） | 达标 proven（audit_detail B2/B3/B4 已修形态在位） |
| 数据 | 语言行：meta = `LangStore.nativeName(langStore.code)` 实时解析（:20505-20511） | meta = 当前语言本名（settings.rs:324-334） | 达标 proven |
| 数据 | 手势行：meta `gestures.settings_sub`（:20513-20518） | 同（settings.rs:336-346） | 达标 proven |
| 数据 | 诊断行：无 meta（:20520-20522） | 同（settings.rs:347-354） | 达标 proven |
| 数据 | **桥行**：meta = `Lang.t(bridge.linkStateKey)` 与桥设置页同源（:20526-20531） | Web 无（桥为原生 M1 面） | 原生独有·定案在位 proven |
| 数据 | **权限行**：`perm.title` / `perm.settings_sub`（:20538-20543） | Web 无 | 原生独有·定案在位 proven（§5） |
| 天气 | 组头与入口行同用 `settings.weather`、meta = `settings.weather_sub` 固定说明键（:20561-20568） | Web 无此组（key 构建注入、无设置面） | **定案偏离**（B8：构建注入 + 设置页自填）proven（§6） |
| 关于 | 版本行：值字面量 `Text("0.9.61")`、f14（:20545-20552 区，实测行 :20550） | 版本行值 14px（settings.rs:358-361，两端版本线各自独立不计差） | 达标（值一致性见 §10） |
| 关于 | 联系行：`overcanopies@gmail.com`、f13_6 ≈ Web 0.85rem（同上区） | 同（settings.rs:363-367） | 达标 proven |
| 页脚 | `settings.footer` 12px italic 次级居中 opacity 0.8（:20572-20578） | 同（settings.rs:368） | 达标 proven |

组距账在位：外观卡底→数据组头 40、数据卡→天气组头 32、天气卡→
关于组头 32（注释逐项留痕 S1 口径，:20486/:20545/:20561 区）。
主题行两端皆无（均跟随系统色），一致。设置页进入打点
`SET settings enter` 在位（:20616-20620 区 onAppear）。
子页路由为单 `navigationDestination` + `Sub` 枚举分发，无第二套
状态源（桥行一致性 audit_home §4.9 口径复核成立）。

---

## 3. 备份导入/导出（BackupView :20625 起）

### 3.1 格式与事务（core 层）

- 包格式 = Rust 原生格式（D1 定案）：`memos.json` + `manifest.json`
  + `attachments/<id>` 原始字节；上限沿原版校验（包 50MiB / 条目
  3000 / 单文件 50MiB / 解压总量 200MiB，超限拒绝）
  （`rust/crates/core/src/backup_zip.rs:1-16`）。proven
- 导入 = validate-then-swap：`read_backup_zip` 全包解析校验通过才
  落库；已校验包的单事务全量替换（清库→逐篇插入→附件，
  backup_zip.rs:211-293 区注释与实现）；re-import 替换不追加。
  旧格式走独立一次性迁移通道 `read_backup_zip_migrated`（D2），
  主通道对旧形态解析失败、零兼容层残留于主路径。proven
- 桥快照链守恒未触：写前必拍、直调 FFI `exportBackup`、不污染
  备份新鲜度（impl_backup_tail §4 复核口径，本轮未见改动面）。proven

### 3.2 原生链（Library / BackupView）

- 导出：确认底表 → `exportZip()`（:1725-1780）：`lib == nil` 显式
  守卫（旧可选链假成功已于批 A 根治，注释在位）、文件名
  `此刻备份_<UTC 日期>.zip`、成功记 `lastExportTs` + recordOp、
  失败 `lastExportError` 回带原因、toast 走 `status.export_failed
  {e}`。proven
- 导入：fileImporter(.zip) → `stageImport`（校验、失败 toast
  `status.import_invalid` 且数据未动）→ 确认底表 →
  `commitStagedImport() -> ImportOutcome`（:1870-1930 区）。proven
- **BK-1..3（0.9.59）口径在位**（回归③，详 §12）：ImportOutcome
  契约（成败只由 importBackup 本体定、parseStats 失败记
  `IMPORT stats unparsed` warn 不反转成败、reload 移出成败域且
  失败走新键 `notice.import_reload_failed`）；`stagedStats` 全仓
  grep **零命中**（本轮实测，含 verify/ Web 面）；导出 toast 后移
  ShareSheet `onComplete`（completed 才弹 `status.shared`、取消
  不弹、error 记 Diag warn，BackupView .sheet :20894 区）。
  verify [40] 组 BK40-1..4 结构锁在位（verify_ios.sh:4677 起）。proven
- 确认底表定案形态在位：自绘底表、透明遮罩（Color.clear 点按
  取消）、卡 maxWidth 600、radius panel、标题 18/700 居中、消息
  13/1.45 居中、按钮纵列高 min 44、主钮 accent 0.86；进场 =
  `.transition(.opacity)` + spring(response 0.25, damping 0.86)
  ——250ms 弹簧**仅淡入、无位移**（backupConfirmSheet
  :20932 起、挂载点 :20857）。proven（源码形态；进场观感归真机）
- toast 形态：全宽条（左右 16、底 safe+16、radius panel overlay
  档、文案 14/500、成功 success 绿 / 失败 danger、时长 3s/6s），
  进场 `.move(edge:.bottom)+opacity` 220ms 族动画在根 `.animation`
  （spring 0.28）——与定案「备份 toast 220ms 上滑保留」一致。proven
- 反馈口径其余：导入成功有计数走 `status.imported {n}/{m}`、
  计数未知复用 `backup.hist_restored`（零新增键裁定）；最近操作
  6 条、opMessage 按 kind/ok 映射 Web 记录消息（C10 口径）、
  类型徽章 9px/700 大写。proven
- iCloud/Google 面：全仓 Swift + 语言包 grep `google` **零命中**；
  无单独 iCloud 行，仅 `backup.icloud_note` 一行说明（分享面板
  「存储到文件」/文件选择器路径，:20786）——与定案逐字合。proven
- 超期横幅：独立横幅卡（warning 边 0.5、radius panelHero）在位
  （C3 已修形态）。proven

### 3.3 新发现 C-01（见 §13）

`stageImport`/`commitStagedImport` 的 `lib == nil` 可选链假成功，
与 exportZip 已根治的同型旧路并存——详 §13。

---

## 4. 语言设置与 i18n 设置面

### 4.1 已落面（I1–I3 + 收尾批）

- LangStore（:4933 起）：五语包 bundle 内置（build-app2.sh 构建
  拷贝 Web 五包入 `.app/lang/`，单一真源）、回退链 当前包→zh-CN→
  键名（lookup :5040 区）、`{name}` 占位符 tf 同 Web 语义、
  `LANG init/applied/follow-system` 打点单点。proven
- 语言页（LanguageView :21541 起）：首行「跟随系统」（副文案 =
  当前解析语言本名、生效时状态「使用中」）+ 五语独立卡（radius
  口径、卡间隔 6、无分隔线）、状态纯文字 12px（当前 accent/700、
  余次级标「内置」）、点行即切换（E1–E4 按立项改判关单形态）。proven
- 五包现状：**各 429 键、键集合互等**（本轮脚本逐包实测）；
  verify [9] 组含深检移植（占位符齐平 + 僵尸键反向扫描，共源
  `scripts/i18n_deep_check.py`，impl_gate_port_i18n）。proven
- 设置族 + 首页换键完成（I2/I3）；收尾批 T-1..T-4 已落：图片页
  兜底/失败文案入包、ImagePageView 补 LangStore 观察、
  followSystem 监听 `NSLocale.currentLocaleDidChangeNotification`
  运行中重解析（LangStore init :4983-4998，回调仅 followSystem
  在位时沿 applyFollowSystem 单点）。proven
  → audit_home §4.5 两差（SET-15）中**图片页半边与系统语言变更
  半边已销账**；编辑器半边仍开（§14 旧账）。

### 4.2 回归⑥：语言默认口径

LangStore.init（:4955-4980）逐字合裁定（plan_native_i18n §7）：

- 有偏好：`system` → 跟随系统解析；具体码 → 手动。
- 无偏好 + 存量（`hasExistingState()`：moment.db 已存在，或
  launchInProgress/launchStep/lastExportTs/lastEditTs/diagAutodel/
  diagLevel 任一哨兵键在位，:5061-5085）→ 解析 zh-CN 并**落盘
  `"zh-CN"`、判据只跑一次**（防全新装第二启被自家已建库误判）。
- 无偏好 + 全新 → 跟随系统并落盘 `"system"`；系统映射表
  （zh-Hant/TW/HK/MO→zh-TW、en→en-US、ja→ja-JP、ko→ko-KR、
  其余→zh-CN，systemCode :5046-5060）与立项 §3 一致。
- LangStore 先于 Library 声明的构造序在位（:21881-21882 注释 +
  根声明序），判据赶在开库建 db 之前。proven（源码判据；
  全新装/覆盖装的真机行为归发版抽样，unknown 运行时面见 §15）

### 4.3 I4 边界（待办，非本片缺陷）

I4 = 编辑器全域换键，未落：EditorView（:10686）属性区**无
langStore 声明**（桥远程切语言时编辑器文案停旧语言，SET-15
编辑器半边）；SlashCmd 定义（:5817-5870 区）标题/副标题仍
zh-CN 字面量（EDT-59/M-07，非中文语言下斜杠菜单恒中文）。
两项均已在册归 I4（impl_i18n_tail §3 明示只登记不落码），
本片不重开、列旧账（§14）。

---

## 5. 权限中心（MomentPermissions.swift，660 行）

### 5.1 结构与真读/请求面

- 行集 13 行与 impl_permission_center §二一致：grant 组 11
  （通知/定位/相机/相册读/相册存/麦克风/Face ID/本地网络/日历/
  提醒/实况）+ declared 组 2（后台任务/远程推送）
  （PermKind :42-60、grantKinds/declaredKinds 分组）。proven
- 状态真读单点 `refreshOne`（:170-209）：逐项走各框架正道读面
  （CLLocationManager.authorizationStatus、AVCaptureDevice、
  PHPhotoLibrary readWrite/addOnly、AVAudioApplication/
  AVAudioSession、LAContext.canEvaluatePolicy、EKEventStore、
  ActivityAuthorizationInfo.areActivitiesEnabled、UN 异步读面）；
  后台/推送恒 `.declared`。折入口径在位：相册 `.limited`→granted、
  通知 `.provisional/.ephemeral`→granted、EventKit `.writeOnly`
  单列。proven
- 请求分发单点 `request(_:)`（:313-406）：点按才请求、进页只
  `refreshAll` 不自动索取；请求钮仅未定状态出（Face ID 以
  unavailable 为条件、本地网络恒可重探、实况恒「去系统设置」
  深链且深链仅此一类）；定位以 pendingLocRequest 旗守卫委托
  回调记账。Diag 收口三处同式 `SET perm request kind=… result=…`，
  进页行 `SET permissions enter`。proven
- 本地网络探针：NWBrowser 浏览 `_moment._tcp`、PolicyDenied
  (-65570) 判已拒绝、8s 超时判未能确定、进行中禁重入、终态
  cancel（:440-510 区）。proven（机制）；弹窗与探针结果的真机
  行为 unknown（§15，impl_permission_center §七 13 点终判清单
  仍待装机执行）。

### 5.2 回归①：行注文案逐字核（五包实测）

zh-CN 全 13 行注（`rust/apps/web/lang/zh-CN.json:406-430`）：

| 行 | 行注 | 口径判读 |
|---|---|---|
| 通知 | 桥接长操作完成时提醒（与桥设置页的通知开关是同一授权） | 有功能行，功能注 ✓ |
| 定位 | 天气正在使用：显示你所在城市的天气 | 有功能行 ✓ |
| 相机 | 暂无功能使用 | 单句 ✓ |
| 相册（读取） | 暂无功能使用 | 单句 ✓（PHPicker 进程外不需授权，无消费面属实） |
| 相册（保存） | 暂无功能使用 | 单句 ✓ |
| 麦克风 | 暂无功能使用 | 单句 ✓ |
| Face ID | 暂无功能使用 | 单句 ✓ |
| 本地网络 | 暂无功能使用 | 单句 ✓ |
| 日历 | 暂无功能使用 | 单句 ✓ |
| 提醒事项 | 暂无功能使用 | 单句 ✓ |
| 实况 | 桥接长操作与场景运行正在使用；在「设置 · 此刻 · 实况」中开关 | 有功能行 ✓（未误挂单句注） |
| 后台任务 | 已声明，系统调度：热修复指令拉取与附件快照清理 | 有真实消费（BGTask 已注册），非本族、未动属实 ✓ |
| 远程推送 | 暂无功能使用 | 单句 ✓ |

结论：**9 个无功能行注五包均为独立单句**（zh-CN「暂无功能使用」/
zh-TW「暫無功能使用」/en-US "No feature uses it yet"/ja-JP
「まだ使う機能はありません」/ko-KR「아직 사용하는 기능이 없습니다」，
本轮逐包实测），无「已声明 ·」前缀、无原因附句；3 个有功能行
（通知/定位/实况）与后台任务行均未误挂此注。Swift 侧行注全经
`noteKey` 查包、无拼接字面（MomentPermissions.swift:80）。
与用户 2026-11-27 19:22/19:23 两段裁定终态逐字合。proven
注：页首 `perm.intro` 含「暂未被任何功能使用的授权会如实标注」
一句——属页级说明、非行注，不在裁定射程，登记备考不作差。

### 5.3 边界登记（不作缺陷）

推送行呈现止于「已声明 + 暂无功能使用」：缺的是 APNs **发送
凭据**（.p8/推送证书，须 App ID 所属团队开发者账号签发），
与 iCloud 容器同道门、等用户个人 Developer 账号（MEMORY 定案）。
本地网络探针的呈现是探针结论而非系统状态接口——此口径现只存
于代码注释与 impl 报告，行注按裁定不附说明（见 C-03）。

---

## 6. 天气设置（WeatherView :21227 起）

- 双 key 链 proven：优先级 自填 > bundle 注入 > 空
  （`WeatherService.key()/keySource()` :17615-17645，bundleKeys
  进程级单次缓存）；构建注入在 build-app2.sh:1029-1037（源
  `~/ios-native/weather-keys.json` 仓外不入 git、存在才打包、
  缺失则整链按无 key 静默不发请求，与 Web key 门同）。
- 拉取链：定位/IP 兜底取坐标 → 和风 fetchQWeather 任一环失败
  才落 fetchCaiyun、彩云 key 空跳过、双败记
  `WEATHER provider=fail`（:17737-17765 区）。城市呈现序
  CLGeocoder > 和风 geo > ipCity（英转中表）为定案口径。
- 设置页：双卡各字段即时提交（失焦/onSubmit/离页/粘贴即提交，
  统一保存钮已退役）；commit 去全部空白、无变化不写盘、空值
  删键；clear 仅 custom 在位时出现；字段初值只取自填值、内置
  key 永不进字段、SecureField 掩码 + 眼睛钮明文切换；长度软
  提示（和风 32/彩云 16）和风/彩云分开；保存反馈 savedField
  1.2s 闪烁 + Diag 只记来源 `qweather=<src> caiyun=<src>`、
  **绝不回值**（:21260-21360 区 WeatherKeyEditor）。桥
  settings_get 同口径只回 state/source。proven
- SET-14 旧差已销账：commit/clear 现统一走
  `WeatherService.invalidateAfterKeyChange()`（:17668-17677）——
  世代自增（在飞旧 key 结果整趟作废）+ 清呈现 + 删缓存 +
  主动 `refreshIfNeeded()` 重拉，不再依赖 ListView onAppear
  重入（W-T1）。verify W18-9 锁 commit/clear 两调用点。proven
  （换源刷新的真机时序仍属 §15 抽样面）

---

## 7. 桥设置页（MomentBridgeSettings.swift，349 行）

- 页面结构：启用开关卡（系统 Toggle、默认关）/ 通知开关卡
  （与权限页通知同一授权、开启才请求）/ 指纹卡 / 配对区 /
  最近调用卡（环形 20 条、只记工具名/结果码/耗时/时刻）。
  状态文案与设置主页桥行同源 `Lang.t(bridge.linkStateKey)`。proven
- 回归⑤（配对二维码）：待配对分支内 148pt 码图
  （MomentBridgeSettings.swift:228-245 区）——载荷 =
  `bridge.pairingURL()` 逐字输出、与链接钮同单一构造点；生成
  `makePairingQRImage`（MomentBridgeQR.swift:14-27）纠错级
  **"M"**、整数倍 ×8 放大；视图层白底板 `.background(Color.white)`
  + 圆角 `Radius.controlS`（14）裁切；`bridge.pair_qr_hint`
  五语键在位（429 键集内）。verify B16-QR-1..4 锁（载荷单源/
  凭据零入码/视图恰一处在待配对分支/有效期行）。proven
  （真扫可达性归人工终判，impl_pairing_qr 既定口径）
- 待配对呈现：指纹大字 + 核对提示 + 等待文案 + 过期口径双态
  （未过期 `pair_expires {time}`、过期 `pair_expired`，判据与
  协调器同 `epochMs() > expiresAtMs`，:247-262 区）——旧账
  「待配对无过期呈现」已销。proven
- scopes 呈现（桥呈现小批 ②）：空集显 `bridge.scopes_none`
  「未回带授权」、不再兜底断言只读；非空显已授名 + 未授负向行
  `scopes_ungranted {names}`（派生在协调器 ungrantedScopes，
  :285-310 区）——旧账 §5.10 两差已销。proven
- 会话状态呈现：状态词下 reason 次级行（`stateReasonKey`，仅
  backoff/connecting 带因，映射 bridge.reason_* 三键，:205-215
  区）——旧账 §5.11「backoff reason 不上屏」已销；吊销回执行
  （revokeOutcome 三态：pending/confirmed/unconfirmed，
  unconfirmed 以 warning 色，:315-330 区）——旧账 §5.9(b)
  「吊销零感知」已销（回执的真机到达率 unknown，§15）。proven
- 回归⑤（续连令牌）：MomentBridge.swift 会话恢复令牌口径在位
  ——welcome 双路下发、每次成功恢复轮换、本地 Keychain
  （AfterFirstUnlockThisDeviceOnly）恒存最新一枚、中继只存
  sha256（:187-204、:898-905 区注释与实现）；连接后首帧呈递
  resume 帧、未命中/被拒回退全量 challenge、持留 challenge
  补答（:529-540、:854-880 区）；解配对/吊销同步清令牌
  （clearPairing :204-215 区）。发起配对只报 scopes `["read"]`
  请求、授权勾选在中继配对页（:1032）。proven（机制）；
  冷/温启恢复时延（目标冷 0.5–1.2s/温 2.5–4s）为运行时面，
  unknown（§15）。

---

## 8. 外观 / 文字大小行

- 行形态达标（§2 外观组）。实效面：DT 真跟随全量实装后，
  设置族各页均已接入语义字体喂点/`@ScaledMetric`——本轮实测
  计数：MomentApp.swift 全文件 122 处 ScaledMetric、桥设置 6、
  权限页 2（f12/f16 两喂点覆盖其全部字号）、救援页 7；设置族
  各 View 属性区逐个在位（SettingsView :20352-20363、BackupView
  :20633-20645、GesturesView、WeatherView、LanguageView、
  DiagView :5145-5158、DiagLogPage 均有喂点声明）。verify [36]
  组锁固定字号白名单（仅余缩放基准）。proven（源码覆盖面）；
  audit_home P2-1「182 处固定字号」旧账**已销**。大档缩放下
  布局不破（GLB-04）为运行时抽样面，unknown（§15）。

---

## 9. 关于与版本串（回归④）

- 三处同值 proven（本轮实测）：build-app2.sh:838-839 内嵌
  plist `0.9.61` / build `88`；设置页字面量 `Text("0.9.61")`
  （MomentApp.swift:20550，HEAD 已提交版本同值，git show
  复核）；Diag 导出环境头与救援页读 Bundle 运行时值
  （DiagView.envHeaderText :5514-5516 区、Library 快照
  :642-644/:1118-1140 区）。**0.9.61/88 一致**。
- 非同源隐患仍在（旧账，§14）：设置页串为独立字面量、靠
  verify [1] 兜底，而 [1] 取值仍是 `grep -o 'Text("[0-9]…")' |
  head -1` 位置假设（verify_ios.sh:65-67 区）——本轮实测全文件
  数字字面量 Text **恰一处**，故当前比对对象正确纯属巧合；
  上方新增任何数字 Text 即静默比错对象（audit_home §4.12
  原登记、plan_selftest_coverage §4.12 注记归组版顺手，至今未办）。

---

## 10. 诊断导出入口与设置内手动救援

- 诊断页（DiagView :5135 起）：自动清理开关（set 即
  applyAutodelete + 记行、与桥 settings_set_toggle 白名单同路）/
  等级 segmented / 当天终端卡（全量可滚、整卡进视窗页）/
  **导出全部日志卡**（buildExportFile：环境头 + 归档旧→新 +
  当天 + 快照环，写 tmp 走 ShareSheet，:5540-5600 区）/ 历史
  归档胶囊（FlowLayout 横向流式）/ 库状态节（路径/篇数/附件数/
  哈希/冷启 + 清天气缓存 + 只读校验库两动作）。proven
- 日志视窗页（DiagLogPage :5609 起）：终端卡撑满页头下可用区、
  文字胶囊「导出」= 全量未过滤行、成败均记 DIAG 行。proven
- 手动救援入口在位：DiagView 库状态节内「进入救援」
  （`diag.enter_rescue`）→ `library.enterRescueManually()`
  （:5460-5462 区按钮、Library :892-896 写 bootMode=.safe
  source="manual"）——Web `?rescue=1` 的原生等价物，audit_home
  P2-3 旧账已销；BootMode source 注记已含 watchdog/manual。
  救援页本体（MomentRescue.swift）五动作 + 状态区（含布防
  reason 面见矩阵 LCH-15 归属，非本片展开）。proven

---

## 11. 宽屏收窄（回归②）：720 在位面清单

单源 `settingsContentFrame()`（MomentApp.swift:16351-16361：
横 20 / 顶 126 / 底 40 + `frame(maxWidth: 720)` + 全宽居中）。

| 面 | 在位 | 证据 |
|---|---|---|
| 设置主页 SettingsView | ✓ | :20580 调用 |
| 备份 BackupView | ✓ | :20819 调用 |
| 手势 GesturesView | ✓ | :21213 调用 |
| 天气 WeatherView | ✓ | :21380 调用 |
| 语言 LanguageView | ✓ | :21561 调用 |
| 桥设置 BridgeSettingsView | ✓ | MomentBridgeSettings.swift:180 |
| 权限 PermissionsView | ✓ | MomentPermissions.swift:537 |
| 救援 RescueView | ✓（同口径自写） | MomentRescue.swift:241-244（720 居中）+ WatchdogBar 600（:515 区） |
| **诊断 DiagView** | **✗** | 手抄 `.padding(.horizontal, 20)/.top 126/.bottom 40`（:5472 起），无 720 框 |
| **日志视窗 DiagLogPage** | **✗** | 终端卡横 20 全宽（:5670），无 720 框 |

verify W18-8（verify_ios.sh:2128-2143）计数锁的口径明示
「Diag 不在本批收敛面」——即诊断两页的排除是**既定留置**而非
落码遗漏；但 DiagView 是 `SettingsView.Sub` 七子页之一，
「设置族宽屏收窄」全称与现状不符，登记 C-02 待裁（视窗页
终端卡全宽另有功能理由，意图 unknown）。

---

## 12. 回归抽查汇总（任务六项）

| # | 项 | 结论 | 证据 |
|---|---|---|---|
| ① | 权限页行注逐字（单句口径/有功能行不误挂） | **全过** proven | §5.2 五包逐行实测表 |
| ② | 设置族宽屏 720 在位面 | **部分过**：7 页 + 救援在位；诊断/视窗不在（既定留置） | §11 清单、W18-8 |
| ③ | 备份 BK-1..3（0.9.59） | **全过** proven | §3.2；verify [40]；stagedStats 零命中实测 |
| ④ | 版本串 vs build-app2.sh（0.9.61/88） | **全过** proven | §9 三处同值实测（HEAD 与工作树同值） |
| ⑤ | 配对二维码（纠错 M/白圆角底板/五语键）+ 续连令牌 | **全过** proven（机制面） | §7；MomentBridgeQR.swift:19、BridgeSettings:242、B16-QR-1..4 |
| ⑥ | 语言默认（全新跟随系统/存量 zh-CN 零突变） | **全过** proven（判据面） | §4.2 LangStore.init :4955-4980 |

---

## 13. 新发现（本轮首登）

### C-01 导入链 `lib == nil` 可选链假成功（P3）
- 现状：`stageImport` 以 `_ = try lib?.validateBackup(…) ?? ""`
  收口（MomentApp.swift:1849）——`lib == nil` 时可选链短路
  为 nil、`?? ""` 吞掉、函数回 **true**（校验未执行却报通过）；
  `commitStagedImport` 同型：`try lib?.importBackup(…) ?? ""`
  （:1891-1892）在 lib == nil 时回空串成功 → importOk 置真、
  recordOp(ok:true)、parseStats(nil) → `.success(stats: nil)`
  → 界面弹「从本地文件恢复」成功 toast，**实际一行未导入**。
- 应然：exportZip 已于批 A 就同型旧路根治（显式 `guard let lib`
  + 失败记账，:1750-1757 注释自证旧路病理），导入两函数应同
  口径显式守卫。
- 证据级：机制 **proven**（源码短路语义确定）；可达性
  **inferred**——正常流 lib 已开库时不可达，须 lib == nil 而
  BackupView 仍可达的异常路径（开库失败通常先进安全模式、
  只读态 commit 被 writeBlocked 拦、但 stage 不查 writeBlocked，
  stage 假通过后确认底表照常弹、commit 才被拦回 failure，
  呈现为「校验通过却导入失败」的口径错位，较轻一格同存）。
- 影响面：备份导入的成败口径可信度（与 BK-1 根治同族的残余
  面）；建议随备份面顺手批把两处改显式守卫 + verify [40]
  补一条可选链锚。

### C-02 诊断页与日志视窗页未入 720 收窄（P3，已裁已落：用户 2026-11-28 裁定纳入，0.9.63 落码，fix_diag_pages_narrow.md；DiagView 改调设置族内容框、DiagLogPage 终端卡共用收窄钳单点——审计原「视窗页可单独定案保留」备选未采用，用户裁定两页均纳入）
- 现状/证据：§11 清单。DiagView 手抄三值与容器逐值等价、唯
  缺 720 框，宽屏下诊断内容全幅展开，与其余七子页形态分叉。
- 应然：二选一收口——DiagView 补 `settingsContentFrame()`
  对齐设置族全称；或明确裁定诊断面（终端长行）全宽为定案
  并同步 W18-8 注释与矩阵 SET-01 表述。DiagLogPage 终端卡
  全宽的功能理由较强，可单独定案保留。
- 证据级：代码事实 **proven**；排除意图 **unknown**（W18-8
  注释只说「不在本批收敛面」，未记终局裁定）。

### C-03 权限文件注释与行注单句口径漂移（P3·文档面）
- 现状：MomentPermissions.swift 文件头（:15-19 区）与本地
  网络探针注释（:440-447 区）仍称探针口径「在行注写明」/
  「行注已写明」，但 19:23 裁定后行注只余单句「暂无功能使用」，
  探针来源说明已整段删除（impl_permission_center §八留痕）；
  注释指向的说明实际只存于 impl 报告 §五。
- 影响面：无用户可见影响；后续维护者按注释找行注说明会扑空。
  建议注释改指 impl_permission_center §五/§八。

---

## 14. 旧账（此前已登记、本轮复核仍开，勿与新发现混记）

| # | 项 | 状态 | 出处 |
|---|---|---|---|
| C-04 | I4 未落：EditorView 无 LangStore 观察（桥远程切语言编辑器不刷新）+ SlashCmd 五语换键（EDT-59） | 仍开·归 I4 独立大批 | audit_home §4.5、impl_i18n_tail §3、矩阵 SET-15/EDT-59 |
| C-05 | I5 残余：CJK 零残留门未全量转正（现仅首页范围白名单）；两处未入包硬编码 Text（MomentApp.swift:13050 导出面 PDF 说明、:13558 双栏说明，本轮实测仍在） | 仍开·归 I5 窗口；两处均在编辑器领地、非设置族本体 | impl_i18n_tail §4、plan_native_i18n §4 I5 |
| C-06 | verify [1] 版本取值 head -1 位置假设（当前恰一处数字 Text 故未比错） | 仍开·归组版顺手 | audit_home §4.12、§9 本报告 |
| C-07 | 桥呈现残面归属他片：安全模式状态区布防 reason 呈现（LCH-15）、只读期桥分发回码一致化（LCH-13）、OPS effectiveScope 回读（LCH-14） | 仍开·归桥呈现/救援面，非设置族本体 | plan_selftest_coverage §4.8 |
| C-08 | 设置族 UI 场景覆盖缺口（SET-01/03/04/05/06/09-UI 腿/10/11/12 多行无自动场景，归 U5） | 仍开·归自检覆盖面，非功能缺陷 | plan_selftest_coverage §4.7 |

已销账复核（本轮回源确认、不再欠）：文字大小实效 P2-1（§8）、
天气 key 生效依赖 onAppear P3（§6）、桥 scopes 空集/backoff
reason/吊销回执/待配对过期四项（§7）、手动救援入口 P2-3（§10）、
语言页 E1–E4、备份 C6 底表与 C8/C9 toast 族、SET-15 图片页与
系统语言变更两半（§4.1）。

边界登记（只记不作缺陷）：APNs 发送凭据与 iCloud 容器等用户
个人 Developer 账号（§5.3）；天气彩云 key 免费额度属外部面、
链路口径不变。

---

## 15. 运行时项（unknown + 取证法）

| 项 | 为何代码不可判 | 取证法 |
|---|---|---|
| 权限页 13 行真机行为（弹窗/状态词/互通） | 系统授权面 | impl_permission_center §七 13 点清单装机逐项执行 + Diag `SET perm request` 行对账 |
| 本地网络探针三态（可用/已拒绝/未能确定） | NWBrowser 与系统策略交互 | 同上 §七.8：允许/拒绝两路各跑一次 |
| 备份导入/导出真机全链（计数对账、取消分享不弹 toast） | 系统文件选择器/分享面板 | impl_backup_tail §6.4 两点：真实 ZIP 导入计数对账；导出取消 vs 完成各一次 |
| 语言默认判据真机两路（全新装跟随系统 / 覆盖装存量 zh-CN） | 安装态构造 | 全新装与覆盖装各一台次，Diag `LANG init` 行判读 |
| 桥续连时延与令牌恢复命中率 | 中继 + 网络面 | 桥 Diag `BRIDGE resume ok/fallback` 行抽样（MEMORY 既定口径） |
| DT 大档下设置族布局不破（GLB-04 抽样） | 渲染面 | 系统文字最大档下设置七子页通查（U5 抽样行） |
| 二维码真扫可达 | 相机/另一设备 | 另一台设备扫码打开配对页一次（BRG-11 既定人工面） |

—— C 片完。后续覆盖状态以 plan_selftest_coverage.md 矩阵为准；
本报告新发现 C-01..C-03 待主线分批，旧账 C-04..C-08 沿原归属。
