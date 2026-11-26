# 分片 B 审计：正文编辑行为（输入 / 选区与光标 / 键盘 / 粘贴 / 占位符 / 自动聚焦 / 撤销 / 滚动 / 点按与长按）

## 覆盖声明

- 原版已完整通读：`src/app/editor/use-editor-dom.js`（729 行，全）、`src/app/editor/use-history.js`（305 行，全）、`src/app/editor/lifecycle-hooks.js`（69 行，全）；`src/app/editor.js`（3339 行）中编辑行为部分已通读：跨栏光标 `moveCaretAcrossEditorColumns`（:55-101）、尾随段 `ensureTrailingParagraphBlock`（:410-421）、首次挂载自动聚焦（:550-557）、卡片 hydrate 选区保存/恢复（:955-1009）、滚动阈值监听（:1010-1027）、`handleEditorBeforeInput`（:1753-1768）、`handleEditorInput`（:1769-2024）、`handleEditorKeyDown`（:2025-2144）、`handleEditorPaste`（:2145-2271）、非 autoFocus 自动聚焦（:2376-2392）、正文宿主 props（占位符/组字/事件绑定，:3250-3268）。结构渲染、菜单/导出、标题输入为略读（另有分片负责；标题归 title_controller 线，本片不审）。
- Rust 已完整通读：`rust/apps/web/src/editor/bridge.rs`（2003 行，全，含 EDITOR_JS 桥、跨块选区 xsel、长按拾起引擎）；`rust/apps/web/src/editor/columns.rs`（108 行，全）；`rust/apps/web/src/editor.rs`（6074 行）中编辑行为相关部分已通读：历史栈 `hist_push/step_undo/step_redo/restore_focus`（:120-315）、typed/占位与自动聚焦（:1316-1410）、桥消息循环与关闭全量同步（:1680-1705、:2224-2245）、菜单撤销路径（:2345-2390）、占位符 class 判定（:3166-3172、:3224-3228）、`handle_bridge_msg` 编辑 op 分发（:3530-3950）、`op_split`（:3974-4098）、`op_merge/prev_sibling`（:4099-4232）、`op_replace_range`（:4330-4460+）、`op_paste_text`（:4652-4712）。
- 长按拖拽排序：原版拖拽为未接线死代码（`onDragStart/onDragEnd` 无元素设 draggable），Rust 为用户裁定的长按拾起新交互——按任务口径只记事实、不记差异（见一致清单末项）。
- 证据等级：proven = 代码原文直接可证；inferred = 由代码路径推断、未做活体验证。

---

### B-1 待办/引用块回车：原版整块后插空段，Rust 改为同型拆分延续
- 结论：有差异
- 原版：`src/app/editor.js`:2080-2114 `handleEditorKeyDown`——Enter 且块 `dataset.type !== 'paragraph'`（含 todo/quote/heading 等）时一律 preventDefault，在该块后插入一个空 `<p>` 并聚焦，**不拆分原块文本**（卡片文字区除外，走浏览器默认）。
- Rust：`rust/apps/web/src/editor.rs`:4048-4070 `op_split`——heading/callout 保留原版口径（整段保留+后插空段）；但 todo/quote 改为「有内容按光标拆为同型新块（新待办未勾选）、空块回车自身转段落退出」，代码注释自述为「调优评估结论，偏离原版 B1 口径」。
- 差异：todo/quote 中间按 Enter：原版光标后文本留在原块、新空段在块后；Rust 光标后文本进入一个新的 todo/quote 块。空 todo/quote 回车：原版块保留、其后多一空段；Rust 原块就地变段落。属已知的有意偏离，但行为语义不同。
- 严重度：高
- 证据：proven（双方代码原文；Rust 注释自述偏离）

### B-2 段首退格遇紧邻原子块：原版文本被吸入原子块后丢弃，Rust 删原子块保文本
- 结论：有差异
- 原版：`src/app/editor.js`:2116-2143 `handleEditorKeyDown` 的 Backspace 分支只处理「当前块为空」一种情形；非空块段首退格不拦截、走单宿主原生合并——文本被吸入前一原子块 div，落盘 parse 时被丢弃（数据丢失）。
- Rust：`rust/apps/web/src/editor.rs`:4196-4228 `op_merge` 的 `PrevKind::Atomic` 分支——当前块非空时删除原子块、当前块与文本原样保留、光标仍在段首；代码注释明确「原版此处…数据丢失缺陷，不复刻」。
- 差异：[段][图][段] 布局下后段段首退格：原版删图后文本（实际丢字）；Rust 删图保字。属有意修复型偏离，但按键结果语义不同。
- 严重度：高
- 证据：proven（Rust 注释引活体实证；原版分支覆盖范围为代码直证）

