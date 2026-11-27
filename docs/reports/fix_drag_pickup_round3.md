# 拖拽拾起第三轮根治落码报告（0.9.49）

- 日期：2026-11-27
- 依据：audit_drag_pickup_round3.md（排查定案）+ 用户
  2026-11-27 卡片口径纠正（Web 上卡片块全可拖）。
- 范围：MomentDrag.swift（引擎）、MomentApp.swift
  （BlockRow 锚点/卡片行/BlockTextView/EditorModel）、
  build-app2.sh（版本）、verify_ios.sh（[14] 增补）。
- 状态：落码完成，未提交、未构建（构建与冒烟由主线
  在 tree 上收口）。

## 一、逐条对账（对排查报告第五节 + 用户纠正）

### 1. 并行姿态放开（五.1）

`DragPressEngine.gestureRecognizer(_:shouldRecognize
SimultaneouslyWith:)` 改为对全部其他识别器返回 true
（函数体 `return gr === recognizer`），引擎降为纯计
时 + 位移判定，与 Web 按压计时器同构（除 move 超限 /
up / cancel / 新 down 四条明文路径外无可被强制失
败）。宿主 pan 不再是单独豁免对象——它只是「全部」
之一。拾起后的实际让行不变：拾起即锁
isScrollEnabled、手指先行 >10pt 由 allowableMovement
自然失败。

### 2. 参数不动（五.2）

minimumPressDuration = 0.48、allowableMovement = 10
一字未动，verify J14-8 新增锁定。未引入「按下即
拖」——那是规格变更，须用户改判，不在本轮内。

### 3. 拾起收敛选区 + 文本拖放处置（五.1 尾巴）

- EditorModel 新增 `convergeSelectionOnPickup
  (blockId:)`：经 tvRegistry 取本块 EditorTextView，
  清 selectedTextRange、本视图持焦点则 resignFirst
  Responder——Web pickup 的 removeAllRanges 对应动
  作。行侧 onPickup 在置 draggingId 后调用，实际收
  敛时记 `DRAG converge id=`（该行同时是「选区长按
  确曾与拾起同跑」的旁证）。
- 文本拖放二选一裁量：**取「关闭」**——
  BlockTextView.makeUIView 设
  `tv.dragInteractionEnabled = false`。理由：文本拖
  动交互的 lift 预览是 UI 接管而非单纯识别，并行放
  开压不住；块文本被拖出并非编辑器的行为面（Web 按
  压期以 user-select:none 压选区、无块文本拖出
  路）。关闭后拾起路径上只剩选区长按一方，由并行
  放开 + 拾起收敛覆盖。实测面（留真机）：长按文本
  块不再出现文本 lift 预览；外部文本拖入（drop
  side）未动、不受影响。

### 4. 打点补全（五.3，字段级照落）

- handle() 入口无条件记全部状态变迁：
  `DRAG press state=<possible|began|changed|ended|
  cancelled|failed> id=<目标|-> ms=<距认领毫秒，未
  认领 -1> disp=<距认领点位移 pt，未认领 -1>`。
  .changed 防刷屏：只记首条与首次越 10pt 各一条。
  旧 drop/cancel 行保留（与状态行互为校验）。
- shouldReceive 记认领时刻（pressStart）与起点坐标
  （pressOrigin），target 行带 `x=/y=`。
- began 无目标/行缺失：显式记 `DRAG began orphan`
  （warn），不再静默 return。
- 其余拒绝路径补齐：UIButton 命中记
  `DRAG press reject button`（logOnce）；无行命中记
  `DRAG press norow x=/y=`（logOnce）。说明：
  DiagLevel 只有 info/warn/error、无 verbose 档，排
  查报告的「verbose 级」以 logOnce 信息级代之（防
  高频触摸刷屏，证据不丢）。
- disarmed 行保留（logOnce per id）。

### 5. 卡片块武装（用户纠正）

- `BlockRow.dragAllowed` 删除卡型 disarm：全部块型
  一律武装，仅剩两类真守卫——正在编辑的文本块
  （`block.isText && editingBlockId == block.id` →
  disarmed，归文本选择）、按钮类子视图（引擎
  shouldReceive 先行排除）。
- CardMenuGesture（独立 SwiftUI 长按）整段退役：
  定义与唯一调用点（BlockRow .modifier）全删，全
  仓代码行零残留（仅注释提及沿革），verify J14-3
  改判锁定。
