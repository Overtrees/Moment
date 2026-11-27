# 标题胶囊不能二次编辑——根治报告

时间：2026-11-27。对象：原生 iOS `MomentApp.swift` 的 `EditorHeaderView`（标题胶囊）。用户真机报障（0.9.53）：标题编辑过一次之后，再点标题胶囊无反应、进不了编辑态。截图实况：胶囊呈截断态（标题超 10 字 + meta 行），即报障发生在长标题呈现态。

## 一、定因（证据分级）

### proven（结构，代码确证）

胶囊的呈现/编辑切换是**条件替换**结构（改前 `titleCapsule`）：

- 未聚焦且标题 ≤10 标量：渲染 `TextField`（常驻层级）；
- 未聚焦且标题 >10 标量：渲染普通 `Text`（截断串），**字段不在层级内**，点按仅在手势里置 `titleFocused = true`，字段在同一次视图更新中才被条件插入。

由此截断态的每次进入都依赖「程序化置焦请求与字段入层级同事务」这条脆弱路径，且聚焦瞬间字段的 `onChange(of: titleFocused)` 写 `ui.titleBase`（EditorUI 的 `@Published`），触发 EditorView/EditorHeaderView 整树重演算——焦点获取与宿主重建同帧竞态，请求被吞、`titleFocused` 被系统回滚为 false，胶囊弹回截断 Text。用户可感即「点击没反应」。

与报障经历逐项吻合：标题尚短时字段常驻、点按走 UIKit 原生落焦（确定性），故第一次编辑可用；把标题改长并提交后，呈现态切换为 Text 分支，此后每次进入都走脆弱路径——「编辑过一次之后不能二次编辑」。竞态性质亦解释偶发可进、非必现。

### proven（对照，同构可靠路径在仓内已有实证）

音乐输入胶囊 `MusicPillView` 的字段常驻其块层级，`focusMusicId` 变化时程序化置 `fieldFocus = true` 可靠落焦——「字段先在层级、后置焦」是仓内已实证的确定性口径。本次根治即把标题胶囊收敛到同一结构。

### inferred（微观时序）

竞态的精确微观形态（置焦请求被丢弃 vs 字段重建丢焦 vs FocusState 回滚的先后）取决于 SwiftUI 运行时调度，本机无真机/模拟器分步复现；定案依据为结构证据 + 报障形态的逐项对应，不逐帧断言。

### 已排除（逐项查实）

1. **转场认领门波及**：`focusGateOpen`/`wantsInitialFocus` 只被新建篇首块的 `BlockTextView.claimInitialFocus` 消费（成功校验/有界重试均在该点），标题字段不经 claim 链；0.9.50 转场重构与本故障无交点。
2. **正文落焦热区吞点**：`focusHotZone` 在滚动内容内，页眉是 EditorView ZStack 的兄弟层且在其上，命中先达页眉。
3. **glassControl 修饰器**：仅背景材质 + 描边 + 裁切，无手势、无命中改写。
4. **菜单面板遮挡**：`menuPanel` 隐藏时 `.allowsHitTesting(false)` 已门控。
5. **提交链残留状态位**：`commitTitle` 只写标题/草稿/反链，无任何「已编辑」闩锁；失焦后状态位仅 `titleFocused=false`，与初态一致——不存在被守卫挡回的记账位，断点纯在置焦路径本身。

## 二、状态机（改前 → 改后）

改前：

```
呈现态（≤10 字）: TextField 常驻 ──点按──> 原生落焦 ──> 编辑态
呈现态（>10 字）: Text（字段离场）──点按──> 置焦+字段同事务插入 ──✗ 竞态吞焦──> 弹回呈现态
编辑态 ──失焦/Enter──> commitTitle ──> 呈现态
编辑中滚动 >30: 坞翻转（VStack↔HStack）→ 胶囊重建 → 会话可被腰斩
```

改后：

```
呈现态（任意长度）: TextField 恒常驻（单一身份）
  ├─ ≤10 字 / 聚焦中：字段本体可见，点按走原生落焦
  └─ 截断态：字段 opacity 0 + 截断 Text 覆盖层呈现；
       点按覆盖层 ──> titleFocused = true（字段已在层级，确定性置焦）
编辑态 ──失焦/Enter/Esc──> 既有口径原样（trim+空回退、快照还原、辞焦）
编辑中滚动: dockCompact 冻结坞态，会话不被重建打断；失焦后按当刻 scrollY 归位紧凑
```

## 三、改动清单（仅 `MomentApp.swift` 的 EditorHeaderView 段 + `verify_ios.sh`）

