# 0.9.58 组版报告（release_0.9.58）

基线 HEAD d540d89（0.9.57）→ 组版 HEAD 4070d70（bump 笔），其后报告入册笔另记。版本 0.9.58 / build 85。

## 一、提交清单（23 笔：22 批分拣 + bump）

分拣法：以各批标记词逐 hunk 分类（420 hunk / 37 文件）、补丁级暂存；同锚交错的共享 hunk（verify [25]/[30]/[32–39] 段、build-app2.sh 编译名单、MomentApp #54）按行级标记切分、按全局序变换暂存，最终索引与工作树逐字一致（跟踪文件树净为凭）。分拣小注三处：① 首页四症的 F30-16/17 断言与宽屏 F30-15 同锚交错，单列续笔 48138df；② B25-E3-5 条目内 callout 改判注释随 E3 笔入册（条目本体属 E3，callout 批的落码与 E3-6 条目在 callout 笔）；③ MomentLiveOps.swift / MomentLiveOpsAttributes.swift 两新文件整体入权限 B 笔，其中桥会话形态扩展（LiveOpKind.bridge + opDetail）为实况保活批同文件扩写、已在该笔提交信息外另由 keepalive 笔的其余文件与报告承载。

| # | commit | 内容 |
|---|--------|------|
| 1 | ff27ade | 救援完整性 + 只读态编辑入口禁用（impl_rescue_integrity） |
| 2 | 9a033d3 | 首页四症根治（fix_home_regressions_0957） |
| 3 | 9749f2a | 宽屏/横屏对齐批 L-1~L-8/E-1/E-2（impl_wide_landscape） |
| 4 | 8cc4542 | callout 尾随空段微批（fix_callout_trailing_para） |
| 5 | dbcbea8 | E3 转换语义单点化 + listStart 类型修复（impl_conversion_e3 / fix_e3_liststart_type） |
| 6 | c9c9da2 | E4 编辑器健壮性（impl_editor_robust_e4） |
| 7 | c72046f | 桥续连根治 App 侧 + 中继源码入册（impl_bridge_reconnect，中继已部署） |
| 8 | bdc2f9f | 配对二维码（impl_pairing_qr_code） |
| 9 | 952e3cb | 媒体增强 Gallery 删/排序 + 视频插入（impl_media_enhance） |
| 10 | c65f065 | 权限 B 段（impl_entitlements_b） |
| 11 | 8c42540 | 桥 M3a 清单 31→35（impl_bridge_m3a，中继已部署） |
| 12 | e52dadd | U4a 自检六景（impl_uitest_u4a） |
| 13 | 0f9d758 | MD 预览缓存陈旧根治（fix_md_cache_stale） |
| 14 | c0c3c4e | 文字大小真跟随全量实装（impl_dynamic_type_full） |
| 15 | 45883da | DT 布局韧性（impl_dt_layout_resilience） |
| 16 | 29def8e | DT 首页领地补批 R-1~R-5（impl_dt_home_resilience） |
| 17 | 48138df | 首页四症分拣续笔 F30-16/17 断言 |
| 18 | 91fd481 | 标题提交→库传播根治（fix_title_commit_propagation） |
| 19 | 43499a0 | 桥会话实况保活（impl_bridge_live_keepalive） |
| 20 | 7720671 | iPad 大屏贴合新 8 项断言组 [39]（impl_ipad_fit8，仅 verify+报告） |
| 21 | 253c2ca | Web 真块型兼容 W1–W4（impl_web_block_compat） |
| 22 | 88a662c | probe_batch3 探针竞速修复（fix_probe_batch3_route） |
| 23 | 4070d70 | bump 0.9.58 / build 85（build-app2.sh 内嵌 plist + 设置页版本串） |

推送：PAT shell 流程，d540d89..4070d70 快进推 main（输出脱敏、临时副本未落盘）。

## 二、tree 冒烟（smoke_ios.sh 全量，/data/home/smoke58-tree.log）

同步方式：push_small.py 名单补入本波 6 个新文件（MomentLiveOps 三件 + Moment.entitlements + Widget plist/entitlements）与 Web 兼容 4 文件（ops/export/blocks + block_compat.rs），全量传输 md5 对账 OK；overlay 覆入 tree 克隆 /opt/work/Moment 后关键文件 md5 与本机逐字一致（MomentApp.swift 89bfed47…、verify_ios.sh 2b9f6b77…、ops.rs 3e0585a5…）。

结果：**SMOKE ALL GREEN（一轮全绿，无重跑）**

- [1/4] cargo test --workspace：通过（smoke 脚本 tail 截断，绿灯以 set -e 推进为凭）。
- [2/4] FFI 静态库重建：Finished（4.43s）。
- [3/4] 构建 ipa：产出 Moment-stage2.ipa（见第三节对账）；构建内 entitlements 回读断言（B 段）随构建通过。
- [4/4] verify_ios.sh：**372 ✓ / 0 ✗，ALL PASS**（0.9.57 为 279 ✓；本波新增 [32]–[39] 等组段）。版本断言 ✓「版本 0.9.58（脚本与设置页一致，build 85）」。

点名单项证据（冒烟后同机补跑）：

- block_compat 契约测试（moment-core）：3 passed / 0 failed。
- moment-ffi 契约测试：5 passed / 0 failed（checksum 断言在内）。
- **UniFFI 纪律核对：本波未动 FFI 导出面**——`git diff d540d89..HEAD --stat -- rust/crates/ffi` 为空（ffi_lib.rs 传输件与基线同 md5），bindings 未重生、checksum 无漂移，与契约测试全过互证。

