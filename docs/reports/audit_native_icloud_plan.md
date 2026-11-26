# 原生版 iCloud 备份接入 — 设计与核验计划

日期：2026-11-22。性质：设计文档，只出方案与核验清单，不动代码。
决策来源：用户 2026-11-22 拍板——原生版必须加入 iCloud 备份；Web 版
CloudKit 因需用户自己名下的开发者会员先放一放、只留 provider 接口。

证据分级：proven（有源码/官方文档/实测支撑）、inferred（由 proven 事实
推导）、unknown（未核验、需后续步骤定案）。苹果口径优先引官方文档名。

## 0. 本地既定事实核对（proven，均已查源码/仓库）

- Rust Core 与平台无关且已就绪：`rust/crates/core` 的
  `backup_zip.rs` 提供 `read_backup_zip` / `write_backup_zip`，包结构 =
  memos.json（version 2）+ manifest.json（原文透传）+ attachments/<id>，
  与原版 ZIP 字节兼容（文档格式冻结红线）。
- 恢复口径已存在且 proven：`rust/crates/storage` 的
  `Store::import_backup`——先由 core 把整包解析校验完毕（manifest 结构
  校验、体积上限），再在单个事务里全量换库（validate-then-swap），
  坏包不污染现有数据。iCloud 恢复直接复用这条路径，不另设校验。
- 格式上限（core 校验口径）：zip ≤ 50 MiB、解压 ≤ 200 MiB、条目 ≤ 3000。
  这是 iCloud 载荷的尺寸上界，选型时按此评估。
- 原生树现状：`native/` 内是已弃用的 Flutter 应用与 spike；原生 UI
  框架选择有既定结论「等设备 spike」，本设计不推翻。
- 打包：无 Mac，GitHub Actions 云端 macOS 出无签名 IPA，bundle id
  现为 app.canopies.mynote（此值可能被证书核验结果推翻，见 §1.3）。

## 1. 证书核验清单

### 1.1 核验对象与方法（proven 方法）

描述文件（.mobileprovision）是 CMS 签名的 plist，可离线解析出完整
字段（`security cms -D -i <file>` 或等价库），不需要设备、不需要联网。
p12 是 PKCS#12 包，需密码才能解出证书与私钥。核验分两段：先只验
描述文件（多数结论在此即可定），p12 只在真正签名打包前才需要交接。

### 1.2 必查字段与判读表

| 字段（描述文件 Entitlements / 根字典） | 看什么 | 结论分支 |
|---|---|---|
| `Entitlements.application-identifier` | 形如 `<TEAMID>.<bundle>`；后缀是否含 `*` | 含 `*` = 通配 App ID → **iCloud 不可用，一票否决**（iCloud 等能力必须显式 App ID，见 §1.4）；为显式 id → 该后缀就是本 App 必须采用的 bundle id |
| `Entitlements.com.apple.developer.icloud-container-identifiers` | 是否存在且为非空数组，元素形如 `iCloud.<...>` | 缺失/空 → 描述文件根本没带 iCloud 容器，卖家说法不成立，否决；非空 → 记下容器 id（构建配置要用，核验阶段只记结论不外传值） |
| `Entitlements.com.apple.developer.icloud-services` | 数组是否含 `CloudKit` / `CloudDocuments` | 决定可用通道：含 CloudKit → CloudKit 可选；含 CloudDocuments → iCloud Drive 可选；两者都有 → 按 §2 推荐走；都没有 → 否决 |
| `Entitlements.com.apple.developer.ubiquity-container-identifiers` | 是否非空 | iCloud Drive 通道需要它与 icloud-container-identifiers 同时指向容器；缺失则 Drive 通道不成立 |
| `Entitlements.com.apple.developer.ubiquity-kvstore-identifier` | 是否存在 | 只影响 KV Store（本设计排除，见 §2），有无不作否决项 |
| `TeamIdentifier` / `TeamName` | 团队 id 与名称 | 容器归属团队即此团队（卖家团队）；与 application-identifier 的 TEAMID 前缀应一致，不一致 = 文件拼凑，直接否决 |
| `ExpirationDate` | 过期时间 | 与「一年期」说法核对；剩余有效期 < 3 个月要在报告里预警（到期 App 打不开，属通道存续风险） |
| `ProvisionedDevices` / `ProvisionsAllDevices` | 前者为设备 UDID 列表；后者 true = 企业级全设备 | 用户 iPhone 的 UDID **不在** ProvisionedDevices 里 → 这张描述文件装不到用户手机上，否决（或要求卖家补登记）；ProvisionsAllDevices=true → 安装不受 UDID 限制，但企业证书被吊销的面更大，风险等级上调 |
| `Entitlements.get-task-allow` | true = 开发型，false = 分发型 | 决定 CloudKit 环境：开发型 → Development 环境（schema 可按需自动创建）；分发型 → Production 环境（schema 必须由团队所有者预先部署，见 §2.3 的关键分支） |
| `DeveloperCertificates` | 内含证书的指纹/过期时间 | 与 p12 解出的证书比对指纹是否一致、证书是否在有效期内；不一致 → p12 与描述文件不是一套，签名必失败 |
| 根字典 `Name` / `AppIDName` | 卖家给这套文件的命名 | 辅助判断卖家是否专为某固定 bundle id 出货（与第一项互证） |

