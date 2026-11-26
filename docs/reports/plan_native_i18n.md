# 原生 i18n 立项计划（2026-11-26）

范围：Moment 原生 iOS 多语言切换本体。设置审计 E1–E4 当时明确留给本立项
（`docs/reports/audit_detail_settings.md` §E）。本文只做调研与方案，不含落码。
基线：仓库 HEAD 1756cd1（0.9.40）。

## 1. 现状证据

### 1.1 Web 语言体系（真源）

- **语言包**：`rust/apps/web/lang/{zh-CN,zh-TW,en-US,ja-JP,ko-KR}.json`，
扁平 JSON、点分命名空间键。**五语各 268 键，键集合五语完全一致**
（脚本逐键比对：无缺失、无多余）。单文件 12.5–16 KB，五包合计约 73 KB。
`dist/lang/` 与 `lang/` md5 逐字一致（构建拷贝）。
- **键分布**（按前缀）：slash 59、backup 24、settings 19、media 15、
export 14、bg 12、diag 12、gestures 12、menu 12、editor 10、list 9、
empty 8、storage 8、group 7、lang 7、sheet 6、status 6、action 5、
callout 5、attach 4、errbadge 3、hint 2、search 2、time 2，
app/cardmenu/shortcuts/imgpage/music 各 1。
- **引擎**：`rust/apps/web/src/i18n.rs`（175 行）。
- zh-CN 用 `include_str!` 内嵌保底（i18n.rs:63-68）；其余四包是部署在
`./lang/<code>.json` 的独立文件，选中时才 fetch 下载、缓存进
localStorage `moment_pack_<code>`（i18n.rs:97-124）。
- 偏好：localStorage `moment_lang` 存具体语言码（i18n.rs:56）。
- 查表回退链：当前包 → zh-CN → 键名本身（`t()`，i18n.rs:74-83）；
`tf()` 做 `{name}` 占位符替换（i18n.rs:85-92）。无复数/性别机制。
- 切换即时生效：`CURRENT`/`PACK` 是 Dioxus `GlobalSignal`（i18n.rs:59-60），
`apply_lang` 换包即全界面反应式重渲染，**无需重启**（i18n.rs:155-175）。
- 启动恢复：先用缓存包即时应用、再后台网络刷新（`init_lang`，i18n.rs:126-152）。
- **跟随系统：不存在**。无偏好时默认 `DEFAULT_LANG = "zh-CN"`（i18n.rs:55、
128-131）；全仓无 navigator.language 参与 UI 语言判定（仅 errbadge.rs:35
借 navigator.language 做 Intl 日期格式化，与 UI 语言无关）。
- **调用面**：`i18n::t/tf` 全仓 244 行调用——settings.rs 67、main.rs 56、
editor/layers.rs 47、editor/render.rs 25、list.rs 20、blocks.rs 18 等。
- **语言页**：`main.rs:3006` LanguageView；状态文案逻辑在 main.rs:3030-3042：
当前=「使用中」(lang.active)、下载中、zh-CN=「内置」(lang.builtin)、
已缓存=「已下载」、未缓存=「下载」。`lang.*` 共 7 键（zh-CN.json:90-96）。
- **Diag**：Web 已有 LANG 打点（init/applied/apply failed，i18n.rs:133/147/167/173）。

### 1.2 原生现状

- **LanguageView 是纯静态形态**（`MomentApp.swift:12557-12640`）：行数据是
硬编码数组（12562-1268 一带）——zh-CN 写死 `current: true`，其余四语一律
标「内置」，行**没有任何点按动作**，连偏好都不写。文件头注释自承
「切换行为待原生 i18n 落地后接通」（12555-12556）；onAppear 注释
「切换打点随 i18n 立项」（约 12636）。审计 E1（单卡+分隔线 vs Web 独立卡）、
E2（胶囊徽章+勾选 vs Web 纯文字状态）形态差亦未动。
- **设置页语言行**：`SetRow(title: "语言", meta: "简体中文")`（12023-12026），
meta 写死。
- **无语言偏好存储**：全文件无语言相关 UserDefaults 键；其余偏好走
UserDefaults / @AppStorage（diagAutodel、diagLevel、lastExportTs 等）。
- **无系统本地化资源**：app 目录内无 `.strings` / `.lproj` / `.xcstrings`。
构建脚本手工拷资源已有成例（Assets.car、开屏 json、weather-keys.json，
build-app2.sh:100/112/123），加一份 lang 资源拷贝与现有管线同形。
- **硬编码文案规模**：MomentApp.swift 单行字符串字面量含 CJK 者
**478 处出现、388 个互异**（多行模板另计）；其中 65 处带插值/格式符。
直接 `Text("…")` 只有 69 处（CJK 54）——多数文案经 SetRow、SectionHeader、
Button、toast、菜单与数据结构（SlashCmd 等）流入，Text 计数严重低估，
真实改造面以 478 处为准。按结构分组（出现数）：

