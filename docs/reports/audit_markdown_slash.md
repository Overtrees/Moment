# 审计：斜杠菜单全项 + 纯文本路径 + Markdown 完整适配（2026-11-22）

> 性质：只审计、不落码。基线 = `audit_slash_md_report.md`（2026-11-21，S1–S15 + M1–M9），本次逐项对**当前**代码与生产复核，不抄旧结论。
> 运行时口径：生产构建 `e5bab8397a`（提交 1ca6b22；2026-11-22 晚 curl 核对线上 sw.js VERSION 一致）。无头 Chromium 无法直连外网（隧道失败），故将生产文件全量镜像至本地静态服务后以 393×852 + hasTouch 隔离档案探针（探针 `probe_audit2/3/4.mjs`）；原版对照以仓库根静态服务打开 `Moment.html` 同口径探针（`probe_audit5.mjs`）。**全部运行时结论为 Chromium 口径**，不代表 iOS 真机。
> 代码引用：原版以文件 + 符号定位（`src/app/editor/commands.js` COMMANDS、`src/app/editor/use-slash.js`、`src/app/editor/slash-model.js`、`src/app/editor/slash-panel.js`、`src/editor/editor.md.js`、`src/editor/md-blocks.js`、`src/app/editor.js`、`src/app/markdown-bridge.js`）；Rust 以文件:行定位（审计时工作树）。

---

## 1. 斜杠菜单逐项盘点（22 项）

原版命令全表在 `commands.js`（含 title/subtitle/keywords/type/pinyin/shortcut/group）；Rust 对应 `editor.rs:49–116` SLASH_CMDS（22 条齐全，字段含 oid）+ `editor.rs:4994–5198` op_convert + `editor/bridge.rs:1090–1290` 行内应用。

| # | 命令（原版 type） | 产物 | Rust 状态 | 差异 |
|---|---|---|---|---|
| 1 | heading 一级标题 | heading level 1 | 已适配 | — |
| 2 | heading2 二级标题 | heading level 2 | 已适配 | — |
| 3 | heading3 三级标题 | heading level 3 | 已适配 | — |
| 4 | paragraph 正文 | paragraph | 已适配 | — |
| 5 | quote 引用 | quote | 已适配 | — |
| 6 | todo 待办事项 | todo（attrs.checked） | 已适配 | — |
| 7 | divider 分隔线 | divider + 尾随空段 | 部分适配 | op_convert divider 臂不查「下一块已是空段」便插入尾随段（原版 use-slash 应用逻辑有此检查，callout/todo 臂 Rust 有、divider 臂漏）；见 §3 智能前缀侧另一处分叉 |
| 8 | inline_bold 加粗 | `**选区**` 字面包裹 | 部分适配 | 选区首尾空格未外置，见 §2-④ |
| 9 | inline_italic 斜体 | `*选区*` | 部分适配 | 同上 |
| 10 | inline_highlight 高亮 | `==选区==` | 部分适配 | 同上（空格同理） |
| 11 | code_block 代码块 | paragraph + ``` 围栏源码 | 部分适配 | 围栏固定三反引号、正文含 ``` 时不加长（S12 残留，§2-③）；转换前 strip_md_prefixes 剥行首前缀，原版用 cleanedText 原样入围栏 |
| 12 | unordered_list 无序列表 | paragraph + `- ` 源码 | 部分适配 | 功能在；仅搜索面缺 type 名（S10，§2-①） |
| 13 | ordered_list 有序列表 | paragraph + `1. ` 源码 | 已适配 | （搜索面同 12） |
| 14 | callout 标注块 | callout | 已适配 | 折叠形/默认标题与原版一致 |
| 15 | img_text_card 图文卡片 | imgTextCard 占位块 + 尾随段 | 已适配 | 占位文案与 attrs{fileId:''} 与原版一致（S6 已修） |
| 16 | image_text_row 图文混排 | imageTextRow 占位块 + 尾随段 | 已适配 | 同上 |
| 17 | inline_link 链接 | 链接表单 → `[文字](url)` | 部分适配 | 表单 Enter 不提交（§2-⑥，运行时实证）；URL 中括号不转义 %28/%29（原版 use-slash 插入时转义，Rust 原样存入字面，URL 含 `)` 时再解析断裂） |
| 18 | inline_code 行内代码 | `` `选区` `` | 部分适配 | 空格外置同 8 |
| 19 | inline_strikethrough 删除线 | `~~选区~~` | 部分适配 | 空格外置同 8 |
| 20 | music_card 音乐卡片 | musicCard{url:'',meta:null,status:'input'} | 已适配 | 形状与原版一致（S5 已修） |
| 21 | image 图片 | image 占位块 + 尾随段 | 已适配 | S4 已修 |
| 22 | gallery 画廊 | gallery 占位块 + 尾随段 | 已适配 | S4 已修 |

