# 设置页天气栏差距排查（只排查，未落码）

立项来源：用户实报——天气重构批（0.9.43）落地后，设置页天气栏除位置外，样式、UIUX、交互依旧是旧样子。本报告四部分：一、现行全貌账；二、与设置页设计系统的差距表；三、与 Web 两代的对照与形态来源判定；四、漏检定因；五、与既定方案 `plan_weather_settings.md` 的对表与增补清单。行号均为落盘时现行值（MomentApp.swift，文件已因 0.9.44–0.9.46 多批漂移，落码以符号名为准）。

## 结论速览

- 天气组是整个设置页里**唯一把完整表单摊在主页**的组：自绘表单卡 + 整组一个保存钮 + 零校验 + 状态靠输入框 placeholder 暗示。与设置家族的现行体例（主页 = 组头 + SetRow 导航行卡；可编辑项进二级页；语言页即时生效、备份页内动作确认）全面分叉。
- 两代 Web 都没有天气 key 设置 UI（原版走常量注入、Rust 版走部署注入），**无形态可照搬**；原生此组是 H17 裁定（默认构建注入 + 设置页自填）落地时按最小实现自创的内联表单，从未按设置项设计过。
- 漏检是结构性的：两轮设置审计的框架都是「对 Web 数值对齐」，天气组无 Web 对照面，先后被记为「已定案偏离」（只量数值、不判形态）与「尚成规律，不作缺陷」（只挪组位）——所以 0.9.43 落地的只有位置（分组方案 A），形态原封不动，与用户实报严丝合缝。
- 既定方案 `plan_weather_settings.md` 对差距表的覆盖基本完整；需增补/修正 5 处（键数基线、verify 组号、key() 重复读盘解析、组头与行同名提示、OpsDirectives guard 点勿伤），见第五节。

## 一、现行全貌账

### 1.1 UI 构成（SettingsView 内，:14716–14773）

- 组头：`SectionHeader(settings.weather, topPad: 32)`（:14723），位于数据组之后、关于组之前（0.9.43 分组方案 A 的落点）。
- 组卡：`VStack(alignment: .leading, spacing: 10)` + `.padding(.horizontal, 16).padding(.vertical, 14)` + `glassCard(radius: 32)`——表单型卡，与外观行卡同 radius 32，与数据/关于的导航行卡（radius 28）不同型。
- 卡内自上而下：
  1. `weatherKeyRow`（和风）（:14727）：VStack（spacing 4）= 标题 `settings.weather_qweather`（13 semibold / T.textMain）+ `SecureField`（14 / T.textMain，`.autocorrectionDisabled` + `.textInputAutocapitalization(.never)`）（weatherKeyRow 定义 :14599–14613）。
  2. `weatherKeyRow`（彩云）（:14740）：同构。
  3. 底部 HStack（:14753）：说明 `settings.weather_note`（12 / T.textSecondary）+ Spacer + 保存 Button（14 semibold / T.accent），文案在 `settings.weather_save` / `settings.weather_saved` 间切换。
- 两字段的 placeholder 按**生效值**判空（body 内直调 `WeatherService.key(name)`，:14730/:14743）：空 → `settings.weather_unset`（未设置）；非空 → `settings.weather_active`（已生效（可自填覆盖））。判据是生效值，内置与自填在 UI 上不可区分——状态信号只有这一处，且藏在空字段的占位文案里。

### 1.2 存取与交互语义（WeatherKeyUI，:14553–14585）

- `SettingsView` 内嵌 `ObservableObject`（`@StateObject weatherUI`，:14585）：`qweather` / `caiyun` 初始化自 UserDefaults `weatherKey_qweather` / `weatherKey_caiyun`，`saved: Bool`。
- `save()`（:14562）：双字段 `trimmingCharacters(.whitespaces)`（**只 trim 首尾**）后写回 UserDefaults（空串照写、不删键）→ 删 `weatherCacheV1` → `saved = true` → Diag `SET weather key saved qweather=set|empty caiyun=set|empty`（只记有无、绝不记值）。
- 任一字段编辑（Binding set，:14738/:14751）即 `saved = false`。除此之外无任何状态机：无校验、无逐字段状态、无错误态、无显隐、无粘贴钮、无清除钮（清除 = 手工删空字段再保存）。
- `SecureField` 无 `submitLabel` / `onSubmit` / `@FocusState`：键盘 Done 不构成提交点；不按保存钮，改动永不生效且无任何提示。

### 1.3 消费面（WeatherService，:12726 起）

