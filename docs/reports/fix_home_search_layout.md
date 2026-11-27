# 首页两线根治：搜索胶囊状态同源派生 + 内容布局对齐（2026-11-27）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。基线 HEAD 9d9dd9f（0.9.55）。
> 领地：`ListView` / 首页段 + `AvatarView` / `CompactTitle`（首页同族组件）+ `T` 令牌一枚 + verify [30]。
> 与在途批次零交叠：动工前核 git diff——U1 在途 hunk 在 BlockTextView/EditorView/桥文件、完成胶囊批在 EditorHeaderView/GlassCard 与 verify [29]；本批 hunk 全在 14816 行后（AvatarView 起）与 verify 尾部 [30]，逐 hunk 比对无重叠、未回退他人改动。
> 本机 verify 自跑：**254 ✓，[30] 九条全绿**；仅剩 2 条既有产物类 ✗（ipa 陈旧、产物语言包，tree 构建自解），与各批本机基线一致。Swift 编译级随主线 tree 冒烟（本机无 swiftc）。

---

## 线 A：搜索胶囊回车后不回缩

### 定因（证据分级）

- **结构根因 = proven（代码通读）**：胶囊开合由独立存储标志 `NavState.searchOpen` 记账，全仓写点只有三处——触发钮置 true、清除（×）钮置 false、页眉动画取值。搜索 `TextField` **没有焦点绑定**（无 `@FocusState`）、**没有 `onSubmit`**。于是任何不经清除钮的编辑结束（回车辞焦、导航离开、系统收键盘）都无路触及该标志：键盘与胶囊状态自此脱钩，胶囊永停展开态。空查询时更甚——清除钮不渲染（`if !nav.query.isEmpty`），展开态**没有任何关闭路径**。
- **用户路径复现 = proven（真机实报）**：点胶囊 → 键盘起、胶囊展开；点回车 → 键盘消失、宽胶囊停在展开态。与上述结构逐项对应（回车使字段辞焦，但辞焦事件无人消费）。
- **回车为何能辞焦 = inferred**：现行字段无焦点管理代码，回车辞焦是平台对未托管焦点字段的默认收束（同批字段在编辑器内则由 UIKit 附件栏「完成」承担确定性出口）。本批落码后该问题不再相关——辞焦由 `onSubmit` 显式承担。
- **Web 口径 = proven（源码）**：`SearchCapsule`（web/src/main.rs:170-228）——`onmounted` 自动聚焦、`onblur` 即 `search_open.set(false)`、Esc 同收；**开合 ⟺ 字段持焦**，query 是独立信号、收起后保留续滤；Web 面板无清除钮（清除走空状态动作或重开后删词）。

### 根治（状态单一真相）

胶囊展开态改为由焦点的**同源派生**，存储标志整删（代码零残留，verify F30-1 锁）：

| 件 | 改法 |
|---|---|
| 真相源 | `ListView` 新增 `@FocusState private var searchFocused: Bool`；`searchCapsule` 分支条件即 `searchFocused` 本身；触发钮动作 = `searchFocused = true`（字段随分支插入即持焦，与 Web onmounted set_focus 同构） |
| 回车 | 字段 `.onSubmit` 写明来源 `submit` 后辞焦 → 胶囊回缩、**query 保留续滤**（Web onblur 同口径） |
| 清除钮 | 原生增强保留：清 query + 来源 `clear` + 辞焦同收（与旧行为等价） |
| 滑动收起 | 窄屏 `List` 与宽屏 `ScrollView` 各加 `.scrollDismissesKeyboard(.interactively)`（编辑页既有同口径）——辞焦即回缩 |
| 离开首页 | `resignSearch()` 单点收敛：`createAndOpen` / `openMemo` / 头像钮 / 紧凑标题钮四处离开漏斗调用（来源 `nav`），对应 Web 页面切换时 input 失焦 |
| 来源记账 | `NavState.searchCloseSrc`（普通 var、不发布）：程序化辞焦前写明 submit/clear/nav，系统侧辞焦走默认 `system`，`onChange` 消费后复位 |
| Diag | 此前搜索胶囊迁移无打点，本批补：`APP search capsule open` / `APP search capsule close src=<submit\|clear\|nav\|system>` 各一行（挂 body 的 `onChange(of: searchFocused)`） |

**全路径收敛核对**（每条让键盘消失的路径 → 胶囊终态）：回车 → 回缩（词保留）；滚动 → 回缩；清除钮 → 回缩（词清）；点开/新建备忘 → 回缩（词保留，返回首页后续滤，与 Web 一致）；进设置 → 回缩；空状态「清除搜索」→ 只清词不辞焦（字段持焦时胶囊保持展开、词已清——Web 同：动作只清 query、input 不失焦）。

**行为等价守恒**：过滤口径（`library.search` / `searchHits`）未动；结果点按走 `openMemo` 同路；query 的保留/清除语义如上逐项对 Web；展开/收起交叉淡入（M5）保留，动画值改绑派生状态。左滑动作钮点按不辞焦（与改前一致、无回退；Web 该路径会失焦，属未在用户清单内的微分叉，登记不扩围）。

