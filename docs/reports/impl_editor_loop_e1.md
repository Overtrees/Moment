# E1 编辑回路根治批报告

依据：docs/reports/audit_editor_deep.md 域一（编辑回路）——F-01 组字守卫、F-02 智能前缀、F-08 段首原子前驱退格、M-01 斜杠触发面、M-02 粘贴块型守卫、m-01 标题 Esc 组字守卫，及主线追加定案项 M-06。

批次状态：M-06 专节先行落（纯定案、无落码，见下）。其余六项（F-01/F-02/F-08/M-01/M-02/m-01）已于落码门开后落码完毕——门状态：0.9.58 组版提交落定、HEAD = cb8ff18、开工时树净；落码期间同树另有八批并行（搜索命中集 / OPS 口径 / SVG 解码 / 桥呈现 / 天气 / 备份等），全程 git diff 快照映射、逐 hunk 避让、完工复验他人 hunk 完好（详见文末自检节）。未提交、未 bump，随下一组版。

---

## M-06 代码块 Enter 语义定案（主线追加项）

### 审计口径

audit_editor_deep.md M-06（形态级，证据等级 inferred）：原生 codeBlock 内 Enter 放行块内换行；审计疑 Web 模型层为拆块口径——推论依据是 ops.rs `op_split` 的通用路径对未列名块型一律拆出 paragraph 新块，codeBlock 未见特例。

### 回源定案：Web 为块内换行，原生现状即达标（proven，双侧源码行级）

**1. Web 的 Enter 分流在 JS 桥先行完成，split op 根本不到达 codeBlock。**

- `rust/apps/web/src/editor/js/editor.js:890-905`：keydown 处理对 `codeBlock`/`mdsrc` 设独立分支，注释明言「md 源码/代码块（编辑态审计 B11）：回车仍是块内换行放行原生」；该分支仅拦截段首（caret offset 0）的 Backspace 发 `merge` op，其余按键（含 Enter）不 preventDefault、直接 return，Enter 由浏览器原生在块内插入换行。
- 通用 Enter → `split` 分支在 `editor.js:906` 之后，codeBlock 永不到达。
- `rust/apps/web/src/editor/ops.rs:325` 的 `op_split` 确无 codeBlock 特例：heading/callout 有整段保留 + 插空段特例、todo/quote 有空块退出特例、其余走通用拆分（新块型 list-item/todo/quote 同型、余皆 paragraph）。但 dispatch 的 `"split"` 分支只转发桥消息，桥从不为 codeBlock 的 Enter 发 split——该通用路径对 codeBlock 不可达。审计的「拆块」推论是只读模型层、漏读桥分流的结果，就此推翻。
- 旁证同向：粘贴路径 `editor.js:1803、1814` 把 codeBlock 与 mdsrc 同组——多行粘贴不走 `pasteText` 拆块、留在块内；输入同步面 `collectInputSyncMap` 只排除 mdsrc/musicInput，codeBlock 全文（含 `\n`）经 inputSync 整块同步，模型以单块多行文本持有代码块。

**2. 原生现状逐项对齐。**

- `rust/apps/ios/app/MomentApp.swift:2995-2996`（Coordinator `shouldChangeTextIn`）：替换文本含 `\n` 时 codeBlock 支 `return true`（注释「代码块内换行是正文」），放行 UITextView 在块内插入换行——与 Web 同口径。
- 段首退格：原生同函数段首支对 codeBlock（`isText` 含 codeBlock）走 `mergeBlockBackward`，与 Web codeBlock 段首 Backspace 发 `merge` 同口径（其原子前驱等细目属 F-08 本批范围，本节不展开）。

### 处置

**M-06 关闭：Web 为块内换行口径，原生现状即达标，无落码、无断言新增。** 审计 inferred 项按源码定案销账，后续审计不再重复列报。

证据上限：本节为代码级 proven（双侧分流点行级对读）；行为未发生任何变更，不新增真机终判点，codeBlock 编辑体验随 E1 批其余条目的真机终判一并观察即可。

---

## F-01 拼音组字 · didChange 守卫（头号）

### 规格出处（Web 真源）

