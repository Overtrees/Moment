# 权限 B 段落码：声明拉满 + Live Activity 实况 + tree 签名实证（2026-11-27）

> 依据 impl_ios_entitlements_liveops.md（A 段审计与 31 行声明矩阵、B 段清单）。落码门已过（HEAD 6ce6cd8）后照单落码；不提交、不 bump，随下一组版。**verify 组号顺延**：A 段提案 [32] 已被 E4 健壮性批占用、[33] 又被媒体增强批（M33）占用，本批实际落 **[34]**（主线 17:33 更正口径一致）。

---

## 一、工具建立（B 段第 0 步，tree）

本机/tree 均无 ldid/zsign/codesign——按「缺工具先自补」口径自写 **macho-entitle**（Python3 stdlib 单文件，7892 B），装于 tree `~/ios-native/bin/macho-entitle`，源码留档 `~/workspace/ios-tools/macho_entitle.py`，技能 toolchain.md 已加备忘。

- 原理：ld64.lld `-adhoc_codesign` 产物 = 单 CodeDirectory（SHA-256、nSpecialSlots=0、无 entitlements blob）。工具重建签名：CodeDirectory 扩至 7 个特殊槽（hashOffset/length 相应调整）、superblob 新增 entitlements blob（magic 0xfade7171、槽 CSSLOT_CODE_ENTITLEMENTS=5）并把其哈希记入特殊槽 5；`--info` 时槽 1 = Info.plist 哈希；逐页哈希与 codeLimit 不动，签名区位于文件尾、可增长，LC_CODE_SIGNATURE datasize 同步更新。
- 接口：`embed <bin> <ent.plist> [--info <Info.plist>]`（内含 verify、不过即非零退出）/ `read` / `verify`。

### 演练实证（tree，0.9.57 现行产物副本，演练后已清理）

| 演练 | 结果 |
|---|---|
| 现行产物 `read` | NONE（与 A 段审计「空 entitlements」一致） |
| 嵌入 aps-environment=development（245 B）+ `--info` | 签名 146048 → 146529 B；`verify` OK（槽 5 哈希匹配）；回读 XML 逐字一致 |
| 独立复核（另一段脚本重算） | 逐页哈希与原产物**逐字节相同**；槽 1 == SHA-256(Info.plist)；槽 5 非零、槽 7 零；check-macho.py 通过 |
| 扩展口径：嵌入空集 entitlements（188 B） | 同链路 OK、回读为空 dict |

## 二、逐项落码

### 2.1 build-app2.sh 接线（A 段所列五处全落）

1. **Info.plist 增键**：六项惰性就绪用途串（相机/相册读/相册写/麦克风/Face ID/本地网络，zh-CN 值按 A 段 §四表；定位沿用现行值）+ `NSSupportsLiveActivities` + `NSSupportsLiveActivitiesFrequentUpdates` + `UIBackgroundModes`（remote-notification/processing/fetch）+ `BGTaskSchedulerPermittedIdentifiers`（processing/refresh 两标识符）。版本行未动（[1] 三处一致口径无扰）。**audio 未声明、application-groups 未声明、iCloud 类未碰**（矩阵裁定）。
2. **五份 .lproj/InfoPlist.strings**：脚本内 `write_infoplist_strings` 函数生成 zh-Hans/zh-Hant/en/ja/ko 五份，每份 = CFBundleDisplayName 五语显示名（此刻/Moment/此刻/瞬間/순간）+ 七项用途串本地化（A 段 §四全表）——i18n I5 的显示名部分由本批提前落地，I5 后续只做残余通查。
3. **Moment.entitlements 嵌入**：仓内新文件（内容仅 aps-environment=development，245 B 与演练件同字）；plist 写毕后对 `$APP/Moment` 执行 `macho-entitle embed … --info $APP/Info.plist`，工具内 verify 不过即非零退出、set -e 中断构建（不带病出包）；构建日志留 `entitlements embedded + verified (aps-environment)` 一行。工具缺失时不中断（[34] 会红、出包门拦下，与 accord 缺失同口径）。
4. **新文件入构建**：MomentLiveOps.swift + MomentLiveOpsAttributes.swift 进全部 16 遍名单 + 各自 primary 遍（liveops.o / liveops_attr.o）+ 链接行。
5. **扩展段**：MomentLiveOpsWidget.swift + Attributes 以 $COMMON 同旗标两遍编译（**模块名与主 App 同为 MomentMain**——ActivityAttributes 跨进程按类型全名匹配，两侧同名同构是硬要求）→ 单独链接（SwiftUI/WidgetKit/UIKit/Foundation + stub.o）→ check-macho → 组装 `PlugIns/MomentLiveOpsWidget.appex`（自有 Info.plist 模板 MomentLiveOpsWidget-Info.plist：标识符 com.canopies.moment.liveops、扩展点 com.apple.widgetkit-extension、版本与主 App 同步 0.9.57/84）→ 嵌入空集 entitlements（MomentLiveOpsWidget.entitlements）→ 随 .app 封入 ipa。

