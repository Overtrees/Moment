# 自检全场景覆盖矩阵（UI 驱动 × 桥层场景 总注册表）

> 状态：**方案稿，未落码。** 基线 HEAD 9d9dd9f（0.9.55）；工作树含 U1
> （驱动核 + S1 + B-4 + 在席四工具，报告 impl_uitest_u1.md）、完成胶囊
> （impl_editor_done_capsule.md）、首页两线修复（搜索胶囊状态 + 首页布局，
> 在途）三批未提交落码，本矩阵的「现状」以该工作树为准。
>
> 起因：用户 2026-11-27 指示——自检覆盖要及于**所有页面、模块、功能**，
> 不止标题胶囊一处。此前场景清单散在两处：plan_ui_selftest_driver.md §4
> （S1/S2/S3，视图层）与 plan_bridge_m3.md §2（10 景，语义层）。**本文件
> 是此后唯一的场景注册表**：两方案的机制设计（驱动步进引擎、场景引擎、
> 夹具卫生、能力门、证据分级）继续有效，但「测什么、归哪批」一律以本
> 矩阵为准，U2/U3 与 M3a–c 及后续扩展批从矩阵取项，不再各立清单。
> 与 M3 十景的逐条对账在 §5，两套矩阵不并存。

---

## 0. 结论先行

1. **全集共 121 行**（§4 逐行）：首页 17、编辑页 52（壳/标题/转场
   12 + 块与编辑语义 11 + 拖拽/双栏/浮层 17 + 媒体/卡片/解析链 12）、
   图片页 6、设置族 12、启动/救援/OPS 10、桥 10、数据层与全局 14。
   其中已覆盖 17 行（构建期/已落场景/桥工具可直判）、计划覆盖 16 行
   （U2/U3/M3 既定批）、在途修复 3 行，**其余 85 行（含仅真机人工
   8 行）为缺口或仅构建期锁住源码形态、运行时行为从未被自动验
   过**——缺口主要集中在编辑页回路（浮层群、双栏、斜杠、块矩阵）
   与首页/设置/图片页的 UI 层呈现。
2. **新增两个扩展批 U4/U5**：U 方案原定的 U2（探针）/U3（拖拽半面）
   装不下缺口。U4 = 编辑器回路扩展（分 U4a/U4b 两小批、约 15 个场
   景单元），U5 = 首页/设置/图片页回路（约 9 个场景单元 + P4 首页
   几何探针）。M3a–c 按原方案不变，矩阵行逐行标注归属（§6 排批表）。
3. **分层裁定**：UI 驱动 64 行、桥层 24 行、双层 16 行、构建期 7 行、
   仅真机人工 8 行、非场景/待裁 2 行（永久人工清单汇总 §7）。
   诚实边界照 U 方案 §6 旧规：真实触摸投递、识别器仲裁、键盘/光标/
   拼音、像素栅格化五面**永远不进场景层**，驱动绿不得升级表述。
4. **排批按真机翻车史排序**：拖拽（三轮战）→ 转场/新建 settle（两轮）
   → 标题（点不动 + 横排卡死两连）→ 几何留白（截图连报四次）→ 搜索
   （0.9.55 新报）→ 首页几何（同批新报）→ 其余按模块风险顺延。

---

## 1. 范围与方法

### 1.1 范围

- **在内**：原生 iOS App 全部页面与模块、MCP 桥（App/中继/连接器三
  方）、Rust core/storage 经原生可观测的行为面、OPS/救援/启动链。
- **不在内**：Rust Web（Dioxus）版的页面行为——它有自己的验证线
  （verify_rustweb.sh + box 全量 + Web 真机门禁），本矩阵只在数据层
  行引用其共用 core 的构建期覆盖，不重复登记 Web 页面行。

### 1.2 清单来源（逐项回源，不凭印象）

| 来源 | 供料 |
|---|---|
| MomentApp.swift 结构清单（实测 grep） | ListView / EditorView / EditorHeaderView / BlockRow / 各块视图（Image/Gallery/Video/Attachment/ImgText/Md 系）/ CardBlockView / MusicPillView / ImagePageView / SettingsView / BackupView / GesturesView / WeatherView / LanguageView / DiagView / DiagLogPage / ErrBadgeOverlay / SplashHostView 等页面与组件全集 |
| 源码字面（MomentApp.swift） | 块型全集：paragraph/heading/todo/quote/callout/codeBlock/mathBlock/divider/list/image/gallery/video/attachment/imgTextCard/imageTextRow/musicCard/linkCard/md；斜杠命令 20 个（SlashCmds：paragraph/todo/quote/callout/codeBlock/divider/bulletList/numberList/image/imgTextCard/imageTextRow/musicCard/link + 行内 bold/italic/strikethrough/code/highlight/mathInline + mathBlock） |
| MomentBridgeProtocol.swift `toolNames`（实测） | 桥清单 30 件（M1 11 + M2 11 + 在席 4 + uitest 4），manifestHash `c0c991a6…` |
| verify_ios.sh 组目（实测） | [1]–[29]（[27] 为 M3 预留、[30] 为首页在途批预留）：构建期已锁面逐组对应到行 |
| crates/ffi/src/lib.rs（实测） | FFI 23 个 pub fn（18 方法 + open/open_readonly + md 三件 + render_mathml + run_phase0_checks）；core/storage cargo 测试 67 个 |
| audit2 四线（home/editor/settings/image_misc）+ audit_detail 五线（home/editor_blocks/editor_layers/image_page/settings/diag_ops） | 逐功能点盘点与历史待修登记（E1–E10 等） |
| audit_search_weather.md / audit_native_diag_rescue.md / audit_scroll_report.md | 搜索匹配域 H18、诊断自救对齐面、编辑器滚动历史 |
| impl_batch_k.md（F1–F11）/ impl_weather_settings.md（S/I 14 项）/ impl_rescue_r1/r2r3（S1–S13） | 音乐图片线、天气设置、救援机制的功能点与已修账 |
| plan_ui_selftest_driver.md / plan_bridge_m3.md / impl_uitest_u0/u1.md | 已落与已计划场景、引擎与地基现状 |

---

## 2. 层与现状的定义

### 2.1 层（每行恰一主层）

