# 审计报告：斜杠菜单 + Markdown 渲染（Rust Web 版 vs 原版）

- 日期：2026-11-21
- 范围：编辑页「/ 斜杠菜单 22 条命令逐项」「Markdown 渲染覆盖面」「相关 UIUX 度量」，只读审计，未改应用代码、未重新 build（以当前 dist 为准）。
- 方法：通读原版 `src/app/editor/{use-slash,commands,slash-model,slash-panel}.js`、`src/editor/{editor.md,md-blocks}.js` 与 Rust `rust/apps/web/src/{editor,blocks,list}.rs`；无头双边实测（playwright-core + headless Chromium，视口 393×852 hasTouch）：Rust 版自起服务 8102，原版自起 8103（/Moment.html），未动主线回归的 8096。
- 探针（仓库根，可复跑）：`probe_slash_rust.mjs`、`probe_slash_rust2.mjs`、`probe_slash_orig.mjs`、`probe_slash_orig2.mjs`、`probe_md_rust.mjs`、`probe_md_orig.mjs`。md 边缘用例为自造 ZIP（17 段合成备忘「md边缘」+「目标笔记」），Rust 走 UI 导入流、原版走其自身校验+原子恢复直注，两边同数据。
- 结论计数：**严重 6 · 一般 9 · 轻微 7 · 已对齐 16 项**。KaTeX 按已知待评估项单列（§3.4），不计入问题数。斜杠面板开着时拼音组合输入不安全（编辑态审计 D3）归兄弟审计，本报告不重复计数。

---

## 一、斜杠菜单

### S1 过滤词残渣：应用命令后查询串留在正文里（主流程数据污染）

- 现象：打 `/` + 拼音/关键词筛选再应用命令是斜杠的主用法。Rust 版应用后只删掉 `/` 本身，查询串原样留在块文本中：
- 实测 R1：空块输 `/db` 回车应用「待办事项」→ todo 块 children text = `"db"`。
- 实测 R1b：正文块块首输 `/yy` 点击应用「引用」→ quote text = `"yy正文内容"`。
- 跨类型转换链实测同样中招（残渣文本 `'yydb转换文本'`）。Enter 与点击两条路径皆然。
- 原版：应用时按 token 模型整体删除 `/` + 查询串再套用工厂。实测原版 `/db` 应用待办 → children text = `""`；正文前 `/bt1` 应用标题 → text = `"正文内容"`（无残渣）。
- 证据：原版 `src/app/editor/use-slash.js:518-545`（cleanedText 后 buildReplacementBlock）；Rust `rust/apps/web/src/editor.rs:52`（EDITOR_JS 的 `stripSlash` 仅 `textContent.slice(1)` 删首字符），`editor.rs:463/524` 两处调用均如此。

### S2 触发面与面板锚点：仅块首可触发、面板锚在块底而非光标

- 触发：Rust 的 input 处理要求块文本以 `/` 开头才开面板（`editor.rs:234` `t.startsWith('/')`）。实测：块中（`abc` 之后）打 `/` **不开面板**。原版为 token 模型（光标前最后一个 `/` 起的无空白串，≤30 字符，URL token 排除），任意位置可触发——实测原版块中打 `/` 正常打开。
- 锚点：Rust 面板 top = 块底 + 10。实测十行块、光标在第一行（光标底 181，块底 439）→ 面板 top = 449，离光标 258px。原版公式为光标底 + 10（`use-slash.js` 定位段），同场景实测光标底 181 → 面板 top 191。单行块时两边巧合一致（Rust 实测 panelTop − blockBottom = 10），多行块即暴露。
- 附带：left 亦锚块左缘而非光标左缘（实测面板 x：Rust 12，原版 21，同为单行块场景）。

### S3 行内命令机制分叉：选区包裹失效、无选区无占位文

