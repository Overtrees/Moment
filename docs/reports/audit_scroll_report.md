# Mynote Rust Web 版「滚动监听」全面审计报告

审计时间：2026-11-21。只读审计，未改任何应用代码。
方法：原版（`src/app/memo-list.js`、`src/app/editor.js`、`src/app/editor/use-slash.js`、`src/app/editor/use-editor-dom.js`、`src/styles/*.css`）与 Rust 版（`rust/apps/web/src/main.rs`、`list.rs`、`editor.rs` 含 EDITOR_JS 桥、`styles/*.css`）源码通读对照 + 无头双边探针实证（同一 fixture、同一视口）。
探针环境：Rust = `serve_headers.py dist 8098`，原版 = `python3 -m http.server 8099`（入口 `/Moment.html`）；视口 393×852 hasTouch（双栏用 1280×800）；fixture = `/tmp/scroll_test.zip`（13 篇：置顶长文 30 段 + 12 篇列表备忘，两边导入同一 zip）。探针脚本：仓库根 `probe_scroll.mjs`（列表/编辑器主探针）、`probe_scroll2.mjs`（原版选择器修正）、`probe_scroll3.mjs`（原版恢复/菜单/斜杠）、`probe_scroll4.mjs`（双栏）。

## 结论概览

| # | 项 | 严重度 | 一句话 |
|---|----|--------|--------|
| S1 | 列表滚动位置保存/恢复 | **高** | Rust 全仓零 `scrollTo`：开编辑器不回顶、返回不恢复 |
| S2 | 编辑器菜单/导出面板滚动关闭 | 中 | 原版滚动即关；Rust 菜单滚动后仍开着且 scrim 拦截后续点击 |
| S3 | 斜杠面板滚动跟随 | 中 | 原版滚动时按选区重定位；Rust 面板钉在打开时坐标，与光标脱节 |
| S4 | ed_scroll 监听泄漏 | 中 | 每打开一次编辑器净 +1 个 window scroll 监听，永不移除（实测 3→5） |
| S5 | 列表滚动监听节流/作用域 | 中 | 原版 rAF 节流且随列表卸载；Rust 无节流、App 级常驻、所有页面滚动都触发 App 重渲染 |
| S6 | 标题光标横向跟随滚动 | 中 | 原版 selectionchange/visualViewport 驱动光标保活在胶囊可视区；Rust 无等价实现 |
| S7 | 标题编辑期 scrolled 翻转抑制 | 低-中 | 原版编辑标题期间不响应滚动翻转；Rust 无守卫 |
| S8 | 编辑器失焦回顶行为 | 低-中 | 原版键盘收起时 scrollTo(0,0) 并强制未滚动态（含重试）；Rust 无（真机行为，无头不可验） |
| S9 | 诊断页内滚穿透 | 低 | Rust `.diag-body` 内滚无 overscroll-behavior，滚尽带动页面（Rust 独有页，原版无对应） |

已对齐 9 项（见文末），含标题联动公式、紧凑阈值、标题坞三档、背景渐变、双栏独立滚动等，均有实测同值证据。

---

## S1（高）列表滚动位置保存/恢复整体缺失

- 原版证据：`src/app/memo-list.js:240-246` `openEditor` 先存 `scrollRestoreRef.current = window.scrollY` 再 `window.scrollTo(0, 0)`；`:247-258` `closeEditor` 用双 rAF `window.scrollTo(0, savedScroll)` 恢复（savedScroll>0 时）。
- Rust 证据：`grep scrollTo rust/apps/web/src/` **零命中**。列表打开编辑器只是 `main.rs:480` `selected.set(Some(mid))`，Editor 的 `go_back`（editor.rs:1580/1620 `on_close.call`）只落盘+回调，无任何滚动处理。
- 实测（fixture 列表总高 1012，最大 scrollY=160）：
  - 原版：列表滚至 160 → 打开长文 **editorY=0** → 返回 **backY=160**（分毫不差）。
  - Rust：列表滚至 160（指令 400 被钳到最大值）→ 打开长文 **editorY=160**（原样继承列表滚动位置，标题坞一打开就是紧凑态、首块不在视口顶）→ 在编辑器里继续滚动后返回，列表位置取决于编辑器最终滚动量被列表高度钳制的结果，用户原来的列表位置丢失。
- 复现：probe_scroll.mjs 的 L3 段（两边同流程）。

## S2（中）编辑器 ••• 菜单 / 导出面板：滚动不关闭

