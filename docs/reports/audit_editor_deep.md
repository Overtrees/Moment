# 编辑页全面深挖审计（原生 iOS vs Web 规格）

- 审计时点：2026-11-27，基线 HEAD 477b1bc（0.9.57 / build 84）。只审未落码，仓库零改动。
- 方法：四片并行通读——A 文本编辑回路+标题全链 / B 块操作+转换矩阵 / C 浮层菜单+媒体解析链 / D 拖拽+呈现+双栏+健壮性+转场。每项以 Web 源码为行为规格第一真源、既有定案报告为第二真源，给「达标 / 缺陷 / 缺失 / 定案偏离」判读。
- 证据口径：proven = 指到源码行级机制；凡涉真实手势/键盘/拼音组字/光标投递/系统选择器/外部站解析者，代码级结论最高 inferred、终判归真机或人工——本报告不把任何结构自证写成运行通过。
- 结构性总注（分片 B 查实）：块转换在 FFI 面无对应导出——Web 转换在 editor/ops.rs 模型层、原生在 Swift 模型层，两侧手写对齐、无共享单点；本报告多处转换分叉皆源于此，修复时应优先考虑转换语义单点化（clear_type_fields 等价物）。

---

## 结论总览（去重后）

| 分级 | 数 | 说明 |
|---|---|---|
| 功能级缺陷/缺失 | **19** | 其中 3 项待产品/主线裁定（B-5 落盘形态、Gallery 删/排序、视频插入——均为双侧同缺或口径分叉）；1 项为结构性立项（跨块选区） |
| 形态级缺陷 | **11** | 其中 2 项待裁定/确认（代码块 Enter 口径、图文卡图区图片页登记） |
| 微差 | **6** | 另 1 项平台等价登记不计数（图文编辑底表全屏 sheet） |
| 疑点待定性 | 1 | 前向 Delete 块尾合并（Web 规格未行级坐实，inferred） |
| 定案偏离（登记不翻案） | 10 组 | 见 §7 |
| 回潮核验 | 全过 | 0.9.54 字段常驻、0.9.55 DockSession 锁存、0.9.56 B-4 落点映射/sizeThatFits/占位色、B-1 commitTitle、B-3 Enter/Esc 会话、audit2 E1 跨块方向键、0.9.50 拾起白底——逐项复核仍在位，无回退、无部分回退 |

达标面（无新增缺陷，逐项判读见各域）：输入/删除/拆并块主链、选区恢复与落焦认领、组字结构拦截与提交后终态、粘贴纯文本/富文本/图片成块、标题提交与两坞全链、完成胶囊、待办勾选落盘、公式插入与渲染链接入、斜杠过滤/最近使用/键盘导航/22 命令执行落点、卡片菜单 9 型项集、••• 六项与置灰态、链接校验规范化、图片/Gallery 增换/附件真名与打开分流、图文底表保存提交制、音乐六站点与粘贴成卡状态机、天气双源链与失败回退、面板定高与底表互斥、拾起仲裁/让位/落盘/玻璃框、MD 预览切换与渲染项、图片页入口全集、反向链接、编辑页头像、双栏分界函数与独立五项、在席冲突守卫三消费点、TRANSITION 判据（新建路）与三路转场时序、未知块再保存保真。

---

## 缺陷分级汇总

### 功能级（19）

| # | 项 | 差一句话 | 证据 | EDT |
|---|---|---|---|---|
| F-01 | 拼音组字·didChange 无守卫 | 组字期 marked 中间态每变即入模型、可经 0.6s 防抖落盘、并触发斜杠扫描；与同文件另三处组字守卫自相矛盾，Web 组字期模型冻结 | proven（无守卫确证）/ 落盘命中 inferred | 增补候选（组字段） |
| F-02 | 智能前缀转换整体缺失 | Web apply_smart_prefix（`# /## /### /> /[] /[] /---`）原生零实现（A、B 两片独立查实） | proven | 增补候选 |
| F-03 | 转换不清旧类型字段（B-1） | setBlockType 与斜杠 convert 两路径均不清 checked/level，残留落盘、转回待办勾选复活 | proven | EDT-16/17 |
| F-04 | 列表类型互换语义分叉（B-3） | Web 斜杠对列表项互换 = 整表换型；原生拆表成单项新表，整表互换无任何入口 | proven | EDT-17 |
| F-05 | 列表 start 传递缺失（两处） | exitListItem 尾表 start 丢失致编号重启；mergeListItemBackward 首项删/并后 start 未 +1 致编号漂移 | proven | EDT-15/17 |
| F-06 | 多行文本转列表不逐行拆项（B-4） | 整段塞单个 list-item；Web 逐行加前缀成项（与 F-04/F-07 同族） | proven | EDT-17 |
| F-07 | 斜杠转代码块/提示落盘形态分叉（B-5，待裁定） | Web 产 MD 源段落（runs 全丢、进源码态），原生产真 codeBlock/callout 类型（runs 保留）；代码语言面与变体可编辑性随之分叉——原生形态未必劣，须主线裁定「从 Web 改判等价更优」或「回改 Web 口径」 | proven | EDT-17/19 |
| F-08 | Backspace 段首·原子块前驱死键 | 非空块段首退格、前驱为原子块时三分支全不命中且按键已被吞——无效果、无 Diag；Web 有删原子块/两步选中定案处置 | proven | EDT-15 |
| F-09 | 跨块选区（xsel）整体缺失 | 每块独立 UITextView，选区物理不可跨块，跨块复制/删除/替换不存在；Web 有完整实现与守卫（结构性课题，单独立项） | proven | 增补候选 |
| F-10 | 撤销粒度与栈管理 | 无爆发合并、无去重（未改一字落焦也压栈→幻影步）、上限 50（Web 100）、粒度 = 整个聚焦会话——正是 diagnose_batch4_undo 在 Web 侧根治过的同型问题 | proven | EDT-14 |
| F-11 | 撤销选区/焦点恢复缺失 | applySnapshot 只换文档不回落 focusBlockId/pendingCaret；编辑中撤销更直接换掉当前块视图对象致失焦（inferred） | proven（无接线）/ inferred（失焦形态） | EDT-14 |
| F-12 | Cmd+Z·三指手势未接模型栈 | 菜单副文案宣称「Cmd+Z / 三指左滑」，两入口均未接线；UITextView 自带 undoManager 若介入与模型栈双轨（文案与实现不符） | proven（无接线）/ inferred（双轨形态） | EDT-14/34 |
| F-13 | 链接表单取消/Esc 不回滚斜杠 token（C-F1） | applyInlineSlash 先剥 token 再开表单，取消即丢字；Web 提交时才剥、取消 token 还在 | proven | EDT-18 / 增补候选 |
| F-14 | Gallery 无删项/无排序（C-F2，待产品裁定） | 双侧同缺；已加错的图只能删整块重建；与 EDT-46 登记口径「增删/排序」不符——补实现（原生增强）或修订登记口径，二选一待裁 | proven | EDT-46 |
| F-15 | 视频无插入路径（C-F3，待产品裁定） | 双侧同缺；附件选视频只成 attachment 块而非 video 块，形态分叉 | proven | EDT-50 |
| F-16 | 窄屏拖拽 × 休眠 layout 锚落盘分叉 | 原生落盘从不按新序重写 layout 名单；窄屏跨休眠分界拖拽后宽屏重进，成员归属与 Web 一刀切口径静默分叉（「重进不跳栏」在带锚篇被窄屏拖过后不成立） | proven（机制）/ 跳栏形态 inferred | EDT-32 / 增补候选 |
| F-17 | 未知块类型呈现占位吞正文（B-10，与 audit2 旧登记同一缺陷未修） | 兜底行只显「{type} 块 · 后续轮支持」开发文案，不展示块内文本、无 Diag 打点；Web 为降级纯文本 + log_once（再保存保真本身达标） | proven | EDT-17 |
| F-18 | 编辑中切后台无 flush | scenePhase 只做启动哨兵，不调 saveNow/commitTitle；后台被系统回收即丢最后 <0.6s 编辑（A 片判形态级、D 片判功能级——本报告按数据丢失类取功能级，窗口窄这一事实已注记）；Web 有 pagehide/visibilitychange 保险丝 | proven（flush 缺失）/ 命中率 inferred | EDT-03 / 增补候选 |
| F-19 | 空文档打开无守卫 + 超长文档无性能护栏 | ① EditorModel.init 无空 doc 补空段（删块路径有、打开路径没有），空篇打开成无从落焦的死页；② 单列/双栏均 VStack 全量构建、每文本块一台 UITextView 全量实例化，无 Lazy/窗口化/降级，千块级首帧无上限保护（EDT-10 历史卡顿面同源） | proven（守卫/护栏缺失）/ 量级 inferred | 增补候选 / EDT-10 |

