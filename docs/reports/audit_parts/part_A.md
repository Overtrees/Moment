# 分片 A 审计：编辑页骨架与样式体系

## 覆盖声明

实际完整读过的原版文件清单（逐行通读，非抽样）：

- `src/styles/editor-shell.css`（630 行，全读）
- `src/styles/editor.css`（392 行，全读）
- `src/styles/tokens.css`（263 行，全读）
- `src/styles/tokens.js`（126 行，全读）
- `src/styles/base.css`（549 行，全读）

原版 `src/app/editor.js`（3339 行）：页面结构渲染部分完整读（根节点/内层、双 fab、标题坞摆位、editor-spread/editor-body 挂载、反向链接、菜单/导出面板定位段，约 595–675 行背景段与 2455–3339 行渲染段）；行为逻辑部分略读。

Rust 侧对照读：`rust/apps/web/styles/tokens.css`（284 行，全读，与原版做过逐行 diff）、`rust/apps/web/styles/base.css`（663 行，全读）、`rust/apps/web/styles/editor.css`（1427 行，全读）、`rust/apps/web/src/editor.rs` 页面结构/挂载部分（根节点、坞、菜单/导出、正文容器、双栏判定段）、`rust/apps/web/src/main.rs` 页面切换/根背景/动画相关部分（略读）。

标题胶囊内部几何归另一条线，本片只记坞在页面中的摆位。

---

### A-1 默认双栏形态：CSS 多列流 vs 物理双栏网格
- 结论：有差异
- 原版：`src/styles/editor-shell.css`:282-295 `@media (min-width:768px) and (min-height:600px), (min-width:1100px)` 下 `.editor-spread > .editor-body { column-count:2; column-rule:1px solid var(--border-color); column-fill:balance }`，即默认双栏是浏览器多列平衡流，与独立滚动开关无关（开关只切 `is-independent-scroll` 类）；同文件:367-372 后置规则把 `column-gap` 定为 `clamp(28px,3.2vw,52px)` 并设 `line-height:1.72`
- Rust：`rust/apps/web/styles/editor.css`:1095-1113 新增 `.editor-spread > .editor-body.is-flow-columns { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr); gap:clamp(28px,3.2vw,52px); column-count:1 }`，分隔线改用 `background-image:linear-gradient(...)` 居中 1px 线模拟 column-rule；成员由 `rust/apps/web/src/editor.rs`:2730-2745 的 `column_boundary` 估高分界决定，恒渲染左右两个 `.editor-column` 物理容器
- 差异：①分栏机制不同（多列平衡 vs 固定成员网格），块的栏间分布由「浏览器按实测高平衡」变为「代码估高分界」，长文档中具体块落哪一栏可与原版不同；②Rust flow 规则未带原版的 `line-height:1.72` 覆盖，正文行高仍为令牌值 1.75；③分隔线实现不同（column-rule vs 背景渐变线），视觉近似但线只画在容器背景上、高度随容器而非栏内容平衡区。此为用户「左右栏各自独立容器」决策的有意偏离，但与原版 1:1 口径不符，如实记录
- 严重度：高
- 证据：proven（双边代码都读到确切行）

### A-2 双栏下媒体块跨栏（column-span）缺失
- 结论：有差异
- 原版：`src/styles/editor-shell.css`:312-319 `.editor-spread > .editor-body > .atomic[data-type="image"/"gallery"]、.img-text-card、.img-text-row、[data-type="musicCard"] { column-span: all }`，宽屏双栏时这些块横跨整幅
- Rust：`rust/apps/web/styles/editor.css`:1095-1163 flow 网格规则中无任何跨栏等价物（网格子项无法跨越物理栏容器），图片/画廊/图文卡/音乐卡恒留在其所属单栏内、宽度为单栏宽
- 差异：宽屏下大图/图文卡在原版是整幅展示，在 Rust 版被压进半幅单栏，视觉差异显著（Rust 代码注释亦承认此取舍，见 editor.css:1095 段前注释）
- 严重度：高
- 证据：proven