### B-3 空块退格且紧邻原子块：原版越过原子块落到更早文本块末尾，Rust 只选中原子块
- 结论：有差异
- 原版：`src/app/editor.js`:2125-2141——空块退格时 `target` 沿相邻块向前跳过所有 `contentEditable==='false'` 块，删空块后把光标放到那个**更早的文本块末尾**；若前面只有原子块/无块，则 preventDefault 保留空段。
- Rust：`rust/apps/web/src/editor.rs`:4183-4195 `op_merge`——紧邻上一块是原子块且当前块为空时，删空块并把原子块置为选中态（`sel_block`），不移动光标到更早文本块；需再按一次退格才删原子块（两步流）。
- 差异：[文本][图][空段] 空段退格：原版一步落到文本末尾可继续打字；Rust 一步只选中图片、无文本光标，焦点承载方式不同。
- 严重度：中
- 证据：proven

### B-4 普通打字的模型同步与撤销粒度：原版 80ms 防抖落模型+记撤销点，Rust 普通打字不逐段同步模型
- 结论：有差异
- 原版：`src/app/editor.js`:1922-1928 `handleEditorInput`——每次 input 后 80ms 防抖 `parseEditorDOM` 落模型，文档变化即 `recordUndoPoint()`（600ms 合并）；撤销粒度≈每个输入爆发一段。
- Rust：`rust/apps/web/src/editor/bridge.rs` input 监听（EDITOR_JS）——普通段落打字只做斜杠检测与智能前缀 80ms 防抖（命中模式才发 `pasteSync`），**不发任何模型同步消息**；全文同步靠 20s 定时器/`visibilitychange` 的 `sync` op（`editor.rs`:3905-3919，该 op 只写持久副本、不动 doc 信号、不压历史栈）、关闭时 `__mnSyncAll`（`editor.rs`:2237）、以及 undo/redo/replaceRange/moveBlock 消息自带的 sync 快照。
- 差异：会话内 doc 模型可滞后真实文本最长约 20s（影响字数统计、双栏分界、反链等读 doc 信号的派生显示）；按 Ctrl+Z 时 `step_undo` 先把当前全文压栈再回退一步，回退落点是上一个结构性/同步快照——连续打字数分钟后一次撤销可整段回退，而非原版的最近一个输入爆发。
- 严重度：高
- 证据：proven（桥 input 监听与 sync op 实现原文）

### B-5 iOS 三指撤销/重做手势（beforeinput historyUndo/historyRedo）缺失
- 结论：有差异
- 原版：`src/app/editor/use-history.js`:285-296——在 editorBody 上监听 `beforeinput`，`inputType==='historyUndo'/'historyRedo'` 时 preventDefault 并异步调 undo/redo。
- Rust：全仓检索 `historyUndo`/`beforeinput` 在 `rust/apps/web/src/` 下**零命中**（桥与 editor.rs 均无此监听）；撤销入口只有桥 keydown 的 Ctrl/Cmd+Z/Y 与菜单按钮（`editor.rs`:2349-2390）。
- 差异：iOS 三指滑动撤销/重做在 Rust 版无响应；原版可用。
- 严重度：高
- 证据：proven（原版代码原文 + Rust 全量 grep 零命中）

### B-6 撤销/重做的选区恢复：原版普通快照路径不恢复选区，Rust 强制恢复焦点
- 结论：有差异
- 原版：`src/app/editor/use-history.js`:193-232 `undo` 快照路径——`el.innerHTML = renderDocToEditorHTML(...)` 后只 `setRenderKey`+autosave，**不恢复选区/焦点**（选区恢复仅 `recordUndoTransaction` 条目携带 `restoreSelection`，:229 才走 `restoreEditorSelection`）；单宿主焦点仍在宿主内但光标位置丢失。
- Rust：`rust/apps/web/src/editor.rs`:185-212 `restore_focus` + :214-262 `step_undo`——每次撤销/重做都按操作前块 id+偏移（钳制到新文档长度）恢复光标，块不存在则落第一个可编辑块首。
- 差异：撤销后光标落点不同：原版无定义落点（浏览器默认），Rust 确定性回到操作前块。属改进型差异，但与原版可观察行为不一致。
- 严重度：中
- 证据：proven

