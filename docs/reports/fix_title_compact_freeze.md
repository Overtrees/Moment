# 标题胶囊横排点按卡死——根治报告

时间：2026-11-27。对象：原生 iOS `MomentApp.swift` 的 `EditorHeaderView`（标题坞）。用户真机报障（0.9.54）：竖排（列态坞）点标题胶囊可正常进入编辑；下滑进入横排（紧凑坞）后点胶囊，整个页面卡死，只能强退。

主线端内证据（桥 diag_tail，0.9.54 会话）：上一会话以异常收尾（重启后 LAUNCH 行报「上次会话未正常收尾（停在：场景·编辑页）」，与卡死后强退吻合）；当前会话竖排实证正常（`EDIT title focus via=capsule` 与 `EDIT title session begin len=35` 成对出现）；卡死前可见尾迹只有滚动与 DRAG 行（scrollY 在 40–173 间，坞处于紧凑条件）。

## 一、定因（证据分级）

### 候选 1：dockCompact 活派生在会话起点翻转坞结构 —— proven（结构，代码确证）

改前坞分支是活公式：

```swift
private var dockCompact: Bool {
    scroll.scrollY > 30 && !titleFocused
}
```

`!titleFocused` 一项是 0.9.54 标题批为「编辑期抑制滚动翻转」引入的，但它实现的是**每帧现算的否定**，不是冻结：

- 紧凑态（scrollY > 30、未聚焦）下点按覆盖层（或直点字段）置 `titleFocused = true`，**同一次视图更新内**公式由真翻假；
- `headerOverlay` 以 `if dockCompact` 在 HStack（横排）/ VStack（竖排）两分支间选一，`titleCapsule` 在两分支中处于**不同结构位置**——SwiftUI 视图身份按位置定，分支切换即胶囊子树（含 TextField）销毁重建；
- 于是 `.focused($titleFocused)` 的目标视图，其结构身份是焦点值本身的函数（**自指涉**）：焦点刚授予的字段在自己的焦点事务中被销毁。字段销毁触发焦点回滚（titleFocused 被系统改回 false）→ 字段 `onChange(false)` 跑 `commitTitle()`（可写 `ui.titleDraft`，@Published）；回滚前若 `onChange(true)` 已跑，又写 `ui.titleBase`（EditorUI 的 @Published，整树重演算）——分支随即翻回紧凑、字段再重建，键盘呈现绑在一个已释放的第一响应者上。整条链在主线程事务内自激，页面冻死。

与报障形态逐项对应：竖排下公式恒假（scrollY ≤ 30），置焦前后不翻转、字段身份连续，故独正常（且 session begin 正常落盘）；横排下置焦必翻转，故点按必卡死；上一会话「停在编辑页异常收尾」即冻死后强退。卡死的微观形态（AttributeGraph 更新环 / 焦点引擎重试 / 键盘 machinery 自旋何者为主）为 inferred——本机无真机分步复现与堆栈；但三种形态都以同一自指涉为必要条件，根治不依赖区分。

`via=capsule` 行为何可能未落盘：`DiagLog.log` 在主线程把条目入内存环，落盘走 `schedulePersist`（仅 error 级立即）——info 级的 via 行入环后若主线程随即冻死、进程被强杀，计划落盘永不执行，行随内存环丢失。此点为 inferred（与 DiagLog 代码口径一致），亦解释竖排会话的两行能成对留存（落盘调度正常完成）。

### 候选 2：capsuleWidth 量测反馈环 —— disproven（无独立环）

`capsuleWidth` 读 `measure.headerW`，其写者是 `headerOverlay` 背景 GeometryReader，量的是**页眉条自身宽度**（全宽 HStack、两端钮 + Spacer 锚定），由屏幕/坞宽决定，不随胶囊宽变化——不存在「量测→改宽→再量测」的回路。置焦瞬间 capsuleWidth 的变化（chrome 扣减、metaW 计入）是候选 1 分支翻转的**下游后果**，外加聚焦态显全文的既定量测口径，均为单向依赖。根治后 capsuleWidth 改读同一锁存分支（见下），其紧凑相关项在会话内同样冻结。

### 候选 3：两分支字段身份不连续 —— 候选 1 的组成项，非独立缺陷

两分支的结构位置差异属实，但非会话期翻转（滚动过 30）时字段未持焦点，销毁重建无害——该行为自坞双态落地以来多版本真机无恙。身份不连续只在「翻转由焦点事务本身触发」时致命，即候选 1。本批不重构两分支容器（保 [24]/[28] 既有形态锚），以锁存使会话期翻转不可达，致命组合即拆解。

放大项（非独立因）：body 上 `.animation(value: dockCompact)` 对结构换位做 0.25s 缓动、胶囊上 `.animation(value: capsuleWidth)` 0.2s——非会话翻转时同动画长期在位无恙，只在焦点事务中与销毁重建叠加加重病理；根治后会话内两值皆不变，动画不再介入焦点事务。

### Web 口径核对（S7 结构）

Web 的坞布局由 `ed_scroll` **信号**驱动（`rust/apps/web/src/editor/hooks/scroll.rs`）：标题编辑期滚动处理只记一行 `scrolled flip suppressed while editing title (S7)`、**根本不 set 该信号**，滚动量照常供其他联动消费；布局值因此冻结在会话起点（含紧凑态进入即整场紧凑），失焦后由后续滚动事件按当刻 y 归位。`title_controller.rs` 头注同口径（翻转不在输入类触发集内）。原生旧活公式与之的结构差：Web 是「被编辑冻结的锁存信号」，原生是「由（滚动， 编辑中）现算的函数」——后者在会话起点必然翻转，前者不可能。本批根治即把原生坞分支改成同构的锁存结构。

