# 全面排查第二轮 · 首页线（列表态 + 宽屏网格态）

只读审计（2026-11-26 晚）。方法按用户口径：先完整读原版相关代码弄清设计用意，再逐项对照原生。

真源链：

- 主真源 = 现行 Web：`rust/apps/web/src/{main,list,weather}.rs`、`rust/apps/web/styles/{tokens,base,editor}.css`、`rust/apps/web/lang/zh-CN.json`。
- 归档原版 = `~/workspace/.scratch/moment-original-archive-2026-11-25/src/{app/memo-list.js,app/runtime.js,components/SwipeRow.js,styles/base.css}`——与现行 Web 有出入处单独标注（本轮仅一处，见 §四组序注）。
- 原生 = `rust/apps/ios/app/MomentApp.swift`。**行号为审计时工作区状态**：HEAD 17d3c79 之上含 i18n I3 未提交在途改动（审计期间该文件仍在被 I3 编辑，行号可能有 ±数十行漂移；结构与数值均按读到的现行代码核证）。I3 只换文案字符串与日期口径接线，不动布局/交互——本审计以结构与数值规格为准，文案类只核文形。

判定口径：**已对齐** / **等价更优保留**（注明为何更优或定案出处）/ **待修**（标感知级或小/微差，给 Web 真值与原生现状的数值证据）。第一轮（`audit_detail_home.md`，86 条）已修项不作新项重报：批 A（0.9.32）2+1 条、批 C（0.9.36）A 级 9 条、批 E 天气子项，逐项回潮核验见 §十一（结论：无回潮）。第一轮 B 级登记项（未修）现状核验见 §十，不计入新待修。

## 一、页眉（头像 / 搜索 / 紧凑胶囊）

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 头像尺寸/形态 | 72×72 圆（list.rs:1599 AvatarContent；归档同） | 72×72（Swift:11147 附近 header 内 AvatarView(size: 72)） | 已对齐 |
| 头像滚动变换 | progress = scrollY/30 钳 0..1；scale 1→0.55、ty 0→−4、opacity 1→0.7、p≥1 才 hidden（main.rs:2003-2013） | 同公式（compactP = scrollOffset/30；scaleEffect 1−0.45p、offset −4p、opacity p≥1→0 否则 1−0.3p）；锚点 .leading = Web transform-origin left center | 已对齐 |
| 头像/胶囊点按 | 头像（h1.page-title）与紧凑胶囊点按均进设置（main.rs:2346、149） | 两者均 nav.dest = .settings | 已对齐 |
| 紧凑胶囊度量 | 17/600、padding 6/16、radius 20、letter-spacing −0.3、line-height 1.2、glass-overlay（base.css:85-107） | 17 semibold、6/16、radius 20、tracking −0.3（Swift CompactTitle）；材质档差见 §十 B4 | 已对齐（材质除外） |
| 紧凑胶囊位置 | fixed、top = safe+7、水平居中（base.css:86-88） | C-A2 已改顶对齐：胶囊顶 = 页眉内容盒顶 = safe+7 | 已对齐（批 C 落地、无回潮） |
| 紧凑呈现 | visibility/opacity 阈值切换、无 transition | 阈值 + 180ms 淡入 | 等价更优保留（0.9.23 定案） |
| 页眉结构/首卡静止位 | 流内：header-actions 44 + 标题区 + container padding-top 46 | 悬浮页眉 82 + spacer 88 | 等价更优保留（0.9.23 真悬浮定案） |
| ≥1280 页眉约束 | W-4 定案：页眉左右内距与搜索 right 同取 (100vw−1240)/2（base.css:618-633） | C-A4 已落：homeW≥1280 时横 padding = (W−1240)/2、未量测回退 20 | 已对齐（批 C 落地、无回潮） |

