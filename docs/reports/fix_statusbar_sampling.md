# 状态栏字色根治第二阶段：全局背景色采样落码

2026-11-27 晚。第一阶段诊断见 diag_statusbar_dark.md；
本阶段按用户 22:30 改判的设计口径落码（不做恒白/
恒黑、也不做按外观 trait 的固定映射——让**全局背
景色采样**真正生效：采样状态栏后方当前生效的背景
色、按亮度决定字色、全局各页一致；定位为增强机
制）。本批未提交、未组 ipa，留主线随 0.9.62 组版；
tree 全量冒烟 ALL GREEN（verify 539 ✓，含新 [53]
SB-1..SB-5）。**构建与断言全绿只证明决定链、采样
映射与送达接线成立；往返当场回位以真机终判为准
（见 §六），不表述为已修复。**

## 一、机制总形

- **采样单点**：`MomentStatusBar.swift`（纯核心，
  Foundation-only）`StatusBarCore`——UIColor 按
  当前 trait 解析为具体 RGB（`resolvedColor`）→
  WCAG 相对亮度 → 纯函数判定白字/黑字。无状态、
  无缓存：判定只依赖入参（背景色 + trait），同一
  入参恒同出参，结构上不存在闩锁。
- **生效层**：`MomentStatusBarBridge.swift`
  `MomentStatusBar.evaluate(source:background:trait:)`
  ——全应用唯一的「背景→状态栏样式」决策点；每次
  判定变化写 Diag `STATUSBAR bg=#RRGGBB lum=…
  style=light|dark src=…`（去重键只防刷屏，不参
  与决策）。页面背景登记栈（registerCurrent/
  clearCurrent）只决定平台面在编辑页呈现期间的
  采样源，判定仍走同一点。
- **承载面收口**：build-app2.sh plist 翻
  `UIViewControllerBasedStatusBarAppearance=
  true`（`UIStatusBarStyle=LightContent` 保留，只
  管开屏首帧）。应用自有的两个承载控制器
  （Editor/ImageHostingController）override
  `preferredStatusBarStyle` 一律调决策点现算；
  SwiftUI 平台承载面（首页/设置族/救援）由平台
  在 VC 化后按其内部求值决定——其背景恒为 T.bg，
  两形态与采样判定逐值一致（见 §二），全局结果
  一致。
- **送达链**（针对「值源正确、坏在送达」的用户
  实证——故障态挂后台重进即自愈）：根 ZStack 挂
  零命中 trait 观察器，外观变化当场对根控制器
  `setNeedsStatusBarAppearanceUpdate` 并补一行
  采样 Diag；编辑页换底（bgColor 变化）经订阅当
  场对自身重估。送达不依赖 viewWillAppear 等生
  命周期偶遇。

## 二、采样源逐页清单

| 页面 | 承载 | 状态栏带区后方生效色 | 采样/决定 |
|---|---|---|---|
| 首页（列表/网格） | SwiftUI 平台承载 | `T.bg`（ListView 全页 `.background(T.bg)`，MomentApp.swift:18765） | 平台求值；根观察器强制送达 |
| 设置族/诊断/语言/天气等子页 | SwiftUI 平台承载 | `T.bg`（ChromeView `.background(T.bg)`，20141） | 同上 |
| 救援页 | 根 ZStack 直挂 | `T.bg`（RescueView `.background(T.bg)`，MomentRescue.swift:246） | 同上；观察器在根、安全模式下同样在位 |
| 编辑页 | EditorHostingController（自有） | `T.memoBg(bgColor)`：无底色 = T.bg；选色浅形态原色、深形态 ×0.55 压暗（13239 全页底） | 注入闭包查询时现读 `T.memoBgUI(editor.bgColor)`，override 调 evaluate(src=editor)；换底订阅当场重估 |
| 图片页 | ImageHostingController（自有） | `T.bg`（ChromeView 全页底；图片本体在页头下方可用区 contain 呈现，不达状态栏带区） | 注入 `{ T.bgUI }`，override 调 evaluate(src=image)；**采样口径 = 页面根背景，不是图片像素**——图片页按此口径点名，不静默 |
| 开屏（瞬态浮层） | 根内 SwiftUI 层 | splashColor：浅 (35,121,220) / 深 #1F1F21 | 无独立承载，由根承载链治理；浅蓝 L=0.1894（阈值上方、黑/白对比 4.79/4.39 近等）列为真机观察点（§六-5） |
| 系统呈现面（选图器/分享等） | 系统 VC | 系统决定 | 范围外（系统 UI 瞬态） |

