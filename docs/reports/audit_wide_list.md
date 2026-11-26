# 宽屏列表页适配审计（Rust Web vs 原版）— 时间流分组 / 叠卡 / 卡片 / 头部元素

方法：原版列表相关代码完整通读（src/app/memo-list.js、src/app/runtime.js 的 getSectionLabel、src/utils/time.js、src/utils/preview.js、src/components/SwipeRow.js、src/components/ImageCard.js、src/styles/base.css 宽屏块与基础块、src/styles/editor.css 的 .section-header、src/styles/tokens.css）+ Rust 侧对照（rust/apps/web/src/list.rs、src/main.rs 列表渲染段、styles/base.css、styles/editor.css、styles/tokens.css）+ 无头 Chromium 多视口双边实测量测。只审计，未改源码、未构建。

量测口径与环境注记（重要）：
- 视口：1024×768（横屏平板）、1280×800、1440×900、1920×1080、852×393（手机横屏，触发 landscape 矮屏规则）。
- 数据：同一份 16 条夹具 ZIP 双边经各自备份导入通道导入（置顶文+图、今天文 4 条+图 3 条（两组叠卡）、昨天 2、过去7天图+文、过去30天 1、同年 9 月 1、去年 1；含 4 标签、长标题用例），保证双边同数据对照。
- Rust 侧构建戳：量测时生产已升至 **1c9769e990**（sw.js VERSION；wasm md5 `1c9769e990d5…`）。无头 Chromium 过不了本沙箱出口代理（直连被封、代理 CONNECT 报 ERR_TUNNEL_CONNECTION_FAILED），故 Rust 侧采用**生产构建字节级镜像**本地量测：全量下载线上 index.html / mynote-web.js / mynote-web_bg.wasm / sw.js / lang / snippets，wasm md5 与线上 VERSION 戳逐字节核对一致后本地静态服务量测；应用为纯客户端，行为与线上同构建一致。原版侧为仓库 src/ 静态服务（即线上原版源码本体）。
- 全部结论为 Chromium 口径；几何量测误差 ±1px（封面高 1px 级差为亚像素取整，不计分叉）。
- 与 2026-11-21《audit_responsive_report.md》的关系：断点/列数同值结论与该报告一致，本审计在其之上专钻列表场景（分组口径、叠卡、标签、天气、头部轴线），W-1/W-2/W-3 均为新发现，该报告未覆盖。

## 结论计数

- **分叉 2 条**：1 高（分组标签口径错位）、1 中（宽屏标签隐藏规则失效）。
- **缺失 1 条**：1 中（新建卡天气行整体缺失，宽屏方卡底部行空缺）。
- **共同现状/场景观察 3 条**（低，原版即如此、Rust 忠实复刻，仅登记）。
- **已对齐**：断点列数、方卡几何、分组头、叠卡机制与伪层、卡内字号/截断、头部元素、无横向溢出——逐项实测同值（见第四节）。

---

## 一、分叉（按严重度排序）

### W-2（高）同年 >30 天的分组标签错位：原版「N月」，Rust 出「YYYY年」

- 视口：全部（含竖屏；本项属时间流分组口径，在宽屏分组头上同样可见）。
- 原版依据：`src/app/runtime.js:89-105` getSectionLabel——今天 / 昨天 / 过去7天 / 过去30天 / **同年 → `${date.getMonth()+1}月`** / 跨年 → `${year}年`。
- Rust 现状：`rust/apps/web/src/list.rs` section_label 取 `today_info()` 的第一个分量作年比较。today_info 返回 `(day_num, year)`（day_num 为 days-from-civil 计数，量级约 208xx），section_label 写 `let (ty, _) = today_info();`，ty 实际是 day_num 而非 year；随后 `y == ty`（备忘年份 2026 与 208xx 比）永假，同年旧月份全落年标签分支。
- 实测（五视口一致）：夹具中 2026-09-23 的备忘，原版归 **「9月」** 组，Rust 归 **「2026年」** 组（分组头序列：Rust 为 …过去30天 → 2026年 → 2025年；原版为 …过去30天 → 9月 → 2025年）。
- 影响：所有同年、距今 >30 天的笔记在 Rust 里都进「YYYY年」组，与真跨年组标签形态完全相同、不可区分，时间流的月份粒度丢失。注：time_ago 的同年判定取的是 `(_, ty)` 正确分量，未受此 bug 影响（实测卡面时间文案无异常）；分组函数 build_groups 的分桶顺序与位置亦正确，只是标签文本错。

