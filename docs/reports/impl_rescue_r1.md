# 落码报告：原生自救机制 R1 + 热更新指令通道（0.9.45）

日期：2026-11-27。规格真源：`plan_native_rescue.md`（S1/S2/S3/S6/S9/S10/S11）+ S13 热更新指令通道（用户 2026-11-27 新规，含端点更正）。范围 = R1 + S13；R2（只读 FFI）、R3（看门狗/快照环/缓存清理）只留附着点。主文件 `rust/apps/ios/app/MomentApp.swift`（行号为落码后终态）；未 commit、未跑构建/冒烟（主线在 tree 收口）。

## S1 哨兵加密 + 文件直写

- 步名集中定义 `enum LaunchStep`（MomentApp.swift:332）：开库 / 开库·FFI / 读数据·列表 / 读数据·解析 / 写种子 / 再水化·待删 / 附件名表 / 附件类型 / 首帧 / 会话中 / 场景·首页 / 场景·编辑页，含 `isLoadStep` 分级（会话/场景/首帧 = 非加载步）。全仓 `launchMark(`/`loadStepMark(`/`markScene(` 调用零散写字面量（verify R13-1 断言）。
- 步点落位：load() 开库 :627 段、开库·FFI（open 调用前）、写种子（空库分支）；reload() 读数据·列表 :698、读数据·解析、再水化·待删、附件名表 :743；refreshAttachmentTypes 内附件类型；didLoad 置真前首帧（load 成功主线程段）；launchDone 推进会话中。markScene 两调用点（:7722 编辑页、ListView 首页）改传 `LaunchStep.sceneEditor/sceneHome`。
- 哨兵存储 `LaunchSentinel` + `LaunchSentinelStore`（:367/:377）：落 `Application Support/diag/launch-sentinel.json`，每步 `Data.write(.atomic)` 同步直写；字段 busy/step/streak + lastRescueAction/lastRescueAt（S6）。读序文件优先、缺失回退 UserDefaults 三键只读一版。写失败记 `LAUNCH sentinel write failed`（logOnce，launchMark :492）。
- 新增 `loadStepMark`（:508）：reload 内步点专用守卫——哨兵处于会话/场景步时不记（导入换库等会话内 reload 不得把步倒退回加载步，否则前台死亡被误判启动死亡）；加载态/未置态照常记。附件类型的步点同样经此守卫。

## S2 判定前移 + bootMode

- `Library.init()`（:488）末尾同步执行 `judgePreviousLaunch()`（:577）；load() 内旧判定调用已删（全文件 judgePreviousLaunch 恰两处：定义 + init 调用，verify R13-2）。
- 判定逻辑：busy 且停加载步 → streak+1 落盘、LAUNCH error 行（沿旧格式 + 附 `lastRescue=`，见 S6）；streak≥3 沿用 `notice.launch_streak`；streak==1 置 `launchOnceNoticePending`，load 成功且 notice 为空时兑现 `notice.launch_once`（load 成功段）；streak≥2 → `bootMode = .safe(streak:step:source:"streak")`。停会话/场景/首帧步 → warn 行、不计数、永不进安全模式。
- 判定同时读指令缓存：`OpsDirectives.cached().forceSafeMode` 在位 → 直接 .safe（source="ops"）。进安全模式统一记 `RESCUE enter streak=<n> step=<step> src=<source>`（error）。
- 结果发布：`@Published bootMode`（BootMode 枚举 :355）、`prevLaunchStep`、`prevLaunchStreak`、`bootIsSafe`、`isDbOpen` 计算属性。根 ZStack（:16221）按 bootIsSafe 分流：.safe 渲染 RescueView、不构建 ListView；SplashHostView 仅正常模式挂载（安全模式 didLoad 不置真，挂了会永久盖住救援页）。
- 附带顺序修正：launchDone() 由 reload 后后台线程改到 didLoad 主线程段（首帧标记之后），使「首帧」步点与 S1 表对位（首帧 = didLoad 置真前）。

## S3 RescueView 骨架

