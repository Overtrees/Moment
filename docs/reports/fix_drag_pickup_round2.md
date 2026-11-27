# 拖拽拾起第二轮全链定因与根治（0.9.47）

背景：0.9.36 定因「长按 require(toFail: pan)、静止手指下 pan 永不判失败、拾起永不发生」，修法为删 require + 拾起锁滚动 + 补 Web 拾起框/双轴缩放，当时记为代码级 proven。2026-11-27 用户真机裁定依旧拾不起。本轮按「上次结论已被推翻」处理：先复核 0.9.36 落码本身，再通读现行全链，最后按 Web 压引擎形态整体替换仲裁结构。落码已完成（未提交、未构建），版本号 0.9.47 / build 74。

## 一、0.9.36 结论复核

| 0.9.36 的说法 | 复核结果 | 证据 |
|---|---|---|
| require(toFail: pan) 使拾起永不触发 | **成立（对旧代码）** | 提交 1e24756 的 diff 逐行核：确有删除行 `lp.require(toFail: sv.panGestureRecognizer)`；其引入提交 42f97c4（0.9.14）亦核 |
| 修复已落：删 require、拾起锁滚动、attach 打点 | **落码属实、与现行代码一致** | 现行 DragPickupInstaller 全文通读：无任何 require；`handle` 的 .began 内 `isScrollEnabled = false`、ended/cancelled/failed 恢复；attach 成功有 `DRAG installer attached` 行 |
| 该定因即全因、修复即根治 | **被真机推翻** | 0.9.36 之后各批（0.9.37–0.9.46）无一改动 installer 本体（git -S 仅 42f97c4 与 1e24756 两笔触及），而真机依旧全无拾起——说明至少还有一层拦截在 require 之外，且 0.9.36 的「proven」只是代码级自洽、从未有真机正证据（0.9.36 后的 Diag 导出缺失，端内无一次 pickup 留痕可查） |

附带证据一条：2026-11-26 17:11 的 Diag 导出（≤0.9.35 构建、require 尚在）中有一行 `DRAG pickup id=… type=imgTextCard`——旧路在卡片块上曾触发过恰一次。说明命中换算（锚点 bounds → 滚动视图坐标）本身可用，失效不是坐标数学全错，而更像仲裁在多数触点上被他人赢走、偶发漏过一次。

## 二、全链关口表（现行代码逐关口）

| # | 关口 | 现行形态 | 可能拦死点 + 代码证据 |
|---|---|---|---|
| 1 | 识别器安装 | 每行一个 DragPickupInstaller（UIViewRepresentable），updateUIView 时走祖先链找第一个 UIScrollView、把自己的 UILongPressGestureRecognizer 挂上去 | ① 找不到滚动视图时 `guard let sv else { return }` **静默返回、无任何留痕**——装没装上端内不可知；② 每行一枚识别器，同一滚动视图上叠 N 枚同型长按，仲裁面随行数放大 |
| 2 | 命中过滤 | delegate `shouldReceive`：锚点视图 bounds 换算到滚动视图坐标系、与触点同系比对 | 换算口径与旧路唯一一次真机 pickup 同源，可用性有据；但每枚识别器只认自己行，N 枚并行判定 |
| 3 | 武装判定 | `dragAllowed`：卡片类恒 false；正在编辑的文本块 false；余 true | 口径与 Web 一致（编辑中文本块长按 = 选择），非病灶；但卡片类因此**整体不可拖**（见关口 5） |
| 4 | 行级竞争消费者（非卡行） | 每行 `rowMain.contextMenu { … }`（类型转换七项 + 删除块） | **UIContextMenuInteraction 自带行级长按识别，与拾起同抢一个 480ms 触点**——这是 0.9.36 之后仍在场的、与 require 同级的结构性竞争者，第一轮排查未入账 |
| 5 | 行级竞争消费者（卡片行） | CardMenuGesture：SwiftUI `onLongPressGesture(0.48)` 出贴卡菜单；同时 dragAllowed=false | 卡片行长按被菜单独占（0.9.19 的原生取舍）；Web 口径下卡片可拖且菜单骑拾起——原生此面与 Web 分叉 |
| 6 | 文本块触点落点 | 文本块常驻 BlockTextView（UITextView 可编辑、isScrollEnabled=false），MD 预览段为 MdTextGroupView（UITextView） | UITextView 内部选区长按识别（约 0.5s）与拾起长按（0.48s）同触点赛跑，时差仅约 20ms，仲裁在平台内部、不可控 |
| 7 | 滚动视图 pan | SwiftUI ScrollView 的 pan，无 require 关系（0.9.36 后） | 静止手指下 pan 不 began，本关口不拦；拾起后靠锁滚动让行——此环 0.9.36 后形态正确 |
| 8 | J1 落焦热区（0.9.44） | 编辑区背景/热区的 `.onTapGesture` 落焦（focusHotZone 等） | tap 手势在触摸抬起才裁决，不拦截长按序列；逐处核过，**排除** |
| 9 | 静止期视图重建 | 480ms 内 rows 是否被 dismantle | 编辑器打开后状态变化频繁走 updateUIView（无害、attach 幂等）；行身份由 BlockState 对象恒定，ForEach 不重建行；静止长按期间无定时器/回刷源可打断识别器（逐项查过保存防抖、选区发布、高度回报——均由用户动作驱动）。**无证据，列 unknown 尾部** |
| 10 | 拾起后状态机 | onPickup 置 draggingId → 框（LiftFrame）/双轴缩放/震动；onDrag 跟指；commitDrag 落位 + settle 弹簧 | 呈现与数值规格齐备（拾起框/缩放规格已按 Web 对齐）；从未被触发过，无从证伪——死点在拾起之前，与「震动/缩放/框全无」的现象自洽 |