### A-3 编辑页根节点层级形态
- 结论：有差异
- 原版：`src/app/editor.js`:2455-2473 两层结构——外层 div `position:relative; minHeight:100dvh; zIndex:0; backgroundColor:editorBg` 挂进/出场动画，内层 div `position:relative; zIndex:1; minHeight:100dvh; paddingBottom:env(safe-area-inset-bottom)` 承载全部内容
- Rust：`rust/apps/web/src/editor.rs`:2823-2828 单层 `div#editor-root`，style 只有 `background:{effective_bg};{page_anim}`（无 position/min-height/z-index 声明），其下再套 `.detail`（`rust/apps/web/styles/editor.css`:1247 `min-height:100dvh; padding-bottom:env(safe-area-inset-bottom); position:relative`）与 `.editor-pad.editor-spread` 两层
- 差异：层级数与职责划分不同：原版「动画+背景」与「内容」是父子两层，Rust 是「根（背景+动画）→ .detail（高度/安全区）→ .editor-pad（内距）」三层；根节点本身无定位/高度声明，靠 .detail 补足。computed 结果接近，但 DOM 形态与原版不一致，动画 transform 的包含块链也不同（原版动画挂外层、内容在内层同受其变；Rust 动画挂根、内容为其子，效果近似）
- 严重度：中
- 证据：proven

### A-4 正文容器 DOM 形态：单一 contentEditable vs 逐块可编辑包装
- 结论：有差异
- 原版：`src/app/editor.js`:3249-3270 `.editor-body` 本身 `contentEditable:true`（独立滚动模式时改为 false、由两个 `.editor-column[contenteditable=true]` 承担），子节点是原生语义元素（p/h1/ul/pre 等），内联 style 给 `caretColor:var(--text-main); outline:none`
- Rust：`rust/apps/web/src/editor.rs`:3163-3258 `.editor-body` 不是 contentEditable，子节点是逐块包装 div（`.blk-p/.blk-h1/.blk-quote/.todo-row/.md-hit/.blk-wrap`，见 editor.rs:5360-5457 等块渲染），可编辑性在每块的 `.ed-line` 上（`rust/apps/web/styles/editor.css` `.ed-line{outline:none;min-height:1lh}`）
- 差异：DOM 形态根本不同（原生元素直子 vs div 包装层）；连带使原版所有 `.editor-body > p/h1/...` 选择器在 Rust 侧必须逐条改靶到 `.blk-*` 类——Rust editor.css 的 900px 72ch 居中规则（约 :620-650）与独立滚动 72ch 规则已补了 `.blk-p/.blk-h1~h4/.blk-quote/.todo-row/.md-hit`，本片核对范围内补齐，但任何遗漏的选择器都会静默失效，属结构性风险面
- 严重度：中
- 证据：proven

### A-5 右侧 fab 的 z-index
- 结论：有差异
- 原版：`src/app/editor.js`:2743-2752 右 fab（`.editor-fab right`）带内联 `style:{zIndex:3003}`，高于菜单面板 3002 与遮罩 3001；左 fab 无内联、走类规则 3001（`src/styles/editor.css` `.editor-fab{z-index:3001}`）
- Rust：`rust/apps/web/src/editor.rs`:2834-2835 右 fab 无 z-index 内联/覆写，与左 fab 同走 `rust/apps/web/styles/editor.css` 的 `.editor-fab{z-index:3001}`；菜单面板在 Rust 为 3002（editor.css `.editor-menu-panel,.editor-export-panel{z-index:3002}`）
- 差异：右 fab 层级由 3003 降为 3001，低于菜单面板 3002。因面板 top 在 fab 下方 6px、二者几何不重叠，实际不可见，仅层级数值与原版不符
- 严重度：低
- 证据：proven

### A-6 标题坞内头像元素类型
- 结论：有差异
- 原版：`src/app/editor.js`:2530-2547 坞内头像是 `<button class="editor-avatar-button">`（72×72），点击调隐藏 file input 的 click；input 是坞外兄弟节点（editor.js:2735）
- Rust：`rust/apps/web/src/editor.rs`:2910-2928 坞内头像是 `<label class="editor-avatar-button">`，file input（`#file-avatar.hidden-input`）嵌在 label 内部，靠 label 原生关联触发
- 差异：仅坞摆位口径内记录：元素类型 button→label、input 位置不同；尺寸/圆角/玻璃令牌一致（`rust/apps/web/styles/editor.css`:1253 与原版内联逐项同值），摆位（坞 fixed、top=calc(safe+7px)、left/right 62px）一致
- 严重度：低
- 证据：proven

### A-7 运行时令牌注入层（tokens.js）无对应物
- 结论：有差异
- 原版：`src/styles/tokens.js`:1-126 运行时把令牌表挂到 `window.MynoteTokens`，含 `palette.backgroundColors` 8 色与 `fontSizeMap{small:14px,medium:16px,large:19px}`，供 JS 内联样式消费
- Rust：无 MynoteTokens 等价全局；同值被复制为 Rust 常量——背景 8 色为 `rust/apps/web/src/editor.rs`:5972 `BG_COLORS`（与 tokens.js:111 八色逐值相同），字号映射在 `rust/apps/web/src/settings.rs`:13 注释口径下硬编码
- 差异：令牌单一出处被打散为多处常量副本，值目前一致，但原版「改 tokens.js 一处全站生效」的结构不存在，后续改色/字号易漏同步
- 严重度：低
- 证据：proven

