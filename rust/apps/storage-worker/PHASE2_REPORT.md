# SQLite 接入阶段二报告：Worker 桥切换 + 迁移演练

分支 `sqlite-phase2`（基点 sqlite-spike）。本阶段做到
「可切换、已演练」：默认构建行为不变，`MYNOTE_SQLITE=1`
构建即切换到 SQLite 后端；**不切生产、不部署**。

## 1. 桥口径表（idb.rs 消费面 → persist 门面 → sqlite 落点）

| 消费面（调用点） | persist 函数 | sqlite 模式落点 | IDB 模式 |
|---|---|---|---|
| main.rs 启动加载 | load_state | Worker `load_all`（迁移编排后） | idb 直读 |
| editor/dispatch.rs 保存、main.rs 删除/收敛写回 ×4 | save_memos | Worker `save_sync`（逐篇哈希差量） | idb 全量写 |
| settings.rs 导入落库 | save_all | Worker `import_library` + IDB 全量镜像（含附件替换） | idb save_all |
| dispatch.rs / ops.rs 清单更新 | save_manifest | Worker `save_manifest`（meta） | idb kv 写 |
| dispatch.rs / ops.rs 附件写入 | put_attachment | IDB attachments 店 | 同左 |
| blocks.rs / list.rs / export.rs 附件读 | get_attachment | IDB attachments 店 | 同左 |
| settings.rs 导出 | get_all_attachments | IDB attachments 店 | 同左 |
| blocks.rs / list.rs blob URL | （不经门面）idb::blob_url* | 纯主线程 helper | 同左 |

RPC 命令面（storage-worker）：init / migration_status /
migrate / load_all / save_sync / import_library /
save_manifest / search / bench_import_zip / stats。结果以
JSON 字符串过桥（大整数哈希以字符串传，防 f64 精度丢失）。

**附件决策：留 IDB attachments 店（文件式）**，不入
SQLite BLOB。理由：引用为单向 id 引用、缺附件已有降级
面、读路径（blob URL 构造）在主线程与 IDB 同步性契合；
Store 的 attachments 表保留给原生口径，Web 桥不用
（import 时 store_attachments=false）。救援层原文件导出
面（IDB/LS）由此不受影响。

## 2. 迁移器（方案 (b)：写路径归一 + 版本戳）

- 落点：Worker `migrate` 命令。入参 = IDB 原始
  memos_json + manifest_raw。
- 纪律（与主线程 run_stock_migration 同校验口径）：
  Value 层过 core::migrate 归一通道 → 节点守恒校验
  （归一后节点数 = 归一前 − gallery 影子 children 清除数）
  与篇数守恒校验 → 严格解析 BackupFile → 单事务
  replace_library 换库 + migration_stamp（源/篇数/聚合
  哈希/时刻）→ 回读 memo_hashes 与源侧逐篇 FNV-1a 64
  哈希聚合对账，全等才算成功。
- 失败/中断：任一步失败整笔放弃；Worker 从不写 IDB，
  IDB 原库完好；重跑 migrate 即续演练（幂等）。
- 开库半段：init 时 Store::renormalize_library 按
  NORMALIZE_VERSION 戳检查，过期整库重归一（差量写回）。
- 门面编排（persist::load_state，sqlite 模式）：等待独占
  → 查迁移戳 → IDB 有存量则 migrate → 成功后把归一形态
  收敛镜像写回 IDB kv（IDB 副本保持有效回退面，与 IDB
  模式加载期收敛写回同口径）+ Diag 发 `MIGRATE d3 {摘要}`
  与 census 行（同一通道同一 boot 的归一事件，两后端下
  probe_load_stock 的 MIGRATE 断言同口径成立）→ load_all
  返回。Worker 硬失败（非独占）回退 IDB 直读保可用，
  Diag 记 SQLITE init failed。
- Diag 结果行（SQLITE 标签）：migrate ok（篇数/哈希/
  IDB 附件数/毫秒）、load source=sqlite、idb mirror
  converged、save_sync（upserted/deleted/unchanged/毫秒）、
  import_library ok、独占与接管行（见 §4）。

## 3. 演练数字（box，Chromium 口径；探针
tools/sqlite_bench/probe_sqlite_phase2.mjs，五段 27 项
断言 ALL PASS，终跑两遍一致）

夹具：302 篇 / memos_json 4,985,700 B（含整数时间戳、
callout 别名两篇旧形态、唯一检索词一篇、附件 2 个）。

