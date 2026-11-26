# 确诊：设置页返回后列表顶栏实心栏遮挡（页面过渡机制不一致）

日期：2026-11-24。报告人：顶栏排查线。用户拍板处置口径：全应用页面过渡收敛到编辑页已验证机制（2026-11-23 晚根治集），设置页等组件页全部接入同一机制，禁止单点补丁。

## 1. 症状与真机证据（proven）

用户真机截图（iPhone，1179×2556px = 393×852pt，3x）逐行像素剖面：

- 屏 y 0–58pt：rgb(242,241,246)——状态栏带区为根色 242，正常。
- 白色卡片（新建卡，文案「现在，点击记录你的瞬间」）顶边在**布局视口顶（屏 y=59pt）被平切**：x=60pt 列白色自 y59pt 起、圆角上半缺失；卡内文字仅下半截可见（字形下半落在屏 y≈59–70pt 带内）。
- 紧凑标题胶囊「此刻」在屏 y≈66–98pt 完整显形（fixed 于布局坐标 top 7pt）——紧凑态成立 ⟺ scroll_y 信号 > 30pt。
- 置顶节头屏 y≈113–130pt、置顶卡 y140–206pt；右侧滚动条拇指在场。
- 按列表静止几何（标题块 ≈86pt + 搜索区 + 新建卡 ≈48pt + 节头）反推：截图时文档滚动位 ≈ **105–120pt**（取 ~110pt）。

判定：返回后的列表停在一个中途滚动位（~110pt），内容整体上移、顶部被视口顶截断——用户所见「实心栏压顶」的实物即被截断的标题/搜索区与停在半途的列表，不是某个新画的元素。进入设置前的列表滚动值 unknown（本会话同型操作在 12:32 Diag 中有 127/227 的列表滚动存档）：若进入前为 0，则 110pt 全为伪位移；若为 ~227，则 110 为钳制残值。两种情形都指向同一结论——**组件页路径不管理滚动位，返回值由浏览器对文档高度骤变的钳制/恢复行为决定，不确定**。

## 2. box 复现（Chromium 口径，旁证）

Simular Box 对现行构建 d14763baef（8096）以 Playwright 复现列表→设置→列表两轮往返：返回后 +120ms/+420ms/+1120ms/+3120ms 逐行像素剖面与列表静止基线**无差异**，`.page-leaving` 均已摘除，Diag 尾与真机同型（`TRANS settings -> leaving` 后只有一行 ROOTSET、无 committed/POST/CENSUS）。

分级：Chromium 无 iOS 的视口分层与滚动钳制行为，不复现本缺陷；此结果只证明 DOM 结构层无残留、摘除计时在 Chromium 下守时。缺陷定性以真机截图（§1）为准，终判亦归真机。

## 3. 机制差异表（根因候选全集）

编辑页过渡（昨晚根治集，参照机制）vs 组件页过渡（设置/备份/语言/诊断/图片页，现行 `Nav::go` + 栈式快照）：

| # | 维度 | 编辑页（参照） | 组件页（现状） |
|---|---|---|---|
| D1 | 提交点 | 页面状态保持到出场播完，卸载计时到时在同一任务内提交（`arm_unload` editor 路） | `page.set(target)` 在导航瞬间即刻提交 |
| D2 | 挂载/翻色时序 | 提交帧内：旧页卸载、新页挂载、根色翻转同属一次渲染提交（串行同帧） | 新页即刻挂载，旧页快照再存活 280ms；根色随页面状态即刻翻转，与旧页出场解耦（即 2026-11-23 白带审计定罪的同型结构差） |
| D3 | 离页载体 | 离页页**本体**在流内以当前页身份播 slideOut（同实例、状态不丢） | 旧页本体即刻卸载，另在 fixed `.page-leaving` 层（inset:0、z 0）重挂一份 closing 快照（新实例、状态重演） |
| D4 | 滚动保存/恢复 | 进入时 `open_memo` 存列表滚动并回顶；返回提交点双 rAF 恢复保存值 | **全无**：进入不存、不回顶；返回不恢复。窗口滚动为全应用共享，短页（设置内容 ≈697pt、根 min-height 100vh=735pt）挂载期间由浏览器钳制，返回后停在钳制残值（§1 实测 ~110pt） |
| D5 | 提交后普查 | 提交点打 `TRANS … -> committed` + POST（computed 实测）+ CENSUS（残留普查）+ LATE 300/1000/3000 三发 | 离页层摘除**静默**（arm_unload 非编辑路只 set None、无任何打点）——两份真机 Diag 均只见 leaving + ROOTSET 即此 |
| D6 | 出场动画 | 本体 `.editor-stage.leaving` 在流内 slideOut | 快照内容层 `.page-slide-out`（fill forwards，translateX 16px/opacity .92）；根层与返回钮/胶囊不参与动画，靠 `.page-leaving` 的层叠上下文 + overflow hidden 困住 fixed 子元素 |
| D7 | 顶替/重入 | 重开同 id 实例续用、异 id 换键重挂，代际推进作废旧计时 | leaving 单槽被下一跳静默顶替；快照组件 use_hook 重跑（如 DiagView 快照重读日志、SettingsView 快照重打 enter 日志的抑制靠 closing 标志逐个兜） |
| D8 | 子页链 | 不适用（编辑页无子页） | 设置→备份/语言/诊断及其返回全部走同一快照机制，缺陷面覆盖全部组件页间过渡；图片页（灯箱页化新页）亦建于此机制之上（LeavingPage 增 img 快照载荷、返回时即刻双 rAF 恢复编辑器滚动——恢复点在发起任务而非提交点，同族偏差） |