### 形态级（11）

| # | 项 | 差一句话 | 证据 | EDT |
|---|---|---|---|---|
| M-01 | 斜杠触发面宽于 Web | eligible 仅排除 codeBlock/callout，heading/quote 内仍可弹（audit2 §3.2 残项仍在） | proven | EDT-18 |
| M-02 | 粘贴成卡缺块型守卫（疑点） | handlePaste 无块型守卫，codeBlock 内粘贴 URL 疑走成卡判定；Web 代码块应留字面 | proven（守卫缺失）/ 触发面 inferred | EDT-41 |
| M-03 | 待办转换无尾随空段（B-6） | Web 转 todo 后补尾随空段，原生斜杠/菜单两路径均不补 | proven | EDT-16/19 |
| M-04 | callout 重转抹变体（B-8） | 原生斜杠重转 callout 恒重置 calloutType=note，warning 等变体被抹；块菜单路径又不设此字段（机制异、结果同） | proven | EDT-17 |
| M-05 | 转列表/引用类前不剥 MD 前缀（B-9） | 对已是 `- x` 源文本的段落转列表，Web 先 strip_md_prefixes 得干净项，原生得字面 `- x` 项文本 | proven | EDT-17 |
| M-06 | 代码块 Enter 语义分叉（待裁定） | 原生 codeBlock 内放行块内换行；Web 模型层为拆块口径——须回源定案后登记或对齐 | inferred | EDT-15 |
| M-07 | 斜杠命令标题/副标题未 i18n | 24 条命令 title/sub 为 zh-CN 字面量直写，非中文语言下恒中文；代码注释自称「已同源换键」与实际不符（注释与代码不符一并登记） | proven | 增补候选 |
| M-08 | 斜杠面板锚为块底非光标行底 | Web 桥以光标 rect 锚定；原生以触发块底近似，多行块内光标在中段时面板贴块底有偏移 | proven | EDT-36 |
| M-09 | flow 模式拖拽被无语义分界钳制 | flow 本不读锚，原生 commitDrag/dragShift 对 flow 同按 columnBoundaryIndex 钳制，拖拽活动半径被人为截断，且钳制基准与落定后分界不是同一数 | proven（机制）/ 手感 inferred | EDT-33 |
| M-10 | 取消路径拾起菜单残留 | onCancel 只清 draggingId/dragDy，不清 cardMenuBlockId/blockMenuBlockId，系统取消/行卸载后菜单可孤儿留存；Web 取消即收菜单 | proven | EDT-25 |
| M-11 | 图文卡图区进图片页（待主线确认） | 定案接入清单未列 imgTextCard/imageTextRow 图区，原生常态点图区即 openImagePage；Web 落 selectBlock。若非后续裁定即清单外多接一路（无数据风险） | proven（行为）/ 定性 inferred | 增补候选 |

### 微差（6）

| # | 项 | 差一句话 | EDT |
|---|---|---|---|
| m-01 | 标题 Esc 组字守卫缺失 | handleEscape 标题支无 markedTextRange 检查，硬件键盘组字中 Esc 可能直接还原草稿辞焦（可达面窄） | EDT-08 |
| m-02 | 待办重转 checked 两路径不一致（B-7） | 块菜单保留勾选、斜杠重置 false——随 F-03 单点化一并收敛 | EDT-16 |
| m-03 | 斜杠 URL 抑制口径差 | 大小写敏感、无剥前导括号/引号：`HTTP://…`、`（www.…` 形态原生仍弹面板，Web 不弹 | EDT-18 |
| m-04 | 斜杠图标全表 SF Symbols 近似 | 24 项图标由 Web 自绘名改 SF 近似（全表性形态差，非逐项缺陷） | EDT-19 |
| m-05 | 选图 sheet 在位时斜杠状态不清 | 系统 sheet 弹出时 slashBlockId 不清，关后斜杠面板仍在（Web 无对应面，影响轻微） | 增补候选 |
| m-06 | liftScaleFor 按行盒取 dim | 公式与 Web 等值，但 dim 取行盒而非视觉面、无抓握点补偿；image/gallery 等面内缩块型缩放偏小、拾起瞬间可轻微漂移 | EDT-27 |

### 疑点待定性（1）

- 前向 Delete 块尾合并：原生 shouldChangeTextIn 无前向删除支、块尾 Delete 无效果；Web 现行口径本轮未行级坐实，先回源 bridge.rs/editor.js 定性再决定是否补 mergeBlockForward（并入 EDT-15）。

---

## 修复分批建议

| 批 | 内容 | 归属 |
|---|---|---|
| E1 编辑回路根治 | F-01 组字 didChange 守卫（runs/save/斜杠推迟到 marked 清除后一拍）+ F-02 智能前缀移植 + F-08 原子前驱退格支 + M-01 斜杠守卫集对齐 + M-02 粘贴块型守卫 + m-01 标题 Esc 组字守卫 | U4a/U4b（与 EDT-13/15/18 景同验） |
| E2 撤销体系 | F-10 去重+600ms 爆发合并+上限 100 + F-11 选区/焦点恢复 + F-12 Cmd+Z/三指接线并禁块视图 undoManager 双轨（或改文案与实现一致） | U4b（EDT-14 undo_redo_roundtrip） |
| E3 转换语义单点化 | F-03 清字段单点（两路径共用 clearTypeFields 等价物）+ F-04 整表互换 + F-05 start 传递两处 + F-06 逐行拆项 + M-03/M-04/M-05 + m-02；F-07 先裁定再并入 | U4a/U4b（EDT-16/17 block_type_matrix 景） |
| E4 健壮性 | F-18 切后台 flush（经 EditorSeatRegistry 取在席编辑器 saveNow；标题草稿是否一并 commit 须主线裁，建议只 flush 正文）+ F-19① 空 doc 补空段守卫 + F-17 未知块降级呈现+Diag logOnce；F-19② 超长先量测（500/1000 块样本）再立窗口化专项 | 健壮性批（可随 U4b） |
| E5 拖拽/双栏 | F-16 窄屏落盘按 Web 口径以拖前分界数重写 layout 名单 + M-09 flow 不钳 + M-10 onCancel 清菜单 + m-06 liftScale 改吃面量测 | 随 U3 拖拽批 |
| E6 浮层/表单 | F-13 链接表单延迟剥离（优先，丢字类）+ M-08 斜杠锚改光标行 rect（BlockTextView 同通道回报）+ m-03 URL 抑制逐字移植 + m-05 sheet 前清 slash 状态；M-07 斜杠 i18n 换键随 I4 | C 批 / I4 |
| 待裁定（先裁后落） | F-07 落盘形态、F-14 Gallery 删/排序、F-15 视频插入、M-06 代码块 Enter、M-11 图文图区登记、疑点前向 Delete 定性、F-09 跨块选区独立立项评估、双栏右栏坐标系旁注核验（见 §6） | 主线/用户裁定 |

