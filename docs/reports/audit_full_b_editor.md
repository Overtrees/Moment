# 全面审计 B 片：编辑页（原生 iOS）

- 基线：仓库 HEAD `b682d02`（Web 跨块选区边角洞根治）。**工作树注意**：审计时工作树含状态栏线（排除项）的未提交改动——`MomentApp.swift`、`MomentEditorTransition.swift`、`build-app2.sh`、`verify_ios.sh` 已改，`MomentStatusBar.swift`、`MomentStatusBarBridge.swift` 未跟踪；本报告行号一律为**工作树行号**，与 HEAD 行号可能有个位数漂移。
- 方法：只读回源审计。原生代码 `rust/apps/ios/app/`（MomentApp.swift、MomentDrag.swift、MomentXSel.swift、MomentXSelBridge.swift、MomentUndo.swift、MomentEditorTransition.swift、TitleTextField.swift、TitleTapCaret.swift）；Web 对照 `rust/apps/web/src/editor/`（render.rs / ops.rs / model.rs / js/editor.js）。未跑构建、未动 git。
- 分级：**proven**＝代码/报告证据闭合；**inferred**＝机制在位但结论由推导得出；**unknown**＝静态审无法定性，附取证法。
- 裁定准绳：AGENTS.md 与 MEMORY.md 在册条目（行为等价优先、真块型为正、拾起规格数值以 Web 源码为准、标题胶囊恒显全文宽口径、完成胶囊 0.9.56 定案、切后台 flush 只冲正文不带标题草稿、只读态编辑入口禁用）。
- 排除：小组件 appex、状态栏采样、APNs/iCloud。
- 基线报告：audit_editor_deep.md（F/M/m 旧账）、impl_cross_block_selection_p1/p2.md、impl_editor_undo_e2.md、impl_conversion_e3.md、plan_selftest_coverage.md（EDT 矩阵）。数值对齐线（audit_detail_editor_blocks，≤2px/令牌微差）按用户裁定搁置，本报告不重报。

---

## 一、回归抽查（必做六项）

### ① 拖拽拾起规格 —— proven 在位（除 M-10，见旧账）

- 长按 480ms / 容差 10px：`MomentDrag.swift:107-108`（minimumPressDuration 0.48、allowableMovement 10）；与全部手势识别器同时识别（同文件 ~236-245），仲裁为 DragPressEngine 单点。
- 玻璃框：LiftFrame = 视觉面 ⊕ LIFT_INSET 4、半径 = 面半径 + 4（MomentApp.swift ~16306、~16461；gallery 格网面同口径，见 GalleryBlockView background）。
- `liftScaleFor`：`max((dim − 8)/dim, 0.9)`，dim ≤ 0 回退 0.97，双轴以 `block.rowW` / `block.height` 喂入（MomentApp.swift ~10497）。
- 可拖集：BlockRow `dragAllowed` 全块型武装，唯排除「正在编辑的文本块」与「卡编辑态行」；拾起置位菜单——卡型置 `cardMenuBlockId`、其余置 `blockMenuBlockId`（菜单骑拾起，~10371-10373）；拖动 >10px 自动收两菜单（~10388-10395）。

### ② 标题胶囊宽公式 —— 公式在位；截断口径有源冲突待主线裁定（见 B-02）

- `capsuleWidth`（EditorHeaderView，~12690）：量测串以 `TitleTextField.fieldFont()` + kern −0.2 量宽；宽 = max(标题宽, meta 宽) + 40（横内距 20×2）；上限 = headerW − 124 − chrome，紧凑横排 chrome = 80（头像 72 + gap 8 → W−204）；下限 66。聚焦态量测串 = 草稿全文，全文宽口径成立。
- 未聚焦且草稿 >10 unicode scalars 时，呈现串截断为 10 标量 + "…"（覆盖层 Text + `activateTitleFromCapsule` 的 B-4 落点映射）。与 MEMORY「标题胶囊 CLOSED」条的口径冲突，单列 B-02。

### ③ commitTitle 真变更同步冲刷 —— proven 在位

- EditorHeaderView `commitTitle`（~12409）：trim、空回退「无标题」；仅真变更时 `pushHistory()` → `editor.title = final` → `editor.saveNow()` 同步冲刷（明文不走 `scheduleSave` 0.6s 防抖，fix_title_commit_propagation 口径）→ 刷新 backlinks。关闭编辑页 `closeEditor` 同路 commitTitle + saveNow。

