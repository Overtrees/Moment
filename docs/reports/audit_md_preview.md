# E16 余项调研：Web 版 MD 源段落失焦预览机制（供原生实现）

调研范围：`rust/apps/web/src/blocks.rs`、`editor/`（model/render/dispatch/hooks/js）、`crates/core/src/mathml.rs`、`crates/ffi/src/lib.rs`、原生 `rust/apps/ios/app/MomentApp.swift`。结论逐项标 proven / inferred / unknown，关键口径给文件:行号。

---

## 1. 哪些段落算 MD 源段落

### 1.1 存储形态（proven）

MD 源段落在文档模型里**没有独立块类型**：就是 `type = "paragraph"` 的普通段落，源码全文住在 `children[0].text` 里（可含 `\n`）。代码块、列表、Callout 在文档里都是这个形态，渲染时才成预览、点击回源码编辑（`blocks.rs:1436-1439` 注释，源头是原版 `use-slash.js:518-545` 的模型实证）。

原生侧现状与之天然兼容：原生段落块的文本同样是字面全文，**不需要数据迁移**（inferred，由原生 BlockState 模型与 Web 模型同构推得）。

### 1.2 分类判据（proven）

判据单点在 `blocks.rs`：

- 入口 `md_classify(text) -> Option<MdKind>`：`blocks.rs:1531`（量测包装）、实现 `md_classify_impl` 在 `blocks.rs:1538`。
- 编辑器门控每渲染趟预判一次：`editor.rs:585-592` 的 `para_kinds`——块类型为 `paragraph` 且 `md_classify(plain_text()).is_some()`。
- 只读渲染（列表页/非编辑器复用）同判据：`blocks.rs:829-834`，段落 `md_classify` 命中即走 `MdPreview`。

`md_classify_impl` 的判定顺序（`blocks.rs:1538-1790`，逐项 proven）：

| 顺序 | 形态 | 判据细节 |
|---|---|---|
| 1 | 代码围栏 Code | ≥2 行且首行以 ` ``` ` 或 `~~~` 起；闭合行须同字符、长度 ≥ 开围栏，**可缺省**（未闭合取到段尾，marked 口径）。空围栏 guard：全文剥尽 ` ``` ` 后无内容 → 不转（C-23） |
| 2 | 失焦 guards | 段首 `>` 时先行校验：引用正文（剥首行 `^\>\s*` 后）< 2 字符不转；`> [!` 未以 `[!\w+]` 合法闭合不转（C-23，原版 `md-blocks.js` 的失焦 guards 等价单点） |
| 3 | Callout | 首行 `> [!TYPE]`，可带折叠符 `+`/`-` 与自定义标题；其余行剥 `>` 前缀为正文。类型映射表 `callout_style_title`（`blocks.rs:1474`）：note/info/todo/abstract/quote→note 系、tip/success/example→tip、question/warning→warning、important/failure/bug→important、caution/danger→caution；**未知类型标题回退类型原文**（C-21） |
| 4 | 缩进代码 Code | 全部非空行 ≥4 空格或 tab 缩进（C-28，须在列表分支之前判，防 `    - x` 误判列表） |
| 5 | 列表 List | 全部非空行同为 `- ` 前缀（无序）或全为 `N. ` 前缀（有序） |
| 6 | 分隔线 Divider | 整段仅由 ≥3 个 `-` 组成。**`***` / `___` 独占段不转**（原版门控下不转换，M8 反向差收窄） |
| 7 | 标题 Heading | **单行**段且 `#`~`######` + 空格（1–6 级） |
| 8 | 表格 Table | ≥2 行、首行含 `|`、次行是分隔行（每格仅 `-`/`:` 且含 `-`，对齐 左/中/右 = 0/1/2），**且全文须过 `looks_like_markdown` 门控**——单元格无任何行内 md 信号的纯表格在原版保持源码态，不转（与 M8 同类收窄） |
| 9 | 引用 Quote | 全部非空行以 `>` 起（Callout 已先行摘走）；空行分段、同段行以空格拼接 |
| 10 | Rich（兜底） | 其余段落过 `looks_like_markdown` 即归 Rich：纯行内 md、混合结构、脚注、上下标、公式、wiki 链接等 |

`looks_like_markdown`（`blocks.rs:1793`，原版 `editor.md.js:330-335` 的手写等价，proven）：

