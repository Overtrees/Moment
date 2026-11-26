# 审计线 B：标题胶囊输入态专项排查（第二代控制器）

审计时间：2026-11-26。方法：代码层面逐行排查（用户明示实在测不出从代码层面查）。范围：原版归档实现、Rust Web（title_controller.rs / title.rs / editor.js 桥 / hooks/scroll.rs / styles/editor.css）、原生 iOS（MomentApp.swift TitleDock 段）。定性分三档：**proven**（代码路径确证）/ **inferred**（机制存在、是否触发取决于平台时序或设备性能）/ **已排除**（代码确证不会发生）。

注：本文件覆盖同名旧报告（2026-11-22，对象为上一代 contenteditable + scroller + 弹簧几何机器，已整代退役）；旧报告结论对现行代码不再适用。

## 0. 原版意图与现行口径（先明意图再判差异）

- 原版（归档 `src/app/editor.js`）：标题是 **contenteditable div** + 外层 scroller，自带一整套几何机器——`scheduleTitleCaretSync`（双 rAF 量光标矩形、写 scroller.scrollLeft，editor.js:1027-1092）、`syncTitleLayout`（长文本字号 14→11px、溢出左对齐、caret gutter 内距，editor.js:~660-709）、编辑期冻结布局快照防光标重置（onFocus/onInput，editor.js:2613-2682）、滚动监听在编辑标题期间直接 return 不翻转坞态（editor.js:1013-1019）。
- Rust Web 已按用户 2026-11-23 裁定**整体换代**：原生 `<input type="text">` + TitleController 独占会话（title_controller.rs 模块注 :1-61），旧几何机器整段删除、我方对 input 的 scrollLeft 写入归零、字号恒 14、居中为构造性质。此换代是用户规格（标题胶囊豁免原版对齐），**不作缺陷计**；下文只查换代后实现自身的正确性与残留风险。
- Esc 还原是 Rust 代规格新增（原版 onKeyDown 只有 Enter、无 Esc，editor.js:2690 段）；截断显示「前 10 字 + …」三代一致，但**计数基不同**：原版 JS `.length`（UTF-16 单位）、Rust `chars().count()`（Unicode 标量）、原生 Swift `String.count`（字素簇）——含 astral 字符（emoji 等）的标题截断点三端不一致（见 B-6）。

## (a) 快速连续输入长文本：丢字 / 跳字 / 回滚 / 打断组字

### Web（Rust）

- **已排除：受控值回写覆盖输入中文本。** 标题 input 的 value 绝不进 vnode（title.rs:5-14 模块注 + TitleCapsule 壳只渲染结构与静态属性，title.rs:78-107）；逐键 `input` 事件在控制器内只做两件事：组字期置 `comp_reflected` 标记、非组字期 `sync_width()` 定宽（title_controller.rs:832-846）。Editing 路径上**没有任何一处写 input.value**（写值只发生在 on_focus 换全文、on_blur 回展示值、Esc 还原、detach 兜底四处，均不在逐键路径）。平台先把字符落进 input、事件后到，处理器不回写 ⇒ 丢字/回滚在构造上不存在。
- **已排除：框架重渲染打断组字。** 标题子树挂载后退出 VDOM 托管；meta 文案节点是框架唯一可写点，MutationObserver 守卫对其子树豁免（title_controller.rs:1076-1082 guard_record）；on_commit 置标题信号 + persist（bridge_wire.rs:105-113）不触标题 DOM。
- **inferred（性能，非正确性）：逐键同步强制布局 2 次以上。** 每次 `input` / `compositionupdate` 都走 sync_width → measure_text（写镜像 textContent + 读 rect，:187-194）+ avail_width（临时摘坞 transition、读 rect 强制回流、遍历坞子节点逐个读 rect，:412-470）+ 多次 getComputedStyle。快速连打（尤其拼音 compositionupdate 高频）时每键数次同步布局，低端机可能出现输入延迟感；但事件不丢、值不回滚，**只影响跟手感、不影响正确性**。严重度：低。
- **inferred（仅宽度，极低）：live_text 拼接依赖平台事件时序。** 组字期实时全文靠 comp_range + comp_data + comp_reflected 拼接（:286-308）；若某平台 input 事件先于 compositionupdate 到达且 value 已含新组字串，skip 段按旧 comp_data 长度计算会短暂拼错——**只影响镜像量宽（胶囊宽度瞬时偏差），不影响文本本身**，下一事件即自愈。严重度：极低。
- **已排除：防抖合并丢键。** 标题路径无防抖；persist 只在 compend/blur/Enter 触发（commit_raw :589-598、on_blur :639-676），逐键不落盘是设计（与原版 commitTitleFromDOM 时机一致）。