- 原版行内命令（加粗/斜体/高亮/行内代码/删除线）把**字面标记写回 text**：有选区 → `**选区**` 包裹（前后空格保留在包裹外）；无选区 → 插入 `**文字**` 等占位（占位文「文字」），光标落在包裹后。原版实测：无选区加粗 → text = `"**文字**"`；斜体 → `"*文字*"`；行内代码 → `` "`文字`" ``（`use-slash.js:518-545` 工厂 + INLINE_WRAP_PAIRS）。
- Rust 走 execCommand 路线（`__mnInline`）：实测面板开着选中「词组」点加粗 → DOM 无 `<b>/<strong>`，**未包裹**（stripSlash 先改文本节点、restoreSel 后选区失效嫌疑）；点行内代码 → 仅在光标处插入一对空反引号，不包裹选区。无选区时加粗/斜体/删除线 = 空转无任何插入；高亮 = 插入 ZWSP 的 mark（可继续打字带高亮，此点自洽但与原版 `==文字==` 口径不同）；行内代码无选区插入 `` `` `` 并回退一格。
- 存储口径连带：原版斜杠行内产物是字面 `**文字**` 文本，而 Rust 编辑器对纯行内 md 段落不做预览渲染（见 M1），即原版数据在 Rust 里打开会字面显示 `**`——跨端口径不一致。

### S4 图片/画廊命令不插入占位块，流程分叉

- 原版：应用「图片」立即插入 `{type:'image', attrs:{fileId:''}}` + 尾随空段（实测 doc 与编辑器内 566px 高占位块）；「画廊」插入 `{type:'gallery', attrs:{items:[]}}` + 尾随空段。选图是后续替换占位 fileId 的动作。
- Rust：点击后块数不变、无占位块、面板关闭，直接走文件选择器（MediaReq::Replace）。取消选图即什么都没发生，与原版「先落块、后换图」的模型不同。

### S5 音乐卡片存储形状不一致

- 原版实测：`{type:'musicCard', url:'', meta:null, status:'input'}`，**无 children 键**，后跟尾随空段。
- Rust 实测：`{type, children:[{text}], status:'input', url:''}`——多了 children、**缺 meta:null**。形状与原版工厂不一致，跨端/导出读取时有兼容风险。
- 附记（编辑器范围，仅简记）：原版 input 态是可直接粘贴的 contenteditable 输入胶囊（DOM 实测占位文「粘贴音乐链接到这里...」）；Rust 是 BlockView 胶囊 + 选中后「设链接」prompt，交互路径不同。

### S6 图文卡片/图文混排缺 attrs 且正文处理不同

- 原版工厂实测：`{type:'imgTextCard', children:[{text:'点击输入文字'}], attrs:{fileId:''}}`（图文混排为「点击输入说明文字」），即 children 被固定占位文替换、用户原正文不保留。
- Rust 实测：保留用户正文 children、**无 attrs{fileId:''}**。fileId 缺失影响后续配图替换与导出形状。

### S7 待办转换不补尾随空段

- 原版 `needsTrailingParagraph` 含 todo（`use-slash.js:539`，列表为 divider/musicCard/image/gallery/callout/imgTextCard/imageTextRow/todo，后面已有空段则免）。实测原版应用待办 → `[todo, 空段落]` 两块。
- Rust `op_convert`（`editor.rs:3112`）通用转换路径不补尾随段，实测仅 todo 一块。

### S8 链接表单五处差异 + 取消即关面板 + 校验弱

- Rust 实测：标题「插入链接」（原版「链接地址」）；placeholder `https://`（原版 `https://example.com`）；无预填（原版预填 `https://` 且聚焦全选，实测 focused=true、value=`https://`）；按钮「取消/插入」（原版「取消/插入链接」）；点取消 → **整个面板关闭**（原版实测回到命令列表，rows 恢复）；校验仅 `starts_with http(s)`（原版 URL 解析 + 协议校验，错误文案「请输入有效的 http 或 https 链接」）；无选区提交时 Rust 插入以 URL 为文本的 `<a>`（原版插入 `[链接文字](url)` 字面）。

### S9 点击面板外不关闭

