# 全仓 mynote → moment 重命名盘点与执行单

用户 2026-11-26 拍板：存量代码名一并同步 Moment、Web 端也要统一、
全面彻底。仓库名与生产域名已于 2026-11-25 改完（Overtrees/Moment、
canopies-moment.pages.dev），本单处理仓内与本机侧的全部残留旧名。

## 原则

- **代码名/产物名**：直接改，无兼容包袱。
- **数据键名**（localStorage / IndexedDB / OPFS / 库内文件名）：
  一律带迁移——新名优先、旧名读到即搬运、校验通过才删旧，
  任何一步失败回退旧名继续运行并记 Diag，绝不丢数据。
- **历史记录不改**：docs/reports/ 既有报告、CHANGELOG 历史段、
  git 历史保留原文（记录的是当时事实）；现行文档（根目录八份 +
  docs 两份参照）按新名更新。本地目录名最后改（含 mynote-ab、
  mynote-zip-acceptance），改后全量核引用。

## 盘点（2026-11-26，git grep 口径，691 处 / 100+ 文件）

### A. Rust 包名与依赖（直接改）
- crates/core `mynote-core` → `moment-core`（lib 名 mynote_core → moment_core，
  全仓 use 路径 135 处随 Cargo 依赖键改名机械跟随）
- crates/storage `mynote-storage` → `moment-storage`
- apps/web `mynote-web` → `moment-web`
- apps/storage-worker `mynote-storage-worker` → `moment-storage-worker`
  （独立 workspace，wasm 产物名 mynote_storage_worker 同步）
- crates/ffi 已是 `moment-ffi`（新建即新名）；其 deps 键与 use 路径跟随
- 环境变量：`MYNOTE_SQLITE` → `MOMENT_SQLITE`（build.sh/verify/文档），
  `MYNOTE_ZIP_ACCEPTANCE_DIR` → `MOMENT_ZIP_ACCEPTANCE_DIR`（core 测试/CI）

### B. Web 产物名（直接改，build.sh / sw.js / index.html 同步）
- 主产物 `mynote-web.js` / `mynote-web_bg.wasm` → `moment-web.*`
  （wasm-bindgen --out-name 决定，index.html import 与 sw.js CORE 跟随）
- Worker 产物 `storage-worker/pkg/mynote_storage_worker.*` → `moment_storage_worker.*`
- SW 缓存名 `mynote-rustweb-<ver>` → `moment-<ver>`（activate 按名清旧缓存，
  改前缀即自然换代）
- Diag 导出文件名 `mynote-diagnostics-*` → `moment-diagnostics-*`

### C. localStorage 键（18 个，带迁移）
mynote_lang、mynote_backend_v1、mynote_pool_v1、mynote_diag_v1、
mynote_diag_archives_v1、mynote_diag_autodel_v1、mynote_diag_day_v1、
mynote_diag_level_v1、mynote_rescue_log_v1、mynote_boot_ok、
mynote_panic_v1、mynote_swupd_pending_v1、mynote_swupd_dismissed_v1、
mynote_imgsize_v1、mynote_backup_history、mynote_hint_editor_v1、
mynote_pending_input_v1、mynote_pack_<lang>（前缀族）。
迁移点：index.html 救援层内联脚本是每次加载最早执行者，在其开头
放一段自包含的键搬运（新键缺失且旧键在 → 复制后删旧；前缀族按
前缀扫描搬运）。应用与 Worker 侧只认新键。

### D. IndexedDB 库名（带迁移）
`mynote-web`（v2，kv/memos/attachments 三店）→ `moment-web`。
启动时若新库不存在且旧库存在：开旧库全量读 → 写新库 → 逐店计数
核对 → deleteDatabase 旧库；失败则继续用旧库并记 Diag，下次再试。

### E. OPFS 池与 SQLite 文件名（带迁移，最深一层）
- 池目录 `.opfs-sahpool` / `.opfs-sahpool-default` / `.opfs-sahpool-<fp>`
  → `.opfs-moment` / `.opfs-moment-default` / `.opfs-moment-<fp>`
  （VFS 注册名 opfs-sahpool* 同步改 opfs-moment*；池解析的「先探后用」
  候选表把新名排前、旧名排后，命中旧名且新名为空时整目录逐文件
  复制迁移，复制后开库验篇数/哈希，通过才删旧目录）
- 库文件名 `mynote.db`（storage-worker DB_NAME）→ `moment.db`：
  迁移走 Store API——旧库 export_backup ZIP → 新库 import → 计数/
  哈希对账 → 删旧文件（不做文件级改名，OPFS 无可靠 rename）

### F. CSS 类与 DOM 标识（直接改，全仓同 token 替换）
mynote-wiki-link、mynote-highlight、mynote-strikethrough、
mynote-export-*（导出 HTML 类族）、mynote-slash-*（编辑器 DOM id 前缀）、
mynote-pool-resolve（Web Locks 名）等 `mynote-` 前缀族 → `moment-`。
导出 HTML 为自包含文档（类与样式同文件），改名只影响新导出。

### G. 测试与文档
- tests/ 51 文件引用旧名（Diag 键、IDB 名、产物名、验收目录）：
  机械跟随新名；另新增迁移探针：旧名状态播种（LS 全键 + 旧 IDB +
  旧池/旧库文件）→ 新构建启动 → 断言数据完整迁至新名、旧名清除、
  笔记逐篇哈希不变（沿 probe_state_resilience 骨架）
- 现行文档八份 + docs/mynote-visual-language.md（文件改名
  moment-visual-language.md 并更新引用）；.github/workflows/
  mynote-rust-web.yml → moment-rust-web.yml
- storage 测试临时文件名 mynote_native_pipeline_* → moment_*

### H. 本机侧（最后执行）
- ~/workspace/Mynote → ~/workspace/Moment；~/workspace/mynote-ab →
  ~/workspace/moment-ab；~/workspace/mynote-zip-acceptance →
  ~/workspace/moment-zip-acceptance；逐一核对脚本/文档中的绝对路径
  引用（部署工具以参数传路径为主）；box 侧测试树随下次使用重建

## 执行序与门禁

1. A+B+F（纯代码/产物）一笔批：cargo check/test 全绿、verify 15 节
2. C+D+E（数据迁移）一笔批：迁移探针先行（旧状态播种必须在旧构建
   上生成、在新构建上验），box 全量 58 项 + 迁移专项全绿
3. G 文档与测试跟随；H 本地目录最后改
4. 部署（双 key 注入规矩不变）→ verify_live LIVE == ARCHIVE →
   生产冒烟；推送待用户给 1.txt

## 不在本单内

- SQLite 观察期口径不变（dual 双写继续；本单不动后端三态逻辑，
  只动命名与迁移）。观察期退出判据照旧。
- 原生 iOS 侧尚无存量命名（moment-ffi 已新名），③④ 以最终名推进。
