# 原生自救机制补齐规格（对 Web 救援层全量对表）

立项背景：原生 0.9.43 出现「点开 App 即闪退」。用户 2026-11-26 已立规矩：原生 iOS 的诊断覆盖与自救机制须与 Rust Web 版全面对齐。Web 救援层 2026-11-24 已部署生产（提交 7cc10b87d8），且是部署基线的一部分（`开发规范.md:108-110`：后续每次部署基线都应包含它、不得破坏其独立性）。

本文件三部分：一、Web 机制全量清单（逐项触发/动作/数据安全边界，带源码出处）；二、原生现状对表（已有/部分/缺失，带行号）；三、原生补齐规格（逐项可落码，含 verify 断言建议与 Diag 新增打点清单）。前置清点见 `docs/reports/audit_native_diag_rescue.md`（2026-11-26 双线清点，其批 A/B/C 已于 0.9.15/0.9.17/0.9.18 落地，本规格在其之上补「救援面」整层，不重复批 A–C）。

**先说清本次 0.9.43 闪退与本规格的关系**：本规格不预判 0.9.43 的崩因（定因仍靠用户导出的 .ips / Diag 证据）。但现状下确定性启动崩溃是一个**死循环**：崩在首帧完成前 → 下次启动哨兵只累计计数、提示渲染在进不去的列表页里 → 用户没有任何出口拿证据、看数据。本规格的核心就是拆掉这个死循环：第二次启动起进安全模式，最坏情况从「无限闪退」降级为「可导出诊断、可只读看数据、可尝试正常启动」。

---

## 一、Web 机制清单（proven，逐项带出处）

源码主体：`rust/apps/web/index.html`（内联外壳脚本，与 Dioxus 应用解耦、先于 wasm 执行）、`rust/apps/web/src/diag.rs`、`rust/apps/web/src/persist.rs`、`rust/apps/web/src/main.rs`。

### W1 状态快照（每次加载一条，只记元数据）

- 出处：`index.html:318-320`（设计注释）、`index.html:335-338`（键与环长）、`index.html:372-434`（`collectSnapshot`）。
- 触发：每次页面加载无条件执行一次，结果追加进 localStorage 键 `moment_rescue_log_v1`，环形保留 20 条（`RING = 20`）。
- 内容：SW 注册清单（脚本名+状态）、Cache Storage 键名、IndexedDB 库名/版本/表名清单、localStorage 键名与长度（Diag 键只记行数）。**只记元数据、绝不记值**；若上一条是 repair 动作，本条快照打 `afterRepair: true` 标记。
- 数据安全边界：纯读元数据，零写入业务数据；写失败静默（try/catch 吞）。

### W2 存活标记 boot_ok（应用侧写、外壳侧读）

- 出处：`src/diag.rs:143`（`BOOT_OK_KEY = "moment_boot_ok"`）、`src/diag.rs:562-571`（`mark_boot_ok`）、`src/diag.rs:619-627`（init 后 2s 以 once 闭包 + setTimeout 调度）。
- 语义：`diag::init` 完成 2 秒后由存活闭包写标记——**闭包能被调到本身即存活证明**；若应用在此前 panic=abort，闭包随实例死亡、标记停留在上一会话的值。数据加载与首帧正常都在此 2s 窗口内完成。

### W3 看门狗 + 救援小条

- 出处：`index.html:602-640`（`booted()`/`showBar()`/主调度）；样式 `index.html:96-101`；进场动画 `mnSwupdIn` 220ms（`index.html:69`，与 SW 更新条同曲线同时长）。
- 触发：加载后 **12 秒**定时器检查 `booted()`：boot_ok 值相对加载时已变化，**或**启动页元素（`#main .splash`）已消失，任一成立即判活。
- 呈现：未活 → 底部浮出救援小条（fixed、左右 16、底部 = 安全区 + 16、z-index 6001、毛玻璃卡），文案「应用似乎没有响应」+「点此修复」钮（开面板）+「×」关闭钮。
- 自撤：小条出现后每 2 秒轮询 `booted()`，应用晚活过来（慢网/慢设备）即自动撤条；面板已开时不重复出条。

### W4 `?rescue=1` 直达面板

- 出处：`index.html:632-634`。URL 带 `?rescue=1` 时不等看门狗、直接开全屏救援面板——给「用户主动求救/开发者远程指导」留的直达入口。

### W5 救援面板（形态与文案）

- 出处：`index.html:517-600`（`openPanel`）；样式 `index.html:102-115`，关键帧 `mnRescueIn` 在 `index.html:104`。
- 形态：全屏 fixed 层（z-index 10000），**遮罩 transparent 不压暗**（2026-11-23 模态压暗改判 C 的同源口径）；居中卡片 max-width 520、radius 24、进场 **250ms 纯淡入无位移**；深色模式与 backdrop-filter 降级级联在 `index.html:117-156`。
- 文案（内联五语字典 `index.html:340-346`，按 localStorage `moment_lang` 选、缺失回退 zh-CN——理由：应用起不来时也必须出字）：标题「应用救援」；**边界说明段**（zh-CN 原文要点：修复启动只重置缓存与服务进程、不动笔记数据；备忘与附件保存在设备数据库里；修复后仍无响应则先导出诊断发开发者；**不要清除浏览器站点数据、那会让笔记全部丢失**）；「当前状态快照」标题 + 等宽字体快照区（取救援日志里最新一条 snapshot 渲染，见 `snapText` `index.html:437-453`，无存量时现场重采）。
- 动作按钮（纵列四枚，`index.html:543-585`）：修复启动（主按钮蓝底）、导出诊断、关闭、存储后端开关（见 W9，随当前值在「以兼容模式启动（存储）」/「恢复存储自动模式」间切换文案）。