结论：**22 项功能全部在位，无整项缺失**；差异集中在 6 项的细节层（divider 尾随段检查、行内包裹空格、围栏加长、链接表单/转义、无序列表搜索面）。

面板行为面对照（原版 `use-slash.js` + `slash-panel.js` + `slash-model.js` vs Rust `editor.rs:5599–5929` SlashPanel + `bridge.rs:182–230` stripSlash / `830–880` 触发检测）：

- 已对齐：令牌模型（光标前最后 `/` 起无空白串、按偏移核验后剥离，S1 已修）；任意位置触发与光标锚点定位（S2 已修）；最近使用（cap 6、localStorage 键 `memos_slash_recent_v1` 同名）；点外关闭（S9 已修）；拼音首字母搜索（pinyin 字段进 haystack）；键盘 ArrowUp/Down + Enter + Esc；面板行数 22（运行时实测）。
- 运行时实测面板 computed：z-index **3500**（原版 9999）、max-height **固定 320px**（原版 `min(320px, calc(100dvh - top - 16px))` 按剩余空间动态）、position fixed ✓。原版另有进/出场 opacity/transform 140ms 动画，Rust 面板无进出场动画（挂载/卸载即时）。

## 2. 斜杠残留差异（S10–S14 复核 + 新发现）

① **S10 残留（搜索 type 名缺失）**：SlashPanel 过滤 haystack 用 `c.act`（bulletList/codeBlock 等内部名），SLASH_CMDS 的 `oid` 字段（unordered_list/code_block/inline_bold…，即原版 `cmd.type`）从未进 haystack。运行时实证：搜 `code_block`、`unordered` 均返回空态。原版 haystack = title+subtitle+keywords+**type**+pinyin。

② **S11 残留（排序非拼音序）**：前缀优先组内 Rust 用 `String::cmp` 字节序，原版 `localeCompare(zh-Hans-CN)`。运行时实证：搜「图」Rust = 图文卡片|图文混排|图片|画廊，原版口径应为 图片|图文混排|图文卡片|画廊（前缀组内拼音序）。

③ **S12 残留（围栏不加长）**：op_convert codeBlock 用固定三反引号；原版随正文最长反引号串逐级加长。运行时实证：正文 `a```b` 转代码块后存储为 ` ```\na```b\n``` `，源码结构已损坏（第二行起围栏被正文反引号提前闭合）。

④ **行内包裹空格分叉（新定性）**：原版 use-slash 把选区首尾空格留在包裹标记之外；Rust `bridge.rs` applyInline 按原始 range 包裹。运行时实证：文本 `x ab y` 选区含首尾空格应用加粗后存储为 `x** ab **y` —— CommonMark/marked 下 `** ab **` 不渲染为粗体，且丢失词间空格。该分叉影响 §1 的 8/9/10/18/19 全部行内命令。

⑤ **S13 残留（空态与高亮）**：空态 Rust 只有「无匹配项」四字（运行时实证 hint=false）；原版为「未找到匹配命令」+ 拼音提示 kbd 行（bt/tp/yykp 示例）+ 搜索图标。匹配高亮 `<mark class="slash-match">`：Rust CSS 已备但 SlashPanel 从不发出该元素（运行时实证 mark=false）。注：空态文案键 `slash.no_match`=「无匹配项」与原版「未找到匹配命令」本身也不同字。

