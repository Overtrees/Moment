# 设置页「天气」分组重构方案（只读调研产出，未落码）

立项来源：用户反馈现行天气组太平、太杂、不简洁、交互不够优雅，指示可引用系统 API 增优（行为等价更优口径）。本方案全部回源现行实现与 Web 口径，功能等价面以现行实现为准，不丢任何现行能力。

## 0. 现行实现盘点（回源）

### 0.1 原生 UI 与存取（MomentApp.swift）

- 设置主页天气组（0.9.43 方案 A 后位于数据组之后、关于组之前）：`SectionHeader(settings.weather, topPad: 32)` + 一张 `glassCard(radius: 32)` 表单卡，卡内平铺（SettingsView body，约 :14330–14385）：
  - `weatherKeyRow` ×2（:14207）：VStack（标题 13 semibold + `SecureField` 14），placeholder 按**生效** key 判空——空 → 「未设置」、非空 → 「已生效（可自填覆盖）」。注意此判据用的是 `WeatherService.key()`（生效值），内置与自填在 UI 上不可区分。
  - 底部 HStack：说明文案（`settings.weather_note`，12/textSecondary）+ Spacer + 保存 Button（14 semibold/T.accent），保存后文案切「已保存」，任一字段编辑即经 Binding set 回置 `saved=false`。
- 存取模型 `WeatherKeyUI`（:14161，SettingsView 内嵌 ObservableObject）：`@Published qweather/caiyun` 初始化自 UserDefaults `weatherKey_qweather` / `weatherKey_caiyun`；`save()` —— 双字段 trim 后写回 UserDefaults（空串照写）、删 `weatherCacheV1`（下次进列表重拉）、`saved=true`、Diag `SET weather key saved qweather=set|empty caiyun=set|empty`（只记有无、绝不记值，G5 口径）。
- **现行无任何校验**：无长度/格式检查、无粘贴钮、无显式清除钮（清除 = 手动清空字段再保存）、无逐字段状态呈现（只有 placeholder 一处混合信号）。

### 0.2 消费面 WeatherService（:12370）

- `key(_ name:)`（:12387）优先序（用户裁定）：UserDefaults `weatherKey_<name>` 非空 → bundle `weather-keys.json`（build-app2.sh:120-126 自 `~/ios-native/weather-keys.json` 构建注入）同名值 → `""`。
- `fetch()`（:12460）：和风 key 为空 → 整链不发请求（Diag `WEATHER no api key, skip`）；和风主链失败 → 彩云兜底（`fetchCaiyun` 自读 key，空则 `WEATHER caiyun skipped (no key)`）；双失败记 `WEATHER provider=fail (qweather + caiyun)`。列表页 1.5s 触发 + 30 分钟缓存 `weatherCacheV1`（ListView :12948 `refreshIfNeeded()`）。
- 错 key 的行为：请求失败走兜底/失败打点，无 UI 面反馈——设置页是唯一能看见 key 状态的地方，现行却看不清。

### 0.3 Web 对应面

- Web **没有** key 设置 UI：`weather.rs:100-110` 双 key 走部署注入（`window.__APP_CONFIG__` / 常量），仓库不落值；天气链口径（和风主 → 彩云兜底、30 分钟缓存、双失败打点）与原生同源同口径。
- 结论：天气 key 自填是**原生独有能力**（用户 H17 裁定：默认构建注入 + 设置页自填），Web 无形态可抄，形态设计按原生设置页自身家族一致性 + 系统惯例定。

### 0.4 设置页家族形态（重构必须同族）

- 子页统一：`ChromeView(title:onBack: dismiss)` + ScrollView + VStack，外距横 20 / 顶 126 / 底 40（BackupView :14533、GesturesView :14958、LanguageView :15024 皆然）；入口统一经 `SettingsNav.route`（Sub 枚举）+ `navigationDestination(isPresented:)` switch（:14431），**不用字面 NavigationLink**；子页 onAppear 记 `SET xxx enter`（G5）。
- 主页导航行统一 `SetRow`（:14044：标题 16 semibold + meta 12/T.glassLabel + 「›」@45%，Button + RowPressStyle），数据组四行（备份/语言/手势/诊断）全是此形态，卡 `glassCard(radius: 28)` + `rowDivider`。
- LanguageView 是「即时生效」先例：点选即应用、无保存钮，状态以纯文字呈现（使用中/内置，12pt，生效 accent/700、余次级）。

