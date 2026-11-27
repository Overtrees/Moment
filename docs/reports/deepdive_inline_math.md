# 行内公式呈现路径代码级深挖定性（J1/E5）

结论先行：**不能显示（proven，SDK 接口层证据完备）**。断环不在产图侧（MathImageStore 链完整），不在 NSAttributedString 构造侧（附件确实挂上了），而在最后一环：**SwiftUI `Text` 没有消费 `NSTextAttachment` 的任何 API 面**——附件属性随 `AttributedString(ns:)` 转换进入数据层后，无人渲染，U+FFFC 占位符在真机上呈空白。症状特征：公式在 pending/failed 态反而有字（mono 原码/红色原码），**快照就绪后反而消失变空白**——真机若见此特征即与本定性互证。

文件：rust/apps/ios/app/MomentApp.swift（行号为 0.9.44 落码后现行值）；SDK 为 ~/ios-native/iPhoneOS27.2.sdk。

## 一、转换链逐环（代码实读）

1. **产 run**：`MdRender.runs` 的 `"Math"` 分支（:9498-9502）把 tex 同时放进 `text` 与 `mathTex` 键。仅 display=false 的行内公式走此路；display 段由 MdSegsView 分段走 MdMathView 块级路（:9617-9635），不在本链。
2. **构串**：`MdRender.attributed`（:9510-9516）= `Marks.withRhythm(Marks.attributed(runs:base:), block:)`。
   - `Marks.attributed`（:1684）的 mathTex 分支（:1755-1778）：`MathImageStore.shared.entry(tex:fontSize:)` 三态——ready 时建 `NSTextAttachment`（image + bounds，y = −descent 基线对齐），置 `attrs[.attachment]`、文本替换为 `"\u{FFFC}"`（:1759-1767）；failed → mono 0.85em + `T.mathFailUI` 红码；pending → mono 正文色原码占位。
   - `Marks.withRhythm`（:1599-1631）：以 `NSMutableAttributedString(attributedString:)` 复制后仅加 `.paragraphStyle`（及标题 kern）——**不剥附件**，出串确实携带 `.attachment` 属性。此环无问题。
3. **呈现**：`MdSegsView.body`（:9593-9613）——`Text(AttributedString(MdRender.attributed(g.segs, base: base, block: block)))`，即 Foundation 的 `AttributedString.init(_ nsAttributedString:)` 转换后交给 **SwiftUI Text**，同处挂 `.environment(\.openURL, …)` 兑现 wiki 链接点按。**没有 UILabel/UITextView 承载**。MdBlockView 表格单元格（:9842、:9861）同为此形态、同链同命。

## 二、SDK 接口层实证（平台语义）

在本机 iPhoneOS 27.2 SDK 全部框架 swiftinterface 内做完备枚举：

- **`AttachmentAttribute` 全 SDK 仅出现于 UIKit**：`grep -rln "AttachmentAttribute" */*.swiftinterface` 只命中 UIKit.framework。SwiftUI 与 SwiftUICore 的 swiftinterface 中 `NSTextAttachment` **零出现**；Foundation 的 swiftinterface 中 `attachment`（不分大小写）**零出现**。
- **附件在 AttributedString 模型层有合法席位**（属 UIKit 作用域）：UIKit.swiftinterface:5565 `UIKitAttributes` 成员含 `public let attachment: …AttachmentAttribute`；:5692-5693 `AttachmentAttribute: CodableAttributedStringKey, Value = NSTextAttachment`。故 `AttributedString(ns:)` 转换大概率把 `.attachment` 作为数据保留进 UIKit 作用域（此点 graded **inferred**——接口只证明席位存在，转换实现不在接口内）——但保留与否不影响结论，见下。
- **SwiftUI Text 的属性支持面无附件**：SwiftUI 自己的作用域 `SwiftUIAttributes` 全量成员（SwiftUICore.swiftinterface:10021-10040）为 font / foregroundColor / backgroundColor / strikethroughStyle / underlineStyle / kern / tracking / baselineOffset / alignment（iOS 26+）/ lineHeight（iOS 26+）/ **adaptiveImageGlyph** / accessibility / foundation——**没有 attachment**。Text 另行映射的 Foundation/UIKit 属性（link、font、foregroundColor 等）也不含附件；整个 SwiftUI/SwiftUICore 接口没有任何消费 `UIKitAttributes.attachment` 的声明。
- **唯一的「文中图」机制是另一套**：`adaptiveImageGlyph`（iOS 18+，`NSAdaptiveImageGlyph` 类型 + 专属属性）才是 SwiftUI Text 支持的行内图机制，与 `NSTextAttachment` 类型、属性、入口全不相同。本工程未用它（MomentApp.swift 内 `AdaptiveImageGlyph` 计数 0）。

