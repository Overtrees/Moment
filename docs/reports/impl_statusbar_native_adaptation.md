# 状态栏字体颜色适应——纯原生方案根治（impl_statusbar_native_adaptation）

日期：2026-11-28。分支 `fix/statusbar-native-adaptation`（父 = e65e396，独立 worktree 落码，待主线合并；与偿还批二的主工作区改动零文件冲突面见 §留账 4）。

背景：旧背景色采样整套已于 71b6354 删除、状态栏回到系统默认。用户 2026-11-28 改判重开，定纯原生三条架构（下 §方案落点逐条对位），本批按此落码，不偏离架构。

## §普查 可达顶层的面 × 类别 × 回答者

回答者全应用唯一：根容器 `StatusBarRootContainer.ContainerViewController`（MomentStatusBarRoot.swift），是 WindowGroup 根视图经 UIViewControllerRepresentable 在首帧即位的框架根承载子控制器，内嵌 UIHostingController 持原根 SwiftUI 视图；其 `preferredStatusBarStyle` 回问判定引擎 `StatusBarEngine`（MomentStatusBarEngine.swift），`childForStatusBarStyle` 恒 nil。各面只登记输入、不各自作答。

| 面 | 类别 | 输入（判定来源） | 登记点 |
|---|---|---|---|
| 首页（列表/搜索） | 数据自答 | 根令牌色 T.bg（dyn 0xF2F2F7 / 0x000000，背景层级模型单源）resolved 后算相对明度 | 引擎内建 provider（底层 .root） |
| 设置族五页 / 桥设置 / 权限 / 诊断 / 日志视窗 | 数据自答 | 同上（全族同源根令牌色底） | 同上（同一底层 .root，无独立面） |
| 救援页（安全模式） | 数据自答 | 同上 | 引擎内建 provider（底层 .rescue） |
| 开屏层 | 数据自答 | 渐变停点即数据：带中心点经 max 填充变换映射回 1179×2556 画布、投影到渐变轴、停点分量插值（`SplashBandData.centerColor`，与 NativeSplashCanvas 同变换同源）；不可算回落垫层平色 SplashOverlayView.uiColor | 引擎内建 provider（底层 .splash） |
| 编辑页 | 数据自答 | 备忘底色 T.memoBgUI(editor.bgColor) resolved；底色变化经 $bgColor 订阅触发重估 | EditorHostingController viewWillAppear 登记闭包、真正离栈时注销（MomentEditorTransition.swift） |
| 图片页 | 像素保底 | 带中心单点：window 坐标映射进图视图，图覆盖该点才经 CGImage 1×1 裁剪采样；未覆盖/不可采样回落根令牌色（带区实景即页背景：图面可用区顶让 126、带区恒为 ChromeView 的 T.bg，此为构造口径） | ImageHostingController 登记面；ZoomableImageView 注册/注销像素源（MomentApp.swift） |
| 系统呈现面（选图器/分享面板/内嵌 AVPlayerViewController） | 范围外 | 平台自管呈现，不在本应用回答链内 | — |

底层（splash/root/rescue）由根 SwiftUI 报告点对齐：MomentApp.refreshStatusBarBase（onAppear + 开屏退出 onChange + bootIsSafe onChange），与根 ZStack 分流/开屏挂载条件同口径；承载面（editor/image）在底层之上成栈、离栈回落底层判定。

## §方案落点 用户三条逐条

