# Mynote Rust Web 回归测试矩阵

一键运行：`bash run_all_tests.sh`（本地构建+起服务+全套冒烟+专用探针；
`bash run_all_tests.sh --live` 只对线上地址跑冒烟与探针）。
任一 ✗ 或脚本异常 → 总结为 SOME SUITES FAILED 并以非零码退出。

静态一致性检查（不起浏览器）：`bash scripts/verify_rustweb.sh`
——核对五语言包键集一致、样式四模块齐全且拼接顺序
（tokens→base→editor→panels）、dist 产物齐全、sw.js 版本戳
与 wasm md5 一致、i18n 占位符跨包一致与僵尸键零容忍
（第 7 节硬门禁；疑似漏译仅警告）、dist 体积预算门
（第 8 节，批 13 P-D4）、串行同帧防回归静态锁（第 9 节：
离页舞台 .editor-stage.leaving 不得含 position:fixed、
列表渲染分支须以 editor_slot.is_none() 为门）、备份确认
底表进场无位移静态锁（第 10 节：@keyframes sheetIn 不得
含 transform、.backup-modal 的 animation 须仍指向
sheetIn）；任一失败以非零码退出。

| 页面 / 模块 | 覆盖点 | 脚本 |
|---|---|---|
| 核心库（core/storage） | 备份 ZIP 双向互通、导入全量替换、FTS 搜索、HTML 桥、MathML 公式渲染 | `cargo test`（全量） |
| 列表页 | 日期分组（置顶/今天/昨天/7天/30天/月/年）、标签 chips、图片卡封面、子组折叠（展开 N 条=总数）、滑动置顶/删除 | smoke-rustweb-list |
| 列表页（数据闭环） | 播种、导入真实备份（确认弹窗）、详情图片、搜索面板、刷新持久、导出 ZIP 19 条目 | smoke-rustweb（W1） |
| 编辑器（基础） | 输入、回车分块、斜杠 22 命令面板、转待办、圆形勾选、返回/重开/刷新三段持久 | smoke-rustweb-w2 |
| 编辑器（进阶） | 加粗快捷键、富文本/多行粘贴、列表转换/空项退出、代码块回车不分块、删块+持久 | smoke-rustweb-w3 |
| 编辑器（高亮实时） | 手打 ==重点== 闭合瞬间包 mark、斜杠高亮空选区占位键入、有选区包 mark、Diag 记录、刷新后 mark 持久且不露 == | smoke-rustweb-highlight |
| 全块渲染（格式层） | 全块备忘导入：h1/h2/h3 字号 28/23/20、todo 完成态、callout 三类标题、代码块 pre、列表 5 项合并渲染、图集图片、音乐/链接卡；md 源段落点开编辑、失焦回预览 | smoke-rustweb-blocks |
| 编辑器（菜单） | 面板宽 246/条目齐全/双栏行窄屏隐藏、撤销/重做、背景色底表设置/移除、导出面板 MD 下载、添加附件 | smoke-rustweb-editor2 |
| 设置/备份页 | 外观/数据/关于结构、文字大小三档（root rem 全应用缩放）+持久、备份 hero/确认弹窗、Drive 未连接如实报待定、诊断页深色日志 UI | smoke-rustweb-settings |
| 国际化 | 语言包按需下载恰好一次、全 UI 切换（含斜杠面板）、刷新持久、切回中文 | smoke-rustweb-i18n |
| 启动页 / 深色 / 灯箱 | 外壳 HTML 含 splash（恐龙 SVG+SVG 圆环）、挂载后移除、深色卡片令牌、灯箱开/关 | smoke-rustweb-misc |
| 视觉度量 | 头像 72×72、搜索触发 66、分组头 14px/600、行圆角 32、设置顶距 126、fab 46×46、标题胶囊 66、标题字号 14、正文 16/28、附件块全幅/图片块边距 36、斜杠面板 300/行 ≥48、待办勾选圈 22 圆形、背景底表悬浮 14 | smoke-rustweb-visual |
| 根治尾巴（卡片/背景/预览/标题） | 音乐卡状态机（loading 骨架封面+三行骨架线、或 hydrate 后 ready/error、不再渲染附件文件行）、编辑器背景延伸 html/body 且 body::before 渐变随滚动 0→150 淡入、列表预览剥 md 源码（文首 md 备份剥净 + allblocks 夹具与原版 join+strip 口径一致）、标题聚焦编辑/失焦截断 10 字+…/清空变无标题 | smoke-rustweb-tails |