| 层 | 含义 | 证据上限 |
|---|---|---|
| **UI** UI 驱动场景 | uitest_run 内置场景：经注册面调具名入口（与手指同一闭包）、读状态/量测/Diag | 状态机、呈现结构、布局几何、落盘 = proven；命中/仲裁/键盘呈现不在内 |
| **BR** 桥层场景 | scenarios_run 内置场景：组合工具内部实现与内部服务（M3 引擎） | 数据/持久化/状态迁移/留痕 = proven |
| **2L** 双层 | 同一功能点两层各验一半（注明分工），或桥景内嵌一次 uitest 子步（M3 §3.2 单向组合） | 各半按所属层 |
| **BK** 构建期 | cargo test / FFI 契约 / verify_ios.sh 断言在构建时锁死，不需要运行时场景 | 源码形态与纯逻辑 = proven（**不等于运行时行为**，凡运行时行为另有行） |
| **HM** 仅真机人工 | 结构性不可驱动或属系统面/外部面，永远归用户终判（§7 汇总） | 用户实报 + Diag 判读 |

注：BK 是本矩阵在 U/M3 两方案四层之外补的一层——FFI 契约、core 纯
逻辑、五语包完整性这类面已有构建期 proven 的既成覆盖，硬塞运行时
场景是浪费；但凡某行的**运行时行为**未被构建期覆盖，构建期只记进
「现状」，行本身仍按行为归 UI/BR/2L 层。

### 2.2 现状值域

- **已覆盖**：注明出处（场景 id / verify 组 / cargo / 桥工具可直判 BK
  判读——指助手用现有 30 件工具编排即可判读、未成内置场景）。
- **计划覆盖**：注明已定批（U2/U3/M3a–c 原方案内）。
- **在途**：修复批正在落码（首页两线），场景待修复落地后建。
- **缺口**：无任何自动覆盖，本矩阵新登记，归批见「批次」列。

### 2.3 证据分级

承 U 方案 §6 逐场景落格规矩：每行场景落地时在证据包 grades 里声明
上限（stateMachine / geometry / persistence / hitDelivery /
recognizer / keyboard / rasterization 等），报告引用不得升级。本矩
阵各行只标层与归属，不预支等级结论。

---

## 3. 共享引擎件（各批复用，不许重造）

| 共享件 | 出处/现状 | 复用方 |
|---|---|---|
| 异步作业信封（runId + 轮询 + 证据包四件套） | U1 已落（uitest）；M3 引擎向 U 对齐（M3 §1.3 合并规则） | 全部场景批 |
| 落定判据四类（Diag 行 / 状态两轮一致 / 布局两测差 ≤0.5pt / 转场信号），禁写死睡眠 | U 方案 §3.3，U1 已实装 | UI 全部；BR 的 waitDiag 同源 |
| waitDiag / waitDiagPair + Diag 时间窗抓取 | U1 已实装 | UI 全部；BR 引擎内直读 DiagLog 同解析 |
| 夹具登记集 + 双标记 + 卫生链（关编辑器→软删→立即真删→libraryHash 前后对账，不过全场降格） | U1 已建（UITestFixtureSweep 含孤儿只报不删） | UI 全部；BR 共用同一登记集（M3 §4.3，谁先谁建已定：U1 建、M3 复用） |
| 并发门五项 + 步边界漂移检测（aborted_user_active）+ 失败复原链六步 | U1 已实装 | UI 全部 |
| run 互斥锁（驱动/场景共用一把） | M3 §8.5 归属未定，U1 驱动核已持锁——**本矩阵裁定归 U 侧**，M3a 引擎引用不重造 | U/M3 |
| 在席注册表 + 桥导航通道（EditorSeatRegistry / BridgeNavigationChannel） | U0 已落 | UI 开篇步、BR 重开腿、在席四工具 |
| 几何探针 P1/P2/P3（+ 本矩阵新增 P4/P5，见 §6 U2/U5）与 BlockState 量测通道、Radius 派生式（断言写关系式不写死数） | U2 落（P1–P3）；P4/P5 为矩阵增补 | UI 几何行 |
| 写安全底座 BridgeWriteSupport（写前快照/幂等/docHash 守卫/写后回读） | M2 已落 | BR 全部写景 |
| Diag 前缀族（LAUNCH/SMOKE/CREATE/TRANSITION/EDIT/DRAG/SCROLL/BRIDGE/UITEST/SCENARIO/RESCUE/OPS） | 各批已落 | 全部场景的 waitDiag 判据源 |
| 场景评审纪律（新场景逐个评审 scopes/夹具面/红线面 + 同步 CONNECTOR.md 目录） | U §8.4 / M3 §8.4 同口径 | U4/U5/M3 每景 |

---

## 4. 覆盖矩阵

### 4.1 首页（ListView；源：audit_detail_home、audit2_home、audit_detail_settings §I/J）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| HOM-01 | 页眉头像呈现与点按入口 | UI | 缺口（无注册面） | U5 |
| HOM-02 | 滚动紧凑胶囊收合/展开状态机 | UI | 缺口（状态可读、未注册） | U5 |
| HOM-03 | 搜索胶囊：展开→输入→回车收键盘→胶囊自动回缩（用户 2026-11-27 实报障） | UI | **在途修复**（首页线，verify [30] 预留）；场景缺口 | U5（修复落地后建景首跑） |
| HOM-04 | 搜索其余退出路径（取消/滑动收起/点进笔记）状态一致 | UI | 在途修复同批；场景缺口 | U5 |
| HOM-05 | 搜索匹配域（FTS：标题/正文/标签/卡片字段，H18 口径） | BR | 桥工具可直判（notes_search），未成景 | —（BK 按需；U5 在 HOM-03 景内抽样断言） |
| HOM-06 | 日期分组与排序、置顶序 | BR | 桥工具可直判（notes_list 回读） | —（BK 按需） |
| HOM-07 | 行卡封面派生（文档序首图、删除顺位/拖序跟随） | 2L | 缺口（取数可桥判、呈现结构未验） | U5 |
| HOM-08 | 行卡摘要/标签取数口径 | BR | 桥工具可直判（内容口径 audit_detail_home §七） | —（BK 按需） |
| HOM-09 | 行菜单（置顶/删除）动作链 | UI | 缺口 | U5 |
| HOM-10 | 滑动删除 + 8 秒撤销 toast 恢复链 | 2L | 缺口（数据腿由 M3b delete_restore 覆盖工具路径，UI toast 链未覆盖） | U5（UI 腿）+ M3b（数据腿） |
| HOM-11 | 新建卡天气块呈现（双源状态/IP 兜底城名） | BR | 计划覆盖（刷新链 = M3 weather_settings_flow） | M3a（链）+ U5（呈现读抽样） |
| HOM-12 | 新建卡点按新建→转场开篇 | 2L | 计划覆盖（桥腿 = M3 create_transition 经导航通道） | M3b（桥腿）+ U5（UI 腿） |
| HOM-13 | 点开行→转场→编辑器在席 | UI | 地基已落（U0 通道，工具级可达）；场景缺口 | U5 |
| HOM-14 | 空状态呈现 | UI | 缺口（结构读即可） | U5 |
| HOM-15 | 宽屏网格态布局几何 | UI | 缺口 | U5（P4 扩展） |
| HOM-16 | 首页几何账：顶区占位/首卡距顶/卡间距/左右边距（用户实报「顶到顶」） | UI | **在途审计修复**；探针缺口 | U5（P4 首页几何探针） |
| HOM-17 | 首页行卡/分组圆角派生回读 | UI | 构建期 [21] 锁派生式；运行时回读缺口 | U5（复用 U2 P5 技术） |

