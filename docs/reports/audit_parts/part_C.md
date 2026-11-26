# 分片 C 审计：块渲染与 Markdown

覆盖声明：本分片完整通读原版 `src/editor/editor.render.js`（508 行）、`src/editor/md-blocks.js`（155 行）、`src/editor/editor.md.js`（412 行）、`src/app/markdown-bridge.js`（25 行）、`src/utils/preview.js`（72 行）全文；Rust 侧完整通读 `rust/apps/web/src/blocks.rs`（3622 行）、core 相关模块 `model.rs`、`inline_html.rs`、`mathml.rs`（门控/切分部分及模块规格头，其余为 TeX 解析器实现细节）、`lib.rs`，并抽查 `editor.rs` 的编辑态块分发、`list.rs` 的 `strip_markdown`/`summarize` 移植、`icons.rs` 的 Callout 图标、`styles/editor.css` 的块级样式段。只审计，未改任何源码、未构建、未部署。行号以审计时工作区文件为准。

说明：原版的块渲染有两条路径——`renderDocToEditorHTML`（editor.render.js，文档模型 → 编辑区 HTML）与 md 预览路径（md-blocks.js + editor.md.js 的 marked 管线，paragraph 的 children[0].text 存 md 源码、渲染态与源码态切换）。Rust 对应为 `blocks.rs` 的 `BlockView`（只读/非文本块）+ `MdPreview`/`md_classify`/`parse_md_document`（md 源段落）+ `editor.rs` 的编辑态分发。下文逐项注明所比路径。

## 块类型覆盖表

| 类型 | 原版有无 | Rust 有无 | 结论 |
|---|---|---|---|
| paragraph | 有 | 有 | 有差异（C-01、C-02） |
| heading | 有 | 有 | 有差异（C-03） |
| quote（块类型） | 有 | 有 | 有差异（C-04） |
| todo | 有 | 有 | 有差异（C-05） |
| divider | 有 | 有 | 一致（等价差异，C-06） |
| image | 有 | 有 | 基本一致（C-07） |
| gallery | 有 | 有 | 有差异（C-08、C-09） |
| attachment（含文件卡/图片附件） | 有 | 有 | 基本一致（C-10） |
| link-card | 有 | 有 | 有差异（C-11、C-12） |
| musicCard / music | 有（musicCard） | 有（musicCard + music 别名） | 基本一致（C-13） |
| imgTextCard | 有 | 有 | 有差异（C-14） |
| imageTextRow | 有 | 有 | 基本一致（C-15） |
| embedCard | 有（落 `<p>` 兜底） | 无（未知类型兜底） | 基本一致（C-16） |
| 地点（location/place） | 无（五文件中无此类型） | 无 | 一致（双方均无） |
| video（独立块类型） | 无（仅 attachment/BlobMedia 形态） | 有 | 有差异（C-17） |
| callout（独立块类型） | 无（仅 md 语法） | 有 | 有差异（C-17） |
| codeBlock / code（独立块类型） | 无（仅 md 围栏） | 有 | 有差异（C-17） |
| bulleted-list / numbered-list（独立块类型，列表组） | 无（仅 md 语法） | 有 | 有差异（C-17） |
| md 源段落：代码围栏 | 有 | 有 | 基本一致（C-18） |
| md 源段落：列表组 | 有 | 有 | 基本一致（C-19） |
| md 源段落：表格 | 有 | 有 | 一致（C-20） |
| md 源段落：Callout | 有 | 有 | 有差异（C-21、C-22） |
| md 源段落：引用块 | 有 | 有 | 基本一致（C-23） |
| md 源段落：标题/分隔线/setext | 有 | 有 | 一致（C-24） |
| md 源段落：脚注 | 有 | 有 | 一致（C-25） |
| md 源段落：公式（KaTeX / MathML） | 有 | 有 | 有差异（已知取舍，C-26、C-27） |

## 差异与逐项结论