即：附件属性即使被转换保留，也没有任何 SwiftUI 渲染路径消费它；U+FFFC 在 SF 字体下无字形，呈空白占位。**断环定位：环 3（呈现），环 1/2 无罪。**

## 三、产图侧核对（MathImageStore，:10031-10179）

逐环完整，graded **proven（代码层）**：

- `entry(tex:fontSize:)`（:10050-10063）：缓存键 = 字号×2|明暗|tex；未命中且不在队/不在途才入队并 `pump()`，返回 .pending。
- `pump()`（:10065-10084）：串行单工；先过 FFI `renderMathml(tex, display: false)`，空串即 .failed + DiagLog logOnce；否则隐藏 WKWebView 加载 `html(ml, size:)`（strut 锚 + MathML，:10106-10119）。
- 量测（:10136-10179）：didFinish 后 JS 取 math rect 与 strut 基线（descent = rect.bottom − strut.top，Swift 侧钳 [0,h]），`takeSnapshot` 以该 rect 截图；任一环失败 → finishCurrent(nil) = .failed + 打点。
- 通知：`finishCurrent`（:10121-10134）每 job 落定（ready/failed 皆然）`version += 1`；MdSegsView 以 `@ObservedObject mathStore`（:9579-9581）订阅，body 重估 → `entry()` 命中 .ready 换图。链闭合。
- 残余风险（不改变结论、修兜底时一并留意）：JS `getBoundingClientRect` 为 CSS 像素，`WKSnapshotConfiguration.rect` 为 webview 点坐标，离屏 900pt 宽 + viewport device-width 下比例是否恒 1 未经代码层外证据确认——图即使产出，尺寸/清晰度仍有 **inferred** 级风险；但此风险在断环之下位，现无验证价值。

## 四、工程内先例旁证

- `Marks.attributed` 的另一消费面是编辑器 `EditorTextView`（UITextView，:1948/:2114 经 withRhythm 赋值）——UITextView 原生渲染附件本可成立，但**编辑面 runs 永不含 mathTex**（注释 :1752-1753 明载、产 run 唯一入口在 MdRender），此先例对本链不构成支持。
- 其余行内构造从不走附件：行内代码走 `.backgroundColor`（在 Text 支持面内）、图片走独立 `MdImageView`/`ItemImageView` 视图、高亮走 backgroundColor+字重。**全工程只有行内公式一处把宝押在「附件穿过 SwiftUI Text」上**，且全仓 Swift 源除 MomentApp.swift 外无第二处 NSTextAttachment（grep 零命中）。

## 五、结论分级

| 命题 | 分级 | 依据 |
|---|---|---|
| MathImageStore 能产出公式图并通知重渲 | proven | §三逐环代码实读 |
| NSAttributedString 出 MdRender 时携带附件 | proven | §一环 2 代码实读 |
| 附件经 `AttributedString(ns:)` 转换后仍在数据层 | inferred | UIKit 作用域席位存在（UIKit.swiftinterface:5565/5692），转换实现不在接口内；且与结论无关 |
| SwiftUI Text 渲染该附件 | **不能（proven）** | §二完备枚举：AttachmentAttribute 全 SDK 仅 UIKit 声明；SwiftUIAttributes 全量成员无附件；SwiftUI/SwiftUICore 零 NSTextAttachment |
| **整链真机可见公式图** | **不能显示（proven）** | 断在呈现环；症状 = ready 后空白、pending/failed 反有字 |

代码层到此已尽：剩余不确定性只有「转换是否保留数据」这一与结论无关的 inferred 项，不构成「需真机验证」式悬案。

## 六、兜底修复方案（不落码，供排批）

思路：**只换承载、不动上游**。NSAttributedString 本身是对的（附件、段落节奏、链接全在内），把 MdSegsView 文本组的承载从 SwiftUI Text 换成只读 UITextView representable，TextKit 原生排附件，整链其余部分（MdRender/Marks/MathImageStore）零改动。

### 设计：`MdTextGroupView: UIViewRepresentable`

- 构造入参：`attr: NSAttributedString`（仍由 `MdRender.attributed` 产出）、`onOpenURL: (URL) -> OpenURLAction.Result`（由 MdSegsView 把现行 OpenURLAction 逻辑——wiki 方案拦截 → wikiTap、余 `.systemAction`——以闭包传入，语义逐字保留）。
- makeUIView：`UITextView`，`isEditable=false`、`isScrollEnabled=false`、`backgroundColor=.clear`、`textContainerInset=.zero`、`textContainer.lineFragmentPadding=0`（此二项是与 SwiftUI Text 布局盒对齐的关键：UITextView 默认 inset 上下各 8、行片段 padding 5，不清零会系统性多出 16 高 + 10 宽偏移）、`isSelectable=true`（链接点按依赖，见下）、`dataDetectorTypes=[]`（防系统自作主张加链，与 Web 呈现口径一致）。
- 尺寸：实现 `sizeThatFits(_:uiView:context:)`（UIViewRepresentable iOS 16+ API，本工程部署目标 16.0 可用）→ `uiView.sizeThatFits(CGSize(width: proposal.width ?? .infinity, height: .infinity))`，高度随附件就绪后的重排自然增长。
- updateUIView：`if uiView.attributedText != attr { uiView.attributedText = attr }`（只读场景成本低；相等判断防无谓重排）。

