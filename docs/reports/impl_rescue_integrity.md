# 救援完整性小批 + 只读入口落码（2026-11-27）

> 状态：**落码完成、未提交、未 bump**（随下一组版，主线定）。基线 HEAD 6ce6cd8（0.9.57 组版全落定）。
> 依据：docs/reports/audit_home_other_deep.md §7「救援小批」（P2-2/P2-3/P2-4、§5.2 c/d、§5.1）+ P2-5（用户 2026-11-27 裁定：只读入口禁用，照做）。
> 开工门：动工时 HEAD 已越 0.9.57 bump 且已跟踪文件零改动（仅未跟踪报告文档），门过后落码。落码期间有兄弟批（Dynamic Type 真跟随、图片页公式、配对二维码、编辑健壮性 E4 等）在同文件并发落码——本批全部 hunk 与之逐段核对零交叠（见文末并发账）。

---

## 1. 看门狗 arm 前移（P2-2）

- 原状（proven）：`armWatchdog()` 只在 `load()` 起点调用，`load()` 由 ListView.onAppear 触发——根视图/ListView 构建期挂死时 onAppear 永不达，看门狗从未 arm、救援浮条永不出（Web 救援层内联 index.html、不依赖 App 构建，无此洞）。
- 落码：`Library.init()` 末尾（judge → writeBootSnapshot 之后、桥接线派发之前）恒调 `armWatchdog()`；`load()` 起点调用保留、只作续期（armWatchdog 自带 `watchdogWork?.cancel()` 取消旧项，语义不变）。安全模式不 arm 的既有 guard（`guard !bootIsSafe` + OPS 可禁）原样在 armWatchdog 内部，前移不改变这两条口径。
- 效果：看门狗覆盖面从「ListView 已出现之后」扩到「进程启动即起」，构建期挂死 12s 后浮条必出。

## 2. 正常模式手动救援入口（P2-3）

- 原状（proven）：正常模式下设置/Diag 页无任何 `bootMode=.safe` 写点，Web `?rescue=1` 在原生无等价物；App 能跑但劣化（缓存损坏型）时用户只能等 streak 攒满。
- 落码：
  - `Library.enterRescueManually()`：与看门狗入口同机制——直接切 `bootMode = .safe(…, source: "manual")`、根分流即时呈现 RescueView，补记 `RESCUE enter … src=manual` 行；不写哨兵、不动数据。从 Diag 页进入时编辑器不可能在席（设置路径与编辑器互斥），无在席冲突面。
  - Diag 页「库状态」卡内、数据自救动作行下方新增按钮，直引新键 `diag.enter_rescue`。
  - `BootMode` source 注记补齐 `watchdog` / `manual` 两值（原注记漏记 watchdog、已与代码漂移，审计 §5.4 a 点名）。
- 五语新键 `diag.enter_rescue`（五包各 +1、键数 360→361，[9] 期望同步改）：zh-CN「进入救援模式」/ zh-TW「進入救援模式」/ en-US「Enter Rescue Mode」/ ja-JP「救済モードに入る」/ ko-KR「복구 모드 진입」。译词从各包既有 rescue 词根（救援/救援/Rescue/救済/복구）。

## 3. 清缓存避让只读副本（P2-4）

- 原状（proven 共域）：只读副本目录在 tmp（`moment-rescue-ro`），经横幅回救援页时只读句柄保留打开；`RescueCacheCleaner.clear()` 对 tmp 无差别清扫，会删正被 SQLite 打开的副本三件套。
- 落码（取审计两案中的「跳过目录」案——不关句柄、不改只读会话状态，ZIP 导出等回页消费面不受影响）：
  - 副本目录名单点化：`Library.readOnlyCopyDirName = "moment-rescue-ro"` 静态常量，`readOnlyCopyDir()` 改引常量（原字面量仅此一处定义，R19-5 锚仍成立）。
  - `RescueCacheCleaner.measure()` / `clear()` 对 tmp 顶层该目录一律跳过（dirBytes 按顶层名/前缀排除、clearContents 按顶层名跳过）；副本自有退出/重进清理路径（prepareNormalStart / enterReadOnly 先删后建），不依赖清缓存回收。