- `editor.js` 组字总闸：`composing` 标志由 compositionstart/end 维护，input 监听 `if (!el || composing) return;`——组字期模型冻结，中间态不入模型。
- compositionend 显式重放输入管线（B-11 口径）：组字期间被挡下的 input 在组字结束以目标块直调 processInput 重放一拍；斜杠检测/智能前缀等在重放拍随已提交文本复检。
- dispatch 侧：inputSync 等文本类消息只在组字外到达模型；组字期无落盘面。

### 原生落码

`BlockTextView.Coordinator.textViewDidChange`（MomentApp.swift）在 `resetArrowGoal()` 后、runs 写模型前加单点守卫：

```swift
guard tv.markedTextRange == nil else { return }
```

一处守卫同时收三面（与审计三缺陷面一一对应）：① runs/text 不写中间态；② `parent.onChange()`（即 scheduleSave 的 0.6s 防抖落盘）不排程；③ `updateSlash` 不以拼音中间态扫描（域三「斜杠触发-组字中」同根同收）。marked 清除后一拍（提交/取消均经 didChange 且 markedTextRange == nil）走原全量同步——提交瞬间全量重算 runs 的既有口径不变，终态同源无残留。此守卫与同文件既有三处组字守卫（shouldChangeTextIn 结构拦截、handleKey 方向键不消费、updateUIView 组字期禁反写）构成第四面、四面同口径。

断言：E43-1（守卫在 runs 入模型之前的行序锁）。

### 真机终判点（归用户，报告不升级表述）

拼音组字全程：候选选择停顿 >0.6s 时中间拼音串不得落盘（杀进程重开验）、组字中不弹斜杠面板、提交后文本与落盘一致。此面自检驱动与代码级断言均证不了，永远归真机 + Diag 成对行终判。

---

## F-02 智能前缀转换（整体移植）

### 规格出处（Web 真源）

- `ops.rs:1220 smart_prefix_match`：只看首行；`### /## /# ` + 非空 rest → Heading(level, rest.trim())；`>` + 非空 rest 且 rest（trim_start 后）非 `[!X` 标注形 → Quote(rest.trim())；`[ ] /[] ` + 非空 rest → Todo(rest.trim())；全文恰 `---`（不 trim）→ Divider。rest 仅空白时正文为空串仍命中（Web 同式）。
- `ops.rs:1271 apply_smart_prefix`：扫全 doc 顶层段落（文档序）、首个命中只转一处；转换 = apply_type 口径（同 id、单文本子节点、类型字段先清后设、正文为捕获纯文本、行内格式不保留）；焦点落新块文末（caret = 转换后文本长度）；divider 只原地替换、不补尾随段、焦点落 divider 本身 caret 0；转换后 persist。
- `dispatch.rs:705`：扫描挂文本类消息（pasteSync/mdText/split/merge/pasteText/inputSync）落定之后、同一消息内完成；斜杠面板/链接表单打开时跳过（showSlash 守卫）。
- `editor.js:1146` 注释同口径：智能前缀不在桥侧单独触发，落模型后同尾扫。

### 原生落码

- `EditorModel.smartPrefixMatch`：逐条镜像上表（含首行语义、`>` 标注负向前瞻按 trim_start 全空白语义实现、divider 全串相等）。
- `EditorModel.applySmartPrefixIfNeeded`：扫 `blocks` 顶层 paragraph（文档序）、首个命中只转一处；`slashBlockId/linkFormBlockId` 非空时跳过（Web 守卫同位）；命中先 `pushHistory()`（与原生 applySlash/setBlockType 的每 op 压栈粒度一致）。
- 文本类转换落点 `convertSmartPrefix`：与 applySlash 的 convert 同形——runs 置单文本段、children 以新 runs 重组、走转换单点 `convertNodeType`、焦点落转换后文本末尾（focusBlockId + pendingCaretOffset = text.count，原生字符口径）。
- divider 臂：node 原地换 divider（同 id、无 children）、nodeVersion 自增；该块若为编辑中块则清 editingBlockId（其文本视图随块型变更卸载、会话事实结束）；焦点落 divider 本身（focusBlockId = 该 id、pendingCaretOffset = 0），不补尾随段。
- 尾随空段：Web apply_smart_prefix 的 todo 臂**不**补尾随空段（补段是 op_convert 口径、另一路径），原生同口径不补。
- 调用点与 Web 消息尾一一对应（六处）：didChange 尾（inputSync）、insertLines 尾（pasteText）、splitBlock 尾（split）、mergeBlockBackward 尾（merge）、mergeListItemBackward 的 idx==0 出口与函数尾（merge）。组字期由 F-01 守卫在 didChange 早退、天然不到扫描。

