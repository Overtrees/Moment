# 原生 ↔ Web 动效与微交互专项审计（2026-11-26）

口径：等价是底线、原生更优才用原生形态；等价以下照抄 Web。
方法：Web 侧逐项摘录 CSS `transition`/`animation`/`@keyframes` 与 rs/js 侧手势动效常量；原生侧全文件清点动画 API——**MomentApp.swift 全文仅 2 处 `.animation(`，`withAnimation` 与 `.transition(` 均为 0 处**，其余动效全部来自系统控件的隐含行为（NavigationStack 推送、swipeActions、.sheet/.alert 呈现、Toggle）。这是本维度的总病灶：凡 Web 自绘浮层/条/面板处，原生多为条件渲染瞬时显隐。

## Web 动效令牌（单一出处，tokens.css:198-204,294）

| 令牌 | 值 | 用途 |
|---|---|---|
| --motion-spring | cubic-bezier(0.34, 1.56, 0.64, 1) | 全部浮层 transform 曲线 |
| --motion-pop | 220ms | 菜单/导出面板/toast/拾起的 transform 时长 |
| --motion-fade | 180ms | 菜单/toast 的 opacity 时长 |
| --motion-sheet | 250ms | 底表 transform 时长 |
| --motion-sheet-fade | 200ms | 底表 opacity 时长 |
| --motion-slash | 140ms | 斜杠面板进场 |
| --motion-reorder | 260ms cubic-bezier(0.22, 0.61, 0.36, 1) | 拖拽兄弟让位 |
| --motion-page-transition | 280ms | 页面切换（reduced-motion 时归零，tokens.css:297） |

reduced-motion 全局熔断：base.css:635-639（全部 animation/transition 压至 0.01ms）。

## 差距表

