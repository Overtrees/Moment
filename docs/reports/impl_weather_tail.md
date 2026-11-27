# 天气小批 · 登记余项收口（只读准备 + 落码设计，停门）

> 状态：**W-T1 已落码**（2026-11-27 晚，落码门已开：HEAD cb8ff18、开工时树净；落码记录见 §5）。W-T2/W-T3 守原设计只登记不落码。未提交、未 bump，随下一组版。
> 清单来源（报告原文为准，不自扩）：`audit_home_other_deep.md`（§4.7 / §4.13 / §8 批表 / §9 终判表）、`audit_landscape_wide.md`（§五 V-4 / §六 E-1）、`audit2_home.md`（§五 B7 余项）、`fix_weather_subtitle_i18n.md`（§7 终判点）、`impl_weather_settings.md`（遗留注记）、`plan_selftest_coverage.md`（SET-02/03/04、HOM-11 覆盖归属）。
> 行号为 2026-11-27 晚现行树（MomentApp.swift 已随多批漂移，以符号名为准）。

## 1. 清单总表

| # | 项 | 出处 | 现行核对结论 | 处置 |
|---|---|---|---|---|
| W-T1 | 天气 key commit/clear 后不主动刷新：只删缓存、不清 `WeatherService.now`、不触发 refresh，新 key 生效依赖 ListView onAppear 重入（pop 下是否恒发生代码不能证） | audit_home_other_deep §4.7（P3）+ §8 批表「天气小批」行 | **未办，属实**（§2 核对） | **落码**，设计见 §3 |
| W-T2 | 天气页横屏唤键盘，第二张（彩云）卡输入行可达可视（unknown） | audit_landscape_wide §五 V-4、§六 | 无显式键盘避让代码的形态未变（页面已套 settingsContentFrame，顶距口径随之） | 只登记：归横屏 V-1..V-6 真机量测批，量测不成立才立落码项 |
| W-T3 | 彩云免费额度耗尽时回退无真实答案 | 任务书已知事实 + audit_search_weather §2.1 | 回退链代码完备（见 §4 销项 5 的 Diag 行面），属外部条件 | 只登记，不在本批修复面；终判 = Diag 抽样见 `WEATHER fetched provider=caiyun-fallback` 行 |
| W-T4 | 设置族宽屏收窄容器（E-1，天气页在六页内） | audit_landscape_wide §六 E-1 | **已落**：`settingsContentFrame()` 定义 MomentApp.swift:14922，WeatherView 内应用在 :19585，另五面 + MomentBridgeSettings.swift:156 同套 | 销项（用户裁定③、宽屏批已落） |
| W-T5 | impl_weather_settings 遗留：verify [10] S1 组头 topPad 断言期望同步（40/32/40 → 40/32/32）留主线合流改 | impl_weather_settings §六 | **已合流**：verify_ios.sh:488-491 现行期望即 40/32/32 | 销项 |
| W-T6 | 天气缓存 weatherCacheV1 无版本号与坐标 | audit_home_other_deep §4.13 | 审计自判「Web 读时亦不比坐标、行为等价，仅注记」 | 销项（不立项） |
| W-T7 | 新建卡天气最小间隔合成 ≈32 vs Web 24（B7 余项，待修待核）+ 新建卡副行色 | audit2_home §五 | **已落**：newCardRow（MomentApp.swift:18019）HStack spacing 已改 6，注释账明记「6×2 + leading 12 = 24，此前 spacing 10 合成 ≈32」；副行色已改 T.glassLabel（同处注释引 H4） | 销项（二轮微差批已落，代码注释自证） |
| W-T8 | 双 key 回退「呈现」面：二级页逐源状态/生效行、主页副标题 | audit_home_other_deep §4.7、fix_weather_subtitle_i18n §2/§7 | 二级页 sourceWord/effectiveText 在位（§4.7 判达标）；副标题已改固定说明键并入 0.9.57（提交 6e56ddd）；天气块本体无 provider 标识与 Web 逐项同（§4.13 失败呈现等价） | 销项（落码面无缺口）；副标题批 §7 两条真机终判点转真机终判积压，不属本批 |
| W-T9 | 自检覆盖：SET-03/SET-04 UI 腿、HOM-11 呈现读（缺口）；SET-02 桥腿 weather_settings_flow | plan_selftest_coverage :136/:234-236/:312 | 覆盖归属已定：UI 腿/呈现读归 U5、桥腿归 M3a（已落） | 归他线（U5/M3 线），本批不纳入 |
| W-T10 | OPS 生效口径双轨（P2-6/S13）：天气刷新 guard 实时读 cached() 与「恒下次启动生效」表述漂移 | audit_home_other_deep §1 P2-6、§4.13 | 天气侧只是消费点（ListView.onAppear guard，MomentApp.swift:17157-17163）；口径修订与 ops_refresh 回读字段属 OPS 批 | 归他线（OPS 口径批）；W-T1 设计与之的交叉点见 §3.4 |

## 2. W-T1 现行形态核对（proven，逐点源码）

