# 盘点：彻底去除兼容、贴合 Rust 原生（只读盘点）

- 基线：HEAD `66a4496`（2026-11-24）。行号以 HEAD 为准；`editor.rs` 工作树有并行线未提交改动，该文件一律引 `git show HEAD:` 的行号并标注（HEAD）。其余文件工作树与 HEAD 一致。
- 背景口径（用户 2026-11-24 连续放宽）：功能行为等价优先于形态 1:1；数据格式字节兼容不再是硬约束（现存笔记以展示为主）；种子数据格式可改为 Rust 原生；只为兼容旧格式存在的代码应去除以减少冗余。
- 证据标注：**proven** = 本次读码/grep 实证；**inferred** = 由已证事实推导。
- 工作量级：S ≤ 半天；M = 1–3 天量级；L = 一周量级或跨多文件结构改造。均为粗估。

## 0. 结论摘要

1. 真正的「兼容层」并不厚：它 = 一个架构选择（core 模型逐字段镜像旧块 JSON + `extra` 透传，`model.rs:1-5`、`backup.rs:1-6` 头注自陈，proven）+ 约十处双读/别名/透传点。删冗余的主战场是模型类型化（B 类），不是逐个删分支。
2. 种子数据只有一处：`main.rs:875-931` 的 `sample_data()`，用裸 JSON 拼装旧格式再 `from_value` 解析——改原生形态是 S 级，且它已经半脱钩（时间戳用毫秒数，与原版 ISO 串不同，见 §1）。
3. 多数双读点（§2.3–2.6）的删除都卡在同一个前置：存量文档里旧形态的归一入口。这与决策点 D2（原版导入保留为一次性迁移通道）是同一件事——先有迁移通道，B 类大半自动解锁。
4. 备份 ZIP 是唯一需要用户拍板的格式面（D1/D2，§4）。其余各项不依赖该拍板即可排期。

## 1. 种子数据

### 1.1 落点与生成路径（proven）

| 项 | 位置 | 说明 |
|---|---|---|
| 种子生成 | `rust/apps/web/src/main.rs:869-931`（注释 869 起，`fn sample_data` 875，`from_value` 收尾 930-931） | 5 篇 demo 备忘（demo_exhibit/home/tools/book/music），裸 `serde_json::json!` 拼旧格式文档，再 `serde_json::from_value::<BackupFile>` 解析 |
| 注入点 | `main.rs:950` `use_signal(sample_data)` 为 App 初始值；`main.rs` 启动加载 effect（HEAD 约 1193 行 `no persisted state, seed sample`） | IndexedDB 无持久数据时保留种子；有持久数据则整表覆盖 |
| 附件清单 | `main.rs:26` `EMPTY_MANIFEST = {"version":1,"attachments":{}}` | 种子无附件字节，manifest 为空字典形 |
| 原版对照 | `src/app/demo-memos.js:14-88`（`buildBuiltinMemos`）+ 文件头 CN_CITY 城市表 | Rust 种子是其数据口径移植；CN_CITY 表（天气城市英转中）未移植，与种子数据无关 |

原生端（storage/SQLite）无种子：`Store` 初始为空（`crates/storage/src/lib.rs` 全文无 seed，proven）。

### 1.2 现格式与 Rust 原生模型的差异（proven）

种子数据本身就是按旧格式写的，其「原生模型」目前也只是旧格式的镜像（`Node` = text/type/id/children + `extra` 透传），所以差异分两层：

| # | 差异 | 证据 |
|---|---|---|
| S-1 | 生成方式：裸 JSON 拼装 + `from_value`，不走任何类型构造；字段写错只能运行时 `expect` 炸 | `main.rs:875-931` |
| S-2 | 时间戳用毫秒数（`Timestamp::Millis`），原版种子用 ISO 串（`demo-memos.js` `new Date(now).toISOString()`）——种子已在此处脱离原版口径，靠模型的双形时间戳（§2.1）才收得下 | `main.rs:886-887` 等 vs `model.rs:31-36` |
| S-3 | 节点 id 用固定短串（`de1`/`dh1`…），原版用 `genId()` 随机 id | `main.rs:880-928` |
| S-4 | heading 的 level、todo 的 checked 放 `attrs`；musicCard 的 url/meta/status 放节点顶层——全是原版节点工厂的字段布局，经 `extra` 透传承载，模型层无类型 | `main.rs:890,896-899,920-927`；`model.rs:66-70` 注释自陈 |
| S-5 | 备忘顶层 `version:2` 的 `BackupFile` 壳（含 exportedAt 位）被当作应用内部状态结构使用，不只是导入导出格式 | `main.rs:883-930`；App 全程以 `BackupFile` 为状态（`main.rs:950` 起） |

