# 快照 zip 域批：规范域第四面（计数）收口与 zip 收录域实证

日期：2026-11-28。分支 fix/snapshot-zip-domain（基线 main
bdf062c）。承 fix_snapshot_restore_domains.md（0.9.67 入版）：
该批把规范域定为可恢复活库域、清单/verify/FFI 三方同源；本批
处理其桥自办（0.9.67 装机后）暴露的余项——drill 第一遍步 5 实
红、第二遍（干净库）全绿。

## 一、定案：工单前提修正——导出域本已对齐，真残差在计数面

工单原判：zip 导出域仍含已删态行，删过的库恢复快照会带回已删
备忘。落码前以探针 + 域测试实证，此判**不成立**：

- storage `Store::export_backup`（crates/storage/src/lib.rs）
  早在规范域批即有收录过滤——导出条目以容错解析收集后
  `retain(|m| m.deleted_at.is_none())`，软删窗内与窗外过期未
  清两态都不入包（本批新增域测试
  `export_zip_domain_equals_active_domain` 逐值锁定：zip 条目
  id 集 ≡ `active_memo_hashes` 活篇域、入包者无 deletedAt）。
- 全链实证 `snapshot_restore_never_revives_deleted_rows`：含
  两删态行铸快照 → 导入新库 → 已删篇在新库全行域
  （memo_hashes）无迹，活篇集/聚合哈希/计数与源库规范域逐值
  一致。已删备忘不会经快照恢复复活（proven，构建期）。

drill 步 5 的红另有其面——**计数面**：清单 memoCount 旧出应用
镜像（`library.memos.filter { deletedAtMs == nil }.count`），
而 zip 条目出 DB 面。镜像与 DB 分叉时（备忘已从镜像删除、DB
行尚在且无 deletedAt 标记），清单计数 7 vs zip 实测 8：恢复
verify 的计数格必红，且多出的行在恢复后成孤儿（桥自办当时以
卫生网实打 orphan、手工清回）。即规范域实为**四方**——清单/
verify/zip/计数，前三方已同源，计数是最后一面。

## 二、根治：计数恒测自产 zip（铸快照单点）

根治点在铸造端单点 `BridgeWriteSupport.takeSnapshot`
（MomentBridgeTools.swift），不在恢复端过滤：

- 导出后立即以同一只读句柄 `validateBackup` 回读自产 zip，
  `parseValidateCount` 解析统计行（`memos=N attachments=M`，
  FFI 既有口径）得实测条目数，作为清单 memoCount 入册——
  清单 ≡ zip 由构造恒等，与镜像态无关。
- 回读失败或统计行无计数 → 整份快照失败（snapshot_failed）、
  不入册，不留清单不可信的半成品。
- `appendManifest` 改为只收外部测得的 memoCount（唯一调用方
  即 takeSnapshot，签名收口干净）；preHash 仍走 FFI 规范域。
- 新增 `snapshotZipMemoCount(library:id:)`：以同法回读任意在
  册快照的 zip 实测计数，供场景做运行对账（失败回 nil、调用
  方判红不猜数）。

恢复端零改动：其 verify 本就以清单为期望侧对账，期望侧改由
zip 实测后，计数格与哈希格同源同面。

## 三、附件收录域普查（工单②）：全表收录为设计口径，测试锁现状

导出收录 attachments 全表——含仅被已删篇引用的附件与无主附
件，恢复后随包回库为孤儿字节。此口径**保留不裁**，理由：附
件可被多篇共享引用，按备忘域裁剪须先建引用图、误伤共享件
的代价远高于包内孤儿字节（无害、不成备忘复活面——备忘面仍
守规范域）；且与 Web 导出同口径，保备份救援完整性。本批以
域测试 `export_attachments_cover_whole_table_by_design` 锁现
状防无声漂移：改口径须先改此测试并重新论证。

## 四、运行腿：新景 snapshot_deleted_rows_restore（矩阵 DAT-07）

桥景注册表九 → 十景（武装门与 drill 同集、高危声明三 → 四）：

1. 三夹具三态：存活对照 / 软删窗内 / 软删后等窗过期真删
   （8 秒撤销窗 < 15 秒轮询，与待删窗回归景逐字同型）；
2. 铸快照四方对账：zip 实测条目数 ≡ 清单计数 ≡ 当前活篇数
   （断言 zip_count_matches_manifest /
   active_count_matches_manifest——drill 步 5 的红面在此建
   格）；
3. 哈希守卫（快照后无本景外变更才许恢复）→ 内部同路恢复 →
   两删态均不复活（全集回读无行）、存活夹具仍在、哈希/计数
   与清单逐值一致。

自检矩阵登记 DAT-07（编号沿革：本行初稿误编 DAT-06，与既有
「SQLite 观察期冷启对账」DAT-06 撞号——该号为多份审计报告
在引，收尾审出后改编 DAT-07，矩阵行/§7 注记/场景注释三处
同步）。

## 五、断言与负对照

verify_ios.sh [75] 组：SR75-3 扩为「哈希三方同源 + 计数四方
同源」（appendManifest 无镜像过滤计数、takeSnapshot 段含
validate 回读与 parseValidateCount 解析）；SR75-5 扩 zip 收
录域测试三条在位；新增 SR75-6 新景接线锁（三点 + 武装门同
集 + zip 对账断言）。另 B27-2 注册表基数 9→10、B67-6 高危基
数 3→4。

负对照两组实做、各恰红其所指、复原转绿：

- 镜像计数回潮（appendManifest 改回 library.memos.filter
  计数）→ SR75-3 恰红，SR75-6 不动；
- 武装门摘除（armGatedIds 删新景 id）→ SR75-6 恰红，SR75-3
  不动。

## 六、验证分账

- cargo test -p moment-storage：24 passed / 0 failed（新 zip
  域测试三条全绿）。
- swiftc -parse MomentBridgeTools/MomentBridgeScenarios：
  通过（语法级；类型级编译门留 tree 组版 smoke）。
- verify_ios.sh 本机：本线 741 ✓ / 7 ✗；pristine 基线
  bdf062c 同机同跑 740 ✓ / 7 ✗，红集逐字一致（6 条产物红 +
  B25-10 枚举镜像环境红，基线同红、非本批引入，tree 构建自
  清）；增量恰 +1 ✓ = SR75-6 新增锁，SR75-3/5 与 B27-2/B67-6
  原位加强皆绿。
- 装机格（未冒充已验）：新景 snapshot_deleted_rows_restore
  装机实跑 + drill 在「删过东西的库」上复跑两遍全绿，归下
  版（0.9.68）桥自办清单。
