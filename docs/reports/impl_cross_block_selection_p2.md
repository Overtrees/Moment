# 跨块选区二期落码报告（F-09 Shift+方向端点扩展 + 段内分段着色）

定案出处：`plan_cross_block_selection.md` §8.1 二期（任意端点键盘扩展 + 段内分段高亮）+ `impl_cross_block_selection_p1.md` §七待二期清单。地基 = 一期未提交落码（MomentXSel.swift / MomentXSelBridge.swift / MomentApp.swift·build-app2.sh·verify_ios.sh 的 XSel hunk），动工前 git status/diff 全量快照映射（/tmp 侧留痕），一期 hunk 只读核对、未回退；本批与一期 hunk 同文件处 disjoint 叠加。组版状态：未提交、未 bump，随 0.9.61 组版；verify 组号顺延 **[51] X51-1..5**（[50] 为一期组）。

登记先行（先改矩阵再落码）：自检矩阵 EDT 行已回写——**一期报告 §七建议的「EDT-15」编号有误**：EDT-15 在现行矩阵已被「块拆分/合并语义」占用，跨块选区的注册行是 **EDT-55**（一期动工时该行已在册、状态「计划覆盖」）。本批按 §七建议文本的实质内容回写 EDT-55：功能点补「+ 段内分段着色」、现状改判「功能已落而场景未建」（一期 [50] + 二期 [51] 构建期锁、场景 xsel_replace_roundtrip 待立）、批次列标两期 ✓；§0 计数随动（计划覆盖 13 → 12、部分覆盖或功能已落而场景未建 13 → 14，其余不变）。

## 一、落点清单

### MomentXSel.swift（纯核心增补，+约 120 行）

| 符号 | 内容 |
|---|---|
| `XSelDirection` | 方向枚举（桥接层入参口径）。 |
| `XSelCore.stepChar` | Web `stepChar` 逐支移植：标量步进不劈代理对（UTF-16 码元查高/低代理）、块界跨相邻单元邻界、文档首尾钳住。 |
| `XSelCore.extendHorizontal` | 横向接管判定：焦点不在单元表 → nil；原无选区且步进未跨出焦点单元 → nil（放行原生）；余皆返回新端点对。 |
| `XSelCore.verticalFocus` | 纵向决策表：非边缘（原无选区 → nil；有选区 → sameHit、无果 nil）/ 边缘（crossHit 优先；仅 docClamp 时原无选区且钳位恰合焦点 → nil）。几何量测由桥接层喂入（onEdge / sameHit / crossHit / docClamp 四值）。 |
| `XSelCore.segmentRange` | 段内分段计算（paintXsel 段级口径）：起/止/同单元/中间四态 + 跨度外与端点消失返回 nil。 |

### MomentXSelBridge.swift（状态机增补）

- **`xselExtend(dir:native:)`**：端点源双路——xsel 在位取锚/焦（端点消失先清选作废、返回 false）；不在位取引参原生两端（loc/len/focusAtEnd → 锚/焦，活动端为焦）。左右走 `extendHorizontal`；上下走几何量测（焦点视图 tvForBlock + caretRect 窗口系 + lineBoxes 行盒判边缘 + hitOffset 目标列 hit-test，x = 焦点光标 minX + 1 与 Web `rect.left + 1` 同值）后走 `verticalFocus`。成立后经 `setXSel` 单点置位（guardSpan 钳制、二期入口即一期预留的该入口；钳后重合归 nil），原生选区收拢到锚点（placeXSelCaret 投递），Diag 两行（终值 / collapsed）。
- **`xselSegment(forBlockId:)`**：呈现查询，计算本体在 XSelCore.segmentRange。
- **`xselRowCovered` 口径收窄**（一期函数的二期分工修正，非缺陷修复）：行面仅判「端点容器之间的原子顶层行」（加 `xselIsAtomicTop` 前置 + 严格不等式）；文本行移交段内分段着色。一期全选态下端点恒全文首尾，行面整行与段级涂法等价，故一期行为在全选面不变；X50-6 的调用点锚（`xselRowCovered(block)` 恰 1）形态未动。

