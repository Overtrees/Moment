# 补丁债偿还批二·分类单点（repay_patch_debt_2）

日期：2026-11-28。基线：HEAD `e65e396`（批一已办结）。工单：docs/reports/audit_patch_debt.md §九偿还序第 2 批（分类单点批），只执行该批两项：A-3（块型名单三处不一致）、A-2（卡片呈现判别整链复制）。逐项一笔、笔笔可独立回滚。

**办结：2/2 项。** 总册两项引文与代码现状核对：形态与危害均属实；行号已随批一漂移（A-3 三表实位 = EditorModel 文末集函数、init 普查局部表、materializeMdTrails 局部表；A-2 拾起链实位 = BlockRow 内 liftFaceRadius 及两份拾起面派生）。回写注记与对账结论见各节（不改总册结论口径）。

---

## A-3 块型分类收口 BlockKind 表 —— 已清（`40a248d`）

- **改动单点**：新文件 `MomentBlockKind.swift` 立分类表 `BlockKind`：全 18 块型一型一行、两分类维（trailEnd / trailAfterNext）作列，三派生子集（trailEndAtomic / trailAfterAtomic / censusKnown）由行过滤派生。三消费方收口：文末尾随（init 末块判 + scheduleSave 落盘路径）与普查 atomic 计数改经 `BlockKind.isTrailEndAtomic`；MD 尾随物化（materializeMdTrails，落盘路径）改经 `BlockKind.trailAfterAtomic`；普查 unknown 过滤改经 `BlockKind.censusKnown`。旧三处字面表（文末集函数、atomicNext 局部表、censusKnown 局部表）整删、grep 零残留。
- **三表逐成员对账（本批核心工作，结论已写回分类表头注）**：
  - **后继集 = Web 忠实移植（proven）**：与 Web `trail_after`（rust/apps/web/src/editor/model.rs 的 matches! 名单）逐字同集（image/gallery/imgTextCard/imageTextRow/attachment/link-card/musicCard/embedCard/divider）。其与文末集的出入（无 video、有 embedCard）在 Web 侧两集之间同样存在——是两语义刻意不同，非原生漂移。
  - **文末集与 Web TRAIL_END_ATOMIC 三成员出入（+video +divider −todo）**：该出入已经 `audit_markdown_full.md` 登记为已知低危差异（原生插入路径 trailingParagraph 覆盖主要场景、打开不补段有落焦热区兜底）。**本批只收口不改成员**——文末集成员直接决定打开存量备忘时的落盘文档结构，在偿债批内顺手改成员等于无立项地变更数据面行为；是否对齐 Web 须另行立项裁定（留账 3）。
  - **普查集取全宇宙（行为逐值等价 proven）**：unknown 过滤先以 isText/isList 短路、后查本集，故文本/列表型在集内与否对计数恒无影响；旧 11 成员表相对全宇宙的差集恰全为文本/列表型（其内的 callout 同为文本型、属惰性成员）。语义由此字面化为「已知 = 在分类表内」，他端未来新块型仍计 unknown。
- **行为等价依据**：三派生集与收口前三处字面表的有效成员逐集恒等（PD72-1 登记集即收口前字面表成员、独立写于断言内）；三消费点的调用形态、落盘路径（init 尾随补段 + scheduleSave、materializeMdTrails 插入 + scheduleSave、普查只读计数）逐项未动。
- **构建接线**：新文件照拆分例接入 build-app2.sh 全 31 遍（30 遍次级输入 + 自有 primary 遍）+ `blockkind.o` 链接行；遍数变化引发的精确计数锁六处随批改判并注沿革（B16-23 30→31、DT46-6 29→30、E47-8 30→31、X50-7 30→31、SB-2 30→31、PD71-4 30→31）。
- **断言**：PD72-1（分类表探针：MomentBlockKind.swift 与内嵌断言体以宿主 swiftc 编译运行，三派生集逐集与登记集恒等 + 行数/宇宙恒等 + 类型无重复 + 分叉成员 video/embedCard/todo 逐点验）、PD72-2（三字面表零残留 + 三消费点经派生）、PD72-3（构建接线 31 遍 + blockkind.o ×2）。**负对照实做**：scratch 副本翻转 video 行 trailEnd 标志 → 探针恰红（FAIL trailEnd set / FAIL video trailEnd，exit 1）；复原转绿。

## A-2 卡片面型收口 CardFace 派生 —— 已清（`0cfd078`）

- **改动单点**：`MomentBlockKind.swift` 增纯派生 `CardFace.derive`（输入结构体 CardFaceInput、输出十面型枚举、各面型带半径令牌符号量）。判别序 = **呈现有效序**（行分发先于卡视图本体）：musicCard+input → fileId 文件行 → 音乐 loading 骨架 → 音乐 error 卡（须有 URL）→ 有标题内容卡 → 链接无标题 err 卡 → 音乐 URL 胶囊 → 音乐空态胶囊；attachment 独立序：单图（node.image 且恰一文件）→ 空态纯文本（零文件）→ 文件行。四方共消费同一 `BlockState.cardFace` 值（适配按呈现口径喂字段：status/url/title 取 node 顶层与 meta、fileCount 与 AttachmentBlockView.files 同口径）：
  - **呈现分发**（BlockRow）：musicCard input 支改以 `cardFace == .inputPill` 判；
  - **呈现本体**（CardBlockView）：body 的 if 链改面型 switch（八支一一对应、子视图全保留，附件专属两面型为不可达兜底）；AttachmentBlockView 单图支改以 `cardFace == .singleImage` 判、本地单图私有判别整删；
  - **拾起面**（BlockRow.liftFaceRadius）：音乐/链接/附件三型改经 cardLiftRadius 把面型半径令牌绑 Radius 数值（文件行令牌经 Radius.attachmentFile 与 AttachmentRow 行面同派生），旧两份拾起面复制判别整删（$SRC grep 零残留；Radius.attachmentFile 头注的陈旧引用同步更正）。
