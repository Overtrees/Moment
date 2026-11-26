# 页面/弹窗退出过渡「弹跳」排查进度落盘（2026-11-23 停线版）

状态：**取证量测已完成、根因已定、修法已设计、验收探针已备并验证区分力；落码未开始**。
停线原因：落码闸门随提交链插入多次顺延（920f9bb 之后 ≥8 → ≥9 → ≥10 → ≥12 → ≥13 笔），
停线时点链上计数 = 7（HEAD 45b5b46）。后续凭本文件重新派发即可直接进入落码，
量测不必重做（基线变化注意见文末）。

口径声明：全部量测为 **Chromium（headless shell）口径**，不等于 iOS 真机结论；
用户真机复报（设置页、备份页、确认弹窗等退出时仍有弹跳）是 ground truth。
成因分级：proven = 时钟/帧级实测直接证明；inferred = 机制自洽推断；unknown = 未测或不可测。

---

## 一、已测路径逐条（跳变 px / 发生时点 / 成因分级）

量测基线：生产逐字节 dist（量测时点 sw VERSION `cbf7e480c7`、wasm md5
`cbf7e480c7ba6e7eee3e9817271e0506`）vs 原版 `src/Moment.html`（React 18）。
方法：rAF 逐帧采样地标元素 rect、scrollTop、根背景色、视口高；
动画时钟判别（Animation.currentTime 逐帧读数）区分「几何停滞」与「时钟冻结」。
未节流（1x）与 4x CPU 节流（慢设备口径）两档。

| 路径 | Rust 1x | Rust 4x 节流 | 原版 1x | 原版 4x |
|---|---|---|---|---|
| 设置→列表 | 干净：交换 1 帧完成、动画内步进 ≤7.1px、定格后 0 | **缺陷**：进场动画 currentTime 在 from 姿态冻结 84ms（anim_clock 时钟级实测）；另一轮几何停滞 ~116ms + 单帧步进 17.9px | 干净（步进值与 Rust 几乎逐值同形） | 干净：交换同帧、步进 ≤6.9px |
| 备份→设置 | 干净 | 此轮干净（设置页轻、挂载块短，与机制自洽） | 干净 | 干净（步进 ≤5.1px） |
| 编辑→列表 | 干净：根色与列表首帧同帧到达（交换后 369ms 帧） | 步进粗化、末段 6.8px 二次步进（与动画时钟迟滞同源，inferred） | 干净（存量备忘；根色同帧 378ms） | 未测 |
| 备份确认弹窗 开/关（取消、确认两路） | 干净：页面零位移、零滚动、零根色变 | 干净 | 原版确认表为条件渲染、无进场动画、瞬时关（与 Rust 同构） | — |
| 搜索退出 | 干净：列表零位移 | — | — | — |

全路径共同事实：scrollTop 全程恒定；innerHeight / visualViewport.scale 全程恒定
（852 / 1）；无任何路径出现「动画定格后 >1px 步进」。

验收探针（probe_page_transitions，见第五节）对修复前 dist 的复测（4x）：
设置→列表 ct 起步于新页首现后 117ms（判据 ≤40ms，败）、单帧步进 11.8px（判据 ≤10px，败）；
编辑→列表 ct 起步 133ms（败）、步进 11px（败）；定格后步进与根色同帧两项全过。
探针按设计变红，区分力已验证。

**根因（proven）**：串行交换设计下，新页进场动画与新页挂载在同一提交内应用；
挂载后的主线程长任务（Dioxus 提交 + 效果链）使动画的首次样式变更事件迟到，
currentTime 冻结于 from 姿态（4x 实测 84ms），页面以 24px 偏移静止坐住，
任务清空后动画才起步走完——视觉即「退出时顿一下再弹」。原版同为串行交换设计，
但 React 挂载成本近零，冻结不可见。退出侧的定时卸载、根色、滚动均无辜；
缺陷纯在「进场动画启动被挂载长任务门控」。

原版探查附带事实（重派时注意）：原版列表首个列表项是「新建笔记」（新空备忘），
其关闭走删除路径（保存 _delete 后直接重渲列表、编辑器根无 slideOut 即被移除）；
编辑退出基线必须开存量备忘（harness 已按第 3 条备忘测）。Rust 侧开种子备忘为
正常备忘、slideOut 完整——两版此路径行为差异属既有口径，非本单缺陷。

## 二、六假设裁定（逐个证实/证伪）

- ① closing 动画时长与卸载时机错位：**证伪**。anim_clock 实测设置出场
  currentTime 与墙钟同步、卸载发生于 ct≈267–280/280；编辑器 320ms 定时同口径。
- ② animDone 的 animation:none 覆写与新进场动画叠加冲突：**证伪**。
  无任何定格后步进或残留 transform 效应。
- ③ 弹窗关闭时滚动锁释放导致位移：**证伪**。全站无滚动锁机制；
  全部路径 scrollTop 全程恒定。
