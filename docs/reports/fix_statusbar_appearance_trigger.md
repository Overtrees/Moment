# 状态栏原生适应补遗——外观切换补案（fix_statusbar_appearance_trigger）

日期：2026-11-28。分支 `fix/statusbar-native-adaptation`，在本体 `e3c1d06`（impl_statusbar_native_adaptation）之上追加一笔补遗提交；本体结论与架构不动，本报告为补遗的独立小报告（本体报告不回改）。

## §补案来源

用户 2026-11-28 15:02 实报：编辑页、备忘为浅色自定义背景时，直接开启系统深色模式，状态栏字体停在黑色（旧答案），要等滚动页面、深色图片卡经过状态栏下方才翻成白色。裁定：纳入本方案解决——外观切换为一等触发，切换即按当前外观下的有效背景重答，零滚动验收。

注：用户实报发生在 0.9.66 出货口径上（该口径全仓无 preferredStatusBarStyle override、状态栏为系统默认行为，git grep e65e396 实证）；本补遗的对象是本分支的新架构——保证新架构上线即含此格，不把旧口径的机制猜测写进定案。

## §定案（两条逐条证实/证伪，均以本分支代码为据）

### 病灶 1「外观切换不是触发源」——部分证伪、实质证实

- **证伪点**：触发集并非没有 trait 通道。根容器 `ContainerViewController.traitCollectionDidChange`（MomentStatusBarRoot.swift）已有接线 → 引擎 `noteTrait()`（e3c1d06 树内实证）。
- **证实点（实质病灶）**：该接线与滚动/布局完全同路——`noteTrait()` 只是普通 `evaluate()` 的别名。外观翻转在引擎里只是一个普通候选：须过 去抖 48ms + 最短驻留顺延，且**可被整段取消**——候选存续期间任一次重估得出 `raw == currentStyle`，`evaluate()` 即把 pending 清零、取消落定工作。而 trait 事件只在变化瞬间来一次、过后不再重发：一一次性事件 × 可取消候选 = 翻转可静默丢失、答案停在切换前，直到下一次无关触发（滚动/布局）才重估。这与用户症状的形态（切换不动、滚动才翻）同构。
- 另一面：旧路径无任何专属 Diag 证据，外观切换是否到达引擎在设备上不可判读（与本体 §留账 1 的未证面同型）。

### 病灶 2「答案没按当前外观下的有效背景算」——整体证伪（本分支）

四数据面逐一回源，全部已按当前 trait 解析有效色、存储色值从不裸算：

| 面 | 实证 |
|---|---|
| 编辑页 | `T.memoBgUI(hex)` 本体即动态色（`UIColor { traits in … }`：浅 = 原色、深 = ×0.55 压暗，MomentApp.swift）；登记闭包（MomentEditorTransition.swift）以 `.resolvedColor(with: ctx.trait)` 解析后才算明度 |
| 首页/设置族/救援页 | `T.bgUI` 为动态色（dyn 双值），引擎 provider 以 `.resolvedColor(with: ctx.trait)` 解析 |
| 开屏 | `SplashBandData.centerColor(dark: ctx.trait.userInterfaceStyle == .dark, …)` 以 trait 选渐变停点数据；回落 `SplashOverlayView.uiColor` 为动态色且经 resolvedColor 解析 |
| 图片页（回落支） | 同根令牌色 resolvedColor 解析；像素支读实像素、无外观口径问题 |

且 `ctx.trait` 单源于回答者（根容器）的 traitCollection，各面同源。故本批**不改任何数据计算**，只以 SB-16 普查锁把此口径钉死防回潮（见 §断言）。

## §补遗落码

### 触发面（订阅点恰一，在回答者）

根容器 `traitCollectionDidChange` 改分流（MomentStatusBarRoot.swift，全应用唯一外观订阅点，不新增第二回答者、容器仍是唯一 override）：

- `previous?.userInterfaceStyle != traitCollection.userInterfaceStyle` → 外观切换 → 引擎新入口 `noteAppearanceChanged()`；
- 其余 trait 变化（内容尺寸类别等）→ 原 `noteTrait()` 普通通道不动。
- style 过滤同时充当同帧合并：一次切换 style 只变一次，重复送达不重入。

### 引擎确定性通道（MomentStatusBarEngine.swift）

- `evaluate(deterministic:)` 加确定性形参（默认 false，滚动/布局/落定复算等既有调用逐字不变，`settle()` 的复算仍走普通形参）；主线程跳板透传该旗。
- 确定性路径：重算得出新答案且与现行不同 → **直落** `apply(animated: true, trigger: "appearance")`——不进候选、不候去抖、不受驻留门顺延；与现行一致 → 不翻转，但记证据行（见 Diag）。`apply` 内仍是全仓唯一 `setNeedsStatusBarAppearanceUpdate` 调用点（SB-11 不动），淡变仍走 160ms fade 口径。
- 与候选状态机的关系：直落经 `apply` 统一清 pending（滚动候选若与外观结论同向则被吸收、异向则被覆盖——外观是更新的确定性事实，覆盖正确）；驻留门只治高频源，对一次性系统事件不适用，此为本补遗与状态机的分工线。

