# Mynote Rust Web 版「每页按钮/功能/模块显示渲染」全面审计报告

- 日期：2026-11-21
- 范围：列表页 / 编辑页外壳（斜杠与 md 渲染不在本报告，另有专项）/ 设置页 / 备份页 / 诊断页 / 全局项（启动、toast、深色、语言完整性、字号、SW）
- 方法：通读原版对应源码与 Rust 实现后，无头 Chromium（393×852、hasTouch）逐控件实测（点击/手势 → 断言 DOM/状态变化），同数据（real_backup.zip、allblocks.zip、合成多日期 zip）同视口与原版（8101）度量对比。Rust @8100、原版 @8101。
- 探针：probe_pages_list.mjs、probe_pages_editor_rust.mjs、probe_pages_editor_rust2.mjs、probe_title_fs.mjs、probe_pages_editor_orig.mjs、probe_orig_time.mjs、probe_pages_settings.mjs、probe_pages_global.mjs（均在仓库根目录）。
- 说明：列表/全局两线的部分报告原件存于 /tmp，因系统清理丢失，本报告中该两节据代理回执（含逐项结论与实测数值）重构，其中最高严重度条目已经主线源码复核（复核点在条目内标注）；设置/编辑两节为全文。

## 总览

| 分区 | 高 | 中 | 低 | 已知决策差异 |
|---|---|---|---|---|
| 列表页 | 1 | 2 | 4 | 0 |
| 编辑页外壳 | 0 | 2 | 10 | 0 |
| 设置/备份/诊断 | 1 | 4 | 7 | 3 类 |
| 全局 | 0 | 2 | 3 | 0 |
| **合计** | **2** | **10** | **24** | — |

最严重两条（均为高）：
1. **列表折叠组点击首卡是死点击**——既不展开也不打开备忘（列表 L1）。
2. **头像 avatars 全链路丢失**——Rust 导入不保存、导出无 avatars 键，真实备份往返静默丢 7 个头像（设置 S1）。

---

## 一、列表页

源码对照：原版 src/app/memo-list.js、src/components/{ImageCard,SwipeRow,LazyImage}.js、src/styles/cards.css、src/utils/time.js、src/utils/preview.js；Rust rust/apps/web/src/list.rs、main.rs 列表外壳、styles/base.css。数据：real_backup.zip + 合成 11 条 zip（置顶/今日×5/过去7天/30天/3月/2025 年、#标签、md 语法）+ 单条 zip 测空态；滑动手势 Rust 用 PointerEvent 序列、原版用 TouchEvent（其手势钩子只听 touch），均按真机语义处理；12h/24h 用 en-US / zh-CN locale context 分别实测。

### 正常项（实测通过）

| 控件 | 实测证据 |
|---|---|
| 头像 | 72×72、点击进设置、无头像时恐龙回退，两边一致 |
| 新建卡 | 文案与点击新建 → 进编辑器 → 新备忘落库，两边一致 |
| 搜索 | 触发胶囊与玻璃面板度量一致（面板 196×66、输入框 140、自动聚焦）；按标题/正文过滤、Esc 关闭、清空恢复全列表，两边一致 |
| 日期分组 | 置顶/今天/过去7天/过去30天 标题与归属正确；组内 updatedAt 倒序，两边一致 |
| 折叠（按钮路径） | 点「展开 N 条」展开、末卡「收起」回收，两边一致（首卡点击见 L1） |
| 滑动行 | 过阈值 -55 吸附 -168、未过回弹 0、打开态点卡只关闭、删除落库（reload 后不恢复），两边一致 |
| 图片卡 | 封面加载 naturalWidth=886、骨架/占位、标题/预览/时间行，两边一致 |
| 文本卡 | 预览 md 剥离口径、标签 chip 渲染与去重，两边一致 |
| 空状态 | 删光后空态文案、搜索无结果空白，两边一致 |
| 滚动联动 | scrollY 0/15/30/120 四点标题 transform/opacity 与原版逐项一致 |

### 异常项

