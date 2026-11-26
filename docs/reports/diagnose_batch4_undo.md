# 批 4（B-4）撤销粒度确诊报告

确诊日期：2026-11-24。范围：只确诊、不落码。基线口径：landing_plan.md 批 4 节 B-4 行、audit_parts/part_B.md B-4 条、audit_editor_full.md H-3 条；结论一律以现行代码实证为准（审计引用行号已漂移，本文行号均为现行文件实测）。

## 0. 结论摘要

- 审计口径**成立（proven）**：普通打字不落模型，doc 信号在纯打字会话内冻结；历史栈的合并机制（600ms/100 步）本身已对齐原版，但**没有输入流喂它**——合并时钟只被 mdText 与 pasteSync 两类消息驱动，普通段落打字的文本根本不产生消息。
- 一次 Ctrl+Z 回退数分钟的成因链完整闭合（见 §1.5）：撤销时 step_undo 先把当前全文同步压栈、再后退一格，落点是上一个结构性快照或打开基线，两点之间全部打字即一步。
- 根治方向与原版同构：桥侧 input 后 80ms 防抖发一次全文（或增量）同步消息，Rust 侧落**真 doc 信号**并以 coalesce=true 压栈；20s 定时器退为兜底。落点集中在 bridge.rs 输入管线与 editor.rs 一个新 op，hist_push/step_undo 本体不用改。
- 关键风险一条：inputSync 落 doc 会触发 doc 信号更新，须实证编辑中块的渲染不回写活 DOM（mdText 逐键落模型已上线运行，inferred 可 tolerable，落码首笔必须带光标稳定性探针坐实）。

## 1. 现行链路实证（proven，带行号）

### 1.1 输入如何进模型——普通打字：不进

桥 `root.addEventListener('input', …)`（`rust/apps/web/src/editor/bridge.rs:984-989`）：组字中直接 return，否则调 `processInput(el)`。

`processInput`（bridge.rs:994-1072）的全部分支：

| 分支 | 行为 | 是否落模型 |
|---|---|---|
| mdsrc（bridge.rs:997-1000） | 每 input 事件发 `mdText`（整块 innerText） | 是，逐键 |
| musicInput（:1001-1005） | 发 `musicInput` 复检 | 否（设计如此） |
| codeBlock（:1006） | 直接 return | **否，整段打字零消息** |
| realtimeHighlight 命中（:1007-1010） | 仅光标刚闭合 `==…==` 时发 `pasteSync` | 偶发 |
| 斜杠检测（:1012-1045） | 发 `slash`/`slashClose`（只动面板信号） | 否 |
| 智能前缀防抖（:1050-1071） | paragraph 停顿 80ms 后，文本命中 `# / > / [ ] / [] / ---` 模式才发一次 `pasteSync`（仅该块） | 仅模式命中时 |

即：普通段落/标题/列表/todo 里打字（不触发上述模式）**不发任何模型同步消息**，文本只存在于活 DOM。块内退格/删除同理：桥 keydown 仅在光标 offset==0 时发 `merge`（bridge.rs:919-926），块内删除是浏览器原生 DOM 编辑、零消息；Enter 发 `split`（:919，带 before/after HTML——仅被拆的那一块文本随之入模型，其余块的未同步文本仍不在模型里）。

### 1.2 20s 同步的真实触发与粒度——只落持久副本

- 桥定时器（bridge.rs:1759-1764）：`setInterval` 20000ms，页面 visible 时发 `{op:'sync', map: collectSync()}`；`visibilitychange` 到 hidden 时补发一次（:1765-1769）。
- `collectSync`（bridge.rs:365-376）：遍历全部 `[data-bid]` 取 innerHTML 成 map（排除 mdsrc、musicInput；含 codeBlock）。
- Rust 侧 `"sync"` op（`rust/apps/web/src/editor.rs:4394-4408`）：把 map 套到 doc 的**影子克隆**上，变化才 `persist.call(shadow, …)` 落盘；**从不 `doc.set`、从不压历史栈**（消息循环按 handle 前后 doc JSON 判定压栈，editor.rs:1820-1825，此 op 前后 doc 不变，天然不压）。

后果分层（proven 机制推导）：

- 读**持久副本**的面（列表页数据等）：滞后 ≤20s。
- 读 **doc 信号**的面：滞后**不以 20s 为界**——纯打字会话内 doc 信号冻结在最后一个模型变更 op，直到下一次结构性 op / 撤销 / 关闭才动。实证落点：编辑页字数 `orig_char_count(&doc_snapshot)`（editor.rs:2668、:541-547）；双栏分界派生 `normalize_boundary(&d, layout)`（editor.rs:1645，columns.rs:70）。

