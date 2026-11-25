# 测试夹具说明

## sample_memos.json / sample_flutter_memos.json / sample_manifest.json

迁移通道的回归语料（T-3，见仓库根 `refactor_remove_compat.md` §3.3）。

- **来源**：由 2026-11-19 真机互通验收的两份真实备份（原版导出
  `real_backup.zip` 与 Flutter 版导出 `flutter_export.zip`，现仅存
  仓库外 `mynote-zip-acceptance/`）中的 memos.json / manifest.json
  结构派生。两份样本的差异仅在 exportedAt，脱敏后保留此差异。
- **脱敏口径**（结构保留、内容替换）：
  - 保留：全部键与结构、块类型与顺序、id（备忘/块/附件）、
    时间戳、exportedAt、pinned、attachment 节点的顶层 fileId /
    status / image、manifest 条数与 type、文件名重复模式。
  - 替换：备忘标题改为构造标题（样本图片备忘 / 样本文本备忘）；
    doc 内一切行内 text 改为编号构造样本句（空串保持空串）；
    avatars 的 data URI（原为真实头像照片）改为 1x1 PNG 占位
    data URI；manifest 文件名按首次出现序改为
    sample-photo-NN.<原扩展名>，同名同映射、重复模式保留。
  - 结果：单份 memos 由约 5.4MB 降至约 7.7KB，真实笔记内容与
    真实图片数据零残留（校验：标题原文、IMG_ 文件名、JPEG
    base64 特征串均不出现）。
- **用途**：`tests/roundtrip.rs` 以「旧夹具 → 迁移通道归一 →
  内容/结构等价于期望原生形」口径断言；`tests/migrate.rs` 的
  存量扫描以块类型普查引用。原真实夹具（real_*.json /
  flutter_*.json，含真实内容）已随 T-3 落地移出仓库。

## 其余夹具

仓库根 `fixtures/` 下的 stock_oldform_persisted.json 等为浏览器
探针夹具，与本目录无关。
