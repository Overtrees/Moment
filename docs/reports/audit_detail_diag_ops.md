# 线 5：诊断与运维/自救机制 原生 vs Rust Web 全面复查（2026-11-26）

本线为只读审计：在既有清点 `audit_native_diag_rescue.md`（批 A/B/C 已于 0.9.15–0.9.18 落地）之上逐项核现行代码，找剩余缺口。结论分三类：缺陷待修 / 平台无对应面属等价处理 / 已对齐（本次复核过代码、非复述旧报告）。

## 计数总览

- Web 打点调用点（diag.rs 之外）：`diag::log` 290 + `log_warn` 15 + `log_once` 19 + `log_modal` 7 + `log_probe` 3 + `log_census` 3 + `log_late` 2 ≈ **339 处**；按文件：main.rs 84、editor/ops.rs 42、persist.rs 37、editor/dispatch.rs 29、blocks.rs 24、settings.rs 21、editor/layers.rs 19、list.rs 13、editor.rs 11、weather.rs 10、idb.rs 9（`grep diag::` 提及数，含少量非 log 调用）。
- Web TAG 分布（首参字面量形式 224 处）：EDIT 114、APP 46、SQLITE 13、ATT 10、WEATHER 7、LANG 7、IMPORT 7、CARD 5、WIKI 4、SET 3、EXPORT 3、IMGPAGE 2、IDB 2、ERRBADGE 2、BACKUP 2、SAFE 1、IMGSIZE 1；另有 ERR / PANIC / DIAG / RESCUE / SWUPD 由 diag.rs 管线与 drain 生成。
- 原生打点：`DiagLog.shared.log` **75 处**（MomentApp.swift 单文件）。分布：Library 生命周期与数据安全约 30（LAUNCH/SMOKE/打开库/隔离/重试/删除 5/保存 3/附件写 2/备份导出导入 6/头像 4/搜索 3）、WEATHER 9、编辑器约 20（EDIT 13 + CARD 2 + SCROLL 4 + DRAG 1）、图片 3、ERRBADGE 3、诊断导出 2。
- 缺口共 **14 条**（缺陷待修 12 + 呈现差 1 + 修复入口 1），平台等价/无对应面 7 条。

## 一、差异表

