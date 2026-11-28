# fix_home_header_gap_adaptive — AUD-A-08 首组头顶距动态适应

用户 2026-11-28 裁定：不取写死的 28（横幅在位会更挤、观感差），也不留现状 31，改**动态适应单点规则**——顶距由上方邻居的实际几何算出，两态视觉间隔落入同一节奏且横幅态不贴脸。未提交，留主线组 0.9.63。

## 一、合成拆解（回源实测，现行码）

视觉间隔口径（与既有 28/6 账同近似）：组头文字顶缘 − 上方相邻可见元素底缘 = 紧邻行 bottom inset + 组头行 top inset。前提：① List 行距由 insets 唯一合成（verify F30-13 零默认依赖锁在位）；② 组头 Text 无内 padding、行顶≈文字顶；③ 首组头紧邻行集合由 body 行序与条件字面穷尽（下表四种）。

窄屏 List 占位清单（首组头邻域，自上而下）：

| 行 | 呈现条件 | top inset | bottom inset | 定义面 |
|---|---|---|---|---|
| spacerRow（占位 132） | 恒在 | 0 | 0 | `listRowInsets(EdgeInsets())` |
| readonlyBannerRow | `library.isReadOnly` | 0 | **6** | 行定义单点 |
| noticeRow | `!library.notice.isEmpty` | 0 | **6** | 行定义单点 |
| newCardRow | `!loadFailed && !isReadOnly` | 3 | **3** | 行定义单点 |
| 首组头 groupHeader | groups 非空 | T（旧 25 写死） | 3 | 本批形参化 |
| 后续组头 | — | 25 | 3 | 紧邻恒为前组末卡 |

旧合成四态（首组头间隔）：

| 态 | 紧邻行 | 合成 | 判定 |
|---|---|---|---|
| 常态 | 新建卡（3） | 3 + 25 = **28** | 基准（Web 组间定案：前组 margin 24 + 组头 padding-top 4） |
| 只读横幅 | 横幅（6），新建卡隐 | 6 + 25 = **31** | 漂移 +3（审计原账） |
| 只读 + notice | notice（6）紧邻（行序在横幅之下） | 6 + 25 = **31** | 漂移 +3 |
| loadFailed（无横幅/notice/新建卡） | 占位行（0） | 0 + 25 = **25** | 漂移 −3（此前未登记，本批拆解新发现） |

notice 单独在位（非只读）时新建卡仍在位、紧邻组头恒为新建卡 → 间隔 28 本就不漂；notice 与新建卡之间 6 + 3 = 9 属另一处合成，不在组头顶距面，本批不动、登记备查。

网格形态：外层 VStack(spacing: 14) 统一段距，组头块内 Text 顶 padding 8 → 组头间隔 = 14 + 8 = **22，横幅/notice 在位与否恒等**（横幅只多一行、不改 spacing）——构造上已满足动态规则，无需改码，本批以量测提取同值登记（HG57-2 一并断言 22）。

Web 同构核查：Web 的只读/会话横幅是 `position: fixed; bottom` 底部常驻浮条（styles/panels.css:322 `.storage-readonly-banner`；main.rs:2244/2254 渲染），不在列表流内、与组头无间距合成——**Web 无同构问题**，仅此登记、本批不改 Web。原生横幅为流内行（S4 定案呈现面），合成漂移系原生独有。

## 二、动态规则（单点）

落点：`HomeHeaderMath`（与 compactP 同家纯函数单源）新增：

```
groupRhythm = 28            // 基准节奏：Web 组间合成定案值（常态实测）
groupTopFloor = 3           // top 下限：本 List 卡行 top inset 同值（行间最小呼吸）
firstGroupTopInset(b) = max(28 − b, 3)
firstGroupGap(b)      = b + firstGroupTopInset(b)   // ≥ 28 恒成立
```

- 输入 = 紧邻行 bottom inset，由 ListView 派生 `firstGroupAboveBottomInset` 按 body 行序判定（newCard 条件与 body 字面同源 → 3；notice → 6；banner → 6；皆无 → 0），判定序经 HG57-3 锁。
- 四态输出：b=3 → top 25（**常态与旧值逐值相同、行为等价**）；b=6 → top 22；b=0 → top 28。四态间隔全 = 28。
- 补偿项追溯：横幅态 top 22 = 基准 28 − 横幅行自身 bottom 6，来自横幅行定义单点，非另拍数。
- 不贴脸不变量：gap ≥ 28 构造恒成立——横幅（强视觉块）在位时间隔永不小于无横幅态；b > 25 的未来邻居出现时 top 钳 3、间隔随 b 增大（钳只防 top 负值，现行四邻居均不触发）。
- groupHeader 改形参 `topInset`，全部组头（含后续组）调用点恒经规则函数（后续组邻居恒卡行 bottom 3 → 25），文件内无第二处写死 top 值。

## 三、量测断言（verify [57] HG57 + F30-5 改判）

按工单口径锁量测值不锁源码文本：

- **HG57-2（核心量测）**：shell 从各行**定义段提取实测几何**（newCard/banner/notice 三行 EdgeInsets bottom、spacer 零 insets 记 0、网格 spacing 取「直接包含横幅行的 VStack」值、组头顶 padding），连同 HomeHeaderMath **源码真身段**（awk 按锚提取）喂宿主 swiftc 编译实跑：断言四态间隔全 = 28 且 ≥ 基准、常态 top = 25、钳不变量（b=25 → top 3/间隔 28；b=40 → top 3/间隔 43）、网格间隔 = 22。本机实跑全过。
- **判别力自检（副本变异，不动本体）**：节奏字面 28→31 变异 → 量测 FAIL（proven）；横幅 bottom 6→9 变异 → 仍 PASS——此为动态适应语义本身（几何变、间隔恒），非断言失效：断言锁的是「间隔输出值」而非某个输入字面，输入漂移由规则吸收正是本批目标。
- **HG57-1**：规则单点计数锁（节奏字面恰 1、函数定义恰 1、调用面 3、派生定义+调用各 1）。
- **HG57-3**：紧邻派生判定序锁（newCard 条件与 body 同源字面在位；notice 判定行序先于 banner——序反则并存态判定面漂移，虽同值亦锁）。
- **F30-5 改判**：旧锁字面 `top: 25` 作废（沿革注已写入断言头注），改锁形参化 `top: topInset` + bottom 3 + 字距/大写 + `top: 25` 零残留。

本机 verify 全跑：HG57-1/2/3 与 F30-5 全绿；余红 = 既有产物红 2（ipa 陈旧/产物语言包，tree 构建后归零）+ 在途三批中间态红（E43-2、SB-1/SB-2，属状态栏二轮/编辑器批在途面，非本批文件面）。swiftc -parse MomentApp.swift 零报错。tree 冒烟组版统一跑。

## 四、登记同步

- 审计总册 AUD-A-08 行改「已裁已落（动态适应）」、§6-3 划线结案；分册 A 的 A-08 节改判已裁已落。
- 矩阵 HOM-23：间距合成段改已裁已落 + HG57 量测锁，呈现面本身仍 U5 抽样。

## 五、真机观感终判点（归用户）

1. 只读横幅在位（救援/降级态进首页）：首组头与横幅间隔与无横幅态观感同节奏、不贴脸不松垮。
2. notice 在位（落盘失败提示后）：同上。
3. 常态与 loadFailed 恢复后：组头节奏无可感变化（常态逐值零变化、理论上不可见差异）。
4. iPad/横屏网格：横幅在位时组头间隔与常态无异（构造恒等，抽验即可）。
