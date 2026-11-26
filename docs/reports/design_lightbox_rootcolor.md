# 灯箱颜色链彻底重构——取证与方案设计

- 性质：只出方案、不落码（方法裁定：根因与方案先给用户看、定了再落码）。
- 取证基线：本地 HEAD `e689012`；生产构建 `f43a1eceb5`（含灯箱摘压暗 `1f94aba`，2026-11-24 上线）。
- 行号口径：下文文件行号均以 HEAD `e689012` 为准。
- 证据分级：proven（读码/实测可复核）/ inferred（推断）/ unknown（待真机证据）。

## 0. 头号疑点：摘除态带仍近黑，M2 因子律不成立（2026-11-24 08:51 用户补证）

摘除 DimLayer 预压暗后，根色在灯箱打开期间应保持编辑 base（浅色默认 `#FAFAFA`，即 250）。按既有因子律 M2（带 = 根色 ×(1−α)，α=0.88 为灯箱遮罩自身的 alpha），带应 ≈ 250×0.12 ≈ 30，与视口内灯箱呈现同值。**用户真机判读：上下带「还是近黑」**——即带未按 M2 预测变为 ≈30。M2 在摘除态不成立（proven by user verdict；带的精确像素值 unknown，未逐列剖面）。

本报告据此把疑点拆为两路逐点核：

- **疑点 (i)**：灯箱打开路径上是否还有别的根色写入把根色写暗（残存压暗）。→ §1 逐点核完，结论 **proven 无此写入**。
- **疑点 (ii)**：浏览器带色是否改由全屏遮罩自身派生（与根色无关或不只由根色决定）。→ §5 候选律与相容性分析；最终坐实靠 §10 的一次真机取证（截图逐列剖面 + Diag 根色实测行同测）。

## 1. 取证一：灯箱打开路径残存根色写入逐点核（疑点 i）

### 1.1 全仓根色写入点全清单（grep `apply_root_bg` 实证，共 4 处调用）

`apply_root_bg`（main.rs:290-344）是唯一合法写者：Some(c) 时 html+body 内联 `backgroundColor` 直写（权威路径）+ `:root` 变量 `--mn-root-bg`/`--mn-root-rgb` 同值镜像；None 时两路全清、回落 CSS `--primary-bg`。全部调用点及其在「灯箱打开」窗口内的触发条件：

| # | 调用点 | 写入值 | 触发条件 | 灯箱打开时是否触发 |
|---|--------|--------|----------|--------------------|
| 1 | App 派生 effect（main.rs:1063） | 派生 target（见 §3） | 派生输入变化：page / selected / scheme_tick / DimStack 信号 | **否**——开灯箱不改任何派生输入（灯箱信号是 Editor 内部信号，见 §2） |
| 2 | open_memo 发起任务先行写入（main.rs:1313） | 新篇 `effective_bg` | 用户从列表打开备忘 | 否——发生在进编辑器时，灯箱尚未开 |
| 3 | Editor `set_bg` 换色（editor.rs:1103） | `effective_bg(&color)` | 用户在编辑器内主动换背景色 | 否——用户操作，非灯箱路径 |
| 4 | Editor scheme 处理（editor.rs:2273） | `dim_stack.dimmed(&base)` | 系统深浅色 mq change | 仅当开着灯箱时系统恰切换深浅色才触发；且其值见 1.3，恒为 base 本值 |

桥 JS 侧无任何根背景写入（grep `backgroundColor` 于 bridge.rs 仅命中选区高亮样式与量测读数，非写入）。

### 1.2 DimStack 空栈派生（proven 恒空）

- `DimLayer` 组件仍定义于 main.rs:488-492，`DimGuard`（main.rs:460-484，Drop 时 pop、tag=="lightbox" 时补 `log_lbx("pop")`）仍在，但**全仓无任何 `DimLayer` 调用点**（grep 仅命中定义与两处注释）——摘除 `1f94aba` 后 DimStack 恒空。
- App 派生（main.rs:1032）`alpha = max_alpha()` 恒 0 → target = base 原值，不走 `dim_toward_black`。
- 连带：DimGuard 的 LBX pop 兜底已不可达（异常关闭少一条 Diag 证据行，editor.rs:3722-3726 注释已明说）；`DimStack::dimmed`（main.rs:446-455）在空栈时恒返回 base 本值。

