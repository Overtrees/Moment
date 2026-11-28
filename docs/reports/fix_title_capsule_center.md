# 标题胶囊预览态居中根治

- 日期：2026-11-28
- 批次：0.9.63（未提交，留主线组版）
- 实报：用户 2026-11-28——标题胶囊在预览（非编辑 / shown）态下标题需要居中显示。
- 范围：编辑页标题胶囊的预览态呈现（字段形态 + 截断覆盖层形态）；编辑态与落点映射零改动。

## 一、偏心定性（逐层排查）

预览态标题的呈现链共五层，逐层回源核对（MomentApp.swift EditorHeaderView 段、
TitleTextField.swift、TitleTapCaret.swift、Web title.rs / editor.css 对照）：

| 层 | 构造 | 居中性 | 判定 |
|---|---|---|---|
| 页眉容器 | HStack 双 Spacer(minLength: 0) + 两侧同宽 46 钮 | 胶囊在页眉内对称居中 | 不偏（proven，源码直读） |
| 胶囊定宽 | capsuleWidth = max(标题宽, meta 宽) + 41、钳 [66, avail] | 公式对文本对称——meta 更宽时胶囊对称变宽，公式本身不产生偏心，只放大下层偏心的可见量 | 不偏（proven） |
| 胶囊内行布局 | VStack 居中对齐 + 横内距 20/20 对称；字段尺寸契约宽随提议（T26-8）、覆盖层 frame(maxWidth: .infinity)，两呈现者帧宽恒 = 行宽 | 行中心 ≡ 胶囊中心 | 不偏（proven） |
| 字段形态（全文态 shown / 编辑态） | UITextField `textAlignment = .center`（makeUIView 显式设定） | 字形在字段帧内居中 | 不偏（proven） |
| **截断覆盖层形态（长标题 shown）** | SwiftUI Text + `.frame(maxWidth: .infinity)`，**无任何自身字形居中指令**（无 multilineTextAlignment） | Text 帧占满行宽后，字形在帧内按缺省 .leading 排布、贴左内距；frame 的视图级居中对已满宽的字形排布不构成居中 | **偏心层位（proven：全链唯一无显式居中指令的层；字形 leading 排布的框架语义与用户真机实报互证为 inferred）** |

旁证两条：① 全仓其他需在宽帧内居中的 Text（空态标题/描述等 3 处）都带
`.multilineTextAlignment(.center)`，唯独覆盖层缺失，与全仓口径相悖；② 系统自身的
落点算式（TitleTapCaret：startX = (rowW − dispW)/2）以「显示串居中」为既定前提——
覆盖层是唯一违反该共享前提的消费方。Web 侧预览态走 input text-align:center，
无覆盖层构造，此偏心为原生独有。

旧构造下覆盖层的偏差量（leading 排布模型）：偏差 = (行宽 − 显示串宽) / 2。
meta 不宽于显示串时 ≈0.5pt（几乎不可见）；meta 更宽时随差额线性放大（见 §四），
与「长标题 + 长 meta 时偏左明显」的实报形态相容。

## 二、几何前提清单（落码前定，断言分工守之）

- P1 内距对称：胶囊横内距 20/20 → 标题行宽 = 胶囊宽 − 40、行中心 ≡ 胶囊中心。
- P2 行内填满：字段尺寸契约（T26-8）与覆盖层满宽帧 → 两呈现者帧宽恒 = 行宽。
- P3 字形居中指令：字段 .center（既有）+ 覆盖层 multiline .center（本批补）→ 两形态字形块中心 ≡ 行中心。
- 由 P1–P3：预览态文本中心 ≡ 胶囊中心，模型偏差 0（量测容差 0.5，吸收 tracking 尾随 −0.2 的 ≤0.1pt 视觉量级）。
- 落点守恒前提：覆盖层 frame 与其后手势修饰序不动 → SpatialTapGesture 坐标系（原点在标题行左缘）不变 → TitleTapCaret 算式零改动即守恒（§五复跑实证）。

## 三、落码清单

1. **MomentApp.swift · 截断覆盖层**：Text 补 `.multilineTextAlignment(.center)`
   （根因单点：字形排布居中指令）；frame / contentShape / 手势修饰序逐字不动。
   同处加根因注记（为何 frame 居中挡不住字形 leading、与落点守恒的关系）。
2. **TitleTapCaret.swift · 新增纯核心 `TitleCapsuleLayout`**（Foundation-only，
   与落点映射同文件同纪律）：定宽公式单点 `capsuleWidth(titleW:metaW:avail:)`
   （= min(max(max(titleW, metaW) + 41, 66), max(avail, 66))，AUD-B-02 的 +41
   口径逐值不变）+ 居中量测 `textCenterX` / `centerDeviation`（按 P1–P3 模型：
   可见块宽 min(文本宽, 行宽)、居中原点、偏差绝对值）。
