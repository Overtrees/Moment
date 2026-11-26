# 审计线 D：Markdown 完整适配核查 + 可优化点

范围：解析器本体 `rust/crates/core/src/md.rs`（全文通读）+ `core/src/mathml.rs`（has_math_syntax / split_math）；Web 消费侧 `apps/web/src/blocks.rs`（InlineSegs / MdBlockView / MdPreview / parse_md_document 缓存包装 / MathSpan / MathBlock）、`editor/model.rs`（materialize_trails / is_list_group_member / flow_runs）、`editor/render.rs`（MdEdit/ActiveEdit 状态机抽查，定案口径未推翻）；原生消费侧 `apps/ios` 的 FFI 三函数与 `MomentApp.swift` 的 MdRender / MdSegsView / MdBlockView / MdPreviewView / EditorModel MD 方法。基准 = 原版 `src/editor/editor.md.js` + `md-blocks.js` + `markdown-bridge.js`（marked v15，gfm + breaks:true，preprocess 扩展：代码保护 → Callout → 公式 → 脚注 → 行内扩展，DOMPurify 收口）。既有定案（audit_md_preview.md：分类判据、光标恒落末尾、尾随空段物化、列表成组、路径 C）不推翻，只核兑现与新问题。证据等级：下述「proven」均为双边代码在手的推演确认，未跑预言机实测的条目已注明。

---

## (a) 完整性：原版语法全集 × 解析 × 双端渲染

图例：✓ 兑现 / ◐ 部分或降级 / ✗ 缺失。

