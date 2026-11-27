# i18n 收尾批（审计登记余项）——只读准备 · 停门回报

> 状态：**只读准备完成，停门待放行**。落码门 = 0.9.58 组版分拣提交中
> （停门时点 HEAD 4070d70，bump 笔已落、分拣未收口），门前未动任何源码。
> 范围口径：原生 i18n I1–I3 已落、I5 显示名部分已由权限 B 段提前落地；
> I4（编辑器全域换键）是独立大批，本批不入其领地（重叠项只登记，见 §3）。
> 本批清单以审计/立项报告原文为准逐条提取，不自扩（顺手发现另列 §4）。

## 1. 清单提取（出处 → 现行形态 → 落码设计）

### T-1 图片页回退文案三处硬编码「图片」→ 既有键

- 出处：audit_home_other_deep.md §3.3（缺陷 P3，IMG-02 增补候选行），
  汇总表 §7「i18n 收尾批」第一项。
- 现行形态（本机实读，行号为停门时点）：`?? "图片"` 三处，均喂
  `ImageTarget.name` 兜底——MomentApp.swift:8878（image 块）、
  :12422（gallery 项）、:14568（CardBlockView.openImagePage）。
  审计时点行号 8194/11397/13440，其后多批落码行号漂移，点位以形态对齐。
- 键已在位：`imgpage.untitled` 五包齐全（zh-CN「图片」/en-US「Image」等），
  当前零引用。落码设计：三处改 `?? Lang.t("imgpage.untitled")`，行为等价
  （zh-CN 呈现逐字不变），非中文界面不再恒显中文。Diag 记全名逻辑
  （displayName 清单优先）不受影响，仅兜底值来源变。
- 注：:5236 SlashCmd 定义里的 `title: "图片"` 同形但属斜杠命令表，
  是 I4/M-07 领地，不在本批（见 §3）。

### T-2 「图片加载失败」无键 → 新增键五语补齐

- 出处：同 §3.3（「同页 Text("图片加载失败") 亦硬编码、无对应键。
  提案：失败文案新增键五包同步，随 i18n 零残留批」）。
- 现行形态：MomentApp.swift:19912，ImagePageView（:19838 起）内
  `Text("图片加载失败")` 直写；五包无对应键（`imgpage.*` 现仅
  untitled 一键，实读 zh-CN.json:178）。
- 落码设计：新增键 `imgpage.load_failed`，五语同批补齐（译文拟定，
  落码时定稿）：zh-CN「图片加载失败」/ zh-TW「圖片載入失敗」/
  en-US「Failed to load image」/ ja-JP「画像を読み込めませんでした」/
  ko-KR「이미지를 불러오지 못했습니다」。Text 改 `Lang.t(...)`。

### T-3 ImagePageView 未观察 LangStore → 补观察接线（图片页半边）

- 出处：audit_home_other_deep.md §4.5（SET-09 子行）：「EditorView 与
  ImagePageView 未声明 @EnvironmentObject langStore，子树 Lang.t 为
  静态查表无失效触发——桥远程切语言时若页面正开，文案停在旧语言
  直至重开」。
- 现行形态（实读）：ImagePageView 属性区（:19838–19852）无 langStore
  声明；对照 ListView:16704、SettingsView:18613、LanguageView、
  ErrBadgeOverlay:3800 均已声明。根注入在位，缺的只是本视图的观察声明。
- 落码设计：ImagePageView 补一行 `@EnvironmentObject private var
  langStore: LangStore`（与各页同形），零行为差（默认语言下呈现不变），
  桥远程切语言时图片页即时刷新。编辑器半边归 I4（见 §3）。

### T-4 followSystem 运行中改系统语言不重解析 → 变更监听重解析

- 出处：同 §4.5 差②（「followSystem 时运行中改系统语言不重解析，
  须重启。提案：系统语言变更监听重解析随手补或明确登记重启生效口径」）。
- 现行形态（实读）：LangStore（MomentApp.swift:4345）有 apply（:4395）/
  applyFollowSystem（:4408），系统解析读 Locale.preferredLanguages
  （:4440）；全仓 grep 无 NSLocale 变更通知监听、无 scenePhase 重解析
  ——运行中改系统语言确实须重启才生效（proven，源码面）。
- 落码设计：LangStore init 增 `NSLocale.currentLocaleDidChangeNotification`
  监听，回调内仅 followSystem==true 时重解析 + 沿既有
  `LANG follow-system -> <code>` 打点口径落行；手动模式零动作。
  不采「重启生效」登记口径——监听是系统现成能力，行为等价更优
  （立项 §3 判读同理）。