### ④ E2 撤销 —— proven 在位（代码级）

- `MomentUndo.swift`（181 行，Foundation-only 核心）：合并窗 600ms（`undoBurstWindow = 0.6`）、上限 100（`undoStackCap`）、双入栈路按快照键去重、钳制淘汰最旧、操作边界/undo/redo 断合并链、新记录清 redo、条目惰性工厂。
- 馈入单点：`pushHistory`（定义 MomentApp.swift:3476）+ 文本爆发馈入 `noteTextWillChange`；调用点封闭。
- 选区恢复：`restoreSelection` + `pendingSelectionLength`（按目标单元字符数钳制，无附带选区落首个文本单元兜底）。
- 单轨漏斗：`EditorModel.undo()/redo()` 承菜单 / Cmd+Z·⇧Z·Y / 三指手势 / 标题字段闭包四入口。
- 系统轨封堵：`override var undoManager: UndoManager? { nil }`（MomentApp.swift:2851、TitleTextField.swift:78）。
- 矩阵 EDT-14 由 U4b 场景 `undo_redo_roundtrip` 覆盖（plan_selftest_coverage.md）。

### ⑤ XSel 两期与 ops.rs 契约 —— proven 一致（含 Web 边角洞的原生对应面）

- Web 契约（HEAD）：`model.rs:536-538` `outside_survives(block, truncated) = !truncated || is_atomic_class(block)`；原子分类 `model.rs:516-525`（非文本恒原子；列表仅空时原子）。
- 原生 `MomentXSelBridge.swift`：`xselIsAtomicTop`（~47-52）与上述分类逐项同构；`replaceRangeUnits` 两条路径（K5 路 ~520/527、普通路 ~606/613）均以 `!fromStart || xselIsAtomicTop(block)` / `!toEnd || …` 保外侧原子块——即原生自一期起即实现 Web 于 HEAD（b682d02）才补齐的语义，无对应洞。
- 替换单步撤销：单次 `pushHistory()` + `scheduleSave`；selectAll/replace 均守 `library.isReadOnly`。
- 二期：`xselExtend` / `XSelCore.stepChar/extendHorizontal/verticalFocus/segmentRange`，段选区经 textStorage 属性描画（既有背景快照/恢复）。
- 真机面（触摸菜单、Cmd 送达、高亮像素、Esc 优先级）沿 p1/p2 报告 §六为 **unknown**，取证法：真机手势 trace + Diag `XSEL` 行。

### ⑥ 斜杠转块落盘真块型 —— proven 在位（E3）

- 转换单点 `convertNodeType` 由 `setBlockType`（块菜单）与斜杠 `convert` 共用：`clearTypeFields` 清 attrs 的 level/checked（attrs 空则整键移除），heading 设 level、todo 设 checked=false；`calloutType` 转换不写（M-04 已修，重转保变体）。
- F-04：列表项 × 列表命令 = 父表换型 + 清 start，早于 `promoteListItem` 返回；F-05：`listStart/setListStart/shiftListStart` 帮手齐（exitListItem 2 处、mergeListItemBackward 3 处传 start）；F-06：转列表逐行成项（`listLineRuns`/`runsSplitByLine`）；M-05：`stripMdLineRuns` 直调 FFI `mdParseJson`，不经 mdKind/mdBlocks 缓存对。
- 公式块落盘形态见 SL-12：段落 + 字面 `$$` 围栏（公式无独立块型，段落即其落盘形态，定案口径）。

---

## 二、逐域现状 vs 应然

### 2.1 全块型编辑

