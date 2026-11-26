# 全面排查第二轮 · 图片页与残余面线（原生 iOS vs Rust Web）

2026-11-26 用户下达（全面排查第二轮）。方法：先读 Web 现行代码弄清意图与数值，再对照原生 `MomentApp.swift` 对应段逐项核。判定口径：已对齐 / 等价更优保留 / 待修（感知级或微差，双侧证据与行号）。前轮 `audit_detail_image_page.md` 已修项不重报，仅在回潮时单标——本轮图片页前轮修复项**无回潮**。审计基准：git HEAD 17d3c79 + 在途 I3 已落部分（Fmt locale 段已在树内）。

摘要先行：**待修感知级 1 项**（F7，且低频）；其余待修均为微差。开屏接线核对结论：**完整正确**（详见 §2）。

---

## 1. 图片页

Web 真值（复核）：`main.rs:2737-2793` ImagePage + `panels.css:169-171`——独立页、PageHead 复用、标题按 fileId 查 manifest 真名（无名兜底 `imgpage.untitled`=「图片」，`blocks.rs:512` att_name_in_manifest）、整图 contain 进可用区（大图只缩/小图不放大/居中）、IMGPAGE open（图就绪、带文件名与自然像素尺寸）/close（返回钮）打点；接入范围 = image 块、gallery Url 项、附件文件行图片类文件、图片附件整幅（`blocks.rs:444/739/949/1035` 四处 ImgView 设定点）。

