# Web 全页面内容框对齐设置页口径（2026-11-28）

用户裁定（2026-11-28）：除编辑页、首页外，所有页面按设置页口径对齐；原生与 Web 两端都要（Web 侧为本批，原生侧另批）。本批只动 `rust/apps/web` 与 Web 侧脚本，未提交、未部署，留主线组 0.9.63。

## 一、标准口径（回源实测）

Web 设置页的内容框单点 = `styles/panels.css` 的 `.page-content`（设置/手势/备份/语言/诊断/日志视窗/图片七页共用类）：

| 维 | 值 | 来源 |
|---|---|---|
| 顶 | 126px | `.page-content` padding-top（避固定 PageHead） |
| 横 | 20px | 同上；tokens.css「尺寸与安全区」节既有令牌 `--page-padding-x: 20px`（落码前零消费，本批接入） |
| 底 | 40px + env(safe-area-inset-bottom) | 同上 |
| 宽屏钳 | **无** | 全 styles 实测：`.page-content` 无 max-width/居中规则，宽屏全幅（与原生 720 钳口径不同，Web 以源码实测为准，不移植原生数值） |

## 二、全页面盘点对比表

量测面 = 各页内容层 computed 口径来源（类规则/内联），顶/横/底单位 px，底含安全区记为「40+safe」。

| 页面 | 内容框实现 | 顶 | 横 | 底 | 宽屏 | 判定 |
|---|---|---|---|---|---|---|
| 设置 SettingsView | `.page-content` | 126 | 20 | 40+safe | 无 | 标准本体 ✓ |
| 手势速览 GesturesView | `.page-content` | 126 | 20 | 40+safe | 无 | 已对齐（复核） |
| 备份 BackupView | `.page-content` | 126 | 20 | 40+safe | 无 | 已对齐（复核） |
| 语言 LanguageView | `.page-content` | 126 | 20 | 40+safe | 无 | 已对齐（复核） |
| 诊断 DiagView | `.page-content`（根 `.diag-page` 无自持内距） | 126 | 20 | 40+safe | 无 | 已对齐（复核） |
| 日志视窗 DiagLogPage | `.page-content.diag-log-content`（后者只加 flex 撑满） | 126 | 20 | 40+safe | 无 | 已对齐（复核） |
| 图片 ImagePage | `.page-content.img-page-content` | 126 | **0（自持归零）** | 40+safe | 无 | **横向偏离 → 本批对齐** |
| 救援面板 `#mn-rescue`（index.html 内联） | 容器 padding 20（顶/底 = safe+20）、卡 max-width 520 居中、卡内距 22/20 | — | 20（卡内） | — | 卡钳 520 | 异形态只登记（见 §三） |
| 存储阻断 `.storage-blocked`（两态） | fixed 覆盖、居中空状态：padding (safe+24)/24/(safe+24) | — | **24** | — | 无 | 壳层阻断态只登记（见 §三） |
| 启动页 `.splash`（index.html 内联） | flex 居中、无内容框 | — | — | — | — | 品牌页排除登记 |
| 首页 `.container` | padding 46/16/…、宽屏 max-width 1240 | — | — | — | 1240 | **用户豁免** |
| 编辑页（detail） | editor.css 编辑器口径 | — | — | — | — | **用户豁免** |

浮层/底表/菜单（备份确认底表、导出面板、斜杠面板、菜单、toast、errbadge 面板）非整页，不在本批面内，排除理由即形态（fixed 浮层、自有口径且多有用户定案）。

## 三、豁免与边界登记

- **编辑页/首页**：用户明示豁免，未动。
- **图片页 contain 公式**：`.img-page-img` 的整图 contain（max-width/max-height:100% 相对内容盒、大图只缩/小图不放大/区内居中）为 2026-11-24 用户定案，本批**未动**；只改其外框边距（见 §四）。后果如实登记：可用区宽较此前减少 40px（左右各 20），大图 fit 渲染随之按新可用区缩放——探针以量测可用区为基准判读（§五），视觉终判归用户真机。
- **救援层**：只核值登记、未改。量测：容器横 20 与标准横同值；卡钳 520、卡内距横 20。但其形态是全屏居中卡片面板（遮罩 transparent、卡居中），不是流内滚动内容页——顶 126/底 40 的流内口径无对应面，**值不等价但形态不同类**。按工单「不破坏内联自包含形态、值不等价先回报不擅改」：本批不动，是否要把救援卡也纳入某种对齐由主线/用户裁量。
- **存储阻断态**（多标签独占/存储不可用两态，`.storage-blocked`）：应用内渲染的全屏阻断覆盖层、居中空状态呈现，与救援层同族（其 panels.css 注释自述呈现向救援层收敛）。横 24 ≠ 标准 20，顶/底为 safe+24 的居中口径、126 顶距无对应面。本批只登记不擅改，理由同救援层（壳层/阻断态独立性 + 居中形态）；若用户裁定阻断态也归口，再行收敛。
- **启动页**：外壳品牌页（wasm 就绪前呈现），非内容页，排除。

