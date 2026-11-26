# 确诊：批 2 — 斜杠面板与命令落地（只读确诊，未改产品代码）

- 日期：2026-11-23
- 基准：本地 HEAD `4bf0bfd`；源码 `rust/apps/web/src/editor.rs`、`src/editor/bridge.rs`、`styles/editor.css`、`lang/zh-CN.json`；原版对照 `src/app/editor/{slash-model.js,slash-panel.js,use-slash.js}`。
- 口径对齐：landing_plan 批 2 表共 **14 行**（D-2、D-3、D-4、D-5、D-25、D-24、D-8、D-6、D-7、D-10、D-11、D-12、D-13、D-14+MD-C9）。任务所称「余 13 项」应是已把 D-8 计为 #12 斜杠定位批（3c42d54）处理——但 D-8 只落了三分之二（见该项），故本报告 14 行全诊，计数如下。
- **结论汇总：完整仍成立 12 项；部分成立 2 项（D-8、D-10）；全消 0 项。**

| 编号 | 判定 | 落点一句话 |
|---|---|---|
| D-2 | 仍成立（proven） | haystack 用 `c.act` 不用 `c.oid`，editor.rs:6271 |
| D-3 | 仍成立（proven） | 前缀组内 `String::cmp` 字节序，editor.rs:6288 |
| D-4 | 仍成立（proven） | 行渲染从不发 `<mark>`，editor.rs:6359-6367 |
| D-5 | 仍成立（proven） | 空态只有一行文案、键值未改，editor.rs:6380 / zh-CN.json |
| D-25 | 仍成立（proven） | 图标 stroke_width "2.5" + accent 色，editor.rs:6356 |
| D-24 | 仍成立（proven） | recent pill 在行尾 shortcut 之后，editor.rs:6371 |
| D-8 | 部分成立 | max-height 动态 + visualViewport 已落（3c42d54）；z-index 仍 3500，editor.css:1437 |
| D-6 | 仍成立（proven） | 无 listbox/option/activedescendant/dialog 语义，editor.rs:6337 起 |
| D-7 | 仍成立（proven） | 无 Home/End、无 hover 同步、aria-selected 不随导航，bridge.rs:732-757 |
| D-10 | 部分成立 | 取消回列表已对齐；Enter 提交/type=url/aria/括号转义仍缺 |
| D-11 | 仍成立（proven） | 转换后焦点落全文/源码末尾，editor.rs:5811 / 1913 |
| D-12 | 仍成立（proven） | 图文卡/混排焦点指向卡片块本身，editor.rs:5811 |
| D-13 | 仍成立（proven） | 围栏固定三反引号 + 先剥前缀，editor.rs:5737 / 5706 |
| D-14+MD-C9 | 仍成立（proven） | divider/图片/画廊/智能前缀四路均无 next-empty 检查 |

---

## D-2（≡ MD-C2 / S10）过滤 haystack 以内部名 act 代替原版 type

- 原述：搜 `code_block`/`unordered`/`ordered` 无命中，因 haystack 用内部 act 名而非原版 type（oid）。
- 落点：`editor.rs:6271-6279` —— haystack = 本地化 title + sub + `c.kw` + **`c.act`** + `c.py`；`SLASH_CMDS` 的 `oid` 字段（editor.rs:64-86，如 bulletList 的 oid="unorderedList"、codeBlock 的 oid="codeBlock"）从未进 haystack。原版 `slash-model.js:14` haystack 含 `cmd.type`。
- 判定：**仍成立，proven（代码确定性）**。`code_block` 含下划线，与 "codeblock"（act 小写）永不包含匹配；`unordered` 在 act="bulletlist"、kw 中均不存在。附带：editor.rs:6246-6251 的移植注释自述 haystack 含「type」，与代码不符（注释/代码漂移，同根）。
- 根治落法：haystack 的 `c.act` 换/补 `c.oid`（一行），注释同步订正。
- 改动面：极小（editor.rs 一处）。冲突：editor.rs 为批 2/4/5/6 串行文件，与本批其余项同文件同批落最省。

## D-3（≡ MD-C3 / S11）前缀组内排序用字节序而非拼音 collation

