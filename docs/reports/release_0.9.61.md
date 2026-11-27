# 0.9.61 组版报告（装机修复过渡版 + 跨块选区两期）

版本 0.9.61 / build 88；基线 0be6c1d（0.9.60）。本版双主题：① 0.9.58–0.9.60 签名后装不上的过渡处置——交付包不再捆绑小组件扩展（根治线另行推进，见 diag_appex_install.md）；② 跨块选区桥接层一期 + 二期落码。

## 一、提交清单（0be6c1d..HEAD）

| 笔 | 内容 | 文件 |
|---|---|---|
| b7a211c | 跨块选区一期 + 二期 | MomentXSel.swift / MomentXSelBridge.swift（新）、MomentApp.swift、build-app2.sh、verify_ios.sh、覆盖矩阵、impl_cross_block_selection_p1/p2.md（8 件） |
| 07ed649 | 装机根治过渡处置 | build-app2.sh、verify_ios.sh、fix_install_signing_0958.md 附记（3 件） |
| a76196e | bump 0.9.61 / build 88 | build-app2.sh（plist 两串）、MomentApp.swift（设置页版本串） |
| 本笔 | 本报告 | docs/reports/release_0.9.61.md |

## 二、内容摘要

**跨块选区两期**（细节见 impl_cross_block_selection_p1.md / p2.md）：纯核心 MomentXSel.swift（XSelCore，与 Web 多宿主虚拟选区同构）+ 桥接层 MomentXSelBridge.swift（replaceRangeUnits 双路径逐支移植 Web ops.rs）；一期 = 跨块全选动作面 + 跨块替换（单个撤销步）+ 守卫；二期 = Shift+方向扩展（字符/行/段内分段着色走 textStorage 属性层）。verify [50] X50-1..7、[51] X51-1..5，核心表驱动 25 + 33 项全过。矩阵行 EDT-55（编号纠错：一期建议的 EDT-15 已被块拆分/合并占用）。

**装机根治过渡处置**（定案与沿革见 fix_install_signing_0958.md 附记）：用户二分实测消去法闭合——VC（无 appex + 无 entitlements）可装、VA（无 appex + 有 entitlements）可装、VB（有 appex + 无 entitlements）不可装、原版不可装，真阻因 = 包内 PlugIns/MomentLiveOpsWidget.appex 本体。build-app2.sh 新增显式开关 `BUNDLE_WIDGET_EXT=0` 门控拷入段（appex 仍编译 + check-macho 防代码腐烂）；封包前硬断言：开关关时 $APP/PlugIns 在场即停。verify 新增 [52] INS52-1..3；既有 B34-5、SG49-2、SG49-3 按新口径逐条改判并注沿革（锁编译接线与步骤在位、不再锁入包事实），未整组删。实况小组件 UI 自始未真正到过用户手上（≤0.9.57 的交付包本就无 PlugIns），去捆绑无功能回退。

## 三、同步与冒烟

- push_small 名单补 MomentXSel.swift / MomentXSelBridge.swift 后全量同步，逐件 md5 对账全合；共享文件以 git HEAD 提取件为准入克隆——rust/apps/web/src/editor/ops.rs 同步的是 HEAD 版，Web 边角洞批的工作树版本在同步窗口后已恢复原样（窗口内无人并发改动，恢复后 md5 与窗口前一致）。
- tree smoke_ios.sh 一轮 **ALL GREEN**：cargo test --workspace 全过 → FFI 静态库重建 → 构建（日志含 `widget extension compiled + checked only, NOT bundled`、无 FATAL，封包断言实走通过）→ verify **534 ✓ / 0 ✗**。本机同版 verify 532 ✓ / 2 ✗，两红均为陈旧产物类（ipa 未更新 + 产物语言包），tree 新产物下归零。

## 四、产物级复验（本机解最终 ipa 实测，不引构建日志）

- `Payload/Moment.app/PlugIns` **不存在**（app 目录清单逐项核对）。
- Info.plist：版本 **0.9.61 / build 88**，bundle id com.canopies.moment。
- 主二进制 macho-entitle validate（AMFI 口径）：**OK**。
- 独立解析器复算：代码槽 5117、**坏页 0**；签名末端 − __LINKEDIT 末端 = **0 B**；superblob 总长 == LC_CODE_SIGNATURE datasize。
- ipa：`Moment-0.9.61.ipa`，**11,670,302 B**，md5 **ada9ac3da820ae4a82d30b3f0a67e38b**（tree 远端与本机落地两侧一致）。

## 五、前置门与排除项

- FFI 前置门：`git diff 0be6c1d..HEAD -- rust/crates/ffi/` 零行，导出面（含文档注释）未动，无需重生 bindings。
- Web 边角洞批（并行在途、未提交）逐件排除于本版提交与同步、原样留置工作树：TESTING.md、rust/apps/web/src/editor.rs、editor/model.rs、editor/ops.rs、scripts/verify_rustweb.sh、tests/probe_slash_anchor.mjs、docs/reports/fix_web_xsel_edge.md；crates/core 的 model.rs / ops.rs 工作树 diff 同属该批，存在属预期。

## 六、终判点

1. **用户装机确认（第一位）**——0.9.58–0.9.60 三版签名后拒装之后的首个去捆绑交付包。
2. XSel 两期真机点：一期 §六 8 点 + 二期 §六 8 点（见两 impl 报告）。
3. 装后走桥自办全集：S1 title_capsule_reedit 两遍（BRG-09 关闭证据）、M3b 写景验收、实况保活量测三档、undo_redo_roundtrip 桥实跑、在席工具抽验、§6.8 回归子集余项。
4. appex 根治线另行推进（diag_appex_install.md）：判别变体装测与通道结论收口后，后续版本把小组件带回且可装。
