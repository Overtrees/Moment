# fix_undo_step5_selection — EDT-14 步 5 选区恢复实测缺陷根治

## 一、实测证据（0.9.63 桥上实跑）

- 场景 `undo_redo_roundtrip`（EDT-14）runId `6c23d26a-eec5`，终态
  failed / step_failed，败点在步 5「selection restored on undo」；
  步 1–4 全过（空历史 no-op、连打合并 merged=4/dedup=1、undo/redo
  回路、新编辑清 redo 尾）。
- 步 5 两断言失败：
  - `text_reverted`：期望回退到「自检段落甲己」，实际回退到更早的
    「自检段落甲」——选区替换那次编辑的 undo 多退了一层；
  - `focus_restored_sel`：期望选区 `b-e9f02345@1+2`，实际
    `@5+0`——选区未按预期恢复、仅块焦点回位。

## 二、机制定性（proven）

步 5 前的栈顶返回点是 redoTail 步「己」字追加所落的 E2（载荷 =
「自检段落甲」文档态、sel = 追加范围 (5,0) → `@5+0`），且其文本
合并链仍活着。步 5 的时序是：辞焦（真实耗时百毫秒级）→ 选区替
换馈入 → 续键入 → 一次 undo。替换馈入落在「己」键后 600ms 窗
内时，`UndoHistoryCore.noteTextWillChange` 的窗内合并支路直接
`return .withinBurst`——**不落新返回点，且 EditorModel 辛苦算出
的「被替换范围」sel 被整条丢弃**；续键入同样并入旧链。于是
undo 弹出的只能是 E2：文本多退一层（回「自检段落甲」）、
focus 回读 E2 的 `@5+0`——与实测两断言的实际值逐字吻合。

- 证据分级：机制 = proven。失败签名（载荷与 sel 同时恰为 E2 的
  值）唯一对应「替换被爆发链吞并」这一条路径——若替换曾落新返
  回点 E3，其 sel 必为 `@1+2`、载荷必为「自检段落甲己」文档态，
  两断言至少过其一。600ms 窗内这一时间前提本身 = inferred（未
  直测 Δ 值，由结果反推），但修复使语义不再依赖该时间量，前
  提真伪不再影响结论。
- 语义权威：E2 定案（impl_editor_undo_e2.md §四）明文「文本检
  查点的选区取被替换范围（爆发前选区）」——该 sel 只有在替换馈
  入能落返回点时才可达；纯墙钟合并使 F-11 选区恢复随亚秒级时
  序翻转，是实现缺陷、非场景过规格。**场景断言一字未改。**
- 真机可达性：同一吞并在真实编辑链同样存在——会话内以键盘选
  区+重打、或输入法整段替换在上一键 600ms 内完成时，替换被并
  入先行爆发，一撤多退且选区落爆发锚点。场景步 5 的「辞焦后直
  接馈入」是把检查点单独隔离测（真实链的会话开始 recordOp-
  Boundary 本会断链），修复落在检查点/核心层，两条路径同盖。

## 三、判别口径（关键修正）

- 初判「range.length > 0 即断链」被否：单字退格的 range.length
  同样为 1，照此每次退格自成一步、退格爆发的撤销粒度爆炸。
- 定案判别：**breaksBurst := range.length > 0 &&
  !replacement.isEmpty**——「非空范围被非空文本替换」才是独立
  编辑操作（选区替换）。纯删除（退格/选区删除，replacement 为
  空）不置位、仍走爆发合并（与 Web coalesce 同向）；粘贴（零
  长范围）不置位；零长插入全口径不变。

## 四、落点

- `MomentUndo.swift`：`noteTextWillChange` 增形参
  `breaksBurst: Bool = false`；置位时跳过窗内合并早退支、照常
  落新返回点（去重/钳制口径不变），并以本馈入重启合并链（其
  后连续键入并入替换步——步 5「续一键入（窗内合并）」的预期
  形态）。
- `MomentApp.swift`：`EditorModel.noteTextWillChange` 增
  `replacement: String` 形参，向核心传
  `breaksBurst: range.length > 0 && !replacement.isEmpty`；
  `BlockTextView.feedUndoCheckpoint` 增 `replacement` 形参，
  三处放行点（代码块换行 / Shift+Enter 软换行 / 普通文本放行）
  各自把 `shouldChangeTextIn` 的 replacementText 穿入。
- `MomentBridgeUITest.swift`：场景 `typeReplace` 把其
  replacement 转发进检查点调用——喂入面与真实链同构化，断言
  未动。

## 五、断言与自检

- verify [47] E47-3 断言体新增 h7（步 5 在核心层的全序复刻：
  锚→爆发→撤→重做→再撤→续键起链→窗内替换断链起步→续键并
  入替换步→一撤恰回替换前载荷且条目 sel = 被替换范围）与
  h8 对照（零长插入窗内仍合并）。本机以 verify 原文抽出的断
  言体 + 改后核心编译实跑：**UNDO_CORE_PASS**（swiftc 6.4.2）。
- 负对照（机制锁验证）：在 /tmp 副本中摘掉核心的
  `!breaksBurst` 守卫（= 旧语义），同一断言体恰红三条 h7 替
  换断言（replace breaks / merges into replace / one undo =
  pre-replace），与真机失败形态同构——断言锁的是机制非文本。
- verify 新增 E47-9 接线断言：核心 `breaksBurst` 出现 3 处
  （注释/声明/守卫）、模型传参 `breaksBurst: range.length > 0`
  恰 1 处。既有 E47-6 计数复核不漂移（`feedUndoCheckpoint(`
  = 4、两处 `func noteTextWillChange` 各 1）。
- `swiftc -parse` 三个改动 Swift 文件全净；verify_ios.sh
  `bash -n` 过。本机未跑全量 verify 与整包构建（他线 WIP 在
  树，归组版轮 tree 冒烟）。

## 六、提交与撞车记录（如实登记）

- 已成笔：`1a0b194`（MomentUndo.swift + MomentBridgeUITest
  .swift）。
- **被扫入**：feedUndoCheckpoint 的定义改动（签名+注释）已被
  批 3 线提交 `be0ac74`（解码管线收口，其暂存整文件带走
  MomentApp.swift）收进 HEAD——内容无损、已逐字核对。
- **留组版收**：MomentApp.swift 余 5 个 hunk（三处放行点调用、
  EditorModel 注释/签名、核心调用表达式）与 verify_ios.sh
  4 个 hunk（E47-3 注释/断言体/通过串、E47-9）仍在工作区未
  提交。原因：本线落码期间索引里已有他线暂存内容，直接暂存
  本线 hunk 会与之混合成笔（今日已有误扫前科），故按 hunk 过
  滤补丁核对后主动撤出、只提交纯属本线的文件；组版时请按
  「breaksBurst / replacement / E47-9」标记整文件收齐。在此
  之前 HEAD 处于「定义先行、余件未落」的暂态（单独构建 HEAD
  不过），组版收齐后即闭合。

## 七、验收口径

- 本版证据上限 = 纯核心单测 + 接线断言层 proven；桥上复跑须
  等下一版（0.9.64）装机后重跑 `undo_redo_roundtrip`：预期步
  5 两断言转过、步 1–4/6/7 不回退（burst merged=4、幻影去重、
  100 钳制均已逐项对过新口径）。
- 账本旗标：impl_editor_undo_e2.md §三规则表尚未载「选区替换
  断链」一条，归批 6 账本线/组版时回写，本线未代改。
