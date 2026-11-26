# 批 6 余项范围核定（只读核定，未落码）

基线：HEAD `7153f56`（含 c3a1616 批 6 E-1/E-3、7544832 批 5、cfa8265 CI 修复）。核定对象为 landing_plan.md 批 6 表内余项 E-4、E-5、E-6、E-7、E-9、E-13、E-15、E-16、E-17 及附带 E-8、E-12。审计口径出处：audit_parts/part_E.md 各条 + audit_editor_full.md 对应行；现行实证为本轮读码（文件:行号均为基线现值）。

总览：**仍成立 10 条**（E-4、E-5、E-6、E-7、E-8、E-9、E-12、E-13、E-15、E-16），**部分成立 1 条**（E-17），**已消解 0 条**。旁证确认：E-10/E-11 已由批 5（7544832）消解（图文底表现行 editor.rs:3657-3661 有 role/aria-labelledby、:3708 textarea 有 aria-label），不在余项内；E-2 已随 c3a1616 收口；E-14 为用户裁定保留项，不在余项内。

---

## E-4 撤销/重做禁用态 — 仍成立（proven）

- 审计口径（part_E E-4）：原版不禁用（editor.js:2828、2890，onClick 先 closeEditorMenu 再按历史长度守卫；样式仅 opacity 0.3 + cursor:default，无 disabled）；Rust 为 disabled + pointer-events:none，点按无反应、菜单不关。
- 现行实证：editor.rs:3357-3358、3367-3368 仍有 `disabled: !can_undo / !can_redo`（can_undo/can_redo 定义 :2667-2668）；styles/editor.css:1320 `.menu-item.dis { opacity: 0.3; pointer-events: none; }` 原样。有利条件：do_undo/do_redo（editor.rs:2524 起、2545 起）已先调 animate_menu_close 再 step_undo/step_redo，与原版「先关菜单」同序——差异只剩禁用面本身；step_undo 有 idx==0 分支（editor.rs:282-285），落码时复核该分支不改 doc 即可。
- 落码要点：editor.rs 删两处 `disabled:` 属性（保留 `dis` 类作视觉）；editor.css:1320 改为 `.menu-item.dis { opacity: 0.3; cursor: default; }`（去掉 pointer-events:none）。i18n 不涉；Diag 不需新增。验收：探针——无历史时点按撤销项，菜单关闭且文档不变。

## E-5 菜单尾随 › 缺失 — 仍成立（proven）

- 审计口径（part_E E-5）：原版附件/导出/背景三项全有 ›（editor.js:3013-3026、3147-3160，font-19 + --color-placeholder-strong）；Rust 仅导出项有。
- 现行实证：editor.rs:3376-3382 附件 label 无 chevron；:3395-3410 背景 button 无 chevron；导出项 :3392 有 `span { class: "menu-chevron", "›" }`。`.menu-chevron` 样式在 editor.css:1326（--text-secondary / font-18 / opacity .45）——与原版 › 的字面规格（font-19 + --color-placeholder-strong）有细差，但该差对三项一视同仁、且不在 E-5 审计主张内，落码沿用现行类保持菜单内一致，不在本项扩围。
- 落码要点：editor.rs 附件 label 与背景 button 各补一个 `span { class: "menu-chevron", "›" }`（置于 menu-copy 之后，与导出项同构）。i18n 不涉（字面字符）；Diag 不需。验收：DOM 核对三项均有 .menu-chevron。

## E-6 附件菜单关闭时机 — 仍成立（proven）

- 审计口径（part_E E-6）：原版 handleAddAttachment 先 closeEditorMenu 再 fileInput.click()（editor.js:1304-1308）；Rust label 直唤、仅 onchange 才关，取消选择时菜单残留。
- 现行实证：editor.rs:3376 附件 label（`for: "file-attach"`）无任何关闭处理；关菜单只在 #file-attach 的 onchange 内（editor.rs:3599-3613，animate_menu_close 在选文件后才跑）。取消选择不触发 onchange，残留成立。
- 落码要点（推荐低风险路径）：保留 label 原生唤起（不改手势链），给 label 加 onpointerdown 处理先调 animate_menu_close（MenuAfter::None）——pointerdown 先于 label 的 click 激活，选择器弹出时菜单已在退场，取消后无残留；与原版的时序差仅为退场动画与选择器并行（原版 closeEditorMenu 本身也是 220ms 动画，并行同理）。备选路径（改 button + eval 点 #file-attach）在 Dioxus spawn 下有丢 Safari 瞬时激活的风险，不推荐。i18n 不涉；Diag 不需新增（菜单开关已有既有打点）。验收：探针——点附件后取消文件选择，菜单已关（Chromium 口径可验取消路径；真机选择器行为终判在真机）。