## 二、搜索胶囊与搜索行为

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 触发态盒 | 高 66、padding 0/18、gap 6、radius 999、glass-control（base.css:286-297） | 高 66、横 18、spacing 6、radius 999、glassControl | 已对齐 |
| 触发文字 | 14、--glass-label-color、letter-spacing −0.1（main.rs:225-228） | 14、T.glassLabel、tracking −0.1（批 E 已修，第一轮 B5 子项销账） | 已对齐 |
| 展开态盒度量 | 高 66、padding 0/14、gap 8、radius 999（base.css:276-285） | 高 66、横 14、spacing 8、radius 999 | 已对齐（材质档见 §十 B5） |
| 输入框 | width 140、height 40、font 15（main.rs:205-213） | frame 140×40、font 15 | 已对齐 |
| 过滤口径 | query 先 trim；matches_search = 标题 + doc 全节点 text + 卡片 meta 白名单字段（text/title/subtitle/source/name/label/alt/description/content）+ 非 data: 的 url 子串匹配（list.rs:758-861；main.rs:1898） | search() 同样 trim；FTS 命中 ∪ 对已加载备忘按同白名单拼 haystack 子串扫描补齐（Swift:1152-1180，注释明载与 Web 的等价边界：附件文件名与卡片顶层 url 两边都不匹配） | 已对齐（实现路线不同、口径同构） |
| 收起行为 | 失焦或 Esc 收起、query 保留（main.rs:196-203）；无清除钮 | 额外 × 钮（清 query + 收起）；无失焦收起 | 等价更优保留（第一轮已定：清除钮为原生增强、失焦不收起属可接受分叉） |
| 紧凑态 | opacity 1→0 + hidden（main.rs:184-186） | opacity 1−p | 已对齐 |
| 图标尺寸/色 | 触发 SVG 20、展开 SVG 18；触发整体色 = glass-label；面板内图标继承 --text-main | SF 17 / 15；触发图标随容器 T.textSecondary、面板图标 T.textSecondary | 待修（微，并入 §十 B5 余项：图标 ±3 为全 app SF/SVG 度量差；面板图标色差一档） |

