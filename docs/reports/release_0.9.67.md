# 组版报告 0.9.67（build 94）

2026-11-28 组版。基线 8dc2842（偿还批四收官）→ 六条分支全并入 main + 合并对账笔 + 本 release 笔（与版本号 bump 同笔，CI 不变量 WORKFLOW §3.2）。本版主线：0.9.66 装机后桥自办的定案回收（标题字形环、快照线两缺陷）+ 用户三报直修（状态栏原生适应含外观切换补案、Diag 两页打开慢、浅色默认背景改判）+ 补丁债偿还批一~四的合并入账（批一/二/三/四已在基线内）+ Web 浅色背景同步入账。合并坐标：880001a（Web 背景）/ 00e7733（标题字形）/ e956772（浅色背景）/ 6104f34（Diag 性能）/ e071005（快照线）/ 4ae3da5（状态栏）/ ffcf5ee（合并对账）。

## 一、本版内容（按批分组）

| # | 批 | 内容 | 定案 |
|---|---|---|---|
| 1 | 标题字形环根治（2c2c38e，分支 fix/title-glyph-center） | 0.9.66 桥自办分环定案：帧环已正（fieldCenterDev 0.05）、字形环偏 15.0–16.2——文本本体经 plain 赋值后按 defaultTextAttributes 物化绘制，而 applyFont 的属性字典独缺段落样式（占位串独有、文本本体没有，同构造点两呈现者只给其一）。根治 = applyFont 内居中段落样式收为一份构造 centerPara，文本本体与占位共用；新增 T24-13 机制锁（负对照实做） | fix_title_glyph_center.md |
| 2 | 状态栏原生适应（e3c1d06 + 补遗 a60ff67，分支 fix/statusbar-native-adaptation） | 用户 14:41 改判方案落地：容器统一回答（根容器为全应用唯一 preferredStatusBarStyle 实现者、childForStatusBarStyle 恒 nil、原根视图整体内嵌不换根）；判定引擎单源（相对明度 + 阈值 0.45 / 去抖 48ms / 驻留 120ms / 淡变 160ms 状态机、翻转 Diag 行 + answerer live 链活证）；像素保底独立文件仅挂图片页（CGImage 1×1 点取带 EXIF 映射 / CALayer 离屏 / 视频帧），整屏截图入断言禁区（负对照实做）；开屏渐变以停点数据自答。补遗：外观切换确定性通道——trait 变化即重算直落、不进可取消候选（定案：旧路径把一次性 trait 事件喂进可取消候选机、翻转可静默丢失，与用户实报同构）；数据面按当前 trait 解析有效色经普查证实零改、加 SB-16 锁防回潮 | impl_statusbar_native_adaptation.md + fix_statusbar_appearance_trigger.md |
| 3 | 快照线两缺陷根治（27cff39..8c06f89 五笔，分支 fix/snapshot-restore-domains） | 缺陷一：Library.reload 镜像发布恒异步主队列——桥恢复同步返回时镜像仍是换库前态，drill 步 5 必误读、收尾清扫扑空后迟到发布又把已删夹具在列表「复活」而登记已注销（残留对卫生检查不可见）。根治 = 主线程调用同步落定，不变量「主线程 reload 返回 ⇒ 镜像与库一致」；清理守卫补验净（逐篇删后回读确认消失才注销、残留升级 hygiene_failed）。缺陷二：清单哈希/恢复 verify 同走含待删标记行的全行域、ZIP 收录与计数却是活篇域——待删窗内铸的快照永不可恢复。规范域定为「可恢复活库域」（与 export 收录域恒等），storage Store::library_hash 单点三方同源；旧快照影响面：干净态铸者新旧域逐值恒等、窗内铸者旧口径下本就不可恢复（非本批打破）。新景 snapshot_pending_window_restore + 矩阵 DAT-05；断言 [75] SR75-1..5（原 SR73，改号见 §二） | fix_snapshot_restore_domains.md |
| 4 | Diag 两页打开慢根治（a137742，分支 fix/diag-page-perf） | 定案三层相乘：两页非惰性 VStack 首帧同步建全部行（现网 1094 / 满环 2000、可见仅约 24/41）；每行格式化逐次新建 DateFormatter（开页千次级重型构造）；DiagView 直挂观察 DiagLog、打开期间全应用每写一行整页全价重演。根治 = 格式化静态单例（DiagEntry dayFmt/timeFmt + DiagLog stampFormatter）、两页 LazyVStack、DiagView 改呈现快照模型（DiagUI 持 todaySnap/archSnap、refreshSnap 单点；视窗入参/导出/自检面动作时刻直读守恒新鲜度）；拼装计数 lineFormatCount + DIAGPERF open 基线行供桥侧对账。容量 2000 行不回退、无占位遮丑。断言 [76] DP76-1..5（原 DP73，改号见 §二；负对照五项各红恰一） | fix_diag_page_perf.md |
| 5 | 浅色默认背景改判（6bb2db0，分支 fix/light-bg-dae3f0） | 用户裁定全应用浅色默认背景 #F2F2F7 → #DAE3F0：根令牌 T.bg/T.bgUI 浅值单点（深色逐字不变、备忘自定义背景不动、无自定义色备忘经派生回落随新值）；普查证实无页面自带旧值字面量、收口即令牌改值本身。开屏按用户裁定暂不动（品牌蓝/停点表/降级件未碰），退出交接色差台阶为已裁定暂时状态、单项登记。断言 [74] BG74-1/2（值锁 + 旧值残留集 == 开屏降级件豁免集；负对照实做） | fix_light_bg_dae3f0.md |
| 6 | Web 浅色背景同步（a0530a7 + 746021a，分支 fix/web-light-bg-dae3f0） | Web 根背景令牌（tokens.css --primary-bg）浅值改 #DAE3F0 + 启动页内联底色同值（字面量与令牌恒等锁）；自定义背景与深色不动。已自分支部署生产（戳 5ff8c91ac5、LIVE == ARCHIVE 对账毕），本版只入账合并（见 §二 Web 条与 §三冻结登记） | fix_web_light_bg_dae3f0.md |

