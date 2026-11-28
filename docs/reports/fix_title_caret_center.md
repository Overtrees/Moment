# 标题 caret 环根治：空编辑态插入点落占位行缘、偏离中心 23.2

## 一、症状与设备实证（0.9.67 桥自办，proven）

五修（字形环，fix_title_glyph_center）装机后，title_center_geometry 四格
首度全跑：短展示 / 短编辑 / 长截断三格过；占位格（编辑态清草稿、字段空
文本）`field_frame_centered` 偏差 0.05 ✓、`glyph_centered`（同轮短编辑格）
1.0 ✓，唯 **`caret_centered` 实测 23.2、门 ≤1.0 红**。此格 0.9.66 轮止于
步 3 从未测到，本轮为首个设备数值。与字形环是不同环：帧已居中、字形已
居中、占位墨迹已居中，独插入点（光标）落点偏离胶囊中心 23.2pt。

## 二、定案：空文档的插入点只认占位行盒

量测链先核（排除量测面）：探针 title_geometry 的 `c=` 是
TitleFieldControl.titleGeometryString 对空文本字段直读
`caretRect(for: beginningOfDocument).minX` 的窗口坐标，与胶囊中心同瞬
同源比差；同 payload 内字段帧偏差 0.05——帧与 caret 同瞬两读，帧正而
caret 偏，偏在字段内部布局，不在帧、不在量法。

机制（inferred，算术精确吻合 + 排除法收口）：UITextField 空文本时按
「显示串」布局唯一一行——无文本时显示串即占位串，位置 0 的插入点落进
居中占位行的一缘（行首），与字段中心的偏差恰为占位串宽之半。本轮数值
逐项对上：偏差 23.2 × 2 = 46.4，与「无标题」在设备字号档（14 semibold
经 Dynamic Type 缩放，三 CJK 字面宽 ≈41.6 × 约 1.12 档 ≈ 46.6）下的
呈现宽同值（量级与尾数皆合，非巧合量级）。排除面逐项清：字段无
leftView / rightView / clearButton / borderStyle 构造（全文件零出现，
无配件占位说）；textRect 与帧同心（历轮设备偏差 0.05）；段落样式
（五修）与 textAlignment 皆在位且已被字形/占位两环设备证正——空文档
无字形行可排，属性面够不到插入点取位，剩余唯一布局演员就是占位行。

短编辑态真字 caret 对照：非空文本的插入点由同一 caretRect 在字形块
首尾两缘取位（探针 `g=` 即两缘真读），字形环过即 caret 随块居中——
但「实际选区落点」此前从未单独量。本批给探针补 `s=`（当前选区起点
插入点窗口 x），场景短编辑格新增 `edit_caret_on_glyph_block` 断言
（落点须骑在字形块区间内、块外距离 ≤1.0），与字形环分工：字形量块
两缘、caret 量实际落点是否同环。

## 三、根治（构造单点）

收口于字段本体 `TitleField`（UITextField 子类、本即字段行为单点，
undoManager / pressesBegan 覆盖同居此）：新增 `caretRect(for:)` 覆盖——

- 非空文本：直通 `super.caretRect(for:)`，逐字回系统原值。帧环、
  字形环、落点映射环（含探针以 caretRect 取字形两缘、TitleTapCaret
  的点按落点）全部走非空路径，逐字守恒；
- 空文本：插入点帧的 x 改由文本矩形中点定（`textRect(forBounds:)`
  的 midX 减插入点宽之半），纵向与宽高仍取系统原值。textRect 与帧
  同心（设备偏差 0.05），居中于 textRect 即居中于胶囊（合成偏差
  ≤0.1 级，远在 ≤1.0 门内）；
- 组字态文本非空（标记串在串内），不入空支，拼音组字落点不受扰。

不另起路径：不改占位构造、不改帧、不动 applyFont 与段落样式。

## 四、断言

**T24-14**（verify_ios.sh [24] 组）锁机制，写成 python 派生普查形态
（同 [74] 组与偿还批四纪律：集合/结构恒等、弱形态计点为零）：

1. 全 app Swift 中 `override func caretRect` 恰一处，且落在 TitleField
   类段内（字段行为单点外不得另起覆盖）；
2. 覆盖体内三件齐：`super.caretRect(for: position)` 直通、空文本守卫
   （isEmpty）、经 `textRect(forBounds: bounds)` 的 midX 定 x。

**负对照实做**（/tmp 副本树、同体 python 本体逐字跑）：摘除整个覆盖 →
恰红（census 0 ≠ 1 + override not in TitleField）；摘空文本守卫 →
恰红（no empty guard）；居中改左缘（midX→minX）→ 恰红（no textRect
centering）；复原 → 绿。三红各指其所摘，不连坐他锁。

**棘轮对账**：PD73 分类器同口径跑原版 / 改后 verify_ios.sh，存量逐值
不变（CNT 406 / PRES 1408，帽不动）——T24-14 为派生普查、零弱形态
增量，合并时无需调帽。

场景面：title_center_geometry 占位格 caret_centered 断言已在（本批不
新增格口）；短编辑格新增 edit_caret_on_glyph_block（见二）；探针
title_geometry payload 新增 selectionCaretX 透出（s= 读源），旧键逐
字不变、解析器按 key 分发，新增键向后兼容。

## 五、验证分账（worktree 干净树，父 bdf062c）

- swiftc -parse：TitleTextField.swift、MomentBridgeUITest.swift 均过
  （本机 swift-6.4.2 工具链）。
- verify_ios.sh 全量：改前基线 **741 ✓ / 6 ✗** → 改后 **742 ✓ / 6 ✗**，
  红集逐行与基线相同——6 红全为构建产物缺失类（ipa / Assets.car /
  开屏 vector ×2 / 产物语言包 / SG49-4 样本），tree 组版构建后自清，
  非源码红；T24-14 ✓、PD73-1 ✓ 在位。
- 本批零 Rust 改动，cargo 未跑（diff 仅 3 个 Swift/脚本文件 + 本报告）。

## 六、留账

1. **Swift 类型级编译门未过**——留 tree 组版 smoke（0.9.68 组版批）。
2. **设备终判**留 0.9.68 装机桥自办：title_center_geometry 四格全跑——
   占位格 caretDev 应自 23.2 落至 ≤1.0；短编辑格 edit_caret_on_glyph_
   block 为真字 caret 首个设备数值（本批机制推定落点在块内，未经设
   备证实）；短展示 / 长截断两格回归对照，四格缺一不算 caret 环收官。
3. 本笔在分支 fix/title-caret-center（父 bdf062c），待主线合并组版。
