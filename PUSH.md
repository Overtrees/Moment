# GitHub 推送流程（一次性 PAT，批 13 P-D9 固化）

仓库在 Overtrees 名下，日常推送走「一次性个人访问令牌」通道：
令牌只用于当次推送，用后即毁，不落盘、不入库、不进日志。
每批落码在部署核对后即推送，不攒批（P-D9 立规矩的背景：
曾积压多笔、远端长期停在更早批次）。

## 流程

1. **用户给令牌文件**：用户把令牌写入 `~/workspace/user/files/1.txt`
   后告知推送。令牌形态为 GitHub PAT（前缀 `ghp_`）。
2. **shell 内提取，不读入上下文**：只在 shell 里用模式匹配把
   令牌取进变量，禁止把文件内容读进对话/日志/提交信息：

   ```bash
   TOKEN=$(grep -o 'ghp_[A-Za-z0-9]*' ~/workspace/user/files/1.txt | head -1)
   ```

3. **推送**（远端 URL 不落令牌，令牌只出现在进程参数里）：

   ```bash
   cd ~/workspace/Moment
   git push "https://$TOKEN@github.com/Overtrees/Moment.git" main
   ```

   输出回显前先过滤令牌形态（如 `sed -E 's/ghp_[A-Za-z0-9]+/ghp_***/g'`），
   防止令牌随命令输出进入任何记录。
4. **核对**：`git ls-remote` 查远端 main 的哈希，必须与本地
   `git rev-parse HEAD` 完全一致才算推送完成：

   ```bash
   git ls-remote "https://$TOKEN@github.com/Overtrees/Moment.git" main
   ```

5. **销毁**：推送与核对完成后立即粉碎令牌文件，不留副本：

   ```bash
   shred -u ~/workspace/user/files/1.txt
   ```

## 红线

- 令牌不得写入仓库任何文件（含本文档）、提交信息、脚本或记忆；
  本文档只写流程与占位描述，不写任何真实令牌示例。
- 令牌不得改作他用（不调其他 API、不做验证之外的操作）。
- 推送失败先报告失败原因与远端现状，不换通道重试、不自行
  生成新令牌。
