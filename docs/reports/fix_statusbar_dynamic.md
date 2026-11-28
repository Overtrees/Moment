# 状态栏字色二轮根治：动态识别带区后方实际内容（fix_statusbar_dynamic）

状态：落码完成、待 tree 全量冒烟与真机终判（留主线组 0.9.63，不单独出包）。
缘起：用户 2026-11-28 真机（0.9.62）实报两症——① 图片页图片滚过状态栏
带区时字色不随之变；② 开屏浅色主题下状态栏字一直黑。用户口径：状态栏
字色须动态识别变化——带区后方是什么内容（随页、随滚动、随主题）就按其
实际感知明暗实时判定；按开发红线全面根治，不做单页补丁。

一轮根治（fix_statusbar_sampling）立了采样单点与静态采样源清单；本批把
「采样源」从静态登记升级为带区实况，并把判定度量从 WCAG 对比度比率换
成感知明度。机制面三件：纯核心换度量（MomentStatusBar.swift）、图片页
带区像素采样器（MomentStatusBarImage.swift，新）、开屏独立承载
（MomentSplashHost.swift，新）。决策单点仍是 MomentStatusBar.evaluate /
evaluateLightness，全应用无第二决定面。

## 一、定性（证据分级）

### 症状① 图片页：采样源与滚动实际覆盖脱节（proven，代码级）

一轮口径把图片页采样源点名为页面根背景 T.bg（静态登记）。代码级事实：
图片页的滚动视图（ZoomableImageView = UIScrollView + UIImageView）全屏
铺设，图片缩放/平移后其可见矩形可与状态栏带区（window 顶部安全区高）
交叠；而采样链对此毫无感知——承载控制器 preferredStatusBarStyle 只读
登记的静态色。故「滚过带区字色不变」是采样源定义问题，不是送达问题。

几何附注（inferred → 待真机 Diag 终判）：按现行布局算术（滚动视图顶边
在绝对 y=126、带区约 59pt），静止 contain 态图片本不应进入带区；用户实
报可达。本批实现不预设相交与否：运行时以 convert(to: window) 实测图片
可见矩形与带区矩形的交叠覆盖率，真机 Diag 的 cov 值将终判此几何分歧。

### 症状② 开屏：双因并存（均 proven）

因一·采样源错位（架构级 proven）：开屏此前没有应用自有承载、也没有登
记采样源——它只是根 ZStack 里的一层 SwiftUI 浮层，状态栏由平台承载控
制器在应用采样单点之外内部求值。平台内部启发式细节为 unknown，但各候
选口径对浅主题品牌蓝都给出黑字，与症状一致。

因二·度量对高饱和蓝感知失真（数值级 proven）：开屏稳态带区实色是渐变
色而非垫层平色——按 shipped 资源原表（assets/native-splash 两份 vector
JSON）以绘制同式（cover 变换 + 轴投影分段插值 + 12×4 网格）复算，浅主
题带区平均色 ≈ (51.6, 146.1, 242.7)，其 WCAG 相对亮度 Y=0.278 > 一轮
阈值 0.1791 → 判浅底黑字。而该色的感知明度（CIELAB L*）为 59.67，属
中深；开屏 artwork 自身标语在浅主题用白色填充（#FFFFFF）、深主题
#F5F5F7——设计方亦自判此蓝为深色类。比率阈值是「哪种字色对比度更高」
的中点，对高饱和色与人眼感知明暗系统性脱节，此为二因。

开屏帧一致性：plist UIStatusBarStyle=LightContent 使系统开屏帧本为白
字；本批把 app 内开屏停留期收进自有承载同口径判定，两主题均白字（见
§二全表），帧与停留期一致。

## 二、判定度量换代：WCAG 比率 → CIELAB L*

阈值推导：取白字 WCAG 对比度恰 3.0（大字/图形级可读下限）之点——
1.05/(Y+0.05)=3 解得 Y=0.30，换算 L* = 116·0.30^(1/3) − 16 ≈ 61.65。
感知明度 L* < 61.65 → 深色类、白字；高于 → 黑字。L* 为 CIE 感知明度
本体，即用户口径「实际感知明暗」的度量。APCA 因常数无法可靠复述未采
用；L* 路线可确定性实现，且与 APCA 在本表各色上判定一致。

