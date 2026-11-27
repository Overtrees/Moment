# Moment 全链路工作流（交接手册）

> 任何人 / 任何 AI 新会话接管 Moment 开发，先读本文：读完即可搭好
> 环境、跑通出包、独立推进。本文只写「怎么做事」；项目是什么与
> 现状看 [`CONTEXT.md`](../CONTEXT.md)，红线全文看
> [`开发规范.md`](../开发规范.md)，版本账看
> [`CHANGELOG.md`](../CHANGELOG.md)，一周脉络与报告索引看
> [`docs/retrospect-2026-11-21-27.md`](./retrospect-2026-11-21-27.md)。
>
> **本文严禁写入任何密钥 / 令牌 / 密码的值。** 凭据一律只写
> 「在哪、按什么规矩取用」，值只存在于钥匙串文件与各连接器
> 的安全存储里。

## 0. 接管第一步（十分钟清单）

1. 读 `CONTEXT.md`（项目全景与现状）→ 本文（流程）→
   `开发规范.md`（红线）。
2. `cd ~/workspace/Moment && git log --oneline -5 && git status`
   确认当前批次：已入库到哪一版、工作树里躺着哪一批未提交改动。
3. 看 `CHANGELOG.md` 的「iOS 原生版里程碑」节确认最新交付版本，
   再看本文第七节的队列指针确认下一步。
4. 涉及 iOS 出包：先确认 tree 云机在跑（见 2.2），不要在本机
   硬跑全量构建（本机只落码 + 编译级自检，见 2.1）。

---

## 一、项目全景

个人笔记应用「此刻」（Moment）：打开就写、数据归用户本地。
双端共用一个 Rust Core，数据经备份 ZIP 互通。

| 端 | 实现 | 状态 |
|---|---|---|
| Web | Rust Core + Dioxus DOM Web（scheme-B） | 生产：https://canopies-moment.pages.dev ；SQLite 测试站 https://moment-sqlite-test.pages.dev（与生产严格分开） |
| iOS 原生 | SwiftUI + UniFFI 接 moment-core | 阶段 2 进行中；测试签名 ipa 分发，bundle id `com.canopies.moment`，覆盖安装升级 |

仓库：GitHub `Overtrees/Moment`（用户无自有 GitHub 账号，项目仓
一律在 Overtrees 名下），本地 `~/workspace/Moment`。

目录地图（细节见 CONTEXT.md「架构与目录地图」）：

- `rust/crates/core` — 文档模型、MD 解析、备份 ZIP、迁移通道
- `rust/crates/storage` — SQLite 索引、FTS5 trigram 全文检索
- `rust/crates/ffi` — UniFFI 导出面（包名 `moment-ffi`），iOS 专用
- `rust/apps/web` — Dioxus Web 应用；`lang/` 五语包是双端语言真源
- `rust/apps/storage-worker` — Web 存储 Worker（SAHPool VFS）
- `rust/apps/ios` — iOS 原生版：`app/`（Swift 源码 + 构建脚本）、
  `bindings/`（UniFFI 生成的 Swift 绑定，入库）、`src/stub.c`
- `rust/apps/ios/app/` 内 Swift 文件：`MomentApp.swift`（主体，
  约 1.7 万行）+ 按模块拆出的 `MomentLaunch.swift`（启动步进与
  哨兵）、`MomentOps.swift`（运维指令通道）、`MomentRescue.swift`
  （救援页）、`MomentDrag.swift`（拖拽按压引擎）
- 原版（React 版）只读归档：`~/workspace/.scratch/moment-original-archive-2026-11-25/`
  （仓外，只查行为规格，不再改动）

---

## 二、环境搭建

### 2.1 本机（落码机）

当前这台 Linux 云机（VM）：**只做落码与编译级自检**——
`cargo check` / `cargo test`、跑 `verify_ios.sh` 的文本断言、
写文档。不在本机跑全量 iOS 构建、不把无头 Chromium 当常规
回归手段（内存长期受压）。本机保留着完整 iOS 工具链
（`~/ios-native/`，布局同 2.3），仅作应急本地构建。