### 跨批对账：B25-E3-1 改锚（第三调用点正当性）

桥呈现批完工复验发现 verify B25-E3-1 红：`convertNodeType(b` 出现第三处调用（本批 convertSmartPrefix 内）。逐点点名全集：

| # | 调用点 | 归属 | 语义 |
|---|---|---|---|
| 1 | `setBlockType` 体内 | E3 既有 | 块菜单转换路径 |
| 2 | `applySlash` 的 convert 闭包内 | E3 既有 | 斜杠转换路径 |
| 3 | `convertSmartPrefix` 体内 | **本批 F-02 新增** | 智能前缀转换路径 |

第 3 点为正当新调用面：F-02 转换与斜杠转换同构（同 id、单文本子节点、清旧字段后设新），E3 单点化的设计意图正是新转换入口必须经同一漏斗、不得另写一份清字段逻辑；本批若绕开 convertNodeType 自行清字段，才是与 E3 定案相悖的分叉。处置：B25-E3-1 按「调用点全集逐个点名」改锚——三段 awk 抽取（setBlockType / applySlash / convertSmartPrefix）各验恰 1 + 总数恰 3 兜底（防无名第四点混入、亦防任一点名路径脱漏斗），注释记明改锚事由并回指本节；实测 PASS。

断言：E43-2（匹配定义 1 + 尾扫调用点合计 7 + 四类分派齐备）、B25-E3-1（改锚后）。

### 真机终判点

行首键入 `# 标题`/`## ` /`### `、`> 引用`、`[] 待办`/`[ ] 待办`、`---` 四类转换形态与落点；多行粘贴「# 标题行\n正文」首块成标题、次块仍段落；`> [!NOTE] …` 不转引用。属行为走查面，真机终判。

---

## F-08 Backspace 段首 · 原子前驱死键

### 规格出处（Web 真源，ops.rs op_merge 现行口径）

- prev_sibling 分类：文本块（列表取末项）= Text；其余顶层非文本（含空列表）= Atomic；无前块 = None。
- Atomic 支：当前块**空** → 向前跳过全部连续原子块、落更早文本块末尾并删空块；无更早文本块则保留空块、无动作（Diag kept 行）。当前块**非空** → 不删原子块、不并文本，只把原子块带入选中态（sel_block = atom id，Diag「selected (kept)」）；editor.js:1587-1592 另钉：选中态下 Backspace/Delete 一律无操作——键盘永不删非文本块，删块走卡菜单明路。（注：audit_editor_full H-11 的「删原子块」是 K2 收口前的旧行为，现行 ops.rs 已收口为选中保留，本批以现行源码为准。）
- Item(li, 0) 经 classify_top 归同一分类：列表首项段首退格的前驱分类与顶层同规。

### 原生落码

- 新增视图态 `EditorModel.selectedBlockId`（@Published，不落盘）：置位面 = 下两支；清除面 = 进入文本编辑（Coordinator textViewDidBeginEditing，与 Web clearSelect 同口径）、选中块被 deleteBlock 删除、再次撞另一原子块时覆写。BlockRow 对非文本块在既有描边 overlay 后加一层选中描边（T.accent 2px、Radius.block、allowsHitTesting false）。
- `mergeBlockBackward` 末支（此前三分支全不命中、按键已被 shouldChange 吞掉的死键）：非空块 + 原子前驱 → `selectedBlockId = prev.id` + Diag「EDIT merge backspace before atomic {id} selected (kept)」（与 Web 行同形）。同函数空块无目标支补 Diag kept 行（Web 同口径、原仅静默 return）。
- `mergeListItemBackward` 首项支同型收口：非空首项 + 前块非文本且非「有项列表」→ 选中前原子块 + 同形 Diag。此前该支注释误记「Web 原子规则 = 无动作」，已按现行 ops.rs 更正注释。前为有项列表（Web 归 Text 类、应并其末项）不在本支处置范围、维持无动作，登记备忘待后续对账。

