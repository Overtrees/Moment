# 标题胶囊输入态专项深查（只审计，未落码）

审计对象：生产构建 **1c9769e990**（sw.js VERSION 与 wasm md5 `1c9769e990d515a4b86e74bf0ed2218c` 一致；含组字振荡修复提交 c58e9f5）。源码基线 = HEAD `c58e9f5` 的 `rust/apps/web/src/editor/title_controller.rs`（下称控制器）。

方法与口径：

- 运行时探针为 Chromium headless-shell 口径。因沙箱出口代理与无头 Chromium 的隧道不通，探针跑在生产文件的**逐字节镜像**上（curl 拉取生产 dist 本地托管；wasm md5 与生产部署记录逐字节一致，sw VERSION 经页面内 fetch 复核 = 1c9769e990）。行为口径与生产站等价，但一切结论仍只是 Chromium 口径。
- 真机（iOS 27 / WebKit）行为凡探针测不到的，均标 unknown 并归入文末真机终判清单，不以 Chromium 结果代判。
- 结论标注：**proven**（代码行级证据或探针数据）/ **inferred**（机制推断）/ **unknown**（须真机）。
- 本审计不改任何源码；文内「修复线」指已上线的组字期几何冻结（c58e9f5），其改变的结论在第 5 节集中对照。

---

## 1. 快速连续输入长文本

### 1.1 机制（code, proven）

- 输入事件路径极薄：`input` 监听（title_controller.rs:951）只调 `kick()`；`frame()`（:456）在帧内**按当前全文状态**读镜像量宽（状态式测量，不吃事件增量），故事件快于 rAF 时多个事件天然合并为一帧的最新状态，**不存在丢步**（proven，代码 + S1b 实测互证）。
- 弹簧为指数趋近（τ≈90ms，dt 钳制 1–100ms），对任意 dt 无过冲；帧循环的存续条件 `settled`（:560）只看宽/内距两弹簧，不看 scrollLeft——滚动校正靠事件侧的脏标记再踢（见 3.2）。
- cap 判定在帧内按落定文本宽单向啮合；非 cap 态帧循环强制 scrollLeft 归零。

### 1.2 实测（Chromium，生产镜像）

| 场景 | 数据 | 判定 |
|---|---|---|
| S1：40 字 CJK 以 CDP insertText 紧密连发（约 33 键/秒，远超人手） | 宽单调增长、**回退 0 次**；末键后 ≤194ms 收敛到 184（cap）；光标终点距滚动区右缘恰 16px（caretRel 130 / 区宽 146）；foreign=0 | 正常 |
| S1 单帧最大宽步长 | 两轮分别 22.8px / 16.5px | 见异常 E（低） |
| S1b：同一 JS 任务内同步插入 30 字（事件完全快于 rAF） | 无中间态可观测（整段在一帧间隙内完成），终点宽 184、foreign=0、无异常 | 正常（状态式测量的预期表现） |
| S2：cap 态 34 次快速 Backspace 删到空 | scrollLeft 随删单调回落、**逆行 0 次**，终点 sl=0；删空后 DOM 为单个 `<br>`、选区锚在元素 0 位、焦点仍在标题内 | 正常 |
| S3：组字 1→24 字高速连发（16ms/步）+ 同长同文重复组字 ×8 | 组字期**几何写计数零增长**（53→53）、胶囊宽全程恒定（range=0）、增长期 sl/宽逆行 0 次；Diag compupdate 行同 len 的 tw 无离散（Chromium 下恒定） | 冻结口径成立（proven，限 Chromium） |

### 1.3 组字跨 cap 阈值期间的光标可见性（专项验证，含一次被证伪的假设）

审计曾假设：冻结构建在「空/短标题起长组字」路径上，会话以非 cap 开始（滚动区 overflow-x:hidden、胶囊宽冻结在短态），组字串越过胶囊宽后尾部与光标将被胶囊 `overflow:hidden` 裁掉。**实测证伪（Chromium）**：

- 路径甲（空标题组字至 24 字）：胶囊宽恒 108.7 不动，但滚动区 scrollLeft 随组字原生增长（43→126→195→278），光标矩形全程钉在距胶囊右缘约 20px 处、始终在胶囊内。`overflow:hidden` 容器在 Blink 中仍是可被 reveal 滚动的滚动容器，原生 scroll-into-view 照常工作。
- 路径乙（28 字已 cap 会话内续组字）：组字期 sl 由原生从 272 推到 326，光标保持在内；compend（取消）后精确回到 sl=272、光标回末位边距。
- compend 后首帧按落定文本收敛（冻结线在 on_composition_end 置 caret_dirty，title_controller.rs:782），路径甲取消组字后 sl 归 0、宽回短态。

