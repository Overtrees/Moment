# 权限页 UIUX 调优（fix_permissions_uiux）

用户 2026-11-28 实报：权限页 UIUX、交互、渲染细节有点差，按美观优雅、简洁、自然方向调。本批只调呈现与交互细节：权限状态真读、请求路径、各项在位面、文案（含实况行注「暂无功能使用」定稿）全部零改动；PermCenter 一行未动。改动文件：`MomentPermissions.swift`（PermKind 加图标映射 + PermissionsView 呈现层）、`verify_ios.sh` 尾部新增 [60] 组。未提交，留主线组 0.9.63。

## 一、调优清单（现状问题 → 改法 → 依据）

| # | 面 | 现状问题 | 改法 | 依据（设置族既有口径） |
|---|---|---|---|---|
| 1 | 图标列 | 权限行无图标列，是设置族子页里唯一无图标锚点的行组（文字左缘直起、扫读无锚、与同族页并置形态断裂） | 每项加 SF Symbol 图标列：槽 24×24、字形 `min(f16, 24)` 封顶、T.accent、HStack spacing 11。符号优先取全 App 已在用者（photo.badge.plus / photo.on.rectangle.angled / checklist / location），余为部署目标 16.0 内长期可用符号，与各项系统设置面语义对应（bell.badge / camera / mic / faceid / network / calendar / timer / arrow.triangle.2.circlepath / paperplane） | SetRow 图标形态（槽 24、字形封顶同式、accent、spacing 11）；手势页（槽 25）、备份行（槽 28）同为「子页行组必有图标列」 |
| 2 | 行注/说明行距 | 行注 12pt 无 lineSpacing，通知/实况/后台三条长注折行后行间紧贴；intro 三行同病 | 行注与 intro 均加 `.lineSpacing(f12 * 0.55)`（默认档 = 6.6，DT 高档随字号同比例放大） | 手势页 12pt 说明 lineSpacing 6.6（= 0.55 倍字号）；倍数写法使行距随 DT 缩放（DiagView 说明行 f11×0.45 同为倍数式） |
| 3 | 状态色分组 | 已授权系 = accent 蓝：与操作标示同色、整列已授权时满列蓝字读作链接；已拒绝 = 橙、受限制 = 灰，同为受阻态分色含糊 | 可用态（granted/enabled/available/lanOK/writeOnly）→ T.success；受阻态（denied/restricted）统一 T.warning；余（未请求/未检测/检测中/未能确定/已关闭/已声明/不可用）→ T.textSecondary。改判 impl_permission_center §五的强调色口径，理由：success 是令牌表 --color-success 单点、本义即成功状态（备份 toast 成功图标已用）；accent 蓝在本页与「可点」同义，作状态色产生误读 | T 令牌表 success 单点定义；语言页状态词「着色只表分组」的克制口径 |
| 4 | 状态字重 | 状态词 12pt semibold，与行题、钮同抢视觉层级 | 改 regular 字重（喂点 f12 不变） | 语言页 rowCard 状态词：12pt、非常态 regular 次级——信息性状态不作操作强调，强调让给动作胶囊 |
| 5 | 动作胶囊 | 请求/去系统设置钮 = 16pt semibold accent 玻璃胶囊（与行题同号、全页最响），且为默认 ButtonStyle、无家族按压形态 | 改 DiagView 胶囊口径逐值：13pt（f13 喂点）regular、T.textMain、内距 横16/纵10、glassControl Radius.pill；本体降为视觉标示（见 #6） | DiagView 历史胶囊钮（13pt regular、textMain、16/10、glassControl pill） |
| 6 | 整行命中 | 动作只在小胶囊上（命中区 ≈ 60×31），行本体无点按反馈；设置族凡有动作的行均为整行钮 | 有动作的行整行成钮：Button + RowPressStyle(radius: 0) + contentShape(Rectangle())，动作经新增 rowAction 单点收口（可请求态 → PermCenter.request；实况 → openAppSettings，深链仍仅此一类）；无动作行（已授权/已拒绝/已声明/探针进行中）保持静态、无钮。胶囊标示随行钮出入 | SetRow 整行 Button + RowPressStyle(radius: 0) + contentShape；DiagView 级别行整行钮同式 |
| 7 | 状态切换过渡 | 状态词更替与胶囊出入全为硬切；通知状态经 getNotificationSettings 异步到达，进页后一拍跳变 | 行内容加 `.animation(.easeOut(duration: 0.15), value: status)`，状态更替、胶囊出入、异步到达跳变同受缓动收口 | RowPressStyle/CardPressStyle 的 0.15s easeOut 为全家过渡惯例值 |
| 8 | 核查无偏离（未改） | — | 节距：首节 topPad 24（SectionHeader 通用默认）、次节 32（与设置主页数据组同型卡组距账 32 一致）；卡半径 Radius.panel、行内距 16/14、分隔线 0.5 borderSoft 横 16、行题/行注字号与色（16 semibold textMain / 12 glassLabel）均与 SetRow 逐值一致，不动。深色：全部颜色走 T 令牌 dyn 对（success/warning/accent/次级均有双值），无裸值，未改 | 设置主页组距账 S1；SetRow 行形态 |

