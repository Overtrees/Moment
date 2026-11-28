# 日志两页打开慢根治（fix_diag_page_perf）

用户实报（2026-11-28 15:04）：点击进「日志诊断页」（DiagView）与「日志视图页」（DiagLogPage）反应有点慢。背景：Diag 当天环刚由 300 行扩至 2000 行（26bfc01，用户裁定）。本批全面排查、按红线根治；分支 fix/diag-page-perf（父 44b8d5b）。

## 一、打开路径逐段量测（结构量测）

本机无 swiftc、无真机，绝对耗时不可在此测——本节给**每段工作量的代码级量测**（proven：逐行回源计数）；设备绝对值由新增的 DIAGPERF 基线行 + fmtCount 计数在 0.9.67 装机后桥侧对账（见 §六），此为本批证据上限，不升级表述。

点按 → 路由 → 首帧 → 内容可读，四段在旧代码下的工作量（N = 当天行数，现网实测 1094、满环 2000）：

| 段 | 诊断页 DiagView | 视窗页 DiagLogPage |
|---|---|---|
| 路由/呈现 | navigationDestination 按需构建目的地，ChromeView 为薄壳（ZStack + 页头行），无重活 | 同左（值传递 entries，COW 拷贝近零） |
| 首帧 body | 过滤 O(N) + **当天卡急切构建 N 行** + 归档胶囊 ≤60 测排 + 库状态段 FFI 两读（libraryHash / attachmentCount） | 过滤 O(N) + **急切构建 N 行**（GeometryReader 满幅量测同遍发生） |
| 每行单价 | `Text(e.line)`：**line 每次访问新建 DateFormatter**（构造 + 格式化） + Text 文本布局 | 同左（行内逐行 font/lineSpacing） |
| 打开后持续 | **body 挂 @Published 观察：全应用每记一行日志整遍重演上表全部**（含本页开关/选级自记的行） | 不观察 DiagLog（快照页），无此项 |

## 二、病灶定案（分级）

1. **P0 · 急切全量行构建（两页同型）**：两页行容器均为非惰性 `VStack` + `ForEach(全部行)`，ScrollView 内全部行在首帧同步构建并布局，与可见行数（当天卡约 24 行 / 视窗页约 41 行）无关，恒付 N 行全价。
2. **P0 · 行串格式化逐次新建格式化器（与 1 相乘的常数因子）**：`DiagEntry.line` 与 `dayKey` 每次访问 `DateFormatter()` 新建——格式化器构造是 ICU 初始化级开销（量级数十 µs，设备值待桥测），旧开页单遍即 N 次构造、N 次格式化；`DiagLog.diagStamp` 同型（加载/冻结路径，非开页关键路径，一并收口）。
3. **P1 · 诊断页发布粒度（重演乘子）**：DiagView 以 `@ObservedObject` 直挂 DiagLog，today/archives 为 @Published——打开期间任何模块记一行，本页 body 整遍重演（P0 全价重付），页内操作（自动删除开关、级别选择）自记的 G6 行同样触发自重演。乘子与行数无关、随打开时长与记行频率无界增长；这是「不只是打开慢、页面整体发沉」的来源。
4. **P2 · 附带同型**：库状态段 FFI 两读位于 body 内，本身与行数无关（常数项），但被 3 的乘子反复重付；快照化后回归「打开时一读」。

**与 300 行时代对照**：常数项（页头、归档胶囊 ≤60、库状态 FFI）两时代相同；线性项（过滤、行构建、格式化构造、布局）随 N 由 300 → 2000 为 ×6.7（现网 1094 行 ≈ ×3.6）；乘子项（病灶 3）不随 N 变、随使用时长变。三者叠加即本次体感来源——扩容本身没错（2000 行是用户裁定，不回退），错在呈现面按 300 行时代的全量急切模型没跟上。

**普查排除（非病灶，附据）**：RescueView 虽同观察 DiagLog，但只读计数、body 轻量；桥 diag 读口（MomentBridgeTools）用 ts/level/text 原始字段组包、不经 `.line`，且分页切片在前；`buildExportFile` 内一处日期格式化器为导出时单次调用、非开页路径；`DiagArchive.lines` 无消费方；设置页入口与 ChromeView 均无全量活；DiagLog 读口无锁竞争面（全主队列串行、无 NSLock）。

## 三、根治落码（MomentApp.swift 单文件内四面收口）

