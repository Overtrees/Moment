# 首页及非编辑页全面深挖审计（2026-11-27）

> 状态：**只读审计完成，未落任何代码**。基线 HEAD 477b1bc（0.9.57）。工作树 MomentApp.swift 有他线在途未提交 diff（卡间距线），涉及其 hunk 的条目以 HEAD 已提交代码为准并单独注明。
> 范围：首页、图片页、设置族、天气二级页、桥设置、救援/安全模式与 OPS 面、启动链。**不在范围**：编辑页（另一条线）、首页竖屏卡间距（间距线在跑，本报告仅交叉引用其落账风险，见 §6）。
> 真源：Web 源码（list.rs/main.rs/settings.rs/weather.rs/blocks.rs + styles）为第一真源，原生既有定案（各 audit/fix/impl 报告）为第二真源。
> 判读值域：达标 / 缺陷 / 缺失 / 定案偏离。证据分级：proven（源码机制实证）/ inferred（代码可读但结论依赖运行时、手势、系统或外部服务）/ unknown。涉真实手势、系统面板、外部服务者证据上限 inferred，终判归属逐项标注。
> 主线 spot-verify：本报告五处承重断言已由主线独立 grep 复核属实——@ScaledMetric 全仓恰 3 处（MomentApp.swift:15456-15460）、searchHits 仅在 search() 内赋值（2047 起）、armWatchdog 定义 745 行且仅在 load() 内 899 行被调用（459 行注释自证 load() 由 ListView.onAppear 触发）、设置页版本字面量 Text("0.9.57") 在 17395 行且 verify_ios.sh:44 以 head -1 位置假设取值、判图扩展集含 "svg"（14024 行）。

---

## 1. 总判与缺陷分级汇总

三线共审 36 项：达标 22、定案偏离 3、含缺陷/缺失 11 项（缺陷点合计 P2 ×8、P3 ×20 上下，无 P1）。两批刚落地的修复面（搜索两线、首页布局线、救援布防、桥稳定性呈现面）逐项回源复核**无回潮**。新发现集中在三处此前审计的盲区：**定案只核了行形态没核实效面**（文字大小）、**救援链的跨面相撞**（看门狗 arm 点、清缓存×只读副本、只读编辑入口）、**状态新鲜度**（搜索命中集、OPS 生效口径表述）。

### P2（按建议处理顺序）

| # | 缺陷 | 面 | 证据 | 矩阵 |
|---|---|---|---|---|
| P2-1 | 文字大小「跟随系统」定案大面积未实装：全仓 @ScaledMetric 仅 ListView 三处（组头/列表标题/meta），设置族、编辑器正文、图片页等 182 处固定 .system(size:) 不随 Dynamic Type 缩放——行文案承诺与实效不符 | 设置/全局 | proven | 增补候选（SET 族新行） |
| P2-2 | 启动看门狗 arm 点在 load() 内、load() 由 ListView.onAppear 触发：根视图/ListView 构建期挂死时 onAppear 永不达，看门狗从未 arm、救援浮条永不出。Web 救援层在 index.html 内联、不依赖 App 主体构建 | 启动 | proven | LCH-09 增补 |
| P2-3 | 正常模式下无任何手动救援入口：设置/Diag 页无 bootMode=.safe 写入点，Web ?rescue=1 在原生无等价物。App 能跑但劣化（缓存损坏型）时用户无路可达救援页，只能等 streak 攒满 | 救援 | proven | LCH-04 增补 |
| P2-4 | 清缓存与只读副本相撞：只读副本在 tmp（moment-rescue-ro），经横幅回救援页时只读句柄仍开着副本，此时清缓存 clearContents(tmp) 会删掉正被 SQLite 打开的副本三件套 | 救援/只读 | proven（共域）/后果 inferred | LCH-06 增补 |
| P2-5 | 只读态编辑入口未禁用：既有卡片仍可点进编辑页打字，仅在 persist 时被 writeBlocked 拦下弹 notice，编辑成果当场丢失且入口无只读预期。S4 定案只定了「门面拒写+横幅」，入口面未定，须用户裁定后落定案 | 只读 | proven | LCH-05 增补 |
| P2-6 | OPS 生效口径双轨与定案表述漂移：注释/头注宣称「恒下次启动生效」，但附件类型、Diag 冻结写盘、天气刷新、分发器 forceSafe 紧缩四面实时读 cached()，ops_refresh 会话中段即改行为。行为本身 fail-safe，失真在定案表述与回读口径 | OPS | proven | LCH-07 |
| P2-7 | SVG 附件进图片页解码死路：判图扩展集含 svg、附件行会把 SVG 送进图片页，但 decodeImage 走 CGImageSource/UIImage 无 SVG 光栅解码，恒落「图片加载失败」且原分享路被截断；Web `<img>` 可直渲 SVG。低频 | 图片页 | proven | IMG-01 增补子行 |
| P2-8 | LAUNCH 判读误报面：加载步内用户手动强杀、系统 jetsam 回收与真崩溃代码上不可分，一律 streak+1、两次即进安全模式。iOS 无退出原因 API，属平台事实，现行缓解只有「==1 不进」；漏报面为退后台清 busy 后被杀恒不留痕（设计口径） | 启动 | proven（机制）/归类 inferred，终判归真机 Diag | LCH-02 |

### P3（汇总，细节见各节）

首页：搜索命中集陈旧（编辑返回/重载不重算 searchHits，§2.1，**本轮首页唯一功能性新发现**）；页眉命中死区 p∈[0.5,1) 三件皆不可点（§2.8）；网格图文方卡折叠态无「展开 N 条」药丸（§2.12）；网格组头缺 uppercase（§2.12）；横幅/notice 在位时首组头合成距 31 vs 常态 28、网格更松，未决（§2.9）；搜索 haystack 与 Web walk 三处细差（§2.1）；左滑/网格菜单动作不辞焦（已登记微分叉，§2.1/§2.5）。
图片页：无名图回退文案三处硬编码「图片」+「图片加载失败」未走语言包（§3.3）；非 GIF 动图帧时长兜底与 APNG 支持 unknown（观察项，§3.2）。
设置族：天气 key 改/清后无主动刷新、生效依赖 ListView onAppear 重入（inferred，§4.7）；桥远程切语言时编辑器未观察 LangStore 文案不即时刷新、followSystem 运行中改系统语言不重解析（§4.5）；导入边沿——commit 成功但 stats 解析失败会误报「导入失败（现有数据未动）」而数据其实已换（inferred 边沿，§4.8）；stagedStats 只写不读死字段（§4.8）；导出 toast 锚在生成成功而非分享完成（§4.8）；verify [1] 版本取值靠 head -1 位置假设、上方新增数字字面量 Text 会静默比错对象（§4.12）。
启动/救援：冷启失败路径无 SMOKE 对应行、发版清单按 SMOKE 检索会漏计失败冷启；「首帧」步痕与 firstFrameMs 双口径无注记（§5.1）；哨兵 launchMark/markScene 无锁 RMW 并发写可致步名回退/丢失（inferred，§5.2）；安全模式内强杀致 streak 展示值单调虚增（不影响判定，§5.2）；看门狗 12s 固定阈值不随库量缩放、大库冷启误伤仅限呈现层（§5.3）。
桥呈现：桥布防 reason 对用户不可见（被远程布防进安全模式不知为何，§5.5）；scopes 空集 UI 兜底显「只读」与实际授权可不一致、write 未授无负向呈现（§5.10）；backoff 状态不带 reason 上屏、连接失败原因只入 Diag（§5.11）；配对无二维码（缺失，待用户裁是否补）、重配对无显式入口且吊销中继回执用户零感知、待配对过期时刻不呈现（§5.9）；BootMode source 注记漏 watchdog/manual 与代码漂移（§5.4）；ops_validate 把核心步名列为「合法步名」给发布者错误预期（§5.8）；只读期桥分发呈 full 形态与门面拒写的回码一致性未验（inferred，§5.6）。