全色表（L*，阈值 61.65；verify [53] SB-2 宿主单测全表锁定）：

| 色面 | L* | 判定 | 与一轮口径 |
|---|---|---|---|
| 纯白 | 100 | 黑字 | 不变 |
| 纯黑 | 0 | 白字 | 不变 |
| 中灰 #808080 | 53.59 | 白字 | **改判**（旧比率判黑字） |
| 灰阶 0.55（边界下） | 58.35 | 白字 | — |
| 灰阶 0.62（边界上） | 65.15 | 黑字 | — |
| 根背景浅 #F2F2F7 | 95.62 | 黑字 | 不变 |
| 根背景深 #000000 | 0 | 白字 | 不变 |
| 开屏垫层平蓝 (35,121,220) | 50.92 | 白字 | 改判（治症状②） |
| 开屏渐变带区·浅 (52,146,243) | 59.67 | 白字 | 改判（治症状②） |
| 开屏渐变带区·深 (38,38,40) | 15.23 | 白字 | 不变 |
| 开屏垫层深 (31,31,33) | 11.83 | 白字 | 不变 |
| 开屏降级件·浅（根色） | 95.62 | 黑字 | 不变（资源损坏兜底路径，与 plist 帧有一帧级不一致，已登记） |
| 备忘八色·浅形态 | 85.5–96.3 | 黑字 | 不变 |
| 备忘八色·深形态（×0.55） | 49.5–56.1 | 白字 | **全数改判** |

沿革登记三项：
1. 度量更换：WCAG 相对亮度阈值 0.1791 退役，核心符号 luminanceThreshold
   全仓零残留（SB-1 锁）；relativeLuminance 保留为 L* 的中间量 Y。
2. 备忘深形态改判：一轮曾以「黑字对比度占优」为采样应然——那是比率口
   径的结论；纯 L* 阈值无法把渐变蓝（59.67）与备忘深形态（49–56）分
   开，二者在感知明度上本就同类，用户感知口径下统一归深色类。本批最
   显眼的行为变更，真机终判请用户目检（§五）。
3. Diag 字段改名：STATUSBAR 行的 lum=（相对亮度）改为 lst=（L* 一位小
   数），防两代数值混读。

阈值裕量备注：渐变带区浅色 L* 59.67 距阈值约 2——裕量来自带区面积平
均的采样定义（渐变末 stop #3898F8 单点 L* 61.72 仅一线高于阈值）；设
备尺寸敏感性已复算（393×852 与 430×932 两档 ΔL* ≤ 0.07），判定稳健。

## 三、采样动态化

### 图片页（MomentStatusBarImage.swift：ImageBandSampler）

- 几何面：图片可见矩形（图视图 ∩ 滚动视图，window 坐标）与带区矩形
  交叠覆盖率走纯核心 StatusBarCore.coverage；覆盖率 ≤0.001 不出值，
  承载回落既有 T.bg 静态求值——静止态零扰动。
- 像素面：覆盖率 >0 时把 window 带区条带以 drawHierarchy 实渲染进小
  位图（与屏幕合成逐像素一致，含图片当前帧、根背景与一切图层，免手工
  坐标/EXIF 方向换算；decodeImage 的方向只在 UIImage 层成立、cgImage
  裁剪不可靠，故不走像素裁剪路），缩绘 16×4 逐像素平均 L*。
- 节流与收尾：滚动/缩放事件 90ms 节流 + 尾随一次；结束拖动/减速/动画
  与落定（updateUIView）必实算一次，终态不停在中间态。
- 送达：判定（白字/黑字/回落）变化才经 onDecision 戳承载重估；承载
  preferredStatusBarStyle 有采样值走 evaluateLightness（src=imgpage-
  scroll、Diag 带 cov），否则回落 evaluate（src=image）。
- Diag 纪律：evaluateLightness 去重键 = 来源+判定，同判定不记行防刷
  屏，翻转必记一行。

### 开屏（MomentSplashHost.swift）