## E-7 菜单图标细节 — 仍成立（proven）

- 审计口径（part_E E-7）：背景图标原版 var(--color-purple)（editor.js:3095），Rust 为 accent；导出图标线宽原版 2.2（editor.js:3052），Rust 2.5。
- 现行实证：editor.rs:3404 palette 图标 `stroke: "var(--color-accent)"`；editor.rs:3387 导出图标 `stroke_width: "2.5"`。`--color-purple: #af52de` 令牌现成（styles/tokens.css:80）。
- 落码要点：editor.rs:3404 改 `var(--color-purple)`；:3387 改 stroke_width "2.2"（仅导出图标，菜单其余图标 2.5 与原版同口径不动）。i18n/Diag 不涉。验收：属性核对。

## E-9 fab 触发时机 — 仍成立（proven；手感后果 inferred，同审计）

- 审计口径（part_E E-9）：原版返回/更多 fab 均 onPointerDown + stopPropagation（editor.js:2478-2481、2756-2759）；Rust 为 onclick，晚一个抬手。
- 现行实证：editor.rs:3047-3051 返回 button `onclick: go_back`；:3052 起更多 button `onclick:` 大处理（含菜单状态机），均无 onpointerdown。
- 落码要点：两处改 onpointerdown 并在处理头 stop_propagation（Dioxus 事件对象的 stop_propagation）；onclick 必须同时摘除防双触发。注意更多按钮处理内含 spawn 异步开菜单逻辑，换事件不换逻辑体。单独成笔（交互时序变更，需独立验证）。i18n/Diag 不涉（菜单开关已有打点）。验收：事件核对探针——pointerdown 即触发（不等 pointerup）、且不穿透到下层；冒烟回归菜单开关/返回交接不重复触发。

## E-15 Esc 关闭范围 — 仍成立（proven）

- 审计口径（part_E E-15）：原版各浮层 Esc 互斥、一次关一层，导出面板 Esc 带 preventDefault（editor.js:243、257-263；ImageTextSheet.js:52-57）；Rust 单一全局处理器同次连关多层且未 preventDefault（多层同开可达性 inferred）。
- 现行实证：editor.rs:2087 `__mnEsc` 监听只 send 不 preventDefault；:2090-2123 的处理是串行 if 链——同一次 Esc 依次关图文底表（:2096）、卡片菜单/编辑态（:2101-2106）、导出或菜单（:2107-2113，此对为 else-if）、背景底表（:2114-2116）、链接表单（:2117-2119）、斜杠面板（:2120-2122）。一次按键最多可连关 5 类层。另桥 bridge.rs:813 有 slashClose 的独立 Esc 路径，落码须一并理顺防双处理/穿透。
- 落码要点：把串行链改优先级 else-if 链（优先级沿现行书写序：图文底表 > 卡片菜单 > 卡片编辑态 > 导出面板 > 菜单 > 背景底表 > 链接表单 > 斜杠面板），一次只落一层；`__mnEsc` JS 内对已处理的 Esc 调 e.preventDefault()；与 bridge.rs:813 的 slashClose 路径核对职责（斜杠面板关闭只走一处）。Diag：建议在每层关闭分支沿用既有打点，并可加一行标明本次 Esc 命中的层（便于探针断言），属建议非必需。i18n 不涉。单独成笔。验收：探针——底表+菜单同开时一次 Esc 只关一层、再按一次关下一层。

## E-13 导出文件名截断 — 仍成立（proven）

- 审计口径（part_E E-13）：原版 toFilename 用 JS slice(0, 80) 按 UTF-16 码元截断（export.js:509-511，本轮复核原文无误）；Rust chars().take(80) 按 Unicode 标量，星平面长标题截断点不同（边缘情形）。
- 现行实证：export.rs:1357-1380 export_filename，现行 `.chars().take(80)`（约 :1376）。其余口径（非法字符转 _、去尾点/空格、空名回退「笔记」）与原版一致，未变。
- 落码要点：export.rs 改按 UTF-16 码元累计截断：逐 char 累加 len_utf16，≤80 收、超界停；跨界的星平面字符 JS 会留下孤代理半字，Rust String 无法表示——整字丢弃（文件名实际落盘时孤代理亦会被系统替换，此近似无实际差）。i18n/Diag 不涉。验收：cargo test 单测——构造 emoji 长标题，断言与 JS slice 口径的码元数一致（≤80 码元、边界整字丢弃）。

