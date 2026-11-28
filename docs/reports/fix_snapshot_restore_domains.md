# 快照线两缺陷根治：恢复读面一致性 + 库哈希规范域

- 日期：2026-11-28
- 分支：`fix/snapshot-restore-domains`（父 b352260，独立 worktree `~/workspace/Moment-snapshot`）
- 提交：`27cff39`（哈希规范域）、`9cb4726`（reload 同步发布）、`9cfde75`（清理守卫 + 回归景 + 矩阵）、`d890a82`（verify [73] 组）
- 触发：0.9.66 装机后桥自办——snapshot_restore_drill 两遍步 5 误红且失败后夹具残留；待删窗内铸的快照直调恢复必挂 verify。

## 1. 缺陷一定案：单竞态、两落点

根因不在场景步序，也不在恢复工具——在 `Library.reload` 的镜像发布形态：发布块恒走 `DispatchQueue.main.async` 派发。桥恢复链在主线程同步执行（validateBackup → importBackup → reload → FFI 直读对账），reload 返回时 `memos`/`pendingDeletions` 仍是换库前镜像，于是：

- **落点一（步 5 误红）**：drill 步 5 `fixture_back_in_list` 在同一回合同步读 `library.memos`，读到的必然是旧镜像，夹具判 missing → step_failed。工具级 FFI 直读 verify（count=5/5、hash match=1）与场景读数不一致，正是两读面一新一旧的实证。两遍确定性复现，与竞态时序无关——派发即迟到。
- **落点二（失败残留）**：场景收尾清理 sweep 在同一旧镜像上查找夹具（待删集分支与列表分支双扑空），随后迟到的发布块以换库时点的快照覆盖 `memos`，把 sweep 已从 DB 真删的夹具在列表里「复活」；而夹具登记此时已注销，残留对卫生网不可见。桥自办只能手工清回（count=4/orphans=0）。

根治（`9cb4726`）：发布形态按调用线程分流，与本仓既有 isMainThread 分支先例同式——主线程调用方同步落定（publishMirror 内联执行），后台开库链仍异步派发、行为不变。不变量：**主线程 reload 返回 ⇒ memos/pendingDeletions 已与库一致**。场景步 5 与 sweep 自此与 FFI 直读同面，无需在场景层另加刷新或重试。

## 2. 缺陷二定案：三域不一致

### 三处哈希域现状（改前回源实证）

| 消费方 | 旧口径 | 域 |
|---|---|---|
| 铸快照清单 preHash（appendManifest） | FFI `library_hash` = memos 全表逐行（含 deletedAt 待删标记行、含解析不过的坏行） | 全行域 |
| 恢复后 verify 对账（bridgeRestoreFromSnapshot） | 同一 FFI `library_hash` | 全行域 |
| 快照 ZIP 收录（export_backup） | 活篇：`memos.retain(\|m\| m.deleted_at.is_none())` 且解析不过的坏行不入 | 活库域 |
| 计数（清单 count / verify count） | 活篇数 | 活库域 |

即哈希走全行域、收录与计数走活库域。待删窗（8 秒）内铸的快照：清单哈希把窗内夹具算在内，恢复后该夹具不进活库、重算哈希回到干净态，两值永不相等。实证：begin expectHash=159526573388 vs 恢复后 166426568086、count 4/4 合、match=0。推论成立：任何在任一备忘待删窗内铸造的快照（含软删操作自身铸的 snapshot-first 快照）日后恢复必挂。

### 规范域选择

规范域 = **可恢复活库域**：哈希域与 ZIP 实际能承载的集合恒等——这是三方唯一能自洽的选法，全行域的清单哈希对窗内铸件是「永不可达值」，不构成任何有效校验。落法（`27cff39`）：

- storage 立唯一域定义 `Store::library_hash()` / `active_memo_hashes()`：域 = 与 export_backup 收录域恒等（deletedAt 在位待删项与解析不过的坏行不入域），逐篇仍对存储原文 JSON 算 FNV。
- FFI `library_hash` 仅改函数体走 `store.library_hash()`，签名与文档注释未动——UniFFI checksum 契约测试通过、checksum 不变，无需重生 bindings。
- `memo_hashes()` 全行口径**保留不动**：其消费方是 Web storage-worker 的 sync_library 差量预言，不属三方，改它会误伤同步差量语义。

### 旧快照影响面

- 干净态（无待删窗）铸的快照：新旧域逐值恒等（域测试 `library_hash_matches_legacy_when_no_pending` 锁），清单哈希含义不变、照常可恢复。
- 窗内铸的旧快照：旧口径下本来就永远 verify 不过——不是本批打破的；新域下恢复它仍如实失败（清单值与新域重算值不等），不引入假成功。
- 影响面上界：快照保留策略 10 份 / 7 天，存量至多 10 份，且仅「铸造瞬间恰有备忘在待删窗内」者受影响。

