# LAUNCH 判读误报根治（LCH-02）— 设计（停门待放行，2026-11-27）

> 状态：**设计完成、未落码**。落码门：0.9.58 组版提交全落定、工作树净；门前只做只读通读与本设计。
> 出处：docs/reports/audit_home_other_deep.md §1 P2-8 / §5.2（LCH-02）。
> 对账基线：救援完整性批（impl_rescue_integrity.md）已落形态 + 设计时工作树现行代码（行号以该时点为准）。
> 纪律：桥布防 `take()` 先删后判与判定点无条件消费、救援防循环口径——本批设计全程禁动（见 §3.6）。

---

## 0. 对账结论：LCH-02 四子项，两项已根治、两项归本批

审计 §5.2 列四差 (a)(b)(c)(d)，先逐项对账现行代码，防重复劳动：

| 子项 | 内容 | 现状 |
|---|---|---|
| (c) P3 | 哨兵 launchMark/markScene 无锁 RMW 竞态，步名可回退/丢失 | **已根治**（救援完整性批）：`LaunchSentinelStore.update` NSLock 锁内读改写收敛全部 8 个 RMW 写点，verify R13-10 在位。本批不重做 |
| (d) P3 | streak 虚增：安全模式内被强杀时步仍停原加载步、展示值单调虚增 | **已根治**（救援完整性批）：`LaunchStep.sceneRescue` 步名 + RescueView.onAppear 推进，R13-10 同锁。本批不重做 |
| (a) P2 | **误报面**：加载步内强杀/jetsam/真崩溃代码上不可分，一律 streak+1、两次即进安全模式 | **未处置，归本批**（§2 F1/F2、§3.2/§3.4） |
| (b) P3 | **漏报面**：退后台清 busy 后被杀恒不留痕；load 中途退后台→清标→后台被杀，加载期死亡被吞 | **未处置，归本批**（§2 F3/F4、§3.3） |

审计对 (a) 的原提案仅为「把口径写入 LCH-02 已知误报注记」。按主线口径——**能修条件不只加注记**——本批以判读条件修正为主：(a) 的主形态（跨步散射合并计数）是条件缺陷、可根治（§3.2）；只有同一步外部终止不可分一面属平台事实、条件不可修，才走注记+呈现销账（§3.4），且不假装根治。

---

## 1. 现行判读全链（通读账）

**哨兵本体（MomentLaunch.swift）**
- `LaunchStep`：步名集中定义（开库/开库·FFI/读数据·列表/读数据·解析/写种子/再水化·待删/附件名表/附件类型/首帧/会话中/场景·首页/场景·编辑页/场景·救援）；`isLoadStep` 以「会话/场景」前缀与首帧判非加载步，其余皆加载步。
- `LaunchSentinel{Codable}`：字段仅 `busy / step / streak / lastRescueAction / lastRescueAt`——**无步时戳、无 streak 锚步、无挂起墓碑**（此三缺为 §2 根因的载体）。
- `LaunchSentinelStore`：diag 域文件 `.atomic` 直写；`load()` 文件优先、解码失败回退 UserDefaults 三键；`update` 串行收敛（(c) 根治点）。

**写点（MomentApp.swift Library）**
- `launchMark(step)`：busy=true + step=step（经 update）。
- `loadStepMark(step)`：reload 内步点专用，哨兵已进非加载步时不倒退。
- `launchDone()`：streak 清零（一笔 update）+ launchMark(会话中)——G2 全会话口径：不清 busy。
- `markScene(scene)`（static）：busy 时改 step。
- `launchSuspend()`（static）：**无条件 busy=false**，不记挂起时步名。
- `launchResume()`（static）：!busy 时 busy=true 且 **step 直接写「会话中」**，不恢复挂起前步名。
- `launchFailed()`：开库失败路 busy=false（已知失败不计数）。

**判定（judgePreviousLaunch，Library.init 同步段，三路「先定源者赢」）**
- streak 路：busy && isLoadStep(step) → streak+1 落盘；≥2 定 safe(source=streak)、≥3 置 notice、==1 置 launchOnceNoticePending（load 成功收尾消费为 notice.launch_once 一次提示）；busy && 非加载步 → warn 行「疑似前台崩溃或被系统终止」不计数。
- OPS 路：normal 时 forceSafeMode 定源。
- 桥布防路：无条件 `take()` 消费恰一次，仅 normal 时定源（禁动面）。

