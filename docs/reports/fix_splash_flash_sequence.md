# 开屏闪现根治（fix_splash_flash_sequence）

用户 2026-11-28 13:16 真机实报（0.9.65）：开屏期间闪过 10–20ms 首页
空态、最后闪黑一下才进入首页。此问题此前三轮被归因「根承载换根」并
在 0.9.64 全页回退，症状仍在——本批不沿用旧结论，自帧序列回源重定案，
结论：病灶是二轮留下的**呈现式承载结构本身**，按红线重构为单承载、
单退场、无根切换。用户同日 13:22 硬约束：根治不动开屏整体节奏
（总时长/呈现退场节拍/淡入淡出时长不变），本批节拍常数逐项未动，
并以 SB-10 断言锁定（见 §五）。

## 一、帧序列（旧结构，逐帧重建）

| # | 帧内容 | 决定者 | 证据 |
|---|--------|--------|------|
| 1 | 系统 LaunchScreen 纯色（浅 35,121,220 / 深 31,31,33） | Info.plist `UILaunchScreen` 的 `UIColorName=LaunchBackground` | proven（plist 与色值定义在仓） |
| 2 | 根 SwiftUI 首帧：页眉 + **首页空态** + T.bg 底 | 根 ListView 自首帧渲染；空态条件 `visibleMemos.isEmpty` 无就绪门（旧主文件两处） | proven（代码路径）；该帧即症状 A 的载体 |
| 3 | 开屏 VC 全屏呈现覆盖（品牌画布） | SplashPresenter 于根入窗后 `root.present(animated: false)` | proven（呈现调用点）；呈现只能在根入窗后的下一事务生效 |
| 4 | 开屏时间线 2.5s（静止 0.5 + progress 1.0 + 再等 1.0） | SplashState 时间线（定时 + 动画） | proven（常数见 §五对账表） |
| 5 | 退出：VC 视图 260ms alpha 淡出，底下是**窗口本身（黑）** | 呈现器订阅 gone 后对 VC 视图淡出；`.fullScreen` 呈现完成后根视图已被移出窗口；全仓从未设 `window.backgroundColor`（默认黑） | 机制 proven（grep 零命中 + 呈现语义）；逐帧分布 inferred |
| 6 | `dismiss(animated: false)` 硬切回首页 | 呈现器淡出完成回调 | proven |

数据就绪时点：冷启开库+首载为百 ms 级（load 含 0.05s 人为延迟），
被 2.5s 节拍完全吸收——就绪等待在旧结构中实际占 0。

## 二、两症状定案

- **症状 A（空态闪 10–20ms）= 入口接缝**。根视图先行入窗渲染、开屏
  呈现晚 1–2 个事务：间隙帧里窗口上是根首帧，而根首帧因空态无就绪
  门必是空态。60/120Hz 下 1–2 帧 ≈ 8–33ms，与实报量级吻合。代码
  路径 proven；帧数 inferred（静态不可证帧数，待装机相位打点回读）。
  又因系统开屏与应用开屏同底色，这 1–2 帧夹在两段同色开屏之间，
  内容突变格外显眼。
- **症状 B（结束闪黑）= 出口接缝**。`.fullScreen` 呈现的退场淡出不是
  向首页淡出，而是向从未设色的黑窗口淡出，末尾再硬切。机制 proven。
  已排除：开屏自身深色底（开屏全程在位、非末尾事件）、LaunchScreen
  色（位于序列起点、非终点）。

## 三、旧归因证伪点

0.9.64 回退报告（fix_statusbar_rollback_all §四）把两症状归给三轮的
根承载换根/根承载推迟安装；其自身亦记录「根 SwiftUI 首帧 = 数据未
就绪的空态」「闪黑与窗口底为黑相关」。换根机制已在 0.9.64 拆除、
0.9.65 症状仍在——真病灶是二轮呈现式承载的三层结构（系统开屏 /
根 SwiftUI / 呈现 VC）与「呈现与退场分家、呈现期根被移出窗口」两点，
不在换根。故本批走重构支路而非时序补丁。

