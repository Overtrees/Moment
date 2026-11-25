# SQLite 阶段三报告：双写对账观察期（2026-11-25 落地并部署）

设计定案见 PHASE3_DESIGN.md。本报告记实现落点、基线对齐、
box 演练与部署结果；观察期自生产部署日起算。

## 1. 基线对齐（sqlite-phase3 分支）

自 main 884af07（生产 4c5449cdaf）拉分支，逐笔 cherry-pick
阶段一/二 13 笔 + 对齐修正笔 03ea602。冲突处置：

- idb.rs 以主线分条版为底，保留 quarantine kv 全套
  （QUARANTINE_KEY / load_quarantine / save_quarantine）；
  新增 replace_attachments（附件店单事务全量替换，供
  sqlite 形态 save_all 的附件半边）。
- main.rs 隔离落盘整块与「隔离先落盘」顺序红线保留，
  写回改走 persist::save_backup_full；dispatch/main 的
  save 调用面统一经 persist（delta/full/load_state）。
- 过渡期 persist 旧 save_memos 入口由 delta/full 口径
  取代；主线已退役的 idb::save_memos（kv 全量键写）不复活。
- 门禁：cargo test --workspace 192 全过（对齐后 191 +
  阶段三新增 backend_value_parsing 等）、verify 15 节
  ALL PASS（两口径构建各一次）、warning 与基线逐值一致
  （web 27 + core 1；sqlite wasm 口径 web 25）。

设计稿 §5 六项迁移源对齐差异销账：

1. 组装读入口 ✓ persist 迁移入参 = idb::load_state 组装
   读（backup_meta + memos_order + memos 店），与主线
   加载同源。
2. 坏篇走既有隔离通道 ✓ 迁移入参先在主线程过
   normalize_stock（core::migrate::normalize_stock_value
   + 严格解析校验，与 main 的 run_stock_migration 同
   算法、同 MIGRATE/QUARANTINE Diag 格式）；归一不过
   （整包校验失败）放弃迁移、原文走 IDB 加载路径。
3. quarantine_json 键保留可达 ✓ 隔离落盘先于 Worker
   migrate（落盘失败本轮不迁移）；对账/镜像写回面不含
   该键，永不触碰。
4. 分条全量写回 ✓ 迁后收敛与漂移收敛均走
   idb::save_backup_full（分条形态）。
5. Diag/探针基线重对齐 ✓ Diag 新增行见 §3；smoke-blocks
   S3 两项直读断言在双写下转绿（§4 销账）；19 个组装读
   探针沿用合流口径不变。
6. 导入两段提交 + 对账收敛 ✓ import_library：SQLite
   replace_library 先行、IDB 半边随后（dual = save_all
   全量、sqlite = 仅附件），两段分别记 Diag 行；第二段
   失败不回滚第一段，冷启对账收敛（T5b 杀页实证）。

## 2. 观察期形态实现（a0eec4b）

- 后端三态：Backend { Idb, Dual, Sqlite }；运行时开关
  解析序 = URL ?backend= ＞ localStorage
  mynote_backend_v1（idb/dual/sqlite/auto）＞ 构建默认
  （sqlite 构建 = Dual、无 feature = Idb）。启动 Diag 行
  `SQLITE backend mode={} source={}`。
- 双写：dual 下 save_backup = Worker save_sync 主写 +
  IDB 差量镜像（save_backup_delta / 全量时
  save_backup_full / manifest 变更同写），结果段拼同一
  行（`mirror=ok up=A del=B` / `mirror=fail`）；镜像失败
  不报错主写，置 mirror-dirty 待冷启对账收敛。
- 冷启对账：列表首绘后异步执行（仅 dual 且本会话未迁
  移/未导入/未降级时）。Worker memo_hashes（哈希十进制
  字符串回传）vs IDB 组装读逐篇 typed 重序列化 FNV-1a
  比对；漂移以 SQLite 为准单向收敛（load_all →
  save_backup_full）。Diag：`SQLITE reconcile ok
  memos=N ms=T` / `drift put=A del=B` / `fail <err>`。
- 硬失败姿态：wait_ready 或 load_all 失败 → dual 置
  READONLY（Diag warn `SQLITE backend unavailable,
  readonly fallback`、数据面 = IDB 镜像、底部常驻横幅
  .storage-readonly-banner）；sqlite 置 UNAVAILABLE
  （`backend unavailable, blocked`、.storage-blocked
  覆盖层变体 + 重试整页重载）。两态下写路径（含附件）
  一律拒绝。
