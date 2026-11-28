# 组版报告 0.9.66（build 93）

2026-11-28 组版。基线 0db9a56（0.9.65 组版修复笔）→ 本版入料 4 批 5 笔 + 开屏分支合并笔 + 本 release 笔（与版本号 bump 同笔，CI 不变量 WORKFLOW §3.2）。本版主线：0.9.65 装机用户实报三件根治（开屏闪空态/闪黑、标题短字不居中、图片卡点按进不了图片页）——四批同批收口，其中开屏批走独立分支重构、标题居中三修+四修两连、图片批带 [70] 断言组与新景。Web 本轮无实改，不部署（见 §三）。

## 一、本版内容（按批分组）

| # | 批 | 内容 | 定案 |
|---|---|---|---|
| 1 | 标题占位居中三修（dc1d543） | 空标题时胶囊内呈现的是字段占位串，其绘制对齐只认属性串自带段落样式、构造时从未给过 → 缺省左排；字段 textAlignment 管不到占位串。根治 = 占位串构造单点（TitleTextField.applyFont）钉 NSParagraphStyle .center 入串，两态同构；T24-9 补 untitled-placeholder 格、新增 T24-11 机制锁（负对照实做：摘段落样式 T24-11 恰红） | fix_title_center_short.md |
| 2 | 图片卡点按回归根治（36b1355） | 定案 proven（git 证据）：审计批 3 的 d272e80 五面换 AnimImageView 承载，image 块是五面中唯一靠叶子天然命中体的一面、行无 contentShape，承载恒关交互后命中体消失、点按恒不达。根治 = 路由收口单点 EditorModel.presentImagePage（五入口全经单点）+ ImageBlockView 已载图分支补 .contentShape(Rectangle()) 显式命中形；新增 verify [70] TP70-1..5 锁机制 + 新景 image_page_open_cards 三腿；T-1/SVG42-3 计数口径随收口改判注沿革 | fix_image_tap_regression.md |
| 3 | 标题真实短标题四修（5a0d244） | 用户纠正：不只是占位、真实短标题也不居中。帧链端到端定案：坏环在「行 → 字段帧」——representable 平台帧随 sizeThatFits 回告走，二修的弹性帧（.frame(maxWidth:.infinity)）在设备上证伪（帧仍为内容宽坐行左缘）。根治 = 字段改定宽帧 .frame(width: capsuleWidth - 40)（帧宽由胶囊定宽值派生、不再经协商）；T24-9 废自证模型改判（帧构型为外部入参、期望值来自设备像素量测）、T24-10 构造锁换代、新增 T24-12 跨点同源锁；设备侧量测钩子落地：title_geometry 探针（UITestProbes 第七件）+ title_center_geometry 场景四格（矩阵 EDT-62），装机后首次以设备数字验收居中 | fix_title_center_short_text.md |
| 4 | 开屏闪现根治（e6b9d0c，分支 fix/splash-flash-sequence，合并笔 e303f09） | 旧归因（根承载换根）被 0.9.65 实报证伪后自帧序列重定案：病灶 = 二轮呈现式承载结构本身——症状 A（空态闪）是入口接缝（根先行入窗渲染、呈现晚 1–2 事务，间隙帧露出无就绪门的空态首帧）；症状 B（闪黑）是出口接缝（.fullScreen 呈现退场向从未设色的黑窗口淡出后硬切）。重构 = MomentSplashHost.swift 整文件重写：单承载（根 ZStack 内 SplashLaunchLayer 随首帧同帧在位）、单退场（opacity 淡出、其下恒为首页本体，无 dismiss/硬切）、窗口底色单点（LaunchChromeProbe 同源色）、空态就绪门（两处空态加 && library.didLoad）、SB-8 方向锁决定面迁应用委托掩码门、SPLASH phase 五行相位打点；节奏硬约束（用户 13:22 裁定）逐项未动——静止 500ms / progress 线性 1.0s / 再等 1.0s / 淡出 easeOut 0.26s，SB-10 锁；SB-8 改判、新增 SB-9 序列不变量、DM45-1 双文件口径改判 | fix_splash_flash_sequence.md |

## 二、组版收敛项（逐项办结登记）

