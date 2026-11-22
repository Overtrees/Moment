#!/usr/bin/env python3
"""S3 行内口径夹具：一篇备忘三块，覆盖编辑对接线后的归一与往返。

甲（s3b1）：存量 bool 标记多子节点段（粗/粗斜/斜/删/码 + 链接
节点），打开编辑并保存后应归一为字面单文本节点。
乙（s3b2）：字面标记段（粗/斜/高亮），预览→源码编辑往返后
模型逐字不变。
丙（s3b3）：下划线 bool 段（编辑口径的唯一元素承载），往返后
下划线仍为 underline 节点、纯文本不变。
"""
import json
import zipfile

TS = "2026-11-21T10:00:00+08:00"

memo = {
    "id": "s3-test",
    "title": "S3行内口径",
    "pinned": False,
    "createdAt": TS,
    "updatedAt": TS,
    "doc": [
        {
            "id": "s3b1",
            "type": "paragraph",
            "children": [
                {"text": "甲"},
                {"text": "粗", "bold": True},
                {"text": "粗斜", "bold": True, "italic": True},
                {"text": "斜", "italic": True},
                {"text": "删", "strikethrough": True},
                {"text": "码", "code": True},
                {
                    "type": "link",
                    "url": "https://example.com",
                    "children": [{"text": "链"}],
                },
                {"text": "尾"},
            ],
        },
        {
            "id": "s3b2",
            "type": "paragraph",
            "children": [{"text": "**粗字** 与 *斜字* 与 ==高亮== 尾"}],
        },
        {
            "id": "s3b3",
            "type": "paragraph",
            "children": [
                {"text": "下划", "underline": True},
                {"text": "普通"},
            ],
        },
    ],
}

with zipfile.ZipFile("fixtures/s3-inline.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr(
        "memos.json",
        json.dumps(
            {"version": 2, "exportedAt": TS, "memos": [memo], "avatars": {}},
            ensure_ascii=False,
        ),
    )
    z.writestr(
        "manifest.json",
        json.dumps({"version": 1, "attachments": {}}, ensure_ascii=False),
    )
print("fixtures/s3-inline.zip written")
