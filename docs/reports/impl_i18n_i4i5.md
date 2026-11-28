# i18n I4/I5 落地报告（全面审计批 5）

日期：2026-11-28。出处：plan_native_i18n.md 的 I4/I5 定义；审计总册
批 5（audit_full_2026-11-27.md）= AUD-B-16/AUD-C-04（EditorView 无
LangStore 观察 + 斜杠 24 项换键 EDT-59）+ AUD-C-05（硬编码 Text 两
处 + CJK 门未全量转正）。键真源唯一 = Web 五包，本批未动 Web 消费面。

## 一、I4 落码

### 1. 斜杠菜单整组换键（SL-A / EDT-59）

Web render.rs 的 SLASH_CMDS 存键名、渲染时 t() 解析——原生照此同构
移植：SlashCmd 的 `title`/`sub` 存储字段改为 `titleLangKey`/
`subLangKey` 存键，新增计算属性 `title { Lang.t(titleLangKey) }`、
`sub { Lang.t(subLangKey) }` 即唯一解析面。全部消费方（rows() 过滤
haystack、前缀命中排序、slashPanelWidth 量测、slashRow 渲染、
hlParts 高亮切分）零改动、随语言即时重演算。24 项映射：

heading1/2/3→slash.heading1/2/3(+_sub)、paragraph→slash.paragraph、
quote→slash.quote、todo→slash.todo、divider→slash.divider、
bold→slash.bold、italic→slash.italic、highlight→slash.highlight、
codeBlock→slash.code_block、bulletList→slash.bullet_list、
numberList→slash.number_list、callout→slash.callout、link→slash.link、
code→slash.code（sub 用 slash.code_sub）、strikethrough→
slash.strikethrough、imgTextCard→slash.img_text_card、imageTextRow→
slash.image_text_row、musicCard→slash.music_card、image→slash.image、
gallery→slash.gallery（余皆 +_sub 同前缀）。kw/py 保持字面（过滤
数据面，Web 同口径）。

公式两项（mathBlock/mathInline）为原生独有、Web 无对应键，新增四键
（见第三节）。字段名避用 titleKey：PermKind.titleKey 为计算属性且
经深检 D4 按同名声明溯源认领，同名存储属性会遮蔽其声明体致
perm.item_* 全数误判僵尸（本批实测踩中、改名后复绿）——深检的同名
声明首命中语义下，跨类型同名键属性须避名。

斜杠空态一并换键：未找到匹配命令→slash.no_match、试试拼音首字母：→
slash.empty_hint_lead、「标题 ·/图片 ·/音乐」→slash.empty_hint_1/2/3
拼「 ·」后缀，zh-CN 呈现逐字不变。最近丸→slash.recent_pill；链接
表单四点（slash.link_form_title / link_invalid / link_insert /
action.cancel）换键。

### 2. EditorView 补 LangStore 观察（AUD-C-04）

EditorView 头部新增 `@EnvironmentObject private var langStore:
LangStore` 一行；斜杠面板与编辑器整树随语言变更重演算，与其余页面
同口径。verify [9] 新增头部 60 行内断言锁此声明。

### 3. 残余硬编码扫尾（AUD-C-05 及全量扫描）

全 App CJK 字面量全量扫描（逐个字面量归类、多行串整块计）逐个
定性：用户可见 UI 壳全部换键（约 50 个调用点、45 个 hunk），余按
立项 §3 口径归类豁免（见第五节）。换键明细（复用既有键）：

- calloutTitle 五变体→callout.tip/warning/important/caution/note
- 标题回退四处（cleanTitle/commitTitle/胶囊预览/反向链接行）+
  TitleTextField 占位→editor.untitled
- 胶囊 meta 整串→editor.meta_line（Lang.tf {ago}/{n} 复合键，
  替原字符串拼装）
- 音乐卡改链 alert→sheet.edit_link（新键）+ action.cancel /
  action.save（新键）
- 头像对话框→editor.avatar_title/avatar_change/avatar_reset
  （三新键）+ action.cancel；附件来源→menu.attach（题）+
  attach.pick_media/pick_file（两新键）
- 卡菜单→cardmenu.edit / editor.delete_block；块转换菜单→
  menu.paragraph（新键）/ slash.heading1/2/3 / slash.todo /
  slash.quote / callout.tip / menu.delete_block（新键）
- ••• 菜单十项→menu.undo/undo_sub/redo/redo_sub/attach/attach_sub/
  export/bg/bg_sub/twopane/twopane_sub（包值与原字面逐字一致）
