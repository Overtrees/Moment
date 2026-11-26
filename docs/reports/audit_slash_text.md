# 审计线 C：斜杠菜单逐项 + 普通文本适配核查

日期：2026-11-26。范围：斜杠菜单 22 条命令 ×（原版 / Web / 原生）三方对照 + 普通文本编辑语义三方对照。只审计、不改代码。

真值源：
- 原版：归档 `src/app/editor/commands.js`（命令全集）、`slash-model.js`（过滤/分组）、`use-slash.js`（触发/执行/落点）、`src/app/editor.js`（Enter/Backspace/Esc 键处理）。
- Web：`rust/apps/web/src/editor/render.rs`（SLASH_CMDS + SlashPanel）、`hooks/slash.rs`、`ops.rs`（op_convert / op_insert_media_placeholder / op_split / op_merge）、`js/editor.js`（桥：触发检测、applyInline/__mnApplyLink、keydown）。
- 原生：`rust/apps/ios/app/MomentApp.swift`（SlashCmds / updateSlash / applySlash / applyLink / BlockTextView.Coordinator / splitBlock / mergeBlockBackward / insertLines / exitListItem / mergeListItemBackward）。

## 全局前提（影响多行判定，先读）

- **原生触发模型决定了「剩余文本恒为空」**：原生 updateSlash 要求块全文以「/」开头、slashQuery =「/」后全部文本；applySlash 的 stripSlashPrefix 按 1+query.count 剥离，即剥光全文。故原生一切「保留 cleanedText」类语义在可达路径上都作用于空文本，与原版/Web「token 可在块中任意位置、token 前后文本保留」不是同一模型（差异 S-1）。
- Web 与原版在命令数据（22 条、oid/kw/py/type/分组/文案）上逐字一致；Web 面板注释多处标注对原版 slash-model 的逐项移植，核对属实。

## 表 1：22 条命令逐项对照

图例：✓ 一致；◐ 结果形近但数据形/落点/细节有别；✗ 行为不一致或命令失效。

