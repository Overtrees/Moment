# E4 编辑器健壮性批（F-18 / F-19① / F-17 / F-19② 量测）

- 时点：2026-11-27。基线 HEAD 6ce6cd8（0.9.57 组版全落定），落码门已过。未提交、未 bump，随下一组版。
- 依据：docs/reports/audit_editor_deep.md 域四健壮性各条（F-17/F-18/F-19）。
- 并发纪律：落码期间多批同仓在途（救援完整性批动 Library 段 + MomentLaunch/MomentRescue、Dynamic Type 批扫 EditorView/MdBlockView/ListView/Settings、设置收窄批、配对二维码批动 lang 包）。开工快照 diff 为空；本批 hunk 与各在途批逐段核对**零交叠**，完工复验他人 hunk 均在位未损（归属清单见 §6）。

---

## 1. F-18 切后台 flush（已落码）

**落点**：MomentApp.swift 的 App 级 `scenePhase` onChange（全仓唯一 scenePhase 消费点，原只做启动哨兵收尾）。`.background` 支内、清哨兵 `Library.launchSuspend()` **之前**新增：

```swift
if let mid = EditorSeatRegistry.shared.currentMemoId,
   EditorSeatRegistry.shared.saveNow() {
    DiagLog.shared.log(.info, "EDIT flush src=background memo=\(mid)")
}
```

- 走现行保存单点：注册表 `saveNow()` → `EditorModel.saveNow()`（取消 0.6s 防抖 work、立即 `persist(preparedItem())`），不另起保存路。与桥 editor_save_now、关编辑器 onDisappear 的 saveNow 同一消费面。
- 时机口径：`.background` 是 Web `pagehide`/`visibilitychange(hidden)` 的等价点；`.inactive` 瞬态（控制中心、来电横幅）不冲刷——进程尚在、无回收风险。
- 序：flush 在 launchSuspend 之前——先把数据落盘，再声明「正常收尾」，两序不可反转（断言 E4-1 含序锚）。

**标题连带定案登记（主线裁定，审计待裁定第 8 项）**：切后台 flush **只冲刷正文**，标题草稿不连带 commit，标题维持「手势返回才 commit」的现行口径。本落码天然合此裁定，无需额外代码：标题草稿活在 EditorView 的视图状态里，`EditorModel.title` 只持已提交值；`preparedItem()` 取的是模型标题——saveNow 落盘的是正文 + 已提交标题，进行中的草稿既不在模型内、也不会被 flush 写出。真机可观察后果见 §7 第 2 点。

## 2. F-19① 空文档打开守卫（已落码）

**落点**：`EditorModel.init`，在原子尾随物化之前：

- `blocks.isEmpty` 时补一个空段落块并记 `EDIT empty doc seeded memo=<id>`，物化随原子尾随同路 `DispatchQueue.main.async { scheduleSave() }` 异步落盘（只读态下 persist 自有 writeBlocked 闸，无副作用——与 init 既有原子物化同口径）。
- 空段节点形状单点化：新增 `EditorModel.emptyParagraphNode()` 工厂（定义恰一处），三处调用——打开守卫 / 原子尾随物化 / 删块兜底（deleteBlock 原字面量已收敛至工厂，形状逐字不变）。防三处字面漂移（断言 E4-2 计数锁：定义 1 / 调用 3）。
- 与 Web 口径对齐：Web 空 doc 有插段/落焦路径；原生删块路径本有同守卫（定案偏离登记 #7「删空补空段为原生守卫」），本批把打开路径补齐到同一口径，死页（无块 → 无落焦入口、focusHotZone 无锚）消除。

## 3. F-17 未知块呈现降级（已落码）

**落点**：BlockRow 分发链的兜底 else 支（原「{type} 块 · 后续轮支持」+ photo 图标的开发文案行，整支替换）：

- 呈现 = 类型标识小字（11pt medium、secondary，原文 type 串）+ 正文纯文本（14pt、T.textMain、左对齐），与同分发链内 embedCard 兜底段落的既有口径同族（纯文本、不露开发文案）；正文为空时只显类型标识。
- 正文来源 `block.text`：BlockState.init 以 children 文本拼接填充，未知块带文本子节点时天然在位（与 Web 降级纯文本同源）。
- Diag：`.onAppear` 内 `DiagLog.shared.logOnce("unknown-block:<type>", …)` 记 `EDIT unknown block type=<type> chars=<n>`——每 type 每进程一行（Web log_once 等价），补齐审计指出的「无 Diag 打点」。
- **只改呈现、不动数据**：`flushedNode()` 对非文本非列表块原样透传 node（审计已判字节级保真达标），本支不写 node、不触发保存改写；与数据层未知块保全机制对齐核对无误。「后续轮支持」字面全仓零残留（断言 E4-3）。

## 4. F-19② 超长文档：量测点与护栏裁定

### 4.1 现行结构（proven，源码级）

- 单列：`ScrollView { VStack { ForEach(editor.blocks) { BlockRow } } }`（MomentApp.swift contentArea）——**非 Lazy 的 VStack 全量构建**，打开即实例化全部行。
- 双栏：`blockColumn` 同为 VStack + ForEach 切片，两栏合计仍是全量。
- UITextView 实例数 ≈ **text + callout + listItems**：每个文本块一台 BlockTextView（UIViewRepresentable→UITextView）；callout 块内嵌一台；列表块逐项各一台（ListBlockView 实证）。原子块为 SwiftUI 视图、无 UITextView。
- 成本模型：首帧 = O(blocks) 行视图构建 + O(chars) 跨全部文本视图的文本布局（每台 UITextView 各自 sizeThatFits/排版），全程无 Lazy、无窗口化、无降级——千块级首帧无上限保护，与审计定性一致。

