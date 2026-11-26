# 全面排查第二轮 · 设置线（含分组专项）

只读审计（2026-11-26），不改代码。方法：先完整读原版与现行 Web 设置相关代码弄清设计用意，再对照原生。

真源：
- 现行 Web：`rust/apps/web/src/settings.rs`（SettingsView / GesturesView / BackupView）、`rust/apps/web/src/main.rs`（DiagView:2814 / DiagLogPage:2965 / LanguageView:3006）、`rust/apps/web/styles/{tokens,base,editor,panels}.css`、`rust/apps/web/lang/zh-CN.json`。
- 原版归档（出入标注用）：`~/workspace/.scratch/moment-original-archive-2026-11-25/src/components/SettingsView.js`。
- 原生现行：`rust/apps/ios/app/MomentApp.swift`（SettingsView:12056 起、BackupView:12358 起、GesturesView:12744、LanguageView:12823、DiagView:3045、DiagLogPage:3449、SectionHeader:12051、SetRow:12071）。

前轮（audit_detail_settings.md 63 条）已修项经批 E（0.9.40）与 i18n I2（0.9.41）落地的，本轮逐项复核通过、不重报：A1/A2 内边距、A7 首组 topPad、C2 glassLabel 色族、B2/B3/B4 新鲜度呈现、C3 超期横幅独立卡、C4 删多余节标题、C7/C9 文案、C10 最近操作内容形态、D1/D2 手势行、E1–E4 语言页、F1/F3/F5/F6/F7/F8/F9 诊断形态、G1/G2/G3 视窗页形态、B5 版本值字号、J1 天气块。本报告只报：分组专项（新）、前轮未修残余、批 E/I2 之后的新发现。

---

## 一、分组专项（用户实报：设置页有些功能项分组不对）

### 1.1 设计用意（Web 真源）

Web 设置页三组，`settings.rs` 组件注释明载：「外观（文字大小分段）/ 数据（备份与恢复；语言、诊断为按用户要求加入的同组入口）/ 关于卡」——语言、手势、诊断与备份同属「数据」组是明确设计用意，不是随手堆放。组头三处均内联 `padding-top:4px`（settings.rs 外观/数据/关于各节标题）。

原版归档出入：原版数据组只有「备份与恢复」一行（meta 为「Google Drive 云端同步」）；现行 Web 相对原版扩为四行（语言/诊断按用户要求同组加入、手势速览为批 12 新增），备份 meta 改为新鲜度呈现（谷歌入口已按用户 2026-11-22 拍板移除）。原生与现行 Web 的差异不在这条线上。

### 1.2 全项对照表（主设置页，每一项）

| # | 设置项 | Web 所属组（组内序） | 原生所属组（组内序） | 判定 |
|---|---|---|---|---|
| 1 | 文字大小 | 外观（1/1） | 外观（1/1） | 一致（行形态为 Dynamic Type 定案偏离，前轮 B1，不重报） |
| 2 | 和风天气 Key 自填 | 无此项（key 构建注入） | **天气（1/2）** | 原生多出（用户 H17 裁定：设置页支持自填） |
| 3 | 彩云天气 Key 自填 | 无此项 | **天气（2/2）** | 原生多出（同上） |
| 4 | 天气说明 + 保存钮 | 无此项 | **天气（组内尾行）** | 原生多出（同上） |
| 5 | 备份与恢复 | 数据（1/4） | 数据（1/4） | 一致 |
| 6 | 语言 | 数据（2/4） | 数据（2/4） | 一致 |
| 7 | 手势速览 | 数据（3/4） | 数据（3/4） | 一致 |
| 8 | 诊断日志 | 数据（4/4） | 数据（4/4） | 一致 |
| 9 | 版本 | 关于（1/2） | 关于（1/2） | 一致 |
| 10 | 联系我们 | 关于（2/2） | 关于（2/2） | 一致 |
| 11 | 页脚文案 | 关于组后 | 关于组后 | 一致 |