- 背景底表→bg.title/sub/remove/note；导出面板→export.title /
  md_detail/html_detail/pdf_detail + export.pdf_file_note（新键，
  iOS 口径文案、Web 的浏览器措辞键不可复用）
- 反向链接头→editor.backlinks；Done 胶囊 a11y→editor.done_aria
  （新键）；PDF 导出失败徽章→errbadge.pdf_failed（新键，此前为
  ErrBadge 唯一字面量 addError）
- 媒体面：media.add_image（两处）/ image_unavailable（新键）/
  gallery_add/gallery_add_hint/gallery_multi / music_paste_hint /
  music（两处回退与 hint）/ audio（新键）/ att_none（新键）/
  list.open（附件行 hint）
- 图文卡编辑 sheet→sheet.imgtext_title（新键）/ action.cancel /
  action.save / sheet.view_full（新键）

## 二、可见文案 delta 登记（一处）

strikethrough_sub：五包该键为裸形「~~删除线~~」（与 bold/italic/
highlight 的包裹形并存、包内自洽），原生旧字面为「包裹选中文字为
~~删除线~~」。按真源唯一口径换键对齐包值后，zh-CN 斜杠删除线项
副标题变为「~~删除线~~」，与 Web 现行呈现一致。除此一处外，本批
全部换键在 zh-CN 下呈现逐字不变（新键 zh-CN 值即原字面）。

## 三、键增删清单（五包同步，441 → 463，净 +22 / 删 0 / 改值 0）

| 键 | zh-CN | 备注 |
|---|---|---|
| slash.math_block | 公式块 | 原生独有项新增 |
| slash.math_block_sub | 插入 $$ 公式块 | 同上 |
| slash.math_inline | 行内公式 | 同上 |
| slash.math_inline_sub | 包裹选中文字为 $公式$ | 同上 |
| action.save | 保存 | 包内此前无此键 |
| sheet.edit_link | 编辑链接 | 音乐卡改链 alert 题 |
| sheet.imgtext_title | 图文文本 | 图文卡编辑 sheet 题 |
| sheet.view_full | 点击查看完整文本 | 空态提示 |
| editor.avatar_title | 头像 | 对话框题 |
| editor.avatar_change | 更换头像 | |
| editor.avatar_reset | 恢复默认头像 | |
| editor.done_aria | 完成 | Done 胶囊 a11y |
| editor.meta_line | {ago} · 共 {n} 字 | 胶囊 meta 复合串 |
| attach.pick_media | 图片/视频 | 附件来源 |
| attach.pick_file | 文件 | 附件来源 |
| menu.paragraph | 正文 | 块转换菜单 |
| menu.delete_block | 删除块 | 与 editor.delete_block（删除此块）有别 |
| export.pdf_file_note | PDF 将生成文件，可通过分享存储或打印。 | iOS 口径尾注 |
| media.audio | 音频 | 附件名回退 |
| media.att_none | 附件（无文件） | 空附件块 |
| media.image_unavailable | 图片不可用 | 图片块失败态 |
| errbadge.pdf_failed | PDF 导出失败 | 徽章（export.pdf_failed 含重试语、不合） |

五语译文均齐备（繁简转换、日/韩/英逐键译）；占位符集合五包齐平
（深检 7a）。僵尸认领：math 四键为原生独有、仅经深检新 D7 规则
认领（见第四节）；余新键均有字面 Lang.t/tf 引用。

## 四、深检演进（scripts/i18n_deep_check.py）

- **新增 D7 数据表 \*Key 字段认领**：字面量恰为包内键、且作标签以
  Key 结尾的实参值出现（titleLangKey:/subLangKey:）时认领，逐条
  打 log 供复核——按脚本头注既定演进规矩（D4 先例）扩展，与 Web
  存键同构的数据表形态自此有正式认领面。verify_rustweb.sh 第 7 节
  口径注释同步（双处同文规矩）。
- **7c 登记感知**：深检 7c 读 scripts/i18n_7c_exemptions.txt，已登记
  同值对只计豁免数、不再逐条列示；未登记者照常警告。深检保持警告
  级、退出码不变；恒等棘轮在 verify [9]（下节）。

## 五、I5 对账与豁免

### 覆盖率前后

- 键数 441 → 463（五包键集恒等）；原生字面引用 237 → 304 键、动态
  认领 63 → 111 键（含 D7 的 48）；僵尸 0；占位符不一致 0。
