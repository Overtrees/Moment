# Web 启动慢排查根治（fix_web_boot_latency）

用户实报（2026-11-28）：新版（戳 5ff8c91ac5）部署后，iPhone 上
Web 进得去但久到异常。本批走独立 worktree/分支
fix/web-boot-latency，量测先行，结论分级 proven/inferred/
unknown。救援层逻辑只量测未改动。

## 一、定案（分级）

- **proven：不是功能回归。** 上版构建基线 4e023aa → 本版
81a5996 之间触及 rust/apps/web 与 rust/crates 的提交为零
（主线取证）；本批在 worktree 重构建的 wasm 与线上逐字节
一致（md5 5ff8c91ac5、4,160,928 B）。干净房全新无状态启
动正常（远在 12s 看门狗内）。
- **proven：稳态冷启把全部启动字节押在网络上。** 改前机制
三件套——资产固定名（moment-web.js / moment-web_bg.wasm）、
平台默认响应头 `Cache-Control: public, max-age=0,
must-revalidate`（无 _headers 文件）、sw.js 对导航/.js/
.wasm/.html 一律网络优先（fetch 无超时、失败才回缓存）。
后果：每次冷启 index/胶水/wasm 都先走网络；304 也要付
RTT+TLS+边缘往返，连接挂起时 fetch 无限等到浏览器放弃
——启动页长卡。慢网量测与用户体感量级吻合（见二）。
- **proven：SW 缓存路径本身是快的。** 改前 warm 量测 boot
176ms、0 网络字节（网络优先失败/回退后由缓存供）——病在
策略让网络当主路，不在缓存本身。
- **inferred（强）：用户这次的长卡 = 部署更新过渡 × 大陆
pages.dev 间歇不稳。** 更新后首启要为新版 SW 预缓存整包
CORE（wire 约 1.55MB，见三），预缓存与页面自身的网络优
先回源在慢/不稳链路上叠加；SW install 是 all-or-nothing，
中途被杀/断网即整包作废、下次冷启重来。个体那一次的确切
分段无手机侧数据（unknown），机制与量级均已对齐。

## 二、启动分段量测（tree，Chromium 154 + playwright-core）

探针 tests/boot_probe.mjs。fresh 组屏蔽 SW 量纯网络路径
（页面会话 CDP 节流覆盖不到 SW 目标，SW 会无节流抢跑预缓
存污染量测——方法学注记见探针头注释）；字节走 CDP
dataReceived 逐包累加。节流档：mid = 下 1.6Mbps/上
750kbps/RTT 150ms；slow = 下 400kbps/上 400kbps/RTT 400ms
（CDP Network.emulateNetworkConditions）。

改前（生产 5ff8c91ac5，固定名资产）：

| 场景 | index 终 | js 终 | wasm 终 | boot 总 | 总 wire |
|---|---|---|---|---|---|
| fresh 无节流 | 95ms | 163ms | 400ms | 597ms | 1,470,747B |
| fresh-mid | 281 | 481 | 7,798 | 7,957ms | 1,470,460B |
| fresh-slow | 730 | 1,284 | 30,639 | 30,769ms | 1,470,663B |
| warm 无节流 | — | — | — | 176ms | 0B |

wasm wire 1,247,289B（brotli）；wasm 到达后 compile+init
约 130–200ms（tree 4vCPU 口径）——耗时几乎全在下载段。

改后（指纹版部署后，同探针）：fresh 无节流 boot 800ms、
wire 1,470,325B（内容不变、路径改名，量级同前，差异为
tree→CF 往返波动）；warm 无节流：prime 508ms 后二启
boot **129ms、0 字节、全 8 请求 fromServiceWorker**；
warm-mid（1.6Mbps 节流）：二启 boot **125ms、0 字节、
全请求 SW 供**——节流对稳态冷启已无影响（对照同档
fresh 7,957ms：差的正是那一整包网络下载）。对照改前 warm 176ms
（同为 0 字节，但那是网络优先逐项尝试/回退后的结果，
慢网下不可同日而语——改后大文件资产结构性零网络）。

## 三、更新过渡字节账（本地静态服模拟，服务端请求账定案）

归档双版在 tree 本地同源模拟（旧 1b3eee9998 首启 → 原地
换新 5ff8c91ac5 → 更新启 → 落定窗 → 再启；服务端带弱
ETag 与 brotli，字节为本地压缩口径，与 CF 略有出入，计数
与结构为准）：

