# 组版报告 0.9.64（build 91）

2026-11-28 组版。基线 cf87bd3（0.9.63 发布笔）→ 本版 80 笔（各线逐批成笔 + 组版收齐/小项 11 笔）+ 本 release 笔（与版本号 bump 同笔，CI 不变量 WORKFLOW §3.2）。本版主线：0.9.63 装机反馈三项处置（标题居中二修 / 权限页六项 / 状态栏全页回退）、全面审计余批清账（批 3 媒体解码 / 批 4 编辑器遗留 / 批 5 i18n I4·I5 / 批 6 首页细项与账本）、卡片防误触机制统一扩展、桥自办实测立项两件（undo 步 5 根治 / M3b 写景落码）、自检矩阵 U2/U3/U5 落码与中继清单 36 件。Web 本轮不动生产（见 §三）。

## 一、本版内容（按线分组）

| # | 线 | 内容 | 定案 |
|---|---|---|---|
| 1 | 状态栏全页回退 | 三轮渲染采样整层拆除（MomentStatusBarRender.swift 整文件删、BandRenderSampler 与根承载容器一并拆）、全页回到登记色 evaluate 单点、开屏恢复公式色承载（MomentSplashHost bandColor）；保留开屏 iPhone 方向锁（SB-8）与 CIELAB L* 61.65 度量；verify [53] 按回退口径改判；本机+tree 零残留普查 11 符号全域零命中 | fix_statusbar_rollback_all.md |
| 2 | 标题居中二修 | 短标题 × 宽 meta 非截断预览偏心根治：字段有效帧实测 = 内容宽且坐行左缘（上版前提 P2 被真机证伪），titleCapsule 字段加显式满宽帧单点、与协商宽脱钩；T24-9 补本案量测格 + T24-10 字段满宽帧机制锁 | fix_title_capsule_center2.md |
| 3 | 权限页装机反馈六项 | 「暂无功能使用」行注改为请求后才显；删请求钮旁「未请求」文本；副标题五语缩短；实况「去系统设置」可见文本去除（深链动作保留）；请求钮统一改 SVG 引导图标（PermGuideGlyph 新字形、pillLabel 退役零残留）；已声明组归类改写（后台任务 = 声明即生效、远程推送改注「发送需账号配套」）；组版追加 intro 句口径对齐（请求后才标注） | fix_permissions_feedback63.md |
| 4 | 审计批 3 媒体解码 | AUD-D-01 定性 proven：解码侧无病、块内五面（图块/gallery/图文卡两面/MD 图）以 SwiftUI Image 只呈首帧——AnimImageView 五面统一承载；解码管线收口 MediaDecode 单点（共享缓存 96MB / 解码即降采样、块内 2048 桶、图片页全尺寸；旧 decodeImage 退役零残留）；AUD-D-04 视频改轨道自然比例 + 失败三出口补失败面与 Diag；新增 [64] MD64 | fix_audit_batch3_media.md |
| 5 | 审计批 6 首页细项 + 账本 | A-01 封面 URL 白名单单点 safeCoverURL；A-04 页眉命中死区阈值改判；A-05 网格组头 uppercase；A-06 图文方卡折叠钮收口 squareFoldPill 单点；A-07 四动作补辞焦；账本回写（矩阵 HOM/LCH/BRG 多行与总册对齐、断言基数三方量测归因）；新增 [65] HM65；线 B 三项口味候选只登记未动（待用户裁） | fix_audit_batch6_home.md |
| 6 | 审计批 4 编辑器遗留 | 依赖映射结论：九项无一真依赖 E5/E6、全量落地。F-13（丢字类）链接表单改提交时才剥 token、取消/Esc 零改动；B-04 URL 抑制逐字对齐 Web；SL-16 链接校验改解析+协议白名单；B-01 公式块围栏保正文；B-06 sheet 唤起前清斜杠态；M-09/M-10/F-16/B-03 拖拽与面板锚诸项；新增 [63] EB63 | fix_audit_batch4_editor.md |
| 7 | 卡片防误触统一 | 普查全块型后接入两型：codeBlock（四向键盘溶解守卫 + 拾起卡菜单）与 embedCard（原子兜底块归一路由）；分类单点 isStructuralAtomic 被四合并函数/F-08 描边/菜单路由同点消费、无逐型特判；成员集 9→11 型；代码块拾起菜单由类型转换菜单改删除单项（转出路径退役、已登记）；新增 [66] CG66 | impl_card_guard_unify.md |
| 8 | undo 步 5 根治 | 0.9.63 桥实测立项：选区替换落 600ms 合并窗内被爆发链吞并（多退一层 + 选区落爆发锚点）。核心 noteTextWillChange 增 breaksBurst（判别 = range.length > 0 && !replacement.isEmpty，纯删除/退格/粘贴口径不变）、模型与三放行点穿 replacement；E47-3 补 h7/h8 复刻 + 负对照（摘守卫恰红三条）；E2 §三规则表回写「选区替换断链」 | fix_undo_step5_selection.md |
| 9 | 审计批 5 = i18n I4/I5 | 斜杠 24 项存键（titleLangKey/subLangKey，与 Web 存键同构）+ 残余硬编码约 50 调用点换键；五语 441→463 键、深检退出码 0（僵尸零、7c 同值 77 对逐键定性登记 + 棘轮断言）；全量 CJK 门转正（未归类判红、fail-closed）；组版追加开屏 a11y 换键 app.splash_icon_aria（463→464）并销 CJK 门 W2 白名单 | impl_i18n_i4i5.md |
| 10 | 自检矩阵 U2/U3/U5 | 六探针实装（UITestProbes 替换 measure 壳）、U3 drag_pickup_statemachine 景、U5 五景与十面注册（home/settings/bridge/image + RowFrameStore）；新工具 metrics_drag_trace 出货（清单 35→36、中继已部署、清单哈希 c75689d5…）；新增 [68] U68 | impl_selftest_u2u3u5.md |
| 11 | 桥 M3b 写景 | 三景实装注册：delete_restore_roundtrip（恢复守卫：待删集最近一篇须为夹具才恢复）、drag_semantic_reorder（内部同路移块 + 重开在席再断言）、create_transition（settle 护栏、超限标 degraded）；snapshot_restore_drill 只注册描述符——前置工具 backup_restore_snapshot 全仓未落，availability=wiring_missing、run 受理即拒（不假成功），补完路径留账；新增 [67] B67；矩阵四景行状态与连接器场景目录已回写 | impl_bridge_m3b_scenarios.md |
| 12 | 组版收齐与小项 | 索引重建与未提交 hunk 收齐（undo 接线、[66] 组、B-06 落位、残余空行）；T24-5 锁同步（editor.untitled）；verify 中段汇总块归位真尾；HM65-5 基数改判（见 §二） | 本报告 §二 |

