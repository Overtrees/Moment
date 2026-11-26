# 白带问题对比审计：45b5b46（无白带基线） vs 现行（构建 1af457fdd4 源码）

- 审计时间：2026-11-23 晚。基线 = 提交 `45b5b46`（#14 页面过渡之前）；对象 = HEAD `8286384` + 此前未提交改动（Diag 结果侧打点 + body::before 改写装置移除 + 根色内联双写），即生产构建 `1af457fdd4` 的源码状态。
- 方法：只读对比。基线文件抽至 /tmp/audit_band 后逐项 diff + 读码；未改任何代码。
- 第六轮三杠杆（串行交换 / 灯箱不预压暗 / 启动预绘）已于审计前全数撤销：index.html 与两探针 `git checkout` 恢复，main.rs 10 处、editor.rs 5 处逐项反向编辑恢复；验证 = git status 已修改集恰为此前 8 个文件（native 两件、probe_pages_settings.mjs、diag.rs、editor.rs、editor/bridge.rs、main.rs、styles/base.css）、「第六轮」标记 grep 为 0、灯箱 DimLayer 注册回位（editor.rs:3602）。工作树与 1af457fdd4 源码状态逐项一致。

## 观测集

- ① 浅色：编辑→列表返回后，列表顶部带为纯 #FAFAFA 实心栏（页面已 #F2F2F7），稳态不消。
- ② 深色冷启动、零过渡：列表黑页（根色实测 rgb(0,0,0)）顶部带为浅色（状态栏黑字坐浅带）。Diag 同轮：启动首行 ROOTSET body=rgb(255,255,255)（WASM 启动期白画布）。
- ③ 灯箱开：页面 rgb(30,30,30)，上下带纯 0。
- 既有实测定案（截图逐列剖面）：因子律 M2 —— 带色 = 当前根色 ×(1−α)，α 为覆盖层不透明度（备份态 α0.28 → ×0.72 吻合；灯箱 α0.88 时带 ≈ 根色×0.12）。
- 既有设备 Diag 定案：现行文档侧根色写入/清除/残留/晚到写入全对（五轮实证），残留绘制者在浏览器带区绘制层。

---

## 主线一：html/body 滚动管理与单色铺满

| 项 | 45b5b46 | 现行 | 差异 | 解释力 |
|---|---|---|---|---|
| tokens.css / --primary-bg | 浅 #f2f2f7（tokens.css:3）、深 #000000（:209） | 同 | **文件逐字一致** | 无 |
| base.css 的 html/body 规则 | html{background:var(--mn-root-bg, var(--primary-bg)); overflow-x:hidden; min-height:100%}；body 同背景 + min-height:100vh + padding-bottom:env(safe-area-inset-bottom) | 同 | **逐字一致**（仅注释差） | 无 |
| 滚动主体/滚动监听 | html/body 统一滚动；spawn_list_scroll_listener 为 use_hook 常驻（基线 main.rs:56 定义、:419 调用） | 同构 | 无 | 无 |
| apply_root_bg 形态 | 基线 main.rs:257-282：**只写 documentElement 上两个 CSS 变量**（--mn-root-bg / --mn-root-rgb），`let _=` 吞错，无内联 backgroundColor | main.rs:348-423：内联 backgroundColor 直写 html+body（权威）+ 变量同值镜像 + ROOTERR 守卫 + ROOTSET 打点 | 写入形态变，**值与时机口径未变** | **不能解释 ①③（proven）**：第五轮真机已证——内联直写下设备 Diag 全程正确、截图带依旧。写什么形态带都不跟 |
| 根色派生输入 | 基线 main.rs:445-473：纯由 page/selected 决定；**无 DimStack**（基线 main.rs/editor.rs 中 DimStack 出现 0 次）；selected 查无备忘时 .and_then 直接 None | 派生增 DimStack 压暗输入（栈非空按 max α 向黑混合）；唯一注册者 = 灯箱 α0.88（editor.rs:3602）；查无备忘时回落 effective_bg(&None) | **新增压暗输入**（#13 批引入） | **能解释 ③**（见主线二灯箱行与判定） |
| 其他 html/body 背景写入者 | 仅列表 .page-enter 内联 background-color:var(--primary-bg)（基线 main.rs:688） | 同（现行 main.rs:1308） | 无 | 无 |
| #main/stage 容器 | 无包裹层（见主线二） | 新增 .page-current/.page-leaving/.editor-stage（base.css:692-702），均无自有 background（透出根色/下层） | 新增层级 | 与主线二合并判读 |