- **基线复核**：开工 main = 5a0d244、工作区有开屏批在途副本与陈旧共享索引（多方涂改态）。处置：工作区 10 个改动路径先全量快照留 /tmp，再逐个对账——7 件与 HEAD 逐字一致（纯索引噪声）、MomentSplashHost.swift 与分支版逐字一致、MomentApp.swift 与 verify_ios.sh 待合并验证（见下行）。
- **开屏分支合并（本版最大风险点）**：在临时 worktree 以 5a0d244 为基三方合并 e6b9d0c——**自动合并无冲突**（分叉后三批与开屏批改动区域不重叠，工单预期的 MomentApp/verify 冲突未发生）；合并树与主工作区联合态逐字对账：MomentApp.swift、MomentSplashHost.swift **逐字一致**（证明工作区在途副本全被分支覆盖、丢弃无损），verify_ios.sh 仅文件头注一处沿革差异（分支新版「单承载序列文件」胜出，工作区旧注为采样去除期文本，功能面零差异）。合并笔 e303f09 经快进回 main，工作区残留与陈旧索引一并清零（status 归零）。
- **中继/连接器**：本版无新桥工具——`git log 4e023aa..HEAD -- bridge/ MomentBridgeProtocol.swift` 零改动，清单仍 37 件、哈希 1c2fe22e… 不变；title_geometry 探针与 image_page_open_cards 场景均为 app 侧 uitest 既有通道（uitest_measure / uitest_run_scenario）内的增量，不入协议清单。**不部署中继**，连接器无需改动（装机后端内清单哈希实读对账在 §四挂账）。
- **tree 同步与普查**：push_small 全量传输（57 文件逐个 md5 对账全 OK）；overlay → 克隆按名单逐个 cp（禁通配）；普查：克隆 app 目录 35 件与本地文件集逐字一致、全量 md5 多重集摘要双边同值（e4fe72af…）、关键文件（MomentApp / MomentSplashHost / MomentBridgeUITest / TitleTextField / TitleTapCaret / verify_ios.sh / build-app2.sh）md5 逐个全等；克隆内无 MomentStatusBar* 残留（0.9.65 删净、本轮复核在位）；克隆 build-app2.sh 已为 0.9.66 / build 93；tree /data 余约 1.7G（91.3%），与前两版同水位
- **签名工具**：macho-entitle 本机源码与 tree 副本 md5 同为 c2cf6bb7118512690c7692e0cc31014f（与 0.9.63–0.9.65 基线一致），构建前核对通过
- **bump 两处**：build-app2.sh（0.9.66 / build 93）+ 设置页版本文本（MomentApp.swift），与本报告同笔；bump 先落工作区再随 push_small 传输，tree 克隆内即本版号构建。

## 三、验证

- **本机门**：cargo test --workspace 全绿（239 passed / 0 failed，本版零 Rust 改动）；verify_ios.sh 全量 **705 ✓ / 2 ✗**，2 红为已知产物红（[5] ipa 陈旧、[9] 产物语言包），源码面归零——含 [53] SB-8 改判 / SB-9 / SB-10、[70] TP70-1..5、[24] T24-9 改判 / T24-10 / T24-11 / T24-12、DM45-1 改判、[69] HR69-7、[1] 版本三处对账。注记：verify 须以绝对路径调用（脚本 cd 至自身目录后 B25-10 自读 $0，相对路径调用会令该条假红——本轮首跑实证，绝对路径复跑转绿；脚本本体未动）。
- **tree 冒烟 / CI / ipa 复验**：结果登记于组版回报（与 0.9.64/0.9.65 口径同：报告不再为此二次改动，以免破坏 bump 同笔不变量）；红先定性分账（源码红/产物红/卫生红）、不改判。
- **Web 生产**：本轮无实改——`git log 4e023aa..HEAD -- rust/apps/web` 零提交（四批全在 iOS app 面），**跳过部署**，生产戳维持 1b3eee9998。

## 四、真机终判点（汇全，归用户装机后验；桥自办项由主线装后自跑）

1. **开屏（本版首验）**：冷启全程三无——无首页空态闪、无结束闪黑、无节奏变化感（总时长与节拍与 0.9.65 无别）；装后桥回读 Diag `SPLASH phase` 五行（show/data/timeline/exit/end），核相位间隔与「间隙帧无空态、无黑帧」的结构预期（exit 行附 data/timeline 两戳）；开屏 iPhone 方向锁（SB-8 迁委托掩码门后）不回归、iPad 不受影响；状态栏回系统默认（0.9.65 终判点 1）同轮目检。
2. **标题居中（本版首验，首次数字验收）**：桥跑 `title_center_geometry` 场景两遍——四格（短标题展示/编辑、长标题截断对照、空占位格）偏差数值入组版回报后续登记：fieldCenterDev ≤ 0.5、字形格 glyphCenterDev ≤ 1.0、占位格 caretDev ≤ 1.0；`uitest_measure title_geometry` 直读复核。用户目检：空标题展示态占位居中、真实短标题两态居中、长标题截断态与点按落点不回归。
3. **图片卡（本版首验）**：桥跑 `image_page_open_cards` 场景首跑（图块 fileId 形 / URL 形 / 图文卡图区三腿经路由单点开页）；用户真机真实 tap 终判：点图片卡进图片页、长按拾起与卡片菜单不回归；gallery 瓦点按同路复核（image_page_open 景已改经单点）。
4. **0.9.65 桥自办余项（挂账续跑）**：drag_pickup_statemachine 全程复跑（步 3–5 首验 + lift_gaps 在 quote 上 faceInsets bottom 归 0）；U5 三景（home_search_cycle / home_surface_roundtrip / home_list_actions）各两遍 + home_geometry 复读无幽灵行/负 cardGaps；snapshot_restore_drill 带 armRestore 两遍 + backup_restore_snapshot 工具直调一轮；Diag 场景密集日早行（2000 行窗口内）分页可达复验；端内清单哈希与中继 1c2fe22e… 实读对账。
5. **沿革挂账（用户目检）**：0.9.65 §四.6 余项（块内 GIF 五面、卡片防误触手感、权限页六项、0.9.63 余项等）随本版一并目检。
