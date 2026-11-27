# 0.9.54 组版报告（M2 桥批 + 标题胶囊根治 + 留白/内角/浮层综合批）

2026-11-27。基线 78bac65（0.9.53）→ HEAD f629be0（推送前）+ 本报告笔。版本 0.9.54 / build 81。用户已裁：等留白线落码、0.9.54 全量一起出再验。

## 一、提交分拣（五笔，归属逐段核对）

| 笔 | 哈希 | 内容 | 归属核对 |
|---|---|---|---|
| 1 桥 M2 | b9bc160 | 桥五文件（Protocol/Tools/Ops/Bridge/（Settings、Transport 未动））+ bridge/relay/worker.js + verify [16] 协调 + impl_bridge_m2.md | verify 暂存恰为 [16] 三 hunk（组头/B16-3/B16-10..16），无 [23]/[24] 混入 |
| 2 标题胶囊 | 18fed3b | MomentApp EditorHeaderView 六 hunk（dockCompact 定义/动画值/headerOverlay/capsuleWidth/titleCapsule 两段）+ verify [24] + fix_title_capsule_reedit.md | 六 hunk 全在 EditorHeaderView 段内；菜单浮层 hunk（同 struct 内的 menuPanel 段）经标记核对归留白批，未混入 |
| 3 留白综合 | 4fee6ff | MomentApp 其余 22 hunk（ImageBlockView/BlockRow/EditorView menuPanelH/menuPanel/Gallery/CardBlockView/ImgText/GlassCard CornerRect/ListView）+ verify [23] + fix_lift_spacing.md | 索引内 [23]（行 1979）在 [24]（行 2069）之前，顺序与组号一致 |
| 4 文档沉淀 | 4d6db0f | docs/WORKFLOW.md §5.4 | 仅该节 +26 行 |
| 5 版本 bump | f629be0 | build-app2.sh + MomentApp 设置页版本串 | 见第三节 |

分拣方法：MomentApp.swift 与 verify_ios.sh 均为多批共改文件，按各批报告改动清单以标记词逐 hunk 分类、补丁级暂存（git apply --cached），每笔提交前核暂存 hunk 清单。过程校正一笔：首轮 verify_title 补丁多带一行 [24] 尾随空行（与原始工作树差一行），已软重置三笔、以修正补丁重提，最终 HEAD 与原始三批工作树逐字节零残差（git status 干净为据）。

注记（文档时效）：WORKFLOW.md §5.4 是 M2 落码前写的沉淀，末句「M2 未开，写工具不在连接器白名单内」在本版出后即过期——本笔按沉淀原文入账，建议主线随手把该句更新为 M2 已随 0.9.54 出货。

## 二、verify [16] 协调明细（按 impl_bridge_m2.md §5）