- 卡菜单改骑拾起：行侧 onPickup 对卡型置
  `editor.cardMenuBlockId`（余者仍置 blockMenu
  BlockId），统一记 `DRAG menu show id=`；呈现走
  既有 cardMenuLayer（贴卡下 8px/放不下上翻/宽
  216/点遮罩关，形态口径未动）。onDrag 转入拖动
  >10px 时两套菜单一并收起；原地松手菜单留存待点
  选——与文本块 blockMenuLayer 同构、与 Web 卡菜
  单骑拾起同构。

### 6. 版本与断言

- bump 0.9.49 / build 76（build-app2.sh 的
  CFBundleShortVersionString/CFBundleVersion + 设
  置页 Text("0.9.49")，verify [1] 对账过）。
- verify [14] 增补/改判：J14-3（CardMenuGesture 零
  残留）、J14-4（并行全放开形态）、J14-8（参数未
  动）、J14-9（全状态打点齐全）、J14-10（卡片武装
  + 卡菜单骑拾起 + 收敛在位）、J14-11（dragInter-
  action 关闭 + 收敛函数在位）。
- 本机实跑 verify：除 [5] ipa 陈旧、[9] 产物语言
  包两条已知产物红（构建后消除）外全绿，[14] 组
  11 项全 ✓。

## 二、块型武装对账表（Web unitKind ↔ 原生）

Web（editor.js unitKind）：text = 单元本体即
contenteditable 文本；atomic = blk-wrap 原子块；
composite = data-bids 组合块。原生拖拽单元 = 顶层
BlockRow（列表项在原生不是独立行，随列表块整行）。

| Web unitKind | 原生块型 | 0.9.49 前 | 0.9.49 后 | 拾起菜单 |
|---|---|---|---|---|
| text | paragraph / heading / quote / callout / codeBlock | 武装（编辑中本块除外） | 同左 | 类型转换菜单 |
| text | todo（主体文本区；勾选钮 = 按钮守卫） | 武装（同上） | 同左 | 类型转换菜单 |
| composite | bulleted-list / numbered-list（整行一个单元） | 武装 | 同左 | 类型转换菜单（仅删除项） |
| atomic | image / gallery / imgTextCard / imageTextRow / musicCard / link-card / attachment / video / divider（= cardMenuTypes） | **disarmed**（走 CardMenuGesture 独立长按） | **武装** | 卡菜单（骑拾起） |

守卫全集（仅此两类）：① 正在编辑的文本块（行级
enabled=false，日志 `DRAG press disarmed`）；② 按
钮类子视图命中（引擎 shouldReceive 排除，日志
`DRAG press reject button`）。

## 三、下一包真机判读表（沿排查报告第六节，按新打点字段更新）

导出 Diag 后按一次长按尝试的日志序列对表：

| 日志形态 | 判定 | 下一步 |
|---|---|---|
| target → `state=failed` 且 ms≪480、disp>10 | 手势形状：移动先于拾起（规格行为，Web 同） | 非缺陷；若产品要「按下即拖」须用户改判规格 |
| target → `state=failed` 且 ms≈480–520、disp<10 | 竞争强杀残存——并行全放开后此型应消失，消失即反证本轮定因；仍现 = 另有非识别器路径 | 按 id/块型回查该块的视图层级 |
| target → `state=began` → `DRAG pickup` | 拾起成立 | 断点后移：看 menu show / drop / cancel 与呈现层 |
| target → `state=began` 无 pickup | 行侧断点：查 `DRAG began orphan`（目标/行缺失）或 onPickup 未达 | 按 orphan 有无分流 |
| 文本块拾起伴 `DRAG converge` | 选区长按确曾同跑、已被收敛——本轮定因的活旁证 | — |
| 卡片块：target → began → pickup → menu show，拖动 >10 菜单收起、drop 落位 | 卡片武装 + 菜单骑拾起全链成立 | — |
| 只有 `press disarmed`（编辑中文本块）/ `press reject button` / `press norow` | 守卫/未命中，设计内 | — |

## 四、残余与未动面

- 呈现层（框/双轴缩放/让位/落位弹簧/触觉）零改
  动，行为等价。
- 外部文本拖入（UITextView drop side）未动。
- 列表块整行拾起时若某列表项正处编辑态：行级守
  卫只认顶层文本块的 editingBlockId，列表项编辑
  态的 id 口径未在本轮改动（与 0.9.48 前行为一
  致，非本轮回归面）。
