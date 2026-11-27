# 备份小批（审计登记余项收口）— 只读准备 · 停门

> 状态：**清单提取 + 现行形态核对 + 落码设计完成，未落任何代码，停门等放行。**
> 落码门：0.9.58 组版分拣提交进行中（开工时 HEAD 4070d70 = bump 笔已入、组版未收口）。门前全程只读。
> 清单来源（报告原文为准、不自扩）：`audit_home_other_deep.md` §4.8 + §7 分批表「备份小批」行（三项）；`audit_landscape_wide.md` 备份相关面逐项复核（均为达标/销项，见 §4）；备份相关批报告（impl_bridge_m2 快照链、impl_rescue_r2r3 只读门面、impl_entitlements_b 实况挂点）交叉核对。
> 守恒红线（本批不许动）：导入 validate-then-swap 单事务、re-import 替换不追加、桥快照链（写前必拍 / 保留 10 份 7 天 / 直调 FFI exportBackup 不走 Library.exportZip）口径——三项设计均不触碰。
> 行号口径：MomentApp.swift 现行工作树（含 0.9.58 在途 hunk），放行落码时以当时源码复核为准。

---

## 1. 本批清单（3 项，全部来自 §4.8 / §7）

| # | 项 | 出处 | 证据级 | 现行形态核对结论 |
|---|---|---|---|---|
| BK-1 | commit 返回拆成败/计数两路——导入成功但 stats 解析失败误报「导入失败（现有数据未动）」 | §4.8 差②、§7 备份小批 | inferred 边沿（审计）→ 本轮源码核对 **proven 可达两条边沿**（见 §2.1） | 未办，现行代码坐实 |
| BK-2 | stagedStats 只写不读死字段——清理或补呈现 | §4.8 差①、§7 备份小批 | proven | 未办，现行代码坐实（见 §2.2） |
| BK-3 | 导出 toast 锚在生成成功而非分享完成——口径注记/收口 | §4.8 差③、§7 备份小批 | proven | 未办，现行代码坐实（见 §2.3） |

§7 分批表对本批的原文界定即此三项，无前置裁定（「无」）。覆盖矩阵增补候选 #12（SET-07/08 子行：导入 stats 边沿回读；stagedStats 死字段构建期可查）与本批同源，落码后由断言承接（见 §3.4）。

## 2. 逐项现行形态核对

### 2.1 BK-1：成败与计数耦合在同一返回值（根源在 Library 层，非呈现层）

`Library.commitStagedImport() -> (Int, Int)?`（MomentApp.swift:1755-1793）现行结构：

- do 块内顺序：`importBackup`（整库替换，**提交点**）→ `parseStats(result)` → `importOk = true` → `recordOp(ok: true)` → Diag → `try reload(lib:)` → `return stats`。
- **边沿 A（审计原项）**：importBackup 已成功换库，但 `parseStats` 解析不出 `memos=/attachments=` 时返回 nil，函数整体回 nil。调用方（BackupView 确认钮，:19213-19224）以 `if let stats` 判成败，落 else 分支弹 `status.import_error`「导入失败（现有数据未动）」——**数据其实已换、文案明示未动**，且与先行写入的 recordOp(ok:true) 自相矛盾。
- **边沿 B（本轮新坐实，同根）**：`try reload(lib:)` 在 importBackup 之后同处一个 do/catch。reload 抛错时 catch 再记一条 `recordOp(ok: false)`（插到列表首位，覆盖真值呈现）+ 弹导入失败 toast + ErrBadge——同样是「库已换、报未动」。另 `importOk` 已在 reload 前置 true，实况以 .ok 收口而 toast 报失败，三面（toast / 操作记录 / 实况）口径互斥。
- **同根兄弟（stage 侧）**：`stageImport(from:)`（:1727-1753）校验通过但 parseStats 失败时同样回 nil，fileImporter 回调（:19125-19135）落失败分支记 recordOp(ok:false) 并弹 `status.import_invalid`——文件其实合法，只是计数解析失败；`import-pending.zip` 已暂存却无路可走（下次 stageImport 覆盖，无残留危害）。
- 根源定性：**stats 是导入的附带产物，却被用作成功判据**。成败应只由 importBackup / validateBackup 本体决定，计数解析失败至多降级为「计数未知」，不许反转成败。此为返回值契约问题，按红线在 Library 层根治，不在 BackupView 消费方加补丁（如「nil 时再查库计数猜成败」一律不取）。

