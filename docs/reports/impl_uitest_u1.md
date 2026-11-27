# U1 落码报告：UI 自检驱动核 + S1 场景 + B-4 落点映射 + 在席四工具入册 + 在席守卫补齐

基线 HEAD 9d9dd9f（0.9.55）。本批只落码，**未提交、未 bump**。规格源：plan_ui_selftest_driver.md（U1 段 + §7.3）、plan_title_tap_caret.md（B-4）、impl_uitest_u0.md（地基接口）。

## 1. 驱动核（新文件 MomentBridgeUITest.swift）

- 注册表照 DragPressAnchor 模式：`UITestAnchor`（0 尺寸、不可交互的 representable 锚点，updateUIView 以当轮 body 闭包刷新注册、dismantle 注销）+ `UITestRegistry`（属主制注销，同 id+instance 后到为准）+ `UITestSurfaceEntry`（id/kind/instance/frameInWindow/actions/state/setText）。锚点分两型：providesFrame=true 的面由注册方给 frame 闭包（editor.view 读 EditorUI 的 viewW/viewH、menuPanel 读新量测通道 `EditorUI.menuPanelFrame`）；providesFrame=false 的面（胶囊）由锚点宿主视图几何填充 frame（锚点即胶囊本体背景、几何同源）——此处偏离方案 §3.1 表「胶囊新增 GeometryReader」的字面，依 DragPress Row.hostView 既有先例取锚点几何，少一处量测通道、口径更单一。
- 工具四件全归 ops 层：分发器新增 `uiTestScopeTools` 集合 + ops 门分支（BTOOLS）；中继新增 `UITEST_SCOPE_TOOLS` + 同式门分支；`uitest_run` 入 `twoStageTools`（两段提交）。安全模式下四件均不在 `safeLimitedTools`，由既有受限分发一律回 `safe_mode_limited`。
- 模拟点击口径：不构造 UITouch、不注入事件——面的手势/按钮动作体先抽具名入口（见 §3），手指与驱动注册动作指向同一入口闭包。落定判据按步类型：Diag 行等待（waitDiag/waitDiagPair）、状态两轮一致（waitState）、布局两测差 ≤0.5pt（waitLayout）、转场信号；步内轮询 100ms，零写死睡眠；作业总超时 90s。
- 并发门五项：受理前置门（library_unavailable / read_only_mode / ops_disabled）先于并发门；并发门查 App 活跃态、驱动单飞（driver_busy）、设备忙（device_busy：在席他篇/菜单开启等）；步边界漂移检测（用户在作业期间动了界面 → aborted_user_active）；失败复原链六步（见 §2）。

## 2. S1 场景（标题二次编辑回路）

- 夹具：App 内建模板，标题前缀「自检」+ 进程内登记集双标记；一切写路径先验 id 在登记集内（fixture_guard）。孤儿只报不删：`UITestFixtureSweep` 在 app_state / uitest_list_surfaces 时扫描登记外带前缀的残留、logOnce 留痕、计数回包（app_state 新增 `uitestFixtureOrphans`）。
- 九步：开夹具并等转场信号 → 短标题 tap 进入 → 置长标题、辞焦、回读对账 → 截断态断言 + 胶囊帧落定 → **步 5 核心：截断态第二次 tap，waitDiagPair 断言 `EDIT title focus via=capsule` 与 `EDIT title session begin` 成对各一**（失败判读区分「只有 via 无 begin」= 置焦未达）→ 置短标题辞焦回读 → 复长标题截断态 → 第二轮核心 tap → 关编辑器 + 在席清空断言。
- 卫生链（复原链）：Esc 还原草稿 → 关菜单 → 关编辑器（关失败记 editor_close 未复原并跳过删夹具，防编辑器副本落盘复活）→ softRemove + commitPendingDeletion + 回读断言消失 → libraryHash 前后对账。终态码优先级：restore_failed > hygiene_failed > aborted_user_active > run_timeout > step_failed > ok；卫生不过则全场结论降格。完成记 operations 流水（tool=uitest_run）。

### S1 红在步 5 自证（结构级 proven，运行级待真机）

自证方法为代码路径结构分析，未做真机/模拟器真跑（本环境无设备，驱动按设计只能在真机经桥运行）：

