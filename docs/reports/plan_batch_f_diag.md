# 批 F（诊断覆盖）落码执行清单 —— 对 audit_detail_diag_ops.md 的逐条核证（2026-11-26，现行 0.9.35）

方法：逐条回读 `rust/apps/ios/app/MomentApp.swift` 现行代码与 Web 出处（diag.rs / ops.rs / list.rs / settings.rs / wiki.rs / cards_fx.rs），只记代码证据。行号为核证时点行号，落码时以符号名为准。

## 状态总表

| 编号 | 状态 | 说明 |
|---|---|---|
| G1 等级过滤门槛制 | 已修（0.9.32） | `diagFiltered`（:2331）已改 rank 门槛制，注释在位 |
| G2 全会话崩溃哨兵 | 已修（0.9.32） | `launchDone` 改置「会话中」（:367）、`markScene`（:372，首页 :10115 / 编辑页 :5956 调用）、`launchSuspend/launchResume`（:379/:385）+ scenePhase 接线（:11827），`inspectPreviousLaunch`（:398）已分级 |
| G11 宽屏空状态重试钮 | 已修（0.9.32） | gridEmpty 已调 `library.retryLoad()`（:10421），与窄屏 emptyRow（:10876）同路 |
| 图片页 IMGPAGE | 已修（0.9.35） | open 就绪后记带 nat（:11792-11806）、close 钮 + onDisappear 兜底去重（:11747） |
| G3 编辑文本打点 | **待修** | 见下 |
| G4 首页打点 | **待修** | 见下 |
| G5 设置族打点 | **待修** | 见下（LANG 切换部分无对象，随 i18n 立项） |
| G6 Diag 页自身留痕 | **待修** | 见下 |
| G7 log_once 原语 | **待修（前置）** | 见下 |
| G8 徽章扩面 + 上提 | **待修** | 见下 |
| G9 导出环境头 | **待修** | 见下 |
| G10 截断/自删留痕 | **待修** | 见下 |
| G12 wiki 跳转打点 | **待修** | 见下 |
| G14 数据修复入口 | **待修（部分）** | 见下，只落零风险两项 |
| G13 视窗页终端形态/当天卡 8 行 | 待修（呈现差，不在本批落码序） | 当天卡仍 `suffix(8)`（:2467）；属线 4 批 E 呈现面，本批不混入 |

待修共 **10 条**（G3–G10、G12、G14，其中 G14 部分落、G5 的 LANG 切换无对象）。

---

## G7 去重打点原语（前置项，先落）

- **Web 出处**：diag.rs:199-202 `seen()`（进程级 `HashSet<String>`，log_once 与 log_err 共用一集）；diag.rs:853-858 `log_once(key, tag, msg)`——key 插入成功才记行；diag.rs:308-329 `log_err` 以 `err:{msg}` 为 key 同集去重。
- **原生现状**：`DiagLog`（:2192）只有 `log(_:_:)`（:2304）一式，无 seen 集、无 once 能力（全文件 grep `logOnce/onceKeys` 零命中）。
- **落点**：`DiagLog` 类内，紧邻 `log` 方法。
- **改法（最小设计）**：
  1. 加 `private var onceKeys: Set<String> = []`（单例进程级、不落盘、随进程重启清空——与 Web 会话级语义一致）。
  2. 把 `log` 的入环主体抽为 `private func appendEntry(_ level:_ text:)`（现 :2304-2324 的 work 闭包内容），`log` 与新原语共用，避免两份节流/冻结逻辑分叉。
  3. 加 `func logOnce(_ key: String, _ level: DiagLevel, _ text: String)`：在主线程工作闭包内先 `guard onceKeys.insert(key).inserted else { return }` 再走 appendEntry——判定与入环同闭包同队列，天然无竞态（`log` 本就把工作收敛到主队列）。
  4. 加 `func logErrorOnce(_ text: String)`：`logOnce("err:" + text, .error, text)`，对位 Web log_err，供图片加载失败类同文错误（ImageLoader :1867/:1880 两处 error 行）改投，堵审计 G7 点名的刷屏面。
  5. key 纪律写进注释：key 必须是模板串（可含 id/查询词等有界标识），禁止拼整段用户正文；Web 对 search 用 `search:{q}` 同口径，不设上限（集随会话自然有界）。
- **工作量**：小。

## G3 编辑文本操作打点

