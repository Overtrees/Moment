# AUD-C-02 落码：诊断页与日志视窗页纳入宽屏 720 收窄

- 裁定：用户 2026-11-28 裁定「做」（审计总册 §6-2 决策点，用户在四项裁定中对 C-02 的答复）；审计分册 C 原列「DiagLogPage 可单独定案保留」备选未采用，两页均纳入。
- 范围：0.9.63 批次，未提交（工作树留主线组版）；本机自检止步，tree 冒烟随 0.9.63 组版统一跑。

## 一、收窄单点（现行实现，落码前回源核对）

- 单点 = `settingsContentFrame()`（MomentApp.swift，View 扩展）：内距横 20 / 顶 126 / 底 40 + `.frame(maxWidth: 720)` + `.frame(maxWidth: .infinity)`（居中）。窄屏（可用宽 < 720）时 720 框不生效、与原手抄逐值等价零变化。
- 落码前接入面：设置六页（主文件 5 处调用 + MomentBridgeSettings.swift 1 处）与权限页（MomentPermissions.swift 1 处），共 7 页；救援页在 MomentRescue.swift 手抄同口径一份（E-2，R19-14 单独锁，属既定留置，本批不动）。
- 未入面（本批对象）：DiagView 内容 VStack 尾手抄 `.padding(.horizontal, 20) / .padding(.top, 126) / .padding(.bottom, 40)` 三行——与单点逐值等价、唯缺 720 框；DiagLogPage 终端卡自持内距（横 20 / 顶 126 / 底 40 + 安全区），无任何收窄。

## 二、落码（机制根单点，两页同源接入）

1. **收窄钳抽单点** `wideNarrowClamp()`（与内容框同扩展、紧邻定义）：`.frame(maxWidth: 720)` + `.frame(maxWidth: .infinity)`。`settingsContentFrame()` 本体改经此钳收口（修饰链逐项等价：内距三行 + 钳 = 原内距三行 + 两框，行为等价 proven by 链对照）。720 字面在主文件收敛为恰一处（钳定义内）。
2. **DiagView**：内容 VStack 尾手抄三行删除，改调 `.settingsContentFrame()`——与设置六页字面同一接入面。手抄值与单点逐值相同，窄屏呈现零变化；宽屏内容入 720 居中列，页头（ChromeView）保持全宽、与设置族同形态。
3. **DiagLogPage**：终端卡（ScrollView）在其自持内距之后追加 `.wideNarrowClamp()`。不走设置族整框的原因：卡底距为 `40 + safeAreaInsets.bottom`（S7 口径），整框的平 40 会改窄屏呈现、违反零变化——故只共用钳、底距自持。钳作用域含卡内距（横 20），宽屏卡总宽 720 与设置族内容列同口径；窄屏钳不生效零变化。页头行（返回/文件名/导出）保持全宽，与设置族页头形态一致。

## 三、断言（verify_ios.sh）

- **W18-8 改判**（原「Diag 不在本批收敛面」口径作废，沿革注已写入断言头注）：`settingsContentFrame()` 主文件计数 6→7（定义 1 + 六页调用，新增 DiagView）；`.padding(.top, 126)` 主文件计数 4→3（容器定义 1 + 视窗页 1 + 图片页顶让 1；诊断页手抄 1 已收敛）。
- **新组 [56] DG56-1..3**（尾部自组）：
  - DG56-1 钳单点锁：主文件 `.frame(maxWidth: 720)` 字面恰 1 处且位于钳定义段内；钳调用共 3（定义行 + 设置框本体 + 视窗页卡）；设置框定义段含钳调用——两面共用同钳、无第二套收窄逻辑。
  - DG56-2 诊断页锁：DiagView 段内含内容框调用且手抄 `.padding(.top, 126)` 零残留。
  - DG56-3 视窗页锁：DiagLogPage 段内含钳调用且 `40 + geo.safeAreaInsets.bottom` 自持底距仍在位（窄屏等价守卫，防整框顶替）。
- 本机实跑：verify 556 ✓ / 2 ✗——2 红为既有产物红（ipa 陈旧、产物语言包待重构建），tree 组版构建后归零；W18-8 与 DG56-1..3 全绿。本机无 swiftc，Swift 语法面由 tree 冒烟构建步终判。

## 四、登记同步

- 覆盖矩阵 plan_selftest_coverage.md：§4.7 新增 **SET-17**（BK 层，已覆盖口径 + 真机宽屏抽样终判归口）。
- 审计总册 audit_full_2026-11-27.md：AUD-C-02 登记行处置改「已裁已落」，§6-2 决策点划线结案。
- 审计分册 audit_full_c_settings.md：C-02 标题行改「已裁已落」并注备选未采用。

## 五、真机终判点（归用户，iPad/横屏）

1. iPad 或横屏宽屏下打开诊断页：内容列居中收窄至 720、两侧留白与设置页一致；窄屏（iPhone 竖屏）呈现与改前无异。
2. 诊断页点入任一日志视窗页：终端卡居中收窄 720、卡底距不变（不贴屏底）；页头行全宽。
3. 深/浅两主题各看一眼，收窄列背景与页面根背景同源无色带。

## 六、并发与边界

- 动工前 git diff 全量快照为空（在途三批尚未落树），本批为首落；改动面仅 MomentApp.swift 三段（钳定义/DiagView/DiagLogPage）、verify_ios.sh（W18-8 + 尾部 [56] 组）、三份文档。与状态栏二轮批（MomentStatusBar* + [53]）、标题胶囊批、前向删除批文件段零交叠。
- 未动：MomentRescue.swift 的 E-2 手抄收窄（既定留置，R19-14 在位）、图片页 `.frame(maxWidth: 720, alignment: .leading)`（图文卡口径，非本收敛面，字面形态不同不入普查）。