- 原述：前缀优先组内用字节序，原版 `localeCompare(zh-Hans-CN)`；搜「图」序应为 图片/图文混排/图文卡片/画廊。
- 落点：`editor.rs:6281-6290` —— 前缀判定后 `.then_with(|| i18n::t(a.title).cmp(i18n::t(b.title)))`，`String::cmp` 为 UTF-8 字节序。原版 `slash-model.js:20` 为 `a.title.localeCompare(b.title, 'zh-Hans-CN')`。
- 判定：**仍成立，proven（代码确定性）**。字节序下「图」组 = 图文卡片/图文混排/图片/画廊，与规格序不符（卡<混 为字节序、混<卡 为拼音序；片>文 为字节序、片<文 为拼音序）。
- 根治落法：排序改为经 JS `localeCompare(..., 'zh-Hans-CN')` 口径——渲染在 Rust 侧，需以预计算拼音键或调 web_sys 的 JS String localeCompare 实现等价排序，落码时定实现形。
- 改动面：小（editor.rs 排序一处；若引入拼音键生成则中）。冲突：同 D-2 同函数区（6264-6295），宜同笔。

## D-4（≡ MD-E1 高亮部分 / S13）匹配高亮未实现

- 原述：从不发 `<mark class="slash-match">`，CSS 已备、运行时 mark=0。
- 落点：`editor.rs:6359-6367` 行渲染——title/subtitle 均为整串纯文本 span，无命中切分。`.slash-match` 样式在 `styles/editor.css:594` 已备。原版 `slash-panel.js:32` 对 title/subtitle 命中段包 `<mark class="slash-match">`。
- 判定：**仍成立，proven**。
- 根治落法：行渲染按 query 在 title/subtitle 中切分命中段包 mark（大小写不敏感、只首个命中段，原版口径复核后落）。
- 改动面：小（editor.rs 行渲染一处）。冲突：与 D-5/D-24/D-25 同在行渲染区（6337-6383），宜同笔。

## D-5（≡ MD-E1 空态部分 / S13）斜杠空态缺件

- 原述：空态缺搜索图标 +「未找到匹配命令」+ 拼音 kbd 提示行；文案键字面亦异。
- 落点：`editor.rs:6379-6381` 空态只有 `div.slash-empty-state` + `t("slash.no_match")` 一行；`lang/zh-CN.json` 中 `slash.no_match` = 「无匹配项」（原版为「未找到匹配命令」）。CSS 已备未用：`styles/editor.css:596`（`.slash-empty-state > svg`）、597-598（`.slash-empty-hint kbd`）。原版空态全形见 `slash-panel.js:186-195`（28px 搜索 svg + 文案 + 「试试拼音首字母：bt 标题 · tp 图片 · yykp 音乐」kbd 行，role="status"）。
- 判定：**仍成立，proven**。
- 根治落法：空态补 svg 图标 + hint 行（文案走 i18n 新键或既有键扩充）；`slash.no_match` 五包同步改字为原版口径。
- 改动面：小（editor.rs 空态一处 + lang 五包同键——受 i18n 全包同改门禁约束）。冲突：lang 五包与批 12 同文件族，本批内落无交叉；role="status" 顺带补（与 D-6 同面）。

## D-25 斜杠行图标描边 2.5 + 主题蓝

- 原述：行图标 stroke-width 2.5、主题蓝；原版 1.9 + currentColor（path 几何已一致）。
- 落点：`editor.rs:6356` —— `Icon { stroke_width: "2.5", stroke: "var(--color-accent)" }`。原版 `slash-panel.js:112` 为 `SvgIcon(cmd.icon, { strokeWidth: '1.9' })`，颜色随 currentColor。
- 判定：**仍成立，proven**。
- 根治落法：该调用点改 "1.9" + currentColor 口径（一行）。
- 改动面：极小。冲突：与 D-4 同行渲染区，同笔顺带。

## D-24 最近使用 pill 位置

- 原述：pill 原版在标题内紧随标题文字，Rust 在行尾。
- 落点：`editor.rs:6368-6375` —— 行结构为 icon / copy（title+subtitle）/ shortcut / **pill（行尾）**；`.slash-row-title`（6359-6361）内只有 title-text。原版 `slash-panel.js:116` pill 生成于标题 span 内、紧随标题文字。
- 判定：**仍成立，proven**。
- 根治落法：pill 节点移入 `.slash-row-title`、置 title-text 之后（rsx 结构一处）。
- 改动面：极小。冲突：同 D-4/D-25 渲染区同笔。

## D-8（≡ MD-E2 部分）面板定位 — 部分已消

- 原述：max-height 固定 320 靠下溢出、z-index 3500（原版 9999）、定位改用 visualViewport。
- 落点与现状：
  - visualViewport：**已落**——`editor.rs:6153-6164` 视口量取 vv（缺失 fallback inner*）。
  - max-height 动态：**已落**——`editor.rs:6190-6193` 内联 `max-height:min(320px, calc(100dvh - (top+16)px))`，CSS 静态 320 只作兜底。此二子项为 3c42d54（#12 斜杠面板定位批）落地，probe_slash_anchor 已锁。
  - z-index：**未落**——`styles/editor.css:1437` `.slash-panel` 仍 `z-index: 3500`；原版 `slash-panel.js:125` 为 9999。
