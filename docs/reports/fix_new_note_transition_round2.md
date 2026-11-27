# 新建笔记过渡卡顿：第二轮根治落码（0.9.48）

排查定账：`docs/reports/audit_new_note_transition_round2.md`（嫌疑 S1 主因 / S2、S3 共犯 / S4 脆弱点）。本批按其第五节根治方向逐条落码，全部落源头、未在转场消费方做任何延时/预热式遮掩。版本 0.9.48 / build 75。**状态：落码完成、未提交未构建**；本机 verify 除 [5] ipa 陈旧、[9] 产物语言包两条已知产物红（构建后消除）外全绿，新增 [15] 组 8 项全过。

## 一、逐条对账

### 1. 列表 groups 去每趟重算（治 S1 趟基数）

- `ListView.groups` 由 body 内计算属性改为**版本缓存包装**：缓存键 =（`Library.memosVersion`、`Library.manifestVersion`、`searchHits`、当前语言码——组标题经语言包解析，切换必须失效）；键命中直接回缓存，body 重演算不再逐篇重跑。原组装逻辑整段平移为 `assembleGroups()`，口径逐项不变（置顶/桶序/遇见序/MemoGroup 分区）。
- 版本 bump 写点全集（grep 锁定、verify T15-1 计数断言）：memos 六处——reload 赋值、create 插入、persist 替换、remove、softRemove、undoDeletion；manifest 三处——名表刷新、类型表刷新、putAttachment 登记名。计数口径：`touchMemos()` 全文件恰 7 行（定义 1 + 写点 6）、`touchManifest()` 恰 4 行（定义 1 + 写点 3），多一少一即红。
- `Clock.parseISO`/`isoNow` 改**共享静态 formatter**：带/不带小数秒两形态各预建一个 `ISO8601DateFormatter`，全部访问经 `NSLock` 串行（formatter 非线程安全）。消除的是每篇每趟的 formatter 构造价。**按篇解析缓存未取**（报告方向 2 的取舍）：MemoItem 是值类型、计算属性 getter 不可 memoize，构造期缓存需给全部加载路径加显式 init 手术；共享 formatter 已除去主项，余下纯解析为 µs 级，二阶收益不值当——已在代码注释中记明此取舍。

### 2. 头像离开首帧同步路径（治 S1 触发源）

- `Library.loadAvatar` 改**后台队列 FFI 读 + 主线程回写**：同 id 在途去重（`avatarLoadsInFlight`）；回写时若在途期间已被 `setAvatar` 写过则不覆盖；读到非空头像经既有 `.momentAvatarChanged` 通道通知 `AvatarView` 回读（空头像不发通知，避免全列表无谓刷新）。首帧只出恐龙占位、头像随后贴入——与 Web 异步头像同形态。
- 回写发布仍会引 ListView 一趟 body，但归组已是版本缓存读，廉价；T7 那趟「全库重算」就此消失（由 listpass 打点验账，见第三节）。

### 3. EditorView 首帧发布收敛（治 S2）

- **种子化初值**：`EditorView` 新增显式 init，`EditorUI` 诞生时即写入 `titleDraft = editor.title`、`backlinks = library.backlinks(...)`（与旧 onAppear 回写同源同口径）；onAppear 的两处回写已删。首帧少一轮全量 body。
- **headerW 改非发布通道**：`EditorUI.headerW` 删除（零残留，verify T15-4 锁代码行无 `ui.headerW`）；改由 `EditorHeaderView` 自己的 `HeaderMeasure` 观察对象承载（属性名仍为 headerW，[7] 几何断言的公式口径不变），量测回写只失效页眉子树——与 scrollState 的隔离口径同理。
- **menuPanel 惰性构建**：`ui.menuBuilt` 门控整树（ScrollView + 5 菜单项 + twoPaneRow），隐藏态不再每轮 body 重构。预建时点 = onAppear 后 0.6s（转场窗 0.35s 与 settle 窗 0.5s 都已过）；窗内抢先打开由 `showMenu` 的 onChange 兜底即时建。**已知微差**：仅「打开编辑页 0.6s 内首次打开菜单」这一次无 220ms 进场弹簧（面板直接在位），其后全部打开与旧口径一致——换取首帧整树零构建，登记在此。