- S1 Worker 直调：备份 zip 导入 258–364 ms（302 篇，
  归一变更 2 项与夹具旧形态数一致）；FTS 检索「鹭江
  夜泊」2–3 ms、命中恰 1 篇（fixture-137）。
- S2 中断重入：migrate 发出 30 ms 后强杀 Worker——同
  步事务在 terminate 生效前整笔跑完，终态为「已提交」
  极（戳在、聚合哈希 8150782089912133320 与重跑逐字
  一致）；同刻强杀（发出即终止）同落已提交极。两极
  （全提交/全未提交）不变量成立，无部分提交；重跑
  migrate 431–557 ms 幂等成功。进程级中途死亡的回滚
  由 SQLite 事务日志保证、S5 应用级关页续跑旁证。
- S3 应用冷启迁移：IDB 播种后首启（含迁移）至列表呈
  现 1,162–1,583 ms（box 无头 Chromium，含 wasm 加
  载）；Diag 四行齐全（migrate ok / MIGRATE d3 摘要
  millis_ts=2 / 收敛镜像 / load source=sqlite）；IDB
  收敛写回核验 302 篇全字符串形、附件 2 个完好；应
  用内检索唯一词恰中第 137 篇；二启不再迁移、加载
  源仍 sqlite。迁移本身（Worker 内）约 0.45 s。
- S5 应用级中断：首启 250 ms 关页 → 重开迁移完成、
  列表可用、迁移至多一行（无重复迁移）、IDB 副本完
  好（302 篇 + 2 附件）。
- 迁移对账：篇数 302 = 302；逐篇 FNV-1a 64 哈希聚合
  8150782089912133320，源侧与回读侧全等；归一摘要
  memos=302 nodes=7804 millis_ts=2 callout 移动 1
  （census：heading=300 paragraph=3601 callout=1）。

读写主路径对照（与 IDB 基线行为）：打开/编辑/预览/
撤销/合并持久化由 smoke-rustweb-blocks 在 sqlite 构
建上 45 项行为断言全过（见下回归子集）；编辑保存的
差量口径由 storage 原生测试 sync_library 五项锁
（upserted/deleted/unchanged 计数）。

回归子集（box）：
- probe_load_stock（WebKit）：ALL PASS（21 项）——
  sqlite 构建下 boot1 MIGRATE 断言经 persist 同口径
  发行成立、boot2 幂等成立。
- probe_click_dead（WebKit）：ALL PASS（21 项）。
- smoke-rustweb-list：sqlite 与默认构建均 ERRORS:
  none。
- smoke-rustweb-blocks：默认构建 ERRORS: none（全
  绿）；sqlite 构建 45 项行为断言全过、2 项红——
  「S3 normalize: bool block saved as single literal
  text node / literal text carries all marks + link」
  两项经 readS3Doc 直读 IDB kv 断言编辑保存后的落
  盘形；sqlite 后端下编辑保存只写 SQLite、IDB 为迁
  移/导入时刻的回退镜像，故读到导入时形态。此为探
  针与旧后端的耦合面、非应用行为差异（同段的应用内
  断言：打开归一、源码编辑、输入回收、重开持久化全
  过）；让其转绿须编辑保存全量双写 IDB，即阶段三双
  写对账的范围，阶段二不越界（见 §8）。
- probe_state_resilience：本分支基点早于该探针落地
  （主线并行线产物），不在本阶段子集内；阶段三前合
  流后补跑（其 S7 逐篇隔离口径与迁移源形态相关）。

## 4. 多标签独占+提示（用户拍板口径）

- 呈现：**应用内呈现**（非外壳层）。理由：提示须带「立
  即重试」交互且与接管闭环（轮询标记清除即消失）在应用
  状态内完成；外壳层无应用状态通道。文案入五语言包
  （storage.occupied_title / occupied_sub / retry），
  呈现复用三态空状态组件 + 玻璃覆盖层口径
  （.storage-blocked，panels.css，--glass-overlay-*）。
- 机制：persist 等待循环——init 返回 occupied → 置
  OCCUPIED 标记（App 500ms 轮询出覆盖层）→ 每 2s 重试
  init，「立即重试」按钮经 nudge 标记提前唤醒；第二标
  签全程不发任何写命令（load_state 不返回、应用不挂载
  数据面）。第一标签关闭（SAHPool 句柄释放，spike 实测
  约 61ms）后下一轮重试即接管，Diag 记
  `SQLITE takeover ok after N retries`；检出独占时记
  warn 行 `SQLITE storage occupied by another tab`。

