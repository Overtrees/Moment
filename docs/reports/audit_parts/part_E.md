# 分片 E 审计：菜单、对话框、toast、导出与编辑页入口

## 覆盖声明

- 原版必读文件已完整通读：`src/app/runtime.js`（223 行，全文）、`src/app/editor/export.js`（521 行，全文）、`src/components/BgSheet.js`（48 行，全文）、`src/styles/panels.css`（182 行，全文）、`src/app/editor.js`（3339 行）中菜单/弹层部分（菜单状态机 186–295 行、附件/导出回调 1304–1416 行、顶栏与全部浮层渲染 2455–3339 行，含返回 fab、标题坞、头像、更多菜单、导出面板、BgSheet/ImageTextSheet/lightbox 挂载点；结构渲染/编辑行为略读）。
- 关键事实（proven）：**`runtime.js` 内没有任何 toast / 对话框 / 菜单基础设施**——它只是常量、存储与编辑器适配层。原版编辑页的失败提示实际走 `src/error-boundary.js` 的 `MynoteErrors.addWarn`（黄/红点徽章 + 点击展开面板，上限 20 条、不自动消失）；该文件不在必读清单内，为定位 toast 口径补读全文，特此声明。原版 `panels.css` 也只有备份页卡片样式，编辑页一切弹层样式均为 `editor.js` 内联样式。
- 补读：`src/components/ImageTextSheet.js`（全文，编辑页弹层）、`src/styles/tokens.js:116`（BgSheet 预设色源）、`src/styles/inline.js:6-11`（fixedOverlay 定义）。
- Rust 侧已读：`rust/apps/web/src/editor.rs` 菜单/底表/对话框/toast/入口部分（939–1150、1591–1600、1884–2010、2385–2670、2783–3400、5168–5257、5971–6074 行）、`rust/apps/web/src/editor/export.rs`（1353 行，全文）、`rust/apps/web/styles/panels.css`（218 行，全文）、`rust/apps/web/styles/editor.css` 弹层段（254–275、600–675、894–1033、1240–1427 行）、`rust/apps/web/styles/base.css:625-645`（.backup-toast）、`rust/apps/web/src/settings.rs:70-108`（Toast 实现）、`rust/apps/web/lang/zh-CN.json` 相关键；`main.rs`/`list.rs` 仅略读编辑页入口衔接（main.rs:627-630、875-891；list.rs:1021、1131、1211）。
- 预期差异（只记事实、不记缺陷）：设置页谷歌备份入口已按用户裁定移除。本分片范围内（编辑页顶栏菜单/导出面板）两版均无任何谷歌/云备份入口，此事与编辑页无关，不计入差异条数。
- 本分片只审计，未编辑任何源码、未构建、未部署。行号以审计时工作树为准。

## 菜单项对照表（顶栏「更多」菜单，自上而下）

| # | 菜单项 | 原版（editor.js） | Rust（editor.rs / zh-CN.json） | 结论 |
|---|------|------|------|------|
| 1 | 双栏独立滚动（开关，副文案「平板与 PC 可分别滚动两栏」） | 2807–2827，role=switch，columns 图标 | 3030–3055，role=switch，menu.twopane / menu.twopane_sub 同文案 | 一致（细节见已核清单） |
| 2 | 撤销（副文案「快捷键→ Cmd+Z / 三指左滑」） | 2828–2889，accent undo 图标；无历史时 opacity 0.3、**不禁用** | 3056–3066，menu.undo / menu.undo_sub 同文案；无历史时 `disabled` + pointer-events:none | **有差异 → E-4** |
| 3 | 重做（副文案「快捷键→ Cmd+Shift+Z / 三指右滑」） | 2890–2955，同上口径，marginBottom 4 | 3067–3077，同撤销口径 | **有差异 → E-4** |
| 4 | 添加附件（副文案「图片、PDF 或文本文件」，带 ›） | 2956–3027，button，先关菜单再唤起文件选择，尾随 › | 3078–3085，`<label for="file-attach">`，**无 ›**，菜单待选完文件才关 | **有差异 → E-5、E-6** |
| 5 | 导出笔记（副文案「Markdown · HTML · PDF」，带 ›，上方有分隔线分组） | 3028–3077，下载图标 strokeWidth 2.2，分隔 div borderTop | 3079–3091（.menu-section，editor.css:1414 同口径分隔），图标 strokeWidth 2.5 | 基本一致（图标线宽 → E-7） |
| 6 | 更换背景色（副文案「为当前笔记设置专属底色」，带 ›） | 3078–3161，**紫色** palette 图标（--color-purple），尾随 › | 3092–3107，palette 图标 stroke=--color-accent，**无 ›** | **有差异 → E-5、E-7** |
| — | 删除笔记 / 置顶 / 分享 / 复制 | 菜单内**不存在**（全文检索无） | 菜单内**不存在** | 一致（两版皆无） |
| — | 块上下文菜单 / 长按菜单 | **不存在**（全文无 contextmenu/长按菜单） | 无上下文菜单，但有选中块浮动按钮「删除此块/换图/选图」 | **有差异 → E-14** |

