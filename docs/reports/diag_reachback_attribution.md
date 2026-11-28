# Diag 回溯窗口异常定案（2026-11-28）

## 异常事实

0.9.64 真机桥自办补读时发现：经桥 diag_search / diag_tail（beforeTs
分页）只能回溯到当日 12:05:22 CST 为止；更早的行（今晨 0.9.63 时段
补读行、本轮 11:5x–12:0x 的 undo/drag 场景 run 行）分页回 0、不可
达。bootSessionId 全程未变（排除重启分段）；app 0.9.64/build 91。

## 定案（proven）

**根因 = Diag 当天缓冲是 300 行环形缓冲，写满后静默丢最旧行；所
有读路径共读这一份缓冲，被挤出的行从一切路径永久不可达。属设计
内容量滚动，非分页/游标缺陷。**

代码位置：

- `MomentApp.swift:5356` `DiagLog.appendEntry`——入环后
  `if today.count > 300 { today.removeFirst(today.count - 300) }`
  （5363–5364 行），超限即丢最旧，且**不留任何痕迹行**。
- 存储形态：`today` 内存数组 + `today.json` 落盘（persistToday 写
  的就是裁剪后的数组，5260 行）；归档 `archives.json` 只在跨日冻
  结时整日转入（loadIfNeeded 5157 行 / freezeToday）。日内被挤出
  的行不进归档、无任何副本。
- 读路径同源：桥 diag_tail（MomentBridgeTools.swift:741）与
  diag_search（:777）都经 scopedEntries（:709）读
  `DiagLog.shared.today`；Diag 页与导出同读此数组。故 tail 与
  search 两路同根（候选④坐实为同一根因，不是两个缺陷）。
- 容量口径来源：Web diag.rs 文件头明载「内存环形缓冲（上限 300
  行）」、`const CAP: usize = 300`，原生 300 上限于 0.9.39 批 F
  （G10）随归档机制一并对齐引入——跨端一致的设计口径，非回归。

## 候选逐项判读

- ① 容量滚动挤出：**坐实（proven，机制面）**。构造性复刻（按
  appendEntry + diagTail 原逻辑以脚本重演：稀疏晨间行 + 11:50 起
  场景爆发写入）结果：环恒为 300 行、晨间行全部挤出、保留窗口最
  旧行即环界——与真机「12:05:22 硬墙」同形。
- ② 分页游标在段/文件边界断裂：**排除（proven）**。today 作用域
  是单个扁平数组，无段/文件边界可断；复刻显示分页（limit 50 ×
  6 页）可无损走完保留集全部 300 行、不重不漏；向环界以下翻页
  回空数组，正是「数据已不在保留集」的正确表现，非游标故障。
- ③ beforeTs 比较口径：**排除（proven）**。单位一致（entryDict
  出 ms、过滤以 `ts * 1000 < before` 比）；`nextBeforeTs` = 本页
  最旧返回行 ts、严格小于是正确的游标语义。附带一条次要观察
  （inferred，与本异常无关）：同毫秒内的两行，nextBeforeTs 指向
  已返回行的毫秒时，未返回的同毫秒兄弟行会被严格小于吞掉——影
  响面至多同毫秒行，本异常缺口以分钟计，不构成解释。
- 字节守卫（maxDiagBytes 256KB，MomentBridgeProtocol.swift:20）：
  只裁响应包并在裁时回 nextBeforeTs，不动存储，与本异常无关。

## 12:05:22 边界的吻合度（inferred，强）

保留集最旧行 = 环界。当日 11:5x–12:0x 正是场景 run 密集窗口
（undo/drag 场景逐 step 记行 + 桥流量行），数分钟内写入 ≥300 行
即可把当日更早的行整体挤出；12:0x 补读时环界落在 12:05:22 与此
完全吻合。bootSessionId 未变与日内挤出相容（挤出不需重启）。
定量等式（补读时刻保留集恰为 300 行）因真机数据已不可达无法复
验，按 inferred 登记，不升级表述。

## 处置

按工单口径：定案为容量滚动属设计内——**本单不落码、不擅自扩
容改策略**，以下两项登记待用户裁：

1. **容量账与扩容选项**：现口径 300 行/日环。平日够用，但桥场
   景连跑日会在数分钟内烧穿。选项：(a) 双端同步扩容（如 2000
   行）——Web CAP=300 是源口径，改动须双端同改并过 i18n/对齐
   账；(b) 维持容量、给环裁剪加留痕（归档截断与自动删除都有
   G10 留痕行，唯独当天环裁剪静默，是本机制唯一的信息缺口；
   留痕行自身占环位，爆发日会高频触发，宜用进程级 logOnce
   形态）；(c) 维持现状。
2. **场景证据口径建议（建议采纳，与容量裁定无关）**：桥场景证
   据不依赖 Diag 事后回读——场景 run 的 step 证据以 run 回包本
   体为准；Diag 回读只作同窗口补充，其有效窗口在爆发日只有
   「最近 300 行 / 分钟级」。确需 Diag 佐证的补读须紧跟该 run
   之后、在下一 run 之前完成。本次异常正是 12:0x 补读回够
   11:5x 的 run、中间已隔数个 run 的必然结果。

## 证据清单

- MomentApp.swift:5099–5428（DiagLog 全实现通读）、5356–5368
  （appendEntry 环裁剪）、5157–5210（loadIfNeeded 冻结）、
  5260（persistToday）。
- MomentBridgeTools.swift:700–855（entryDict/scopedEntries/
  byteGuard/diagTail/diagSearch 通读）。
- rust/apps/web/src/diag.rs:1–25（Web 300 环口径源头）。
- git log -L：300 上限引入笔 446f29b（0.9.39 批 F）。
- 构造性复刻脚本（一次性，结论已录上文②①，未入仓）。