## 1. 系统 API 候选核定（SDK 头 ~/ios-native/iPhoneOS27.2.sdk，部署目标 16.0 — build-app2.sh `-target arm64-apple-ios16.0`）

| 候选 | 核定 | 理由 |
|---|---|---|
| `navigationDestination` + route 枚举 | **采用（既有机制）** | 与全设置页同构，新增 `.weather` case 即可，不引入字面 NavigationLink |
| `SecureField` | **采用（现行已用）** | 掩码口径不变；加 `.submitLabel(.done)` + `onSubmit` 提交点 |
| `UIPasteboard` | **采用** | 「粘贴」钮用户主动点按后读 `UIPasteboard.general.string`，系统粘贴横幅即知情面；SecureField 长按粘贴本就有，钮解决可发现性 |
| `@FocusState` | **采用** | 字段失焦 = 提交点之一；兼管键盘收起 |
| `ContentUnavailableView` | **不采用** | SDK swiftinterface 实证 `@available(iOS 17.0, *)`，部署目标 16.0 需 #available 门；且本页无整页空态需求（双未配置由状态行呈现），不为它引版本门 |
| `Form` / `List` 分节 | **不采用** | 设置页家族全部自研 ChromeView+ScrollView+glassCard（与 Web 形态对齐的既定体系），单页改 Form 会与兄弟页视觉/滚动/顶栏全面分叉 |
| SF Symbols eye/eye.slash | **采用** | 显隐切换钮（见 2.3），系统标准字形 |

## 2. 设计方案

### 2.1 主页形态：天气组收为单行入口

- 组头与组序**不动**：`SectionHeader(settings.weather, topPad: 32)`（0.9.43 方案 A + S1 组距账不推翻）。
- 组卡由表单卡改**单行导航卡**：`glassCard(radius: 28)`（与数据组同口径，不再用表单卡的 32）内放一个 `SetRow`：
  - title = `settings.weather`（天气）
  - meta = 双 key 状态合成（`Lang.tf("settings.weather_status", {qw, cy})`，模板「和风 {qw} · 彩云 {cy}」），状态词三态：**内置 / 自定义 / 未设置**（未设置复用既有键 `settings.weather_unset` 值不变）。
  - chevron 恒显，action = `nav.route = .weather`。
- 一致性论证：主页自此全是「组头 + 导航行卡」（外观组为系统跟随说明行，属展示行既定形态），天气不再是唯一把表单摊在主页的组；meta 合成法与备份行（新鲜度合成文案）、语言行（当前语言本名）同为「一行看清现状」的既定口径。
- 状态派生（单一真源）：`WeatherService` 新增 `static func keySource(_ name:) -> KeySource { .custom / .builtin / .none }`（user 非空 → custom；bundle 非空 → builtin；皆空 → none），`key()` 改为在其上取值，避免主页与子页各写一份判据。主页 meta 与子页状态共用此派生。

### 2.2 二级页 WeatherView（新结构，落点见 §4）

`ChromeView(title: settings.weather)` + ScrollView + VStack（外距同族：横 20 / 顶 126 / 底 40），onAppear 记 `SET weather enter`。自上而下：

