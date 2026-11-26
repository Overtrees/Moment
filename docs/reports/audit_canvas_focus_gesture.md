# 空白落焦真机失效——分支②取证与手势内同步落焦修法设计

状态：取证定案（2026-11-23）；落码待闸门（920f9bb 后 ≥8 笔，拾起重构批落盘后动手）。
基线：45b5b46（构建 82da190a4f）。

## 一、分支裁定：②（proven）

- 用户真机 Diag（2026-11-23 12:48，备忘 1795409199531）：连点正文空白区记下四行
  `[12:48:27~28] EDIT canvas focus -> b9b72d68e05`——canvasFocusRoute 在 iOS 上触发无误，
  目标即该备忘唯一文本单元（与开页 auto focus 同 id），路由与目标解析都对；
  但真机无光标、无键盘（用户随即改点标题，12:48:41 title caret tap 正常）。
- 同日志 12:57 多个新建备忘会话无 canvas focus 行：那些会话开页 auto focus 已落焦，
  未构成空白点按样本，不作反证。

## 二、失效机制（代码级 proven；WebKit 内部丢弃点为 inferred）

落焦路径（现行 45b5b46）：

1. 桥 click 监听（bridge.rs，document click 非捕获）调 canvasFocusRoute；
2. canvasFocusRoute 在桥内**同步**执行 setCaretEdge(last, true)——el.focus() + Range 置末尾选区；
3. 随后 dioxus.send({t:'canvasFocus', bid}) 仅供 editor.rs 记 Diag（editor.rs 对 canvasFocus
   只落日志、不回任何 op）——**落焦本身不经 wasm 异步队列**，任务单「异步 op」嫌疑就此排除。

失效点在第 2 步的执行时机：iOS 上 click 是 touchend 之后合成的兼容性事件，WebKit 不把它
当作可信用户激活手势——click 阶段的编程式 focus()/选区设置不被承认为手势内聚焦，
键盘不弹、光标不显。对照组（同机同页 proven）：点首行文本单元本身走桥 pointerdown/
原生路径落焦正常；标题点按落焦（title caret tap）正常。

修法方向因此定为：把路由触发从 click 阶段前移到 **pointerup 手势事件内同步执行**。
pointerup 是 Pointer Events 规范的真实手势事件（非合成兼容事件），且桥内既有先例：
editorPointerUp 在 pointerup 里同步 setCaretEdge + focus 处理选区点按
（「iOS 需要手势内同步聚焦」的同款约束，选区点按真机可用即其旁证）。
pointerdown 阶段不落焦：按下时选区/手势意图（点按/滚动/长按拾起）未定，按压状态机
自 pointerdown 起量测位移与时长，pointerdown 落焦会污染其判据并与原生滚动竞争。

## 三、修法设计（根治，复用既有函数本体，零新判定逻辑）

改动文件：`rust/apps/web/src/editor/bridge.rs`（桥脚本）、`probe_canvas_focus.mjs`、
`run_all_tests.sh`、`TESTING.md`。editor.rs 不动（canvasFocus op 语义不变）。

1. **记录器扩展**：既有 capture pointerdown 记录器（canvasPressOnCanvas）在判定为画布本体
   按下时，另记 `canvasTap = {id: ev.pointerId, x: ev.clientX, y: ev.clientY}`；
   仅当 `(ev.isPrimary === undefined || ev.isPrimary) && (ev.pointerType !== 'mouse' || ev.button === 0)`
   时记录（右键/多指副指针不记，避免 contextmenu/双指手势误触发）。
2. **pointerup 主路**：在既有 document pointerup 监听（editorPointerUp 所在）之后、
   pressCleanup 之前，新增一段：canvasTap 存在且 `ev.pointerId === canvasTap.id` 时，
   先取走并清空 canvasTap；位移 `dx*dx+dy*dy <= 100`（10px，与按压机触摸取消武装的
   d2>100 阈值同值）则调 `canvasFocusRoute(ev.target, ev.clientX, ev.clientY)`；
   返回 true 时记 `canvasTapDone = {x, y, t: Date.now()}`。
   - 触摸隐式指针捕获使 pointerup 的 target 恒为按下元素（body 本体/栏本体），
     与 canvasFocusRoute 入参形态（target + 坐标）恰合；桌面鼠标无捕获、target 为
     释放点元素，命中块时函数内 `closest('[data-bid]')` 自行早退。
3. **pointercancel 清理**：既有 pointercancel 监听内加 `canvasTap = null;`
   （手势被滚动接管/系统打断时不留陈旧记录；且滚动手势的 pointerup 若仍到达，
   位移判据亦会拦下，双保险）。
4. **canvasFocusRoute 改返回布尔**：全部早退路径 return false；落焦并 send 后 return true；
   函数本体（scope 解析、canvasPressOnCanvas 守卫、xsel 守卫、原生选区未收拢守卫、
   末单元顶边判据、双栏回退）零改动复用。
5. **click 路由降为兜底 + 去重**：既有 click 监听调 canvasFocusRoute 前先判：
   canvasTapDone 在 1000ms 内且与 click 坐标差 ≤2px → 跳过（主路已落焦，避免 Diag 双记
   与二次 setCaret 扰动）；否则照旧调用（覆盖无 Pointer Events 的环境与键盘/程序化 click）。

守卫全保留：手势起点在画布本体（canvasPressOnCanvas，pressStart 时刻由 pointerdown
记录器写入，pointerup 时仍有效——pressCleanup 在其后才清）、拖选进行中（xsel）、
原生选区未收拢、点位须在末单元顶边之下、双栏按栏解析 + 空栏回退全栏、盒外不干预。

## 四、探针增补（probe_canvas_focus 新增第 ⑤ 节）

- CDP 触摸点按（Input.dispatchTouchEvent touchStart/touchEnd）点空备忘正文下方空白：
  落焦首段、Diag `canvas focus ->` 计数恰 +1（验主路落焦 + click 去重）、打字落字。
- 合成 PointerEvent（pointerdown/pointerup，不派发 click）单独驱动：落焦成立
  （Chromium 口径下证明主路不依赖 click）。
- CDP 触摸滚动（纵移 60px）：不落焦、Diag +0（位移判据）。

## 五、验收口径边界

- Chromium 探针只能证明接线、判别与去重逻辑；**键盘弹出与光标可见的终判不在 Chromium 口径内**。
- WebKit 口径复验须走 Muse app 内置浏览器（browser device 通道）对生产构建执行：
  空备忘多点位点按落焦 + 落字、内容备忘落末尾——此通道无子代理 browser 工具，须主线执行。
- 最终终判：用户真机（新建笔记点正文任意空白出光标）。