- 文本/标题/待办/引用/提示/代码：编辑面齐备；斜杠触发守卫集已对齐 Web（heading/quote/codeBlock/callout 不弹，可弹集 = paragraph/todo/list-item，`updateSlash` MomentApp.swift:8287-8299，M-01 已修）。智能前缀 F-02 在位（`smartPrefixMatch`/`applySmartPrefixIfNeeded`，didChange/split/merge/paste 尾扫）。
- 图片/gallery/视频/附件：F-14 gallery 编辑态删项角标（`applyGalleryRemove`）+ onDrag/onDrop 排序（GalleryTileDropDelegate，跟随式换位、会话首动单压历史）在位；F-15 视频 `addVideoBlock` + 文件导入/PhotoPicker 双路 UTType.movie 分流在位。
- 链接卡/音乐卡：打开时未就绪卡补拉解析链（init pending 支）；音乐输入胶囊提交走 `submitMusicInput` 公共解析；粘贴成卡 `pasteCard`（音乐域名 → musicCard、余 → link-card）。
- 未知块：F-17 在位——类型标签 + 纯文本呈现 + logOnce；embedCard 渲其文本。
- 段首退格撞原子前驱：F-08 在位——顶层 `mergeBlockBackward` 与列表首项支均置 `selectedBlockId`（只选中不删，删走卡菜单明路）。
- 前向删除（Delete 键块末合并）：**无对应实现**——全仓无 mergeBlockForward 类路径，`keyboardDeleteForward` 仅出现在 XSel 接管支（MomentApp.swift:7960-7961）。Web 对应行为本轮未回源定性，记 B-05（unknown）。

### 2.2 MD 预览

- 解析走 moment-core 同一解析器（FFI `mdClassify`/`mdParseJson`）；`mdKind` 文本变更经 `invalidateMdCache()` 单点失效（fix_md_cache_stale）；尾随空段物化 `materializeMdTrails` 在 init 与失焦路执行；点预览回源码光标落末尾（`beginMdEdit`，Web 口径）。
- 呈现：MdBlockView 递归（Heading/Para/Code/Math/Quote/Callout/List/Table/Footnotes/Divider）；行内公式经 MdRender 的 mathTex run + 快照附件，块级公式 MdMathView；含链/公式的文本组才开交互（`MdRender.hasInteractive`），免吞长按拾起/落焦手势。
- 行为结论（预览像素、附件渲染时序）：静态审 **unknown**，取证法：真机打开含公式/表格/脚注的种子篇截图比对 + Diag `MD` 行。

### 2.3 标题胶囊

- 见抽查 ②。字段恒常驻层级（截断态覆盖层呈现，0.9.53「点按无反应」根治结构在位）；坞态会话锁存（DockSession，fix_title_compact_freeze 口径）在位；胶囊高随 Dynamic Type 增量（`capsuleHeight`）。

### 2.4 完成胶囊（••• → ✓）

- `doneExpanded` 单点派生（EditorHeaderView，~12267）：`ui.kbVisible`（仅由键盘 show/hide 通知单点写位，明文不由 safeBottom 派生——0.9.56 锁存回归的修法）∧ ¬（showMenu ∨ showExport ∨ showBgSheet ∨ draggingId ∨ cardMenuBlockId ∨ blockMenuBlockId）六抑制格。
- 形态：单容器宽 46、帧高 46↔92 顶锚、✓ 段下置延迟淡入；`finishEditing()` 仅 resignFirstResponder，提交走各字段既有失焦链。
- 手感/动画时序：**unknown**，取证法：真机录屏逐帧 + Diag `EDIT donecapsule` 行。

### 2.5 块拖拽

- 见抽查 ①。落位 `commitDrag` 按实测高累加判定（非固定步距）。双栏钳制与 layout 锚的旧账见 F-16/M-09。

### 2.6 跨块选区两期

- 见抽查 ⑤。矩阵行 EDT-55 由 verify [50] X50-1..7 / [51] X51-1..5 锚定（本轮只读核对，未跑）。

### 2.7 撤销体系

- 见抽查 ④。

### 2.8 键盘与拼音组合

- 静态面在位：组字中 didChange 让路（E1）、标题 Esc 组字守卫（`handleEscape` 先查 `titleControl.composing`，m-01 已修）、XSel 接管支组字不消费（`tv.markedTextRange == nil` 门）、跨块方向键组字不接管。
- 行为结论一律 **unknown**（纪律）：取证法——真机系统拼音键盘全程 trace（pointer→touch→组字候选→上屏事件串）+ Diag 组字行；无头/合成事件不作数（AGENTS.md 验证清单）。

### 2.9 粘贴与附件插入

