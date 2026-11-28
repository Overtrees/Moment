# 卡片防误触机制统一收口（impl_card_guard_unify）

指令（用户 2026-11-28）：代码块加入卡片的编辑/删除防误触机制；再排查哪些块型可接入、一起统一。口径红线依旧（通读后动、行为等价为底线、根治不打补丁、拒绝逐型特判、退役零残留、断言锁机制）。

## 一、现行机制定性（第一段只读，proven 均回源）

「卡片的编辑/删除防误触机制」在 Web 与原生是同一束三件：

1. **菜单独占**：成员块的编辑/删除只存在于拾起浮层菜单一处（Web：长按拾起/右键/悬停钮三路同开 CardMenuLayer，项 = 编辑（has_edit 名单）+ 删除；原生：按压引擎拾起 → cardMenuLayer，项集与几何逐项同构）。普通点按只达块的主功能面（开图片页、播放、选图），永不到达删除。
2. **键盘不变量（Web K1/K2）**：键盘永不直接删除非文本块——选中态下 Backspace/Delete 无操作（editor.js document 级收口）；文本块段首退格撞原子前驱只带入选中态（op_merge 原子支），删卡只走菜单明路。原生对应 = F-08（mergeBlockBackward/Forward 原子支 + selectedBlockId 描边）。
3. **成员集单点**：Web `CARD_MENU_TYPES`（editor.js:2456）九型 = imgTextCard/imageTextRow/image/gallery/musicCard/link-card/attachment/video/divider，has_edit 五型 = imgTextCard/imageTextRow/image/gallery/musicCard。原生 `EditorModel.cardMenuTypes`/`editCardTypes` 与之逐字一致（本批前）。

代码块在本批前的处境（原生与 Web 一致）：属文本块（isText 含 codeBlock），编辑 = 点按直入打字（块内换行不拆块、粘贴字面守卫 M-02 已有），但**结构面四向可溶解、全部无守卫**——① 自身段首退格并入前块；② 自身块末前删吸收后块；③ 后继段落段首退格把它当前块吸入（prev.isText 支）；④ 列表首项退格并入它、列表末项前删吸入它。代码是字面内容（Web B11 把 codeBlock 与 mdsrc 并列为「源码态块」），任一向合并都使代码脱离代码块身份、与散文混写，是卡片天然免疫的那类误触。删除入口则混在拾起的**类型转换菜单**末位（8 项滚动面板），与「正文/标题…」等同样具结构后果的转换项同列。

## 二、全块型普查表

判据：(a) 块为原子/框定单元、内容不以跨块文本流方式编辑（源码态字面内容同列）；(b) 现行存在点按/键盘可达的结构破坏面（删除/溶解/吸收）未被守卫；(c) 接入不剥夺该块型的主功能路径（以打字编辑正文为业的块型不接入）。

| 块型 | 内容模型 | 现行编辑入口 | 现行删除/溶解面 | 判定 |
|---|---|---|---|---|
| paragraph | 文本流 | 点按打字 | 合并流即其编辑模型 | ✗ (a)(c) |
| heading | 文本流 | 同上 | 同上 | ✗ |
| todo | 文本流+勾选钮 | 同上 | 同上 | ✗ |
| quote | 文本流 | 同上 | 同上 | ✗ |
| callout | 文本流（散文，框形） | 同上 | 同上 | ✗ 散文流；框形非判据，字面性才是 |
| **codeBlock** | 源码态字面文本 | 点按打字（保留） | 四向溶解无守卫（见上）；删除混于转换菜单 | **✓ 接入（用户点名）** |
| bulleted/numbered-list | 容器+项文本流 | 项内打字 | 整表删除已仅块菜单单项；项级合并是其编辑模型 | ✗ (a)(c) 容器文本流 |
| list-item | 项文本流 | 项内打字 | 项合并流 | ✗ 非顶层块型 |
| image/gallery/imgTextCard/imageTextRow/musicCard | 原子卡 | 卡菜单编辑态 | 仅卡菜单 | ✓ 已在集（基线） |
| link-card/attachment/video/divider | 原子卡 | 无编辑态 | 仅卡菜单 | ✓ 已在集（基线） |
| **embedCard** | 原子（只读兜底渲染、无编辑面） | 无 | 键盘面靠 !isText 隐性守卫；拾起却走块菜单（与卡菜单同为删除单项、归属与标签不一） | **✓ 接入（菜单路由归一）** |
| 未知块型 | 降级纯文本保全 | 无 | !isText 隐性守卫 + 块菜单删除单项 | ✗ 不可枚举入集；现状同等保护，留注 |
| MD 源码段 | paragraph 的呈现态（非独立块型） | 点按打字 | 段落合并流 | ✗ 无独立块型可入集；如需同等保护须另立维度，留账 |

跨块选区（XSel）删除/替换为显式选区操作（用户可见地选定范围后执行），非误触面，全型一致、本批不动（XSel 对 codeBlock 另有源码态分类 isXSelSourceBlock，不受影响）。

## 三、落码（第二段，单点收口）