⑥ **链接表单 Enter 不提交（新发现，运行时实证）**：Rust 链接态是 div+input，无 form、无 input 的 Enter 处理；桥面板 keydown 以 editableOf 为门，焦点在链接 input 时不进面板 Enter 分支。实测：填入 example.com 后按 Enter，文档无链接插入、面板仍开着。原版为 form onSubmit 提交。鼠标点「插入链接」可用，故定级一般。

⑦ **URL token 误触（新发现，运行时实证）**：桥触发检测只判 query 无空白，无原版的 URL token 排除（token 以 http(s):// 或 www. 开头时不触发）、无 30 字符上限。实测：在段落中手打 `https://abc.com/x`，光标停在末尾时斜杠面板被打开（以最后 `/` 后字符为 query）。粘贴路径不受影响（走粘贴分流），手打 URL 是真实使用路径。

⑧ **S14 残留（面板细节簇）**：行图标 stroke-width 2.5（原版 1.9，运行时实证）；面板键盘无 Home/End（原版有）；hover 不改.sel（行是 Dioxus button、无 pointerenter 接线，鼠标悬停行与键盘选中行可不一致，点击本身可用）；recent pill 渲染在行尾 shortcut 之后（原版在标题 span 内紧随标题文字）；宽度公式 group 加成只给 media 组（原版凡有 group 即 +20，当前视口被 360 上限掩盖，属潜伏差）；z-index/max-height/进出场见 §1 末。

## 3. 普通文本路径

### 3.1 粘贴多行纯文本丢换行 —— 本次审计最严重发现（双侧运行时实证）

同一文本 `- [] 未完任务\n- [x] 已完任务\n\n第二段 **粗体** 测试` 以合成 paste 事件注入：

- **原版**：粘贴后按行拆为独立块（`- [] 未完任务` / `- [x] 已完任务` / 空段 / `第二段 **粗体** 测试`），换行零丢失；失焦后前两块成一个 md 预览，任务列表两项、checkbox 勾选态正确，第三段为行内预览（`<strong>` 正确）。
- **Rust**：粘贴后仍是**单个段落块**，存储文本为 `- [] 未完任务- [x] 已完任务\n第二段 **粗体** 测试` —— 第一个换行**丢失**（两行黏连），仅空行处保留一个 `\n`；其 md 预览随之坏死：任务列表合并成一项，文本为「未完任务- [x] 已完任务」。

机制（代码+DOM 实证）：Rust 桥粘贴走 execCommand('insertText') 插入**每块一个的 `<div>` 宿主**，Chromium 把换行生成为 `<div>` 行元素（粘贴后块 DOM 实测为 `- [] 未完任务<div>- [x] 已完任务</div><div><br></div><div>第二段…</div>`）；随后 pasteSync 的 HTML→inlines 转换（`crates/core` editor_html_to_inlines）只把 `<br>` 映射为 `\n`，**块级 `<div>` 边界不产出 `\n`**（首个边界直接黏连）。原版宿主结构下 parseEditorDOM 按顶层子元素逐个成块，天然保行。

连带症状：粘贴 `# 标题行\n后面一行正文` 时，Rust 先黏连成一块、再被智能前缀把整块转成 heading（两行并入标题文本）；原版则拆块后第一块转标题、第二块仍为段落。**根因同一处**：粘贴后块/行结构与原版不一致 + HTML 回读丢 `<div>` 边界换行。

另注意口径分叉：Rust 桥粘贴注释自述「多行进当前块成块内换行、不拆块」并称与原版同口径，但原版实测为**按行拆块**——设计口径本身即与原版不同，且实现连自述口径（块内 `\n`）也未达成。

### 3.2 粘贴分流（其余路径与原版同口径，代码核对）

纯 URL → 链接卡 ✓；内嵌媒体 URL → 媒体卡 ✓；内嵌普通 URL（非 md 文本）→ 卡 + 余文成段 ✓；剪贴板图片 → 附件 ✓（`bridge.rs:1006–1090` vs `editor.js:2147–2270`）。Rust URL 判定正则要求带点 TLD 形状，与原版 isUrl 大致等价。

### 3.3 Markdown 快捷转换（智能前缀，输入防抖触发）

原版 `editor.js` PATTERNS（命中文本 trim 后判定）vs Rust `editor.rs:4769–4994` smart_prefix_match / apply_smart_prefix：