**接线与呈现**
- scenePhase（根视图 onChange）：.background → E4 编辑冲刷 → launchSuspend()；.active → launchResume()。load 在途与否不传给这两个函数。
- RescueView 状态区：prevStep 行 + streak 行（MomentRescue.swift 状态区，只读呈现）；快照环 RescueSnapshot 记 prevStep/streak；Diag LAUNCH 行两式（error 未完成 / warn 未收尾）。

---

## 2. 误报/漏报形态与根因（逐项）

**F1 误报·跨步散射合并计数**（(a) 主形态，机制 proven）
streak 是无锚的单一计数：任意两次相邻的加载步死亡即凑满 ≥2 进安全模式，与两次死亡是否同源无关。典型误报链：某次冷启在「开库」步被用户强杀（streak=1），下次冷启在「读数据·解析」步被系统 jetsam（内存压力恰在加载期最高）——两起互不相关的外部终止被合并判为「启动期连续死亡」进安全模式。**根因：计数的语义宣称是「启动期确定性死亡循环」（0.9.43 型故障的防护目标），但计数条件只验「死在加载步」、不验「死在同一步」；确定性崩溃的证据形态是同一步复现，条件与语义不对齐。**

**F2 误报·同一步外部终止不可分**（(a) 残余，平台事实）
同一加载步内强杀×2 / jetsam×2 与真崩溃×2，App 侧无任何可同步读取的信号可分：iOS 无「上次退出原因」API；MetricKit 的 MXAppExitMetric 只有按日聚合的退出类别累计计数，送达时机不定、不可归因到紧邻的上一次启动，进不了 init 同步判定。此面**条件不可修**，处置 = 注记 + 呈现销账（§3.4），报告口径如实标平台事实，不冒充根治。

**F3 漏报·加载中退后台被杀零留痕**（(b)，机制 proven）
load 未完时退后台 → launchSuspend 无条件清 busy → 后台被系统回收 → 下次判定见 busy=false：连 warn 行都不出，加载期死亡被静默吞掉（审计 (b) 后半例）。**根因：suspend 把「正常收尾」与「加载未完即挂起」压成同一动作、不留墓碑**——清标的本意是「后台回收不算未收尾」（G2 设计口径，正确），但连「加载曾被挂起中断」这一事实痕迹一并抹掉，判读面全盲。

**F4 漏报相邻·resume 伪造步名**（本批通读新发现，机制 proven）
加载中退后台 → 回前台时 launchResume 把 step 直接写成「会话中」，而 load 尚在途（load 步在后台队列续跑，resume 不查完成态）。其后若进程死在剩余加载步，判定见非加载步 → 降级为「前台终止 warn 不计数」，加载期死亡被错分、streak 证据链断裂。**根因：suspend/resume 不是保存/恢复对——suspend 丢弃步名、resume 单方造步**，两函数各自为政、无单点语义。

---

## 3. 修订口径（落码设计，放行后照此执行）

### 3.1 哨兵 schema 扩展（MomentLaunch.swift，单点）

`LaunchSentinel` 增两字段：
- `streakStep: String = ""`——当前 streak 的锚步（streak>0 时有效）。
- `suspendedStep: String = ""`——最近一次 launchSuspend 时的步名墓碑（"" = 未挂起/已恢复）。

**兼容纪律（承重）**：Swift synthesized Codable 对缺键不容忍（非 Optional 字段缺键即解码失败、声明默认值不兜底），而 `load()` 解码失败会回退 UserDefaults——若直接加字段，升级后首次启动将静默丢失全部哨兵证据。故新字段必须经自定义 `init(from:)` 以 `decodeIfPresent` 兜底（或等价手写解码），保证旧版哨兵文件可读；编码侧仍全字段写出。verify 增构建期锚锁此兜底在位（§3.5）。

### 3.2 streak 路改同一步锚定（judgePreviousLaunch 内，判读条件收敛点）