### 1.3 scheme 分支（proven 写 base 本值）

Editor scheme effect（editor.rs:2220-2275）：mq change 时同任务直写，target = `dim_stack.dimmed(&base)`（editor.rs:2266）。空栈下 dimmed = base，故即使开着灯箱时系统切深浅色，写入的也是新 scheme 的 base 本值（浅 #FAFAFA 系 / 深色 effective_bg），**不存在写暗残留**。probe_root_dim ⑦ 已按此口径断言并在 box 转绿（开灯箱切深色根色落 #595959 本值）。

### 1.4 页面状态残留（proven 无）

- 灯箱信号 `lightbox` 是 Editor 实例内部信号（editor.rs:1741，context provider :1742），不进 App 的 page/selected 状态；App 派生的 base 只读 selected 备忘的 `bgColor` extra，与灯箱在否无关。
- VARMUT 监视（main.rs:765-808）常驻盯 html/body style 的 `--mn-root-bg`/`--mn-root-rgb`/内联 backgroundColor，任一变更必记一行——若真机开灯箱期间有任何晚到写暗，Diag 必有 VARMUT 行可查（§10 判读表用此行做 (i) 的设备侧终判）。

### 1.5 附带发现：文档注释与现状矛盾（落码时须同步订正）

main.rs DimStack 长注释（约 :388）仍写「注册方沿革：现行仅灯箱（α0.88）」，与 1.2 的零调用点现状矛盾——该注释是预压暗时代文本，摘除时未同步。属文档漂移、非行为问题；重构落码时须一并订正，避免后续排查被误导。

**§1 结论：疑点 (i) 在代码层 proven 不成立——灯箱打开路径上没有任何把根色写暗的残存写入；根色在灯箱期间恒为编辑 base（设备侧最终确认看 §10 的 LBX/VARMUT 行）。带仍近黑的原因不在应用的根色写入面，须从浏览器带色派生机制解释（§5）。**

## 2. 取证二：现行灯箱全链

### 2.1 打开路径（proven）

- 唯一显式置位点：blocks.rs BlobMedia（:357-382）——IDB Blob URL 加载完成后，img 的 onclick 把 URL 写入 Lightbox context 信号（:378 `s.set(Some(u2.clone()))`）。图文卡、图片卡、画廊等一切图片面共用此组件，故入口统一。
- 渲染：editor.rs:3719-3737，`lightbox` 信号为 Some 时渲染 `div.lightbox`，onmounted 记 `diag::log_lbx("open")`（:3727），内含单张 img。
- CSS：editor.css:1468——`position:fixed; inset:0; z-index:10000; background:rgba(0,0,0,0.88)`，flex 居中，padding 四边 `max(20px, env(safe-area-inset-*))`（浮层安全区自适配，用户口径有意偏离原版平值 20px），`overscroll-behavior:none`。:1469 img max 100%/contain/radius-12。
- 灯箱节点无 animation / transition / transform（全仓排查 proven）。
- 打开动作不触任何根色代码（与 §1 结论一致）。

### 2.2 关闭路径（proven）

- 正常关闭只有点按一路：`div.lightbox` onclick（editor.rs:3728-3731）先记 `log_lbx("close")` 再 `lightbox.set(None)`。
- Esc 不关灯箱：桥内 `.lightbox` 引用只有滚动锁三路（bridge.rs:1564-1580、2807-2811）与点外排除（:2729）；全局 Esc 链（bridge.rs:1519-1525 等）处理块选中/拖拽取消，不触灯箱信号。此点与原版一致（原版亦无 Esc 关灯箱，2026-11-23 灯箱四面排查 proven）。

### 2.3 异常路径（编辑器卸载带走，proven）

