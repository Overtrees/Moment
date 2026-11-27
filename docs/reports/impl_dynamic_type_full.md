# 文字大小真跟随——Dynamic Type 全量实装（impl_dynamic_type_full）

用户 2026-11-27 裁定：设置行「跟随系统」须名实相符，全量实装，不取「仅列表跟随」降级。依据 audit_home_other_deep.md P2-1。本批不提交、不 bump，随下一组版。

## 1. 盘点（落码前全量，proven）

盘点法：多行感知正则扫全部 app Swift 文件的 `.system(size:` / `UIFont.systemFont(ofSize:` / `UIFont(name:size:)`（含拆行写法），逐处按括号栈归属视图。

- 固定字号共 **220 处**：MomentApp.swift 185（SwiftUI 182 + UIKit 量测 3）、MomentBridgeSettings.swift 22、MomentRescue.swift 10、TitleTextField.swift 3（UIKit）。
- 其中 7 处落码前已随缩放：ListView 既有 @ScaledMetric 喂点 3（卡题/组头/meta）、slashHlText 形参 2、MdBlockView baseSize 喂点 1（经 dynFont）、memoRow `size * titleFontScale` 1。
- **待转 213 处**，本批全量转换。落码后复扫：数字字面字号仅余 **2 处**，且为本批新设的刻意基准（见 §3 胶囊高），已入 verify 白名单（DT36-1）。
- 既有缩放基建：Marks.dynFont（UIFontMetrics）供编辑器块文本（标题/正文/代码/引用/MD 树，含 MD 表格 td/th、callout 子块 baseSize 链）；ListView @ScaledMetric 三枚（groupFontSize 14 / metaFontSize 12 / titleFontScale 1.0，均 relativeTo .body）。

## 2. 映射口径（单一手法，全批统一）

等值优先语义样式（默认档与原字号逐值一致，字重经 `.weight()` 保持）：

| 原字号 | 语义样式 | 原字号 | 语义样式 |
|---|---|---|---|
| 11 | caption2 | 16 | callout |
| 12 | caption | 17 | body（标题角色 headline） |
| 13 | footnote | 20 | title3 |
| 15 | subheadline | 22 | title2 |
| 28 | title（仅粗体标题） | | |

无语义等值者走 @ScaledMetric，relativeTo 按角色就近：9/10/11→.caption2、12→.caption、13.6→.footnote、14→.body、18→.body、19→.title3、24→.title2、25→.title、28（图标）→.title、40→.largeTitle、44→.largeTitle。本批新增 @ScaledMetric 声明：MomentApp 49 枚（与既有 3 枚合计 52）、MomentRescue 2、MomentBridgeSettings 1，全部按视图就近声明、命名 f<基准值>。

- 等宽站点保留 design:.monospaced，样式/缩放换底（footnote/caption/caption2 语义或 ScaledMetric 同值）。
- 代码/MD：编辑器代码与 MD 渲染本就走 dynFont 链（已跟随）；MD 预览内的固定点（代码段 13 mono、脚注 13、callout 标题链）按上表转语义。
- UIKit 面走 dynFont 单源：TitleTextField 新增 `fieldFont()`（= Marks.dynFont(size: 14, weight: .semibold)），本体/缺省属性/占位三面经 `applyFont(_:)` 在建场与每次 updateUIView 刷新（系统字号变更经宿主重演算传导）。
- 三元字号（导出徽章 PDF 9 : 11、标签 chip small 10 : 11）：两支各换对应 ScaledMetric，分支结构不动。
- 字号派生行距：表达式中含字号乘数者随之换缩放值（标题 lineSpacing f14×0.4、副题 f12×0.3、堆栈 f9×0.4、图文 f14×0.7、导出尾注/诊断说明 f×0.45）；独立行距字面（6.5/7/6/5.6 等间距设计值）不动——lineSpacing 为附加间距、字号放大时不构成截断。

## 3. 布局账处置清单

