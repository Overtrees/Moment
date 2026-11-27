# 附件行宽屏圆角恢复 22——小批根治报告

时间：2026-11-27。对象：原生 iOS `MomentApp.swift` 的附件文件行（`AttachmentRow`）与附件拾起面（`BlockRow.attachmentLiftFace`）。基线 HEAD ec4105c（0.9.54），本批落码未提交、未 bump。

## 一、定因（已坐实，本批只执行）

0.9.52 圆角批 S1 裁断称「Web .attachment-file 恒 32、宽屏 22 缺 Web 实据」，把附件行面与拾起面统一为 cardL=32。0.9.54 组版 S1 复核回 Web 源码实证推翻该依据（release_0.9.54.md 第四节）：

- 基础规则 editor.css:428 `.editor-body .attachment-file`：radius-32、padding 16/20、gap 10，特异性 (0,2,0)。
- 宽屏规则 editor.css:726 `.editor-spread > .editor-body .attachment-file { border-radius: var(--radius-22); padding: 12px 14px; gap: 8px }`，特异性 (0,3,0) 且位置在后——宽屏 spread 形态下 Web 计算值确为 22。
- 原生宽屏 padding（12/14）与 gap（8）此前已按该规则对齐，唯半径被 S1 统一成 32。本批把半径恢复 Web 口径；S1 裁断的另一半（行面与拾起面同值）仍然有效——两面统一，只是数值随宽屏条件派生。

## 二、媒体条件全集与原生判定对齐表

宽屏规则所在段的完整触发条件逐项核过（editor.css:681 段首，全文件同式共 6 处 @media 均为同一串）：

| # | Web 侧条件/事实 | 出处 | 原生对应 | 对齐结论 |
|---|---|---|---|---|
| 1 | `(min-width: 768px) and (min-height: 600px)`：宽 ≥768 **且** 高 ≥600（合取，含 min-height 一维） | editor.css:681 | `EditorView.syncWide`：`size.width >= 768 && size.height >= 600` | ✓ 逐项一致 |
| 2 | `, (min-width: 1100px)`：或宽 ≥1100（析取，此支无高度条件） | editor.css:681 | syncWide：`\|\| size.width >= 1100` | ✓ 逐项一致 |
| 3 | `.editor-spread` 类恒挂编辑器根（非条件开关），媒体条件是唯一门 | editor.rs:792 `class: "editor-pad editor-spread"` | 原生编辑页恒在，无对应开关 | ✓ 无额外门 |
| 4 | Web JS 宽屏信号用同一 matchMedia 串驱动双栏状态 | editor/hooks/columns.rs:61 | 原生 `columnsActive` 与 `ui.wide` 由 syncWide 单点以同一公式喂入（全文件仅此一处赋值） | ✓ 单点同式 |
| 5 | 横屏例外段（landscape 且 max-height 560 且 max-width 1099 → column-count 1）与宽屏条件互斥（560<600、1099<1100 两维都进不了），且该段只动栏数、不动半径 | editor.css:672 | 无需对应：该形态下宽屏条件本身不成立，原生同判 false | ✓ 无交互 |
| 6 | 独立滚动 / 流式两变体段对 `.attachment-file` 只设 break-inside，不覆盖半径——同样吃 726 的 22 | editor.css:1020/1090 附近 | 原生两模式共用同一 `AttachmentRow` 与同一派生 | ✓ 同口径 |
| 7 | 宽屏段对附件图片（`.atomic.attachment:has(> img)`）只有 break-inside，图片半径恒 32 不变值 | editor.css:705 | 原生单图附件面恒 cardL、不经条件派生 | ✓ 不变 |

结论：原生「宽屏」判定不存在只按宽度近似的问题——`syncWide` 一处以与 Web 逐字同构的公式（含 min-height 合取与 1100 析取）计算，`AttachmentRow` 经 `editor.columnsActive` 消费，本批半径派生挂同一信号。

