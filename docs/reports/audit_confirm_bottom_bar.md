# 确认弹窗底部实心栏 — 只读全面排查报告

日期：2026-11-23 晚。范围：rust/apps/web 全部确认弹窗 / 模态 / 底表。
方法：全仓普查 + 代码推演 + 原版（src/）对照。未改任何产品代码。
观测来源：用户真机报「确认弹窗打开时底部出现实心栏（颜色不对的实心带，
位于页面底部、浏览器工具栏带区附近）」。本报告对「确认弹窗」的认定：
应用内唯一带「确认」语义与标题（确认导出备份 / 确认导入）的弹窗是
备份页确认弹窗（settings.rs BackupView 的 .backup-modal，导出/导入两
模式同一组件）。其余底表/浮层一并普查判读，防同族漏网。

## 结论速览

- 备份确认弹窗在代码侧**不存在**能产生「异色底部实心栏」的路径：
  打开时根色不写、不压暗（DimStack 注册已按裁定 C 注销）、遮罩透明、
  几何为 fixed inset:0（无 100vh 类定高残留）、底表不延伸进带区、
  带区唯一绘制者仍是根色，而弹窗所在页根色 = 页面自身底色（同值）。
  逐项 proven 阴性（见 §3.1）。
- 因子律 M2 对本弹窗**不适用**：M2 需要整屏半透明遮罩 α>0；本遮罩
  α=0 且根色未压暗，M2 预测带 = 根色 ×1 = 页面色，即无可见栏。
- 锁存模型（整屏层挂载时刻采样，inferred）对本弹窗**预测同样无异色**：
  挂载冲击时刻根色 = 页面默认色 = 页面色。两种既有模型都解释不了
  「异色」——剩余可能只有两类：(i) 确认流程其后出现的 toast 本体
  （设计形态的底部玻璃实心条，见 §3.4）；(ii) 浏览器在整屏层挂载时
  采样的并非根色而是别的图层色（如贴底的玻璃底表本色）——无现行
  证据，**待真机像素量测裁决**。
- 决定性阻塞是**仪器缺口**：备份弹窗打开/关闭在 Diag 里**零记录**
  （无 open/close 行、无根色快照、无图层普查），与灯箱的 LBX 打点
  形成鲜明对照。用户下次复现时日志无从判读。先补仪器、再谈根治
  选型（方案集 §7 按量测结果分叉）。

## 1. 弹窗普查表