- ④ 根背景色同步链滞后一帧：**页面退出面证伪**。编辑退出根色与列表首帧同帧
  到达（1x/4x 皆然），open_memo / on_close 的同步先行同值写入有效。与「安全区
  实心栏」一单**不同根、不合流**：那单已定案为模态压暗未接入 apply_root_bg
  派生链（用户 2026-11-23 定：Rust 0.28 压暗保留、只修根色同步完整性）；
  本单实测模态开/关对根色与几何零影响。
- ⑤ 视口单位（dvh）在弹窗开/关时重算引发布局跳变：**证伪（Chromium 口径）**。
  innerHeight / visualViewport 全程恒定。iOS 真机口径 unknown（见未测清单）。
- ⑥ 焦点/键盘收起引发尺寸变化：**点名路径证伪**。搜索退出干净；
  设置/备份/弹窗路径无键盘参与。

## 三、未测路径清单（重派时按需补测，勿默认干净）

1. 编辑→列表 **原版 4x**（Rust 4x 已测、原版仅 1x）。
2. 诊断页→设置、语言页→设置退出（同为 .page-enter 组件页，机制与设置/备份
   同构，inferred 同类风险；未量测）。
3. 图文卡底表开/关：未测。注意基线已变——交互专项 b311293 后非编辑态点
   itc-text 只选中不开底表，须走菜单编辑入态；仓库内门外旧探针
   probe_exit_anim、probe_pages_editor_rust2 仍按旧口径写、未在门禁环内，
   **不得拿其旧断言当基线**。
4. 列表长按菜单浮层开/关：未测。
5. 前进方向进场：列表→设置、列表→备份仅有间接证据（备份→设置 4x 干净）；
   列表→编辑器进场存在同类冻结残留（机制同源，inferred），未单独量测，
   不在本单原验收路径内，修法落地时如实回报。
6. 搜索进入（列表→搜索态）：只测了退出，未测进入。
7. **iOS 真机（WebKit）全部路径**：未测。Chromium 的动画时钟行为不能外推
   WebKit；冻结量级在真机上为 unknown，最终验收须以用户真机复测为准。

## 四、修法设计（已定稿，待闸门开后落码）

页面切换由串行交换改 **App 层栈式交接状态机**：导航即刻同时挂载新页
（上层、播进场动画）与旧页（下层、经 closing prop 播出场动画），旧页由 App
在过渡时长后统一卸载（页面对时长：含编辑器 320ms、余 280ms，公式同
getPageTransitionMs，含 reduced-motion 口径）。新页挂载长任务与旧页出场动画
（合成器驱动、不吃主线程）重叠，进场动画在出场窗口内起步。

- main.rs：page/selected 之上加 leaving 槽（Leaving { view, memo 快照,
  scroll（导航时点 window.scrollY）, gen }）+ 统一 `navigate` 入口：算
  from-view 并快照 → 执行目标状态变更（含既有根色先行写）→ spawn 计时
  （gen 匹配才卸载）→ diag 记 TRANS 一行。既有 page.set 调用点、open_memo、
  on_close 闭包全部改走 navigate / close_editor_to_list；列表滚动恢复（双
  rAF 口径不变）改在导航时点对已挂载的下层列表执行。
- 渲染：当前页沿用原 if/else 链；leaving 层渲染于当前页之前——外层
  .page-leaving（position:fixed; inset:0; overflow:hidden;
  pointer-events:none; z-index:0 显式建层叠上下文，困住其内 fixed 子元素），
  内层以 transform: translateY(-scroll) 冻结离页滚动姿态；当前页外包
  .page-current（position:relative; z-index:1）。
- **列表不作 leaving 入栈（有据偏离）**：前进导航的入页根层全不透明、挂载即
  全屏覆盖，且交换提交前浏览器保持最后一帧（列表）不重绘、无空白帧；全部
  退出路径（本单对象）的入页是列表/设置、离页是组件页，栈式全覆盖。
- settings.rs：SettingsView / BackupView 增 `closing: bool` prop；删内部
  closing 信号与 close_page 的延时卸载，返回钮即刻回调 on_back；
  page_transition_ms 拆为 pub(crate) 供 main.rs 卸载计时复用。
  备份确认弹窗不动（量测干净）。
- editor.rs：Editor 增 `closing: bool` prop（page_closing 改 prop 派生）；
  go_back 删 320ms spawn 等待，保存/同步完成即刻 on_close；App 以导航时点
  的备忘快照渲染 leaving 编辑器（绕开删备忘后 sel_memo 查无导致编辑器被
  提前卸载的既有陷阱，保出场动画与空备忘删除次序口径）；leaving 实例的
  on_close / on_open_wiki 传空 handler。
