# Web 跨块选区边角洞核修（非 K5 路径丢弃首/尾外侧原子）

出处：原生一期报告 `impl_cross_block_selection_p1.md` §二分叉裁定——Web 非 K5 路径在选区端点顶到文档首/尾（from_start/to_end）时丢弃选区外侧全部块，与 ops.rs `op_replace_range` 的 K5 契约（「选区内及 Ctrl+A 首尾外侧的原子块全程存活、原位保留」）冲突；原生已按契约保外侧原子。本批只办 Web 侧：定性 + 根治 + 回归。基线 HEAD 0be6c1d，落码未提交、未部署（主线另行安排）。

## 一、定性：成立（proven，双侧实证）

### 代码级证据链

1. 触发面：`editor.js` `selectAllXsel()`（Ctrl+A）端点恒落首/末**可编辑块**（`editableBlocks()` = contentEditable 的 `[data-bid]`），并置 `fromStart/toEnd = true`；删除/覆打/回车/粘贴/剪切经 `sendReplace` 发 `replaceRange`（from/to 标记随行）。
2. 路径分流：`ops.rs` 的 K5 分段路径仅当端点顶层位**之间**（`s_top + 1..e_top`）有原子块时进入；外侧原子不计数。
3. 分叉点：K5 路径重组时外侧块条件为 `!from_start || is_atomic_class(block)`（契约口径）；非 K5 路径同位置只有裸 `!from_start` / `!to_end`——端点间无原子时，文档首/尾外侧的原子块被整块丢弃，op 随即 `doc.set` 并落盘。

### 实证（tree，Chromium 口径，未修复构建 wasm 戳 6c2536a069）

`probe_slash_anchor` 新增 K5c–K5f，对未修复构建跑两轮：

| 例 | 文档形 | 动作 | 未修复结果 | 判定 |
|---|---|---|---|---|
| K5c | [图][段][段] | Ctrl+A + Backspace | 落盘仅剩一个空段，**首图丢失** | 红（复现） |
| K5f | [段][段][视频] | Ctrl+A + Backspace | 落盘仅剩一个空段，**尾视频丢失** | 红（复现） |
| K5d | [段][段][图] | Ctrl+A + Backspace | 图存活 | 绿（被掩盖，见下） |
| K5e | [图][段][段][图] | Ctrl+A + 覆打 X | 双图存活 | 绿（被掩盖，见下） |

其余 38 项断言（斜杠锚定 S1–S9、K1–K7 既有不变量）未修复构建全绿——洞只落在新增判别面。

### 尾侧掩盖机制（取证探针实读，解释 K5d/K5e 为何不红）

定点取证（回读 `__mnXSel` 端点 + Diag `EDIT replace range` 行）：

- K5c：端点 `k5c-1@0..k5c-2@4`，Diag 无 `atoms kept` 后缀 → 非 K5 路径，首图被丢。
- K5d/K5e：焦点端点不是末段，而是一个运行时生成的块 id（尾随段）——`model.rs` `materialize_trails` 在打开备忘时对文末 `TRAIL_END_ATOMIC`（image/gallery/imgTextCard/imageTextRow/attachment/link-card/musicCard/todo）块后补一个真实空段。于是尾图从「端点外侧」变成「端点之间」，走 K5 路径存活。
- 不对称性：头部没有对应的前置物化机制，故首侧洞直接可达；尾侧洞被尾随段清单偶然掩盖，清单外原子（`video`、`embedCard`、`divider`、`decorative_divider` 等，渲染口径见 model.rs TRAIL_END_ATOMIC 注释）文末时不补段、洞直接可达——K5f 以 video 坐实。

结论：疑似洞**成立**。可达面 = ① 任意原子块位于文档首（首个可编辑单元之前）；② 清单外原子块位于文档尾（末个可编辑单元之后）。原生侧的裁定与保外侧落法正确，本批 Web 向其对齐。

## 二、修法（根源单点，不在消费方打补丁）

替换语义收口到一个契约谓词，两条路径共用：

