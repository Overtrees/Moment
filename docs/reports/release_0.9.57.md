# 0.9.57 组版报告（救援布防 + 桥稳定性 + 0.9.56 回归三线 + 圆角收口 + 天气副标题 + 首页卡间距）

> 基线 HEAD fdb1a67（0.9.56）。本版共十一笔：分拣八笔 + bump 一笔 + 卡间距追加笔一笔 + 本报告一笔。U4a 五景不在本版（其代理已停门回报、设计蓝图齐备，组版后另行重派）。

## 一、提交分拣（归属逐 hunk 核对）

分拣法：动工前快照全树 diff（113,463 B），按 change-group 粒度以标记词分类 + 补丁级暂存逐批提交；混合 hunk（worker.js 首 hunk、MomentApp 设置段两处、verify 的 B16-17|18/19 与 F30-9|F30-10..12|[31] 连排块）均在组内切分、无整文件一锅烩。分拣后对账：分拣前 diff 的全部 +/- 行在已提交区间内逐行多重集比对，**pre-only = 0**（无一行丢失或重复入册）。

| 笔 | 提交 | 内容 |
|---|---|---|
| 1 | 1e0878b | 救援布防 rescue_arm_safe_mode 整环入册（impl_rescue_arm.md） |
| 2 | 62800f7 | 桥稳定性全面根治·App 侧与中继入册（fix_bridge_stability.md） |
| 3 | e2b4dc8 | 回归·搜索胶囊点不了（fix_search_tap_dead.md） |
| 4 | a02f926 | 回归·标题胶囊竖排渲染异常（fix_title_vertical_render.md） |
| 5 | 6a551ee | 回归·完成胶囊不回缩（fix_donecapsule_retract.md） |
| 6 | 6e56ddd | 天气副标题五语（fix_weather_subtitle_i18n.md） |
| 7 | aff7fd7 | 圆角收口 R1+R2（impl_radius_consolidation.md + plan_dynamic_radius.md） |
| 8 | 4fa8e33 | 文档册：plan_selftest_coverage.md |
| 9 | 477b1bc | bump 0.9.57 / build 84 |
| 10 | 6ce6cd8 | 首页卡间距根治·追加分拣笔（fix_home_card_spacing.md，见第三节时序） |
| 11 | 本笔 | 本组版报告 |

## 二、本版各批要点（细节见各批报告）

- **救援布防**：写入方（BridgeSafeModeArmStore，diag 域双文件 + ops 两段提交/幂等管线）+ 启动判定第三路消费（take 先删后判防循环）+ 清单 31 件三方同步入册；安全模式受限集不收、无远程解除。
- **桥稳定性**：App 侧传输层代次作用域、前台 5s 探活、NWPathMonitor 路径看门狗、退避重置、生命周期打点；中继侧选连 epoch/新鲜度、pending 按连接隔离、webSocketError 处理器、等设备 4s 窗、alarm 僵尸回收。中继与连接器已由该批先行部署/生效，本版为入册 + 复核（见第五节）。
- **回归三线**（0.9.56 真机实报）：搜索 = 分支条件即焦点本身的自指涉结构 → 字段常驻 + activateSearch 具名入口；标题竖排 = representable 缺 sizeThatFits、竖排灵活行吞余高 → 补尺寸契约 + 占位色复刻；完成胶囊 = kbVisible 由 safeBottom 边沿派生、静息 34 闩锁为真 → 改键盘通知单点喂入。三批断言均已改写到机制层。
- **圆角收口**：Radius 扩表四枚（panel/panelHero/panelS/controlS），59 处收口数值零变更；底表手搓对改走 overlayCard、描边归一 strokeBorder；R3 贴边面政策指针入注释。
- **天气副标题**：新键 settings.weather_sub 五语同步（zh-CN 定案「天气数据源令牌配置」），旧键 weather_status 与主页状态合成机器（weatherMeta/weatherSourceWord）退役零残留，共享语言包每包键数 360 守恒。
- **首页卡间距**（追加笔）：C-A3 图/文分隔行与 emptyRow 未声明 listRowInsets、静默继承系统默认 insets（纵向 ≈32），图/文交界实测 72pt vs 账面/Web 真值 40；规则收敛为全 List 行显式声明、零默认依赖，F30-13 计数相等锁 + F30-14 合成值锚。