- 原版证据：`src/app/editor.js:241-252` 菜单打开期间注册 window scroll（passive）→ `closeEditorMenu()`，卸载时移除；`:255-292` 导出面板同理（scroll → closeExportPanel）。
- Rust 证据：`menu_open` 只被点击类处理改动（editor.rs 内 9 处 `menu_open.set(false)` 均为点击/scrim/动作回调），无任何滚动联动；导出面板 `show_export` 同理。
- 实测：Rust 打开菜单后滚动 200px，菜单仍在（`menuAfter=true`），且 `.menu-scrim` 拦截后续对返回键的点击（探针首轮即因此超时）；原版同流程菜单打开=true、滚动 200 后=false。
- 复现：probe_scroll.mjs E3（Rust）/ probe_scroll3.mjs E3（原版，注意原版 fab 是 onPointerDown 触发，须用真实点击）。

## S3（中）斜杠面板：滚动时不跟随重定位

- 原版证据：`src/app/editor/use-slash.js:660-697` 面板打开期间监听 window scroll + visualViewport scroll/resize + selectionchange，统一走 rAF 节流的 `updateSlashStateFromSelection()` 按当前选区重算面板位置；卸载全量移除。
- Rust 证据：`SlashPanel` 的锚点是打开瞬间由桥消息带入的 props（editor.rs:2355 `anchor_x/anchor_top/anchor_bottom`，组件内 editor.rs:3583-3616 只用这组冻结值算 left/top），滚动后无任何更新通道。
- 实测：聚焦首块输入 `/` 开面板后滚动 200px——Rust 面板 top **253 → 253（纹丝不动）**，而其锚定的块已滚走 200px；原版 top **564 → 2487**（重定位逻辑确实被滚动触发并重算了位置；该无头场景下重算结果把面板推到视口外，等效于不再压住光标，但「有重定位通道」与 Rust「无通道」是本质区别）。
- 复现：probe_scroll.mjs E4（Rust）/ probe_scroll3.mjs E4（原版）。

## S4（中）编辑器 ed_scroll 监听每次挂载泄漏一个

- 原版证据：编辑器两处 scroll 监听都有 cleanup——`src/app/editor.js:1009-1025`（scrolled 态，removeEventListener）、`:665-671`（背景渐变，移除监听+删 style 元素）。
- Rust 证据：标题坞滚动订阅在 editor.rs:1356-1366 用 `document::eval` 注册 `window.addEventListener('scroll', f, {passive:true})`，JS 侧 `f` 无任何移除路径（不像背景渐变那段有 `window.__mnBgCleanup` 且 editor.rs:1430 有 `use_drop` 兜底清理）。eval 的 Rust 侧 future 随组件卸载取消，但已注册的 JS 监听只会继续往失效通道 `dioxus.send` 发数。
- 实测（探针以 addInitScript 包裹 add/removeEventListener 统计 window+document 的 scroll 监听净值）：Rust 首次进编辑器=3、回列表=3、再进出 2 个周期后=**5**（每周期净 +1，与 ed_scroll 监听一一对应）；原版编辑器=3、回列表=3，无增长。
- 复现：probe_scroll.mjs E5。

## S5（中）列表滚动监听：无 rAF 节流 + App 级常驻全页触发

- 原版证据：`src/app/memo-list.js:190-211` 列表监听用 `rafRef` 合并到每帧最多一次 `setScrollY`，且是 passive；组件卸载时 removeEventListener + clearTimeout + cancelAnimationFrame。编辑器/设置页不背这个监听。
- Rust 证据：`main.rs:168-182` 监听注册在 **App 根组件**的 `use_effect` 里（App 永不卸载），回调对每个 scroll 事件直接 `dioxus.send(window.scrollY)` 跨桥回 Rust，仅以 0.5px 差值去重，无 rAF 合并；而 `scroll_y` 在 App 渲染体中被无条件读取（main.rs:275），意味着**在编辑器、设置、备份、诊断任一页滚动，都会以滚动事件频率触发整个 App（含 Editor 子树）重渲染**——编辑页还叠加 editor.rs:1356 自己的 ed_scroll 订阅，双通道同频触发。
- 影响定级：无头环境下功能数值不受影响（L1/L2/L4 实测均对齐，见已对齐项），定中：长文编辑滚动时每帧多次跨桥+全树重渲染，是真机滚动帧率的风险项，且与 S4 同源（监听治理缺失）。
- 复现：代码证据即足；帧率量化需真机，不在无头范围。