- 实测 Rust：点面板外后 panel 仍在（OUTCLICK panel? true）。原版 document pointerdown 点外即关并恢复选区快照（实测 O10 关闭）。Esc 关闭两边均可 ✓。

### S10 搜索 haystack 缺命令 type：'unordered' / 'code_block' 搜不到

- 原版 haystack = title + subtitle + keywords + **cmd.type**，实测搜 `unordered` → 无序列表，`code_block` → 代码块。
- Rust haystack 用内部 act 名（如 `bulletList`/`codeBlock`），实测这两词**结果为空**。

### S11 搜索排序非中文区域排序

- 原版排序：前缀优先组内 `localeCompare(..., 'zh-Hans-CN')`（`slash-model.js:20`）。实测搜「图」→ **图片 | 图文混排 | 图文卡片 | 画廊**（片 piàn < 文 wén、混 hùn < 卡 kǎ 的拼音序）。
- Rust 为字节序，实测同查询 → **图文卡片 | 图文混排 | 图片 | 画廊**，三项次序皆不同。

### S12 代码块围栏不随正文加长

- 原版：正文含 ``` 时围栏逐级加长（`use-slash.js:514-516`）。实测正文 `a```b` → 存储 ` ````\na```b\n```` `（四反引号）。
- Rust 固定三反引号，正文含 ``` 时源码结构会被误读。

### S13 空态文案与拼音提示缺失

- Rust 空态仅「无匹配项」；原版为「未找到匹配命令」+ 拼音输入提示（kbd 形式，如 bt/tp/yykp 示例）。匹配高亮 `<mark class="slash-match">`：CSS 已逐字移植但 Rust 从不发出该元素（死 CSS）；原版实测搜「图」时行内有 mark 高亮。

### S14 面板细节度量差（汇总）

| 项 | 原版 | Rust |
|---|---|---|
| z-index | 9999（实测） | 3500 |
| max-height | 动态 `min(320px, calc(100dvh - top - 16px))` | 固定 320px |
| 进出场动画 | opacity/transform 140ms | 无 |
| 行图标 stroke-width | 1.9 | 2.5（颜色同为 --color-accent，两边一致） |
| 面板键盘 | Arrow + Home/End + Esc | 无 Home/End |
| hover | pointerenter 改选中行 | hover 不改.sel |
| 最近使用 pill 位置 | 标题 span 内紧随标题文字 | 行尾独立 span（在快捷键提示之后） |
| 宽度公式 group 加成 | 有 group 即 +20（全命令都有组） | 仅 media 组 +20（393 视口下被 240 下限掩盖，两边实测均 360，属潜伏差） |

### S15 类型转换残留空 attrs

- 实测 todo→quote 转换后 Rust 块残留 `attrs:{}`；原版工厂 quote 无 attrs 键。形状洁净度问题，暂未见功能影响。

### 斜杠部分（附证据）

1. **钩子槽位 panic 修复复核通过**：段落→全部 14 条块命令、heading→divider、todo→quote、quote→heading2 等跨类型转换链实测均无 pageerror。原版同路径亦无错误。
2. 22 条命令集合、顺序、分组标题（基础块/媒体块）与原版一致（双边实测行序 act 顺序全等）。
3. 面板基础度量：宽 360、高 320（单行块场景）、圆角 22px、行高 50（min-height 48 + margin 2），两边实测一致。
4. 拼音/关键词主干命中：`fgx`→分割线、`bt`→标题 1/2/3、`yykp`→音乐卡片、`tp`→图片、`list`→无序|有序，双边一致。
5. 最近使用：cap 6、按使用顺序置顶、分组中排除最近项、默认选中首行，双边行为一致（pill 位置差见 S14）。
6. Esc 关闭面板 ✓。
7. divider/heading/quote/todo 基础存储形状与原版工厂一致（尾随段差见 S7、attrs 残渣见 S15）。
8. 深色模式面板度量全等：bg `rgba(28,28,30,0.94)`、文字白、backdrop `blur(28px) saturate(1.35)`，双边实测逐项相同。

---

## 二、Markdown 渲染