导出面板项（两版同集）：Markdown（badge `MD`，副文案「保存为 .md 文件」）/ HTML（badge `<>`，「保存为独立网页」）/ PDF（badge `PDF`，「打印或存储为 PDF」），尾注「PDF 会打开浏览器打印窗口，可在其中存储为 PDF。」——项集、顺序、文案、badge、尾注均一致（原版 editor.js:3208-3265；Rust editor.rs:2986-3018 + zh-CN.json export.*）。

## 差异条目

### E-1 编辑页失败提示通道：错误徽章被 toast 全宽条取代
- 结论：有差异
- 原版：src/error-boundary.js:31-48（addWarn）、src/error-boundary.js:95-197（右下角徽章+展开面板）；触发点 src/app/editor.js:1313、1373、1394、1414
- Rust：rust/apps/web/src/editor.rs:1591-1600、2938-2947；rust/apps/web/src/settings.rs:84-108；rust/apps/web/styles/base.css:630-641
- 差异：原版编辑页**没有 toast**：导出模块缺失、PDF 窗口被拦截、打印失败、导出失败等只调用 `MynoteErrors.addWarn`，在右下角出现黄点徽章（36×36，bottom=64px+安全区），不自动消失、点击才展开详情面板（含时间与堆栈，最多 20 条）。Rust 无此徽章在编辑页的等价物，改用与备份页同规格的 `.backup-toast` 全宽条（left/right 16px、bottom=16px+安全区、z 5000、220ms 上滑进场），success 3s / 其余 6s 自动消失。通道、位置、驻留时长、队列（原版累积列表 vs Rust 单条覆盖、仅 seq 重挂）全不相同。
- 严重度：高
- 证据：proven（两版源码逐行对照；Rust 代码注释自认「原版编辑器无自有状态条，形态复用备份页 .backup-toast 全宽条口径」editor.rs:1591-1594）

### E-2 导出成功 toast 为 Rust 新增，且 HTML 导出复用了 Markdown 文案
- 结论：有差异
- 原版：src/app/editor.js:1309-1416（handleExportFormat 全程无任何成功提示，下载/打印即结束）
- Rust：rust/apps/web/src/editor.rs:2411（MD）、2553（HTML）；rust/apps/web/lang/zh-CN.json `export.done = 已导出 Markdown`
- 差异：Rust 在 MD 与 HTML 导出成功后都弹 success toast，且两处共用同一键 `export.done`，其 zh-CN 文案是「已导出 Markdown」——**HTML 导出成功时用户看到的是「已导出 Markdown」**，文案与实际格式不符。PDF 导出成功则无 toast，三种格式反馈不一致。原版三种格式成功均无提示。
- 严重度：中
- 证据：proven（editor.rs 两处 `ed_status2.show("success", t("export.done"))` 与语言包原文对照）

