# 0.9.59 组版报告

- 版本：0.9.59 / build 86
- 基线：cb8ff18（0.9.58 组版报告笔）
- HEAD（推送时）：801a605（文档门禁笔）；本报告笔另起一笔、随后推送。
- 本波 diff 总账：`git diff cb8ff18..801a605` = 39 文件、6511+/893−（其中 14 批分拣部分：原跟踪文件 3727+ 与删除 497 逐数吻合，新文件 1903+ 为三新 Swift 文件 1135 行 + 六份新报告，与分拣引擎对账一致；门禁复刻两笔 +881/−396 另计）
- **FFI 导出面核对**：`git diff cb8ff18 -- crates/` 为空——本波未动 FFI 导出面、无 checksum 漂移、无需重跑 bindgen、无契约测试改动。
- 推送：cb8ff18..801a605 共 18 笔已推 GitHub main（PAT shell 流程、输出脱敏）；推送前复核两件全过（§5）。

## 一、分拣账（18 笔：14 批 + bump + CI 修复 + 门禁复刻 2 笔）

分拣法与 0.9.58 同：自建分拣引擎（/tmp/sort59/，seg.py 按 HEAD→工作树算编辑段并规则打标、stage.py 以模拟索引逐批生成补丁 `git apply --cached` 并逐批以 `git show:file` 对账模拟），411 段全分类、0 未标；多义段逐个看全貌定归属。引擎修过三类真 bug：hlo 哨兵（10**9）使 find_head_pos 截断替换范围、同一头锚纯插入须按 final 序落码、补丁上下文不得含已删 segold 行。