## 三、新定因（证据分级）

- **主因（结构 proven / 单点归因 inferred）**：拾起的仲裁结构本身——「祖先滚动视图上的每行一枚 UIKit 长按」是最弱 claimant，与行级 UIContextMenuInteraction（非卡行）、SwiftUI 长按（卡片行）、UITextView 内部选区识别（文本行）三方同触点竞争，全部仲裁都在平台内部、无显式接法。0.9.36 只拆了其中 require 一环，其余竞争面原样保留，真机结果与「拾起信号从未到达状态机」完全自洽（pickup 后的震动/框/缩放同灭、代码通读无误、旧路偶发成功一次）。三方中谁是决定性赢家无法从代码单独指认（平台仲裁不可见），故单点归因标 inferred；「竞争面不清空则不可靠」这一结构判断为 proven 级处置依据。
- **次因（proven）**：留痕缺口——attach 失败静默、shouldReceive 的拒绝无痕、识别器 failed 无痕，导致两轮真机失败都拿不到端内定位证据，只能靠现象倒推。本轮已按关口补齐（见五）。
- **排除项**：require 回潮（无）、锁滚动缺位（在）、命中换算全错（旧路成功过一次）、J1 热区拦截（tap 不拦长按）、编辑器滚动卡死（另一条战线，不在本轮范围）。

## 四、根治落点（子系统替换，旧路整段删除）

按 Web 压引擎形态重构（editor.js：单一 pointerdown 引擎全程所有按压序列、菜单骑拾起、类型转换不占长按）：

1. **单引擎单识别器**（新文件 `MomentDrag.swift`，按 0.9.45 拆分纪律独立成文件）：
   - `DragPressEngine`：每滚动视图一个（关联对象挂宿主 UIScrollView），全程恰一枚 UILongPressGestureRecognizer（0.48s / allowableMovement 10 / cancelsTouchesInView=false，与旧口径一致）。
   - 与 pan 的关系改 require 的**正向接法**：delegate `shouldRecognizeSimultaneouslyWith` 对宿主 pan 返回 true——pan 不再能取消本识别器；滚动让行靠拾起即锁 `isScrollEnabled`（保留），手指先移动 >10pt 则识别器自然失败、滚动零延迟（与 Web 触屏按压 >10px 取消同构）。
   - `DragPressAnchor`（后继锚点）：行只注册（命中视图 + 武装判定 + 四回调），自身不持识别器；注册随每次 update 刷新、滚动视图变更先注销再注册、拾起中被卸载按取消收尾。attach 找不到滚动视图时不再静默：logOnce 警告 + 主队列重试一次。
   - 命中过滤沿用已证换算；新增 Web 同口径排除：触点落在 UIButton 子视图上不武装。
   - 旧 `DragPickupInstaller` 定义与调用**整段删除**（代码行零残留，verify J14-2 锁），无兼容层。
