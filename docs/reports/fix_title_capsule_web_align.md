# AUD-B-02 落码：标题胶囊口径对齐 Web

- 日期：2026-11-28
- 批次：0.9.63（未提交，留主线组版）
- 裁定：全面审计 AUD-B-02 登记的口径源冲突（旧在册口径「恒显全文」与 Rust Web
  title.rs 现行码非编辑态 10 字截断互斥），用户 2026-11-28 裁定以 Web 现行码
  为准绳、原生逐项对齐。本批据此落码。
- 范围：编辑器标题胶囊（原生 EditorHeaderView 标题段 + TitleTextField.swift +
  TitleTapCaret.swift）对 Web（rust/apps/web/src/editor/title.rs、
  title_controller.rs、styles/editor.css 标题段）的逐项对齐。

## 一、对齐表（逐项）

Web 出处：title.rs = T、title_controller.rs = TC、editor.css = CSS。
原生出处：MomentApp.swift EditorHeaderView 段 = HDR、TitleTextField.swift =
TF、TitleTapCaret.swift = TCaret。

| # | 项 | Web 口径（出处） | 原生现状 | 判定 |
|---|---|---|---|---|
| 1 | 非编辑态截断字数 | chars 数 >10 截断（T:22-27） | unicodeScalars 数 >10 截断（HDR capsuleWidth shown / 覆盖层 / 落点入口三处同式） | 一致（Rust chars ≡ Unicode 标量，原生 B-6 已按标量口径、非字素簇） |
| 2 | 截断形态 | 前 10 字 +「…」（U+2026 单字，T:26） | scalarPrefix(10) +「…」三处同式 | 一致 |
| 3 | 空标题非编辑态显示串 | display 串 = i18n「无标题」（T:23-24），宽度量测同串 | shown =「无标题」量测（HDR capsuleWidth） | 一致（呈现载体差见注记 2） |
| 4 | 编辑态显示 | input 值 = 已提交全文、永不截断（TC on_focus） | 字段恒持草稿全文、截断仅覆盖层呈现（HDR titleCapsule） | 一致（结构不同：Web 换值、原生覆盖层；行为等价） |
| 5 | 定宽量测串 | 两态量当前值：非编辑 = 显示串、编辑 = 实时全文（TC sync_width / live_text） | shown 同分流（未聚焦量显示串、聚焦量草稿全文） | 一致 |
| 6 | 定宽 meta 下限 | max(标题宽, meta 宽)，meta 隐藏（行态）时不计（TC sync_width_for） | max(titleW, metaW)，紧凑态 metaW = 0（不渲染同源） | 一致 |
| 7 | 定宽加项 | + 内距 40 + 边框 1（0.5×2，border-box；TC sync_width_for + CSS padding 0 20px / border 0.5px） | 原 +40：内距计入、边框漏计（原生玻璃边框为 overlay 内描边、不占布局，总宽差 1pt） | **偏离 → 本批改 +41**（公式侧补边框项，总宽与 Web 逐值一致） |
| 8 | 定宽下限钳 | 66（TC MIN_CAPSULE_W + CSS min-width） | max(…, 66) | 一致 |
| 9 | 定宽上限钳 | avail = 坞内容宽（W−124）；行态再扣可见兄弟宽（头像 72）+ gap 8×兄弟数（TC avail_width） | maxW = headerW − 124，紧凑再扣 chrome 80（=72+8） | 一致（量测通道差见注记 3） |
| 10 | 内距 | 胶囊 padding 0 20px、两态同值、input padding 0（CSS） | .padding(.horizontal, 20)、字段无内距 | 一致 |
| 11 | 居中 | input text-align:center；胶囊在坞内 flex 居中、变宽中心锚对称展开（CSS + TC 模块注） | 字段 .center、覆盖层居中、页眉 HStack 双 Spacer(minLength: 0) 对称 | 一致 |
| 12 | 弹性增长 | width transition 0.2s ease；挂载首写免 transition（CSS + TC sync_width） | .animation(easeInOut 0.2, value: capsuleWidth)；.animation(value:) 只动变更、首现不演 | 一致（时长同 0.2s；曲线 ease vs easeInOut 为平台近似，注记） |
| 13 | 胶囊高 / 圆角 / 边框宽 | 66 / 33 / 0.5（CSS） | capsuleHeight 默认档 66（+DT 增量）/ Radius.titleCapsule 33 / strokeBorder 0.5 | 一致（默认档逐值；DT 增量为原生平台口径、用户已裁） |
| 14 | 字号 / 字重 / 字距 | 14px / 600 / −0.2px，两态恒定（CSS） | fieldFont 14 semibold + kern −0.2（量测/字段/覆盖层三方同源）+ DT 缩放 | 一致（默认档逐值；DT 为平台口径） |
| 15 | meta 字号 / 隐藏 | 10px（--font-10）；行态 display:none（CSS） | dynFont 10（.caption2 缩放）；紧凑态整行不渲染 | 一致 |
| 16 | 点按落点 · 介入条件 | Idle 且全文 >10 字且现值确为截断形态（TC pointerdown + tap_caret_target 守卫） | 未聚焦且草稿 >10 标量（构造上现值恒为截断形态，与 Web 守卫等价） | 一致 |
| 17 | 点按落点 · 算式 | 显示串居中几何 → 逐前缀实测宽最近边界；边界 ≤10 同位、=11（省略号）→ 全文末尾（TC tap_caret_target） | TitleTapCaret.caretScalarIndex 同式（标量口径、逐前缀宽由呈现同源属性量测） | 一致（同距决胜差见注记 1） |
| 18 | 点按落点 · 键盘/程序聚焦 | 无记号且换值 → 落文末；无记号未换值 → 不干预（TC on_focus / place_caret_next_frame） | 程序化置焦无记号、字段原生落点（字段恒持全文、iOS 落焦默认文末向） | 一致（行为等价） |
| 19 | 提交口径（关联面、防回归核对） | blur trim、空回退「无标题」字面提交；Enter 走 blur；Esc 还原会话起始文本后 blur 不提交（TC on_blur / keydown） | commitTitle trim + 空回退（T24-5 锁）；shouldReturn 辞焦提交；handleEscape 还原 titleBase（快照 = 聚焦时 editor.title） | 一致（提交时序差见注记 4） |

