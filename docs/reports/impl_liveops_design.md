# 实况按功能样式设计（impl_liveops_design）

用户 2026-11-28 拍板：实况（Live Activity）按功能做针对性样式设计并落码；
用户实报症状：灵动岛长按展开是一条长黑条。本批只动呈现与步名接线，
引擎（MomentLiveOps.swift）与属性契约（MomentLiveOpsAttributes.swift）
零改动（git diff 实证为空）。

## 一、前提修正（回源实证，与工单转述不符处以源码为准）

- export / restore **已有启动点**，非「只定义枚举」：整库导出
  `Library.exportZip()` 与整库恢复提交 `Library.commitStagedImport()`
  早在权限批 §5.3 已挂 start/end（kind=.export / .restore，标题走
  `liveops.export` / `liveops.import`）。本批未新造接通点，只补步名
  本地化（见 §四）。其余三 kind 挂点亦在位：bridgeOp = 桥分发长操作
  （MomentBridgeTools）、scenario = 自检驱动核（MomentBridgeUITest，
  start/update/end 全程）、bridge = 桥会话收敛单点（MomentBridge）。
- 旧呈现确为一套通用模板：标题 + 步名 + 进度条，kind/phase 均不
  参与渲染，minimal 态为一颗无色 `Circle()`——此为本批改造对象。

## 二、五 kind × 四形态设计表

样式单点 `LiveOpStyle`（MomentLiveOpsWidget.swift，扩展自包含；
跨进程无共享令牌，色取系统语义色族，桥系蓝与主 App accent
0x007AFF 同族）：

| kind | 图标（running） | 主题色 | 语义 |
|---|---|---|---|
| bridgeOp 桥操作 | wrench.and.screwdriver.fill | indigo | 工具执行 |
| scenario 自检场景 | checklist | teal | 逐项核验 |
| export 导出 | square.and.arrow.up.fill | orange | 向外产出 |
| restore 恢复 | square.and.arrow.down.fill | purple | 向内写入 |
| bridge 桥会话 | antenna.radiowaves.left.and.right | blue | 连接在位 |

四形态呈现（同一 kind/phase 映射全形态共用）：

| 形态 | 内容 |
|---|---|
| 锁屏/横幅 | 徽章锚（38pt 圆角方底 + 白色阶段图标）+ 标题行（右侧：opDetail 指纹短记优先，否则 done/total 计数）+ 步名 + 进度；卡面以 kind 主题色 0.5 淡染（activityBackgroundTint，16.2+，低版回落系统默认） |
| 灵动岛展开 | leading：徽章（30pt）+ 标题（2 行）；trailing：计数（阶段色等宽数字）或阶段图标；bottom：步名行（右侧 opDetail）+ 进度条（阶段色 tint）；keyline 描边随阶段色（16.2+） |
| 灵动岛 compact | leading：kind/阶段图标（阶段色，代旧长标题文本）；trailing：计数，或终态/等待态阶段图标；桥会话 running 为空（状态在展开/锁屏面） |
| 灵动岛 minimal | kind/阶段图标（阶段色），代旧无色圆点 |

桥会话与一次性操作分形态：bridge 无 total → 全形态无进度条，
重状态词（stepLabel = 连接态）与指纹短记（opDetail）；一次性
操作（scenario 有 total 走确定进度；bridgeOp/export/restore
无 total 时 running 走不确定进度条，终态撤条）重进度与步名。

## 三、阶段样式表（phase 参与渲染）

`LiveOpStyle.symbol/tint(kind:phase:)` 单点覆盖规则：

| phase | 图标 | 色 | 进度 | 说明 |
|---|---|---|---|---|
| running | kind 本体 | kind 主题色 | 确定/不确定条（tint=主题色） | — |
| waiting | pause.circle.fill | gray | 保留当前值、tint 转灰 | 宽限到期由引擎 update 送达（桥会话不送，B38-5 守恒） |
| done | checkmark.circle.fill | green | 满条绿 tint | end 的 final ContentState（引擎既有：成功 15s 消退） |
| failed | exclamationmark.circle.fill | red | 残值红 tint | end 的 final ContentState（失败留 10min） |

## 四、步名口径（终态步名本地化，新增 3 键）

