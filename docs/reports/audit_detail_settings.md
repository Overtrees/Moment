# 数值级对齐排查 · 线 4：设置族 / 诊断 / 图片页 / 搜索 / 天气

只读审计（2026-11-26）。Web 真值 = `rust/apps/web/src/{settings.rs,diag.rs,main.rs,list.rs}` + `rust/apps/web/styles/{tokens,base,editor,panels}.css`；原生现行 = `rust/apps/ios/app/MomentApp.swift`（下称 Swift，行号为现行文件行号）。文案真值 = `rust/apps/web/lang/zh-CN.json`。

分类口径：**缺陷待修** / **系统等价更优**（含平台档位近似） / **已定案偏离**（注明出处） / **一致·注记**。

汇总：共 63 条对照——缺陷待修 44 条、系统等价更优 3 条、已定案偏离 4 条、一致或说明性注记 12 条。

先说定案核验结论：

- 开关尺寸：Diag 自动删除 Web 为自绘轨道 42×26，原生系统 Toggle 51×31——已定案等价更优，**一致**（F2）。
- 图片页 contain / 大图只缩 / 小图不放大 / 标题=真实文件名——原生**全部一致**（H2、H3）。
- 备份确认底表定案形态（250ms 弹簧、仅淡入无位移、透明遮罩、自绘卡）——**原生未落地**，现行走系统 `.alert`（C6，本线最重一条）。
- Diag 改版口径（胶囊卡、绿字黑底当天卡、等级 W/E）：W/E 行格式**一致**（F11）；胶囊与当天卡形态**多处走样**（F6、F8）。

---

## A. 子页骨架（设置/备份/手势/语言/诊断共用）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| A1 | 内容左右内边距 | 20px（panels.css:155 `.page-content`） | 16（Swift:10975 等各页 `.padding(.horizontal, 16)`） | −4 | 缺陷待修 |
| A2 | 内容底内边距 | `calc(40px + 安全区)`（panels.css:155） | 设置/备份/诊断 32、手势/语言无底距 | −8 起 | 缺陷待修 |
| A3 | 内容顶距 | 126px（panels.css:155） | 126（各页 `.padding(.top, 126)`） | 0 | 一致·注记（量测锚点 Web 为文档顶、原生为安全区顶，静态不可判，待真机量测） |
| A4 | 返回钮 | 盒 46×46、左 16、顶 safe+7（editor.css:209 `.editor-fab`）；内 SVG 22px、描边 2.5（icons.rs:205） | 盒 46×46 ✓（Swift:10658 ChromeView）；SF `chevron.left` 17pt semibold | 字形 −5 | 缺陷待修（微） |
| A5 | 紧凑标题胶囊度量 | 17px/600、padding 6/16、radius 20、letter-spacing −0.3、glass-overlay（base.css:85） | 17 semibold、6/16、radius 20、tracking −0.3（Swift:10645） | 0 | 一致 |
| A6 | 紧凑标题胶囊顶位 | 与返回钮同顶 safe+7（base.css:85、editor.css:226） | 顶距 11（钮为 7，Swift:10675） | +4 | 缺陷待修（微） |
| A7 | 分组头 | 14px/600/次级/letter-spacing 0.3/uppercase、padding 24/4/6（editor.css:139）；**设置页三处内联改顶距 4px**（settings.rs:277,306,356） | 14 semibold/次级/tracking 0.3、padding 24/4/6（Swift:10686）数值全同，但顶距恒 24 | 设置页首组 +20、后续组 −8（Web = 卡 margin-bottom 16 + page-gap 12 + 4） | 缺陷待修 |
| A8 | 行间分隔线 | 0.5px、`--border-color` 浅 rgba(0,0,0,0.05)/深 rgba(255,255,255,0.10)、左右缩进 16（panels.css:188） | 0.5、左右 16 ✓；色 = `T.glassBorder`(0.16) × opacity 0.5 ≈ 浅 0.08/深 0.08（Swift:10739、8751） | 浅 +0.03、深 −0.02 | 缺陷待修（微） |
| A9 | 行标题字重 | 650（base.css:165 `.item-title`） | `.semibold` = 600（Swift:10700 SetRow 等） | −50 | 系统等价更优（SwiftUI 无 650 档，600 为最近档位，全应用同口径） |

