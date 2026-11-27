# 0.9.57 首页三回归 + 焦点泄漏全面排查根治（fix_home_regressions_0957）

用户真机实报（0.9.57 装机）四症：S1 编辑页点完成胶囊 ✓、键盘收起后返回首页，首页自弹键盘；S2 首页搜索胶囊仍点不了；S3 首页头像与搜索胶囊不见了；S4 时间流分组内图文卡↔文本卡上下间距仍偏大。定性以 0.9.57 出货代码（HEAD d540d89）为准，落码在现行工作树（逐 hunk 避让在途批，完工多重集对账零丢失）。未提交、未 bump，随 0.9.58 组版。

## 一、共根图（先于逐症）

### 图 1 · 首页页眉合成

```
根 ZStack(alignment:.top)
├─ List（窄屏）/ gridHome（宽屏）        ← 滚动内容
├─ header                                ← 悬浮页眉（无条件在场）
│   └─ ZStack
│       ├─ HStack[ 头像 Button | Spacer | searchCapsule ]
│       └─ CompactTitle Button（顶层；窄幅居中，静止时命中关闭）
└─ undoToast（仅删除待撤销时）
```

页眉两元素的**可见性与命中由同一个量决定**：`compactP = clamp(nav.scrollOffset / 30, 0, 1)`——头像 opacity = compactP≥1 ? 0 : 1−0.3p、命中 = p<0.5；胶囊 opacity = 1−p、命中 = p<0.5；CompactTitle 反相（p≥1 才现）。除此之外全仓无第二处能隐藏头像或关掉胶囊命中：header 无条件构建、AvatarView 恒渲染（自定义图或恐龙回退）、CompactTitle 静止时命中关闭且幅宽不覆胶囊位。**S2 与 S3 必然同源于 scrollOffset 的输入端**，与胶囊自身的两层结构无关（0.9.57 的字段常驻修复机制本身成立，病灶在其上游）。

scrollOffset 的旧来源 = 基线捕获制：spacerRow 几何首读定基线 `firstRowMinY`（终生只采一次、仅形态切换时重采），scrollOffset = max(0, 基线 − 当前 minY)。该制有结构性缺陷：基线本应在「静止于顶」时采，却在启动首帧（导航栏/安全区未定型）或导航转场（几何未定帧）被首读定死；误差 ≥15pt 胶囊即被命中门关死（S2），≥30pt 头像与胶囊整隐（S3），且**无任何重采/恢复路径、无一行 Diag**——紧凑态为何卡死在旧版不可判读。具体是哪一帧毒化属设备时序，源码不可定（unknown）；毒化机制与后果链为 proven。

### 图 2 · 全 App 搜索焦点状态机

- 置焦写点全集（proven，含 F30-10 计数锁）：`searchFocused = true` 只有 `activateSearch()` 一处，调用者只有收起态触发层 Button。字段本体被点按置焦仅在已展开（字段可命中）时成立、非入口。
- 辞焦写点全集：onSubmit（src=submit）、清除钮（src=clear）、`resignSearch`（src=nav：新建/打开/头像/紧凑标题四手指路径）、系统侧辞焦（滚动收起等，src=system 经 FocusState 同步）。
- 编辑器呈现路径全集：手指（openMemo/createAndOpen——均先经 resignSearch ✓）、**桥 `BridgeNavigationChannel.requestOpen` 直调 `host.pushEditor`——不经 resignSearch ✗**、关联打开 replaceTopEditor（已在编辑器内、与首页焦点无关但同经 seat）。
- 平台行为：@FocusState 为焦点单一真相，承载层级被 push 覆盖期间状态保留，pop 后若仍为 true 则被焦点系统重新施加、字段重获第一响应者、键盘自升。

## 二、逐症定性与根治

### S1 焦点泄漏 —— 边界不变量缺失（机制 proven、具体触发路径 inferred）

