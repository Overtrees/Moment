# 设置页天气项副标题文案更换 + 五语同步（2026-11-27）

> 状态：**落码完成、未提交、未 bump**（随后续组版，主线定）。基线 HEAD fdb1a67（0.9.56）。
> 用户定案：设置页天气项副标题（原「和风 内置 · 彩云 内置」的状态合成文案）改为固定说明「天气数据源令牌配置」，五语同步。

## 1. 文案来源定位

副标题走共享 i18n 语言包（真源 `rust/apps/web/lang/*.json`，Web 与原生同一真源、原生构建时拷入 .app/lang），非 Swift 字面。

- 旧键：`settings.weather_status`（tf 模板，五包行 220），由设置主页 `SettingsView.weatherMeta` 以双源状态词填充 `{qw}`/`{cy}` 后作天气行 `meta`；状态词来自主页 `weatherSourceWord`（内置/自定义/未设置，键 `settings.weather_builtin` / `weather_custom` / `weather_unset`）。
- 默认态（双 key 均构建注入）渲染即用户所见的「和风 内置 · 彩云 内置」。

### 旧值五语抄录（settings.weather_status，改前）

| 语言 | 模板值 | 默认渲染 |
|---|---|---|
| zh-CN | `和风 {qw} · 彩云 {cy}` | 和风 内置 · 彩云 内置 |
| zh-TW | `和風 {qw} · 彩雲 {cy}` | 和風 內置 · 彩雲 內置 |
| en-US | `QWeather {qw} · Caiyun {cy}` | QWeather Built-in · Caiyun Built-in |
| ja-JP | `QWeather {qw} · Caiyun {cy}` | QWeather 内蔵 · Caiyun 内蔵 |
| ko-KR | `QWeather {qw} · Caiyun {cy}` | QWeather 내장 · Caiyun 내장 |

## 2. 处置：退役旧键 + 新键同位（键数净账守恒）

副标题语义已由「双源状态」改为「固定说明」，`weather_status` 的 status 语义死亡。按项目先例（`weather_save` / `weather_active` 退役口径，W18-2/W18-6 零残留守卫）退键、不留名实不符的键：

- 五包同位：删 `settings.weather_status`、增 `settings.weather_sub`；每包键数 360 不变（[9] 键集合一致 + 键数断言守恒）。
- 设置主页：行 meta 改直引 `Lang.t("settings.weather_sub")`；主页侧状态合成机器 `weatherMeta` + `weatherSourceWord` 整删（其唯一消费方即该行），原址留注释说明逐源状态的归属（二级页）。
- 天气组头注释同步：「只留状态入口」改为「只留入口行（副标题 = 固定说明键 settings.weather_sub）」。

### 新值五语与译法出处

| 语言 | 新值（settings.weather_sub） |
|---|---|
| zh-CN | 天气数据源令牌配置（用户定案原文） |
| zh-TW | 天氣資料來源令牌設定 |
| en-US | Weather data source token settings |
| ja-JP | 天気データソースのトークン設定 |
| ko-KR | 날씨 데이터 소스 토큰 설정 |

译法纪律与诚实标注：

- **「令牌 / token」与「数据源 / data source」在五包内均无先例**（全包 grep 零命中）——zh-CN 用定案原文引入；其余四语对这两个新词取各语标准译词：令牌（zh-TW 同字）/ token / トークン / 토큰；資料來源 / data source / データソース / 데이터 소스。
- 其余成分全部从包内先例：天气 = 天氣 / Weather / 天気 / 날씨（`settings.weather`，各包行 214）；数据 = 資料 / data / データ / 데이터（`settings.data`，各包行 203；zh-TW 包内「資料」21 见、「數據」0 见，取資料）；配置 = 設定 / settings / 設定 / 설정（`settings.title` 各包先例：設定 / Settings / 設定 / 설정）。

## 3. 出现点清单与逐点处置