## B. 设置页（Web settings.rs:240 SettingsView / Swift:10745）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| B1 | 文字大小行 | 分段钮 小/中/大：高 32、min-width 40、padding 0 12、radius 16、字号 13/15/17、选中 accent（panels.css:173）；副文案「跟随浏览器缩放」(settings.font_note) | 无分段钮；副文案「在系统「显示与亮度 · 文字大小」中调整」+ 右值「跟随系统」13px（Swift:10830） | 形态与文案全异 | 已定案偏离（文字大小改判 Dynamic Type，用户裁定；Web 分级是接不到系统设置的替代口径） |
| B2 | 备份行副文案（未备份时） | 「尚未导出过备份」(settings.backup_never) | 「尚未备份」（Swift:10814） | 文案不符 | 缺陷待修 |
| B3 | 备份行警示着色 | 仅警示后缀段着 warning 色，前段保持次级（settings.rs:271-275） | 整行 meta 变 warning 色（SetRow `metaWarn`，Swift:10700） | 着色范围扩大 | 缺陷待修（微） |
| B4 | 警示文案续接 | 后缀以空格续接（settings.rs:273） | 以「 · 」续接（Swift:10820） | 分隔符异 | 缺陷待修（微） |
| B5 | 版本行值 | 14px/400/次级（panels.css:189 `.about-val`） | 未设字号 → 环境默认 17pt（Swift:10955） | +3 | 缺陷待修 |
| B6 | 联系行值 | 内联 0.85rem ≈ 13.6px（settings.rs:371） | 13px（Swift:10968） | −0.6 | 缺陷待修（微） |
| B7 | 页脚 | 12px italic/次级/居中/opacity 0.8、顶距 12（panels.css:190） | 同（Swift:10975） | 0（Web 另有底距 4，可忽略） | 一致 |
| B8 | 天气设置组（和风/彩云 Key 自填） | Web 无此组（key 构建注入） | 整组原生独有：卡 radius 32、标题 13 semibold、输入 14、说明 12 次级、保存钮 14 semibold accent（Swift:10845） | — | 已定案偏离（用户裁定：默认构建注入 + 设置页自填覆盖，只存本机） |

注：版本号 Web「2.2.7」/ 原生「0.9.31」为两端各自版本线，不计差。主题行两端皆无（均跟随系统色），一致。