### E-3 附件失败在 Rust 编辑页无用户可见提示（仅 Diag 日志）
- 结论：有差异
- 原版：src/app/editor.js:1239（附件保存失败，已取消插入，请重试。）、1429（此处只接受图片文件，请重新选择。）、1444（图片读取失败，未添加该图片。）、1468（卡片图片保存失败，未添加图片，请重试。）均经 addWarn 呈现
- Rust：rust/apps/web/src/editor.rs:6026-6030（IDB 写失败仅 `diag::log` 后 return）、5985-6074（attach_file/attach_one 无 error toast 调用）
- 差异：Rust 附件写入 IDB 失败时静默返回，用户无任何反馈（成功时反而有原版没有的 `attach.done` success toast，editor.rs:6072）。文件读取失败（array_buffer Err）在 6018-6020 同样静默 return。原版各类附件失败都有明确中文 warn 文案进入徽章。
- 严重度：中
- 证据：proven（Rust attach 路径全文检索仅一处 ed_status.show，为 success 分支）

### E-4 撤销/重做禁用态实现不同：原版不禁用、点按仍关菜单
- 结论：有差异
- 原版：src/app/editor.js:2828、2890（onClick 先 `closeEditorMenu()` 再按 past/future 长度守卫；样式仅 opacity 0.3 + cursor:default，无 disabled 属性）
- Rust：rust/apps/web/src/editor.rs:3057-3058、3068-3069（`disabled: !can_undo / !can_redo`）；rust/apps/web/styles/editor.css:1289（.menu-item.dis = opacity .3 + pointer-events:none）
- 差异：无历史时，原版该项仍可点按，点按效果是关闭菜单（无撤销动作）；Rust 用原生 disabled + pointer-events:none，点按完全无反应、菜单保持打开。视觉同为 0.3 透明度，行为不同。
- 严重度：中
- 证据：proven（两版事件与属性对照）

### E-5 「添加附件」「更换背景色」两项尾随 › 在 Rust 缺失
- 结论：有差异
- 原版：src/app/editor.js:3013-3026（附件项 ›）、3147-3160（背景项 ›），均为 font-19、--color-placeholder-strong 的 › span；导出项同样有 ›
- Rust：rust/apps/web/src/editor.rs:3078-3085（附件 label 无 chevron span）、3092-3107（背景 button 无 chevron span）；仅导出项有 .menu-chevron（3088-3090 附近 menu-section 内）
- 差异：原版菜单内三个可下钻项（附件/导出/背景）尾随 › 全齐；Rust 只有导出项有 ›，附件与背景两项缺失，视觉齐整度与「可下钻」暗示不一致。
- 严重度：中
- 证据：proven（RSX 逐项对照）

### E-6 添加附件的菜单关闭时机不同（取消选择时菜单残留）
- 结论：有差异
- 原版：src/app/editor.js:1304-1308（handleAddAttachment 先 closeEditorMenu 再 fileInput.click()）
- Rust：rust/apps/web/src/editor.rs:3078（`<label for="file-attach">` 直接唤起系统选择器）、3295-3305（file-attach 的 onchange 里才 animate_menu_close）
- 差异：原版点「添加附件」菜单立即退场（220ms）后才出文件选择器，取消选择后回到无菜单状态。Rust 靠 label 原生唤起选择器，菜单在选择期间仍挂载；只有真正选了文件（onchange）才关菜单，用户在选择器里取消时菜单原样残留。
- 严重度：中
- 证据：proven（事件绑定位置对照；取消不触发 onchange 为浏览器通则，属 inferred 的运行时推论部分已按源码结构成立）

### E-7 菜单图标细节：背景图标颜色与导出图标线宽
- 结论：有差异
- 原版：src/app/editor.js:3095（背景 palette 图标 color=var(--color-purple)）、3052（导出下载图标 strokeWidth 2.2）
- Rust：rust/apps/web/src/editor.rs:3098（palette stroke=var(--color-accent)）、3084（export 图标 stroke_width "2.5"）
- 差异：背景色项图标原版为紫色（与 accent 蓝区分），Rust 统一成 accent 色；导出图标线宽原版 2.2，Rust 2.5（与菜单其他图标齐平）。均为像素级细节。
- 严重度：低
- 证据：proven

