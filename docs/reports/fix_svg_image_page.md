# SVG 附件图片页解码死路（P2-7）— 定性与根治设计（停门稿）

> 状态：**已落码**（2026-11-27，主线放行、基线 HEAD cb8ff18；落码记录见 §8）。未提交、未 bump，随放行批次组版。
> 出处：docs/reports/audit_home_other_deep.md §3.1（P2-7，proven）与 §7 图片小批、§8 矩阵增补第 6 项（IMG-01 子行）。

## 1. 定性复核（源码逐点对账，与审计一致）

- **判图单点**：`MemoItem.attIsImage`（MomentApp.swift:15145）——清单 MIME 优先（`image/*` 放行）、缺失才回落名扩展集；扩展集（`attNameIsImage`，15161）含 `svg`，与 Web `att_file_is_image_raw`（blocks.rs）逐值同。**判图本身无错，不动。**
- **送达面全集**：`editor.imageTarget` 五处赋值（图块 8874、gallery 项 12417、图片附件整幅 14311、附件文件行经 attIsImage 分发 14328、图文卡图区 14566）+ 附件文件行非图走 `shareAttachmentFile`（14338）。SVG 经 MIME 路（type=`image/svg+xml`）与名路（`.svg`）都会被判图送进图片页。
- **死路点不在图片页、在解码层**：全 App 渲染面共用一条解码漏斗——`ImageLoader.load`（fileId 字节 / URL 数据两路）→ `decodeImage`（3170，CGImageSource 逐帧 + `UIImage(data:)` 兜底）。iOS ImageIO/`UIImage(data:)` 对任意 Data 的 SVG 无光栅解码 → 恒返回 nil。后果不止图片页：
  - 图片页：`loader.failed` → 恒显「图片加载失败」（19838 起 ImagePageView 三态），且本可用的分享路被截断（文件行已分发进页、不再走 share）。
  - **编辑器内联呈现同样死**：`ItemImageView`（3375）/`ImageBlockView`/gallery 瓦/附件整幅图/首页封面派生全部经同一 `ImageLoader` → SVG 在备忘正文里就是失败占位（photo.badge.exclamationmark）。审计只记了图片页，本稿把故障域补全到解码层——这决定了根治落点（见 §2）。

## 2. 二选一裁定：走 WKWebView 光栅化（根治），分流回分享路否决

### 方案 A（采纳）：解码漏斗内增 SVG 光栅化路

在 `ImageLoader` 的数据汇合点按**内容嗅探**分流 SVG → 离屏 WKWebView 渲染快照成 UIImage → 回注既有呈现管线（ItemImageView / ZoomableImageView / 封面）。判据：

1. **落点即根**：死路在解码层，分流点设在解码漏斗，一处修复全表面（图片页 + 内联 + 封面），不是在五个入口逐个打补丁。
2. **行为等价**：Web `<img>` 直渲 SVG 是真实能力而非平台妥协；且 SVG-as-image 的浏览器语义恰为「禁脚本、禁外部资源、独立文档」——WKWebView 以 JS 关闭 + `baseURL: nil` 的 `loadHTMLString` 加载，正是这套语义的原生等价实现，不是近似模拟。
3. **仓内有现成 proven 形态可复用**：`MathImageStore`（13358 起，隐藏 WKWebView 排版 + 快照 + 串行队列 + 离屏挂载关键窗口 + 明暗 overrideUserInterfaceStyle）与 HTML→PDF 的离屏 WKWebView（8403 起）已在产线运行，形态照搬、不新造轮子。

### 方案 B（否决）：把 svg 从原生可开集分流回分享路

- 须新造「可开图片页」谓词与 attIsImage 分家、逐个改五处赋值点——attIsImage 本身还必须保留（Web 对账的判图/封面派生口径），等于在消费方叠一层分流补丁；
- **治不了内联死路**：正文里的 SVG 图块/gallery/封面仍走同一解码漏斗恒失败，分流只救了图片页一个面；
- 行为降级：Web 能看的图在原生只能弹分享面，与「行为等价为底线」相悖。
否决理由与 AGENTS.md 红线③（不在消费方打补丁、从根治理）逐项对应。

### 附带考察：QLThumbnailGenerator（不采纳）

QuickLook 缩略图在部分系统版本可出 SVG 缩略图，但其为文件 URL 型、缩略图导向（尺寸/底色语义不可控、无自然尺寸口径），不适合作解码管线公民；WKWebView 路可控性与仓内实证均占优，仅此登记。

## 3. 落码设计（放行后照此施工）

**新文件 `MomentSvgRaster.swift`**（按红线④独立成文，进 build-app2.sh 构建名单多遍 + primary 遍 + 链接行），含两件：

