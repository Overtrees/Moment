# KaTeX 数学公式渲染立项评估（只读评估，未改任何代码）

评估时间：2026-11-21。评估对象：Rust Web 版（`rust/apps/web`，线上构建 bf834fa11d）与原版 Web 应用（仓库根，版本 2.2.7）。

## 0. 前提纠正（重要）

任务背景称「原版没有实现 KaTeX」——**与源码证据不符**。原版**完整实现了** KaTeX 渲染，且是自托管、无 CDN 依赖：

- `Moment.html:18,38`：`<link rel="stylesheet" href="./vendor/katex.min.css?v=2.2.7">` 与 `<script src="./vendor/katex.min.js"></script>`；
- `vendor/` 实物：`katex.min.js`（272,537 B，运行时 `katex.version` 实测 **0.16.47**）、`katex.min.css`（21,693 B）、`vendor/fonts/` 20 个 woff2 共 296 KB、KATEX-LICENSE；
- `src/editor/editor.md.js` 有完整的公式管线：`hasMathSyntax`（门控）、`looksLikeMathExpression`（防误判）、`preprocessMath`（预处理 stash）、`renderMath`（调 `w.katex.renderToString`，参数 `output:'htmlAndMathml', throwOnError:false, trust:false, strict:'ignore', maxExpand:100, maxSize:20`；KaTeX 缺失或抛错时兜底 `<code class="math-source">` 原码）；
- `src/styles/editor.css:315-327` 有 `.math-block / .math-inline / .math-source / .katex` 配套样式。

**定性随之改变**：这不是「要不要发明一个新功能」，而是 **1:1 复刻缺口**——与此前各审计波次的差距项同类。用户从原版导入带公式的备忘到 Rust 版，公式会从排版形态退化为满屏 `$…$` 原码（见 §1）。

## 1. 现状取证

### 1.1 Rust 版当前如何渲染公式（代码路径确定性结论）

- `rust/apps/web/src/blocks.rs` 的 `looks_like_markdown` 明确**不含**数学门控，函数注释自述：「数学公式（hasMathSyntax）属 KaTeX 立项范围，不在此门控内」。全文检索 `blocks.rs` 无任何 `$` 定界处理（`parse_inlines` 无 math 分支）。
- 因此公式段落只有两种下场：
  1. **纯公式段**（如 `$$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$$`、含 `\frac/\sqrt/\sum/\alpha` 的行内混排段）：不命中任何 md 模式 → `md_classify` 返回 None → 按普通可编辑段落原样显示，`$`、`$$`、反斜杠命令全部字面可见；
  2. **同时含其他 md 语法**（粗体、反引号等）的段落：进入 Rich 预览，但 `$…$` 仍被当普通文本分段，公式部分依旧是原码字面（且有被 `^…^` 上标等行内模式误切的风险面）。
- 列表页预览同理走纯文本剥离，显示 `$E=mc^2$` 原码。

### 1.2 原版如何渲染（管线 + 实测输出）

管线（`editor.md.js`）：段落失焦/初次加载走 md 预览时，`preprocessMath` 先行 stash——独占行 `$$…$$` 与任意 `$$…$$` → display 公式；`$…$` 仅当 `looksLikeMathExpression` 命中（单个字母，或含 `\命令`、数字、运算符、希腊字母）才算行内公式（`\$` 转义、普通价格写法由此防误判）；随后 `renderMath` 调 KaTeX 生成 HTML，包 `<div class="math-block" role="math">`（块级，居中、可横向滚动）或 `<span class="math-inline" role="math">`（行内）。

用仓库自带 `vendor/katex.min.js` 在 Node 下以原版同参数实测评估夹具的输出（与浏览器内执行同一份 JS，结果等价）：

| 式样 | 输出字节 | 结构 |
|---|---|---|
| 行内 `\frac{a+b}{2}` | 1,464 B | `.katex` + MathML 并存 |
| 块级 `\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}` | 4,861 B | `.katex-display` + MathML |
| 矩阵 `\begin{pmatrix}…\end{pmatrix}` | 2,423 B | 正常渲染 |
| 未知命令 `\unknowncmd{x}`（throwOnError:false） | 619 B | 仍渲染（红色字形），不崩 |
| 残缺 `\frac{1}{` | 198 B | `.katex-error` 红色原码兜底 |

