# Web 画廊添加失效根治 + 同型普查 + 媒体几何统一

- 日期：2026-11-28
- 分支：`fix/web-gallery-add`（worktree `~/workspace/Moment-webgallery`，基点 main `ffcf5ee`）
- 范围：Rust Web（Dioxus）编辑器。本批**只落码不部署**（部署与启动慢线由主线统一排序，避免戳互相覆盖）；生产戳未动（仍为 `5ff8c91ac5`）。
- 证据分级：proven = 真实触摸路径 + op 流/change 计数/Diag 实测；inferred = 代码回源推定；unknown = 未能确证。

## 一、实报与复现（生产构建，tree Chromium，CDP 真实触摸）

实报：画廊只能加一张图，有图后右侧无反应；截图示有图态单张竖图居左半、右半整块空白、底部提示的加图路径为长按菜单→「编辑」。

基线场景（新建备忘→斜杠插画廊→长按开卡菜单→「编辑」→空瓦选图→各点位点按，全程装 `dioxus.send` op 流、input click/change 监听、Diag 同步取证）：

1. 空态第一张可加（proven）：空瓦点按发 `cardPick galleryAdd`，选图器开，`handle_media_files` 以 `index=None` 追加成功，计数 0→1。
2. 有图态无添加入口（proven，主病）：呈现面无任何添加瓦；点右半空白格（命中链 `DIV.gallery-grid → DIV.atomic → DIV.blk-wrap`）后 **op 流为空、无 input click、无 change、计数不变**——死区。（量测中 `waitChooser` 曾返回一次事件，经 op 流核对为首轮选图的 CDP 拦截残留事件、非本次点按触发，见 §五量测注记。）
3. 菜单→「编辑」路径核过（proven）：菜单仅「编辑/删除此块」；「编辑」只置卡编辑态、切换占位文案键（`media.gallery_add` / `media.add_image` 两组编辑态/常态文案），不接任何追加动作——既定路径本身是死胡同。
4. 换图路完好（proven）：点图发 `galleryItem index=Some(0)`，替换成功。
5. 同文件重选静默失效（proven，同族第二病）：换图选同一文件时 `INPUT_CLICK` 有、选图器开，但 `CHANGE` 不发火（计数 1 不增），`#file-media` 的 value 停在 `C:\fakepath\timg2.png`——常驻 input 选后从不复位 value，浏览器按 value 判同文件不触发 change。

## 二、定案

**主病（呈现+路由双缺，非 machinery 断线）**：添加链完好（`cardPick galleryAdd → MediaReq::GalleryPick{index:None} → #file-media → push 追加，多选、全 fid`），唯一触发点被空态门死：

- 呈现面：`blocks.rs` 非空 gallery 只渲染 `.gallery-grid` 本体，无添加瓦；空态才有双瓦。
- 路由面：`editor.js` 编辑态 gallery 分支只接两路——`.gallery-empty-tile`（空态瓦）与 `.gallery-grid img`（换图）；格网空白区不命中任何分支，穿透块选择，无反馈。
- 原版对账（归档原版）：render 层非空画廊同样无瓦，但其编辑 DOM 语义是点画廊任意非图区即开选图器追加（pendingImageBlock + concat 追加）。即原版「添加只在空态」的设计缺口被两端忠实移植；原生 iOS 同根同病（添加 machinery 完好、触发点被空态门死），两端修复形态已由主线对齐（见 §四）。

**第二病（file input 生命周期，全站同族）**：三个常驻隐藏 input 选后均不复位 value——`#file-media`（`ops.rs handle_media_files`）、`#file-attach`（`ops.rs attach_file`）、`#file-avatar`（`layers.rs pick_avatar` 的 eval）。健康对照：`#file-import` 的 `backup.rs pick_file_bytes` 本有 `input.set_value("")`，仓内本有正确范式；原版 `handleFilesSelected` 首行即清值。

## 三、同型普查（全站「重复选图/再添加」流，逐项第二次触发实测）

