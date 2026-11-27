# 卡片圆角全面排查与根治 + 动态圆角适配机制（0.9.52，未提交）

用户 2026-11-27 点名：图文卡片（imgTextCard）、混排卡片（imageTextRow）等圆角不配，要求全面排查同类、根治，并落地动态圆角适配（圆角按嵌套关系动态派生、不再各处写死）。

结论先行：**静态卡面本身全部配**（逐项与 Web 对账无误）；不配集中在**拾起（拖拽）呈现面**——`liftFaceRadius` 自维护第二张半径表且已漂移三处，拾起玻璃框与真实面不同心，其中正含用户点名的图文/混排两卡。根治 = 建立 `Radius` 派生机制（令牌单源 + `concentric`/`lift` 派生函数），拾起面改为与呈现分支同判据的状态派生，全仓卡面/裁切半径收口到同一入口。verify 新增 [21] 组九项断言、本机自跑全绿（全脚本仅剩 ipa 陈旧/产物语言包两项构建产物检查，待组版构建自解）。

## 一、全量圆角账（编辑器内块面）

同心口径：内半径 = 外半径 − inset；inset = 0（出血贴边）时内面不另给半径、由外层裁切成形。Web 源为 rust/apps/web/styles（tokens.css 半径阶梯、editor.css 逐规则）。

| 面 | 外半径 | 内层元素 / inset | 内半径（现值=应值） | Web 源 | 判定 |
|---|---|---|---|---|---|
| imgTextCard 卡面 | 22 | 顶图出血 / 0 | 直角，卡面裁外角 | `.img-text-card` radius-22 + overflow hidden；`.itc-img-wrap` 无半径 | ✓ 配 |
| imageTextRow 卡面 | 22 | 左图出血（flex 50%）/ 0 | 直角，卡面裁外角 | `.img-text-row` radius-22；`.itr-img` 无半径 | ✓ 配 |
| image 块图面 | 22 | —（图本体即面） | clip 22 | `.atomic[data-type=image] > img` radius-22（1405 行，覆盖通用 img 10） | ✓ 配 |
| gallery 格网 | 22 | 瓦 22 / 间距 4 | 瓦与格网同值 22 | `.gallery-grid` 22、`.gallery-grid img` 22 | ✓ 配（Web 自身即同值，非同心递减） |
| video 面 | 22（原生自定） | — | clip 22 | Web `.blk-media` 无 radius 规则——无 Web 口径，原生自定 22 与图片面同阶 | ✓ 自洽（标注：无 Web 源） |
| link-card ready/error/skeleton | 32 | 封面出血 / 0 | 直角，卡面裁外角 | `.link-card-block/err/skeleton` radius-32；`.lkc-cover img` radius 0 显式 | ✓ 配 |
| musicCard ready/error/skeleton | 32 | 同 link-card（共用 CardBlockView） | 同上 | 同上（`.music-*` ready 态同卡） | ✓ 配 |
| musicCard urlPill / 输入丸 | 999 胶囊 | — | contentCard/glassControl 999 | `.music-pill/.music-input-pill` radius-999 | ✓ 配 |
| musicCard 带 fileId | 附件行面（见下） | — | — | CardBlockView 首分支 fileRow = AttachmentRow | ✓ 配 |
| attachment 单图 | 32 | 图本体 clip 32 | 32 | `.atomic.attachment img` radius-32 | ✓ 配 |
| attachment 文件行 | 常态 32 / 宽屏 22 | — | contentCard 同值 | `.attachment-file` radius-32；宽屏 22 为原生既有口径（见存疑项 S1） | ✓ 配（S1 标注） |
| quote 行面 | 10 | 左条 1.5（微装饰） | 底/描边 10 | `.blk-quote` radius-10 | ✓ 配 |
| callout 行面 | 12 | — | 底/描边 12 | `.callout` radius-12 | ✓ 配 |
| codeBlock 行面 | 12 | — | 底/描边 12 | `pre` radius-12 | ✓ 配 |
| MD 预览 Code/Callout/Table | 12 | — | 底/描边/裁 12 | editor.css pre 12 / callout 12 / table 框同阶 | ✓ 配 |
| MD 预览 Quote | 10 | 左条 1.5 | 10 | blockquote 10 | ✓ 配 |
| MD 图片 | 10 | — | clip 10 | `.markdown-render img` radius-10 | ✓ 配 |
| 公式块（mathBlock/MdMathView） | 无面 | — | — | `.math-block` 无 radius | ✓ 配 |
| 卡编辑描边（overlay） | 图文 22 / 余 32 | 外扩 3 的轮廓，非嵌套面 | 同左 | `.card-editing` 通用 32 + 图文两型显式改 22（editor.css:1345–1349） | ✓ 配（Web 自身两档规则，原样承接） |