### MomentApp.swift 接线（与一期/E2/U4b hunk disjoint）

- **量测共用**：`tvForBlock` / `lineBoxes` / `hitOffset` / `LineBox` 由 private 改内部级（各加注记，沿一期 shiftListStart 跨文件共用单点先例），桥接层扩展共用 crossBlockArrow 同源量测，不另写一份。
- **活动端跟踪**：`EditorTextView.xselFocusAtEnd` + `noteXSelSelection()`——UITextView.selectedRange 不记方向，以逐次变化「未动端为锚、动端为活动端」推定（从光标长出时光标端为锚；双端齐动保持旧推定；收拢即复位）；挂 Coordinator.textViewDidChangeSelection 首行（与 xsel 在位无关恒记；一期对账调用与 `ed.xsel != nil` 计数原样未动，X50-3/4 实测仍绿）。程序化投递（落点/撤销恢复）不经该回调、推定不更新，默认活动端在尾——与 E2 恢复选区的存储读法（location 起向后延展）同口径。
- **handleKey 在位支**：四方向 Shift 支由一期「收拢后放行」改「先试 xselExtend、成立消费、未命中收拢到焦点端后放行」（Web 同支形态）；每支保留恰一处 `collapseXSel()` 于失败路（X50-4 计数 5 未动）；头注同步改二期口径。
- **handleKey 无选区入口**（新增，置 xsel 支之后、方向分发之前）：非组字 + 纯 Shift + 四方向 → 以本视图原生选区两端调 xselExtend，接管才消费；不接管落下方 mods 守卫放行原生（与 Web else-if 支同位）。
- **段内分段着色**：`BlockTextView.refreshXSelHighlight` + Coordinator 状态两件（`xselSegRange` / `xselSegSaved`）+ updateUIView 收尾调用（组字中不入）。经 textStorage 属性层涂 `T.xselHighlightUI`；涂前快照段内既有 `.backgroundColor`（Marks 的行内代码/高亮底同通道），收段/移段逐段恢复，不整段剔除；内容重灌后以「段首实测背景 ≠ 令牌色」自愈重涂，不依赖各重灌点逐个通知。
- **令牌**：`T.xselHighlightUI`（UIColor 变体，与 xselHighlight 同值 rgba(0,105,217,0.30)、明暗同值，沿 fillHoverUI/mathFailUI 的 UI 变体先例）。
- **BlockRow 注释**同步二期分工（一期注释的「分段着色随二期」已兑现）。

### verify_ios.sh

- 新增 [51] 组 X51-1..5（见 §四）。
- 连带改锚一处（期望合法变更，注释留沿革，同 J20-12 先例）：X50-6 的 `xselHighlight` 行数 2 → 7、`0x0069D9` 出现 2 → 3（二期加 UI 变体令牌的定义 + 属性层消费 + 注记），分段面明细由 X51-4 分锁。
- build-app2.sh **零改动**（无新文件，两 xsel 文件的构建登记一期已备）。

## 二、Web 实证对账表

落码前逐项回 Web 源码核对（editor.js xselExtend 622–686、stepChar 582–613、pointRect/pointFromXY 596–621、keydown 分发 812–840、paintXsel 470–510、setXsel/guardSpan 503–534），不凭方案转述：