**定性**：`searchFocused = true` 的写点唯一（proven），手指路径全辞焦（proven）；但桥路径直调宿主 push、不辞焦（proven，源码坐实）——resignSearch 只是散落在各手指入口的点写，**「搜索焦点不与编辑器会话共存」从来不是被强制的不变量**，只靠每条路径自觉。一旦焦点因任何非手指路径（桥 editor_open 在本机为活路径：装后自检与日常桥操作均经它开编辑器；2026-11-27 晚用户已重配对全授 read+write+ops，桥开编辑器属真实工作流）残存于编辑器之下，pop 返回时被重新施加，即「无人点搜索、首页自弹键盘」。用户本次具体经哪条路径触发不可考（unknown），但洞是结构性的：关闭方式必须是边界收口而非逐路径补辞焦。

**根治**（会话边界单点）：
- `EditorSeatRegistry` 增 `onSeatChange` 钩子：seat/unseat（全部呈现路径的单点收口——宿主 pushEditor/replaceTopEditor 均经 seat）各恰一处发出。
- ListView 在探针接线点（与桥通道同点位、幂等覆盖写、恒指向现行实例）登记钩子：在席开始即 `resignSearch(src: "seat")`——与手指路径共用同一辞焦本体（resignSearch 增 src 形参、缺省 "nav"，旧调用点零改动），Diag 归因链完整（close 行带 src=seat）。
- 效果：无论焦点由何路径置位、编辑器由何路径打开，会话开始瞬间焦点必收敛；返回首页无可重施加的残存焦点。断言 F30-16 锁此结构（钩子双发点计数、登记在位、seat 调用恰一处、同本体签名）。

### S2/S3 胶囊点不了 / 头像与胶囊不见 —— 量测源毒化（类别 proven）

**S3 定性到类别**：没渲染 ✗（header 无条件、AvatarView 恒渲染）、零尺寸 ✗（页眉框高恒 82）、被遮挡 ✗（header 居根 ZStack 顶层，CompactTitle 静止命中关且不覆胶囊位）、**被状态条件关掉 ✓**——compactP 卡在高位时 opacity=0 + 命中关，呈现为「只剩『此刻』小胶囊」。S2 同门：命中需 compactP<0.5（距顶 <15pt），基线一偏即恒关。

**根治**（量测换源，基线制整套退役）：新增 `HomeScrollProbe`（与 EditorNavProbe 同点位族的 UIViewRepresentable），直读承载滚动视图真值：距顶量 = max(0, contentOffset.y + adjustedContentInset.top)，KVO 双观察（contentOffset/adjustedContentInset），静止于顶恒 0、下拉过冲钳 0——**量测对象即所需量本身，无基线、无捕获窗、无可毒化状态**。搜索域经响应链限于自身宿主控制器子树（编辑器/设置的滚动视图不入域）；被编辑器覆盖时自动 detach、返回时重挂直读现值（返回瞬间的紧凑态由滚动视图真值决定）；形态切换换滚动视图时 updateUIView + 有界重试（20×50ms，与宿主 attachRetries 同打法）重找；找不到时 scrollOffset 保持 0、页眉恒展开（无害降级），不猜基线；挂载记 Diag `APP home scrollprobe attach inset=<n>`。新增紧凑迁移打点 `APP home compact <0|1> offset=<n>`（与编辑页 dockflip 同式）——此后紧凑态卡死类问题在 Diag 一行可判。

**退役零残留**：`NavState.firstRowMinY` 字段、共享 `probeAction`、spacerRow 与网格占位行的 onGeometryChange、List 与 gridHome 的 `.coordinateSpace(name:"momentList")`（全仓仅旧探针消费）整套删除，grep 计数归零由 F30-17 锁。spacerRow/网格占位回归纯占位（高度账 132/135 不动）。scrollOffset 写点收敛为恰 2（探针接线 + 形态切换归零），F30-17 计数锁。

### S4 图/文交界间距 —— 账面误记（proven，逐项核正）

0.9.57 的修复（分隔行 insets 归零）只治了「默认继承」段，账面本身是错的。逐项重核 Web 真源（base.css + main.rs/list.rs DOM）：

| 构成项 | Web 真值 | 出处 |
|---|---|---|
| 图卡 margin-bottom | **0**（卡在 .swipe-wrapper 内恒为末子，`:last-child` 归零） | base.css:191-192、list.rs:1239 起 DOM 序 |
| .swipe-wrapper margin-bottom | 6 | base.css:118 |
| .gap-16 高 | 16 | base.css:205、main.rs:2505 插入点 |
| 文卡侧 margin-top | 0（.list-item 无 margin） | base.css:150 |
| **卡缘到卡缘合计** | **22** | |

