# 修复批 K · 音乐卡与图片线 F1–F11 落码报告

2026-11-27。范围 = audit2_image_misc.md 的 F 组 11 项（F1–F11；F12/F13 反链两项不在本批）。方法：每项先回 Web 规格源（blocks.rs / errbadge.rs / weather.rs / editor.css / base.css）核真值，再回原生当前源码（HEAD 1f93642，0.9.52 已出包）核现状——审计基于旧 HEAD（17d3c79），其中两项已被后续批次修掉，本批以源码实证为准当面更正销账。落码只动 `MomentApp.swift`（音乐卡/图片/分享/徽章/天气段）与 `verify_ios.sh`（新增 [22] 组）；未碰桥文件、设置区、救援文件、FFI；版本号未 bump（随 0.9.53 出）。

## 逐项账

### F1 附件文件行图片判定 —— 审计后已修，本批复核销账（不重复落码）

- 审计读数：原生 `imageExts` 仅 8 种（缺 svg/avif）、纯扩展名判定、无 MIME 优先；FFI 只出名不出 MIME，MIME 优先需扩契约。
- 源码实证（推翻审计的待修状态）：J1 批已扩 FFI 契约（`attachmentTypesJson`），原生现行实现 = `MemoItem.attIsImage(name:type:)`（MomentApp.swift:13081-）——清单 type 非空以其为准（trim+小写 image/ 前缀）、缺失才回落扩展名，扩展集 10 种与 Web `att_file_is_image_raw`（blocks.rs:542-557）逐值一致（png/jpg/jpeg/gif/webp/bmp/svg/avif/heic/heif）；附件文件行分发（:12420-）与封面派生（:13149、:13871）全走此单一口径，旧 `imageExts` 已退役（grep 零残留）。
- 本批动作：无代码改动；verify [22] K22-1 把该口径钉为防回潮断言。

### F2 IMGPAGE open 的 nat= 口径 —— 本批已修

- Web 规格：记自然**像素**尺寸（main.rs:2757-2766 naturalWidth/Height）。
- 改前：原生记 `Int(img.size.width)` —— UIImage.size 是点（pt），3× 机上只有 Web 的 1/3，跨端对读 Diag 误判图尺寸。
- 改后：`nat=\(Int(img.size.width * img.scale))x\(Int(img.size.height * img.scale))`（size×scale = 像素，UIImage 语义定义式，单帧/动图解码路径同立）。断言 K22-3。

### F3 超大图缩放上限 —— 改判保留（裁定项，非缺陷）

- 审计读数：落码口径「适配倍率 ×4」，实现 `maximumZoomScale = max(base * 4, 1)`；超大图 base<0.25 时保底 1.0 使实际可达约 10×，审计标「供裁定」。
- 裁定：**保留现式**。理由：① 保底只在 base<0.25（图在任一维度超视口 4 倍）时触发，常规图与小图（base≥0.25，含 base=1 时上限恰 4）与 ×4 口径逐值等价，行为底线不破；② 保底方向是能力增强——无保底时超大图（如全景/长截图）永远到不了 1:1 像素级查看，图片页作为查看器缺此能力是实亏；③ 与用户已裁定的缩放口径（默认呈现不变、缩放只在用户手动时触发）不冲突，保底不引入任何自动缩放。
- 落点：fit() 处补裁定注释钉住口径，断言 K22-2 锁原式防漂移。

### F4 缺失附件分享弹空文件 + 分享无结果打点 —— 本批已修（单一实现收敛）

- Web 规格：预取定无文件记 `ATT open {fid} -> missing`（warn）且不分享；分享结局全记 ATT（`open {fid} {name} {type} {size}B -> shared/cancelled/error <name>`，blocks.rs:579-656、751、778）。
- 改前：`AttachmentBlockView.share(fid:name:)` 与 `CardBlockView.shareAttachment(fid:name:)` 两处同型实现——`attachmentData` 为空（缺失附件回空 Data）也照样写出空文件弹分享面；`try?` 吞写失败后仍设 shareState.url 弹面；全程无任何 ATT 打点。
- 改后（根源收敛，不逐点打补丁）：两处私有实现**整段删除**，收敛为单一 `shareAttachmentFile(library:state:fid:name:)`——
  - 字节为空 → 记 `ATT open <fid> -> missing`（.warn）、不弹面；
  - 写盘改 do/catch，失败记 `ATT open <fid> <meta> -> error <error>`、不弹面；
  - meta 同 Web 式（name + 清单 type（有则）+ 字节数 B）；
  - 结局打点通道：`ShareSheet` 增可选 `onComplete`（内部接 `UIActivityViewController.completionWithItemsHandler`），`ShareState` 增 `shareCompletion` 透传；附件两处弹面记 shared/cancelled/error。导出面等其余 ShareSheet 调用点不传回调、行为零变化。
- 断言 K22-4（含旧两实现 grep 零残留）。

### F5 徽章面板条目信息量（loc/stack/完整时间） —— 本批已修