**L1折叠态点击首卡是死点击（主线已源码复核）**
- 原版：折叠组点首卡 = 展开该组（memo-list.js 折叠渲染段）。
- Rust 证据：main.rs 折叠分支中 `.card-expand-wrapper` 的 onclick（toggle：有则移除 fold_key）与 MemoRow 的 on_open（insert fold_key）对同一次点击各翻转一次、互相抵消。
- 实测：Rust 点折叠组首卡后仍折叠、也不进编辑器；原版同动作正常展开。只能点「展开」小胶囊才行。图片子组与文本共用同一代码路径，同理受影响（夹具图片组 ≤1 条未单独触发，按代码判定）。

**L2置顶/取消置顶不刷新 updatedAt（主线已源码复核）**
- 原版证据：memo-list.js:302-308 togglePin 同时写 `updatedAt: new Date().toISOString()`。
- Rust 证据：main.rs 三处 on_pin 只翻 pinned 字段。
- 实测后果：置顶后组内排序不同（原版跃至组首、Rust 仍在组末）、取消置顶后分组顺序不同、落库字段与原版分叉（与原版互通时排序口径不一致）。

**L324 小时制下今日时间小时不补零（主线已源码复核）**
- 原版证据：src/utils/time.js:23 `String(h).padStart(2, '0')` → 「01:05」。
- Rust 证据：list.rs:857 `format!("{h}:{min:02}")` → 「1:05」（只补分不补时）。
- 实测：zh-CN（24h）locale 下今日卡片时间行受影响；12h 分支「上午 1:05」两边逐字一致。中文用户默认 24h，属高频可见文案。

**L4展开后末卡收起文案缺符号**：Rust「收起」，原版「▲ 收起」（分组折叠段文案对照）。

**L5已置顶备忘的滑动按钮文案不符**：Rust「取消置顶」，原版「取消」（源码对照；功能一致）。

**L6新建卡缺原版天气块**：原版 NewCard 含天气区（源码对照）。注：原版天气 key 为空、实际从不显示，两边用户可见结果一致，仅结构差异。

**L7滑动按钮 pointer-events 启用时机差异**（源码对照）：Rust 与原版 SwipeRow 在拖动中间态的可点时机略有不同，实测吸附/回弹/点击结果一致，影响小。

未测留白：google_avatar 头像图分支（两边均无该数据，仅源码对照一致）。

---

## 二、编辑页外壳（双 fab / 标题坞 / ••• 菜单 / BgSheet / 导出面板 / 链接表单 / 附件与图片入口 / 灯箱 / 图文面板）

### 正常项（实测通过）

