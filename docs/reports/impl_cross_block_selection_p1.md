# 跨块选区一期落码报告（F-09 桥接层）

定案出处：`plan_cross_block_selection.md` §8.1 一期。范围 = 全选动作面 + 跨块替换（replaceRange）+ 守卫全集，与 Web 多宿主虚拟选区同构。二期（Shift+方向任意端点扩展）与触摸跨块拖选（b2）不在本批。

组版状态：本批动工期间 0.9.60 组版批先行提交（HEAD 至 c5677c3，含 E2/U4b/签名根治与版本 0.9.60/build 87），本批落码未提交、叠在该 HEAD 之上，搭下一版本组版。verify 组号顺延：[49] 已被签名批 SG49-1..3 占用，本批为 **[50] X50-1..7**。

## 一、落点清单

### 新文件（按规范独立成文件，不塞上帝文件）

| 文件 | 内容 |
|---|---|
| `rust/apps/ios/app/MomentXSel.swift`（320 行） | 纯核心，Foundation-only：`XSel`/`XSelPos`/`XSelUnitInfo` 值类型 + `XSelCore`——`runText/runsText/runsUTF16Length/textRun`、`utf16Index`（标量对齐：落标量内进到其后）、`utf16Slice`、`splitRuns`（逐支同构 ops.rs `split_inlines_at`，段内劈分保留标记键含 `_link`）、`ordered`（端点消失返回 nil）、`guardSpan`（逐支同构 Web `guardSpan`）、`selectedText`（`\n\n` 连接）、`plainResultColumns`、`k5SegmentColumns`。可独立宿主编译做表驱动（X50-2）。 |
| `rust/apps/ios/app/MomentXSelBridge.swift`（478 行） | 桥接层：`XSelUnit` + `EditorModel` 扩展全集——`xselUnits`（Web `editable_units` 口径：顶层文本块 + 顶层列表直属项，嵌套项不入；与既有递归口径 `textUnits` 分工并注明）、`xselIsAtomicTop`、`isXSelSourceBlock`（原生源码态只有 codeBlock）、`setXSel`（`whole==nil` 才过 guardSpan，钳后重合归 nil）、`selectAllXSel`、`clearXSel`、`collapseXSel`（焦点端）/`collapseXSel(toOrderedStart:)`、`placeXSelCaret`、`xselClipboardText`、`cutXSelText`、`replaceXSel`、`noteXSelNativeSelection`、`xselRowCovered`、`replaceRangeUnits`（双路径逐支移植 ops.rs `op_replace_range`）+ 私有助手 `applyXSelRuns`/`newXSelBlock`（新块 id 沿既有 `"b-"+UUID 前 8 小写` 惯例）。 |

### MomentApp.swift 接线（与 E2/U4b hunk 全 disjoint，动工前已逐段映射核对）

- `EditorModel`：`editingBlockId` 后新增 `@Published var xsel: XSel?`（选区状态单点，全仓恰一处声明，X50-1 锁）。
- `T` 令牌：`accent` 后新增 `xselHighlight = dynA(0x0069D9, 0.30, 0x0069D9, 0.30)`（色值走令牌不写裸值，X50-6 锁）。
- `handleKey`：命令支插在 E2 的 Cmd+Z 块**之前**——xsel 在位时 A/C/X 消费；Z/Y 及其余 Cmd 先 `clearXSel` 再放行落入 E2 支（与 Web「修饰键清选后放行」同构，E2 行零改动）。斜杠支后新增 xsel 动作支：Delete/Enter/Esc/无修饰方向键收拢消费、Shift+方向收拢后放行（return false，二期扩展的挂点）、单字符覆打（控制符排除）、余键收拢放行、marked 在位整面让路。
- `EditorTextView`：`paste()` 前置 xsel 分流（纯文本优先于图片、无文本清选走常规）；新增 `copy`/`cut`/`selectAll`/`canPerformAction` 覆写（xsel 在位时菜单给复制/剪切；selectAll 源码块守卫走 `isXSelSourceBlock`；全仓无程序化 selectAll 调用方，已 grep 核）。
- `Coordinator`：`shouldChangeTextIn` 在 marked 守卫后、块内流程前加 xsel 支（`"\n"` → enter 替换、余皆整段替换、恒 return false，且不喂 E2 爆发检查点——替换自带单次 pushHistory）；`handlePaste` 的 xsel 支先于 listParent 守卫（锚为列表项亦可替换）；`textViewDidChange` 的组字判定点挂 `collapseXSel()`（与 E1 组字守卫同一点，不另起守卫；原一行 guard 形态保持不动，见 §五教训）；新增 `textViewDidChangeSelection` 做失效对账，**置于 textViewDidChange 之后**（位置有断言约束，见 §五）。
- `BlockRow`：`.background(rowBackground, …)` 前插 xsel 背景层（圆角 quote 取 `Radius.quote` 余 `Radius.block`、`.fill(T.xselHighlight)`、层序与判定单点注释在位）。
- `shiftListStart`：`private` 去除改内部级（一词改 + 注释注明跨文件共用单点），`replaceRangeUnits` 复用之，不另写 start 修正。