### W6 修复启动 repairBoot（动作边界的样板）

- 出处：`index.html:487-515`。
- 动作全集（仅此三件）：① 注销全部 Service Worker 注册；② 删除全部 Cache Storage 键；③ `location.replace(location.pathname)` 无参重载（顺带剥掉 `?rescue=1` 等参数）。动作执行前先把 `{kind:'repair'}` 落救援日志（见 W8）。
- **绝不动**：IndexedDB、localStorage、OPFS——即备忘、附件、偏好、Diag 全部原样。按钮点击即置 disabled 防重复。

### W7 导出诊断（面板内）

- 出处：`index.html:455-486`（`exportDiagnostics`）。
- 内容三段：导出头（时刻 + UA）、Diag 全文（localStorage `moment_diag_v1`）、救援日志全文（`moment_rescue_log_v1` JSON 美化）。打包为 `moment-diagnostics-<ISO时刻>.txt`；出口优先 `navigator.share` 文件分享，不支持则 `<a download>` 兜底。导出动作本身先落一条 `{kind:'export'}` 救援日志。

### W8 救援日志 drain（动作回执折入 Diag）

- 出处：`src/diag.rs:496-560`（`drain_rescue_log`，init 内调用序见 `src/diag.rs:613`）。
- 规则：键**无论解析成败先清除**（防坏值每次启动反复重试）；纯快照条目 = 导出备料，健康启动时静默清除、不刷 Diag 环；含 repair/export 动作条目时逐条转 `RESCUE` 行（`repair boot at=… (sw unregistered, caches cleared)` / `diagnostics exported at=…`），并给最新快照一行摘要（sw/caches/idb/ls 计数 + afterRepair）作回执——救援后的现场状态在 Diag 里有据可查。

### W9 存储后端开关（只动开关、不动数据）

- 出处：面板按钮 `index.html:556-585`；消费面 `src/persist.rs:74-97`（`resolve_backend`）。
- 机制：只写 localStorage `moment_backend_v1` = `idb`（兼容模式）或 `auto`，然后无参重载。解析优先序：URL `?backend=` > `moment_backend_v1` > 构建默认（观察期为 dual）。落一条 `{kind:'backend', v:…}` 救援日志。
- 价值：存储层出问题时**回滚不需重新部署**，重启即生效（CHANGELOG 2026-11-24 阶段三条目）。

### W10 panic / 全局错误取证双通道

- 出处：`src/diag.rs:45-59`（设计注释）、`src/diag.rs:61-107`（`install_panic_hook`）、`src/diag.rs:110-141`（`drain_panic_log`）、init 尾 `install_error_hooks()`（`src/diag.rs:640` 一带）。
- 通道一：panic 钩在 abort 前**同步直写**专用键 `moment_panic_v1`（环上限 20）+ 当场往 Diag 键追加一行；两处都写裸 localStorage（钩触发时日志锁/节流写者都可能已不可用），写失败静默、禁止二次 panic。
- 通道二：全局 error / unhandledrejection 钩只旁路记录。下次启动 drain 成 `PANIC` 行并清键。附带判据：trap 时专用键无新记录，即证明 trap 不是 Rust panic 本体而是已 drop 闭包被调等他因——取证设计自带归因能力。

### W11 SW 更新提示条（更新自救）

- 出处：`index.html:40-300` 一带（`#mn-swupd` 样式 `index.html:63`）+ `src/diag.rs` 的 `drain_swupd_events`（init 调用序 `src/diag.rs:611`）。
- 口径：新版就绪只出条提示、**点才更新**（不强更、不打断编辑）；「×」按 VERSION 戳记、同版不重弹；事件暂存 `moment_swupd_pending_v1`，下次启动 drain 成 `SWUPD` 行留痕。

### W12 dual 硬失败 → 只读降级（可看不可写）

- 出处：形态语义 `src/persist.rs:10-14`；只读标记与门面拒写 `src/persist.rs:157-170` 一带（`writes_blocked`）；呈现 `src/main.rs:2246-2252`。
- 触发：双写形态下 SQLite Worker 硬失败。
- 动作：数据面切 IDB 镜像**只读**呈现（可看、可导出），**写路径在门面统一拒绝**（不走可写直读回退，防静默分叉）；底部常驻只读横幅（`storage-readonly-banner`，role=alert）告知。状态经 listener 回调推呈现、不轮询（`src/persist.rs:215-229`）。

### W13 sqlite 硬失败 → 阻断页（不给误导性只读）

- 出处：形态语义 `src/persist.rs:15-17`；呈现 `src/main.rs:2224-2244`。
- 触发：纯 SQLite 形态硬失败——此时镜像已停写，只读呈现的数据是旧的、会误导，故**不降级只读、直接阻断**。
- 呈现：全屏空态（warning 图标 + `storage.unavailable_title/sub`），唯一动作「重试」= 整页重载；抢救（导出/切兼容模式）走救援面板（W5/W9）。

