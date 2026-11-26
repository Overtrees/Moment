# Mynote Web 端接入 SQLite 可行性评估

评估范围：现行 Web 持久层（IndexedDB）替换为 SQLite 的收益、路线、迁移与风险。只评估，未改任何代码。结论分级：proven = 有代码/实测/官方文档直接支撑；inferred = 基于已证事实的推断。

## 0. 现行形态（基线事实，均为 proven）

- Web 持久层 `rust/apps/web/src/idb.rs`：IndexedDB 库 `mynote-web`，kv 店存 `memos_json`（整个 BackupFile 序列化为一个 JSON 字符串）与 `manifest_raw`；attachments 店存 id → 字节。
- 加载（`rust/apps/web/src/main.rs` 启动效应，约 1454 行起）：`load_state()` 全量读出 memos_json 字符串 → `serde_json` 解析为 Value → 每次加载先经 migrate 通道归一（validate-then-swap，不看完成标记）→ 严格解析为 BackupFile → 整库克隆进应用信号。即：**整库常驻内存是现行应用架构的前提，与持久层选型无关**。
- 保存（`rust/apps/web/src/editor/dispatch.rs` `save_backup`）：每次编辑持久化都把**整个 BackupFile 重新序列化**为 JSON，再以单个 kv put 全量写回（`idb::save_memos`）。未见防抖合并（persist 调用点分布于 editor/dispatch.rs、editor/cards.rs，逐操作触发）。删除/软删路径（main.rs 约 1135、1165 行）同样全量序列化 + 全量写回。
- 导入落库（`idb::save_all`，由 settings.rs 约 790 行调用）：memos put、manifest put、attachments 的 clear+逐个 put 是**三个独立事务**顺序 await。
- 搜索（`rust/apps/web/src/list.rs:773` `matches_search` + `main.rs:1616`）：查询变化触发列表重算，对每篇备忘现场构造全小写检索文本（`search_text`，拼接标题/正文/卡片字段）后做子串 contains。无索引、无缓存；重算已 memo 化到 data/query 两信号（main.rs 约 1603 行注释与 PERF 打点），但单次重算成本仍与全库文本量成正比。
- 现成 SQLite 层 `rust/crates/storage`：rusqlite 0.32 bundled + FTS5 trigram；schema 为 memos（原样 JSON + 索引列）、attachments（BLOB）、meta、memos_fts；导入为 core 校验后单事务全量替换（lib.rs `import_backup`）；检索 ≥3 字符走 FTS5 短语查询、短查询回退 LIKE（lib.rs `search`）。该 crate 无任何下游依赖，Web 与原生端都未用它跑生产（proven：全仓 Cargo.toml 依赖检索仅自身声明）。
- 数据规模：种子 6 篇；真实库 JSON 约 5.46 MB 量级（历史真实夹具体积，附件另计）；storage 层自身注释记录的量测口径为 1000 篇导入约 40 ms（lib.rs `insert_memo` 注释，Lane T 实测）。现行应用 wasm 4,000,605 B（dist 实测，约 4.0 MB）。

## 1. 收益面

### 1.1 启动加载

现行构成：IDB 读一个约 5.46 MB 字符串（proven：单值存储）→ 两轮 JSON 解析（先 Value 后模型）+ migrate 归一 → 整库克隆。成本主体是解析与归一，随库体积线性增长；当前量级下尚无用户可感的启动抱怨记录，且加载失败有明确 Diag 行与失败态（proven：main.rs 加载效应）。

接入 SQLite 后的变化（inferred）：若应用架构不变（仍整库读出进信号），加载变成逐行取 memo_json 再逐篇解析，总量相同、还多一层引擎开销，**无实质改善**。只有把应用改成「列表只查索引列、正文按需取」时启动才真正变快——那是应用层改造，不是换持久层的自然结果。

### 1.2 保存写放大（现行最实的成本，proven）

