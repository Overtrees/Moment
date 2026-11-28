# Web 浅色默认背景改判 #DAE3F0（与原生同批）

用户 2026-11-28 裁定：全页面浅色下默认背景色统一改 #DAE3F0
（RGB 218, 227, 240），Web 端与原生同批口径同步；同日 15:22
范围变更：Web 的启动页也改（index.html 内联启动/开机呈现面
一并到 #DAE3F0），救援面板本体维持不动。本批已落码、已部署
生产并对账。

## 坐标

- 分支 `fix/web-light-bg-dae3f0`（worktree `~/workspace/Moment-webbg`，
  父 = 81a5996）；落码笔 `a0530a7`，戳记与本报告为其后一笔。
- 生产戳：`1b3eee9998` → **`5ff8c91ac5`**（wasm md5
  `5ff8c91ac589bfb9663d9db6a1f8fa13`，归档 4,683,618 B）。

## 旧值来源普查（改前）

| 面 | 旧值与出处 | 性质判定 |
|---|---|---|
| 根令牌 `--primary-bg` 浅色 | `#f2f2f7`，tokens.css:3 | **单源本体**：html/body 默认层、`var(--mn-root-bg, var(--primary-bg))` 表达式全站共用（列表/设置/图片页/存储阻断页等） |
| 编辑器默认底 | `#FAFAFA`，editor.rs `effective_bg` 字面量（无自定义色备忘的默认有效背景）；tokens.css `--color-editor-bg: #fafafa` 为其命名令牌（CSS 侧无消费方，值靠 Rust 字面量镜像） | **属「默认背景」**：无自定义色时编辑页呈现的底色即它，与根令牌不同源是收口对象 |
| 外壳启动面 body 背景 | `#ffffff`，index.html 内联（先于样式表绘制，只能写字面量；注释自述原版 launch.css 白底口径） | 启动/开机呈现面，本批范围变更后纳入 |
| 外壳 theme-color 浅色 | `#ffffff`，index.html meta | 浏览器在启动/外壳期呈现的底色，与启动面 body 旧值同值同组，纳入启动面一并对齐（判定点名在此） |
| 救援面 | 面板卡/两条提示条底色 = `--glass-overlay-bg` 同值复刻（浅 #ffffff 系级联），index.html 独立定义段 | 与启动面**无共用定义**（启动面 = body/.splash 段；救援面源头是底表玻璃令牌、由 verify §13 锁）→ 按裁定维持不动 |
| `--launch-bg` | `#ffffff`，tokens.css「启动页专用」 | **无任何消费方**（全仓 grep 仅定义两处），不产生呈现，本批不动、仅登记 |
| body::before 顶带渐变 | 白色半透明渐变，base.css（与原版同构的光泽层） | 非底色定义、是覆在根色上的渐变层，不动 |
| 其余自带底色 | `.gesture-hint` #1c1c1e（深色提示条）、`--diag-bg` #111111（诊断终端面）、MD callout/code/quote 各令牌、manifest.json `background_color` #4DA6E8（品牌蓝、非旧底色） | 均非页面默认背景，逐个判定不动 |
| 历史注释 | main.rs:1537 注释中的 `#FAFAFA→#F2F2F7`（旧离页残差定案叙述） | 历史记录非呈现面，不改、不计残留（§21 普查口径已排除） |

## 收口面（本批改动，恰 4 文件）

- `styles/tokens.css`：`--primary-bg` 浅色 `#f2f2f7 → #DAE3F0`
  （深色 `#000000` 不动）；`--color-editor-bg` 同步 `#DAE3F0`。
  全站消费根背景的页面（首页/设置族/图片页/双栏与流式/存储
  阻断页）经既有同源表达式随令牌走，零逐面改动。
- `src/editor.rs`：`effective_bg` 浅色默认字面量
  `#FAFAFA → #DAE3F0`（含两处注释同值更新）。备忘自定义背景
  分支（Some(c) 原样/深色压暗）逐字不动——「默认」二字边界。
- `rust/apps/web/index.html`：启动面 body 背景
  `#ffffff → #DAE3F0`、theme-color 浅色 `#ffffff → #DAE3F0`
  （深色段 #000000 不动）；启动段注释补改判沿革。救援段
  （#mn-rescue / #mn-rescue-bar / #mn-swupd 的全部底色级联）
  逐字未动，§13 锁全绿即证。
- `scripts/verify_rustweb.sh`：新增 **§21 浅色默认背景同源锁**。

## 断言与负对照

§21 锁：令牌浅色值恒 `#DAE3F0`、深色值恒 `#000000`；
`--color-editor-bg`、editor.rs 字面量、index.html body 背景、
theme-color 浅色四面与令牌值逐个恒等对账；旧值普查——
`#f2f2f7` 在 styles 全域零残留、index.html 恰 2 处（救援深色
前景，点名保留）、src 引号字面量零残留；`#fafafa` 在 styles
与 editor.rs 零残留。

负对照实做两组：① index.html body 背景改回 #ffffff → §21
恰红一条（启动面恒等）、余节不误伤；② 令牌改回 #f2f2f7 →
令牌值/三面恒等/残留共 5 条恰红。均验毕还原，工作区干净。

全量 `verify_rustweb.sh`：**ALL PASS**（含 §13 救援锁、
§20、§21）。

## 暂缓面登记（改判后）

- **Web 侧：暂缓面撤销**——启动页已在本批同步改判，无剩余
  暂缓面；救援面是「维持不动」而非暂缓（其底色源为底表玻璃
  令牌，与页面底色本就不同源，§13 持续锁）。
- **原生侧：开屏暂缓维持**（用户对原生开屏的裁定不变，与
  本批 Web 启动面改判是两端各自状态，勿混读）。

## 部署与对账

流程按既有口径：`build.sh` 构建 dist（wasm 4,160,928 B）→
`archive_release.py` 归档干净版 `5ff8c91ac5`（归档无 key）→
staging 副本注入 `window.__APP_CONFIG__` 双 key（和风/彩云，
注入点与上一版线上形态同位：`</style>` 后、`</head>` 前；
staging 用后 shred 销毁）→ `deploy_api.py staging
canopies-moment`（DEPLOYED，env production）→
`verify_live.py 5ff8c91ac5 --url https://canopies-moment.pages.dev`
输出 **LIVE == ARCHIVE**（线上 sw 戳与 wasm md5 与归档逐字
一致）。线上 index.html 复核（布尔口径）：新 body 底色在位、
theme-color 新值在位、双 key 注入在位、救援段 `#f2f2f7`
仍恰 2 处、旧 body 白底消失。

戳记落点：CONTEXT.md「地址」节现行戳已更至 `5ff8c91ac5`、
CHANGELOG「Rust 版生产里程碑」已补本批条目。如实注记：两处
记录此前停在 `ffdc0845e2`（2026-11-25），与实际上一生产戳
`1b3eee9998` 已脱节——本批只更现行戳与本批条目，未补录他批
条目，待主线收口。

## 上线目检点（归用户/主线）

- 浅色：首页、设置族、图片页底色为 #DAE3F0 且各页一致；
  打开无自定义色备忘，编辑页底色同为 #DAE3F0；冷启动启动
  页底色与进入首页后无色差台阶。
- 深色：各页底色仍为黑、无变化；自定义背景备忘浅/深两态
  呈现与改前一致。
- 救援面：`?rescue=1` 面板与看门狗小条观感与改前一致（本
  批未动）。