### 1.3 改成原生形态的落点

- 短期（不依赖模型改造，S）：`sample_data()` 改为直接构造 `BackupFile/Memo/Node` 类型值（去掉一层裸 JSON 与 `expect`）；时间戳统一走一种口径（与 §2.1 收紧方向一致）。
- 终局（依赖 §2.2 模型类型化，归 B）：种子按强类型块枚举逐块构造（heading/todo/musicCard 各有字段），S-4 的字段布局随模型定形。
- 存量提示：已首开过的用户，IndexedDB 里存的是旧形种子副本——它与普通存量文档同命，归一走 §4 D2 的迁移通道，不需要种子专项迁移（inferred）。

## 2. 兼容专用代码清单

### 2.1 模型层双形：Id 与 Timestamp（B）

- 位置：`crates/core/src/model.rs:9-46`。`Id` untagged 双形（字符串/数字，注释自陈「真实样本各一」）；`Timestamp` untagged 双形（ISO 串/毫秒数）。
- 用途：收下原版与 Flutter 两路来源的存量备忘。
- 删后影响：收紧为单一形前必须先归一存量（数字 id → 字符串、毫秒 → ISO 或反之）。下游 `storage` 以 `id_json`+`id_text` 双列存 id（`crates/storage/src/lib.rs:73-74,196-198`），收紧后可简化一列（inferred）。
- 证据：proven（模型定义 + `crates/core/tests/timestamp.rs:4-15` 双形测试）。

### 2.2 模型层总透传：Node.extra / BackupFile.extra / Manifest 不建模（B，根源项）

- 位置：`crates/core/src/model.rs:50-83`（Memo/Node 的 `#[serde(flatten)] extra`）；`crates/core/src/backup.rs:13-33`（BackupFile 的 `avatars: Option<Value>`、Manifest 的 `attachments: Option<Value>` 均不建模、原样透传，头注 4-6 自陈）。
- 用途：一切未建模字段（卡片 url/status/meta、附件 fileId、attrs、layout、avatars、manifest 附件元数据）靠透传保证往返无损。这是下面 §2.3–2.8 全部双读点的存在前提。
- 删后影响：即「模型类型化」本体——块按类型建模（枚举/结构体）、manifest 附件建模、avatars 或删或建模。工作量 L；与批 14（拆 editor.rs）、批 11（性能，Value 查找热点）强协同，应合并规划而非单独一遍（见 §5 冲突面）。
- 证据：proven。

### 2.3 字段双位读取：attrs 优先、顶层兜底（B）

- 位置：`rust/apps/web/src/blocks.rs:169-213`——`attrs_get`（173-176）、`heading_level`（190-204，attrs.level 缺失再读顶层 level）、`todo_checked`（206-213，同构）。文件头注释 169-172 自陈「兼容本应用旧版本写出的顶层形」。
- 现行写入只写 attrs（种子 `main.rs:890,896`、编辑器各工厂均 insert attrs，grep proven），顶层兜底只服务旧文档。
- 删后影响：删兜底本身 S；但旧文档的 heading 会回落默认 level 2、todo 回落未勾选——须先归一存量（迁移时把顶层 level/checked 搬进 attrs）才可删。归 B。

### 2.4 fileId 双位读取 ×3 份 + 双写一处（读 B / 停双写 A）

- 读取（三份同口径实现，冗余本身与兼容无关也值得并）：
  - `blocks.rs:271-285` `file_id()`：顶层 `fileId` 优先，其次 `attrs.fileId`，空串视为无；
  - `editor/export.rs:480-496` `export_file_id()`：同口径复制；
  - `settings.rs:661-671` `attachment_file_id()`：同口径第三份。
- 写入（双写，proven）：附件节点工厂同时写两处——`editor.rs`（HEAD）`:7257-7271` 先 insert `attrs:{fileId}` 又 insert 顶层 `fileId`（连同顶层 name/status/image）；而图片工厂只写 attrs（HEAD `:4522,7049,7064,7113,7257`）。
- 删后影响：停双写是 A（工厂一处改，S）——前提是读取端保留双读直到存量归一；三份读取合并为一份公共函数是纯重构（C 向收益，S）；双读收紧为单位随存量归一，归 B。

### 2.5 gallery items 三形态 + children 兜底，双实现（B）

