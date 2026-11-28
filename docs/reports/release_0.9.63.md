# 组版报告 0.9.63（build 90）

2026-11-28 组版。基线 b7d330e（0.9.62 发布笔）→ 本版 15 笔（13 批逐批成笔 + 组版收敛 1 + 组版修复 1）+ 本 release 笔（与版本号 bump 同笔，CI 不变量 WORKFLOW §3.2）。本版主线：状态栏动态识别三轮收口、全面审计裁定项清账（B-02/B-05/C-02/A-08）、设置族顶距与页面框单点化、配对去 Safari、实况按功能样式设计；Web 同批上线（构建戳 d85900ea57 → 9b2efd68ee）。

## 一、本版内容（按提交序）

| # | 提交 | 内容 | 定案 |
|---|---|---|---|
| 1 | 5e61357 | 状态栏字色二轮+三轮根治：感知明度换 CIELAB L* 阈值 61.65（白字对比度 3.0 ⇔ Y=0.30 推导）；全页面统一带区渲染采样单点 BandRenderSampler（新文件 MomentStatusBarRender.swift），登记静态色降首帧兜底、图片页特路与开屏公式色并入单点，模式层为底、动态识别为增强层；开屏独立承载 MomentSplashHost.swift + iPhone 竖屏方向锁（idiom 闸、iPad 守卫 SB-8） | fix_statusbar_dynamic.md + fix_statusbar_render_sample.md |
| 2 | c08e4f6 | 标题胶囊对齐 Web（AUD-B-02）+ 预览态居中：双侧对位 19 项唯一真偏离（宽度公式漏边框项）改 +41；预览态偏心根因（截断覆盖层缺字形居中指令）一行根治 + 定宽公式下沉纯核心 TitleCapsuleLayout，T24-8/T24-9 机制与量测锁 | fix_title_capsule_web_align.md + fix_title_capsule_center.md |
| 3 | 834c971 | MCP 配对去 Safari、改 App 内确认：中继加 JSON 确认通道（与表单通道同一 DO 校验单点，RELAY_VERSION 1.1.0）；App 内 scopes 勾选 + 确认钮 + 一次性密钥卡（仅内存、零落盘）；i18n 429→438 | fix_bridge_pairing_inapp.md |
| 4 | 7011c83 | AUD-C-02 诊断/日志页纳入 720 收窄：收窄钳抽单点 wideNarrowClamp()，DiagView 改调 settingsContentFrame，DiagLogPage 终端卡共用钳；新增 [56] DG56 | fix_diag_pages_narrow.md |
| 5 | d7539fb | AUD-A-08 首页首组头间距动态适应：firstGroupTopInset(b) = max(28 − b, 3) 单点，四态间隔构造性恒 ≥28、常态逐值零变化；新增 [57] HG57 量测锁 | fix_home_header_gap_adaptive.md |
| 6 | 1eab306 | 全页面内容框对齐盘点与收敛锁 [61] PF61：14 面盘点，应接入 8 页已全在 settingsContentFrame 单点、零未对齐页，本批为全集锁定防回潮（原编 [58] 与 FD58 撞号、组版顺延 [61]） | fix_page_frame_align_all.md |
| 7 | baf935e | AUD-B-05 前向删除块末合并（原生+Web 两端）：原生全块型矩阵 + 双触发面斜杠守卫 + 每路径恰一撤销单元；Web 回源原无此行为同批补齐（merge_forward_core 纯核心，9 例测试含全量文档相等锁）；[58] FD58 + verify_rustweb §18 | fix_forward_delete_merge.md |
| 8 | f91331e | 日志页导出改 46×46 圆玻璃图标钮（与返回钮成对、无障碍读名保留）+ 终端卡改经 settingsContentFrame 单点（量测三法互证数值本同、差在来源）；新增 [59] DL59 | fix_diaglog_header_spacing.md |
| 9 | 5b9f090 | 权限页 UIUX 调优：补图标列、已授权状态色改走 T.success 令牌、有动作行整行成钮（rowAction 单点）、动作胶囊降噪；新增 [60] PU60 | fix_permissions_uiux.md |
| 10 | d27174e | 头像恐龙圆内构图按参考图精测调整：构图常数单点（宽 0.698D 基准、纵向为唯一病灶——顶距 0.214D→贴合参考、底边贴圆下缘裁切）；圆框本体与调用点零改动；F30-24 数值复算锁 | fix_avatar_dino_position.md |
| 11 | 79aa4e5 | 设置族顶距 126→81（用户裁定：以其上滑 ≈45pt 截图位置为标准）：settingsContentFrame 单点一处值变更，9 消费面自动跟随，内容顶 185→140 与截图逐值一致；图片页自持 126 分叉登记 | fix_frame_top_inset_81.md |
| 12 | 68aa6bd | Web 全页面内容框对齐 + 顶距改判：图片页横向内距自持归零回 .page-content 单点（contain 公式未动）；顶距改 calc(env(safe-area-inset-top) + 81px)，页头底边→内容顶间隙任意设备恒 28 与原生同锚；verify_rustweb §19 | fix_web_page_frame_align.md + fix_web_frame_top_inset.md |
| 13 | 81b0c27 | 实况按功能样式设计：样式单点 LiveOpStyle（五 kind 专属图标+主题色、phase 参与渲染、minimal 改 kind/阶段图标）；灵动岛展开三区成卡治长黑条；桥会话与一次性操作分形态；i18n 438→441；[62] LV62。引擎与属性契约零 diff | impl_liveops_design.md |
| 14 | 8f91fc7 | 组版收敛：SB-2 ok 文案随 L* 口径同步（分拣漏网一行，组版累计等值核对捕获） | — |
| 15 | 936bc46 | 组版修复：实况 keylineTint 类型归属纠正（tree 首轮冒烟构建实证，详见 §二） | impl_liveops_design.md 组版附记 |