- `WeatherKeyEditor.commit(_:)`（MomentApp.swift:19494-19513）：清洗 → 与现存值比较 → 写/删 `weatherKey_<name>` → `removeObject(forKey: "weatherCacheV1")` → flashSaved/logSaved。**无** now 清理、**无** refresh 调用。
- `WeatherKeyEditor.clear(_:)`（:19515-19527）：删键 → 清字段 → 同样只删 weatherCacheV1。
- `WeatherService.now`（:16136 `@Published var now: Now?`）全仓写点只在 refreshIfNeeded/fetch 链内；key 变更路径不触碰。故：改 key 后若重拉失败（新 key 错/断网），天气块将无限期呈现**旧 key 取回的旧数据**——缓存已删也救不了，因为呈现读的是内存 now 而非缓存。此点比审计原文更进一层：不只是「生效靠重入」，还有「失败即旧数永驻」。
- `refreshIfNeeded()`（:16217-16233）无 force 形参：缓存新鲜（<1800s）直接以缓存置 now 返回；否则走 1.5s 延迟 + inFlight 去重的 fetch。
- 唯一自动触发点 = ListView `.onAppear`（:17155-17163，OPS guard 内侧）。编辑器侧无任何触发。
- **竞态增补（本批新发现，proven by reading）**：commit 时若恰有一趟 fetch 在飞（inFlight=true，携旧 key），其完成后仍会 writeCache + 置 now（fetch 落点 :16341/:16405 一带），把刚删的缓存以旧 key 数据重写、且新触发的 refresh 会被 inFlight 守卫吞掉——key 变更可被在飞旧请求整体抵消。落码设计须一并处理（§3.2 世代守卫）。

## 3. W-T1 落码设计（根治落点在 WeatherService 单点，不在编辑器消费方逐处补）

### 3.1 服务侧新增失效单点

`WeatherService` 新增 `invalidateAfterKeyChange()`，职责四件收敛一处：

1. 世代号 `keyGeneration += 1`（见 3.2）；
2. `now = nil`（呈现立即回落缺数形态，与 Web「无数据整块不渲染」同义；ListView 经 :16706 观察 shared，@Published 变更即时生效）；
3. 删 `weatherCacheV1`——**缓存键的删除权从编辑器收归服务**（现行 commit/clear 两处直删改为调本方法，缓存归属与 readCache/writeCache 同置一类，防再分叉）；
4. 调 `refreshIfNeeded()` 主动重拉（缓存已删必走 fetch 路径，不依赖 ListView onAppear 重入）；Diag 记 `WEATHER invalidate src=keychange`（行风与既有 WEATHER 行一致），使「改 key → 失效 → fetched provider=…」在 Diag 成对可判。

### 3.2 在飞旧请求世代守卫

`fetch()` 入口捕获 `let gen = keyGeneration`；writeCache 与置 now 前校验 `gen == keyGeneration`，不符则整趟结果作废并（若该趟是被失效打断的）由 invalidate 侧已发的 refresh 接续，不另起重试逻辑。守卫点单点落在 fetch 的落盘/置值两处，不动双源链内部。

### 3.3 编辑器侧改动（仅两处替换）

- commit（:19509-19510）与 clear（:19521-19522）的 `UserDefaults.standard.removeObject(forKey: "weatherCacheV1")` 各改为 `WeatherService.shared.invalidateAfterKeyChange()`。flashSaved/logSaved（SET 侧来源口径行）不动；无变化不写盘的既有 guard 不动（无变化时本就不该失效）。

### 3.4 与 OPS guard 的交叉口径

ListView 自动刷新受 `OpsStep.weatherRefresh` guard 管辖（「天气**自动**刷新」步）。key commit 触发的刷新是用户在设置页的显式编辑后果、非自动刷新，设计上**不进 guard**（与手动刷新同类）；Diag 的 invalidate 行使该路径在指令禁用期也可审计。此口径与 W-T10（OPS 批）的 S13 表述修订不冲突，落码报告中记明，OPS 批回读时可复核。

### 3.5 断言设计（verify [18] 组续号，W18-8 起）

- W18-8：commit/clear 两处均调 `invalidateAfterKeyChange()`（计数 = 2），且 WeatherKeyEditor 段内 `weatherCacheV1` 字面零残留（删除权收归服务）。
- W18-9：`invalidateAfterKeyChange` 本体四件在位（世代自增 / now=nil / 删缓存 / refreshIfNeeded 调用 + Diag 行）。
- W18-10：fetch 落盘两点（writeCache 调用与 now 赋值）受世代守卫（锚守卫式样计数）。
- 本机自跑 [18] 组全绿 + MomentApp primary 遍类型检查零错误（放行后执行）。

### 3.6 真机终判口径（并入 SET-04 子行，审计 §9 #10）

设置页改和风 key 为另一有效值 → 返回首页：天气块应先消失（失效）后以新源数据出现；改成错 key → 天气块消失且不回显旧数据；Diag 成对见 `WEATHER invalidate src=keychange` 与其后 `WEATHER fetched provider=…`（或 provider=fail）。清除自定义 key 同路复验一遍。