- 回列表（串行同帧提交）、换篇（keyed 重挂）、wiki 跳转等使 Editor 实例销毁时，`lightbox` 信号随实例消失，新实例初值 None——不存在「灯箱残留信号」。
- 无灯箱专属的根色恢复动作，也不需要：根色由 App 派生随页面状态自动回落（§3）。
- 桥滚动锁以 `.lightbox` 节点在否为事件时判定源（bridge.rs:1564-1580），节点消失即自动 disengage，无登记可漏。
- Editor use_drop（editor.rs:2297-2304）同步直调 `sync_editor_cleanup`（bridge.rs:2892 起）摘除全部具名全局监听并做 CLEAN 前后普查 + `log_census("EDIT")`；**明确不碰根背景**（根色不归 Editor 清理，归 App 派生）。
- 清理缺口逐条：
  1. DimGuard 的 LBX pop 兜底不可达（§1.2）——异常关闭时 Diag 无灯箱专属关闭行，只能靠 CENSUS/POST 间接确认。
  2. CENSUS_JS（diag.rs:318-323）计数面含 `.editor-stage`/`#editor-root`/`.page-leaving`，**不含 `.lightbox` 计数**——卸载后无「灯箱残留 = 0」的直接断言行。
  3. LBX 量测只在 open/close 两点采样，无开后延迟重采样（对比 log_modal 有 300/1000ms 两发，diag.rs:441-444）——开后晚到变化抓不到。

## 3. 取证三：根色统一真源现状

### 3.1 写入（单点）

`apply_root_bg`（main.rs:290-344）唯一写者，双路同值（内联权威 + 变量镜像），失败记 ROOTERR 行。调用点全清单见 §1.1 表。

### 3.2 派生（App 层）

App use_effect（main.rs:1004-1066）：

- 输入：page 状态、selected 备忘、scheme_tick、DimStack。
- base = page 为空（编辑器在场）时 selected 备忘的 `effective_bg`（editor.rs:946-962：自定义色深色压暗、否则原色；默认浅 `#FAFAFA` / 深 `#000000`），否则 None（回落根页面色）。
- alpha = DimStack.max_alpha()（现恒 0）；alpha>0 时 base（或回落态的 `primary_bg_value()`，main.rs:347-360，computed `--primary-bg`）经 `dim_toward_black`（main.rs:364-377，channel×(1−α)）混合。
- target 变化记 `root bg -> …` 行，恒调 apply_root_bg，随后 `log_probe("APP","ROOTSET")` 回读实值。

### 3.3 监听

- App 常驻 `spawn_scheme_listener`（main.rs:86-105）：mq change 才 bump scheme_tick 并记行，驱动派生重算。
- Editor 侧 scheme effect（editor.rs:2220-2275）：同 mq 变化同任务直写（与 App 派生无定序、但同值，见 §1.3）。
- VARMUT MutationObserver（main.rs:765-808）：use_hook 常驻不摘，监视面见 §1.4。

### 3.4 页面切换时序（串行同帧，白带根治口径）

Nav（main.rs:496 起长注、:560-760）：编辑器→列表为串行同帧——`begin_editor_leaving` 只登记 LeavingEditor + 翻 editor_closing、selected 保留（离页窗口内派生继续给编辑底）；`arm_unload` 320ms 到时，同一任务清离页条目/selected/closing，记 TRANS committed + POST 普查 + CENSUS + LATE 300/1000/3000 三发重采样，随后一次渲染提交内「卸载编辑器 + 挂载列表 + 根色翻转」同帧完成。open_memo 则先 clear_editor_leaving、再先行写入新篇 effective_bg（§1.1 #2）。

### 3.5 Diag 现有量测面

- PROBE_JS（diag.rs:300-316）：html/body computed、var/rgb、内联、vv、sy、sat。
- CENSUS_JS（diag.rs:318-323）：见 §2.3 缺口 2。
- LATE_JS（diag.rs:326-335）：只根色诸项。
- LBX_JS（diag.rs:338-356）：documentElement computed root + `.lightbox` 挂载链首三段 + rect + vv/sy/sat。缺口：不记 body computed/变量/内联分项、不记 `.lightbox` 自身 computed 背景、不记 scheme 与备忘 bgColor/派生输入、无延迟重采样（§2.3 缺口 3）。

## 4. 取证四：原版灯箱对照