### 1.3 最容易翻车的一项（inferred，须在核验报告里置顶）

转售型「支持 iCloud」证书通常绑定卖家指定的**固定 bundle id**（因为
iCloud 必须显式 App ID，卖家要在自己账号下预先注册 App ID + 容器）。
这意味着原生版的 bundle id 大概率不能用 app.canopies.mynote，必须
改用描述文件 application-identifier 指定的那个。核验第一结论就是
「本 App 要用的 bundle id 是什么」，后续打包、容器配置全部以此为准。

### 1.4 依据

- 苹果《Configuring iCloud services》（Xcode 文档）：各 iCloud 服务与
  entitlement 的对应关系——CloudKit 与 iCloud Documents 都写入
  `com.apple.developer.icloud-container-identifiers`，Documents 另加
  `com.apple.developer.ubiquity-container-identifiers`，服务开关记在
  `com.apple.developer.icloud-services`（CloudKit / CloudDocuments）。
- iCloud 必须显式 App ID、通配 App ID 不能启用 iCloud：苹果 App ID
  注册口径（能力按 App ID 允许列表管理，通配 id 下此类能力不可选），
  多方签名文档一致 corroborated，定级 proven。
- 描述文件构成（App ID + 证书 + 设备 + entitlement 允许列表，由苹果
  签发、设备在启动时校验）：苹果 TN3125《Inside code signing:
  Provisioning profiles》口径。

### 1.5 交接方式（本线不实际索取，仅定规矩）

沿用既有 1.txt 式一次性交接：用户把 .mobileprovision 放成单个附件
文件 → Tree 在隔离临时目录解析、只把 §1.2 的**结论**（通过/否决/
风险项）带出 → 原文件用后 shred 销毁、不进仓库、不进记忆、不留副本。
p12 及其密码不在本阶段交接；到签名打包阶段再单独走，且密码只走
安全输入通道、绝不经聊天明文（沿用既定凭据纪律）。

## 2. iCloud 通道选型

载荷前提（proven）：备份是一个完整 ZIP（≤50 MiB），恢复是全量
validate-then-swap。备份语义是「整包快照替换」，不是逐条同步——
选型按整包载荷评估，不按记录级同步评估。

### 2.1 三通道逐项比