即：冻结构建把组字期滚动全权交原生后，Chromium 下光标可见性在两条路径上都成立。**iOS WebKit 对 overflow:hidden 容器的 reveal 滚动是否同口径 = unknown**，这是冻结构建在真机上的头号待验项（异常 B）。

---

## 2. 光标表现（逐场景，对照原版）

原版基线（src/app/editor.js）：聚焦快照按初始长度定格、会话内只升不降（:2613 起 onFocus）；截断态聚焦才换全文并 rAF 落光标文末（:2640 附近），未截断则原生落点；`scheduleTitleCaretSync`（:1033）双 rAF 后按相邻字形量 caret x、以 16px 边距（TITLE_CARET_GUTTER，:681）校正滚动区 scrollLeft，触发源 = selectionchange / input / compositionupdate / compositionend / 视口 resize·scroll；失焦提交 = trim、空回退「无标题」、回截断（>10 字取前 10 + …）、scrollLeft=0（onBlur :2678 附近）。

| 场景 | 控制器行为（实测/代码） | 与原版 |
|---|---|---|
| 点按截断标题·可见前缀（第 3 字） | 光标落全文同位（实测 offset 2，Diag sel=2 同步佐证）——点按映射（用户 2026-11-22 拍板的有意调优） | 原版一律文末；此为已批准偏离 |
| 点按截断标题·省略号字形中心 | 落 offset **10**（省略号前边界），不触发「省略号后→文末」 | 见异常 D（低） |
| 点按短标题（未截断） | 不换文本、原生落点（实测点第 2 字落 offset 2） | 与原版一致 |
| 删空 | 单 `<br>` 结构、光标在 0 位；控制器 caret 量测对空文本返回 None、不做伪校正（title_controller.rs caret_client_x 的 len==0 分支） | 一致；审计采样器曾报 caretRel=-180.5，系 Blink 空折叠 Range 矩形 (0,0) 的探针假象，非应用行为 |
| cap 态滚动边缘 | 输入/删除/组字落定后光标恒被校正到距缘 16px（多场景实测恰 16.0） | 与原版边距口径一致 |
| 纯选区移动跟随 | 见第 3 节（单跳 ≤2 帧校正到位；连续步进 0 出界帧） | 触发覆盖一致；时序差见异常 A |
| 失焦恢复 | 展示回截断串、scrollLeft=0、长标题展示字号 11px（实测） | 一致 |
| 二次进入（28 字标题） | 字号按初始全文冻结 11px、cap 重新啮合宽锁 184；点按中心（截断串前缀区）→ 映射落位 offset 5（点按映射口径，非缺陷） | 字号冻结为已批准偏离（原版会话中途跨 5 字会 14→11 切换一次，控制器全程冻结） |
| 聚焦瞬间宽瞬态 | 长标题聚焦时胶囊以展示态涌现宽为弹簧起点，可短暂超 cap（实测 189.2→184，约 0.3s 收窄） | 见异常 C（低） |

其余已核一致项：Enter/Esc 失焦提交（控制器多 Esc 一路，原版无，属增益）、组字中 Enter 不误提交（keydown 的 composing 守卫，:971）、标题无挂载后外部变更源（静态壳 title.rs）。

**口径性偏离备忘（非缺陷，均为已批准设计）**：① 字号会话冻结 vs 原版跨阈值单向切换；② cap 按**宽度**啮合（textW+2·pad ≥ 184）vs 原版按**字数**（>11 字）切 overflow——窄字符长串（如 20 个 ASCII）在原版早切滚动模式，控制器要等实际宽满才切，行为更贴合几何但与原版不一致；③ 点按落点映射 vs 原版文末口径。

---

## 3. 空格键长按滑动控制光标（iOS 键盘 trackpad 模式）

该手势在 Web 内容中只动选区：产生 selectionchange（及原生 reveal 滚动），不产生 input/composition 事件。以下为代码层排查结论。

### 3.1 标题：跟随链完整（code proven）

- `selectionchange` 监听注册在 document 上（title_controller.rs:1005）：置 `caret_dirty = true` **并 `kick()`**（:1005-1010）——纯选区移动能唤醒帧循环，不是只置标不开循环。
- `kick()` 的闸门是 `phase == Editing`（:435，冻结线收紧后）。trackpad 滑动发生在 Editing 态（非组字中），**不受组字冻结影响**，照常调度。
- 帧内校正为边距式：仅当 caret 越出滚动区左右 16px 边距才写 scrollLeft（frame() 的 cap 分支）——向左滑入早先文本时，caret 越过左边距即被跟随（Chromium 代理实测见 3.3）。
- 视口 resize/scroll 监听（:1015/:1021/:1030）同样置标 + kick，键盘收起/视口变化不丢跟随。
- 非 cap 态无需跟随：文本全宽可见、scrollLeft 恒 0，光标不可能出视口（构造性质）。

