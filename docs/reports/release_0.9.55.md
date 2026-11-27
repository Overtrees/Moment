# 0.9.55 组版报告（横排标题卡死根治 + U0 地基 + 附件宽屏 22）

2026-11-27。基线 ec4105c（0.9.54）→ HEAD b9617d7（推送前五笔）+ 本报告笔。版本 0.9.55 / build 82。本版以用户真机新报的横排标题卡死修复为头，U0 地基与附件宽屏小批搭车。

## 一、提交分拣（五笔，归属逐段核对）

| 笔 | 哈希 | 内容 | 归属核对 |
|---|---|---|---|
| 1 卡死根治 | 0f7f3c9 | MomentApp EditorHeaderView/titleCapsule 三 hunk（DockSession 锁存定义 + 同步三点/翻转面包屑 + title session end 行）+ verify [28] + fix_title_compact_freeze.md | 三 hunk 全在 EditorHeaderView 段内（@@9806/@@9829/@@9997），与 U0 的 ListView 接线、附件批的 BlockRow/AttachmentRow/Radius 段零交叠 |
| 2 U0 地基 | 4c26910 | MomentEditorTransition.swift（EditorSeatRegistry + dismissSeatedEditor）+ MomentBridgeTools.swift（BridgeEditorSeat/memo_busy 接线）+ MomentApp 仅 ListView 接线 +9 行 + verify [25] B25-U0 段 + impl_uitest_u0.md | MomentApp 暂存恰为 ListView 一 hunk（@@15216）；verify [25] 块（87 行）以构造补丁插入 [28] 块之前，组序 [25] 在 [28] 前与文件尾顺序一致 |
| 3 附件宽屏 22 | d4a4987 | MomentApp 五 hunk（attachmentLiftFace 注释/本体、AttachmentRow 注释/本体、Radius.attachmentFile 派生）+ verify [21] R21-9 改写 + fix_attachment_radius_wide.md | 五 hunk 全在 BlockRow/AttachmentRow/Radius 段；R21-9 为 verify 首 hunk，与 [25]/[28] 尾部块无涉 |
| 4 文档沉淀 | b0f4dc3 | plan_ui_selftest_driver.md / plan_title_tap_caret.md / plan_bridge_m3.md 三方案入册 + WORKFLOW.md §5.4 末句更新 | WORKFLOW 仅改末句（「M2 未开」→ M2 已随 0.9.54 出货、U 批进行中），标题与其余段未动 |
| 5 版本 bump | b9617d7 | build-app2.sh + MomentApp 设置页版本串 | 见第三节 |

分拣方法：MomentApp.swift（9 hunk）与 verify_ios.sh（2 hunk，其中尾 hunk 为 [25]+[28] 两组连排）为多批共改文件，按各批报告改动清单以标记词逐 hunk 分类、补丁级暂存（git apply --cached）；verify 尾 hunk 按 [28] 起始行拆为两段构造补丁（卡死笔先暂存 [28] 尾随追加、U0 笔再以 [28] 组头为后文构造插入 [25]）。五笔提交后 git status 干净（仅剩三份未跟踪计划报告，已于第 4 笔入册），最终 HEAD 树与三批原始工作树逐字节一致。

## 二、本版三批要点（细节见各批报告）

