# 原生补齐调研：搜索匹配域（H18）与天气链（H17）

> 只读调研，2026-11-26。结论标注 proven（源码直读）/ inferred（由源码推断）/ unknown（未取证）。
> 对照基线：Web = `rust/apps/web`，core = `rust/crates/core`，storage/ffi = `rust/crates/{storage,ffi}`，原生 = `rust/apps/ios/app/MomentApp.swift`。

---

## 一、搜索匹配域（H18）

### 1.1 Web 口径（proven）

唯一入口：列表渲染时 `main.rs:1898` 对每篇备忘调 `list::matches_search(m, &q)` 过滤（查询在 `main.rs:1895` 先 `trim`）。`matches_search`（`list.rs:758-766`）：空查询恒真；否则把查询 `to_lowercase()` 后，对缓存好的小写检索文本做**整串子串 contains**（`list.rs:765`）——不分词、不拆空格，标点与空格都按字面参与。

检索文本由 `search_text`（`list.rs:773-860`）拼装，按 (id, updatedAt, title) 缓存（`list.rs:776-782`），字段来源逐项如下：

| # | 字段 | 口径 | 出处 |
|---|------|------|------|
| 1 | 备忘标题 `memo.title` | 全量收入 | `list.rs:783` |
| 2 | 正文行内文本 | 每个节点（含 children 递归）的 `text` 字段：段落/标题/待办/引用/列表项等一切行内文本，含 link 子节点的文字、imgTextCard 的 `node.text` | `walk_node` `list.rs:814-850`（`n.text` 在 816-818，children 递归在 845-849） |
| 3 | `attrs.text` | 装饰分割线（decorative_divider）的文字 | `list.rs:824-826` |
| 4 | `attrs.url` | 非 `data:` 开头才收：行内 link 节点的 URL、image 节点的 URL 等 | `list.rs:827-831` |
| 5 | `attrs.items[].url` | gallery 条目 URL，非 `data:` 才收 | `list.rs:832-840` |
| 6 | 卡片 `meta`（Value）内白名单键 | 递归遍历 meta 对象，键名（小写后）命中 `text/title/subtitle/source/name/label/alt/description/content` 的字符串值收入；另 `url` 键非 `data:` 时收入 | `walk_value` `list.rs:784-812`（白名单 800-802） |
| 7 | 跳过键 | `walk_value` 内键名命中 `id/fileid/dataurl/blob/thumb/imagedata` 的子树整段跳过 | `list.rs:791-795` |

由此确定的**匹配/不匹配**结论：

- **卡片 meta 的 title/subtitle/source 可搜**（proven，第 6 项）：搜歌名、歌手/作者（subtitle）、站点名（source）能命中 musicCard/linkCard，前提是卡片已解析出 meta。
- **meta 的 cover 不可搜**（proven）：`cover` 不在白名单内。
- **卡片节点顶层 `url` 不可搜**（proven）：musicCard/linkCard 的链接本体存在节点顶层 `url` 字段（`crates/core/src/model.rs:188`；写入点 `editor/cards.rs:193` `n.url = Some(url)`），而 `walk_node` 只收 `attrs.url`、不收 `n.url`。即「粘贴的音乐/网页链接本身」在 Web 搜索里**搜不到**；能搜到的 URL 只有行内链接、图片与 gallery 条目的 URL（第 4/5 项）。先前清单里「URL 子串匹配」的说法只对这三类成立，对卡片链接不成立。
- **附件文件名不可搜**（proven）：真实文件名只存在于备份 manifest 的 `attachments` 表，doc 节点本身不带 name（`blocks.rs:88-91` 注释明示，渲染侧查 `manifest_att_name` `blocks.rs:509`）；而 `matches_search` 签名只吃 `&Memo`、不吃 manifest（`list.rs:758`），故文件名不进检索文本。节点 `name` 兜底字段同样不被 `walk_node` 收集。
- **节点顶层 `title`/`caption` 不可搜**（proven）：`walk_node` 不收 `n.title`、`n.caption`。图文卡文本走 `node.text`（第 2 项）可搜；若存量卡只有 caption 无 text 则漏搜（inferred，属边缘形态）。
- **标签无独立匹配逻辑**（proven）：没有标签字段/索引，`#标签` 只是段落文本的一部分，随正文以普通子串命中（搜「旅行」与搜「#旅行」都能命中含 `#旅行` 的段落）。
- 字段间以单个空格 join 后整体小写（`list.rs:852`），故跨字段边界的查询串（如标题尾+正文首拼成的串）理论上可命中，属次要语义。

### 1.2 core plain_text 与原生/storage 口径（proven）