- **标题胶囊宽量测（同源耦合，本批核心）**：capsuleWidth 标题字体、titlePrefixWidths 属性字体、TitleTextField 呈现字体三方统一为 `TitleTextField.fieldFont()`；meta 量测字体改 dynFont(size: 10, style: .caption2)，与 meta 渲染（@ScaledMetric relativeTo .caption2 的 f10）同缩放比。titlePrefixWidths 原注释中的耦合钉子（写死 14、将来改随系统须同步改）已拔除并改记新口径。
- **胶囊高 66**：前提账——66 = 标题行高（14 semibold 字体）+ 间距 3 + meta 行高（10 字体）+ 纵向留白 ≈34，默认档两行实高 ≈28.5、恒有余量；标准档位（至 XXXL）两行 ≈42.5 仍不溢；AX 大档才触顶。处置：新增 `capsuleHeight` = 66 + 两行行高相对未缩放基准的增量（紧凑态只计标题行），默认档恒 66、逐值不变；其内的未缩放基准字体 2 处即 §1 白名单。
- **完成胶囊 46↔92**：verify F29-1 以字面锁定帧高公式，不动帧；ellipsis 字形 22→f22（EditorHeaderView，relativeTo .title2），46 帧内容纳默认档字形、放大时字形随帧内居中、胶囊本体为命中/呈现框不裁字。
- **其余固定高容器**（行高 44/46/48/50/54、chip 高 18/20、瓦高 366、搜索字段高 40 等）：均为命中/布局几何而非文字盒，文字在内居中或单行省略，字号放大不破账；其中随字号走的既有派生（meta 行高 `20 * titleFontScale`、MD 列表缩进 `em × baseSize`）原本已缩放，不动。底表定高类（导出/备份确认）内容为纵向流式布局，随行高自然生长。
- **图片页**：标题走 CompactTitle（已转 headline）；正文无固定字号面。

## 4. verify 改动清单

- **新增 [36] 组 DT36-1**：四文件（MomentApp / MomentRescue / MomentBridgeSettings / TitleTextField）数字字面字号合计恒 = 白名单 2（tr 合行后多行感知计数），防回潮锁。
- 逐条核查未受影响（不改）：J20-9 抓的是 MD 表格 td 的 `dynFont(size: 14)` 令牌（本就在缩放链上、本批未动，仍命中）；T26-6（$HDR 段 `weight: .semibold` ≥2，转换后 f14/f22 调用保留该字面、计数守恒）；T26-8/T26-9（TitleTextField sizeThatFits 契约与占位色，本批未触）；F29-1（完成胶囊帧高字面，未动）；F30-13/14（listRowInsets 计数，未触）。
- 实跑：**341 ✓ / 2 ✗**，2 ✗ 为既有产物类（ipa 陈旧、产物语言包与 Web 源不一致，tree 构建自解），与基线同类。

## 5. 编译级验证（本机，swift-frontend primary 遍）

- MomentBridgeSettings、TitleTextField primary 遍：零错误（先行批）。
- MomentApp primary 遍：以现行 build-app2.sh 名单（20 文件，含同批新增 MomentLiveOps / MomentBridgeQR 等）零错误。
- MomentRescue primary 遍：零错误。
- 全量冒烟（smoke_ios.sh：cargo test → FFI 重建 → 22 遍构建 → verify）按分工在 tree 随下一组版跑。

## 6. 同批避让与完好性

落码门：0.9.57 组版提交落定（HEAD 6ce6cd8）且已跟踪文件净，已过。落码期间同批多批并行（救援完整性、宽屏收窄、配对二维码、LiveOps B 段、编辑审计批等），本批以文本锚点逐 hunk 避让、全程未触他人代码行；完工核验：全模块编译零错误 + verify 341 ✓（含同批新增 [32]–[35] 组全过）+ 关键令牌抽查在位（enterRescueManually / settingsContentFrame / MomentLiveOps / MomentBridgeQR / weather_sub 等），他人 hunk 完好。注：EditorView 与 EditorHeaderView 的归属以编译器作用域为准逐处核正（bgSheet / exportPanel / 菜单 / 回链 / 双栏行实属 EditorView，变量声明按归属落位）。

## 7. 真机终判点（系统字号最大 / 最小两档逐页看）

1. 首页：卡题/meta/标签 chip 不截断不重叠；空态图标与文案比例；搜索胶囊展开字段可读；撤销条文字不出框。
2. 编辑页：标题胶囊宽量测仍成立（长标题截断覆盖层与字段同宽、meta 行不裁、胶囊高随档生长后与坞/正文不重叠）；完成胶囊字形居中；斜杠面板行高与高亮文本同大；链接表单、背景底表、导出面板、编辑菜单、反向链接行不溢出。
3. 块面：待办勾选框、callout、链接/音乐卡（标题两行、来源行）、图库占位、视频播放钮、附件行、图文卡行距随字号走。
4. 设置族：SetRow/BackupRow 标题与 meta 两行不挤压开关/箭头；备份 hero/确认底表/操作行徽章；天气卡字段与状态行；语言行状态字。
5. 诊断/救援/桥设置：日志等宽行不横溢（可横滚区除外）、状态行键值不重叠、救援页按钮与状态区、看门狗条、错误徽章面板与计数丸。
6. 最小档：各页不出现因字变小而错位的派生量测（标题前缀宽/胶囊宽、MD 列表缩进、chip 高）。