### 2.2 Live Activity（新文件三件）

- `MomentLiveOpsAttributes.swift`：`OpsActivityAttributes`（opKind/opTitle 静态属性；ContentState = phase/stepLabel/done/total/updatedAt）+ LiveOpKind/LiveOpPhase 枚举；双目标同编。
- `MomentLiveOps.swift`：封装 start/update/end + 节制（步进 5s 合并、只留最新帧、终态与 phase 翻转不节流、staleDate +10min、成功 15s 消退/失败留 10min、relevanceScore 未设——系统默认，A 段 50 为建议值未采，差异在此登记）+ Diag 五式 `OPS live start/update/end/skip/grace` + 后台宽限组合（appDidEnterBackground：有 active 才 beginBackgroundTask、过期回调置 waiting 并收口、记 grace begin/end）+ BGTask 注册/调度 + 通知偏好/授权请求。
- `MomentLiveOpsWidget.swift`：@main WidgetBundle 以 #available 条件纳入；锁屏面（标题/步名/ProgressView）+ 灵动岛 expanded/compact/minimal；文案全来自属性/状态、扩展内零硬编码语言串。
- **版本口径实证纠错**：`ActivityContent` 与 content 式 request/update/end 是 **iOS 16.2+** API（A 段按 16.1 写有误）——落码双路：16.2+ 走 content API、16.1 走 contentState 旧式 API（request(contentState:)/update(using:)/end(using:)），16.0 整体 no-op + skip 行。部署目标 16.0 不变。

### 2.3 挂点清单（A 段 §5.3 表逐点）

| 挂点 | 落点 | 起/止 |
|---|---|---|
| 场景运行 | MomentBridgeUITest.swift：UITestJob.liveId 新字段；begin() 受理后、setup 前 start（total = def.steps().count，标题 liveops.scenario）；runSteps 每步完成后 update（done=步序）；finish() 双路（ctx nil 路 + restore 完成后）按终态码 end | 全终态覆盖 |
| 桥长操作 | MomentBridgeTools.swift：`liveLongOpTools` = {notes_delete_permanent, notes_restore_deleted}；dispatch 在两段令牌消费、幂等回放之后、switch 执行前 start（dryRun/回放命中不误起）；done 闭包统一 end（code=="ok" → ok、余 failed） | 第二段起、回执止 |
| App 侧导出 | Library.exportZip()：入口 start（kind=export）、defer 按 lastExportError 收口（覆盖库未打开失败路）；救援页 exportZipAction 经此同路、不重复起 | 函数全程 |
| App 侧导入 | Library.commitStagedImport()：writeBlocked 拦截后 start（kind=restore）、importOk 旗 + defer 收口 | 函数全程 |
| 后台宽限 | MomentBridge.swift didEnterBackground 观察头部调 `MomentLiveOps.shared.appDidEnterBackground()`（与 presence 发送独立、先行） | 进后台时 |
| BGTask | MomentApp.init() 注册 + 首次调度；handler：processing → BridgeWriteSupport.pruneForBackground()（新内部入口、走同一保留策略）；refresh → OpsDirectives.refreshInBackground()；进后台时续提调度 | 启动期注册 |
| 通知开关 | 桥设置页启用卡下方新增通知卡（bridge.notify/notify_note 五语新键）：开启才 requestAuthorization（§3.4 口径、启动不索取） | 用户开启时 |

短操作不启的判据 = 操作集成员资格（liveLongOpTools / 场景 / 导出导入四面），无时长猜测；桥连接会话本身不起。

### 2.4 语言包

