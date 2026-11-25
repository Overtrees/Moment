<p align="center">
  <a href="https://mynote-rustweb.pages.dev"><img src="./Mynoteicon.png" width="80" alt="此刻"></a>
</p>

<p align="center">
  <strong>此刻</strong>
</p>

<p align="center">
  <a href="https://github.com/Overtrees/Moment/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="https://mynote-rustweb.pages.dev"><img src="https://img.shields.io/badge/App-%E5%9C%A8%E7%BA%BF%E4%BD%93%E9%AA%8C-brightgreen" alt="App"></a>
  <a href="https://github.com/Overtrees/Moment/commits/main"><img src="https://img.shields.io/github/last-commit/Overtrees/Moment" alt="Last Commit"></a>
</p>

有时候你只是想记一句话、存一张图、贴一个链接。  
不想先建目录，不想被一堆按钮打断，也不想为了记点东西先登录账号。  
「此刻」就是为这种场景做的：无需选择模版，打开就写，数据归你。

音乐链接贴进去自动变卡片、标题点一下就能改、顶部渐变随背景色自适应——这些细节你可能用着用着才会发现。

> 当前线上版本为 Rust 重构版（Rust Core + Dioxus Web）；原版实现保留在 `src/` 作为行为规格参照。项目上下文一览见 [`CONTEXT.md`](./CONTEXT.md)。

## 这个 App 想解决什么问题

不是做一个"最强笔记系统"，而是做一个你愿意每天顺手打开的记录工具。

你会在这些时刻用到它：

- 🚇 地铁上突然想到一个点子，想马上记下
- 🎵 刷到一首歌，想留个卡片以后再听
- 📋 记会议要点、待办、灵感碎片，不想切来切去
- ✨ 对日常碎片化记录，想做个好看的排版

---

## 日常会用到的功能

### 📝 记
- 段落、标题、待办、引用、分割线、代码块、Callout 提示块
- 图文卡片、图片卡片、文件附件（图片自动渲染，PDF/Word 等文件支持点击系统分享）、音乐卡片（粘贴链接 / 斜杠命令插入，通过 Cloudflare Worker 抓取元数据，部分地区可能受限）
- 标题胶囊：滚动自适应横竖排，点一下就能改
- 斜杠命令面板：22 种排版命令，支持搜索筛选和最近使用
- Markdown 自动渲染（**粗体**、*斜体*、~~删除线~~、`行内代码`；应用内额外支持 ==高亮==、提示块、数学公式、双链、脚注、上标与下标）
- 单篇笔记可从“更多 → 导出”选择 Markdown、HTML 或 PDF：Markdown 导出语义化内容与可表示的媒体链接；HTML/PDF 保留编辑器当前的卡片结构与样式，PDF 由浏览器打印生成

```md
> [!TIP]- 自定义标题
> 这里是可折叠的 **提示正文**。

行内公式 $x^2 + y^2 = z^2$，双链 [[另一篇笔记|自定义文字]]，脚注[^来源]，上标 ^(高1)^、下标 ~(低1)~。

$$
\frac{1}{2}
$$

[^来源]: 这里是脚注正文。
```

`> [!TIP]+ 标题` 会默认展开，`-` 会默认折叠。旧笔记里的 `:smile:` 等 emoji 短码，以及已停用的自定义标记（如 `!!提示`、`#标签`、`$标签$`、`->居中<-`），都会按原文显示，不会被转换或改写。

### 👀 看
- 首页按时间分组，信息一眼就能找到
- 手机竖屏保留时间线列表；手机横屏与平板使用三列方卡，宽桌面（1280px 起）使用四列
- 支持置顶、展开/收起长分组
- 图文卡片自动识别文件类型，图片显示原图，非图片文件可点击打开
- 平板和桌面编辑器采用双栏布局：两栏是各自独立的容器，可分别编辑、滚动与混排，任何块不整幅跨栏；笔记保存、撤销/重做及导出保留从左到右的内容顺序。较窄的手机横屏保持单栏
- 从编辑页返回时，首页从右侧跟随滑入，过渡自然

### 💾 存
- 默认本地保存（SQLite 为主存、IndexedDB 镜像双写，均在本机浏览器内）
- ZIP 导出/导入（含所有图片、附件与头像），导入经整包校验后全量替换
- 本地记录、单篇导出和 ZIP 备份都无需注册登录

### 🎨 调
- 字号切换
- 笔记背景色（8 色可选，顶部渐变自适应背景色）
- 头像（默认内置图标，可自定义，随 ZIP 备份导出/导入）
- 毛玻璃样式按明暗主题、透明度偏好和浏览器能力回退，并保留可读边界

---

## 和常见笔记工具不一样的地方

| | 其他笔记 | 此刻 |
|---|---|---|
| **组织体系** | 文件夹 / 标签树 / 数据库 | 打开就写，时间流 |
| **账号** | 强制注册登录 | 无需登录 |
| **数据** | 默认存服务端 | 默认存本地，ZIP 备份由你自己保管 |
| **外观** | 功能优先 | iOS 原生感（毛玻璃、过渡、圆角） |