## 三、版本 bump 与卡间距追加笔时序（如实记录）

- bump（477b1bc）：build-app2.sh 内嵌 CFBundleShortVersionString 0.9.57 / CFBundleVersion 84 + MomentApp 设置页版本串，与前版同位置。
- 卡间距批在 bump 落定、工作树净后按门落码，落在首轮 tree 同步之后：**首轮冒烟（/data/home/smoke57-run1-tree.log）不含此批**，verify 277 ✓ ALL PASS；追加笔 6ce6cd8 提交并补推后重新同步（MomentApp.swift md5 d3ef3ccb、verify_ios.sh md5 b1c15ea2 与本地逐一对账），**第二轮冒烟全量重跑**（/data/home/smoke57-tree.log）verify **279 ✓ / 0 ✗**（较首轮 +2 即 F30-13/F30-14）ALL PASS、SMOKE ALL GREEN。**本版交付 ipa 出自第二轮，含全部十一笔内容**，提交记录与包内容一致、无静默差。

## 四、tree 冒烟（smoke_ios.sh 全量）

- 流程：push_small.py 同步（传输名单先核——本波全部改动文件含 tests/title_tap_caret_main.swift 与 worker.js 均在名单内，md5 逐个对账）→ overlay 覆盖 tree 克隆 → setsid nohup 跑 smoke_ios.sh（cargo test 全仓 → FFI 重建 → 构建 → verify）。
- 结论：**第二轮 ALL GREEN**（verify 279 ✓ / 0 ✗，三十一组全过，含新组 [31] R31-1..9 与 B16-17/18/19、F30-13/14）。

## 五、中继复核（入册后对账，本版无新部署）