| 分组 | 处数 | 分组 | 处数 |
|---|---|---|---|
| MemoItem（分组名/相对时间/行菜单） | 87 | AvatarView | 20 |
| SlashCmd（斜杠菜单定义） | 65 | GesturesView | 11 |
| ListView（首页/搜索/空态） | 52 | BlockRow | 10 |
| BackupView | 39 | LanguageView | 10 |
| DiagView | 31 | CardBlockView / ImgTextBlockView | 6 / 6 |
| SettingsView | 30 | CardEditSheets / ShareSheet | 5 / 5 |
| EditorView | 28 | GalleryBlockView | 4 |
| EditorHeaderView | 26 | ErrBadgeOverlay | 3 |
| ImageTarget | 20 | DiagLogPage / AttachmentBlockView | 2 / 2 |

- **日期词亦是硬编码**：Fmt 的「今天/昨天」（2336/2339）、MemoItem.ago
「昨天」（10128）、分组名（置顶/今天/昨天/过去 7 天…）都在字面量里；
DateFormatter 本身跟随系统 locale——语言口径需一并裁定（见 §3）。
- **键对账前瞻**：Web 包 268 键与原生 388 互异字面量只是部分重叠——
原生有 Web 无键的文案（DiagView「校验库」「清理缓存」等原生增强，
见审计 F10），Web 也有原生尚未用到的键。最终键数预计 ~300 上下，
对账与补键（五语齐全）是实施的一部分。

## 2. 方案对比

### (a) 复用 Web 语言包：JSON 入 bundle + Swift 查表层

五包 JSON 原样拷入.app（build-app2.sh 加一条 cp，与 weather-keys.json 同例）；
Swift 侧建 `LangStore: ObservableObject`（@Published 当前码 + 当前包字典 +
zh-CN 保底字典），提供与 Web 同签名的 `t()/tf()` 与同一条回退链；
根注入后各 View 观察 store，改码即全界面重渲染。偏好存 UserDefaults。

- 优：**单一真源**——键与译文与 Web 永远同源，完整性可脚本对账；
行为与 Web 按构造等价（同回退链、同占位符语义）；纯 Foundation JSON
解析，本机 Linux 工具链零新依赖、零风险；五包全内置仅约 73 KB。
- 劣：无编译期键检查（靠 §5 断言补）；无复数机制（Web 包本身也没有，
属平价而非退步）。

### (b) 原生.strings /.xcstrings +.lproj

- **工具链硬伤**：本项目在 Linux 上以 swiftc 直编、无 Xcode。
`.xcstrings` 的编译需 macOS 专属 xcstringstool，本机不可用；
旧式 `.strings` 虽是纯文本可手工维护，但——
- **即时切换要绕系统**：`NSLocalizedString` 读的是进程级 locale；
app 内偏好 ≠ 系统语言时，只能靠 AppleLanguages + 指定 lproj bundle
手工加载——等于在 (a) 的查表层外面再包一层系统格式。而走系统
「每应用语言」设置则须用户出 app 操作、切换伴随界面重建，
体验劣于 Web 的点选即时切换。
- **双格式双维护**：268 键要在 JSON 与.strings 两套格式间同步，
与 Web 的键对账从脚本比对退化为跨格式映射，长期必漂移。

### (c) 混合：系统面走原生机制 + 应用内走 (a)

系统直接呈现的少数面——app 显示名（各语言名已定案：此刻 / Moment /
此刻 / 瞬間 / 순간）、系统权限弹窗归属的 Info.plist 键——用极小的
InfoPlist.strings（五份.lproj，纯文本、无需编译工具）承接；
应用内全部 UI 走 (a)。成本近零，且显示名跟随系统语言本就是系统口径。

## 3. 推荐与判读依据

**推荐 (c)：应用内 (a) 查表 + 系统面 InfoPlist.strings。**