- `handlePaste`（~9315）：codeBlock 恒字面（M-02 守卫，先于成卡判定）；XSel 在位时粘贴替换支先行；裸 URL / 内嵌媒体 URL 成卡（`pasteCard`），余放行原生粘贴。
- 附件插入：选图/选片/文件三路均 `putAttachment(fid, data, name:)` 带真实文件名登记 manifest（0.9.36 根治口径）；失败只记 Diag 不成块。

### 2.10 切后台 flush

- 根 scenePhase 处理（~21932）：`.background` 时经 `EditorSeatRegistry.shared.saveNow()` 冲在席编辑器正文 + Diag `EDIT flush src=background`，随后 `Library.launchSuspend()`。
- 标题草稿**不**连带提交（代码注引用审计待裁项 8 的推荐；矩阵 EDT-03 记为主线定案）——与裁定准绳一致，proven。

### 2.11 只读态入口禁用

- `readonlyEntryBlocked` 守新建（~18911）与打开（~18931）；XSel selectAll/replace 守 `library.isReadOnly`；只读态 persist 自有 writeBlocked 闸（空 doc 补段等物化无副作用）。proven。

### 2.12 双栏编辑独立性

- 分界函数族（canonicalBoundary / normalizeBoundary / captureAnchorIfNeeded）逐项移植 Web columns.rs；flow 不读不写 layout 分界、independent 锚优先；`toggleTwoPane` 按当前分界重写名单落库。
- **坐标空间不对称（旧旁注复核仍在）**：independent 左栏 ScrollView 有 `.coordinateSpace(name: "editorScroll")`（~13476），右栏 ScrollView 无（~13484）；块 frameMinY 经 `.named("editorScroll")` 量测（~10321），右栏块的量测基准与左栏不同源，现以菜单层 +155 纵向补偿与 `panelLeftX` 的右栏原点账（~11360 段）对冲。结论 **inferred**：静态无法判定右栏菜单/斜杠面板落点是否逐值正确。取证法：真机/自检探针在 independent 右栏长按拾起，读卡菜单与斜杠面板 panelTop 对触发块底的偏差。

---

## 三、斜杠菜单逐项清单（SL 组，独立成节）

**分母**：原生 `SlashCmds.all`（MomentApp.swift:5837-5860）共 **24 项**，逐项已核 **24 项**。Web `SLASH_CMDS`（render.rs:26-48）共 **22 项**；原生多出公式块 ∑（SL-12）与行内公式 ƒ（SL-18）两项（0.9.46 原生增强，原版/Web 无对应项，其应然以原生定案规格为准）。Web render.rs:586 注释自称「21 条命令」为陈旧注释，不作分母。

**共用面（24 项同源，以下不逐项重复）**：

- 触发：`updateSlash`（:8279）——块内任意位置、光标前最后一个 `/` 起无空白至光标为 token；可弹集 paragraph/todo/list-item；查询 ≤30 字；URL 抑制见 B-04。筛选 `SlashCmds.rows`（:5896）——空查询 = 最近（≤6，UserDefaults `slashRecentOids`）置顶 + 基础/媒体两组（组内剔最近）；有查询 = title+sub+kw+ty+py 小写 contains、前缀命中优先、余按标题 zh-Hans-CN localeCompare。点选：行 Button → `applySlash`（:8764）；键盘：`slashMoveSel`/`slashSelEdge`/`slashApplySelected`（:7740-7757）。
- 撤销：`applySlash` 入口单次 `pushHistory()`（link 例外见 SL-16），一命令 = 一撤销步，选区恢复走 E2 附带选区（抽查 ④）。proven（代码级）。
- 面板锚：见 B-03。

