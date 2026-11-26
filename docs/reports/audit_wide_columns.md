# 双栏 / 宽屏形态审计：Web 口径 vs 原生现状与落地建议

- 日期：2026-11-26
- 范围：Web 编辑页双栏（`rust/apps/web/src/editor*` + `styles/editor.css`）与原生 iOS 编辑页（`rust/apps/ios/app/MomentApp.swift`、`build-app2.sh`）的形态差距；只读审计，未改源码。
- 口径基准：用户 2026-11-22 双栏要求（左右各自独立容器、可混排、重进不跳栏）、2026-11-24 裁定（宽屏流式不跨栏、两物理栏形态，覆盖 A-2 跨栏设计）、既定 G-2（无 mode 的 layout 默认 independent）/ G-3（首次切分用规范估高，有意偏离原版实测高）。

## 结论摘要

- Web 双栏已是定案形态：宽屏时**恒为两个物理栏容器**，开关只切换分栏来源与滚动形态（流式 flow / 独立 independent），不切换栏的有无。数据骨架 = 一份有序文档 + 单一分界点，`layout` 锚只是分界的 id 名单表示。**（proven）**
- 原生编辑页目前是彻底的单列实现：无宽屏判定、无模式状态、不读 `layout`（仅经 raw 透传保全）、菜单无双栏开关。iPhone 上与 Web 窄屏形态一致、无差距；差距只出现在宽屏设备（iPad / 大屏横屏），而现行 ipa 连 iPad 原生形态都进不去（见 §2.3）。**（proven / inferred）**
- 原生落地不需要动数据层：分界函数是文档的确定性纯函数，可逐行移植；主要工作量在编辑页视图拆分（两栏容器 + 独立滚动）与拖拽的栏内限定。跨栏拖拽是唯一的大件，建议分两步走（见 §4）。

---

## 一、Web 双栏完整口径（proven，出处为现行代码）

### 1.1 触发条件：宽屏判定

- 媒体查询：`(min-width: 768px) and (min-height: 600px), (min-width: 1100px)`——宽 ≥768 且高 ≥600，或宽 ≥1100（不论高）。`rust/apps/web/src/editor/hooks/columns.rs:58-68`（初值）、`:73-97`（matchMedia change 监听回送）。
- CSS 侧同一媒体查询掌管双栏布局与开关行可见性：`rust/apps/web/styles/editor.css:972` 起（independent）、`:1061` 起（flow）、`:631` 起（spread 排版）。
- 例外：横屏低高（`orientation: landscape) and (max-height: 560px) and (max-width: 1099px)`）强制单栏，`editor.css:673-678` 一带。
- 含义换算：iPhone 竖屏（393pt 宽）与横屏（852×393，高 <600 且宽 <1100）都不触发；iPad 竖屏（768×1024 起）与横屏触发。

### 1.2 两种模式与默认

模式状态 = `twopane` 信号（true = independent，false = flow），初值决议序（`hooks/columns.rs:35-55`）：

1. 本篇 `layout.mode` 在位：`mode == "independent"` 为真，其余（`"flow"`）为假；
2. 有 layout 但无 mode：默认 **independent**（G-2 翻转后口径，与原版 normalize 缺 mode 对齐）；
3. 无 layout：读 localStorage `sj_editor_independent_scroll`（`"1"` = independent）——这是用户级默认值，由开关切换时写入（`editor/layers.rs:395-402`），供无锚备忘下次打开沿用；
4. 都没有：false（flow）。

两模式的差异只在两点（`editor.rs:552-575` 注释与实现）：

| | flow（流式） | independent（独立滚动） |
|---|---|---|
| 分界来源 | 恒为规范估高切分 `canonical_boundary`，**不读不写 layout** | layout 锚优先（`column_boundary`），无锚时规范估高 |
| 滚动形态 | 整页滚动，两栏自然高 | 栏内各自滚动（见 §1.5） |
| DOM 类 | `editor-body is-flow-columns` | `editor-body is-independent-scroll` |

注意：`show_cols = wide`（`editor.rs:564`）——只要宽屏就渲染两栏，模式只决定上表差异；窄屏恒单栏（`runs_all` 单列渲染，`editor.rs:610-625`）。

### 1.3 数据骨架

- 一份有序文档 + 单一分界点：`Memo.layout: Option<MemoLayout>`，`MemoLayout { version, mode, left, right }`，left/right 为两栏块 id 名单（`rust/crates/core/src/model.rs:87,100-113`）。名单在写入方恒为文档序的前缀/后缀切分（见 §1.4、§1.6、§1.7），归一后等价于一个分界下标。
- 渲染按分界下标把 `flow_runs` 切成左右两组分别喂两个 `.editor-column` 容器（`editor.rs:599-609`、`806-860`）；跨块列表组合并按栏区间各自成组、不跨栏成组（`editor.rs:576-577`）。

### 1.4 分界点如何定（G-3 规范估高）

分界函数 `column_boundary(doc, layout)`（`rust/apps/web/src/editor/columns.rs:97-106`）：