## 主线二：页面交换与过渡期背景清理/同步

### 两版编辑→列表完整时序

**45b5b46（串行）**——证据：基线 editor.rs go_back 尾段（:2306/:2363 附近）、基线 main.rs:884-921 on_close、基线 main.rs:663-978 渲染：

1. 点返回 → 编辑器内保存（data.set + save_backup await）→ `page_closing.set(true)`：#editor-root 内联动画切 slideOut。
2. **整个 320ms 出场窗口内，文档只有编辑器一层**（在流内、非 fixed；列表未挂载；无任何包裹层）。窗口内 selected 未清、根色恒编辑值（变量 = 250）。
3. `document::eval` 的 setTimeout 320ms 到时 → `on_close` 在**同一次任务/提交**内：`apply_root_bg(None)`（摘变量，html/body 落 var(--primary-bg)）+ `selected.set(None)` → 编辑器卸载（use_drop 同步清理）、列表挂载（.page-enter + 内联 var(--primary-bg)）+ 双 rAF 滚动恢复。**编辑器消失、列表出现、根色翻转三者同帧。**

**现行（重叠交接，#14 e645b37 + 提交点终版语义）**——证据：main.rs:1046-1087（begin_editor_leaving / arm_unload / clear_editor_leaving）、main.rs:1090-1157（Nav spawn：set_timeout(page_transition_ms) + 代际校验）、main.rs:1277-1523 渲染、base.css:692-702：

1. 点返回 → 编辑器保存 → on_close → `begin_editor_leaving`：selected **保留**、editor_closing=true、存列表滚动位。
2. **同一次渲染提交内列表即刻挂载**：列表在 .page-current（position:relative; z-index:1，**上层**）内播 .page-enter；离页编辑器在 .editor-stage.leaving（position:fixed; inset:0; z-index:0，**下层**；pointer-events:none）内以 closing prop 播 slideOut。窗口内根色恒编辑值（派生输入未变）。
3. 320ms 计时到时（代际校验通过）→ 提交闭包同任务清 leaving 条目 + selected + closing 复位 → 编辑器卸载、根色**单次**翻转。

**结构差（proven）**：现行窗口内文档同时存在两层全文页面，且**列表的挂载时刻由基线的「编辑器消失同帧」提前到「点击同帧」**——此刻根色仍是编辑色 250；根色翻转被推迟到 320ms 后的提交帧。基线中列表挂载与根色翻转同任务发生。

### 窗口内逐层背景来源（编辑→列表，t=点返回）

| 层 | 45b5b46 窗口内（0–320ms） | 现行窗口内（0–320ms） | 现行提交帧（t=320ms） |
|---|---|---|---|
| html/body 背景 | 变量 --mn-root-bg = 编辑色 250 | 内联+变量 = 编辑色 250（同值双写） | 单次翻为默认（变量摘除、内联清除 → var(--primary-bg) 242） |
| 根 div / 包裹层 | 无包裹层 | .page-current（z1，无自有背景）/ .editor-stage.leaving（z0 fixed，无自有背景） | 包裹层随编辑器卸载消失 |
| #editor-root | 在流内，内联 background = effective_bg（250），slideOut 播于自身 | fixed 下层内，内联 background = effective_bg（250，恒自带、closing 不改 transparent），slideOut 播于自身 | 卸载 |
| 列表根 | **不存在** | .page-enter：内联 background-color:var(--primary-bg)（242），slideIn backwards 播于自身，z1 上层 | 已在位（进场动画已播完/将完） |

注：现行设计为有意「进入层在上、离页层在下」（base.css:683-691 注释：出场动画由合成器驱动、不吃主线程）。窗口内顶层全文层是列表自身，但**根色（html/body）在窗口内仍是 250**，且列表根的挂载动作发生在根色=250 的时刻。

### #editor-root 自有背景（单独项）

两版**同形**：基线 editor.rs:2896 与现行 editor.rs:2985 起均为内联 `background:{effective_bg}` + page_anim。`.detail` CSS 两版一致（min-height:100dvh 等）。**它不是两版差异点**；差异在它与谁同屏、何时同屏（基线：独占窗口；现行：与已挂载列表同屏 320ms）。