## 二、组版收敛项（逐项办结登记）

- **索引卫生**：开工时共享索引被并行期污染（暂存着 M3b 前旧版场景文件与 M3b 报告的暂存删除，原样提交会回退 M3b）——以工作区为准 reset 重建索引，全部脏 hunk 逐一归属到线、零无主残留。本轮全部提交走临时索引 + 内容过滤 + 提交后核树（并行期禁普通 add/commit 的纪律延续，批 4 报告 §三教训）。
- **未提交收齐**：undo 线 MomentApp 5 hunk + verify 3 hunk（标记 breaksBurst/replacement/E47-3）拆出单提；卡片守卫 [66] 组本体在尾部共享追加区，拆出单提；[65]/[67]/[68] 三组已由各线在批内入史（与开工清单的预估差异在此登记：尾组实际只余 [66] 待收）。批 4 B-06 的 onChange 落位修复（文件尾误置副本删除 + EditorView 本体归位）残存工作区，一并收齐。
- **i18n 侧分支合并**：batch/i18n-i4i5 五笔 cherry-pick 入 main（其工作区同内容副本先行丢弃）；合并后 MomentApp.swift / verify_ios.sh 与合并前工作区参照逐字节等值（核树通过），i18n_deep_check 退出码 0。
- **HM65-5 基数改判（组版定性）**：本机全量 verify 独红 HM65-5。回源定性（proven）：U5 home.row 注册面的同体动作（pin/delete，与网格菜单同体、同样辞焦）在批 6 写锁之后落码，使两段 awk 窗口内 resignSearch() 计数 2→4——辞焦机制无损、纯断言基数漂移（U 批回写 F30-2/PC44-6 时漏及本组）。改判 4/4 并注沿革，组版成笔。
- **verify 结构归位**：脚本中段（[64] 后）的 ALL PASS/exit 汇总块使 [65] 后各组在全量跑遇红即不可达——删除中段块，汇总收尾单点归脚本真尾（尾块含 [65]–[68] 判读），最小改动、行为等价。
- **归属混杂三起（均不改写历史，登记在案）**：批 3 be0ac74 带入编辑线 delegate 签名 hunk、批 6 d9fe880 带入回退线 46 行删除、批 4 12826cb 误提（已由 112cd9c 自行逐字修复）；三起内容均逐字无损、仅提交归属错位，后续各线已改用内容标记选 hunk + 计数断言。
- **tree /data 余量注记**：组版时点 tree /data 余约 1.7G（91%），根分区余 8.9G 健康；冒烟产物量级不构成阻塞，未在本轮扩容。