组序对照：Web = 外观 → 数据 → 关于；原生 = 外观 → **天气** → 数据 → 关于。

**结论：行级错组 0 项**——Web 既有 8 个功能项在原生的组别与组内次序全部正确。唯一的结构性差异是**天气组整组原生独有、且插位在外观与数据之间**（3 个项：第 2/3/4 项），打断了 Web「外观 → 数据」的相邻关系。这与用户实报的观感最吻合：天气 Key 本质是外部服务凭据配置，与数据组的备份/恢复同属「数据与服务」范畴，却独立成组并排在数据组之前，找备份时先撞见一组 Key 输入框，像分组错位。

### 1.3 目标分组方案

以 Web 分组为真源，天气组（用户裁定的功能本体保留，只动位置）：

- **方案 A（推荐）：天气组整体下移至数据组之后、关于组之前。** 恢复 Web 的「外观 → 数据 → 关于」主序与相邻关系；天气是低频配置（填一次 Key 长期不动），沉底合理；改动仅为组块挪位，组内形态（双 SecureField + 说明 + 保存）不动。
- 方案 B（不推荐）：天气并入数据组作第 5 个条目。数据组四行全是导航行（SetRow + chevron），天气是表单块（输入框 + 保存钮），并入后同一张卡内形态混杂，且卡高骤增，不成体例。
- 方案 C（不推荐）：维持现位。论证「外观与天气同属偏好配置」较弱——外观是显示偏好、天气 Key 是服务凭据，不同类；且用户已实报观感不对，不宜维持。

子页内分组顺带核完，无错组：备份页（hero → 导出/导入行卡 → iCloud 说明 → 最近操作）与 Web 同构；诊断页（设置卡 → 当天 → 历史）同构，原生独有的「导出全部日志」钮与「库状态」节为前轮 F10 已定案增强（位置在当天卡与历史节之间、库状态在历史之后，不构成错组）；手势页单卡五行为一组、语言页单组（五语行 + 原生三态「跟随系统」首行，用户裁定）均无分组问题。

附带（与分组同源的间距账，详见 §2.1）：原生各组组距一律 24px，Web 因卡型不同而不同（外观组 `.list-group` margin-bottom 24 + gap 12 + 组头 4 = 40；数据组 `.backup-card` margin-bottom 16 + gap 12 + 组头 4 = 32）——组距被原生压平且整体偏紧，与「分组感弱」互为表里，修分组时应一并按组距账落。

---

## 二、其余待修汇总

### 2.1 感知级