### B-7 历史条目不含双栏 layout 快照；原版 patch 双轨（recordOp）在 Rust 无对应
- 结论：有差异
- 原版：`src/app/editor/use-history.js`:84-99 `recordUndoTransaction` 与 :193-262 undo/redo——每条历史含 `layout/redoLayout`，撤销/重做时 `restoreLayout` 恢复双栏分界与滚动模式；另有 :102-128 `recordOp` patch 双轨（200ms 防抖合并、insert/update/remove 逆操作、与快照同栈、上限 100）。
- Rust：`rust/apps/web/src/editor.rs`:134-168 `hist_push`——历史栈元素仅为 doc 的 JSON 字符串，无 layout 字段；`step_undo/step_redo` 只还原 doc 并 `epoch+1` 重挂载，栏分界由现行 layout 锚经 `columns.rs:normalize_boundary` 重新归一。
- 差异：撤销一次跨栏移动/分界变化的操作时，原版连同栏布局一起回到旧态；Rust 文档序恢复但栏锚不随历史回退，分界按归一规则重算，可能与撤销前所见栏分布不同。patch 双轨缺失本身对用户不可见（快照轨覆盖），仅记 layout 一项为实质差异。
- 严重度：中
- 证据：proven（hist_push 签名与 step_undo 原文）

### B-8 跨块选区粘贴的多行文本：原版整段留在单块内换行，Rust 拆成多个段落块
- 结论：有差异
- 原版：`src/app/editor.js`:2262-2270 `handleEditorPaste`——纯文本粘贴一律 `execCommand('insertText', text)`，选区（含跨块原生选区）被替换，`\n` 成块内换行，不拆块；随后 80ms parse 落模型。
- Rust：`rust/apps/web/src/editor/bridge.rs` paste 监听——无 xsel 时同走 `insertText`+`pasteSync`（一致）；但 xsel（跨块虚拟选区）激活时走 `sendReplace(pt)` → `editor.rs`:4375-4405 `op_replace_range` 按 `\n` 切分：首行并入起始块、中间行各成新段落块、末行接尾部残文。
- 差异：跨块选区上粘贴多行文本：原版结果为一个块内多行；Rust 结果为多个段落块（块数、后续 Enter/退格行为随之不同）。另注：`op_paste_text`（`editor.rs`:4652，同为多行拆块实现）在桥内无任何发送方，为不可达代码，其文件头注释（columns.rs:8-9）描述的「多行粘贴拆块」并非现行粘贴路径的实际行为。
- 严重度：中
- 证据：proven

### B-9 音乐输入胶囊的粘贴事务（错位粘贴回收）缺失
- 结论：有差异
- 原版：`src/app/editor.js`:1715-1751 `captureMusicPasteTransaction` + :1753-1768 `handleEditorBeforeInput` + :2145-2171 paste/:1769-1860 input——粘贴前快照全部块，粘贴被浏览器错位落到别的块时，在 input 阶段 diff 出插入的 URL 段、回滚目标块并转交音乐胶囊解析。
- Rust：`rust/apps/web/src/editor/bridge.rs` paste 监听 musicInput 分支——仅当粘贴目标本身是胶囊且剪贴板文本含 URL 时发 `musicInput`；无 beforeinput 快照、无错位回收。胶囊内普通输入由 input 监听发 `musicInput` 复检（此部分一致）。
- 差异：iOS/WebKit 把粘贴重定向到邻块时，原版能回收 URL 并解析成卡；Rust 会把 URL 当普通文本落进邻块、胶囊仍停在输入态。
- 严重度：中
- 证据：proven（原版事务三段代码 vs 桥 paste 分支原文）

### B-10 撤销快捷键的作用域：原版全局 window 监听，Rust 仅编辑块内桥 keydown
- 结论：有差异
- 原版：`src/app/editor/use-history.js`:269-282——`window.addEventListener('keydown')` 全局拦截 `(meta|ctrl)+z`（shift→redo）与 `(meta|ctrl)+y`，不判焦点位置（焦点在正文宿主外、如点过原子块后焦点落 body 时仍生效）。
- Rust：`rust/apps/web/src/editor/bridge.rs` keydown 监听挂在 root 上且首行 `editableOf(e)` 为空即返回——焦点不在某个可编辑块内时 Ctrl/Cmd+Z 不被接管（document 级监听只处理选中块的 Backspace/Delete/Escape）；菜单撤销按钮需先全量同步再走同一 step_undo（`editor.rs`:2349-2365）。
- 差异：点选原子块/焦点落 body 后按 Ctrl+Z：原版撤销，Rust 无反应（浏览器原生 undo 对模型无作用）。大小写处理 Rust 用 `toLowerCase` 归一、原版精确匹配 `'z'` 靠第二分支兜 Shift+Z，两边净效果相同，此点不记差异。
- 严重度：中
- 证据：proven

