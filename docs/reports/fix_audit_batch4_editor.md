# 全面审计批 4（编辑器遗留）落地报告

2026-11-28。范围：总册批 4 = AUD-B-01/B-03/B-04/B-06/B-11（F-16+M-09）/B-12（M-10）/B-13（F-13），另 SL-16 校验面随 B-04 同批（总册 §1.3）。分册源：docs/reports/audit_full_b_editor.md。落码面：rust/apps/ios/app/MomentApp.swift 编辑器段 + verify_ios.sh [63] 组（新开，EB63-1..9）与 J20-13 改判。不推送、不出包；本机自检（tree 不抢，编译门留组版 tree 冒烟）。

## 一、依赖映射（先行结论）

**批 4 无一项真依赖未落地的 E5/E6 能力。** E5/E6 只是 audit_editor_deep.md:92-93 的排期簇名（E5=拖拽/双栏、E6=浮层/表单），其修复处方在当年审计里已全量写明、本批逐项按处方落码。逐项映射：

| 项 | 内容 | 依赖判定 | 落码 |
|---|---|---|---|
| B-04（m-03） | 斜杠 URL 抑制与 Web 分叉 | 独立。Web editor.js processInput 原式在仓可逐字移植 | ✓ EB63-1 |
| SL-16 | 链接提交校验面（原生前缀判更宽） | 独立。Web render.rs submit_slash_link 口径在仓 | ✓ EB63-2 |
| B-01 | 公式块转换弃正文 | 独立。applySlash 内单支 | ✓ EB63-3 |
| F-13（B-13） | 链接表单取消不还原 token（丢字） | 独立。Web 提交时才剥口径在仓；原生 adjustedSel/trimmedSel 换算现成、参数化即共用 | ✓ EB63-4 |
| B-06（m-05） | sheet 前不清斜杠态（幽灵面板） | 独立。三 sheet 呈现真值现成 | ✓ EB63-5 |
| M-10（B-12） | 拾起取消不清菜单（孤儿菜单） | 独立。复位点两处现成 | ✓ EB63-6 |
| M-09（B-11 半） | flow 双栏拖拽被隐形栏界钳制 | 独立。Web ops.rs move_block 无钳制作参照 | ✓ EB63-7 |
| F-16（B-11 半） | 拖拽不维护 layout 锚 | 独立。normalizeBoundary/名单写形现成 | ✓ EB63-8 |
| B-03 | 斜杠面板锚整块底非光标行 | 独立。caretRect 窗口通道已为横向锚在位（F18），同矩形扩 Y 即可 | ✓ EB63-9 |

唯一外部牵连：M-09/M-10/F-16 的**运行时场景验证面**在 U3 拖拽自检（EDT-25/32/33 仍属真机/自检 unknown 面）——代码与静态断言先落，场景验证随 U3 既有排期，不构成本批阻塞。m-06（liftScale 改吃面量测）在 E5 原始行内但不在总册批 4、也不在本批任务清单，不在本批范围。

## 二、逐项落码

1. **B-04（ebb2524）**：updateSlash 抑制判定整段换 Web 同式——含本斜杠的非空白 token（自斜杠向前至空白、含斜杠本身）剥前导字符集 `([{<"'"‘` 后，lowercased 以 http://、https://、www. 开头则抑制。旧两判（前字为 `:`/`/` 抑制 + 所在词词首判、大小写敏感、无剥除）在 `HTTP://`、`(www.` 等形态与 Web 分叉，已废除零残留。
2. **SL-16（711b7e7）**：applyLink 校验由前缀判改解析口径——URL 可解析 + scheme 白名单 http/https + host 非空（Web submit_slash_link 同面）。已知残余微差：无斜杠形态 `http:example.com` Web 经 WHATWG 归一化后受、原生拒（旧前缀判同样拒，无回退），不追。
3. **B-01（4adb4ef）**：applySlash mathBlock 支改围栏保内容——正文非空时 `$$` 两行夹原 runs（行内标记随行保留），为空时产出与旧围栏三行 `$$\n\n$$` 逐字同、光标仍落中行行首偏移 3。0.9.46 旧断言锁的字面与偏移均不破。
4. **F-13（462c588，全批最要紧，丢字类）**：链接表单改提交时才剥 token。旧链 applySlash 无条件压历史 + applyInlineSlash 先剥 token 再开表单 + scheduleSave 已落盘，取消/Esc 只清会话字段——token 永久消失且已落盘。改延迟剥离：applySlash 对 link 不压栈、不落盘；applyInlineSlash 的 link 支提到 removeRunRange 之前只记账（选区剥前坐标 + token 起点/长快照，新增 linkTokenLen 字段）；applyLink 校验通过后压栈、剥 token、以同一 adjustedSel+trimmedSel 序列把快照映射到剥后坐标再打标——落点与旧即时剥离逐字同；校验不过的提交也不再丢 token。adjustedSel 参数化供即时/延迟两路共用。取消/Esc 两面零改动自动变正确（文本从未被动）。
5. **B-06（73c0ba5）**：EditorView 三枚 onChange 漏斗——选图/文件/换图任一 sheet 呈现真值转真即清 slashBlockId（Web input.click 前 closeMenu 同界）；只清面板态，token 文本与独立的 linkForm 会话不动。
6. **M-10（f966b93）**：EditorModel 新增 clearDragState(for:) 单点（跟手量 + cardMenuBlockId/blockMenuBlockId 全按 id 守卫清），onCancel 与行 onDisappear 改调它；commitDrag 落位路不经此路（原地松手留菜单待点选是定案）。
7. **M-09（bfbd828 + d5a8e42 补提）**：commitDrag 落点钳制与 dragShift 栏界门同源同改，加 twoPaneIndependent 条件——flow 下两门皆开、independent 钳制不变。
8. **F-16（40e29b5）**：commitDrag 重排前以现 layout 经 normalizeBoundary 记有效分界数（锚不存在不维护），independent 锚在位时重排后名单按新序以同一分界数切分重写、mode 保留（缺省 independent），Diag 打点 `EDIT drag anchor maintained`。flow 不读不写 layout 分界不在此列。窄屏休眠期跨锚拖拽不再令名单与新序脱钩。
9. **B-03（b5bee2a，修复见 §三）**：纵向锚改光标行。textViewDidChange 同一光标矩形一并取行上下缘窗口 Y → updateSlash 新参 caretLineTop/Bottom 写入 slashAnchorTopY/BottomY 并绑定触发块 id；slashLayer 锚与当前块相符时 belowTop = 行底 + 10、上翻/限高按行顶（anchorTop）算，窗口系直接用、不加 editorScroll 的 +155；缺失/异块逐字回退旧块底公式（UITest 直调 updateSlash 不带行锚、走回退）。连带改判 J20-13（ceeab61）：下限式由 `max(top - 10 - 12, 120)` 随锚改 `max(anchorTop - 10 - 12, 120)`，回退式在位与旧 48 零残留不变量不变。**前提待证伪点**：窗口 Y 与面板层同源沿 slashAnchorX 既有口径（F18 已 shipped），真机/U3 量测若得恒定偏移，先查此前提。

