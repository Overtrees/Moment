# 开屏白边根治（fix_statusbar_root_fullbleed，2026-11-28）

## 缘起与定因（主线定因，proven）

0.9.67 装机首启实报：开屏品牌蓝未铺满——顶部状态栏带与底部小横条带为白色，
蓝区像素实测恰为安全区矩形（顶 ≈59pt / 底 ≈34pt）；首页同病只是带区与页色
接近而无感。定因：0.9.67 状态栏根容器（StatusBarRootContainer，
UIViewControllerRepresentable）未忽略安全区，框架把根内容树整体收进安全区
矩形承载；开屏本体（SplashOverlayView 满幅画法）与状态栏引擎（答案正确）
逐字无恙。本批只修承载几何与露底链，不碰开屏本体、引擎与参数。

## 落码（两处，各自理由）

分支 `fix/statusbar-root-fullbleed`，基线 main `ac79ed7`。

### 第 1 处（主修）：根段 representable 满幅

`MomentApp.swift` WindowGroup 根段：StatusBarRootContainer 补
`.ignoresSafeArea()`（+8 行含注释）。几何链：representable 满幅 → 容器 VC
视图帧 = 窗口帧 → `embed()` 中 `host.view.frame = view.bounds` 随之满幅 →
内层 SwiftUI 中开屏层 `splashColor.ignoresSafeArea()` 的满幅画意才有全窗
画布（此前画布被钳在安全区帧内、画意再满也出不了帧）；首页背景同链受益。

### 第 2 处（露底链显式化）：embed 托管视图背景 clear

`MomentStatusBarRoot.swift` `embed()`：`host.view.backgroundColor = .clear`
（+8 行含注释）。取舍依据（工单实验定序的条件判定）：

- 源码面可确证的透明链只到容器视图为止——容器视图是 loadView 的素
  UIView、全仓从未设其背景（nil 透明，UIKit 语义可确证）；框架根托管视图
  与 0.9.66 同构未变。
- 内嵌托管视图（UIHostingController 专用视图）的默认背景在本机无 SDK
  头文件可查、**无法仅凭源码确证**其必透明；而 0.9.67 像素事实是：铬面
  探针已把窗口底色设为开屏同源品牌蓝、带区仍呈白——新链中确有不可确
  证的不透明可能面。
- 故按定序落第 2 处：若该视图本已 clear，本行是无副作用的显式钉子；
  若其自带不透明底，本行即为带区回窗口色的充要修复。两处理由独立成立，
  非无据叠加。

## 断言（verify_ios.sh [53] 新增 SB-17）

- SB-17 根容器满幅：@main 段内 `.ignoresSafeArea()` **整行锚定**恰一 +
  去注释口径的 MomentStatusBarRoot 内 `host.view.backgroundColor = .clear`
  整行锚定恰一。
- 负对照实做两组，均恰红 SB-17 一条、余组不动，污染已逐一恢复：
  - NC-1 根段修饰行后缀污染 → 红（app=0 clear=1）；
  - NC-2 clear 行后缀污染 → 红（app=1 clear=0）。
- 如实登记：SB-17 首版用子串计数，被 NC-1 当场击穿（后缀污染仍含子串、
  计数不变、假绿）——改整行锚定后复跑 NC-1/NC-2 均恰红，方定稿。

## verify 对账（本机同树）

- pristine 基线（ac79ed7、未构建工作树）：741 ✓ / 6 ✗。
- 落码后：742 ✓ / 6 ✗——增量恰为 SB-17 一条；6 红全为产物红（ipa /
  Assets.car / 开屏向量 ×2 / 语言包 / SG49-4 样本），与基线同集，
  tree 构建后自解（0.9.67 冒烟口径）。
- SB-11…SB-16 全绿不回退；PD73 棘轮 CNT 406 / PRES 1408 未动仍绿。

## 装机验收格（登记，未验）

自检矩阵 plan_selftest_coverage §7 已增一行「开屏/首页带区满幅」。
归 0.9.68 桥自办 / 用户截图终判：

- 开屏截图顶/底带应为品牌蓝（与开屏画布同色、无白带）；
- 首页带区应为 #DAE3F0（与页底同色）。

本批为源码面 + 断言面收口，不冒充设备已验。

## 面纪律

MomentApp.swift 只动 WindowGroup 根段一行域（修饰 + 注释），与原生画廊批
（编辑面）区域不重叠；开屏本体、状态栏引擎、参数、SB-8/9/10 零改动。
