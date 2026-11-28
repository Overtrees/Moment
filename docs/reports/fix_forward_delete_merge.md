# AUD-B-05 落码：编辑器块末前向删除与下一块合并

用户 2026-11-28 裁定：做，与退格合并对称，两端一致。未提交，留主线组 0.9.63。

## 一、退格侧规格（回源提取，两端）

**触发**：原生 = `BlockTextView.Coordinator.shouldChangeTextIn` 的 `(0,0)+""` 空变更支（段首退格）→ `mergeBlockBackward` / `mergeListItemBackward(listParent)`；Web = editor.js keydown `Backspace` + 折叠光标 offset 0 → op `merge` → `op_merge`（目标分类 `prev_sibling`：紧邻关系为准，原子块不跳过——仅空块支向前跳过全部连续原子块）。

**不变量（两端共有）**：内容恒并入较早的存活单元、光标落接合处；存活单元的类型不变；原子块永不被键盘删除（非空撞原子 = 只带入选中态，删卡走卡菜单）；合并为单个撤销单元（原生每条落变路径恰一 `pushHistory()`；Web 消息级快照、非 coalesce 类）；合并后走既有落盘尾（原生 `scheduleSave()`、Web `persist`）+ 智能前缀尾扫（原生 `applySmartPrefixIfNeeded()`、Web dispatch 尾名单含 `merge`）。

**Web 原状定性（B-05 的 unknown 部分，本批回源关账）**：Web 无前向删除行为——每块独立 contenteditable，Delete 在块末无原生动作，keydown 处理器无 Delete 支（XSel 支的 Delete 走 replaceRange、选中原子块的全局支对 Delete 是无操作守卫，均非块末合并）。原生同：`keyboardDeleteForward` 此前仅 XSel 接管支出现，块末前向删除无动作。

## 二、对称规则表（退格 → 前向）

| 场景 | 退格（既有） | 前向删除（本批） |
|---|---|---|
| 文本块 + 相邻文本块 | 当前块 runs 并入上一块，删当前块，落点 = 上一块接合处 | 下一块 runs 并入当前块，删下一块，落点 = 当前块接合处（光标原位） |
| 相邻为列表 | 并入列表**末项**；当前块删 | 列表**首项**并入当前块；删首项，存续首项原号不变 → start +1；表空删表 |
| 当前块为空 | 删空块、向前跳过原子块落最近文本块**末尾**；无目标保留空块 | 删空块、向后跳过原子块（与列表）落最近文本块**块首**；无目标保留空块（Diag kept 行） |
| 非空 + 相邻原子块 | 不删原子块，只带入选中态，两块全保留 | 同左（镜像） |
| 列表项 · 表内 | 并入上一项 / 空项删项 | 并入下一项 / 空项删项落下一项块首 |
| 列表项 · 边界项 | 首项按列表**前**一块分类（文本并入前块 / 原子选中 / 空首项向前跳原子落文本块末尾、无目标整表转空段） | 末项按列表**后**一块分类（文本并入项内 / 列表取其首项 / 原子选中 / 空末项向后跳原子落文本块块首、无目标整表转空段） |
| 音乐输入胶囊（仅 Web 有此面） | 段首退格只移焦点回上一单元末尾、不删不并（K4） | 块末 Delete 只移焦点到下一单元块首、不删不并（`musicFocusNext`，K4 镜像） |

接合点口径：原生 = 字符数（`text.count`，与退格侧同）；Web = UTF-16 码元（`plain_len` 同口径，MERGE1 教训，核心以活 DOM inlines 计长、宿主测试含 emoji 用例锁）。

落盘形态：与退格合并产出同构——存活单元 children/runs = 前段 + 后段直接拼接，被并单元整节点摘除，列表 start 维护走同一助手（原生 `shiftListStart`、Web `shift_list_start`，均仅编号表生效）。

## 三、守卫清单

- **触发守卫（原生）**：delegate 支须空变更 + `range.location == tv.text` 全长 + `location > 0`（空块在 delegate 面与退格不可分，归按键面）；按键面须 `.keyboardDeleteForward` + 无修饰（Shift/Ctrl/Alt/Cmd 放行）+ 非组字（markedTextRange 为 nil）+ 折叠光标落块末。两面均加 `slashBlockId == nil`（斜杠面板在位不并块——退格侧因 token 几何天然不可达，前向可达故显式守卫）。XSel 在位时按键先行走既有 replaceXSel 支，不入本路。
- **触发守卫（Web）**：折叠光标 + `textAfterCaret(el) === ''`（既有块末判定助手，与跨块方向键同口径）；块内有后文放行原生删下一字。codeBlock/mdsrc 支与通用支同判；XSel 支、选中原子块全局支先行不变。
- **原子守卫**：图片/图库/视频/卡片/分割线等不可编辑块（含空列表）永不被前向删除摘除或并入；非空撞原子只选中（原生 Diag `EDIT merge fwd before atomic … selected (kept)`，Web `mergeForward: delete before atomic … selected (kept)`）。
- **撤销粒度**：原生两函数每条落变路径恰一检查点（verify [58] FD58-3 普查锁：顶层 3、列表项 5）；Web `mergeForward` 与 `merge` 同为消息级单快照（dispatch 分类未加 coalesce）。
- **md 源码编辑态（Web）**：被并掉的下一块若正处 md 源码编辑态，其块已消失，dispatch 臂按存亡核对清 `md_edit`（`merge` 臂对 bid 清理的同口径推广）。