| 编号 | 项（act / 组） | 插入结果块型 · 落盘形态 | 光标落点 | 失焦预览 | 与 Web 对照 / 分级 |
|---|---|---|---|---|---|
| SL-01 | heading1（基础） | `convert("heading", level:1)` → 真 heading 块，attrs.level=1 | token 起点 | 标题梯呈现 | Web 同项同果。proven |
| SL-02 | heading2（基础） | 同上 level=2 | token 起点 | 同上 | proven |
| SL-03 | heading3（基础） | 同上 level=3 | token 起点 | 同上 | proven |
| SL-04 | paragraph（基础） | `convert("paragraph")`，清类型字段 | token 起点 | 正文 | proven |
| SL-05 | quote（基础） | `convert("quote")` 真引用块 | token 起点 | 引用盒 | proven |
| SL-06 | todo（基础） | `convert("todo")`，checked=false；顶层路补尾随空段（列表项升格路不补，Web Item 臂同口径） | token 起点 | 待办行 + 勾选框 | proven |
| SL-07 | divider（基础） | 节点整体替换 `{id, type: "divider"}`（children 弃），后插空段 | 新空段 | 分隔线 | Web 同果。proven |
| SL-08 | bold（基础，行内） | `markRunRange(key:"bold")` 打标记 run；无选区插「文字」标记 run | 有选区 s+l；无选区 at+2 | 粗体 | Web 走桥 applyInline 包裹元素，落盘同为粗体标记。proven |
| SL-09 | italic（基础，行内） | 同上 key:"italic" | 同上 | 斜体 | proven |
| SL-10 | highlight（基础，行内） | 字面 `==` 包裹（不入标记模型）；无选区插 `==文字==` | 有选区 s+l+2；无选区 at+6 | 高亮底色（定界符不呈现） | 与 Web `== ==` 口径同。proven |
| SL-11 | codeBlock（基础） | `convert("codeBlock")`；MD 源段落**不剥前缀**、runs 原样入块（F-07 定案，与 Web 围栏臂保原文同果） | token 起点 | 代码盒 | proven |
| SL-12 | mathBlock ∑（基础，原生增强） | runs **整体替换**为 `$$\n\n$$` 后 `convert("paragraph")`——落盘 = paragraph + 字面围栏（无独立块型，定案形态） | 中间空行（偏移 3） | core 切分出块级公式 | Web 无此项。落盘/落点 proven；**既有正文被弃**见 B-01 |
| SL-13 | bulletList（基础） | 逐行成项（`listLineRuns`，MD 源先剥前缀）→ bulleted-list 真块；列表项内触发 = 父表整表换型 + 清 start | token 所在行/行内偏移 | 列表 | proven（F-04/F-06） |
| SL-14 | numberList（基础） | 同上 → numbered-list | 同上 | 有序列表 | proven |
| SL-15 | callout（基础） | 顶层 MD 源先剥前缀（`stripMdLineRuns`）再 `convert("callout")`；calloutType 不写、缺省 note；顶层路补尾随空段 | token 起点 | 提示卡（变体保留） | proven（M-04/M-05） |
| SL-16 | link（基础，行内） | 先剥 token + 记选区 → 面板内链接表单；提交 `applyLink`：有选区挂 `_link`+underline 标记 run、无选区插字面 `[链接文字](url)`（括号转义） | 提交后：有选区 s+l、无选区字面末尾 | 链接样式 | 提交路 proven；**取消路 token 不还原**见旧账 F-13。校验：原生仅 http(s) 前缀判，Web 为 URL 解析 + 协议白名单（render.rs submit_slash_link）——判定面 inferred 等价（原生更宽：`http://` 前缀即过，无效 URL 字面入盘） |
| SL-17 | code（基础，行内） | `markRunRange(key:"code")`；无选区插「文字」标记 run | s+l / at+2 | 行内码 | proven |
| SL-18 | mathInline ƒ（基础，原生增强） | 字面 `$` 包裹（不入标记模型）；无选区插 `$文字$` | 有选区 s+l+1；无选区 at+4 | core has_math_syntax/split_math 切分出公式 | Web 无此项（INLINE_ACTS 无 math）。proven（代码级）；预览像素 unknown |
| SL-19 | strikethrough（基础，行内） | `markRunRange(key:"strikethrough")` | s+l / at+2 | 删除线 | proven |
| SL-20 | imgTextCard（媒体） | 节点 `{type:"imgTextCard", text:"点击输入文字"}` 占位落数据 + 尾随空段 | 尾随空段 | 图文卡占位 | proven |
| SL-21 | imageTextRow（媒体） | 同上，文案「点击输入说明文字」 | 尾随空段 | 混排卡占位 | proven |
| SL-22 | musicCard（媒体） | 节点 `{type:"musicCard", status:"input", url:""}` + 尾随空段（不承焦） | 输入胶囊本身（`focusMusicId`） | 胶囊 → 解析后音乐卡 | proven |
| SL-23 | image（媒体） | 节点 `{type:"image", attrs:{}}` 占位块 | 尾随已有空段优先、否则新插空段 | 空图占位（点按选图替换） | proven |
| SL-24 | gallery（媒体） | 节点 `{type:"gallery", attrs:{items:[]}}` | 同 SL-23 | 空态双占位瓦 | proven |