| 语法 | core 解析 | Web 渲染 | 原生渲染 | 备注 |
|---|---|---|---|---|
| ATX 标题 1–6 级 | ✓ | ✓ h1–h6 | ◐ | 原生字号 L1 28 / L2 23 与 Web `--md-heading-h1/h2`（1.75rem/1.4375rem）合；L3 起一律 20，h4 应 17（1.0625rem）、h5/h6 无分级 |
| Setext 标题（===/---） | ✓ 解析层 | ✓ | ✓ | classify 门控不转（与原版 looksLikeMarkdown 无 === 模式一致，测试 m8 已锁） |
| 无序列表（- / * / +） | ✓ | ✓ | ✓ | classify 的 List 类只认 `-`，`*`/`+` 段经 Rich 落解析，渲染等价 |
| 有序列表（. /) 定界、起始号） | ✓ | ✓ `start` 属性 | ✓ start+i | classify 只认 `N. `，`)` 形经 Rich 落解析 |
| 任务列表（- [] / [x] / [X]） | ✓ task_split | ✓ disabled checkbox | ✓ 只读勾选框 | |
| 嵌套列表（缩进子列表挂父项 sub） | ✓ | ✓ li 内嵌 | ✓ sub 递归 | |
| 列表续行 / loose 列表 | ◐ | ◐ | ◐ | 见 (b) R6/R7 |
| 表格（对齐、转义竖线、列数校验） | ✓ | ✓ 对齐 + 完整表样式（th 12px/600/muted、行分隔线、圆角） | ✗ 对齐与样式 | 原生 MdBlockView 不读 JSON 的 `align` 数组、Grid 无分隔线/表头底，见 (c)-4 |
| 引用（多段、懒续行、嵌套块） | ✓ | ✓ blockquote（底色 + 10/14 内边距 + 左线） | ◐ | 原生只有 3px 左线，无 `--md-quote-bg` 底与内边距 |
| Callout 15 类型 → 五系样式/标题表 | ✓ callout_style_title 逐字移植 | ✓ | ✓ | |
| Callout 自定义标题 / 未知类型回退原文 | ✓ | ✓ | ✓ | classify 侧有一处潜伏分叉，见 (b) R9 |
| Callout 折叠（`+` / `-`） | ✓ folding 字段 | ✓ `<details>`（+ 默认开） | ✗ | 原生 MdBlockView 完全不读 `folding`，恒展开、无开合交互 |
| 围栏代码（` ``` ` / `~~~`、语言、未闭合取段尾） | ✓ | ✓ `language-{lang}` 类，无高亮（原版 marked 同样无高亮， parity） | ✓ | 等宽 + codeBg；lang 两边都不可见，一致 |
| 缩进代码（≥4 空格 / tab） | ✓ | ✓ | ✓ | |
| 分隔线 `---` | ✓ | ✓ | ✓ | `***`/`___` 独占段门控不转，与原版一致（M8 定案） |
| 脚注（定义/引用/多引用编号/文末区/回链） | ✓ | ✓ sup 锚点 + section + ↩ | ◐ | 原生引用渲染为正文基线上的 `[n]` 文本；脚注区标签显示内部 id `[fn-1]`（应为序号），无回链 |
| 引用式链接/图片 + 定义抽取 | ✓ C-28 | ✓ | ✓ | 经同一解析树 |
| 块级公式 `$$…$$` | ✓ split_math | ✓ 纯 Rust MathML，失败红源码 + Diag | ✗ | 原生等宽源码（已知降级，FFI 至今无 render_mathml 过桥，见 (c)-6） |
| 行内公式 `$…$`（启发式 + 转义 + 代码保护） | ✓ 与原版逐条对齐 | ✓ MathML | ✗ | 同上；段中 `$$` 在 Web 是块式居中，原生只是行内等宽 run |
| 图片 `![alt](src)` | ✓ | ✓ 白名单 + imgsize 预留几何 + lazy | ◐ | 原生 MdSegsView 把图片切成独立纵排块，行内流排丢失（行内小图会断行）；无白名单校验（整块点按回源码、不打开图片，故无安全后果） |
| 链接（行内/引用/角标 `<url>`/裸 URL/www/邮箱 autolink） | ✓ | ✓ 协议白名单，被拦降纯文本 | ◐ | 原生仅 `_link` + 下划线文本，被 MdPreviewView 整块手势吞掉，不可点（已知分叉，见 (c)-7） |
| wiki 链接 `[[目标\|标签]]` | ✓ | ✓ 可点跳篇（stop_propagation） | ◐ | 原生文本化，不可跳篇（已知分叉） |
| 粗 / 斜 / 三连粗斜 / 嵌套 / flanking | ✓ scan_delim 近似 CommonMark 定界栈 | ✓ | ✓ | |
| 删除线 `~~…~~` | ✓ 内容不二次解析（同原版 stash 口径） | ✓ | ✓ |
| 高亮 `==…==` | ✓ | ✓ span.moment-highlight | ✓ | 原生以 `==` 字面回包 + withRhythm tint 实现，等效 |
| 上标/下标（`^x^`、`^(…)^`、`~x~`、`~(~)~`） | ✓ | ✓ `<sup>`/`<sub>` | ✗ | 原生 runs() 对 Sup/Sub 直接 push 纯文本，无基线偏移/字号缩放（Marks 亦无 baselineOffset 键） |
| 行内代码（等长反引号、内容规范化） | ✓ | ✓ | ✓ | |
| 软换行（breaks:true）/ 硬换行（行尾 2+ 空格） | ✓ Break 段 | ✓ `<br>` | ✓ Break→`\n` | |
| 反斜杠转义 ASCII 标点、`\|` | ✓ | ✓ | ✓ | |
| 原始 HTML 行内（b/strong/u/ins/a/img/br/hr、剥标签留子段、DROP_CONTENT 集） | ✓ C-28 | ✓ | ✓ | 经同一解析树，映射一致 |
| 块级 HTML（`<div>`/`<details>`/`<table>` 等成块） | ✗ | ✗ | ✗ | 解析层无 html block 分支，拍平为段落内文本流，见 (b) R11 |
| 链接 title 属性、`[a](<href>)` 角括号 href | ✗ | ✗ | ✗ | title 丢弃（渲染无感）；角括号 href 见 (b) R5 |
| 列表页摘要剥 MD（stripMarkdownForPreview） | — | ✓ list.rs strip_markdown 逐条移植 | 未核（不在本线范围） | |

解析单点化已兑现：分类/解析只在 core 一处，Web 与 FFI 共用；Web 侧仅余量测包装（md_classify 计数）与内容键缓存（parse_md_document）。编辑器状态机（MdEdit/ActiveEdit 双信号、聚焦不翻预览、失焦两信号清零翻预览、点回源码恒落末尾、列表成组与点击合并回首块）抽查 render.rs / model.rs 均在位，与 audit_md_preview.md 定案一致。

---

## (b) 正确性风险（附可复现样例）

**R1（中，原生）空解析结果无兜底，预览成空白块。**
Web 的 MdPreview 对 `blocks.is_empty()` 有 `<p>{原文}</p>` 兜底；原生 MdPreviewView 直接遍历空数组，渲染空白。
样例：段落全文 = `[^1]: 未被引用的定义`。classify 经 `[^…]` 命中 Rich；解析时定义被抽走、未引用且首行无空白 → 按 marked 吞行口径不回填、无引用 → blocks 为空。Web 显示原文一行；原生什么都不显示（数据未丢，点开源码可见，但用户观感是内容消失）。

**R2（中，双端解析）脚注/链接定义抽取不避围栏与缩进代码。**
`extract_footnotes` / `extract_link_defs` 在文档级先行逐行抽取，不跟踪围栏状态；原版管线是 protectCodeSegments 先把围栏 stash 成 token、定义抽取在其后，故围栏内定义形行不被抽。link_defs 的代码注释自认此取舍，脚注侧同病。
样例：段落 = "```\n[^1]: 不是脚注\n```" → Rust 代码块内容被抽空一行（且该定义进入未引用回填判定）；原版代码块原样保留该行。缩进代码内的定义形行同理。

**R3（低-中，双端）单行 ``` 误转空代码预览。**
classify 的空围栏 guard（C-23）只在 `lines.len() >= 2` 的围栏分支内；单行段落 ` ``` `（trim 后单行）落 looks_like_markdown（任一反引号命中）→ Rich → parse_md_blocks 的 fence_start 命中、取到段尾 → 单个空 Code 块 → 块级空预览。原版失焦 guard 有 `text.trim() === '```'` 专门跳过此形。样例：段落全文恰为三个反引号。注：单行 "```rust" 原版会转空代码块（guard 只挡纯 ```），修复时勿扩大拦截面。