### 1.3 历史条目如何生成与合并——机制在、喂流缺

- 栈本体：`hist: Vec<String>`（doc 全量 JSON 快照）+ `hist_idx` 指针，打开时以会话文档为基线 `[json]`、idx=0（editor.rs:1699-1702）。Rust 是**后态快照 + 指针**模型（栈内存「变更后」的文档），与原版「前态条目」模型净效果等价，差异只在记账方式。
- 消息循环（editor.rs:1817-1827）：每条桥消息 handle 前后各序列化一次 doc，`!skip_hist && after != before` 才 `hist_push(after, coalesce)`。
- `hist_push`（editor.rs:176-207）：与当前快照相同不压；`coalesce && 合并链活着 && idx 在栈顶 && 距上次 <600ms` → 替换栈顶（爆发合并）；否则截断重做尾、压栈、上限 100（`h.len() > 100` 时 `remove(0)`）；`hist_clock.set((now, coalesce))`——**结构性压栈（coalesce=false）即断链**。
- coalesce=true 的来源只有两处：`mdText`（editor.rs:4213-4216）与 `pasteSync`（:4243-4246）。其余变更 op（split/merge/convert/pasteText/卡片/拖拽等）一律 coalesce=false。
- 净效果：md 源编辑、粘贴、Shift+Enter、智能前缀命中等路径**已有**爆发粒度；普通打字路径连一条消息都没有，合并机制无从生效。审计背景里「此前批次已部分对齐撤销合并参数」属实——参数（600ms/100 步/撤销后断链）已逐字对齐，缺的是喂流。

### 1.4 撤销/重做入口与 step_undo/step_redo

入口四路，均带 `sync: collectSync()` 全量快照汇入同一 `step_undo/step_redo`：桥 keydown Ctrl/Cmd+Z/Y（bridge.rs:848-862）、document 级兜底（bridge.rs:1525-1526，批 1 B-10）、beforeinput historyUndo/historyRedo（bridge.rs:1595-1596，批 1 B-5）、菜单按钮（editor.rs:2518-2560，经 eval 拉 `__mnSyncAll`，bridge.rs:2836）。

`step_undo`（editor.rs:252-302）：

1. `apply_sync_map` 把 sync 快照套到 doc 克隆 → `cur`（此刻模型才第一次拿到全部打字文本）；
2. 若 `hist[idx] != cur`：截断重做尾、压 `cur`、idx 移到栈顶（上限 100）；
3. `hist_clock` 归零断链；
4. idx==0 则停；否则 idx-=1，反序列化该快照 `doc.set`、`epoch+1` 整体重挂载、`restore_focus` 落光标、persist。

`step_redo`（editor.rs:305-350）对称，并对「撤销后又打字」的分叉有显式处理。

### 1.5 一次 Ctrl+Z 回退数分钟的成因链（proven）

设用户在一段里连续打字 3 分钟（无 Enter、无模式命中、无粘贴）：

1. 全程零模型消息（§1.1），hist 栈顶仍是打开基线或上一个结构性快照；
2. Ctrl+Z 到达，step_undo 把当前全文压栈（§1.4 步 2）——栈里新增的只有「现在」这一态；
3. idx-=1 落到基线/结构性快照——**3 分钟打字整体消失**；再 Ctrl+Y 又整体回来。中间不存在任何爆发粒度的中间态，因为它们从未被记录。

若中途有过一次 Enter：split 快照只含被拆块的 before/after（op_split 仅写回拆分产物），其余块的未同步文本不在该快照内——撤销到该快照时其余块的打字照样整段丢（proven：op_split 写回范围 + §1.1）。

## 2. 与原版规格的逐项差异

原版现行文件：`src/app/editor.js`（handleEditorInput 现位于 :1769 起，审计引用的 :1922 已漂移）、`src/app/editor/use-history.js`。