- `key(_:)`（:12741）：UserDefaults `weatherKey_<name>` 非空 → bundle `weather-keys.json` 同名值 → `""`。注意实现细节：**每次调用都重新 `Data(contentsOf:)` 读盘并 JSON 解析 bundle 文件**，无缓存；设置主页 body 每轮求值要为两个 placeholder 各调一次（外加字段判空路径），属现行小缺陷（见增补 B3）。
- `fetch()` 链：和风 key 空 → 整链不发请求（Diag `WEATHER no api key, skip`）；和风失败 → 彩云兜底；双失败记 `WEATHER provider=fail`。**错 key 的唯一反馈就是这行 Diag**，设置页与列表页均无 UI 面提示。

## 二、对照组一：设置页设计系统现状与差距表

### 2.1 家族现行体例（对照系）

- **主页**：`ChromeView` + ScrollView；组 = `SectionHeader`（14 semibold / T.textSecondary，topPad 按组距账逐组推导）+ 卡。导航行统一 `SetRow`（:14424：标题 16 semibold + meta 12 / T.glassLabel + warnSuffix 可选 + 「›」@45%，Button + RowPressStyle，内距 16/14），行间 `rowDivider`（0.5 / T.borderSoft，:14835）。数据组四行（备份/语言/手势/诊断）全是 SetRow + `glassCard(radius: 28)`。
- **二级页**：统一 `ChromeView(title:onBack:)` + ScrollView + 外距横 20 / 顶 126 / 底 40（GesturesView :15316、LanguageView :15399 皆然；BackupView :14848 同 ChromeView 骨架）；入口统一经 `SettingsNav.route`（`Sub` 枚举：backup/gestures/language/diag，:14587）+ `navigationDestination` switch（:14812），不用字面 NavigationLink；子页 onAppear 记 `SET xxx enter`（G5 口径：settings/backup/gestures/language 均有）。
- **提交模型先例**：LanguageView 点选即应用（`langStore.apply`，无保存钮，状态纯文字 12pt：生效 accent/700、余次级，rowCard :15471）；BackupView 页内动作按钮 + 确认底表 + 页内 toast（其页内既定件）；GesturesView/DiagView 为只读呈现页。**全页没有第二个「表单 + 保存钮」面**。
- 例外注记：外观组是主页内联展示行（跟随系统说明，16 semibold + 12 次级 + 右侧 13 次级值，radius 32 卡）——属只读展示行既定形态，非表单，不构成天气表单的先例。

### 2.2 差距表 · 样式

| # | 项 | 现状（出处） | 应然（家族口径） |
|---|---|---|---|
| S1 | 组卡形态 | 主页内联表单卡，glassCard radius 32（:14726–14773） | 主页收为单行导航卡 radius 28（数据组同型）；表单移入二级页 |
| S2 | 行型 | 自绘 weatherKeyRow（标题 13 semibold + 字段 14，spacing 4，:14599），不走 SetRow、也不走子页行卡 | 主页 SetRow；子页内走行卡口径（名 16 semibold + 副文案/状态 12） |
| S3 | 卡内布局 | 卡 padding 16/14 + VStack spacing 10 的表单专用合成 | 导航卡内距由 SetRow 自带（16/14）+ rowDivider 分行；子页卡按 LanguageView 卡口径 |
| S4 | 状态呈现 | 无独立状态位；状态靠 SecureField placeholder 二选一，且判据为生效值、内置/自填不可区分（:14730） | 独立状态词 + 生效来源行（12pt，生效 accent/700、余次级——LanguageView 状态口径） |
| S5 | 说明文案 | note（12 次级）与保存钮同行挤在卡底 HStack（:14753） | 说明独立成行/成卡（子页内），不与动作钮同行 |
| S6 | 保存钮 | 14 semibold accent 文本钮挂在主页卡底右下，全设置页唯一的保存钮形态 | 家族无此件；随即时提交模型废除 |
| S7 | 组距连带 | 天气卡被归「表单型卡」类，使其下关于组头 topPad 按 .list-group 口径推得 40（:14775 注释账） | 卡改导航型后，关于组头应按 .backup-card 口径重推（方案已账：32） |
| — | 组头本身 | SectionHeader + topPad 32 与家族一致 | 非差距，注记已对齐 |

### 2.3 差距表 · 交互