## 二、渲染细节核查

- **Dynamic Type 高档**：图标字形封顶 min(f16, 24) 不溢槽（SetRow 同式）；行注可折行、行高随内容长（无固定高）；胶囊字号由 f16 降 f13 后高档膨胀量显著减小；状态词短文不截断。真机 AX 大字号抽查列终判点。
- **基线对齐**：图标槽 24 与文字栈在 HStack center 对齐（SetRow 同构）；状态词与胶囊在尾部 HStack center 对齐，两行高形态（有/无胶囊）切换经 #7 缓动。
- **入场/滚动**：行内容为静态文本 + 真读状态，高度不随滚动变；进页首读除通知外皆同步面，通知异步到达经 #7 缓动、不再硬跳。
- **五语文案**：未动任何键与文案（PC44-8 仍 48 键全绿）；长文案语种（en/ja 的通知/实况行注）靠 #2 行距与折行承接，不截断关键信息。

## 三、自检（本机）

- swiftc -parse（iPhoneOS 27.2 SDK、arm64 ios16.0 target）：MomentPermissions.swift 零诊断。
- verify_ios.sh 全量：577 ✓；[44] PC44-1..8 全绿（字号喂点 `.system(size: f` 仍恰 5——图标字形走 min(f16, 24) 不入该模式、胶囊改用新增 f13 喂点替换原 f16 喂点，PC44-5 无需改判）；新增 [60] PU60-1..5 全绿（图标映射 13 符号段内锁 / 状态色分组单点锁 / 胶囊标示 + 旧 pillText 零残留锁 / 整行钮 + 嵌套钮零处锁 / 行距·过渡·封顶锁）。
- 余 4 红均非本批：产物陈旧 2（ipa、产物语言包，tree 构建归零）；SB-4/SB-7 为状态栏二轮批在途中间态（其文件面 MomentStatusBar*/MomentSplashHost 与本批零交叠）。tree 全量冒烟随 0.9.63 组版统一跑。

## 四、真机终判点

1. 权限页整体观感：图标列与设置族并置无形态断裂；整列已授权时状态词为克制的绿/灰、无满列蓝字。
2. 点按：未请求行整行可点、按压态与设置行一致；点胶囊与点行任意处行为一致（同一请求）；已授权/已拒绝行点按无反应、无误触弹窗。
3. 请求全程：点行 → 系统弹窗 → 授权后状态词与胶囊以缓动切换（非硬切）；拒绝后回页状态即时更新；切后台再回前台状态重读无跳变。
4. 实况行：整行点按跳系统设置、返回后状态刷新；行注「暂无功能使用」相关文案逐字未动（本页实况行注为使用说明、设置页实况行注定稿句另面核对）。
5. 本地网络行：点行开始检测（状态「检测中…」期间整行不可点）、出结果后缓动落定、可重探。
6. 深/浅两色逐行核对状态色可辨（绿/橙/灰三分组在深色下不混淆）。
7. Dynamic Type 高档（如 AX3）：标题/行注不截断、图标不溢槽、状态词与胶囊不挤压正文列；五语中 en/ja 长行注行距舒展、无贴行。