### W-1（中）宽屏标签第 3 个不隐藏，且与「+N」重复计数

- 视口：全部宽视口（1024 / 1280 / 1440 / 1920 / 852 横屏），文本卡与图片卡同病。
- 原版依据：`src/components/SwipeRow.js:43`、`src/components/ImageCard.js:61` 每个标签 span 带 `data-tag-index={ti}`；`src/styles/base.css` 宽屏块规则 `.container .item-tag[data-tag-index]:not([data-tag-index="0"]):not([data-tag-index="1"]) { display: none }` ——宽屏只露前 2 个标签，其余由 `.item-tag-more` 的「+N」概括（N = 标签数 − 2）。标签总数口径双边一致（preview.js 与 Rust summarize 均截 3 个）。
- Rust 现状：`rust/apps/web/src/list.rs` 的 TagList 渲染标签 span 时**不输出 data-tag-index 属性**（全仓 grep 无此属性），宽屏隐藏规则永不命中。
- 实测（五视口一致）：4 标签用例（摘要截为 3）——
  - 文本卡：Rust 三标签 computed display 均为 block（11px），呈现「#alpha #beta #gamma +1」；原版 #gamma 为 **none**，呈现「#alpha #beta +1」。
  - 图片卡：Rust「#图集 #旅行 #风景 +1」（10px，#风景 block）；原版 #风景 none，呈现 2 标签 +「+1」。
  - 1280 截图目验同结论（置顶文本卡：Rust 3 标签 +「+1」，原版 2 标签 +「+1」）。
- 影响：第 3 个标签既完整露出、又被计入「+1」，计数语义错；宽屏方卡内标签行更挤——文本卡 tag-list 为 wrap + max-height 44px，多一行挤占标题/预览区；图片卡 tag-list 为 nowrap + max-height 20px，第三标签在一行内挤压标题与「+N」。

## 二、缺失

### W-3（中）新建卡天气行整体缺失，宽屏方卡底部行空缺

- 原版依据：`src/components/SwipeRow.js:49-52`——新建卡在 weather 有数据时于 .list-item 内追加天气块（温度 `--font-16`/650、城市（英转中）+状况 `--font-12`，右对齐列）；`src/app/memo-list.js` 在列表挂载后拉取天气并缓存。宽屏下 base.css 的 `.container .list-item > div:last-child:not(.item-left)` 规则把该块排成方卡底部行（row、space-between），与 .item-left 的 space-between 共同构成方卡的「标题顶 / 副行与天气底」的版式。
- Rust 现状：`rust/apps/web/src/main.rs`、`src/list.rs` 全无天气代码（grep weather 零命中），list::NewCard 只渲染 .item-left 一个子元素；宽屏 CSS 中对应的 last-child 规则为死规则。方卡（1280 下 288×288）内只有标题贴顶、副行（现在 点击记录你的瞬间）贴底，中底部版式与原版不同（原版底部行还有右侧天气）。
- 量测注记：本次沙箱环境中原版天气接口亦 fetch 失败（控制台「weather ip 兜底失败」，天气块未渲染，双边截图均无天气行），故本项证据为代码级（Rust 无天气子系统）+ 原版结构口径，非截图量差；在可联网环境打开原版即可见差异。

## 三、共同现状 / 场景观察（原版即如此，Rust 忠实复刻；仅登记，若改属产品口径变更）

### W-4（低）超宽屏下头部元素与内容列轴线分离

- 1440/1920 下内容列 max-width 1240 居中（1920 时列 x=340–1580、首卡 x=364），但头像恒在 x=20、搜索胶囊恒距右 20px（双边量测同值）。视口 ≥1560 起，头像/搜索与卡片阵列左右边缘错位约 340px，头部与内容不在同一视觉轴线。原版头部无 max-width 约束，Rust 1:1 复刻。

### W-5（低）矮横屏（852×393）首行方卡一屏不见全貌

- 横屏且高 ≤560 触发 3 列方卡（259×259），叠加头部区约 176px，首行卡底达约 435px > 视口高 393，需滚动才见全卡。双边同值同行为，系原版「横屏切换看板密度」的设计取舍。