1. **和风卡**（独立卡，glassCard radius 32 — LanguageView 行卡先例）：
   - 头行：名称 `settings.weather_qweather`（16 semibold/textMain）+ 右侧状态词（12pt；custom 时 accent/700、builtin 时次级「内置」、none 时次级「未设置」—— LanguageView rowCard 状态口径）。
   - 生效来源行（12/T.glassLabel）：custom → `settings.weather_effective_custom`（当前生效：自定义 Key）；builtin → `settings.weather_effective_builtin`（当前生效：内置 Key）；none → 同行呈 `settings.weather_unset` 并提示天气不可用语义由状态词承担，不另造文案。
   - 输入行：SecureField（或显隐态 TextField，见 2.3），placeholder = 有自填时呈掩码语义外的提示「自填 Key」类——直接复用状态行信息，placeholder 只留 `settings.weather_unset` 于空态；`.autocorrectionDisabled` + `.textInputAutocapitalization(.never)`（现行口径保留）+ `@FocusState` 绑定。
   - 操作行（13pt 文本钮，T.accent）：**粘贴**（`settings.weather_paste`，读剪贴板 → 去全部空白 → 填入并立即提交）；**清除自定义**（`settings.weather_clear`，仅 custom 时出现；点按即删 UserDefaults 该键、清缓存、状态回落内置/未设置）。两钮以 `rowDivider` 同色细线或间距分隔，不做大按钮。
   - 长度软提示行（见 2.4）：命中时出现，12pt/T.warning。
2. **彩云卡**：同构（名称 `settings.weather_caiyun`，其余同）。
3. **说明卡**：`settings.weather_note` 全文（12/textSecondary，glassCard radius 32，内距同 LanguageView 卡），位置在两卡之后——说明从主页收进子页，主页只剩状态。

### 2.3 保存模型：废除全局保存钮，改逐字段即时提交

- 现行「改完必须记得按保存」是平铺形态的主要交互税。改按系统惯例与本 app 先例（LanguageView 点选即生效）：**提交点 = onSubmit（键盘 Done）/ 失焦（@FocusState 变 nil）/ 粘贴 / 清除 / 页面 onDisappear 兜底 flush**。提交动作（逐字段）：trim + 去内嵌空白 → 与现存值比较，无变化不动作；有变化 → 写 UserDefaults（空值改 `removeObject`，与现行写空串等价、更干净）→ 删 `weatherCacheV1`（保持现行「变更即清缓存」口径，不做生效值 diff 的精细化）→ Diag（见 §3）。
- 反馈：无保存钮后，反馈 = 状态词与生效来源行即时刷新 + 提交瞬间该卡状态词位置短暂呈 `settings.weather_saved`（已保存，既有键复用，约 1.2s 后回状态词）。不引 toast（设置页家族无 toast 先例，备份页 toast 是其页内既定件，不外溢）。
- 显隐切换：每卡输入行尾 eye/eye.slash 钮（SF Symbol，T.textSecondary），在 SecureField 与 TextField 间切换本卡字段的掩码态。理由：32 位 key 粘贴后无从核对是现行真实痛点；显隐只影响本屏呈现，不改存储与掩码默认态（默认恒掩码，进页恒掩码）。无障碍标签用新键 `settings.weather_show` / `settings.weather_hide`。
- 风险与兜底：即时提交下「打一半退页」会存下半截 key——与现行「打一半按保存」同险，且软长度提示 + 状态行使异常可见、WEATHER 失败打点可查；不为此保留全局保存钮（保留即回到旧形态）。半截 key 导致的天气失败走既有兜底链（彩云/失败打点），不新增 UI 打断。

### 2.4 校验：软提示，不硬拦

- 现行实现零校验；服务方 key 格式无契约保证（现行注入值实测：和风 32 位、彩云 16 位，属当前事实非格式承诺）。**只做软提示**：字段非空且长度 ≠ 期望（和风 32 / 彩云 16）时，输入行下呈警告色提示（`settings.weather_len_hint_qw` / `_cy`：「和风 Key 通常为 32 位，请确认无误」），照常保存。硬拦会在服务方改格式时把用户锁死，违根治口径。
- 格式处理：提交时 trim 首尾 + 去除全部空白字符（粘贴常带尾换行/空格，现行只 trim 首尾，粘贴整段带内部换行会存进无效值——此为现行小缺陷，顺带根治）。

### 2.5 令牌与组件复用

- 全走既有：`SetRow`（主页行）、`SectionHeader`（组头）、`glassCard`（卡）、`T.textMain / T.glassLabel / T.textSecondary / T.accent / T.warning / T.borderSoft`；字号字重全用子页家族现行档（16 semibold 名、12 状态/说明、13 操作钮）。零新令牌、零裸值新增（长度期望 32/16 是业务常量，写注释账）。