## 二、合并对账（逐项实测）

- **合并方式**：六并全走临时索引 + commit-tree 双亲笔，逐笔核树；开工前主工作区陈旧共享索引以 read-tree 对齐 HEAD 后归零（工作区与 HEAD 逐字一致、无内容丢失）。
- **冲突处置**：Web/标题/浅色三并的 verify 冲突经真基 merge-file 零冲突解；Diag/快照两并各 1 处尾部组冲突人工解（组序落定 73/74/75/76）；状态栏并 3 文件冲突——MomentApp merge-file 零冲突，build-app2.sh 以集合并集重构（见遍数账），verify 7 处冲突逐项解（DT46-6 取主线集合对账版、SB-1 取分支改判版、计数锁按实测落值）。全程无行为取舍型冲突，未触发停并上报。
- **断言组号映射**：[73] = PD73（主线既有，棘轮）；[74] = BG74（浅色背景线）；快照线 SR73 → **[75] SR75**；Diag 线 DP73 → **[76] DP76**。组内编号与 verify/矩阵（plan_selftest_coverage DAT-05 等）引用同步改；各分支报告原文不回改，映射以本表为据。尾注组表补全 [73][74][75][76]。
- **棘轮重算**（[73] 分类器同口径逐行实算）：CNT 394 → **406**、PRES 1388 → **1408**、FLOOR 34 不变；帽随合并实测设至 406/1408，PD73 沿革三注记。归因：CNT 净 +12 全为状态栏线 [53] SB-11..16 机制普查（新增计数形态 16、SB-1/2 改判摘除 4）；各组计数锁改值（31/33→34）为同行改字、净 0。PRES 净 +20 = 状态栏线 [53] +18、标题线 [24] T24-13 +2。
- **构建遍数重算**（合并后 build-app2.sh 实测）：全遍 **34**、每遍输入集恒等（34 文件、集合对账 DT46-6 通过）；小组件两遍恒等 {MomentLiveOpsWidget, MomentLiveOpsAttributes}（状态栏三文件未入 appex 面）；MomentFontFactory 出现 **34**（状态栏报告预估 33 已被偿还批三 SvgRaster 遍补接 + 本轮 BlockKind 遍入账 supersede，以实测为准）；状态栏三 .o 与 splash_host.o / blockkind.o / treewait.o / undo.o 各 ×2。联动计数锁按实测 34 落值并注沿革：SB-2、B16-23、E47-8、X50-7、PD71-4、PD72-3（DT46-6 为集合对账、无基数可改）。
- **B27-11 合并对账**：快照线新景构造器声明折行（private static func 与函数名分行），批四普查的单行声明正则漏检、报 defined!=referenced——定案为普查口径问题（构造器实装、mainSteps 分发在位、B27-10 注册↔分发恒等通过）。普查正则改 \s+ 容差容折行、构造器数改判十（ffcf5ee）。
- **小组件污染哨**：build 并集重构中一度把状态栏三文件插入小组件两遍输入集，普查当场抓出并剔除（终态两遍恰 {Widget, Attributes}）——DT46-6 集合对账即为此设。
- **Web 入账对账**：合并树 Web 面（rust/apps/web + scripts/verify_rustweb.sh + CHANGELOG/CONTEXT）与已部署分支 746021a **逐字恒等**（git diff 为空）——合并未引入任何 Web 内容变化。
- **中继/连接器**：桥工具清单无增减（仍 37 件、哈希 1c2fe22e…）；新景 snapshot_pending_window_restore 走 app 侧 uitest 既有通道、不入协议清单，不部署中继。连接器侧前置：scenarios_run 的 ALLOWED_TOOLS 需补新景名（连接器 CONNECTOR.md 场景目录已由快照线就地更新），归 §四桥自办前置。

