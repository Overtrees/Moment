# 状态栏采样完整性审计与根治（fix_statusbar_sampling_integrity）

基线 main `bdf062c`，分支 `fix/statusbar-sampling-integrity`。以用户另一 App 的
「壳 App 采样翻车案」（跨域图污染画布 + 容错吞错 → 退回下层白卡、三采样点全读
241，似真值实错值）为对照清单，逐条映射审计 Moment 原生状态栏采样链
（MomentStatusBarPixel / MomentStatusBarEngine / 图片页注册点），坐实同型缺陷
三处，按红线在采样/回答层根治重构。Swift 类型级编译门留 tree 组版冒烟（既定
分工）；本机 verify 与 swiftc -parse 已过（见 §五）。

## 一、审计结论总表

| 对照条 | 结论 | 要点 |
|---|---|---|
| L1 取像素可静默失败 | **proven（潜伏错值 + 静默失败两形态并存）** | 覆盖门不感知裁剪：缩放平移形态下可对带下并不存在的内容采样并记 src=pixel；全部失败形态旧实现一律塌缩为 nil、读数不可辨 |
| L2 兜底必须带原因码 | **proven（缺陷）** | Diag 只有 src=pixel/data 两态；未覆盖（兜底即真值）与没取到、没解码好完全同貌 |
| L3 未就绪先不判 | **部分缺陷（行为侥幸正确、语义缺位）** | 图就绪重估已接线；但未就绪窗无暂缓语义、即时兜底且读数不分账——兜底恰与当时实景（页背景）同色才未出错 |
| L4 采样坐标须对真实图内容 | **proven（门缺陷；映射本体无误）** | EXIF 八向映射与 scale 换算逐项核对正确；错在覆盖门以未裁剪帧几何判定「覆盖」，见 L1 |
| L5 同型面普查 | **逐面关闭（证据在 §三）** | 唯一「媒体按设计应入带」的面就是图片页（即缺陷面）；其余面带下实景与数据答逐面同源 |

## 二、L1/L4 定案（几何证明，不依赖设备复现）

图片页构造（ImagePageView，MomentApp.swift）：图面可用区**顶让 126**、底让
40 + safeBottom，ZoomableImageView 的滚动框只存在于该让位区内；滚动框
clipsToBounds 全段零设置（默认 true，内容渲染恒被裁剪在框内）。状态栏带高
约 59。由此：

1. **适配态（contain）像素路径恒不可达**：图面渲染区顶界 ≥ 页面顶 +126，
   永远进不了带区；带下实景恒为 ChromeView 页头与 `.background(T.bg)`——
   原设计报告 impl_statusbar_native_adaptation §普查亦自承「带区恒为
   ChromeView 的 T.bg，此为构造口径」，却同时保留「图覆盖带中心才采样」
   的路径与其真机终判点（「带中心被图覆盖与未覆盖两形态」），预设与构造
   自相矛盾。全仓报告与代码记载中无任何 src=pixel 出现记录，与「恒不
   可达」互证。
2. **缩放/平移态覆盖门假阳性（错值形态）**：旧门 = `iv.convert(带中心)`
   + `iv.bounds.contains`。convert 与 bounds 均不感知裁剪：图放大并上移
   至底界贴滚动框底时，图视图在 window 坐标中的帧可大幅伸出滚动框上
   方，带中心随之落入 bounds 内、门放行，采到的是**已被裁剪、带下并不
   存在**的图内容；而带下实景仍是页头 + 页背景。引擎据此翻转并记
   `src=pixel`，与真测量不可区分——与对照案「读到下层/不存在内容的三
   个 241」同型（彼因跨域、此因裁剪盲区，形态同为似真值实错值）。
3. **静默失败形态**：imagePoint 的无 CGImage、尺寸退化、裁剪失败、全透
   明像素，与注册点的无窗、无图、未覆盖，旧实现全部回 nil → 引擎回落
   根令牌色记 src=data，与数据面、与「未覆盖（兜底即真值）」三者同貌。

## 三、L5 逐面普查

- **开屏（splash）**：带下即开屏渐变本体；SplashBandData 以与画布同源的
  停点投影带中心色，数据答出自实景定义本身，非固定值冒充。关闭。
- **首页/设置族（root）**：悬浮页眉 + 「顶部渐变罩」（页底色渐变，源码注
  记明言罩住穿行列表内容与状态栏区）——列表媒体卡穿行带下时被页底色罩
  覆盖，带答 T.bg 即罩顶色。关闭。注记：本基线根内容在安全区内（白边问
  题属 fix/statusbar-root-fullbleed 与安全区普查两线的几何面），样式答
  在两种几何下均正确，不属本批。
- **救援页（rescue）**：根令牌色平色面。关闭。
- **编辑页（editor）**：正文上距 155、悬浮页眉位于安全区下 7pt 且以备忘
  底色为底，滚动内容在本基线几何下不入带；答 = 备忘底色即带下实景。
  内嵌视频为 UIViewControllerRepresentable 内嵌承载（非模态呈现、不成
  为状态栏回答面）。关闭。
- **图片页（image）**：唯一缺陷面，见 §二。
- **layerPoint / videoCenter 两采样器**：无消费方（用户方案点名的待消费
  备置），其 nil 塌缩不进入任何判定，不构成缺陷面；本批不动，维持登记。