五包各 +6 键（liveops.bridge_op/export/import/scenario、bridge.notify/notify_note），键数 361 → 367；verify [18] 期望已同步。其后配对二维码批又 +3 键（bridge.pair_*），期望已再同步为 **370**（注释链完整留痕）。

## 三、tree 签名实证（逐条）

实证分两层：**工具层**已在 tree 以真实产物演练定案（第一节表）；**产物层**逐条回读须待下一组版在 tree 全量构建后执行——构建脚本本身已把回读做成构建内断言（embed 内 verify + 日志行），组版冒烟时即是实证现场，下表为预期集与核对法：

| # | 项 | 预期实嵌集 | 核对法 | 现状 |
|---|---|---|---|---|
| 26 | aps-environment | development（主 App） | `macho-entitle read Moment.app/Moment` | 工具层演练 ✓ 同值同法；产物层待组版构建 |
| — | 扩展 entitlements | 空集 | `macho-entitle read …appex/MomentLiveOpsWidget` | 工具层演练 ✓（空 dict 件） |
| 27/28/29/30/31 | groups/keychain/get-task-allow/iCloud/其余 | **不出现** | read 输出 + verify B34-4 禁区零命中 | 源码层 ✓（[34] 全绿） |
| 18–23 | plist 键（实况两键、后台三模式、BGTask 两标识符） | 全在位 | verify B34-1/2/3 + 产物 PlistBuddy 式回读（组版时） | 源码层 ✓ |

无任何一条在演练中签不进——**无降级撤下项**。若组版构建时 embed 失败，脚本 set -e 直接中断、不出包（ fail-closed 已落码）。

## 四、verify [34] 与自检

- 新组 **[34] 权限声明 + Live Activity 实况**（B34-1…B34-9）：用途七键 / 实况与后台键集 + 无虚假模式 / 五份 strings 生成 / entitlements 集与矩阵一致 + 禁区零 / 三文件双目标接线 + appex 入包 / 挂点计数（start 4、end 5、update 1）/ Diag 五式 / BGTask 注册消费 + 通知开关 / 语言包新键五语。**本机全量 verify 中 [34] 九条全绿**；余红为他批在途项（B27 M3a、F30 首页批落码中）与陈旧 ipa（组版重建后消），与本批无关。
- 编译级自检（本机同旗标 primary 遍）：MomentLiveOps / MomentLiveOpsAttributes / MomentLiveOpsWidget（两遍）/ MomentBridgeSettings / MomentBridgeUITest **全过**。MomentApp / MomentBridgeTools / MomentBridge 三遍在本批挂点落码后曾于 LiveOps 遍的次级输入形态下全过；其后 M3a 等批在途改动使其主遍出现他批符号缺口（BridgeScenario* 新文件未入其构建名单前）与 MomentApp 他批区域错误——非本批 hunk，待各批构建名单补齐后由组版 tree 全量构建定案。

## 五、真机终判点（装下一组版后）

1. 惰性声明不弹窗：相机/相册/麦克风/Face ID/本地网络在现行任何流程中**不应**弹出（弹出即有未对账 API 调用点、记缺陷）；定位弹窗五语文案随系统语言正确。
2. 实况全程：跑一次 uitest_run——锁屏出现实况（标题/步名/进度）、灵动岛 compact、点按回前台；成功结束 15s 消退、失败留 10min；Diag `OPS live start→update*→end` 行序完整。
3. 长操作切后台：整库导出/恢复中切后台 30s 回来——操作完成或进度连续；`OPS live grace begin/end` 成对；桥 `BRIDGE session` 行按稳定性批判读法对读。
4. 重签安装：全能签重签后安装成功、首启无 entitlement 崩溃；`macho-entitle read` 对装机同源 ipa 内主二进制回读 aps-environment 在位（组版交付时主线附带核对）。
5. BGTask：属系统调度不可强求时点——以 Diag `OPS bg processing/refresh run` 行在装机后数日内出现为弱判据，不作本版阻塞项。

## 六、边界重申（不许升级表述）

实况不让挂起进程续命、不扩张桥的保证域（前台必连通仍归稳定性批）；APNs 发送方与实况推送更新仍是基建缺口（A 段 §八），aps-environment 本期只落声明与嵌入，不宣称远程唤醒能力；iCloud 仍为唯一 parked。