每次编辑保存 = 全库序列化 + 全量写回。以约 5.46 MB 的库计，单次保存约 5.46 MB 的 CPU 序列化（主线程）+ 同量级 IDB 写入；高频编辑时按操作次数线性放大。SQLite 路线下保存可降为单行 UPDATE（memo_json + 索引列 + FTS 行），写放大基本消除——**这是接入 SQLite 唯一立竿见影的收益项**。但注意第 4 节路线 ④：同样的增量保存用 IDB 分条存储也能实现，不必引入 SQLite 才能拿到。

### 1.3 搜索

现行：每次查询变化对全库逐篇构造小写文本再子串扫，O（全库文本量）。当前量级（数百篇）下重算有 PERF 打点可回溯，尚无实测超标记录（proven：打点存在；inferred：当前量级可接受）。FTS5 trigram 的优势在库达数千篇/数十 MB 文本后才显著，且语义等价（storage 层已按现行子串语义对齐，短查询回退 LIKE）。**当前规模下搜索不是接入理由。**

### 1.4 跨店原子性缺口（真实存在，但根源是代码而非 IDB）

`save_all` 三事务顺序提交（proven，见 §0）。导入中途杀页/断电的窗口：

- memos 已换新、attachments 未换：新备忘引用的附件 id 不存在 → 图片/附件显示破损，直至重新导入（数据本体在备份包里可恢复，但盘上状态不一致）。
- attachments 已 clear、逐个 put 未完：该事务自身是原子的（clear 与 puts 同属一个 IDB 事务，未提交即回滚），故附件店不会半残；不一致只发生在**跨店之间**。

关键事实（proven）：IndexedDB 原生支持多对象店单事务，现行代码只是没有用。若把 `save_all` 改为一个横跨 kv + attachments 的单事务，导入原子性缺口即在现行栈内关闭。编辑保存 `save_memos` 本就是单 put、单事务，无此问题。**原子性不构成换 SQLite 的理由，只构成一次小改的理由。**

### 1.5 收益小结

| 项 | 接入后 | 判定 |
|---|---|---|
| 启动加载 | 架构不变则无感 | 无收益 |
| 保存写放大 | 全量 → 单行 | 实质收益，但路线 ④ 同样可得 |
| 搜索 | 当前规模无感，数千篇后显著 | 远期收益 |
| 导入原子性 | 单事务天然成立 | 收益，但 IDB 单事务小改即可得 |
| 数据校验/约束 | schema + 事务 | 边际收益 |

## 2. 路线面

### 路线 ① rusqlite 直编 wasm32（现行 0.32 bundled 原样）

不可行（proven）：bundled 经 cc 编译 SQLite C 源码，wasm32-unknown-unknown 缺标准 C 库头（stdio.h 等）与链接工具链，社区多年记录均为构建失败，需打补丁分支或 wasi-sdk 绕行。现行 storage 钉 rusqlite 0.32，此路不通。

### 路线 ①′ rusqlite 升级 + sqlite-wasm-rs（①的现代形态）

可行但工程量最大（proven 部分）：sqlite-wasm-rs 提供 wasm32 的 SQLite FFI 与 VFS 实现（memory / OPFS SAHPool / relaxed-idb），rusqlite 自 0.40 起以 `ffi-sqlite-wasm-rs` feature 官方集成该后端；该 feature 在 0.32–0.39 均不存在，故须先把 rusqlite 0.32 → 0.40（storage 的 API 面很小，升级本身可控）。硬约束：

- OPFS 同步访问句柄只存在于 Dedicated Worker（proven：平台规范与 sqlite 官方文档一致）→ SQLite 连接必须住在 Worker 里，Dioxus 主线程的全部存储调用要改走异步 RPC 桥。现行 idb.rs 是主线程 async 直调，改造面覆盖加载、保存、导入、导出、附件读写全部调用点。
- 构建链新增 wasm-capable clang 要求（cc 编译 SQLite amalgamation），build.sh（现为 cargo + wasm-bindgen 的纯 Rust 链）要引入 clang/lld 环境依赖，CI 与 box 构建环境同步改造。
- 包体积（inferred）：SQLite amalgamation 编入应用 wasm，按官方独立 sqlite3.wasm 约 850 KB 原始体积（见路线 ②）同量级估算，应用 wasm 约 4.0 MB → 4.8 MB 上下（gzip 约 +340–400 KB）。
- 收益：唯一能复用 crates/storage 现成代码与 FTS5 schema 的路线；与未来原生端共用同一存储层的战略价值也只在这条路线上成立。