**R4（低，双端解析）引用/Callout 块内的脚注与链接定义不被抽取。**
定义抽取只在文档顶层；块体递归（md_quote_block → parse_md_blocks）不抽定义、也不查块内定义。原版 preprocess 是全文级，定义写在引用内可被引用命中。
样例：`> 引文[^1]\n>\n> [^1]: 出处` → Rust 侧 `[^1]` 无定义命中、按字面渲染；原版成脚注引用（脚注区仍在文末）。

**R5（低，双端解析）角括号 href 不支持。**
`parse_md_link_at` 取首个 `)` 为止且不剥 `<>`：样例 `[文档](<https://example.com/a b>)` → href 解析成 `<https://example.com/a`，Web 渲染再被 safe_http_url 拦成纯文本；marked 支持此形并正常成链。

**R6（低，双端解析）loose 列表被拆成多个列表块。**
parse_md_list 遇项间空行即结束。样例：`- 甲\n\n- 乙` → 两个 List 块（Web 渲染为两个 `<ul>`）；marked 为单个 loose 列表（li 内包 `<p>`）。视觉接近，DOM/间距口径分叉；原生同树同病。

**R7（低，双端解析）列表项内块级内容受限。**
项的缩进行只有「缩进列表行 → 子列表」与「其余 → 续行文本」两路，缩进围栏/引用被 trim 后拼入项文本走行内解析。样例：`- 项\n ```\n code\n ``` ` 不成 Code 块，反引号按行内代码碰运气配对；marked 成项内 `<pre>`。

**R8（低，双端解析）脚注引用 label 被 trim 后命中。**
行内脚注分支 `ctx.foot_ref(label.trim())`：样例 `[^ 1]` + 定义 `[^1]: x` → Rust 成脚注引用；原版 `\[\^([^\]\s]+)\]` 含空格不匹配、保持字面。

**R9（低，潜伏）classify 与 parse 的 Callout 标题解析不一致。**
md_classify 对 `> [!note]标题`（尾巴无空格）把尾巴当自定义标题（tail.trim() 非空即取）；parse 侧 callout_header 按原版正则口径「无空格尾巴不作标题」。当前 classify 的 title 无渲染消费方（Web 只判 is_some、FFI 只回 kind 字符串），尚不构成用户可见 bug；任何将来读 `MdKind::Callout.title` 的消费方接入即成真分叉。

