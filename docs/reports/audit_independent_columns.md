# 宽屏独立滚动模式「真独立双栏容器」取证 + 差距审计

审计对象：用户 2026-11-23 定调——宽屏开启独立滚动模式须为完整真独立双栏容器（独立组合混排、独立滚动、独立渲染、独立排序、数据互不扰），且用户记得原版即如此实现。本报告先取证原版、再逐项核 Rust 现状，最后给 A-2 判断标准矩阵的「模式」轴输入。

**总结论：用户记忆基本属实。** 原版确有完整的独立滚动双栏实现（物理栏容器、各自滚动、各自编辑宿主、布局随备忘持久化）。两处需要修正精度：① 它不是「两份数据」，而是**一份有序文档 + 一条 layout 记录（本质是一个分界点）**，左右栏是同一文档的前缀/后缀；② **独立模式下原版媒体不跨栏**——跨栏（column-span）只存在于流式（多列）模式，独立模式媒体就是栏内宽。Rust 独立模式五项独立性**全部成立**（其中四项有活体证据），与原版的主要分叉不在独立模式内，而在流式模式的形态（见差距 G-1）。

量测口径：Rust 侧活体探针跑本地 dist 构建 `416ebf21c1`（提交 d4ec9b2）。线上现为 `3113b7d926`（提交 5e77f1e）；两提交间 diff 仅 title_controller.rs、probe_title_geom.mjs、editor.css 两行（标题线），栏子系统源码（columns.rs、editor.rs 栏段、bridge.rs 拖拽段、editor.css 栏段）逐字节同源，故栏行为与生产一致。视口 1440×900，无头 Chromium 口径；原版侧为代码取证（未活体跑原版）。

---

## 一、原版取证（src/，行号为现行文件）

### 1. 模式存在与开启方式
- 模式名：**双栏独立滚动**。编辑菜单内有开关行 `.editor-column-mode-toggle`（标题「双栏独立滚动」，editor.js:2809-2822），仅在宽屏媒体查询下显示（editor-shell.css:526 区：`display:none !important` 为默认，宽屏才 `display:flex`）。
- 宽屏门槛与双栏共用：`(min-width:768px) and (min-height:600px), (min-width:1100px)`。
- 开关处理 `toggleIndependentColumns`（editor.js:328-350）：切换时调用 `MynoteEditorColumns.setIndependentScroll`，并把偏好写入 localStorage `sj_editor_independent_scroll` 作为**无 layout 备忘的默认模式**；备忘自身的 `layout.mode` 优先（editor.js:306-315）。

### 2. DOM 结构与滚动容器（editor-shell.css:529-604）
- `.editor-body.is-independent-scroll` 变为两列 grid（1fr/1fr，gap 与流式同口径 clamp），定高 `max(200px, calc(100dvh - 187px - 安全区))`，`overflow:hidden`。
- 每栏 `.editor-column`：`height:100%; overflow-y:auto; overscroll-behavior:contain`——**真独立滚动容器**；左栏右内距 16px + 右边框线，右栏左内距 16px。
- 窄屏下栏包装层 `display:contents` 退化为透明流、保持单栏编辑（editor-shell.css:443-445），模式标记保留。
- 每栏是**独立的 contenteditable 宿主**：容器本体 contenteditable=false，两栏各 contenteditable=true、role=textbox、aria-label「左栏正文/右栏正文」（editor.render.js:138-149 `configureIndependentHosts`）；编辑宿主解析、跨栏光标移动都有专门代码（editor.render.js:101-136；editor.js:55 `moveCaretAcrossEditorColumns`）。