## 4. 根因判定

- **proven**：应用内存在两套页面过渡机制；组件页路径（D1–D8）与编辑页已验证机制全面不一致。设置页往返后列表滚动位无人管理（D4），真机实测停在 ~110pt 的非进入值（§1），即本次可见缺陷的直接成因。
- **proven**：组件页提交无结果侧打点（D5），缺陷在 Diag 中不可见——与诊断红线「只记意图不记结果」的既往教训同型。
- **inferred**：~110pt 的具体成数由 iOS 对短文档的滚动钳制/恢复启发式给出（进入前滚动值 unknown，无法唯一分解）；机制收敛后滚动由应用显式保存/恢复，此项不再影响行为。
- 与前科的区别：返回列表白带（已根治）是列表挂载与根色翻转解耦——D2 与之同型但发生在组件页路径上，编辑页的串行同帧锁（verify 第 9 节、probe_page_transitions ④ 组）从未覆盖此路径；确认弹窗实心栏是 sheetIn 位移动画与全幅渲染冲突，机制不同，不适用。

## 5. 落码方案（统一到编辑页机制，逐笔）

总原则：`Nav` 只留两类导航——**前进**（即刻挂载新页、同提交卸载旧页、进场 slideIn，与 `open_memo` 同形）与**返回**（`go_back`：本页本体在流内以 closing 播 slideOut、页面状态保持到出场播完才在提交任务内翻转，与 `begin_editor_leaving` 同形）。快照离页层整套退役。

1. **笔 1（Nav 骨架）**：`arm_unload` 非编辑路改为提交语义——到时任务内清 leaving、翻 page 到目标、打 `TRANS {name} -> committed gen={g}` + POST + CENSUS + LATE×3（与编辑路同口径，diag 补齐）；新增 `begin_page_leaving(target)`（记 leaving 条目 {name=当前页, dest, gen}、当前页渲染 closing、不翻 page）与 `go_back(target)` 入口；`go` 收窄为前进专用（不再入栈）。
2. **笔 2（调用点收敛）**：全部 on_back 改走 `go_back`（设置→列表、备份/语言/诊断→设置、图片→编辑）；前进点保持 `go`（列表→设置、设置→备份/语言/诊断）。当前页渲染的 closing 由 leaving 条目与本页名匹配派生（SettingsView/BackupView/LanguageView/DiagView/ImagePage 的 closing prop 语义由「快照」转为「本页出场中」，组件本体不改）。
3. **笔 3（滚动收口）**：自列表进入组件页时与 open_memo 同形——存列表滚动至共享 `list_scroll_restore` 并回顶；`go_back` 提交点在目标为列表时双 rAF 恢复该值（复用 arm_unload 编辑路的恢复形态）。图片页返回的 img_restore 恢复改挂同一提交点（删其发起任务内的即刻恢复）。
4. **笔 4（退役清零）**：删 `stack_current_page`、`render_leaving_page`、App 的 `.page-leaving` 渲染块、LeavingPage 的 img 快照载荷、base.css 的 `.page-leaving` 规则；grep 证明产品码零残留（CENSUS 的 `leaving=` 计数保留为恒 0 哨兵）。
5. **笔 5（verify 锁）**：verify_rustweb.sh 新增第 12 节——产品码无 `page-leaving`/`stack_current_page`/`render_leaving_page`；on_back 调用点全部经 `go_back`；提交点含组件页 committed 打点。落锁后做可变红自证（临时回退一处应变红、复原转绿）。
6. **笔 6（探针）**：probe_page_transitions 新增 ⑤⑥⑦ 段（见 §6），注册不变（脚本已在 run_all_tests 名单内），TESTING.md 补登记。

调度约束：灯箱页线已落两笔（aad1179/26642b1），本线落码前以 git log 为准确认其收尾（探针笔）已落或工作树无其未提交改动，再基于新树逐笔落码；同树只 add 自有文件/自有 hunk。

## 6. 探针判据（新增段）

- **⑤ 设置→列表·串行同帧组**（同 ④ 口径）：出场窗口内列表不挂载（`.page-current` 内无 `.page-enter`）、设置本页在流内播 slideOut（slideOutToRight currentTime 推进）、全程无 `.page-leaving` 节点；提交帧设置卸载与列表挂载同帧（±1）；Diag 含 `TRANS settings -> committed` 行且其后 CENSUS `leaving=0`。
- **⑥ 滚动保存/恢复**：(a) 列表滚至 150 → 进设置（断言设置内 scrollY=0）→ 返回 → 落定 scrollY=150±1，且返回落定后顶部像素剖面（中心列 RLE）与进入前同滚动位剖面一致；(b) 列表在 0 → 往返 → 落定 scrollY=0、剖面与静止基线一致（用户本次路径）。
- **⑦ 组件页链**：设置→备份（前进即刻交换、无快照层）→返回设置（go_back 出场+提交打点齐）→返回列表，全程 `.page-leaving` 计数恒 0、每跳 committed 行齐。

## 7. 剩余终判

- box/Chromium 口径只锁事件序、结构不变量与滚动数值；iOS 钳制行为测不到——统一后行为由应用显式管理，Chromium 判据即全量判据，但「顶栏不再被截断」的最终确认仍归用户真机（部署后看一眼设置往返即可）。
