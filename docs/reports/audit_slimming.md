# 仓库源码瘦身审计（2026-11-25，只读盘点）

基线：main = 251486e，生产 ffdc0845e2。git 跟踪快照共 **1,142 个文件 / 25,325,738 B**。
本报告所有「回收量」指**跟踪快照（检出体积）**的减少；删 HEAD 文件不缩小.git 历史包（历史刚重写过，不在本轮范围）。
判定「零引用」的口径逐项注明：grep 模式、搜索范围、是否跑了编译器/特性口径复核。

## 总览

| 档 | 项数 | 可回收（跟踪快照） | 性质 |
|---|---|---|---|
| A 可直接删 | 5 组 | ≈144 KB / ≈2,800 行 | 零引用或编译器实证，无需拍板 |
| B 删前需确认口径 | 11 组 | ≈16.2 MB（另有 ≈3.1 MB 优化型） | 全部回收的大头，集中在两个整线去留决策 |
| C 看着冗余但不能删 | 15 组 | — | 逐项注明保留理由 |

**结构性结论**：仓库的「肥」不在零碎死代码（A 档只占 0.6%），而在两条整线：
Flutter 原生线 `native/` 占跟踪快照 **40.8%**，原版 Web 规格参照栈（src+vendor+tests+入口）占约 **16%**。
这两条线的去留定了，瘦身才有量级；其余都是千字节级清理。

---

## A 档：可直接删（证据确凿、无引用）

### A1. 根目录无引用一次性脚本 ×10 — 51,565 B / 1,003 行
- 路径：`katex_array_dump.cjs`（3,805 B/52 行）、`katex_cols.cjs`（1,700/21）、`katex_metrics.cjs`（3,529/73）、`katex_rows.cjs`（1,588/25）、`probe_scroll2.mjs`（4,004/74）、`probe_scroll3.mjs`（3,651/64）、`probe_scroll4.mjs`（6,598/119）、`probe_slash_orig2.mjs`（5,202/133）、`probe_slash_rust.mjs`（12,088/254）、`probe_slash_rust2.mjs`（9,400/188）。
- 证据：对全部跟踪文本文件（.mjs/.cjs/.js/.rs/.md/.sh/.py/.html/.json/.toml/.css）做文件名+基名 grep，十个文件**外部引用均为 0**；不在 `run_all_tests.sh` 门禁集（57 支），不在 TESTING.md 登记。scroll 系列已被 `probe_scroll.mjs` 与现行门禁探针取代，slash 系列已被门禁内 `probe_slash_anchor.mjs` 取代；四个 KaTeX 量测脚本是 MathML 落码期的一次性取数，结论已沉淀进 `rust/crates/core/src/mathml.rs` 与 `audit_katex_eval.md`。
- 风险/前置：无。删除后 git 历史仍可找回。

### A2. archive/probes 内的 scratch/tmp 残渣 ×22 — 81,817 B / 1,573 行
- 路径：`archive/probes/` 下 `.scratch_*` 15 个、`app_check.tmp.mjs`、`probe_launch_tmp.mjs`（0 字节）、`proxytest_tmp.mjs`、`dbg_mirror_tmp.mjs`、`probe_menu_tmp.mjs` 等共 22 个（文件名含 `.scratch_` 或 `tmp`）。
- 证据：归档区其余 273 个文件是批 13 脚本治理（2026-11-23）有意归档的一次性脚本，唯独这 22 个连归档价值都没有——文件名即调试残渣标记，且有 1 个零字节文件。
- 风险/前置：无。