- core `Memo::plain_text()`（`crates/core/src/model.rs:248-250`）= 各节点 `Node::plain_text()`（`model.rs:232-243`）拼接：**只有 `text` 字段 + children 递归**，无分隔符；不含 attrs 任何键、不含 meta、不含标题（标题在 Memo 层单独存在）。
- storage 入库时把 `plain_text` 存入 `memos.plain_text` 列，并把 `(id, title, content=plain_text)` 写进 FTS5 trigram 虚表 `memos_fts`（`crates/storage/src/lib.rs:253-270`，表定义 131-132）。
- storage `search`（`crates/storage/src/lib.rs:345-371`）：查询 ≥3 字符走 FTS5 短语查询 `MATCH "\"q\""`（trigram 下等价子串）；<3 字符回退 `title LIKE %q% OR plain_text LIKE %q%` 并按置顶/更新排序。FTS 分支**无 ORDER BY**（注释称「顺序同列表」与实现不符，属既有小瑕疵，原生侧列表按自身排序呈现、影响不可见，inferred）。
- FFI `search_ids_json`（`crates/ffi/src/lib.rs:140-144`）直透 `store.search`；原生 `Library.search`（`MomentApp.swift:795-805`）只调它、结果存 `searchHits` 供列表过滤，无任何客户端补充。

### 1.3 差集（Web 有、原生无）

| 差集项 | 影响面 | 量级 |
|--------|--------|------|
| 卡片 meta 白名单字段（title/subtitle/source/name/label/alt/description/content，及 meta 内 url 若存在） | 搜歌名/歌手/站点名/链接标题在原生全部漏检——卡片类备忘在原生近乎「只能搜标题和正文」 | **主差集** |
| `attrs.url` 子串（行内 link URL、image URL）与 `attrs.items[].url`（gallery URL） | 搜域名/链接片段漏检 | 次差集 |
| `attrs.text`（装饰分割线文字） | 极小众块 | 可忽略级 |

反向差集（原生有、Web 无）：无实质项——原生的 title + plain_text 是 Web 检索文本的子集（Web 的第 1/2 项与之同集）。细微语义差（inferred）：FTS trigram 短语对含标点/空格的长查询存在 token 连续性要求，个别查询可能比 Web 的纯 contains 更严；LIKE 分支与 contains 等价。

### 1.4 原生补齐方案（proven 可行）

原生 `Library` 已全量加载备忘且每篇 `MemoItem.raw` 保存全量原 JSON（自查批 1 落地），客户端补齐不需要改 FFI/storage：

1. **做法**：`Library.search` 改为并集——FFI `searchIdsJson` 结果 ∪ 客户端补充扫描命中。补充扫描遍历 `memos`，对每篇用与 `search_text` 同口径的提取器（Swift 递归 walk `raw` 字典）拼小写文本、做 contains。或更简单：直接全量客户端扫描替代 FFI（备忘全量在内存、量级与 Web 列表同为数百篇级，Web 侧自证此量级子串扫描为毫秒级）；保留 FFI 路可在 FTS 命中之外只补差集字段（meta/attrs.url/items.url/attrs.text），扫描成本更低。二选一建议取**并集补差集**：改动面小、正文/标题仍走已验证的 FTS。
2. **提取口径必须逐项照抄** `walk_node`/`walk_value`（`list.rs:784-850`）：title + 节点 text/attrs.text/attrs.url（非 data:）/attrs.items[].url（非 data:）/meta 递归白名单键 + 跳过键集合；大小写与 trim 与现行一致（查询先 trim、两边 lowercase）。
3. **不要顺手扩围**：附件文件名、卡片顶层 url 在 Web 同样不可搜（1.1 已证），补齐目标是与 Web 等价，不是超过 Web；若日后要扩围应 Web/原生同改并先报用户。
4. 落地后在审计表 H18 标注：差集三项补齐、口径出处指向本节。

---

## 二、天气（H17）

### 2.1 Web 天气链全貌（proven，出处 `rust/apps/web/src/weather.rs`）

**数据结构**：`WeatherData { temp: i32, city: String, condition: String }`（`weather.rs:31-37`）。

**触发与缓存**：
- 列表可见时挂载后延迟 1500ms 拉一次，初值先取新鲜缓存（`main.rs:1421-1435`）；`fetch_weather` 内并发在飞去重（`weather.rs:166-186`）。
- 缓存：localStorage 键 `weather_cache`、版本 v6、TTL 30 分钟（`weather.rs:39-41`）；存 `{temp, city, condition, lat, lng, ts, v}`，版本不符或过期即弃（`weather.rs:49-73`）。缓存存城市原文，渲染时才经 `to_cn` 英转中（`weather.rs:404+` 的 CN_CITY 表）。