## 四、根治落点（采样/回答层，不在消费方打补丁）

1. **采样层三态成型**（MomentStatusBarPixel.swift）：新增
   `StatusBarPixelOutcome`（measured / notCovered / notReady /
   failed(原因码)）与 `StatusBarPixelFailure`（noraster / degenerate /
   crop / transparent）。imagePoint 与 readSinglePixel 改回三态：无
   CGImage→noraster、尺寸退化→degenerate、裁剪/上下文失败→crop、全透
   明像素→transparent、点不在图上→notCovered、成色→measured。
2. **覆盖门裁剪感知**（MomentApp.swift 注册点）：带中心须落在图视图可
   见区（图帧 ∩ 滚动框帧，window 坐标；滚动框是本链唯一裁剪祖先）内
   才采样；视图未入窗 / 图未备好回 .notReady，门外回 .notCovered。缩放
   平移下被裁剪的内容自此不可能再冒充实测。
3. **引擎按态消费**（MomentStatusBarEngine.swift）：像素源类型改回三
   态；图片面消费收口单点 `imageInput`——实测直入判定；未覆盖/失败以
   页背景兜底并带 px 分账（`notcovered` / `failed:<码>`）；未就绪（源
   未注册的图面未就绪窗 + 源报 .notReady）进**暂缓集**：集内保持现答
   不判定、集起记 `STATUSBAR defer surface=image px=notready` 一行并
   挂超时重估，超时（StatusBarParams.pixelReadyTimeout = 1.0，与四
   手感参数同单源）仍未就绪才兜底、记 `STATUSBAR fallback` 一行且判
   定带 `px=notready`；同窗已服务闩防重复起集，定态到达与面进出清集；
   集起时取消图片面既有候选（证据不跨未就绪窗落定）。
4. **读数分账**：面输入元组扩 px 分账位（编辑承载闭包同步扩位、恒
   nil）；flip 行与 appearance 证据行在 src 后拼 ` px=<分账>`。非图片
   面读数逐字不变。
5. **verify**（verify_ios.sh [53]）：SB-13 扩为五常数（pixelReadyTimeout
   同锁、管道普查形态）；SB-16 计数 3→4 改判（见 §五沿革）；新增
   **SB-18 采样完整性**（三态成型 + 失败映射 return 点 + 引擎四态消费
   + 裁剪感知门 + 暂缓两行 + px 分账拼装，全管道普查形态）。

## 五、验证与对账

- 本机 verify：基线 741 ✓ / 6 ✗ → **742 ✓ / 6 ✗**，增量恰 SB-18 一
  条；6 红与基线逐字同集（全为未构建工作树的产物红，tree 构建自解）。
- **PD73 棘轮零增量**：CNT 406 / PRES 1408 / FLOOR 34 与基线逐值同
  ——SB-18 与 SB-13 新增行全用 SB-11/15/16 既定的管道普查形态（批四
  成例：新断言零弱形态增量），帽未动。
- **SB-16 改判沿革**：基线计数 3 的三点实为根/救援、开屏回落、编辑缺
  登记回落——图片回落当时跨行书写（`resolvedColor(` 与 `with:` 分行）
  不在计数内、原注释归因（称第三点为图片回落）有误。本批图片面解析
  收口 imageInput 单点后四点全入账，计数改 4 并在锁注释内记明，不以
  跨行书写躲计数。
- **负对照三组实做**（SB-18 抽取块同口径复跑）：NC-1 摘除 intersection
  可见区门 → 恰红（gate=0）；NC-2 把 imagePoint 的 noraster 失败改回
  .notCovered（失败冒充未覆盖）→ 恰红；NC-3 改 defer 读数词形 → 恰红
  （defer=0）。三组还原后均复绿。
- swiftc -parse：四触碰文件全过。Swift 类型级编译门留 tree 0.9.68 组
  版 smoke（本机只落码 + 编译级自检的既定分工）。

## 六、行为等价账

- 适配态图片页：答案不变（页背景数据答），读数由 src=data 变为
  src=data px=notcovered（分账新增、判定不变）。
- 缩放/平移态：旧可采到带下不存在的图色误判，新恒未覆盖数据答——本
  批唯一的判定修正，即 L1/L4 的根治本体。
- 加载窗：旧即时以页背景答；新暂缓 ≤1s 保持前一面答案（push 期间前
  一面仍在屏、其答更合实景），超时以页背景答且带因。此为 L3 口径的
  有意变更。
- 采样失败（如 SVG 图页）：答案不变（数据答），读数带
  px=failed:noraster。
- 其余各面：判定路径与读数逐字不变（px 位恒空）。

## 七、装机验收格（归 0.9.68 桥自办）

1. 普通照片图片页：surface=image 的 flip/appearance 行须为
   `src=data px=notcovered`，全程不得出现 src=pixel（适配态）。
2. 双击放大 2.5× 后上移到底并保持：不得出现 src=pixel 行，答案保持
   数据答（旧形态在此可误采）。
3. 大图/慢加载图片页：出现 `STATUSBAR defer … px=notready` 至多一
   行；加载超 1s 时出现 `STATUSBAR fallback … px=notready` 且随后判
   定带 px=notready；图到后转 px=notcovered 分账。
4. SVG 附件图片页（有夹具时）：判定行带 px=failed:noraster。
