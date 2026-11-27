# 原生 callout 尾随空段与 Web 全等微批

- 出处：impl_web_block_compat.md 语义对照表唯一残留差异——斜杠/菜单转 callout 后 Web 补尾随空段，原生 E3 的 M-03 只覆盖 todo 路径、callout 顶层路径不补（设计允许差异二）。本批把 E3 已落的同一助手 `ensureTrailingEmptyPara` 扩到 callout 顶层转换路径，不新造第二套。
- 纪律：不提交、不 bump，随 0.9.58 组版。落码文件：rust/apps/ios/app/MomentApp.swift（转换领地三处）、rust/apps/ios/app/verify_ios.sh（[25] 组 B25-E3-5 改判 + 新增 B25-E3-6）。

## 口径对账（Web 真源逐项核）

Web 真源 = rust/apps/web/src/editor/ops.rs 的 `op_convert`（Web 斜杠与块菜单共用同一转换入口）：

| 路径 | Web 口径 | 落码前原生 | 落码后 |
|---|---|---|---|
| 顶层转 callout | 补：`act == "callout" && !next_is_empty_para` 时在 i+1 插空段（ops.rs 顶层真型臂，注释「Callout 在原版尾随空段清单内（斜杠审计 S7）」） | 菜单/斜杠均不补 | 两路径均补（见落点） |
| 顶层转 todo | 补（todo/musicCard/imgTextCard/imageTextRow 同臂，S7 needsTrailingParagraph） | M-03 已补 | 不变 |
| 列表项转 callout（Item 臂） | 不补：Item 臂走 apply_true_block_form 产真型提出，整臂无尾随插入（divider 的 D-14 自带处理不在此列） | 升格路不补 | 不变（同口径） |

现成空段判定两侧同式：下一块为 paragraph 且纯文本 trim 后为空则不补；被转块位于文末（无下一块）时 Web `next_is_empty_para` 为假、照补，原生助手 guard 同果（无下一块不命中早退、落 trailingParagraph 补段）。焦点口径同 Web：补段不动焦点（焦点仍落被转块令牌起点；仅图文卡类落尾随段，原生助手注释「焦点不动」与 todo 路径既有行为一致）。

## 落点（MomentApp.swift，三处）

1. **菜单路径** `setBlockType`：补段条件由 `type == "todo"` 扩为 `type == "todo" || type == "callout"`，共用同一助手调用。菜单路径块恒顶层（调用方为块菜单对顶层行块操作，E3 已定性），与 Web 顶层臂同口径，无需额外守卫。
2. **斜杠路径** `applySlash` 的 `case "callout"`：`convert("callout")` 之后新增顶层守卫补段——`if parentList == nil { ensureTrailingEmptyPara(after: b) }`，与同函数 `case "todo"` 的既有守卫同式；列表项升格路（parentList 非 nil）不补，与 Web Item 臂同口径。剥前缀（M-05）仍在 convert 之前、顺序未动。
3. **助手文档注释**同步扩围：`ensureTrailingEmptyPara` 注释由「转 todo 后」改记「转 todo/callout 后……callout 与 todo 同臂系 Web op_convert 顶层口径，斜杠审计 S7」，防后续读码者按旧注释误判 callout 不应补。

助手本体（失效判定 + trailingParagraph 补插）零改动——扩围只在两个调用点的条件/守卫，不动单点实现。

## 断言（verify_ios.sh [25] 组）

- **B25-E3-5 改判留痕**：`ensureTrailingEmptyPara` 全文件计数由 3（定义 1 + 调用 2）改判为 4（定义 1 + 调用 3：菜单 1、斜杠 todo 1、斜杠 callout 1），注释内写明改判缘由指向本报告。
- **新增 B25-E3-6**：锁 callout 两路径接入——① 菜单补段条件 `type == "todo" || type == "callout"` 全文件恰 1；② 斜杠 `convert("callout")`（全文件恰 1）后 8 行内顶层守卫 `if parentList == nil` 与助手调用同在（守卫在位即锁「升格路不补」一并成立）。

## 自检

- 本机 verify 全跑：B25-E3-1..6 全绿（E3-5 改判后通过、E3-6 新增通过）；全量仅剩 2 条 ✗，与本波各批开工基线同为构建产物陈旧项（ipa 陈旧、产物语言包未构建，tree 构建自解），非源码断言、非本批引入。
- MomentApp primary 遍全量类型检查（build-app2.sh app.o 遍同旗标、输出重定向仓外）：**零 error、.o 产出**。过程如实记：本机内存被共享宿主挤压（可用 ~600MB），前两跑分别遇 swift-frontend 崩溃与 SIGBUS（崩点在无关的 runsFrom 类型检查、诊断输出零 error），第三跑完整通过——属已知本机环境退化形态，结论以完整跑为准。
- 并发纪律：动工前 git diff 全量快照（/tmp 留档）映射领地——本批三落点均在 E3 已落定的转换领地内，与在途首页回归批/DT 韧性批领地无交叠；完工复验 = 全量 verify 仅基线红 + 全树 primary 类型检查零错误（在途各批现行代码同遍共检通过），他人 hunk 无损。

## 真机终判点（装后抽验，并入 E3 终判清单第 7 项旁）

1. 顶层段落经斜杠转提示：提示块后应紧跟一个空段（后已有空段时不重复补）；块菜单转提示同验一遍。
2. 列表项经斜杠转提示（升格提出）：提出后不应新增尾随空段（Web Item 臂口径），其后为原尾表或原下一块。
3. 文末段落转提示：文末应补一个空段、光标仍在提示块内。