**SL 组共性问题**（不逐项重复登记）：

- **SL-A 标题/副标题未入 i18n（M-07 / EDT-59，未结）**：`SlashCmds.all` 的 title/sub 为 zh-CN 字面（:5837-5860），空态文案同为字面（slashEmptyState）；仅组头/最近走 `Lang.t`。Web 全项走 `slash.*` 语言键。非 zh-CN 界面下斜杠菜单仍中文。proven，影响：i18n 完整性（I4 批承接，代码注已自认）。
- **SL-B 面板纵锚 = 触发块底，非光标行底（M-08，未结）**：见 B-03。

---

## 四、新发现（B 组）

### B-01 mathBlock 转换弃既有正文 —— proven，影响：中

- 现状：SL-12 执行时 `b.runs = [["text": "$$\n\n$$"]]`（applySlash mathBlock 支，~8890）整体替换，随后转段落；触发块原有文本（除已剥 token 外）全部丢失。其余 23 项转换均保留 runs/正文。
- 应然：无 Web 对应项；按其余转换的保内容通例，应保留正文（如围栏包裹既有文本或正文移入公式行间），至少不应静默弃文。撤销可恢复（单步 pushHistory 在先），故为可逆数据丢失，但行为与全表通例不一致。
- 取证：代码直读闭合；真机复现法——非空段落输 `/mathBlock` 选之，看正文是否消失。

### B-02 标题胶囊截断口径的源冲突 —— 待主线裁定（非单方缺陷）

- MEMORY「Mynote title capsule — CLOSED」条：Web 无字数上限、恒显全文，称原生 10 字截断为自创口径。
- 但 Rust Web `title.rs:22-27` 本身在非编辑态把显示串截断为 10 字；原生截断 + B-4 落点映射经 audit_editor_deep 判达标且有真机修复史（0.9.53 字段常驻根治）。
- 现状与两源各有依据：编辑态恒全文（合 CLOSED 条的编辑面），非编辑态截断（合 Web title.rs 现行码）。请主线裁定以何者为准绳；裁定前不判缺陷。影响：胶囊宽量测的 `shown` 串随之二选一。

### B-03 斜杠面板纵锚为块底而非光标行底 —— proven（机制），影响：小-中

- 现状：`slashLayer`（:11573）top = 触发块 `frameMinY` + 块高 `height` + 10（放不下上翻）；`updateSlash` 只回传 `caretX`（横锚），无光标行纵坐标。
- 应然：Web 面板锚 = 光标 rect（editor.js `slashCaretAnchor`，render.rs anchor_top/bottom 为光标行上下缘）。多行块中段触发时，原生面板贴块底、与光标行可差数行高；单行块无差。
- 旧账 M-08 同条，此处以现行码复核仍未结，归 B 组重述以便总装引用（与 M-08 为同一问题，不双计）。

### B-04 斜杠 URL 抑制与 Web 判定面不一致 —— proven（代码差），影响：小

- Web（editor.js:1124-1132）：取含 `/` 的非空白 token、剥前导括号引号 `([{<"'"‘` 后以大小写不敏感正则 `^(?:https?:\/\/|www\.)` 判。
- 原生（updateSlash :8330-8345）：仅查 token 前一字符为 `:` 或 `/`，或所在词以 `www.`/`http` 起头——大小写敏感、无前导括号引号剥除。后果：`HTTP://…`、`(www.…/…` 等形态下原生误弹面板（或反之），属边缘误触发，不毁数据。

### B-05 前向删除块末合并缺位 —— 已裁已落（用户 2026-11-28 裁定做、与退格对称、两端一致；0.9.63 落码，fix_forward_delete_merge.md：原生 mergeBlockForward/mergeListItemForward + Web op_merge_forward 纯核心同口径；Web 原状回源定性为无此行为——分块 contenteditable 下 Delete 块末无原生动作、keydown 无支）

- 原生无 mergeBlockForward 路径（见 2.1）；硬件键盘 Delete 在块末的行为（原生 UITextView 默认 = 块内删字、块末无动作）与 Web 对应口径未回源比对。取证法：回源 Web ops/keydown 的 deleteForward 支 + 真机硬件键盘实测两端同场景。