3. **MomentApp.swift · capsuleWidth**：尾段算式改委托 TitleCapsuleLayout（视图只
   备 shown 串 / UIKit 量测宽 / avail 入参）；原公式注记保留并补单点化说明，
   数值逐值不变。
4. **verify_ios.sh [24]**：T24-7 改判（见 §五）、新增 T24-8 / T24-9。

编辑态零改动：字段构造、会话语义、commitTitle、Esc/Enter 收口均未触碰。

## 四、量测前后值（模型量测，宿主实跑）

| 形态 | 入参（标题/显示串宽, meta 宽, avail） | 胶囊宽 | 改前偏差 | 改后偏差 |
|---|---|---|---|---|
| 全文态短标题（字段形态） | 70, 40, 300 | 111 | 0（字段 .center 既有） | 0 |
| meta 更宽短标题（字段形态） | 42, 180, 400 | 221 | 0（同上） | 0 |
| 截断态 | 154, 100, 500 | 195 | 0.5 | 0 |
| 截断 × meta 更宽 | 154, 200, 500 | 241 | **23.5** | 0 |
| 钳上限（坞宽 390） | 600, 100, 266 | 266 | —（块宽以行宽为界） | 0 |
| 钳下限（紧凑） | 10, 0, 300 | 66 | — | 0 |
| avail 兜底 | 200, 50, 50 | 66 | — | 0 |

改前偏差按 §一 leading 排布模型计算（覆盖层形态）；改后偏差为 T24-9 宿主断言
实跑的 TitleCapsuleLayout.centerDeviation 输出（全例 0，容差 0.5）。
定宽公式期望值同表逐例锁定（sync_width 手算核对）。

## 五、断言与自检（证据等级）

- **T24-7 改判**（沿革已写入断言头注）：定宽算式单点化后，③ 由「HDR 内公式
  字面」改盯「纯核心公式字面（$TCARET）+ HDR 委托调用在位 + HDR 旧式字面零
  残留」；+41 口径与数值不变，①② 不动。改判后 T24-7 ✓。
- **T24-8 新增（机制锁）**：预览态双形态居中指令在位——字段
  `f.textAlignment = .center`（TFIELD）+ 覆盖层 `multilineTextAlignment(.center)`
  （CAP 段）。守前提 P3。✓
- **T24-9 新增（量测型，E47-3 同式）**：verify 内以宿主 swiftc 编译
  TitleTapCaret.swift + 内嵌断言体真跑，§四矩阵 7 例（定宽期望 + 偏差 ≤0.5）
  全过，输出 TITLE_CENTER_PASS。✓（本机 ~/ios-native 工具链实跑；tree /opt/tc
  同候选路径，组版冒烟同跑。）
- **落点守恒复跑**：tests/title_tap_caret_main.swift（plan_title_tap_caret §5.2
  期望表）以本机 swiftc 编译真跑 **19/19 ALL PASS**；verify [26] 全组 9 ✓ 不动。
  覆盖层手势坐标系未变（frame 与修饰序逐字保留），算式零改动。proven。
- **语法/全量自检**：MomentApp.swift swiftc -parse rc=0；verify_ios.sh bash -n
  过；全量 verify 本批后 [24] 9/9 ✓、[26] 9/9 ✓。红集对账：改前基线 6 红
  （ipa 陈旧 / 产物语言包 2 产物红 + 他批在途 4 红），改后红集为 2 产物红 +
  状态栏二轮批在途 SB-4/SB-7（其 SB-6 在两次跑之间已自清）——均为并发批的
  进行中状态，非本批引入；本批相关组零新增红。注：全量 ✓ 计数在并发批落码
  间波动（503→585→572），以红集归属为准。
- **并发隔离**：动工前 git diff 全量快照（/tmp 留存）；本批 hunk 恰三处——
  MomentApp 标题段两处（覆盖层、capsuleWidth 尾段）、TitleTapCaret.swift 纯
  追加（+76 行，该文件他批未动）、verify [24] 段（T24-7 改判 + T24-8/9 新增）。
  B-02 的 shown 口径注记与 +41 语义完整保留（公式移纯核心、T24-7 已同步改判）。

## 六、真机终判点（随 0.9.63 装机）

1. 长标题（>10 字）预览态：截断串在胶囊内居中（重点看 meta 较长的一篇——
   改前偏差最大形态）；点按覆盖层落点与改前同位（前缀内同位、省略号上落文末）。
2. 短标题预览态：标题居中（字段形态不回归）；meta 更宽的短标题篇同核。
3. 编辑态：聚焦后全文呈现、胶囊弹性变宽与失焦收敛如旧（本批未动该路径，
   防重演算波及）。
