# Web 兼容原生真块型 — 设计报告（只设计，未落码）

- 时点：2026-11-27。基线：0.9.57 组版提交落定后的工作树（组版后 HEAD）。
- 裁定（用户 2026-11-27）：斜杠转代码块/提示/列表的落盘形态**以原生真块型为正**（真 `codeBlock` / `callout` / `bulleted-list`·`numbered-list` 类型、保 runs），Web 侧另外做兼容。本报告即 Web 侧兼容的设计：差距实证 → 修法 → 验收口径 → 排批。
- 依据：`docs/reports/audit_editor_deep.md` 域二转换矩阵（分片 B）；本报告所有现状判断均回 Web/core 源码行级复核，与审计矩阵冲突处以本报告实证为准并注明。
- 口径对齐：文档格式已经用户 2026-11-24 放松（现存笔记以展示为主，可按最优重构 + 迁移；兼容层彻底去除；D1 备份转 Rust 原生格式 / D2 旧格式只走一次性迁移通道 / D3 存量归一）。本设计与该口径同向：真块型为正形，MD 源段落退为「手打 MD 文本的预览表示」与存量旧形，不再是转换产出。

---

## 0. 先说清的事实：三类块的形态双端本就同源

原生斜杠转换产出的节点形态（`rust/apps/ios/app/MomentApp.swift` `applySlash` 内 `convert()`，:7196-7268；落盘 `flushedNode()`，:218-262）：

| 类 | 原生产出 | 字段 |
|---|---|---|
| 代码块 | `{type:"codeBlock", children: runs}` | runs 原样保留（含行内标记）；无 language 字段（双端同无，审计域二登记） |
| 提示 | `{type:"callout", calloutType:"note", children: runs}` | `calloutType` 在**节点顶层**；变体恒 note（转换时设定） |
| 列表 | `{type:"bulleted-list"\|"numbered-list", children:[{type:"list-item", children: runs}]}` | 转换产出为**单项**列表（审计 F-06）；列表节点 attrs（如 start）落盘时随原节点透传（`flushedNode` :221-225 只换 children）；list-item 的 children = 行内 runs + 可选嵌套列表节点（:226-247） |

Web/core 侧的类型名与字段位与此**逐字一致**：core 类型化模型 `crates/core/src/model.rs` 的 `Node` 对任意 type 字符串通用承载，三类块用到的字段全部已类型化——`callout_type`（顶层，:170）、`attrs.start`（:143）、`attrs.level/checked`（:137-139）、children 递归。迁移通道 `crates/core/src/migrate.rs` 甚至留着这条谱系：旧名 `code` → `codeBlock` 改名（:26、:771）、callout 变体旧名 `kind`/`variant` → 顶层 `calloutType` 归一（:794、:901-913）——真块型本就是格式正统，MD 源段落只是 Web 转换层的一条产出路线。

**推论**：本任务不是「Web 学一种新格式」，而是「Web 的转换产出与少数消费面从源段落路线切回真型路线」。差距面比预想小得多，逐项实证如下。

---

## 1. 差距实证：含真块型的文档今天在 Web 的全链路

设样本：一篇由原生创建/编辑过的文档，含真 codeBlock（多行、带行内标记的 runs）、真 callout（note 及其他变体）、真 bulleted/numbered-list（含 start、嵌套子列表）。逐面判读（✅ 已兼容 / ⚠️ 部分 / ❌ 会坏）：

### 1.1 加载与解析 ✅

- Web 全部加载路径先经迁移通道归一、再过类型化模型校验：存量加载 `apps/web/src/persist.rs:1075`（`normalize_stock_value`）+ `BackupFile` 校验（:1081）；主线加载 `apps/web/src/main.rs:1043-1073` 同口径；ZIP 导入走 storage 的 `read_backup_zip_migrated`（`crates/storage/src/lib.rs:216、:231`）。
- 三类块的全部原生字段都在类型化模型内（§0），解析不丢字段、不报错。迁移通道只改旧名（`code`→`codeBlock` 等），对现行真型节点无动作。

### 1.2 只读呈现（首页列表/详情渲染）✅

共享渲染器 `apps/web/src/blocks.rs` `BlockView` 三臂齐备：

