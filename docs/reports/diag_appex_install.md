# 小组件 appex 装机阻因排查报告

本批性质：诊断（机理取证 + 判别变体），不出正式修复包。样本：/tmp/ipa57、/tmp/ipa58、/tmp/ipa60、用户提供的签名后 0.9.60 ipa（user/files/C1543087-…-此刻_0.9.60_20261127_220549.ipa）、变体 VA/VB/VC 与 VE 系列。分级口径：proven = 有实测或签名后实物证据；inferred = 多项证据一致指向但无直接观测；unknown = 无从判。

## 结论先行

阻因机理已锁定（proven）：签名工具把**同一份 profile 与其全量 entitlements 原样盖入主程序与 appex 两处**；该 profile 的 application-identifier 是卖家自有 app 的显式 id（ZP7KP7TN22.app.tiger4240.lychee1720、非通配），与 appex 的 bundle id（com.canopies.moment.liveops）不匹配。签名后的 appex 结构本身完好（页哈希、槽位、资源封印全过，下文 §2 逐项数值）——不是签坏，是**身份校验问题**：installd 对嵌入扩展执行「扩展 bundle id 须被其所带 profile 的 application-identifier 覆盖」这一校验且不放行；主程序带同种不匹配却可装，是这条侧载通道已被多版本实证的既有行为，校验只在扩展一侧绑定。

未定的一项：该校验的**匹配语义**究竟是「profile App ID 作命名空间前缀、后缀可扩展」还是「须与 profile App ID 逐字同名」——由判别变体 VEA/VEB 装测裁定（§6、§7）。

## §1 证据链（全部为用户真机实测）

| 包 | appex | entitlements（交付侧） | 结果 |
|---|---|---|---|
| 0.9.57 | 无 | 无 | 可装 |
| 0.9.58 / 0.9.59 / 0.9.60 原版 | 有 | 有 | 不可装 |
| VA（60 去 appex） | 无 | 有 | 可装 |
| VC（60 去 appex + 剥 entitlements） | 无 | 无 | 可装 |
| VB（60 留 appex + 剥 entitlements） | 有 | 无 | 不可装 |

消去法结论（proven）：阻因在 appex 本体或其与签名通道的交互之内；主程序的代码、Info.plist、交付侧 entitlements、主签名面已由 VA 全面洗清（VA 与原版仅差 appex 在否）。设备侧症状为系统通用弹窗（无法安装、请稍后再试），不带错误码，与 installd 校验拒绝相容但本身无判别力。

## §2 签名后 ipa 取证（主线取证，本线对实物独立复核、全项吻合）

对签名后 0.9.60 ipa 解包逐项复核如下（均为 proven）：

- **profile 两处逐字节相同**：主程序与 appex 内 embedded.mobileprovision 的 md5 同为 1238ea69c568f95369253ad05e0b80a8。其解码字段：TeamIdentifier = ZP7KP7TN22；application-identifier = `ZP7KP7TN22.app.tiger4240.lychee1720`（显式、无通配）；aps-environment = production；entitlements 共 44 键（卖家 app 的全量集）；ProvisionedDevices 仅 1 台。
- **工具对 appex 做了完整的递归重签**（非跳过、非保留链接器签名）：签名后 appex 的 superblob 含 CodeDirectory、requirements、XML entitlements、DER entitlements 与 CMS 签名五件；CD flags = 0x0（adhoc 位已清）；CD ident 已由链接器时期的可执行名改写为 appex 的 bundle id（com.canopies.moment.liveops）；team 字段 = ZP7KP7TN22。
- **签名后 appex 结构完好**：全部代码页哈希按 codeLimit 裁剪口径逐一相符（坏页 0）；special slot-1 与其 Info.plist 相符、slot-5 与 entitlements 整 blob 相符；appex 的 _CodeSignature/CodeResources 正确封存其 embedded.mobileprovision（files2 中仅此一件，sha1/sha256 均符）。
- **不匹配点精确定位**：签名后 appex 的 entitlements 是 profile 全量集的原样盖入，其 application-identifier（ZP7KP7TN22.app.tiger4240.lychee1720）与其 bundle id / CD ident（com.canopies.moment.liveops）不一致。
- **对照组（主程序）同形态**：主程序 CD ident = com.canopies.moment、entitlements 的 application-identifier 同为卖家 id——同种不匹配；其 CodeResources 封存全包（含整个 appex 子树），签名工艺完整。该主程序可装（本通道多版本实证），与 appex 形成唯一变量对照：**校验只在扩展一侧绑定**。