- 位置：`blocks.rs:216-262`（`gallery_items`/`gallery_item_of`，注释 216-225 自陈三形态来源）；`editor/export.rs:498-548`（`export_gallery_items` 同口径第二份实现，537 行注释自陈回退口径）。
- 三形态：裸字符串 = 本应用自写（附件 id）；`{fileId}` 对象 = 原版编辑器实写；`{url}` 对象 = 外部直链。解析序 fileId 优先。另外 `attrs.items` 缺失/非数组时回退到 children 的 fileId 列表（blocks.rs:226-235、export.rs:537-548）。
- 删后影响：定一种规范形态（建议 `{fileId}`/`{url}` 对象或类型化枚举），迁移时把字符串形与 children 形归一，渲染/导出双实现合一。工作量 M。归 B（双实现合一的部分可先行，S）。

### 2.6 行内标记别名 strike（A）

- 位置：`blocks.rs:322`（`strikethrough || strike`）、`crates/core/src/inline_html.rs:118`（读双名，写只写规范名 `strikethrough`，见 :36-37）、`crates/core/src/inline_editor.rs:86`。
- 用途：收旧数据的 `strike:true` 标记；现行任何写路径只产 `strikethrough`（grep proven）。
- 删后影响：仅含 `strike` 的历史文档丢删除线渲染；三处各一行。归 A（接受历史渲染差异即可删；若走 D2 迁移通道，迁移时改名后删更干净）。

### 2.7 callout 变体别名链 kind/variant（A）

- 位置：`editor.rs`（HEAD）`:6363-6367`：渲染时 `calloutType → kind → variant` 三级回退取变体。
- 用途：`kind`/`variant` 在 Rust 侧无任何写路径（全仓 grep 只有此读点，proven）；应是早期/外部形态的别名。
- 删后影响：只保留 `calloutType` 后，带 kind/variant 的旧 callout 回落默认 note 变体。S。归 A。
- 注意区分：`blocks.rs:1049-1063` 的变体归一（note/info/todo/abstract… → 五类）是 MD 源码 Callout（GitHub 语法）的解析，是现行功能不是兼容层，归 C 保留。

### 2.8 块类型别名 music / code（A，附一次性扫描前置）

- 位置：渲染别名 `blocks.rs:531`（`"codeBlock" | "code"`）、`blocks.rs:638`（`"music" | "musicCard"`）；编辑器侧 `editor.rs`（HEAD）`:2314`（打开补拉含 `"music"`）、`:2451`（原子块清单含 `"music"`）。
- 现行写入只产 `musicCard`（HEAD `:5460`）与 `codeBlock`；导出侧只认 `musicCard`（`export.rs:1101,1342`）——`"music"` 已经是二等公民（导出走默认臂）。
- 存量实证：仓库内两份真实夹具的块类型普查只有 paragraph/attachment（本次 python 普查，proven），无 music/code 旧名。
- 删后影响：删别名臂 S；前置一次性扫描用户存量确认无此二名即可。归 A。

### 2.9 未知块类型降级为纯文本（C，保留）

- 位置：`blocks.rs:994-1004` 默认臂：未知 type 打一条 Diag 后以纯文本渲染。
- 来历：与原版校验策略同源——`src/services/backup-validate.js:100-107` 注释「Unknown historical block types remain importable: renderer safely degrades them to text」；`embedCard` 即其一例（原版列为现行类型，Rust 无渲染臂、只在 `editor.rs`（HEAD）`:614-618` 相邻判定里出现，靠此默认臂降级）。
- 保留理由：这不只是旧格式兼容，而是「任何未知类型不丢数据」的兜底，对未来新类型、外部导入同样成立；成本为一个默认臂。若日后格式版本化，可改为按版本门控，不必现在删。归 C。

### 2.10 ZIP 导入的容忍面（B，随 D1/D2）

- 位置：`crates/core/src/backup_zip.rs:76-124` `read_backup_zip`。
- 容忍点（proven）：
  - 无节点级校验：未知块类型、未知字段、attrs 任意形全部经模型透传收下（与 §2.2 同根）；
  - `Manifest.attachments` 为无类型 `Value`：字典形、数组形、任意形都不拦（`backup.rs:27-33`）；
  - `manifest_raw` 原文透传：导入存原文、导出原样带回（`backup_zip.rs:24-26,138-140`；storage 侧存 meta `manifest_json` 原文 `crates/storage/src/lib.rs:166-175`、导出回写 `:262-272`）——为保住 Rust 不建模的 manifest 字段而设。