### 3.2 与原版的时序差（异常 A 的机制，code proven）

原版 `scheduleTitleCaretSync` 用**双 rAF**：等布局与原生 reveal 都落定后再量 caret、再校正，且合并快速移动中排队的多次更新。控制器是**单 rAF + 脏标记**：帧在原生 reveal 之前先量先写时，校正可能被同帧随后的原生滚动覆盖；覆盖后帧循环已因 `settled`（只看宽/内距，:560）停转，要等下一次 selectionchange 再踢。连续滑动时事件不断，实际影响只是 1–2 帧迟滞；滑动恰好停在被覆盖的那一帧时，终点位置由原生 reveal 决定（光标仍可见，只是未必恰在 16px 边距）。

### 3.3 Chromium 代理实测（方向键/程序化选区 = 纯选区移动）

- 程序化单跳（光标从末尾直接跳到第 0 字）：**2 个采样帧内** scrollLeft 校正到 0，光标终点距左缘恰 16px。
- ArrowLeft 逐字左行 30 步（34ms/步）：**出视口帧 0**；过程中光标距左缘最小 1.8px（短暂进入边距带、未出界），终点恰 16px、sl=0。
- ArrowRight 回行 30 步：出视口帧 0，终点 sl=maxSl、光标距右缘约 16px。
- 结论：纯选区移动的滚动跟随在 Chromium 口径下**成立**，仅有边距带内的瞬态迟滞（异常 A）。

### 3.4 正文编辑器（bridge.rs）：无自有 caret 跟随，全靠原生（code proven）

- 桥内仅有两处 selectionchange 监听，均不碰滚动：:617 跨块选区（xsel）失效判定、:1099 savedRange 存档（供行内格式恢复）。正文**不存在**任何 caret→scroll 同步代码，光标可见性完全依赖 WebKit 在页面滚动容器上的原生 reveal。
- 这与原版口径相同（原版的 caret 同步只有标题的 scheduleTitleCaretSync，正文同样靠原生）——**无回归**；但也意味着正文 trackpad 滑动若原生 reveal 在某 iOS 版本上迟滞，应用层没有任何兜底，异常时从代码层无可修点，只能靠真机现象定性（unknown）。

### 3.5 只能真机终判的点

1. iOS trackpad 滑动期间 selectionchange 是连续派发还是松手才派发一次：若仅末尾一次，标题在滑动全程只有原生 reveal 跟随、停手后控制器校正一次到位——终点仍正确，过程手感与原生备忘录的差只能手验。
2. trackpad 模式下 WebKit 是否对 overflow:hidden / overflow:auto 的标题滚动区做 reveal（与异常 B 同源）。
3. 正文长距离滑动（跨屏）时原生 reveal 是否逐程跟随、停手位置光标是否在视口内。

---

## 4. 异常清单（按严重度）

| # | 级别 | 异常 | 证据 |
|---|---|---|---|
| A | 中 | 纯选区移动的边距校正有 1–2 帧迟滞：连续移动时光标可短暂进入 16px 边距带（实测最差距缘 1.8px），从不出视口、静止终点恒精确 | code proven（单 rAF + settled 只看几何，title_controller.rs:456/:560；原版双 rAF :1033）+ Chromium 实测（3.3） |
| B | 中（待真机定级） | 冻结构建组字期光标可见性 100% 依赖 WebKit 原生 reveal（含 overflow:hidden 非 cap 容器与 cap 容器两种形态）；Chromium 两路径均成立，iOS 未验——若 iOS reveal 口径不同，跨阈值组字期间尾部光标可能不可见 | Chromium proven（1.3）；iOS unknown |
| C | 低 | 聚焦长标题时弹簧起点 = 展示态涌现宽，可超 cap（实测 189.2→184 约 0.3s 收窄），进编辑瞬间胶囊先宽后窄 | Chromium 实测 + on_focus 以当前 rect 初始化 cw（title_controller.rs on_focus 量测段） |
| D | 低 | 点按省略号字形中心落 offset 10（省略号前），「点省略号→文末」只在点到字形右半才触发；与用户直觉（点省略号 = 看全文尾）可能不符 | Chromium 实测（专用点按探针，Diag sel=10 佐证）；tap_caret_target 的 `c <= 10` 规则 + caretRangeFromPoint 边界语义 |
| E | 低 | 超人手速连发（约 33 键/秒）下单帧宽步长可达 16–23px（cap 翻转帧的目标跳变 + dt 墙钟弹簧）；单调无回退、≤194ms 收敛，人手速率下步长约 ≤3px，不构成缺陷 | Chromium 实测两轮 |
| F | 低 | Diag 每行同步全量落盘：`diag::log`（diag.rs:55）每行都把整个 300 行环 JSON 序列化并 setItem localStorage；标题帧行是输入期最高频来源之一（S1：40 键约 20 行）。桌面成本小，真机主线程代价未测 | code proven；真机影响 inferred |
| G | 信息 | rAF 闭包以 try_borrow_mut 取 Inner：若某次回调借用失败，raf_id 将悬挂为 Some、kick 永久短路该会话。rAF 回调在空 JS 栈运行、借用只在同步 handler 内持有，实际不可达 | code inferred（健壮性备忘，非现行缺陷） |