- SplashHostingController 全屏呈现（modalPresentationCapturesStatusBar
  Appearance），preferredStatusBarStyle 走 evaluate（src=splash），采
  样源 = SplashBandColor：按当前主题取 artwork 数值表（与绘制同源解码
  的 backgroundStops/Start/End），以 StatusBarCore.bandAverageColor
  按视图实尺寸 + 顶部安全区实高现算带区平均色；安全区未落定（首帧）
  回退垫层平色——带区在画布落定前实际露出的正是垫层色，采样与呈现
  一致；首个有效安全区高出现时一次性重估（viewDidLayoutSubviews）。
- 托管根视图与根层级同构：ErrBadgeOverlay 在下、SplashHostView
  (hosted: true)、WatchdogBar 在上；LangStore.shared 显式注入。
- 时序状态机不搬家：SplashState 仍由 SplashHostView 驱动，gone 翻转
  经呈现器订阅以 exitDuration（0.26 / 减弱动态效果 0）做承载视图
  alpha 淡出后卸载，复刻内联口径。
- 兜底：呈现通道异常（窗口/根控制器久不可用，有界重试 10×0.25s）置
  SplashGate.inlineFallback 回落根内联呈现（InlineSplashHost）并记
  Diag，开屏呈现不成为启动单点故障；安全模式/资源缺失不挂载呈现器
  （与旧内联挂载条件同口径）。

## 三之二、开屏方向锁（用户 2026-11-28 08:14 追加裁定，并入本批）

裁定：iPhone 下开屏界面不跟随系统转向——开屏呈现期间方向锁定竖屏
（设备横置也不转），开屏退出后恢复全应用既有方向口径；其他页布局与
方向行为零改动；iPad 不在范围（用户 08:15 再次强调不要误伤）。

现行方向机制定性（回源 proven）：全应用方向只由 Info.plist 决定——
生成的 plist 只有 UISupportedInterfaceOrientations~ipad 一键（竖屏 +
左右横屏），无 iPhone 专属键、无全局键（iPhone 走系统默认口径：除倒
置外全向）；Swift 侧无 AppDelegate/Scene 方向掩码、无任何
supportedInterfaceOrientations override（全仓零命中）。故与现行机制
同构的最小面 = 全屏呈现中的承载控制器 override——与本批状态栏字色
的 override 单点同一模式、同一文件。

落码（MomentSplashHost.swift，SplashHostingController）：

    override var supportedInterfaceOrientations:
        UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone
            ? .portrait
            : super.supportedInterfaceOrientations
    }

- 恢复语义：掩码只在承载在位期间生效，退出卸载即由根的 plist 口径
  接管，无状态需回滚、无其他页感知。
- iPad 闸（结构锁死）：收窄以 idiom 为闸，iPad 路径恒回 super 既有
  口径，结构上不可达收窄；Info.plist 的 ~ipad 数组逐字零 diff；
  NativeSplashCanvas 的 isPad 分支（foregroundScale 钳制、logo/tagline
  纵置）零改动。verify [53] SB-8 守卫四件：override 恰 1 且全仓仅此
  文件持有该符号、idiom 闸在位、~ipad 数组逐字在位且无全局键被引
  入、isPad 分支两处特征字面在位。
- 与本批采样/量测的交互：竖屏锁定后 iPhone 开屏几何恒为竖屏口径，
  SplashBandColor 的视图实尺寸 + 安全区实高现算天然落在此前提下；
  SB-7 的规范几何（393×852 竖屏、带区 59）即 iPhone 开屏的唯一形
  态，无横屏开屏假设需纠正（本批带区量测从未设横屏开屏分支）。
  iPad 开屏方向维持现状，其带区采样仍按运行时实尺寸/实安全区现
  算，不受锁影响。
- 已知缺口登记：内联兜底路径（InlineSplashHost，呈现通道故障时才
  启用）无应用自有承载，方向锁与采样单点均不覆盖该路径——属故障
  兜底的既有边界，本批不为其另起 AppDelegate 全局机制（与「最小
  面」裁定一致），登记备查。

## 四、全页面带区审计

