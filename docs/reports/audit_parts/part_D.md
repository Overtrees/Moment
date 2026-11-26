# 分片 D 审计：卡片与斜杠面板与命令

## 覆盖声明

- 审计范围：斜杠面板（项全集/过滤/分组/键盘/定位/动画）、每一项斜杠命令的落地行为（插入块/光标/源码态）、卡片（链接卡/音乐卡/视频卡/文件卡/地点卡/图片卡）DOM 与行为、图文底表 ImageTextSheet、LazyImage。
- 必读原版文件已**完整通读**（非抽样）：`src/app/editor/slash-model.js`（65 行）、`src/app/editor/slash-panel.js`（199 行）、`src/app/editor/use-slash.js`（740 行）、`src/app/editor/commands.js`（229 行）、`src/styles/cards.css`（147 行）、`src/components/ImageCard.js`（70 行）、`src/components/ImageTextSheet.js`（131 行）、`src/components/LazyImage.js`（42 行）、`src/utils/svg.js`（86 行）。
- 为核对卡片成品 DOM，另完整通读了原版渲染器对应段：`src/editor/editor.render.js:425-502`（link-card/musicCard 原子渲染）、`src/editor/editor.render.js:37-86`（imgTextCard/imageTextRow/gallery/image/embedCard 分支）、原版斜杠/卡片样式真源 `src/styles/editor-shell.css` 对应段。
- Rust 侧已读：`rust/apps/web/src/editor/cards.rs`（268 行，全）、`rust/apps/web/src/icons.rs`（139 行，全）、`rust/apps/web/styles/panels.css`（218 行，全；内无斜杠/卡片规则，斜杠与卡片样式实际在 `styles/editor.css`）、`rust/apps/web/src/editor.rs` 的 SLASH_CMDS 定义（:60-118）、slash_click/link_click 处理（:1766-1860）、handle_bridge_msg 的 slash/slashLink/slashClose/slashApply（:3718-3760）、op_convert/apply_type/op_insert_media_placeholder（:4889-5200）、SlashPanel 组件（:5590-5840）、ImageTextSheet 渲染与 animate_text_sheet_close（:1104-1140、:3320-3385）、`rust/apps/web/src/editor/bridge.rs` 的斜杠检测/面板键盘/stripSlash/applyInline/__mnApplyLink（:185-235、:625-660、:830-870、:1097-1225）、`rust/apps/web/src/blocks.rs` 的卡片渲染（:400-760）、`rust/apps/web/src/list.rs` 的 MemoRow/CoverImg（:955-1170，列表图片卡对应实现）。
- 方法：静态代码逐项对照，未构建、未运行、未部署、未改任何源码。证据分级：proven = 代码原文直接可证；inferred = 由代码路径推断、未经真机/运行验证。
- 严重度口径（按任务）：高 = 项缺失/行为不同；中 = 文案/图标/细节偏差；低 = 等价差异。

## 斜杠项对照表（原版 commands.js 全集 22 项 × Rust SLASH_CMDS）