## C. 备份页（Web settings.rs:471 BackupView / Swift:10989）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| C1 | Hero 卡 | radius 30、padding 18、标题 18px/700、下距 18（panels.css:29,46） | radius 28、padding 16、标题 17 bold（Swift:11040） | radius −2、padding −2、标题 −1 | 缺陷待修 |
| C2 | 描述类文字色（系统性） | `--glass-label-color` 浅 #48494F / 深 #D1D1D6：`.backup-desc`（panels.css:194）、`.backup-row-desc`、`.backup-section-title` 均直用；且 base.css:359 的级联覆盖使 `.item-meta` 实际亦渲染此色（覆盖 base.css:184 的 text-secondary 定义） | 一律 `T.textSecondary` 浅 #68686D / 深 #98989D（Swift:8739）；原生无 glass-label 令牌 | 浅色下整族偏浅约一档 | 缺陷待修（系统性：覆盖设置行 meta、备份 hero 描述/行描述/节标题、iCloud 说明、搜索触发文案 I2） |
| C3 | 超期横幅 | 独立横幅卡：radius 30、0.5px warning 边、padding 12/18、13px/1.5 warning 色、hero 后 margin-bottom 18（panels.css:16） | 并入 hero 卡内一行 13px warning 文本（Swift:11052） | 结构/边框/间距全缺 | 缺陷待修 |
| C4 | 「本地备份」节标题 | Web 备份页无此标题，hero 后直入行卡 | 原生多出 SectionHeader「本地备份」（Swift:11065）；文案亦不在 i18n | 多余元素 | 缺陷待修（微） |
| C5 | 导出/导入行 | padding 16/18、图标槽 28px（蓝色描边 SVG）、标题 16/650、描述 13px、右箭头 18px opacity 0.45（panels.css:78,87,95,100） | 借 SetRow：padding 14/16、SF 图标 16pt@24 槽、行内距 11、标题 16/600、描述 12px（Swift:11067） | 描述 −1、padding −2、图标槽 −4 | 缺陷待修 |
| C6 | 确认底表形态 | 自绘底表（已定案）：透明遮罩、左右 14、底距 safe+14、卡 max-width 600、radius 28、padding 14/14+safe、标题 18/700 居中、消息 13/1.45 次级居中、按钮纵列 gap 10、高 44、radius 999、primary rgba(0,122,255,0.86)、进场 250ms 弹簧仅淡入无位移（panels.css:213-222 + 定案） | 系统 `.alert`（Swift:11124,11140） | 定案形态未落地 | 缺陷待修（重） |
| C7 | 导出确认消息文案 | 「打包全部笔记、附件与头像为 zip，将通过系统分享面板保存或发送。」(backup.export_msg) | 「将当前全部备忘与附件导出为一个 ZIP 备份文件。」（Swift:11137） | 文案不符 | 缺陷待修 |
| C8 | Toast 形态 | 全宽条：left/right 16、bottom safe+16、radius 28、padding 14/16、gap 10、图标 19px、文案 14px/500、220ms 上滑进场（定案保留，base.css:657） | 居中胶囊：radius 999、padding 10/16、文案 13px、SF 图标、下距 24、左右 24（Swift:11097） | 形态/度量全异 | 缺陷待修 |
| C9 | Toast 文案 ×3 | 导出成功「文件已分享」(status.shared)；导出失败「导出失败：{e}」；导入提交失败「导入失败（现有数据未动）」(status.import_error) | 「备份已导出」；「导出失败，请重试」；「导入失败，请重试」（Swift:11129,11147） | 3 条不符 | 缺陷待修 |
| C10 | 最近操作行 | padding 12/14；点 8px（成功 `--color-success`）；标题 14/600 = 记录消息（文件已分享/备份已下载/从本地文件恢复/导出失败等）；类型徽章 9px/700 大写、padding 1/6、radius 999、玻璃边；副行 12px「{时间} · {文件名}」（settings.rs:609-637） | padding 10/16；标题为自造「导出成功/导入成功/导出失败/导入失败」14 semibold；徽章 11px 无边；detail 11px 独立行；时刻 11px 右置（Swift:11184 opRow） | 字号 −1~−2、布局与标题文案异 | 缺陷待修 |
| C11 | iCloud 说明 | 13px/1.55、padding 0 4、margin-top 10（panels.css:51） | 13px、padding 0 4 ✓、顶距 16（Swift:11084） | 顶距 +6（色差并入 C2） | 缺陷待修（微） |

注：toast 时长口径一致（success 3s / error 6s）；导入确认标题/消息/按钮文案与 Web 全同（backup.sheet_import_title、backup.import_msg、backup.confirm_import）；导出文件名 UTC 日期口径两端同。

## D. 手势速览页（Web settings.rs:398 GesturesView / Swift:11231）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| D1 | 行图标 | 25px SVG、正文色（currentColor）（panels.css:5、settings.rs:440） | SF 符号 19pt、accent 蓝、24 槽（Swift:11252） | −6 且变色 | 缺陷待修 |
| D2 | 名称/说明字号 | 14/600 行高 1.4；12px 次级 行高 1.55、上距 2（panels.css:6,7） | 15 semibold；13px（Swift:11258） | 各 +1 | 缺陷待修 |
| D3 | 桌面快捷键页脚 | 有一行「桌面快捷键：/ 搜索 · N 新建 · J/K 移行 · Esc 返回」(shortcuts.line) | 无 | — | 一致·注记（桌面键盘语境，iOS 不适用） |