## §3 appex 结构面逐项排查（交付侧）

- **bundle 内容**：仅 Info.plist + 可执行文件两件，无 _CodeSignature/CodeResources、无 embedded.mobileprovision——与主程序的交付形态相同。签名后实物证明这两件均由工具在重签时为 appex 补齐（§2），故交付侧缺失非阻因（proven 关闭）。
- **plist 键全集（10 键）逐项**：
  - CFBundleIdentifier = com.canopies.moment.liveops：以主程序 id 为前缀，前缀规则表面合法（proven）。
  - CFBundlePackageType = XPC!、NSExtension = { NSExtensionPointIdentifier = com.apple.widgetkit-extension }：与 WidgetKit 扩展的正版最小形态一致；此类扩展入口为 @main 静态注册、不需要 NSExtensionPrincipalClass（inferred 无问题，且 §2 的身份阻因已构成充分解释）。
  - CFBundleExecutable 与二进制同名、zip 内权限 0755（proven 无问题）。
  - 版本键：0.9.58/59 曾冻在 0.9.57/84 与主程序不一致；0.9.60 已单源同步为 0.9.60/87 且仍不可装——版本不一致**已证伪为阻因**（proven 排除）。
  - MinimumOSVersion 缺失（主程序有 16.0）、CFBundleSupportedPlatforms 缺失（主程序同样缺失且可装）：无公开明文表明 installd 对扩展这两键另有硬校验；在身份阻因已被证充分存在的前提下，两键是否另有问题被掩盖、无独立判读价值（unknown、已降级；仅当身份问题解除后仍不可装才重开，VE1 为此留作低优先级探针，见 §6）。
  - CFBundleDevelopmentRegion = zh_CN 与主程序同值（可装对照在场，排除）。
- **二进制面**：filetype EXECUTE、有 LC_MAIN、BUILD_VERSION minos 16.0、与主程序同为 ld64.lld 链接器签名同构；0.9.60 起经新 macho-entitle validate 全量口径复核（坏页 0、签名超出 __LINKEDIT 0 B）。静态面无可判坏点；但依本事件教训，静态无坏点不作装机结案（§2 的签名后实物才是扩展侧的终局证据）。

## §4 签名通道处理模型（原三模型，取证后收敛）

- 模型 A（递归重签、单 profile 通签全部 bundle）：**已被签名后实物证实**——工具确实递归处理了 appex（§2），且主程序与 appex 用同一份 profile 与同一套 entitlements。此模型下 appex 的授权 id 必然错位，是本次阻因的生成机制。
- 模型 B（只签主程序、appex 原样保留）：证伪——appex 的签名已被整体重建（ident 改写、CMS/DER 齐备、adhoc 位清除）。
- 模型 C（为 appex 另制自洽签名面但 profile 本体仍不覆盖其 id）：证伪——appex 内 profile 与主程序逐字节相同，不存在另制件。
- 与公开生态的一致性（背景，非证据）：zsign 类工具文档明示扩展需以多个 -m 分别指定 profile；重签工艺指南明示「一个扩展一个 profile」；正版多扩展应用（如 Chromium）每个 appex 各嵌一份 application-identifier 与其 bundle id 对应的 profile。本通道只备一份卖家 profile，工艺上无从为 appex 生成对应件。

## §5 profile 覆盖假说（已由取证证实，不再是假说）

