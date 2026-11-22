# 标题胶囊「双光标 + 输入跳变」根因报告

- 日期：2026-11-22
- 缺陷来源：用户真机截图（Safari 无痕，线上构建 26acbd0829，14:17）：新建空备忘、九宫格拼音键盘已弹，标题胶囊内同一行高出现两处蓝色竖条（左侧呈「II」双条、右侧单条），标题为空。用户反馈：输入显示还是会出现跳变。
- 修复构建：fb525b0660（本地 dist 已备，**未部署**）

## 一、两条竖条各自是什么

**结论：两条竖条是同一个标题光标被 WebKit 画了两次，分别落在空标题行盒的左、右两端。（inferred，证据链如下）**

- proven（量测）：截图视觉定位量测（归一化坐标）：胶囊 x∈[262,736]、左条 x∈[338,361]、右条 x∈[648,663]、meta 文本居中于 499。换算为 pt（屏宽 390）：左条中心 ≈136pt = 胶囊左缘 102 + 胶囊内边距 18（长标题态）+ 滚动区内边距 16；右条中心 ≈256pt = 胶囊右缘 287 − 18 − 16。两条恰好是标题输入内容盒的左、右端点，像素级对称。
- proven（平台不变量）：一个文档只有一个选区，不存在第二个可编辑元素位于该行高（正文首段在胶囊下方、且自动聚焦的光标不在此带内）。
- proven（Chromium 逐帧采样，probe_title_ghost）：全部场景全部帧中，标题选区 getClientRects 至多返回 1 个 rect（空态返回 0 个），不存在第二个逻辑光标位。即「双光标」不是 DOM/选区层面的双落点，而是绘制层重复。
- inferred（WebKit 绘制机制）：空 contenteditable 的行盒横贯内容盒全宽时，WebKit 在行盒几何不稳定（宽度过渡动画进行中、布局模式刚翻转）时可把同一 caret 画在行盒的前导端与尾随端各一次；左条的「II」双笔划是同一伪影在前导端的双重绘制（两笔划间距约 9pt，与占位 `<br>` 前后两个候选位吻合）。WebKit 内部绘制路径无法在本机复现取证（Playwright WebKit 自动化在本环境不可用，为既定结论），此机制标注 inferred，不宣称 proven。

## 二、跳变机制（proven）

根因：**桥侧 syncTitleLayout 把原版的「会话快照单向锁存」移植成了「每次按当前文本长度双向重算」。**

- 原版（src/app/editor.js）：onFocus 建 editingStyleSnapshot（按全文长度初始化），syncTitleCompositionLayout 只读快照且只把 isLong/isOverflow 置 true（单向升级），commitTitleFromDOM 时销毁快照；三元素全部样式另有 React style prop 全量托管，任何重渲染都会按状态重断言。原版注释明言此单向性是为「避免跨阈值来回切换造成光标跳动」（editor.js 标题坞段）。
- Rust 版（修复前 bridge.rs）：syncTitleLayout 每次 compositionupdate / 组合期 input 都按 `el.textContent.length` 现场算 isLong/isOverflow 并整表重写三元素内联样式——可升可降。注释里虽写着「单向升级」，代码并未实现（名实不符）。
- Chromium 逐帧实测（修复前，probe_title_ghost P8 组字收缩 17→0）：总长跨回 11 时 capW 184→113、text-align left→center、white-space nowrap→normal；跨回 5 时字号 11px→14px、光标高 12→16、capW 再变。每次翻转伴随胶囊 `transition: width 0.2s ease` 动画，居中文本与光标逐帧位移——即用户所说「跳变」。P4 提交瞬间同样发生溢出→长标题的即时降级（capW 184→104.7、对齐翻转）。
- 对照（原版同探针）：组字长到 17、提交、逐字删空、组字再由长缩短——全程 capW 恒 184、样式恒溢出集、光标 x 随删字平滑左移（204.3→193.5→182.7→171.9→161.1→150.3），失焦才复位。

## 三、截图状态复核（纠正一条初判）

