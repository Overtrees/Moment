# U4a 落码报告：自检驱动第二波第一批（六景 + 驱动核泛化）

基线 HEAD 6ce6cd8（0.9.57 组版落定）。本批只落码，**未提交、未 bump**，随下一组版。规格源：plan_selftest_coverage.md §6.3（U4a 取项）+ U4a 停门回报蓝图 + impl_uitest_u0/u1.md（地基与 S1 形态）。同树多批并行：动工前全量 diff 快照（/tmp/u4a_base_diff.txt，1943 行）映射在途批，逐 hunk 避让；完工复验他人 hunk 完好（E1/E3/E4/DT/救援/宽屏/媒体/权限各批改动俱在，见 §7）。

## 1. 开工复核三条（停门遗留）

1. **EDT-09 口径**：按 fix_donecapsule_retract 落定后代码复核——kbVisible 唯一写点 = EditorUI.setKbVisible（键盘通知喂入，MomentApp.swift EditorUI 段），Diag 行 `EDIT kb visible=<0|1> src=notify h=`；doneExpanded 为派生（kbVisible ∧ 抑制六格）。done_capsule_cycle 断言全部以此为准（kb 行 + expand/collapse 派生行 + 三行序），无 safeArea 旧口径残留（B25-U4a-7 锁）。
2. **verify [25] 插点**：以现行文件为准——B25-10 后、[26] 组前插入 B25-U4a-1..7（同组尾部追加式，与 E3 批 B25-E3-* 并列共存，互不覆盖）。
3. **EDT-16/17 与 E3 依赖**：开工时 E3 尚未落定；落码中途 E3 在同树落定（impl_conversion_e3.md，clearTypeFields + convertNodeType 单点，B25-E3-1..5 全绿）。矩阵景转换断言已按 E3 落码后语义逐项对齐并实证吻合：转出待办清 checked、转出标题清 level（clearTypeFields 摘两键）、转入待办恒 checked=false（convertNodeType）。**依赖已解除**，该步不再预期红。

## 2. 驱动核泛化（MomentBridgeUITest.swift）

- **场景目录查表**：新增 `UITestScenarioDef`（名/夹具形态/grades/步表构造）+ `UITestDriver.catalog`（七景：S1 + U4a 六景）；begin() 改目录查表，unknown 回码列全注册名。S1 的硬编码特判与专属 grades 整体退役（S1 步表本体一字未动）。
- **ctx 跨步存储**：UITestRunContext 新增 `store: [String: Any]`；夹具块 id 表（blockIdByType/blockTypes/paragraphIds）、落点预期标量（expectedCaret）、斜杠目标块（slashBlockId）均经 store 传递，不再逐景往 ctx 加专属字段。
- **步证据前缀**：步记录 Diag 过滤新增 `SLASH ` 与 `SCROLL ` 两前缀（斜杠景的 SLASH open 行、紧凑景的 SCROLL 轨迹行据此入步证据）。
- **复原链补清三位**：restore() 在关浮层后、关编辑器前新增 ②′ 步——在席编辑器为夹具篇时先清 EditorModel 的 slashBlockId/linkFormBlockId/focusMusicId（防关编辑器失败走孤儿兜底时三位随副本残留）。
- **夹具模板**：`UITestFixtureTemplate.build(kind)`——.title 保持 create() 单空段；.blocks = 全块型序（段落/标题 L1/待办/引用/提示/代码块/分割线/无序列表/有序列表/未知类型 futureWidget/段落乙）+ 10 填充段；.tall = 段落 + 14 填充段（保 scrollY 可越 30）。构造与 Library.create() 同式，persist 仍只写夹具自篇（B25-7 禁区零触碰复验通过）。

## 3. 注册面扩展（MomentApp.swift，四处）

1. **editor.view 增读**：dockCompact（页眉派生、仅页眉锚点可读）+ scrollY（独立滚动状态对象）两 state 键——EDT-06 断言源。
2. **editor.doneCapsule 新面**（锚 moreCapsule 本体）：done → finishEditing() 具名入口（与勾钮同一体）；state expanded（doneExpanded 派生单源）/ kbVisible（通知单点写位）。
3. **editor.slashPanel 新面**（锚 EditorView 根、恒注册，面板未开 open=false 可读）：state open/query/sel/count/selAct（行序命令由 SlashCmds.rowCommands 单源派生）；actions applySelected/moveSel 走 slashApplySelected/slashMoveSel 具名入口，close 为模型 close() 同写（直置 slashBlockId=nil）。
4. **editor.scroll 滚动面**：新锚点 `UITestScrollAnchor`（驱动文件内，UITestAnchor 同注册纪律 + 宿主视图弱引用）挂单列内容 VStack——沿 superview 链找 UIScrollView，action to(y) 程序化设 contentOffset；state offsetY（UIKit 本体量）与 scrollY（探针派生量）分开回报。

另：**EditorModel.toggleTodoChecked(_:) 具名入口抽取**（开工复核为不在位，按蓝图由本批抽）——勾选钮原内联五步（pushHistory/翻转/node 回写/nodeVersion/排保存）整段搬入模型，勾选钮改单行调用，行为等价；矩阵景与勾选钮共用此入口（B25-U4a-6 三方同源锁）。

## 4. 六景（步表与断言）

