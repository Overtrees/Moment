# 确诊：首页图文卡封面空白（图片卡抓不到图）

日期：2026-11-24。报告人：封面统一派生线。状态：根因 proven（读码 + box 活体复现双证），修复口径已由用户定案。

## 现象

用户给一篇备忘加入一张图片卡后，首页该备忘呈现为图文卡片样式
（.img-card），但卡片图片展示位为空白——图片卡里的图没有被抓
出来作封面。

## 复现（box，生产构建 91554d079d，导入夹具量测）

- 备忘「纯图片卡复现」：doc = [paragraph, image 块（fileId=rep-red，
  manifest 登记 image/png、字节在库）]。
  量测：.img-card 在场；`img.img-cover` 不存在；`div.img-cover`
  （无图占位）在场 → 封面位空白，与用户报告逐字一致。
- 对照「附件图对照」：doc = [attachment 块（image:true）]。
  量测：`img.img-cover` 在场、naturalWidth=8 → 正常出图。

## 根因（proven）

列表卡有两套互不一致的判定：

1. **样式门** `has_image`（list.rs）：doc 中有 image / gallery /
   imgTextCard / imageTextRow 任一块，或 attachment 且 image:true
   → 渲染为图文卡（.img-card，带封面位）。
2. **封面查找** `cover_file_id`（list.rs）：只扫 **attachment 块**
   取 fileId，其余块形一律不看。

两者交集之外即缺陷面：图只存在于 image / gallery / imgTextCard /
imageTextRow 块中的备忘，被样式门判为图文卡，封面查找却恒返回
None，封面位永远空白。用户加入的「图片卡」在编辑器内落为 image
块，正中此面。

另有两处同族不一致，一并在本线收口：

- attachment 文件行（image 标志为 false、但 manifest 登记类型为
  image/*，即用户经「添加附件」选入的照片）：样式门不认（恒文
  本卡），编辑器内点按却已按图片类文件走图片页（2026-11-24 扩
  围口径 att_file_is_image）——同一张图在编辑页是图、在首页不
  是图。
- `CoverImg` 取图以 manifest type 为唯一闸门：type 未登记但字
  节已在库时重试 5 次后恒空白；而编辑器内 BlobMedia 对同一
  fid 是取字节直渲（无 type 闸）——同一附件在编辑页能显示、
  在首页封面可能空白。

## 原版口径对照

原版同一分裂：`hasImageAttachment`（memo-list.js）认五种块形；
`ImageCard.js` 的缩略图查找却只找 doc 中第一个 `attachment`
节点读其 fileId。Rust 版忠实复刻了这一分裂（D-21 落码时以
ImageCard 为口径源）。本次按用户定案 supersede 原版该口径，
不属复刻回归。

## 用户定案（2026-11-24 15:18）

首页卡片封面 = 该备忘内**按编辑页排序最靠前的那张图**，来源
不限于图片块：附件图片、各类卡片内含的图片都算，统一一套机
制；被选中的那张图所在卡片/附件被删除时，顺位到下一张离它
最近的图。即封面是「当前文档序第一张图」的动态派生：渲染时
按现行 doc 计算，删除/新增/换序自动跟随，不落库、不留陈旧
指向。

## 修复设计

- `cover_source(memo, manifest)`：按 doc 块序深度优先遍历，
  首个命中即停，返回 File(fid) / Url(src) 两形来源（详见
  list.rs 实现头注的候选表与取舍）。
- `has_image` 并入同一派生：原样式门谓词 ∪ 派生命中（增量仅
  attachment 图片文件一类，与编辑器图片页扩围同判据），分组
  与行渲染同源。
- `CoverImg` 取图与 BlobMedia 对齐：manifest type 明确非图才
  停；字节在库即出图（type 已知为图时带类型建 Blob、未知时
  无类型建 Blob 靠浏览器嗅探）；type 已知为图而字节未到时保
  留 5×300ms 重试（导入在途）。
- 探针：probe_list_cards 扩「封面统一派生」组（纯 image 块出
  图、混合序首图、附件图片文件成卡、删首图顺位、拖拽换序跟
  随、无图纯文本卡），封面身份以图色像素判定，不只看在场。
