# 诊断：选了图片加载不出（图片卡片选图后不显示）

- 对象：原生 app 现行版本（用户在 0.9.60 VA 变体实报；VA 与 0.9.61 同代码面、仅多 appex，本诊断按现行版本问题处理，HEAD b682d02）。
- 性质：只读诊断。断点为源码级 proven；桥 Diag 活证未取到（见 §5）。

## 一、结论先行

**断点在呈现层，不在数据层。** `ImageLoader` 是一次性闩锁：`started` 布尔守卫 + 只在 `onAppear` 调用一次 `load`，且**没有任何按 fileId 变化重载的入口**（MomentApp.swift:3749-3790、4047）。而图片块/图文卡的主选图流恰恰是「先出空块、后经 `EditorModel.replaceImage` 原位改 node 塞 fileId」（6058-6075）：块视图在 fileId 尚为 nil 时已出现并把闩锁打死（`failed=true`），选图成功后 body 虽重演算（占位面消失、转入失败/占位分支——此现象本身即重演算发生的旁证），loader 永不重跑，所选图片在会话内永不显示。

数据侧全链无恙（§3 逐环节实证）：选图字节经 `putAttachment` 落库、清单登记、按 id 精确读回、解码路径均健全；且写失败有守卫（不成块 + 错误行 + 徽章），不可能产生「有块无图」的静默坏态。退出备忘再重进，视图重建、loader 新生，图片即正常显示——这也是判别本症的真机口径（§7）。

**回归定性：非 0.9.58–0.9.60 回归（源码实证）。** 闩锁机制源自 0.3.0（35c498d），空占位选图流源自 0.7.2（7d3ef7c）；0.9.58 媒体增强批（952e3cb）只动 gallery 增删排序与视频插入、0.9.59 SVG 批（f083be9）只动解码漏斗分流，均未触碰本机制。属长年潜伏缺陷、被用户本轮 VA 实测撞出（此点为 inferred：用户此前未走此流或以重进备忘掩盖，无从实证）。

## 二、断点机制（proven，逐行实证）

1. `ImageLoader.load` 以 `guard !started` 开头，`started` 置真后终身不复位；fileId 与 url 两路任选其一，皆 nil 时直接 `failed = true`——且该分支**无 Diag 行**（MomentApp.swift:3758-3787）。
2. `ImageBlockView`（3983 起）与 `ImgTextBlockView`（15731 起）各持 `@StateObject ImageLoader`，全仓 `loader.load` 调用点仅五处、图片相关四处全在 `onAppear`（3976 ItemImageView / 4047 ImageBlockView / 15893 ImgTextBlockView / 21735 图片页），无一处挂 `onChange(of: fileId)`（全仓 `onChange(of: block…)` 仅 imgTextEditSignal 一处，15897 旧行号）。
3. 编辑器整页由单个 `EditorHostingController` 承载（MomentEditorTransition.swift:79），块行视图身份随块存续——`replaceImage` 原位改 node 不重建块视图，`@StateObject` 随之存续、闩锁不解除。
4. 选图流时序（图片块）：斜杠「图片」把当前块原位转为无 fileId 的空 image 块（8961-8965，命令副文案即「插入图片占位」，5856）→ 块行点按（编辑态或 fileId 为 nil 时）置 `replaceImageBlockId` 并开选图器（10080-10107）→ `putAttachment` 成功后 `replaceImage` 写 `attrs.fileId`（11273-11284 的 sheet 回调）→ 视图重演算落入 `loader.failed` 分支显示「图片不可用」。图文卡同构：斜杠建卡时 node 无图（8984-8996）→ 点图区 `tapImageArea` 开同一 replace 选图器（15877-15880 段）→ 同一闩锁 → 图区恒为 160pt 灰占位（连失败文案都没有）。

## 三、全链逐环节核对（数据侧洗清，均 proven）

| 环节 | 实证 | 结论 |
|---|---|---|
| 选图器 | PhotoPicker/MultiPhotoPicker：`loadDataRepresentation(UTType.image)` 回主线程带 (Data, pickerFileName 真实名)（4097-4136、4160-4185） | 无恙 |
| 入口写库 | 各入口统一 `att-`+UUID 前 12 位 fid → `library.putAttachment(fid, data, name:)`，失败记错误行且**不成块**（11243-11284、9918-9948、7373、11318-11341） | 无恙 |
| 存储 | storage `put_attachment` 按 id 原样 INSERT + name 登记 manifest（storage/src/lib.rs:436-468）；`attachment_data` 按 id 精确查（419-430） | 无恙 |
| 块数据 | `addImageBlock` 写 `attrs.fileId`（7332-7345）；`BlockState.fileId` 读 `attrs["fileId"]`（119-121），键名两端一致 | 无恙 |
| 读回解码 | ImageLoader 后台读字节 → `decodeImage`（GIF 逐帧/单帧）；失败有 `图片加载失败 fid=… bytes=…` 结果行（3760-3770、3792-3826） | 无恙（本症根本没走到这一步） |
| SVG 分流 | `isSvgData` 要求剥 BOM/空白/XML 序言后首元素字面 `<svg`（MomentSvgRaster.swift:26-79），JPEG/PNG/HEIC 二进制首字节不可能命中 | 误判改道排除 |
| 清单/命名 | 0.9.36 命名根治面（put 同步登记 manifest）在位（storage 注释与实现一致） | 无恙 |