## 4. 纪律与停门

- 天气 key 纪律守恒：本批设计不触 key 的存取与注入路径（key() 优先序、bundle 构建注入、仓外 weather-keys.json 均不动）；key 永不入仓、不入 Diag（既有 SET 行只记来源口径，invalidate 行只记事件）。
- 未提交、未 bump；本报告为本批唯一写出物。
- **停门回报**：清单与设计已备，待主线放行（0.9.58 组版落定）后按 §3 落码，落码面 = MomentApp.swift（WeatherService + WeatherKeyEditor 两段）+ verify_ios.sh [18] 组。

## 5. W-T1 落码记录（2026-11-27 晚）

落码面 = MomentApp.swift（WeatherService + WeatherKeyEditor 两段）+ verify_ios.sh [18] 组尾，逐项对 §3：

- **§3.1 失效单点**：`WeatherService.invalidateAfterKeyChange()` 已落，四件收敛一处（世代自增 / `now = nil` / 删 `weatherCacheV1` / 调 `refreshIfNeeded()`），Diag 行 `WEATHER invalidate src=keychange` 在位。缓存删除权已从编辑器收归服务（全文件 `weatherCacheV1` 仅剩四处合法持有：readCache 读、writeCache 写、本方法删、Diag 页「清缓存」自救钮直删——后者是数据自救消费方、不在编辑器面，不属本批收敛范围）。
- **§3.2 世代守卫**：`fetch()` 入口捕获 `let gen = keyGeneration`；落盘/置值四点全守卫——双源（fetchQWeather/fetchCaiyun）的 `writeCache` 与 `WEATHER fetched` 打点同置于 `await MainActor.run { guard gen == keyGeneration … }` 内，与 invalidate 的世代自增/删缓存同在主线程串行（校验与写入之间无跨线程窗口，旧世代整趟作废）；`fetch()` 置 `now` 两点在 MainActor.run 内以 `gen == keyGeneration` 为条件。
- **接续机制（§3.2「由 invalidate 侧已发的 refresh 接续」的实现落点）**：`refreshIfNeeded()` 在飞时不再静默吞请求——置 `refreshPending = true`，本趟 Task 收口（inFlight 落旗）后自动续跑一趟。否则失效时恰有旧趟在飞，其 refresh 会被 inFlight 守卫吞掉、新 key 拉取要等下一次 ListView 重入，与 §3.1 第 4 件「不依赖重入」相悖；本机制是该条的必要组成，非另起重试逻辑（续跑仍走 refreshIfNeeded 本体、含缓存新鲜短路）。
- **§3.3 编辑器两处**：commit/clear 的 `removeObject(forKey: "weatherCacheV1")` 各改为 `WeatherService.shared.invalidateAfterKeyChange()`；flashSaved/logSaved 与无变化不写盘 guard 均未动。
- **§3.4 OPS 交叉口径**：按设计未进 guard——invalidate 的刷新是显式编辑后果，Diag 失效行使其在 OPS 禁用期可审计；W-T10 归 OPS 批复核。
- **断言（§3.5 编号顺延记明）**：设计编号 W18-8..10 落码为 **W18-9..11**——W18-8 已被宽屏批 E-1（设置族收窄容器）先占，整体顺延一位，verify 注释内已注映射。W18-9 = 编辑器两处调用计数 2 + WeatherView 段内 `weatherCacheV1` 零残留；W18-10 = 失效本体四件 + Diag 行；W18-11 = 世代捕获恰 1 + 守卫校验恰 4（置 now 2 + 落盘 2）+ refreshPending 接续两锚。本机自跑 **[18] 组全绿（W18-1..11 全 ✓）**；全量跑另有既有产物类两红（ipa 陈旧、产物语言包，构建自解），且跑次中途两次撞上兄弟批在 verify 其他段（[16]/[24]）的半成品语法断点——均非本批段落，本批段落已单独判读全绿。
- **类型检查**：MomentApp primary 遍（build-app2.sh 第二遍同旗标）两跑——首跑撞兄弟批并发写期间的撕裂状态（254 条伪 error，含搜索/SVG 等他批领地）；次跑以 md5 前后一致证文件全程稳定，**本批领地（WeatherService/WeatherKeyEditor 两段及其符号）零 error**，全文件仅剩 2 处 error 在 SVG 批在途调用点（`isSvgData`/`SvgRasterizer` 未定义，归该批收口）。
- **同树纪律**：开工快照树净；落码全程逐 hunk 锚定天气段，完工 diff 复验——本批 hunk 恰 9（WeatherService 7 + WeatherView 2），删除行仅设计内替换点（inFlight 守卫行、置 now ×2、writeCache+打点 ×2、编辑器直删 ×2），他人 hunk 零损伤。过程留痕：编辑器两处替换曾因同文件并行编辑调用互相覆盖丢一处，已即时复验发现并单独补回、计数复核归位（教训：同文件多点编辑禁并行发调用）。
