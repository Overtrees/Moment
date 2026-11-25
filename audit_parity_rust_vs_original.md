# Rust 版 vs Web 原版平价性自查自证审计

- 日期：2026-11-25
- 基准构建：Rust 生产 `ffdc0845e2`（本地 main `25bf613`）；原版 = 仓库 `src/`（React 18 UMD，入口 `Moment.html`）
- 性质：只读审计，未改任何代码
- 用途：为「Rust 版是否可替代原版、原版 `src/` 是否可退役」提供证据底稿

## 方法与判定纪律

- 原版行为以 `src/` 源码行号为准；原版功能宣称清单取 `git show 251486e:README.md`（README 更新前的旧版功能表）。
- Rust 现状以 `rust/apps/web`、`rust/crates` 源码行号与 `TESTING.md` / `run_all_tests.sh` 的探针、冒烟清单为准（实测口径：15 套冒烟 + 42 探针，`run_all_tests.sh` 内去重计数）。
- 判定四档：**等价**（行为一致，有代码或探针证据）/ **有意偏离**（行为不同，但能指到定案记录）/ **增强**（Rust 多出且已定案保留）/ **缺失或未核**（无实现，或无证据可判）。
- 无代码或探针证据者一律标未核，不凭印象标等价；有意偏离必须能指到定案出处，指不到的按缺失处理。

## 总览

共对照 **66 项**：

| 判定 | 数量 | 说明 |
|---|---|---|
| 等价 | 43 | 含全部块类型中的 14 项、列表与编辑主链 |
| 有意偏离 | 9 | 每项均有用户拍板或定案报告出处 |
| 增强 | 11 | Rust 独有且已定案保留 |
| 缺失 | 2 | 均为用户已定案处置（见缺失清单） |
| 未核 | 1 | 数据反向互通，无测试证据 |

**阻断替代的缺失：0 项。**

---

## 一、列表页（9 项）

| # | 功能面 | 原版证据 | Rust 证据 | 判定 |
|---|---|---|---|---|
| 1.1 | 分组标签（今天/昨天/过去7天/过去30天/N月/YYYY年） | `src/app/runtime.js:90-107` getSectionLabel | `list.rs:745` section_label 同分桶；smoke-rustweb-list | 等价 |
| 1.2 | 排序（置顶优先 + updatedAt 倒序） | `src/app/memo-list.js:401-403` | list.rs 排序同口径；曾因「分组按 createdAt、排序按 updatedAt 两序分叉产出重复分组键致 trap」根治（build_groups 改按标签归并，提交 0636793，用户真机确认） | 等价 |
| 1.3 | 置顶/取消置顶（左滑动作层） | `src/app/memo-list.js:453` 置顶标签 + SwipeRow | probe_swipe_mouse、probe_delete_undo | 等价 |
| 1.4 | 搜索 | `src/app/memo-list.js:404-407` 内存子串过滤（matchesMemoSearch） | `list.rs:773` matches_search 同为内存子串匹配（标题+正文字段拼接）。注：FTS5 trigram 在 storage 层另有实现（`crates/storage/src/lib.rs:311` search + Worker `cmd_search`），阶段二演练验证过中文精确命中，但列表 UI 搜索路径两边均为内存过滤 | 等价 |
| 1.5 | 封面派生 | `src/app/memo-list.js:409-412` hasImageAttachment（image/gallery/图文/图片附件） | 渲染时动态派生：文档数据序第一张自有图，候选含附件图片文件、不含外部封面（2026-11-24 用户定案）；probe_list_cards 以像素取色锁封面身份 | 有意偏离 |
| 1.6 | 左滑删除 | 原版硬删、无撤销（proposals U3 列为待拍板第 1 条） | 软删 deletedAt + 8 秒撤销 toast，用户按 A 案拍板（批 12 U3）；probe_delete_undo | 增强 |
| 1.7 | 长分组折叠（同组同类 >2 只显首卡 + 展开钮） | 原版既有设计（曾被误报为缺陷、核对为与原版 1:1） | smoke-rustweb-list 子组折叠断言（展开 N 条=总数） | 等价 |
| 1.8 | 空状态 | 原版为空白 | 三态空状态（空库/搜索零结果/加载失败，批 12 P-U2 定案新增）；probe_empty_states | 增强 |
| 1.9 | 响应式布局（竖屏时间线/横屏三列/桌面四列） | 旧 README「看」一节 | probe_responsive、audit_wide_list；WL-W-5/W-6 经拍板维持原版口径、W-4 量测无差 | 等价 |

## 二、编辑器 — 块类型（16 项）