1. **格式化单点**：DiagEntry 立 `dayFmt`/`timeFmt` 两静态单例，line/dayKey 改经单例（配置与逐次新建逐项等价：仅设 dateFormat、不动 locale/calendar，输出逐字不变）；DiagLog 立 `stampFormatter` 单例供 diagStamp（POSIX 口径不变，零依赖纪律不变）。
2. **惰性行栈**：两页行容器 `VStack` → `LazyVStack`（alignment/spacing 不变，行字面/行距/命中口径逐项保全），只构建可见行，滚动按需续建。
3. **呈现快照模型（诊断页）**：撤 `@ObservedObject diag`；快照存既有 DiagUI 的两 @Published（todaySnap/archSnap，初值 = 构造时刻现值），刷新收口 `refreshSnap()` 单点，消费面三处：onAppear、页内自动删除开关（视图 Toggle 与自检动作同体各一）。**新鲜度守恒点**：视窗页入参在导航时刻直读单例（与旧代码 body 恒新求值等价）、导出在动作时刻直读单例、自检面状态闭包改直读单例（探针读数仍为实时值）。行为取舍明说：打开后外部新记行不再实时尾随进卡面——视窗页自始即快照模型、Web 诊断页同为打开时渲染，尾随从未是既定行为；本页自记行在重进/导出/桥读均可见。
4. **拼装计数与打开基线**：DiagEntry 立进程级 `lineFormatCount`（只在 line 拼装处 +1），两页自检面各暴露 `fmtCount` 读数；两页 onAppear 各记一条 `DIAGPERF open view=diag|logpage … fmt=<计数>` 基线行（诊断页在快照捕获后记，不入本页快照）。

未采「打开先占位再填」式遮丑：病灶在呈现模型本身（急切 + 逐次构造 + 发布粒度），根治后首帧即真内容，无占位必要。

## 四、断言（verify_ios.sh 新增 [73] 组 DP73-1..5）

- DP73-1 格式化器单点：DiagEntry 段 `DateFormatter()` 恰 2（仅两单例闭包内）、两单例各 1；DiagLog stampFormatter 声明与消费各 1。
- DP73-2 惰性行栈：两页各 1 处 `LazyVStack(alignment:`、全文件恰 2。
- DP73-3 快照模型：DiagView 段 @ObservedObject 直挂零残留、DiagUI 两快照各 1、`refreshSnap()` 定义 + 调用面共 4、`ui.todaySnap` 消费恰 3、视窗页入参直读恰 1。
- DP73-4 拼装计数：声明恰 1、增点恰 1、两页 `"fmtCount"` 共 2。
- DP73-5 打开基线行：`DIAGPERF open view=diag|logpage` 各 1。

**负对照五项实做**（突变副本 + 同判据复刻器）：line 内加回逐次新建 → 仅 DP73-1 红；一页行栈改回 VStack → 仅 DP73-2 红；DiagView 加回直挂观察 → 仅 DP73-3 红；摘计数增点 → 仅 DP73-4 红；摘视窗页基线行 → 仅 DP73-5 红。原件五项全绿。

**断言体系实证一笔**：本批初版快照曾误用 `@State` 持仓，被既有 [2] 组「无 @State（宏插件缺失）」当场拦红——改存 DiagUI（ObservableObject）后消解。旧锁拦新代码，棘轮有效。

## 五、验证分账

- 本机 verify（worktree 干净树，绝对路径调用）：**717 ✓ / 5 ✗**；基线树（同父 44b8d5b 另建 worktree 同法跑）**712 ✓ / 5 ✗**，5 红逐项同名同类——全为构建产物缺失（ipa/Assets.car/开屏双 JSON/语言包），tree 构建后自解；源码面零新增红、新增 [73] 组五项全绿。（注：/tmp 下同名日志曾被并行代理覆盖一过，分账以当场读数为准。）
- cargo：本批零 Rust 改动，未跑。
- Swift 类型级编译门：本机无 swiftc，留 tree 0.9.67 组版冒烟（改动均为既有类型内修改 + 一处 ObservableObject 属性增补，无新文件、build-app2.sh 遍数不变）。

## 六、装机验收点（0.9.67 桥自办）

1. 两页开页 Δfmt 对账：开页前读 fmtCount、开页后读 DIAGPERF 行内 fmt——增量应为可见行量级（数十），而非 N（1094/2000）量级。
2. 开页耗时基线：桥侧点按时戳与 DIAGPERF 行时戳差，两页各记，与 0.9.66 体感对照。
3. 页内操作不重演：诊断页内切级别/拨自动删除开关后 Δfmt 不随操作次数全量增长（仅本地过滤重算 + 可见行）。
4. 滚动到底：两页滚至末行，行按需构建、无空白段、无行错位；归档页（大日归档）同验。
5. 快照语义目检：打开诊断页后经桥记一行新日志，卡面不尾随（预期内）、重进可见；导出全量仍含该行（动作时刻直读守恒）。