### 4.2 编辑页 A：壳 / 标题 / 转场（EditorView、EditorHeaderView、MomentEditorTransition）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| EDT-01 | 打开转场时序（TRANSITION claim>anim、kb>claim） | UI | 缺口（打点在位、无场景） | U4 |
| EDT-02 | 新建 settle 分段对基线（CREATE settle 各段阈值） | BR | 计划覆盖（M3 create_transition；解析器 metrics_create_settle 随 M3a 补出，§5 裁定） | M3a（工具）/M3b（景） |
| EDT-03 | 返回收口（保存→列表回读一致） | 2L | 缺口 | U4 |
| EDT-04 | 标题点按进入（竖排、短标题态） | UI | **已覆盖**（S1 步 2） | U1 ✓ |
| EDT-05 | 标题二次编辑（截断态再进入，会话 begin/end 成对） | UI | **已落 S1**（步 5 核心断言）；运行级首跑待 0.9.56（§6 前置） | U1 ✓ |
| EDT-06 | 横排坞点按不卡死（坞态会话锁存，会话期零翻转） | UI | 构建期 [28] + 真机已判（0.9.55）；**场景缺口**（S1 只跑竖排态） | U4（S1 变体 title_capsule_reedit_compact） |
| EDT-07 | 标题落点映射 B-4（算式/记号先行/施加回读） | UI | 构建期已覆盖（纯函数 tree 真跑 19/19 + [26]）；驱动断言缺口（S1 未验 caret） | U4（S1 扩展断言） |
| EDT-08 | 标题提交口径（trim/空回退/Enter 提交/Esc 还原） | UI | 部分（S1 验改值回读；Esc 还原路径未覆盖） | U4 |
| EDT-09 | 完成胶囊（键盘态延展/点勾辞焦/抑制六格） | UI | 构建期 [29]；场景缺口 | U4（done_capsule_cycle） |
| EDT-10 | 编辑器滚动健康（滚动状态机/SCROLL 行完整性；间歇卡顿历史多轮未终判，audit_scroll_report） | UI | 缺口 | U4（editor_scroll_health）+ 人工体感（§7） |
| EDT-11 | 整页落焦热区（点空白处落焦，E2 口径） | UI | 缺口 | U4 |
| EDT-12 | 在席四工具语义（open/get_state/focus_block/save_now） | BR | 工具已入册（U1）；助手 BK 可直判，未成景 | —（BK 按需；M3b 两景复用其腿） |

### 4.3 编辑页 B：块与编辑语义（BlockRow、BlockTextView、Md 系、SlashCmds）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| EDT-13 | 文本块输入→防抖落盘→回读一致 | 2L | 缺口（驱动 setText 仅标题面，块面未注册） | U4（块面 setText 注册后） |
| EDT-14 | 撤销/重做回路（模型链 + 菜单项可用态） | UI | 缺口 | U4（undo_redo_roundtrip） |
| EDT-15 | 块拆分/合并语义（Enter 分块/Backspace 合并） | 2L | 构建期部分（core inline_editor cargo）；UI 链缺口 | U4（抽样并入 EDT-13 景） |
| EDT-16 | 待办勾选切换落盘 | UI | 缺口 | U4（block_type_matrix 内） |
| EDT-17 | 块类型呈现矩阵（全块型在位/帧落定/未知类型降级形态） | UI | 缺口 | U4（block_type_matrix） |
| EDT-18 | 斜杠菜单全链（触发/过滤含拼音首字母/最近使用/键盘导航/选中执行） | UI | 缺口（audit2 E4 四缺已修、未自动验） | U4（slash_menu_flow） |
| EDT-19 | 斜杠 20 命令逐个执行抽样（成块类型/行内标记） | UI | 缺口 | U4（slash_menu_flow 扩展段） |
| EDT-20 | MD 失焦预览切换与结构（MdBlockView 呈现入层级） | UI | 缺口 | U4 |
| EDT-21 | MD 渲染项结构（标题/引用/代码/高亮 ==/行内公式，audit2 E5/E7 登记项） | UI | 构建期部分（core md cargo）；呈现结构缺口 | U4 |
| EDT-22 | 公式块渲染（KaTeX→MathML） | BK | 构建期已覆盖（core render_mathml cargo + [11]）；像素呈现归人工 | —（像素 §7） |
| EDT-23 | 跨块方向键导航（audit2 E1，外接键盘场景） | HM | audit2 登记缺失、待定性；触摸面无此路径 | 人工保留（iPad/外接键盘另行终判） |

