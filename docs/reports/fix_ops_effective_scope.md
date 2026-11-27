# OPS 生效口径双轨修订（S13）+ ops_refresh 补 effectiveScope — 设计（停门待放行）

> 状态：**只读准备完成，停门**。0.9.58 组版分拣进行中（HEAD 已推进至 4070d70 bump 笔），本批未动任何源码/中继/连接器；下文为落码设计，放行后照单执行。
> 出处：audit_home_other_deep.md §1 P2-6 / §5.7(a)（LCH-07）；impl_rescue_r1.md S13 落码账。

## 一、定性（proven，全链回源）

「恒下次启动生效」只是**半条真相**。现行 OPS 消费面实为两轴：

**甲轴·启动判定轴（恒下次启动）**——消费点在 `Library.init` 判定段，只读判定入口快照 `bootAppliedOps`（MomentApp.swift:880 赋值、:388 声明）：
- 启动模式判定：streak / OPS forceSafeMode / 桥布防三路（:921 读 bootAppliedOps.forceSafeMode）。
- 看门狗步：`armWatchdog`（:801）在 init 末尾判定段内读 `cached()`——arm 时机即启动期，会话中途刷新既不补 arm 也不撤 arm，**实效等同下次启动**。

**乙轴·会话消费轴（实时，会话中段刷新即改行为）**——消费点全部直读 `OpsDirectives.cached()`（每次调用重读缓存文件）：
- 附件类型 guard：`refreshAttachmentTypes`（MomentApp.swift:1536）——load 期与 didLoad 后会话内刷新共用此点。
- Diag 冻结写盘 guard：`DiagLog.flushStructural`（MomentApp.swift:4103）——全会话持续调用。
- 天气自动刷新 guard：ListView.onAppear（MomentApp.swift:17155）——每次回首页求值。
- 分发器 forceSafeMode 紧缩：MomentBridgeTools.swift:148——**每次工具调用**求值，新拉到的 forceSafeMode 会话中段即收紧受限集（纵深定案，行为本身 fail-safe）。
- 桥步深查：MomentBridgeTools.swift:230/:259（数据写/scenarios 前置门，每次调用读 cached()）——实时。
- try-normal 诚实回读：MomentBridgeOps.swift:227-229（bootApplied ∥ cached() 取并，会话内新置 forceSafeMode 立即如实回 forceSafeStillArmed）。

**丙面·桥启停（混合）**：`BridgeCoordinator.start` 的 opsDisabled 求值（MomentBridge.swift:363）只在桥启动时读一次——点名禁桥对「已启动的桥」不立即停（靠乙轴深查面拦写面），对「下次桥启动」生效。

行为本身全 fail-safe（紧缩方向实时、放松方向恒等下次启动/判定），**失真只在表述与回读**：四处文本宣称单轨「下次启动」——
1. MomentOps.swift `refreshInBackground` 头注（:141-146）：「本次不生效——guard 读的是启动时缓存，热指令下次启动兑现」——与乙轴四面直接矛盾（该函数 :1033 在 didLoad 后触发，落缓存后乙轴立即兑现）。
2. MomentBridgeOps.swift 文件头注（:4-7）：「生效点恒为下次启动（effectiveFrom=next_launch）」。
3. 中继工具描述 bridge/relay/worker.js:154：「生效点为下次启动」。
4. 连接器 CONNECTOR.md:33：「takes effect on next launch」。

且回读面缺字段：`ops_refresh` 回报只有扁平 `effectiveFrom: "next_launch"`（MomentBridgeOps.swift:80），`ops_get_effective` 只有三层集 + converged 布尔（:38-70）——远程判读时无法区分「哪部分已在会话内生效、哪部分待下次启动」，正是 S13 登记的问题。

## 二、单一生效口径（收敛定案，落码时写入上述文本面）

> **OPS 指令分两轴生效：启动判定轴（启动模式判定、看门狗 arm）恒下次启动，以判定快照 bootApplied 为准；会话消费轴（各步 guard、分发器紧缩、桥写面深查）实时读当前缓存，会话中刷新即生效——紧缩立即、放松对已收紧的会话面同样实时，但启动模式本身不在会话内翻转。桥步的启动拦截以下次桥启动为准、会话内靠深查面实时拦截。**