背景单源化配套：`T.memoBg` 的 ×0.55 深色压暗原
在 SwiftUI Color 层实现、采样层无法复算——本批
把压暗逻辑下沉为 UIColor 本体 `T.memoBgUI`，
`memoBg` 改为其 Color 包装，呈现与采样同值同
源（MEMORY 背景层级模型：根页面颜色是唯一背景
色源，本批把它落实到 UIColor 层）。

## 三、映射与阈值依据

- 亮度：WCAG 相对亮度（sRGB 分量线性化后
  0.2126/0.7152/0.0722 加权）。
- 阈值 `luminanceThreshold = 0.1791`：白字对比度
  1.05/(L+0.05) 与黑字对比度 (L+0.05)/0.05 的等
  值点，L = √0.0525 − 0.05 ≈ 0.17913——两侧对比
  度相等处翻转，任一侧都取对比度占优的字色。
- 调色板实算（SB-2 表驱动锁定）：T.bg 浅
  #F2F2F7 L=0.891 → 黑字；深 #000000 L=0 → 白
  字。备忘八色浅形态 L=0.670–0.907 → 全黑字；
  深形态（×0.55）L=0.194–0.240 → 全黑字（黑字
  对比 5.0–5.7 优于白字 3.7–4.2：深色下选了浅
  彩底的篇、带区是压暗后的中灰彩，黑字为采样
  应然，不是映射错误）。
- **贴阈值个案**：#e8d0d4 深形态 L≈0.180，与阈
  值 0.1791 相距 <0.005，白/黑对比 4.57/4.60 近
  等——方向由浮点实现决定、无感知差；SB-2 只钉
  「贴阈值」事实，不断言其方向。

## 四、送达链细节与一处工具链实证改判

1. 根观察器 `StatusBarObserverView`（零尺寸、
   不命中触摸）：以 lastStyle 去重，只认
   userInterfaceStyle 真变化，恰触发一次
   requestRefresh（根 VC 重估 + evaluate 补行）。
2. **registerForTraitChanges 排除（实证）**：
   原设计双路监听中 iOS 17 路
   `registerForTraitChanges` 在本机 Linux 工具
   链的 UIKit 链接桩中无符号——首次 tree 构建
   链接期 undefined symbol 四件（该方法 +
   UITraitUserInterfaceStyle 的 UITraitDefinition
   一致性见证），冒烟 [smoke 3/4] 红。故监听收
   敛为 `traitCollectionDidChange` 经典路
   （iOS 13+，部署目标 16.0 本就须有此路）：现
   行系统上 UIKit 仍正常投递该回调；且机制自带
   Diag 采样行，投递若失效、STATUSBAR 行缺失即
   证据，不静默。SB-4 已按此口径改判并注理由。
3. 编辑页：`editor.$bgColor.dropFirst()` 订阅，
   换底当场 setNeeds + evaluate(src=editor) 补
   行；订阅随控制器存续（cancellables 存控制
   器属性，与既有 keyboardCancellable 同生共死）。
4. 呈现/消失：编辑、图片两页 viewWillAppear 登
   记自身背景为平台面采样源、viewDidDisappear
   注销——栈式登记保证嵌套呈现回退时采样源回
   到下层页面，不残留。

## 五、与 Web 侧采样机制的异同

Web 侧口径在册（rust/apps/web/src/main.rs:266-
292）：平台（浏览器）按根页面背景绘制状态栏带
区，CSS 变量驱动的变更不触发带区重绘、会锁存
陈旧采样；应用对策是根背景内联直写 + 深浅切换
时同步先行写入。

- **同**：采样对象同为根背景单源；病理同形——
  平台采样会锁存陈旧值、回程腿不重估；对策同
  向——把决定权收回应用侧的权威写入/求值路径，
  不等平台自觉。
