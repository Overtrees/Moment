# 确诊报告（第二轮）：普通 Safari 列表在、滚动活、点击全死、无痕正常

日期：2026-11-24 晚。对象：生产构建 eb09ed0e08（第七轮）。第一轮结论见链尾回报（四路复现皆绿）。

## 症状定型（用户证据）

- 普通 Safari：彻底关标签 + 后台划掉重开，问题依旧 → 僵尸视图假设排除，成因必在普通 profile 的**持久化状态**。
- 页面**可滚动**、点击全无反应 → 不是全屏拦截层（会连滚动一起挡）、不是主线程死锁。
- 天气定位允许提示未跳出（无痕下正常出现）→ 死亡时点大概率在列表挂载效应链早期（天气 GPS 步在挂载后 1500ms，之前有：数据加载链、首帧渲染、封面 BlobMedia/imgsize 回填）。
- 形态学最吻合：panic=abort 冻屏（首帧已渲染、wasm 事件系统已死），或首手势 handler 内 panic。

## 本轮实证（box，8096 = 与生产逐字节一致的 eb09ed0e08）

方法：新 profile 首启 → 注入毒化状态（localStorage / IDB）→ reload → 分阶段判活（点头部进设置 / 点首卡进编辑器 / 手势全串），全程采集 pageerror、console error 与 Diag 尾行（含 ERR 行）。

### 面 1：localStorage 逐键毒化（Chromium，26/26 全过、零 panic）

| 键 | 毒化形态 | 结果 |
|---|---|---|
| weather_cache | 原版 v6 形态（对照）、temp 字符串、ts 字符串、缺 ts、city 20 万字 | 全过；静态审计 cached() 全防御（版本/类型/ TTL 逐项 Option 化） |
| mynote_imgsize_v1 | 坏 JSON、值类型错位（字符串/对象/负数/零）、2000 条超 cap | 全过；serde 整表失败即空表自愈 |
| mynote_pending_input_v1 | 坏 JSON、值非字符串（数字/null/对象） | 全过（坏格式整键作废口径） |
| mynote_diag_v1 | 坏 JSON、对象非数组、300 行×5KB | 全过 |
| mynote_lang + mynote_pack_* | 旧包删 20% 键、值非字符串、不存在的语言码 | 全过（缺键回退内嵌 zh-CN；坏码仅 404 资源错误、功能正常） |
| memos_slash_recent_v1 | 对象非数组、数字/null/对象混入、5000 条 | 全过 |
| sj_fontsize | '16px'、'99999'、空串 | 全过（match 兜底 medium） |
| mynote_backup_history | 坏 JSON、对象 | 全过（设置页读取面亦防御） |
| mynote_hint_editor_v1 / mynote_stock_mig_v1 | 预置 / 摘除（D3 在种子上真跑） | 全过 |

原版同名键的写入形态均已从原版源码 src/ 查实（weather.js 的 `{temp,city,condition,lat,lng,ts,v:6}`、storage.local.js、sj_* 等），毒化按原版形态 + 类型错位 + 截断 + 超大四类构造。

### 面 2：IDB 数据形态（Chromium 9 例 + WebKit 5 例，全过）

- **全块形备忘**（fixtures/allblocks.zip：23 块含 musicCard/link-card/gallery 双形态/imgTextCard/Callout/代码段 + 4 真实附件含 637KB 图）：列表渲染、点开编辑器、返回，全过。
- **kitchen sink**（全块形 + 最毒 LS 组合）：全过。
- **deletedAt 变体**（字符串/浮点/负数/i64 溢出邻域/布尔/对象）：全过——超大值被「撤销窗口已过」口径正常真删（Diag 有行），余者按未标记处理。
- **layout 变体**（字符串/怪 mode/越界 boundary/幽灵锚 bid/缺失 id 名单）：列表与编辑器均正常。
- **巨型备忘**（2000 块混合）：正常。
- **D3 旧形态电池**（迁移标记缺失下：数字 id、毫秒时间戳、顶层 fileId/level/checked、strike 别名、music/code 旧名块、gallery 字符串 items）：迁移真跑、Diag 落 MIGRATE 与 persisted state applied、点按正常。
- **manifest_raw 垃圾串**：正常（类型查表失败即回退字节判读）。
- **memos_json 截断**：走 P-U2 设计的可见失败态（⚠️ 加载失败 + 重载入口），Diag 落 `empty state shown: load-error`——**与用户症状不符**（用户能看到列表），可排除「其数据整体解析失败」。
- **pending_input 真实 bid 三连**（1000 层嵌套列表 HTML、100 万字文本、500 层嵌套行内标签）：恢复链全过（apply_sync_map → editor_html_to_inlines 递归面实测不崩）。

### 面 3：首手势全串（全块形数据，Chromium）

tap 开编辑器 ✓ → 编辑器内点块 ✓ → 返回 ✓ → 鼠标 pointerdown→move→up 全串 ✓ → 左滑全串 ✓ → 触摸长按 850ms ✓ → 第二下 tap ✓。全程 pageerror 零。首手势 panic 面未命中。

### 面 4：sw.js 时序审计（逐行，构造性证明）

现行策略：install addAll(CORE)→skipWaiting；activate 删异代缓存→clients.claim；navigate/js/wasm/html 网络优先、失败回缓存（caches.match 跨全部缓存）。

轮换窗口内全部 (index, js, wasm) 组合的失败形态：

