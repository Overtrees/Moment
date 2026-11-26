# 落码执行清单 · 批 D：浮层数值（线 2 报告 80 条核证）

核证时间：2026-11-26（原生 0.9.35 基线）。方法：`docs/reports/audit_detail_editor_layers.md` 逐条回读 Web 真值出处，并在现行 `rust/apps/ios/app/MomentApp.swift` 按符号名重新定位核对（报告行号已漂移，下文行号为 0.9.35 现行值）。口径：行为等价为底线、系统控件等价更优标「改判保留」；Web 字重 650 无 SF 字阶、原生 semibold 近似为系统性定案，不逐条计差。

分级：**A = 形态/定位级（本批落码）**；**B = 微差（只登记，不在本批动）**；已修 / 改判保留 / 一致单列。

---

## 〇、已修（只核现状，不列待修）

| # | 条目 | 现状核证 |
|---|------|----------|
| 6 | 标题胶囊最大宽钳制 | **已修（0.9.35）**：`capsuleWidth`（MomentApp.swift:6764）现行 `avail = ui.headerW − 124 − chrome`，chrome 紧凑态 80 → 列态 W−124 / 横排 W−204，与 Web（editor.css:1193 坞左右 62 + 横排扣头像 72+gap 8）逐值一致；页眉两段 Spacer 已改紧贴（minLength 0），verify_ios.sh [7] 有前提断言锁定 |
| 17 | 撤销/重做置灰行为 | **已修（0.9.32）**：`menuItem`（:7087）已删 `.disabled(dimmed)`，仅 `.opacity(dimmed ? 0.3 : 1)`，点按照常走 action（undo/redo 栈空时自身 no-op 并关菜单），与 Web .dis 口径一致，代码注释已登记出处 |

## 〇.五、改判保留 / 已定案偏离（不修）

| # | 条目 | 定案 |
|---|------|------|
| 21 | 导出分节线缺失 | 已定案偏离（2026-11-26 裁定：••• 菜单六项无分隔线），不补 .menu-section |
| 24 | 双栏开关形态 | 系统 Toggle（51×31）改判保留——系统控件等价更优，已定案 |
| 44 | bgSheet 选色生效时点 | 已定案：关闭 220ms 后经 onChange(bgClosing) 生效，与 Web BgAfter::Apply 同口径 |
| 77 | 错误徽章条目无 loc/stack | 已定案偏离：原生投递点无堆栈来源，详情由 Diag 承接 |
| 80 | 键盘上方「完成」栏 | 系统等价更优：Web 无对应概念，原生 inputAccessoryView / .toolbar(.keyboard) 双路按第一响应者分工，保留 |

## 〇.六、一致（38 条，不动）

#1、#2、#4、#5、#7、#8、#9、#11、#12、#16、#26、#27、#28、#31、#36、#37、#38、#39、#40、#42、#43、#45、#46、#47、#49、#50、#54、#62、#63、#65、#67、#68、#69、#70、#71、#73、#78、#79。核证抽样：bgSheet 全面（:6800 区）、卡菜单几何（cardMenuLayer :6243、panelH 114/64、panelLeftX 钳 12）、导出行本体（exportChoice :7050 区）、错误徽章主体（errBadgeLayer :6123）、标题坞主体均与报告「一致」结论相符。

---

## 一、A 级（形态/定位级，本批落码，共 3 组）

### A-1 · #52 斜杠面板纵向锚（本批最重项）

