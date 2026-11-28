# 状态栏全页回退（三轮渲染采样整层拆除，回到兜底版）

定案与执行记录，2026-11-28。对象：原生 iOS 状态栏字色机制（三轮
fix_statusbar_render_sample.md 所建的带区实渲染采样层）。

## 一、裁定与范围

用户 2026-11-28 装机 0.9.63 后实报开屏状态栏有问题，裁定回退；随后范围
经两步收紧为**全页回退**：

1. 三轮渲染采样整层拆除，全页回到三轮之前作兜底保留的那一层——provider
   登记色 + evaluate 单点决策——扶正为唯一机制。
2. 根承载容器一并拆除，window 根与开屏承载恢复三轮前形态，不以别页采样
   所需为由保留（回退后别页走登记色 evaluate，本就不需要它）。
3. 保留两项勿退：① 开屏 iPhone 方向锁（SB-8/idiom 闸，用户独立裁定）；
   ② CIELAB L* 61.65 度量（兜底版 evaluate 本就跑在此度量上，八色改判
   不回归）。
4. 图片页回登记色口径，不复活已删的 MomentStatusBarImage.swift 独立
   采样器（兜底版里它本就不存在；其覆盖率字段在三轮只是 Diag 附加项，
   随三轮一并退役）。

用户补充症状（回归账）：整个开屏画面受影响——闪白、能看到首页空态、
开屏结束时闪黑。机制定性见 §三。

## 二、回退切面清单（文件/函数级）

源码（rust/apps/ios/app/）：

- **MomentStatusBarRender.swift**：整文件删除（BandRenderSampler 本体）。
- **MomentStatusBar.swift**：文件头改判；带区几何组（SBRect /
  intersection / coverage / blendedLightness）删除；prefersLightContent
  (lightness:) 过载删除（删后全域普查零消费方）。L* 阈值 61.65 与核心
  判定不动。
- **MomentStatusBarBridge.swift**：文件头改判；renderedStyle 整函删除；
  requestRefresh 复原为戳承载链；style("trait") 证据行恢复；evaluate
  文档陈旧措辞顺正。
- **MomentSplashHost.swift**：文件头与 SplashBandColor 注复任主采样源；
  preferredStatusBarStyle 改 evaluate(background: bandColor())；
  layout/trait 两 override 去采样器 refresh；noteDismissed 与安装器
  重试删除（dismiss completion 简化）。方向锁与 registerCurrent 未动。
- **MomentEditorTransition.swift**：编辑/图片承载改 evaluate；两
  viewDidAppear 采样 refresh override 删除；换底订阅只留 setNeeds；
  observeImage 去 statusBarSampler 实参 / invalidateImage。
- **MomentApp.swift**：ZoomableImageView 的 bandSampler 属性与
  Coordinator 接线删除（scrollViewDidScroll / DidEndDragging /
  DidEndDecelerating / DidEndScrollingAnimation 四回调经核实仅为采样器
  存在，整删；DidZoom 只留 center）；ImagePageView 的 statusBarSampler
  属性/实参/onDisappear 作废调用删除；根 background 块删
  StatusBarRootMount() 并改写注释。

构建（build-app2.sh）：渲染遍整遍删除 + 其余 30 处 Render 输入行删除 +
链接行 statusbar_render.o 摘除 + 遍注释改判。实测计数：StatusBar /
Bridge / Splash 各 30 遍、FontFactory 29、三 .o 各 2、render/image.o
各 0。tree-sync/push_small.py 名单同步删 MomentStatusBarRender.swift
一行（仓外文件，不入提交）。

零残留普查（swift 全域，本机与 tree 克隆各一份）：
BandRenderSampler / renderedStyle / StatusBarRoot / noteImageScroll /
invalidateImage / drawHierarchy / bg=render / ImageBandSampler /
evaluateLightness / coverage / blendedLightness 均零命中。

## 三、回退前后各页承载与采样链对照

回退前（三轮态）：根容器 StatusBarRootContainerController 置 window 根
（src=root），BandRenderSampler 以 drawHierarchy 实渲染带区 + 指纹 +
90ms 节流为全页主采样，编辑/图片/开屏承载同问 renderedStyle，evaluate
只作兜底，Diag 以 bg=render 区分来源。

回退后（兜底版扶正）：模式层（dyn 令牌 + trait 链 + provider 登记栈）
为唯一基础；各页以自有承载经 evaluate 单点决策——编辑页 memoBg、图片页
T.bg、开屏公式色 bandColor()，Diag 标记 src=editor/image/splash；根页面
恢复平台承载 .default 决定（与 T.bg 双形态 evaluate 判定逐值一致，
二轮审计结论）；Diag 只剩 bg=#RRGGBB 一路。

