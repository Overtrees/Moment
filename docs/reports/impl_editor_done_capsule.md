# 编辑页「完成」胶囊落码报告（••• 圆钮键盘态向下延展成竖向胶囊）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。基线 HEAD 9d9dd9f（0.9.55）+ U1 在途改动之上（领地零交叠，见 §6）。
> 规格：用户 2026-11-27 直接规格——键盘态「完成」钮迁到更多菜单（•••）按钮下方；编辑页光标输入态、系统键盘弹起时 ••• 圆钮向下延展成竖向胶囊（同容器上段 •••、下段完成钮）；点完成 → 键盘收起 → 胶囊缩回 ••• 圆钮；完成文本改矢量打勾形；过渡动效与上下左右间距处理好。

---

## 1. 现状考古：旧「完成」钮有两处，行为链同一条

| # | 位置（已删） | 服务对象 | 动作 |
|---|---|---|---|
| A | EditorView 的 SwiftUI 键盘工具栏组（`.toolbar` + 键盘 placement 的「完成」文本钮） | SwiftUI 文本控件为第一响应者时（链接表单字段等） | `sendAction(resignFirstResponder, to: nil)` 沿响应链辞焦 |
| B | BlockTextView（块编辑 UITextView）的 `inputAccessoryView`：UIToolbar + 右侧「完成」BarButtonItem | 块文本视图为第一响应者时（正文编辑的主场景；SwiftUI 键盘工具栏对 UITextView 不生效，故当年另挂 UIKit 附件栏） | 直接对该文本视图 `resignFirstResponder` |

两处动作同义：**辞退当前第一响应者**。下游提交/保存全在各字段既有失焦链里，不在钮上：

- 标题字段（U1 的 UITextField representable）：辞焦 → 委托收口 → `onEndEditing` → `commitTitle()`（trim/空回退/落盘/backlinks 刷新）。
- 块文本视图：辞焦 → `textViewDidEndEditing` 的既有提交/保存链。
- 链接表单字段：辞焦 → 表单既有失焦处理。

故新胶囊的完成动作 = A 的动作体逐字（`sendAction` 沿响应链辞焦，覆盖全部第一响应者），一字不改失焦链。标题字段此前无专属附件栏、A 是否经宿主桥接呈现不确定；新胶囊统一覆盖，是严格的可用性净增、无行为回退。

## 2. 落码结构（单容器变形）

页眉（EditorHeaderView.headerOverlay）尾随位由独立 ••• 玻璃圆钮换成 `moreCapsule`：

- **单容器单玻璃面**：VStack（spacing 0）两段——上段 ••• 钮（`toggleEditorMenu()`，U1 具名入口，复用不另造）、下段完成钮（`finishEditing()` 具名入口）；容器统一挂 `.glassControl(radius: 999)`，旧 ••• 钮自带的玻璃随容器化删除。
- **顶锚定**：容器帧 `.frame(width: 46, height: 46↔92, alignment: .top)` + 页眉 HStack 本就 `.top` 对齐——展开时 ••• 段一像素不动，胶囊只向下生长；GlassCard 的 clipShape 随帧高同步裁切下段。
- **触发源（单点派生）**：`EditorUI.kbVisible`（@Published）由 `safeBottom` 的现行喂入点（EditorView 背景 GeometryReader 的 onChange，与 CREATE kb 打点同一边沿）在翻转时发布——不另起键盘通知跟踪；不消费 `kbPad`（其去抖 80ms 是为内容底距防逐帧重排设的，胶囊跟它会迟到约一拍）。展开与否由 `doneExpanded` 单点派生（kbVisible ∧ 抑制格全空）。
- **浮层不占位**：页眉本身是 EditorView ZStack 的悬浮层，胶囊增高不推正文；右边距 = 页眉横距 16（圆钮现行值不变），顶与圆钮现行顶线一致；z 序在正文之上、菜单面板之下（ZStack 既有序，面板在页眉之后挂载）。

## 3. 状态矩阵（逐格定规，`doneExpanded` 派生即实现）

| 场景 | 完成段 | 点完成/点 ••• 的后果 |
|---|---|---|
| 块编辑（键盘弹起） | 展开 | 点勾 → 块失焦链（提交/保存）+ 键盘落、胶囊缩回 |
| 标题会话 | 展开 | 点勾 → `onEndEditing → commitTitle` 不丢字 + 键盘落、胶囊缩回 |
| 斜杠面板开 | 展开（不抑制） | 同属编辑会话：点勾 = 确定性出口，斜杠随块失焦链关闭（与旧附件栏在位时可达口径一致） |
| 链接表单 | 展开（不抑制） | 点勾 → 表单字段失焦（与旧工具栏钮 A 的可达口径一致） |
| 菜单/导出面板开（showMenu/showExport） | **抑制** | 点 ••• 时胶囊同拍缩回圆钮、面板自上方盖入，无稳态重叠；关面板后若键盘仍在，胶囊复展 |
| 背景色底表开（showBgSheet） | **抑制** | 底表带全屏遮罩接管手势，胶囊保持圆钮 |
| 卡片菜单/块菜单开（cardMenuBlockId/blockMenuBlockId） | **抑制** | 两层在页眉之上呈现，胶囊保持圆钮 |
| 拖拽拾起中（draggingId） | **抑制** | 防拾起行与胶囊相扰、拖动态不呈现可点完成段 |
| 键盘收起（点完成/滑动收起/失焦/字段间转移后键盘落下） | 缩回 | kbVisible 边沿翻假即缩；字段间转移时键盘不落、胶囊保持展开不闪 |