### A-8 Rust tokens.css 的增补令牌
- 结论：有差异
- 原版：`src/styles/tokens.css`:1-263 无 `--motion-*` 浮层动效令牌（动效时长散在各组件内联），无诊断令牌
- Rust：`rust/apps/web/styles/tokens.css`:187-200 新增 `--motion-spring/--motion-pop:220ms/--motion-fade:180ms/--motion-sheet:250ms/--motion-sheet-fade:200ms/--motion-slash:140ms/--motion-reorder`，:277-283 新增 `--fs-body/--diag-bg/--diag-fg`；其余全部令牌经逐行 diff 与原版逐值一致（含深色块与 @supports 半透明块）
- 差异：纯增补，不改变任何原有令牌值；动效令牌数值自称取自原版内联口径（菜单 180/220、底表 200/250、斜杠 140），本片核对菜单/底表内联值与之相符
- 严重度：低
- 证据：proven（tokens.css 双边 diff 全量比对）

### A-9 顶部 body::before 渐变的兜底色
- 结论：有差异
- 原版：`src/app/editor.js`:645 滚动渐变取 body computed 背景色，取不到时兜底 `isDark?'0,0,0':'255,255,255'`（浅色纯白）
- Rust：`rust/apps/web/src/editor.rs`:2063 桥内同逻辑兜底为浅色 `'250,250,250'`
- 差异：仅 computed 取不到时的兜底值不同（255 白 vs 250 对应 #FAFAFA 编辑器底）；正常路径两边都用真实 computed 色，此分支几乎不触发
- 严重度：低
- 证据：proven

### A-10 拖拽指示样式体系被替换
- 结论：有差异
- 原版：`src/styles/editor.css`:237-248 `.block{transition:transform .15s,opacity .15s}`、`.block.dragging{opacity:0.4}`、`.drop-indicator{height:3px;background:var(--color-accent);margin:4px 0}`（拖拽中有落点线）
- Rust：`rust/apps/web/styles/editor.css` 保留 `.block` 基础规则但删除 `.drop-indicator` 与 `.block.dragging`，代之以 `.mn-lifted`（玻璃拾起面）+ `.editor-body .mn-shift{transition:transform var(--motion-reorder)}` + `body.mn-drag-active` 锁选区
- 差异：落点指示线在 Rust 版不存在，拖拽反馈形态不同。此为用户 2026-11-22「去拖柄、iOS 桌面式长按拾起」决策的有意偏离，记录备查
- 严重度：低
- 证据：proven

### A-11 图文卡图片的额外裁剪声明
- 结论：有差异
- 原版：`src/styles/editor.css`:80 `.editor-body .img-text-card .itc-img-wrap img { width:100%; height:auto; display:block }`，高度裁剪只靠包裹层 `.itc-img-wrap{max-height:468px; overflow:hidden}`
- Rust：`rust/apps/web/styles/editor.css` 同规则多出 `max-height:468px; object-fit:cover` 直接加在 img 上
- 差异：高图时原版是「自然比例、包裹层裁底部」，Rust 是「图自身限高 + cover 裁剪」，构图取景可不同；常规图无感
- 严重度：低
- 证据：proven

### A-12 菜单面板 will-change 缺失与 .detail.spread 残留规则
- 结论：有差异
- 原版：`src/app/editor.js`:2782-2802 菜单面板内联含 `willChange:"opacity, transform"`；原版无 `.detail` 概念、无对应残留规则
- Rust：`rust/apps/web/styles/editor.css` `.editor-menu-panel` 类规则无 will-change（导出面板靠 editor.rs 内联 transition 串带了 will-change，菜单面板没有）；另 editor.css:1400 有 `.detail.spread .editor-body:not(.is-independent-scroll):not(.is-flow-columns){column-count:2;...}` 一条对当前两种模式都被 :not 排除、实际永不命中的多列残留规则
- 差异：will-change 仅影响合成提示、无视觉差；残留规则为死规则，不生效但与 A-1 的网格路线并存易误导后续维护
- 严重度：低
- 证据：proven

---

## 已核一致项清单