### build-app2.sh 接线（纯行插入，101 行、0 删除，diff 已复核）

每个 plain 输入名单后补两新文件（各 25 遍输入）；新增 xsel / xsel_bridge 两 primary 遍（各以 `-primary-file` 出 `xsel.o`/`xsel_bridge.o`，primary 文件不入 plain 名单——E2 教训口径）；主链接行补两 .o。实测登记数：MomentXSel.swift 26、MomentXSelBridge.swift 26、xsel.o 2、xsel_bridge.o 2（X50-7 锁）。

### verify_ios.sh

- 新增 [50] 组 X50-1..7（见 §四）。
- 连带改锚（期望合法变更，注释留沿革，同 J20-12 先例）：DT46-6 的 MomentFontFactory 构建登记 23 → 25、E47-8 的 MomentUndo 登记 24 → 26，均因新增两 primary 遍，落笔时按实测复核。

## 二、Web 实证对账表

落码前逐项回 Web 源码核对原值（不凭方案转述）：`editor.js` xsel 全段（370–905）、粘贴支（1714–1719）；`ops.rs` `op_replace_range` 全文（617–1010）；`model.rs` 助手（`split_inlines_at`/`editable_units`/`is_atomic_class`/`shift_list_start`/`plain_len`）。

| 项 | Web 实证 | 原生落法 | 等值性 |
|---|---|---|---|
| 选区模型 | `{a, f, fromStart, toEnd}`，端点 = 单元 id + UTF-16 偏移 | `XSel{anchorId, anchorOff, focusId, focusOff, fromStart, toEnd}`，偏移恒 UTF-16 | 同构 |
| 光标回落口径 | DOM selection 本身 UTF-16 | 投递经既有焦点面时以 `EditorModel.charOffset` 单点换算为字符口径（与 E2 选区恢复同链） | 行为等价 |
| 高亮 | `rgba(0,105,217,0.30)` 段内分段着色 | 一期端点恒全文首尾、覆盖内无段内分段 → 行级整行着色即精确；色值入 `T.xselHighlight` 令牌 | 一期等值；段内分段着色留二期 |
| guardSpan | 选区跨源码块时焦点钳到锚侧邻界 | `XSelCore.guardSpan` 逐支移植（含反向钳到锚侧边一支） | 同构（表驱动 4 支全过） |
| xselText | 单元切片以 `\n\n` 连接 | `selectedText` 同 | 同构 |
| replaceRange 双路径 | K5（首尾同顶层容器）分段保型；普通路径结果列保起始单元类型；列表 `start` 的 E-17 修正双路径各一份 | `plainResultColumns`/`k5SegmentColumns` 纯函数 + `replaceRangeUnits` 双路径逐支移植；start 修正复用既有 `shiftListStart` 单点（4 调用点 = 双路径首尾容器各一） | 同构 |
| Diag | `EDIT replace range {a}@{off}..{f}@{off} ins={字节}B enter={}`（日志用未排序原始端点）、K5 追加 ` atoms kept={n}` | 同格式同口径（含原始端点） | 同构 |
| 落盘/撤销 | 先清选后调 op（`sendReplace`） | `replaceXSel` 先清选后 op；`pushHistory()` 恰一次（单个撤销步，X50-5 锁）+ `scheduleSave`，与原生 op 惯例一致 | 行为等价 |
| 结果块字段 | 结果列保起始单元类型 | 字段清理由结果列保型天然满足，E3 `clearTypeFields` 口径不冲突，未另写 | 等值 |
| 组字 | `compositionstart` 收拢到焦点端 | 挂 `textViewDidChange` 组字判定点 `collapseXSel()` | 同位同构 |
| 失效对账 | `selectionchange` 对账清选 | `textViewDidChangeSelection` → `noteXSelNativeSelection`（marked 先收拢；length>0 或落点≠锚点清选）；`applySnapshot` 未改（在 E2 hunk 区内）——撤销后 restoreSelection 的落点投递必触发 didChangeSelection 离锚清选，与 Web 同果；动作/呈现面另有端点存在性惰性校验兜底 | 同果 |
| 菜单面 | 编辑菜单给复制/剪切 | UIKit 正道：`EditorTextView` 覆写 copy/cut/selectAll/canPerformAction | 平台正道、行为等值 |
| 粘贴替换 | 粘贴支 1714–1719 先清选替换 | `paste()` 前置分流 + `Coordinator.handlePaste` xsel 支（先于 listParent 守卫） | 同构 |

### 分叉裁定（须点名）：非 K5 路径外侧原子存活