### 3. 数据模型：一份文档 + layout 分界点（editor.render.js:150-174、194-205）
- 备忘记录 = 单份有序 `doc` + 可选 `layout = {version:1, mode:'flow'|'independent', left:[块id], right:[块id]}`，随备忘落库（editor.js:749-766 保存路径写 `changes.layout` 与 `layout: columnLayoutRef.current`）；草稿恢复同样携带 layout（editor.js:152）。备份校验器对 layout 有专门格式校验（services/backup-validate.js:165-176：version 必须 1、mode 枚举、两列 id 不许重复），即 layout 是备份格式的一部分。
- **关键语义**：`normalizeColumnLayout` 把任意 left/right 名单归一为**单个分界点**——取 right 名单中按文档序最早的块为右栏起点（无 right 时取最后一个 left 块之后），left = 文档前缀、right = 后缀。交错归属会被强制拉直为一刀切。所以「栏归属」在数据上只是一个切分下标，不存在逐块任意分配。
- 首次启用且无存档 layout 时的分法：按**实测块高**（editorBlockHeight：实测 rect 高优先，回退表 图/画廊/图文 280、音乐/链接/文件 120、文本 28+行×25）在 [1, len-1] 中取左右高差最小处切分（editor.render.js:293-312）。
- 关闭模式时 `flattenEditorColumns` 把两栏子节点按左→右顺序摊平回单容器（editor.render.js:207-231），与前缀/后缀模型自洽；`parseEditorDOM` 读文档时同样按左栏块→右栏块展平（editor.render.js:94-105、316+）。

### 4. 独立模式下媒体如何呈现：栏内宽，不跨栏
- `column-span: all` 只出现在流式多列规则下（editor-shell.css:217-223：image/gallery/img-text-card/img-text-row/musicCard；258-259：带图附件）。
- 独立模式段（582-601）对媒体**没有任何 span 规则**：image/gallery 只给 `margin: 8px 0`，musicCard 给 `width:100%`（栏宽）。即原版在独立模式里媒体就是栏内呈现，这是设计而非缺失。
- 另：独立模式下栏内文本块在 ≥900px 时限宽 72ch 居中于栏内（editor-shell.css:605-622）。

### 5. 栏内排序与跨栏
- 原版没有拖拽排序（块排序整体是 Rust 新增能力，此前审计已定）。栏内次序变化只能靠编辑操作（输入、拆分、剪切粘贴）；块换栏只能靠剪切到另一栏宿主粘贴，或关开模式重切分。任何编辑结果经 parseEditorDOM 展平后仍是单一文档序，成员关系恒为一刀切。

---

## 二、Rust 现状：五项独立性逐项核

实现骨架与原版同构：一份 doc + `memo.extra["layout"]`（model.rs:48 注释明示备忘级扩展走 extra，形状与原版同为 {version:1, mode, left, right}）；分界由 `column_boundary` 决定（columns.rs:101-108：有锚走 `normalize_boundary`——与原版归一同口径：right 名单中最早存活块为界、无 right 时取最后 left 块之后；无锚走 `canonical_boundary` 规范估高分界，估高表与原版回退表逐值一致，columns.rs:17-41、47-68）。宽屏时恒渲染两个物理 `.editor-column` 容器（editor.rs:3166-3229），独立开关只切换滚动形态不切换成员（editor.rs:2727-2734 代码注释明示此设计及其理由）。模式判定、开关、落锚、落库路径齐全：twopane 初值自 layout.mode / localStorage 默认（editor.rs:1471-1492）；菜单开关行与原版同文案同形态（editor.rs:3026-3046，i18n `menu.twopane`「双栏独立滚动」）；独立模式首次渲染把规范分界落锚落库（editor.rs:1527-1578）；关存时 twopane 开启则按当前分界重写 layout（editor.rs:2296-2333）；开关切换即时重写 layout 并记 localStorage（editor.rs:2436-2480）。样式为原版逐字移植（styles/editor.css:950-1100+，含定高、双栏各自 overflow、72ch 限宽；另加一处 .blk-wrap 防断裂适配）。