- 行首模式任一命中：`#{1,6}\s`、`[-*+]\s`、`\d+\.\s`、`>\s`、整行 `---+`；
- 行内模式任一命中：任一反引号；成对跨度 `**…**`、`__…__`、`~~…~~`、`==…==`（内容禁含定界符/换行）；`[[…]]`（wiki）、`[^…]`（脚注引用）、`^(…) ^` / `~(~)~`（上下标）、`[…](…)` 与 `![…](…)` 链接/图片、单 `*…*` 斜体、上标裸形 `^…^`、下标裸形 `~…~`；
- 数学门控：`moment_core::has_math_syntax`（`crates/core/src/mathml.rs:70`：`$$` 成对、`$` 成对且内容过启发式）。

**排除项**（proven）：标题块、待办块、原生 codeBlock 块等非 `paragraph` 类型永不走此判据（`is_block_preview_para` 先卡块类型，`editor/model.rs:151-158`）；空段不转；纯文本无 md 信号不转。

### 1.3 块级预览 vs 行内预览（proven）

分类命中只决定「进预览」，预览本身分两形态，由**全量解析结果**决定（`md_is_block_preview`，`blocks.rs:4799-4802`）：

- 解析结果恰为单个普通段落（`MdBlock::Para`）→ **行内预览**；
- 其余（多块、或单块但非 Para，如单个代码块/表格/标题）→ **块级预览**。

此区分有实际后果：尾随空段只跟块级预览补（§2.4）；行内预览的 DOM 是段落元素本身（§2.2）。

---

## 2. 失焦→预览、点按→回源码的完整交互

### 2.1 状态机（proven）

两个上下文信号（`blocks.rs:37`、`blocks.rs:45`，由 `editor/hooks/bridge_wire.rs:214-218` 提供）：

- `MdEdit: Signal<Option<String>>`——正处于「MD 源码编辑态」的块 id；
- `ActiveEdit: Signal<Option<String>>`——当前聚焦编辑中的块 id。

渲染门控在 `EditorBlock` 的段落分支（`editor/render.rs:279-345`）：

```
if editing (MdEdit == bid):
    源码编辑态：EditableDiv，force_btype = "mdsrc"，
    initial_html = 源码转义后 \n → <br>
else if !active (ActiveEdit != bid) && para_md (分类命中):
    预览态：.md-hit 包裹 MdPreview
else:
    普通 EditableDiv
```

编辑态优先于分类结果是刻意的防抖设计：源码打字中间态（如只打了 `-`）暂时不构成合法 md，若按分类切分支会把编辑区重挂成普通段落、丢 mdsrc 语义（`editor/render.rs:281-286` 注释）。

### 2.2 时序（proven）

- **聚焦**：桥 `focusin`（`editor/js/editor.js:1152-1159`）→ `focusBlock` 消息 → `ActiveEdit = bid`（`editor/dispatch.rs:472-476`）。聚焦中的块即使分类命中也保持可编辑形态——这是「打字过程中不翻预览」的机制本体。
- **失焦**：桥 `focusout`（`editor/js/editor.js:1177-1183`）→ `blurBlock` 清 `ActiveEdit`（`dispatch.rs:477-481`）；若该块 `data-btype == "mdsrc"`，同拍再发 `mdDone` → 清 `MdEdit` 并落盘（`dispatch.rs:465-471`）。两信号清零后重渲染，门控 `!active && para_md` 成立 → **翻成预览**。普通段落里现打出的 md 也是这条路：失焦清 ActiveEdit 后按分类转预览（不需要 MdEdit 参与）。
- **源码同步**：mdsrc 块编辑期间逐键发 `mdText`（`editor.js:1094`），Rust 侧把整块文本以单个文本节点落模型、尾部 `\n` 修剪、历史压栈走 600ms 合并（`dispatch.rs:452-464`）。
- **点按回源码**：预览外层 `.md-hit` div 的 `onclick`（`editor/render.rs:305-335`）→ `MdEdit.set(Some(bid))` + `sync_arm_md_focus(bid)`（`editor/render.rs:951-963`，武装桥的挂载焦点守卫 `__mnFocusAtMount(bid, usize::MAX)`）。
- **合并列表组**：相邻 ≥2 个列表源段落成组渲染为单个合并预览（`MergedListPreview`，`editor/render.rs:112-197`；组员资格 `is_list_group_member` 在 `editor/model.rs:332-367`、成组 `flow_runs` 在 `editor/model.rs:369-395`，不跨栏/不跨流）。点击时**模型层把组员合并回首块**（首块 id 与位置保留、文本为各段修剪后 `join('\n')` 的合并源码、其余块删除）再进源码编辑（`editor/render.rs:138-176`）。

