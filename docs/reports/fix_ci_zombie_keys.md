# CI 门禁盲区根治：僵尸键扫描动态引用误判（2026-11-27）

## 背景

`moment-rust-web` 工作流在 main 上连红多笔（a0d336c、0f6a097、60efba4、3688ac6、8a6cadb，
最新 05:40 UTC 失败），失败步为 `test-build-verify`。本地复现确认红在
`scripts/verify_rustweb.sh` 第 7b 节僵尸键扫描。

根因：第 7b 节只认 `Lang.t("字面量")` 一种引用形态，节首注释中断言的
「实参字面量扫描即完备」已被三类动态引用证伪。14 个键被误判为僵尸，
删键会直接弄坏运行时文案。

## 修复前重扫（HEAD 8a6cadb，未修脚本）

14 个误报僵尸键，全部为动态引用：

| 类 | 键 | 引用形态 |
|---|---|---|
| 桥状态 8 个 | bridge.state_connected、state_connecting、state_backoff、state_pairing、state_unpaired、state_revoked、state_ops_disabled、state_off | D1：`linkStateKey` 计算属性 switch 返回字面量，调用方 `Lang.t(bridge.linkStateKey)`（MomentBridge.swift:242–251，调用点 MomentBridgeSettings.swift:154、MomentApp.swift:16172） |
| 桥 scope 2 个 | bridge.scope_write、bridge.scope_ops | D2：`Lang.t("bridge.scope_" + scope)` 拼接（MomentBridgeSettings.swift:23）；scope 值域来自配对协议，不在 Swift 内 |
| 天气 4 个 | settings.weather_qweather、settings.weather_caiyun、settings.weather_len_hint_qw、settings.weather_len_hint_cy | D3：`weatherCard(titleKey:/hintKey:)` 纯字符串参数，函数内 `Lang.t(titleKey)` / `Lang.t(hintKey)`（MomentApp.swift:16954–16964 调用点、17026–17100 定义） |

另：60efba4 时的 7 个救援僵尸键（rescue.open_readonly、rescue.cache_clear、
rescue.cache_clear_confirm、rescue.watchdog_bar、rescue.enter、rescue.readonly_banner、
rescue.readonly_write_blocked）**已全部被 492b17a 的 R2/R3 落码认领**，
本次重扫零救援键残留——**无未认领救援键，不存在待裁断的删键项**。
认领位置：MomentRescue.swift（open_readonly、cache_clear、cache_clear_confirm、
watchdog_bar、enter）、MomentApp.swift（enter、readonly_banner、readonly_write_blocked）。

注：`bridge.scope_read` 从未进误报清单，因 MomentBridgeSettings.swift:185 有
`Lang.t("bridge.scope_read")` 字面量兜底（空 scope 回退分支）。

## 修复规则（只改脚本，App 侧零改动）

文件：`scripts/verify_rustweb.sh` 第 7b 节（注释 + Python 块）。字面量扫描原样保留，
新增动态键值域解析，值域证据只认四处：

- **D1 声明体字面量**：`Lang.t(变量)` 的变量名解析到 `var/let/func` 声明，
  取声明体内全部键形字面量（`linkStateKey` 的 switch 八个 return 值）。
  另含两条同域规则：循环变量取自同域 `for-in` 字面量数组
  （`Lang.t(key)`，`slash.group_basic` / `slash.group_media` 取自
  `rows(_:)` 内 `[(0, …), (1, …)]`；该二键同时也被 Web src 认领，
  本规则为纵深防御）；同域 `let/var 变量 = "字面量"` 绑定。
  解析顺序为先同域（形参 → 循环变量 → 局部绑定）后全局声明，避免他处同名变量误解析。