注意：本机 `/tmp` 是 512M tmpfs——cargo 构建目录、accord
工作目录必须落在 家目录卷上（冒烟脚本已设 `TMPDIR=$HOME/.tmp`，
手工跑构建时照此办理），否则链接期会被撑爆。

### 2.2 tree 云机（冒烟 / 出包 / 回归机）

InstaBox 机器 **tree**（Debian 13，4 vCPU / 7 GiB，
`HOME=/data/home`），与放 SupplyKit 的 canopies 机是**两个不同
的 InstaBox 工作区**，互不可见。tree 不是 Simular Box
（那是另一台机器，勿混称）。

- 机器 ID：`m_agq6jbnlh5tdbred5hcdqlkn6a`
- 访问方式（唯一通道，经连接器 helper）：

  ```bash
  python3 ~/workspace/custom-connectors/custom.instabox-tree/bin/instabox-tree.py \
    machines exec --id m_agq6jbnlh5tdbred5hcdqlkn6a -- "<shell 命令>"
  ```

- 连接器文档：`~/workspace/custom-connectors/custom.instabox-tree/CONNECTOR.md`
- tree 上的布局：工具链实体在 `/opt/tc`，`$HOME/ios-native`
  下各条目是软链指过去；Moment 克隆在 `/opt/work/Moment`
  （克隆后已把 remote URL 里的令牌洗掉）；待构建文件先落在
  `/data/home/overlay/`，再拷进克隆对应位置（见第三节）。
- 分工红线：**canopies 机只留给 SupplyKit / Ollama 本职，
  Moment 的冒烟与回归一律不上 canopies。**

### 2.3 iOS 工具链构成（本机与 tree 同构）

权威说明是技能文档 `~/workspace/custom-skills/ios-dev-linux/SKILL.md`
（Linux 上 Swift 编译 → 链接 → 打包的全部坑都在里面），此处
只列构成：

- Swift 6.4.2 官方 Ubuntu 包：`$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04`
- SDK 两份：`iPhoneOS27.2.sdk`（应用构建用）与
  `iPhoneOS27.1.sdk`（FFI 交叉编译 sysroot，冒烟脚本引用）
  ——**用仓库既有快照，不要新拉第三方 SDK 仓**：新拉的
  .tbd 含工具链不认的架构标记、任何 lld 都拒（迁移时实证）。
- `$HOME/ios-native/swift-resource`（自建 Darwin resource-dir）、
  `mods/`（由 .swiftinterface 编出的二进制 swiftmodule）、
  `bin/accord`（图标 Assets.car 编译器）、`bin/ld64.lld`
  （链接器包装，FFI 构建经环境变量指过去）
- clang / llvm-18 在 `/usr/lib/llvm-18`（系统区，VM 替换会丢，
  丢了重装即可；家目录的工具链不丢）

### 2.4 钥匙串与凭据规矩（只写位置与规矩）

- 钥匙串文件：`~/workspace/user/files/1.txt`——带标签的常驻
  钥匙串，含 Cloudflare token、canopies 与 tree 两把 InstaBox
  令牌、GitHub PAT（用户 2026-11-26 裁定：分别登记、文件
  留在文件区、shell 用；**不销毁、不用后粉碎**）。
- 取用规矩（无例外）：**只在 shell / 脚本内按标签或模式提取
  进变量使用，绝不把文件内容读进对话上下文，绝不打印、
  绝不写入任何仓库文件 / 日志 / 提交信息**。helper 脚本
  （instabox-tree.py、push_small.py）都是运行时自行从该文件
  装载，调用者不需要也不应该接触值。
- Cloudflare 走已登记连接器 `custom.cloudflare`
  （helper `~/workspace/custom-connectors/custom.cloudflare/bin/cf.py`），
  其 token 同样只在 helper 内使用。

### 2.5 天气 key（仓外注入，只写机制）

- 文件：`~/ios-native/weather-keys.json`（仓外，永不入 git）；
  内容是和风（主用）+ 彩云（兜底）两把 key。