| # | 提交 | 批 | +/− | 报告 |
|---|---|---|---|---|
| 1 | c2862a0 | E1 编辑回路（智能前缀/原子退格/组字守卫/粘贴分流；含 B25-E3-1 第三调用点改锚，第三处 `convertNodeType(` 调用点位于 MomentApp.swift:8042） | +491/−10 | impl_editor_loop_e1.md |
| 2 | 06f44dc | P3 搜索命中集（computeSearchHits 计算单点、search 与 bridgeSearchIds 共用、桥内嵌复制体整段删；searchQuery/searchHitsVersion 沉淀 Library；refreshSearchHitsIfStale 唯一触发点在 touchMemos 内） | +170/−42 | fix_search_hits_stale.md |
| 3 | c4281cd | OPS S13（effectiveScopeDict() 构造单点、四轴 + steps 六步实效表、ops_refresh/ops_get_effective 两回报同名同形共用、effectiveFrom 保留收窄语义；连接器 CONNECTOR.md 同步两轴表述，仓外文件、磁盘上已改好、无提交动作） | +102/−7 | fix_ops_effective_scope.md |
| 4 | f083be9 | SVG 解码（新文件 MomentSvgRaster.swift：内容嗅探分流离屏 WKWebView 光栅化、自然尺寸链、长边 ≤4096px/总像素 ≤16M；ImageLoader publish(data:failNote:) 单点收口） | +531/−26 | fix_svg_image_page.md |
| 5 | aba9609 | LCH-02（streak 改同一步锚定 streakStep、suspend/resume 保存/恢复对 + suspendedStep 墓碑、新字段 decodeIfPresent 自定义解码；覆盖矩阵 LCH-02 行正文补行改写） | +299/−20 | fix_launch_verdict_lch02.md |
| 6 | 27105e5 | 桥呈现三项（吊销回执 revokeOutcome 单点、scopes 空集如实显 + 源头兜底 `?? ["read"]` 改 `?? []`、backoff reason 行；五语 +8 键） | +356/−13 | fix_bridge_presentation_trio.md |
| 7 | 21523bf | i18n 收尾（图片页三处 `?? "图片"` 改引 imgpage.untitled、新键 imgpage.load_failed、ImagePageView 补 langStore 观察、followSystem 监听 NSLocale 变更重解析） | +122/−6 | impl_i18n_tail.md |
| 8 | bd4078a | 天气 W-T1（WeatherService.invalidateAfterKeyChange() 单点、fetch 四落点世代守卫 + refreshPending 接续） | +138/−20 | impl_weather_tail.md |
| 9 | ee2f317 | 备份 BK-1..3（ImportOutcome 契约、stagedStats 死字段清理、导出 toast 后移 ShareSheet.onComplete） | +192/−35 | impl_backup_tail.md |
| 10 | 620f7ca | 横屏网格 + 间距 12（全跨元素移出网格置纵排、每组=标题+组内 LazyVGrid；分隔行 16→6、卡缘到卡缘合成 12） | +217/−48 | fix_home_grid_landscape.md |
| 11 | 91b4ea1 | 权限中心 + 文案终裁（新文件 MomentPermissions.swift：PermCenter 唯一请求面、逐项真读状态、本地网络 NWBrowser 探针、实况只读状态；五语 +48 键、终态 429；文案终裁：无功能项行注只留「暂无功能使用」一句） | +1237/−17 | impl_permission_center.md |
| 12 | b692218 | 深色模式全量（attributed 加 baseColor 形参 + BlockTextView.baseColorUI 单点同喂三面、`.label` 死通道退役、checkBorder 深值归正 Web #B5B5BB、新令牌五件 onAccent/termText/termBg/doneTextUI/codeBgUI） | +343/−58 | fix_dark_mode_full.md |
| 13 | 1a5bebc | DT 真跟随（新文件 MomentFontFactory.swift：FontHub 监听类别变更发 epoch + FontFactory 为 UIFont 构造单点；Marks.dynFont 委托工厂；BlockTextView 抽 reloadContent 单点 + epoch 失效键；语义字体全量收口；J20-12 改锚 fix_j20_anchor_reconcile.md 并入本笔） | +1013/−174 | fix_dynamic_type_follow.md、fix_j20_anchor_reconcile.md |
| 14 | b311dde | 页眉消失根治（ScrollOffsetSanitizer 纯状态机、attach 后 120ms 挂载复读、HomeHeaderMath.compactP 纯函数单源、findScroll 面积最大选取） | +400/−14 | fix_home_header_vanish.md |
| 15 | c622a1c | bump 0.9.59 / build 86（改动点同前版：build-app2.sh 内嵌 plist 两串 + MomentApp.swift 设置页版本串） | +3/−3 | — |
| 16 | 6fe5ef0 | CI 僵尸键 bridge.pair_expired 补引用（用户 2026-11-27 定 A；见 §5） | +17/−5 | 本报告 §5 |
| 17 | 44584c2 | 门禁复刻·引擎共源：scripts/i18n_deep_check.py 单源（verify_rustweb.sh §7 与 verify_ios.sh [9] 共读），解析补 D4 声明体拼接 / D5 函数返回 / D6 成员绑定三形态 | +560/−396 | impl_gate_port_i18n.md |
| 18 | 801a605 | 门禁复刻·文档门禁：scripts/verify_docs.sh 新立（链接/引用完整性 + release 一致性硬门禁、孤儿报告仅警告）+ CI 接线（moment-rust-web 加 verify docs step 与两脚本触发路径） | +321/−0 | impl_gate_port_i18n.md |

本报告笔另起一笔（连同 note_w3_fixture_tree.md 入册），提交后推送。

### 跨批搭载留痕（分拣时定案）

- BlockTextView @2887 段归 dm（DT 的 adjustsFont 一行搭载）、@3102 段归 dt（DM 的 baseColorUI 调用搭载）、ImagePageView @20901 段归 dt（i18n 的 langStore 观察行搭载）。
- build-app2.sh 链接行 `svg_raster.o`+`permissions.o` 同行归 svg 笔。
- 桥设置页若干 DT 字体行搭载于 trio 笔。
- verify [9] 键数段（371→429 链式注释 + 计数行）归 perm 笔、verify B38-6 注释 371→429 归 perm 笔。