## S6（中）标题编辑：光标横向跟随滚动缺失

- 原版证据：`src/app/editor.js:1028-1122` —— `scheduleTitleCaretSync`（双 rAF）在标题编辑期间由 `selectionchange`、window resize、**visualViewport resize/scroll** 驱动，把光标保持在标题横滚容器内 16px 边距内（`container.scrollLeft` 双向校正）；配套的 `syncTitleCompositionLayout`（:678-702）处理溢出态容器宽度/内边距。
- Rust 证据：桥内有 `syncTitleLayout` 等价物（editor.rs:184-195，只调 scroller 宽/padding），也有标题置入/复位时 `scrollLeft = 0`（editor.rs:974、1001）；但桥的 `selectionchange` 监听（editor.rs:402-409）只服务正文 savedRange，**没有任何按光标位置校正标题 scroller 的逻辑**，也无 visualViewport 监听（全仓仅 main.rs:60 的 SAFE 探针读过 visualViewport.height）。
- 影响：长标题（溢出态）在胶囊内编辑、光标移到可视区外时不自动跟随；iOS 键盘弹出引起 visualViewport 变化时同样不校正。无头可验性：可聚焦标题、置光标于长标题末尾、断言 scroller.scrollLeft 变化——本轮未做该探针（标题溢出态构造需 11+ 字标题且进入编辑态），以代码证据定级。

## S7（低-中）标题编辑期间 scrolled 翻转无抑制

- 原版证据：`src/app/editor.js:1013-1019` rAF 回调里先查 `isEditingTitleRef.current`，编辑标题期间直接跳过 `setEditorScrolled`——注释写明原因：防止点击胶囊时页面回弹触发竖排（row/column）切换。editorScrolled 驱动胶囊布局方向（:2522 flexDirection、:2717 条件渲染）。
- Rust 证据：ed_scroll 订阅（editor.rs:1356-1366）与 `scrolled` 派生（editor.rs:1906 `*ed_scroll.read() > 30.0`）无任何「标题编辑中」守卫；标题编辑态信号（title_editing）存在但未参与该判断。
- 影响：真机上编辑标题时若发生滚动回弹，胶囊会在编辑中途切换横竖布局。无头不可复现（需 iOS 回弹），代码证据定级。

## S8（低-中）编辑器失焦（键盘收起）回顶 + 强制未滚动态缺失

- 原版证据：`src/app/editor/use-editor-dom.js:425-450` 正文失焦且焦点不在编辑器/标题坞内时：`window.scrollTo(0, 0)`，并以 80ms×6 次重试调 `setEditorScrolled(false)`（注释：iOS 可能异步恢复滚动位置）。
- Rust 证据：桥与 Editor 均无失焦回顶逻辑（全仓 scrollTo 零命中，见 S1）。
- 影响：真机从编辑态收起键盘后，原版回到顶部未滚动布局；Rust 停留在当前滚动位置与紧凑坞态。属真机交互行为，无头不可验，代码证据定级。

## S9（低）诊断页日志区内滚穿透

- Rust 证据：`styles/panels.css:212` `.diag-body { max-height: 52vh; overflow-y: auto; }` 无 `overscroll-behavior`；滚到日志尽头继续滚会链式带动背后的设置/诊断页（窗口滚动）。对照：同仓 `.slash-panel`（editor.css:458）与双栏列（editor.css:955）都有 contain，只有 diag-body 与备份底表类容器没给。
- 原版对照：诊断页是 Rust 版按项目规矩新增的页面，原版无对应物，故此项记为 Rust 自身一致性问题，非 1:1 偏差。

---

## 已对齐项（附证据）

