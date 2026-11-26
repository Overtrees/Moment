# 编辑页与菜单全面 1:1 审计报告（原版 vs Rust Web）

- 日期：2026-11-22
- 范围：编辑页结构/顶栏/坞摆位、正文编辑行为、全部块类型渲染与 Markdown、卡片、斜杠面板与命令、菜单/对话框/toast、导出、编辑页全部入口。功能、样式、UIUX、渲染四面。
- 不在范围：标题胶囊内部（另一条线专项）；列表页/设置页本体（仅审编辑页入口衔接）。
- 方法：原版相关代码**完整通读**（见覆盖声明），逐项映射 Rust 实现，双边行号对照。运行时抽查：生产构建 `1c9769e990`（线上 sw.js VERSION 与 wasm md5 实测一致）；本机无头 Chromium 直连 pages.dev 被代理隧道拒绝，改以**与线上逐字节一致的同构建 dist** 本地服务做探针，数据只进探针浏览器自身存储——结论均为 **Chromium 口径**，不代表 iOS 真机。
- 证据等级：proven = 双边代码确切行号（或代码+运行时实测）；inferred = 代码路径推断、未活体验证。
- 分片全文：`audit_parts/part_A.md`（骨架样式）、`part_B.md`（编辑行为）、`part_C.md`（块与 md）、`part_D.md`（卡片与斜杠）、`part_E.md`（菜单/toast/导出）。本报告为综合裁定版，条目细节以分片为准。

## 覆盖声明（原版通读清单）

editor-shell.css(630)、styles/editor.css(392)、tokens.css(263)、tokens.js(126)、base.css(549)、panels.css(182)、cards.css(147)；app/editor.js(3339，结构/行为/菜单三面分片通读)、use-editor-dom.js(729)、use-history.js(305)、use-slash.js(740)、slash-panel.js(199)、slash-model.js(65)、commands.js(229)、lifecycle-hooks.js(69)、export.js(521)、runtime.js(223)、error-boundary.js(204，toast 口径补读)、editor.render.js(508)、md-blocks.js(155)、editor.md.js(412)、markdown-bridge.js(25)、preview.js(72)、ImageTextSheet.js(131)、ImageCard.js(70)、LazyImage.js(42)、BgSheet.js(48)、svg.js(86)。Rust 侧：editor.rs、bridge.rs、blocks.rs、cards.rs、columns.rs、export.rs、title.rs（仅坞摆位）、icons.rs、list.rs 相关段、core 的 model/inline_html/mathml，四份 styles 全读。

## 总览

| 分片 | 差异条目 | 高 | 中 | 低 | 已核一致 |
|---|---|---|---|---|---|
| A 骨架与样式 | 12 | 2 | 2 | 8 | 20 项 |
| B 编辑行为 | 15 | 4 | 9 | 2 | 26 项 |
| C 块渲染与 md | 33 条目中 17 有差异 | 2 | 10 | 5 | 10 项 + 25 行覆盖表 |
| D 卡片与斜杠 | 25 | 2 | 13 | 10 | 32 项 |
| E 菜单/toast/导出 | 17 | 2 | 7 | 8 | 15 项 |
| **合计** | **86（跨片重复 4 处合并后 82 个独立项）** | **12** | | | **103 项** |

跨片合并：D-20 ≡ E-10/E-11（图文底表）；C-14 ≡ D-15（图文卡无图占位）；C-12 ≡ D-18（链接卡骨架）；C-11 与 D-19 同指链接卡容器（两侧分记、合并裁定）。

**裁定修正一条**：A-1 子项「Rust 漏原版 line-height:1.72 覆盖」**不成立**——Rust editor.css:745 在同媒体块内有同值规则，运行时实测 computed line-height = 27.52px = 16×1.72（见运行时抽查节）。A-1 的机制差异与 A-2 跨栏缺失仍成立。

---

## 高严重度（12 条）