- callout（:869-890）：变体取顶层 `calloutType`（`callout_variant` :477），五变体标题/图标与 MD Callout 共用单点 `icons::callout_icon_markup`。
- codeBlock（:891-894）：`pre.blk-code` + `plain_text()`——行内标记不可见（代码语义如此），文本全量呈现。
- 列表（:895-908）：标记列 + `attrs.start` 起始号（`list_start` :222-226），嵌套项经 `kids_of` 递归。

### 1.3 编辑器呈现 ✅

`apps/web/src/editor/render.rs` 块分发三臂齐备且均为可编辑形态：

- callout（:354-386）：头部（图标+变体标题）+ `EditableDiv` 正文（class `callout-body`）。
- codeBlock（:388-390）：`EditableDiv`（class `blk-code`）。
- 列表（:430 起）：`list-wrap` 逐项 `EditableDiv`，有序起始号取 `list_start`。
- 未列名类型走默认臂（:491-506）退化为只读 `BlockView` 包裹——三类块不命中此臂。
- **MD 预览态判定零干扰**：预览门控只存在于 `"paragraph"` 臂内（:283-340，父级预判 `para_md` 与编辑态/聚焦态三路分流，:245、:287-289）。真块型永不进 `md_classify` 路由；反之 core `md.rs` 从段落文本解析围栏/Callout 头/列表的预览宇宙是另一套平行表示，与真块型互不串扰。

### 1.4 编辑器基础编辑 ✅（主链全通）

- 文本块集合 `is_text_block`（`apps/web/src/editor/model.rs:101-106`）含 `callout | codeBlock | list-item`——落焦、光标、同步 machinery 按文本块对待。
- codeBlock 键盘语义在 JS 桥层定型（`apps/web/src/editor/js/editor.js`）：回车 = 块内换行放行原生、永不发 split（:890-904）；段首退格发 merge（同段）；打字走 inputSync 防抖落模型、斜杠检测在 codeBlock 内抑制（:1108）；多行粘贴不拆块（:1803-1814）。——顺带关闭审计 M-06 的定性悬案：**Web 代码块回车与原生同为块内换行**，`op_split` 通用臂的 paragraph 落点（`ops.rs:425-430`）对 codeBlock 不可达（桥层先行拦截），不是分叉。
- callout 回车 = 整块保留、其后插空段（`ops.rs:383-395`，与 heading 同臂），正文不拆分。
- 列表项主链（拆项/空项退出/合并/start 按首项号传递）在 `editor/model.rs`（:501-629 诸 helper）与 `ops.rs` 的 `Loc::Item` machinery 全量实现，与原生口径逐项对齐（审计域二已核）。

### 1.5 编辑后落盘保真 ✅（附一条守则）

- 编辑器落盘从类型化 `Node` 信号序列化；三类块的原生字段全在模型内（§0），Web 打开 → 编辑他块 → 保存，三类块逐字段无损。
- 一般性守则（非现行缺陷）：§2.2 起未知键不往返（`model.rs` 头注）。若将来原生给这三类块加未建模字段，Web 编辑保存会静默吞掉。防线不是改模型，而是契约测试钉死（§3 验收 1/2 + §2 G5）。
- 原生转换残留 attrs（如 heading→codeBlock 后 `attrs.level` 残留，审计 F-03）在 Web 侧被类型化承载、渲染忽略、原样往返——无害，不在本设计处理面（归 E3 原生侧收敛）。

### 1.6 从真块型出发的转换 ⚠️（一处静默错误）

`op_convert`（`apps/web/src/editor/ops.rs:1469` 起）：

- 顶层块转 paragraph/heading/todo/quote 等：走 `apply_type`（:1341-1399，先清 level/checked 后设型，children 由编辑器 HTML 回收的 inlines 替换）——真 codeBlock/callout 转出正常 ✅。
- 顶层块转 MD 四类（bulletList/numberList/codeBlock/callout）：进源段落臂（§1.7）——形态被改写回源段落，与裁定相悖 ❌（即 G1）。
- **列表项转 codeBlock/callout：静默变普通段落** ❌（即 G2）。`Loc::Item` 臂（:1483-1565）对非互换 act 一律走 `apply_type`，而 `apply_type` 无 codeBlock/callout 臂、落默认臂成 paragraph——转换意图无声丢失，连源段落都不是。原生同路径是「提出该项 → 转真型」。这是现行代码里唯一一处行为错误级缺口（与裁定无关、本就该修）。
- 列表互换（有序↔无序经任一项斜杠）：✅ 已实现且 start 清除口径在位（:1487-1505）。

