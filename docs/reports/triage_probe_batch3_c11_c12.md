# probe_batch3 C-11/C-12 两红 triage（只定性，未落码）

- 日期：2026-11-27。出处：impl_web_block_compat.md W4 节（probe_batch3 在 tree 两红、A/B 已证非该批引入、原因未定，派本 triage）。
- 运行场：tree（/opt/work/Moment，dist 为 Web 兼容批 09:50 构建），tree Chromium 口径。

## 结论（先行）

**探针/夹具口径问题（proven），非 Web 端缺陷（proven），亦非 tree 环境故障——tree 的网络恰恰是「太通」。**

两条断言假设夹具卡的 err 态是静态的，但夹具卡按设计会在打开编辑器时触发 hydrate 补拉，向**线上真实元数据 Worker** 发请求；Worker 对两个夹具 URL 都返回带非空 title 的 200 响应，两卡在打开后约 0.4s 内先后翻成 ready 卡。探针在固定 800ms 后断言 err 态，与设计内的异步补拉竞速、在 tree 上必输。err 渲染逻辑本身正确（见下 B 组对照实证）。

## 复现证据

### 1. tree 复跑 probe_batch3（原文行）

全探针其余断言全绿，仅此两红，与兼容批报告一致：

```
✗ FAIL C-11 err 无 scheme 标题 = 完整 URL null
✗ FAIL C-12 无 loading 骨架态（落 err 卡） {"skeleton":false,"errCard":false}
```

即：lc-err 块内 `.link-card-err` 不存在（err=null）；lc-load 块内无骨架（符合预期）但也无 err 卡。

### 2. 元数据 Worker 对两夹具 URL 的实际返回（tree 与本机 curl 一致）

`GET https://mynote.overtrees.workers.dev/meta?url=<url>`，响应头含 `Access-Control-Allow-Origin: *`（浏览器 fetch 可读）：

| 夹具 URL | HTTP | 返回 title |
|---|---|---|
| `example.com/path`（lc-err） | 200（0.64–0.93s） | `未命名页面`（上游 404 时的回退标题） |
| `https://example.com`（lc-load） | 200（0.09–0.33s） | `Example Domain` |

两条 title 均非空 → 按解析口径（有 title=ready）两卡必翻 ready。

### 3. A/B 对照探针（同夹具同导入流，仅保留 b3-link 一篇）

**A 组（活网）状态变迁轮询：**

```
A t=13ms  lc-err={err:true, title:"example.com/path"}  lc-load={err:true, title:"example.com"}
A t=417ms lc-err={ready:true, title:"未命名页面"}        lc-load={ready:true, title:"Example Domain"}
```

初始帧两卡都是 err 态且 lc-err 标题恰为探针期望的完整 URL；约 0.4s 后补拉返回、双双翻 ready。探针的断言点（打开后 ≥800ms）稳定落在翻转之后。

**B 组（ctx.route 拦截 `mynote.overtrees.workers.dev` 全部请求）：**

```
B final: lc-err={err:true, title:"example.com/path"}  lc-load={err:true, skeleton:false}
B CARD diag: "CARD resolve lc-err -> error" / "CARD resolve lc-load -> error"
```

拦截后两条断言的期望**全数满足**，且 Diag 证明解析路径确实跑过、因 fetch 失败落 error 态。

## 机制链（源码定位）

1. 触发：`rust/apps/web/src/editor/hooks/cards_fx.rs` `use_card_hydrate`——打开备忘时，link-card 有 url 且（无标题 meta 或 status=loading）即逐张 `spawn_resolve_card`（原版 hydrate 口径）。夹具 lc-err（meta=null）与 lc-load（status=loading、meta=null）双双命中；lc-ready（有 title）、lc-blocked（有 title）不命中——与探针中该两条 C-11 断言全绿互证。
2. 解析：`rust/apps/web/src/editor/cards.rs` `spawn_resolve_card` → `fetch_link_meta`（GET Worker `/meta?url=`，非 2xx/解析失败=None）；回写口径：meta 有非空 title → status=ready 并回填 meta，否则 meta=Null、status=error。
3. 渲染：`rust/apps/web/src/blocks.rs` link-card 分支（约 1244–1280 行）——title 为空才渲染 `.link-card-err`，err 标题 = `host_of(url)`、host 为空回退完整 URL；`host_of` 对无 scheme URL 返回空串（约 203–214 行），故 lc-err 的 err 标题恒为 `example.com/path`。C-12 的「无骨架」口径同分支（loading 骨架渲染分支已删，status 不参与渲染）。**渲染逻辑与两条断言的期望逐字一致，B 组已实证其产出正确。**

## 定性分级

| 候选 | 结论 | 依据 |
|---|---|---|
| Web 端真缺陷（err 呈现逻辑） | **排除（proven）** | B 组拦截后 err 卡/标题/无骨架全数达标；A 组初始帧同；源码口径与断言期望逐字一致 |
| tree 环境故障（网络不可达/字体/时序基建） | **排除（proven）** | 失败方向与不可达相反：正因 tree 到 Worker 链路快（约 0.4s 落定）才翻卡；其余 40+ 断言同场全绿 |
| 探针/夹具口径（状态非确定） | **成立（proven）** | 夹具把 err 态断言建在活网外部服务（Worker + 其上游 example.com）的返回值上；结果随宿主网络可达性/延迟变：慢或不通则绿、快则红。与兼容批 A/B（批前同值同红）互证：此红与被测代码版本无关，只与运行环境网络有关 |

附带观察（inferred，不在本 triage 裁定范围）：Worker 对上游 404 页面回退 title `未命名页面`，使一张「抓不到元数据」的卡在产品里也会翻成 ready 卡（标题=未命名页面）。这是 Worker 侧的产品口径问题、与本两红无因果（两红的根源是探针断言非确定态），如需处置应另立 Worker 批评估，不建议混入探针修复批。

## 建议处置（不落码，待主线派修）

- **修探针，不修 App**：在 probe_batch3 中对元数据 Worker 域名做路由拦截使夹具状态确定化——`ctx.route('**://mynote.overtrees.workers.dev/**', r => r.abort())`，在打开 b3-link 之前生效即可；保守起见可全程拦截（全探针无其他断言依赖该 Worker：夹具无 musicCard、其余段不触发卡片解析）。拦截后 err 态由「resolve -> error」确定落定（B 组已实证），两断言恢复确定性，且仍真实覆盖 hydrate 失败路径与 err 渲染面。
- 不建议改夹具 URL 求「天然失败」：Worker 对 404/DNS 失败等的回退行为未经全量验证（如 404 已实证回退标题），换 URL 仍可能非确定；路由拦截是唯一与 Worker 行为无关的确定化手段。
- 不建议把断言改到「打开瞬间」抢跑补拉：与 0.4s 量级的网络落定竞速，本质仍是时序赌博，换慢机器即翻。
- 修复后回归口径：probe_batch3 在 tree 应 ALL PASS；同时保留一条活网冒烟认知——link-card 打开补拉翻 ready 本身是设计行为，已有 CARD Diag 行与本报告 A 组记录为据，无需在 batch3 内重复断言。

## 证据留存

- tree 复跑日志：tree `/data/home/probe_batch3_triage.log`；A/B 对照日志：tree `/data/home/probe_triage_c11.log`（对照探针脚本为临时件，跑后已删除、未入仓；复现方法即本报告第 3 节所述拦截与轮询）。
- 本 triage 未改任何源码/探针/dist；tree 上临时起的 :8096 服务已停。
