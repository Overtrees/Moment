#!/usr/bin/env python3
"""生成全块类型测试备份 ZIP（冻结格式），供原版与 Rust 版同数据导入比对。"""
import json, zipfile, io, sys

src = zipfile.ZipFile('/home/hatch/workspace/mynote-zip-acceptance/real_backup.zip')
man = json.loads(src.read('manifest.json'))
att_ids = list(man['attachments'].keys())
img1, img2, img3 = att_ids[0], att_ids[1], att_ids[2]
bytes1 = src.read(f'attachments/{img1}')
bytes2 = src.read(f'attachments/{img2}')
bytes3 = src.read(f'attachments/{img3}')

def T(text, **marks):
    d = {"text": text}
    d.update(marks)
    return d

def P(bid, children, **extra):
    d = {"id": bid, "type": "paragraph", "children": children}
    d.update(extra)
    return d

doc = [
    P("b01", [T("普通段落：行内样式混合 —— "), T("粗体", bold=True), T("、"), T("斜体", italic=True), T("、"), T("下划线", underline=True), T("、"), T("删除线", strikethrough=True), T("、"), T("代码", code=True), T("、"), T("==高亮段=="), T("、链接：") , {"text": "示例站点", "type": "link", "url": "https://example.com", "children": [{"text": "示例站点"}]}]),
    {"id": "b02", "type": "heading", "attrs": {"level": 1}, "children": [T("一级标题")]},
    {"id": "b03", "type": "heading", "attrs": {"level": 2}, "children": [T("二级标题")]},
    {"id": "b04", "type": "heading", "attrs": {"level": 3}, "children": [T("三级标题")]},
    {"id": "b05", "type": "quote", "children": [T("引用块：被引用的文字内容，看看左侧竖线与底色。")]},
    {"id": "b06", "type": "todo", "attrs": {"checked": False}, "children": [T("未完成待办")]},
    {"id": "b07", "type": "todo", "attrs": {"checked": True}, "children": [T("已完成待办")]},
    {"id": "b08", "type": "divider"},
    P("b09", [T("> [!NOTE]\n> 注释类标注块正文。")]),
    P("b10", [T("> [!WARNING]\n> 警告类标注块正文。")]),
    P("b11", [T("> [!TIP]\n> 提示类标注块正文。")]),
    P("b12", [T("```\nfn main() {\n    println!(\"hello\");\n}\n```")]),
    P("b13", [T("- 无序项一\n- 无序项二")]),
    P("b14", [T("1. 有序项一\n2. 有序项二\n3. 有序项三")]),
    {"id": "b15", "type": "image", "attrs": {"fileId": img1}, "children": [T("")]},
    {"id": "b16", "type": "gallery", "attrs": {"items": [img2, img3]}, "children": [T("")]},
    {"id": "b16c", "type": "imgTextCard", "attrs": {"fileId": img3}, "children": [T("图文卡片的文字部分")]},
    {"id": "b16d", "type": "imageTextRow", "attrs": {"fileId": img1}, "children": [T("图文混排的说明文字")]},
    {"id": "b17", "type": "musicCard", "url": "https://music.163.com/song?id=1", "status": "ready", "meta": {"title": "测试歌曲名", "cover": ""}, "children": [T("")]},
    {"id": "b18", "type": "link-card", "url": "https://example.com/article", "status": "ready", "meta": {"title": "示例文章标题", "description": "这是一段链接描述文字，用来核对卡片排版。", "siteName": "example.com", "image": ""}, "children": [T("")]},
    {"id": "b19", "type": "attachment", "fileId": "testpdf1", "status": "done", "image": False, "children": [T("")]},
    {"id": "b20", "type": "attachment", "fileId": img2, "status": "done", "image": True, "children": [T("")]},
    P("b21", [T("结尾段落。")]),
]

memo = {
    "id": "allblocks1",
    "title": "全块渲染测试",
    "doc": doc,
    "pinned": False,
    "createdAt": "2026-11-21T02:00:00.000Z",
    "updatedAt": "2026-11-21T02:00:00.000Z",
}
memos_json = {"version": 2, "exportedAt": "2026-11-21T02:00:00.000Z", "memos": [memo], "avatars": {}}
manifest = {"version": 1, "attachments": {
    img1: man['attachments'][img1],
    img2: man['attachments'][img2],
    img3: man['attachments'][img3],
    "testpdf1": {"name": "测试文档.pdf", "type": "application/pdf"},
}}

out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/allblocks.zip'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('memos.json', json.dumps(memos_json, ensure_ascii=False))
    z.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False))
    z.writestr(f'attachments/{img1}', bytes1)
    z.writestr(f'attachments/{img2}', bytes2)
    z.writestr(f'attachments/{img3}', bytes3)
    z.writestr('attachments/testpdf1', b'%PDF-1.4 test bytes')
print('wrote', out)