- 旧结构实证（git 78bac65，0.9.53）：胶囊为条件插入——`if titleFocused || scalars ≤ 10 { TextField } else { 覆盖层 }`；截断态字段根本不在层级，覆盖层点按把 @FocusState 置 true 被焦点引擎拒绝，会话开始路径（onChange(true)）永不触发。
- 本批结构下同理：若把胶囊回退为条件插入，TitleTextField 随条件分支不在层级，`activateTitleFromCapsule` 置 `titleControl.focused = true` 后无 UITextField 可成为第一响应者，Coordinator 的 didBegin 永不回调，`EDIT title session begin` 行永不出现；步 5 的 waitDiagPair 必然超时且判读为「只有 via 无 begin」——红在步 5、且红的形态正是设计预期的失败签名。
- 限度：以上证明的是「旧结构下步 5 必红」的结构必然性；「新结构下步 5 应绿」仍须真机首跑 S1 终判（见 §6 诚实边界）。

## 3. B-4 落点映射（plan_title_tap_caret.md 路径 B）

- 标题字段换 `TitleTextField`（UIViewRepresentable，TitleTextField.swift）：UITextField 只建一次、身份由 UIView 实例承载；Coordinator 纪律照 BlockTextView（didBegin/didEnd/shouldReturn/editingChanged/didChangeSelection）。呈现与旧 SwiftUI 字段逐项对齐（14 semibold / kern −0.2 / 居中 / textMain / 占位「无标题」/ returnKey.done）。
- 焦点单一真相搬家：`@FocusState` 退场，真相在 `TitleFieldControl.focused`（@Published）；EditorHeaderView 留只读别名 `titleFocused`（坞锁存公式与全部读点零改动）；会话 begin/end 的快照、Diag、commitTitle 由 Coordinator 委托回 EditorHeaderView 的 onBeginEditing/onEndEditing 闭包单点处理（与 R1 收敛律一致：didEnd 无条件回写 false；Enter = shouldReturn 置 false → didEnd 提交，与旧 onSubmit 等价合流）。
- 入口签名冻结：`activateTitleFromCapsule(atX: CGFloat?)`。覆盖层手势换 SpatialTapGesture 取 location.x 调入口；落点映射在置焦之前以呈现态几何定格（pendingCaret 先算后置焦，verify T26-3 锁行序），字段 Coordinator 在 didBegin 后一拍只施加不重算，施加后回读比对，不符记 `EDIT title caret readback mismatch` error 行、成功记 `EDIT title caret -> {scalar}`。
- 纯函数 `TitleTapCaret.swift`（Foundation-only）：`caretScalarIndex`（全扫前缀宽取最近边界、同距取较后边界；rel≤0→0；末界→全文长）+ `utf16Offset`（astral 标量计 2）。数值断言 tests/title_tap_caret_main.swift 共 19 例（ASCII/CJK/astral 混排/恰 11 标量/簇内位 + UTF-16 换算），**已在 tree 以 swiftc 独立编译真跑 19/19 PASS**。
- 量测同源钉子：`titlePrefixWidths` 的属性集与 capsuleWidth 现行量测同源（system 14 semibold + kern −0.2，标题字号现行写死不随 Dynamic Type；将来改随系统字号须同步改，注释已钉）。
- 具名入口抽取三处（行为等价搬家）：`activateTitleFromCapsule`、`toggleEditorMenu()`（••• 钮）、`closeEditor()`（返回钮）；驱动三面注册：editor.titleCapsule（tap/resign/escape + focused/truncated/draftLen/caretUTF16 + setText）、editor.menuPanel（open/close 显式两向 + open/renderedH/contentH/capped；面板呈现处新增 GeometryReader 写 `EditorUI.menuPanelFrame` 非 @Published 量测通道）、editor.view（close + memoId/title/dirty/focusBlockId/draggingId，注册点在 EditorHeaderView——编辑器在位期间页眉恒在层级）。

## 4. M2 在席四工具入册