出包回归子集提示（§6.8 口径）：E1/E2/E3 落地版本应把 EDT-13/14/15/16/17/18 对应场景与组字面列入本版所动模块行。


---

## 域一 · 文本编辑回路 + 标题编辑全链（分片 A）

原生坐标：MomentApp.swift（下称 MA）、TitleTextField.swift（TTF）、TitleTapCaret.swift（TTC）。

| 项 | 规格出处 | 原生现状（机制） | 判读 | 证据 | EDT |
|---|---|---|---|---|---|
| 普通输入→模型→落盘 | Web editor.js:975-988（80ms 防抖 inputSync） | MA:3017-3042 didChange 同步直写 runs/text → onChange → scheduleSave，无中间防抖层 | 达标（同步直写等价更优） | proven | EDT-13 |
| 块内删除与 runs 同步 | Web processInput+inputSync | MA:2895 普通删除放行原生，didChange 全量重算 runs（含待办完成态显示样式扣除 3019-3024） | 达标 | proven | EDT-13 |
| Enter 分块 | Web ops.rs:325 op_split + H-10 定案 | MA:2925-2962 分流：codeBlock 块内换行、Shift+Enter 软换行、heading/callout 整块后插空段、空 todo/quote 转段落、余 splitBlock 同型延续 | 达标 | proven（机制）/ 落点 inferred | EDT-15 |
| Backspace 并块·文本前驱 | Web ops.rs:490 + B-3 | MA:6061 mergeBlockBackward：runs 拼接落接合处、空块跳原子块落最近文本块、prev 列表并末项 | 达标 | proven | EDT-15 |
| Backspace 并块·原子前驱 | Web B-2/B-3 定案处置 | 见 F-08 | 缺陷（功能级） | proven | EDT-15 |
| 智能前缀转换 | Web ops.rs:1271 apply_smart_prefix | 见 F-02 | 缺失（功能级） | proven | 增补候选 |
| 选区保持/程序化落焦 | Web bridge.rs focus_req/restore_focus | MA:2752-2796 消费 focusBlockId/pendingCaretOffset/focusCaretEnd；拆并后强制重载；新建认领有校验+≤3 次有界重试 | 达标 | proven / 投递 inferred | EDT-12/13 |
| 跨块选区 xsel | Web editor.js:739-790 | 见 F-09 | 缺失（功能级） | proven | 增补候选 |
| 跨块方向键 | Web crossBlockArrow（audit2 E1） | MA:2552 pressesBegan → 6385 handleKey（组字/选区守卫）→ 6437 crossBlockArrow（目标列会话+钳行尾） | 达标（E1 已修回潮核验在位） | proven / 硬件键盘 inferred | EDT-23 |
| 组字·结构操作拦截 | Web editor.js:62-68 总闸 + :774 keydown 守卫 | MA:2897-2899 markedTextRange 总闸；6424 方向键组字不消费；2802 组字期禁反写 | 达标 | proven / 实机 inferred | 增补候选（组字段） |
| 组字·didChange 守卫 | Web 组字期模型冻结 | 见 F-01 | 缺陷（功能级） | proven / 落盘 inferred | 增补候选（组字段） |
| 组字提交后终态 | Web compositionend 重放全管线 | MA:3019 提交瞬间全量重算 runs 同源无残留；标题侧 TTF:186-192 同口径 | 达标 | proven / 事件序 inferred | 增补候选（组字段） |
| 撤销·粒度与栈 | Web 600ms 合并/上限 100（diagnose_batch4_undo） | 见 F-10 | 缺陷（功能级） | proven | EDT-14 |
| 撤销·选区恢复与入口 | Web restore_focus + 三指/Cmd+Z | 见 F-11、F-12 | 缺陷（功能级） | proven / 双轨 inferred | EDT-14/34 |
| 撤销·菜单可用态 | 原版 E-4（置灰不停用） | MA:10638-10653 dimmed 仅置灰、动作仍执行、空栈 guard | 达标 | proven | EDT-34 |
| 复制面 | Web xsel 复制+块内原生 | 块内走 UITextView 原生；跨块随 F-09 缺失 | 达标（块内） | proven | 增补候选 |
| 粘贴纯文本/多行 | Web bridge paste 按换行拆段口径 | MA:2536-2549 paste 覆写分流 → insertLines（首行留本块、余行同型新块、heading 降段落、列表续项） | 达标 | proven | EDT-13/15 |
| 粘贴富文本 | Web ops.rs:1132 HTML 入模保 runs | paste 只读 image/string，富文本经 UITextView attributed 插入后 didChange 回收 runs | 达标 | proven / 来源保真 inferred | 增补候选 |
| 粘贴 URL 成卡 | Web ops.rs:1011 op_paste_card | MA:7449-7482 裸 URL/内嵌媒体 URL 成卡+余文成段、选区切分传 before/after；块型守卫缺失见 M-02 | 达标（主链）+形态级疑点 | proven / inferred | EDT-41 |
| 粘贴图片成块 E17 | Web 粘贴图片成块口径 | MA:2538 image 优先 → 5922 insertPastedImage（写失败不成块、插 image 块、尾随落焦齐） | 达标（E17 已实现非缺口） | proven | EDT-45 |
| 保存落盘时机 | Web visibilitychange/blur 提交 | 0.6s 防抖（5866-5875）+ closeEditor/onDisappear 双 saveNow；切后台冲刷缺失见 F-18 | 达标（主链）+缺陷 | proven / inferred | EDT-03 |
| 标题 commitTitle | Web title_controller.rs:606-618 + B-1 | MA:10228-10246 trim/空回退「无标题」/变化才压栈写回+刷新反链 | 达标（B-1 回潮核验在位） | proven | EDT-08 |
| 标题 Enter/Esc 会话 | Web title_controller.rs:868-886 + B-3 | Enter 结束会话走 didEndEditing 提交；titleBase 为会话起点快照；Esc 还原后辞焦、commit 幂等空转；Esc 浮层优先级链一次关一层 | 达标（B-3 回潮核验在位） | proven | EDT-08 |
| 标题两坞 + DockSession | fix_title_compact_freeze + Web scroll S7 | MA:9963-10053 锁存三写者封闭、dockCompact 单点派生、dockflip 面包屑带 src/计数 | 达标（0.9.55 回潮核验在位） | proven | EDT-06 |
| 标题截断落点 B-4 | Web title_controller.rs:228-278 | TTC 算式与 Web 同式；MA:10275 置焦前几何定格记号；TTF 施加后回读比对不符记 error | 达标（0.9.56 回潮核验在位；驱动断言仍缺口） | proven / 投递 inferred | EDT-07 |
| 标题字段常驻+二次编辑 | fix_title_capsule_reedit | TTF representable 只建一次、胶囊 ZStack 恒挂字段、截断态覆盖层点按置焦 | 达标（0.9.54 回潮核验在位） | proven | EDT-04/05 |
| 标题 sizeThatFits/占位色 | fix_title_vertical_render | TTF:202-218 宽随提议、高恒自量测、纵向提议不采；占位色 placeholderText；胶囊定义一处两坞同构 | 达标（0.9.56 回潮核验在位） | proven | EDT-04/06 |
| 标题字号 | 用户定案（Dynamic Type） | 标题恒 14 semibold 写死（TTF:110-125、MA:10306-10313），正文已随系统；代码自登记三处耦合 | 定案偏离（登记不翻案） | proven | 增补候选 |
| 标题 Esc 组字守卫 | Web title_controller.rs:868-871 | 见 m-01 | 缺陷（微差） | proven / 可达 inferred | EDT-08 |
| 完成胶囊 | impl_editor_done_capsule + 用户规格 | MA:10188-10226 doneExpanded 单点派生、抑制六格齐备、单容器 46↔92 顶锚定、finishEditing 单路辞焦 | 达标（定案规格在位） | proven | EDT-09 |
| 斜杠触发面 | Web hooks/slash + blockquote 守卫 | 见 M-01 | 缺陷（形态级） | proven | EDT-18 |
| 前向 Delete | 待回源 | 见疑点待定性 | 缺失（待定性） | inferred | 增补候选 |