| 项 | Web 实证 | 原生落法 | 等值性 |
|---|---|---|---|
| 接管总则 | 仅跨块步进或已有 xsel 时接管，块内放行原生保粒度 | extendHorizontal/verticalFocus 的 hadSel 判定全集 | 同构（表驱动锁） |
| 左右步进 | stepChar：代理对不劈（高代理 +2 / 低代理 −2）、块界跨邻界、文档端钳 | XSelCore.stepChar 逐支移植（NSString 码元判定） | 同构（11 项表驱动全过） |
| 上下边缘判定 | 光标矩形对块矩形：`rect.top - er.top < lh*0.9`（lh = rect.height‖24）近似判首/末行 | TextKit 行盒直判焦点行序号（li == 0 / 末行） | 决策等值、量测更准（Web 为 DOM 近似，原生有真行盒——机制差异点名，判定面同果） |
| 上下目标列 | pointFromXY(fEl/tEl, rect.left + 1, y)：y 取相邻行内侧（块内 ±lh*0.6、跨块目标行 ∓lh*0.4） | hitOffset（crossBlockArrow 同源量测）对目标行以 xWindow = 焦点光标 minX + 1 逐偏移取最近 caret X | 行为等价（同为「同列 hit-test、超宽钳行尾」；y 的亚行偏移在行盒口径下由目标行本身吸收） |
| 上下文档端 | 边缘且无相邻块：↑ → 首块首、↓ → 焦点块尾；原无选区且恰合焦点 → 不接管 | docClamp + verticalFocus 同支判定 | 同构 |
| 上下兜底 | pointFromXY 无果 → ↑ 目标尾 / ↓ 目标首 | 目标视图未注册/无行量测/（hitOffset 恒有果）→ 同形兜底位 | 同构 |
| 已有 xsel 时块内上下 | xsel 在位时非边缘行内移动亦接管（原生选区收拢在锚点、无从扩展） | verticalFocus hadSel 支取 sameHit | 同构 |
| 扩展后落点 | setXsel 尾 placeNativeAt(anchor)：原生选区收拢锚点 | setXSel 后 placeXSelCaret(锚点) 投递 | 同位同构 |
| 步回收拢 | setXsel 钳后锚焦重合 → xsel = null、不另落点 | setXSel 既有口径（二期经其入）；Diag 记 collapsed | 同构（一期单点复用） |
| 源码块守卫 | guardSpan 钳跨源码块的跨度；端点可在源码块内起步（Cmd+A 才有 !isSrcBlock 门） | setXSel 的 guardSpan 既有单点；扩展入口不另设源码门 | 同构 |
| 分发位 | xsel 支内 Shift+方向：extend 未命中 → collapseXsel 后续行原生处理；无 xsel 时 else-if 支先试 extend | handleKey 两处同位接线；未命中保留一期裁定的「收拢 + 放行原生块内扩展」形态（见 §五注记） | 主体同构，失败路形态差见 §五 |
| 段级呈现 | paintXsel：端点块涂 [from,to) 段、中间文本块整段、端点间非可编辑单元整块 | 文本单元走属性层段涂（segmentRange 逐单元）、原子行走行面整行（xselRowCovered 收窄后口径） | 同构 |
| Esc 先后 | 斜杠开时 Esc 在 xsel 支之前吞键归页级链；xsel 支 Esc 收拢到焦点端 | 原生 handleKey 斜杠支不消费 Esc（归页眉 Esc 链）、xsel 支消费 Esc 收拢——两面不同时在位（斜杠开时 xsel 已被击键替换面收口），先后无实际交面；**实机先后仍待核**（一期 §七注记沿袭，列 §六终判点） | 代码级无交面（proven）；实机面 unknown |

### 原生端点方向的近似（点名）：nativeEnds 的方向

Web nativeEnds 读浏览器 selection 的真实锚/焦（含方向）；UITextView 不提供方向。原生以活动端推定补齐（见 §一跟踪项）：连续 Shift 扩展的建立过程（先块内长出、再跨界）中推定恒准（每次变化恰动一端）；双端齐动的跳变（点按定位后直接 Shift+方向、程序化恢复选区）保持旧推定/默认尾端，首步方向可能与 Web 真实锚/焦不同——差异只落在「已有非收拢原生选区时第一步扩展的锚取哪端」，一步之后 xsel 锚/焦即为模型真值、自洽收敛。此为平台 API 缺失下的最优近似，非行为面缺口扩大。

## 三、proven 上限分级