### C-01 paragraph 只取 children[0] vs 全子节点渲染
- 结论：有差异
- 原版：src/editor/editor.render.js:41-43
- Rust：rust/apps/web/src/blocks.rs:338-346、rust/crates/core/src/model.rs:104-115（plain_text 递归拼接）
- 差异：原版 paragraph/heading/quote/todo/imgTextCard/imageTextRow 一律只取 `children[0].text`，第二及后续行内子节点在该渲染路径不输出；Rust `Inlines` 渲染全部子节点、`plain_text()` 拼接全部子节点。现网模型通常为单子节点，故实际影响小，但多子节点（混合标记拆分）文档两边输出不同。
- 严重度：中
- 证据：proven（双方代码直读）

### C-02 paragraph 空态 `<br>` 占位
- 结论：有差异
- 原版：src/editor/editor.render.js:38、42（esc 空文本返回 `<br>`）
- Rust：rust/apps/web/src/blocks.rs:344（`div.blk-p` 内 Inlines，空时无子内容）
- 差异：原版空段落渲染 `<p data-blockid><br></p>` 保高度/可编辑；Rust 只读态为空 div，无 `<br>`。编辑态由 editor.rs 的 EditableDiv 另行处理，不在本项范围。
- 严重度：低
- 证据：proven

### C-03 heading 默认级与级数范围、语义标签
- 结论：有差异
- 原版：src/editor/editor.render.js:44-47（level = attrs.level || 2，无钳制，渲染真实 `<h{level}>`）
- Rust：rust/apps/web/src/blocks.rs:158-163、347-351（heading_level 默认 1、clamp(1,4)，BlockView 渲染 `div.blk-h{lv}` 而非 h1–h6 元素；editor.rs 编辑态同为 div.blk-h）
- 差异：①无 level 时原版 h2、Rust h1 级样式；②原版可出 h5/h6，Rust 钳到 4；③DOM 标签 div vs hN（类名样式等价、语义/无障碍不同）。md 段落内的 ATX 标题 Rust MdBlockView 用真实 h1–h6（blocks.rs:2949-2958），与原版 marked 一致，不在本项。
- 严重度：中
- 证据：proven

### C-04 quote 的 DOM 结构
- 结论：有差异
- 原版：src/editor/editor.render.js:48-50（`<blockquote data-blockid><div>text</div></blockquote>`）
- Rust：rust/apps/web/src/blocks.rs:352（`div.blk-quote` 单层 div）
- 差异：标签与嵌套层级不同（blockquote>div vs div），样式靠 .blk-quote 类对齐，语义标签丢失。
- 严重度：中
- 证据：proven

### C-05 todo 勾选控件形态
- 结论：有差异
- 原版：src/editor/editor.render.js:51-54（`div.editor-todo[data-type=todo]` + 真实 `input.todo-checkbox[type=checkbox]`，带 checked 属性、aria-checked、aria-label=文本、data-checked；外层类 editor-todo/is-checked）
- Rust：rust/apps/web/src/blocks.rs:353-361（BlockView：`div.todo-row(.done)` + `span.todo-checkbox(.on)` + div.todo-text，无 input、无 aria）；editor.rs 编辑态为 `button.todo-checkbox`（editor.rs todo 分支）
- 差异：只读态控件由原生 checkbox 变为 span 绘制，aria-checked/aria-label 缺失；checked 落点同为 attrs.checked（Rust attrs 优先、顶层兜底，blocks.rs:165-168），数据口径一致。
- 严重度：中
- 证据：proven

### C-06 divider
- 结论：一致
- 原版：src/editor/editor.render.js:80-81（`<hr data-blockid>`）
- Rust：rust/apps/web/src/blocks.rs:362（`hr.blk-hr`）
- 差异：仅多一个样式类、无 data-blockid 属性（Rust 块 id 由外层 blk-wrap 的 data-wrapbid 承载，属架构等价差异）。
- 严重度：低
- 证据：proven

### C-07 image 有图/无图形态
- 结论：一致
- 原版：src/editor/editor.render.js:74-79（.atomic[data-type=image]；有图 img 内联 style max-height:668px/radius-22/margin 8px auto/contain；无图 566px 占位盒「📷 点击添加图片」）
- Rust：rust/apps/web/src/blocks.rs:399-419（同 .atomic[data-type=image]；BlobMedia img.blk-media；无图 .atomic-placeholder + i18n media.add_image）
- 差异：像素级尺寸由内联 style 改为 CSS 类（.blk-media/.atomic-placeholder），占位高度不再固定 566px；结构与文案口径一致。
- 严重度：低
- 证据：proven（结构）；inferred（类样式视觉等价性未逐值比对原版 CSS，该文件不在本分片范围）