## E-16 导出模型兜底标记不同构 — 仍成立（proven）

- 审计口径（part_E E-16）：两版均快照优先、仅快照缺失走模型兜底；原版 renderBlock（export.js:175-256）与 Rust block_html 结构不同构（触发罕见，频率 inferred）。
- 现行实证：快照优先结构未变（export.rs doc_to_html :720-728，snapshot_html 有则直用、None 才逐块 block_html）。block_html（export.rs:920 起）差异臂：heading 裸 `<h{lv}>`（:929-932）、quote|callout 裸 `<blockquote>`（:933-935）、todo 为 todo-row 同构结构（:936-947）、paragraph 裸 `<p>`（`_` 臂 :1109-1113）。原版对应（本轮复核 export.js:177-189）：paragraph = `div.note-text.note-paragraph` 包 renderMarkdownBlock(text)；heading = `div.note-text.note-heading` 包 hN（level 钳 1..6、缺省 2）；quote = `div.note-text` 包 blockquote（纯文本转义、\n→`<br>`）；todo = `div.note-text.note-todo[.is-checked]` 包 span.todo-checkbox[.is-checked]（勾选时含 ✓）+ span.todo-text。注：divider 臂 Rust 已是 `<div class="note-text"><hr></div>`，与原版逐字一致，不动。
- 落码要点：export.rs block_html 的 heading/quote/todo/paragraph 四臂改原版结构。两处落码决策点先定：①内容源——原版四臂均走节点纯文本（renderInline/escapeHTML/renderMarkdownBlock），Rust 现行走 inlines_to_html(children)，quote 臂差异最实（原版不带行内标记）；建议按原版逐臂对齐（结构与内容源同为 renderBlock 口径的组成部分）。②callout——原版 switch 无 callout 专臂（落 default），落码前读 export.js renderBlock 的 default 臂定其兜底形态，再决定 Rust callout 是并入 quote 臂还是随 default。i18n/Diag 不涉。验收：构造快照缺失场景（单测直调 doc_to_html 传 snapshot_html=None 的 ExportAssets）比对四臂输出结构与原版字符串口径。

## E-17 MD 列表导出重建 — 部分成立（代码面 proven / 数据面 inferred）

- 审计口径（part_E E-17，审计自评 inferred）：原版 unordered_list/ordered_list 等直接返回块存储文本原文（export.js:63-110）；Rust list_md 按节点重建、有序从 1 重编号、嵌套统一 2 空格；Rust 列表模型未存源文本。
- 现行实证（本轮新增分化）：
  - 重建路径实存（proven）：export.rs:1328-1355 list_md——有序标记 `i + 1` 一律从 1 起、缩进 `"  " × depth`、项内容取 item.plain_text()（行内标记亦随之丢失）；调用点 :1233-1240（bulleted-list/numbered-list 臂）。
  - 但主流存量形态已直出（proven）：段落（含存 MD 源码的列表段）在 block_md_str 走 `_ => text` 原样（export.rs:1322-1324 注释与代码）；且斜杠新建/转换的列表现行就是 MD 源段落、不造列表节点（editor.rs:5870-5872）。原版存量类型名 unordered_list/ordered_list 在 Rust 无类型映射，载入后落 `_ => text` 直出臂，与原版一致。
  - 残余面：真实列表节点（bulleted-list/numbered-list）在模型内实存（渲染 blocks.rs:522；文档变换 editor.rs:214、505、4522、4676、4859、4879；列表类型互换 editor.rs:5799-5810 只改既有列表节点的类型），含此类节点的备忘 MD 导出必经 list_md 重建——编号/缩进/行内标记三处会被改写。节点不存 start 与源文本（全仓 grep `"start"` 无命中）。此类节点在真实数据中的占比未量测（inferred）。
- 落码要点：按 landing_plan 既定——先实测再定改动面。笔 0（量测，非落码）：同夹具双端实测，夹具须含真实列表节点场景（非 1 起编号、嵌套多级缩进、项内含加粗/链接），双端 MD 导出 diff 定残余面的实际影响。实测后二选一：(a) 影响仅及罕见构造 → 以量测证据关单或降为已知差异登记；(b) 影响实存 → 改法候选为导出侧由列表节点回生源文本时保留起始编号（需模型给 numbered-list 存 start，属模型层改动，单独评审）或 list_md 改用节点存量文本（当前无此字段，同属模型层）。在实测结论前不预设模型改动。i18n/Diag 不涉。