## 4. 动效与间距取值表（逐项出处）

| 项 | 取值 | 出处 |
|---|---|---|
| 胶囊宽 / 圆钮直径 | 46 | 现行玻璃钮帧（返回/••• 同值） |
| 每段高 | 46 | 同上（两段同格，图标各居格心） |
| 段间内距 | 0（同径相接、无分隔线） | 玻璃坞/胶囊族无分隔线先例 |
| 展开总高 | 92 = 46 + 46 | 上两项派生 |
| 玻璃半径 | 999（宽 46 下钳为 23） | 现行圆钮 `.glassControl(radius: 999)` 同值；圆（高 46）↔胶囊（高 92）随高连续变形 |
| 右边距 / 顶距 | 16 / 安全区+7 | 页眉 `.padding(.horizontal, 16)` 与 `.padding(.top, 7)` 现行值，未动 |
| 高度动画 | easeInOut 0.25s | 页眉坞形态动画同族（dockCompact 0.25） |
| 勾淡入 | 0.15s，展开延迟 0.1s 起淡 | 规格「勾淡入略滞后于高度动画」；收起延迟 0 = 勾先淡出、高度随后缩（反序） |
| 勾形框 / 描边 | 22×22 / 线宽 2.8、圆头圆角 | 页眉 SF 图标 22 semibold 的光学大小与描边量级 |
| 勾形路径 | (0.27, 0.54) → (0.43, 0.70) → (0.75, 0.30) 相对坐标 | `CheckmarkGlyph`（纯 Path 三点折线，短长臂比约 1:2.2；不用文字、不用字符/SF 字形） |

## 5. Web 对照

原版 Web 与 Rust Web 端均**无**键盘附着的「完成」钮（移动 Web 依赖浏览器键盘自身的收起与失焦语义）；其语义核心是**失焦即提交**（标题控制器 blur → 提交、正文 blur → 保存，与原版 use-editor-dom 的焦点转移处理一致）。原生旧两钮与新胶囊都是这一语义在 iOS 上的「确定性失焦触发器」：动作链（辞焦 → 既有失焦提交链）逐字等价、零改动；变的只有 affordance 的位置与形态，按用户本次规格（属平台形态裁量，与 Dynamic Type/系统 Toggle 的「等价更优」先例同类）。

## 6. 改动清单（与 U1 领地零交叠）

`MomentApp.swift` 七处 hunk：

1. BlockTextView：删 inputAccessoryView 工具栏构造段（旧钮 B）。
2. EditorUI：新增 `@Published var kbVisible`（safeBottom 旁，附口径注释）。
3. EditorView 背景 GeometryReader onChange：kbVisible 边沿发布（与 CREATE kb 同点）。
4. EditorView：删 `.toolbar` 键盘组（旧钮 A）。
5. headerOverlay：尾随独立 ••• 钮 → `moreCapsule` 一处。
6. EditorHeaderView：新增 `doneExpanded` 派生、`moreCapsule`、`finishEditing()`。
7. GlassCard 旁（Shape 族）：新增 `CheckmarkGlyph`。

U1 在途 hunk（EditorUI 菜单帧量测、菜单面注册、标题胶囊/字段段、commitTitle 段等）逐个核对未触碰；本批复用 U1 成果两处：`toggleEditorMenu()` 具名入口、TitleTextField 的 onEndEditing 提交链。verify_ios.sh 仅尾部 [28] 后新增 [29] 组（U1 的 [25]/[26] 段未动）。

**Diag**（EDIT 族同风格）：`EDIT donecapsule expand` / `EDIT donecapsule collapse`（派生翻转各一行）、`EDIT donecapsule done`（点完成）。主线可走桥 diag_tail 复核：键盘升起应见 expand、点勾应见 done → collapse 序。

**断言**：verify 新增 [29] F29-1..6（单容器结构/触发单源/旧钮零残留/勾形在位/抑制六格/动效与辞焦单路锚）。本机自跑：[29] 六条全绿，全脚本仅剩 2 条既有产物类 ✗（ipa 陈旧、产物语言包——tree 构建自解），与本批前基线一致；Swift 编译级验证随主线 tree 冒烟（本机无 swiftc）。

## 7. 真机终判点

1. 块编辑键盘升起：••• 向下长成竖向胶囊、••• 本身位置不动、无跳位。
2. 点勾：键盘落下、标题/正文改动已提交、胶囊缩回圆钮。
3. 标题编辑中点勾：改名生效（commitTitle 链）后再开标题应为新名。
4. 键盘态点 •••：胶囊缩回与菜单打开同拍、无重叠残影；关菜单（键盘仍在）胶囊复展。
5. 滑动收起键盘：胶囊同步缩回；字段间点按转移焦点时胶囊不闪退。
6. 长按拾起拖拽中：胶囊保持圆钮。
7. 勾形观感与描边量级、淡入是否抢拍——视觉项真机判读。