### W14 会话 IDB 降级（存储上下文不可用）

- 出处：定案注释 `src/persist.rs:19-26`；会话降级标记与横幅支别 `src/persist.rs:172-213`；呈现 `src/main.rs:2254-2272`。
- 失败分类（按步结构化，不做文案子串匹配）：Worker install 按 SAHPool 步位回结构化失败——`CreateSyncAccessHandle`（handle 步）= 真锁冲突 → Occupied（见 W15）；其余步位（directory/file/register/unsupported/import）= 本上下文存储不可用 → 立即分流。
- 分流：dual 形态 → **会话 IDB 降级**：本会话全量走 IDB 读写（可写降级、非只读），落降级标记，SQLite 恢复后下次冷启自动再迁移回去。sqlite 形态 → 直接阻断（W13）。
- 横幅两支（同槽位同玻璃口径）：`ephemeral`（失败签名命中无痕/易失会话——directory 步 SecurityError、UnknownError + unknown transient——文案明示「数据不保存」）；`session`（一般不可用，文案明示下次启动自动恢复）。

### W15 多标签独占提示页

- 出处：呈现 `src/main.rs:2198-2222`；等待接管在 persist 侧（状态 listener 推送）。
- 触发：SQLite SAHPool 单连接被另一标签占用（用户口径定案：独占 + 提示、零写入）。
- 呈现：全屏空态（clock 图标 + `storage.occupied_title/sub`）+「立即重试」钮。重试 = `nudge_retry()` 只催促 persist 再试、**不触碰数据库**，带 1.2s 忙碌态防连点；第一标签关闭后 persist 等待循环自动接管，本层随标记清除而自行消失。

### W16 逐篇隔离 quarantine（坏数据不拖垮整库）

- 出处：`src/persist.rs:40-45`（迁移编排注释）；清点细节见 `audit_native_diag_rescue.md` 一、。
- 机制：加载/迁移时逐篇归一解析，坏篇原文 stash 进 IDB 独立 kv 键 `quarantine_json`（任何写回都不触碰它）；隔离落盘失败则**整次加载阻断**（宁阻断不丢原文）；导出 ZIP 随包附 `quarantine.json`，坏数据永远有据可查、可人工抢救。

### W17 加载期自愈（静默修复类）

- 出处：`audit_native_diag_rescue.md` 一、「加载期自愈」条（Web 家底 proven）。
- 清单：pending-delete 过期清理/未过期重水化；pending input（未提交输入）恢复；种子置顶 retarget；改名迁移失败保留旧库续跑；会话降级次冷启自动再迁移回 SQLite（W14）；存量旧形字段每次加载先归一再解析（CHANGELOG 2026-11-24「加载与点击故障根治」）。

### W18 错误徽章 errbadge（第二取证面）

- 出处：`audit_native_diag_rescue.md` 一、（Web 家底）。
- 机制：应用根悬浮徽章，错误/警告入列上限 20、可展开看明细、可 clear；与 Diag 环互为第二取证面——Diag 读不出时徽章还在（反之亦然）。

---

## 二、原生现状对表

原生源码：`rust/apps/ios/app/MomentApp.swift`（16,099 行，行号为 0.9.44 工作树现值）。根结构：`@main MomentApp`（:15457）→ `@StateObject LangStore.shared` 先于 `Library()` 声明（:15461-15462）→ 根 ZStack{ ListView; ErrBadgeOverlay; SplashHostView }（:15467-15475）；`scenePhase` 变化驱动哨兵收尾/续上（:15476-15486）。加载触发点在 ListView `.onAppear`（:13077，`memos.isEmpty` 时调 `library.load()`）。