2. **行级竞争清零**：
   - 删除 BlockRow 的 `.contextMenu`（关口 4）。其项集（文本块七项类型转换 + 删除块）由**拾起呈现的浮层菜单**等价承接：新增 `EditorModel.blockMenuBlockId` 与 `EditorView.blockMenuLayer/blockMenuPanel`（锚定/翻转/面板形态与卡菜单层同口径，项高 50、面板上限 340 内滚）——拾起即贴块弹出、转入拖动 >10px 自动收起、原地松手留存待点选，与 Web 卡片菜单骑拾起同构。
   - 卡片行**不动**：CardMenuGesture 保留为其唯一长按消费者，引擎对卡片行恒 disarmed（dragAllowed 口径不变），两者不相争。卡片不可拖是 0.9.19 的既有原生取舍，本轮不借根治之名翻案。
   - 编辑中文本块仍 disarmed（长按归文本选择，Web 口径不变）。
3. **行为等价核对**：长按 480ms 拾起、拾起框（视觉面 ⊕4、半径同心）、双轴缩放 liftScaleFor、兄弟让位 260ms 曲线、落位弹簧、拾起/落位触觉——全部沿用既有呈现与数值（本轮零改动）；类型转换与删除块仍长按可达（呈现载体由系统 contextMenu 换自有浮层，与卡菜单同形态语言）；卡片菜单、文本选择两路原样。
4. **构建接入**：build-app2.sh 五处文件清单加 MomentDrag.swift、新增 primary 轮产出 drag.o 并入链接行；版本 bump 0.9.47 / build 74（构建脚本 + 设置页文本，verify [1] 对账）。

## 五、打点与断言清单

Diag 打点（全链关口）：
- `DRAG engine attached`（引擎侧，建引擎时）——证识别器已装；
- `DRAG anchor attach deferred (no sv ancestor yet)`（锚点侧 logOnce warn）——attach 时序异常留痕；
- `DRAG press target id=`（引擎侧，触点命中且武装时）——证触摸到达引擎；
- `DRAG press disarmed id=`（引擎侧 logOnce）——命中但被武装判定拒绝（编辑中文本块/卡片）；
- `DRAG pickup id= type=`（行侧，沿用）+ `DRAG menu show id=`（行侧新增）——证拾起发生；
- `DRAG drop id=` / `DRAG cancel id= state=`（引擎侧新增）——证序列收尾形态。

verify_ios.sh：
- [7] 拖拽哨兵改锚：取段来源由旧 installer 段改指 MomentDrag.swift 全文（注释行除外），require 零回潮 + 锁滚动在位两项语义不变；
- 新增 [14] 组（J14-1…J14-7）：单识别器计数恰 1 + 引擎/锚点符号在位；旧 DragPickupInstaller 代码行零残留；BlockRow 无 .contextMenu 且 CardMenuGesture 保留；pan 并行 + 命中过滤 + disarmed 留痕三件；全链打点五点；拾起菜单承接面四点（状态/呈现层/置位/面板）；MomentDrag.swift 构建接入（primary 轮 + drag.o 链接）。
- 本机实跑（未构建）：源码组 [1]–[14] 全绿；仅 [5] ipa 陈旧、[9] 产物语言包两条产物类红（与历次落码同型，构建后消除）。

## 六、残余 unknown 与真机验证读法

- **unknown**：三方竞争者中决定性赢家是谁（平台仲裁不可见，本轮以清空竞争面处置，不依赖单点指认）；UITextView 选区识别在本轮后是否仍会在个别触点上与引擎长按（0.48s）发生可见干扰（引擎已是唯一显式 claimant 且与 pan 并行，理论上只剩它一方，量级待真机证）。
- **真机验证读法**（装 0.9.47 后导出 Diag，按行判读）：
  1. 无 `DRAG engine attached` → 引擎未建（锚点注册路断），看有无 deferred 警告行区分时序问题；
  2. 有 attached、无 `DRAG press target` → 触摸未达引擎或命中换算落空（下一步查锚点 frame）；
  3. 有 target、无 `DRAG pickup` → 识别器在 480ms 内被判失败（看同序列有无 cancel 行与 state 值）；
  4. 有 pickup、无框/缩放体感 → 问题转呈现层（draggingId 已置位，查 LiftFrame/scaleEffect 段）；
  5. 全链齐全且可拖 → 本轮定案关闭；类型转换菜单在拾起浮层内点选验证、卡片菜单与编辑中文本选择各验一次未被误伤。
