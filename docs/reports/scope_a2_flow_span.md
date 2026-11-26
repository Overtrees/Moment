# A-2 流式跨栏批 范围核定（只读核定，不落码）

基线：HEAD `bb5fa03`。口径以 `audit_independent_columns.md` 与已定判断矩阵为准：独立×宽屏不跨栏（已一致）、独立×窄屏单栏内容宽、**流式×宽屏整幅跨栏**（跨栏块集 = 原版 span 名单：image/gallery/imgTextCard/imageTextRow/musicCard/带图附件；分段只看文档序与块类型、与 layout 锚正交、不得改写锚）；G-2 随本批翻转；G-3 有意偏离不动。

行号均为现行文件（editor.rs 经批 5/6/批 6 余项后已增长，下述行号按本次读取实证）。

---

## 一、流式×宽屏跨栏：现状与缺口

### 1. 现状（proven）

- 宽屏渲染恒为两个物理 `.editor-column` 容器：editor.rs:3567-3660，`show_cols`（=wide）时 `.editor-body` 内只有左/右两个 `.editor-column` div，块按单一 `boundary` 切成 runs_left（`0..boundary`）/ runs_right（`boundary..len`）渲染（editor.rs:2975-3023，flow_runs 按 range 分别成流）。
- 模式只切换 `.editor-body` 的 class：`two_col`（twopane && wide）→ `is-independent-scroll`，否则 `is-flow-columns`（editor.rs:3569）。流式与独立**共用同一成员分界**（锚优先、无锚规范估高，column_boundary，editor.rs:2977-2987），这是既有设计（代码注释 editor.rs:2969-2974 明示：为防分界漂移与两模式成员不一致而弃 CSS 多列）。
- 流式 CSS（styles/editor.css:1146-1197）：`.is-flow-columns` 为两列 grid（1fr/1fr、gap clamp(28px,3.2vw,52px)），栏内块 `max-width:100%` 钳制；无任何 span 机制。**流式×宽屏下六类名单块全部栏内宽，无一跨栏**（与审计 G-1/W-2 量化一致：图库栏内方图 vs 原版整幅 666×366）。

### 2. 既有 column-span 规则是死规则（proven）

- styles/editor.css:739-749、783-787 有从原版逐字移植的 `column-span: all`（image/gallery/imgTextCard/imageTextRow/[data-type=musicCard]、.blk-wrap.blk-music/.music-input-pill、带图附件 `:has(> img)`），位于宽屏媒体查询（:699 起）内、选择器瞄 `.editor-spread > .editor-body > …` 直子。
- 在现行宽屏 DOM 中块是 `.editor-column` 的子（孙辈），且两模式段（:1052、:1146）都把 `.editor-body` 设为 `column-count:1` + grid——这批 span 规则**永不命中、永不生效**，只剩文档意图。落码时须处理（见决策点 D3），不能指望「改回多列即可复活」：多列回归与既定确定性分界口径冲突（审计 G-1 已记录弃用原因），本批不走多列路线。

### 3. 跨栏块集 → Rust 块型/DOM 对照（proven）

| 原版 span 名单 | Rust block_type | 渲染形态（blocks.rs） | 跨栏判定落点 |
|---|---|---|---|
| image | `image` | .blk-wrap > .atomic[data-type=image]（blocks.rs:538-556） | block_type |
| gallery | `gallery` | .blk-wrap > .atomic[data-type=gallery]（blocks.rs:574-589）；内 .gallery-grid 为 repeat(2,1fr)（editor.css:1425），宽随容器自动放大 | block_type |
| imgTextCard | `imgTextCard` | .blk-wrap 卡片（blocks.rs:909） | block_type |
| imageTextRow | `imageTextRow` | .blk-wrap 卡片（blocks.rs:946） | block_type |
| musicCard | `musicCard` | .blk-wrap.blk-music（editor.rs:6382） | block_type |
| 带图附件 | `attachment` 且 `extra["image"]==true` 且有 fileId | .blk-wrap > .atomic.attachment（blocks.rs:769-783，extra_bool(&node,"image")）；无图附件为 .attachment-file 不跨 | block_type + extra 标志（与 columns.rs:24-35 估高口径同一标志） |