| # | 机制（对 Web 条目） | 原生状态 | 现状与差距 |
|---|---|---|---|
| 1 | Diag 日志管线（W8/W10 的载体） | **已有** | `DiagLog`（:2949）：today 环 300（:3110-3112）、1s 节流合并落盘 + error 行立即刷（:3030-3052、:3113-3114）、按天冻结归档上限 60 且超限记 WARN 行（:3000-3026）、自动删除 30 天开关（:3063+）、`logOnce`/`logErrorOnce` 去重原语（:3121、:3140）。落盘在 Application Support/`diag/`（:2956-2965），与 `library/` 库目录分离——库坏时日志仍可读，隔离域已成立。 |
| 2 | Diag 查看与全量导出（W7 的应用内面） | **已有** | DiagView 当天卡 + DiagLogPage（:3832）逐页查看；`exportEverything()`（:3786）全量一键导出（归档旧→新 + 当天，带环境头 envHeader，系统分享），导出结局记行。与 Web 的差距只在**可达性**：必须先进得去 App、走得通设置页（见第 9 项死循环）。 |
| 3 | 错误徽章（W18） | **已有** | `ErrBadge`（:2776，上限 20、ERROR/WARN 两级）+ `ErrBadgeOverlay`（:2826）挂根 ZStack 全应用可见；addError 赋值点覆盖开库/保存/删除/附件/导出等（:511、:757-979 多处）。 |
| 4 | notice 横幅通道 | **已有** | `Library.notice`（:934），ListView 两处呈现（:12992、:13320）；赋值点：启动连续未完成（:454）、隔离告知（:526）、保存失败三支（:759-777）。 |
| 5 | 启动哨兵/面包屑（W2 的原生等价物） | **部分** | 批 B（0.9.17）+ G2 全会话化已落地（:377-460）：三键 `launchInProgress`/`launchStep`/`launchCrashStreak`（:383-385，UserDefaults 同步 set）；步进点：开库（:467）→ 读数据/写种子（:478-486）→ `launchDone` 推进到「会话中」并清零 streak（:394-402）；场景步「场景·首页」（:13075）/「场景·编辑页」（:7705）；退后台 `launchSuspend` 清哨兵、回前台 `launchResume` 续上（:416-431、根 :15476-15486）。下次启动 `inspectPreviousLaunch`（:438-460）分级：停在加载步 = error + streak+1、≥3 出 notice；停在会话/场景步 = warn 留痕不计数。**差距**：① 判定与呈现都埋在正常加载链里，崩在首帧前时用户看不到任何东西（第 9 项）；② 步进粒度粗（开库内部 FFI open/种子/列表解析未再分步，reload 内部无步点）；③ UserDefaults 在硬崩时落盘不如文件直写可靠（见规格 S1）。 |
| 6 | 冷启成功证据行（W2 的回执面） | **已有** | `SMOKE 冷启完成 v=… memos=… 首帧…ms 数据…ms`（:497-503），reload 全程走完才记——与 LAUNCH 行构成「成功/未完成」双证据。 |
| 7 | 开库/加载失败态（W13 的弱化版） | **部分** | `load()` 的 catch（:505-519）：清哨兵不计 streak、置 `loadFailed`（:332）、记 error 行 + ErrBadge；失败空态三态之一（:13406-13420、:14029）给「重试」= `retryLoad()`（:582-596，按结局置位、失败记行）。此态下 didLoad 已置真、开屏退出，设置/Diag 仍可达。**差距**：只有「同路径重试」一个动作——没有只读打开、没有跳步降级、没有从失败态直达导出诊断的入口（要绕设置页）；且此态只覆盖「抛错」型失败，不覆盖「挂死」与「崩溃」。 |
| 8 | 逐篇隔离（W16） | **已有** | 批 A 已落地：storage 逐行容错 + `quarantine_json` 入库 meta、导出随包附出；Swift 侧 `reload` 解析回隔离数（:522-531）记 warn 行 + notice 告知。 |
| 9 | 加载期自愈（W17） | **部分** | 待删再水化/过期真删已落地（:533-580，含导入换库后旧计时全撤防误删）；种子仅空库时写（:481-486）。**缺**：与 Web 对位的「归一失败逐篇隔离后继续」已由第 8 项覆盖；无其他缺口级差距。 |
| 10 | 看门狗（W3） | **缺失** | 全文件无 watchdog/超时呈现。开屏退出条件 = `didLoad && timelineComplete`（:15447），`load()` 若挂死（FFI 阻塞、死锁、永不返回的异步），开屏**永久驻留**，无超时提示、无任何可点入口。与 Web 12s 看门狗完全不对位。 |
| 11 | 安全模式 / 启动失败救援面（W4/W5） | **缺失** | 无 safeMode 概念（全文件零命中）。**确定性启动崩溃死循环**（0.9.43 形态）：崩点在 `didLoad` 之前 → 哨兵 streak 逐次 +1、notice 写进了 ListView 的呈现面（:12992）但 ListView 永远到不了可交互态 → 用户看不到提示、进不去设置、导不出 Diag、看不到数据，唯一出路是删 App（= 丢库）。Web 的「外壳与应用解耦」在原生没有等价物——这是本规格要补的核心层。 |
| 12 | 状态快照环（W1） | **缺失** | Diag 导出有 envHeader 环境头，但没有「每次启动一条结构化元数据快照」的留存环（库字节/篇数/附件量/磁盘余量/哨兵态），也没有给救援面消费的快照结构。崩溃现场的结构化证据只有 LAUNCH 行一行文本。 |
| 13 | 救援动作日志（W8） | **部分** | 原生同进程内动作可直接记 Diag 行（LAUNCH/SMOKE/ERRBADGE 行已是此形态），不需要 Web 的跨层 drain；但尚无 `RESCUE` 族行与「上次救援动作」跨启动留痕（哨兵里不记 lastRescueAction，下次启动的 LAUNCH 行无法附带「上次已试过什么」）。 |
| 14 | 只读降级打开（W12） | **缺失** | `MomentLibrary.open` 恒可写打开；无只读句柄、无门面拒写层、无只读横幅。加载失败时用户连「先把数据看一眼/导出来」都做不到，只能重试同一条可写路径。 |
| 15 | 跳步降级加载 | **缺失** | `load()`/`reload()` 是单路径全量流程：开库 → （种子）→ listMemos → parse → 待删再水化 → 附件名/类型刷新。任一步确定性失败即整链失败，没有「跳过非必要步、先把列表拿出来」的分级降级。 |
| 16 | 修复启动等价动作（W6） | **缺失（且需重新定位）** | 原生无 SW/Cache Storage，「清缓存重载」没有直接等价物。可再生层只有 URLCache、Library/Caches、tmp 导出残留——清它们对代码型启动崩溃无疗效。规格中保留为安全模式页的次级动作并明示定位，不得冒充 Web 修复启动的主打地位（见 S7）。 |
| 17 | 存储后端开关（W9） | **不适用** | 原生单一存储（SQLite 直连），无双写/多后端形态，无此开关需求。对位机制是 S4 只读打开与 S5 跳步降级（同为「只动模式、不动数据、重启/重试即生效」）。 |
| 18 | panic 取证（W10） | **部分（平台受限）** | Rust panic 跨 UniFFI 即 abort，Swift 侧无等价钩可同步直写；现状靠哨兵步进 + 系统 .ips 通道（0.9.17 闪退即由哨兵步「开库」与 .ips 互证定案，见 `audit_native_diag_rescue.md` 完成注记）。本规格不强求等价物，只把哨兵步进加密（S1）让留痕更细。 |
| 19 | 多标签独占（W15）/会话降级（W14）/更新条（W11） | **不适用** | 分别为浏览器多标签、WebKit 存储政策、SW 更新机制所独有，原生无对应面。原生单进程打开 moment.db 无独占冲突问题（同机双开不存在）。 |