### 链接点按等价

- Coordinator 作 `UITextViewDelegate`：`textView(_:shouldInteractWith:in:interaction:)` —— 取 URL，调 `onOpenURL(url)`，恒 `return false`（行为全由闭包接管，与现行 OpenURLAction 的 `.handled/.systemAction` 分流等价：闭包内 wiki → wikiTap 后回 .handled；余走 `UIApplication.shared.open` 对应 .systemAction 语义，落码时以捕获 MdSegsView 现行 OpenURLAction 本体转发为最稳妥——representable 拿不到 environment 的 openURL，故由 MdSegsView 在 body 里构造闭包时捕获其 `@Environment(\.openURL)` 值传入，逐字复用现有判断代码）。
- 注意 iOS 17+ 另有 `shouldInteractWith` 的 UITextViewPrimaryAction 语义差异：恒 false + 自行 open 是通行做法；落码后 Diag 打点记每次链接点按的方案与去向，与现行 wikiTap 打点并轨。

### 行高/段距一致性

- 段落节奏已在串内：`Marks.withRhythm` 的 `lineHeightMultiple`（正文 1.75 / 标题 1.2·1.28 / 引用 1.6 等）是 NSParagraphStyle，UITextView 原生兑现，与 Text 时代同源同值，**零换算**。
- 组间 spacing 6、`.frame(maxWidth:.infinity, alignment:.leading)` 等 MdSegsView 外层布局不动；文本组改承载后盒高由 sizeThatFits 给出，附件行高出正文行高时自然撑高（期望行为，与 Web .math-inline 同理）。

### 与 MathImageStore 重渲接法

- 现行机制原样保留：MdSegsView 的 `@ObservedObject mathStore` 使 version 变化触发 body 重估 → representable 收到新 attr（entry 已 .ready）→ updateUIView 换串 → sizeThatFits 给出新高。无需给 store 加任何新通知。

### 改动面清单

| 落点 | 改动 |
|---|---|
| MdSegsView.body 文本组分支（:9593-9613） | `Text(AttributedString(...))` + `.environment(\.openURL)` 改为 `MdTextGroupView(attr:onOpenURL:)`；openURL 判断代码搬入闭包构造 |
| 新增 `MdTextGroupView` + Coordinator | 约 100-130 行，置 MdSegsView 附近 |
| MdBlockView 表格单元格（:9842/:9861） | 同形态同断环（单元格可含行内公式）——建议同批换承载；风险：Grid 单元格内 UITextView 的宽度纪律（sizeThatFits 的 proposal 宽度来自 Grid 列宽，需实测列宽不被内容撑爆），可作本批第二段、单独断言 |
| verify_ios.sh | 新增断言：MdSegsView/MdBlockView 不再以 `Text(AttributedString(MdRender` 直喂（旧形态零残留门）+ MdTextGroupView 在位 + textContainerInset/lineFragmentPadding 清零在位 |
| 不动 | MdRender、Marks.attributed、withRhythm、MathImageStore、MdMathView、语言包 |

### 风险点

1. **块手势吞触**：预览位于编辑器块内，UITextView 会先于块级长按拾起手势拿到触摸——DragPickupInstaller 的仲裁需复核；缓解：无链接且无公式的文本组可 `isUserInteractionEnabled=false`（由 runs 是否含 `_link`/`mathTex` 判定，MdSegsView 分组时可算），把换承载的影响面缩到必要组。
2. **isSelectable 的选区 UI**：长按出选择手柄/菜单与编辑器长按转换菜单可能叠加——同风险 1 的分组开关可一并缓解（仅交互组 selectable）。
3. **sizeThatFits 宽度提案**：VStack 内 proposal 宽度应为栏宽；若拿到 .infinity 需回退到 textContainer.size 约束——落码时以 `proposal.width ?? context` 兜底并 Diag 记一次量测值。
4. **TextKit 版本**：UITextView 默认 TextKit 2（iOS 16+），NSTextAttachment 在 TK2 受支持（UIKit.swiftinterface 中 AttachmentAttribute 无 TK2 弃用注记，与 obliqueness/expansion 的弃用标注形成对照——此对照亦是 §二的旁证）。