### 2.3 光标落点口径（proven）

**一律落源码末尾，点击位置不参与落点。** 单块与列表组同口径：原版 `use-editor-dom.js:117-135` 对块级预览还原后 `selectNodeContents + collapse(false)`；表格分行时落最后一行末尾，单块模型下即全文末尾。Diag 日志口径 `caret=end offset={全文 UTF-16 码元数}`（`editor/render.rs:179`、`editor/render.rs:318`）。历史上曾误读为「点击处附近」，第八批双边复测已证伪（`editor/render.rs:116-121` 注释）。

原生对应物现成：批 5 已落的 `focusBlockId` + `focusCaretEnd = true` 路径即等价落点（inferred）。

### 2.4 尾随空段（proven，原生必须复刻的行为）

块级预览（列表组除外）之后，若紧邻块是原子块 / 分割线 / 另一个块级预览，或已到文末 → 补一个真实空段落块，否则用户在预览下方无处点按落焦。实现是**模型层物化**而非视图占位：`materialize_trails`（`editor/model.rs:242-262`），判定 `trail_after`（`editor/model.rs:191-216`）；打开备忘时与会话内 effect 续补，正处源码编辑的块之后暂不补、失焦转预览时再补。文末原子块另有 `TRAIL_END_ATOMIC` 清单（`editor/model.rs:226-235`）。插入的空段是带 id 的真实段落、会落盘（原版首次 parseEditorDOM 同步即成真实段落）。

### 2.5 预览 DOM 结构与样式类（proven）

`MdPreview` 组件（`blocks.rs:4718-4794`）两形态：

- 行内预览：`<p class="md-preview-inline" tabindex="0" role="group" aria-label="Markdown 预览，按回车或空格编辑">`，内文为行内分段渲染（`InlineSegs`）。
- 块级预览：`<div class="md-preview block markdown-render">` 包裹 `MdBlocks` 渲染树；解析为空时兜底 `<p>{原文}</p>`。

编辑器内两形态外层再包 `<div class="md-hit" data-bids="{bid}">` 承接点击（`editor/render.rs:305`）。样式要点：

- `.markdown-render` 语义层级（表格/列表/callout/pre/h1-h4 等）在 `styles/editor.css:2-90` 一带，编辑态与阅读态共用同一套（`editor.css:236` 注释：编辑态块级 Markdown 复用阅读态语义层级）。
- 编辑态预览本体：`.editor-body .md-preview` 玻璃胶囊底（`editor.css:475`），`.md-preview.block` 覆写为整宽、无底、无边、上下 4px 边距（`editor.css:478-482`）；`.md-preview-inline { cursor: pointer }`（`editor.css:476`）。
- `.md-hit` 与 `.blk-wrap` 同列 `-webkit-touch-callout: none`（`editor.css:203`）；预览两形态有 `:focus-visible` 描边（`styles/base.css:264-265`）。

**unknown**：行内预览的「按回车或空格编辑」——`aria-label` 如此声明（`blocks.rs:4775-4778`），但本次调研在编辑器桥（`editor.js`）内未找到针对 `.md-hit` / `.md-preview-inline` 的 keydown 处理（点击由 Dioxus `onclick` 承接，桥内 grep 无命中）。编辑器内键盘回源码是否真实可用，未取证；原生实现时按「点按回源码」为必达口径、键盘路径自行补齐即可（iOS 无物理键盘常态，影响低）。

---

## 3. 预览渲染覆盖的语法集

### 3.1 渲染管线（proven）

预览**不走 HTML 字符串**，是纯 Rust 结构化管线（Dioxus rsx 直接挂 DOM）：

```
源码文本
  → parse_md_document (blocks.rs:4310，带 48 条 / 512KB 内容键缓存)
      → extract_footnotes 抽脚注定义
      → extract_link_defs 抽引用式链接定义（定义行不渲染）
      → parse_md_blocks 逐行切块（marked 子集，混合结构段逐行切分，不要求整段同型）
      → 每块行内文本经 parse_inlines 解析为 InlineSeg 树
  → MdBlocks / MdBlockView (blocks.rs:4426) 逐块 rsx
  → InlineSegs (blocks.rs:3302) 逐段 rsx
```