## 二、tree 磁盘清理留痕（冒烟前）

tree 根分区冒烟前实测 99% 满、仅剩 267M 可用（比 0.9.58 时的 0.6 GiB 更紧）；/data 20G 尚余 4.7G。大户：/opt/tc 5.2G（工具链，勿动）、/opt/work/Moment 3.6G（其中 rust/target 3.4G：debug/deps 2.0G、debug/incremental 701M、debug/build 194M）、/opt/npm 928M、/opt/rust 856M、/tmp 363M、/var/log 122M。

已清（均核对无引用后删）：

- `/opt/work/Moment/rust/target/debug/incremental`（701M，增量编译缓存、可弃、cargo 自动重建；deps 2.0G 保留，复建不全量）
- `/tmp/sdks.tgz` 88M、`/tmp/ulld.tgz` 38M、`/tmp/tc.tgz` 10M（工具链安装包残留；/opt/tc 已装件完好、smoke/verify/build 三脚本无引用）
- `/tmp/sw642` 188M（早期 Swift 前端手工构建草稿，App.o/build 日志；无脚本引用）
- `/tmp/car_out`、`/tmp/mc`、`/tmp/mc2`、`/tmp/m119`（约 28M 构建草稿）
- `apt-get clean`

清理后根分区 94%、**963M 可用**（df 复核）。Moment 克隆本体与工具链未动。冒烟过程 cargo test 增量重建 + iOS 构建在此余量内完成（见 §6 日志）。

## 三、tree 同步留痕

- push_small.py 名单已补三新文件（MomentSvgRaster.swift / MomentPermissions.swift / MomentFontFactory.swift），逐个 md5 对账到 /data/home/overlay/。
- 同步中途插曲：A 修复（6fe5ef0）编辑 MomentBridgeSettings.swift 落在首次同步中途，该文件首次同步读到的是修前版本（overlay md5 aade4509 ≠ 本地 71ef4317），其余文件 md5 均一致；已重跑 push_small.py 全量复核（幂等、逐文件 md5 对账），重跑后该文件 md5 与本地一致，方拷入克隆。
- overlay 拷入克隆：按 WORKFLOW §3.4 照抄，名单与 push_small.py 保持一致（含新文件、tests、bindings、crates、web editor 三文件、relay 两文件、天气 key）。

## 四、tree 冒烟

- 日志：/data/home/smoke59-tree.log
- 判据：smoke_ios.sh 四阶（cargo test → FFI 重建 → 构建 → verify）ALL GREEN 才出包。
- 结果：**SMOKE ALL GREEN**。[1/4] cargo test --workspace 全过；[2/4] FFI 静态库重建（ios profile 4.57s）；[3/4] ipa 构建（产物 Moment-stage2.ipa，11,606,655 B）；[4/4] verify_ios.sh **ALL PASS（504 ✓ / 0 ✗）**——含 [9] 组新增的共源深检两行（占位符跨包一致 429 键 ✓、僵尸键扫描零僵尸 ✓，深检透传行：原生字面引用 221 键、动态解析 63 键）。
- 同步插曲留痕：门禁批的 verify_ios.sh 新版在冒烟启动前已随 overlay 拷入克隆，但其 [9] 组调用的 scripts/i18n_deep_check.py 不在 push_small 名单内——冒烟启动后发现并单独直传克隆 scripts/ 目录（gzip+base64 一片、md5 f8908750 两侧一致），赶在 [4/4] 之前到位，未扰动冒烟。

## 五、CI 僵尸键事件（pair_expired 与 46 键解析器缺口）

### pair_expired（A 修复，6fe5ef0）