- 状态：src/app/editor.js:294 `lightboxSrc`；置位在 use-editor-dom.js:169-173（已有图点击 `setLightboxSrc(existingImg.src)`）。
- 渲染：editor.js:3333-3336，内联样式 div（fixed inset:0、z 10000、`rgba(0,0,0,0.88)`、flex 居中、padding 20 平值、cursor zoom-out）+ img（max/contain/radius var）；点关 `setLightboxSrc(null)`。
- **原版开/关灯箱不触任何根色代码（proven）**：根色由 editor.js:617-637 的 useLayoutEffect 按 effectiveBg/isDarkMode 写 html/body，依赖不含 lightboxSrc；handleClose（:937-941）等 320ms 后清 html/body 内联背景并删 body-before-bg 再 onClose；编辑器根自身 backgroundColor: editorBg（:2460）。
- 与 Rust 的结构差异：内联样式 vs 类规则；padding 20 平值 vs `max(20px, env(...))`（用户浮层自适配口径，有意偏离）；原版无滚动锁（Rust 滚动锁为用户 2026-11-23 裁定偏离）；原版无 LBX Diag；原版根色是编辑器自有 effect，Rust 是 App 统一派生（本次重构的基线正是后者，不回退）。


## 5. 取证五：带色派生候选机制与因子律相容性（疑点 ii）

记号：R = 根色实值；α = 0.88（灯箱遮罩 alpha，摘除前后不变）；P = 视口内灯箱呈现色 = R 与遮罩的合成 = R×(1−α)（R=250 时 P≈30；R=30 时 P≈4）。

### 5.1 三个时代的实测数据（proven，用户真机/截图剖面）

| 时代 | R | P | 顶带 | 底带 |
|------|---|---|------|------|
| 预压暗（根色被 DimStack 压到 30） | 30 | ≈4 | ≈0 | 见注 |
| 备份模态对照（α=0.28，R 被压到 174） | 174 | ≈125 | 125（=R×0.72） | 174（=R 精确） |
| 摘除后（f43a1eceb5） | 250（代码 proven；设备 LBX 行待 §10 确认） | 30 | 近黑（用户判读） | 近黑（用户判读） |

注：备份态底带曾被浮动工具栏 chrome 本身占据（像素剖面 proven），底带读数有混杂因素，判读须与顶带分开。

### 5.2 候选律逐条拟合

- **L1（旧 M2）：带 = R×(1−α)。** 预压暗预测 3.6≈实测 ✓；备份顶带 125 ✓；摘除后预测 30，用户判读近黑 ✗。**在摘除态被证伪**（除非「近黑」实际即 30 的口头描述——像素值 unknown，§10 取证第一优先就是测这个数）。
- **L2：带 = P×(1−α) = R×(1−α)²（浏览器对已合成的呈现色再叠一层同 α 因子）。** 预压暗预测 ≈0.4 ✓；摘除后预测 ≈3.6，近黑 ✓；但备份顶带预测 174×0.72² ≈ 90 vs 实测 125 ✗。单独成立不了，除非顶带因子随层类型不同。
- **L3：带由全屏遮罩层自身派生（浏览器采样视口边缘的呈现层/顶层 fixed 层色作带底，再叠自身因子），与 R 无直接函数关系。** 与摘除后现象相容（遮罩层没变，带就不变——这正解释了「摘除压暗后带纹丝不动」）；与预压暗时代「R 改 30 后带跟着变 ≈0」表面矛盾，但该时代 P 同步变到 ≈4，L3 以 P 为源同样预测近黑，**两时代在 L3 下都拟合**（带源是 P 而非 R 时，预压暗与摘除的差别只在 P：4 vs 30；带若 = P×(1−α) 或 P 再叠固定深色因子，两时代带分别 ≈0 与 ≈4–22，都可被读作近黑）。L3 是目前唯一能同时容纳三时代的框架，但其精确函数形 unknown。
- **L4：挂载时刻锁存（白带 inferred 模型同族）**——浏览器在整屏层挂载冲击帧锁存带色采样、其后稳态 R 正确也不重采。摘除前后挂载的都是同一遮罩层，锁存值同为近黑 ✓ 相容；预压暗时代锁存发生在 R 已压暗之后，带 ≈0 ✓。可与 L3 叠加，靠 §10 的「开灯箱后改 R」实验区分（见 5.4）。