判读（设计意图 vs 平台妥协）：

- Web 的「按需下载语言包 + 下载/已下载/下载中状态 + localStorage 缓存」
是 **Web 平台妥协**（网页没有 bundle，只能远程拉包）。原生五包全内置，
语言页状态集随之坍缩：当前=「使用中」，其余=「内置」——审计 E3 记的
原生「其余四语全标内置」在原生模型下反而是对的终局形态，不再修它；
E4 的下载动作同理消解为点选即切换。
- 语言页**行形态是设计意图**（视觉规格）：按 E1/E2 改回 Web 形——
每语言独立卡（radius 32、glass-content、卡间隔 6）、状态为纯文字 12px
（当前 accent/700、余次级），去掉胶囊徽章与勾选图标。
- Web 的「即时切换、无需重启」是**设计意图**（Telegram 模型的核心体验），
原生以 ObservableObject 反应式重渲染等价达成，且优于系统每应用语言
的出 app 切换路径——按用户口径走原生更优路，不抄系统设置流。
- Web 无跟随系统，属产品默认（默认 zh-CN）而非技术不能。原生有系统
语言这一等公民信号，立项按三态落：**跟随系统 / 手动五语**。
- 存储：UserDefaults 键存模式——缺省（从未设置）按 zh-CN 解析，
保证现存用户升级零突变；语言页首行「跟随系统」，其状态副文案显示
当前解析到的语言；用户一旦点选具体语言即转手动，点「跟随系统」回三态。
- 系统语言解析映射：zh-Hans*→zh-CN、zh-Hant*→zh-TW、en*→en-US、
ja*→ja-JP、ko*→ko-KR，其余→zh-CN（与 Web 默认/回退底一致）。
- 全新安装是否默认跟随系统。本计划默认取
上述保守口径（缺省=zh-CN 解析），裁定可改。
- **回退链与 Web 逐字一致**：当前包 → zh-CN → 键名；启动先落 zh-CN 包
再按偏好换包（对应 Web init 的保底先行）。占位符沿用 `{name}` 语法，
与 Web 包原文直接兼容（Swift 侧 tf 做同名替换）。
- **键的真源只有一个**：`rust/apps/web/lang/*.json`。原生独有文案的新键
按既有命名空间（diag.*、settings.* 等）补进这五份文件、五语齐全后才许
引用；Web 对不认识的键天然无感（查表未命中不报错），无需改 Web 代码。
- **Diag 文案不做多语言**：Diag 日志行是证据记录，须跨设备/跨版本可 grep、
可与 Web 日志逐行对读（审计 F11 已立格式对齐口径）；现行日志本就以
英文标签式文案为主（478 处 CJK 字面量中属 Diag 载荷的仅 3 处）。
但诊断**页的 UI 壳**（标题、按钮、空态）是普通界面文案，走语言包
（diag.* 12 键已在包内）。
- **Diag LANG 打点**：切换成功落一条
`DiagLog.shared.log(.info, "LANG applied <code>")`（手动）/
`"LANG follow-system -> <code>"`（跟随系统解析），启动落
`"LANG init <code>"`——与 Web 既有 LANG 标签口径对齐，只记目标语言码。
落点：LangStore 的 apply/init 内部各一处，LanguageView 不另打
（现 12636 行注释「切换打点随 i18n 立项」在此兑现）。
- **日期/数字格式**：跟随 **app 内语言**而非系统 locale（否则语言切到
英文、日期仍按系统出中文词，自相矛盾）——Fmt 与 MemoItem.ago 的
「今天/昨天」等词走语言包（time.* / group.* 键已在包内），
DateFormatter 的 locale 显式设为当前语言码。

## 4. 分批实施计划

每批独立成笔、跑 `smoke_ios.sh` 全量冒烟全绿才出包（既定出包门）。

