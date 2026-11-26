# 原生诊断 + 自救机制与 Web 对齐清点（2026-11-26）

用户 2026-11-26 下达：原生 iOS 的诊断覆盖（全页面/功能/模块）与自救机制（救援层、看门狗、修复入口、降级与隔离等）须与 Rust Web 版全面对齐；同日点明：诊断页必须有日志显示记录，显示层与打点覆盖缺一不可。

本文件是双线清点（Web 家底 vs 原生现状）的落盘版，兼作落码批序依据。状态：清点完成、落码未开始（2026-11-26）。

## 一、Web 侧家底（proven）

### 诊断管线（diag.rs，全 1143 行）

- 内存环 300 行 + 落盘键 `moment_diag_v1`，1s 节流合并写；`flush_persist` 使 ERR 行与 pagehide 立即刷盘。
- 行格式 `[HH:MM:SS] TAG msg`；warn/error 在时间括号内加 W/E。
- API：`log` / `log_warn` / `log_once`（同 key 每会话一次）/ `log_err`（立即落盘 + 去重 + 错误徽章）。
- 按天冻结归档 `moment_diag_archives_v1`，上限 60 份，超限丢弃记 WARN；自动删除偏好默认关；等级过滤只动呈现、导出全量。
- 全局 error / unhandledrejection 钩只旁路记录；panic 钩在 abort 前同步直写专用键 `moment_panic_v1`（上限 20），下次启动 drain 折入 PANIC 行。
- 结果侧量测仪器：`log_probe` / `log_census` / `log_late`（300/1000/3000ms 重采样）/ `log_modal`。
- Diag 页：自动删除行、等级行、归档胶囊流、当天绿字卡；DiagLogPage 与图片页同级，系统分享导出，导出结局记 DIAG 行。
- 全应用 `diag::` 调用点共 340 处（main.rs 50、persist.rs 37、idb.rs 9、editor 系约 120、blocks.rs 24、weather.rs 10、settings/backup 20 等）。口径 = 意图/结果成对、结果带实测值。persist.rs 的结果侧打点含：实际后端、读源、写入字节、对账漂移、池身份 fp hash。

### 自救机制

- index.html 救援层（先于 wasm 执行）：每次加载写状态快照 `moment_rescue_log_v1`（环 20，只记元数据绝不记值：SW 注册 / Cache 键 / IDB 库表 / localStorage 键名长度）。
- 存活标记 `moment_boot_ok`（diag::init 后 2s 写）+ 12s 看门狗：未活出底部救援条；活过来每 2s 轮询自撤。`?rescue=1` 直达面板。
- 面板动作：导出诊断（.txt 系统分享/下载兜底）；修复启动 repairBoot（**只注销 SW + 清 Cache Storage 后无参重载，绝不动 IDB / localStorage / OPFS**）；存储后端开关（只写 `moment_backend_v1` = idb/auto 后重载）。动作先落救援日志，下次启动 drain 成 RESCUE 行。
- SW 更新提示条：点才更新、× 按 VERSION 戳记同版不重弹、事件暂存 `moment_swupd_pending_v1` 启动 drain 成 SWUPD 行。
- 存储状态四值经 listener 推呈现：多标签独占阻断页（重试 = nudge 催促、第一标签关闭自动接管）；sqlite 硬失败阻断页（重试 = 整页重载）；dual 硬失败只读降级横幅（写路径门面 `writes_blocked` 统一拒绝）；会话 IDB 降级横幅（ephemeral 无痕支「数据不保存」/ session 支）。
- 逐篇隔离 quarantine：隔离落 IDB kv 键 `quarantine_json`；落盘失败则整次加载阻断；导出 ZIP 附 quarantine.json。
- 加载期自愈：pending-delete 过期清理/重水化、pending input 恢复、种子置顶 retarget、改名迁移失败保留旧库续跑、会话降级下次冷启自动再迁移回 SQLite。
- 错误徽章 errbadge：第二取证面、上限 20、可展开 clear。
- Worker install 失败按步结构化分类（GetDirHandle=directory / CreateSyncAccessHandle=handle=真锁冲突 / GetFileHandle=file / Vfs=register / NotSupported=unsupported / ImportDb=import）；仅 handle 步判 Occupied 走等待接管（重建 Worker 再试、250ms×8 后 5s 退避、每轮重估可转轨），其余步立即分流；隐私签名（UnknownError + unknown transient / directory 步 SecurityError）判 ephemeral。

