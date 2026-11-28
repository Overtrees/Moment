# 组版报告 0.9.68（build 95）

2026-11-28 组版。基线 bdf062c（Web 两线合并部署对账）→ 六条分支全并入 main + 合并对账笔 + 本 release 笔（与版本号 bump 同笔，CI 不变量 WORKFLOW §3.2）。本版主线：0.9.67 装机后桥自办两缺陷回收（标题占位 caret 环、快照计数面）+ 用户四报直修（原生画廊添加缺口与卡内几何改判、开屏白边满幅、安全区全面普查收口）+ 对照壳 App 采样翻车案的状态栏采样完整性根治。合并坐标：5c7c929（标题 caret）/ ffc1025（快照 zip 域）/ c303abc（采样完整性）/ df12611（原生画廊批）/ f49734d（开屏满幅）/ 886fff8（安全区普查）/ febe58d（合并对账）。Web 侧本版不动：main 的 Web 与生产 bdf062c 同树（生产戳 09b75a3d2d、AF 19fdfe520f），不重部署。

## 一、本版内容（按批分组）

| # | 批 | 内容 | 定案 |
|---|---|---|---|
| 1 | 原生画廊批（760f9aa..14beeb2 五笔，分支 fix/native-gallery-batch） | 两端同病同根回收：添加链完好、唯一触发点被空态门死。根治 = 卡编辑态下格网末项后补添加瓦（呈现门单点派生 `addTileShown = editing && !items.isEmpty`、计数 displayCount 派生、点按与空态同一对赋值直达 applyGalleryAdd、模型零改动）；新景 gallery_add_append（EDT-63）。卡内几何改判（用户裁定两端同规）：image/gallery 块行 36 对称内缩退役、瓦对半分填满卡宽，缝收口单一令牌 MediaGeom.gap = 4（与 Web --media-gap 同值），量测 36/36/(W−76)/2 → 0/0/(W−4)/2。图文卡接缝角：源码普查结论复合卡全部接缝子面角位逐项合规、无源码可改，设备截图残余半径 ≈10–12pt 成因 unknown，登记 §四同位复拍；断言侧 GA77-4 逐点位多重集普查补 S23-4 计数锁盲区。B25-11 名集 18→19 | fix_native_gallery_batch.md + audit_native_gallery_add.md |
| 2 | 开屏白边满幅根治（57c8316，分支 fix/statusbar-root-fullbleed） | 0.9.67 定因：状态栏根容器把根内容树整体收进安全区，开屏蓝区恰为安全区矩形、带区露白（首页同病无感）。根治两处：根段 StatusBarRootContainer 补 .ignoresSafeArea()（满幅画布）+ embed() 托管视图背景显式 .clear（防不可确证的默认不透明面）。引擎/参数/开屏本体零改动。新增 SB-17 整行锚定锁（首版子串计数被自身负对照击穿后改整行锚定） | fix_statusbar_root_fullbleed.md |
| 3 | 安全区全面普查收口（9651f8a，分支 fix/safearea-census，基线含第 2 批） | 用户指令「全面根治安全区异常」+ 架构口径「各面自答」：逐面普查（根/窗口、各页顶距、浮动层、键盘、横屏）定案——根层只给满幅画布与运行时 inset 来源，每页/浮动层按自身口径自答；设置族 81、图片页 126 等自答分叉保留。代码落点为防回潮锁而非逐面改码：新增 [78] SA78 五条前提锁（改号见 §二）+ 看门狗浮条前提注记补齐；装机复量三格登记 §四 | fix_safearea_census.md |
| 4 | 标题 caret 环根治（6f8fdc6，分支 fix/title-caret-center） | 0.9.67 桥自办首测：空标题编辑态 caret_centered 实测 23.2（门 ≤1.0）。定案（inferred，算术精确吻合 + 排除法）：UITextField 空文本时插入点落进居中占位行一缘，偏差恰为占位串宽之半（23.2×2=46.4 ≈「无标题」设备档宽 46.6），与字形环（2c2c38e）不同环。根治 = TitleField.caretRect 覆盖收口构造单点：空文本 x 取 textRect midX、非空直通 super（帧/字形/落点三环守恒）。探针新增 s= 选区落点读数 + 短编辑格 edit_caret_on_glyph_block 断言；新增 T24-14 派生普查锁（负对照三组恰红） | fix_title_caret_center.md |
| 5 | 快照计数面四方同源（1b4bee9，分支 fix/snapshot-zip-domain） | 0.9.67 桥自办 drill 首遍步 5 红的真面：工单原判「zip 导出域含已删态行」经域测试实证**不成立**（export 早有 retain 过滤、zip 条目集 ≡ 活篇域、已删篇恢复不复活 proven）；真残差在计数面——清单 memoCount 出应用镜像、zip 条目出 DB 面，镜像/DB 分叉时计数必红且多出行为孤儿。规范域实为四方（清单/verify/zip/计数）。根治 = 铸造端单点：清单计数恒测自产 zip（validateBackup 回读实测条目数入册），不在恢复端过滤。新增域测试 + 新景 snapshot_deleted_rows_restore；SR75 加强、矩阵 DAT-07 | fix_snapshot_zip_domain.md |
| 6 | 状态栏采样完整性根治（ac1d07f，分支 fix/statusbar-sampling-integrity） | 对照壳 App 采样翻车案（跨域取不到像素、容错吞错、回落白卡读数全 241）审计本仓同型面：覆盖门裁剪盲区 proven（适配态像素路径恒不可达；缩放平移态可采带下不存在的图色冒充 src=pixel）+ 失败全塌缩 nil 读数不可辨 + 未就绪无暂缓语义。根治 = 采样三态成型（measured / notCovered / notReady / failed + 四原因码）+ 注册点可见区门（图帧 ∩ 滚动框帧）+ 引擎 imageInput 单点按态消费（未就绪暂缓集 1s 超时兜底带因、候选不跨窗落定）+ Diag px 分账（读数写明没取到还是没解码好，兜底不静默）。新增 SB-18、SB-13 扩五常数、SB-16 计数 3→4 改判入账（图片解析单点化）；负对照三组恰红 | fix_statusbar_sampling_integrity.md |