**对表小结**：诊断管线、徽章、隔离、哨兵计数这些「留痕层」原生已基本齐（批 A–C + G 批的成果）；缺的是整层「救援面」——看门狗、安全模式、只读打开、跳步降级、快照环。留痕层再全，出口不存在时对用户等于零：0.9.43 正是留痕齐全（哨兵会记、Diag 会写）但用户够不着。

---

## 三、原生补齐规格（逐项可落码）

落码分三批（批间独立提交、各自过冒烟）：**R1** 哨兵加密 + 判定前移 + 安全模式骨架（导出诊断/尝试正常启动两个动作先行）；**R2** 只读打开（FFI 新增只读打开导出，含 bindgen 与契约表更新）；**R3** 看门狗 + 状态快照环 + 跳步降级 + 可再生缓存清理 + verify [12] 组转正。

### S1 启动分段打点加密（R1）

现步进点（开库/读数据/写种子/会话中/场景）粒度不足以定位 reload 内部崩点。加密为下表步枚举，`launchMark` 在每步**进入时**调用（现口径不变），步名常量集中一处（`LaunchStep` 枚举或常量组），禁止散写字面量：

| 步名 | 进入点（现行行号） | 备注 |
|---|---|---|
| `开库` | load() 起点（:467） | 沿用 |
| `开库·FFI` | `MomentLibrary.open` 调用前（:472） | 与「开库」分开：区分哨兵/Dispatch 段与 FFI 段 |
| `读数据·列表` | `reload` 内 `listMemosJson` 前（:523） | |
| `读数据·解析` | `Self.parse` 前 | parse 顶层失败现回假空的风险点，须有步痕 |
| `写种子` | 种子写入前（:482） | 沿用；仅空库路径 |
| `再水化·待删` | reload 待删处理前（:540） | |
| `附件名表` | `refreshAttachmentNames` 前（主队列段 :561） | |
| `附件类型` | `refreshAttachmentTypes` 前 | |
| `首帧` | didLoad 置真前（:487） | 与 SMOKE 行同点 |
| `会话中` | launchDone（:394） | 沿用；场景步沿用 |

落盘可靠性升级：哨兵三键现走 UserDefaults（:388-392），其内存缓存 + 异步刷盘在硬崩（abort/强杀）时可能丢最后一步。规格：哨兵改落 **diag 域文件直写**——`Application Support/diag/launch-sentinel.json`，每步以 `Data.write(.atomic)` 同步落盘（与 Diag 同隔离域、库坏不影响）；UserDefaults 三键保留只读兼容一个版本（判定读序：文件优先、缺失回退 UserDefaults），下版删旧键。Diag 新增行：哨兵文件写失败记 `LAUNCH sentinel write failed` warn（logOnce）——留痕层自身失效也要留痕。

### S2 启动完成标记与安全模式判定（R1）

- 完成标记沿用现口径：`launchDone`（reload 成功 + didLoad 置真）清零 streak 并推进「会话中」；SMOKE 行仍为成功回执。开库抛错走 `launchFailed` 清哨兵不计数（:433-436、:505-519），口径不变。
- **判定前移（本规格最关键的结构改动）**：现 `inspectPreviousLaunch` 在 `load()` 内、由 ListView `.onAppear`（:13077）触发——ListView 构建不出来时判定根本不执行。改为在 `Library.init` 末尾（或 `MomentApp.init`，须晚于 DiagLog 可用、早于 ListView 构建）同步执行判定，结果落 `@Published var bootMode`（`.normal` / `.safe(streak:step:)`）；根 ZStack 按 bootMode 分流：`.safe` 时**先渲染 RescueView、不构建 ListView**。`load()` 内的旧判定点删除（防双记），LAUNCH 行改在判定点记（行文沿用现格式 + 附 `lastRescueAction`，见 S6）。
- 进入条件：上次启动停在**加载步**（非会话/场景步）且 streak **≥ 2** 即进安全模式。定 ≥2 的理由：第 1 次未完成可能是强杀/偶发，现有口径（error 行 + 本次正常启动）足够；第 2 次同类未完成已证明非偶发，继续盲启只是重复闪退。streak == 1 时维持现口径另加一条：正常启动后 notice 提示一次「上次启动未完成，如反复出现请导出诊断」（新键 `notice.launch_once`）。现 ≥3 notice（:454-457）保留，与安全模式并行不悖（安全模式里也要能看到次数）。
- 会话/场景步未收尾（warn 支）永不触发安全模式（系统回收/前台崩溃与启动死循环是两回事），沿用现分级（:446-449）。