原版块集以 `src/editor/editor.render.js:35-97` 渲染开关 + `src/editor/md-blocks.js:92` 块级标签集为准；Rust 以 `rust/apps/web/src/blocks.rs:832` 起的块渲染分发 + `blocks.rs:3518` MdBlock 枚举为准。全块渲染有 smoke-rustweb-blocks 覆盖（字号/完成态/callout 三类/代码 pre/列表合并/图集/音乐/链接卡逐项断言）。

| # | 块类型 | 判定 | 证据与备注 |
|---|---|---|---|
| 2.1 | paragraph 段落 | 等价 | 两边同形；C-01 子节点口径已按拍板对齐原版（landing_plan §三 #9） |
| 2.2 | heading 标题（attrs.level） | 等价 | C-03 默认级与钳制口径已对齐（landing_plan 批 3） |
| 2.3 | quote 引用 | 等价 | C-04 结构对齐 blockquote>div（landing_plan 批 3） |
| 2.4 | todo 待办（attrs.checked） | 等价 | 圆形勾选 22px，smoke-rustweb-visual 量测 |
| 2.5 | divider 分割线 | 等价 | — |
| 2.6 | image 图片 | 等价 | 含尺寸预留几何（imgsize.rs，probe_img_reserve） |
| 2.7 | gallery 图集（attrs.items） | 等价 | D-17 几何（2 列/定高/内缩）已对齐（landing_plan 批 3）；probe_batch3 |
| 2.8 | imgTextCard 图文卡 | 等价 | C-14 占位与可达性已补齐（landing_plan 批 3） |
| 2.9 | imageTextRow 图文行 | 等价 | — |
| 2.10 | musicCard 音乐卡 | 等价 | input/loading/ready/error 状态机两边同构（原版 editor.render.js renderAtomicHTML）；loading 骨架呈现为脉冲式（提交 7e196c6）属呈现层小偏离，用户已确认关单 |
| 2.11 | link-card 链接卡 | 等价 | C-11/C-12 容器与骨架口径已对齐（landing_plan 批 3） |
| 2.12 | callout 独立块 | 增强 | 原版只落段落纯文本；Rust 结构化渲染为超集，landing_plan §三 #7 经拍板选 A 保留超集，图标已统一为 SVG |
| 2.13 | attachment 附件 | 等价 | 打开/分享链已经用户真机确认（PDF 附件行分享面板正常） |
| 2.14 | embedCard | 等价 | 两边皆段落兜底（原版 render 开关 default 支；Rust `editor/model.rs:251` 注释明示同口径） |
| 2.15 | video 视频块 | 增强 | 原版无此块类型；Rust 有结构化渲染（blocks.rs:1056），属 C-17 超集族、随同项拍板保留 |
| 2.16 | MD 复合形态（代码块/列表组/表格/嵌套引用） | 等价 | Rust MdBlock 含 Code/List/Table/Quote/Callout（blocks.rs:3518-3548+），与原版 BLOCK_TAGS（PRE/UL/OL/TABLE/BLOCKQUOTE）对应；MD-C10 围栏跨块合并已处理（landing_plan 批 3） |

## 三、编辑器 — 行为（16 项）

