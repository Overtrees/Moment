# E2 撤销体系落码报告（审计 F-10 / F-11 / F-12）

2026-11-27 晚落码，基线 HEAD e12fc62（0.9.59），未提交、未 bump，随 0.9.60 组版。

## 一、现状盘点（落码前实测）

- 撤销本体：EditorModel 两裸数组 `undoStack/redoStack: [[String: Any]]`，`pushHistory()` 无条件 append 会话/结构边界快照、上限 50、清 redo；`applySnapshot` 只换 title/blocks/layout + scheduleSave；`undo()/redo()` 弹栈互压。F-10 三病全在：无爆发合并（粒度 = 整个聚焦会话）、无去重（未改一字落焦也压栈 → 幻影步）、上限 50（Web 100）。
- F-11：快照不带选区，applySnapshot 不回落 focusBlockId/pendingCaret；编辑中撤销换掉当前块视图对象致失焦（审计口径：无接线 proven / 失焦形态 inferred）。
- F-12：••• 菜单副文案宣称「Cmd+Z / 三指左滑」「Cmd+Shift+Z / 三指右滑」，两入口均未接线（全仓无 Cmd+Z 处理、无三指识别器）；UITextView 自带 undoManager 若被系统手势唤起将与模型栈双轨。
- Web 规格真源（ops.rs hist_push/step_undo/step_redo + model.rs restore_focus）：后态快照+指针、去重（snap==当前态跳过）、coalesce 600ms 替换栈顶、结构压栈断链、上限 100、undo/redo 后断链、restore_focus 按 focus hint（块 id+偏移、plain_len 钳制）恢复、块不存在落 first_editable。
- pushHistory 调用点约 35 处（会话开始 1 + 结构 op 与视图侧余数）——本批定案**签名不变、调用点零改动**，语义在漏斗内升级。

## 二、漏斗落点

新文件 **MomentUndo.swift**（Foundation-only 纯状态机，拒绝上帝文件红线）：`UndoHistoryCore<Payload>` 承载全部记账——返回点记录、爆发合并时钟、撤销/重做步进、条目附带选区（`UndoSel`：blockId + 字符口径 location/length）、结果量计数（mergedCount/dedupedCount/clampedCount）。EditorModel 只持一台核心（`private var history`），旧两裸数组删除、grep 零残留。

模型口径：原生既有「两栈返回点」形态与 Web「后态快照+指针」同构（undo 弹返回点应用之、当前态压对方栈），不推翻既有形态、只补规则——行为等价且实现更优。全部入口只经 `EditorModel.undo()/redo()` 二函数（断言 E47-1 普查守恒）：

| 入口 | 接线 |
|---|---|
| ••• 菜单撤销/重做行 | 既有（dimmed 仍由 canUndo/canRedo 驱动） |
| Cmd+Z / Cmd+Shift+Z / Cmd+Y（正文） | handleKey 顶部分发前拦截消费（pressesBegan 不上抛 super） |
| 三指左滑/右滑（正文） | EditorTextView 两枚 UISwipeGestureRecognizer（numberOfTouchesRequired=3）→ navEditor 漏斗 |
| Cmd+Z / Cmd+Shift+Z（标题字段） | 新 TitleField.pressesBegan 拦截 → onUndoKey 闭包 → 同漏斗 |

双轨封堵：EditorTextView 与 TitleField 各覆写 `undoManager` 恒 nil，系统撤销轨（摇一摇/系统手势）不介入。

## 三、合并 / 去重 / 钳制规则表

| 规则 | 机制 | 对齐 |
|---|---|---|
| 爆发合并 | 文本变更前馈入 `noteTextWillChange`：合并链活着且距上一键 <600ms 只续链（mergedCount++）；否则落新返回点（= 本次爆发开始前文档态）并起链。检查点接在 shouldChangeTextIn 的普通文本放行点全集 3 处（代码块换行 / Shift+Enter 软换行 / 末尾兜底），均在变更落模型前调，快照即变更前态 | Web coalesce 600ms 同值同义 |
| 断链 | 结构记录（recordOpBoundary）、undo、redo 后恒断链——结构 op 前后的键入不跨 op 合并 | Web hist_clock 归零同义 |
| 去重 | 向任一栈压入时 key == 该栈顶 key 则跳过（dedupedCount++）：会话开始锚与爆发首键同态只入一（幻影步根治）、结构 no-op 不起步、撤销/重做往返不堆重复条目。key = 快照 JSONSerialization sortedKeys 规范串（失败以唯一串兜底、永不误并） | Web「snap==当前态跳过」的返回点模型等价式 |
| 钳制 | 任一栈超 100 逐最旧（clampedCount 累计），常量 undoStackCap=100 / undoBurstWindow=0.6 单点声明于核心文件 | Web 上限 100 |
| 清重做尾 | 新记录（边界/文本起链）恒清 redoStack；新文本编辑清尾同 Web | 既有 pushHistory 口径延续 |
| 惰性求值 | 文本馈入的 entry 为惰性工厂：仅真要落返回点时求值一次——窗内逐键馈入不付全量快照 + 规范序列化成本 | 本批实现优化（行为无涉） |

净零爆发说明（逐场景验算过）：爆发内删回原样时，爆发返回点与当前态同键——撤销仍落回该态（视觉无变化、一步），与 Web 双条目殊途同归，不丢步不串篇。

与 E1 对齐：snapshot()/applySnapshot 本体未动（epoch/落盘/归属守卫面零触碰）；pushHistory 签名与调用点全集未动、语义升级在核心内完成；标题轨撤销作用于文档历史（标题草稿经 commitTitle 入文档后由快照覆盖），与标题会话快照（titleBase/Esc 还原）分工不交叉。

