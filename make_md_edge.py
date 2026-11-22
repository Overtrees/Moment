#!/usr/bin/env python3
"""生成 Markdown 边缘语料测试备份 ZIP（冻结格式）：17 段 e01–e17
与斜杠/Markdown 审计（audit_slash_md_report.md §二）的语料一一
对应，供 smoke-rustweb-blocks 的 e 批断言导入。e03 在审计报告
中未单独描述，此处定为无语言围栏（与 e01 带语言形对照）。"""
import json, zipfile, sys

def T(text):
    return {"text": text}

def P(bid, text):
    return {"id": bid, "type": "paragraph", "children": [T(text)]}

doc = [
    P("e01", "```js\nconst x = 1;\n```"),
    P("e02", "~~~\nlet y = 2;\n~~~"),
    P("e03", "```\nplain code\n```"),
    P("e04", "> [!TIP]-\n> 折叠提示正文"),
    P("e05", "# 标题行\n后面一行正文"),
    P("e06", "前一行\n- 列表项\n- 第二项"),
    P("e07", "- 含 **粗** 与 `代码` 和 [链接](https://example.com) 的项\n- 第二项"),
    P("e08", "| 列一 | 列二 |\n| --- | --- |\n| **粗** | `代码` |"),
    P("e09", "这是 **粗体** 和 *斜体* 与 ~~删除~~ 和 `代码` 以及 [外链](https://example.com) 混合"),
    P("e10", "- [ ] 未完任务\n- [x] 已完任务"),
    P("e11", "2. 第二项\n3. 第三项"),
    P("e12", "正文带脚注[^a]\n[^a]: 脚注内容"),
    P("e13", "公式 x^2^ 与水 H~(2)~O"),
    P("e14", "参见 [[目标笔记|显示名]]"),
    P("e15", "***"),
    P("e16", "文字上\n---\n文字下"),
    P("e17", "```\n未闭合代码"),
]

memo = {
    "id": "mdedge1",
    "title": "md边缘",
    "doc": doc,
    "pinned": False,
    "createdAt": "2026-11-21T03:00:00.000Z",
    "updatedAt": "2026-11-21T03:00:00.000Z",
}
target = {
    "id": "mdtarget1",
    "title": "目标笔记",
    "doc": [P("t01", "被引用的目标笔记正文。")],
    "pinned": False,
    "createdAt": "2026-11-21T03:00:00.000Z",
    "updatedAt": "2026-11-21T03:00:00.000Z",
}
memos_json = {"version": 2, "exportedAt": "2026-11-21T03:00:00.000Z", "memos": [memo, target], "avatars": {}}
manifest = {"version": 1, "attachments": {}}

out = sys.argv[1] if len(sys.argv) > 1 else 'fixtures/md-edge.zip'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('memos.json', json.dumps(memos_json, ensure_ascii=False))
    z.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False))
print('wrote', out)
