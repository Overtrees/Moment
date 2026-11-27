# 设置页天气分组重构 · 落码报告

依据：`plan_weather_settings.md`（主方案）+ `audit_weather_settings_gap.md`（差距账 S1–S7 / I1–I7 与增补 B1–B5），叠加主线增补口径（键数基线 351、verify 组号 [18]、key() 进程级缓存、命名二选一记账、OpsDirectives 天气 guard 勿伤）。落码完成，未提交、未 bump（落版号由主线统一排）。

## 一、差距 14 项逐项对账

### 样式 S1–S7

| # | 处置 | 落点 |
|---|---|---|
| S1 组卡形态 | 主页表单卡（radius 32）→ 单行导航卡（radius 28，数据组同型）；表单移入 WeatherView 二级页 | SettingsView 天气组改 `SetRow` + `glassCard(radius: 28)` |
| S2 行型 | 自绘 `weatherKeyRow` 删除；主页走 SetRow，子页走行卡口径（名 16 semibold + 状态/副文案 12） | WeatherView.weatherCard |
| S3 卡内布局 | 主页卡内距由 SetRow 自带；子页卡 padding 16、卡间隔 6（LanguageView 口径） | WeatherView body |
| S4 状态呈现 | 独立状态词（自定义 accent/700、内置/未设置次级）+ 生效来源行（12 / T.glassLabel），判据 = `WeatherService.keySource` 单一派生 | 主页 meta 与子页共用 |
| S5 说明文案 | note 从主页卡底 HStack 拆出，子页末尾独立成卡 | WeatherView 说明卡 |
| S6 保存钮 | 废除（全设置页唯一的保存钮形态退役），反馈改状态即时刷新 + 「已保存」在状态词位短暂呈现约 1.2s | WeatherKeyEditor.flashSaved |
| S7 组距连带 | 关于组头 topPad 40 → **32** 重推（天气卡改 .backup-card 口径：16+12+4），注释账已同步改写 | SettingsView 关于组头 |

### 交互 I1–I7

| # | 处置 | 落点 |
|---|---|---|
| I1 提交模型 | 整组批量保存 → 逐字段即时提交：onSubmit / 失焦（@FocusState 变 nil）/ 粘贴 / 清除 / onDisappear 兜底 flush | WeatherKeyEditor.commit |
| I2 生效可见性 | 无「未保存」中间态：提交即写盘、状态词与生效来源行即时刷新、saved 短暂呈现 | 同上 |
| I3 校验与反馈 | 软提示不硬拦：和风 ≠32 位 / 彩云 ≠16 位时呈 warning 提示行（业务常量、注释账在码内）；提交去除**全部**空白（治粘贴内部换行污染，现行只 trim 首尾的小缺陷一并根治） | weatherCard 提示行 + commit 清洗 |
| I4 清除路径 | 显式「清除自定义」钮（仅 custom 时出现）：删 UserDefaults 键（非写空串）、清缓存、状态回落内置/未设置；清空字段提交为第二路 | WeatherKeyEditor.clear |
| I5 导航层级 | Sub 加 `.weather` case + destination switch 接 `WeatherView()`；主页 SetRow 进入 | SettingsView |
| I6 进入留痕 | 子页 onAppear 记 `SET weather enter`（G5 同口径） | WeatherView |
| I7 写盘粒度 | 逐字段与现存值比较，无变化不写盘、不清缓存、不打点；缓存删除只在有效变更时 | commit 的 guard |

能力等价（方案 §4 十二项）：双 key 自填、优先序自填 > 内置、构建注入、清除回退、状态可见性（超集）、保存反馈、变更清缓存、Diag 只记来源不记值、只存本机不入备份、trim 加强、默认掩码（+ 本屏显隐切换，SF Symbols eye/eye.slash、无障碍标签走新键）、天气消费链——逐项在位，无一丢失。显隐默认恒掩码、进页恒掩码，只影响本屏呈现。