1. **主判定交给数据**：六类面中五类由已知色值（令牌色/备忘底色/渐变停点）直接算相对明度，无采样、无延迟。内容切换/滚动后经触发点调引擎 evaluate → 落定后由引擎单点调 `setNeedsStatusBarAppearanceUpdate` 触发系统重问容器。触发点：scrollViewDidScroll / scrollViewDidEndDragging / scrollViewDidEndDecelerating / scrollViewDidZoom（图片页图面）、viewDidLayoutSubviews（根容器，布局落定）、traitCollectionDidChange（根容器）、承载进出与底色订阅（编辑页）、根报告点（底层切换）。滚动高频回调只入去抖通道、不直接翻转；拖动/减速落定与图就绪必实算一次（终态不停在中间态）。
2. **像素只做保底**：独立文件 MomentStatusBarPixel.swift，三采样器按介质分工——图片 CGImage `cropping(to:)` 1×1（EXIF 八向映射回原始像素面、预乘回读、动图取首帧）、图层 `CALayer.render(in:)` 离屏 1×1 读目标点、视频 `AVPlayerItemVideoOutput.copyPixelBuffer` 取当前帧中心（32BGRA）。采样点恒为状态栏带中心单点。**严禁整屏截图**：三状态栏文件代码内 drawHierarchy / snapshotView / UIGraphicsImageRenderer / UIGraphicsBeginImageContext 零命中、像素文件无 UIWindow 引用（SB-12 锁）。消费面恰为图片页一面：layerPoint / videoCenter 两采样器已备、当前无消费方（应用内无覆盖状态栏带的自绘图层/内嵌视频面；内嵌播放器为系统呈现面、范围外），登记为待消费能力，不扩散回数据面。
3. **回答者唯一**：容器统一答 + `childForStatusBarStyle` 恒 nil，全仓一致、不混答（SB-11 锁：override 代码恰一处且在根容器、child 代码恰一处、重问请求代码恰一处且在引擎）。UIApplication 旧 setter 全仓不用（iOS 27 空操作）。编辑/图片承载原 override 随旧制已删，本批只加登记、不复活 override。

判定与手感：相对明度（sRGB 线性化加权）> 阈值判 .darkContent、余 .lightContent。状态机：首判直落（启动期无既存值可抖）→ 候选去抖 48ms → 最短驻留 120ms 门（不足顺延）→ 落定前复算确认候选未被推翻 → 淡变 160ms 落定。每次翻转记 Diag 一行：`STATUSBAR flip surface=<面> src=data|pixel lum=<三位小数> style=light|dark`；容器首次受问另记 `STATUSBAR answerer live style=...` 一行（转发链活证，见 §留账 1）。

## §参数单源