| # | 机制/覆盖面 | Web 现行（证据） | 原生现行（证据） | 缺口与影响 | 分类 |
|---|---|---|---|---|---|
| G1 | Diag 等级过滤语义 | **门槛制**：All/Info 全显、Warn 只显 warn+error、Error 只显 error（diag.rs:686-753 `LevelFilter::min_level` + `filter_lines`） | **精确匹配**：`diagFiltered` 选 warn 只剩 warn 行、选 info 只剩 info 行（MomentApp.swift:2232-2242，DiagView 与 DiagLogPage 共用） | 用户在原生选「警告」筛日志时**看不到任何 error 行**，与排障直觉和 Web 口径相反，诊断工具本身误导 | 缺陷待修（高） |
| G2 | 会话中途崩溃取证 | panic 钩同步直写 `moment_panic_v1`（diag.rs:61-141）+ window error/unhandledrejection 钩（diag.rs:298-335），覆盖**全会话**，下次启动 drain 成 PANIC/ERR 行 | 启动守卫三键只覆盖 `load()` 阶段：`launchDone()` 在加载成功即清标记（MomentApp.swift:360-364、413）；无 `NSSetUncaughtExceptionHandler`、无 MetricKit、无 os_log（全文件 grep 零命中） | 编辑中崩溃/被杀后下次启动**无任何 Diag 行**；0.9.17 式 FFI 断言若发生在编辑期，原生侧只有系统 .ips 一条证据链，应用内取证断裂 | 缺陷待修（高） |
| G3 | 编辑文本操作打点 | EDIT 114 处（ops.rs 42 + dispatch.rs 29 + layers.rs 19…），覆盖拆分/合并/类型转换/斜杠/粘贴等操作的结果侧 | 原生 EDIT 仅 13 处，全在卡片/图库/撤销重做/粘贴图片/双栏锚点；`EditorModel.splitBlock`（:3375）、`mergeBlockBackward`（:3437）、`applySlash`（:3949）、`convert`（:3990）及回车/退格主路径**零打点** | 丢字、合并错位、转换丢内容类问题在原生日志里无证据，只能靠用户复现描述 | 缺陷待修（中高） |
| G4 | 首页交互打点 | list.rs 13 处 + main.rs APP：row open / pin tap / expand tap / delete tap（list.rs:1248-1404）、search 走 `log_once` 去重记一行（list.rs:763） | 打开备忘、置顶、分组展开、新建（`Library.create()` :626）**均无行**；搜索只记失败与 0 命中（:1046-1080），成功搜索无行 | 首页是最高频页面，其交互故障（点不开、置顶不生效、搜索怪结果）在原生无留痕 | 缺陷待修（中） |
| G5 | 设置族打点 | SET：设置进入、字号变更（settings.rs:255、296）；LANG：语言初始化/切换全程 7 处（i18n.rs:137-173）；BACKUP：备份页进入与历史结果（settings.rs:212、515）；toast 结果行（settings.rs:102） | `SettingsView`（:10745）与 `LanguageView`（:11290）区间内 DiagLog **零命中**：主题/语言/字号/手势设置变更、备份页进入均无行（备份导入导出动作本身有行，在 Library :725-833） | 语言切换失败、字号不生效类问题无证据；设置变更无审计行 | 缺陷待修（中） |
| G6 | Diag 页自身动作留痕 | `set_level_filter` / `set_autodel` 各记一行 DIAG（diag.rs:735-741、1029-1036）；视窗页导出 `export_log` 记 DIAG 结局行（diag.rs:1071 起，含 file-construct 失败行） | 等级 Picker（DiagView :2310 附近）与自动删除 Toggle（:2287 附近）只改偏好不记行；`DiagLogPage.exportAll`（:2614）`try?` 静默、无成败行——而全量导出 `exportEverything` 有成败行（:2509、2515），同页两路不一致 | 「日志被谁改了设置/导出到底成没成」无从对账 | 缺陷待修（中低） |
| G7 | 去重打点机制（log_once / log_err 同文去重） | `log_once` 19 处调用 + `log_err` 同文每会话只记一次并共用 seen 集（diag.rs:199-201、308-335），防 rAF 循环抛错刷屏 | DiagLog 只有 `log` 一式（:2212-2230），无去重原语；调用点只能各自克制 | 重复错误可逐次入环挤占 300 行环（如图片加载失败 :1777、1790 在列表重演算时是否重复触发取决于失败缓存，标 inferred）；后续新增高频打点无防刷屏兜底 | 缺陷待修（中低） |
| G8 | 错误徽章覆盖面与呈现面 | 徽章挂 **App 根**（main.rs:2696 `errbadge::ErrorBadge`），全应用可见；投递是**管线级**：`log_err_full` 使全部全局错误 + `add_warn` 调用点（ops.rs/layers.rs 的附件/PDF 失败）都进徽章（diag.rs:319-335、errbadge.rs） | 徽章层只在 EditorView 内（`errBadgeLayer`）；投递点仅 persist 3 处、putAttachment 2 处、PDF 1 处（:589-688、4648）；删除失败、导入失败、搜索失败、图片加载失败、打开库失败等 error 行**不进徽章**，首页/设置页发生失败时无徽章可见 | 本轮刚落的徽章与 Web 的「第二取证面」定位有实质差距：编辑页外失败仍只躺在日志里 | 缺陷待修（中） |
| G9 | 导出诊断的环境上下文 | 救援快照每加载一条：UA、SW 注册、Cache 键、IDB 库表、localStorage 键名长度（index.html:372、335-336），导出诊断自带环境 | `exportEverything`（:2497）只拼日志行；环境信息仅 SMOKE 行含 app 版本与篇数/耗时（:425），无设备型号/系统版本行 | 跨设备排障时需向用户另行询问设备与系统版本 | 缺陷待修（低） |
| G10 | 归档截断/自动删除的删除留痕 | 归档超 60 丢弃记 WARN；`set_autodel` 记 DIAG 行（diag.rs:1029-1036） | `prefix(60)` 静默截断（:2151、2196）；`applyAutodelete`（:2200-2210）删除不记行 | 日志变少的原因（截断/自动删除各删了多少）无从对账 | 缺陷待修（低） |
| G11 | 加载失败呈现的两路一致性 | 阻断页统一重试入口（persist 状态 listener 推呈现） | 列表空行有「重新加载」动作（:10593 `emptyRow`）；宽屏 `gridEmpty`（:10146-10165）同为 loadFailed 却只有文案、无重试钮 | iPad/宽屏下加载失败只能干等或重启 | 缺陷待修（低） |
| G12 | Wiki/反向链接跳转打点 | wiki.rs:220 `log_once` 记跳转 | 原生 wiki 逐链点按跳转（0.9.25 落）无行（全文件 census 无 WIKI 等价条目） | 跳转错篇/目标解析问题无留痕 | 缺陷待修（低） |
| G13 | Diag 视窗页与当天卡呈现 | 视窗页正文与当天卡同款**绿字黑底终端卡**（panels.css:247 `.diag-body` 背景 #111、字 #7cfc9a、max-height 52vh 内滚动）；当天卡显示过滤后**全部行**（卡内滚动） | 视窗页（:2550-2592）用普通底色 + 主色文字（error 行红色），非终端形态；当天卡只显**最后 8 行**（:2360 `suffix(8)`） | 与 Web 定案观感不一致（数据无损：视窗页内原生为全量行、当天卡点入即全量） | 呈现差（低） |
| G14 | 数据修复/维护动作入口 | 救援面板有 repairBoot（只注销 SW + 清 Cache，绝不动数据）与存储后端开关，且 `?rescue=1` 可直达（index.html:102-115、635-640） | DiagView 动作只有导出全部/自动删除/等级（:2245-2530 通读），「库状态」段纯展示；库打不开时用户侧动作只有 loadFailed 的重试 | iOS 无 SW/Cache 层，Web 修复动作无直接对应物；但「打开库失败」场景下原生无第二动作（如校验库、重建索引）。旧报告「数据修复入口：无」至今未补 | 缺口（低，优先级靠后） |