| # | 命令 | 原版行为 | Web 行为 | 原生行为 | 判定 |
|---|------|----------|----------|----------|------|
| 1 | heading1 | 转 heading level=1，children=cleanedText，光标落 token 起点，无尾随段 | 同原版（apply_type） | convert("heading",1)，剥光后空文本，光标落块末（=起点） | ✓ |
| 2 | heading2 | 同上 level=2 | 同原版 | 同上 | ✓ |
| 3 | heading3 | 同上 level=3 | 同原版 | 同上 | ✓ |
| 4 | paragraph | 转 paragraph，children=cleanedText | 同原版 | convert("paragraph") | ✓ |
| 5 | quote | 转 quote，children=cleanedText，无尾随段 | 同原版 | convert("quote") | ✓ |
| 6 | todo | 转 todo（checked=false）+ **尾随空段**（下块已是空段则不插）；落点：插入尾随段时焦点落尾随段（原版口径如此，疑似原版怪癖），否则落本块 | todo + 尾随空段（同款 next-empty 判定），焦点落本块 token 起点 | todo（checked=false）✓，**不插尾随段**，焦点落本块末 | ✗ 尾随空段缺失 |
| 7 | divider | 本块转 divider + 尾随空段（next-empty 不重插），焦点落尾随段起点 | 同原版 | 转 divider + 尾随段 + 焦点落尾随段；但**不查 next-empty，已有空段仍再插一段** | ◐ |
| 8 | bold | 行内命令：按快照选区在 cleanedText 中字面包裹 `**…**`；无选区→在光标处插入 `**文字**`；结果块强制 paragraph、纯文本字面标记，光标落包裹段之后 | 桥 applyInline：选区偏移捕获→strip 后重建选区→DOM 包裹 `<b>`；无选区插入 `<b>文字</b>`，光标落其后；选区首尾空白外置 | 对剩余全部 runs 打 bold 键；剩余文本恒为空 → **零 run、无任何效果**，仅剩空段落 + 焦点 | ✗✗ 命令失效（见 S-3） |
| 9 | italic | 同上，`*…*` / 占位「文字」 | 同上 `<i>` | 同上（italic 键） | ✗✗ 命令失效 |
| 10 | highlight | 字面 `==…==` 包裹/占位 | `<mark class=moment-highlight>文字</mark>` | 首尾 run 拼 `==`；runs 为空 → 无效果 | ✗✗ 命令失效 |
| 11 | codeBlock | **降级为 paragraph 的 MD 源**：` ```\n cleanedText \n``` `（围栏随正文最长反引号串加长，正文不剥前缀），光标落开围栏后 + token 起点，无尾随段 | 同原版（op_convert md 源臂，含 D-13 围栏加长） | 转**真 codeBlock 类型**，内容=剥后文本（恒空），光标落块末 | ◐ 空态结果形近；数据形（MD 源段 vs codeBlock 类型）与落点口径不同，跨端打开同篇时形态分叉 |
| 12 | bulletList | 降级 paragraph MD 源：cleanedText 逐行加 `- `，空→`- 列表项`，光标落前缀+token 起点 | 同原版 | 转**真 bulleted-list**，单项承接剥后文本（恒空→空项，无「列表项」占位），焦点落项末 | ◐ 数据形不同；空占位文案缺失 |
| 13 | numberList | 同上，逐行 `N. ` 编号 | 同原版 | 转真 numbered-list，同上 | ◐ 同上 |
| 14 | callout | 降级 paragraph MD 源：`> [!NOTE]\n> …`，空→`> 提示内容`；**+ 尾随空段** | 同原版（源段 + 尾随空段，进 MD 编辑态） | 转**真 callout 块**（calloutType=note），正文=剥后文本（恒空），**无尾随段** | ◐ 数据形不同；尾随段缺失；空占位「提示内容」缺失 |
| 15 | link | 先开表单（预填 `https://` 并全选，校验 URL 解析+协议白名单，不过→表单内报错不关闭，取消→**回命令列表**）；提交：有选区→字面 `[选区](url)` 包裹，无选区→光标处插入字面 `[链接文字](url)`；URL 括号转义 %28/%29 | 同原版（submit_slash_link + __mnApplyLink：restoreSel 非折叠才 createLink，否则 insertText 字面式） | SwiftUI alert 表单：**无预填**、message 常驻校验文案（非报错态）、applyLink 先关表单再校验、不过→**静默无反馈**；通过→给剩余全部 runs 打 `_link`（恒零 run）→ **无任何效果**；取消不回命令列表 | ✗✗ 命令失效 + 表单口径三处不符（见 S-4） |
| 16 | code | 行内：字面 `` `…` `` 包裹/占位「文字」 | `<code>` 包裹/占位 | runs 打 code 键；零 run → 无效果 | ✗✗ 命令失效 |
| 17 | strikethrough | 字面 `~~…~~` 包裹/占位；注：原版 zh 文案副标题为「~~删除线~~」，Web 语言包作「包裹选中文字为 ~~删除线~~」 | `<s>` 包裹/占位 | runs 打 strikethrough 键；零 run → 无效果 | ✗✗ 命令失效 |
| 18 | imgTextCard | 本块转 imgTextCard：children 文本被固定占位 **「点击输入文字」替换**（不保留原文），attrs.fileId=''，+ 尾随空段，焦点落尾随段 | 同原版（apply_type S6 工厂） | node 置 {type, text:""}：**占位文案未落**（靠渲染层空文案「点击查看完整文本」兜，外观近似但存量数据不同）、无 attrs.fileId、**无尾随段**、focusBlockId 指向原子卡本身（无文本视图承接，落焦悬空） | ✗ |
| 19 | imageTextRow | 同上，占位「点击输入说明文字」 | 同原版 | 同上（text:""、无尾随、落焦悬空） | ✗ |
| 20 | musicCard | 本块转 {url:'', meta:null, status:'input'} + 尾随空段；**焦点落输入胶囊本身**、光标在占位文末 | 同原版（apply_type S5 + focus=(bid, MAX) 落胶囊） | node 置 {status:"input", url:""}（无 meta 键，靠归一兜底）+ 尾随段 ✓；但**焦点落尾随空段而非胶囊**——用户还须再点一次胶囊才能粘贴 | ✗ 落点错误 |
| 21 | image | 本块转 image 占位（attrs.fileId='') + 尾随空段（next-empty 不重插），焦点落尾随段；文件选择留待点占位块后 | 同原版（op_insert_media_placeholder，含列表项提出分支） | 本块转 image（attrs 空字典，无 fileId 键，渲染层以 nil 判空、等价）+ **恒插尾随段（不查 next-empty）**，焦点落尾随段 | ◐ |
| 22 | gallery | 本块转 gallery（attrs.items=[]）+ 尾随空段（同上判定），焦点落尾随段 | 同原版 | 同 image 行 | ◐ |

