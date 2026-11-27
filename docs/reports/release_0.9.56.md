# 0.9.56 组版报告（U1 自检驱动 + 完成竖向胶囊 + 首页两线）

2026-11-27。基线 9d9dd9f（0.9.55）→ 推送四笔 ab3c96e / 4e1a36d / 0fa5a0c / 297ad13 + 本报告笔（哈希见 git log）。版本 0.9.56 / build 83。本版三批：U1（自检驱动核 + S1 + B-4 落点映射 + 在席四工具入册，桥清单 22→31）、完成竖向胶囊（用户直接规格）、首页两线（搜索胶囊回缩根治 + 布局对齐）。桥清单变更，中继随版重部署（见第七节）。

## 一、提交分拣（四笔，归属逐段核对）

| 笔 | 哈希 | 内容 | 归属核对 |
|---|---|---|---|
| 1 U1 | ab3c96e | 新文件 MomentBridgeUITest.swift / TitleTextField.swift / TitleTapCaret.swift / tests/title_tap_caret_main.swift；MomentBridgeProtocol.swift、MomentBridgeTools.swift、bridge/relay/worker.js、build-app2.sh 全量；MomentApp.swift 标题字段/胶囊/B-4 段 12 hunk；verify [16]/[24]/[25]/[26] 段；plan_app_mcp_bridge.md §3.4 错误表补 nav 两行；impl_uitest_u1.md | 提交序先行——完成胶囊批复用了本批的 toggleEditorMenu 与 TitleTextField 提交链，不可颠倒。暂存 MomentApp 经标记核查：含 TitleTextField/UITestAnchor 字面 5 处、胶囊批/首页批标记（moreCapsule/glassLabelAccent/searchFocused）0 处 |
| 2 完成胶囊 | 4e1a36d | MomentApp.swift 页眉尾随/EditorUI/BlockTextView 段 6 hunk + verify [29]（尾 hunk 前段）+ impl_editor_done_capsule.md | 暂存经标记核查：首页批标记 0 处；[29] 以尾随追加入本笔，[30] 于下笔以 [29] 尾行为前文构造插入（同 0.9.55 尾 hunk 拆法） |
| 3 首页两线 | 0fa5a0c | MomentApp.swift 的 enum T/AvatarView/ListView/CompactTitle 段 24 hunk + verify [30] + fix_home_search_layout.md | hunk 全在 enum T（glassLabelAccent）与 14517 行后（AvatarView 起），与前两批段零交叠 |
| 4 版本 bump | 297ad13 | build-app2.sh + MomentApp 设置页版本串 | 见第三节 |

分拣方法：MomentApp.swift（42 hunk）与 verify_ios.sh（10 hunk，尾 hunk 为 [29]+[30] 连排）为三批共改文件，按各批报告改动清单以标记词逐 hunk 分类（变更行口径，注释提及不计）、补丁级暂存（git apply --cached --recount）；分类 MANUAL 项逐个看过变更行实样（[16] 工具名清单、T24-5、B25-U0-5 改写均属 U1）。四笔提交后 git status 对 tracked 文件干净，最终 HEAD 树与三批原始工作树逐字节一致。

仓外同步（不入本仓 git）：连接器 custom.moment-bridge 的 CONNECTOR.md 与 bin/client.py（ALLOWED_TOOLS 31 件 + nav 两码说明）、tree-sync/push_small.py 名单（+3 文件）已由 U1 批落盘，本版核对在位。

## 二、本版三批要点（细节见各批报告）

- **U1（impl_uitest_u1.md）**：驱动核 MomentBridgeUITest.swift（锚点注册表照 DragPressAnchor 模式；uitest 四件全归 ops 层、中继双门、uitest_run 两段提交、安全模式 safe_mode_limited 不入受限集；模拟点击只走具名入口、零写死睡眠）；S1 标题二次编辑回路九步（步 5 waitDiagPair 核心；夹具双标记 + 卫生链 + libraryHash 对账）；B-4 落点映射路径 B（TitleTextField representable + TitleFieldControl 单一真相，入口 activateTitleFromCapsule(atX:) 签名冻结，纯函数 19 例 tree swiftc 真跑 19/19）；在席四工具入册（editor_open/get_state/focus_block/save_now，nav 两码三方登记，get_state 不回正文摘要；清单总数与哈希见第七节更正）；在席守卫补齐（软删接入，消费点三处；restore/permanent 经不变量论证无需守卫）。
- **完成竖向胶囊（impl_editor_done_capsule.md）**：••• 圆钮与键盘态完成同容器变形（宽 46、帧高 46↔92、顶锚定、玻璃单面）；勾形 CheckmarkGlyph 纯 Path；触发单源 kbVisible 边沿发布，抑制六格；完成动作逐字复用旧辞焦链，旧两处「完成」钮连构造码删净零残留。
- **首页两线（fix_home_search_layout.md）**：线 A 定因——搜索展开态由独立 searchOpen 标志驱动、与焦点脱钩（回车只辞焦不改标志）；根治为 @FocusState 单点派生 + 辞焦收敛四路（submit/clear/system/nav 来源记账）。线 B 布局占位账逐段对 Web 量测落码（首卡顶距、分组头合成距、网格组头、空状态双形态、chip 体系、材质档、恐龙回退图）；调优候选只列报告待裁、未落码。

