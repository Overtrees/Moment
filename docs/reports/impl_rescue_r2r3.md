# 自救 R2 + R3 落码记录（未提交、未 bump，版号由主线排）

依据：`plan_native_rescue.md` 的 S4/S5/S7/S8 与 Diag guard 真隔离项；R1 已落实现见 `impl_rescue_r1.md`。本批只动救援/启动/运维文件与 crates/ffi，未碰设置区与编辑器区。

## 一、逐项对规格对账

### S4 只读打开（R2）——已落

- **storage 层**（`crates/storage/src/lib.rs`）：`Store` 加 `read_only` 标记；新增 `Store::open_readonly(path)` —— 以 `SQLITE_OPEN_READ_ONLY` 打开（不建库、不迁移、不写 journal），打开后以 sqlite_master 探针校验 memos 表存在，缺失报 `InvalidData "not a moment library"`（防对空/错文件假成功）。`list_memos_tolerant_impl` 在只读句柄下跳过隔离落盘（隔离是写操作）；可写句柄的隔离落盘失败仍整体报错，行为不变。
- **FFI 层**（`crates/ffi/src/lib.rs`）：`MomentLibrary` 新增第二构造子 `open_readonly`（`#[uniffi::constructor]`），Swift 侧生成静态工厂 `MomentLibrary.openReadonly(path:)`。bindgen 已按红线重跑回拷（见第二节）。
- **门面**（Library）：`OpenMode` 四态（none/readWrite/readOnly/readOnlyCopy）+ `isReadOnly`。`enterReadOnly()` 先直开只读；失败回退副本路径——db 三件套（moment.db/-wal/-shm）拷入 tmp 的 `moment-rescue-ro/` 目录后以普通方式打开副本（mode=copy）；再失败记 `RESCUE readonly open fail err=` 并复位留页。成功记 `RESCUE readonly open ok mode=direct|copy` + `RESCUE exit to=readonly`，bootMode 回 .normal 进只读浏览。
- **门面拒写**：写入口统一经 `writeBlocked(kind)` ——只读时 logOnce 记 `READONLY write-blocked kind=<kind>` + 既有 notice 槽位呈 `rescue.readonly_write_blocked`，非只读时恒 false 零开销。已挂 kind：persist（persist 全量写）、seed（load 种子分支双保险——正常流程种子在进只读前已完成，此为防线）、delete（persistDeletionMark/softRemove/undoDeletion/commitPendingDeletion/remove 五处）、attach（putAttachment/setAvatar）、import（commitStagedImport）。`create()` 另补 `&& !isReadOnly` 防幻影篇入内存列表。
- **reload 跳真删**：只读态待删过期分支不执行真删——logOnce 记 `READONLY write-blocked kind=delete` + 明细行「只读态待删过期仅隐藏 id=…」，删除标记留库，待下次正常打开由既有过期清理真删。
- **呈现与退出**：ListView 列表形态与宽屏 grid 形态均在 notice 槽上方加只读横幅（锁形图标 + `rescue.readonly_banner` + 「进入救援」钮），两形态的新建卡在只读态隐藏。退出唯一路径：横幅钮 → `exitReadOnlyToRescue()`（以进入前来源恢复 .safe）→ 页内「尝试正常启动」→ `tryNormal()` 先调 `prepareNormalStart()`（关句柄、删副本目录、清待删调度与内存列表并 bump 归组版本）再回 .normal，ListView 重建触发常规 load()。只读态不提供「切可写」钮。只读句柄打开后 RescueView 的 ZIP 导出行随 `isDbOpen` 解灰可用（走既有只读查询链）。

### S5 启动状态快照环（R3）——已落

- `RescueSnapshot` + `RescueLogStore` 落在 MomentLaunch.swift（与哨兵同文件、同纪律：Foundation-only、直写、失败静默）。文件 `diag/rescue-log.json`，环长 20（`ringLimit`），整环 JSON 原子写。
- **写入点**：Library.init 在 `judgePreviousLaunch()` 之后调 `writeBootSnapshot()` ——先折入上次会话的待记动作（见下），再 append 本次判定点快照。字段只有元数据：ts / appVersion / systemVersion / prevStep / streak / bootMode / dbBytes / diagToday / diagArchives / diskFreeBytes；memoCount/attachCount 在本次 load 成功后经 `updateLatest` 补写（同环同条），并记 `BOOT snap db=… memos=… diag=…` 摘要行。字段黑名单由 verify R19-8 锁：快照结构内无 title/content/fileName。
- **动作折行**：`Library.recordRescueAction` 同步 `RescueLogStore.markAction`（往最新一条的 actions 数组追加：normal-retry/diag/ops/readonly/zip/cache-clear）；下次启动 writeBootSnapshot 先 `drainActionMarks` 取出并清空，记一行 `RESCUE log actions=<csv> lastSnap=mode=… db=… memos=…` 后再 append 新条——快照环不依赖 Diag 存活即留痕。
- **消费面**：RescueView 状态区新增 snap（最新）/ snapPrev（上次启动）两行并列（`mode= db= memos= streak=` 数据行口径）；Diag 导出经 `buildExportFile` 附入整环文本（`RescueLogStore.exportText()`，对位 Web W7 第三段，DiagView 与 RescueView 两条导出链共用）。