未覆盖（需真机）：拼音组合输入（编辑器桥不拦截组合态，靠真机验）、
Google Drive 云备份（用户定为待定，UI 如实显示未连接）。
| Wiki 链接与反向链接 | 别名/不存在目标成锚点、代码围栏与行内代码内不成链、点链跳转（编辑器重挂）、反向链接区块与回跳、点不存在链新建同名备忘 | smoke-rustweb-wiki |
| 差距清单修复批次 | 文案、md 结构预览、链接卡锚点、删空范围、空占位、深链、粘贴成卡/图片、斜杠拼音+最近、SW、双栏独立滚动 | smoke-rustweb-gaps |
| 标题胶囊几何（专用探针） | 组字按含组字串的实时全文定宽（非溢出整串在流内 sl=0、溢出固定 184 + scroll-padding 16）、latch 按实时长度判定、caret 边距规则同步只写 scrollLeft、foreign=0、编辑态留白对称 | probe_title_geom |
| 块拖拽排序（专用探针） | 桌面栏内/跨栏拖动落点与落位帧差、撤销重做、双栏锚保持、落盘重开；触屏文本块与原子块长按起拖 | probe_drag_sort |
| 长按拾起（专用探针） | 跟指误差、FLIP 让位链与过渡令牌、取消清零、桌面三态、边缘静止自动滚动、拾起定形（视觉面驱动：代表块 scale 按面边长、框半径 = 面半径 + 4、抓握点不漂移） | probe_drag_pickup |
| 拾起视觉面矩阵（专用探针） | 全块型逐类：拾起框↔视觉面四边间隙 = 4px（两两差 ≤1px）、框半径 = 面半径 + 4 同心（四角双轴 ≤1px）、偏心抓握面内比例不漂移、跟指（面中心）误差 ≤2px；占位文案状态感知（非编辑态长按菜单引导/编辑态「点击添加图片」：图文卡/图片块/画廊空态）；视频块因无头媒体控件吞按压临时摘 controls 量测（环境限制，几何同路） | probe_lift_surface |
| 无拖柄回归（专用探针） | 触屏聚焦不出手柄、占位符全文可读；桌面悬停手柄右缘不压字形 | probe_drag_handle |
| 桥输入管线（专用探针，批 1） | 组字结束重放（斜杠/智能前缀不依赖补发 input）、beforeinput 三指撤销/重做、全局撤销兜底与标题 input 不劫持、xsel 跨块粘贴按行落块、音乐胶囊粘贴分流+错位回收、原子块点击插段区分档（卡片右 15%/附件 28px）、方向键目标列保持、行内包裹空白外置、斜杠 URL token 与 30 字抑制 | probe_bridge_input |
| 批 3 解析与卡片（专用探针，批 3） | C-28 引用式链接/原始 HTML 白名单面/缩进代码、C-21 Callout 未知类型标题、C-23 失焦 guards、C-27 公式错误态包裹、D-17 图库几何与空态双格（空态首格文案 = 非编辑态引导「长按编辑添加」）、C-11/C-12 link-card div 化与点击委托、C-14 图文卡占位盒/几何/选中轮廓（占位文案 = 非编辑态引导「📷 长按打开菜单，点『编辑』添加图片」）、C-15 混排占位、C-10 附件图 alt、C-03 标题级别、C-04 quote 结构、C-05 todo aria、MD-C10 围栏跨块合并 | probe_batch3 |
| 卡片块交互（专用探针，卡片交互专项） | 常驻悬浮钮与悬停「•••」钮移除（全页 .blk-del/.blk-more 零残留断言；菜单入口只剩长按+右键）、长按拾起弹浮层菜单（贴卡/原地松手留存/拖动收起/菜单删除落盘）、编辑态门禁（非编辑态点文本区不开表、点图片区仍开灯箱；入态后点文本区开表、点图片区选图实换落盘；点卡外退出）、图库点格换单图保裸串形态、高卡拾起框↔格网间隙 = 4px、覆盖面菜单项构成（音乐有编辑/链接附件分隔线仅删除）、桌面右键全流程（开菜单/Esc 关/菜单编辑入态/点卡外退态/再开菜单删除落盘） | probe_card_menu |
| 列表卡可达性与封面（专用探针，批 7） | D-21 三处卡片 role=group/tabIndex/aria-label 逐字与 Enter/Space 打开、展开按钮 Enter 不穿透打开；封面按 manifest type 判定（SVG/BMP 出图、PDF 恒空、字节迟到 400ms 经 5×300ms 重试补出）；W-4 超宽头部轴线（1440/1920/1280 头像与搜索缘对内容列缘差 ≤1px） | probe_list_cards |
| 画布空白点按落焦（专用探针） | 空备忘点 body 盒内尾部空白多点位×两轮落首段且打字落字；有内容备忘点文末空白落文末块末尾（原子块结尾落物化尾随空段）；块间空隙不劫持到文末、点已有块仍落该块、body 盒外点按不落焦（原版同口径）；Diag 落 canvas focus 行；手势主路（pointerup 同步落焦）：CDP 触摸点按落焦且 Diag 恰 +1（合成 click 去重）、合成 PointerEvent 单独驱动落焦、CDP 触摸滚动 60px 不落焦；触摸落焦成功的手势另武装兼容回声抑制（canvasEcho）：紧随的 touchend 被取消、兼容 mousedown/mouseup/click 不生成，落下的焦点不被回声 mousedown 的默认动作 blur 掉（链尾全量 ⑤a 红项根治：trace 实证选区曾在兼容 mousedown 后 focusout 丢失） | probe_canvas_focus |
| 标题坞翻转定宽（专用探针） | 三档标题（短 6 字/14 字截断档/27 字）× 长正文上滚：坞翻 scrolled 后胶囊与头像同行（cy 差 ≤4px）、胶囊宽 ≤ 行态可用宽（坞宽 − 头像 − gap 8；gap 取翻转落定值——坞 transition:all 令翻转瞬间 computed gap 停在动画起点 6、曾致可用宽多算 2px、胶囊 191px 被换行，已由 avail_width 测量段摘 transition 读指定值根治）、Diag 记 ph=dockflip；回滚恢复大态（宽回滚前值 ±2、恢复堆叠）；空正文长标题不可滚、坞不翻、胶囊保持大态且 meta 可见；标题会话期程序滚动被 S7 抑制、失焦后无新滚动靠 blur 重播 ed_scroll 自行翻入行态且 scrollY 不被改动 | probe_title_dock |
| 斜杠锚定与键盘删块（专用探针） | 面板贴调用光标（下置间距 10、动态限高不溢出视口底、底部翻转带）、窗滚与独立双栏栏内滚动跟随重锚、链接表单在选区离开调用块时锚点保持；键盘删块不变量：选中卡 Backspace/Delete 不删、非空块块首退格邻卡至多选中、空段退格删空段+选中卡、音乐胶囊段首退格只移焦点不删、跨块选区/全选删除原子块按序存活且文本分段保留、文本合并与 MD 源段合并基线不变 | probe_slash_anchor |
| 根色压暗跟随（专用探针） | 备份确认模态打开（2026-11-23 用户裁定 C：撤 0.28 压暗对齐原版透明遮罩，scrim 改 transparent、DimLayer 注册注销；旧口径为根色压成 #aeaeb2 / html rgb(174,174,178)、Diag dim push/pop 各 +1）：根色不改写（变量未设、html 仍 rgb(242,242,247)）、scrim 计算背景 rgba(0,0,0,0)、采样像素 rgb(242,242,247)、Diag 无 dim push/pop backup-modal；关闭后根色仍未设。编辑页灯箱：2026-11-23 晚恢复集 (b) 摘除根色预压暗登记后，根色保持编辑 base（#FAFAFA / rgb(250,250,250)）不压暗、关闭不变、全程无 dim push/pop lightbox 行，灯箱自身 0.88 遮罩样式不变（旧口径为根色按 0.88 混合至 #1e1e1e、关闭恢复 base）。rider：图片卡左滑开启态点按无操作（保持 -168、不打开、Diag 记 noop）、右滑收起后点按打开正常。判据边界：无头只断言网页层量（CSS 变量与 html 计算背景），iOS 视口外 chrome 带区本身测不到、终判待真机。2026-11-23 灯箱截图定案补记：状态栏带因子律 = M2（带 = 根色 ×(1−α)；α0.28 → ×0.72 实测 rgb(125,124,129)、α0.88 → ×0.12 预测 ≈4 实测 ≈0，M1 固定 0.72 预测 ≈22 排除），浏览器侧处理、无应用杠杆，量级为灯箱态页面 30 vs 带 ≈0–4；底部带 = 根色精确（备份态实测），灯箱态底区被浏览器工具栏 chrome 占据、纯带色不可分离。灯箱几何原版对读：原版 inset:0 四边锚定，Rust 版曾以 height:100vh/100lvh 定高——真机量测盒底停在视口 735/754、末 19pt 无灯箱层覆盖、图心上偏 9.5pt，已收口 inset:0（editor.css .lightbox），探针 ② 段加灯箱 rect 覆盖布局视口断言（无头无动态工具栏、对旧写法不具区分力，区分力在真机）。2026-11-23 用户裁定补记：灯箱背景滚动锁（偏离原版——原版不锁）：桥内三路拦截（灯箱在场时 touchmove/wheel/滚动键在手势源头拦下；判定源 = .lightbox 节点在否、与灯箱 DOM 同生共死，无登记可泄漏，滚动容器状态零改动）+ CSS overscroll-behavior:none 兜底；探针 ⑨ 段：无锁对照组三路真滚自证区分力、灯箱态三路试滚 scrollY 纹丝不动、点关后滚轮恢复、异常离页后重进编辑页可滚（触摸走 CDP 合成链、与真机同构，真机橡皮筋/滚动链手感终判）；⑥ 段离页窗口断言（2026-11-23 白带根治终版口径）：离页层在场期间根色恒为编辑 base #FAFAFA（10ms 页内采样，灯箱预压暗摘除后口径），提交帧后回落列表默认、全程无 dim pop lightbox；此「窗口恒编辑值」与曾被回退的同名断言成因不同——彼时状态已提交列表、靠派生加离页特例凑出（用户裁定补丁），现时是 Nav 提交点后移（窗口内当前页仍为编辑器、DimStack 随实例存活）的直接结果，派生输入无离页特例，分界见 main.rs 派生注与本表过渡行登记 | probe_root_dim |
| 页面退出过渡（专用探针） | 4x CPU 节流下设置→列表、编辑→列表两条退出路径：① 进场动画 currentTime 在新页首现后 3 个 rAF 帧内 >0（帧数口径，毫秒值仅打印参考；审计恢复集 (a) 后本判据只锁栈式交接路径（设置→列表），编辑→列表串行口径下 ct 起步只打印参考、不判红——挂载长任务冻结进场起步为用户知情接受的代价；栈式交接修复前实测起步 ≈7 帧 / 117/133ms）；② 地标限定 .page-current 内（进入页自身 .main-header/首条 .list-item）单帧步进 ≤10px（原版 4x 基线 6.9px，修复前 11.8/11px），并输出 max 步进 argmax 帧信息（帧时间/地标所属层/相邻帧间隔）；③ 定格后（首现 +900ms）步进 ≤1px、scrollTop 全程恒定；④ 编辑路径窗口互洽（2026-11-23 审计恢复集 (a) 串行同帧口径，audit_band_diff_45b5b46.md）：离页期间根色恒为编辑值（开时基线）、离页编辑器根（#editor-root）自有底恒为开时基线计算色；防回归判据组（串行同帧语义）三条——离页期间无列表层（.page-enter 不在场、.page-current 无子元素，未预挂载）、离页舞台 .editor-stage.leaving 计算 position 非 fixed（编辑器在流内以当前页身份出场）、提交帧列表出现与根色翻转同帧（±1）且提交后根色撤除不回现、终值变量已撤且 html 计算色 = 列表默认 rgb(242,242,247)；改组内任一判据须连同 Nav 时序一起评审，静态侧另有 verify_rustweb 第 9 节双锁。修法 = 编辑→列表恢复基线 45b5b46 串行同帧交换（窗口内文档只有编辑器一层、提交帧卸载+挂载+翻色同帧、列表可见性以 editor_slot 为门；设置→列表仍走 App 层栈式交接）；判据治理（2026-11-23，只读审查裁定、主线已接受）：原 ① ≤40ms 毫秒口径在链尾 box 全量误红（设置→列表 67ms、编辑→列表 50ms）——采样器在 rAF 回调读 ct，结构性地板为插入后 1–2 个帧间隔，box 帧间隔约 25–33ms（探针内硬编码 4x 节流、与本机校准同口径，实际间隔随宿主拉伸），67/50ms ≈ 2 帧，与修复前 ≈7 帧真冻结量级不同，且同轮定格后步进/scrollTop/根色三项全过、原缺陷无复现证据，故改帧数口径（≤3 帧）；原 ② 全局地标查询在交接期命中离页层里设置页快照的 .list-item（设置内容层出场 X 行程 16px、.page-content 左右 padding 20px vs 列表 .container 16px），卸载帧地标身份切换的预测步进 19.7px 与实测 19.6px 吻合、进入页当时已完全遮住下层属屏幕不可见，属探针跟踪对象换人而非画面跳变，故地标限定进入页自身并增 argmax 帧信息输出。区分力预期：修复前构建 eb54197da7 在新判据下应仍红（ct ≈7 帧 > 3、步进 11.8 > 10），主线复验时实测；步进量法再治理（2026-11-23 方案 1，用户裁定）：cf1420c69b 复验中设置→列表步进判红恰 20px，取证 proven 为同容器跨页换对象——步进循环计入了（首现前一帧，首现帧）对，前帧采样到的是设置页复用 .list-item 类名的设置行（left 20）、后帧是列表首项动画起始帧（left 40 = 自然 16 + 起始偏移 24），40−20 = 20；同元素逐帧步进平滑（max 3.9，与曲线理论最大单帧位移 3.97 吻合）、layout-shift 全程 0 条、动画挂载帧即在位，真机无可见跳变。故步进统计改自首现帧起算、并加元素身份戳校验（仅同一元素相邻帧计入），③ 定格步进口径同步，阈值（≤10px / ≤3 帧）不变；区分力复验（2026-11-23 box 实测，如实登记）：旧构建 eb54197da7 在新探针下亦全绿（ct 两路 @第2帧、步进两路 0）——其串行交换的挂载长任务冻结为宿主算力敏感缺陷，本机 4x 节流校准时 ≈7 帧 / 117/133ms（步进 11.8/11px 为旧探针全局地标口径），box 上不复现，故本探针区分力仅本机校准口径成立、box 口径不成立；新构建无冻结的结论另有取证逐帧 trace（动画挂载帧即在位、同元素步进平滑）支撑，不单独依赖本探针区分力；白带定案登记（2026-11-23，用户打回补丁式修法后按记录复审重定）：与 2026-11-22 页面色泄漏（第四批根治）异源——分界证据：彼时根色静止态即错（use_drop 内 spawn 清理永不执行、编辑色残留根上，probe_page_side_effects 前后对照定罪，列表/设置/备份页顶底带全染、Chromium 可复现）；此次设备 Diag 实读 + box 实测均证实返回序列全终点于 root bg -> (root default)、其后无任何晚到 #FAFAFA 写者（含历史会话），派生静止态取值正确、Chromium 不复现。产生异色的状态在呈现侧：#14 栈式交接的离页窗口内页面状态已切列表、根色已派生为列表色，而离页编辑器仍以 #editor-root 自有底色（effective_bg 内联、min-height 100dvh 的 .detail 承载）作全屏不透明底留在下层——页面底色出现根色之外的第二来源（违背背景层级模型：根页面是唯一背景色源、上层容器不自带另一套底色），WKWebView 带区锁存该自有底色（#FAFAFA）且交接后无重采；不对称解释：现有备忘（内容满幅、编辑器根全程覆盖视口）中招，新建空备忘（内容近空、编辑器根底色覆盖面与触发面不同）与未滚动路径不复现，与带区采样面一致（浏览器采样微观规则为 inferred，应用侧第二底色源的存在为 proven 读码）。根治（终版，结构性，用户「彻底根治」指令）：改 Nav 提交语义而非颜色管线——编辑器离页窗口内页面状态不提交（selected 保留至卸载计时到时、与实例卸载同一任务清除，Nav::arm_unload 提交），与原版串行语义同构（出场期间当前页即编辑器、列表只是预挂载进入层）；派生保持页面状态纯函数（selected/page/data/DimStack/scheme，输入与函数不变、无离页特例），窗口内继续给编辑底，与 #editor-root 恒自带的 effective_bg 同值同源——不透明离页层不再是异色第二来源，编辑器以自身底色出场、衬底不透列表色；提交帧状态翻转、实例卸载、根色翻值同属一次渲染提交，带区只在此帧翻一次且与编辑器消失同帧、过渡后零残差。选型弃因：候选「进页全覆盖点翻转根色」——编辑→列表进入层至末帧才全覆盖（24px 位移 + opacity 0.94），翻转点退化为卸载帧，且状态 t=0 已提交而根色故意滞后属状态/输出不一致（与被回退版同病），窗口内带区=编辑色而当前页已盖满大半，为白带构型镜像，弃；候选「编辑器离页改快照层」——组件页从不出带区问题非因快照、乃其页面底恒 var(--primary-bg) 与非编辑页派生同值，快照对编辑器仍自带 effective_bg ≠ 窗口根色（锁存复发或改透明回透色残差），且重挂与单实例桥/全局监听清理竞态冲突，弃。曾试两版均回退：① 撤色后移卸载点 + 派生对象改「在屏编辑器」（状态已提交列表却让派生输出编辑色——派生对状态撒谎，用户裁定为「过渡带追页面色」的补丁）；② closing 时 #editor-root 改 transparent（带区虽正，离页衬底透出列表色 #FAFAFA→#F2F2F7 差 8 色阶/280ms，交换式残差，用户不接受）；on_close 的发起任务先行撤色（第六批口径）在本版一并去除——窗口内当前页仍是编辑器，先行撤色与状态矛盾且派生不会以编辑值重申（selected 未变、effect 不重跑），留之则窗口根色被钉在列表色；wiki 编辑器→编辑器为瞬时换键重挂（无离页窗口、新篇派生接管）、留槽同 id 重开 closing 复位，均不经本路径。终判在真机（现有笔记滚动后返回，带区即时与列表同灰、无白带残留）。留槽实测对账补记（2026-11-23，构建 5816604baa 验收）：④ 的 edbg 断言在 box 红（17 个离页帧 #editor-root 采样全 null、独立 rAF 转储同结论），本机对同构建 dist 以 MutationObserver 抓现场定案——离页起始帧 #editor-root 是被 Editor 自身换成 div.empty「备忘不存在」，非 diff 丢节点、非桥摘除。成因 proven：④ 的 setup locator（.img-card-title-text 与 .list-item .item-title-text 并集取 first）命中排在列表最前的新建卡（其根即 .list-item、内含 .item-title-text「新建备忘」），打开的是本会话新建空备忘，返回走 go_back 空备忘删除路径：on_close 先行登记离页、data.set 删备忘在同一任务随后落地，Editor 渲染首查 data 无此备忘即提前 return 空模板——App 槽位留存与 Editor 渲染对 data 在场的依赖脱节（LeavingEditor 设计明文「实例靠槽位留存渲染、不依赖 data 查得」在 Editor 层未落实）。与 root_dim ⑥ 无矛盾：⑥ 夹具备忘含图文卡、走普通路径不删 data；本机对照复测（真现有备忘 demo_exhibit）亦证实普通路径窗口内 #editor-root 全程在场、slideOut 在播、提交帧才卸载、DimGuard pop 在卸载帧——同一机制、两条路径分野。修复（editor.rs）：Editor 备忘来源加挂载首查快照回退（渲染期仍以 data 现查为准、快照仅现查无果时启用；与 state_owner 同口径——实例状态只归属其加载 id、挂载时定格），空备忘路径离页窗口内 #editor-root 与内容留槽至提交帧，删除语义与提交语义均不变（Diag 仍见 close empty memo -> deleted、根色侧既有绿项不受影响）；判据未动。setup 误点新建卡单列主线裁定：建议 locator 排除新建卡、使 ④ 名副其实测现有备忘路径；修复后两条路径均应全过（空备忘路径窗口内 edbg 恒基线、提交帧舞台与根色同帧消失）；setup 双路径补记（2026-11-23 收尾验收）：探针保留原空备忘段（点新建卡、走 close-empty 删除路径，断言全不动），新增现有备忘段——locator 排除新建卡（.swipe-wrapper:not(:has(.new-card-title)) 的首个内容卡标题），同 ④ 口径外加两断言：离页 slideOut 在播（离页帧内 slideOutToRight 的 currentTime 推进 ≥20ms）与 Diag 无 close empty memo -> deleted 行；两段分别计数、互不替代，④ 至此双路径覆盖（空备忘删除路径 + 真现有备忘普通路径）；恢复集 (a) 落地补记（2026-11-23 晚）：终版提交点口径部署后真机两轮复测仍 FAIL（构建 1a119d7886 / 1af457fdd4，顶带逐像素实测仍 250），按用户裁定改与基线 45b5b46 逐项对比审计定案——重叠交接的「列表挂载与根色翻转解耦」为白带唯一结构差（CSS/动画定义/退出清理/body::before 与基线逐字一致或无丢失，均阴性），编辑→列表已恢复串行同帧交换（构建 fdc3d8b14d），三条结构判据归入防回归判据组（串行同帧语义）、静态锁入 verify_rustweb 第 9 节；用户真机确认过渡色残留已解决（2026-11-23 21:23） | probe_page_transitions |