- **Web 出处**：ops.rs EDIT 42 处 + dispatch.rs 29 处；成功路径亦记：`split-exit-list {bid}`（ops.rs:373）、`split-styled-insert-para {bid}`（:390）、`split-exit-styled {bid}`（:412）、`convert {bid} -> {act}`（:1695）、`paste text {} lines into {bid}`（:1191），异常路径 `split: block not found {bid}`（:335）、`merge: block not found {bid}`（:500）。
- **原生现状**：EDIT 共 13 处全在卡片/图库/撤销重做/粘贴图片/双栏；下列函数体内 DiagLog **零命中**（逐个回读确认）。调用入口唯一：Coordinator `shouldChangeTextIn` 的回车/退格分流（:1751-1777）。
- **落点与格式**（TAG 统一 `EDIT`，文案对 Web 小写动词短语 + id 口径；原生既有行如 `EDIT paste image -> block` 同风格）：

| # | 落点（符号） | 记点 | 建议文案 | 节流 |
|---|---|---|---|---|
| G3-1 | `EditorModel.splitBlock`（:3487） | 插入新块后、scheduleSave 前 | `EDIT split {b.type} {b.id} -> {nb.id}`（info） | 普通 log |
| G3-2 | `EditorModel.exitEmptyBlock`（:3520） | 类型改段落后 | `EDIT split-exit-styled {b.id}`（info，对 Web :412 同名） | 普通 log |
| G3-3 | `EditorModel.mergeBlockBackward`（:3549） | 三分支各一：空块删→目标 / 并入 prev 文本 / 并入列表末项（T-13） | `EDIT merge empty {b.id} -> {target.id}` / `EDIT merge {b.id} -> {prev.id} at {junction}` / `EDIT merge {b.id} -> list-item {last.id}`（info） | 普通 log |
| G3-4 | `EditorModel.mergeListItemBackward`（:4546） | 各 return 路径前按分支记一 | `EDIT merge list-item {item.id} case={first-empty/first-merge/empty/whole-list/promote}`（info） | 普通 log |
| G3-5 | `EditorModel.insertLines`（:3593） | 拼装完成后 | `EDIT insert lines {lines.count} into {b.id}`（info，对 Web paste text 口径） | 普通 log |
| G3-6 | `EditorModel.applySlash`（:4061） | switch 收口后一处总记 + 目标缺失 guard（:4079）一处 | `EDIT slash {act} {b.id}`（info）；缺失：`EDIT slash target missing {bid}`（warn） | 普通 log |
| G3-7 | `EditorModel.setBlockType`（:3389） | nodeVersion 自增后（长按菜单类型转换入口） | `EDIT convert {b.id} -> {type}`（heading 附 ` level={level}`，info） | 普通 log |
| G3-8 | `EditorModel.deleteBlock`（:3471） | removeAll 后 | `EDIT delete block {b.id} type={b.type}`（info） | 普通 log |
| G3-9（可选） | `addImageBlock`（:3406）/ `addAttachmentBlock`（:3458） | 追加后 | `EDIT add image block {fid}` / `EDIT attach {fid} {name}` | 普通 log |

- **高频结论**：**全部用普通 log，无一需要 once/节流**。理由：这些函数只由离散用户动作触发（回车一次一次、退格到块首才触发并块、菜单点按、斜杠选择），不随击键逐字、不随帧/重演算触发；连按退格跨块合并的速率受块数封顶且每次合并本身就是要留痕的事件。Web 对同路径同样逐次普通记（无 once）。once 的真正用武之地在 G4 搜索与图片加载同文错误，不在此。
- **工作量**：中（9 处落点、逐处一行，无逻辑改动）。

## G4 首页交互打点