**刻意不取的替代**：派生式 `searchFocused || !query.isEmpty`（有词则保持展开）——用户实报场景正是「有词回车后仍停宽胶囊」，该式会让原报障原样保留；且与 Web 失焦即收相悖。故取纯焦点派生。

### 真机终判点（线 A）

1. 点搜索胶囊 → 键盘升起且胶囊保持展开（字段插入即持焦，无闪烁回落）；桥 diag_tail 应见 `APP search capsule open` 恰一行。
2. 输词后点回车 → 键盘收、胶囊回缩成触发钮、列表仍按词过滤；Diag 见 `close src=submit`。
3. 重新点开胶囊（词还在、× 在）→ 点 × → 词清、胶囊收；Diag 见 `close src=clear`。
4. 展开态上滑列表 → 键盘交互收起、胶囊随之回缩；Diag 见 `close src=system`。
5. 展开态点开一篇备忘 → 键盘收、进编辑器；返回首页胶囊为触发态、词保留；Diag 见 `close src=nav`。

---

## 线 B：首页内容布局全量对齐审计

方法：以现行 Web 为基准逐段量对（真源 `rust/apps/web/styles/{tokens,base,editor}.css`、`src/{main,list}.rs`），并先销前两轮审计账（`audit_detail_home.md` 86 条 + `audit2_home.md`）——批 A/C/E 与 H 系列已修项逐项回潮核验**无回潮**（含 audit2 新项：日期边界 ≤7/≤30、折叠卡整卡点按、网格空状态搜索态、meta 色 glass-label、置顶刷新 updatedAt、组序遇见序、摘要 strip_markdown 全链、标题上限基数、方卡药丸钮、pendingDeletions 多槽等，均在现行代码属实）。已定案偏离不翻案：悬浮页眉结构（0.9.23）、左滑系统实现、紧凑胶囊阈值 + 180ms 淡入、notice 行、空状态 SF 图标替代、网格长按菜单。本轮落码 = 下表「对齐修复」6 组；其余进「调优候选 / 维持登记」。

### 量测对账表（顶区逐段，用户点名项）

坐标以安全区顶为原点（原生安全区由系统 safe area 动态给出、无写死值，Web 侧为 `env(safe-area-inset-top)`，同口径）：

| 段 | Web 原版 | 原生修复前 | 原生修复后 |
|---|---|---|---|
| 顶行（actions 带） | 44（空带，流内占位） | 无此带（悬浮结构定案，不补） | 同左 |
| 头像行顶距 | 标题区 padding-top 4 → 头像顶 48 | 页眉 padding-top 7 → 头像顶 7 | 7（悬浮定案内） |
| 头像 | 72 | 72 | 72 |
| **头像底 → 首卡顶** | **10（标题区底 padding）+ 46（.container 顶 padding）= 56** | **12**（页眉框余 3 + 占位溢出 6 + 行 inset 3） | **56**（占位 132 + 行 inset 3 → 首卡顶 135 = 头像底 79 + 56） |
| 首卡顶（绝对） | 176 | 91 | 135 |

**「顶到顶」定因**：悬浮结构（0.9.23 定案）把流内三段（44 空带 + 标题区 86 + container 顶距 46）压成页眉框 82 + 占位 88；其中 44 空带属结构性取舍（定案范围），但头像之下的两段**纯间距**（10 + 46 = 56）被压到只剩 12——第一轮审计当时把「首卡静止位」整项归入定案偏离，其备注已自陈「纵向偏移量本身未见单独定案记录」。本轮按用户实报把间距段从结构定案中拆出补回：占位行 88 → **132**（窄屏，+首行 inset 3 = 135）；网格占位行 88 → **135**（网格无行 inset，同账：首卡顶同为 135、头像下间距同为 56）。页眉框 82 与滚动探针基线机制不动（基线由占位行本体捕获，与行高无关）。

### 对齐修复清单（已落码）