### 4.4 编辑页 C：拖拽 / 双栏 / 浮层

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| EDT-24 | 拾起状态机（pickup→drag→drop，块序落盘回读） | UI | 计划覆盖（U drag_pickup_statemachine） | U3 |
| EDT-25 | 拾起 cancel 复位（状态清零/滚动锁恢复） | UI | 计划覆盖 | U3 |
| EDT-26 | 拖动态让位量与拾起菜单自动收起（>10 收菜单） | UI | 计划覆盖 | U3 |
| EDT-27 | 拾起几何（玻璃框 = 面 ⊕4 同心、缩放口径） | UI | 计划覆盖（P2 lift_gaps，配合 U3 拾起或真机拾起） | U2/U3 |
| EDT-28 | 识别器仲裁（长按触发/全并行豁免/文本选区互斥） | HM | 结构性不可驱动（U 方案 §4.3 定案，三轮战故障全在此层） | 人工永久（§7）+ BRG 轨迹复核兜底 |
| EDT-29 | 真机拖拽轨迹归组复核（DRAG 全链行完整性） | BR | 计划覆盖（M3 drag_trace_review；U3 metrics_drag_trace 出货后切共用解析器，§5 对账） | M3a/U3 |
| EDT-30 | 卡片菜单骑拾起呈现（菜单随拾起、项集） | UI | 计划覆盖（U3 景内状态读） | U3 |
| EDT-31 | 双栏开关/分界锚/重开保持 | UI | 缺口 | U4（columns_roundtrip） |
| EDT-32 | 双栏独立滚动/栏内混排/落盘不串栏 | 2L | 缺口 | U4 |
| EDT-33 | 流式分栏切分（宽屏不跨栏口径） | UI | 缺口 | U4（columns_roundtrip 内） |
| EDT-34 | ••• 菜单打开/关闭与项可用态（撤销置灰等） | UI | 注册面已落（U1 menuPanel 面）；场景缺口 | U4 |
| EDT-35 | 菜单面板高（contentH vs renderedH vs cap 三值） | UI | 计划覆盖（P3 menu_panel） | U2 |
| EDT-36 | 斜杠面板高（slashPanelH 同机制三值） | UI | 缺口（与 EDT-35 同机制、探针未扩） | U2（P3 扩展） |
| EDT-37 | 导出面板呈现 + 三格式导出触发（状态腿） | UI | 缺口（分享系统面归人工） | U4 |
| EDT-38 | 背景色底表（开/选色/落盘后呈现） | UI | 缺口 | U4 |
| EDT-39 | 块菜单/卡片菜单独立打开（非拾起路径的项集与动作） | UI | 缺口（拾起路径见 EDT-30） | U4 |
| EDT-40 | ErrBadge 错误徽章呈现/展开信息量（K F5） | UI | 缺口（构建期 [22] 部分） | U4（抽样） |

### 4.5 编辑页 D：媒体 / 卡片 / 解析链

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| EDT-41 | 粘贴 URL 成卡（音乐/链接解析链 handler 路径） | 2L | 缺口；成功解析依赖外部源站（结论 inferred），error 卡路径可确定性验 | U4（music_link_parse：error 路径必验 + 成功路径抽样） |
| EDT-42 | 音乐卡 error 形态/空态/input 态（K F7/F8） | UI | 构建期 [22] 部分；场景缺口 | U4 |
| EDT-43 | 音乐胶囊状态（解析中/失败/成卡） | UI | 缺口 | U4 |
| EDT-44 | 选图插入成块（PHPicker 之后回落） | 2L | 系统选择器内操作归人工；成块断言缺口 | U4（成块腿）+ 人工（选择器内） |
| EDT-45 | 粘贴图片成块（E17） | UI | 缺口 | U4 |
| EDT-46 | gallery 增删/排序编辑（CardEditSheets） | UI | 缺口 | U4 |
| EDT-47 | 图文卡编辑底表（保存提交制，audit2 E10） | UI | 缺口 | U4 |
| EDT-48 | 附件添加（文件导入 + 真实文件名登记） | 2L | 构建期契约已锁（attachment_names，0.9.36）；场景缺口 | U4 |
| EDT-49 | 附件行打开分流（图片→图片页/文件→分享/非图不误入） | UI | 缺口（历史 diagnose_attachment_open 实证类） | U4（分流状态腿）+ 人工（分享面） |
| EDT-50 | 视频块呈现/播放器打开 | HM | 结构读可抽样，播放体感归人工 | 人工主（U4 结构抽样可选） |
| EDT-51 | 反向链接呈现 + 点按打开目标篇 | UI | 缺口 | U4（backlink_open） |
| EDT-52 | 编辑页头像点按功能（红线：有实际功能不得误伤） | UI | 缺口 | U4 |

---

### 4.6 图片页（ImagePageView；源：audit_detail_image_page、audit2_image_misc §1）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| IMG-01 | 打开路径三入口（图块/gallery 项/附件图片行） | UI | 缺口 | U5（image_page_open） |
| IMG-02 | 标题 = 真实文件名（清单优先、超 12 字截断单行不折行） | UI | 构建期部分（0.9.36 契约）；呈现断言缺口 | U5 |
| IMG-03 | 整图 contain 适配几何（大图缩小/小图不放大/居中） | UI | 缺口（探针可量测） | U5 |
| IMG-04 | 手动缩放（双击/捏合，只手动触发） | HM | 状态可读、手势跟手归人工 | 人工永久（U5 附带状态读） |
| IMG-05 | GIF 逐帧播放 | HM | 播放观感归人工；结构在位可读 | 人工主 |
| IMG-06 | 返回恢复编辑状态（go_back 恢复焦点/滚动） | UI | 缺口 | U5 |

### 4.7 设置族（SettingsView/BackupView/GesturesView/WeatherView/LanguageView/DiagView；源：audit_detail_settings、audit2_settings）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| SET-01 | 主设置分组结构呈现（audit2 §1.3 目标分组） | UI | 缺口（分组已修、未自动验） | U5 |
| SET-02 | 天气分组：双 key 状态/来源回读（绝不回值） | BR | 桥工具可直判（settings_get）；刷新链 M3a 景覆盖 | M3a |
| SET-03 | 天气自填 key 保存/清除（设置页 UI 路径） | UI | 缺口（桥侧 clear_weather_key 工具级已验） | U5 |
| SET-04 | 天气二级页逐字段保存（WeatherView，0.9.51 待终判项） | UI | 缺口 | U5 |
| SET-05 | 诊断自动清理开关（diagAutodel） | 2L | 桥工具可直判（settings_set_toggle）；UI 入口腿缺口 | U5（UI 腿） |
| SET-06 | 桥配对区呈现（连接状态/scopes/最近调用） | UI | 缺口（结构读） | U5（抽样） |
| SET-07 | 备份导出 ZIP（生成 + 清单回读） | 2L | 桥快照链已验同源 exportBackup；UI 导出面缺口（分享面归人工） | U5（状态腿） |
| SET-08 | 备份导入 ZIP（校验→整库替换→计数对账） | BK | 构建期已覆盖（core backup validate/import cargo）；导入需系统文件选择器，运行面归人工 | —（人工配合，§7） |
| SET-09 | 语言页五语切换呈现 | 2L | 桥腿计划覆盖（M3 language_roundtrip）；UI 呈现腿缺口 | M3a（桥腿）+ U5（UI 腿） |
| SET-10 | 手势速览页呈现 | UI | 缺口（静态、低风险） | U5（抽样） |
| SET-11 | 诊断页（列表/导出/自动清理执行） | UI | 缺口（导出分享面归人工） | U5（状态腿） |
| SET-12 | 日志视窗页（滚动/呈现） | UI | 缺口（低风险） | U5（抽样） |

