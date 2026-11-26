# 阶段 1 spike：UI 路线二选一（2026-11-26）

两壳同机并装（bundle id 不同），用户真机按三判据判读后拍板。

| 壳 | ipa | bundle id | 内容 |
|---|---|---|---|
| Web | build-web/Moment-spike-web.ipa | com.canopies.moment.spikeweb | WKWebView + moment:// scheme handler 加载包内生产 Web dist；顶部胶囊显示冷启（原生 didFinish ms + 页面 performance.now + OPFS 可用性探测） |
| 原生 | build-native/Moment-spike-native.ipa | com.canopies.moment.spikenative | SwiftUI 列表（数据经 moment-ffi 走 Rust Core、首启种子 8 篇）+ UITextView 编辑页；列表顶部显示冷启（首帧/数据就绪 ms） |

## 三判据的试法

1. **拼音组字**：Web 壳打开任意备忘、在编辑器里用拼音连续组字（现行 Web 编辑器本体）；原生壳点开示例篇、在正文区用拼音组字（UITextView 系统输入法）。比候选跟随、上屏、删改顺滑度。
2. **长按拖拽跟手**：Web 壳在编辑页长按块拾起拖动（现行口径 480ms）；原生壳在列表长按卡片 0.48s 拾起（scale 0.97）上下拖、松手落位。比拾起响应与跟手感（原生壳为 spike 级实现：固定行距估算、无兄弟让位动画，只判路线潜力）。
3. **冷启**：两壳杀进程后冷启，看各自上屏的 ms 数（口径不同：Web 为导航完成 + 页面侧计时，原生为首帧 + FFI 数据就绪；只作量级对照）。

附带观察：Web 壳胶囊里的 OPFS 探测行——WKWebView 内 OPFS 是否可用，直接决定 Web 路线在 app 内能否沿用 SAHPool 存储。

## 构建

`bash build-spike.sh web|native`（链路同 build-ipa.sh；
工具链坑：27.2 接口编出的 SwiftUI 模块下 `@State` 的 `$`
投影不可用，编辑态一律 ObservableObject + 显式 Binding；
WKWebViewConfiguration 无 allowsContentJavaScript 成员，
JS 默认启用）。

## 阶段 2 第三轮新增工具链坑（2026-11-26）
- `@State` 在 app 多文件编译下报 SwiftUIMacros 插件缺失——视图状态一律 ObservableObject + @StateObject 持有，不用 @State。
- SwiftUI 的 PhotosPicker/PhotosPickerItem 在本工具链 27.2 SwiftUI 模块不可见；选图走 UIKit 的 PHPickerViewController（PhotosUI 框架本身可用）。

## 启动闪退定案（2026-11-26，梯子实证）
- 现象：0.5.0/0.5.1 点图标即退，.ips 为 EXC_BREAKPOINT，帧在 ListView.body 的 List 内容构建。
- 定位梯子（build-diag.sh，独立包）：纯文本 ✓、编辑器样本（含图片/gallery/卡片/imgText 全块）✓、真实列表页 ✗、诊断页 ✗。两崩页的唯一共同构造 = builder 式 `List { Section {...} }`（含 LabeledContent 的诊断页同崩，修饰符/数据/FFI 均无关）；spike 的集合式 `List(items)` 与梯子根的 List{NavigationLink}（无 Section）均正常。
- 处置：本 app 内禁用 List+Section，列表类一律 ScrollView+(Lazy)VStack（DiagView 用 HStack 行、ListView 左滑改长按 contextMenu）。先前对 ItemImageView 尺寸断言的归因被梯子证伪（编辑器子树无罪），特此更正。

## 导航 API 口径（2026-11-26 阶段 2 第三轮实证）

- `navigationDestination(item:)` 为 iOS 17+ 且要求 Hashable；本 app 部署目标 16.0，一律用 `navigationDestination(isPresented:)` + 状态枚举 switch（含 nil 兜底 EmptyView）。子页在父页内再注册一层 isPresented 目的地即可同栈推进。
