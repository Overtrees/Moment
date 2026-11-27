# 文字大小「真跟随系统」全面排查根治（fix_dynamic_type_follow）

起因：用户真机实报（0.9.58，2026-11-27 19:07–19:11）——改系统文字大小后
只有首页有变化，其他页面纹丝不动；首页内部搜索胶囊与新建笔记卡片同样不变。
0.9.58 的 DT 批曾报 213 处转换、仅 2 处白名单、断言锁死，现被真机推翻：
断言锁的是源码文本（字体声明形态），不是运行时机制。本批先定性、再根治、
断言改锁机制。不提交、不 bump，随 0.9.59 组版。

## 1. 定性（根因分级）

### proven（源码层实证）

- **全应用没有任何内容尺寸类别变更的传播机制**（改前 grep 实证）：零
  `UIContentSizeCategory.didChangeNotification` 监听、零
  `traitCollectionDidChange`、零 `\.sizeCategory` 环境读、零
  `adjustsFontForContentSizeCategory`。类别变更这一事件在应用内无任何
  消费者。
- **SwiftUI 面分裂线与用户实报逐面吻合**：会变的面（首页卡行标题/meta/
  chip、组头）全部是 `@ScaledMetric` 喂点；不变的面全部是 SwiftUI 语义
  样式字面（`.font(.callout)` 等）。逐面来源对照见 §2 表。
- **UIKit 面是构建快照、重建门只认内容**：编辑器正文 BlockTextView 的
  attributed string 在构建时以当刻类别定格，`updateUIView` 的重灌门只认
  `tv.text != block.text || typeChanged`（+ version），类别变更永不触发；
  MdTextGroupView 同型（attr 相等不换）；TitleTextField 的 applyFont 虽每
  次 updateUIView 无条件刷，但宿主无类别触发源、不会因类别变更被调用。
  `Marks.dynFont` 用 `UIFontMetrics.scaledFont(for:)`——是调用时快照，
  本身没错，缺的是重算时机。

### inferred（平台层推断，源码层不可证毕）

- 本机 iOS 27 环境下，SwiftUI 语义样式字体不随类别变更重演算、而
  @ScaledMetric 喂点有效——这是与实报吻合的平台行为推断。本批的收口
  策略不依赖该推断的成因：把所有面迁到**已被实报证明有效**的通道
  （ScaledMetric 喂点 + UIKit 显式 traits 工厂 + epoch 重刷），机制面
  以源码 + 断言 proven 表述，渲染面终判归真机（§6）。

## 2. 逐面三态表

| 面 | 改前字体来源 | 改后机制 |
|---|---|---|
| 首页卡行（标题/meta/chip）、组头 | @ScaledMetric 喂点（0.9.58 既有） | 不动——用户实报会变的对照样本 |
| **搜索胶囊·触发层** | 图标 `.body.weight` 语义 | f17 喂点（rel .body） |
| **搜索胶囊·展开层** | 字段/图标 `.subheadline` 语义 | f15 喂点。注：0.9.58 补批 R-3 判的「两层 AX5 均 <66」是高度账、不是缩放账，本批按缩放机制重新定性，不沿用旧结论 |
| **新建笔记卡（行/方卡）** | `.callout` / `.caption` 语义（非封顶问题） | f16 / f12 喂点；图标为 SF Symbol 字形、随字体度量缩放 |
| 方卡/文图卡、网格组头 | 语义样式 | 喂点 |
| 编辑器正文（含代码块/待办/引用） | dynFont 构建快照 + 内容门 | dynFont 委托 FontFactory（hub 显式 traits 计算）；BlockTextView `adjustsFont=true`；FontHub epoch 为失效键：未持焦整串 `reloadContent` 重建、持焦只换 font/typingAttributes 并登记 pendingFontRefresh（失焦补刷）、组字中两支不入且不消费 epoch（防永久漏刷） |
| 标题字段 + 胶囊量测 | applyFont 无触发源 | TitleTextField `adjustsFont=true`；EditorHeaderView 观察 FontHub 驱动重演算；胶囊宽/高量测与呈现同经 fieldFont/dynFont 工厂账 |
| MD 渲染链 | dynFont 快照 + attr 相等不换 | MdBlockView 观察 FontHub（base 输入变 → MdSegsView 重建串）；MdTextGroupView `adjustsFont=true`；列表标记 em 账基字改工厂缩放值 scaledBase（此前 marker 字/markerW/文起点用未缩放 baseSize、与已缩放正文脱档） |
| 斜杠菜单/各浮层菜单 | 语义样式散点 | 喂点；slashHlText 的 AttributedString 字体由调用点 f 度量喂入、随 EditorView 重演算重建 |
| 输入框（链接表单/天气 key/桥与救援输入） | TextField `.font` 语义 | 喂点 |
| 图片页 | CompactTitle 语义；失败文案裸 Text（继承环境默认 body） | 喂点；失败文案 f17 等值收口（默认档呈现不变） |
| 设置族各页（SetRow/天气/语言/手势等） | 语义样式 | 喂点（SetRow 标题 f16、meta f12 等） |
| 备份/导出面板 | 语义样式 | 喂点（heroDesc 使用点 f13 为既有 ScaledMetric，不动） |
| 桥设置页 | 语义 20 余处（含配对码跨行 mono title3） | 喂点（mono 跨行式 → f20/f13 同式收口） |
| Diag 页 | 语义样式；空态文案裸 Text | 喂点；diag.empty f17 等值收口 |
| 救援页/看门狗条 | 语义 7 处（含跨行 mono ×3） | 喂点 |
| 权限页（在途新页顺带核） | 语义 5 处 | 喂点；其自有锁 PC44-5 同步改判（§5） |
| **头像（首页 + 编辑页）** | `AvatarView(size: 72)` 固定字面、纯图形无文字 | **评估结论：不必跟随，本批不落码**（§4） |
| Live Activity / Widget 扩展（MomentLiveOpsWidget.swift） | 语义 8 处、无 ScaledMetric | 范围外：独立 appex 目标、系统合成呈现、不在 build-app2.sh 应用遍内；如需跟随须在扩展目标内同法处理，留待裁 |
| 系统域（PHPicker/ShareSheet/系统 alert/Picker/上下文菜单） | 系统渲染 | 不受 App 字体面支配，不处理 |