Diag：`SET weather key saved` 升级为生效来源口径 `qweather=custom|builtin|none caiyun=…`（清除并入此行）；WeatherService 既有 WEATHER 行未动。

## 二、语言键清单与净账

- 新增 11 键 ×5 语：`settings.weather_builtin`、`settings.weather_custom`、`settings.weather_status`（tf 模板 {qw}/{cy}）、`settings.weather_effective_builtin`、`settings.weather_effective_custom`、`settings.weather_paste`、`settings.weather_clear`、`settings.weather_len_hint_qw`、`settings.weather_len_hint_cy`、`settings.weather_show`、`settings.weather_hide`。值案按方案 §5 五语落齐。
- 退役 2 键 ×5 语：`settings.weather_save`、`settings.weather_active`——五包同步删，Swift 源码引用零残留（grep 实证；文档与 build 产物中的历史提及不在源码面）。
- 复用不动：`settings.weather` / `_qweather` / `_caiyun` / `_note` / `_saved` / `_unset`。
- 净账：**351 + 11 − 2 = 360 键/包**（实测五包各 360、键集合一致）；verify [9] 期望已同步改 360 并补账注释。

## 三、缓存处置（增补 B3）

`WeatherService` 新增 `KeySource` 枚举（custom/builtin/none）+ `keySource(_:)` + `customKey(_:)`；bundle `weather-keys.json` 解析改 `private static let bundleKeys` 进程级单次缓存，`key()` 与 `keySource()` 共用同一解析结果——严格同判（bundle 解析失败时 key() 返 ""、keySource 返 .none），且主页 meta / 子页状态每轮求值不再重复读盘。`key()` 优先序与返回值行为不变。

## 四、命名处置（增补 B4，二选一记账）

组头与主页入口行**同名保留**（均 `settings.weather`）：组头是分区标签（14 semibold uppercase 次级），行是该组唯一目的地入口（16 semibold + 状态 meta），层级与形态不同、读感不构成重复；另造行题（如「天气 Key」）需 +1 键、打破本批锁定的 360 净账，且与子页标题同名口径冲突。代码注释账已在天气组处记明此处置。

## 五、红线核对

- **OpsDirectives 天气 guard 未伤**：ListView 的 `OpsStep.weatherRefresh` guard 段与 `WeatherService.refreshIfNeeded()` 调用面零改动（本批未触 ListView；WeatherService 只动 key 读取层，fetch/refresh 链原样）。
- 退役零残留：`WeatherKeyUI` 类、`@StateObject weatherUI`、`weatherKeyRow` 函数、主页表单卡整段全删，[18] W18-2 以代码行 grep 锁死。
- 样式全走既有令牌与家族档位，零新令牌、零裸值（长度期望 32/16 为业务常量，码内注释账注明非格式契约）。

## 六、verify

- 新增 **[18] 组** W18-1…W18-6（二级页/路由/主页行、旧形态零残留、keySource+缓存、即时提交面、关于 topPad 32、退役键五包零键+新键在位），**本机自跑全绿**；[9] 键数 360 项绿、五语集合一致绿、Swift 引用键齐全绿。
- 本机全量 verify 仅剩三红：ipa 陈旧、产物语言包不一致（本机无新构建产物，既有口径，tree 构建后消）与 **[10] S1 组头 topPad 分档**——S1 断言仍期望旧账 40/32/40，源码已按方案重推为 40/32/32。按本批边界（verify 只加 [18]、不改他组断言，[9] 除外），**[10] S1 期望同步（40/32/40 → 40/32/32）留主线在合流时改**，此处明示不静默。
- Swift 语法级自检：swift-frontend -parse MomentApp.swift 零错误。类型级错误只能在 tree 冒烟暴露（本批新面：@FocusState 枚举绑定、SecureField/TextField 条件切换、嵌套 ObservableObject），主线冒烟时请优先看 WeatherView 相关报错。