## 3. 清理守卫收口面

普查结论：全仓夹具清理只有两条路径——场景引擎 sweep 与驱动 `cleanupFixture`（MomentBridgeUITest.swift，本身已有 gone 验净 + 失败 mark 不注销）。无第三处残留面。本批补的是引擎 sweep 这一条（`9cfde75`）：

- 场景上下文加 `cleanupResidue`；sweep 逐篇删除后以 `BridgeReadTools.allMemos` 全集回读验净，确认消失才 `UITestFixture.unregister` + 记成功行；残留记 residue + Diag error 且**不注销**，残留对卫生网保持可见。
- `finishAfterCleanup` 按终态优先级把残留升级 `hygiene_failed`（覆盖 ok/step_failed/run_timeout/aborted_user_active）；场景自定义终态码（如 language_left_changed）不覆盖，但残留仍记入 `detail["cleanupResidue"]`，不静默。
- 武装门收口：`BridgeScenarioRegistry.armGatedIds` 集合单点，availability 与 scenariosRun 受理两处同消费；旧逐景硬编码（`desc.id == "snapshot_restore_drill"`）清零，drill 与新景共用同一武装门。

## 4. 回归景与矩阵

新景 `snapshot_pending_window_restore`（ops/高危、两段、用户指令、armRestore 武装、fixture template、grades persistence=proven），即 DAT-05 的运行腿：建夹具 → 软删入窗 → 窗内 takeSnapshot 铸快照 → poll 15s 等窗口过期真删 → 守卫「当前 libraryHash == 清单 preHash」（步名 `hash_stable_across_window`）→ 内部同路 restoreSnapshot → 断言 hash/count 与清单一致 + 夹具不复活 → 结论 `pending_window_restore_verified`。

矩阵 plan_selftest_coverage.md：DAT-05 行改写登记规范域与新景；§5 后加 2026-11-28 状态注记（注册表扩为九景）。仓外同步：连接器 custom.moment-bridge 的 CONNECTOR.md 场景目录已补新景一条。

## 5. 断言与负对照

verify_ios.sh 新组 **[73] SR73-1..5**：

- SR73-1 清理验净结构锁（sweep 验净 + residue 记入 + 不注销在位）；
- SR73-2 reload 同步发布锁（主线程内联发布形态在位）；
- SR73-3 哈希三方同源普查锁（appendManifest preHash、bridgeRestoreFromSnapshot 对账、FFI 本体三方同走 storage 单点；FFI 段禁再现 memo_hashes 全行拼装）；
- SR73-4 回归景接线 + 武装门单点锁；
- SR73-5 域测试在位锁。

连带改判：B27-2 场景基数 8→9、B67-6 高危基数 2→3，均注沿革。负对照已实做并恢复：① 摘 storage 域过滤 → 两条判别域测试恰 FAILED（恒等守卫保持绿）；② 摘 sweep 的 residue 记入 + FFI 本体改回全行拼装 → SR73-1、SR73-3 恰红，SR73-2/4/5 保持绿。

storage 域测试三条（新 mod `library_hash_domain_tests`）：`library_hash_excludes_pending_deleted`、`library_hash_matches_legacy_when_no_pending`、`snapshot_minted_in_pending_window_restores_to_same_hash`。

## 6. 验证分账

- verify_ios.sh（worktree 干净树、绝对路径调用）：**717 ✓ / 5 红**——5 红全为无构建产物的陈旧红（ipa 不存在、Assets.car、两份 splash vector json、产物语言包），源码面全绿，含 [73] 五条。
- cargo：`cargo test --workspace` 全量绿（各套件 57/5/3/22/12/10/4/4/4/6/3/5/9/3/5，0 failed），含 storage 域测试三条与 FFI checksum 契约。
- swiftc -parse（本机 Swift 6.4.2）：MomentApp.swift、MomentBridgeScenarios.swift 两改动文件零诊断通过。仅语法面；全量 Swift 编译门留 tree 0.9.67 组版冒烟。

## 7. 留账（0.9.67）

- 组版：本分支与状态栏分支、标题字形分支、偿还批三余项三方合并入 main；Swift 全量编译与 smoke_ios.sh 全绿在 tree 完成。
- 桥自办装机实跑：snapshot_restore_drill 两遍复跑验步 5 转绿 + 失败路径零残留；新景 snapshot_pending_window_restore 首跑；待删窗直调恢复复验。前置：连接器场景面同步（scenarios_run 与新景枚举入 ALLOWED_TOOLS）须先行。