---

## 域二 · 块操作与块类型转换矩阵（分片 B）

原生坐标：MomentApp.swift（下称 Swift）；Web 转换真源 editor/ops.rs（apply_type / clear_type_fields / op_convert / apply_smart_prefix）。

### 转换入口清单

| 入口 | Web | 原生 |
|---|---|---|
| 斜杠命令 | 22 项（render.rs:26-48）→ op_convert（ops.rs:1469） | 24 项（Swift:5006-5031）→ applySlash（:6988）；多 mathBlock/mathInline 两项 = 定案偏离（原生增强，0.9.46，不翻案） |
| 块菜单转换 | 无（Web 块级只有卡菜单编辑/删除 + 斜杠/智能前缀） | 拾起块菜单 7 项（正文/H1/H2/H3/待办/引用/提示，Swift:9394-9449）→ setBlockType（:5888）——原生自有入口（0.9.47 定案形态），转换语义仍按 Web apply_type 口径审 |
| 智能前缀 | apply_smart_prefix（ops.rs:1264-1341） | 全仓无实现（见 F-02） |
| 列表项转换 | op_convert Loc::Item 臂（ops.rs:1497-1565）：互换改父列表整表、余提出拆表、尾表 start 按首项号传递 | applySlash 先 promoteListItem（:6870-6926，拆表+尾表 start 同式 ✓）再按顶层 convert——互换语义分叉见 F-04 |

### 转换矩阵（源 × 目标 × 丢失字段；runs = 行内段全集）

| 源＼目标 | 正文 | 标题 H1–H3 | 待办 | 引用 | 提示 | 列表 | 代码块 | 分割线 | 公式 |
|---|---|---|---|---|---|---|---|---|---|
| 正文·Web 斜杠 | 自身 runs 保留 | runs 保留、level 设、checked 先清 | runs 保留、checked=false、尾随空段补插 | runs 保留、字段清 | **不产 callout 类型**：转 MD 源段落，runs 全丢、进源码态、尾随空段 | **不产列表类型**：转 MD 源段落逐行加前缀，runs 全丢、多行逐行成项 | **不产 codeBlock 类型**：转 MD 源段落（围栏加长、正文不剥前缀），runs 全丢 | 文本全丢+尾随空段 | 无此目标 |
| 正文·原生斜杠 | runs 保留 | runs 保留、level 设、**旧 attrs 不清（F-03）** | runs 保留、checked=false、**无尾随空段（M-03）** | runs 保留、旧 attrs 不清 | 产**真 callout 类型**+note，runs 保留（F-07） | 产**真列表类型**、整段塞**单个** item（F-06） | 产**真 codeBlock 类型**，runs 保留（F-07） | 文本全丢+尾随空段 ✓ 同 Web | 增强定案：mathBlock 置 `$$\n\n$$` 光标中置；mathInline $ 包裹/占位 |
| 正文·原生块菜单 | runs 全保留 | runs 保留、level 设、旧 attrs 不清 | runs 保留、checked **仅 nil 时**设 false（与斜杠重置口径不一致，m-02）；无尾随空段 | runs 保留、旧 attrs 不清 | 真 callout 但 **calloutType 不设**（恒默认 note 呈现） | —（菜单无此项） | — | — | — |
| 标题→其他 | Web：level 被清 ✓；原生两路径：**level 残留（F-03）** | 改 level ✓ | Web：level 清+checked=false；原生：level 残留 | 同左残留 | 同正文行 | 同正文行 | 同正文行 | 全丢同 | — |
| 待办（已勾）→其他 | Web：checked 清 ✓；原生：**checked=true 残留落盘（F-03）**（flushedNode 仅 todo 写 checked，残留来自两路径对 node 直接改写原样透传，Swift:218-260/5888/7036） | Web 清+设 level；原生残留+设 level | 自身重转：Web 恒重置 false；原生斜杠同、**块菜单保留 true（m-02）** | Web 清；原生残留 | 同残留 | 提出/成表时 checked 不入 item ✓ 两侧同 | 原生残留/Web 清 | 全丢同 | — |
| 引用→其他 | runs 保留、无专有字段问题 ✓ | ✓ | checked=false 新设 ✓ | 自身 | 同正文行 | 同正文行 | 同正文行 | 全丢同 | — |
| 提示→其他 | calloutType：Web clear_type_fields **只清 level/checked 不清 calloutType**，原生亦不清——**两侧同留、转回变体复活，同口径达标不报**（定案登记） | 同左 | 同左+checked=false | 同左 | 自身重转：原生斜杠恒重置 note（M-04）；Web 源码态无此问题 | 同正文行 | 同正文行 | 全丢同 | — |
| 列表项·Web 斜杠 | 提出成段、拆表、尾表 start ✓ | 提出+apply_type ✓ | 提出+checked=false ✓ | 提出 ✓ | 提出→MD 源（runs 丢） | **整表互换**：只改父表 type、清 start，项集/序/runs 全保留 | 提出→MD 源 | 提出→divider+尾随段 ✓ | 无 |
| 列表项·原生斜杠 | promote 提出、拆表、尾表 start ✓ 同 Web | 提出+convert（残留同 F-03） | 提出+checked=false ✓ | 提出 ✓ | 提出+真 callout（F-07 同源） | **拆表成单项新表、余项不变（F-04）** | 提出+真 codeBlock（F-07 同源） | 提出→divider+尾随段 ✓ | mathBlock 提出后置围栏段（增强口径内） |
| 整表（有序/无序） | 两侧均无整表直转段落路径 ✓ 同缺 | — | — | — | — | Web 经任一项斜杠整表互换 ✓；原生**无任何整表互换路径（F-04）** | — | — | — |
| codeBlock→其他 | Web is_text_block 含 codeBlock、保 inlines 转段落 ✓；原生 isText 含、两路径可转、children 保留 ✓ 等价 | ✓ | ✓+checked=false | ✓ | 原生真类型/Web MD 源（F-07 同源） | Web MD 源/原生真列表（F-06/F-07 同源） | 自身 | 全丢同 | — |
| MD 源段落→其他 | 两侧皆 paragraph+预览态，转换同正文行；Web 转列表/代码/callout 前 strip_md_prefixes，**原生无剥前缀（M-05）**；Web 转 codeBlock 例外不剥 ✓ | 同 | 同 | 同 | 同 | 同（M-05） | — | 全丢同 | 原生 mathBlock 恒覆盖围栏（增强定案内） |
| 原子卡→文本类 | 两侧均无转换路径 ✓ 同口径（Web 卡菜单仅编辑/删除；原生块菜单对非文本块仅「删除块」、卡菜单仅编辑/删除） | — | — | — | — | — | — | — | — |
| 未知类型→任意 | 入口面同（均无转换入口、仅可删除）；呈现面分叉见 F-17 | — | — | — | — | — | — | — | — |