| # | 行为 | 原版证据 | Rust 证据 | 判定 |
|---|---|---|---|---|
| 3.1 | 斜杠面板（22 命令/搜索/拼音/最近使用） | `src/app/editor/commands.js` 22 个命令 id；`slash-model.js` 过滤与最近使用 | `editor/render.rs:27-48` SLASH_CMDS 22 条，oid 与原版 id 一一对应、kw/py 同源；smoke-rustweb-w2、probe_slash_rust | 等价 |
| 3.2 | Markdown 输入与失焦渲染 | `src/editor/editor.md.js` + md-blocks 三路渲染 | 批 3 C-28 等落地；probe_md_rust 与 probe_md_orig 双端对照 | 等价 |
| 3.3 | 行内语法（粗/斜/删/行内代码/高亮/链接/图片/原始 HTML 白名单） | editor.md.js 行内管线 + DOMPurify 白名单 | blocks.rs InlineSeg 全集（blocks.rs:2181-2211）；C-28 白名单面已对齐 | 等价 |
| 3.4 | 脚注（定义/引用/文末段） | `src/editor/editor.md.js:170-219` | InlineSeg::FootRef + extract_footnotes（blocks.rs:2221、2300，注释自述逐段等价实现） | 等价 |
| 3.5 | 上标/下标 | `src/editor/editor.md.js:286-296` | InlineSeg::Sup/Sub | 等价 |
| 3.6 | 双链 [[]] 与反向链接 | `src/editor/editor.md.js:302` wiki-link；`src/app/editor.js:114-115、3271` backlinks | wiki.rs 全套（wiki.rs:211 memo_wiki_targets 等）；smoke-rustweb-wiki | 等价 |
| 3.7 | 数学公式 | 原版 KaTeX JS 自托管渲染（vendor/katex 0.16.47，editor.md.js renderMath） | 纯 Rust 渲染 MathML（crates/core/src/mathml.rs），门控/防误判/红色原码兜底对齐（landing_plan §四 C-26）；呈现与 KaTeX 有视觉差，**用户拍板知情接受**（KaTeX 红线：不用原版 JS）；probe_katex / probe_katex_eval / probe_katex_visual | 有意偏离 |
| 3.8 | 标题胶囊 | 原版滚动自适应横竖排、点改 | 规格经用户单独定案豁免 1:1（等内空白/居中/弹性变宽，设计规范 §四）；probe_title_geom / probe_title_dock | 有意偏离 |
| 3.9 | 块拖拽排序 | 原版拖拽为未生效实现（单一 contenteditable 宿主） | 长按拾起体系（触摸 480ms/桌面 280ms），用户 2026-11-22 裁定（landing_plan §四 A-10）；probe_drag_sort / probe_drag_pickup / probe_lift_surface | 有意偏离 |
| 3.10 | 长按/右键卡片菜单 | 原版卡片菜单（audit_editor_full D 片基线） | 入口收口长按+右键、「•••」钮整删（提交 12dfe0c）；probe_card_menu | 等价 |
| 3.11 | 双栏独立模式 | 原版双 contenteditable 栏宿主（editor.render.js configureIndependentHosts） | 物理双容器 + 跨栏拖拽（原版没有），用户「独立容器」决策（landing_plan §四 A-1）；probe_twocol_matrix、probe_audit_indcols 系列 | 有意偏离 |
| 3.12 | 双栏流式模式 | 原版媒体块 column-span 整幅跨栏 | 2026-11-24 用户裁定宽屏流式不跨栏、回退两物理栏（覆盖 A-2 跨栏设计）；probe_twocol_flow_span | 有意偏离 |
| 3.13 | 撤销/重做 | `src/app/editor/use-history.js` | B-4 撤销粒度已对齐（打字爆发成步，probe_undo_granularity）；B-7 历史含 layout 成对快照为 Rust 多出的恢复面，已落地保留 | 等价 |
| 3.14 | 自动保存与持久化 | IDB/localStorage 双通道自动落盘 | persist 门面 + 差量保存；smoke 三段持久（返回/重开/刷新）多套覆盖 | 等价 |
| 3.15 | 拼音组合输入 | 原版 contenteditable 原生组字 | Dioxus 桥不拦截组合态，**用户真机确认通过（2026-11-21 生死门）**；probe_bridge_input 组字重放 | 等价 |
| 3.16 | 图文底表编辑 | `src/components/ImageTextSheet.js` | D-20「完成编辑」语义已按原版恢复（landing_plan 批 5） | 等价 |

## 四、设置与数据（12 项）

