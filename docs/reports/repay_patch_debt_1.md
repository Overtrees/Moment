# 补丁债偿还批一·事件面（repay_patch_debt_1）

日期：2026-11-28。基线：HEAD `eb78103`（0.9.66 已出包）。工单：docs/reports/audit_patch_debt.md §九偿还序第 1 批（事件面批），只执行该批四项：A-5（入树等待三写）、A-1（落焦定时重开）、A-7（菜单预建经验常数）、A-4（桥等在席轮询）。逐项一笔、笔笔可独立回滚。

**办结：4/4 项。** 总册四项引文（文件:行与形态）与代码现状逐项核对一致，无条目需更正；以下为回写注记与状态更新。

---

## A-5 入树等待三写收口 —— 已清（`b02de13`）

- **改动单点**：新文件 `MomentTreeWait.swift` 立共享工具 `ViewTreeWait`：等待者以（条件 + 动作 + 到期回调）注册，单枚 `CADisplayLink` 逐帧复查——复查节拍与布局生产同源（入树必发生在帧生产中、无帧链自动闲置），到期走各消费点自持的 onTimeout。三处消费点收口：
  - 转场宿主 `pushEditor`：探针未登记时的 0.05s×20 定时重入删除，改等 attach 落定后重入；到期语义不变（1s 预算 = 旧 20×0.05，`TRANSITION attach missing` 错误行保留）。`attachRetries` 字段整删。
  - 首页滚动探针 `HomeScrollProbe.ProbeView.tryAttach`：0.05s×20 重试删除，改等滚动视图入子树；到期静默降级不变（scrollOffset 保持 0、后续 update/入窗仍可再驱动）。达成与离窗（detach）均注销等待。
  - 拖拽锚点 `DragPressAnchor.Coordinator.attach`：单次主队列异步重试删除，改等祖先滚动视图出现后以最新 anchor（等待期间 update 只刷新 `pendingAnchor`）补注册；`drag-anchor-nosv` 留痕保留，detach 注销等待。
- **行为等价依据**：三处旧预算同为约 1s（锚点旧制为单次次周期重试、且后续 updateUIView 本就反复再驱动 attach——新制逐帧复查只更早达成、不晚于旧制的最坏情形）；各消费点的到期后果（留痕放弃 / 静默降级 / 留痕延后）逐项原样保留；注册的最早需求时点（长按 ≥480ms、转场呈现、滚动量测）均远晚于逐帧复查的最大一帧延迟。
- **构建接线**：新文件照拆分例接入 build-app2.sh 全 30 遍（29 遍次级输入 + 自有 primary 遍）+ `treewait.o` 链接行；遍数变化引发的计数锁五处随批改判并注沿革（MomentBridgeRestore / MomentUndo / MomentXSel / MomentXSelBridge / MomentSplashHost 29→30、MomentFontFactory 28→29）。
- **断言**：PD71-1（工具本体形态：DisplayLink + wait/cancel + tick 恰 1）、PD71-2（三标识零残留）、PD71-3（三消费点 wait 各恰 1 + 探针/锚点 cancel 在位）、PD71-4（构建接线 30 遍 + treewait.o ×2）。**负对照实做**：scratch 副本回潮 `asyncRetried` → PD71-2 计数 1 判红；整行摘除宿主 wait 调用 → PD71-3 计数 0 判红。

## A-1 落焦认领收口入窗回调单点 —— 已清（`683b474`）

- **改动单点**：认领尝试收口 `BlockTextView.attemptInitialClaim`（门开 + 意图在 + 本块为首个文本块三条件 + 投递），双触发面共用本体：更新轮（宿主开门 tick）与块视图入窗回调——`EditorTextView` 新增 `didMoveToWindow` 覆写与 `onDidMoveToWindow` 注入点，`installWindowClaim` 在 make/update 两处接线（window != nil 由回调点保证）。宿主 `transitionCompleted` 的 0.2s 无条件重开门整段删除，开门恒一次（completion 单点）。
- **行为等价依据**：旧重开门的唯一作用是「首拍更新未达块视图时再推一拍」；入窗回调是该情形的因果事件本身（视图未入窗 → 入窗瞬间补认领；视图未建 → 建后首轮 update 即见门开旗在、同点认领）。认领本体 `claimInitialFocus`（成功校验 + 有界重试 ≤3、§七设计内语义）与落点口径未动；意图旗已清（认领已成/已耗尽）时入窗回调同旧制一样不复活。
- **断言**：PD71-5（宿主 `openFocusGate()` 恰 1 + transitionCompleted 段内 `+ 0.2` 零残留）、PD71-6（EditorTextView 段内覆写/回调在位 + 尝试单点定义恰 1 + 接线恰 3）。**负对照实做**：整段摘除 didMoveToWindow 覆写 → 段内命中 0 判红。连带改判：T17-4 的认领条件字面随单点化失效，改锁 attemptInitialClaim 段内双旗同在（机制「认领必过门」不变，沿革注记在该条注释）。

## A-7 菜单预建改挂落定事件 —— 已清（`3acf60d`）