新增 i18n 键（五语齐，键数 438 → 441，verify [9] 账本与
B34-9 键表同步）：`liveops.running`（进行中）、`liveops.done`
（已完成）、`liveops.failed`（已失败）。

- export / restore：start 步名由机器词 `"export"` / `"import"`
  改 `liveops.running`；end 步名改按结果取 `liveops.done` /
  `liveops.failed`（原为与 start 相同的机器词）。改点在
  MomentApp.swift 导出/导入函数内共 4 处 hunk（行 1731/1736/
  1894/1900 区），与状态栏三轮批在同文件的在途 hunk（3614 起）
  disjoint、无交叠。
- scenario：两处 finish 的 end 步名由结果码（`finalCode` /
  `job.code`）改 `liveops.done` / `liveops.failed`；运行中步名
  仍为各步 label、计数走 done/total 不变。
- bridgeOp：end 步名**保留工具名**——其标题恒为「桥长操作」，
  工具名即该次操作的步身份，结果由阶段图标/色承载；运行中
  步名同为工具名（既有口径，不动）。
- bridge：步名仍为协调器定格的连接态词（既有口径，不动）。

## 五、长黑条成因与治法

成因：灵动岛展开区为系统黑底，旧版三区各仅一行小字（标题 /
计数 / 步名）、无图标锚、无进度、无描边与底色处理，内容高
远小于展开区高，视觉上即一条空黑条。
治法：① leading 徽章 + 标题成锚；② bottom 区补步名行 + 全
宽进度条（桥会话为步名 + 指纹行）；③ trailing 计数以阶段色
等宽数字提权；④ keylineTint 随阶段色给黑区一条色边；
⑤ 锁屏面同构（徽章锚 + 背景淡染），不再是系统默认空壳。

## 六、断言

- 新增 verify [62] 组 LV62-1..5：kind 图标/色单点五映射、
  phase 覆盖分支、minimal 图标化 + 旧圆点零残留、终态步名
  接线计数、展开三区 + 徽章两用 + 着色 API 在位。全绿。
- 改判一处：DM45-2（.white 前景全仓归零）——扩展目标跨进程
  无 T 令牌，徽章白字形与配对二维码白底板同属功能性例外；
  普查排除扩展文件、改为正向锁扩展内恰 1 处，主 App 侧归零
  口径不变，沿革已注 verify 注释。
- 既有实况断言全过：B34-1..9（挂点计数 start 4 / end 5 /
  update 1 不破）、B38-4..6、[9] 键集/键数（441）。
- appex 门控不破：BUNDLE_WIDGET_EXT=0 未动，B34-5 / [52]
  INS52 全绿；widget 仍照常编译入构建链（防腐烂口径不变）。

## 七、自检（本机止步口径）

- swiftc -parse：MomentLiveOpsWidget.swift /
  MomentBridgeUITest.swift / MomentApp.swift 三文件零诊断。
- verify_ios.sh 全量：590 ✓；红 2 条均为陈旧产物类（ipa 陈旧、
  产物语言包与 Web 源不一致——后者系本批改 lang 源后本地产物
  未重建，tree 全量重建归零），与本批断言面无关。
- widget 在 Linux 无 ActivityKit/WidgetKit 运行时：本批仅
  parse 级自检；类型级编译随 appex 编译遍在 tree 冒烟时覆盖
  （BUNDLE_WIDGET_EXT=0 下仍编译 + check-macho）。

## 八、真机终判点（须等 appex 回归：个人 Developer 账号后）

1. 灵动岛长按展开不再是空黑条：三区成卡、徽章/计数/进度齐。
2. 五 kind 图标与色一眼可辨（尤其 bridge 与 bridgeOp 两蓝系
   区分：蓝 + 天线 vs 靛 + 扳手）。
3. 终态呈现：done 绿勾 15s 消退、failed 红标 10min 留置的
   观感强度（锁屏 kind 色 0.5 淡染是否过重）。
4. 桥会话锁屏形态：无进度条、状态词 + 指纹短记可读；切后台
   宽限 waiting 态（操作类）灰暂停样式。
5. iOS 16.1 回落形态：无背景淡染 / keyline 时仍成卡可读。
6. 不确定进度条（export/restore/bridgeOp running）在实况中
   的实际渲染形态（静态条亦可接受，须不破版）。
7. compact 态以图标代标题后，与其他应用并存时的辨识度。