- iOS：`build-app2.sh` 构建时若该文件存在则拷入 .app；
  tree 上的副本在 `/data/home/ios-native/weather-keys.json`，
  由 push_small.py 顺带传输（见 3.4）。
- Web：部署时重新注入 staging（见 `开发规范.md` 第四节），
  仓库里永远没有 key。
- App 内用户自填的 key（存 UserDefaults）优先于构建注入值。

---

## 三、日常推进流（以 iOS 一批为例，Web 见 3.8）

### 3.1 落码纪律

- **改前通读**：动手前把相关完整源码读透（原设计意图与
  交互逻辑），不浅读、不抽读。数值规格（手势时长、几何
  公式等）只存在于 Web JS 桥时，先从 Web 源码提取规格
  再落码，不凭印象复刻（教训见 `教训沉淀.md`）。
- **外科编辑**：大文件一律逐处小改（编辑工具定点替换），
  **禁止脚本整文件读-改-写回**——2026-11-22 曾因此把大
  文件截断为 0 字节。写后立即复验 diff / 行数 / 字节数。
- **新模块独立成文件**：不往 `MomentApp.swift` 里继续堆。
  新建 Swift 文件后必须同步登记三处，缺一构建就缺文件：
  ① `build-app2.sh`（仿既有文件：加一轮以它为
  `-primary-file` 的 swift-frontend 调用，并把 .o 加入
  链接行）；② `push_small.py` 的传输名单；③ 3.4 的 tree
  侧 cp 名单。

### 3.2 版本号 bump

每批改两处、verify [1] 三处对账：

- `build-app2.sh` 里 Info.plist 段的
  `CFBundleShortVersionString`（如 0.9.48）与
  `CFBundleVersion`（构建号，如 75，逐批 +1）
- 设置页的版本文本（`MomentApp.swift` 内，与上两处一致）

**提交顺序（CI 不变量）**：bump 先只在工作树内改（供构建
与 tree 冒烟），**bump 的提交必须与该版 release 报告同笔
落**——文档门禁 D4 判同一棵树内现行版本的 release 报告
须存在，bump 单独成笔先推会让该笔 CI 必红（0.9.59/0.9.61/
0.9.62 三例实证，见 `fix_ci_rustweb.md`）。

### 3.3 本机自检

```bash
cd ~/workspace/Moment
cargo test --workspace                       # 改了 Rust 侧时
bash rust/apps/ios/app/verify_ios.sh         # 文本/断言级检查
```

本机 verify 出现 [5]（ipa 陈旧）与 [9]（产物语言包）两条红
是**已知产物红**——产物要到 tree 构建后才更新，不算失败；
其余组红必须当轮修掉再往下走。

### 3.4 传 tree

```bash
python3 ~/workspace/tree-sync/push_small.py
```

该脚本：按名单逐个传 app 源码文件与五语包到 tree 的
`/data/home/overlay/`，顺带传天气 key 文件、确保 tree 上
克隆存在；base64 分片 **≤30K 字符**一片（InstaBox exec
通道更长会截断），逐片校验长度、整文件 md5 对账。
名单是写死的——新增 / 改名文件先改脚本（见 3.1）。

传完后在 tree 上把 overlay 拷入克隆（这条命令每批照抄，
名单与 push_small.py 保持一致）：

```bash
python3 ~/workspace/custom-connectors/custom.instabox-tree/bin/instabox-tree.py \
  machines exec --id m_agq6jbnlh5tdbred5hcdqlkn6a -- \
  "cp /data/home/overlay/MomentApp.swift /data/home/overlay/MomentLaunch.swift \
      /data/home/overlay/MomentOps.swift /data/home/overlay/MomentRescue.swift \
      /data/home/overlay/MomentDrag.swift /data/home/overlay/build-app2.sh \
      /data/home/overlay/verify_ios.sh /opt/work/Moment/rust/apps/ios/app/ \
   && cp /data/home/overlay/lang/*.json /opt/work/Moment/rust/apps/web/lang/"
```

### 3.5 tree 冒烟（出包门）