- **改动单点**：`EditorModel` 增落定发布 `settleTick` + `noteTransitionSettled()`；宿主在转场落定单点 `transitionCompleted`（push completion / 关联替换同点）发布。EditorView 双消费：`onChange(of: editor.settleTick)` 落定拍建整树；onAppear 时已落定（关联替换等 settleTick 已 >0）即建。onAppear + 0.6s 定时预建整段删除；打开抢先兜底（showMenu onChange 即时建、首开无动画）与常驻挂载/opacity 命中口径不变。
- **行为等价依据**：旧 0.6s 常数的构成是「转场窗 0.35s + settle 打点窗 0.5s」的经验上界，onAppear 实际在转场前构建期即触发、与落定无因果；新触发点即落定本身，预建恒在落定后、稳态打开前（用户打开恒晚于落定或经兜底即时建），进出场动画口径不变。
- **断言**：PD71-7（`now() + 0.6` 全仓恒 1——唯一存留为 scheduleSave 防抖，§七设计内语义；预建常数回潮即变 2 判红）、PD71-8（发布面 + 宿主调用恰 1 + 编辑页双消费在位）。**负对照实做**：摘除宿主 `noteTransitionSettled()` 调用 → 计数 0 判红。

## A-4 桥等在席事件驱动 —— 已清（`8835641`）

- **改动单点**：`EditorSeatRegistry` 增变更发布单点 `publishSeatChange`（钩子 `onSeatChange` 发出全仓恰一处，seat/unseat 各调用发布一次）与等待者订阅面 `addSeatWaiter`/`removeSeatWaiter`（落定后逐个询问、满足自动注销；发布时先快照再询问，防等待者回调内注销与迭代相撞）。`BridgeNavigationChannel` 两等待收口 `awaitSeat` 骨架：先自查现状、未定论则等待者事件驱动重查 + 一枚到期定时，完成恒一次（finish 内等待者与定时互清）。100ms 递归轮询两份整删。
- **行为等价依据**：判定语义逐项不变——等在席：对上号 success、被他篇占走 memo_busy、2.5s 到期 nav_timeout；等注销：在席不再是目标篇即成（注销/被替换同算）、到期同码。旧轮询的 100ms 判读延迟由事件即时性取代（只更快定论、不改结论集合）；呈现异步性（探针未登记时宿主经入树等待重入）下 seat 登记仍是同步事实，等待者恒在其落定拍被唤醒。
- **断言**：PD71-9（`deadline - 0.1` 零残留 + addSeatWaiter/awaitSeat 定义各恰 1 + 注册恰 1）、PD71-10（钩子发出恰 1 + 发布点合计恰 3）。**负对照实做**：回潮 `deadline - 0.1` 残式 → 计数 1 判红。连带改判：F30-16 随发布单点化改锁发布形态（不变量「会话边界恰发一次钩子」不变，沿革注记在该条注释）。

---

## 总册条目状态更新清单

| 编号 | 旧状态 | 新状态 | 依据 |
|---|---|---|---|
| A-5 | 根治（待偿还） | **已清** | `b02de13` + PD71-1..4 |
| A-1 | 根治（待偿还） | **已清** | `683b474` + PD71-5/6 |
| A-7 | 根治（待偿还） | **已清** | `3acf60d` + PD71-7/8 |
| A-4 | 根治（待偿还） | **已清** | `8835641` + PD71-9/10 |

连带（非总册条目，属本批改判登记）：verify T17-4、F30-16 两条断言随机制单点化改判（机制不变、沿革在注）；构建计数锁五处随新文件遍数改判（见 A-5 节）。本批未触及：A-6（待裁，探针 120ms 复读原样保留）、A-9/A-10（§九.2 以后批次）、批二及以后各批。

## 验证（如实分账）

- 本机 verify_ios.sh 全量：**715 ✓ / 2 ✗**——2 红均为产物陈旧（ipa 早于源码、产物语言包未重建），本机无构建所致，下版 tree 组版自清；源码面断言全绿（基线 0.9.66 为 705 ✓，本批 +10 条 PD71 全绿、改判 2 条保持绿）。
- cargo test --workspace：**239 全过 / 20 套件**（本批未动 Rust 面，与基线一致）。
- Swift 语法：四改动文件（MomentTreeWait / MomentApp / MomentEditorTransition / MomentDrag）本机 swiftc -parse 全过。**类型级编译门未过**——留下一版 tree 组版冒烟（smoke_ios.sh），本报告不声称已编译。

## 留账

1. **Swift 编译门**：下一版组版在 tree 跑 smoke_ios.sh 全量（新文件 MomentTreeWait.swift 须入 tree 同步名单——组版批的 push_small 名单制注意新增此文件，build-app2.sh 已全遍登记）。
2. **对应景复跑**（总册 §九.1 要求）：装机后经桥自办复跑——新建篇落焦链（S1 / create_transition：TRANSITION 行 claim/kb 时点应仍满足 claim > anim、kb > claim）、桥 editor_open/editor_close（在席等待事件驱动后 open/close 回包时延与码集对读）、首页冷启与形态切换（滚动探针 attach 行在位）、拖拽景 drag_pickup_statemachine（锚点入树等待后注册不丢）。本批未装机、未跑景，证据上限如实止于源码断言 + parse。
3. 真机终判点：新建篇键盘升起单段动画体感（A-1）、菜单首开动画在位（A-7）归用户装机目检（矩阵 §7 人工保留面口径）。