- **Web 真值**：`render.rs:651-659`——top = 锚底 + 10；放不下按 **260 估高**上翻（top = 锚顶 − 260 − 10，下限 vy+76）；**动态限高** `max-height: min(320, 100dvh − (top+16))`，面板永不溢出视口底，下半部靠收缩而非翻转。
- **原生现行**：EditorView body 浮层段（:5822-5855）——`panelH: CGFloat = 320` 写死，below = top + bh + **8**，以 `.position(x:, y: centerY)` 按 320 估高定中心；slashPanel（:6336）本体 `.frame(maxHeight: 320)` 静态限高。后果：实际高 < 320 时（过滤态/最近态/空态）面板顶边下移 (320−实际高)/2，短列表可达约 100px；且间距 8 比 Web 少 2；无限高收缩。
- **目标**：间距 10；纵向锚按**实测高**定顶边（不用估高定中心）；限高随锚位动态收缩。
- **落法设计（实测高）**：
  1. **量高**：在浮层 Group（slashPanel / linkFormPanel 共用呈现处）外层挂 `.onGeometryChange(for: CGFloat.self) { $0.size.height }` 回写一个专用状态（放 EditorUI 的 `@Published var slashPanelH: CGFloat = 260`，初值取 Web 估高 260）。选 onGeometryChange 而非背景 GeometryReader：本 app 有「0 高视图 + 背景 GeometryReader 真机恒报 0」前科（0.9.6 滚动探针定案），且 scrollProbe 已以 onGeometryChange 直读为现行机制，同路可靠。量测对象是面板本体（有真实高度、非 0 高），值变化才回调、天然收敛，不会循环重演算。
  2. **首帧预估兜底**：量得前第一帧用构成估高避免跳变——行数已知（recents/filtered/分组构成在 SlashCmds.filtered 与 panel 构成同源）：估高 ≈ 16（padding）+ 组头数 × 30 + 行数 × 48，钳 [48, 320]；空态 ≈ 120。呈现处按当前 query/构成算预估值，实测回写后以实测为准（两者差 <10 时首帧无感跳变）。
  3. **锚点改顶边公式**：`panelTop = top + bh + 10`；若 `panelTop + h > viewH − 12` 则上翻 `panelTop = max(12, top − 10 − h)`（h 为实测/预估高）。呈现保留 `.position`，y = panelTop + h/2（h 与呈现高同源后中心即准）。top/bh 来源不变：top = blk.frameMinY（independent 时 +168，与 cardMenuLayer 同口径）、bh = blk.height。
  4. **动态限高**：slashPanel 的 `.frame(maxHeight: 320)` 改为参数传入 `maxH = min(320, viewH − panelTop − 16)`（下锚）；上翻时 `maxH = min(320, top − 10 − 12)`。slashPanel 签名加 `maxH: CGFloat` 参数；linkFormPanel 高度远小于限高、不受影响（共用定位、各自限高）。
  5. **横向不动**：panelLeftX（:6278）与 panelW 本条不碰（#51/#53 在 B 级）。
- **占位账**：GeometryReader 全屏（geo.size = 视口）；top 锚 = 触发块顶（frameMinY，editorScroll 坐标，independent +168 补偿）；间距 8→10；底安全距 12（Web 判翻用 vh−8，原生 12 为既有近似、保留登记）；限高收缩量 = viewH − panelTop − 16（Web 为 top+16 同义）。
- **风险/前提**：① 量测回写引发 EditorView 一次重演算（面板开启期间、值稳定后不再触发，可接受）；② EditorView.body 有类型检查超时前科——量测只挂在既有 Group 上加一个修饰符、状态字段加在 EditorUI，不往 body 堆新计算段；③ 上翻下限 Web 为 vy+76（避页眉），原生取 max(12,…) 与卡菜单 panelTop 同口径，页眉区重叠由面板自身浮层层级覆盖（现行上翻公式同样未避页眉，非本批新增问题，登记）。

### A-2 · #25 ••• 菜单面板最大高缺失

- **Web 真值**：editor.css:1230——max-height = 100dvh − safe − 64，超出滚动。
- **原生现行**：menuPanel（:6905）VStack（padding 7、宽 246）无 maxHeight、无滚动；固定 5–6 行约 364，矮屏/横屏可溢出。
- **目标/改法**：菜单 VStack 外包一层 ScrollView（.vertical、showsIndicators false），并 `.frame(maxHeight: ui.viewH − ui.safeTop − 64)`（下限兜底 200）。ui.viewH/ui.safeTop 由 EditorView 既有尺寸同步通道取（syncWide 写 ui.viewW/viewH；safeTop 若无字段则用 59 锚点反推：maxH = ui.viewH − 59 − 8，两者等价取后者更少新状态——落码时二选一并注释口径）。
- **占位账**：面板 top = 59（现行 .padding(.top, 59) 不变）；可用高 = viewH − 59（顶距）− 8（底边距近似 Web 的 −64 含 safe 的合成，横屏 safe 小、误差 ≤8，登记近似）。
- **风险/前提**：菜单项 Button 进 ScrollView 后点按/拖动仲裁——菜单不滚动时（常态行数少）无感；M13 进出场动画挂 menuPanel 外层（scale/opacity）不受影响；twoPaneRow 的 Toggle 在 ScrollView 内拨动可能被纵向拖动抢手势——仅超高滚动时有此风险，宽屏高足够、实际不触发滚动，可接受。

### A-3 · #22 + #23 双栏行独立度量

- **Web 真值**：editor.css:896-935——双栏行 min-height **56**、标题 **14**/650、副 11、图标 slot 24 / SVG 20 / stroke 1.8，与普通菜单项（50/15）是两套度量。
- **原生现行**：twoPaneRow（:7386）独立实现但取值随 menuItem：minHeight **50**、标题 **15** semibold、图标 font 17。
- **目标/改法**：twoPaneRow 单独改：minHeight 50→56、标题字号 15→14；图标 font 17 保留（字形差归 B 级字形组统一议，不在本组单独调）。
- **占位账**：菜单总高仅宽屏（twoPaneRow 仅 ui.wide 时出现）+6，其余形态零影响。
- **风险/前提**：twoPaneRow 与 menuItem 不共用实现，改动隔离、无连带。