### 组件页（设置/备份等）

基线：组件内 close_page（settings.rs:41）——closing 置位 + 按 --motion-page-transition（运行时读 CSS 变量、回落 280ms、reduced-motion 为 0）延时后 on_back 卸载，**串行**；页面底恒 var(--primary-bg)，与派生同值。现行：Nav 栈式交接——离页内容快照入 .page-leaving 冻结层（fixed、内层 translateY(-scrollY) 冻结滚动姿态）、新页即刻上层 .page-current。其底色与派生同值，对三观测无独立解释力。

### 灯箱（与 ③ 相关）

基线：**无 DimStack**——开灯箱根色不变（250）；.lightbox 为 height:100lvh 定高、自身 rgba(0,0,0,0.88) 遮罩。现行：灯箱注册 DimStack α0.88（editor.rs:3602）→ apply_root_bg 把根色**预压暗为 #1e1e1e（30）**；灯箱几何另已收口为 position:fixed + inset:0（盒高差 19pt 的修复，与带色无关、勿混）。设备 LBX 实证现行开时根色 30、rect 满幅、dim push/pop 干净——应用侧按现行设计全对。

## 主线三：编辑器退出清理面逐项对照

基线 sync_editor_cleanup（bridge.rs:2510-2567，use_drop 同步直调，基线 editor.rs:2140 附近）；现行（bridge.rs:2821-2922）+ editor.rs use_drop 末尾 log_census("EDIT")。

| 清理项 | 45b5b46 | 现行 | 判定 |
|---|---|---|---|
| __mnBgCleanup（撤 #body-before-bg 样式元素 + 背景 scroll 监听 + scheme mq 监听、置 __mnBgActive=false），并将 __mnBgCleanup/__mnBgUpdate 置 null | 调用 + 置 null | **不再调用**（装置已整删）；仅列入 CLEAN 普查名单作恒 null 见证 | 非丢失：三项职责分别对应「元素不存在（设备 bbbg=false 恒证）/ 该 scroll 监听随装置消亡 / scheme mq 由 __mnSchemeCleanup 独立摘除」 |
| scheme mq 监听 | 含在 __mnBgCleanup 内 | 独立 __mnSchemeCleanup 调用 + 置 null | 等价保留 |
| __mnBridgeCleanup 调用 + 置 null | 有 | 有 | 同 |
| __mnWideCleanup 调用 + 置 null | 有 | 有 | 同 |
| __mnEdScroll（window scroll）摘除 + 置 null | 有 | 有 | 同 |
| __mnEsc（keydown capture）摘除 + 置 null | 有 | 有（bridge.rs:2888-2895） | 同 |
| __mnResume（visibilitychange/pageshow/focus）摘除 + 置 null | 有 | 有（bridge.rs:2896-2904） | 同 |
| __mnTypedMark（input capture）摘除 + 置 null | 有 | 有（bridge.rs:2905-2911） | 同 |
| 清理打点 | 末尾无条件 log "editor cleanup sync done" | 新增 CLEAN pre/post 逐项普查 + bbbg 检查 + 同句 log | 现行新增（结果侧量测） |

**结论：清理面无「基线有而现在丢了」的悬空项（proven）**；设备 Diag 亦证现行清理全项落地（CLEAN post 全 null）。与三观测无关。

## 主线四：body::before

| 项 | 45b5b46 | 现行 | 差异 |
|---|---|---|---|
| CSS 规则（base.css @supports 块） | fixed 顶带、高 env(safe-area-inset-top)×1.2、浅色白渐变/深色黑渐变、z-index 9999、pointer-events none | 同 | **逐字一致** |
| JS 改写面 | editor.rs:2070-2113 整套装置：use_effect 内 spawn+eval 安装（装前先调上一代 __mnBgCleanup）；update() 按 alpha=scrollY/30 把 body::before 背景 !important 改写为以 var(--mn-root-rgb) 为源的渐变（变量缺失回落字面量浅 250,250,250 / 深 0,0,0），alpha≤0.01 写 transparent!important；window scroll rAF 节流刷新；scheme mq 同居（基线 editor.rs:905-913 set_bg 同步刷新入口） | **装置整套移除**（第四轮，构建 08d48a2daa）；body::before 在所有页面恒为 base.css 基础渐变 | 装置存废 |

