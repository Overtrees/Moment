# E3 转换语义单点化批 · 落码报告

- 时点：2026-11-27。基线 HEAD 6ce6cd8（0.9.57 组版提交落定后），工作树多批并行落码中开工：动工前 `git diff` 全量快照（/tmp 留存口径：11 文件在途），逐 hunk 避让；完工复验 = 开工快照全部「+」行在现行文件中零丢失（11/11 文件、合计 628 行新增行全存活）。
- 依据：audit_editor_deep.md 域二（F-03…F-07、M-03/M-04/M-05、m-02）与转换矩阵全表；Web 真源 rust/apps/web/src/editor/ops.rs（op_convert/apply_type）+ model.rs（clear_type_fields/list_start/set_list_start/shift_list_start/strip_md_prefixes）。
- 纪律：不提交、不 bump，随下一组版。落码文件：rust/apps/ios/app/MomentApp.swift（转换领地）、rust/apps/ios/app/verify_ios.sh（[25] 组尾 B25-E3-1..5）。

## F-07 定案登记（用户 2026-11-27 裁定）

**原生真块型形态为正**：斜杠转代码块/提示/列表产真 codeBlock/callout/list 类型（保 runs）即定案口径，本批按此落码。Web 侧产 MD 源段落是其呈现模型下的形态，Web 兼容读真块型另有专批、不在本批范围。由此派生两条本批口径：

- 转代码块不剥 MD 前缀：真块型口径下正文原样入 codeBlock、runs 保全——与 Web 围栏臂「正文保留原样、不剥前缀」（ops.rs D-13 注释）同果，仅形态不同（真块型 vs 围栏源段落）。
- 剥前缀（M-05）的适用集按 Web 真源定：op_convert 中 strip_md_prefixes 唯一调用点在其 MD 形态臂，剥的是转**列表（bullet/numbered）与提示（callout）**两类目标；纯引用（quote）走 apply_type 路径、Web 不剥，原生同口径不剥（任务书「转列表/引用」中的引用按此读为提示的 MD 引用形态臂；若主线另有裁定，quote 剥前缀为一行守卫之增量）。

## 单点设计（F-03 / m-02）

新增于 EditorModel（setBlockType 之前）：

- `clearTypeFields(_:)`：Web clear_type_fields 等价——摘 attrs 的 level/checked 两键；attrs 清空后整键摘除不留空壳（与 Web 序列化省略空 attrs 同果）。**calloutType 不清**：Web clear 同口径（其 Node 无此字段、变体存于 MD 源文；原生等价语义 = 转出提示时变体字段保留、转回复活，两侧一致，审计定案登记第 6 条）。
- `convertNodeType(_:type:level:)`：转换单点，Web apply_type 口径——先 clear、再按目标设新字段：heading 设 level、todo 恒设 checked=false；checked 镜像（BlockState.checked）转入 todo 时同步 false；children 与 nodeVersion 不在此动（两路径各自口径与 bump 点不变）。
- 两路径收敛：块菜单 `setBlockType` 改为 pushHistory → convertNodeType →（todo 时尾随空段）→ bump/save/原 Diag 行；斜杠 `applySlash` 的 convert 闭包改为「children 以当前 runs 重组 → convertNodeType → text 重算 → bump」。旧两处各自的 attrs 手写（菜单「checked 仅 nil 时设」、斜杠「不清旧字段」）整段删除、零残留。
- 根除点在转换时而非落盘时：flushedNode 对非 todo 块原样透传 node 的旧机制不再能把残留带进盘面（转换瞬间已清），未在消费方（flush）打补丁。
- m-02 随单点收敛：待办重转两路径恒重置 checked=false（Web apply_type todo 臂同式），旧菜单路径「保留勾选」口径消失。

## 逐项落码

### F-04 列表互换整表换型

applySlash 在 removeRunRange 之后、promoteListItem 之前加早路：触发块在列表项内且 act ∈ {bulletList, numberList} 时，只改父表 node 的 type（bulleted-list ↔ numbered-list）+ 无条件摘 attrs.start（Web remove_start_field 同式：互换生成的新表 start 默认 1、旧值不复活），项集/序/runs 全保留、不升格不拆表；落点回触发项 token 起点（Web D-11 同位），save + 原 Diag 行后返回。与 Web op_convert Item 臂逐项等价。B25-E3-3 以「早路锚在 promote 调用之前」的行序断言锁此顺序语义。

### F-05 start 传递两处

新增 start 三助手（Web 同名口径）：`listStart(of:)`（非 numbered 恒 1、缺失/非法读 1 不回写）、`setListStart(_:_:)`（仅 numbered 生效、≤1 删字段）、`shiftListStart(_:by:)`（头部摘除后递增）。