box 实测（演练 S4）：第二标签打开后 .storage-blocked
覆盖层出现、文案为五包口径「已在另一标签页打开」、
Diag 独占 warn 行在场；其加载全程挂起（无任何写命令
发出，load_state 不返回）；关闭第一标签后第二标签在
轮询周期内自动接管、列表呈现 302 篇、Diag 记
takeover ok 行。接管延迟上界 = 等待循环重试周期
（2 s）+ 句柄释放（约 61 ms，spike 实测）。

## 5. 构建与体积

- build.sh：MYNOTE_SQLITE=1 时 web 带 sqlite-backend
  feature 构建 + 存储 Worker 构建段（需本机 clang；
  box 不构建、只跑 dist，无需 clang）；Worker 三资产
  （worker.js / pkg js / pkg wasm）注入 dist/sw.js CORE
  与主 wasm 戳同代换版；演练台页一并入 dist
  （storage-worker/index.html，不进 CORE）。
- verify：第 15 节静态锁（源级恒查 + sqlite dist 级核
  资产与 CORE）；§8 体积预算加 sqlite 增量口径
  2,300,000 B（默认口径不变）。
- 实测：默认 dist wasm 4,014,400 B；sqlite dist 总
  7,894,064 B（应用 wasm 4,036,496 B + Worker wasm
  1,678,202 B + 胶水/演练台/lang/图标）。
- spike 脚手架处置：rust/apps/sqlite-spike 保留为阶段一
  证据与最小复现资产（报告 §5 已定不进生产构建面）；
  阶段二正式 Worker 为独立 crate
  rust/apps/storage-worker（独立 workspace，理由同
  spike：sqlite-wasm-vfs 原生 target 不可编译）。

## 6. 本地门禁

- cargo test --workspace：170 全过（基线 165 + 新增
  phase2_sync 五项）。
- cargo check（wasm32）：web 默认 / sqlite-backend 两
  模式零错误；warning 默认 25 / sqlite 26（基线 27，
  零新增；跨后端未用函数以 cfg_attr 精确处理）。
- verify：默认 dist 与 sqlite dist 均 ALL PASS（15 节）。

## 7. 真机门禁清单（阶段三开工前，用户真机 Safari）

构建产物 dist（MYNOTE_SQLITE=1）部署到测试路径后：

1. 打开 `storage-worker/index.html` 演练台 → 点「全流
   程自检」→ 输出 init ready、migrate ok、load_all
   memos=20 ok、search 命中在场、SELFCHECK DONE；
2. 整页刷新 → 点「复验落盘」→ recheck load_all
   memos=20 ok（落盘在）；
3. 应用页冷启（存量 IDB 有数据）：列表正常加载，设置
   → 诊断日志查 `SQLITE migrate ok` 与
   `SQLITE load source=sqlite` 两行；
4. 双标签：第二标签开应用 → 出「已在另一标签页打开」
   提示；关第一标签 → 第二标签自动进入列表；
5. 编辑任意一篇保存 → Diag 有 `SQLITE save_sync
   upserted=1`（或 deleted/unchanged 合理值）行；
6. 杀进程后重开应用 → 数据完好、无加载失败态。
任一项不过，阶段三不开工、先回本报告补证据定位。

## 8. 阶段三开工条件

- [x] 本报告 §3/§4 的 box 演练数字全绿（回归子集的
  smoke-rustweb-blocks 两项 IDB 直读断言为已定性口径
  例外：双写落地或该冒烟读法改经 persist 后转绿，见
  §3）；
- [ ] §7 真机门禁清单由用户真机跑通并回报；
- [ ] 双写对账设计定案：迁移后常规保存的 IDB 镜像策
  略（现阶段二在迁移与导入两个时刻做全量 IDB 镜像，
  常规编辑保存只写 SQLite——观察期双写须补 save_memos
  的 IDB 侧落点与对账 Diag 行；smoke-rustweb-blocks 的
  两项 S3 落盘断言届时转绿，或先行把该冒烟的
  readS3Doc 改为经应用面读回）；
- [ ] Worker 硬失败姿态定案：现回退 IDB 直读（保可
  用）；切生产前须定「已迁移用户 Worker 损坏时」的呈
  现与抢救路径（救援层导出 IDB 副本仍有效）；
- [ ] 逐篇隔离（主线）与 IDB 分条（idb-optimize）合流
  后的存量形态对齐：迁移源形态若变，migrate 入参适配
  层随之对齐并重跑本演练；
- [ ] Store::export_backup 的 chrono 时钟面在 wasm 下
  未验（桥不调用、导出走主线程）；阶段三若 Worker 侧
  需要时间戳生成须先补验。