| # | 项（原版 id / type） | 分组 | 原版（commands.js） | Rust（editor.rs SLASH_CMDS） | 结论 |
|---|---|---|---|---|---|
| 1 | heading / heading L1「标题 1」`# ` | basic | commands.js:4-14 | editor.rs:64 act=heading1 | 一致（落地光标见 D-11） |
| 2 | heading2 / heading L2「标题 2」`## ` | basic | commands.js:15-25 | editor.rs:65 act=heading2 | 一致（光标见 D-11） |
| 3 | heading3 / heading L3「标题 3」`### ` | basic | commands.js:26-36 | editor.rs:66 act=heading3 | 一致（光标见 D-11） |
| 4 | paragraph / paragraph「文本」 | basic | commands.js:37-46 | editor.rs:67 | 一致（光标见 D-11） |
| 5 | quote / quote「引用」`> ` | basic | commands.js:47-57 | editor.rs:68 | 一致（光标见 D-11） |
| 6 | todo / todo「待办」`[ ] ` | basic | commands.js:58-68 | editor.rs:69 | 一致（光标见 D-11；尾随段一致） |
| 7 | divider / divider「分割线」`---` | basic | commands.js:69-79 | editor.rs:70 | 一致 |
| 8 | bold / inline_bold「加粗」`** **` | basic | commands.js:80-90 | editor.rs:71 act=bold | **有差异（D-9）** |
| 9 | italic / inline_italic「斜体」`* *` | basic | commands.js:91-101 | editor.rs:72 | **有差异（D-9）** |
| 10 | highlight / inline_highlight「高亮」`== ==` | basic | commands.js:102-112 | editor.rs:73 | **有差异（D-9）** |
| 11 | codeBlock / code_block「代码块」` ``` ` | basic | commands.js:113-123 | editor.rs:74 | **有差异（D-11、D-13）** |
| 12 | unorderedList / unordered_list「无序列表」`- ` | basic | commands.js:124-134 | editor.rs:75 act=bulletList | 一致（搜索串见 D-2；光标见 D-11） |
| 13 | orderedList / ordered_list「有序列表」`1. ` | basic | commands.js:135-145 | editor.rs:76 act=numberList | 一致（搜索串见 D-2；光标见 D-11） |
| 14 | callout / callout「Callout」`> [!]` | basic | commands.js:146-156 | editor.rs:77 | 一致（光标见 D-11；尾随段一致） |
| 15 | imgTextCard / imgTextCard「图文卡片」 | media | commands.js:157-167 | editor.rs:81 | **有差异（D-12、D-15）** |
| 16 | imageTextRow / imageTextRow「图文混排」 | media | commands.js:168-178 | editor.rs:82 | **有差异（D-12、D-16）** |
| 17 | link / inline_link「链接」`[](url)` | basic | commands.js:179-190 | editor.rs:78 act=link | **有差异（D-9、D-10）** |
| 18 | code / inline_code「代码」`` ` ` `` | basic | commands.js:191-201 | editor.rs:79 | **有差异（D-9）** |
| 19 | strikethrough / inline_strike「删除线」`~~ ~~` | basic | commands.js:202-212 | editor.rs:80 | **有差异（D-9）** |
| 20 | musicCard / musicCard「音乐卡片」 | media | commands.js:213-223 | editor.rs:83 | 一致 |
| 21 | image / image「图片」 | media | commands.js:224-228（无 shortcut 字段） | editor.rs:84 shortcut="" | 一致（占位尾随段见 D-14） |
| 22 | gallery / gallery「画廊」 | media | commands.js:229-（文件尾项） | editor.rs:85 | 一致（占位尾随段见 D-14；画廊成品见 D-17） |

说明：22 项无缺失、无多余；名称/副标题/keywords/pinyin/shortcut 逐项核对一致（Rust 标题走 i18n 键，zh-CN 文案与原版同）。分组归属一致（原版 commands.js 中 link/code/strikethrough 夹在 media 项之间，但 filter 按 group 归组，展示序与 Rust 按组迭代一致）。图标名逐项一致，图标 path 数据逐项一致（见已核一致清单），但描边参数不同（D-26）。

---

### D-1 斜杠触发：URL token 抑制与查询长度上限缺失
- 结论：有差异
- 原版：src/app/editor/use-slash.js:242-277（光标前 token 若为 `https?://…`/`www.…` 则 slashPos=-1 不触发；rawQuery 长度 >30 或含空白则关闭面板；另 :216-222 对音乐输入胶囊内斜杠抑制）
- Rust：rust/apps/web/src/editor/bridge.rs:841-868（input 监听仅判「最后一个 `/` 后无空白」即开面板）
- 差异：在普通块里输入/粘贴 URL（如 `https://example.com/a`）时，Rust 会在第二个 `/` 后以空查询弹出斜杠面板，原版永不弹出；查询超过 30 字符 Rust 仍保持面板，原版关闭。音乐胶囊抑制 Rust 有等价实现（bridge.rs musicInput 分支先行 return），该子项一致。
- 严重度：中
- 证据：proven（两侧代码原文对照）

### D-2 过滤搜索串以 act 代替原版 type，英文 type 词搜不到
- 结论：有差异
- 原版：src/app/editor/slash-model.js:13-15（搜索串 = title+subtitle+keywords+**type**+pinyin；type 如 `ordered_list`、`inline_bold`、`unordered_list`）
- Rust：rust/apps/web/src/editor.rs:5726-5738（搜索串 = 本地化标题+副标题+kw+**act**+py；act 如 `numberList`、`bold`、`bulletList`）
- 差异：查询 `ordered`、`unordered`、`inline` 在原版可命中（type 含该词），Rust 无命中；反之 `bullet`/`number` 仅 Rust 可命中。另外 Rust 用本地化标题入串，非 zh 语言下以中文标题词搜索不再命中（原版标题恒为中文、恒可搜）——此子项为 inferred（取决于当前语言包）。
- 严重度：中
- 证据：proven（搜索串构造原文对照）；本地化子项 inferred

### D-3 查询结果排序：标题排序不用中文 collation
- 结论：有差异
- 原版：src/app/editor/slash-model.js:16-21（前缀命中优先，其次 `title.localeCompare(title, 'zh-Hans-CN')`）
- Rust：rust/apps/web/src/editor.rs:5740-5749（前缀命中优先逻辑等价，其次 Rust 字符串序 `cmp`，即 Unicode 码点序）
- 差异：多条中文标题同为非前缀命中时，排序可能与原版拼音 collation 不同（如「待办/代码/代码块」类相邻序）。前缀优先规则本身一致。
- 严重度：低
- 证据：proven（比较器原文对照）；具体乱序个例 inferred