| 批 | 范围 | 出包 |
|---|---|---|
| I1 基础设施 | LangStore + t/tf + 回退链；build-app2.sh 拷五包入 bundle；启动 init + LANG 打点；UserDefaults 三态偏好与系统解析；verify 新增 [9] 组（§5 前四条）。界面文案暂不换（默认解析 zh-CN，视觉零变化） | 随 I2 同包 |
| I2 设置族 + 语言页 | LanguageView 按 E1/E2 重建（独立卡 + 纯文字状态 + 跟随系统行 + 点选即切换，E4 兑现）；SettingsView 语言行 meta 改读 store；Settings/Backup/Gestures/Diag 四页文案全量换键（约 111 处）；审计 E1–E4 关单 | 0.9.41 |
| I3 首页与列表 | ListView、MemoItem（分组名/相对时间/行菜单）、搜索、空态、ErrBadge（约 160 处，含 Fmt/ago 日期词与 formatter locale） | 0.9.42 |
| I4 编辑器 | EditorView、EditorHeaderView、SlashCmd（65 处、最大单组）、BlockRow、各卡片块、CardEditSheets、ImageTarget、AvatarView（约 190 处）。MomentApp.swift 类型检查膨胀史在案——换键为机械替换，仍须外科小步、每段过编译级自检 | 0.9.43 |
| I5 残余与系统面 | ImagePage、ShareSheet、全局 toast 残余清零；InfoPlist.strings 五语显示名（路线 c 的系统面）；CJK 字面量零残留门（§5 第五条）转正；五语 × 窄屏 × 大字号（Dynamic Type 最大档）视觉通查 | 0.9.44 |

工作量量级：I1 约半个专注会话，I2/I3/I4 各约一个会话，I5 约半个；
合计约 4–5 个会话、4 个交付包。主导成本在 I4 的编辑器换键与 I3 的
日期词口径，其余为机械替换 + 对账。

## 5. verify_ios.sh 断言清单（新增 [9] 组「语言包完整性」）

1. **五语键集合一致**：脚本解析 `rust/apps/web/lang/*.json`，五份键集合
两两相等，不等即红（Web 侧现已满足，转为常驻门）。
2. **产物含包**：构建后.app 内五份 lang JSON 在位且与仓库源 md5 一致。
3. **引用键齐全**：提取 Swift 全部 `Lang.t("…")` / `t("…")` 键名，
逐个断言存在于 zh-CN 包且五语齐全；缺一即红。
4. **语言页接通**：LanguageView 无硬编码行数组残留（grep 特征行）、
含 apply 调用与 `LANG applied` 打点行；SettingsView 语言行 meta
不再是字面量「简体中文」。
5. **硬编码零残留门**（I5 转正）：脚本提取单行 CJK 字符串字面量，
与白名单文件比对——白名单仅含 Diag 载荷（约 3 条）、语言本名行、
种子/示例内容；白名单外新增 CJK 字面量即红。
6. **系统面**（I5 后）：五份 InfoPlist.strings 在位、显示名与定案一致；
plist 含 CFBundleLocalizations 五语（若采用该声明）。

## 6. 风险

- **字符串变长**（以 zh-CN 为 1.0 的实测比）：en-US 平均 2.89×、最长
6.5×，164 个键超过 1.8×；ja-JP 平均 1.60×（43 键 >1.8×）；
ko-KR 平均 1.51×（44 键 >1.8×）；zh-TW 1.01×。影响面排序：
斜杠菜单行（slash 59 键、行宽固定，最易溢出）、设置行右侧 meta
（长译文挤压标题）、备份页说明段与超期横幅（可折行，风险低）、
底表按钮（确认/取消类短词，风险低）、标题胶囊（是用户内容非 UI
文案，不受影响）。对策：每批以 en-US + ja-JP 在窄屏各通查一遍；
Web 端同文案的折行/截断行为即口径（Web 允许折行处原生不许单行截断）。
- **Dynamic Type 叠加**：原生字号跟随系统大字号时与长译文叠加，
设置行/菜单行首当其冲——I5 通查含最大字号档。
- **键漂移**：Web 与原生共用一包后，任一端加键不补五语都会被 [9]-1/3
拦下；风险转为流程风险（补译的工作量），不再是静默缺键。
- **跟随系统解析边界**：zh-Hant-HK、en-GB 等变体映射已在 §3 给表；
系统语言不在五语内时回退 zh-CN，与 Web 默认一致，但对纯英文系统
用户可能反直觉——与 §3 的待裁定项一并由用户拍板。
- **用户内容永不本地化**：备忘标题/正文/标签、附件名、备份内容一律
不走语言包；语言包只覆盖 UI 壳。此界线写进 I1 的 LangStore 注释防误用。
- **编辑器文件膨胀**：I4 在 MomentApp.swift 编辑器区段换键近 200 处，
该文件有 body 膨胀触发类型检查超时的前科——分段落码、逐段自检，
不整文件回写（既定大文件规矩）。