| # | 项 | 原版（proven） | Rust 现行 | 差异 |
|---|---|---|---|---|
| 1 | 打字落模型时机 | editor.js:1903-1915：每次 input 重置 80ms 定时器，尾部 `parseEditorDOM` 全文落模型，序列化有变即记撤销点 | 无（§1.1） | **核心差异** |
| 2 | 撤销点记录 | editor.js:1910-1914：`lastSnapshotRef = prevDoc; recordUndoPoint()`，与落模型同一防抖尾 | 仅模型变更 op 触发（§1.3） | 随 #1 |
| 3 | 合并窗口/上限 | use-history.js:170-193：600ms 内合并（保留更早 before）、past 上限 100、future 清空；undo/redo 后 lastPushAt 归零（:214/:223/:247/:256） | hist_push 600ms/100/断链语义已对齐（editor.rs:176-207、:282、:327） | 无（参数面） |
| 4 | 智能前缀时点 | editor.js:1916 起：同一 80ms 防抖尾、落模型后扫 | 桥侧独立 80ms 防抖 + pasteSync 命中才带入、Rust 在消息尾同步扫（editor.rs:4419-4435） | 时点结构不同、净效果近似；根治后应收敛到同一条防抖链（见 §3） |
| 5 | 历史条目含 layout | use-history.js:172-187：条目含 snapshot+layout（B-7） | 仅 doc JSON | 属 B-7，不在本报告根治范围，交互见 §3.3 |
| 6 | 组字路径 | editor.js:3258-3260：组字中跳过、compositionend 重放 handleEditorInput | 批 1 B-11 已补 compositionend 重放 processInput（bridge.rs:991-994 注释口径） | 重放入口已有，新防抖须挂在 processInput 而非裸 input 监听（见 §3.2） |

## 3. 根治方案

### 3.1 目标语义

- 普通打字（段落/标题/列表/todo/引用/codeBlock 等一切可编辑文本块）在**停顿 80ms 后落真模型**（doc 信号），粒度与原版防抖尾一致；
- 落模型消息以 coalesce=true 压栈：600ms 内连续爆发合并为一步，撤销一次回到爆发前；结构性 op 照旧断链；上限 100 步；
- doc 派生（字数/分界/反链）随落模型即时刷新（≤80ms+一帧）；
- 20s 定时器与 hidden 补发保留，退为兜底（模型已实时时其影子比对恒无变化、天然无操作）；
- persist 仍走现行 PersistHandle 单通道，不新增落盘路径。

### 3.2 落点与改法

**桥（bridge.rs）**：

1. 在 processInput 尾部（或 input 监听与 compositionend 重放的公共尾）加一个全编辑器单例防抖 `inputSyncTimer`（80ms），触发时发新 op `inputSync`，载荷为**增量 map**：桥侧维护 `lastSentHtml` 表，仅收录 innerHTML 变化过的 `[data-bid]`（排除口径同 collectSync：mdsrc 走 mdText、musicInput 不落）。增量而非全量：避免每爆发对未动块重复 `editor_html_to_inlines` 重解析（现行 apply_sync_map 对 md 相关块有归一非幂等前科，见 editor.rs:672-676 注释所记 sync 归一教训——少碰未动块即少一分风险面）。
2. 定时器登记进 `bridgeDisposers`（与 prefixTimers 同惯例，bridge.rs:979-982），卸载即清，杜绝向死通道发送（bridge.rs:39 注释所记前科）。
3. codeBlock 块当前在 processInput 早退（:1006）——防抖调度点须在该 return **之前**或为 codeBlock 单独调度，保证代码块打字同样落模型（原版 parseEditorDOM 全覆盖）。

**Rust（editor.rs）**：

4. 新增 `"inputSync"` op：对真 doc 调 `apply_sync_map`（现成，:4438），有变化则 persist；返回 `coalesce=true`，由消息循环统一压栈（不自理历史）。
5. 把 `"inputSync"` 加入消息尾智能前缀扫描的 op 名单（:4419 的 `matches!`）——与原版「落模型后同尾扫前缀」同构，转换与打字同属一个撤销步。桥侧现有模式门控 pasteSync 防抖（bridge.rs:1050-1071）届时冗余（同内容 pasteSync 到达时 after==before、天然不压栈不落盘），首笔可保留、探针绿后第三笔再删。
6. hist_push / step_undo / step_redo **不改**：喂流到位后，step_undo 的「先同步压栈」只在真有未及防抖的尾巴（<80ms 内按 Ctrl+Z）时才有增量，落点自然是上一爆发。

### 3.3 风险面