## 三、行卡（窄屏列表态）

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 文本卡几何 | radius 32、glass-content、0.5 边、padding 14/16、卡内 gap 4、卡间 margin 6、容器横 16（base.css:118、150-169） | glassCard r32、padding 横 16 纵 14、VStack spacing 4、listRowInsets 上下 3/左右 16 | 已对齐 |
| 标题 | 16、单行省略（base.css:170-180） | 16、lineLimit 1 | 已对齐（字重见 §十 B1） |
| 置顶圆点 | 6×6、--color-warning（base.css:183） | 6×6、T.warning | 已对齐 |
| 标题 60% 上限的精确口径 | .item-title-text max-width 60% 的百分比基数是其包含块 .item-title-main；而 .item-title-main 与 .item-tag-list 各 flex:1（flex-basis 0%，min-width 0）——**有标签时两者恒各占行宽约一半，标题上限 ≈ 60% × 半行 ≈ 30% 行宽、标签区 ≈ 半行；无标签时 tag-list 不渲染（list.rs:1156 TagList 空不渲染；归档 SwipeRow.js:42 同条件），main 独占整行、上限 = 60% 行宽**（base.css:170-177；归档 base.css:165-172 同构） | C-A7 以 GeometryReader 恒按 0.6 × 整行宽截断（Swift titleRow），仅无标签时与 Web 吻合；有标签时长标题可多显约一倍才截断、标签区被压到剩余 ≈40% | **待修（小）**——第一轮把真值读作「标题 max-width 60%（行宽）」不精确，C-A7 据此落地；本轮按 flex 链推导更正 |
| 图文卡标题上限 | .img-card-title-text 无 max-width，仅 min-width 0 + 省略，占标题行余宽（base.css:197；list.rs:1394 同行结构） | titleRow 与文本卡共用，图文卡同样套 60% 上限 → 长标题截断更早 | **待修（微）**（与上行同根：titleRow 不分卡型） |
| 标签个数/「+N」 | scan 上限 3；窄屏 .item-tag-more display:none（base.css:178） | prefix(3)、窄屏不显 +N | 已对齐 |
| chip 间距 | .item-tag-list gap **4**（base.css:177） | titleRow HStack spacing 6，chip 间亦 6 | **待修（微）**（+2；方卡侧 gap 与 Web 宽屏值一致，见 §九） |
| chip 色/高/边 | .glass-tag：accent 蓝字 + control 底 + 1px 边（base.css:354-358）；行卡高 18（list.rs:1164-1172） | 灰字、无边、高 ≈16 | 待修（第一轮 §十 B2 登记，本轮核验未修，非新项） |
| meta 字号/文形 | 12；文本卡「{ago}␣␣{摘要}」、图文卡「{ago} · {摘要}」同段截断（list.rs:1497、1394） | 12（ScaledMetric 跟随 Dynamic Type 为已定案口径）、同形同截断 | 已对齐 |
| **meta 文字色** | **.item-meta 与 .img-text .m 的 color 由 base.css:359-367 的组规则定为 --glass-label-color（#48494F / 深 #D1D1D6）**——该组规则在文件后部、同为单类选择器，覆盖 base.css:184 自身的 --text-secondary 声明；归档 base.css:276-284 同一组规则、同覆盖关系 | metaRow 与两类方卡 meta 均 T.textSecondary（#68686D / 深 #98989D）（Swift metaRow、squareTextCard、squareImageCard）；C-A6 只把展开钮改到 T.glassLabel，meta 文本未动 | **待修（感知级·小）**——浅色差一档、深色差显著（#98989D vs #D1D1D6）；新建卡副行同病（见 §五）。T.glassLabel 令牌已存在，属逐处换色 |
| 摘要截断长 | 文本卡 80 / 图文卡 60（list.rs:1224） | prefix(80/60) | 已对齐 |
| 时间格式 | time_ago：今天→时刻（24h HH:MM 补零 / 12h 上午·下午 h:MM）、昨天、同年 M/D、跨年 Y/M/D（list.rs:922-965） | ago 四分支同构（今天经 Fmt.timeOfDay、locale 随 app 语言，I3 接线） | 已对齐 |
| 展开/收起钮 | .expand-btn 玻璃药丸：11、padding 4/10、radius 14、1px 边、glass-label 色、居 meta 行右端（base.css:199-205） | C-A6 已落同值药丸（Swift metaRow） | 已对齐（批 C 落地、无回潮） |
| **折叠卡整卡点按** | 折叠态首卡的 on_open 被替换为展开动作：点整卡 = 展开该子列，不打开编辑器（main.rs render_sub 折叠分支，文本/图文同）；展开后各卡恢复打开语义 | memoRow 的 onTapGesture 无条件打开编辑器（Swift memoRow），展开仅能点 meta 行药丸；网格侧 squareCard 则正确地先判 expand | **待修（感知级）**——窄屏折叠组主手势语义与 Web 相反（点开成编辑器而非展开），网格侧无此问题 |
| 图文卡封面/体 | aspect 16/9、上圆角 32 下 0；体 padding 10/16/12、标题 15（base.css:193-200） | aspectRatio 16/9 + 整卡 clip r32；体 横 16 上 10 下 12；标题 15 | 已对齐 |
| 左滑动作 | 自绘双钮 68×44、radius 22、区宽 168、图标 17 + 文字（置顶/取消、删除；action.unpin 文案即「取消」，zh-CN.json 实证） | 系统 swipeActions：删除（T.danger #E0433A = --color-danger）、置顶（.orange = --color-warning #FF9500），顺序同为删除在最外侧，文案「置顶/取消」与语言包一致 | 等价更优保留（左滑系统实现已定案；色值/顺序/文案逐项核对一致） |
| 行高固定与字号缩放 | Web 固定 px、无 Dynamic Type 概念 | titleRow 行高写死 20，而标题字号经 titleFontScale（@ScaledMetric）随 Dynamic Type 放大——大字号档下 16pt×scale 的行高超过 20 的固定行盒，有挤压/裁切风险 | **待修（微，待核）**——仅大 Dynamic Type 档显形；与 meta 的 ScaledMetric 定案同面，行盒应随 scale 同步 |