- busy && isLoadStep(prevStep) 时：
  - `prevStep == streakStep` → newStreak = streak + 1（同一步复现）；
  - 否则 → newStreak = 1、streakStep = prevStep（**换锚重计**，旧锚证据作废）。
  - streak 与 streakStep 经既有串行 update 一笔落盘。
- 阈值与下游口径**全不变**：≥2 定 safe(source=streak)、≥3 notice、==1 成功后提示一次。变化的只有计数条件：进安全模式收敛为「**同一步连续死亡 ≥2**」，与确定性死循环的证据形态对齐——原防护面不减（确定性崩溃恒死在同一步，0.9.43 型仍两次进安全模式）；散射外部终止（F1）不再合并。
- `launchDone()` 清零面扩为 streak 与 streakStep **一并清**（成功收尾 = 证据链断开，锚不残留）。
- LAUNCH error 行附锚信息：同一步复现与换锚重计行文可辨（行前缀与既有格式一致、便于 grep；具体行文落码时定），并附 F2 口径短注记（见 §3.4）。
- Library 新增呈现字段 `prevLaunchStreakStep`，与 prevLaunchStep/prevLaunchStreak 在判定点同点赋值，供 §3.4 消费。

### 3.3 suspend/resume 改保存/恢复对（治 F3+F4，落点在两函数内）

- `launchSuspend()`：一笔 update 内先记墓碑再清标——`suspendedStep = s.step; busy = false`。其余口径不变：仍不计数、不进判定，G2「退后台不误报」守恒。
- `launchResume()`：!busy 时恢复 `step = suspendedStep 非空 ? suspendedStep : 会话中`，并清 suspendedStep；busy 时不动（现行语义）。效果：加载后挂起恢复 → 步为「会话中」与现行一致；加载中挂起恢复 → 步回到原加载步，在途 load 的后续 loadStepMark 自然接续（其「不倒退」守卫以加载步为界、与恢复步同域不冲突），F4 错分消除。
- **判定侧墓碑消费**（judgePreviousLaunch 新增只读观察分支，**不动三路定源**）：busy==false 且 suspendedStep 为加载步（= 上次加载未完即挂起、其后未见 resume/launchDone 收尾，即挂起后被杀或直接冷启）→ 记一条 warn 行（口径：「上次加载未完成即退后台（停在：<step>），其后未回前台收尾——后台回收不计数」）并一笔 update 清墓碑。busy==true 时不消费（resume 已清或已被 launchMark 链覆盖，防重复记行）。**此行只留痕、不计数、不写 bootMode**——漏报面的根治目标是「有痕可判」，不是把后台回收升级成死亡证据（那会反向制造误报面）。

### 3.4 呈现与注记（F2 销账面）

- RescueView 状态区：streak 行附锚步（「N · 锚步 <step>」同行呈现或新增一行，落码时按状态区行格统一）；快照环 RescueSnapshot 增 `streakStep` 字段（同 §3.1 兼容纪律），导出文本行附带——用户在救援页即可见「连续死亡是否同一步」，配合既有 prevStep 行销 F2 大半（审计原注记提案的呈现落点在此）。
- LAUNCH 行注记：§3.2 的 error 行尾附固定短注记，标明同一步内强杀/系统回收与崩溃不可分（平台事实），防 Diag 判读者把 streak 触发一律读作真崩溃。
- plan_selftest_coverage.md LCH-02 行改写（矩阵纪律：先改矩阵再落断言）：由「已知误报口径注记」升级为现行口径表述——同一步锚定计数、散射不合并、墓碑留痕、残余不可分面与呈现销账点。

### 3.5 断言设计（verify_ios.sh [13] 续号，落码批执行）

- **R13-13** 哨兵 schema：streakStep/suspendedStep 字段 + decodeIfPresent 兜底在位（计数锁）。
- **R13-14** streak 锚定：judge 段含锚步比对分支与换锚赋值；launchDone 清零面含 streakStep（grep 锚）。
- **R13-15** suspend/resume 对 + 墓碑消费：launchSuspend 写 suspendedStep、launchResume 读 suspendedStep 恢复（两函数体锚）；judge 墓碑 warn 行字面量在位，且该分支段内无 bootMode 赋值（静态核查，只留痕不
...[truncated 2087 chars]