### 4. 键盘安全区（治 S3）

- 内容层（contentArea）加 `.ignoresSafeArea(.keyboard, edges: .bottom)`：滚动框高不随键盘动画逐帧变。
- 遮挡量改由**内容底 padding 落定后一次应用**：背景读数 `safeAreaInsets.bottom` 仍逐帧记入 `ui.safeBottom`（非发布），新增 `ui.settleKbPad` 去抖 80ms 后把落定值写入 `@Published ui.kbPad`（仅落定时变一次、引发一轮 body）；三形态底距同步加 kbPad——单列 40 + kbPad、flow 24 + kbPad、independent 两栏各 24 + kbPad。无键盘时 kbPad 恒 0、占位账与旧口径逐项一致；键盘落定后的避让量 = 旧口径稳态值（安全区底高），行为等价。

### 5. 落焦认领成功校验 + 有界重试（治 S4）

- 新增 `BlockTextView.claimInitialFocus`：`becomeFirstResponder()` 返回值入账（`CREATE claim ok=/inwindow=`），**成功才清** `wantsInitialFocus` 并走原落点/计时收口；失败不清旗、下一主线程回合重试，总尝试 ≤3，耗尽才清旗并记 ok=0。旧「尝试前先清旗 + 返回值丢弃」形态零残留（verify T15-5）。focusBlockId 聚焦请求路径（拆/并块落焦）原样保留、与认领路径分开走。

### 6. CREATE 分段打点七点 + focus 段修复

| 打点 | 落点 | 内容 |
|---|---|---|
| `CREATE dest` | 四新建入口 `nav.dest` 置位后（`noteCreateDest`） | model2dest 段 |
| `CREATE listpass n= ms=` | `assembleGroups` 每次真重装（trace 在位时） | 趟序 + 单趟耗时 |
| `CREATE avatar ms=` | loadAvatar 后台读完成回写时 | FFI 单趟耗时 |
| `CREATE claim ok= inwindow=` | 认领成功/耗尽收口（`recordCreateClaim`） | S4 分辨位 |
| `CREATE kb` | 背景读数 safeBottom 首次 0→非零 | dest2kb 段 |
| `CREATE bodypass` | EditorView body 入口计数（`noteBodyPass`），settle 行汇总 | S2 轮数 |
| `CREATE settle` | onAppear 后 0.5s 一次性总账 | 全段一行定案 |

- **focus 段缺陷修复**：分段函数换 `traceMs`——两端基点都已记且有序才出数，否则输出 `na`（旧实现基点未记时以 0 为基点算出 `Int(now×1000)` 量级巨值、或 -1，均不可作判据）。focus 段基点改 dest→claim（语义明确：置位到认领收口）。原 `CREATE appear` 行保留（create/pre 两段口径不变）。

### 7. 版本与断言

- bump 0.9.48 / build 75（build-app2.sh 与设置页版本文本，verify [1] 对账过）。
- verify_ios.sh 新增 **[15] 组 T15-1…T15-8**：归组缓存 + bump 计数、formatter 构造恰 2、loadAvatar 异步形态、menuPanel 惰性 + headerW 零残留、认领校验 + 旧清旗零残留、打点七点、na 口径、键盘免疫 + kbPad。本机实跑：[15] 八项全 ✓；全表仅 [5] ipa 陈旧、[9] 产物语言包两条已知产物红。

## 二、真机判读法（新建一篇 → 导出 Diag）

按时间序应出现的行与判读：