单次 exec 调用约 60 秒就会在 API 层超时，**长命令必须
detach**，靠轮询日志跟进：

```bash
# 在 tree 上后台启动（经 helper exec 发出）：
cd /opt/work/Moment/rust/apps/ios/app && \
  setsid nohup bash smoke_ios.sh > /data/home/smoke<NN>-tree.log 2>&1 &

# 轮询（短命令，反复查）：
grep -E '^==|ALL PASS|FAIL' /data/home/smoke<NN>-tree.log | tail -8; \
  pgrep -f smoke_ios.sh >/dev/null && echo SMOKE-RUNNING || echo SMOKE-DONE
```

判读：日志出现 `SMOKE ALL GREEN` 才算过（构成见第四节）。
红了先看是哪一阶：[1/4] cargo 测试、[2/4] FFI 重建、
[3/4] 构建、[4/4] verify 断言。

**排障要点（2026-11-27 实证）**：[3/4] 构建失败时，
冒烟日志可能只剩几百字节——build-app2.sh 的输出经
`tail` 过滤，编译器完整诊断会被吞掉，只剩尾注。此时
不要对着空日志猜：直接在 tree 上带跟踪重跑构建本体，
真错立刻现形：

```bash
cd /opt/work/Moment/rust/apps/ios/app && \
  setsid nohup bash -x build-app2.sh > /data/home/build-trace.log 2>&1 &
# 然后读 build-trace.log 尾部
```

### 3.6 取包

```bash
# 先改 pull_ipa.py 顶部的 LOCAL 为本版文件名，再运行：
#   LOCAL = "/home/hatch/workspace/your_files/Moment-<版本号>.ipa"
python3 ~/workspace/tree-sync/pull_ipa.py
```

脚本从 tree 分片下载 `build/Moment-stage2.ipa` 并与远端
md5 对账；交付文件一律是带版本号的新文件名，放在
`~/workspace/your_files/`。

### 3.7 提交与推送

```bash
cd ~/workspace/Moment
git add <本批文件…>          # 按批圈定，不无差别全加
git commit -m "0.9.x：一句话说清本批根治了什么 + 关键手段"
PAT=$(grep -o 'ghp_[A-Za-z0-9]*' ~/workspace/user/files/1.txt | head -1)
git push "https://Overtrees:${PAT}@github.com/Overtrees/Moment.git" main \
  2>&1 | sed "s/${PAT}/***/g"
git ls-remote "https://Overtrees:${PAT}@github.com/Overtrees/Moment.git" main
# 远端哈希必须与本地 git rev-parse HEAD 逐字一致才算推完
```

- PAT 只在 shell 变量里活一程：不写进 remote URL 落盘、
  不进任何输出（回显一律经 sed 脱敏）。
- **逐批推、不攒批**（`PUSH.md` 立的规矩）。`PUSH.md` 写
  的是一次性令牌流程，与此处是同一通道；钥匙串的保留
  口径以 2.4 为准（用户后来的裁定覆盖了「用后粉碎」）。
- GitHub 的 MCP 推送只收 UTF-8 文本（无二进制、无删除），
  常规批一律走上面的 PAT 路线。

### 3.8 交付口径

- 把 `Moment-<版本号>.ipa` 作为附件发给用户，附一句：
  **覆盖安装，不要删旧 App**（笔记数据在 App 数据内，
  删装即丢）。
- 交付说明写清：本批改了什么、真机要验哪几项（只有真机
  终判类——体感、光标、视觉、崩溃——才提用户验，其余
  自己验完再报）。

### 3.9 Web 侧流程（一行版，细节见 CONTEXT.md 与开发规范第四节）

构建 `bash rust/apps/web/build.sh`（SQLite 构建加
`MYNOTE_SQLITE=1`）→ 静态门 `bash scripts/verify_rustweb.sh`
→ 部署器出归档并以 `verify_live` 核对 LIVE == ARCHIVE →
天气双 key 每次部署重新注入 → 浏览器全量回归
`bash tests/run_all_tests.sh`（在 tree / box 上跑，不在本机）。