1. **列表标题联动公式**：原版 memo-list.js:213-217（progress=clamp(scrollY/30)，scale=1−0.45p，ty=−4p，opacity=1−0.3p）与 Rust main.rs:275-279 逐项同式。实测 @scrollY=15 两边 h1 计算样式**同值**：transform matrix(0.775, 0, 0, 0.775, 0, −1.55)、opacity 0.85（−1.55 而非 −2 是两边同有的 CSS 过渡中途值，非实现差异）。
2. **紧凑头翻转阈值**：两边实测 @29 紧凑胶囊 hidden/opacity 0、@31 visible/1（progress≥1 即 scrollY≥30 翻转），一致。
3. **搜索/新建卡显隐联动**：@60（紧凑态）两边搜索触发器 opacity 均为 0、新建卡均为 1，与原版 memo-list.js:548/602 的 isCompact 口径一致。
4. **`.page-title.scrolling` 类**：原版 memo-list.js:197-201 会在滚动时给标题加 `scrolling` 类、停滚 200ms 后移除，但原版 CSS 中该规则是**空规则**（src/styles/base.css:90-92 `.page-title.scrolling {}`），无任何视觉效果；Rust 未实现该类，等效对齐（仅记录，不算差异）。
5. **编辑页标题坞三档**：firstBlockTop 实测两边同值——scrollY 0→**159**、15→**144**、60→**99**；标题坞高度两边同为未滚 144 → 滚动（>30）72。阈值同为 30（原版 editor.js:1010/1018，Rust editor.rs:1906）。坞随页面流上移、过阈值切紧凑形态的模型一致。
6. **body::before 背景渐变**：公式与产物逐字一致——实测 @15 两边 style 文本均为 `rgba(250,250,250,0.41) 0%, rgba(250,250,250,0.3) 50%, rgba(250,250,250,0) 100%`，@45 均为 0.82/0.6（原版 editor.js:638-672 的 alpha=scrollY/30、×0.82/×0.6 双站渐变；Rust editor.rs:1370-1407 同构移植，含 rAF 节流）。清理也对齐：原版卸载移除监听+style 元素（:665-671），Rust 有 `use_drop` 调用 `__mnBgCleanup` 并复位 html/body 背景（editor.rs:1430-1433）。`body::before` 基础规则两边同在 base.css:18/33。
7. **双栏独立滚动**：1280×800 实测两边同值——左列 scrollTop 设 200 后保持 200、右列 0、window.scrollY 0；左列 clientHeight 两边同为 613。Rust 切篇后两列归零（0/0）——原版编辑器按篇重挂同理归零。支撑 CSS 已对齐移植：列 `overflow-y:auto; overscroll-behavior-y:contain; -webkit-overflow-scrolling:touch`（原版 editor-shell.css:551-553 ↔ Rust editor.css:954-956），窄屏列 `display:contents` 退化（原版 editor-shell.css:444 ↔ Rust editor.css:847）。
8. **overscroll / 动量滚动 CSS 移植面**：代码块 `pre` 的 overscroll-behavior-x:contain（原版 editor.css:62 ↔ Rust editor.css:62）、斜杠面板 overscroll-behavior:contain（原版 editor-shell.css:55 ↔ Rust editor.css:458）、图文底表 `-webkit-overflow-scrolling:touch`（原版 editor-shell.css:124 ↔ Rust editor.css:527）均逐项在位；两边 body/html 均未设全局 overscroll-behavior（橡皮筋行为同为浏览器默认）。
9. **滚动模型同构**：两边正文（含 md 源码编辑态）都是单一窗口流滚动，无嵌套正文滚动容器；双栏模式下两边都只认 window 滚动驱动坞/渐变（列滚动不触发 window.scrollY，两边实测 winY 恒 0），行为一致。编辑器桥不拦截 wheel/scroll，两边同。

## 附带观察（非滚动监听本体，记录供并入其他队列）

- **双栏分栏成员分布不同**：同一篇 30 段长文，原版左列 scrollHeight=853、Rust=1075（probe_scroll4），即 `column_boundary` 的分栏点与原版 `normalizeColumnLayout`/权重平衡结果不一致。属布局分布问题，建议并入双栏/布局队列核对，非滚动监听缺陷。
- **双栏开关后菜单去留**：Rust 在菜单内点 `.twopane-row` 后菜单保持打开（探针实测 scrim 仍在）；原版开关行同在菜单面板内，本轮未单独验证其点后去留，不下结论。
- **块拖拽排序的边缘自动滚动**：原版 editor.js:2444-2450 拖拽块到视口上下 80px 内时 `window.scrollBy(0, ±10)` 自动滚动；Rust 无块拖拽排序功能本体（editor.rs 内 dragstart/draggable/dragover 零命中），该自动滚动随功能本体一并缺失，应随拖拽功能在编辑功能队列处理。

## 修复优先级建议

S1（列表位置保存/恢复）→ S4+S5（监听治理：ed_scroll 加清理、列表监听 rAF 化并收回列表页作用域）→ S2+S3（菜单/导出/斜杠的滚动联动）→ S6（标题光标跟随）→ S7/S8（真机联动守卫）→ S9（overscroll 补齐）。
