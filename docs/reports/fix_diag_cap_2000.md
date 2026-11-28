# Diag 当天环扩容 300 → 2000（双端同步）落地报告（2026-11-28）

## 出处

- 定案：[diag_reachback_attribution.md](diag_reachback_attribution.md)
  ——回溯窗口异常根因 = 当天 300 行环形缓冲写满静默挤出早行
  （设计内、非分页缺陷），扩容选项登记待裁。
- 裁定：用户 2026-11-28 选定 (a) 案——扩容到 2000 行、Web/原生
  双端同步。本批落码；**不部署 Web 生产、不出包**（并行期防半
  成品上线，部署留下批组版）。

## 改动点清单

| # | 文件 | 改动 |
|---|---|---|
| 1 | `rust/apps/ios/app/MomentApp.swift` DiagLog.appendEntry | 当天环裁剪点 `today.count > 300 / - 300` → `2000`（全类唯一定义点，通读 DiagLog 全段确认无第二处同值口径）；补沿革注释（裁定出处 + 双锁位置） |
| 2 | `rust/apps/ios/app/MomentApp.swift` 诊断管线段头注释 | 「300 行环」→「2000 行环」 |
| 3 | `rust/apps/web/src/diag.rs` | `const CAP: usize = 300` → `2000`（含 doc 注释记双端同值锁）；文件头注释「上限 300 行」→「上限 2000 行」。CAP 的全部消费点（push_line 裁剪、init 读回 take、panic 钩写 Diag 键裁剪）均引用同一常量、随之同变，无第二定义点 |
| 4 | `架构设计.md` §诊断日志的架构位置 | 「内存 300 行环形缓冲」→「内存 2000 行环形缓冲」（活文档口径同步） |
| 5 | `rust/apps/ios/app/verify_ios.sh` [12] 新增 J12-2 | 断言原生裁剪点 `> 2000 / - 2000` 在位且 Web CAP == 2000 |
| 6 | `scripts/verify_rustweb.sh` 新增 §20 | 断言 Web CAP == 2000、原生裁剪值 == 2000、双端相等（与 J12-2 同锁对侧，任一端漂移两脚本各自判红） |

**提交归属（如实登记）**：#1/#2/#5 所在的两个共享文件
（MomentApp.swift、verify_ios.sh）被并行 drag 线提交 ca6bf55
整文件扫入——本批三处改动已逐字随该笔入史（HEAD 核验：
`today.count > 2000` 在位、J12-2 在位）；本批自有提交只含
#3/#4/#6 与本报告。内容无损、仅归属错位（与此前并行期同型
事故同处置：不改写历史）。

## 普查对账表（全仓 300 消费面逐项）

| 面 | 处置 | 理由 |
|---|---|---|
| 桥 diag 字节守卫 maxDiagBytes 256KB（MomentBridgeProtocol.swift:20） | **不动** | 与环容量正交：tail/search 分页 limit 默认 50/上限 200，byteGuard 超限裁包并回 nextBeforeTs 续读；环扩到 2000 只增加可翻页数（上限约 10 页），单页字节仍由守卫兜底，配合成立 |
| 桥 diag_tail/diag_search 页大小（默认 50、上限 200） | 不动 | 同上，分页机制不随环容量变 |
| Web diag.rs:267 注释「旧实现…序列化 300 行环」 | 不动 | 历史叙述：指节流改造前旧实现当时的环（当时 CAP 即 300），非现行口径声明 |
| Web diag.rs 内 trunc 300 字、log_late 300/1000/3000ms、弹窗重采样 [300,1000] | 不动 | 字符截断与延迟采样，非行数容量 |
| 原生/Web 归档上限 60 份、Web panic 专用键 20 条 | 不动 | 归档份数与 panic 键容量，非当天环 |
| plan_selftest_coverage.md / plan_bridge_m3.md 中的「300 行」 | 不动 | 均为代码行数估算（场景 +300 行等），非 Diag 容量 |
| docs/reports 其余历史报告中的「300 行环」 | 不动 | 历史记录，不回改；现行口径以本报告与架构设计.md 为准 |
| verify 脚本其余 300（布局 avail、时间戳、wasm 预算 2,300,000B 等） | 不动 | 与 Diag 容量无关 |
| TESTING.md、lang 包、连接器文档 | 无命中 | 普查确认无写死 300 的 Diag 条目 |

## 行为等价核对

- 只改容量常数一处/端：归档跨日冻结、logOnce 去重、G10 留痕行
  （归档截断/自动删除）、落盘节流、等级过滤等既有机制一律未碰。
- 裁剪仍静默：用户选扩容案、未选留痕案，未顺手加裁剪留痕行。
- 原生侧扩容后 today.json 落盘体积随之增大（2000 行量级），落盘
  节流（1s 合并/error 立即）不变，无新增写放大点。

## 验证结果（本机，2026-11-28）

- **cargo test --workspace：全绿**（exit 0；moment-core 57+集成
  130、ffi 5、storage 6+3、web 86 等各套件 0 failed）。
- **scripts/verify_rustweb.sh：ALL PASS**，含新 §20「Diag 当天
  环双端容量同值锁：Web CAP = 原生环上限 = 2000」✓。
- **verify_ios.sh：本批面全绿**——J12-1 ✓、J12-2 ✓（首跑因断言
  内相对路径多写一层 `../` 致 Web CAP 取空判红，已修正为
  `../../web/src/diag.rs` 并单点复核在位：webcap=2000、原生标
  记 1/1）。全量红 3 项如实分账：
  - 产物陈旧 2 项（ipa 早于源码、产物语言包未重建）——重建自
    清类，非源码红；
  - HM65-5（列表动作辞焦计数）1 项——**他线在飞红、非本批**：
    其计数窗口（swipeActions/contextMenu 段）在首页线作业面
    内，与 Diag 零交集；判红时点树面实测计数 2/2（期望 4/4），
    为 home 线编辑中途态，归该线落码时对账，本批未动。

## 留账

1. **Web 生产部署**：diag.rs CAP 变更未部署生产，留下批组版随
   版带入（部署后以 verify_live 戳与线上回读复核）。
2. **原生随下版出包**：Swift 侧无本机编译门，tree smoke_ios.sh
   为首次编译门，留下版组版。
3. **装机后回溯窗口复验**：下版装机后在场景连跑日抽查——当日
   早行（≥2000 行窗口内）经 diag_tail/diag_search 分页可达，
   与本定案的复刻结论对读。