---

## 四、质量门

### 4.1 出包门：smoke_ios.sh 四阶（用户 2026-11-26 立规）

每次出包前全量跑，全绿才出包，红了先修不发：

1. `cargo test --workspace` — 含 core 回归与 ffi 契约测试
2. 重建 iOS FFI 静态库（`cargo build -p moment-ffi --target aarch64-apple-ios`）
3. `build-app2.sh` 构建 ipa
4. `verify_ios.sh` 分组断言（现行十五组）

### 4.2 verify_ios.sh 分组速览

| 组 | 守什么 |
|---|---|
| [1] | 版本串三处一致（构建脚本 / 设置页 / 产物） |
| [2] | 工具链禁区零回潮（见 4.3） |
| [3] | FFI 契约：Swift 调用面在 bindings 中齐备 |
| [4] | 数据契约守卫（既定数据形态在位） |
| [5] | ipa 产物存在与完整性 |
| [6] | UniFFI checksum 双向核对（见 4.4） |
| [7] | 几何前提断言（数字依赖的结构前提） |
| [8] | 图标 / 开屏资源（Assets.car 路线） |
| [9] | 五语包完整性（与 Web 真源 md5 对账） |
| [10]–[15] | 逐批修复的防回归断言（一批一组，只增不减） |

新一批落码若动了既有机制的前提，同步给对应组补断言；
新机制自带新组（编号顺延）。

### 4.3 工具链禁区（本工具链 + iOS 27.2 实证，verify [2] 守）

- `@State` 宏插件缺失 → 状态一律 ObservableObject
- PhotosPicker / VideoPlayer 不可见 → PHPicker / AVPlayerViewController
- builder 式 `List { Section }` 构建即 trap → 用无 Section 的 List
- 部署目标 16.0；SwiftUI Text 拼接注意前景色口径

### 4.4 UniFFI checksum 坑（改 FFI 必读）

**导出函数的文档注释也计入 checksum。** 改 `crates/ffi`
导出面——哪怕只改注释——checksum 就变；只重建库不重生
绑定，真机首次 FFI 调用即在初始化断言闪退（0.9.15 埋雷、
0.9.17 首装引爆的实案）。规矩：

1. 改导出面 → 重跑 bindgen 生成 Swift 绑定 → 回拷到
   `rust/apps/ios/bindings/`
2. 同步更新 ffi 契约测试里的 checksum 断言表
   （现行契约 22 项导出）
3. verify [6] 双向核对通过才算完

### 4.5 Diag 证据工作法

- 每个功能模块 / 页面在落地时同步接 Diag 日志（硬规矩，
  不后补）；日志记**结果侧量测**（耗时、计数、状态变迁），
  不记意图。
- 真机问题的第一证据面是用户导出的 Diag 日志与 .ips
  崩溃报告（存 `~/workspace/user/files/`，勿删）。判读
  顺序：先在日志里定位对应打点行，再回代码对机制。
- 结论分级：**proven**（源码 / 日志 / 实测直证）、
  **inferred**（证据链推定）、**unknown**（未定）——报告
  与汇报都按级写，inferred 不冒充 proven；被新证据推翻
  的旧结论当面更正、不留含糊。
- 交互类修复的验收面必须与失败面同级：手势 / 落焦类
  只有用户真机（或至少同引擎）结果算终判，无头 / 模拟
  通过只算参考。
- 单例纪律（0.9.43 闪退定案）：单例初始化链内**禁止**
  经格式化 / 本地化回读另一个单例（会成初始化环、递归
  锁死进程）；DiagLog 必须零依赖叶子化，verify [12] 守。

---

## 五、运维面

### 5.1 热更新指令通道（原生 App）

用途：极端问题（闪退类）不靠重装新 ipa，靠下次启动拉取
的运维指令热修（跳步 / 降级 / 强制安全模式）。指令文件
`ops.json`，**字段白名单只有两个**：`disableSteps`
（启动步名数组）、`forceSafeMode`（布尔）。核心数据步
（开库 / 读数据）不设 guard 点，不可被指令跳过。