| # | 独立性 | 结论 | 证据 |
|---|--------|------|------|
| ① | 独立组合混排 | **成立** | 两栏渲染走同一 EditorBlock 全块型管线（editor.rs:3179-3229）；活体：混排夹具 16 块（段落/音乐/链接/待办/引用/图片/图文/分隔/标题）双栏分布渲染，左栏 12 块右栏 6 块（含开篇物化的 2 个尾随段）；既有 probe_twocol_matrix 已验右栏 md 进源码编辑、右栏斜杠面板、跨栏方向键 |
| ② | 独立滚动 | **成立（活体）** | 两栏 computed overflow-y=auto、clientH 713、各自 scrollHeight>clientHeight（右栏 1020）；探针令左栏 scrollTop 0→54，右栏恒 0、window.scrollY 恒 0（probe_audit_indcols.mjs I2） |
| ③ | 独立渲染 | **成立（活体）** | 左栏块内打字期间，右栏 MutationObserver（childList/attributes/characterData/subtree）突变数 = 0，右栏 innerHTML 哈希前后一致（I3/I3b）。机制：Dioxus 虽重渲染组件树，未变子树的 diff 结果为零 DOM 写入 |
| ④ | 独立排序 | **成立（活体）** | 左栏内长按拖拽换位后：右栏 DOM 序逐块不变、落盘 layout.right 逐块不变、右栏块内容逐块字节不变（I4a-I4d、I5c）。拖拽引擎按栏分组走查（bridge.rs unitMetasExt/columnWalk/applyFlip），独立模式自动滚动作用于目标栏（bridge.rs:1617-1637）。另支持跨栏拖拽（原版无此能力）：moveBlock 落盘时按原分界下标重切 left/right 名单，成员跟随且恒保持一刀切（editor.rs:3470-3515） |
| ⑤ | 数据互不扰 | **成立（活体）** | 左栏编辑+排序+多次落盘后，右栏块内容逐块字节一致、layout 成员跨会话稳定（I5c、I6a/I6b 重进成员不变）。常规 persist 只换 doc/title、extra.layout 透传保留；窄屏（单栏渲染）编辑不改成员：落锚只在 twopane&&wide 首次渲染触发，关存重写 layout 也按同一锚分界 |

活体探针：`probe_audit_indcols.mjs`（I1-I6）、定点复测 `probe_audit_indcols2/3.mjs`。说明：首轮探针中 I1c/I5a/I5b/I4d 四项表面失败，经定点复测查明全是探针口径问题——DOM 子元素是「渲染单元」（列表成组单元一元多块、md 预览单元的 bid 不在直子属性上），不能与 layout 的块 id 序列直比；且 `.editor-back` 选择器在本构建不存在、列表在编辑器下层常驻使「回到列表」假阳性。改用 DOM↔DOM、layout↔layout 同口径对比后全部成立。打字落盘经 Diag 实证走 20 秒 autosync（`EDIT autosync applied` 后 save_memos 含新文本）——这是编辑器通用的 B-4 同步口径（见 audit_editor_full.md），双栏与单栏无差别，不构成栏间干扰。

媒体量测（独立模式，活体）：图片块渲染宽 673px = 所在栏内容宽 673px；音乐卡 672≈673；图文卡 673 = 栏宽。**媒体严格栏内宽，与原版独立模式口径一致。**

---

## 三、差距清单（按严重度）

**G-1（中）流式模式形态与原版不同（独立模式不受影响）**
原版流式 = 单容器 CSS 多列（浏览器按实测高平衡、媒体 column-span 整幅）；Rust 流式与独立共用同一对物理栏容器 + 同一锚分界，只差滚动形态（styles/editor.css:1115-1140 `is-flow-columns`；editor.rs:2727-2734 注释自述）。后果：流式下成员不随实测高平衡（这是有意取舍，换来两模式成员一致、重进不跳栏——wide-editor 审计已验 @1440 两模式指派一致）；流式下媒体不跨栏（A-2 本体，量化见 audit_wide_editor.md W-2：原版图库 @1440 为 666×366 整幅，Rust 176×176 栏内方图）。

**G-2（低）无 mode 字段的 layout 默认值相反**
原版 normalize 对缺 mode 的 layout 默认 independent（editor.render.js:169）；Rust twopane 初值在 layout 存在但无 mode 时判 flow（editor.rs:1481-1483，另兼容一个原版不写的 legacy `twoPane` 布尔）。原版自身永远写 mode，故只影响手写/异常数据的互操作，可忽略级。