1. **内容嗅探 `isSvgData(_:)`**：loader 只持有字节（URL 项可无 `.svg` 后缀、MIME 未接入 loader），故按内容判：跳过 BOM/前导空白 → 可选 `<?xml …?>` 序言、注释、`<!DOCTYPE …>` → 首个元素须为 `<svg`。二进制格式（GIF/PNG/JPEG…）天然不命中，嗅探置于 `decodeImage` 调用之前且仅命中时改道，GIF 逐帧路零影响。
2. **光栅化器 `SvgRasterizer`**（照 MathImageStore 形态）：单例 + 串行队列 + 单离屏 WKWebView（挂关键窗口、移出可视区）；
   - 配置：`allowsContentJavaScript = false`；`loadHTMLString(html, baseURL: nil)`——外部引用（http/file/相对路径）一律不可达，与 SVG-as-image 规范一致；包装 HTML 仅 `margin:0` + 透明底 + 内联 `<svg>` 本体；
   - 自然尺寸解析：扫根 `<svg>` 标签的 `width`/`height` 数值属性，缺失则取 `viewBox` 宽高，再缺失回落浏览器 SVG-as-image 默认 300×150 画布口径（报告登记、Diag 可见）；
   - 光栅倍率：位图按自然尺寸 × rasterScale 渲染，rasterScale 取使长边 ≤ 4096px、总像素 ≤ 16M 的上限内尽量 4（对齐图片页最大缩放 base×4 的清晰度需求）；`UIImage.scale` 回填使 `image.size`（点）= 自然尺寸——ZoomableImageView 的 fit 规则（base=min(fit,1)、小图不放大）与 IMGPAGE `nat=` 打点（点×scale=像素）口径自动守恒，**用户 2026-11-26 图片页裁定（整图适配/小图不放大/居中/缩放与 GIF 规格）零改动**；
   - 明暗：`overrideUserInterfaceStyle` 随当前 trait（容纳 `prefers-color-scheme` 型 SVG，与 MathImageStore 同口径）；
   - 完成：导航结束 + 渲染落定后 `takeSnapshot` 出图，经回调回主线程发布；失败（畸形 SVG/WebView 失败）→ 回调 nil。

**`ImageLoader` 改点（唯一改点）**：fileId 与 URL 两路现各自调 `decodeImage`，收口为一个 `publish(data:source:)` 私有汇合点：嗅探命中 → 走 SvgRasterizer 异步路；未命中 → 现行同步 `decodeImage`。`image`/`failed` 发布与 Diag 失败行沿用既有形态，失败行加格式标记（`fmt=svg`）以便与光栅图失败分开判读。`started` 一次性守卫不变。

**明确不动**：`attIsImage`/扩展集（判图对账面）、五处 imageTarget 赋值、ImagePageView 三态与可用区公式、ZoomableImageView、decodeImage 本体、分享路。

## 4. 已知边界（如实登记）

- **动 SVG**（SMIL/CSS 动画）：快照取渲染落定帧、静态呈现；Web `<img>` 可播 SMIL，属 parity 观察项（低频，与审计 §3.2 的 APNG 观察同级登记，不在本批扩面）。
- **`.svgz`**（gzip 压缩 SVG）：原始字节为 gzip、嗅探不命中 → 仍走 decodeImage 恒失败（与现状同），不在本批范围。
- **无自然尺寸且无 viewBox 的 SVG**：按 300×150 默认画布光栅化，呈现比例可能与 Web 略异（Web 同样以默认对象尺寸处理），登记观察。

## 5. 断言设计（verify_ios.sh 新组，放行时按当时组号顺延，暂记 SVG 组）

1. SVG-1：`isSvgData` 在位且 `ImageLoader` 两路（fileId/URL）共用同一汇合点调用它（计数锁：嗅探调用点 = 1 处汇合点，非两路各一份）。
2. SVG-2：光栅化器沙箱语义锁——`allowsContentJavaScript = false` 与 `baseURL: nil` 字面在位。
3. SVG-3：判图守恒锁——扩展集仍含 `svg`（attIsImage 未被分流改动）；`imageTarget` 赋值点计数恒 = 5（防入口分流补丁混入）。
4. SVG-4：`MomentSvgRaster.swift` 在 build-app2.sh 构建名单内。
5. SVG-5：呈现守恒锁——ZoomableImageView fit 式与 ImagePageView 可用区公式（126/40）字面未动（沿既有 K22 组口径复核即可，落码时确认不重复立项）。

## 6. 真机终判点（落码后）

- 备忘含 SVG 附件：正文内联可见图（非失败占位）→ 点文件行进图片页正常呈现 → 双击/捏合缩放可用、小尺寸 SVG 不被放大；
- URL 形 SVG 图块（`.svg` 结尾与无后缀各一）同样成图；
- 一张畸形 SVG：落「图片加载失败」且 Diag 失败行带 `fmt=svg`；
- GIF 与普通图回归各一（嗅探不误伤）。

## 7. 停门回报

