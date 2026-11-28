# 全面审计批 3：媒体解码与呈现 — 落地报告

- 时点：2026-11-28；基线 HEAD `5e37c07` 起工（期间批 4 线推进至 `4adb4ef`，本批 hunk 与其不重叠、逐笔自提）。
- 范围（总册批 3 定义）：AUD-D-01（块内 GIF 承载）、AUD-E-04 + AUD-D-06 + AUD-D-07（解码管线降采样/缓存/帧时长）、AUD-D-04（视频比例与失败态）、AUD-D-05（取证）。
- 不在本批：AUD-D-02（断言改锚）、AUD-D-03（图片页查名注释）属批 6，未动；状态栏段（回退线在途）、MomentStatusBar*/SplashHost 文件未碰。
- 分级：proven = 读码/实跑可复核；inferred = 推断；unknown = 代码不可判、归真机。

---

## 1. AUD-D-01 块内 GIF 静止 — 定性 proven（代码级）+ 根治

### 1.1 定性

解码侧无问题：`decodeImage`（旧）对多帧源经 ImageIO 逐帧 + GIF delay 组 `animatedImage`。**病在呈现面**：块内全部呈现面都走 SwiftUI `Image(uiImage:)`，该承载只呈 UIImage 的首帧、从不驱动逐帧——管线组好的动图到呈现面被弃。逐面盘点（现行码）：

| 呈现面 | 旧承载 | 所在 |
|---|---|---|
| 图片块 ImageBlockView | `Image(uiImage:)` + scaledToFit | MomentApp.swift |
| gallery 瓦 / 图文卡（编辑）/ 附件整幅图 / 首页封面 | 共用 ItemImageView：`Image(uiImage:)` + scaledToFill | 同上 |
| 图文卡 imgTextCard 图区 | `Image(uiImage:)` + scaledToFill（overlay） | 同上 |
| 图文行 imageTextRow 图半 | `Image(uiImage:)` + scaledToFill（定框） | 同上 |
| MD 预览图 MdImageView | `Image(uiImage:)` + scaledToFit | 同上 |
| 图片页 | ZoomableImageView 的 UIImageView | **唯一可播**（不在本批动） |

与 Web `<img>` 全面播、2026-11-26 裁定②「GIF 播放一并加入」的覆盖面分叉坐实：裁定当年只落到图片页承载，块内面从未接通。**代码级 proven；用户眼中「块内 GIF 动没动」的最终判读仍归真机**（见 §7），本报告不升级表述。

### 1.2 落点（单点承载）

新增 `AnimImageView: UIViewRepresentable`（MomentApp.swift，紧随 MediaDecode）：UIImageView 驱动逐帧；`sizeThatFits` 按 mode 复刻原 SwiftUI 布局语义——
- fill：提议双维齐给直填、单维缺失按图比例补、全缺回自然尺寸（≡ resizable + scaledToFill 的尺寸协商）；
- fit：自然比例 contain、scale ≤ 1 不放大，可选高钳（图块 668、MD 图无钳）（≡ scaledToFit + frame(maxWidth: 自然宽, maxHeight:) 的合成效果）。
非交互（`isUserInteractionEnabled = false`）：点按/长按恒挂容器面，与旧 Image 的被动角色一致，不吞手势（图文卡图区点按、块长按拾起路径不变）。

五面图本体由 `Image(uiImage:)` 换为 AnimImageView（ItemImageView / ImageBlockView / MdImageView / ImgTextBlockView 两面），各面其余修饰（圆角、LiftFrame、contentShape、onTapGesture、占位/失败面）逐字保留。断言 MD64-3 锁：定义恰 1、消费恰 5、文件内 `Image(uiImage:` 代码残留恰 1（头像自定义图——非媒体解码面，不在本批口径）。

## 2. 解码管线收口 — AUD-E-04 + D-06 + D-07

旧 `decodeImage` 自由函数整体退役（grep 零残留），收口为 `MediaDecode` 枚举单点（MomentApp.swift），`ImageLoader.publish` 仍是唯一调用方（SVG 嗅探分流在其前、口径不变）：