1. **`CREATE appear`**：`create=` 应为个位数 ms（落盘+入列）；`pre=` 是建篇→出现的总账（内含 dest/listpass/首帧构建），只看总量、归因看下面分段。
2. **`CREATE dest`**：`model2dest=` 应 ≈0–2ms（同回合置位）。异常大 → 点按回合内有别的同步长尾（回查 create 入口同回合工作）。
3. **`CREATE listpass`**：**应只出现 n=1 一行**（点按回合的版本变更重装），ms 为单趟全库组装价（共享 formatter 后应显著低于旧趟价；库量 N≈100 时期望个位数 ms）。若出现 n=2 → 仍有第二趟触发源：看它与 `CREATE avatar` 的时序——回写发布不应再引重装（版本未变必走缓存），出现即缓存键被意外击穿，回查 bump 写点是否有多余 bump（如某高频路径误 bump memosVersion）。ms 本身大（>20ms）→ 单趟价未降：回查 assembleGroups 内是否还有逐篇重活（hasCover 探针是余下最大单项，可再议按篇缓存）。
4. **`CREATE avatar`**：ms 是后台 FFI 读价（不占主线程，只作记录）；**不应**伴随 listpass n=2（见上）。整行缺席 = 本篇头像在建篇前已缓存（不可能，新篇必首读）或 loadAvatar 未被调——回查 AvatarHolder.refresh 调用面。
5. **`CREATE claim`**：期望 `ok=1 inwindow=1`。`ok=1 inwindow=0` = 认领成功但当时视图未入窗（becomeFirstResponder 对未入窗视图亦可成功，后续入窗即第一响应者——可接受、继续观察）；`ok=0`（耗尽行）= S4 坐实：认领在安装帧始终失败，需回查视图入窗时序（下一嫌疑是 NavigationStack 预构建调度下 updateUIView 首轮早于入窗且重试窗内仍未入窗——对策方向是把认领改挂 didMoveToWindow 钩子）。
6. **`CREATE timing`**：`focus=` 不应再出现巨值或 -1；未记基点时为 `na`。focus（dest→claim）应为小值（认领在首帧布局内）。
7. **`CREATE kb`**：`dest2kb=` ≈ 键盘开始呈现时点；与 settle 的 `kb=` 段同义。kb 迟迟不出现而 claim 已 ok=1 → 键盘呈现被系统延后（非应用侧），与卡顿归因分离。
8. **`CREATE settle`（定案行）**：逐段判读——`listpass=1x<总ms>` 期望趟数 1；`bodypass=` 期望 ≤3（首帧构建 + header 量测子树外溢残量 + kbPad 落定一轮；旧账约 4 轮且含整树菜单——若仍 ≥5，回查剩余发布源：T8 的 editingBlockId/canUndo 两发布未动，是已知残量，若其单轮价被 settle 总账证明可观，下一批再议编辑会话发布的收敛）；`claim=`/`kb=` 与单行互证；`avatar=` 为 na 表示 settle 时头像读尚未回（慢 FFI），不影响主线程、只记录。

**残余嫌疑清单**（本批未动、settle 数据指认后再议）：① T8 begin-editing 的 editingBlockId + canUndo 双发布（编辑页第 4 轮 body 的触发源）；② assembleGroups 单趟内的 hasCover 全树探针（单价残量）；③ 认领若 ok=0 坐实，改 didMoveToWindow 钩子。

## 三、行为等价与风险备注

- 归组结果、落点、键盘稳态避让、菜单稳态动画、头像最终呈现均与旧口径等价；有意微差仅两处且已登记：菜单首开（0.6s 窗内）无进场弹簧、头像由同步变异步（首帧占位→贴入，Web 同形态）。
- loadAvatar 的 FFI 读移至后台队列：代码库已有后台 FFI 先例（ImageLoader 等）；若真机出现头像读异常行，先回查此线程切换。
- 本批未改：编辑器滚动卡顿、长文档打开路径（不在本轮实报口径内，与第二轮排查第七节一致）。
