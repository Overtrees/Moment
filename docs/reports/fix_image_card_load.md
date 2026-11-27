# 根治：选了图片加载不出（图片加载身份键控）

- 对象：原生 app（诊断 diag_image_card_load.md；HEAD b682d02 + 状态栏批/审计批工作树）。
- 性质：落码批（未提交，留主线组 0.9.62；tree 冒烟随组版统一跑，本批未单独占 tree）。

## 一、落码清单

| # | 文件 | 改动 |
|---|---|---|
| 1 | **MomentImageLoad.swift（新）** | 纯核心（Foundation-only）：`ImageSourceKey`（fileId/urlString 原值键、hasSource、diagTag）、`ImageLoadDecision`（skip/start/reload）、`ImageLoadGate`（当前键单点持有、offer 比对推进）。按准备稿原样落。 |
| 2 | build-app2.sh | 名单登记：28 处既有名单各加一行 MomentImageLoad.swift + 新增 imageload primary 遍（imageload.o）+ 链接行加 imageload.o。全文件计数齐平 29（XSel/StatusBar/Undo/ImageLoad 一致），bash -n 过。 |
| 3 | MomentApp.swift · ImageLoader | 删 `started` 一次性闩锁 → `gate: ImageLoadGate` + `loadSerial` 代际号。load 呈键裁定：skip 零副作用；reload 先复位 image/failed 并记 `IMG reload <tag>`；publish/deliver 透传 serial/key/isReload，deliver 主线程单点代际守卫（过期结果弃、不覆新图不记行，SVG 异步光栅路同受守卫）；重载成功记 `IMG reload ok <tag>`；nil 源分支记 logOnce 首行 `IMG load nosource`。五处既有调用点形态不变、全经此漏斗受益。 |
| 4 | MomentApp.swift · ItemImageView | 加 `onChange(of: fileId)` / `onChange(of: urlString)` 双钩重呈 loader；加自检注册锚 image.item（instance = fid ?? url ?? "none"，state: fid/url/hasImage/failed/tone）。 |
| 5 | MomentApp.swift · ImageBlockView | 加 `onChange(of: block.fileId)` / `onChange(of: block.imageURL)` 双钩；加注册锚 image.block（instance = 块 id，state 同上）。 |
| 6 | MomentApp.swift · imgToneHex | 1x1 绘制取平均色 hex 帮手（场景图身份判读；小图精确、大图近似）。 |
| 7 | MomentApp.swift · GalleryBlockView | 新增 `GalleryTileEntry`（Identifiable，键 = 项 fileId/url、同图重复以出现序 `#n` 消歧、无图项回落位键）+ `tileEntries`；ForEach 由 `Array(items.enumerated()), id: \.offset` 改 `ForEach(tileEntries)`——瓦身份随项，换图/删项/排序后图随项走。 |
| 8 | MomentApp.swift · ImgTextBlockView | onAppear 旁加 fileId/imageURL 双钩（建卡无图 → 点图区 replace 塞 fid 当场出图）。 |
| 9 | MomentApp.swift · VideoBlockView/VideoHolder | **本批一并承担（审计批不再碰）**：VideoHolder 加 `preparedKey`；prepare() 键控化（源键 = url 串优先、否则 fid；同键且 player 在位才跳过；键变清旧 player 重备；fid 异步回主线程加 preparedKey 守卫防旧片覆新）；body 加 fileId/imageURL 双钩。AUD-E-05② 三静默出口补 VIDEO Diag 行：badurl（URL 串在而不可解析，.warn）、missing（附件空数据——**不建 player**，.warn）、write（写盘失败，.error）；另加无源 logOnce `VIDEO prepare nosource`。 |
| 10 | MomentBridgeUITest.swift | 夹具 `.media` 形态（段落甲 + gallery[ga/gb/gc] + 段落乙）+ `mediaFids/mediaColors/mediaTones` + `solidPNG` 纯色图生成；setup 在 persist 后经 Library.putAttachment 正式写面逐 fid 落附件字节；目录加两景 image_block_seated_load（EDT-60）/ gallery_items_follow（EDT-61）；两场景体（UITestScenarioImageSeated / UITestScenarioGalleryFollow）。 |
| 11 | plan_selftest_coverage.md | §4.5 媒体行群加 EDT-60/EDT-61 两行（已覆盖）；§0 计数同步：全集 154→156、编辑页 61→63（媒体/卡片/解析链 12→14）、已覆盖 34→36、UI 驱动 83→85；头部加本批增补注记。 |
| 12 | verify_ios.sh | 尾部新组 [55] IMG55-1..7（见 §三；落码时暂用 [54]，0.9.62 组版顺延定号 [55]）；IMGCORE 变量登记。**连带沿革更新（见 §四）**。 |

## 二、Diag 口径判断点（准备稿定、主线复核）