### 定案偏离（非缺陷，登记在案）

- 折叠展开键：原生 `{bucketId}-{kind}` 语言无关（防切语言丢展开态），Web 为本地化 label 键——原生有意更优（§2.3）。
- 只读横幅与 notice 行：Web 无对应物，系原生自救 S4 定案的呈现面（§2.9）。
- OPS 实时紧缩方向：步 guard/分发紧缩实时生效属 fail-safe，偏离仅在「恒下次启动」的表述（P2-6）。

---

## 2. 首页（12 项）

**2.1 搜索全链｜达标（主体）+缺陷 P3｜proven／焦点实效 inferred（终判归真机）｜HOM-03/04/05**
现状：searchCapsule（MomentApp.swift:16049-16120）字段常驻、宽 0↔140 由 searchFocused 派生、触发层真 Button 走 activateSearch()；resignSearch()（15835）被 createAndOpen/openMemo/头像/紧凑钮四漏斗调用；onSubmit src=submit 辞焦、清除钮清词+src=clear、双形态 scrollDismissesKeyboard。过滤走 library.search（16062）→FTS ∪ haystack 补扫（2047-2095、2136-2180），匹配域与 Web 白名单同构（list.rs:758-861）。**匹配高亮两边皆无**（Web try_highlight 是 MD 摘要剥离、非搜索高亮），一致无缺失。空结果三态齐全，「清除搜索」只清词不辞焦与 Web 同口径（点按后焦点去向 inferred 归真机）。搜索态下 visibleMemos（15498-15503）过滤后归组，置顶/折叠正确穿透。
差：**(a) P3 命中集陈旧（主线已复核）**——searchHits 仅在 search() 内赋值，persist/编辑返回/reload 均不重算；Web 为每渲染反应式重滤（main.rs:1895）。后果：结果中打开一篇删掉关键词、返回首页该篇仍在结果里，下一键才自愈。提案：persist 与 reload 收口处若 searchHits != nil 以现 query 重跑一次。（b) haystack 三处 walk 细差（原生 items 下钻 text、meta.url 未查 data: 前缀、meta 只读顶层键），双向微量命中差，audit2 判同构不翻案，登记候选待裁是否收严。（c) 左滑/网格 contextMenu 的置顶·删除不辞焦（16461/16470、16805/16798 未调 resignSearch），已登记微分叉仍在。

**2.2 时间流分组｜达标｜proven｜HOM-06**
assembleGroups（15620-15690）：bucket() 用 Calendar.current.startOfDay 日历日差，≤0 今天／=1 昨天／≤7 过去7天／≤30 过去30天／同年 m-月／跨年 y-年，audit2 的 off-by-one 已修含端点。归组键 bucketDate（14096）= **createdAt 优先、失败回退 updatedAt**，与 Web created>0 优先同口径。组序 = 置顶剔除后 updatedAt 倒序的标签遇见序；组内序由 persist/undo 的 sort 维护。跨时区漂移两边同幅、行为一致非缺陷；无 24h 滑动窗误用。

**2.3 折叠组「展开 N 条」｜达标｜proven｜增补候选（矩阵无独立行，建议 HOM-06 子行）**
sublist/gridSublist（16124-16148、16265-16290）同构：子列 count>2 且未展开只显首卡，N=memos.count 总数口径与 Web n=total 同（两边同「名实差一」但一致）；展开态末卡带 collapseHint；窄屏整卡点按+药丸双路、网格整卡点按+方卡药丸。存储域 NavState.expandedKeys 内存集不落盘，Web use_signal 同为会话内存，等价。展开后无 scroll-into-view、原地增高，两边同。定案偏离：展开键原生 bucketId 语言无关 vs Web label 键，原生更优（见 §1）。

**2.4 置顶与排序｜达标｜proven｜HOM-06/09**
入口全集：窄屏仅左滑置顶钮（16851-16863）、网格仅 contextMenu（16461-16471），与 Web 仅 swipe 钮同。置顶独立组恒居首、组内再分图/文子列。togglePin（1390-1403）→persist 无条件 updatedAt=now 并按 pinned/updatedAt 全表重排——audit2「置顶不刷新 updatedAt」已销账；被置顶篇 ago 跳「现在」是 Web 原版行为本身。Swift/Rust 均稳定排序、ISO 串字典序=时间序。

**2.5 左滑动作｜达标（系统实现定案）｜proven／手势互斥 inferred 归真机｜HOM-09**
swipeActions(edge:.trailing, allowsFullSwipe:false)（16838-16864）：删除（destructive、最外）+ 置顶/取消置顶（orange），与 Web 168 区镜像一致；无右滑（Web 同）；删除无确认、直接 softRemove 进 8 秒撤销窗，两边同契约。差仅 §2.1(c) 不辞焦微分叉。

**2.6 新建全路｜达标｜proven｜HOM-12（天气呈现 HOM-11）**
四入口收敛 createAndOpen()（15863-15877）：resignSearch → library.create()（单空段落、title 空、createdAt=updatedAt=now、persist）→ wantsInitialFocus → pushEditor(create)，落点编辑器在席且首段落焦。**模板两边皆无**，无缺失。天气块只是新建卡呈现件、不写入新篇内容，两边同。新篇 id 配方差（Web 毫秒串/原生 m-uuid12）为内部标识，不作缺陷。