### 2.2 BK-2：stagedStats 死字段（proven）

- `BackupUI.stagedStats`（:18892）全仓仅一处写：fileImporter 回调 :19126 `ui.stagedStats = stats`；**零读点**（grep 实证，含 verify_ios.sh）。确认底表的消息恒为静态 `Lang.t("backup.import_msg")`（:19183），不带计数。
- Web 对照（审计 §4.8 已核）：Web 确认面同样不显校验计数——不呈现属行为等价，字段本身是死状态。审计提案二选一：清理或补呈现。
- 处置取向（设计 §3.2）：**清理**。理由：① 与 Web 行为等价、零文案/语言包新增；② 导入成功 toast 已以 commit 回读计数对账（`status.imported` {n}/{m}），确认前再显 staged 计数为重复信息面；③ 红线⑤：只为占位存在的死状态应删、不留兼容层。若主线倾向补呈现（确认前显「将以 N 篇备忘 / M 个附件整库替换」），需新增五语键一条并改确认消息拼装，工作量小、但须在放行时明示改判——本设计默认按清理落码。

### 2.3 BK-3：导出 toast 在分享面板弹出即报「文件已分享」

- 现行（:19193-19202）：确认钮点按 → `exportZip()` 成功 → `ui.shareURL = url`（.sheet 随之呈现）**同时** `showToast(status.shared)`。ShareSheet 呈现/完成/取消均未回读，toast 与真实分享结局无关——用户在分享面板点取消，仍已报「文件已分享」。
- Web 口径（审计 §4.8）：Web 导出为下载路，toast 锚在下载真实发生；原生「同义不同真」。
- 可根治性（本轮新核）：`ShareSheet`（:3604-3626）**已有** `onComplete: ((Bool, Error?) -> Void)?` 回调（批 K 为附件打开路接入，completionWithItemsHandler 已接线），注释明示「其余调用点（导出面）不传、行为不变」——备份页 .sheet（:19138-19145）正是未传的调用点。根治无需新机制，接线即可。
- 边界：操作记录 opMessage 对 (export, true) 恒映射「文件已分享」（:19290-19296，C10 定案：记录消息按 kind/ok 映射 Web 记录口径）——recordOp 记的是**生成**结局，其标题映射属 C10 既定口径，本批不动；仅 toast 锚点后移到分享完成。取消分享时不弹 toast（与现状的差别仅此一处，属口径收真、非行为回退）。

## 3. 落码设计（放行后执行，本轮未落码）

### 3.1 BK-1：Library 层返回值契约拆分

- 新增结果类型（Library 内）：`enum ImportOutcome { case success(stats: (Int, Int)?); case failure }`（命名以落码时文件内惯例为准）。
- `commitStagedImport() -> ImportOutcome`：
  - writeBlocked / importBackup 抛错 → `.failure`（现行 recordOp(ok:false) + Diag + ErrBadge 保持）。
  - importBackup 成功即提交点成立：recordOp(ok:true) + Diag + importOk=true 均以此为准；`parseStats` 结果只填 `stats`（可 nil，Diag 附一行 `IMPORT stats unparsed` 便于定因，不入 ErrBadge）。
  - `reload` 移出成败域：swap 成功后 reload 抛错单独记 Diag error + notice（数据已换、呈现重载失败是另一故障面），不回滚 ImportOutcome、不再记 recordOp(ok:false)。
- `stageImport(from:) -> Bool`（校验成败）+ 暂存计数改由独立只读属性 `stagedImportStats: (Int, Int)?` 承载（parseStats best-effort，失败为 nil 不影响 Bool）——与 BK-2 清理联动：staged 计数若无人读则连此属性一并不要，stageImport 只回 Bool（默认取向：不要，见 §3.2）。
- BackupView 确认钮改按 ImportOutcome 分支：`.success(stats)` → 有 stats 走 `status.imported` {n}/{m}；stats 为 nil 走无计数成功文案（需核语言包有无现成键；无则用 `backup.hist_restored`「从本地文件恢复」同义键或新增五语键一条，放行时定）。`.failure` → `status.import_error` 不变。