旧账「margin 24 + gap 16 = 40」的 24 是 `.list-group` 的**组间** margin-bottom（base.css:116），被误记到组内子列交界上；分隔行高 34 即由错账反推（40−3−3）。原生实测构成（修前）= 卡行 inset 3 + 分隔行 34 + inset 3 = 40，比 Web 多 18——与用户「归零后仍偏大」严丝合缝。

**根治**：分隔行高 34 → **16**（insets 3+3 顶 Web 的 wrapper margin 6、与子列内卡间距同值同源；本行只补 gap-16 的 16 本体），合成 3+16+3 = 22 = Web。F30-14 改锚 22 并把逐项出处写进断言注释（旧锚锁 40 是「断言锁错账面」的又一实例，一并改判）。宽屏网格无此交界（Web `.container .gap-16{display:none}`、原生网格两子列间亦无分隔行，仅 grid gap 14），不动。

## 三、落码清单

- `MomentApp.swift`：新增 HomeScrollProbe；NavState 删基线字段；body 接探针 + 在席钩子登记 + compact 迁移打点；resignSearch 增 src 形参；分隔行高 16 + 注释账改写；spacerRow/网格占位去量测；两处 momentList 坐标空间删除；probeAction 删除；syncHomeSize 去基线重置。
- `MomentEditorTransition.swift`：EditorSeatRegistry 增 onSeatChange 钩子（seat/unseat 各一发点）。
- `verify_ios.sh`：F30-2 计数口径更新（无参调用 4）、F30-14 改锚 22、新增 F30-16（在席边界）/F30-17（距顶量测机制）。

## 四、自检

- verify 全量：**344 ✓ / 2 ✗**，[30] 组 17 条全绿（含新增 F30-16/17 与改判 F30-2/14）；2 ✗ 为既有产物陈旧（ipa 早于源码、产物语言包待构建），tree 构建自解，非本批。
- 类型检查：MomentApp primary 遍 **零错误**（本批全部结构落码在位时跑通，.o 14.4MB 产出；仅 3 条既有 warning、均不在改动区）；MomentEditorTransition primary 遍零错误。其后一行的探针小改（detach 重置重试计数）后本机复跑受阻：先内存挤压 SIGBUS 两次（可用内存 ~200MB，本机已知形态），再遇同树兄弟批（DT 布局韧性）在途半成品——其 error 全在编辑器菜单领地（f34/f17 声明未就位，11764–12219 行），本批领地（ListView/探针/注册表）各跑次零 error；正式把关随 0.9.58 组版 tree 全量冒烟。
- 并发纪律：开工全树 diff 快照（9,689 行）与完工快照做已删行多重集对账——MomentApp/verify/build 脚本/中继/Web 侧五文件 missing=0，他人在途 hunk 零丢失；本批只动 MomentApp.swift、MomentEditorTransition.swift、verify_ios.sh 三文件。

## 五、真机终判点（按用户复现路径）

1. **S1**：首页展开搜索（键盘升起）→ 点开任意一篇 → 编辑 → 点 ✓（键盘收起）→ 返回首页：键盘**不得**再升、胶囊已收起。再以桥 editor_open 开一篇重复一轮（桥路径为原洞所在）：同预期。Diag 判读：seat register 同窗应有 `APP search capsule close src=seat`。
2. **S2**：冷启静止于顶，点搜索胶囊：键盘升起、胶囊展开（Diag 三段齐：tap → open）。此前点不动的形态不得复现。
3. **S3**：冷启首页头像与搜索胶囊在位；下滑过 30pt 两者整隐、『此刻』小胶囊现（Diag `APP home compact 1`），滑回顶即恢复（compact 0）、头像可点进设置、胶囊可点。编辑往返一轮后，页眉形态与列表实际滚动位一致、无「停在半路」的假紧凑。
4. **S4**：同组图/文交界量卡缘到卡缘 ≈ **22pt（66px @3x）**，对照修前 ≈40pt（120px @3x）、子列内卡间距 6pt（18px @3x）——交界应为「子列内间距 + 一段明显但克制的 16」。
