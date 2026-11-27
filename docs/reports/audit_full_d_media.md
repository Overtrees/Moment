# 全面审计分报告 D 片：媒体与图片页（只读审计）

- 时点：2026-11-27；仓库 HEAD `b682d02`（与任务基线一致）。
- 范围：图片页全口径、gallery（删/排序/首项封面联动）、视频（插入/播放器宿主）、SVG 解码（MomentSvgRaster.swift）、附件行分流、可开范围边界、图片名来源链。代码面：`rust/apps/ios/app/MomentApp.swift`、`MomentSvgRaster.swift`、`MomentEditorTransition.swift`、crates/ffi+storage 附件名面；Web 对照：`rust/apps/web/styles/panels.css`、`base.css`、`src/blocks.rs`、`src/main.rs`。
- 基线：plan_selftest_coverage.md §4.6（IMG-01…08）、audit_detail_image_page.md、audit_home_other_deep.md §3、design_lightbox_rootcolor.md（灯箱已退役、仅作背景链参考，本片不重复审 Web 灯箱）；裁定准绳：AGENTS.md / MEMORY.md（12 字截断+单行、缩放只手动、查名序=清单优先节点兜底、可用区公式对齐 Web 审计裁定④）。
- 工作树注记：审计读的是工作树现行文件；未提交改动为状态栏在途线（MomentApp 的 T 令牌段、MomentEditorTransition 宿主段、build/verify），经 diff 核对**未触任何媒体/图片页代码段**，本片行号以工作树为准。排除项（appex、状态栏采样、APNs/iCloud）未审。
- 分级：proven=读码/报告可复核；inferred=推断；unknown=代码不可判、须真机取证。像素/手势跟手类一律标 unknown 并注取证法。
- 方法：只读 grep/逐段读码 + verify_ios.sh 断言面核对；未跑构建、未跑 verify（纪律）。

---

## 1. 回归抽查（必做五项）

| # | 抽查项 | 结论 | 证据 |
|---|--------|------|------|
| ① | 标题截断 12 字 + 单行不折行 | **在位 proven** | `ImagePageView.titleText`（MomentApp.swift:21676-21681）：`n.count > 12` 时 `String(n.prefix(12)) + "…"`，仅呈现截断、Diag 记全名（21748）；`CompactTitle`（20107-20136）`lineLimit(1)` 在位（全应用共用、首页/设置子页同受益）。曾有的长名折行前科未回潮。断言面瑕疵见新发现 D-02 |
| ② | GIF 播放与缩放（0.9.58 媒体增强批） | **图片页在位 proven；块内呈现面有静止风险，见 D-01** | `decodeImage`（3719-3746）CGImageSource 逐帧 + GIF delay（下限 0.02、无信息 0.1s）组 `animatedImage`；图片页经 `ZoomableImageView` 的 UIImageView 承载（3833 起）可播。缩放：`fit` 中 `base=min(fitScale,1)`、`maximumZoomScale=max(base*4,1)`、双击 fit↔min(2.5×base,max)、contentInset 居中；全仓无程序化自动放大点（audit_home §3.2 同结论，本轮复核 ZoomableImageView 全文无异议）。手势跟手/双击命中 unknown（真机：双击/捏合各一遍看倍率与 Diag 无异常行） |
| ③ | gallery 删/排序 + 视频插入（0.9.58 增强批） | **在位 proven** | 删：`applyGalleryRemove`（6160-6182，压栈→摘项→落盘→Diag，角标接线 13725-13742）；排序：`applyGalleryMove`（6192-6224，一拖一撤销步）+ `GalleryTileDropDelegate`（13760-13785，dropEntered 实时换位）；视频：`addVideoBlock`（7352-7368，attrs.fileId 规范位）+ 选片路（11267）与附件文件路 UTType.movie 分流（11335）双入口；verify [33] M33-1…5 锁形态（本轮只读核对断言文本，未执行） |
| ④ | attachment_names FFI 面 + put 带名登记（0.9.36 根治） | **在位 proven** | FFI：`put_attachment(id,data,name)`（crates/ffi/src/lib.rs:133-144）、`attachment_names_json`（146-149，契约 checksum 断言 569 行在位）；storage：`put_attachment`（crates/storage/src/lib.rs:436 起）非空名同步写 manifest_json；Swift：`Library.putAttachment`（1666-1693）成功后同步增补内存表 `attachmentNames[id]=name`；选图器/文件导入全程传真名（pickerFileName 4070 段、fileImporter 11318 传 lastPathComponent） |
| ⑤ | 图片页可用区公式 vs Web 逐项对照 | **逐项等值 proven（文本面）；运行时几何 unknown** | 见 §2.1 对照表。verify K22-12 锁顶 126/底 40+safe 字面 |

