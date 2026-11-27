# 原生启动路径 + 崩溃面自查（0.9.43 点开即闪退）

审计对象：`rust/apps/ios/app/MomentApp.swift`（工作树含 J1 未提交改动，共 16,099 行）+ `rust/apps/ios/bindings/moment_ffi.swift`。只读审计，未改源码、未跑构建。行号均为当前工作树行号。

证据等级：**proven-risk** = 代码形态必然可崩（触发条件成立即 trap，不可被 catch）；**inferred** = 需特定数据形态/时序才成立；**unknown** = 本次静态审计未能定性。

## 一、启动时序（按执行顺序）

1. `@main MomentApp`（15457）：`@StateObject langStore = LangStore.shared`（15461）先于 `Library()`（15462）声明。`Library` 无显式 init，仅属性默认值——init 本身零风险。
2. `LangStore.init`（3239–3271）：`loadPack("zh-CN")` → 读 `langPref` → 存量判据 `hasExistingState()`（3350）→ 必要时落盘裁定 → `DiagLog.shared.log("LANG init")`。全链 guard/try? 化（见发现 P-1）。
3. 首帧：根 `ZStack { ListView; ErrBadgeOverlay; SplashHostView（resourcesReady 时）}`（15466–15476）。`memos` 为空，ListView 首帧轻量。
4. 开屏画布首帧求值 → `NativeMomentSplash` → `NativeSplashCanvas(artwork:)` → 触发 `NativeSplashArtwork.light/.dark` 静态量首次求值 = `load(theme:)`（15596）。
5. `ListView.onAppear`（13074–13079）：`markScene` → `markFirstFrame` → `library.load()` → `WeatherService.shared.refreshIfNeeded()`。
6. `Library.load()`（462）：`inspectPreviousLaunch()` → 面包屑 `launchMark("开库")` → 全局队列 +0.05s → `MomentLibrary.open`（**首个 FFI 调用**）→ `memoCount` →（空库才写种子）→ `reload(lib:)`。
7. `reload`（522）：`listMemosJson` → `Self.parse`（697，含 `BlockState(node:)` 递归建模）→ 待删再水化（过期真删/未过期收集）→ 主队列回填：`memos` 赋值、`refreshAttachmentNames()`（862）、`refreshAttachmentTypes()`（873）、待删集重建 + 重新 arm。
8. `didLoad = true`（主队列）→ 开屏在 `didLoad && timelineComplete`（时序 2.5s）后淡出。

## 二、发现清单

### F-1 UniFFI checksum trap：首个 FFI 调用处不可捕获的 fatalError

- 位置：`bindings/moment_ffi.swift` 的 `makeRustCall`（281–289，每次 FFI 调用先跑 `uniffiEnsureInitialized()`，284）；`uniffiEnsureInitialized`（1110–1117）对 22 项 checksum 逐项比对，任一不符即 `fatalError("UniFFI API checksum mismatch…")`（1117）。Swift 侧首个触发点 = `Library.load()` 内的 `MomentLibrary.open`（MomentApp.swift 473 附近）。
- 触发条件：随包 `.a` 静态库与随包 bindings 的 checksum 不一致。`load()` 的 do/catch 只能接住 Rust 抛错，**接不住此 trap**；进程在开库步直接死，`didLoad` 永不置位，开屏停在画面上随进程一起消失——与用户「点开就闪退」的观感严丝合缝（0.9.17 同型）。
- 本次相关性折扣：工作树 bindings 22 项齐全、新项 `attachment_types_json = 51632` 在位（bindings 1064）；0.9.43 出包冒烟含 ffi 契约测试 + verify 双向核对且全绿，交付 ipa 即冒烟产物——按现有门禁链，本版不应触发。但此面**没有任何运行时兜底**：门禁之外一旦漏网，真机必闪且 Diag 留不下行（见 F-7）。最终排除/坐实只能看.ips 的异常类型（应为 SIGABRT + 上述 fatalError 文案）。

### F-2 开屏矢量资源解码失败即 fatalError

- 位置：`NativeSplashArtwork.load`（15596–15620），解码/读文件失败走 `fatalError`（15602）。宿主侧 `SplashHostView.resourcesReady`（15376）只验**文件存在**（url!= nil），不验可解码——「资源缺失时宿主不呈现」的注释承诺（15357 段）只兑现了存在性一半。
- 触发条件：bundle 内 `MomentSplash-{light,dark}-vector.json` 存在但与 `NativeSplashVectorResource` 的 Decodable 结构不符（字段改名/类型漂移），首帧画布求值即死。
- 本次排除依据：已解开交付的 0.9.43 ipa 逐项核对两份 JSON——顶层键、viewBox、logo/tagline 结构、stops 类型全部与 Decodable 定义吻合（见 F-3 的数组长度亦合）。故本版不触发；但这是全文件**仅有的两处** `fatalError`/`try!` 之一（另一处见 P-3），属结构性裸奔：资源格式下次任何漂移都会变成点开即闪退，且 verify [8] 只查资源存在、不查可解码。