| 编号 | 场景 | Web 参数（出处） | 原生现状（出处） | 判定 | 建议动作 |
|---|---|---|---|---|---|
| M1 | 页面切换·前进 | 整页 slideInFromRight 280ms cubic-bezier(0.22,0.61,0.36,1)，from opacity 0.94 + translateX(24px)（base.css:711；editor.css:151-154；main.rs:2339） | NavigationStack 系统推送：全页滑入、系统时长（约 0.35s）与曲线（MomentApp.swift ListView navigationDestination） | 参数偏差 | 二选一待裁定：保留系统推送（iOS 惯例）并登记有意偏差，或自绘 280ms/24px 转场照抄 |
| M2 | 页面切换·返回（设置/备份/图片/日志等子页） | 仅内容层 page-slide-out 280ms 同曲线，to opacity 0.92 + translateX(16px)；返回钮与标题胶囊不参与滑动（base.css:720-721；editor.css:159-162；settings.rs:259-261；main.rs:2770-2772 图片页、2980-2982 日志页） | 系统 pop 整页滑动，页头随页一起滑走 | 参数偏差 | 同 M1；注意 Web 的「页头静止、内容滑动」在系统转场下无法复刻，若照抄须自绘 |
| M3 | 列表卡片逐卡入场 | 无（仅整页 .page-enter；contentFadeIn/mainFadeIn 关键帧只有定义、全仓无引用点，base.css:1、editor.css:155） | 无 | 已对齐 | 无（两边皆无，勿自创） |
| M4 | 首页滚动紧凑态（头像渐缩/搜索隐/紧凑标题现） | 头像按 scrollY/30 进度内联渐缩至 0.55 并淡出（.page-title transition:none，base.css:76-79；main.rs 滚动处理）；搜索胶囊/面板 opacity 另带 280ms ease 过渡（base.css:284,295） | compactP 连续驱动 scale/opacity（MomentApp.swift:4165-4179），末端 .animation(.easeOut 0.18, value: compactP>=1)（4163） | 已对齐 | 无（连续进度同构；末端平滑为近似等价） |
| M5 | 搜索胶囊展开/收起 | 触发钮与展开面板交叉淡入淡出：opacity 280ms ease（base.css:284,295） | 两态条件渲染瞬时切换，无任何过渡（MomentApp.swift:4168 searchCapsule） | ✅ 0.8.8（两态交叉淡入 0.2s） | 两态同层叠放做 opacity 交叉淡入（0.28s ease），或给切换加 .transition(.opacity) + withAnimation |
| M6 | 列表左滑揭示与吸附 | 卡片 transform 过渡 220ms cubic-bezier(0.25,0.46,0.45,0.94)（base.css:160）；动作钮 transform 220ms 弹簧 + opacity 180ms（base.css:134）；过 -55 吸附、无全滑触发 | 系统 swipeActions（系统曲线与吸附；全滑已按批 2 口径关闭、色值已对齐） | 原生更优可留 | 无（系统左滑为 iOS 标准手感，参数不可调，批 2 已定此形态） |
| M7 | 删除撤销 toast 进场 | .backup-toast 进场 toastSlideUpBar 220ms 弹簧：from opacity 0 + translateY(24px) + scale(0.94)（base.css:664-668） | undoToast 条件渲染，无过渡（MomentApp.swift:4102-4103 呈现、4234 定义） | 缺失 | 加自绘进场：offset 24px + scale 0.94 + opacity，spring 曲线 0.22s（cubic-bezier(0.34,1.56,0.64,1) 近似用 SwiftUI spring(response:0.22, dampingFraction≈0.7) 或 UnitCurve） |
| M8 | 备份页 toast 进场（含加载 spinner 态） | 同 .backup-toast 220ms 弹簧上滑（base.css:657-668）；进行中态 spinner toastSpin 0.7s linear infinite（base.css:678-679） | toast 条件渲染无过渡（MomentApp.swift:4880）；无加载中 spinner 态 | 缺失 | 进场与 M7 共用同一 toast 动效组件；加载态如需补，spinner 用系统 ProgressView 即可（形态差另计） |
| M9 | 编辑器手势提示条进场 | .gesture-hint 无进场动画，条件渲染即终态（panels.css:11；main.rs:2676） | 该提示条功能本身未落地 | 已对齐（动效维度） | 动效无动作；功能缺失另案（E 批） |
| M10 | SW 更新条 / 救援条进场（Web 外壳层） | mnSwupdIn 220ms 弹簧：from opacity 0 + translateY(24px) + scale(0.94)（index.html:63,69,96） | 原生无此外壳层（版本更新不走应用内提示条） | 不适用 | 无 |
| M11 | 救援面板进场（Web 外壳层） | mnRescueIn 250ms 弹簧曲线、仅 opacity 淡入、无位移（index.html:103-104） | 原生无救援层 | 不适用 | 无 |
| M12 | 启动屏 | 恐龙 dinoFloat 2.4s ease-in-out infinite（translateY 0→-8px）+ spinner spinRotate 1.1s linear infinite（index.html:26-30，仅 no-preference 时启用） | 无启动屏，冷启直达列表（数据约 2ms） | 原生更优可留 | 无 |
| M13 | 编辑器 ••• 菜单进/出场 | opacity 180ms ease + transform 220ms 弹簧，起止态 translateY(-10px) scale(0.92)，transform-origin 85% -18px（右上锚点）；关闭同路反向、播满 220ms 才卸载（editor.css:1237 及 1225-1236 注释、.is-closing） | menuPanel 条件渲染瞬时显隐（MomentApp.swift:2645 呈现、2921 定义） | ✅ 0.8.8（常驻挂载+右上锚点 scale/offset/opacity 弹簧 0.22） | 以右上为锚点做 scale 0.92 + offsetY -10 + opacity 进出场（spring 0.22s），关闭走完动画再卸载 |
| M14 | 导出面板（菜单内切换）进场 | 与菜单同机制：关 animation、由 closing 态 + transition 承担，同令牌数值（panels.css:234；editor.css:1228-1229） | ui.showExport 条件切换瞬时（MomentApp.swift menuPanel 内） | ✅ 0.8.8（菜单↔导出同浮层淡入切换） | 随 M13 同一浮层动效组件一并处理（面板间切换亦做淡入+轻缩放） |
| M15 | 浮动底表进/出场（背景色底表、图文编辑底表） | .sheet-wrap：opacity 200ms ease + transform 250ms 弹簧，进场自 translateY(20px) 升起至 0、出场反向（editor.css:1267,1270-1273；图文底表 editor.css:549-551 同令牌） | 系统 .sheet + presentationDetents([.height(300)])：整模态自屏幕底滑入、系统曲线（MomentApp.swift:2849 bgSheet、2909） | 参数偏差 | 形态（系统 sheet）若保留则登记有意偏差；若要照抄须改自绘浮动底表（20px 升起 + 200ms 淡入、250ms 弹簧） |
| M16 | 确认弹窗（导出/恢复确认） | .backup-modal sheetIn 250ms 弹簧曲线、仅 opacity 淡入、无位移（panels.css:219-220；存储阻断页同，panels.css:310） | 系统 .alert（系统缩放+淡入） | 原生更优可留 | 无（批 4 S8 已定 alert 形态可留，系统动效为 iOS 标准） |
| M17 | 标题胶囊编辑态弹性生长 | .editor-title-capsule transition width 0.2s ease、以中心为锚变宽（editor.css:1198,1218-1222） | .animation(.easeInOut(duration: 0.2), value: ui.titleDraft)（MomentApp.swift:2819-2820） | 已对齐 | 无（时长同 0.2s；ease vs easeInOut 名义微差、视觉等价） |
| M18 | 编辑器标题坞滚动紧凑切换 | .editor-title-dock transition all 0.25s ease：坞收成一行、meta 隐藏均在过渡内（editor.css:1193；.scrolled .editor-title-meta） | ui.scrollY > 30 条件换视图、瞬时切换（MomentApp.swift:2746） | 缺失 | 坞容器加 .animation(.easeOut(duration: 0.25), value: 紧凑态 Bool) 并让两形态同层交叉过渡 |
| M19 | 块长按拾起 | transition translate/transform 220ms 弹簧至 scale ≈0.97（按视觉面分轴取值、每轴 ≥0.9 钳制），附抓握点位移补偿、抓握点全程不漂移（editor.js:2560-2566） | scaleEffect 0.97 瞬时切换、无过渡、无位移补偿（MomentApp.swift:2480） | 参数偏差 | 终值同为 0.97；给 scale/offset 加 spring 0.22s 过渡（withAnimation 包裹拾起与放下） |
| M20 | 拖拽兄弟让位 + 落位回弹 | 兄弟块 .mn-shift 以 transform 过渡 260ms cubic-bezier(0.22,0.61,0.36,1) 让位（editor.css:200；editor.js:2346,2362）；被拖块落位同弹簧 restore 归位（editor.js:2647,2699） | 拖动中兄弟块完全静止、不让位；松手 commitDrag 瞬时换位、无回弹（MomentApp.swift:2481 offset 直跟、commitDrag） | 缺失 | 拖动中按 dragDy 给相邻块加实时 offset 并以 0.26s 曲线跟随；落位加弹簧归位动画（与 E11 实测高落点同批做） |
| M21 | 拖拽触觉反馈 | 拾起时 hapticTap()（editor.js:2549） | 全仓无触觉反馈（无 UIImpactFeedbackGenerator / sensoryFeedback） | 缺失 | 拾起加 impact .medium、落位加 .light（注：Web 在 iOS Safari 触觉不可靠，原生补齐属等价更优方向） |
| M22 | 音乐/链接卡加载骨架 | 骨架脉冲 mynoteSkeletonPulse 1.4s ease-in-out infinite alternate（底色在 --border-color 与 --glass-content-border 间往复）（editor.css:451-455） | CardBlockView loading 态为系统 ProgressView 转圈（MomentApp.swift:3234） | 参数偏差 | 改骨架占位（封面块+文本线）+ 1.4s 交替脉冲对齐；或明确登记 spinner 为有意偏差 |
| M23 | 图片块/图片页加载占位 | 无加载动画规范（按真实尺寸预留几何占位，imgsize 口径） | ProgressView 转圈（MomentApp.swift:1124,5171） | 原生更优可留 | 无（补原版缺失的加载反馈，按「增强可保留」口径） |
| M24 | 斜杠面板进场 | slashIn 140ms ease：from opacity 0 + translateY(-4px)（editor.css:1368-1369） | 斜杠菜单未落地（E14 待排期） | 缺失 | 随斜杠菜单功能一并实现，进场照此参数 |
| M25 | 按钮/行/卡按下态（成体系） | .menu-item:active 背景（editor.css:1243）；.editor-export-choice:active scale(0.975)+背景、transition 150ms（editor.css:1261,1263）；.diag-today/.diag-capsule/.diag-export-btn:active scale(0.975)、transform 过渡 180ms（panels.css:278-296）；.set-row:active 背景、transition 150ms（panels.css:183-184）；.bg-dot transform 过渡 160ms 弹簧（editor.css:1277）；.undo-toast-btn:active 背景 accent-10（base.css:673）；.attachment-file:active opacity 0.6（editor.css:429）；todo 行 :active 背景（editor.css:416） | 普遍无按下态：列表卡片为 onTapGesture 零反馈；SetRow/菜单项/导出选项/诊断卡均为默认 Button，无背景或缩放按下态 | ◐ 0.8.8（RowPress/CardPress 两样式已套菜单项/导出行/设置行/撤销钮/诊断卡与胶囊/背景色点/搜索胶囊；列表卡为手势命中未套） | 引入统一 Pressable ButtonStyle：行/菜单项给背景按下态、胶囊/卡片类给 scale 0.975，过渡 0.15s；逐面套用 |
| M26 | 设置分段钮（文字大小）切换 | .seg-btn transition all 0.18s ease（panels.css:173） | 分段钮瞬时切换、无动画（SettingsView 文字大小段） | 参数偏差 | 给选中态加 .animation(.easeInOut 0.18, value: fontSizeKey)（微差，可随手做） |
| M27 | 待办勾选过渡 | checkbox transition background-color/border-color 0.15s ease，行 background-color 0.15s（editor.css:414,418,1305,1308） | 勾选瞬时换图、无过渡（BlockRow todo 钮） | 参数偏差 | 勾选圆加 .animation(.easeInOut 0.15, value: checked) / symbol contentTransition（微差） |
| M28 | Callout 折叠箭头旋转 | summary::after transition transform 0.16s ease，展开 rotate(180deg)（editor.css:274-276） | callout 折叠形态未实现（仅五变体静态渲染） | 缺失 | 随 callout 折叠功能一并实现 |
| M29 | 双栏开关 knob 滑动 | transition transform 160ms ease（editor.css:963） | 双栏未落地 | 缺失 | 随双栏功能一并实现（iPhone 竖屏本不呈现，优先级低） |
| M30 | reduced-motion 适配 | 全局熔断：reduce 时全部 animation/transition 压至 0.01ms（base.css:635-639）、页过渡令牌归零（tokens.css:297）、启动屏动画仅 no-preference 启用（index.html:27） | 无 accessibilityReduceMotion 检测（全仓未检得） | 缺失 | 引入 @Environment(\.accessibilityReduceMotion)，本表各动效落地时统一降级为瞬时/淡入 |
| M31 | 错误徽章进场 | .eb-badge ebFadeIn 0.2s ease 淡入（base.css:687-688） | 错误徽章（errbadge）未移植 | 缺失 | 随 errbadge 功能一并（原生已有 Diag 通道，是否移植待裁定） |
| M32 | 分组折叠展开/收起、删行 | 无专门动画（条件渲染/卸载即终态） | 瞬时增删行、无动画 | 已对齐 | 无 |

## 汇总

- 总项数：32（M1–M32）
- 已对齐：M3、M4、M9、M17、M32（5）
- 原生更优可留：M6、M12、M16、M23（4）
- 不适用：M10、M11（2）
- **参数偏差：M1、M2、M15、M19、M22、M26、M27（7）**
- **缺失：M5、M7、M8、M13、M14、M18、M20、M21、M24、M25、M28、M29、M30、M31（14）**

优先级建议（供排批参考）：第一梯队为用户可直接感知的浮层/条动效——M13/M14（••• 菜单与导出面板）、M7/M8（toast 统一动效）、M25（按下态体系）、M5（搜索展开）、M18（标题坞紧凑切换）；第二梯队为拖拽手感——M19/M20/M21（与 E11 同批）；M1/M2 页面转场涉「系统 vs 照抄」裁定，单独议；M26/M27 为随手微差；M24/M28/M29/M31 随各自功能落地；M30 随第一梯队动效落地时一并接入。