**2.7 头像入口｜达标｜proven｜HOM-01**
首页头像 = header 真 Button（15978-15994）：resignSearch 后 nav.dest=.settings，与 Web 点头像/紧凑标题进设置逐项等价（红线「头像有实际功能」满足）。无头像回退 glassControl 圆 + DinoView(size−8) 底对齐，滚动变换公式与 Web 同。

**2.8 紧凑页眉｜达标+P3 微差｜proven（派生式）／基线时序 inferred｜HOM-02/16**
compactP=min(max(scrollOffset/30,0),1)（15969-15971）；scrollOffset 由占位行 onGeometryChange 探针派生、首值捕获基线、max(0,·) 钳死回弹/负偏移；形态切换 syncHomeSize 重置。紧凑胶囊点按进设置、仅 p≥1 可命中。差：**(a) P3 命中死区**——头像/搜索 allowsHitTesting(compactP<0.5)、胶囊须 p≥1，p∈[0.5,1) 页眉三件皆不可点；Web 头像 pointer-events 至 p≥1 才关。窗口仅 15pt 行程，提案阈值改 p<1 一行对齐。（b) 基线由几何回调首值捕获，若首回调落在未落定帧整会话进度可偏几 pt，无落定断言锁定，待探针批加基线复捕核。

**2.9 只读横幅与 notice 行｜定案偏离+P3 未决｜proven｜增补候选（矩阵无救援呈现行）**
readonlyBanner 条件=library.isReadOnly（15700/16195 两形态同源），文案走语言包，唯一出口=「进入救援页」→exitReadOnlyToRescue()，横幅不给切可写钮（防误触定案）；在位时新建卡两形态同隐。notice 行=library.notice 非空呈现（persist 失败三路置位、下一笔成功清空），纯 Text 无动作。差：**P3 已登记未决**——横幅/notice 在位时其下首组头合成距=6+25=31（常态 28），Web 无对应行无从对齐；网格侧另叠 LazyVGrid gap 14 更松且未被任何报告登记。提案二选一收口（横幅/notice bottom 改 3 回 28；网格 notice cell 底距单独核），归调优裁决。

**2.10 撤销 toast｜达标｜proven｜HOM-10**
softRemove（1133-1149）打标落盘（不碰 updatedAt）+摘列+pendingDeletions 登记+本篇独立 8 秒 armDeletion；undoDeletion 回插后按 (pinned, updatedAt) 全序重排——updatedAt 未被删除污染 ⇒ 回原组原位（非近似）。多槽与 Web 逐项同构：数据层逐篇独立到期，**toast 与撤销动作只跟最近一篇**（先删篇撤销机会被后删篇顶替，两边同契约非原生独有缺陷）；杀进程重开按落盘标记再水化续计时。toast 挂 ListView 根 ZStack，进编辑器后不可见/不可点，但计时与待删集在 Library 层独立，窗口内返回仍可撤销、窗口在编辑器内到期照常真删，与 Web 同结果。

**2.11 长按行菜单｜达标｜proven｜HOM-09**
窄屏 memoRow 全段无 contextMenu（全文件仅 16453 网格一处）——窄屏长按无菜单、与 Web 逐项一致，HOM-09 窄屏实体即左滑双钮。网格 contextMenu={打开/置顶/删除} 为「无左滑的补偿通道」定案，比左滑集多「打开」一项（与整卡点按重复但无害），动作链与左滑同函数无分叉。网格长按与整卡点按仲裁 inferred 归真机。

**2.12 网格与窄屏功能差集｜达标（定案差集）+P3×2｜proven｜HOM-15**
共用面：同一 header/groups/createAndOpen/openMemo/undoToast/空状态三态。定案差集：左滑=窄屏独有／contextMenu=网格独有（补偿对子）。差：**(a) P3 网格图文方卡折叠态无展开药丸**——squareCard 对图文卡只下传 collapse（16414-16418、16500-16540），展开仅整卡点按+幽灵叠卡；窄屏图文卡与网格文本方卡（squareFoldPill）均有药丸，Web 两形态共用 MemoRow、expand-btn 恒在。功能可达、呈现冗余缺一，提案 meta 行补同款药丸。**(b) P3 网格组头缺 .textCase(.uppercase)**（16210-16225 有 tracking/色/负底距无大写；窄屏 16715 有），Web uppercase 对两形态同适用——中文无感、英文月份/年份组名形态差，一行补齐。网格组头 13 vs 窄屏 14 字号为 Web 本有差，非原生差集。

---

## 3. 图片页（4 项）

**3.1 打开入口全集｜缺陷 P2·低频（SVG 死路）｜proven｜IMG-01（增补 SVG 子行）**
editor.imageTarget 全仓仅五处赋值：图块 fileId/URL（8190）、gallery 项（11392）、图片附件整幅（13188）、附件文件行经 attIsImage 分发（13209）、图文卡图区（13438）。判图单一口径 attIsImage（14002）：清单 MIME 优先否决/放行、扩展集 10 种，与 Web att_file_is_image_raw（blocks.rs:542-557）逐值同。排除集逐个核无误接：music/link 封面只有 openCard() 开 URL、MD 内嵌图无点按、video 无 target、列表封面仅派生呈现、头像走 PHPicker、非图片附件行走 shareAttachmentFile。差：扩展集含 **svg**（14024，主线已复核），文件行/MIME 判图都会把 SVG 送进图片页，但 decodeImage（3053）走 CGImageSource/UIImage、iOS 无 SVG 光栅解码 → 恒落加载失败且分享路被截断。提案：判图不动，图片页/loader 对 svg 走 WKWebView 光栅化，或把 svg 从原生可开集分流回分享路，二选一加断言。

**3.2 呈现/缩放/GIF｜达标｜proven（状态机）／手势跟手 inferred 归真机｜IMG-03/04/05**
可用区=GeometryReader 全高−66 页头让位、判定与呈现同用 availH（18466-18480）。ZoomableImageView（3140）：base=min(fitScale,1)（大图缩/小图不放大）+contentInset 居中、max  zoom=max(base×4,1)、双击 fit↔min(2.5×base,max)、捏合 UIScrollView 原生；全仓无程序化自动放大点。GIF：decodeImage（3053-3089）CGImageSource 逐帧+delay（下限 0.02s、无信息 0.1s）组 animatedImage，图片页与块内图共用。观察项：非 GIF 动图帧时长一律 0.1s 兜底、APNG 在 ImageIO 下是否逐帧 unknown，低频登记观察。

**3.3 标题｜缺陷 P3（i18n 残留）｜proven｜IMG-02（增补候选）**
displayName（18436）：fileId 在时 attachmentName(for:) 优先——清单表（FFI attachment_names_json；load 全表拉取、put 同步增补）优先、扫 attachment/items 节点名兜底、无回 nil；titleText（18451）>12 字取前 12+「…」仅呈现截断、Diag 记全名；CompactTitle lineLimit(1) 单行。差：回退文案三处硬编码字面量 `"图片"`（8194/11397/13440）未走 Lang.t("imgpage.untitled")（五包在位、en-US="Image"），非中文界面无名图标题仍显中文；同页 `Text("图片加载失败")`（18483）亦硬编码、无对应键。提案：三处改引既有键、失败文案新增键五包同步，随 i18n 零残留批。

