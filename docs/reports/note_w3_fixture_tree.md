# w3 真实备份夹具迁 tree — 完工记录

- 日期：2026-11-27。出处：impl_web_block_compat.md「待办」①——真实备份夹具未迁 tree，smoke-rustweb-w3 第 6 步在 tree 只能缺席跳过；迁入后自动恢复严格跑。本单已关闭。

## 定位结果

- 夹具口径（脚本原文）：`tests/smoke-rustweb-w3.mjs:142,154` 读 `$HOME/workspace/moment-zip-acceptance/real_backup.zip`，缺席时打印 `⊘ step 6 skipped` 并跳过第 6 步。
- 本机在位：`~/workspace/moment-zip-acceptance/real_backup.zip`，12,344,339 B。该目录在仓库之外（与 ~/workspace/Moment 同级），夹具不入仓、不受 git 跟踪；tree 侧落点同为克隆外（/data/home/workspace/…），口径一致。

## 传输与校验

- 通道：既有 tree-sync 通道（push_small.py 的 push_file 机制）——base64 分片 30,000 字符/次经 custom.instabox-tree 连接器 exec 逐片追加、逐片尺寸核对，终点解码后 md5 对账。
- 过程留痕：首轮传至第 231/549 片时本机服务重启、进程中断；按远端 .b64 尺寸（片对齐）断点续传剩余 318 片，全程无尺寸发散。
- 对账：本机与 tree 两侧 md5 均为 `bb0a4f6db36e8f141500e344d83ea446`，字节数 12,344,339 一致。
- 数据红线：全程机器间直传与哈希校验，未打开内容、未复制到其他位置。

## tree 实跑结果（第 6 步由跳过变实跑通过）

- 环境：tree 克隆 /opt/work/Moment（HEAD 9c73f6c），tools/serve_headers.py 起 :8096 服务 rust/apps/web/dist，tests 下 node smoke-rustweb-w3.mjs（tree Chromium 口径）。
- 结果：全量 20 项断言 ✓、ERRORS: none。关键证据——日志中**无** `⊘ step 6 skipped` 行，且第 6 步专属断言实跑通过：`✓ delete button not resident`、`WRAPS: 1 -> 0`、`✓ delete block`、`✓ delete persists after reload`（导入真实备份 → 打开图片备忘 → 浮层菜单删块 → 重载持久校验全链）。
- 收尾：实跑用的 :8096 服务已停，tree 恢复原状；夹具留置 /data/home/workspace/moment-zip-acceptance/real_backup.zip，后续 w3 在 tree 运行时第 6 步恒严格全跑。