## 四、分组与排序（功能口径）

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 归组日期 | createdAt 优先、缺失回退 updatedAt（list.rs:863 build_groups） | bucketDate 同口径 | 已对齐 |
| **分组日期边界** | section_label：diff ≤ 0 今天、=1 昨天、**≤7 过去7天、≤30 过去30天**、同年 {m}月、跨年 {y}年（list.rs:730-757）；归档 runtime.js:89-104 以 date ≥ today−7d / today−30d 同界 | bucket：days < 7 → week（即 2..6）、days < 30 → month（即 7..29）（Swift groups bucket） | **待修（感知级）**——恰 7 天整的备忘 Web 入「过去7天」、原生入「过去30天」；恰 30 天整 Web 入「过去30天」、原生落「{m}月」。两处 off-by-one，两真源一致、非口径争议 |
| 组内排序 | sorted_refs：置顶在前、其余 updatedAt 倒序（稳定排序）（main.rs:1022-1031） | Library.memos 同序（undoDeletion 回插时亦按 pinned/updatedAt 重排） | 已对齐 |
| **组序** | build_groups 按扫描序（updatedAt 倒序）**标签遇见序**成组：编辑一篇旧备忘会把它的日期组顶到置顶组之后的第一位（list.rs:863-906 按标签归并）；归档 groupedItems 为连续成组、序同为遇见序（memo-list.js:421-458） | 固定桶序：今天→昨天→过去7天→过去30天→月/年按最新倒序（Swift groups） | **待修（小）**——组序在「编辑旧篇」场景分叉。注：原生固定序更可预测，亦可由用户改判等价保留；但与两真源均不一致，先按待修登记、附此说明 |
| **置顶刷新时间** | togglePin 翻标记**同时 updatedAt = now**（list.rs 两处 on_pin；归档 memo-list.js:302-308 同）→ 该篇 ago 变「现在」、在置顶组内按更新序置前 | Library.togglePin 只翻 pinned 后 persist，不动 updatedAt（Swift:720-727） | **待修（感知级·小）**——置顶后时间戳与组内序两边不同；取消置顶同理 |
| 分组头本体 | 14/600/--text-secondary、padding 24/4/6（editor.css:139-149） | 14 semibold、T.textSecondary、insets top 24/leading 20/bottom 6 | 已对齐（tracking 与组间合成差见 §十 B6） |
| 图/文子列间隔 | img 组 margin-bottom 24 + .gap-16 高 16 = 40（base.css:111-125、205） | C-A3 已落间隔行 34（合成 3+34+3=40） | 已对齐（批 C 落地、无回潮） |
| 列表底部留白 | .container padding-bottom = 20 + safe（base.css:108） | C-A8 已落尾行 17（合成 3+17=20） | 已对齐（批 C 落地、无回潮） |