- 反向事实：Rust 导入在版本上比原版更严——`BackupFile.version` 为必填，缺 version 的最旧格式包在原版可过（`backup-validate.js:63-65`「missing version is the pre-versioned legacy format」），在 Rust 会解析失败（proven，模型定义）。即「容忍」主要来自透传架构而非校验放宽。
- 安全限额（包 50MiB/条目 3000/单文件 50MiB/解压 200MiB，`backup_zip.rs:14-17`，注释自陈沿用原版校验上限）：是安全策略不是格式兼容，归 C 保留。

### 2.11 avatars 强制键与透传（待决，系于 D1）

- 位置：`settings.rs:608-620` `handle_export`：导出时若 avatars 为空强制填 `{}`，注释自陈为与原版 `buildBackupPayload` 的互通口径；`backup.rs:23-25` 模型透传；storage 侧 `avatars_json` meta 往返（`crates/storage/src/lib.rs:176-183,252-258`）。
- 处置：若 D1 定为 ZIP 转原生且 avatars 无产品功能 → A 可删整链；若 avatars 后续要做头像功能 → 建模保留。单列待决，不在本盘点定性。

### 2.12 内部不一致一处（顺手项）

- storage 导出在无 manifest 时回退字符串 `{"version":1,"attachments":[]}`（数组形，`crates/storage/src/lib.rs:270`），与全仓其余口径（字典形，`main.rs:26`）不一致。这不是兼容层，是内部双形，归一到哪形随 D1/manifest 建模一并处理。S。

### 2.13 不是兼容层的澄清（避免误删）

- `sj_*` localStorage 键（`sj_fontsize`、`sj_editor_independent_scroll` 等）：Rust 版与原版不同源（pages.dev vs github.io），键名相同只是命名沿用，不构成跨应用兼容，删改无收益。inferred。
- MD 源码段落承载代码块/列表/Callout（paragraph + children[0].text 存 MD 源码）：这是原版与 Rust 版共用的**现行**文档模型（`blocks.rs:1009` 起注释自陈），不是旧格式残留；是否改结构化块属于产品/模型设计议题，不在「删兼容」范围。
- 桥（bridge.rs）的触摸兼容回声抑制等：是浏览器事件兼容，与数据格式无关，不在范围。

## 3. 测试侧处置

### 3.1 仓库外验收 ZIP（cfa8265 后现状，proven）

- `crates/core/tests/backup_zip.rs:17-75`：`acceptance_zip()` 缺失即打印跳过（cfa8265 已修），`real_backup_zip_roundtrip`/`flutter_export_zip_roundtrip` 对两份真实包断言 read→write→read 深相等 + manifest 原文 + 附件逐字节。
- `crates/storage/tests/pipeline.rs:17-157`：同口径跳过；`run_pipeline` 对真实包跑导入→检索→导出全链并与原包对齐；`reimport_replaces_instead_of_appending` 亦依赖双样本在位。

### 3.2 仓库内真实夹具（proven）

- `crates/core/tests/roundtrip.rs` + `tests/fixtures/{real,flutter}_{memos,manifest}.json`：真实旧格式 JSON 入 git，断言解析→序列化深相等。本次普查：两份 memos 各 2 篇、块类型只有 paragraph/attachment、id 均为字符串、manifest attachments 为字典形。

### 3.3 新口径下的处置选项

| 选项 | 内容 | 代价/收益 |
|---|---|---|
| T-1 自造原生夹具（推荐默认） | 测试内以原生模型程序化构造全块类型 + 附件的 ZIP/文档夹具，断言改为原生格式往返与行为断言；默认套件不再依赖仓库外文件，CI 恒跑 | 一次性 M；覆盖面由构造决定，可超过真实样本（真实样本只有 paragraph/attachment 两类块，覆盖本来就薄，proven） |
| T-2 保留为可选外检 | acceptance 系列维持现状（缺失跳过 / `MYNOTE_ZIP_ACCEPTANCE_DIR` 覆盖），定位改为「旧格式导入/迁移通道的回归哨」，随 D2 迁移通道存续 | 零改动；但其断言语义（与原包深相等）在格式转原生后不再成立，须随 D1 拍板改写为「迁移后内容等价」断言 |
| T-3 仓库内夹具转迁移测试 | `roundtrip.rs` 的断言从「往返深相等」改为「旧夹具 → 迁移 → 内容/结构等价于期望原生形」；夹具保留入 git 作迁移语料 | M；与 T-1 互补：T-3 守迁移正确性，T-1 守原生往返 |