- 旧版首启服务端总出账 1,889,113B：页面自取一遍（index/
js/wasm/图标 200）+ SW 预缓存一遍（多为 304 回源核对，
manifest/五语言包/storage-worker 三件为 200 实下）+
storage-worker 再回源一轮（304×3）。**预缓存的
cache.addAll 恒走网络**（命中 HTTP 缓存也付回源核对）。
- 更新启（换版后第一次）：页面由**旧 SW 的旧缓存全量供**
（boot 151ms、0 字节）——skipWaiting+claim 的实际时序
是：新 SW 先在后台 install（预缓存新 CORE），激活后才
接管；本启不付新版下载。
- 落定窗（6s）内新 SW 预缓存完成：新 wasm 等实下
915,776B（本地 brotli 口径；CF 口径新 CORE wire 约
1.55MB，其中 wasm 1,246,152B）。**更新的真实成本落在这
里：整包新 CORE 一遍全量下载**，与页面流量异步重叠。
- 再启：新缓存供，boot 170ms、0 字节。
- 推论（inferred）：若预缓存未落定前 app 被杀或断网，
install 整包作废，下一启重复整包尝试——慢/不稳链路上
「连着几次打开都很慢」由此而来；且每次冷启页面自身仍
走网络优先（见一定案），两笔账叠加。

## 四、产物与构建口径对照

- wasm：上版（1b3eee9998）4,211,575B；本版 4,160,928B
——**本版反小 50,647B（1.2%），无异常变大**，wasm 体积
治理不立项。
- dist 总量：上版 7,175,654B vs 本版 4,683,618B，差
2,492,036B 全部来自 storage-worker（2,403,520B）等
sqlite 构建产物：**上版生产是 MOMENT_SQLITE=1 构建
（源 /tmp/dist65），本版是默认构建**——构建口径不统一
本身是事实登记：默认构建的 dist 无 storage-worker，
sw CORE 亦不含其条目，存储面走 IDB 路径（阶段三双写
的降级形态）。此口径差异与启动慢无因果（本版反而更
轻），但与存储线观察期口径需主线对账（见七）。
- release profile 两版同源：rust/Cargo.toml lto="fat"、
codegen-units=1、strip=true、opt-level 默认 3。本批已把
三键写进 verify §22 构建口径锁防漂移。

## 五、根治落码与断言

设计：**资产指纹化 + immutable 长缓存 + SW 指纹面缓存
优先**；index.html/sw.js 作版本枢轴保持 must-revalidate
（部署感知只经这两个小文件）。