### B-11 组字结束无显式重放：原版 compositionend 主动跑一次输入管线，Rust 只翻标志
- 结论：有差异
- 原版：`src/app/editor.js`:3260 正文宿主 `onCompositionEnd`——清 `isComposingRef` 后**显式调用 `handleEditorInput(e)`**，保证组字提交文本立即走斜杠检测、80ms 落模型与智能前缀管线；keydown 守卫含 `keyCode===229`（:2026）。
- Rust：`rust/apps/web/src/editor/bridge.rs` 开头——`compositionstart/end` 只置 `composing` 布尔；input 监听在 `composing` 时直接 return，compositionend 后不重放任何处理；keydown 守卫只查 `composing || e.isComposing`，无 229 兜底。
- 差异：组字提交后的斜杠面板弹起/智能前缀转换/模型同步依赖浏览器在 compositionend 后再补发一次 input 事件——多数引擎会发，但这不是原版所依赖的保证路径；不发时要等下一次击键或 20s 同步。keyCode 229 单独出现的旧式 IME 事件序列下，Rust 的 Enter/退格分支可能抢先执行。
- 严重度：中
- 证据：inferred（桥无重放为 proven；实际是否漏检取决于引擎事件序，未活体验证）

### B-12 上/下方向键跨块的判定方式：原版原生视觉行移动，Rust 首/末行阈值+hit-test
- 结论：有差异
- 原版：单宿主 contentEditable，ArrowUp/Down 全程浏览器原生（按视觉行移动，可进入卡片文字区、跨越原子块相邻行）；仅 ArrowLeft/Right 有自研跨栏函数 `moveCaretAcrossEditorColumns`（`src/app/editor.js`:55-101，且仅当候选块在**另一栏**时才接管）。
- Rust：`rust/apps/web/src/editor/bridge.rs` `crossBlockArrow`——Up/Down 仅当光标行距块顶/块底 < 0.9 倍行高时接管，用 `caretRangeFromPoint` 按光标 x 在相邻可编辑块首/末行落点，失败回落块首/块尾；目标集合只有可编辑文本块（原子块、卡片文字区不可达）。
- 差异：边界行附近（0.9 行高阈值带内）的 Up/Down 落点 x 可能与原生视觉行结果不同；光标在原子块相邻行时原版可原生移入/移出卡片文字区，Rust 只能在文本块之间跳。Left/Right 的净效果（块首/尾跨块、跳过不可编辑岛）两边一致，不记差异。
- 严重度：中
- 证据：inferred（阈值与目标集合为 proven；落点偏差幅度未活体量测）

### B-13 原子块/卡片的点击插段区：原版卡片用右 15% 区、附件用左右 28px，Rust 统一左右 28px
- 结论：有差异
- 原版：`src/app/editor/use-editor-dom.js`:171-194——`imgTextCard/imageTextRow/image/gallery/musicCard/divider` 点击落点 `clientX-rect.left > rect.width*0.85`（右 15%）才在块后插段；同文件 :313-366 原子附件则用左右 28px 边带（左插段前、右插/聚焦段后），中央区另有分享/打开行为。
- Rust：`rust/apps/web/src/editor/bridge.rs` click 监听——所有 `.blk-wrap` 统一 `x<28` 插段前、`x>width-28` 插段后、中央 `selectBlock` 选中（链接/图片灯箱优先放行）。
- 差异：宽卡片（宽 > ~187px 时 15% > 28px）右侧点击：原版在 28px~15% 区间内不插段（走图片区/灯箱等逻辑），Rust 在 >28px 处只选中不插段的区间与原版重合但插段触发带更窄；窄卡片则相反，Rust 28px 带宽于原版 15%。点击落点语义分区不同。
- 严重度：中
- 证据：proven