行度量本身一致：padding 13/16、gap 12、卡 radius 28、行间分隔线，两端同。

## E. 语言页（Web main.rs:3006 LanguageView / Swift:11290）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| E1 | 行结构 | 每语言一张独立 `.list-item` 卡：radius 32、glass-content、卡间隔 6（base.css:150） | 单卡 radius 28 + 行间分隔线（Swift:11300） | 结构异 | 缺陷待修 |
| E2 | 状态呈现 | 纯文字 12px：当前 = accent/700、余次级（panels.css:191） | 胶囊徽章 11px semibold + 背景 + 当前行加勾选图标（Swift:11324） | 形态异 | 缺陷待修 |
| E3 | 状态文案 | 当前「使用中」；zh-CN「内置」；其余按缓存「下载/已下载/下载中…」 | 其余四语全标「内置」 | 4 条状态不符 | 缺陷待修 |
| E4 | 切换动作 | 点行即下载语言包并切换（main.rs:3040） | 行无点按动作（Swift:11288 注释自承待原生 i18n 落地） | 功能缺口 | 缺陷待修（已知未落地） |

行内度量一致：padding 14/16、标题 16、副文案（英文名）12px 次级，两端同。

## F. 诊断页（Web main.rs:2814 DiagView / Swift:2242）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| F1 | 自动删除说明 | 行下独立说明行：11px 次级、padding 0 16 12、行高 1.45（panels.css:261 `.diag-note`）；行内仅标题 | 说明作行内 meta 12px（Swift:2280） | 位置异、字号 +1 | 缺陷待修 |
| F2 | 自动删除开关 | 自绘轨道 42×26、knob 20、inset 3（editor.css:943） | 系统 Toggle 51×31（Swift:2292） | — | 已定案偏离→系统等价更优（用户裁定，含双栏开关同口径） |
| F3 | 等级行值字号 | 14px 次级、右内距 6（panels.css:267） | 13px（Swift:2317） | −1 | 缺陷待修（微） |
| F4 | 等级选项 | seg-btn 组：高 32、min-width 40、radius 16、选中 accent（panels.css:173,268） | 系统 segmented Picker（Swift:2333） | — | 系统等价更优（iOS 标准分段控件） |
| F5 | 「当天日志」节标题 | 有：section-header + 顶距改 4（panels.css:277、main.rs:2930） | 缺失，当天卡以顶距 24 直入（Swift:2350） | 元素缺失 | 缺陷待修 |
| F6 | 当天日志卡 | `.diag-body`：底 #111、字 #7CFC9A、radius 28、padding 12、11px mono 行高 1.55、max-height 52vh 全量可滚（panels.css:247） | 底纯黑 #000、字 Color.green、radius 20、padding 14、仅显末 8 行（Swift:2352） | 底色/字色/radius/行数全差 | 缺陷待修（重） |
| F7 | 当天卡空文 | 「暂无日志」居中（panels.css:288 + `.is-empty`） | 「（暂无日志）」左对齐、绿 0.7（Swift:2361） | 文案+对齐异 | 缺陷待修（微） |
| F8 | 历史归档胶囊 | 横向流式 wrap、gap 8；胶囊 padding 10/16、13px/400、glass-control 面、radius 999（panels.css:280,281） | 纵向逐行堆叠 VStack spacing 8；padding 8/14、13 medium、glassCard 内容档（Swift:2400） | 布局异 | 缺陷待修（重） |
| F9 | 历史空态 | 「暂无日志」12px 次级居中（panels.css:288） | 自造长句「暂无归档——跨天后前一天的日志会自动冻结成归档（上限 60 份）。」13px 左对齐（Swift:2393） | 文案不符 | 缺陷待修 |
| F10 | 导出全部日志卡 / 库状态节 | Web 诊断页无此二者（导出在视窗页） | 原生独有（Swift:2379,2421） | — | 已定案偏离（导出全部为批 C 定案增强；库状态为原生自加读数面，注明出处） |
| F11 | 日志行 W/E 格式 | `[HH:MM:SS W] TAG msg` / `[HH:MM:SS E] …`（diag.rs:655） | `[HH:MM:SS W] text` / `[HH:MM:SS E] …`（Swift:2028） | 括号标记口径同（原生无 TAG 段，管线差异） | 一致 |