### B-06 选图/文件 sheet 呈现不关斜杠态 —— proven（机制缺位），影响：小

- `showPhotoPicker`/`showFilePicker` 的呈现绑定（:11241、:11304）无清 `slashBlockId` 的联动；全仓清 slashBlockId 的写点（:8294/:8317/:8785/:8792/:9046/:11077/:12386）无一在 sheet 路。可达性 inferred（面板开着时经菜单开 sheet 的路径窄），后果至多面板与 sheet 叠态/回来面板钉旧块。旧账 m-05（EDT-60）同条，未结。

---

## 五、旧账未结（自 audit_editor_deep，E5/E6 未落地）

### F-16 + M-09 拖拽落位不重写 layout 锚名单 —— proven

- `commitDrag`（~9518）只重排 `blocks` 并 `scheduleSave()`；persist 的 `layout` 名单原样写回，无任何按新序重写 left/right 的代码。窄屏（independent 锚休眠）下拖拽跨越休眠分界后，切宽屏时锚成员与视觉序脱节。
- M-09 同源：钳制 `if columnsActive, blocks.count > 1` 以 `columnBoundaryIndex` 为界恒行——flow 模式下该分界是规范估高值、flow 本身不读它，flow 拖拽被一条自身不消费的界钳住。

### M-10 拾起取消不清菜单态 —— proven

- BlockRow `onCancel`（~10429）只清 `draggingId`/`dragDy`；拾起置位的 `cardMenuBlockId`/`blockMenuBlockId` 不清，行 `onDisappear` 复位同缺。系统取消拾起（来电、手势冲突）后可留孤儿拾起菜单。

### F-13 斜杠链接表单取消不还原 token —— proven

- `applyInlineSlash` 在开表单**之前**已 `removeRunRange` 剥 token 且 `applySlash` 尾路 `scheduleSave()` 已落盘（SL-16）；取消钮（linkFormPanel :11968）与 Esc（handleEscape :12381）均只置 `linkFormBlockId = nil`，不还原已剥文本。
- Web 对照：表单取消仅 `link_for.set(None)` 回命令列表，token 剥离在提交路（`__mnApplyLink`）才发生，取消后正文无损。
- 原生侧可经撤销恢复（applySlash 入口已 pushHistory），但取消语义与 Web 不等价：用户取消一次链接插入，正文已少一段 `/xx` 文本且已落盘。

---

## 六、unknown 清单与取证法（静态审纪律）

| 面 | 取证法 |
|---|---|
| 拼音组字全链（块文本/标题/音乐胶囊） | 真机系统拼音键盘 trace（整串事件）+ Diag 组字行 |
| 长按拾起手感、菜单骑拾起呈现时序 | 真机手指 trace（480ms/10px 实测）+ Diag `DRAG` 行 |
| 标题胶囊 B-4 点按落点映射精度 | 真机截断态逐字点按、读 `titleControl.caretUTF16` 自检面 |
| 完成胶囊展开/收起动画与键盘同步 | 真机录屏逐帧 + Diag `EDIT donecapsule` 行 |
| XSel 触摸选区手柄、段选描画像素、硬件键 Cmd 送达 | 真机手势 + 截图；桥 Diag `XSEL` 行 |
| 双栏右栏浮层（卡菜单/块菜单/斜杠面板）落点 | independent 右栏拾起探针，量 panelTop 对块底偏差（见 2.12） |
| MD 预览公式/表格/脚注呈现像素 | 种子篇真机截图比对 |

---

## 七、总结

- 回归抽查 ①③④⑤⑥ proven 在位；② 公式在位、截断口径待裁定（B-02）。
- 斜杠菜单共 24 项逐项已核 24 项（SL-01…SL-24）：落盘真块型、落点、撤销单步三面全项闭合；问题集中在 SL-12 弃文（B-01）、SL-16 取消路（F-13）、全表 i18n（SL-A）与面板锚（B-03）。
- 未结旧账三组：F-16+M-09（拖拽 × layout 锚）、M-10（拾起取消残菜单）、F-13（链接取消弃 token）——均属 E5/E6 未落地范围，建议总装按此三组派批。