**3.4 返回恢复｜达标（机制面）/恢复深度未验｜机制 proven、焦点恢复 inferred 归真机｜IMG-06**
呈现已移交转场宿主：MomentEditorTransition.swift:325-365 observeImage——imageTarget 置位 push、清空 pop、VC 移除时反向清 target；编辑器 VC 与同一 EditorModel 实例不销毁留栈下层，标题/块/滚动凭「同实例同 VC 存续」恢复，onDisappear 仅 saveNow。差：全仓无显式焦点/选区/滚动偏移恢复代码——代码只能证「状态未被清」、不能证「焦点被恢复」。提案：真机终判清单加一条（编辑中开图→返回，查键盘/光标/滚动三项），若焦点丢则在 pop 后按 focusBlockId 重认领。

---

## 4. 设置族与天气（9 项）

**4.5 语言行｜达标为主+缺陷 P3×2｜proven／运行中系统语言变更 inferred｜SET-09**
LangStore（4176）五语；apply/applyFollowSystem 写 langPref+即时换 pack，lookup 回退链=当前包→zh-CN→键名本身；全新装默认判据（无 pref 且无存量→"system"；存量→"zh-CN" 零突变）只跑一次。本轮实测五包各 360 键、键集合互等（missing/extra 皆 0）。即时生效面：ListView、SettingsView 及全部设置子页、ErrBadgeOverlay、RescueView 均观察 LangStore。差：① EditorView（8723）与 ImagePageView 未声明 @EnvironmentObject langStore，子树 Lang.t 为静态查表无失效触发——应用内切换时编辑器本就不在栈上故无感，但**桥远程切语言时若编辑器正开，文案停在旧语言直至重开**；② followSystem 时运行中改系统语言不重解析，须重启。提案：EditorView 顶层补一行观察接线；系统语言变更监听重解析随手补或明确登记重启生效口径。

**4.6 文字大小｜缺陷 P2（定案落点大面积未实装）｜proven（主线已复核）｜增补候选（SET 族新行「文字大小实效」）**
设置行呈现达标：外观组行（17310）标题+「跟随系统」副文案+右值，无分段钮、无应用内字号偏好键残留。但实效面：@ScaledMetric 全仓仅 ListView 三处（15456-15460：groupFontSize/metaFontSize/titleFontScale），覆盖组头、列表标题（16844）、meta 行（16929）；其余界面含整个设置族、编辑器正文 UITextView、图片页，182 处固定 .system(size:) 不随 Dynamic Type 缩放——系统文字调大档时本 App 除首页列表三处外纹丝不动，与行文案承诺不符。此系 audit_detail_settings B1 定案只核行形态、未核生效面。提案二选一须用户裁定：分批把设置族+编辑器正文+列表其余行接入 ScaledMetric/语义字体（默认档 pt 值与 Web 对账不变）；或改判「仅列表跟随」并同步改行文案不得再称跟随系统。不建议继续挂账。

**4.7 天气行与二级页｜达标+P3｜proven／生效路径一条 inferred 归真机｜SET-02/03/04**
主页行 meta 直引 settings.weather_sub（17377），旧 weatherMeta/weather_status 五包与代码零残留（W18-2/6/7 断言在位、zh-CN 逐字实测）。WeatherView（18017）双卡=和风 key/彩云 key+说明卡，**无城市字段**（城市走定位链，Web 亦无城市设置）；逐字段即时提交（失焦/onSubmit/离页/粘贴即提交，统一保存钮已退役）；commit 去空白、无变化不写盘、空值删键；clear 仅 custom 在位时出现、删键+清缓存、回落 builtin/none。回读绝不回值：字段初值只取用户自填值、内置 key 永不进字段、SecureField 掩码；桥 settings_get 只回 state/source（MomentBridgeTools.swift:1889-1905）proven。差（P3）：commit/clear 只删 weatherCacheV1、不清 WeatherService.now 也不主动 refresh——新 key 生效依赖返回 ListView 时 onAppear 重入触发 refreshIfNeeded（缓存已删必重拉），该重入在 NavigationStack pop 下是否恒发生代码不能证，终判归真机（改 key→返回首页看天气块换源刷新）。提案：commit 后直调 refreshIfNeeded(force:) 或先清 now。

**4.8 数据区导出/导入｜达标+缺陷 P3×3｜proven（核心事务引既有定案）｜SET-07/08**
导出：确认底表→exportZip（1530，空库守卫、FFI exportBackup、成功/失败各记 recordOp）→ShareSheet（17740）；成功反馈 toast status.shared。导入：fileImporter(.zip)→stageImport（1623，security-scoped 暂存→validateBackup→parseStats）失败即 toast 且数据未动；校验过弹确认底表→commitStagedImport（1651，整库替换+reload）成功 toast 带 {n} 备忘/{m} 附件计数对账。确认底表定案在位（透明遮罩+仅 opacity 进场+spring 0.25/0.86 无位移）。iCloud/Google：全仓 grep google 零命中、无单独 iCloud 行、仅 backup.icloud_note 说明文，与定案一致。差：① **stagedStats（17483）只写不读**——校验计数确认前不呈现（Web 确认面同样不显、属等价，但字段是死状态）；② **边沿误报（inferred）**：commitStagedImport 导入成功但 stats 解析失败返回 nil 时，确认面 else 分支（17807）误报「导入失败（现有数据未动）」而数据其实已换——提案 commit 返回拆成败与计数两路；③ 导出 toast 在 ShareSheet 刚弹出即报「文件已分享」（未接 onComplete），锚在生成而非分享完成，与 Web 同义不同真，P3 注记。

**4.9 桥行一致性｜达标｜proven｜SET-06**
设置主页桥行（17352）与桥设置页（MomentBridgeSettings.swift:154）共用 BridgeCoordinator.shared.linkStateKey 经 Lang.t 呈现，入口与 Sub 路由一致，无两套状态源（细节见 §5.11）。

**4.10 手势速览页｜达标｜proven｜SET-10**
GesturesView（17939）五行全走语言包；数值核对：longpress「约半秒」↔ DragPressEngine minimumPressDuration=0.48（MomentDrag.swift:107）同值；swipe「8 秒内可撤销」↔ undoWindowMs=8_000（435）同值；编辑块长按=选文字文案与 DragPressEngine disarm 口径一致。无差。