### H-1 图库 items 对象形态被丢弃，非空图库渲染成空态（C-08）
- 原版：editor.render.js:65-73，attrs.items 元素可为 `{fileId}`/`{url}` 对象或裸字符串，三者都取图渲染。
- Rust：blocks.rs:164-172，`gallery_items` 只收字符串项，对象项被 filter_map 丢弃；仅全灭时才回退 children 的 fileId。
- 差异：items 为对象数组（原版编辑器实写形态之一）时，Rust 把非空图库显示为空态占位。**数据形态覆盖缺口，直接丢图。**
- 证据：proven

### H-2 md 行内原始 HTML 不渲染（C-28）
- 原版：editor.md.js:375-392 + markdown-bridge.js:9-24，marked 解析原始 HTML 后经 DOMPurify 净化，白名单标签（`<b>`/`<sub>`/`<div>` 等）真实生效。
- Rust：blocks.rs:1700-1960，手写解析器中 `<` 仅识别 `<http…>` autolink，其余标签一律字面显示。
- 差异：md 源码里写原始 HTML 的段落，原版渲染、Rust 显示原文。同类 marked 特性缺口：引用式链接 `[text][ref]`+定义整体不识别、缩进代码块未实现（直链 title 丢弃与 marked 净效果一致，不计）。
- 证据：proven

### H-3 普通打字的模型同步与撤销粒度（B-4）
- 原版：editor.js:1922-1928，每次 input 后 80ms 防抖落模型，文档变化即记撤销点（600ms 合并），撤销粒度≈每个输入爆发。
- Rust：bridge.rs input 监听——普通打字不发模型同步消息；全文同步靠 20s 定时器/visibilitychange 的 `sync` op（editor.rs:3905-3919，只写持久副本、不压历史栈）与关闭时全量同步。
- 差异：①会话内 doc 模型可滞后真实文本最长约 20s，字数统计/双栏分界/反链等派生显示随之滞后；②Ctrl+Z 的回退落点是上一个结构性快照——**连续打字数分钟后一次撤销可整段回退**，而非最近一个输入爆发。
- 证据：proven

### H-4 iOS 三指撤销/重做手势缺失（B-5）
- 原版：use-history.js:285-296，beforeinput 的 historyUndo/historyRedo 监听，三指滑动可撤销/重做。
- Rust：全仓 grep `historyUndo`/`beforeinput` 零命中；撤销入口只有 Ctrl/Cmd+Z/Y 与菜单按钮。
- 差异：iOS 三指手势在 Rust 版无响应（菜单副文案却仍写着「三指左滑/右滑」，见 E 对照表——文案与实现不符）。
- 证据：proven

### H-5 失败提示通道整体替换：错误徽章 → toast 全宽条（E-1）
- 原版：error-boundary.js:31-48、95-197，编辑页**没有 toast**；导出/附件失败只进右下角错误徽章（36×36、黄/红点、不自动消失、点击展开详情、累积 20 条含时间与堆栈）。
- Rust：editor.rs:1591-1600、settings.rs:84-108、base.css:630-641，复用备份页 `.backup-toast` 全宽条（bottom 16+安全区、z 5000、220ms 上滑），success 3s / 其余 6s 自动消失、单条覆盖。
- 差异：通道、位置、驻留、队列全不同（Rust 注释自认原版编辑器无自有状态条）。
- 证据：proven

### H-6 图文全文底表「完成编辑」行为不同（D-20 ≡ E-10/E-11）
- 原版：ImageTextSheet.js:33-131，「完成编辑」只退出编辑态、**底表保持打开**回阅读态；编辑逐键实时落盘（editor.js:828-841）；Escape 关表、Tab 焦点陷阱、打开聚焦 dialog、关闭焦点还 triggerElement、role=dialog/aria-modal、textarea 自动聚焦+placeholder「输入图片说明文字…」。
- Rust：editor.rs:3320-3385，「完成编辑」= 保存草稿并**直接关闭底表**；编辑期仅草稿制（完成/遮罩/Esc 才落盘）；role/aria/焦点陷阱/焦点归还/placeholder 整体缺失。
- 差异：核心按钮语义相反（留表 vs 关表），落盘时机与无障碍/焦点管理成组缺失。
- 证据：proven