### 路线 ② 官方 sqlite3 wasm（JS 构建）+ Rust 桥

引擎成熟（proven）：SQLite 官方 `@sqlite.org/sqlite-wasm`，含 FTS5；sqlite3.wasm 约 844–900 KB 原始、约 341–406 KB gzip（多方实测，见出处）。持久化两 VFS：

- `opfs` VFS：需 SharedArrayBuffer → 服务端必须下发 COOP/COEP 头。现行托管 Cloudflare Pages 可经 `_headers` 配置，但 require-corp 会波及跨源资源加载（天气接口、外部封面图等现行跨源面需逐项核），且 Safari <17 与该 VFS 不兼容（官方文档明示的子 worker 缺陷）。
- `opfs-sahpool` VFS：不需要 COOP/COEP，官方推荐给无法设头的场景；代价是单连接独占——第二个标签页打开同库直接失败，与现行「多标签无碍」的形态是行为回退，需另做多标签互斥提示。
- 两者都只能在 Worker 内开库（同路线 ①′ 的 Worker 约束）。
- 桥接成本（inferred）：crates/storage 的 Rust 代码完全用不上，存储逻辑要在 JS 侧或 wasm-bindgen 桥上重写一遍，等于新写一个存储层并长期维护双实现（原生端仍是 rusqlite）。成熟度高的是引擎、不是这条集成路径。

Safari 支持实情（proven，sqlite.org 官方 persistence 文档）：OPFS 所需 API 齐备的门槛为 Safari 16.4+（SAHPool 与 WASMFS 路线）；OPFS VFS 本体需 Safari 17+。用户设备 iPhone 15 Pro / iOS 27 远超门槛，**设备兼容不是问题**；普通标签页与主屏幕 PWA 均可开 OPFS（安全上下文 + Worker 前提下）。

### 路线 ③ rusqlite 经 OPFS VFS / SAHPool 的持久化形态

即路线 ①′ 的存储后端细节（proven）：SAHPool 把库文件存进 OPFS 的预分配文件池，同步句柄独占，同路线 ② 的单连接约束；relaxed-idb VFS 把页存回 IndexedDB，可避开 OPFS 的 Worker 独占问题的一部分，但性能与成熟度低于 SAHPool，且「SQLite on IDB」叠床架屋。WAL 在 OPFS 上受同步句柄模型限制，一般用 rollback journal 模式。此路线无独立成立性，并入 ①′ 评估。

### 路线 ④ 维持 IDB、改增量/分片（对照基线）

- `save_all` 改多店单事务 → 导入原子性关闭（小改，见 §1.4）。
- memos 由单字符串改分条存储（新对象店按 memo id 存单篇 JSON）：编辑保存只写变化的一篇，写放大从全库降到单篇；加载仍全量读出拼装（多一次遍历，量级不变）。
- 搜索维持内存扫，或在内存侧给检索文本加缓存（按 memo id + updated_at 失效），把每次重算降为增量。
- 成本（inferred）：数天内的小改量级，无新平台依赖、无 Worker 化、无包体积变化、无迁移风险（分条化本身需一次盘上格式迁移，但同在 IDB 内、旧值可保留回退）。收益覆盖 §1 中除「数千篇搜索」外的全部实质项。

## 3. 迁移面

若走 SQLite（路线 ①′），一次性迁移设计（沿用既有红线口径）：