## 四、落码清单

**原生（MomentApp.swift）**
- `mergeBlockForward(_:)`：顶层前向合并（空支/文本支/列表首项支/原子支四路，单尾 `scheduleSave` + 智能前缀尾扫）。
- `mergeListItemForward(list:item:)`：表内支（空项/并入下一项）+ 末项支（按下一顶层块分类，空末项收敛一尾）。
- `nearestTextBlock(after:)`：`nearestTextBlock(before:)` 的镜像（跳原子块与列表）。
- 触发：`shouldChangeTextIn` 块末空变更支（紧随段首退格支）；`handleKey` 硬件 Delete 支 + `mergeForwardFromKey(blockId:)` 入口（按 id 定位顶层块/列表项，`findItem` 含嵌套子表）。

**Web**
- `editor/ops.rs`：`next_sibling`（`prev_sibling` 镜像分类）+ `merge_forward_core`（纯核心，文档改动全量在此，宿主可测；新块经注入工厂）+ `op_merge_forward`（信号投递 wrapper）。
- `editor/dispatch.rs`：`mergeForward` 臂（+ md_edit 存亡清理）、`musicFocusNext` 臂、智能前缀尾扫名单加 `mergeForward`。
- `editor/js/editor.js`：通用支、codeBlock/mdsrc 支发 `mergeForward`；音乐胶囊支发 `musicFocusNext`。
- `editor.rs`：ops 导入表加 `op_merge_forward`。

**断言/测试**
- Web 宿主测试 `merge_forward_tests` 9 例（cargo test --workspace 全过）：next_sibling 分类矩阵；核心块型矩阵（文本/标题存活、列表首项 + start、表空删表、原子选中、空块三形、表内三形、空末项两形、末块无动作）；完整性断言以全量文档 id/文本相等与未涉块逐字不变（`assert_eq!(d, before)`）锁存量不串改；emoji 接合点 UTF-16 用例。
- verify_rustweb 新增 §18 静态锁（纯核心/分类单点/双发送面/分发臂/尾扫名单），全脚本 ALL PASS。
- verify_ios 新增 [58] FD58-1..5（定义单点/触发两面/检查点普查/原子守卫/Diag 谱系）；连带沿革：[43] E43-2 智能前缀尾扫调用点普查 7 → 11（本批 +4，注释已注）。本机 verify_ios 本批断言全过；其余红为既有产物红（ipa/语言包待 tree 构建）与状态栏二轮批在途的构建接线普查漂移（DT46-6/E47-8/X50-7/SB-5/SB-2，非本批文件面，组版时由各批统一回写）。

## 五、有意的不完全镜像（逐项明示）

1. **原生退格空项落点怪癖未复制**：退格删表内空项后落点为「顶替项的末尾」（末项时即上一项末尾、表中时为下一项末尾）；前向按几何一致性落「顶替项（下一项）的块首」——光标在删除点原地不动，符合前向删除的落点语义。退格侧既有行为未动。
2. **Web 退格「空块 + 前为列表」与原生退格口径分叉（既有，未动）**：Web `op_merge` 空支仅在前为原子块时走跳块，空块前为列表时经 Text 支并入末项；原生退格空支一律跳过列表找最近文本块。前向两端统一按原生口径（空支跳过列表）。Web 退格该支不在本批范围，登记为既有分叉待后续裁。
3. **原生空块 Diag**：退格侧空块居首块时 guard 静默无行；前向空块居末块（或后无文本块）有 kept Diag 行（与退格「有原子在前」时的 kept 行同式），取可诊断性。
4. **原生音乐胶囊无对应项（proven）**：原生胶囊为 SwiftUI `TextField`（MusicPillView），不经 BlockTextView 协调器，退格侧亦无收口支；Web 的 `musicFocusNext` 只对 Web 胶囊面成立，两端行为面等价（原生胶囊两方向均无操作）。

## 六、真机终判点

- 硬件键盘 Delete：段落/标题/待办/引用/callout/代码块块末 → 与下一块合并、光标停接合处、撤销一次整回退；列表项各位置（表内/末项/空项各形）；下一块为图片/图库/视频/分割线时只选中不删；空块块末跳过原子块落后续文本块块首；末块块末无动作；拼音组字中 Delete 不触发合并；斜杠面板打开时 Delete 不并块。
- Web（桌面浏览器）同场景一遍；音乐胶囊块末 Delete 只移焦点。
- 存量完整性：含原子块与列表的长备忘逐场景操作后，其余块内容/顺序/编号逐一不变（宿主测试已锁核心层，终判看落盘后重进结果）。