| 触发 | 原版 | Rust | 备注 |
|---|---|---|---|
| `# ` / `## ` / `### ` + 空格 | 转 heading 1/2/3 | ✓ | 多行块场景差异见 §3.1 连带症状 |
| `> `（非 `[!`） | 转 quote | ✓ | Callout 形不误触，两边一致 |
| `- [] ` / `- [] ` | 转 todo 未勾 | ✓ | Rust 另含 `- [x] ` 转已勾 todo（原版无此条，属无害扩展） |
| `---` exact | 替换为 divider | 部分 | Rust 命中后**多插一个尾随空段**，原版智能前缀只替换不补段（斜杠应用 divider 两边都补，一致；仅打字路径分叉） |

### 3.4 回车 / 退格逐块型

| 场景 | 原版 | Rust | 判定 |
|---|---|---|---|
| paragraph Enter | 光标处拆块 | ✓ | 一致 |
| paragraph 段首 Backspace | 并入上块 | ✓ | 一致 |
| heading Enter | 整块保留 + 块后插空段 | ✓ | 一致 |
| heading 段首 Backspace | 转段落 | ✓ | 一致 |
| callout Enter | 整块保留 + 块后插空段 | ✓ | 一致 |
| todo/quote 有内容 Enter | 整块保留 + 块后插空段（不拆文本） | 按光标拆为同型新块 | **有意偏离**（主流编辑器口径，前期调优评估结论在案，非缺陷，单列提示） |
| 空 todo/quote Enter | 块后插空段 | 自身转段落退出 | 同上，有意偏离 |
| md 预览块 Enter/空格 | 转源码态编辑 | ✓ | 一致；预览→源码光标落点为块末（第八批双边复测证伪旧「点击处」结论，两边同为末尾） |
| 非段落块段首 Backspace 等 | 删块/聚焦上块末等细则 | ✓ | 与原版 keydown（`editor.js` 2026–2145）逐项核对一致 |

### 3.5 打字实时形态

纯打字保持字面、失焦走 md 预览，与原版同口径。唯一额外行为：Rust 有 `==` 高亮的打字即时转换（realtimeHighlight，输入即变 `<mark>`），原版无此即时转换（高亮只在失焦预览出现）；同步回存储时折为 `==` 字面，存储形态一致，属体验层多出、非缺陷。

## 4. Markdown 完整性矩阵

规格 = 原版管线：`editor.md.js`（marked breaks:true + gfm:true，渲染前预处理：代码保护、Callout、脚注、上下标、==高亮、~~删除、wiki 链接；DOMPurify 消毒 ADD_TAGS input / ADD_ATTR checked/type/open）+ `md-blocks.js`（跨块围栏/列表合并、块级/行内分发）。Rust 对应 `blocks.rs`（md_classify/looks_like_markdown 760–1100、parse_md_blocks/parse_md_document 2714–2929、MdBlockView 2932–3224、InlineSegs 2120–2306）。

场景列：源码编辑态（块内字面编辑）/ 预览（失焦渲染）/ 导出 HTML·PDF（实时 DOM 快照）/ 导出 MD（`export.rs:1119–1260` block_md_str）。

