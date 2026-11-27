# probe_batch3 C-11/C-12 竞速修复（只动探针）

- 日期：2026-11-27。定性与修法出处：triage_probe_batch3_c11_c12.md（探针断言建在活网补拉返回值上、与约 0.4s 的 hydrate 翻卡竞速，proven）。
- 运行场：tree（/opt/work/Moment，dist 为 Web 兼容批构建），tree Chromium 口径。

## 落点（仅 tests/probe_batch3.mjs，两处）

1. **全程路由拦截**：`browser.newContext` 之后、任何页面打开之前加
   `await ctx.route('**://mynote.overtrees.workers.dev/**', (r) => r.abort())`。
   在打开 b3-link 前已生效且全程有效（triage 已证全探针无其他断言依赖该 Worker：夹具无 musicCard、其余段不触发卡片解析）。拦截后 lc-err/lc-load 的补拉经「resolve -> error」确定落定。
2. **防再犯纪律入文件头注释**：「凡断言涉及线上异步补拉（hydrate）的卡面状态，必须先拦截外部元数据源使状态确定化」，并注明本探针的拦截点与适用依据；拦截行处另有就近注释指向该纪律。

断言口径零改动：C-11 仍断 err 呈现与无 scheme 标题回退完整 URL，C-12 仍断无骨架 + 落 err 卡，未放宽任何期望值。

## 复跑结果（tree，两轮连跑）

| 轮次 | 日志 | 结果 |
|---|---|---|
| 第 1 轮 | tree `/data/home/probe_batch3_fix_r1.log` | **ALL PASS**（41 ✓ / 0 FAIL） |
| 第 2 轮 | tree `/data/home/probe_batch3_fix_r2.log` | **ALL PASS**（41 ✓ / 0 FAIL） |

关键行（两轮同值）：

```
✓ C-11 err 无 scheme 标题 = 完整 URL {"tag":"DIV","title":"example.com/path"}
✓ C-12 无 loading 骨架态（落 err 卡） {"skeleton":false,"errCard":true}
```

其余 39 条断言（C-28/C-21/C-27/C-23/D-17/C-14/C-15/C-10/C-03/C-04/C-05/MD-C10）两轮全绿、零回潮。连跑两轮全绿，非偶绿，收口。

## 纪律核对

- 未碰 App/Web 源码；本地 diff 仅 tests/probe_batch3.mjs 一文件两 hunk（文件头注释 + ctx.route 一行）。
- 修改件经分片传输推 tree 并 md5 对账一致（24,335 B，md5 0439299d…）后复跑；跑完已停 tree 上临时起的 :8096 静态服务。
- 未提交，随组版分拣归测试文件笔。