---

## 界面预览

<details>
<summary>点击展开截图</summary>

### 首页
![首页列表](./screenshots/list-view.jpg)

### 编辑页
![编辑页面](./screenshots/editor-view.jpg)

### 设置页
![设置页面](./screenshots/settings-view.jpg)

### 备份页
![备份页面](./screenshots/backup-view.jpg)

### 音乐卡片
![音乐卡片](./screenshots/music-card.jpg)

</details>

---

## 隐私

- 默认笔记和附件保存在本机浏览器存储（SQLite + IndexedDB）；导出的 ZIP 备份目前没有客户端加密。
- 天气功能会自动请求浏览器定位；定位不可用时会尝试 IP 定位，并把坐标发送给天气服务查询天气与城市（和风主用、彩云兜底）。此功能需要网络与部署时注入的 API 配置。
- 链接元数据和图片代理请求会把目标 URL 发送到 `mynote.overtrees.workers.dev`；Worker 实现不在本仓库中，无法从此仓库确认其日志、转发或保留策略。
- 当前版本不提供云备份：笔记只在本机与你手动导出的 ZIP 之间移动，不会上传到任何账号。
- 自定义头像保存在本机（并包含在 ZIP 备份中）；浏览器本身也会向天气服务和 Worker 等发送必要请求。

---

## 技术说明

- 生产实现：Rust（Dioxus DOM Web + Rust Core），构建为 WebAssembly；Markdown 渲染、公式、字体和其他静态资源均使用仓库内资源，不依赖运行时 CDN；Service Worker 会预缓存这些本地资源，支持首次缓存完成后的离线编辑。
- 本地存储：SQLite（OPFS SAHPool，存储 Worker 化）主写 + IndexedDB 镜像双写（观察期）；附件为文件式存储。
- 数学公式：纯 Rust 渲染为 MathML，不依赖 KaTeX 的 JS 运行时。
- Cloudflare Worker（链接抓取与图片代理）。
- 天气查询和链接元数据是联网服务，不会被伪装成本地资源；断网时这些在线功能不可用，本地笔记编辑与存储仍可用。
- 原版（React 18 UMD）保留在 `src/`，作为行为规格参照，不再是线上实现。

### 代码结构

- `rust/`：现行生产实现——`crates/core`（文档模型、迁移通道、ZIP 备份、TeX→MathML 公式渲染）、`crates/storage`（SQLite 索引与全文搜索）、`apps/web`（Dioxus Web 应用；存量数据经迁移通道归一后与原版互通，行为等价优先于形态复刻）、`apps/storage-worker`（存储 Worker）。回归矩阵见 `TESTING.md`（一键运行 `bash run_all_tests.sh`），静态一致性检查为 `bash scripts/verify_rustweb.sh`
- `Moment.html`：原版页面骨架、样式与脚本引用（原版仅作行为规格参照）
- `src/app/`：原版运行时桥接、Editor（含斜杠菜单、历史和导出）、列表、天气、启动等应用模块
- `src/styles/`：原版全局设计令牌、基础样式、编辑器/卡片/面板样式
- `src/editor/`、`src/components/`、`src/services/`、`src/hooks/`、`src/utils/`：原版 Markdown/块渲染、界面组件、存储与备份、交互 Hook 和通用工具
- `tools/verify.mjs`：原版校验本地资源、版本串、跨模块声明与 CSS 变量完整性
- `tests/`：原版单元、结构、浏览器响应式、音乐卡片与视觉回归测试
- 项目上下文一览见 [`CONTEXT.md`](./CONTEXT.md)；开发规范见 [`开发规范.md`](./开发规范.md)，设计口径见 [`设计规范.md`](./设计规范.md)，踩坑记录见 [`教训沉淀.md`](./教训沉淀.md)，改进与修复记录见 [`CHANGELOG.md`](./CHANGELOG.md)；原版工程约定见 [`docs/engineering-notes.md`](./docs/engineering-notes.md)，原版视觉规范见 [`docs/mynote-visual-language.md`](./docs/mynote-visual-language.md)（参照）

### 自动视觉回归（原版侧）

以下为原版（`src/`）侧的回归方式；Rust 版的回归矩阵见 `TESTING.md`。

`npm run check` 会运行静态校验、单元测试和 Chromium 截图回归。视觉矩阵覆盖手机、平板、桌面三种视口，浅色/深色主题，以及默认透明度、减少透明度偏好和无 `backdrop-filter` 回退（共 18 组）。运行前需有 Chromium 可执行文件（默认路径为 `/usr/bin/chromium`）。

单独运行可使用 `npm run test:browser:visual`。只有在有意调整界面并审阅结果后，才使用 `UPDATE_VISUAL_BASELINES=1 npm run test:browser:visual` 更新 `tests/browser/visual-baselines/` 中的基线；默认运行会与基线做像素比较。需要时可通过 `CHROME=/path/to/chromium` 指定浏览器。