| 维度 | CloudKit 私有库（CKAsset 存 ZIP） | iCloud Drive ubiquity 容器（文件式） | KV Store |
|---|---|---|---|
| 载荷适配 | CKRecord + CKAsset 承载整包字节，可行；单次保存有明确成功/失败回执 | 容器内放 ZIP 文件本体，与现有导出文件完全同形 | **排除**：总量上限 1 MB、最多 1024 键（苹果《Configuring iCloud services》），ZIP 可达 50 MiB，量级不符；至多适合存「最近备份时间」这类指针 |
| 冲突处理 | 服务器 change tag 可做乐观并发（ifServerRecordUnchanged），冲突是显式错误码，可编程处理 | 文件级冲突产生冲突版本副本，需应用自己按文件名/时间戳裁决；用「只新增、永不原地改」命名法可基本绕开（见 §4） | 不适用 |
| 容量计费 | 私有库数据计入**用户本人** iCloud 容量（苹果 WWDC14《Introducing CloudKit》：私有库数据计入用户配额、开发者不可见）；不占卖家团队的公共库配额 | 同样计入用户本人 iCloud 容量（其 iCloud Drive 本人空间） | 计入用户容量但量级忽略 |
| 离线/恢复语义 | 在线 API：fetch 有确定错误（未登录/无网络/配额满），恢复流程可控；离线时只能提示 | 系统托管同步：文件可能「在云端未下载」，恢复前须显式触发下载并等完成；同步时延不确定，但系统在后台持续推进 | 不适用 |
| 卖家团队依赖 | **有额外依赖**：分发型描述文件走 Production 环境，record type 的 schema 必须由团队所有者（卖家）在 CloudKit Dashboard 部署后才能保存成功；开发型走 Development 环境可按需建 schema（见 §2.3） | **无 schema 概念**：容器在描述文件里存在即可用，不需要卖家任何后台操作 | 无 |
| 与 Web 版 CloudKit JS 的衔接 | 同一容器同一 record type，Web 将来拿到 API token 即可读同一份快照——但 token 只能由团队所有者在 Dashboard 生成（苹果 WWDC15《CloudKit JS and Web Services》：容器 + API token + 域名限制都在 Dashboard 配置），卖家团队下此路实际不通；用户自有团队容器下才成立 | Web 端无 iCloud Drive 的 JS 接口，衔接为零；但 ZIP 文件本身就是跨端通用载荷，Web 可经用户手动文件流转 | 无 |
| 用户自救 | App 死了就够不着（数据仍在用户私有库里，但没有第二个客户端能读卖家容器） | **文件在「文件」App 里可见可拷贝**（声明 NSUbiquitousContainers 公开文档域时），App/证书出事时用户能手动把 ZIP 拷出来用 Web 版导入——直接对冲头号风险（通道存续） | 不适用 |

### 2.2 推荐（结论）

**主通道：iCloud Drive ubiquity 容器（文件式）。** 理由按权重：
(1) 零卖家后台依赖——本项目最大的外部不确定性就是卖家团队，
Drive 通道把卖家依赖压到只剩「描述文件本身有效」一项；
(2) 载荷零改造——放进去的就是现有备份 ZIP，恢复直接喂
import_backup 的 validate-then-swap；
(3) 用户自救路径存在——证书失效时数据不被锁死在容器里，
文件可见可拷出，Web 版可接盘导入。
**CloudKit 定为迁移后目标**：等容器换到用户自有团队（§4.3），
CloudKit 的显式回执、乐观并发与 CloudKit JS 同容器衔接才全部
成立，届时经 provider 接口切换通道，载荷与恢复路径不变。
KV Store 只留作可选小状态指针（如最近备份时间戳），不承载备份。

此推荐与 Web 线的 provider 接口决定同构：Web 侧已定「备份层留
provider 接口、文件 provider 为现行实现」；原生侧把 iCloud Drive
作为第二个 provider 实现接入同一边界，CloudKit 是第三个预留位。

### 2.3 关键分支说明（inferred，核验后定案）

若 §1.2 查得 get-task-allow=true（开发型描述文件），CloudKit 的
schema 障碍消失（Development 环境按需创建 record type），且开发型
描述文件通常意味着卖家按设备出货——此时 CloudKit 可升为并列候选，
但 §2.2 的 (1)(3) 两条理由仍在，推荐不变，仅把 CloudKit 列为
「可提前接的第二实现」。若为分发型（大概率），按 §2.2 执行。

## 3. 原生 UI 栈衔接（仅 iCloud/签名相关面，不做全面选型）

共同前提（proven）：CloudKit 与 ubiquity 容器都是苹果原生框架
（CloudKit.framework / Foundation 的 NSFileManager ubiquity API），
**没有 Rust 绑定可用**，iCloud 传输层必然是原生代码（Swift/ObjC）。
因此架构切分与 UI 框架无关：Rust Core 负责产出/消费 ZIP 字节
（write_backup_zip / import_backup 已就绪），原生壳负责把字节
搬进搬出 iCloud 容器——即 provider 接口的 transport 实现在原生侧，
数据面在 Rust 侧。UI 框架之争不影响 iCloud 设计，只影响这层
transport 胶水写在哪。