- **Web 出处**：list.rs `row open {mid}`（:1346/:1461）、`row pin tap {mid}`（:1248）、`row delete tap {mid}`（:1262）、`row expand tap {mid}`（:1374/:1487）、`row new tap`（:1545），TAG 均 `APP`；搜索 `log_once("search:{q}", "APP", "search '{q}'")`（list.rs:763）。
- **原生现状**：`Library.create()`（:664）、`togglePin`（:701）、`softRemove`（:516）均无行；打开备忘的四处 `nav.dest = .editor(...)` 赋值（:10427、:10451、:10534、:10541）无行；分组展开两处（窄屏 :10276-10287、宽屏 gridSublist :10381-10396）无行；`Library.search`（:1079）仅失败与 0 命中记行，成功无行。注：删除的**结果**已有行（commitPendingDeletion :541 起 info/error、remove :681 起），缺的是「点按」意图行。
- **落点与改法**：
  1. 打开：单点收敛——`EditorView` 根 `.onAppear`（现已有 `Library.markScene("场景·编辑页")` :5956 同处）加 `APP row open {editor.item.id}`（info）。一处覆盖行点按/网格点按/右键菜单打开/wiki 跳转/反向链接全部入口，与 Web row open 的「每次打开记一行」语义等价，避免四处赋值点各写一份。
  2. 置顶：`Library.togglePin` 内 `APP row pin tap {item.id} pinned={it.pinned}`（info）——单点覆盖左滑与两处 contextMenu（:10546、:10802）。
  3. 删除点按：`Library.softRemove` 入口 `APP row delete tap {item.id}`（info），与既有 commit 结果行成对。
  4. 新建：`Library.create()` 返回前 `APP row new {item.id}`（info），单点覆盖 newCardRow（:10681）与 newCardSquare（:10446）。
  5. 展开/收起：窄屏分组头与 gridSublist 的展开/收起闭包各一处 `APP row expand tap {key}` / `APP row collapse tap {key}`（info）。
  6. 搜索成功：`Library.search` 成功路径末尾加 `DiagLog.shared.logOnce("search:\(query)", .info, "APP search '\(query)' hits=\(searchHits?.count ?? 0)")`——依赖 G7；逐键调用下同查询只记首行，既有 0 命中/失败行保留不动。
- **工作量**：中（6 类落点，其中展开两处）。

## G5 设置族打点

- **Web 出处**：settings.rs `SET settings enter slideIn`（:255）、`SET font size {key}`（:296）、`SET gestures enter slideIn`（:391）、`BACKUP backup enter slideIn`（:515）、`BACKUP history {kind} ok={ok} {title}`（:212）；i18n.rs LANG 初始化/切换 7 处。
- **原生现状**：`SettingsView`（:11024）、`BackupView`（:11268）、`GesturesView`（:11590）、`LanguageView`（:11649）四区间内 DiagLog **零命中**（逐段 grep 复核）。备份导入/导出**动作结局**已有行（Library :749-880），缺页进入行与设置变更行。原生无字号设置（Dynamic Type 定案）、无备份历史列表——该两项 Web 对应物无对象，不落。
- **落点与改法**：
  1. `SettingsView` 根 `.onAppear`：`SET settings enter`（info；Web 的 slideIn 后缀是转场形态，原生系统转场改判后不带）。
  2. `BackupView` 根 `.onAppear`：`BACKUP backup enter`（info）。
  3. `GesturesView` 根 `.onAppear`：`SET gestures enter`（info；本页为只读速览，无开关可记）。
  4. `WeatherKeyUI.save()`（:11046）：`SET weather key saved qweather={len>0 ? "set" : "empty"} caiyun={同}`（info）——**只记有无与不记值**，key 本体绝不入日志。
  5. `LanguageView` 根 `.onAppear`：`SET language enter`（info）一处即可；LANG 切换/初始化打点随原生 i18n 立项（语言页现为静态展示、切换未接通），本批不落、不假装。
- **工作量**：小。

## G6 Diag 页自身动作留痕

- **Web 出处**：diag.rs:735-741 `set_level_filter` 记 DIAG 行、:1029-1036 `set_autodel` 记 DIAG 行；:1071 起 `export_log` 结局行 `export ok {fname} {size}B` / `export err {fname} {reason}`。
- **原生现状**：DiagView 自动删除 Toggle 的 set 闭包（:2406）只调 `applyAutodelete()` 不记行；等级 Picker 的 set 闭包（:2441）只写 AppStorage 不记行；`DiagLogPage.exportAll`（:2721）`try?` 静默写文件、无成败行——而同文件 `exportEverything`（:2600）有成败行，两路不一致（复核确认）。
- **落点与改法**：
  1. Toggle set 闭包内、applyAutodelete 后：`DIAG autodel -> {on/off}`（info）。
  2. Picker set 闭包内：`DIAG level -> {新值}`（info）。
  3. `DiagLogPage.exportAll` 改 do/catch：成功 `DIAG export ok {fileName} {bytes}B`（info）、失败 `DIAG export err {fileName}: {error}`（error），与 exportEverything 口径统一。
- **工作量**：小。

## G9 导出诊断加设备/系统环境头