### A3. Rust 编译器实证死代码 ×6 处 — ≈3.5 KB / ≈95 行
口径：`cargo check --workspace --all-targets`（默认口径）与 `-p mynote-web --features sqlite-backend --all-targets`（特性口径）双跑，以下六处在**两种口径下都**报 never used/never constructed/never read；另逐项 grep 全仓复核无构造/调用点。
- `rust/apps/web/src/editor/model.rs` `prev_editable`（约 28 行，102 行起）：注释自证已被 ops 的新合并路径取代（ops.rs:454 注释提及旧用法）。
- `rust/apps/web/src/editor/model.rs` `now_millis`（约 3 行）：零调用。
- `rust/apps/web/src/list.rs` `is_escaped_at`（约 11 行）：web 侧零调用（core/mathml.rs 的同名函数在用，是另一份实现，不受影响）。
- `rust/apps/web/src/list.rs` `Summary.attach_count` 字段及汇总累加（约 4 行）：字段从未被读（settings.rs 的同名局部变量是另一处统计，不受影响）。
- `rust/apps/web/src/editor.rs` `MediaReq::Replace` 变体 + `rust/apps/web/src/editor/ops.rs` 对应 match 臂（约 39 行）：全仓无构造点（现行只构造 SetImage/GalleryPick）；删变体须连臂一并删，编辑器.rs 媒体请求注释同步改。
- `rust/apps/web/src/blocks.rs` `CardMenu` 上下文包装结构 + `editor/hooks/bridge_wire.rs` 的 `use_context_provider(|| CardMenu(...))` 一行（约 5 行）：全仓 `try_use_context` 消费点逐个核过（MdEdit/SelBlock/ActiveEdit/CardEdit/CardRetry/TextSheet/WikiNav/Manifest/ImgPage 均有消费），**唯独 CardMenu 无任何上下文消费者**——信号本体经 Contexts 结构体以 props 传给 CardMenuLayer 在用，只删包装结构与 provider 注册，信号保留。这正是 cargo 报 `CardMenu.0 field never read` 的本体。
- 风险/前置：删后跑 `cargo check`（双口径）+ `cargo test --workspace` 确认 warning 基线下降且无新错。

### A4. 空 lib 目标 — 0 B / 0 行
- `rust/apps/web/src/lib.rs`：0 字节，全仓 grep `mynote_web::` 零引用；它只让 Cargo 多编一个空 lib 目标。删之无体积回收，纯结构清理。

### A5. styles 死规则一组 — ≈6.7 KB / ≈144 行（上限估算）
口径：提取四样式表全部类名（369 个），在 `rust/apps/web/src` + `index.html` + storage-worker web + editor.js 中做字面 grep，并对动态拼名族（`blk-h{lv}`、`callout-{variant}`、`language-{l}` 等 format! 构造）单独排除后，以下类**零字面引用且无动态构造路径**：
- base.css：`.editor-btn`、`.more-btn`、`.item-right`、`.item-time`、`.img-cover-fb`（原版列表/封面类，Rust 列表用 item-left/item-meta/img-cover 等另一套）。
- editor.css：`.attachment-placeholder`、`.lazy-img-placeholder/.lazy-img-wrapper/.lazy-img-thumb/.lazy-img-full`、`.virtual-scroll`（原版 LazyImage 家族，Rust 走 imgsize 预留 +.img-rsv）、`.mynote-decorative-divider`、`.ed-block`、`.atomic-img`、`.atomic-att`（Rust 原子块统一 `.atomic[data-type]`）、`.link-card-body/.link-card-title/.link-card-subtitle`（现行 lkc-* 前缀）、`.lke-inner`、`.task-list/.task-list-item/.task-list-item-checked`（原版 marked 输出类，Rust MD 渲染不产此 DOM）、`.katex/.katex-display` 两条小规则（Rust 纯 MathML 不产 katex 类）。
- panels.css：`.backup-stats/.backup-stat/.backup-stat-label/.backup-stat-value/.backup-hero-desc`（旧备份页统计栅格，现行备份页为 backup-hero/backup-card 行式布局，无此标记）。
- 估算口径：按规则块逐块量得 base ≈1,153 B/29 行、editor ≈4,912 B/87 行、panels ≈679 B/28 行；含个别与活选择器共享的规则行，实际回收略低于此上限。
- 风险/前置：删后跑 verify_rustweb + smoke visual + probe_katex 系列确认无视觉回归；lang 五包已另行核过（见 C8，无可删）。

**A 档合计 ≈143.6 KB / ≈2,815 行。**

---

## B 档：删前需确认口径（逐项列明拍板点）