## 脚本索引（批 13 P-D6，2026-11-23 建）

根目录只留在册脚本：门禁面（run_all_tests.sh 逐套运行）与被
在册文档引用的专项/审计探针。一次性/已退役脚本已移入
`archive/probes/`（共 295 个：tracked 91 经 git mv、未跟踪
204 直接移动；移动前逐个核对未被 run_all_tests.sh、TESTING.md
及任何在册文档引用）。新增长期脚本须在本索引补一行；
临时量测脚本用完即移 archive/probes/，不留根目录。

门禁面（用途见上方矩阵各行，入口 `bash run_all_tests.sh`）：
冒烟 15 套 smoke-rustweb、smoke-rustweb-w2、smoke-rustweb-w3、
smoke-rustweb-i18n、smoke-rustweb-settings、smoke-rustweb-list、
smoke-rustweb-editor2、smoke-rustweb-misc、smoke-rustweb-visual、
smoke-rustweb-highlight、smoke-rustweb-blocks、smoke-rustweb-tails、
smoke-rustweb-wiki、smoke-rustweb-gaps、smoke-rustweb-export；
专用探针 14 支 probe_title_geom、probe_drag_sort、
probe_drag_pickup、probe_drag_handle、probe_bridge_input、
probe_batch3、probe_card_menu、probe_list_cards、
probe_canvas_focus、probe_lift_surface、probe_title_dock、
probe_slash_anchor、probe_root_dim、probe_page_transitions。

