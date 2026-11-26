# 斜杠面板定位根治 + 键盘删块收口 — 取证落盘（停线交接）

状态：**取证与修法设计已完成，落码未开始**。落码闸门：920f9bb 之后 ≥11 笔新提交（主线 2026-11-23 两次顺延后的现行口径）。落盘时 HEAD = 45b5b46（第 7 笔）。闸门临近时主线凭本文件重新派发落码；落码前须以届时 HEAD 重读相关代码（bridge.rs / editor.rs 行号在他线推进中持续漂移，本文行号为 b140b75–45b5b46 时代口径，只作定位参考）。

任务构成（两部分同批落地）：
- 第一部分：斜杠面板位置跟随调用点根治（用户真机反馈：正文下半部输入唤出面板，面板却显示在上半部、与输入位置脱节）。本单只提前抽 landing_plan 批 2（斜杠面板 14 项）中的「定位」一项，其余 13 项不动。
- 第二部分：键盘删块路径按块性质收口。不变量（用户裁量、已定）：**键盘输入永不直接删除非文本块**；删卡只走长按/右键菜单一条明路。

---

## 一、量测环境与方法

- 被测对象：与生产逐字节一致的 dist（构建戳 1fb1dabd18，sw.js VERSION 已核、wasm md5 一致），下载于 `/tmp/slashdist`，`python3 -m http.server 8213` 本地服务。原版对照：仓库根 Moment.html 以 `python3 -m http.server 8214` 服务。
- 工具：Playwright（chromium_headless_shell-1255，`hasTouch: true`），视口 393×852（单栏）与 1440×900（双栏）。
- **全部结论为 Chromium 口径**；真机（iOS WebKit）几何待落码后复核，不得据此宣称真机已修。
- Fixture：60 段长备忘 + 键盘路径专用混合块备忘组，经 ZIP 导入流程注入（构造法同 probe_bridge_input）。

脚本位置（仓库根，未跟踪）：
- `probe_slash_anchor.mjs` — **本批验收探针（已校准，见 §五）**，落码时注册进 run_all_tests.sh + TESTING.md。
- `.scratch_slash_anchor.mjs` — 第一部分主量测（上/中/下/双栏）。
- `.scratch_slash_ancestor.mjs` — 祖先链与独立滚动量测。

---

## 二、第一部分定性：现行锚定机制错在哪

### 2.1 现行机制（读码证实）

- 桥（editor/bridge.rs input 处理，~940 行）：输入 `/` 后取选区 range 的**最后一个** client rect，发 op `slash` {x, y=top, b=bottom}；无 rect 时兜底块 rect。
- editor.rs `slash` 臂（~3976）：存 panel 信号 `(bid, filter, x, top, bottom)`。
- SlashPanel 组件（editor.rs ~5817）：渲染时算定位——width 按原版启发式；`left = min(vw−width−12, anchor_x−8).max(12)`；`top = anchor_bottom+10`；若 `top+260 > vh−8` 则上翻 `top = max(anchor_top−270, 76)`；vw/vh 取 `window.innerWidth/innerHeight`。
- CSS `.slash-panel`（styles/editor.css:1436）：`position:fixed`，`max-height:320px`（静态）。
- 既有跟随机制（滚动审计 S3，editor.rs ~1882 起）：use_effect 注册 window scroll 监听（__mnEdScroll，Δy>2 才发）；滚动消息到时若 panel 开着，spawn eval 调桥 `window.__mnSlashAnchor(bid)`（bridge.rs ~2473：选区在该块内取 caret rect（最后一个）、**否则兜底块 rect**），回更新 panel 信号锚点。

### 2.2 逐项量测（393×852，Chromium 口径）