不在名单内、明确不跨（proven，原版名单无此项）：video（.atomic[data-type=video]）、link-card/embedCard、普通附件、一切文本类块。列表组（FlowRun::ListGroup）成员恒为段落类（flow_runs，editor.rs:775-806），永不含跨栏块；跨栏块天然打断列表组，与现行「组只在 range 内相邻成组」语义自洽。

### 4. 缺口本质（proven + 设计推论）

`.editor-column` 的子元素在 CSS 上不可能跨出栏容器——纯 CSS 改动无解，必须改渲染分段：流式×宽屏时把文档按跨栏块切成段，段间跨栏块以 `.editor-body` 直子整幅渲染，段内非跨栏块仍走双栏容器。此即已定口径「分段只看文档序与块类型」的实现形。

---

## 二、落码设计（建议形，供派发）

### 笔结构总览

| 笔 | 内容 | 落点 |
|---|---|---|
| 笔 1 | G-2 翻转（独立小笔，先行） | editor.rs twopane 初值一处 |
| 笔 2 | 分段纯函数 + 单测（无渲染变化） | editor/columns.rs 新增 `flow_segments` |
| 笔 3 | 流式渲染分段化（DOM 重构） | editor.rs rsx 宽屏分支 + runs 计算 |
| 笔 4 | 流式 CSS 重构 + 跨栏规则 + 死规则清理 | styles/editor.css is-flow-columns 段 |
| 笔 5（条件） | 桥几何补修（仅探针坐实才动） | editor/bridge.rs canvasFocusRoute 等 |
| 笔 6 | 探针：新流式跨栏探针 + probe_twocol_matrix M1 改判据 + TESTING 登记 | probe_*.mjs、TESTING.md |

笔 3 与笔 4 功能上不可分（只改其一版面即坏），同链落码、各自成笔、各过编译级自检，box 探针在两笔齐后跑。

### 笔 2：分段纯函数（columns.rs）

- 新增 `flow_segments(doc: &[Node]) -> Vec<FlowSeg>`，`FlowSeg = Columns { left: Range<usize>, right: Range<usize> } | Span(usize)`：
  - 跨栏判定 `is_span_block(node)`：按上表（block_type 五类 + attachment 带图标志），与 est_block_height 的类型口径同源、建议同文件维护。
  - 扫描文档序：连续非跨栏块成段，段内以既有 `canonical_boundary(&doc[seg])` 切左右（规范估高、文档内容纯函数，与现 canonical 路径同机制，columns.rs:47-68 可直接对切片调用）；跨栏块各自成 Span 段；空段不产出（跨栏块在首/尾、连续跨栏块）。
- **段内切分口径 = 段内规范估高平衡，不用全局锚**（依据：已定口径「分段与 layout 锚正交」）。备选「锚与段求交」已排除（inferred，几何推论）：锚一侧的段会整段单栏（另一栏空置），文档呈左右锯齿，原版多列流与现行流式观感均无此形态。
- 随附 cargo 单测（纯函数、主机靶可跑）：无跨栏（单段、规范切分）、跨栏在首/尾、连续跨栏、单块段（canonical 对 len<2 全归左，columns.rs:48-50 既有语义）、attachment 标志开/关、空文档。
- **锚零接触（proven 可守）**：渲染分段不读不写 extra.layout；现行流式渲染读锚算 boundary 的路径（editor.rs:2977-2987）改为仅独立模式消费，落锚 effect（:1651-1704，`twopane && wide` 才触发）、关存写锚（:2493-2541）、开关写锚（:2647-2689）一概不动。

### 笔 3：渲染分段化（editor.rs）