| 专项/审计探针（根目录保留） | 用途 |
|---|---|
| probe_audit2 / 3 / 4 / 5 | 2026-11-22 审计抽查：生产站口径、多行粘贴存储保行、逐行打字成组形态、原版同口径对照 |
| probe_audit_indcols / 2 / 3 | 独立双栏五项独立性活体与定点复测（打字→落盘全链、关存路径） |
| probe_exit_anim | 浮层出场动效断言（编辑菜单/背景色底表等） |
| probe_katex / probe_katex_eval | KaTeX 立项：Rust 原生 MathML 验证与双边评估（只读） |
| probe_md_orig / probe_md_rust | md 渲染双边基准：边缘 ZIP 导入后逐块转储 |
| probe_orig_time | 原版时刻渲染口径量测 |
| probe_pages_editor_orig / _rust / _rust2 | 编辑页外壳双边审计（fabs/标题坞/菜单/导出面板、长标题与媒体入口） |
| probe_pages_global | 全局项只读审计（启动/toast/深色/语言/字号/SW/错误兜底） |
| probe_pages_list | 列表页双边审计（同 zip 同视口） |
| probe_pages_settings | 设置/备份/诊断双边只读审计 |
| probe_responsive / probe_responsive_orig | 多视口响应式双边度量 |
| probe_responsive_twopane | 独立双栏模式 + 矮横屏开关可见性双边探针 |
| probe_scroll / 2 / 3 / 4 | 滚动监听双边审计（恢复时序、菜单/斜杠跟随、双栏独立滚动） |
| probe_slash_orig / orig2 / rust / rust2 | 斜杠菜单双边基准与逐项实测（只读审计） |
| probe_title_fs | 标题字号档位量测 |
| probe_title_ghost | 标题胶囊双光标 + 跳变复现（逐帧采样选区） |
| probe_title_tapmap | 标题落点映射探针（WebKit 口径） |
| probe_twocol_matrix / probe_twocol_mix | 双栏逐块适配矩阵与混排成员稳定性 |
| probe_wave1 | 修复波次验证（编辑态/斜杠/回车/粘贴） |
| .scratch_slash_anchor / .scratch_slash_ancestor | 斜杠锚定量测（面板锚点与祖先链 containing block 判定） |
| wide_orig_tmp / wide_run_tmp | 大屏双边对照量测（原版只读 / Rust 侧审计） |