解释力：当前三观测均为标签页形态截图，该形态 env(safe-area-inset-top)=0 → body::before 高度为 0，**两版都画不出顶带**——不能解释 ①②（proven 阴性）。备注：若日后以 standalone（主屏图标）形态运行（env>0），基线会把顶带画成随滚动变化的根色渐变、现行只画静态基础渐变——那是另一形态下的真实差异，与本次三观测无关，单列备忘。

## 主线五：过渡动画本身逐项对照

### keyframes 定义

| keyframes | 45b5b46 | 现行 | 差异 |
|---|---|---|---|
| slideInFromRight（editor.css:172-175，两版同行号） | from{opacity:.94; transform:translate3d(24px,0,0)} to{opacity:1; transform:translate3d(0,0,0)} | 同 | **逐字一致** |
| slideOutToRight（editor.css:180-183） | from{opacity:1; transform:translate3d(0,0,0)} to{opacity:.92; transform:translate3d(16px,0,0)} | 同 | **逐字一致** |
| mainFadeIn（editor.css:176-179） | opacity 0→1 | 同 | 逐字一致 |

注：交接动画实为**小位移淡变**（入 24px、出 16px，opacity .94/.92），并非整屏滑出；两版皆然。动画属性仅 transform + opacity，**不含 background**——动画本身从不改任何背景色（两版同）。

### 交接类 CSS

| 类 | 45b5b46 | 现行 | 差异 |
|---|---|---|---|
| .page-enter（base.css:668 基线） | animation: slideInFromRight var(--motion-page-transition,280ms) cubic-bezier(0.22,0.61,0.36,1) **backwards** | 同（规则逐字一致） | 无 |
| .page-slide-in / .page-slide-out（base.css:676-677 基线，组件页内容层） | both / forwards，同 280ms 变量、同曲线 | 同 | 无 |
| #editor-root 的 page_anim（内联） | editor.rs:2881-2889：slideOut 0.28s forwards / slideIn 0.28s both，播完 320ms 由 page_anim_done 摘除 | editor.rs:2975-2980：同字符串、同摘除机制（closing prop 优先） | 无 |
| .page-current | **不存在** | base.css:692：position:relative; z-index:1（无 background/transform/animation） | **新增** |
| .page-leaving | **不存在** | base.css:693-696：position:fixed; inset:0; overflow:hidden; pointer-events:none; z-index:0；内层冻结包裹 transform:translateY(-scrollY)（main.rs:1215-1227 附近内联） | **新增** |
| .editor-stage / .leaving | **不存在** | base.css:698-702：常态 position:relative; z-index:1；.leaving 切 fixed/inset:0/overflow:hidden/pointer-events:none/z-index:0 | **新增** |
| will-change | 仅 toast 一处（base.css:652 基线） | 仅 toast 一处（base.css:655） | 无；交接元素两版均无 will-change |
| backdrop-filter（交接层） | .page-enter/#editor-root/.detail 均无 | .page-current/.page-leaving/.editor-stage/#editor-root 均无 | 无 |

--motion-page-transition 未在 tokens.css 定义（两版同），CSS 与 JS 两侧均走 280ms 回落。

### 玻璃/模糊层清单（backdrop-filter，选择器级 diff）

- 交接相邻玻璃集**两版一致**：列表头 .page-title.compact、.glass-search-trigger/.glass-search-panel、编辑器 .editor-fab、.editor-title-capsule、.editor-menu-panel、卡片类玻璃（.editor-body .img-text-card 等）——取值同为 var(--glass-*-filter)。
- scheme flip 玻璃重挂边界（App 层 tick + 四个列表胶囊 keyed 重挂）**基线已存在**（基线 main.rs:596 附近注释与代码），非现行新增。
- 选择器级差异全在无关批次：现行新增备份页玻璃（.backup-btn/.backup-card/.backup-hero/.backup-modal/.backup-stat）与 .seg-btn；基线 .blk-more 随卡片 ••• 移除批消失；.mn-lifted 改为 .mn-lifted::before（拾起框批）。
- 灯箱 .lightbox 两版均无 backdrop-filter（纯 rgba 遮罩）。
- 判定：玻璃层随页面挂载/卸载而生灭，两版均无跨交接残留机制；Diag 的 glass remount 发生在 scheme 切换路径、非交接路径。**不能解释 ①②③（proven，代码级阴性）。**

