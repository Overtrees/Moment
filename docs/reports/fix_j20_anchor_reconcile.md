# J20-12 红项对账收口（fix_j20_anchor_reconcile）

日期：2026-11-27。性质：组版（0.9.59）前清障——verify 断言锚与
DT 批（fix_dynamic_type_follow）改写面的同源对账。本批零 Swift
落码，只动 verify_ios.sh 的 J20-12 一处 hunk；未提交、未 bump。

## 一、判定结论：(a) 期望合法变更——改锚，非代码修复

J20-12 红的构成：断言第二子句锚 `* baseSize - markerW`，现行
源码（MomentApp.swift MdBlockView 的 List 支）为
`* scaledBase - markerW`，字面失配。判定为 DT 批设计内后果、
断言漏网，证据链四条：

1. **DT 批定案在册**：fix_dynamic_type_follow.md §2 逐面三态表
   「MD 渲染链」行明载——「列表标记 em 账基字改工厂缩放值
   scaledBase（此前 marker 字/markerW/文起点用未缩放 baseSize、
   与已缩放正文脱档）」。文起点改走 scaledBase 是该批的明确
   设计决定，不是无声漂移。
2. **源码自带设计注**：MomentApp.swift:13651-13658 注释逐字
   同口径（em 账基字与同行正文同档、默认档逐值不变）。
3. **DT 批自以为已同步**：其 §5 记录「DT36-4 锚改判：
   baseSize * 1.125 → scaledBase * 1.125」，且 DT36-4 的
   verify 注释写有「间距账 J20-12 同步」——但实际只改了
   DT36-4 自身的锚，J20-12 的第二子句从未动。属同源改锚的
   漏网兄弟锚，与 E1 的 B25-E3-1 跨批对账同型。
4. **默认档逐值等价成立**（账见 §二）——若不等价应判 (b)，
   本例等价，故不触碰 DT 批落点代码。

## 二、默认档等价账（新公式构成）

现行公式（MdBlockView List 支，非任务项）：

- 基字：`scaledBase = FontFactory.scaledSize(baseSize, style: .body)`
  ——UIFontMetrics(.body).scaledValue 以 FontHub 类别显式计算。
  默认档（Large）下 UIFontMetrics 恒等回基值（缩放表以 Large
  为定义基准），故 **scaledBase ≡ baseSize**。
- 标记框：`markerW = scaledBase × 1.125` → 默认档 ≡ baseSize ×
  1.125；baseSize 16 时 = 18，与旧定值逐值相同。
- 非任务支间距：`max(0, (ordered ? 1.4 : 1.2) × scaledBase − markerW)`。
  em ∈ {1.2, 1.4} 恒 > 1.125，正基字下 max 钳永不触发 →
  **文起点 = markerW + 间距 = em × scaledBase**；默认档即
  em × baseSize，与 J20-12 自始所锁不变量逐值等价。基字 16
  实数：markerW 18、间距 ul 1.2 / ol 4.4（与源码注一致）。
- 任务支 spacing 8 未动。
- 同档性：同行正文 `Marks.dynFont(size: baseSize)` 委托
  FontFactory.uiFont、默认 style 同为 .body——标记字
  （`.system(size: scaledBase)`）、markerW、文起点与正文共用
  同一张 .body 缩放表，非默认档下同涨同缩，正是 DT 批要根治
  的「脱档」的反面。非默认档文起点随类别缩放属设计行为，
  不是回归。

## 三、改锚清单（verify_ios.sh，仅 J20-12 一处 hunk）

- 第二子句：`has '* baseSize - markerW'` → `has '* scaledBase - markerW'`。
- 新增第三子句：`has 'let scaledBase = FontFactory.scaledSize('`
  ——该定义点全文件恰一处（MomentApp.swift:13659）、此前无任何
  断言锁定；J20-12 的不变量现依赖此定义，改锚须自足，防定义
  被无声改写后公式锚空转。
- 第一子句 `(ordered ? 1.4 : 1.2)` 不动。
- 注释块续写改判沿革：注明出处（fix_dynamic_type_follow §2
  定案 / §5 DT36-4 同源改锚 / 本对账报告）、新公式构成账与
  默认档等价账（§二摘要）、不变量改锁口径（文起点 = em ×
  与正文同档的缩放基字）。原 impl_dt_layout_resilience 改判
  注保留——沿革不断链。

## 四、全量扫锚（DT 改写面：ListBlock/MdBlock markerW、indent、文起点）

方法：对 verify_ios.sh 全文 grep `baseSize` / `markerW` /
`scaledBase` / `indent` / `1.125` / `dynFont` / `FontFactory` /
`scaledSize`，逐个命中核对；再以全量实跑结果交叉验证（除
J20-12 外全绿即其余锚对现行源码全部成立）。逐条登记：

| 锚 | 引用面 | 核对结论 |
|---|---|---|
| J20-12 | MD 列表文起点公式 | **失配 → 本批改锚**（§三） |
| DT36-4 | `scaledBase * 1.125` 恰 1、`frame(width: markerW` 恰 2、`frame(width: 18,` = 0、编辑 ListBlock 段 `frame(width: 20` = 0 + `indentOrdered` 在位 | DT 批已同源改锚；本批复核四子句对现行源码全成立，**不动**（改锚前实跑 ✓） |
| DT46-6 | FontHub 观察三点 + 工厂构建登记 22 + dynFont 委托 | 与改写面相邻（工厂接线）；实跑 ✓，期望仍成立，**不动** |
| DT36-1 注释内提及 | 仅注释沿革文字 | 非断言条件，不核 |
| 其余各组 | 不引用改写面符号/公式 | 全量实跑交叉验证全 ✓ |

结论：改写面内失配锚仅 J20-12 一条，无第二漏网。

## 五、自检

- 全量 verify：改锚前 430 ✓ / 3 ✗（ipa 陈旧、产物语言包、
  J20-12）；改锚后 431 ✓ / 2 ✗（仅产物陈旧两项）；收尾复跑
  435 ✓ / 2 ✗（期间页眉消失批落定自带 +4 ✓，红集不变）。
  **组版门达成：除产物陈旧两红（tree 构建自解）外零红。**
- 类型检查（本批零 Swift 改动，仍按要求跑相关 primary 遍，
  源码快照法避撕裂读）：
  - 首跑（工作树直读）：20 条幻影 error（作用域解析级联、
  均不在本批锚面），系本机内存受压 + 兄弟批在途撕裂读，
  与既往各批同型留痕，不作数。
  - 快照复跑：收敛至 2 条真实 error——`ScrollOffsetSanitizer`
    未定义（MomentApp.swift:17369/17465），系页眉消失批
    （fix_home_header_vanish）刚开工的半落定状态，非本批面。
  - 该批定义（同文件 17548 行）落入后重快照复跑：
    **MomentApp primary 遍 exit 0、零 error、.o 产出
    （14,988,488 B）；MomentFontFactory primary 遍 exit 0、
    零 error、.o 产出**。本批锚面（MdBlock List 支）在三轮
    中零 error。
- 同树纪律：动工前 git 状态快照在案；本批仅 verify_ios.sh
  J20-12 一处 hunk（注释续写 + 两子句），完工复读该段确认
  无损，他批 hunk（B25-E3-1 改锚、GRIDH30 改锚、B38-6 键数
  注等）完好。

## 六、终判点

无真机终判项：本批只改断言锚、不改任何运行行为；默认档
渲染逐值等价（§二），缩放档行为即 DT 批已交付的终判面
（fix_dynamic_type_follow.md §6 清单）覆盖，不重复列。