- 现宽屏分支（:3567-3660）拆两路：`two_col`（独立）原样不动；流式（show_cols && !two_col）改渲染 `.editor-body.is-flow-columns` 的子序列：
  - `Columns` 段 → `div.editor-flow-seg` 包两个 `.editor-column`（保留 `data-editor-column="left"/"right"` 属性，探针与桥按属性/类名定位的口径不变），段内 runs 走既有 flow_runs 按 left/right range 各算一组（:3005-3023 的 PERF 纪律保持：只算会被消费的组）。
  - `Span(i)` 段 → 直接渲染该块的 EditorBlock（其 .blk-wrap 即 body 直子）。
- key 纪律：EditorBlock 现以 `{epoch}-{block.id}` 为 key 且在迭代内（:3585、:3610）——分段后仍须保持「迭代子节点 + 业务 id key」形态（运行时语义三坑之一，静态位置 key 惰性），段循环与段内块循环两层迭代都要带稳定 key（段 key 可用段首块 id）。
- 窄屏分支（:3642 起单栏）与独立分支逐字不动；`show-placeholder` 类拼接（:3570-3577）流式路保留等价判定。

### 笔 4：CSS（styles/editor.css）

- `.is-flow-columns` 本体（:1148-1160）：由 grid 改 block 容器（保留 column-count:1 / column-rule:none 的压制声明，防 :711 的 `column-count:2` 复活）；现挂在 body 上的居中分隔线背景（linear-gradient）移至 `.editor-flow-seg`——分隔线在跨栏块处中断，与原版多列 spanner 中断 column-rule 的呈现同构（inferred，原版未逐像素验）。
- 新增 `.editor-flow-seg`：grid 两列、gap 与现行同值 clamp(28px,3.2vw,52px)；现 `.is-flow-columns .editor-column > …` 系列规则（:1161-1197：子块钳制、防断裂、image/gallery margin、musicCard 宽）改挂 `.is-flow-columns .editor-flow-seg > .editor-column` 作用域（或等价改写），逐条搬、不增减语义。
- 新增跨栏规则：`.is-flow-columns > .blk-wrap` 整幅（width:100%、min-width:0）；image/gallery margin 与宽屏现行口径对齐（8px 0，参照 :777-780 的直子规则值）；musicCard 整幅宽；带图附件 .atomic.attachment 整幅。gallery 内 grid 为 1fr 自适应（:1425），整幅后 tile 自动变宽、img 高 366px 固定与原版整幅口径一致（W-2 的 366），无需改 gallery 内部规则（inferred，待探针 F1/F2 量测坐实）。
- 死规则处置（决策点 D3）：:739-749 与 :783-787 的 span 声明在新 DOM 下仍不命中（跨栏块直子是 .blk-wrap、非 .atomic 本体）——建议同笔删除该批 span 声明、防二层死代码；防断裂（break-inside）声明不在此列、保留。

### 与既有跨栏拖拽的交互

- **数据层：零交互（proven）**。分段是渲染期纯派生，不落盘、不改 doc；op_move_block（editor.rs:3901-4009）按文档序重排 + 锚存在时按重排前分界块数重写锚（:3952-3999，mode 保留、缺失时默认 "independent"——与 G-2 翻转同向，见三·2），与渲染形态无关，流式分段不碰此路径。
- **桥几何层：结构可容（proven）、三处风险待探针坐实（inferred）**：
  - allUnits/unitOf（bridge.rs:2079-2110）：collect 按子元素走查、遇 .editor-column 递归、其余带 data-bid 的直子即单元——多段多栏 + body 直子跨栏块的形态天然在容忍内，文档序即走查序（proven，读码）。
  - unitMetasExt 分组（bridge.rs:2200-2247）：按 `closest('.editor-column')` 分组、跨栏块 colEl=null 归 body 组；body 组 stackTop 取 body 顶——单元素组的 firstMode 走 'lead' 兜底可复现其缓存 top（静态自洽，proven 读码）；但「拖块落入 body 组（与跨栏块相邻落位）」时 columnWalk 以 body 顶为栈顶推演其余位置，可能与真实布局偏离（inferred 风险点 R-1，探针 F7 覆盖、坐实才动笔 5）。
  - canvasFocusRoute（bridge.rs:1265-1324）：在全部 `:scope > .editor-column` 中只按 clientX 选栏——分段后同 X 有多段栏，find 取首个命中，可能把「点正文下方空白落焦」送进错误段的末可编辑块（inferred 风险点 R-2，探针 F8 覆盖）。独立模式恒两栏、不受影响。
  - 流式栏不独立滚动（.editor-column 无 overflow，整页滚），metaRectNow（bridge.rs:2263-2266）对 colEl 的 colDy 在流式恒空、走 winDy，与分段无冲突（proven 读码）。

