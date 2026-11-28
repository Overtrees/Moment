# 全面审计批 6 落地报告：首页细项 + 账本/断言回写

日期：2026-11-28。范围：总册 audit_full_2026-11-27.md 批 6 定版项。
纪律：只碰首页相关段与 verify 对应组、自开新组尾号；状态栏段/媒体
解码段为并行线禁区，未碰。不推送、不出包、未上 tree。

## 提交清单（现行历史）

| 笔 | 内容 |
|---|---|
| 69d09d4 | AUD-A-01 封面探针 URL 口径对齐 |
| da77078 | AUD-A-04 页眉命中死区 + Sanitizer 门带联动 |
| 5e8a273 | AUD-A-05 网格组头大写 |
| ea50bb1 | AUD-A-06 图文方卡展开药丸单点化 |
| a54f266 | AUD-A-07 左滑/网格菜单辞焦 |
| 8bb7ccf | AUD-D-03/C-03 注释对齐 |
| 94a965c | AUD-D-02/C-06 verify 改锚 |
| 5068df0 | verify 新组 [65] HM65-1..5 |
| 81e18ad | 账本回写（矩阵 + 总册） |
| d9fe880 | 断言基数回写 F30-2/R31-3（含他线内容，见 §4） |

## 1. 逐项落地

### AUD-A-01 封面探针 URL 口径（缺陷/一致性）
新增 `MemoItem.safeCoverURL(_:)` 单点（与 Web safe_image_url /
core 同规则：trim 后 http(s) 直过；data:image/(png|jpeg|gif|webp|
bmp|avif);base64 且载荷非空、全 base64 字符集才过；其余 nil）。
cover 探针：image 支 URL 过白名单、不过继续下探；imgTextCard/
imageTextRow 拆出同支只取 fileId（删 URL 回退——Web 无此路，此前
会派生 Web 不派生的封面）；gallery 逐项同口径、空串跳下一项。
断言 HM65-1。

### AUD-A-04 页眉命中死区 + Sanitizer 联动（缺陷）
页眉头像/搜索胶囊 `.allowsHitTesting(compactP < 0.5)` 两处改 `< 1`
（Web 头像 pointer-events 至 p≥1 才关；紧凑胶囊 p≥1 接管），
p∈[0.5,1) 三件皆不可点的死区消除。联动：ScrollOffsetSanitizer
`hitGateBand` 15→30（关门点与满格点同值），消毒逐序列期望按新带
重算并回写注释（[0,8,25,60,120]→{8,25,120}；[0,5,10,14,16,20,40]
→{5,10,14,16,20}，40 转悬置候选；余三列不变）；探针毒化注、
compactband 边沿注同步改口径。verify F30-21 锚改判带 30 并注沿革；
HM65-2 锁阈值计数（<1 恰 2、<0.5 零回潮）。

### AUD-A-05 网格组头 uppercase（一致性）
网格组头 `Text(group.title)` 补 `.textCase(.uppercase)`，与 Web
text-transform 及窄屏 groupHeader/SectionHeader 同口径（CJK 无字
形差、英文月份组头可见差）。断言 HM65-3。

### AUD-A-06 图文方卡展开药丸（一致性）
squareCard 向 squareImageCard 下传 expand/total；其 meta 行内联
自绘收起钮删除，改与文本方卡同走 `squareFoldPill` 单点：折叠态
出「展开 · 共 N 条」、展开态末卡出收起（Web 两卡同一 MemoRow、
药丸无分类差）。语义前提已回源：folded 时 expand 非 nil、expanded
时仅末卡 collapse 非 nil，两者永不同时在位。断言 HM65-4。
连带基数：glassControl(controlS) 计数 5→4，R31-3 已回写（见 §3）。

### AUD-A-07 左滑/网格菜单辞焦（一致性）
行卡左滑删除/置顶、方卡长按菜单置顶/删除四处动作首行补
`resignSearch()`，与点按打开（openMemo/createAndOpen 本已辞焦）
口径齐。断言 HM65-5。连带基数：F30-2 无参 resignSearch() 计数
4→8，已回写（见 §3）。

### AUD-D-03 图片页查名注释（文档）
attachmentName/displayName 两处文档改实序：清单优先 → 节点名兜底
（扫 attachment/gallery 节点名）→ 调用点传入名；删「唯一真值」
表述（与实现序不符）。

### AUD-C-03 权限注释（文档）
MomentPermissions.swift 文件头与本地网络探针注释的自指表述
（「行注已写明」）改指实处：impl_permission_center §五/§八。

### AUD-D-02 / C-06 verify 改锚（断言完整性）
- D-02：[4] 组标题截断由全文件 grep `prefix(12)`（恒命中 UUID 等
  九处、断言恒真）改锚 ImagePageView 段内真实截断式
  `String(n.prefix(12))` + `+ "…"`（段界至 SplashHostView）。
- C-06：[1] 组版本串由全文件首个数字 Text（现行恰一处、偶合正
  确）改锚 settings.version 标签之后首个数字 Text。
两处均属「锁文本不锁机制」的同类欠账，本批一并收口。

### verify 新组 [65]
尾号顺延（落地时 HEAD/工作树最大组头为 [64]，批 4 线所开）。
HM65-1..5 均为段内锚 + 计数/存在性断言，逐条对应 A-01/04/05/06/07。
注：矩阵 §6.4 注记称 U 批断言用「新组 [65]」，但 verify 实体
（HEAD 与工作树）无第二个 [65] 组头；U 批后续若落组头需顺延 [66]。

## 2. 账本回写（81e18ad）

矩阵 plan_selftest_coverage.md：
- HOM-16（AUD-A-03）：改锚 12——分隔行高 6、与行距合成 12，
  0.9.59 用户改定，verify F30-14 已锚 12，出处 fix_home_grid_
  landscape §五；旧记「22 改定 / 分隔行高 16」系账实差，已更正。