### 5.3 数学约束（硬选根色了事为什么不行）

设目标为顶带、底带、视口内呈现三区一致。在「底带 = R 精确」（备份态 proven）与任一含 (1−α) 因子的顶带律下：顶带合要求 R=P，底带合要求 R=B（编辑 base 250），两者只在 α=0 时同解。**单一根色下三区不可同时合**——与预压暗时代定案的「三区数学不可兼得」同构。区别在：预压暗时代不可兼得是应用自己引入的（根色被压暗后与因子叠加）；摘除后若带源真是呈现层（L3），则连「选 R」这个杠杆都不存在于带上。

### 5.4 应用可控 vs 不可控（如实分界）

**应用可控（根色统一真源内）：**
- R 的值与写入时机（派生、先行写入、同帧提交）；
- 遮罩层自身的呈现参数：alpha、是否不透明、挂载结构（挂在哪一层、是否整屏 fixed）；
- 呈现色 P（经 R 与 alpha 共同决定）。

**应用不可控（浏览器带区绘制层）：**
- 带以何为源（R / P / 顶层 fixed 层）、带上叠何种因子——网页层无 API、无可调量；env/视口单位不参与带色（既有实证）；
- 底部浮动工具栏 chrome 对底带的占据与混杂。

**由此得到的真实杠杆清单（按 §10 证据分支启用）：**
1. 若带源 = R（L1 复活，即像素实测带 ≈30、「近黑」为口头近似）：无须改色，问题降级为观感/文案问题，或按用户口径接受。
2. 若带源 = P（L3 以 P 为源）：唯一杠杆是 P 本身——但 P 是灯箱呈现色，改 P 即改灯箱观感（如把遮罩改为不透明纯黑，P=0，带随之为 0，与呈现一致但属呈现层决策、且偏离原版 0.88 半透）。
3. 若带 = P×(1−α) 型（L2/L3 复合）：R 与 alpha 都救不回带与 P 一致（带恒比 P 再暗一档），只能接受残差或改呈现层形态。
4. 若为锁存型（L4）：杠杆在挂载时序——让遮罩挂载帧的根色/呈现即为目标稳态值（与串行同帧口径同族），须先以实验坐实锁存存在。

## 6. 方案：基于根色统一真源的灯箱重构设计

前提：本方案先把灯箱收编为根色统一真源的**正式派生输入**（颜色链的彻底重构部分），无论 §5 最终带源落在哪一律，这一步都成立且必要——它消除的是「灯箱对根色链隐形」这一结构缺陷（现状：派生不知道灯箱在场，scheme 先行写入靠 dimmed() 空转同值、Diag 无灯箱派生输入行）。呈现层杠杆（§5.4 的 2/3/4）按 §10 证据分支另行决策，不在本方案内硬选。

### 6.1 状态归属

- 新增 App 层派生输入 `lightbox_open: Signal<bool>`（或等价的呈现层在场登记），由 App 经 context 提供，**不复活 DimLayer/DimGuard 私有登记**、不新增 editor 侧直写通道。
- Editor 的 `lightbox` 信号仍是呈现真源（挂载/卸载语义不变）；Editor 以一个同步 effect 把 `lightbox.read().is_some()` 镜像写入 App 输入。镜像只报在否、不报 URL。
- 生命周期与 Editor 实例绑定：实例销毁时镜像输入必须同归 false——镜像写点放在 Editor 渲染作用域内随实例生灭，并由 §6.3 的卸载断言兜底（use_drop 同步清的既有口径，不走 spawn）。

### 6.2 派生与写入

- App 派生（main.rs:1004-1066）输入集加入 `lightbox_open`：target 的计算顺序仍为 base →（DimStack，现恒空，保留）→ 灯箱口径（按 §7 决策点取值）。派生仍是唯一计算者，写入仍只经 `apply_root_bg`。
- 开/关灯箱与根色翻转同任务/同提交：镜像 effect 与派生 effect 在同一渲染提交内完成（参照串行同帧口径），不允许「遮罩已挂载、根色下一帧才跟」的分帧窗口。
- 两处先行写入收口：editor.rs:2273 scheme 分支与 editor.rs:1103 set_bg 分支改走同一派生 helper（含灯箱输入），不再各自调 `DimStack::dimmed` 或裸 `effective_bg`——先行值与派生值由同一函数计算，杜绝「直写值与派生值不同口径」的既有竞速类问题在灯箱态复发。
- open_memo 先行写入（main.rs:1313）同理改走该 helper（此时灯箱输入恒 false，值不变，纯收口）。

