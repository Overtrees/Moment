# 组版报告 0.9.62（build 89）

2026-11-27 晚。三批合包：状态栏全局背景采样根治 + 图片卡加载键控根治 + 全面审计批 1/2/7。tree smoke_ios.sh 全量 **ALL GREEN（verify 555 ✓ / 0 ✗）**，产物级复验全过（见 §三）。ipa：`~/workspace/your_files/Moment-0.9.62.ipa`，11,737,316 B，md5 `40f2232becbee73093ca721118f13bc4`。

## 一、本版内容（按提交序）

| 提交 | 内容 |
|---|---|
| 29690a1 | 状态栏批：全局背景色采样单点决策（纯核心 MomentStatusBar.swift + 生效层 MomentStatusBarBridge.swift；plist 翻 VC 化；承载 override 现算；根观察器送达）。定案 fix_statusbar_sampling.md，诊断 diag_statusbar_dark.md |
| 8288d0b | 审计批 1+2+7：AUD-E-01 开屏解码降级、C-01 备份导入 lib 守卫去假成功、E-03 DiagLog 原子写、E-02 ops_validate 拆集、E-05① Undo eventSink 接线、E-05③ PdfMaker 失败带因、A-02 FTS LIKE 转义（+ 附记 haystack data: 过滤）。定案 fix_audit_0962_b127.md；全面审计总册与五分册同笔落盘 |
| c40be37 | 图片批：加载身份键控（MomentImageLoad.swift 纯核心、删一次性闩锁、三视图 onChange 钩子、gallery 瓦项键、视频 prepare 键控 + AUD-E-05② Diag）；场景 EDT-60/61。定案 fix_image_card_load.md |
| 3b51781 | 组版收敛笔（见 §二） |
| 80a6cc9 | bump 0.9.62 / build 89 |

FFI 导出面零改动（UniFFI checksum 无涉）。appex 维持 0.9.61 过渡口径（BUNDLE_WIDGET_EXT=0、不捆绑），回归等个人 Developer 账号（见 diag_appex_install.md）。

## 二、组版收敛项（逐项办结登记）

1. **verify [54] 同号顺延**：图片组 [54] IMG54-* → **[55] IMG55-1..7**（组标题、断言名、组内变量 IMG55D/IMG55SEG/SWIFTC55、头部 IMGCORE 取段注释同步）；全文引用同步——覆盖矩阵 EDT-60 行、fix_image_card_load.md §一/§三/§四（§四-2 改记组版定夺）、fix_audit_0962_b127.md §五组版注记回填。AU54 组不动。tree verify [55] 七项全绿实证。
2. **构建接线普查期望终态复核**：本机全量 verify 对 build-app2.sh 终态实测——DT46-6（28）、E47-8（29）、X50-7（29）、SB-5（双文件各 29）四处期望与终态逐一对齐（两批新增 primary 遍的合法递增，沿革注记已在各断言头注）；本机 553 ✓、余 2 红为已知产物红（ipa 陈旧/产物语言包），tree 构建后归零（555 ✓ / 0 ✗）。收敛笔 3b51781 落普查回写。
3. **push_small.py 名单核全**：五件全在册——MomentStatusBar.swift / MomentStatusBarBridge.swift（状态栏批已补）、**MomentImageLoad.swift（组版补）**、**Web editor.rs / editor/model.rs（组版补）**。补入时实证路径修正：editor.rs 在 `rust/apps/web/src/editor.rs`（非 editor/ 子目录）、model.rs 在 `src/editor/model.rs`；首轮传输因路径误写中断、修正后重跑 ALL TRANSFERS DONE，tree 克隆内关键五文件 md5 与本机逐一一致。
4. **diag_statusbar_dark.md 截断处置**：核对属实（正文止于 §1.3 中段、尾行带截断标记、§二以后未落盘）。已在文首加落盘完整性注记：现存部分结论由 fix_statusbar_sampling.md 承接、引用以该报告为准，不补造原文。
5. **macho-entitle 双边一致**：本机 `~/workspace/ios-tools/macho_entitle.py` 与 tree `~/ios-native/bin/macho-entitle` md5 同为 `c2cf6bb7118512690c7692e0cc31014f`，构建前已核。