- 迁移编排：见 §1 销账 2/3/4；Worker migration_status
  的 done 语义 = 迁移戳在位或 has_library=1（防种子首
  存后次启重复迁移）。
- 救援面板开关：index.html 救援 actions 末尾加后端开
  关行（非 idb 时「以兼容模式启动（存储）」置
  mynote_backend_v1='idb'；idb 时「恢复存储自动模式」
  置 'auto'），pushEntry 留痕 + location.replace 重载；
  只动开关、不动数据。五语字符串在救援层内联表中。
- 应用文案：lang 五包各加 storage.readonly_banner /
  storage.unavailable_title / storage.unavailable_sub
  三键。样式走 panels.css 全局表（tokens 变量、无内联）。

## 3. box 演练（probe_sqlite_phase3，Chromium 口径）

独立树 /workspace/mynote-sqlite-p3、端口 8191、开跑前
curl 核 served wasm md5 = 本地 dist（144273dc911a…）。
**ALL PASS（38 项）**：

- T1 迁移→双写→对账：冷启含迁移 1,254ms；save_sync
  78–142ms 带 mirror=ok up=1；IDB 镜像已含编辑；
  reconcile ok memos=302 ms=142–202。
- T2 漂移：改镜像一篇 + 注入幽灵篇 → drift put=1
  del=1 ms=217–245，篡改还原、幽灵清除。
- T3 硬失败：Worker 脚本桩（init 恒失败）→ 只读横幅 +
  降级行 + 列表读镜像 + 编辑被拒（EDIT save err、盘上
  不变）；撤桩清 SW 缓存后迁移恢复、数据完好。桩的
  响应头教训：跨源隔离下 module worker 脚本缺 COEP
  头会被浏览器拦死（dbg 隔离实证后补齐全头）。
- T4 开关：置 idb → mode=idb、无 sqlite 加载、编辑走
  分条保存且无 save_sync；回 auto → dual，且对账以
  drift put=1 收敛 idb 期编辑（设计实证）。
- T5 导入：两段行齐（import_library ok + idb
  mirrored）、组装读与加载源均为导入态。
- T5b 导入途中杀页：SQLite 已提交 302、IDB 仍旧 1 →
  冷启 drift put=302 del=1 收敛一致。

欠账与回归（同 dist）：probe_state_resilience
ALL PASS（231 项，阶段二欠账销账）；probe_load_stock
ALL PASS；probe_idb_split ①② 全过（写放大在 dual 下
同测得 IDB save ok bytes=20196、40.0×，镜像 delta 同
落该行）、③ 多个杀页变体过后探针快速翻页与独占锁释
放节拍碰撞（第二页被 .storage-blocked 拦截，占用面按
设计工作，属探针耦合、非应用缺陷）；冒烟 blocks
47 ✓ ERRORS none（**S3 两项断言转绿，阶段二遗留销
账**）、list / editor2 均 ERRORS none。

## 4. 部署（2026-11-25，观察期开始）

- 测试站 mynote-sqlite-test：同构建部署（deployment
  9e94f78d），sw VERSION 144273dc91 线上核对在位。
- 生产 mynote-rustweb：**144273dc91**（wasm 4,170,246 B，
  md5 144273dc911aec021fe8f133561378ad；总 dist
  8,029,914 B）。staging 注入和风 key（git 1798f5e
  shell 内提取、只验长度 32 与 md5 指纹 63f146dc、线
  上 index 单处核验在位、staging 已销毁、归档干净版），
  archive_release 归档 144273dc91，verify_live
  **LIVE == ARCHIVE**。

## 5. 观察期判读（给后续会话/用户）

- 采样：用户日常使用即采样。每次冷启 Diag 应有一行
  `SQLITE reconcile ok memos=N ms=T`；偶发 drift 行看
  put/del 计数与随后是否收敛（drift 本身不判负——如
  idb 开关期编辑、导入杀页都会产生可解释 drift）。
- 退出判据（设计稿 §6）：≥14 天且 ≥30 次冷启对账全
  等（或漂移均可解释）、零未解释漂移、零硬失败降级
  （Diag 无 `backend unavailable` 行）。达成后另发构
  建默认 = sqlite 的版本完成正式切换（不在本轮）。
- 回滚一句话：救援面板点「以兼容模式启动（存储）」
  重启即回 IDB 形态（数据面 = 一直在双写的 IDB 镜
  像），不需重新部署；恢复自动模式同面板再点一次。
