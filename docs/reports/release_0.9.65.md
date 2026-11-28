# 组版报告 0.9.65（build 92）

2026-11-28 组版。基线 1f59251（0.9.64 发布笔）→ 本版入料 9 笔 + 本 release 笔（与版本号 bump 同笔，CI 不变量 WORKFLOW §3.2）。本版主线：0.9.64 装机后桥自办立项三件收口（拖拽拾起面高定案根治 / 首页行注册面对账根治 / Diag 回溯窗口定案后扩容）、用户裁定两件落地（背景色采样整套去除、Diag 双端扩容 2000）、M3 快照恢复工具与第四景真接线（中继清单 36→37）。Web 本轮有实改（diag.rs CAP 2000），随版部署生产（见 §三）。

## 一、本版内容（按批分组）

| # | 批 | 内容 | 定案 |
|---|---|---|---|
| 1 | M3 快照恢复（3259529） | `backup_restore_snapshot` 工具落地：ops 门 + 两段提交 + 恢复前强制再快照（可逆）+ 在席守卫，换库复用既有 validate-then-swap 链；snapshot_restore_drill 摘 wiring_missing 真接线（自取快照/软删变更/恢复守卫/三面断言 + arm 武装门第三重）；清单 36→37、哈希 1c2fe22e…；连接器 ALLOWED_TOOLS 与 CONNECTOR.md 同批同步 | impl_bridge_backup_restore.md |
| 2 | Diag 回溯定案（b64f810） | 0.9.64 装机后 Diag 只能回溯到当日 12:05 的定案：300 行当天环容量滚动（设计内、与 Web CAP 同源）挤出早行，读路径同源、分页游标排除；非缺陷，处置登记待裁（后由批 6 扩容裁定收口） | diag_reachback_attribution.md |
| 3 | 拖拽拾起面高根治（94c9ab2） | drag_pickup_statemachine 步 2 定案 proven：face 通道对 quote 回报含块外距的面高（51）vs 行盒高（31），差 20 = 块上下外距；根治 = BlockState.height 改行盒高单点（两写同源、contentH 分流），景对读口径同步；新增 U68-8 | fix_drag_pickup_quote_face.md |
| 4 | 背景色采样整套去除（71b6354） | 用户裁定：状态栏背景色采样全拆——采样两文件（MomentStatusBar.swift / MomentStatusBarBridge.swift）整删、编辑/图片/开屏承载摘登记与 evaluate override、根观察器退役、开屏公式色（bandAverageColor/SplashBandColor）与 artwork 数值表整表退役；状态栏字色全页回平台默认（trait 决定）；SB-8 开屏方向锁保留；构建遍数 31→29 与跨组遍数锁同步；verify [53] 改判（SB-1 零残留锁/SB-2 构建接线/SB-8 原样） | remove_statusbar_sampling.md |
| 5 | 首页行注册面对账根治（5407a12 + 3c5222d + 89df0e5 + 641689f） | 0.9.64 U5 三景红同层定案：home.row 注册/注销骑 List 细胞生命周期，删行残留成幽灵行、新行发布迟到；根治 = 注册/注销脱离细胞生命周期、改呈现行集对账单点（RowFrameStore 对账三触发 + 注销连帧清 + 行面状态 liveMemo 现查 + 折叠派生单点），景侧等发布 + 自密封；新增 [69] HR69 六条；HOM-18 行半边关闭（注册面侧），矩阵回写；两条断言基数改判（F30-2 13→11、HM65-5 段内 4→2，辞焦单点化沿革） | fix_home_row_registry.md |
| 6 | Diag 扩容双端 2000（26bfc01 对账重入账） | 用户裁定：当天环 300→2000——原生 DiagLog 裁剪点单点改 2000、Web diag.rs CAP 同值改 2000（文件头口径 + 架构设计.md 同步）；双锁防漂移（verify_ios [12] J12-2 + verify_rustweb §20）；本笔为对账重入账：原 Diag 批提交被并行线历史重建挤出，组版以临时索引从 HEAD 按 hunk 分拣只取 Diag 段重新成笔，内容以改动清单为准 | fix_diag_cap_2000.md |

## 二、组版收敛项（逐项办结登记）

