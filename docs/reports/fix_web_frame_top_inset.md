# Web 内容框顶距按自身几何调整（calc(安全区 + 81px)，间隙与原生新标准同值 28）

用户裁定（2026-11-28）：原生顶距已按上滑位置改判 126 → 81；Web 的 126 构成因素不同（避固定 PageHead），「按它考虑因素后调，视觉效果差不多就行」。本批按 Web 自身几何定值：顶距改 `calc(env(safe-area-inset-top) + 81px)`，页头底边→内容顶的视觉间隙与原生新标准逐值同为 **28**。未提交、未部署，留主线组 0.9.63。

## 一、量测表（回源实测）

锚口径统一：间隙 = 内容顶 − 页头底边，页头底边取页头组件最低元素（返回钮）下沿。

| 项 | 值 | 依据 |
|---|---|---|
| Web 页头底边锚 | 安全区 + **53** | `.editor-fab.left`：`top: calc(env(safe-area-inset-top) + 7px)`、高 46（editor.css:209–229）→ 底边 = 安全区 + 7 + 46。标题胶囊 `.page-title.compact` 底边 ≈ 安全区 + 40.4（字 17 × 行高 1.2 = 20.4 + 上下内距 12 + 边框 1，base.css:85–111），更浅、非约束边 |
| Web 内容顶起点 | 视口顶 + 0（流内无根偏移） | body 无 padding-top（base.css:13–19）；页面根 div 无顶内距（settings.rs SettingsView 根层）；`.page-current` 仅 position:relative（base.css:731）。故旧内容顶 = 顶距裸值 126 |
| Web 旧间隙 | 126 −（安全区 + 53）= 73 − 安全区；用户机安全区 59 → **14px** | 裸值口径下间隙随设备安全区漂移 |
| 原生页头底边锚 | 安全区 + **53**（同构） | ChromeView 返回钮：顶距 7 + 高 46（MomentApp.swift ChromeView）；胶囊顶 = 安全区 + 11（fix_frame_top_inset_81.md 锚点量测 70.3 @ 安全区 59） |
| 原生新标准间隙（目标） | **28**（与设备无关） | 内容顶 = 安全区 + 81（绝对 140 @ 59）− 页头底边 = 安全区 + 53 → 81 − 53（fix_frame_top_inset_81.md §二/§四） |
| **Web 新顶距** | **`calc(env(safe-area-inset-top) + 81px)`**；用户机 = 140px | 与编辑页 `.editor-pad` 的 `calc(安全区 + 155px)`（editor.css:1190）同式先例；安全区运行时 env 取值、不写死单机数值（项目红线） |
| 实达间隙 | **28px 恒定**（任意设备），与原生目标差 **0** | 81 − 53；硬约束核查：顶距恒大于页头底边偏移 53、余量 28，内容不与固定页头重叠/贴死 ✓ |

首卡交叉核对：两端首组头块同账 ≈28（Web `.section-header:first-child` 内距顶 4 + 14px 字高 ≈18 + 底 6，editor.css:139–149；原生同账 28，见原生报告 §一）→ 用户机首卡顶两端同为 ≈168（内容顶 140 + 28），与原生改判后首卡顶 168 逐值一致。

备选未取：裸值 140px 在用户机同达间隙 28，但间隙随设备安全区漂移（安全区 0 的桌面端达 87、安全区更大机型反缩），且违安全区动态适配红线，故取 calc 式。

## 二、落码（4 文件）

1. **`rust/apps/web/styles/panels.css`**：`.page-content` 顶距 `126px` → `calc(env(safe-area-inset-top) + 81px)`，单点一处；规则上方注释改写——补顶距构成（页头锚 53 + 目标间隙 28 + 裁定出处 + 量测指向本报告），横/底口径不变。各整页（设置/手势/备份/语言/诊断/日志视窗/图片）共用单点自动跟随，逐页零改动。
2. **`rust/apps/web/src/settings.rs`**：SettingsView doc 注「126px 顶距内容」→「顶距内容（.page-content 单点：安全区 + 81px，见 panels.css）」，注释账同步。
3. **`scripts/verify_rustweb.sh` 第 19 节改判**（注沿革）：单点形态锁改盯新式全文；计数锁改判——新式 `env(safe-area-inset-top) + 81px` 全 styles 恰一处 + 旧裸值 `padding: 126px` 全 styles 零残留（原「126 恰一处」锁退役）。
4. **`tests/smoke-rustweb-visual.mjs`**：头注「设置页顶距 126」改「安全区+81」；断言改判——无头环境安全区 = 0，computed 期望 `81px`，注中写明真机（安全区 59）为 140px。

影响面登记：图片页内容盒顶随单点 +14（用户机），可用高相应 −14，contain 公式未动、探针以实测内容盒判读（§三全过）；其余页仅顶距位移，无构件级变化。

## 三、验证

- **本机**：`cargo test --workspace`（rust/）全套件 0 failed；`bash scripts/verify_rustweb.sh` **ALL PASS**（含改判后第 19 节、第 18 节前向删除批）。
- **tree**（现行源码打包送 tree 构建，md5 c98665aa 对账一致；dist wasm 4,128,609 B，serve 8123）：
  - `smoke-rustweb-visual` **ERRORS: none**——关键量测行：`✓ settings content padding-top calc(safe 0 + 81) = 81px`（无头安全区 0 下 computed 逐值合式）；同跑实测 fab 46×46、top 口径同前，间隙合成 = 81 −（7 + 46）= 28 ✓。
  - `smoke-rustweb-settings` **ERRORS: none**。
  - `probe_lightbox_page` **ALL PASS（80/0）**——新顶距下图片页 fit/居中/小图不放大逐项合（量测以实测内容盒为基准）。
  - `probe_diag_ui` / `probe_gestures` / `probe_backup_fresh` / `probe_page_transitions`（含图片页进出组）**ALL PASS**。
  - `probe_pages_settings` 非门禁对比探针（需原版服务 8100/8101）本次环境未备、连接失败——环境面缺失、非产品判读，与前批同口径登记。

## 四、证据等级

- 几何量测与新值推导：proven（源码逐项回读 + 两端同构对照 + 首卡交叉核对）。
- 改后渲染：proven 至无头 Chromium 口径（computed 81px @ 安全区 0 与式逐值一致、各探针全绿）；真机（安全区 59）内容顶 140 与间隙 28 的栅格化观感：unknown，归真机终判。

## 五、真机 / Web 终判点

1. Web 设置页（真机浏览器，安全区 59）：首组标签/首卡与页头的视觉间隙与原生 0.9.63 设置页观感大致一致（两端间隙同 28、首卡顶同 ≈168）。
2. 设置族其余页（手势/备份/语言/诊断/日志视窗）顶距同动、无页遗漏。
3. 图片页：整图在新可用区内 fit/居中观感无异常（顶侧留白略增 14）。
4. 桌面端（安全区 0）：内容顶 81、间隙恒 28，不再出现旧裸值下间隙 73 的过松呈现——此为本次 calc 式的预期收益，一并判读。

## 六、部署前置条件

- 本批未部署。部署走既有通道（Pages API 部署器 + verify_live 戳比对），须与在途 Web 侧改动（前向删除批 editor 面、内容框对齐批）合流后统一出构建；组版/提交顺序归主线（CI 不变量：bump 与 release 报告同笔）。
