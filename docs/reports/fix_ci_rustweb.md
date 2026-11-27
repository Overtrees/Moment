# CI moment-rust-web 持续红：诊断与根治（2026-11-27）

## 结论先行

「持续红」不是单一故障，是两段性质完全不同的红，混在
失败邮件里看成了一片：

1. **僵尸键段（真实缺陷，门禁立功，已关账）**：2026-11-27
   凌晨至上午的一串红（3248def…8a6cadb、4070d70）全部挂在
   `verify rustweb` 步，报错为 i18n 僵尸键（引用面零命中
   的语言键）。这是门禁抓到的真实缺陷，已由 6fe5ef0
   （CI 僵尸键修复）根治，其后 f629be0 起多轮转绿实证。
2. **release 一致性段（流程时序问题，本报告根治）**：
   801a605、a76196e、80a6cc9 三笔挂在 `verify docs` 步，
   报错恒为同一句——现行版本的 release 报告缺失。根因
   是组版提交顺序与文档门禁 D4 的判定时机相撞（见下），
   属门禁接线/流程类问题，非代码缺陷。当前 HEAD
   f0e55f1 的树内 D4 已满足（本机 `scripts/verify_docs.sh`
   实跑 exit 0），红只出现在组版中间笔上。

当前 HEAD f0e55f1 本身没有 CI run：该笔只动
docs/reports，不在 workflow 的 paths 触发面内，属未触发
而非失败。本报告的修复笔触及 `scripts/verify_docs.sh`
（在触发面内），其 run 即 HEAD 全量判绿的实证（结论见
文末回填）。

## 证据（全部 proven，取自 GitHub API 的 runs/jobs/日志原文）

| run | 提交 | 结论 | 失败 step | 日志报错原文（摘） |
|---|---|---|---|---|
| 45929385246 | 3248def | failure | verify rustweb | 僵尸键 bridge.scope_ops / bridge.scope_write / bridge.state_backoff 等 |
| 45947189758 | 8a6cadb | failure | verify rustweb | 同上（该段最后一红，其后转绿） |
| 45982038679 | 4070d70（0.9.58 bump） | failure | verify rustweb | 僵尸键 bridge.pair_expired |
| 45996807545 | 801a605（门禁接线笔） | failure | verify docs | release 一致性：`release_0.9.59.md` 缺失 |
| 46012711922 | a76196e（0.9.61 bump） | failure | verify docs | release 一致性：`release_0.9.61.md` 缺失 |
| 46024269499 | 80a6cc9（0.9.62 bump） | failure | verify docs | release 一致性：`release_0.9.62.md` 缺失 |
| 46017033229 | b682d02 | success | — | 报告已在树内（7104ce4 先行），全绿 |

每轮失败 job 恒为 test-build-verify、约 1 分钟挂，与
失败邮件口径一致；cargo test / build web dist 两步在
上述所有 run 中均为 success——代码与构建从未红过，
红的只有两个静态门禁步。

## 根因（release 一致性段）

`scripts/verify_docs.sh` 的 D4 判的是**同一棵树**内：
现行版本（`rust/apps/ios/app/build-app2.sh` 的
CFBundleShortVersionString）的 release 报告必须存在。
而组版惯例顺序是：各批提交 → bump 笔（改版本号）→
tree 构建冒烟 → release 报告笔（报告须含冒烟结果与
ipa 对账，只能最后写）。于是 bump 笔落地的那棵树必然
「版本已新、报告未至」，D4 必红；报告笔落地后又因只
动 docs 不触发 workflow，连「转绿的 run」都不会产生，
失败邮件就成了每版留给外界的最后印象。801a605 同理：
门禁接线笔落地时 0.9.59 的 bump 已先行、报告未至，
门禁上线第一笔即被自己的 D4 判红。

定性：(a) CI 环境/门禁接线问题——准确说是**流程时序**
问题。门禁本身判得对（发布完成的树就该版本与报告
并存），错的是提交顺序让中间态冒充了发布态受检。

## 根治（不降门禁、不删断言，D4 逻辑一字未动）

改的是流程，把不变量写进两处活文档：

1. `docs/WORKFLOW.md` §3.2 新增「提交顺序（CI 不变量）」：
   bump 先只在工作树内改供构建/冒烟，**bump 的提交必须
   与该版 release 报告同笔落**。
2. `scripts/verify_docs.sh` 头注在 D4 条目下补同一不变量
   与三版实证指针（指向本报告），让下一个改门禁的人
   先看到这条约束。

这样每一笔落地的树都自洽：要么版本未动、旧报告在位；
要么版本与新报告同笔到位。不存在需要 D4 放水的中间
态，门禁强度不变。

## 后续注意

- 0.9.63 起组版按新顺序执行；若再现 release 一致性红，
  先查是否有人把 bump 单独成笔，不要怀疑 D4。
- 僵尸键段提醒仍在：verify_rustweb 的僵尸键检查是真
  抓过缺陷的门禁，其红一律按真实缺陷处理，不与本报告
  的时序红混为一谈。

## 新 run 结论（回填）

（待修复笔推送后回填 run 号与结论。）