| 组合 | 形态 |
|---|---|
| 全网络新版 / 全同代缓存 | 健康 |
| 新 js + 旧 wasm | LinkError → 卡启动页/白屏 |
| 旧 js + 新 wasm | TypeError（导出缺失）→ 白屏 |
| activate 删缓存与在飞请求竞态 | 资源失败 → 卡启动页 |

**没有任何组合能产生「列表已渲染 + 事件全死」**：渲染成功即证明 js/wasm 同代且模块完整引导；引导完成后 SW 不再参与事件通路。混版形态与症状不符（与第一轮强制混版实测一致）。

### 效应链时序审计（静态，补充实证）

天气（挂载后 1500ms）之前跑的效应：① 数据加载链（IDB 读 → BackupFile 解析 → D3 迁移 → recover_pending_input 逐篇 → 待删 retain/再水化 → data.set）——解析边界全部 Option/Result 化，毒化实测覆盖；② 首帧后渲染（build_groups / section_label / has_image / cover_source / CoverImg 异步取字节）——逐函数审毕，无 unwrap/索引越界（build_groups 唯一 unwrap 在刚 push 之后、恒成立）；③ init_lang / font_size / Diag 节流落盘——全防御。静态与实证互相印证：**应用代码内未找到可被存量状态打穿的 panic 点**。

## 未能复现的腿（unknown，如实登记）

桌面 Chromium/WebKit 均构造不出 iOS Safari 本体与其存储分区的行为：

1. iOS SW 进程在内存压力下被杀于 activate 中途、skipWaiting/claim 的 iOS 特有竞态——即便如此，按面 4 组合学其降级形态仍应是卡启动页而非冻屏，解释力弱。
2. 内容拦截器（2026-11-20 同型事件的未隔离嫌疑，当时亦无痕正常、常规异常、后自愈）：拦截器作用于常规模式存量规则集；iOS 上其与 SW/缓存的交互面桌面不可复现。
3. 主屏幕 PWA 容器与 Safari 常规容器是两个存储分区——用户称常规 Safari 亦坏，若两处同坏，共同因更指向「被服务的更新通路本身在 iOS 上的状态」或拦截器，而非单一容器的数据。
4. iOS 的页面生命周期/会话恢复把已序列化 DOM 以死 JS 形态还魂的边缘情形。

结论：**新构建在一切可构造的状态面下健康；故障成因未定（unknown），剩余嫌疑集中于 iOS 客户端环境面。** 按红线不猜修、不回滚（回滚不清除客户端状态，且旧构建在同一容器上要经过同一套 SW/存储通路）。

## 救援部署方案设计（未执行，待用户拍板）

目标：下次同类冻屏时，用户能**自助恢复**且**把证据送出来**——本轮调查最大的堵点是应用死了之后 Diag 读不出来（设置页进不去）。方案全部落在 index.html 内联层（先于 wasm 执行、不依赖应用存活）：

1. **状态快照（每次加载自动）**：内联脚本采集并写入 localStorage 新键 `mynote_rescue_log_v1`（环形 20 条）：SW 注册表（scriptURL/状态）、Cache Storage 键名清单、indexedDB.databases() 清单、localStorage 键名 + 字节数清单（**只记键名与大小、绝不记值**）、UA 与时间戳。
2. **救援入口（双通道）**：
   - URL 通道：`?rescue=1` 打开即显示救援面板（可由支持方直接发链接）；
   - 看门狗通道：加载后 12s 内未见「应用已活」标记（应用侧加一行：数据应用完成且首帧渲染后写 localStorage `mynote_boot_ok` = 构建戳 + 时间；或启动页 12s 未消失），底部出现可关的小条「应用似乎没有响应 — 点此修复（不影响笔记）」。
3. **面板三动作**（纯 DOM/JS，应用死了也能点）：
   - **导出诊断**：把 mynote_diag_v1 全文 + 状态快照打包下载为文件——冻屏现场的 Diag 从此可达；
   - **修复启动（保留全部笔记）**：`serviceWorker.getRegistrations()` 全部 unregister + `caches.keys()` 全部删除 → 记一条救援日志 → `location.replace` 无参重载（新 SW 重新安装、缓存自网络重建）。**明确不动**：IndexedDB（备忘与附件本体）、localStorage 全部键（含 Diag）、OPFS（Rust 版未用）；
   - 关闭面板。
4. **回执**：下次应用成功启动时读 `mynote_rescue_log_v1` 折入 Diag（RESCUE 行），救援是否生效有据可查。
5. **诚实边界**：若真因在 IDB/LS 数据本体，此复位无效——面板文案明示下一级阶梯（先经面板导出诊断与备份，再谈清站点数据；清数据 = 笔记全失，绝不做成一键按钮）。
6. **配套建议（独立小笔）**：本轮毒化电池（poison.mjs / poison2b.mjs / poison_wk.mjs，位于 box /workspace/pwtest）与第一轮升级复现脚本转正为常驻探针 `probe_state_resilience` 登记 run_all_tests，防止未来批次把某个状态面改脆。

## 附：本轮产物

- box /workspace/pwtest/poison.mjs（LS 26 例）、poison2.mjs / poison2b.mjs（IDB 17 例）、poison3.mjs（手势串）、poison_wk.mjs（WebKit 5 例）；原始输出 /tmp/poison_out.jsonl、/tmp/poison2_out.jsonl、/tmp/poison2b_out.jsonl、/tmp/poison3_out.json、/tmp/poison_wk_out.jsonl（box /tmp，易失）。
- 本机代码与生产零改动；未回滚、未部署。