**R10（低，原生性能）mdBlocks 缓存对空结果永不命中。**
`mdBlocks(for:)` 以 `!mdCacheBlocks.isEmpty` 兼作已缓存标志，R1 同触发面的空结果段在每次 body 求值都重新走 FFI 解析 + JSON 解码。mdKind/mdBlocks 共享 mdCacheText 的失效联动本身已核无陈旧读（文本变更两路都会重算）。

**R11（低-中，双端解析）块级 HTML 拍平。**
parse_md_blocks 无 html block 分支：样例 `<details>\n<summary>标题</summary>\n内容\n</details>` 多行段 → 整段按段落收集、标签逐个被行内 HTML 通道剥掉，成「标题 / 内容」文本流；原版 marked 输出 `<details>` 结构（DOMPurify 白名单内、可折叠）。`<div>`、`<table>` 开头段落同理。

**已核无问题（备查）**：
- Web parse 缓存：内容全文作键，天然无失效；48 条 / 512KB 双限、超限整表清空重建；超大文本不入缓存恒真解析。MATH_CACHE 无条目上限、只增不减，长会话内存缓慢增长（低危，列入 (c)-12 顺手项）。
- 尾随空段：Web materialize_trails 与原生 materializeMdTrails 口径对齐（源排除 list 类、next 集合含原子块/divider/列表段/另一预览段、editing 守卫、幂等）。Web 独有文末 TRAIL_END_ATOMIC（文末原子块后补段，含 todo、不含 divider——与 trail_after 的 next 集合刻意不同，原版 init 口径）原生 MD 物化未含此条；原生插入路径有 trailingParagraph 覆盖主要场景，差异仅在「打开存量备忘且文末恰为原子块」时原生不补段，且原生有落焦热区兜底可点，低危。
- 表格后随普通行并入表格行：已被 m3 预言机测试锁定为 marked 口径，非 bug。
- 货币型 `$5 和 $10` 被判公式：原版启发式同行为（内容含数字即真），parity，非分叉。
- 围栏跨段拆分合并 merge_split_fences 只认 ` ``` ` 不认 `~~~`：原版 collectFenceGroup 的 FENCE_RE 同样只认反引号，parity。
- 分类器有序列表 is_num 用 find(". ") 的潜在误判面已逐形核过（「1.5 版本」等形态被「点前须全数字」校验挡住），未发现可复现误判。

---

## (c) 可优化点（按收益排序，前 8 为主清单）

1. **定义抽取避围栏/缩进代码（治 R2）。** 在 extract_footnotes / extract_link_defs 逐行扫描时维护围栏状态（fence 开闭跟踪，与 md_classify 的围栏判定同口径），围栏内行直接 kept；缩进代码行（块首语境）同理。依据：原版 protectCodeSegments 先行保护是既定管线顺序。改动面：core/md.rs 两函数 + 回归测试，中。
2. **单行纯 ``` guard 补齐（治 R3）。** classify 在 Rich 落点前加 `trimmed == "```"` → None（严格只挡纯三反引号形，与原版 guard 字面一致）。改动面：小（数行 + 一条测试）。
3. **Callout 折叠兑现。** MdBlockView 读 `folding`：`-` 默认收起、`+` 默认展开，标题行可开合。注意与 MdPreviewView 整块点按回源码的手势分区——建议折叠型 callout 的标题行点按归开合、正文点按回源码（与 Web details 的 summary 点击语义同构）。改动面：中（单视图 + 手势分区）。
4. **表格对齐与样式兑现。** MdBlockView Table 读 `align` 数组映射列对齐；表头改 12 号 semibold + muted 色、行间加分隔线，对齐 Web `.markdown-render table` 口径（th 12px/600、td/th padding 9/12 的原生等价）。改动面：小-中。
5. **空解析兜底（治 R1）+ 缓存空结果（治 R10）。** MdPreviewView 在 mdBlocks 为空时渲染原文 Text（对齐 Web `<p>{text}</p>`）；mdBlocks 缓存改用独立 hasCache 标志或以 mdCacheText + 独立布尔判定，不以数组空兼任。改动面：小。
6. **公式 MathML 过桥（audit_md_preview 阶段 3 遗留）。** FFI 至今只有 classify/is_block_preview/parse_json 三函数，render_mathml 未过桥，原生公式仍是等宽源码且与普通代码无视觉区分。建议 FFI 加 `render_mathml(tex, display) -> String`（core 现成、失败回空串），原生 Math 段以一只共享 WKWebView 渲染 MathML 片段（公式数量少、离流嵌入）；若暂不做 WebView，至少把原生公式源码改成 Web 失败态同款的红色 `.math-source` 语义色，先把「这是公式」区分出来。改动面：中（FFI 一函数 + 绑定重生成 + 原生渲染分支）。
7. **预览内链接 / wiki 逐个点按。** Web 已兑现（wiki 点按跳篇且 stop_propagation、链接打开、白名单在渲染层）。原生需把 MdPreviewView 的整块 onTapGesture 改为分段手势：MdSegsView 文本段用带 `.link` 属性的 AttributedString + 链接点按回调（wiki 走既有跳篇通道、http 走 openURL 且过 safe 口径），非链接区域保留整块回源码。改动面：中。
8. **上下标基线 + 脚注呈现三件。** Marks.attributed 增加 `sup`/`sub` run 键（baselineOffset ± 0.35em 左右 + 字号 0.75 缩放），MdRender 传键；脚注引用改上标数字样式；脚注区标签按 items 下标显示序号（1、2…）替代内部 id 文本。改动面：小（三处同批）。