- 有意偏离原版一处（须写入提交信息）：原版串行（出场播满才交换）改重叠
  交接——原版串行在其挂载成本下无缺陷、本应用串行已证缺陷；视觉参数
  （时长/曲线/位移量）全部不变。

红线照旧：muse.edit 外科落码、禁整文件回写；只 git add 本批文件，不碰
native/app、probe_pages_settings.mjs 与其他批次文件；环境退化先停写；
新行为带 Diag。

## 五、验收探针（已备，落码时落位）

`probe_page_transitions.mjs`（现存 scratch，见第六节）：argv[2] = baseURL，
成功打印 ALL PASS。4x 节流下测设置→列表、编辑→列表，断言：
① 进场动画 currentTime 在新页首现后 40ms 内 >0；
② 地标单帧步进 ≤10px（原版基线 6.9px）；
③ 定格后（首现 +900ms）步进 ≤1px、scrollTop 恒定；
④ 编辑路径根色与新页首现同帧（±1 帧）。
对修复前 dist 实测如设计变红（数字见第一节）。落码时拷入仓库根、注册进
run_all_tests.sh 探针环 + TESTING.md，判据变更逐条写入提交信息；其后
cargo test + verify 七节 + run_all_tests ALL GREEN → /tmp/mynote_build.lock
构建 → tools/deploy_api.py 部署 → 线上 sw VERSION + wasm md5 逐字节核对。

## 六、脚本与数据位置

全部工件在持久目录 **`~/workspace/.scratch-bounce/`**（/tmp 曾被清空，勿再放 /tmp）：

- `findings.md`——取证结论与修法设计全文（本文件为其落盘摘要 + 最新闸门状态）。
- `bounce_harness.mjs`——rAF 逐帧采样 harness（rust/orig 两版、路径代号
  R1 设置退出 / R2 备份退出 / R3 弹窗取消 / R4 弹窗确认 / R5 编辑退出 /
  R6 搜索退出 / O1、O2、O5 为原版对应路径；参数 4 = 4x 节流）。
- `anim_clock.mjs`——动画时钟判别（ct 冻结 84ms 的时钟级证据来源）。
- `analyze_frames.mjs`——帧数据离线复析；`orig_probe.mjs` /
  `orig_ed_trace.mjs`——原版结构探查与编辑器关闭 MutationObserver 追踪。
- `frames_*.json`——各路径原始帧数据；`out_*.log`——各轮运行日志。
- `probe_page_transitions.mjs`——验收探针（见第五节）。
- `dist/`——量测用生产逐字节 dist 副本（cbf7e480c7；**已过期**，见文末基线警告）。
- 本地服务：`~/workspace/mynote-ab/tools/serve_headers.py`，8231 = scratch
  dist、8232 = 仓库根（原版）；进程不随重启存活，复用前先
  `ss -tlnp | grep 823` 核活。playwright-core 经 scratch 下 node_modules
  符号链接（→ 仓库 node_modules）解析；Chromium 可执行文件为
  `~/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell`。

## 七、环境退化对量测的影响说明

- 2026-11-23 约 03:46 一次服务重启把 /tmp 整体清空（其他代理的工件亦受影响）；
  本单工件此后全部改放 ~/workspace/.scratch-bounce 持久目录，无数据丢失。
- 期间有内存退化期：可用内存一度降至约 533–741MB，出现 Chromium headless
  启动 SIGTRAP、curl 写失败（error 23）。**退化窗口内的失败运行一律作废、
  恢复后重跑**；本文件全部结论数字均出自健康窗口的运行（harness 与
  anim_clock 多轮复现一致）。
- 4x CPU 节流是人为慢设备口径，用于放大主线程长任务对动画启动的影响；
  1x 干净、4x 现形，与真机（性能弱于桌面 Chromium 且为 WebKit）报告的
  「仍有弹跳」方向一致，但量级不可直接外推（unknown）。

## 八、基线变化警告（重派时先处理）

1. 量测 dist（cbf7e480c7，批 3 构建）已被生产推进取代：交互专项 b311293
   构建 6607c8ccaa 已上线，其后还有多笔在链。重派落码验收时以届时本地
   构建 + 部署后逐字节比对为准；如需复测，先重拉生产 dist 再基线化。
2. b311293 起图文卡点按口径已变（见第三节第 3 条），涉及底表路径的探针
   入口须按新口径写。
3. 落码目标文件（main.rs / settings.rs / editor.rs）在闸门等待期内已被
   批 7（main.rs/list.rs）、空白落焦（editor.rs）、安全区栏（main.rs 根色
   链/panels.css）等批次改动——落码前必须以届时 HEAD 实读相关段落，
   本文件第四节的行号级描述（page :396、selected :389、根色 effect
   ~:446、rsx 分支 ~:660–1100、close_page 与 SettingsView/BackupView
   签名、editor go_back/page_anim ~:2881）仅为量测时点（b311293 前后）
   的坐标，届时以实读为准。
