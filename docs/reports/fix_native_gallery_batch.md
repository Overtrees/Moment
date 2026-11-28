# 原生画廊批（fix_native_gallery_batch）

2026-11-28。分支 `fix/native-gallery-batch`，基线 ac79ed7（0.9.67）。
工单四项：审计报告落盘、有图态添加缺口、卡内几何改判（用户裁定）、
图文卡图区接缝角（仅原生）。验证口径：本机落码 + verify_ios.sh 全量
自检；全量冒烟（tree 构建 + 桥景实跑）归 0.9.68 组版，本批未跑。

## 提交清单

| 笔 | 内容 |
|---|---|
| 760f9aa | 审计报告 audit_native_gallery_add.md 入 docs/reports/（内容不改） |
| 26ee2d1 | 添加瓦 + 新景 gallery_add_append + B25-11/[77] + 矩阵 EDT-63 |
| 9dc13b8 | 卡内几何改判（36 内缩退役 + MediaGeom.gap 单一令牌） |
| 8575e11 | 接缝角逐点位锁 GA77-4 |
| （本报告笔） | 本报告 |

## 1. 报告落盘

pending 的 audit_native_gallery_add.md 原样移入 docs/reports/，
pending 原件删除（git mv 等价：同内容增删对）。

## 2. 添加缺口（审计 §5 落码）

定案复述（审计 proven）：有图态添加 machinery 完好（applyGalleryAdd
append + 落盘 + Diag），唯一触发点 `showGalleryAddPicker = true`
被空态分支门死——原版「添加只在空态」设计缺口被忠实移植，非断线。

落码（GalleryBlockView，呈现层单点、模型层零改动）：

- 新增单点派生 `editing`（`editor.cardEditBlockId == block.id`，
  与 galleryTile 既有编辑态判据同源，原局部量改用此属性）。
- 呈现门 `addTileShown = editing && !items.isEmpty`；计数派生
  `displayCount = items.count + (addTileShown ? 1 : 0)`。
- 添加瓦 `addTile`：ForEach 后 `if addTileShown` 渲染；高 366 与
  图瓦同高；角位走既有 `tileCorners(ix, displayCount)` 按位取角
  （添加瓦居末位、与图瓦同一套角规矩）；底色按瓦位奇偶在
  fillSubtle/fillSubtle2 交替（与图瓦加载底/空占位同族）；内容 =
  photo 图标 + 既有文案键 `media.gallery_add`（五语既有译文，
  与空态占位同键）；点按与空态**同一对赋值**
  （`galleryPickBlockId = block.id` + `showGalleryAddPicker = true`），
  下游 CardEditSheets 消费、putAttachment、applyGalleryAdd 全程
  零改动。
- 图瓦 clip 同步改走 displayCount：编辑态下末图瓦的右下角由圆改
  直（角位让给添加瓦），与空态双瓦同一套按位规矩，非新发明。

新桥景 `gallery_add_append`（自检矩阵 EDT-63，fixture.media）：
夹具画廊 3 项 → 场景内先经模型口径裁到 1 项（applyGalleryRemove
×2，模拟「已有图」起点）→ putAttachment 两枚新图（品红/青，
att-uitest-gx/gy）→ applyGalleryAdd 追加（与 sheet 消费同一函数、
同参形态）→ 断言 items 1→3 且尾附序 [ga, gx, gy]、Diag
`EDIT gallery add` 行在位、新瓦出图（像素探针轮询）→ notesGet
落盘回读同序 → 关开重进仍在。夹具/附件在快照-复原信封内自洁。
断言名：trimmed_to_one / fixture_pngs_put / items_1_to_3_appended /
add_diag_logged / appended_tiles_render / persisted_items /
reenter_items。

注记（装机桥自办前置）：连接器 custom.moment-bridge 的
CONNECTOR.md 场景目录需补 `gallery_add_append` 名（与既有 18 景
同列），否则桥侧目录与 B25-11 名集对不上。

## 3. 卡内几何改判（用户 2026-11-28 裁定）

### 占位前提清单（落码前）

- 行盒宽 W = 栏宽（BlockRow 行盒）；卡面 = 行盒（S23-2 同源口径）。
- 改前：image/gallery 块行带 `.padding(.horizontal, columnsActive
  ? 0 : 36)`——单栏态面宽 W−72、居中内缩；双栏态 0。
- 画廊格网 = LazyVGrid 双 flexible 列 + spacing gridGap；瓦宽 =
  （面宽 − gap）/2 由 flexible 均分自动成立。

### 量测三项（源码派生口径，pt；设备像素复核归 0.9.68 装机）

| 量 | 改前（单栏） | 改前（双栏） | 改后（两态同） | 目标 |
|---|---|---|---|---|
| 卡内左缘 → 首瓦左缘 | 36 | 0 | 0 | 0 |
| 末瓦右缘 → 卡内右缘 | 36 | 0 | 0 | 0 |
| 单瓦宽 | (W−72−4)/2 = (W−76)/2 | (W−4)/2 | (W−4)/2 | (W−4)/2 |
| 单体图片卡图面宽 | W−72 | W | W | W（留白与画廊对齐 = 0） |

### 落码

- BlockRow 两处内缩整体删除（image / gallery 分支），旧双栏归零
  分支随内缩消解；分支注释改判登记。
- 缝单一令牌：新增 `MediaGeom.gap = 4`（与 Web 线 `--media-gap: 4px`
  同值同规）；GalleryBlockView.gridGap 改恒派生该令牌——旧两态
  派生（有图 4 / 空态 6，对 Web 两选择器的逐值移植）随改判退役，
  两态同缝。