## 3. Diag 打点清单

- 新增 `SET weather enter`（G5 子页进入行，与 language/backup 同口径）。
- 保留并升级 `SET weather key saved …`：逐字段提交时记一行，状态词改**生效来源**口径 `qweather=custom|builtin|none caiyun=…`（比现行 set|empty 更可诊断：能看出保存后实际生效的是哪层）；仍绝不记值。
- 清除动作并入 saved 行（清除后来源变 builtin/none 即其记录），不另设行。
- WeatherService 既有 WEATHER 行全不动。

## 4. 能力等价清单（现行能力 → 新形态落点，逐项不丢）

| # | 现行能力 | 新形态 |
|---|---|---|
| 1 | 双 key 自填（和风 + 彩云） | 子页双卡各自字段 |
| 2 | 优先序 自填 > 内置 | `WeatherService.key()` 语义不动（仅加 keySource 派生） |
| 3 | 内置默认（bundle 注入） | 构建注入链不动；状态呈「内置」 |
| 4 | 清除回退内置 | 「清除自定义」钮 + 清空字段提交，两路都在 |
| 5 | 状态可见性 | 主页 meta 双状态 + 子页状态词 + 生效来源行（现行 placeholder 混合信号的超集） |
| 6 | 保存反馈 | 状态即时刷新 + 「已保存」短暂呈现（代保存钮文案切换） |
| 7 | 保存后清天气缓存 | 每次有效提交删 `weatherCacheV1`（同现行） |
| 8 | Diag 只记有无不记值 | 保留，状态词升级为来源口径 |
| 9 | 只存本机、不入备份 | 存储仍 UserDefaults（备份走 FFI 库导出，不含 UserDefaults） |
| 10 | trim 口径 | 保留并加强（去全部空白，治粘贴污染） |
| 11 | 字段掩码 | SecureField 默认掩码保留（+ 本屏显隐切换） |
| 12 | 天气消费链（主/兜底/无 key 跳过） | WeatherService 消费逻辑不动 |

## 5. 语言键清单（真源 rust/apps/web/lang/*.json ×5，现 307 键）

- **复用**：settings.weather / _qweather / _caiyun / _note / _saved / _unset（值全不动）。
- **新增 10 键 ×5 语**（值案）：
  - `settings.weather_builtin`：内置 / Built-in / 內置 / 内蔵 / 내장
  - `settings.weather_custom`：自定义 / Custom / 自訂 / カスタム / 사용자 지정
  - `settings.weather_status`（tf，{qw}/{cy}）：「和风 {qw} · 彩云 {cy}」/「QWeather {qw} · Caiyun {cy}」/「和風 {qw} · 彩雲 {cy}」/「QWeather {qw} · Caiyun {cy}」/「QWeather {qw} · Caiyun {cy}」
  - `settings.weather_effective_builtin`：当前生效：内置 Key / Using the built-in key / 目前生效：內置 Key / 現在有効：内蔵キー / 현재 적용 중: 내장 키
  - `settings.weather_effective_custom`：当前生效：自定义 Key / Using your custom key / 目前生效：自訂 Key / 現在有効：カスタムキー / 현재 적용 중: 사용자 지정 키
  - `settings.weather_paste`：粘贴 / Paste / 貼上 / 貼り付け / 붙여넣기
  - `settings.weather_clear`：清除自定义 / Remove custom / 清除自訂 / カスタムを削除 / 사용자 지정 삭제
  - `settings.weather_len_hint_qw`：和风 Key 通常为 32 位，请确认无误 / QWeather keys are usually 32 characters — please check / 和風 Key 通常為 32 位，請確認無誤 / QWeather キーは通常32文字です。ご確認ください / QWeather 키는 보통 32자입니다. 확인해 주세요
  - `settings.weather_len_hint_cy`：彩云 Key 通常为 16 位，请确认无误 / Caiyun keys are usually 16 characters — please check / 彩雲 Key 通常為 16 位，請確認無誤 / Caiyun キーは通常16文字です。ご確認ください / Caiyun 키는 보통 16자입니다. 확인해 주세요
  - `settings.weather_show` / `settings.weather_hide`：显示 / 隐藏（无障碍标签）——计入则新增为 11 键，落码时二选一处理：若显隐钮只用 SF Symbol + 既有 accessibility 惯例可省，则 10 键；本方案按加键计（无障碍完整性优先）。
