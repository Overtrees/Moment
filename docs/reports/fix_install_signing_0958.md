# fix_install_signing_0958 — 0.9.58 起签名后装不上根治

用户实报：0.9.57 签名后安装正常，0.9.58 / 0.9.59 签名后装不上，证书没问题。
用户重签流程会原样保留二进制内嵌签名集（build-app2.sh 注释有据），故我方
交付的签名面即最终签名面——签名面坏，装机必拒。

## 一、取证（主线取证 + 本批独立复现，数字逐一对齐）

样本 = 已交付 ipa 解包产物（/tmp/ipa57、/tmp/ipa58、/tmp/ipa59），页哈希按
codeLimit 裁剪口径逐页核对，签名区与 __LINKEDIT 区间对账：

| 样本 | 坏页（LC 所在页） | 签名末端 − __LINKEDIT 末端 | nSpecial |
|---|---|---|---|
| 0.9.57 主程序（lld 原生、未过 entitle） | 无（0 坏） | 0 B | 0 |
| 0.9.58 主程序 | 页 1（LC cmd_off=7272） | **+481 B** | 7 |
| 0.9.58 appex | 页 0（LC cmd_off=3920） | **+424 B** | 7 |
| 0.9.59 主程序 | 页 1 | **+481 B** | 7 |
| 0.9.59 appex | 页 0 | **+424 B** | 7 |

两处结构性损坏，均出自 macho-entitle（~/workspace/ios-tools/macho_entitle.py）
的 embed()，0.9.58 权限批引入 entitlements 嵌入起每版皆然：

- **① 页哈希失效恰一页**：embed() 在 LC_CODE_SIGNATURE 所在页内改写 LC
  datasize 后从未重算该页哈希，CodeDirectory 自此不自洽。57 的同页因 lld
  出厂即终值而相符，是现成对照。
- **② __LINKEDIT 不覆盖签名区**：embed() 把新 superblob 截旧附尾、文件变长，
  却未同步 __LINKEDIT 的 filesz/vmsize。超出的 481/424 B 恰含 CD 尾部与整个
  entitlements blob——签名结构非法，AMFI 口径下不成立。

量测口径缺陷与代码缺陷同源：工具自带 verify 只查 slot-5 哈希（自己写自己
读），①②两面全不在检查面内，构建门禁因此全程绿灯放行坏件。

次生缺陷：appex 的 Info.plist 是静态文件 MomentLiveOpsWidget-Info.plist 整拷
（build-app2.sh），版本冻在 0.9.57/84，与主程序自 0.9.58/85 起逐版脱钩。

## 二、修法（根源治理）

1. **macho_entitle.py embed()**：组装 out 后先把全部头部改写落定——LC
   datasize 更新、__LINKEDIT filesz/vmsize 同增 delta（= 新签名长 − 旧签名
   长）；再对「与原文件相比字节有变的代码页」逐页按 codeLimit 裁剪重算哈希、
   回写新 CD 对应槽。页集由 diff 通用得出，不点名任何页（LC 页、__LINKEDIT
   命令页同理覆盖）；重复 embed（已 entitled 再嵌）路径同样成立。
2. **macho_entitle.py 新增 validate 子命令**（AMFI 口径全量校验，任一不过
   exit 3 并逐项点名）：superblob magic/总长与 LC datasize 一致；签名区整体
   落在 __LINKEDIT 内；全部代码页哈希（codeLimit 裁剪）相符并点名坏页；
   blob 不越 superblob、CD 长度字段与 blob 一致、nCodeSlots 与
   ceil(codeLimit/pageSize) 自洽、哈希区不越 CD；给 --info 时 slot-1 ==
   Info.plist 哈希；slot-5 == entitlements 整 blob 哈希（非零槽无 blob 判
   红）；slot-7 DER 同口径。embed() 收尾自调 validate，不过即失败退出
   （工具层自检，不只靠构建脚本）。旧 verify 保留为弱口径兼容子命令。
3. **build-app2.sh**：主程序与 appex 在 entitle 后各加一道显式 validate
   硬门（set -e，失败即停构建）；appex plist 版本同步——拷入后以刚生成的
   主程序 Info.plist 为单源回写 CFBundleShortVersionString/CFBundleVersion
   两键（plistlib），且同步在 embed --info 之前（slot-1 哈希的是同步后
   plist）。
4. **verify_ios.sh [49] 组**（SG49-1..3）：锁工具 validate 存在且 embed 自
   调、build 两处 validate 门、appex 版本同步步骤在位。

## 三、回归实证（全量输出要点）

旧工具以本批开工时通读的原文逐字重建于 /tmp 备复现（ios-tools 非 git 仓）。

**① 复现坏件**：旧工具对 0.9.57 主程序副本 embed（旧 verify 照旧绿灯、
exit 0），新 validate 恰旗出两缺陷、exit 3：

```
FAIL signature [18677152, 18823681) not inside __LINKEDIT [10010624, 18823200)
FAIL page hash mismatch at slots [1] (1 bad)
```

签名增长 146048 → 146529（+481 B），与已交付 0.9.58 的取证数字分毫不差。

**② 新工具同副本**：embed exit 0（内含自调 validate 通过），显式 validate
再过；read 回读 XML 与源 Moment.entitlements 逐字一致；已 entitled 再嵌
（重复 embed）validate 仍过。独立取证脚本复核产物：签名末端 − __LINKEDIT
末端 = 0 B、坏页 0、__LINKEDIT filesz 恰增 481 B（8812576 → 8813057）。

**③ 真件判红**：对已交付 58/59 原件（只读）跑 validate，主程序与 appex
四件全判红，缺陷点名与取证表逐一对应（58 主：超出 + 页 1；58 appex：超出
+ 页 0；59 同型）。

**④ 好件不误伤**：对 0.9.57 原件跑 validate 全过（OK，exit 0）。

**⑤ appex 版本同步单测**：静态 plist 副本（0.9.57/84）经构建同款同步段后
回读 = 0.9.59/86，与主程序一致，CFBundleIdentifier 等其余键无损。

**⑥ 门禁**：verify_ios.sh 全量 517 ✓ / 2 ✗，[49] 三条全绿；2 红为既有产物
陈旧项（ipa 早于源码、产物语言包未重建），与本批无关、重建即消。

## 四、证据分级

- 两处签名面缺陷的存在与成因：**proven**（三版样本数字复现 + 旧工具在好件
  副本上确定性复现坏件、新工具同副本全过）。
- 「装不上」的归因：以版本边界（57 正常 / 58、59 装不上，恰与 entitle 引入
  版对齐）+ 保留式重签使我方签名面即最终签名面 + 缺陷面恰为 AMFI 校验面
  为据，归因成立；**最终终判仍归用户装机**——待 0.9.60 组版出包后由用户按
  原流程签名安装确认。
- tree 上的工具副本（~/ios-native/bin/macho-entitle）本批未动，由 0.9.60
  组版批同步新版工具后再出包；本批不提交、不 bump、不出包。