块树 `MdBlock`（`blocks.rs:3515-3553`）：Code{lang} / Heading{level} / Para / Math{tex} / Quote{blocks} / Callout{style,title,folding,blocks} / List{ordered,start,items（含任务勾选与嵌套子块）} / Table{head,align,rows} / Divider / Footnotes{items}。

行内段 `InlineSeg`（`blocks.rs:2178-2216`）：Text / Code / Strong / Em / Underline（仅原始 HTML `<u>` 通道产生）/ Del / Highlight / Sup / Sub / Link{href,children} / Image{src,alt} / Wiki{target,label} / FootRef / Math{tex,display} / Break。

### 3.2 逐语法处理（proven）

- **标题**：块级 `#`~`######` → `<h1>`~`<h6>`，行内段递归解析。混合段（标题行+正文行）由 `parse_md_blocks` 逐行切分，各自成块。
- **列表**：无序/有序（`start != 1` 时带 `start` 属性）；任务项 `- [ ]`/`- [x]` → disabled 的 checkbox input；缩进子块成嵌套列表挂在父 `li` 内（旧实现拍平、现已对齐 marked）。
- **表格**：`<table>` + thead/tbody，单元格 `text-align` 按对齐列内联样式；单元格内容走行内解析；`\|` 为转义竖线不作分隔（`split_table_row`，`blocks.rs:1507`）。
- **代码**：围栏 → `<pre><code class="language-{lang}">`（**只有语言类名、无语法高亮**）；缩进代码同路。行内代码 → `<code>`。
- **公式**：core 纯 Rust MathML——`moment_core::render_mathml(tex, display)`（`crates/core/src/mathml.rs:2920`），结果经 `dangerous_inner_html` 注入 `.math-inline` / `.math-block` 包裹（`MathSpan` `blocks.rs:3454`、`MathBlock` `blocks.rs:3487`，带 (tex,display) 记忆化缓存）。块级公式 = 独占段的 `$$…$$`，居中成块；段中 `$$…$$` 同样以块式呈现。**渲染硬错误回退红色原码** `<code class="math-source">` 并记 Diag（与原版 renderMath 兜底同形）。
- **链接**：`[文字](url)`、引用式 `[文字][label]`、裸 URL/邮箱 autolink（GFM）。href 过协议白名单 `safe_http_url`——**被拦时只渲染子段文本（span 保形）、不生成锚点**（C-30，`blocks.rs:3331-3341`）。
- **图片**：`![alt](src)` → `<img loading="lazy" decoding="async">`，src 过图片白名单 `safe_image_url`——被拦保留 img 元素、src 置空；尺寸走 imgsize 预留几何（Natural 型）防跳动（`blocks.rs:3343-3358`）。
- **wiki 链接**：`[[目标]]` / `[[目标|标签]]` → `.moment-wiki-link` 锚点，点击经 WikiNav 上下文跳篇（stop_propagation，不触发回源码）。
- **引用/Callout**：Quote → `<blockquote>` 递归块树；Callout 五系样式（note/tip/warning/important/caution）+ 图标 + 标题，带折叠符时渲染 `<details>/<summary>`（`open` 由 `+` 决定）。
- **脚注**：`[^id]` → 上标编号锚点；文末汇总 `<section class="footnotes">` 有序列表 + ↩ 回链。多引用同脚注编号口径按定义顺序。
- **其余行内**：`**`/`__` 粗、`*`/`_` 斜、`~~` 删除（`.moment-strikethrough`）、`==` 高亮（`.moment-highlight` span，非 `<mark>`）、上下标 `^…^`/`~…~` 与 `^(…) ^` 形、软换行 → `<br>`（marked breaks:true 口径）、原始 HTML 标签有处理通道（计数落 Diag，具体标签按 marked 口径剥壳/保留，未逐标签取证——unknown 细节级）。

### 3.3 降级与不转清单（proven）

- `***` / `___` 分隔线段：不转预览（保持源码）；空围栏不转；极短引用（正文 <2 字符）不转；`> [!` 未合法闭合不转；无行内信号的纯表格不转（§1.2 表格行）。
- 公式渲染失败 → 红色源码（不阻断整段预览）。
- 链接/图片过白名单失败 → 降为纯文本/空 src img（不阻断）。
- 未被引用的脚注定义：按 marked「链接定义吞行」口径——主体含空白的残行以普通段落文本补回渲染（`blocks.rs:4400-4424`）。
- 解析结果为空（极端输入）→ 块级预览兜底直接显示原文 `<p>`。

---

## 4. 原生落地建议

