# 审计 0.9.62 批 1+2+7 落码报告（fix_audit_0962_b127）

工单：audit_full_2026-11-27.md §4 批 1（崩溃与自救真实性）+ 批 2（数据信任面）+ 批 7（Diag 补点）。
时序门：状态栏批与图片批并发占用 MomentApp.swift / verify_ios.sh / build-app2.sh——本报告分两态登记：
**已落**（不碰在途文件的三件，本轮完成）与 **待放行**（落点已通读、改法已定稿，放行后按稿外科落码）。
全部未提交，留主线组 0.9.62。

## 一、已落三件

### AUD-A-02 FTS 短查询 LIKE 通配符转义（批 2）— proven，已落 + 测试全绿

- 落点：`rust/crates/storage/src/lib.rs` `search()` 的 <3 字符 LIKE 回退分支。
- 改法：模式构造前对 q 依次转义 `\` → `\\`、`%` → `\%`、`_` → `\_`（转义符本身必须先行，漏转时 `\%` 会被读成转义的 %），SQL 两处 LIKE 均加 `ESCAPE '\'`。FTS ≥3 字符路径不动（引号转义既有）。
- 测试（锁机制不锁文本）：同文件新增 `search_like_escape_tests::short_query_like_wildcards_are_literal`——五篇判别样本（真含 % / 数字形近 % / 真含 _ / 形近 _ 的 acb / 真含 \），断言 `%`、`0%`、`a_`、`_`、`\` 五个短查询各只命中字面篇，另加正常短子串回归。`cargo test -p moment-storage` 全包 18 项全过、新测试 ok。
- 负向判别力自检：以同批样本在 sqlite3 复刻旧口径（未转义）——`%` 命中 5/5、`0%` 2/2、`a_` 3/3、`_` 5/5 全过宽；新口径全精确。断言判别力 proven。
- 附记（待放行顺手）：A 片附记的 haystack `meta.url` 未滤 `data:` 已回源坐实（MomentApp.swift haystack  walk 中 node url 与 items.url 两处均有 `!hasPrefix("data:")`、独 meta 键循环直取），改法 = meta 循环对 `key == "url"` 加同一过滤，一行条件，随待放行批落。

### AUD-E-02 ops_validate 不可 guard 步拆集（批 1）— proven（机制面），已落源码

- 落点：`rust/apps/ios/app/MomentBridgeOps.swift`。
- 通读核对：guard 消费点逐个在位——附件类型（MomentApp.swift:1639）、Diag 冻结写盘（:4691）、天气自动刷新（:18840）、看门狗（:837）、MCP 桥（MomentBridge.swift:429、MomentBridgeTools.swift:231/260）；公式预热无调用点、登记口径为执行前必查（MomentApp.swift:14714 注释 + MomentOps.swift 登记），属可 guard 集。`effectiveScopeDict`（MomentOps.swift:148-166）的 steps 键集与可 guard 集同集，已在新代码注释中对账。
- 改法：新增 `guardableOpsSteps`（OpsStep 六步显式集）与 `unguardedOpsSteps`（`knownOpsSteps.subtracting(guardableOpsSteps)` 派生，禁手抄第二份名单）；`opsValidate` 回报新增 `unguardedSteps` 字段，`valid` 改判为 `invalidSteps.isEmpty && unguardedSteps.isEmpty`，unguarded 非空时附 `note` 明示核心步永不跳过。规范形/哈希口径不变（仍按 sanitize 产物计，valid 只表达发布预期真实性）。
- 附带发现（登记不顺手改）：`knownOpsSteps` 注释称「LaunchStep ∪ OpsStep 全集」，实际漏 `LaunchStep.sceneRescue`（点名它现行判 invalidSteps）。本批不扩权改其判定面，留主线裁量。
- 待放行配套（verify_ios.sh）：断言两集定义在位、unguarded 为 subtracting 派生、opsValidate 回报含 unguardedSteps 且 valid 含其判据——随放行与 verify 同批落。行为终判 = 桥场景/真机以 ops_validate 点名「开库」应回 valid=false + unguardedSteps=[开库]（真机终判点 §三）。

### AUD-E-05① Undo 引擎本体打点（批 7）— 本体已落，接线待放行

- 落点：`rust/apps/ios/app/MomentUndo.swift`（整文件原零 DiagLog）。
- 设计：引擎保持 Foundation-only 纯状态机（宿主表驱动测试面不破）——新增 `eventSink: ((String) -> Void)?` 事件出口，引擎在四类内部分支自记：appendUndo/appendRedo 去重命中（dedup side=…）、钳制逐出（clamp side=… n=…）、performUndo/performRedo 空栈步进（step-empty side=…，即审计所指「恢复失败」面）。引擎只回吐分支事实短文，Diag 词形由注入方承接；默认 nil、行为零变化。
- 待放行接线（MomentApp.swift）：EditorModel 在 history（:6231）构造后注入 sink → `DiagLog.shared.log(.info, "EDIT undo core " + 事件)`；同时收敛代记：logHistoryFeed（:6833-6846）的 dedup/clamp 两支与 sink 双记，须删该两支（clampedBefore 参数与调用点随之清理），步进结果行（EDIT undo 余栈…:6980）保留不动。
- 待放行断言（verify [47] 宿主面扩展）：表驱动捕获 eventSink，断言序列——同键连馈出 dedup、101 条馈入出 clamp、空栈 performUndo 出 step-empty；且断言 EditorModel 代记两支零残留、sink 注入点恰一处。

## 二、待放行五件（落点已通读、改法定稿）

### AUD-E-01 开屏解码 fatalError + 渐变无守卫（批 1）— 落点 MomentApp.swift:22059-22151 + verify [8]

- 现行实证：`NativeSplashArtwork.load` 解码失败 `fatalError`（:22066-22073 区）；`NativeSplashGradient.init` 对 `start[0]/[1]、end[0]/[1]` 裸下标（:22150-22151）；`SplashHostView.resourcesReady` 只验文件存在。
- 改法定稿：
  1. `load` 改降级：guard 失败 → DiagLog error 行（`SPLASH artwork decode failed theme=<…>`）+ 返回降级件（背景 = 主题根色双同色 stop 的线性渐变、logo.base = 空 Path、details = []、tagline.path = 空 Path），永不 trap。static let light/dark 求值时机在场景呈现面、DiagLog 叶子可用，无初始化序问题。
  2. `NativeSplashGradient.init` 守卫：start/end 元素 <2 时回退 (0,0)/(1,1) 对角；stops 为空时回退单色双 stop（防空 Gradient 绘制异常）。
  3. verify [8] 升级（解码面锁）：构建期 python3 解码两份矢量 JSON，断言 background 与 logo.gradient 的 start/end 长度 ≥2、stops ≥1、logo.basePath 与 tagline.d 非空——字段集与 `NativeSplashVectorResource` Decodable 结构逐项对齐；另加源码断言：load 体内 fatalError 零命中、降级 Diag 行在位。
- 证据等级：缺陷 proven（源码）；降级呈现的视觉终判归真机（§三）。

### AUD-C-01 备份导入 lib == nil 假成功（批 2）— 落点 MomentApp.swift:1849 / :1891-1892 + verify [40]

- 现行实证：stageImport `_ = try lib?.validateBackup(…) ?? ""`（可选链短路回 true）；commitStagedImport `result = try lib?.importBackup(…) ?? ""`（回空串走成功收口、弹恢复成功 toast）。exportZip 已根治口径在 :1750-1757（显式 guard let lib + 失败记账 + Diag + ErrBadge）为对齐样板。
- 改法定稿：
  1. stageImport：do 内首行 `guard let lib else { throw … }`——抛既有口径错误走现行 catch（Diag「导入校验失败」+ ErrBadge + return false 已齐），错误值用与 exportZip 同文案的 NSError 域内构造或复用现有错误面（落码时以文件内既有「库未打开」表达为准，不新造词形）；随后 `try lib.validateBackup(…)` 直调。
  2. commitStagedImport：do 前加 `guard let lib else { recordOp(ok:false) + Diag error + ErrBadge + return .failure }`（与 catch 收口同形态；liveId 的 defer 以 importOk=false 收 .failed，守卫位置须在 liveId 建立后、do 前）。
  3. verify [40] 新增断言：stageImport/commitStagedImport 两函数体内 `lib?.` 零命中 + `guard let lib` 在位（BK40-2 既有断言只数 validateBackup 次数，不受影响）。
- 证据等级：机制 proven；可达性 inferred（异常路径），根治后失败口径如实。

### AUD-E-03 DiagLog 原子写（批 2）— 落点 MomentApp.swift:4604-4608

- 现行实证：`DiagLog.write` 以 `try? data.write(to:)` 无 options 落盘，persist/persistToday 均经此（:4704-4714）；哨兵/ops 缓存均 .atomic 直写，Diag 为全家唯一非原子面。
- 改法定稿：write 改 `try? data.write(to: URL(...), options: .atomic)`——Data 的 .atomic 即同目录临时文件 + rename 替换语义，崩在写盘中旧文件完好。DiagLog 叶子纪律不受影响（Foundation 既有 API、零新依赖）。写频口径：现行节流（普通行 1s 合并、error 立即）不变，.atomic 的临时文件开销在该频率下可忽略。
- 待放行断言：verify 以 awk 截 DiagLog.write 函数体断言 `.atomic` 在位（锁机制）。

### AUD-E-05② 视频失败面补点（批 7）— 落点 MomentApp.swift VideoBlockView.prepare（:15485-15515）

- 现行实证（比审计登记更细）：prepare 三出口全静默——① url 与 fileId 皆无 → 占位永驻无行；② fileId 路 attachmentData 空 Data → 照样写空文件建 AVPlayer（必然不可播、无行）；③ 写盘 `try?` 吞错。与图片面 ImageLoader 失败行不对称坐实。
- 改法定稿：三出口各补 Diag 结果行（VIDEO 行族）：无源记 warn（fid/url 皆空）、附件空数据记 warn 且不建 player（与 ATT missing 口径对齐）、写盘改 do/catch 记 error。AVPlayerItem 播放期失败观察（KVO）列为可选增强、非本批必落（块内 InlinePlayerView 的系统播放 UI 自带失败呈现，Diag 价值在打开面）。
- 待放行断言：prepare 体内三条 VIDEO 行在位 + 空数据不建 player 的 guard 在位。

### AUD-E-05③ PdfMaker 本体补点（批 7）— 落点 MomentApp.swift PdfMaker（:9631-9665）

- 定性修正（与审计条目部分出入，如实登记）：EditorModel.exportPDF 的 completion 内**已有**成败 Diag 行（「单篇导出 pdf ok/失败」）——审计所指缺口实为 **PdfMaker 本体**两条失败路径吞原因：`webView(didFail:withError:)` 的 error 与 createPDF 的 .failure 均只回 nil，上层只知失败不知因。ExportGen 为纯函数生成器、无 I/O 无失败面，不补点。
- 改法定稿：PdfMaker 两失败路径各记一行带原因（`PDF make nav failed: <error>` / `PDF make create failed: <error>`），completion 契约（URL?）不变。
- 待放行断言：PdfMaker 段内两条失败行在位。

### AUD-E-06 布防 reason 呈现（批 1）— 取证完成，本批定性关账（不落码）

- 三方矛盾取证结论（proven，源码 + 批报告原文双证）：
  - 布防批原文 impl_rescue_arm.md:84 明示「未改救援页 UI（RescueView 的 source 是数据行直出，bridge 无需新文案——本批零改 MomentRescue.swift）」，其真机验收口径（:89）亦只到状态区 mode 行 `src=bridge`。**reason 上屏从未有过设计与落码**。
  - reason 的实际留存面：Diag 三行中的 arm set 行（MomentBridgeOps.swift:308-313 带 reason=；consumed/cleared 行只带 id/applied/audit）+ 桥 rescue_status 的 safeModeArm.statusDict 回读（:415/:448/:456）。判定点消费（MomentApp.swift:1007-1024）take 即清，RescueView 无从取 reason（MomentRescue.swift 内 reason 零命中）。
  - trio 报告 §0「RescueView 状态区附读审计 reason 一行（0.9.57 已落）」为**转述失真**，与布防批原文互斥。
- 处置：E-06 定性 = 「呈现未落、Diag/桥回读在位」；建议矩阵 LCH-15 回写此定性（归批 6 文档面）。若要补上屏，须判定点先留存 reason（如 bootMode 附带或审计留痕转呈现），属呈现增强小设计，另行立项，不在本批顺手。

## 三、真机终判点（落码后归用户/桥验收）

1. ops_validate 点名核心步（如「开库」）→ valid=false 且 unguardedSteps 含该步；点名六步可 guard 集 → valid=true。（E-02，桥可自办）
2. 开屏：正常包开屏呈现与旧版一致；资源损坏的构造包（仅测试）开屏走降级呈现不闪退、Diag 有 SPLASH 行。（E-01，后者为构造验证、非常规用户路径）
3. 导入：正常 ZIP 导入成败口径与旧版一致（成功弹成功、坏包报失败）；lib==nil 异常路径非常规可达，终判以断言 + 代码口径为准。（C-01）
4. 撤销：反复撤销/重做 + 触发去重（连续同态）后 Diag 有 EDIT undo core 行；视频坏附件块有 VIDEO 行；PDF 导出失败有带原因行。（E-05 三处，Diag 导出可核）
5. DiagLog 原子写无用户可见面，终判 = 写盘中强杀后重启 Diag 不整日丢失（构造验证）。（E-03）

## 四、状态与纪律

- 已落三件文件：rust/crates/storage/src/lib.rs（A-02 + 测试）、rust/apps/ios/app/MomentBridgeOps.swift（E-02）、rust/apps/ios/app/MomentUndo.swift（E-05①本体）。与在途两批（MomentApp.swift / MomentEditorTransition.swift / build-app2.sh / verify_ios.sh）零交叠，diff 已复核。
- Rust 侧本机 cargo test 全绿（moment-storage 18/18）；Swift 侧本机无 swiftc，编译级自检随放行后 tree smoke_ios.sh 一并做（MomentUndo.swift 宿主断言面在 verify [47]，随待放行断言同批落）。
- 待放行五件 + A-02 附记 + 全部 verify 断言已定稿于 §二，放行信号到即按稿落码并在本报告回填落码行号与冒烟结果。

## 五、放行后落码回填（收尾轮）

状态栏批完工放行后按 §二定稿落码：待放行件中四件（E-01 / C-01 / E-03 / E-05③）+ E-05① 接线收尾 + A-02 附记 + E-02 配套断言全落。**E-05② 视频面按主线分工归图片批承担，本批未碰 VideoBlockView。** 逐项证据（行号为落码后现值，文件因并发批次持续生长会漂移，以符号名为准）：

1. **AUD-E-01**（MomentApp.swift 开屏段）：load 陷阱退出删除 → DiagLog error 行 `SPLASH artwork decode failed theme=…`（:22347）+ `degraded(theme:)` 降级工厂（:22376：主题根色双同色 stop 渐变 + logo/tagline 空 Path）；`NativeSplashGradient.init` 下标守卫（start/end count ≥2 才下标、否则对角回退；stops 空回退透明双 stop）+ `init(solid:)`（:22470）。verify [8] 升级两断言全绿：构建期 python3 实解码两主题 JSON、字段集与 Decodable 结构逐项对齐；降级面源码锁（load 体内 fatalError 零命中 + Diag 行 + 守卫/单色 init 在位）。
2. **AUD-C-01**：stageImport（:1852）do 内首行 `guard let lib`（抛既有 `status.db_not_open` 文案走现行 catch）+ 直调 validateBackup；commitStagedImport（:1909）do 前 guard（recordOp ok:false + Diag「导入失败: 库未打开」+ ErrBadge + return .failure，与 catch 同形态，位置在 liveId 建立后）+ 直调 importBackup；其后 reload 的 `if let lib` 包装随守卫确立收敛为直调。verify [40] 新增 BK40-5（两函数体可选链零命中 + 守卫各恰 1）✓；连带修订 BK40-1 普查（ok:false 记录 1→2、.failure 出口 2→3，沿革已注于断言头注）。
3. **AUD-E-03**：DiagLog.write 改 `options: .atomic`（:4769）；AU54-1 ✓。
4. **AUD-E-05① 收尾**：EditorModel.init 注入 `history.eventSink`（:6596，Diag 词形单点承接 `EDIT undo core ` + 引擎事件短文）；logHistoryFeed 函数本体与两调用点（pushHistory / noteTextWillChange）的 clampedBefore 管道全删，全文件零残留，步进结果行（EDIT undo/redo 余栈…）保留不动。连带收敛三处（均为代记删除的下游面）：
   - verify E47-7 改锁新承接行（旧代记字面两支随删改判，沿革注于断言头注）；事件字面本身由 AU54-2/3 在核心侧锁。
   - 桥场景 undo_redo_roundtrip 的 Diag 期望字面同步新词形（MomentBridgeUITest.swift：dedup 过滤改 `EDIT undo core dedup`、clamp 过滤改 `EDIT undo core clamp`）；verify U4b-3 断言锚同步。
   - 场景 clamp_depth_100 判据保全：旧代记 clamp 行携 depth=（钳后栈深），引擎事件原无此量——MomentUndo.swift 两栈 clamp 事件尾补 `depth=<钳后栈深>`（与旧行同口径），AU54-3 前缀断言不受影响。
   - AU54-2（接线单点 + 代记零残留 + 引擎三类出口各 2）✓；AU54-3 宿主表驱动实跑 UNDO_SINK_PASS（dedup 恰一 / clamp 恰一 n=1 / 空栈 step-empty 双向）✓。
5. **AUD-E-05③**：PdfMaker 两失败路径补带原因行（createPDF .failure :9802 `PDF make create failed: <error>`；didFail :9823 `PDF make nav failed: <error>`），completion 契约不变；AU54-4 ✓。ExportGen 纯函数无失败面不补（§二定性沿用）。
6. **AUD-A-02 附记**：searchHaystack 的 meta 键循环对 `url` 键加 `data:` 过滤（:2469，与 attrs node url / items.url 两处同形态）；AU54-5 ✓。
7. **AUD-E-02 配套断言**：AU54-6 ✓（guardableOpsSteps 显式集 + unguarded 以 subtracting 派生 + 回报含 unguardedSteps + valid 判据含其为空）。

**本机编译级自检**：三改动 Swift 文件（MomentApp / MomentUndo / MomentBridgeUITest）swiftc -parse 全过；verify_ios.sh 本机全跑 **549 ✓ / 6 ✗**，6 红定性如下，均非本批引入：
- 2 红为本机产物陈旧类（ipa 早于源码、产物语言包未重建）——tree 重构建即解（历版同类）。
- 4 红为构建接线普查漂移（DT46-6 期望 27、E47-8/X50-7/SB-5 期望 28，实测各 +1）：根因 = 并发图片批在 build-app2.sh 新增一遍全量输入（build-app2.sh mtime 23:07 CST 实证，非本批改动；本批未碰 build-app2.sh）。期望值普查须由该遍所有方/主线在 0.9.62 组版时统一回写（先例口径见 E47-8 头注沿革）。
- 本批自有断言全绿：[8] 新增 ×2、BK40-1 改判、BK40-5、E47-7 改判、AU54-1..6、U4b-3 锚。

**⚠ 组版注意（报主线裁量）**：verify 现有两组同号 **[54]**——本批「[54] 审计 0.9.62 收尾」（AU54-*）与图片批「[54] 图片加载键控」（IMG54-*）并发同号（两批各自尾部追加所致，两组内容不交叠、断言名前缀已分）。组版时须其一顺延 [55] 并同步其组内自引，本批不擅自改号以免与图片批在途编辑相撞。**（0.9.62 组版已办结：图片组顺延为 [55] IMG55-*，AU54 组不动，全文引用已同步。）**

**真机终判点**：沿 §三，其中 E-05 三处的 Diag 词形以本节新词形为准（`EDIT undo core dedup/clamp/step-empty …`、`PDF make nav/create failed: …`）；U4b 场景桥实跑时 dedup_lines_3 与 clamp_logged / clamp_depth_100 按新字面判读。tree 冒烟随 0.9.62 组版统一跑，本批未单独上 tree。