## 三、版本 bump 位置（与前版同位置，逐一核对）

- `build-app2.sh` 内嵌生成的 Info.plist 段：CFBundleShortVersionString 0.9.55→**0.9.56**、CFBundleVersion 82→**83**。
- `MomentApp.swift` 设置页版本串 Text("0.9.55")→Text("0.9.56")。

## 四、本机 verify 自跑（组版前基线）

**254 ✓**，余 2 ✗ 均为既有产物类（ipa 陈旧、产物语言包），tree 构建后自解（见第五节）。[25]/[26]/[29]/[30] 各组本机全绿。

## 五、tree 冒烟（smoke_ios.sh 全量，/data/home/smoke56-tree.log）

- 同步：push_small.py 全量 overlay 传输 md5 对账全 OK，拷入 tree 克隆 /opt/work/Moment 后核对关键标记（moreCapsule ×2、build 脚本 0.9.56、中继 uitest_run）在位。
- 首跑：[smoke 1/4] cargo test、[2/4] FFI 重建、[3/4] ipa 构建全过；[4/4] verify **255 ✓ / 1 ✗**——唯一红项 T26-4，其查的 tests/title_tap_caret_main.swift 本地在册（U1 笔已提交），但 push_small.py 传输名单漏列该子目录文件，tree 工作副本缺失所致，**非代码缺陷、与 ipa 产物无关**（该文件不入 App 构建）。
- 就地修：补传该文件（md5 be066c76 对账 OK）+ push_small.py 名单补 tests 子目录条目（防下版再漏）；tree 单跑 verify_ios.sh 复核 **256 ✓ / 0 ✗，ALL PASS**（/data/home/verify56-tree.log）。冒烟门以「1–3 步首跑全绿 + verify 补齐后全绿」构成为全绿，过程如实记于此。
- 构建产物：Moment-stage2.ipa 11,007,550 B（tree 侧）。

## 六、取包

- pull_ipa.py（LOCAL 改本版）分片回传，远端/本地 md5 对账一致：**11,007,550 B，md5 `3deccf87de7f59efc8f7f45ebd33c125`**。
- 成品：~/workspace/your_files/Moment-0.9.56.ipa（交付件）。

## 七、中继重部署（清单变更随版必办）

- 部署：bridge/relay/deploy.py（multipart 上传）→ PUT workers/scripts 200、POST subdomain 200。
- 逐字节核对：经 CF API 下载线上脚本，模块主体与仓库 worker.js **逐字节一致**（43,031 B，md5 9525fa6a…）。
- 工具面实测：既有配对密钥调 list-tools 回 **31 件齐**（含 uitest 四件与在席四件）；bridge_status 回 app_offline（App 仍为 0.9.55 且未在前台，正常码，与 M2 部署先例同）。三方哈希对齐待用户装 0.9.56 后 App 上线自洽（staging 态同前例）。
- **清单口径更正（以落码实物为准）**：本版清单为 **31 件、manifestHash `a52116c3…`**——U1 报告的「30 件 / c0c991a6」未计布防批入册的 rescue_arm_safe_mode（+1）；App BPROTO、verify B16-3/B16-15 断言、中继 TOOLS、连接器 ALLOWED_TOOLS 四处实物均为 31 件 / a52116c3 且逐名一致（tree verify 已锁），属批报告数字滞后、非代码不一致。

## 八、CI（本版顺手补核，待补核项关闭）