- 判定：**部分成立**（z-index 子项 proven 仍在；余二子项已消，证据为上述代码现状 + 3c42d54 提交）。
- 根治落法：editor.css:1437 改 9999（一行）。
- 改动面：极小。冲突：styles/editor.css 同时是批 8 主文件——一行改动可随本批先落，批 8 落码时注意勿覆盖；当前并行线对 styles 的改动在 panels.css（备份弹窗 sheetIn），不同文件无冲突。附带观察（inferred，同族登记）：top 上翻判定仍用固定 260 估算高（editor.rs:6184-6187），与动态 max-height（上限 320）口径不完全一致，长列表时翻转时机可能偏差，不扩围、落码时顺带复核。

## D-6 斜杠面板无障碍全套缺失

- 原述：补 listbox/option/activedescendant/aria-label 全套，链接态补 dialog 语义。
- 落点：`editor.rs:6337` 面板 div 只有 id/class/style，无 role/aria-label/aria-activedescendant；行是 `<button aria-selected>`（6339-6342）——aria-selected 挂在 button 上、无 role="option"、无行 id 可供 activedescendant 指向；链接表单（6196-6244）无 role="dialog"/aria-modal/aria-label，input 无 aria-invalid/aria-describedby，错误行无 role="alert"。原版全形：`slash-panel.js:149-152`（role listbox/dialog + aria-label + aria-activedescendant + aria-orientation）、92-94（option + aria-selected + aria-label）、169-170/181（链接 input aria 与 error role=alert）。
- 判定：**仍成立，proven**（仅 pill 的 aria-label 与行的 aria-selected 属性名存在，语义骨架全缺）。
- 根治落法：面板 div 补 role/aria-label/aria-activedescendant（行加 id `mynote-slash-option-{i}` + role="option"，button 改 div 或保留 button 加 role——按原版 React 口径为 div option，落码时定）；moveSel（bridge）同步 activedescendant 与 aria-selected；链接态面板转 role="dialog" + input/error aria 三件。
- 改动面：小-中（editor.rs 两处渲染 + bridge.rs moveSel 一处）。冲突：bridge.rs 与批 1 串行衔接（批 1 已落，当前无在改）；与 D-7 的 aria-selected 同步同点位，宜同笔。

## D-7 键盘导航模型：Home/End、hover 同步、aria-selected 更新

- 原述：无 Home/End；hover 不更新 .sel、Enter 可能应用旧选中项；aria-selected 不随导航更新。
- 落点：
  - `bridge.rs:732-757` 面板 keydown 分支只有 ArrowDown/ArrowUp（moveSel ±1）/Enter/Escape，**无 Home/End**（1475-1501 的 Home/End 是选中块键盘守卫、与面板无关）。原版 `slash-panel.js:63/66` 有 Home/End 跳首尾。
  - hover：editor.rs 行只有 onclick（6344），全仓 bridge.rs/editor.rs 无 mouseenter/mouseover/pointerenter 接线（grep 零命中）；原版 `slash-panel.js:106` onMouseEnter 即 setSlashSelectedIndex。Enter 分支（bridge.rs:738）取 `.slash-row.sel`——悬停不改 sel，Enter 应用的是键盘选中行而非悬停行。
  - aria-selected：由 Rust 按初始 sel 渲染（editor.rs:6342），moveSel（bridge.rs:319-327）只改 class 不动 aria-selected 属性 → 导航后 aria 与视觉脱节。
- 判定：**仍成立（三子项全在），proven**。
- 根治落法：bridge 面板分支补 Home/End（moveSel 扩为可跳首尾）；行加 pointerenter 接线（桥委托或 Dioxus onmouseenter 写回 sel 状态——现 sel 为 DOM class 模型，最省为桥在面板上加 mouseover 委托调 moveSelTo）；moveSel 内同步 aria-selected +（D-6 落地后）activedescendant。
- 改动面：中（bridge.rs 为主 + editor.rs 行属性）。冲突：bridge.rs 当前无并行在改（diag/settings 线不碰 bridge）；与 D-6 同笔最合。

## D-10（≡ MD-C7）链接表单 — 部分已消