### C-08 gallery 的 items 数据形态
- 结论：有差异
- 原版：src/editor/editor.render.js:65-73（attrs.items 元素可为对象 `{fileId}`、或 `{url}`、或裸字符串，三者都取 url/fileId 渲染）
- Rust：rust/apps/web/src/blocks.rs:164-172（gallery_items 只收 `as_str` 的字符串项，对象项被 filter_map 丢弃；仅当 items 全军覆没时才回退 children 的 fileId）
- 差异：items 为对象数组（原版 renderAtomic/编辑器实写形态之一）时，Rust 会把非空图库渲染成空态占位——数据形态覆盖缺口。
- 严重度：高
- 证据：proven

### C-09 gallery 空态占位
- 结论：有差异
- 原版：src/editor/editor.render.js:68（空态为 2 列网格双占位格：366px 高、「🖼 点击添加」+「多张图片」）
- Rust：rust/apps/web/src/blocks.rs:420-431（单个 .atomic-placeholder 文案块 media.gallery_empty）
- 差异：空态结构与视觉完全不同（双格网格 vs 单行占位条）。
- 严重度：中
- 证据：proven

### C-10 attachment 文件卡/图片附件
- 结论：一致
- 原版：src/editor/editor.render.js:430-437（renderAtomicHTML：图片附件 .atomic.attachment>img（radius-32、alt=文件名）；文件 .atomic.attachment>.attachment-file（📎 att-icon/att-name/att-hint「点击打开」），无文件条目时名落「附件」）
- Rust：rust/apps/web/src/blocks.rs:564-602（图片 .atomic.attachment>BlobMedia；文件直接 .attachment-file（📎/名/「打开」），名查 manifest attachments 表、节点 name 兜底、再落 i18n「附件」）
- 差异：①文件卡少一层 .atomic.attachment 外包（CSS 有 .editor-body .attachment-file 独立规则，视觉等价）；②BlobMedia 的 img 无 alt 属性（原版 alt=文件名）；③原版文件条目存在但 name 为空时显示空名，Rust 显示「附件」兜底——边界文案微差。
- 严重度：低
- 证据：proven

### C-11 link-card 容器元素与错误态
- 结论：有差异
- 原版：src/editor/editor.render.js:438-450（ready 与 err 均为 `div.atomic.link-card-block / .link-card-err`，不可编辑 div，不整体作链接；err 标题=域名、来源行=完整 URL）
- Rust：rust/apps/web/src/blocks.rs:603-695（ready 与 err 均渲染为 `<a class=link-card-block / a.atomic.link-card-err href=url target=_blank>`）
- 差异：整卡变为锚点（点击行为由「卡内无链接、靠编辑器点击处理」变为整卡跳转）；字段口径（title/subtitle/source/cover、哔哩哔哩不显副标题、cover 走 proxyImg、subtitle 不读 description）经代码注释与实现核对一致。err 态标题/来源行内容一致。
- 严重度：中
- 证据：proven

### C-12 link-card 的 loading 骨架（Rust 多出）
- 结论：有差异
- 原版：src/editor/editor.render.js:438-450（link-card 无 status 概念，无 meta 即 err 卡，无骨架态）
- Rust：rust/apps/web/src/blocks.rs:617-628（status=="loading" 且无标题时渲染 .link-card-skeleton 三行骨架，与 musicCard 骨架同形）
- 差异：Rust 多一个原版 link-card 不存在的中间态；musicCard 的 loading 骨架本身与原版一致（见 C-13）。
- 严重度：低
- 证据：proven

### C-13 musicCard 状态机
- 结论：一致
- 原版：src/editor/editor.render.js:451-478（input 胶囊「粘贴音乐链接到这里...」→ ready 卡（a.music-card-link、封面/标题/副标题/🎵来源）→ loading 骨架（封面 2.4/1 + 75%/50%/35% 三行）→ error 卡（🎵+URL 链接+重试按钮）→ 兜底胶囊（有 url 为 a、无 url 为 div））
- Rust：rust/apps/web/src/blocks.rs:451-563（五态齐全且同序：music-input-pill / a.link-card-block.music-card-link / .link-card-skeleton / .music-card-error+重试（走 CardRetry 上下文）/ a.music-pill 或 div.music-pill；另带 fileId 时走音频附件文件行，原版 musicCard 无此分支但原版 attachment 有同形文件行）
- 差异：兜底胶囊由内联 glass 样式改为 .music-pill 类；ready 卡 rel 为 noreferrer（原版 noopener noreferrer）——等价差异。
- 严重度：低
- 证据：proven

