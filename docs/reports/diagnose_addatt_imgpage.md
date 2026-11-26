# 确诊：更多菜单「添加附件」点按误入图片页（2026-11-24）

用户报告（真机，生产构建 bc55e05687）：编辑器更多菜单点「添加附件」，预期调起系统文件选择，实际导航去了图片页；此前该入口正常。

## 根因（proven：box 事件轨迹实证 + 机制隔离实验）

「添加附件」是编辑器菜单里一个 `<label for="file-attach">`（editor.rs:3510），靠 label 原生唤起链调起隐藏 file input。三段链相遇成病：

1. **手势内启动关菜单**：批 6 E-6（`4867798`）给该 label 加了 `onpointerdown` → `animate_menu_close(MenuAfter::None)`——pointerdown 一落就置 `menu_closing=true`。其意图正当（选择器取消时菜单不残留，对齐原版先关菜单），但启动时机在手势中途。
2. **关闭态摘除命中**：菜单面板 `.editor-menu-panel.is-closing` 的 CSS（浮层动效统一批 `64e6337`）含 `pointer-events: none`——关动画一开始，面板对命中测试即透明。
3. **兼容鼠标事件改道**：pointerdown 的命中对象还是 label 本体，但随后的 mousedown/mouseup/click 按翻转后的样式重新做命中测试，全部改道离开 label。label 收不到自己的 click → 原生唤起行为不发生 → `#file-attach` 的 click 永不触发 → 系统文件选择永不调起（这一半与下方是什么内容无关，恒成立）。改道后的 click 落在当时可命中的最上层元素上：box Chromium 实测落 `.menu-scrim`（被遮罩吞掉）；真机 WebKit 命中穿透到面板下方内容——用户备忘里正压着面板的大照片 img，其 Dioxus onclick（图片页入口）接住这次点按 → 导航进图片页。

引入提交定性：坏掉的是 picker 本身，引入点为 `4867798`（E-6 的 pointerdown 预关）与 `64e6337`（is-closing 的 pointer-events:none）的相遇；任务书嫌疑的两笔 `209f567`/`9c3de9e` 不是病因——它们只新增/保留了图片入口的 onclick（改道 click 的可能落点之一），同一改道在它们之前同样存在（落点会是旧浮层灯箱或被 scrim 吞掉）。今日图片页化（`aad1179`/`26642b1`）把落点副作用从可关浮层放大为整页导航，用户才察觉。

## 实验（box，生产构建 bc55e05687，独立目录/8103，夹具：首块为大图、压在菜单面板下方）

- 实验 1（真实 touchscreen tap 点 label 中心）：轨迹 `pointerdown -> span.menu-title [in-label]`、`pointerup -> span.menu-title [in-label]`，而 `mousedown/mouseup/click -> div.menu-scrim`；`#file-attach` click 计数 0、filechooser 0 次。**复现：picker 不调起。**
- 实验 2（机制隔离）：注入 `.editor-menu-panel.is-closing { pointer-events: auto !important; }` 后同点位 tap：mousedown/mouseup/click 全部回到 label，合成 click 命中 `input.hidden-input`，filechooser 触发。**pointer-events:none 的中途改道为直接成因，proven。**
- 实验 3（对照）：程序化 `label.click()` → input click + filechooser 均正常——label/input 链本身健康；既有探针 probe_pages_editor_rust 正是用程序化 click 测此入口，绕过命中测试，故从未测出本病（量测口径教训：文件唤起类断言必须走真实 tap）。

## 同族排查（全仓文件唤起面逐项核）

| 入口 | 唤起方式 | 手势内预关浮层 | 结论 |
|---|---|---|---|
| 编辑器菜单·添加附件（label for=file-attach） | label 原生链 | **有（onpointerdown 预关）** | **受害，本笔修** |
| 编辑器菜单其余项（双栏/撤销/重做/导出/更换背景色） | button onclick，关菜单在 click 交付后 | 无 | 不受影响 |
| 导出面板选项 | button onclick | 无 | 不受影响 |
| 卡片菜单（编辑/删除两项） | button onclick，scrim 点击才关 | 无 | 不受影响，且无文件动作 |
| 编辑态卡片点图区（桥 cardPick：set/galleryItem/galleryAdd） | 桥 click 内 send op → eval `#file-media`.click() | 无 label、无预关 | 不受影响（程序化唤起为既有形态） |
| 标题坞头像钮 | button onclick → eval `#file-avatar`.click() | 无 | 不受影响（E-8 既有口径，probe_avatar_button 守） |
| 设置页备份导入（label 包 input#file-import） | label 原生链 | 无 onpointerdown、无浮层预关 | 不受影响 |
| 斜杠「图片/画廊」命令 | 只插媒体占位块，不唤起 picker | — | 不受影响 |
| 图文底表 | 无独立 picker 入口（换图走 cardPick） | — | 不受影响 |
| 返回/菜单 fab | onpointerdown 本身即动作（E-9） | — | 设计如此，不依赖 click 交付 |

全仓 `label for=` 仅此一处；程序化 input.click() 仅 file-avatar/file-media 两处，均在 click 完整交付后发起。

## 修法（结构性，落在根因点）

把该 label 的关菜单触发从 `onpointerdown` 挪到 `onclick`：click 先完整交付 label，关菜单在 click 派发内启动；label 的唤起行为随即把合成 click 直接派发到 input 元素本体（不经坐标命中测试），is-closing 的命中摘除再快也够不着它——picker 带手势瞬时激活正常调起；选择器取消（无 onchange）时菜单已在退场，E-6 的目标（不残留）保持。不采用的备选：删 `.is-closing` 的 pointer-events:none——那会改变所有菜单/面板关闭期间的命中行为（关闭中点按本应穿透），病灶在触发时机不在关闭样式，不动它。

探针锁：新增 probe_menu_attach.mjs（门禁）——真实 tap 点 label → filechooser 触发、Diag 有 menu closed、不进图片页；同夹具附件图片行点按仍进图片页（守 209f567 入口不回归）；选文件后新附件行落块（全链）。

## 与 BgSheet 线的关系

本病灶（菜单项 click 交付被改道）与 BgSheet 线的「附件行点按后菜单→更换背景色底表丢失」不同源：更换背景色是 button、关菜单在 onclick 内（MenuAfter::Bg），click 交付完整，不经本改道；两线根因不相遇，互不越界。