另：build-app2.sh 工作树权限曾漂移 755→644（编辑工具 umask 所致），组版时已恢复 755，提交无模式变更。

## 三、验证

- 本机：cargo test（storage 18/18 含 A-02 新判别测试，审计批已验）；verify 本机 553 ✓ / 2 产物红（已知口径）。
- tree：push_small 全量传输（md5 逐件对账）→ overlay 拷入克隆（关键五文件 md5 复核一致）→ smoke_ios.sh 四阶全过，**SMOKE ALL GREEN，verify 555 ✓ / 0 ✗**（[53] SB 五项、[54] AU 六项、[55] IMG 七项全绿）。
- 产物级复验（tree 解包实测）：Payload 内 **PlugIns 不存在** ✓；Info.plist 版本 **0.9.62 / 89** ✓、UIViewControllerBasedStatusBarAppearance = **true** ✓（状态栏批 plist 翻转入产物）；主二进制 macho-entitle validate **OK**（签名落 __LINKEDIT 内、页哈希与特殊槽一致——坏页 0、签名超出 0 B 同口径）✓；天气 key 文件在包内 ✓。
- 推送：远端 main == 本地 HEAD（80a6cc9，bump 笔）核对一致；本报告笔随后推送。

## 四、真机终判点（汇全，归用户装机后验）

1. **装机**：0.9.62 覆盖安装应成功——与 0.9.61 同为去 appex 过渡口径，本版取代 0.9.61，**无需另装 0.9.61**；此项兼作 0.9.61 的 appex 过渡终判。
2. **跨块选区两期各 8 点**（0.9.61 遗留，清单见 release_0.9.61.md 与 plan_cross_block_selection.md）：一期全选动作面/跨块替换/守卫、二期 Shift+方向扩展等逐点验。
3. **状态栏往返**：编辑页（无底色篇）系统外观深→浅→深往返两轮，字色每腿当场回位（不挂后台、不重进）；Diag 成对 `STATUSBAR bg=#000000 style=light ↔ bg=#F2F2F7 style=dark` 行可核。另：浅彩底篇深色下黑字为采样应然；首页/设置/图片页/救援态往返同验（全清单 fix_statusbar_sampling.md §六，共 6 点）。
4. **图片卡复现路径**：斜杠「图片」建空块 → 点占位选图 → 当场出图（Diag 见 `IMG reload`/`IMG reload ok` 成对行）；图文卡点图区选图当场出图；图块换图当场换新；gallery 删首项/排序后各瓦图随项不错位；视频坏附件块不出假播放面（Diag `VIDEO prepare missing`）。全清单 fix_image_card_load.md §五，共 5 点。
5. **审计抽点**：备份导入——坏包如实报失败（不再假成功弹恢复）、正常包成败口径如旧；开屏——正常包呈现如旧（降级面仅资源损坏构造包可达，非常规路径）；ops_validate 点名核心步（如「开库」）应回 valid=false + unguardedSteps（桥可自办）；撤销/重做后 Diag 有 `EDIT undo core` 行、PDF 导出失败有带原因行（Diag 导出可核）。全清单 fix_audit_0962_b127.md §三/§五。

## 五、证据分级与遗留

- 构建/断言/产物面 = proven（tree 冒烟全绿 + 产物复验实测）；三批各自的机制面证据等级见各定案报告。
- 真机行为面 = unknown，归 §四终判（构建绿不表述为已修复）。
- 遗留队列不变：审计批 3/6 排 0.9.63、批 4 随 E5/E6、批 5 = I4/I5；4 个用户裁定项（AUD-B-02/C-02/A-08/B-05）仍待裁；装机后走桥自办全集（S1 两遍、M3b、undo_redo_roundtrip 桥实跑——其 Diag 期望字面已随审计批同步新词形）。