| # | 组件 | 触发路径 | 挂载点 | 整屏层 | 遮罩色/α | 底表/面板几何 | 打开时根色 | Diag |
|---|------|----------|--------|--------|----------|---------------|------------|------|
| 1 | 备份导出确认 `.backup-modal` | 设置→备份页→点「导出备份」行 (settings.rs:377,479) | BackupView 根 div 内 (settings.rs:480) | `.backup-modal-scrim` fixed inset:0, z 5000 (panels.css:194) | transparent, α=0 | scrim flex-end + padding-bottom env+14；卡片玻璃、radius 28、padding 14/14/calc(14+env) (panels.css:198) | **不变**（无 DimStack 注册、无 apply_root_bg 调用） | **无** |
| 2 | 备份导入确认 `.backup-modal` | 备份页选 .zip 文件→校验通过后自动开 (settings.rs:409,479) | 同上 | 同上 | 同上 | 同上 | **不变** | 仅 IMPORT staged/validate 行，无弹窗行 |
| 3 | 背景色底表 `.bg-sheet` | 编辑器菜单→背景色 (editor.rs:3383) | #editor-root 内 (editor.rs:3383-3389) | `.sheet-scrim` fixed inset:0, z 4000, transparent (editor.css:1342) | transparent, α=0 | `.sheet-wrap` fixed bottom: env+14, z 4001, pointer-events:none；卡片玻璃、padding 20/20/calc(20+env) (editor.css:1343,1348) | 打开不变；**选色时**随备忘底色变（派生写根色，有 ROOTSET） | close 行 editor.rs:1097；open 仅 menu 过渡行 :1011 |
| 4 | 图文全文底表 `.image-text-sheet` | 点图文卡全文 (editor.rs:3620) | #editor-root 内 (editor.rs:3612-3620) | `.image-text-sheet-backdrop` fixed inset:0, z 4000, transparent (editor.css:616) | transparent, α=0 | wrap fixed bottom: var(--safe-bottom)+14（tokens.css:173 --safe-bottom 即 env()，同值异名）, z 4001；卡片玻璃、padding 20/20/calc(20+var(--safe-bottom)) (editor.css:619,621) | 不变 | close 行 editor.rs:1139；open 无专用行 |
| 5 | toast `.backup-toast` | 备份页与编辑器内动作结果（导出/导入/保存等）(settings.rs:536, editor.rs:3111) | 各页根层 | 否（自身即浮条） | — | fixed, left/right 16, bottom: env+16, z 5000, 玻璃实底, pointer-events:none (base.css:647-653) | 不变 | 有（settings.rs:102 toast 行） |
| 6 | 编辑器菜单 / 导出面板 | 编辑器右上钮 (editor.rs:3223) | #editor-root 内 | `.menu-scrim` fixed inset:0, z 3001, transparent (editor.css:1298) | transparent | 面板 top-right 锚定 (editor.css:1306) | 不变 | menu 开/关行（既有） |
| 7 | 卡片菜单 | 长按/右键卡片 (editor.rs:3129) | #editor-root 内 | `.card-menu-scrim` fixed inset:0, z 3001, 无 background 声明（默认透明）(editor.css:1412) | transparent | 面板锚定卡片 (editor.css:1413) | 不变 | card menu open 行（既有） |
| 8 | 斜杠面板 `.slash-panel` | 输入 / (editor.css:1437) | 编辑器内 | 否（无遮罩） | — | 光标锚定 fixed, z 3500 | 不变 | slash 行（既有） |
| 9 | 灯箱 `.lightbox` | 点图片卡 (editor.rs:3590) | #editor-root 内 | 自身 fixed inset:0, z 10000 (editor.css:1468) | rgba(0,0,0,0.88) | 整屏 flex 居中 + 安全区 padding | **压暗**：DimLayer α0.88 (editor.rs:3602)，DimStack 现行唯一注册者 | LBX open/close/pop (editor.rs:3590 注释, diag.rs:166) |

无确认环节的删除路径（普查附带确认，防误认「删除确认弹窗」）：
列表行左滑删除直删（list.rs:1131-1132，Diag `row delete tap`）；
卡片菜单删块直删（editor.rs:3202，Diag `card menu delete`）；
空备忘关闭即自动删（无 UI）。**全应用不存在删除确认弹窗，也不存在
放弃编辑确认弹窗**——编辑内容直存、关页即保存。

## 2. 根色与带区的现行机制（判读基准）

- 带区（布局视口外、浏览器工具栏带）只能由浏览器以根（html）背景
  绘制；html/body 背景规则 base.css:10-15：`background-color:
  var(--mn-root-bg, var(--primary-bg))`，内联双写为权威、变量为镜像。
- body::before 仅顶部（base.css:18-32，height = env(top)×1.2 渐变），
  画不到底部（proven）。
- body 自带 `padding-bottom: env(safe-area-inset-bottom)` 与
  `min-height: 100vh`（base.css:12-15），属页面层、非弹窗。
- 各页根 div 均 `background:var(--primary-bg);min-height:100vh`
  （settings.rs:180,352；main.rs:1692,1742）：页面底色与根默认色
  **同一令牌同值**——根色画出的带与页面同色、不可见。
- 根色派生（main.rs:946-1065）输入只有页面状态 + DimStack；弹窗
  内部状态（BackupView 的 modal signal）不在输入内，打开弹窗不
  触发 apply_root_bg（结构 proven）。