建议组合：T-1 + T-3 为默认套件；T-2 仅在 D2 保留迁移通道期间存续，通道退役时一并删。`timestamp.rs` 的双形用例随 §2.1 收紧后缩为单形（S）。

## 4. 决策点（请用户拍板，本盘点只给推荐）

### D1：备份 ZIP 导出/导入格式是否转 Rust 原生

| | 利 | 弊 |
|---|---|---|
| 转原生 | memos/manifest/avatars 全类型化，删 `manifest_raw` 透传（§2.10）、avatars 强制键（§2.11）、§2.12 双形；导出确定性；内部存储（idb 的 BackupFile JSON、storage 的 memo_json）与备份格式可统一口径 | 与原版/Flutter 互导断裂；用户已导出的旧 ZIP 新版不能直读（须靠 D2）；验收体系按 §3.3 重建 |
| 维持现格式 | 互通不变；§2 多数 B 项只能靠「读时归一」慢慢收，透传架构长期保留 | 兼容冗余长期化，与本次放宽的初衷相悖 |

**推荐：转原生**，但必须与 D2 打包拍板——单独转原生而无迁移通道，等于让用户手上的旧备份作废。

### D2：原版备份导入是否保留为一次性迁移通道

- 形态建议：独立 importer（只读旧 ZIP → 转原生模型 → 落库），与日常备份路径分离、单独成模块与测试；存量文档的字段归一（§2.3 顶层字段搬 attrs、§2.5 gallery 字符串形归一、§2.6 strike 改名、§2.1 id/时间戳单形化）也收进这条通道一次做完。若干版本后可整体退役。
- 利：旧备份不作废；B 类删除的全部前置集中在一处解决；主模型从此只面对原生形。
- 弊：迁移通道本身是一段要维护的兼容代码——但它只读旧格式、边界清晰、不污染主模型，与散落在渲染/导出各处的双读相比冗余度低得多。
- **推荐：保留为独立迁移通道**（与 D1 打包）。

### D3（附带）：存量归一时机

- 选项：(a) 首次启动一次性迁移并写回（迁移后存储里只有原生形，读路径最干净）；(b) 读时惰性归一（不写回，双形在存储层长期存在）。
- **推荐 (a)**，与 D2 通道共用同一套转换函数；Web 侧 IndexedDB 与原生侧 SQLite 各跑一次。

## 5. 分类汇总与建议落码顺序

### A 可直接删（纯兼容、无现行功能依赖）

| 项 | 位置 | 量级 | 备注 |
|---|---|---|---|
| strike 别名读 | blocks.rs:322；inline_html.rs:118；inline_editor.rs:86 | S | 历史文档丢删除线；走迁移改名更干净（§2.6） |
| callout kind/variant 回退 | editor.rs（HEAD）:6363-6367 | S | 无写路径（§2.7） |
| 块类型别名 music/code | blocks.rs:531,638；editor.rs（HEAD）:2314,2451 | S | 前置一次性存量扫描（§2.8） |
| 附件工厂双写停一处 | editor.rs（HEAD）:7257-7271 | S | 只停写顶层 fileId；双读保留至归一（§2.4） |
| avatars 整链 | settings.rs:614-620 等 | S | **系于 D1**：转原生且无头像功能时成立（§2.11） |

### B 先迁移再删（种子与存量形态）

| 项 | 位置 | 量级 | 前置 |
|---|---|---|---|
| 种子原生化 | main.rs:869-931 | S（短程）/ 随模型 L（终局） | 短程可立即做；终局随模型类型化（§1.3） |
| Id/Timestamp 单形化 | model.rs:9-46 | M | D3 一次性迁移 |
| attrs/顶层双读收紧 | blocks.rs:169-213 | S（删） | 迁移搬字段（§2.3） |
| fileId 双读收紧 + 三份合一 | blocks.rs:271-285；export.rs:480-496；settings.rs:661-671 | M | 合一可先行；收紧随迁移（§2.4） |
| gallery 形态归一 + 双实现合一 | blocks.rs:216-262；export.rs:498-548 | M | 迁移归一（§2.5） |
| manifest 建模、删 manifest_raw 透传 | backup.rs:27-33；backup_zip.rs:24-26,138-140；storage lib.rs:166-175,262-272 | M | 系于 D1（§2.10） |
| 模型类型化（extra 透传退役） | model.rs:50-83；backup.rs:13-33 | L | 全局工程，与批 14/11 合并规划（§2.2） |
| 测试体系切换 | tests/backup_zip.rs、pipeline.rs、roundtrip.rs | M | T-1+T-3，随 D1/D2（§3.3） |