| 元素 | 编辑态 | 预览 | HTML/PDF 导出 | MD 导出 | 备注 |
|---|---|---|---|---|---|
| 标题 # ～ ###### | ✓ | ✓ | ✓ | ✓ | 段内多行 parse 含 setext 标题 ✓ |
| 段落 / 软换行 / 硬换行 | ✓ | ✓ | ✓ | ✓ | breaks 口径对齐 |
| 粗体 / 斜体 / 行内代码 | ✓ | ✓ | ✓ | ✓ | 编辑面空格包裹分叉见 §2-④ |
| 删除线 ~~ / 高亮 == | ✓ | ✓ | ✓ | ✓ | 预览带 mynote-strikethrough / mynote-highlight 类，与原版一致 |
| 上标 ^()^ ^x^ / 下标 ~()~ ~x~ | ✓ | ✓ | ✓ | ✓ | M7 已修 |
| 链接 [t](u) / <url> / 裸 URL / 邮箱 | ✓ | ✓ | ✓ | ✓ | **href 未消毒**：blocks.rs 无 javascript:/data: 协议过滤，原版经 DOMPurify 剥离；危险 href 会随 DOM 快照进导出 HTML（影响低） |
| 图片 ![alt](url) | ✓ | ✓ | ✓ | ✓ | — |
| 引用块 > 多行 | ✓ | ✓ | ✓ | ✓ | — |
| Callout（16 类型→5 风格、折叠 +/-） | ✓ | ✓ | ✓ | ✓ | 折叠 details/summary 运行时实证 ✓（M5 已修） |
| 无序 / 有序 / 任务列表 | ✓ | ✓ | ✓ | ✓ | checkbox disabled、有序 start（运行时实证 ✓）、跨块成组 ✓（M6 已修）；**粘贴入口坏死见 §3.1** |
| 代码块 ``` / ~~~ + 语言类 | ✓ | ✓ | ✓ | ✓ | 未闭合围栏 ✓（M4 已修）；多段落拆分的围栏不跨块合并（原版失焦路径 collectFenceGroup 合并、加载路径亦只替换首段——原版自身口径差，Rust 缺失焦合并侧，边缘项） |
| 表格 | ✓ | ✓ | ✓ | ✓ | 列 align ✓；门控需行内信号（纯表格段不触发预览），与原版 looksLikeMarkdown 门控一致，运行时实证两边同为不触发 |
| 分隔线 --- / *** | ✓ | ✓ | ✓ | ✓ | *** 独占段门控对齐（M8 已修） |
| 脚注（定义/引用/未引用回填） | ✓ | ✓ | ✓ | ✓ | 文末 section + backref ✓（M7 已修）；未引用定义按 marked 链接定义吞行口径分流 |
| Wiki 链接 [[]] | ✓ | ✓ | ✓ | ✓ | — |
| 公式 $ / $$ | ✓ | ✓ | ✓ | ✓ | Rust 原生 MathML 已上线、失败红色原码兜底（KaTeX 立项结论，见 audit_katex_eval.md，本次不重查） |
| **原始行内 HTML**（`<u>` `<kbd>` `<br>` 等） | 字面 | **✗ 字面显示** | ✗ 随预览 | ✓ 原样 | **唯一元素级缺失**：Rust parse 只认 `<https://…>` 角标 autolink，其余原始 HTML 按文本转义；原版 marked 直通 + DOMPurify 消毒后渲染。需段内另有 md 信号触发预览才暴露（如 `带 <u>下划线</u> 与 **粗体**`：原版下划线生效，Rust 显示标签原文） |
| 转义 \* 等 | ✓ | ✓ | ✓ | ✓ | — |

矩阵总评：除原始 HTML 一行外全元素四面齐全；旧审计 M1–M9 全部复核已修（含 M9 落点结论已被第八批证伪并对齐）。导出面结构性口径：HTML/PDF = 实时 DOM 快照（所见即所得，md 段以预览形态导出），MD 文本导出与原版 blockToMarkdown 逐项同构、md 源码段原样透传。

附带运行时观察（未定性）：逐行打字生成两个相邻列表块后，在合成 blur 下未观察到合并为组预览（首块为单块预览、次块仍源码态）；既有冒烟（第八批列表组用例）有成组通过记录，疑为探针 blur 未走完应用失活流程，**记为未证实、不计缺陷**，建议落码批次顺带以真机或冒烟复核。

## 5. Markdown 可优化点

### 正确性