### 拾起面（本批唯一不配集中区，已根治）

拾起玻璃框口径（Web 定案）：框半径 = 面半径 + LIFT_INSET 4、等距外扩。旧 `liftFaceRadius` 独立维护一张表，与真实面脱节：

| 块型 | 真实面 | 旧拾起面 → 框 | 应值 → 框 | 形态 |
|---|---|---|---|---|
| imgTextCard / imageTextRow | 22 | **32 → 36** | 22 → 26 | 框角过圆、与卡角不同心（**用户点名两卡在此成立**） |
| attachment 文件行常态 | 32 | **22 → 26** | 32 → 36 | 框角内切、玻璃框在卡角内侧露边 |
| attachment 文件行宽屏 | 22 | 22 → 26 | 22 → 26 | 偶合正确 |
| attachment 单图 | 32 | **22 → 26** | 32 → 36 | 同文件行常态 |
| musicCard urlPill / 输入丸 | 999 | **32 → 36** | 999 → 1003 | 胶囊面套方框，形态全错 |
| musicCard ready/error/loading | 32 | 32 → 36 | 32 → 36 | ✓ 偶合正确 |
| musicCard 带 fileId | 附件行面 | **32 → 36** | 随附件行（常态 36 / 宽屏 26） | 宽屏时错 |
| link-card | 32 | 32 → 36 | 32 → 36 | ✓ |
| video / image 有图（子视图 LiftFrame 22）/ gallery（子视图 22）/ quote 10 / callout·code 12 | — | 与面一致 | 同左 | ✓ |

不配形态分类：① 框半径大于面（过圆外凸）——图文/混排；② 框半径小于面（内切露边）——附件常态；③ 面形态类别错判（胶囊当方卡）——音乐丸态；④ 状态未分流（一型多面恒一值）——附件、音乐。三者同根：**第二张手写表与呈现分支判据脱节**。

## 二、编辑器外同类面（在账、处置范围标注）

| 面 | 半径 | 嵌套关系 | Web 源 | 处置 |
|---|---|---|---|---|
| 首页行卡 memoRow | glassCard 32 | 封面出血、卡裁外角 | base.css `.list-item` 32 / `.img-card` 32 / `.img-cover` 上两角 32 | ✓ 已配；默认值已收口 Radius.cardL |
| 首页方卡（网格） | 26 | 封面出血、卡裁；幽灵叠卡为缩放副本（与 Web transform 同行为） | `.img-card` 网格变体 26 | ✓ 已配；本批收口 Radius.grid（主卡/幽灵×4/图卡/裁切共 8 处） |
| 标题胶囊 | 33 | — | `--radius-33`（高 66） | ✓ 已配；收口 Radius.titleCapsule |
| 图片页 | 无圆角（整页图） | — | 原生独立图片页、无 Web 对应面 | 不处置（无面） |
| 菜单/面板浮层 | overlayCard 22、行 14/17、kbd 4、shortcut 6、link 输入 10 | 面内行按下态非嵌套面 | editor.css slash-panel 22 等 | J2 刚落的地界，本批不碰（值已对齐） |
| 设置卡族 | glassCard 28/32/30/20 等单面 | 无嵌套圆角面（SetRow 按下态 radius 0 为既有审计口径） | panels.css backup-hero 30 / backup-card 28 等 | 设置区为 0.9.51 地界，本批不碰（逐项已在批 E/天气批对齐） |
| 救援页 glassCard 20/28 | MomentRescue.swift 自有面 | — | 原生自救面、无 Web 对应 | 不处置（救援文件禁区） |
| 桥设置页 glassCard 28 | MomentBridgeSettings.swift | — | 原生面 | 不处置（桥地界） |
| Diag 页卡 28 / 终端卡 28 | 并列姊妹卡、非嵌套 | — | panels.css `.diag-body` 28 | ✓ 已配，不处置 |
| 开屏图标 clip 20 continuous | 原生自有面 | — | 无 Web 对应 | 不处置 |