## 四、逐页处置（落码）

实际偏离只有图片页一处，外加单点本身的一处同义裸值收口：

1. **`.page-content` 横距接令牌**（panels.css）：`padding: 126px 20px …` → `126px var(--page-padding-x) …`。`--page-padding-x: 20px` 是 tokens.css 既有令牌（尺寸与安全区节），此前零消费、`.page-content` 自持裸值 20px 属同义常量——接入后横距单点落在令牌，computed 值逐值不变（smoke-rustweb-visual 实测 settings padding-top 126 不变、横距同值）。规则上方补全应用内容框单点注释（裁定出处与禁自持口径）。
2. **图片页外框对齐**（panels.css）：`.img-page-content` 删除 `padding-left: 0; padding-right: 0;`，外框边距随 `.page-content` 全口径（顶 126/横 20/底 40+safe）；flex 撑满与居中、`.img-page-img` contain 公式逐字未动。规则上方注释同步改判（旧「仅左右内距归零」口径退役、注明裁定与公式不变）。
3. **静态锁**（scripts/verify_rustweb.sh 新增第 19 节「全页面内容框对齐静态锁」；第 18 节为在途前向删除批所占，本节顺延）：锁 `.page-content` 单点形态、令牌本体在位、`padding: 126px` 声明全 styles 恰一处、`.img-page-content` 无左右归零残留。锁机制不锁呈现文本。判别力自检：两处变异（img 恢复归零、单点改回裸值 20px）在 /tmp 副本上均被检出判红（proven）。

其余已对齐六页只复核未动代码；各页内构件级内距（如 `.diag-note` 0/16、备份历史行内联样式）属构件口径、非页面内容框，不在本批面内，未动。

## 五、验证

- `cargo test --workspace`（本地全仓）：全套件 0 failed。
- `bash scripts/verify_rustweb.sh`（本地全仓）：**ALL PASS**，含新增第 19 节与在途第 18 节（前向删除批）。
- tree 探针（独立 scratch `/data/home/webframe`：本地现行源码打包送 tree 构建 dist，wasm 4,127,201 B，serve 8123）：
  - `probe_lightbox_page` **ALL PASS（80/0）**——图片页 fit 量测以新内容盒（横 20 后可用区）为基准：大竖图渲染宽==可用区宽、fit 期望逐项合、区内居中（偏差 ≤2）、小图不放大、无滚动。
  - `probe_diag_ui` / `probe_gestures` / `probe_backup_fresh` / `probe_page_transitions`（含⑧图片页进出组）**ALL PASS**。
  - `smoke-rustweb-visual` **ERRORS: none**（含「settings content padding-top 126 = 126px」量测）；`smoke-rustweb-settings` **ERRORS: none**。
  - `probe_pages_settings` 非门禁探针（设置/备份/诊断 vs 原版的只读对比审计探针，硬编码 Rust 8100 + 原版 8101 双服务），本次环境未备原版服务、连接失败——环境面缺失、非产品判读，不计入结论。
  - scratch 内 verify 的红仅缺子树假阳性（未含 storage-worker 与原生 iOS 子树，僵尸键/Worker 检查无从取面），以本地全仓 ALL PASS 为准。

## 六、部署前置条件

- 本批未部署。部署走既有通道（仓内 Pages API 部署器 + verify_live 口径），须以含本批的构建为源：部署构建戳应与 tree 探针所用构建同源核对（本批 tree 构建 wasm md5 可作比对基准，部署时以当次构建为准重新核对）。
- 部署须与在途 Web 侧改动（前向删除批 editor 面）合流后统一出构建，避免半批上线；组版/提交顺序归主线（注意 CI 不变量：bump 与 release 报告同笔）。
- 真机终判点：图片页大图横向留白变化（外框对齐后图两侧各 20px 页边距）观感、设置族各页呈现无变化（computed 逐值同前，预期无感）。