### F-3 开屏渐变数组无长度校验下标

- 位置：`NativeSplashGradient.init`（约 15680–15687）：`resource.start[0]`、`start[1]`、`end[0]`、`end[1]` 对解码所得 `[Double]` 直接下标，Decodable 不保证长度 ≥2。短数组即越界 trap，发生点同 F-2（首帧）。
- 对照：同文件 `Array.affineTransform`（15896）有 `guard count == 6` 守卫，tagline/decoration 的 transform 安全；唯独渐变起止点漏守。
- 本次排除依据：交付 ipa 两份 JSON 的 background 与 logo 渐变 start/end 长度均为 2。

### F-4 数据首渲（load 后、开屏退场前后）的索引扫描面

- 位置：`stripMarkdown`（12196 起）以 `chars[i]`/`chars[j]` 逐字索引扫描（Swift 摘要移植，约 490 行），由列表行在数据回填后首渲时对每篇摘要执行；行组装（分组、图文卡判图 `hasImageShape` 等）同在此窗口。
- 性质：索引均由循环边界构造守卫，本次未逐行穷尽证明全部边界——若某篇备忘文本形态（畸形 MD 构造）使内层索引越界，trap 发生在数据回填后的首渲，距点开约 1–3 秒、开屏刚退或未退，用户观感仍是「点开就闪退」。此面是本次审计**唯一未穷尽**的启动窗口代码，若.ips 符号化落在 SwiftUI 列表渲染/摘要函数，先查此处。

### F-5 BlockState 递归建模的深嵌套栈风险

- 位置：`BlockState.init(node:)`（131–167）：列表块对子项递归 `BlockState(node:)`、list-item 再递归 nestedList；`Library.parse`（697）在 load 的后台队列对全库每篇执行。
- 触发条件：某篇 doc 存在病理深嵌套（数百层列表）→ 递归爆栈。init 内其余取值全为 `as?` + 兜底，普通坏数据只降级不崩。用户存量数据为真实使用数据，深嵌套可能性低。

### F-6 待删再水化与附件表刷新（0.9.43 新面）

- `pendingDeletions` 再水化（543–585）：标记经 `MemoItem.deletedAtMs`（`raw["deletedAt"] as? NSNumber`）读取，无强制解包；过期真删在 do/catch 内；重建 + arm 在主队列异步块内，字典/计时器操作无下标陷阱。
- `refreshAttachmentTypes()`（873–880，新 FFI `attachmentTypesJson`）与 `refreshAttachmentNames()`（862–869）：均为 `try?` + guard + `as? [String: String]`，FFI 失败或 JSON 形态不符只静默返回旧缓存。唯一前提是 FFI 已初始化成功——即只受 F-1 连累，无独立崩面。
- 结论：0.9.43 三个结转项（导出过滤在 Rust 侧、MIME 判图、底表 padding）与 J1 先行 FFI 中，Swift 启动面没有新增 proven-risk。

### F-7 崩溃证据链缺口：闪退时 Diag 可能一行都留不下

- 落盘节流：`DiagLog.schedulePersist`（3028）普通行 1s 合并一写、仅 error 行立即刷盘；写盘用 `data.write` **非原子写**（3019 `persist`）——崩在写一半会把 today.json/archives.json 写坏，下次启动 `read` 解码失败即整表丢弃（try? 兜底不崩，但历史蒸发）。
- 启动面包屑：`launchMark`（396）只 `UserDefaults.set`，全文件**无一处 `synchronize()`**——硬崩时最近一步可能未落盘，`inspectPreviousLaunch`（约 437）的「停在步骤」证据可能缺失或停留在更早步骤。
- 覆盖现状：LangStore init 有 `LANG init` 行（info 级，受 1s 节流管辖）；开屏有 `SPLASH show`（info）；load 成功有 `SMOKE 冷启完成`（info，收尾才记）；开库失败有 error 行（立即刷盘，这条最可靠）。**开库步 trap（F-1）与首帧 trap（F-2/F-3）发生时，本次启动在 Diag 里零行**，只能靠下次启动的 UserDefaults 哨兵（且受上条落盘不确定性影响）。
- 附带：`DiagLog.loadIfNeeded()`（2979）的磁盘读（today + 最多 60 份归档的 JSON 解码）在**第一次 log 调用时同步执行**——即 LangStore.init 内、首帧之前的主线程上。归档量大时是冷启主线程的一笔同步 IO（不崩，但占启动预算；解码全 try? 化，坏档只丢弃）。

### 其余查过且安全的点（P 组）

