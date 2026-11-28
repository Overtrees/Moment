# 状态栏字色三轮根治：全页面统一带区渲染采样（fix_statusbar_render_sample）

状态：落码完成、tree 全量冒烟 ALL GREEN（/data/home/smoke63e-tree.log，verify 587 ✓ / 0 ✗），未提交、留主线组 0.9.63。
缘起：用户 2026-11-28 08:39 改判——二轮只把图片页换成带区实况采样、开屏换成公式色，其余页面仍是静态登记；用户口径是**所有页面（含开屏期间）一律按状态栏带区实际渲染像素动态识别定字色**。08:43 补充定性：**该机制是浅/深色模式之上的增强版**——模式仍是底层基础，渲染采样是在模式之上做精细化判定的增强层，专治模式本身判不了的面。

## 一、分层：模式层 / 增强层各自管什么

| 层 | 管什么 | 本轮处置 |
|---|---|---|
| 模式层（基础） | 主题令牌 dyn（T.bg / T.memoBg 的 trait 动态解析）、trait 变化链（根观察器 + 各承载 traitCollectionDidChange）、模式派生的静态登记色（MomentStatusBar 的 provider 登记栈 + `evaluate` 按 trait 解析登记色判定） | **全部保留其位，不拆不替代**：它决定「模式给的底色是什么」，是增强层的兜底与触发源 |
| 增强层（本轮新建/收口） | 以状态栏带区**实际渲染像素**的平均感知明度精细化判定，专治模式判不了的三面：彩色备忘底（同模式下逐篇不同）、图片滚入带区（同页随滚动变）、开屏渐变（非平色、模式无对应令牌） | 全页面统一采样单点（下 §二），所有承载主采样源一律为此 |

模式切换是增强层的**一级触发源**：trait 变化当场由根观察器驱动重采样（requestRefresh 内先 `BandRenderSampler.refresh` 再戳承载链），开屏/编辑承载的 trait override 同样先重采样再重估。判定度量两层共用：纯核心 CIELAB L* 阈值 61.65（二轮换代，本轮不动——备忘八色深形态改判结论不变）。

## 二、机制设计（单点收口）

### 统一渲染采样器（新文件 MomentStatusBarRender.swift：BandRenderSampler）

- **采样本体**：对当前承载窗口的状态栏带区做实渲染快照——`drawHierarchy` 把 window 全幅绘进「窗宽 × 顶部安全区高」画布（画布外裁切、只剩带区条带，与屏幕合成逐像素一致，含当前页内容/滚动覆盖/一切图层，免手工坐标与 EXIF 方向换算），缩绘 16×4 逐像素算 L* 平均。同批像素算 FNV-1a 指纹：指纹不变即像素未变，不重算、不戳送达。
- **查询面**：承载被 UIKit 查询时经 `MomentStatusBar.renderedStyle` 问采样器——缓存新鲜（<90ms）直接用，过期当场实渲染一次。任一次判定要么来自实际渲染像素，要么是明确的不可得回落，不存在陈旧值冒充实况。
- **送达联动**：采样器记已送达判定（生效层每次以渲染判定应答后回记 `markDelivered`）；新采样把已送达判定推翻时，采样器直接戳 `window.rootViewController.setNeedsStatusBarAppearanceUpdate()` 触发承载链重估。在途查询自会读到新值，未送达过的判定不戳。
- **Diag 可辨识**：渲染路记 `STATUSBAR bg=render lst=<L*> cov=<覆盖率或 -> style=… src=<页>`；静态兜底路沿用 `bg=#RRGGBB …`。同判定去重不刷行、翻转必记一行。

### 根承载（同文件：StatusBarRootContainerController + 安装器 + 挂载探针）

首页/设置族/救援此前无应用自有承载，字色由平台根 UIHostingController 以 `.default`（trait 映射）内部求值——决定面不在应用单点内。本轮把 SwiftUI 根承载整体接入一个应用自有容器控制器并置为 window 根：容器不 override `childViewControllerForStatusBarStyle`（默认 nil，决定止于容器），其 `preferredStatusBarStyle` 走 renderedStyle（src=root）。编辑/图片承载在包含链内层、开屏以 captures 呈现，各自 override 同问采样器——全应用无第二决定面。
安装由根 background 的零尺寸探针（StatusBarRootMount，排在开屏呈现器之前）驱动：入窗/update 节拍尝试安装（根仍是平台 HostingController 且未被呈现占用才装，全程同步、无中间帧）；被开屏呈现占用时跳过，由开屏卸载完成节拍（呈现器 dismiss completion）与 trait 节拍（requestRefresh）重试。根形态异常（非平台承载）只留痕一次、不强装。容器只决定状态栏字色：不碰方向、不碰布局（子承载视图满铺 + autoresizing 跟随，几何逐值不变）。

