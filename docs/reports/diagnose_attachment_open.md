# 附件打开失效确诊（2026-11-24）

用户报告：编辑页添加附件（PDF 等）后，附件卡「打开」点击无效；原版该按钮触发系统分享机制。

## 原版 vs Rust 链路差异表

| 环节 | 原版（src/） | Rust 修复前（d14763baef） |
| --- | --- | --- |
| 触发面 | `.att-hint` pill（use-editor-dom.js 委托 click，preventDefault + stopPropagation + 清选区/blur） | 整行 `.attachment-file` Dioxus onclick |
| 文件取得 | 开篇全量预加载：editor.js:376 收集 attachment/image/imgTextCard/imageTextRow/gallery 的 fileId，data URL 存内存 files 表；点击同步命中 | 点击后 spawn → `idb::get_attachment().await`（异步） |
| 打开动作 | 同步 `dataURLtoBlob` → `new File([blob], fi.name, {type})` → `navigator.canShare({files})` → `navigator.share({files, title: fi.name})` | await 后 `idb::blob_url()`（无类型 Blob）→ `window.open(url, "_blank")`，返回值 `let _ =` 丢弃 |
| 兜底 | canShare 不过 → `<a download>` 下载 | 无 |
| 失败留痕 | share catch：非 AbortError 才 warn | 只有无条件意图行 `ATT open attachment {fid}`；取数失败/open 被拦均无痕 |
| 图片附件 | BlobMedia 图 → 点击开图（现行为图片页） | 同左（正常） |

## 根因（proven：读码 + box 桩复现双证）

1. **分享机制从未移植（主因）**：Rust 版自首版纳入（091478a）起附件打开即 window.open 套路，非某次重构弄丢 handler；批 5/6 卡片线只动过删卡/菜单路径（0b0c1d9、12dfe0c），未碰打开链。
2. **激活过期**：window.open 在两次 await 之后发起，transient activation 已失效，iPhone Safari 静默拦截且返回 null 被丢弃——真机「点击无效」的机制解释（规范 + 时序判定；Chromium 无头不复现拦截本身）。
3. **失败全静默**：违反结果侧打点红线，Diag 无从判读。

box 复现（生产构建 d14763baef + 桩）：点 PDF 行 → `share:[] canShare:[] open:[{url:blob:…, target:_blank}] downloads:[]`，Diag 仅意图行。

## 各呈现面结论

- attachment 非图片文件行：坏链，已修（见下）。
- attachment 图片标志（image=true）：BlobMedia 图 → 图片页，正常（新构建实证）。
- attachment 文件行·图片类文件（image 标志 false、内容为图片）：扩围笔 1（209f567）已接图片页，本线整合保留。
- music/musicCard 带 fileId 文件行：同型坏链（原版无此行），已一并修。
- image 块 / gallery / 图文卡图片位：图片页路径，未受影响；URL 形入口为扩围笔 1 新增。
- video 文件块：内嵌 controls 播放、无打开按钮，原版无对应面，无恙。
- 备份 ZIP 分享（backup.rs try_share_zip）：独立功能、自带下载兜底，不在本线范围；其 share 同在 await 后发起、靠兜底降级，仅记录。

## 修复（9c3de9e，基于 HEAD dd5476e 与扩围笔整合）

`AttachmentFileRow` 组件（附件文件行 + 音乐文件行共用）：
- 图片类（att_file_is_image）→ 图片页（扩围代码平移，含其 Diag 行）；
- 其余文件：**渲染期预取**挂载即 IDB 取字节构造 `web_sys::File` 存信号（原版开篇预加载的等价结构、与 BlobMedia 同型）→ onclick 同步 `open_js_file`：canShare 通过 → `share({files, title})`，Promise 结局回记 `ATT open {fid} {name} {type} {size}B -> shared|cancelled|error <name>`；不过/缺失 → 同步下载兜底回记 `-> download`；预取未就绪 → 异步取字节 + 下载兜底；无文件 → `-> missing`。预取失败记 `prefetch {fid} -> miss|file-error`。
- 类型取 manifest 条目 type（插入侧三处均登记 {name, type}；缺失时 File.type 为空串，与原版 fi.type 缺省的终态等价）。
- 旧 window.open 两处与意图日志整段删除（blocks.rs 内 `open_with_url_and_target` 零残留）。
- 文案：`media.open` 五包对齐原版动作短语（点击打开/點擊打開/Tap to open/タップして開く/눌러서 열기；该键全仓仅此一处使用）。
- 触发面保持整行（与扩围线现状一致）。

## 验证（box，构建 bc55e05687 = HEAD dd5476e + 本线两笔）

- 本地门禁：cargo check 无新警告；cargo test --workspace 全绿（119 项）；verify_rustweb ALL PASS（12 节）。
- probe_attachment_open ALL PASS：PDF 行 share 以 File{季度报告.pdf, application/pdf, 2015B} + title 调用（canShare 先行、window.open 零次）；Diag 实测 `open att-pdf-1 季度报告.pdf application/pdf 2015B -> shared`；音乐行 share File{演示音频.mp3, audio/mpeg, 509B}；图片附件进图片页；canShare=false 下载降级。点击均走 touchscreen tap（真机同路）。
- 回归：probe_page_transitions ALL PASS、probe_card_menu ALL PASS、smoke blocks/gaps 零 FAIL、probe_lightbox_page 35/36（红项见跨线冲突条）。
- 真机终判（待部署后）：点 PDF 应弹系统分享面板；失败时 Diag ATT open 行给出错误名（如 NotAllowedError）。

## 跨线冲突与相邻事项（需父级知悉）

1. **probe_lightbox_page ⑨ 与本修复冲突**：扩围笔 2（dd5476e）的 ⑨ 断言「PDF 行点按开新标签（系统打开）」，锁定的是本笔按用户报告 + 原版源码替换掉的 window.open 临时行为；整合构建上 ⑨ 红、其余 35 项全绿。建议扩围线将 ⑨ 改为分享口径（share 桩被调 + 不进图片页），或由父级并笔处理。本线未擅改他线探针。
2. **图片页返回故障归属已定**：本线早期在构建 223b262a41 上见 probe_lightbox_page 返回后 `.detail` 不显形——经对照实验（HEAD 原样构建 dd7b4bae9d 同探针 ALL PASS）与过渡线 8a46d3d 提交信息互证：系灯箱笔 5 前的旧 style 通道粘滞（槽位隐藏 style 空串更新不落地），已由 308634f（笔 5.5，class 通道）修复，与本线 diff 无关。
3. **既有小疣（未动）**：桥 click 委托对附件 wrap 左右 28px 边缘发 insertPara，而行 onclick 同时触发打开动作（图片页/分享均然）——双动作属两线现状，本线未动桥；如需收口（边缘区不触发打开）须桥侧协调另笔。
4. 本线落码期间灯箱扩围线（209f567/dd5476e）与过渡线（308634f/8a46d3d）在同文件并行落码，本线经 stash + 对照构建后 rebase 整合，无覆盖丢失（att_type_in_manifest 与扩围线同名同体，取其一）。