- Web 规格（errbadge.rs + base.css:699-702）：条目 = kind/message/**loc**/**stack**/time（`toLocaleString()` 完整 locale 串）；add_warn 的 stack = detail 前 4 行（无 detail 时合成栈）、全局 add_error 前 8 行；面板呈现 = 消息截 120 字、meta 行（loc 非空才显 + 时间）、stack 以 pre 块（9 号、次级色、行高 1.4）呈现。
- 改前：原生 Entry 只有 kind/message/time，time 仅 `HH:mm:ss`；投递 API 无 detail 参数，面板看不到任何底层错误。
- 改后：
  - Entry 增 `loc`、`detail` 两字段；`addError/addWarn` 增 `detail: String? = nil`（旧调用点源码兼容），入列时按 Web 行数收口（WARN 4 行 / ERROR 8 行）；
  - 时间改完整 locale 串：`Fmt.locale`（随 app 内语言）+ dateStyle/timeStyle .medium，与 toLocaleString 同义；旧 `clock`（HH:mm:ss）删除零残留；
  - 面板：消息截 120 字、新增 meta 行（loc 非空才显 + 时间）、detail 非空时以 9 号等宽次级色堆栈块呈现（Web --color-stack-text #666 无对应原生令牌，按样式红线复用 T.textSecondary，不新造裸值）；
  - 投递侧同链补齐：8 处手握 `error` 的 catch 点全部传 `detail: "\(error)"`（open_db、save_write、delete_failed、attach_failed、export_failed、import_failed ×2、search_failed）；其余 7 处为守卫失败（库未开/序列化 guard/PDF 布尔失败），无 error 对象、detail 恒空，与 Web「无 detail」路径同义。
  - loc 说明：原生无全局错误钩（无 RENDER/PROMISE 来源，审计 4.6 已定案），loc 恒空、字段与呈现条件按 Web 全式就位——通道完整，来源面决定其恒空，不伪造。
- 断言 K22-9。

### F6 徽章面板文案未接语言包 —— 审计后已修，本批复核销账

- 源码实证：面板标题已走 `Lang.t("errbadge.title_error"/"title_warn")`、清除钮走 `Lang.t("errbadge.clear")`（I3 批落，J2 又补 F28/F29/F30 面板形态）。本批无改动；断言 K22-10 钉住防回潮。

### F7 musicCard input / 空态无呈现（感知级） —— 本批已修

- Web 规格（blocks.rs:1091-1093、1192-1198 + editor.css:457、462）：状态机 input 支 = `.music-input-pill`（padding 12/18、radius 999、glass-control 底、14 号主色、纯文本 media.music_paste_hint、无图标）；末支空态 = `.music-pill`（图标 17 + media.music_click_hint、padding 12/16、glass-content 底、纯呈现 div 无点按）。
- 改前：原生 body 分支链无 input 支、无空态兜底，两类音乐块落 `EmptyView()` **整块隐形**（跨端 ZIP 导入的未完成态文档、解析中断遗留命中时块凭空消失）。
- 改后：按 Web 状态机同序落两支——input 支插在标题判定之前（status 单值，input 与 loading/error 不共存，位置与 Web 逐项等价）；末支 EmptyView 换 `emptyPill`（该支只达音乐卡：链接卡已被 errCard 截走、有 URL 已被 urlPill 截走，与 Web 末支同达面）。两胶囊半径走 `Radius.pill`、底面走既有 `glassControl`/`contentCard` 修饰器，无写死值。
- 断言 K22-5。

### F8 error 卡 URL 不可点开 —— 本批已修（附同卡 i18n 残余收口）

- Web 规格（blocks.rs:1151-1164 + editor.css:439）：error 卡 URL 本身是锚（过 safe_http_url 白名单才可点、不过降级纯文本 span），卡面其余部分 cursor default；重试钮文案 = media.retry 键。
- 改前：原生 URL 为纯 Text、整卡无点按手势；重试钮文案硬编码「重试」（键已存在未用，与 F9 同型残余、同卡一并收口）。
- 改后：URL Text 挂 `.onTapGesture { openCard() }`（openCard 内含 http(s) 前缀闸，与白名单降级等价——不过闸点按无动作；其余卡面不挂手势）；重试钮改 `Lang.t("media.retry")`。
- 断言 K22-6。

### F9 error 兜底胶囊文案 —— 本批已修

- Web 规格（blocks.rs:1176-1181）：兜底胶囊 = 图标 + **URL 常显**，status=error 时其后并列一枚注记 span（media.preview_unavailable 语言键，.lkc-source-text 次级小字面）。
- 改前：原生 urlPill 以硬编码「预览不可用」**替换** URL 文本——链接本体不可见，且键已存在未用。
- 改后：URL 常显；status==error 时并列注记 `Lang.t("media.preview_unavailable")`（11 号次级色，对 .lkc-source-text 面）。硬编码字面量零残留。
- 诚实注记：现行分支序下 error+URL 先被 errorCard 支截走，urlPill 的 error 子态在两端均不可达（Web 同支注记亦被其 error 支遮蔽）——本项修的是呈现规则本身与硬编码残余，使胶囊在任何达面下按 Web 式呈现，不夸大为现行可见变化。
- 断言 K22-7。

