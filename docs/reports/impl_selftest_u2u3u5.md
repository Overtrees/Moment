# impl_selftest_u2u3u5 — 自检覆盖矩阵 U2/U3/U5 探针落地

日期：2026-11-28。依据：plan_selftest_coverage.md §6.1（U2）/§6.2（U3）/§6.4（U5），
矩阵增补记录 §4.13。性质：**实现批**——全部场景/探针只落码，桥上实跑待 BRG-09
（S1 于 0.9.58+ 复跑两遍 ok）后由主线另派，本报告不作任何实跑表述。

## 一、落点

### U2 几何探针（MomentBridgeUITest.swift：UITestProbes + measure 分发）

- `uitest_measure` 的 U1 壳（恒回 invalid_params）替换为探针注册表六件：
  P1 `card_alignment`、P2 `lift_gaps`、P3 `menu_panel`、P3 扩展 `slash_panel`、
  P5 `radius_derivation`、P4 `home_geometry`（U5 取项同表落地）。
- 几何前提账写在 UITestProbes 头注五条：坐标系分系标注（editorScroll / window
  不混算）、落定两读（首读后泵主 runloop 0.15s 复读、数值差 ≤0.5pt 标 settled）、
  正文列基准 = 在席内最宽行派生、face 哨兵口径（−2 未回报 / −1 面在子视图，
  未回报回 `surface_missing` 不充数）、lift 框派生标 derived 且主判读为面相对
  行盒的实测内缩量。
- 地基（MomentApp.swift）：BlockState face 通道五字段（faceMinX/faceMinY/faceW/
  faceH/faceRadius，非 Published）；三回报点——行级面由 BlockRow 行盒
  GeometryReader 同点回报（面 ≡ 行槽）、image/gallery 由行内分支面
  GeometryReader 回报（面 = 内缩后卡槽、faceRadius=−1）。slashPanelMaxH 由
  EditorUI 新增 @Published 承载，slashLayer 既有 onGeometryChange 内与渲染同点
  回写；editor.slashPanel 注册面补 panelH/panelMaxH 两键。

### U3 拖拽（DragPressEngine 现行口径）

- 行为等价重构：BlockRow 的 DragPressAnchor 四内联闭包抽为私有方法
  dragPickup/dragMove(_:)/dragDrop/dragCancel（方法体逐字搬移，含 M-10 的
  clearDragState），锚点改方法引用接线；同处新注册 `editor.blockRow` 面
  （instance=block.id；actions = 四方法；state 含 type/dragging/dragOffset/
  menuShown/faceRadius）。驱动与识别器回调自此共用同一组入口（S3 定案）。
- 场景 `drag_pickup_statemachine`（夹具 .blocks，复用 U4a 模板）：引用块拾起
  （face==行盒 ±0.5、faceRadius==Radius.quote、菜单骑拾起）→ cancel 复位 →
  段落拾起拖动（跟手量、菜单 >10 自动收起、下邻行让位量与 dragShift 同源公式
  期望对读）→ drop（块序下移、余块相对序不变、落盘回读一致、settle 偏移归零）
  → 换块 cancel 轮（状态清零、块序不变）。
- restore() 步③补实：夹具篇在席且 draggingId 在位时经行面 cancel 同体复位，
  面不在位以 clearDragState(for:) 同一单点兜底。
- `metrics_drag_trace` 出货（工具清单 35→36）：收集逻辑抽为
  BridgeDragTraceParser.collect(params) 单一来源，drag_trace_review 景改调之
  （§5 切换点兑现）；BridgeMetricsTools.dragTrace 镜像 createSettle 回结构化
  结论。协议 toolNames / 中继 worker.js TOOLS / 连接器 ALLOWED_TOOLS 三方同步，
  manifestHash（36 件）= c75689d57ac7236862d1382aae6e6741fa4d73fab874213cd2beee2ec9027156。
- 证据上限（不升级）：grades 含 `recognizer: "unknown (by construction)"` 与
  `geometry: "proven"`；状态机/让位/落盘/几何可 proven，触摸投递与识别器仲裁
  （长按触发/并行豁免/选区互斥）恒 unknown、归真机终判（EDT-28）。

### U5 首页/设置/图片页回路

- 新注册面十件（动作与手指同体、状态读不新造路径）：`home.view`（ListView 根；
  focusSearch/blurSearch/submitSearch/tapAvatar/closeDest/undoDelete + setText
  与搜索字段 Binding 同式；state 含命中集/compactP/scrollOffset/cols/空态等）、
  `home.row`（instance=memo.id、providesFrame；pin/delete 与左滑及网格菜单同体、
  open 同体；行帧经 RowFrameStore 无发布存储盒回报）、`settings.view`、
  `settings.diag`、`settings.diaglog`、`settings.gestures`、`settings.backup`、
  `settings.weather`（instance=qweather/caiyun；**只回 key 来源、绝不回 key 值**）、
  `settings.bridge`（MomentBridgeSettings，无动作）、`image.view`（close 与页头
  onBack 同体；ImgPageFlags 新增 viewportW/availH 同点回写）。