### 4.8 启动 / 救援 / OPS（MomentLaunch/MomentOps/MomentRescue；源：impl_rescue_r1/r2r3、audit_detail_diag_ops）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| LCH-01 | 冷启健康（SMOKE/LAUNCH 行、首帧/数据分段） | BR | 桥工具可直判（diag_tail/app_state），历版发版已在做——**固化为发版清单项** | —（发版清单） |
| LCH-02 | 上次异常收尾检出（哨兵：停在编辑页/疑似强杀） | BR | 构建期 [13]；运行判读已实证（0.9.55 卡死会话即由此检出） | —（BK 判读，配合人工强杀） |
| LCH-03 | 安全模式进入 + 受限集 8 件逐个可用/其余拒 | BR | 计划覆盖（M3 safe_mode_drill，安全模式内腿为助手侧编排，§5 对账） | M3c |
| LCH-04 | 救援页动作（导出诊断/修复启动/清缓存入口） | HM | try_normal 已桥化（M2）；救援页 UI 操作归人工 + 桥判读留痕 | 人工主 |
| LCH-05 | 只读打开（R2）态下各面只读口径 | 2L | 构建期 [19]；场景为 M3c 条件项（只读腿） | M3c（条件） |
| LCH-06 | 清除可再生缓存（R3 S7，清前/清后字节回读） | BR | M3c 条件项（cache_clear_drill，随工具同批） | M3c（条件） |
| LCH-07 | OPS 双源拉取/合并/bootApplied 收敛 | BR | 计划覆盖（M3 ops_convergence，跨重启挂起续跑） | M3a |
| LCH-08 | OPS 源头发布（改源→回桥确认链） | — | **非场景**：助手侧 runbook（M3 §3.2 例外一），随 M3c 入 CONNECTOR.md | M3c（文档） |
| LCH-09 | 启动看门狗 12s / 快照环留痕 | BR | 构建期 [19]；桥工具可直判留痕 | —（BK 按需） |
| LCH-10 | Diag guard 真隔离（初始化环防回归） | BK | 构建期已覆盖（[12]） | — |

### 4.9 桥（MomentBridge* + 中继 + 连接器；源：impl_bridge_m1/m2、impl_uitest_u0/u1）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| BRG-01 | 配对流（新配对/重配对/解除，配对收敛五断点） | HM | 根治已落（0.9.52）；配对动作本身须用户在 App 内完成，桥侧判读状态 | 人工主（桥判读兜底） |
| BRG-02 | 错房钥匙三联征识别（list 过 + app_offline + App 显示已连接） | BR | 桥工具可直判，已实证处置流程 | —（BK 按需） |
| BRG-03 | scopes 双层门（write 未授拒、ops 放行、执行前拦截） | BR | 构建期 [16] + M2 上线实测；每版抽样 BK | —（发版抽样） |
| BRG-04 | 两段提交全链（令牌绑定/60s 过期/异参拒绝） | BR | 构建期 [16]；运行级全链判读缺口 | M3b（永删段景内继承验） |
| BRG-05 | 写安全底座（快照先行/幂等回放/docHash 守卫/写后回读） | BR | 构建期 [16]；运行级由 M3b 两景验 | M3b |
| BRG-06 | manifestHash 三方对账（App/中继/连接器逐名一致） | BR | 桥工具可直判（bridge_status），0.9.54/55 已实证——**固化为发版清单项** | —（发版清单） |
| BRG-07 | 安全模式受限分发（8 件集外一律 safe_mode_limited） | BR | 构建期 [16]；运行级随 LCH-03 景验 | M3c |
| BRG-08 | 在席守卫三处（删块/移块/软删，在席即拒不分脏净） | BR | 构建期 [25]；运行判读缺口 | M3b（两景内顺带）+ BK 抽样 |
| BRG-09 | uitest 作业面自检（并发门/漂移检测/复原链/卫生对账本身可信） | UI | 落码 + [25]；运行级验收 = S1 真机首跑两遍 + 人为回退旧结构应红在步 5（U 方案 §7.4） | U1 验收（0.9.56 组版后主线执行） |
| BRG-10 | scenarios 引擎自检（journal 落盘/跨重启续跑/run 互斥） | BR | 未落（M3a 建） | M3a |

### 4.10 数据层与全局（crates core/storage/ffi、i18n、圆角、动效）

| # | 功能点 | 层 | 现状 | 批次 |
|---|---|---|---|---|
| DAT-01 | FFI 契约 23 项 + UniFFI checksum 双向核对 | BK | 构建期已覆盖（[3]/[6] + 契约测试） | — |
| DAT-02 | core 模型/迁移归一/种子形态（cargo 67 测试） | BK | 构建期已覆盖 | — |
| DAT-03 | FTS5 trigram CJK 搜索（storage） | BK | 构建期已覆盖；桥侧回读见 HOM-05 | — |
| DAT-04 | 备份 ZIP 往返无损（validate-then-swap 单事务） | 2L | 构建期已覆盖（core backup cargo）；运行级恢复演练 M3b | M3b（运行腿） |
| DAT-05 | libraryHash 对账口径（卫生链真源） | BR | 已覆盖（U1/M2 各场景共用） | — |
| DAT-06 | SQLite 观察期冷启对账（≥14 天且 ≥30 次冷启全等） | BR | 进行中（Diag BK 长期判读） | —（长期） |
| GLB-01 | 五语包完整性（I1–I3） | BK | 构建期已覆盖（[9]） | — |
| GLB-02 | 编辑器 i18n 换键（I4）后全域文案呈现 | UI | 前置未落（I4 本体在队列）；换键后需一轮呈现抽样 | I4 落地后并入 U5 扩展 |
| GLB-03 | 语言切换即时生效（全页文案随切随换） | 2L | 分散在 SET-09 两腿 | M3a + U5 |
| GLB-04 | Dynamic Type 缩放下关键面布局不破 | UI | 缺口（探针抽样可验帧关系） | U5（抽样） |
| GLB-05 | 根背景同源/深色呈现 | HM | 令牌构建期在位；观感归人工 | 人工 |
| GLB-06 | 圆角体系运行时回读（半径单源/同心派生/复合卡内角直角构造） | UI | 构建期 [21][23] 锁派生与构造；**运行时回读缺口**（内角像素归人工） | U2（P5 radius_derivation） |
| GLB-07 | 圆角按 iPhone 机型动态适配（用户 2026-11-27 新问） | — | **另线调研中**（主线并行研究屏幕圆角/机型参数，结论回本行增补归批） | 待裁 |
| GLB-08 | 动效终态落点（转场/面板/胶囊动画结束态与状态一致） | UI | 分散覆盖（EDT-01/EDT-35/HOM-02 各行）；过程手感归人工 | —（各行内） |