## 4. 哨兵串行化 + streak 虚增收口（§5.2 c/d）

- 串行化（c）：`LaunchSentinelStore` 新增 `update(_:)`——NSLock 锁内 load→改→save 一次完成，仍 `.atomic` 直写、返回前落盘（硬崩可靠性语义不变）；纯读仍走 `load()`。Library 全部 8 个 RMW 写点收敛经 update：launchMark、launchDone（streak 清零一笔 + launchMark 推进）、markScene、launchSuspend、launchResume、launchFailed、recordRescueAction、judgePreviousLaunch 的 streak 递增落盘。主文件 `LaunchSentinelStore.save(` 直调归零（R13-10 锁）。桥侧（MomentBridgeOps）只有 load 只读，不在写面。
- streak 虚增收口（d）：取审计两案中的「救援页推进步名」案——`LaunchStep` 新增 `sceneRescue = "场景·救援"`（`isLoadStep` 按「场景」前缀判非加载步，口径自动成立）；`RescueView.onAppear` 调 `Library.markScene(LaunchStep.sceneRescue)`。安全模式内被强杀时步已非加载步，下次判定走「前台终止 warn 不计数」口径，streak 展示值与 RESCUE enter 行不再随「开救援页又强杀」单调虚增；进/出安全模式的判定逻辑本身未动。

## 5. SMOKE 失败行 + 首帧双口径注记（§5.1）

- `load()` 失败路（catch）在既有「打开库失败」error 行后补 `SMOKE 冷启失败 v=<版本> err=<错误>`，与成功行 `SMOKE 冷启完成 v=…` 同前缀同格式——发版清单按 SMOKE 检索不再漏计失败冷启。
- 双口径注记（纯注释）：load 收尾「首帧」步痕处注记其为加载链面包屑（数据就绪后写），与 ListView 量测的 `firstFrameMs`（真实首帧渲染时刻）是两个口径；`markFirstFrame()` 定义处互相指引。

## 6. 只读入口禁用（P2-5，用户裁定）

- 原状（proven）：只读态下既有卡片仍可点进编辑页打字，仅在 persist 时被 writeBlocked 拦下弹 notice，编辑成果当场丢失、入口无只读预期。
- 落码：`Library.readonlyEntryBlocked(_ kind:)`（与 writeBlocked 同构：logOnce 记 `READONLY entry-blocked kind=<open|create>` + notice，notice 文案与只读横幅同源 `rescue.readonly_banner`）；ListView 两条漏斗首行守卫——`openMemo`（kind=open）、`createAndOpen`（kind=create），拦截即返回、不进编辑页。writeBlocked 门面拒写仍是最终兜底，未动。
- **只读入口全集清单**（逐个核毕）：

| # | 入口 | 路径 | 处置 |
|---|---|---|---|
| 1 | 窄屏列表卡点按（含搜索结果行——同一行构造） | row onTap → `openMemo` | 漏斗守卫 open |
| 2 | 窄屏列表卡长按菜单「打开」 | contextMenu → `openMemo` | 同上 |
| 3 | 宽屏网格方卡点按 | squareCard onTap → `openMemo` | 同上 |
| 4 | 宽屏网格方卡长按菜单「打开」 | contextMenu → `openMemo` | 同上 |
| 5 | 折叠组卡点按 | 折叠态 = 展开动作、不进编辑器；展开后走 #1 | 无需守卫（展开非编辑入口） |
| 6 | 窄屏新建行 / 宽屏新建方卡 / 窄屏空态钮 / 宽屏空态钮 | 四路 → `createAndOpen` | 漏斗守卫 create（新建卡呈现层只读隐藏为既有口径，守卫兜底空态路） |
| 7 | 紧凑页眉态下的列表行 | 与 #1/#2 同一行构造（页眉形态不改变行入口） | 同 #1 |
| 8 | 编辑器内反链/wiki 打开 | `openLinkedMemo`（宿主 replaceTopEditor） | 不守卫：仅在编辑器已在席时可达，只读态编辑器本身不可达（#1–#7 全堵）；persist 门面仍兜底 |
| 9 | 桥 editor_open / 自检驱动打开 | BridgeNavigationChannel → 宿主 pushEditor | 非 UI 入口，不在本批面：桥分发器已有只读回读面（rescue_status.readOnlyOpen），其写面一致化属审计 §5.6 b 另一批 |
| 10 | 图片页/附件页 | 只读浏览面、无编辑入口 | 无需守卫 |