**4.11 诊断页｜达标｜proven／跨天真实触发 inferred 归真机抽样｜SET-05/11/12**
DiagView（4361）：自动清理行+说明行、等级 segmented、当天终端卡、导出全部日志卡、历史归档胶囊、库状态节。导出链 buildExportFile（环境头+归档+当天+快照环）写 tmp→ShareSheet。diagAutodel 实效三点成链：开关 set 即 applyAutodelete()+记行（4415）、DiagLog.loadIfNeeded 收尾亦调（3888）、桥 setToggle 白名单同路；本体（4012）30 天 cutoff 删归档与当天条目、删量记行。DiagLogPage（4811）终端卡撑满可用区、文字胶囊「导出」全量未过滤行。无新发现。

**4.12 关于/版本行｜达标（当前一致、非同源）+P3 隐患｜proven（主线已复核）｜增补候选**
三处实测同值：build-app2.sh:300-301 plist 0.9.57/84、设置页硬编码 Text("0.9.57")（17395）、Diag 导出头与救援页读 Bundle 运行时值。设置页串与 plist 非同源、双字面量人工同步，靠 verify [1] 兜底。隐患：verify_ios.sh:44 取值 `grep -o 'Text("[0-9][0-9.]*")' | head -1` 是位置假设——文件上方新增任何数字字面量 Text 即静默比错对象。提案：取值锚改 settings.version 行邻域或加可 grep 注释锚，随下次组版顺手。

**4.13 天气数据链/天气块｜达标｜proven（链路）／外部源出数 inferred 归 Diag provider 行抽样｜HOM-11/SET-02**
WeatherService（14983）：和风 key 空整链不发请求（15120，与 Web key 门同）；fetchQWeather 任一环失败才落 fetchCaiyun、彩云 key 空跳过、双败记 WEATHER provider=fail。key() 优先级=自填>bundle weather-keys.json（构建机注入不入 git）>空，keySource 同派生、bundleKeys 进程级单次缓存。城市链：GPS WhenInUse 单次定位（公里精度、5s 超时、拒授权回 nil）→失败才 ipapi.co 取坐标+IP 城名；呈现序=CLGeocoder zh_CN 反查>和风 geo>ipCity（英转中表已修）。缓存 weatherCacheV1 TTL 1800s 与 Web 30 分钟同、inFlight 去重、OpsDirectives 天气 guard 在位（15803）。失败呈现：无缓存全败时 now=nil→天气块整块不渲染、无占位无错误，与 Web 逐项同。字段呈现窄屏/宽屏与 Web 口径同。缓存无版本号与坐标（Web 读时亦不比坐标）行为等价，仅注记。

---

## 5. 启动链 / 救援 / OPS / 桥呈现（11 项）

**5.1 冷启路径分段｜达标+P3×2｜proven｜LCH-01**
判定前移 Library.init 同步段（466-467 judge→writeBootSnapshot，只读文件元数据不开库）；load() 步序：开库（900）→开库·FFI（905）→写种子（918）→读数据（reload 内步痕 991/993/1009/1049）→附件类型（+0.3s 延迟刷新）→首帧（927）→launchDone（502-511）。首帧前无同步阻塞项（开库延迟 0.05s 派发后台）；快照环 20 条、字段只记元数据。差：(a) 失败路径（开库 catch 973-986）只有 error 行、无 SMOKE 失败对应行——发版清单按 SMOKE 检索会漏计失败冷启，提案补 `SMOKE 冷启失败` 同格式行。(b)「首帧」步痕（927）写于数据就绪后收尾段，与 ListView 量测的 firstFrameMs（15798）是两个口径，Diag 并读易误读，提案行文/注释区分。

**5.2 LAUNCH 未收尾判读｜缺陷 P2/P3｜proven（机制）／jetsam 归类 inferred 归真机 Diag｜LCH-02（(c)(d) 增补候选）**
judgePreviousLaunch（809-891）三路「先定源者赢」：① streak 路——busy 且停加载步（isLoadStep）→streak+1 落盘，≥2 定 safe(source=streak)、≥3 notice、==1 成功后提示；停会话/场景/首帧步只 warn 不计数。② OPS 路仅 normal 时以 forceSafeMode 定源（845-850）。③ 桥布防路无条件 take()、仅 normal 时定源（861-879）。哨兵 launchMark 每步 RMW+atomic 写；退后台 launchSuspend 清 busy；launchDone 清 streak 不清 busy。差：(a) **P2 误报面**（见 §1 P2-8）：加载步内强杀/jetsam/真崩溃不可分。现行缓解只有 ==1 不进安全模式；RescueView 已有 prevStep 行（RS:97-100）可销大半，提案把此口径写入 LCH-02 已知误报注记。(b) P3 漏报面：退后台清 busy 后被杀恒不留痕（设计口径 G2），且 load 中途退后台→清标→后台被杀，加载期死亡被吞一例。(c) **P3 竞态**：launchMark/markScene（515-521）无锁 RMW，后台 load 步写与主线程 markScene 并发时步名可回退/丢失（文件不撕裂），提案哨兵写收敛串行队列。(d) **P3 streak 虚增**：安全模式内被强杀时 busy 仍停原加载步（救援页不写哨兵），下次判定再 +1，展示值随「开救援页又强杀」单调虚增（不影响进/出判定，仅状态区与 RESCUE enter 行失真）；提案 judge 在「上次已判 safe 且本启未走 load」时不递增，或救援页 onAppear 把步推进为「场景·救援」（需新增步名）。

**5.3 启动看门狗｜缺陷 P2｜proven（覆盖面）／慢启动量级 inferred 归真机｜LCH-09（(a) 增补候选）**
阈值单点 12s（418-419）；armWatchdog 在 load() 起点（899，主线已复核），didLoad 两路 cancelWatchdog；触发记 RESCUE watchdog fired 并置 watchdogFired；浮条挂根 ZStack 开屏之上、didLoad 自撤；OPS 可点名禁用；安全模式不 arm（定案销账）。差：**(a) P2 覆盖洞**（见 §1 P2-2）：arm 依赖 ListView.onAppear 触发 load()，构建期挂死无覆盖；提案 arm 前移到 Library.init 末尾（didLoad 前恒 arm、load 起点只续期）。(b) P3 慢启动误伤：12s 不随库量缩放，大库冷启读/解析 >12s 必出条；但浮条非阻断、load 不中断、就绪自撤，误伤仅呈现层——用户点「进入救援」则 bootMode 切 safe 而 load 仍在后台跑完，出现「安全模式页+内存已载入列表」中间态（inferred）；提案阈值维持 12s（与 Web 对齐），enterRescueFromWatchdog（785-795）前先判 load 是否在途并在 RESCUE enter 行附 inFlight= 标记便于定因。