### S7 清除可再生缓存（R3）——已落

- RescueView 动作区在 ZIP 行后新增「清除缓存」行（次级动作、destructive 确认弹窗，文案 `rescue.cache_clear_confirm` 已含「不会删除笔记与附件」定位）。
- `RescueCacheCleaner`（MomentRescue.swift）：清单封闭三处——`URLCache.shared.removeAllCachedResponses()`、`Library/Caches` 目录内容、`temporaryDirectory` 内容（导出残留）。按构造只引用 cachesDirectory 与 temporaryDirectory，零 Application Support、零 UserDefaults；边界由 verify R19-10 锁（清理器代码段内出现 applicationSupportDirectory 即红）。
- 动作行：`RESCUE action cache-clear bytes=<清前字节数>`（measure = URLCache 当前磁盘占用 + 两目录递归求和），并经 recordRescueAction("cache-clear") 进快照环折行。

### S8 启动看门狗 12s（R3）——已落

- 阈值单一定义 `Library.watchdogSeconds = 12`（对齐 Web WATCHDOG_MS）。`load()` 入口 arm（bootIsSafe 不 arm——已在救援页无需再报）；arm 前查 OPS 步名「看门狗」（MomentOps.OpsStep.watchdog，本批按既有登记体系新增一步），被禁记 logOnce `OPS skip step=看门狗` 不 arm。
- 触发：12 秒未 didLoad → 记 error 行 `RESCUE watchdog fired step=<哨兵当前步名>`（步名取 LaunchSentinelStore 的 prevStep——「卡在哪一步」与哨兵同源）+ `watchdogFired = true`。load 成功/失败收尾均 cancelWatchdog。
- 浮条 `WatchdogBar`（MomentRescue.swift）挂根 ZStack、位于 SplashHostView 之上（挂死时开屏正驻留，浮条必须压得住它），bootIsSafe 时不挂。构成对位 Web W3：底部浮卡 + `rescue.watchdog_bar` 文案 + 「进入救援」钮（`enterRescueFromWatchdog()`：bootMode=.safe + `RESCUE enter … src=watchdog`）+ 「×」关闭钮（只撤条不记动作）。应用晚到就绪由根视图 `onChange(of: didLoad)` 自动撤条。

### Diag guard 真隔离（R3，取代 R1 取舍 2）——已落

- 落盘拆为分文件出口：`persist()`（today+archives 双写）只供结构 flush；新增 `persistToday()` 为记行唯一出口。archives.json 的唯一写出口收归结构 flush（OPS「诊断落盘」guard 辖区）。
- `flushStructuralPersist` 把清脏移到 guard 判定**之后**：被指令跳过时脏标保留、两文件都不写——此后记行写在结构脏未清期间一律并入结构 flush 等待（普通行催 2s 定时、error 行立即催 flush），磁盘恒为一致快照，永不出现「today 已冻结、archives 未冻结」半态。guard 的停写自此真正生效：救援路径的 Diag 写盘不可能绕过 guard 反噬启动。
- 代价（已在代码注释与本节明示）：guard 生效期间本会话 Diag 只活在内存（环上限 300 行），进程被杀即丢；但结构变更本身不落盘，下次启动从磁盘存量重演冻结/自动删除，幂等无损。
- 连带：`freezeToday()` 与 `applyAutodelete()`（含设置页开关触发路径）在实际变更后置 structuralDirty 并调度结构 flush（此前仅 loadIfNeeded 尾部统一置脏，运行期 autodel 的落盘时机靠记行顺带——现归口径一致）。

## 二、契约 checksum 变更清单（22 → 23）

bindgen 已重跑（工具 moment-bindgen-tool，crate moment_ffi），新 bindings 与旧版 diff 纯增量，回拷三文件（moment_ffi.swift / moment_ffiFFI.h / modulemap 无变化）。