- `struct RescueView`（:15953，段头注释含红线与 R2/R3 附着点）。构建路径只依赖 DiagLog + FileManager 元数据 + OpsDirectives 缓存 + Library 已判定状态（bootMode/prevLaunch*），不打开库、不调可写 FFI（verify R13-5 段内扫描 upsertMemoJson/removeMemo/putAttachment/MomentLibrary.open 零命中）。
- 呈现：标题 rescue.title + 边界段 rescue.boundary（glassCard）；状态区只读数据组（上次停步、streak、mode 来源、库文件字节数、Diag 当天行数+归档数、OPS 指令摘要、上次救援动作）；动作区主按钮 + SetRow 率动作卡（SetRow/rowDivider/glassCard/T.* 既有口径，无新造视觉、无内联裸值——状态行的键宽/字号沿 DiagLine 呈现惯式）。
- 动作 1 尝试正常启动 `tryNormal`（:16151）：记 RESCUE action + recordRescueAction + RESCUE exit to=normal → bootMode 切 .normal → ListView 构建走常规 load()。救援层自身不新增任何写；load() 既有语义（待删过期真删、空库写种子）是正常加载本身的行为，非救援写面。
- 动作 2 导出诊断 `exportDiag`（:16162）：走 DiagView 同链——抽出静态 `DiagView.buildExportFile(library:extraSections:)`（:4237）与 `envHeaderText(library:)`（:4203），DiagView 实例面改调它（行为不变：失败行/成功行口径保留），救援侧追加哨兵摘要段（==== RESCUE sentinel ====）后走系统分享。只依赖 DiagLog，安全模式可用。
- 动作 4 导出备份 ZIP `exportZipAction`（:16194）：lib 为 nil（isDbOpen=false）时 SetRow meta 显示 rescue.export_zip_unavailable 且动作内 guard 拦截，不触发假成功；库已打开时走 Library.exportZip() + 分享。
- 动作 3 只读（R2）、动作 5 清缓存（R3）本批不落，文案键已备（见 S10）。

## S6 救援留痕

- `RESCUE enter streak=<n> step=<step> src=<streak|ops>`（判定点，error）；`RESCUE action <normal-retry|export|zip>`（各动作前，info）；`RESCUE exit to=normal`（info）。readonly/cache-clear 的 action 名随 R2/R3 落地时同模板补。
- 跨启动留痕：`Library.recordRescueAction`（:562）写哨兵 lastRescueAction + 时刻；下次启动 LAUNCH 行（error/warn 两支）尾附 `lastRescue=<action>`；RescueView 状态区亦呈现 lastRescue。

## S9 初始化延后