| 场景 | 调用光标 rect | 面板 rect | 结论 |
|---|---|---|---|
| A 顶部块 | bottom 172 | top 182，gapBelow=10.0 | ✓ 正常 |
| B 中部块 | bottom 442 | top 452，gapBelow=10.0 | ✓ 正常 |
| D 下半部翻转带 | bottom 567 | top 577、**bottom 897，溢出视口底 45px、未翻转** | ✗ 缺陷（见 2.3-②） |
| C 底部块 | bottom 802 | 翻转触发，top 515、bottom 835，覆盖光标行 50px | 与原版同形态（见 2.4），不算回归 |
| E 窗口滚动 +240 | — | 面板跟随，gap 仍 10 | 跟随机制存在（仅 window 滚动） |
| 双栏 1440×900（流式/独立） | 左右栏各一处 | gapBelow=10，left 跟随本栏 caret（57 vs 793） | ✓ 开错栏假设证伪 |
| 独立滚动模式栏内滚动 +200 | caret 移至 −19 | **面板不动（top 191→191），gap=210 脱节** | ✗ 缺陷（见 2.3-③） |
| 祖先链 | — | 无 transform/filter/backdrop-filter/perspective 祖先，offsetParent=null，真 fixed | 「变换祖先困住 fixed」假设证伪 |

### 2.3 三处移植缺失（定性结论）

**① 定位公式丢 visualViewport 补偿项 — proven（代码级）。**
原版公式（src/app/editor/use-slash.js `computeSlashAnchor`）的 viewportLeft/Top/Width/Height 全部取 visualViewport（fallback inner*），left/top/翻转判定都带 vv 偏移项。Rust 移植只用 innerWidth/innerHeight。真机键盘弹起时 vv 高度/offset 与 inner* 分叉——这是用户真机「下半部输入、面板跑到上半部」的主因（代码级 proven；真机几何待复核）。

**② 丢动态 max-height 上限 — proven（Chromium 实测，D 带溢出 45px）。**
原版渲染（src/app/editor/slash-panel.js:129）带内联 `maxHeight: min(320px, calc(100dvh − (anchor.top+16)px))`，面板永不溢出视口底（D 带靠收缩而非翻转解决）。Rust 只剩 CSS 静态 `max-height:320px`；且翻转判定用估算高 260——D 带 `577+260=837 < 844` 不翻转，但面板实际高恒 320（空过滤时内容 scrollH=1186 被 320 封顶），于是溢出。

**③ 跟随覆盖缺口 — proven（独立双栏栏内滚动实测脱节，gap 210）。**
S3 路径只认 window 滚动（scrollY 变化；Δy>2 守卫）。栏内容器滚动不触发（scrollY 不变）；visualViewport scroll/resize、selectionchange 均无监听。原版在面板打开期间注册 window scroll/resize + **visualViewport scroll/resize** + document **selectionchange**，rAF 节流全量重算锚点，关闭即摘。

### 2.4 与原版同形态、不改的点

- C 场景翻转带覆盖光标行 50px：翻转几何按 260 估算、面板实际 320 所致；原版同公式同形态，不算回归、不单独改。
- 原版锚点取法：以 focusNode/focusOffset 新建 collapsed Range，取 `getClientRects()`**[0]（第一个）**；全零 rect 时插入零宽 marker span 量测后移除并恢复选区；再兜底块 rect。Rust 现行取最后一个 rect——落码时按原版收敛（见 §三）。

### 2.5 链接表单脱锚链（S6）— proven（Rust 与原版双侧实测）

链接表单与斜杠面板同组件同锚（SlashPanel 的 link 态，锚存 link_pos 信号），同批同修。其实测缺陷链：