对照基准：原版 `src/editor/editor.md.js`（marked GFM + markdown-bridge 预处理 + 行内扩展）与 `src/editor/md-blocks.js`（围栏组/列表组跨块合并渲染）；Rust 为 `rust/apps/web/src/blocks.rs:914` 的 `md_classify` 单块分类 + `MdPreview`（blocks.rs:1087）。以下条目均以同一份 17 段边缘备忘双边实测（段号 e01–e17）。

### M1 纯行内 md 段落永不转预览

- e09「这是 **粗体** 和 *斜体* 与 ~~删除~~ 和 `代码` 以及 [外链](url) 混合」：原版转 `md-preview-inline`，渲染 strong/em/del/code/a 全套；Rust `md_classify` 仅认块级结构，此段返回 None → 永远源码态纯文本，行内 md 字面显示。
- 原版判定含行内模式（`editor.md.js:330` looksLikeMarkdown），Rust 无对应判定。

### M2 预览内部行内 md 不解析

- e07 列表项：原版 `<strong>粗</strong>`、`<code>代码</code>`、`<a>链接</a>`；Rust 列表预览项内字面显示 `**粗**`、`` `代码` ``、`[链接](url)`。
- e08 表格单元格：原版单元格内 strong/code 渲染；Rust 字面。
- 原因：Rust `MdPreview` 的列表项/单元格/标题/引用一律走 `WikiText`（blocks.rs:874，仅切 wiki 链接），无行内 md 解析层。Callout 正文同理（逐行 div + WikiText，原版走完整 markdown）。

### M3 混合结构段落不分类

- e05「# 标题行\n后面一行正文」：原版渲染 h1 + p；Rust 仅认单行标题段 → None，源码态。
- e06「前一行\n- 列表项\n- 第二项」：原版 p + ul 分段渲染；Rust 要求全部非空行同型 → None。
- e16「文字上\n---\n文字下」：原版 marked 按 setext 语义渲染为 h2 + p；Rust None。
- 另：引用懒续行（非全部行以 `>` 起）、表格与文本混排段，Rust 同样 None，原版均可渲染。

### M4 围栏覆盖缺口