- Diag 结果侧打点 log_probe/log_census/log_late（diag.rs:145-163）
  的全部调用点都在页面过渡路径（main.rs:638-643 提交点、
  main.rs:1065 ROOTSET、editor.rs:2221 清理点）；**任何弹窗打开
  都不触发**。LBX 是唯一的弹窗专用打点（diag.rs:166）。

## 3. 逐个判读

### 3.1 备份确认弹窗（导出/导入，用户所报）

- 整屏层挂载：**是**——打开瞬间新增 .backup-modal-scrim 整屏 fixed
  层。锁存模型的形式条件具备，但锁存对象（当时根色）= 页面默认色
  = 页面色，预测无异色（见结论速览）。
- 根色打开前后：代码推演恒为 (root default)（浅 #f2f2f7 / 深 #000，
  与备份页底色同值）；**Diag 不可观测**——打开/关闭零 Diag 行，
  ROOTSET 只在 apply_root_bg 时发、弹窗不调用（仪器缺口 §6-1）。
- 底边几何：scrim inset:0 四边锚定，无定高；旧 `height:100lvh`
  定尺 + dvh 补偿写法已于此前轮次移除，移除理由与真机像素证据
  写在 panels.css:176-193 注释里（遮罩实高 695 而非 735、视口下缘
  外一条带未被压暗——那是压暗时代的旧账）。现行无同型残留
  （proven：全仓 grep 无第二处以视口单位定高的整屏遮罩；灯箱亦
  已 inset:0）。
- 自带底部背景延伸：无。底表是 scrim 内 flex-end 的玻璃卡片，
  下缘距视口下缘 env+14；其 backdrop-filter 只作用于卡片自身
  盒内（proven）。
- 关闭清理：确认/取消均 `modal.set(None)` 即时卸载（settings.rs:
  500,523），无关闭动画、无残留状态；导入取消连带清 pending
  （:524）。打开有 sheetIn 250ms 弹簧进场（panels.css:199，用户
  拍板保留的有意偏离）。
- 与原版差异（非带相关，附带记录）：原版遮罩可点关
  （BackupView.js:799 onClick 关），Rust 版 scrim **无点击关闭
  处理**，只能点按钮关。
- **风险判定：有（用户实报在案）；代码侧成因 proven 阴性；
  待真机像素量测 + 补仪器后裁决。**

### 3.2 背景色底表（编辑器）

- 与备份弹窗同族几何：透明整屏 backdrop + 贴底玻璃表，打开新增
  整屏层；根色打开时不变。差别：身处编辑页，根色 = 编辑器实效
  底色、页面同色，带即便锁存亦同色；**选色动作**会改备忘底色→
  派生改根色且有 ROOTSET 可观测——若带问题在此出现，形态属顶带
  家族（根色翻转与图层共存），与本议分开。
- **风险判定：待真机量测（低）。代码侧无独立异色源（proven）。**

### 3.3 图文全文底表（编辑器）

- 同族几何同上。底距用 var(--safe-bottom)（tokens.css:173，其值
  即 env(safe-area-inset-bottom)），与 .sheet-wrap 直用 env() 同值
  异名，无数值分歧。
- **风险判定：待真机量测（低）。代码侧无独立异色源（proven）。**

### 3.4 toast（确认流程的尾巴）

- toast 本体就是一条贴底实心玻璃条（fixed、左右 16、bottom
  env+16、--glass-overlay-bg 在浅色为 #ffffff 不透明、
  tokens.css:39）。它在**点确认之后**出现（导出中 spinner / 成功
  / 失败），弹窗打开期间不出现（除非上一条未消的 toast 与开弹窗
  时序重叠的边角情形）。
- 若用户所指实为「点确认后底部那条」，此条为**设计形态**（原版
  同型全宽条，审计 G2 口径），非缺陷——需用户一句话确认所指
  时点（弹窗在场时 / 点确认后）。
- **风险判定：有（设计形态）；与所报时点是否吻合待用户确认。**

### 3.5 锚定面板（菜单/导出/卡片菜单/斜杠）

- 遮罩同为透明整屏层，但面板在顶部或光标处，底部带区无任何
  新增绘制；根色不变。**风险判定：无。**