### 原生 iOS

- **已排除：文本被回写打断。** TextField 绑定 ui.titleDraft（MomentApp.swift:4551-4557），setter 只存草稿；SwiftUI 不会把绑定值反写回 UITextField（get 返回的正是字段刚产生的新值），拼音组字走 UITextField 平台文本系统，无 marked 区间被打断的代码路径。
- **inferred（性能）：逐键全 EditorView body 重演算。** titleDraft 是 EditorUI 的 @Published（:4148），每键发布 → EditorView 整棵 body 重新求值，其中 capsuleWidth 每键做两次 NSString 尺寸实测（:4583-4601），且 `.animation(value: ui.titleDraft)` 每键重定向 0.2s 宽动画（:4579-4580）。大视图树下快速连打可能掉帧/宽度动画滞后于文本（胶囊短暂窄于全文、居中文本被平台内滚顶住），但不丢字。严重度：低（跟手感）。

## (b) 光标表现：落焦 / 同步 / 截断落点映射

### Web（Rust）

- 落位时机：on_focus 换值或有点按记号时才用 rAF 延后一帧 set_selection_range（place_caret_next_frame，:753-773），帧内复查 is_connected 与 activeElement——快速点开又点走不会被迟到落点抢焦，**已排除**迟到重定位。
- **inferred（极低）：首帧光标闪跳。** on_focus 先 set_value(全文)（:610-614），平台随即把选区置于平台默认位（通常起点），rAF 后才移到文末/映射位——中间一帧光标可能在起点闪现。单帧量级，真机未必可辨。严重度：极低。
- **inferred（极低）：rAF 与首键竞态。** 落焦后一帧内用户已先打字，rAF 仍按计划落点：无记号时落「帧时全文末尾」（含刚打的字）无害；有点按记号时光标会被拉回映射位，后续字符插在映射位——窗口仅一帧且需点按后立即盲打，实际近乎不可达。严重度：极低。
- 截断落点映射（tap_caret_target，:228-278）边界逐项核对**正确**：
  - 仅截断形态介入（全文 >10 字且当前值恰为「10 字 + …」共 11 字、前缀与全文一致），未截断时返回 None 不干预原生落点；
  - 显示串居中偏移按镜像实测宽 `(rect.width − disp_w)/2` 换算（:254-256），逐前缀实测找最近字符边界（:263-275），落在省略号上/之后（best ≥ 11）→ 全文末尾，落在第 10 字后（best == 10）→ 全文第 10 字位，与用户 2026-11-22 拍板口径一致；
  - char 位 → UTF-16 单位由 utf16_of_char 换算（:205-208），astral 字符不串位；
  - 记号 2000ms 过期作废（:625-633），编辑中点按不捕获记号（pointerdown 监听 :848-857 仅 Idle 捕获），键盘/程序聚焦无记号且未换值时不干预原生落点。
- **proven（命中面，非光标逻辑）：胶囊上下内距区点按不落焦。** pointerdown 记号与 focus 都只来自 input 元素本身；input 为块级、宽 = 胶囊内容盒，但高仅行高（14px × 1.3 ≈ 18px，editor.css:1203），胶囊高 66px（editor.css:1198）、meta 行 pointer-events:none（editor.css:1213）——点在胶囊上/下留白区既不聚焦也不记落点，事件落在胶囊 div 上无任何转发聚焦的代码（全仓 grep 无 capsule 点击聚焦接线）。与原版对比：原版 contenteditable 元素同样只是文本行高，原版亦无此转发——**与原版同形态、不算回归**，但作为现行可感知的命中面事实记录。严重度：低（可用性）。