## 三、并行事故与修复（如实记录）

本批与状态栏回退、媒体批 3、首页批 6、标题、权限诸线同仓并行，共享工作树 + 各线临时 index 提交，发生三起竞态，均已修复收口：

1. **462c588 扫入媒体线 [64] 组**：F-13 提交时 verify 尾部我的 EB63-4 与媒体线刚追加的 [64] 组（审计批 3）相邻，git 合并 hunk 后被内容过滤整段带入。内容逐字无损、仅归属错位。**知会媒体线：[64] 组已在 HEAD（462c588），其批 3 提交只需源码面，勿重复添加。**
2. **EB63-5 在 HEAD 重复一份**：[65] 组提交的基线错位令 EB63-5 块在 [64]/[65] 组间多出一份副本（断言重复执行、计数虚增）。91e7569 按 HEAD 实文手术删除误入副本，[63] 组内正份不动。
3. **陈旧基线回绕吃掉四项源码**：某线以陈旧基线提交时，M-10/M-09/F-16/B-03 的源码改动被冲出 HEAD 树（对应 EB63-6..9 断言在 HEAD 俱在、源码缺失，B-03 更令字段引用悬空、HEAD 不编译）。5ae9679 按工作树同文逐字回补四项全部缺失段（12 处替换逐一断言唯一命中，108+/24-），回补后 HEAD 与工作树在 commitDrag/clearDragState/slashLayer 三段逐字一致（slashLayer 仅差他人未提交的 slashPanelMaxH 尾段，非本批）。教训：临时 index 提交必须 read-tree 与 commit 同一 exec 内完成且提交后立即核树对账；长间隔的 read-tree→commit 窗口即回绕源。

另 EB63-3 断言自身一处提取 bug（b775d84 修）：段提取 awk 的 exit 模式未加 f 守卫，被文件前段另一 switch 的 `case "callout":` 提前截断、段恒空假红；补守卫后实测通过。

4. **报告提交误提陈旧暂存（本笔自伤，112cd9c 已修复）**：报告提交时误用普通 git commit，把真实 index 中他人暂存的陈旧回退（批 4 诸段与 J20-13 改判的删除形态）一并提入（12826cb）。随即以父提交 ceeab61 的两文件 blob 逐字恢复（112cd9c），实证 ceeab61→HEAD 净变化仅报告文件一份。教训与 §三.3 同源：本仓并行期一切提交走临时 index + 内容过滤，普通 git add/commit 禁用。

## 四、本机自检

- **[63] 组独立复跑 9/9 全过**（自 verify 提取本组段以脚本同款 ok/bad/has 环境执行，避并发编辑对整脚本的增量解析干扰）。
- **verify 全量**：658 ✓。红 8 项逐项归属：ipa 陈旧 + 产物语言包不一致（基线产物红、重建自清，与动手前基线 594 ✓ / 2 红同类）；J20-13（本批 B-03 连带，ceeab61 改判后实测通过）；B16-15/B25-10（桥工具清单，桥线在途）；F30-2（批 6 在途）；PC44-6（权限线在途）；T24-5（标题线在途，TitleTextField 领地、本批未触）。**本批零新增红。** 全量运行期间脚本被并发编辑增量解析打断两次（日志停摆/7765 行伪语法错误），第三次跑完——此为并行期整脚本运行的已知不稳定，非断言失败。
- **邻接组复跑**（含于全量）：[24] 标题（除 T24-5 外全绿）、[43] 编辑回路、[47] 撤销体系、[48] U4b 撤销场景、[50]/[51] 跨块选区一/二期全绿；0.9.46 公式断言在 B-01 新形态下通过。
- **cargo test --workspace：239 全过**（本批未动 Rust，符合预期）。

## 五、移交与未决

- 编译门：本机无 swiftc，本批 Swift 改动未经本机编译；组版 tree 冒烟（smoke_ios.sh）为编译级终验。
- B-03 窗口 Y 同源前提、M-09/M-10/F-16 运行时行为：随 U3 拖拽/面板自检场景（EDT-25/32/33）与真机装机终判。
- 媒体线 [64] 组归属知会（§三.1）请组版时转达。
