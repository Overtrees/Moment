# 原生画廊有图态添加路径同型排查（2026-11-28）

> 主线暂存件：排查线回报全文。0.9.67 合并收口后由原生画廊修复线落入 docs/reports/audit_native_gallery_add.md。

缘起：Web 端实报画廊有图后右侧为空白死区、无添加瓦片，菜单→「编辑」为页面提示的既定路径；用户指令同步排查原生 iOS 是否同病。方法：源码接线普查（MomentApp.swift 为主），结论分级：源码接线 = proven；设备行为未在本批复验（见 §4 留账）。

## §1 逐项结论表

| # | 排查面 | 结论 | 一句话依据 |
|---|---|---|---|
| 1 | 画廊有图态添加瓦片 | **同病** | 有图分支只渲染图瓦，无添加瓦；添加入口唯一接线在空态占位瓦 |
| 2 | 长按菜单→「编辑」路径 | **同病（死胡同）** | 菜单可进卡编辑态，但有图态编辑态只有换图/删项/排序，无追加 |
| 3 | 单图块换图 | 正常 | 点按（编辑态或空图）→ 换图链无状态残留，二次触发同构 |
| 4 | 图文卡/图文行图区加图 | 正常 | 编辑态点图区走同一换图链写图槽，空卡亦可由此设图 |
| 5 | 附件再添加 | 正常 | 每次调用成新附件块；块内追加无此 affordance 属设计 |
| 6 | 视频添加 | 正常 | 两条成块路均可重复触发；存量视频块无换片 affordance 属设计 |

## §2 画廊定案（同病，根因定位）

**添加 machinery 本身完好、且是追加语义**：`EditorModel.applyGalleryAdd`（MomentApp.swift:7060）向 `attrs.items` 逐项 append → `scheduleSave` 落盘；其唯一调用点是 `CardEditSheets` 的 MultiPhotoPicker 完成回调（:11329，多选、逐张 putAttachment 后调 add）。

**唯一触发点被空态门死**：`editor.showGalleryAddPicker = true` 全仓只有一处赋值——GalleryBlockView 空态占位瓦的点按（:15347–15350），且该瓦只在 `items.isEmpty` 分支渲染（body :15308 起，空态分支 :15319 起）。有图分支（:15355 起 `ForEach(tileEntries)`）只出图瓦：常态点瓦进图片页、编辑态点瓦 = 换该张（galleryReplaceIndex + replace picker，:15396–15402）、编辑态另有右上删项角标与长按拖拽排序。**有图后不存在任何能到达 add 链的 UI 路径**；单图时网格右格即用户在 Web 点到的那块死区（原生同构：LazyVGrid 只出已有瓦、余格为行背景）。

**菜单路径对位核**：拾起卡菜单（cardMenuPanel :12983）对 gallery 只出「编辑」「删除」两项；「编辑」置 `cardEditBlockId` 进卡编辑态（:12996），而有图态卡编辑态的全部动作就是换/删/排——与 Web 提示文案承诺的「点『编辑』添加图片」在原生同样落空。两端同型：不是接线断裂，是 affordance 从未在有图态存在（Web 侧 blocks.rs 有图格网同样无添加格、dispatch 注释自注「galleryAdd=空画廊追加」；原生代码注释亦自注「编辑态点空瓦 = 加图（Web cardPick galleryAdd 同口径）」——两端都是忠实移植了原版的空态限定设计，用户实际使用中撞到的正是这个设计缺口）。

**断言面**：verify_ios.sh 对 `showGalleryAddPicker`/`applyGalleryAdd` 零断言；桥场景中 applyGalleryAdd 零调用（EDT-61 gallery_items_follow 只验删项/换图模型面）——缺口从未被任何锁或场景覆盖。

## §3 同型普查证据链（原生）

- **单图块换图（正常）**：行点按分流（:11562–11577）——编辑态或无图 → `replaceImageBlockId = block.id` + `showReplacePicker = true`；sheet 消费（:12820）PhotoPicker → putAttachment → `replaceImage`（:6987）写 `attrs.fileId` 后清会话位。每点重设会话位、无一次性状态，二次/三次换图同构。
- **图文卡/图文行图区（正常）**：`tapImageArea`（:17830）编辑态同走 replace 链；`BlockState.fileId` 单点读 `attrs.fileId`（:167），图槽与单图块同位，空卡在编辑态点图区即完成首次设图（充当其添加路）。
- **附件再添加（正常）**：附件流（斜杠/菜单→ attach choice :12863 → 选媒体或 fileImporter :12870）每次成功都 `addAttachmentBlock`（:8342）追加一个新单文件块，两路（媒体/文件、视频在 fileImporter 内按 .movie 分流成 video 块 :12898）均可重复调用。AttachmentBlockView（:17494）为纯呈现（文件行→图片页/分享），块内追加文件无此 affordance——多文件 attachment 块仅由导入产生、只读呈现，与 Web 模型一致，属设计。
- **视频添加（正常）**：成块两路——选图 sheet 的视频分流（PhotoPicker allowVideo + onPickVideo，:12792）与 fileImporter 的 .movie 分流，均调 `addVideoBlock`（:8289）成新块，可重复。存量 video 块不在 editCardTypes（:7028），卡菜单只出删除、无换片——无此 affordance 属设计（F-15 定位：原生增强的成块路，块级编辑从未在列）。

## §4 设备面留账（0.9.67 装机桥自办候选格，不冒充已验）

本批未在现装 0.9.66 上跑桥：添加链的关键段（PHPicker 系统 UI）桥本就驱动不了，且无现成场景覆盖 add。候选格：
1. 新景 `gallery_add_append`：夹具画廊 1 项 → 经 sheet 消费同路（putAttachment + applyGalleryAdd，绕 PHPicker）追加 2 项 → 断言 items 1→3、存盘重进仍在、夹具自洁。
2. 修复落码后：有图态卡编辑态下添加瓦的呈现与点按开 picker，只能真机目检/点验（picker 呈现本身以 Diag 行 `EDIT gallery add <id> +N` 为设备侧痕迹）。

## §5 修复建议（未落码，待主线与 Web 线的 affordance 裁定对齐后同批落）

模型层零改动即可闭合：GalleryBlockView 有图分支中，当 `editor.cardEditBlockId == block.id` 时在末项后追加一张添加瓦（高 366、角位按 count+1 走既有 tileCorners），点按复用空态同一对赋值（galleryPickBlockId + showGalleryAddPicker = true）——直达现成 add 链。单图时该瓦恰落用户点到的右格死区。配套：verify 结构锁（有图分支含添加瓦接线、setter 计数 1→2 且均受卡编辑态门）+ §4 新景 + 自检矩阵登记一行。非编辑态不露出添加瓦，与既有编辑态门禁设计一致（占位文案 hint 引导长按→编辑的路径由此才真正兑现）。
