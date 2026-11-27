# E1 编辑回路根治批报告

依据：docs/reports/audit_editor_deep.md 域一（编辑回路）——F-01 组字守卫、F-02 智能前缀、F-08 段首原子前驱退格、M-01 斜杠触发面、M-02 粘贴块型守卫、m-01 标题 Esc 组字守卫，及主线追加定案项 M-06。

批次状态：M-06 专节先行落（纯定案、无落码，见下）。其余条目的落码受硬门约束（0.9.57 组版提交全落定且工作树净）；截至本节写入时 HEAD = 6ce6cd8（0.9.57 分拣链末笔），工作树有并行批在途未提交（救援完整性 / 配对二维码 / 文字大小等，MomentApp.swift 56 个 hunk 在途），门未过，其余章节待落码后补齐。

---

## M-06 代码块 Enter 语义定案（主线追加项）

### 审计口径

audit_editor_deep.md M-06（形态级，证据等级 inferred）：原生 codeBlock 内 Enter 放行块内换行；审计疑 Web 模型层为拆块口径——推论依据是 ops.rs `op_split` 的通用路径对未列名块型一律拆出 paragraph 新块，codeBlock 未见特例。

### 回源定案：Web 为块内换行，原生现状即达标（proven，双侧源码行级）

**1. Web 的 Enter 分流在 JS 桥先行完成，split op 根本不到达 codeBlock。**

- `rust/apps/web/src/editor/js/editor.js:890-905`：keydown 处理对 `codeBlock`/`mdsrc` 设独立分支，注释明言「md 源码/代码块（编辑态审计 B11）：回车仍是块内换行放行原生」；该分支仅拦截段首（caret offset 0）的 Backspace 发 `merge` op，其余按键（含 Enter）不 preventDefault、直接 return，Enter 由浏览器原生在块内插入换行。
- 通用 Enter → `split` 分支在 `editor.js:906` 之后，codeBlock 永不到达。
- `rust/apps/web/src/editor/ops.rs:325` 的 `op_split` 确无 codeBlock 特例：heading/callout 有整段保留 + 插空段特例、todo/quote 有空块退出特例、其余走通用拆分（新块型 list-item/todo/quote 同型、余皆 paragraph）。但 dispatch 的 `"split"` 分支只转发桥消息，桥从不为 codeBlock 的 Enter 发 split——该通用路径对 codeBlock 不可达。审计的「拆块」推论是只读模型层、漏读桥分流的结果，就此推翻。
- 旁证同向：粘贴路径 `editor.js:1803、1814` 把 codeBlock 与 mdsrc 同组——多行粘贴不走 `pasteText` 拆块、留在块内；输入同步面 `collectInputSyncMap` 只排除 mdsrc/musicInput，codeBlock 全文（含 `\n`）经 inputSync 整块同步，模型以单块多行文本持有代码块。

**2. 原生现状逐项对齐。**

- `rust/apps/ios/app/MomentApp.swift:2995-2996`（Coordinator `shouldChangeTextIn`）：替换文本含 `\n` 时 codeBlock 支 `return true`（注释「代码块内换行是正文」），放行 UITextView 在块内插入换行——与 Web 同口径。
- 段首退格：原生同函数段首支对 codeBlock（`isText` 含 codeBlock）走 `mergeBlockBackward`，与 Web codeBlock 段首 Backspace 发 `merge` 同口径（其原子前驱等细目属 F-08 本批范围，本节不展开）。

### 处置

**M-06 关闭：Web 为块内换行口径，原生现状即达标，无落码、无断言新增。** 审计 inferred 项按源码定案销账，后续审计不再重复列报。

证据上限：本节为代码级 proven（双侧分流点行级对读）；行为未发生任何变更，不新增真机终判点，codeBlock 编辑体验随 E1 批其余条目的真机终判一并观察即可。