- **异**：Web 的采样者是浏览器、应用看不见采样
  过程，只能靠直写逼其重绘；原生本批把采样做
  进应用代码（解析 + 亮度判定 + Diag 取证），
  决定面可断言、可复算。Web 的文档头配套是
  theme-color 静态双色；原生对应面是 plist 的
  LightContent，仅管启动帧，运行期由承载链 +
  决策点接管。

## 六、真机终判点

1. 编辑页（无底色篇）系统外观 深→浅→深 往返
   两轮：每腿字色当场回位，不挂后台、不重进；
   Diag 应见成对 `STATUSBAR` 行（bg=#000000
   style=light ↔ bg=#F2F2F7 style=dark，src 含
   trait/editor）。
2. 编辑页浅彩底篇（如 #eaeef2）在深色模式打
   开：字色为黑（L=0.226，采样应然）；编辑内
   换底时字色当场随新底重估，Diag 有 src=
   editor 新行。
3. 首页、设置页往返切换：字色随外观当场翻转
   （平台承载面在 VC 化后的送达验证——第一阶
   段故障的原始现场）。
4. 图片页往返切换：字色当场回位（src=image）。
5. 开屏帧：浅色冷启开屏期字色观感（品牌蓝底
   L=0.1894 贴阈值个案）——异常则另立专用承
   载，不在本批判定内。
6. 救援/安全模式下往返切换：字色回位（观察器
   挂根 ZStack、救援态在位）。

## 七、验证与沿革

- verify_ios.sh：[8] 按 VC 化新口径改判（Light
  Content 保留检查 + true 必在、false 回潮即
  红）；新增 [53] SB 组——SB-1 决策单点（承载
  override 恰 2、主文件 0）、SB-2 采样映射主
  机表驱动实跑（亮度基线/灰阶边界/调色板全表/
  往返序列无闩锁/逆序重放一致，令牌
  STATUSBAR_CORE_PASS）、SB-3 单源计数锁（阈
  值字面独占核心文件）、SB-4 送达链恒发布、
  SB-5 构建接线（双文件各 28 遍登记 + .o 各
  ×2）。
- 既有计数断言沿革：新增两 primary 遍使全遍登
  记数 +2，DT46-6（25→27）、E47-8（26→28）、
  X50-7（26→28）已按各自沿革惯例更新并注本
  批出处。
- tree 冒烟过程两红均已定因收口：① 首轮 cargo
  步红于克隆 Web 文件新旧混杂（overlay 名单缺
  边角洞批的 editor.rs/model.rs，与本批无关，
  按同一传输通道补齐克隆后即过——该两文件已
  建议主线补入 push_small 名单，防后续批次重
  踩）；② 链接红于 registerForTraitChanges 桩
  缺口（见 §四-2）。
- 终局：tree smoke_ios.sh 全量 **ALL GREEN，
  verify 539 ✓ / 0 ✗**（0.9.61 基线 529，本批
  净增 [53] 五项 + [8] 改判 + 三条计数沿革）。
- 本批文件：新增 MomentStatusBar.swift、
  MomentStatusBarBridge.swift；改 MomentApp.
  swift（T.bgUI/memoBgUI 单源化 + 根观察器接
  线）、MomentEditorTransition.swift（两承载
  override + 登记/订阅）、build-app2.sh（新文
  件全 28 遍登记 + plist 翻 true）、verify_
  ios.sh（[8] 改判 + [53] + 三条沿革）、tree-
  sync/push_small.py（名单 +2）。Web 边角洞批
  7 文件零触碰。
- 证据分级：决定链与采样源 = proven（源码逐面
  核对 + SB-2 宿主实跑）；平台承载面 VC 化后
  的内部求值与采样判定一致 = inferred（不可
  见，靠终判点 3 验）；真机往返当场回位 =
  unknown（§六终判）。

## 八、附记

第一阶段诊断报告 diag_statusbar_dark.md 的磁
盘副本在本批开工时实查为截断状态（止于 §1.3
中段、尾带截断标记），其 §二以后结论以主线转
述为准据推进；建议主线核对该文件完整性后补齐
落盘，避免后续批次引用残本。