### 域二其余逐项

| 项 | 判读 | 证据 | 要点 |
|---|---|---|---|
| 块新建/删除（菜单与模型层） | 达标 | proven | 删除走顶层 find 与状态清理齐备（详见域三菜单行）；拖拽移动归域四 |
| 待办勾选切换落盘 | 达标 | proven | 勾选钮 → toggleTodoChecked 具名入口（U4a 已抽）、落盘口径在位；转换进出 checked 存亡问题在 F-03/m-02 |
| 列表回车·续项/空项退出 | 达标（主链）+缺陷 | proven | insertLines/exitListItem 主链与 Web 同；start 传递两处缺失见 F-05 |
| 列表缩进 | 两侧同缺 | proven | Web 与原生均无列表缩进实现——同口径登记，不报缺陷 |
| 代码块编辑（语言面） | 两侧同无 | proven | 代码语言字段块型面两侧均无（Web 经 MD 源围栏语言、原生真块型无语言面）——与 F-07 裁定联动 |
| 代码块 Enter | 待裁定 | inferred | 见 M-06 |
| 公式块/行内公式 | 达标 | proven | 插入形态（$$ 三行光标中置、$ 包裹/占位）为定案；空公式块失焦呈字面 `$$` 为定案口径；渲染经 FFI render_mathml 在位、checksum 契约锁定（ffi lib.rs:328/563-566） |
| MD 块编辑↔预览保真 | 达标 | proven | MD 非独立块型（paragraph+预览态）；解析经 FFI md_classify/md_parse_json 调 core 同一解析器（ffi lib.rs:293/319），原文不漂移面见域四 MD 预览行 |
| 未知块模型层处置 | 达标（保真）/缺陷（呈现） | proven | 再保存字节级保真见域四；呈现见 F-17；转换入口两侧同无 |


---

## 域三 · 浮层与菜单 + 媒体插入与解析链（分片 C）

原生坐标：MomentApp.swift（下称 Swift）。