其余优化项：

9. **标题分级补齐**：h4 = 17、h5 ≈ 13、h6 ≈ 11（或按 Dynamic Type 比例缩放），与 Web h1–h4 token 对齐。改动面：小。
10. **引用块补底色与内边距**：MdBlockView Quote 加 `--md-quote-bg` 等价底（T 侧已有 quoteBg 近似值需核对）+ 10/14 内边距 + 圆角 10，对齐 `.markdown-render blockquote`。改动面：小。
11. **classify Callout 标题与 callout_header 单点对齐（治 R9）**：md_classify 的 Callout 分支直接复用 callout_header 的尾巴规则（无空格不作标题），消除潜伏分叉。改动面：小。
12. **行内解析的字符集重建 + MATH_CACHE 上限。** parse_inline_chars 每递归层做 chars→String→split_math（内部再 collect chars）→子段 chars 的多次全量拷贝；整篇粘贴型长段（数十 KB 单段）时为可感成本。可让 split_math 直接吃 `&[char]` 免去 String 中转。Web 侧有内容缓存兜底、原生靠 Swift 侧 block 缓存，长段首次解析仍受益。MATH_CACHE 加条目上限（如 256，超限整表清空，与 parse 缓存同策略）。改动面：中 / 小。
13. **块级 HTML 结构保留（治 R11）**：parse_md_blocks 增 html block 分支的评估——至少 `<details>`/`<div>` 块透传成结构段（Web 侧 rsx 直挂、原生侧再议）。与 DOMPurify 白名单对齐的消毒面要一并设计，改动面：大，建议单独立项、先做使用面摸底（存量备忘里块级 HTML 的实际出现率）。
14. **loose 列表与项内块级（治 R6/R7）**：parse_md_list 支持空行分隔的 loose 形态合并为单个 List、项内缩进围栏成 Code 子块。marked 口径细节多（loose 的 li 包 p 与现有渲染的间距口径联动），改动面：中，建议与 13 一并排期、非急。
15. **点回源码落点**：恒落末尾是 Web 定案口径（audit_md_preview §2.3），长 MD 段点中间改中间的落差问题只在用户反馈出现时再议，不擅自改口径。

---

## 总评

解析层（core 单点）对原版语法全集的覆盖已近完备：块级十类、行内十七段、脚注/引用定义/HTML 通道/公式切分均有实现且关键口径有预言机测试锁定；Web 渲染端逐项兑现（含白名单降级、公式 MathML、折叠 Callout、对齐表格）。缺口集中在两处：解析层的三个边角（定义抽取不避围栏 R2、单行空围栏 R3、块级 HTML R11）与原生渲染端的保真欠账（折叠 Callout、表格对齐、公式 MathML、上下标、脚注呈现、逐链点按），其中 R1（原生空解析空白块）是唯一可能让用户误以为内容丢失的项，建议优先。