| # | 出现点 | 处置 | 理由 |
|---|---|---|---|
| 1 | 设置主页天气行 meta（`weatherMeta` → SetRow，MomentApp.swift） | **改** | 用户点名处；改直引新键、状态合成机器整删 |
| 2 | 天气二级页 WeatherView：逐字段来源词（`sourceWord`）+ 生效行（`effectiveText`，「当前生效：内置 Key」等） | 不改 | 配置页内的功能性状态呈现（哪把 key 在生效），与主页副标题非同一语义；`builtin` / `custom` / `unset` / `effective_*` 键仍归该页消费、不成孤儿 |
| 3 | 二级页字段名 `settings.weather_qweather` / `weather_caiyun`（和风天气 Key / 彩云天气 Key） | 不改 | 字段名，非副标题文案 |
| 4 | 桥侧：worker.js / CONNECTOR.md / MomentBridgeSettings.swift | 不改 | 已查：只有工具名 `settings_clear_weather_key` 与「weather key state/source」的功能描述，无此副标题文案 |
| 5 | Web 前端（rust/apps/web/src） | 不改 | 已查：Web 无 `settings.weather_*` 消费点（天气 key 走构建注入，weather.rs），Web 设置页没有这一行 |
| 6 | 历史报告 plan_weather_settings.md / impl_weather_settings.md 的旧值记载 | 不改 | 历史档案 |

全仓复查：`weather_status` / `weatherMeta` / `weatherSourceWord` 在代码与语言包中零残留（仅历史报告存档）。

## 4. Web 影响面结论

语言包是 Web 与原生的**同一真源**（`rust/apps/web/lang/`），原生构建脚本将其拷入 .app/lang（verify [9] 以 md5 对账）。本次只改真源一处、不分叉：

- Web 呈现零影响：Web 不消费该键（上表 #5），其设置页无此行。
- 原生下次构建时 .app/lang 随真源同步（本机 verify 的「产物语言包与 Web 源不一致」✗ 即此 stale 标记，tree 重建自解）。
- `rust/apps/web/dist/lang/` 是未入仓的构建产物，未手改、部署构建时自生成。

## 5. 断言（verify_ios.sh [18]）

- W18-1 改写：主页行断言由 `meta: weatherMeta` + `weather_status` 改为 `settings.weather_sub` 直引在位。
- W18-2 扩围：零残留清单加 `weatherMeta` / `weatherSourceWord` / `"settings.weather_status"`（与旧表单退役同格）。
- W18-6 改写：退役零键清单加 `settings.weather_status`；在位清单以 `settings.weather_sub` 替换之。
- **W18-7 新增（文案锚）**：五包 `weather_sub` 值非空且无 `{}` 占位符（固定说明、非模板，防旧模板回潮）；zh-CN 值逐字等于「天气数据源令牌配置」。
- [9] 不动：键集合一致、键数 360（退一进一）天然守恒。

## 6. 验证与纪律

- 本机 verify 自跑：**273 ✓**，[9] 键集合/键数/引用键全绿，[18] W18-1…W18-7 全绿；仅剩 2 条既有产物类 ✗（ipa 陈旧、产物语言包 stale——源包刚改、待 tree 重建自解），非本批引入。Swift 编译级随主线 tree 冒烟（本机无 swiftc，项目惯例）。
- 在途纪律：动工前快照全树 diff（1741 行）并逐 hunk 映射——在途批（三条回归线 + U4a + 圆角/布防）在 MomentApp.swift 的 SettingsView 邻域只有圆角批的一行值替换（glassCard 半径），与本批编辑行不重叠；完工后 pre/post diff 的 +/- 行逐行比对，7 个在途文件（含两共享文件 MomentApp.swift / verify_ios.sh）他人改动行**零缺失**。
- 改动文件：`rust/apps/web/lang/{zh-CN,zh-TW,en-US,ja-JP,ko-KR}.json`、`rust/apps/ios/app/MomentApp.swift`（设置段）、`rust/apps/ios/app/verify_ios.sh`（[18] 组）、本报告。

## 7. 真机终判点

1. 设置页天气行副标题显示新文案；五语各切一遍，副标题随语言即时切换为对应译文。
2. 点进天气二级页：逐字段来源词与「当前生效」行照旧（状态呈现未受影响），改/清自定义 key 后主页副标题保持固定说明、不再随状态变。