## 四、方案：单承载重构（MomentSplashHost.swift 整文件重写）

- **单承载**：开屏改为根 ZStack 内一层（`SplashLaunchLayer`），随根
  首帧同帧在位——入口接缝结构性消失（不存在「根已入窗而开屏未至」
  的帧）。挂载条件与旧呈现器同口径：正常模式 && 资源就绪；安全模式
  不挂（不盖救援页）。
- **单退场**：退出 = 状态置 gone 后 SwiftUI opacity 淡出（easeOut
  0.26s，减弱动态效果时 0），淡出对象是根内图层、其下恒为首页本体；
  淡出结束置 exited 后整体不渲染。无 dismiss、无硬切。
- **窗口底色单点**：`LaunchChromeProbe`（根 background、零尺寸）入窗
  即把 `window.backgroundColor` 设为开屏同源色（单源
  `SplashOverlayView.uiColor`，与画布底同一动态色对），exited 后换为
  根页底色 T.bgUI——即便任何间隙帧露出窗口，露出的也是开屏色/页底
  色，黑色在序列内无来源。
- **空态就绪门**：ListView 两处空态（窄屏 emptyRow / 宽屏 gridEmpty）
  呈现条件加 `&& library.didLoad`：加载中只呈页眉与底色，真空库在
  didLoad 后照常呈空态（行为等价，真空态不被吞）。
- **方向锁 SB-8 决定面迁移**：承载 override 随呈现退役；方向掩码改
  由应用委托 `application(_:supportedInterfaceOrientationsFor:)`
  经 `LaunchOrientationGate`（splashActive 初值 true、iPhone 时
  .portrait、其余三向）决定，铬面探针在 exited 时清门并触发
  `setNeedsUpdateOfSupportedInterfaceOrientations` 重估。行为口径与
  旧承载 override 等价（呈现期锁竖、退出后放行），且消除了旧形态
  「呈现 VC 的朝向回调在呈现完成前不被查询」的时序依赖。
- **相位打点**：Diag 新增 `SPLASH phase show/data/timeline/exit/end`
  五行（Clock.ms() 时刻；exit 行附 data/timeline 两戳），装机后可经
  桥回读相位间隔，验证闪现窗口是否归零。

### 职责保全对账（开屏承载旧职责逐项）

| 旧职责 | 新形态 |
|--------|--------|
| 品牌时间线与画布本体（NativeMomentSplash） | 原样迁入 SplashOverlayView，未动一笔 |
| 方向锁 SB-8 | 决定面迁委托掩码门（见上），SB-8 断言改判 |
| 安全模式不挂开屏（不盖救援页） | 挂载条件同旧（`!bootIsSafe && resourcesReady`） |
| 资源缺失不挂 | 同上（resourcesReady 静态迁入新文件） |
| 「呈现失败回落内联兜底」 | 呈现通道退役后该失败模式结构性不存在，职责随之消解 |
| WatchdogBar / ErrBadge 压开屏 | 靠根 ZStack 层序保持（开屏层在浮条之下、徽章在开屏层之下，与旧内联兜底的层序关系一致） |
| 退出门（didLoad && timelineComplete） | 单点保留于 beginExitIfReady，gone 全仓恰一写（SB-9 锁） |

## 五、节奏对账（用户 13:22 硬约束）

| 相位 | 旧构成 | 来源性质 | 新构成 |
|------|--------|----------|--------|
| 静止 | 500ms（`Task.sleep 500_000_000`） | 定时 | 同值未动 |
| progress | 线性 1.0s（`.linear(duration: 1.0)`） | 动画 | 同值未动 |
| 再等 | 1.0s（`Task.sleep 1_000_000_000`）后置 timelineComplete | 定时 | 同值未动 |
| 就绪等待 | 0（被节拍吸收） | — | 0（同上） |
| 退场淡出 | easeOut 260ms（呈现器对 VC 视图）；减弱动态时 timelineComplete 立即置位、淡出 0 | 动画 | easeOut 0.26s（根内图层 opacity）；减弱动态同口径 0 |