### C-14 imgTextCard 无图占位缺失
- 结论：有差异
- 原版：src/editor/editor.render.js:56-60（无图时 .itc-img-wrap 内 160px 占位盒「📷 点击添加图片」；.itc-text 带 role=button/tabindex/aria-label「查看完整文本」、contenteditable=false）
- Rust：rust/apps/web/src/blocks.rs:696-720（无 fileId 时 .itc-img-wrap 为空，无占位盒；.itc-text 为普通 div + onclick 打开 TextSheet，无 role/tabindex/aria-label）
- 差异：无图时原版有明确占位与点击区，Rust 为空白区；文本点击开面板的行为等价（TextSheet），无障碍属性缺失。
- 严重度：中
- 证据：proven

### C-15 imageTextRow
- 结论：一致
- 原版：src/editor/editor.render.js:61-64（.img-text-row>.itr-img+.itr-text；无图 .itr-placeholder「📷」）
- Rust：rust/apps/web/src/blocks.rs:721-748（同结构；无图 span.itr-placeholder「🖼」）
- 差异：仅占位 emoji 不同（📷 vs 🖼），且 editor.css:71 .itr-placeholder 字号/透明度规则一致口径。
- 严重度：低
- 证据：proven

### C-16 embedCard 与未知类型兜底
- 结论：一致
- 原版：src/editor/editor.render.js:82-86（embedCard 与 default 落 `<p data-blockid>` + 转义文本）
- Rust：rust/apps/web/src/blocks.rs:750-758（未知类型（含 embedCard）落 div.blk-p 纯文本，并记 RENDER diag「unknown block type degraded to text」）
- 差异：标签 p vs div 的等价差异；文本均纯文本呈现、不丢内容。
- 严重度：低
- 证据：proven

### C-17 Rust 独有块类型（callout / codeBlock / bulleted-list / numbered-list / video）
- 结论：有差异
- 原版：src/editor/editor.render.js:40-86（renderDoc 的 switch 无此五类，落 default `<p>` 纯文本）
- Rust：rust/apps/web/src/blocks.rs:363-450、382-398（callout 渲染 .callout 卡、codeBlock/code 渲染 pre.blk-code、bulleted/numbered-list 渲染 .list-wrap/.list-row 自定义列表、video 渲染 .atomic[data-type=video]>video/audio）
- 差异：同一份 doc JSON 在原版编辑器里这些类型只显示纯文本，Rust 显示结构化块。属 Rust 侧扩展（可能源于其他端数据），但与原版渲染语义不一致；其中独立 callout 块的图标为 emoji（⚠💡❗⛔ℹ，blocks.rs:366-370），与 md Callout 的 SVG 图标（C-22）也不同。另 list 块用 div+span.list-marker 模拟列表而非 ul/ol/li。
- 严重度：中
- 证据：proven

### C-18 md 代码围栏
- 结论：一致
- 原版：src/editor/md-blocks.js:6、26-38（collectFenceGroup：``` 起、单段落内已含完整围栏则不再向下收集）；src/editor/editor.md.js:38-84（protectCodeSegments：```/~~~、长度≥开围栏、同字符闭合、引用内围栏剥 > 前缀）；marked 生成 pre>code.language-*
- Rust：rust/apps/web/src/blocks.rs:830-866（md_classify 围栏：首行 ```/~~~、闭合行同字符且长度≥开围栏、未闭合取到段尾）、2380-2405（fence_start/fence_close、语言取 info 首词、反引号围栏 info 含 ` 则无效）、2925-2929（pre>code.language-{lang}）
- 差异：单行形如 ` ```js``` `（整段一行）原版经 marked 可成代码块，Rust md_classify 要求 ≥2 行、parse 层 fence_start 因 info 含反引号拒绝，落普通段落字面——极小边界差异。
- 严重度：低
- 证据：proven