要点：不改任何消费点行为（全 fail-safe 已是定案），只收敛**表述与回读**到与行为一致的单一口径。白名单边界（sanitize 只收 version/disableSteps/forceSafeMode）与双源端点一字不动。

## 三、effectiveScope 字段口径

**构造单点**：`MomentOps.swift` 内新增纯常量构造 `OpsDirectives.effectiveScopeDict()`（无状态、无副作用，与 sanitize 同纪律），`ops_refresh` 与 `ops_get_effective` 两回报共用——口径只有一处定义，防再漂移。

**字段形态**（两回报同名同形）：

```json
"effectiveScope": {
  "launchDecision": "next_launch",
  "stepGuards": "immediate",
  "dispatcherTightening": "immediate",
  "bridgeStartGate": "next_bridge_start",
  "steps": {
    "附件类型": "immediate",
    "Diag冻结写盘": "immediate",
    "天气自动刷新": "immediate",
    "公式预热": "immediate",
    "MCP桥": "mixed",
    "看门狗": "next_launch"
  }
}
```

- 轴字段取值域：`next_launch` / `immediate` / `next_bridge_start`；steps 值域再加 `mixed`（仅 MCP桥：启动拦截 next_bridge_start + 深查 immediate，如实标混合）。
- steps 键 = OpsStep 登记步名全集（六步），与 §5.8 的 guard 点登记表同源；公式预热标 immediate 的依据是其登记口径「新增预热必须先查 isDisabled 才许执行」——按构造在调用时求值（现无消费点，属先行登记，如实注记）。
- forceSafeMode 不入 steps（它不是步）：其双面实效由 launchDecision（判定面 next_launch）与 dispatcherTightening（紧缩面 immediate）两轴字段分别陈述，恰好把双轨讲全。

**兼容裁定**：`ops_refresh` 既有 `effectiveFrom: "next_launch"` **保留不改值**——理由：①中继描述与 verify 现行断言（verify_ios.sh:1273 锁此串）已按它对账，改值是无谓的契约震动；②在新口径下它的语义收窄为「启动判定轴的速记」，由 effectiveScope 作权威全述、头注与连接器文档同步注明此收窄。`rescue_arm_safe_mode` 的 effectiveFrom（MomentBridgeOps.swift:307）**豁免不动**：布防标记确为纯下次启动消费（判定点 take 一次、无任何会话消费面），其 next_launch 表述属实。

## 四、落码清单（放行后执行，本批不含行为改动）

1. `MomentOps.swift`：新增 `effectiveScopeDict()`；改写 refreshInBackground 头注为两轴口径（删「本次不生效」句）。
2. `MomentBridgeOps.swift`：文件头注改两轴口径；opsRefresh 回报加 `effectiveScope`（effectiveFrom 旁注收窄语义）；opsGetEffective 回报加同一 `effectiveScope`。
3. 连接器 `custom.moment-bridge/CONNECTOR.md:33`：改两轴表述 + 注明 effectiveScope 与 effectiveFrom 的分工（连接器在仓外，随批同改、报告留痕）。
4. 中继 worker.js:154 工具描述：**默认不入本批**——改它须中继重部署，与「双源/部署面不动」的稳妥口径冲突；登记为后续项，随下次中继部署窗口顺带改（描述文本不影响行为）。
5. 历史报告（impl_rescue_r1.md 等）原文不回改；本报告即口径修订的沉淀点，audit LCH-07 随之销账。

**相邻项划界**：audit §5.8 的 ops_validate unguardable 步名拆集（P3）与本批同属审计建议的「桥呈现小批」篮子，但不在本批任务书内——单独登记，不在本批顺带落码。

## 五、断言计划（放行后随落码）

verify_ios.sh 在 B16 组续号（B16-6 三层回读组旁）：
- effectiveScope 构造单点：`effectiveScopeDict` 定义恰 1 处（MomentOps.swift）、两回报面各引用 1 次。
- 字段键齐：launchDecision/stepGuards/dispatcherTightening/bridgeStartGate/steps 六键 + steps 六步名在位。
- 漂移文本零残留：app 源码内「本次不生效」「生效点恒为下次启动」两串 grep 归零（退役即删除口径）。
- 既有 B16-6 与 effectiveFrom 断言不改判、继续成立。

## 六、终判口径