### 6.3 恢复语义与异常清理

- 正常关：点按清信号 → 镜像 false → 派生同提交恢复 base。无独立恢复动作。
- 异常路径（卸载带走/换篇/回列表）：Editor 实例销毁，镜像输入随实例失效；App 派生在提交帧按新页面状态取值——与 Nav 串行同帧语义天然同帧，不新增计时器、不新增清理任务。
- 兜底断言：CENSUS 增 `.lightbox` 计数（§8），卸载后 CENSUS 行须见 `lbx=0` 且根色 = 新页面派生值；任一不符记 Diag 异常行（结果侧量测，非意图行）。

### 6.4 文档订正（随落码同批）

- main.rs DimStack 长注释中「现行仅灯箱（α0.88）」等预压暗时代文本按现状订正（§1.5）；editor.rs:3732-3736 灯箱旁注按新派生输入口径改写。

## 7. 根色口径与决策分叉（不硬选）

设 base B（浅色默认 250）、遮罩 α=0.88、呈现 P=B×0.12≈30。

| 口径 | 灯箱期 R | 与底带律（=R 精确） | 与顶带 L1（=R×0.12） | 与 L3（带源=P） | 代价 |
|------|----------|--------------------|--------------------|----------------|------|
| O1 保持 base | 250 | 底带 250，与 P=30 差 220 ✗ | 顶带 30 = P ✓ | 带跟随 P≈30 或更暗，与 R 无关 | 无（现状） |
| O2 R = P（派生 dim(base, 0.88)） | 30 | 底带 30 = P ✓ | 顶带 ≈4，与 P 差 26 | 带源若为 P 则 R 不相干、白改 | 复活压暗形制（与摘除裁定的区别：这次经统一派生而非私挂登记）；关灯箱恢复须同帧 |

**决策点 D1（取决于 §10 像素实测）：**
- 实测带 ≈30（L1 成立）→ 选 O1，收口 §6 的结构重构即可，颜色口径不动；用户所见「近黑」实为 30 的观感，是否接受由用户定。
- 实测带 ≈0–4 且 Diag 证 R=250（L3/L2 成立）→ 根色口径对带**无杠杆**（§5.4），O1/O2 之争作废，升级为呈现层决策 D2。
- 实测带 ≈0–4 且 Diag 证 R≠250（有未知写暗）→ 回到疑点 (i) 的设备侧分支，按 VARMUT 行定位写者，先修写入面再谈口径。

**决策点 D2（呈现层，仅 D1 第二分支触发，须用户拍板）：**
- D2-a 接受残差：带近黑、呈现 30，差值在带区，应用无杠杆——如实关闭。
- D2-b 遮罩改不透明（alpha=1，P=0）：带与呈现同为 0，一致性达成；代价是灯箱失去半透感、偏离原版 0.88。
- D2-c 遮罩 alpha 降低（如 0.6，P≈100）：带与呈现的差值量级缩小但不同值，且灯箱变亮、偏离原版更远。不推荐，仅列全。

**推荐**：先执行 §6 结构重构 + §8 Diag 补点，部署后按 §10 做一次真机取证，按 D1 分支落口径——不预先硬选 O2，避免重蹈「按推断律改色、真机证伪」的覆辙。

## 8. Diag 补点清单（结果侧量测）