- 原述：补 form/Enter 提交、type=url 与 aria、Enter 路径打开的表单取消应回列表而非整关面板；URL 括号转义口径复核。
- 落点与现状：
  - 取消回列表：**已对齐**——`editor.rs:6217-6221` 取消按钮 `link_for.set(None)` 只退回命令列表、面板不关（鼠标/键盘打开同路径）。
  - Enter 提交：**仍缺**——表单是 div+input（6196-6244），无 form、无 input Enter 处理；且 bridge 面板 keydown 以 `editableOf(e)` 为门（bridge.rs:725-727），焦点在链接 input 时整段不入，Enter 无任何效果。
  - type=url 与 aria：**仍缺**——input 无 type 属性（默认 text）、无 aria-label/aria-invalid/aria-describedby。
  - 括号转义：**仍缺**——提交原样传 url（editor.rs:6226-6241），`bridge.rs:1839-1855` `__mnApplyLink` 对 createLink 与字面插入 `[链接文字](url)` 均用原串；原版 `use-slash.js:355` 插入前把 `(`→%28、`)`→%29。含 `)` 的 URL 经字面形落库后按 MD 再解析断裂（审计运行时已实证，本次代码复核同向）。
  - 附带（同族登记）：链接 input 聚焦时 Esc 同样被 editableOf 门挡下——既不回列表也不关面板，与原版 Esc 退回列表口径不符，落码时随 Enter 路径一并处理。
- 判定：**部分成立**（四子项中一已消、三仍在，均 proven）。
- 根治落法：input 补 onkeydown Enter → 走同一提交校验路径（或改 form onsubmit）；input 加 type="url" 与 aria 三件；`__mnApplyLink` 入口对 url 做 %28/%29 转义（与原版同点位）；bridge keydown 门对链接 input 放行 Enter/Escape 并分流（Enter 提交、Esc 回列表）。
- 改动面：中（editor.rs 表单段 + bridge.rs 两处）。冲突：bridge.rs 与 D-7 同文件不同区，可同批串行两笔；editor.rs 表单段与 D-6 的 dialog 语义同段，宜同笔。

## D-11 转换后光标落点

- 原述：原版落 token 起点（md 类加前缀长），Rust 落全文/源码末尾。
- 落点：
  - 一般转换臂：`editor.rs:5810-5811` focus_req = (bid, `plain_len` 全文长) —— 恒落块末。
  - md 源类（列表/代码/Callout）：op_convert 返回 src，调用方 `editor.rs:1905-1916` 以 `len = src.chars().count()` 做 dom_set 落点 —— 恒落源码末尾。
  - 列表项类型互换/提出臂同样落 plain_len 末尾（5656/5683）。
  - 原版口径：`use-slash.js:414-434` 以 tokenStart/tokenEnd 切分，落点为 token 起点（md 类为起点 + 前缀长）；审计已运行时实证。
- 判定：**仍成立，proven**（divider 臂落新段 0、智能前缀路径不在本项范围）。
- 根治落法：落点口径改 token 起点——需要桥在 stripSlash 时把 token 起点偏移随 slashApply 带回（`el.__mnStrip.pos` 已存在于 bridge.rs:316，正是切分起点），Rust 侧 focus 改为 pos（md 类 +前缀长：列表 2/3、围栏首行 4、Callout 首行 9，落码时逐 act 核）。
- 改动面：中（bridge.rs 消息字段 + editor.rs 三臂落点）。冲突：与 D-12 同在 op_convert 焦点语义、同笔处理；bridge.rs 改动与 D-7/D-10 同文件串行排笔。

## D-12 图文卡/混排应用后焦点落空

- 原述：focus_req 指向不可编辑的卡片块本身、落点落空，应落尾随空段。
- 落点：`editor.rs:5791-5811` 一般臂——imgTextCard/imageTextRow 经 apply_type 原地转卡、尾随空段已按 next-empty 规则补好（5796-5807），但 focus_req 设为 (bid, len)，bid 是卡片块本身（原子不可编辑），`__mnFocus` 对其落点无处安放；同臂 musicCard 有胶囊特判（usize::MAX，5810）、todo 落自身正确，唯图文两卡未特判。
- 判定：**仍成立，proven**。
- 根治落法：两 act 的 focus 改落尾随段（i+1 空段 id, 0）——与 divider/媒体占位臂同口径（op_insert_media_placeholder:5626 已是此口径可参照）。
- 改动面：极小（editor.rs 一般臂一处）。冲突：与 D-11 同函数同笔。

## D-13（≡ MD-C4 / S12）代码块围栏不加长 + 先剥前缀

