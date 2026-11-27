# Web 兼容原生真块型 — 落码报告（W1→W4）

- 日期：2026-11-27。依据：plan_web_native_block_compat.md（设计推荐案 A）+ 用户裁定「落盘形态以原生真块型为正」。
- 领地：rust/apps/web + moment-core 契约测试 + scripts/verify_rustweb.sh + tests。core 的 md.rs 未动；iOS 领地零接触。
- 验证放置（用户 2026-11-27 17:29 最终口径）：构建/测试/浏览器验收全在 tree（InstaBox 机器 tree 的 /opt/work/Moment 克隆，改动经既有分片通道同步、md5 对账）；本机结果仅作落码期静态自检，下文结论均以 tree 为准，浏览器结论为 tree Chromium 口径。

## W1 契约测试先行（先红后绿留痕）

- 新增 `rust/crates/core/tests/block_compat.rs`：夹具与设计 §3.1 同构——真 codeBlock（多行、反引号、带标记 runs）、callout 五变体、start=3 有序列表（嵌套子列表）、带标记/链接的无序列表，另加一篇纯存量 MD 源段落篇。三条契约断言：① 无编辑往返（ZIP 导出→导入）逐块深等且迁移通道零命中（真型块不被当存量改写）；② 编辑一篇的无关段落后，另一篇的三类块子树逐字段不变；③ 存量源段落篇往返不变（源形态不被顺手升级）。
- 先红留痕：W2 落码中先以编译红（E0425，行切分 helper 尚不存在）确认测试与实现缺口对应；W2/W3 落齐后转绿。tree 定案：moment-core 全套件通过（含本文件 3 条）。

## W2 转换产出单点化（ops.rs）

- 新增单点 `apply_true_block_form(n, act, inlines, tok_pos, next_id)`：斜杠顶层转换与列表项转换（Item 臂）共用一处产出 codeBlock/callout/bulletList/numberList 真型。id 工厂以参数注入（生产传 gen_id；主机单测注入序列 id——gen_id 走 js_sys 在主机靶不可用，此为单测可达性的必要设计）。
- 唯一新算法面 `split_inlines_by_line` / `split_node_lines`：runs 按 \n 切分，口径与 str::lines() 一致（尾随换行不产末尾空行、空文本零行）；文本节点按行克隆、标记随段走；link 等容器节点逐行克隆包裹、递归切分（设计 §2.3 的结构保真方案，未用降级方案——真型夹具的带标记代码行与带链接列表项均有测试锁）。
- 语义沿 Web 现行规则逐项保留：codeBlock 不剥前缀（D-13 不变）runs 直入；callout 先 strip_md_prefixes（剥变则单文本节点承载、未变则 runs 保标记）、顶层 callout_type="note"、空正文占位「提示内容」；列表先剥前缀、**逐行拆项**（不抄原生整段塞单项）、空正文占位「列表项」、numberList 不写 start、bulletList 清 start、clear_type_fields 清公共字段；列表落点按 UTF-16 逐行走查换算到含 tok_pos 的项（原 D-11 规则的多行推广）。
- op_convert 顶层 MD 源段落臂整臂删除（`text_node(&src)` 产出路径清零）；callout 尾随空段规则保留在 op_convert（与 todo 同臂）。
- G2 修复：Item 臂对 act ∈ {codeBlock, callout} 改走单点产真型（提出为顶层真块），不再经 apply_type 静默变段落；其余 act 仍走 apply_type。converted.children 仅在 apply_type 路径赋值（单点路径自带 children，旧无条件回写会覆盖 callout 占位/清字段成果，已随路修正）。
- md_edit 参数改名 _md_edit：四类转换不再置位 MD 源码编辑态；两个调用方（dispatch.rs、hooks/slash.rs）的 Some 分支自然不再命中，无需改动。
- ops.rs 新增 6 条单元测试（行切分三态、容器包裹、codeBlock/callout/列表产出、Item 提出、落点换算）。tree 定案：moment-web 74 条全过（65 既有 + 9 本批新增，含 W3 的 3 条）。

## W3 导出两臂（export.rs / blocks.rs）

- `block_md_str` 在默认臂前加两臂：codeBlock 产围栏形（围栏长 = 正文最长连续反引号串 + 1、下限 3），规则抽为同文件 `md_fence` 单点（G1 后产出路径已不用围栏，无双份实现）；callout 产 `> [!{VARIANT}]` 头 + 逐行 `> ` 前缀，变体归一复用 blocks.rs 的 `callout_variant`（改 pub；未知/缺失落 NOTE）。
- 默认臂注释改义：只剩「paragraph（含存 MD 源码段）原文直出」一义，与真型两臂分开（G3 关闭）。
- export.rs 新增 3 条测试（围栏长度随正文反引号、五变体+未知+缺失归一、源段落原文回归）。

## W4 防回潮与实跑验收（tree）