| 项 | 规格出处 | 原生现状（机制） | 判读 | 证据 | EDT |
|---|---|---|---|---|---|
| 斜杠触发-位置 | Web editor.js:1114-1140：光标前最后 `/`、query 无空白即触发（不限行首） | Swift:6620-6691 回扫取最后 `/` 为 tokenStart，eligible=文本类/list-item 排除 codeBlock/callout | 达标（与任务口径「行首/空格后」不同：Web 真源为任意位置 token，原生逐字等价，不按任务口径判缺陷） | proven | EDT-18 |
| 斜杠触发-URL 抑制 | Web editor.js:1128-1132（剥前导符号+大小写不敏感） | 见 m-03 | 缺陷（微差） | proven | EDT-18 |
| 斜杠触发-组字中 | Web 桥 input 组字期同样走检测、落模型侧另有守卫 | Swift:3039 updateSlash 调用点无 marked 守卫——与 F-01 同根（组字中间态可能以拼音 query 弹面板/闪烁） | 缺陷（随 F-01 收口；本片单列时判形态级） | inferred | EDT-18 |
| 斜杠过滤-拼音/关键词 | Web render.rs:775-800 | Swift:5092-5110 hay 与排序逐字移植、py 全集对表 | 达标 | proven | EDT-18 |
| 斜杠过滤-最近使用 | Web render.rs:82-110（上限 6、最新在前、空 query 置顶组） | Swift:5146-5165 UserDefaults 同口径（存储键原生自有、跨端数据分区，非缺陷） | 达标 | proven | EDT-18 |
| 斜杠键盘导航 | Web editor.js:335-360/777-810 | Swift:6261-6281 环绕/首尾、6389-6404 分发、面板 scrollTo 跟随、onHover 设选 | 达标 | proven（结构）/ 实键 inferred | EDT-18（实键归 EDT-23） |
| 斜杠面板呈现/锚定/限高 | Web render.rs:606-670 锚光标 | Swift:9472-9568 宽公式/上翻/限高逐项移植（J2-F17/F18），实测回写 slashPanelH；锚为块底见 M-08 | 达标 + 形态级 | proven | EDT-36 |
| 斜杠命令 i18n | Web render.rs:26-48 语言包键五语 | 见 M-07 | 缺陷（形态级） | proven | 增补候选 |
| 斜杠 24 命令执行 | Web 22 命令逐个对账 | 22 项 act/oid/ty/kw/py 逐项一致、执行落点与光标落点逐个核毕（convert/markRunRange/字面包裹/占位文案/尾随空段复用口径齐）；heading 图标等 SF 近似见 m-04；mathBlock/mathInline 两项定案增强 | 达标（22）+ 定案偏离（2） | proven | EDT-19 |
| 卡片菜单项集 | Web layers.rs:104-260 + CARD_MENU_TYPES 9 型 | Swift:5247-5255 9 型、editCardTypes 5 类逐字一致；9319-9353 编辑+删除 | 达标 | proven | EDT-30/39 |
| 卡片菜单打开方式 | Web 长按出贴卡浮层 | Swift:9262-9295 同度量同翻转；触发=拾起骑呈现（0.9.49 定案） | 定案偏离 + 达标 | proven | EDT-30 |
| 块菜单项集 | audit_editor_menu_uiux F4 定性（Web 文本块无长按转换菜单） | Swift:9364-9460 拾起浮层承接七项转换+删除；旧 .contextMenu 竞争面已删（verify[14] 锁）；无复制块/移动块——Web 同无，不判缺失 | 定案偏离（承接面） | proven | EDT-39 |
| 块/卡菜单动作完整性 | Web 删除走 find_loc+清状态 | Swift deleteBlock（5977）+ 菜单内同步清 cardEditBlockId；嵌套列表项内块无菜单入口——Web 同为顶层，登记不判 | 达标 | proven | EDT-39 |
| 长按文本选区菜单 | Web 浏览器原生、无定制 | Swift 无 UIEditMenuInteraction 定制、走系统 editMenu；长按=选区与拾起经 DragPressEngine 仲裁互斥 | 达标 | proven（无定制）/ 系统项集 inferred | 增补候选（实机抽样） |
| ••• 菜单六项 | 用户 2026-11-26 裁定 + Web MenuLayer | Swift:10614-10690 宽屏含双栏共六项、窄屏五项，无删除备忘、无分隔线 | 定案偏离（已按裁定落） | proven | EDT-34 |
| ••• 撤销/重做置灰 | Web layers.rs .dis 态（仅视觉） | Swift:10639-10653 dimmed 驱动、点击仍执行后关菜单 | 达标 | proven | EDT-34 |
| ••• 导出/背景入口 | Web 同浮层切 exportPanel / BgSheet | Swift:10663-10682 同面板切换三格式；背景先关菜单再开底表 | 达标 | proven | EDT-37/38 |
| ••• 面板高度 | Web css max-height 上限滚动 | Swift 实测回写 menuPanelH + 估高钳制 + ScrollView（横屏误差 ≤8 已注释登记） | 达标 | proven | EDT-35 |
| 链接表单-新建路 | Web render.rs:586-740 + dispatch.rs:420-429（提交时才剥 token） | 见 F-13 | 缺陷（功能级） | proven | EDT-18 / 增补候选 |
| 链接表单-校验规范化 | Web submit_slash_link | Swift:7187-7240 http(s) 前缀校验、错误行不关表单、无选区字面插入+括号转义、有选区 markRunRange | 达标 | proven | EDT-18 |
| 链接表单-编辑既有链接 | Web 无独立编辑表单 | 原生同样无入口——双侧同缺登记，不判原生缺陷；如需只能删后重建 | 达标（同缺登记） | proven | 增补候选（产品候选） |
| 链接表单-产物形态 | 口径澄清 | 斜杠 link 产物为行内链接非 link-card；成卡走粘贴链——任务口径「保存后成卡」与真源不符，已按真源判读 | 达标 | proven | EDT-41 |
| 图片-单选插入 | Web cardPick set | Swift:3336-3395 PHPicker 单选、真实名登记（suggestedName+UTType 补扩展）、占位块点按换图 | 达标 | proven / 选择器内人工 | EDT-44 |
| 图片-附件路 | Web ••• 添加附件 | Swift:9216-9225 图片/文件二选、图片单选成块——与 Web 附件面同为单文件口径 | 达标 | proven | EDT-44/48 |
| Gallery 增/换 | Web dispatch.rs:241-265（单张 set/add） | Swift:3397-3460 多选追加（超出 Web 单张，行为增强）；applyGalleryAdd/Replace 写前 putAttachment(name:) 守卫、失败跳过不落空引用 | 达标（含增强） | proven | EDT-46 |
| Gallery 删/排序 | EDT-46 登记口径含增删/排序 | 见 F-14（双侧同缺） | 缺失（功能级，待裁定） | proven | EDT-46 |
| 视频插入 | Web 无插入命令、仅存量呈现 | 见 F-15（双侧同缺）；呈现面 VideoBlockView/AVPlayerViewController 在位 | 缺失（功能级，待裁定） | proven | EDT-50 |
| 附件-导入+真名 | 0.9.36 定案（put 带名登记 manifest） | Swift:9223-9255 fileImporter、security-scoped 读、putAttachment(name: lastPathComponent) 失败不成块、name/size 落 attrs | 达标 | proven | EDT-48 |
| 附件-打开分流 | 定案（图片→图片页/文件→分享/非图不误入） | AttachmentRow 分流 + ShareSheet 结局 Diag 行 | 达标 | proven / 分享面 inferred | EDT-49 |
| 粘贴图片 E17 | measure_e17 口径 | Swift:2536-2548 paste image 优先；5925-5958 写失败不成块、尾随落焦口径齐（粘贴无真实名属口径内） | 达标 | proven | EDT-45 |
| 图文卡编辑底表 | audit2 E10 定案（保存提交制） | Swift:13248-13420 草稿快照、取消弃草稿/保存写回+scheduleSave，imgTextCard 与 imageTextRow 共用 | 达标（底表为系统全屏 sheet vs Web 底部 sheet，平台等价微差登记不计数） | proven | EDT-47 |
| 斜杠 image/gallery 成块 | Web blocks.rs 节点工厂 | Swift:7100-7130 同形态+尾随空段复用 | 达标 | proven | EDT-19 |
| 音乐-支持站点集 | Web ops.rs:1020-1028 MUSIC_HOSTS 6 | Swift:7279-7281 同 6 项逐字 | 达标 | proven | EDT-41 |
| 音乐-粘贴成卡全路 | Web ops.rs:1009+ op_paste_card | Swift:7367-7490 before 保留、卡插其后 loading、remain/after 成段；fetchLinkMeta（Worker /meta、10s 超时）+ startResolveCard（url 竞态守卫、title 非空 ready/否则 error） | 达标 | proven（状态机）/ 解析结果 inferred | EDT-41 |
| 音乐-胶囊状态机 | Web MusicInputPill 四态 | Swift:11414-11470 粘入即检 URL、回车提交转 loading、落点卡下文本块；卡面 input/loading/error/ready 四态呈现（12590-12940） | 达标 | proven / error 像素 inferred | EDT-42/43 |
| 音乐-手动输入 | Web layers.rs:177-205 prompt 路 | Swift:8063-8090 alert 输 URL 同口径（双侧均不校验合法性、失败成 error 卡，同口径不判） | 达标 | proven | EDT-42 |
| link-card 手动路径 | Web F3 定案（无编辑项） | Swift editCardTypes 不含 link-card、卡菜单仅删除 | 达标 | proven | EDT-39 |
| 天气-编辑页插入 | Web 斜杠/菜单/块集均无天气块 | 原生同样无天气块类型——任务口径此面在真源中不存在，不判缺失 | 达标（无此面） | proven | — |
| 天气-数据源口径 | audit_search_weather + weather.rs（和风主链→彩云兜底、缓存/TTL、城市反查） | Swift:14978-15270 WeatherService：构建注入 key+设置页自填、keySource 派生、双源链、缓存、城市表逐值移植；首页有数才渲染 | 达标 | proven（链路）/ 回数 inferred | SET-02 |
| 天气-失败回退 | Web 双源失败 UI 无痕仅 Diag | Swift 同口径（now=nil 不渲染、Diag WEATHER provider=fail） | 达标 | proven | SET-02 |
| 浮层-面板定高 | Web 上限滚动/限高随锚 | Swift menuPanelH/slashPanelH 双实测回写+首帧估高+钳制 | 达标 | proven | EDT-35/36 |
| 浮层-底表互斥 | Web sheets 单开序 | Swift 状态置位序齐备；选图 sheet 与斜杠面板同在见 m-05 | 达标 + 微差 | proven / 观感 inferred | 增补候选 |
| 浮层-完成胶囊抑制六格 | impl_editor_done_capsule 定案六格 | Swift:10109-10125 六格逐格接线与定案注释一致；斜杠/链接表单不抑制（同属编辑会话）与定案合 | 达标 | proven | EDT-09 |
| 浮层-Esc 优先级 | Web 面板 Esc 序 | Swift:10210-10240 链接表单>斜杠>背景底表>菜单/导出>标题还原；链接表单 Esc 与 F-13 同根随其修 | 达标 | proven | EDT-08 |

---

## 域四 · 拖拽 + 呈现与预览 + 双栏 + 健壮性 + 转场（分片 D）

原生坐标：MomentDrag.swift、MomentEditorTransition.swift、MomentApp.swift（下称 MA）。

