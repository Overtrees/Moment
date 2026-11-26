#!/usr/bin/env python3
"""跨块编辑语义夹具：合并光标口径 / 跨块选区 / 段首退格跨原子块。

XB合并：三组相邻段落，依次退格合并——
  甲乙😀 + 丙丁（星光平面 emoji 在前块末尾：标量 3 / UTF-16 4）
  café连 + 后续（é = e + U+0301 组合字符：标量 6 / UTF-16 6，对照组）
  末𐮷 + 合体（𐮷 = U+20BB7 星光平面汉字：标量 2 / UTF-16 3）
XB选区 / XB选区二：三段纯文本，供拖选/Shift 选/编程式选区后退格与打字替换。
XB原子甲：[图][段]；乙：[段][图][段]；丙：[图][空段]；丁：[段][图][空段]。
"""

import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
import base64
import json
import zipfile


def D(day):
    return f"2026-11-{day:02d}T10:00:00+08:00"


def para(bid, text):
    return {"id": bid, "type": "paragraph", "children": [{"text": text}]}


def img(bid):
    return {"id": bid, "type": "image", "attrs": {"fileId": "attimg1"},
            "children": [{"text": ""}]}


def memo(mid, title, doc, ts):
    return {"id": mid, "title": title, "doc": doc, "pinned": False,
            "createdAt": ts, "updatedAt": ts}


PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
)

memos = [
    memo("xb-merge", "XB合并", [
        para("xm1", "甲乙😀"),
        para("xm2", "丙丁"),
        para("xm3", "café连"),
        para("xm4", "后续"),
        para("xm5", "末\U00020bb7"),
        para("xm6", "合体"),
    ], D(21)),
    memo("xb-sel", "XB选区", [
        para("xs1", "第一段文字"),
        para("xs2", "第二段文字"),
        para("xs3", "第三段文字"),
    ], D(20)),
    memo("xb-sel2", "XB选区二", [
        para("xt1", "第一段文字"),
        para("xt2", "第二段文字"),
        para("xt3", "第三段文字"),
    ], D(19)),
    memo("xb-atom-a", "XB原子甲", [
        img("xa1"),
        para("xa2", "图后段落"),
    ], D(18)),
    memo("xb-atom-b", "XB原子乙", [
        para("xb1", "前段文字"),
        img("xb2"),
        para("xb3", "后段文字"),
    ], D(17)),
    memo("xb-atom-c", "XB原子丙", [
        img("xc1"),
        para("xc2", ""),
    ], D(16)),
    memo("xb-atom-d", "XB原子丁", [
        para("xd1", "前段文字"),
        img("xd2"),
        para("xd3", ""),
    ], D(15)),
]

manifest = {
    "version": 1,
    "attachments": {
        "attimg1": {"name": "dot.png", "type": "image/png", "size": len(PNG)},
    },
}

with zipfile.ZipFile("fixtures/xblock.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr(
        "memos.json",
        json.dumps(
            {"version": 2, "exportedAt": D(21), "memos": memos, "avatars": {}},
            ensure_ascii=False,
        ),
    )
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
    z.writestr("attachments/attimg1", PNG)
print("fixtures/xblock.zip written")