- **共享缓存（E-04）**：`NSCache<NSString, UIImage>`，键 = 源键（fid/全 URL）+ 尺寸桶；cost 按解码像素估算、总量上限 96MB。同图在列表/编辑/图片页多面出现只解一次。键不含内容哈希的依据：附件字节按 id 写一次读多次、内容不可变（storage put 语义）。SVG 路不入此缓存（光栅化异步路自有形态，未动）。
- **降采样护栏（E-04/D-06）**：`MediaDecode.decode(data, maxPixel:)` 带上限时逐帧/单帧均走 `CGImageSourceCreateThumbnailAtIndex`（解码即降采样，不先全尺寸再缩；WithTransform 保方向）。块内四视图的全部 load 调用（10 处）传 `MediaDecode.blockMaxPixel` = 2048（纯核心 `MediaDecodePolicy` 单点，覆盖编辑栏整宽 @3x ≈1290 与 iPad 分栏约 1600 仍留余量）；图片页 load 不传（nil）→ 全尺寸 + 独立尺寸桶，缩放查看口径不破。load 双入口加默认参数 `maxPixel: CGFloat? = nil`，既有调用面（含图片页）源码零改动。
- **帧时长（D-07）**：取数面依次读 GIF / APNG / WebP 三字典的 unclamped → clamped 原值，呈纯核心 `MediaFrameTiming.resolve`（MomentImageLoad.swift）裁定：首个正值胜出、下限 0.02、全无正值回缺省 0.1（旧 GIF 口径原样保留、扩至三格式）。宿主表驱动 10 例全过（本机 swiftc 真跑 + verify MD64-2）。
- **代际守卫不另起**：沿 fix_image_card_load 的 ImageLoadGate + loadSerial 单点——publish 把 `activeMaxPixel` 与 serial 同拍更新、deliver 守卫原样；缓存在 publish 内、deliver 前消费，过期结果照旧弃（缓存里存的是按源键的解码产物、与代际正交：旧代际结果即使入缓存，新键呈递时按新键取数，不回闪）。

断言：MD64-1（管线本体）、MD64-2（帧时长表驱动）、MD64-4（接线计数 10 + 双入口默认 nil）。

## 3. AUD-D-04 视频比例与失败态

Web 口径回源：`.blk-media { width: 100%; display: block; }`（editor.css:1399），`<video>` 无比例钳 → **自然比例**。原生旧形态块面恒 16:9（播放面与占位面同），竖屏视频信箱化，分叉坐实。

落点（VideoHolder / VideoBlockView / prepare）：
- **自然比例**：holder 新增 `@Published aspect`（16:9 兜底）；prepare 备源后 `resolveAspect` 异步读视频轨 `naturalSize.applying(preferredTransform)` 回填（键变弃旧）；播放面、占位面、失败面三面统一消费 holder.aspect。
- **失败态**：holder 新增 `@Published failed`，与既有 Diag 结果行成对上屏（失败面 = borderSoft 圆角面 + `video.badge.exclamationmark`，与图片失败面 photo.badge.exclamationmark 同族口径）。触发面：坏 URL（原静默出口一）、附件缺失/空字节（出口二）、写盘失败（出口三）三处备源失败同步置位（回主线程 + 键守卫）；URL 源的 404/坏数据经 `watchItem` 观察 AVPlayerItem.status 转 failed 置位 + 新增 Diag 行 `VIDEO play failed`。键变重备时 aspect/failed/观察句柄一并复位。
- **临时名扩展名**：fid 路临时文件由恒名 `video-<fid>.mov` 改为按附件 MIME（清单类型面 `attachmentTypes[fid]`）经 `UTType(mimeType:)?.preferredFilenameExtension` 派生，派生不出回 `mov` 兜底（播放按内容嗅探、名仅作提示——MIME 缺失的老附件仍可能落 .mov 名，如实登记为已知边界）。

断言：MD64-5（双状态/两方法/失败面/播放失败行/扩展名派生 + 恒名 .mov 字面零残留）。IMG55-5 的 VIDEO prepare 计数为 `-ge` 口径，新增行不破。

## 4. AUD-D-05 SVG 光栅化时序 — 取证结论：保留观察（无落码）

总册处置本就是「保留观察（真机取证）」：SvgRasterizer 在 didFinish 即快照、复杂 SVG 首帧完整性静态不可判。本批无真机取证条件，不凭推断改时序（加落定等待属无证据改行为）。维持现状，取证法留档：真机开一张复杂 SVG（多图层/外链字体替形）备忘，首帧截图与 Web 渲染逐项对图；若缺形，再按「快照前加落定判据」单独立批。本项不关闭、不升级表述。

## 5. verify 断言变更（含两处改判沿革）