### 原生 iOS

- **proven：长标题点按落点映射未实现（与 Web 口径分叉）。** 未聚焦且 >10 字时渲染的是截断 Text（:4564-4569），点按仅置 titleFocused = true；TextField 出现后光标落位完全交 UIKit 程序化聚焦默认（通常文末），无 x 坐标 → 字符位换算的任何代码。Web 的「点哪落哪（省略号后落文末）」调优在原生缺失。严重度：中低（行为等价红线下属未对齐项，非故障）。
- **proven：聚焦瞬间胶囊宽度突跳、无过渡。** capsuleWidth 的 shown 在 titleFocused 翻转时于「截断串 ↔ 全文」之间切换（:4585-4589），而宽度动画只绑定 ui.titleDraft（:4579-4580）——聚焦动作本身不改草稿 ⇒ 宽度从截断宽直跳全文宽（或钳后宽）无动画；Web 两态同公式且 width 带 0.2s CSS transition（editor.css:1198），聚焦换宽是平滑跟随。严重度：低（视觉）。
- **proven：胶囊最大宽按整屏算，大屏/分屏错位。** maxW = `UIScreen.main.bounds.width − 124`（:4598），−124 是手机坞左右 62+62 的镜像值；iPad 双栏/横屏/分屏下坞并非整屏宽，胶囊可超出实际可用宽（被父容器裁/挤）或在宽屏下限得过窄。与「安全区/尺寸动态适配、禁写死设备数值」红线相抵。严重度：中（iPad 双栏场景，即用户本轮第 6/7 项语境）。

## (c) 编辑态空格键长按左右滑动（iOS 键盘 trackpad 模式）控制光标

### Web（Rust）——逐项排除

- **光标被同步逻辑抢回：已排除。** TitleController 全文**没有 selectionchange 监听**（监听集只有 focus/blur/composition*/input/pointerdown/keydown + visualViewport/window resize，:812-920）；空格滑动只移动 input 内部选区，不产生 input/composition 事件 ⇒ 无任何我方代码在滑动期间写选区。
- **桥侧 selectionchange 三监听均不触标题：已排除。** editor.js:744 的跨块选区守卫先判 `!xsel` 直接 return，且 window.getSelection() 本就不反映 input 内选区；editor.js:1838 的 savedRange 仅当 range 起点在编辑器 root 内才存，标题 input 不在其内；editor.js:2889 的斜杠跟随在斜杠面板未开时为空转，且标题聚焦与斜杠面板不共存。
- **被误判为页面滚动收起（坞翻转）：已排除。** 两层防线：①空格滑动是键盘内部手势，不产生 window scroll；②即便编辑期间页面真滚动，hooks/scroll.rs:40-52（S7）在 title_editing 为真时**丢弃滚动值不翻转 .scrolled**（与原版 editor.js:1013-1019 同口径），会话结束由 bridge_wire.rs:118-140 按当刻 scrollY 重播归位；控制器侧 on_dock_flip 也只重定宽、不碰选区/值（:574-582）。
- **胶囊宽度抖动：已排除。** sync_width 的全部触发源（input/composition/focus/blur/dockflip/viewport resize）无一由选区移动触发；空格滑动期间文本不变，宽度恒定。visualViewport resize 仅在键盘框架变化时触发，trackpad 模式不改键盘框架。
- 残留注记：iOS trackpad 滑动到文本边界时可能伴随页面级橡皮筋滚动——即便发生，走的也是上面 S7 路径，结论不变。

### 原生 iOS —— 已排除为主