存疑项（账内标注、本批未擅改）：
- **S1**：AttachmentRow 宽屏半径 22 缺 Web 实据——editor.css `.attachment-file` 恒 32、spread 段只取消 image/gallery 的 36 内缩、未改附件半径。22 为原生既有口径（注释自称 spread 口径）。本批按「面半径单源」处理：行面与拾起面共用同一派生（wide ? cardS : cardL），数值未动；是否回归 Web 32 待主线/用户裁断。
- **S2**：Web 级联下 `.itc-img-wrap img` / `.itr-img img` 未显式归零半径，会继承 `.editor-body img` 的 radius-10 与 margin（疑似 Web 侧残留——对照 `.lkc-cover img` 有显式 radius 0）。原生出血直角 + 卡裁外角为同心正形（inset 0 → 内面即外半径），与卡片 overflow hidden 的设计意图一致，本批保留原生形态、不回退到 10。
- **S3**：卡编辑描边对 gallery/video/image 沿用 Web 通用 32（面 22）——Web 自身即如此（仅图文两型有显式改 22 的覆盖规则），属轮廓光晕（外扩 3、非嵌套面），原样承接。

## 三、派生机制设计与落点

落点：`MomentApp.swift`，`enum T` 之后、卡片修饰器之前，新增 `enum Radius`（约 12835 行区段）：

- **令牌表（唯一入口）**：`cardS = 22`（图文/混排/gallery/图片/视频/附件宽屏）、`cardL = 32`（内容卡/附件常态/玻璃卡默认）、`grid = 26`（首页方卡）、`quote = 10`、`mdImage = 10`、`block = 12`、`pill = 999`、`titleCapsule = 33`、`liftInset = 4`。每值注释标注 Web 令牌名与适用面，与 tokens.css `--radius-*` 逐值同源。
- **同心派生**：`Radius.concentric(outer:inset:) = max(outer − inset, 0)`；`Radius.lift(face:) = concentric(outer: face, inset: −liftInset)`（拾起框 = 面外扩一圈的逆运算）。`LiftFrame` 改走 `Radius.lift` + `.padding(−Radius.liftInset)`，删除写死 `+4/−4`。
- **拾起面状态派生**：`liftFaceRadius` 全改令牌直取（quote/callout/code/imgText/video/image/gallery），多面块型走两个与呈现分支**同判据**的 helper：
  - `musicLiftFace`：fileId → 附件面；status==input → pill（BlockRow 分发）；loading → cardL；error 且 url 非空 → cardL；meta.title 非空 → cardL；url 非空 → pill（urlPill）；余 → 0（EmptyView 无面）。分支序与 CardBlockView body 逐条对应。
  - `attachmentLiftFace`：`node.image && files.count == 1` → cardL（files 计数口径与 AttachmentBlockView.files 一致：items 中带 fileId 者计数、无 items 时 attrs.fileId 兜底一件；image 标记读 node 顶层——落码中曾误读 attrs 层、已按源码更正）；余 → `editor.columnsActive ? cardS : cardL`（wide 与 AttachmentRow 同源）。
  - link-card 带 fileId 时同走 attachmentLiftFace（CardBlockView 首分支 fileRow 对两型同理）。
- **修饰器默认值单源**：GlassCard/ContentCard struct 默认与 View 扩展默认 → Radius.cardL；OverlayCard 与扩展默认 → Radius.cardS。

## 四、写死值清零清单