## 四、选区恢复机制（F-11）

- 记录面：每次落返回点时附 `currentSel()`——编辑中块视图的实时 selectedRange（UTF-16→字符换算，`EditorModel.charOffset`）优先；焦点请求在飞时取其落点（文末请求记 Int.max、恢复时钳制）；皆无为 nil。文本检查点的选区取被替换范围（爆发前选区）。
- 恢复面：undo/redo 应用快照后 `restoreSelection(sel)` 单点——目标块在恢复后文档中仍为文本单元（顶层文本块或列表项，item id 即焦点 id）时，按该单元字符数钳制落点与选区长度，经既有消费面投递（focusBlockId + pendingCaretOffset + 新增 pendingSelectionLength）；块已不存在落第一个文本单元首；全文无文本单元则清焦点请求。
- 投递面：updateUIView 两支（未持焦聚焦支 / 已持焦落点支）设 selectedRange 时 length = min(pendingSelectionLength, text.count − caret)，随既有 async 清理一并清零（必须 async：同步清会让同遍第二支把选区塌成 0）。其余路径 pendingSelectionLength 恒 0 = 纯光标，行为与旧版逐项等价。
- Diag：undo/redo 行续记 `merged=` / `dedup=` 累计量与 `focus=<块>@<落点>+<选长>` 回读串（保留「EDIT undo 余栈」前缀）；去重/钳制事件各有专行（`EDIT undo dedup skip depth=` / `EDIT undo clamp depth= evicted=`）。

## 五、断言（verify [47] E47-1..8，全绿）

- E47-1 漏斗普查：undo()/redo() 定义各 1；成员调用 .undo()/.redo() 各 3（菜单/手势/标题闭包逐点点名）；裸调用 undo() 1（Cmd+Z）、redo() 2（Shift+Z、Cmd+Y）守恒。
- E47-2 核心在位 + 旧栈零残留（private var undoStack = 0、上限 50 字面 = 0、常量 0.6/100 在位）。
- E47-3 **行为表驱动**：MomentUndo.swift 与内嵌断言体以宿主 swiftc 编译运行（本机与 tree 路径双候选）——爆发序列（锚 dedup、窗内合并 ×2、过窗新步、撤销链回 S3→S0 一步整段、空栈 nil）、幻影去重、101 步钳制（栈 100、k0 出栈、k100 在顶）、选区往返、新编辑清重做尾、结构断链，全过打 UNDO_CORE_PASS。
- E47-4 选区恢复接线（restoreSelection 单点、pendingSelectionLength 声明 1 + 消费清零 2、textUnit/firstTextUnit 在位）。
- E47-5 单轨接线（undoManager 覆写两文件各 1、三指识别器 2、.keyboardZ 两面、onUndoKey 定义+接线）。
- E47-6 检查点接线（feedUndoCheckpoint( 恰 4 = 1 定义 + 3 调用；noteTextWillChange 模型/核心各 1）。
- E47-7 Diag 结果量（dedup/clamp 行各 1、merged 插值 2 行）。
- E47-8 构建接线（MomentUndo.swift 于 build-app2.sh 24 处 = 23 遍输入 + primary-file；undo.o 恰 2 = 自有 primary 遍产出 + 主链接行）。build 接线注记：primary 文件在自己遍内只经 -primary-file 出现、不入 plain 名单（与既有各文件同构，初版误加 plain 行致 duplicate input、已正）。

连带改锚一处（期望合法变更，J20-12 先例）：DT46-6 的 MomentFontFactory.swift 构建登记数 22 → 23（新增 undo primary 遍使其 +1，机制未变），注释留沿革。

自检实测：本机 verify 510 ✓ / 2 ✗（仅 ipa 陈旧 + 产物语言包两红，组版基线 504 + 本批 8 − 陈旧 2 = 510，账平）；primary 遍 undo / app / font_factory / title 四遍零 error。落码中实证：UIKeyboardHIDUsage 字母成员为 `.keyboardZ`/`.keyboardY`（0x1D/0x1C，UIKeyConstants.h），初稿 `.keyZ` 经 app 遍 typecheck 抓出已正。

## 六、真机终判点

1. 连续打字一段（>600ms 持续输入）后撤销一次：整段一次撤回（爆发合并），再撤回上一段/上一 op；重做逐步回。
2. 撤销后光标回位：撤销/重做后焦点回到原块、选区（含非零选区）恢复到操作前位置，不失焦、不跳块。
3. Cmd+Z 与三指左滑不双撤：外接键盘 Cmd+Z 一次只撤一步；三指左滑撤一步、右滑重做一步；摇一摇无系统撤销弹窗（单轨）。
4. 标题字段聚焦时 Cmd+Z：走文档撤销、不触发字段级系统撤销。
5. 未改一字进出编辑会话后撤销：无幻影步（菜单撤销行不因空会话点亮出无变化步）。
6. 长会话撤销深度：连续 100+ 个结构 op 后撤销，最旧步出栈、栈深封顶 100（Diag `EDIT undo clamp` 行可佐证）。

## 七、组版交接注记

- tree-sync 的 push_small.py 文件名单须补 MomentUndo.swift（组版批办理，同 MomentFontFactory 先例）。
- U4b 的 EDT-14 undo_redo_roundtrip 场景将以本批漏斗为被测面端到端验收（场景本体属 U4b 批）。
- 跨块选区一期的 replaceRange 落码时，选区恢复的字符口径与 pendingSelectionLength 通道可直接复用。