### 4.1 现状与关键约束（proven）

- 原生编辑器现状：段落块恒渲染 `BlockTextView`（UITextView）可编辑态，**无任何 md 分类/预览代码**（`MomentApp.swift` 内 grep `mdPreview/markdown` 零命中，导出方向的 ExportGen 除外）；MD 源段落目前在原生就是「永远源码态」。
- 原生已有的可复用件：`EditorModel.editingBlockId`（聚焦块跟踪，`MomentApp.swift:2133`，由 Coordinator 的 didBegin/didEndEditing 维护 `:1231-1238`）≈ Web 的 ActiveEdit；`focusBlockId`/`focusCaretEnd` 落焦通道 ≈ 点回源码的光标落末尾；`ExportGen`（`MomentApp.swift:3197`）是**模型→MD/HTML 的反方向**生成器（导出用），不是 MD 解析器，除转义/runs 映射的思路外不可直接复用为预览管线；`PdfMaker`（`MomentApp.swift:3152`）是离屏单只 WKWebView 出 PDF 的通道。
- **决定性约束**：md 分类器与解析器（`md_classify` / `looks_like_markdown` / `parse_md_document` / `parse_inlines`）目前住在 **Web 应用 crate**（`apps/web/src/blocks.rs`），不在 `moment-core`；FFI 导出面（`crates/ffi/src/lib.rs:65-248` 全量核过）**没有任何 md 函数**。core 里只有公式件：`has_math_syntax`（`mathml.rs:70`）与 `render_mathml`（`mathml.rs:2920`），且未过 FFI。→ 原生无论走哪条渲染路，**先要把解析能力下沉/过桥**，这是绕不开的前置。

### 4.2 候选路径评估

**路径 A：WKWebView 内嵌预览（每块一只 WebView，HTML 来自新 FFI `md_to_html`）**（inferred 评估）

- 还要先在 Rust 侧新写 MdBlock→HTML 序列化器（现管线产 rsx 不产 HTML，Web 侧也没有现成 MD→HTML 串行器可抄；`doc_to_html` 是模型→HTML、对象不同）。
- 编辑页内嵌 WebView 的代价最重：长备忘几十个块 = 几十只 WKWebView，内存与创建成本（每只数十 ms 级）叠加滚动复用问题；每块高度需 JS 回报 → 异步测高与 SwiftUI 布局互相追赶、抖动；点按回源码、wiki 链接点击、图片点按都要 JS 桥逐项转发；键盘/选区/长按手势与原生块体系（拖拽拾起、块选择）冲突面大。PdfMaker 的经验只证明「离屏单只 WebView」可行，不证明「编辑流内多只」可行。
- 结论：**不推荐**作为编辑页内预览路径。仅公式片段可借道（见阶段 3）。

**路径 B：Swift 全量移植解析器**（inferred 评估）

- 分类器可移植（`md_classify_impl` 约 270 行 + `looks_like_markdown` 约 200 行，纯文本处理）；但全量解析（`parse_md_blocks` + `parse_inlines` + 脚注/引用定义抽取，数千行且带大量 C-2x/M 系列对原版预言机的边角口径）移植后形成**双解析器长期漂移风险**——Web 侧口径是靠 marked 预言机回归测试锁定的，Swift 侧没有等价测试床。
- 结论：不推荐全量移植；分类器移植可作为阶段 1 的临时替代（见下），但正解是解析单点化。

**路径 C（推荐）：解析下沉 core + FFI 结构化输出 + SwiftUI 原生渲染**

- Rust 侧把分类/解析从 `apps/web/src/blocks.rs` 下沉到 `moment-core`（解析层本身是纯文本处理：注释多处自述「解析层直调 diag 不可用」故已与 Web 运行时解耦，`InlineSeg`/`MdBlock` 定义也在同文件内；视图层 `MdBlockView`/`InlineSegs`/白名单/图标留在 Web 侧消费同一结构）。Web 侧改引 core 类型，原有 md 回归测试（预言机期望值在 `blocks.rs` 测试模块）随迁守护，口径单点不分叉。
- FFI 新增（过桥只走字符串/标量，与现行 FFI 口径一致）：
  - `md_classify(text) -> String`：返回 kind 标签（code/rich/callout/list/table/heading/quote/divider/none），供门控与列表成组判定；
  - `md_is_block_preview(text) -> Bool`；
  - `md_parse_json(text) -> String`：MdBlock/InlineSeg 树的 JSON 序列化，供 Swift 渲染；
  - `render_mathml(tex, display) -> String`：core 现成函数直接过桥（成功返回 MathML、失败返回空串走降级）。