**定位链**（`fetch_weather_inner` `weather.rs:188-220`）：
1. 浏览器地理定位 `navigator.geolocation.getCurrentPosition`，5s 竞速超时、`enableHighAccuracy=false`、拒绝/超时/无 API → None（`weather.rs:119-137`）。
2. GPS 失败 → IP 兜底：`GET https://ipapi.co/json/`（4s 超时），取 `latitude/longitude` 作坐标，并拼 `city + region` 为 IP 城市（后续城市反查失败时回落，`weather.rs:192-215`）。
3. 双路皆败 → 整链熄火、Diag 记 `locate failed (gps + ip)`，天气行不渲染。

**数据源链**（先和风后彩云，`weather.rs:221-239`）：
- **key 门**：先读和风 key，**为空则整链不发请求**（彩云也不走，与单体原文同序，`weather.rs:221-228`）。
- **和风主链** `fetch_qweather`（`weather.rs:243-310`）：
  - 实况：`GET https://jq3dna235e.re.qweatherapi.com/v7/weather/now?location={lng},{lat}&key={key}`（4s 超时；该 host 是账号专属 API Host），校验 `code=="200"`，取 `now.text`（状况）与 `now.temp`（温度）。
  - 城市反查：`GET https://jq3dna235e.re.qweatherapi.com/geo/v2/city/lookup?location={lng},{lat}&key={key}`，取首个 location 的 `adm2 + name` 拼城市；失败/为空回落 IP 城市原文。
  - 成功写缓存，Diag 记 `provider=qweather`。
- **彩云兜底** `fetch_caiyun`（`weather.rs:368-401`）：和风链任一环失败才走。彩云 key 为空则跳过；端点 `GET https://api.caiyunapp.com/v2.6/{key}/{lng},{lat}/weather.jsonp?callback=MYCALLBACK`（JSONP 形态，fetch 取文本后剥 `MYCALLBACK(...)` 包裹，4s 超时）；校验 `status=="ok"`，取 `result.realtime.temperature`（按 JS Math.round 语义取整）与 `result.realtime.skycon`，skycon 经 22 项映射表转中文状况（`weather.rs:313-341`，未命中回原文）；城市只用 IP 城市（无反查）；成功同样写缓存，Diag 记 `provider=caiyun-fallback`。双失败记 `provider=fail`。
- **已知未闭环**（既有记录，unknown 现状）：彩云 key 免费配额曾耗尽（HTTP 429），真实兜底出数待配额恢复后以 Diag `provider=caiyun-fallback` 行为证。

**key 注入**（proven）：
- 运行时读 `window.__APP_CONFIG__.<field>`，次选 `window.MynoteConstants.<field>`，皆无 → 空串（`injected_key` `weather.rs:85-97`；字段 `QWEATHER_API_KEY` / `CAIYUN_API_KEY`，`weather.rs:99-108`）。
- 仓库内无 key 值：`index.html` 与源码全局 grep `__APP_CONFIG__` 只命中 weather.rs 的读取代码（本次实测）；生产构建在**部署环节**把含 key 的 `window.__APP_CONFIG__` 脚本块注入部署 staging 副本的 index.html，仓库与归档保持干净版（既有部署口径）。Web 的这套注入本质是「构建产物可被部署侧二次改写」——静态站点特有能力。

### 2.2 首页新建卡天气块呈现口径（proven）

- 位置：新建卡 `.list-item` 末尾追加（`list.rs:1505-1529` 的 `NewCard`，`weather_el` 在 1512-1527，挂载点 1558）；宽屏下排成方卡底部行（base.css last-child 规则，注释 `list.rs:1508-1510`）。
- 内容：`{temp}°`（`.weather-temp`，16px/650，审计表 H17 既有记录）+ 城市行 `.weather-city`（12px 次级）：城市先经 `to_cn` 英转中；拼接规则：condition 空 → 只城市；city 空 → 只 condition；都有 → `{city} {condition}`（`list.rs:1513-1521`）。
- **缺数形态**：`weather == None` 时整块不渲染（`weather.as_ref().map(...)`），无占位、无骨架、无错误提示——定位失败/无 key/双源失败在 UI 上完全无痕，只在 Diag 留行。

### 2.3 原生落地评估

原生现状（proven）：`MomentApp.swift` 全文无 weather/Weather/CLLocation 任何引用（本次 grep 计数 0）；`build-app2.sh` 生成的 Info.plist 无定位用途描述键。等于零起点。

**为什么不能照搬部署注入**（proven 机制 + inferred 结论）：
- Web 注入的前提是部署侧能改写已构建的静态文件（staging index.html）。ipa 是签名封包产物：构建后改包即破坏签名（全能签重签虽可再签，但把 key 塞进包内明文文件等于随包分发、任何人解包可读），且每次换 key 都要重新出包+重装，与 Web「部署时注入、仓库不落值」的安全模型完全不同。
- 两个 key 的性质：和风 key 绑定专属 API Host 且有配额、彩云 key 有免费配额上限——随 ipa 明文分发等于公开凭据（inferred 风险判定）。Web 端 key 同样对访客浏览器可见，但那是用户自用单站部署、暴露面与分发 app 不可同日而语（inferred）。