### D-4 查询匹配高亮 `<mark class="slash-match">` 未实现
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:24-34、118-122（标题与副标题中命中子串包 `<mark class="slash-match">`）
- Rust：rust/apps/web/src/editor.rs:5816-5821（标题/副标题纯文本渲染，无 mark）；rust/apps/web/styles/editor.css:575 有 `.slash-match` 样式但无任何 DOM 使用
- 差异：输入查询后，原版命中文字有高亮底色，Rust 无高亮（CSS 是死样式）。
- 严重度：中
- 证据：proven

### D-5 空结果态缺搜索图标与拼音提示行
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:185-193（空态 = 28px 放大镜 SVG + 「未找到匹配命令」 + 提示行「试试拼音首字母：bt 标题 · tp 图片 · yykp 音乐」，kbd 样式）
- Rust：rust/apps/web/src/editor.rs:5831-5833（仅一行 `slash.no_match` 文案 div）；styles/editor.css:576-579 的 `.slash-empty-state > svg`、`.slash-empty-hint`、kbd 样式均无 DOM 对应
- 差异：空态只剩一行文字，图标与拼音首字母提示（bt/tp/yykp）整体缺失。
- 严重度：中
- 证据：proven

### D-6 面板与行的无障碍语义缺失（listbox/option/activedescendant/aria-label）
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:86-107、149-158（容器 role=listbox、aria-label「斜杠命令」、aria-activedescendant 指向选中行；行 role=option、id=`mynote-slash-option-<i>`、aria-label 含「标题，副标题，快捷键 X」；链接态容器转 role=dialog、aria-label「插入链接」）
- Rust：rust/apps/web/src/editor.rs:5791-5829（容器仅 id/class；行仅 `data-act` 与 aria-selected；无 role、无 id、无 aria-label、无 activedescendant）
- 差异：屏幕阅读器下无列表框语义、无当前项播报、无快捷键播报；链接表单态无 dialog 语义。
- 严重度：中
- 证据：proven

### D-7 键盘导航模型不同：无 Home/End、无 roving focus、hover 不更新选中、aria-selected 不随导航更新
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:38-73（ArrowUp/Down/Home/End 在真实按钮间移焦点并同步选中，焦点即选中；onPointerEnter/onMouseEnter/onFocus 均更新选中；Escape 经 closeSlashPanel(true) 关面板并恢复保存的选区）
- Rust：rust/apps/web/src/editor/bridge.rs:224-232（moveSel 仅切换 `.sel` 类 + scrollIntoView）、:632-656（编辑器 keydown 拦截 ArrowUp/Down/Enter/Escape）；rust/apps/web/src/editor.rs:5796-5812（行只有 onclick，无 pointerenter/focus 处理，aria-selected 只由初次渲染的 row.sel 决定）
- 差异：① 无 Home/End；② 焦点从不进入面板（等价于虚拟选中，与原版真实焦点+aria-activedescendant 不同）；③ 鼠标悬停行只有 CSS :hover 底色、`.sel` 不跟随，按 Enter 会应用旧 `.sel` 项而非悬停项（原版悬停即改选中，Enter/点击一致）；④ 桥 moveSel 改类名后 aria-selected 属性不更新，与视觉选中脱节。Escape 关面板不恢复选区一项为等价差异（Rust 光标从未离开编辑块，无需恢复）。
- 严重度：中
- 证据：proven（处理函数原文对照）；③的 Enter 后果 inferred（由 moveSel/onclick 代码路径推断）

### D-8 面板定位细节：maxHeight 非动态、z-index 不同、未用 visualViewport
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:133-148（position fixed、zIndex 9999、maxHeight=`min(320px, calc(100dvh - (top+16)px))`、opacity/transform 140ms transition 进出场）；定位公式在 use-slash.js:352-386（visualViewport offset/宽高参与钳制，面板高估算 260 上翻）
- Rust：rust/apps/web/styles/editor.css:1377（position fixed、z-index 3500、max-height 固定 320px、animation slashIn 进场、无出场）；rust/apps/web/src/editor.rs:5606-5647（宽/left/top 公式逐项移植，但视口宽高取 window.innerWidth/innerHeight，非 visualViewport）
- 差异：① 面板靠下时原版按剩余高度收缩 maxHeight，Rust 恒 320px 可能溢出视口底；② z-index 9999→3500，低于图文底表（4000/4001）与灯箱（10000）的层级（同屏共存场景少，实际影响 inferred）；③ 移动端键盘弹起时 visualViewport 与 innerHeight 不一致，定位可能偏移（inferred）。宽/left/top 主公式与上翻逻辑一致。
- 严重度：低
- 证据：proven（样式与公式原文对照）；②③影响 inferred