1. 启动时检测：IDB 有存量且 SQLite 侧无「迁移完成」标记 → 进入迁移。
2. 读 IDB 全量 → 走现行同一条校验链（migrate 归一 + 严格解析，validate-then-swap 的校验半段现成）→ 在 Worker 内建库、单事务写入 → 回读校验（篇数、附件数、抽样 id 集合与逐篇 JSON 哈希比对）。
3. 校验全过才写完成标记并切换读路径；任一步失败：标记不写、继续用 IDB、Diag 记 MIGRATE-SQLITE 结果行（失败原因），下次启动重试。**旧 IDB 库不删**，至少保留到后续数个版本周期，作为回退与抢救源；救援面板增加「导出旧库 JSON」入口的成本很低（救援层是纯 JS、直读 IDB 正是其现行能力）。
4. 红线相容性：现行红线是「每次加载先 migrate 归一后严格解析」。storage crate 现只在导入时归一，**没有加载期归一**。接 SQLite 后须二选一并写进设计：(a) 加载时仍逐篇过归一（保留红线，加载成本部分回来）；(b) 归一只在写入路径（导入/迁移/保存）发生 + schema 版本戳，未归一版本开库即先整库归一再用。推荐 (b)，但这改变了红线的执行点，须作为显式决策记录，不可默认滑过。

附件存放取舍：

- 入 SQLite BLOB（storage crate 现行设计）：单文件一致性最好、事务与备忘同体；代价是库文件随附件膨胀、SAHPool 池文件管理与备份导出都要整库过一遍，且大附件读写都经 Worker 桥。
- 维持文件式（OPFS 按 id 存文件，或干脆留 IDB attachments 店）：库体小、附件读写可直读；代价是跨后端一致性又回到多事务问题（但附件与备忘的引用关系是单向 id 引用，容忍最终一致 + 打开时缺附件降级显示，现行已有缺附件降级面）。
- 倾向（inferred）：附件留文件式（OPFS 文件与 SQLite 同源存储、同一驱逐命运），备忘与清单入 SQLite。storage crate 的 BLOB 设计是为原生端单文件便携服务的，Web 端不必照搬。

## 4. 风险面

- **存储驱逐：换 OPFS 不改变命运（proven）**。Safari/ITP 的 7 天规则针对全部 script-writable storage：IndexedDB、localStorage、Cache、SW 注册都在清除名单内，OPFS 与 IDB 同属一个源的统一存储池、同一驱逐与配额体系（Safari 持久化标记为 no-op）。主屏幕 PWA 有自己的用量计数、豁免该清扫——这一条对 IDB 与 OPFS 同等成立。sqlite 官方文档亦专列「数据库神秘消失」一节讲 OPFS 驱逐。结论：**防丢靠备份导出与主屏幕安装引导，不靠换存储后端**；接入 SQLite 在此项零收益、也零新增风险。
- **损坏形态**：现行 memos_json 是单个字符串，坏了也是整库级事件，但它是纯文本——人工打开即可抢救、截断可部分恢复、救援层 JS 可直读并导出。SQLite 是单二进制文件，页级损坏可经 integrity_check 定位、`.recover` 类工具抢救，但救援层（不依赖应用 wasm 的内联 JS）**读不了 SQLite 文件**，应用起不来时盘上数据对现有救援通道不可见。缓解：迁移期保留 IDB 副本（§3.3）+ 救援层加「导出 SQLite 原文件」按钮（字节直拷，可离线用桌面工具抢救）——可做，但都是新增面。
- **可观测性**：现行加载/保存全程有 Diag 行（IDB/APP/EDIT 标签、字节数、parse err 原文）。SQLite 路线下错误来自 Worker 内的 rusqlite 错误，需经桥回传再打点；Worker 本身起不来（clang 构建产物与浏览器兼容问题）会是新的故障类。Diag 体系可覆盖，但要专门设计，不免费。
- **多标签**：SAHPool 单连接独占 vs 现行 IDB 多标签并行——行为回退（见路线 ②/①′），对单设备个人应用影响小，但属用户可感变化，接入时须明示。
- **构建与体积**：wasm 约 +0.8 MB 原始（inferred），且构建链引入 clang 依赖后，本机/box/CI 三处环境都要维护——现行纯 Rust 链的简单性会打折。

## 5. 结论

