# 新建→编辑页过渡卡顿：呈现机制重构（0.9.50 暂记，版本未 bump）

用户 2026-11-27 真机判 0.9.48 未愈：「点新建后过渡到编辑页期间依旧卡顿停顿，像嵌套了两层过渡动画或接力式过渡，第一次卡在差不多中间、第二次接完」，并指示按口径红线重构、不再逐点打补丁。本批把「新建→编辑页」的呈现从 SwiftUI NavigationStack 的 push 里整体拿出，改由 UIKit 单一转场拥有。**状态：落码完成、未提交**；本机自检——新文件与 MomentApp.swift 均 parse 干净，build 同参数的 app 遍与 transition 遍本地 swift-frontend 全量类型检查**零错误**（.o 实产出、符号实证），verify 新增 [17] 组十项全绿，全表仅剩 ipa 陈旧、产物语言包两条已知产物红（构建后消除），[15]/[16] 未受影响。

## 一、查实账（证据分级）

证据源：用户 Diag `~/workspace/user/files/2026-11-27_12-31.log` 12:30 段（0.9.48 会话，连续 10 次新建）+ 现行源码通读。

| # | 事项 | 结论 | 分级 |
|---|---|---|---|
| 1 | 业务工作已干净 | CREATE settle 十连：create 1–6ms、listpass 1×3–8ms、avatar 0ms、bodypass 7–8、appear pre 26–52ms（含模型 init + 列表趟 + 首帧构建的总账）。被打点的业务段无一可解释「卡在中间」 | proven（Diag 实测） |
| 2 | 键盘动画与 push 动画重叠错峰 | 同十连 `CREATE kb dest2kb=36–67ms`：键盘于 dest 后约 40ms 即开始呈现，而系统 push 约 350ms——键盘动画（约 300ms）几乎全程压在 push 窗内，两动画并行且相位错开。用户「两层/接力式」体感与此逐项吻合（第一段=push 起步+键盘插入，第二段=push 收尾） | proven（时点）+ inferred（体感归因） |
| 3 | 编辑器在转场窗内才构建 | 旧机制 `navigationDestination(isPresented:)` 的目的地视图在 push 发起时才由 SwiftUI 构建并保留层级（第二轮排查 T3 已证）；构建绝对量已小（见 #1 的 pre 总账），但构建、首帧布局、头像贴入、认领全部挤在同一动画窗内发生，无隔离 | proven（机制）；量级 proven 小 |
| 4 | 列表侧新行插入与转场同窗共演 | 代码面：四新建入口在同一主线程回合内 `library.create()`（memos 发布 → List 差分插入新行）与 `nav.dest` 置位（push 发起）连续发生，无任何动画隔离（无 withAnimation 也无 disablesAnimations）；插入与 push 必在同一更新周期共演。UIKit List 在转场期对插入行是否另附行级动画，无端内证据 | 同窗共演 proven（代码）；行级动画 inferred |
| 5 | 首响应者中途变更迫使 SwiftUI 转场分段 | 认领在安装帧（push 第 0 帧布局内）执行 `becomeFirstResponder`，转场中途发生响应者变更 + 键盘入场，SwiftUI 转场是否因此重启/分段无端内可测手段；与症状吻合、且重构后此变更被整体移出转场窗，下轮 TRANSITION 行可反证 | inferred |
| 6 | 认领记账整场缺席（附带发现） | 0.9.48 会话全日志 grep：`CREATE claim` **零行**、`CREATE timing` 仅旧会话一行，而十次新建键盘皆起、settle 的 claim 段恒 `nams`（traceClaim 恒 0）。`recordCreateClaim` 三个出口中（成功/耗尽/已是第一响应者早退），仅「早退」分支与全部证据相容——即认领记账点本身不可靠。本批不改认领实现与记账函数，但把认领**驱动点**收归宿主单点（转场 completion 开门），TRANSITION 行复用同一戳记，下轮 Diag 无论如何能定案 | 缺席 proven；早退归因 inferred |

**判定**：卡顿不在任何被打点的业务段里（#1），在呈现机制的动画编排里（#2/#3/#4/#5）——继续在业务层打补丁无处可下手，必须换呈现机制本身。此即本批重构的依据。

## 二、row open 取舍：同一机制，一并切换

查代码后决定**新建与打开既有篇共用同一呈现机制（同一宿主、同一 push 路径）**，理由：

