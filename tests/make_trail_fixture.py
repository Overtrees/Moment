#!/usr/bin/env python3
"""尾随空段夹具：六篇备忘覆盖尾随空段的全部产生位置。

甲：文末是块级 md 预览（代码围栏）→ 预览后需尾随段（文末）
乙：块级预览 → 图片（原子块）→ 普通段 → 预览与图片之间需尾随段
丙：文末是分割线（原子块）→ 原版 init 以 trail_ 形态推入模型
丁：表格预览 → 列表组 → 预览与列表组之间需尾随段
戊：两相邻预览 → 之间不补、文末补（确定性规则对照）
己：预览 → 普通段（对照组：不补）
"""

import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
import base64
import json
import zipfile

def D(day):
    return f"2026-11-{day:02d}T10:00:00+08:00"


TS = D(20)
TS2 = D(21)


def para(bid, text):
    return {"id": bid, "type": "paragraph", "children": [{"text": text}]}


def memo(mid, title, doc, ts=TS):
    return {
        "id": mid,
        "title": title,
        "doc": doc,
        "pinned": False,
        "createdAt": ts,
        "updatedAt": ts,
    }


# 1x1 透明 PNG
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
)

memos = [
    memo("trail-a", "尾随甲", [
        para("ta1", "甲首段文字。"),
        para("ta2", "```js\nconst a = 1;\n```"),
    ]),
    memo("trail-b", "尾随乙", [
        para("tb1", "```\nplain code\n```"),
        {"id": "tb2", "type": "image", "attrs": {"fileId": "attimg1"},
         "children": [{"text": ""}]},
        para("tb3", "乙尾段文字。"),
    ], D(21)),
    memo("trail-c", "尾随丙", [
        para("tc1", "丙首段文字。"),
        {"id": "tc2", "type": "divider"},
    ], D(19)),
    memo("trail-d", "尾随丁", [
        para("td1", "| 列一 | 列二 |\n| --- | --- |\n| 甲 | 乙 |"),
        para("td2", "- 列表项一"),
        para("td3", "- 列表项二"),
    ], D(17)),
    memo("trail-e", "尾随戊", [
        para("te1", "```\nfirst\n```"),
        para("te2", "```\nsecond\n```"),
    ], D(18)),
    memo("trail-f", "尾随己", [
        para("tf1", "```\nmid code\n```"),
        para("tf2", "己尾段普通文字。"),
    ], D(16)),
    memo("trail-g", "尾随庚", [
        para("tg1", "庚首段文字。"),
        {"id": "tg2", "type": "image", "attrs": {"fileId": "attimg1"},
         "children": [{"text": ""}]},
    ], D(15)),
]

manifest = {
    "version": 1,
    "attachments": {
        "attimg1": {"name": "dot.png", "type": "image/png", "size": len(PNG)},
    },
}

with zipfile.ZipFile("fixtures/trail.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr(
        "memos.json",
        json.dumps(
            {"version": 2, "exportedAt": TS2, "memos": memos, "avatars": {}},
            ensure_ascii=False,
        ),
    )
    z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
    z.writestr("attachments/attimg1", PNG)
print("fixtures/trail.zip written")