**5.4 救援层触发与面板动作｜缺失 P2（手动入口）+缺陷 P2（清缓存×只读副本）｜proven｜LCH-04/06（增补候选）**
触发全集仅四路：启动判定 safe（根 ZStack 分流 18650-18654，safe 时不构建 ListView）、看门狗浮条、只读横幅「进入救援」、桥 rescue 动作（不切页）。**正常模式无手动入口**（P2-3）：设置/Diag 页 grep 无 bootMode=.safe 写入点。动作逐个核：导出诊断（RS:325-341）=环境头+全部归档+当天+快照环+哨兵段，不依赖开库、ShareSheet 分享，内容为 Diag 文本面不附库文件——「不带笔记数据文件」红线 proven；检查热修复双源拉取落缓存；导出 ZIP 置灰以 meta+动作内 guard 双保险、不开库不假成功；清缓存 RescueCacheCleaner（RS:381-451）按构造只引用 cachesDirectory+temporaryDirectory+URLCache，绝不含 Application Support/UserDefaults——「绝不动笔记数据」红线 proven。差：(a) 手动入口缺失，提案 Diag 页内加「进入救援」（写 bootMode=.safe source="manual"；BootMode source 注记 353-357 需补 watchdog/manual 两值，现注记已与代码漂移）。(b) **清缓存×只读副本相撞**（P2-4）：只读副本目录在 tmp（702-705），回救援页时只读句柄保留（711-713 明示），清缓存 clearContents(tmp)（424-428）会删正被打开的副本三件套，后果 inferred（读页失败/副本损坏、只读浏览崩坏）；提案 clear 前若 openMode==.readOnlyCopy 先关句柄回退，或 measure/clear 跳过 moment-rescue-ro。(c) Web repairBoot（注销 SW+清 Cache Storage）原生无对应物属平台无对象，定案等价=清缓存动作，销账。

**5.5 安全模式｜达标+P3×2｜proven｜LCH-03/BRG-07**
进入全集五路：streak≥2／OPS forceSafeMode／桥布防一次性／看门狗／只读横幅回页。受限集 8 件精确集（MomentBridgeTools.swift:76-85），分发器首段拦截（132-140，判据=bootIsSafe || cached().forceSafeMode，后者使正常会话亦提前收紧——纵深定案）；rescue_arm_safe_mode 不在受限集、安全模式内调用回 safe_mode_limited，与 impl_rescue_arm 定案一致。退出：tryNormal（RS:285-306）与桥 rescue_try_normal_start（BO:215-246）同一调用序列，桥侧如实回 forceSafeStillArmed 不报假成功。UI：RescueView 全页（状态区含 prevStep/streak/src/DB/Diag/OPS/快照双条/lastRescue+五动作），forceSafeMode 在位时主按钮下明示「下次启动仍回安全模式」。**防循环承重断言代码级复核成立**：take() 先删后判（BO:356-364 读→removeItem→返回，审计 recordAudit 在其后，审计写失败只记 audit=0 不复活标记）；判定点无条件消费（已 safe 也消费、applied=0）；try_normal 后标记已物理删除，下次冷启第三路恒无标记、只余 streak/OPS 按事实判定，收敛 proven。差：(a) P3 桥布防 reason/commandId 对用户不可见——状态区只显 src=bridge，原因仅存审计文件与 rescue_status；提案 src=bridge 时附读 loadAudit 的 reason 一行。(b) P3 BootMode source 注记漂移（见 §5.4(a)）。

**5.6 只读模式 R2｜缺陷 P2｜proven（门面/横幅）／桥面叠加 inferred｜LCH-05（增补候选）**
enterReadOnly（642-700）：FFI openReadonly 直开失败回退 tmp 副本（拷贝后以可写打开、门面按只读对待，源库零触碰）；writeBlocked 门面（619-638）覆盖 persist/delete（软删/真删/待删标记）/seed/attach/import，拦截记 READONLY 行+notice；reload 内待删过期只读态仅隐藏不真删。呈现：双布局只读横幅、新建卡隐藏、横幅含回救援入口。只读由安全模式进入、成功即 bootMode 切 .normal，退出唯一路径=横幅回页→prepareNormalStart 复位。差：(a) **P2 编辑入口未禁用**（P2-5）：全仓 isReadOnly 引用无编辑入口拦截点（grep 实证），用户可打字编辑、persist 才被拦，成果当场丢失。提案二选一落定案：列表卡点按只读态改仅预览/直接弹只读 notice，或编辑页打开即置不可编辑态——须用户裁定入口口径。(b) P3 叠加面（inferred）：只读期 bootMode=.normal 使桥分发器呈 full 形态（BR:250-252），桥写工具最终被门面拦，但工具层可能先行快照/回读造成「写成功假象」未验；rescue_status 已暴露 readOnlyOpen（BO:143），提案分发器在 isReadOnly 时对 dataWriteTools 直回 readonly 错误码、与门面双层一致化。

**5.7 OPS 拉取链｜定案偏离 P2｜proven｜LCH-07/08**
双源顺序拉取（MomentOps.swift:169-216：Worker 主源→GitHub 备源，第一个 sanitize 成功为准，6s 超时、?t= 绕 CDN、逐源失败签名落 OpsFetchOutcome）；时点=正常 load 成功后后台刷新一次（958）、救援页 checkOps、桥 ops_refresh。成功落缓存（diag 域原子写）+更新 current/lastSource。双源全败：缓存原样保留、current 维持 init 缓存值，无缓存则空指令——回退口径 proven 合理。sanitize（108-128）：非字典整包判失败转备源；字典内只取 version/disableSteps/forceSafeMode，未知字段静默丢弃。bootApplied 收敛判据=桥三层回读 boot==cache && cache==current（BO:38-64，三字段全等）。差：(a) **P2 生效口径双轨**（P2-6）：OP:141-145 注释与 BO 头注宣称恒下次启动，但附件类型（1444）、Diag 冻结写盘（3934）、天气刷新（15802）、分发器紧缩（132-134）实时读 cached()；提案 S13 口径修订为「判定/桥启停=下次启动；步 guard/分发紧缩=实时」，ops_refresh 回读加 effectiveScope 字段明示。(b) P3：sanitize 不校验 disableSteps 步名合法性（任意字符串入集、因 guard 精确匹配而惰性无害），仅 ops_validate 事后能报 invalidSteps；属 runbook 面注记（LCH-08）。