- 令牌全表（浅/深/@supports 半透明三段）：tokens.css 逐行 diff，除 A-8 增补外逐值一致
- 玻璃三层令牌与回退：base.css 的 `@supports not (backdrop-filter)` 与 `prefers-reduced-transparency` 两块双边一致
- body::before 顶部渐变静态层：base.css 双边一致（高度 safe×1.2、白/黑 0.82/0.6/0 三段、z-9999）
- 编辑页背景口径：自定义色优先、深色 ×0.35 压暗、默认浅 #FAFAFA（--color-editor-bg）/深 #000——editor.rs:883-903 effective_bg 与 editor.js:605-606 一致；html/body 背景延伸安全区的机制不同（原版直写 style、Rust 写 --mn-root-bg 变量供 base.css 消费），computed 一致
- 根进/出场动画：slideInFromRight/slideOutToRight 0.28s cubic-bezier(0.22,0.61,0.36,1)，进场 both、出场 forwards，关键帧数值（24px/0.94、16px/0.92）双边一致；Rust 动画结束后显式 `animation:none` 摘除（Dioxus style 保留路径的等价处理）
- 双 fab 几何：46×46、圆、玻璃 control 令牌、left/right 16px、top=calc(safe+7px)（editor.css 双边一致；z-index 差见 A-5）
- 标题坞摆位：fixed、top=calc(env(safe-area-inset-top)+7px)、left/right 各 62px、未滚动态 flex-column/gap 6、滚动态 flex-row/gap 8、transition all 0.25s ease、pointer-events none（editor.js:2511-2529 内联 vs editor.css:1251-1252 类规则逐项一致）
- 正文外距：原版 spread 内联 paddingTop=calc(safe+7+66+4+66+12)=safe+155、左右 16、paddingBottom=calc(safe+32)；Rust .editor-pad `padding:calc(env(safe-area-inset-top)+155px) 16px calc(env(safe-area-inset-bottom)+32px)` 数值一致
- 底安全区双层叠加：原版内层 div paddingBottom=safe 且 spread 再 calc(safe+32)；Rust .detail padding-bottom=safe 且 .editor-pad 再 calc(safe+32)，叠加口径一致
- .editor-spread 宽屏框：max-width 1440、margin auto、width 100%（媒体块双边一致）
- .editor-body 基础：min-height 200px、padding 4px 0、position relative；show-placeholder 文案/位置/opacity 0.45 双边一致（Rust editor.css 照抄 editor-shell.css 该段）
- 正文阅读标尺：font-size var(--md-font-body)、line-height var(--md-line-height) 1.75、h1–h4 字号/字重 750/letter-spacing -0.02em、段距 0.65em、引用/代码/表格/链接全套——editor.css 前段双边逐行一致（单栏部分）
- 独立滚动双栏：高度 calc(100dvh - 187px - safe-top - safe-bottom)、左栏 border-right + padding-right 16、右栏 padding-left 16、栏内 overflow-y auto/overscroll contain/scrollbar-gutter stable——editor-shell.css:538-575 与 Rust editor.css 对应段一致
- 独立滚动开关行：.editor-column-mode-toggle 全套（display:none !important 基础态、宽屏 flex、开关 42×26/钮 20/行程 16 令牌）双边一致
- 宽屏 72ch 居中（≥900px）：原版元素靶与 Rust 补的 .blk-* 靶（见 A-4）合起来覆盖段落/标题/引用/列表/代码/表格/待办/md 预览，width min(100%,72ch) margin auto 一致
- 菜单/导出面板定位：fixed、right 16、top=calc(safe+7+46+6)、width 246、radius 22、玻璃 overlay、transform-origin 85% -18px、进出场 opacity 180ms + transform 220ms 弹簧、关闭终态 translateY(-10px) scale(0.92)（导出面板 scale 0.94）双边一致（will-change 差见 A-12）
- 斜杠面板与 slash-row 全套度量：editor-shell.css 该段被 Rust editor.css 照抄，行高 48、radius 14、字重 650 等一致
- image-text-sheet 全套：wrap bottom=calc(var(--safe-bottom)+14px)、sheet max-width 600/radius 28/玻璃 overlay、进出场 opacity 200ms + transform 250ms 弹簧双边一致（Rust 另补了 backdrop 的 fixed 定位基线，原版靠内联 fixedOverlay，computed 一致）
- 反向链接区：.wiki-backlinks width min(100%,720px)、margin 24px auto 0、border-top——双边一致，且两边都挂在正文容器（spread/pad）之外、根内层之下，摆位一致
- 深色模式切换机制：两边都监听 matchMedia change 重算背景；Rust 另有 scheme_tick 重挂玻璃胶囊的根治（base.css 注释），属列表页范畴本片不展开
- 安全区取值方式：全部 env(safe-area-inset-*) 运行时取值，无写死设备数值，双边一致
- prefers-reduced-motion 全局熔断与 --motion-page-transition:280ms：base.css 尾段双边一致