- **Web 出处**：救援快照每加载一条环境（UA / SW / Cache 键 / IDB 库表 / localStorage 键长，index.html:372、335-336），导出诊断自带环境；原生 SMOKE 行（:464）只有 app 版本 + 篇数/耗时。
- **原生现状**：`DiagView.exportEverything`（:2600）只拼归档 + 当天行；全文件无 UIDevice/utsname/系统版本引用（grep 零命中）。
- **落点**：`DiagView.exportEverything` 拼装头部（DiagView 持有 library，可取篇数/附件数/库哈希，与「库状态」段同源读数）。
- **行格式设计**（与既有 `==== {stamp} ====` 分段头同风格，置于文件最前）：
  ```
  ==== 环境 ====
  app 0.9.35 (62)
  device iPhone16,1 · iOS 27.2.1
  store Application Support/library · memos 22 · attachments 5 · hash <libraryHash 前 12 位>
  ```
  取值：版本 = `Bundle.main` 的 CFBundleShortVersionString / CFBundleVersion；机型 = `utsname().machine`（UIDevice.model 只有 "iPhone" 粗名，不够定案用）；系统 = `ProcessInfo.processInfo.operatingSystemVersionString`。只入导出文件、不单独记 Diag 行（避免每次导出多一行噪声；文件自带即可）。
- **工作量**：小。

## G10 归档截断 / 自动删除记删除量

- **Web 出处**：归档超 60 丢弃记 WARN；`set_autodel` 记 DIAG 行（diag.rs:1029-1036）。
- **原生现状**：三处静默——`loadIfNeeded` 的 `Array((fresh + archives).prefix(60))`（:2248）、`freezeToday` 的 `Array(archives.prefix(60))`（:2288）、`applyAutodelete`（:2293）的 removeAll 删多少无行。
- **落点与改法**：
  1. 两处截断（:2248、:2288）前先算 `dropped = archives.count - 60`（含 fresh 合并后总数），`dropped > 0` 时记 warn `DIAG archives truncated dropped={dropped} keep=60`。
  2. `applyAutodelete` 前后计数差：删了归档 a 份 / 当天 t 行且任一 > 0 时记 info `DIAG autodel removed archives={a} entries={t}`。
  3. 注意自调用安全：`loadIfNeeded` 内记行会回入 `log` 的 work 闭包，其内 `loadIfNeeded()` 因 `loaded` 已置 true 直接返回，不递归（落码时在注释里写明此前提）；`applyAutodelete` 被 G6 的 Toggle 记行与本行各记一层（开关动作 vs 删除量），不重复同文。
- **工作量**：小。

## G12 Wiki / 反向链接跳转打点

- **Web 出处**：cards_fx.rs:102 `WIKI nav '{target}' from {from_id}`（逐链跳转）；editor.rs:912 `WIKI backlink -> '{stitle}'`（反向链接点按）；main.rs:2608 `WIKI open '{requested}' -> {id}`。
- **原生现状**：MD 预览 wiki 点按经 `WikiTapKey` 环境（:7653）到 EditorView.blockColumn 的 `.environment(\.wikiTap)` 闭包（:7290）解析跳篇，无行；反向链接区 Button（:7239）`onOpenMemo?(memo)` 无行。
- **落点与改法**：
  1. wikiTap 闭包（:7290）：命中记 info `WIKI nav '{target}' from {editor.item.id} -> {m.id}`；未命中记 `WIKI nav '{target}' miss`——未命中用 `logOnce("wiki-miss:\(target)", …)`（依赖 G7，同目标反复点按只记首行，防刷屏）。
  2. backlinksSection 的 Button 动作（:7239）：`WIKI backlink -> '{memo.title}'`（info，普通 log，点按离散）。
- **工作量**：小。

## G8 错误徽章覆盖扩面 + 呈现上提

- **Web 出处**：徽章挂 App 根（main.rs:2696），全应用可见；投递为管线级——`log_err_full`（diag.rs:319-329）使全部全局错误进徽章，另有 ops.rs/layers.rs 的 `add_warn` 调用点（附件/PDF 失败）。
- **原生现状**：投递仅 6 处——Library.persist 三段（:629/:638/:648）、putAttachment 两处（:719/:728）、EditorModel.exportPDF（:4762）；呈现层 `errBadgeLayer/errBadgePanel` 是 EditorView 的计算属性（:6123/:6180，`@ObservedObject errBadge` :5741），仅编辑页可见。下列 error 行均不进徽章：打开库失败（:474）、删除失败（:686/:696）、导出备份失败（:763/:779）、导入备份失败（:852/:871）、搜索失败（:1084/:1117）、图片加载失败（:1867/:1880）。
- **投递扩面落点**（与既有 error 行同处加一调用，文案短版）：
  1. Library 开库失败（:474 同处）：`addError("打开数据库失败")`。
  2. Library.remove 两处 catch/守卫（:686/:696）：`addError("删除失败")`。
  3. exportZip 两处（:763/:779）：`addError("导出备份失败")`。
  4. stageImport/commitStagedImport 失败（:852/:871）：`addError("导入备份失败")`。
  5. search 失败两处（:1084/:1117）：`addWarn("搜索失败")`（warn 级：不阻断使用，与 Web add_warn 面对应）。
  6. ImageLoader 失败（:1867/:1880）：**不投徽章**——列表滚动可批量失败，会冲掉徽章 20 条上限内的真错误；只按 G7 改投 `logErrorOnce` 进 Diag。
