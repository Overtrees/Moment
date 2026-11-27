# E3 批 listStart 类型错误修复

- 时点：2026-11-27。诊断出处：impl_media_enhance.md「他批在途问题（转主线）」节。
- 范围：只动 MomentApp.swift 一处表达式，语义等价、不改行为；未提交、未 bump。

## 病灶与根因

`listStart(of:)`（E3 批 F-05 的 start 三助手之一）原写：

```swift
let s = (list.node["attrs"] as? [String: Any])?
    ["start"] as? Int ?? 1
```

同型表达式 `(x as? [String: Any])?["k"] as? T` 在本文件多处在位且一直可编译（120、127、1898、7399、12154、12715、16246 行）——差别只在本处：**换行落在链式 `?` 与下标 `[` 之间**，是全文件唯一一处此种断行。解析器据此把 `["start"]` 当作独立的数组字面表达式处理，`let s` 被推成字典型，其后大片级联 error 均为伪影（媒体批在 /tmp 副本中和后全消，本批复证同）。

## 改法（按媒体批示例，两步拆解）

```swift
let attrs = list.node["attrs"] as? [String: Any]
let s = attrs?["start"] as? Int ?? 1
```

与文件内既有先例同形（122–124 行 imageURL 即两步式）。`guard` 与 `s >= 1 ? s : 1` 钳制原样，行为零变更。

## 同型排查

- `setListStart(_:_:)`：`var attrs = n["attrs"] as? [String: Any] ?? [:]`——普通转型 + nil 合并，无链式下标衔接，无此问题。
- `shiftListStart(_:by:)`：无 `as?`，只调用另两助手，无此问题。
- E3 批其余新增 `as?` 表达式逐条过：均为 `as? T ?? 默认值` 直式或 `)?[` 同行式（如 7399 行 `($0 as? [String: Any])?["segs"]` 跨行断在下标之后），无同型断行。
- 全文件复扫 `)?` 行尾 → 次行 `[` 开头的序列：修复后 **零处**。

## 编译验证

以 build-app2.sh 现行工作树版本的 app.o 遍原样旗标（swift-frontend -frontend -c、MomentApp.swift 为 primary-file、其余 19 文件为次级输入、COMMON 原样，非 -parse）全量类型检查：

- **listStart 本体与级联 error 全消**；E3 领地（转换/列表区）零 error。
- 全文件余 11 条真 error，**全部属同期在途兄弟批领地，未代修**：
  - 8 条在文字大小（Dynamic Type）批领地：设置/导出视图的缩放字号变量 `f9/f11/f18/f19/f22` 找不到定义（11597、11689×2、11704、11749、18218），及同区 11678 的 Button 重载对（同视图标签类型检查失败的级联嫌疑）——该批落码进行中，定义侧未就位。
  - 2 条在天气 key 设置 `commit(_:)`（19082/19083，raw/cleaned 声明前使用）——编译期间该区正被编辑，行号已漂移。
  - 1 条在图片页 displayName（19448，fid 找不到）。
- 注记：编译在活树上进行（多批并发编辑中），上述行号为编译时点快照；归属按代码领地判，与本批改动零交集。本机内存挤压下该遍一次 SIGBUS、重试后完整跑完（诊断页脚齐全、非中断）。