- 本机：verify 相关组全绿 + MomentOps/MomentBridgeOps 两 primary 遍类型检查零错误。
- 远程实读（装机后、桥前台窗口）：ops_refresh 回报含 effectiveScope 且 steps 表与本报告一致；会话内实证一例——救援页 checkOps 拉一份点名「天气自动刷新」的指令后回首页，Diag 应见 `OPS skip step=天气自动刷新`（乙轴实时面），且启动模式不翻转（甲轴守恒）。

## 七、门状态

只读准备毕。落码面共 2 个 Swift 文件（注释 + 一个纯函数 + 两处回报加字段）+ 连接器文档一行，零行为改动、零中继动作。**停门待主线放行**（0.9.58 组版提交落定、工作树净后）。

## 八、落码实录（2026-11-27，放行后照单施工）

门已开：HEAD cb8ff18（0.9.58 组版报告笔）、开工快照工作树净。逐项落码：

1. **MomentOps.swift**：`OpsDirectives` 内新增 `effectiveScopeDict()` 纯常量构造（置于 `cached()` 后），四轴键齐（launchDecision=next_launch / stepGuards=immediate / dispatcherTightening=immediate / bridgeStartGate=next_bridge_start），steps 六步以 OpsStep 常量为键引用登记步名（附件类型/Diag冻结写盘/天气自动刷新/公式预热=immediate、MCP桥=mixed、看门狗=next_launch），双轴口径与公式预热先行登记的注记写入函数头注——口径定义全仓仅此一处。`refreshInBackground` 头注改写为双轴口径（删「本次不生效」句，会话消费轴本次会话内即兑现、启动判定轴以下次启动判定快照为准）。
2. **MomentBridgeOps.swift**：文件头注改双轴口径（删「生效点恒为下次启动」句，注明 effectiveFrom 收窄为启动判定轴速记）；`opsGetEffective` 回报加 `effectiveScope`（converged 旁）；`opsRefresh` 回报在 `effectiveFrom` 旁加同一 `effectiveScope` + 收窄语义旁注。两回报各引用构造单点恰 1 次。`rescue_arm_safe_mode` 的 effectiveFrom 按设计豁免未动；白名单与双源端点一字未动；零行为改动（注释 + 纯函数 + 两处回报加字段）。
3. **连接器 CONNECTOR.md**（仓外同批）：ops_refresh 条目改两轴表述，注明 effectiveScope 为权威全述、effectiveFrom 收窄为启动判定轴速记，两回报同报 effectiveScope。
4. **中继 worker.js 工具描述**：按设计默认不入本批，git 复验 bridge/ 零 diff，未部署、未改字，留待下次中继部署窗口顺带。

断言（verify_ios.sh，B16 组续号）：
- **B16-21**：构造单点定义恰 1 处（MomentOps.swift）、两回报引用合计恰 2 次、同名键 `"effectiveScope"` 恰 2 处、四轴键值与六步值逐项在位。
- **B16-22**：漂移文本零残留——「本次不生效」「生效点恒为下次启动」两串在 app 全部 .swift 归零。
- 既有 **B16-6 不改判**、继续成立；B16 全组 27 条（含 QR 子组）全绿。

自检：
- MomentOps / MomentBridgeOps 两 primary 遍（按 build-app2.sh 原序复刻）**零错误**，ops.o（125,904 B）/ bridge_ops.o（172,360 B）均产出。过程留痕：首跑遇同树兄弟批并发编辑 MomentApp.swift 的撕裂读（WeatherService 伪类括号错），文件稳定后按脚本原序重跑即零错误——与本批改动无关。
- verify 全量在本批领地的红项为零；完工时全量余红为产物类 2 条（ipa 陈旧、产物语言包，构建自解）与兄弟批在途项（R13-13 属 LCH-02 批领地、其 MomentLaunch/MomentRescue 正在编辑中；运行中一度出现的五语键数红为兄弟批补键在途态、完工复跑已自敛），均不在本批领地、未越界代修。
- 同树避让：完工 git status 复验，本批 diff 恰为 MomentOps.swift / MomentBridgeOps.swift / verify_ios.sh 三文件（+ 仓外 CONNECTOR.md），兄弟批 hunk（MomentApp/MomentLaunch/MomentRescue/桥设置/lang 五包等）完好未动。

状态：未提交、未 bump，随下一组版分拣。终判口径同 §六（装机后桥实读 ops_refresh 的 effectiveScope + 会话内乙轴实证一例）。