## 断言（verify 增补，本机自跑）

- [9] 键数期望 360→361（注释账同步：+1 救援完整性批 diag.enter_rescue）。
- [13] 新增 **R13-10**（哨兵 update 在位 + 主文件 save 直调 = 0 + sceneRescue 步名/推进点）、**R13-11**（enterRescueManually + src=manual + Diag 行直引新键 + BootMode 注记含 watchdog/manual）、**R13-12**（SMOKE 冷启失败行与成功行并存）。
- [19] 新增 **R19-13**（init 段含 armWatchdog() + 全文件恰三处：定义/init/load）、**R19-14**（readOnlyCopyDirName 单点 + 清理器 excluding 跳过）、**R19-15**（readonlyEntryBlocked 定义/记行 + 两漏斗守卫恰两处）。
- 本机自跑：新增 6 条全 ✓、[9] 361 ✓、本批领地既有条目（R13-1..9、R19-1..12）全 ✓ 不回潮。全量 285 ✓；✗ 共 4 条——`ipa 陈旧`、`产物语言包与 Web 源不一致` 为既有产物类（tree 构建自解）；`图片页判定高口径不在`、`J1-2 热区整页化口径不对` 经基线对照定因**非本批**：stash 本批全部改动后在干净 HEAD（6ce6cd8）自跑为 277 ✓ / 仅 2 条产物类 ✗，两条新增 ✗ 的断言对象（ImagePageView 的 `geo.size.height - 66` 已被在途图片页批改为 -126 口径、EditorView 的 `ui.viewH - 208/192/200` 已被在途编辑批改写）均在本批领地之外，属兄弟批落码中态、待其断言同步后自解。本机无 swiftc，Swift 编译级随组版 tree 冒烟把关。

## 并发账（纪律留痕）

落码期间兄弟批在 MomentApp.swift / verify_ios.sh / MomentBridgeSettings.swift / TitleTextField.swift 持续落码（Dynamic Type、图片页、配对二维码、E4 等）。本批 hunk 仅落在：Library 段（BootMode 注记、init、哨兵写点、判定、只读门面、副本目录、看门狗段、load 失败路）、DiagView 库状态卡、ListView 两漏斗、MomentLaunch.swift、MomentRescue.swift、五语包各一行、verify [9]/[13]/[19]——与兄弟批段落（EditorModel/EditorView/MdBlock/Settings 族/ImagePageView/Radius/[32]）逐段零交叠；基线对照用 git stash 整体暂存后已无冲突还原，兄弟批 hunk 逐字节完好（还原后 git status 清单与暂存前一致）。

## 真机终判点

1. **看门狗覆盖**：正常冷启无浮条（12s 内就绪自撤口径不变）；构建期挂死类故障下次复现时，12s 浮条应出（此前永不出）。
2. **手动入口**：设置 → 诊断日志 → 库状态卡「进入救援模式」→ 即时切到安全模式页，Diag 见 `RESCUE enter … src=manual`；救援页「尝试正常启动」可回正常态、数据完好。
3. **清缓存×只读副本**：安全模式只读打开（副本模式）→ 回救援页 → 清缓存 → 再回只读浏览/导出 ZIP 应正常（此前副本三件套被删、只读浏览崩坏）。
4. **streak 虚增**：进安全模式后在救援页强杀 App，下次启动 LAUNCH 行应为「上次会话未正常收尾（停在：场景·救援）」warn 口径、streak 不 +1。
5. **只读入口**：只读态点任意卡（列表/网格/搜索结果/菜单打开）与新建入口——不进编辑页、弹只读提示（与横幅同文案），Diag 见 `READONLY entry-blocked kind=open|create`；回正常态后点按恢复正常打开。
6. **SMOKE 失败行**：开库失败冷启时 Diag 应见 `SMOKE 冷启失败 v=` 行（与成功版 `SMOKE 冷启完成` 对照）。