未认证 GitHub API 本次可用，moment-rust-web 工作流实查：本版 HEAD 297ad13 **success**；连同补核 0.9.55 的 b9617d7 **success**、0.9.54 代码态 f629be0（bump 笔，其后仅组版报告 docs 笔）**success**——0.9.54 起「CI 正向 success 未查证」的待补核项就此关闭。再往前 1f93642（僵尸键根治）success、8a6cadb 及更早为根治前连红，与既有定案一致。

## 九、S1 真机首跑（主线在用户装后走桥远程执行）

- **执行方式**：用户装 0.9.56 后，App 前台在位时主线经桥以现配对（read+ops，uitest 全归 ops 层、无需 write 重配对）调 `uitest_run` 跑 S1（两段提交取 actionToken 后正式提交），轮询 `uitest_get_result` 至终态，再以 `diag_tail` 复核会话行。
- **判读口径**：终态码 ok 且九步全过、步 5/步 8 两轮 waitDiagPair 均判「via 与 begin 成对各一」为绿；失败先分签名——「只有 via 无 begin」= 置焦未达（旧结构失败签名）；restore_failed/hygiene_failed = 复原/卫生链问题（全场结论降格，不作 S1 功能结论）；aborted_user_active = 作业期间用户动了界面，重跑即可。两遍结论一致才算运行级终判落定；单遍绿只记首跑通过。
- **诚实边界**：驱动绿 proven 的是焦点状态机、布局几何与落盘对账；真实触摸投递、识别器仲裁、键盘/光标/拼音组字、像素栅格化仍为 unknown、真机终判——S1 绿不等于「用户点得动」，标题胶囊的真机判读仍以用户点按 + Diag 成对行为准（0.9.55 已闭环）。

## 十、真机终判点汇总（三批）

### U1 / B-4
1. 长标题截断态点胶囊：光标落到点按位置附近的字（不再一律跳文末）；点省略号上/后落全文末尾。
2. 标题二次编辑回路（点开改过一次的长标题再点）仍可进入（0.9.54 修复 + 0.9.55 锁存不回归）。
3. S1 首跑由主线走桥执行（第九节），用户无须手工复现。

### 完成竖向胶囊
1. 块编辑键盘升起：••• 向下长成竖向胶囊、••• 本身位置不动、无跳位。
2. 点勾：键盘落下、标题/正文改动已提交、胶囊缩回圆钮。
3. 标题编辑中点勾：改名生效（commitTitle 链）后再开标题应为新名。
4. 键盘态点 •••：胶囊缩回与菜单打开同拍、无重叠残影；关菜单（键盘仍在）胶囊复展。
5. 滑动收起键盘：胶囊同步缩回；字段间点按转移焦点时胶囊不闪退。
6. 长按拾起拖拽中：胶囊保持圆钮。
7. 勾形观感与描边量级、淡入是否抢拍——视觉项真机判读。

### 首页线 A（搜索胶囊）
1. 点搜索胶囊 → 键盘升起且胶囊保持展开（字段插入即持焦，无闪烁回落）；桥 diag_tail 应见 `APP search capsule open` 恰一行。
2. 输词后点回车 → 键盘收、胶囊回缩成触发钮、列表仍按词过滤；Diag 见 `close src=submit`。
3. 重新点开胶囊（词还在、× 在）→ 点 × → 词清、胶囊收；Diag 见 `close src=clear`。
4. 展开态上滑列表 → 键盘交互收起、胶囊随之回缩；Diag 见 `close src=system`。
5. 展开态点开一篇备忘 → 键盘收、进编辑器；返回首页胶囊为触发态、词保留；Diag 见 `close src=nav`。

### 首页线 B（布局）
1. 首页静止位：新建卡与头像下沿的间隙明显打开（≈56pt，与 Web 同量级），滚动时卡片仍从页眉下穿行、紧凑进度无跳变。
2. 分组头：组与组之间文字上下距均匀（28/6）；英文语境下组名为大写。
3. 空库/零结果/加载失败三态：纵距舒展、说明限宽居中、动作钮变宽（22/9）。
4. 标签 chip：蓝字、带边、高变足（长标题备忘上最易见）；方卡 chip 同。
5. 无头像时恐龙变大且沉底（贴圆底）。
6. 滚动到紧凑态：「此刻」胶囊与搜索展开面板的底色档位与菜单浮层同族（实色 overlay），深色下尤可辨。
7. 网格组头距首行方卡收紧（合成 8）；负底距在 LazyVGrid 下的实际响应以此项为准核。