命令表数据本身（act/oid/title/sub/shortcut/group/kw/py）：原生与 Web/原版逐项一致 ✓（含 heading oid="heading"、列表 oid=unorderedList/orderedList 等细节）。

## 表 2：面板机制对照

| 机制 | 原版 | Web | 原生 | 判定 |
|------|------|-----|------|------|
| 触发位置 | 块内**任意位置**：光标前最后一个「/」起至光标、无空白即 token（句中可触发）；URL token（http(s)://、www. 开头）抑制；查询 ≤30 字 | 同原版（桥 processInput，S2/D-1 口径） | **仅块首**：全文须以「/」开头；无 URL 抑制概念（块首模型下不适用） | ✗ S-1 |
| 触发块型 | 任意可编辑块（含标题/引用/待办/**列表项**）；音乐输入胶囊除外 | 同原版（codeBlock 与 mdsrc/音乐胶囊除外；列表项可触发且 op_convert 有提出列表分支） | isText 且非 codeBlock/callout；**列表项不触发**（textViewDidChange 以 listParent==nil 门控） | ✗ 列表项缺失 |
| 触发时机 | selectionchange + 输入双路（光标移入既有「/…」文本也开面板） | 输入驱动（processInput）为主 | 仅 textViewDidChange（文本变化）；光标移入不开 | ◐ |
| 过滤 haystack | `title+' '+sub+' '+kw+' '+type+py` 小写包含（type 与 py 无空格相连） | 同原版（空格连接 title/sub/kw/ty/py） | `title+sub+kw+act+py` 无空格拼接、**以 act 代 type**：查「inline」原版/Web 命中 5 条行内命令、原生零命中；查「code_block」原生零命中；反之查「heading1」原生命中、原版/Web 不命中 | ✗ S-5 |
| 有查询排序 | 前缀命中（title+kw 或 py 以查询开头）优先，其余按标题 `localeCompare(zh-Hans-CN)` | 同原版 | **不排序**，命令表原序平铺 | ✗ |
| 无查询分组 | 最近使用组置顶（存储序），其余按基础/媒体分组且**排除已在最近组者**；最近行带「最近」胶囊标记 | 同原版（slash.recent / recent_pill） | 最近组 ✓（存储序）；但基础/媒体组**不排除最近项（重复出现）**；无「最近」胶囊 | ✗ S-6 |
| 最近使用 | localStorage `memos_slash_recent_v1`，oid 数组，上限 6，执行成功后置顶（含 link 须提交成功后） | 同原版（键名同） | UserDefaults `slashRecentOids`，上限 6 ✓；但 **link 在开表单时即记录**（取消/校验失败也记） | ◐ |
| 命中高亮 | slash-panel hl：标题/副标题中命中段 `<mark>` | 同原版（SlashHl） | 无高亮 | ◐ 视觉项 |
| 空态 | 28px 搜索图标 + 「未找到匹配命令」+ 拼音提示行（kbd 码 `bt` 标题 · `tp` 图片 · `yykp` 音乐） | 同原版（D-5 全形） | 两行纯文本：「未找到匹配命令」+「试试拼音首字母：标题 / 图片 / 音乐」（**无 kbd 拼音码、无图标**） | ◐ 文案/形态不符 |
| 键盘操作 | ↑↓ 循环选中、Enter 执行选中项、Esc 关面板并恢复光标；面板开时 Enter 不拆块 | 同原版（桥 keydown + aria-activedescendant） | 无键盘导航（点选）；**面板开时按 Enter 仍走 shouldChangeTextIn 拆块**，拆后 slashBlockId 仍指旧块、焦点已移新块，面板悬空指向未聚焦块（见 T-9） | ✗（iPad 硬件键盘场景） |
| 面板定位 | 贴光标 rect，靠下上翻，动态限高（≤320 且不溢视口底） | 同原版公式（visualViewport 口径） | 页眉下固定位（top 160）、maxHeight 320 | ◐ 平台适配（已知取舍） |
| 点外关闭 | pointerdown 点外关面板并恢复光标 | 桥 esc/点外同口径 | 点块外/切块由 updateSlash 状态收口，无显式点外关闭 | ◐ |

## 表 3：普通文本语义对照

| # | 语义 | 原版 | Web | 原生 | 判定 |
|---|------|------|-----|------|------|
| T-1 | 段落回车拆块 | 光标处拆分，后半成新段，光标落新段首 | 同（op_split 通用路径） | splitBlock 同口径 | ✓ |
| T-2 | **标题回车** | **不拆文本**：整段保留，其后插空段落，光标落空段（editor.js 非段落块 Enter 分支） | 同原版（B1：heading/callout 不拆、插空段） | **按光标拆分标题文本**，前半留标题、后半成新段落 | ✗✗ 与原版/Web 均不符 |
| T-3 | 待办/引用回车（非空） | 同 T-2（不拆、插空段）——原版口径 | **调优偏离原版**：拆为同型新块（新待办未勾选） | 拆为同型新块（新待办未勾选） | ◐ 与 Web 一致、与原版有别（Web 侧已定案的调优） |
| T-4 | 待办/引用回车（空块） | 不拆、插空段（空待办保留） | **自身转 paragraph 退出**（调优口径） | 再拆出一个**空待办/空引用**（splitBlock 恒产同型新块） | ✗ 与两者均不符（空待办垃圾块正是 Web 口径要避免的） |
| T-5 | 列表项回车（非空） | MD 源段口径（列表为源文本行） | 同型新项（op_split list-item） | insertLines 新项 | ✓ |
| T-6 | 空列表项回车 | 退出列表成段落 | 同（op_split 劈表、尾表 start 传递） | exitListItem 劈表 ✓；但尾表**不带 start 传递**（原生列表 attrs.start 语义下新表恒自 1 起？——原生 numbered 渲染取 attrs.start，劈后尾表无 start 即 1，原列表 start>1 时编号重启） | ◐ 编号起始风险 |
| T-7 | 代码块回车 | 块内换行 | 同（桥 codeBlock 分支放行原生） | return true 放行 | ✓ |
| T-8 | Shift+Enter 软换行 | keydown 直接 return 放行浏览器默认（块内 `<br>`） | insertLineBreak + pasteSync（`\n` 落文本） | EditorTextView.pressesBegan/Ended 跟踪 shiftHeld，shouldChangeTextIn 放行原生插入 | ✓（限硬件键盘；shiftHeld 若在焦点切换时漏收 pressesEnded 可能粘滞，代码级小风险） |
| T-9 | 面板开时 Enter | 执行选中命令，不拆块 | 同 | **照常拆块**且面板状态悬空（见表 2 键盘行） | ✗ |
| T-10 | 段首退格并块（prev 为文本块） | 单宿主浏览器默认合并 | op_merge：并入 prev、光标落接合处 | mergeBlockBackward 同口径（接合处 pendingCaretOffset） | ✓ |
| T-11 | 段首退格（prev 为原子块，当前**空**段） | 向前跳过全部不可编辑块、删空段、光标落更早可编辑块末尾；无目标则保留空段 | 同原版形式化（op_merge Atomic 支） | mergeBlockBackward：prev 非文本即 return，**空段删不掉、光标不动**（键被吞） | ✗ |
| T-12 | 段首退格（prev 为原子块，当前非空） | 单宿主默认行为（无专项收口） | 不删卡：原子块入选中态，两块全保留（K2） | 无动作（无块选中态概念） | ◐ 结果同为「不删」，缺选中反馈 |
| T-13 | 段首退格（prev 为**列表块**） | 单宿主默认合并进末项 | op_merge：prev_sibling 把列表末项作 Text 目标，**段落并入末项**、光标落接合处 | prev 为 list 块、isText=false → return，**无动作** | ✗ |
| T-14 | 首项退格（非空） | 单宿主默认（并入前块） | 按 prev_sibling 分类：并入前文本块末尾（光标落接合处）/原子规则 | mergeListItemBackward：**把该项提出列表成段落**置于列表前，光标落该段**末尾** | ✗ 语义与落点均不同 |
| T-15 | 首项退格（空项） | 同上 | 删项、光标落前块末尾（或原子规则） | 删项、光标落**下一项**末尾（列表清空时整表转空段） | ✗ 落点不同 |
| T-16 | 项内退格（idx>0） | 默认合并 | 并入上一项、光标接合处 | 同 Web | ✓ |
| T-17 | 多行粘贴（顶层文本块） | 粘贴经 parse 落模型、逐行成块 | pasteSync 解析剪贴板 HTML（**保留行内标记**）后拆块 | EditorTextView.paste 拦截纯文本：insertLines 逐行成块（同型/heading 降段），**插入行一律纯文本 run（标记丢失）**，before/after 标记保留 | ◐ 结构一致、富文本粘贴丢格式 |
| T-18 | 多行粘贴（列表项内） | 逐行成项 | 同（拆项） | handlePaste 以 listParent==nil 门控→回落 super.paste：若系统不回调 shouldChangeTextIn，`\n` 将整段塞进**单个项的文本**（项内多行、数据形污染）；若回调则走 insertLines 正常拆项——**取决于系统粘贴是否触发 shouldChangeTextIn，代码级未证风险** | ✗/风险 |
| T-19 | 粘贴裸 URL 成卡 | 有（paste 卡片链） | 有（op_paste_card） | 有（handlePaste 判卡） | ✓ |
| T-20 | 拼音组字不介入 | keydown 首行 composing/229 直接 return；组字中不触发斜杠/拆并 | 桥 composing 标志门控 keydown 与 realtimeHighlight；组字中不检测斜杠 | shouldChangeTextIn 以 markedTextRange!=nil 整体放行（拆/并/软换行均不介入）✓；但 **textViewDidChange 组字期间仍把组字中拉丁串写入 block.runs/text 并调 updateSlash**（updateUIView 有 marked 守卫不重渲染、提交后自愈；残余风险：组字中途 autosave 落盘拼音串、组字串以「/」起头时面板误开） | ◐ 基本一致 + 小风险 |
| T-21 | Esc | 面板开→关面板恢复光标；链接表单→回列表；块选中→取消选中 | 同原版（桥 esc 分流 + overlay Esc） | 0.9.2 隐形快捷键钮：关链接表单（**不回列表**）/斜杠面板/背景底表/菜单、标题编辑中还原草稿；文本块内 Esc 无动作（软键盘无 Esc 键） | ◐ 浮层收口大体齐，链接表单 Esc 去向不同 |
| T-22 | 段首退格（首块/无 prev） | 无动作 | 无动作（PrevKind::None） | guard i>0 return（键被吞、无动作） | ✓ |

## 差异与风险清单（按严重度）

- **S-3（高）行内五命令在原生全部失效**：bold/italic/highlight/code/strikethrough/link 因「剩余文本恒为空 + 按 runs 施加」模型，点选后无任何可见效果（表 1 #8/9/10/15/16/17）。原版/Web 的语义核心是**无选区时插入占位**（`**文字**` 字面 / `<b>文字</b>` / `[链接文字](url)`），原生缺这一整层。
- **S-1（高）触发模型窄化**：原生仅块首触发 vs 原版/Web 块内任意位置 token 触发。用户在句中输入「…/bt」原生无面板；且连带使 S-3 的选区语义无从建立（token 前文本在原生不存在）。
- **T-2（高）标题回车拆分标题文本**：与原版/Web 的「不拆、其后插空段」口径相反，中段回车即把标题切成「半个标题 + 段落」。
- **S-4（中）链接表单三处不符**：无 `https://` 预填全选；校验失败静默关表单无报错（且「/」token 已先行剥除，用户无从修正）；取消不回命令列表。另 link 的最近使用在开表单时即记录（Web/原版为提交成功后）。
- **T-4（中）空待办/空引用回车**：原生再产一个空同型块，与 Web「自身转段落退出」及原版「插空段」均不符。
- **T-11/T-13/T-14（中）段首退格三处缺口**：prev 为原子块时空段删不掉；prev 为列表块时段落无法并入末项；首项退格原生作「提出成段」而非「并入前块」，落点亦不同（段末 vs 接合处）。
- **S-2（中）尾随空段规则成片偏差**：todo/callout/imgTextCard/imageTextRow 原生不插尾随段（Web/原版插，imgText 类且焦点应落尾随段，原生落焦悬空于原子卡）；divider/image/gallery 原生不查 next-empty、已有空段仍重复插。
- **S-7（中）musicCard 落点错误**：焦点应落输入胶囊本身（用户下一步即粘贴），原生落尾随空段，需多点一次。
- **T-18（中/未证）列表项内多行粘贴**：回落 super.paste 后是否经 shouldChangeTextIn 拆项取决于系统行为，代码层未设防，存在单项被塞入多行文本的数据形污染风险。
- **S-5（低）过滤口径分叉**：haystack 以 act 代 type + 无空格拼接——「inline」「code_block」类查询原生漏检；排序缺前缀优先 + zh-Hans-CN 标题序。
- **S-6（低）最近使用重复展示**：无查询时最近项同时出现在最近组与所属分组（Web/原版分组排除最近项）；最近行无「最近」胶囊。
- **T-6（低）列表劈分 start 传递**：exitListItem 尾表未传递起始号，start>1 的有序列表退出中间项后尾表编号可能重启（Web 有 E-17 ① 传递口径）。
- **T-9（低，限 iPad 硬件键盘）面板开时 Enter 拆块**且面板指向失焦旧块。
- **数据形分叉（低，跨端注意）**：codeBlock/bulletList/numberList/callout 在原版/Web 是「paragraph + MD 源文本」，原生是真类型块。同库跨端打开时渲染可达一致（Web 有真类型块渲染、原生有 MD 预览），但同一命令在两端产出的存量节点形态不同，后续编辑路径（MD 源码态 vs 类型块态）随之分叉。
- **T-20（低）组字期间模型写入**：textViewDidChange 未做 marked 守卫，组字拉丁串短暂入模型并参与 updateSlash/autosave。
- 文案细节：strikethrough 副标题原版为「~~删除线~~」、Web 语言包与原生同为「包裹选中文字为 ~~删除线~~」（Web 语言包对原版有一处文案改写，三方中原版独异，记录备查）；空态拼音提示行原生缺 kbd 拼音码（bt/tp/yykp）与搜索图标。

## 已一致项（不展开）

命令表 22 条数据全集与分组、最近使用存储上限/置顶序、heading1-3/paragraph/quote 转换、段落拆块、项内并块、代码块回车、Shift+Enter（硬件键盘）、粘贴成卡、首块退格无动作、Esc 浮层收口大体——均已在表中标 ✓/◐。