| # | 项 | Web 真值 | 修复前 | 修复后 |
|---|---|---|---|---|
| B-1 | 首卡顶距（窄屏 + 网格） | 头像下 56 | 12 | 56（占位 132 / 135，见上表） |
| B-2 | 分组头组间合成距（批 C 登记 B6） | 文字上 28 / 下 6（前组 margin-bottom 24 + 组头 padding-top 4——组头恒为组包裹首子、`:first-child` 恒生效，editor.css:139-149）+ letter-spacing 0.3 + uppercase | 合成 27 / 9、无字距无大写 | insets 改 25 / 3（与卡 inset 3 合成 28 / 6）、补 `.tracking(0.3)` + `.textCase(.uppercase)`（设置页 SectionHeader 已同口径） |
| B-3 | 网格组头（批 C 登记 B9） | 13/600、色 --glass-label-color、letter-spacing .02em、padding 8/2/0、margin-bottom −6（与网格 gap 14 合成距首卡 8） | textSecondary、无负底距 → 合成 14 | 色改 `T.glassLabel`、tracking 0.3、leading 2、bottom −6 → 合成 8 |
| B-4 | 窄屏空状态度量组（批 C 登记 B8） | padding 56/24、gap 8；说明 13 / lh 1.55 / max-width 280；钮 padding 9/22、margin-top 10（editor.css:132-138） | 纵距 48、说明无行距/限宽、钮 16/8 + 上距 6 | 纵距 56、说明 lineSpacing 7 + maxWidth 280 + 居中、钮 22/9 + 上距 10——与 gridEmpty 逐值同（双形态同值由 F30-7 互锁） |
| B-5 | 标签 chip 体系（批 C 登记 B2） | `.glass-tag`：文字 --glass-label-accent（#005BBB/#72B7FF）、control 底 + 1px 边；高：行卡 18（font 10 / lh 18 / padding 0/5）、方卡 20（11 / lh 20 / 0/7）、图文方卡 18（10 / lh 18 / 0/6） | 三处均灰字（textSecondary）、无边、底为平色 tint；高 ≈16 / 18.2 / 14 | 新增令牌 `T.glassLabelAccent`（逐值）；三处 chip 改 accent 色 + `glassControl` 面（材质 + 0.5 边，即本 app 控件面口径）+ `.frame(height:)` 锁高 18 / 20 / 18、横 padding 5 / 7 / 6 |
| B-6 | 头像回退恐龙（批 C 登记 B3） | dino = size − 8（64@72）、圆内底对齐（list.rs AvatarContent） | 0.72 倍（51.8@72）、居中 | `DinoView(size: size − 8)` + `.frame(alignment: .bottom)` |
| B-7 | 紧凑胶囊材质档（批 C 登记 B4） | `.page-title.compact` = --glass-overlay | glassCard（content 档） | `overlayCard(radius: 20)`（首页与各子页共用同一组件，Web 同为 overlay，一并对齐） |
| B-8 | 搜索展开面板材质 + 图标色（批 C 登记 B5 余项，与线 A 同视图顺手） | `.glass-search-panel` = --glass-overlay（底为实色 #FFF/#1C1C1E + backdrop）；面板图标随正文色 | glassCard（content 档）、图标 textSecondary | `overlayCard(radius: 999)`、图标改 `T.textMain` |

其余逐项量对**已对齐、不动**：卡片间距（卡间 6 = 行 insets 3+3）、容器左右距 16、卡内边距 14/16、图/文子列间隔 40（C-A3）、列表底部留白 20（C-A8 尾行 17 + inset 3；网格 bottom 20）、新建卡本体度量与天气块（批 E 后口径）、网格容器/gap/列数/方卡几何、撤销 toast（C-A1）、≥1280 页眉同轴（C-A4）。

### 调优候选（只列不落，待主线/用户裁）

1. **首卡顶距再收紧**：补回 56 后顶区总高仍比 Web 流内少 41（44 空带 + 标题顶 4 与页眉顶 7 之差等结构项）。若真机观感仍觉空，可在 56 基础上议回收 8–12；本批按原版值落，不预收。
2. **标题字重 650**（批 C 登记 B1，5 处）：SF 无 650 档，semibold(600)/bold(700) 各差 50——属平台粒度抉择而非对齐缺失，维持 semibold 登记；若裁改 bold 须五处同改另成一批。
3. **搜索图标尺寸**（B5 余项）：SF 17/15 vs Web SVG 20/18——全 app SF/SVG 度量差的同型表现，单点放大与全 app 图标体系脱节，维持登记。
4. **图文方卡 meta 行高 1.35**（B10）：单行截断下不可见，纯登记、无落码意义。
5. **首组组头上距的场景差**：只读横幅/notice 行在位时，组头上合成 = 横幅 bottom 6 + 组头 top 25 = 31（Web 无对应行，无从对齐）——若观感需要可议横幅行下距与组头衔接，不在本批预设。

### 断言（verify [30]，本机全绿）

F30-1 胶囊焦点单源派生 + 旧标志代码零残留；F30-2 辞焦四路径（submit/clear/离开收敛点计数）；F30-3 双形态滚动收键盘 + Diag 两行；F30-4 顶占位账（132/135、页眉 82）；F30-5 分组头 28/6 + 字距/大写；F30-6 网格组头色/左距/负底距；F30-7 空状态双形态同值互锁；F30-8 chip 令牌/色/高；F30-9 overlay 档两处 + 恐龙 size−8 底对齐。

### 真机终判点（线 B）

1. 首页静止位：新建卡与头像下沿的间隙明显打开（≈56pt，与 Web 同量级），滚动时卡片仍从页眉下穿行、紧凑进度无跳变。
2. 分组头：组与组之间文字上下距均匀（28/6）；英文语境下组名为大写。
3. 空库/零结果/加载失败三态：纵距舒展、说明限宽居中、动作钮变宽（22/9）。
4. 标签 chip：蓝字、带边、高变足（长标题备忘上最易见）；方卡 chip 同。
5. 无头像时恐龙变大且沉底（贴圆底）。
6. 滚动到紧凑态：「此刻」胶囊与搜索展开面板的底色档位与菜单浮层同族（实色 overlay），深色下尤可辨。
7. 网格组头距首行方卡收紧（合成 8）；负底距在 LazyVGrid 下的实际响应以此项为准核（批 C 登记时已注「须实测」）。