- 场景五件：`home_search_cycle`（.title；HOM-03 展开/命中/回车收口三段 +
  HOM-18 扩展段——改题回首页后命中集新鲜度断言，红即该缺陷的运行级证据 +
  HOM-04 辞焦段）、`home_surface_roundtrip`（.media；HOM-01 头像同体进设置、
  HOM-02 紧凑派生一致性、HOM-13 行点开在席、HOM-14 无命中空态）、
  `home_list_actions`（.media；HOM-07 封面 = 文档序首图断言、HOM-09 置顶两回、
  HOM-10 删除→待删态→撤销恢复、HOM-17 列表形态行圆角令牌）、
  `image_page_open`（.media；IMG-01 gallery 入口、IMG-02 清单名 + 12 字呈现
  截断、IMG-03 contain 关系式 + 8×8 小图不放大、IMG-06 关页后编辑器状态未清）、
  `settings_surface_roundtrip`（.title；SET-01 分组/版本、SET-03/04 天气两槽
  与自填腿、SET-05/11 诊断 autodel 同体两回、SET-12 日志页、SET-06 桥区读、
  SET-09 语言呈现腿——LangStore.apply 同体切换后按原态恢复、SET-07 备份状态
  腿、SET-10 手势行数、GLB-04 现档类目抽样）。

### 口径差登记（如实）

- IMG-01：运行腿 = gallery 项入口（瓦面无注册动作，景内以与点按逐字同式的
  imageTarget 赋值开页）；图块入口同 imageTarget 链，置位点对清单为构建期
  口径，不作运行级同路断言（矩阵 IMG-01 行已同步改判）。
- 天气自填腿：仅当 qweather 槽初始来源非 custom 时执行（写入假 key→custom→
  清除→回初始来源）；用户自填 key 在位时只读校验 + 断言注记跳过，不毁真实 key。
- HOM-14：全库空态不可由夹具制造，景内验无命中空态 + 结构在位读。
- GLB-04：DT 档位不可由 App 内驱动，抽样以设备现档为界（类目回读 + 设置面
  在位），大档帧关系归真机抽样。

## 二、提交清单（分项、未推送、未出包）

| 笔 | 内容 |
|---|---|
| 06abae6 | 矩阵先行更新（§4.13 增补记录 + 相关行现状） |
| f596822 | U3 工具链：metrics_drag_trace 出货（36 件）+ collect 单一来源 |
| c6bb21e | 矩阵改判：组号顺延定案 [68] 三段合组 + U5 注册面十面清单 + IMG-01 口径 |
| 1032e0d | 驱动侧：UITestProbes 六探针 + 六景 + restore③ + settings.bridge 面 |
| 6489fd2 | App 侧：face 通道/三回报点/slashPanelMaxH/四入口抽取/十注册面 |
| 1f4d22e | verify [68] 新组 + [16] 改判 36 件 + F30-2/PC44-6 基数更新 |

组号定案经过：初记 [63]/[64]/[65]，其间 [63] 审计批 4、[64] 审计批 3、[65] 批 6、
[66] 卡片防误触、[67] M3b 相继占用（主线协调两度改判），按矩阵 §8.5 尾号顺延
定案 **[68]** 三段合组（U68-1..7）。

## 三、自检账（本机，离线可验部分）

- verify_ios.sh 全量：**663 ✓**；红 3 项——「ipa 陈旧」「产物语言包缺失」为开工
  基线既有产物类（构建后自消）；**T24-5 为他线锁漂移**（标题提交/占位已由
  lang/标题线改判为 Lang.t("editor.untitled")，T24-5 字面锁未同步），非本批，
  留账待该线收口。
- [68] 组因脚本中段汇总块结构（见撞车账）在全量跑中未达，另以 standalone
  方式双跑验证：工作树版 7/7 ✓、已提交树（HEAD 抽文件）版 7/7 ✓。
- [16] 改判后 B16-3/B16-15 在全量跑中转绿 ✓。
- cargo test --workspace：全绿（本批纯 Swift，预期不受影响，实测确认）。
- **Swift 编译级检查本机未做**：本机无 swiftc（工具链在 tree），语法/类型终验
  随下次 tree 冒烟（smoke_ios.sh）一并完成——本批代码未经编译，此点如实标注，
  主线组版前须先过 tree 构建再谈实跑。

## 四、撞车账

- **F30-2 / PC44-6 基数更新（本批引起、已收口）**：home.view/home.row 与
  settings.view 的同体动作新增 resignSearch() 调用 +5、nav.route=.permissions
  赋值 +1，两条计数锁按文件内既有惯例更新基数（8→13、1→2）并注记来源；机制
  本体不变，非新路径。
- **verify 中段汇总块（既有结构、提请主线留意）**：脚本 8594 行有一处先行汇总
  块（fail≠0 即 exit），[65]–[68] 诸组位于其后——前缀有红时后段组不执行（本机
  因产物类两红恒在，[65] 起各组本机全量跑均未达，tree 全绿跑不受影响）。此
  布局为 [65] 追加时形成，非本批引入，本批未擅动他线组序，仅在此留账。
- **提交方式**：MomentApp.swift / verify_ios.sh 有他线暂存与未暂存 WIP，本批
  两笔（6489fd2/1f4d22e）经临时索引（GIT_INDEX_FILE）以 HEAD 为基线只入本批
  hunk 落成，未触碰真实索引中他线的暂存集；提交前逐笔复核 --stat 与删除行
  构成（6489fd2 的删除行全为拖拽闭包抽取本体）。另：本批早期一笔矩阵提交曾
  误卷他线暂存内容，已当场 soft reset + 路径限定重提修复（工作树全程未动）。
- 本批曾有一处以脚本整文件回写 MomentApp.swift 的操作（违反大文件外科落码
  规矩），写后已复验行数/文件尾/diff 完整，后续全部改回 muse.edit 落码，记此
  为教训。

## 五、未跑面登记（待主线另派）

- 全部六探针 + 六新景（drag_pickup_statemachine、home_search_cycle、
  home_surface_roundtrip、home_list_actions、image_page_open、
  settings_surface_roundtrip）的桥上实跑：待 BRG-09 门（S1 两遍 ok）后另派。
- metrics_drag_trace 工具的桥上实调同上。
- Swift 编译终验：待 tree 冒烟。
