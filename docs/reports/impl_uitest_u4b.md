# U4b 撤销面场景批实装报告（EDT-14 undo_redo_roundtrip）

2026-11-27 晚。基线 HEAD e12fc62（0.9.59）+ E2 未提交落码之上施工；
E2 hunk 只读未动，本批只加场景、断言与矩阵回写，未改任何功能代码；
未提交、未 bump，随 0.9.60 组版。规格出处：plan_selftest_coverage.md
§4 EDT-14 行、§6.3 U4b 取项、§6.8 出包回归子集口径；
impl_editor_undo_e2.md §六终判点与 §七交接（场景名与被测面由 E2 定）。

## 一、落点清单

| 文件 | 改动 |
|---|---|
| MomentBridgeUITest.swift | 新场景枚举 UITestScenarioUndoRedo（+679 行）+ 目录 def 一条 + 目录注释一行 |
| verify_ios.sh | 新组 [48] U4b-1..4（尾部追加，未动既有组） |
| plan_selftest_coverage.md | EDT-14 行改判已覆盖、§6.3 U4b 续注、§0 计数 33/95→34/94、§0 扩展批注记 |
| CONNECTOR.md | 无改动（只对 BR 场景逐景登记，uitest 段为通用描述、无逐景名目录） |

## 二、场景与矩阵行对应

| 矩阵行 | 场景 | 夹具 | 被测面 |
|---|---|---|---|
| EDT-14 撤销/重做回路 | undo_redo_roundtrip | .blocks | E2 漏斗 EditorModel.undo()/redo() + UndoHistoryCore；canUndo/canRedo 即菜单项可用态的同源 @Published 值，场景直读 |

与 E2 §六真机终判点的分工：终判点 1（爆发一撤整段）、3 后半（不双撤的漏斗
单消费面）、5（幻影步）、6（钳制）由本景在驱动面内覆盖；终判点 2 的选区
像素落点、3 的物理手势/按键投递、4（标题字段 Cmd+Z）不在驱动证据面，
仍归真机（见 §五分级）。

## 三、步表与断言（8 步，open/close 为共享步）

1. **baseline**（empty history no-op）：canUndo/canRedo 开编皆假；空栈
   undo()/redo() 后 600ms 缺席窗内无任何「余栈」步行；旗标仍皆假。
   缺席断言以时间谓词实现（ctx.poll 等满窗），非事件等待——报告口径按此。
2. **burst_merge**：焦点请求开会话（focus_claimed / session_anchor_
   canUndo）→ 同构键入 5 键（burst_text_applied）→ saveNow 落盘回读同值
   （burst_text_readback）→ undo 一次整段回退（burst_merged_4 /
   one_undo_reverts_burst / canRedo_after_undo）→ 回退落盘回读
   （reverted_readback）→ redo 整段恢复（redo_restores_burst /
   canRedo_consumed）。
3. **redo_tail_cleared**：再 undo 回爆发前（back_to_base / redo_armed /
   undo_drained）→ 新键入一键 → redo 尾清空（redo_tail_cleared /
   new_text_applied）。
4. **selection_restore**：辞焦（resigned_before）→ 非零选区 (1,2) 替换
   键入 + 续键入（replace_typed）→ undo → 文本回退（text_reverted）、
   Diag 步行 focus= 回读串恰为「A@1+2」（focus_restored_sel）、焦点真
   落回 A（focus_landed_back）；撤销后 undo 深度记 store（depth_
   recorded）供下一步判据。
5. **phantom**：三次开会话→辞焦零变更 → dedup 行恰 3（dedup_lines_3，
   账见 §四）→ 一次 undo 文档不变（doc_unchanged_by_anchor_undo）、
   深度恰回基线（depth_back_to_base）。
6. **clamp_and_single**：todo 连翻 105 次（toggles_flipped_odd）→
   clamp 行出现且末行 depth=100（clamp_logged / clamp_depth_100）→
   一次 undo 恰退一格且步行恰 1 条（single_undo_one_step /
   single_undo_one_line）→ 一次 redo 恰回一格（single_redo_one_step）。

卫生与 S1 同级：全程只写夹具篇（驱动写路径有 fixture_guard），终态由
驱动复原链软删+真删自清、pre/post libraryHash 对账，终态码优先级沿
矩阵既有口径（restore_failed > hygiene_failed > aborted_user_active
> run_timeout > step_failed > ok）。

## 四、账本推演的源码实证（落码前逐项核过，非印象）