## G. 日志视窗页（Web main.rs:2965 DiagLogPage / Swift:2538）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| G1 | 正文呈现 | 绿字黑底终端卡撑满页头下可用区：#7CFC9A on #111、radius 28、padding 12、11px mono/1.55（panels.css:247,290 `.diag-fill`） | 无终端卡：页面底色上正文色直排，error 行改红字（Swift:2552） | 形态全异 | 缺陷待修（重） |
| G2 | 导出钮 | 文字胶囊「导出」：高 46、padding 0 18、radius 999、14px/500、glass-control、right 16、top safe+7（panels.css:295） | 46×46 图标圆钮（SF 导出图标 16pt）（Swift:2590） | 形态异 | 缺陷待修 |
| G3 | 空态文案 | 「暂无日志」(diag.empty) | 「（无符合等级的日志）」（Swift:2558） | 文案不符 | 缺陷待修（微） |
| G4 | 标题与导出内容 | 标题「{stamp}.log」；导出全量未过滤行 | 同（Swift:2548,2608） | 0 | 一致 |

## H. 图片页（Web main.rs:2737 ImagePage / Swift:11358）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| H1 | 图区顶距 | 内容区 padding-top 126（图盒自 126 起，panels.css:155,170） | 全幅 GeometryReader + 顶距 66（Swift:11380） | 图盒高 +60、居中点上移 | 缺陷待修 |
| H2 | 尺寸口径 | contain、大图只缩、小图不放大、区内居中（panels.css:170 注，用户 2026-11-24 定案） | 同：自然尺寸分支 + scaledToFit（Swift:11383） | 0 | 一致（定案核验通过） |
| H3 | 标题 | 附件清单真实文件名、无名兜底「图片」(imgpage.untitled) | 同（Swift:11366） | 0 | 一致（定案核验通过） |
| H4 | 加载/失败态 | Web 无对应态 | 原生有 ProgressView +「图片加载失败」（无字号指定）（Swift:11397） | — | 一致·注记（原生补位态，不计差） |

## I. 搜索（Web main.rs:174 SearchCapsule / Swift:9969 searchCapsule）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| I1 | 触发胶囊 | 高 66、right 20、top 7、padding 0 18、radius 999、glass-control（base.css:286）；图标 20px | 高 66 ✓、padding 0 18 ✓、radius 999 ✓、glassControl ✓；图标 SF 17pt（Swift:10001） | 图标 −3 | 缺陷待修（微） |
| I2 | 触发文案色 | 「搜索」14px、`--glass-label-color`、letter-spacing −0.1（main.rs:218） | 14px `T.textSecondary`、无 tracking（Swift:10003） | 色差（根因同 C2） | 缺陷待修（微） |
| I3 | 展开面板材质档 | glass-**overlay**（base.css:276） | `.glassCard` 内容档（Swift:9992） | 材质档低一档 | 缺陷待修（微） |
| I4 | 输入框 | 宽 140、高 40、15px、占位「搜索笔记...」（main.rs:192） | 同（Swift:9975） | 0 | 一致 |
| I5 | 清除钮 | 无（Esc/失焦关闭） | 独有 xmark 钮：清空并关闭（Swift:9983） | — | 一致·注记（原生行为增强） |
| I6 | 零结果空态 | padding 56/24、钮 padding 9/22、上距 10（editor.css:132,138）；副文案「换个关键词试试，或清除搜索查看全部备忘」；加载失败副文案全句（empty.load_error_sub） | padding 纵 48、钮 8/16、顶距 6（Swift:10630）；副文案少「备忘」二字；加载失败副文案为缩略版 | 度量微差 + 文案 2 条不符 | 缺陷待修（微） |