- **原生 Swift 壳 + UniFFI 调 Rust Core**：契合度最高。iCloud API
  一等公民，entitlements/签名在标准 Xcode 工程里配置，GitHub
  Actions 云端打包链与既有 IPA 流程同形；UniFFI 是 Rust 官方
  绑定生成路线，ZIP 字节以 Data/[UInt8] 过界即可。
- **Dioxus 原生**：其 iOS 渲染路线（WebView 或实验性原生视图）
  之上仍需自写 Swift 插件层调 CloudKit/NSFileManager，等于在
  Swift 壳方案之外多养一层桥；iCloud 本身不受益也不受损，
  成本在框架成熟度，与既定「等设备 spike」结论一致，不在此定案。
- **Slint**：同理需 C++/Swift 胶水调原生 iCloud API；其既有许可与
  Web 存储成本问题（2026-11-21 已评估）与 iCloud 无关，不重复评估。

结论：iCloud 接入点固定为「原生 transport 层 + Rust Core 数据面」，
UI 框架后续无论选谁，此设计不返工。

## 4. 数据与迁移设计

### 4.1 备份对象与命名（绕开 Drive 冲突的主手段）

- 容器内目录放快照文件，命名 `mynote-backup-<UTC 时间戳>-<短设备标识>.zip`，
  **只新增、永不原地修改**——Drive 的文件冲突主要来自同名并发改写，
  此命名法把并发备份变成两个并存文件，裁决退化为「取时间戳最新」。
- 保留策略：本地保留最近 3 份的索引；上传成功后清理更旧的云端
  快照（删除动作在确认新快照已同步上行后才执行）。3 份历史是
  对「坏备份覆盖好备份」的保险：恢复时可任选一份。
- 每份快照的校验值：在文件名同侧放同名 `.sha256` 小文件或把
  sha256 编进同目录的 index.json（小文件，含每份的时间戳/字节数/
  sha256/备忘数）。恢复前先比 sha256，再走 core 校验，双保险。

### 4.2 触发、恢复与冲突口径

- 触发：手动（设置页「立即备份」）为保底；自动触发用「数据变更后
  防抖 + App 退后台时」两个时机，失败只记状态不打扰编辑（沿用
  诊断日志硬规矩：iCloud 备份/恢复全程打 Diag，含容器可用性、
  上行/下行结果、错误码原文）。
- 多端同时备份：各端各写各的快照文件（命名含设备标识），不互斥；
  「最新」按快照内 memos.json 的 exportedAt 与文件名时间戳双核对，
  不一致时以包内为准。
- 恢复：用户在快照列表里选一份 → 下载完成确认 → sha256 比对 →
  `read_backup_zip` 全量校验 → `import_backup` 单事务换库（现有
  proven 路径）→ 换库前自动把当前数据另存一份本地快照（回滚位）。
- iCloud 账户状态：未登录 iCloud / iCloud Drive 关闭 / 容器不可用
  时，设置页如实显示状态（沿用「云备份未连接须诚实显示」的既定
  口径），编辑功能不受任何影响。

### 4.3 降级与迁移

- **证书失效降级**（头号风险的兜底）：证书/描述文件被吊销的最坏
  情况是 App 无法启动。此时数据有三条命：(1) iCloud Drive 里的
  ZIP 在「文件」App 可见（须在 Info.plist 声明
  NSUbiquitousContainers 公开文档域，设计阶段就定死这一项），
  用户可拷出后用 **Web 版导入** 恢复——Web 版是常驻降级通道；
  (2) 数据本身仍在用户 iCloud 里不丢；(3) 质保期内换新证重签
  重装（同 bundle id + 同容器）后通道恢复。本地 ZIP 导出在 App
  能启动的任何时刻永远可用，不依赖 iCloud 状态。
- **迁到用户自有团队**（用户将来入会后）：容器按团队隔离——同一
  容器 id 在不同团队下是**不同的容器**（proven：容器注册在团队
  账号下、随 App ID 归属团队），私有数据不会自动跟随。迁移步骤：
  (1) 旧通道最后一次备份并把 ZIP 经文件导出留存；
  (2) 用户自有账号下注册显式 App ID + 新容器（可同名 id，
  归属新团队）；
  (3) 新签名包指向新容器，首次启动从留存 ZIP 导入恢复；
  (4) 若届时接 CloudKit：在自有容器部署 schema 后走 §2.2 的
  CloudKit provider，Web 版 CloudKit JS 用同一自有容器 + 自建
  API token 与原生互通——Web 留的 provider 接口在此闭环。