- **卡死根治（fix_title_compact_freeze.md）**：定因 proven（结构）——坞分支旧为活公式 `scrollY > 30 && !titleFocused`，紧凑态点按置焦的同一更新内公式翻转、页眉横/竖分支换结构、焦点事务中的 TextField 销毁重建且其结构身份是焦点值本身的函数（自指涉），与焦点回滚的 commitTitle 写 @Published 叠加成环冻死主线程；竖排公式恒假不翻转故独正常，与真机形态逐项对应。根治 = DockSession 会话锁存（同步写者封闭三处：onAppear 初值、非会话期滚动跟随、失焦按当刻 scrollY 归位；会话期内无任何写者，翻转结构性不可达），与 Web S7 锁存信号同构。量测反馈环候选已 disproven。面包屑：`EDIT dockflip compact=<0|1> src=<scroll|session> n=<累计>` 逐翻转记行（src=session 本身即复发信号）+ `EDIT title session end` 与 begin 成对。
- **U0 地基（impl_uitest_u0.md）**：在席 EditorModel 注册表（会话令牌注销）+ 桥导航通道（正规 push 路径、等在席登记对号）+ memo_busy 接通块删/移两件（在席即拒，主线已裁从严口径）。四工具未入册——清单仍 22 件、manifestHash `05bff500…` 不变，入册归 U1 批。
- **附件宽屏 22（fix_attachment_radius_wide.md）**：Radius.attachmentFile(wide:) 条件派生为全文件唯一宽屏半径来源（宽屏 cardS=22/常态 cardL=32），行面与拾起面同派生同值，附件图片面恒 cardL 不经派生。0.9.52 S1「恒 32」裁断已被 Web 级联实证推翻（editor.css:726 特异性 (0,3,0)），本批恢复 Web 口径。

## 三、版本 bump 位置（与前版同位置，逐一核对）

- `build-app2.sh` 内嵌生成的 Info.plist 段：CFBundleShortVersionString 0.9.54→**0.9.55**、CFBundleVersion 81→**82**。
- `MomentApp.swift` 设置页版本串 Text("0.9.54")→Text("0.9.55")。
- verify [1] 版本一致断言已按新值转绿。

## 四、本机 verify 自跑（组版前基线）

222 ✓，余 2 ✗ 均为既有产物类（ipa 陈旧、产物语言包），tree 构建后自解（见第五节）。其中 [24] 五项保持全绿、[25] B25-U0 段与 [28] F28-1..5 全绿。

## 五、tree 冒烟（smoke_ios.sh 全量，/data/home/smoke55-tree.log）

- 同步：push_small.py 全量 overlay 传输 md5 对账全 OK，拷入 tree 克隆 /opt/work/Moment 后核对关键标记（DockSession、0.9.55、attachmentFile）在位。
- 结果：**SMOKE ALL GREEN**——cargo test --workspace 全过、FFI 静态库重建、ipa 构建、verify_ios.sh **224 ✓ / 0 ✗**（本机 222 + 产物两项转绿）。
- 构建产物：Moment-stage2.ipa 10,876,101 B（tree 侧）。

## 六、CI

五笔已推送（ec4105c..b9617d7，ls-remote 核对远端 main == b9617d7）。moment-rust-web 工作流的正向 success 未在本笔内查证（沿 0.9.54 待补核项一并后查），不作结论。

## 七、取包

- pull_ipa.py（LOCAL 改本版）取回：~/workspace/your_files/Moment-0.9.55.ipa，**10,876,101 B，md5 0aeac9c88d928713832e3e8f0ad2080c**，远端/本地 md5 一致。

## 八、真机终判点（待用户）

1. **横排（滚动后紧凑坞）点标题胶囊：即刻进入编辑、整页不卡死**（本版头号项，0.9.54 卡死点）。
2. 标题编辑会话期内滚动页面：坞形态保持会话开始时的形态不翻转；失焦后坞按当刻滚动位置归位（滚过阈值回紧凑、滚回顶部回竖排）。
3. 竖排点胶囊编辑零回归（0.9.54 已实证路径不回退）；长标题截断态点按置焦、提交/Esc 行为不变。
4. 附件文件行宽屏（双栏/spread）圆角为 22、常态 32，两面（行面与拾起面）一致；附件图片面仍 32。
5. U0 地基无用户可见面（桥清单仍 22 件、行为面零变化），无需判读。

## 九、桥复核法（装后主线走桥判读，无需用户描述）

App 前台时经连接器调 `diag_tail`，核对横排点按一次的日志三点：

- `EDIT title focus via=capsule` 与 `EDIT title session begin` 出现且各一次；
- 会话收尾有 `EDIT title session end` 与 begin 成对；
- **无 `EDIT dockflip ... src=session` 行**（src=session 本身即复发信号）；src=scroll 的 dockflip 行可有（非会话期正常翻转），其 n= 计数即翻转总量，异常暴涨即风暴证据。