### H-7 斜杠行内命令落地形态不同（D-9）
- 原版：use-slash.js:464-545，加粗/斜体/高亮/代码/删除线/链接把 `**…**`、`[…](url)` 等**字面 Markdown 拼入纯文本**，选区首尾空白留在标记外，落块**强制转 paragraph**（标题内加粗会把块降为段落），光标落在包裹整体之后；编辑态见原码、失焦后经 md 渲染。
- Rust：bridge.rs:1147-1200 applyInline 生成 `<b>/<a>` 等 DOM 元素，editor.rs:1766-1795 落为结构化行内节点，**块类型保留**，编辑态即时呈效果。
- 差异：存储形态、编辑态显示、源码态处理、块类型结果四面不同（导出 Markdown 结果等价）。空白处理子项 inferred。
- 证据：proven（空白子项 inferred）

### H-8 宽屏媒体块跨栏缺失（A-2）
- 原版：editor-shell.css:312-319，图片/画廊/图文卡/图文行/音乐卡在双栏下 `column-span:all` 整幅展示。
- Rust：editor.css:1095-1163 flow 网格无跨栏等价物（块在物理栏容器内），媒体恒为半幅单栏宽。Rust editor.css 虽保留了原版 column-span 规则段，但在现行物理栏 DOM 下子项不是 .editor-body 直子，规则不命中。
- 差异：宽屏大图/图文卡原版整幅、Rust 半幅，视觉差异显著。此为物理双栏路线的结构性代价（与 H-9 同源）。
- 证据：proven（代码）；运行时抽查未覆盖（演示数据无媒体块备忘，见抽查节）

### H-9 默认双栏机制：多列平衡流 vs 估高物理分栏（A-1，有意偏离）
- 原版：editor-shell.css:282-295，`column-count:2; column-fill:balance` 浏览器多列平衡流，与独立滚动开关无关。
- Rust：editor.css:1095-1113 物理双栏网格 + editor.rs:2730-2745 `column_boundary` 估高分界，恒渲染左右两个 `.editor-column` 容器；分隔线由 column-rule 改为背景渐变线模拟。
- 差异：块落哪一栏由「实测高平衡」变「估高分界」，长文档中具体分布可与原版不同。系用户「左右栏各自独立容器」决策的有意偏离，与 1:1 口径不符，如实记录。（原 A-1 的行高子项经复核不成立，见总览裁定。）
- 证据：proven；运行时实测两物理栏容器 + is-flow-columns 类（抽查节）

### H-10 待办/引用回车语义不同（B-1，有意偏离）
- 原版：editor.js:2080-2114，非段落块 Enter 一律整块后插空段、不拆文本。
- Rust：editor.rs:4048-4070 op_split，todo/quote 改为同型拆分延续、空块回车转段落（heading/callout 保留原版口径）；代码注释自述为调优结论、偏离原版。
- 差异：todo/quote 中间回车与空块回车的结果结构不同。
- 证据：proven

### H-11 段首退格遇原子块（B-2，有意修复型偏离）
- 原版：editor.js:2116-2143 只处理空块退格；非空块段首退格走原生合并，文本被吸入前一原子块、落盘时丢弃（**原版数据丢失缺陷**）。
- Rust：editor.rs:4196-4228，删原子块、保当前块文本（注释明言不复刻原版缺陷）。
- 差异：按键结果语义不同，方向为修复。如实记录，不建议回退。
- 证据：proven

### H-12 （并入 H-6）

---

## 中严重度（41 条，合并后）