双源（App 端端点常量在 `MomentOps.swift`）：

| 源 | 地址 | 改法 |
|---|---|---|
| 主源 Cloudflare Worker「moment-ops」 | https://moment-ops.overtrees.workers.dev/ops.json | 改 Worker 脚本内的 OPS 常量后重新部署（见下） |
| 备源 GitHub Pages（仓 `Overtrees/moment-ops`） | https://overtrees.github.io/moment-ops/ops.json | 改仓内 ops.json 并推送（Pages 约 10 分钟缓存，App 拉取带时间戳参数绕过） |

主源改法：

1. 编辑 `~/workspace/tree-sync/moment-ops-worker.js`
   顶部的 `OPS` 常量（只动白名单字段）。
2. 用 Cloudflare helper 部署（经典 `addEventListener`
   格式——helper 的 workers put 不收 `export default`
   模块格式，写错会报 10021）：

   ```bash
   python3 ~/workspace/custom-connectors/custom.cloudflare/bin/cf.py \
     workers put --account <Overtrees 账号 id> --name moment-ops \
       --file ~/workspace/tree-sync/moment-ops-worker.js
   ```

   账号 id 用 `cf.py accounts` 查（Worker 在 Overtrees
   账号下，不在个人账号下）。
3. Worker 响应带 `Cache-Control: no-store`，部署即生效。

App 侧消费：启动判定消费缓存指令（forceSafeMode /
disableSteps），联网刷新在主页加载后后台进行；每次成功
拉取在 Diag 记一行
`OPS directives fetched src=<worker|github> steps=<n> forceSafe=<0|1>`——
运维时先查这行确认指令到达。

> 注：曾试过 Cloudflare Pages 直传托管同一文件，API 报
> 成功但边缘持续空 500，已弃用（空项目留置）；不要再
> 往 Pages 直传方向折腾，备源走 GitHub Pages。

### 5.2 救援 / 安全模式

- 原生：启动步进集中定义在 `MomentLaunch.swift`
  （LaunchStep + 哨兵文件 launch-sentinel.json 原子直写）；
  连续启动未完成达阈值 → 下次启动进安全模式，救援页
  （`MomentRescue.swift`）只依赖 Diag 与文件元数据，可
  导出诊断 / 尝试正常启动 / 检查热修复。规格与后续
  R2 / R3（只读开库、看门狗等）在
  `docs/reports/plan_native_rescue.md`。
- Web：救援层内联在 `rust/apps/web/index.html`（加载快照、
  12 秒看门狗、`?rescue=1` 直达面板；修复动作只注销 SW
  与清 Cache Storage，**绝不动 IndexedDB / OPFS 站点
  数据**）。每次 Web 部署的基线都含救援层，不得破坏
  其独立性（`开发规范.md` 第四节）。

### 5.3 Web 生产部署

见 3.9 与 `开发规范.md` 第四节：部署器出归档、
`verify_live` 核对 LIVE == ARCHIVE、天气 key 部署时
注入、救援层在基线内。生产戳记在 CONTEXT.md「地址」节
与 CHANGELOG「Rust 版生产里程碑」节。

### 5.4 App 内 MCP 桥（M1，只读）

状态：**已接通**（2026-11-27 真机活验，App 0.9.52 /
build 79；中继 moment-bridge.overtrees.workers.dev，
设备指纹 156E 8166 1ED7 642F，能力位 read + ops）。
方案与落码见 `docs/reports/plan_app_mcp_bridge.md`、
`impl_bridge_m1.md`、`fix_bridge_pairing_state.md`；
日常操作与排障以连接器 doc 为准
（`~/workspace/custom-connectors/custom.moment-bridge/CONNECTOR.md`），
中继部署法与坑见 ios-dev-linux 技能
`references/mcp-bridge-relay.md`，此处只记验活口径。

验活（App 须在前台且桥已连接——后台挂起即断连属
设计行为，后台时段的 app_offline 不作失败结论）：