## 二、合并对账（逐项实测）

- **合并方式**：六并全走临时索引成笔、逐笔核树；六并 ort 策略**零文本冲突**，语义对账为下列各项。
- **断言组号改号**：画廊 GA77 与安全区 SA77 同占 [77]——按先例（SR73 合并改 [75]）**后到者改号**：安全区组改 **[78] SA78**，GA77 留 [77]。同步面：verify 组头与 SA77-1..5 全部锁名、尾注 ALL PASS 清单补 [78]、MomentApp.swift 看门狗注记引用、安全区报告组号说明与 §7、自检矩阵 §7 三格引用（SA78-1/SA78/SA78-2）。另：S23-4 注释引「GA77-5」为画廊线自带悬空引用（实锁为 GA77-4），对账笔一并改正。
- **[53] 组内并存**：SB-17（满幅，第 2 批）与 SB-18（采样，第 6 批）同组并存、互不覆盖；SB-16 计数以采样线改判的 **4** 为准（引擎 resolved ×4），合并树实测绿。
- **景数多面同动**：B25-11 名集 18→**19**（gallery_add_append）、B27-2 注册表九→**十景**（snapshot_deleted_rows_restore）、B67-6 高危恰三→**四景**——合并树逐锁复核计数自洽、全绿。
- **棘轮重算**（[73] 分类器同口径，合并树实测）：CNT **406** / PRES **1408** / FLOOR **34**，与 0.9.67 帽逐值一致、**零增量**，帽不调整。归因：六线新增锁均为机制/普查形态（分类器口径外或同行改字守恒），各线基线自报零增量与合并实测互证。
- **构建遍数**：合并树 build-app2.sh 实测全遍 **34**（MomentFontFactory 引用 34），与基线一致；各文件接线计数锁（=34 系列）全绿。
- **本机门**：verify_ios.sh 全量（合并树、绝对路径）**763 ✓ / 2 ✗**，2 红为已知产物红（ipa 陈旧、产物语言包），tree 构建后自解；源码面归零——含 [53] SB-16/17/18、[77] GA77-1..4、[78] SA78-1..5、T24-14、SR75 加强、B25-11/B27-2/B67-6 新计数、PD73-1 棘轮恰达帽。
- **中继/连接器**：桥工具清单无增减（仍 37 件、哈希 1c2fe22e…）；两新景走 app 侧 uitest 既有通道、不入协议清单，不部署中继。连接器侧前置（CONNECTOR.md 场景目录补 gallery_add_append 与 snapshot_deleted_rows_restore 两名）归 §四前置。