| # | 位置 | Web 真值 | 原生现行 | 差值/证据 |
|---|---|---|---|---|
| S1 | 设置页组间距（外观→次组、数据→关于） | 外观卡底→次组头文字 40（base.css:111 `.list-group` margin-bottom 24 + `.page-gap` 12 + 组头内联 4）；数据卡底→关于头文字 32（panels.css:62 `.backup-card` margin-bottom 16 + 12 + 4） | 两处均为 SectionHeader topPad 24（Swift:12266 天气、12317 数据、12346 关于，均未传 topPad） | 外观→次组 −16、数据→关于 −8；首组头 4 已对齐（批 E）不计。组距压平且偏紧 |
| S2 | 诊断页「当天日志」节前距 | 设置卡底→标题文字 32（`.backup-card` margin-bottom 16 + page-gap 12 + `.diag-today-head` padding-top 4，panels.css:277 区注释明载此账） | 4（SectionHeader topPad 4，Swift:3179；VStack spacing 0、卡无下边距） | −28：标题几乎贴卡。批 E 补 F5 时只对了标题自身的 4px、漏了卡 margin 与 page-gap 两段 |
| S3 | 备份页「最近操作」节标题 | `.backup-section-title`：13px/500、glass-label、uppercase、letter-spacing 0.5、padding 0 4、margin 8/8（panels.css:57） | 通用 SectionHeader：14 semibold、tracking 0.3、无 uppercase（批 E 仅改 tint 为 glassLabel，Swift:12535） | 字号 +1、字重 +100、字距 −0.2；节前距：Web = note 后 margin-top 8，原生 = topPad 24（+16）；节后距 Web 8 / 原生 6 |
| S4 | 备份页 toast 形态（前轮 C8 未修残余） | 全宽条：left/right 16、bottom safe+16、radius 28、padding 14/16、gap 10、图标 19px SVG、文案 14px/500（base.css:657 `.backup-toast`，220ms 上滑为定案保留动效） | 居中胶囊：radius 999、padding 10/16、文案 13px、左右 24、底 24（Swift:12500 区） | 形态/度量全异。另：成功图标色原生 = T.accent（蓝），Web = `--color-success` #34C759 绿（tokens.css:81）；原生图标为 SF 实心圆，原版系描边 SVG |
| S5 | 备份 hero 度量（前轮 C1 未修残余） | radius 30、padding 18、标题 18px/700（panels.css:29,46） | radius 28、padding 16、标题 17 bold（Swift:12393 区） | radius −2、padding −2、标题 −1 |
| S6 | 备份导出/导入行（前轮 C5 未修残余） | `.backup-row` padding 16/18、图标槽 28px（专用蓝色描边 SVG）、标题 16/650、描述 13px（panels.css:78,87,95） | 借 SetRow：padding 14/16、SF 图标 16pt@24 槽 accent 色、标题 16/600、描述 12px（Swift:12441 区） | 描述 −1、纵内距 −2、横内距 −2、图标槽 −4 |
| S7 | 日志视窗页终端卡底距 | 卡下缘距视口底 40+safe（`.page-content` 底 padding calc(40px + safe)，panels.css:155；卡在 `.diag-log-content` 内 flex 撑满） | 16（Swift:3449 区 `.padding(.bottom, 16)`，未叠安全区） | 卡高多出约 58pt（以 safe 34 计），卡底几乎贴屏底 |
| S8 | 组头 uppercase（限非中文语境） | `.section-header` 与 `.backup-section-title` 均 `text-transform: uppercase`（editor.css:139、panels.css:57） | SectionHeader 无 textCase 处理（Swift:12051） | 中文无感；i18n 后 en-US 等语境下 Web 组名全大写、原生原样，形态分叉。与 S3 的节标题同源，可一并落 |

### 2.2 微差组（逐项双侧数值，批量处理即可）