### C-19 md 列表组（md 源段落）
- 结论：一致
- 原版：src/editor/md-blocks.js:7、41-51（LIST_RE = `[-*]\s` 或 `\d+\.\s`，collectListGroup 只并相邻同流段落）；marked 渲染 ul/ol/li、任务项 input[disabled]、嵌套列表进 li、start 属性
- Rust：rust/apps/web/src/blocks.rs:913-944（md_classify 的 List 只认 `- ` 与 `N. `）、2494-2580（parse_md_list：同种标记归组、任务项 [ ]/[x]、缩进嵌套子列表进 sub、续行并入项内）、3010-3070（ol start≠1 时带 start、li 内 input[type=checkbox disabled]）
- 差异：分类层不认 `* `/`+ ` 起始的列表组，但这类段落经 looks_like_markdown 门控落 Rich 后由 parse_md_blocks 的 list_marker（认 -*+ 与 `)` 定界）正确解析，最终呈现一致；`1)` 有序形分类层不认、解析层认，同样经 Rich 兜住。呈现结果等价，路径不同。
- 严重度：低
- 证据：proven

### C-20 md 表格
- 结论：一致
- 原版：src/editor/editor.md.js:330-335 门控 + marked GFM 表格（thead/tbody、对齐 style、单元格行内解析、\| 转义竖线不成格、列数以表头为准补/截）
- Rust：rust/apps/web/src/blocks.rs:976-1015（md_classify 表格须先过 looks_like_markdown 门控——纯表格无行内信号时不转，与原版门控实测对齐，见其 m8 测试）、812-837（split_table_row 处理 \|）、2620-2645 与 3071-3097（table_aligns 列数须相等、th/td 带 text-align style、行补空/截断）
- 差异：未发现。
- 严重度：低
- 证据：proven（双方代码 + Rust 内 m2/m8 预言机回归测试）

### C-21 md Callout 未知类型标题兜底
- 结论：有差异
- 原版：src/editor/editor.md.js:161-162、148-172（CALLOUT_TITLE 无此类型时标题回退为类型原文 rawType，如 `[!FOO]` 标题为「FOO」；样式回退 note）
- Rust：rust/apps/web/src/blocks.rs:798-815（callout_style_title 默认臂返回 ("note","笔记")，未知类型标题恒为「笔记」）
- 差异：未知/自定义 Callout 类型的标题文本不同（原版显类型名，Rust 显「笔记」）。已知 16 种类型的样式/标题映射逐字一致（note/info/todo/abstract/quote→note 等，含 question→warning「问题」、bug→important「问题」）。
- 严重度：中
- 证据：proven

### C-22 md Callout 结构与折叠
- 结论：一致
- 原版：src/editor/editor.md.js:148-172（非折叠 aside.callout.callout-{style}、折叠 details.callout-collapsible（+ 带 open、- 不带）、.callout-header=span.callout-icon(SVG)+span.callout-title、.callout-body 为 marked 递归渲染；图标为 5 套 SVG 路径、stroke 用 var(--md-callout-{style}-icon)）
- Rust：rust/apps/web/src/blocks.rs:2959-2996（同 aside/details 结构、同 open 规则、body 经 parse_md_blocks 递归）、rust/apps/web/src/icons.rs:123-134（SVG 路径与原版逐字相同）
- 差异：未发现（独立 callout 块类型的 emoji 图标问题见 C-17，不在此项）。
- 严重度：低
- 证据：proven

### C-23 md 引用块与失焦门控 guards
- 结论：有差异
- 原版：src/editor/md-blocks.js:100-139（renderSingleParagraph 的 guards 仅失焦路径：BLOCKQUOTE 正文 <2 字符跳过转换、`> [!` 未闭合跳过、空围栏跳过）；marked 引用渲染 blockquote 内段落、懒续行并入
- Rust：rust/apps/web/src/blocks.rs:1017-1045（md_classify Quote：全行 > 起、空行分段）、2570-2595（parse 层懒续行、引用递归 parse_md_blocks）、2949-2951 附近 MdBlock::Quote 渲染真实 blockquote
- 差异：Rust 无「正文 <2 字符不转预览」的失焦 guards 等价物，`> a` 这类极短引用在 Rust 会转预览、原版失焦路径保持源码态；引用内部结构（多段、嵌套块）一致。
- 严重度：低
- 证据：proven（guards 代码）；inferred（Rust 编辑器失焦路径是否另有等价判断未在本分片文件内见，editor.rs 抽查未见）