---

## 三、G-2 翻转：落点与影响面

### 1. 落点（proven，唯一）

editor.rs:1592-1613 twopane 初值闭包：mode 有值从 mode；legacy twoPane==true 从之；**layout 存在但无 mode（且 twoPane 非 true）时现行 `return false`（:1604-1606）→ 改 `return true`**，与原版 normalize 缺 mode 默认 independent（editor.render.js:169，审计 §3）对齐。全仓再无第二处读 layout.mode（apps/web/src 内 grep 仅 editor.rs 命中；crates 对 layout 不做校验、extra 透传，model.rs:48）。

### 2. 影响面（proven + inferred）

- **数据来源面极小（proven）**：Rust 三处写锚点全部带 mode（落锚 "independent" :1692、关存 "independent" :2531、开关按 next 写 :2674-2682）；原版亦恒写 mode。无 mode 的 layout 只可能来自导入的旧/手写备份或异常数据——与审计 G-2「可忽略级」定级一致。
- **行为变化（proven，读码推论）**：此类备忘宽屏打开由 flow 变 independent（栏内独立滚动、定高容器）；窄屏无变化（show_cols=false 与 twopane 无关）。
- **连带归一（proven，读码）**：翻转后首次宽屏打开即满足落锚 effect 的 `twopane && wide` 门（:1661）——已有合法 left/right 名单者 normalize_boundary 命中、锚不动（:1666-1675）；名单缺失/不合形者会被规范分界落锚并覆写为带 mode 的完整 layout（:1677-1700）。关存时 twopane 为真亦会按分界重写 layout 并补 mode（:2495-2541）。即翻转顺带把这类存量 layout 在首次宽屏打开/关闭时归一为标准形状——与原版 normalize 的处理方向一致；原版对两边皆无存活 id 的病理 layout 输出全右栏、Rust 既有实现已刻意不从（columns.rs:73-76 注释），此差异与 G-2 无关、不在本批。
- **仓内先例同向（proven）**：op_move_block 重写锚时 mode 缺失默认已用 "independent"（editor.rs:3967-3972）——翻转后两处口径统一。
- G-3 不动（proven）：canonical_boundary 只用规范估高（columns.rs:17-68），本批段内切分复用之，与「落锚后恒定、首次位置可与原版不同」的既定偏离一致。

---

## 四、决策点（派发前请父级确认）

- **D1（必须确认）probe_twocol_matrix M1 判据失效**：现 M1 断言「独立/flow 两模式成员逐块一致」（probe_twocol_matrix.mjs:2、:105）。A-2 落地后流式成员由段内规范切分决定、与独立锚分界**按设计不再一致**（含跨栏块的文档必然不同；无跨栏块时流式=全档一段规范切分，与锚分界亦可不同）。M1 须改判据：独立模式成员=锚（M2 往返不变保留）、流式成员=分段确定性（同文档两次打开逐块一致 + 跨栏整幅断言归新探针）。这是对既有已验断言的口径变更，不应在落码线内静默改。
- **D2**：段内切分采用段内规范估高（不用锚）——本报告按已定「正交」口径的唯一自洽读法拟定（锚求交的锯齿形态见二·笔2）；若父级另有读法，笔 2 需改拟。
- **D3**：死 span CSS（:739-749、:783-787 的 column-span 声明）建议删除（防断裂声明保留）；若父级倾向保留作意图文档，笔 4 可只新增不删。
- **D4（信息）**：musicCard 编辑态的 .music-input-pill 在流式段内保持栏宽（不跨栏）——原版 span 瞄的是 musicCard 块本体、编辑胶囊无对应原版形态，属编辑瞬态，拟不特殊处理（inferred）。