- **基线复核**：开工 HEAD = 26bfc01、工作区全干净，与主线对账一致，无索引污染需重建（本版各批已按临时索引纪律成笔）。
- **中继部署**：bridge/relay 经 deploy.py 部署（PUT 200、subdomain 200），GET /health = version 1.1.0；list-tools **37 件**含 backup_restore_snapshot 与 metrics_drag_trace；按 worker.js 口径（sha256(protocol + "|" + 排序工具名)）复算 manifestHash = **1c2fe22e…**，与 App 侧 MomentBridgeProtocol 注记三方一致（端内实读待装机后桥自办对账）。
- **tree 同步与普查**：push_small 全量传输（名单含 MomentBridgeRestore.swift、不含状态栏两文件）；overlay → 克隆按名单逐个 cp（禁通配，0.9.64 卫生红前车之鉴）；**显式删除克隆与 overlay 内 MomentStatusBar.swift / MomentStatusBarBridge.swift 残留副本**（71b6354 登记项办结）；普查：克隆 app 目录文件集合 35 件与本地逐字一致（无多无缺）、关键文件 md5 全等。另：克隆 web/src/diag.rs 与本仓 diff 恰为 CAP 扩容两处，本仓版已同步入克隆（Web 构建基线对账）。
- **签名工具**：macho-entitle 本机源码与 tree 副本 md5 同为 c2cf6bb7118512690c7692e0cc31014f（与 0.9.63/0.9.64 基线一致），构建前核对通过。
- **bump 两处**：build-app2.sh（0.9.65 / build 92）+ 设置页版本文本（MomentApp.swift），与本报告同笔；bump 后两文件已重传 tree 并 cp 入克隆（md5 对账一致），冒烟构建即本版号。
- **tree /data 余量注记**：组版时点 tree /data 余约 1.7G（91.2%），与 0.9.64 时点同水位、历轮冒烟产物量级可容纳，未在本轮扩容。

## 三、验证

- **本机门**：cargo test --workspace 全绿（0 failed）；verify_ios.sh 全量 **695 ✓ / 2 ✗**，2 红为已知产物红（[5] ipa 陈旧、[9] 产物语言包），源码面归零（含 [1] 版本三处对账、[12] J12-2 双端 2000 锁、[53] SB 改判、[67] B67-7 快照景、[68] U68-8、[69] HR69）；verify_rustweb §20 双锁在 Web 部署前随静态门复跑。
- **tree 冒烟 / CI / ipa 复验 / Web 部署**：结果登记于组版回报（与 0.9.64 口径同：报告不再为此二次改动，以免破坏 bump 同笔不变量）；红先定性分账（源码红/产物红/卫生红）、不改判。
- **Web 生产**：本轮有实改——diag.rs CAP 2000（双端扩容的 Web 半边）。部署口径照 §3.9/开发规范第四节：tree 构建（MOMENT_SQLITE=1，与现网同口径）→ verify_rustweb 全过 → 干净 dist 归档 releases/<新戳> → staging 注入天气双 key → deploy_api.py 部署 canopies-moment → verify_live 核对 LIVE == ARCHIVE；现行戳 9b2efd68ee 将被新戳取代，新戳登记于组版回报。

## 四、真机终判点（汇全，归用户装机后验；桥自办项由主线装后自跑）

1. **状态栏回系统默认**：全页（首页/设置族/编辑/图片/救援/开屏）状态栏字色由系统 trait 平台默认决定，不再随背景采样翻转；**开屏浅外观下深字落品牌蓝渐变带为裁定内形态**（公式色已退役，不按异常报）；开屏 iPhone 方向锁（SB-8）不回归、iPad 不受影响。
2. **drag_pickup_statemachine 全程复跑（装后自办）**：步 2 face_equals_row 转过（quote 面高 = 行盒高）；步 3–5（heading / callout / codeBlock 段）首验；lift_gaps 探针在 quote 上复读 faceInsets（bottom 应由 −20 归 0）。
3. **U5 三景复跑 + home_geometry（装后自办）**：home_search_cycle / home_surface_roundtrip / home_list_actions 各两遍转过；home_list_actions 封面断言应直接读到 live coverPair；home_geometry 探针复读应无幽灵行、cardGaps 无负值。
4. **快照恢复全链（装后自办）**：snapshot_restore_drill 带 armRestore 连跑两遍；backup_restore_snapshot 工具直调一轮（dryRun 取令牌 → 执行 → 回执 preRestoreSnapshotId 在位、verifyStore 对账）；端内清单哈希与中继 1c2fe22e… 实读对账。
5. **Diag 回溯复验（装后自办）**：场景连跑密集日抽查——当日早行（2000 行窗口内）经 diag_tail / diag_search 分页可达，与定案复刻结论对读。
6. **沿革挂账（0.9.64 §四未验项续）**：标题居中二修目检、块内 GIF 五面、卡片防误触手感、权限页六项体感、0.9.63 余项（八色白字/前向删除/顶距 81/恐龙构图/配对不跳 Safari 等）——随本版一并目检。