### F10 哔哩哔哩副标题抑制分支缺一 —— 本批已修

- Web 规格（blocks.rs:1315-1317）：`is_bilibili = shown_source == "哔哩哔哩" || (type == "video" && (url.contains("bilibili") || url.contains("b23.tv")))`，shown_source = source→siteName→host 兜底链。
- 改前：原生 subtitleText 只判 `sourceText == "哔哩哔哩"`——来源为空、host 兜底为 b23.tv 的 B 站视频卡多显一行副标题。
- 改后：抽 `isBilibili` 计算属性按 Web 全式（sourceText 与 shown_source 同链），subtitleText 改判 `isBilibili`；音乐卡豁免（`!isMusic`）与 Web 同（抑制只在 link-card 支）。
- 断言 K22-8。

### F11 天气 IP 兜底城名未转中文 —— 本批已修

- Web 规格（weather.rs:403-465、list.rs:1513）：城名渲染侧过 `to_cn` 表（原版 CN_CITY 逐值移植，60 条）——整串精确命中回中文、未命中回原文。
- 改前：原生主链靠 CLGeocoder zh_CN 直出中文（审计 5.2.2 已判等价更优），但 GPS 失败且 geocoder/和风 geo 全落空时，落 ipCity 原文（英文），无转表。
- 改后：`WeatherService.cityToCn(_:)` 逐值移植 60 条表（与 weather.rs 机械对账：两端抽表 diff **零差异**）；在 ipCity **生产点单点应用**（fetch() 组装处），和风/彩云两条消费链同享——应用点与 Web 渲染侧不同但作用面等价（ipCity 是唯一的英文城名来源，geocoder/和风名本就是中文、过表为 no-op）。与 Web 同口径的固有性质一并记账：复合串「City Region」整串查表未命中回原文，两端逐值一致；裸城名（region 为空）命中转中文，即本项修复的实际命中面。
- 断言 K22-11。

## 改判保留汇总

| 项 | 裁定 | 理由（要旨） |
|---|---|---|
| F3 | 改判保留现式 `max(base * 4, 1)` | 保底仅 base<0.25 触发、常规图与 ×4 逐值等价；方向是 1:1 像素级查看能力增强，无自动缩放副作用。裁定注释 + K22-2 断言钉住 |
| F1 | 销账（非改判） | J1 已扩 FFI 契约并落 attIsImage 单一口径，审计待修状态被当前源码推翻；本批复核 + 断言防回潮 |
| F6 | 销账（非改判） | I3 已接语言键，J2 已补面板形态；本批复核 + 断言防回潮 |

## 附注（本批未动、记录待主线）

- 音乐卡分支判定序与 Web 一处不同：Web 先判标题（ready）后判 loading/error，原生先 loading/error 后标题。status 为单值，两序仅在「有标题且 status=loading/error」的解析中间态分叉（现行写入路径下 error 态不带标题），不在 F1–F11 任一项内，本批未动、留档待裁。
- ErrBadge 的 PDF 导出投递点（MomentApp.swift:7687）消息仍为硬编码字面量「PDF 导出失败」——属 I4/I5 编辑器全域换键范围，不在本批。

## verify [22] 组断言清单与本机自跑结果

新增 [22] 组 11 项（K22-1…K22-11，与上文逐项对应）：F1 口径防回潮 / F3 裁定式 / F2 像素式 + 旧式零残留 / F4 单一实现 + ATT 行 + 旧实现零残留 / F7 input 分支与两胶囊 + CardBlockView 内 EmptyView 零残留 / F8 点按数 ≥4 + media.retry + 硬编码零残留 / F9 语言键 + 字面量零残留 / F10 isBilibili 全式 / F5 loc/detail 字段 + 完整时间 + 行数上限 + 面板堆栈块 / F6 语言键销账 / F11 cityToCn + 生产点应用 + 表条目抽核。

本机自跑：`bash verify_ios.sh` —— **[22] 组 11/11 全绿，源码级 [1]–[21] 组全绿**；仅 [5] 组产物新鲜度两项红（「ipa 陈旧（早于 MomentApp.swift）」「产物语言包缺失或与 Web 源不一致」）——本机不构建、ipa 为旧构建产物，属构建后即转绿的产物检查，非源码问题。

## 编译级自检说明

本机无 swiftc，Swift 编译级验证随主线 tree 冒烟（smoke_ios.sh 全量）执行；本批已做源码级自检：全量 diff 人工复审（括号/分支/引用逐段核）、to_cn 两端表机械 diff 零差异、退役项 grep 零残留（旧 share 两实现、ErrBadge clock、"预览不可用" 字面量、Text("重试")、CardBlockView 内 EmptyView)、既有断言兼容性预检（I3 的 CJK 字面量门、R21-5 的 contentCard 计数、J20-11 徽章面板形态均不受影响）。落码未提交，待主线合流出 0.9.53。