| # | 项 | 原版证据 | Rust 证据 | 判定 |
|---|---|---|---|---|
| 4.1 | 字号三档 | `src/components/SettingsView.js:24` fontSizeMap 14/16/19 | settings.rs font_px + 同名键 `sj_fontsize`；smoke-rustweb-settings（root rem 全应用缩放+持久） | 等价 |
| 4.2 | 笔记背景色（8 色） | BgSheet + memo.bgColor（`src/app/editor.js:296、3315`） | `editor/sheets.rs:262-263` 8 色同字段 bg_color | 等价 |
| 4.3 | 明暗主题 | 跟随系统（`src/styles/tokens.css:193` prefers-color-scheme） | 同为跟随系统（`main.rs:94` matchMedia + tokens.css:212） | 等价 |
| 4.4 | 界面语言 | 原版无 i18n 体系（src/ 全域无语言切换实现） | 五语言包（zh-CN/zh-TW/en-US/ja-JP/ko-KR）；smoke-rustweb-i18n | 增强 |
| 4.5 | 头像（自定义/按篇头像） | avatars 表随备份携带（`src/components/BackupView.js:143-155`） | avatars 透传保留（用户硬约束）+ probe_avatar_button 全链 | 等价 |
| 4.6 | Google 头像自动同步 | `src/components/BackupView.js:311` OAuth 后拉 picture 存 localStorage | 无 | 缺失（随 Drive 线定案移除，见 4.9） |
| 4.7 | 备份 ZIP 导出/导入 | `src/services/zip.js` + backup-validate | core/backup_zip.rs；cargo test 双向互通 + smoke W1（导出 ZIP 19 条目、导入确认弹窗） | 等价 |
| 4.8 | 原版格式数据导入 | 原版格式本体 | 独立迁移通道 D2（core::migrate，read_backup_zip_migrated）；两份真实原版验收包经通道导入与旧口径逐值一致（refactor_remove_compat.md §7） | 等价 |
| 4.9 | Google Drive 云备份/恢复 | `src/services/drive.js` 全实现（列表/选择/可续传上传/合并恢复） | 无实现；TESTING.md 明示「Drive 未连接如实报待定」 | 缺失（用户定案：待定，且设置页谷歌备份入口已按 2026-11-22 裁定移除；ZIP 导出导入覆盖 iCloud Drive 等手动路径） |
| 4.10 | 备份新鲜度呈现 | 原版无 | 设置行副文案 + 超期横幅（批 12 P-U8）；probe_backup_fresh | 增强 |
| 4.11 | 诊断/错误呈现 | ErrorBoundary + 浮动调试面板 + 编辑页错误徽章（旧 README 技术说明） | 错误徽章按原版恢复（E-1，errbadge.rs）之外，另有完整 Diag 页：300 行环、按天归档、等级过滤、日志视窗页与分享导出（probe_diag_ui 35 项） | 增强 |
| 4.12 | 附件管理（添加/打开/分享） | 附件行点击打开、图片自动渲染 | 全链等价且已经用户真机确认（含系统分享） | 等价 |

## 五、平台面（8 项）

| # | 项 | 原版证据 | Rust 证据 | 判定 |
|---|---|---|---|---|
| 5.1 | 天气（新建卡天气行） | 现行 src 为和风单源（`src/services/weather.js:50-64`）；历史单体曾有彩云兜底、模块化拆分时丢失 | 和风主用 + 彩云兜底双源（weather.rs），恢复历史单体口径；probe_weather + probe_weather_caiyun（主链出数、兜底触发链 proven） | 增强（附未核子项：彩云实调取数因 key 免费配额耗尽回 429 未证，载荷回放已证渲染口径） |
| 5.2 | PWA 离线（SW 预缓存） | sw.js 预缓存本地资源、离线可编辑（旧 README） | sw.js CORE 同戳换代 + verify §15 资产锁 | 等价 |
| 5.3 | SW 更新 UX | 原版 sw.js:101 skipWaiting 直通式 | 只出底部提示条、用户点击才 reload 接管（用户定案）；probe_sw_update 双版模拟 43 项全过 | 有意偏离 |
| 5.4 | 救援/恢复面 | 原版仅 ErrorBoundary 应用内兜底 | 独立救援层（与应用解耦、看门狗出条、修复启动只清 SW/缓存不动数据）+ 存储阻断页 + 会话降级链；probe_rescue、probe_blocked_ui | 增强 |
| 5.5 | 手势体系（左滑/长按/三指撤销重做） | SwipeRow + useSwipeGesture + beforeinput 历史手势 | B-5 三指撤销已补齐（landing_plan 批 1）；probe_gestures、probe_swipe_mouse | 等价 |
| 5.6 | 手势可发现性 | 原版无 | 种子「使用指南」+ 编辑器一次性提示 + 设置手势速览页（批 12 P-U1）；probe_gestures | 增强 |
| 5.7 | 图片查看 | 原版灯箱浮层 | 独立图片页取代浮层（2026-11-24 用户拍板，design_lightbox_rootcolor.md）；probe_lightbox_page，用户真机确认 | 有意偏离 |
| 5.8 | 桌面快捷键 | 原版无应用级快捷键 | / 搜索、n 新建、j/k 导航、Esc 返回（批 12 P-U6）；probe_shortcuts | 增强 |

## 六、数据层（5 项）