转换口径统一：喂点命名 f<基准点数>、`relativeTo` = 被替样式本身
（caption2→f11、caption→f12、footnote→f13、subheadline→f15、
callout→f16、body/headline→f17、title3→f20、title2→f22、title→f28），
默认档逐值等价。四文件（MomentApp / MomentBridgeSettings /
MomentRescue / MomentPermissions）语义字体两式普查归零（DT46-4 锁）。

## 3. 类 A 字形封顶复审（9 点逐个给数）

缩放值为系统 UIFontMetrics 分样式表约值（L 档为基准；XXXL ≈ 基准
×1.3 上下、AX1 ≈ ×1.6 上下，逐样式略有出入）。本批不改任何封顶值。

| # | 位点 | 式 | 封顶起始档 | 判 |
|---|---|---|---|---|
| 1 | 待办勾选 | min(f22, 30) rel title2 | XXXL 约 28 <30 透传，AX1 起 | ✓ 仅极端档 |
| 2 | 菜单行图标 | min(f20, 24) rel title3，槽宽 24 | XXXL 约 26 → 压至 24（XXL 约 24 恰达帽） | 槽宽设计约束：图标字形封顶、旁行文字全程缩放；改槽宽属布局变更、不在本批 |
| 3 | 斜杠行图标 | min(f20, 24) rel title3 | 同 #2 | 同 #2 |
| 4 | 完成胶囊 | min(f22, 34) rel title2 | AX1 约 35 → 34（恰在 AX1） | ✓ 极端档 |
| 5 | 双栏行图标 | min(f17, 24) rel body | AX1 起 | ✓ |
| 6 | SetRow 图标 | min(f16, 24) rel callout | AX1 起 | ✓ |
| 7 | BackupRow 图标 | min(f17, 28) rel body | AX1 约 27.9 恰透传、AX2 起 | ✓ |
| 8 | 天气可见性图标 | min(f15, 28) rel subheadline | 约 AX2 起 | ✓ |
| 9 | 手势图示 | min(f25, 25) rel title | 帽 = 基准，默认档以上全程压平 | 代码注释自陈「图示不随字号胀」的设计决定；给数留用户终判（§6 单列） |

结论：9 点中 6 点仅辅助功能（AX）档封顶，符合「只许极端档封顶」；
#2/#3 在 XXXL 起封顶但属字形槽约束；#9 全程压平待终判。DT46-5 锁
封顶位点总数 = 9，防静默新增（与 DT36-2 分项锁互补）。

## 4. 头像评估（单列）

现行：首页（ListView）与编辑页（EditorHeaderView）均
`AvatarView(size: 72)` 固定字面，内容为照片/插画、纯图形无文字。
推荐**不必跟随**，理由：① 平台惯例图形元素不随 Dynamic Type 缩放；
② 72 已 ≥44、命中区守规在所有档位不变；③ 编辑页页眉框固定高 82，
头像胀缩会挤压同行标题胶囊与搜索布局，失衡源在布局不在头像；
④ AX 档同行相对关系的变化点是标题胶囊，其已有 capsuleHeight delta
生长机制承接。结论留用户终判（§6 单列），本批不落码。

## 5. 根治落点与断言改锁

### 落点（单源工厂，新文件 MomentFontFactory.swift）

- **FontHub**（ObservableObject 单例）：监听
  `UIContentSizeCategory.didChangeNotification`（UIKit 通道、不经
  SwiftUI 环境），比对 `UIApplication.preferredContentSizeCategory`
  后发布 category + 单调递增 epoch；每次变更记 Diag 一行
  `FONT category -> <raw> epoch=<n>`，下次同类回归日志可见。