- **呈现上提方案与影响面**：把 `errBadgeLayer/errBadgePanel` 从 EditorView 抽为独立 `ErrBadgeOverlay` 视图（内部自持 `@ObservedObject ErrBadge.shared`），挂载点改到 `MomentApp.body` 的 WindowGroup 根：`ZStack { ListView(library:); ErrBadgeOverlay() }`——对位 Web 的 App 根挂载，首页/编辑页/设置族全部页面之上可见（导航 push 的子页也在同一 WindowGroup 层级内呈现于其下、上浮于其上的是系统 sheet，徽章被 sheet 盖住与 Web 模态层级口径可接受）。影响面：① EditorView 内旧 layer 与 `@ObservedObject errBadge`（:5741、:5859 引用、:6123-6250 两计算属性）整段删除，防双份呈现；② Overlay 的定位口径原样搬运（GeometryReader + bottom = safeBottom + 64、trailing 16、空 entries 时 allowsHitTesting(false)），不改数值；③ ErrBadge 单例与 panelOpen 状态不变，各页共享同一面板状态；④ verify_ios.sh 若有 errBadgeLayer 在 EditorView 的 grep 断言需同步改指 ErrBadgeOverlay（落码时核 [4] 组）。
- **工作量**：中（投递 5 类小改 + 呈现搬运一处）。

## G14 数据修复动作入口（只评估，本批部分落）

- **Web 出处**：救援面板 repairBoot（只注销 SW + 清 Cache Storage、绝不动数据）+ 存储后端开关，`?rescue=1` 直达（index.html:102-115、635-640）。
- **原生现状**：DiagView 动作只有导出全部/自动删除/等级；「库状态」段（:2544-2562）纯展示（路径/篇数/附件数/库哈希/冷启）。FFI 无 integrity_check / reindex 接口；库 open 失败时句柄不存在，任何库内修复无从执行。
- **评估结论**：
  1. **可落（零风险，对位 repairBoot 的"只清缓存不动数据"）**：DiagView「库状态」卡下加一行「清理缓存」动作——删 UserDefaults `weatherCacheV1`（天气缓存，WeatherKeyUI.save 已有同款删除先例），记 info `DIAG cache cleared`。图片 URL 缓存为进程内内存态，无落盘缓存可清，不列。
  2. **可落（只读校验）**：同卡加「校验库」动作——以现行 FFI 做 `listMemosJson` 重解析计数 + `libraryHash()` 取值，记 info `DIAG verify memos={n} hash={h}` 并与「库状态」段读数对照；纯读、不写库。
  3. **不落（登记）**：真修复（integrity_check / REINDEX / 隔离库重建）需 storage/FFI 新增接口，属 core 批另行立项；「打开库失败」场景的第二动作（导出 moment.db 副本供取证）涉及 loadFailed 态下设置页可达性核证，一并留待该批。
- **工作量**：小（仅 1+2）。

---

## 建议落码序

1. **G7** log_once / logErrorOnce 原语（G4-6、G12 未命中、G8-6 的前置依赖，必须最先）。
2. **G6 + G10 + G9** Diag 自身小件包（三项同文件同区域：DiagView/DiagLog/DiagLogPage，一版落完互相不干扰）。
3. **G3** 编辑文本打点（9 处，纯加行）。
4. **G4 + G5** 首页与设置族（进入行 + 动作行；G4-6 依赖第 1 步已落）。
5. **G12** wiki 打点（命中普通行 + 未命中 once）。
6. **G8** 先投递扩面（5 类），后呈现上提（抽 ErrBadgeOverlay + 删 EditorView 旧层 + 同步 verify 断言）——两步同版但分开成笔，上提后重点核编辑页不双份呈现。
7. **G14** 可落两项（清理缓存 + 校验库）收尾；真修复登记待 core 批。

每步落码后跑 `verify_ios.sh`；[7] 几何前提组不受本批影响，[4] 数据契约组若因 G8 上提改名需同步更新断言文本。