| 编号 | 项 | 差异一句话 | 原版 | Rust | 证据 |
|---|---|---|---|---|---|
| A-3 | 编辑页根节点层级 | 原版两层（动画+背景 / 内容）vs Rust 三层（根→.detail→.editor-pad），根无 position/min-height 声明 | editor.js:2455-2473 | editor.rs:2823-2828 | proven |
| A-4 | 正文容器 DOM 形态 | 单一 contentEditable+原生语义元素 vs 逐块 div 包装（.blk-*），原版选择器须逐条改靶、遗漏即静默失效（结构性风险面） | editor.js:3249-3270 | editor.rs:3163-3258 | proven |
| B-3 | 空块退格遇原子块 | 原版越过原子块落更早文本块末尾一步到位；Rust 只选中原子块、需再按一次退格（两步流） | editor.js:2125-2141 | editor.rs:4183-4195 | proven |
| B-6 | 撤销选区恢复 | 原版快照路径不恢复选区；Rust 每次强制恢复到操作前块+偏移 | use-history.js:193-232 | editor.rs:185-262 | proven |
| B-7 | 历史不含 layout 快照 | 跨栏移动撤销时原版连栏布局一起回退；Rust 只还原 doc、栏锚按归一重算。原版 recordOp patch 双轨亦无对应（不可见，仅记 layout） | use-history.js:84-128、193-262 | editor.rs:134-168 | proven |
| B-8 | 跨块选区粘贴多行 | 原版整段留单块内换行；Rust xsel 路径按 \n 拆成多个段落块。另 op_paste_text 为无发送方的不可达代码、其注释与现行路径不符 | editor.js:2262-2270 | bridge.rs paste / editor.rs:4375-4405、4652 | proven |
| B-9 | 音乐胶囊粘贴事务缺失 | 原版有粘贴前快照+错位回收（URL 被浏览器落到邻块时 diff 回收转交胶囊）；Rust 无，URL 会当普通文本落邻块 | editor.js:1715-1768 | bridge.rs paste musicInput 分支 | proven |
| B-10 | 撤销快捷键作用域 | 原版 window 全局监听（焦点落 body 也生效）；Rust 仅编辑块内桥 keydown，点过原子块后 Ctrl+Z 无反应 | use-history.js:269-282 | bridge.rs keydown | proven |
| B-11 | 组字结束无重放 | 原版 compositionend 显式跑一次输入管线（斜杠/前缀/落模型）；Rust 只翻标志，依赖引擎补发 input，不发则等下次击键或 20s 同步。keyCode 229 兜底亦缺 | editor.js:3260、2026 | bridge.rs  composition 段 | inferred（无重放为 proven） |
| B-12 | 上下方向键跨块判定 | 原版原生视觉行移动（可进卡片文字区）；Rust 首/末行 0.9 行高阈值+hit-test、目标仅文本块 | editor.js:55-101 | bridge.rs crossBlockArrow | inferred（阈值/目标集 proven） |
| B-13 | 原子块点击插段区 | 原版卡片用右 15% 区、附件用左右 28px；Rust 统一左右 28px，宽/窄卡触发带宽窄互换 | use-editor-dom.js:171-194、313-366 | bridge.rs click | proven |
| C-01 | paragraph 子节点 | 原版只取 children[0].text；Rust 渲染/拼接全部子节点（现网多为单子节点，影响小） | editor.render.js:41-43 | blocks.rs:338-346、model.rs:104-115 | proven |
| C-03 | heading 默认级/范围/标签 | 默认级 2 vs 1；原版无钳制可出 h5/h6、Rust 钳 1–4；真实 hN vs div.blk-hN（md 段落内 ATX 两边同为真实 hN，不在此项） | editor.render.js:44-47 | blocks.rs:158-163、347-351 | proven |
| C-04 | quote 结构 | blockquote>div vs 单层 div.blk-quote，语义标签丢失 | editor.render.js:48-50 | blocks.rs:352 | proven |
| C-05 | todo 勾选控件 | 原生 checkbox+aria-checked/aria-label vs 只读态 span 绘制（编辑态为 button），无障碍属性缺失；checked 落点一致 | editor.render.js:51-54 | blocks.rs:353-361 | proven |
| C-09 | gallery 空态 | 原版 2 列双占位格（366px、「🖼 点击添加」+「多张图片」）vs Rust 单行文案占位（与 D-17 同项的空态面） | editor.render.js:68 | blocks.rs:420-431 | proven |
| C-11/D-19 | link-card 容器 | ready/err 均为不可编辑 div vs 整卡 `<a target=_blank>`；err 无 scheme 时标题推导不同（完整 URL vs 首段主机名） | editor.render.js:438-450 | blocks.rs:603-695、632-646 | proven（点按后果 inferred） |
| C-14/D-15 | imgTextCard 无图占位 | 原版 160px 占位盒「📷 点击添加图片」+ role/tabindex/aria；Rust 图区为空、无占位、无障碍属性缺失 | editor.render.js:56-60 | blocks.rs:696-720 | proven |
| C-17 | Rust 独有块类型 | callout/codeBlock/列表组/video 在原版只落 `<p>` 纯文本，Rust 结构化渲染（超集扩展）；独立 callout 图标用 emoji，与 md Callout 的 SVG 图标不一致；列表组用 div+span 模拟而非 ul/ol/li | editor.render.js:40-86 | blocks.rs:363-450 | proven |
| C-21 | Callout 未知类型标题 | 原版回退类型原文（如 FOO）；Rust 恒「笔记」。已知 16 类型映射逐字一致 | editor.md.js:148-172 | blocks.rs:798-815 | proven |
| C-30 | URL 协议白名单缺失 | 原版 safeHttpUrl/safeImageUrl 只许 http(s)/data:image，其余置空；Rust 把 extra.url 原样写 href/src，`javascript:` 链接可点触发（安全项） | editor.render.js:14-21 | blocks.rs:399-450、603-695 | proven |
| D-1 | 斜杠触发抑制缺失 | 输入/粘贴 URL 时 Rust 会在第二个 `/` 后误弹面板；查询 >30 字原版关面板、Rust 保持 | use-slash.js:242-277 | bridge.rs:841-868 | proven |
| D-2 | 过滤搜索串 | 原版含 type（ordered_list 等英文词可搜）；Rust 以 act 代替（ordered/inline 搜不到，bullet/number 仅 Rust 可搜）；本地化标题入串使非中文词搜索随语言变（子项 inferred） | slash-model.js:13-15 | editor.rs:5726-5738 | proven |
| D-4 | 匹配高亮未实现 | 原版命中子串包 `<mark class=slash-match>`；Rust 纯文本渲染，CSS 成死样式。**运行时实测 mark=0（抽查节）** | slash-panel.js:24-34 | editor.rs:5816-5821 | proven |
| D-5 | 斜杠空态缺件 | 原版放大镜 SVG+「未找到匹配命令」+拼音提示行（bt/tp/yykp）；Rust 仅一行文案，图标/提示 CSS 均无 DOM 对应 | slash-panel.js:185-193 | editor.rs:5831-5833 | proven |
| D-6 | 斜杠面板无障碍 | 原版 listbox/option/activedescendant/aria-label 全套；Rust 无 role/id/aria-label，链接态无 dialog 语义 | slash-panel.js:86-107 | editor.rs:5791-5829 | proven |
| D-7 | 键盘导航模型 | 无 Home/End；hover 不更新 .sel → Enter 可能应用旧选中项（后果 inferred）；aria-selected 不随导航更新 | slash-panel.js:38-73 | bridge.rs:224-232、632-656 | proven |
| D-10 | 链接表单 | 无 form/Enter 提交（Enter 不提交）；经 Enter 打开表单时取消会整关面板（点按路径可回列表，两路不一致）；input 缺 type=url 与 aria | slash-panel.js:160-184 | editor.rs:5648-5701、3382-3385 | proven |
| D-11 | 转换后光标落点 | 原版落 token 起点（md 类再加前缀长）；Rust 落全文/源码末尾。句中触发与 md 类差异明显，块尾触发普通块等价 | use-slash.js:604-612 | editor.rs:5144-5161 | proven |
| D-12 | 图文卡应用后焦点 | 原版落尾随空段可直接打字；Rust focus_req 指向不可编辑的卡片块本身，落点落空（后果 inferred） | use-slash.js:574-596 | editor.rs:5144-5161 | proven |
| D-17 | 画廊成品几何 | 2 列/366px 定高/radius 22 vs 3 列/方图/radius 10/margin 8px 36px（空态见 C-09） | editor.render.js:67-75 | blocks.rs:420-440、editor.css:1374-1375 | proven |
| D-21 | 列表图片卡 | 原版 role/tabIndex/aria-label + Enter/Space 打开；Rust 仅指针。封面取图：原版重试 5×300ms 且按 stored.type 判定；Rust 单次读取+字节嗅探，非嗅探格式（BMP/AVIF/SVG/HEIC）或稍后就绪时封面恒空（后果 inferred） | ImageCard.js:14-55 | list.rs:955-986、1086-1170 | proven |
| D-25 | 斜杠图标描边 | strokeWidth 1.9 + currentColor vs 2.5 + 主题蓝（path 几何逐字一致） | slash-panel.js:109-112 | editor.rs:5813-5815 | proven |
| E-2 | 导出成功 toast | 原版成功无提示；Rust 新增，且 MD/HTML 共用 `export.done`=「已导出 Markdown」——**HTML 导出会显示错误格式名**；PDF 成功又无 toast，三格式不一致 | editor.js:1309-1416 | editor.rs:2411、2553 | proven |
| E-3 | 附件失败无可见提示 | 原版 4 条明确 warn 文案进徽章；Rust IDB 写/读失败仅记 Diag 静默返回（成功反而有原版没有的 success toast） | editor.js:1239、1429、1444、1468 | editor.rs:5985-6074 | proven |
| E-4 | 撤销/重做禁用态 | 原版不禁用（opacity .3，点按仍关菜单）；Rust disabled+pointer-events:none，点按无反应、菜单不关 | editor.js:2828、2890 | editor.rs:3057-3069、editor.css:1289 | proven |
| E-5 | 菜单尾随 › 缺失 | 原版附件/导出/背景三项全有 ›；Rust 仅导出项有，附件与背景缺失 | editor.js:3013-3026、3147-3160 | editor.rs:3078-3107 | proven |
| E-6 | 附件菜单关闭时机 | 原版先关菜单再唤起选择器；Rust label 直唤，选择器取消时菜单残留（仅 onchange 才关） | editor.js:1304-1308 | editor.rs:3078、3295-3305 | proven |
| E-14 | Rust 新增选中块浮动按钮 | 原版无块级操作入口；Rust 多「删除此块/换图/选图」，其中删块单击即删、无确认（两版编辑页均无删除确认底表，此点本身一致） | editor.js 全文检索无 | editor.rs:5168-5257 | proven |