### 1.3 存储是否有损

**无损（两侧一致）**。公式自始至终以源码形态存于 paragraph 块 `children[0].text`，渲染只是预览层行为：

- Rust：IDB `kv/memos_json` 存 BackupFile JSON 原文；导入 validate-then-swap 不改文本；core 往返验收（真实备份双向无损）已于 2026-11-19/21 多次通过，公式文本只是普通字符串，无特殊风险点。
- 原版：同上（localStorage `memos_app_v2` + IDB 存同一 JSON）。

### 1.4 导出时公式的去向

| 通道 | 原版 | Rust 现行 |
|---|---|---|
| Markdown | 结构化文本语义生成，`$…$` 源码原样保留（export.js 无 math 特殊处理） | 同口径：`memo_to_markdown` 走 plain_text，源码原样保留 ✅ 一致 |
| HTML / PDF | 实时 DOM 快照 → 带 `.katex` 排版 HTML + 应用样式（含 katex 规则）；字体走相对路径 `fonts/…`，导出文件离开应用目录后字体失效、靠 MathML 部分兜底显示（原版固有软点） | 实时 DOM 快照 → 快照里只有 `$…$` 原码文本，导出文档同样是原码 ❌ 与原版分叉 |

### 1.5 取证方式说明（环境限制）

本轮尝试在无头浏览器内做双边同夹具实测（探针 `probe_katex_eval.mjs` 已备，IDB/localStorage 直注 7 段公式夹具：行内混排、块级积分、多行块级、矩阵、希腊+上下标、价格防误判、错误公式容错），但本机沙箱当期资源争用严重：Chromium 启动即 SIGTRAP（日志含 `mmap() failed: Operation not permitted` 与 profile 写拒绝），WebKit 的 WPE/GTK 通道在本单元内亦不可用（无 X、图形栈争用）。故 §1.1/§1.2 的结论来自**两侧完整代码路径 + 原版 KaTeX 本体在 Node 下的实测执行**，均为确定性证据；唯「原版在真实浏览器中的字体加载观感」未在本轮复验（其机制为标准 @font-face 自托管，无悬念）。探针留仓库根，资源恢复后可直接复跑补齐双边 DOM 量测。

## 2. 方案对比

### 方案① KaTeX 官方 JS+CSS+字体自托管（复用原版 vendor 资产）+ 同步 FFI 桥

做法：把原版 `vendor/` 的 KaTeX 0.16.47 三件套原样搬进 `rust/apps/web` 静态资产（版本与原版锁死一致），`index.html` 壳按 Moment.html 同式引入 CSS、JS 用 `defer` 引入；`blocks.rs` 侧：

- **门控层**：`looks_like_markdown` 补 `has_math_syntax`（原版 `hasMathSyntax` + `looksLikeMathExpression` 的手写等价移植，与既有手写模式同风格）；
- **解析层**：`parse_md_blocks`/`parse_inlines` 前加 `preprocessMath` 等价物——先把 `$$…$$`（块级）与合格 `$…$`（行内）stash 成占位段，绕开粗体/上标/wiki 等行内解析，最后还原为公式段（新增 `InlineSeg::Math{tex, display}` 与块级 MathBlock 形态），包装类名与原版逐字一致（`math-block`/`math-inline` + `role="math"`，兜底 `math-source`）；
- **渲染层**：新增同步 FFI 小函数 `katex_render(tex, display) -> Option<String>`——经 web_sys/js_sys Reflect 直调 `window.katex.renderToString`（纯同步函数，原版同参数），结果按 (tex, display) 记忆化（thread_local HashMap）；KaTeX 未就绪/返回 Err → 兜底 `<code class="math-source">`（与原版兜底逐字一致），JS 就绪后靠一次状态刷新换上正式渲染。**不走 eval 异步通道**，避免预览渲染变异步（现行 MdPreview 是同步渲染，异步化会牵动焦点/光标口径）；
- **样式层**：原版 editor.css 的 `.math-*` 四组规则并入 `styles/editor.css`（与既有移植同法）；katex.min.css 由壳 `<link>` 引入，快照导出时其规则随应用样式一并被 `collect_export_assets` 收走；
- **SW**：katex.min.js/css 与字体加入 `sw.js` 预缓存清单（见方案②的精细化口径）。