- **P-1 LangStore.init**：`loadPack` 三段 guard + try?，包缺失/坏 JSON 回退空表（查表再回退键名）；`hasExistingState` 路径与哨兵键读取均可选化；存量裁定落盘是普通 `set`。无崩面。
- **P-2 Library.load 的 Rust 抛错面**：open/memoCount/upsert/listMemos 全在 do/catch 内，失败走 `loadFailed` + 错误徽章 + error Diag，是降级页不是闪退。`storeDir`/`DiagLog.dir` 的 `urls(...)[0]` 为系统保证非空的定式，下标安全。
- **P-3** 全文件扫描：`try!` 仅 1 处 = `NativeSVGPath.tokenRegex`（15723，字面量正则，编译期可证有效）；`as!`、`first!`、`last!` 零处；`fatalError` 仅 F-2 一处（+ bindings 的 F-1）。
- **P-4 WeatherService**：`refreshIfNeeded`（12566）的缓存解析全 guard 化，网络/定位在异步 Task 且延时 1.5s，不在首帧路径；`key()` 读 weather-keys.json 亦 try? 化。
- **P-5** 种子写入仅 `memoCount == 0` 时触发（存量用户不达）；`MathImageStore`（10154）懒单例、WKWebView 按需建，列表首帧不触达；`ErrBadge`（2777）纯内存数组，无 init 风险。

## 三、与 0.9.43 闪退的相关性排序

| 名次 | 发现 | 等级 | 本次判断 |
|---|---|---|---|
| 1 | F-1 UniFFI checksum trap（开库步） | proven-risk | 机制与「点开即闪」最合；但本版门禁链完整，概率被压低——.ips 一眼可排除/坐实 |
| 2 | F-4 数据首渲索引扫描（stripMarkdown 等） | inferred | 未穷尽审计的唯一启动窗口面；若崩在数据回填后首渲，观感相同 |
| 3 | F-2 开屏解码 fatalError | proven-risk | 交付资源已静态验合，本版排除；结构缺陷保留 |
| 4 | F-5 BlockState 深嵌套递归 | inferred | 需病理数据，可能性低 |
| 5 | F-3 渐变下标越界 | proven-risk（形态） | 交付数据长度已验，本版排除 |
| — | F-7 证据链缺口 | proven（机制） | 非崩因；解释了为何此类闪退在端内不留痕、必须靠.ips |

总判断：在拿到.ips 前，静态面能给的最强结论是——**能在首帧前/开屏期把进程打死的代码面只有三处（F-1、F-2、F-3），其中两处已被交付产物静态排除，剩 F-1 靠门禁记录背书、靠.ips 定案；F-4 是唯一的未穷尽面**。若.ips 显示 SIGABRT 且含 "UniFFI API checksum mismatch"，即 F-1 坐实（意味着门禁链有洞，需查.a 与 bindings 的实际出包路径）；若落在 SwiftUI 渲染栈，则转查 F-4。

## 四、启动期应延后 / 应隔离清单

**应隔离（加失败降级，形态根治）**
1. F-2/F-3 开屏资源：`load(theme:)` 的 `fatalError` 改为返回降级 artwork（纯色背景 + 空路径）并记 Diag error；`NativeSplashGradient.init` 对 start/end 做 `count >= 2` 守卫（对齐 affineTransform 的既有守法）。同时把「可解码」并入 `resourcesReady` 判据（预解码一次并缓存结果），宿主承诺才完整。
2. F-2 的构建侧对应项：verify [8] 增加两份矢量 JSON 的**解码级断言**（按 Decodable 结构校验键/类型/数组长度），把这类漂移挡在出包门而非真机。
3. F-1 无运行时隔离手段（trap 不可捕）：防线只能在构建门（现状已闭环）。建议把「交付 ipa 内嵌 bindings 与.a 的 checksum 对账」做成 verify 的独立一项并留痕出包日志，使每包都有据可查，而不是只靠契约测试的源头对账。

**应延后（移出首帧前/冷启主线程）**
4. `DiagLog.loadIfNeeded` 的磁盘解码：从首个 log 调用点（LangStore.init 内）剥离，改为首帧后异步加载，早期行先进内存环、加载完成再合并——消除冷启主线程同步 IO，也避免 init 顺序耦合。
5. `refreshAttachmentNames/Types`：现位于数据回填的主队列块内、首数据帧之前；两者只服务附件行/图片页/图文卡判图，可延后到 didLoad 置位之后一拍执行（列表首渲先用空表，行内有兜底口径），缩短「数据到、首帧出」的窗口。
6. `WeatherService.refreshIfNeeded`：现挂 ListView.onAppear，与 load 同拍；缓存命中时仅一次 UserDefaults 读，可保留；未命中路径虽已异步，仍建议整体延后到 didLoad 之后触发，启动期只做渲染与开库两件事。

**证据链补强（与自救机制同批）**
7. Diag 写盘改原子写（`.atomic`），避免崩中写坏整表；`launchMark` 的关键步（开库/读数据）后加 `synchronize()`，面包屑证据才可靠。
8. load 入口先记一行 error 级别以下的「LAUNCH begin v=…」并立即刷盘（或单设一条立即落盘的启动行），保证任何启动期 trap 在端内至少留一行版本 + 步进证据，不再完全依赖系统.ips。