| 控件 | 原版证据 | Rust 证据 | 实测 |
|---|---|---|---|
| 双 fab 尺寸/位置 | editor.js:2475/2744 | styles/editor.css:239-265 | 两边同值：46×46，左 (16,7)、右 (331,7)；左 fab 返回列表、右 fab 开关菜单均生效 |
| 标题坞布局 | editor.js:2510-2531（fixed、left/right 62） | styles/editor.css:1041 | 两边同值：dock x=62、w=269、top=7、展开态 h=144；头像 72×72；胶囊 h=66 |
| 标题截断显示 | editor.js:2499-2500（>10 字截断+…） | editor.rs display_title_of | 两边同值：12 字标题失焦后均显示「一二三四五六七八九十…」 |
| 标题编辑态字号/溢出 | editor.js:2504-2508（>5 字 11px、>11 字溢出定宽） | editor.rs:1919-1931 | 编辑中实测：6 字 → 11px；12 字 → 胶囊 overflow 类、定宽 184px（styles/editor.css:1052），与原版口径一致 |
| meta 行口径 | editor.js:2693-2710（timeAgo · N字） | editor.rs:1939 附近 meta_line | 格式一致；「冬日」两边均显示 0 字（字数公式只计段落首叶，两边同结果，非缺陷）；滚动态两边 meta 均隐藏、坞转横排、回顶恢复（时间标签刷新时机差见 E10） |
| 头像按钮 | editor.js:2533-2570（72 按钮 + accept=image/* 隐藏 input） | editor.rs:2005-2021（label + #file-avatar） | 默认恐龙图；选图后显示 img、重开备忘仍在；real_backup 自带头像两边均渲染 |
| 菜单面板度量 | editor.js:2782-2807（宽 246、right 16、top=safe+59） | styles/editor.css:1063 | 两边同值：w=246、x=131、y=59；点 scrim 关闭 |
| 菜单条目构成 | editor.js:2809-3162 | editor.rs:2081-2152 | 6 行顺序与文案逐项一致：双栏独立滚动/平板与 PC 可分别滚动两栏、撤销/快捷键→ Cmd+Z / 三指左滑、重做/快捷键→ Cmd+Shift+Z / 三指右滑、添加附件/图片、PDF 或文本文件、导出笔记/Markdown · HTML · PDF、更换背景色/为当前笔记设置专属底色；无多行漏行（原版菜单无字号项、无删除备忘项，两边皆无） |
| 双栏开关 | editor.js:2810-2835 | editor.rs toggle_twopane | 点击后 switch 态翻转、localStorage sj_editor_independent_scroll 1→0 可逆，菜单保持打开（两边同） |
| 撤销/重做功能 | editor.js:2840-2955 | editor.rs do_undo/do_redo | 输入 Z → 菜单点撤销 → Z 消失且菜单关闭；重做 → Z 恢复；无历史时重做行 disabled+opacity 0.3（两边同） |
| 导出面板 | editor.js:3162-3239 | editor.rs:2047-2079 | 宽 246、返回钮 46×46、返回回到菜单；三选项徽标与文案一致（MD/Markdown/保存为.md 文件、<>/HTML/保存为独立网页、PDF/PDF/打印或存储为 PDF）；MD/HTML 均触发下载、MD 后 toast「已导出 Markdown」且面板关闭；PDF 打开打印弹窗（选项尾 › 与底部说明缺失见 E5） |
| 附件入口 | editor.js:1305-1308、3284-3291 | editor.rs:2263-2276 | 菜单行触发文件选择器（multiple）；#file-attach 的 accept 与原版逐字一致；选 txt 后菜单关闭、附件块追加文末、点附件行打开 blob 新页（块文件名缺失见 E2） |
| 媒体入口 | editor.js 隐藏 media input | editor.rs:2278-2285 | #file-media accept=image/*、multiple，与原版口径一致 |
| BgSheet 结构 | components/BgSheet.js | editor.rs:2154-2200 | 标题「背景色」、副文「为当前笔记设置底色」一致；8 色点 44×44、列距 84、行距 56，两边同值 |
| BgSheet 色板 | src/styles/tokens.js:116 | editor.rs BG_COLORS（4278） | 8 色逐一同值：#eaeef2/#e8e0d4/#d4e8d0/#d0e0e8/#e8d0d4/#fff3e0/#e8e0f0/#f0e8d0（实测 computed 颜色两边一致） |
| BgSheet 行为 | components/BgSheet.js | editor.rs set_bg（1707） | 选色 → 表关闭、编辑根背景变该色；重开 → 对应色点带 sel 勾、「移除背景（恢复默认背景）」行出现；移除 → 背景回 #FAFAFA；点 scrim 关闭 |
| 灯箱 | editor.js:3333-3337 | editor.rs:2289-2295、blocks.rs Lightbox | 点正文图片 → 灯箱打开（img contain）；点任意处关闭（层级/底色数值差见 E6） |
| 图文面板 | components/ImageTextSheet.js | editor.rs:2297-2360 | 点图文卡文本 → 面板打开：标题「完整文本」、正文全文、按钮「编辑文字」→ textarea、「完成编辑」文案对齐（行为差见 E8） |
| 链接表单骨架 | editor/slash-panel.js:156-184 | editor.rs SlashPanel slash-link-form | 表单出现、取消关闭表单与面板、空提交出错误且表单保留（文案差见 E9） |

### 异常项

**E1标题编辑失焦后字号丢失（11/14px → 16px）**
- 原版证据：editor.js:2504-2508 及失焦提交段（失焦后长标题保持 11px，实测 fs=11px）。
- Rust 证据：editor.rs:1001 失焦清理 JS 执行 `el.style.fontSize = ''`（意图回退类驱动），但 styles/editor.css:1048 `.editor-title-input` 无 font-size 规则——字号仅由 TitleText 的 inline style prop 提供（editor.rs:963），清掉后无人补回，Dioxus 因 prop 未变也不重写。
- 实测（probe_title_fs）：编辑中 6 字 = 11px、12 字 = 11px 且 overflow 正常；失焦后 style 属性变空、computed = 16px，胶囊宽涨到 212px。短标题同理 14px → 16px。切换备忘重挂后才恢复。每次改标题必现。

**E2菜单添加的附件块不带文件名**
- 原版证据：原版附件块节点带顶层 name 字段（fixtures/allblocks.zip 中 attachment 节点含 "name":"测试.pdf"；原版 handleFilesSelected 写 name 进节点）。
- Rust 证据：editor.rs:4318-4368 attach_one 只把 name 写进 manifest，节点 extra 只写 fileId/status/image；blocks.rs:509 渲染时读 node 的 name，读不到回退通用文案。
- 实测：菜单添加 att_test.txt 后附件行显示「📎 | 附件 | 打开」，文件名丢失；导出 memos.json 里该块同样缺 name，原版打开此备份也显示不出文件名（互通性受损）。

**E3首次打开菜单时「撤销」即呈可用态**
- 原版证据：editor.js:2840-2855（past 为空时 opacity 0.3）；实测原版首开菜单撤销/重做均为 op=0.3。
- Rust 证据：editor.rs:1971-2000 右 fab 打开菜单前无条件 __mnSyncAll + hist_push，打开动作本身制造一条历史 → 撤销 enabled、op=1（实测）。点之只是恢复同一内容，无数据损害；反复开关菜单还会堆积重复快照（上限 50），极端情况下挤掉真实历史。

**E4菜单「添加附件」「更换背景色」两行缺 ›**：原版 editor.js:3021、3162 两行均有 ›（实测 innerText 含 ›）；Rust editor.rs:2126-2134、2140-2152 无 chevron（实测 chevron=false）。导出行有 ›（一致）。

**E5导出面板缺底部说明、三选项缺 ›**：原版 editor.js:3215-3239 每选项尾 ›、底部「PDF 会打开浏览器打印窗口，可在其中存储为 PDF。」；Rust editor.rs:2047-2079 无 footer 节点、选项无 chevron（实测面板全文无该说明）。

**E6灯箱层级/底色数值偏差**：原版 editor.js:3335 zIndex 10000、rgba(0,0,0,0.88)；Rust styles/editor.css:1158 z-index 6000、rgba(0,0,0,0.92)（实测 computed 同）。当前无更高层元素冲突，属数值未对齐。

**E7双栏开关缺无障碍语义、图标线宽不符**：原版菜单首行 role="switch"、aria-checked、图标 strokeWidth 1.8；Rust editor.rs:2083-2095 button.twopane-row 无 role/aria-checked，columns 图标 stroke_width="2.5"。

**E8图文面板：编辑框无 placeholder、「完成编辑」行为不同**：原版 ImageTextSheet.js:111-127 textarea placeholder「输入图片说明文字…」、onChange 实时保存、「完成编辑」只切回阅读态不关面板；Rust editor.rs:2320-2358 textarea 无 placeholder、编辑态动作 = 保存并关闭面板（实测点后 sheetGone=true）。数据不丢，交互口径不同。

**E9链接表单文案四处与原版不符**：原版 slash-panel.js:157 标题「链接地址」、168 placeholder「https://example.com」、184 提交「插入链接」，use-slash.js:357 错误「请输入有效的 http 或 https 链接」；Rust 实测：标题「插入链接」、placeholder「https://」、提交「插入」、错误「链接无效，请输入 http(s) 地址」。功能正常，纯文案偏差。

**E10打开备忘的当次会话内，标题坞 meta 时间不刷新**：原版 editor.js:754/768 doSave 恒写 updatedAt=now，打开后自动保存即触发——实测（probe_orig_time）打开「冬日」未做任何编辑，updatedAt 由 2026-05-20 刷新为当日、meta 显示「上午 9:36」；Rust editor.rs:651 updated_at 仅在 build_backup（落库/关闭）时更新，会话内 meta 用打开时的值（实测「5/20」）。关闭后两边最终数据一致，仅会话内显示与列表重排时机观感不同。

**E11标题输入 aria-label 不符**：原版「笔记标题」；Rust editor.rs:966 取 t("editor.untitled") = 「无标题」。仅读屏受影响。

**E12附件选择器取消时菜单状态不同（源码证据；无头无法取消 chooser 实测）**：原版 editor.js:1305-1308 先关菜单再唤起选择器，取消后菜单已关；Rust 仅在 #file-attach 的 onchange 关菜单（editor.rs:2263-2276），取消选择不触发 change → 菜单保持打开。

备注：导出 MD 下载文件名在无头 Chromium 下回退 "download"（非 ASCII 文件名已知回退），不作判定。头像实测备忘在 real_backup 中自带头像，换图流程以「设置成功且重开保持、无报错」为据，未做像素级前后对比。

---

## 三、设置页 / 备份页 / 诊断页

前置事实（影响多项判定）：① 原版设置页只有 3 组——外观（文字大小）/ 数据（备份与恢复单行）/ 关于（版本、联系我们）+ 页脚标语；**原版没有语言行、没有诊断日志行、没有诊断页**（grep 诊断/Diag 于 src/ 零命中；诊断系 Rust 按用户硬规矩新增）。② 原版备份历史条目不可点击恢复（仅展示），Rust 同样不支持，不计缺陷。③ 原版导入/导出确认表均不显示计数，Rust 确认表亦无（计数在完成 toast），与原版一致。

### 正常项（实测通过）

| 控件 | 原版证据 | Rust 证据 | 实测 |
|---|---|---|---|
| 设置行序/文案/页脚 | SettingsView.js:44-88 | settings.rs:70-170 | 两版 body 文本逐字比对：除 Rust 多语言/诊断两行（决策差异）外，行标题、副文案、排序、页脚「此刻，值得被记住。」完全一致 |
| 版本号 | constants.js:5 APP_VERSION 2.2.7 | settings.rs:160 写死 2.2.7 | 两版均显示 2.2.7 |
| 头像/账号区 | 两版设置页皆无 | — | DOM 均无头像/账号元素 |
| 字号分段控件 | SettingsView.js:30-35,52-64（三段 0.8125/0.9375/1.0625rem） | settings.rs:96-113 | 形态、选中态一致 |
| 字号生效+持久 | SettingsView.js:24-28（14/16/19px 写 documentElement + sj_fontsize）；font-boot.js:5 启动恢复 | settings.rs:15-22 同映射 | 两版点「大」后 root=19px、ls=large；Rust computed=19px、列表.item-title-text 随 rem 放大；reload 后两版均保持 |
| 语言 5 包状态机 | 原版无（决策新增） | i18n.rs:26-57、LanguageView | 初始：简体中文/使用中，其余 4 包/下载；点 English → GET /lang/en-US.json 200 → 全页英文、状态变 Active/Built-in；mynote_lang、mynote_pack_en-US 落盘；reload 保持；切回 zh-CN 正常 |
| 备份行 → 备份页 | SettingsView.js:68-74 | settings.rs:116-126 | 副文案「Google Drive 云端同步」+ › 一致，点击进入备份页 |
| 返回链 | SettingsView.js:38-41 | settings.rs:76-79 | 诊断→fab→设置→fab→列表逐级返回实测通过 |
| 备份统计数值 | BackupView.js:74-96 | settings.rs:188-198 | 种子态两版均「5 条笔记 · 0 个附件」；Rust 导入 real 后 2/17 与 zip 一致（计数口径差见 S9） |
| 导出下载/分享回退 | BackupView.js handleExportLocal（canShare→share、AbortError 不降级、余回退下载） | settings.rs:425-445 try_share_zip 三态 | 无头无 share：两版均回退下载；Rust Cancelled 不写历史不下载（代码核对） |
| 导入确认→完成 | 原版 restoreFromZipAtomic 原子恢复 | settings.rs:246-270 | toast「已导入：2 条备忘 · 17 个附件（已存本机）」，hero 与列表数据更新，与 zip 实际一致 |
| 导入取消 | 原版取消清 pending | settings.rs 取消清 modal+pending | 取消后弹窗消失、hero 与导入前逐字相同 |
| 历史新增与持久化 | BackupView.js:47-72 | settings.rs:38-55 | 导出/导入后均新增条目、localStorage 落盘、reload 后仍在（信息量差见 S5） |
| 历史条目点击 | 两版均无恢复功能 | settings.rs 历史行无 onclick | 点击无弹窗、数据不变，与原版一致 |
| 诊断页渲染 | 原版无（决策新增） | panels.css:212.diag-body（#111/#7cfc9a/mono/11px）；diag.rs:62 行格式 | 实测 bg=rgb(17,17,17)、color=rgb(124,252,154)；首行 `[09:32:17] APP start` 格式符合；mynote_diag_v1 历史恢复、reload 后仍在 |
| 诊断标签覆盖 | — | editor.rs 内 40+ 处 EDIT 日志等 | 一轮操作后 31 行：APP 8、LANG 7、SAFE 4、IMPORT 5、BACKUP 3、SET 2、EXPORT 1、IDB 1；EDIT 本轮未触发但代码证据充分 |
| 诊断清空/复制 | — | main.rs DiagView | 清空后仅剩自记 `DIAG cleared` 行且持久（口径注见 S11）；复制全部实测剪贴板 1489 字符与页面内容一致；按钮组 [刷新， 复制全部， 清空] 齐全 |

### 异常项

**S1头像 avatars 全链路丢失**
- 原版证据：导入 restoreFromZipAtomic 恢复 avatars 进 IDB avatars store；导出 buildBackupPayload 回填，memos.json 恒含 avatars 键（实测原版导出 keys=[version, exportedAt, memos, avatars]）。
- Rust 证据：settings.rs apply_import 只存 memos/manifest/attachments，不处理 avatars；导出模型无 avatars 字段（实测导出 keys=[version, exportedAt, memos]）。
- 实测：real_backup.zip 含 7 个头像，经 Rust 导入再导出后头像静默丢失，破坏 ZIP 互通完整性。备忘正文与 17 附件不受影响。

**S2备份导出文件名不一致**：Rust settings.rs download_zip 写死 `mynote-backup.zip`（实测下载 2168B）；原版为 `此刻备份_<YYYY-MM-DD>.zip`（历史 detail 实证 `此刻备份_2026-11-21.zip`）。日期丢失、同日多次导出同名覆盖。

**S3确认弹窗主按钮位置颠倒 + 标题不符**：导出/导入确认表形态对齐（实测 rect y641/h197 贴底悬浮），但 Rust 按钮序为 取消（上 @y725）/确认（下 @y779），原版为 确认（上）/取消（下）；标题 Rust 用「导出备份/导入备份」，原版用「确认导出备份/确认恢复备份」（settings.rs:316-360 vs BackupView.js sheet 段）。

**S4「上次备份」直出原始 ISO 串**：Rust hero 显示 `2026-11-21T09:32:29.271Z` 未格式化（settings.rs:195）；原版格式化为「今天/昨天 HH:MM 或 M/D HH:MM」，且仅云端上传成功才更新（本地导出后仍「暂无」），Rust 本地导出即更新——格式与口径双差。

**S5历史条目信息降级**：原版条目含状态色点 + detail（文件名或「N 条笔记」）+ 失败也记 + 只渲染前 6 条（BackupView.js:47-72 及渲染段）；Rust 仅 type/ok/title/at，无状态点、无 detail、失败不记、渲染全部（上限 20）；且历史键 `mynote_backup_history` 与原版 `memos_backup_history` 不互通（settings.rs:38-55,290-326）。

**S6导出确认表文案缺信息**：Rust「将全部笔记与附件打包为 zip 导出。」；原版含「头像」与「将通过系统分享面板保存或发送」。

**S7坏 zip 错误文案混入英文内部原文**：实测 toast「导入失败：zip: invalid Zip archive: Could not find EOCD（现有数据未动）」——功能正确（数据未动），但 EOCD 等内部术语直接示人（原版同类错误亦偏技术化，故低）。

**S8设置页数据组容器结构不同构**：Rust 备份/语言/诊断三行同置一个 `.backup-card`（settings.rs:115-152）；原版备份行是 `.list-group >.list-item` 独立圆角单行卡，与外观组同构（SettingsView.js:66-74）。

**S9附件计数口径差**：Rust = manifest.attachments 键数（settings.rs:188-198）；原版 = 遍历 doc 中 attachment 节点 fileId 去重计数（BackupView.js:74-96）。manifest 含未被引用孤儿附件时 Rust 多计；当前夹具未触发。

**S10英文字号分段按钮为全词**：en-US 下显示 Small/Medium/Large（lang/en-US.json settings.font_*），原版恒单字 小/中/大，按钮宽度随之变化。纯文案差异。

**S11诊断清空后自记一行**：清空后立即 `log("DIAG","cleared")`，列表永不真正全空（main.rs DiagView）。属留痕口径，与「清空即空」字面预期不符。

**S12导出成功 toast 文案/样式口径差**：Rust「已导出备份 ZIP」纯文本；原版「✅ 本地备份已下载 (.zip)」带类型图标（与全局 G2 同族）。

### 已知决策差异（不计缺陷）
- 设置页新增「语言」「诊断日志」两行、语言页、诊断页：原版皆无，系按用户要求/诊断硬规矩加入（settings.rs:58-60 注释明示）。
- 备份页 Drive 卡未连接、连接按钮 toast「Google 云备份目前待定，尚未接入」：既定决策（原版为真实 Google OAuth 全功能，含上传/断开/云端恢复）。

---

## 四、全局项（启动 / toast / 深色 / 语言完整性 / 字号 / SW / 视口 / 兜底）

源码对照：Rust main.rs、i18n.rs、lang/*.json、styles/tokens.css、index.html、sw.js；原版 src/app/launch.js、src/styles/{launch,tokens}.css、Moment.html、src/app/sw-register.js、sw.js。

### 正常项（实测通过）

| 项目 | 实测证据 |
|---|---|
| 启动 | splash 224ms → 列表 696ms，无白屏；有持久数据直达列表；种子不重复播种；启动不弹 toast（历史 bug 复验已修） |
| 深色模式 | 五页（列表/编辑/设置/备份/诊断）计算样式与原版同值：body #000、卡片 rgba(32,32,36,0.86)；令牌 diff 仅 Rust 多诊断补充令牌；theme-color 双值 meta 齐 |
| 语言完整性 | 5 包各 206 键、差集全空；en-US 下列表/设置/备份/编辑外壳四页 UI 残留中文 0（列表 CJK 均为用户数据）；ja-JP 设置页 21 键逐条核为合法日语汉字非漏译 |
| 字号全局 | 改「大」后根字号 16→19px，卡片标题/设置行/编辑正文三处同步 19px |
| Service Worker | 注册 scope 正确；dist/sw.js 版本戳 `869cb2b057` 与当前 wasm md5 前 10 位一致；预缓存 11 项齐；二次加载正常 |
| 视口/滚动 | 五页 scrollingElement 均为 html；scrollWidth 均 =393 无横向溢出 |
| 兜底 | 断网 reload 列表完整（SW 兜底）；预置坏 diag JSON + 非法字号值启动不崩；全程 pageerror 0 |

### 异常项

**G1toast 连续同文案触发时全程不可见（主线已源码复核）**
- Rust 证据：settings.rs:367 toast 以文案作 key（`div { key: "{status_text}"}`），status 信号同值写入不重挂，styles/base.css:553.status-toast 为纯 CSS 动画（2.6s 淡出 forwards），动画不重启。注：editor.rs 的编辑页 toast 同为 `key: "{ed_status_text}"` 同模式（主线查见），同根。
- 原版证据：BackupView.js:111-124 定时器移除制，每次触发重置计时。
- 实测：同页第二次导入相同 zip（toast 文案相同）后 40ms 高频采样 200 点，可见样本 0 个；跨页复测也被截断为 1459ms（首次 2899ms）。导入本身成功，但第二次起用户得不到成功反馈。

**G2toast 样式偏离 1:1**：原版为 left/right 16px 全宽条、radius-28、16px 字、带 ✅/❌/spinner 图标、可换行；Rust 为居中胶囊、radius-999、14px 字、无图标、nowrap + 省略号截断——长错误文案（如 S7）会被截断不全显。

**G3toast 残留 DOM**：淡出后元素以 visibility:hidden 留在 DOM 不卸载（原版超时直接卸载），与 G1 同根。

**G4SW 注册缺原版守卫**：原版 sw-register.js 有 https/localhost 守卫与 load 时机处理、失败有痕迹；Rust index.html 注册无同等守卫、失败静默。

**G5启动页无原版倒计时文案**：原版 launch 有倒计时提示，Rust 启动页无（单页架构差异，用户可见差异小）。

---

## 五、异常总汇总（按严重度）

### 高（2）
1. **L1 列表折叠组点击首卡死点击**——双 toggle 抵消，不展开不打开（main.rs 折叠分支）。
2. **S1 头像 avatars 全链路丢失**——导入不存、导出无键，真实备份往返静默丢头像（settings.rs apply_import/handle_export）。

### 中（10）
3. **L2 置顶不刷新 updatedAt**——排序与落库口径与原版分叉（main.rs on_pin ×3 vs memo-list.js:302-308）。
4. **L3 24h 制今日时间不补零**——「1:05」vs「01:05」，中文用户高频可见（list.rs:857 vs time.js:23）。
5. **E1 标题失焦后字号丢失**——长 11px/短 14px 均变 16px，每次改标题必现（editor.rs:1001 vs styles/editor.css:1048）。
6. **E2 菜单附件块不带文件名**——块渲染与导出 memos.json 均缺 name，互通受损（editor.rs attach_one / blocks.rs:509）。
7. **S2 备份导出文件名写死**——`mynote-backup.zip` vs 原版 `此刻备份_<日期>.zip`（settings.rs download_zip）。
8. **S3 确认弹窗主按钮上下颠倒 + 标题不符**（settings.rs:316-360 vs BackupView.js）。
9. **S4 「上次备份」直出 ISO 原串**且更新口径不同（settings.rs:195）。
10. **S5 历史条目信息降级**——无状态点/detail/失败记录/6 条上限，历史键与原版不互通（settings.rs:38-55）。
11. **G1 toast 同文案重触发不可见**——key=文案 + CSS 动画不重启（settings.rs:367；editor.rs 同模式）。
12. **G2 toast 样式偏离 1:1**——全宽条变居中胶囊、无图标、长文案截断。

### 低（24）
L4 收起文案缺 ▲ / L5 置顶滑动按钮文案「取消置顶」vs「取消」/ L6 新建卡缺天气块（实际不可见）/ L7 滑动按钮 pointer-events 时机 / E3 首开菜单撤销呈可用态 / E4 附件·背景行缺 › / E5 导出面板缺 PDF 说明与选项 › / E6 灯箱 z 6000·底色 0.92 vs 10000·0.88 / E7 双栏开关缺 role=switch·aria-checked、图标线宽 2.5 vs 1.8 / E8 图文面板无 placeholder、「完成编辑」关面板 vs 切阅读态 / E9 链接表单文案四处不符 / E10 打开备忘会话内 meta 时间不刷新 / E11 标题 aria-label「无标题」vs「笔记标题」 / E12 附件选择取消后菜单不关 / S6 导出确认文案缺「头像/分享面板」 / S7 坏 zip 错误混英文内部原文 / S8 设置数据组容器不同构 / S9 附件计数口径（manifest 键数 vs 引用去重） / S10 英文字号按钮全词 / S11 诊断清空自记一行 / S12 导出 toast 文案口径 / G3 toast 残留 DOM / G4 SW 注册缺守卫 / G5 启动页无倒计时文案。

## 六、结论

四页 + 全局共核查 100+ 控件点：主体功能与度量（fab/坞/菜单/面板/BgSheet/搜索/分组/滑动/字号/语言状态机/深色令牌/SW）与原版对齐，正常项均有实测数值支撑。异常 36 条中：高 2 条均为功能性问题（折叠死点击、头像丢失），建议优先修；中 10 条集中在文案/口径/状态显示与文件名、按钮序等 1:1 细节；低 24 条多为文案与无障碍/数值微差。本报告只审计未改代码，修复按主线队列进行。