## 三、改动清单（仅 MomentApp.swift + verify_ios.sh）

1. **Radius 单源新增条件派生**（enum Radius，既有 concentric/lift 之后）：
   `static func attachmentFile(wide: Bool) -> CGFloat { wide ? cardS : cardL }`——全文件唯一的宽屏半径数值来源（22/32 仍只存在于 cardS/cardL 令牌本体），注释钉死 Web 出处与两面共用口径。
2. **行面**：`AttachmentRow` 的 `.contentCard(radius: Radius.cardL)` → `.contentCard(radius: Radius.attachmentFile(wide: wide))`；`wide` 参数注释改写（删去已被推翻的 S1「恒 32」表述，改为 726 级联实证口径）。两个调用点（附件块文件行、音乐卡 fileId 文件行）本就传 `wide: editor.columnsActive`，随之同值。padding/gap 未动（已对齐）。
3. **拾起面**：`BlockRow.attachmentLiftFace` 文件行分支 `return Radius.cardL` → `return Radius.attachmentFile(wide: editor.columnsActive)`；单图分支恒 cardL 不动（对齐表第 7 项）。该 helper 同时是音乐卡/链接卡 fileId 态的拾起面来源——两类卡带 fileId 时呈现本体即 `AttachmentRow`（CardBlockView 首分支），故框面自动同源。拾起框本体仍由 `LiftFrame` 经 `Radius.lift(face:)` 同心外扩派生，自动跟随。
4. 半径令牌注释无需改：`Radius.cardS` 注释本就含「附件文件行宽屏态」、cardL 含「文件行常态」——0.9.52 令牌语义原本正确，错的只是消费点被 S1 统一。

## 四、断言清单（verify [21] R21-9 改写）

R21-9 由「附件行半径恒 cardL」改写为条件派生口径，锁机制不锁裸数值：

- 派生本体在位：`static func attachmentFile(wide: Bool)` 存在，且 `wide ? cardS : cardL` 全文件**仅一处**（唯一入口，防第二处数值源回潮）；
- 行面走派生：AttachmentRow 段含 `contentCard(radius: Radius.attachmentFile(wide: wide))`，且段内 `contentCard(radius: Radius.cardL)` 零残留；
- 拾起面同源：liftFaceRadius 段（含 attachmentLiftFace）含 `Radius.attachmentFile(` 与 `wide: editor.columnsActive`；
- 图片面不经派生：同段 `if isImage && fileCount == 1 { return Radius.cardL }` 在位；
- 调用点禁裸三元：`contentCard(radius: wide` 零残留（旧防线保留）；
- 原 R21-9 的行面/描边两项（quote/block 三元、卡编辑描边 cardS/cardL 三元）原样保留。

本机自跑：全量 210 项 ✓；仅 2 项 ✗，均为 ipa 陈旧类（「ipa 陈旧（早于 MomentApp.swift）」「产物语言包缺失或与 Web 源不一致」——本机 build 产物早于本次源码改动，tree 重新构建后自解，非本批断言）。[21] 其余各组、[22][23][24] 未受影响。

## 五、真机终判点

1. **宽屏**（iPad 或 iPhone 横屏达宽屏条件：宽 ≥768 且高 ≥600，或宽 ≥1100）打开含文件附件的笔记：附件文件行圆角应为 22，与 Web 宽屏同位对照（同篇在 Web 宽屏打开比对）；同行的音乐文件行（音频附件）同为 22。
2. 宽屏下长按拾起附件文件行：玻璃框与行面同心（框半径 = 面 22 + 4 外扩），四边间隙等距、无圆角不配。
3. **窄屏**回归：附件行圆角仍为 32、拾起框同心，与 0.9.54 及以前一致（本批零改动面）。
4. 宽屏下单图附件：图片圆角仍为 32（不变值），不随文件行变 22。
5. 宽窄切换（旋转/分屏拖动跨过 768/600 或 1100 界）时附件行圆角随条件即时切换、无残留态。