**计数对账**：HOM 17 + EDT 52 + IMG 6 + SET 12 + LCH 10 + BRG 10 +
DAT/GLB 14 = **121 行**。层分布（逐行实数）：UI 64、BR 24、2L 16、
BK 7、HM 8、非场景/待裁 2（LCH-08 runbook、GLB-07 待裁）。

---

---

## 5. 与 plan_bridge_m3.md 十景逐条对账（合并/去重/改层点名）

M3 十景**全部保留、无一删除**；本矩阵只做三件事：给每景钉上矩阵行
号、点名与 U 批的重叠边界、裁定 M3 原方案的两处未决。U 方案 S1/S2/
S3 的对账附于表后。

| M3 景 | 矩阵行 | 对账裁定 |
|---|---|---|
| `drag_trace_review`（M3a） | EDT-29 | **保留·桥层**。与 U3 `metrics_drag_trace` 不是两套：同一归组解析器两期接入——M3a 先以引擎内直读实装，U3 工具出货后本景切共用解析器（M3 §2.1 既定），矩阵只登记一行，禁双轨维护 |
| `weather_settings_flow`（M3a） | SET-02 / HOM-11 | **保留·桥层**。验的是刷新状态迁移链；HOM-11 的呈现读是另一半（U5 抽样），不合并——链与呈现分属两层是既定分工 |
| `ops_convergence`（M3a） | LCH-07 | **保留·桥层（跨重启）**。无重叠 |
| `language_roundtrip`（M3a） | SET-09（桥腿）/ GLB-03 | **改判双层分工**：桥腿验偏好与生效码（本景），UI 呈现腿（各页文案随切随换）归 U5——原方案只登记桥腿，矩阵补 UI 腿一行，不算重复 |
| `delete_restore_roundtrip`（M3b） | HOM-10（数据腿）/ BRG-04 / BRG-05 | **保留·桥层**。与 HOM-10 的 UI toast 链分工点名：本景走工具内部路径验数据链，toast 的呈现与点按恢复是 UI 行（U5），两者同验「删除恢复」但不同层、不同入口，不合并 |
| `drag_semantic_reorder`（M3b） | EDT-24 的数据面 / BRG-08 | **保留·桥层为主**。与 U3 `drag_pickup_statemachine` 边界点名：本景验**语义块序与落盘**（经 editor_move_block 内部路径），U3 验**拾起后的编辑器状态机**（经 DragPress 回调）——同为「拖拽」但入口、证据面完全不同，各记一行。与 BRG-08 的关系：本景运行即顺带验在席守卫（重开腿经导航通道） |
| `create_transition`（M3b） | EDT-02 / HOM-12（桥腿） | **保留·桥层**。其 settle 解析依赖 metrics_create_settle——M3 §8.6 留主线裁的归批问题，**本矩阵裁定：随 M3a 补出**（与 M3 方案建议一致；U3 只管 drag trace 一件，不再捆绑） |
| `snapshot_restore_drill`（M3b） | DAT-04（运行腿）/ BRG-05 | **保留·桥层**。与构建期 core backup 测试分工：cargo 验格式往返，本景验真机快照→恢复→verifyStore 全链 |
| `safe_mode_drill`（M3c） | LCH-03 / BRG-07 / LCH-05（只读腿条件项） | **保留·桥层（跨模式）**。安全模式内自检腿维持助手侧编排例外（M3 §3.2 例外二）；只读打开腿维持条件项，随 R2 既有落地直接可加，不再等前置 |
| `ops_command_drill`（M3c） | —（运维命令本体未入矩阵行，属 M3c 工具批） | **保留·桥层**。前置不变：桥运维命令四件先落地 |
| 条件项 `cache_clear_drill`（M3c） | LCH-06 | **保留为条件项**，随 rescue_clear_caches 工具同批转正 |
| 例外：OPS 源头发布 runbook | LCH-08 | **维持非场景**（助手侧 runbook，M3 §3.2 例外一），矩阵登记只为防遗忘，不转场景 |

**U 方案三景对账**：S1 = EDT-05（已落，变体与扩展见 EDT-06/07/08）；
S2 三探针 P1/P2/P3 = EDT-35/EDT-27 与编辑页几何行的技术底座
（逐行归属在 §6 U2；HOM-17 的回读手段是 U2 新增的 P5，归 U5
复用）；S3 = EDT-24/25/26/30（U3）。U 方案 §7.4 的验收口径（S1 真机
首跑两遍 + 人为回退必红）登记为 BRG-09，不另立行。

**自此场景清单单一出处 = 本文件 §4/§6**；plan_ui_selftest_driver.md
与 plan_bridge_m3.md 保留机制与单景规格，新增/改名场景先改本矩阵
再落码（§8 纪律）。

---

## 6. 排批表（U2/U3/U4/U5/M3a–c 取项）

排序依据（真机翻车史）：拖拽三轮（0.9.47–0.9.49）＞ 转场两轮
（0.9.48/0.9.50）＞ 标题两连（0.9.54 点不动、0.9.55 横排卡死）＞
几何留白截图四连（0.9.54）＞ 搜索/首页几何（0.9.55 新报）＞ 音乐
图片线 K 批 11 项 ＞ 其余。U2/U3 为 U 方案既定批，取项以补齐矩阵
为准；U4/U5 为本矩阵新增扩展批；M3a–c 按 M3 方案原序。

### 6.1 U2 几何探针批（既定，矩阵补 P5 与 P3 扩展）

- **取项**：P1 `card_alignment`（服务编辑页卡面对齐类行，EDT-17 族）、P2
  `lift_gaps`（EDT-27，配合真机拾起先行、U3 后自给）、P3
  `menu_panel`（EDT-35）+ **P3 扩展 slashPanelH 三值**（EDT-36，
  同机制零新通道）、**P5 `radius_derivation`（新增）**：各卡面
  faceRadius 派生回读 + 复合卡子面角位构造读（GLB-06；像素仍归
  人工）。卡面 face 量测通道（BlockState faceMinX/faceW）为本批
  地基。