- `editor_open` / `editor_get_state` / `editor_focus_block` / `editor_save_now` 接 U0 在席注册表 + 导航通道入分发器（新枚举 BridgeEditorTools）。scope：open/focus_block/save_now 入 write 层（桥方案 §7.2 write 层覆盖编辑器语义写），get_state 只读无门。现配对 read+ops 下前三件将回 scope_denied——与既有 write 工具同命运，待用户 write 重配对（M3a 交付时提醒）。
- 错误映射：editor_open 的通道错误经 BridgeNavError 映射直出；`nav_unavailable` / `nav_timeout` 随本批正式登记进错误表三方——BPROTO 登记注记、桥方案 §3.4 错误表补两行、中继工具描述与 CONNECTOR.md 同步（两码 retryable=true）；在席他篇复用 memo_busy、只读复用 read_only_mode、不在册复用 memo_not_found。
- get_state 偏离 §5.3 字面一处：不回正文摘要，只回 id/type 块序 + dirty + columnsActive——从 M2 既定正文红线（块级工具只载 id/序号/哈希，U0 快照同口径），摘要不入回包。focus_block 的 caret 只设 end（缺省）/start 两态（在席落焦地基只有块尾/块首），数值 offset 明确回 invalid_params 不假装。save_now 回落盘后 docHash/libraryHash/dirty + verifyStore 计数对账。
- 清单增量账：22 → 26（在席四件）→ **30 件**（uitest 四件另账，归 ops 层）。新 manifestHash = `c0c991a686799b738ee005fce5beb6e875eebc52381865e9e6bd12d92f8af1bc`（sha256("2025-06-18|" + 30 名排序逗号连接））。三方逐名对账：App toolNames / 中继 TOOLS / 连接器 ALLOWED_TOOLS 已同步（中继 redeploy 与新版 App 上线后三方哈希才对齐，与 M2 上线时同为 staging 态）。

## 5. 在席守卫补齐

- `notes_soft_delete` 接入同一 seatedConflict 守卫（主线裁定：在席即拒、不分脏净；dirty 仅作消息注记）。守卫加 purpose 参数（块写/软删措辞各一份），消费点共三处：删块、移块、软删。在席篇被软删后编辑器下一次保存会以其副本整篇 persist 回列表——复活面与块写覆盖同型，故同守卫。
- `notes_restore_deleted` / `notes_delete_permanent` **无需守卫**，逐个核同型复活面后的结论：两者的目标恒在待删集，而「待删集 ∩ 在席 = ∅」是不变量——(a) 在席登记只可能源于 memos 在册篇的打开路径（列表/关联/导航通道均查 `deletedAtMs == nil` 且不在 pendingDeletions）；(b) softRemove 全部四个调用点（grep 实证）：列表行右键菜单删除、列表行滑动删除（编辑器 push 在位时列表不可达）、桥 softDelete（本批已加守卫）、驱动清理（复原链先关编辑器，关失败即跳过删除）；(c) 编辑器内 ••• 菜单无删除项（2026-11-26 裁定已删自创项）。故待删集中的篇不可能在席，restore/permanent 不存在「目标在席」的复活面。

## 6. 诚实边界（不得升级表述）

驱动 proven 的是**焦点状态机与布局几何**（外加落盘对账）：会话 begin/end 成对、坞锁存、截断呈现、落点记号施加与回读、帧落定、卫生链哈希。以下仍为 unknown、真机终判：**真实触摸投递、识别器仲裁、键盘/光标/拼音组字、像素栅格化**——驱动经具名入口走的是与手指同一份逻辑，但入口之前的触摸链不在驱动面内。本批的运行级证据：纯函数数值断言 tree 真跑 19/19、本机全量 Swift 编译 16 遍 objects ok、verify 本机 239 ✓（仅剩 ipa 陈旧 + 产物语言包 2 条产物类红，tree 重建自解）；S1 的真机首跑（经桥两遍结论一致）是 U1 的运行级终判，尚未发生。

## 7. verify 联动

- [16] B16-3 改写（30 件逐名 + 禁区缩为正文级 4 名 + rescue_arm_safe_mode）；B16-15 件数 22→30 + 哈希注记换 c0c991a6…。
- [24] T24-1/T24-2/T24-5 按 B-4 方案 §5.1 联动改写（T24-1 锁 representable 常驻、T24-2 锁 SpatialTapGesture + 具名入口、T24-5 的 Enter 锚移到 Coordinator 的 shouldReturn）。
- [25] B25-U0-5 消费点 2→3；B25-U0-7 改写为入册计数（editor_* 恰 6）；新增 B25-1..9（方案 §7.3 原编号）+ B25-10 名集镜像断言（B16-3 枚举集与 Protocol 清单差集为空）。
- [26] 新组 T26-1..7（结构锁 + 纯函数断言锚）。
- 构建集成：build-app2.sh 每遍名单 +3 文件、新增三遍 primary（bridge_uitest.o / title_field.o / title_caret.o）、链接行 +3；push_small.py 名单 +3。