| 项 | 规格出处 | 原生现状（机制） | 判读 | 证据 | EDT |
|---|---|---|---|---|---|
| 拾起仲裁参数 | Web editor.js:2803-2815（480ms + 位移 >10px 放弃） | MomentDrag.swift:136-137 minimumPressDuration=0.48、allowableMovement=10 | 达标 | proven | EDT-28 |
| 拾起全并行豁免 | 定案 round3（计时器不可被强制失败） | MomentDrag.swift:236-245 对全部识别器 simultaneous=true；拾起锁滚动、四路恢复 | 达标 | proven / 体感 inferred | EDT-28 |
| 编辑中块长按=选区 | 用户定案 + Web editor.js:2084 | MA:8708-8712 dragAllowed 排除编辑中文本块、引擎对 disarmed 行拒绝并 logOnce；拾起收敛选区（6319）；文本拖放交互关闭（0.9.49 定案） | 达标 | proven | EDT-28 |
| 可拖块全集 | Web pickup 无块型白名单；CARD_MENU_TYPES 9 型（editor.js:2427） | MA:8708-8712 全块型武装（编辑中文本块除外）；cardMenuTypes 9 型逐字等值（5247-5251）、拾起后按型分流两菜单 | 达标 | proven | EDT-24/30 |
| 兄弟让位 | Web dragMove/stepDrag（实测高+过半换位 FLIP） | MA:8620-8690 dragShift 与 commitDrag 同源算法（实测高+gap 6、栏内钳制）、让位动画 260ms 同曲线 | 达标 | proven | EDT-26 |
| 弹簧落定 | Web settleDrag 220ms spring | MA:8440-8468 spring(response 0.26, damping 0.82)、0.35s 清标记、reduceMotion 瞬时 | 达标 | inferred（曲线族差不可代码判读、体感归真机） | EDT-24 |
| 排序落盘 | Web ops.rs move_block | MA:7620-7670 commitDrag 实测高定落点→pushHistory→重排→scheduleSave（layout 锚问题见 F-16） | 达标 | proven | EDT-24 |
| 取消回滚（数据面） | Web dragCancel 不提交 | 重排只在 onDrop 发生、cancel 天然无数据变更；引擎四路清状态+恢复滚动、行卸载无条件复位 | 达标 | proven | EDT-25 |
| 取消菜单残留 | Web 取消即 cardMenuHide | 见 M-10 | 缺陷（形态级） | proven | EDT-25 |
| 拾起几何玻璃框 | 用户定案 + Web editor.js:2415-2426（⊕4 同心） | MA:13887-13900 LiftFrame（padding −4、Radius.lift=面+4）；面半径表与呈现分支同源；image/gallery 在子视图挂框 | 达标 | proven | EDT-27 |
| 拾起缩放 | Web liftScaleFor 按视觉面 + 抓握补偿 | 见 m-06 | 缺陷（微差） | proven（机制差）/ 量级 inferred | EDT-27 |
| 拾起白底回潮核验 | fix_drag_pickup_visual（0.9.50 根治） | MA:8685-8700 rowBackground 只按块型派生、与 draggingId 无关，无换底残留 | 达标（仍在位） | proven | EDT-27 |
| 跨栏拖拽钳制 | 定案：单列一步未做（登记） | MA:7651-7660 落点钳回来源栏、代码注释明示未做——现状与登记一致 | 定案偏离（登记在案） | proven | EDT-31/33 |
| 窄屏拖拽×休眠锚 | Web ops.rs:262-295 move 落盘按新序重写 layout | 见 F-16 | 缺陷（功能级） | proven / 形态 inferred | EDT-32 / 增补候选 |
| flow 拖拽钳制 | Web flow 不读不写 layout | 见 M-09 | 缺陷（形态级） | proven / 手感 inferred | EDT-33 |
| MD 失焦预览切换 | audit_md_preview 口径 | MA:8228-8234 判据（paragraph+未编辑+mdKind≠none）→ MdPreviewView；点按 beginMdEdit 落源码末尾；解析经 FFI 调 core、缓存按文本键 | 达标 | proven | EDT-20 |
| MD 渲染项 | core md.rs 全集（E5/E7 登记项） | MdBlockView 覆盖 Heading/Para/Code/Math/Quote/Callout/List/Table/Divider、MdSegsView 覆盖 Highlight 与行内 Math；对 core 新增 kind 无 default 支（静默空白）——现行产物全覆盖，仅未来扩展风险，登记备忘 | 达标（附登记） | proven | EDT-21/22 |
| 图片页入口全集 | 定案清单（接入 4 类/不接入 6 类） | imageTarget 置位恰 5 处与清单合（image 块/gallery 项/图片附件整幅/附件文件行分流/图文卡图区）；不接入面核对无误接 | 达标（图文图区单列 M-11） | proven | EDT-49 / 增补候选 |
| 图文卡图区入口 | 定案清单未列 / Web 落 selectBlock | 见 M-11 | 定案偏离（待确认） | proven / 定性 inferred | 增补候选 |
| 反向链接 | Web .wiki-backlinks 口径 | MA:11048-11095 呈现齐备；点按 replaceTopEditor 无动画换篇；双栏只挂文档末栏 | 达标 | proven | EDT-51 |
| 编辑页头像 | 红线（有实际功能不得误伤） | MA:10326 头像钮 → 更换/恢复默认 dialog → PHPicker 转 data URL 走 avatars 通道 | 达标 | proven | EDT-52 |
| 天气块呈现（编辑页） | 任务清单项 | 两版编辑页均无 weather 块型（天气块是首页列表面） | 达标（无此面） | proven | — |
| 引用/提示/高亮呈现 | Web blocks 段 | quote 淡底+左条+文内缩单点；callout 五档变体钳制；高亮编辑面与 MD 预览同源 fill | 达标 | proven | EDT-17/21 |
| 双栏分界函数 | Web columns.rs:15-105 | MA:5617-5671 逐项移植逐值一致（估高表/canonical/normalize/有效分界序） | 达标 | proven | EDT-31/33 |
| 独立模式五项 | 定案 audit_independent_columns | wideColumns 两栏独立 ScrollView/混排/栏内排序/锚定成员；排序栏内钳制 | 达标 | proven（结构）/ 体感 inferred | EDT-32 |
| 重进不跳栏 | 定案（锚定成员） | layout 落盘+init 决议+一次性落锚闩；例外 = F-16 窄屏拖拽面 | 达标（例外单列） | proven | EDT-31/32 |
| 落锚+开关重写锚 | Web hooks/columns.rs + layers.rs:388-430 | captureAnchorIfNeeded 与 toggleTwoPane 逐项对应（翻转/写默认/按当前分界重写名单/切 flow 也写锚）；mode 决议序与 Web 一致（G-2 定案在内） | 达标 | proven | EDT-31 |
| 宽屏判定 | Web (≥768 且 ≥600) 或 ≥1100 | MA:11143-11147 syncWide 同式 | 达标 | proven | EDT-31 |
| 右栏坐标系（旁注） | 面板锚定按栏坐标换算 | independent 左栏 ScrollView 挂 coordinateSpace("editorScroll")、右栏未挂同名系——右栏块 frameMinY 解析空间是否同系代码静态不可判；若不同系，右栏斜杠/块菜单锚定可错位 | 未判（风险登记） | inferred | EDT-39（旁及） |
| 空文档打开 | Web 空 doc 有落焦/插段路径 | 见 F-19① | 缺失（功能级） | proven / 可达 inferred | 增补候选 |
| 超长文档护栏 | 不劣于 Web 可用性底线（EDT-10 历史面） | 见 F-19② | 缺失（功能级） | proven / 量级 inferred | EDT-10 / 增补候选 |
| 未知块呈现 | Web audit2 定案（降级文本+log_once） | 见 F-17（与 B 片 B-10 同一缺陷合并登记） | 缺陷（功能级） | proven | EDT-17 |
| 未知块再保存保真 | 规格：保存不得改写未知块 | flushedNode 对非文本非列表块返回 node 原样、整篇落盘全块走此路——字节级保真含未知字段 | 达标 | proven | EDT-17 |
| 切后台保存 | Web pagehide/visibilitychange 保险丝 | 见 F-18（与 A 片同项合并、取功能级） | 缺陷（功能级） | proven / 命中 inferred | EDT-03 / 增补候选 |
| 在席冲突守卫 | impl_uitest_u0/u1 定案（在席即拒 memo_busy） | MomentBridgeTools seatedConflict（1169-1187）+ 三消费点（softDelete 1523/deleteBlock 1724/moveBlock 1793）均写前守卫；恢复/永删无守卫与定案注记一致；座位登记带令牌、关联替换不误清 | 达标 | proven | BRG-08 |
| 滚动健康现状 | audit_scroll_report（两代观测链作废史） | 第三代观测链（1pt 探针+直读、双守卫、SCROLL 三类行齐备）代码面已收敛；EDT-10 场景未落、体感未终判 | 缺失（验证面，非代码缺陷） | proven / 体感 inferred | EDT-10 |
| TRANSITION 判据 | 定案（claim>anim、kb>claim） | logTransition 四时点同基准；新建路判据由认领门控构造保证恒成立；open/link 两路 claim/kb 恒记 na（无认领属如实登记非缺陷） | 达标（新建路）/ 覆盖面登记 | proven | EDT-01 |
| 三路转场时序 | 定案 round2 + 0.9.50（首帧窗外构建、单动画） | pushEditor 预构建+completion 单点收口；replaceTopEditor 无动画换栈顶；返回确定性 pop、交互取消不误收口；imageTarget 由宿主订阅接管 | 达标 | proven / 体感 inferred | EDT-01/03 |