## 二、组版收敛项（逐项办结登记）

- **累计等值核对**：`git diff b7d330e` 限定原 32 个已跟踪文件，与组版前全量工作树 diff 逐字一致（delta 0 行）；分拣漏网一行（SB-2 文案）由该核对捕获、独立成笔 8f91fc7。
- **组号撞号顺延**：全页面框锁原编 [58] 与前向删除 FD58 撞号，顺延定号 [61] PF61 并在两处注沿革。
- **tree 首轮冒烟 [3/4] 构建红 → 组版修复笔**：`DynamicIsland has no member 'liveOpsKeylineTint'`。定性（proven，SDK .swiftinterface 实证）：keylineTint 是 DynamicIsland 结构体自有方法（iOS 16.1+）、非 View 修饰符，批 13 误包 View 扩展。删扩展、调用点改 `.keylineTint(tint)` 直调；activityBackgroundTint（View 扩展、iOS 16.0+）的 16.2 守卫属保守写法保留。教训：WidgetKit 修饰符先查归属类型（View / DynamicIsland / ActivityConfiguration 不互通）。
- **tree 第二轮冒烟 verify 独红 SB-1/SB-6 → 克隆卫生**：本机同断言全绿。定性（proven，目录清单 diff）：tree 克隆 app 目录残留已删文件 MomentStatusBarImage.swift，其 evaluateLightness 旧符号触发零残留普查。删除残留后第三轮全绿。注：该文件不在构建名单内、ipa 产物不受影响；克隆为目录拷贝同步、删文件须显式清理，已记入本节防再犯。
- **本机 verify 基线口径**：组版前本机 590 ✓ / 2 ✗，两红为产物面（[5] ipa 陈旧、[9] 产物语言包 md5），tree 全量重建归零（592 ✓），与任务定性一致。另有一红 B25-10 经定性为从仓库根误跑 verify 的调用产物（断言以 $0 相对读自身），非代码漂移。

## 三、验证

- **tree 冒烟（出包门）**：smoke_ios.sh 四阶全量三轮——首轮 [3/4] 构建红（keyline，见 §二）、次轮 verify 红 2（克隆残留，见 §二）、第三轮 **SMOKE ALL GREEN（verify 592 ✓ / 0 ✗，cargo test 全仓 + FFI 重建 + 构建 + verify）**。
- **ipa 产物复验**：Moment-0.9.63.ipa，**11,848,230 B，md5 2c15c19774f3b024c689036813d3e150**（取包远端/本地 md5 一致）；Info.plist 版本 0.9.63 / build 90 / com.canopies.moment；**PlugIns 不存在**（去捆绑维持）；macho-entitle validate OK（签名在 __LINKEDIT 内、页哈希与 special slots 一致）；macho-entitle 工具本机/tree 双边 md5 同为 c2cf6bb7118512690c7692e0cc31014f；包内 weather-keys.json 在位、双 key 指纹与现网一致（和风 63f146dc / 彩云 c0716145，只记指纹）。
- **中继**：bridge/relay 经 deploy.py 部署，`GET /health` = version **1.1.0**（部署先于 App 侧依赖，表单通道逐字不变、二维码通道保留）。
- **Web 生产部署（与原生分别留账）**：tree 构建（MOMENT_SQLITE=1，与现网同口径）戳 d85900ea57 → **9b2efd68ee**（wasm 4,210,674 B）；verify_rustweb 全过（含新 §18 前向删除、§19 页框锁）；干净 dist 归档至 releases/9b2efd68ee；staging 注入天气双 key（指纹与部署前现网逐一一致）；deploy_api.py 部署至 canopies-moment（部署 URL 45bceaff.canopies-moment.pages.dev）；**verify_live 首跑 LIVE == ARCHIVE**；tree 探针 smoke-rustweb-visual 对生产全过（ERRORS: none）。
- **CI**：本报告与 bump 同笔推送后，workflow moment-rust-web.yml 九步以全绿为完成判据，结果登记于组版回报（报告不再为此二次改动，以免破坏同笔不变量）；红先定性、不改判。