断言：E43-3（声明 1 + 两支赋值各 1 + Diag 行 2）。

### 真机终判点

文本块段首退格、前为图片/卡片时：原子块出现选中描边、文本与块均保留、再按退格无删除发生；删块仍走长按卡菜单。触摸/键盘投递面归真机终判。

---

## M-01 斜杠触发面守卫集对齐

### 规格出处

audit2 §3.2：Web 于 heading/quote 内不弹（原版 use-slash + blockquote 守卫）；原生 updateSlash 此前仅排除 codeBlock/callout，heading/quote/todo 均可弹。todo 不在 Web 排除之列（审计只点名 heading/quote），保留可弹。

### 原生落码

`updateSlash` 的 eligible 在既有 `!= codeBlock`、`!= callout` 后增 `!= heading`、`!= quote` 两条排除，注释记明出处。对齐后可弹集 = paragraph / todo / list-item，与 Web 一致。ineligible 时既有收口（slashBlockId 为本块则清）不变。

断言：E43-4（updateSlash 段内两排除各恰 1）。

### 真机终判点

标题块、引用块内输入 `/` 不弹面板；段落/待办/列表项内仍可弹。归真机走查。

---

## M-02 粘贴成卡块型守卫

### 规格与定性

审计口径：handlePaste 无块型守卫（proven），codeBlock 内粘贴 URL 疑走成卡判定、Web 代码块应留字面（触发面 inferred）。回源旁证：Web 代码块在其余全路皆字面口径——打字换行块内放行（editor.js:890-905）、多行粘贴不拆块不走 pasteText（editor.js:1803/1814 对 codeBlock 与 mdsrc 同组排除）、斜杠不触发（processInput 对 codeBlock 早退）；而成卡路径（op_paste_card）会改写目标块 children 为 before 行内集并在块后插卡，对代码块即毁代码内容。本批按审计处置落守卫，证据等级如实记为：守卫缺失 proven、Web 触发面 inferred、处置依据 = 代码块字面原则的一致性。

### 原生落码

`EditorModel.handlePaste` 入口首行加块型守卫：`if block.type == "codeBlock" { return false }`——返回 false 后上层 EditorTextView.paste 走 super.paste 原生插入，shouldChangeTextIn 的 codeBlock 支放行块内换行，粘贴文本（含 URL、多行代码）整段留字面。MD 源段落（原生为 paragraph 编辑态）在 Web mdsrc 的粘贴面与 codeBlock 分组关系仅限多行拆块排除、成卡分支未见排除，本批不扩面、仅守 codeBlock。

断言：E43-5（handlePaste 段内守卫恰 1）。

### 真机终判点

代码块内粘贴裸 URL 与多行代码：不出现卡片、文本原样入块。归真机走查。

---

## m-01 标题 Esc 组字守卫

### 规格出处

`title_controller.rs:868-871`：keydown 闭包先算 `composing = phase == Composing || ke.is_composing()`，composing（或 Idle）时 act = 0——Esc 不还原、不 blur，全忽略（Esc 归输入法）。

### 原生落码

- `TitleFieldControl` 新增 `composing` 读数面（普通 Bool，非 Published：唯一消费者 handleEscape 同步读，不驱动视图）。
- Coordinator 维护三点：editingChanged 与 textFieldDidChangeSelection 按 `f.markedTextRange != nil` 回写、textFieldDidEndEditing 清零（收敛律同位）。
- `EditorView.handleEscape` 标题支首行加守卫：`if titleControl.composing { return }`——组字中 Esc 不还原草稿、不辞焦；浮层优先级链前四支（链接表单/斜杠/底表/菜单）不受影响（审计范围仅标题支）。

断言：E43-6（TTF 声明 1 + 维护写点 2 + handleEscape 检查 1）。

### 真机终判点

硬件键盘标题组字中按 Esc：组字不被打断、不还原草稿、不辞焦；组字外 Esc 仍还原草稿并辞焦。硬件键盘 + 拼音组字，永远归真机终判。