---

## 2. 图片页（ImagePageView，MomentApp.swift:21638-21768）

### 2.1 可用区公式逐项对照（Web panels.css:155、169-171）

| 项 | Web | 原生 | 判 |
|----|-----|------|----|
| 顶让位 | `.page-content` padding-top 126px（页头 fixed 浮动不占流） | `.padding(.top, 126)`（21734）+ availH 减 126 | 等值 |
| 底让位 | `calc(40px + env(safe-area-inset-bottom))` | availH 减 `40 + geo.safeAreaInsets.bottom`、底 padding 同式（21701-21702、21735-21736） | 等值 |
| 横向 | `.img-page-content` 左右 padding 0、全宽 | ZoomableImageView viewport 宽 = geo 全宽、无横 padding | 等值 |
| 图适配 | img max-w/max-h 100%、width/height auto：大图只缩、小图不放大、flex 居中 | `base=min(fitScale,1)` 上限 1:1、contentInset 居中（ZoomableImageView.Coordinator.fit/center） | 等值（判定与呈现同用 availH，0.9.34 同源口径保留） |
| 页头高 | 返回钮 fixed、top=safe+7；标题胶囊 top 同源 | ChromeView（20139-20166）：钮 46 玻璃圆、padding top 7；CompactTitle top 11、17 semibold/tracking −0.3/padding 16/6/radius 20/overlay 档 | 与 audit_detail_image_page #1 既判一致，本轮复核无漂移 |

运行时几何（GeometryReader 的 safeAreaInsets 在转场宿主 VC 内的实际取值、图在可用区内是否真居中）代码不可判，unknown——取证法：真机开一张高图与一张小图各一，截图量图边距与居中（U5 IMG-03 探针量测同面，矩阵已登记缺口）。

### 2.2 其余口径

- **独立页与返回恢复**：呈现已移交转场宿主 `MomentEditorTransition.observeImage`（390-430）：imageTarget 置位 push、VC 移除反向清 target、编辑器 VC/同一 EditorModel 留栈下层不销毁。机制面 proven；返回后焦点/光标/滚动恢复深度 unknown（矩阵 IMG-06 已登记，恒归真机人工一条）。现状与 audit_home §3.4 一致，无回退。
- **标题来源**：`displayName`（21666-21673）fileId 在时查 `library.attachmentName(for:)`、无果回退调用点传入名；URL 图用传入名。查名链本体见 §6。注：ImagePageView 头注写「清单为唯一真值」，与 Library 实际的节点兜底序有文字分叉，见 D-03。
- **Diag**：open 行图就绪后记全名 + `nat=` 自然像素（size×scale，21740-21752）、失败 `nat=error`、close 行钮路径 + onDisappear 兜底去重（21684-21689、21760-21766）——与 audit_detail_image_page #8/#9 修复口径一致，proven。
- **三态**：图/失败文案/ProgressView。失败文案已走 `Lang.t("imgpage.load_failed")`（21719），且 ImagePageView 已声明 `@EnvironmentObject langStore`（21650）——audit_home §3.3 的 IMG-08 i18n 残留（硬编码「图片」三处 + 失败文案）**已由 i18n 收尾批清零**：三处回退名均引 `imgpage.untitled`（10098/13717/15929 调用点，verify T-1 锁恰 3 处、T-2/T-3 同组），五语包两键齐备（lang/*.json:186-187）。旧账销账（见 §8）。
- **背景**：ChromeView `.background(T.bg)` 根色同源，与 Web `.img-page` 回落根色口径一致，proven。
- **缩放边界**：旋转/分栏视口变化时倍率钳回 base、偏移归零（Coordinator.fit 的 resized 支，L-5 已落，verify K22-13 锁）；旋转后实态 unknown 归 IMG-04 真机复验。

## 3. Gallery（GalleryBlockView / EditorModel）

- **增/换/删/排序四动作全在模型单点**：Add（6114）、Replace（6138）、Remove（6160）、Move（6192），均 pushHistory→改 `node.attrs.items`→nodeVersion+1→scheduleSave→Diag，与 impl_media_enh
...[truncated 6593 chars]