## 二、平台无对应面 / 等价处理（不算缺陷）

| # | Web 机制 | 原生处理与残余差异 |
|---|---|---|
| E1 | index.html 救援层：状态快照环 + 存活标记 `moment_boot_ok` + 12s 看门狗出救援条 + 活过来 2s 轮询自撤（index.html:318-340、627-640） | iOS 无预启动脚本层。等价物 = 启动守卫三键（面包屑步骤 开库/读数据/写种子 同步落 UserDefaults，MomentApp.swift:350-390）+ LAUNCH error 行 + 连续 ≥3 次 notice 建议导出。残余差异：Web 在「应用完全起不来」时仍能出救援条并导出快照；原生若崩在守卫执行前，用户侧只能靠系统 .ips。方向已定案（批 B），残余风险如实记录 |
| E2 | SW 更新提示条（index.html:63-69 `#mn-swupd`，事件暂存 `moment_swupd_pending_v1` 启动 drain 成 SWUPD 行，diag.rs:464-489） | 分发渠道不同（ipa 手工侧载），无 SW 概念，无对应面。已定案不移植 |
| E3 | 存储状态四值 listener：独占阻断页 / sqlite 硬失败阻断页 / dual 只读降级横幅（`writes_blocked` 写门面统一拒写）/ 会话 IDB 降级横幅（persist.rs:230-235、342、856） | 原生单进程单后端（rusqlite 直连），无多标签、无双写、无 IDB。等价面：loadFailed 阻断态 + 重试（:10593）、隔离 notice（:447-456）。实质差异：**无「只读降级续跑」档**——写失败时原生逐次记 persist error + notice（:589-613），不设统一写总闸；库 open 失败即全阻断（Web dual 下可退 IDB 续跑）。属架构差异，原生不做双后端为既定决策 |
| E4 | Worker install 失败按步结构化分类（GetDirHandle/CreateSyncAccessHandle/… 六步，persist.rs:856 起） | 无 Worker，无对应面。原生 open 失败只有一句 error 行（:436），不区分文件缺失/权限/损坏——FFI 错误仅 message 字符串（既定边界），记为已知限制 |
| E5 | 量测仪器 log_probe / log_census / log_late / log_modal（共 15 处调用，main.rs:543-548、editor.rs:364、sheets.rs 等） | DOM/CSS/安全区量测专用，平台无对应。原生部分等价：SCROLL 探针（采样 ≥24pt 且 ≥0.3s 才记行，:7033-7052）+ SMOKE 耗时行。批 C 已定案取舍：块型视图逐块打点不加，同理不补 |
| E6 | 加载期自愈细项：pending-delete 过期清理、种子置顶 retarget、改名迁移失败保留旧库、会话降级下次冷启再迁移 | 原生 pendingDeletion 在进程被杀时不落库删除 = 安全默认（数据保留优先）；种子仅空库写入（:404-411）；无改名迁移与降级迁回面。等价或无对象 |
| E7 | SAFE（安全区探针，main.rs:758）/ IMGSIZE 等 Web 专属 TAG | CSS env 与 Web 图片量测专属，平台无对应面 |