| # | 项 | 结论 |
|---|----|------|
| 1.1 | 呈现口径：contain、小图不放大、居中 | 已对齐：`ZoomableImageView.Coordinator.fit`（MomentApp.swift:2065-2078）base = min(fitScale, 1)、contentInset 居中，与 Web max-width/max-height:100% 同义 |
| 1.2 | 缩放只在手动触发（双击/捏合、无自动缩放） | 已对齐：双击 fit↔2.5×（:2095-2115）、捏合由 UIScrollView 承担、无任何程序化自动放大 |
| 1.3 | GIF 逐帧播放 | 已对齐：`decodeImage`（:1923-1957）ImageIO 逐帧 + 帧时长（下限 0.02s）组 animatedImage，图片页与块内图共用 |
| 1.4 | 标题：清单真名优先 + 超 12 字截断单行 | 已对齐（用户 2026-11-26 定规）：displayName 清单优先（:12940-12947）、titleText 前 12 字+「…」（:12951-12955）、CompactTitle lineLimit(1)（:11941）；Diag 仍记全名 |
| 1.5 | 页头返回恢复编辑状态 | 已对齐：EditorView navigationDestination 推入（:6883-6892）、EditorModel 状态保持、onDisappear 落盘，与 Web go_back 同语义 |
| 1.6 | 可开范围 | 已对齐：原生五接入点——image 块（:6270）、gallery 项（:8400）、图片附件整幅（:9621）、附件文件行分发（:9638）、图文卡 openImagePage（:9838）；不接入项（封面/头像/video/MD 内嵌图）无误接 |
| 1.7 | 加载中/失败呈现 | 原生增强保留（前轮已定）：ProgressView + 「图片加载失败」文字，Web 为空白 + Diag 行 |
| 1.8 | **附件文件行图片判定** | **待修（微差）F1**：Web `att_file_is_image_raw`（blocks.rs:542-557）先查 manifest 的 MIME（image/* 优先）、再扩展名兜底，扩展集 10 种（含 **svg、avif**）；原生 `imageExts`（MomentApp.swift:9590-9591）只有 8 种（缺 svg/avif）且纯扩展名判定、无 MIME 优先。后果：.avif/.svg 附件、或扩展名与真实类型不符的图片文件，原生走分享而非图片页。注：原生 FFI 只暴露附件名（attachment_names_json）、不暴露 MIME，MIME 优先判定需扩 FFI 契约；扩展集补齐可独立先行 |
| 1.9 | **IMGPAGE open 的 nat= 口径** | **待修（微差）F2**：Web 记自然**像素**尺寸（naturalWidth/Height，main.rs:2757-2766）；原生记 `Int(img.size.width)`（MomentApp.swift:13009-13011）是**点（pt）**，3× 机上数值只有 Web 的 1/3，跨端对读 Diag 会误判图尺寸。修法：乘 image.scale 取像素 |
| 1.10 | **缩放上限口径** | **待修（微差）F3**：落码口径为「捏合至适配倍率 ×4」，实现 `maximumZoomScale = max(base * 4, 1)`（:2073）——超大图 base 很小（如 0.1）时上限被兜底抬到 1.0、实际可达适配的约 10×；常规图与小图（base=1 → 上限 4）无异。属手感口径偏差，标出供裁定（保留 1:1 上限亦可视作像素级查看的更优解） |

---

## 2. 开屏（静态帧 + 宿主时序 + Assets.car 接线）

**接线核对结论：完整正确。** 逐项证据：

- plist（build-app2.sh:63-67）：`UILaunchScreen = {UIColorName: LaunchBackground, UIImageRespectsSafeAreaInsets: false}`、**不写 UIImageName**（原壳口径）、`UIStatusBarStyle = UIStatusBarStyleLightContent`、`UIViewControllerBasedStatusBarAppearance = false`、`CFBundleIcons` 与 `CFBundleIcons~ipad` 均只留 `CFBundleIconName = AppIcon`——五项全对。
- colorset（icon-src/Assets.xcassets/LaunchBackground.colorset/Contents.json）：浅 = srgb 0x23/0x79/0xDC（#2379DC）、深 = 0x1F/0x1F/0x21（#1F1F21），与 Swift 宿主垫层色 splashColor（MomentApp.swift:13058-13065）逐值一致，静态帧与动效首帧同色、无色跳。
- 编译段（build-app2.sh:86-105）：moment.icon 复制改名 AppIcon.icon（包内一字不动）+ Assets.xcassets 一并交 accord 编译（iphone+ipad、min target 16.0），**只把 Assets.car 拷入 .app**，accord 顺手吐的散落 AppIcon*.png 不入包（脚本内无任何平铺 PNG 拷贝段残留）；构建目录走 $OUT 避 /tmp tmpfs。
- verify [8]（verify_ios.sh:174-215）：断言 car 真源在位、产物含 Assets.car、散落 AppIcon*.png 零残留、accord inspect 核 colorset rendition + 图标深/着色外观——断言面与接线面对应。
- 宿主时序（MomentApp.swift:13067-13145）：底色垫层 ignoresSafeArea + 画布 ignoresSafeArea(.container) 全屏（0.9.39 半透明条修法在位）；静止 500ms → progress 线性 1.0s → 再 1.0s 置完成位；退出 = didLoad && timelineComplete、easeOut 260ms 淡出；减弱动态时完成位立即置位、淡出 0；资源缺失时宿主不呈现（resourcesReady 门，:13047-13055）；SPLASH show/dismiss 打点齐。
- 已知在册（非本线新发现）：CFBundleDisplayName 仍硬编码「此刻」（build-app2.sh:52），五语显示名 InfoPlist.strings 属 I5 范围。

判定：开屏全项**已对齐**，无待修。

---

## 3. 分享面

Web 口径：附件文件行非图片路 = 渲染期预取 File、手势内 navigator.share({files})，canShare 不过降级下载，结果全程记 ATT（shared / cancelled / error \<name\> / download / missing，blocks.rs:579-656）；预取已定无文件时点击记 `open -> missing` 不静默。

| # | 项 | 结论 |
|---|----|------|
| 3.1 | 分享载体 | 等价更优保留：原生 ShareSheet = UIActivityViewController 系统分享面（MomentApp.swift:2300-2310），是 navigator.share 的平台对应物；附件先写临时文件（文件名清洗 `/`→`_`）再分享，五处调用点（备份导出/诊断导出/附件行/音频行等）同型 |
| 3.2 | **缺失附件与结果留痕** | **待修（微差）F4**：`share(fid:name:)`（:9669-9680）与同型 `shareAttachment`（:9470-）对空数据无失败分支——attachmentData 为空也照样写出空文件并弹分享面；`try?` 吞写失败后仍设 shareState.url 弹面。Web 同场景记 missing 且不分享。且原生分享路径**无任何结果打点**（Web ATT 结局行 shared/cancelled/error 全记），分享失败在 Diag 里无痕。修法：data 为空不弹面 + 记一条 ATT 同义打点（投 ErrBadge 与否另议） |

---

## 4. 错误徽章 ErrBadgeOverlay

Web 真值（errbadge.rs + base.css:687-701）：徽章 36×36、radius 18、right 16、bottom = 64 + safe、红（有非 WARN）/黄（纯 WARN）、「!」12/700 + 计数 10/600（>99 显 99+）、淡入 0.2s；条目内存上限 20、倒序、面板宽 320、头行标题 + 清除、条目含 kind 图标（monitor/clock/film/warning）、message（截 120）、loc、完整 locale 时间串、stack（WARN 4 行 / 全局 8 行，pre 呈现）；投递/打开/清除均记 ERRBADGE 行；挂 App 根。

| # | 项 | 结论 |
|---|----|------|
| 4.1 | 几何与色彩 | 已对齐：原生（MomentApp.swift:2455-2525）36×36 radius 18、trailing 16、bottom = safe + 64、红/黄优先序、「!」12 bold + 计数 10 semibold、99+、淡入 0.2s、面板宽 min(320, 屏宽−32)（窄屏比 Web 固定 320 更稳，等价更优）、条目倒序、上限 20（:2440-2443） |
| 4.2 | 挂载层级 | 已对齐：0.9.39 抽为 ErrBadgeOverlay 挂 @main 根 ZStack（:13156），首页/编辑/设置族全可见；系统 sheet 盖其上（与 Web 模态层级差已在 G8 注明可接受） |
| 4.3 | 打点 | 已对齐：add 记 `ERRBADGE add <kind> total=`、panel open、clear 均有行（:2446-2453） |
| 4.4 | **面板条目信息量** | **待修（微差）F5**：原生 Entry 只有 kind/message/time（:2409-2413），且 time 仅 HH:mm:ss（:2426-2430）；Web 条目另有 loc 与 stack 呈现、time 为完整 locale 时间串。原生面板看不到失败堆栈细节、须转 Diag 页——呈现面信息量低于 Web（投递侧 call site 多数也未带 detail，属同链） |
| 4.5 | **面板文案未接语言包** | **待修（微差）F6**：面板标题「运行异常/警告信息」与「清除」钮为硬编码字面量（:2549-2556），语言包已有现成键 errbadge.title_error / title_warn / clear（lang/zh-CN.json:288-290）。注：I3 在途范围含 ErrBadge，本项若 I3 未覆盖则由 I5 零残留门收 |
| 4.6 | kind 图标 | 等价保留：Web 按 kind 分四种 SVG 图标，原生 ERROR/WARN 二分 SF 图标（xmark.octagon / exclamationmark.triangle）；原生无 RENDER/PROMISE 来源（无全局错误钩），二分与来源面对应 |

---

## 5. 天气 / 音乐 / 链接卡只读呈现

说明：卡片在两端都只在编辑器内整卡渲染；列表侧只派生封面/文本行（音乐/链接卡封面不入列表封面派生，两端同规，属首页线已核范围，本线不重报）。

### 5.1 音乐 / 链接卡（CardBlockView，MomentApp.swift:9149-）

Web 真值（blocks.rs:1062-1345 + editor.css:434-472）：musicCard 状态机 = input 胶囊 → ready 卡 → loading 骨架（封面 2.4:1 + 三行 75/50/35% + 整体脉冲）→ error 卡（图标 20 + URL 锚 + 重试）→ 兜底胶囊（图标 + URL + error 时附「预览不可用」注记）→ 空态胶囊（点击粘贴提示）；link-card 无标题 = err 卡（标题 = 主机名、来源行 = 完整 URL）、有标题 = ready 卡（副标题只认 subtitle、哔哩哔哩不显副标题含 type=video 且 URL 含 bilibili/b23.tv 的判定、封面过图片白名单走代理、来源 source→siteName→host 兜底、图标按 type 分）。

| # | 项 | 结论 |
|---|----|------|
| 5.1.1 | ready 卡几何/排版 | 已对齐：封面 2.4:1 满幅 cover（:9229-9246）、正文 padding 10/14/12（有封面顶 6）、标题 14 semibold 行高 1.4 钳 2 行、副标题 12 行高 1.3 上距 3 钳 2 行、来源行 11 上距 4 gap 5 dot 3px/0.4——与 .lkc-* 逐值对上；radius 32 contentCard 同 .link-card-block |
| 5.1.2 | 副标题/来源/图标口径 | 已对齐：subtitle 只认 meta.subtitle 不读 description（:9271-9276）、source 兜底链 music 缺省「音乐」/link source→siteName→host（:9278-9287）、type 图标 music/video/link 三分与 Web type_icon 同（:9289-9296；SF 符号形态差属既有图标面）。微注：来源行图标字号 12 vs Web SVG 14px，≤2px 级不单列 |
| 5.1.3 | 封面处理 | 等价更优保留：原生直连 + mzstatic 尺寸段归一 600x600bb 取紧方图（:9177-9195，用户实证的 Apple 画布封面修法）；Web 走 proxy_img 是 Web 平台需要，原生无此约束。openCard 的 http(s) 前缀闸（:9474-9479）与 Web safe_http_url 白名单等价 |
| 5.1.4 | loading 骨架 | 已对齐：封面盒 + 三行 75/50/35%、整体脉冲 1.4s ease-in-out 往返（:9330-9377）、减弱动态不脉冲，与 Web 骨架同形同周期 |
| 5.1.5 | error 卡重试 | 已对齐：重试钮置 status=loading + startResolveCard 重解析（:9399-9412），与 Web CardRetry 同义 |
| 5.1.6 | **musicCard input / 空态无呈现** | **待修（感知级，低频）F7**：原生 body 分支（:9210-9230）无 input 分支、无空态兜底——status="input" 且无 URL、或无 URL/无标题/无状态的音乐块落到 EmptyView **整块隐形**；Web 分别有 input 胶囊（media.music_paste_hint「粘贴音乐链接到这里，回车解析...」）与空态胶囊（media.music_click_hint「点击粘贴音乐链接」）。原生自身流程不产 input 态（粘贴即解析），命中面主要是跨端 ZIP 导入的未完成态文档与解析中断遗留——一旦命中，用户看到的是块凭空消失 |
| 5.1.7 | **error 卡 URL 不可点开** | **待修（微差）F8**：Web error 卡的 URL 本身是锚（可点开，卡面其余部分 cursor default）；原生 errorCard（:9392-9418）URL 为纯 Text、整卡无点按手势，只有重试钮——解析失败时原生无法从卡上直接打开原链接核对 |
| 5.1.8 | **error 兜底胶囊文案** | **待修（微差）F9**：status=error 的兜底胶囊，Web 并列显 URL + 注记（media.preview_unavailable =「预览不可用 · 点击打开」）；原生 urlPill（:9426-9445）以「预览不可用」**替换** URL 文本（且为硬编码短版、键已存在未用）——链接本体不可见 |
| 5.1.9 | **哔哩哔哩副标题抑制分支缺一** | **待修（微差）F10**：Web 抑制条件 = 来源 == 哔哩哔哩 **或**（type=video 且 URL 含 bilibili/b23.tv）；原生 subtitleText（:9271-9276）只判 sourceText ==「哔哩哔哩」——来源为空、host 兜底为 b23.tv 的 B 站视频卡，原生会多显一行副标题 |

### 5.2 天气（首页新建卡内天气块）

Web 真值：NewCard 末尾天气块（list.rs:1510-1528），城市先过 to_cn 英转中表（weather.rs:401-）；窄屏右对齐列（base.css:188-190：gap 4、padding-left 12、温度 16/650/字距 −0.5、城况 12 次级）；宽屏方卡底部整行（温度左、城况右，C-A5 已对齐）。

| # | 项 | 结论 |
|---|----|------|
| 5.2.1 | 窄屏形态 | 已对齐：原生 newCardRow（MomentApp.swift:11708-11731）右对齐列 spacing 4（批 E 已由 2 改 4）、leading 12、温度 16 semibold tracking −0.5、城况 = [city, text] 空过滤空格拼，与 Web city_line 同义；有数才渲染、缺数整块不出现，两端同 |
| 5.2.2 | 城市中文来源 | 等价更优保留：Web 靠 to_cn 静态表转 IP 定位的英文城名；原生主链 CLGeocoder 以 zh_CN locale 直出中文城名（:10734-10745）+ 和风 geo 中文名，平台能力直达 |
| 5.2.3 | **IP 兜底城名未转中文** | **待修（微差）F11**：仅当 GPS 失败、geocoder 与和风 geo 都拿不到城名时，原生落 ipCity 原文（英文「City Region」，:10636-10650 组装、:10724 兜底）；Web 同路径会过 to_cn 表。触发条件苛刻（多级兜底全落空），命中时城况行显英文 |

---

## 6. Wiki / 反向链接

Web 真值：提取管线（wiki.rs）= 收集 text 叶（跳 code/codeblock/fencedcode/inlinecode 子树）→ 按 run 配对剔除反引号段 → 剔除转义 `\[[…]]` → 扫描 `[[…]]`（inner 不含单个 `]` 与换行、支持 `[[目标|标签]]` 拆 `|` 取目标、标签非空才成链）→ 键 = 剥 # 锚点/trim/小写。反链区（editor.rs:890-925 + editor.css:376-382）：非空才渲染、宽 min(100%,720)、上距 24 + 顶 padding 14 + 1px 顶分隔线、标题 12/650 次级、条目扁平行（「↗」前缀次级色、正文链接色、min-height 44、padding 6/8、radius 10、透明底）、空标题显 untitled、点按先落盘再跳、记 WIKI 行。

| # | 项 | 结论 |
|---|----|------|
| 6.1 | 键归一与目标解析 | 已对齐：原生 wikiKey（MomentApp.swift:1018-1025）剥 #/trim/小写、空与「无标题」无链，与 wiki_title_key 同；跳代码子树以类型小写后比对（现行文档代码块类型 codeBlock 归一后命中；Web 集合另含字面 `code` 类型，原生文档无此类型节点，形式分叉无实际命中） |
| 6.2 | MD 预览 wiki 点按跳篇 | 已对齐：core 解析拆 target/label（原生 MdSegs 的 Wiki 段，:8553-8565），点按经 wikiTap 通道跳篇、命中/未命中均记 WIKI 行（:8207-8222） |
| 6.3 | **反链提取边沿四分叉** | **待修（微差）F12**：原生 Library.wikiTargets（:1027-1085）与 Web 管线在边沿输入上分叉——(a) **管道式 `[[目标|标签]]` 不拆 `|`**：键成「目标\|标签」永不命中标题，反链漏检（MD 预览侧由 core 拆分、不受影响，仅反链提取中招）；(b) 转义 `\[[…]]` 未剔除，被计为链接；(c) 反引号以单字符奇偶切分：双反引号代码段内的 `[[…]]` 仍被计（Web 按 run 配对整段剔除），且落单反引号后全文被吞；(d) inner 含单个 `]` 或换行时原生仍成键（另有 inner 200 字上限），Web 判无效。四者均为低频边沿输入，但 (a) 是原版既有写法、跨端文档可达 |
| 6.4 | **反链区形态** | **待修（微差）F13**：原生 backlinksSection（:8146-8182）为 glassCard 卡片行（radius 14、link 图标 accent 色、标题 14 主色、区标题 13 semibold、无顶分隔线、区上距 8）；Web 为顶分隔线 + 扁平链接行（↗ 前缀、正文链接色、区上距 24/顶 padding 14、区标题 12/650）。行为面（非空才现、点按跳篇、WIKI 打点、标题改后重算 :7591）等价，差在呈现形态一档 |
| 6.5 | 跳篇前落盘 | 已对齐（机制不同）：Web 点按显式 persist 后跳；原生编辑器自动防抖保存 + onDisappear saveNow 承接，跳篇换 EditorModel 时旧篇已落盘 |

---

## 待修汇总

- **感知级 1 项**：F7 —— musicCard 的 input/空态在原生整块隐形（Web 有提示胶囊），跨端未完成态文档命中时块凭空消失。
- **微差 12 项**：F1 附件图片判定缺 svg/avif 与 MIME 优先；F2 IMGPAGE nat= 记 pt 非像素；F3 超大图缩放上限被兜底抬至 1:1、偏离 ×4 口径；F4 分享缺失附件弹空文件且无结果打点；F5 徽章面板缺 stack/loc、时间仅时分秒；F6 徽章面板文案未接语言键；F8 音乐 error 卡 URL 不可点开；F9 error 兜底胶囊以「预览不可用」替换 URL；F10 B 站副标题抑制缺 URL 分支；F11 天气 IP 兜底城名未转中文；F12 反链提取边沿四分叉（管道式漏检为首）；F13 反链区卡片形态 vs Web 扁平行。（F6/F9 含 i18n 残余成分，分别与 I3/I4 在途范围相邻。）
- **开屏接线**：完整正确，无待修。
- 前轮图片页已修项（标题真值序、availH、lineLimit、IMGPAGE 打点、缩放/GIF）本轮复核**无回潮**。