## 二、落码清单

1. **MomentApp.swift · capsuleWidth**（本批唯一行为改动）：定宽公式
   `max(titleW, metaW) + 40` → `+ 41`，补齐 Web 公式的边框项（Web border-box
   计入总宽；原生边框 overlay 不占布局，由公式侧补足）。同处加口径注释两段：
   shown 量测串的 display_title_of 出处与本裁定、定宽公式的 sync_width 出处
   与 +41 构成（内距 40 + 边框 1）。
2. **verify_ios.sh · [24] 组新增 T24-7**（口径对齐锁）：锁 ① shown 状态分流
   （未聚焦且 >10 标量走截断串）② 截断呈现串构造点（落点入口 disp / 覆盖层 /
   shown）合计 ≥3 ③ 定宽 +41 在位、旧 +40 零残留。

## 三、改判清单（旧口径的处置）

| 旧锁定点 | 原口径 | 处置 |
|---|---|---|
| MEMORY「Mynote title capsule — CLOSED」条 | Web 无字数上限、恒显全文；原生 10 字截断为自创口径 | 用户 2026-11-28 裁定作废、对齐 Web（主线已改判 MEMORY 在册条目，本批不另动 MEMORY） |
| verify_ios.sh 断言 | 无任何断言锁定「恒显全文」（全域 grep 零命中） | 无旧锁可改判；T24-7 为新口径的防回潮锁（首锁），已在断言头注写明沿革 |
| 原生代码注释 | commitTitle 头注（失焦/回车提交、非编辑态超 10 字截断）、TitleTapCaret 头注（Web display_title_of 口径）本已按 Web 口径书写 | 不动；capsuleWidth 处补齐出处注释（原缺） |
| audit_full_b_editor.md / 总册 AUD-B-02 | 「待裁、裁定前不判缺陷」 | 裁定已下：归属 = 原生现行截断为正、本批完成逐项对齐；审计册本文不回改（历史卷），以本报告为收口据 |