### C-24 md 标题/分隔线/setext（md 源段落）
- 结论：一致
- 原版：marked 口径（ATX 1–6、闭合 # 剥除、setext =/-、分隔线 -/*/_ 三种）+ editor.md.js:330-335 门控（分隔线只认 `---+` 整行入 commonMarkdown；*** / ___ 独占段不入门控）
- Rust：rust/apps/web/src/blocks.rs:946-975（md_classify Divider 只认 ---，与门控对齐）、2407-2470（atx_heading/setext_level/is_thematic_break 解析层全认）、2830-2865（setext 在段落收集时吸收）
- 差异：分类层与解析层分工不同但门控结论一致（*** / ___ / setext 独占段不转预览，有 m8 测试锁定）。
- 严重度：低
- 证据：proven

### C-25 md 脚注
- 结论：一致
- 原版：src/editor/editor.md.js:174-211（定义行+缩进续行、重复 label 取首个、编号按定义顺序、引用 sup.footnote-ref>a#ref、文末 section.footnotes>ol>li+span.footnote-backlinks（↩ 回链）、未引用定义原文回填文末）
- Rust：rust/apps/web/src/blocks.rs:1590-1680（extract_footnotes 同口径）、footnote_id 同 encodeURIComponent→%换_ 规则、3098-3120（section.footnotes 同结构）、2890-2924（未引用定义按 marked 链接定义吞行口径分流：首行正文单 token 不渲染、含空白才字面回填）
- 差异：未引用定义的回填细节 Rust 按预言机实测复刻，与原版「原文回填后再经 marked」的净效果一致。
- 严重度：低
- 证据：proven

### C-26 公式呈现：KaTeX(HTML+MathML) vs 纯 MathML
- 结论：有差异
- 原版：src/editor/editor.md.js:226-247（katex.renderToString，output:'htmlAndMathml'、throwOnError:false、trust:false、maxExpand:100、maxSize:20；行内 span.math-inline、块级 div.math-block，均带 role="math"）
- Rust：rust/crates/core/src/mathml.rs 全模块（纯 Rust TeX 子集 → MathML）；rust/apps/web/src/blocks.rs:2240-2300（MathSpan/MathBlock：.math-inline/.math-block + role="math"，dangerous_inner_html 注入 MathML；段中 $$ 用 span.math-block 由 CSS display:block 对齐原版 div 几何，editor.css:419-422）
- 差异：呈现技术不同（KaTeX 的 HTML 排版层缺席，靠浏览器原生 MathML 排版，字形/间距与原版有视觉差）——此为用户已拍板接受的 MathML 路线，只记事实。门控/防误判（$$ 成对、$ 同行成对+内容启发式、\$ 转义、代码段保护、$abc$ 不算式）经 mathml.rs:15-135 与原版 editor.md.js:213-275 逐条核对一致。
- 严重度：低
- 证据：proven

### C-27 公式失败兜底形态
- 结论：有差异
- 原版：src/editor/editor.md.js:226-247（KaTeX 在场时非法 TeX 由 KaTeX 自身渲染为红色错误式（throwOnError:false），不是原码；仅 KaTeX 缺失/抛错时落 `<code class="math-source">` 原码，行内还包 span.math-inline、块级包 div.math-block）
- Rust：rust/apps/web/src/blocks.rs:2262-2300（硬错误一律回退 code.math-source 红色原码（editor.css:380 color:#cc0000）；行内错误态为裸 code、无 .math-inline 包裹；块级有 .math-block 包裹）
- 差异：①原版常见错误（未知命令等）在 KaTeX 下是「红色渲染式」，Rust 对未知命令按 mathml.rs 规格同样式内红色呈现命令名续渲（此点一致），但硬错误（括号不配平等）原版仍是 KaTeX 红式、Rust 是红色原码；②行内错误态少一层包裹（样式 .math-source 本身已定义，视觉近似）。
- 严重度：低
- 证据：proven