- 新增 **[64] MD64-1…5**（尾部自开；[63] 已被批 4 线占用，顺延一位）。落笔期间批 6 线的尾部组笔（`5068df0`，新开 [65]）与 [64] 相邻成同一 diff hunk，[64] 全段已随该笔入史、内容逐字无改动；SVG42-1/J1-6 两处改判由本批自提成笔。
- **SVG42-1 改判**：原锁 `decodeImage(data)` 恰 1 + 全文件 `decodeImage(` 恒 2；管线收口后改锁 publish 段内 `MediaDecode.image(` 恰 1 + 全文件恰 1 + `decodeImage(` = 0。单汇合点不变量不变、符号随机制迁移，沿革已写入断言头注。
- **J1-6 改判**：原锁 `scaledToFit()` 字面（全文件仅 MD 图与图块两处、本批全数换承载后必红）；改段内锚：MdImageView 段内 AnimImageView fit 在位、fill 不入段。专用视图 + 自然比例的原意图保留且加强，沿革入头注。

## 6. 本机自检（结合树实测）

- swiftc -parse：MomentApp.swift / MomentImageLoad.swift 均 0 错。
- 纯核心表驱动：帧时长 10 例本机真跑 `MEDIA_TIMING_PASS`。
- cargo test --workspace：全套件 ok、0 failed（本批未动 Rust，作基线复核）。
- verify_ios.sh 本机全量：本批相关全绿——MD64-1…5 ✓、SVG42-1 ✓、J1-6 ✓、IMG55-1…7 ✓。红项归属（均非本批）：ipa 陈旧 + 产物语言包 2 红为产物类（下轮构建自清）；EB63-3、F30-2、R31-3、五语键数/僵尸键一批红为批 4 线在途编辑两次运行间落入工作树所致（其符号与本批零交集），待其线收官自清。
- **tree 验证排队（未抢构建）**：他线（状态栏回退/批 4）在用 tree，留命令与预期——同步本批四文件（MomentApp.swift / MomentImageLoad.swift / verify_ios.sh / 本报告）后跑 `bash smoke_ios.sh`，预期 verify 全绿（产物 2 红随重建归零）、[64] 五条在 tree 候选①/② swiftc 下真跑通过；构建级风险点（见 §8）若红，按构建输出回修后再报。

## 7. 真机终判点（装机后验，不升级表述）

1. **块内 GIF 动没动**（D-01 本体）：含 GIF 的图块、gallery、图文卡/图文行、MD 图、首页封面五面各看一眼是否逐帧动；图片页对照（应仍动）。
2. GIF 播放速度观感：APNG/动态 WebP 各一（帧时长改读各自字典后不应恒速 0.1）。
3. 竖屏视频块：比例应随视频自然比例（不再 16:9 信箱）、横屏视频不回归。
4. 视频失败面：删附件字节后的视频块 / 坏 URL 视频块应呈失败图标面而非恒占位。
5. 大图滚动：含 48MP 级大图的长备忘滚动内存与流畅度（降采样 + 缓存的实际收益面，代码不可判）。
6. 图文卡图区点按进图片页、块长按拾起：AnimImageView 非交互设定下应与旧形态一致（手势归容器面）。

## 8. 边界与遗留

- **构建级未验面**（本机只有 parse 级）：AnimImageView 的 `sizeThatFits` 签名、AVPlayerItem KVO 闭包捕获、UTType(mimeType:) 等 API 面以 tree 构建为判；已按 SDK 既有用法回源对齐（ZoomableImageView 先例、UTType 既有调用点），仍以构建结果为准。
- 单帧降采样路（缩略图）输出 UIImage scale 恒 1，带 scale 元数据的单帧图（如 @2x 资产图）在块内面的点尺寸可能与旧 UIImage(data:) 路不同——附件/截图类数据无此元数据，图片页全尺寸路不受影响；如真机见块内图尺寸异常，此为首查点。
- 缓存与代际正交性见 §2；SVG 不入缓存为有意保留（光栅化形态不同）。
- D-05 保留观察（§4）；D-02/D-03 归批 6，本批未动。

## 9. 提交清单与一处暂存事故登记

本批自提五笔（不推送、不出包）：纯核心（MomentImageLoad.swift）、管线收口（MediaDecode/AnimImageView 定义 + ImageLoader 接线）、publish 汇合补提、D-01 五面承载、D-04 视频、verify 改判（SVG42-1/J1-6）与本报告——以 git log 为准。事故登记：管线收口笔（`be0ac74`）暂存时，他线并发提交使 `git diff` hunk 编号在「读表→暂存」间漂移，该笔除本批三 hunk 外带入了编辑线的一枚 BlockTextView delegate 签名 hunk（`replacement:` 形参，+5/−5 级）——内容为该线本就要提的改动、无代码损失，仅提交归属混杂；因他线仍在并发落笔，未做历史改写，漏提的 publish 汇合 hunk 已由补提笔（`54b44d2`）补齐。此后各笔改用内容标记选 hunk 并逐笔断言计数，未再漂移。主线如需归属洁净，可在各线收官后自行处置该笔，本批不代办。