| # | 项 | 证据 | 预期收益 |
|---|---|---|---|
| C1 | 粘贴多行：`<div>` 边界映射 `\n`（或按原版按行拆块，二选一先定口径） | §3.1 双侧实证 + 存储原文 | 粘贴 md 源码/多行纯文本从「黏连坏死」恢复可用；列表/代码/表格粘贴入口打通 |
| C2 | 斜杠 haystack 补 oid（type 名） | §2-① 代码+实证 | `code_block`/`unordered` 等英文词可搜，与原版命中面对齐 |
| C3 | 前缀组内排序换拼音 collation | §2-② 实证 | 中文搜索结果序与原版一致 |
| C4 | codeBlock 围栏按正文最长反引号串加长 | §2-③ 实证（存储损坏形） | 含 ``` 的正文转代码块不再结构损坏 |
| C5 | 行内包裹前选区首尾空格外置 | §2-④ 实证（`** ab **` 存储形） | 含空格选区的粗/斜/删/高亮/代码全部恢复可渲染 |
| C6 | 触发检测补 URL token 排除 + 30 字上限 | §2-⑦ 实证 | 手打 URL 不再误弹面板 |
| C7 | 链接表单 Enter 提交 + URL 括号转义 | §2-⑥ 实证 + 代码 | 键盘流完成链接插入；含括号 URL 不再断裂 |
| C8 | 原始行内 HTML 直通 + href 协议消毒（配套） | §4 矩阵 | 补齐解析覆盖最大缺口；顺带消除危险 href 进导出 HTML |
| C9 | divider 两路径对齐：斜杠臂补 next-empty 检查；智能前缀不补尾随段 | §1-7 / §3.3 代码 | 消除多余空段的存储分叉 |
| C10 | 围栏跨块合并（导入/存量多段围栏） | §4 代码 | 边缘数据形态渲染对齐原版失焦口径 |

### 性能

| # | 项 | 证据 | 预期收益 |
|---|---|---|---|
| P1 | MdPreview 解析记忆化：现每次渲染对同一段落跑 parse_md_document + md_classify 双趟全量解析，无按文本缓存（仅公式有 MATH_CACHE） | blocks.rs / editor.rs 渲染路径代码 | 长备忘、多 md 段场景的滚动与重渲染开销下降；**收益幅度待量测**，建议先加 Diag 计数再定级 |
| P2 | 列表/围栏分组判定在 flow_runs 与渲染层各算一遍，统一一次走查 | editor.rs flow_runs 与 MdBlockView 代码重复 | 微小性能 + 维护性（判定口径单点化，防两处漂移） |

### 体验

| # | 项 | 证据 | 预期收益 |
|---|---|---|---|
| E1 | 空态补拼音 kbd 提示行 + 搜索图标；标题/副标题发 `<mark class="slash-match">` 高亮 | §2-⑤；对应 CSS 类已存在未被使用 | 纯组件侧小改，搜索可发现性与原版对齐 |
| E2 | 面板细节簇：图标 stroke 1.9、Home/End、hover 同步.sel、recent pill 回标题内、进出场 140ms、z-index 9999、max-height 按剩余空间动态 | §1 末 / §2-⑧ | 键盘打开场景（键盘占屏时面板不溢出）、鼠标/键盘选中态一致 |

## 6. 结论摘要（按影响排序）

**部分适配 / 缺失清单：**

1. 粘贴多行纯文本丢首个换行且不拆块，列表/代码/表格粘贴入口坏死（§3.1，双侧实证）。
2. 行内包裹选区空格未外置，五种行内命令对含空格选区产出不可渲染字面（§2-④）。
3. 手打 URL 误触斜杠面板（缺 URL token 排除与长度上限）（§2-⑦）。
4. 链接表单 Enter 不提交（§2-⑥）。
5. 斜杠搜索缺 type 名（S10）+ 排序非拼音序（S11）（§2-①②）。
6. 代码块围栏不加长，正文含 ``` 时存储结构损坏（S12）（§2-③）。
7. 原始行内 HTML 不渲染（唯一元素级缺失）+ href 未消毒（§4）。
8. 空态缺拼音提示/图标、匹配高亮未发 mark（S13）；面板细节簇（S14）；divider 两处尾随段分叉；围栏跨块不合并；链接 URL 括号未转义。
9. todo/quote Enter 拆块口径（§3.4）；`==` 打字即时高亮（§3.5）；智能前缀 `- [x] ` 扩展（§3.3）。

**已确认修复（旧审计）**：S1–S9、M1–M9 全部复核成立（M9 以第八批双边复测结论为准）。

**探针留档**：`probe_audit2.mjs`（面板/搜索/URL/围栏/包裹/链接/md 七例）、`probe_audit3.mjs`（粘贴存储原文 + 块 DOM）、`probe_audit4.mjs`（打字列表成组观察）、`probe_audit5.mjs`（原版同口径对照），均在本仓库根（未跟踪，与既有 probe 惯例一致）。