**推荐：现阶段不接 SQLite；先落路线 ④ 的两项小改（save_all 多店单事务、分条增量保存），把已证的实质成本在现行栈内消掉。**（综合 proven 收益表与路线成本的判断）

理由收束：当前规模（约 5.46 MB JSON、数百篇量级）下，SQLite 的四项名义收益里，启动与搜索无感、原子性与写放大用 IDB 自身能力即可拿到；真正只有 SQLite 能给的（FTS5 索引化搜索、单行级事务粒度、与原生端共用存储层）都指向「规模上台阶」或「原生端落地」两个尚未发生的条件。反之接入成本是结构性的：Worker 化存储、rusqlite 大版本升级、构建链引 clang、救援通道重做、多标签行为回退——为无感收益付结构成本，不划算。

若将来接，路线定为 ①′（rusqlite 0.40 + sqlite-wasm-rs SAHPool、附件留 OPFS 文件式），分阶段：

1. 阶段一（中量级，约 1–2 周量级）：storage 升级 rusqlite 0.40 并打通 wasm 构建 spike（Worker 内开库、SAHPool 落盘、box + 真机 Safari 各验一轮），验收 = spike 页可建库/重启可读/FTS 查询与现行语义对照一致。
2. 阶段二（中量级）：Web 持久层改走 Worker 桥（加载/保存/导入/导出/附件），IDB 保留为迁移源与回退；验收 = 全量探针绿 + §3 迁移演练（造存量 → 迁移 → 逐篇哈希一致 → 断电式中断重试不丢）。
3. 阶段三（小量级）：观察期（Diag 双写对账：两后端篇数/哈希定期比对打点），稳定后删 IDB 读路径，救援层补 SQLite 原文件导出。

**重估触发线（任一命中即重开本评估）**：

- 备忘库 JSON 体积 > 20 MB，或篇数 > 2000；
- 真机 Diag 的 PERF 行显示列表重算（含搜索）常态 > 50 ms，或保存序列化在真机出现可感卡顿记录；
- 附件总量 > 200 MB（分条/文件式管理的边际开始反转）；
- 原生端（iOS）正式落地并要求与 Web 共用同一存储层与 FTS 语义；
- 路线 ④ 落地后仍出现写放大或原子性相关的真实故障。

## 出处

- 代码：`rust/apps/web/src/idb.rs`（全文）、`rust/apps/web/src/main.rs`（加载效应约 1454 行、列表重算约 1603–1628 行、删除路径约 1135/1165 行）、`rust/apps/web/src/editor/dispatch.rs`（save_backup/build_backup）、`rust/apps/web/src/list.rs:773`、`rust/crates/storage/src/lib.rs` 与 `rust/crates/storage/Cargo.toml:9`、`rust/apps/web/build.sh`、dist 实测 wasm 4,000,605 B。
- sqlite.org 官方《Persistent Storage Options》（sqlite.org/wasm/doc/trunk/persistence.md）：OPFS 仅 Worker、OPFS VFS 需 COOP/COEP、Safari <17 不兼容 OPFS VFS、SAHPool 为无头场景推荐、浏览器 API 门槛 Safari 16.4+、数据库驱逐专节。
- rusqlite wasm 集成现状：rusqlite 文档（0.40 的 wasm32 支持与 ffi 路径）与 sqlite-wasm-rs 集成记录（`ffi-sqlite-wasm-rs` 仅存在于 rusqlite 0.40.x、0.32–0.39 缺失；bundled 直编 wasm 的 C 工具链障碍）。
- 体积实测：官方 sqlite3.wasm 约 341 KB brotli / 393 KB gzip（3.53.4-build2 实测），另一口径约 406 KB gzip（3.54.1）；独立文件约 844–900 KB。
- Safari 存储政策：WebKit ITP 7 天 script-writable storage 清除（IndexedDB/localStorage/Cache/SW 均在名单）、主屏幕 Web 应用豁免且独立计数、Safari 持久化标记 no-op、IDB 与 OPFS 同源统一存储池。