### 二轮两条特路收口

- **图片页**：`ImageBandSampler` 类删除、文件 MomentStatusBarImage.swift 删除（构建名单改名为 MomentStatusBarRender.swift、.o 改名 statusbar_render.o，计数不变）。其几何覆盖率计算（纯核心 coverage）与 90ms 节流/收尾实算并入统一采样器：ZoomableImageView 的 Coordinator 改喂 `noteImageScroll/noteImageScrollEnd`，覆盖率降为 Diag 附加字段（cov）。二轮「覆盖率 ≤0.001 不出值」的采样门退役——渲染带区在未覆盖时本就是根背景合成，采样值与静态判定同值，零扰动性质由「同像素同判定」结构性保持。
- **开屏**：SplashHostingController 改问 renderedStyle（src=splash），实渲染其开屏视图带区；`bandAverageColor` 公式色（SplashBandColor）降为首帧前/采样不可得的兜底。SB-7 资源对账锁**不降级保留**——兜底错值会在首帧闪错字色，它锁的是「兜底公式与资源原表同式」，与渲染面互不替代（前提已在 SB-7 注释复核改判）。
- `evaluateLightness`（二轮图片特路专用求值）随特路并入退役，全仓零残留（SB-1 锁）。

## 三、逐页面接入表

| 页面 | 承载 | 主采样（增强层） | 兜底（模式层） | 专属触发 |
|---|---|---|---|---|
| 首页 | 根容器（新） | 带区实渲染（src=root） | provider 栈顶/T.bg 静态 | 容器 viewDidAppear、trait |
| 设置族（五页+桥设置+权限+诊断+日志） | 根容器（新） | 同上（同承载同源） | 同上 | 同上（页内切换带区恒为根背景合成，查询时采样即实况） |
| 救援页 | 根容器（新） | 同上 | 同上 | 同上 |
| 编辑页 | EditorHostingController | 带区实渲染（src=editor） | 本篇 memoBg 静态 | 换底订阅（bgColor）重采样、viewDidAppear、trait |
| 图片页 | ImageHostingController | 带区实渲染（src=image） | T.bg 静态 | 滚动/缩放 90ms 节流+收尾实算、viewDidAppear、图更换布局落定 |
| 开屏（独立承载） | SplashHostingController | 带区实渲染（src=splash） | 渐变公式色/垫层平色 | 布局落定（首个有效安全区）、trait |
| 开屏（内联兜底） | 根容器（新） | 带区实渲染（src=root） | T.bg 静态 | 同根页面 |

附带收口：二轮登记的「内联兜底开屏字色采样不可及」缺口，本轮被根容器渲染采样顺带覆盖（内联开屏在根 ZStack 内，其带区像素即根窗口带区像素）。方向锁缺口（内联路径无自有承载、方向不锁）维持原登记不变——那是方向面、非字色面，不在本轮范围。

## 四、触发与节流（完整性论证）

触发面：① 页面出现/切换（各承载 viewDidAppear + 根容器 viewDidAppear + 查询时按需采样）；② 模式/trait 变化（一级触发：根观察器 + 开屏/编辑 trait override，均先重采样）；③ 带区内容可变事件（图片滚动/缩放 90ms 节流 + 收尾实算、编辑换底订阅、开屏布局落定、首页横幅出入——横幅在内容流内且位于页眉下，带区像素变化由其引起的滚动/布局最终都经查询时采样与出现节拍覆盖）；④ 采样翻转自戳（采样器戳根重估）。
纪律：只渲带区小图、禁全屏快照（渲染画布高 = 带区高）、禁逐帧轮询（无定时器；指纹比对作变化检测，只在已触发的采样内顺带完成）、判定不变不戳承载不记 Diag、应用退后台停采样（didEnterBackground 挂起 + 取消尾随，回前台复位新鲜度由触发面接管）。
论证要点：带区内容能变的面只有「全屏滚动覆盖」（图片页，已有 UIKit 滚动钩子）与「整页底色切换」（编辑换底，已有 Combine 订阅）两类事件驱动面；根页面（首页/设置/救援）的滚动视图均在带区下方成框（内容顶 140 = 安全区 59 + 内容框顶距 81），带区恒为根背景与页眉合成，出现/trait/查询三路已完备——此结论与二轮图片页几何附注同口径，真机 Diag 的 src/cov 行可证伪。