- Web CI 在 cb8ff18（0.9.58、371 键）上旗的僵尸键：`bridge.pair_expired`，五包各 1 行、均在 line 53；iOS 侧零引用；既有键、不在 0.9.59 diff 内。
- 用户 2026-11-27 定 **A 补引用**（B 删键未取）：MomentBridgeSettings.swift 待配对分支——当前时间超过 pending.expiresAtMs 时改显 `Lang.t("bridge.pair_expired")` 替代「有效期至」行；未过期形态逐值不变。判据与协调器同口径（`Library.epochMs() > expiresAtMs`）。
- 复核：① Swift 引用面恰 1 处（该分支）；② cb8ff18 的 worktree 上同口径复跑 verify_rustweb.sh 第 7 节——371 键、僵尸键恰该 1 键，与 CI 所旗一致；当前树复跑中该键已不在旗单。

### 46 键解析器缺口（已由门禁复刻批根治，见下）

- 当前 0.9.59 树（429 键）复跑第 7 节：占位符跨包一致 ✓，但退出码 1——另有 **46 个键**被判僵尸，全部来自本波两批，均为**解析器覆盖缺口、非真僵尸**（运行时真实引用、功能成立）：
  - `bridge.reason_network/timeout/unknown`（3，桥呈现批③）：消费形态 `if let reasonKey = bridge.stateReasonKey { Lang.t(reasonKey) }`——解析器不追成员绑定到属性声明体。
  - `bridge.revoke_pending/confirmed/unconfirmed`（3，桥呈现批①）：消费形态 `Lang.t(revokeOutcomeKey(outcome))`——函数返回值直喂 Lang.t 的调用形态不在识别面内。
  - `perm.status_*`×14、`perm.item_*`×13、`perm.note_*`×13（40，权限中心批）：键以计算属性 `"perm.item_" + token` 等拼接构造（MomentPermissions.swift:71-72/113）——解析器 D2 拼接只认 Lang.t 调用点实参，不认声明体内的拼接。
- 过程缺口：脚本头注自立规矩「新增动态形态时须同步扩展本节解析」；两批只跑了 verify_ios.sh [9]（键数对账）、从未跑 verify_rustweb.sh，各批报告亦无一字提及此门。
- **根治（主线裁定并入本版）**：门禁复刻批（impl_gate_port_i18n.md）将 §7 引擎抽为共源 scripts/i18n_deep_check.py（verify_rustweb.sh §7 与 verify_ios.sh [9] 共读、禁止另抄副本），并按 §7 自订纪律补 D4（声明体拼接）/ D5（函数返回）/ D6（成员绑定）三形态扩展；复跑：429 键、僵尸 0、深检退出码 0；46 键认领逐条有证据行（D4×40、D5×3、D6×3）。
- **推送复核（最终树）**：① Swift 引用面 bridge.pair_expired 恰 1 处 ✓；② verify_rustweb.sh 全量 exit 0（VERIFY RUSTWEB ALL PASS、106 ✓ 行）✓；verify_docs.sh exit 0 ✓。两件全过后推送（cb8ff18..801a605）。
- **待主线回核下一次 CI 运行转绿**（cb8ff18 那笔结果未见、可能排队，一并观察；按本次对账，cb8ff18 那笔若出现应只旗 pair_expired 一键；801a605 这笔应全绿）。

## 六、出包

- ipa：~/workspace/your_files/Moment-0.9.59.ipa
- 字节数：**11,606,655 B**
- md5：**a7ec7e96f62b40f00487ac6d2cb88dc2**（pull_ipa 分片拉回、远端与本地 md5 一致）

## 七、真机终判点全集（逐项点名，断言绿 ≠ 已跟随）

### E1 编辑回路

1. 拼音组字全程：候选选择停顿 >0.6s 时中间拼音串不得落盘（杀进程重开验）、组字中不弹斜杠面板、提交后文本与落盘一致。
2. 行首键入 `# 标题`/`## `/`### `、`> 引用`、`[] 待办`/`[ ] 待办`、`---` 四类转换形态与落点；多行粘贴「# 标题行\n正文」首块成标题、次块仍段落；`> [!NOTE] …` 不转引用。
3. 文本块段首退格、前为图片/卡片时：原子块出现选中描边、文本与块均保留、再按退格无删除发生；删块仍走长按卡菜单。
4. 标题块、引用块内输入 `/` 不弹面板；段落/待办/列表项内仍可弹。
5. 代码块内粘贴 URL/多行代码整段留字面、不成卡。