| 项 | 变化 |
|---|---|
| `uniffi_moment_ffi_checksum_constructor_momentlibrary_open_readonly` | **新增 = 7751** |
| 其余 22 项（构造子 open + 21 个方法） | **全部未变**（逐项比对旧 bindings 一致） |
| 契约断言表（crates/ffi `CHECKSUMS`） | 22 → 23 行，新增行与 bindings 对账一致 |
| verify [6] | ok 文案计数同步「22 项」→「23 项」（双向比对逻辑未动） |

`cargo test -p moment-storage -p moment-ffi` 本机全绿：契约测试 `checksum_contract_matches_bindings`（23 项）、新增 storage 测试 `readonly_open_reads_and_refuses_writes`（只读打开读通、写被 SQLite 拒、探针拒非 Moment 文件、list_tolerant 只读不落盘隔离）、新增 ffi 测试 `readonly_constructor_opens_existing_db`。

## 三、看门狗与快照环的打点形态（汇总）

- 看门狗：arm 无行（高频路径不噪音）；跳过 `OPS skip step=看门狗`（logOnce）；触发 `RESCUE watchdog fired step=<步名>`（error 级）；进救援 `RESCUE enter … src=watchdog`。
- 快照环：判定点 append（init 内、无 Diag 行）；动作折行 `RESCUE log actions=<csv> lastSnap=mode=… db=… memos=…`；load 成功补写后 `BOOT snap db=<n> memos=<n> diag=<n>`（logOnce "boot-snap"）。
- 只读：`RESCUE action readonly` → `RESCUE readonly open ok mode=direct|copy` / `RESCUE readonly open fail err=…`；拒写 `READONLY write-blocked kind=<kind>`（logOnce per kind）；副本回退前另有 warn 行 `RESCUE readonly direct fail, fallback copy err=…`。
- 缓存：`RESCUE action cache-clear bytes=<n>`。

## 四、verify [19] 组（新增 12 项，本机自跑全绿）

R19-1 FFI 只读全链 / R19-2 openMode 四态 / R19-3 拒写五 kind / R19-4 只读跳真删 / R19-5 副本回退 / R19-6 看门狗（阈值单一定义计数锁 + 步名登记消费 + 浮条挂根）/ R19-7 快照环 / R19-8 快照字段黑名单 / R19-9 Diag 真隔离（persistToday 在位 + flush 内 guard 行序先于清脏行序）/ R19-10 缓存清单封闭 / R19-11 只读横幅与退出路径 / R19-12 救援页动作接线。

本机全量 verify 其余红（均非本批范围）：ipa 陈旧、产物语言包不一致（构建产物未重建，tree 冒烟重建后自解）；S1 组头 topPad 分档（设置区，天气线范围）。

## 五、需主线知晓的两处他组同步（最小、已注明出处）

1. **T15-1 计数 7 → 8**：本批 `prepareNormalStart()` 清空内存列表时新增一处正当的 `touchMemos()` bump 写点（不 bump 则只读退出后归组缓存串台）。T15-1 的计数锁正是为抓写点变化而设，按 [6] 计数同步的同类口径把期望值 7→8 并在注释注明来源（本报告）。若主线不认此同步，替代方案是去掉该 bump 并接受退出只读后首帧归组短暂串台——不推荐。
2. **R13-4 标记保留**：R13-4 断言 RescueView 文件含字面标记「R2 附着点」（R1 时代的未落标记）。本批把 MomentRescue 文件头改为「R2 附着点已落地 / R3 附着点已落地」以保留该字面量，未改 R13-4 断言本身；后续主线整理 verify 时可把 R13-4 的该项断言退役。

## 六、偏离与未落项

- **快照 attachBytes 未记**：规格 S5 字段表有「附件总字节（可得时）」——当前 FFI 无附件总字节出口，新增出口要再动契约面；本批只记 attachCount（条数，load 后补写）。如需字节数，后续批随其他 FFI 变更一并加。
- **跳步降级未落**：S6/S13 的「跳步」在规格中无 S 级细规（guard 点清单 S13 只钉了既有五步 + 本批新增「看门狗」一步），本批未自创跳步机制；救援页「尝试正常启动」仍是全量重走 load()。若主线要跳步，按规格修订后再落。
- **真机/构建终判未做**：本机只完成落码 + cargo test + Swift 四遍全量类型检查（MomentApp/MomentLaunch/MomentOps/MomentRescue 作 primary 均零错误）+ verify [19]。出包前仍须 tree 跑 smoke_ios.sh 全量（本批新代码未经真机构建与运行验证，尤其：只读副本回退的真机文件行为、看门狗浮条与开屏层的实际层叠、Diag 分文件落盘的时序）。