### JS 侧动画驱动

| 项 | 45b5b46 | 现行 | 差异/一致性 |
|---|---|---|---|
| 编辑器出场定时器 | go_back 内 eval setTimeout **320ms** → on_close | page_transition_ms(Editor) = **320ms**（settings.rs）→ arm_unload 提交 | 一致：均为 CSS 280ms + 40ms 尾 |
| 编辑器进场动画摘除 | spawn 320ms → page_anim_done | 同 | 一致 |
| 组件页出场定时器 | close_page（settings.rs:41）：运行时读 CSS 变量（NaN→280）、reduced-motion→0；closing 重入守卫 | page_transition_ms：同逻辑 Rust 化；Nav 代际校验 | 时长口径一致；机制由组件 spawn+eval 迁 App 层 spawn+set_timeout+gen |
| animationend 监听 | **无**（src 全grep 0 命中） | **无**（同） | 一致：两版完成判定全靠定时器 |
| 代际校验 | 无此概念（串行下不需要） | leaving 条目 gen 与 nav_gen 比对，过期提交作废 | 现行新增，与重叠交接配套 |
| 动画被打断 | 窗口内编辑器在流内独占视口、列表未挂载，**无从点到列表**；组件页 close_page 有 closing 守卫 | 窗口内列表已挂载且可交互（.editor-stage.leaving 为 pointer-events:none、列表在上层）→ 中途点开另一备忘 → clear_editor_leaving **即刻卸载**离页编辑器（动画中途截断）、待提交被 gen 校验作废 | **行为差异（proven）**；但三观测均非打断场景，**不能解释 ①②③** |

### 合成层提升

- 两版同：#editor-root 在进/出场动画期间因 transform+opacity 动画被提升；出场 fill forwards 使终态（opacity .92、+16px）在 280–320ms 的 40ms 尾内保持图层，直至定时器卸载；进场 fill both 使 translate3d(0,0,0) 残留至 320ms 摘除动画。列表根 .page-enter 为 backwards 填充，动画后无残留 transform，仅动画期间提升。
- 现行新增：窗口内多出 .editor-stage.leaving（fixed 全屏层）与（组件页路径的）.page-leaving（fixed + 内层 translateY 变换层）两个全屏合成层；窗口内全屏层数由基线的 **1**（在流编辑器）变为 **2**（fixed 离页编辑器 + 进入中列表）。
- 动画结束后回落：现行提交帧卸载离页层、.page-enter 播完回自然样式，无残留变换层（代码级）。**残留的只有带色，不是 DOM/图层残留**（设备 Diag CLEAN/CENSUS 亦证无残留节点）。

### 旧版动画形态结论

45b5b46 的交接动画与现行**是同一套动画**（keyframes、时长、曲线、填充模式、驱动定时器逐项一致）；旧版之「旧」不在动画，而在**层构成与挂载时序**：出场窗口内只有离页一层、新页在出场播满且根色翻转的同一任务内才挂载。动画定义层面的差异为零（proven）。

---

## 根因判定（分级）

### 观测 ①（返回列表顶带 #FAFAFA）

- **proven（结构差）**：现行把「列表挂载」与「根色翻转」解耦——列表在点击同帧、根色仍为编辑色 250 时挂载，翻转迟至 320ms 提交帧；基线三者同任务。现行窗口内另多一个 fixed 全屏离页层。
- **inferred（机制模型）**：浏览器带色在「整屏层挂载冲击时刻」按当时根色锁存、其后普通根色样式变更不触发重采。该模型与全部观测自洽：现行冲击时刻（t0 列表挂载）根色 = 250 → 带锁存 250，t320 翻转被无视；基线冲击与翻转同任务 → 锁存 242；②③ 亦由此模型统一解释（见下）。此模型无直接量测手段，定级 inferred，不冒充 proven。
- **proven（排除项）**：apply_root_bg 写入形态（变量 vs 内联双写）无关（第五轮真机实证）；tokens/--primary-bg 与 html/body CSS 两版一致；清理面无丢失项；body::before 在标签页形态高度为 0；动画定义零差异；玻璃层无跨交接残留机制。