### B1. Flutter 原生线 native/（跟踪部分） — 10,342,282 B / 153,788 行
- `native/app` 200 文件 6,819,855 B / 55,897 行（Flutter 应用本体，含 NotoSansSC 字体 woff2 两件共 4,009,196 B、sqlite3.wasm 758,836 B）；`native/vendor/super_editor` 245 文件 3,522,427 B / 97,891 行（本地补丁版第三方编辑器库）；`.github/workflows/mynote-flutter.yml` 随线。
- 背景口径：2026-11-21 用户定架构转向 Rust scheme-B、Flutter「暂搁置、代码原样保留」；后续原生计划是 Rust Core + 原生 UI（云端 macOS 打包），与这套 Flutter 实现不是同一条线。此后 native/app 仅 2026-11-21 有提交，workflow 仍会在 native/** 变更时触发。
- **拍板点**：Flutter 实现是彻底退役（删）还是继续留作参照/回退（留）？另有未跟踪的同线实验目录 `native/spike`、`native/spike_se`、`native/vendor/appflowy_editor`（本地共 ≈251 MB，不在 git 内）随同一决定处置。

### B2. 原版 Web 规格参照栈 — ≈4.05 MB
- `src/` 54 文件 662,938 B / 14,379 行；`vendor/` 29 文件 1,055,859 B（React/KaTeX/marked 等原版运行时 + KaTeX 字体）；`tests/` 33 文件 2,281,212 B / 10,044 行（其中 `tests/browser/visual-baselines` 18 张 PNG 占 1,975,168 B）；根入口组（Moment.html、index.html、sw.js、manifest.json、package.json、package-lock.json ≈16 KB）；`tools/verify.mjs` 6,565 B；`dev/` 9,840 B；`docs/` 两份原版规范 13,982 B。
- 背景口径：CONTEXT.md/README.md 现行口径为「原版退居行为规格参照、不再是线上实现」，原版站（GitHub Pages）仍作参照在线。Rust 侧回归已由 run_all_tests.sh + TESTING.md 体系独立承担，不依赖 tests/。
- **拍板点**：① 原版规格参照角色是否结束？② 若结束，`docs/` 两份规范（engineering-notes、mynote-visual-language）建议保留为提炼后的规格沉淀，其余整栈删除；③ 视觉基线 1.98 MB 可单独先行处置（原版视觉回归若不再跑，基线先删、测试代码后议）。

### B3. archive/probes 归档主体（A2 之余） — 951,706 B / 18,563 行，273 文件
- 2026-11-23 脚本治理有意把 295 个一次性脚本移入此处归档（提交 11b536f），不是误入。
- **拍板点**：是否接受归档脚本只留在 git 历史、树内不再保留？接受则 B3+A2 合并回收 1,033,523 B / 20,136 行。

### B4. 根目录专项探针（TESTING 登记但不在门禁内） — 227,160 B / 4,176 行
- 22 支 TESTING.md 有登记、run_all_tests.sh 未纳入的专项/原版对照探针（probe_pages_*、probe_md_orig/rust、probe_katex*、probe_scroll、probe_twocol_*、probe_wave1 等）197,839 B / 3,600 行；外加仅被审计报告与他探针引用的 `probe_pages_editor_rust.mjs`/`probe_pages_editor_rust2.mjs` 29,321 B / 576 行。
- **拍板点**：这批是「手动专项资产」还是「已完成使命」？处置选项：删、或移入 archive/probes（不省体积、只整洁根目录）、或维持现状。

### B5. SQLite 阶段一 spike crate — 42,485 B / 1,230 行
- `rust/apps/sqlite-spike`（含 Cargo.lock 679 行）：不在主 workspace、不被 build.sh/verify 引用，阶段二正式实现是独立的 storage-worker。但 PHASE2_REPORT 明确写了处置决定「保留为阶段一证据与最小复现资产」。
- **拍板点**：是否推翻该保留决定？建议折中：删代码、保留 `SPIKE_REPORT.md`（8,395 B）或将其移入 storage-worker 文档区。

### B6. 图标重复与尺寸（优化型，非删除） — 可回收 ≈1.26 MB
- `Mynoteicon.png` 与 `rust/apps/web/Mynoteicon.png` SHA-256 逐字相同，各 1,255,457 B。两份各有引用：根级供原版（Moment.html/index.html/manifest/sw.js/README），web 份供 Rust 构建（build.sh cp 进 dist、manifest 引用）。
- 且该图 1254×1254、1.25 MB，而 manifest 只用 192/512 两档——proposals_optimization 已登记此 dist 膨胀点。单源化（构建时从一处拷贝）+ 生成 192/512 衍生图，可回收 ≈1.2 MB/份。
- **拍板点**：是否动图标资产管线？动则需验主屏图标与 favicon 呈现。

### B7. fixtures/allblocks.zip 内部三同图（优化型） — 可回收 ≈1.87 MB
- zip 内 `attachments/03tr8q3k`、`0bt6n032`、`2oo1ex1h` 三个附件各 637,276 B，SHA-256 完全相同（同一张图存了三份不同 id）。该夹具是现行门禁资产（smoke-rustweb-blocks/tails、probe_exit_anim 在用）。
- **拍板点/前置**：先确认「三 id 同字节」本身不是被测点（去重/同图多引用语义）；生成器 `make_allblocks.py` 的源是仓库外验收包，再生需该包在位；再生后重跑 blocks/tails 冒烟与 probe_exit_anim。

### B8. screenshots 响应式验证证据组 — 602,793 B
- `screenshots/responsive-image-cards/`（图 9 张 + verification.json）：仅 verification.json 自引用，README 未引（README 引用的 5 张 jpg 共 856,646 B 在 C 档保留）。属一次性验证留痕。
- **拍板点**：证据留存还是删除。

### B9. tools/sqlite_bench 阶段二探针 — 13,297 B / 270 行
- `probe_sqlite_phase2.mjs` 已被 `probe_sqlite_phase3.mjs` 取代；同目录 harness.html、gen_fixture.py、serve.mjs 仍被 phase3/blocked/ephemeral/pool 等现行探针共用，不能连带删。
- **拍板点**：阶段二探针随阶段二报告留存还是单独退役。

### B10. core 测试夹具同文两名 — 1,572 B
- `rust/crates/core/tests/fixtures/sample_manifest.json` 与 `sample_flutter_manifest.json` SHA-256 相同；roundtrip.rs 用同一 checker 分别跑两个文件名。
- **拍板点**：测试设计问题——两名同文的「来源覆盖」是否还有意义；无意义则并成一份、删一个测试名。量级极小，可随手并入执行批。

### B11. fixtures/audit-bg.zip — 568 B
- 仅被 archive 内一支已归档探针引用。随 B3 决定联动：归档区删则它失去唯一引用。

**B 档删除型合计 ≈16.2 MB；优化型（B6+B7）另 ≈3.1 MB。**

---

## C 档：看着冗余但不能删（注明理由）

- **C1 `idb.rs has_library_data`**：默认口径 cargo 报 never used，但 `--features sqlite-backend` 口径下警告消失——它是池指纹解析的 IDB 存量探针，特性门控使用。删之即断无痕根治线的池解析。
- **C2 `imgsize.rs` 的 `CACHE_KEY` 与 `record_url_size`**：host 口径 cargo 报未用，实为 `#[cfg(target_arch = "wasm32")]` 的 load/persist/record_from_img 路径使用，非 wasm 构建看不见。假阳性。
- **C3 `backup.rs` 的 `ProviderId::CloudKit` 与 `CloudKitProvider` 桩**：用户已定案的 provider 接口缝（iCloud 待本人 Developer Program 后接入），代码内有 `#[allow(dead_code)]` 与接入条件注释。属「刻意保留的未实现接口位」，非死代码。
- **C4 storage-worker 的 `wasm-bindgen-futures` 依赖**：src 内 grep 零命中，但 `#[wasm_bindgen] pub async fn rpc` 的宏生成代码引用该 crate，grep 不可见。删之构建即断。spike 的同名依赖同理。
- **C5 `persist.rs` 内复刻的 `fnv1a_64`**：与 storage crate 同算法两份实现，注释写明理由——web 包不能依赖 storage（会把 rusqlite 拉进主 wasm），且有测试以 storage 的测试向量钉住两份等价。有意重复。
- **C6 persist.rs 与 idb.rs 的同名函数群**（load_state/save_backup_delta/save_all 等）：前者是三态后端门面、后者是 IDB 臂实现，同名是分层而非重复实现。
- **C7 `now_iso` 两份**（settings.rs 私有 vs editor/model.rs pub(super)）：模块局部小助手，合并需跨模块开放，回收约 6 行，不值当动。
- **C8 lang 五包 268 键**：以 zh-CN 为全集逐键 grep web 源码，268/268 全部有字面引用，零废弃键；verify §8 另有键集对齐与僵尸键门禁。无可删。
- **C9 `rust/apps/web/index.html` 内联救援层/SW 更新脚本**（613 行中的大部）：与应用解耦是其设计前提（应用死了也要能出救援面板），verify §13 静态锁在位。不是与 styles 重复的样式堆。
- **C10 根 `sw.js` 与 `rust/apps/web/sw.js`**：分属原版与 Rust 两个应用，各自现行（原版部分随 B2 决定）。
- **C11 根重定向存根**（clear_drive.html、color_preview.html、preview_dino.html）：被 tools/verify.mjs 与 tests/modules.test.mjs 断言引用，是原版栈的防误删护栏，随 B2 联动。
- **C12 门禁资产**：run_all_tests.sh 的 57 支冒烟/探针（843,285 B / 15,249 行）、tools/sqlite_bench 现行探针组、fixtures 其余夹具（逐个核过均有现行探针/生成器引用）、根目录 5 张 README 截图（856,646 B，README 在引）。
- **C13 native 内的同图两名**（Icon-512 与 Icon-maskable-512 等）：Flutter/PWA 平台约定路径，必须同图异名并存；随 B1 整线决定，不单删。
- **C14 三份 Cargo.lock**（主 workspace / storage-worker / spike）：各自独立 workspace 的可复现构建锁；spike 那份随 B5。
- **C15 `.editor-export-entry/.editor-export-back` 等 CSS 规则**：全局表里与活类 `.editor-export-choice` 共享规则块，且原版对照探针仍以此选择器打原版页面；只能修剪选择器列表，不能整块删，量级小，留待 A5 执行时顺手核。

---

## 每面盘点小结

1. **git 跟踪体积**：Top 大文件为 native 字体（4.0 MB）、fixtures/allblocks.zip（1.90 MB）、双份图标（各 1.26 MB）、native sqlite3.wasm（0.76 MB）、原版 vendor（katex.min.js 272 KB、google-gsi 264 KB）。无误跟踪的构建产物：rust/target、dist、node_modules 均已被.gitignore 正确忽略（git check-ignore 实证）。
2. **Rust 死代码**：cargo 双口径 check 的真实死项只有 A3 六处；另三处是特性/cfg 假阳性（C1/C2）。模块图无孤儿文件（web/src 各文件均有 mod 声明或 include 关系）；唯一被取代的旧实现是 sqlite-spike（B5）。
3. **依赖**：core/storage/web 三 crate 的直接依赖逐个 grep 均有实际引用；唯一 grep 零命中的 worker `wasm-bindgen-futures` 是宏生成引用（C4）。无可删依赖。
4. **原版与历史代码**：原版栈完整在位（B2）；Flutter 线完整在位（B1）；旧单体 Moments.html 已不在树内（仅存于 git 历史），现行原版入口是 Moment.html + src/ 模块化形态，无单体残留。
5. **根目录杂物**：跟踪内的杂物为 A1 十支；未跟踪的 `.scratch_slash_*.mjs`、`wide_*_tmp.mjs`、`wtest.txt`、`wklaunch.sh`（合计 ≈50 KB）是本地临时物，可随手清（不属 git 范围）。`tools/` 无一次性脚本混入现行工具链：verify_rustweb.sh 与 sqlite_bench 现行探针均在岗，仅 phase2 探针待议（B9）。
6. **测试与夹具**：现行门禁 57 支全在岗（C12）；历史探针分三层——根目录专项（B4）、archive 归档（A2+B3）、TESTING 登记口径与 run_all 门禁口径不一致是这批资产的主要管理问题。夹具除 B7/B10/B11 外均有现行引用。
7. **样式与前端资产**：死规则见 A5；lang 零废弃键（C8）；index.html 内联层为设计在位（C9）；sw.js 无过期段（Rust 侧 CORE 清单与 build.sh 注入的 Worker 资产一致，verify §15 在锁）。

## 附：本地工作区（非 git 跟踪，不计入上表）
- `rust/target` ≈11.23 GB、`rust/apps/storage-worker/target` ≈236 MB、`rust/apps/web/dist` ≈8.1 MB、`node_modules` ≈14 MB：均为已忽略的构建产物，`cargo clean` 等可回收 ≈11.5 GB，随时可再生。
- 未跟踪实验目录 `native/spike` ≈146 MB、`native/spike_se` ≈89 MB、`native/vendor/appflowy_editor` ≈16 MB：随 B1 决定一并处置。