### T-5 键数守恒口径同步（371 → 372）

- 现行实测：五包各 **371 键、键集合两两互等**（本机脚本逐包比对，
  missing/extra 皆 0）；verify [9] 四条（键集一致 / 键数 371 含完整
  注释链 / 产物 md5 / 引用键齐全）结构在位、源码面全绿——**无漂移存量**，
  历史漂移均已由各加键批同步期望（[9] 注释链 307→…→371 可查）。
- 落码设计：T-2 加 1 键后，[9] 键数期望改 372、注释链续一行
  （`+ 1（i18n 收尾批：imgpage.load_failed）= 372`），其余三条不动。
- 断言增补（并入 [9] 组尾）：三点位 `Lang.t("imgpage.untitled")`
  计数 = 3 且 `?? "图片"` 在 MomentApp.swift 计数归零（SlashCmd 的
  title 字面量是独立形态 `title: "图片"`，不被此式误伤，断言式须
  以 `?? "图片"` 为锚）；`Text("图片加载失败")` 零残留；
  ImagePageView 段内 langStore 声明在位；LangStore 段内 locale
  变更监听锚在位。

## 2. 落码面汇总（放行后）

| 文件 | 改动 |
|---|---|
| rust/apps/web/lang/*.json（五份） | +1 键 imgpage.load_failed（T-2） |
| rust/apps/ios/app/MomentApp.swift | T-1 三处、T-2 一处、T-3 一行、T-4 LangStore 监听段 |
| rust/apps/ios/app/verify_ios.sh | [9] 键数 372 + 注释链 + 尾部四锚（T-5） |

自检口径：本机 verify [9] 组全绿 + MomentApp primary 遍类型检查
零错误；产物 md5 条随组版 tree 构建自解（既有口径）。

## 3. 与 I4 重叠——只登记、不落码

- **EditorView 观察 LangStore**（§4.5 编辑器半边）：EditorView
  （:9431 起）属性区实读无 langStore 声明，审计提案「顶层补一行
  观察接线」——落点在 EditorView 本体，归 I4 落码时顺手一行，
  本批不入。
- **M-07 斜杠命令 i18n**（audit_editor_deep.md:61/204/326 明示
  「随 I4」）：24 条命令 title/sub 为 zh-CN 字面量（含 :5236
  「图片/插入图片占位」），Web 侧键在 render.rs 口径五语在位；
  归 I4，本批不动。

## 4. 边界与顺手发现（非本批落码）

- **桥 scopes 空集兜底**（MomentBridgeSettings.swift:233–235）：
  用的是既有键 `bridge.scope_read`，**非漏键**；其「空集误显只读」
  是呈现语义问题，归桥呈现小批（已登记），本批不涉。
- **bridge.pair_expired**：已入包未接线系配对二维码批定案备用
  （impl_pairing_qr_code.md），非缺键、不处理。
- **救援页 statusRow 英文技术标签**（MomentRescue.swift，mode/DB/
  Diag/OPS 等）：属 Diag 证据口径——立项 §3 定「Diag 载荷不做
  多语言」，救援页 UI 壳（rescue.title/boundary 等）已走语言包，
  非漏键。
- **I5 计划残余**（plan_native_i18n.md §4/§5，未被审计登记入本批）：
  全文件 CJK 零残留门转正（现 [9] 仅首页范围白名单，:376 起）、
  五语 × 窄屏 × 大字号视觉通查——建议随 I5 窗口另行处置。
- **顺手发现两处未登记硬编码**（只读普查 Text 直写 CJK 时见，
  不自扩入本批）：MomentApp.swift:11755 `Text("PDF 将生成文件，
  可通过分享存储或打印。")`（导出/分享面，近 I5 ShareSheet 残余）、
  :12263 `Text("平板与 PC 可分别滚动两栏")`（双栏说明面）——
  登记在此，归 I5 残余面或相应窗口顺手。

## 5. 真机终判点（放行落码后随组版）

1. 非中文界面（如 en-US）打开无名图：图片页标题显「Image」、
   加载失败显新键译文，不再恒中文。
2. 桥远程切语言时图片页正开：文案即时刷新、不需重开（T-3）。
3. 跟随系统模式下运行中改系统语言：回 App 语言即时重解析
   （Diag 有 LANG follow-system 行）；手动模式改系统语言无变化（T-4）。

——停门回报完。放行条件：0.9.58 组版提交收口、工作树净。