### E-8 顶栏入口无障碍标签缺失 + 头像由 button 变 label
- 结论：有差异
- 原版：src/app/editor.js:2475-2477（返回 fab aria-label「返回笔记列表」）、2751-2753（更多 fab aria-label「打开更多菜单」）、2531-2533（头像为 `<button>`，aria-label「更换笔记头像」）
- Rust：rust/apps/web/src/editor.rs:2831-2836（返回 button 无 aria-label）、2837-2907 区间（更多 button 无 aria-label）、2911-2925（头像为 `<label>` 包 input，无 aria-label）
- 差异：三个编辑页主入口在 Rust 均无 aria-label，读屏下只剩无名按钮/标签；头像元素类型由 button 变 label（点击唤起文件选择的功能等价，但键盘可达性/语义不同）。
- 严重度：低
- 证据：proven

### E-9 顶栏 fab 触发事件：onPointerDown 变 onclick
- 结论：有差异
- 原版：src/app/editor.js:2478-2481（返回 onPointerDown + stopPropagation）、2756-2759（更多 onPointerDown + stopPropagation 后 toggleEditorMenu）
- Rust：rust/apps/web/src/editor.rs:2834（返回 onclick: go_back）、2840 起（更多 onclick）
- 差异：原版在 pointerdown 即触发（按下即返回/开菜单），Rust 在 click（抬起后）触发，响应时机晚一个抬手；且原版显式 stopPropagation 防穿透，Rust 无对应处理（靠 DOM 结构规避，未见实证问题）。
- 严重度：低
- 证据：proven（事件名对照）；实际手感差异 inferred

### E-10 图文全文底表（ImageTextSheet）「完成编辑」行为不同 + 编辑生效时机不同
- 结论：有差异
- 原版：src/components/ImageTextSheet.js:122-131（页脚按钮只切换 editing 态，「完成编辑」后底表**保持打开**回阅读态）；src/app/editor.js:828-841（onChange 每键即时写回块并触发自动保存）
- Rust：rust/apps/web/src/editor.rs:3358-3378（「完成编辑」= save_sheet_text 后立即 animate_text_sheet_close 关表）、3340-3355（编辑期只改 sheet_draft 草稿，点遮罩/Esc/完成时才落盘）
- 差异：①原版点「完成编辑」只是退出编辑态、留在底表内继续阅读；Rust 点「完成编辑」直接关闭整个底表。②原版编辑是逐键实时生效（关表无「未保存」状态）；Rust 是草稿制，仅在完成/点遮罩/Esc 三条路径落盘，会话异常终止时草稿丢失的窗口与原版不同。
- 严重度：高
- 证据：proven（两版按钮回调与 onChange 落盘路径对照）

### E-11 图文底表对话框语义与焦点管理缺失
- 结论：有差异
- 原版：src/components/ImageTextSheet.js:36-96、103-121（role=dialog、aria-modal、aria-labelledby、挂载即聚焦 dialog、Tab 焦点陷阱、关闭后焦点还给 triggerElement；textarea 带 placeholder「输入图片说明文字…」与 aria-label「编辑图片说明文字」）
- Rust：rust/apps/web/src/editor.rs:3340-3385（section 无 role/aria-modal/aria-labelledby、无 tabindex、无焦点陷阱与焦点归还；textarea 无 placeholder、无 aria-label）
- 差异：Rust 图文底表只有视觉与 Esc/遮罩关闭（全局 Esc 处理器 editor.rs:1952-1975 覆盖此表），对话框语义、初始焦点、Tab 循环、关闭后焦点归还、输入框 placeholder 全缺。
- 严重度：中
- 证据：proven

### E-12 BgSheet 色点无障碍名缺失与移除图标细节
- 结论：有差异
- 原版：src/components/BgSheet.js:29（每色 button aria-label=冷雾/暖沙/浅绿/浅蓝/浅粉/米橙/淡紫/浅杏）、36-40（移除图标 svg 20px，置于 24px 容器）、30（选中勾 stroke=var(--color-accent)）
- Rust：rust/apps/web/src/editor.rs:3119-3135（bg-dot button 无 aria-label）、3144-3158（移除图标 Icon "del" size 17）、3133（选中勾 svg_markup 硬编码 "#007AFF"）
- 差异：8 个色点在 Rust 无 aria-label（读屏为无名按钮组）；移除背景的垃圾桶图标 20px→17px；选中勾原版用令牌 --color-accent，Rust 写死 #007AFF（浅色下等值，深色/主题令牌变更时不跟随）。
- 严重度：低
- 证据：proven

