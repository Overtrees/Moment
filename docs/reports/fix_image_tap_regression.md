# 图片卡点按进不了图片页 — 回归定案、普查、根治与补断言

日期：2026-11-28。触发：0.9.65 真机报编辑页图片卡（image 块）点击不再进入图片页。范围：卡片点按 / 图片页入口面；与开屏线、标题居中线并行，hunk 零重叠（本批面 ≤ 行 17545 区 + verify 尾组 + UITest + 矩阵；标题线已先行成笔 dc1d543）。

## 一、定案（proven，git 证据）

**切断者 = 审计批 3 的 d272e80（AUD-D-01：五面换 AnimImageView 承载）。** 机制链：

1. image 块的行级点按挂在 `BlockRow` 的 `.onTapGesture` 上，其命中域依赖内容视图自身的命中体；该行**无 `contentShape` 声明**（批 3 前后均无）。
2. 批 3 前，图面由 SwiftUI `Image` 叶子承载——`Image` 天然提供与自身帧等大的命中体，行级手势可达。
3. d272e80 把已载图分支换为 `AnimImageView`（UIViewRepresentable 包 `UIImageView`），而 `AnimImageView` 内部恒设 `img.isUserInteractionEnabled = false`（动图承载的被动语义，五面共用）——命中体消失，图面点按恒不达行级手势。行级手势与置位代码本身一字未动，故 diff 表面看点按链「完好」。
4. 余四面同批换承载却无恙，逐面查实各有显式命中形：gallery 瓦有 GeometryReader 满框；图文卡图区 `Color.clear + overlay + .contentShape(Rectangle())`；imageTextRow 图区同构；附件整幅图 `ItemImageView + contentShape`；附件图片文件行 `AttachmentRow + contentShape`。**image 块是五面中唯一靠叶子天然命中体的一面**，故独断。

嫌疑批逐个排除（diff 实证）：0a8079d 卡片防误触统一只动键盘合并守卫 / 拾起菜单 / 选中描边，未触点按链；94c9ab2 行盒单点只动高度双喂；ea50bb1 批 6 A-06 只动首页 MemoRow 折叠药丸；MomentDrag.swift 自 0.9.49 未动，仲裁层无恙（长按拾起在真机仍可触发亦旁证仲裁在位、断点在命中投递层）。

## 二、普查（图片页可开范围定案全集，逐项结论）

| 入口 | 结论 | 依据 |
|---|---|---|
| image 块（fileId 形） | **断（本批修复）** | §一机制；与 URL 形共用同一行级闭包 |
| image 块（URL 形） | **断（本批修复）** | 同上（同分支、同承载） |
| gallery 单项瓦 | 无恙 | GeometryReader 满框命中 + 瓦级手势 |
| imgTextCard 图区 | 无恙 | contentShape 显式命中形，tapImageArea 路由在位 |
| imageTextRow 图区 | 无恙 | 同上（与图文卡共用 ImgTextBlockView） |
| 附件整幅图（image 块附件呈现） | 无恙 | ItemImageView + contentShape |
| 附件图片文件行 | 无恙 | attIsImage 分流 + AttachmentRow contentShape |

不可开集（防误开复核，逐个确认仍无图片页路由）：musicCard / link-card 封面（readyCard 手势为 openCard 编辑路由、非图片页，未受损）、video（内联播放器，无图片页路由）、MD 预览内嵌图（MdImageView 无手势）、首页封面（列表派生图无路由）、头像（无路由）、非图片附件行（attIsImage 分流挡下）。2026-11-24 附件误入图片页前科的防线（分流判图）在位未动。

呈现端本已单点：`imageTarget`（@Published）→ 编辑器转场宿主订阅 push，各入口只差「置位写法」与「命中投递」两段未收口。

## 三、根治（路由单点 + 命中形补齐）

1. **路由收口单点**：`EditorModel.presentImagePage(fileId:urlString:name:)` 为全仓唯一构造 `ImageTarget` 之处（无名回退 `imgpage.untitled` 一并收口于此）；五入口（image 块 / gallery 瓦 / 附件整幅 / 附件文件行 / 图文卡 openImagePage 转调）全部改经单点，行为等价（参数与原直拼逐字对应，含图文卡原有的双路透传语义）。
2. **命中形补齐**：ImageBlockView 已载图分支在承载链补 `.contentShape(Rectangle())`——与图文卡图区同款显式命中形口径，使命中域与承载实现解耦（承载再换不丢命中）。未改 AnimImageView 的被动语义（五面共用、GIF 承载本分），不在消费方打补丁。
3. 手势仲裁零改动：长按拾起 / 卡片菜单 / 编辑入口的既有口径全保全（DragPressEngine 与行级手势的共存关系未动）。