Web 非 K5 路径在 `from_start`/`to_end` 时丢弃选区外侧全部块（含原子块），与 ops.rs:612 注释契约（「选区内及 Ctrl+A 首尾外侧的原子块全程存活」）及方案 §1.5 冲突。外侧块恒为原子类（非空列表的项必是单元、其顶层位必在区间内），故分叉只落在边缘原子（如文档首/尾是图片时 Ctrl+A+删除）。代码级 proven 的 Web 疑似边角洞。**裁定：原生双路径统一按契约保外侧原子**（行为等价底线 + 不复制数据丢失）；建议 Web 侧另行核修，本批不越界改 Web。

## 三、proven 上限分级

| 面 | 级别 | 依据 |
|---|---|---|
| 纯核心行为（劈分/排序/钳制/选区文本/双路径结果列） | **proven** | 表驱动 25 项检查全过（本机宿主 swiftc 实跑 + X50-2 内嵌同体）；首跑唯一 FAIL 为测试期望写反（guardSpan 反向应为锚侧边，与 Web 代码一致、移植无误），改期望后全绿——期望错、代码对，已留账 |
| 三个 primary 遍类型检查（xsel/xsel_bridge/app） | **proven** | 本机工具链 swift-frontend 逐遍实跑零 error（app 遍两处实错已修：HID 名 `keyboardDeleteOrBackspace`、SDK 中 `UIKey.characters` 非可选） |
| 接线/守卫/单步撤销/构建登记 | 构建期断言锁 | X50-1/3/4/5/6/7 + 全量 verify 524 ✓（见 §四） |
| 触摸菜单呈现、Cmd 物理投递、选区高亮像素、组字实机会话 | **unknown** | 无真机/实机会话证据，按纪律如实标，归真机终判（§六） |

## 四、verify 结果

本机全量 `verify_ios.sh`：**524 ✓ / 2 红**。红项为既有产物红（ipa 陈旧、产物语言包与 Web 源不一致），均待下一次构建消解，非本批引入。本批 X50-1..7 全绿；签名批 SG49-1..3 全绿；DT46-6/E47-8 改锚后绿。

过程中 E43-1 一度转红并已根治（见 §五），复跑绿。

## 五、本批教训（即时沉淀）

- **新委托方法命名会污染既有段提取锚**：verify 多处以 awk `/func textViewDidChange/` 取段，新增的 `textViewDidChangeSelection` 因同前缀成为首匹配，段提取截到错误函数、E43-1 误红。根治 = 新方法置于被取段函数之后（委托方法顺序自由），既有断言零改动。通则：新增方法若与既有函数同前缀，先查 verify 是否有按名取段/计数的锚，再定落点。
- **既有断言锁定的字面形态不可顺手重构**：E43 的顺序锁以单行 `guard tv.markedTextRange == nil else { return }` 为锚；组字收拢改为 guard 前 `if marked != nil { collapse }` 的等价形态挂同一点，字面锚不动。

## 六、真机终判点

1. Cmd+A 全选呈现与行高亮（行级着色与 Web 观感对照）。
2. 外接键盘 Cmd+C/X/V、方向键收拢、Esc 收拢。
3. 触摸菜单：全选/复制/剪切项的出现与生效。
4. 软件键盘：覆打、退格、回车三动作对跨块选区的替换。
5. 拼音组字：组字开始即收拢、落字只进焦点端块、不经 replaceRange。
6. 跨原子全选删除后原子存活（§二分叉裁定的实机面）。
7. 列表 start 显示号在双路径替换后正确（E-17 修正面）。
8. 撤销一次整段回退（单步性）。

## 七、待二期项

- Shift+方向任意端点扩展（`setXSel` 的 guardSpan 入口已备；handleKey Shift+方向现收拢后放行，挂点在位）。
- 段内分段着色（端点可落段内后行级着色不再精确）。
- Esc 与页级 Esc 链的先后未实证（一期 handleKey 内先行消费，待实机核）。
- 自检覆盖矩阵 EDT 增补行建议（矩阵文件有并发改动，本批不碰，留组版批回写）：`EDT-15 | 编辑 | 跨块选区一期：全选→替换/删除/粘贴替换 单步撤销 + 外侧原子存活 + 列表 start | 未覆盖（场景 xsel_replace_roundtrip 待立，依赖 §六真机终判）`。

## 八、组版注记

- **tree-sync/push_small.py 名单须补 `MomentXSel.swift` 与 `MomentXSelBridge.swift` 两件**（与 MomentUndo.swift 同批补入）。
- 本批未提交、未 bump；HEAD 已是 0.9.60/build 87（组版批先行），本批搭下一版本。
- tree 的 `~/ios-native/bin/macho-entitle` 同步新版的组版铁律（签名批定）与本批无关但同版生效，组版时勿漏。