### B-14 占位符显隐的空判定：原版只看首个子节点文本，Rust 用整块 trim 后文本
- 结论：有差异
- 原版：`src/app/editor.js`:3250——`show-placeholder` 条件为 `!hasTyped && doc.length===1 && type==='paragraph' && !(children[0] && children[0].text)`，即只查**第一个子节点的 text 真值**：首子节点为纯空格字符串时条件不成立、不显占位符。
- Rust：`rust/apps/web/src/editor.rs`:3166-3172、:3224-3228——条件为 `!typed && len===1 && paragraph && plain_text().trim().is_empty()`，整块文本 trim 后为空即显。
- 差异：单空段里只有空格（或首子节点为空但后续行内节点有空白）时：原版不显占位符，Rust 显示占位符（占位文案与空格叠显）。hasTyped/typed 的置位口径本身一致（见一致清单）。
- 严重度：低
- 证据：proven

### B-15 自动聚焦的时机与落点：原版固定 200/300ms 延时+宿主聚焦，Rust 就绪轮询+段首落点
- 结论：有差异
- 原版：`src/app/editor.js`:550-557——`autoFocus` 时挂载后 200ms `focusEditorBlock(el, firstBlock)`；:2379-2392——非 autoFocus 且文档为单个全空段落时 300ms 同样聚焦首块。聚焦动作是宿主级 `focus()`（经 columns 的 focusEditingHost），光标落点由浏览器落在块内默认位置。
- Rust：`rust/apps/web/src/editor.rs`:1348-1410——`is_new || 挂载时单个空段` 统一判定（use_hook 锁定），挂载即尝试、未就绪以 10ms 间隔轮询 `__mnFocus(fid, 0)`（上限 2s），光标**明确落在段首 offset 0** 并带出视口才滚动的 ensureVisible。
- 差异：聚焦生效时刻不同（Rust 通常快于 200ms）；is_new 但文档非单空段时 Rust 聚焦「第一个段落块」，原版 autoFocus 聚焦 getBlocks 的第一块（可能是非段落块宿主）。净体验接近，记为低。
- 严重度：低
- 证据：proven

---

## 已核一致项清单