## 三、验证

- **本机门**：verify_ios.sh 全量（合并树、绝对路径）**749 ✓ / 2 ✗**，2 红为已知产物红（ipa 陈旧、产物语言包），tree 构建后自解；源码面归零——含 [53] SB-1..16、[74] BG74、[75] SR75、[76] DP76、B27-11 十构造器、PD73-1 棘轮（实测恰达新帽）、DT46-6 集合对账。cargo test --workspace 结果见组版回报（storage/FFI 改动面：FFI 仅改函数体、UniFFI checksum 契约不变，冒烟 FFI 重建段复核）。
- **tree 冒烟 / CI / ipa 复验**：结果登记于组版回报（与 0.9.64–0.9.66 口径同：报告不再为此二次改动，以免破坏 bump 同笔不变量）；红先定性分账（源码红/产物红/卫生红）、不改判。冒烟特别盯：状态栏三文件首编译、SvgRaster 遍补列 FontFactory 后构建、快照线 storage/FFI 编译与 checksum 契约。
- **Web 生产（冻结登记）**：生产现戳 5ff8c91ac5（webbg 分支部署）。**2026-11-28 15:38 主线口径：生产出现「卡在启动页」实报、疑与刚部署的 webbg 构建有关、排查中——本轮严禁从合并树重部署 Web**，「不等则重部署」一条冻结，等主线定案后另行指示。本轮合并树 Web 面与已部署内容逐字恒等（§二），冻结不影响入账；解冻与重部署与否归主线后续笔。

## 四、真机终判点（汇全，归用户装机后验；桥自办项由主线装后自跑）

前置：连接器 ALLOWED_TOOLS 补 snapshot_pending_window_restore 后再跑快照三件。

1. **标题居中（五修首验）**：桥跑 title_center_geometry 四格全跑——短展示格 glyphCenterDev 应自 15.0/16.2 落至 ≈0（≤1.0）、fieldCenterDev 维持 ≤0.5；短编辑格为编辑态首个设备数值；长截断/占位两格回归对照。用户目检：真实短标题两态居中。
2. **状态栏（本版首验）**：桥回读 Diag `STATUSBAR answerer live` 有行 = 转发链活（无行则回退评估触发）；翻转行 `STATUSBAR flip … src=data|pixel` 与目检一致。用户目检：深/浅外观各页明暗正确；**编辑页浅色自定义背景 → 切深色模式 → 零滚动即翻白字**（Diag 须见 trigger=appearance 或 STATUSBAR appearance 行）、反向同理；图片页深/浅照片、滚动跨区不抖；开屏两形态字色与退出回落。
3. **快照线（本版首验）**：桥跑 snapshot_restore_drill 两遍（步 5 应转绿、失败路径零残留抽查）、新景 snapshot_pending_window_restore 首跑、待删窗直调 backup_restore_snapshot 恢复复验（应成功、哈希同域）。
4. **Diag 性能（本版首验）**：桥读两页 DIAGPERF open 基线行 + 开页前后 fmtCount 增量（应为可见行量级、非 N 量级）；用户目检：诊断页/日志视图点开明显变快、页内操作不发沉、滚至末行无空白错位；快照语义目检（桥记新行卡面不尾随、重进可见、导出仍含新行）。
5. **浅色背景（本版首验，用户目检）**：浅色外观下首页/编辑页（无自定义色）/设置族/桥设置/权限/诊断/日志/图片页/救援面底色一致 #DAE3F0；深色外观不变；自定义背景备忘不变；开屏仍品牌蓝、退出交接台阶为已裁定暂时状态（不作缺陷报）。
6. **回归子集**：S1 title_capsule_reedit、drag_pickup_statemachine、image_page_open_cards、U5 三景各一遍抽查；端内清单哈希与中继 1c2fe22e… 实读对账。