## 四、保留注记（知情差，非本批改动）

1. **点按同距决胜**：点按恰在两相邻前缀边界正中点时，Web 实现以严格小于取
   较早边界（省略号正中 → 第 10 字），原生取较后边界（→ 全文末尾）。原生此
   式为 plan_title_tap_caret.md §5.2 期望表的明文定案（省略号中心 → fullLen，
   宿主数值断言锁定），且与 Web tap_caret_target 的注释口径（落在省略号上 →
   全文末尾）一致——Web 实现在该单点的浮点决胜与其自身注释口径相左。仅精确
   中点可达、其余点位两端全等。本批按「落焦既有机制不得回归」保留原生式，
   在此明示，主线如裁定改从 Web 实现、须同步改 §5.2 期望表与 [26] 宿主断言。
2. **空标题呈现载体**：Web 非编辑态把「无标题」作 input 实文本以正文色呈现；
   原生字段为空、走 UITextField placeholder（系统占位色），T26-9 已锁占位色
   与旧 SwiftUI 字段同源。此差不在本批枚举面（截断字数/形态、宽度、内距、
   居中、弹性、落点）内，且属既有定案，不动。
3. **可用宽量测通道**：Web 运行时实测坞布局；原生以页眉实测宽 headerW − 124
   （− 紧凑 80）等值换算，headerW 未量得（首帧）时回退 240——量测通道差，
   落定值同口径，[7] 前提组已锁 Spacer 紧贴与公式同在。
4. **提交时序**：Web 组字落定（compositionend）先原文提交一次、失焦再 trim
   提交；原生仅会话末 commitTitle 一次提交（trim 后值）。落盘终态一致，中途
   镜像差不在本批枚举面；标题传播机制（commitTitle 同步冲刷）未动、T24-5 与
   TC37-2 漏斗守恒断言全过。

## 五、证据等级

- 对齐表 19 项：**proven**（Web 三文件与原生三文件全量通读逐项对位，含 CSS
  数值与 TC 公式原文）。
- 改动 1（+41）：**proven**（Web 公式原文 = content + pad 40 + border 1；
  原生 GlassCard 边框为 .overlay strokeBorder、布局零占位，源码直读）。
- 标题传播/落焦不回归：**proven（断言面）**——verify [7] 前提组、[24] 全组
  （含新 T24-7）、[26] 全组、TC37-2 本机全过；落点纯函数本批未动，其宿主
  数值断言（tests/title_tap_caret_main.swift）随 tree 冒烟真跑（本机无
  swiftc，与既有分工一致）。
- 真机呈现（胶囊总宽 +1pt 后的观感、截断/落点手感）：**unknown**，归真机
  终判（见 §六）。

## 六、本机自检与真机终判点

本机 verify_ios.sh 全跑：557 ✓ / 2 ✗——2 红为既有产物红（[5] ipa 陈旧、
[9] 产物语言包，tree 重建后归零，WORKFLOW §3.3 在册口径），与本批无关；
标题相关组 [7] / [24]（T24-1..7）/ [26]（T26-1..9）全绿。并发纪律：动工前
后 diff 隔离复核——本批 hunk 仅 capsuleWidth 两处与 verify [24] 一处，
在途 C-02 批的 DiagView/设置帧/尾组改动零触碰。

真机终判点（随 0.9.63 装机）：
1. 长标题（>10 字）非编辑态呈前 10 字 +「…」，点按覆盖层落点与 Web 同位
   （前缀内同位、省略号上落文末），二次编辑可入（字段常驻不回归）。
2. 胶囊宽与 Web 同标题同机型对照：总宽逐值一致（+1pt 边框项生效、长标题
   顶限不溢出横排）。
3. 编辑态恒全文、胶囊随输入弹性变宽、失焦回截断呈现且宽收敛。