### 1.7 Web 自身转换产出 ❌（本设计的主战场）

`op_convert` 顶层 MD 臂（`ops.rs:1567-1644`，注释自述「原版模型是 md 源段落，不造 codeBlock/bulleted-list/callout 类型」）：

- 四类产出统一为 paragraph + **单个纯文本子节点**（`text_node(&src)`，:1631）——源块的行内标记（runs）在转换瞬间全丢；转后强制进源码编辑态（`md_edit.set`，:1642）。
- 列表源形逐行加前缀（多行逐行成「行」，:1585-1600）；代码源形围栏按正文最长反引号串加长（:1603-1625）；Callout 源形 `> [!NOTE]` + 逐行 `> `（:1627-1635），且 callout 在尾随空段清单内（:1636-1639）。
- 智能前缀（`apply_smart_prefix`，:1271-1340）：`PrefixHit` 只有 Divider/Heading/Quote/Todo——Web 打字打 ``` / `- ` / `> [!` 不经转换，靠段落 MD 预览呈现。这是「源段落宇宙」的输入侧，与转换产出同源。

### 1.8 导出 ⚠️（MD 两臂缺失）

- HTML 导出（`apps/web/src/editor/export.rs`）：callout 臂在位（:866-874，与原版 export.js 同组走 note-markdown 臂、正文内嵌、不出变体头——原版口径，保留）；codeBlock 臂在位（:1014-1016，`<pre>` 转义全文）；列表臂在位（:1030-1049，`<ol start>` 口径同原版）。已有测试直接以真 callout 节点喂 HTML 导出（:1576-1605）✅。
- MD 导出（`block_md_str`，:1148 起）：列表有专臂（`list_md` :1404，start/嵌套/行内标记折回全量实现，测试 :1639 起多例）✅；**codeBlock 与 callout 无臂、落默认臂 `_ => text`（:1256-1259）** ❌（即 G3）：
  - 真 codeBlock 导出 = 无围栏原文——多行代码摊成普通文本段，MD 语义丢失（再被任何 MD 读者打开即散架）。
  - 真 callout 导出 = 无 `> [!VARIANT]` 头的正文——变体与提示语义丢失。
  - 同一默认臂对 MD 源段落输出原文是**正确**的（源即 MD）——该臂把两种表示混为一谈，是缺口的准确形态。

### 1.9 搜索/索引与杂项 ✅

- storage 以 `Memo::plain_text()` 建索引（`crates/storage/src/lib.rs:297-300`；递归拼接 children，`model.rs:224-233`）——三类块正文全量可搜。
- callout 变体可编辑性：**双端同缺**——Web 全仓无 `callout_type` 写点（仅读：render.rs:356、blocks.rs:479），原生亦只在转换时写 note。本设计不顺手造变体切换 UI（产品面，另行立项）；G1 产出恒 note 与双端现行一致。

### 1.10 实证结论表

| 面 | 判读 | 缺口编号 |
|---|---|---|
| 加载解析 / 只读呈现 / 编辑器呈现 / MD 预览判定 / 基础编辑 / 落盘保真 / 搜索 | ✅ 已兼容 | — |
| 列表项斜杠转 codeBlock/callout | ❌ 静默变段落 | G2 |
| Web 斜杠转换产出（三类 + 列表） | ❌ 仍产 MD 源段落、丢 runs | G1 |
| MD 导出 codeBlock/callout | ❌ 落兜底臂丢语义 | G3 |
| 智能前缀产出 | ⚠️ 无三类命中（源段落宇宙输入侧） | G4（分期） |
| 往返契约守卫 | ⚠️ 无钉死测试 | G5 |

---

## 2. 兼容设计

总原则一句话：**形态换真型，语义沿 Web 现行转换规则**。Web 转换层多年沉淀的语义（剥 MD 前缀、逐行拆项、围栏加长、尾随空段、落点口径）全部保留，只把产出表示从源段落换成真块型、把 runs 从「压平丢弃」换成「保真传递」；原生 E3 批（转换语义单点化）从另一侧向同一张语义表收敛。两侧各自落码、共用一张表（即审计域二矩阵经本裁定修正后的形态）。

### G1 斜杠转换产出改真型（ops.rs MD 臂改造）

改造点：`op_convert` 顶层臂（`ops.rs:1567-1644`）整臂替换为真型产出，四个 act 分别：

- **codeBlock**：`node_type = codeBlock`，children = 现行 `inlines`（编辑器 HTML 回收，含标记）原样保留——与原生产出逐字段同形。清字段走 `clear_type_fields` 同口径（level/checked）。不进 `md_edit` 源码态；落点 = 令牌起点（沿 D-11 口径换算到真型块：块首偏移即 tok_pos 钳制）。围栏加长规则（:1612-1620）从产出路径退役，但**保留为 G3 导出的单点规则**（见 G3，不删、迁移）。
- **callout**：`node_type = callout`，`callout_type = "note"`（顶层字段直写 Node.callout_type），children = inlines 保留；尾随空段规则保留现行（:1636-1639，callout 在尾随清单内——此为 Web 语义、E3 侧原生随后对齐，见 §4 耦合）。剥前缀保留（`strip_md_prefixes` 先行，与现行同序）。
- **bulletList / numberList**：产出**一个**真列表块，children 为逐行 list-item——逐行口径沿现行源形臂的 per-line 语义（:1585-1600），**不抄原生的整段塞单项**（审计 F-06 是原生缺陷、E3 修；Web 侧一步到位）。行内标记按行切分：inlines 是平坦 run 列、文本内含 `\n`——需一个切分 helper（遍历 runs、按 `\n` 切文本节点、标记随段走），这是 G1 唯一的真工程点；helper 须带单测（含跨行标记、行首尾空行、空正文占位文案沿现行「列表项」口径）。numberList 不写 start（默认 1，与现行源形及原生一致）。
- 转换**源**侧不变：源块是 MD 源段落时，先剥前缀再产出（现行 `strip_md_prefixes` 调用点保留）；源块是真块型时 inlines 即其 children 回收，天然保真。

JS 桥连带：转换后块的 `data-btype` 由渲染层按新 type 输出（codeBlock 臂已有 btype 语义，editor.js 的 isSrcBlock/回车/斜杠抑制全按 btype 工作，无需新协议）；`md_edit.set(Some(bid))`（:1642）对四类不再触发——dispatch 侧确认无其他消费方依赖该置位做转换后处理（落码时 grep 全量核）。

### G2 列表项转 codeBlock/callout 接回真型路径

`Loc::Item` 臂（`ops.rs:1539-1545` 的 `apply_type` 调用点）：act ∈ {codeBlock, callout} 时，先按现行提出结构（head/tail 拆表 + start 传递，:1507-1563 既有骨架）把该项提出为顶层块，再走 G1 的同一产出函数。实现纪律：G1 产出抽为共用函数（暂名 `apply_true_block_form(n, act, inlines)`），顶层臂与 Item 臂同调一处——不在 Item 臂复制一份（开发规范：拒绝堆积、单点收敛）。列表互换臂（:1487-1505）不动。

### G3 MD 导出补两臂（export.rs）

`block_md_str` 在默认臂之前加：

- `"codeBlock"`：围栏形——围栏长度 = 正文最长连续反引号串 + 1、下限 3（规则与现行 `ops.rs:1612-1620` 同式；G1 落码时把该规则抽到 core 或 export 可达的单点，两处同调，不留双份实现）。
- `"callout"`：`> [!{VARIANT}]\n` + 正文逐行 `> ` 前缀；VARIANT = `callout_type` 大写、缺失/未知值落 NOTE（与 `callout_variant` 的归一口径同源）。
- 默认臂注释同步修订：只剩「paragraph（含存 MD 源码段）原样」一义。
- 测试：`export.rs` 既有测试区追加两臂用例（真 codeBlock 含反引号正文、真 callout 五变体各一），与列表臂测试同置。

### G4 智能前缀（分期，本期不做，登记口径）

两案：

- 案甲（本期并入）：`smart_prefix_match` 增 ``` 围栏与 `> [!` 命中、产真型。代价：Web 手打 MD 的输入体验从「源码段落 + 预览」变「即时成真块」，与原版 Web 多年手感分叉；且围栏输入是流式逐键过程，命中时机（闭合围栏出现时？）需另行设计，误转风险实有。
- 案乙（推荐）：本期不动智能前缀。手打 MD 仍成源段落——它与真块型**共存无损**（呈现等价、往返保真，§1.3/1.5 已证），只是同篇内两种表示并存。待 G1-G3 落地、真型成唯一转换产出后，再单独评估输入侧是否收敛（届时源段落只剩「手打 MD」一个来源，收敛面更清楚）。

推荐案乙。理由：裁定的对象是「落盘形态以真型为正」，G1 已使全部**命令式转换**产真型；输入侧是手感面、非数据面，按根治不扩围的口径分期。

### G5 往返契约守卫（core + web 测试）

- core 层：新增往返夹具测试——含三类真块的文档 JSON（变体五枚、start=3、嵌套子列表、带标记 runs、多行代码含反引号）经 `Memo` 类型化解析 → 序列化，断言逐块深等（防 §1.5 的未知字段吞噬在未来字段扩展时无声发生；新字段若故意不建模，测试红即提醒补建模）。
- web 层：`ops.rs`/`export.rs` 既有测试区加 G1/G2/G3 用例（上文各处已注）；另加一条「编辑无关块后三类块不变」的模型级用例（构造 doc → 改一篇中段落 → 全 doc 序列化比对三类块子树）。
- 静态锁：仓库 verify 脚本（Web 侧 `verify_rustweb.sh` 口径）加一条 grep 断言——`op_convert` 中不再存在以 `text_node(&src)` 形态产出四类 act 的源段落臂（防回潮）。

### 两案对比（任务点名项）：Web 自身产出是否随之改真型

| | 案 A：产出改真型（G1，**推荐**） | 案 B：只读兼容、产出维持源段落 |
|---|---|---|
| 内容 | 转换产出 + G2 + G3 + G5 | 仅 G2（修静默错误）+ G3 + G5 |
| 数据面 | 全端产出单形：命令式转换只产真型；源段落仅剩手打 MD 与存量 | 双形永久并存：Web 转一次、块变源段落；原生转一次、又变真型——**同块在双端间被反复改形**，每次改形丢 runs（源形臂压平） |
| 与裁定 | 正面落实「以真型为正」 | 只做到「能读」，裁定落空一半 |
| 成本 | 多 G1 一臂改造 + 行切分 helper（M 级，§4） | 省 G1 |
| 风险 | 转换落点/编辑态衔接需回归（有现行 D-11 落点账与测试托底） | 零产出风险，但 F-07 分叉永久化、审计矩阵永久双行 |

结论：案 A。案 B 省下的只是一臂改造，换来的是表示分叉的永久化与每次跨端转换的 runs 损耗，与裁定和去兼容口径都相悖。

---

## 3. 双端互通验收口径

夹具单源：先在 core 测试区落一份夹具文档 JSON（验收与 G5 共用同一夹具，不另造）：含 §1 开头样本全集 + 一篇混排文档（三类真块 + MD 源段落 + 待办/标题/图片占位混排，模拟真实跨端文档）+ 一篇纯存量源段落文档（回归基线）。

往返断言（ZIP 互导主链：原生导出 ZIP → Web 导入 → Web 导出 ZIP → 原生再导入）：

1. **无编辑往返不变**：Web 导入后不做任何编辑直接导出，两份 ZIP 的 doc JSON 逐块深等（附件/清单按既有备份契约另核）。——钉「打开即改写」类问题。
2. **编辑他块不殃及**：Web 打开夹具篇、只改其中一个段落并保存导出，三类真块子树逐字段与导入前等。——钉 §1.5 保真。
3. **产出同形**：Web 斜杠把普通段落分别转 codeBlock/callout/两类列表，产出节点与原生 `convert()` 同 act 产出逐字段比对。允许差异仅两处（皆为已裁定的 Web 语义优位，E3 侧原生对齐）：① 列表逐行拆项（原生现单项，F-06）；② callout 尾随空段（原生现无）。除此之外 type/children/calloutType/attrs 全等。
4. **MD 导出语义在位**：夹具篇 MD 导出断言——代码块有围栏且围栏长 > 正文最长反引号串、callout 有 `> [!WARNING]` 等变体头、编号列表 start 保留；HTML 导出断言 `<pre>` 与 `<ol start>` 在位（既有测试扩夹具即可）。
5. **存量不回退**：纯源段落基线篇全链路（打开/预览/点回源码编辑/保存/导出）行为与现行一致——G1-G3 不碰段落宇宙，以既有 Web 测试集 + 冒烟为据。
6. **浏览器实跑**：夹具 ZIP 在 Simular Box 的已部署构建上实跑一遍（导入 → 逐篇打开截图核三类块呈现 → 各转一次 → 导出回读），按测试分工归 box、本机只落码与编译级自检；呈现核对点 = §1.2/1.3 三臂形态（callout 头与变体色、代码等宽块、列表标记与起始号）。

断言 1-4 为代码级（core/web cargo test），5 为既有测试集回归，6 为 box 实跑留痕——三层各司其职，不把代码级绿写成真机/浏览器通过。

---

## 4. 工作量分级与排批建议

| 批 | 内容 | 量级 | 备注 |
|---|---|---|---|
| W1 | G5 core 往返夹具 + 契约测试（先行，纯测试） | S | 给 W2/W3 铺断言网；core 无生产代码改动预期 |
| W2 | G1 + G2（ops.rs 转换产出单点化：共用产出函数 + runs 按行切分 helper + 落点换算 + md_edit 置位收口） | M | 本设计主批；JS 桥原则上不动（btype 语义现成），落码前 grep 核 md_edit 消费方 |
| W3 | G3（export.rs 两臂 + 围栏规则单点抽取） | S | 可与 W2 并行（不同文件、仅围栏规则抽取点相接——先落 W3 的规则单点或 W2 直接引用，二选一在落码时定，不留双份） |
| W4 | §3 验收 6（box 浏览器实跑）+ verify 静态锁（G5 后半） | S | 随 W2/W3 落地后的组版走 |
| — | G4 智能前缀 | 不排 | 案乙分期，待真型产出稳定后单独评估 |

耦合与排序：

- **与原生 E3（转换语义单点化）**：代码零交集（Swift vs Rust），但共用语义表——本报告 §2 的产出表即该表（Web 语义为基准：剥前缀/逐行/尾随/清字段；表示为真型）。验收 3 的「允许差异两处」就是 E3 的待对齐清单；E3 落地后该断言应收紧为全等。两批先后不限，建议 E3 先行或并行均可，但验收 3 的全等版断言须等双侧都落。
- **与 U4a/U4b（EDT-16/17/19 场景）**：场景验的是原生转换；Web 侧 W2 落地不阻塞 U 批。反之 U 批若先行扩了原生转换面（如新 act），W2 的产出表需同步复核——落码前以审计矩阵 + E3 最新报告对表一次。
- **与在途 iOS 各批（0.9.58 工作树）**：W1-W3 全在 `rust/crates/core` 与 `rust/apps/web`，与 iOS 领地（`rust/apps/ios`、ffi 导出面）零交集，可与 iOS 批次并行落码；但组版/冒烟节奏分开走（Web 走自身 CI 与 box 冒烟，不塞进 iOS 组版）。
- **与 MD 预览/解析（core md.rs）**：零改动——段落宇宙不动是本设计的边界，W2 落码时凡需碰 md.rs 的想法一律停下重审（大概率是方向错了）。
- **i18n**：无新文案（转换命令标题沿现行语言包键），零耦合。

风险登记：W2 的 runs 按行切分 helper 是唯一新算法面，边界（跨行标记 run、空行、首尾 `\n`）以单测钉死；若实测复杂度超预期，降级方案 = 逐行纯文本（与现行源形臂同损耗、只在列表一类），但 codeBlock/callout 两类的 runs 保留不降级（无切分问题、直传 inlines）。

---

## 附：证据索引（本报告行号出处）

- 原生产出/落盘：`apps/ios/app/MomentApp.swift` :7196-7268（convert）、:218-262（flushedNode）。
- core 模型与迁移：`crates/core/src/model.rs` :137-170、:224-233；`crates/core/src/migrate.rs` :26、:771、:794、:901-913。
- 加载路径：`apps/web/src/persist.rs` :1075-1087；`apps/web/src/main.rs` :1043-1073；`crates/storage/src/lib.rs` :216、:231、:297-300。
- 只读渲染：`apps/web/src/blocks.rs` :222-226、:477、:869-908。
- 编辑器：`apps/web/src/editor/render.rs` :245、:283-340、:354-390、:430 起、:491-506；`apps/web/src/editor/model.rs` :101-106、:501-629、:638-642；`apps/web/src/editor/ops.rs` :325、:383-395、:1195、:1271-1399、:1469-1694；`apps/web/src/editor/js/editor.js` :388、:890-904、:1108、:1803-1814。
- 导出：`apps/web/src/editor/export.rs` :866-874、:1014-1049、:1148-1259、:1404、:1576-1605、:1639 起。