## E-8 入口 aria-label + 头像形态（附带） — 仍成立（proven）

- 审计口径（part_E E-8）：原版返回 fab aria-label「返回笔记列表」、更多 fab「打开更多菜单」、头像为 button 且 aria-label「更换笔记头像」（editor.js:2475-2477、2751-2753、2531-2533）；Rust 三入口均无 aria-label，头像为 label（与 A-6 同事分记）。
- 现行实证：editor.rs:3047-3051 返回 button 无 aria-label；:3052 起更多 button 无 aria-label；:3128-3143 头像为 `label.editor-avatar-button` 包 #file-avatar input，无 aria-label。lang 五包无现成键（zh-CN.json 检索无对应项；命名可循既有 export.back_aria 先例）。
- 落码要点：分两部分——(a) 三个 aria-label 直接落：新增 i18n 键 3 个（建议 editor.back_aria / editor.menu_aria / editor.avatar_aria，文案按原版三句）× 五包同改，过 verify 第 7 节；返回/更多 button 直接加 aria_label，头像先给 label 加 aria-label。(b) 头像 label→button 形态复原：需 JS 激活 #file-avatar（eval click），Safari 瞬时激活有风险，单列一笔并以探针验证能唤起选择器为关单条件；验证不过则保留 label + aria-label 作等价收口并登记。Diag 不需新增。

## E-12 BgSheet 细节（附带） — 仍成立（proven）

- 审计口径（part_E E-12）：色点无 aria-label（原版每色 colorNames，BgSheet.js:29）；移除图标原版 20px（置于 24px 容器），Rust 17px；选中勾原版 stroke=var(--color-accent)，Rust 写死 #007AFF（浅色等值）。
- 现行实证：editor.rs:3431-3453 bg-dot button 无 aria-label；:3449 选中勾 `svg_markup("check", 20, "2.5", "#007AFF")` 仍写死；:3467 移除图标 Icon "del" size 17。色名表原版 BgSheet.js:11 colorNames = 冷雾/暖沙/浅绿/浅蓝/浅粉/米橙/淡紫/浅杏；原版 presetColors（tokens.js:116 backgroundColors）与 Rust BG_COLORS（editor.rs:6921-6923）顺序逐值一致（本轮复核 proven），可按下标配对。
- 落码要点：①bg-dot 按下标补 aria-label——新增 i18n 键 8 个（建议 bg.color_0 … bg.color_7）× 五包同改；②:3449 勾的描边改传 "var(--color-accent)"（svg_markup 描边为入参字符串，可直接传 var()）；③:3467 del 图标 size 17 → 20。Diag 不需。验收：属性逐项核对 + verify 第 7 节。

---

## 预估分笔（可直接派发）

| 笔 | 内容 | 文件 | i18n | 备注 |
|---|---|---|---|---|
| 1 | E-4 + E-5 + E-7（菜单行为/视觉组） | editor.rs 菜单段、editor.css:1320 | 无 | 三项同段、同为小改；逐项可验 |
| 2 | E-6（附件关菜单时机） | editor.rs label + onchange 段 | 无 | 推荐 label + onpointerdown 预关路径；探针验取消路径 |
| 3 | E-8(a) + E-12（无障碍组） | editor.rs、lang 五包 | +11 键 ×5 | 过 verify 第 7 节；E-8(b) 头像形态另行单笔待定 |
| 4 | E-9（fab pointerdown 化） | editor.rs 顶栏段 | 无 | 交互时序变更，独立验证防双触发 |
| 5 | E-15（Esc 分层） | editor.rs Esc 段、bridge.rs:813 核对 | 无 | 改 else-if 优先级链 + preventDefault |
| 6 | E-13（文件名 UTF-16 截断） | export.rs | 无 | cargo test 单测关单 |
| 7 | E-16（兜底标记四臂对齐） | export.rs | 无 | 先定内容源与 callout default 两决策点 |
| 0→8 | E-17（先双端同夹具实测，再定关单/模型层笔） | 探针 +（或）export.rs/core | 无 | 实测结论前不预设改动面 |

Diag 总评：本组余项除 E-15 建议顺手加一行 Esc 命中层打点外，均不需新增 Diag（菜单/导出/附件路径已有既有打点覆盖）。
