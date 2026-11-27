# 状态栏字色深浅往返不回位——诊断（diag_statusbar_dark）

> **落盘完整性注记（0.9.62 组版核对）**：本文件磁盘副本不完整——正文止于 §1.3 中段，尾行带截断标记（`...[truncated 6854 chars]`），§二以后未落盘。本文现存部分的诊断结论（原生零状态栏代码、声明面与生效面矛盾、根治方向 = 决定权收回应用侧单点）已由第二阶段报告 **fix_statusbar_sampling.md** 承接并落码（用户 22:30 改判为全局背景色采样口径）；引用本症诊断与处置以 fix_statusbar_sampling.md 为准，本文件仅存已落盘部分，不补造原文。

用户真机实报（2026-11-27 22:16，0.9.60）：编辑页在系统深色外观下切到浅色，状态栏字变黑（对）；再切回深色，状态栏字仍是黑（错，应回白）。用户补充定性两段：① 此前做过「按背景色采样来动态适应」、且该采样是**全局生效**的；② 诊断范围两层都要——全局采样为根之外，各页面局部的状态栏决定面逐页对照，查清是全局闩锁、局部覆盖还是两者叠加。本报告为第一阶段（只读诊断），未落码；落码待主线放行（0.9.61 组版完成后）。

**结论先行**：原生侧不存在任何应用自建的背景采样器，也不存在任何状态栏代码——声明面是 plist 静态钉死（白字恒定），与真机「会自适应、且回程闩锁」的表现直接矛盾。真机实际生效的决定链不是声明面，而是平台的视图控制器/承载链；而应用对这条链**零参与、零纠偏**：回程那一腿平台没有重新求值时，应用没有任何面把字色扳回来。用户记忆中的采样机制真实存在，但不在原生代码里——它在 Web 侧（平台按根背景/顶层呈现层采样绘制带区、且会锁存陈旧采样，2026-11-23 真机定案在册）。原生本症与它同形（全局背景驱动 + 单向闩锁），根治方向一致：**决定权收回应用侧单点、按当前 trait 实时求值、双向都成立**，不靠平台采样/钉死任何一侧。

---

## 一、决定链全图（两层）

### 1.1 全局层（原生）

| 环节 | 事实 | 出处 |
|---|---|---|
| plist 声明 | `UIStatusBarStyle = UIStatusBarStyleLightContent`、`UIViewControllerBasedStatusBarAppearance = false`，由 build-app2.sh 写主应用 Info.plist（heredoc，$APP/Info.plist） | build-app2.sh:755-756 |
| 声明沿革 | 0.9.40（1756cd1）随开屏静态帧同批写入，提交注记为「状态栏口径」；audit2_image_misc 曾以「与原壳口径五项全对」判过——原壳是 Web 壳，其状态栏语义不迁移到原生场景生命周期（见 §三） | git 1756cd1；audit2_image_misc.md:32 |
| 签名后实物 | 用户签名后的 0.9.60 与未签包同值（LightContent / false），签名工具未动这两键 | /tmp/ipas60 与 /tmp/ipa60 的 Info.plist 逐键核对 |
| 按声明应然 | VC-based 关闭 + LightContent ⇒ 全应用恒白字、与外观无关（Apple TN3105 的 app-level 配方） | TN3105 |
| 应用内切换面 | 无。设置页「外观」组只有文字大小（跟随系统 Dynamic Type），无深/浅/跟随选项；全仓无 preferredColorScheme、无 overrideUserInterfaceStyle 落在窗口/根视图（仅两处离屏 WKWebView 渲图钉外观：公式 MathImageStore、SVG 光栅化，与窗口无关） | MomentApp.swift:20411-20435 设置段；全文检索 |
| 状态栏代码 | **零**。全部 *.swift + 构建脚本内无 statusBar 字面引用（plist 两键除外）、无 preferredStatusBarStyle、无 setNeedsStatusBarAppearanceUpdate、无 UIAppearance 代理、无 traitCollectionDidChange / registerForTraitChanges（仅一处 UITraitCollection.current 读值供公式渲图分档，MomentApp.swift:14734） | 全文检索（本报告 §五附检索面） |
| 场景结构 | SwiftUI App 生命周期：@main MomentApp → WindowGroup → ZStack{ListView 或 RescueView + 浮层}，无自建 UIWindow/SceneDelegate | MomentApp.swift:21849-21900 |

即：声明面把字色钉死为白，应用对状态栏再无第二句话。

### 1.2 全局层（Web，用户记忆的采样机制定位）

用户所说「按背景色采样来动态适应」在 Web 侧有完整的代码与定案记录，且确为**全局作用域**——采样对象是根页面背景（全应用唯一的背景色源，背景层级模型 2026-11-20 定调）：

- 平台侧采样（浏览器行为，非应用代码）：画布与视口外带区（状态栏带即在其中）由浏览器按**根元素背景**绘制；带区对 CSS 变量驱动的变更**不重绘、锁存陈旧采样**——2026-11-23 真机定案（变量已撤净、computed 已回落，眼见顶部实心栏仍为旧编辑色），见 rust/apps/web/src/main.rs:266-292 长注。
- 应用侧对策（这才是「做过」的部分）：根背景单次写入函数走**内联 style.backgroundColor 直写**（能触发带区重绘的权威路径）+ :root 变量同步镜像；调用方含「深浅切换的编辑器 scheme 处理」——即外观切换时由应用同步先行写入新根色，专治采样锁存（main.rs 同注）。
- 同族模型：design_lightbox_rootcolor.md 的 L3（带色由全屏遮罩层自身派生、浏览器采样视口边缘呈现层）/ L4（挂载时刻锁存：整屏层挂载冲击帧锁存采样、其后稳态正确也不重采）。
- 文档头配套：index.html 静态 theme-color 双色（浅 #ffffff / 深 #000000，带 media）+ `apple-mobile-web-app-status-bar-style=black-translucent`（audit_safearea_report.md §1.2）。注：iOS 26 起 Safari 大体忽略 theme-color、改为采样触碰顶边的最上层呈现层（外部实测口径），采样+锁存的形状不变。

**定位结论**：采样器不在原生应用代码内（原生与 Web 的 Rust/Swift 源码全量检索：无亮度/对比度计算、无背景色读取点、无 theme-color 动态写入）。原生侧与之对应的「采样」只能是平台状态栏机器按承载链/背景的内部求值，应用不可见、不可控——这正是根治要改变的格局。

### 1.3 页面局部层（原生逐页对照）

| 页面 | 承载形态 | 局部状态栏决定面 | 与本症关系 |
|---|---|---|---|
| 首页（列表/网格） | SwiftUI NavigationStack 内部承载控制器（平台所有） | 无应用侧 override；根视图 ZStack 无 preferredColorScheme | 平台链直辖；用户未在此页报症（未测得，不等于无症） |
| **编辑页** | **EditorHostingController**（UIHostingController<EditorView> 子类）经 EditorTransitionHost 手动 push 进同一个 UINavigationController（探针沿响应链登记） | override 仅两件：viewWillAppear 隐导航栏、viewDidDisappear 的 onRemoved 收口；**无 preferredStatusBarStyle、无 trait 钩子**（MomentEditorTransition.swift:79-95） | 用户发现页。局部无覆盖——排除「编辑页自己把字色改黑/钉住」 |
| 编辑页·页眉（含完成胶囊） | 页内悬浮玻璃件（GlassCard 材质 + 玻璃令牌） | 只绘制状态栏后方的内容，不参与字色决定 | 无关（它决定「字后
...[truncated 6854 chars]