1. **字段常驻**（`titleCapsule` 重构）：标题行改为 `ZStack { TextField; if truncated { 覆盖层 } }`。字段恒在层级，`truncated`（未聚焦且草稿超 10 标量）时字段 `.opacity(0)` + `.accessibilityHidden(true)`；覆盖层为原截断 Text（同字体/字距/单行），加 `.frame(maxWidth: .infinity)` + `.contentShape(Rectangle())` 整行命中面，点按记 Diag 后置 `titleFocused = true`。旧条件式 `if titleFocused || count <= 10 { TextField } else { Text }` 整段退役。
2. **坞态冻结**（同根问题，会话期结构漂移）：新增单点派生 `dockCompact = scroll.scrollY > 30 && !titleFocused`，`headerOverlay` 分支、`capsuleWidth` 的 compact 判定、坞翻转动画值三处共用。标题会话期间滚动不翻转坞态——与 Web S7「编辑期抑制翻转、会话结束按当刻 scrollY 归位」同口径；同时消除 capsuleWidth 与呈现分支两处各算一份 compact 的漂移面。
3. **Diag 打点**（此前标题链零打点，本次补齐）：覆盖层点按记 `EDIT title focus via=capsule`（命中达入口）；聚焦落定在既有 `onChange` 快照点记 `EDIT title session begin len=<标量数>`（会话真开始）。主线经桥 `diag_tail` 判读路径：两行齐现 = 进入成功；只有前者 = 置焦未落（复发信号）；两者皆无 = 命中未达入口。
4. **既有行为零改动**：`commitTitle`（trim + 空回退「无标题」）、`onSubmit` 提交并辞焦、Esc 快照还原（`titleBase`）、胶囊宽度公式与截断呈现形态（前 10 标量 + …）均原样；落焦认领（claim）链未触碰。

## 四、同类面排查账（编辑页内点按进入/重入编辑的面）

| 面 | 结构 | 结论 |
|---|---|---|
| 文本块（BlockTextView） | UITextView 常驻 + 原生点按落焦；claim 门只管新建初始认领 | 不同病（proven） |
| 音乐输入胶囊（MusicPillView） | 字段常驻块层级，`focusMusicId` 置焦 | 不同病，且为本次根治的同构参照 |
| 链接表单字段 | 表单 `onAppear` 置焦，字段随表单同生、点按原生落焦 | 不同病 |
| 标题 meta 行（时间·字数） | 纯呈现 Text，无编辑入口（Web 同形态） | 不适用 |
| 副标题/日期行 | 编辑页无此可编辑面 | 不存在 |

「条件插入字段 + 同事务程序化置焦」反模式在编辑页内仅标题胶囊一处，已清零。

## 五、断言（verify [24]，锁机制不锁数值）

`verify_ios.sh` 新增 [24] 组 T24-1…T24-5，本机自跑**全绿**（全脚本 194 ✓；余 3 条 ✗ 为既有非本批项：ipa 陈旧、产物语言包——本机无新构建，tree 冒烟自解；B16-3 为 M2 在途的预期断言债，其报告 §5 已列改写计划）：

- T24-1 字段常驻：capsule 段含 ZStack + `.opacity(truncated ? 0 : 1)`，旧条件式 `if titleFocused ||` 零残留；
- T24-2 覆盖层置焦路径：`if truncated` + 整行 `contentShape` + Diag 入口行 + 置焦行齐备；
- T24-3 坞态单点：EditorHeaderView 段内 `scroll.scrollY > 30` 字面仅剩定义处 1 处、`dockCompact` 消费 ≥4 点、capsuleWidth 共用派生；
- T24-4 会话打点 `EDIT title session begin` 在位；
- T24-5 既有行为锚：trim+空回退式、titleBase 快照、Enter 辞焦三行不移（防回退）。

Swift 编译级验证本机无 swiftc，随主线 tree 冒烟执行（改动为纯 SwiftUI 视图层重组，无新 API 面）。

## 六、真机终判点

1. 长标题（>10 字）笔记：点胶囊一次即升键盘、全文可编辑；失焦后反复点、反复编辑，循环不失效。
2. 标题编辑中滚动正文：坞不翻转、键盘不掉、草稿不被腰斩提交；失焦后下滑，坞按当刻位置归位紧凑态。
3. 短标题（≤10 字）点按落焦与改前一致；Enter 提交辞焦、Esc 还原会话起点、清空标题回退「无标题」均不变。
4. 紧凑态（下滑后）点胶囊同样可进编辑。
5. Diag 复核：点按截断胶囊后应见 `EDIT title focus via=capsule` 与 `EDIT title session begin` 两行成对出现。

## 七、账外存量（如实标注，非本批范围）

审计 B-4（audit_title_input.md，proven）：原生未实现 Web 的「截断态点按落点 x → 全文字符位」光标映射，落焦后光标位交 UIKit 默认。本批只恢复「能进编辑态」，未动落点口径——点按进入后的落点行为与改前一致（改前竞态偶发成功时同为 UIKit 默认），不构成回退；映射补齐需单独立项（涉及字段选区编程接口）。