- UITextField 的空格 trackpad 是系统行为，选区变化不写 titleDraft；capsuleWidth 只依赖 titleDraft 与 metaLine（:4583-4601），滑动期间宽度不动，**无抖动、无抢光标代码**（全段无 selection 观察者）。已排除。
- 原生编辑器页无「滚动紧凑态」翻转机制（坞翻转是 Web 形态），不适用。

## (d) Esc 还原 / 回车提交 / 失焦提交：一致性与竞态

### Web（Rust）

- 主路径一致：Enter = preventDefault + blur() 同步落入 on_blur（keydown 两段借用处理 blur 再入，:862-901）；Esc = 先把 input.value 写回 session_base 再 blur()，on_blur 以 committed 比对、无变更不提交不 persist（:873-886 + :656-663）；失焦 = trim → 空回退「无标题」→ 提交（:645-663）。三路最终都收敛到 on_blur 同一提交口径，**主干一致（proven 良好）**。
- **proven（低）：Esc 还原可被 trim 偷换。** commit_raw 在 compositionend 时以**原文未 trim** 直写 committed（:589-598）；若该文本带首尾空白，下次会话 session_base = 未 trim 的 committed（:602-604），Esc 写回该值后 blur 仍会 trim 并判定 changed → 产生一次提交与 persist。Esc「不产生改动提交」的规格（:877-879 注释自述口径）在「上会话组字落定带空白」这一窄路径上不成立。严重度：低。
- **proven（低）：detach 兜底提交口径分叉。** detach 在会话未收尾时以原文直提（无 trim、无空回退「无标题」，:1005-1013），与 blur 口径不一致。主关闭路径有 blur_title_if_focused() 同步失焦在先（title.rs:31-44），detach 只是兜底，实际触发面窄；但若某卸载路径未先失焦（如直接换篇重挂），空标题/未 trim 标题可经此落盘。严重度：低。
- 组字期 Enter/Esc 均被守卫挡下交输入法（:868-871，composing 或 isComposing），与原版 Enter 的组字守卫（editor.js:2690 段）一致；组字中 blur 时 comp 状态清零、迟到 compositionend 在 Idle 被守卫忽略（:716-731），**无双提交竞态（已排除）**。
- keydown 处理器 try_borrow_mut 失败时静默返回（:865-867）：借用被占仅可能发生在同任务重入，JS 事件不嵌套派发，实际不可达；纵使发生，Enter 在单行 input 无默认动作、Esc 无默认动作，无副作用。已排除（理论项）。

### 原生 iOS

- **proven（中）：commitTitle 无 trim、无空标题回退，与 Web 口径分叉。** MomentApp.swift:4538-4548 原样写入 ui.titleDraft：清空标题失焦后落盘的是空串而非「无标题」，首尾空白原样落盘（持久路径无二次 trim，3549 行的 trim 仅用于导出文件名）。Web 三路提交恒 trim + 空回退。数据层跨端不一致：同一篇在 Web 打开失焦会被改写、在原生则保留空标题（列表/反向链接以标题为键，空标题是实际数据差异，不只是显示差异）。严重度：中。
- **proven（中低）：Enter 不结束会话，Esc 还原点随之漂移。** onSubmit 只调 commitTitle()（:4560），不辞焦（titleFocused 保持 true、键盘不收）；Web Enter = blur 结束会话。后果链：原生 Enter 已把草稿提交进 editor.title，此后再按 Esc，handleEscape 的还原源是 `editor.title`（当前值，:4532-4534）而非**聚焦时快照**——Enter 之后的那段输入无法被 Esc 撤销。Web 的 session_base 是聚焦时快照（title_controller.rs:604）、且 Enter 后会话已结束不存在此问题。原生既无会话起始快照、Enter 又不收尾，两点叠加使 Esc 语义与 Web 分叉。严重度：中低。
- 失焦提交本身闭合：onChange(of: titleFocused) 失焦即 commitTitle（:4561-4563）；Esc 路径先还原草稿再置 titleFocused=false，触发的 commitTitle 因草稿 == 现标题而空转（:4532-4534 + :4539），这一支自洽（proven 良好）。
- 竞态面：原生无组字守卫问题（UITextField 组字不触发 onSubmit；失焦提交读草稿现值），无双提交路径。已排除。