## 二、原生现状与缺口（proven，按严重度）

### 基础设施

DiagLog 在：300 行环、today.json + archives.json 落盘、归档上限 60、自动删除开关、DiagView 当天卡显最后 8 行 + DiagLogPage 逐页分享导出、Phase0 自检卡（自检链已于 0.9.12 按用户评估去除，卡改名「库状态」保留真实库读数）。但：

- 落盘逐条全量重写、无节流（性能放大）；读写 `try?` 静默；导出只能逐页、无全量一键；归档戳为冻结时刻而非日志当天。
- 打点仅 27 处（启动 1 结果行、备份 5、天气 9、CARD 2、EDIT 3、SCROLL/DRAG 3、删除/头像各 1 且记意图）。首页列表、搜索、设置族、图片页、各块型视图、编辑操作（撤销重做/斜杠/块操作/单篇导出）、MD 预览降级、图片/视频加载失败全无打点。
- FFI 错误处理三形态并存不统一（do-catch + Diag 仅 load/export/import 三处；search do-catch 无 Diag；其余约 45 处 `try?` 全静默）；md_* 非抛错函数的降级 Swift 无从知晓；Rust panic 跨 UniFFI 即 abort、无捕获层。

### 会丢数据级缺口（最高优先）

1. **persist 全静默**（MomentApp.swift 约 :479-486）：序列化失败 guard return、upsert `try?` 吞错、内存列表先行更新——编辑丢失零感知零日志，全文件最严重。
2. **单篇坏数据整库不可见**：storage `list_memos` 逐行 `serde_json::from_str(&row?)?`（crates/storage/src/lib.rs 约 :281-291）一行坏全表抛错 + Swift parse 顶层失败回 [] 假空库；core migrate 的逐篇隔离未接原生读取链。
3. **exportZip 假成功**（约 :541-556）：lib == nil 时 `try lib?.` 可选链不抛错、直落成功分支、记 ok + 返回不存在的文件 URL——开库失败时救援导出恰不可用。
4. **putAttachment 静默失败**（约 :515-517 + 调用点 :2740/4716/4727/4767）：块引用不存在的 fileId、附件永久缺失。

### 静默失败级

5. 启动硬崩无留痕：面包屑 timing 只在内存不落盘；无看门狗 / 崩溃环检测 / 安全模式；@main（约 :9266）零防护。
6. retryLoad 二次失败被 `try?` 吞（约 :385-389），失败态跌落假空态。
7. 搜索 FFI 失败 catch 吞成空结果、无打点（约 :861）。
8. 删除/头像 Diag 在 `try?` 后无条件记成功行（意图冒充结果，约 :424/:830）。
9. `Library.notice` 横幅（约 :532 声明、ListView 约 :8047 呈现）零赋值点、空壳。

### 结构性现状

- 隔离仅一条：diag/ 与 library/ 目录分离，库坏时日志仍可看。
- 导入恢复链完整且安全（storage 单事务换库、坏包不污染）。
- 数据修复入口：无（Diag 页只有查看/导出/自检）。

## 三、落码批序（拟定）