### 3.2 BK-2：死字段清理

- 删 `BackupUI.stagedStats` 字段与 :19126 赋值行；fileImporter 回调改 `if library.stageImport(from: url)`（Bool）。
- 清理后全仓 grep `stagedStats` 零命中为验收据（红线：退役即零残留）。

### 3.3 BK-3：toast 锚点后移

- BackupView .sheet 的 ShareSheet(url:) 补 `onComplete`：completed==true → showToast(status.shared)；completed==false（取消/失败）→ 不弹（error 非空时可记 Diag 一行，落码时定）。
- 确认钮处删即时 showToast(status.shared)；导出失败路（exportZip 回 nil → status.export_failed {e}）不变。
- ShareSheet 本体零改动（回调现成）。

### 3.4 断言与自检（随落码）

- verify_ios.sh 新增/续组（组号放行时按当时占用顺延）：① `commitStagedImport` 返回 ImportOutcome 且函数体内 recordOp(ok:false) 不出现在 importBackup 成功点之后（结构锚：成功点与 catch 分离、reload 在成败域外）；② `stagedStats` 全仓零命中；③ BackupView .sheet 传 onComplete 且 status.shared 的 showToast 只在回调内出现（计数锁）。
- 本机自跑相关组 + MomentApp primary 遍类型检查零错误（口径同各批）。
- 真机终判点（写入组版报告）：导入一份真实备份 ZIP，成功 toast 计数与库实际篇数对账；导出后在分享面板点取消——不应出现「文件已分享」toast，完成一次真实保存/发送后才出现。

## 4. 销项复核（审计中与备份相邻、经核已办/不属本批）

- **桥快照链**（impl_bridge_m2 已落、0.9.54）：写前必拍、保留 10 份/7 天、FFI 直调 exportBackup 不污染备份新鲜度——红线守恒对象，本批零触碰。
- **只读门面 import 拦截**（impl_rescue_r2r3）：commitStagedImport 已挂 writeBlocked("import")，现行代码在位（:1756）。
- **实况挂点**（impl_entitlements_b §5.3）：exportZip / commitStagedImport 的 Live Activity 起止已落，现行代码在位（:1627-1637、:1762-1772）；BK-1 设计保持 importOk 语义与挂点收口不变（仅 reload 移出成败域后 importOk 置点更准）。
- **确认底表形态**（audit_detail_settings C6 + 用户定案）：自绘底表、透明遮罩、250ms 弹簧仅淡入、maxWidth 600 已落地（现行 backupConfirmSheet），横屏/宽屏审计复核达标（landscape §一浮层行、§二·5）。BK-3 只动其钮后 toast 时机，不动形态。
- **备份页 UI 度量/文案族**（audit_detail_settings C1-C10、audit2_settings S3-S6/M2）：hero 度量、toast 全宽条、opMessage 映射等已由设置族各批逐项收口，现行代码注释逐项留痕（S5/M2/C3/C4/C10 等在位）；landscape 审计对吐司判「与 Web 逐值等价、达标」。不属本批三项清单，不重开。
- **landscape L-6**：对象为背景色底表横屏余量，非备份确认底表（备份确认底表同审计判达标、总占高约 238 < 393），不属本批。
- **救援页导出 ZIP 置灰**（audit_home_other §5.4）：meta+动作内 guard 双保险、只读/安全模式口径已核达标，属救援面，不属本批。

## 5. 停门回报

- 清单 3 项（BK-1/2/3）逐项现行形态核对完毕：均未办、均可在 Library/BackupView 两面内根治、均不触守恒红线。
- 待主线确认的两个小口径（放行时一并定，不阻塞设计）：① BK-2 默认清理 stagedStats（改判补呈现则加五语键一条）；② BK-1 成功但计数未知的 toast 文案取现成键还是新增键。
- 放行条件：0.9.58 组版提交收口、工作树净。本报告落盘后停门，不落码、不提交、不 bump。