| # | 项 | 现状（出处） | 应然（家族口径） |
|---|---|---|---|
| I1 | 提交模型 | 整组一钮、双字段批量保存（save() :14562） | 逐字段即时提交（LanguageView 即时生效先例） |
| I2 | 生效可见性 | 只有 saved 布尔一面：改后必须记得按保存；按后钮文案变「已保存」，再编辑即回置（:14738） | 状态词/生效来源行随提交即时刷新，无「未保存」中间态 |
| I3 | 校验与反馈 | 零校验：长度/格式不查，粘贴带内部换行只 trim 首尾原样存入（:14564）；错 key 无 UI 反馈，仅 Diag 一行 | 软提示不硬拦（长度提示行）；提交时去全部空白 |
| I4 | 清除路径 | 无清除钮；清 = 手工删空 + 保存，且写空串而非删键（靠 key() 的 isEmpty 兼容） | 显式「清除自定义」动作，落盘删键，回落内置/未设置 |
| I5 | 导航层级 | 唯一摊在主页的完整表单；Sub 枚举无 weather case（:14587），无二级页 | 主页 SetRow → WeatherView 二级页（Sub 加 case + destination switch 接线） |
| I6 | 进入留痕 | 无页即无 SET enter 行；只有 saved 一行 Diag | 子页 onAppear 记 `SET weather enter`（G5 同口径） |
| I7 | 写盘粒度 | 批量保存时未改字段也整表重写 UserDefaults（无变化比较） | 逐字段提交时与现存值比较，无变化不动作（缓存删除同理只在有效变更时） |
| — | 缓存联动 | save 后删 weatherCacheV1（:14572） | 已对齐，注记保留此口径 |

## 三、对照组二：Web 两代与形态来源判定

- **原版（归档 `~/workspace/.scratch/moment-original-archive-2026-11-25/`）**：天气 key 来自 `window.MynoteConstants.QWEATHER_API_KEY`（`src/services/weather.js:51`，常量/配置注入），设置面无 key 输入 UI。
- **Rust Web**：`rust/apps/web/src/settings.rs`（1016 行）全文零 weather 命中；key 走 `window.__APP_CONFIG__` 部署注入（`weather.rs:86–110` 的 `injected_key("QWEATHER_API_KEY")` / `injected_key("CAIYUN_API_KEY")`），仓库不落值、页面无设置项。
- **判定**：原生天气组**没有照搬对象**——不是抄了原版旧形态，而是 H17 裁定给原生新增「设置页自填」能力时（调研见 `audit_search_weather.md`，其主题是天气**数据链**而非设置 UI），按最小实现自创的内联表单：形态上唯一借用的是把卡归入外观组的「表单型卡」类（radius 32、组距按 .list-group 推导），其余（双 SecureField 平铺 + 卡底保存钮 + placeholder 状态）皆原生自创且从未与设置家族体例对过表。

## 四、漏检定因（证据分级）

1. **（proven）第一轮设置审计把它登记为「定案偏离」而豁免形态判断。** `audit_detail_settings.md` B8：天气组记为「整组原生独有……已定案偏离（用户裁定：默认构建注入 + 设置页自填覆盖，只存本机）」，该轮量了它的数值（radius 32、标题 13、输入 14、说明 12、保存 14 accent），但因 Web 无此组、无对照真源，未对它做任何「与家族是否一致」的判断。
2. **（proven）第二轮审计只处理组位，并明文把形态判为不成问题。** `audit2_settings.md` 分组对照表第 2/3/4 项仍记「原生多出（用户 H17 裁定）」，该轮对天气的产出只有分组方案 A（整组下移至数据组之后）；且其数值复核行明文写「天气卡 32（原生自选，与外观同为『表单型卡』，尚成规律，不作缺陷）」。0.9.43 落地的正是方案 A——**只有位置变了，与用户实报逐字吻合**。
3. **（proven）两轮审计的对照系都是 Web，天气恰在对照系之外。** 设置族批次（批 E 0.9.40、i18n I2 0.9.41）的修复清单全部来自「原生 vs Web」的差分表；天气组在差分表里的身份恒为「原生多出/已定案」，从未进入「原生 vs 原生家族体例」（SetRow / 二级页 / 即时提交）的对照——而它的问题恰好全部在后一个维度。
4. **（inferred）立项归类偏差是上游原因。** 天气在 H17 调研中被归为「数据链/配置注入」课题（key 是注入物、设置页只是注入的覆盖口），UI 以附带产物身份按最小实现内联进设置主页；此后它的身份在各文档中一直是「凭据配置」而非「设置项」，没有批次以设置项标准回头审过它。此条为归因推断，无单一直证文档，故标 inferred；但与 1–3 的文档事实链一致。

