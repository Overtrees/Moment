#!/usr/bin/env python3
"""生成双栏混排验收备份 ZIP（冻结格式）：卡片+长文本+图片+链接卡
+待办+列表源+代码+分割线+公式+附件混排一篇，供双栏成员稳定性
探针（probe_twocol_mix.mjs）导入。

语料设计（栏归属对度量敏感）：
- tc01 音乐卡（规范高 120 / 字数权重 12）
- tc02–tc04、tc06、tc08 各 200 字长段（规范高 153 / 字数权重 200）
- tc05 图片（规范高 280 / 字数权重 12）
- tc07 链接卡（120 / 12）、tc09 待办、tc10–tc11 列表源段、
  tc12 代码源段、tc13 分割线、tc14 公式段、tc15 附件（120 / 12）
按原版 editorBlockHeight 规范回退表（图片 280、卡片 120、文本
28+ceil(字数/44)*25）算出的最优分界 = tc06 起右栏（左 tc01–tc05）；
按旧字数权重分界 = tc05 起右栏。两者在 tc05（图片）上分歧，
且在 tc08 追加 300 字后旧分界会再漂移到 tc07 起右栏——探针据此
坐实「按字数重算的分界随编辑漂移、回来再进来跳栏」。
"""
import json, zipfile, sys

def T(text):
    return {"text": text}

def P(bid, text):
    return {"id": bid, "type": "paragraph", "children": [T(text)]}

def pad200(s):
    # 补到 200 字（中文标点计入），保证两套度量口径稳定
    while len(s) < 200:
        s += "补充文字用来占满这一段的篇幅，让栏高估算与字数权重产生可测差异。"
    return s[:200]

doc = [
    {"id": "tc01", "type": "musicCard", "url": "https://music.163.com/song?id=1",
     "status": "ready", "meta": {"title": "测试歌曲名", "cover": ""},
     "children": [T("")]},
    P("tc02", pad200("左栏第一段长文本，紧跟音乐卡之后输入的普通文字。")),
    P("tc03", pad200("左栏第二段长文本，继续在卡片下方累积的内容段落。")),
    P("tc04", pad200("左栏第三段长文本，混排场景里靠前的普通文本段落。")),
    {"id": "tc05", "type": "image", "attrs": {"fileId": "tcimg01"},
     "children": [T("")]},
    P("tc06", pad200("图片之后的第一段长文本，分界预期从这里开始右栏。")),
    {"id": "tc07", "type": "link-card", "url": "https://example.com/article",
     "status": "ready",
     "meta": {"title": "示例文章标题", "description": "链接卡描述文字。",
              "siteName": "example.com", "image": ""},
     "children": [T("")]},
    P("tc08", pad200("右栏长文本段落，探针会在这一段末尾追加三百字验证漂移。")),
    {"id": "tc09", "type": "todo", "attrs": {"checked": False},
     "children": [T("双栏待办事项")]},
    P("tc10", "- [ ] 列表任务一"),
    P("tc11", "- [x] 列表任务二"),
    P("tc12", "```rust\nfn main() { println!(\"hi\"); }\n```"),
    {"id": "tc13", "type": "divider", "children": [T("")]},
    P("tc14", "公式 $E=mc^2$ 混排收尾段"),
    {"id": "tc15", "type": "attachment", "attrs": {"fileId": "tcpdf01"},
     "children": [T("")]},
]

memo = {
    "id": "twocolmix1",
    "title": "双栏混排",
    "doc": doc,
    "pinned": False,
    "createdAt": "2026-11-22T01:00:00.000Z",
    "updatedAt": "2026-11-22T01:00:00.000Z",
}
memos_json = {"version": 2, "exportedAt": "2026-11-22T01:00:00.000Z",
              "memos": [memo], "avatars": {}}
manifest = {"version": 1, "attachments": {
    "tcimg01": {"name": "twocol-photo.jpg", "type": "image/jpeg"},
    "tcpdf01": {"name": "双栏文档.pdf", "type": "application/pdf"},
}}

# 图片字节借用 mix-layout 夹具的实拍图
src = zipfile.ZipFile('fixtures/mix-layout.zip')
img_bytes = src.read('attachments/miximg01')
pdf_bytes = b"%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF"

out = sys.argv[1] if len(sys.argv) > 1 else 'fixtures/twocol-mix.zip'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('memos.json', json.dumps(memos_json, ensure_ascii=False))
    z.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False))
    z.writestr('attachments/tcimg01', img_bytes)
    z.writestr('attachments/tcpdf01', pdf_bytes)
print('wrote', out)