1. **有锚走锚**：`normalize_boundary`（`columns.rs:67-90`）——right 名单中按文档序第一个仍存在的块即右栏起点；right 全灭时取 left 名单最后一个存活块之后；layout 形状不合（left/right 任一缺失）或两边皆无存活 id → 视同无锚。
2. **无锚走规范估高**：`canonical_boundary`（`columns.rs:37-55`）——在 [1, len-1] 中取使左右估高总和最接近的切分点；不足两块全归左栏。
3. **估高表** `est_block_height`（`columns.rs:13-30`，原版 editorBlockHeight 回退表）：image/gallery/imgTextCard/imageTextRow = 280；musicCard/link-card/embedCard = 120；attachment 带图 280、否则 120；其余按纯文本 UTF-16 长度折行（44 字/行）：`28 + ceil(len/44)×25`。
4. G-3 口径：原版优先用实测高，实测随图片加载/字体/骨架态漂移；Rust 只用规范表，使分界成为文档内容的确定性纯函数（同文档同结果、重开一致、编辑不漂移）。此为有意偏离，已定案。
5. **落锚时机**：independent 首次渲染且本篇无有效锚时，按规范分界一次性落锚写库（left/right 名单 + `mode:"independent"` + `version:1`），此后成员由锚决定（`hooks/columns.rs:100-148`）。关闭保存时若双栏开启，按当前分界重写锚（`editor.rs:455-505`）。

### 1.5 排布与滚动（CSS）

- 共同：`.editor-spread` 最大宽 1440 居中（`editor.css:631-638`）；两栏为 grid 两等分列，列距 `clamp(28px, 3.2vw, 52px)`。
- flow（`editor.css:1061-1075`）：整页滚动、栏自然高；分隔线以背景渐变画在列距正中（对原版 column-rule）；栏内不设内边距（文本宽 = (体宽 − 列距)/2）。
- independent（`editor.css:975-1010`）：`.editor-body` 固定高 `max(200px, calc(100dvh − 187px − 安全区上下))`、`overflow:hidden`；每栏 `overflow-y:auto` 独立滚动（`overscroll-behavior-y: contain`），左栏右内边距 16 + 右边框 1px 分隔，右栏左内边距 16。
- 块防断裂：原子块/卡片/`.blk-wrap` 在栏内 `break-inside: avoid`，任何块不跨栏（flow 与 independent 同，`editor.css:1015-1026`、`1085-1096`）。
- 窄屏兜底：非宽屏时 `.is-independent-scroll > .editor-column { display: contents }` 退化为透明流（`editor.css:887-890`）——但窄屏渲染路径本就不产出栏容器，此规则只作信号与 CSS 瞬时不一致时的兜底。**（inferred：兜底性质）**
- 残留：`editor.css:639-646` 仍有一条 `.editor-spread > .editor-body { column-count: 2 }` 的多列规则，但现行 DOM 在宽屏恒带 `is-flow-columns`/`is-independent-scroll` 类、两者都以 grid + `column-count: 1` 覆盖之，该规则实际不生效，属 A-2 跨栏设计退役后的残留声明。**（inferred）**

### 1.6 双栏开关在哪

- 位置：编辑页 ••• 菜单面板首行（`editor/layers.rs:691-718`）：图标 + 标题「双栏独立滚动」+ 副标题「平板与 PC 可分别滚动两栏」（`lang/zh-CN.json:149-150`）+ 自绘开关轨/钮（42×26、钮 20、行程 16、开态 accent，`editor.css:943-965`）。
- 可见性：该行 CSS 默认 `display: none !important`，仅宽屏媒体查询内 `display: flex !important`（`editor.css:892-909`、`972`）——即**宽屏才显，窄屏菜单里根本没有这一行**（与标题坞双栏钮 M29 的 Web 形态同源）。
- 切换动作 `toggle_twopane`（`layers.rs:388-433`）：翻转信号；写 localStorage 默认值；按当前分界把 layout 重写为 `{version:1, mode: independent|flow, left, right}` 落库。注意关双栏（切 flow）也写锚（mode=flow + 现行名单），flow 渲染虽不读锚，但下次切回 independent 时锚即现行分界。

### 1.7 拖拽与跨栏规则

- 拖拽本体：JS 桥长按拾起，落点计算遍历两栏全部块元（`editor/js/editor.js:2289-2370` 的 `columnWalk`/`computeTarget` 按栏走查 FLIP），**可以跨栏落点**（原版无此能力，Rust 新增，审计定性「有意偏离」见 `docs/reports/audit_parity_rust_vs_original.md:82`）。
- 提交语义 `op_move_block`（`editor/ops.rs:213-275`）：文档序 remove+insert 重排；**有锚时保持分界块数**——按重排前分界下标在新序同一切分点重写 left/right 名单。即跨栏拖拽的净效果 = 块在文档序中越过分界点，栏成员随之换位，落盘恒为一刀切（名单恒前缀/后缀）。
- 历史：doc + layout 成对快照，撤销跨栏移动连锚一起回退（`ops.rs:11-19`、`hooks/bridge_wire.rs:188-196`）。

### 1.8 与 2026-11-24 裁定的核对

- 「宽屏流式不跨栏、两物理栏」：现行实现符合——flow 已由 CSS 多列改两物理栏容器（`editor.rs:556-562` 注释明载改版缘由：多列分界随加载漂移、column-span 与独立容器口径不符），`column-span` 规则已整删（`editor.css:660-665` 注释）。**（proven）**
- 「流式按规范切分自动分栏」：符合（§1.2/§1.4）。**（proven）**
- 「独立模式媒体不跨栏、卡片下方输入不跳栏」：分界只由锚/规范函数决定，编辑不改分界（文本编辑不触发重算，见 `columns.rs:92-96` 注释对旧字数分半漂移的复盘）。**（proven）**

---

## 二、原生现状（MomentApp.swift）

### 2.1 编辑页结构：单列、零宽屏处理（proven）

- `EditorView.body` 是单个 `ScrollView` + `VStack(spacing: 6)` 顺序渲染全部 `editor.blocks`（`MomentApp.swift:3468-3482`），其下挂落焦热区与反向链接区。
- 全文 grep `twoPane / sizeClass / horizontalSizeClass / regular / 双栏 / 宽屏` 的命中只有：字体权重 `.regular`、gallery 的 `LazyVGrid`、菜单注释、手势页一
...[truncated 6578 chars]