### C 保留（实为现行功能/安全兜底，非兼容层）

| 项 | 位置 | 理由 |
|---|---|---|
| 未知块类型降级纯文本 | blocks.rs:994-1004 | 数据不丢失兜底，对未来类型与外部导入同样成立（§2.9） |
| ZIP 安全限额 | backup_zip.rs:14-17 | 安全策略，与格式无关（§2.10） |
| MD 源码 Callout 变体归一 | blocks.rs:1049-1063 | 现行 MD 功能解析（§2.7 注） |
| fileId 三份读取的「合一重构」部分 | 同 B 行 | 删冗余实现属重构收益，与兼容存续无关，可独立先行 |

### 建议落码顺序（proven 依赖关系 + inferred 排期）

1. **D1/D2/D3 拍板**（前置一切 B 类收紧动作）。
2. **无依赖先行组**（S，可与在跑各线并行）：种子短程原生化（main.rs，与灯箱线同文件不同区，须错开提交窗口）；fileId 三份合一；gallery 双实现合一；停附件双写。
3. **迁移通道**（M）：旧 ZIP importer + 存量一次性归一（含 D3），测试按 T-3 迁入。
4. **双读/别名收紧组**（S-M）：§2.3、§2.4 读、§2.5 形态、§2.6、§2.7、§2.8、§2.1 依次删，测试按 T-1 切换。
5. **ZIP 转原生**（M，系于 D1）：manifest 建模、avatars 处置、§2.12 归一、导出格式定形。
6. **模型类型化**（L）：extra 透传退役；与批 14 合并为同一工程窗口。

### 与在跑工作的文件冲突面

| 在跑线 | 冲突文件 | 冲突点 |
|---|---|---|
| 灯箱重构 | main.rs、editor.rs、diag.rs | 种子（main.rs:869-931）与灯箱的根色派生同在 main.rs 不同区：可同窗但须分笔、错开提交；editor.rs 别名/双写点（§2.4/2.7/2.8）与灯箱的 editor 改动同文件——灯箱线收尾后再动 editor.rs |
| A-2 流式跨栏 | editor.rs、editor/columns.rs、blocks.rs（渲染臂） | §2.8 别名臂与 §2.5 gallery 渲染同在 blocks.rs 渲染区：A-2 落码期避免同窗改 blocks.rs 渲染 match |
| 批 11 性能 | core model、storage、editor.rs | 与模型类型化（B 最大项）同向：Value/extra 查找正是性能热点口径之一，建议类型化直接挂批 11 的量测框架验证收益 |
| 批 12 产品面 | settings.rs（备份页）、editor/export.rs | D1 拍板决定备份页与导出格式的改动面；§2.4 export 侧 fileId、§2.11 avatars 都在此面，先拍板后落批 12 的备份相关项 |
| 批 14 拆 editor.rs | editor.rs 全量 | 模型类型化与拆分都是 editor.rs 大手术：顺序上先类型化（定接口）后拆分，或拆分时顺带类型化；二者不可并行同窗 |

## 6. 未尽与不确定

- 用户真实存量（IndexedDB/SQLite 内）未做实机扫描：§2.8 的「无 music/code 旧名」只对仓库内夹具 proven；落码前需一次存量扫描（可借 Diag 或迁移通道的 dry-run 统计）。
- 原生端（native/）的 Flutter 遗留代码不在本次盘点范围（其格式镜像属另一条线）。
- probe/smoke 脚本按任务纪律未读；其断言中涉及旧格式的部分（如导出 roundtrip 类）应在第 4/5 步落码时同步复审。

## 7. 落地状态（2026-11-24 更新）