**成员集单点**：`EditorModel.cardMenuTypes` 增 `codeBlock`、`embedCard`（9 → 11 型）；`editCardTypes` 不动（新成员菜单只出「删除此块」，与 divider/attachment/video/link-card 同形态；代码块打字编辑仍点按直入——那是其主功能路径，不设编辑态门）。

**分类单点**：`BlockState.isStructuralAtomic` = `!isText || cardMenuTypes.contains(type)`——回答「结构可否被键盘合并/溶解」，与 isText（「内容可否打字编辑」）分立。成员集全文件仅两处消费：本谓词 + BlockRow.isCardType（拾起菜单路由）。

**守卫消费点（全部经同一谓词，无逐型特判）**：
- `mergeBlockBackward`：新增自身守卫支（成员段首退格不并出、只落 Diag `EDIT merge backspace guarded self`）；prev 支改判 `prev.isText && !prev.isStructuralAtomic`（prev 为代码块落既有 F-08 选中支）。
- `mergeBlockForward`：镜像——自身守卫支（Diag `EDIT merge fwd guarded self`）+ `next.isText && !next.isStructuralAtomic`（next 为代码块落后继选中支；自身守卫同时堵住吸收后继列表首项一路）。
- `mergeListItemBackward`：首项并入支排除守卫前驱；F-08 支分类由 `!isText` 直判改经 isStructuralAtomic（对既有型逐 case 等价：卡/空表仍入、非空表仍不入、文本仍不入；仅新增代码块入选中支）。
- `mergeListItemForward`：末项吸收支改判 `next.isText && !next.isStructuralAtomic`（next 为代码块落既有选中支）。
- `BlockRow` F-08 选中描边：呈现条件由 `!block.isText` 改 `block.isStructuralAtomic`（代码块被带入选中态同显描边；纯文本块从不置位 selectedBlockId，无误伤）。

**保留口径（有意）**：空成员（空代码块）段首退格/块末前删仍走既有空支自删——无内容可失，与 Web op_merge 空段支「只删空段本身」的不变量一致，不在守卫面内。空邻块退格时 nearestTextBlock 仍可落代码块首/末（仅焦点落点，不动结构）。

**行为此消彼长（如实记）**：代码块拾起菜单由类型转换菜单（7 转换 + 删除块）变为卡菜单（删除此块单项）——「删除与转换同列」的误触面即是指令要关的面；转入代码块（斜杠/粘贴 ```）不受影响，转出代码块的菜单路径随之退役（可经撤销恢复）。embedCard 拾起菜单由块菜单变卡菜单（同为删除单项，标签「删除块」→「删除此块」）。

**与 Web 口径的差异（有意偏离，标注在案）**：① codeBlock——Web B11 明文其段首退格走 op_merge 合并流，本批按用户指令在原生加守卫，Web 侧不动（后续如需双侧一致另立批）；② embedCard——Web CARD_MENU_TYPES 无此型（其渲染兜底同源），原生归一菜单路由。

## 四、断言

verify_ios.sh 新增 **[66] CG66-1..8**：成员集恰 11 型含两新成员 / 文本流五型不在集 / editCardTypes 恒 5 型不含新成员 / 分类单点定义式 + 成员集恰两处消费 / 退格双向守卫 / 前删双向守卫 / 列表镜像三支 / 选中描边同点。**FD58-5 改判**：前向 Diag 谱系计数 6 → 7（新增守卫自身行），注释已注改判缘由。

## 五、验证（本机口径）

- [66] 八项全 ✓（尾部组以同头 harness 单独执行核验：全量脚本当前在 [63] 前页脚处先行 exit，他线在途红使 [65] 后组别在全量跑中不可达——见留账）。
- 邻接回归：[58] FD58-1..5 全 ✓（含改判后 FD58-5）；全量跑红清单与本批前一致、无一落在本批面：ipa 陈旧 + 五语键数/产物语言包（i18n 线在途）、B16-15/B25-10/B27-2（桥/M3b 线在途）、J20-13（斜杠线）、T24-5（标题线）、EB63-3（审计批 4 在途）。尾部邻组 HM65-5、B67-3/B67-5 为各线自家在途红，未动。
- cargo test --workspace 全绿（0 failed）。

## 六、真机终判点（不升级表述）

1. 长按拾起代码块 → 出卡菜单（删除此块单项）、embedCard 同；拾起拖动/取消后菜单无残留。
2. 代码块四向键盘面：自身段首退格/块末前删无动作（Diag guarded self 行）；后段段首退格撞代码块 → 代码块描边选中、不并入；列表首/末项邻接代码块同。
3. 代码块打字/块内换行/粘贴字面与既往一致；空代码块退格自删如旧。
4. 长按手感与误触收益本身归真机终判。

## 七、留账

- verify [66] 组与尾部判读行在工作区未提交：尾部为 [65][66][67] 三线共享的 EOF 追加区（三组同在一个 diff hunk 内，索引级分离会伤他线待组），随组版收口时与 [65][67] 一并成笔；FD58-5 改判已单独成笔。
- [65] 组被追加在脚本中段 ALL PASS 页脚（原 8313 行）之后，其失败在全量跑中不触发 exit——本批已在文件尾补判读行兜底（含 [65][66]，后为 [67] 线扩为 [65][66][67]），页脚归位留组版收口。