### D-9 行内命令落地形态不同：字面 Markdown 包裹 vs DOM 元素包裹；且原版强制转段落、Rust 保留原块类型
- 结论：有差异
- 原版：src/app/editor/use-slash.js:464-545（pairs 表：`**…**`、`*…*`、`==…==`、`` `…` ``、`~~…~~`、`[…](url)` 直接拼入块的**纯文本**，选区首尾空白留在标记外、链接文本转义 `\[\]`；无选区占位文为「文字」/链接为「链接文字」；落块固定为 `{type:'paragraph'}`——在标题等块内应用行内命令会把块降为段落；光标落在包裹整体之后）
- Rust：rust/apps/web/src/editor/bridge.rs:1147-1200（applyInline 手工 surroundContents 生成 `<b>/<i>/<s>/<code>/<mark class=mynote-highlight>` 元素，无选区插入元素版「文字」，光标在元素后）；rust/apps/web/src/editor.rs:1766-1795（结果经 editor_html_to_inlines 落为行内格式节点，块类型不变）
- 差异：① 存储形态不同：原版 children 是含字面标记的纯文本（编辑态可见 `**文字**` 原码、靠 md 机制在失焦后渲染），Rust 是结构化行内节点（编辑态即时呈加粗等效果）——导出 Markdown 结果等价，但编辑态显示与源码态处理不同；② 块类型：在标题/引用/待办块内用行内命令，原版整块变段落，Rust 保留原类型；③ 选区首尾空白处理：原版把空白剥出标记外，Rust surroundContents 会把选区内首尾空白一并包进元素（inferred，由 surround 路径推断）；④ 链接带选区时 Rust 走 __mnApplyLink 的 execCommand createLink 生成 `<a>`（bridge.rs:1207-1225），原版为字面 `[文本](url)`；无选区时 Rust 同样插入字面 `[链接文字](url)`，该子项一致。
- 严重度：高
- 证据：proven（pairs 表/落块类型与 applyInline/__mnApplyLink 原文对照）；③ inferred

### D-10 链接表单：无 form/Enter 提交、Enter 路径取消直接关面板、输入框语义缺失
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:160-184（`<form onSubmit>`，Enter 即提交；input type=url、required、autoFocus+聚焦全选、aria-invalid/aria-describedby、错误 role=alert；取消经 cancelSlashLink 回命令列表并聚焦首行，use-slash.js:690-699）
- Rust：rust/apps/web/src/editor.rs:5648-5701（div 版表单：input 无 type/required/aria 属性，靠 onmounted 聚焦全选；提交仅点「插入链接」按钮，Enter 无处理；校验 URL 解析+协议白名单与错误文案同口径）；rust/apps/web/src/editor.rs:3382-3385 + 5650 区（经桥 Enter 打开的表单 link_for 清除后整个 SlashPanel 卸载）
- 差异：① 链接输入框按 Enter 不提交（原版提交）；② 点按行打开表单时取消可回列表（link_for 清除后面板仍在，一致），但键盘 Enter 打开表单时取消会把面板整体关掉，原版两种路径取消都回列表；③ 输入框缺 type=url（移动端键盘/校验语义）与 aria 关联。
- 严重度：中
- 证据：proven

### D-11 块转换后光标落点：原版落 token 起点（md 类加前缀长），Rust 落文本/源码末尾
- 结论：有差异
- 原版：src/app/editor/use-slash.js:604-612、645-652（afterSelection offset = markdownPrefixLength + commandCaretOffset；commandCaretOffset = 斜杠 token 起点；codeBlock 前缀=围栏长+1、列表=2/3、callout=`> [!NOTE]\n> ` 长；普通块即 token 起点）
- Rust：rust/apps/web/src/editor.rs:5144-5161（op_convert 顶层路径 focus = plain_len(转换后全文)，musicCard 除外）；:1796-1816 与 :3750-3762（md 源类经 dom_set 以源码总长落点，即源码末尾）
- 差异：斜杠在句中触发（如 `abc /bt def` 光标在 token 后）时，原版光标回到 token 起点，Rust 落到整块末尾；md 源类（代码块/列表/Callout）原版落在正文起点（围栏/前缀之后），Rust 落在源码最末尾。斜杠在块尾触发的常见情形两者等价（token 起点=清洗后文末；md 类差一个正文长度，仍不同）。
- 严重度：中
- 证据：proven

### D-12 图文卡/图文混排应用后焦点：原版落尾随空段，Rust 指向卡片块本身
- 结论：有差异
- 原版：src/app/editor/use-slash.js:574-596（needsTrailingParagraph 含 imgTextCard/imageTextRow；shouldFocusAfterBlock 含这两类，insertedFocusId = 尾随段 id，光标落尾随段）
- Rust：rust/apps/web/src/editor.rs:5144-5161（尾随空段有补，:5150-5158；但 focus_req 设为 (bid, len)，bid 是卡片块自身；卡片在 Rust 是 blk-wrap 原子块、无 [data-bid] 可编辑宿主）
- 差异：应用图文卡/混排后，原版光标在卡后空段可直接打字；Rust 焦点请求指向不可编辑的卡片块，落点落空（后续输入焦点去向 inferred）。
- 严重度：中
- 证据：proven（focus_req 取值原文）；落空后果 inferred