- `rust/apps/web/src/editor/model.rs`：在 `is_atomic_class` 后新增 `outside_survives(block, truncated)`——未顶到该侧恒保留；顶到时仅原子类存活。注释写明可达性论证：非原子块（文本块/含项列表）必含可编辑单元，Ctrl+A 端点恒落首/末单元所在块，其外侧不可能有非原子块，故按类判定与「外侧无条件全留」在可达状态下逐字同果，本判定是外侧原子的唯一存活依据。
- `rust/apps/web/src/editor/ops.rs`：K5 与非 K5 两条重组循环的 from/to 两侧共 4 个外侧分支统一改走该谓词。K5 侧与原内联条件逐字等价（仅收口）；非 K5 侧为行为修正（外侧原子由丢弃改存活）。起始/止容器内的列表项 from/to 处理（选区内单元）未动。
- `rust/apps/web/src/editor.rs`：`model::` 导入清单补 `outside_survives` 一名（按字母序）。

其余路径行为等值：非 Ctrl+A 选区（from/to 恒假）谓词恒真、与旧口径一致；选区内块的处理两路径均未动。

## 三、回归

| 层 | 内容 | 结果 |
|---|---|---|
| 核心层 cargo test | 新增 `outside_survives_tests` 三测（未顶到全留 / 顶到原子全类存活含空列表 / 顶到非原子回假）；`cargo test --workspace` 20 个测试二进制全 ok、零 FAILED | ✓ |
| 静态门禁 | `verify_rustweb.sh` 新增第 17 节：谓词定义恰一处、ops.rs 调用恰 4 点（两路径 × 两侧）、路径自带条件形态（`!from_start \|\| is_atomic_class` 等）零残留；全脚本 **ALL PASS**。负向自检：同口径 grep 打 HEAD 旧版 ops.rs 得调用 0、旧形态残留 1，两锁均可判红 | ✓ |
| DOM 探针（tree） | 修复构建（wasm 戳 d85900ea57）同探针整跑：**42 项 ALL PASS**——K5c/K5d/K5e/K5f 全绿（含「不该变的块没变」完整性口径：存活原子类型序与原位逐项核对、落盘回读），S/K 既有 38 项无回归 | ✓ |
| 告警面 | 本批触碰文件 cargo check 零新增 warning | ✓ |

探针与登记：`tests/probe_slash_anchor.mjs` 夹具增 kb-k5c/kb-k5d/kb-k5e/kb-k5f 四篇、断言增 8 条（文件头注释同步）；`TESTING.md` 第 70 行判据补 K5c–K5f 登记（含尾图/尾画廊因尾随段物化转入选区内、不作外侧判据的口径注记）。

## 四、生产影响面（现网 Web）

- 触发条件：用户在 Web 版编辑器中打开一篇**以原子块开头**（如首块是图片/画廊/卡片）、或**以清单外原子块结尾**（如末块是视频）的备忘，按 Ctrl+A 后执行删除/退格/覆打输入/剪切/回车/粘贴任一替换动作，且选区端点之间没有其他原子块（有则走 K5 路径、本就存活）。
- 数据后果：首/尾原子块被静默删除并随自动保存落盘——图片/视频等附件块本体丢失（附件文件本身不删，但块引用消失，正文内不可见、导出亦缺失）。可经撤销（Ctrl+Z）当场恢复；一旦继续编辑越过撤销窗口或关闭页面，即为实际数据丢失。
- 不受影响：原生 iOS（已按契约实现）；非全选的跨块选区（from/to 为假时旧口径即全留）；端点间含原子的全选（K5 路径）；文末为图片/画廊等清单内原子的备忘（尾随段物化掩盖）。
- 存量：本洞只在上述动作发生时丢块，不做后台数据变更；已部署版本（生产现行构建）仍带洞，待主线安排部署本修复后关闭。

## 五、改动清单（未提交）

- `rust/apps/web/src/editor/model.rs`：+`outside_survives` 谓词与 `outside_survives_tests` 三测。
- `rust/apps/web/src/editor/ops.rs`：两路径 4 个外侧分支收口谓词 + 非 K5 重组注释补契约注记。
- `rust/apps/web/src/editor.rs`：导入清单补一名。
- `scripts/verify_rustweb.sh`：头部登记 + 第 17 节静态锁。
- `tests/probe_slash_anchor.mjs`：K5c–K5f 夹具与断言、文件头注释。
- `TESTING.md`：第 70 行判据登记续补。
- 本报告。