1. **LBX 行扩容**：LBX_JS 增 body computed、`--mn-root-bg`/`--mn-root-rgb` 变量、html/body 内联分项、`.lightbox` 自身 computed background、当前 scheme、备忘 bgColor 与派生输入快照（base、lightbox_open、alpha、target）——一行内意图与实值同呈，脱节即显形。
2. **LBX 延迟重采样**：open 后挂 300/1000/3000ms 三发（比照 log_late/log_modal 口径），抓开后晚到写入与锁存后的稳态值。
3. **CENSUS 增 `.lightbox` 计数**（`lbx=`），卸载/提交点普查含灯箱残留断言（§6.3）。
4. **派生输入行**：App 派生在 target 变化行（`root bg -> …`）附输入摘要（page/selected/scheme/lightbox_open/dim_depth），使「为什么写这个值」可回溯。
5. **VARMUT 既有行不改**，作为开灯箱窗口内未知写者的终判证据（§10 判读表引用）。

## 9. 探针断言组（probe_root_dim 增补，box 口径）

1. 开灯箱同提交内：`.lightbox` 在场 ∧ 根色 = 派生 target（按当时口径）∧ LBX open 行含派生输入快照且与网页层实值一致。
2. 开后 300/1000/3000ms：根色恒 target、无 VARMUT 异常行（除派生自身写入外无第二写者）。
3. 关灯箱同提交恢复 base；LBX close 行根色 = base。
4. 异常路径（开着灯箱离页）：提交帧 CENSUS `lbx=0` ∧ 根色 = 列表派生值；离页窗口内根色恒编辑口径值（串行判据组同族）。
5. 开着灯箱切 scheme：根色落新 scheme 的派生同值（经统一 helper，断言 scheme 行与派生行同值）。
6. 开着灯箱换篇（keyed 重挂）：新实例灯箱初值 none、CENSUS `lbx=0`、根色 = 新篇派生值。
7. 静态锁（verify 增节）：灯箱路径不得出现 `DimLayer` 调用复活；editor 侧不得新增 `apply_root_bg` 直调点（先行写入只准经统一 helper）。

注：无头口径测不到 iOS 视口外带区，以上只锁网页层颜色链；带区终判归 §10 真机协议。

## 10. 真机一次操作定案协议（用户只做一次）

**操作**（在现行构建 f43a1eceb5 上即可先行一轮，为 D1 提供像素证据；§6 落码后复跑一轮验收）：

1. 打开一篇**浅色默认底（无自定义 bgColor）**备忘，进编辑页；
2. 点开一张图片进灯箱，等 2 秒（避开挂载瞬态）；
3. 截一张全屏图（须含状态栏与底部 Home 区）；
4. 关灯箱，回设置页导出 Diag 全文回传。

**助手侧判读（截图逐列剖面同测四值）**：取截图同一列 x（如屏宽中点避开图片主体处）逐行剖面，读：顶带像素（状态栏区中点行）、视口内灯箱像素（带下缘紧邻行）、底带可分离像素（布局视口下缘外、避开浮动工具栏占据段）、关灯箱后同位置页面像素（对照）。同时读 Diag 的 `LBX open` 行（root= 实值）、open 窗口内的 VARMUT 行、`root bg ->` 行。

**判读表（四象限定案）**：

| Diag R（open 期） | 截图带像素 | 结论 | 后续 |
|---|---|---|---|
| 250 | ≈30 | L1 成立，「近黑」为 30 观感 | D1 第一分支：O1 收口，观感由用户定 |
| 250 | ≈0–4 | L3/L2 成立，带源为呈现层，根色无杠杆（proven） | D2 呈用户拍板 |
| ≠250 | 任意 | 疑点 (i) 设备侧复活：有未知写者 | 按 VARMUT 行时刻定位写者，先修写入面 |
| 250 | 顶≈30、底≈0（或反之） | 上下带异律（底带含工具栏混杂） | 分带处置：顶带按 L1，底带单独定性 |

剖面读数注意：JPEG/HEIC 量化误差 ±4 色阶内不判差；图片主体压到采样列时换列重读；底带先判是否被浮动工具栏占据（与备份态 proven 形态比对）。

## 11. 待用户确认项

1. §6 结构重构（灯箱收编为统一派生输入 + 两处先行写入收口 + Diag 补点）是否按此落码；
2. §10 协议先在现行构建跑一轮取像素证据，还是与 §6 落码合并为一轮（先取证更稳：口径决策有据后再落码）；
3. D2 仅在证据落到第二分支时才需要拍板，现不预决。