- Swift 侧：
  - 门控照搬 §2.1：段落块在 `editingBlockId != 本块` 且 classify 命中时，`BlockRow` 段落分支改渲 `MdPreviewView`（只读），点按 → 设源码编辑态 + `focusBlockId/focusCaretEnd` 落末尾（§2.3 口径）。进入源码态的块复用现有 BlockTextView（其文本即源码全文，与 Web mdsrc 的「普通可编辑段落装源码」同构）；失焦（didEndEditing）后门控自然翻回预览——与 Web 的 blurBlock+mdDone 合流等价，不需要再造状态机。
  - 尾随空段：`EditorModel` 在 init 与失焦翻预览时点按 §2.4 规则物化（块级预览之后无可编辑块则插入空段落），判定用 FFI 两函数即可。
  - 列表成组：**v1 不做模型合并**——逐段各自预览（每段一个列表预览），视觉与 Web 合并预览近似；点击回源码只动本段、不合并邻段（与 Web 的模型合并行为有分叉，但存储更安全、无删块风险）。是否补齐成组列为后续裁定项（inferred 可接受分叉）。
  - `MdPreviewView` 渲染 JSON 树：块级用 SwiftUI 原生组件拼装（Heading/Para 用 Text + AttributedString 行内构建器；Code 用等宽文本 + 现有 `T.codeBg`；List 复用批 5 `ListBlockView` 的行结构经验；Table 用 Grid；Callout 复用现有 callout 五变体的 `T.calloutBg/calloutAccent` 与标题表；Quote 左边线样式；Divider 现有渲染；Footnotes 简化为文末小字列表）。行内段构建器把 Strong/Em/Code/Del/Highlight/Sup/Sub/Link/Break 映射到 AttributedString 属性——与现有 `Marks` 体系同源可扩展；Image 走现有 ImageLoader；Wiki 链接点按走已落地的跳篇通道（反向链接同路）；Link 用 openURL。Dynamic Type 自然跟随（原生更优面）。

### 4.3 分阶段与工作量分级

| 阶段 | 内容 | 量级 |
|---|---|---|
| 阶段 1 | Rust：解析下沉 core + Web 改引 + 回归测试守护；FFI 四函数 + 绑定重生成。Swift：门控 + 点回源码（落末尾）+ 尾随空段物化；预览先只做**纯文本占位渲染**验证状态机闭环 | M |
| 阶段 2 | SwiftUI `MdPreviewView` 全语法渲染（块树 + 行内 AttributedString 构建器 + 表格/嵌套列表/脚注/callout 折叠） | M–L |
| 阶段 3 | 公式：FFI `render_mathml` 的 MathML 串在 SwiftUI 无原生渲染面——两案待裁：(a) 仅公式段借一只共享 WKWebView 渲染 MathML 片段（数量少、离流渲染后以快照/固定高嵌入）；(b) v1 降级为等宽源码文本（着色区分），后续再补。推荐先 (b) 保闭环、(a) 单独排期 | S（案 b）/ M（案 a） |

总量级 **L**（阶段 1+2 主体，公式按案 b）。对照：路径 A 表面 M、但运行风险与长期维护成本最高；路径 B 为 L+ 且带双解析器漂移，不取。

### 4.4 落地时不可省的对齐清单（proven 口径汇总）

1. 门控三条件：`paragraph` 类型 ∧ classify 命中 ∧ 本块非聚焦编辑中；源码编辑态恒优先于分类（防打字中间态 flicker）。
2. 点回源码光标**恒落全文末尾**，不取点击位置。
3. 块级预览后尾随空段为**模型层真实段落**、会落盘；源码编辑中的块之后暂不补。
4. 行内预览与块级预览的区分由全量解析结果决定（单 Para = 行内），不是由 classify 的 kind 直接决定——如纯 `**粗**` 段 classify 为 Rich、解析为单 Para，走行内形态。
5. 降级口径：公式失败红源码、链接被拦只剩文本、图片被拦空 src——原生 FFI/渲染层需留对应口子（白名单函数 `safe_http_url`/`safe_image_url` 在 Web 视图层，core 下沉时建议一并下沉供双端共用）。
6. 列表组点击合并是 Web 的模型行为，原生 v1 若不做，须在审计表 E16 明确记分叉，不可默认等价。