## 三、验证

- **本机门**：cargo test --workspace 全绿（0 failed）；verify_ios.sh 全量 689 ✓ / 3 ✗ → 其中 HM65-5 经组版改判后源码面归零（见 §二），余 2 红为已知产物红（[5] ipa 陈旧、[9] 产物语言包），tree 构建后复跑消除； i18n_deep_check 退出码 0（合并后与换键后各跑一次）。
- **签名工具**：macho-entitle 本机源码与 tree 副本 md5 同为 c2cf6bb7118512690c7692e0cc31014f（与 0.9.63 基线一致），构建前核对通过。
- **中继**：bridge/relay 经 deploy.py 部署（PUT 200），GET /health = version 1.1.0；list-tools 清单 36 件含 metrics_drag_trace（清单哈希 c75689d5…，待 0.9.64 装机后与端内对账）。
- **tree 冒烟 / CI / ipa 复验**：结果登记于组版回报（与 0.9.63 的 CI 口径同：报告不再为此二次改动，以免破坏 bump 同笔不变量）；红先定性、不改判。
- **Web 生产**：本轮不动生产。lang 真源变更（+23 键、perm.intro 五语文案）均为原生消费面（斜杠/权限/开屏 a11y），Web 应用代码零 diff；生产构建戳维持 9b2efd68ee，待后续 Web 批随版带入。

## 四、真机终判点（汇全，归用户装机后验；桥自办项由主线装后自跑）

1. **开屏三无（状态栏回退验收）**：冷启开屏不闪白、不透出首页空态、结束不闪黑；开屏 iPhone 锁竖屏不回归；iPad 不受影响。Diag 应只见 `STATUSBAR bg=#RRGGBB` 登记色行、无 `bg=render` 行。
2. **标题居中二修**：短标题 × 宽 meta 篇（「使用指南」案原样）预览态标题居中；截断态居中不回归且点按落点与全文映射同位；编辑态、紧凑横排态短标题居中。
3. **块内 GIF 五面**：图块 / gallery 瓦与封面 / 图文卡两面 / MD 图内的 GIF（及 APNG/WebP）播放与帧速；大图滚动流畅度；动图面手势不吞（点按/长按拾起照常）。竖屏视频自然比例与加载失败面呈现。
4. **卡片防误触**：长按拾起代码块 / embedCard 出卡菜单（删除单项）；四向键盘守卫手感——代码块段首退格不并出、段末前删不吸收、邻接段退格撞代码块只选中带描边、列表首/末项合并同守；代码打字/换行/粘贴无回归。转出代码块的菜单路径已退役（转入不受影响、撤销可恢复），目检确认无困惑。
5. **undo 桥复跑（装后自办）**：undo_redo_roundtrip 步 5 转过（选区替换一撤恰回替换前态、选区 = 被替换范围），步 1–4/6/7 不回退。
6. **M3b 三景桥实跑（装后自办）**：delete_restore_roundtrip / drag_semantic_reorder / create_transition 逐景连跑两遍口径验收；snapshot_restore_drill 在 scenarios_list 现形 wiring_missing 为预期态（工具落地批前不算失败）。
7. **U 探针与六景桥实跑（装后自办）**：U2 几何探针、U3 drag_pickup_statemachine、U5 五景（home_search_cycle / home_surface_roundtrip / home_list_actions / image_page_open / settings_surface_roundtrip）首跑判读；S1 两遍复跑不回归（BRG-09 口径维持）。
8. **沿革挂账（0.9.63 §四未验项续）**：八色深形态白字目检、前向删除手感、设置族顶距 81 体感、A-08 横幅间隔、恐龙构图、配对全程不跳 Safari、Web 图片页可用区观感——随本版一并目检。