## 四、真机终判点（汇全，归用户装机后验）

1. **状态栏三轮（fix_statusbar_render_sample.md §九）**：全页面（首页/设置族/编辑/图片/救援/开屏）深浅底面上字色随带区实渲染动态识别——深底白字、浅底黑字，滚动/切页即时跟随、无闩锁残留；开屏期间字色与品牌渐变带区匹配。
2. **八色深形态白字目检（沿革项）**：L* 口径下备忘八色深形态（L* 49.5–56.1）由黑字改判白字，装机逐色目检可读性。
3. **开屏方向锁**：iPhone 开屏恒竖屏（横持启动不旋转）；iPad 不受影响（守卫结构不可达，目检确认无回归即可）。
4. **图片页采样**：图片页滚动时状态栏字色随图面覆盖带区变化（Diag src/cov 可佐证）；图片页 Web 侧可用区观感（横向内距收敛后 contain 区宽 −40px 的呈现）。
5. **标题胶囊**：长标题预览态省略号居中（meta 越宽原偏越大的形态重点看）；点按落点与全文映射不回归。遗留决胜点（点按恰在省略号正中落第 10 字 vs 文末）仍待用户裁，未裁前保持文末口径。
6. **前向删除 B-05**：块末 Delete 跨块合并全块型手感（原子后继只选中不删、列表取首项）、撤销单步回退完整；Web 端同行为。
7. **顶距/页框**：设置族各页内容顶距新标准（上滑 ≈45pt 位置感）；诊断/日志页宽屏收窄居中；日志页导出图标钮可发现性。
8. **A-08**：首页横幅/通知在位时首组头视觉间隔不低于常态、无挤压感。
9. **权限页**：图标列与状态色分组观感（已授权绿、受阻 warning），整行点按触发动作。
10. **恐龙构图**：默认头像恐龙在圆内位置（底边贴圆下缘、可见中心下移）与参考图观感一致。
11. **配对去 Safari**：桥设置页内完成 scopes 勾选 + 确认 + 密钥卡复制，全程不跳 Safari；旧配对/二维码通道不受影响（中继 1.1.0 已上线）。
12. **实况样式 7 条——等 appex 回归终判**：本版样式已落码并随扩展源码构建，但 0.9.61 起 appex 去捆绑、扩展本体不在包内，灵动岛/锁屏呈现（含长黑条是否被新三区卡替换）须待 appex 回归（个人 Developer 账号 profile 覆盖双 id）后逐条终判，本版不作已验表述：① 五 kind 图标+主题色区分；② phase 色彩/字形（done 绿勾、failed 红叹、waiting 灰暂停）；③ minimal 区 kind/阶段图标（非无色圆点）；④ 展开三区成卡（徽章+标题/计数/步名+进度）；⑤ keyline 随阶段色；⑥ 锁屏卡 kind 色淡染；⑦ 桥会话形态（无进度条、状态词+指纹短记）与一次性操作形态分工。

## 五、证据分级与遗留

- proven：提交链与累计等值核对（delta 0）；tree 冒烟第三轮 ALL GREEN 592 ✓；ipa 产物六项复验；中继 /health 1.1.0；Web LIVE == ARCHIVE + 探针全过；keyline 定性（SDK 接口原文）；克隆残留定性（目录 diff）。
- inferred：无（本版构建/部署面均有直接判读）。
- unknown（真机终判域）：§四全部条目——触摸投递、像素栅格化、视觉观感类按既有口径永远归真机终判，报告不升级表述。
- 遗留结转：全面审计批 3（媒体解码收口，GIF 块内静止待真机定性）、批 6（首页细项 + 账本回写）未派；批 4 随 E5/E6、批 5 = I4/I5；0.9.62 装机终判余项（XSel 两期、图片卡复现路径等）与 S1 自检两遍重跑、M3b 写景验收仍在装后桥自办队列；标题点按省略号正中决胜点待用户裁；appex/iCloud/APNs 同等个人 Developer 账号一次办齐。