- **FontFactory**：UIFontMetrics 全部以 hub 显式 traits 计算（不依赖
  调用点环境 trait）；`baseFont` 为全应用 UIFont 构造单点；`uiFont`
  供 UIKit 面；`scaledSize` 供 SwiftUI 侧纯数值场景（MD 标记 em 账）；
  `derivedMono` 收口派生等宽构造（输入已是缩放后点数、不二次缩放——
  公式源码回退 = 基字 ×0.85 两处已归此口）。
- **Marks.dynFont 改为委托 FontFactory.uiFont**（签名不变，全应用
  UIKit 字体自此同账）。
- **SwiftUI 面**：语义样式全量改走 @ScaledMetric 喂点（同与 UIFontMetrics
  共用分样式缩放表、同账）；EditorView / EditorHeaderView / MdBlockView
  三点观察 FontHub，保证类别变更即整树重演算（MdSegsView 由 base 输入
  变化驱动重建，不另加观察）。
- **构建接线**：MomentFontFactory.swift 进 build-app2.sh 全部 21 遍
  名单 + 新增 primary 遍 + 链接行（DT46-6 锁登记数 22）。
- 白名单 2 处复核**成立**：capsuleHeight 的 14 semibold / 10 未缩放
  字体是行高 delta 的参照基准本身——若缩放，delta 恒零、胶囊永不
  生长；必须保持未缩放，DT36-1 在册口径正确，不动。
- 公式图（MathImageStore）以 base.pointSize 为键：类别变更后经 MD/
  编辑器重建链以新点数重渲，自动换档，无单独机制。
- 行为等价注：抽出 `reloadContent` 时一处微统一——建场非引用块
  textColor 由 UIKit 默认收口为 .label（与旧 update 支口径一致）；
  其后深色批（fix_dark_mode_full）已将该口改为显式 baseColorUI，
  现行形态以深色批为准，与本批 epoch 逻辑正交共存。
- 过程留痕：首轮类型检查出一红——EditorView 的 bgSheet/导出面板/
  菜单行三处 f15 漏声明（EditorHeaderView 为 EditorView 的嵌套类型，
  按顶层 struct 名聚合的校验脚本误判归属）；已补声明修复。教训：
  嵌套类型下声明归属以编译器为终验，脚本聚合只作普查。

### 断言改锁清单（verify_ios.sh）

- **新增 [46] 组（锁机制）**：DT46-1 UIFont 构造单源（全集 5 = 工厂 3
  + 白名单 2；UIFontMetrics 仅工厂 2）；DT46-2 adjustsFont 三点点名
  置真（BlockTextView/MdTextGroupView/TitleTextField）；DT46-3 epoch
  机制锚（didChange 监听/epoch 递增/fontEpoch 失效键/pendingFontRefresh/
  失焦 reloadContent）；DT46-4 四文件语义字体零残留；DT46-5 封顶位点
  总数 = 9；DT46-6 FontHub 观察三点 + 工厂构建登记 22 + dynFont 委托。
- **DT36-1 加改判注**：「改走语义样式」路线作废注记，本条降为数字
  字面防回潮，机制锁移交 [46]。
- **DT36-4 锚改判**：`baseSize * 1.125` → `scaledBase * 1.125`（em 基
  字与正文同档缩放，机制增强、注释同步）。
- **PC44-5 改判**（权限批自有锁）：`.system(size:` 零 → 喂点恰 5 +
  数字字面 0；原口径以语义样式为跟随通道、已被真机推翻，意图（无固
  定字号）不变、通道换代。
- DT36-2 保留：封顶分项锁与 DT46-5 总数锁互补。

### 本机自检

- 六文件（MomentApp / MomentFontFactory / TitleTextField /
  MomentRescue / MomentBridgeSettings / MomentPermissions）以
  build-app2.sh 同旗标跑 swift-frontend primary 遍，零 error。
- [46] 六项 + DT36-4/PC44-5 改判锚已在本机对现行树逐项实跑达标；
  verify 全量与冒烟归 tree 组版批（0.9.59）。

## 6. 真机终判清单（归用户，断言绿 ≠ 已跟随）

改系统字号（L → XXXL → AX2 各一遍）逐面核：

1. 编辑器正文（含代码块、待办、引用）随动；持焦中改字号 → 失焦后
   补刷到位；组字（拼音）中改字号不打断输入、失焦后对齐。
2. 标题字段与胶囊宽/高随档重算。
3. MD 预览正文、列表标记、代码段随动。
4. 首页单列两面：**搜索胶囊两层**（触发层图标、展开层字段）、
   **新建笔记卡片**（行/方卡）；另组头、方卡文图卡。
5. 设置族各页行标题/meta；备份面板、导出面板；天气/语言/手势页。
6. 斜杠菜单与各浮层（••• 菜单、背景底表）。
7. 桥设置页、Diag 页（含空态文案）、救援页 + 看门狗条、权限页。
8. 图片页标题与加载失败文案。
9. **头像单列**：两处头像尺寸不变（设计决定）且 AX 档同行胶囊/布局
   不失衡——若判应跟随再立项。
10. **手势图示单列**（min(f25,25) 全程压平）：确认图示字形不随字号
    为可接受的设计决定，或改判立项。
11. Diag 出现 `FONT category -> … epoch=…` 行（变更留痕在位）。