**5.8 OPS guard 点覆盖｜达标+P3｜proven｜增补候选（挂 LCH-07）**
OpsStep 登记六步逐项对消费点：附件类型（1444-1452）✓、Diag 冻结写盘（3934-3939）✓、天气自动刷新（15802-15808）✓、MCP 桥（BR:285-294 start 拦截+BT:184 分发深查）✓、看门狗（749-755）✓、公式预热——无调用点，步名先行登记且注释明示新增预热须先查 isDisabled，懒加载现状与登记一致 ✓。**核心步红线 proven**：开库/FFI/读数据/写种子/再水化/附件名表全程无 isDisabled 消费点（全仓 grep 实证），指令点名核心步名物理无效。forceSafeMode 消费时点=启动判定+分发器实时紧缩。差 P3：ops_validate 的 knownOpsSteps（BO:146-163）把核心步名列为「合法步名」，校验通过会给发布者「可禁用核心步」的错误预期；提案拆 guardable 与 known-but-unguarded 两集（核心步校验回 warning 或单列 unguardableSteps）。

**5.9 配对全链 UI｜缺陷 P3×2/缺失 P3｜proven（本地面）／中继残留 inferred 归中继回读｜BRG-01（(a) 增补候选）**
发起：未配对分支「开始配对」钮（BS:197-205）；beginPairing（BR:711-775）已配对只重连不新铸 pid、有待配对会话复用同 pid（未过期续轮询/已过期先问中继）、新铸 pid 落 Keychain 持久；请求 scopes 只报 ["read"]，授权勾选在中继配对页完成。配对中呈现：指纹大字+核对提示+等待文案+「打开配对页」+取消。成功：finishPairing 落 pairingId/scopes→connectNow，设置页翻已配对分支。解除：两段点按确认（onDisappear 复位），disconnectAndRevoke 本地先行删 pairingId/scopes/pending+销毁设备私钥，中继吊销为签名 POST 尽力而为（无回执校验）；中继 revoke-notice 到达侧亦 clearPairing。差：(a) **缺失 P3 无二维码**——全仓 grep qr 零命中，配对靠链接在本机浏览器完成；impl_bridge_m1 定案本就是链接式，登记增补候选由用户裁是否补 QR（跨设备场景才有增益）。(b) P3 重配对无显式入口——已配对态只有「断开并吊销」，换房/换钥须先吊销再重配且无引导文案；吊销 POST 失败用户零感知零重试，中继房间残留不可见（inferred：残留只在错房三联征 BRG-02 时以 app_offline 显形）；提案吊销后状态行区分「已本地断开」与中继确认、Diag 分开记（现仅 BRIDGE revoked via=app 一行）。(c) P3 待配对无过期呈现——expiresAtMs 已落盘但设置页不显剩余/过期态，配对页打开晚了只见轮询静默停，用户无从知晓需重开始；提案 pending 分支加过期时刻行。

**5.10 scopes 呈现｜缺陷 P3｜proven｜BRG-03（呈现侧增补候选）**
已配对分支显示 scopes 本地化名拼接（BS:177-190，五语键）；分发器能力门与呈现同源 scopes；welcome 以中继授予覆盖本地、配对完成以 status 回带授予落盘——呈现=实际授权的收敛路径 proven。write 未授时已授列表只列已有项，不显负向行。差：(a) **空集兜底误导**——scopes 为空时 UI 兜底显「只读」（BS:186-188），但空集在分发器侧连 read 层亦须复核，呈现却断言已授只读；且 status 缺 scopes 字段时 finishPairing 默认 ["read"]（838-840）的契约兜底与此叠加更难分辨真值；提案空集显「—（未回带授权）」。(b) write 未授无负向呈现，用户无法在 App 内区分「未授」与「不存在」，与 BRG-02 错房排查判读需求相悖；提案已配对分支末尾以次级文案列未授项（灰色「功能写（未授权）」）。

**5.11 状态呈现一致性｜达标+P3｜proven（呈现层）／机制定因引 fix_bridge_reconnect_flow.md 不重导｜BRG-02（呈现侧增补候选）**
双面同源 proven：主页桥行 meta（17350-17354）与桥设置页状态文案（BS:171）均直读 Lang.t(bridge.linkStateKey)，linkStateKey 映射八态（BR:254-265），setState 单点写并记 BRIDGE state 迁移行；呈现零迟滞零缓存与用户 2026-11-27 裁定一致。温启「假已连接」窗与 backoff→connecting→connected 序列属状态机/探活机制面（reconnect_flow 报告 A2/B2 定因），呈现如实反映、非呈现层缺陷，终判归真机 Diag 量测。最近调用环形 20 条（工具名/结果码/耗时/时刻）只记元数据 proven。差 P3：最近错误无独立呈现——backoff reason、session down 的 receive_error/send_error、最近 BRIDGE error code 只入 Diag，用户只见「重连中」无从判读是网络断还是被吊销（revoked/opsDisabled 有专属态、唯 backoff 不带因）；提案状态行下加一行次级文案呈现最近迁移 reason（setState 已有 reason 入参，零新机制纯呈现）。

---

## 6. 交叉引用（他线在途，本报告不展开）

- **首页竖屏卡间距（间距线）**：图/文分隔行零 insets（audit_detail_home C-A3 合成 40）在 HEAD 已提交代码中**未**声明 listRowInsets、系统默认 insets 被继承、合成实测 72（用户 0.9.56 实报）；修复（分隔行+emptyRow 两处显式零 insets + verify F30-13）**只存在于工作树未提交 diff**。本审计按 HEAD 判「已修未提交」——主线组版收口时勿漏提此 hunk。
- **桥续连流程**：fix_bridge_reconnect_flow.md 已定因（全量握手/探活 5s 窗/中继存储往返），本报告 §5.11 只核呈现层、结论与该报告一致。
- **编辑页**：另一条线审计中；本报告涉编辑页者仅只读态入口（§5.6）与语言观察接线（§4.5）两处边界项。

## 7. 修复分批建议