截图中空标题而胶囊宽 ≈184px（溢出定宽）：这本身**不是**异常残留——原版在会话跨过溢出阈值后、失焦前，删空标题同样保持 184（探针 P5 实测）。异常的是 Rust 版在到达该状态的途中几何反复翻转，以及终态样式取决于最后一次 compositionupdate 的文本长度（不确定残留：若组合以取消/短串收尾，最后一次重算可把空标题留在短态集，与类锁存的会话态互相矛盾）。修复后终态由会话快照唯一决定，与原版逐值一致。

另：新备忘标题元素内含字面文本「无标题」、聚焦时换空——原版同型（探针实测两版一致），非差异点，先前怀疑已排除。

## 四、与原版的执行形态差异清单（聚焦/组合期）

| # | 差异 | 修复前 Rust | 原版 | 处置 |
|---|------|------------|------|------|
| 1 | 组合期布局锁存语义 | 每次按当前长度双向重算 | 快照单向升级，会话内不降级 | **本次根治** |
| 2 | 快照生命周期 | 无快照概念 | onFocus 建、commit/失焦销毁 | **本次补齐**（focusin 建、focusout 销毁） |
| 3 | 三元素样式托管 | 类（CSS）+ 桥内联双写者，内联可与类态矛盾 | React style prop 单写者全量托管 + 组合期直写同集 | 保留双写者结构，但桥内联改由快照驱动，与类锁存（Rust 侧 title_long/title_ovf 同为单向升级）同向同值，不再矛盾 |
| 4 | syncTitleLayout 守卫 | 无条件执行 | 无快照时直接返回 | 已对齐（无快照时按当前长度建快照后执行，属超集，仅防桥在聚焦后迟装的边角） |
| 5 | 失焦清理 | 同步摘除三元素 style（第二批护栏） | React 重渲染按非编辑态 style 全量重断言 | 等价，不动 |

未动（护栏与既定调优）：第二批三护栏（失焦同步摘 style、状态先行、字号类驱动单写者）、第六批点按落点调优、自动聚焦正文首段。

## 五、修复

- `rust/apps/web/src/editor/bridge.rs`：新增会话快照 titleLayoutSnap（focusin 初始化、focusout 销毁）；syncTitleLayout 改为快照单向升级后按快照写样式，写集与原函数逐项不变；升级翻转时发 titleLatch 消息。
- `rust/apps/web/src/editor.rs`：新增 titleLatch 消息臂，只记 Diag（EDIT 标签 `title layout latch long=.. overflow=..`），不改状态。
- 无新增 setTimeout/延时重试；无样式写集增减；无类驱动口径变更。

## 六、验证（Chromium 口径）

- probe_title_ghost 修复后重跑：P4（提交→删空）capW 恒 184、光标 x 193.5→182.7→171.9→161.1→150.3；P8（组字收缩）capW 恒 184、光标 x 238.8→226.3→214.1→192.9→168→155.6→150.3——两序列与原版同探针**逐值相同**。全 565 帧中出现 ≥2 个不同 caret x 的帧数 = 0。
- Diag 实录：`title layout latch long=true overflow=false` → `long=true overflow=true`（会话内只升不降，两个会话各一组）。
- cargo test 全过；probe_title_* 全套通过（blurstyle / capsule_verify / gap_assert / reopen2 含 ALL PASS；ime 组字序列完整、标题节点零替换；tapmap 的 Chromium 版通过）。probe_title_tapmap（WebKit 版）在本环境启动即失败（无 X 显示），与本修复无关，为既定环境限制。
- run_all_tests.sh：ALL GREEN（15 套冒烟 + 构建 + 校验）。

## 七、WebKit 残余风险

- 双光标的 WebKit 绘制机制本身无法在本机自动化复现（inferred 结论），修复消除的是其使能条件（会话内行盒几何不稳定）。真机终判仍需在 WKWebView/真机上按原场景复验：新备忘 → 点标题 → 九宫格组一句长拼音（跨 11 字）→ 删改/取消 → 观察光标是否恒一位、输入是否还跳。Diag 中应只见 title layout latch 单向升级行。
- 若真机仍见双画，需进一步怀疑 WebKit 对 backdrop-filter 胶囊内 caret 的绘制伪影（与布局稳定性无关的独立面），届时以真机 Diag + 录屏逐帧定罪，不在本批结论内。