1. 鼠标点击链接行（SlashPanel onclick，editor.rs ~6024）只设 `link_for`，**不设 link_pos**（键盘 Enter 路径经 `slashLink` op 在 editor.rs ~3987 以 panel 现值设 link_pos——两条路径不一致，属潜伏 bug；当前渲染结构下 panel 信号仍在、表单借 panel 分支渲染，此项暂不显形）。
2. 表单 input 自动聚焦 → 编辑区 focusout → 桥 S8「失焦回顶」（bridge.rs ~1005 起：新焦点不在 `.editor-body`/标题坞内即 scrollTo(0,0) + forceTop 重发）触发——面板不在 `.editor-body` 内，被判「焦点离开编辑区」。实测 scrollY 852→0，Diag 有 `EDIT blur -> force unscrolled (S8)`。
3. 回顶滚动触发 S3 审计重锚：`__mnSlashAnchor` 在选区已离开调用块（焦点在表单 input）时**兜底返回块 rect**——块随页面回顶移到视口外（top 420.3+852=1272.3），新锚写回 panel 信号，表单经 panel 分支以新锚渲染，翻转 top=1272.3−270=**1002.3（与实测逐值吻合）**，表单整体落在视口外（bottom 1322 > 852）。
4. **原版对照实测**（393×852，同场景）：原版点链接行后 scrollY 同样 380→0（S8 是原版行为、两边一致），但**面板纹丝不动停在 top=464**。原版重锚是选区驱动（updateSlashStateFromSelection）：选区离开编辑区时锚点状态保持不变。

结论：S6 的根因不在 S8（原版同有），而在 **Rust 的重锚路径在选区已离开调用块时仍用块 rect 兜底改写锚点**，与原版「选区不在块内则锚点不动」的语义分叉。修法见 §三第 3 点的守卫。

### 2.6 同类浮层排查（已毕）

| 浮层 | 锚定机制 | 判定 |
|---|---|---|
| 链接表单 | 与斜杠面板同组件同锚（link_pos） | **同病同批修**（§2.5） |
| 编辑器菜单 / 导出面板 | 锚固定页头钮（editor.css:1297，fixed + dvh 上限） | 无此病 |
| 图文 / 背景底表 | fixed 底表 | 无此病 |
| 备份弹窗 | inset:0 scrim + 底表 | 无此病 |
| 灯箱 | 全屏 fixed | 无此病 |
| 卡片菜单 | 已锚卡（任务书明示不算） | 不计 |

---

## 三、第一部分修法设计（落码照此执行）

1. **桥内锚定计算收敛为单一 helper**（开启与重定位共用）：按原版法取 fresh collapsed range 的第一个 rect；零 rect 走 marker span 兜底；再兜底块 rect。现行 input 路径（取最后一个 rect）与 `__mnSlashAnchor` 一并改走它。
2. **SlashPanel 定位公式逐项恢复 vv 项**：Rust 侧以 web_sys 读 `window.visual_viewport()`（offset_left/top/width/height，缺失 fallback inner*）；left/top/翻转判定与钳制全按原版式。style 增内联 `max-height: min(320px, calc(100dvh − (top+16)px))`（CSS 静态 320 保留作兜底）。
3. **跟随补全 + 选区守卫（桥侧，原版同构）**：
   - 面板在场期间（以 `#slash-panel` 是否存在为守卫，链接表单同 id 同守）注册：capture 阶段 scroll（吃栏内容器滚动）+ window resize + visualViewport scroll/resize + document selectionchange；rAF 节流重算锚点，发新 op **`slashPos`** 只更新坐标。editor.rs 该臂：panel 为该 bid 开着则更新 panel 坐标；link_for 为该 bid 则更新 link_pos；面板已关/换块则 no-op。
   - **守卫（S6 根治点）**：重锚仅当**当前选区仍在调用块内**才生效；选区已离开（焦点在表单 input、选区在别处）则不发/不应用新锚，锚点保持。既有 S3 路径的 `__mnSlashAnchor` 同步加此守卫（选区不在块内返回 null；editor.rs 消费端对 null/缺字段已有跳过逻辑，见其 ~1925 行 `if let (Some, Some, Some)`）。S3 路径保留（改走统一 helper 后与新路径同值、幂等）。
4. **Diag**：重定位实际发火更新时记一行（节流后）。
5. 顺带一致化（可选、落码时裁量）：鼠标链接行路径与键盘路径统一——onclick 设 link_for 的同时以 panel 现值设 link_pos（需把 link_pos 作 prop 传入 SlashPanel），消除 §2.5-1 的潜伏不一致。

验收断言见 §五探针 S1–S9。

---