---

## 五、探针断言清单（宽屏流式夹具）

新探针（建议名 probe_twocol_flow_span.mjs）+ G-2 断言组；视口 1440×900（Chromium 口径，真机/WebKit 终判不在本批）。夹具文档序：段落×3、image、段落×2、gallery、段落、imgTextCard、musicCard、带图 attachment、段落×2（另备无 layout / layout 无 mode / layout mode=flow 三种存量形态）。

- **F1 跨栏整幅**：六类跨栏块渲染宽 ≈ .editor-body 内容宽（容差 ≤2px）、左缘与 body 内容左缘齐。
- **F2 非跨栏栏宽**：各段内文本块宽 ≈ (body 内容宽 − gap)/2（容差 ≤2px）；段内两栏均非空（段长 ≥2 且估高可分时）。
- **F3 文档序**：桥 allUnits 口径（或 DOM 走查）得到的块序 == 文档序（含跨栏块位置）。
- **F4 分段切分确定性**：同备忘两次打开（关→开）流式下逐块栏归属/整幅标记全等；段内切分位置 == 对段切片手算 canonical_boundary（夹具内预置已知估高组合核一例）。
- **F5 锚零改写**：带锚备忘以流式打开→渲染→关闭全程，extra.layout 与打开前逐字节一致；Diag 无 "column anchor captured" 行（流式打开不落锚）。
- **F6 模式往返**：流式→独立→流式：独立下成员 == 锚分界（逐块）；回到流式与 F4 首开全等；layout 全程不变。
- **F7 流式拖拽**：段内换位落盘后 doc 序正确；拖一段落跨过 image（跨栏块）落到其后段，落盘 doc 序与落点一致、重进渲染序一致；带锚时落盘 layout 仍一刀切（left/right 为新序前缀/后缀）。（兼验风险点 R-1 的落位动画/落点判定。）
- **F8 画布落焦**：点最后一段正文下方空白，焦点落最后一段内末可编辑块（不落到首段）。（验风险点 R-2。）
- **F9 窄屏退化**：500px 宽同备忘：无 .editor-flow-seg、单栏序 == 文档序、跨栏块宽 == 内容宽。
- **F10 独立模式防漏**：同夹具独立模式下六类块宽 == 栏宽（不跨栏）——A-2 不得漏进独立模式。
- **G2 组**：layout 无 mode 备忘宽屏打开 = 独立模式（body class is-independent-scroll、菜单开关 aria-checked=true）；layout mode="flow" 备忘 = 流式；无 layout 备忘沿 localStorage 默认（回归既有口径）；无 mode 且名单合法者打开后 layout 名单不被改写（仅模式判定翻转，名单合法不触发落锚覆写）。

既有探针回归面：probe_twocol_matrix（M1 按 D1 改判据、M2 保留）、probe_audit_indcols*（独立模式五项，不应受影响——流式分支与独立分支隔离，跑一轮坐实）。

---

## 六、结论分级汇总

- proven：流式×宽屏现状无跨栏、死 span 规则、块集对照与判定标志、G-2 唯一落点与三处写锚恒带 mode、拖拽数据层零交互、桥走查结构可容、落锚/关存/开关三路径不需动。
- inferred：段内锚求交的锯齿形态（排除依据）、分隔线随段中断与原版同构、gallery 整幅后内部呈现达原版口径、拖拽 R-1/R-2 两风险点、music-input-pill 编辑态口径（D4）。
- unknown：无（本批范围已由审计与已定矩阵封顶；真机手感终判按惯例归部署后真机，不在本批）。