- **前置**：U1 已落 ✓；**S1 真机首跑两遍一致（BRG-09）为开工门**
  ——驱动运行时未被真机证明前，不在其上叠探针批。
- **夹具/卫生**：探针本身无夹具（测在席编辑器现状）；验收用的人
  为 +8 偏移测试构建沿 U 方案 §7.4 口径。
- **工作量**：face 通道 ~100 行（MomentApp 各卡面）+ 探针实装
  ~300 行（MomentBridgeUITest）+ verify [25] 扩项。约 M1 一期的
  三分之一。

### 6.2 U3 拖拽半面批（既定）

- **取项**：`drag_pickup_statemachine` 景（EDT-24/25/26/30）+
  `metrics_drag_trace` 出货（清单 30→31，EDT-29 解析器切换点）+
  P2 自给拾起联动。
- **前置**：U2（P2/face 通道）；行双锚点共存开销按 U 方案 §8.1
  以 CREATE settle/滚动量测对照把关。
- **夹具/卫生**：多块夹具模板（≥4 块多类型）由本批建，M3b
  drag_semantic_reorder **复用同一模板**（登记集共用，不另造）。
- **工作量**：场景 ~150 行 + metrics 工具 ~80 行 + 注册接线
  ~30 行 + [25]/[16] 同步。
- **证据钉子**：grades 必含 `recognizer: unknown (by construction)`
  （EDT-28 不因此行升级）。

### 6.3 U4 编辑器回路扩展批（新增，本矩阵主体批）

分两小批串行（同文件 MomentBridgeUITest.swift，避免并行改同文件）：

- **U4a 标题/键盘/斜杠/块矩阵**：EDT-06（S1 横排变体）、EDT-07
  （S1 caret 断言扩展）、EDT-08（Esc 段）、EDT-09
  （done_capsule_cycle）、EDT-18/19（slash_menu_flow）、EDT-16/17
  （block_type_matrix：全块型夹具一段验在位/帧落定/勾选/降级）。
  约 5 景、~600 行 + 注册面扩展（坞态控制、块面焦点读）。
- **U4b 转场/浮层/双栏/媒体**：EDT-01（transition_timing，
  waitDiag TRANSITION 时序断言）、EDT-03（close_roundtrip）、
  EDT-10（editor_scroll_health：程序化滚动状态读 + SCROLL 行
  完整性；体感仍人工）、EDT-11（落焦热区 invoke）、EDT-13/14/15
  （block_edit_roundtrip：块面 setText 注册 + 输入落盘回读 +
  撤销重做 + 拆分合并抽样）、EDT-20/21（md_preview_assert）、
  EDT-31/32/33（columns_roundtrip）、EDT-34/37/38/39（浮层群：
  菜单/导出/背景/块菜单状态腿）、EDT-40（ErrBadge 抽样）、
  EDT-41/42/43（music_link_parse：error 路径确定性验 + 成功抽
  样、音乐卡形态、音乐胶囊）、EDT-44/45/46/47/48/49（媒体编辑
  群：成块/粘贴图/gallery/图文底表/附件分流）、EDT-51/52
  （backlink_open、头像入口）。约 10 景、~1100 行 + 块面
  setText 与若干浮层注册面 ~200 行。
- **前置**：U2（几何断言手段）；块面 setText 的 IME 边界按 U 方
  案 §3.2 旧规（置草稿+提交链等价、逐字输入不等价，grades 钉
  keyboard: unknown）。
- **夹具/卫生**：全块型模板、多块模板、媒体模板（内置图/附件
  字节）三套登记集模板归本批建，后续批复用。

### 6.4 U5 首页/设置/图片页回路批（新增）

- **取项**：HOM-03/04（home_search_cycle：搜索胶囊全退出路径状
  态断言——本批头号景，专打 0.9.55 实报障类）、HOM-01/02/13/14
  （home_surface_roundtrip：头像/紧凑胶囊/点开在席/空态）、
  HOM-07/09/10（home_list_actions：封面派生呈现/行菜单/滑动删
  除 toast 链 UI 腿）、**P4 首页几何探针（新增）**（HOM-15/16：
  顶区段高账/首卡距顶/卡间距/网格几何，回数值断言关系式）、
  HOM-17（复用 P5）、IMG-01/02/03/06（image_page_open：三入口/
  标题/适配几何/返回恢复）、SET-01/03/04/05/06/09/10/11/12
  （settings_surface_roundtrip 群：分组呈现/天气 UI 路径/二级
  页/开关 UI 腿/配对区/语言呈现腿/手势页/诊断页/日志页抽样）、
  SET-07（备份导出状态腿）、GLB-02（I4 后并入）、GLB-04
  （Dynamic Type 抽样）。
- **前置**：**首页两线修复落地**（搜索胶囊状态根治 + 首页布局
  对齐，在途批）——修复前建景只会把红固化成基线；ListView/
  Settings/ImagePage 三处注册面新挂（首页此前只有 U0 导航接
  线，无 uitest 注册面）。
- **工作量**：注册面 ~250 行 + P4 ~120 行 + 场景 ~700 行 +
  verify [25] 扩项（或新组 [31]，落码时裁）。
- **排位说明**：本批排在 U4 之后，但 HOM-03 的**人工复核**不等
  本批——首页修复版出包后，主线先以真机 + Diag 判读收口该报
  障，场景是防回潮的固化手段，不替代首判。

### 6.5 M3a 引擎 + 只读/低危四景（原方案不变）

- **取项**：场景引擎 + journal + 注册表（BRG-10）、
  drag_trace_review（EDT-29）、weather_settings_flow（SET-02）、
  ops_convergence（LCH-07）、language_roundtrip（SET-09 桥腿，
  现配对标 scope_missing）、**metrics_create_settle 补出**
  （EDT-02 的解析器，§5 裁定）。
- **前置**：U1 信封已定型 ✓；证据格式向 U 看齐（M3 §1.3）。
- **工作量**：沿 M3 §6.3 估——新文件 ~800 行 + 分发器/清单/
  中继/连接器同步 ~80 行 + verify [27] 首批。
- **交付动作**：随本批交付**提醒用户 write 重配对**（M3b 与
  M2 写层、语言景同批解禁）。

### 6.6 M3b 写景四景（原方案不变）