### C-28 md 行内原始 HTML 不被渲染
- 结论：有差异
- 原版：src/editor/editor.md.js:375-392 + src/app/markdown-bridge.js:9-24（marked 解析原始 HTML 后经 DOMPurify 净化输出，`<b>`/`<sub>`/`<div>` 等白名单内标签真实生效；renderMarkdownHtml 无 marked 时才 fail-closed 转义）
- Rust：rust/apps/web/src/blocks.rs:1700-1960（parse_inline_chars_raw：`<` 仅识别 `<http(s)://…>` 角标 autolink，其余标签字符一律作字面文本进 buf）
- 差异：md 源码里写原始 HTML 的段落，原版渲染标签、Rust 显示标签原文。属解析器子集化的结构性缺口（marked 全集 vs 手写子集的代表项；同类还有引用式链接 `[text][ref]`+定义、缩进代码块、链接标题 title 等 marked 特性未实现，Rust parse_md_link_at 只认 `[text](href)` 直链、href 中空格后 title 被丢弃——丢弃 title 与 marked 渲染结果一致，但引用式链接整体不识别）。
- 严重度：高
- 证据：proven

### C-29 行内扩展语法（~~ / == / 上下标 / wiki 链）
- 结论：一致
- 原版：src/editor/editor.md.js:277-305（preprocessInlineExtensions：~~→del.mynote-strikethrough、==→span.mynote-highlight、^(x)^/^x^→sup、~(x)~/~x~→sub、[[目标|标签]]→a.mynote-wiki-link[data-note-title]；均在 marked 前 stash、内容不二次解析；代码段/链接目标/原始 HTML 属性先行保护，editor.md.js:38-147）
- Rust：rust/apps/web/src/blocks.rs:1440-1470（InlineSeg 枚举 Del/Highlight/Sup/Sub/Wiki 同语义）、1750-1960（parse_inline_chars_raw 同序识别、Del/Highlight 内容不递归、Sup/Sub 内容转义输出）、2030-2060（InlineSegs 渲染：del.mynote-strikethrough、span.mynote-highlight、a.mynote-wiki-link 带 data-note-title 与 title「打开笔记：…」）
- 差异：原版 stash 的是未转义原文直插 HTML（内容含 `<` 时按 HTML 解释），Rust 一律文本转义输出——安全口径更严，纯文本内容呈现一致。另非 md 路径的行内节点高亮：core split_highlight（inline_html.rs:89-110）与原版字面 == 存储口径一致。
- 严重度：低
- 证据：proven

### C-30 URL 安全过滤（safeImageUrl / safeHttpUrl）
- 结论：有差异
- 原版：src/editor/editor.render.js:14-21、440-477（图片 src 只许 http(s) 或 data:image base64，其余置 ''；卡片 href/data-url 只许 http(s)，其余置 ''）
- Rust：rust/apps/web/src/blocks.rs:399-450、603-695（image/video 的 url 分支与 link-card/music 的 href 直接把 extra.url 原样写入 src/href，无协议白名单校验；封面走 proxy_img 代理但原 url 仍作参数）
- 差异：doc JSON 中若含 `javascript:` 等非 http(s) url，原版渲染为空、Rust 原样输出（img src 风险低，a href 的 javascript: 可点触发）。Dioxus 属性转义只防引号逃逸、不防协议。
- 严重度：中
- 证据：proven

### C-31 净化层（DOMPurify fail-closed）
- 结论：一致
- 原版：src/editor/editor.render.js:23-30（sanitizeRenderedHTML：DOMPurify 在场则净化（ADD_TAGS input、ADD_ATTR checked/type/target/rel），缺席则整段转义 fail-closed）；editor.md.js:386-389（md 的 DOMPurify 另 ADD_ATTR open）
- Rust：rust/apps/web/src/blocks.rs 全文（rsx 构建 DOM、文本默认转义，无 marked 式 HTML 注入面；仅 MathML（自研生成器输出）与 Callout SVG 图标（icons.rs 静态串）走 dangerous_inner_html）
- 差异：机制不同（无净化器、靠不产生任意 HTML），净效果等价；Callout 标题/正文均走文本节点转义。
- 严重度：低
- 证据：proven