| 流 | 入口 / input | 结论 | 处置 |
|---|---|---|---|
| 画廊空态加第一张 | 空瓦 / #file-media | 正常（基线 proven） | 不动 |
| 画廊有图态追加 | 无入口 | **主病**：无瓦 + 空白区无路由 | 已修（§四 1、2） |
| 画廊换单图 | 点图 / #file-media | 路由正常；同文件重选**同病**（未复位） | 已修（§四 3），回归 proven |
| 单图块换图 | 点图/占位 / #file-media | **同病**（未复位） | 已修，隔离回归 proven（change ×2、value 归空） |
| 图文卡图区换图 | 点图区 / #file-media | **同病** | 已修，回归 proven（同文件第二次 set，change 1→2） |
| 图文行图区换图 | 点图区 / #file-media | **同病** | 已修，回归 proven（change 3→4） |
| 附件再添加 | 菜单 label / #file-attach | **同病** | 已修；图片文件落 image 块、非图片落 attachment 行（`attach_one` 按 mime 分流的既有设计），两分支同文件连加 proven（块数 1→2、change 累计 ×4） |
| 头像更换 | 头像钮 / #file-avatar | **同病** | 已修，回归 proven（同文件两次均触发 `avatar set` Diag、value 归空） |
| 备份导入选包 | 设置 / #file-import | 健康（原有复位范式） | 不动，§22 加守恒锁 |
| 视频添加 | —— | 无选文件入口：`MediaReq` 仅 `SetImage/GalleryPick` 两变体，无斜杠视频项，`#file-media` accept=image/* 且处理函数拒非图片。视频块仅由导入/存量数据进入 | 无此路径，非同病，登记 |
| MD 插图 | —— | 粘贴路径只处理文本/URL（`editor.js` paste 分流），无文件入口 | 不在隐藏 input 族，登记 |

## 四、根治（落码）

1. **有图态添加瓦（呈现单点）**：`blocks.rs` 非空 gallery 分支在格网末格追加添加瓦，仅卡编辑态（`card_editing`，逐块 CardEdit 上下文）呈现，非编辑态不露瓦。瓦复用空态瓦的类与几何（`gallery-empty-tile gallery-add-tile`：高 366 / radius 22 / fill-subtle / 图标+「点击添加」），不带 `data-liftsurface`（格网整体已标记）。
2. **路由同源（不新增发送点）**：添加瓦因共用 `.gallery-empty-tile` 类，直接被既有空态分支接住、同发 `galleryAdd`——两态共用同一添加机制，非叠加新路。另在 `editor.js` gallery 分支末尾给格网非图区加兜底：编辑态下点 `.gallery-grid` 非图区（含末行空格）同发 `galleryAdd`，与原版「非图区点按追加」语义合流，消除瓦外死区。`dispatch.rs` cardPick 注释同步订正（galleryAdd 为空态/有图态同链）。
3. **input 生命周期收口**：三处在消费单点统一「先快照 FileList 为 `Vec<File>`、再 `set_value("")`、后处理快照」（与原版 Array.from 后清值同语义，清值不影响已捕获 File 对象读取）：`handle_media_files`、`attach_file` 各一处；`pick_avatar` 的 eval 在捕获 file 后立即 `f.value=''`（FileReader 读已捕获对象，不受影响）。
4. **与原生形态的对齐关系**：同一修复形态——卡编辑态下于末项后追加一张添加瓦、点按直达现成 add 链、非编辑态不露瓦；Web 的编辑态门以 Web 自身机制（CardEdit 逐块上下文）为准。原生线在 0.9.67 合并收口后基于新 main 同形态落码，不在本批内。

## 五、几何统一（用户改判，覆盖原口径；与原版数值异同如实留账）

裁定口径：画廊瓦卡内对半分填满卡宽、只留中间小缝；单体图片卡左右留白对齐；缝统一 4（用户在 3/4/5/6 中授权主线定 4）；量测三项以卡（`.blk-wrap`）内缘为参照：左缘→瓦左缘、瓦右缘→右缘、瓦宽 vs (卡内宽−4)/2。目标态反推：卡缘侧 inset 为 0（瓦贴卡内缘），4 只活在缝里。

**量测（393 CSS px 视口，卡宽 361）**：

| 项 | 改前（原版度量） | 改后（实测） | 目标 |
|---|---|---|---|
| 卡内左缘→瓦左缘 | 36 | 0 | 0（贴缘） |
| 瓦右缘→卡内右缘 | 36 | 0 | 0（贴缘） |
| 中间缝（空态） | 6 | 4 | 4 |
| 中间缝（有图态格间） | 4（裸值） | 4（令牌） | 4 |
| 瓦宽（空态/单图格） | 141.5 / 142.5 | 178.5 | (361−4)/2 = 178.5 |

**落码**：

- `tokens.css` 新增单一令牌 `--media-gap: 4px`（定义恰一处）；消费恰两处：`.gallery-grid` gap（原裸值 4 改令牌）、`.gallery-empty` gap（6→令牌）。
- `.editor-body .atomic[data-type=image/gallery]` 边距 `8px 36px → 8px 0`：媒体原子块贴卡内缘全宽，与图文/链接/附件卡同口径。原 36px 为原版度量，本项系用户改判覆盖，旧注释（1318 行自注、D-17 注）已同步改判注记。
- 宽屏三处覆盖（spread / independent-scroll / flow-columns 的 `margin: 8px 0`）**删除**：其选择器用子组合子要求 atomic 为 `.editor-body`/`.editor-column` 直子，而实际 DOM 中 atomic 恒在 `.blk-wrap` 内，三条覆盖从未命中（死规则）；基线归零后它们与基线同值亦无存在意义，一并清零（行为零变化）。
- 单体图片块：原子块边距同归零；块内 img 的 contain 居中口径保留——窄高宽比图片两侧的空区由图片自身宽高比决定（非 CSS 边距），不在本次收口面。

**全卡型普查（窄屏编辑语境，styles/editor.css 逐项量）**：

| 卡型 | 现行边距/间隙 | 结论 |
|---|---|---|
| 画廊（空态/有图态） | 36px 边距、缝 6/4 | **收口**（本节上表） |
| 单体图片 | 36px 边距 | **收口**（同上） |
| 视频 | 无边距规则（0，填满宽） | 合理保留：本已贴缘 |
| 图文卡 | margin 8px 0、图区 width 100% | 合理保留：本已填满卡宽 |
| 图文行 | margin 8px 0、内部图文 gap 10px | 合理保留：10px 为图文分栏内距，非卡缘留白 |
| 链接卡/音乐卡（.link-card-block） | margin 8px 0 | 合理保留 |
| 嵌入/代码等原子块 | margin 8px 0 系 | 合理保留 |
| 附件 | margin 8px 0 | 合理保留 |
| .atomic-placeholder | padding 24 | 合理保留：占位面内距，非卡缘留白 |

## 六、断言（verify_rustweb §22 新增）

- 添加瓦呈现门：`blocks.rs` 添加瓦恰一处且挂 `if card_editing` 门。
- 路由同源：`editor.js` 中 `galleryAdd` 发送恰两处（空态/添加瓦共用分支 + 格网非图区兜底），格网兜底选择器在位。
- input 复位：`ops.rs` `set_value("")` 恰两处、`layers.rs` 头像 eval 复位恰一处、`backup.rs` 导入复位保持一处。
- 几何令牌：`--media-gap: 4px` 定义恰一处、消费恰两处且两 gap 均走令牌；媒体原子块边距为 `8px 0`；`margin: 8px 36px` 声明零残留；宽屏死覆盖零残留。
- 结果：**VERIFY RUSTWEB ALL PASS**（含 dist 级锁；dist 为本批本地构建，戳 `09b75a3d2d`，仅供 tree 回归、未部署）。

## 七、回归结果（tree Chromium，本批 dist 静态服务，CDP 真实触摸）

- **画廊主线场景全过**：空态几何三项达标（贴缘 0 / 缝 4 / 瓦宽 178.5）；编辑态连加至 4 张（空瓦 1 张 + 添加瓦多选追加 2 张 + 添加瓦再加 1 张），1/3/4 张时添加瓦恒在；同文件换图重选 change 照常发火、value 归空；格网空白格点按开选图器（兜底）；退出编辑态后添加瓦消失。
- **普查场景**：图文卡、图文行同文件第二次 set 均发火（见 §三）；单图块同项在隔离场景全过（组合场景中曾因长文档滚动定位丢失一次点按、驱动进程后被环境回收，未在组合场景内复跑——以隔离场景结论为准，差异为量测面问题非应用问题）；附件两分支、头像两项均过（见 §三）。
- **量测注记（harness 伪影，proven）**：本机 CDP 开启 `Page.setInterceptFileChooserDialog` 后，单次 input click 可产生**两个** `fileChooserOpened` 事件（实测 iclick=1、事件 2 个、逐个应答各发一次 change）。只应答首个事件时，残留事件会被下一次 `waitChooser` 误作新选图器——基线「空白点按开选图器」假象与头像首选计数偏差均源于此。后续量测以 op 流 / change 计数 / Diag 为准绳、选图器应答采排空口径后，结论稳定。

## 八、待部署注记

本批不部署：分支 `fix/web-gallery-add` 待主线与 Web 启动慢线统一排序合并发布。合并时注意 `styles/editor.css`、`src/blocks.rs`、`src/editor/ops.rs`、`src/editor/layers.rs`、`src/editor/js/editor.js`、`src/editor/dispatch.rs`、`styles/tokens.css`、`scripts/verify_rustweb.sh` 八文件；与启动慢线（sw/部署面）无文件交叠预期。