### W-6（低/信息）≥1280 只增列数、卡尺寸封顶

- 1280 起 4 列、卡恒 288×288；1920 与 1280 卡尺寸相同，仅两侧留白增大（容器 1240 封顶）。双边同值，原版口径，登记备考。

## 四、已对齐（逐项实测同值）

- **断点与列数**：1024×768 → 3 列；1280×800 / 1440×900 / 1920×1080 → 4 列；852×393 横屏 → 3 列。容器 max-width 1240px、居中偏移（1280 时 x=20、1440 时 x=100、1920 时 x=340）、左右 padding 24px、gap 14px。Rust styles/base.css 宽屏块与原版 src/styles/base.css 对应段 diff 为空（仅标点级空白差），令牌（--radius-26=26px、--font-10..16 等）逐值一致。
- **方卡几何**：aspect-ratio 1/1、border-radius 26px（宽屏），实测卡尺寸 316×316 @1024、288×288 @1280/1440/1920、259×259 @852，双边同值；全部视口 scrollWidth == 视口宽，无横向溢出、无错位拉伸。
- **分组头**：整行跨列（实测宽 = 容器内宽：976 @1024、1192 @1280+、804 @852），font 13px / 600 / glass-label 色，双边同值；分组构成除 W-2 外一致（置顶组恒前、组内图前文后、图/文之间 gap-16 且宽屏隐藏）。
- **叠卡（卡片叠加）**：折叠阈值同为组内同类 >2；折叠态只露首卡 + 卡内「▼ 展开 N 条」按钮（N=组内总数，实测双边文案一致：图组「展开 3 条」、文组「展开 4 条」）；宽屏叠层伪元素 computed 逐值一致——::before transform matrix(0.94,0,0,0.94,0,7) / opacity 0.68、::after matrix(0.97,0,0,0.97,0,4) / opacity 0.86（1280 实测）；展开交互后双边一致（卡数 12→14、图组可见 1→3、叠卡数 2→1）；展开态末卡「▲ 收起」为代码口径一致（main.rs 与 memo-list.js 同逻辑）。
- **卡内细节**：文本卡标题 16px、宽屏 3 行截断（line-height 21.6px；852 实测标题高 65px=3 行，1280 实测 43px=2 行系该标题在该列宽下只占 2 行，双边同）；meta 12px、预览 span 3 行截断（高 52px @行高 17.4，双边同）；图片卡封面 flex 填充（高随列宽：208 @1280、236 @1024）、.img-body 恒 78px、图标题 13px；标签字号文本卡 11px / 图片卡 10px（除 W-1 的隐藏分叉外）；pin-dot 宽屏 7px。
- **头部元素**：头像 72×72 @x=20（玻璃圆/恐龙线稿回退同构）；搜索触发胶囊高 66px、右距 20px；搜索展开面板输入宽 140px（代码口径，base.css 类规则与原版内联口径逐值一致）；紧凑标题胶囊（滚动后「此刻」）fixed 居中，CSS 同文。
- **悬浮按钮**：原版列表页本无 FAB（新建入口即列表首张卡），Rust 同——任务清单中的「悬浮按钮」一项核完为不存在此元素、双边一致（设置/备份页的 .editor-fab 属页面级返回钮，非列表元素）。
- **空态**：.empty-tip 宽屏整行跨列，CSS 同文、渲染口径一致（本次夹具数据非空，未触发截图）。

## 五、证据索引

- 量测数据：/tmp/wl/measure_rust.json、/tmp/wl/measure_orig.json（五视口 + 1280 展开态全量几何）。
- 截图：/tmp/wl/shot_{rust,orig}_{1024x768,1280x800,1440x900,1920x1080,852x393}.png、shot_{rust,orig}_1280_expanded.png、shot_{rust,orig}_stack.png（叠卡特写）。
- 夹具：/tmp/wl/wide_fixture.zip（16 条，双边同导入）。
- 关键代码坐标：原版 src/styles/base.css:289-535（宽屏块）、src/app/runtime.js:89-105、src/components/SwipeRow.js:42-52、src/components/ImageCard.js:60-62；Rust rust/apps/web/styles/base.css:355-601、rust/apps/web/src/list.rs（section_label / TagList / summarize）、rust/apps/web/src/main.rs:701-880（列表渲染）。
