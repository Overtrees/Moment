# SQLite 接入阶段一：构建 spike 报告

范围：按 `audit_sqlite_integration.md` 路线 ①′（rusqlite 0.40 +
ffi-sqlite-wasm-rs + SAHPool VFS + Dedicated Worker）验证「能构建、
能跑、能落盘」。不做业务切换。全部数字为实测，环境为本机 VM
（1.5 共享 CPU，构建时长按上限看）与 Simular Box Chromium
（headless shell 1255）。结论分级沿用评估报告：proven / inferred。

## 验收逐项结果

| # | 口径 | 结果 |
|---|---|---|
| 1 | 构建通（storage 升 0.40、cfg 分离、web 链编出含 SQLite 的 wasm） | ✅ 通过，数字见 §1 |
| 2 | Worker 内跑通（SAHPool 开库/建表/写入/查询/FTS5 trigram 中文检索） | ✅ 通过，box 实测见 §2 |
| 3 | 落盘持久（reload + 第二页核验终态） | ✅ 通过，落点与独占行为见 §3 |
| 4 | 兼容面清单 | §4（9 项冲突/注意点，均给阶段二处置判断） |
| 5 | 原生面不破（cargo test --workspace） | ✅ 165 passed / 0 failed（15 套件） |

## 1. 构建

- `crates/storage`：rusqlite 0.32 → **0.40.2**，依赖按 cfg 分离——
  原生 `bundled`、wasm32-unknown-unknown 走 `ffi-sqlite-wasm-rs`。
  storage 的 lib.rs **零 API 改动**即编译通过。
- 额外实证：`cargo check -p mynote-storage --target wasm32-unknown-unknown`
  通过——storage crate 本身已能对着 wasm 后端编译（仅 check 级；
  Store 在 Worker 内的端到端运行未验，见 §4-g）。
- spike 本体（独立 crate `rust/apps/sqlite-spike`，不在主 workspace
  members 内）以与主线相同的链构建：`cargo build --release
  --target wasm32-unknown-unknown` + `wasm-bindgen --target web`。
- **新增工具链依赖：clang**（sqlite-wasm-rs 的 build.rs 以 clang 编
  SQLite amalgamation；不需要 emscripten）。本机 clang 18 已在位；
  **box 无 clang（实测）**，阶段二前须给 box/CI 构建环境装 clang。
- 版本配对（踩过并锁定，阶段二不得随意升）：
  rusqlite 0.40.x 钉 sqlite-wasm-rs **0.5.x**；sqlite-wasm-vfs 必须
  **0.2.x**（0.3 配 0.6.x，混用会引入第二份 SQLite）。0.5.x 无
  `wasm-bindgen` feature（该依赖为必备、WasmOsCallback 无条件导出）；
  vfs 0.2 无 feature 划分，安装函数为 `sahpool::install`、返回
  `OpfsSAHPoolUtil`（非 Sync，须 thread_local 保活）。
- FTS5：sqlite-wasm-rs 0.5.5 的 build.rs 默认旗标含
  `-DSQLITE_ENABLE_FTS5`，无需额外旗标（源码实证 + §2 运行实证）。
- 构建时长（本机节流环境，冷构建）：spike 全冷（含 SQLite C 编译）
  约 505 s；增量重编约 5 s；fat-LTO 变体另约 270 s。
- **体积**（bindgen 产物实测）：

  | 产物 | raw | gzip -9 |
  |---|---|---|
  | spike（含 SQLite，strip、无 LTO） | 1,678,202 B | 657,793 B |
  | spike（同壳基线，feature sqlite=off） | 30,852 B | 12,324 B |
  | spike（含 SQLite，fat-LTO + 单 CGU，主线同 profile） | 1,645,813 B | 654,139 B |
  | 现行应用 wasm（生产 518f101dcf） | 4,000,605 B | 1,274,736 B |

  SQLite 增量 ≈ **raw +1.61 MB / gzip +0.64 MB**；据此推算应用 wasm
  约 5.65 MB raw / 1.92 MB gzip。评估报告此前 inferred 的 +0.8 MB
  偏乐观约一倍，以本实测为准。注：现行链与 spike 均未跑 wasm-opt。

## 2. Worker 内跑通（box Chromium 实测，探针 ALL PASS）

- 形态：module 型 Dedicated Worker 加载 spike wasm，主线程经
  postMessage 桥调用（与阶段二桥形态一致）。静态服务**刻意不下发
  COOP/COEP**，SAHPool 免头口径成立。
- `sahpool::install`（默认配置、设为默认 VFS）→ rusqlite
  `Connection::open("spike.db")` → 建表 + 两行写入 + 全量查询 →
  FTS5 trigram 虚拟表 `MATCH '"文检索"'` 精确命中中文行、
  不命中对照行。引擎版本 **SQLite 3.53.0**。
- 新 profile 首读：库不存在、零行（读路径不建表、无副作用）。

