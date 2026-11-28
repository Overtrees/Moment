# 背景色采样整套去除（状态栏回系统默认口径）

执行记录，2026-11-28。对象：原生 iOS 状态栏字色的背景色采样家族
（一轮 fix_statusbar_sampling 立、二轮 fix_statusbar_dynamic 换
CIELAB L* 度量、三轮渲染采样已于 0.9.64 全页回退）。

## 一、裁定与范围

用户 2026-11-28 12:12 裁定：把此前加入的背景色采样都去除——含编辑
页、含 8 色；覆盖此前采样口径的全部改判（22:30 采样口径、二轮感知
明度改判、回退后「登记色 + evaluate 单点」的兜底版口径，一并作废）。

保留两件（非采样，不在去除面）：

1. 开屏 iPhone 方向锁（SB-8，用户独立裁定，挂 SplashHosting
   Controller 的 supportedInterfaceOrientations override）。
2. 开屏独立承载本体（SplashHostingController + 呈现器）：呈现节拍
   与方向锁都挂在它身上，去除的只是它的状态栏决定面。

## 二、去除后口径（回源定案）

采样前基线回源（git 29690a1^ + diag_statusbar_dark.md 定案）：原生
侧**零状态栏代码**——无任何 preferredStatusBarStyle override、无
登记、无观察器；plist 的 UIStatusBarStyle=LightContent +
UIViewControllerBasedStatusBarAppearance=false 是 0.9.40 随开屏静
态帧写入的声明面，诊断已定案其从未真正生效（真机生效面一直是平台
承载链）。故去除后不复活该声明钉死，落「系统默认」：

- 应用侧状态栏代码清零：各承载不再 override preferredStatusBar
  Style，平台以 .default 按当前 trait 决定明暗（浅外观深字 / 深外
  观浅字），不读任何页面背景。
- plist 不动：UIViewControllerBasedStatusBarAppearance=true 维持
  （[8] 组锁），UIStatusBarStyle=LightContent 只作开屏首帧。

直接后果（如实登记）：开屏停留期字色同样回平台默认——浅外观下为
深字、落在品牌蓝渐变上，即二轮症状②的形态；这是本次裁定的题中
之义（采样去除后无任何应用面再按开屏内容改判），真机观感归用户
终判。编辑页备忘底色（八色）不再参与字色决定：深外观恒浅字、浅
外观恒深字，与 trait 一致。

## 三、去除清单（文件 / 段 / 断言逐项）

源码（rust/apps/ios/app/）：

- **MomentStatusBar.swift**：整文件删除（StatusBarCore 纯核心：
  L\* 阈值 61.65、relativeLuminance / labLightness / lightness /
  prefersLightContent 判定、SBStop、gradientColor、bandAverage
  Color——八色与全色表的判定度量本体）。
- **MomentStatusBarBridge.swift**：整文件删除（MomentStatusBar 生
  效层：provider 登记栈 registerCurrent / clearCurrent、
  currentBackground、evaluate 采样决策单点、style、request
  Refresh；StatusBarTraitObserver / StatusBarObserverView 送达
  观察器；Diag STATUSBAR 采样行随 evaluate 一并退役）。
- **MomentEditorTransition.swift**：EditorHostingController 与
  ImageHostingController 各摘——statusBarBackground 注入属性、
  preferredStatusBarStyle override、viewWillAppear /
  viewDidDisappear 内的 registerCurrent / clearCurrent（导航栏
  隐与 onRemoved 收口保留）；EditorHostingController 的换底订阅
  statusBarBgObservation 一并摘除。宿主创建点接线同步摘除：
  makeEditorController 的采样源闭包 + $bgColor 订阅、observe
  Image 的 ivc.statusBarBackground 注入。**编辑页登记点在此清
  零**（任务点名的含编辑页）。
- **MomentSplashHost.swift**：SplashBandColor 整 enum 删除（见
  §四定性）；SplashHostingController 摘 preferredStatusBar
  Style override、bandColor()、registerCurrent / clearCurrent
  的 appear/disappear override、安全区落定重估（viewDidLayout
  Subviews 的 didNudgeInsets 节拍——其唯一目的是让公式色以实带
  区高重算）、traitCollectionDidChange 重估 override。呈现器、
  托管根视图、方向锁（SB-8）未动。
- **MomentApp.swift**：
  - 根 .background 块摘 StatusBarTraitObserver() 挂载（开屏呈现
    器 SplashPresenterMount 保留），注释改判。
  - NativeSplashArtwork 的背景渐变数值表整表删除（background
    Stops / backgroundStart / backgroundEnd 及其在 load() /
    degraded() 的构造）——该表唯一消费方就是带区采样；绘制面
    （NativeSplashGradient）不动。本类型可见性复原 private（
    二轮为数值表跨文件公开才去 private，消费方清零后复原）、
    三成员 fileprivate 收回普通 let。
  - T.bgUI / T.memoBgUI 本体保留（memoBgUI 是备忘底色压暗的单
    源实现、memoBg 的 Color 包装在用；bgUI 为其无色回落），仅
    注释摘除「状态栏采样专用」措辞。
- **MomentImageLoad.swift**：文件头注释摘除对 MomentStatusBar 的
  先例引用（符号零残留口径）。

构建（build-app2.sh）：

- 两采样文件从全部 29 遍输入名单摘除（30 遍 × 2 行实删 60 行，
  含两文件自有 primary 遍的输入行）；statusbar.o /
  statusbar_bridge.o 两 primary 遍整遍删除；链接行摘两 .o。