## 三、已对齐（本次逐项复核现行代码确认）

- **管线四件**：300 行环（MomentApp.swift:2226-2228）、落盘 1s 节流合并 + error 立即刷（`schedulePersist` :2166-2183，对 Web `flush_persist`/节流口径）、按天冻结归档上限 60 且**归档戳 = 日志当天**（:2136-2158、2184-2197）、自动删除 30 天（:2200-2210，偏好键 `diagAutodel`）。
- **行格式**：`[HH:MM:SS]` + warn/error 括号内 W/E（DiagEntry.line :2028-2038），与 Web `format_line`/`line_level`（diag.rs:660-684）同口径。
- **等级过滤只动呈现、导出全量**：`diagFiltered` 只用于呈现（:2232）；全量导出与视窗页导出均走未过滤 entries（:2497-2525、2614-2625）。
- **Diag 页呈现主体**：自动删除行 + 等级行、当天绿字黑底卡（:2343-2378）、归档胶囊流（:2400-2425）、视窗页（返回 + 标题=文件名 + 系统分享导出）、全量一键导出且**导出结局记行**（:2509-2515）。另有「库状态」段（路径/篇数/附件数/库哈希/冷启耗时 :2444-2460）为原生增强，Web 无此段。
- **批 A 数据级**：persist 结果回路（序列化/库未打开/写入三段 error + notice，成功才同步内存列表 :580-620）、putAttachment 回 Bool 且失败记 error（:674-695）、exportZip 库未打开守卫（:725）、retryLoad 按结局置 loadFailed 并记 error（:460-475）、逐篇隔离全链（storage `list_memos_tolerant` lib.rs:300-346 `merge_quarantine` 并入 meta `quarantine_json`、导出附 quarantine.json lib.rs:500-536；Swift 包装形 parse + warn 行 + notice :443-456）。
- **批 B 启动自救**：守卫三键与面包屑（:350-390）、LAUNCH 行、SMOKE 冒烟行（:425-430）——0.9.17 checksum 闪退曾被此链完整抓下（旧报告完成注记，真机日志实证）。
- **天气打点逐字同源**：原生 WEATHER 9 处（:9439-9584）与 Web weather.rs 10 处文案一致（locate failed / provider=fail / fetched provider=…），含彩云兜底分支。
- **notice 通道已实装**：隔离、保存失败、启动连续失败三路赋值（:447、589-613、385-388），非旧报告所述空壳。
- **ErrBadge 本体形态**：上限 20、内存不落盘、投递记 ERRBADGE 行（:2052-2093），与 Web errbadge.rs 口径一致（覆盖差距见 G8）。

## 四、严重度排序（供排批参考）

1. **G1 等级过滤语义反转**——一行判定逻辑的差，排障时直接藏掉 error，最先修。
2. **G2 会话中途崩溃无留痕**——取证链最大盲区；可行补法是把启动守卫的「进行中」标记扩展为全会话哨兵（场景切换时更新步骤、正常退出清除），下次启动即可知崩在哪个场景，成本低。
3. **G3 编辑文本操作零打点**——按 Web EDIT 的操作清单挑结果侧关键点（拆分/合并/转换/斜杠插入）补行，不必逐块。
4. **G8 徽章覆盖**——投递点扩到与 Web add_warn/add_error 同面 + 徽章层上提到首页/设置页可见。
5. **G4 + G5 首页与设置族覆盖**——补 log_once 等价去重后（G7）再补这两面，避免刷屏。