### S3 安全模式页 RescueView（R1 骨架 + R2/R3 补全动作）

形态（全部用既有呈现层组件与令牌，不新造视觉语言）：

- 全屏页，构成复用设置族/空态口径：顶部标题「应用救援」（新键 `rescue.title`）+ 边界说明段（新键 `rescue.boundary`，五语，文案口径对位 Web W5：先声明数据没动、再给动作指引、明示不要删 App——删 App 等于删库，与 Web「不要清站点数据」同位警告）。
- 状态区（只读文本组）：上次停步、连续未完成次数、当前 streak、库文件字节数、Diag 当天行数 + 归档数、上次救援动作（S6）。数据来自哨兵文件 + `diag/` 与 `library/` 的文件元数据（FileManager 读属性，**不打开库**）。
- 动作区（纵列按钮，主次分明）：
  1. **尝试正常启动**（主按钮，R1）：清本次哨兵标记 → bootMode 切 `.normal` → 走常规 `load()`。成功则 streak 清零（现 launchDone 口径）；再崩则下次 streak+1 仍回安全模式。动作前记 `RESCUE action normal-retry` 行。
  2. **导出诊断**（R1）：走 DiagView `exportEverything()` 同链（:3786）+ 追加 S5 快照段与哨兵摘要段，走系统分享。动作前记 `RESCUE action export` 行（对位 Web W7/W8 的「动作先落日志」）。**此动作在安全模式下必须可用**——RescueView 只依赖 DiagLog（diag 域文件直读），不依赖 Library 开库成功。
  3. **只读打开资料库**（R2，见 S4）：成功后进只读浏览态。
  4. **导出备份 ZIP**（R1 可达性修复）：`Library.exportZip()`（:942）现链已有 lib==nil 守卫（批 A）；安全模式下 lib 为 nil 时此钮置灰并给原因文案，不得假成功。只读打开成功后此钮可用（导出走只读句柄）。
  5. **清除可再生缓存后重试**（R3，见 S7）：次级文字钮，带确认。
- 安全模式页自身红线：零 FFI 写调用、零库打开（只读打开是用户显式动作 3、且走 S4 只读句柄）；页面构建路径只许碰 DiagLog 与 FileManager 元数据——保证「库或加载链坏透」时本页仍起得来。

### S4 只读打开（R2）

- Rust/FFI 层：storage 新增只读打开（rusqlite `OpenFlags::SQLITE_OPEN_READ_ONLY`），ffi 新增导出 `open_readonly`（命名落码时定）。**FFI 导出面变更必走全套**：重跑 bindgen 回拷 bindings、ffi 契约测试表 +1（现 22 项 → 23）、verify [6] 计数同步——UniFFI checksum 含文档注释的教训在案（0.9.17），漏一步即真机首调闪退。
- **WAL 坑（必须处理）**：moment.db 为 WAL 模式时，只读打开需要 `-shm` 可写或恢复窗口；若库目录不可写或 `-wal` 未 checkpoint，只读打开可能直接失败。规格：只读打开失败 → 回退**副本模式**：把 moment.db（及存在的 -wal/-shm）拷贝到 tmp 救援目录，对副本以可写方式打开但 Swift 门面按只读对待（副本可弃、源文件零触碰），状态区与 Diag 行明示 `mode=copy`。两种模式用户数据影响面相同（源库零写），差别只在呈现新鲜度，文案如实标注。
- Swift 侧：`Library` 加 `openMode: .none/.readWrite/.readOnly/.readOnlyCopy`；只读态门面拒写清单（首行 guard + 记 `READONLY write-blocked kind=…` logOnce 行 + notice 告知）：`persist`（编辑落盘）、`upsertMemoJson` 全入口、种子写入、`removeMemo` 与待删过期真删（只读态 reload 跳过真删、仅隐藏并记行）、`putAttachment`、`removeAttachment` 类、导入换库、头像写入。
- 呈现：只读态进 ListView，顶部常驻只读横幅（复用 noticeRow 槽位上方独立 banner，文案新键 `rescue.readonly_banner`，对位 Web W12 横幅）；编辑入口（新建/进编辑页编辑/删除/导入）禁用或点了给 notice；查看、搜索、单篇与全量导出可用。退出只读态唯一路径 = 回安全模式页点「尝试正常启动」（不在只读态内提供切可写钮，防误触）。

### S5 状态快照环（R3）

- 每次冷启在哨兵判定后写一条快照进 `diag/rescue-log.json`（环 20，结构对位 Web W1）：字段 = 时刻、版本/build、哨兵判定结果（prevStep/streak/bootMode）、库文件字节（FileManager 属性，不开库）、Diag today 行数/归档数、磁盘可用字节、系统版本。开库成功后补写第二条（或更新本条）加 memoCount/附件文件数与总字节。**只记元数据：绝不记标题、正文、文件名**。
- 消费面：RescueView 状态区（取最新一条 + 上次启动那条并列）、导出诊断时整环附入（对位 Web W7 第三段）。
- 纯快照不刷 Diag 环（对位 Web W8 静默口径）；含救援动作的条目在下次启动折一条 `RESCUE log actions=… lastSnap=…` 摘要行后清环中动作标记（快照本体保留在环内供导出）。