体积增量（实测原版资产）：

| 资产 | 原始 | gzip | 备注 |
|---|---|---|---|
| katex.min.js | 272,537 B | 76,229 B | defer 加载，不阻塞列表首屏解析；编辑器打开含公式备忘前未就绪时走 math-source 兜底 |
| katex.min.css | 21,693 B | 3,444 B | 壳 link 引入 |
| 字体 20 个 woff2 | 296 KB | ≈原样（woff2 已压缩） | @font-face 按需下载，见方案② |
| **wasm 本体** | **+0** | — | 渲染在 JS 侧，Rust 只加门控/解析/FFI，wasm 增量仅数 KB 级 |

- 离线：资产同源自托管，SW 预缓存后断网可用，与原版一致；
- 编辑态/拼音零影响论证：公式渲染只发生在**预览分支**（与现行全部 md 预览同一门控：聚焦编辑的块走 EditableDiv 源码态，失焦才转预览）；组字（composition）全程在编辑分支内，管线不触碰；点击公式预览回源码编辑的既有机制（MdPreview 点击转编辑）天然复用；
- 导出：快照天然带 `.katex` HTML 与 katex CSS 规则，与原版同形态（含同样的相对字体路径软点——与原版一致而非新引入）；
- 变体：可用 crates.io 的 `katex` crate（katex-rs 0.4.6，wasm 下即绑定 JS KaTeX）代替手写 FFI——省一层胶水，但该 crate 停在 2023-02、绑定的是旧版 JS API 形态，且仍需自备 JS 资产；手写 FFI 仅约几十行且与桥既有 web_sys 用法同型，评估倾向手写。

### 方案② 字体子集化 / 预缓存分层（方案①的配套优化，非独立路线）

关键事实：@font-face 字体是**按需下载**的——页面渲染出某字族的字形时浏览器才拉对应 woff2。20 个字体全量自托管的运行时网络成本≈实际用到的几个；全量 296 KB 的真实成本只在 **SW 预缓存**（首次安装占用与更新流量）。

字体用量分层（实测单文件大小）：

- 核心 9（覆盖绝大多数公式）：Main-Regular 26,272 + Main-Bold 25,324 + Main-Italic 16,988 + Math-Italic 16,440 + AMS-Regular 28,076 + Size1 5,468 + Size2 5,208 + Size3 3,624 + Size4 4,928 = **132,328 B**；
- 常用扩展 +2：Math-BoldItalic 16,400 + Main-BoldItalic 16,780 → 累计 **165,508 B**；
- 长尾 9（Typewriter、SansSerif×3、Fraktur×2、Script、Caligraphic×2 ≈ 85 KB）：仅 `\texttt/\textsf/\mathfrak/\mathcal/\mathscr` 触达。

建议口径：SW 预缓存只放核心 9（或 11），长尾字体留在同源静态目录、靠 SW 的 runtime cache 在首次用到时缓存——离线首次用到长尾命令时降级为 MathML/近似字形（KaTeX 的 htmlAndMathml 输出自带 MathML，断网长尾场景仍可读）。相比全量预缓存省约 130–164 KB/版本更新流量。**不建议**做 glyph 级子集化（按语料裁字形）：公式字符集开放，裁剪风险大于收益。

### 方案③ 纯 Rust 数学渲染（LaTeX → MathML）

候选（crates.io 实查）：

| crate | 版本 | 状态 | 形态 |
|---|---|---|---|
| pulldown-latex | 0.8.0 | 活跃维护，113K 下载 | LaTeX 解析 → MathML Core 输出 |
| latex2mathml | 0.2.3 | 2020 年后未更新，136K 下载 | 同上，覆盖更窄 → 排除 |
| katex（katex-rs） | 0.4.6 | 2023-02 后未更新 | 实为方案①的绑定变体，见上 |