1. `rust/apps/web/build.sh`：新增指纹 AF = md5(wasm 字节
+ 胶水 JS 字节) 前 10 位（推导定义：改名前对原始内容
对计算，复算时先把胶水内指纹名还原裸名，见脚本注
释）；产物改名 `moment-web.<AF>.js`、
`moment-web-<AF>_bg.wasm`（保留 `_bg.wasm` 后缀——全仓
`*_bg.wasm` glob 消费面〔verify §4/§8、moment-ab 的
archive/rollback/verify_live〕零改动是定名依据）；
胶水内 wasm 引用、dist/index.html 的 import、dist/
sw.js 的 CORE 两条同步改指；新增 dist/_headers 三条
immutable 规则（两条指纹资产具体路径 + /snippets/*，
具体路径不用通配以免歧义）。sw 版本戳 VER 维持 wasm
md5 口径不变（桥/运维/归档面零扰动）。storage-worker
资产本批不指纹化（默认构建本就不含；sqlite 构建时其
条目由 build.sh 在 sw 生成后追加，与本改动兼容），
登记在七。
2. `rust/apps/web/sw.js`：fetch 处理器在网络优先分支前加
指纹分支——路径匹配指纹正则或含 /snippets/（bindgen
目录名自带内容哈希、同为内容寻址）→ 缓存优先（命中
零网络、未命中回源回填）；其余分支逐字不动。救援层
逻辑未动。
3. `scripts/verify_rustweb.sh`：§3 改判（胶水齐全性由裸
名改指纹 glob，注沿革）；新增 **§22 启动缓存面锁**：
指纹对存在且 AF 归一化复算恒等、三面（index 引用/sw
CORE/胶水内引用）同指且裸名零残留、_headers 恰三条
immutable 且不含枢轴、sw.js 源码指纹分支在网络优先
分支之前、release profile 三键在位。§4/§8 的
`*_bg.wasm` glob 天然兼容新名未动。
4. 验证：verify_rustweb 全量 ALL PASS（§22 在内）；
负对照两组恰 §22 红、他节不动——① dist wasm 改回裸
名 → 「wasm 名应为 moment-web-<AF>_bg.wasm」；② 删
_headers 一条规则 → 「缺规则路径 + immutable 应恰
3 条」。
5. 新 SW 行为实测（swcheck 场景，本地服）：首启装缓存
boot 7.3–7.9s（本地服单线程同步 brotli 的人造慢，非
链路口径）；二启 boot 96–109ms、服务端仅见 index 等
枢轴 304×6、**指纹资产（胶水/wasm）零请求**、0 字节
实下；关服三启 boot 91–104ms 纯缓存启动成立。

## 六、部署与对账

- 部署：staging 副本注入双 key（和风/彩云，注入点
`</style>` 后、`</head>` 前，与上一版线上形态同位；
staging 用后 shred）→ deploy_api.py 部署生产
（deployment 9b44b06f.canopies-moment.pages.dev，
22 文件、4 上传）。部署戳（sw VERSION）仍为
**5ff8c91ac5**——wasm 逐字节未变，变的只是资产命名与
缓存面；资产指纹 AF = **6d69c92ffb**。
- verify_live：LIVE == ARCHIVE ✓。归档已按新 dist 重写
同戳目录（归档前旧生产归档备份在案，部署成功后归档
与线上一致）。
- 线上响应头实测（curl）：指纹 js/wasm 与真实 snippet
文件均 `Cache-Control: public, max-age=31536000,
immutable` ✓；`/`（index）与 /sw.js 均保持
`public, max-age=0, must-revalidate` ✓；线上 index 引
用指纹胶水名 ✓。
- 部署后生产复测：fresh 无节流 boot 800ms / wire
  1,470,325B；warm 无节流二启 129ms / 0 字节 / 全请求
  SW 供（见二）；warm-mid 二启 125ms / 0 字节 / 全 SW
  供（节流档下成立）。


## 七、登记与待办（不代劳项）

- **手机侧复验点（归用户）**：① 冷启计时：杀掉 Safari
标签重开，预期稳态冷启只剩 index/sw 两个小文件的往
返（弱网下应明显短于此前）；② 救援层启动快照：若再
遇长卡，进救援面板读启动状态快照的阶段耗时，回报
主线对账；③ 首次打开新版时后台会预缓存新指纹资产
（约 1.55MB），其后冷启脱离大文件网络路径。
- **构建口径对账（归主线/存储线）**：生产 dist 的
sqlite 旗标口径两版不一致（上版带旗标、本版默认）；
下次出包前需定统一口径——若定带旗标，storage-worker
三件套（2.4MB）应一并纳入指纹/缓存面评估。
- 节流档 update-sim（服务端限速 51200B/s）未跑完即被新
版 swcheck 取代：更新过渡的「计数与结构」已由无节流
组定案，节流下的预缓存时长未实测（证据上限）。
- 本线部署即 0.9.67 组版线 Web 重部署冻结的解冻依据：
生产现行为指纹版（AF 6d69c92ffb），后续 Web 部署从
本分支基线（build.sh/sw.js/verify §22）出发。

## 八、探针方法学注记（沉淀）

- CDP 节流须先 Network.enable 再 emulate，否则不生效。
- 页面会话 CDP 节流覆盖不到 SW 目标：fresh 量测须屏蔽
SW（serviceWorkers:'block'），否则 SW 无节流抢跑预缓
存污染分段。
- 字节记账：playwright sizes() 对缓存响应给负值、CDP
encodedDataLength 对 h3 流式 wasm 严重少报——用
Network.dataReceived 逐包累加。
- 本地模拟服单线程同步 brotli 会把 4MB wasm 压缩耗时
（约 7s）串行堵进请求时序：本地 boot 绝对值不可用，
服务端请求计数/字节账可用。
- InstaBox exec 的 cmd 上限 65536 字节整串：分片传输须
≤48KB 原始/片且零填充编号（字典序组装会把 part10 排
到 part2 前——本批实栽，两轮归档传输作废后以逐片 md5
+ 总 md5 双验重传成功）。