- e02 `~~~` 围栏：原版渲染代码块；Rust 不支持（源码态）。
- e17 未闭合围栏：原版渲染代码块；Rust 要求末行恰为 ```（blocks.rs:921-926）→ None。注：fixtures/allblocks.zip 的代码段正是未闭合形，是现成回归用例。
- e01 带语言围栏：两边都渲染，但原版保留 `class="language-js"`，Rust 丢弃语言标记（影响高亮/样式钩子）。

### M5 Callout 折叠形态不支持且标题误作 '-'

- e04 `> [!TIP]-`（折叠形）：原版渲染 `<details class="callout callout-tip callout-collapsible"><summary>`，标题为默认「提示」；Rust 渲染普通 aside，且把 `-` 当作自定义标题（blocks.rs:930-935：`rest[end+1..].trim()` 得 `"-"`）——标题会显示一个减号。`+` 形同理。

### M6 任务列表无 checkbox、有序列表丢 start 与跨块合并

- e10 任务列表段：原版渲染 disabled checkbox（勾选态对应 [x]）；Rust 渲染普通 ul，项内字面 `[] 未完任务`。
- e10+e11：原版把相邻的任务列表段与有序列表段**合并进同一预览块**渲染（md-blocks.js 跨块组），且有序列表保留 `start="2"`（显示 2、3）；Rust 两段各自独立预览，有序列表无 start、从 1 重排。

### M7 脚注与上下标缺失

- e12 脚注：原版渲染脚注引用上标 + 文末 footnotes 区；Rust 源码态字面。
- e13 上标 `x^2^` / 下标 `H~(2)~O`：原版渲染 sup/sub；Rust 源码态字面。

### M8 反向差异：'***' 独占段 Rust 多渲染

- e15 `***` 独占段：原版实测保持纯文本段（无预览）；Rust 渲染为 `<hr>`。此项为 Rust 比原版多渲染，口径仍不一致（Rust 分隔线判定含 `***`/`___` 整段，原版门控更窄）。段中 `---` 的差异归 M3。

### M9 预览→源码切换的光标落点

- 实测原版：点击代码预览后转源码，光标落在点击处附近（focusOffset 1，锚点文本为源码首行起）；Rust：转源码后光标落块尾（实测定版为整块末尾）。焦点本身两边都正确落在源码块内 ✓，仅落点策略不同。

### Markdown 部分（附证据）

1. 基本围栏（``` 起止闭合）渲染为 pre/code，两边一致；代码块计算样式原版实测 bg `rgb(244,244,245)`、字号 13px、圆角 12px，Rust 的 `.markdown-render` 共有选择器声明体与原版 **0 差异**（CSS 逐条比对）。
2. Callout：16 类型→5 风格映射、中文默认标题表、自定义标题，双边一致（折叠形除外，见 M5）。
3. 表格：结构 + 列对齐（left/right）双边一致（单元格行内解析差见 M2）。
4. Wiki 链接含别名：e14 `[[目标笔记|显示名]]` 双边均渲染为 `a.mynote-wiki-link`、`data-note-title="目标笔记"`、显示文本「显示名」，形状全等。
5. 列表卡预览剥 md 口径：同一备忘双边实测预览文本**逐字相同**（含围栏作「代码块」、 `**` 剥离、以及 `> [!WARNING]`/`#` 前缀两边同样保留的现象）——`list.rs` 与原版 stripMarkdownForPreview 在此用例上等价。
6. md 预览 CSS：`.md-preview` 17 条规则选择器与声明体两边全同；`markdown-render` 共有选择器声明体 0 差异。
7. 导出 HTML 中 md 段落呈现：上一批次（差距清单修复）V4 已对齐 exportHeaderMarkup + 双份 CSS 且冒烟通过，本审计未重复全量导出对照，仅沿用该结论（原版导出走 `export.js` 的 renderMarkdownHtml 路径，Rust 侧 md 段落在导出中的行内渲染受 M1/M2 同源限制，建议修复时一并复核）。

### 3.4 KaTeX（已知待评估项，单列）

原版经 markdown-bridge + KaTeX 渲染 `$...$`/`$$...$$`；Rust 未实现，公式源码字面显示。按任务约定单列记录，不计入问题分级，待立项评估。

---

## 三、UIUX 度量对照（汇总）

| 项 | 原版实测 | Rust 实测 | 判定 |
|---|---|---|---|
| 面板宽/高/圆角（单行块） | 360 / 320 / 22px | 360 / 320 / 22px | ✓ 一致 |
| 面板行高 | 50 | 50 | ✓ |
| 面板 z-index | 9999 | 3500 | S14 |
| 面板锚点 | 光标底 +10（top 191 @ 光标底 181） | 块底 +10（top 449 @ 块底 439、光标底 181） | S2 |
| 深色面板 bg/文字/backdrop | rgba(28,28,30,0.94) / 白 / blur(28px) saturate(1.35) | 同左 | ✓ 全等 |
| 代码块 bg/字号/圆角 | rgb(244,244,245) / 13px / 12px | CSS 声明体 0 差异 | ✓ |
| 行图标 stroke-width | 1.9 | 2.5 | S14 |
| 链接表单 | 标题「链接地址」、预填+全选、取消回列表 | 标题「插入链接」、无预填、取消关面板 | S8 |

## 四、修复优先级建议（供主线排期，非本审计结论）

1. S1 过滤词残渣（主流程数据污染，Enter/点击两路）→ S2 触发面与光标锚点 → S3 行内命令字面标记口径。
2. S4/S5/S6 媒体与卡片存储形状对齐原版工厂 → S7 尾随段 → M1/M2 行内 md 渲染层。
3. M3–M7 覆盖面补齐、S8–S15 与 M8/M9 细节收口。

*（本报告由斜杠/Markdown 审计子代理产出；数值均为 2026-11-21 当次无头实测，探针脚本可复跑复现。）*