- 原述：正文含 ``` 时固定三反引号被提前闭合、存储结构损坏；Rust 先剥正文 md 前缀、原版保留。
- 落点：`editor.rs:5737` codeBlock 臂 `format!("```\n{plain}\n```")` 固定三反引号，不随正文最长反引号串加长；`editor.rs:5706` 入围栏前 `strip_md_prefixes(&cur_text)` 先剥行首 md 前缀（原版以 cleanedText 原样入围栏）。审计 §2-③ 已运行时实证 `a```b` 转后存储结构损坏。
- 判定：**仍成立（两子项），proven**。
- 根治落法：围栏长 = 正文最长连续反引号串 +1（下限 3）；codeBlock 臂不走 strip_md_prefixes（其余 md 类臂维持——原版仅代码块保留原文，落码时逐臂核 use-slash 口径）。
- 改动面：小（editor.rs md 臂一处）。冲突：与 D-14 同在 op_convert 区段（5630-5813），宜同笔或邻笔。

## D-14 + MD-C9 尾随段检查对齐（四路）

- 原述：图片/画廊下一块已是空段时仍多插一段（D-14）；斜杠 divider 臂漏 next-empty 检查、智能前缀 `---` 多插尾随段（MD-C9）。
- 落点（四路全查）：
  - 斜杠 divider 臂：`editor.rs:5778-5789` 无条件 `d.insert(i + 1, para)`，无 next-empty 检查。列表提出路径的 divider（5671-5679）同形无检查。
  - 图片/画廊（占位路径）：`op_insert_media_placeholder` `editor.rs:5596-5599`（Top 臂）与 Item 臂（5614-5615）均无条件跟一段。
  - 智能前缀 `---`：`apply_smart_prefix` `editor.rs:5471-5482` 替换为 divider 后无条件插空段并聚焦之；原版智能前缀只替换不补段（审计 §3.3）。
  - 对照组（已对齐、勿动）：一般臂 todo/musicCard/imgTextCard/imageTextRow 与 callout 臂均已有 next-empty 检查（5796-5807、5745-5752）。原版总口径 `use-slash.js:546`：trailingBlock 仅在 needsTrailingParagraph 判定需要时才拼入。
- 判定：**仍成立（四路全在），proven**。
- 根治落法：抽一个 next-is-empty-para 判定共用：divider 两臂与媒体占位两臂改「下一块非现成空段才插」；智能前缀 `---` 改不补段、焦点落下一块起点（无下一块时才补——此点 inferred，落码时对原版 editor.js `---` 分支焦点口径复核后定）。
- 改动面：小（editor.rs 三函数）。冲突：与 D-13/D-12/D-11 同文件同区，是本批最先落的天然一笔（纯逻辑、无 CSS/lang 牵连）。

---

## 建议落码序（按改动面与冲突排）

1. **D-14+MD-C9 → D-13**（op_convert 及邻函数纯逻辑，小面、无外部文件牵连；先把存储结构类问题清掉）。
2. **D-12 → D-11**（同函数焦点语义连落；D-11 需 bridge 消息字段加 token 起点，单独成笔便于探针锁落点）。
3. **D-2 → D-3**（过滤/排序同函数区连落；D-3 的 collation 实现形先定）。
4. **D-4 + D-5 + D-24 + D-25**（行渲染区四项同笔；D-5 带 lang 五包同改，单独走 i18n 门禁核对）。
5. **D-7 + D-6**（键盘/hover/aria 一体：bridge moveSel 与面板语义同笔，探针锁 Enter 应用悬停项 + 属性全套）。
6. **D-10**（链接表单：editor.rs 表单段 + bridge 门/ApplyLink，与第 5 笔同文件串行、后落）。
7. **D-8 残项**（editor.css 一行 z-index，可随任意一笔搭车；注意与批 8 的 editor.css 改动错开覆盖）。

## 同族新发现（只登记，不扩围）

- editor.rs:6246-6251 移植注释自述 haystack 含 type，与代码（act）不符——D-2 根治时顺手订正，不单独立项。
- 链接表单聚焦时 Esc 被 bridge editableOf 门挡下无任何效果——已记入 D-10 附带，落码随 D-10 处理。
- 面板 top 上翻估算高 260 与动态 max-height 上限 320 口径差——已记入 D-8 附带观察（inferred），落码时复核。

## 并行冲突总提示

- 本批全部落点只在 **editor.rs / bridge.rs / styles/editor.css / lang 五包**；与当前并行在改的 diag.rs（批 10）、settings.rs + styles/panels.css（备份弹窗线）**无文件重叠**。
- editor.rs 是批 2/4/5/6 的串行共用文件：本批落码期间批 4/5/6 不得同落 editor.rs。
- styles/editor.css 与批 8 交叉：本批只动一行 z-index，先落并在批 8 开工前知会即可。