| 面 | 级别 | 依据 |
|---|---|---|
| 纯核心决策（stepChar/横向接管/纵向决策表/分段计算） | **proven** | 表驱动 33 项检查全过（X51-2 内嵌断言体与核心同体，宿主 swiftc 编译实跑） |
| 三个 primary 遍类型检查（app/xsel/xsel_bridge） | **proven** | 本机工具链 swift-frontend 逐遍实跑零 error |
| 接线/守卫/计数锚（扩展调用 6、跟踪 2、量测共用、着色接线、Diag、行面收窄） | 构建期断言锁 | X51-1/3/4/5 + X50-6 改锚；全量 verify 529 ✓（见 §四） |
| 纵向几何的实机量测（行盒判边缘、hitOffset 落点）、活动端推定的实机会话、着色像素、Cmd/Shift 物理投递、Esc 实机先后 | **unknown** | 无真机/实机会话证据，按纪律如实标，归真机终判（§六） |

## 四、verify 结果

本机全量 `verify_ios.sh`：**529 ✓ / 2 红**。红项为既有产物红（ipa 陈旧、产物语言包与 Web 源不一致），待下一次构建消解，非本批引入（基线 = 一期 524 ✓ + 本批新增 5 = 529 ✓，账平）。本批 X51-1..5 全绿；一期 X50-1..7 全绿（X50-6 改锚后绿）；E47/DT46 等邻组计数未受影响（build-app2.sh 零改动）。

过程中 X51-4 首跑一红并已根治：断言模式串 `units[ord.sIdx]` 的方括号被 grep 解析为字符类——模式转义后绿（断言写法问题、非落码问题；通则：verify 模式串含 `[` 须转义或走 -F）。

## 五、注记与分叉

- **失败路形态差（沿一期裁定，不在本批翻案）**：Web 在 xsel 支内 extend 未命中时 collapseXsel 后不 return、续落 crossBlockArrow（收拢光标的跨块移动）；一期原生裁定为「收拢到焦点端 + return false 放行原生块内扩展」，二期在位支沿此形态（仅把成功路换成真扩展）。未命中在原生量测面近乎不可达（焦点视图已注册且落点可测时恒有果），差异面积极小，登记备查。
- **一期缺陷回报**：无。二期发现一期 `xselRowCovered` 的行面口径属一期设计内的近似（报告自陈「分段着色随二期」），按二期分工收窄，非缺陷。
- **并发观察（非本批，出界不碰）**：本批工期内 `tests/probe_slash_anchor.mjs` 出现非本批修改（K5c/d/e Web 侧外侧原子守卫的探针增补，与一期报告 §二「建议 Web 侧另行核修」对应，应为并行批在办），本批未触碰该文件，留主线对账。

## 六、真机终判点

1. 外接键盘 Shift+←/→：块内不接管（原生粒度）、块界跨块建立选区、连续扩展锚不动、反向步回收拢后选区消失。
2. Shift+↑/↓：首/末行跨块、非首末行块内放行（无选区时）/块内续扩（有选区时）、目标列保持与超宽钳行尾。
3. 先块内 Shift 选词段再跨界：锚取选区静端（活动端推定实机面，含反向选区起步一例）。
4. 段内分段着色呈现：端点块只涂段内、中间文本块整段、原子行整行、行留白不涂；与 Web 观感对照。
5. 着色与标记共存：选段压行内代码/高亮（==）时底色关系、收拢后标记底完整恢复。
6. Esc 先后实机核：xsel 在位 Esc 收拢 vs 页级 Esc 链（一期 §七沿袭项）。
7. 扩展后动作面衔接：扩展选区上删除/覆打/复制/粘贴替换走一期漏斗、单步撤销。
8. 组字中 Shift+方向不接管、组字收拢既有口径不变。

## 七、组版注记

- **tree-sync/push_small.py 名单**：二期无新文件，名单沿一期注记（MomentXSel.swift + MomentXSelBridge.swift 两件随 0.9.61 组版补入即可，本批未增件）。
- 本批未提交、未 bump；与一期落码同搭 0.9.61 组版（HEAD 0be6c1d = 0.9.60/build 87 之上两期叠加）。
- 矩阵 EDT-55 与 §0 计数已先行回写（见文首登记注），组版批勿再重复改判。
