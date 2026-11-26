# 活体验证报告 · 2026-11-26（Web 全量回归 + 原生接线深核）

执行：Simular Box「main」(cb-e5f228120912) 跑 Web 全量回归；原生接线深核在本机静态核查。只读验证，未改任何源码、未提交。

## 一、所测版本口径（重要）

- 本机 HEAD：`cd7c83d`（含 23d3c68 的 0.9.35 与其后的 verify_ios.sh 断言组提交）。
- Box 上的 `~/workspace/Moment` 不是 git 仓库（无 .git，为文件拷贝的子集：仅 rust / scripts / tests / tools / node_modules，无 docs 与 rust/apps/ios），`git pull` 无从执行；按任务口径以文件哈希比对定版：
  - 比对集合 134 个文件（rust/apps/web/src、rust/crates、tests、scripts、tools 下 .rs/.sh/.mjs/.css/.html/.json），**131 个与本机 HEAD 逐字一致**，含全部 Web 应用源码、全部测试脚本（run_all_tests.sh、57 套件脚本本体）、构建脚本。
  - 3 个 core 文件停在旧状态：
    - `rust/crates/core/src/md.rs`：内容与 `e12f8cc`（0.9.24）及更早一致——**不含** R3/R9（0.9.25）、R4（41bca61）、R5/R8（0.9.26）、R6（c409f47）、R7 的解析修正。
    - `rust/crates/ffi/src/lib.rs`、`rust/crates/storage/src/lib.rs`：内容与 `20ba3ef`（0.9.15 前）及更早一致——storage 不含逐篇容错 `list_memos_tolerant`，ffi 不含包装形 list 与 renderMathml。
- 结论口径：**本次回归证明的是「本机 HEAD 的 Web 层 + 旧 core（md.rs 停在 0.9.24、ffi/storage 停在 0.9.15 前）」组合全绿**。R3–R7 的 core 修正对 Web 的影响未被本轮覆盖（Web 的 MD 解析经 core 薄包装，探针跑的是旧 md.rs）；该缺口需待 box 树同步到 HEAD 后补跑一轮，或在本机以 cargo test 为准（本机 core 测试含 R 系列回归用例，此前各批均已全绿）。
- 跑前环境核查：8096 端口空闲、无遗留服务；served 身份以构建戳为准——box 本次构建 sw.js VERSION 与 wasm md5 一致（`13fe4fc11a`，跨机构建戳与生产 `71ca05965a` 不同属预期）。

## 二、Web 全量回归结果（box，bash tests/run_all_tests.sh）

前置三步全过：cargo test（core + storage，脚本 FAIL 标志未触发；日志保留 tail -3 显示 ok）、build web 成功、verify_rustweb.sh 全 ✓（仅 2 条既有非阻断警告：ja-JP 14 键、zh-TW 48 键与 zh-CN 同值疑似漏译，脚本设计为仅警告）。

| 类别 | 通过 | 失败 |
|------|------|------|
| 冒烟（smoke-rustweb 系列） | 15 | 0 |
| 探针（probe_* 系列） | 42 | 0 |
| **合计** | **57** | **0** |

脚本终判：**ALL GREEN**。失败套件：无；失败明细：无。

通过名单：smoke-rustweb、smoke-rustweb-w2、smoke-rustweb-w3、smoke-rustweb-i18n、smoke-rustweb-settings、smoke-rustweb-list、smoke-rustweb-editor2、smoke-rustweb-misc、smoke-rustweb-visual、smoke-rustweb-highlight、smoke-rustweb-blocks、smoke-rustweb-tails、smoke-rustweb-wiki、smoke-rustweb-gaps、smoke-rustweb-export、probe_title_geom、probe_drag_sort、probe_drag_pickup、probe_drag_handle、probe_bridge_input、probe_batch3、probe_card_menu、probe_list_cards、probe_canvas_focus、probe_lift_surface、probe_title_dock、probe_slash_anchor、probe_root_dim、probe_lightbox_page、probe_attachment_open、probe_menu_attach、probe_page_transitions、probe_undo_granularity、probe_avatar_button、probe_twocol_flow_span、probe_weather、probe_backup_fresh、probe_delete_undo、probe_empty_states、probe_gestures、probe_shortcuts、probe_tap_targets、probe_a11y、probe_img_reserve、probe_swipe_mouse、probe_sw_update、probe_rescue、probe_b_group、probe_click_dead、probe_load_stock、probe_diag_ui、probe_state_resilience、probe_music_cover、probe_music_capsule、probe_pin_guide、probe_idb_split、probe_icon_unify。

注：中途一次轮询以启动 shell 的 pid 判「DONE」系误读（setsid 后实际进程 pid 不同），以日志与 pgrep 复核后确认进程一直在跑，最终以脚本 ALL GREEN 行为准。

## 三、原生接线深核（本机，MomentApp.swift 对 bindings）

### ① FFI 函数调用点（bindings 共 20 个导出函数）

19/20 在 MomentApp.swift 有真实调用点（逐个核过调用语境，非注释提及）：

- MomentLibrary 方法（14）：attachmentData、attachmentIdsJson、avatarData、exportBackup、importBackup、libraryHash、listMemosJson、memoCount、putAttachment、removeMemo、searchIdsJson、setAvatar、upsertMemoJson、validateBackup——全有。
- 全局函数（4/5）：mdClassify、mdIsBlockPreview、mdParseJson、renderMathml——全有。
- open：以 `MomentLibrary.open(...)` 静态构造形态在 Library.load() 调用（MomentApp.swift:436），属正常 init 形态。

唯一无调用点：**runPhase0Checks**——阶段 0 自检链，其 app 内入口已于 0.9.12 按定案移除（自检使命结束）；它仍被仓库内的阶段 0 探针壳 `rust/apps/ios/src/App.swift:28` 调用，且保留在 FFI 表面与 checksum 契约内。属预期形态，非接线遗漏。

### ② 视图入口（struct View / ViewModifier / Representable 共 46 个）

逐个核过实例化点（`Name(...)` 构造或 `.modifier(Name(...))`），**46/46 全部有真实入口，无死视图**。其中仅一处引用的也都是真构造：ImageBlockView（BlockRow）、DiagView / BackupView / GesturesView / LanguageView（SettingsView 导航）、EditorHeaderView（EditorView）、MdCalloutView / MdMathView（MdBlockView）、MathWebView（MdMathView）、InlinePlayerView（VideoBlockView）、DinoView（AvatarView 占位）、ListView（@main WindowGroup 根）、ImagePageView（EditorView 的 navigationDestination）、ContentCard / OverlayCard（View 扩展的 contentCard/overlayCard 助手）等。

### ③ DiagLog 打点计数与分布

`DiagLog.shared.log` 调用点共 **78 处**（全部在 MomentApp.swift）：等级分布 info 43 / error 32 / warn 3。

带 Web 对齐 TAG 前缀的 39 处：EDIT 13、WEATHER 9、SCROLL 4、ERRBADGE 3、IMGPAGE 3、LAUNCH 2、CARD 2、PDF 2、SMOKE 1。其余 39 处为中文自述行（保存/删除/导入导出/头像/搜索/图片加载等失败与结果行，多为 error 级）。与线 5 报告的缺口结论一致：TAG 化覆盖集中在编辑/天气/滚动域，首页与设置族的动作打点仍以自述行为主，G3/G4/G5 的系统性补点属批 F 范围，本次深核未发现打点回退或新增死打点。