- 组头更新为「M1+M2」。
- **B16-3 改写**：原 M1 边界（11 件 + 写名零出现）→ 清单 22 件逐名在 BPROTO + 未开放 9 名（正文级 notes_create/editor_insert_block/editor_update_block/editor_set_block_type、在席 editor_open/editor_get_state/editor_focus_block/editor_save_now、rescue_arm_safe_mode）在桥六文件与中继的**代码行**零注册。口径说明：此 9 名在 Protocol/worker.js 的注释里有提及（说明为何不入册），按 verify 既有 [2] 的「只查代码行、注释提及不算」口径剥除整行注释后查，与报告「零出现」的注册义一致。
- **B16-10** 能力门：writeScopeTools/opsScopeTools 集合 + scope_denied 双分支 + 中继 WRITE_SCOPE_TOOLS/WRITE_TIMEOUT_MS 30000。
- **B16-11** 两段提交：twoStageTools + actionToken 签发 + confirmation_required + 永删 confirmMemoId 逐字比对行。
- **B16-12** 快照先行：openReadonly + exportBackup 直调 + bridge-snapshots 落点 + 桥六文件 exportZip( 零出现。
- **B16-13** 幂等与守卫：paramsHash/idempotency_conflict/revision_conflict/guardedMemo。
- **B16-14** 受限集：safeLimitedTools 抽取与 §9.6 八件逐名比对 + BOPS not_in_safe_mode/via=bridge/recordRescueAction("normal-retry")。
- **B16-15** 三方清单（仓内两侧）：BPROTO toolNames 与中继 TOOLS 名集合 diff 为空且同为 22 件；manifestHash 05bff500… 以注记入断言（运行时两边计算对账）。连接器 ALLOWED_TOOLS 在仓外，M2 批已同步，不在本脚本射程。
- **B16-16** 设置白名单：toggleRegistry 抽取只含 diagAutodel；桥六文件 weatherKey_ 仅一处落点（removeObject 的 forKey 行）——只清不写。落码时一处自纠：首版抽取字符类漏大写（diagAutodel 的 A），改 [a-zA-Z_] 后转绿。
- [9] 五语键：M2 零新增，期望数未动。

本机自跑：协调后 210 ✓，余 2 ✗ 均为 ipa 陈旧类（产物早于源码/产物语言包），tree 构建后自解（见第五节）。

## 三、版本 bump 位置（与前版同位置，逐一核对）

- `build-app2.sh` 内嵌生成的 Info.plist 段：CFBundleShortVersionString 0.9.53→**0.9.54**、CFBundleVersion 80→**81**（仓库无独立 Info.plist 文件，plist 由脚本生成，此即其字段落点）。
- `MomentApp.swift` 设置页版本串 Text("0.9.53")→Text("0.9.54")。
- verify [1] 三处一致断言已按新值转绿。

## 四、S1 旁注复核（只读复核，本版不改口径）

留白批第七节第 4 项提出：editor.css 宽屏段存在 .attachment-file 的 radius-22 规则，与 0.9.52 圆角批 S1 裁断「Web .attachment-file 恒 32、宽屏 22 缺 Web 实据、统一 cardL=32」的依据表述有出入。回 Web 源码复核结论：

- **规则存在（proven）**：`rust/apps/web/styles/editor.css` 第 726–734 行，`.editor-spread > .editor-body .attachment-file { gap: 8px; padding: 12px 14px; border-radius: var(--radius-22); }`，位于 `@media (min-width: 768px) and (min-height: 600px), (min-width: 1100px)` 宽屏段内（「双栏正文细节」节）；--radius-22 = 22px（tokens.css:153）。
- **作用域**：仅 .editor-spread（宽屏双栏形态）+ 上述媒体条件；独立滚动/流式两变体段（1012/1085 行附近）对 .attachment-file 只设 break-inside，不覆盖半径，同样吃此规则。
- **级联结果**：基础规则（同文件 428 行，`.editor-body .attachment-file`，radius-32、padding 16/20、gap 10）特异性 (0,2,0)；宽屏规则 (0,3,0) 且位置在后——**宽屏 spread 形态下 Web 计算值确为 22**，窄屏为 32。且同规则把 padding/gap 一并改成 12/14 与 8——原生宽屏 padding 12/14、gap 8 此前已按此对齐，唯半径被 S1 统一为 32。
- **结论**：S1 的「恒 32 / 缺 Web 实据」表述不准确，留白批旁注属实；S1 的统一 32 决策使原生宽屏附件行半径与 Web 宽屏计算值（22）不一致（窄屏一致）。
- **建议（本版未改）**：后续单开一小批——AttachmentRow 宽屏面半径恢复 22（Radius.cardS），拾起框走既有 Radius.lift 同心派生自动跟随，窄屏维持 32；同步改 R21-9 断言的宽屏子句。媒体条件含 min-height 600 一维，原生「宽屏」判定与之的映射关系须在该批一并核清，不在本版顺手改。

## 五、tree 冒烟（smoke_ios.sh 全量，/data/home/smoke54-tree.log）

- 同步：push_small.py 全量 27 文件 OK（本批改动文件全在名单内、无新增文件）；overlay 覆盖入 tree 克隆后启动。
- 结果：**SMOKE ALL GREEN**——cargo test --workspace 通过、FFI 静态库重建、ipa 构建、verify_ios.sh **212 项断言全绿、零 ✗**（本机 210 + ipa 两项在构建后转绿）。
- ipa：tree 侧 build/Moment-stage2.ipa，10,848,755 B，md5 4f4946c940fe4feac461764fe539534e。

## 六、CI（moment-rust-web @ f629be0）

- 推送完成：git ls-remote 远端 main == 本地 HEAD f629be0f08a286e61584b85c461ef0b1ab431700。
- 结论分级：**未见失败证据，正向 success 待主线复核**。判读过程：GitHub API 未认证查询返回 403（共享出口限流），按纪律未换通道重试、未动用 PAT 调 API（PUSH.md 红线）；Gmail 失败通知通道复查两次——推送后约 36 分钟内无 f629be0 的失败邮件（历史三次失败通知均在运行后约 15–40 分钟内到达）。风险面评估：本批未触语言键、Rust 与 Web 源码，1f93642 根治的僵尸键门禁不在本批射程内。主线下次 API 可达时请补核该 run 的 completed 结论入账。

## 七、取包

- pull_ipa.py 的 LOCAL 已改指 Moment-0.9.54.ipa（中途一次取包进程被本机服务重启杀掉，整包重拉，无半成品）。
- 产物：`~/workspace/your_files/Moment-0.9.54.ipa`，**10,848,755 B**，md5 **4f4946c940fe4feac461764fe539534e**（脚本内远程/本地 md5 对账一致）。

## 八、留白批登记的 5 项待裁小账（原样转录自 fix_lift_spacing.md 第七节）

1. **列表 marker 列**：原生顶层文起点 28（marker 框 20 + gap 8），Web ul ≈ 17 / ol ≈ 20；嵌套层同差。改动需同时定编号 marker（"100." 等宽数）的框宽口径，且触既有 #29 审计结论，本批不动。
2. **imgTextRow 卡高**：原生固定 188，Web 为 181–196 内容驱动（min/max-height）。在区间内、非不对称问题，不动。
3. **music 骨架线宽**：原生 75/50/35% 阶梯、Web 三线通宽。属形态差、非留白，不动。
4. **附件行宽屏半径旁注**：圆角批 S1 裁断记「附件宽屏 22 缺 Web 实据、统一 32」；本批查账见 editor.css 宽屏段存在 `.attachment-file` 的 radius-22 规则（spread 变体），与 S1 表述有出入。属圆角面、用户已判圆角无事，本批不动，仅登记请主线复核 S1。（本报告第四节已复核：旁注属实，建议后续小批恢复宽屏 22。）
5. **slash / ErrBadge 面板**：与 ••• 菜单同为「ScrollView + 限高」结构，前者有实测回写、后者为 J2 既定限高内滚，均无悬空实报，不动（第六节已登记）。

## 九、真机终判点（待用户，沿三批报告）

标题胶囊：长标题反复点按进编辑、编辑中滚动坞不翻转（Diag 两行 EDIT title 成对出现可经桥 diag_tail 判读）；留白/内角：满宽卡左右缘与正文共线、拾起四边等距、图文卡空态底角直角无白缺口、gallery 瓦间十字缝、••• 菜单高贴合内容、引用条贴面缘（四张原截图同位复拍）；M2：bridge_status 清单哈希换新（05bff500…）属预期——中继 worker.js 须经 bridge/relay/deploy.py 同批部署后 tools/list 才含 M2 集，部署前清单不一致是预期中间态；write 层工具须重新配对勾选 write 才可用（现配对 read+ops，ops 三件现即可用）。