### P3 搜索命中集

1. 搜关键词 → 打开命中篇 → 删掉该关键词 → 返回：该篇立即消失于结果（不按键）；反向：未命中篇改入关键词 → 返回后出现。
2. 搜索活跃置于首页时，桥侧改一篇标题/正文，命中集随之更新（Diag 见 refresh 行）。

### OPS S13

- 装机后桥前台窗口：ops_refresh 回报含 effectiveScope 且 steps 表与 fix_ops_effective_scope.md 一致；会话内实证一例——救援页 checkOps 拉一份点名「天气自动刷新」的指令后回首页，Diag 应见 `OPS skip step=天气自动刷新`，且启动模式不翻转。

### SVG 解码

1. 备忘含 SVG 附件：正文内联可见图（非失败占位）→ 点文件行进图片页正常呈现 → 双击/捏合缩放可用、小尺寸 SVG 不被放大。
2. URL 形 SVG 图块（`.svg` 结尾与无后缀各一）同样成图。
3. 一张畸形 SVG：落「图片加载失败」且 Diag 失败行带 `fmt=svg`。
4. 无自然尺寸且无 viewBox 的 SVG：呈现为 300×150 画布口径且 Diag 有 `SVG 光栅化自然尺寸缺失` 行。
5. GIF 与普通图回归各一（嗅探不误伤）。

### LCH-02 启动判读

1. 加载步强杀两次、**不同步**（如开库步一次、解析步一次）：不应进安全模式，Diag LAUNCH 行见「锚步变更、本步第 1 次」。
2. **同一步**强杀两次：进安全模式，LAUNCH 行见「同一步连续第 2 次」+ F2 注记；救援页 streak 行显「2 · 锚步 <step>」。
3. 加载中退后台等系统回收后冷启：Diag 见墓碑 warn 行（不计数），不进安全模式。
4. 加载中退后台再回前台：哨兵步名恢复原加载步（Diag/救援页步名不跳「会话中」），load 正常收尾。
5. 升级首启：旧版哨兵文件可读（streak/步名不丢失、不回退 UserDefaults 旧值）。

### 桥呈现三项

1. 吊销回执：设置页真吊销一次——回执行先显「正在向中继确认」、数秒内翻「中继已确认吊销」；Diag 见 `revoke relay=confirmed`。飞行模式下再配对再吊销——回执如实显「中继未确认」（warning 色），Diag 见 `relay=unconfirmed`。
2. scopes 呈现：全授态已授行三名齐、无未授行；只授 read 的配对下未授行显「功能写 · 运维」。空集态真机难构造（需中继异常回带），以断言 + 代码审为准、不列真机点。
3. backoff reason：已连接后开飞行模式——状态翻「重连中」、其下显「连接中断」；关飞行模式恢复「已连接」后 reason 行消失。
4. （新增，A 修复）待配对码过期后进桥设置页：有效期行改显「本轮配对已过期，请重新开始配对」；未过期码仍显「有效期至」行。

### i18n 收尾

1. 非中文界面（如 en-US）打开无名图：图片页标题显「Image」、加载失败显新键译文，不再恒中文。
2. 桥远程切语言时图片页正开：文案即时刷新、不需重开。
3. 跟随系统模式下运行中改系统语言：回 App 语言即时重解析（Diag 有 LANG follow-system 行）；手动模式改系统语言无变化。

### 天气 W-T1

- 设置页改和风 key 为另一有效值 → 返回首页：天气块应先消失（失效）后以新源数据出现；改成错 key → 天气块消失且不回显旧数据；Diag 成对见 `WEATHER invalidate src=keychange` 与其后 `WEATHER fetched provider=…`（或 provider=fail）。清除自定义 key 同路复验一遍。