- HOM-21：已落码（A-04）；HOM-22：已落码可关（A-05/A-06）；
  HOM-04：不辞焦微分叉已除（A-07）；HOM-07：增补封面三分叉样本
  注（url 形 imgTextCard 不派生 / 非白名单 URL 首图跳过下探 /
  空串 url 后跟真图取真图，桥回读可判、待样本抽样）；
  HOM-05：增补短查询通配符口径注（A-02 已于 0.9.62 批 2 落地，
  不在本批范围）。
- LCH-13：改「机制已落」——MomentBridgeTools.swift 分发层
  :224/:254 直回 read_only_mode、:1382 同码收口（回源核实）；
  未成内置场景、桥可直判（§0 计数口径不动）。
- LCH-14：改「主项已落」——MomentBridgeOps.swift 回
  effectiveScope :74-75/:92-93；guardableOpsSteps :184 与差集
  区分 :199。
- BRG-11：吊销回执已落——MomentBridgeSettings.swift
  revokeOutcomeKey :76-85、回执行 :442-448；中继房间残留一项
  仍按原登记。BRG-12：已落（scopes_none :407 / scopes_ungranted
  :417）。BRG-13：已落（stateReasonKey 次级行 :287-295）。

总册 audit_full_2026-11-27.md：AUD-A-01/03/04/05/06/07、C-03、
C-06、D-02、D-03 与批 6 行逐行附「批 6 已落」注，最小改动。

不在本批：AUD-A-02（FTS LIKE 转义，0.9.62 批 2 已落，回源实证
storage 转义 + ESCAPE 在位）；E-06/LCH-15 布防 reason 呈现
（回源实证 MomentRescue.swift 仍无 reason 呈现，矩阵原状正确、
未动）。

## 3. 断言基数回写（d9fe880）

本批两处正当收口改变了既有计数型断言的基数，三方量测归因
（批前 5e37c07 / 批 4 后 4adb4ef / 现行）：resignSearch() 4/4/8、
controlS 5/5/4、pill 14/14/14。故回写：F30-2 计数 4→8（注 A-07
沿革）、R31-3 controlS 5→4（注 A-06 沿革），pill 不变。

## 4. 并行撞车与拆笔记录（如实）

本批执行期同仓有三线并行（状态栏回退线、审计批 4 线、U 批/矩阵
线），HEAD 与暂存区多次被推进，发生四次扫入，均已处置：

1. A-01 首笔误扫回退线已暂存的 MomentStatusBarRender.swift 删除
   ——当场拆笔修复（69d09d4 只含本项），其暂存删除一度复位，其后
   由回退线自身提交收口（b913f6a 等）。
2. A-04 首笔（cf842b3）扫入回退线进行中的图页段/EditorModel 段
   改动——拆笔后改用「HEAD blob 内容锚点」法重落（da77078 只含
   本项 8+4 hunk），cf842b3 已孤置不入历史。
3. D-03/C-03 首笔扫入回退线暂存的 verify 尾部 −142 行——拆笔
   修复（8bb7ccf 只含本项）并复原其暂存；其后该暂存由回退线自行
   撤下，其改动全程保留于工作树、无丢失。
4. 基数回写笔（d9fe880）扫入回退线暂存的 MomentApp 第二波删除
   46 行（BlockTextView/EditorModel/EditorView 段的状态栏拆除）。
   其后回退线自行 rebase 重整历史（b913f6a/a5c879a/c42a832/
   91e7569）并保留该笔于顶；91e7569 另清理了 [65] 追加与其尾态
   间误入的第二份 EB63-5 块。本批未再改写历史：d9fe880 的
   MomentApp 部分归属回退线、在此登记；verify 部分确为本批两锚
   （现行 HEAD 实测 F30-2 =8、R31-3 =4 在位）。

后续落笔纪律（本批后段已执行）：提交前查暂存区名单、HEAD blob
内容锚点落笔、提交与 HEAD 稳定性检查同 exec 完成。

## 5. 线 B 调优候选（只登记，不动，待用户裁）

出 audit_detail_home.md:141 系统性小差，非缺陷、属口味：
- 标题类字重：Web 650 vs 原生 semibold——行卡/方卡/图文方卡/
  新建卡/天气温度共 5 处；
- chip 文字色：Web accent vs 原生灰——3 处；
- SF 图标比 Web SVG 小 3px：搜索两态。

## 6. 自检结果（本机）

- cargo test --workspace：全绿（各套件 0 failed，最大套件 86 项）。
- verify_ios.sh 全量（工作树）：636 ✓ / 24 ✗。本批相关全过：
  [1] 版本（C-06 新锚）、[4] 标题截断（D-02 新锚）、F30-21
  （带 30）；[65] 五条因脚本 trailer 在既有红项处 exit 未及执行，
  已抽块单独执行全过（HM65-1..5 ✓）；F30-2/R31-3 回写后基数与
  HEAD 实体量测一致。
- 24 ✗ 构成：陈旧 ipa/语言包产物类、perm.* 僵尸键（他线 i18n
  进行中）、B16/B25/EB63（批 4 线）、T24-5（标题线工作树 WIP；
  本批八笔 diff 无标题胶囊/TextField hunk，非本批）、R31-3/F30-2
  两条为本批基数回写对象（回写前测得、回写后已对齐）。
- Swift 编译级验证：本机无 swiftc，按既定分工归 tree 冒烟；本批
  Swift 改动均为同文件既有 idiom 的同构复用（squareFoldPill 调用
  与 squareTextCard 同形、.textCase 与 groupHeader 同形、
  resignSearch 调用与 openMemo 同形）。
- 未推送、未出包。