## 四、受影响入口清单

**坏（本断点直接命中）：**
1. 图片块·斜杠占位选图：/ → 图片 → 点占位选图 → 恒「图片不可用」。
2. 图文卡 imgTextCard / 图文混排 imageTextRow·点图区选图：恒灰占位。
3. 图片块·换图（已有图块在卡编辑态点图换新图）：loader 留旧图——显示错图（同机制、表现不同）。

**同族坏（gallery 瓦身份）：**
4. 图库换图（applyGalleryReplace）：瓦列表 `ForEach(id: \.offset)` 按位定身份（13688-13690），ItemImageView 存续 + 闩锁 → 恒旧图。
5. 图库删项/排序（applyGalleryRemove/Move）：items 按位移位、loader 按位留守 → 图随**位置**不随**项**，删首图后各瓦依次错位一图。

**同族潜伏：**
6. VideoBlockView.prepare() 同为 onAppear 一次性 + `guard player == nil`（15461-15515）；视频块现仅「带 fid 新建」一途，暂不可达，登记防新入口踩入。
7. 首页封面等 ItemImageView 调用点（19601、19829 等）：身份随备忘行、fid 随行稳定，暴露面低；备忘首图在列表不刷新期间变更时同理可陈旧，登记观察。

**无恙（对照组）：** 添加附件→图片/视频（全新块全新视图）、图库加图（新 offset 新视图）、粘贴图片成块、文件导入附件/视频、头像（data URL 通道不经 loader）、图片页（每次打开新 loader，21735）。

## 五、活证尝试（未取到）

经 custom.moment-bridge 调 `bridge_status`：三轮重试后 `app_offline`（app 不在前台），Diag 未取到，按任务口径注明不强求。本症在 Diag 上的预期指纹（供修复批与复验取证）：有 `EDIT slash image` / `EDIT card replace image … fid=…` 行、其后**无** `图片加载失败` 行（根本没发起加载）、重进备忘后图片正常——「有写入行、无加载行」即本断点的日志形态。

## 六、根治方案（交修复批，本批不落码）

按红线「机制根单点、不在消费方打补丁」：

1. **ImageLoader 改身份键控**：以 `loadedKey: (fileId, urlString)` 取代 `started` 布尔——`load` 时键未变才跳过，键变即复位 image/failed 并重载。单点改漏斗，五处调用点形态不变即全受益（含图片页、MD 内嵌图、封面）。
2. **调用点补变化钩子**：ImageBlockView / ImgTextBlockView 加 `onChange(of: block.fileId)`（及 imageURL）重调 load；ItemImageView 加 `onChange(of: fileId/urlString)`。与 1 配套——只改 1 不补钩子，重演算时无人再调 load，照样不刷。
3. **Gallery 瓦身份改项键**：ForEach 身份由 offset 改为项的 fileId/url（无图项回落其在 items 中的稳定占位键），使换图/删项/排序后 loader 随项走；与 2 的钩子互为双保险。
4. **VideoBlockView 同步键控**：prepare 按 fid 记已备键，fid 变重备。
5. **Diag 补行**：loader 因键变重载时记 `IMG reload fid=…` 结果行，使本症在日志上从「无行」变「有行可验」；nil 源分支维持静默（占位态本就无图、非失败）。

**断言设计（verify_ios.sh 新组，机制锁）：**
- 源码锁：ImageLoader 无无条件一次性闩锁（loadedKey 模式在位）；三视图各有 fileId 变化重载钩子；gallery ForEach 非 offset 身份。
- 宿主单测：loader 键控纯逻辑表驱动——同键重复调零重载、键变必重载、nil→fid 迁移必载。
- 自检场景（覆盖矩阵新行）：夹具备忘内斜杠建图片块 → 程序化走 replaceImage 塞夹具图 → **不重进**断言 loader.image 非 nil；图库换图/删首项后逐瓦断言图随项。
- 完整性口径：重载只读当前块当前 fid，断言「存量附件不串件」——A 块换图后 B 块图不变、gallery 删项后余项图各归其项（沿 XSel 批的完整性断言先例）。

## 七、真机复现路径（用户口径）

1. 打开任意备忘 → 输入 `/` → 选「图片」→ 点占位「点击添加图片」→ 选一张照片 → 回到编辑页：图片块显示「图片不可用」。图文卡片同理：`/` →「图文卡片」→ 点上方图区选图 → 图区恒灰。
2. 退出该备忘、重新打开 → 图片正常显示（证明照片已存好，坏在呈现）。
3. 对照路（无恙）：「添加附件 → 图片/视频」选图 → 新图块当场正常显示。