```bash
python3 ~/workspace/custom-connectors/custom.moment-bridge/bin/client.py list-tools
python3 ~/workspace/custom-connectors/custom.moment-bridge/bin/client.py call-tool \
  --name bridge_status --arguments-file <含 {} 的 json 文件>
```

`bridge_status` 每次会话先打，核对清单哈希与端内
一致；`app_state` / `diag_tail` 已实测可回真机数据。
M2（语义读写 + 运维动作）已随 0.9.54 出货：工具
面 22 件、清单哈希已与端内对齐活验；桥内 UI 自
检驱动 U 批进行中（U0 地基已落码，工具入册在
U1 批）。

---

## 六、红线与口径速查（一句话版，全文按指针查）

- **开发规范六条**（改前通读 / 行为等价且实现更优 /
  根治不打补丁 / 拒绝上帝文件、按作用独立成文件 /
  复用优先、尾巴查无消费方再删 / 结论即时沉淀到文档）：
  工作区 `~/AGENTS.md`「开发规范与红线」节 + 仓库
  `开发规范.md`。
- **行为等价优先于形态 1:1**：Web 的做法若是平台妥协
  （如文字大小分级），原生有系统能力就走系统能力
  （如 Dynamic Type、系统 Toggle），不抄妥协形态。
- **退役即删除**：功能退役时其标记 / 样式 / 信号 / 打点
  连带清零，以 grep 零残留为据，不留兼容孤儿层。
- **样式走全局**：呈现走全局样式表与既有令牌变量，
  不写内联样式、不新造裸值。
- **测试分工**：tree 跑冒烟 / 回归全量；本机只落码与
  编译级自检；特殊情况用 App 内置浏览器兜底；真机终判
  只认用户设备结果。
- **诊断同步落地**：新模块同批带 Diag，不后补（见 4.5）。
- **安全区动态取值**：一律运行时 env / 视口单位，
  禁止写死某台设备的数值。
- **Safari 站点数据绝不轻清**：Web 版笔记在 IndexedDB /
  OPFS，清站点数据 = 笔记全没；ZIP 备份是安全网。
- **逐批推送**：每批冒烟绿即提交推送，不攒批（见 3.7）。

---

## 七、当前状态与队列指针（截至 2026-11-27 午间）

- 已交付：iOS 0.9.44（J1 十项 + 闪退热修）、0.9.45
  （自救 R1 + 热更新通道）、0.9.46（/ 菜单公式两项）、
  0.9.47（拖拽第二轮，仲裁子系统替换）；逐版账在
  `CHANGELOG.md`「iOS 原生版里程碑」节。
- 进行中 / 待判：0.9.48 新建过渡第二轮根治在工作树
  （落码已成、冒烟中）；拖拽第三轮排查已定案待落码
  （`docs/reports/audit_drag_pickup_round3.md`：并行豁免
  放开 + 卡片块武装——卡片在 Web 上可拖，原生 disarmed
  是范围错误，落码批一并纠正）；0.9.47 的拖拽仍待用户
  真机终判。
- 后续队列（编号随前批顺延）：设置天气分组重构
  （方案 `docs/reports/plan_weather_settings.md` + 差距账
  `docs/reports/audit_weather_settings_gap.md`）→ J2 浮层
  与 MD 微差批（`docs/reports/plan_batch_j2_specs.md`）
  → 音乐 / 图片线 K 批 → i18n I4 / I5
  （`docs/reports/plan_native_i18n.md`）→ 自救 R2 / R3
  （`docs/reports/plan_native_rescue.md`）。
- 专项报告全索引：`docs/retrospect-2026-11-21-27.md`
  第四节（77 份 reports 按主题列齐）。
- Web 侧未收口：SQLite 双写观察期（2026-11-25 起，
  退出判据 ≥14 天且 ≥30 次冷启对账全等 / 漂移可解释、
  Diag 零降级行）达成后发默认 sqlite 切换版。
- 长线定案：多人 / 同步 / 真 iCloud 等用户自开 Apple
  Developer Program 后在原生端接入，当前只留 provider
  接口缝；签名证书为测试签名（零 iCloud 容器授权），
  不在此方向投入。