## 五、新建卡与天气（窄屏）

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 新建卡盒/标题/副行 | 同 .list-item；标题「新建笔记」16/600/--text-secondary；副行「现在␣␣点击记录你的瞬间」12（base.css:179-190；list.rs:1505-1568） | 同口径（Swift newCardRow） | 已对齐（副行色见下行） |
| 新建卡副行色 | 副行在 .item-meta 内 → glass-label 色（同 §三 meta 色行） | T.textSecondary | 待修（并入 §三 meta 色行，同根同改） |
| 天气块结构 | .newcard-weather：纵列右对齐、gap 4、padding-left 12；温度 16/650/lh 1.1/字距 −0.5；城况 12/lh 1.2「{城市} {状况}」（base.css:188-190；list.rs:1520-1528） | 纵列右对齐、VStack spacing 4、padding.leading 12、温度 16 semibold + tracking −0.5、城况同文形（Swift newCardRow） | 已对齐（批 E 已修 gap/tracking 两子项，第一轮 B7 部分销账；字重见 §十 B1） |
| 天气最小间隔合成 | 左列与天气文案的最小横距 = .list-item gap 12 + 天气块 padding-left 12 = 24 | HStack spacing 10 夹 Spacer 两侧（10+10）+ 天气块 leading 12 → Spacer 压到 0 时 ≈32 | **待修（微，待核）**——仅左列文案长到顶格时显形；HStack 对 Spacer 两侧 spacing 的合成按代码读数推得，建议量测确认后与 B7 余项一并处理 |
| 天气缺数 | 无数据整块不渲染（list.rs NewCard weather: Option） | weather.now 为 nil 不渲染 | 已对齐 |
| 城市名来源 | to_cn 映射 | 系统地理编码 | 等价更优保留（0.8.6 已定案原生更优口径） |

## 六、撤销 toast 与删除窗口

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 撤销条形态 | .backup-toast 全宽条：左右 16、bottom = safe+16、radius 28、glass-overlay、padding 14/16、gap 10、del 图标 19、文字 14/500/lh 1.35、撤销钮 14/600 + padding 6/10（base.css:660-680；main.rs 撤销块） | C-A1 已落同值全宽条（Swift undoToast：overlayCard r28、trash 19、14 medium、钮 semibold + 6/10、左右 16、底 16） | 已对齐（批 C 落地、无回潮；底距以根 ZStack 底 = safe 底为前提，计划注记的真机一帧核对仍未决，属既有未决前提、非本轮新发现） |
| 撤销条进场 | toastSlideUpBar 220ms 弹簧（上滑 24 + scale .94→1 + 淡入） | move(.bottom)+opacity、spring 0.28 | 等价更优保留（第一轮已判近似等价） |
| 撤销窗口 | UNDO_WINDOW_MS = 8000（main.rs:1284） | softRemove 8 秒后真删 | 已对齐 |
| 多篇待删口径 | 每篇独立 deletedAt 标记、各自 8 秒到期真删；标记落盘、窗口内杀进程重开仍可恢复计时（list.rs:1052-1058 及 main.rs 到期任务） | 单槽 pendingDeletion：删第二篇时第一篇立即真删落盘（Swift Library.softRemove 先 commitPendingDeletion） | **待修（微）**——连删两篇时第一篇的撤销机会提前归零、且不落盘标记；单篇场景两边一致 |
| notice 行 | Web 首页无对应物 | 12px 次级色行 | 等价更优保留（原生诊断通道呈现面，已定案） |

