#!/usr/bin/env python3
"""SQLite 阶段二演练夹具生成：生产形态 IDB 存量 + 备份包。

产出（tools/sqlite_bench/fixture/）：
- memos.json     —— IDB kv `memos_json` 原文：300 篇、约
  5 MB；含两篇旧形态（整数毫秒时间戳、callout kind 别名），
  供迁移归一计数对账；一篇含全文检索唯一词「鹭江夜泊」。
- manifest.json  —— IDB kv `manifest_raw` 原文：2 个附件条目。
- att-1.bin / att-2.bin —— IDB attachments 店字节。
- real_backup.zip —— 同内容备份包（memos.json + manifest.json
  + attachments/<id>），供 Worker bench_import_zip 实测。

用法：python3 gen_fixture.py
"""
import io
import json
import pathlib
import zipfile

OUT = pathlib.Path(__file__).parent / "fixture"
OUT.mkdir(exist_ok=True)

BODY = (
    "江畔的灯火在雾里散开，潮声把白昼的喧哗一层层洗淡。"
    "这一篇记录迁移演练的存量形态：段落、标题与列表交错，"
    "只为让归一通道与全文索引都有真实的活儿可干。"
)

memos = []
for i in range(300):
    day = 1 + (i % 27)
    ts = f"2026-01-{day:02d}T08:{i % 60:02d}:00.000Z"
    doc = [
        {"type": "heading", "attrs": {"level": 2},
         "children": [{"text": f"演练存量第 {i} 篇"}]},
    ]
    for p in range(12):
        text = BODY * 6
        if i == 137 and p == 3:
            text += "鹭江夜泊，唯一检索词在此篇。"
        doc.append({"type": "paragraph",
                    "children": [{"text": text}]})
    memos.append({
        "id": f"fixture-{i:03d}",
        "title": f"演练存量 {i}",
        "createdAt": ts,
        "updatedAt": ts,
        "doc": doc,
    })

# 旧形态一：整数毫秒时间戳（归一 ts_int_to_iso）。
memos.append({
    "id": "fixture-legacy-ts",
    "title": "旧形态时间戳",
    "createdAt": 1795494731533,
    "updatedAt": 1795494731533,
    "doc": [{"type": "paragraph", "children": [{"text": "整数时间戳存量。"}]}],
})
# 旧形态二：callout 变体别名 kind（归一 normalize_callout）。
memos.append({
    "id": "fixture-legacy-callout",
    "title": "旧形态标注",
    "createdAt": "2026-01-05T09:00:00.000Z",
    "updatedAt": "2026-01-05T09:00:00.000Z",
    "doc": [{"type": "callout", "attrs": {"kind": "warning"},
             "children": [{"text": "别名变体存量。"}]}],
})

memos_json = json.dumps({"version": 2, "memos": memos}, ensure_ascii=False)
manifest = {
    "version": 1,
    "attachments": {
        "att-1": {"name": "fixture-a.png", "type": "image/png"},
        "att-2": {"name": "fixture-b.pdf", "type": "application/pdf"},
    },
}
manifest_json = json.dumps(manifest, ensure_ascii=False)
att1 = bytes(range(256)) * 16
att2 = b"%PDF-1.4 fixture" * 128

(OUT / "memos.json").write_text(memos_json, encoding="utf-8")
(OUT / "manifest.json").write_text(manifest_json, encoding="utf-8")
(OUT / "att-1.bin").write_bytes(att1)
(OUT / "att-2.bin").write_bytes(att2)
with zipfile.ZipFile(OUT / "real_backup.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("memos.json", memos_json)
    z.writestr("manifest.json", manifest_json)
    z.writestr("attachments/att-1", att1)
    z.writestr("attachments/att-2", att2)

print(f"memos={len(memos)} memos_json={len(memos_json.encode())}B "
      f"zip={(OUT / 'real_backup.zip').stat().st_size}B")