- **D2 拼接展开**：`Lang.t("前缀" + 变量)` 时，先查包围函数的形参调用点实参；
  无调用点字面量时（如 scope 值来自中继配对载荷），以后缀语料展开——
  裸词字面量取自 Swift 代码 + `bridge/relay/*.js`，仅当 `前缀+后缀` 恰为包内键时认领。
  scope 三值证据现为协议源：`worker.js:314`（默认 `["read"]`）、
  `:360–361`（`scopes.includes("write"/"ops")` 授权判定）。
- **D3 参数传递**：`Lang.t(参数)` 时解析包围函数定义，按标签名或位置序号
  收集全部调用点实参字面量（weatherCard 两处调用点的 titleKey/hintKey 各二值）。

每条动态认领在 CI 输出中逐条打 log（`✓ 动态键：<键> ← <规则与证据>`），供复核；
汇总行同步计入动态解析键数。

### 诚实边界（D2 后缀语料法）

- 后缀语料法有误报可能：无关字面量恰等于某后缀会掩盖真僵尸。
  两项缓解：后缀只取**代码内**字符串字面量（跳过 `//` 与 `/* */` 注释内的引号，
  注释里的巧合词不算证据）；证据优先引中继 JS（协议源）后引 Swift，
  且每条认领逐条打 log。新增动态形态时须同步扩展本节解析（节首注释已注明）。
- 解析器为启发式而非 Swift 全量解析：含默认值的函数签名（参数里带 `=`）会被
  声明守卫跳过；`var body` 类计算属性不作包围函数（其内 `Lang.t(变量)` 走全局声明解析）。
  当前目标声明均无默认值，本批不受影响。

### 修复中抓到的实现 bug

首版 `_parse_params` 把单名参数（如 `titleKey: String`）的标签算成 `None`
（应为参数名本身兼作外部标签），导致 D3 走位置序号分支、取到
`titleKey: "…"` 整段而非字面量，天气四键首轮仍红。已修正为：
无前置标签词时标签 = 参数名；`_` 前缀时标签为空（纯位置参数）。
修正后天气四键认领成功。

## 修复后重扫（同一 HEAD 8a6cadb）

第 7 节全绿，退出码 0：

- 7a 占位符跨包一致：360 键五包齐平。
- 动态解析 **17 键**：bridge.state_* 8 个、bridge.scope_* 3 个、
  settings.weather_* 4 个、slash.group_* 2 个（逐条证据见 CI 输出）。
- 僵尸键扫描：360 键在 Web src 或原生引用面均有引用
  （原生字面引用 196 键，动态解析 17 键），**零僵尸**。
- 7c 疑似漏译仅警告（既有：ja-JP 14 键、zh-TW 49 键，不判失败）。

验证方式：第 7 节 Python 块从已改脚本抽出重跑（`bash -n` 校验脚本语法通过）。
完整 `verify_rustweb.sh` 未在本机全跑：本机无已构建 dist，第 8 节体积预算门
无产物可核——CI 上 `build web dist` 步骤在前，全量以 CI 为准。

## 改动清单（未提交、未推送）

- `scripts/verify_rustweb.sh`（唯一改动文件，+304/−11）：
  第 7b 节首注释改写（旧「实参字面量扫描即完备」口径作废，记三类动态形态与解析规则）；
  Python 块新增动态解析（`_paired_body` / `_func_spans` / `_parse_params` /
  `_enclosing_func` / `_declaration_body` / `_callsite_literals` /
  `_code_string_literals` / `_suffix_evidence` / `_lang_calls` + 认领循环与逐条 log）；
  `referenced()` 并查动态键集；汇总行计入动态解析键数。
- App 侧零改动（`MomentApp.swift` / 桥文件 / `MomentRescue.swift` 均未动）。
- 并行说明：工作树内 `rust/apps/ios/app/verify_ios.sh` 另有一笔未提交改动
  （R21-9 附件行半径裁断），属 0.9.52 半径线，非本批。

## 待主线

- 收口复推本批后，以 CI `moment-rust-web` 全绿为准（本机第 7 节已绿，第 8 节待 CI 构建产物核验）。
- 未认领救援键：无，无删键裁断待办。