- 全文件遍数由 31 → 29（FontFactory 例外 30 → 28，其一遍名单
  本不含它）。bash -n 语法通过。
- tree-sync/push_small.py 名单同步删两文件一行（仓外文件，不入
  提交；tree 克隆内残留副本须于下次组版 overlay 时显式删除，
  沿回退批先例登记）。

verify（verify_ios.sh）：

- 头部变量 STATUS / STATUSB 定义删除（全脚本仅 [53] 消费，已
  核）；SPLASH 注释改判。
- [53] 组改判：SB-1…SB-7 采样断言整组删除（决策单点锁、L\* 全
  色表宿主单测、阈值单源锁、送达链锁、构建接线锁、回退接线锁、
  SB-7 开屏带区色资源对账——python 独立复算 + 核心函数复现，
  随公式色退役整条作废）；新增两条：
  - SB-1（改判）采样家族零残留锁：两文件不存在 + 符号集（见
    §五）在全部 .swift 与 build-app2.sh 零命中 + preferred
    StatusBarStyle 全仓零命中（口径回平台默认的机制锁）。
  - SB-2（改判）开屏承载构建接线：SplashHost 29 遍 +
    splash_host.o ×2、两代采样器文件名延续零残留。
  - **SB-8 原样保留**（编号、锁体、文案未动）。
- 跨组遍数锁同步改判（各 −2，均注沿革）：B16-23 的 Moment
  BridgeRestore 31→29；DT46-6 的 MomentFontFactory 30→28；
  E47-8 的 MomentUndo 31→29；X50-7 的 MomentXSel /
  MomentXSelBridge 31→29。IMG55-7 为相对等值锁（ImageLoad 与
  XSel 同步 −2），无需改。

## 四、bandAverageColor 定性（任务点名单项）

定性：**属采样家族，归去除面**。依据：它虽是纯函数，但其唯一存
在目的是「由开屏渐变内容派生状态栏带区的决策色」——输入是内容
（artwork 渐变表）、输出只供 SplashBandColor → evaluate 一条决
策链消费，全仓无第二个消费方（绘制面走 NativeSplashGradient，
不经它）。按用户「背景色采样都去除」的 plain reading，凡「按内
容算状态栏色」的面都在去除面内，本函数正是该面的计算本体。

改判后的开屏带颜色来源：**不存在应用侧颜色来源**——开屏期状态
栏字色由平台 .default 按 trait 决定；开屏画面本身的渐变绘制
（NativeSplashCanvas + NativeSplashGradient）与垫层色不变，本
批未动任何呈现像素。

## 五、零残留普查（本机工作树，代码面）

对全部 .swift 逐符号 grep（命中文件集均为空集）：

StatusBarCore / MomentStatusBar / registerCurrent / clearCurrent
/ prefersLightContent / lightnessThreshold / bandAverageColor /
SplashBandColor / StatusBarTraitObserver / preferredStatusBarStyle
/ evaluateLightness / BandRenderSampler / renderedStyle /
'STATUSBAR bg=' / '61.65' / '0.1791' / backgroundStops

build-app2.sh：'MomentStatusBar' 0 命中、'statusbar.o' 0、
'statusbar_bridge.o' 0（余 2 处 'statusbar' 为注释中的报告名引
用 fix_statusbar_dynamic / remove_statusbar_sampling，非文件
登记）。

## 六、0.9.63 待验项销账

release_0.9.63.md §四与回退报告 §八中「八色深形态改判白字目检」
（深色主题下浅彩底备忘字色由黑改白、请用户目检可读性）——该终
判点的前提（L\* 改判机制）已随本批整体删除，**终判点作废销
账**，不再请用户验。后续口径：八色页状态栏字色只随 trait（深
外观浅字 / 浅外观深字），若用户在真机上对某形态有新意见，属新
裁定另行立项，不在本批回潮采样。

## 七、验证结果

- 本机 verify_ios.sh 全量：692 ✓ / 5 ✗。5 红归属：ipa 陈旧 +
  产物语言包 2 红为既有产物陈旧对（tree 重建归零口径，非源码
  红）；F30-2 / HM65-5 / HR69-3 3 红为并行线（drag quote 面 /
  home.row 注册面）在途改动的取段（ListView / BlockRow 段 +
  home 线自带 [69] 新组断言），与本批改动段（状态栏 / 开屏 /
  artwork / 令牌注释）零交集，非本批引入。[53] 组 SB-1 /
  SB-2 / SB-8 三项全 ✓。
- cargo test --workspace：20 套件全过、零失败。
- 组数对账：[53] 由 8 条（SB-1…SB-8）收为 3 条（SB-1 改判 /
  SB-2 改判 / SB-8 保留），净 −5；跨组遍数锁 4 处改判不增减条
  目；[69] 为并行 home 线新增组（非本批）。
- **Swift 编译门未过**：本机无 swiftc，MomentApp / TRANS /
  SPLASH 的删除后编译正确性（尤其 NativeSplashArtwork 可见性
  复原、SplashHostingController 摘 override 后的类完整性）以
  tree smoke_ios.sh 为首次编译门，留下版组版；本报告不表述为
  已编译验证。

## 八、提交与协作注记

本批与 drag quote 面、home.row 注册面、Diag 扩容三线并行同仓作
业：MomentApp.swift 与 verify_ios.sh 为共享文件，提交按 hunk 级
分拣（临时索引 + 内容过滤 + 提交后核树），只入本批 hunk；并行
线在途改动（含其作业期间新落的 [69] 组与 fix_drag_pickup_quote_
face.md）原样留在工作树未动。本批不推送、不出包，留主线组下版。