### 观测 ②（深色冷启动浅带）

- **proven（阴性）**：index.html 两版**逐字一致**（diff 为空）——theme-color 浅 #ffffff / 深 #000000（media 分行，与原版 Moment.html 相同）、splash 内联样式（body 浅 #ffffff、深色 media #000000）皆同。WASM 启动期白画布窗口在基线同样存在。**② 不是相对基线的代码回归，无任何代码差异可归因。**
- **unknown**：基线在真机深色冷启动下是否同样出浅带，从未被报告/量测，无从判定；带色机制本身（浏览器对首帧画布的采样）在应用侧不可量测。若按 ① 的 inferred 模型，首帧冲击锁存白画布（255）与观测一致，但模型本身未证，② 的成因维持 unknown。

### 观测 ③（灯箱带纯 0）

- **proven（算术）**：DimStack 灯箱预压暗为现行新增（基线不存在，grep 0 次 vs editor.rs:3602 注册 α0.88）。按已实测定案的 M2（带 = 根色 ×(1−α)）：基线开灯箱根色 250 → 带 ≈ 250×0.12 ≈ 30 = 页面呈现色（30），无可见色差；现行根色预压暗至 30 → 带 ≈ 30×0.12 ≈ 0 ≠ 页面 30。**预压暗是解释 ③ 色差的唯一必需代码差异。**
- **inferred**：M2 中「浏览器把遮罩合成延伸到带区」的浏览器侧归因（因子律本身由截图剖面实测，归因未直测）。

## 若恢复 45b5b46 相关行为：最小改动集（仅方案，未落码）

1. **编辑→列表恢复串行时序**（对应 ①）：Nav 对「编辑器退出到列表」一条路径停用预挂载与留槽——出场窗口内不渲染列表层；提交任务内同帧完成编辑器卸载 + 列表挂载 + 根色翻转（提交点语义保持现行终版：离页期状态仍为编辑器、根色恒编辑值、只翻一次）。其余过渡（列表→编辑器、组件页链、wiki 瞬时交换）不动。
   - **代价须用户权衡**：此即 #14 栈式交接要根治的问题本体——串行下新页挂载长任务冻结其进场动画起步（#14 取证：4x 节流实测冻结 84ms、退出弹跳）。恢复基线时序 = 放弃该根治，二者是同一枚硬币的两面。
2. **灯箱摘除 DimStack 注册**（对应 ③）：删 editor.rs:3602 的灯箱 DimLayer 注册点；DimStack 代码与 Diag 形状保留（注册者归零后 dimmed 恒返回 base，scheme 竞速路径行为不变，须核对一遍）。灯箱自身 rgba(0,0,0,0.88) 遮罩不动，页面内呈现仍为约 30，带按 M2 应回 ≈30 与页面齐平。备份弹窗压暗已按裁定 C 撤除，不在此列。
3. **② 不在恢复集内**：基线与现行 index.html 一致、无可恢复项。若用户决定处理启动白画布，那是新增工作（首帧预绘类），须单独立项裁定，不属于「恢复旧行为」。
4. **body::before JS 装置不恢复**：标签页形态高度为 0、与三观测无关，且其安装（spawn+eval 异步）与清理（use_drop 同步）的竞态是第四轮已根治项，恢复即引回。standalone 形态差异仅作备忘（见主线四）。

## 证据索引

- 基线：git 45b5b46（抽取于 /tmp/audit_band）——main.rs:257-282、445-473、663-978（列表支 :686、Editor 支 :877、on_close :884-921）；editor.rs:905-913、2070-2113、2306/2363、2881-2896；bridge.rs:2510-2567；settings.rs:41；styles/base.css:668-677 与 html/body、body::before 规则；styles/editor.css:172-183；styles/tokens.css:3、:209；index.html 全文 50 行。
- 现行：main.rs:348-423、1046-1157、1277-1523；editor.rs:2975-2985、3602；bridge.rs:2821-2922；styles/base.css:683-702。
- 设备侧：构建 1af457fdd4 的 Diag 序列（ROOTSET/VARMUT/CLEAN/LBX）与四张截图像素实测（2026-11-23 20:38-20:41 用户提供）；M2 因子律为同晚截图逐列剖面定案。