### Diag 证据

- 翻转行扩展一字段：`STATUSBAR flip surface=… src=… lum=… style=… trigger=eval|appearance`（旧行无此字段，装机对账时按 trigger 区分来源；flip 行无其他程序消费者，grep 实证仅引擎自写）。
- 外观重答无翻转时另记一行：`STATUSBAR appearance surface=… src=… lum=… style=…`——使「切换已达引擎且按新外观重算、结论恰与现行一致」与「根本没触发」在 Diag 里可分辨。

### 数据面

零改动（定案二证伪）。仅新增 SB-16 锁现状。

## §断言（verify_ios.sh [53] 组新增两条）

- **SB-15 外观确定性触发**（去注释口径计数）：根容器 traitCollectionDidChange 恰一 + style 过滤（previous?.userInterfaceStyle）恰一 + 根容器调 noteAppearanceChanged 恰一 + 全仓 noteAppearanceChanged 恰二（引擎定义一 + 根容器调用一 ⇒ 无第二订阅点）；引擎 `func noteAppearanceChanged` 恰一、`evaluate(deterministic: true)` 恰一、直落 `trigger: "appearance"` 恰一、无翻转证据行 `STATUSBAR appearance` 恰一。
- **SB-16 数据面 trait 解析普查锁**：引擎内 `resolvedColor(with:` 恰三（根/救援、开屏回落、图片回落）+ 开屏 trait 选数（userInterfaceStyle）在位；编辑承载闭包 `resolvedColor(with:` 恰一；`memoBgUI` 动态色形态（`UIColor { traits in` 恰一 + 深色变体分支 `traits.userInterfaceStyle == .dark` 恰一，均在 MomentApp）。
- **负对照（实做并登记）**：NC-3 把根容器的 `.noteAppearanceChanged()` 临时改回 `.noteTrait()` → SB-15 恰红（rootCall=0、all=1），SB-11/SB-16 不误伤，验毕逐字节还原；NC-4 把编辑闭包的 `.resolvedColor(with: ctx.trait)` 临时摘除 → SB-16 恰红（trans=0），SB-15 不误伤，验毕逐字节还原。
- 本机 verify 全量分账：**714 ✓ / 5 ✗**（712 本体基线 + SB-15/16 两条新绿；5 红全为 worktree 产物陈旧——ipa / Assets.car / 开屏双 JSON / 语言包，tree 构建后自解，与本批无关）。[53] 组 SB-1…SB-16 全绿，四参数、回答者唯一、像素保底面、SB-8/9/10 开屏口径逐项未动。

## §验收格（装机终判，登记于此；自检矩阵无状态栏面，不另登记）

1. 编辑页打开浅色自定义背景的备忘 → 切系统深色模式 → **零滚动**，状态栏即翻白字；Diag 须见 `STATUSBAR flip … trigger=appearance`（或结论一致时的 `STATUSBAR appearance …` 行）。
2. 同页反向：深色模式下切回浅色 → 零滚动即翻黑字，Diag 同上对账。
3. 首页（根面）同型一格：浅外观切深色、零滚动翻转正确（验根面 provider 的 trait 解析在设备上贯穿）。
4. 回归面：滚动跨区翻转（图片页）仍受去抖/驻留治理、不抖；开屏两形态字色与退出回落同本体验收格不变。

## §留账

1. **订阅送达链待装机实证**：traitCollectionDidChange → 容器分流 → 引擎确定性入口的送达，与本体 §留账 1 的转发链同为 inferred（构造与先例同构），proven 待装机：验收格 1/2 的 Diag 出现 trigger=appearance（或 STATUSBAR appearance）行即链活。若两行皆缺（事件未达），回退评估为 SwiftUI 环境 colorScheme 通道汇入同一引擎确定性入口——只登记为预案，本批不预埋第二通道（守「订阅点恰一」）。
2. **Swift 编译门未过**：本机无 swiftc（本体同口径），全量编译留 tree 组版冒烟把关；本批改动均为既有文件内外科小改，已逐行回读 diff 复核。
3. 合并注意：本批只动 MomentStatusBarEngine.swift / MomentStatusBarRoot.swift / verify_ios.sh 三文件（+ 本报告），与主工作区偿还批二零文件冲突面；verify 改动为 [53] 组内纯追加（SB-15/16），合并时与他批的计数锁改判无交叠。
