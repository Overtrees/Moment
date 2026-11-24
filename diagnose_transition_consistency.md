# 页面过渡一致性全面审计（2026-11-24 14:17 用户问询）

问题：从图片页（灯箱页）到编辑页、以及其他各页面之间的过渡动画有没有统一。
方法：全量读码清点（main.rs Nav 状态机 + 各页组件渲染 + styles 动画规则），
量测口径为 box Chromium（probe_page_transitions ①–⑨）；真机专属现象
（iOS 滚动钳制等）不在本审计结论面内。

## 统一机制本体（全方向共用）

- 关键帧只有一份定义：`slideInFromRight` / `slideOutToRight`
  （styles/editor.css:172/180，被四样式拼接全局引用）——进场自右
  24px+opacity .94 滑入、出场向右 16px+opacity .92 滑出。
- 时长/缓动：`--motion-page-transition` = 280ms、
  cubic-bezier(0.22,0.61,0.36,1)，进/出场类
  （.page-enter/.page-slide-in/.page-slide-out）逐字同值；
  prefers-reduced-motion 时变量归 0、全局 animation-duration 压 0.01ms。
- 前进（Nav::go / open_memo）：即刻提交——旧页同提交卸载/隐藏、
  新页挂载播 slideIn；自列表进入先存列表滚动并回顶。
- 返回（Nav::go_back / begin_editor_leaving）：状态保持到出场播完
  才在 arm_unload 提交点同任务翻转（组件页 280ms 读变量值、编辑器
  320ms），提交带 TRANS committed + POST/CENSUS/LATE 普查，
  目标滚动双 rAF 恢复。
- 根色 = 页面状态纯函数（App 派生 effect），随页面状态在同一
  提交点翻转，无第二写者口径。

## 方向 × 机制差异表

记号：提交 = 页面状态翻转时点；动画落点 = 挂动画的元素层。

| 方向 | 走的函数 | 进入动画 | 退出动画（反向时） | 提交时序 | 滚动 | 根色翻转 |
|---|---|---|---|---|---|---|
| 列表→设置 | go("settings") | 内容层 page-slide-in（both） | — | 即刻 | 存列表位+回顶 | 即刻（page 翻转同帧） |
| 设置→列表 | go_back("") | （列表重挂 page-enter，backwards） | 内容层 page-slide-out（forwards） | 出场后 280ms | 提交点双 rAF 恢复 list_restore | 提交帧 |
| 列表→编辑器 | open_memo | 编辑器根内联 slideInFromRight .28s both（320ms 后摘除） | — | 即刻（selected 置位） | 存列表位+回顶 | 发起任务内先行同值写 + 派生 |
| 编辑器→列表 | begin_editor_leaving | （列表重挂 page-enter） | 编辑器根内联 slideOutToRight .28s forwards | 出场后 320ms | 提交点双 rAF 恢复 | 提交帧（卸载/挂载/翻色同帧） |
| 设置→备份/语言/诊断 | go(子页) | 内容层 page-slide-in（备份）；**根层 page-enter（语言/诊断）← 偏差 D-1** | — | 即刻 | 回顶（子页自有滚动） | 即刻 |
| 备份/语言/诊断→设置 | go_back("settings") | （设置重挂、内容层 page-slide-in） | 内容层 page-slide-out（备份）；**根层 page-slide-out（语言/诊断）← D-1** | 出场后 280ms | dest 非列表不恢复（设置页回顶） | 提交帧 |
| 编辑器→图片页 | img_req effect → go("image") | 内容层 page-slide-in（both），页头静止 | — | 即刻（page 翻 "image"、编辑器槽位 stage-hidden 同提交隐藏） | 存编辑器位 img_restore+回顶 | 即刻（派生 None→根页面色） |
| 图片页→编辑器 | go_back("") | （编辑器槽位恢复显示、不重播进场，见 I-3） | 内容层 page-slide-out（forwards） | 出场后 280ms，提交点清 img_req | 提交点双 rAF 恢复 img_restore | 提交帧（回编辑器有效背景） |
| 编辑器→编辑器（Wiki 跳转/列表再开） | open_memo | 新实例根 slideIn（同列表→编辑器） | 旧实例即刻卸载、无出场 | 即刻 | 存当前位+回顶 | 先行同值写+派生 |
| 列表→图片页 / 设置→图片页 / 图片页→列表（直达） | — | **无此路径**：img_req 仅由编辑器内块（blocks.rs ImgPage 上下文）写入；列表封面点按 = open_memo 进编辑器（已定案）；图片页返回 dest="" 但编辑器槽位在场、列表不挂载 | | | | |