- 第一步（A 类先行）已落：23c24d8 种子原生化、7c96f28 strike 别名读删、0c083d8 callout 只读 calloutType、625b925 附件工厂停写顶层 fileId、391e367 删 avatars 导出强制 {} 互通片。
- 第二步（合一重构）已落：b2627e2 fileId 三份合一、ec77056 gallery 双实现合一、7af690a 待收紧点承接标注。
- 第三步（迁移通道）已落：a189c86 通道本体 core::migrate、07a2a5c 测试+扫描、cfef368 D3 首启迁移、d8b1c81 D2 导入归一。
- **第四步（收紧组）已落（2026-11-24）**，逐项独立成笔：
  - 笔1 `10040ba`：删顶层 fileId 读（§2.4 读侧）——blocks::file_id 只认 attrs.fileId，主线零残留（余 blocks.rs 内两处 .get("fileId") 为 gallery 条目对象形与 attrs 读本身）。
  - 笔2 `9fd0607`：gallery 形态收紧 + 写路径统一（§2.5）——读侧只认 attrs.items 对象形（删裸串解析与 children 兜底）；写侧 GalleryPick/Replace 只产对象形（新增 ensure_gallery_items_form 写前归一）；通道侧 items 归一后全 fileId 载体的 children 清除并计 gallery_children_removed，D3 校验预期节点数同步扣除。
  - 笔3 `cfee099`：heading_level/todo_checked 双读删除（§2.3），只认 attrs。
  - 笔4 `087855c`：Id/Timestamp 单形化（§2.1）——模型改单形 newtype（数字/毫秒解析期拒绝），迁移通道改作用于模型解析前的 Value 级（normalize_value/dry_run_value），backup_zip 新增 read_backup_zip_migrated 为 D2 唯一入口（settings/storage 改用），D3 改 Value 级先行于模型解析；种子/新建/pin 改产字符串 id + ISO 时间戳；测试按 T-2 口径改「归一后等价」对照。
  - 笔5 `ee174af`：music/code 旧名别名删除（§2.8）——渲染臂、打开补拉、has_card 清单各删旧名（has_card 顺带补正 musicCard 原本不在列的缺口）；非别名保留：type_icon 的 meta 来源型 "music"、wiki 源码收集跳过集、行内标记 code、icons 图标键。
- **callout 改名已落（2026-11-25，用户拍板纳入通道）**：`1e21941` 通道侧改名（core::migrate `normalize_callout`，仅作用于 callout 块）——生效值按旧三级回退读链（calloutType → kind → variant，各取字符串值）取首个字符串值，来自旧名时写入 calloutType（计 callout_moved），字符串形旧名一律删除（被影子覆盖计 callout_cleared），非字符串旧名原样保留；D2 导入与 D3 存量归一共用 normalize_value 一处覆盖。`5f0d38b` ZIP 级锁：主线直读不改名、通道改名后旧名零残留、原生导出只出 calloutType。主线代码中文档节点旧名零残留（editor.rs 的 kind 是桥消息 cardPick 判别字段、diag.rs 的 kind 是日志条目字段，均非文档数据）。
- **第五步（manifest 建模 + D1 ZIP 转原生）已落（2026-11-24）**：`dfa1d2e` 一笔（含全部消费点适配，中间态不可编译故不拆笔）。
  - 建模：`core::backup::Manifest` 由无类型透传（`attachments: Option<Value>` + flatten extra）改为类型模型——`attachments: BTreeMap<String, AttachmentMeta>`，`AttachmentMeta` 只有 name / type（JSON 键 `type`）两字段。字段形态三方同形 proven：两份验收包各 17 条目普查全为 {name, type}；原版写入点（src/services/drive.js:86）同形；Rust 编辑器两处写入点（editor.rs 附件/媒体入仓）同形。不臆造 size 等字段（真实形态无此键，旧包若带，在通道按多余键剥离计数）。
  - 通道衔接：`migrate::normalize_manifest_value` 为 manifest 的 Value 级归一（与第四步 memos 侧 Value 级通道同构），`read_backup_zip_migrated` 对 memos 与 manifest 双文件归一、命中合并入同一 MigrationStats（新增三计数 manifest_form_fixes / manifest_entries_dropped / manifest_fields_normalized，摘要键 mform/mdrop/mfield）；主线 `read_backup_zip` 对旧形 manifest 直接拒绝。另有 `migrate::manifest_parse_lenient` 供内部存量字符串（旧版本写下的 storage meta / Web IDB 值）宽容解析。
  - 透传退役：`BackupPackage.manifest_raw` 删除；`write_backup_zip` 改收 `&Manifest`、manifest.json 由模型直出序列化。storage 导入落库改存模型序列化、导出宽容解析后模型直写；Web apply_import 落库改存模型序列化、handle_export 宽容解析后模型直出（IDB kv 键名 `manifest_raw` 沿用，存值语义已变）。§2.12 的 storage 数组回退字符串 `{"version":1,"attachments":[]}` 退役，无存量时回退 `Manifest::default()`（空字典形）。
  - avatars 未动：字段透传与 storage 往返、Web 头像功能数据通道原样保留（用户硬约束）；导出强制 {} 互通片已于第一步（391e367）删除，本步无新增处置。
  - **原生格式与旧格式差异清单（D1 定形）**：
    1. ZIP 容器不变：memos.json + manifest.json + attachments/<id>，安全限额不变（§2.10 C 类保留）。
    2. manifest.json 根级只 `version` + `attachments` 两键（旧：任意根键经 flatten 透传往返保留；新：主线不承载，通道剥离计数）。
    3. attachments 恒为字典形（旧：字典/数组/缺失/任意形均可经透传入库；新：数组形与缺失只在通道归一——数组条目须自带字符串 id 为键、无 id/非对象条目剔除计数）。
    4. 条目恒 {name, type} 字符串两键（旧：任意键透传，如 size 等多余键原样往返；新：通道剥离多余键、缺失/非字符串字段补空串，均计数）。
    5. manifest 往返由模型重组：序列化键序由模型定（根 version→attachments、条目 name→type、附件 id 字典序）（旧：manifest_raw 原文逐字节带回）。
    6. 内部存量同口径原生化：storage meta `manifest_json` 与 Web IDB manifest 值存模型序列化（旧：存导入原文）；旧存量在下一次导入时整体替换、导出时经宽容解析收敛。
    7. memos.json 本步不变：version 2、BackupFile 模型序列化、exportedAt 导出时写入、avatars 透传保留。
  - 往返与回归锁：原生 ZIP 往返逐值等价 + 包内 manifest.json 字节即模型序列化（core tests/backup_zip 新测）；旧形 manifest 主线拒绝/通道归一计数断言（同上）；migrate manifest 归一逐项 + 幂等 + 宽容解析（core tests/migrate 新段）；storage 旧形数组 manifest 全链导入→导出原生形（storage tests/pipeline 新测）；两份验收 ZIP（在位）经通道导入的结果与第四步前一致——pipeline 的 manifest 断言改「原包先经通道归一再深相等」（与 memos 侧同口径），core backup_zip 往返断言改模型相等 + 序列化稳定，全绿。门禁：cargo test --workspace 151 项全过、verify_rustweb ALL PASS。
