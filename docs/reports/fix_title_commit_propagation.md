# 标题提交→库回读传播缺口根治（fix_title_commit_propagation）

实证来源：主线走桥自办（0.9.57 真机）——S1 场景 `title_capsule_reedit` 连跑两遍（runId 91243f4c-1ebe / 742a8d8a-2b7e），同一步同一断言确定性失败、终态码 step_failed：第 3 步「set long title + resign」中 `title_committed` ✓（编辑器侧标题已提交为长标题），`notes_get_title` 回读为夹具原短标题。两遍卫生全清（pre/post libraryHash 相等、夹具已清），故障域只在标题传播。本批定性 + 根治落码完成，未提交、未 bump，随 0.9.58 组版。

## 一、定性（全链通读，proven）

标题会话全链（现行源码）：

- 开始：`TitleTextField.Coordinator.textFieldDidBeginEditing` → `onBeginEditing`（快照 titleBase + Diag `EDIT title session begin`）。
- 草稿：键入经 `editingChanged` 只写 `ui.titleDraft`（视图状态，E4 口径：草稿只活视图状态）。
- 结束（全漏斗收敛于一点）：`textFieldDidEndEditing` → `onEndEditing` → Diag `EDIT title session end` + `commitTitle()`；Enter（shouldReturn 辞焦）、完成胶囊 `finishEditing`（resignFirstResponder）、驱动 resign 动作（先直调 commitTitle 再置 focused=false、didEndEditing 二次调用幂等无变更）全部经此点。
- `commitTitle()`（EditorHeaderView）：trim/空回退「无标题」→ 真变更时 `pushHistory` + `editor.title = final` + **`editor.scheduleSave()`** + 反链刷新。
- `EditorModel.scheduleSave()`：取消在途后 `DispatchQueue.main.asyncAfter(0.6s)` → `library.persist(preparedItem())`。
- `Library.persist(_:)`：序列化 → FFI `upsertMemoJson` 写库，**成功后才**同步更新内存镜像 `memos[idx] = it` + `touchMemos()`（源码注释钉死「列表 = 库的镜像、写入成功后才同步」）。
- 桥回读：`BridgeReadTools.notesGet` 读 `allMemos(library)` = `library.memos` 镜像（+待删集），不直读存储。

场景步 3 的读时序：`setText` 置草稿 → resign 动作 → `waitState(editor.view.title == 长标题)` 命中后**同步**直调 notesGet。editor.title 在 commitTitle 内同步赋值，waitState 命中即读，回读点距 resign 约 104ms（主线实测口径），结构性恒在 600ms 防抖窗内。

三候选逐项裁定：

- **(a) 时序——近因，proven**：回读抢先于防抖落盘。persist 未运行时镜像仍持夹具短标题，读回必然旧值；两遍同点同断言、与等待时长无关地确定性复现，与此机制逐项吻合。
- **(b) 缺写——结构根，proven**：不是永不写（closeEditor 的 saveNow、E4 切后台 flush 终会冲刷），而是**提交点未落**：标题提交是会话结束点的离散提交事件，却被路由进为正文键入流设计的防抖路（scheduleSave）。在设计钉死的提交点上，已提交标题只存在于 EditorModel，库的权威存储与镜像均未更新——提交点语义不成立，这才是根。
- **(c) 读陈旧——排除，proven**：notesGet 读的是既定镜像，镜像在 persist 写成功后同步更新，读方忠实、无独立缓存/索引滞后。滞后全部来自上游未写；读方不修（任务书明禁消费方特殊刷新）。

设计口径核查（停报门）：`plan_ui_selftest_driver.md` §4.1 步 3 明定期望「waitState editor.title = 模板值；断言 commit 后 notes_get（内部直调）标题一致」——设计即要求提交后回读立即一致，无「等防抖」另行口径；覆盖矩阵 EDT-08 同口径（S1 验改值回读）。按设计修 App 侧，不触发停报。