环境注记（非本批红）：tree 根分区 95.6–95.9% 满（0.6 GiB free）的 diskWarning 全程在场，冒烟未受影响；后续需清理根分区大日志（build48 系列 trace 等）。

中继与连接器：本组版**零改动、未重复部署**（续连 + M3a 中继已于各批落码时部署并逐字节验一致，worker.js 本波仅源码入册 53,288 B / md5 3bef593e 与在册一致）。

## 三、ipa 对账

- 文件：~/workspace/your_files/Moment-0.9.58.ipa
- 字节数：**11,432,828 B**
- md5：**bec5504c98d14f102d1025213e32b0c9**（tree 构建产物与本机到手件逐字一致；取包首程因运行时重启中断、核查无残留后重跑完成，脚本内 remote/local md5 双对账通过）

## 四、装后桥侧预期

装机后 App 侧 manifest 应由 a52116c3（31 件）切至 **ec9fbc90（35 件）**：bridge_status 回读 manifestHash = ec9fbc90890f…、工具清单 35 件、scopes read+write+ops（现行配对）。若仍回 a52116c3 即装机未生效，先查安装再查桥。

## 五、真机终判点全集

自检驱动证据上限沿用既有口径：状态机/布局几何/落盘可 proven；触摸投递、识别器仲裁、键盘光标拼音、像素栅格化永远真机终判。

1. **首页四症复验**（fix_home_regressions_0957 §5）：① 搜索展开态点开一篇 → 点完成胶囊 ✓ → 返回首页，键盘不自弹；② 走桥打开一篇同验，Diag 应见辞焦行 src=seat；③ 冷启点头像/搜索胶囊可点，Diag scrollprobe attach 与 home compact 迁移两行齐；④ 图文卡与文本卡交界量距 ≈22pt（66px@3x）。
2. **S1 桥重跑（标题传播关闭证据）**：装后走桥重跑 title_capsule_reedit 两遍——两遍 ok 且第 3 步 notes_get_title 回长标题为关闭判据，BRG-09（U2 开工门）随之复核。
3. **DT 两极走查**：系统字号最小/最大（AX5）两极逐面走查（首页/编辑/设置/救援/Diag），并入 impl_dt_layout_resilience §7 与 impl_dt_home_resilience 终判点；两处「观察」边界复核：紧凑态标题胶囊 ≈166 略超顶距 155、备份底表横屏×AX5 文案顶或裁（双钮恒可见）。
4. **iPad 八面走查**（impl_ipad_fit8）：底表 600、正文 1440 居中、斜杠面板宽钳、菜单锚块钳制、DiagLogPage 全宽卡、全宽 toast、系统 sheet/PHPicker 居中卡、命中 46 不随屏放大——iPad 实机逐面看。
5. **配对二维码真扫**：解除配对后以设置页二维码真扫一次完成重配对（148pt 码图、有效期行显示）；注：重配对将轮换设备指纹，连接器侧基线需同步更新。
6. **MD 缓存两轮**：MD 段落编辑 → 失焦预览仍渲染态（非字面原文），连改两轮成立（fix_md_cache_stale 终判口径）。
7. **callout 三点**：菜单转 callout 补尾随空段；斜杠转 callout（顶层）同补；列表项转 callout 不补（与 Web 全等）。
8. **权限 B 五点**：① 头号——现行流程（启动/浏览/编辑/导出）不得出现任何授权弹窗（惰性声明）；② 桥设置页开启通知开关才请求通知授权；③ uitest_run 场景运行全程 Live Activity 在位、Diag OPS live 行序成对；④ 切后台时桥长操作/场景 journal 不被腰斩（宽限护收口）；⑤ BGTask 消费点（快照清理）在 Diag/系统调度下可观察。
9. **续连 Diag 时戳**：冷启 LAUNCH→session up 目标 0.5–1.2s；温启回前台 foreground→probe ok 目标 2.5–4s；resume ok 应占恢复路径绝大多数；probe fail state=connecting 应绝迹（出现即回读 impl_bridge_reconnect 排查）。
10. **实况保活量测三档表**（impl_bridge_live_keepalive §5）：切后台静置 1/5/15 分钟各 ≥3 次，回前台读 BRIDGE bg return 成对行（dur/socket/live）+ 紧随 probe 行，三元组判读存活/半死/已死，与 0.9.57 基线对照填表；无显著延长则如实保留状态呈现价值结论。
11. **M3a §7 设备点**：scenarios_list 回读（七景注册与逐景可用性）；三景实跑（含 ops_convergence 挂起→重开续跑关单）；metrics_create_settle 与 CREATE 侧 settle 对账。
12. **§6.8 出包回归子集**：按 plan_selftest_coverage §6.8 常备子集随本版执行（桥在席工具抽验 + Diag 补读含桥连通耗时行）。
13. 余项沿袭：E4 切后台 flush（编辑中切后台→回前台内容在、标题草稿未被连带提交）、宽屏 V-6/IMG-04、Gallery 删/排序手感与视频插入真机路径、U4a 六景装后桥跑（随 M3a 设备点合并执行）。

## 六、遗留与注记

- Web 兼容批遗留：w3 第 6 步依赖宿主本地 12MB 真实备份夹具（未随仓、tree 缺席）为缺席响亮跳过，夹具迁 tree 后自动恢复（impl_web_block_compat 既有登记，本组版未变）。
- E1 编辑回路（拼音守卫等）落码门已开（本组版提交落定、树净），按队列续派。
- tree 根分区磁盘告警（95%+）为环境项，建议下轮冒烟前清理。