- **编辑中块渲染回写（最高优先实证项）**：inputSync 每爆发 `doc.set` 一次。现行 mdText 逐键 doc.set 已上线且光标无恙（inferred：编辑态块的活 DOM 应为非受控、内容仅挂载/dom_set 时写入），但普通段落的渲染路径是否同样非受控须在落码首笔以探针坐实（打字中块的 DOM 节点身份与光标偏移在 inputSync 前后不变）。若坐实失败，备选：inputSync 对「当前编辑块」延迟到 blur/结构 op 再落、其余块照常——但这会让字数仍滞后当前块，属降级口径，须回报用户再定，不得擅自采用。
- **persist 归属守卫**：inputSync 经 handle_bridge_msg 同一 persist 句柄落盘，不新建通道，守卫口径不变（落码时复核 PersistHandle 的属主校验仍覆盖此 op 即可，低风险）。
- **换篇路径**：防抖未发火即关篇时，最后 <80ms 的文本靠现有关闭路径的全量 sync 兜底落盘（proven：关闭/菜单路径均拉 collectSync）；但**历史粒度**上这截尾巴只进持久副本不进栈——与原版一致（原版关篇亦不补记撤销点）。探针须覆盖「打字后立即返回、重开文本完整」。
- **斜杠/卡片转换交互**：斜杠打开时打字照常 inputSync（原版同），智能前缀扫描仍受 panel 守卫跳过（editor.rs:4420 现行条件不动）；slashApply 自带 html 落转换、coalesce=false 断链，粒度不受影响。卡片类 op 同理。
- **撤销恢复焦点**：restore_focus 按块 id+偏移钳制恢复（editor.rs:230-247），爆发粒度变细后落点更贴近原版，不新增风险。
- **性能**：增量 map + 消息循环既有的前后全量序列化（editor.rs:1820-1824，本就存在）之外，新增成本仅变化块的 inline 重解析/爆发；大文档连打时以 Diag 计数观察（见 §3.4），若序列化成本成问题另立批 11 议题，不在本批夹带优化。
- **与 B-7（layout 快照）的交互**：B-4 落地后快照频率大增，B-7 若随后给条目加 layout 字段，栈内存随之放大（100 步 × (doc+layout)）——建议 B-7 独立成笔、条目格式变更与 B-4 分开评审，不捆绑。

### 3.4 需要的探针 / Diag

- 新增 `probe_undo_granularity.mjs`：
  1. 爆发 A → 等 >600ms → 爆发 B → Ctrl+Z 仅 B 消失 → 再 Ctrl+Z 仅 A 消失 → 两次 Ctrl+Y 逐步回；
  2. 块内退格爆发同口径；
  3. 打字后 ≤300ms 内字数统计刷新（不等 20s）；
  4. 打字中光标稳定性：inputSync 落定后活动块 DOM 节点身份不变、光标偏移不变（§3.3 首风险的坐实断言）；
  5. 打字后立即返回列表、重开文本完整（换篇兜底）。
- Diag：inputSync 有变化时记一条节流行（如 `input sync applied (n blocks)`，log_once/计数口径），探针侧断言读取按现行治理口径轮询等落盘（1s 节流）。
- 回归面：probe_bridge_input、probe_slash_*、smoke-rustweb-editor2、probe_root_dim 等含打字路径的既有套件须全绿（run_all_tests 链尾口径）。

## 4. 工作量分笔建议

| 笔 | 范围 | 说明 |
|---|---|---|
| 1 | bridge.rs 防抖+增量 map+新 op 调度（含 codeBlock、disposer 登记）；editor.rs `inputSync` op + 智能前缀名单扩入 | 主体根治，独立成笔；自带 §3.4-4 光标稳定性断言的最小自检 |
| 2 | probe_undo_granularity 新探针 + Diag 节流行 + TESTING.md 登记 | 验收笔，与笔 1 分开便于红绿归因 |
| 3 | 清理笔（探针全绿后）：删桥侧模式门控 pasteSync 防抖、20s 定时器注释改「兜底」口径 | 可选、低风险，不做也不影响语义 |
| — | B-7 layout 快照、B-3、B-14、B-15 | 不在本方案内：B-7 独立成笔（条目格式变更）；B-3/B-14/B-15 与撤销链无耦合，按 landing_plan 批 4 其余行另行排 |

## 5. 证据分级汇总

- proven：§1 全部行号实证、§2 原版行号、成因链 §1.5、合并参数已对齐。
- inferred：编辑态块渲染对 doc.set 的容忍度（由 mdText 上线行为推得，待探针坐实）；增量 map 与全量重解析的等价性（由 apply_sync_map 逐块独立作用推得）。
- unknown：大文档（数百块）下每爆发全量 doc 序列化的实测开销——现行消息循环已付此成本，增量可忽略为 inferred，但无实测数，留 Diag 计数在落码后回答。