| # | 位置 | Web 真值 | 原生现行 | 差值 |
|---|---|---|---|---|
| M1 | 标题-副文案盒距（SetRow / 设置外观行 / 手势行） | `.item-left` gap 4（base.css:164）；`.set-row .item-meta` 再加 margin-top 2（panels.css:188）→ 设置行合计 6、手势行 `.gesture-desc` margin-top 2 + gap 4 = 6（panels.css:7） | VStack spacing 2（SetRow Swift:12085、设置外观行 12247、手势行 12771） | 设置/手势 −4、外观 −2（批 E 手势按 margin-top 2 落 spacing、漏了 item-left 的 gap 4） |
| M2 | 备份 hero 内部距 | 标题文字底→描述 19（`.backup-hero-title` margin-bottom 5 + `.backup-hero-top` margin-bottom 14，panels.css:38,46） | VStack spacing 8（Swift:12394） | −11；另描述行分隔点 Web 为独立 span opacity 0.3（settings.rs BackupView desc 段），原生为纯文本「 · 」无弱化 |
| M3 | 备份确认底表内部 | 标题→消息 12、消息→按钮 12（panels.css:213,214 margin-bottom）；按钮字 14px/650（panels.css:107 `.backup-btn`）；卡内底 padding 14+safe（panels.css:211） | 标题→消息 8（padding-top，Swift:12610 区）、消息→按钮 16；按钮字 15 semibold；卡内底 padding 14（卡外底距 safe+14 两端同） | 两段相消后总高近似；按钮字 +1；卡内底留白少 safe 一截（静态账，待真机量测） |
| M4 | 最近操作行内距 | padding 12/14（settings.rs 历史行内联 style） | padding 10/16（opRow，Swift:12680 区） | 纵 −2、横 +2（前轮 C10 报过、批 E 改内容未改内距的残余） |
| M5 | iCloud 说明行高与顶距 | 13px/1.55、margin-top 10（panels.css:51 `.backup-note`） | 13px 无 lineSpacing（默认行高约 1.2）、top 16（Swift:12466 区） | 顶距 +6（前轮 C11 残余）；多行时行间偏紧 |
| M6 | 终端卡行距（诊断当天卡 / 视窗页） | 11px mono 行高 1.55 → 行间增量 ≈6（panels.css:247 `.diag-body`） | 当天卡 lineSpacing 6 + VStack spacing 2 = 8（Swift:3233 区）；视窗页 lineSpacing 6 + spacing 3 = 9（Swift:3473 区） | 分别 +2/+3，且两处彼此不一致 |
| M7 | 联系行值字号 | 0.85rem ≈ 13.6（settings.rs 关于行内联） | 13（Swift:12370 区） | −0.6（前轮 B6 残余） |
| M8 | 分隔线色 | `--border-color` 浅 rgba(0,0,0,0.05)/深 rgba(255,255,255,0.10)（tokens.css:13,220） | glassBorder(0.16) × opacity 0.5 ≈ 0.08/0.08（rowDivider 等） | 浅 +0.03、深 −0.02（前轮 A8 残余） |

### 2.3 已对齐 / 定案核验（一笔带过）

- 设置页骨架：顶距 126、横 20、底 40 三页族统一 ✓；返回钮盒 46×46 ✓（字形与标题胶囊顶位为前轮 A4/A6 微差，未回潮、未修，仍按前轮结论挂账）。
- 数据组/关于组卡 radius 28、外观行卡 radius 32、天气卡 32（原生自选，与外观同为「表单型卡」，尚成规律，不作缺陷）。
- 诊断页：自动删除说明行（F1）、等级值 14（F3）、当天卡终端形态（F6）、归档胶囊流（F8）、两处空态（F7/F9）均已按 Web 落地；系统 Toggle（F2）与 segmented Picker（F4）为定案等价更优；导出全部与库状态节为定案增强（F10）。
- 语言页：独立卡 radius 32、间隔 6、状态纯文字、点行即切换（E1–E4 关单）；「跟随系统」首行为用户裁定的原生三态，非错组。
- 行标题字重 600 vs Web 650：SwiftUI 无 650 档、600 为最近档（前轮 A9 定案口径），全线同口径不重报。
- 备份确认底表定案形态（透明遮罩、250ms 弹簧仅淡入、按钮纵列序）已落地 ✓（内部度量细差见 M3）。

---

## 摘要

- **分组不一致：行级错组 0 项；整组性差异 1 组 3 项**——和风天气 Key、彩云天气 Key、天气说明+保存行同属原生独有的「天气」组（用户 H17 裁定的功能），插位在外观与数据之间，打断 Web「外观 → 数据」主序。目标方案：天气组整体下移至数据组之后、关于组之前（方案 A，推荐）。
- **其余待修感知级 8 项**：S1 设置页组间距压平偏紧（外观→次组 −16、数据→关于 −8）、S2 诊断页当天节标题贴卡（−28，批 E 漏账）、S3 备份「最近操作」节标题形态与间距、S4 备份 toast 仍为居中胶囊（前轮 C8 残余，含成功图标色蓝 vs 绿）、S5 备份 hero 度量（C1 残余）、S6 备份导出/导入行度量（C5 残余）、S7 视窗页终端卡底距 16 vs 40+safe、S8 组头 uppercase 缺失（限非中文语境）。
- 微差 8 项（M1–M8）已逐项给双侧数值，可随感知级批次一并处理。