### E-13 导出文件名截断口径：UTF-16 单元 vs Unicode 字符
- 结论：有差异
- 原版：src/app/editor/export.js:471-474（toFilename 用 JS slice(0, 80)，按 UTF-16 码元截断）
- Rust：rust/apps/web/src/editor/export.rs:1269-1293（export_filename 用 chars().take(80)，按 Unicode 标量截断）
- 差异：含星平面字符（emoji 等，1 字符 = 2 UTF-16 单元）的长标题，两版截断点不同，Rust 文件名可更长。其余口径（非法字符转 _、去尾点/空格、空名回退）一致；调用点均先以「无标题」兜底空标题，最终文件名一致性不受回退值差异影响。
- 严重度：低
- 证据：proven（算法对照）；实际触发需 >80 单位标题，属边缘情形

### E-14 Rust 新增选中块浮动按钮（删除此块/换图/选图），原版无此入口且删除无确认
- 结论：有差异
- 原版：src/app/editor.js 全文 + src/app/editor/*.js 检索无 contextmenu、无长按菜单、无块级浮动操作按钮（块删除靠文本编辑/退格）
- Rust：rust/apps/web/src/editor.rs:5168-5198（BlockDelBtn「删除此块」）、5201-5225（BlockPickBtn 选图）、5228-5257（BlockImgBtn「换图」）
- 差异：Rust 在原子块选中时多出一组原版不存在的操作入口，其中「删除此块」单击即删块并落库、**无确认底表**。原版编辑页内不存在任何块级删除按钮，也不存在删除确认对话框（两版编辑页均无删除确认，此点本身一致；差异在入口新增）。
- 严重度：中
- 证据：proven（原版全文检索无命中 + Rust 组件实存）

### E-15 Esc 关闭范围扩大：原版分层独立，Rust 一次全关
- 结论：有差异
- 原版：src/app/editor.js:243（菜单 Esc 只关菜单）、257-263（导出面板 Esc 只关面板并聚焦 •••，带 preventDefault）、src/components/ImageTextSheet.js:52-57（底表 Esc 只关自身）
- Rust：rust/apps/web/src/editor.rs:1943-1985（单一全局 Esc 处理器：同一次按键依次处理图文底表、导出/菜单、背景底表、链接表单、斜杠面板）；rust/apps/web/src/editor/export.rs:20-37（导出 Tab 陷阱为面板挂载后另装的 JS 监听）
- 差异：原版各浮层 Esc 互斥（谁开着谁响应，一次只关一层）；Rust 一次 Esc 可同时关掉多个层级（如图文底表与背景底表同开时一并关闭），且全局监听未 preventDefault。日常单层场景行为一致，多层叠加时不同。
- 严重度：低
- 证据：proven（处理器结构对照）；多层同开的可达性 inferred

### E-16 HTML/PDF 模型兜底渲染标记与原版 renderBlock 不同构（仅快照缺失时触发）
- 结论：有差异
- 原版：src/app/editor/export.js:175-256（renderBlock：heading 为 div.note-text.note-heading>hN、quote 为 div.note-text>blockquote、todo 为 div.note-todo 带 ✓ span、paragraph 为 div.note-text.note-paragraph 经 Markdown 渲染）
- Rust：rust/apps/web/src/editor/export.rs:865-1032（block_html：heading 裸 hN、quote/callout 裸 blockquote、todo 为与实时 DOM 同构的 todo-row、paragraph 裸 p）
- 差异：两版均以实时 DOM 快照为第一优先（原版 snapshotMarkup / Rust doc_to_html 同口径），仅当快照缺失走模型兜底时标记结构不同，导出文档在编辑器 CSS 下的呈现可能有别。触发条件在两版都罕见（快照采集失败时）。
- 严重度：低
- 证据：proven（两函数逐项对照）；触发频率 inferred

### E-17 Markdown 列表导出：原版存量文本直出 vs Rust 按节点重建编号
- 结论：有差异
- 原版：src/app/editor/export.js:63-110（unordered_list/ordered_list/code_block/callout 均直接返回块存储文本原文）
- Rust：rust/apps/web/src/editor/export.rs:1119-1267（bulleted/numbered 列表经 list_md 按节点重建：有序列表一律从 1 递增重编号、嵌套统一 2 空格缩进）
- 差异：原版 MD 导出保留列表源文本（含原编号、原缩进）；Rust 模型化后重建，有序列表若源编号非连续/非 1 起，导出编号会被改写。段落/代码/标注类 Rust 走 `_ => text` 直出，与原版一致。
- 严重度：低
- 证据：inferred（依据两版算法对照；Rust 模型已无源文本，此为模型差异的必然结果，未做双端同夹具实测）

## 已核一致项清单

1. **顶栏更多菜单外壳**：fixed 右 16、top = 安全区+7+46+6、宽 246、玻璃 overlay、radius 22、内距 7、transform-origin 85% -18px、进场 closing 双 rAF 撤下、出场 opacity 180ms + transform 220ms 弹簧至 translateY(-10px) scale(0.92)、220ms 后卸载、遮罩点击关、滚动关、Esc 关——一致（原版 editor.js:192-252、2771-2806；Rust editor.rs:963-1010、2837-2955、editor.css:1267-1284）。细节差：菜单面板 max-width 原版无、Rust 为 calc(100vw-24px)（editor.css:1275），窄屏才有别，未单列条目。
2. **双栏独立滚动开关行**：文案/副文案/role=switch/aria-checked/columns 图标/开关轨道口径一致；原版该行恒渲染靠 CSS 宽屏才显示，Rust 同走 .editor-column-mode-toggle 媒体规则（editor.css:953-1033）。
3. **菜单分组分隔**：导出项上方分隔线（borderTop 0.5px、padding 10px 0 7px、marginTop 3）两版一致（原版 3028-3032；Rust editor.css:1414 .menu-section）。
4. **导出面板外壳与时序**：菜单先退场 220ms 再挂面板（openExportPanel 时序）、面板同坐标同宽、role=dialog/aria-modal/aria-label「导出笔记」、头部返回钮 46px 圆形 + 居中标题 + paddingRight 46 补偿、返回钮点击关面板后 220ms 重开菜单、选项区独立滚动、进出场 scale 0.94 口径、关后焦点还给 ••• fab、开场聚焦第一个选项、Tab 焦点陷阱、Esc 关、滚动关——一致（原版 editor.js:213-292、3162-3265；Rust editor.rs:175-215 export.rs、1952-1975、2961-3020，panels.css:199-218 度量覆盖）。
5. **导出三格式全集与行为**：Markdown 走语义导出下载 .md（text/markdown;charset=utf-8）、HTML 走快照文档下载 .html、PDF 走 window.open 打印窗（图片全就绪后 120ms 打印、单图等待上限 2500ms）——一致（原版 editor.js:1369-1415；Rust editor.rs:2387-2670、export.rs download_text 同为 a[download] 挂 body 点击 + 1s 后 revoke）。
6. **导出失败文案口径**：PDF 被拦截文案「浏览器阻止了 PDF 导出窗口，请允许弹出窗口后重试。」与原版 addWarn 文案一致（zh-CN export.pdf_blocked）；PDF 失败「PDF 导出失败，请重试。」对应原版「导出失败，请重试。/无法启动 PDF 打印，请重试。」的合并口径。呈现通道差异见 E-1。
7. **导出副标题口径**：`timeAgo(updatedAt) · N字`，N 只数 paragraph 首子文本去换行长度——一致，且 Rust 额外复刻了原版链接卡被 parseEditorDOM 当段落计入的实测口径（export.rs:217-257 export_char_count 及注释）。
8. **MD 语义导出主体**：标题行 `# ` + 特殊字符转义、块间 \n\n、尾部单 \n、heading # 数、quote 逐行 `> `、todo `- [x]/[ ]`、divider `---`、装饰分隔 `---文---`、图片 `![alt](url)`（alt/URL 转义同口径）、图文卡「说明：」后缀、附件图片走图片式/非图片走 `📎 名`、链接/音乐卡 `[label](url)` 且 label 取 meta.title→name→url——一致（原版 export.js:63-145；Rust export.rs:1034-1240）。
9. **HTML 导出文档骨架**：doctype、lang=zh-CN、meta charset/viewport/color-scheme、`<title>` 为标题、主题属性 data-export-theme + 全部 CSS 变量钉在 html style、body 带页面底色、页眉优先真实 chrome 克隆（剥 contenteditable、meta 换导出副行、高度实测且 min 160）、缺失时手工页眉（恐龙兜底 SVG 路径逐字、标题 >5 字用 11px 否则 14px、185px 高）、快照 CSS 全文 + shell CSS、@page 16mm 与 print 规则——一致（原版 export.js:271-520；Rust export.rs:280-747）。Rust shell CSS 另多一条 `.mynote-export-shell math{…}` 公式字体规则，原版无，属增益未单列。
10. **文件名净化主体**：非法字符 `\/:*?"<>|` 与控制字符转 `_`、去尾部点/空格、扩展名 md/html——一致（截断口径差见 E-13）。
11. **BgSheet 本体**：标题「背景色」/副文案「为当前笔记设置底色」、8 色值与顺序逐一相同（#eaeef2/#e8e0d4/#d4e8d0/#d0e0e8/#e8d0d4/#fff3e0/#e8e0f0/#f0e8d0，原版 tokens.js:116；Rust editor.rs:5971-5975）、4 列网格 gap 12、色点 44px 圆、选中 2px accent 边 + 勾、底表 bottom=安全区+14、max-width 600、radius 28、padding 20+安全区、遮罩透明点击关、出场 opacity 200ms + translateY(20px) 250ms 弹簧、220ms 后卸载且**选色/移除在卸载时点才生效**（closeWithAnim(afterClose) 口径，Rust BgAfter::Apply 同构）、有色时才显示「移除背景（恢复默认背景）」危险色行——一致（原版 BgSheet.js 全文；Rust editor.rs:949-1100、3109-3170、editor.css:1311-1329）。差异仅 E-12 的无障碍/图标细节。
12. **编辑页入口可达性**：列表点按备忘打开、列表新建入口、Wiki 链接打开、反向链接条目点击跳转、返回列表（保存后 320ms/280ms 滑出）——入口全集一致（原版 memo-list.js:240-278、471、3271-3284；Rust main.rs:627-630、875-891，list.rs:1131、1211，editor.rs:3265-3300）。新建空笔记返回即删除（未输入/未改背景/未设头像/标题未变四条件）两版一致（原版 editor.js:923-931；Rust editor.rs:2292）。
13. **编辑页内其他入口**：头像点击换图（image/* 文件选择）、标题坞 meta 行（时间 · 字数）、lightbox 点按关闭（rgba(0,0,0,0.88)、z 10000、radius 12 图片）——一致（原版 editor.js:2531、2736-2745、3334-3339；Rust editor.rs:2911-2925、3330-3338、editor.css:1389-1390）。
14. **删除/置顶入口缺如的一致性**：编辑页顶栏菜单内两版均无删除笔记、无置顶、无分享项；编辑页内两版均无删除确认底表/对话框（删除备忘在列表页滑动行，不在本分片范围）。
15. **panels.css 备份段**：Rust panels.css 前 182 行口径与原版备份卡片样式一致（.backup-hero/.backup-card/.backup-row/.backup-btn 等），且按预期移除了原版 .backup-hero-badge/.backup-state 的 connected/disconnected 徽章规则（与谷歌备份入口移除同批事实，不计缺陷）；Rust 另加的 .backup-modal* 确认底表与导出面板修正段属备份页/共享层，不在本分片缺陷范围。