## 四、第二部分：键盘删块路径枚举矩阵（审计已毕，逐条读码证实）

口径：文本分类 = editor.rs:470 `is_text_block`（paragraph/heading/quote/todo/callout/list-item/codeBlock）；prev_sibling/PrevKind 在 editor.rs ~4364（列表归其末项、空列表归 Atomic、其余顶层块归 Atomic）。sel_block 来源已核：桥 click 路由的 selectBlock（图文卡文本区非编辑态、卡片本体点按兜底）与 op_merge——只装原子/卡片块。原版基线（src/app/editor.js:2116）：空块段首退格在原版是跳过 contentEditable=false 原子块找上一可编辑块、找不到就保留空段——Rust 的 K3「选中原子块」是分块架构的等价承载且合裁定（至多选中），文本合并语义以现行（已按原版对齐）为准不重动。

| # | 路径 | 现行行为 | 判定 |
|---|---|---|---|
| K1 | 选中原子块（sel_block）+ Backspace/Delete：桥 document 级 keydown（焦点不在可编辑区时）发 op `deleteSelected`（bridge.rs ~1195/1252），editor.rs ~3771 删块落盘 | 删卡 | **改**：键盘不再发 deleteSelected（BS/Del 在选中态无操作、Esc→clearSelect 保留）。菜单删除是 editor.rs ~3095 的 Dioxus onclick 直删（Diag "card menu delete"），不经此 op，收口不误伤 |
| K2 | op_merge（editor.rs ~4402）Atomic 支、当前块**非空**、块首退格且前块为原子块 | **删原子块**、当前块保留（Diag "merge: backspace over atomic deleted"） | **改**：不删；改为选中该原子块（sel_block.set，与 K3 同落点），两块与文本全保留 |
| K3 | op_merge Atomic 支、当前块为空 | 删当前空块 + 选中原子块（Diag "merge: empty block removed, atomic selected"） | **留**（合裁定「至多选中该卡」） |
| K4 | 音乐输入胶囊段首退格：桥 musicInput 支发 op `musicDelete`（editor.rs ~4113） | 删音乐卡块、焦点回上块末（原版 resolvePendingMusicUrl 口径） | **改**：不删块；仅焦点移回上一可编辑块末尾，无上一块则无操作；胶囊保留（删除走卡片菜单） |
| K5 | op_replace_range（editor.rs ~4591）：xsel 跨块选区 + BS/Del/打字/Ctrl+X/粘贴/Enter（桥 sendReplace） | 选区内中间块整块丢弃（**含原子块**）；from_start/to_end（Ctrl+A）连首尾外侧原子块一并丢弃 | **改**：原子块全程存活——重组循环中存活原子按原位保留、按原子边界分段：首段承接 head+插入文本、末段首单元承接 tail（enter 时 tail 归末段）、Ctrl+A 边缘原子只保不删。存活判定 = 非文本块且非「含项列表」（空列表按 Atomic，与 prev_sibling 分类一致）。无原子介入时行为与现行逐字不变 |
| K6 | 文本块块首退格、前块为文本块（op_merge Text 支合并） | 合并、dom 回写存活块、光标落接合点 | **留**（原版基线口径） |
| K7 | MD 源段/代码块段首退格（桥 mdsrc/codeBlock 支发 op `merge`） | 同文本合并 | **留**（裁定③：MD 源段按文本块同规，无独立整块键盘删除路径）。探针进入方式：MD 块非编辑态是 `.md-hit` 预览（data-bids），点击后进入 btype=mdsrc 源码态再退格；注意编辑器文末另有临时 bid 的空可编辑区，勿误点 |
| K8 | 块内选区/逐字删除（原生 contenteditable，beforeinput 仅拦 historyUndo/Redo 与粘贴快照） | 块内文本删除 | **留**（文本编辑本身） |
| K9 | 文本块块尾正向 Delete 跨块 | **无此路径**（分块 contenteditable 内原生无操作，桥无 deleteContentForward 跨块拦截） | **留**（无删块路径、与不变量自洽） |
| K10 | 选中原子块 + 打字/Enter | 无处理器、焦点在 body、键入无操作 | **留** |