---

## 二、B 级（微差登记，本批不动）

### B-组 1 · SF Symbol 字形系统性偏小（−1～−8，同源：SF 字形同 font 号小于 SVG 画布号）

| # | 落点（符号） | 现行 | Web 真值 | 目标 |
|---|------|------|----------|------|
| 10 | EditorHeaderView 两侧钮图标（:6597 区 chevron.left / ellipsis） | font 17 semibold | SVG 22×22 | 22 或按字形实测等效号 |
| 14 | menuItem 图标（:7095） | font 17 / slot 24 | SVG 20 | 20 |
| 29 | exportPanel 返回钮图标（:6982） | font 14 | SVG 22 | 22（本组最大差 −8） |
| 55 | slashRow 图标（:6445 区） | font 19 / slot 24 | SVG 20 | 20 |
| 76 | errBadgePanel 条目图标（:6200 区） | font 12 | SVG 14 | 14 |
| 48 | cardMenuPanel 项 | 复用 menuItem | 同 #13/#14 | 随 #14 |

改法（一句话）：统一按「SVG 号 = SF font 号」逐点对表改；注意个别符号字形留白不同（如 chevron.left 22 号视觉可能偏大），改后须真机逐项判读，不宜盲改一刀切——这是本组缓行的原因。

### B-组 2 · 纵向小距成组缺失（2–9px）

| # | 落点（符号） | 现行 | 目标 | 改法 |
|---|------|------|------|------|
| 18 | menuPanel 附件行（:6936 区） | VStack spacing 0、无上距 | margin-top 4 | 附件 menuItem 上加 .padding(.top, 4) |
| 19 | menuPanel 背景行（:6948 区） | 同上 | margin-top 4 | 背景 menuItem 上加 .padding(.top, 4) |
| 30 | exportPanel 选项区（:7003 区） | 三 exportChoice 直排 spacing 0 | gap 3 + padding-top 6（总高 +12） | 选项组包 VStack(spacing: 3).padding(.top, 6) |
| 35a | exportPanel 尾注（:7030 区） | 边线贴选项（margin 0）、padding T5 | margin-top 5 + padding-top 9（边线 −5、注文 −9 的距差部分；文案差已定案不算） | 尾注 Text 加 .padding(.top, 5) 且内 padding-top 5→9 |
| 41 | bgSheet 移除区（:6857 区） | 边线 + 钮 padding-top 10、无 margin-top 4 | border-top 前 margin-top 4（边线下移 4） | 边线 Rectangle 上加 .padding(.top, 4) |
| 57 | slashPanel 行间（:6336） | 列表 VStack spacing 0 | 行 margin 1 上下（相邻行间 2） | slashRow 加 .padding(.vertical, 1) |

### B-组 3 · 单项微差