## 偏差

### D-1（已根治）：诊断/语言页动画落点在根层，与同级页不一致

- 现象：Settings/Backup/Image 三页的进/出场动画只挂**内容层**
  （.page-content + page-slide-in/out），PageHead（返回钮+标题）
  静止——base.css:697-704 注释载明此为原版 SettingsView/
  BackupView 口径。DiagView/LanguageView 则把 page-enter /
  page-slide-out 挂在**根层**，进/出场时返回钮与标题跟着整页
  滑动，同级子页之间肉眼可辨不一致。
- 定性：诊断/语言为 Rust 期新增页（原版无对应页），无原版口径
  可循；DiagView 组件头注自称「收敛后与其它组件页同口径」，
  仅提交语义同口径、动画落点并不同——无有意设计证据，属收敛
  遗漏。（proven：读码逐字比对五页 content_class/根层 class。）
- 根治：DiagView/LanguageView 改与 Settings/Backup/Image 逐字
  同形——根层去动画类、内容层挂 page-slide-in/out。verify 第 12
  节加 (iv) 静态锁、probe_page_transitions 加 ⑨ 断言组守之。

## 有意差异（证据在案，不动）

- I-1 编辑器时长字面量：根动画用内联 0.28s 字面量（不走变量）、
  出场提交 320ms = 280+40——原版 editor.js 字面量与 handleClose
  等待口径，settings.rs page_transition_ms 头注载明。
- I-2 列表根 .page-enter 用 fill backwards、内容层 page-slide-in
  用 both：base.css:686-696 注释载明——整页根 fill both 会让
  transform 常驻、困住 fixed 后代；内容层无 fixed 后代故 both
  无害。终态视觉一致。
- I-3 图片页返回后编辑器不重播进场动画：编辑器实例留槽保留
  （状态/会话不丢为既定设计，main.rs 槽位注），page_anim_done
  已置位故恢复显示即定格；与之相对，列表/设置在返回提交后是
  重挂载、照常播各自进场。属实例保留设计的直接结果，非分叉。
- I-4 编辑器→图片页进入时编辑器无出场动画：前进全方向皆
  「即刻交换 + 新页滑入」（旧页从不播出场），图片页此方向与
  列表→设置、列表→编辑器完全同形；且编辑器实例不得卸载
  （槽位保留），只能同提交隐藏（stage-hidden）。
- I-5 返回提交后新挂载页一律播 slideInFromRight（方向中立）：
  列表 page-enter、设置内容层 page-slide-in 在返回方向同样
  触发，全方向一致，为现行定案口径。

## 探针覆盖（probe_page_transitions）

- 既有：①–④ 编辑器↔列表、⑤ 设置→列表串行同帧组、⑥ 滚动
  保存/恢复、⑦ 设置→备份→设置→列表链。
- 本审计新增：⑧ 图片页进入/返回组（进入：内容层 slide-in 在
  场且推进、页头静止、编辑器槽位隐藏、IMGPAGE open；返回：
  slide-out 在播、提交前编辑器不显形、TRANS image committed、
  编辑器滚动恢复）；⑨ 子页落点组（诊断/语言进/出场动画类只
  在内容层、根层无动画类——D-1 回归锁）。