`StatusBarParams`（MomentStatusBarEngine.swift，全仓仅此一份，SB-13 锁）：luminanceThreshold = 0.45、debounce = 0.048、minDwell = 0.120、fade = 0.160（用户 2026-11-28 给定，沿用网页层口径；Web 侧无状态栏实现、四值以用户给定为准）。阈值名 luminanceThreshold 与相对明度函数 func luminance( 均全仓单点。

## §断言与负对照（verify_ios.sh [53] 组）

- SB-1 改判：旧采样符号集（StatusBarCore / bandAverageColor / 61.65 / registerCurrent / clearCurrent / StatusBarTraitObserver / SplashBandColor / STATUSBAR bg= / 0.1791 / evaluateLightness / BandRenderSampler / renderedStyle / lightnessThreshold 等）持续全仓零命中 + 旧两文件持续不存在；'MomentStatusBar' 名与 preferredStatusBarStyle 不再禁（新架构自有形态，归 SB-11 锁唯一性）。
- SB-2 改判：构建接线——开屏承载与状态栏三文件各 33 遍、四 .o 各 ×2、两代采样器文件名零残留。
- SB-11 回答者唯一（去注释口径计数）：override 恰一@根容器、childForStatusBarStyle 恰一、setNeedsStatusBarAppearanceUpdate 恰一@引擎、两承载 begin/end 登记在位。
- SB-12 采样禁区（作用域 = 状态栏三文件代码）：截图 API 四名零命中、像素文件无 UIWindow；三采样器形态在位。作用域说明：桥自测台 MomentBridgeUITest 的夹具渲染是另一面、不属状态栏采样路径，不在本锁内。
- SB-13 参数单源：四常数引擎各恰一定义、阈值名仅引擎文件出现、明度函数全仓恰一。
- SB-14 触发接线：图面段注册/滚动/清源、根包装与底层报告、SplashBandData 定义与引擎消费在位。
- 计数锁联动改判（+3 遍沿革注）：B16-23（30→33）、DT46-6（29→32）、E47-8（30→33）、X50-7（各 30→33）、PD71-4（30→33）；IMG55-7 为相对锁（ImageLoad == XSel，同增自动成立）；-ge 型下限锁不受影响。
- 负对照（实做并登记）：NC-1 临时给 MomentTreeWait.swift 加第二个 preferredStatusBarStyle override → SB-11 恰红（ovr=2）、SB-12 不误伤，验毕还原；NC-2 临时给 MomentStatusBarPixel.swift 加 drawHierarchy 调用 → SB-12 恰红（shot=1）、SB-11/13/14 不误伤，验毕还原且文件逐字节复原。
- 本机 verify 全量分账：712 ✓；红 5 项全为产物陈旧（ipa 不存在 / Assets.car 缺 / 开屏双 JSON 缺 / 语言包缺——worktree 无构建产物，tree 构建后自解），与本批无关。

## §与开屏重构的衔接

开屏单承载序列（fix_splash_flash_sequence）结构零改动：根 ZStack 分流、开屏层挂载/退出门、SplashHostingController 与窗口底色单点（SB-9）、节奏构成（SB-10）、方向锁委托掩码口径（SB-8）逐项未动、断言全绿。状态栏归属理顺为：开屏在位期间底层 = .splash（渐变数据自答），退出完成经报告点切回 .root；开屏承载不再是状态栏回答者（其 override 早随旧制退役），回答权收归根容器一处。首帧口径不变：plist VC-based + LightContent 只作开屏首帧（[8] 组锁），容器首问前引擎经 attach 已有正确底层与首判。

## §构建接线

build-app2.sh：三新文件按 MomentTreeWait 先例全遍登记——原 30 遍每遍次级输入各 +1 份、新增 3 个 primary 遍（statusbar_engine.o / statusbar_root.o / statusbar_pixel.o）、主链接行加 3 个 .o；纯插入 197 行、零删除，bash -n 通过。实测计数：全文件 33 遍（FontFactory 32——svg_raster 遍自始未含它）、三 .o 各 ×2。tree-sync/push_small.py 名单已加三文件（仓外，不入本提交）。

## §留账

1. **转发链真机终判（第一验点）**：容器为框架根承载的直接子控制器、同编辑/图片承载 0.9.5x 多轮真机生效的转发链受问——此为 inferred（构造与先例同构），proven 待装机：桥回读 Diag 有 `STATUSBAR answerer live` 行即链活；若缺失则链断、改走每页自答的回退评估（不在本批预埋第二机制）。
2. **Swift 编译门未过**：本机无 swiftc（工具链在 tree），swiftc -parse 与全量编译均留 tree 组版冒烟（smoke_ios.sh）把关；本机已尽静态核对（符号存在性逐个回源：SplashOverlayView.uiColor / resourcesReady、NativeSplashArtwork.light|dark.background、T.bgUI / T.memoBgUI、EditorView.editor.$bgColor 均在位）。
3. **真机终判点**：深/浅外观下各页（首页/设置族/编辑页各底色/救援页）明暗正确；图片页深色照片与浅色照片各一、带中心被图覆盖与未覆盖（小图）两形态；图片页滚动/缩放跨区翻转不抖（去抖+驻留实证）；开屏深/浅两形态字色正确且退出后回落首页判定；翻转 Diag 行（面/来源/明度）与目检一致。
4. **合并时计数重算**：偿还批二在主工作区并行给 build-app2.sh 加 MomentBlockKind（+1 遍）。本批计数锁以父 e65e396 的 33/32 为口径；两批合并后全文件遍数再 +1（通例 34、FontFactory 33），主线合并时须按合并后实测同步 SB-2 与五处联动计数锁（B16-23 / DT46-6 / E47-8 / X50-7 / PD71-4），算术即本批同式 +1。
5. layerPoint / videoCenter 两采样器当前无消费方（见 §方案落点 2），属用户方案点名的保底能力备置；后续若出现覆盖带区的自绘图层/内嵌视频面，经引擎保底面单点接入，不另起判定路径。