## 三、验证

- **tree 冒烟 / CI / ipa 复验**：结果登记于组版回报（与 0.9.64–0.9.67 口径同：报告不再为此二次改动，以免破坏 bump 同笔不变量）；红先定性分账（源码红/产物红/卫生红）、不改判。冒烟特别盯：storage 计数面改动编译与域测试、采样三态引擎编译、根容器满幅后首启开屏形态。

## 四、桥自办清单（归主线装机后自跑；用户目检项单列）

前置：连接器 CONNECTOR.md 场景目录补 `gallery_add_append`、`snapshot_deleted_rows_restore` 两名后再跑相关景。

1. **画廊加图（本版首验，主线承诺先桥验通再交用户）**：新景 gallery_add_append 首跑（EDT-63）——夹具 1 项 → 追加 2 → 尾附序/新瓦出图/落盘回读/重进仍在全断言；编辑态添加瓦呈现与真点按归用户终判。
2. **图文卡接缝角同位复拍**：0.9.67 用户截图同位（图文卡图区底部两角）复拍判读——源码为直角（bl/br=0），截图残余半径 ≈10–12pt 成因 unknown，复拍定级。
3. **开屏/首页带区像素格**：冷启开屏顶/底带应为品牌蓝（非白带）；首页顶/底带应为 #DAE3F0。归桥截图/用户目检。
4. **标题四格**：title_center_geometry 四格全跑——占位格 caret 应自 23.2 落 ≤1.0；短编辑格 edit_caret_on_glyph_block 取首个设备数值；短展示/长截断两格回归对照（glyph 1.0 / field 0.0 不回退）。
5. **快照（删过的库）**：snapshot_restore_drill 在删过备忘的库上连跑两遍应全绿（计数面根治的验收形态）；新景 snapshot_deleted_rows_restore 首跑；收尾 orphans=0、夹具不复活。
6. **安全区复量三格**：图片页 availH 回读 = 屏高 −126 −40 −safeBottom 对账；横屏带区同色与挖孔侧净空；编辑键盘 kbPad 回读与 Done 胶囊键盘落下后收回（0.9.56 latch 面）。
7. **采样四格**：图片页适配态 Diag 恒 px=notcovered（不出 src=pixel）；放大上移后不得出现以不存在图色冒充的 src=pixel；图片加载窗内应见 defer/fallback 带因行（notReady/原因码）；SVG 页 px=failed:noraster。
8. **回归子集**：S1 title_capsule_reedit、drag_pickup_statemachine、image_page_open_cards、U5 home_surface_roundtrip 抽查；STATUSBAR answerer live 实读；端内清单哈希与中继 1c2fe22e… 对账；零净变化收尾（count/hash/pending/orphans）。
9. **遗留终判（用户）**：状态栏外观切换整格已于 0.9.67 装机后设备行 + 目检双面关闭，本版仅回归抽查不重开。