- 定性：proven（审计 + 本稿全链复核，故障域补全至解码层）。
- 口径：方案 A（WKWebView 光栅化于解码漏斗单点），方案 B 与 QL 路均已否决并记理由。
- 待放行后动作：新建 MomentSvgRaster.swift + ImageLoader 单点收口 + verify SVG 组 + 本机自跑相关组；不提交、不 bump，随放行批次组版。

## 8. 落码记录（2026-11-27）

照 §3 设计施工，**无偏离**。落点四处：

1. **新文件 `MomentSvgRaster.swift`**：`isSvgData(_:)`（BOM/空白/XML 序言跳过，DOCTYPE 按 `[…]` 深度扫终结，首元素须 `<svg` 且后接空白/`>`/`/`）；自然尺寸链 `svgRootTag`/`svgAttr`/`svgAttrNumber`/`svgNaturalSize`（width/height 数值属性两项齐备优先 → viewBox → 300×150 回落，回落经 `DiagLog.logOnce("svg-nat-fallback")` 记行）；`SvgRasterizer`（单例 + 串行队列 + 单离屏 WKWebView 挂关键窗口 + `overrideUserInterfaceStyle` 随当前 trait；`WKWebpagePreferences.allowsContentJavaScript = false`、`loadHTMLString(_:baseURL: nil)`；包装 HTML 仅 margin:0 + 透明底 + svg 以帧尺寸 CSS 定型；`rasterScale` = 长边 ≤4096px、总像素 ≤16M 上限内尽量 4；webview 帧点数 = 目标像素 / 设备倍率，快照后以实际像素宽 / 自然宽回填 `UIImage.scale`，`image.size` 恒 = 自然尺寸）。两处实现细化（不改设计口径）：作业序号守卫防迟到导航回调串扰下一作业；scale 回填以快照实际像素为准、设备倍率差异自动吸收。
2. **`ImageLoader` 单点收口**（MomentApp.swift 内唯一改段）：fileId/URL 两路改走私有 `publish(data:failNote:)` 汇合点——嗅探命中 → `SvgRasterizer` 异步路；未命中 → 既有同步 `decodeImage`；数据缺失（网络失败）→ 直接失败发布。发布收口 `deliver` 恒主线程；失败行沿用既有两式（fid 式含 bytes、url 式含 host），SVG 失败追加 ` fmt=svg`。`started` 一次性守卫不变。
3. **build-app2.sh**：新文件进全部 20 遍次级输入 + 新增 primary 遍（`svg_raster.o`）+ 链接行，全文件引用 21 处，`bash -n` 过。
4. **verify_ios.sh**：新增 `SVGR` 取段变量 + **[42] 组 SVG42-1..5**（组号顺延：落码时 [40] 已被备份小批、[41] 已被桥呈现批占用；断言内容与 §5 五条一一对应——SVG42-5 锁 fit 基准 `min(fitScale, 1)` 这一未被他组锁定的缺口，缩放上限式/可用区公式由 K22-2 与图片页可用高检查既锁、注释注明不重复立项）。

**明确未动**（与 §3 清单一致）：`attIsImage`/扩展集、五处 `imageTarget` 赋值（计数锁 = 5；文件行分发处为折行赋值式、计数口径取 `editor.imageTarget =`）、ImagePageView 三态与可用区公式、ZoomableImageView、decodeImage 本体、GIF 路、分享路。本批在 MomentApp.swift 的 diff 只有 ImageLoader 一段。

**自检**：
- verify [42] 组 **5/5 全绿**；本机全量 401 ✓。红项：既有产物陈旧 2 红（ipa 陈旧、产物语言包，tree 构建自解，与各批基线一致）；另 B25-E3-1 一红为**兄弟批在途态**——`convertNodeType(b` 调用点新出现第 3 处（MomentApp.swift:8042，E1 领地），本批首轮全量时未现、本批 hunk 与之零交叠，留归该批更新计数锁。
- 类型检查：MomentApp 与 MomentSvgRaster 两 primary 遍（本机同旗标）**exit 0、零 error**、.o 产出。
- 同树避让：开工快照仅 MomentBridgeOps/MomentOps 两文件为兄弟批改动（与本批领地零交叠）；完工复验其 hunk 完好、本批四文件 diff 纯净。

**真机终判点**（沿 §6，装后逐项判读）：
- 备忘含 SVG 附件：正文内联可见图（非失败占位）→ 点文件行进图片页正常呈现 → 双击/捏合缩放可用、小尺寸 SVG 不被放大；
- URL 形 SVG 图块（`.svg` 结尾与无后缀各一）同样成图；
- 一张畸形 SVG：落「图片加载失败」且 Diag 失败行带 `fmt=svg`；
- 无自然尺寸且无 viewBox 的 SVG：呈现为 300×150 画布口径且 Diag 有 `SVG 光栅化自然尺寸缺失` 行；
- GIF 与普通图回归各一（嗅探不误伤）。