### 3.6 灯箱（边界，仅标注）

- 本审计不解决。其与确认弹窗的共用点只有两条：(i) 同为「打开
  瞬间新增整屏 fixed 层」的挂载冲击暴露面；(ii) 曾同用 DimStack
  ——备份弹窗已注销，现行 DimStack 仅灯箱（editor.rs:3602）。
  备份弹窗的遮罩 α=0、根色不压暗，与灯箱的 M2 双重压暗链**不
  共用**。若 §7 的量测最终指向「挂载冲击采样非根色图层」，灯箱
  议题应与本议并案复核采样对象。

## 4. 对照原版（src/）

| 项 | 原版 | Rust 现行 | 差异 |
|----|------|-----------|------|
| 遮罩 | fixedOverlay：fixed inset 0, z 4000, transparent（styles/inline.js:6-11），独立 div、可点关 | .backup-modal-scrim：fixed inset:0, z 5000, transparent，兼作 flex 容器，**不可点关** | 几何/色值等价；z 值与关闭手势不同（非带相关） |
| 底表定位 | 独立 wrap：fixed, left/right 0, bottom: env+14, z 4001, pointer-events:none（BackupView.js:802-812） | scrim flex-end + padding-bottom env+14（panels.css:194） | 等价 |
| 底表卡片 | 玻璃 bg + backdrop-filter、0.5px 边、radius 28、padding 14/14/calc(14+env)（BackupView.js:814-822） | 同值（panels.css:198） | 无 |
| 进场动画 | 无 | sheetIn 250ms 弹簧 | 有意偏离（用户拍板保留） |
| 根色 | 备份底表不碰根色（原版根色处理仅编辑页） | 同（裁定 C 后） | 无 |
| 弹窗数量 | 导出确认、恢复确认两张独立表 + 云端合并/恢复 window.confirm×2（BackupView.js:390,447） | 一组件两模式；云端两项随功能移除（用户 2026-11-22 拍板） | 结构合并，语义无缺 |

原版 BgSheet / ImageTextSheet 同用 fixedOverlay + 同型 wrap
（components/BgSheet.js、ImageTextSheet.js），与 Rust 两底表的
对应关系同上表。

## 5. 根因分级

- **proven（代码/算术）**：备份弹窗打开不写根色、不压暗、遮罩
  α=0；M2 与锁存模型按现行输入均预测带 = 页面色；全仓无第二处
  视口单位定高整屏层；带区无应用侧第二绘制者（body::before 仅
  顶部）；删除/放弃类确认弹窗不存在。
- **inferred**：若真机像素显示带色 = 底表玻璃本色（浅色 #ffffff
  等），则浏览器挂载采样对象不是根色——与顶带定案的采样模型
  同族但采样对象不同，现有证据不足以确立。
- **unknown**：用户所报实心栏的实际像素色值与出现时点（弹窗在
  场 / 点确认后）未量测——这是全案唯一缺的关键事实，且现行
  Diag 无法提供（见 §6）。

## 6. 仪器缺口清单

1. **备份弹窗 open/close 零 Diag**（settings.rs:377,409,500,523
   四个 set 点均无 log）：无从知道设备上弹窗何时开/关、开时根色
   与图层状态。应对：比照 LBX 加 MODAL 打点（open/close +
   log_probe 快照 + 整屏层 census），落在 settings.rs modal 的
   开/关路径。
2. **log_census 只挂在页面过渡点**（main.rs:639、editor.rs:2221）：
   弹窗打开时刻的整屏层清单（哪些 fixed 层在场、z 序）无记录。
   应对：MODAL 打点内嵌一次 census 即可（复用 diag.rs:152）。
3. **无弹窗打开后的延迟重采样**：log_late 仅过渡提交后触发
   （main.rs:643）。弹窗开后 300/1000ms 的根色/层状态无回读。
   应对：MODAL open 后同挂 log_late 三发。
4. 背景
...[truncated 2057 chars]