### 4.2 本批落的量测点（已落码）

`EditorModel.init` 末尾每篇一行普查（自变量面）：

```
EDIT open census memo=<id> blocks=N text=T callout=C listItems=L atomic=A unknown=U chars=CH init=<ms>ms
```

- init 计时基点 `initT0` 在 init 首行取（局部量，普查行出 init 全程 ms）。
- 因变量面复用既有 `TRANSITION id=<同 id> build=<ms>`（转场宿主的首帧前置构建段）——普查（构成）× build（耗时）按 memo id 对读，即 500/1000 块样本的完整量测对。
- unknown 字段顺带成为 F-17 的存量普查面（censusKnown 集与 BlockRow 分发链的非文本已知集对齐，注释已注明耦合点）。

### 4.3 护栏裁定：本批不落虚拟化（裁定与理由）

- 依审计自身排批口径（「先量测（500/1000 块样本）再立窗口化专项」）与红线「无量测不许直接上虚拟化大改」：本批交付的是**量测面**（4.2），设备侧数值尚待真机样本（§7 第 5 点）——在此之前动呈现结构属无据大改，不落。
- 专项方向（样本达标后按序评估）：(a) **混合静态呈现**——未编辑的文本块以 SwiftUI 文本呈现、落焦时才换 BlockTextView（本仓已有同构先例：MD 预览段落即「呈现态 SwiftUI 视图 + 点按换编辑面」，对拖拽帧读数/滚动探针/落焦热区的冲击最小，首选）；(b) LazyVStack 换装——滚动探针基线、整页落焦热区、拖拽让位三套机制都建立在「全行在位可量测」之上，换装即全数重做，风险最高；(c) 窗口化实例化——复杂度最高、与 (a) 收益重叠，末选。
- 建议判读阈值（供样本回来后主线裁）：1000 块样本 TRANSITION build ≳ 1000ms、或滚动体感经 Diag SCROLL 行证实掉帧成串 → 立 (a) 专项；build 在数百 ms 级且滚动无异常 → 维持全量、仅保留普查行作长期观测。

## 5. 断言（verify [32]，本机自跑）

新增组 [32] 四条，全绿：

- E4-1 flush 在位（注册表 saveNow + 打点 + **序锚**：scenePhase 段内 flush 行号 < launchSuspend 行号）。
- E4-2 空 doc 守卫 + 工厂单点（定义 1 / 调用 3 计数锁）。
- E4-3 未知块降级（「后续轮支持」全仓零残留 + logOnce 键在位）。
- E4-4 普查量测点在位（census 行 + initT0 + listItems 字段）。

全量自跑：**294 ✓**，✗ 5 条归属如下——`ipa 陈旧`、`产物语言包缺失或与 Web 源不一致` 为既有产物类（tree 构建自解，后者因在途二维码批刚改 lang 源）；`图片页判定高口径`、`J1-2 热区整页化`、`W18-8 设置页容器收敛` 三条均落在**在途兄弟批的活跃落码区**（图片页 L-4/L-5 批、Dynamic Type 批的 EditorView 段、设置收窄批——W18-8 断言本身即该批自带），其锚点代码区与本批六处 hunk 逐一核对无交集，待各批落定/组版分拣时由其归属批收口，非本批回潮。

## 6. 编译级自检与 hunk 归属

- 编译：以构建同旗标跑 MomentApp.swift primary 遍——全工作树口径被在途批的瞬时半成品污染（MomentRescue 一度语法未闭合 + 本机内存挤压两度 SIGBUS），改用**隔离快照口径**（MomentApp/MomentLaunch 取工作树现态——含救援批互依的 `LaunchSentinelStore.update`；其余文件取 HEAD）一次通过：**exit 0、零错误**、产物 .o 13.8MB。全量整合编译随组版 tree 冒烟把关。
- 本批 hunk（MomentApp.swift 六处）：EditorModel.init 计时基点 / 空 doc 守卫 + 原子尾随收敛 / 普查 + 工厂 / deleteBlock 收敛 / BlockRow 兜底支 / App scenePhase flush；verify_ios.sh 尾部 [32] 一组。他人 hunk（Library 段、MomentLaunch、MomentRescue、EditorView/Md/List/Settings 各段、lang 五包等）完工复验均在位。

## 7. 真机终判点

1. **flush 主判**：编辑中打字后立刻（<0.6s 内）切后台、再从多任务强杀、重开该篇——最后输入在位；Diag 应见 `EDIT flush src=background memo=<id>`（在 LAUNCH 哨兵收尾行之前）。
2. **标题定案判读**：标题改到一半（草稿未提交）切后台 + 强杀重开——标题仍是旧值（草稿不被 flush 连带 commit），正文编辑已落盘。此「正文在、标题旧」正是 §1 定案的可观察形态，非缺陷。
3. **空 doc**：打开一篇零块备忘（导入空 doc 或删空后重进的边界样本）——编辑页有可落焦的空段、能打字；Diag 见 `EDIT empty doc seeded`。
4. **未知块**：打开含未知类型块的文档（跨端新块型样本）——该块显类型小字 + 正文全文，不露开发文案；编辑别处后保存、重开，正文与未知字段无损；Diag 每 type 一行 `EDIT unknown block`。
5. **长文档量测**：500 / 1000 块样本各打开一次，导出 Diag 取同 id 的 `EDIT open census` 与 `TRANSITION build=` 两行回主线——按 §4.3 阈值裁护栏专项是否立项。