## 五、兜底边界

渲染采样不可得的瞬间才回落模式层静态登记：窗口未就绪（承载 view 未入窗）、首帧前（开屏安全区未落定 → 公式色/垫层平色，与首帧实际呈现的垫层一致）、退后台挂起期、带区高为 0（横屏状态栏隐没形态，字色无对象）。采样一到即接管（查询面过期即渲、触发面推送），Diag 以 bg 字段区分两路，真机对读可辨何时在兜底、何时已接管。

## 六、性能量化

单次采样成本：UIGraphicsImageRenderer 画布 = 窗宽 × 带区高（iPhone 逻辑点 393×59，@3x 物理 1179×177 ≈ 0.21MP）的带区限幅 drawHierarchy + 一次 16×4 缩绘 + 64 像素读取与 L* 累加 + 256 字节指纹。频率上界：查询驱动（状态栏查询本身是离散事件）+ 离散触发 + 图片滚动 90ms 节流（≈11 次/秒峰值、仅图片页滚动期间）。无常驻定时器、无后台轮询。量级为毫秒以下/次，不构成滚动帧负担（图片页二轮同路采样已实证同口径）。

## 七、断言改判（verify [53]）

- SB-1：生效层符号 evaluateLightness → renderedStyle；承载 override 恰 3 → 恰 4（+根容器，STATUSR）；加 evaluateLightness 全仓零残留。
- SB-4：加根承载面（挂载点根恰 1、容器类恰 1、安装器三节拍计数）。
- SB-5：文件名/.o 名改名（计数不变）+ 旧名零残留。
- SB-6：整段改判为统一采样接线锁（采样单点/图片喂入收尾作废/全承载 renderedStyle 查询面/旧特路类与旧文件零残留）。
- SB-7：逻辑不变，注释复核前提（公式色降兜底、锁保留理由）。
- SB-2/SB-3/SB-8 不动（SB-3 一度因本批新注释带阈值字面而红，已按锁本意改注释去字面修复，锁本身未动）。

基线定性（任务第 5 条）：本机 verify 改前 585 ✓ / 2 ✗，两红实证为产物面检查——[5] ipa 新鲜度（ipa mtime 早于工作树源码）与产物语言包 md5 对账（读 .app 产物与 Web 源比对），均只读构建产物、不读源码契约；tree 重建后两项归零（587 ✓ / 0 ✗），与「既有产物红 2 条」定性一致（proven）。

## 八、不回归清单

- 开屏方向锁原样保留：SplashHostingController 的 supportedInterfaceOrientations override + idiom 闸未动，SB-8 全绿；plist ~ipad 数组逐字零 diff、开屏画布 isPad 分支零改动；根容器不 override 方向，iPad 方向/开屏形态无感。
- 备忘八色深形态 L* 改判：纯核心零代码改动（仅头注文件指向更新），SB-2 全表锁定全绿。
- 模式层全保留：dyn 令牌、trait 链、provider 登记栈、evaluate 静态路均在位且仍是兜底与证据面（SB-3/SB-4 锁）。
- 组版三组编辑零串扰：动工前 git diff 全量快照比对，改后变更文件恰为本批 6 个目标文件（MomentApp / MomentEditorTransition / MomentStatusBar / MomentStatusBarBridge / MomentSplashHost / build-app2 改名行）+ 新文件 1 + 删文件 1 + verify [53]；PF61 顺延、两处旧注释订正、0.9.63 bump 均复核在位。

## 九、真机终判点（归用户）

1. 各页字色随带区实际渲染变化：Diag 中 STATUSBAR 行 src 覆盖 root/editor/image/splash 且 bg=render 为主路（兜底行只应出现在启动首帧/窗口未就绪瞬间）。
2. 开屏期间：浅主题全程白字（bg=render src=splash），横置启动恒竖屏（方向锁不回归），退出后根页面字色由 src=root 接管无闪错。
3. 图片页滚过带区：字色随覆盖翻转、Diag 带 cov 值（兼判二轮遗留的几何分歧）。
4. 编辑页切备忘底色（深/浅彩底互换）：字色当场跟随、无需退页。
5. 深浅模式往返两遍：各页字色当场扳回（trait 一级触发），Diag 翻转行成对出现。
6. iPad：开屏形态、方向行为与改前一致；首页/设置字色正常。