假说原形态：profile 不覆盖 appex 的 bundle id。签名后 ipa 直接给出 profile 本体字段（§2），假说证实（proven），且比原设想更严：该 profile 的 application-identifier 与**主程序**的 bundle id 同样无关（卖家自有 app 的显式 id），主程序能装纯属本通道对主程序侧不执行该覆盖校验的实证行为。在不拿到 profile 本体的前提下原设计的间接判别（换后缀变体）已被实物取证取代，不再需要。

## §6 判别变体清单与判读

### VEA / VEB（主线已备，本线已验构造）

均基于未签的 0.9.60 原版、单因素改动 appex 的 CFBundleIdentifier：

| 变体 | appex bundle id 改为 | 大小 / md5 | 测什么 |
|---|---|---|---|
| Moment-0.9.60-VEA-suffix.ipa | app.tiger4240.lychee1720.liveops | 11,662,170 B / 3f6bd32022170548faf1795b26abd726 | 后缀语义：profile App ID 作命名空间前缀是否被接受 |
| Moment-0.9.60-VEB-exact.ipa | app.tiger4240.lychee1720 | 11,662,166 B / 90390ae9e5e97437b1adb51945d16d0b | 同名语义：是否须与 profile App ID 逐字一致 |

构造核验（本线）：两件与原版的条目级差异恰为 appex Info.plist 一件，zip 完整、无增删条目。
**构造注记（须主线知悉）**：两件只改了 plist，未同步刷新 appex 二进制 CD 的 special slot-1（仍为旧 plist 的哈希），以新 validate 口径验为 rc=3。本线评估其对装测判读的影响为可忽略，依据是 §2 实物：该工具对 appex 的 CD 是整体重建（ident、entitlements、CMS、DER 皆重建），slot-1 必然在签名时按当时 plist 重算，交付侧的陈旧值活不到 installd 面前。若主线追求构造洁净，修法与构建自身在 plist 变更后的形态一致：把 slot-1 刷为新 plist 的 sha256（恰 32 字节、位于签名区内、不动任何代码页与尺寸），本线的 VE1/VE2/VE4 即按此法构造且 validate 全过；若 VEA/VEB 出现负结果且需排除一切构造噪声，可先刷新 slot-1 再复测同一变体。

判读：VEA 装 → 后缀语义成立（见 §7）；VEA 不装而 VEB 装 → 同名语义；两者皆不装 → 进入 §7 的下一判别（VE-E）或通道不兼容收口。

### VE1–VE4（本线已备，判读力按新证据重估）

四件均保留 appex 旧 id（com.canopies.moment.liveops），即**已证充分存在的身份阻因在四件中全部在场**，预期结果均为不可装、且不可装不为其自身因素提供任何信息；仅当某件意外可装时才有信息量（将证伪 §2 的身份机理）。故建议装测优先级一律置于 VEA/VEB 之后，不先耗装测次数。构成与签名面状态备查：

| 变体 | 单因素改动 | 大小 / md5 | 签名面 |
|---|---|---|---|
| Moment-0.9.60-VE1-plist.ipa | appex plist 补 MinimumOSVersion=16.0 与 CFBundleSupportedPlatforms=[iPhoneOS] | 11,662,211 B / bae2a651a2de439bf94496602c597176 | slot-1 已刷新（与原版恰差 32 B）；两二进制 validate 全过 |
| Moment-0.9.60-VE2-bundleid.ipa | appex id 后缀 liveops → widget（仍在 profile 命名空间外） | 11,662,159 B / 97fc396d462352ce8464229acdcdb7ff | 同上 |
| Moment-0.9.60-VE3-coderesources.ipa | appex 预置 _CodeSignature/CodeResources（按 codesign 口径生成、仅封 Info.plist） | 11,663,191 B / 5896f625293056184c051559ff672967 | 两二进制逐字节未动、validate 全过；其因素（工具不为扩展生成封印）已被 §2 证伪，判读力仅剩意外阳性 |
| Moment-0.9.60-VE4-liveact.ipa | 主程序 plist 删除 NSSupportsLiveActivities 与 NSSupportsLiveActivitiesFrequentUpdates 两键 | 11,662,138 B / 01eacc2f6dadef74b44a605de735c67f | 主程序 slot-1 已刷新（恰差 32 B）；validate 全过 |