- **逐格行为等价核对**：呈现行为逐格不变（派生序即原呈现有效序、子视图与半径令牌全保留）。拾起面逐格核对后**坐实两处旧拾起漂移、按呈现真源对齐**（总册「呈现一改拾起静默漂移」的存量实证）：
  1. **音乐尾支**（无 fileId/标题/URL、status 非 input/loading，含 error 而 URL 为空者）：呈现为空态胶囊（pill 面），旧拾起派生返回 0（无面）——拾起框与真面不符；新派生归 .emptyPill（pill）。
  2. **序位两格**：musicCard 的 input 与 fileId 并存时旧拾起先判 fileId、呈现由行分发先送 input 胶囊；fileId 卡（音乐/链接）挂 image 旗且恰一文件时旧拾起套用附件单图判给 cardL、呈现恒为文件行面。新派生从呈现序：input 先行、卡 fileId 恒 .fileRow。
  其余格口（音乐 loading/error+URL/ready/url 各支、链接 ready/err、附件单图/多文件/零文件）逐格同值；附件零文件（plainNote）拾起半径保守保留旧值（attachmentFile 令牌，与旧派生落点同值）。
- **断言**：PD72-4（面型表驱动：21 输入格口 + 10 面型半径令牌逐项与登记面型恒等，登记面型 = 收口前呈现有效序逐支真值、独立写于断言内）、PD72-5（四方共消费锁 + 适配恰 1 + 旧单图判别零残留）。**负对照实做两组**：scratch 副本交换 derive 内 input/fileId 序 → 恰红（FAIL music input beats fileId）；emptyPill 令牌 pill→cardL → 恰红（FAIL token emptyPill）。连带改判：R21-3（段内 helper 在位改锁 cardLiftRadius/半径令牌绑定）、R21-4（改判为派生单点 + 旧判别零残留，行为锁移交 PD72-4）、R21-9（单图字面句改锁 cardFace.radiusToken 段内绑定）、K22-5（改锁面型 switch 两支 + derive input 判据；段内 EmptyView 现为附件专属面型不可达兜底、注记在条）——四条机制不变量不变、沿革注记在各条注释。

---

## 总册条目状态更新清单

| 编号 | 旧状态 | 新状态 | 依据 |
|---|---|---|---|
| A-3 | 根治（待偿还） | **已清** | `40a248d` + PD72-1/2/3 |
| A-2 | 根治（待偿还） | **已清** | `0cfd078` + PD72-4/5 |

连带（非总册条目，属本批改判登记）：verify 计数锁六处随新文件遍数改判（B16-23 / DT46-6 / E47-8 / X50-7 / SB-2 / PD71-4）、机制锁四条随派生单点化改判（R21-3 / R21-4 / R21-9 / K22-5），机制不变量均不变、沿革在各条注释。本批未触及：§九.3 起的断言棘轮化批（C-6/C-7/C-8/C-11/C-13）、自救/桥/自检机制化批、Web 收口批、登记表批——计数锁的集合恒等化改造（C-6）仍在后续批次，本批计数改判只是随遍数的例行沿革。

## 验证（如实分账）

- 本机 verify_ios.sh 全量：**720 ✓ / 2 ✗**——2 红均为产物陈旧（ipa 早于源码、产物语言包未重建），本机无构建所致，下版 tree 组版自清；源码面断言全绿（基线批一为 715 ✓，本批 +5 条 PD72 全绿、改判 10 条保持绿）。
- cargo test --workspace：**239 全过**（本批未动 Rust 面，与基线一致）。
- Swift 语法：两改动文件（MomentBlockKind / MomentApp）本机 swiftc -parse 全过；MomentBlockKind 另经 PD72-1/PD72-4 两探针以宿主 swiftc **真编译运行**全过。**类型级编译门未过**——MomentApp 侧改动（cardFace 适配、面型 switch、拾起委托）留下一版 tree 组版冒烟（smoke_ios.sh），本报告不声称已编译。

## 留账

1. **Swift 编译门**：下一版组版在 tree 跑 smoke_ios.sh 全量（新文件 MomentBlockKind.swift 须入 tree 同步名单——组版批的 push_small 名单制注意新增此文件，build-app2.sh 已全遍登记）。
2. **对应景复跑**：装机后经桥自办复跑——拖拽景 drag_pickup_statemachine（拾起框与卡面同心：音乐各态/附件单图与文件行/lift_gaps 面读数对读）、卡片点按景 image_page_open_cards（附件单图支与图文卡路由未受面型收口影响）、打开存量备忘的尾随物化（文末原子块/预览段尾随补段形态与旧版逐篇对读，落盘结构不变）。
3. **文末集对齐 Web 待裁**：trailEnd 与 TRAIL_END_ATOMIC 的三成员出入（+video +divider −todo）维持现状（audit_markdown_full 已登记低危）；若日后立项对齐，改动只在 BlockKind 表三行标志 + PD72-1 登记集，消费方零改动——此正为本批收口的收益，登记备查。
4. 真机终判点：音乐卡空态胶囊拾起框同心（尾支漂移修复后）、input 胶囊拾起框形态归用户装机目检（矩阵 §7 人工保留面口径）。