- 两路的呈现本体完全相同（同一个导航控制器 push 同一个 EditorView），旧代码里也共用一个 destination 分发；分开切换会留下两套呈现路径长期并存，正是「消费方打补丁」的变体。
- 打开既有篇同样有「目标页在转场窗内构建」的问题（长篇首帧构建更重，SCROLL open 的块数可达数百），共用机制后同样受益于首帧前置。
- 差异只收敛在参数面：kind（create/open/link）、是否带落焦意图（门控只对 create 生效）、新建回合的禁动画事务（只包 createAndOpen）。编辑器内部、数据层零改动面与新建路一致。

设置页**不**切换：它仍走 NavigationStack 的 destination（Dest 只剩 .settings），其内部子页（备份/手势/语言/诊断）层级关系不变——设置无落焦、无首帧重活，不在本症口径内，动它只增风险。

## 三、重构前后结构对照

| 面 | 旧（0.9.46–0.9.49） | 新（本批） |
|---|---|---|
| 呈现载体 | `ListView` 内 `NavigationStack` + `navigationDestination(isPresented:)` 按 `nav.dest` 分发 | 同一 UINavigationController 不变；编辑器改由 `EditorTransitionHost`（新文件 `MomentEditorTransition.swift`）以 `pushViewController` 承载 `EditorHostingController`。导航控制器经 `EditorNavProbe`（根视图背景探针，入窗后沿响应链登记）交给宿主 |
| 编辑器构建时点 | push 发起时 SwiftUI 在转场窗内构建 | push 前 `loadViewIfNeeded()` + 强制帧布局一趟，首轮 body 与块视图安装全部在转场窗外完成 |
| 初始落焦认领 | 安装帧（push 第 0 帧）`claimInitialFocus`，键盘与 push 全程重叠 | 认领加门 `EditorModel.focusGateOpen`：宿主在 `transitionCoordinator` completion（未取消）后 `openFocusGate()` 以 tick 触发一轮块视图更新，认领仍走 `claimInitialFocus` 单点实现（校验/重试/记账不变）；键盘在页面落定后单独升起。兜底：开门后 0.2s 旗仍在则再推一拍 |
| 列表侧 | 建篇发布与 push 同回合裸奔，行插入与转场同窗共演 | 四新建入口收敛 `ListView.createAndOpen()`，整回合包 `Transaction(disablesAnimations)`：新行插入无动画；呈现发起与 dest 戳（宿主内 `noteCreateDest()` 单点调用）仍同回合 |
| 入口形态 | 新建四处同形态五步散写、打开三处散写、关联打开在 destination 构建器里换 dest | 全部收敛为 `createAndOpen()` / `openMemo(_:)` / `openLinkedMemo(_:)` 三个 ListView 辅助函数 → 宿主 `pushEditor` / `replaceTopEditor` |
| 关联打开（反链/wiki） | 同层换 dest 内容：无 push 动画、EditorView 整替、返回直达列表 | `setViewControllers` 无动画替换栈顶承载控制器：同为无动画整替、返回直达列表、新 EditorView 全量新建（onAppear 的 `APP row open` 留痕口径不变） |
| 图片页 | EditorView 内 `navigationDestination` 挂首页栈（imageTarget 绑定） | 宿主订阅 `editor.$imageTarget`：置位 push `ImageHostingController`、清空 pop、页面关闭反向清空 imageTarget——与旧绑定语义逐项等价 |
| 返回 | 页眉钮/图片页钮走环境 `dismiss()`（栈内 pop） | 闭包直达宿主 pop：`EditorView.onClose` → 页眉 `EditorHeaderView.onBack`（commitTitle/saveNow 顺序不变、最后一步换 pop）；图片页 `ImagePageView.onClose` 同理。dismiss 保留为无闭包注入时的兜底（其他构造点行为不变）。侧滑返回为同一导航控制器的系统手势，原样保留 |
| 系统导航栏 | 全应用隐藏（SwiftUI toolbar 口径） | 承载控制器 `viewWillAppear` 显式 `setNavigationBarHidden(true, animated: false)`，同口径确定性保住 |
| 打点 | CREATE 七点（dest/listpass/avatar/claim/kb/bodypass/settle） | CREATE 全保留不动；**新增 TRANSITION 一行**（宿主出）：`TRANSITION id= kind= build= anim= claim= kb=`，四时点相对 push 起点 ms——build=首帧前置构建段、anim=纯转场动画段（构建止→转场止）、claim/kb 复用 CREATE 戳（仅新建篇有戳，其余 kind 记 na）。判据：anim ≈ 系统 push 时长且 claim > anim、kb > claim，即证「单段动画、认领在落定后」 |

## 四、退役清单（零残留，grep 实证）