- CJK 字面量：全 App 逐个归类、未归类 0（明细见下表；桥自检文件
  的计数随并行线在途增补浮动，门以未归类判红、不锁计数）；
  审计分母（斜杠 24 项 + 约 35 处）全数销账，另多扫出并处理
  errbadge.pdf_failed、图文卡 sheet、附件来源等审计后新增面。

### 7c 豁免（77 对，真漏译 0）

与 zh-CN 同值且含汉字：zh-TW 60 对、ja-JP 17 对，逐键定性全为同形
——zh-TW 类 = 繁简同形（该串全部字符繁简同形、台式用法成立，如
取消/背景色/未找到匹配命令）；ja-JP 类 = 日汉同形词（如 背景色/
警告/使用中/保存）。启发式曾标记 操/收/找/入 四字为简体字，经核
四字繁简同形、系误报。本批新键新增 4 对（zh-TW：editor.done_aria/
editor.meta_line/menu.paragraph；ja-JP：action.save），同理解登记。
全表在 scripts/i18n_7c_exemptions.txt；verify [9] 棘轮断言实算集
== 登记集，新增同值未登记或登记失效皆红。

### CJK 全量门归类（verify [9] 新增，全 App *.swift）

| 归类 | 数 | 口径 |
|---|---|---|
| DiagLog 调用域（含 logOnce） | 70 | Diag 载荷不本地化（立项 §3） |
| 天气对照表 cityToCn/caiyunCondition | 80 | Web 同表数据面（地名/天气文本查表） |
| 桥自检四文件（UITest/Scenarios/Launch/Ops） | 浮动 | 夹具/证据/标识面，非终端 UI（计数随并行线在途增补） |
| SlashCmds kw 过滤字段 | 24 | 过滤数据（Web 同口径） |
| 导出物生成 mdBlock/htmlBlock | 10 | 导出文件内容（数据面） |
| timing 读数 | 7 | 仅 Diag 页库状态呈现（既有口径） |
| 内容模板（applyInlineSlash/applyLink/图文卡占位） | 6 | 落文档数据、Web 同字面（ops.rs/editor.js 实证） |
| Diag 导出组装（envHeaderText/buildExportFile） | 3 | 证据文件文本 |
| 语言本名 | 3 | 语言自称恒原文 |
| failNote 注记 | 2 | ImageLoader 失败 Diag 注记 |
| 种子内容（seedMemos 声明域） | 2 | 示例备忘整块多行串（用户内容同类） |
| wikiKey 哨兵比较 | 1 | 用户内容语义比较字面 |
| 平台名匹配（哔哩哔哩） | 1 | 逻辑匹配（Web is_bilibili 同口径） |
| 导出文件名 | 1 | 此刻备份_*.zip 数据面 |
| 救援锚步读数 | 1 | 救援页证据读数（MomentRescue） |
| W2 此刻启动图标 | 1 | 见留账 |

门实现注记：字面量提取支持 Swift 多行串（"""）整块消费——种子
JSON 此前会被逐字扫描错位吞掉而不可见，本批补齐后正式归类；
锚点失效（函数改名等）时对应字面量转为未归类判红，fail-closed。

### 留账（一项）

W2「此刻启动图标」（开屏图 accessibilityLabel）：位于开屏宿主区，
与状态栏/开屏线在途 hunk 同域，按并行纪律本批不硬改；已在 [9] 全
量门登记为 W2 单条白名单（注明随开屏线组版换键后销账）。该线组版
时换键并删 W2 即全门无白名单。

## 六、verify [9] 同步

- 键数期望 441 → 463（注释链续写本批 +22 明细）。
- 新增断言五条：7c 棘轮（实算集 == 登记集）、I4 斜杠存键锁
  （24 组 titleLangKey/subLangKey + 解析面）、AUD-C-04 EditorView
  观察锁（头部 60 行内）、I4/I5 扫尾零残留（12 锚）、I5 全量 CJK
  门（上表规则、未归类判红）。

## 七、本机自检

- i18n_deep_check：退出码 0（7a 齐平 / 7b 僵尸零 / 7c 全登记）。
- verify_ios.sh [9] 组：全绿，唯一红为「产物语言包 md5 不一致」
  ——本机 .app 产物陈旧的既有基线（组版重建后自清）。
- 全量 verify 本机跑至 [10] 后段被环境 SIGTERM 截断；截断前他组
  红项（J20-13 斜杠 maxH、T24-5、B16-15、B25-10、F30-2）均为并行
  在途线的 WT 状态（J20-13 所查 slashLayer 几何式已被在途线重构、
  两式皆无），与本批 hunk 无交集；全量绿待 0.9.64 组版在 tree 复跑。