### S6 救援动作留痕（R1 起）

- 安全模式内每个动作**执行前**先记 Diag 行（进程内直记，不需 Web 式 drain）：`RESCUE enter streak=n step=…`（进安全模式时）、`RESCUE action export|normal-retry|readonly|zip|cache-clear`、`RESCUE readonly open ok mode=direct|copy` / `fail err=…`、`RESCUE exit to=normal|readonly`。
- 跨启动留痕：哨兵文件加 `lastRescueAction` + 时刻字段；下次启动 LAUNCH 行尾附 `lastRescue=<action>`——定因时一眼看到「用户上次试过什么、试完还崩没崩」。

### S7 可再生缓存清理（R3，次级动作，明示定位）

- 清理清单（仅此三处）：`URLCache.shared` 全部缓存响应；`Library/Caches` 目录内容；`temporaryDirectory` 内本 App 导出残留。动作后记 `RESCUE action cache-clear bytes=…`（清前统计字节）。
- **绝不含**：Application Support 全域（`library/` 库与附件、`diag/` 日志）、UserDefaults（偏好与哨兵）。
- 文案定位（边界段内明示）：此动作只对缓存损坏型问题有效；若问题在数据或代码，它不会修好任何东西——不得写「修复」字样误导（与 Web repairBoot 的差异在此明示：Web 清的是真能致瘫的 SW/缓存层，原生此动作只是排查项）。

### S8 看门狗（R3）

- 阈值：冷启 **12 秒**未 `didLoad` → 判定挂死（与 Web W3 对齐；本地冷启实测数据耗时在秒级以内，12s 有足够余量且不误报慢设备）。
- 实现：`load()` 起点 arm 一个可取消的 `Task.sleep(12s)`（或 DispatchWorkItem），`didLoad` 置真（成功/失败两路，:487/:506）即取消。触发时若 bootMode 仍为 `.normal` 且未 didLoad：在 SplashHost 之上出救援浮条（构成复用 ErrBadgeOverlay 的根 ZStack 挂载位与玻璃卡口径，文案新键 `rescue.watchdog_bar`「应用似乎没有响应」+「进入救援」钮 +「×」）；点钮进 RescueView（与 S3 同页，来源标记 `from=watchdog`，记 `RESCUE watchdog fired step=<当前哨兵步>` 行）；应用随后活过来（didLoad 变真）浮条自动撤（订阅 @Published，对位 Web 2s 轮询自撤）。
- 分工写明：看门狗只管「活着但挂住」（进程在、加载链卡死）；「进程已死」（崩溃/强杀）由 S2 哨兵在下次启动管。运行期（didLoad 之后）的编辑器挂死不在本看门狗范围（已有场景哨兵留痕兜底）。

### S9 初始化延后清单（R1 顺带落）

首帧（didLoad）之前只许做：LangStore init（现口径不动）、哨兵判定（S2）、DiagLog `loadIfNeeded`、开库与列表加载本体。其余一律推到 didLoad 后首帧渲染完（`.task` 或 asyncAfter 0.3s）：

| 延后项 | 现行点位 | 理由 |
|---|---|---|
| Diag 归档冻结与自动删除的**写盘**部分 | `DiagLog.loadIfNeeded` 内（:2980-3026） | 读回判定保留在加载时（当天行要对），冻结合并写与 autodel 落盘移后——冷启写放大且与开库抢 IO |
| `refreshAttachmentTypes` | reload 主队列段（:562 一带） | 判图类型表非首帧必需，列表先出、类型回填后刷行 |
| 救援快照的开库后补写 | S5 新增点 | 本就设计为后补，不挡首帧 |
| ErrBadge 历史回放类动作（如有新增） | — | 预防性条款：徽章只呈现本会话新错，禁在首帧前做历史扫描 |

种子写入**不延后**（空库首启必需、且在加载链语义内）；`refreshAttachmentNames` 不延后（列表行呈现依赖附件名判图，属首帧必需）——延后清单逐项给理由，不一刀切。

### S10 语言键新增清单（五语齐备，落码时译全）

`rescue.title`、`rescue.boundary`、`rescue.status_prev_step`、`rescue.status_streak`、`rescue.try_normal`、`rescue.export_diag`、`rescue.open_readonly`、`rescue.export_zip`、`rescue.export_zip_unavailable`、`rescue.cache_clear`、`rescue.cache_clear_confirm`、`rescue.watchdog_bar`、`rescue.enter`、`rescue.readonly_banner`、`rescue.readonly_write_blocked`、`notice.launch_once`。共 16 键，五语包 316 键（0.9.45 天气批后）→ 332 键，verify [9] 计数同步。

### S11 verify_ios.sh 断言建议（新增 [12] 组「自救机制（R 批）」）

逐条可脚本化（grep/符号级，与既有组同风格）：

