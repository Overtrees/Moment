# 数值级对齐排查 · 图片页（灯箱页，原生 iOS vs Rust Web）

2026-11-26 用户下达（全面排查续线）。方法：读 Web 真值（`main.rs` ImagePage + PageHead、`panels.css` .img-page 三规则、`base.css` .page-title.compact、`blocks.rs` att_name_in_manifest）与原生 ImagePageView / ChromeView / 三处接入点逐项对照。口径同前：等价是底线、原生更优才用原生形态。

## Web 真值

- 独立页面与列表/编辑/设置同级；页头复用 PageHead：返回钮 `.editor-fab.left`（与编辑器返回钮同款同位、fixed 悬浮），标题 `.page-title.compact`（fixed 居中、17px/600、字距 −0.3、padding 6/16、radius 20、glass-overlay、nowrap、fit-content、无 max-width）。
- 标题 = 按 fileId 查附件清单（manifest）的真实文件名，为唯一真值；无名/无附件来源兜底 i18n `imgpage.untitled` =「图片」。URL 图 fileId 为空 → 一律兜底。
- 内容区 `.img-page-content`：flex 列根（100dvh）、内容 flex:1、左右 padding 0、图 `max-width/max-height: 100%`、width/height auto——整图 contain 进页头以下可用区，大图只缩、小图不放大、居中、不变形不裁切。
- 根背景 `var(--primary-bg)`，与其它页同源（本页在场时 App 底色派生为 None 回落根色）。
- 无缩放/平移/点按手势，纯展示页。
- Diag IMGPAGE：open 行在图就绪后记（`open name=<文件名> nat=<自然宽>x<自然高>`，失败 `nat=error`）；close 行在返回钮点击时记。出场态 closing 不重复记。
- 接入范围（2026-11-24 定案）：URL 形 image 块、gallery Url 项、附件文件行中图片类文件、图片附件（node.image）整幅；不接入：musicCard/link-card 封面、MD 预览内嵌图、video、列表封面、头像、非图片附件行。

## 对照结果

| # | 元素 | 结论 |
|---|------|------|
| 1 | 页头形态 | 已对齐：原生 ChromeView 悬浮返回钮（46 玻璃圆、chevron 17 semibold）+ CompactTitle 胶囊（17 semibold、tracking −0.3、padding 16/6、radius 20）与 PageHead/.page-title.compact 逐值等价（材质档 glassCard 与 Web glass-overlay 的分档差属浮层批既有面，非本页独有） |
| 2 | 标题长名 | 已对齐：Web nowrap 无 max-width、长名两边溢出；原生 CompactTitle 同无截断约束——同形态，不单独改 |
| 3 | 标题来源 | **待修（已修）**：原生 displayName 优先调用点传入 name、仅当其为「图片」时才查清单——与 Web「清单名为唯一真值」分叉（节点名过期/占位时显错名）。改：fileId 在时清单名优先、查不到回退传入名；无 fileId 用传入名（URL 图节点名多为兜底「图片」，偶有真名时显示真名属更优，保留） |
| 4 | 图尺寸口径 | 主体已对齐：小图不放大（非 resizable 原尺寸居中）、大图 scaledToFit contain。**待修（已修）**：小/大图判定用 GeometryReader 全屏高，未减悬浮页头让位 66——图高落在 (可用高, 全屏高] 区间时走小图分支、不缩放被 frame 裁切。改：判定与呈现同用 availH = 全屏高 − 66 |
| 5 | 图区范围 | 已对齐：全宽贴边（Web 左右 padding 0）、顶让位 66（页头钮底边 53 + 13 间隙，近似） |
| 6 | 背景 | 已对齐：ChromeView .background(T.bg) 根色同源 |
| 7 | 加载/失败态 | 原生增强保留：ProgressView + 「图片加载失败」文字（Web 为空白 + Diag error 行），属补反馈的增强 |
| 8 | Diag open 行 | **待修（已修）**：原生原在 onAppear 记自述行（图未就绪、无尺寸）。改 Web 口径：图就绪记 `IMGPAGE open name=… nat=WxH`、失败记 error 行 `nat=error`，各一次 |
| 9 | Diag close 行 | **待修（已修）**：原生缺失。改：返回钮记 `IMGPAGE close`；侧滑返回经 onDisappear 兜底记（去重标志，Web 只记钮路径、此为覆盖增强） |
| 10 | 接入范围 | 已对齐：image 块（fileId/URL，编辑态换图优先）、gallery 项（fileId/url）、附件文件行图片扩展名分发、图片附件整幅点按，四路全通；不接入项（封面/头像/video/MD 内嵌图）无误接 |
| 11 | 返回恢复编辑状态 | 已对齐：导航推入/dismiss，EditorModel 状态保持（Web go_back 同语义） |
| 12 | 宽屏 | 已对齐：全屏 contain，Web 同（100dvh flex） |
| 13 | 手势 | 已对齐：无缩放/平移，两端同为纯展示（系统相册式缩放 Web 无此口径，不自加） |

## 修复落点（0.9.34，随 MD 预览组同版）

MomentApp.swift ImagePageView：displayName 优先序、availH 判定、IMGPAGE open/close 打点（含 loggedOpen/loggedClose 去重状态）。

## 补遗漏（2026-11-26 晚，用户实报后复查）

首轮 13 项有三处遗漏，均已处理：

- **#2 标题折行（实报）**：首轮只对了「无截断约束」、漏了 Web 的 nowrap——原生 CompactTitle 的 Text 未设 lineLimit，长文件名在胶囊内折成多行异形。修：lineLimit(1)，长名单行横向溢出由 ZStack 居中承载（与 Web 同形态）。CompactTitle 为全应用共用（首页小标题/设置子页同受益、无副作用）。
- **缩放查看（实报，用户裁定破例）**：首轮按 2026-11-24 定案记「无手势、两端一致」未作缺口；用户实报长图 contain 后看不清、页面不能动。用户 2026-11-26 裁定加相册式缩放：图片页改 UIScrollView 承载（ZoomableImageView）——初始 contain（小图不放大）、捏合至 ×4、双击适配↔2.5 倍、平移、居中。定案口径自此更新为「图片页可缩放查看，编辑器内图仍纯展示」。
- **GIF 静止（复查发现）**：ImageLoader 两路 UIImage(data:) 只取首帧，Web <img> 会播。修：统一 decodeImage（ImageIO 逐帧 + 帧时长组 animatedImage），图片页与块内图一并生效（与 Web 一致）。

未处理登记：超大图全尺寸解码无降采样（内存/卡顿风险，独立优化项）；图片页侧滑返回与藏导航栏的共存未在真机核（待终判时一并看）。