### 备份 BK-1..3

1. 导入一份真实备份 ZIP：成功 toast 计数与库实际篇数对账。
2. 导出后在分享面板点取消：不应出现「文件已分享」toast；完成一次真实保存/发送后才出现。

### 横屏网格 + 间距 12（双设备）

1. **iPhone 横屏**：首页各组标题独占整行、其下卡片 3 列流排；折叠组展开后卡片连续 3 列、组间不混排；新建卡在首组标题上方独占一格。
2. **iPad（1180 三列 / 1366 四列各一遍）**：标题整行全跨；1366 档卡片排满 4 列、标题不再散落进行内。
3. **间距改判（竖屏即可）**：图文卡与文本卡交界量距 ≈12pt（36px@3x）；同子列内相邻卡仍 ≈6、组头距与网格形态无连带变化。
4. 附带回归面：只读横幅/公告出现时整行呈现（不再占一格）；空库/搜索零结果空状态整行居中如旧；横屏滚动紧凑态（HomeScrollProbe）行为不变。

### 权限中心（逐项弹窗清单）

前置：全新安装或在系统设置中重置各权限至未定状态；进设置页 → 权限页，先核每行状态词与系统实际一致，再逐项点「请求」：

1. **通知**：应弹系统通知授权弹窗；允许后行状态变「已授权」；与桥设置页通知开关状态互通（同一授权）。
2. **定位**：应弹定位授权弹窗（使用 App 期间允许）；允许后变「已授权」；天气页取位不受影响。
3. **相机**：应弹相机授权弹窗；允许后变「已授权」。
4. **相册（读取）**：应弹相册授权弹窗（含「选择照片/允许全部」系统选项）；选任一后变「已授权」（.limited 折入口径）。
5. **相册（保存）**：应弹保存授权弹窗；允许后变「已授权」。
6. **麦克风**：应弹麦克风授权弹窗；允许后变「已授权」。
7. **Face ID**：状态先显「可用」或「不可用」；不可用时点请求应起 Face ID 系统评估界面；行注「暂无应用锁」属实。
8. **本地网络**：点请求应弹本地网络授权弹窗（提及在局域网内发现设备）；允许后探针应回「浏览可用」，拒绝应回「已拒绝」；无弹窗直接出结果或恒「检测中」为异常。
9. **日历**：应弹日历全访问授权弹窗（iOS 17+ 文案）；允许后变「已授权」。
10. **提醒事项**：应弹提醒事项全访问授权弹窗；允许后变「已授权」。
11. **实况**：无弹窗（预期行为）；状态词与「设置 · 此刻 · 实况」系统开关一致；点「去系统设置」应跳到本 App 系统设置页。
12. **后台任务 / 远程推送**：两行恒显「已声明」且无请求钮（预期行为）；远程推送行注「发送通道尚未建立」属实。
13. **通用**：已授权行无请求钮、点按无任何弹窗；杀进程重进后状态与系统设置内一致；回前台后状态自动刷新；Diag 应见每项请求各一行 `SET perm request kind=… result=…` 与进页行 `SET permissions enter`。
14. 无功能项行注终态：相机/相册读/相册写/麦克风/Face ID/本地网络/日历/提醒事项/远程推送各行注只写「暂无功能使用」一句、不附说明。

### 深色模式（深 / 浅各走一遍，6 项）

