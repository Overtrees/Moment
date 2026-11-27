# 媒体增强批：Gallery 删/排序 + 视频插入路径（F-14 / F-15）

- 落码时点：2026-11-27，基线 HEAD 6ce6cd8（0.9.57 组版后），与多批同树并行落码（动工前 git diff 全量快照映射、逐 hunk 避让、完工复验标记完好）。
- 裁定依据：用户 2026-11-27——审计 F-14/F-15 双侧同缺的两项按原生增强补齐。
- 范围文件：`rust/apps/ios/app/MomentApp.swift`（全部落码）、`rust/apps/ios/app/verify_ios.sh`（新增 [33] 组）。不提交、不 bump，随下一组版。

## F-14 Gallery 删项 / 排序

### 现行编辑面（落码前考古）

- 编辑态 = `editor.cardEditBlockId == block.id`（卡菜单「编辑」进入、点卡外退出，EditorView 容器级 tap 与子点按共存触发）；既有动作：点瓦 = 换该张（PhotoPicker 单选）、点空瓦 = 加图（MultiPhotoPicker 多选）、模型单点 `applyGalleryAdd/applyGalleryReplace`（压栈 → 改 `node.attrs.items` → `nodeVersion += 1` → scheduleSave → Diag）。
- 本批在这套既有形态内增补，不新造编辑面、不引入新 sheet。

### 删项

- 模型单点 `applyGalleryRemove(blockId:index:)`：与 add/replace 同构（索引守卫 → pushHistory → 摘项 → 落盘 → Diag `EDIT gallery remove <id> idx=<i> left=<n>`）。可撤销（历史已压栈）。
- 呈现：编辑态每瓦右上 overlay 删项角标（`xmark.circle.fill` 双色调，22pt 字形 + 6 padding ≈ 34pt 命中区）。角标走 overlay 独立命中，与瓦面点按（换图）不叠触发。
- 节奏注记：角标点按与既有换图同为「一击办成 + 容器 tap 顺带退出编辑态」的 cardPick 节奏（与 Web 编辑态点瓦即办同型）；连删多张需重进编辑态。拖拽排序不受此限（拖拽非点按、不触发退出，可一口气排完）。
- **附件口径（核对结论）**：删项只摘节点里的项引用，**不删附件字节、不动清单登记**。依据：FFI/存储层无附件删除面（全仓无 remove/delete attachment 通路）；现行换图（applyGalleryReplace 换掉旧 fileId）、删块、换图片块均只摘引用、字节留存——本批与全仓现行口径一致，不另立引用计数/孤儿回收（那是备份/存储层课题，不在本批）。

### 排序

- 交互：编辑态长按瓦拖拽，`onDrag`/`onDrop` + `GalleryTileDropDelegate`：进入目标瓦即实时换位（跟随式），源位经模型侧会话变量 `galleryDragTileIndex` 链式跟进（同进程内拖拽，不经 NSItemProvider 异步读回）；落下 `performDrop` 收口。
- 模型单点 `applyGalleryMove(blockId:from:to:)`：一拖 = 一个撤销步——历史只在会话首动压一次（`galleryReorderArmed` 旗），与块拖拽 commitDrag 的单步口径同；会话收口点 = performDrop / `exitCardEdit` / 任一离散操作（加/换/删自带压栈时复位旗，防下一拖漏压栈）。
- **为何不复用 DragPressEngine（查清结论）**：该引擎是滚动视图级的 UIKit 长按引擎，注册表以**块行**为粒度（blockId 命中锚点 + 行级拾起/让位/落盘回调），无瓦级概念；泛化到瓦级等于重写三轮根治过的仲裁层，风险与收益不成比例。故走 SwiftUI onDrag/onDrop 独立轻量路。
- **同触点竞抢的源头收口**：瓦拖拽与块拾起同为长按起手——落码前卡编辑态的行仍武装拾起（dragAllowed 只排除编辑中的文本块），双路同触点必竞抢（拾起史三轮根治的同型病灶）。根治点在 `BlockRow.dragAllowed`：新增 `editor.cardEditBlockId != block.id` ——卡编辑态的行不拾起（编辑的是卡内容而非块本身；退出编辑态即恢复武装）。此条同时惠及 image/imgTextCard 等卡的编辑态（语义同为「编辑卡内容时不拾起块」）。

## F-15 视频插入路径

### 分流设计（两路，判据同源）