- 历史注释处置：rowBackground 的 0.9.50 定案段（内缩 36pt 前提）
  加改判注、不删史；探针 cardAlignment 判读基线与前提④注释同步
  改判（旧单栏 ≈36 对称期望式作废、两态同为 ≈0）。

### 同型普查（BlockRow 全分支 + 各卡视图）

| 卡 | 卡缘侧留白现状 | 结论 |
|---|---|---|
| gallery | 36 对称内缩（块行） | 本批退役 |
| image（单体） | 36 对称内缩（块行） | 本批退役（用户点名对齐） |
| video | 块行无内缩、视图内无横向 padding | 已满宽、无病 |
| imgTextCard / imageTextRow | 无（仅内容内边距 12/16） | 已满宽、无病 |
| linkCard / musicCard | 无（封面贴边、内容内边距为排版内边距） | 已满宽、无病 |
| attachment | 无（行内边距 12 为内容排版） | 已满宽、无病 |
| text / todo / quote / tip / divider / code / md / embed | 块行均无横向 padding（grep 普查：BlockRow 内 `padding(.horizontal,` 改前恰 2 处、即上两行） | 无病 |

## 4. 图文卡图区接缝角（仅原生）

### 普查（源码面，逐子面）

| 复合卡 | 子面 | 角位 | 判定 |
|---|---|---|---|
| imgTextCard（上下） | 已填图 / 加载底 / 空占位 | tl+tr = cardS、接缝 bl/br = 0 | 合规 |
| imageTextRow（左右） | 已填图 / 加载底 / 空占位 | tl+bl = cardS、接缝 tr/br = 0 | 合规 |
| linkCard / musicCard readyCard | 封面 / 骨架底 | tl+tr = cardL、接缝 = 0 | 合规 |
| gallery 瓦 | tileCorners 按位 | 仅网格外角圆、瓦间角直 | 合规 |
| 首页图卡 | 封面 | tl+tr = grid | 合规 |
| image / video / attachment | 独立整面 | 无接缝（整面圆角即卡角） | 不适用 |

源码面结论：**全部合规、无源码可改**——接缝角在 0.9.66 出货源
（e05a091）与现行源逐字一致（ImgTextBlockView 仅 T.bg 取色差）。

### 设备残余（unknown，登记复拍）

用户 15:48 原生截图（图文卡空占位态）像素量测：占位灰区底边
平直段止于 y=1261px、两底角上扬 ≈19px（左）/ ≈36px（右），
有效半径 ≈10–12pt（顶角 ≈22pt = cardS）。源码 bl/br = 0 不产生
此半径，成因与矩阵 §7 既载「复合卡内角像素机理曾判 unknown、
只能同位复拍」同型。**登记 0.9.68 装机同位复拍**（同卡同态同位
截图后像素复量）；本批不冒充已修。

### 落码（断言侧）

S23-4 原为 CornerRect 计数锁（≥6/≥2）——对单点角位变更无感知
（负对照 NC-4 实证：接缝角加圆后计数仍 6、S23-4 保持绿）。
本批在 [77] 新增 GA77-4 逐点位普查：各复合卡段 CornerRect 角位
多重集与期望恒等（图文 (tl,tr)×3 + (tl,bl)×3、链接音乐
(tl,tr cardL)×2、gallery tileCorners 四条件式、首页图区 ×1），
任一子面角位漂移即红。

## 5. 断言与负对照

新增/改判锁：B25-11 名集 18→19；[77] GA77-1（添加瓦接线普查：
呈现门/计数派生/同对赋值全文件恰 2/角位 displayCount/旧字面零
残留）、GA77-2（add 消费单点 + 景与矩阵在位）、GA77-2b（景体
同路：putAttachment + applyGalleryAdd + 落盘回读 + 重进断言）、
GA77-3（MediaGeom 令牌单源 + `? 0 : 36` 零残留）、GA77-4（接缝
角逐点位）；S23-2 改锁零内缩、S23-5 改锁令牌派生（两处均保持
PD73-1 棘轮分类行数不变）；366 瓦高锁 2→3（DT36-7 白名单先行
在 impl_dt_layout_resilience 更新、添加瓦入册）；S23-4 gallery
角位字面随 displayCount 改判。

负对照（突变 → 恰红，2026-11-28 本机实测）：

| # | 突变 | 结果 |
|---|---|---|
| NC-1 | 添加瓦 setter 改 false | GA77-1 红（setter=1） |
| NC-2 | 图瓦 clip 回退 items.count | GA77-1 红（clip/remnant） |
| NC-3 | 呈现门去掉 editing 条件 | GA77-1 红（gate） |
| NC-4 | 图文空占位接缝角加 bl 圆角 | GA77-4 红；S23-4 计数不变保持绿（升级价值实证） |
| NC-5 | gridGap 回退两态派生 | S23-5 / GA77-3 红 |
| NC-6 | 目录条目改名 | B25-11 红（名集不等） |

## 6. 验证结果

本机 verify_ios.sh 全量：源码面断言全绿（含 [77] 五条新锁）；
红集与基线 ac79ed7 在本机直跑的红集**逐字一致**（6 条产物红：
ipa/Assets.car/开屏 JSON ×2/语言包/SG49-4——均为本机无构建
产物所致、tree 构建自解，非本批引入）。tree 冒烟与桥景实跑
（gallery_add_append 首跑、EDT-63）归 0.9.68 组版批。