| 景 | 覆盖行 | 步数 | 核心断言 |
|---|---|---|---|
| title_capsule_reedit_compact | EDT-06 | 7 | 滚动 to(200) → dockCompact 两轮一致 true ∧ scrollY>30 → 截断点按 via/begin 成对（S1 coreTap 同体）→ 会话期坞态锁存两轮一致 → resign 回读 → 滚回顶坞态回落 |
| title_caret_assert | EDT-07 | 4 | 同源量测（fieldFont + kern −0.2）在驱动侧算预期：瞄准第 5 边界 tapX → 纯函数预期 =5（aim 断言）→ Diag `EDIT title caret -> 5` 施加行 → 字段回读 caretUTF16 与 utf16Offset 对账 |
| title_commit_escape | EDT-08 | 5 | Esc 段：改草稿 → escape → 标题未变 ∧ 草稿回滚（draftLen 复原）∧ 焦点已辞；trim 段：两侧空白提交落 trim 值；空回退段：纯空白 → 「无标题」 |
| done_capsule_cycle | EDT-09 | 6 | 两轮循环，每轮：tap 置焦 → `EDIT kb visible=1` ∧ donecapsule expand ∧ expanded=true → done → 三行齐且序 done ≤ kb=0 ≤ collapse ∧ expanded=false（第二轮防闩锁假绿） |
| slash_menu_flow | EDT-18/19 | 7 | 喂 "/" → SLASH open 行 ∧ 面板开 ∧ 首选 = 行序首项；喂 "/db" → query=db ∧ 选中 todo（拼音命中）；空 query moveSel ±1 环绕对行序表；applySelected → 段成 todo ∧ token 剥净 ∧ 面板关 ∧ `EDIT slash todo` 行；段落乙 "/bt1" → heading ∧ level=1 ∧ `EDIT slash heading1` 行 |
| block_type_matrix | EDT-16/17 | 6 | 类型序对模板 ∧ 帧落定（块顶 frameMinY 随序不递减、末 > 首）；待办 toggleTodoChecked 两轮 saveNow + notes_get 回读 checked true/false；未知块 saveNow 后回读类型仍在 ∧ 模型正文未吞；转换清字段三断（E3 语义，见 §1.3） |

斜杠景的块文本喂入（UITestShared.feedBlockText）与 BlockTextView didChange 的模型侧效果同构：纯文本 runs 重建 + 文本写入 + updateSlash 单路（选区置末）。逐字输入不等价口径不变（grades 已钉 keyboard: unknown）。

**EDT-19 抽样边界（如实）**：本批抽样块型命令两例（todo/heading1，含成块类型与 level 落点）；行内命令（bold/link 等包裹类）需块选区态，不在本批驱动面，留 U4b 块面 setText 落地后补抽样——矩阵 EDT-19 行不因此判全覆盖。

## 5. verify 联动（[25] 新增 B25-U4a-1..7，插 B25-10 后）

- B25-U4a-1 目录查表 + 七景全注册 + 无单景特判残留（断言初版曾因 grep 正则字符类 `[scenario]` 误红，已转义修正——断言自身的量测坑，留痕）。
- B25-U4a-2 ctx store 在位且有消费点；B25-U4a-3 步证据前缀 SLASH/SCROLL；B25-U4a-4 复原清三位；B25-U4a-5 注册面扩展四处；B25-U4a-6 toggleTodoChecked 三方同源；B25-U4a-7 EDT-09 kb 通知行 + 三行序口径锁。
- 本机全量 verify 结果：[25] 组 U0/U1/U4a/E3 全绿。余红均为他批/产物面：[5] ipa 陈旧、[9] 产物语言包（tree 重建自解，历批同例）；[16] B16-15 与 [25] B25-10 在本次运行间转为红——实证为 M3a 批在途状态（MomentBridgeProtocol.swift 已加 scenarios_*/metrics_create_settle 四名、B16-3 枚举尚未同步），非本批 hunk，待 M3a 自行收口。

## 6. 判读口径（真机/桥跑）

- 运行面：App 前台经桥 `uitest_run {"scenario": "<名>"}` 受理（ops scope + 两段提交），`uitest_get_result` 轮询至 status done/failed；终态码优先级沿 S1（restore_failed > hygiene_failed > aborted_user_active > run_timeout > step_failed > ok），两遍结论一致才算终判（§6.8 出包回归子集口径）。
- EDT-09 首跑重点看第二轮 doneStep 的 triple_ordered：若 kb=0 行缺失而 collapse 在位，是键盘通知链问题而非胶囊派生问题（行序即分段定位）。
- EDT-06 若 dock_compact_on 超时，先看步证据中的 SCROLL 行判滚动是否真实发生（offsetY 驱动到达 vs 探针 scrollY 未动 = 探针基线问题，与坞态无关）。
- 证据上限（不升级表述）：六景 proven 的是状态机/几何/落盘回读；真实触摸投递、识别器仲裁、键盘呈现手感、未知块降级呈现的像素形态仍 unknown，真机终判。斜杠景的文本喂入为模型侧同构喂入，非逐字键入等价。

## 7. 同树避让与完好性

- 本批 hunk：MomentBridgeUITest.swift（主体，独占文件）；MomentApp.swift 五处（toggleTodoChecked 抽取 + 勾选钮单行化、editor.view 两读、doneCapsule 锚、slashPanel 锚、scroll 锚）；verify_ios.sh [25] 组内追加一段。
- 完工复验：在途各批 hunk 俱在（E3 clearTypeFields/convertNodeType、E4 [32] 组、DT fieldFont dynFont 注释与量测、媒体 [33]、权限 [34] 等均在位）；行号因多批叠加整体后移，锚点以内容为准。
- 本机无 swiftc（工具链在 tree），Swift 语法/类型终验随下一组版 tree 冒烟（smoke_ios.sh 全量）收口；本机已过 verify 静态全组 + 人工逐段复读。