- `ListView.Dest.editor` 枚举case 与 destination 构建器的 editor 分支（含关联打开的换 dest 回调）——`case .editor` / `nav.dest = .editor` 全仓 **0 命中**。
- EditorView 内图片页 `navigationDestination` 整段——`ImagePageView(` 构造点在 MomentApp.swift 内 **0 命中**（只剩宿主文件构造与结构体定义）。
- 四处新建散写 + 三处打开散写 + 四处 `ed.noteCreateDest()` 调用——收敛后 `wantsInitialFocus = true` 全文件恰 **1** 处（createAndOpen），`noteCreateDest()` 只剩定义 + 宿主单点调用。
- BlockTextView/EditorView 中描述「安装帧认领」的过时注释已按新口径改写（注释即文档，不留误导）。

编辑器内部（块编辑/滚动/菜单/底表等）、数据层、Library、CREATE 既有打点函数体**未动**；唯一例外是 settle 的 claim 段输出规范化（下节）与 EditorModel 新增门字段（`focusGateOpen`/`focusGateTick`/`openFocusGate`，纯新增）。

## 五、settle claim 段规范化

按任务口径对回 fix 文档形态：`recordCreateClaim` 新增存 `traceClaimOk`/`traceClaimInWindow` 两位；settle 的 claim 段由旧 `claim=<ms>ms`（未达时印成 `claim=nams`、不可判读）改为预计算 `claimSeg`：已认领输出 `claim=ok<0/1>/inwindow<0/1>`（与 `CREATE claim` 行同形态），未达输出 `claim=na`。`CREATE timing` 的 focus 段（dest→claim 的 ms 值）是计时行本义，保留不动。

## 六、verify 断言（新增 [17] 组，T17-1…T17-10，本机实跑全绿）

| 断言 | 锁什么 |
|---|---|
| T17-1 | 宿主文件在位 + build-app2.sh 含其编译遍与 transition.o 链接项 |
| T17-2 | 宿主以 `pushViewController` 呈现 + `transitionCoordinator` 落点 |
| T17-3 | 首帧前置（`loadViewIfNeeded` + `layoutIfNeeded`）在位 |
| T17-4 | 认领门三点齐：`openFocusGate` 定义、块视图认领条件含 `focusGateOpen`、宿主 completion 后调用 |
| T17-5 | 旧路径零残留：代码行无 `nav.dest = .editor`、无 `case .editor` |
| T17-6 | 新建收敛：`wantsInitialFocus = true` 计数恰 1 + `createAndOpen` 在位 |
| T17-7 | TRANSITION 打点行在位 |
| T17-8 | settle claim 段 `claimSeg` 在位 + 旧 ms 形态零残留 |
| T17-9 | 图片页只在宿主构造 + `onClose`/`onBack: onClose` 接线在位 |
| T17-10 | 新建回合 `disablesAnimations` 事务在位 |

构建集成：`build-app2.sh` 现 13 遍——转场文件加为全部 12 个既有遍（含 MCP 桥六遍）的次级输入（MomentApp 在每遍的次级集里引用宿主符号，缺一遍即该遍符号不可见），并新增其主遍出 `transition.o`、链接行已含。`push_small.py` 同步名单已加 `MomentEditorTransition.swift`（现 21 项）。与 MCP M1 线的共改文件（build-app2.sh / verify_ios.sh / MomentApp.swift）已按区域错开：本批只动导航/呈现/编辑器入口区，未碰设置区与桥文件；M1 的 [16] 组与桥六遍在最终 verify 中均保持绿。

## 七、行为等价与残余风险

- 等价面：落点（首个文本块、块首光标）、认领校验与重试、CREATE 七点时序语义、返回手势与导航深度、关联打开的无动画整替、图片页三向语义、设置页全家、编辑器 onAppear/onDisappear 留痕与 saveNow 时点——逐项按第三节对照保持。
- 已知微差（登记）：① 开门 tick 会给 EditorView 多带 1–2 轮 body（bodypass 计数相应 +1~2，发生在转场落定后、非转场窗内）；② 探针未登记时 push 有界重试（20×50ms，理论上只在首帧前一瞬，超限记 `TRANSITION attach missing` 错误行放弃，不静默）。
- 未定案（留给下轮 Diag）：第一节 #5（转场分段机制）与 #6（认领记账早退归因）均为 inferred——本批结构上已把两者成因移出转场窗，下轮真机导出看 TRANSITION 行（anim/claim/kb 时序）与 CREATE claim 行是否回归，即可同时结案或证伪。
- 真机终判仍归用户：新建一篇的体感是否单段顺滑、TRANSITION 行四时点是否如判据。本批未 bump 版本号（0.9.49 冒烟中；落版号主线定，暂记 0.9.50），未提交。