**G-3（低）首次切分依据不同（有意偏离）**
原版首次启用按**实测高**切分；Rust 按规范估高表（columns.rs:17-68，只用回退表不用实测，注释明示为使分界成为文档内容的确定性纯函数、免随图片/卡片加载漂移）。两边落锚后都恒定；仅「第一次打开的分界位置」可能不同。

**G-4（低）编辑宿主粒度不同**
原版每栏一个 contenteditable 宿主（栏内跨块原生选区）；Rust 每块一个可编辑元素 + 桥内跨块选区机制（mn-xsel 虚拟选区，见拖拽线既有结论）。不影响五项独立性（渲染/数据隔离已活体证明），影响的是栏内跨块选择的原生手感，属编辑模型差异。

**G-5（信息）跨栏拖拽为 Rust 独有**
原版无拖拽排序，块换栏靠剪贴；Rust 拖拽可跨栏且落盘成员自洽（一刀切保持）。超出原版能力，不作缺陷计。

**未发现高严重度差距**：就独立模式本身，用户五条要求 Rust 全部满足，且数据模型、layout 格式、开关形态与原版同构，原版存档（含 layout 的备份 ZIP）在 Rust 侧可无损往返（layout 走 extra 透传，备份校验在 Rust 侧亦接受该形状——见快速修复批 C-08 同批的格式结论）。

---

## 四、对 A-2 判断标准矩阵的输入（模式轴）

取证给出的模式轴事实（原版依据在前，Rust 现状在后）：

| 模式 × 宽度带 | 原版媒体呈现 | Rust 现状 | 矩阵应如何定 |
|---|---|---|---|
| 独立滚动 × 双栏宽度带（≥768&≥600 或 ≥1100） | **栏内宽**（editor-shell.css:582-601，无 span 规则） | 栏内宽（活体实测 = 栏内容宽） | **不跨栏**。此格无取舍：原版设计如此、Rust 已一致，A-2 不应在此格引入跨栏 |
| 独立滚动 × 窄屏 | 栏包装 display:contents 退化单栏，媒体 = 内容宽 | 同（CSS 逐字移植） | 单栏口径，无跨栏问题 |
| 流式 × 双栏宽度带 | **整幅跨栏**（column-span: all，editor-shell.css:217-223、258-259；块集 = image/gallery/imgTextCard/imageTextRow/musicCard/带图附件） | 栏内宽（物理容器无 span 机制） | A-2 的真正战场只在这一格：按用户已定的「宽度带 × 媒体类型」标准 + 文档序确定性分段实现整幅呈现；媒体块集以原版 span 名单为准 |
| 流式 × 窄屏 | 单栏，媒体 = 内容宽 | 同 | 无跨栏问题 |

补充约束（供分段实现参考）：原版流式中跨栏块在多列流里天然把文档切成「栏流段→整幅→栏流段」，与用户定的「媒体 = 文档序确定性分段点」标准同构；独立模式的成员分界（layout 锚）与流式分段是两个正交机制——流式分段不应改写 layout 锚，模式切换时成员一致性已由现有实现保证（probe_twocol_matrix M1/M2 已验两模式成员逐块一致、开关往返不变）。

---

## 五、审计边界

- 全部活体结论为无头 Chromium 口径，未验 iOS 真机/WebKit（栏滚动与拖拽手感终判仍归真机）。
- 原版侧未活体运行，结论全部来自代码取证（文件+行号可复核）；原版媒体跨栏/栏内的 CSS 规则无歧义，未做原版活体复测。
- 活体夹具为单一混排备忘（16 块 + 物化尾随段）；超长文档、空右栏（单块备忘全归左）等边界形态未逐一活测，其行为由 columns.rs 分界纯函数与代码路径推得。
- 探针文件：probe_audit_indcols.mjs、probe_audit_indcols2.mjs、probe_audit_indcols3.mjs（仓库根，未跟踪）。