探针逐路径断言见 §五（K1–K7）。

---

## 五、验收探针校准结果（probe_slash_anchor.mjs）

探针在生产构建（1fb1dabd18）上已跑通校准：**恰 11 条目标断言变红、其余 20+ 条全过**（通过项即回归守卫）。红项清单（落码后须全绿）：

- S3 下半部带面板溢出视口底（bottom=897 > vh−15）
- S6 链接表单锚点被回顶重锚改写（top 452→1002）、表单溢出视口
- S9 独立双栏栏内滚动后面板脱节（gap 210）
- K1 选中卡 Backspace 删块（Delete 断言之红是 Backspace 先删的连带，落码后两条独立全绿）
- K2 块首退格删卡（卡消失、无选中）
- K4 音乐胶囊段首退格删音乐块
- K5a 跨卡选区删除图片被丢（结果合并为一段 'aabb'）
- K5b Ctrl+A 删除后图片/画廊被丢

断言口径要点：
- 下置态 gapBelow=10±2；翻转态（S4）top=max(76, caret.top−270)±2 且面板底与光标行差在原版带内（−12..54，实测 50）；任何态面板完整落在视口内（bottom ≤ vh−14）。
- S5 窗滚跟随、S7/S8 双栏两栏锚定在生产上已过，作回归守卫。
- K5b 断言位置宽松：原子块按序存活 + 恰一个空段承载光标（承载段位置随实现）。
- K7 断言：非空块恰一个且文本为「前文## 标题行」（合并后文末临时空段不计）。

注意事项：
- fixture 中 MD 段（`## 标题行`）在导入/打开时可能被重新赋 id，探针已按 `.md-hit`/`[data-btype="mdsrc"]` 动态定位，不依赖固定 bid。
- S6 须先输入过滤词「链接」使链接行进入面板可见区再真实点击（行在面板内部滚动区外时 rect 在视口外，真实点击会落空——此为探针手法、非产品行为）。

---

## 六、未完事项清单（落码清单）

闸门：920f9bb 后 ≥11 笔（现 7 笔：…b140b75、45b5b46）。闸门开后按序执行：

1. 以届时 HEAD 为基线重读：bridge.rs（input 处理、`__mnSlashAnchor`、S8 focusout、deleteSelected 发送处、musicInput 支、sendReplace）、editor.rs（`slash`/`slashLink` 臂、SlashPanel 组件与链接行 onclick、op_merge、op_replace_range、deleteSelected 臂、S3 消费端）、editor.css `.slash-panel`。注意他线（安全区实心栏、过渡弹跳、拾起重构等）可能已改动其中若干处，逐处核对后再落码。
2. 第一部分按 §三落码（helper 收敛 / vv 公式 + 动态 max-height / slashPos 跟随 + 选区守卫 / Diag）。
3. 第二部分按 §四落 K1/K2/K4/K5 四改（K3/K6–K10 不动）。
4. 探针 `probe_slash_anchor.mjs` 注册进 run_all_tests.sh 与 TESTING.md（注意 run_all_tests.sh 当时可能有他线未提交改动，合并时逐行核对）。
5. 验收：新探针全绿 + cargo test + verify_rustweb.sh 七节 + run_all_tests ALL GREEN → `/tmp/mynote_build.lock` 构建 → deploy_api.py 部署 → 线上逐字节核对（sw VERSION / wasm md5）。
6. 提交：只 git add 本批文件；不碰 native/app、probe_pages_settings.mjs 与他线文件；提交信息转述、不引原话。
7. 回报主线：定性结论（本文件 §二/§四）、逐处量测、提交哈希、构建戳；真机复核项单列（vv 几何、链接表单跟随手感属 Chromium 口径外）。

与批 2 的关系：批 2（斜杠面板余 13 项）仍按原计划排队；若落码时发现与批 2 某项同源冲突，回报主线。