## 四、三症状机制定性（证据分级）

无设备侧 Diag/抓帧留证，逐症状帧级归属不冒充 proven；以下为代码级
回源结论：

- **闪白**：根承载安装在启动期探针节拍同步换根，容器 .clear 覆窗口
  默认底色——换根机制本身代码级 proven，逐帧归属 inferred。
- **透出首页空态**：换根重挂使根 SwiftUI 首帧（首页数据未就绪的空态）
  在竞速中透出——inferred，无设备抓帧直证。
- **结束闪黑**：presented 守卫使根承载安装被推迟到开屏卸载节拍，与
  退出淡出同刻相撞，深色 trait 下窗口底为黑——节拍调度代码级 proven，
  逐帧归属 inferred。
- 采样器 drawHierarchy 只读、不改呈现，直接致因排除（proven，代码级）。

三症状共同指向根承载换根而非采样源本身；本批将根容器与采样层一并
拆除，即按此定性取根治切面。

## 五、已知缺口复归登记

内联兜底开屏的字色采样缺口随根容器拆除复开，与二轮登记同口径：开屏
走内联兜底形态（资源异常降级）时，字色由公式色 evaluate 决定、不做
实渲染采样——此为兜底版的既有边界，非本批新引入。根页面平台决定面的
精确表述以二轮报告 fix_statusbar_dynamic.md 为准。

## 六、verify [53] 改判表

- 组题加 fix_statusbar_rollback_all 沿革。
- SB-1 改判：核心 5 符号 + 生效层 7 符号 + 承载 override 恰 3、主文件
  0；零残留集扩入 renderedStyle / BandRenderSampler。
- SB-2：嵌测删带区几何段（SBRect/coverage/blendedLightness 用例），
  头注与 ok 文案同步；L* 基线/边界/调色板/渐变用例未动。
- SB-4：删根承载三节拍五条件（根容器已拆，无此机制可锁）。
- SB-5 改判：三文件各 30 遍；两代采样器名与 .o 零残留。
- SB-6 整组改写为回退接线锁：evaluate 面 TRANS ≥2 / SPLASH =1、
  SplashBandColor ≥1、渲染层符号集零残留、两代采样器文件不存在。
- SB-7：前提注释改判（公式复任主源），锁体与容差未动。
- SB-8：未动（方向锁保留）。
- 跨组计数同步：DT46-6 30→29、E47-8 31→30、X50-7 31→30，各注沿革。

## 七、验证结果

- 本机：verify_ios.sh 594 ✓ / 2 ✗（2 红为既有产物陈旧对：ipa 新鲜度 +
  产物语言包 md5，tree 重建归零口径）；[53] SB-1…SB-8 全 ✓；
  cargo test --workspace 20 套件零失败。
- tree：overlay 落克隆 + 显式删克隆内 MomentStatusBarRender.swift +
  克隆残留普查零命中后，全量 smoke_ios.sh **SMOKE ALL GREEN**
  （日志 /data/home/smoke_rollback_tree.log）：verify 596 ✓ / 0 ✗，
  SB-1…SB-8 回退口径全 ✓，cargo/FFI/构建四步全过。build-app2.sh 改过
  遍结构，构建级验证在此轮完成。
- tree 快照口径注记：同步为 push_small 推送时点的工作树快照，自洽性
  以快照内为准（如 F30-21 在快照内以门带 15 通过，与主仓其后并行批
  改判 30 不冲突，两者各自快照内一致）。

## 八、真机终判点（留 0.9.64 组版后用户装机判读）

1. 开屏全程三无：无闪白、不透出首页空态、结束无闪黑。
2. 浅主题开屏全程白字（公式色 evaluate + L* 61.65）。
3. iPad 形态与方向行为不变；开屏 iPhone 方向锁仍生效。
4. 各页 Diag 只见 bg=#RRGGBB 行，无 bg=render 来源行。
5. 八色改判不回归（深/浅色备忘、图片页登记色字色与 0.9.62 口径一致）。

## 九、提交与协作注记

本批与审计批 3/4/6 并行同仓作业，MomentApp.swift 与 verify_ios.sh 为
多线共享文件：提交按 hunk 级分拣，只入本批回退 hunk，他线在途改动
（含 MomentImageLoad.swift 媒体解码批）原样留在工作树未动。本批不
推送、不出包，留主线组 0.9.64。