## 七、摘要 / 标签 / 封面取数（内容口径）

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 摘要取材 | 遍历全部 paragraph、各取首个子节点文本、trim 非空计入（list.rs:620-668） | paraFirstTexts 全段遍历同口径（批 A 已修） | 已对齐（无回潮） |
| 摘要取材细差 | 取「首个子节点」的 text，首子无 text 则该段不计（list.rs:631-640） | 取首个「有 text 的」子节点，另对 link 子节点下钻取文（Swift paraFirstTexts） | **待修（微）**（并入下行保真度项）——首子为空文本/非文本节点而次子有文时，两边摘要有无不同 |
| **摘要剥 MD 保真度** | strip_markdown 约 25 趟规则链：脚注定义/引用删除、wiki 链取文、$$…$$ 与行内 $…$ 取文、上/下标取文、==高亮== 取文、**```围栏整段替换为「 代码块 」**、代码段取文、图取 alt、链取文、行首 #/>/列表标记剥离、成对 **/__/*/_/~~ 剥离、空白折叠（list.rs:71-98 及各 try_* 匹配器） | summary() 为简化剥离：链接展开、行首 #/>/-·*·+ 剥、分隔符 **/__/==/~~/`/* 全局删除、标签剥、空白折叠（Swift:10302-10307 段） | **待修（小）**——含代码围栏的段落：Web 摘要显「代码块」、原生显代码原文；含公式/脚注/wiki 的段落文形亦分叉。原生已有 core 侧 MD 解析（FFI），摘要未接 |
| 标签取数 | 全段落 scan_tags、上限 3、含 # 原样（list.rs:22-46、645） | 全段扫描同口径、上限 3、存储不含 # 渲染拼 #（显示同形） | 已对齐（无回潮） |
| 图文卡判定与封面（附件图） | has_image = 图类块 ∪ attachment image 标志 ∪ **cover_source 命中**；cover 对 attachment 按 manifest 类型/扩展名判图（att_file_is_image_raw，清单名优先、节点名兜底）（list.rs:674-690、992-1050） | hasImageShape 只看 attrs 里 items/name 的扩展名集合；cover 探针的 attachment 分支仅认 image 标志（Swift hasImageShape、cover 探针） | **待修（小，待核）**——image 标志为假且 attrs 无名/无扩展名、仅 manifest 记类型的图片附件：Web 渲图文卡 + 封面，原生渲文本卡无封面。实际存量中该形态占比待核 |

## 八、空状态

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 三态构成（窄屏） | 同一 EmptyState：加载失败（warning 图标）/ 空库（file-text）/ 搜索零结果（search），标题 + 说明 + 单一动作钮（main.rs:2380-2410） | emptyRow 三态同构（图标 SF 替代） | 已对齐（图标替代为等价更优，第一轮已定） |
| 文案 | load_error_sub 全文、search_sub 全文、search_title = 未找到「{q}」、empty_tip = 暂无笔记，点击上方新建（zh-CN.json） | C-A9 已落全文两条；三态文案与语言包逐字一致（I3 后经 Lang 键） | 已对齐（批 C 落地、无回潮） |
| 度量组 | padding 56/24、gap 8；说明 13/lh 1.55/max-width 280；钮 padding 9/22、margin-top 10（editor.css:132-138） | 纵 padding 48、说明无 lineSpacing/无 maxWidth、钮 16/8 + top 6 | 待修（第一轮 §十 B8 登记，本轮核验未修，非新项） |

## 九、宽屏网格态

| 元素 | Web 真值 | 原生现状 | 判定 |
|---|---|---|---|
| 判定/列数/gap/容器 | ≥768 或横屏且高 ≤560；3 列、≥1280 四列；gap 14；max-width 1240 居中、横 padding 24（base.css:371-383、614-617） | 同值（syncHomeSize / gridHome） | 已对齐 |
| 方卡几何 | aspect 1/1、radius 26、padding 14、内部 gap 8（base.css:404-427） | 同值（squareTextCard / newCardSquare） | 已对齐（字重见 §十 B1） |
| 方卡标题/meta | 标题 16/650、lh 1.35、clamp 3；meta 12、摘要 clamp 3、lh 1.45（base.css:437-507） | 16 semibold、lineSpacing 5.6（=1.35）、lineLimit 3；meta 12、lineSpacing 5.4（=1.45）、lineLimit 3 | 已对齐（字重、meta 色除外：色并入 §三 meta 色行） |
| 方卡置顶点 | 7×7、margin-top 7（base.css:462-465） | 7×7、padding top 7 | 已对齐 |
| 方卡标签 | 11、lh 20、padding 0/7、高 20、gap 6、前 2 + 「+N」、max-height 44（base.css:467-495） | 11、padding 横 7 纵 2.5（高 ≈18.2）、spacing 6、前 2 + +N | 待修（§十 B2 高差登记，核验未修；gap 已对齐） |
| 图文方卡 | 封面 flex 填充上圆角 26；体高 78、padding 10/12；标题 13/650/lh 1.25 单行；标签 10/lh 18/padding 0/6、max-width calc(50%−2px)；meta 12/lh 1.35（base.css:521-572） | 封面填充 + 整卡 clip 26；体 78、10/12；标题 13 semibold 单行；标签 10、padding 横 6 纵 1（高 ≈14）；meta 12 无 lineSpacing | 待修（§十 B2 高差 + B10 行高登记，核验未修；余已对齐） |
| 幽灵叠卡 | ::before scale .94/y+7/opacity .68；::after .97/+4/.86；radius 26（base.css:583-605） | 同值两层 RoundedRectangle | 已对齐 |
| 网格组头 | 13/600、padding 8/2/0、margin-bottom −6（距首卡合成 8）、色 --glass-label-color、letter-spacing .02em（base.css:390-401） | 13 semibold、T.textSecondary、padding top 8、无负下距（距首卡 14） | 待修（§十 B9 登记，核验未修；色差与 §三 meta 色同令牌族） |
| 网格新建方卡天气 | 底部整行：温度左、城况右、同行（base.css:514-520 + 188-190） | C-A5 已落同排布 | 已对齐（批 C 落地、无回潮） |
| **网格空状态** | 同一 EmptyState 三态（含搜索零结果：标题含 query、说明 search_sub、动作「清除搜索」），grid-column 1/-1（main.rs:2380-2410；base.css:403） | gridEmpty 只有 loadFailed / 空库两态：**搜索无结果时（visibleMemos 空）误显空库态**——标题「还没有备忘」、说明为自造文案、动作「新建备忘」（Swift gridEmpty） | **待修（感知级）**——宽屏搜索零结果呈现错误状态与错误动作；窄屏 emptyRow 三态齐全、独网格缺一态 |
| 网格空库说明文案 | list.empty_tip「暂无笔记，点击上方新建」 | gridEmpty 作「暂无笔记，点击新建卡创建」 | **待修（微）**（与上行同视图，一并改） |
| **方卡折叠/收起钮形态** | 折叠与收起钮与窄屏同为 meta 行内 .expand-btn 玻璃药丸——MemoRow 的 expand_text 与布局无关，网格渲染同一组件、同一钮（list.rs:1189-1503；base.css:199-205） | squareFoldRow 与 squareImageCard 收起钮均为 12 号 accent 纯文字、无底无边，且位于 meta 行之外的独立行（Swift squareFoldRow、squareImageCard） | **待修（小）**——第一轮 C-A6 以「Web 网格折叠走整卡点按、无同名对应物」将方卡侧排除在药丸化之外；经查排除前提不成立：Web 网格卡内确有药丸钮（整卡点按展开是额外路径、两边都有）。钮的纵位亦差一行 |
| 网格长按菜单 | Web 网格无长按菜单（点按打开/展开） | contextMenu：打开/置顶/删除 | 等价更优保留（无左滑的补偿通道，第一轮定案配套） |
| 网格底部距 | padding-bottom 20 + safe | padding bottom 20 | 已对齐 |

## 十、第一轮 B 级登记项现状核验（未修、非新项）

| 登记项 | 现状（本轮复核） |
|---|---|
| B1 标题字重 650 系统性（行卡/方卡/图文方卡标题、新建卡温度 ×2） | 仍全为 semibold 600，未动 |
| B2 chip 色 + 三处高（行卡 18 / 方卡 20 / 图文方卡 18） | 色仍 T.textSecondary、无边；高仍 ≈16 / 18.2 / 14，未动 |
| B3 头像回退恐龙（Web size−8=64、底对齐） | 仍 DinoView(size×0.72≈51.8)、居中（Swift AvatarView），未动 |
| B4 紧凑胶囊材质（Web glass-overlay） | 仍 glassCard（content 档），未动 |
| B5 搜索四小差 | 触发文字色/字距已由批 E 修复销账；余：图标 17/15 vs 20/18、展开态材质 content vs overlay、面板图标色一档，未动（见 §二末行） |
| B6 分组头 tracking 0.3 + 组间合成距（Web 28/6 vs 原生 27/9） | 未动 |
| B7 窄屏天气两小差 | gap 4 与温度字距 −0.5 已由批 E 修复销账；余项转为 §五「天气最小间隔合成」微项 |
| B8 窄屏空状态度量组 | 未动（见 §八末行） |
| B9 网格组头（合成距 +6、色、tracking） | 未动（见 §九） |
| B10 图文方卡 meta 行高 1.35 | 未动（见 §九） |

## 十一、回潮核验（批 A / C / E 已修项逐项复查）

- 批 A（0.9.32）：摘要全段取数 ✓、标签全段扫描 ✓、gridEmpty 度量（16/13+lineSpacing 7+maxWidth 280/钮 22·9+top 10/纵 56）✓——均在现行代码中属实，无回潮（gridEmpty 的问题是缺搜索态，属新发现、非度量回潮）。
- 批 C（0.9.36）A 级 9 条：C-A1 toast 整组 ✓、C-A2 胶囊顶对齐 ✓、C-A3 子列间隔 34 ✓、C-A4 ≥1280 页眉 ✓、C-A5 网格天气行 ✓、C-A6 展开钮药丸 ✓、C-A7 标签布局（按其当时目标值落地；目标值本身的精度问题见 §三新项）✓、C-A8 底部尾行 ✓、C-A9 文案两条 ✓——无回潮。
- 批 E：搜索触发文字 glassLabel + tracking ✓、天气列 gap 4 / leading 12 / 温度 tracking −0.5 ✓——无回潮。

## 待修汇总（按感知级排序，仅本轮新项）

**感知级（5 项）**

1. **分组日期边界 off-by-one**（§四）：恰 7 天整、30 天整的备忘归组与 Web/原版不同（原生 days<7、days<30；真值 diff≤7、diff≤30）。
2. **窄屏折叠卡整卡点按语义相反**（§三）：Web 点整卡展开、原生点整卡打开编辑器；网格侧正确、独窄屏错位。
3. **网格空状态缺搜索零结果态**（§九）：宽屏搜索无结果误显空库态 + 「新建备忘」错误动作。
4. **meta 文字色令牌错**（§三，含 §五副行、§九方卡 meta）：原生全用 T.textSecondary，真值 --glass-label-color；深色模式下差最显（#98989D vs #D1D1D6）。
5. **置顶不刷新 updatedAt**（§四）：Web/原版置顶同步刷新时间，原生只翻标记——ago 与置顶组内序不同。

**小差（5 项）**

6. 组序遇见序 vs 固定桶序（§四，附改判说明）。
7. 摘要剥 MD 保真度（§七）：代码围栏应显「代码块」、公式/脚注/wiki 等规则缺失（连带取材细差微项）。
8. 标题 60% 上限基数（§三）：有标签时真值 ≈30% 行宽，原生恒 60%（第一轮读数更正项）。
9. 方卡折叠/收起钮形态（§九）：应为 meta 行内玻璃药丸，原生为独立行纯文字（C-A6 排除前提不成立）。
10. 附件图封面/图文卡判定（§七，待核）：manifest 判图口径未接，attrs 无名/无扩展名的图片附件会漏判。

**微差（6 项）**

11. 图文卡标题误套 60% 上限（§三）。
12. titleRow chip 间距 6 vs 4（§三）。
13. gridEmpty 空库说明文案自造（§九）。
14. titleRow 固定行高 20 与 Dynamic Type 缩放冲突（§三，待核）。
15. 天气块最小间隔合成 ≈32 vs 24（§五，待核）。
16. 多篇待删单槽口径（§六）：连删时前篇立即真删、不落盘标记。