已排除项（曾怀疑、实测/代码证伪）：事件快于 rAF 丢步（状态式测量，无丢步）；组字期几何振荡（冻结构建实测零几何写、宽恒定）；删空光标异常（采样器假象，实际选区锚 0 位、结构为单个 br）；点按映射失效（主探针曾读到 focusNode 瞬时为 null 的 -2 值，专用点按探针以更长落定时间复测 3/3 正常且 Diag sel 值佐证，判为聚焦事务中的读时序假象）。

---

## 5. 振荡修复（c58e9f5，已上线 1c9769e990）改变的结论

用户 21:15 真机复验针对的是修复前构建（5dab658ea9）。该修复落码后，以下结论**已经改变**，本审计其余结论不受影响：

1. **组字期 tw/sl 振荡**：修复前帧循环在组字期逐帧量镜像、按瞬时读数钉 scrollLeft，与原生组字滚动拔河（真机日志同 len 相邻帧 tw 跳 3–12px、sl 每键冲高回落 3–5px）。修复后组字期 kick 短路（:435）、frame 提前返回（:461），实测几何写零增长、宽恒定、Diag compupdate 的 tw 为冻结值——振荡源在代码层已消除（Chromium proven；真机手感终判未回）。
2. **组字期光标跟随的责任方**：修复前由控制器边距校正与原生 reveal 并行；修复后组字期**只有原生 reveal**——异常 B 是这一责任转移的残余风险表述，修复前不存在此条。
3. **compend 收敛**：修复新增 compend 置 caret_dirty（:782），落定首帧不依赖后续 selectionchange 即可做边距校正；修复前 compend 后的校正依赖事件时序。
4. **不变项**：快速打字/删除、点按落点、失焦/二次进入、纯选区移动（含 trackpad 链，异常 A）——修复未触碰这些路径的代码语义，本审计结论对修复前后一致。

---

## 6. 真机终判清单（iPhone，构建 1c9769e990）

1. 九宫格长组字（从短标题起、组字串越过胶囊宽）：组字全程能否看见正在输入的拼音尾部与光标（异常 B 的定级）；双竖条是否消失（看 Diag titleGeom：组字期应无 frame 行几何变化、无 foreign 行）。
2. 已 cap 长标题内续组字：光标是否始终可见、compend 后是否回到 16px 边距位。
3. 标题编辑态空格长按左右滑动：光标移动全程文本是否跟随滚动、停手时光标位置；向左滑入早先文本一段长距离后松手，光标是否在视口内（异常 A 的真机量级）。
4. 正文中空格长按滑动跨屏：停手时光标是否在视口内（3.4/3.5-3）。
5. 聚焦长标题瞬间胶囊是否有可察觉的先宽后窄（异常 C 的可感知度）。

---

## 附：探针与原始数据

- 探针（审计用，未入仓）：快速输入/删除/组字/选区行走综合探针、点按落点专项探针、组字光标可见性专项探针各一份（CDP Input.insertText / imeSetComposition / dispatchKeyEvent + rAF 逐帧采样 + Diag 读数交叉核对）。
- 关键原始值：S1 maxStep 22.8/16.5px（两轮）、settle ≤194ms、终点 caret 距右缘 16.0px；S3 geomWrites 53→53（组字期零增长）、组字期宽 range=0；选区单跳校正 2 帧、左行 30 步出界帧 0 / 最小距缘 1.8px；点按 offset 前缀 2 / 省略号 10 / 短标题 2；聚焦长标题 cw 189.2→184；组字路径甲 sl 43→278 且 caret 恒在胶囊内（距右缘约 20px）、路径乙 sl 272→326（组字期）→272（compend 后）。