- 经 Cloudflare API 下载线上脚本：仓库 bridge/relay/worker.js（47,337 B，md5 2430b93f…）在线上 multipart 内容中**逐字节原文在位**。
- 线上 list-tools 回 **31 件**（含 rescue_arm_safe_mode）。
- manifestHash 按公式 sha256("2025-06-18|" + 31 名排序连接）重算 = `a52116c38d2f70966de8de41df102a5aab10a38c87e3dbd7e64ce229eafc6da9`，与 0.9.56 基线一致、**零漂移**。

## 六、取包

- ~/workspace/your_files/Moment-0.9.57.ipa：**11,037,930 B**，md5 `9aed16e1cf34d55453a4ca60b4667c42`（tree 远端与本地回读一致）。版本 0.9.57 / build 84。

## 七、CI（未认证 API 核）

- bump 提交 477b1bc：moment-rust-web **success**。
- 追加笔 6ce6cd8：moment-rust-web **success**（run #22）。

## 八、出包回归子集（覆盖矩阵 §6.8 新规·本版选取记录）

本版子集 = **S1 + 冷启健康 + 三方哈希对账 + scopes 抽样 + 本版所动模块行**：

- S1：九步场景真机首跑两遍（终态码优先级 restore_failed > hygiene_failed > aborted_user_active > run_timeout > step_failed > ok；两遍一致才算终判，仍为 U2 开工门 BRG-09）。
- 冷启健康：SMOKE 冷启行 + LAUNCH 正常收尾判定。
- 三方哈希对账：App BPROTO / 中继 TOOLS / 连接器 ALLOWED_TOOLS 清单 31 件与 manifestHash a52116c3…（组版时已在第五节先行复核，装后再抽一次）。
- scopes 抽样：在席四工具（editor_open/get_state/focus_block/save_now）+ 布防（rescue_arm_safe_mode 需 ops）+ uitest 四件的放行/拒绝口径抽查。
- 本版所动模块行：搜索 F30 组、标题 T24/T26、完成胶囊 F29、桥 B16-17..19、卡间距 F30-13/14、圆角 [31]、天气 W18 对应的真机终判点（第九节）。

**执行归属：装后主线走桥自办**（本节仅记录选取，执行结果不在本报告内）。

## 九、真机终判点汇总

1. **搜索胶囊**：点搜索胶囊 → 键盘升起、胶囊展开；Diag 中 `APP search capsule tap` → `APP search capsule open` **两行成对**（无 tap = 命中未达；有 tap 无 open = 置焦未立，即本批回归签名）。回车收起见 `close src=submit`（词保留续滤）、点 × 见 `src=clear`、上滑列表见 `src=system`、点开备忘见 `src=nav`。
2. **标题胶囊竖排**：竖排打开一篇笔记，胶囊内 meta 小字行应与标题**成组居中**（0.9.56 旧形态为小字贴底边、与标题裂开约 20pt 空档——用户已确认旧形态即「贴着边」，本版应消失）；空标题时「无标题」占位色为系统占位灰（不再呈正文强度）。
3. **完成竖向胶囊**：点勾 → 键盘落、勾消失、胶囊自动缩回圆钮；Diag 三行序 `donecapsule done` → `EDIT kb visible=0 src=notify h=0` → `donecapsule collapse`。**第二轮**再升键盘再点勾/滑动收起，仍应正常展开与回缩（无闩锁残留）；滑动收起路径同见 visible=0 → collapse。
4. **桥稳定性·前台连通耗时**：App 切后台后回前台，桥应在数秒内连通。Diag 判读（搜 `BRIDGE`）：取 `BRIDGE presence state=foreground`（或 `BRIDGE probe fail`）时刻 → 其后第一条 `BRIDGE session up` / `state …->connected` 时刻之差；已连且活应见一行 `BRIDGE probe ok`（≤5s）；半死连接应见 probe fail 后约 1–2s（退避首档）+ 握手即 session up。旧病签名（应绝迹）：高频 connect 循环伴随 session up 缺失。断连原因看 `BRIDGE session down reason=` 分布（receive_error / send_error / heartbeat_timeout / probe_timeout）。
5. **救援布防·防循环**（头号）：经桥 rescue_arm_safe_mode 布防 → 下次冷启进安全模式（Diag `RESCUE arm consumed … applied=1` + `RESCUE arm cleared` 成对）→ rescue_try_normal_start 回正常模式 → **强杀后再冷启必须正常启动**（标记已消费、不被旧布防拽回）；若布防时启动已由 streak/OPS 定 safe，消费行应为 applied=0 只留痕。
6. **圆角收口**：等值收口，设置族/Diag/桥设置/救援各卡、吐司、备份 hero、开屏图标圆角应与改前逐一相同；iPad 抽查同。唯一可辨点：背景色底表描边由骑边（.stroke）归一为全内侧（.strokeBorder），落位差 **0.25pt**，重点看底表边缘；除此之外的任何可见变化即回归。
7. **天气副标题五语**：设置页天气行副标题逐语呈现——zh-CN「天气数据源令牌配置」、zh-TW「天氣資料來源令牌設定」、en-US "Weather data source token settings"、ja-JP「天気データソースのトークン設定」、ko-KR「날씨 데이터 소스 토큰 설정」；切换语言后该行即时换语、无旧状态词（和风/彩云内置）残留。
8. **首页卡间距**：装机后以与实报相同的角度量测——图文卡与下方文本卡之间的背景段应 **≈120px@3x**（40pt；修复前实测 216px / 72pt）；空状态（空库或零搜索结果）纵距回 56 账（内距 56、不再被默认 insets 放大 ≈+32）。
9. **卡间距批调优候选裁定（补记）**：该批所列候选「封面无图占位图标与 Web 纯灰面不符」——**用户 2026-11-27 17:07 裁定保留图标**（区分加载/失败状态，按增强保留口径定案），后续审计不再重复列报。