- **取项**：delete_restore_roundtrip（HOM-10 数据腿 + BRG-04/05
  运行验）、drag_semantic_reorder（EDT-24 数据面 + BRG-08）、
  create_transition（EDT-02 + HOM-12 桥腿）、
  snapshot_restore_drill（DAT-04 运行腿）+ 工具
  backup_restore_snapshot。
- **前置**：**write 重配对（用户动作，M3a 交付时办）**；U0 ✓；
  U3 的多块夹具模板（若 U3 未及，模板由本批建、U3 复用——登
  记集归属按先落者，§3 表已定）。
- **工作量**：沿 M3 §6.3 估——场景 +500 行 + 恢复工具实装 +
  [27] 扩写景项。

### 6.7 M3c 运维打通（原方案不变）

- **取项**：桥运维命令四件（工具批）+ safe_mode_drill（LCH-03/
  BRG-07）+ ops_command_drill + 条件项 cache_clear_drill
  （LCH-06）与只读腿（LCH-05）+ OPS 发布 runbook 入
  CONNECTOR.md（LCH-08）。
- **前置**：**rescue_arm_safe_mode 布防消费点 + 入册小批**（M2
  §7.3 余项，U0/U1 均未带——本矩阵点名列为 M3c 的开工前置，
  不许临场发现）；R2/R3 已落 ✓（0.9.51）。
- **工作量**：沿 M3 §6.3 估——场景 +300 行 + 运维命令工具批
  （另账）+ [27] 扩运维项。

### 6.8 出包回归子集（每版固定动作，非批）

每版组版时从矩阵选子集跑，不全量跑 121 行：**常备子集** =
S1（EDT-05）+ LCH-01 + BRG-06 + BRG-03 抽样；**增量子集** =
本版所动模块的全部场景行。子集选取结果记入当版组版报告
（release_*.md），缺跑要在报告里点名。

---

## 7. 真机人工保留清单（永远归用户终判）

以下各面结构性不在驱动/场景证据内，任何批次的绿都**不构成**
对它们的结论；终判方式固定为「用户真机操作 + Diag/桥判读」：

| 面 | 覆盖行 | 为什么不可自动化 |
|---|---|---|
| 真实触摸命中投递（点得到/被谁吞/命中区形状） | 全部 UI 行的入口段 | 驱动不经 hitTest 链（U §3.5），恒「命中」 |
| 手势识别器仲裁（长按拾起触发、全并行豁免、文本选区与拾起互斥、0.48s/10pt 计时） | EDT-28 | 驱动绕过识别器直调回调；三轮战故障全在此层，只能真机手指 + DRAG 全状态行判读（EDT-29 桥景是判读兜底，不是替代） |
| 拼音组字/IME 全过程（组字、候选、连打、粘贴分段） | EDT-13 的输入过程段 | 驱动只置草稿与焦点状态；编辑器生命线，历来以系统键盘实测为准 |
| 键盘呈现与光标落点体感（B-4 落点投递精度、键盘升起时序手感） | EDT-07 的投递段、HOM-03 的键盘段 | 算式与单位可 proven（纯函数 + 回读），坐标投递到真机字段的精度只一例真机可判 |
| 动画过程手感（转场顺滑、胶囊生长、拾起弹簧、底表弹簧、菜单进场） | EDT-01/09/24、HOM-02 等 | 量测可证终态落点，不证过程；帧数口径探针是 Web 侧手段，原生无等价面 |
| 像素级栅格化（复合卡内角、玻璃边缘、阴影、圆角像素） | GLB-06 的像素段、EDT-22 | 探针证 clip 形状与帧，不证栅格化像素；机理曾判 unknown，只能同位复拍 |
| 触觉/声音反馈 | — | 无证据面 |
| 图片缩放手势跟手（双击/捏合） | IMG-04 | 状态可读，手势过程归人工 |
| GIF/视频播放观感 | IMG-05、EDT-50 | 播放是系统解码呈现，状态腿之外归人工 |
| 系统面板内操作（PHPicker 选图器、ShareSheet 分享面、文件选择器） | EDT-44、EDT-37、SET-07/08/11 | 系统 UI 不在 App 注册面内；只验进入前与回落后的 App 状态 |
| 外部服务结果（彩云额度、音乐/链接解析源站可用性、天气源数据） | EDT-41、SET-02、HOM-11 | 链路与状态迁移可验，结果正确性靠抽样人工/源站状态 |
| 配对与重配对动作本身（App 内确认、勾选 write） | BRG-01、M3b 前置 | 须用户在设备上完成，助手只能判读结果状态 |
| 强杀/重启类配合动作（LCH-02 的异常收尾制造、安全模式人工重开） | LCH-02/03 | 场景可挂起等人工（journal 续跑），动作本身归用户 |
| 真机性能体感（长列表滚动帧感、编辑器滚动顺滑） | EDT-10 的体感段、HOM 全表 | settle/量测给数值基线，顺滑与否归用户手感终判 |
| 外观观感（深色、玻璃质感、根背景同源的视觉确认） | GLB-05 | 令牌可锁，观感归人工 |

---

## 8. 未决点与维护纪律

1. **GLB-07（圆角按机型动态适配）**：用户 2026-11-27 新问，主线
   另线调研（屏幕圆角半径/机型参数来源、与现行 Radius 单源的关
   系）。结论落地后回本行补层与归批——若成立，P5
   （radius_derivation）的期望式要从「令牌派生」改「机型派生」，
   U2 落码时须为期望式留参数位，不许写死当代理值。
2. **EDT-23（跨块方向键）**：audit2 登记缺失、产品定性未裁
   （触摸面无此路径，iPad/外接键盘才有意义）。维持人工保留，
   待用户裁定是否立项后再议层属。
3. **矩阵维护纪律**：新功能落码批必须同批给本矩阵增行（行号
   只增不改，既有行号永不复用）；场景增删先改矩阵再落码；
   每版组版报告引用 §6.8 子集清单。矩阵与代码现状冲突时以
   代码 + 落码报告为准并同批修矩阵（同 WORKFLOW 沉淀纪律）。
4. **场景增长评审**：沿 §3 表末行纪律——每个新场景上线前逐景
   评审 requiredScopes/夹具面/红线面，UI 景另评审注册面与漂移
   面；正文红线（M3 §5.3 禁令）对 UI 景同样适用（夹具正文只
   许 App 内置模板，证据包不载正文）。
5. **U4/U5 的组号**：verify 组号 U4/U5 落码时按当时空位取
   （现 [27] M3、[30] 首页在途已占/预留，预计 [31] 起），不预
   先写死在本方案，以免与并行批撞号。