- **批 A 数据级**：persist 结果回路（序列化/upsert 失败记 error + notice 横幅告知）；exportZip 加 lib == nil 守卫走失败分支；putAttachment 改回 Bool、失败记 error 且调用点留痕；storage list_memos 逐行容错——解析失败行原文 stash 进 meta 隔离键（仿 Web `quarantine_json`）并跳过，FFI `list_memos_json` 改包装形 `{"memos":[...],"quarantined":n}`（签名不变、免 bindgen 重生，Swift parse 双形兼容），load 时记隔离数；retryLoad 按 reload 结局置 loadFailed。
- **批 B 启动自救**：启动进行中标记 + 完成清除；上次未完成 → Diag error 记 LAUNCH 行，连续未完成 ≥3 出 notice 建议导出诊断/备份；面包屑步骤同步落 UserDefaults、下次启动折入 Diag；notice 通道正式启用。
- **批 C 覆盖面**：列表/搜索/设置/图片页/块型/编辑操作/单篇导出/加载失败逐项补结果侧打点；DiagLog 落盘改 1s 节流合并 + error 行立即刷；Phase0 报告摘要入 DiagLog（注：自检链已去除，此项改为库状态读数在打开 Diag 页时记一行）；DiagView 全量一键导出（当天 + 全部归档一文件）+ 导出动作记行；归档戳改日志当天。

每批独立提交 + 构建。

## 完成注记（2026-11-26）

- **批 A ✅ 0.9.15（49ada69）**：storage `list_memos_tolerant` 逐行容错 + `merge_quarantine` 并入 meta `quarantine_json`（stash 落盘失败整体报错）；导出走容错版并附 quarantine.json；FFI 包装形（Swift 双形兼容）；persist 结果回路（成功才同步内存列表）；exportZip lib==nil 守卫；putAttachment 回 Bool 并四调用点结果侧处理；retryLoad 按结局置位。
- **批 B ✅ 0.9.17（8daa440）**：启动守卫三键（launchInProgress/launchStep/launchCrashStreak），面包屑开库/写种子/读数据，LAUNCH error 行 + ≥3 次 notice。**真机实证（2026-11-26 17:11 日志）**：0.9.17 的 UniFFI checksum 闪退被完整记录——8 次启动均停在「开库」步，与 .ips 崩溃点（MomentLibrary.open 断言）吻合；0.9.18 修复后 SMOKE 行接续、无第 9 次。
- **批 C ✅ 0.9.18（f93aa81）**：DiagLog 落盘 1s 节流合并 + error 立即刷；归档戳改日志当天；DiagView 全量一键导出；结果侧打点补齐（删除/头像 do/catch、搜索失败与 0 命中、撤销/重做余栈深、单篇导出/PDF 结局、图片加载失败、图片页打开）。取舍记录：块型视图逐块打点不加（Diag 是排障工具，Web editor 系打点多为量测仪器而非逐块一行）。
- **连带（同日）**：冷启 SMOKE 冒烟行（v/篇数/首帧/数据耗时）随 0.9.18 落地，真机冒烟证据链 = SMOKE（成功）+ LAUNCH（未完成）双行；防回归门 verify_ios.sh 六组断言 + ffi checksum 契约测试同期落地（UniFFI checksum 含文档注释的教训，见 1dd102e 提交信息）。

## 四、Web 可迁移口径（12 条）

1. 行格式恒定 + W/E 编码等级。
2. `log_once` 去重。
3. ERR 立即落盘。
4. 意图/结果成对、结果带实测值。
5. 关键提交点量测普查 + 延迟重采样。
6. 环 300 + 节流落盘 + 按天冻结 60 + 自动删除删了才记行。
7. 崩溃取证双通道（专用键直写 + 启动 drain；全局错误钩旁路 + 第二取证面）。
8. 救援 UI 与应用解耦、快照只记元数据、存活标记 + 看门狗自撤、动作先落日志后折入。
9. 修复动作只动可再生层、边界文案明示。
10. 失败按步结构化分类，不做文案子串匹配。
11. 降级三分（可写降级 + 横幅 + 标记待自动迁回 / 只读降级 + 门面拒写 / 阻断 + 重试 + 救援入口），经回调推呈现不轮询。
12. 逐篇隔离（独立键、写回不触碰、落盘失败宁阻断、导出随包附出）；更新不强更；键改名逐键搬运校验后删旧。