### C-32 列表预览摘要（preview.js）
- 结论：一致
- 原版：src/utils/preview.js:22-66（summarizeMemoDoc：只取 paragraph 的 children[0].text、标签正则 #[\u4e00-\u9fa5\w-]+ 去重取 3、attachment 计数、stripMarkdownForPreview 后截断 80/60、空预览「无更多文本」）
- Rust：rust/apps/web/src/list.rs:66-105（strip_markdown 逐条移植 editor.md.js:340-373 的替换顺序）、631-661（summarize_uncached 同口径）
- 差异：strip_markdown 已逐条核对替换链顺序一致；summarize 本体未逐行读完，按其注释与 strip 部分推定一致。
- 严重度：低
- 证据：proven（strip 部分）；inferred（summarize 本体）

### C-33 md 门控 looksLikeMarkdown 总口径
- 结论：一致
- 原版：src/editor/editor.md.js:330-338（commonMarkdown 正则集 + hasMathSyntax；含行首 #/列表/>/---、反引号、粗斜体、删除线、链接/图片、==、[[]]、[^]、上下标）
- Rust：rust/apps/web/src/blocks.rs:1050-1180（looks_like_markdown 手写等价：行首模式逐行判、span 扫描各模式、find_md_link、上下标字符集、末尾接 core has_math_syntax）
- 差异：逐模式核对未发现缺项；反引号为「任一即命中」与原版 `{1,3}` 净效果相同。已知反向差（硬换行、有序 `)` 形不入门控）由 m8 测试锁定为与原版一致。
- 严重度：低
- 证据：proven

## 已核一致项清单

1. 块 id 落点：原版 data-blockid ↔ Rust 外层 blk-wrap data-wrapbid / 块 id 信号（架构等价，C-06）。
2. heading level / todo checked / gallery items / imgTextCard·imageTextRow fileId 的存储落点均为 attrs（Rust attrs 优先、顶层兜底，blocks.rs:150-195），与原版 attrs 读法一致（C-05、C-08 的数据口径部分）。
3. paragraph children[0].text 存 md 源码、渲染态/源码态切换模型：Rust MdEdit/ActiveEdit 上下文与 md_classify 门控复刻原版「失焦/初载转预览、点击回源码、编辑中不转」（blocks.rs:14-29、editor.rs paragraph 分支）。
4. md 预览两种形态分发：单段行内内容 → p.md-preview-inline（tabindex/role/aria-label 同原版 markInlinePreview，md-blocks.js:58-65 ↔ blocks.rs MdPreview）；块级 → div.md-preview.block.markdown-render（md-blocks.js:68-79 ↔ blocks.rs MdPreview），类名逐字一致。
5. data-mdtext 源码保存语义：原版 parseEditorDOM 对 contenteditable=false 块以 data-mdtext 还原 paragraph 源码（editor.render.js:392-400、462-463）；Rust 以 doc 模型中 paragraph 的 text 为源码真源、预览为纯视图，净效果一致（模型层不丢源码）。
6. 表格（C-20）、脚注（C-25）、Callout 结构/图标/折叠（C-22）、分隔线/setext 门控（C-24）、门控总口径（C-33）、行内扩展语法（C-29）、musicCard 五态（C-13）、净化净效果（C-31）、列表预览 strip（C-32）。
7. 行内基础格式：粗/斜/粗斜三连、嵌套强调、flanking 防误判、行内代码（等长反引号、内容规范化）、直链/图片、GFM 裸链接与邮箱 autolink、软换行 breaks:true → `<br>`、硬换行、反斜杠转义——Rust parse_inlines 与 marked 口径逐项对齐且有 m1/m2/m3 预言机回归测试（blocks.rs md_render_tests）。
8. 数学门控与防误判（C-26 内列项）逐条一致；Callout 16 种已知类型的样式/默认标题映射逐字一致（C-21）。
9. 空文档兜底：原版 parseEditorDOM 保证 doc 非空（至少一空段落，editor.render.js:475-485）；此为解析路径（分片外 editor.rs 模型层），本分片渲染侧对应物为 MdPreview 空块时落 `<p>{text}</p>`（blocks.rs MdPreview），未见丢空态问题——证据 inferred。
10. 地点类块：双方均无此块类型（覆盖表已列）。