已清零（改走 Radius，本批共 30+ 处，数值逐项与原值相等、行为等价）：
- 卡面：ImgTextBlockView 两面（22→cardS）、CardBlockView 四面（32→cardL）+ urlPill（999→pill）、MusicPillView 输入丸（999→pill）、AttachmentRow 三元（22/32→cardS/cardL）。
- 裁切：ImageBlockView 图 clip + LiftFrame（22→cardS）、GalleryBlockView 瓦/瓦 clip/格网 clip/LiftFrame（22→cardS ×4）、VideoBlockView 播放面 + 占位面（22→cardS ×2）、AttachmentBlockView 单图 clip（32→cardL）、MdImageView 图 clip + 占位（10→mdImage ×2）。
- 行面：BlockRow 背景/描边三元（10/12→quote/block ×2）、卡编辑描边三元（22/32→cardS/cardL）。
- MD 面：MdBlockView Code（12→block ×2）、Quote（10→quote ×2）、Table（12→block ×3）、MdCalloutView（12→block ×2）。
- 首页：方卡主卡/正文卡/图卡 glassCard（26→grid ×3）、幽灵叠卡（26→grid ×4）、图卡 clipShape（26→grid）。
- 基础设施：三修饰器 struct 默认 + 三扩展默认、LiftFrame 外扩、标题胶囊（33→titleCapsule）。

评估后保留字面（附理由）：
- 微装饰（非嵌套面、单元素）：骨架条 6（CardBlockView skeleton）、引用左条 1.5 ×2、eb-clear 命中形 6、ErrBadge 徽章 18（36 盒半徑、Web `.eb-badge` 18）——Web 亦为一次性令牌值，无同心关系可派生。
- J2 地界：浮层 overlayCard(radius: 22) 调用点 ×6、斜杠行 14、kbd 4、shortcut 6、link 输入 10、菜单行 RowPressStyle 17/14、徽章面板 overlayCard 20——值已由 J2 对齐，本批不碰（扩展默认值已单源化，后续批可顺手收口调用点）。
- 设置区：glassCard 28/30/32/20 各调用点——0.9.51 地界，值已逐项审计对齐。
- 按钮类 glassControl(radius: 999) 调用点 ×9（页眉/诊断/首页等胶囊钮）：值即 pill 语义，但属各已审计家族的按钮面，非卡片嵌套面，未在本批越界收口。
- RowPressStyle 默认 12、CardPressStyle 等按下态样式默认：按下态背景、非面半径。
- 原生自有面：开屏图标 20 continuous、救援/桥文件内半径（禁区文件未动）。

## 五、断言（verify [21]，本机自跑全绿）

verify_ios.sh 新增 [21] 组 R21-1…R21-9：令牌表与 concentric/lift 本体在位；LiftFrame 走派生且旧 `faceRadius + 4` 零残留；liftFaceRadius 段内无写死 return 数值、图文走 cardS、音乐/附件走 helper；两 helper 关键分支（input→pill、单图→cardL）在位；卡面 contentCard 写死（22/32/999）全文件零残留且令牌计数达标；gallery/图片/视频段裁切写死 22 零残留、附件图/MD 图走令牌；修饰器默认值写死零残留；首页 26 写死零残留且 Radius.grid 覆盖 ≥6 处；行面/描边/附件行三元走令牌。

连带同步：[7] 组拾起呈现前提断言的 `padding(-4)` 字面随单源化改为 `padding(-Radius.liftInset)`（前提不变、口径同步，注释已注明）。

本机自跑结果：[21] 九项全绿、[7] 同步项绿；全脚本仅剩「ipa 陈旧」「产物语言包与 Web 源不一致」两项构建产物检查（源码已改未重建的必然态，组版在 tree 构建后自解）。本批未做 Swift 编译级自检（本机无 swiftc，工具链在 tree）——组版冒烟（smoke 主线在 tree 跑）时须一并验证；落码均为值等价的令牌替换 + 一处 switch 改写（字典读取口径逐项照抄 CardBlockView/AttachmentBlockView 原判据）。

## 六、边界与遗留

- 只动 MomentApp.swift 卡片/圆角渲染段与 verify_ios.sh（[21] 新增 + [7] 一处同步）；未碰设置区、救援文件、FFI、浮层菜单区；未 bump（暂记 0.9.52，落版主线定）；未提交。
- 遗留裁断：S1（附件宽屏 22 的 Web 实据）建议主线裁断；S2/S3 为 Web 侧形态记录，不需动作。