### D-13 代码块围栏自适应缺失
- 结论：有差异
- 原版：src/app/editor/use-slash.js:550-554（正文含 ` ``` ` 时围栏逐个加长反引号避免冲突；正文取 cleanedText 原样）
- Rust：rust/apps/web/src/editor.rs:5093-5105（固定三反引号围栏；且正文先经 strip_md_prefixes 剥前缀）
- 差异：正文含三反引号时 Rust 生成的 md 源码围栏会被正文提前闭合，渲染/再编辑口径与原版不同；正文行首有 md 前缀时 Rust 会先剥掉再入源码，原版保留。
- 严重度：低
- 证据：proven

### D-14 图片/画廊占位：下一块已是空段时仍多插一段
- 结论：有差异
- 原版：src/app/editor/use-slash.js:574-580（needsTrailingParagraph 在下一块已是空段落时置 false，不重复补段）
- Rust：rust/apps/web/src/editor.rs:4937-4992（op_insert_media_placeholder 无条件 insert 尾随空段）
- 差异：在空段落前一块用图片/画廊命令时，Rust 会多出一个空段落（文档多一空行）。todo/musicCard/imgTextCard/imageTextRow/callout 的尾随段 Rust 有 next_ok 检查（:5150-5158），与原版一致，不在此列。
- 严重度：低
- 证据：proven

### D-15 图文卡无图占位缺失
- 结论：有差异
- 原版：src/editor/editor.render.js:55-60（imgTextCard 无图时 itc-img-wrap 内渲染 160px 占位盒「📷 点击添加图片」）
- Rust：rust/apps/web/src/blocks.rs:696-719（file_id 为 None 时 itc-img-wrap 内为空，无占位）
- 差异：新建图文卡（fileId=''）在 Rust 无图区塌陷为空白，原版有 160px 图标+文案占位（与「换图」按钮的发现性相关，按钮行为本身见一致清单）。
- 严重度：中
- 证据：proven

### D-16 图文混排无图占位图标不同
- 结论：有差异
- 原版：src/editor/editor.render.js:61-66（无图时 `.itr-placeholder` 内为 📷）
- Rust：rust/apps/web/src/blocks.rs:721-736（span.itr-placeholder 内容为 🖼）
- 差异：仅占位 emoji 不同（📷 vs 🖼），结构与样式类一致。
- 严重度：低
- 证据：proven

### D-17 画廊网格几何与空画廊占位不同
- 结论：有差异
- 原版：src/editor/editor.render.js:67-75（成品：2 列网格、每图高 366px、radius 22；空画廊：两块 366px 占位 tile「🖼 点击添加」「🖼 多张图片」）
- Rust：rust/apps/web/src/blocks.rs:420-440 + rust/apps/web/styles/editor.css:1374-1375（成品：`.gallery-grid` 3 列、方图 aspect-ratio 1、radius 10、margin 8px 36px；空画廊：单个 `.atomic-placeholder` 文案块）
- 差异：列数（2 vs 3）、图高/比例（366px 定高 vs 方图）、圆角（22 vs 10）、空态形态（双 tile vs 单文案块）均不同。
- 严重度：中
- 证据：proven

### D-18 链接卡 loading 骨架为 Rust 新增态（原版无标题即错误卡）
- 结论：有差异
- 原版：src/editor/editor.render.js:439-445（link-card 渲染不读 status：meta 无 title 一律输出 link-card-err 错误卡）；骨架样式虽在 src/styles/cards.css:81-123 定义，但 link-card 分支不产出骨架
- Rust：rust/apps/web/src/blocks.rs:603-631（status=="loading" 且无 title 时输出 `.link-card-skeleton` 封面+三行骨架）
- 差异：链接卡解析中，原版显示错误卡（主机名+URL），Rust 显示骨架屏。音乐卡的 loading 骨架两侧一致（原版 musicCard 分支有骨架，editor.render.js:471-474；Rust blocks.rs:515-527 同形），不在此列。
- 严重度：低
- 证据：proven

### D-19 链接卡错误态容器与无 scheme 时标题推导不同
- 结论：有差异
- 原版：src/editor/editor.render.js:439-445（错误卡为 `<div class="atomic link-card-err">` 非链接容器；标题 = `new URL(url).hostname` 去 www，解析失败则 domain='' 回退完整 URL）
- Rust：rust/apps/web/src/blocks.rs:632-646（错误卡为 `<a class="atomic link-card-err" href target=_blank>`；host_of 为手写切分，无 scheme 时把首段当主机名）
- 差异：① 容器 div→a（点按直接新开页；原版编辑态点按行为由宿主点击逻辑处理，非原生跳转）；② 无 scheme 的 URL（如 `example.com/x`）原版标题显示完整 URL，Rust 显示 `example.com`。
- 严重度：低
- 证据：proven；①的实际点按后果 inferred

### D-20 图文底表 ImageTextSheet：「完成编辑」行为不同 + 焦点/键盘/aria 管理缺失
- 结论：有差异
- 原版：src/components/ImageTextSheet.js:33-131（完成编辑仅切回阅读态、底表不关；Escape 关闭；Tab 焦点陷阱；打开聚焦 dialog、关闭 220ms 后把焦点还给 triggerElement；section role=dialog/aria-modal/aria-labelledby；编辑态 textarea 自动聚焦、placeholder「输入图片说明文字…」、aria-label「编辑图片说明文字」；文本经 onChange 逐键回写）
- Rust：rust/apps/web/src/editor.rs:3320-3385（编辑态点页脚按钮 = save_sheet_text 后 animate_text_sheet_close 关表；section 仅 class，无 role/aria-modal/aria-labelledby、h2 无 id；textarea 无 placeholder/aria-label、无自动聚焦；遮罩点击时若在编辑态先保存再关）；关闭时长 220ms 与 is-closing 动画一致（editor.rs:1104-1140）
- 差异：① 「完成编辑」原版留表内回阅读态，Rust 直接关表——行为不同；② Escape 关表、Tab 陷阱、焦点恢复、打开聚焦均缺失；③ textarea placeholder/aria-label 缺失。逐键回写 vs 草稿+保存的落盘结果在正常关表路径等价（遮罩/完成编辑都先保存）。
- 严重度：高
- 证据：proven

### D-21 列表图片卡 ImageCard：键盘可达性缺失、封面取图口径不同
- 结论：有差异
- 原版：src/components/ImageCard.js:47-55（.img-card role=group、tabIndex=0、aria-label「标题，图片笔记，按回车或空格打开」、Enter/Space 打开）；:14-35（封面取 doc 首个 attachment，IDB 读取失败/未就绪时最多重试 5 次×300ms，接受 stored.url 或 stored.thumb，不限图片字节格式——以 stored.type `image/*` 判定）
- Rust：rust/apps/web/src/list.rs:1086-1170（MemoRow 的 .img-card 仅 pointer 手势 + onclick，无 tabindex/role/aria-label、无键盘打开）；:955-986（CoverImg 单次 IDB 读取，靠字节魔数嗅探 JPEG/PNG/GIF/WebP 判定图片，无重试）
- 差异：① 键盘用户无法聚焦/打开图片卡（原版可）；② 附件字节稍后就绪或为 BMP/AVIF/SVG/HEIC 等非嗅探格式时，Rust 封面恒为空占位，原版能出图（重试与格式子项为 inferred，未做真机验证）。标题/标签（>2 出 +N）/时间+摘要（60 字）/左滑置顶删除结构一致。
- 严重度：中
- 证据：proven（DOM 属性与取图代码原文对照）；②后果 inferred

### D-22 LazyImage：原版为无调用点组件，Rust 对应加载无懒加载/两段式
- 结论：有差异
- 原版：src/components/LazyImage.js:1-42（IntersectionObserver rootMargin 100px：skeleton → thumb 先行 + full 叠加 loaded 淡入，full 加载后 revoke thumb blob URL）；全仓 grep 显示该组件除自身文件外无引用（编辑器渲染走 files 表直出 img）
- Rust：rust/apps/web/src/blocks.rs:246-295（BlobMedia 挂载即从 IDB 取字节出图，未就绪时 `.atomic-placeholder`「加载中」文案；无 IntersectionObserver、无 thumb/full 两段）
- 差异：因原版组件实际未被调用，此项无用户可见的原版行为基线；仅记录实现策略不同：Rust 图片随块挂载即加载（长文档首屏成本 inferred），且占位形态为文案而非骨架块。
- 严重度：低
- 证据：proven（无引用为 grep 结果）；首屏成本 inferred

### D-23 视频卡：原版无独立 video 块，Rust 为新增渲染
- 结论：有差异
- 原版：src/editor/editor.render.js:83-86（无 `video` 分支，embedCard/default 落 `<p>` 文本兜底）；「视频」在原版仅是 link-card 的 meta.type——来源图标 🎬 与哔哩哔哩不显示副标题（editor.render.js:446-453）
- Rust：rust/apps/web/src/blocks.rs:441-450（独立 `"video"` 块：fileId→BlobMedia video controls、url→`<video controls>`、无源→占位文案）；🎬 图标与 bilibili 规则另在 blocks.rs:111-117、674-676 有等价实现
- 差异：Rust 超集——原版文档里不存在可渲染的 video 块（同数据在原版降为段落文本），Rust 能播。属新增能力而非 1:1 还原，记录备查。
- 严重度：低
- 证据：proven

### D-24 最近使用胶囊位置不同
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:116-120（`.slash-recent-pill`「最近」在 `.slash-row-title` 内、紧贴标题文字之后，shortcut 另在行尾）
- Rust：rust/apps/web/src/editor.rs:5817-5827（pill 渲染在 copy 与 shortcut 之后、位于按钮 flex 行末尾，标题内无 pill）
- 差异：胶囊视觉位置由「标题旁」变为「行尾」，其余（文案「最近」、aria-label）一致。
- 严重度：低
- 证据：proven

### D-25 斜杠行图标描边参数不同
- 结论：有差异
- 原版：src/app/editor/slash-panel.js:109-112（SvgIcon strokeWidth='1.9'，stroke 默认 currentColor 即面板文字色）；path 数据源 src/utils/svg.js:53-77
- Rust：rust/apps/web/src/editor.rs:5813-5815（Icon size 20、stroke_width "2.5"、stroke `var(--color-accent)`）；path 数据 rust/apps/web/src/icons.rs:20-46 与原版逐项相同
- 差异：图标线更粗（2.5 vs 1.9）且着色为主题蓝而非文字色。path 几何本身一致。
- 严重度：中
- 证据：proven

---

## 已核一致项清单

**斜杠面板与过滤**
1. 项全集 22 项：名称/副标题/keywords/pinyin/shortcut/分组逐项一致（见对照表）。
2. 无查询分组序：最近使用（localStorage `memos_slash_recent_v1`、上限 6、最新在前、按存储序）置顶 → 基础块 → 媒体块，已入最近的从分组中剔除；分组头文案「最近使用/基础块/媒体块」一致（slash-model.js:22-57 ↔ editor.rs:5747-5790、:88-118）。
3. 有查询时无分组头、recent 标记清除，与原版一致（slash-model.js:19-21 ↔ editor.rs:5726-5746）。
4. 前缀命中优先规则（标题+keywords 或 pinyin 以查询开头者靠前）一致（D-3 仅 collation 差异）。
5. 面板宽度公式（标题字数×16 + shortcut×8 + 56、分组 +20，min(360, max(220, 内容+12, 视口-24))）、left 视口钳制（12px 边距、锚点 left-8）、top=锚底+10、高 260 估算上翻（下限 76）逐项移植一致（use-slash.js:352-386 ↔ editor.rs:5606-5647）。
6. 面板容器视觉：glass overlay 背景/模糊/0.5px 边框/radius 22/padding 8/max-height 上限 320、行高 48、行内布局、section-heading、shortcut 胶囊、recent 胶囊样式在 styles/editor.css 与原版 editor-shell.css 对应段逐项同值（D-8 仅 maxHeight 动态部分与 z-index 差异）。
7. 点面板外关闭、点其他块关闭（bridge.rs:953-956 ↔ use-slash.js 全局 pointerdown）；滚动时面板锚点重定位（editor.rs S3 处理 ↔ use-slash.js:707-740）。
8. 组合输入（拼音）期间不拦截面板按键、不触发斜杠检测（bridge.rs keydown 首行 composing 守卫 ↔ use-slash.js:195、slash-panel 行为）。
9. 令牌整体剥离：按 dataset 记录的 token 位置/长度整段删除，找不到可靠位置不剥离（bridge.rs:185-222 ↔ use-slash.js token 模型 :457-462）。
10. 最近使用记录时机：每次成功应用命令后记录并持久化（editor.rs:100-118、1769、1834 ↔ use-slash.js:594-600、702-705）。

**命令落地**
11. heading1/2/3：块转 heading、attrs.level=1/2/3、正文为清洗后文本（use-slash.js:557-568 ↔ editor.rs apply_type:4892-4897）。
12. paragraph/quote：转对应类型、正文保留（apply_type:4898-4907  quote/默认段落）。
13. todo：转 todo、attrs.checked=false，并补尾随空段（下一块已是空段则不补）（use-slash.js:574-580 ↔ editor.rs:5150-5158）。
14. divider：换 divider 块 + 新空段并聚焦空段（use-slash.js:582-596 ↔ editor.rs op_convert divider 分支 :5120-5135）。
15. 代码块/无序/有序/Callout 的「md 源段落」模型：不造独立块类型，children 存源码文本（```围栏、`- `/`1. ` 逐行前缀、`> [!NOTE]\n> ` 前缀）、空正文兜底文案「列表项」/「提示内容」、callout 补尾随空段（use-slash.js:546-573 ↔ editor.rs:5070-5118；D-11/D-13 为落点与围栏细节差异）。
16. musicCard 工厂：`{url:'', meta:null, status:'input'}` 无 children；应用后聚焦输入胶囊且光标落占位文案末尾（use-slash.js:562、645-660 ↔ editor.rs apply_type:4916-4925、focus MAX :5160）。
17. imgTextCard/imageTextRow 工厂：正文被固定占位文替换（「点击输入文字」/「点击输入说明文字」，不保留原文）、attrs.fileId=''、补尾随空段（use-slash.js:565-566 ↔ editor.rs apply_type:4902-4915、尾随段 :5150-5158；焦点差异见 D-12）。
18. image/gallery 工厂：image attrs.fileId=''、gallery attrs.items=[]、替换当前块 + 尾随空段并聚焦尾随段；文件选择延后到点占位块「选择图片」按钮（use-slash.js:563-564、582-596 ↔ editor.rs op_insert_media_placeholder:4937-4992；多补段差异见 D-14）。
19. 链接表单校验与预填：预填 `https://` 并全选、URL 解析 + http/https 白名单、错误文案「请输入有效的 http 或 https 链接」、插入时 URL 中括号 %28/%29 转义在原版 apply 侧（use-slash.js:407-419），Rust 在 __mnApplyLink/createLink 路径以真实 href 落地（表单层校验口径一致，落地形态差异见 D-9/D-10）。
20. 音乐输入胶囊解析：剥占位文案提 URL（scheme 延伸字符集/裸域名补 https）、转 loading 骨架、解析回填 meta+status（有 title=ready 否则 error）、竞态守卫（URL 已改则放弃）、解析后光标落卡片下方文本块开头（无则补空段）、段首退格删胶囊回相邻文本块（cards.rs:13-268 ↔ use-slash.js resolvePendingMusicUrl 口径与 editor.render.js musicCard input 分支）。

**卡片**
21. 链接卡 ready 态 DOM：`.lkc-cover`（2.4/1、proxyImg 封面）+ `.lkc-body(.has-cover)` + `.lkc-title`（2 行截断）+ `.lkc-subtitle`（仅 meta.subtitle、哔哩哔哩不显示）+ `.lkc-source`（type 图标 🔗/🎵/🎬 + 3px 圆点 + source||主机名），class 与样式逐项同值（editor.render.js:446-453 ↔ blocks.rs:650-695、styles/editor.css:487-520）。
22. 链接卡 skeleton 样式（封面 2.4/1 + 转圈 + 三行骨架线 75%/50%/35%）两侧同形（cards.css:81-123 ↔ blocks.rs:517-522、619-627 与 styles/editor.css:488-503）——仅 link-card 是否使用骨架有别（D-18），音乐卡使用一致。
23. 音乐卡全状态机：input 胶囊 / ready 卡（同链接卡结构、来源图标 🎵、source 缺省「音乐」）/ loading 骨架 / error 卡（🎵+URL 链接+「重试」按钮、重试走公共解析路径）/ 无 URL 兜底胶囊「点击粘贴音乐链接」、带 fileId 音频附件走文件行（editor.render.js:454-486 ↔ blocks.rs:451-563、cards.rs spawn_resolve_card）。
24. 音乐卡「设链」：选中态按钮 prompt 输入 URL → 先置 loading 再解析回填（editor.rs musicCard 选中按钮 ↔ 原版设链路径）。
25. 文件卡（attachment 非图片）：📎 图标 + 文件名（manifest 优先）+「点击打开」提示 + 点按打开文件（editor.render.js:432-437 ↔ blocks.rs:565-601）。
26. 图片卡（image 块）：有图出图（点击灯箱）、无图占位文案「点击添加图片」、img 度量（max-height 668、margin auto、object-fit contain、radius 22）一致（editor.render.js:76-80 ↔ blocks.rs:398-418、styles/editor.css:1423 区）。
27. 图文卡/混排结构：`.img-text-card` 上图下文（图 max-height 468 cover）/`.img-text-row` 左右 50% + 文本 6 行截断、点文本开底表、选中态「换图/删除」按钮（editor.render.js:55-66 ↔ blocks.rs:696-745、styles/editor.css:63-74；无图占位差异见 D-15/D-16）。
28. embedCard：原版落段落兜底，Rust 同列入 `<p>` 兜底名单（editor.render.js:83-86 ↔ editor.rs:553-566 注释与实现）。
29. 地点卡：必读原版文件与原版渲染器均无独立「地点卡」块类型，Rust 亦无——双方一致缺省（链接 meta.type 亦无 location 分支，type_icon 仅 music/video/默认）。
30. 图标 path 全集：icons.rs:20-46 与 svg.js:53-77 的 heading/heading2/heading3/paragraph/quote/todo/divider/bold/italic/highlight/codeBlock/list/olist/callout/imgTextCard/imageTextRow/link/code/strikethrough/music/image/gallery 及 pin/del/back/check/palette/undo/redo/attach/columns/warning 逐字相同；TODO_ICONS data-URI 勾选框为原版编辑器内另一路（Rust 待办勾选走 CSS/按钮实现，不在本分片判定面）。
31. 图文底表骨架：backdrop + wrap + sheet 结构、标题「完整文本」、空文案「暂无文本内容」、footer 按钮文案「编辑文字/完成编辑」、220ms is-closing 出场（translateY 20px/opacity）与原版 ImageTextSheet.js:95-131 + 对应 CSS 同口径（行为差异见 D-20）。
32. 列表图片卡主体：swipe-wrapper + 置顶（警告色）/删除（危险色）双动作、img-cover/img-body/img-text 结构、标题缺省「无标题」、摘要 60 字、标签全显 + >2 出「+N」、expand 按钮 stopPropagation（ImageCard.js:40-69 ↔ list.rs:1016-1170；差异见 D-21）。