## 3. 落盘持久（box 实测）

- OPFS 落点：`/.opfs-sahpool/.opaque/<哈希名>` 池文件（默认配置的
  目录与 opaque 命名）；写入两行后主池文件 61,440 B、另五个
  4,096 B 池文件。
- 整页 reload 后：count=2、正文逐字一致。同 context 第二页在
  第一页关闭后可读回（FTS 命中），句柄释放实测约 61 ms。
- **独占实证**：第一页 Worker 存活时第二页 install 直接失败
  （原文 `sahpool install failed: An error occurred while creating
  sync access handle`）——SAHPool 单连接独占为活体事实，非文档推断。

## 4. 兼容面清单（阶段二处置判断）

a. **构建链**：主线 build.sh 是纯 Rust 链；接入后新增 clang 依赖，
   本机有、box 无（实测）、GitHub 托管 runner 自带。处置：阶段二
   开工前给 box 装 clang 并在 build.sh 加 clang 在位检查；三件套
   版本按 §1 配对锁进 Cargo.lock，不得单独升 rusqlite。
b. **sw.js 缓存口径**：现行缓存名 = 应用 wasm 的 md5 戳，install
   时缓存 CORE 清单。处置：Worker 的 JS/wasm/glue 必须进 CORE 清单
   并随同一戳换代，否则会出现新应用配旧 Worker（或离线 404）；
   Worker 资产用带戳命名，避开 SW fetch 的运行时缓存混代。
c. **COOP/COEP**：仓库无 `_headers`、生产未下发这两头（实测代码面）。
   SAHPool 不需要，维持现状；**不得**改用 opfs VFS（需 COOP/COEP，
   且会波及天气/封面等跨源面）。
d. **救援层**：内联救援层只读 IDB/LS，读不了 OPFS 池文件（opaque
   哈希名、池格式）。处置：迁移期 IDB 副本仍是可读回退；阶段三按
   评估报告给救援层加「导出 OPFS 原始池文件」字节直拷入口。
e. **Dioxus 构建方式**：现行链无 Worker 先例（全仓无 `new Worker`）。
   处置：阶段二须在 build.sh 新增 Worker crate 的构建/bindgen/拷贝
   步骤；Worker 拓扑（独立 crate vs 同 crate 双 bin）阶段二定，
   spike 的独立 crate 形态仅为脚手架。
f. **多标签独占**：见 §3 独占实证——相对现行 IDB 多标签无碍是行为
   回退。处置：阶段二必须设计多标签口径（互斥提示或
   BroadcastChannel 选主），不得默认滑过。
g. **storage 的 wasm 运行时未验面**：check 通过 ≠ 运行通过。
   Store::open 的路径参数在 SAHPool 下是池内名而非文件路径；
   storage 依赖的 chrono `clock` 在 wasm32-unknown-unknown 的
   时间来源行为未实测。处置：阶段二第一件事是在 Worker 内用
   mynote-storage 的 Store 本体（而非裸 rusqlite）跑一遍
   导入/保存/检索，覆盖此面。
h. **体积与首载**：增量 gzip +0.64 MB 落在 Worker 资产上，可与主
   wasm 分开缓存/按需加载，首屏主包不必然同步变大；但应用启动即
   需存储，实际收益有限，按 +0.64 MB 常驻增量做预算。
i. **真机未验**：本 spike 只在 box Chromium 验过；iOS Safari 的
   OPFS SAH（Dedicated Worker 内）在真机的行为未验。处置：阶段二
   业务切换前，必须把同一探针在用户 iPhone Safari 上跑一轮作为
   门禁（评估报告阶段一验收原含真机一轮，本任务无设备通道，
   如实顺延为阶段二前置）。

## 5. 原生面

- `cargo test --workspace`（worktree 内）：**165 passed / 0 failed**，
  与升级前基线一致，含 storage 的真实夹具往返套件（导入/导出/
  检索）。升级前基线（0.32）同样全绿。

## 阶段二开工前置条件

1. box/CI 构建环境装 clang；build.sh 加 clang 检查与 Worker 构建段。
2. 本报告 §1 的版本配对表锁入 Cargo.lock 并在 storage 的
   Cargo.toml 注释中留档（已留）。
3. 真机 Safari 跑通同一 spike 探针（§4-i）。
4. 多标签口径先定案（§4-f）。
5. Worker 内 Store 本体端到端验证（§4-g）作为阶段二第一里程碑。

## 脚手架处置

`rust/apps/sqlite-spike/` 全部为阶段二丢弃的脚手架：lib.rs 的
spike_write/spike_read 导出、web/ 页面与 worker.js、probe_spike.mjs、
build.sh。可沿用的只有形态与结论：storage 的 cfg 分离（**非脚手架，
是阶段二地基，可先行合入主线**）、Worker RPC 桥形状、install 句柄
thread_local 保活、探针的独占/落盘核验手法。