- 体积：零 JS、零字体；wasm 增量为解析器本体，量级估计 80–200 KB（需 spike 实测确认，本评估未构建验证）；
- 离线：天然全离线，无 SW 资产问题；
- 接入点与①相同（门控+stash 层完全复用），仅渲染层换成 Rust 函数直出 MathML 字符串——实现上反而更顺（纯同步、无 FFI、无就绪竞态）；
- **致命短板是保真度**：输出是浏览器原生 MathML 渲染（系统数学字体，如 iOS 的 STIX 类字体），与原版 KaTeX 的字形、间距、分数/根号形态肉眼可辨地不同——直接违背本项目「与原版 1:1」的红线；且命令/环境覆盖窄于 KaTeX（矩阵环境、\dfrac、\boxed 等长尾覆盖需逐项验证，超纲部分的行为与原版的红色兜底也不一致）；导出快照带的是 MathML（在导出文档里反而更通用，但与原版导出的 .katex 形态分叉）。

## 3. 风险与成本

| | 方案①（+②分层） | 方案③ pulldown-latex |
|---|---|---|
| 工时量级 | 约 1–2 天：门控/stash 移植半天、FFI+记忆化+兜底半天、CSS/SW/资产接线与导出核对半天、冒烟+探针半天 | 约 1–2 天：门控/stash 同左、渲染接线半天、覆盖度逐项对照与降级口径 1 天起（不确定性高） |
| 主要风险 | 渲染路径纪律：FFI 必须在 katex 缺失时静默兜底、绝不 panic；大量公式备忘的渲染耗时（renderToString 约 0.1–2 ms/式，靠记忆化封顶）；壳脚本加载时序（defer 与首开编辑器的竞态，靠兜底+就绪刷新覆盖） | 保真度不达 1:1（结构性，非调参可解）；覆盖缺口的行为定义；上游版本演进与 KaTeX 语义漂移 |
| 维护成本 | KaTeX 版本与原版锁死 0.16.47，两边同进退；原版已冻结，实际维护≈零 | 跟随 pulldown-latex 升级；与原版 KaTeX 的差异为永久性欠账 |
| wasm/首屏 | wasm +≈0；首屏 +3.4 KB gzip CSS（JS defer 不阻塞，字体按需） | wasm +80–200 KB（估计）；首屏无额外资产 |
| 离线 | 预缓存后全离线（长尾字体 runtime 缓存策略见②） | 全离线 |

## 4. 建议

**建议做，走方案①+②分层预缓存。** 理由：

1. 这是原版已有功能的复刻缺口（§0），不是新增需求——不做，任何带公式的存量备忘在 Rust 版都是原码形态，且导出 HTML/PDF 与原版持续分叉；
2. ①的资产、参数、兜底、CSS 在原版里全部现成，移植路径已被既有 md 管线（stash 门控、失焦预览、快照导出）验证同型，风险集中在 FFI 纪律一点；
3. ③的保真度短板与项目红线冲突，只适合作为「未来若放弃与原版一致」的备选，不适合当下。

若用户决定不做：现状即定版（公式以源码形态显示与编辑，存储与 MD 导出无损），应在差距清单中把本项从「待评估」改为「明确不做」以免反复重提。

### 落地分步计划（若立项）

1. 资产接线：vendor KaTeX 三件套复制为 `rust/apps/web` 静态资产（构建脚本拷贝进 dist 的 `vendor/` 与 `vendor/fonts/`），壳 index.html 加 CSS link + JS defer；`sw.js` 预缓存加 js/css + 核心 9 字体，长尾字体走 runtime 缓存；
2. 门控与解析：`blocks.rs` 移植 `hasMathSyntax`/`looksLikeMathExpression` 门控与 `preprocessMath` stash（块级优先、行内防误判、转义豁免），新增 Math 段类型与 `.math-block/.math-inline` 渲染（点击回源码走既有 MdPreview 通路）；
3. 渲染 FFI：`katex_render` 同步直调 + (tex, display) 记忆化 + `math-source` 兜底 + 就绪后刷新；Diag 加一条 MATH 渲染计数行（沿项目诊断硬规矩）；
4. 样式：原版 `.math-*` 规则并入 styles/editor.css；
5. 回归：新增 `smoke-rustweb-math` 冒烟并入 `run_all_tests.sh`；导出三格式各验一轮（HTML/PDF 带 .katex、MD 留源码）。

### 验收口径（必须全过）