| 页面 | 带区后方内容（静止/滚动/主题/横竖） | 一轮采样源 | 一致性 | 本批处置 |
|---|---|---|---|---|
| 首页 | 根背景 T.bg 静态面 | 平台承载（根色单源） | 一致（新度量下判定不变） | 不扰动 |
| 设置族/救援 | 同上 | 同上 | 一致 | 不扰动（C-02 收窄批另行） |
| 编辑页 | 备忘底色 memoBg（静态面、随主题×0.55） | 自有承载 + memoBg 登记 | 采样源一致；判定随度量换代 | 深形态改判白字（§二沿革 2） |
| 图片页 | 静止 = 根背景；缩放平移后 = 图片实帧 ∩ 根背景 | 自有承载 + T.bg 静态登记 | **不一致**（滚动覆盖脱节） | 动态采样器接管（§三） |
| 开屏 | 品牌渐变（带区为渐变顶部段）+ 垫层 | **无承载、无登记**（平台内部求值） | **不一致**（源错位 + 度量失真） | 收进自有承载 + 渐变带区采样（§三） |
| 系统呈现面（选图器/分享等） | 系统内容 | 系统决定 | 范围外 | 不动 |
| 横屏 | 带区高为 0（刘海机型横屏顶部安全区 0） | — | 无带区即无判定问题 | 采样以运行时安全区为准（bandH≤0 回退平色/根色） |

## 五、验证与真机终判点

本机/tree 验证：verify [53] 改判扩充——SB-1 决策单点（核心六符号 +
生效层八符号 + override 恰 3 + 旧阈值符号零残留）；SB-2 宿主单测全
表换 L* 口径（基线/灰阶边界对/调色板全表/带区几何/渐变纯函数/往返无
闩锁）；SB-3 阈值字面 61.65 独占核心；SB-4 送达链增开屏面；SB-5 构
建接线四文件各 31 + 四 .o 各 ×2；SB-6 图片采样接线锁；SB-7 资源对账
（python 独立复算带区平均 ±3 + 核心函数复现 ±4）；SB-8 开屏方向锁
单点 + iPad 守卫（§三之二）。普查同步：DT46-6
28→30、E47-8 29→31、X50-7 29→31（各 +2 遍沿革）。构建名单三处齐：
build-app2.sh（31 遍 + statusbar_image/splash_host 两 primary 遍 +
链接行）、push_small.py 名单 +2、tree overlay cp 须含两新文件。

冒烟结论：tree smoke_ios.sh 全量 **ALL GREEN**（2026-11-28，日志
/data/home/smoke63d-tree.log；verify 587 ✓ / 0 ✗，含 SB-1…SB-8）。
收口过程三红均在本批新面内、逐一根因修复并留账：① NativeSplash
Artwork 去 private 后三件文件私有类型属性暴露违规 → 属性收
fileprivate（消费方同文件、跨文件零消费）；② 采样器 drawHierarchy
的 CGRect size 误传 CGRect → 改 .size；③ 三条新断言自身的写法错
（属性名大小写 modalPresentationCaptures…、生成测试文件须名
main.swift 才许顶层语句、grep 模式含未转义 *）→ 断言按机制形态修
正，产品代码未动。

真机终判点（归用户）：
1. 图片页：缩放/平移使图片覆盖状态栏带区，字色随图片明暗实时翻转；
   移开后回落根背景判定。Diag 应见 src=imgpage-scroll 行且 cov 随覆盖
   变化——cov 实测值同时终判 §一的几何分歧（静止算术 vs 实报可达）。
2. 开屏：浅色主题开屏全程白字（系统帧与 app 内停留期一致）；深色主
   题不回归。iPhone 横置启动/开屏中途横置：开屏恒竖屏不转，退出后
   方向恢复既有口径（可转横屏）；iPad 开屏方向与形态与此前一致。
3. 编辑页：浅形态备忘底色字色不变；**深色主题下浅彩底备忘的字色由黑
   改白**（§二沿革 2），请目检可读性与观感。
4. 首页/设置：深浅往返字色不回归（判定不变、机制未扰动）。

## 六、教训沉淀

- 采样源清单必须按「带区后方实际内容」逐页核，而不是按页面登记静态
  色：凡带区后方可变（滚动、缩放、渐变、覆盖层），静态登记即脱节。
- 对比度比率回答「哪种字色更可读」，感知明度回答「这块表面看起来深
  还是浅」——用户口径是后者；度量选型先对问题，不沿用上一批的现成
  阈值。
- 无自有承载的呈现面（浮层式开屏）是采样体系的盲区：平台内部求值够
  不着应用单点，审计时须把「谁在承载状态栏」逐面点名。