1. **截图同款编辑页**（自定义底色备忘、深色）：正文/标题/引用/代码文字白系分明；页眉玻璃与首块图文卡保持深色（正确态、勿误判为病）；浅色下与旧版一致。
2. **待办两态**：未选圈深色下清晰可见；完成项删除线文字可读（正文根治后复核其观感，若仍判过淡再议 parity 值）；已选蓝圈两外观各验。
3. **斜杠菜单全项**：深/浅各开一次逐项扫 24 项（图标/标题/副文/快捷键丸/最近丸/选中行/组头），公式块与行内公式在内；空态、链接表单（提交钮白字）一并。
4. **MD 预览**：含表格（表头字）、任务列表（未选方框）、代码段、链接段的 MD 块，深色下文字全白系、方框可见。
5. **外观热切换**：编辑页开着时切系统深/浅，正文颜色即时翻转、不重进页面；持焦块新键入文字颜色正确（typingAttributes 面）。
6. **Diag 两页**：终端绿字深底在两外观下保持不变（设计如此）；错误徽章红/橙底白字两外观可读。

### DT 真跟随（11 项）

改系统字号（L → XXXL → AX2 各一遍）逐面核：

1. 编辑器正文（含代码块、待办、引用）随动；持焦中改字号 → 失焦后补刷到位；组字（拼音）中改字号不打断输入、失焦后对齐。
2. 标题字段与胶囊宽/高随档重算。
3. MD 预览正文、列表标记、代码段随动。
4. 首页单列两面：**搜索胶囊两层**（触发层图标、展开层字段）、**新建笔记卡片**（行/方卡）；另组头、方卡文图卡。
5. 设置族各页行标题/meta；备份面板、导出面板；天气/语言/手势页。
6. 斜杠菜单与各浮层（••• 菜单、背景底表）。
7. 桥设置页、Diag 页（含空态文案）、救援页 + 看门狗条、权限页。
8. 图片页标题与加载失败文案。
9. **头像单列**：两处头像尺寸不变（设计决定）且 AX 档同行胶囊/布局不失衡——若判应跟随再立项（本批结论：不必跟随、未落码；理由见 fix_dynamic_type_follow.md §4）。
10. **手势图示单列**（min(f25,25) 全程压平）：确认图示字形不随字号为可接受的设计决定，或改判立项。
11. Diag 出现 `FONT category -> … epoch=…` 行（变更留痕在位）。
- 范围外待裁：MomentLiveOpsWidget 扩展目标语义 8 处未收口（扩展每次更新独立进程新渲染、与主 App 快照病不同型，终判时瞥一眼实况文字）。

### 页眉消失根治（四场景）

1. 冷启：首屏头像 + 搜索胶囊在位且可点（重点看冷启慢帧时有无一闪消失/迟迟不回）。
2. 导航往返：进编辑器再返回 ×数次（其一在首页先滚动少许再进），返回瞬间页眉与真滚动位置一致。
3. 旋转：竖→横→竖各停留数秒，横屏网格与竖屏列表页眉均随真位置。
4. 回弹滚动：顶部下拉过冲松手、快速上滑下滑交替，静止于顶时页眉恒在位可点。
- 再犯时 Diag 判读法见 fix_home_header_vanish.md §八（spike discarded / compactband / compact 1 三路）。

## 八、遗留与后续

- CI 回核：下一次 CI 运行（801a605 及本报告笔）转绿待主线回核（见 §5）；cb8ff18 那笔结果未见、可能排队，一并观察。
- smoke_ios.sh 接线后续项：文档门禁（verify_docs.sh）本版只接了 GitHub CI，未接入 smoke_ios.sh（避免扰动冒烟流程系主线裁定）；下版评估把 verify_docs.sh 串入冒烟或组版清单。
- push_small.py 名单后续项：scripts/i18n_deep_check.py 本次以单独直传补位（见 §4）；下版组版前应把 scripts/i18n_deep_check.py 与 scripts/verify_docs.sh 补入同步名单，免再手工补传。
- 0.9.58 装后走桥自办（S1 两遍/M3b/实况三档）与 0.9.59 真机终判点全集（§7）待装机后判读。
- 队列：E2 撤销（F-10/F-11/F-12）→ U4b → 跨块选区两期 → U2（门=S1 两遍 ok）→ U3 → U5；M3b→M3c；I4 → I5 残余。