搜索结果行即列表行本体，两端同构，无独立结果行度量。

## J. 天气块（Web list.rs:1510 NewCard + base.css:188 / Swift:10402 newCardRow）

| # | 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|---|
| J1 | 窄屏天气块度量 | 右对齐列、gap 4、padding-left 12；temp 16px/650、行高 1.1、letter-spacing −0.5；city 12px、行高 1.2（base.css:188-190） | 右对齐列 spacing 2、无左内距；temp 16 semibold(600)、无 letter-spacing/行高（Swift:10424） | gap −2、字重 −50、字距缺 | 缺陷待修（微） |
| J2 | 城市行格式与地名来源 | 「{城市} {状况}」空格拼接（list.rs:1515）；城市名走英转中表 `to_cn` | 拼接格式同（Swift:10431）；城市名走系统 CLGeocoder | 来源异 | 已定案偏离（用户裁定：地名用系统 CLGeocoder，原生更优，不移植英转中表） |
| J3 | 宽屏方卡天气 | 宽屏 last-child 规则排底部行、space-between（base.css:437 区） | 置方卡底部右下（Swift:10182） | 形态近似 | 一致·注记 |

---

## 文案不一致条目汇总（与 zh-CN.json 逐字比对）

| # | 位置 | Web i18n | 原生现行 | 出处 |
|---|---|---|---|---|
| V1 | 设置·备份行（未备份） | 尚未导出过备份 | 尚未备份 | B2 |
| V2 | 备份·导出确认消息 | 打包全部笔记、附件与头像为 zip，将通过系统分享面板保存或发送。 | 将当前全部备忘与附件导出为一个 ZIP 备份文件。 | C7 |
| V3 | 备份·toast 导出成功 | 文件已分享 | 备份已导出 | C9 |
| V4 | 备份·toast 导出失败 | 导出失败：{e} | 导出失败，请重试 | C9 |
| V5 | 备份·toast 导入失败 | 导入失败（现有数据未动） | 导入失败，请重试 | C9 |
| V6 | 备份·历史行标题 | 文件已分享 / 备份已下载 / 从本地文件恢复 / 导出失败 / 导入失败（记录消息） | 导出成功 / 导入成功 / 导出失败 / 导入失败（自造） | C10 |
| V7 | 备份·hero（从未备份） | 上次备份 暂无 | 上次备份 尚未备份 | C1 注（backup.never） |
| V8 | 备份·节标题 | （无） | 本地备份（多余且不在语言包） | C4 |
| V9 | 诊断·当天卡空文 | 暂无日志 | （暂无日志） | F7 |
| V10 | 诊断·历史空态 | 暂无日志 | 暂无归档——跨天后前一天的日志会自动冻结成归档（上限 60 份）。 | F9 |
| V11 | 视窗页·空态 | 暂无日志 | （无符合等级的日志） | G3 |
| V12 | 搜索·零结果副文案 | 换个关键词试试，或清除搜索查看全部备忘 | 换个关键词试试，或清除搜索查看全部 | I6 |
| V13 | 空态·加载失败副文案 | 本地数据读取出错。重新加载试试；若反复失败，可在设置页查看诊断日志 | 本地数据读取出错，重新加载试试 | I6 |
| V14 | 语言·状态（非当前四语） | 下载 / 已下载（按缓存） | 内置 | E3 |

文案一致（已逐字核对，不再列）：设置各行标题与副文案（文字大小行除外，B1 定案）、手势五组名称/说明、备份 hero 描述与计数句式、iCloud 说明、导入确认全套、诊断各行标题与等级名、图片页兜底标题、搜索占位符、天气城市行格式。