- **打开既有篇不压锚**：wantsInitialFocus 只在 createAndOpen（新建篇）
  置位，桥 requestOpen 打开既有夹具篇不落焦——baseline 的 canUndo=false
  前提成立（MomentApp.swift createAndOpen / openMemo 两路对照）。
- **首键去重、merged=4 稳健**：UndoHistoryCore.noteTextWillChange 在链
  未起时先 appendUndo——首键快照与会话锚同 key 必被去重但链照起，余
  4 键 withinBurst；无论首键 pushed 或 deduped，撤销行的 merged 恒 4。
- **恢复认领锚（phantom 账的决定项）**：选区步的 undo 经 restore-
  Selection 置 focusBlockId，认领触发真实 didBeginEditing 并压锚——
  其 payload = 恢复后文档，与栈顶（爆发前态）key 不同故 pushed，栈顶
  自此为该同 key 锚；phantom 三次空会话压锚全与之同 key → dedup 恰
  3（非 2），末撤消费该锚、深度恰回选区步基线。初版设计按 dedup=2
  推演，通读认领链后修正为 3——此为本批唯一实质账本修正，属场景侧，
  非功能缺陷。
- **换实例纪律**：applySnapshot 整表重建 BlockState，撤销/重做后读块
  必须按 id 现取（场景 block(_:_:) 助手 + Self. 限定四处，避局部同名
  遮蔽——primary 遍首跑即抓出，已修）。
- **喂入同构**：键入经 noteTextWillChange 检查点（shouldChangeTextIn
  普通文本放行点的同一馈入口，range 为变更前文本 UTF-16 口径）+
  didChange 模型侧同步（text/runsFrom 重建 + updateSlash），与
  UITestShared.feedBlockText 的既有同构口径一致，只是多了检查点馈入。

## 五、证据分级（不升级表述）

- **proven 上限（驱动面内）**：撤销状态机（合并/去重/钳制/清重做尾/
  单消费）、落盘回读、canUndo/canRedo 旗标、Diag focus= 回读串、焦点
  状态机落回（editingBlockId）。
- **unknown（不在证据面）**：Cmd+Z / Shift+Cmd+Z / Cmd+Y 与三指手势
  的物理投递、摇一摇不弹窗、识别器仲裁、选区在真实文本字段内的像素
  落点、键盘呈现。单轨接线（四入口只经漏斗、undoManager 恒 nil）由
  构建期 [47] E47-4/E47-5 锁；物理面终判仍归 E2 §六真机 6 点。
- 目录 grades 已按此钉死（stateMachine/persistence = proven，
  hitDelivery/keyboard = unknown，note 写明边界）。

## 六、本机自检结果（已实证层级）

- **编译**：UITest primary 遍（build-app2.sh 同口径 swift-frontend
  全文件集）零 error，bridge_uitest.o 产出（746,360 B）。首跑抓出
  局部名遮蔽 4 处，Self. 限定后复跑归零。
- **verify_ios.sh 全量**：514 ✓ / 2 ✗——2 红为既有产物陈旧项（ipa 早
  于源码、产物语言包未重建），与 E2 批本机口径一致，非本批引入；
  新增 [48] 四条全绿（U4b-1 注册全集 / U4b-2 漏斗接线 / U4b-3 断言锚
  / U4b-4 矩阵对应）。
- **verify_docs.sh**：exit 0（链接 95 / 锚点 6 / 反引号引用 363 全
  命中，孤儿警告为既有 51 份、本报告经矩阵按名引用不入孤儿）。

## 七、待 tree / 真机项

- **tree 实跑（归 0.9.60 组版批）**：组版冒烟时经桥 uitest_run 实跑
  undo_redo_roundtrip，预期终态 ok、逐步断言全绿、pre/post 库哈希
  相等；本景属编辑器增量子集，后续动编辑器的版本组版报告按矩阵
  §6.8 引用本景回归。
- **真机**：E2 §六 6 点不变（爆发一撤整段手感、非零选区光标回位像
  素、Cmd+Z 与三指不双撤 + 摇一摇无弹窗、标题字段 Cmd+Z、空会话无
  幻影步手感、100+ 钳制的 Diag 佐证）。
- push_small.py 名单：本批无新文件（场景在既有 UITest 文件内），组版
  批同步整文件即可；MomentUndo.swift 名单补入仍按 E2 交接在组版批
  办理。

## 八、缺陷回报

无。施工中未发现 E2/本线功能缺陷；§四的 dedup 计数修正为场景账本
对源码行为的对齐（恢复认领压锚是 E2 定案行为，非缺陷）。