- exitListItem：两处尾表构造（头部清空/头部保留两支）在 itemStates 赋值后补 `setListStart(nl, listStart(of: list) + idx + 1)`（Web op_split 同式，被退出项占一号）——原实现尾表恒无 start、有序列表退出后编号自 1 重启的缺陷根除。
- mergeListItemBackward：首项（idx==0）摘除且列表存续的三处（空首项删项支、非空首项并前块支、li 缺失兜底升格支）各补 `shiftListStart(list, by: 1)`（Web op_merge remove_cur 的 ii==0 支同式）；列表随之消亡的分支不写（无对象）。非首项摘除不递增（序号顺移即正确，Web 同）。
- 既有 promoteListItem 尾表 start 公式（start0 + before.count + 1）与 Web 同式、审计已核，本批未动。

### F-06 多行转列表逐行拆项

applySlash 的 bulletList/numberList case 重写：行集经 `listLineRuns(b)` 取得（见 M-05），逐行各建一个 list-item（runs/children/text 逐行），列表节点形态与旧路同（同 id、type 按 act、children 由 itemStates 落盘）。落点按 token 所在行/行内偏移回置（以剥离 token 后的文本计行并钳制），单行时与旧口径同值。行集为空时兜底单个空项（与旧空文本行为同果）。

行切分 `runsSplitByLine`：以 run 文本内 \n 为界、标记键随片段复制（行内标记逐行保真）；尾随空行按 Rust `lines()` 口径摘一（全文以 \n 结尾时末空行不计）。

### M-03 待办尾随空段

新增 `ensureTrailingEmptyPara(after:)`：下一块非现成空段（paragraph 且纯文本 trim 后为空，Web is_empty_para 同式）时经既有 trailingParagraph 补一段，焦点不动。接入两路径：setBlockType 转 todo 时恒补（菜单路径块恒顶层）；斜杠转 todo 时仅顶层源补——列表项升格路 Web Item 臂不补尾随段，原生同口径不补（与审计「两路径」之斜杠路径指顶层转换，Item 臂差异在此登记）。

### M-04 callout 重转不抹变体

删除斜杠 convert 中唯一的 `n["calloutType"] = "note"` 写点——转换单点对 calloutType 不清不设：重转提示保留既有变体（warning 等不再被抹为 note）；新转入时字段缺省、calloutVariant 读缺省 note，与旧菜单路径（从不设此字段）同果。全文件 calloutType 赋值写点归零（B25-E3-2 负查锁；读取面 calloutVariant 的双源读不在此列）。

### M-05 转列表/提示前剥 MD 前缀

新增 `stripMdLineRuns(_:)`：源为 MD 源段落（paragraph 且 mdKind ∈ {Code, List, Callout, Quote, Heading}）时返回纯内容行集——载荷经 FFI mdParseJson 直调取新鲜解析树（与 Web strip 所用 classify 同源 core 解析器）：Code 取 code 逐行、List 取各项 segs、Callout/Quote 取各子段 segs、Heading 取标题 segs；行内标记经既有 MdRender.runs 保真为真 runs（F-07 口径下优于 Web 的纯文本形态）。接入：转列表经 listLineRuns（剥后逐行成项，与 F-06 同路）；转提示在顶层源时以剥后行集经 `joinedLineRuns`（\n 连接）重组 runs 后走 convert。转代码块不剥（见 F-07 登记）。

兜底与等价边界（如实登记）：

- Rich/Table/Divider 三类 Web strip 为恒等，stripMdLineRuns 返回 nil 走 runs 原路——恒等价，非降级。
- 解析形态与分类不符、Callout/Quote 子块无 segs 时回 nil 走原路：保内容优先于剥前缀。
- 与 Web classify 载荷的两处已知细差（均属真块型口径下的等价更优或无害面）：① 任务项「- [ ] x」在 parse 树中 [ ] 被解析为 checked 标记、不进项文本（结构化列表项本无 checked 承载，项文本为 x；Web strip 后为字面「[ ] x」）；② 嵌套列表项在 parse 树中挂 sub、不平铺（classify 按 trim 后前缀平铺）——转换时 sub 内容不入行集，源段落含嵌套列表时形态与 Web 分叉，属低频面，终判时可抽验。

## 附带发现（转主线定性，不在本批处置）

**mdKind/mdBlocks 缓存对的陈旧隐患（机制 proven / 运行可达性 inferred）**：mdKind 在文本变更时重置 mdCacheBlocks=[] 却不复位 mdCacheDone；其后 mdBlocks 在「cacheText 已等于新文本且 done 仍为真」时直接返回空数组——曾解析过的段落改文后，若渲染序先调 mdKind 再调 mdBlocks，预览可能读到空树。本批 strip 因此直调 mdParseJson、不经该缓存对（自包含免疫）；预览领地是否真实可达（编辑会话内 BlockState 生命周期与重建点）请主线转 E16/预览批次定性，本批未越界改缓存对。