## 低严重度（29 条，合并后）

| 编号 | 项 | 差异一句话 |
|---|---|---|
| A-5 | 右 fab z-index | 3003→3001（低于菜单面板 3002，几何不重叠、实际不可见） |
| A-6 | 坞内头像元素 | button→label、file input 位置不同；尺寸/摆位一致 |
| A-7 | 令牌单一出处 | 原版 tokens.js 运行时全局；Rust 散为多处常量副本（值一致，改一处全站生效的结构不存在） |
| A-8 | Rust 增补令牌 | --motion-*/--fs-body/--diag-* 为增补，原有令牌逐行 diff 逐值一致 |
| A-9 | body::before 渐变兜底色 | computed 取不到时 255 白 vs 250（几乎不触发） |
| A-10 | 拖拽指示体系 | 落点线删除、改长按拾起玻璃面——用户裁定的有意偏离 |
| A-11 | 图文卡图片裁剪 | img 多 max-height:468+object-fit:cover，高图取景与原版包裹层裁底部不同 |
| A-12 | will-change/死规则 | 菜单面板缺 will-change（无视觉差）；.detail.spread 多列规则永不命中（死规则，易误导维护） |
| B-14 | 占位符空判定 | 原版只看首子节点 text 真值；Rust 整块 trim——纯空格单段时原版不显、Rust 显占位 |
| B-15 | 自动聚焦时机/落点 | 原版固定 200/300ms 延时+宿主聚焦；Rust 就绪轮询+段首 offset 0；is_new 非单空段时聚焦目标块口径微差 |
| C-02 | paragraph 空态 | 原版 `<br>` 占位保高；Rust 只读态空 div（编辑态另行处理） |
| C-23 | 极短引用失焦 guard | 原版 `> a`（<2 字符）失焦不转预览；Rust 无等价 guard、会转预览 |
| C-27 | 公式失败兜底 | 硬错误原版 KaTeX 红式 vs Rust 红色原码；行内错误态少一层 .math-inline 包裹（未知命令红色续渲一致） |
| D-3 | 查询排序 collation | 非前缀命中次序：zh-Hans-CN collation vs Unicode 码点序，相邻序可不同（个例 inferred） |
| D-8 | 面板定位细节 | maxHeight 恒 320 非动态（靠下可能溢出）；z 9999→3500；未用 visualViewport（键盘弹起偏移 inferred）。**z 与 maxH 运行时实测属实** |
| D-13 | 代码块围栏自适应 | 正文含 ``` 时原版加长围栏、Rust 固定三反引号会被提前闭合；Rust 还先剥正文 md 前缀、原版保留 |
| D-14 | 图片/画廊尾随段 | 下一块已是空段时 Rust 仍多插一段（其余命令的尾随段检查一致） |
| D-16 | 图文混排占位 emoji | 📷 vs 🖼 |
| D-22 | 图片加载策略 | 原版 LazyImage 实际无调用点（无基线）；Rust 挂载即加载、无懒加载/两段式，占位为文案非骨架（长文档首屏成本 inferred） |
| D-24 | 最近使用胶囊位置 | 标题旁 vs 行尾 |
| E-7 | 菜单图标细节 | 背景图标紫色→accent 色；导出图标线宽 2.2→2.5 |
| E-8 | 入口 aria-label | 返回/更多/头像三入口 Rust 均无 aria-label；头像 button→label（与 A-6 同事分记） |
| E-9 | fab 触发时机 | onPointerDown→onclick（晚一个抬手）；stopPropagation 无对应（手感差 inferred） |
| E-12 | BgSheet 细节 | 色点无 aria-label；移除图标 20px→17px；选中勾写死 #007AFF 不随令牌（浅色等值） |
| E-13 | 导出文件名截断 | UTF-16 单元 vs Unicode 字符，星平面长标题截断点不同（边缘情形） |
| E-15 | Esc 关闭范围 | 原版各浮层互斥一次关一层；Rust 单次 Esc 可连关多层且未 preventDefault（多层同开可达性 inferred） |
| E-16 | 导出模型兜底标记 | 快照缺失时 heading/quote/todo 的兜底标记结构不同构（两版均罕见触发） |
| E-17 | MD 列表导出 | 原版存量文本直出；Rust 按节点重建、有序列表一律从 1 重编号、嵌套统一 2 空格（inferred，未双端同夹具实测） |
| C-26 | 公式呈现（已知取舍） | KaTeX(HTML+MathML) vs 纯 Rust MathML，用户已拍板接受；门控/防误判逐条一致 |

等价差异（不计缺陷，分片内有全文）：C-06 divider、C-07 image 形态、C-10 attachment、C-13 musicCard 五态、C-15 imageTextRow、C-16 embedCard 兜底、C-18 围栏单行边界、C-19 列表组分类路径、C-29 行内扩展语法、C-31 净化净效果、C-32 列表预览、C-33 门控总口径、D-23 video 超集、C-20 表格、C-24 标题/分隔线、C-25 脚注、C-22 Callout 结构。

## 运行时抽查（Chromium 口径，构建 1c9769e990）

探针：无头 Chromium（393×852 移动 + 1280×800 桌面），同构建 dist 本地服务，演示数据。

| 抽查项 | 结果 | 对应条目 |
|---|---|---|
| 斜杠面板打开行数 | 22 行，与原版项全集一致 | D 对照表 ✓一致 |
| 查询「bt」命中高亮 | 3 行命中，**mark 元素 = 0** | **实证 D-4** |
| 斜杠面板 z-index / max-height | 3500 / 固定 320px | 实证 D-8 |
| 桌面双栏形态 | `.editor-body.is-flow-columns` + 2 个物理 `.editor-column`（栏宽 ≈603.5/1248） | 实证 A-1/H-9 |
| 桌面正文行高 | computed 27.52px = 16×**1.72** | **推翻 A-1 行高子项**（规则在 Rust editor.css:745） |
| 斜杠空态 | 探针直接改 DOM 文本破坏了 token 跟踪、面板关闭，未取得有效读数 | D-5 仅代码 proven，活体未验 |
| 媒体跨栏 | 6 篇演示备忘均无图片/画廊/音乐块，未取得读数 | A-2 仅代码 proven |

## 已核一致面（103 项，摘要）

- **样式体系**：tokens 全表逐行 diff 逐值一致（除增补）；玻璃三层与回退、正文顶部 padding safe+155、底安全区双层叠加、坞摆位、双 fab 几何、进/出场动画曲线与关键帧、宽屏 72ch 居中、独立滚动双栏高度公式与开关行全套、菜单/导出面板定位与 220ms 链式时序、斜杠行度量、反向链接区摆位——A 片 20 项。
- **编辑行为**：组字守卫总闸、Enter 拆块/Shift+Enter 软换行、heading/callout 回车口径、退格合并紧邻判定、左右方向键跨块、xsel 跨块选区与复制口径、Ctrl+A、粘贴纯文本/URL 成卡/图片成附件、智能前缀集合与守卫、实时高亮 ==、撤销 600ms 合并/100 上限/基线口径、md 预览点击回源码、失焦回顶、尾随段补齐、待办勾选、卡片解析后光标落点、双栏阅读序与估高回退表逐值——B 片 26 项。
- **块与 md**：表格、脚注、Callout 结构/SVG 图标/折叠/16 类型映射、分隔线/setext 门控、门控总口径、行内扩展语法（~~/==/上下标/wiki 链）、musicCard 五态、行内基础格式与 flanking 防误判（有预言机回归测试锁定）、列表预览 strip 移植——C 片 10 项。
- **斜杠与卡片**：22 项全集（名称/副标题/关键词/拼音/shortcut/分组）逐项一致；分组与最近使用（上限 6、存储序）、面板宽/left/top 公式逐项移植、令牌整体剥离、各命令工厂形态、音乐胶囊解析全链、链接卡 ready DOM 逐项同值、文件卡、图片卡度量、图文卡/混排结构——D 片 32 项。
- **菜单与导出**：菜单/导出面板外壳度量与时序、导出三格式全集与副标题字数口径（连链接卡计字怪口径都复刻）、MD 语义导出主体、HTML 快照文档骨架与 chrome 页眉、PDF 时序、BgSheet 8 色与「卸载时点才生效」、入口可达性与空笔记返回即删、两版皆无删除/置顶/分享菜单项与删除确认底表——E 片 15 项。

## 有意偏离清单（非缺陷，备查）

1. A-1/H-9 双栏物理容器——用户「左右栏独立容器」决策（代价见 H-8）。
2. A-10 拖拽长按拾起——用户 2026-11-22 裁定（去拖柄/落点线）。
3. B-1 todo/quote 回车——调优结论，代码自述偏离。
4. B-2 段首退格保文本——修复原版丢字缺陷，不建议回退。
5. C-26 公式 MathML 路线——用户拍板接受视觉差异。
6. C-17/D-23 Rust 独有块类型与 video 渲染——超集扩展（与原版同数据呈现不一致，是否保留由产品口径定）。
7. 设置页谷歌备份入口移除——用户裁定（编辑页范围内两版皆无此入口）。
8. E-14 选中块浮动按钮——Rust 新增入口（删块无确认一点建议单独裁定，不归入「有意」）。

## 审计边界

- 全部结论为静态代码对照 + 上表 7 项运行时抽查（Chromium 口径）；B-11/B-12/D-7③/D-12/E-9/E-15/E-17 等 inferred 项未做活体量测，真机（iOS WebKit）行为未验。
- 标题胶囊内部、列表页时间流与卡片叠加、设置页本体不在本审计范围。