- 静态锁：scripts/verify_rustweb.sh 新增第 16 节——断言 ops.rs 含 apply_true_block_form 与 split_inlines_by_line，且 `text_node(&src)`、`md source`、`md_edit.set(Some` 在 ops.rs 零残留。tree 实跑全脚本：VERIFY RUSTWEB ALL PASS（含本节）。
- 专用探针 `tests/probe_block_compat.mjs`（设计 §3.6）：与 core 契约同夹具 ZIP 导入 → 五 callout 变体类/头衔、代码块 runs 文本、start=3 标记、嵌套项、编辑器内 runs 源码形态无损 → 斜杠转 callout 产真型保正文 → 列表项斜杠转 codeBlock 提出（G2）且源表恰少一项 → MD 导出围栏/变体头/start/转换成果回读 → 存量篇预览不回归且无真型块。tree Chromium：**ALL PASS**。
- 既有冒烟按新行为更新与回归（tree Chromium）：
  - smoke-rustweb-w3.mjs 第 4/5 步原断言旧行为（转列表/代码块进 mdsrc 源码编辑态），按裁定改写为真型断言（真列表占位项/续打两项/失焦保真；真代码块块内换行/失焦保真/无 MD 预览介入）。第 4 步起点改显式点击粘贴末段 + End 再 Enter（合成粘贴后的环境光标位置不确定，旧写法依赖它、tree 实跑定因）。实跑全绿。第 6 步依赖宿主本地真实备份夹具（12MB、未随仓走）：改为缺席时响亮跳过（⊘ 口径，与 verify 脚本既有跳过同式），夹具在位时仍严格全跑——tree 上该夹具缺席，本步在 tree 跳过（见待办）。
  - smoke-rustweb-export / editor2 / w2：ERRORS: none。probe_slash_anchor：ALL PASS。
  - smoke-rustweb-blocks / tails：夹具路径原写死 $HOME/workspace 布局，tree 上不存在——改为相对测试文件解析（仓内 fixtures，各宿主通用），实跑 ERRORS: none。此为测试基建可移植性根治，非断言变更。
  - probe_batch3：C-11/C-12 两红（link-card err 态标题/loading 落 err 卡）。A/B 定性（proven 非本批引入）：在 tree 上 stash 本批四源文件、重建批前 dist 重跑该探针，两项同值同红；恢复本批后亦然。属 tree 上既存失败（失败面在 link-card err 呈现路径，本批零接触），建议主线另行 triage（疑与宿主环境下该夹具卡的状态落点有关），不在本批领地。
- tree 环境补齐（测试脚手架，不入仓）：tests 目录 npm 装 playwright-core（探针模块解析）、dist 以 build.sh 在 tree 构建、serve_headers.py 起 :8096。

## 与 E3 语义表对照（设计 §3.4）

E3 已从原生侧同表落码（impl_conversion_e3.md）。逐项对照结果：

| 项 | Web 本批 | 原生 E3 | 状态 |
|---|---|---|---|
| 转换产出 codeBlock/callout/list 真型 | 单点产真型 | convertNodeType 真型 | 全等 |
| 列表多行逐行拆项 | split_inlines_by_line 逐行成项 | F-06 runsSplitByLine 逐行成项（同 lines() 口径） | **全等**（设计允许差异一已关闭） |
| callout 尾随空段 | op_convert 保留（todo/callout 同臂） | M-03 仅覆盖 todo；callout 未补 | **残留差异**（设计允许差异二仍开） |
| 剥 MD 前缀适用集 | 列表/callout 剥、codeBlock 不剥 | 同口径（M-05/F-07） | 全等 |
| start 传递 | Web 既有口径不变 | F-05 三助手对齐 Web | 全等 |
| callout 重转保变体 | 顶层新转恒 note；列表项提出保留既有字段（clear 不摘 callout_type） | M-04 不清不设、读缺省 note | 语义等价（新转入口径同为 note） |

- 设计验收 3 的「E3 落地后收紧为全等」尚差 callout 尾随空段一项：原生斜杠/菜单转 callout 后不补尾随空段，Web 补。建议原生侧一个微批补齐（ensureTrailingEmptyPara 扩到 callout 顶层路径即可，与其 M-03 同一助手），不在本批领地。

## 待办与组版清单

- 待办（非本批阻塞）：① 真实备份夹具 real_backup.zip（12MB）未迁 tree，w3 第 6 步在 tree 跳过——后续把夹具迁到 tree 的 $HOME/workspace/moment-zip-acceptance/ 后该步自动恢复严格跑；② callout 尾随空段原生微批（见对照节）。
- 待组版文件清单（本批，不自行提交、未 bump 版本号）：
  - rust/crates/core/tests/block_compat.rs（新）
  - rust/apps/web/src/editor/ops.rs
  - rust/apps/web/src/editor/export.rs
  - rust/apps/web/src/blocks.rs（仅 callout_variant 改 pub）
  - scripts/verify_rustweb.sh（第 16 节）
  - tests/probe_block_compat.mjs（新）
  - tests/smoke-rustweb-w3.mjs（第 4/5 步改写 + 第 6 步缺席跳过）
  - tests/smoke-rustweb-blocks.mjs / tests/smoke-rustweb-tails.mjs（夹具路径相对化）
  - docs/reports/impl_web_block_compat.md（本报告）