---

## 待裁定 / 风险登记（不计缺陷，须主线或用户裁后才动）

1. **F-07 斜杠转代码块/提示的落盘形态**：Web 口径 = MD 源段落（牺牲 runs 与真块型，换源码可编辑性）；原生 = 真块型（保 runs、无语言面/变体经源码编辑）。按「行为等价且更优可改判」口径，原生形态有保留价值，但与 Web 数据形态分叉会影响双端互通文档的呈现一致性——裁定前 E3 批不碰此二目标。
2. **F-14 Gallery 删/排序**：补原生增强（编辑态删瓦+拖拽排序）或修订 EDT-46 登记口径为「增/换」，二选一。
3. **F-15 视频插入**：附件路按 UTType.movie 分流成 video 块，或登记「视频仅存量呈现」口径。
4. **M-06 代码块 Enter**：回源 Web 模型层口径定案（块内换行 vs 拆块）后登记或对齐。
5. **M-11 图文卡图区图片页**：确认属有意增强则补登记进 audit_detail_image_page 接入清单；否则图区点按改回选中块。
6. **F-09 跨块选区**：结构性课题（单 UITextView 多块化或选区桥接层），单独立项评估成本后再定做与不做；此前在矩阵登记为已知缺失，防误判已覆盖。
7. **右栏坐标系旁注**（域四）：independent 右栏 ScrollView 未挂同名 coordinateSpace，右栏块的斜杠/块菜单锚定（frameMinY 口径）有错位风险、代码静态不可判——交真机探针（右栏块开菜单量 panelTop）或菜单分片核验，不在本审判读。
8. **F-18 标题草稿连带**：切后台 flush 若一并 commit 标题草稿，与「手势返回才 commit」的现口径分叉；建议只 flush 正文、标题维持现口径并登记，待主线确认。

## 定案偏离汇总（登记在案、不翻案）

1. 标题字号恒 14 semibold 不随 Dynamic Type（代码自登记三处耦合：字段字体/胶囊量测/titlePrefixWidths 同改才可动）。
2. 标题截断计数基从 Web chars() 标量口径（audit_title_input B-6 三端差登记）。
3. 斜杠 mathBlock/mathInline 两项为原生增强（0.9.46）；空公式块失焦呈字面 `$$` 为定案口径。
4. 块菜单转换七项为原生自有入口（0.9.47 拾起浮层承接；Web 无此面，其转换语义仍按 Web 口径审——本报告 F-03 等即按此判）。
5. 卡片菜单骑拾起呈现（0.9.49 用户纠正口径）；••• 菜单六项口径（2026-11-26 裁定，无删除备忘/无分隔线）。
6. callout 转出后 calloutType 两侧同留（Web clear_type_fields 亦不清）——同口径，不报。
7. 删空文档补空段为原生守卫（更优向）；列表缩进、代码语言字段（块型面）两侧同缺——同口径登记。
8. 宽屏跨栏拖拽单列一步未做（audit_independent_columns 登记，现状与登记一致）；流式不跨栏、独立双栏五项、G-2 mode 默认翻转均按既定案。
9. 完成胶囊单容器变形规格（用户 2026-11-27 定案）；DockSession 会话锁存（0.9.55 根治形态）。
10. 斜杠最近使用存储键为原生自有（跨端数据分区，非缺陷）；图文编辑底表系统全屏 sheet 形态（平台等价）。

## EDT 映射与矩阵增补候选

已映射（缺陷→既有行）：F-03/F-04/F-05/F-06/F-17→EDT-17（F-03 兼 EDT-16）、F-08→EDT-15、F-10/F-11→EDT-14、F-12→EDT-14/34、F-13→EDT-18、F-14→EDT-46、F-15→EDT-50、F-16→EDT-32、F-18→EDT-03、F-19②→EDT-10、M-01/M-03→EDT-18/16、M-02→EDT-41、M-04/M-05→EDT-17、M-06→EDT-15、M-08→EDT-36、M-09→EDT-33、M-10→EDT-25、m-01→EDT-08、m-02→EDT-16、m-03→EDT-18、m-04→EDT-19、m-06→EDT-27。

矩阵增补候选（plan_selftest_coverage.md 未覆盖的新面，建议主线并入矩阵时编号）：
1. 跨块选区/跨块复制（结构缺失登记行，防误判已覆盖）。
2. 智能前缀转换（现挂 EDT-15 相邻未单列；建议单列或并入 EDT-15 景断言集）。
3. 组字面成组行：组字期 didChange 守卫（F-01）+ 组字结构拦截 + 提交后终态——并入 EDT-13 景的组字段，或单列 EDT 增补行（拼音为生死线，建议单列）。
4. 前向 Delete 块尾合并（定性后并入 EDT-15）。
5. link_form_cancel_rollback 场景（F-13：取消/Esc 后 token 原样+回焦断言）。
6. 斜杠命令 i18n 五语呈现行（M-07，随 I4/I5 验收面）。
7. 长按选区菜单实机抽样（人工面，与 EDT-28 同族登记）。
8. 图片页入口全集断言（域四 5 置位点对清单，建议并入 EDT-49 行扩围）。
9. 窄屏拖拽 × 休眠 layout 锚（F-16，建议并入 EDT-32 行扩围：窄屏拖后宽屏重进成员归属断言）。
10. 长文档样本量测行（F-19②：500/1000 块打开耗时与滚动帧基线，EDT-10 相邻）。
11. 切后台 flush 行（F-18，建议并入 EDT-03 close_roundtrip 扩展后台段）。
12. 空文档打开守卫行（F-19①：空 doc 篇打开可落焦断言）。
13. 链接编辑入口（产品候选行：双侧同缺，裁定后决定是否立行）。
14. 标题字号 Dynamic Type 耦合登记行（定案偏离的矩阵留痕）。

## 方法与边界注记

- 本审为代码级审计：全部 proven 结论指到文件:行机制；涉手势仲裁（EDT-28）、组字实机、光标投递、系统选择器内操作、外部站解析、动画体感、滚动体感者一律封顶 inferred 并已逐项标注，终判归真机/人工。
- 任务清单中与真源不符的口径已按真源判读并逐项注记：斜杠触发位置（Web 为任意位置 token 非行首）、链接表单产物（行内链接非成卡）、编辑页天气块插入/呈现（两版均无此面）、Gallery 删/排序与视频插入（双侧同缺、按待裁定登记而非单边缺陷）。
- 呈现数值差（块间距/圆角/字号梯等）已由 audit_detail_editor_blocks.md 等线 1 报告全量登记，本审不重复计数；本审新增面为功能/交互逻辑/数据保真三类。
- 分片原文存档：审计工作底稿四片（A/B/C/D）已并入本报告各域表格，分级口径冲突处（切后台 flush、斜杠组字守卫、未知块呈现）已在汇总层去重并注明取舍。

> **矩阵并入（2026-11-27）**：本报告候选行已并入 docs/reports/plan_selftest_coverage.md（新行与状态更新逐份对账见该文件 §4.12），后续覆盖状态以矩阵为准。