## 五、与既定方案的对表与增补清单

### 5.1 方案前提复核（`plan_weather_settings.md`，逐项对现行代码）

| 方案断言 | 现行核对 | 结论 |
|---|---|---|
| §0.1 天气组在数据组后、关于组前；WeatherKeyUI / weatherKeyRow / 表单卡构成 | 组位与构成未变；行号漂移：WeatherKeyUI :14161→:14553、weatherKeyRow :14207→:14599、表单卡 :14330–14385→:14716–14773 | 成立（行号以符号名为准） |
| §0.1 placeholder 按生效值判空、内置/自填不可区分；无校验/无粘贴/无清除/无逐字段状态 | 与 :14730/:14743、save() :14562 逐项吻合 | 成立 |
| §0.2 `key()` 优先序 自填 > 内置 > 空；WeatherService :12370 | 优先序未变（:12741）；类行号 →:12726 | 成立 |
| §0.4 SetRow :14044 / Sub 路由 / 子页外距 / LanguageView 即时先例 | SetRow →:14424；Sub 仍只有四 case（:14587）；destination switch :14812；LanguageView →:15399、BackupView →:14848、GesturesView →:15316，外距口径未变 | 成立 |
| §2.1 SectionHeader topPad 32 不动 | 现行 :14723 即 32 | 成立 |
| §6 连带账：关于组头 topPad 40 的前提是天气卡 = 表单型卡 | 现行 :14775–14779 注释账与 topPad 40 均在位 | 成立，落码按方案重推 32 |
| §3 Diag：`SET weather key saved` 升级为来源口径 | 现行仍为 set|empty（:14578–14582） | 成立（待落） |

### 5.2 需修正的方案参数（2 处）

- **B1 语言键基线过时**：方案 §5 以 307 键为基线算 307+11−2=316。现行五包已是 **324 键**（0.9.45 自救批 +17，verify [9] 期望已改 324，verify_ios.sh:272）。天气键现存 8 个（weather/_qweather/_caiyun/_note/_saved/_unset/_save/_active），与方案「复用 6 + 退役 2」账吻合；净账应改 **324 + 11 − 2 = 333 键/包**，verify [9] 期望同步改 333。
- **B2 verify 新组组号撞号**：方案 §6 建议「新增 [12] 组」——[12] 已被 0.9.44 热修组占用、[13] 已被 0.9.45 自救组占用（verify_ios.sh:722/738）。天气批新组应为 **[14]**。

### 5.3 方案未覆盖的增补（3 处）

- **B3 `key()` 重复读盘解析应随 keySource 一并根治**：现行 `key()`（:12741）每次调用重读并解析 bundle JSON，无缓存；主页 placeholder 每轮 body 求值调用多次。方案 §2.1 的 keySource 派生若仍逐次走同一解析，会把此缺陷带进主页 meta 与子页状态。增补：bundle 解析结果做进程级单次缓存（static 缓存），key() 与 keySource 共用；主页/子页每轮求值只读 UserDefaults 与缓存。
- **B4 组头与行同名需落码时定夺**：方案 §2.1 定组头不动、主页行 title 同用 `settings.weather`——结果是「天气」组头下紧跟一行同名「天气」SetRow，与数据组（组头「数据」≠ 行题「备份/语言/手势/诊断」）的构成不同。方案未论及此观感。增补：落码时二选一并记账——或维持方案（组头即组名、行是唯一入口，同名可接受），或行 title 借子页义（如「天气 Key」需新增键、动 §5 账）。不预判，留落码批裁定。
- **B5 勿伤 0.9.45 的 OpsDirectives 天气 guard 点**：方案成文于 0.9.45 之前，未提列表侧天气自动刷新已被热更新通道接管（ListView :13327–13336：指令点名 `OpsStep.weatherRefresh` 即跳过自动刷新）。天气批动 WeatherService 时不得破坏此 guard 与 `refreshIfNeeded()` 的调用面；`keySource` 新增不得改变 `refreshIfNeeded` 的既有行为。

### 5.4 覆盖度结论

差距表 S1–S7 / I1–I7 与方案 §2（主页单行化、二级页双卡、逐字段即时提交、粘贴/清除、软提示、状态与来源行、Diag 来源口径、能力等价 12 项）逐项对应，**无整类遗漏**；方案 §7 的不做项（Keychain 迁移、硬校验、Form/List 化、ContentUnavailableView）与本排查无冲突。落码批（0.9.48）按方案 + B1–B5 执行即可。
