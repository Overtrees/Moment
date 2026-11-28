# 标题字形环根治（五修）：展示态真实文本在已居中的字段内仍左排

## 一、症状与设备实证（0.9.66 桥自办，proven）

四修（定宽帧，fix_title_center_short_text）装机后，title_center_geometry 两遍同值：
短标题展示态格 `field_frame_centered` 偏差 0.05 ✓、`glyph_centered` 偏差 16.2 ✗，
格口判别力 rowW−glyphW = 32.33（非空转）。title_geometry 直读用户真实篇
（「使用指南」4 字、展示态）：capsuleCenterX = 196.5、fieldCenterDev = 0.05、
textRectCenterDev = 0.05、glyphCenterDev = 15.0；字形左缘与 fieldX/textRectX
逐值重合、余量 30.07 全在右侧。用户实报一致：占位已居中、真实短标题仍左偏。

定案边界：帧环已合（定宽帧设备成立），剩字形环——文本在字段文本区内按左
对齐绘制。本批不动帧环。

## 二、定案：赋值点普查 + 机制

标题文本全部赋值/构造点逐个对账（全仓 grep + 逐文件通读）：

| # | 呈现者 | 赋值/构造点 | 形态 | 自带居中指令 |
|---|---|---|---|---|
| 1 | 字段文本本体（展示态） | TitleTextField.makeUIView / updateUIView 两处 `f.text = text.wrappedValue` | plain text | 无（见下） |
| 2 | 字段文本本体（编辑态） | 键入由 UIKit 按字段缺省属性物化；editingChanged 只回读 `f.text` | plain text | 无（同 #1 构造点） |
| 3 | 字段属性构造单点 | TitleTextField.applyFont：`defaultTextAttributes = [.font, .kern, .foregroundColor]` | 属性字典 | **无 .paragraphStyle** |
| 4 | 占位呈现者 | 同在 applyFont 构造 `attributedPlaceholder` | attributed string | 有：段落样式 .center（三修 dc1d543，设备已验正） |
| 5 | 截断覆盖层 | MomentApp 胶囊内 SwiftUI Text | SwiftUI | 有：`multilineTextAlignment(.center)` |

TitleTextField.swift 内 `attributedText` 零出现——文本本体从不经属性串显式
赋值；它经 plain 赋值后，由字段按 `defaultTextAttributes` 物化为内部属性串
绘制。机制与占位案（三修定案）同型：**该字段的绘制对齐只认属性串自带的段
落样式**；文本本体的构造点（#3）从未给段落样式，缺省即 .natural（左），字段
`textAlignment = .center`（T24-8 所锁）管不到属性串层。设备实证逐项吻合：
段落左排的字形块恰贴 textRect 左缘（左缘逐值重合）、余量全在右侧；占位因
串内有 .center 而居中——同一构造点上，一名呈现者有段落样式、一名没有，是
唯一的解释变量。

编辑态（#2）：场景 shortEdit 格在 0.9.66 自办时未跑到（步 3 红即停），设备
状态 unknown；但编辑态文本同出 #3 构造单点（键入物化走缺省属性），机制同
型成立，修复同点覆盖，终判留装机后场景四格全跑。

## 三、根治（单点）

`TitleTextField.applyFont`（属性构造唯一单点）：

- 居中段落样式收为一份构造 `centerPara`（`alignment = .center`）；
- `defaultTextAttributes` 新增 `.paragraphStyle: centerPara`——文本本体获
  与占位同一法则的串内居中指令；
- `attributedPlaceholder` 改为复用同一份 `centerPara`（原 placeholderPara
  独立构造删除），两呈现者同点同式、防再漂移。

即三修法则（属性串段落样式钉 .center）自占位推广到文本本体。帧环、定宽
（`.frame(width: capsuleWidth - 40)`）、落点映射、占位构造内容逐字保全；
`textAlignment = .center` 保留（字段级指令与段落样式同向）。TitleTapCaret
P3 前提注记同步改判：字形居中指令由两件（三修时口径）推广为三件，注五修
沿革；inkCenterDeviation 的语义注记同步（居中语义现由属性串段落样式兑现）。

## 四、断言

新增 **T24-13**（verify_ios.sh [24] 组）锁机制：

1. applyFont 段内 `alignment = .center` 恰 1 处（一份构造）、
   `.paragraphStyle: centerPara` 恰 2 处入串（defaultTextAttributes +
   attributedPlaceholder——两呈现者同点同式，不许各备一份）；
2. 普查锁：全仓 `defaultTextAttributes =` 赋值恰 1 处（构造单点外不得另
   起属性构造）；TitleTextField.swift 内 `attributedText` 零出现（不得新
   增属性串赋值路径绕开构造单点）。

**负对照实做**：摘除 defaultTextAttributes 的 `.paragraphStyle: centerPara`
一行 → T24-13 恰红、T24-11（占位锁）与 T24-12 仍绿（分工互证）；复原后
T24-13 转绿。

场景面：title_center_geometry 四格已在（短展示 / 短编辑 / 长截断 / 占位），
本批无新增格口；步 3 之后三格（短编辑、长截断、占位）的设备数值待 0.9.67
装机后桥自办全跑回收（见留账）。

## 五、验证分账（worktree 干净树，父 b352260）

- verify_ios.sh 全量：**713 ✓ / 5 ✗**。5 红全为构建产物缺失类（worktree
  无 build 产物：ipa 不存在、Assets.car 缺、开屏 vector json ×2 缺、产物
  语言包缺）——tree 组版构建后自清，非源码红。源码面全绿，[24] 组含新
  T24-13 ✓。
- swiftc -parse：TitleTextField.swift、TitleTapCaret.swift 均过。
- 本批零 Rust 改动，cargo 未跑（diff 仅 3 个 Swift/脚本文件 + 本报告）。

## 六、留账

1. **Swift 类型级编译门未过**——留 tree 组版 smoke（0.9.67 组版批）。
2. **场景四格装机全跑**留 0.9.67 桥自办：短展示格 glyphCenterDev 应自
   15.0/16.2 落至 ≈0；短编辑格为字形环编辑态首个设备数值（本批机制同型
   推定、未经设备证实）；长截断、占位两格回归对照。
3. 本笔在分支 fix/title-glyph-center（父 b352260），待主线与偿还批三、
   状态栏分支一并合并组版。