| # | 项 | 原版 | Rust | 判定 |
|---|---|---|---|---|
| 6.1 | 存储后端 | IndexedDB（MemosDB v8）+ localStorage | SQLite（SAHPool）主写 + IDB 镜像双写，观察期中（2026-11-25 用户拍板路线，audit_sqlite_integration.md）；冷启对账收敛 | 有意偏离 |
| 6.2 | 数据格式（备忘 JSON 模型） | {id,title,doc,pinned,createdAt,updatedAt} + 块 attrs 约定 | 模型类型化后主线只认原生形，已建模字段旧形只经迁移通道归一（core tests/model_typing 口径锁） | 等价 |
| 6.3 | 原版存量数据 → Rust 读取 | — | 每次加载先经迁移通道归一（validate-then-swap）+ 逐篇结构隔离（坏行原文进 quarantine 不判死整库）；真机存量实证：加载失败根治后整库恢复、逐篇隔离探针 231 项全过（probe_load_stock、probe_state_resilience、core tests/stock_isolation） | 等价 |
| 6.4 | Rust 数据 → 原版读取 | — | ZIP 容器与 manifest 形态与原版同构（refactor_remove_compat.md §7 D1 差异清单：容器不变、条目恒 {name,type}），推断可读；**但无任何测试实际以原版导入 Rust 导出包验证** | 未核 |
| 6.5 | 附件存储 | IDB attachments 文件式 | OPFS/IDB attachments 店文件式、不入 BLOB（定案口径） | 等价 |

---

## 缺失 / 未核清单（分级）

### 阻断替代

**无。** 全部用户可感知的主功能面（列表、编辑全块、备份、设置、天气主链、手势、图片查看）均有等价或经定案的偏离/增强实现与探针证据。

### 不阻断

| # | 项 | 性质与定案 |
|---|---|---|
| M-1 | Google Drive 云备份/恢复（4.9） | 功能缺失，但为用户明确定案：定为待定、设置页入口移除（2026-11-22），手动 ZIP 已覆盖云盘路径。属「知情放弃」，非未决缺口 |
| M-2 | Google 头像自动同步（4.6） | 随 M-1 同线移除；自定义头像功能本身等价（4.5） |
| M-3 | Rust 导出包 → 原版导入方向未实测（6.4） | 形态同构推断可读、无测试证据。若退役原版，此方向即失去意义；若保留原版作回退通道，则应补一次实测再定 |
| M-4 | 彩云兜底实调取数未证（5.1 子项） | key 本身有效、免费配额耗尽（服务端 429 实证）；兜底触发链与渲染口径已证。配额恢复后看 Diag `provider=caiyun-fallback` 行即可闭环 |
| M-5 | 三项拍板对齐项的落地形态未逐行复核 | landing_plan §三 #6/#8/#9（D-9 斜杠行内落地形态、B-6 撤销选区恢复、C-01 段落子节点）已于 2026-11-24 按默认口径拍板对齐原版；本轮审计未逐行复核其最终代码形态，按纪律登记为复核缺口（低成本可补） |

## 替代结论

**附例外可替代。** 66 项对照中 43 项等价、9 项有意偏离（全部有用户拍板出处）、11 项增强、2 项缺失（均为用户知情定案放弃）、1 项未核（反向数据互通，退役后即无意义）。原版的全部核心使用面——记、看、存、调——在 Rust 版均有等价或更优实现，且关键面已经用户真机终判（拼音组字、附件分享、图片页、无痕降级、列表点按）。例外只有两类：一是用户主动放弃的 Google Drive 线；二是用户知情接受的呈现差（公式 MathML 与 KaTeX 的视觉差）。

## 退役原版 src/ 前置条件清单

| # | 条件 | 说明 |
|---|---|---|
| R-1 | 原版线上站的处置决策 | 原版站在 overtrees.github.io/Mynote（仓库 About 仍指此址），与 Rust 站 mynote-rustweb.pages.dev 是**不同 origin、存储互不可见**。退役前须定：下线 / 跳转 Rust 站 / 保留只读，并给原版站存量用户留 ZIP 导出→Rust 导入的迁移口径（该路径已证，见 4.8/6.3） |
| R-2 | SQLite 观察期退出 | 与退役 src/ 无代码依赖，但「Rust 为唯一实现」的存储信心依赖观察期判据达成（≥14 天且 ≥30 次冷启对账全等/漂移可解释、零降级行，2026-12-09 后起评）；判据未达成前退役不影响功能，但回退面少一层 |
| R-3 | 反向互通取舍（对应 M-3） | 退役即关闭此问题；若想保留原版作回退，先补一次「原版导入 Rust 导出包」实测 |
| R-4 | 彩云配额恢复后闭环（对应 M-4） | 非退役阻断项；退役后天气面仍留此一未核点，建议在退役前等一次配额恢复顺手验掉 |
| R-5 | M-5 三项逐行复核 | 一次低成本代码核查即可销账，建议随退役批次一并做 |
| R-6 | src/ 的规格参照价值转移 | 本审计与各 audit_* 报告多处以 src/ 行号为原版行为据。退役时须确认这些证据已沉淀进仓库文档（设计规范/教训沉淀/CHANGELOG 已承接主要口径），或将 src/ 归档至仓库外只读副本，避免退役后行为规格无据可查 |
