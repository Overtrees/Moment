# release_0.9.60 — 签名修复版组版报告

0.9.60 / build 87。主题：0.9.58 起「签名后装不上」根治出包
（fix_install_signing_0958）+ E2 撤销体系 + U4b 撤销面场景。
跨块选区一期（MomentXSel.swift）仍在另一线落码中，本版不含，
其未提交文件与 hunk 全程只分拣排除、未动未删。

## 一、提交清单（e12fc62 → 本版，共 6 笔）

| 笔 | 内容 |
|---|---|
| d4017f3 | E2 撤销体系根治：MomentUndo.swift 纯状态机单点记账（600ms 爆发合并 / 规范键去重 / 上限 100）、选区恢复、Cmd+Z 与三指单轨漏斗；verify [47] + DT46-6 改锚（定案 impl_editor_undo_e2.md） |
| ad4b6cf | U4b 撤销面场景 undo_redo_roundtrip（EDT-14）；verify [48] + 覆盖矩阵 EDT-14 改判已覆盖（定案 impl_uitest_u4b.md） |
| 84834e2 | 签名根治：macho-entitle embed 页哈希重算 + __LINKEDIT 同增 delta、AMFI 口径 validate 子命令、build 双硬门、appex 版本单源同步；verify [49]（定案 fix_install_signing_0958.md） |
| c5677c3 | bump：版本 0.9.60 / build 87（build-app2.sh Info.plist 字段 + 设置页版本串） |
| a93e039 | 组版修正：SG49-1 工具路径双宿主解析（见 §三） |
| 本报告笔 | 本报告入册（连同组版账） |

FFI 前置门：crates/ 全域零 diff，导出面未动、无 checksum 漂移。

分拣口径：三批以标记词逐 hunk 分类 + 补丁级暂存；verify_ios.sh
尾部 [47]/[48]/[49] 三组按行段重构分笔；build-app2.sh 26 hunk
按标记分 24（E2 接线）+ 2（签名硬门/版本同步），与各批报告账面
逐一对齐。

## 二、关键前置：tree 工具同步（顺序不可错）

tree 构建机 ~/ios-native/bin/macho-entitle 在组版前仍是旧工具，
先同步新版 ~/workspace/ios-tools/macho_entitle.py 再构建（新
validate 硬门对旧工具产物必红，设计如此）：

- 同步后两边 md5 一致：c2cf6bb7118512690c7692e0cc31014f
（16533 B，执行位在位、工具可运行）。
- push_small.py 名单本版补四件：MomentUndo.swift、
scripts/i18n_deep_check.py、scripts/verify_docs.sh、
docs/reports/plan_selftest_coverage.md（后两件为 0.9.59 后续项
与本版新发现，见 §三）；全量同步逐文件 md5 对账全 OK。

## 三、tree 冒烟（两轮，日志 /data/home/smoke60-tree.log）

**首轮 517 ✓ / 2 ✗**，两红均为门禁/同步面、本机布局下不可见，
当轮根治后重跑：

1. **U4b-4 矩阵 EDT-14 行未回写**：verify 读克隆内
docs/reports/plan_selftest_coverage.md，而矩阵不在 push_small
名单内、克隆里是旧版。根治 = 矩阵补入同步名单（§二），非改
断言。
2. **SG49-1 工具路径在 tree 不存在**：断言把工具源码路径写死
$HOME/workspace/ios-tools/（本机布局），tree 无此检出。根治 =
双宿主解析：本机取 workspace 源码、缺失时回退部署态
~/ios-native/bin/macho-entitle（同一脚本，组版前已同步对账），
断言语义不变（a93e039）。

**次轮 ALL GREEN：verify 519 ✓ / 0 ✗**，cargo test 全过 → FFI
重建 → 构建（主程序与 appex 两道 validate 硬门均在构建日志
实证通过）→ verify 全绿。

**同步插曲留痕**：跨块选区代理在本版同步窗口内并发编辑
MomentApp.swift / build-app2.sh / verify_ios.sh 三共享文件，
首轮 push_small 捕获到两件的中间态（与 HEAD、与现工作树三方
md5 互不相同）。处置：以 git HEAD 提取的三件为准重推 overlay
并拷入克隆，逐件 md5 与 HEAD 对齐后才启动冒烟；克隆内确认无
MomentXSel 文件残入。并发落码期共享文件的同步须以提交态为准，
不以工作树为准——此条入组版纪律。

tree 根分区冒烟时 95.6%（约 0.6G 可用），本轮未清理、冒烟两轮
均未受影响；克隆与工具链未动。

## 四、产物级签名复验（本版新增，不可省；四数字）

对最终交付 ipa 解包后实测——新 macho-entitle validate 与一份
独立复算实现（不共代码：逐页按 codeLimit 裁剪复算哈希、签名
末端与 __LINKEDIT 末端对账、plist 版本对账）双口径：

| 对象 | validate | 坏页数（独立复算） | 签名末端 − __LINKEDIT 末端 | 版本 |
|---|---|---|---|---|
| 主程序 Moment | OK（exit 0） | **0** | **0 B** | 0.9.60 / 87 |
| appex（MomentLiveOpsWidget） | OK（exit 0） | **0** | **0 B** | 0.9.60 / 87（与主程序一致） |

对照坏件基线（0.9.58/0.9.59 已交付原件）：坏页 1（主）/ 0 页
（appex 的 LC 页）、超出 +481 B（主）/ +424 B（appex）、appex
版本冻 0.9.57/84——四项全数归正。

ipa 对账：~/workspace/your_files/Moment-0.9.60.ipa，
**11,658,956 B，md5 7c68a17689992eb9a34d55f9c8c36c4e**
（tree 构建产物与本地拉回件 md5 一致）。

## 五、真机终判点

1. **签名修复装机确认**：按原流程对 0.9.60 签名并
安装——0.9.57 正常、0.9.58/0.9.59 装不上，本版应恢复可装；
此项为签名根治的最终终判，其余证据（§四）均为构建侧口径。
2. **E2 撤销 6 点**（impl_editor_undo_e2.md §六）：连续打字一撤
整段、撤销后光标/选区回位、Cmd+Z 与三指不双撤 + 摇一摇无
系统弹窗、标题字段 Cmd+Z、空会话无幻影步、100+ 步钳制的
Diag 佐证。
3. **装后走桥自办**（装机并放前台后主线自办）：S1
title_capsule_reedit 两遍重跑（0.9.58 标题传播修复的关闭
证据）、M3b 写景验收、实况保活三档量测、undo_redo_roundtrip
桥实跑（预期终态 ok + pre/post 库哈希相等）、在席工具抽验
与 Diag 补读、§6.8 出包回归子集余项。
4. **0.9.59 终判未验项随本版一并终判**（release_0.9.59.md
§七）：横屏双设备列数与卡间距 12、改系统字号逐页、深色打开
截图同款页、权限页逐项点请求、页眉四场景（冷启/往返/旋转/
回弹）等。

## 六、后续项

- 跨块选区一期落定后随 0.9.61 组版；其组版时 push_small 名单
补 MomentXSel.swift / MomentXSelBridge.swift，共享文件同步
同样以提交态为准（§三纪律）。
- CI 回核：本版推送后下一次 CI 运行应全绿（801a605 起口径）。