- **退役 2 键 ×5 语**：`settings.weather_save`（保存钮废除）、`settings.weather_active`（placeholder 混合信号废除）——五包同步删 + 全仓引用零残留（verify_rustweb 僵尸门现已含原生面，删键删引用须同批）。
- 净账：307 + 11 − 2 = **316 键/包**；verify_ios [9] 计数断言与 verify_rustweb 键集一致性同步改。

## 6. 落点清单（落码批执行用）

MomentApp.swift：
- `WeatherService`（:12387 附近）：新增 `keySource(_:)` + `KeySource` 枚举；`key()` 改走派生（行为不变，契约测试面无此函数、纯 Swift 侧）。
- `SettingsView`（:14141 起）：
  - `Sub` 枚举加 `.weather` case；`navigationDestination` switch 加 `WeatherView()`。
  - 删内嵌 `WeatherKeyUI` 类与 `@StateObject weatherUI`、`weatherKeyRow` 函数、主页天气表单卡整段——**零残留**（grep `weatherKeyRow` / `WeatherKeyUI` / `weatherUI` 归零）；天气组改 SectionHeader（不动）+ 单 SetRow 卡（radius 28）。
  - 新增主页 meta 派生（keySource ×2 → 状态词 → tf 合成）。
  - **连带账**：关于组头 topPad 40 的 S1 推导前提是「天气卡 = 表单型卡（.list-group 口径 margin-bottom 24）」；天气卡改导航行卡（数据组同型，.backup-card 口径 16）后，关于组头应重推为 **32**（16+12+4），注释账与 verify [10] S1 断言同步改。天气组头 topPad 32 的前提（上方数据卡）不变。
- 新增 `struct WeatherView`（置于 LanguageView 附近，:15019 族）：承接 WeatherKeyUI 逻辑（移出 + 逐字段提交/粘贴/清除/显隐/软提示扩展），字段状态以 keySource 派生呈现。
- verify_ios.sh：[10] 组序断言口径复核（首个 `"settings.weather"` 仍为组头行，SetRow title 同键在其后，不破）；S1 关于 topPad 改 32 同步；新增 [12] 组建议：WeatherView 在位、Sub .weather case、weatherKeyRow/旧保存钮零残留、keySource 在位、语言键计数 316、`settings.weather_save`/`_active` 五包零键零引用。
- 语言包 ×5：按 §5 增删。

规模估计：Swift 净改约 ±260 行（删主页表单段约 −90、WeatherView 新建约 +200、WeatherService/SettingsView 接线约 ±60），语言包 5 文件各 +9 净行，verify +1 组。

## 7. 明确不做项与风险

- **不做 Keychain 迁移**：UserDefaults 明文存自填 key 的暴露面与 bundle 内置 key 同级（.ipa 内 weather-keys.json 本就可读），迁移成本（存储层 + 迁移 + key()/UI 双改）与收益不成比例；登记为知情不做项，后续若内置 key 改为不随包分发再重估。
- **不做硬校验**（见 2.4）、**不做 Form/List 化**（见 §1）、**不引 ContentUnavailableView**（iOS 17 门，见 §1）。
- **不明文默认回显**：默认恒掩码，显隐仅本屏手动切换（见 2.3）。
- 风险：① en-US 主页 meta「QWeather Custom · Caiyun Built-in」12pt 单行宽度——与备份行长 meta 同量级，预计可容纳，I5 五语窄屏通查时一并核。② 即时提交的半截 key 风险（见 2.3 兜底）。③ keySource 派生须与 key() 严格同判（bundle JSON 解析失败时 key() 返 ""、keySource 须同返 none——落码以同一解析函数实现，断言锁定）。
