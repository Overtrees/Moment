# 确诊：附件行点按后，菜单「更换背景色」底表（BgSheet）挂载丢失

日期：2026-11-24。发现方：探针治理线（probe_pages_editor_rust 实测）。
本线：复现、二分定性、根治落码与探针锁。

## 一、症状

编辑页添加附件 → 点按附件文件行（走分享链，Diag `ATT open … -> download`，
canShare 不过走下载兜底）→ 打开编辑菜单 → 点「更换背景色」→ 菜单正常关闭，
但 BgSheet 底表永不出现。对照：只添加附件、不点附件行 → 同路径底表正常。

## 二、复现与二分（box，Chromium 口径；构建 c3dc7bc541 = HEAD ba67c27）

| 实验 | 条件 | 结果 |
|---|---|---|
| 治理线原探针 | 长备忘（冬日）、UI 加附件、合成 pointer+click 点行、合成 click 菜单项 | **失败**：`.bg-sheet` 8s 超时（probe_pages_editor_rust:339） |
| A/S1 | 短备忘、导入夹具、真 tap 点行、真 click 菜单项 | 正常 |
| S2 | 短备忘、合成点行 | 正常（Diag 有 insert para + S8 行，但 sy=0） |
| S3/S4 | 短备忘、合成菜单项 / 双合成 | 正常 |
| S5 | 短备忘、前置导出 PDF 弹窗 | 正常 |
| L1 | 长备忘滚到底、真 tap 点行（ATT -> download） | 正常 |
| L2 | 长备忘滚到底、不点行 | 正常 |
| **L3** | 长备忘滚到底、**合成点行** | **失败**：Diag 终局是 `menu closed`（None 支），非 `menu closed -> bg sheet`；菜单打开后 sy 1169→0 |
| **L4** | L3 + 滚动打点 | **坐实**：fab 点按前 activeElement=被插入段落（blk-p ed-line）、sy=1169；fab 点按后首个采样（+3ms）菜单已带 `is-closing`、sy=0；全程仅 1 个滚动事件（→y=0）；Diag 序：`insert para before` → `blur -> force unscrolled (S8)` → `menu closed` |
| **L5** | **纯真实用户路径，无附件参与**：长备忘打字获焦 → 滚动 → 点 fab | **同缺陷**：菜单出现后 600ms 内自行消失、sy 归 0 |

## 三、根因（proven：实测 + Diag + 读码逐点对应）

菜单「滚动即关」逻辑**不区分滚动来源**，而应用自身有一条会产生真实窗口
滚动的编排路径——桥 S8 失焦回顶：

1. 触发态：某可编辑块持有焦点且页面已滚动（sy>0)。到达路径任意：正常打字
   （L5)，或附件行的 click 路径（桥对原子块的 click 路由插入段落并获焦，
   L3/L4 的 `insert para before`)。真手势 tap 点行走桥的点按路径、只选中
   不获焦，故 L1 不触发。
2. 用户点 •••(fab, onpointerdown）打开菜单的动作本身先使可编辑块失焦 →
   桥 focusout 处理（bridge.rs S8，原版 use-editor-dom.js:425-450 同机制）
   判定焦点离开编辑区 → `window.scrollTo(0, 0)` 回顶。
3. 该编排滚动经编辑器滚动订阅（editor.rs `__mnEdScroll`，仅上报裸 y 值）
   到达 Rust 消费端后，被无条件当作用户滚动：`menu_open` 已置位 →
   `animate_menu_close(MenuAfter::None)`。菜单以 None 去向「正常关闭」
   （Diag `menu closed`)，待定的 Bg 去向被代际重排静默作废；若滚动落在
   菜单打开前，菜单刚开即被关，菜单项点按根本无从命中（L4 形态）；若落
   在 220ms 链式关闭窗口内，Bg 去向同样被 None 顶替（同根变体）。
4. sy=0 时 scrollTo(0,0) 不产生滚动事件，链路正常——短备忘/未滚动、
   对照组（不点行→无获焦段落）皆因此通过。

**下载/分享链与缺陷无关**（证据：L5 无附件同缺陷；L1 带 download 通过）。
治理线最初的嫌疑方向（下载锚残留状态、share 信号污染、afterClose 时序）
均被二分排除；真实交点在「行点按的获焦副作用 + S8 回顶 + 滚动关菜单」。

菜单关闭链本身（animate_menu_close 的代际/after 机制）、BgSheet 渲染条件
（bg_open 信号直读）均无恙：对照组同链全通。

## 四、修复（结构性，收在根因点）

原则：应用编排滚动不是用户滚动，滚动订阅必须携带来源，消费端只对用户
滚动执行「滚动即关菜单/导出面板」；滚动量本身（标题坞状态、斜杠跟随）
不依赖来源、照常消费。

1. bridge.rs（S8 focusout 回顶处）：`window.scrollTo(0, 0)` 前打标
   `window.__mnProgScroll = { y: 0, until: Date.now() + 600 }`（600ms 窗口
   覆盖滚动事件派发与可能的平滑滚动尾流）。
2. editor.rs 滚动订阅上报：消息由裸 y 改为 `[y, prog]`，prog 取自打标
   窗口；消费端 prog 时跳过关菜单/导出面板分支，并在菜单/导出在场时回记
   结果侧 Diag 行 `app scroll y={y} -> menu close skipped`（链路留痕，
   诊断红线）。

不改动：S8 回顶语义本身、用户滚动关菜单的原版口径（S2)、菜单代际机制、
BgSheet 链。已知同根他源：桥内其余 scrollIntoView 均为元素级滚动且发生
时菜单不在场，未打标；窗口级编排滚动今后新增时应同打 `__mnProgScroll`。

## 五、探针锁与回归（修复构建 wasm md5 91554d079d01，box 实测）

提交：修复 `6d31ae8`、探针锁 `62e99c4`。

probe_attachment_open 新增 ⑦：真实链——段落打字获焦 → 滚动到附件行 →
真 tap 点行（Diag ATT -> download）→ 开菜单断言 800ms 后仍在场 → 点
「更换背景色」→ `.bg-sheet` 出现 + Diag `menu closed -> bg sheet`。
实测 ⑦ 五断言全绿（前置 sy=379、ATT -> download、菜单留存、底表出现、
Diag bg 行），整探针 ALL PASS。

回归全绿：probe_card_menu ALL PASS、probe_batch3 ALL PASS、
probe_lightbox_page 80/80 ALL PASS。原失败探针 probe_pages_editor_rust
全程走通（exit=0、DONE、PAGE_ERRORS [])：ATTACH_OPEN_SHARE 记 download
后 BGSHEET 段完整读数（8 色点、选色后根色变更、重开/移除/点遮罩关闭
皆在场）——原 339 行超时点消除。

## 六、待真机终判

box 为 Chromium 口径：S8 的 iOS 异步滚动恢复（80ms×6 forceTop 重发所压制
的对象）在 Chromium 不存在，回顶滚动的派发时序与真机可能不同。上线后
真机复测：长备忘编辑获焦 → 滚动态点 ••• → 菜单应留存 → 更换背景色应
开底表；Diag 应见 `app scroll … -> menu close skipped`（若该滚动在菜单
在场时被消费）与 `menu closed -> bg sheet`。