- 式样渲染：分式 `\frac`、根号 `\sqrt`、上下标（`x_1^2`、`\sum_{i=1}^{n}`、`\int_0^\infty`）、希腊字母、矩阵（pmatrix/bmatrix）、大型运算符——块级居中且可横滚、行内与中文混排基线齐；
- 防误判：`售价 $128 元整` 不成公式、`\$` 转义不成公式、`$E=mc^2$` 成公式（与原版同夹具逐项对照一致）；
- 容错：残缺公式与未知命令呈红色原码兜底，不崩、不白块；
- 编辑零回归：聚焦公式段显示源码可编辑、拼音组字全程不被打断、失焦才渲染、点击预览回源码光标落点与既有 md 预览一致；
- 存储与导出：导入→导出 ZIP 往返公式文本逐字一致；导出 MD 源码原样；导出 HTML/PDF 含 `.katex` 结构；
- 离线：SW 预缓存完成后断网打开含公式备忘，核心式样正常渲染；
- 性能：含 50 条公式的备忘打开无可感卡顿（渲染记忆化命中后重渲染不重复调用 KaTeX）。

## 5. 补测（2026-11-22 凌晨实测，Chromium 口径，替换上一版「未跑成」记录）

- 运行口径与时间：2026-11-22 约 00:40 CST，Chromium（playwright-core + chromium_headless_shell-1255），脚本 `probe_katex_eval.mjs`，量测逻辑未改，仅两处通道适配：① Rust 侧地址 8096 → 8126（快照构建，含 KaTeX 实现、视觉对齐与本轮验证中修复的 3 处 core 问题，见下）；② 原版侧种子注入由 localStorage 改为 IndexedDB（MemosDB 的 memos 表）——已实证原版启动时以 IDB 为准并回写覆盖 localStorage，LS 直注会被丢弃（注入后 reload，LS 被种子数据覆盖、夹具不出现），属探针通道问题而非原版行为。原始输出存 `~/workspace/verify-run/katex_eval_out.txt`。
- 注意基线属性：本节 Rust 侧测得的是**立项实现后**的形态（MathML 已落地），不是 §1 描述的实现前原码形态；§1 的实现前结论来自代码通读，仍作历史基线。
- Rust 侧实测：
  - 存储无损：`RUST-STORAGE-LOSSLESS true`（7/7 段逐字一致）。
  - 逐块输出仅捕获 1/7 段：探针的 Rust 逐块提取按 `[data-bid]` 枚举，预览态公式段不带该属性（探针口径），唯一捕获的防误判段 mp6 为可编辑段落（cls `blk-p ed-line`、katex/math 计数全 0、$ 原文保留）。逐块渲染的完整证据见同批 `probe_katex.mjs` 全绿结果（math 元素 10、块级 3、行内 7、mfrac/msqrt/mtable/munderover/msubsup 均出现）。
  - 导出：MD len=428，公式源码原样保留（hasRawDollarTex=true、hasSqrtPi=true）；HTML len=122629，hasMathBlock=true、无 $ 原码残留（hasRawDollarTex=false）；PDF 文档 len=122629（与 HTML 同一快照），hasMathBlock=true、hasFrac=true、无原码残留。
- 原版侧实测：
  - `ORIG-KATEX-VERSION 0.16.47`，字体已加载（fontLoaded=true，KaTeX_Main），存储无损 true。
  - 逐块：行内段每段 katex=3（mathInl=3）；三个块级段各 katex=1（mathBlk=1）；容错段 katex=1、mathInl=2（未知命令式内渲染）。
  - 防误判段（售价 $128…标价 \$9.9）实测：katex=0 但 **mathInl=1**——原版同样把该段一对 $ 消费成行内公式跨度、正文 $ 消失（与 §1/评估期的「原版防误判」预期不同，以本次实测为准）。Rust 实现后该段为 mathInl=0、$ 保留，两侧在此段行为不一致，差异方向是 Rust 更保守。
- 本轮验证顺带修复的 core 问题（已回归全绿）：mathml.rs 一处借用编译错误（E0502）；`\mathbb{R}` 等带括号参数走不到专用字形表（styled_node 未拆 Row 包裹，单测 render_styles_and_color 捕获）；split_math 与 has_math_syntax 的闭定界扫描不跳过 `\$` 转义对，致单个真 $ 与转义 \$ 误配成式（防误判段实测捕获，core 级复现测试确认）。