唯一时序位移：时间线起锚由「呈现完成」提前到「根首帧」，差 ≤1–2 帧，
即被消除的闪现窗口本身；总时长与各节拍常数逐项不变。SB-10 锁四常数
在位且退出门段内无第三条件、无 sleep/asyncAfter。

**备选待裁（未采纳）**：曾考虑给退出门加第三条件「首屏内容就绪」
（homeContentReady）。退出时点上首页内容早已就绪数秒，无结构性冲突，
加条件只新增「信号不达则永不退出」的失败模式，故未加、仅登记备选；
若日后出现慢盘机型使数据就绪晚于 2.5s 节拍，届时再议，其代价即
「最坏情况开屏延长至就绪时点」与节奏硬约束的直接冲突，须用户裁。

## 六、断言（verify_ios.sh）

- **SB-8 改判**：委托掩码门口径（委托方法恰 1、supportedInterface
  Orientations 系符号仅开屏文件持有、旧 override 全仓 0、委托适配
  器在 App 挂载、idiom 闸与重估入口在位；iPad 守卫三件沿旧）。
- **SB-9 新增（序列不变量）**：退出门段同含 didLoad + timeline
  Complete + gone 置位；`gone = true` 代码行全仓恰 1 写；`&&
  library.didLoad` 恰 2；旧无门空态形态 0；退役符号集（Splash
  Presenter / SplashHostingController / SplashHostedRootView /
  SplashGate / InlineSplashHost /
  modalPresentationCapturesStatusBarAppearance / `SPLASH present
  vc`）代码行零残留；`window.backgroundColor` 仅开屏文件且恰 2 写；
  相位打点五串在位。
- **SB-10 新增（节奏锁）**：见 §五。
- **DM45-1 改判**：开屏画布迁出主文件后裸色普查改双文件口径（主
  文件 Color(red: 6 / UIColor(red: 3 / 35 恒 1 / 31 恒 1；开屏文件
  单源对 Color(red: 2 / UIColor(red: 2 / 35 恒 1 / 31 恒 2），改判
  沿革注已写入断言头注。
- 三处 awk 段锚（IMGPG/IPVSEG/PFSEG_IMG）尾锚随状态机迁出由
  SplashHostView/SplashState 改为 `@main`。

## 七、验证分账

- 本笔以独立 worktree 在 HEAD `dc1d543`（标题占位居中修复，父
  0db9a56）上重建三文件 + 本报告成笔，不经共享索引（主线 13:29
  警告：共享索引多方涂改、不可直接成笔）。
- worktree 树内 verify：**源码面全绿**（SB-8/SB-9/SB-10/DM45-1 及
  T-1/SVG42-3 等全过）；仅 5 红为 worktree 无构建产物的缺失类
  （ipa 不存在 / Assets.car / 两份 splash vector json / 产物语言
  包），属「未构建」而非源码红。
- 主工作区联合树复跑曾见 T-1/SVG42-3 红：定案为标题线在途未提交
  hunk 把三处 `Lang.t("imgpage.untitled")` 与五处 `editor.
  imageTarget =` 临时改成跨行形态所致（HEAD 与本笔树内计数均
  3/5 正常），与本笔无关，不为过检弱化断言。
- cargo test --workspace：239 过、0 败（本批未动 Rust，例行门；
  在主仓热缓存跑——worktree 冷构建曾因 /tmp tmpfs 512M 满盘中断，
  环境故障非代码问题）。
- Swift 编译门未在本机跑：按分工留 tree 组版冒烟（smoke_ios.sh
  全量）。

## 八、留账

1. tree 组版：本笔入版后跑 smoke_ios.sh 全量，verify 产物面红随
   构建归零。
2. 装机后桥回读 Diag `SPLASH phase` 五行：show→data / data→
   timeline / exit 时两戳差，核相位间隔与「间隙帧无空态、无黑帧」
   的结构预期。
3. 用户目检终判：冷启全程「开屏 → 首页」三无（无空态闪、无黑闪、
   无节奏变化感）。
4. 主工作区内本批三文件的在途副本（含标题线未提交 hunk 的联合
   态）已被本笔取代，勿自共享工作区直接成笔本批内容。