与 E4 口径对账：E4 定「标题草稿只活视图状态、模型只持已提交值、切后台 flush 只冲正文（经 saveNow 冲已提交值）」。本批不写草稿：commitTitle 只在会话结束点运行、冲刷的只有已提交值（trim/回退后的 final）；`ui.titleDraft` 仍只活视图状态。会话结束提交点与切后台 flush 点同为「已提交值的冲刷点」，口径一致、无冲突。

## 二、根治落点

`MomentApp.swift` `commitTitle()`：标题真变更分支 `editor.scheduleSave()` → **`editor.saveNow()`**，函数头注释同步钉口径（会话结束即提交点、防抖是正文流的、载荷同一 preparedItem 只提前到提交点）。

- 单点收口：commitTitle 是标题提交的唯一漏斗（会话结束/编辑器退出/驱动 resign 三调用点，TC37-2 计数锁），改此一点全漏斗生效。
- 载荷等价：saveNow 与防抖路共用同一 `preparedItem()`（title + 当前 blocks + bg/layout），只是把同一笔写从 +600ms 提前到提交点同步执行（saveNow 顺带取消在途防抖工单，无双写）。
- 行为等价面：Esc 还原路径 final == editor.title 不入分支、零写（与旧行一致）；未变更提交零写（与旧行一致）；只读态 `Library.persist` 的 writeBlocked 守卫对两路同等生效；正文键入流防抖未动（TC37-3 锁）。
- 已知良性差异：closeEditor 在标题有变更时先经 commitTitle 冲刷、再走自身 saveNow，共两笔同内容 upsert（第二笔 updatedAt 取胜，与旧行单笔 outcome 一致）；标题未变更时仍为单笔。

未采纳的替代：镜像在提交方提前刷新（破坏「镜像随写成功」不变量、属消费侧补丁变体）；缩短防抖（仍是竞速、且动正文流口径）；场景加等待（任务书明禁凑绿）。

撤销/重做路径（applySnapshot 改 title 后 scheduleSave）不在本批：那是文档级连续编辑操作、随正文流防抖为既有设计，本次故障域只在标题提交点。

## 三、断言（verify [37] 新增组，全绿）

- TC37-1 提交点机制锁：commitTitle 函数体内 `editor.saveNow()` 恰 1、`editor.scheduleSave()` 恰 0。
- TC37-2 漏斗守恒：`commitTitle()` 全文件恰 4 处（定义 1 + 调用 3：onEndEditing / closeEditor / 驱动 resign）。
- TC37-3 正文流防抖守恒：scheduleSave 函数体内 `.now() + 0.6` 恰 1（防以缩短防抖冒充根治）。
- TC37-4 镜像不变量：Library.persist 函数体内 `upsertMemoJson` 行号恒先于 `memos[idx] = it`。

本机自跑：verify 全量 354 ✓，[37] 四条全绿；仅剩 2 红为既有产物陈旧项（ipa 早于源码、产物语言包待 tree 构建），与本批开工基线一致、非本批引入。MomentApp primary 遍（build-app2.sh app.o 遍原样旗标）全量类型检查 **零 error**、.o 产出（编译前后 MomentApp.swift md5 一致、稳定读）。

并发留痕：类型检查第二跑曾遇 64 条「use before declaration」类 error，定性为兄弟批（首页回归批）并发写 MomentApp.swift 期间的撕裂读——错点遍布无关位置且含现行文件明显正确的声明序；文件稳定后第一、三跑均零 error。此为本机同树并发的已知环境面，组版 tree 冒烟以串行构建为准。

同树避让：动工前 git diff 全量快照（10603 行）映射——commitTitle 区（HEAD 10228 行）与相邻在途 hunk（10298 行起）零交叠；完工复验增量差仅为兄弟批 EditorView 领地 hunk 生长 + 本批两处落点，他人 hunk 完好。

## 四、真机终判口径（0.9.58 装后）

走桥重跑 S1（`title_capsule_reedit`）两遍：**两遍终态码 ok 且步 3 `notes_get_title` 回长标题**为关闭证据；U2 开工门 BRG-09（S1 首跑两遍一致）随之复核。附带抽验：真机手编一篇长标题（失焦提交）后立刻回首页，列表标题即为新值、无 0.6s 滞后窗。