## 二、状态机（改前 → 改后）

改前（横排进入路径）：

```
紧凑稳态: scrollY>30, dockCompact=true（HStack 分支）, 覆盖层在位
点按 ──> titleFocused=true ──同更新──> dockCompact=false
     ──> 分支换 VStack、字段销毁 ──> 焦点回滚 titleFocused=false
     ──> commitTitle/titleBase 写 @Published、整树重演算
     ──> dockCompact=true、分支翻回、字段重建 ──> 主线程自旋/冻死
竖排进入: dockCompact 恒 false ──> 无翻转 ──> 正常（真机实证）
```

改后：

```
任意态进入会话: titleFocused=true ──> dockCompact 读锁存
  （= 会话起点那一刻的实时值，由出现/滚动/失焦三同步点
   保证非会话期恒等于实时）──> 分支不变、字段身份连续
会话中滚动: 锁存无写者 ──> 分支冻结（S7 抑制的结构落点）
失焦: dockCompact 回实时派生 ──> 按当刻 scrollY 归位
  （若与锁存不同，产生恰一行 dockflip 面包屑，src=scroll）
非会话滚动翻转: 与改前同形态（字段未持焦点，无害），逐次记行
```

## 三、改动清单（仅 `MomentApp.swift` 的 EditorHeaderView 段 + `verify_ios.sh`）

1. **实时派生拆名**：`liveDockCompact`（滚动过阈值），段内阈值字面仍仅此一处（T24-3 锁不破）。
2. **会话锁存**：新增嵌套 `DockSession: ObservableObject`（`@Published latchedCompact`、`flipCount`），以 `@StateObject` 承载——本工具链无 @State 宏插件（verify [2] 禁区），与 HeaderMeasure 同纪律（首版曾用 @State，被 [2] 当场拦下，已改）。
3. **坞分支改锁存派生**：`dockCompact = titleFocused ? dockSession.latchedCompact : liveDockCompact`，headerOverlay / capsuleWidth / 动画值三处消费点不变。
4. **同步三点**（锁存的全部写者，F28-3 封闭）：`onAppear` 初值同步；`onChange(of: scroll.scrollY)` 非会话期且值变化时同步；`onChange(of: titleFocused)` 失焦时同步归位。会话期内无写者——翻转在会话期结构性不可达，不是在消费点加守卫。
5. **面包屑**：`onChange(of: dockCompact)` 逐次翻转记 `EDIT dockflip compact=<0|1> src=<scroll|session> n=<累计计数>`（与 Web dockflip 逐翻转记行同口径；计数使风暴时任意一行即量级证据，src=session 的翻转行本身就是复发信号）；字段失焦记 `EDIT title session end`，与既有 via/session begin 凑成完整会话三行。
6. **零改动面**：titleCapsule 两分支调用与 compact 入参、meta 显隐、commitTitle/Esc/Enter/快照口径、字段常驻结构（[24] 全组断言保持绿）。

与在途批次的领地关系：U0 地基的 MomentApp 改动在 ListView 接线点与桥文件、附件批在 AttachmentRow/Radius——与本批 EditorHeaderView 段无 hunk 交叠，动工前已逐 hunk 核对 git diff。

## 四、断言（verify [28]，锁机制不锁数值）

`verify_ios.sh` 新增 [28] 组 F28-1…F28-5，本机自跑：**222 ✓**，余 2 ✗ 为既有 ipa 陈旧类（ipa 早于源码、产物语言包待重建——tree 构建自解，与 0.9.54 组版时同类）：

- F28-1 锁存单点派生：分支定义恰为锁存三元式、定义内不直读 scrollY、阈值与焦点同行的旧公式零残留、DockSession 载体在位；
- F28-2 同步三点在位且实时赋值恰三处；
- F28-3 写者封闭：经 `dockSession.latchedCompact =` 的赋值恰三行（类内初值不经此名）——第四个写者出现即红，会话期翻转由此封闭性保证不可达；
- F28-4 面包屑在位：dockflip 行 + 计数自增恰一处 + session end 行；
- F28-5 竖排/宽度零改动锚：两分支调用、meta 显隐不变，capsuleWidth 不直读锁存/实时（宽与形同源）。

[24] 组五项保持全绿（T24-3 的阈值字面一处、dockCompact 消费点、capsuleWidth 共用派生均未破）。Swift 编译级验证本机无 swiftc，随主线 tree 冒烟执行（改动为纯 SwiftUI 视图层状态重组，无新 API 面）。

## 五、真机终判点

1. **横排点按即编辑**：长笔记下滑至横排坞，点标题胶囊一次即升键盘、全文可编辑，无卡死；失焦后反复进出循环不失效。
2. **会话中滚动不翻转**：横排进入编辑后滚动正文，坞保持横排、键盘不掉、草稿不被腰斩；竖排进入后下滑过 30 同理保持竖排（与 0.9.54 冻结口径一致）。
3. **失焦归位**：横排编辑中滚回顶部再失焦，坞按当刻位置归位竖排；反之竖排编辑中滚到底再失焦，归位横排。
4. **竖排零回归**：竖排点按落焦、Enter 提交辞焦、Esc 还原、短标题直点字段，与 0.9.54 一致。
5. **Diag 复核（主线经桥 diag_tail）**：横排点按后应见 `EDIT title focus via=capsule` 与 `EDIT title session begin` 成对出现、会话期间**无** `EDIT dockflip ... src=session` 行；失焦见 `EDIT title session end`；dockflip 计数 n 应为个位数（正常滚动翻转量级），若 n 暴涨即风暴复发信号。