1. 哨兵文件常量在位：源码含 `launch-sentinel.json` 且 `LaunchStep` 步名集中定义（计数步名字面量出现处 == 定义处 + launchMark 调用处形态）。
2. 判定前移：`inspectPreviousLaunch`（或其改名后的判定函数）调用点位于 `Library.init` 路径内，且 ListView `.onAppear` 处**无**判定调用（防旧点位回潮双记）。
3. bootMode 分流：根 ZStack 源码段含 `bootMode` 条件渲染且 `.safe` 分支不构建 ListView（文本序断言：RescueView 出现在 ListView 之前且互斥）。
4. 安全模式四动作符号齐备：`exportEverything` 被 RescueView 引用、正常启动/只读/ZIP 三动作函数存在。
5. 红线扫描：RescueView 源码段（起止标记注释间）内**零** `upsertMemoJson`/`removeMemo`/`putAttachment`/`MomentLibrary.open(` 可写打开调用（只许 `openReadonly`）。
6. 只读契约并入 [6]：ffi 契约表 22 → 23 项，bindings 与断言表双向核对（沿用 [6] 既有机制）。
7. 只读门面拒写：拒写 guard 符号在 persist/种子/待删真删/putAttachment 四处齐备（逐处 grep）。
8. 看门狗常量：源码含 12 秒阈值常量（单一定义点）与 `RESCUE watchdog fired` 行模板。
9. 快照环：`rescue-log.json` 常量与环长 20 常量在位；快照字段黑名单扫描——快照构建段内无 `title`/`content`/`fileName` 字段引用。
10. 延后清单：`refreshAttachmentTypes` 调用点位于 didLoad 之后的代码段（以 SMOKE 行为界做文本序断言）；Diag 冻结写盘移位同法断言。
11. 语言键并入 [9]：`rescue.*` 16 键五语齐备（由 [9] 全包对账自动覆盖，本条只断言键数增量）。

### S12 Diag 新增打点行清单（汇总）

| 行模板 | 级别 | 出处规格 |
|---|---|---|
| `RESCUE enter streak=<n> step=<step>` | error | S3 进安全模式 |
| `RESCUE action <export\|normal-retry\|readonly\|zip\|cache-clear>` | info | S6 动作前记 |
| `RESCUE readonly open ok mode=<direct\|copy>` / `fail err=<…>` | info/error | S4 |
| `RESCUE exit to=<normal\|readonly>` | info | S3/S4 |
| `RESCUE watchdog fired step=<step>` | error | S8 |
| `RESCUE log actions=<…> lastSnap=<…>` | info | S5 下次启动折入 |
| `READONLY write-blocked kind=<persist\|seed\|delete\|attach\|import>` | warn（logOnce per kind） | S4 |
| `LAUNCH … lastRescue=<action>`（现 LAUNCH 行尾附） | 沿现级 | S6 |
| `LAUNCH sentinel write failed` | warn（logOnce） | S1 |
| `BOOT snap db=<bytes> memos=<n\|-> diag=<lines>` | info（logOnce per launch） | S5 |

---

## 四、红线与各动作数据影响面（总表）

**总红线（高于本规格一切条目）**：任何救援动作**绝不删除、改写、移动** `Application Support/library/moment.db`（及其 -wal/-shm，副本模式只拷不移）、附件文件与 `diag/` 归档；安全模式**不提供**任何「重置数据/删除资料库/恢复出厂」类按钮；用户文案明示「删 App 会连笔记一起删掉，不要删」（对位 Web 边界文案的站点数据警告）。

| 动作 | 触碰什么（写面） | 绝不触碰 |
|---|---|---|
| 进安全模式（判定本身） | 哨兵文件（streak/step/lastRescueAction）、Diag 行、快照环 | 库、附件、偏好 |
| 导出诊断 | 读 diag/ 全部文件 + 快照环；写 tmp 导出文件供分享 | 库零读零写（连打开都不做） |
| 尝试正常启动 | 清本次哨兵标记；随后走**常规加载语义**（含既有的待删过期真删、空库写种子——这是正常加载本身的既定行为、非救援新增写面，须在落码注释里分开写明） | 救援层自身不新增任何写 |
| 只读打开（direct） | 无（SQLITE_OPEN_READ_ONLY） | 库文件与 -wal/-shm 零写；门面全写路径拒绝 |
| 只读打开（copy 回退） | tmp 救援目录写**副本**三件套；副本可写打开但门面只读 | 源库三件套只读拷贝、零改动；副本在退出/下次启动时可删 |
| 导出备份 ZIP（只读态） | 读只读句柄组包、写 tmp ZIP | 库零写 |
| 清可再生缓存 | URLCache、Library/Caches、tmp 残留（写面 = 删除这三处） | Application Support 全域、UserDefaults |
| 看门狗出条/撤条 | 仅 UI 状态 + 一行 Diag | 一切数据 |

---

## 五、补齐后 0.9.43 同类问题的用户路径（验收口径）

1. 第 1 次点开闪退 → 哨兵记步、streak=1。
2. 第 2 次点开：判定前移命中 streak≥2 → **不再闪退**，直接进安全模式页：看得到停步与次数、数据完好声明。
3. 用户三条路任选：导出诊断发开发者（证据链闭环，不再依赖系统 .ips 的翻找）；只读打开先看/导出自己的笔记（数据可达性保底）；尝试正常启动（若是偶发已自愈）。
4. 开发者拿到 Diag：LAUNCH 步进（S1 加密后可定位到 reload 子步）+ RESCUE 动作行 + 快照环，定因材料齐全。

仍需说明的边界：若崩点早于 `Library.init` 判定点本身（如 LangStore init 或 @main 构建期），安全模式也进不去——这类崩溃只能靠 .ips 定因；S1/S2 已把判定点放在原生可及的最早位置，此边界在落码时如实记入 Diag 设计注释，不冒充全覆盖。