- 成块单点 `addVideoBlock(fileId:)`（与 `addImageBlock` 同形）：节点 `type: "video"`、`attrs.fileId` 为规范位——Web blocks.rs 的 video 分支正是按 file_id 渲染 BlobMedia、原生 `VideoBlockView` 亦按 `block.fileId` 取数写临时文件起播，双端呈现面零改动即通。
- **附件文件路**（••• 添加附件 → 文件，fileImporter）：附件写入成功后分流——系统内容类型（`resourceValues.contentType` 优先、扩展名 UTType 兜底）`conforms(to: .movie)` 者走 `addVideoBlock`，余皆维持 attachment 块。图片文件维持附件块现状（不在本批范围：Web 的 image→image 块分流是另一课题，本批只按裁定补视频）。
- **选片路**（••• 添加附件 →「图片/视频」，按钮文案同步改名）：`PhotoPicker` 增默认关的视频通道（`allowVideo` + `onPickVideo`）——开启时 filter 放宽为 images+videos，选中视频经 `loadFileRepresentation(UTType.movie)` 读字节（临时 URL 回调内即读）→ putAttachment → `addVideoBlock`。头像/换图/图库换图等其余四个 PhotoPicker 调用点默认关、行为零变化（verify M33-5 锁 `allowVideo: true` 全仓恰一处）。

### 斜杠面不加视频命令（论证）

- Web 斜杠 22 命令与原生 24 命令（多 math 两项为既定增强）均无视频项；视频的自然入口是文件/相册选择（须先有字节来源），斜杠命令集的媒体项（image/gallery）走的也是「先插占位、后选源」二段式——video 块无占位形态（VideoBlockView 无源即灰面占位、无点按补选路），硬加斜杠项要先造占位补选机制，超出「补插入路径」的裁定范围。附件/选片两路分流已构成完整插入路径，故不加。

### 已知约束（与现行附件机制同源，非本批新增）

- 视频字节整读入内存走 `putAttachment(Data)`——与现行附件路（Data(contentsOf:) 整读）、粘贴图、选图路同为整载口径，App 内无流式附件写入面；超大视频的内存峰值与现行大附件同风险面，留存储层课题。

## 矩阵登记文本（请主线并入 plan_selftest_coverage.md）

- **EDT-46（修订）**：gallery 增/删/排序/换——编辑态：多选追加（增）、点瓦换图（换）、角标删项（删，摘引用不删字节、删空回空态双占位）、长按拖拽排序（一拖一撤销步）；卡编辑态本行不拾起。
- **EDT-50（修订）**：视频插入与呈现——附件文件路与选片路按 UTType.movie 分流成 video 块（attrs.fileId 规范位、VideoBlockView 内嵌播放）；斜杠无视频命令（双侧同口径）。

## 断言与自检

- verify 新增 **[33] 媒体增强**组（M33-1…M33-5）：删项单点+角标接线 / 排序三件（applyGalleryMove + DropDelegate + onDrag）/ 卡编辑态行不拾起 / addVideoBlock 定义 1 + 调用 2 + movie 判据 / 选片器视频支默认关且开启恰一处。本机多轮全绿。
- 落码中一度顶动 [31] R31-8 的 Circle() 计数锚（角标 contentShape）——已按「不为本批小利动他人锚」删去该修饰（命中区改为含 padding 的整框、触达更大），R31-8 复绿、锚未动。
- 编译级自检：以 build-app2.sh 同旗标跑 MomentApp.swift primary-file 全量编译。**现行树有一处他批真 error**（见下），在 /tmp scratch 副本中仅中和该一处（副本内改写、真树未动）后，全文件零 error、.o 正常产出——本批全部区域（PhotoPicker/模型单点/dragAllowed/选片与附件 sheet/GalleryBlockView+委托）类型检查通过。
- verify 其余红项归属（完工时点实测）：[5] ipa 陈旧 + 产物语言包（组版在 tree 重建后消解，开工快照时已红）；[9] 五语键数期望 361 与后续批次补键漂移（本批零补键）；B16/B25 系桥/U4a 在途批。均非本批引入。

## 他批在途问题（转主线）

- `MomentApp.swift` 现行约 6230 行 `listStart(of:)`（E3 转换批 F-05 面）有真实类型错误：`(list.node["attrs"] as? [String: Any])?["start"] as? Int ?? 1` 被解析为产出 `[String: Any]?` 而非 Int（可选链与 as? 结合形态问题），且其后引发大片级联 error（级联均为伪影，中和该处后全消）。改法示例：先 `let attrs = list.node["attrs"] as? [String: Any]` 再 `attrs?["start"] as? Int ?? 1`。本批未动真树该处，归 E3 批自修。

## 真机终判点

1. Gallery 编辑态：角标删项命中与退出节奏（删一张后编辑态退出、撤销可回）、连删操作成本可接受否。
2. 拖拽排序手感：编辑页 ScrollView 内长按起拖的阈值与滚动争夺、LazyVGrid 内跟随换位的动画与落点、拖出网格取消后的序位（现口径：已实时换位并落盘，不回滚）。
3. 视频：相册选一段视频 → video 块内嵌起播；文件路选 .mp4/.mov → video 块而非附件行；大体积视频整载的等待与内存表现。
4. 卡编辑态行不拾起的回归面：编辑任一卡时点卡外退出后，块拾起/菜单恢复正常。