- **模型类型化（§2.2）本线可落部分已落（2026-11-25）**：`575f10d` BackupFile.exported_at 由 `Option<Value>` 收为 `Option<Timestamp>`（写路径本就只产 ISO；毫秒数形由通道在 normalize_value 根级归一、模型直解拒绝），core 顶层补 Id/Timestamp 再导出。余下 extra 透传（Node 块字段、Memo.layout、BackupFile 根级未知键）的类型化须动 editor.rs/blocks.rs 的全部 `.extra` 消费点，与批 14（拆 editor.rs）同窗合并，不在本线范围；avatars 按用户硬约束保留透传、不建模。门禁：cargo test --workspace 155 项全过、verify_rustweb ALL PASS。
- **模型类型化（§2.2）余部已落（2026-11-25，批 14 落地后同窗执行）**：前置 `7ca734b` 迁移通道补 layout 归一（twoPane→mode、名单过滤、未知键剥离）与已建模字段类型归一（attrs level/checked/fileId/start/href/url/text、节点顶层与备忘级字段的类型换算/剔除，计 fields_normalized/layout_normalized）；`a77f28e` core 模型退役三处 flatten extra——Node 的 attrs 提为类型化 `Attrs`（含 decorative_divider 的 attrs.text）、节点顶层 calloutType/url/status/meta/name/title/caption/image 与行内五标记提为类型字段，Memo 的 layout 提为 `MemoLayout`（left/right 用 Option 保「缺失≠空名单」的旧分界口径）、deletedAt/bgColor 类型化，BackupFile 根级未知键解析即弃；`db6f002` web 全部消费点改走类型口径（set_attr/del_attr 类型化访问层、搜索索引 walk 按旧 walk_value 语义等价收集、种子改类型直构）。**保留透传仅 avatars 一项**（用户硬约束，`Option<Value>` 不建模）；meta 保留 `Option<Value>` 字段承载（卡片 provider 载荷、键集随服务方演进，属已建模字段而非未知键透传）。格式变化点：未知键（根/备忘/节点/attrs 内）不再往返、JSON 键序由模型声明序定、layout 名单为空时不落键；已建模字段的旧形只经 core::migrate 通道归一、主线不双读。口径锁：core tests/model_typing 新增 4 项（旧形归一落位、未知键不往返、主线直读丢弃、通道幂等）。门禁：cargo test --workspace 165 项全过、verify_rustweb ALL PASS、web 警告 43 与批 14 基线持平、`.extra` 残留全仓零。未部署未推送（随主线合流）。
- 去兼容余项：无（§2.2 模型类型化已收官；callout 改名已落，见上）。