改造后普查实测（MomentApp.swift）：`func presentImagePage(` = 1、`presentImagePage(` 合计 = 6、`imageTarget = ImageTarget(` = 1（仅单点本体）、ImageBlockView 段内 `contentShape(` = 1。

## 四、断言逃逸分析（为什么没抓住）

1. **运行腿路径未覆盖**：矩阵 IMG-01 行（U5 改判，c6bb21e）明文把图块入口降为「构建期口径、不作运行级同路断言」；唯一运行腿 image_page_open 的 gallery 步是**直接赋值 imageTarget 开页**，其分级注自承「瓦面点按投递不在证据面」——命中投递层从未被任何运行腿覆盖（验证记忆⑥「命中类断言必须真实 tap」的已知盲区在图片面复现）。
2. **构建期断言锁面错位**：verify [55] IMG 组只锁图片**加载**键控（ImageLoadGate 等）；[64] MD64-3 只锁 AnimImageView 定义 1 / 消费 5 的**计数**——承载换了、计数不变，命中形不在锁面。锁文本/计数不锁机制的典型逃逸。
3. **连带改判两条**（计数口径随收口漂移、不变量不变，按 6651e4e / 89df0e5 先例改判注沿革）：T-1 回退字面引用 3→1（单点本体）；SVG42-3 入口计数改锁 `editor.presentImagePage(` 恰 5（原直赋恰 5）。两条在本批 verify 复跑中先红后随改判转绿——这也反证旧计数锁的是「写法」而非「路由在位」。

## 五、新增断言与场景

- **verify [70] 组 TP70-1..5**（锁机制）：TP70-1 路由普查（定义 1 / 调用合计 6 / 直拼仅单点本体 1）；TP70-2 图块命中形（段内 contentShape 恰 1 + 承载被动不变量在位）；TP70-3 不可开集三段（CardBlockView / MdImageView / VideoBlockView）路由符号恒 0；TP70-4 场景同路（UITest 直拼 0、单点调用 ≥2、cards 景与 mediaOpen 夹具在册）；TP70-5 矩阵登记锁。
- **场景扩容**：新景 `image_page_open_cards`（夹具 `.mediaOpen`，与 `.media` 分开以免动首页封面派生序）三腿——图块 fileId 形、图块 URL 形、图文卡图区——经与生产同体的路由单点开页并断言呈页（fileId 形加断 hasImage 与标题 = 清单名）；既有 image_page_open 的 gallery 腿同步改经单点。**证据上限明说**：场景驱动按桥规矩以标识投递、不合成真实 tap，命中投递层的最终证据仍归真机真实 tap 终判；本批把「路由同体」推进到单点调用级，命中形由 TP70-2 构建期锁 + 真机终判收口。
- 矩阵 IMG-01 行已整行改写登记（定案、单点、[70]、两景、终判口径），另两处场景枚举同步补 cards 景。

## 六、点按入口覆盖表

| 入口 | 既有覆盖 | 本批后状态 |
|---|---|---|
| image 块点按（fid/URL） | 无（IMG-01 降级构建期口径；[55] 只锁加载） | TP70-1/2 锁 + cards 景两腿 + 真机终判 |
| gallery 瓦点按 | image_page_open 景（直赋开页，投递不在证据面） | 景改经单点同路 + TP70-1 |
| 图文卡图区点按 | 无运行腿（定案⑨仅代码在位） | cards 景第三腿 + TP70-1 |
| 附件整幅图 / 图片文件行 | 无专腿（分流由 SVG42-3 判图半边旁锁） | TP70-1 入口计数含此两路 |
| 卡片菜单（拾起菜单） | [68] AC68 组 + drag 景族 | 未动（本批零交集，复核在位） |
| 折叠钮（首页药丸 / 块折叠） | HOM 组 / A-06 面断言 | 未动（复核在位） |
| 附件行点按（非图片） | attIsImage 分流 + TP70-3 防误开半边 | TP70-3 新增无路由锁 |
| musicCard 封面 / video / MD 图点按 | 无 | TP70-3 无路由锁（防误开） |

## 七、验证分账

- 本机 verify_ios.sh 全量：702+ ✓，源码面全绿（含 [70] 五条、T-1 / SVG42-3 改判后转绿）；仅剩 ipa 陈旧、产物语言包 2 条既有产物红（tree 重建自清，非源码问题）。
- cargo test --workspace：本批未触 Rust 面，随单登记结果。
- **留账**：① Swift 首次编译门未过（本机无工具链）——MomentApp / UITest 两文件新码的编译终判在 tree 下一版组版冒烟；② cards 景装机实跑留下一版桥自办（与 image_page_open 复跑同批）；③ 命中投递终判归用户真机真实 tap（点图片卡进页、长按拾起不回归两项）；④ 图文卡场景腿以节点名断言标题，与生产「节点名优先」口径一致，清单名断言只挂 fileId 图块腿（夹具登记序确定）。
