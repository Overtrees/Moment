# MD 预览缓存陈旧隐患：定性与根治（fix_md_cache_stale）

- 线索：impl_conversion_e3.md 附带发现——`mdKind` 文本变更时清 `mdBlocks` 却不复位 `mdCacheDone`，其后 `mdBlocks` 可能返回空树（E3 记：机制 proven / 运行可达性 inferred，请主线转预览批次定性）。
- 本批结论：**可达性 proven（代码级全链坐实）**，已按失效单点收口根治。未提交、未 bump，随下一组版。

## 1. 定性：proven 可达

### 1.1 缓存一族的全部读写点（全仓实证）

缓存四字段住 `BlockState`（MomentApp.swift:84-89）：`mdCacheText / mdCacheKind / mdCacheBlocks / mdCacheDone`。全仓写点仅两处，均在 EditorModel：

- `mdKind(for:)`（:6003 起）：文本未变回缓存分类；文本已变 → 重分类、回填 text/kind、**直清 `mdCacheBlocks = []`，不复位 `mdCacheDone`**（病灶）。
- `mdBlocks(for:)`（:6019 起）：命中条件 = `mdCacheText == block.text && mdCacheDone` → 直返 `mdCacheBlocks`；未命中才解析并回填三字段 + `mdCacheDone = true`。

消费点仅两类：行渲染分支（:8880，`mdKind != "none"` 为 MdPreviewView 的入场条件）与 `MdPreviewView.body`（:13506/:13516，只调 mdBlocks）。E3 的 strip 路径（mdKind 后直调 mdParseJson）不经缓存树，免疫，与 E3 报告一致。

### 1.2 可达序列（每步均为现行代码的确定路径，非竞态）

1. 段落 P 含 MD 语法、未在编辑：行分支先调 `mdKind`（首填分类），再建 MdPreviewView，其 body 调 `mdBlocks` → 解析回填：cacheText=A、blocks=树A、**done=true**。
2. 用户点按预览 → `beginMdEdit`（:6034）进入编辑；`textViewDidChange`（:3142）以 `parent.block.text = tv.text` **原地改写同一 BlockState 实例**的文本 A→B（编辑全程不重建状态；重建只发生在打开文档与 undo/redo 快照回放 `applySnapshot`）。
3. 失焦（editingBlockId/focusBlockId 清除）→ 行分支重演算，**恒先调 `mdKind`**：cacheText(A) ≠ B → 回填 cacheText=B、kind、直清 blocks=[]——**done 仍为 true**（毒化点）。
4. kind(B) ≠ "none" → MdPreviewView body 调 `mdBlocks`：cacheText(B) == text 且 done == true → **命中返回空数组 []**。
5. 自持：唯一能复位 done 的是 `mdBlocks` 自身的解析回填支，而毒化态恰好短路该支；其后每次「改文→失焦」都经同一 `mdKind` 路径再次毒化。恢复只靠 BlockState 重建（重开备忘 / 撤销快照）。

渲染序的确定性：MdPreviewView 只能由行分支在 `mdKind` 返回非 "none" 后创建，`mdKind` 恒先于 `mdBlocks` 执行——E3 假设的「先调 mdKind 再调 mdBlocks」不是可能序，而是唯一序。

### 1.3 用户可见形态

不是空白块：MdPreviewView 有 D-R1 原文兜底（:13506，解析为空时显原文）。故形态为——**曾渲染过预览的 MD 段落，被点开编辑一次、改文失焦后，预览退化为原文直显**（标题显字面 `# `、列表显字面 `- ` 等，callout 字号纯文本），且本会话内对该块恒不恢复，直到重开备忘。兜底把故障伪装成「源码呈现」，这解释了它为何未以数据丢失形态被报告。

## 2. 根治：失效单点收口

- `BlockState` 新增失效单点 `invalidateMdCache()`（MomentApp.swift:96）：清 `mdCacheBlocks` 与复位 `mdCacheDone` 同点完成；字段注释钉不变量「mdCacheDone == true ⟹ mdCacheBlocks 是 mdCacheText 的解析树；一切失效只许经此函数」。
- `mdKind` 的文本变更支改为先调 `block.invalidateMdCache()` 再回填 text/kind，散点直清删除。
- `mdBlocks` 的命中/回填口径一字未动（填充半边与命中凭据成对，本就自洽）。
- 收敛性核查：改后全仓对两字段的写只剩三处合法形态——失效单点（清树+复位）、`mdBlocks` 回填（树+置 done）、字段声明初值；无第四处。

## 3. 断言（verify [35]，本机自跑全绿）

- MD35-1：`invalidateMdCache` 定义恰 1 处，函数体内清树与复位 done 两写齐备。
- MD35-2：`mdKind` 段内含单点调用且无散点直清；全文件经 `block.` 的散点直清/直复位计数为 0（锁死将来再添散点失效即红）。
- MD35-3：`mdBlocks` 命中凭 done、回填置 done 的口径在位（不变量消费半边防漂移）。

全量 verify 本机结果：[35] 三条全 ✓；其余红 5 条逐条归属如下，均非本批——① ipa 陈旧、② 产物语言包不一致（产物类，tree 构建自解，此前各批同记）；③ [9] 五语键数（期望 367 / 现行 zh-CN 实数 370——lang 五包正被在途二维码批加键中，本批未碰 lang）；④ B16-15、⑤ B25-10（桥清单三方同步——M3a/续连批在途落码中，本批未碰桥文件）。

## 4. 并发账

动工前快照：HEAD 6ce6cd8，在途 diff 7338 行。目标区在 HEAD 坐标（字段 84-89、mdKind/mdBlocks 5683-5712）与全部在途 hunk 零交叠（最近 hunk 在旧行 5575 插入与 5888 起）。落码期间树仍在动（Web 兼容批、二维码批、M3a 等持续落码，MomentApp.swift/verify 的 hunk 总数在本人两笔之外继续增长）——本批两文件的落点以 [35] 三条断言实测在位为据；编辑区段的其余 verify 组（[24]-[34]）全绿，无本批引起的回潮。

## 5. 真机终判点

1. 主判：打开一篇含 MD 段落的备忘（预览呈渲染态）→ 点段落改几个字 → 点别处失焦 → 预览应仍为**渲染态**（非原文直显）；同块再重复一轮编辑→失焦，仍渲染态。
2. 旁证：改文使段落不再是 MD（如删掉 `#`）→ 失焦后呈普通段落原文（正常口径，非兜底伪装）；再改回 MD → 预览恢复渲染。
3. 恢复面回归：毒化形态在旧版可经「重开备忘」恢复——新版不应再需要此路（第 1 条恒成立即为关闭证据）。