**可行存放选项**（供裁定，非结论）：
- A. 包内明文常量（最省事，凭据随包公开，与上条风险同在；用户自用、单设备侧载场景下风险实际量级低——但与项目「仓库不落凭据」红线冲突，至少不得进 git，需构建机本地文件注入且 gitignore）。
- B. 运行时用户自填（设置页加 key 输入项存 Keychain/UserDefaults）：凭据不出用户设备、最干净；代价是多一步配置、且偏离「打开就有」的 Web 体验。
- C. 经用户自有后端/Worker 代理转发（复用既有 `mynote.overtrees.workers.dev` 一类自有 Worker，key 存 Worker 环境变量）：凭据不落端侧；代价是要给 Worker 加天气转发端点并做基本防滥用（如固定路径+简单令牌），是三项里工程量最大的一项。

**定位形态**（iOS 平台口径，proven 平台事实）：
- CoreLocation 需 Info.plist 写 `NSLocationWhenInUseUsageDescription` 并在运行时请求 WhenInUse 授权；当前构建脚本手写 Info.plist，加键即可。
- Web 的「GPS 失败 → IP 定位兜底」在原生可原样保留（ipapi.co 同端点），且这条兜底让「不授权定位也能出天气」成立——授权被拒不等于熄火，与 Web 行为等价。
- 精度口径对齐 Web：低精度即可（`enableHighAccuracy=false` 对应 `kCLLocationAccuracyKilometer` 级），只取一次坐标。
- 城市英转中：Web 靠 CN_CITY 静态表（IP 城市为英文名时）。原生若用和风反查，城市直接是中文；IP 兜底路径仍需同表——该表在 `weather.rs:404-540`，可逐值移植或改走 CLGeocoder 反查（平台更优但结果口径与 Web 分叉，属「等价更优」判断题，列入裁定点）。

**呈现移植**：新建卡在原生 ListView 已有对应行（newCardRow），天气块按 2.2 口径在卡内右端/底部追加 `{temp}°` + `{城市} {状况}`，缺数整块不渲染；触发时机对齐 Web：列表出现后延迟拉取 + 30 分钟缓存（原生缓存落 UserDefaults 即可，键形自定义、属端内实现细节）。

### 2.4 分步落地建议

1. **先定 key 方案**（2.3 A/B/C，待用户裁定）——这一步不定，后面全是空转。
2. 数据层单文件落地（原生侧 `WeatherService`）：缓存（30 min）→ CoreLocation 一次定位（5s 超时）→ ipapi.co 兜底 → 和风 now + 城市反查 → 彩云兜底，Diag 行逐项照 Web 口径记 `provider=` 结果行；skycon 22 项映射与 Math.round 取整语义逐值移植。
3. 呈现：newCardRow 追加天气块，拼接/缺数口径照 2.2；城市表按裁定结果二选一（移植 CN_CITY 表 / CLGeocoder）。
4. Info.plist 加定位用途描述（文案需定稿，见裁定点）；授权请求时机对齐 Web 的「列表出现后」，被拒走 IP 兜底不打扰。
5. 真机验：有数/拒授权/断网三态 + Diag 行核对。

### 2.5 待用户裁定点清单

1. **key 存放方案**：A 包内注入（构建机本地、不入 git）/ B 设置页自填 / C 自有 Worker 代理。
2. **定位授权文案**：`NSLocationWhenInUseUsageDescription` 的定稿措辞（用途说明，如「用于在新建卡显示当地天气」）。
3. **城市名口径**：逐值移植 Web 的 CN_CITY 英转中表（与 Web 完全一致）还是用 CLGeocoder 系统反查（原生更优、结果可能与 Web 略有出入）。
4. **彩云兜底是否同批接入**：其 key 配额曾耗尽（M-4 未闭环），可先只接和风主链、彩云随配额恢复后补——或一次接全、靠 Diag 行观察。
5. 若选 A/C：和风专属 API Host（`jq3dna235e.re.qweatherapi.com`）继续沿用还是换公有 host（现 key 与该 host 绑定，换 host 需在和风控制台另配，属账号侧动作）。

---

## 附：本报告对先前口径的两处纠正

1. H18 先前记「Web 含附件名匹配」——**不成立**（1.1  proven）：附件文件名只在 manifest，Web 列表搜索不吃 manifest。
2. H18 先前记「Web 含 URL 子串匹配」——**部分成立**：仅行内 link/image 的 `attrs.url` 与 gallery `items[].url`（及 meta 内 url 键若存在）；卡片节点顶层 `url` 不在匹配域。