「加载成败都记 Diag」按「关键路径全程留痕」落地，不逐图刷屏：

- **重载**起始记 `IMG reload <tag>`、成功在 deliver 记 `IMG reload ok <tag>`——本症的日志形态从「有写入行、无加载行」变为成对可验。
- **首载成功不逐个记行**：列表滚动成批首载会冲 Diag 300 行环（G7/G8 去重先例同理）；首载失败沿既有 logErrorOnce 结果行。
- **nil 源**补 logOnce 进程级首行（占位块无图源本非失败，只留可判读痕）。
- 视频面同口径：失败三出口逐记、成功不逐记（播放面归人工终判，AUD-E-05② 只要求失败结果侧有痕）。

## 三、断言结果（本机）

- verify_ios.sh 新组 **[55] IMG55-1..7 全绿**：键控单点（核心三符号 + started 零残留）、闸门行为表驱动宿主实跑（呈键序列 8 步 + currentKey/hasSource/diagTag 形态，IMGLOAD_GATE_PASS）、变化钩子计数（块三视图双钩 3+3、瓦面双钩）、gallery 项键（段内 offset 身份 0）、Diag 行（IMG 成对 + VIDEO 四行 + preparedKey）、场景与矩阵登记、构建名单计数一致 + imageload.o ×2。
- verify 全量本机：**553 ✓**，余 2 红为既有陈旧产物项（ipa 早于源码、产物语言包待重建——本机未构建所致，tree 组版构建后归零，与本批无关）。
- swiftc -parse 三文件（MomentApp / MomentBridgeUITest / MomentImageLoad）零报错。全量类型检查与场景实跑归 0.9.62 组版 tree 冒烟（本批按派工未单独占 tree）。

## 四、连带改动与待主线知悉

1. **计数断言沿革更新（4 处）**：新增 imageload primary 遍使 build-app2.sh 全文件登记数 +1（FontFactory 27→28、其余 28→29）。按既有沿革惯例（DT46-6/E47-8/X50-7/SB-5 注释链均载「新增 primary 遍后计数递增 = 期望合法变更」）同步更新四处期望值与注释：DT46-6（27→28）、E47-8（28→29）、X50-7（28→29）、SB-5（28→29），注释均已注 fix_image_card_load.md 沿革。四处现全绿。
2. **组号 [54] 与审计批重号（0.9.62 组版已定夺）**：审计批（fix_audit_0962_b127）已先行占用 [54]（AU54-1..6），本组落码时同为 [54]（IMG54-1..7）。组版收敛已将本组顺延为 **[55] IMG55-1..7**（组标题、断言名、组内变量与全文引用同步；AU54 组不动）。
3. **VideoBlockView 源优先级注记**：旧 prepare 在 url 串不可解析时回落 fid 路；键控化后以声明源为准（url 键优先、badurl 记行收口，不回落）。视频块构造上只带单一源（url 或 fid 二选一），双源且 url 坏的形态无入口可达，差异实际不可达；此为有意收口、非行为回退。
4. **ItemImageView 注册面口径**：同 fid 多视图同屏时注册以后到为准（注册表既有口径）；EDT-60/61 场景在编辑页在席时读图面、不与首页同屏，口径可接受。
5. **场景读面限制**：ctx.state 只寻 instance "-"，两景经 UITestRegistry 按 instance（fid/块 id）直读图面——既有面限制，场景体内已注明。

## 五、真机终判点（诊断 §7 复现路径往返）

1. 斜杠「图片」建空块 → 点占位选图 → 回编辑页**当场出图**（旧：恒「图片不可用」）；Diag 应见 `EDIT card replace image … fid=…` 后跟 `IMG reload fid=…` + `IMG reload ok fid=…` 成对行。
2. 斜杠「图文卡片」→ 点图区选图 → 图区当场出图（旧：恒灰占位）。
3. 已有图块换图 → 当场换新图（旧：留旧图）；gallery 编辑态换图/删首项/排序 → 各瓦图随项不错位（旧：删首项后依次错位一图）。
4. 对照路回归：退出备忘重进图片仍在（数据面本无恙）；「添加附件 → 图片/视频」选图成块当场显示如旧。
5. 视频块：带 fid 新建/换片后播放器备新源；附件缺失的视频块不再出假播放面（Diag 见 `VIDEO prepare missing`）。

## 六、并发纪律自证

动工前 git diff 全量快照存 /tmp/imgfix_prep/baseline.diff；MomentApp.swift 本批 hunk 仅落在 ImageLoader/ItemImageView/ImageBlockView/GalleryBlockView/VideoHolder/VideoBlockView/ImgTextBlockView 段，与审计批的 Library/DiagLog/EditorModel/PdfMaker/开屏段零交叠；verify 只尾部加自组 + §四的四处计数沿革（逐处注出处）；未提交。