- 组字守卫总闸：keydown 在组字中一律放行（含斜杠面板开着时拼音回车/方向键不被面板抢走）——原版 editor.js:2026 / Rust bridge keydown 首行 `composing || e.isComposing` return。
- Enter 普通段落按光标拆块、选区未折叠时选区内容被前后文夹断丢弃：原版原生拆分+parse / Rust `split` op 的 beforeHtml/afterHtml 口径一致。
- Shift+Enter 块内软换行（`<br>`→模型 `\n`）：原版放行原生 / Rust `insertLineBreak`+`pasteSync`。
- heading/callout 回车不拆文本、整段保留+后插空段聚焦：editor.js:2080-2114 / editor.rs op_split styled 分支。
- 空列表项回车退出列表：Rust op_split Item 分支与原版列表语义一致（原版经 md 列表组渲染路径同口径）。
- 非空块段首退格与上一文本块合并、光标落接合点：原版原生合并 / Rust op_merge Text 分支+junction 落点。
- 退格合并绝不越过紧邻原子块去找更早文本块（除 B-2/B-3 的原子块处理方式外，紧邻判定一致）：editor.rs prev_sibling 注释与原版单宿主相邻语义。
- 方向键 Left/Right：块首/尾、折叠选区、无修饰键时才跨块，跳过不可编辑岛，落相邻块尾/首：editor.js:55-101 / bridge crossBlockArrow。
- 跨块选区存在性：原版单宿主原生跨块选区 / Rust xsel 虚拟选区（端点 UTF-16 偏移、CSS Highlight 绘画、源码态块不可跨越）——可达状态与复制文本（块间 `\n\n` 连接）口径一致；其粘贴多行差异见 B-8，字符级键入/退格/回车经 replaceRange 落地。
- Ctrl+A 全文选区：原版原生 / Rust selectAllXsel（首块首→末块尾，fromStart/toEnd 标记）。
- 粘贴只取纯文本、富文本格式一律不带（有 text/html 也只用 text/plain）：editor.js:2262-2270 / bridge paste `insertText`+`pasteSync`。
- 粘贴纯 URL→链接卡、文本内嵌媒体 URL→链接卡、内嵌普通 URL 且非 Markdown→链接卡+剩余文本保留：editor.js:2172-2206 / bridge pasteCard 三分支（URL 正则细节为等价实现差异）。
- 粘贴图片文件→附件/图片块插入：editor.js:2240-2258 / bridge pasteImage（FileReader→base64→IDB）。
- 音乐胶囊：回车以当前文本尝试解析、段首退格删块回上块、输入含 URL 即解析、胶囊文本不进斜杠检测不落模型：use-editor-dom.js blur 音乐处理 + editor.js resolvePendingMusicUrl / bridge musicInput/musicDelete 分支（粘贴事务差异见 B-9）。
- 智能前缀转换集合与守卫（`#{1,3} `、`>` 非 callout、`[ ] `/`[] `、`---`；斜杠面板开时跳过；转换后光标落转换块文本末尾并 scrollIntoView nearest）：editor.js:1932-2015 / bridge 80ms 防抖检测 + editor.rs apply_smart_prefix。
- 实时高亮 `==…==` 闭合即包 `<mark>`、零宽空格防光标吸入、组字期间不触发：bridge realtimeHighlight（原版对应 input 管线同行为）。
- 撤销合并窗口 600ms、上限 100 步、撤销/重做后清合并链（lastPushAt 归零）：use-history.js:176-191、:232 / editor.rs hist_push（600.0/100）与 step_undo/step_redo 的 hist_clock 归零（粒度差异见 B-4）。
- 撤销/重做快捷键集合 Ctrl/Cmd+Z、Ctrl/Cmd+Shift+Z、Ctrl/Cmd+Y：use-history.js:269-282 / bridge keydown undo/redo 分支（作用域差异见 B-10）。
- 历史基线：打开时的文档为栈底、首个撤销点只立基线不压栈：use-history.js recordUndoPoint 首调分支 / editor.rs hist 初始单元素栈。
- md 预览块点击还原为源码编辑、光标落末尾；表格逐行恢复为多段：use-editor-dom.js:139-150、:202-262 / Rust mdEdit+__mnFocusAtMount 守卫落点（挂载竞速守卫为实现差异，落点语义一致）。
- md 源码/代码块内回车为块内换行、段首退格可合并/删块：bridge codeBlock/mdsrc keydown 分支（原版单宿主原生+Backspace 分支同净效果）。
- 失焦处理：blur 后延迟转 md 预览（原版 400ms 定时器 / Rust active_edit 失焦转换）、失焦回顶 scrollTo(0,0)+80ms×6 次重试、焦点转标题坞则停：use-editor-dom.js:425-470 / bridge focusout+forceTop（editor.rs:3576-3584）。
- 焦点在正文间移动不触发回顶、不清编辑态：use-editor-dom.js handleEditorBlur 的 relatedTarget 包含判定 / bridge focusout 的 activeElement 包含判定+500ms 内点按过编辑区豁免。
- 原子块后必须有可编辑空段落（尾随段补齐，含文档末尾原子块）：editor.js:410-421、:430-441 / editor.rs 尾随空段模型化 effect。
- 待办复选框点击：切换 checked 落盘、空文本待办不响应、键盘触发（detail=0）不抢焦点：use-editor-dom.js:386-423 / Rust blocks 待办渲染路径同口径（本片按 bridge/editor 范围核对事件语义）。
- 卡片解析完成后光标落到卡片下方一行开头：editor.js focusCaretBelowResolvedCard / editor.rs card_caret 通道。
- 双栏内编辑：块序按左栏后右栏的阅读序、栏内编辑不跳栏、layout 锚归一（right 首存活块为右栏起点）：editor.js getBlocks/captureCurrentColumnLayout / columns.rs:normalize_boundary（规范估高分界为确定性实现差异，分界语义口径一致；估高回退表 280/120/28+行×25 与原版 editorBlockHeight 回退表逐值一致）。
- 选区保存/恢复基础设施：selectionchange 时克隆 Range 保存、行内命令/链接插入前恢复：editor.js savedRange 路径 / bridge savedRange+restoreSel（斜杠行内命令的偏移重建为实现差异，见 bridge applyInline）。
- 页面隐藏/关页落盘：pagehide+visibilitychange hidden 时清防抖立即 save+DraftStore：lifecycle-hooks.js:16-42 / bridge visibilitychange sync + editor.rs 关闭全量同步（正文侧等价；草稿存储细节归持久化分片）。
- 长按拖拽排序（事实记录，不记差异）：原版 editor.js:2393-2450 的 HTML5 拖拽为未接线死代码；Rust bridge 为用户裁定的长按拾起新交互（触屏 480ms/桌面文本块 hold 280ms/原子块移动 6px、光标在文本块内不武装、FLIP 让位、边缘自动滚动、落位后 moveBlock 落盘并压历史栈）。