## 断言与自检

verify_ios.sh [25] 组尾新增 B25-E3-1..5（场景本体 EDT-16/17 归 U4a，本组只锁落码构造）：

- B25-E3-1 单点计数：convertNodeType 定义恰 1、两路径调用恰 2、clearTypeFields 定义恰 1。
- B25-E3-2 负查：`["calloutType"] =` 全文件计数 0。
- B25-E3-3 顺序锚：整表换型早路行号 < promoteListItem 调用行号，且 op_convert Item 臂注释锚在位。
- B25-E3-4 计数：setListStart(nl,…) 恰 2、shiftListStart(list, by: 1) 恰 3、start 三助手定义各 1。
- B25-E3-5 构造：stripMdLineRuns/listLineRuns/runsSplitByLine 定义各 1、列表 case 走 listLineRuns、ensureTrailingEmptyPara 定义 1 + 调用 2（合计 3）。

本机自检：swiftc -parse MomentApp.swift 零诊断；verify 全跑——✓ 302 → 308（+5 为本批五条、+1 为同期续连批 B16-20），✗ 恒 2 条且与开工基线同为构建产物陈旧项（ipa/产物语言包未构建所致，非源码断言）。计数 grep 自检与设计值逐项相符（convertNodeType 1+2、calloutType 写点 0、setListStart(nl) 2、shiftListStart 3）。

## 矩阵逐格对照（落码后 vs 审计矩阵缺陷格）

| 格 | 落码前 | 落码后 |
|---|---|---|
| 标题→正文/待办/引用/提示（两路径） | level 残留落盘 | 单点先清 level、目标设新（heading 设 level、todo 设 checked=false） |
| 待办（已勾）→其他（两路径） | checked=true 残留、转回复活 | 清 checked；转回 todo 恒 false（复活根除） |
| 待办→待办重转 | 斜杠重置 false、菜单保留（m-02） | 两路径恒 false（单点同式） |
| 正文/标题等→待办 | 无尾随空段（M-03） | 顶层两路径补尾随空段（next-empty 不重复补） |
| 提示→提示重转（斜杠） | calloutType 恒重置 note（M-04） | 不写 calloutType、变体保留 |
| 提示→其他 | calloutType 两侧同留（定案） | 不变（单点不清，定案维持） |
| 列表项→有序/无序（斜杠） | 升格拆表单项新表（F-04） | 整表换型：父表 type 改、start 清、项集全保留 |
| 列表项→其他（斜杠升格） | 残留同 F-03 | 升格后走 convert 单点、清字段 |
| 正文多行→列表 | 整段塞单个 item（F-06） | 逐行拆项、标记随行 |
| MD 源段落→列表/提示 | 字面带前缀入项/入正文（M-05） | 先剥纯内容行再成项/成正文（代码块目标除外，F-07 登记） |
| MD 源段落→代码块 | 真 codeBlock、runs 保留 | 不变（F-07 定案为正，本批仅经单点补清字段） |
| 空项退出列表（有序） | 尾表 start 丢失、编号重启（F-05） | start = 原 start + idx + 1 传递 |
| 首项退格删/并（有序） | start 未 +1、编号漂移（F-05） | 存续时 start +1、三处齐 |

## 真机终判点（装后抽验）

1. 勾选一个待办 → 经块菜单转正文 → 再转回待办：应为未勾选（复活根除）；斜杠路径同验一遍；转标题再转正文后落盘 JSON 无 level 残留（可经桥 notes 回读或导出核）。
2. 有序列表（起始号 >1，如 start=3）中部空项回车退出：尾表首项应续原号（非 1）；首项退格删除/并入前块后，存续项号不变。
3. 三项有序列表任一项斜杠转无序：整表三项全转、序不变；转回有序：编号自 1（start 已清）。
4. 多行段落（粘贴三行）斜杠转列表：三项逐行；含粗体的一行标记保留。
5. MD 源段落「- 甲\n- 乙」（失焦呈列表预览）点入编辑后斜杠转无序列表：两项纯文本、无「- 」字面残留；转提示同验；「> [!WARNING]」源段转提示后正文无前缀字面。
6. 已有 warning 变体的提示块斜杠重转提示：变体仍为 warning。
7. 转待办后尾随空段：文末转待办补一段、后已有空段时不重复补；列表项升格转待办不补（Web 同口径，观感确认即可）。