VE2 附注：其设计初衷是判别「liveops 具体 id 的注册/形态问题」（原 H5）；身份机理锁定后该假说失去独立地位——新后缀 widget 同样不在 profile 命名空间内，身份理论预言其败，VEA/VEB 已覆盖 id 维度的全部判别空间。

## §7 结论树（VEA/VEB 结果 → 结论与根治方向）

1. **VEA 可装**（VEB 无需测或同装）：匹配语义 = 命名空间前缀（后缀可扩展）。根治 = appex bundle id 置于现行 profile 的 App ID 命名空间内（如 app.tiger4240.lychee1720.liveops）。代价与注记：扩展身份从此系于卖家 profile 的命名空间，卖家换 profile 须同步改名；appex bundle id 在 Swift 代码中零引用（主线已核：仅自身 plist、构建断言与注释），改名不影响 App 与扩展的联动；构建侧应把 appex id 参数化，并在组版时与签名通道现行 profile 的 application-identifier 对账。
2. **VEA 不可装、VEB 可装**：匹配语义 = 逐字同名。根治 = appex id 与 profile App ID 完全同名。代价：扩展与卖家自有 app 共用同一 bundle id 字符串（在用户设备上无冲突对象，仅为借名），同样系于该 profile；其余注记同上。
3. **VEA、VEB 均不可装**：两条身份语义均不放行，判别未尽，先行下一探针 **VE-E（本线设计、未构建）**：主程序 bundle id 亦迁入 profile 命名空间（app.tiger4240.lychee1720）、appex 为其后缀（app.tiger4240.lychee1720.liveops），使「扩展 id 以主程序 id 为前缀」与「扩展 id 在 profile 命名空间内」两条规则首次同时满足。
   - VE-E 可装 → 绑定规则是扩展 id 的主程序前缀规则（此前各包中 appex 前缀其实合规，真正的增量是主程序 id 进入 profile 命名空间后前缀链与覆盖链贯通）。根治 = 整包 id 迁入 profile 命名空间；代价最大：主程序换 id 即新应用身份、数据容器另起，只宜作通道适配的最后手段，且须用户裁定。
   - VE-E 不可装 → **此签名通道（此 profile）与嵌入扩展不兼容，收口**：在现有卖家 profile 下不存在能通过校验的 appex id 组合。根治只剩两条：其一，向卖家索取 application-identifier 覆盖本 app 的 profile（通配或 com.canopies.moment.* 前缀）；其二，用户自有 Developer 账号按「一扩展一 profile」的正版工艺出包（与既有长期计划合流）。两者达成前，appex 维持不捆绑（0.9.61 过渡态）。

## §8 根治方向备忘（待 §7 定案后另批执行，本批不落修复）

- 若语义判明（VEA 或 VEB 路线）：构建侧把 appex bundle id 改为判明形态并恢复捆绑（BUNDLE_WIDGET_EXT 开关转正），verify 增断言锁「appex id 与现行签名通道 profile 的 application-identifier 满足判明语义」——profile 本体不在仓库，断言以组版时的人工对账记录为准，不许把卖家 id 写死进构建脚本之外的文档口径。
- 若通道不兼容收口：维持去捆绑，待 profile 条件变化（卖家新 profile 或自有 Developer 账号）后按正版工艺（一扩展一 profile）带回 appex。

## §9 本批边界

未改仓库任何源码与构建文件；变体只由 /tmp 样本与 your_files 的 0.9.60 原版副本做条目级单因素改动生成；VE1/VE2/VE4 涉及 plist 变更的二进制已按构建自身口径刷新 CD slot-1 并经新 macho-entitle validate 复核（坏页 0、超出 0 B）；VEA/VEB 为主线所备、本线只验构造（注记见 §6）。原任务「若用户提供签名后 ipa 时的取证清单」已因实物到手而直接执行完毕，观测值全录于 §2，不再单列假设性清单。