## 5. 落地步骤与前置条件

| # | 步骤 | 负责人 | 阻塞点/备注 |
|---|---|---|---|
| 1 | 一次性交接 .mobileprovision（1.txt 式附件），Tree 按 §1.2 解析核验、用后 shred | 用户交 / Tree 验 | 本线的第一步；只验描述文件，p12 暂不需要 |
| 2 | 核验结论定案：可用/否决、必用 bundle id、容器 id、通道分支（§2.3）、有效期预警 | Tree | 若通配 id 或无容器字段 → 当场否决，改走「等用户自有会员」路线，不浪费后续步骤 |
| 3 | 最小 spike 包：只做容器探活（Drive 容器 URL 是否可达 + 写/读/删一个测试文件），按核验出的 bundle id 与 entitlements 打包 | Tree | 打包需 p12+密码交接（安全通道）与 CI 签名配置；GitHub 仓库在 Overtrees 名下，Actions secrets 的写入需账号方配合——协调点，提前知会用户 |
| 4 | 真机安装 spike 并验容器读写 | 用户装 / Tree 远程判读 Diag | **历史阻塞在此消解与否取决于核验结果**：描述文件含用户设备 UDID（或全设备型）→ 可直装，不再需要 SideStore，旧阻塞消解；不含 UDID → 仍需卖家补登记或回 SideStore 路线 |
| 5 | 正式实现：Rust Core 侧 provider 接入点确认（字节进出口已就绪）+ 原生 transport（Drive 写/读/列表/清理）+ 设置页备份区（状态/立即备份/快照列表恢复）+ Diag 全程 | Tree | UI 框架未定案前，transport 层按 §3 的切分先行，UI 只做设置页最小面 |
| 6 | 真机全链验收：备份→在「文件」App 里看到 ZIP→删本地数据→从快照恢复→条数/附件核对；再演练证书降级剧本（拷出 ZIP 用 Web 版导入） | Tree 指挥 / 用户动手 | 恢复正确性以 import_backup 的既有验收口径为准（真实 ZIP 双向无损已有 proven 记录） |
| 7 | 自动备份触发、保留策略清理、异常状态文案收口；文档与记忆更新 | Tree | — |

## 6. 风险总表

| 风险 | 等级 | 说明与对冲 |
|---|---|---|
| 描述文件不支持 iCloud（通配 id / 无容器字段） | 未核验前为最大不确定项 | §1 核验第一步定案，否决成本只有一次交接 |
| 通道存续：卖家证书/账号被吊销 | 高（概率 unknown，影响大） | 数据在用户 iCloud 不丢；Drive 文件可见可拷出 + Web 版导入接盘 + 一年质保换证；本地导出永远可用 |
| bundle id 被卖家绑定 | 中（大概率发生） | 接受并改用指定 id；Web 版域名/数据不受影响，本地数据经 ZIP 迁移 |
| 分发型描述文件 + CloudKit schema 需卖家部署 | 中 | 已由选型绕开（主通道 Drive 无 schema）；CloudKit 推迟到自有团队 |
| iCloud 同步时延/未下载状态导致恢复等待 | 低 | 恢复流程显式触发下载并给进度状态；快照保留 3 份 |
| 用户 iCloud 容量不足 | 低 | ZIP ≤ 50 MiB 量级；配额满时 CloudKit/Drive 均给明确错误，Diag 记录、UI 如实提示 |

## 7. 结论速览

- 推荐通道：**iCloud Drive ubiquity 容器（文件式）为主通道，
  CloudKit 为迁到用户自有团队后的目标通道**，KV Store 排除。
- 第一步：用户一次性交接 .mobileprovision 文件，Tree 只验不留存。
- 最大风险：不是数据归属（数据在用户本人 iCloud 私有空间，已对齐），
  而是**通道存续**——证书被吊销时 App 够不着数据；全部设计
  （Drive 文件可见、Web 接盘、本地导出保底）都围绕这一条对冲。
