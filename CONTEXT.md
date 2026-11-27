# Moment（此刻）— 项目上下文一览

供新会话快速接入：一页读完能上手。细节按文末索引查对应文档。

## 这是什么

个人笔记应用「此刻」（英文名 Moment），打开就写、数据归用户本地。
当前线上实现是 **Rust 重构版**（scheme-B：Rust Core + Dioxus DOM Web）；
原版（React 18 UMD）已于 2026-11-25 瘦身轮整栈退役移出仓库
（仓库外只读归档 + git 历史可寻），行为规格口径已沉淀进
《设计规范》与 `docs/` 两份原版规范，不再是线上实现。
仓库：`Overtrees/Moment`（本地目录 `~/workspace/Moment`）。

## 地址

- 生产（Rust 版）：https://canopies-moment.pages.dev ，现行戳 `ffdc0845e2`
- SQLite 测试站：https://moment-sqlite-test.pages.dev（与生产严格分开）
- 原版线上（参照）：GitHub Pages（Overtrees/Moment）

## 架构与目录地图

- `rust/crates/core` — 文档模型、迁移通道（归一 + 逐篇隔离）、
  备份 ZIP、纯 Rust TeX→MathML 公式渲染（无 KaTeX JS）
- `rust/crates/storage` — SQLite 索引与 FTS5 trigram 全文检索、差量同步
- `rust/apps/web` — Dioxus 0.7 Web 应用（包名 `moment-web`）：
  `src/` 按 main/list/editor（含 bridge、cards、title、columns 等子模块）/
  settings/backup/diag/i18n/persist 等分工；样式 `styles/` 四文件
  （tokens→base→editor→panels）；语言包 `lang/` 五包（zh-CN 内嵌兜底）
- `rust/apps/storage-worker` — 存储 Worker（SAHPool VFS + RPC 桥），
  阶段报告与设计稿都在此目录
- `rust/apps/ios` — iOS 原生版（SwiftUI + UniFFI 接 moment-core，
  测试签名 ipa 分发）：app 源码与 build/verify/smoke 脚本同目录；
  阶段回顾见 [`docs/retrospect-2026-11-21-27.md`](./docs/retrospect-2026-11-21-27.md)
- `rust/apps/sqlite-spike` — 阶段一 spike 已退役（2026-11-25 瘦身：
  代码删除，仅留 `SPIKE_REPORT.md`）
- `docs/` — 原版两份规范（提炼后的规格沉淀，原版栈其余部分已退役）
- 仓库根 `audit_*.md / diagnose_*.md / scope_*.md / design_*.md` —
  过程性审计与确诊报告，历史价值，保留原样

## 构建 / 验证 / 部署（一行版）

- 构建：`bash rust/apps/web/build.sh`（SQLite 构建加 `MYNOTE_SQLITE=1`）
- 静态门：`bash scripts/verify_rustweb.sh`（15 节）
- 单元：`cargo test`（workspace）
- 浏览器全量：`bash tests/run_all_tests.sh`（在 Simular Box 跑，见测试分工）
- 部署：Pages API 部署器出归档，`verify_live` 核对 LIVE == ARCHIVE 为准；
  天气双 key 每次部署都要重新注入 staging（见开发规范第四节）
- 推送：见 `PUSH.md`（一次性令牌、逐批推、不攒批）

## 当前状态（2026-11-25）

- **SQLite 三阶段已上线，处于 dual 双写观察期**：SQLite 主写 + IDB
  差量镜像，冷启对账收敛。退出判据：≥14 天且 ≥30 次冷启对账全等
  （或漂移均可解释）、零降级行；达成后发「构建默认 = sqlite」正式
  切换版（纯口径翻转，不搬数据）。
- 无痕/隐私会话：OPFS 被 WebKit 政策性禁用，已根治——会话级落 IDB
  续跑并出横幅明示不保存（生产 ffdc0845e2，真机确认通过）。
- 天气：和风主用 + 彩云兜底（已恢复上线）；彩云 key 免费配额曾耗尽，
  兜底真出数待配额恢复后以 Diag 行判读。
- 仓库已更名 Overtrees/Moment；本地 main 与远端同步至 `251486e` 起
  的文档整理批（以 git 实际为准）。

## 待办大项

- 观察期满后发默认 sqlite 切换版（见上）。
- 多人/同步、容量、iCloud：已定案归原生 app 阶段，Web 端不做
  （原生等开发者计划就绪后接入，当前仅留 backup provider 接口缝）。
- GitHub 历史重写后的缓存清理走工单通道，等平台处理，无仓库侧动作。

## 红线速查（全文见开发规范）

根治性替换禁补丁式修法 · 诊断日志同步落地 · 退役代码 grep 零残留 ·
样式零内联 + 复用既有变量 · 安全区运行时 env 取值 ·
框架语义先源码实证 · 大文件外科编辑 ·
行为等价优先于形态 1:1 · 根页面唯一背景源 ·
测试分工：本机只编译级自检、浏览器全量归 box、iOS 结论须 WebKit/真机 ·
Safari 站点数据（IDB/OPFS）不可轻清，清了笔记就没了，ZIP 备份是安全网。

## 文档索引

- [`开发规范.md`](./开发规范.md) — 工程红线、数据与存储纪律、部署纪律
- [`架构设计.md`](./架构设计.md) — Rust 版结构与流向（运行单元、数据架构、编辑器分工、接缝）
- [`设计规范.md`](./设计规范.md) — 已定案 UI/UX 口径及出处
- [`教训沉淀.md`](./教训沉淀.md) — 已实证的坑（现象→根因→规矩）
- [`CHANGELOG.md`](./CHANGELOG.md) — 版本条目（Rust 生产里程碑 + 原版历史）
- [`TESTING.md`](./TESTING.md) — 回归测试矩阵（现行守门清单）
- [`PUSH.md`](./PUSH.md) — GitHub 推送流程
- [`docs/reports/landing_plan.md`](./docs/reports/landing_plan.md) — 六线审计落码总清单（过程文件）
- `docs/engineering-notes.md`、`docs/moment-visual-language.md` —
  原版工程与视觉规范（仍有参照价值，Rust 口径以设计规范为准）