| # | 落点（符号） | 现行 | Web 真值 | 目标/改法 |
|---|------|------|----------|-----------|
| 3 | titleCapsule 标题文字（:6719 区） | 14 semibold 无 tracking | letter-spacing −0.2px | TextField 与截断 Text 各加 .tracking(−0.2)（注：capsuleWidth 量宽用 UIFont 14 semibold 未含 kern，−0.2×字数误差 ≤2px，登记不改量宽） |
| 13 | menuItem 按压高亮（:7130） | RowPressStyle() 默认 radius 12（RowPressStyle :9188 默认 12） | 菜单项 radius 17 | menuItem 改 RowPressStyle(radius: 17)；cardMenuPanel 复用同函数自动跟随（#48 同步解决） |
| 15 | menuItem 文字（:7100 区） | 标题无 tracking、副 spacing 1 | 标题 letter-spacing −0.1、副 margin-top 2 | 标题 .tracking(−0.1)、VStack spacing 1→2 |
| 20 | menuItem 背景行图标色（:7097） | 一律 T.accent（蓝） | 背景行 stroke --color-purple #AF52DE | menuItem 加 iconColor 参数（默认 accent），背景行传紫（T 需加 purple 令牌 dyn(0xAF52DE, …)——深色值 Web 未给独立值，同值近似登记） |
| 32 | exportChoice 徽章字体（:7060 区） | design .monospaced | font-family inherit（非等宽） | 去 .monospaced、保留 11/9 号与 bold |
| 33 | exportChoice 副文距（:7066 区） | VStack spacing 1 | margin-top 2 | spacing 1→2 |
| 34 | exportChoice chevron（:7076 区） | Text "›" 19、T.textSecondary #68686D、无左距 | 19px、--color-placeholder-strong #C0C0C6、padding-left 4 | 色改 #C0C0C6 等价令牌（T 加 placeholderStrong）、加 .padding(.leading, 4) |
| 51 | 斜杠面板宽（:5830） | min(360, vw−32) | min(360, max(220, 内容估宽+12, vw−24))（render.rs:650） | 宽公式换 Web 口径：内容估宽按 SlashCmds 全表行宽公式（render.rs:637-649 同法移植）；窄屏差 8、典型机差 2 |
| 53 | 斜杠横向锚（panelLeftX :6278） | 栏左缘锚（0.9.22 实现选择） | left = min(视口右对齐, anchor_x−8) 钳 12（光标 x 锚） | 改判候选：原生锚块左缘是既有实现选择、行为差仅在靠右输入时显形；若改，需 BlockTextView 回传 caretRect 的 x——涉及编辑器坐标通道，成本与收益不匹配，建议改判保留并登记 |
| 56 | slashRow 副文距（:6450 区） | VStack spacing 1 | 文案列 gap 2 | spacing 1→2 |
| 58 | slashGroupHeader（:6425 区） | 文字 pad H9、首组 top 2、无字距 | padding 6/8/4、letter-spacing 0.035em（≈0.4px） | pad H9→8、首组 top 2→6 量级对表、加 .tracking(0.4) |
| 59 | slashRow 快捷键丸（:6470 区） | pad V3 H6、radius 6、无 opacity | 面板内 opacity 0.78 | 加 .opacity(0.78)（丸整体，含底） |
| 60 | slashRow 最近丸（:6456 区） | 字 10、pad H5、radius 6、fillHover 无边 | 字 11、pad 2/6、radius 999、glass-control 底 + 0.5 边 | 字 10→11、radius 6→999、底改 glassControl 档 + 0.5 描边 |
| 61 | slashEmptyState（:6395 区） | 图标 font 24、主文 14 semibold 主色、提示 12 | 图标 SVG 28、主文 13 次级色（常规字重）、提示 11 | 图标 24→28、主文改 13/T.textSecondary/regular、提示 12→11；VStack spacing 与 padding 按 editor.css:526-528 对表（24/12/20） |
| 64 | linkFormPanel 输入框（:6510 区） | pad H12、无边框、fillSubtle 底 | padding 9/11、border 1px、radius 10 | pad H12→11、加 1px 描边（T.borderSoft 等价 --border-color） |
| 66 | linkFormPanel 动作钮（:6530 区） | 字 14 semibold、pad H16、无 min-width | 字 13/600、padding 0 14、min-width 76 | 字 14→13、pad H16→14、加 .frame(minWidth: 76) |
| 72 | errBadgePanel（:6190 区） | 宽 min(320, vw−32)、滚动区 maxHeight 280 | 宽 320（窄屏才有别）、max-height 360（含 padding 14×2 + 头 ≈ 滚动区 ≈ 313） | 宽保持（窄屏 −8 属合理钳制，登记）；滚动区 280→313 |
| 74 | errBadgePanel 标题色（:6193） | 错误态 T.dangerBright #FF3B30 | 错误态 --color-danger-light #FF6B6B（警告态同为 #FF9500 无差） | T 加 dangerLight 令牌 #FF6B6B、标题错误态改用之（徽章底色 #70 不动，仍 dangerBright） |
| 75 | errBadgePanel 清除钮（:6198） | 11、次级色、无内距 | 11、padding 2/6、radius 6 | 加 .padding(.vertical, 2).padding(.horizontal, 6) + 底 RoundedRectangle 6（底色 Web 为透明、仅扩命中区） |

---

## 三、建议落码序

1. **A-1 #52 斜杠面板实测高定位**（独立一段：EditorUI 加 slashPanelH 状态 + 呈现处 onGeometryChange 量测与顶边公式 + slashPanel 加 maxH 参数；间距 8→10 同笔）。落码后单独构建一版，真机看过滤态/空态/下半部输入三场景的面板贴合再继续。
2. **A-3 #22/#23 双栏行度量**（twoPaneRow 两值，隔离小改，可与第 1 笔同版不同提交）。
3. **A-2 #25 菜单限高**（menuPanel 包 ScrollView + maxHeight；与第 2 笔同版次序后行）。
4. B 级整批搁置（按既定口径：微差不成批追；其中 #30/#35a/#18/#19 若日后动 exportPanel/menuPanel 时顺手带上，不单独成版）。

每笔落码后跑 verify_ios.sh；A-1 建议在 verify [7] 几何前提组补一条断言：呈现处不得再出现 `panelH: CGFloat = 320` 写死常数（防估高定位回潮）。