## 问题清单（按严重度）

| 编号 | 端 | 问题 | 定性 | 证据 |
|---|---|---|---|---|
| B-1 | 原生 | commitTitle 无 trim / 无空标题回退，空标题与空白原样落盘，与 Web 数据口径分叉 | proven | MomentApp.swift:4538-4548 |
| B-2 | 原生 | 胶囊最大宽 = 整屏宽 − 124 写死，iPad 双栏/横屏/分屏下可用宽算错 | proven | MomentApp.swift:4598 |
| B-3 | 原生 | Enter 不结束会话 + Esc 还原源为当前标题而非会话快照，Esc 可撤销范围与 Web 分叉 | proven | MomentApp.swift:4560、4532-4534 |
| B-4 | 原生 | 长标题点按落点映射未实现，光标落位交 UIKit 默认 | proven | MomentApp.swift:4564-4569 |
| B-5 | 原生 | 聚焦换宽无动画（动画只绑草稿值），截断↔全文宽度突跳 | proven | MomentApp.swift:4579-4589 |
| B-6 | 三端 | 截断计数基不一致：原版 UTF-16 / Web 标量 / 原生字素簇，emoji 标题截断点分叉 | proven | 原版 editor.js:2498；title.rs:23-31；MomentApp.swift:4587 |
| B-7 | Web | Esc 还原在「组字落定文本带首尾空白」时被 blur 的 trim 偷换成一次提交 | proven（窄路径） | title_controller.rs:589-598、645-663、873-886 |
| B-8 | Web | detach 兜底提交无 trim / 无空回退，与 blur 口径分叉（触发面窄） | proven（窄路径） | title_controller.rs:1005-1013 |
| B-9 | Web | 胶囊上下留白区点按不落焦（与原版同形态，非回归；命中面事实） | proven | editor.css:1198、1203、1213；监听仅在 input（title_controller.rs:812 起） |
| B-10 | Web | 逐键 sync_width 多次强制同步布局，低端机快速连打/拼音高频更新时跟手感风险（不丢字） | inferred | title_controller.rs:412-470、187-194、832-846 |
| B-11 | 原生 | 逐键 @Published 发布触发全 EditorView body 重演算 + 每键两次字符串实测，跟手感风险（不丢字） | inferred | MomentApp.swift:4148、4551-4580、4583-4601 |
| B-12 | Web | live_text 拼接依赖 composition/input 事件时序，异常时序下宽度瞬时偏差（文本无损、自愈） | inferred | title_controller.rs:286-308 |
| B-13 | Web | 落焦首帧光标可能在起点闪现一帧；rAF 与首键竞态窗口一帧 | inferred | title_controller.rs:610-614、753-773 |

## 已排除项（代码确证不会发生）

1. Web 快速输入丢字/跳字/值回滚：逐键路径零写值、value 不进 vnode、框架不托管标题子树（title.rs:5-14；title_controller.rs:832-846）。
2. Web 组字被框架重渲染/选区逻辑打断：守卫豁免 meta 子树、提交不触标题 DOM（title_controller.rs:1076-1082；bridge_wire.rs:105-113）。
3. Web 空格 trackpad 滑动被抢光标 / 触发坞翻转 / 宽度抖动：控制器无 selectionchange 监听；桥三处 selectionchange 监听均够不到 input 内选区；S7 编辑期抑制翻转（hooks/scroll.rs:40-52）。
4. Web 组字中 Enter/Esc 误提交、blur 与迟到 compositionend 双提交：守卫齐备（title_controller.rs:716-731、868-871）。
5. 原生组字被绑定回写打断、空格滑动引发宽度抖动：无回写路径、无选区观察者（MomentApp.swift:4551-4601）。
6. Web 截断落点映射的居中偏移/省略号边界/UTF-16 换算：逐项核对正确（title_controller.rs:228-278、205-208）。