| 批 | 内容 | 前置/裁定 |
|---|---|---|
| 救援小批（优先） | 看门狗 arm 前移 init（P2-2）；手动救援入口+BootMode 注记补齐（P2-3）；清缓存跳过/先关只读副本（P2-4）；哨兵写串行化+streak 虚增收口（§5.2 c/d）；SMOKE 失败行+首帧双口径注记（§5.1） | 无 |
| 只读体验批 | 只读编辑入口定案落码（P2-5）；桥分发只读回码一致化（§5.6 b) | **须用户裁定入口口径**（仅预览/弹 notice/编辑页不可编辑 三选一） |
| 文字大小批 | Dynamic Type 接入设置族+编辑器正文+列表其余行（P2-1） | **须用户裁定**：全量接入 vs 改判「仅列表跟随」+改文案 |
| 搜索收口批 | 命中集 persist/reload 重算（§2.1 a)；haystack 收严与否（§2.1 b)；左滑/菜单辞焦微分叉（§2.1 c) | (b) 待主线裁 |
| 首页/网格微差批 | 页眉命中阈值 p<1（§2.8）；网格图文方卡展开药丸（§2.12 a)；网格组头 uppercase（§2.12 b)；横幅/notice 组头距收口（§2.9） | §2.9 归调优裁决 |
| 图片小批 | SVG 分流/光栅化二选一（P2-7）；IMG-06 真机终判一条（§3.4） | 无 |
| i18n 收尾批 | 图片页硬编码文案入包（§3.3）；EditorView 观察 LangStore+系统语言变更重解析（§4.5）；随 I4/I5 窗口 | 与 i18n I4/I5 同窗 |
| 天气小批 | key commit/clear 后主动 refresh（§4.7） | 无 |
| 备份小批 | commit 返回拆成败/计数两路（§4.8 ②）；stagedStats 死字段清理或补呈现（§4.8 ①）；导出 toast 口径注记（§4.8 ③） | 无 |
| 桥呈现小批 | scopes 空集/未授呈现（§5.10）；backoff reason 上屏（§5.11）；布防 reason 上屏（§5.5 a)；待配对过期呈现+吊销回执 Diag（§5.9 b/c)；ops_validate unguardable 区分+OPS effectiveScope 回读与 S13 表述修订（P2-6/§5.8） | 二维码（§5.9 a）待用户裁 |
| 组版顺手 | verify [1] 版本取值换锚（§4.12） | 随下次组版 |

## 8. 矩阵增补候选清单（对 plan_selftest_coverage.md）

1. HOM-04/05 增补：搜索命中集新鲜度（编辑删词返回后断言列表即时更新）；haystack 三样本抽样（items text／meta data: url／meta 嵌套）。
2. HOM-06 子行：折叠组全语义（阈值 >2、N=总数、展开键存储域、收起路径、搜索穿透）。
3. HOM-02 增补：页眉命中死区 p∈[0.5,1) + 探针基线首帧落定性。
4. HOM-15 增补：网格图文方卡展开药丸、网格组头 uppercase 两处呈现读。
5. HOM 增补新行：救援呈现面（只读横幅出现/出口唯一性、notice 置位/清除、在位时组头间距合成）。
6. IMG-01 子行：SVG 附件进图片页解码死路（按格式分流断言）。
7. IMG-02 子行：图片页回退/失败文案语言包覆盖。
8. IMG-06 终判项：返回后焦点/光标/滚动恢复深度（真机一条，恒归人工清单 §7 同类）。
9. SET 新行「文字大小实效」：Dynamic Type 覆盖面回读（默认档 pt 对账 + 大档缩放抽样），挂 GLB-04 邻接。
10. SET-04 子行：改/清 key 后天气块换源刷新（真机一条可判）。
11. SET-09 子行：桥远程切语言时编辑器文案刷新；followSystem 运行中系统语言变更。
12. SET-07/08 子行：导入 stats 边沿回读；stagedStats 死字段（构建期可查）。
13. LCH-01 子行：冷启失败路径 SMOKE 行在位（构建期/发版清单可查）。
14. LCH-02 增补：哨兵写串行化（构建期锚）+ streak 虚增收口；已知误报口径注记（强杀/jetsam 不可分）。
15. LCH-09 增补：看门狗 arm 前移 init（构建期锚：arm 调用点不在 load() 内）。
16. LCH-04 增补：手动救援入口（source="manual" 写点在位）。
17. LCH-06 增补：清缓存与只读副本互斥（clear 前副本关闭/跳过目录断言）。
18. LCH-05 增补：只读编辑入口定案形态 + 只读期桥分发回码一致化。
19. LCH-07 增补：OPS 生效口径双轨的定案表述 + effectiveScope 回读字段；unguarded 步名区分。
20. LCH-03 增补：安全模式状态区布防 reason 呈现。
21. BRG-01 增补：待配对过期呈现、吊销回执可见性；（二维码待用户裁后立项）。
22. BRG-03 呈现侧增补：scopes 空集呈现、write 未授负向呈现。
23. BRG-02 呈现侧增补：backoff reason 上屏。

## 9. 已销账复核汇总（本轮回源复核、无回潮，简列）

首页：搜索线 A 焦点单源派生四路辞焦+src 记账、搜索点按字段常驻根治、分组边界 ≤7/≤30 含端点、组序遇见序、置顶刷新 updatedAt、窄屏折叠整卡点按展开、网格空状态三态、meta 色 glass-label、pendingDeletions 多槽+再水化、摘要 strip_markdown 全链、标题上限基数、首卡顶距 56、分组头 28/6+tracking/uppercase（窄屏）、空状态双形态同值、chip 体系、恐龙 size−8、overlay 材质、C-A1 toast 形态、C-A4 页眉同轴、C-A5 网格新建天气行、C-A8 底部留白——均属实。
图片页：清单名优先序、availH=全高−66、12 字截断、CompactTitle 单行、IMGPAGE open/close 打点、缩放+GIF 裁定、attIsImage 单一口径（K22-1）——均属实。
设置族：分组方案 A、组距账、备份确认底表定案形态、toast 全宽条、iCloud 说明行、诊断 F1/F6/F8、视窗页、语言页 E1–E4、组头 uppercase、天气副标题新口径（W18 全组）、WeatherView 逐字段口径、F11 城名英转中、key bundle 单次缓存、OPS 天气 guard、手势页数值同值——均属实。
启动/救援/桥：哨兵直写+UD 只读回退、判定前移 init（拆 0.9.43 死循环）、布防 take() 先删后判三重锁、受限集恒 8 件、清缓存按构造排除数据目录、救援页零删库按钮、OPS 双源全败回退缓存、核心步无 guard、配对五断点收敛、状态双面同源直读、解除配对本地清除面完整、只读副本源库零触碰——均属实。

## 10. 真机终判清单（本审计证据上限外、归用户真机+Diag 判读）

- IMG-06：编辑中开图→返回，键盘/光标/滚动三项是否原样恢复。
- 搜索：空结果「清除搜索」点按后焦点去向；左滑与 onTapGesture 系统仲裁。
- 紧凑页眉：基线首帧落定性（进度偏倚量级）。
- 天气：改/清 key→返回首页，天气块是否即时换源刷新（§4.7）。
- LAUNCH：加载步强杀/jetsam 的 Diag 归类抽样（§5.2 a）。
- 只读+清缓存：副本在开时清缓存的实际后果（§5.4 b，修复前勿主动试，现行可先关副本再清）。
- 桥：吊销后中继房间残留的可见性（§5.9 b）；诊断自动清理跨天真实触发抽样。

> **矩阵并入（2026-11-27）**：本报告候选行已并入 docs/reports/plan_selftest_coverage.md（新行与状态更新逐份对账见该文件 §4.12），后续覆盖状态以矩阵为准。
