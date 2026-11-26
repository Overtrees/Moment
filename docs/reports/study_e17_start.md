# E-17 ①（有序列表编号起始值）方案研究（2026-11-24，只读研究、未落码）

承 [measure_e17_list_export.md](sandbox://workspace/Mynote/measure_e17_list_export.md) ① 的实测：Rust 结构化 `numbered-list` 节点导出 MD 时编号被重编（3/4/5 → 1/2/3），因模型无 start 字段。本简报查清三件事：原版编号存哪、「从 3 开始」在真实存量里如何产生、若修与格式冻结红线的兼容方案。结论逐条标 proven / inferred / unknown。

## 一、原版数据模型：编号就是文本，没有 start 这回事

1. **原版列表是单个 paragraph 块，编号是 children[0].text 的字符本身**（proven）。斜杠转有序列表时，块被强制降级为 paragraph（`forcedParagraph`），children[0].text 存逐行拼好的源文本，编号按行号 `(lineIndex + 1) + '. '` 生成（src/app/editor/use-slash.js:513-534）。全仓检索 `ordered_list` 只出现在三处：命令定义（src/app/editor/commands.js:133）、上述转换逻辑、导出分支——**原版编辑器从不产生 type=ordered_list 的块**（proven，全仓 grep）。
2. **导出原样返回文本**（proven，本研究 node 直跑复证）：export.js 的 blockToMarkdown 对 paragraph / ordered_list / unordered_list 一律 `return text`（src/app/editor/export.js:69-74）。夹具「3. 甲项\n4. 乙项\n5. 丙项」以 paragraph 形态和 ordered_list 形态喂入 toMarkdown，输出均为逐字 `3. 甲项\n4. 乙项\n5. 丙项`。
3. **编号的显示语义由 marked 在渲染时解释**（proven，本研究以仓库自带 vendor/marked.min.js 实测）：源文本 `3./4./5.` → `<ol start="3">` 显示 3、4、5；源文本 `1./7./2.` → `<ol>`，即**只有首行数字决定起始，其余行数字被忽略、按序递增显示**。原版 HTML 导出走同一条 marked 路径（export.js:226-230 renderMarkdownBlock）。
4. **原版编辑器渲染函数根本没有列表 case**（proven）：renderDocToEditorHTML（src/editor/editor.render.js:37-108）无 ordered_list/unordered_list 分支，未知类型落 default 渲染为 `<p>` + children[0].text。备份校验的已知块类型表同样不含列表类型，注释明言「未知历史块类型可导入、渲染安全降级为文本」，校验对这类节点直接放行（src/services/backup-validate.js:100-110）。

**小结**：原版不存在「编号存字段」这回事——没有 attrs.start、没有渲染时按模型生成编号；编号活在 MD 源文本里，起始值 = 首行数字。这与格式 ground truth「列表是 paragraph + MD 源码」一致。

## 二、「从 3 开始」如何产生：真实形态下易产生、且两端都不丢

1. **在源段落形态下，「从 3 开始」极易产生且完全合法**（proven，代码实证）：列表源文本就是可编辑纯文本——删掉 1、2 两行后剩下的文本天然以「3.」开头，原版全仓**没有任何重编/归一逻辑**（grep renumber 等零命中；parseEditorDOM 对段落原样取 textContent，src/editor/editor.render.js:315 起）；手打「3. 」开头、粘贴外部 MD、导入备份（校验器不查文本内容）同样直接带入。
2. **但源段落形态下两端都不丢起始值**（proven）：Rust MD 导出对 paragraph 走原样返回（rust/apps/web/src/editor/export.rs 末尾 `_ => text`，注释明载「paragraph（含存 md 源码的列表段）原版均是正文原样」）；Rust 预览解析 MdBlock::List **自带 start 字段**、渲染时输出 `<ol start="3">`（rust/apps/web/src/blocks.rs MdBlock::List 定义与渲染分支）。即用户真实使用路径（原版存量、Rust 斜杠建表——Rust 斜杠同样落源段落且逐行从 1 拼号，editor.rs:5989-6052 并注明「原版模型是 md 源段落、不造 bulleted-list/callout 类型」）里，「从 3 开始」从产生到显示到导出全程无损。
3. **E-17 ① 的残余面只存在于结构化 numbered-list 节点，而该节点在双端均无现实生产路径**（proven）：
   - 原版从不产生（见一.1）；Flutter 版内部用 AppFlowy 的 numbered_list，但其导出 ZIP 实测只有 paragraph（见下条），格式层从未出现结构化列表。
   - Rust 现行代码中 `"numbered-list"` 的**唯一赋值点**是已存在结构化列表内部的列表类型互换（editor.rs:5914-5925）；打开文档时无段落→结构化列表的转换（editor.rs:1400-1430 的打开归一只做尾随空段/行内形态/围栏合并）；storage 与 core backup 路径无任何列表转换（grep 实证）。该词汇自首个 Rust Web 提交（091478a）带入，属内部模型词汇。
   - **真实存量实测零命中**（proven，本研究解包两份验收备份统计）：real_backup.zip 与 flutter_export.zip 的节点类型均只有 paragraph（23）与 attachment（1），**连普通列表段落都没有**，更无结构化列表节点。样本仅 2 篇备忘，此条对「用户全部历史数据」的覆盖为 inferred（样本小），但与「双端均无生产路径」的代码实证互相印证。
4. **结构化列表的「应从 3 开始」语义本身也无从产生**（proven）：没有任何代码给结构化列表赋过 ≠1 的起始（字段都不存在）；在结构化列表里删掉头两项，现行渲染/导出按位置从 1 编号——用户若想让它「从 3 开始」，这个意图只存在于手造夹具里。measure 报告的 Rust 夹具正是手工构造的形态。

**小结**：① 的残余面 = 「存量出现外来/手造的结构化 numbered-list 节点」×「其预期起始 ≠1」，两个条件在真实数据与双端生产路径上均无实证命中。它与 ②（行内标记丢失）、③（子项文本在父项行重复）的性质不同：②③ 发生在结构化节点上、是导出侧可修的真缺陷（plain_text 口径问题），但同样只影响结构化节点存量；① 则连「修好后的正确值」都没有数据来源，除非先造字段再造产生路径。

## 三、若确需修：方案与格式冻结兼容性

前提事实（proven）：Rust 的 Node 以 `extra` 扁平透传未建模字段、序列化无损往返（crates/core/src/model.rs 文件头口径与 Node 定义）；attrs 是原版放 level/checked/fileId 的嵌套对象，Rust 侧 set_attr 读写现成（editor.rs:5585-5592）。原版对**未知 attrs 字段**的处置分三面（均 proven）：

- **备份校验**：只对已知键做类型校验（level/checked/fileId/items），未知键不拒绝、不删除（backup-validate.js:109-147）；未知块类型更是整节点放行。
- **纯存储/导入往返**：JSON 原样存取，不重建节点，未知字段不丢。
- **编辑重建（parseEditorDOM）**：未变化的块整对象保留 prev（含全部未知字段）；文本变化的块只重建已知 attrs（heading 的 level、todo 的 checked）。但此面与结构化列表无交集——结构化列表在原版渲染不出可编辑形态（落 default `<p>` 且 children[0].text 为空），原版用户根本编辑不到它；它在原版侧的降级是既存事实，不因多一个 attrs.start 而变坏或变好。

### 方案 A：结构化节点加 attrs.start（模型层小改）

- 改法：numbered-list 节点加 `attrs.start`（仅 start≠1 时写）；渲染两处 marker 改 start+i（editor.rs:6334、blocks.rs:522）；list_md 改 start+i（editor/export.rs）；列表编辑链定维护口径（删首项 start 是否递增、拆分/合并/类型互换时 start 如何传递）。
- 格式兼容：字段只出现在 Rust 独有节点类型上，**不含结构化列表的文档存储与导出字节逐字不变**；原版读到它走既有未知类型降级，不报错、不丢其他字段（校验实证见上）。严格说这是「在冻结格式的自有扩展面内加字段」，与 heading 加 level 时的性质相同（level 本就是原版字段，此为 Rust 首创字段，差异在此）。
- 代价/风险：中。真正的成本不在存字段，而在**维护语义是原版没有的新行为面**——源段落形态下起始值靠文本自维护（删行不自动改号），结构化形态若删首项自动 +1 就与源形态口径分叉，若不自动则 start 只是导入时的静态快照、编辑后即与用户直觉脱节。两种口径都需拍板并写探针锁住。

### 方案 B：不修 ①、关单登记（②③ 拆分单修）

- ① 关单口径：残余面仅存在于构造夹具与外来手造数据，真实存量零命中、双端无生产路径，登记为已知限制（MD 导出对结构化有序列表恒从 1 编号）。
- ②③ 与 ① 拆分：行内标记丢失、子项文本重复是导出侧 plain_text 口径问题，不涉模型层，按原计划修（list_md 行内序列化 + 父项只取自身行内文本）。
- 后果：若未来真有外来结构化列表数据进来（例如其他工具生成的备份），其有序列表导出仍重编——影响面限于 MD/HTML 导出的编号呈现，**存储数据本身不丢、不改**（重编只发生在导出文本里，随时可回滚修复）。

### 方案 C：结构化列表归一为源段落（与原版模型彻底对齐）

- 改法：打开/落盘时把 bulleted-list/numbered-list 折回 MD 源段落，起始值写回首行文本。
- 代价/风险：最大。编辑器 Loc::Item 全链（拆分、合并、拖拽排序、类型互换、逐项编辑）都建在结构化项上，归一等于废掉整套列表编辑内核并改变现存结构化文档的存储字节；这已是独立的「列表内核归一」专项，不是 E-17 的修法。不推荐作为本项处置。

## 四、处置选项（请拍板）

| 选项 | 内容 | 后果 |
|---|---|---|
| **B（推荐）** | ① 关单登记为构造夹具面；②③ 拆出按导出侧修法单独立项 | 零模型改动、零格式风险；真实路径本就无损。外来结构化数据导出编号仍重编（仅呈现层，随时可补修） |
| **A** | 给结构化节点加 attrs.start 全链维护 | 夹具面也无损；但新增原版没有的维护语义需定口径（删首项是否递增等），且给 Rust 独有节点开了首个自创 attrs 字段的先例 |
| **C** | 结构化列表归一源段落 | 与原版模型彻底统一；代价是重写列表编辑内核，远超 E-17 范围，不建议捆绑 |

倾向说明：① 与 ②③ 建议脱钩——无论 ① 选哪个，②③ 都应修（它们是同一批结构化存量上真实存在的导出错误，且修法不涉模型层）。① 选 B 的主要依据是二.3 的双重零命中（真实存量零、生产路径零）；若后续真在用户数据里发现结构化列表存量，A 随时可按本简报直接立项，字段与落点均已查清。