- refreshAttachmentTypes 移出首帧前同步段：reload 收尾改调 `deferRefreshAttachmentTypes()`（:1061，didLoad 后 +0.3s）；原同步调用点删除（verify R13-6 断言 reload 段无直调）。
- Diag 结构写盘延后：loadIfNeeded 的冻结合并与 autodel 的**数据结构变更仍在 load 时完成**（冻结语义与 0.9.44 零依赖热修不动，DiagLog 类体未新增 Fmt./LangStore/Lang.t( 引用，[12] 模拟通过），只把结尾的同步 `persist()` 改为置 `structuralDirty` + `scheduleStructuralFlush()`（:3254；2s 定时或 Library 在 didLoad 后主动 `flushStructuralPersist()` :3278 提前刷）。未及 flush 即崩溃时磁盘仍是旧结构，下次加载重演冻结/删除——派生自存量数据，幂等无损。
- 种子写入不延后（空库首启正确性优先）；refreshAttachmentNames 不延后（列表封面/判图首帧即需）。

## S13 热更新指令通道

- `OpsDirectiveSet` + `OpsDirectives`（:3456）+ guard 步名 `OpsStep`（:3426）。缓存 `Application Support/diag/ops-directives.json`（与 Diag 同域，路径共用 `DiagLog.diagDirPath()` :3184）。
- 端点双源（常量集中，按托管实际建成口径）：主 `https://moment-ops.overtrees.workers.dev/ops.json`（Cloudflare Worker，src=worker）、备 `https://overtrees.github.io/moment-ops/ops.json`（src=github）。原定的 moment-ops.pages.dev 直传在 CF 边缘持续 500 已弃用，代码零引用。
- 拉取：GET 带 `?t=<unix秒>` 绕缓存、超时 6s、HTTP 200 且白名单解析成功才算成功、第一个成功为准；成功落缓存（原子写）+ 更新 @Published current/lastSource + 记 `OPS directives fetched src=<worker|github> steps=<n> forceSafe=<0|1>`；全失败记 `OPS directives fetch failed`（warn，logOnce）。
- 白名单解析 `sanitize`（JSONSerialization 逐字段类型核对）：只认 version（只记不判）/disableSteps（元素须为 String，非串元素剔除）/forceSafeMode（须为 Bool）；未知字段忽略、整包坏损返回 nil 当空指令。纯函数无副作用不记日志——DiagLog 的 guard 点反向调用它，保持无环。
- 消费点：① RescueView「检查热修复」动作 `checkOps`（:16181）→ fetch 后刷新状态区指令摘要；forceSafeMode 在位时主按钮下明示数据行（OPS forceSafeMode=1 · next launch returns to safe mode）。② 正常模式 didLoad 后 `OpsDirectives.refreshInBackground()`（load 成功段 :660，fire-and-forget，为下次启动备缓存；本次 guard 读启动时缓存，口径与 Web 救援开关「重启即生效」同）。③ guard 点三处（verify 断言 `OPS skip step=` ≥3）：refreshAttachmentTypes（点名「附件类型」跳过，判图回落扩展名）、DiagLog.flushStructuralPersist（点名「Diag冻结写盘」跳过结构 flush）、ListView.onAppear 天气自动刷新（点名「天气自动刷新」跳过，:13551）。④ 判定消费 forceSafeMode（见 S2）。
- 核心步（开库/读数据/解析/再水化）不设 guard、指令点名也无效，OpsDirectives 段头注释写明。

## 语言键（S10）

- 五语包（rust/apps/web/lang/*.json）各加 17 键：notice.launch_once + rescue.* 16 键（title/boundary/status_prev_step/status_streak/try_normal/export_diag/open_readonly/export_zip/export_zip_unavailable/cache_clear/cache_clear_confirm/watchdog_bar/enter/readonly_banner/readonly_write_blocked/check_ops），zh-CN 原文、其余四语实译；五包键集完全一致、各 324 键。
- **偏离**：简报定 16 键 → 323。S13 的「检查热修复」动作在 S10 的 16 键中无语义可复用的文案（export_diag 是导出诊断、watchdog_bar 是 R3 浮条），故多加 rescue.check_ops 一键 → **324**。verify [9] 相应新增键数断言 = 324 并注明来由（307 基线 + 17）。后续批次的键数口径（天气批 0.9.46 的 316 口径等）须按 324 基线顺延修正。
- [9] 的 Swift 引用检查是「引用键 ⊆ 五包」方向，R2/R3 预置键（open_readonly/readonly_banner/readonly_write_blocked/enter/cache_clear/cache_clear_confirm/watchdog_bar）未被引用不触发失败，无需豁免。

## verify [13] 断言清单（verify_ios.sh:717 起）

- R13-1（S11#1）：launch-sentinel.json 在位 + LaunchStep 枚举含加密子步字面量 + 代码行（去注释）无 launchMark("/loadStepMark("/markScene(" 散写字面量。
- R13-2（S11#2）：judgePreviousLaunch 全文件恰两处（定义 + init 调用）、ListView 段无判定调用。
- R13-3（S11#3）：根段含 bootIsSafe 且 RescueView(library 行号 < ListView(library。
- R13-4（S11#4 的 R1 子集）：RescueView 段含 buildExportFile/func tryNormal/func exportDiag/func exportZipAction + 「R2 附着点」标记。
- R13-5（S11#5）：RescueView 段（含段头注释）零 upsertMemoJson/removeMemo/putAttachment/MomentLibrary.open。
- R13-6（S11#10）：reload 段含 deferRefreshAttachmentTypes() 且无 self.refreshAttachmentTypes() 直调；loadIfNeeded 段含 scheduleStructuralFlush() 且无同步 persist() 直写行。
- R13-7（S13）：双源端点常量在位、OpsDirectives 段含 "disableSteps"/"forceSafeMode"/func sanitize/OPS directives fetched src= 字面、`OPS skip step=` 计数 ≥3、RescueView 段含 OpsDirectives.shared.fetch、判定消费 OpsDirectives.cached().forceSafeMode。
- [9] 新增：五包键数 == 324 断言（verify_ios.sh:266 ok 行）。
- 自验（本机模拟，未跑全量 verify）：[13] 七组片段、[12] 零依赖、[9] 键集/键数/引用键/CJK 扫描均通过；大括号配平 3101/3101（基线 2997/2997 同型）；bash -n 两脚本通过；旧符号 inspectPreviousLaunch/kLaunch* 零残留。全量 smoke_ios.sh 由主线在 tree 跑。

## 偏离规格与取舍

1. **键数 324 而非 323**：见上（S13 动作需要 rescue.check_ops）。
2. **Diag guard 的辖域**：S13 guard 点「Diag 冻结合并写盘段」落在 flushStructuralPersist 的专用结构 flush 上。DiagLog 的普通记行节流落盘与结构落盘共用同一个 persist()（写 today+archives 全量内存态），结构上不可分——guard 跳过专用 flush 后，后续记行的节流落盘仍会把已合并的内存态写出（数据正确）。即 guard 辖「本段」而非「一切写盘」，与 S9 的保守口径一致；若将来要真隔离，需拆 persist 为分文件写盘，属 R3 结构活。
3. **MathImageStore 预热 guard 点不存在**：全仓无预热调用（entry 懒加载、webview 首用才建）。按「不存在则只留步名常量 + 附着点注释」处理：OpsStep.mathPreheat 已登记，MathImageStore 类头注释（:10619）写明新增预热必须先查 isDisabled。
4. **Diag 导出链抽取**：DiagView.exportEverything 是 private 实例方法，RescueView 无法直接调；抽静态 buildExportFile/envHeaderText 共用（DiagView 改调它，成功/失败记行口径不变），满足「走同一链」。
5. **ZIP 置灰呈现**：SetRow 无 disabled 态，置灰以 meta 原因文案 + 动作内 guard 拦截实现（不触发 exportZip 的失败行，避免假动作留痕）。
6. **launchDone 时机微调**：由 reload 后后台线程改到 didLoad 主线程段（首帧步点对位 S1 表），此间死亡按加载未完成计数，更贴 S1 语义。

## 留给 R2/R3 的附着点

- R2（只读模式）：RescueView 段头注释标「R2 附着点」（动作 3 插入位：导出诊断与导出 ZIP 之间）；前置件已备——FFI 侧待加 openReadonly + 只读句柄类型（契约 22→23 项，verify [13] 届时补 S11#6）；Library.isDbOpen 已就位（只读态打开后 ZIP 动作自动可用）；文案键 rescue.open_readonly/readonly_banner/readonly_write_blocked/rescue.enter 已入包；S6 的 RESCUE action readonly 与 exit to=readonly 记行名已在规格模板内预留。
- R3（看门狗/快照环/缓存清理）：RescueView 段头注释标「R3 附着点」（动作 5 + 浮条挂载位）；文案键 rescue.cache_clear/cache_clear_confirm/watchdog_bar 已入包；Diag 侧 flushStructuralPersist 的 persist 分文件拆分（见取舍 2）可与快照环同批做；OpsStep.mathPreheat 待公式预热落地时接 guard。
- UserDefaults 三键只读回退保留一版（0.9.46 可删 LaunchSentinelStore.load 的回退支 + LangStore.hasExistingState 的旧键名清单同步评估）。

## 改动文件

- rust/apps/ios/app/MomentApp.swift（S1/S2/S3/S6/S9/S13 + 版本文本 0.9.45）
- rust/apps/ios/app/build-app2.sh（0.9.45 / build 72）
- rust/apps/ios/app/verify_ios.sh（[9] 键数断言 + [13] 组七断言）
- rust/apps/web/lang/{zh-CN,zh-TW,en-US,ja-JP,ko-KR}.json（各 +17 键，共 324）

## 文件拆分（0.9.45 拆分批，拒绝上帝文件）

本批新增代码原全数落在 MomentApp.swift（拆分前 16,856 行），按用户开发规范「按作用分类独立、拒绝上帝文件」拆为三个独立文件；存量代码与 Library/DiagLog 类本体不搬家。行号为拆分前 MomentApp.swift 原始行号。

### 映射表

| 新文件 | 内容 | 原行段 | 新文件行数 |
|---|---|---|---|
| MomentLaunch.swift | LaunchStep 步名定义 + LaunchSentinel + LaunchSentinelStore（哨兵文件直写、UserDefaults 只读回退、写失败留痕） | 327–350 + 362–408 | 80 |
| MomentOps.swift | OpsStep + OpsDirectiveSet + OpsDirectives（双源端点常量、白名单解析、拉取、缓存、guard 查询） | 3417–3584 | 178 |
| MomentRescue.swift | RescueView 本体（含嵌套 RescueUI） | 15938–16202 | 275 |
| MomentApp.swift | 拆后 16,348 行（−508 = 代码 504 + 分隔空行 4） | — | — |

留守说明：BootMode（原 :355）留在 MomentApp.swift——它与 Library 的 bootMode 判定同文件同主题，不在拆分映射内；Library 的 judgePreviousLaunch/recordRescueAction/tryNormalStart 相关方法、根 ZStack 的 bootMode 分流、DiagLog.flushStructuralPersist、DiagView.buildExportFile 均按简报留守原文件，只留跨文件引用。

### 可见性调整清单

**无调整。** 被拆符号原本即 internal（无顶层 private/fileprivate）；成员级 private 均在随迁的类型体内自洽（RescueView 的私有成员与嵌套类 RescueUI 随 RescueView 整段迁出；OpsDirectives.fetchFrom 仅类内调用；@Published private(set) 语义不变）。跨文件引用目标（DiagLog、Lang、T、SetRow、glassCard、CardPressStyle、ShareSheet、DiagView.buildExportFile/envHeaderText）经逐个核查均为 internal，同模块内可见。拆分前已核查：被拆三段不引用 MomentApp.swift 内任何文件级 private 符号（编辑页私有成员与 NativeSplash 私有族引用计数均为 0）。

新文件 import 按实际依赖最小化：MomentLaunch = Foundation；MomentOps = Foundation + Combine（ObservableObject/@Published）；MomentRescue = SwiftUI + Foundation。各文件头注释标注职责与所属批次（0.9.45），对齐既有文件头风格。

### 构建接入（build-app2.sh）

swift-frontend 调用由两次增至五次：原 bindings（moment_ffi.o）与 MomentApp（app.o）两次保留，并各补三新文件作次级输入（否则主文件编译时跨文件符号不可见）；新增三次调用分别以 MomentLaunch/MomentOps/MomentRescue 为 -primary-file、其余全部 Swift 文件（含 bindings）作次级输入、$COMMON 原样，产出 launch.o/ops.o/rescue.o；最终 clang 链接行加入三 .o。

### verify 同步（verify_ios.sh [13]）

- 新增文件变量 LAUNCH/OPS/RESCUE（脚本头 SRC 之后）。
- R13-1：LaunchStep 取段与 launch-sentinel.json/enum LaunchStep 存在性改指 MomentLaunch.swift（取段范围改为 enum LaunchStep → struct LaunchSentinel）；散写字面量负检仍查主文件（launchMark 等调用点留守 Library）。
- R13-4/R13-5：RV 段改从 MomentRescue.swift 取（「── 安全模式页」段头注释至文件尾）。
- R13-7：OPSSEG 改从 MomentOps.swift 取（final class OpsDirectives 至文件尾）；双源端点存在性改指 MomentOps.swift；guard 计数与判定消费仍查主文件（消费点留守）。
- 新增 R13-8（轻断言）：三新文件存在且各自含定义（enum LaunchStep/enum LaunchSentinelStore/final class OpsDirectives/struct RescueView），MomentApp.swift 内四定义零残留（只许引用）。
- 断言语义与既有条数不变（R13-1..7 原样，仅 R13-8 为新增）。[12] 及其余组未改动：[12] 的 DIAGBODY 取段（DiagLog→FlowLayout）原跨 Ops 段、拆后段变短，实跑仍绿；[4] 的 launchInProgress 字面在 LangStore 存量键清单（拆后 :3791 一带）仍在，实跑仍绿。

### 自验结果

- 纯移动证据：与拆分前备份 diff 恰 4 个 hunk、删除 508 行、新增 0 行——整段剪切粘贴，无代码内容改写。
- 大括号配平：MomentApp 3029/3029、MomentLaunch 11/11、MomentOps 25/25、MomentRescue 36/36；四文件合计 3101/3101，与拆分前基线（本报告前文）一致。
- 定义零残留：MomentApp.swift 内七个被拆符号（LaunchStep/LaunchSentinel/LaunchSentinelStore/OpsStep/OpsDirectiveSet/OpsDirectives/RescueView）定义 grep 计数为 0；新文件内定义齐位；BootMode 留守（拆后 :330）。
- 接缝目检三处干净（MemoItem→BootMode→Library、DiagLog→diagFiltered、前置类型→@main，各留恰一个空行）。
- bash -n build-app2.sh、verify_ios.sh 均通过。
- 本机实跑 verify_ios.sh：源码相关组全绿——[9] 源侧断言全 ✓（仅产物语言包一条红）、[12] ✓、[13] R13-1..R13-8 全 ✓，[1]–[8]/[10]/[11] 亦全 ✓。全场仅两条红，均为产物陈旧类（[5]「ipa 陈旧（早于 MomentApp.swift）」、[9]「产物语言包缺失或与 Web 源不一致」），系源码刚变更未重建所致，构建后消除，不算回归。
- 未 git commit、未跑完整构建/冒烟（按分工留主线在 tree 收口）。
