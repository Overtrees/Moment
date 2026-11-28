#!/usr/bin/env bash
# 原生 iOS 冒烟断言（防回归）：构建产物与源码红线的
# 静态契约检查。本机无 iOS 模拟器，启动级冒烟靠真机
# Diag 的 SMOKE 行 + 启动守卫（LAUNCH 行）留证；本脚
# 本管住「构建绿但形态/契约已坏」这一类：版本串漂移、
# 工具链禁区回潮（Section/@State/PhotosPicker）、FFI
# 契约缺失、ipa 陈旧/缺件、天气 key 未注入。
# 用法：bash verify_ios.sh [--ipa 路径]；全过打印 ALL PASS。
set -u
cd "$(dirname "$0")"
SRC=MomentApp.swift
# 0.9.45 自救批拆分文件（[13] 取段来源）：启动哨兵 /
# 热更新指令 / 安全模式页已独立成文件。
LAUNCH=MomentLaunch.swift
OPS=MomentOps.swift
RESCUE=MomentRescue.swift
# 0.9.47 拖拽第二轮根治拆分文件：按压引擎/注册锚点。
DRAG=MomentDrag.swift
# MCP 桥六文件（M1，[16] 取段来源）：协议/传输/
# 协调器/分发/运维回读/设置页。
BPROTO=MomentBridgeProtocol.swift
BTRANS=MomentBridgeTransport.swift
BRIDGE=MomentBridge.swift
BTOOLS=MomentBridgeTools.swift
BOPS=MomentBridgeOps.swift
BSET=MomentBridgeSettings.swift
BRESTORE=MomentBridgeRestore.swift
# U1 批新文件（[25]/[26] 取段来源）：UI 自检驱动 /
# 标题字段 representable / 落点映射纯函数。
UITEST=MomentBridgeUITest.swift
TFIELD=TitleTextField.swift
TCARET=TitleTapCaret.swift
# M3a 批新文件（[27] 取段来源）：桥场景库/引擎/
# journal/量测解析。
BSCEN=MomentBridgeScenarios.swift
# SVG 光栅化批新文件（[42] 取段来源）：解码漏斗
# SVG 内容嗅探 + 离屏 WKWebView 光栅化。
SVGR=MomentSvgRaster.swift
# E2 撤销体系新文件（[47] 取段来源）：撤销历史
# 纯状态机（合并/去重/钳制/选区附带）。
UNDO=MomentUndo.swift
# F-09 一期跨块选区新文件（[50] 取段来源）：纯
# 核心（端点排序/守卫钳制/行内劈分/结果列）+
# 桥接层 EditorModel 扩展（状态机/replaceRange）。
XSEL=MomentXSel.swift
XSELB=MomentXSelBridge.swift
# 开屏独立承载文件（[53] SB-8 取段来源）：二
# 轮随状态栏批立；背景色采样整套去除后本文件
# 只剩呈现与方向锁面（remove_statusbar_
# sampling）。
SPLASH=MomentSplashHost.swift
# fix_image_card_load 批新文件（[55] 取段来源）：
# 图片加载身份键控纯核心（源键/裁定/闸门）。
IMGCORE=MomentImageLoad.swift
RELAY=../../../../bridge/relay/worker.js
SH=build-app2.sh
IPA=build/Moment-stage2.ipa
[ "${1:-}" = "--ipa" ] && IPA="$2"
fail=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; fail=1; }
has()  { grep -q -- "$1" "$2"; }
hasE() { grep -qE -- "$1" "$2"; }

echo "[1] 版本串三处一致"
v_sh=$(grep -o 'CFBundleShortVersionString</key><string>[^<]*' "$SH" | sed 's/.*<string>//')
# 取值锚定 settings.version 标签之后首个数字 Text
# （AUD-C-06 改锚：旧法取全文件首个数字 Text、仅因
# 现行文件恰一处而偶合正确，属锁文本不锁机制）。
v_sw=$(awk '/settings\.version/{f=1} f' "$SRC" | grep -o 'Text("[0-9][0-9.]*")' | head -1 | sed 's/Text("//; s/")//')
b_sh=$(grep -o 'CFBundleVersion</key><string>[^<]*' "$SH" | sed 's/.*<string>//')
if [ -n "$v_sh" ] && [ "$v_sh" = "$v_sw" ]; then
  ok "版本 $v_sh（脚本与设置页一致，build $b_sh）"
else
  bad "版本不一致：脚本=$v_sh 设置页=$v_sw"
fi

echo "[2] 工具链禁区零回潮（本工具链 + iOS 27.2.1 定案）"
# 只查代码行：整行注释里提及禁区词（交代口径）不算回潮。
CODE=$(grep -v '^[[:space:]]*//' "$SRC")
if echo "$CODE" | grep -qE 'Section[[:space:]]*\(' \
   || echo "$CODE" | grep -qE '^[[:space:]]*Section[[:space:]]*\{'; then
  bad "出现 Section builder（构建即 trap 的定案禁区）"
else
  ok "无 Section builder"
fi
if echo "$CODE" | grep -qE '@State[[:space:]]' \
   || echo "$CODE" | grep -qE '@State$'; then
  bad "出现 @State（宏插件缺失，须 ObservableObject）"
else
  ok "无 @State"
fi
if echo "$CODE" | grep -q 'PhotosPicker'; then
  bad "出现 PhotosPicker（本工具链不可见，须 PHPicker）"
else
  ok "无 PhotosPicker"
fi
if echo "$CODE" | grep -q 'VideoPlayer'; then
  bad "出现 SwiftUI VideoPlayer（不可见，须 AVPlayerViewController）"
else
  ok "无 SwiftUI VideoPlayer"
fi

echo "[3] FFI 契约（Swift 调用面在 bindings 中齐备）"
BIND=../bindings/moment_ffi.swift
if [ -f "$BIND" ]; then
  for fn in listMemosJson upsertMemoJson removeMemo searchIdsJson \
            exportBackup importBackup validateBackup libraryHash \
            attachmentData attachmentIdsJson putAttachment attachmentNamesJson \
            avatarData setAvatar mdClassify mdIsBlockPreview mdParseJson renderMathml; do
    if has "$fn" "$BIND"; then ok "ffi $fn"; else bad "ffi 缺 $fn"; fi
  done
else
  bad "bindings 文件不存在：$BIND"
fi

echo "[4] 数据契约守卫（批 A/B 定案形态在位）"
if has 'quarantined' "$SRC"; then ok "list 包装形解析在位"; else bad "Swift 侧未见包装形解析（quarantined）"; fi
if has 'list_memos_tolerant' ../../../crates/storage/src/lib.rs; then ok "storage 逐篇容错在位"; else bad "storage 缺 list_memos_tolerant"; fi
if has '"quarantined"' ../../../crates/ffi/src/lib.rs; then ok "ffi 包装形输出在位"; else bad "ffi 未输出包装形"; fi
if has 'launchInProgress' "$SRC"; then ok "启动守卫在位"; else bad "启动守卫缺失"; fi
if has 'SMOKE' "$SRC"; then ok "冷启 SMOKE 行在位"; else bad "冷启 SMOKE 行缺失（真机冒烟证据链断）"; fi
if has 'attachmentNamesJson' "$SRC"; then ok "清单查名接线在位（图片页标题真值源）"; else bad "Swift 侧未接 attachmentNamesJson（图片页标题将回退「图片」）"; fi
if grep -q 'let panelH: CGFloat = 320' "$SRC"; then bad "斜杠面板 320 写死估高回潮（#52 实测高定位被回退）"; else ok "斜杠面板无写死估高（实测高定位在位）"; fi
if has 'slashEstimateH' "$SRC" && has 'slashPanelH' "$SRC"; then ok "斜杠实测高状态 + 首帧估高在位"; else bad "斜杠实测高机制缺失（#52）"; fi
# 截断锚定 ImagePageView 段内的真实截断式（AUD-D-02
# 改锚：旧法全文件 grep 'prefix(12)' 恒命中 UUID 等
# 九处无关用例、断言恒真）。段界至 SplashHostView。
IMGPG=$(awk '/^struct ImagePageView/,/^struct SplashHostView/' "$SRC")
if echo "$IMGPG" | grep -qF 'String(n.prefix(12))' && echo "$IMGPG" | grep -qF '+ "…"'; then ok "图片页标题 12 字截断在位"; else bad "图片页标题截断缺失（用户定 12 字 + …）"; fi
if has 'func logOnce' "$SRC" && has 'func logErrorOnce' "$SRC"; then ok "Diag 去重原语在位（G7）"; else bad "Diag logOnce/logErrorOnce 缺失（G7）"; fi
if has 'struct ErrBadgeOverlay' "$SRC" && has 'ErrBadgeOverlay()' "$SRC"; then ok "错误徽章已上提应用根（G8）"; else bad "错误徽章未上提（G8）"; fi
if grep -q 'errBadgeLayer' "$SRC"; then bad "EditorView 旧徽章层回潮（与根层双份呈现）"; else ok "EditorView 无旧徽章层（单份呈现）"; fi

echo "[5] ipa 产物"
if [ -f "$IPA" ]; then
  sz=$(stat -c%s "$IPA")
  if [ "$sz" -gt 3000000 ]; then ok "ipa 大小 $sz"; else bad "ipa 过小 $sz"; fi
  if [ "$IPA" -nt "$SRC" ]; then ok "ipa 新于源码"; else bad "ipa 陈旧（早于 MomentApp.swift，先重新构建）"; fi
  if unzip -l "$IPA" | grep -q 'Payload/Moment.app/weather-keys.json'; then
    ok "天气 key 已注入 bundle"
  else
    bad "ipa 内缺 weather-keys.json（天气将无默认 key）"
  fi
  if unzip -l "$IPA" | grep -q 'Payload/Moment.app/Moment'; then
    ok "可执行在位"
  else
    bad "ipa 内缺可执行"
  fi
else
  bad "ipa 不存在：$IPA"
fi

echo "[6] UniFFI checksum 契约（bindings 期望 == ffi 断言表）"
FFI_RS=../../../crates/ffi/src/lib.rs
b_vals=$(grep -o '!= [0-9]*)' ../bindings/moment_ffi.swift | grep -o '[0-9]*' | sort -n)
t_vals=$(grep -o 'checksum_[a-z0-9_]*(), [0-9]*)' "$FFI_RS" | awk -F', ' '{print $NF}' | tr -d ')' | sort -n)
if [ -n "$b_vals" ] && [ "$b_vals" = "$t_vals" ]; then
  ok "23 项 checksum 双向一致（改导出面未重生 bindings 会在此红）"
else
  bad "checksum 不一致：bindings 与 ffi 契约测试表对不上"
fi

echo "[7] 几何前提断言（数字依赖的结构前提，改一漏一即红）"
# 标题胶囊横排不溢出的前提组：坞上限 W−124/W−204 只在
# 页眉两段 Spacer 紧贴（minLength 0）时成立——0.9.35 长
# 标题溢出定因即此账漏算。两处 Spacer 与公式必须同在。
hstart=$(grep -n '^struct EditorHeaderView' "$SRC" | cut -d: -f1)
hend=$(awk -v s="$hstart" 'NR > s && /^struct [A-Z]/ { print NR; exit }' "$SRC")
HDR=$(sed -n "${hstart},${hend}p" "$SRC" | grep -v '^[[:space:]]*//')
# 计数域收窄到标题行段（struct 起 → 胶囊上限公式行）：
# J1 反链行（同 struct 段内）自带一枚尾随 Spacer，
# 与页眉前提无关；整段计数会误红（探针随结构复审，
# 2026-11-27 tree 冒烟实证）。
hend2=$(awk -v s="$hstart" 'NR > s && /headerW - 124/ { print NR; exit }' "$SRC")
HDR2=$(sed -n "${hstart},${hend2}p" "$SRC" | grep -v '^[[:space:]]*//')
n_sp0=$(echo "$HDR2" | grep -c 'Spacer(minLength: 0)')
if [ "$n_sp0" = 2 ] && echo "$HDR" | grep -q 'headerW - 124'; then
  ok "页眉 Spacer 紧贴 ×2 + 胶囊上限坞口径（横排不溢出前提组）"
else
  bad "页眉紧贴 Spacer=$n_sp0（应 2）或胶囊上限公式不在——横排溢出前提已坏"
fi
# 段距整组前提：栏 spacing 与拖拽让位 gap 必须同值
# （0.9.33 段距重算的结构账：改栏距必同步改 gap）。
if has 'let gap: CGFloat = 6' "$SRC" \
   && has 'VStack(alignment: .leading, spacing: 6)' "$SRC" \
   && has 'top: 2, left: 0, bottom: 2' "$SRC"; then
  ok "段距合成前提组（栏 spacing 6 == 拖拽 gap 6、文本 inset 2）"
else
  bad "段距前提组缺项：栏 spacing / 拖拽 gap / UITextView inset 三者须同改"
fi
# gallery 瓦高前提：图瓦与空瓦同高 366（0.9.33 #33/#34）。
n_g366=$(echo "$CODE" | grep -c 'frame(height: 366)')
if [ "$n_g366" = 2 ]; then
  ok "gallery 图瓦/空瓦同高 366"
else
  bad "gallery 366 高出现 $n_g366 处（应 2：图瓦 + 空瓦）"
fi
# 图片页判定前提：小/大图判定用可用高，与呈现
# 同高（0.9.35 排查修复的同源口径）；让位数值
# 随 L-4 对齐 Web（顶 126 + 底 40 + safe）后本
# 条同步改判——同源性不变、只换数值。
if has 'geo.size.height - 126' "$SRC"; then
  ok "图片页判定用可用高（全屏 − 126 − 40 − safe）"
else
  bad "图片页判定高口径不在（边界图会走错分支被裁）"
fi
# 拖拽仲裁回潮哨（2026-11-26 真机「拖不了」定因）：
# 按压引擎段内禁止再出现 require(toFail ——该关系
# 使长按等 pan 判失败、拾起永不触发；拾起锁滚动
# isScrollEnabled = false 必须在位。取段来源随
# 0.9.47 拆分改指 MomentDrag.swift（DragPressEngine
# 全文，注释行除外）；机制前提的完整锁在 [14]。
INST=$(grep -v '^[[:space:]]*//' "$DRAG")
if echo "$INST" | grep -q "require(toFail"; then
  bad "拖拽仲裁回潮：引擎内出现 require(toFail（拾起永不触发）"
else
  ok "拖拽仲裁无 require(toFail 回潮"
fi
if echo "$INST" | grep -q "isScrollEnabled = false"; then
  ok "拾起锁滚动在位"
else
  bad "拾起锁滚动缺失（跟指时内容会被 pan 带走）"
fi
# 拾起呈现前提组（Web 规格：LIFT_INSET 4 等距框 +
# liftScaleFor 双轴公式）：LiftFrame 的外扩与缩放
# 公式 (dim - 8) 必须同在。外扩量 0.9.52 起走
# Radius.liftInset 派生（原字面 padding(-4)），前
# 提不变、断言随单源口径同步（fix_card_radius.md）。
if has 'struct LiftFrame' "$SRC" && has 'padding(-Radius.liftInset)' "$SRC" \
   && has '(dim - 8) / dim' "$SRC"; then
  ok "拾起框 + 双轴缩放公式前提组在位"
else
  bad "拾起框/双轴缩放前提缺失（LiftFrame、padding(-Radius.liftInset)、(dim - 8) / dim 须同在）"
fi

echo "[8] 资源断言（图标/开屏：Assets.car 路线）"
AST="assets"
ISRC="icon-src"
if [ -f "$ISRC/moment.icon/icon.json" ] \
   && [ -f "$ISRC/Assets.xcassets/LaunchBackground.colorset/Contents.json" ]; then
  ok "car 真源在位（moment.icon + LaunchBackground colorset）"
else
  bad "car 真源缺失（icon-src/moment.icon 或 colorset）"
fi
if [ -f "$AST/native-splash/MomentSplash-light-vector.json" ] \
   && [ -f "$AST/native-splash/MomentSplash-dark-vector.json" ]; then
  ok "开屏矢量资源（深/浅）在位"
else
  bad "开屏矢量资源缺失（native-splash 两份 json）"
fi
APPB="build/Moment.app"
for f in Assets.car MomentSplash-light-vector.json \
         MomentSplash-dark-vector.json; do
  if [ -f "$APPB/$f" ]; then
    ok "产物含 $f"
  else
    bad "产物缺 $f（先重新构建）"
  fi
done
# 散落 AppIcon*.png 入包 = 系统按普通 PNG 图标处理、
# 不读 car（技能 package.md），必须零残留。
if ls "$APPB"/AppIcon*.png >/dev/null 2>&1; then
  bad "产物含散落 AppIcon*.png（会遮蔽 Assets.car）"
else
  ok "产物无散落 AppIcon*.png（car 不被遮蔽）"
fi
# car 内容：accord 在位时 inspect 核对三外观 +
# LaunchBackground 的 Color（colorset）rendition。
ACCORD_BIN="$HOME/ios-native/bin/accord"
if [ -x "$ACCORD_BIN" ] && [ -f "$APPB/Assets.car" ]; then
  INSPECT="$("$ACCORD_BIN" inspect "$APPB/Assets.car" 2>/dev/null)"
  if echo "$INSPECT" | grep -q 'Color.*"LaunchBackground"' \
     && echo "$INSPECT" | grep -q "UIAppearanceDark" \
     && echo "$INSPECT" | grep -q "ISAppearanceTintable"; then
    ok "car 内容：LaunchBackground colorset + 图标深色/着色外观齐"
  else
    bad "car 内容不全（colorset 或图标外观缺失）"
  fi
fi
# 状态栏声明口径（fix_statusbar_sampling 改判）：
# UIStatusBarStyle 保留 LightContent 只作开屏帧，
# 字色决定权已翻 UIViewControllerBasedStatusBar
# Appearance=true 交承载链采样决定（[53]）；旧
# [8] 只锁 LightContent 字符串存在、与「声明恒
# 白」旧口径绑定，本批起改锁两键形态、<false/>
# 回潮即红。
if grep -q "CFBundleIconName" "build-app2.sh" \
   && grep -q "UIColorName" "build-app2.sh" \
   && grep -q "UIStatusBarStyleLightContent" "build-app2.sh" \
   && grep -q "UIViewControllerBasedStatusBarAppearance</key><true/>" "build-app2.sh" \
   && ! grep -q "UIViewControllerBasedStatusBarAppearance</key><false/>" "build-app2.sh" \
   && grep -q "accord" "build-app2.sh"; then
  ok "Info.plist 图标/开屏/状态栏声明在构建脚本内（开屏帧 LightContent + VC 化已翻 true）"
else
  bad "构建脚本缺 CFBundleIconName/UIColorName/状态栏/accord 任一项（或 VC 化未翻、<false/> 回潮）"
fi
# 开屏解码面锁（AUD-E-01 升级，原 [8] 只验资
# 源在位）：构建期以 python3 实解码两份矢量
# JSON，字段集与 NativeSplashVectorResource
# 的 Decodable 结构逐项对齐——background 与
# logo.gradient 的 start/end 长度 ≥2、stops
# ≥1、logo.basePath 与 tagline.d 非空；资源
# 形态坏在构建期即红，不留到设备端才暴露。
E01D=$(mktemp -d)
cat > "$E01D/splash_check.py" <<'PYEOF'
import json, sys
ok = True
for theme in ("light", "dark"):
    try:
        d = json.load(open(
            "assets/native-splash/"
            f"MomentSplash-{theme}-vector.json"))
        for g in (d["background"],
                  d["logo"]["gradient"]):
            ok = ok and len(g["start"]) >= 2
            ok = ok and len(g["end"]) >= 2
            ok = ok and len(g["stops"]) >= 1
        ok = ok and len(d["logo"]["basePath"]) > 0
        ok = ok and len(d["tagline"]["d"]) > 0
    except Exception:
        ok = False
sys.exit(0 if ok else 1)
PYEOF
if python3 "$E01D/splash_check.py"; then
  ok "开屏矢量解码面（两主题字段集与 Decodable 结构对齐）"
else
  bad "开屏矢量解码面漂移（字段长度/非空不满足 Decodable 契约）"
fi
# 开屏降级面源码锁（AUD-E-01）：load 体内陷
# 阱退出（fatalError）零命中、降级 Diag 行在
# 位；渐变下标守卫（start/end 计数 + stops
# 空回退）与单色 init 在位——解码失败走降级
# 呈现、永不 trap。
SPL8=$(awk '/private static func load\(theme: String\)/,/private static func degraded/' "$SRC")
if [ "$(echo "$SPL8" | grep -c 'fatalError')" = 0 ] \
   && has 'SPLASH artwork decode failed theme=' "$SRC" \
   && has 'resource.start.count >= 2' "$SRC" \
   && has 'resource.end.count >= 2' "$SRC" \
   && has 'resource.stops.isEmpty' "$SRC" \
   && has 'init(solid color: Color)' "$SRC"; then
  ok "开屏降级面（load 零陷阱 + Diag 行 + 渐变守卫/单色 init）"
else
  bad "开屏降级面漂移（陷阱回潮或守卫/降级件缺失）"
fi

echo "[9] 语言包完整性（原生 i18n I1–I3，立项 plan_native_i18n.md）"
LANGDIR=../../web/lang
# 五语键集合一致：真源自身的常驻门，任一包缺键即红
# （补键纪律：新键五语齐全才许引用）。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
sets = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        sets.append(set(json.load(f)))
sys.exit(0 if all(s == sets[0] for s in sets) else 1)
PYEOF
then
  ok "五语键集合一致（Web 真源）"
else
  bad "五语键集合不一致（补键须五语齐全）"
fi
# 键数期望（补键时同步改此数）：307（I1–I3 基线）
# + 17（0.9.45 自救批：S10 清单 16 键 + S13 追加
# rescue.check_ops 1 键）= 324；+ 27（MCP 桥 M1：
# bridge.* 26 键 + settings.bridge 1 键）= 351；
# + 11 − 2（天气设置重构批：新增 weather_builtin
# 等 11 键、退役 weather_save/weather_active）
# = 360；+ 1（救援完整性批：diag.enter_rescue
# 手动救援入口）= 361；+ 6（权限/实况批：
# liveops.* 4 键 + bridge.notify 两键）= 367；
# + 3（配对二维码批：bridge.pair_* 三键）= 370；
# + 1（桥会话实况批：liveops.bridge_session）
# = 371；+ 1（i18n 收尾批：imgpage.load_failed）
# = 372；+ 1（备份小批：notice.import_reload_failed
# 导入后重载失败提示）= 373；+ 8（桥呈现小批：
# bridge.revoke_* 三键 + bridge.scopes_none /
# bridge.scopes_ungranted 两键 + bridge.reason_*
# 三键）= 381；+ 48（权限中心批：perm.* 48 键，
# impl_permission_center.md）= 429；+ 10 − 1（配
# 对 App 内确认批：新增 bridge.pair_confirm /
# pair_confirm_failed / pair_scope_*_note 三
# 键 / key_* 五键共 10 键，退役
# bridge.pair_open）= 438；+ 3（实况设计批：
# liveops.done / liveops.failed 终态步名 +
# liveops.running 进行态步名）= 441；+ 22
# （I4/I5 批：slash.math_* 四键、action.save、
# sheet.edit_link / imgtext_title / view_full、
# editor.avatar_* 三键 / done_aria / meta_line、
# attach.pick_* 两键、menu.paragraph /
# delete_block、export.pdf_file_note、
# media.audio / att_none / image_unavailable、
# errbadge.pdf_failed）= 463；+ 1（0.9.64 组版：
# app.splash_icon_aria 开屏图标 a11y 换键）= 464。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
counts = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        counts.append(len(json.load(f)))
sys.exit(0 if all(n == 464 for n in counts) else 1)
PYEOF
then
  ok "五语键数 464（463 + 0.9.64 组版开屏 a11y 键 1）"
else
  bad "五语键数非 464（补键须同步改此期望）"
fi
# 产物含五包且与 Web 源 md5 一致（单一真源对账；
# APPB 沿 [8] 的 build/Moment.app）。
langok=1
for c in zh-CN zh-TW en-US ja-JP ko-KR; do
  if [ ! -f "$APPB/lang/$c.json" ]; then langok=0; break; fi
  m1=$(md5sum "$LANGDIR/$c.json" | cut -d' ' -f1)
  m2=$(md5sum "$APPB/lang/$c.json" | cut -d' ' -f1)
  if [ "$m1" != "$m2" ]; then langok=0; break; fi
done
if [ "$langok" = 1 ]; then
  ok "产物五包在位且与 Web 源 md5 一致"
else
  bad "产物语言包缺失或与 Web 源不一致（先重新构建）"
fi
# Swift 引用键五语齐全：提取 Lang.t / Lang.tf 键名
# （含跨行调用），逐个断言五包都在。
if python3 - "$LANGDIR" "$SRC" <<'PYEOF'
import json, re, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
packs = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        packs.append(json.load(f))
src = open(sys.argv[2], encoding="utf-8").read()
keys = set(re.findall(
    r'Lang\.tf?\(\s*"([a-z0-9_.]+)"', src))
missing = [k for k in sorted(keys)
           if any(k not in p for p in packs)]
if missing:
    print("  missing keys:", ", ".join(missing))
    sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "Swift 引用键五语齐全"
else
  bad "Swift 引用键有缺（见上 missing keys 行）"
fi
# 语言页接通：点选/跟随系统 apply 与 LANG 打点在位、
# 旧硬编码行数组零残留、设置行 meta 不再写死。
LV=$(awk '/^struct LanguageView/,/^struct ImagePageView/' "$SRC")
if echo "$LV" | grep -q 'applyFollowSystem' \
   && echo "$LV" | grep -q 'langStore.apply(code)' \
   && has 'LANG applied' "$SRC" \
   && has 'LANG follow-system' "$SRC" \
   && has 'LANG init' "$SRC"; then
  ok "语言页已接通 LangStore（点选切换 + LANG 打点）"
else
  bad "语言页未接通（apply/applyFollowSystem/LANG 打点缺）"
fi
if echo "$LV" | grep -q '使用中", true'; then
  bad "语言页旧硬编码行数组残留"
else
  ok "语言页无旧硬编码行数组"
fi
if grep -q 'meta: "简体中文"' "$SRC"; then
  bad "设置页语言行 meta 仍写死「简体中文」"
else
  ok "设置页语言行 meta 已随 store 解析"
fi
if grep -q 'web/lang' "$SH" \
   && grep -q 'lang packs injected' "$SH"; then
  ok "构建脚本含语言包拷入段（Web 源 → .app/lang）"
else
  bad "构建脚本缺语言包拷入段"
fi
# I3：Fmt 日期词去硬编码 + 首页范围 CJK 残留白名单。
# 白名单逐条列清（仅此一条，不得为过断言增补）：
#   W1 "场景·首页"（ListView 1 处）：启动守卫的场景
#      哨兵标识，写入 UserDefaults 与既有值跨版本对
#      读、inspectPreviousLaunch 以 hasPrefix("场景")
#      判定，属 Diag/状态载荷——立项 §3「Diag 不本地
#      化」，不换键。
# 其余范围（Fmt / ErrBadgeOverlay / MemoItem 扩展 /
# ListView 其余）出现 CJK 单行字符串字面量即红；
# Library 只对 notice 赋值与 addError/addWarn 调用点
# 设门，并对已退役的 UI 原文（徽章消息 10 条 +
# notice 5 条 + lastExportError「库未打开」）做零残
# 留断言——Library 其余 CJK 字面量是 Diag 日志行、
# 启动步骤标识、timing 读数（仅 Diag 页库状态呈现）、
# 种子示例内容与导出文件名（数据面），按立项口径
# 不本地化、不在本断言范围。
if python3 - "$SRC" <<'PYEOF'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
cjk = re.compile(r'[一-鿿]')
strlit = re.compile(r'"((?:[^"\\]|\\.)*)"')

def block(start_pat, end_pat):
    a = next(i for i, l in enumerate(lines)
             if re.search(start_pat, l))
    b = next(i for i, l in enumerate(lines)
             if i > a and re.search(end_pat, l))
    return a, b

def lits(a, b):
    out = []
    for i in range(a, b):
        for m in strlit.finditer(lines[i]):
            if cjk.search(m.group(1)):
                out.append((i + 1, m.group(1)))
    return out

bad = []
a, b = block(r'^enum Fmt', r'^// ── 诊断日志管线')
bad += [("Fmt", ln, s) for ln, s in lits(a, b)]
fmt_src = "\n".join(lines[a:b])
for probe in ['"group.today"', '"group.yesterday"',
              '"time.am"', '"backup.never"',
              'LangStore.shared.code']:
    if probe not in fmt_src:
        bad.append(("Fmt-missing", 0, probe))
a, b = block(r'^struct ErrBadgeOverlay',
             r'^final class DiagLog')
bad += [("ErrBadge", ln, s) for ln, s in lits(a, b)]
if 'langStore: LangStore' not in "\n".join(lines[a:b]):
    bad.append(("ErrBadge", 0, "no langStore"))
a, b = block(r'^extension MemoItem', r'^// ── 恐龙线稿')
bad += [("MemoItem", ln, s) for ln, s in lits(a, b)]
a, b = block(r'^struct ListView', r'^// ── 子页骨架')
for ln, s in lits(a, b):
    if s != "场景·首页":
        bad.append(("ListView", ln, s))
if 'langStore: LangStore' not in "\n".join(lines[a:b]):
    bad.append(("ListView", 0, "no langStore"))
a = next(i for i, l in enumerate(lines)
         if re.search(r'^final class Library', l))
b = next(i for i, l in enumerate(lines)
         if i > a and l == "}")
for i in range(a, b):
    if re.search(r'(addError|addWarn)\(\s*"', lines[i]) \
            or re.search(r'notice\s*=\s*"', lines[i]):
        if cjk.search(lines[i]):
            bad.append(("Library", i + 1,
                        lines[i].strip()))
RETIRED = {"打开数据库失败", "导出备份失败",
           "导入备份失败", "附件保存失败",
           "附件保存失败：数据库未打开", "搜索失败",
           "删除失败", "保存失败：内容序列化出错",
           "保存失败：数据库未打开",
           "保存失败：写入数据库出错", "库未打开"}
PHRASES = ["应用连续", "篇备忘数据损坏",
           "这篇备忘暂时无法写入", "编辑只保留"]
for ln, s in lits(a, b):
    if s in RETIRED or any(p in s for p in PHRASES):
        bad.append(("Library-retired", ln, s))
if bad:
    for tag, ln, s in bad:
        print(f"  residual {tag} @{ln}: {s}")
    sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "Fmt 日期词已换键 + 首页范围 CJK 残留合白名单（仅 W1 场景哨兵）"
else
  bad "Fmt/首页范围有 CJK 残留或键引用缺失（见上 residual 行）"
fi
# i18n 收尾批（T-1..T-4）：图片页回退/失败文案
# 换键、ImagePageView 观察接线、followSystem 的
# locale 变更重解析锚。
# T-1 基数改判（fix_image_tap_regression 沿革）：
# 回退字面原三处（图块/gallery/图文三入口各拼
# ?? Lang.t 兜底）已随图片页路由收口单点归一为
# 单点本体恰 1 处——不变量（回退恒走键、硬编码
# 兜底零残留）不变，计数随机制收口改判 3→1。
if [ "$(grep -c 'Lang\.t("imgpage\.untitled")' "$SRC")" = 1 ] \
   && ! grep -q '?? "图片"' "$SRC"; then
  ok "T-1 图片页回退文案单点引 imgpage.untitled（?? \"图片\" 零残留）"
else
  bad "T-1 图片页回退文案未全换键（imgpage.untitled 引用须恰 1 处（路由单点）、?? \"图片\" 须归零）"
fi
if grep -q 'Text("图片加载失败")' "$SRC"; then
  bad "T-2 图片加载失败文案仍硬编码"
elif grep -q 'Lang\.t("imgpage\.load_failed")' "$SRC"; then
  ok "T-2 图片加载失败已引 imgpage.load_failed（硬编码零残留）"
else
  bad "T-2 imgpage.load_failed 引用缺失"
fi
IPVSEG=$(awk '/^struct ImagePageView/,/^final class SplashState/' "$SRC")
if echo "$IPVSEG" | grep -q '@EnvironmentObject private var langStore: LangStore'; then
  ok "T-3 ImagePageView 已声明 langStore 观察（切语言即时刷新）"
else
  bad "T-3 ImagePageView 缺 langStore 观察声明"
fi
LANGSEG=$(awk '/^final class LangStore/,/^enum Lang/' "$SRC")
if echo "$LANGSEG" | grep -q 'currentLocaleDidChangeNotification' \
   && echo "$LANGSEG" | grep -q 'self.followSystem'; then
  ok "T-4 LangStore 已监听 locale 变更（仅 followSystem 重解析）"
else
  bad "T-4 LangStore locale 变更监听缺失"
fi
# i18n 深检（2026-11-27 移植批，与 Web
# verify_rustweb.sh 第 7 节共源）：占位符跨包齐平
# （7a）+ 僵尸键反向扫描（7b）两道硬门禁 + 疑似
# 漏译警告（7c，不判红）。实现单源在
# scripts/i18n_deep_check.py，两脚本共读、禁止在
# 本文件再嵌副本——bridge.pair_expired 曾从原生
# 无此门滑过、被 Web CI 抓到，本组补齐后原生组版
# 即可自查。共源输出逐行透传（文案与 Web 侧同
# 式），再按结论行登记 ok/bad；脚本异常（无结论
# 行）按 fail-closed 判红。
DEEPOUT=$(python3 ../../../../scripts/i18n_deep_check.py \
  "$PWD/../../web" "$PWD/../../../.." 2>&1)
DEEPCODE=$?
echo "$DEEPOUT" | sed 's/^/  /'
if echo "$DEEPOUT" | grep -q '^✓ 占位符跨包一致'; then
  ok "占位符跨包一致（i18n 深检 7a，与 Web 共源）"
elif echo "$DEEPOUT" | grep -q '^✗ 占位符不一致'; then
  bad "占位符跨包不一致（见上 ✗ 行，i18n 深检 7a）"
else
  bad "i18n 深检 7a 未得出结论（脚本异常，退出码 $DEEPCODE）"
fi
if echo "$DEEPOUT" | grep -q '^✓ 僵尸键扫描'; then
  ok "僵尸键扫描零僵尸（i18n 深检 7b，与 Web 共源）"
elif echo "$DEEPOUT" | grep -q '^✗ 僵尸键：'; then
  bad "存在僵尸键（见上 ✗ 行，删键或补引用；i18n 深检 7b）"
else
  bad "i18n 深检 7b 未得出结论（脚本异常，退出码 $DEEPCODE）"
fi
# I5：7c 豁免登记棘轮——与 zh-CN 同值且含汉字的键
# 须逐键定性登记于 scripts/i18n_7c_exemptions.txt
# （繁简同形 / 日汉同形词两类，真漏译为零，定性表
# 见 impl_i18n_i4i5.md）；实算集与登记集恒等，新增
# 同值未登记或登记失效（译文已改而登记未销）皆红。
if python3 - "$LANGDIR" ../../../../scripts/i18n_7c_exemptions.txt <<'PYEOF'
import json, re, sys
codes = ["zh-TW", "ja-JP", "en-US", "ko-KR"]
packs = {}
for c in ["zh-CN"] + codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        packs[c] = json.load(f)
base = packs["zh-CN"]
HAN = re.compile(r"[一-鿿]")
computed = set()
for c in codes:
    for k in base:
        if packs[c].get(k) == base[k] \
                and HAN.search(base[k] or ""):
            computed.add(f"{c}:{k}")
registered = set()
for line in open(sys.argv[2], encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        registered.add(line)
if computed != registered:
    print("  7c 未登记同值:",
          ", ".join(sorted(computed - registered)))
    print("  7c 登记失效:",
          ", ".join(sorted(registered - computed)))
    sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "7c 同值含汉字键全部登记豁免（棘轮：实算集 == 登记集）"
else
  bad "7c 豁免登记与实算不一致（见上两行，定性后登记或改译）"
fi
# I4：斜杠表换键锁——24 项 titleLangKey/subLangKey
# 存键 + 计算属性解析面在位（与 Web 存键同构）。
SLSEG=$(awk '/^enum SlashCmds/,/^    \]$/' "$SRC")
if [ "$(echo "$SLSEG" | grep -c 'titleLangKey: "slash\.')" = 24 ] \
   && [ "$(echo "$SLSEG" | grep -c 'subLangKey: "slash\.')" = 24 ] \
   && has 'var title: String { Lang.t(titleLangKey) }' "$SRC" \
   && has 'var sub: String { Lang.t(subLangKey) }' "$SRC"; then
  ok "I4 斜杠表 24 项已存键（titleLangKey/subLangKey + Lang.t 解析面）"
else
  bad "I4 斜杠表换键不全（24 组键字段与解析面须齐备）"
fi
# AUD-C-04：EditorView 头部须有 LangStore 观察声明
# （编辑器整树含斜杠面板随语言重演算）。
EVSTART=$(grep -n '^struct EditorView' "$SRC" | cut -d: -f1)
EVLANG=$(awk -v s="$EVSTART" 'NR>=s && /@EnvironmentObject private var langStore: LangStore/{print NR; exit}' "$SRC")
if [ -n "$EVLANG" ] && [ $((EVLANG - EVSTART)) -lt 60 ]; then
  ok "AUD-C-04 EditorView 已声明 langStore 观察（头部 60 行内）"
else
  bad "AUD-C-04 EditorView 缺 langStore 观察声明"
fi
# I4/I5 扫尾零残留：本批换键的旧硬编码原文逐条归零
# （任一回潮即红）。
sweep=0
for pat in 'Text("未找到匹配命令")' '.alert("编辑链接"' \
  '.confirmationDialog("头像"' '.confirmationDialog("添加附件"' \
  'title: "删除块"' 'Text("PDF 将生成文件，可通过分享存储或打印。")' \
  'addError("PDF 导出失败")' 'Text("附件（无文件）")' \
  '.navigationTitle("图文文本")' '.accessibilityLabel("完成")' \
  '"\(editor.item.ago) · 共'; do
  if grep -qF "$pat" "$SRC"; then
    echo "  sweep residual: $pat"
    sweep=1
  fi
done
if grep -qF 'string: "无标题"' TitleTextField.swift; then
  echo "  sweep residual: TitleTextField string: \"无标题\""
  sweep=1
fi
if [ "$sweep" = 0 ]; then
  ok "I4/I5 扫尾旧硬编码原文零残留（12 锚）"
else
  bad "I4/I5 扫尾有旧原文残留（见上 sweep residual 行）"
fi
# I5：CJK 全量门转正（AUD-C-05）——全 App *.swift 的
# CJK 字符串字面量逐个归类：未归类即红。归类规则
# （与立项 §3 口径一致，逐类登记、不得为过断言增补）：
#  文件级豁免：桥自检夹具/场景（证据面）、启动步名、
#    运维步名（标识面）四文件；
#  DiagLog.shared.log/logOnce 调用括号域内 = Diag
#    载荷；failNote: 实参同（ImageLoader 失败注记）；
#  函数体豁免（数据面/证据面）：wikiKey 哨兵比较、
#    Diag 导出组装（envHeaderText/buildExportFile）、
#    天气对照表（cityToCn/caiyunCondition）、导出物
#    生成（mdBlock/htmlBlock）、内容模板（applyInline
#    Slash/applyLink 体内且值属模板集、图文卡占位值）；
#  行/值豁免：SlashCmds kw 过滤字段、timing 读数赋值
#    （含续行）、语言本名三值、平台名匹配（哔哩哔哩）、
#    导出文件名（此刻备份_ 前缀）、救援锚步读数、
#    seedMemos 种子声明域（多行串整块、示例内容）。
#  （原 W2「此刻启动图标」开屏图标 a11y 白名单已于
#  0.9.64 组版换键 app.splash_icon_aria 后销账。）
if python3 - . <<'PYEOF'
import re, sys, pathlib
CJK = re.compile(r'[一-鿿]')
app = pathlib.Path(sys.argv[1])

def read_string(text, i):
    if text.startswith('"""', i):
        j = text.find('"""', i + 3)
        if j < 0: j = len(text)
        return text[i + 3:j], min(j + 3, len(text))
    j = i + 1; buf = []
    while j < len(text):
        c = text[j]
        if c == "\\":
            if j + 1 < len(text) and text[j + 1] == "(":
                depth = 1; j += 2
                while j < len(text) and depth > 0:
                    if text[j] == '"':
                        _, j = read_string(text, j); continue
                    if text[j] == "(": depth += 1
                    elif text[j] == ")": depth -= 1
                    j += 1
                buf.append("\x00"); continue
            buf.append(text[j + 1] if j + 1 < len(text) else "")
            j += 2; continue
        if c == '"':
            return "".join(buf), j + 1
        buf.append(c); j += 1
    return "".join(buf), j

def literals(text):
    out = []; i = 0; n = len(text); line = 1
    while i < n:
        c = text[i]
        if c == "\n": line += 1; i += 1; continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            if j < 0: break
            line += text[i:j + 2].count("\n"); i = j + 2; continue
        if c == '"':
            lit, ni = read_string(text, i)
            out.append((lit, i, ni, line))
            line += text[i:ni].count("\n"); i = ni; continue
        i += 1
    return out

def decl_array_span(text, name):
    m = re.search(r"\bstatic let " + re.escape(name)
                  + r"\b", text)
    if not m: return None
    eq = text.find("=", m.end())
    if eq < 0: return None
    br = text.find("[", eq)
    if br < 0: return None
    return (m.start(), paired(text, br, "[", "]"))

def paired(text, open_idx, oc, cc):
    depth = 0; i = open_idx
    while i < len(text):
        c = text[i]
        if c == '"':
            _, i = read_string(text, i); continue
        if c == oc: depth += 1
        elif c == cc:
            depth -= 1
            if depth == 0: return i
        i += 1
    return len(text)

def call_spans(text, pat):
    return [(m.start(), paired(text, m.end() - 1, "(", ")"))
            for m in re.finditer(pat, text)]

def func_span(text, name):
    m = re.search(r"\bfunc\s+" + re.escape(name) + r"\s*\(", text)
    if not m: return None
    brace = text.find("{", m.end())
    if brace < 0: return None
    return (m.start(), paired(text, brace, "{", "}"))

FILE_EXEMPT = {"MomentBridgeUITest.swift",
               "MomentBridgeScenarios.swift",
               "MomentLaunch.swift", "MomentOps.swift"}
FUNC_SPANS = {"wikiKey", "envHeaderText", "buildExportFile",
              "cityToCn", "caiyunCondition",
              "mdBlock", "htmlBlock",
              "applyInlineSlash", "applyLink"}
TEMPLATE_VALUES = {"==文字==", "$文字$", "文字"}
PH_TEMPLATES = {"点击输入文字", "点击输入说明文字"}
AUTONYMS = {"繁體中文", "日本語", "简体中文"}
PLATFORM_NAMES = {"哔哩哔哩"}

unclassified = []
for p in sorted(app.glob("*.swift")):
    text = p.read_text(encoding="utf-8")
    if p.name in FILE_EXEMPT:
        continue
    diag_spans = call_spans(
        text, r"DiagLog\.shared\.log(?:Once)?\(")
    fspans = []
    if p.name == "MomentApp.swift":
        for fn in FUNC_SPANS:
            s = func_span(text, fn)
            if s: fspans.append((fn, s))
        sd = decl_array_span(text, "seedMemos")
        if sd: fspans.append(("seedMemos", sd))
    lines = text.splitlines()
    for val, st, en, ln in literals(text):
        if not CJK.search(val): continue
        if any(a <= st < b for a, b in diag_spans): continue
        if p.name == "MomentApp.swift":
            hit = next((fn for fn, (a, b) in fspans
                        if a <= st < b), None)
            if hit:
                if hit in ("applyInlineSlash", "applyLink") \
                        and val not in TEMPLATE_VALUES \
                        and not val.startswith("[链接文字]("):
                    unclassified.append(
                        (p.name, ln, val[:50]))
                continue
            if val in AUTONYMS: continue
            if val in PH_TEMPLATES: continue
            if val in PLATFORM_NAMES: continue
            if "此刻备份_" in val: continue
            line = lines[ln - 1]
            window = "\n".join(lines[max(0, ln - 4):ln])
            if re.search(r'\btiming\s*=', window) \
                    or 'var timing' in window: continue
            if 'failNote:' in line: continue
            if 'kw: "' in line: continue
        if p.name == "MomentRescue.swift" \
                and "锚步" in val: continue
        unclassified.append((p.name, ln, val[:50]))
if unclassified:
    for fn, ln, s in unclassified:
        print(f"  unclassified CJK @{fn}:{ln}: {s}")
    sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "I5 全量 CJK 门：全 App 字面量逐个归类（未归类零）"
else
  bad "I5 全量 CJK 门有未归类字面量（见上 unclassified 行）"
fi

echo "[10] 审计二轮 G+H 与追加项（0.9.43）"
# G 分组方案 A：组序 外观→数据→天气→关于（组头
# 键在文件中的源码次序）。
ln_app=$(grep -n '"settings.appearance"' "$SRC" | head -1 | cut -d: -f1)
ln_dat=$(grep -n '"settings.data"' "$SRC" | head -1 | cut -d: -f1)
ln_wea=$(grep -n '"settings.weather"' "$SRC" | head -1 | cut -d: -f1)
ln_abo=$(grep -n '"settings.about"' "$SRC" | head -1 | cut -d: -f1)
if [ -n "$ln_app" ] && [ -n "$ln_dat" ] && [ -n "$ln_wea" ] \
   && [ -n "$ln_abo" ] && [ "$ln_app" -lt "$ln_dat" ] \
   && [ "$ln_dat" -lt "$ln_wea" ] \
   && [ "$ln_wea" -lt "$ln_abo" ]; then
  ok "G 设置组序 外观<数据<天气<关于"
else
  bad "G 设置组序不对：外观=$ln_app 数据=$ln_dat 天气=$ln_wea 关于=$ln_abo"
fi
SV=$(awk '/^struct SettingsView/,/^struct BackupView/' "$SRC")
# S1 组距分档：数据组头 40 / 天气组头 32 / 关于
# 组头 32（0.9.51 天气批：天气组改导航卡后关于
# 组头按导航卡口径重推 40→32，impl_weather_settings
# 记账；本期望由主线合流时同步）。
if echo "$SV" | grep -A1 '"settings.data"' | grep -q 'topPad: 40' \
   && echo "$SV" | grep -A1 '"settings.weather"' | grep -q 'topPad: 32' \
   && echo "$SV" | grep -A1 '"settings.about"' | grep -q 'topPad: 32'; then
  ok "S1 组头 topPad 分档 40/32/32"
else
  bad "S1 组头 topPad 分档缺失"
fi
# S8 组头 uppercase 接线（SectionHeader 块内）。
SHDR=$(awk '/^struct SectionHeader/,/^struct BackupSectionTitle/' "$SRC")
if echo "$SHDR" | grep -q 'textCase(.uppercase)'; then
  ok "S8 组头 uppercase 在位"
else
  bad "S8 组头缺 textCase(.uppercase)"
fi
# S3/S6 备份专用组件在位。
if has 'struct BackupSectionTitle' "$SRC" \
   && has 'struct BackupRow' "$SRC"; then
  ok "S3/S6 BackupSectionTitle/BackupRow 在位"
else
  bad "S3/S6 备份专用组件缺失"
fi
# S4/S5：备份 toast 全宽条（overlayCard panel、旧
# 999 胶囊零残留）、hero radius panelHero、成功色令牌。
BV=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
if echo "$BV" | grep -q 'overlayCard(radius: Radius.panel)' \
   && ! echo "$BV" | grep -q 'glassCard(radius: 999)' \
   && echo "$BV" | grep -q 'glassCard(radius: Radius.panelHero)'; then
  ok "S4/S5 备份 toast 全宽条 + hero radius 30"
else
  bad "S4/S5 备份 toast/hero 形态不对"
fi
if has 'dyn(0x34C759, 0x34C759)' "$SRC"; then
  ok "S4 成功色令牌 T.success = #34C759"
else
  bad "S4 成功色令牌 T.success 缺失"
fi
# S2/S7 诊断：当天日志组头 topPad 32、日志视窗
# 页终端卡底距 40+safe。
DV=$(awk '/^struct DiagView/,/^struct DiagLogPage/' "$SRC")
if echo "$DV" | grep -q 'topPad: 32'; then
  ok "S2 诊断当天日志组头 topPad 32"
else
  bad "S2 诊断当天日志组头 topPad 不对"
fi
if has '40 + geo.safeAreaInsets.bottom' "$SRC"; then
  ok "S7 日志页终端卡底距 40+safe 在位"
else
  bad "S7 日志页终端卡底距口径缺失"
fi
# M8：设置族分隔线 borderSoft 化——旧
# glassBorder.opacity(0.5) 全文件零残留。
if grep -q 'glassBorder.opacity(0.5)' "$SRC"; then
  bad "M8 旧分隔线色 glassBorder.opacity(0.5) 残留"
else
  ok "M8 分隔线已全换 T.borderSoft"
fi
# H1 分组日期边界 ≤7/≤30。
if has 'if days <= 7 { return "week" }' "$SRC" \
   && has 'if days <= 30 { return "month" }' "$SRC"; then
  ok "H1 分组边界 ≤7/≤30"
else
  bad "H1 分组边界口径缺失"
fi
# H2 折叠态整卡点按优先走展开提示。
if has 'if let hint = expandHint' "$SRC"; then
  ok "H2 折叠卡整卡点按展开在位"
else
  bad "H2 折叠卡整卡点按语义缺失"
fi
# H3 网格/窄屏空状态三态：搜索态键两处在位
# （gridEmpty 与 emptyRow 各一）。
n_st=$(grep -c 'empty.search_title' "$SRC")
n_cs=$(grep -c 'empty.clear_search' "$SRC")
if [ "$n_st" -ge 2 ] && [ "$n_cs" -ge 2 ]; then
  ok "H3 搜索零结果态两处在位（网格+窄屏）"
else
  bad "H3 搜索零结果态不全：title=$n_st clear=$n_cs"
fi
# H5 置顶刷新 updatedAt 的机制在位：togglePin 经
# persist 落盘，persist 无条件刷新 updatedAt。
TP=$(awk '/func togglePin/,/^    }$/' "$SRC")
if echo "$TP" | grep -q 'persist(it)' \
   && has 'it.updatedAt = Clock.isoNow()' "$SRC"; then
  ok "H5 置顶经 persist 刷新 updatedAt"
else
  bad "H5 置顶刷新 updatedAt 机制缺失"
fi
# 追加·小差 6：分组遇见序（byBucket 扫描成序、
# 旧固定序辅助量零残留）。
if has 'if byBucket\[b\] == nil { names.append(b) }' "$SRC" \
   && ! grep -q 'bucketNewest' "$SRC"; then
  ok "小差6 分组遇见序在位、旧序辅助量零残留"
else
  bad "小差6 分组序实现不对"
fi
# 追加·小差 9：方卡药丸（旧 squareFoldRow 零
# 残留、squareFoldPill 在位）。
if ! grep -q 'squareFoldRow' "$SRC" \
   && has 'squareFoldPill' "$SRC"; then
  ok "小差9 方卡展开药丸在位、旧实现零残留"
else
  bad "小差9 方卡药丸形态不对"
fi
# 追加·微差 11/12：标题上限 flex 推导式在位。
if has 'mainW \* 0.6' "$SRC"; then
  ok "微差11/12 标题上限 flex 推导在位"
else
  bad "微差11/12 标题上限推导缺失"
fi
# 追加·小差 7：摘要 strip_markdown 全规则链在位。
if has 'static func stripFootnoteDef' "$SRC" \
   && has 'static func stripMarkdown' "$SRC" \
   && has 'static func stripTagTokens' "$SRC"; then
  ok "小差7 摘要 strip 规则链在位"
else
  bad "小差7 摘要 strip 规则链缺失"
fi
# 追加·小差 10：附件清单判图在位。
if has 'static func attNameIsImage' "$SRC" \
   && has 'manifestNames' "$SRC"; then
  ok "小差10 附件清单判图在位"
else
  bad "小差10 附件清单判图缺失"
fi
# 追加·微差 16：多篇待删集（单槽旧字段零残留、
# 标记读面在位）。
if has 'pendingDeletions' "$SRC" \
   && has 'var deletedAtMs' "$SRC" \
   && ! grep -q 'private var deletionWork:' "$SRC"; then
  ok "微差16 多篇待删集在位、单槽零残留"
else
  bad "微差16 待删实现不对"
fi

echo "[11] 修复批 J1（0.9.44）：跨块导航/整页落焦/MD 公式/斜杠四缺/高亮/反链/判图 MIME/底表"
# J1-1 跨块导航机制链在位（按键钩 → handleKey →
# crossBlockArrow → textUnits 扁平链 + 弱注册表 +
# TextKit 2 行量测）。
if has 'func handleKey' "$SRC" \
   && has 'func crossBlockArrow' "$SRC" \
   && has 'func textUnits' "$SRC" \
   && has 'func registerTV' "$SRC" \
   && has 'enumerateTextLayoutFragments' "$SRC" \
   && has 'EDIT caret cross-block' "$SRC"; then
  ok "J1-1 跨块导航机制链在位"
else
  bad "J1-1 跨块导航机制缺件"
fi
# J1-2 热区整页化：固定 220 高旧形零残留、弹性热
# 区 + 三形态 minHeight 占位账在位（账值随 L-7
# 正文顶 168→155 同步改判：208/192/200 →
# 195/179/187）。
if ! grep -q 'frame(height: 220)' "$SRC" \
   && has 'minHeight: 220, maxHeight: .infinity' "$SRC" \
   && has 'ui.viewH - 195' "$SRC" \
   && has 'ui.viewH - 179' "$SRC" \
   && has 'ui.viewH - 187' "$SRC" \
   && has 'EDIT canvas focus ->' "$SRC"; then
  ok "J1-2 整页落焦（弹性热区 + 三形态占位账）"
else
  bad "J1-2 热区整页化口径不对"
fi
# J1-3 公式：块级可横滚（mnwrap/max-content/指示
# 器关）+ 失败色令牌；行内 MathImageStore 快照链
# + mathTex run 键。
if has 'class MathImageStore' "$SRC" \
   && has 'mnwrap' "$SRC" \
   && has 'width: max-content' "$SRC" \
   && has 'font-size: 16px' "$SRC" \
   && has 'showsHorizontalScrollIndicator = false' "$SRC" \
   && has 'T.mathFail' "$SRC" \
   && has '"mathTex"' "$SRC"; then
  ok "J1-3 公式块级横滚 + 行内快照链在位"
else
  bad "J1-3 公式实现缺件"
fi
# J1-4 斜杠四缺：rows 单源（旧 filtered 零残留）、
# slashSel + moveSel、命中高亮令牌 fillAccent18、
# ty 字段进 haystack。
if has 'static func rows' "$SRC" \
   && ! grep -q 'static func filtered' "$SRC" \
   && has 'func slashMoveSel' "$SRC" \
   && has 'slashSel' "$SRC" \
   && has 'fillAccent18' "$SRC" \
   && has 'c.ty' "$SRC"; then
  ok "J1-4 斜杠 rows 单源 + 键盘选中 + 命中高亮"
else
  bad "J1-4 斜杠四缺实现不对"
fi
# J1-5 高亮 ==：MdRender push highlight 键 +
# Marks fillHighlightUI 渲染 + 令牌值对 Web。
if has '"highlight": true' "$SRC" \
   && has 'fillHighlightUI' "$SRC" \
   && has 'dynA(0xFFCC00, 0.25, 0xFFCC00, 0.25)' "$SRC"; then
  ok "J1-5 == 高亮渲染（fill-highlight 底 + 600）"
else
  bad "J1-5 高亮渲染缺件"
fi
# J1-6 MD 预览图片专用视图（自然比例 + radius 10，
# 不走填充裁切的 ItemImageView）。沿革：原锁
# scaledToFit() 字面；审计批 3（AUD-D-01）MD
# 图承载换 AnimImageView 的 fit 模式（自然比
# 例语义由其 sizeThatFits 复刻），断言改段内
# 锚——专用视图 + fit 承载在段内、填充裁切不入段。
MDJ1=$(sed -n '/^struct MdImageView/,/^struct [A-Z]/p' "$SRC")
if has 'struct MdImageView' "$SRC" \
   && has 'MdImageView(urlString: src' "$SRC" \
   && [ "$(printf '%s' "$MDJ1" | grep -c 'AnimImageView(image:')" = 1 ] \
   && [ "$(printf '%s' "$MDJ1" | grep -c 'scaleAspectFit')" = 1 ] \
   && [ "$(printf '%s' "$MDJ1" | grep -c 'scaleAspectFill')" = 0 ]; then
  ok "J1-6 MD 预览图 MdImageView 在位（AnimImageView fit 承载）"
else
  bad "J1-6 MD 预览图未换专用视图"
fi
# J1-7 反链管线：四段在位、旧 200 字上限零残留；
# 形态半边（↗ 前缀 + 顶分隔扁平行）。
if has 'stripBacktickSpans' "$SRC" \
   && has 'stripEscapedWiki' "$SRC" \
   && has 'scanWikiTargets' "$SRC" \
   && ! grep -q 'inner.count > 200' "$SRC" \
   && has 'Text("↗")' "$SRC"; then
  ok "J1-7 wiki 管线整段重写 + 反链扁平形态"
else
  bad "J1-7 反链管线/形态不对"
fi
# J1-8 判图 MIME 优先：FFI attachmentTypesJson 接
# 线 + attIsImage 双表 + 旧 imageExts 表零残留。
if has 'attachmentTypesJson' "$SRC" \
   && has 'func attIsImage' "$SRC" \
   && has 'refreshAttachmentTypes' "$SRC" \
   && ! grep -q 'imageExts' "$SRC"; then
  ok "J1-8 判图 MIME 优先（双表 + FFI 接线）"
else
  bad "J1-8 判图 MIME 实现不对"
fi
# J1-9 底表 padding 账：BackupView 段内卡底距
# 14+safe（Web panels.css 静态账）。
BV2=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
if echo "$BV2" | grep -q '14 + geo.safeAreaInsets.bottom'; then
  ok "J1-9 底表卡底距 14+safe 在位"
else
  bad "J1-9 底表 padding 账缺失"
fi
# J1-10 行内公式承载：MdTextGroupView 在位（只读
# UITextView、inset/padding 清零、shouldInteractWith
# 恒 false 转发），MdSegsView/MdBlockView 段内旧
# 形态 Text(AttributedString(MdRender 直喂零残留
# （SwiftUI Text 无附件渲染路径，deepdive 定性）。
SEG1=$(awk '/^struct MdSegsView/,/^struct MdBlockView/' "$SRC")
SEG2=$(awk '/^struct MdBlockView/,/^struct MdCalloutView/' "$SRC")
if has 'struct MdTextGroupView' "$SRC" \
   && has 'shouldInteractWith' "$SRC" \
   && has 'textContainerInset = .zero' "$SRC" \
   && has 'lineFragmentPadding = 0' "$SRC" \
   && echo "$SEG1" | grep -q 'MdTextGroupView(' \
   && echo "$SEG2" | grep -q 'MdTextGroupView(' \
   && ! echo "$SEG1" | grep -q 'Text(AttributedString' \
   && ! echo "$SEG2" | grep -q 'Text(AttributedString'; then
  ok "J1-10 行内公式承载换 UITextView（旧 Text 直喂零残留）"
else
  bad "J1-10 行内公式承载未换/旧形态残留"
fi
# 0.9.46 斜杠公式命令（原生增强，原版无此二项）：
# 定义两项（ty 对渲染面口径）+ mathInline 入行内
# 分发集 + mathBlock 产出 $$ 围栏三行、光标偏移 3。
if has 'act: "mathBlock", oid: "mathBlock", ty: "math_block"' "$SRC" \
   && has 'act: "mathInline", oid: "mathInline", ty: "inline_math"' "$SRC" \
   && has '"highlight", "link", "mathInline"' "$SRC" \
   && grep -qF '"$$\n\n$$"' "$SRC" \
   && has 'pendingCaretOffset = 3' "$SRC"; then
  ok "0.9.46 斜杠公式块/行内公式（定义 + 分发 + 围栏三行产出）"
else
  bad "0.9.46 斜杠公式命令缺件"
fi

echo "[12] 初始化环防回归（0.9.44 热修）：DiagLog 零依赖"
# 0.9.43 点开闪退定因：LangStore.init 记 Diag →
# loadIfNeeded 经 Fmt.fullStamp 回读 LangStore.shared
# → dispatch_once 递归锁 SIGTRAP。红线：DiagLog 类
# 体内（注释行除外）不得出现 Fmt./LangStore/Lang.t(
# 引用；归档戳走 Self.diagStamp。
DIAGBODY=$(awk '/^final class DiagLog/,/^struct FlowLayout/' "$SRC" | grep -v '^[[:space:]]*//')
if ! echo "$DIAGBODY" | grep -q 'Fmt\.' \
   && ! echo "$DIAGBODY" | grep -q 'LangStore' \
   && ! echo "$DIAGBODY" | grep -q 'Lang\.t(' \
   && has 'static func diagStamp' "$SRC"; then
  ok "J12-1 DiagLog 零依赖（无 Fmt/LangStore/Lang.t 引用，diagStamp 在位）"
else
  bad "J12-1 DiagLog 出现回读单例引用（初始化环风险）"
fi
# J12-2 当天环容量双端同值（2026-11-28 用户裁定
# 300→2000，定案 diag_reachback_attribution.md）：
# 原生 appendEntry 裁剪点与 Web diag.rs CAP 是同一
# 机制事实的两端，任一端漂移即红（与 verify_
# rustweb §20 同锁对侧）。
J12WEBCAP=$(grep -oE 'const CAP: usize = [0-9]+' ../../web/src/diag.rs | grep -oE '[0-9]+$')
if echo "$DIAGBODY" | grep -q 'today.count > 2000' \
   && echo "$DIAGBODY" | grep -q 'today.count - 2000' \
   && [ "$J12WEBCAP" = "2000" ]; then
  ok "J12-2 Diag 当天环双端同值 2000（原生裁剪点 + Web CAP）"
else
  bad "J12-2 Diag 当天环容量双端漂移（原生须 >2000/-2000、Web CAP 须 2000，现 Web=$J12WEBCAP）"
fi

echo "[13] 自救机制 R1 + 热更新通道（0.9.45，规格 plan_native_rescue.md S1/S2/S3/S6/S9 + S13）"
# R13-1 哨兵文件 + 步名集中（S11#1）：LaunchStep
# 枚举含全步名；代码行无散写步名字面量（launchMark
# /loadStepMark/markScene 调用一律传常量）。
LS=$(awk '/^enum LaunchStep/,/^struct LaunchSentinel/' "$LAUNCH")
CODE=$(grep -v '^[[:space:]]*//' "$SRC")
if has 'launch-sentinel.json' "$LAUNCH" \
   && has 'enum LaunchStep' "$LAUNCH" \
   && echo "$LS" | grep -q '"开库·FFI"' \
   && echo "$LS" | grep -q '"读数据·列表"' \
   && echo "$LS" | grep -q '"读数据·解析"' \
   && echo "$LS" | grep -q '"再水化·待删"' \
   && echo "$LS" | grep -q '"附件名表"' \
   && echo "$LS" | grep -q '"附件类型"' \
   && echo "$LS" | grep -q '"首帧"' \
   && ! echo "$CODE" | grep -q 'launchMark("' \
   && ! echo "$CODE" | grep -q 'loadStepMark("' \
   && ! echo "$CODE" | grep -q 'markScene("'; then
  ok "R13-1 哨兵文件直写 + LaunchStep 步名集中（无散写字面量）"
else
  bad "R13-1 哨兵/步名集中缺失或有散写步名字面量"
fi
# R13-2 判定前移（S11#2）：judgePreviousLaunch 全
# 文件恰两处（定义 + Library.init 调用），ListView
# 段无判定调用（防旧点位回潮双记）。
LV13=$(awk '/^struct ListView/,/^\/\/ ── 子页骨架/' "$SRC")
if [ "$(grep -c 'judgePreviousLaunch' "$SRC")" = 2 ] \
   && has 'judgePreviousLaunch()' "$SRC" \
   && ! echo "$LV13" | grep -q 'judgePreviousLaunch'; then
  ok "R13-2 判定前移 Library.init（旧 load 内判定点已删）"
else
  bad "R13-2 判定点位异常（应为定义 + init 调用恰两处）"
fi
# R13-3 bootMode 分流（S11#3）：根段 RescueView 在
# ListView 之前且以 bootIsSafe 互斥分流。
ROOT13=$(awk '/^struct MomentApp/,/^import SwiftUI/' "$SRC")
p_rescue=$(echo "$ROOT13" | grep -n 'RescueView(library' | head -1 | cut -d: -f1)
p_list=$(echo "$ROOT13" | grep -n 'ListView(library' | head -1 | cut -d: -f1)
if echo "$ROOT13" | grep -q 'bootIsSafe' \
   && [ -n "$p_rescue" ] && [ -n "$p_list" ] \
   && [ "$p_rescue" -lt "$p_list" ]; then
  ok "R13-3 根 ZStack 按 bootMode 分流（.safe 不构建 ListView）"
else
  bad "R13-3 根分流缺失或次序异常"
fi
# R13-4 安全模式动作符号（S11#4，R1 范围）：导出
# 走 DiagView 共用链、尝试正常启动/导出/ZIP 三动
# 作函数在位、只读打开留 R2 附着点标记。
RV=$(sed -n '/^\/\/ ── 安全模式页/,$p' "$RESCUE")
if echo "$RV" | grep -q 'buildExportFile' \
   && echo "$RV" | grep -q 'func tryNormal' \
   && echo "$RV" | grep -q 'func exportDiag' \
   && echo "$RV" | grep -q 'func exportZipAction' \
   && echo "$RV" | grep -q 'R2 附着点'; then
  ok "R13-4 RescueView 动作齐备（导出同链/正常启动/ZIP 置灰 + R2 附着点）"
else
  bad "R13-4 RescueView 动作符号缺失"
fi
# R13-5 红线扫描（S11#5）：RescueView 段内零可写
# FFI/库打开调用（只许 FileManager 元数据 + Diag
# 导出链 + 置灰守卫后的 exportZip 只读消费）。
if ! echo "$RV" | grep -q 'upsertMemoJson' \
   && ! echo "$RV" | grep -q 'removeMemo' \
   && ! echo "$RV" | grep -q 'putAttachment' \
   && ! echo "$RV" | grep -q 'MomentLibrary.open'; then
  ok "R13-5 RescueView 零可写 FFI 调用（红线）"
else
  bad "R13-5 RescueView 段内出现可写 FFI 调用"
fi
# R13-6 延后清单（S11#10）：reload 段不再直调
# refreshAttachmentTypes（走 defer 延后入口）；
# Diag loadIfNeeded 结构写盘走延后 flush（无同
# 步 persist() 直写行）。
RL13=$(awk '/private func reload\(lib/,/^    func retryLoad/' "$SRC")
DIAGLD=$(awk '/func loadIfNeeded/,/^    }[[:space:]]*$/' "$SRC")
if echo "$RL13" | grep -q 'deferRefreshAttachmentTypes()' \
   && ! echo "$RL13" | grep -q 'self\.refreshAttachmentTypes()' \
   && echo "$DIAGLD" | grep -q 'scheduleStructuralFlush()' \
   && ! echo "$DIAGLD" | grep -qE '^[[:space:]]*persist\(\)$'; then
  ok "R13-6 延后清单落地（类型表 defer + Diag 结构写盘延后）"
else
  bad "R13-6 延后清单未落地（reload 直调或 Diag 同步直写）"
fi
# R13-7 热更新通道（S13）：端点双源常量（Worker
# 主源 + GitHub Pages 备源）、白名单解析、guard
# 点 ≥3（附件类型/Diag 冻结/天气）、RescueView
# 含 fetch 入口、判定消费 forceSafeMode（M1 起
# 经 bootAppliedOps 快照消费——判定入口对
# cached() 的同份快照，B16-6 锁快照落点）。
OPSSEG=$(sed -n '/^final class OpsDirectives/,$p' "$OPS")
if has 'https://moment-ops.overtrees.workers.dev/ops.json' "$OPS" \
   && has 'https://overtrees.github.io/moment-ops/ops.json' "$OPS" \
   && echo "$OPSSEG" | grep -q '"disableSteps"' \
   && echo "$OPSSEG" | grep -q '"forceSafeMode"' \
   && echo "$OPSSEG" | grep -q 'func sanitize' \
   && echo "$OPSSEG" | grep -q 'OPS directives fetched src=' \
   && [ "$(grep -c 'OPS skip step=' "$SRC")" -ge 3 ] \
   && echo "$RV" | grep -q 'OpsDirectives.shared.fetch' \
   && has 'bootAppliedOps.forceSafeMode' "$SRC"; then
  ok "R13-7 热更新指令通道（双源/白名单/guard ≥3/fetch 入口/判定消费）"
else
  bad "R13-7 热更新通道缺件（端点/白名单/guard/入口）"
fi
# R13-8 文件拆分（0.9.45 拆分批，拒绝上帝文件）：
# 三新文件在位且各自含定义；MomentApp.swift 内无
# 定义残留（只许引用）。
if [ -f "$LAUNCH" ] && [ -f "$OPS" ] && [ -f "$RESCUE" ] \
   && has 'enum LaunchStep' "$LAUNCH" \
   && has 'enum LaunchSentinelStore' "$LAUNCH" \
   && has 'final class OpsDirectives' "$OPS" \
   && has 'struct RescueView' "$RESCUE" \
   && ! has 'enum LaunchStep' "$SRC" \
   && ! has 'enum LaunchSentinelStore' "$SRC" \
   && ! has 'final class OpsDirectives' "$SRC" \
   && ! has 'struct RescueView' "$SRC"; then
  ok "R13-8 自救批三文件独立成文件（主文件零定义残留）"
else
  bad "R13-8 拆分不完整（新文件缺失或主文件仍有定义残留）"
fi
# R13-9 桥布防第三路消费（M2 §7.3 接线批）：标记
# 存储在 BOPS（diag 域双文件：活动标记 + 审计）；
# judgePreviousLaunch 段内 take() 消费 + 定源
# source: "bridge" + consumed/cleared 两行 Diag；
# 标记文件名字面只许在存储定义处出现（消费方不
# 散写路径）。
JUDGE13=$(sed -n '/private func judgePreviousLaunch/,/^    }$/p' "$SRC")
if has 'bridge-safe-mode-arm.json' "$BOPS" \
   && has 'bridge-safe-mode-arm-audit.json' "$BOPS" \
   && has 'enum BridgeSafeModeArmStore' "$BOPS" \
   && echo "$JUDGE13" | grep -q 'BridgeSafeModeArmStore.take()' \
   && echo "$JUDGE13" | grep -q 'source: "bridge"' \
   && echo "$JUDGE13" | grep -q 'RESCUE arm consumed id=' \
   && echo "$JUDGE13" | grep -q 'RESCUE arm cleared id=' \
   && [ "$(grep -c 'bridge-safe-mode-arm' "$SRC")" = 0 ]; then
  ok "R13-9 桥布防第三路（判定点消费恰一次 + 转审计 + 双行 Diag）"
else
  bad "R13-9 桥布防消费点缺失或标记路径散写"
fi
# R13-10 哨兵写串行化（救援完整性批，审计 §5.2
# c/d）：LaunchSentinelStore.update（锁内读改写）
# 在位；主文件零 LaunchSentinelStore.save 直调
# （全部改写点收敛经 update，纯读 load 不在此
# 列）；LaunchStep 含「场景·救援」步 + RescueView
# 在场推进该步（安全模式内强杀不再虚增 streak）。
if has 'static func update(' "$LAUNCH" \
   && has 'updateLock' "$LAUNCH" \
   && [ "$(grep -c 'LaunchSentinelStore.save(' "$SRC")" = 0 ] \
   && echo "$LS" | grep -q '"场景·救援"' \
   && has 'markScene(LaunchStep.sceneRescue)' "$RESCUE"; then
  ok "R13-10 哨兵串行 update + 救援场景步（streak 虚增收口）"
else
  bad "R13-10 哨兵仍有无锁直写或救援场景步缺失"
fi
# R13-11 手动救援入口（救援完整性批，P2-3）：
# Library.enterRescueManually（source="manual" +
# RESCUE enter src=manual 行）+ DiagView 入口行直
# 引 diag.enter_rescue + BootMode source 注记含
# watchdog/manual 两值（注记与代码不再漂移）。
BOOTSEG=$(awk '/^enum BootMode/,/^}/' "$SRC")
if has 'func enterRescueManually()' "$SRC" \
   && has 'source: "manual"' "$SRC" \
   && has 'src=manual' "$SRC" \
   && has 'Lang.t("diag.enter_rescue")' "$SRC" \
   && echo "$BOOTSEG" | grep -q '"watchdog"' \
   && echo "$BOOTSEG" | grep -q '"manual"'; then
  ok "R13-11 手动救援入口（Diag 页 → src=manual + 注记补齐）"
else
  bad "R13-11 手动救援入口缺失或 BootMode 注记未补"
fi
# R13-12 SMOKE 失败行（救援完整性批，审计 §5.1
# a）：冷启失败路与成功行同前缀 SMOKE 行在位（发
# 版清单按 SMOKE 检索不漏失败冷启）。
if has 'SMOKE 冷启失败 v=' "$SRC" \
   && has 'SMOKE 冷启完成 v=' "$SRC"; then
  ok "R13-12 SMOKE 成功/失败双行（失败冷启可检索）"
else
  bad "R13-12 SMOKE 失败行缺失"
fi
# R13-13 哨兵/快照 schema 扩展（LCH-02 根治批，
# 设计 fix_launch_verdict_lch02.md §3.1）：哨兵
# streakStep/suspendedStep + 快照 streakStep 三
# 字段在位；两 struct 各一份自定义 init(from:)
# 且 decodeIfPresent( 恰 21 处（哨兵 7 字段 +
# 快照 14 字段全兜底——承重项：旧版文件缺键不
# 得解码失败回退/整环丢失；增删字段须同步改此
# 计数）；快照导出行附 streakStep=。
if [ "$(grep -c 'var streakStep: String = ""' "$LAUNCH")" = 2 ] \
   && has 'var suspendedStep: String = ""' "$LAUNCH" \
   && [ "$(grep -c 'init(from decoder: Decoder) throws' "$LAUNCH")" = 2 ] \
   && [ "$(grep -c 'decodeIfPresent(' "$LAUNCH")" = 21 ] \
   && grep -qF 'streakStep=\(s.streakStep' "$LAUNCH"; then
  ok "R13-13 哨兵/快照 schema（锚步+墓碑字段，decodeIfPresent 兜底 21 处）"
else
  bad "R13-13 哨兵 schema 扩展缺失或解码兜底不在位"
fi
# R13-14 streak 同一步锚定（LCH-02 根治批 §3.2）：
# judge 段含锚步比对 + 换锚/递增后锚步落盘 +
# 呈现字段同点赋值 + F2 注记（不可分）在行；
# launchDone 清零面含 streak 与 streakStep；
# 救援页 streak 行附锚步呈现。
LD13=$(awk '/private func launchDone/,/^    }$/' "$SRC")
if echo "$JUDGE13" | grep -q 'prevStep == s.streakStep' \
   && echo "$JUDGE13" | grep -q '\$0\.streakStep = prevStep' \
   && echo "$JUDGE13" | grep -q 'prevLaunchStreakStep = prevStep' \
   && echo "$JUDGE13" | grep -q '不可分，平台事实' \
   && echo "$LD13" | grep -q '\$0\.streak = 0' \
   && echo "$LD13" | grep -q '\$0\.streakStep = ""' \
   && has '锚步' "$RESCUE"; then
  ok "R13-14 streak 同一步锚定（换锚重计 + launchDone 清锚 + 锚步呈现）"
else
  bad "R13-14 streak 锚定缺失（比对/落盘/清锚/呈现任一不在位）"
fi
# R13-15 suspend/resume 保存恢复对 + 墓碑消费
# （LCH-02 根治批 §3.3）：launchSuspend 先记墓
# 碑再清标、launchResume 读墓碑恢复步名；judge
# 墓碑 warn 行在位且其后 6 行内清墓碑、无
# bootMode 赋值（只留痕不计数，静态核查）。
SUSP13=$(awk '/static func launchSuspend/,/^    }$/' "$SRC")
RESU13=$(awk '/static func launchResume/,/^    }$/' "$SRC")
TOMB13=$(echo "$JUDGE13" | grep -A6 '上次加载未完成即退后台')
if echo "$SUSP13" | grep -q 's\.suspendedStep = s\.step' \
   && echo "$RESU13" | grep -q 's\.suspendedStep' \
   && echo "$TOMB13" | grep -q '\$0\.suspendedStep = ""' \
   && ! echo "$TOMB13" | grep -q 'bootMode'; then
  ok "R13-15 suspend/resume 保存恢复对 + 墓碑只留痕不计数"
else
  bad "R13-15 墓碑机制缺失（保存/恢复/消费留痕任一不在位）"
fi

echo "[14] 拖拽按压引擎（0.9.47 第二轮根治 + 0.9.49 第三轮增补，定案 fix_drag_pickup_round2.md / audit_drag_pickup_round3.md）"
# J14-1 单识别器：全工程（主文件 + 引擎文件）代码
# 行中 UILongPressGestureRecognizer( 恰一处——每行
# 一枚识别器的旧结构整段已删，不得以任何形式回潮。
n_lp=$(cat "$SRC" "$DRAG" | grep -v '^[[:space:]]*//' \
       | grep -c 'UILongPressGestureRecognizer(')
if [ "$n_lp" = 1 ] && has 'final class DragPressEngine' "$DRAG" \
   && has 'static func engine(for' "$DRAG" \
   && has 'struct DragPressAnchor' "$DRAG"; then
  ok "J14-1 按压引擎单识别器（引擎/锚点在独立文件）"
else
  bad "J14-1 长按识别器计数=$n_lp（应 1）或引擎符号缺失"
fi
# J14-2 旧路零残留：DragPickupInstaller 定义与调
# 用在代码行中零命中（只许注释提及沿革）。
if ! cat "$SRC" "$DRAG" | grep -v '^[[:space:]]*//' \
     | grep -q 'DragPickupInstaller'; then
  ok "J14-2 旧 DragPickupInstaller 零残留（代码行）"
else
  bad "J14-2 旧 DragPickupInstaller 仍有代码残留"
fi
# J14-3 行级长按竞争清零：BlockRow 段内无
# .contextMenu（UIContextMenuInteraction 与拾起同
# 抢长按）；CardMenuGesture 已整段退役（0.9.49：
# 卡片改走引擎拾起、菜单骑拾起），全工程代码行
# 零残留（只许注释提及沿革）。
BROW=$(awk '/^struct BlockRow/,/^struct EditorView/' "$SRC")
if ! echo "$BROW" | grep -v '^[[:space:]]*//' \
     | grep -q '\.contextMenu' \
   && ! cat "$SRC" "$DRAG" | grep -v '^[[:space:]]*//' \
     | grep -q 'CardMenuGesture'; then
  ok "J14-3 BlockRow 无 .contextMenu 竞争、CardMenuGesture 零残留"
else
  bad "J14-3 BlockRow 仍有 .contextMenu 或 CardMenuGesture 残留"
fi
# J14-4 仲裁姿态（0.9.49 全放开）：与全部识别器并
# 行（引擎降为纯计时+位移判定，Web 按压计时器同
# 构）+ 命中过滤 + disarmed 留痕三件齐备。
if has 'shouldRecognizeSimultaneouslyWith' "$DRAG" \
   && has 'return gr === recognizer' "$DRAG" \
   && has 'shouldReceive touch' "$DRAG" \
   && has 'DRAG press disarmed' "$DRAG"; then
  ok "J14-4 并行全放开 + 命中过滤 + disarmed 留痕在位"
else
  bad "J14-4 引擎仲裁接法缺件（并行/过滤/留痕）"
fi
# J14-5 全链打点：attached/target（引擎侧）与
# pickup/menu show（行侧）、drop/cancel（引擎侧）
# 五点齐备——真机一次导出可定位死点。
if has 'DRAG engine attached' "$DRAG" \
   && has 'DRAG press target' "$DRAG" \
   && has 'DRAG drop id=' "$DRAG" \
   && has 'DRAG cancel id=' "$DRAG" \
   && has 'DRAG pickup id=' "$SRC" \
   && has 'DRAG menu show id=' "$SRC"; then
  ok "J14-5 拖拽全链打点五点齐备"
else
  bad "J14-5 拖拽打点缺失（下轮真机将无从定位）"
fi
# J14-6 菜单改由拾起呈现：blockMenuBlockId 状态 +
# 呈现层 + 拾起置位三点齐备（旧 contextMenu 项集的
# 行为等价承接面）。
if has '@Published var blockMenuBlockId' "$SRC" \
   && has 'private var blockMenuLayer' "$SRC" \
   && has 'editor.blockMenuBlockId = block.id' "$SRC" \
   && has 'func blockMenuPanel' "$SRC"; then
  ok "J14-6 类型转换菜单由拾起呈现（状态/呈现/置位齐备）"
else
  bad "J14-6 拾起菜单承接面缺失"
fi
# J14-7 构建接入：MomentDrag.swift 在构建脚本的
# primary 轮与链接行中在位（漏接 = 符号缺失构建红，
# 此断言锁其存在性口径）。
if grep -q 'MomentDrag.swift' "$SH" \
   && grep -q 'primary-file "$HERE/MomentDrag.swift"' "$SH" \
   && grep -q '"$OUT/drag.o"' "$SH"; then
  ok "J14-7 MomentDrag.swift 构建接入（primary + drag.o 链接）"
else
  bad "J14-7 构建脚本未接入 MomentDrag.swift"
fi
# J14-8 参数未动（0.9.49 红线）：拾起时长与按压期
# 位移容忍与 Web 逐项等值，不许以放宽参数掩盖真
# 因（audit_drag_pickup_round3 五.2）。
if has 'minimumPressDuration = 0.48' "$DRAG" \
   && has 'allowableMovement = 10' "$DRAG"; then
  ok "J14-8 拾起参数 0.48s/10pt 未动（Web 等值）"
else
  bad "J14-8 拾起参数被改动（0.48/10 为规格值）"
fi
# J14-9 全状态打点补全（0.9.49 补 0.9.47 留痕洞）：
# handle 入口状态行（state/ms/disp）+ began orphan
# + 无行命中留痕三件齐备——未拾起即失败也必须可
# 指认死法。
if has 'DRAG press state=' "$DRAG" \
   && has 'DRAG began orphan' "$DRAG" \
   && has 'DRAG press norow' "$DRAG" \
   && has 'DRAG press reject button' "$DRAG"; then
  ok "J14-9 全状态打点补全（state 行/orphan/拒绝路径）"
else
  bad "J14-9 状态打点缺件（下轮真机将重回盲区）"
fi
# J14-10 卡片武装（0.9.49，用户纠正口径）：BlockRow
# 的 dragAllowed 不再按卡型 disarm；拾起置位卡菜单
# （cardMenuBlockId）与选区收敛在行侧在位。
if ! echo "$BROW" | grep -v '^[[:space:]]*//' \
     | grep -q 'if isCardType { return false }' \
   && echo "$BROW" | grep -q 'editor.cardMenuBlockId = block.id' \
   && echo "$BROW" | grep -q 'convergeSelectionOnPickup'; then
  ok "J14-10 卡片块武装 + 卡菜单骑拾起 + 拾起收敛选区"
else
  bad "J14-10 卡片武装缺件（dragAllowed/卡菜单置位/收敛）"
fi
# J14-11 文本拖放关闭（0.9.49）：BlockTextView 关
# dragInteraction（lift 不再与拾起争）+ EditorModel
# 收敛函数在位。
if has 'tv.textDragInteraction?.isEnabled = false' "$SRC" \
   && has 'func convergeSelectionOnPickup' "$SRC"; then
  ok "J14-11 文本拖放 lift 关闭 + 收敛函数在位"
else
  bad "J14-11 文本拖放处置缺件（dragInteraction/收敛）"
fi
# J14-12 拾起行底恒常态（0.9.50 根治，定案
# fix_drag_pickup_visual.md）：rowBackground 函数
# 体内零 draggingId、零 glassTint——拖动态行盒换
# 底是「卡片拾起多出白色背景块」的根因（image/
# gallery 面在行盒内内缩 36pt、行盒底外凸成板；
# 文本块行盒即面亦凭空多一层白板），拾起反馈只
# 许由 LiftFrame + 缩放承担，此写法不得回潮。
ROWBG=$(echo "$BROW" | awk '/private var rowBackground/,/^    }/')
if [ -n "$ROWBG" ] \
   && ! echo "$ROWBG" | grep -q 'draggingId' \
   && ! echo "$ROWBG" | grep -q 'glassTint'; then
  ok "J14-12 拾起行底恒常态（rowBackground 无拖动态换底）"
else
  bad "J14-12 rowBackground 仍有拖动态换底（拾起白板将回潮）"
fi

echo "[15] 新建过渡第二轮根治（0.9.48，定案 fix_new_note_transition_round2.md）"
# T15-1 归组版本缓存（治 S1 趟基数）：缓存包装 +
# assembleGroups 在位；版本 bump 写点全集计数锁定
# （touchMemos = 定义 1 + 写点 7（R2/R3 批新增
# prepareNormalStart 清列表复位一处，见
# impl_rescue_r2r3.md）、touchManifest =
# 定义 1 + 写点 3——漏一处 bump 即归组过期）。
n_tm=$(grep -c 'touchMemos()' "$SRC")
n_tf=$(grep -c 'touchManifest()' "$SRC")
if has 'private func assembleGroups' "$SRC" \
   && has 'groupsCache.key == key' "$SRC" \
   && has 'private(set) var memosVersion' "$SRC" \
   && [ "$n_tm" = 8 ] && [ "$n_tf" = 4 ]; then
  ok "T15-1 归组按版本缓存（bump 写点全集 memos 7 + manifest 3）"
else
  bad "T15-1 归组缓存缺失或 bump 计数漂移（memos=$n_tm 应 8、manifest=$n_tf 应 4）"
fi
# T15-2 parseISO 共享 formatter（治 S1 单价）：Clock
# 段内 formatter 构造恰两处（两形态预建），且经锁。
CLK=$(awk '/^enum Clock/,/^}/' "$SRC")
n_fmt=$(echo "$CLK" | grep -c 'ISO8601DateFormatter()')
if [ "$n_fmt" = 2 ] && has 'isoFull' "$SRC" \
   && has 'isoLock' "$SRC"; then
  ok "T15-2 parseISO 共享 formatter（构造恰 2、锁串行）"
else
  bad "T15-2 formatter 构造=$n_fmt（应 2）或共享实例/锁缺失"
fi
# T15-3 头像离开首帧同步路径（治 S1 触发源）：
# loadAvatar 段内为后台队列读 + 在途去重 + CREATE
# avatar 打点，段内不得再有主线程同步回写形态。
AVT=$(awk '/func loadAvatar/,/^    }/' "$SRC")
if echo "$AVT" | grep -q 'DispatchQueue.global' \
   && echo "$AVT" | grep -q 'avatarLoadsInFlight' \
   && echo "$AVT" | grep -q 'CREATE avatar'; then
  ok "T15-3 loadAvatar 异步化（后台读/在途去重/回写主线程）"
else
  bad "T15-3 loadAvatar 仍同步或去重/打点缺失"
fi
# T15-4 首帧发布收敛（治 S2）：menuPanel 惰性门 +
# headerW 独立量测通道；EditorUI 的 headerW 发布
# 通道零残留（代码行无 ui.headerW）。
if has '@Published var menuBuilt' "$SRC" \
   && has 'if ui.menuBuilt {' "$SRC" \
   && has 'final class HeaderMeasure' "$SRC" \
   && ! echo "$CODE" | grep -q 'ui\.headerW'; then
  ok "T15-4 menuPanel 惰性 + headerW 自消费通道（旧发布通道零残留）"
else
  bad "T15-4 惰性门/量测通道缺失或 ui.headerW 残留"
fi
# T15-5 认领成功校验（治 S4）：claimInitialFocus +
# recordCreateClaim + 有界计数在位；旧「尝试前清
# 旗」形态零残留。
if has 'func claimInitialFocus' "$SRC" \
   && has 'func recordCreateClaim' "$SRC" \
   && has 'createClaimAttempts' "$SRC" \
   && ! echo "$CODE" | grep -q 'if initialClaim { editor?.wantsInitialFocus = false }'; then
  ok "T15-5 落焦认领校验 + 有界重试（旧静默清旗零残留）"
else
  bad "T15-5 认领校验缺失或旧清旗形态残留"
fi
# T15-6 CREATE 分段打点七点齐全：dest/listpass/
# avatar/claim/kb/settle 六行 + bodypass 计数入口。
if has 'CREATE dest' "$SRC" && has 'CREATE listpass' "$SRC" \
   && has 'CREATE avatar' "$SRC" && has 'CREATE claim' "$SRC" \
   && has 'CREATE kb' "$SRC" && has 'CREATE settle' "$SRC" \
   && has 'traceBodyPasses' "$SRC"; then
  ok "T15-6 CREATE 打点七点齐全（dest/listpass/avatar/claim/kb/settle/bodypass）"
else
  bad "T15-6 CREATE 打点缺项（下轮真机将无从定案）"
fi
# T15-7 focus 段口径修复：未记基点输出 na（取代旧
# 巨值/-1），settle 总账函数在位。
if has '"na"' "$SRC" && has 'func logCreateSettle' "$SRC" \
   && has 'func traceMs' "$SRC"; then
  ok "T15-7 分段未记基点输出 na + settle 总账在位"
else
  bad "T15-7 traceMs/settle 缺失（focus 段巨值缺陷未修）"
fi
# T15-8 键盘编排（治 S3）：内容层键盘安全区免疫 +
# 落定底距通道在位，单列底距账含 kbPad。
if has 'ignoresSafeArea(.keyboard, edges: .bottom)' "$SRC" \
   && has 'func settleKbPad' "$SRC" \
   && has '40 + ui.kbPad' "$SRC"; then
  ok "T15-8 编辑区键盘免疫 + kbPad 落定一次应用"
else
  bad "T15-8 键盘免疫/落定底距缺失"
fi

echo "[16] MCP 桥 M1+M2（连通 + 语义读写/运维动作，方案 plan_app_mcp_bridge.md，M2 定案 impl_bridge_m2.md）"
# B16-1 桥六文件 + 中继在位，构建名单/链接行齐全
# （build-app2.sh 桥六遍 .o 全在链接行）。
bridgefiles=1
for f in "$BPROTO" "$BTRANS" "$BRIDGE" "$BTOOLS" \
         "$BOPS" "$BSET" "$RELAY"; do
  [ -f "$f" ] || bridgefiles=0
done
if [ "$bridgefiles" = 1 ] \
   && has 'class BridgeRoom' "$RELAY" \
   && has 'bridge_protocol.o' "$SH" \
   && has 'bridge_transport.o' "$SH" \
   && has 'bridge_tools.o' "$SH" \
   && has 'bridge_ops.o' "$SH" \
   && has 'bridge_settings.o' "$SH" \
   && has '"$OUT/bridge.o"' "$SH"; then
  ok "B16-1 桥六文件 + 中继在位、构建六遍与链接行齐全"
else
  bad "B16-1 桥文件/中继缺失或构建名单不全"
fi
# B16-2 默认关 + 凭据落点：开关读 UserDefaults
# bridgeEnabled（缺省 false）；配对凭据类键只许
# 出现在 Keychain 段，UserDefaults 调用零混入。
if has 'forKey: "bridgeEnabled"' "$BRIDGE" \
   && has 'setEnabled' "$BRIDGE" \
   && has 'bridge.setEnabled' "$BSET" \
   && ! grep -E 'UserDefaults[^)]*(pairingId|scopes|clientKey)' \
        "$BRIDGE" "$BPROTO" "$BTRANS" "$BTOOLS" \
        "$BOPS" "$BSET" >/dev/null 2>&1; then
  ok "B16-2 默认关在位、凭据零 UserDefaults"
else
  bad "B16-2 默认关/凭据落点不对"
fi
# B16-3 工具集边界（M3a 改写，U3 批增补，
# 快照恢复批再增补）：
# 协议清单 37 件逐名在 BPROTO（M2 的 22 +
# 在席 4 + uitest 4 + rescue_arm_safe_mode 1
# + M3a 场景 3 + 量测 1 + metrics_drag_trace
# 1 + backup_restore_snapshot 1）；正文级 4 名（待端到端加密专项评
# 审，方案 §12.1/附录 B.3）在桥文件与中继的
# 代码行零注册（注释提及不算，与 [2] 的代码
# 行口径一致）。
toolsok=1
for t in bridge_status app_state diag_tail \
         diag_search notes_list notes_search notes_get \
         ops_get_effective ops_get_sources ops_refresh \
         ops_validate rescue_status \
         rescue_try_normal_start rescue_arm_safe_mode \
         settings_get \
         settings_set_language settings_set_toggle \
         settings_clear_weather_key notes_soft_delete \
         notes_restore_deleted notes_delete_permanent \
         editor_delete_block editor_move_block \
         editor_open editor_get_state \
         editor_focus_block editor_save_now \
         uitest_list_surfaces uitest_run \
         uitest_get_result uitest_measure \
         scenarios_list scenarios_run \
         scenarios_get_result metrics_create_settle \
         metrics_drag_trace backup_restore_snapshot; do
  grep -q "\"$t\"" "$BPROTO" || toolsok=0
done
bcode=$(grep -v '^[[:space:]]*//' "$BPROTO" "$BTRANS" \
        "$BRIDGE" "$BTOOLS" "$BOPS" "$BSET" "$RELAY")
forbidok=1
for t in notes_create editor_insert_block \
         editor_update_block editor_set_block_type; do
  echo "$bcode" | grep -q "\"$t\"" && forbidok=0
done
if [ "$toolsok" = 1 ] && [ "$forbidok" = 1 ]; then
  ok "B16-3 工具清单 37 件齐全、正文级未评审工具零注册"
else
  bad "B16-3 工具清单漂移或未开放工具混入注册"
fi
# B16-4 BRIDGE 打点清单（方案 §9.5）：start/state/
# pairing_started/paired/tool/tools_rejected/
# ops_refresh/revoked/error 齐全。
if has 'BRIDGE start enabled=' "$BRIDGE" \
   && has 'BRIDGE state ' "$BRIDGE" \
   && has 'BRIDGE pairing_started fp=' "$BRIDGE" \
   && has 'BRIDGE paired scopes=' "$BRIDGE" \
   && has 'BRIDGE tool ' "$BRIDGE" \
   && has 'BRIDGE tools_rejected reason=ops_disabled' "$BRIDGE" \
   && has 'BRIDGE error code=' "$BRIDGE" \
   && has 'BRIDGE revoked via=' "$BRIDGE" \
   && has 'BRIDGE ops_refresh source=' "$BOPS"; then
  ok "B16-4 BRIDGE 打点清单齐全"
else
  bad "B16-4 BRIDGE 打点缺项"
fi
# B16-5 OPS guard：桥步名登记 + 协调器启动消费
# isDisabled(OpsStep.bridge)；安全模式受限分发在位。
if has 'static let bridge = "MCP桥"' "$OPS" \
   && has 'isDisabled(OpsStep.bridge)' "$BRIDGE" \
   && has 'safe_mode_limited' "$BTOOLS"; then
  ok "B16-5 桥步 OPS guard + 安全模式受限分发在位"
else
  bad "B16-5 桥步 guard/受限分发缺失"
fi
# B16-6 OPS 三层回读源：bootApplied 快照（判定入
# 口落点）+ 三层键 + effectiveFrom=next_launch。
if has 'bootAppliedOps' "$SRC" \
   && has 'bootAppliedOps = OpsDirectives.cached()' "$SRC" \
   && has '"bootApplied"' "$BOPS" \
   && has '"currentCache"' "$BOPS" \
   && has '"lastFetch"' "$BOPS" \
   && has '"next_launch"' "$BOPS" \
   && has 'fetchWithOutcome' "$OPS"; then
  ok "B16-6 OPS 三层回读 + bootApplied 快照 + refresh 逐源结果在位"
else
  bad "B16-6 三层回读/bootApplied/逐源结果缺失"
fi
# B16-7 设置接线：Sub.bridge + 桥行 + 二级页。
if has 'case .bridge' "$SRC" \
   && has '"settings.bridge"' "$SRC" \
   && has 'BridgeSettingsView()' "$SRC" \
   && has 'struct BridgeSettingsView' "$BSET"; then
  ok "B16-7 设置页桥行 + 二级页接线在位"
else
  bad "B16-7 设置接线缺失"
fi
# B16-8 配对身份稳定 + 待配对会话落盘（根治，
# 定案 fix_bridge_pairing_state.md）：pending
# 会话存 Keychain（pendingPairingId 落点）；开始
# 配对先查已 paired 守卫与 pending 复用，未过期
# 不得新铸 pid。
if has 'var pendingPairingId' "$BRIDGE" \
   && has 'kcSet("pendingPairingId"' "$BRIDGE" \
   && has 'persistPending(session)' "$BRIDGE" \
   && has 'connectNow(reason: "begin_guard")' "$BRIDGE" \
   && has 'begin_resume' "$BRIDGE" \
   && has 'func dropPending' "$BRIDGE" \
   && has 'clearPendingPairing' "$BRIDGE"; then
  ok "B16-8 待配对会话落盘 + 身份不轮换守卫在位"
else
  bad "B16-8 会话落盘/身份守卫缺失"
fi
# B16-9 状态校准时点 + 先问中继再谈过期（根治
# 同案）：revalidatePairing 单点在位且调用点
# ≥4（启动/开关/回前台/开始配对/设置页）；设置
# 页 onAppear 接线；queryPairingStatus 内
# pair/status 查询行必须在本地过期日志行之前
# （本地时钟不得抢先判死）。
seg=$(sed -n '/private func queryPairingStatus/,/private func finishPairing/p' "$BRIDGE")
qpos=$(echo "$seg" | grep -n 'pair/status' | head -1 | cut -d: -f1)
epos=$(echo "$seg" | grep -n 'BRIDGE pairing_expired' | head -1 | cut -d: -f1)
if has 'func revalidatePairing' "$BRIDGE" \
   && has 'bridge.revalidatePairing()' "$BSET" \
   && [ "$(grep -c 'revalidatePairing()' "$BRIDGE")" -ge 4 ] \
   && [ -n "$qpos" ] && [ -n "$epos" ] \
   && [ "$qpos" -lt "$epos" ] \
   && has 'identity.pairingId = p.id' "$BRIDGE" \
   && has 'connectNow(reason: "paired")' "$BRIDGE"; then
  ok "B16-9 校准时点齐全 + 先问中继 + 落盘连接同点"
else
  bad "B16-9 校准时点/查询次序/同点落盘缺失"
fi
# B16-10 能力门（M2）：分发器 write/ops 两集合 +
# scope_denied 前置拦截双分支；中继同表门 +
# 写面超时 30s。
if has 'static let writeScopeTools' "$BTOOLS" \
   && has 'static let opsScopeTools' "$BTOOLS" \
   && [ "$(grep -c 'code: "scope_denied"' "$BTOOLS")" -ge 2 ] \
   && has 'WRITE_SCOPE_TOOLS' "$RELAY" \
   && has 'WRITE_TIMEOUT_MS = 30000' "$RELAY"; then
  ok "B16-10 能力门双层（write/ops 集合 + scope_denied + 中继同表/写超时）"
else
  bad "B16-10 能力门缺失或中继门不同步"
fi
# B16-11 两段提交（M2，方案 §7.3）：twoStageTools
# + actionToken 签发 + confirmation_required；
# 永删段 confirmMemoId 逐字校验。
if has 'static let twoStageTools' "$BTOOLS" \
   && has '"actionToken": token' "$BTOOLS" \
   && has 'code: "confirmation_required"' "$BTOOLS" \
   && grep -qF 'args["confirmMemoId"] as? String == id' "$BTOOLS"; then
  ok "B16-11 两段提交（令牌绑定 + confirmation_required + 永删 id 逐字校验）"
else
  bad "B16-11 两段提交机制缺失"
fi
# B16-12 快照先行（M2，方案 §9.3）：只读 FFI 句
# 柄直调 exportBackup 落 bridge-snapshots；桥六
# 文件 exportZip( 零出现（不污染备份新鲜度）。
if has 'openReadonly' "$BTOOLS" \
   && has 'exportBackup' "$BTOOLS" \
   && has 'bridge-snapshots' "$BTOOLS" \
   && ! grep -q 'exportZip(' "$BPROTO" "$BTRANS" \
        "$BRIDGE" "$BTOOLS" "$BOPS" "$BSET"; then
  ok "B16-12 写前快照只读直调 + 桥内零 exportZip"
else
  bad "B16-12 快照链缺失或桥内混入 exportZip"
fi
# B16-13 幂等与守卫（M2）：paramsHash 同口径、
# 幂等冲突/修订冲突错误码、guardedMemo docHash
# 守卫在位。
if has 'static func paramsHash' "$BTOOLS" \
   && has 'code: "idempotency_conflict"' "$BTOOLS" \
   && has 'code: "revision_conflict"' "$BTOOLS" \
   && has 'func guardedMemo' "$BTOOLS"; then
  ok "B16-13 幂等回放/冲突 + docHash 守卫在位"
else
  bad "B16-13 幂等/守卫机制缺失"
fi
# B16-14 安全模式受限集（M2，方案 §9.6 八件逐
# 名）；try_normal 桥路径：非安全模式拒绝 +
# via=bridge 标记 + 救援动作留痕同点。
safeset=$(sed -n '/static let safeLimitedTools/,/\]/p' "$BTOOLS" \
  | grep -o '"[a-z_]*"' | tr -d '"' | sort | tr '\n' ' ')
if [ "$safeset" = "app_state bridge_status diag_search diag_tail ops_get_effective ops_refresh rescue_status rescue_try_normal_start " ] \
   && has 'code: "not_in_safe_mode"' "$BOPS" \
   && has 'RESCUE action normal-retry via=bridge' "$BOPS" \
   && has 'recordRescueAction("normal-retry")' "$BOPS"; then
  ok "B16-14 受限集 §9.6 八件 + try_normal 桥路径留痕"
else
  bad "B16-14 受限集漂移或 try_normal 路径缺失"
fi
# B16-15 清单三方一致（仓内两侧）：BPROTO
# toolNames 与中继 TOOLS 名集合 diff 为空且同
# 为 37 件（连接器 ALLOWED_TOOLS 已由快照恢
# 复批同步 backup_restore_snapshot，仓外不
# 查）。
# manifestHash 注记：1c2fe22e…（sha256(
# "2025-06-18|" + 37 名排序连接)，运行时两
# 边计算对账）。
protonames=$(sed -n '/static let toolNames/,/\]/p' "$BPROTO" \
  | grep -o '"[a-z_]*"' | tr -d '"' | sort)
relaynames=$(awk '/^const TOOLS = \[/{f=1} f{print} f&&/^\];/{exit}' "$RELAY" \
  | grep -o 'name: "[a-z_]*"' | sed 's/name: "//; s/"$//' | sort)
if [ "$protonames" = "$relaynames" ] \
   && [ "$(echo "$protonames" | wc -l | tr -d ' ')" = 37 ]; then
  ok "B16-15 App/中继工具清单一致（37 件，diff 空）"
else
  bad "B16-15 App/中继工具清单不一致"
fi
# B16-16 设置写白名单（M2）：toggleRegistry 只
# 含 diagAutodel；天气 key 只有清（removeObject
# 自填覆盖）无写——桥六文件 weatherKey_ 仅此一
# 处落点。
tgset=$(sed -n '/static let toggleRegistry/,/\]/p' "$BTOOLS" \
  | grep -o '"[a-zA-Z_]*"' | tr -d '"')
wkline=$(grep -h 'weatherKey_' "$BPROTO" "$BTRANS" \
  "$BRIDGE" "$BTOOLS" "$BOPS" "$BSET")
if [ "$tgset" = "diagAutodel" ] \
   && [ "$(echo "$wkline" | wc -l | tr -d ' ')" = 1 ] \
   && echo "$wkline" | grep -q 'forKey: "weatherKey_"'; then
  ok "B16-16 开关白名单仅 diagAutodel + 天气 key 只清不写"
else
  bad "B16-16 设置写白名单漂移或出现经桥写天气 key 路径"
fi
# B16-17 布防入册机制（M2 §7.3 接线批）：
# rescue_arm_safe_mode 同在 ops 能力集、两段
# 集、数据写管线集（幂等辖面）；处理器在
# BOPS（标记写 + Diag 登记行 + next_launch 口
# 径 + arm_write_failed 码）；中继 OPS 集同
# 名在位；受限集不收由 B16-14 的八件精确集
# 合断言守恒（本条只作显式负查）。
OPSEG=$(sed -n '/static let opsScopeTools/,/\]/p' "$BTOOLS")
TSSEG=$(sed -n '/static let twoStageTools/,/\]/p' "$BTOOLS")
DWSEG=$(sed -n '/static let dataWriteTools/,/\])/p' "$BTOOLS")
SLSEG=$(sed -n '/static let safeLimitedTools/,/\]/p' "$BTOOLS")
if echo "$OPSEG" | grep -q '"rescue_arm_safe_mode"' \
   && echo "$TSSEG" | grep -q '"rescue_arm_safe_mode"' \
   && echo "$DWSEG" | grep -q '"rescue_arm_safe_mode"' \
   && ! echo "$SLSEG" | grep -q '"rescue_arm_safe_mode"' \
   && has 'func rescueArmSafeMode' "$BOPS" \
   && has 'RESCUE arm set id=' "$BOPS" \
   && has '"next_launch"' "$BOPS" \
   && has 'code: "arm_write_failed"' "$BOPS" \
   && has '"rescue_arm_safe_mode"' "$RELAY" \
   && grep -q 'OPS_SCOPE_TOOLS = new Set(\[.*rescue_arm_safe_mode' "$RELAY"; then
  ok "B16-17 布防入册（ops/两段/幂等三集 + 处理器 + 中继同表 + 受限集不收）"
else
  bad "B16-17 布防入册机制缺失或集合漂移"
fi
# B16-18 桥稳定性·App 侧（fix_bridge_stability）：
# 传输层代次作用域（迟到回调验代次、旧代不碰新
# 连接状态）+ 前台 5s 探活 + 路径看门狗 + 用户可
# 见触发重置退避 + 连接生命周期打点（connect /
# session down 带 reason 与时长）；sendPing 旧死
# 方法零残留。
if has 'private var generation' "$BTRANS" \
   && has 'guard gen == self.generation' "$BTRANS" \
   && has 'reason: "send_error"' "$BTRANS" \
   && ! has 'func sendPing' "$BTRANS" \
   && has 'func probeLiveness' "$BRIDGE" \
   && has 'probe_timeout' "$BRIDGE" \
   && has 'NWPathMonitor' "$BRIDGE" \
   && has 'connectNow(reason: "path")' "$BRIDGE" \
   && has 'if reason != "backoff" { backoffAttempt = 0 }' "$BRIDGE" \
   && has 'BRIDGE connect reason=' "$BRIDGE" \
   && has 'BRIDGE session down reason=' "$BRIDGE"; then
  ok "B16-18 桥稳定性 App 侧（代次传输 + 前台探活 + 路径看门狗 + 退避重置 + 生命周期打点）"
else
  bad "B16-18 桥稳定性 App 侧机制缺失"
fi
# B16-19 桥稳定性·中继侧（fix_bridge_stability）：
# 选连按 epoch/新鲜度 + 逐 socket lastSeenAt 僵
# 尸判定 + pending 按连接打标隔离 + webSocketError
# 处理器 + 等设备短窗 + alarm 僵尸回收；no-device
# 回码带 retryable。
if has 'STALE_SOCKET_MS' "$RELAY" \
   && has 'WAIT_DEVICE_MS' "$RELAY" \
   && has 'att.lastSeenAt' "$RELAY" \
   && has 'entry.ws === ws' "$RELAY" \
   && has 'failPendingFor' "$RELAY" \
   && has 'webSocketError' "$RELAY" \
   && has 'setAlarm' "$RELAY" \
   && has '"no live device connection", true' "$RELAY"; then
  ok "B16-19 桥稳定性中继侧（选连/僵尸判定/pending 隔离/等设备窗/alarm 回收）"
else
  bad "B16-19 桥稳定性中继侧机制缺失"
fi
# B16-20 桥续连根治（fix_bridge_reconnect_flow）：
# R1 会话恢复令牌（App：Keychain 同级落盘 +
# resume 首帧 + challenge 持留/补答 + resume
# ok/fallback 打点 + 吊销清令牌；中继：只存
# sha256 + 常时比对 + completeAuth 轮换下发 +
# resume_rejected 回退）+ R2 ping/presence 段存
# 储调用零残留 + A2 探活三修正（connected 门 /
# pong 即结案 / 判定窗 2s）+ A3 scopes 变化才写。
PROBESEG=$(sed -n '/private func probeLiveness/,/^    }$/p' "$BRIDGE")
PINGSEG=$(sed -n '/control === "ping"/,/^      }$/p' "$RELAY")
PRESSEG=$(sed -n '/presence \/ incident_hint/,/return;/p' "$RELAY")
if has 'kcGet("resumeToken")' "$BRIDGE" \
   && has 'func clearResumeToken' "$BRIDGE" \
   && has '"moment.control": "resume"' "$BRIDGE" \
   && has 'resumeInFlight' "$BRIDGE" \
   && has 'heldChallengeNonce' "$BRIDGE" \
   && has 'func answerChallenge' "$BRIDGE" \
   && has 'BRIDGE resume ok' "$BRIDGE" \
   && has 'BRIDGE resume fallback' "$BRIDGE" \
   && has 'if granted != identity.scopes' "$BRIDGE" \
   && has 'func finishProbeIfSatisfied' "$BRIDGE" \
   && echo "$PROBESEG" | grep -q 'linkState == "connected"' \
   && echo "$PROBESEG" | grep -qF '.now() + 2' \
   && has 'RESUME_TTL_MS' "$RELAY" \
   && has 'resumeTokenHash' "$RELAY" \
   && has 'hashEqualHex' "$RELAY" \
   && has 'async completeAuth' "$RELAY" \
   && has 'control === "resume"' "$RELAY" \
   && has 'resume_rejected' "$RELAY" \
   && ! echo "$PINGSEG" | grep -q 'this.record()\|saveRecord' \
   && ! echo "$PRESSEG" | grep -q 'this.record()\|saveRecord'; then
  ok "B16-20 桥续连根治（R1 令牌轮换/回退/吊销 + R2 ping/presence 零存储 + A2 探活三修正 + A3 scopes 条件写）"
else
  bad "B16-20 桥续连根治机制缺失"
fi
# B16-23 快照恢复入册机制（M3 backup_restore_
# snapshot，定案 impl_bridge_backup_restore.md）：
# 锁机制面不锁文案——ops/两段/数据写管线三集
# 在位 + 受限集不收（§9.6）；处理器在 BRESTORE
# 且恢复前强制再快照走 takeSnapshot 直取（非会
# 话复用）+ snapshot_not_found/snapshot_failed
# 双码 + 在席守卫；换库走 Library 内部同路
# bridgeRestoreFromSnapshot；中继 OPS 集同名；
# 构建接线（Restore 提及 31 = 全遍次级 + 自有
# primary 遍、bridge_restore.o ×2）。
if echo "$OPSEG" | grep -q '"backup_restore_snapshot"' \
   && echo "$TSSEG" | grep -q '"backup_restore_snapshot"' \
   && echo "$DWSEG" | grep -q '"backup_restore_snapshot"' \
   && ! echo "$SLSEG" | grep -q '"backup_restore_snapshot"' \
   && has 'func restoreSnapshot' "$BRESTORE" \
   && has 'takeSnapshot(' "$BRESTORE" \
   && has 'backup_restore_snapshot:pre' "$BRESTORE" \
   && has 'code: "snapshot_not_found"' "$BRESTORE" \
   && has 'code: "snapshot_failed"' "$BRESTORE" \
   && has 'EditorSeatRegistry.shared' "$BRESTORE" \
   && has 'func snapshotRecord' "$BTOOLS" \
   && has 'func bridgeRestoreFromSnapshot' "$SRC" \
   && has '"backup_restore_snapshot"' "$RELAY" \
   && grep -q 'OPS_SCOPE_TOOLS = new Set(\[.*backup_restore_snapshot' "$RELAY" \
   && [ "$(grep -c 'MomentBridgeRestore.swift' "$SH")" = 29 ] \
   && [ "$(grep -c 'bridge_restore.o' "$SH")" = 2 ]; then
  ok "B16-23 快照恢复入册（ops/两段/管线三集 + 恢复前强制快照 + 双码 + 在席守卫 + 内部同路 + 中继同表 + 构建接线）"
else
  bad "B16-23 快照恢复入册机制缺失或集合漂移"
fi
# B16-QR-1..4 配对二维码（impl_pairing_qr）：载荷
# 只消费 pairingURL() 单一构造点（构造点
# queryItems 恒 pid+fp 两项、设置页引用恰一处
# = 二维码、构建名单含 bridge_qr.o；沿革：原
# 引用两处含「打开配对页」链接钮，该钮已随配
# 对 App 内确认批退役——确认改走协调器
# confirmPairing 直达中继 JSON 通道，外跳清
# 零由 B16-PAIRAPP-1 锁）；
# 二维码生成文件与构造点函数体内凭据词零出现
# （私钥存取/客户端密钥/会话恢复令牌）；二维码
# 视图恰一处且位于待配对分支内（已配对分支随
# 分支结构零出现）；有效期行与 expiresAtMs 数
# 据源同在待配对分支。
BQR=MomentBridgeQR.swift
PAIRSEG=$(sed -n '/func pairingURL/,/^    }$/p' "$BRIDGE")
PENSEG=$(sed -n '/if let pending = bridge.pendingPairing/,/} else if bridge.isPaired {/p' "$BSET")
if [ -f "$BQR" ] \
   && [ "$(grep -c 'pairingURL()' "$BSET")" = 1 ] \
   && has 'makePairingQRImage(url.absoluteString)' "$BSET" \
   && has 'bridge_qr.o' "$SH" \
   && echo "$PAIRSEG" | grep -q 'URLQueryItem(name: "pid"' \
   && echo "$PAIRSEG" | grep -q 'URLQueryItem(name: "fp"' \
   && [ "$(echo "$PAIRSEG" | grep -c 'URLQueryItem')" = 2 ]; then
  ok "B16-QR-1 二维码载荷单源（pairingURL 恰 pid+fp、设置页引用恰一处、构建名单齐）"
else
  bad "B16-QR-1 二维码载荷单源锁缺失"
fi
if [ -f "$BQR" ] \
   && ! grep -q 'clientKey\|resumeToken\|privateKey\|keyTag' "$BQR" \
   && ! echo "$PAIRSEG" | grep -q 'clientKey\|resumeToken'; then
  ok "B16-QR-2 凭据零入码（生成文件 + 构造点函数体）"
else
  bad "B16-QR-2 二维码链出现凭据词"
fi
if [ "$(grep -c 'makePairingQRImage' "$BSET")" = 1 ] \
   && echo "$PENSEG" | grep -q 'makePairingQRImage'; then
  ok "B16-QR-3 二维码视图恰一处且在待配对分支内"
else
  bad "B16-QR-3 二维码视图位置/计数不对"
fi
if echo "$PENSEG" | grep -q 'bridge.pair_expires' \
   && echo "$PENSEG" | grep -q 'pending.expiresAtMs'; then
  ok "B16-QR-4 待配对有效期行在位（pair_expires + expiresAtMs）"
else
  bad "B16-QR-4 待配对有效期行缺失"
fi
# B16-PAIRAPP-1..4 配对 App 内确认
# （fix_bridge_pairing_inapp）：外跳清零（设
# 置页 openURL 与 pair_open 引用零残留）、协
# 调器 confirm 单点在位（confirmPairing 直
# 调 /pair/confirm + pairing_confirmed 打
# 点）、密钥卫生（Diag 行零密钥词、密钥无落
# 盘写点）、中继 JSON 通道在位
# （room/pair-confirm 转发恰两处 = 网页表单
# + App JSON 同入 DO 单点、版本 1.1.0）、勾
# 选面与密钥卡呈现齐。
if ! grep -q 'openURL' "$BSET" \
   && ! grep -q 'bridge.pair_open' "$BSET" \
   && has 'func confirmPairing' "$BRIDGE" \
   && has '"/pair/confirm"' "$BRIDGE" \
   && has 'BRIDGE pairing_confirmed' "$BRIDGE" \
   && has 'bridge.pair_confirm' "$BSET"; then
  ok "B16-PAIRAPP-1 App 内确认单点在位 + 外跳清零"
else
  bad "B16-PAIRAPP-1 App 内确认/外跳清零缺失"
fi
if [ "$(grep 'DiagLog' "$BRIDGE" | grep -c 'clientKey\|oneTimeClientKey')" = 0 ] \
   && [ "$(grep -c 'oneTimeClientKey' "$BRIDGE")" -ge 3 ] \
   && ! grep -q 'kcSet("clientKey"\|kcSet("oneTimeClientKey"' "$BRIDGE"; then
  ok "B16-PAIRAPP-2 密钥卫生（Diag 零密钥词、无落盘写点）"
else
  bad "B16-PAIRAPP-2 密钥卫生锁缺失"
fi
if [ "$(grep -c 'room/pair-confirm' "$RELAY")" = 2 ] \
   && has 'RELAY_VERSION = "1.1.0"' "$RELAY"; then
  ok "B16-PAIRAPP-3 中继 JSON confirm 通道在位（双通道同入 DO 单点）"
else
  bad "B16-PAIRAPP-3 中继 JSON 通道缺失"
fi
if has 'bridge.pair_scope_read_note' "$BSET" \
   && has 'bridge.pair_scope_write_note' "$BSET" \
   && has 'bridge.pair_scope_ops_note' "$BSET" \
   && has 'bridge.key_title' "$BSET" \
   && has 'func dismissClientKey' "$BRIDGE"; then
  ok "B16-PAIRAPP-4 勾选面与密钥卡呈现齐（scopes 三行 + 密钥卡 + 关闭单点）"
else
  bad "B16-PAIRAPP-4 呈现面缺失"
fi
# B16-21 OPS 生效口径双轨收敛（S13，
# fix_ops_effective_scope）：effectiveScope 构造
# 单点（MomentOps 定义恰 1 处）+ 两回报面各引用
# 1 次、同名键各 1 处 + 四轴键与六步值齐全。
if [ "$(grep -c 'static func effectiveScopeDict' "$OPS")" = "1" ] \
   && [ "$(grep -c 'OpsDirectives.effectiveScopeDict()' "$BOPS")" = "2" ] \
   && [ "$(grep -c '"effectiveScope"' "$BOPS")" = "2" ] \
   && has '"launchDecision": "next_launch"' "$OPS" \
   && has '"stepGuards": "immediate"' "$OPS" \
   && has '"dispatcherTightening": "immediate"' "$OPS" \
   && has '"bridgeStartGate": "next_bridge_start"' "$OPS" \
   && has 'OpsStep.attachTypes: "immediate"' "$OPS" \
   && has 'OpsStep.diagFreezePersist: "immediate"' "$OPS" \
   && has 'OpsStep.weatherRefresh: "immediate"' "$OPS" \
   && has 'OpsStep.mathPreheat: "immediate"' "$OPS" \
   && has 'OpsStep.bridge: "mixed"' "$OPS" \
   && has 'OpsStep.watchdog: "next_launch"' "$OPS"; then
  ok "B16-21 OPS effectiveScope 构造单点 + 两回报同名同形 + 轴键/六步齐全"
else
  bad "B16-21 effectiveScope 构造/引用/字段缺失"
fi
# B16-22 单轨漂移文本零残留（退役即删除口径）：
# 旧单轨表述两串在 app 源码归零（布防回报的
# effectiveFrom=next_launch 属实、豁免不动）。
if ! grep -q '本次不生效' ./*.swift \
   && ! grep -q '生效点恒为下次启动' ./*.swift; then
  ok "B16-22 OPS 单轨漂移文本零残留"
else
  bad "B16-22 漂移文本残留（本次不生效/生效点恒为下次启动）"
fi

echo "[17] 编辑器呈现重构（0.9.50，定案 fix_transition_refactor.md）"
TRANS=MomentEditorTransition.swift
# T17-1 宿主文件 + 构建集成：文件在位、build 脚本
# 含其编译遍（transition.o）与链接项。
if [ -f "$TRANS" ] && has 'MomentEditorTransition.swift' "$SH" \
   && has 'transition.o' "$SH"; then
  ok "T17-1 转场宿主文件 + 构建集成（编译遍/链接）在位"
else
  bad "T17-1 宿主文件或 build 集成缺失"
fi
# T17-2 UIKit 单一转场：宿主以 pushViewController
# 呈现，转场落点经 transitionCoordinator completion。
if has 'pushViewController' "$TRANS" \
   && has 'transitionCoordinator' "$TRANS"; then
  ok "T17-2 UIKit push + 转场协调器 completion 在位"
else
  bad "T17-2 宿主未以 UIKit push/协调器落点呈现"
fi
# T17-3 首帧前置：push 前 loadViewIfNeeded + 强制
# 布局一趟（首帧构建落在转场窗外）。
if has 'loadViewIfNeeded' "$TRANS" \
   && has 'layoutIfNeeded' "$TRANS"; then
  ok "T17-3 首帧前置构建（loadView+layout）在位"
else
  bad "T17-3 首帧前置缺失（构建回落转场窗内）"
fi
# T17-4 认领门三点齐：EditorModel 开门点、块视图
# 认领条件含门、宿主在 completion 后开门。
if has 'func openFocusGate' "$SRC" \
   && has 'wantsInitialFocus && $0.focusGateOpen' "$SRC" \
   && has 'openFocusGate()' "$TRANS"; then
  ok "T17-4 认领门三点齐（开门/门控认领/宿主调用）"
else
  bad "T17-4 认领门缺环（认领可能重回转场窗内）"
fi
# T17-5 旧呈现路径零残留：代码行无 nav.dest 的
# .editor 写入、无 Dest 的 .editor 目的地。
if ! echo "$CODE" | grep -q 'nav\.dest = \.editor' \
   && ! echo "$CODE" | grep -q 'case \.editor'; then
  ok "T17-5 旧 destination 编辑器路径零残留"
else
  bad "T17-5 旧路径残留（nav.dest=.editor / case .editor）"
fi
# T17-6 新建入口收敛：落焦意图置位全文件恰一处
# （createAndOpen），旧四处散写已收敛。
n_flag=$(echo "$CODE" | grep -c 'wantsInitialFocus = true')
if [ "$n_flag" = 1 ] && has 'func createAndOpen' "$SRC"; then
  ok "T17-6 新建四入口收敛 createAndOpen（置位恰 1）"
else
  bad "T17-6 置位计数=$n_flag（应 1）或收敛函数缺失"
fi
# T17-7 TRANSITION 打点：宿主一行四时点在位。
if has 'TRANSITION id=' "$TRANS" \
   && has 'kind=' "$TRANS" && has 'claim=' "$TRANS"; then
  ok "T17-7 TRANSITION 打点（build/anim/claim/kb）在位"
else
  bad "T17-7 TRANSITION 打点缺失（下轮无从验单段动画）"
fi
# T17-8 settle claim 段规范化：ok/inwindow 形态
# （claimSeg）在位、旧 ms 形态零残留。
if has 'let claimSeg' "$SRC" \
   && ! echo "$CODE" | grep -qF 'claim=\(traceMs(traceDest, traceClaim))ms'; then
  ok "T17-8 settle claim 段 ok/inwindow 形态（旧 ms 零残留）"
else
  bad "T17-8 settle claim 段未规范化或旧形态残留"
fi
# T17-9 图片页呈现移交宿主：ImagePageView 只在宿
# 主文件构造（MomentApp 内旧构造点零残留），返回
# 出口 onClose/onBack 接线在位。
if has 'ImagePageView(' "$TRANS" \
   && ! echo "$CODE" | grep -q 'ImagePageView(' \
   && has 'var onClose' "$SRC" && has 'onBack: onClose' "$SRC"; then
  ok "T17-9 图片页经宿主呈现 + 返回出口接线在位"
else
  bad "T17-9 图片页呈现未移交或返回出口缺失"
fi
# T17-10 列表侧共演抑制：新建回合包在
# disablesAnimations 事务里（行插入不与转场共演）。
if has 'tx.disablesAnimations = true' "$SRC" \
   && has 'withTransaction(tx)' "$SRC"; then
  ok "T17-10 新建回合禁动画事务（行插入不共演）在位"
else
  bad "T17-10 列表共演抑制缺失"
fi
# T17-11 双栏 independent 栏内距（审计 L-2）：左
# 栏 trailing 16 + 线贴左栏右缘 + 右栏 leading
# gap+15（净距 gap+32 = Web）；panelLeftX 右栏
# 原点账同步（栏宽扣线 1、其后 1 + gap + 15）。
WC=$(awk '/private var wideColumns/,/private var twoPaneRow/' "$SRC")
if echo "$WC" | grep -qF '.padding(.trailing, 16)' \
   && echo "$WC" | grep -qF '.padding(.leading, gap + 15)' \
   && ! echo "$WC" | grep -qF '.padding(.leading, half)' \
   && has 'contentW - 32 - 1' "$SRC" \
   && has 'colW + 1 + gap + 15' "$SRC"; then
  ok "T17-11 independent 栏内距 16/gap+15 + 菜单原点账同步"
else
  bad "T17-11 independent 栏内距或 panelLeftX 原点账漂移"
fi
# T17-12 正文顶 padding 对齐 Web 155（审计
# L-7）：三形态 padding 各一、三层浮层 indepen-
# dent 偏移各一、占位账 195/187/179 各一，旧
# 168 在编辑几何面零残留。
if [ "$(grep -c 'padding(.top, 155)' "$SRC")" = 3 ] \
   && [ "$(grep -c '? 155 : 0' "$SRC")" = 3 ] \
   && [ "$(grep -c 'padding(.top, 168)' "$SRC")" = 0 ] \
   && [ "$(grep -c '? 168 : 0' "$SRC")" = 0 ] \
   && has 'ui.viewH - 195' "$SRC" \
   && has 'ui.viewH - 187' "$SRC" \
   && has 'ui.viewH - 179' "$SRC"; then
  ok "T17-12 正文顶 155 三形态 + 浮层偏移 + 占位账全同步"
else
  bad "T17-12 正文顶 155 落点不齐或 168 残留"
fi

echo "[19] 自救机制 R2+R3（规格 plan_native_rescue.md S4/S5/S7/S8 + Diag guard 真隔离）"
STORAGE_RS=../../../crates/storage/src/lib.rs
BIND_SWIFT=../bindings/moment_ffi.swift
# R19-1 FFI 只读链全套：storage 只读打开（READ_ONLY
# flag）+ ffi 构造子 + bindings 工厂方法 + 契约表
# 新行（计数由 [6] 双向比对兜底）。
if has 'pub fn open_readonly' "$STORAGE_RS" \
   && has 'SQLITE_OPEN_READ_ONLY' "$STORAGE_RS" \
   && has 'pub fn open_readonly' "$FFI_RS" \
   && has 'openReadonly' "$BIND_SWIFT" \
   && has 'checksum_constructor_momentlibrary_open_readonly' "$FFI_RS"; then
  ok "R19-1 只读打开 FFI 全链（storage/ffi/bindings/契约表）"
else
  bad "R19-1 只读打开 FFI 链缺件（bindgen 全套是否走完）"
fi
# R19-2 openMode 四态 + 只读进入路径在位。
if has 'enum OpenMode' "$SRC" \
   && has 'case none, readWrite, readOnly, readOnlyCopy' "$SRC" \
   && has 'var isReadOnly' "$SRC" \
   && has 'func enterReadOnly()' "$SRC" \
   && has 'MomentLibrary.openReadonly(' "$SRC"; then
  ok "R19-2 openMode 四态 + enterReadOnly 直开路径在位"
else
  bad "R19-2 openMode/只读进入路径缺失"
fi
# R19-3 门面拒写五 kind 齐备 + READONLY 行模板。
if has 'writeBlocked("persist")' "$SRC" \
   && has 'writeBlocked("seed")' "$SRC" \
   && has 'writeBlocked("delete")' "$SRC" \
   && has 'writeBlocked("attach")' "$SRC" \
   && has 'writeBlocked("import")' "$SRC" \
   && has 'READONLY write-blocked kind=' "$SRC"; then
  ok "R19-3 只读门面拒写五 kind（persist/seed/delete/attach/import）"
else
  bad "R19-3 拒写 kind 不全（写入口漏 guard）"
fi
# R19-4 只读 reload 跳过待删真删（仅隐藏记行）。
if has '只读态待删过期仅隐藏' "$SRC"; then
  ok "R19-4 只读态待删过期仅隐藏（不真删）在位"
else
  bad "R19-4 只读 reload 仍可能真删"
fi
# R19-5 副本回退：tmp 救援目录 + mode=copy 落点。
if has 'moment-rescue-ro' "$SRC" \
   && has 'finishEnterReadOnly(mode: "copy")' "$SRC" \
   && has 'RESCUE readonly open ok mode=' "$SRC" \
   && has 'RESCUE readonly open fail err=' "$SRC"; then
  ok "R19-5 只读副本回退（tmp 目录 + mode 记行）在位"
else
  bad "R19-5 副本回退缺失或记行不全"
fi
# R19-6 看门狗：阈值单一定义 + fired 行 + OPS 步名
# 登记与消费 + 浮条定义/根挂载。
if [ "$(grep -c 'static let watchdogSeconds' "$SRC")" = 1 ] \
   && has 'RESCUE watchdog fired step=' "$SRC" \
   && has 'OpsStep.watchdog' "$SRC" \
   && has 'static let watchdog = ' "$OPS" \
   && has 'struct WatchdogBar' "$RESCUE" \
   && has 'WatchdogBar(library' "$SRC" \
   && has 'func enterRescueFromWatchdog()' "$SRC"; then
  ok "R19-6 看门狗 12s（单一阈值/OPS 可禁/浮条挂根）在位"
else
  bad "R19-6 看门狗缺件（阈值/fired 行/步名/浮条）"
fi
# R19-7 快照环：环文件/环长/折行/BOOT snap/导出附段。
if has 'rescue-log.json' "$LAUNCH" \
   && has 'ringLimit = 20' "$LAUNCH" \
   && has 'struct RescueSnapshot' "$LAUNCH" \
   && has 'RESCUE log actions=' "$SRC" \
   && has 'BOOT snap db=' "$SRC" \
   && has 'RescueLogStore.exportText()' "$SRC"; then
  ok "R19-7 状态快照环（环 20/折行/补写/导出附入）在位"
else
  bad "R19-7 快照环缺件"
fi
# R19-8 快照字段黑名单：快照结构内绝无备忘内容
# 字段（只记元数据是 S5 总红线）。
SNAPSEG=$(awk '/^struct RescueSnapshot/,/^enum RescueLogStore/' "$LAUNCH")
if ! echo "$SNAPSEG" | grep -qE 'var (title|content|fileName)\b'; then
  ok "R19-8 快照字段黑名单干净（无 title/content/fileName）"
else
  bad "R19-8 快照结构混入备忘内容字段（违反 S5 红线）"
fi
# R19-9 Diag guard 真隔离：记行只写 today 的出口
# 在位；结构 flush 内 guard 判定行序在清脏行之前
# （被跳过时脏标保留、记行不得顺带写出结构）。
DIAGSEG=$(awk '/^final class DiagLog/,/^struct FlowLayout/' "$SRC")
FLUSHSEG=$(echo "$DIAGSEG" | awk '/func flushStructuralPersist/{f=1} f{print} f&&/^    \}$/{exit}')
p_guard=$(echo "$FLUSHSEG" | grep -n 'isDisabled' | head -1 | cut -d: -f1)
p_clear=$(echo "$FLUSHSEG" | grep -n 'structuralDirty = false' | head -1 | cut -d: -f1)
if echo "$DIAGSEG" | grep -q 'func persistToday()' \
   && echo "$DIAGSEG" | grep -q 'self?.persistToday()' \
   && [ -n "$p_guard" ] && [ -n "$p_clear" ] \
   && [ "$p_guard" -lt "$p_clear" ]; then
  ok "R19-9 Diag 分文件落盘 + guard 先判后清脏（真隔离）"
else
  bad "R19-9 Diag guard 隔离形态不对（persistToday/行序）"
fi
# R19-10 缓存清理边界：动作行带字节数；清理器段
# 只许 caches/tmp/URLCache，零 Application Support。
CLEANSEG=$(awk '/^enum RescueCacheCleaner/,/^struct WatchdogBar/' "$RESCUE")
if has 'RESCUE action cache-clear bytes=' "$RESCUE" \
   && echo "$CLEANSEG" | grep -q 'cachesDirectory' \
   && echo "$CLEANSEG" | grep -q 'temporaryDirectory' \
   && echo "$CLEANSEG" | grep -q 'removeAllCachedResponses' \
   && ! echo "$CLEANSEG" | grep -q 'applicationSupportDirectory'; then
  ok "R19-10 缓存清理清单封闭（缓存三处，零 Support 域）"
else
  bad "R19-10 缓存清理越界或缺件"
fi
# R19-11 只读呈现与退出：横幅（两形态共用内容）+
# 新建卡只读隐藏 + 回页/复位两件套。
if has 'rescue.readonly_banner' "$SRC" \
   && has 'func exitReadOnlyToRescue()' "$SRC" \
   && has 'func prepareNormalStart()' "$SRC" \
   && has '!library.loadFailed && !library.isReadOnly' "$SRC" \
   && has 'library.prepareNormalStart()' "$RESCUE"; then
  ok "R19-11 只读横幅 + 退出唯一路径（回页/复位）在位"
else
  bad "R19-11 只读呈现/退出路径缺件"
fi
# R19-12 救援页动作 3/5 接线：只读打开与清缓存
# 均经本页动作函数落到 Library/清理器。
if has 'func openReadonly()' "$RESCUE" \
   && has 'library.enterReadOnly()' "$RESCUE" \
   && has 'func clearCaches()' "$RESCUE" \
   && has 'RescueCacheCleaner.clear()' "$RESCUE"; then
  ok "R19-12 救援页只读/清缓存动作接线在位"
else
  bad "R19-12 救援页动作 3/5 接线缺失"
fi
# R19-14 救援页/看门狗浮条宽屏收窄（E-2，用户
# 裁定；编号顺延避与救援批 R19-13 同号）：救援
# 页内容框 720 居中、浮条 600，各恰一处（与设
# 置族 SettingsContainer 同口径）。
if [ "$(grep -cF '.frame(maxWidth: 720)' "$RESCUE")" = 1 ] \
   && [ "$(grep -cF '.frame(maxWidth: 600)' "$RESCUE")" = 1 ]; then
  ok "R19-14 救援页 720 + 看门狗浮条 600 收窄在位"
else
  bad "R19-14 救援页宽屏收窄缺失或重复"
fi
# R19-13 看门狗 arm 前移（救援完整性批，P2-2）：
# Library.init 段内有 armWatchdog() 调用（独立于
# 任何视图出现）；全文件 armWatchdog() 恰三处
# （定义 + init 恒 arm + load 续期）。
INITSEG=$(awk '/^    init\(\) \{/{f=1} f{print} f&&/^    \}$/{exit}' "$SRC")
if echo "$INITSEG" | grep -q 'armWatchdog()' \
   && [ "$(grep -c 'armWatchdog()' "$SRC")" = 3 ]; then
  ok "R19-13 看门狗 arm 前移 init（load 起点只续期）"
else
  bad "R19-13 看门狗 arm 点位异常（init/load/定义应恰三处）"
fi
# R19-14 清缓存跳过只读副本（救援完整性批，
# P2-4）：副本目录名单点常量（Library 静态定义、
# readOnlyCopyDir 引用）+ 清理器 measure/clear 经
# excluding 跳过该目录（防删正打开的副本三件套）。
if has 'static let readOnlyCopyDirName' "$SRC" \
   && has 'Self.readOnlyCopyDirName' "$SRC" \
   && echo "$CLEANSEG" | grep -q 'readOnlyCopyDirName' \
   && echo "$CLEANSEG" | grep -q 'excluding: roCopyName'; then
  ok "R19-14 清缓存跳过只读副本目录（P2-4 相撞消除）"
else
  bad "R19-14 清缓存仍可能删只读副本"
fi
# R19-15 只读编辑入口守卫（救援完整性批，P2-5
# 用户裁定）：Library.readonlyEntryBlocked（记行
# 模板 + 横幅同源文案）+ 两条 UI 漏斗各一处守卫
# （openMemo="open" / createAndOpen="create"），
# 守卫点恰两处（防漏堵一路或散写多路）。
if has 'func readonlyEntryBlocked(_ kind: String)' "$SRC" \
   && has 'READONLY entry-blocked kind=' "$SRC" \
   && has 'readonlyEntryBlocked("open")' "$SRC" \
   && has 'readonlyEntryBlocked("create")' "$SRC" \
   && [ "$(grep -c 'readonlyEntryBlocked("' "$SRC")" = 2 ]; then
  ok "R19-15 只读入口守卫（两漏斗拦截 + 提示，不进编辑页）"
else
  bad "R19-15 只读入口守卫缺失或漏斗未收敛"
fi

echo "[18] 设置页天气分组重构（方案 plan_weather_settings.md + 差距账 S1–S7/I1–I7）"
WV=$(awk '/^struct WeatherView/,/^struct LanguageView/' "$SRC")
# W18-1 二级页与路由接线：WeatherView 在位、Sub
# .weather case、destination 构造、主页行副标题
# 直引固定说明键 settings.weather_sub。
if has 'struct WeatherView' "$SRC" \
   && has 'case .weather' "$SRC" \
   && has 'WeatherView()' "$SRC" \
   && has '"settings.weather_sub"' "$SRC"; then
  ok "W18-1 WeatherView 二级页 + Sub 路由 + 主页副标题键在位"
else
  bad "W18-1 天气二级页/路由/主页行缺失"
fi
# W18-2 旧形态零残留（只查代码行）：内嵌表单类、
# 自绘行、整组保存钮与 placeholder 混合信号全退役；
# 主页状态合成机器（weatherMeta/weatherSourceWord
# 与 weather_status 模板键引用）随副标题定案同退役。
if ! echo "$CODE" | grep -q 'WeatherKeyUI' \
   && ! echo "$CODE" | grep -q 'weatherKeyRow' \
   && ! echo "$CODE" | grep -q 'weatherUI' \
   && ! echo "$CODE" | grep -q 'weatherMeta' \
   && ! echo "$CODE" | grep -q 'weatherSourceWord' \
   && ! echo "$CODE" | grep -q '"settings.weather_save"' \
   && ! echo "$CODE" | grep -q '"settings.weather_active"' \
   && ! echo "$CODE" | grep -q '"settings.weather_status"'; then
  ok "W18-2 旧表单形态零残留（WeatherKeyUI/保存钮/旧键与状态合成机器）"
else
  bad "W18-2 旧天气表单残留（WeatherKeyUI/weatherKeyRow/旧键/状态合成）"
fi
# W18-3 来源派生单一真源 + bundle 进程级缓存：
# keySource/customKey/bundleKeys 三件齐，key() 走派生。
if has 'enum KeySource' "$SRC" \
   && has 'static func keySource' "$SRC" \
   && has 'static func customKey' "$SRC" \
   && has 'private static let bundleKeys' "$SRC"; then
  ok "W18-3 keySource 派生 + bundleKeys 单次缓存 在位"
else
  bad "W18-3 keySource/缓存缺失（状态判据可能分叉或重复读盘）"
fi
# W18-4 逐字段即时提交面（WeatherView 段内）：进入
# 打点、来源口径 saved 打点、粘贴/清除/显隐/聚焦提交。
if echo "$WV" | grep -q 'SET weather enter' \
   && echo "$WV" | grep -q 'SET weather key saved' \
   && echo "$WV" | grep -q 'UIPasteboard.general' \
   && echo "$WV" | grep -q 'func clear' \
   && echo "$WV" | grep -q 'eye.slash' \
   && echo "$WV" | grep -q 'FocusState'; then
  ok "W18-4 即时提交/粘贴/清除/显隐/进入打点 在位"
else
  bad "W18-4 WeatherView 交互面缺件（提交/粘贴/清除/显隐）"
fi
# W18-5 关于组头组距重推：天气卡改导航行卡后，
# 关于组头 topPad 应为 32（.backup-card 口径）。
SV2=$(awk '/^struct SettingsView/,/^struct BackupView/' "$SRC")
if echo "$SV2" | grep -A1 '"settings.about"' | grep -q 'topPad: 32'; then
  ok "W18-5 关于组头 topPad 32（天气导航卡口径）"
else
  bad "W18-5 关于组头 topPad 未按导航卡重推"
fi
# W18-6 退役键五包零键 + 新键在位（键集合一致由
# [9] 守恒，这里只查天气批的增删落点）。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        pack = json.load(f)
    if "settings.weather_save" in pack: sys.exit(1)
    if "settings.weather_active" in pack: sys.exit(1)
    if "settings.weather_status" in pack: sys.exit(1)
    for k in ("settings.weather_sub",
              "settings.weather_builtin",
              "settings.weather_custom",
              "settings.weather_paste",
              "settings.weather_clear",
              "settings.weather_show",
              "settings.weather_hide"):
        if k not in pack: sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "W18-6 退役键五包零键、新键在位"
else
  bad "W18-6 天气键增删未落齐（退役键残留或新键缺失）"
fi
# W18-7 副标题文案锚：五包 weather_sub 值在位、
# zh-CN 即定案文案、全包无模板占位符（固定说明
# 而非状态模板，防旧模板回潮）。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        pack = json.load(f)
    v = pack.get("settings.weather_sub", "")
    if not v or "{" in v or "}" in v: sys.exit(1)
    if c == "zh-CN" and v != "天气数据源令牌配置":
        sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "W18-7 副标题五语文案锚（zh-CN 定案值 + 无占位符）"
else
  bad "W18-7 副标题文案漂移（值非定案或残留模板占位）"
fi
# W18-8 设置族宽屏收窄容器单源（E-1，用户裁
# 定）：settingsContentFrame 定义恰一处；主文
# 件内计数 8 = 定义 1 + 七面调用，桥设置文件
# 调用 1；全仓 .padding(.top, 126) 共 2 = 容
# 器定义 1 + 图片页 L-4 呈现顶让 1。沿革：
# 0.9.63 AUD-C-02（用户 2026-11-28 裁定）诊
# 断页入收敛面——计数 6→7、top 126 由 4→3
# （原 Diag 页 2 = 诊断页手抄 1 + 视窗页 1，
# 诊断页手抄已改调容器；「Diag 不在本批收敛
# 面」旧口径作废）。同日续批（用户实报，定案
# fix_diaglog_header_spacing.md）日志视窗页
# 终端卡整框接入——计数 7→8、top 126 由
# 3→2（视窗页手抄顶距入单点，底距安全区项
# 独立保留，[56] DG56-3 改判锁）。同日顶距
# 改判（用户 2026-11-28 裁定，定案 fix_
# frame_top_inset_81.md）：单点定义顶 126→
# 81——以用户设置页上滑 ≈45pt 截图位置为标
# 准（126 − 45 = 81，截图三处偏移量测复核）；
# 主文件 top 126 计数 2→1（余 1 = 图片页
# L-4 自持顶让，自分叉登记同报告）、top 81
# 恰 1（定义本体，新顶距值钉死）。
if [ "$(grep -c 'func settingsContentFrame' "$SRC")" = 1 ] \
   && [ "$(grep -c 'settingsContentFrame()' "$SRC")" = 8 ] \
   && [ "$(grep -c 'settingsContentFrame()' "$BSET")" = 1 ] \
   && [ "$(grep -c 'padding(.top, 126)' "$SRC")" = 1 ] \
   && [ "$(grep -c 'padding(.top, 81)' "$SRC")" = 1 ] \
   && [ "$(grep -c 'padding(.top, 126)' "$BSET")" = 0 ]; then
  ok "W18-8 设置族收敛 SettingsContainer（720 居中单源，诊断/视窗页已入面）"
else
  bad "W18-8 设置页容器收敛不齐（手抄 padding 回潮或页缺）"
fi
# W18-9 天气 key 变更失效收敛（W-T1，设计
# impl_weather_tail §3.5 编号 W18-8..10，因
# W18-8 已被宽屏批占用整体顺延一位）：编辑器
# commit/clear 两处均调 invalidateAfterKey-
# Change（WeatherView 段内计数 = 2），且段内
# weatherCacheV1 字面零残留（缓存删除权收归
# WeatherService，防编辑器侧再直删分叉）。
if [ "$(echo "$WV" | grep -c 'invalidateAfterKeyChange()')" = 2 ] \
   && [ "$(echo "$WV" | grep -c 'weatherCacheV1')" = 0 ]; then
  ok "W18-9 key 变更经服务失效单点（编辑器两处调用 + 段内缓存键零残留）"
else
  bad "W18-9 编辑器仍直删缓存或失效调用缺失"
fi
# W18-10 失效单点本体四件（设计 W18-9 顺延）：
# 世代自增 / 清呈现 now=nil / 删缓存 / 主动
# 重拉 refreshIfNeeded + Diag 失效行在位。
INV=$(awk '/func invalidateAfterKeyChange/,/^    }/' "$SRC")
if echo "$INV" | grep -q 'keyGeneration += 1' \
   && echo "$INV" | grep -q 'now = nil' \
   && echo "$INV" | grep -q 'weatherCacheV1' \
   && echo "$INV" | grep -q 'refreshIfNeeded()' \
   && echo "$INV" | grep -q 'WEATHER invalidate src=keychange'; then
  ok "W18-10 invalidateAfterKeyChange 四件 + Diag 行在位"
else
  bad "W18-10 失效单点缺件（世代/清呈现/删缓存/重拉/打点）"
fi
# W18-11 世代守卫落点（设计 W18-10 顺延）：
# fetch 入口捕获世代恰一处；gen 校验恰 4 =
# fetch 置 now 两点 + 双源落盘 writeCache 两
# 点（均主线程串行校验）；在飞期间刷新请求
# 的接续（refreshPending 置位 + 收口后续跑）
# 在位，防失效刷新被 inFlight 守卫吞掉。
if [ "$(grep -c 'let gen = keyGeneration' "$SRC")" = 1 ] \
   && [ "$(grep -c 'gen == self.keyGeneration' "$SRC")" = 4 ] \
   && has 'refreshPending = true' "$SRC" \
   && has 'self.refreshPending = false' "$SRC"; then
  ok "W18-11 世代守卫四落点 + 在飞刷新接续 在位"
else
  bad "W18-11 世代守卫落点漂移（旧 key 结果可回写/接续缺失）"
fi

echo "[20] 修复批 J2（浮层 31 + MD 9，定案 plan_batch_j2_specs.md / impl_batch_j2.md）"
# J20-1 共享 menuItem 度量（F03/F04/F05/F16）：高亮
# 圆角 17、图标 20、标题 tracking -0.1、图标色参数。
if has 'RowPressStyle(radius: 17)' "$SRC" \
   && has 'iconColor: Color? = nil' "$SRC" \
   && has 'iconColor: T.purple' "$SRC"; then
  ok "J20-1 menuItem 共享度量（radius 17/图标色参/背景行紫）"
else
  bad "J20-1 menuItem 共享度量缺失"
fi
# J20-2 新令牌四件（F08/F13/F29/M04）。
if has 'static var purple: Color { dyn(0xAF52DE, 0xAF52DE) }' "$SRC" \
   && has 'static var dangerLight: Color { dyn(0xFF6B6B, 0xFF6B6B) }' "$SRC" \
   && has 'static var cardBg: Color { dyn(0xFFFFFF, 0x1C1C1E) }' "$SRC" \
   && hasE 'placeholderStrong: Color' "$SRC"; then
  ok "J20-2 新令牌 purple/placeholderStrong/dangerLight/cardBg 在位"
else
  bad "J20-2 新令牌缺失"
fi
# J20-3 标题胶囊字距（F01）：呈现 tracking + 量测
# kern 同步。
if has '.kern: -0.2' "$SRC" \
   && [ "$(grep -c 'tracking(-0.2)' "$SRC")" -ge 2 ]; then
  ok "J20-3 标题胶囊 tracking/kern -0.2 双落点"
else
  bad "J20-3 标题字距缺失（呈现或量测）"
fi
# J20-4 斜杠宽/锚（F17/F18）：公式函数、锚点状态、
# SLASH 打点在位。
if has 'func slashPanelWidth' "$SRC" \
   && has 'func slashPanelLeft' "$SRC" \
   && has '@Published var slashAnchorX' "$SRC" \
   && has 'SLASH open id=' "$SRC"; then
  ok "J20-4 斜杠宽公式 + 光标锚 + 打点在位"
else
  bad "J20-4 斜杠宽/锚设施缺失"
fi
# J20-5 斜杠行形态（F22/F23/F24）：组头 tracking+
# uppercase、shortcut opacity、最近丸 glassLabel。
if has 'tracking(0.385)' "$SRC" \
   && has '.textCase(.uppercase)' "$SRC" \
   && has '.opacity(0.78)' "$SRC" \
   && has 'T.glassLabel' "$SRC"; then
  ok "J20-5 斜杠组头/快捷键丸/最近丸形态在位"
else
  bad "J20-5 斜杠行形态缺失"
fi
# J20-6 MD 行内标记（M01/M03）：wiki 标记、虚线、
# 链接色、删除线底。
if has '"wiki": true' "$SRC" \
   && has 'patternDash' "$SRC" \
   && has 'T.linkBlueUI' "$SRC" \
   && has 'T.fillHoverUI' "$SRC"; then
  ok "J20-6 MD 链接色/虚线 + 删除线底在位"
else
  bad "J20-6 MD 行内标记缺失"
fi
# J20-7 Callout 图标令牌（M06）：新值在位、旧系统
# 色值在 calloutAccent 段内零残留。
CA=$(awk '/static func calloutAccent/,/^    }/' "$SRC")
if echo "$CA" | grep -q '0x8436AA' \
   && echo "$CA" | grep -q '0x75E29A' \
   && ! echo "$CA" | grep -q '0x8250DF'; then
  ok "J20-7 calloutAccent 五变体 Web 令牌值"
else
  bad "J20-7 calloutAccent 仍非令牌值"
fi
# J20-8 标题前距补满（M07）：25/18.75/15/11.25。
if has 'level <= 1 ? 25 : level == 2 ? 18.75' "$SRC" \
   && has ': level == 3 ? 15 : level == 4 ? 11.25 : 7' "$SRC"; then
  ok "J20-8 headingExtraTop 补满值在位"
else
  bad "J20-8 标题前距未补满"
fi
# J20-9 表格（M04 + td 字号更正）：横滚容器、
# cardBg 底、td 14、cell maxW 288。
TB=$(awk '/case "Table":/,/case "Footnotes":/' "$SRC")
if echo "$TB" | grep -q 'ScrollView(.horizontal' \
   && echo "$TB" | grep -q 'T.cardBg' \
   && echo "$TB" | grep -q 'size: 14)' \
   && echo "$TB" | grep -q 'maxWidth: 288'; then
  ok "J20-9 表格横滚/外框/td 14/288 上限在位"
else
  bad "J20-9 表格形态缺失"
fi
# J20-10 脚注回链（M02 视觉）：ref_ids 消费 + ↩
# 32 盒在位（跳转动作子项存疑、不在此断言）。
if has 'item\["ref_ids"\]' "$SRC" \
   && has 'Text("↩")' "$SRC"; then
  ok "J20-10 脚注回链视觉形态在位"
else
  bad "J20-10 脚注回链缺失"
fi
# J20-11 徽章面板（F28/F29/F31）：宽 320 固定、
# 标题 dangerLight、条目图标 14；旧 min(320 收缩
# 与 maxHeight 280 写死零残留。
EB=$(awk '/^struct ErrBadgeOverlay/,/^final class DiagLog/' "$SRC")
if echo "$EB" | grep -q 'frame(width: 320)' \
   && echo "$EB" | grep -q 'T.dangerLight' \
   && echo "$EB" | grep -q 'frame(maxHeight: 360)' \
   && ! echo "$EB" | grep -q 'maxHeight: 280'; then
  ok "J20-11 徽章面板宽/限高/标题色在位"
else
  bad "J20-11 徽章面板形态缺失"
fi
# J20-12 列表文起点（M09）：em 公式在位、旧统一
# spacing 8 的非任务支已改判。
# 改判（impl_dt_layout_resilience）：标记框宽由定
# 值 18 改同源量 markerW = 1.125em（baseSize 16
# 时 ≡ 18、文起点 em 账不变），字面 '- 18' 随之
# 改 '- markerW'；本条锁的不变量（文起点 = em ×
# baseSize）不变。
# 再改判（fix_dynamic_type_follow，2026-11-27，
# fix_j20_anchor_reconcile 对账）：em 账基字改工
# 厂缩放值 scaledBase = FontFactory.scaledSize
# (baseSize, .body)——DT 报告 §2 定案：旧基字未
# 含类别缩放、与已缩放的正文 dynFont（同 .body
# 缩放表）脱档；DT36-4 已同源改锚（报告 §5），
# 本条第二子句 '* baseSize - markerW' 系其漏网
# 同源锚，现改 '* scaledBase - markerW' 并加锁
# 定义点。新账：markerW = 1.125 × scaledBase、
# 非任务支间距 = em × scaledBase − markerW
# （em 1.2/1.4 > 1.125、max(0,·) 恒不钳）→ 文起
# 点 = em × scaledBase；默认档（Large）UIFont-
# Metrics 恒等回基值、scaledBase ≡ baseSize，
# 文起点与旧账逐值等价（基字 16：markerW 18、
# 间距 ul 1.2 / ol 4.4 不变），任务支 spacing 8
# 不动。本条不变量改锁为：文起点 = em × 与正文
# 同档的缩放基字。
if has '(ordered ? 1.4 : 1.2)' "$SRC" \
   && has '* scaledBase - markerW' "$SRC" \
   && has 'let scaledBase = FontFactory.scaledSize(' "$SRC"; then
  ok "J20-12 列表文起点 em 公式在位"
else
  bad "J20-12 列表文起点未改"
fi
# J20-13 斜杠面板上翻 maxH 下限 120（审计 L-3，
# 横屏矮高保底）：slashLayer 段下限字面在位、旧
# 48 下限零残留。B-03 改判（fix_audit_batch4_
# editor.md）：定顶锚由整块顶 top 改光标行顶
# anchorTop（未锚定时逐字回退 top、行为等价），
# 下限式随锚改 anchorTop 口径；120 保底与旧
# 48 零残留不变量不变。
SL=$(awk '/private var slashLayer/,/private func slashPanelWidth/' "$SRC")
if echo "$SL" | grep -qF 'max(anchorTop - 10 - 12, 120)' \
   && echo "$SL" | grep -qF '? editor.slashAnchorTopY : top' \
   && ! echo "$SL" | grep -qF 'max(top - 10 - 12, 48)'; then
  ok "J20-13 斜杠上翻 maxH 下限 120 在位"
else
  bad "J20-13 斜杠 maxH 下限漂移（横屏靠顶锚点会被压至约 78）"
fi
# J20-14 背景色底表矮高列数（审计 L-6）：viewH
# < 500 时 8 列 1 行，常态 4 列。
if has 'ui.viewH < 500 ? 8 : 4' "$SRC"; then
  ok "J20-14 背景色底表矮高 8 列变体在位"
else
  bad "J20-14 背景色底表矮高变体缺失"
fi
# J20-15 MD 宽屏顶层分支（审计 L-8）：topLevel
# 标记定义 + 预览直子单点接线、wideTop 派生在
# 位、表格 minWidth 条件两处（表头/表行）。
MB=$(awk '/^struct MdBlockView/,/^struct MdCalloutView/' "$SRC")
if echo "$MB" | grep -qF 'var topLevel = false' \
   && echo "$MB" | grep -qF 'topLevel && Marks.spreadWidth > 0' \
   && [ "$(echo "$MB" | grep -c 'minWidth: wideTop')" = 2 ] \
   && [ "$(grep -c 'topLevel: true' "$SRC")" = 1 ]; then
  ok "J20-15 MD 宽屏顶层分支（标记/派生/表格 minWidth×2）"
else
  bad "J20-15 MD 宽屏分支缺件（pre/引用/表格宽屏口径未落）"
fi

echo "[21] 卡片圆角派生机制（0.9.52 根治，定案 fix_card_radius.md）"
# R21-1 派生机制本体：Radius 令牌表（与 Web
# tokens.css --radius-* 同源）+ concentric/lift
# 派生函数在位。
if has 'enum Radius' "$SRC" \
   && has 'static let cardS: CGFloat = 22' "$SRC" \
   && has 'static let cardL: CGFloat = 32' "$SRC" \
   && has 'static let grid: CGFloat = 26' "$SRC" \
   && has 'static let pill: CGFloat = 999' "$SRC" \
   && has 'static func concentric(outer: CGFloat,' "$SRC" \
   && has 'max(outer - inset, 0)' "$SRC" \
   && has 'static func lift(face: CGFloat)' "$SRC"; then
  ok "R21-1 Radius 令牌表 + concentric/lift 派生在位"
else
  bad "R21-1 Radius 派生机制缺失"
fi
# R21-2 拾起框走派生：LiftFrame 半径 = Radius.lift
# （面 + liftInset 同心外扩），旧写死 +4/-4 零残留。
if has 'Radius.lift(face: faceRadius)' "$SRC" \
   && has '.padding(-Radius.liftInset)' "$SRC" \
   && ! has 'faceRadius + 4' "$SRC"; then
  ok "R21-2 LiftFrame 半径/外扩走 Radius 派生"
else
  bad "R21-2 LiftFrame 仍写死外扩量"
fi
# R21-3 拾起面与真实面同源：liftFaceRadius 段内无
# 写死 return 数值（旧漂移 32/22 零残留）、图文/
# 混排走 cardS、音乐/附件走状态派生 helper。
LF=$(awk '/private var liftFaceRadius/,/private var rowDragOffset/' "$SRC")
if echo "$LF" | grep -q 'Radius.cardS' \
   && echo "$LF" | grep -q 'musicLiftFace' \
   && echo "$LF" | grep -q 'attachmentLiftFace' \
   && ! echo "$LF" | grep -qE 'return (10|12|22|32|999)\b'; then
  ok "R21-3 liftFaceRadius 全走 Radius/状态派生、无写死值"
else
  bad "R21-3 liftFaceRadius 仍有写死半径或派生缺失"
fi
# R21-4 状态派生 helper：音乐丸态派生胶囊、附件
# 单图/文件行分流在位。
if has 'private var musicLiftFace' "$SRC" \
   && has 'private var attachmentLiftFace' "$SRC" \
   && has 'if status == "input" { return Radius.pill }' "$SRC" \
   && has 'if isImage && fileCount == 1 { return Radius.cardL }' "$SRC"; then
  ok "R21-4 music/attachment 拾起面状态派生在位"
else
  bad "R21-4 拾起面状态派生 helper 缺失"
fi
# R21-5 卡面单源：图文/混排两面走 cardS、链接/音
# 乐四面走 cardL、链接丸走 pill；全文件 contentCard
# 写死半径（22/32/999）零残留。
IT=$(awk '/^struct ImgTextBlockView/,/^struct GlassCard/' "$SRC")
CB=$(awk '/^struct CardBlockView/,/^struct InlinePlayerView/' "$SRC")
if [ "$(echo "$IT" | grep -c 'contentCard(radius: Radius.cardS)')" -ge 2 ] \
   && [ "$(echo "$CB" | grep -c 'contentCard(radius: Radius.cardL)')" -ge 4 ] \
   && echo "$CB" | grep -q 'contentCard(radius: Radius.pill)' \
   && ! grep -qE 'contentCard\(radius: (22|32|999)\)' "$SRC"; then
  ok "R21-5 图文/链接/音乐卡面全走 Radius 令牌"
else
  bad "R21-5 卡面仍有写死半径"
fi
# R21-6 图片裁切与所在面同源：gallery/图片/视频/
# 附件图/MD 图裁切半径全走令牌，各段写死 22/32/10
# 零残留。
GB=$(awk '/^struct GalleryBlockView/,/^struct MusicPillView/' "$SRC")
IB=$(awk '/^struct ImageBlockView/,/^struct EditorHeaderView/' "$SRC")
VB=$(awk '/^struct VideoBlockView/,/^struct AttachmentRow/' "$SRC")
if echo "$GB" | grep -q 'LiftFrame(faceRadius: Radius.cardS)' \
   && ! echo "$GB" | grep -q 'cornerRadius: 22' \
   && echo "$IB" | grep -q 'LiftFrame(faceRadius: Radius.cardS)' \
   && ! echo "$VB" | grep -q 'cornerRadius: 22' \
   && has 'cornerRadius: Radius.cardL))' "$SRC" \
   && has 'cornerRadius: Radius.mdImage' "$SRC"; then
  ok "R21-6 图裁切半径与面同源（gallery/图片/视频/附件/MD）"
else
  bad "R21-6 图裁切仍有独立写死半径"
fi
# R21-7 修饰器默认值单源：三修饰器 struct 默认与
# View 扩展默认全走 Radius（无 = 22/32 写死默认）。
if [ "$(grep -c 'radius: CGFloat = Radius.cardL' "$SRC")" -ge 3 ] \
   && has 'func overlayCard(radius: CGFloat = Radius.cardS)' "$SRC" \
   && ! grep -qE 'radius: CGFloat = (22|32)\)' "$SRC" \
   && ! grep -qE 'radius: CGFloat = (22|32)$' "$SRC"; then
  ok "R21-7 修饰器默认值全走 Radius 单源"
else
  bad "R21-7 修饰器默认值仍有写死"
fi
# R21-8 首页方卡单源：26 写死零残留、Radius.grid
# 覆盖主卡/幽灵层/图卡裁切。
if ! grep -qE '(corner)?[Rr]adius: 26\)' "$SRC" \
   && [ "$(grep -c 'Radius.grid' "$SRC")" -ge 6 ]; then
  ok "R21-8 首页方卡半径全走 Radius.grid"
else
  bad "R21-8 首页方卡仍有写死 26"
fi
# R21-9 行面与编辑描边单源：BlockRow 背景/描边
# quote/block 三元走令牌、卡编辑描边走 cardS/cardL；
# 附件文件行半径走 Radius.attachmentFile 条件派生
# （宽屏 cardS=22 / 常态 cardL=32，Web editor.css
# :726 级联实证；S1「恒 32」裁断已被实证推翻，见
# fix_attachment_radius_wide.md）：派生本体唯一
# （wide ? cardS : cardL 全文件仅一处）、行面与拾
# 起面同派生同源、附件图片面恒 cardL 不经派生。
AR=$(awk '/^struct AttachmentRow/,/^struct AttachmentBlockView/' "$SRC")
if has '? Radius.quote : Radius.block' "$SRC" \
   && has '? Radius.cardS : Radius.cardL' "$SRC" \
   && has 'static func attachmentFile(wide: Bool)' "$SRC" \
   && [ "$(grep -c 'wide ? cardS : cardL' "$SRC")" -eq 1 ] \
   && echo "$AR" | grep -q 'contentCard(radius: Radius.attachmentFile(wide: wide))' \
   && ! echo "$AR" | grep -q 'contentCard(radius: Radius.cardL)' \
   && echo "$LF" | grep -q 'Radius.attachmentFile(' \
   && echo "$LF" | grep -q 'wide: editor.columnsActive' \
   && echo "$LF" | grep -q 'if isImage && fileCount == 1 { return Radius.cardL }' \
   && ! grep -q 'contentCard(radius: wide' "$SRC"; then
  ok "R21-9 行面/描边/附件行半径走 Radius 条件派生（宽屏 22/常态 32、两面同源）"
else
  bad "R21-9 行面半径仍有写死或附件派生缺失"
fi

echo "[22] 修复批 K（音乐卡与图片线 F1–F11，定案 impl_batch_k.md）"
CBK=$(awk '/^struct CardBlockView/,/^struct InlinePlayerView/' "$SRC")
# K22-1 F1 销账（J1 已修、本批复核）：附件判图单
# 一口径 attIsImage（清单 MIME 优先 + 扩展集含
# svg/avif），旧本地扩展名表 imageExts 零残留。
if has 'static func attIsImage(name: String,' "$SRC" \
   && has '"bmp", "svg", "avif", "heic", "heif"' "$SRC" \
   && has 'MemoItem.attIsImage(' "$SRC" \
   && ! grep -q 'imageExts' "$SRC"; then
  ok "K22-1 F1 附件判图 attIsImage 单一口径（MIME 优先/svg/avif）"
else
  bad "K22-1 F1 附件判图口径回潮"
fi
# K22-2 F3 裁定保留：缩放上限 ×4 + 保底 1.0 原式
# 在位（保底使超大图 1:1 像素级查看恒可达）。
if grep -qF 'sv.maximumZoomScale = max(base * 4, 1)' "$SRC"; then
  ok "K22-2 F3 缩放上限 max(base*4, 1) 裁定式在位"
else
  bad "K22-2 F3 缩放上限式漂移"
fi
# K22-3 F2：IMGPAGE nat= 记自然像素（size×scale），
# 旧点数式零残留。
if grep -qF 'nat=\(Int(img.size.width * img.scale))' "$SRC" \
   && ! grep -qF 'nat=\(Int(img.size.width))x' "$SRC"; then
  ok "K22-3 F2 IMGPAGE nat= 像素口径（size×scale）"
else
  bad "K22-3 F2 IMGPAGE nat= 仍记点数"
fi
# K22-4 F4：附件分享单一实现——缺失记 ATT
# missing 不弹面、结局经 completionWithItems-
# Handler 记 ATT 行；旧两处 try? 吞错实现零残留。
if has 'func shareAttachmentFile(library: Library,' "$SRC" \
   && grep -qF 'ATT open \(fid) -> missing' "$SRC" \
   && has 'completionWithItemsHandler' "$SRC" \
   && has 'var shareCompletion' "$SRC" \
   && ! grep -q 'private func share(fid:' "$SRC" \
   && ! grep -q 'private func shareAttachment(fid:' "$SRC"; then
  ok "K22-4 F4 附件分享单一实现 + ATT 结局打点"
else
  bad "K22-4 F4 附件分享仍有旧实现或打点缺失"
fi
# K22-5 F7：musicCard input 分支 + 空态胶囊在位，
# CardBlockView 内 EmptyView 兜底零残留；两胶囊
# 半径走 Radius.pill。
if echo "$CBK" | grep -q 'status == "input"' \
   && echo "$CBK" | grep -q 'inputPill' \
   && echo "$CBK" | grep -q 'emptyPill' \
   && has 'media.music_paste_hint' "$SRC" \
   && has 'media.music_click_hint' "$SRC" \
   && ! echo "$CBK" | grep -q 'EmptyView()'; then
  ok "K22-5 F7 音乐 input/空态胶囊呈现（不再整块隐形）"
else
  bad "K22-5 F7 音乐 input/空态仍无呈现"
fi
# K22-6 F8：error 卡 URL 可点开（openCard 闸）+
# 重试钮接语言键，硬编码「重试」零残留。
if [ "$(echo "$CBK" | grep -c 'onTapGesture { openCard() }')" -ge 4 ] \
   && has 'media.retry' "$SRC" \
   && ! echo "$CBK" | grep -q 'Text("重试")'; then
  ok "K22-6 F8 error 卡 URL 可点 + 重试钮语言键"
else
  bad "K22-6 F8 error 卡 URL 仍不可点或重试硬编码"
fi
# K22-7 F9：兜底胶囊 URL 常显 + error 注记走语
# 言键，旧「预览不可用」替换式字面量零残留。
if has 'media.preview_unavailable' "$SRC" \
   && ! grep -q '"预览不可用"' "$SRC"; then
  ok "K22-7 F9 兜底胶囊 URL 常显 + 注记语言键"
else
  bad "K22-7 F9 兜底胶囊仍以注记替换 URL"
fi
# K22-8 F10：哔哩哔哩副标题抑制全式（来源 ||
# video 且 URL 含 bilibili/b23.tv）。
if echo "$CBK" | grep -q 'private var isBilibili' \
   && echo "$CBK" | grep -q 'if !isMusic, isBilibili' \
   && echo "$CBK" | grep -q 'cardURL.contains("bilibili")' \
   && echo "$CBK" | grep -q 'cardURL.contains("b23.tv")'; then
  ok "K22-8 F10 B 站副标题抑制 URL 分支在位"
else
  bad "K22-8 F10 B 站副标题抑制仍缺 URL 分支"
fi
# K22-9 F5：ErrBadge 条目带 loc/detail、时间改
# 完整 locale 串（类段内旧 HH:mm:ss 格式串零残
# 留）、detail 行数上限与面板堆栈块在位。
EBK=$(awk '/^final class ErrBadge/,/^struct ErrBadgeOverlay/' "$SRC")
EBO=$(awk '/^struct ErrBadgeOverlay/,/^final class DiagLog/' "$SRC")
if echo "$EBK" | grep -q 'var loc: String' \
   && echo "$EBK" | grep -q 'var detail: String' \
   && echo "$EBK" | grep -q 'f.dateStyle = .medium' \
   && ! echo "$EBK" | grep -q 'dateFormat = "HH:mm:ss"' \
   && echo "$EBK" | grep -q 'kind == "WARN" ? 4 : 8' \
   && echo "$EBO" | grep -q 'e.detail.isEmpty' \
   && echo "$EBO" | grep -q 'e.message.prefix(120)'; then
  ok "K22-9 F5 徽章条目 loc/detail + 完整时间 + 堆栈块"
else
  bad "K22-9 F5 徽章条目信息量未补齐"
fi
# K22-10 F6 销账（I3 已修、本批复核）：面板标题
# 与清除钮走 errbadge 语言键。
if echo "$EBO" | grep -q 'errbadge.title_error' \
   && echo "$EBO" | grep -q 'errbadge.clear'; then
  ok "K22-10 F6 徽章面板文案语言键（销账复核）"
else
  bad "K22-10 F6 徽章面板文案回潮硬编码"
fi
# K22-11 F11：IP 兜底城名过英转中表——cityToCn
# 在位、fetch 生产点单点应用、表 60 条（抽核首
# 尾与港台条目）。
if has 'static func cityToCn(_ name: String)' "$SRC" \
   && has 'ipCity = Self.cityToCn(' "$SRC" \
   && has 'case "Beijing": return "北京"' "$SRC" \
   && has 'case "Hong Kong": return "香港"' "$SRC" \
   && has 'case "Tainan": return "台南"' "$SRC" \
   && [ "$(grep -c 'case ".*": return "' "$SRC")" -ge 60 ]; then
  ok "K22-11 F11 IP 城名英转中表 + 生产点单点应用"
else
  bad "K22-11 F11 IP 城名未转中文"
fi
# K22-12 图片页可用区公式对齐 Web（审计 L-4）：
# availH = 全高 − 126 − 40 − safeBottom，呈现
# 顶/底让位同值（判定与呈现同源）；旧 −66 与顶
# 让 66 零残留于本页段。
IPG=$(awk '/struct ImagePageView/,/^struct ItemImageView/' "$SRC")
if echo "$IPG" | grep -qF 'geo.size.height - 126' \
   && echo "$IPG" | grep -qF '.padding(.top, 126)' \
   && echo "$IPG" | grep -qF '40 + geo.safeAreaInsets.bottom' \
   && ! echo "$IPG" | grep -qF 'height - 66' \
   && ! echo "$IPG" | grep -qF '.padding(.top, 66)'; then
  ok "K22-12 图片页可用区公式（顶 126 / 底 40+safe）对齐 Web"
else
  bad "K22-12 图片页可用区公式漂移"
fi
# K22-13 图片页旋转复位（审计 L-5）：视口尺寸
# 变化时倍率钳回 base + 偏移归零（lastViewport
# 记账、resized 分支、contentOffset 复位三件）。
if has 'var lastViewport: CGSize' "$SRC" \
   && has 'let resized = lastViewport != viewport' "$SRC" \
   && has 'sv.contentOffset = CGPoint(' "$SRC"; then
  ok "K22-13 图片页视口变化复位（倍率/偏移）在位"
else
  bad "K22-13 图片页旋转复位缺件"
fi

echo "[23] 留白根治 + 复合卡内角规矩 + 浮层内容定高（0.9.54，定案 fix_lift_spacing.md）"
BR=$(awk '/private var rowMain/,/private var liftFaceRadius/' "$SRC")
# S23-1 行盒间距机制：HStack spacing 恒 0（尾随
# 幻影间距退役）、旧三元 spacing 零残留；语义间
# 隙就地（todo 文侧 leading 10）。
if echo "$BR" | grep -q 'spacing: 0) {' \
   && ! grep -q 'spacing: block.type == "todo" ? 10 : 8' "$SRC" \
   && echo "$BR" | grep -q 'block.type == "todo" ? 10 : 0'; then
  ok "S23-1 BlockRow 间距恒 0、间隙就地（内容槽 = 行盒全宽）"
else
  bad "S23-1 行盒幻影间距回潮或间隙未就地"
fi
# S23-2 面与行盒同源：行内横向 padding 只剩图/
# gallery 的 36 对称内缩两处（其面框在子视图内
# 派生）；行级 liftFaceRadius 的 image 分支恒
# nil（面在子视图、框随面）。
LF=$(awk '/private var liftFaceRadius/,/private var rowDragOffset/' "$SRC")
if [ "$(echo "$BR" | grep -c 'padding(.horizontal,')" = 2 ] \
   && [ "$(echo "$LF" | grep -c 'return nil')" -ge 2 ]; then
  ok "S23-2 卡面 = 行盒同源、图片面框子视图内派生"
else
  bad "S23-2 行内出现新的单侧内缩或图片行级出框回潮"
fi
# S23-3 引用文内缩单源：行 leading 17（条 3 +
# padding 14）、条挂面缘 overlay（段内 quoteBar
# 只剩 overlay 一处、行内占位条零残留）。
if echo "$BR" | grep -q 'block.type == "quote" ? 17' \
   && echo "$BR" | grep -q '.overlay(alignment: .leading)' \
   && [ "$(echo "$BR" | grep -c 'T.quoteBar')" = 1 ]; then
  ok "S23-3 引用条面缘化、文内缩 17/14 与 MD 同口径"
else
  bad "S23-3 引用行内条回潮或文内缩漂移"
fi
# S23-4 内角规矩机制：CornerRect 按位取角形状
# 在位；图文卡六子面、链接/音乐封面 + 骨架、
# gallery 瓦按位、首页图卡图区全走按位取角。
IT=$(awk '/^struct ImgTextBlockView/,/^struct GlassCard/' "$SRC")
CB=$(awk '/^struct CardBlockView/,/^struct InlinePlayerView/' "$SRC")
GB=$(awk '/^struct GalleryBlockView/,/^struct MusicPillView/' "$SRC")
if has 'struct CornerRect: Shape' "$SRC" \
   && [ "$(echo "$IT" | grep -c 'CornerRect(')" -ge 6 ] \
   && [ "$(echo "$CB" | grep -c 'CornerRect(')" -ge 2 ] \
   && echo "$GB" | grep -q '.clipShape(tileCorners(ix, items.count))' \
   && echo "$GB" | grep -q 'tileCorners(ix, 2)' \
   && has 'clipShape(CornerRect(tl: Radius.grid,' "$SRC"; then
  ok "S23-4 复合卡子面按位取角全点位（外圆内直）"
else
  bad "S23-4 子面按位取角缺失或回退全角裁切"
fi
# S23-5 gallery 间距两态：内容 gap 4 / 空态
# gap 6 走 gridGap 单点派生，写死 4 两处零残留。
if echo "$GB" | grep -q 'items.isEmpty ? 6 : 4' \
   && echo "$GB" | grep -q 'spacing: gridGap' \
   && ! echo "$GB" | grep -q 'GridItem(.flexible(), spacing: 4)' \
   && ! echo "$GB" | grep -q '], spacing: 4)'; then
  ok "S23-5 gallery 间距 gridGap 派生（4/6 两态）"
else
  bad "S23-5 gallery 间距写死回潮"
fi
# S23-6 混排文贴顶：文半 frame 整高 + topLeading
# （与 textLabel 自身 topLeading 合计 ≥2 处）。
if echo "$IT" | grep -q 'maxHeight: .infinity,' \
   && [ "$(echo "$IT" | grep -c 'alignment: .topLeading')" -ge 2 ]; then
  ok "S23-6 混排文本盒整高贴顶（Web .itr-text 口径）"
else
  bad "S23-6 混排文垂直居中回潮"
fi
# S23-7 图片空占位面：玻璃面 cardL + padding 24
# + 面内 LiftFrame（Web .atomic-placeholder）。
IB=$(awk '/^struct ImageBlockView/,/^struct EditorHeaderView/' "$SRC")
if echo "$IB" | grep -q '.glassCard(radius: Radius.cardL)' \
   && echo "$IB" | grep -q 'LiftFrame(faceRadius: Radius.cardL)' \
   && echo "$IB" | grep -q '.padding(24)'; then
  ok "S23-7 图片空占位成面、框随面派生"
else
  bad "S23-7 图片空占位无面或行级借位回潮"
fi
# S23-8 ••• 菜单内容定高：menuPanelH 实测回写
# 在位、面板帧高 = min(内容, cap)、旧撑满式
# maxHeight 帧零残留。
MP=$(awk '/private var menuPanel/,/private func shareExported/' "$SRC")
if has '@Published var menuPanelH: CGFloat = 0' "$SRC" \
   && echo "$MP" | grep -q 'ui.menuPanelH > 0' \
   && echo "$MP" | grep -q '.frame(height: min(' \
   && ! grep -q 'frame(maxHeight: max(200, ui.viewH - 67))' "$SRC"; then
  ok "S23-8 ••• 菜单面板内容定高（实测回写）"
else
  bad "S23-8 菜单面板撑满回潮或回写缺失"
fi

echo "[24] 标题胶囊二次编辑根治（字段常驻 + 坞态冻结，定案 fix_title_capsule_reedit.md）"
HDR=$(awk '/^struct EditorHeaderView/,/^    \/\/\/ 背景色底表/' "$SRC")
CAP=$(awk '/^private func titleCapsule/,/^private var capsuleWidth/' "$SRC")
# T24-1 字段常驻（B-4 路径 B 改写）：字段 =
# TitleTextField representable（UIView 实例承
# 载身份，常驻比 SwiftUI 字段更硬）；截断态仍
# 以 opacity 0 在层级、覆盖层呈现；SwiftUI 原
# 生 TextField 与旧条件替换式零残留。
if echo "$CAP" | grep -q 'ZStack {' \
   && echo "$CAP" | grep -q 'TitleTextField(' \
   && echo "$CAP" | grep -qF '.opacity(truncated ? 0 : 1)' \
   && ! echo "$CAP" | grep -qE '(^|[^a-zA-Z])TextField\(' \
   && ! echo "$CAP" | grep -q 'if titleFocused ||'; then
  ok "T24-1 标题字段常驻层级（representable 单一身份、旧字段零残留）"
else
  bad "T24-1 标题字段仍被条件替换出层级或 representable 缺失"
fi
# T24-2 覆盖层置焦路径（B-4 改写）：截断覆盖层
# 在位、整行命中面、点按经 SpatialTapGesture
# 取位调具名入口 activateTitleFromCapsule
# （入口定义在 HDR 段内、记行 + 置焦一份）。
if echo "$CAP" | grep -q 'if truncated {' \
   && echo "$CAP" | grep -q 'contentShape(Rectangle())' \
   && echo "$CAP" | grep -q 'SpatialTapGesture()' \
   && echo "$CAP" | grep -q 'activateTitleFromCapsule(' \
   && echo "$HDR" | grep -q 'EDIT title focus via=capsule'; then
  ok "T24-2 截断覆盖层点按置焦（具名入口 + 取位手势 + Diag 入口行）"
else
  bad "T24-2 截断覆盖层置焦路径缺失"
fi
# T24-3 坞态单点派生：dockCompact 定义一处、
# headerOverlay/capsuleWidth/动画值共用；段内
# scrollY > 30 字面仅剩定义处一处（防口径漂移
# 与会话期坞翻转重建字段）。
if [ "$(echo "$HDR" | grep -c 'scroll.scrollY > 30')" = 1 ] \
   && [ "$(echo "$HDR" | grep -c 'dockCompact')" -ge 4 ] \
   && echo "$HDR" | grep -q 'let compact = dockCompact'; then
  ok "T24-3 坞态 dockCompact 单点派生（编辑期冻结、双处共用）"
else
  bad "T24-3 坞态派生漂移或会话期仍可翻转"
fi
# T24-4 会话打点：聚焦落定记 session begin 行
# （主线经桥读 Diag 判读二次进入是否真落焦）。
if echo "$CAP" | grep -q 'EDIT title session begin'; then
  ok "T24-4 标题会话 Diag 打点在位"
else
  bad "T24-4 标题会话无 Diag 打点"
fi
# T24-5 既有行为锚（防回退，B-4 联动）：提交
# trim + 空回退（I4 换键后走 editor.untitled
# 键、字面锁同步改判）、Esc 快照源 titleBase
# 两点不移；Enter 收口锚移到字段 Coordinator
# 的 shouldReturn（置 focused=false 辞焦 →
# didEnd 结束支路提交，与旧 onSubmit 等价）。
if echo "$HDR" | grep -q 'trimmed.isEmpty ? Lang.t("editor.untitled") : trimmed' \
   && echo "$CAP" | grep -q 'ui.titleBase = editor.title' \
   && grep -q 'func textFieldShouldReturn' "$TFIELD" \
   && grep -q 'control.focused = false' "$TFIELD"; then
  ok "T24-5 标题提交/快照既有口径 + Enter 收口在 Coordinator 在位"
else
  bad "T24-5 标题既有行为回退"
fi
# T24-6 两分支同构锚：titleCapsule 全段只一处
# 定义、两分支各调一次（compact true/false）；
# 字段宿主与宽公式只有一份，禁分支内另起胶
# 囊构造——竖排渲染异常的根治落在 represent-
# able 尺寸契约（T26-8）、两分支同构是其前提
# （fix_title_vertical_render.md）。
if [ "$(echo "$HDR" | grep -c 'private func titleCapsule')" = 1 ] \
   && [ "$(echo "$HDR" | grep -c 'titleCapsule(compact: true)')" = 1 ] \
   && [ "$(echo "$HDR" | grep -c 'titleCapsule(compact: false)')" = 1 ]; then
  ok "T24-6 两分支共用同一胶囊构造点（定义一处、调用两处）"
else
  bad "T24-6 胶囊构造点分裂（分支内另起构造）"
fi
# T24-7 口径对齐锁（AUD-B-02，用户 2026-11-28
# 裁定）：标题胶囊以 Web title.rs / title_
# controller.rs 现行码为准绳——非编辑态超 10
# 标量截断（前 10 +「…」）为正口径，旧 MEMORY
# 「恒显全文」口径作废（该口径在断言层本无锁
# 定，本条为新口径的防回潮锁，非改判旧锁）。
# 锁三点：① 量测串 shown 的状态分流（未聚焦
# 且 >10 标量走截断串）在位；② 截断呈现串构
# 造点（落点入口 disp / 覆盖层 / shown）合计
# ≥3；③ 定宽公式边框项 +41 在位、旧 +40 零残
# 留（Web sync_width = 内容 + 内距 40 + 边
# 框 1，border-box）。
# ③ 沿革（居中批 fix_title_capsule_center）：
# 定宽算式单点化至纯核心 TitleCapsuleLayout
# （TitleTapCaret.swift），③ 改盯纯核心公式
# 字面 + 视图委托调用、HDR 内旧式字面零残
# 留；+41 口径与数值不变。
if echo "$HDR" | grep -q 'unicodeScalars.count > 10 && !titleFocused' \
   && [ "$(echo "$HDR" | grep -c 'scalarPrefix(')" -ge 3 ] \
   && grep -q 'max(titleW, metaW) + 41' "$TCARET" \
   && echo "$HDR" | grep -q 'TitleCapsuleLayout.capsuleWidth(' \
   && ! echo "$HDR" | grep -q 'max(titleW, metaW) + 4'; then
  ok "T24-7 标题口径对齐 Web（非编辑态 10 标量截断 + 定宽 +41 含边框）"
else
  bad "T24-7 标题口径漂移（截断分流/呈现构造/定宽边框项任一缺失）"
fi
# T24-8 预览态居中机制锁（fix_title_capsule_
# center）：预览（shown）态两呈现者的字形居
# 中指令必须显式在位——字段 textAlignment =
# .center（TFIELD 定义侧）、截断覆盖层 multi-
# lineTextAlignment(.center)（CAP 段）。覆盖
# 层此前无自身居中指令：其 Text 帧占满行宽
# 后，字形在帧内按缺省 .leading 排布、贴左
# 内距（预览态偏心层位）；仅有 frame 满宽 +
# 居中对齐视图挡不住字形排布。落点算式的居
# 中前提（[26] startX 居中式）与本条同源。
if grep -q 'f.textAlignment = .center' "$TFIELD" \
   && echo "$CAP" | grep -q 'multilineTextAlignment(.center)'; then
  ok "T24-8 预览态居中指令双形态在位（字段 .center + 覆盖层 multiline .center）"
else
  bad "T24-8 预览态居中指令缺失（覆盖层字形居中回潮）"
fi
# T24-9 定宽公式 + 帧链模型表驱动：TitleTap-
# Caret.swift（含 TitleCapsuleLayout）与内
# 嵌断言体一起以宿主 swiftc 编译运行。两部
# 分都不自证（fix_title_center_short_text
# 改判）：① 定宽公式案例的期望宽按 Web
# sync_width 手算、独立于被测算式；② 帧链
# 模型 inkCenterDeviation 以字段帧构型为
# 入参——定宽帧构型（原点 = 内距、帧宽 =
# 行宽）偏差归 0，坏构型（内容宽帧坐行左
# 缘）须复现 0.9.63/0.9.65 两次设备实测偏
# 差（15.3/14.7，容差 1.6 含墨迹/进距口径
# 差）：同一模型双向受验，不再是旧
# centerDeviation 把居中原点写死进算式、
# 偏差按定义恒 0 的自证式（已废除）。构型
# 本身（app 实际建成哪种帧）不在本表职权
# 内：由 T24-10（定宽帧构造）+ T24-12
# （行宽同源 + 探针链）结构锁守、由设备
# 探针 title_geometry 实测终判。
# 落点算式由 [26] 守。
T24D=$(mktemp -d)
cat > "$T24D/main.swift" <<'TITLEEOF'
// 标题胶囊量测（verify [24] T24-9）：定宽
// 公式 + 帧链模型案例矩阵。期望宽按 Web
// sync_width 公式手算（独立于被测算式）；
// 帧链模型以帧构型为入参双向受验（定宽帧
// 构型归 0、设备坏构型复现实测偏差），非
// 旧 centerDeviation 的恒 0 自证式。
import Foundation

var failures = 0
func runCase(_ name: String, titleW: Double,
             metaW: Double, avail: Double,
             expectW: Double) {
    let w = TitleCapsuleLayout.capsuleWidth(
        titleW: titleW, metaW: metaW,
        avail: avail)
    if abs(w - expectW) > 0.001 {
        failures += 1
        print("FAIL \(name) width got \(w) want \(expectW)")
    }
    // 帧链：行宽由胶囊宽独立导出（内距两侧
    // 对称）；定宽帧构型（原点 = 左内距、
    // 帧宽 = 行宽）下偏差归 0。构型是本式
    // 的输入、不是结论——app 实际构型由
    // T24-10/12 结构锁 + 设备探针守。
    let fw = TitleCapsuleLayout
        .fieldFrameWidth(capsuleWidth: w)
    if abs(fw - (expectW - 40)) > 0.001 {
        failures += 1
        print("FAIL \(name) fieldFrameW got \(fw) want \(expectW - 40)")
    }
    let d = TitleCapsuleLayout
        .inkCenterDeviation(
            capsuleWidth: w,
            fieldFrameX: TitleCapsuleLayout
                .hPad,
            fieldFrameWidth: fw)
    if d > 0.5 {
        failures += 1
        print("FAIL \(name) fixed-frame deviation \(d)")
    }
}

// 坏构型对照（模型双向受验）：帧宽 = 内容
// 进距宽、原点 = 行左缘——0.9.63/0.9.65
// 两次设备实测的字段构型。模型须复现其
// 实测偏差（期望取截图像素量测值；模型按
// 进距宽算得 14.0/13.5，与墨迹量测差
// 1.3/1.2 = 墨迹宽 < 进距宽的口径差，
// 容差 1.6）。
func runBroken(_ name: String,
               capsuleW: Double,
               contentW: Double,
               expectDev: Double) {
    let d = TitleCapsuleLayout
        .inkCenterDeviation(
            capsuleWidth: capsuleW,
            fieldFrameX: TitleCapsuleLayout
                .hPad,
            fieldFrameWidth: contentW)
    if abs(d - expectDev) > 1.6 {
        failures += 1
        print("FAIL \(name) broken-frame deviation got \(d) want ≈\(expectDev)")
    }
}

// 全文态短标题：宽由标题定（70 > meta 40）。
runCase("full-title", titleW: 70, metaW: 40,
        avail: 300, expectW: 111)
// meta 更宽：宽由 meta 定（180），短标题居
// 中于宽胶囊——偏心在此形态最显。
runCase("meta-wider", titleW: 42, metaW: 180,
        avail: 400, expectW: 221)
// 本案数值格（0.9.63 真机）：标题「使用
// 指南」4 字（量测宽 55、非截断、字段形态
// 呈现）× meta「09:56 · 共 147 字」全串
// （宽 82）——宽由 meta 定（123）、行宽
// 83。本格锁：定宽公式在本案数值下同值 +
// 定宽帧构型偏差归 0；同案坏构型（字段帧
// = 内容宽坐行左缘）的实测偏差 15.3 由
// 下方 runBroken 对照复现。
runCase("device-short-title-wide-meta",
        titleW: 55, metaW: 82,
        avail: 300, expectW: 123)
// 无标题占位格（0.9.65 真机）：空标题新建
// 篇——量测串 =「无标题」（进距宽 42），
// meta「13:14 · 共 0 字」宽 68 定胶囊宽
// 109（像素量测互证，见三修报告）。本格
// 锁空标题分流取占位串量宽 + 定宽公式 +
// 定宽帧构型归 0；占位呈现者的段落样式由
// T24-11 锁、同案坏构型实测偏差 14.7 由
// runBroken 对照复现。
runCase("untitled-placeholder",
        titleW: 42, metaW: 68,
        avail: 300, expectW: 109)
// 截断态：titleW = 显示串宽 154（10 字 +
// 省略号），meta 100。
runCase("truncated", titleW: 154, metaW: 100,
        avail: 500, expectW: 195)
// 截断 × meta 更宽：宽由 meta 定（200），显
// 示串 154 居中于 241 宽胶囊——旧覆盖层按
// leading 排布时偏差 (201−154)/2 = 23.5、
// 为偏心最显形态，居中后归 0。
runCase("truncated-meta-wider", titleW: 154,
        metaW: 200, avail: 500, expectW: 241)
// 钳上限：avail 266（坞宽 390 − 124），公式
// 宽 641 钳至 266；行宽 226、定宽帧构型
// 中心仍合。
runCase("clamped-max", titleW: 600, metaW: 100,
        avail: 266, expectW: 266)
// 钳下限：紧凑态 meta 不计（0），公式宽 51
// 抬至下限 66。
runCase("clamped-min", titleW: 10, metaW: 0,
        avail: 300, expectW: 66)
// avail 低于下限：maxW 以 66 兜底。
runCase("avail-floor", titleW: 200, metaW: 50,
        avail: 50, expectW: 66)
// 坏构型对照：两次设备实测构型（内容宽帧
// 坐行左缘）须被同一模型复现。
runBroken("device-0.9.63-short-title",
          capsuleW: 123, contentW: 55,
          expectDev: 15.3)
runBroken("device-0.9.65-placeholder",
          capsuleW: 109, contentW: 42,
          expectDev: 14.7)

if failures == 0 {
    print("TITLE_CENTER_PASS")
} else {
    print("TITLE_CENTER_FAIL \(failures)")
    exit(1)
}
TITLEEOF
SWIFTC24=""
for c24 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c24" ] && [ -x "$c24" ]; then
    SWIFTC24="$c24"; break
  fi
done
if [ -n "$SWIFTC24" ] \
   && "$SWIFTC24" -O -o "$T24D/center_test" \
        "$TCARET" "$T24D/main.swift" 2>"$T24D/err.log" \
   && [ "$("$T24D/center_test" 2>/dev/null)" = "TITLE_CENTER_PASS" ]; then
  ok "T24-9 标题量测表驱动全过（定宽公式 + 帧链模型双向受验）"
else
  bad "T24-9 标题量测失败（swiftc=$SWIFTC24，详见编译/运行输出）"
  sed 's/^/    T24-9: /' "$T24D/err.log" | head -5
  "$T24D/center_test" 2>/dev/null | sed 's/^/    T24-9: /' | head -5
fi
rm -rf "$T24D"
# T24-10 字段定宽帧机制锁（fix_title_
# center_short_text 改判；前身为 fix_title_
# capsule_center2 的弹性帧锁）：字段行内
# 居中两度栽在「按意图断言」——初版
# sizeThatFits 契约（0.9.63 真机证伪：字
# 段有效帧为内容宽且坐行左缘、偏差 =
# (行宽 − 标题宽)/2）、二修弹性帧
# .frame(maxWidth: .infinity)（提议经父
# 级透传、决定性量测仍落内容宽一档，
# 0.9.65 真机复报真实短标题仍不居中、证
# 伪）。现行构造：字段帧宽由胶囊自身定
# 宽值派生钉死——字段修饰链（CAP 段
# TitleTextField( 起、至 if truncated
# 止）内必须有 .frame(width:
# capsuleWidth - 40)（定宽帧不经协商、
# 恒以定值向子视图提议），且同段不得再
# 有弹性帧（防新旧叠加回潮）。覆盖层自
# 身的满宽帧在 if truncated 之后、不在
# 本段，不构成代偿。本锁守构造、实效由
# 设备探针 title_geometry 终判（T24-12
# 锁其链）。
FIELDSEG=$(echo "$CAP" | awk '/TitleTextField\(/,/if truncated \{/')
if echo "$FIELDSEG" | grep -q 'TitleTextField(' \
   && echo "$FIELDSEG" | grep -qF '.frame(width: capsuleWidth - 40)' \
   && ! echo "$FIELDSEG" | grep -qF '.frame(maxWidth: .infinity)'; then
  ok "T24-10 字段定宽帧在位（帧宽由胶囊定宽值派生、与协商脱钩）"
else
  bad "T24-10 字段定宽帧缺失或弹性帧回潮（短标题居中回潮）"
fi
# T24-11 占位居中机制锁（fix_title_center_
# short）：空标题时呈现者是字段占位串
# （attributedPlaceholder），其绘制对齐
# 只认属性串自带的段落样式——字段 text-
# Alignment（T24-8）只管文本本体、T24-9
# 模型以量测串为呈现文本、T24-10 锁帧
# 宽，三者均不及占位：0.9.65 真机空标题
# 截图标题墨迹贴行左缘（偏差 −14.7pt）
# 逃过全部既有断言。结构锁：占位串构造
# 单点（TitleTextField.applyFont，全仓
# 唯一 attributedPlaceholder 赋値处）内
# 必须有段落样式 .center 且经 .para-
# graphStyle 入串。
APPLYSEG=$(awk '/static func applyFont/,/^    }/' "$TFIELD")
if echo "$APPLYSEG" | grep -q 'attributedPlaceholder' \
   && echo "$APPLYSEG" | grep -q 'alignment = .center' \
   && echo "$APPLYSEG" | grep -q '.paragraphStyle'; then
  ok "T24-11 占位串居中段落样式在位（空标题占位呈现者自带居中指令）"
else
  bad "T24-11 占位串缺居中段落样式（空标题占位左偏回潮）"
fi
# T24-12 行宽同源 + 设备探针链锁（fix_
# title_center_short_text）：① 行宽同源
# ——字段定宽帧与落点映射的 rowW 必须同
# 出「胶囊宽 − 40」一式：MomentApp.swift
# 内该字面恰两处（定宽帧 + activate-
# TitleFromCapsule 的 rowW），任一处改道
# （改内距、改帧宽来源）即不再同源、本
# 锁红。② 探针链——设备侧量测通道全链
# 在位：控制面字段弱引用 + 几何读数法
# （TitleTextField）、胶囊注册面 title-
# Geometry 状态键（MomentApp）、探针与
# 场景登记（MomentBridgeUITest）。本锁守
# 「下版装机后主线能以数字验收」的通道
# 本身；偏差数值由景 title_center_
# geometry 装机首跑给出。
ACTSEG=$(awk '/private func activateTitleFromCapsule/,/^}/' "$SRC")
if [ "$(grep -c 'capsuleWidth - 40' "$SRC")" = 2 ] \
   && echo "$ACTSEG" | grep -q 'capsuleWidth - 40' \
   && has 'weak var fieldView' "$TFIELD" \
   && has 'func titleGeometryString' "$TFIELD" \
   && has '"titleGeometry"' "$SRC" \
   && has '"title_geometry"' "$UITEST" \
   && has 'title_center_geometry' "$UITEST"; then
  ok "T24-12 行宽同源（定宽帧与落点 rowW 同式）+ 标题几何探针链在位"
else
  bad "T24-12 行宽同源破裂或标题几何探针链缺环"
fi

echo "[25] 桥内 UI 自检驱动（方案 plan_ui_selftest_driver.md）"
# 本组随 U 批分期生长：U0 地基条目（B25-U0-*）
# 先行；方案 §7.3 的 B25-1..9（注册表/锚点/夹具
# 卫生/禁区等）属 U1–U3，落码时按原编号补入本
# 组，此处留位注明，不预设空断言。
# B25-U0-1 在席注册表：定义在转场宿主文件；登
# 记点在 push/替换两处会话点、注销点在会话收口
# （endSession），且注销带会话令牌（防旧会话误
# 清新在席）。
if has 'final class EditorSeatRegistry' "$TRANS" \
   && has 'func seat(editor:' "$TRANS" \
   && has 'func unseat(token:' "$TRANS" \
   && [ "$(grep -c 'EditorSeatRegistry.shared.seat(' "$TRANS")" = 2 ] \
   && has 'EditorSeatRegistry.shared.unseat(' "$TRANS"; then
  ok "B25-U0-1 在席注册表在位（登记×2/令牌注销）"
else
  bad "B25-U0-1 在席注册表或会话点接线缺失"
fi
# B25-U0-2 导航通道：请求-应答两口（open/close）
# + 接线口 + 宿主关闭点（pop 回根）；打开走
# pushEditor 正规路径（通道内无第二呈现栈的字
# 面标志：popToRootViewController 只此关闭点）。
if has 'final class BridgeNavigationChannel' "$TRANS" \
   && has 'func wire(host:' "$TRANS" \
   && has 'func requestOpen(' "$TRANS" \
   && has 'func requestClose(' "$TRANS" \
   && has 'func dismissSeatedEditor(' "$TRANS" \
   && has 'popToRootViewController' "$TRANS" \
   && has 'kind: "open", onOpenMemo: openLinked' "$TRANS"; then
  ok "B25-U0-2 桥导航通道在位（open/close/接线/宿主关闭点）"
else
  bad "B25-U0-2 桥导航通道缺环"
fi
# B25-U0-3 根视图接线：ListView 探针点把宿主/库
# 交给通道（与 attach 同点位）。
if has 'BridgeNavigationChannel.shared.wire(' "$SRC"; then
  ok "B25-U0-3 根视图通道接线在位"
else
  bad "B25-U0-3 根视图未接线导航通道"
fi
# B25-U0-4 拒绝口径五码齐全（通道内部码 + 错误
# 表既有码的字面都在 BridgeNavError 定义处）。
if has 'return "nav_unavailable"' "$TRANS" \
   && has 'return "read_only_mode"' "$TRANS" \
   && has 'return "memo_not_found"' "$TRANS" \
   && has 'return "memo_busy"' "$TRANS" \
   && has 'return "nav_timeout"' "$TRANS"; then
  ok "B25-U0-4 导航拒绝口径五码齐全"
else
  bad "B25-U0-4 导航拒绝口径缺码"
fi
# B25-U0-5 memo_busy 接线（U1 扩）：在席判定消
# 费点三处——块级两工具（删块/移块）+ 软删（在
# 席篇软删后编辑器落盘即复活，与块写同型，主
# 线裁定在席即拒不分脏净）；判定枚举在位且分
# 叉比对走规范哈希。恢复/永删不设守卫（待删集
# 与在席恒不相交，论证见 BTOOLS 的守卫注释）。
if [ "$(grep -c 'BridgeEditorSeat.seatedConflict(' "$BTOOLS")" = 3 ] \
   && has 'enum BridgeEditorSeat' "$BTOOLS" \
   && has 'static func isDiverged' "$BTOOLS" \
   && has '"memo_busy"' "$BTOOLS"; then
  ok "B25-U0-5 memo_busy 在席判定接线（删块/移块/软删三处）"
else
  bad "B25-U0-5 在席判定缺失或消费点不齐"
fi
# B25-U0-6 Diag 打点：注册/注销各一行、导航请
# 求/成功/拒绝各一行（与既有 BRIDGE 打点同风格，
# 主线经 diag_tail 判读）。
if has 'BRIDGE seat register memo=' "$TRANS" \
   && has 'BRIDGE seat unregister memo=' "$TRANS" \
   && has 'BRIDGE nav wire' "$TRANS" \
   && has 'BRIDGE nav request open memo=' "$TRANS" \
   && has 'BRIDGE nav open ok memo=' "$TRANS" \
   && has 'BRIDGE nav open rejected memo=' "$TRANS" \
   && has 'BRIDGE nav request close' "$TRANS" \
   && has 'BRIDGE nav close ok memo=' "$TRANS" \
   && has 'BRIDGE nav close rejected code=' "$TRANS"; then
  ok "B25-U0-6 导航/在席 Diag 打点齐全"
else
  bad "B25-U0-6 导航/在席 Diag 打点缺项"
fi
# B25-U0-7 在席类工具入册计数（U1 改写）：U0 期
# 的「未入册」边界已由 U1 正式入册取代——清单
# 内 editor_* 恰 6 件（M2 数据写 2 + 在席 4），
# 多一件少一件都是漂移。
if [ "$(grep -c '"editor_' "$BPROTO")" = 6 ]; then
  ok "B25-U0-7 在席工具已入册（清单 editor_* 恰 6 件）"
else
  bad "B25-U0-7 工具清单 editor_* 计数漂移"
fi
# ── U1 条目（方案 §7.3 的 B25-1..9）──
HDR=$(awk '/^struct EditorHeaderView/,/^    \/\/\/ 背景色底表/' "$SRC")
CAP=$(awk '/^private func titleCapsule/,/^private var capsuleWidth/' "$SRC")
ucode=$(grep -v '^[[:space:]]*//' "$UITEST")
# B25-1 文件与构建：驱动文件在位且进 build 三
# 名单（每遍名单 + 专属 .o + 链接行）；push_
# small 名单在本机仓外、存在时同查（tree 上由
# 构建本身兜底：名单漏名则文件不到、构建即红）。
PUSHSM=../../../../../tree-sync/push_small.py
pushok=1
if [ -f "$PUSHSM" ]; then
  for n in MomentBridgeUITest.swift TitleTextField.swift TitleTapCaret.swift; do
    grep -q "$n" "$PUSHSM" || pushok=0
  done
fi
if [ -f "$UITEST" ] && [ -f "$TFIELD" ] && [ -f "$TCARET" ] \
   && [ "$(grep -c 'MomentBridgeUITest.swift' "$SH")" -ge 3 ] \
   && has 'bridge_uitest.o' "$SH" && has 'title_field.o' "$SH" \
   && has 'title_caret.o' "$SH" && [ "$pushok" = 1 ]; then
  ok "B25-1 驱动三文件在位 + 构建/推送名单齐全"
else
  bad "B25-1 驱动文件或构建名单缺失"
fi
# B25-2 能力门：uiTestScopeTools 四件集合 + ops
# 门分支在分发器；uitest_run 在 twoStageTools。
uitestset=$(sed -n '/static let uiTestScopeTools/,/\]/p' "$BTOOLS" \
  | grep -o '"[a-z_]*"' | tr -d '"' | sort | tr '\n' ' ')
if [ "$uitestset" = "uitest_get_result uitest_list_surfaces uitest_measure uitest_run " ] \
   && has 'Self.uiTestScopeTools.contains(name)' "$BTOOLS" \
   && sed -n '/static let twoStageTools/,/\]/p' "$BTOOLS" | grep -q '"uitest_run"'; then
  ok "B25-2 驱动能力门（ops 集合 + 门分支 + 两段提交）"
else
  bad "B25-2 驱动能力门缺失"
fi
# B25-3 受限集排除：safeLimitedTools 字面量与
# uitest 四名交集为空（逐名查）。
safeset2=$(sed -n '/static let safeLimitedTools/,/\]/p' "$BTOOLS")
safeok=1
for t in uitest_list_surfaces uitest_run uitest_get_result uitest_measure; do
  echo "$safeset2" | grep -q "\"$t\"" && safeok=0
done
if [ "$safeok" = 1 ]; then
  ok "B25-3 驱动工具不在安全模式受限集（安全模式一律 safe_mode_limited）"
else
  bad "B25-3 驱动工具混入受限集"
fi
# B25-4 单一来源：胶囊点按的记行字面在 HDR 段
# 内只此一份（入口定义处）；手势体只剩入口调
# 用；toggle/close 具名入口各一份且钮体调用。
if [ "$(echo "$HDR" | grep -c 'EDIT title focus via=capsule')" = 1 ] \
   && echo "$CAP" | grep -q 'activateTitleFromCapsule(' \
   && ! echo "$CAP" | grep -q 'onTapGesture' \
   && [ "$(echo "$HDR" | grep -c 'func toggleEditorMenu()')" = 1 ] \
   && [ "$(echo "$HDR" | grep -c 'func closeEditor()')" = 1 ] \
   && echo "$HDR" | grep -q 'toggleEditorMenu()' \
   && echo "$HDR" | grep -q 'closeEditor()'; then
  ok "B25-4 具名入口单一来源（胶囊/菜单钮/关闭三处）"
else
  bad "B25-4 具名入口缺失或动作体仍内联"
fi
# B25-5 注册点齐全：UITestAnchor 定义在位；三
# 个注册 id 字面在位（胶囊/菜单面/编辑器面）。
if has 'struct UITestAnchor' "$UITEST" \
   && has '"editor.titleCapsule"' "$SRC" \
   && has '"editor.menuPanel"' "$SRC" \
   && has '"editor.view"' "$SRC"; then
  ok "B25-5 驱动注册点齐全（锚点 + 三面）"
else
  bad "B25-5 注册点缺失"
fi
# B25-6 夹具守卫：登记集校验 + fixture_guard 回
# 码；清理链三件（softRemove + commitPending-
# Deletion + libraryHash 对账）与 hygiene_failed
# 回码字面在位。
if echo "$ucode" | grep -q 'fixture_guard' \
   && echo "$ucode" | grep -q 'softRemove' \
   && echo "$ucode" | grep -q 'commitPendingDeletion' \
   && echo "$ucode" | grep -q 'libraryHash' \
   && echo "$ucode" | grep -q 'hygiene_failed'; then
  ok "B25-6 夹具双标记守卫 + 清理链 + 卫生回码在位"
else
  bad "B25-6 夹具守卫/清理链缺失"
fi
# B25-7 禁区零触碰：驱动代码行零 UITouch/
# UIEvent(/performSelector/exportZip(；对
# Library 的写调用只许白名单三符号（create/
# softRemove/commitPendingDeletion），persist
# 只许夹具自篇（persist(fixture 形参锚）。
if ! echo "$ucode" | grep -q 'UITouch' \
   && ! echo "$ucode" | grep -q 'UIEvent(' \
   && ! echo "$ucode" | grep -q 'performSelector' \
   && ! echo "$ucode" | grep -q 'exportZip(' \
   && ! echo "$ucode" | grep -qE '\.(deletePermanent|restoreDeleted|deleteCommitted|moveBlock|deleteBlock)\(' \
   && echo "$ucode" | grep -q '\.create()'; then
  ok "B25-7 驱动禁区零触碰（无事件注入/私有 API，写面白名单）"
else
  bad "B25-7 驱动触碰禁区"
fi
# B25-8 打点齐全：UITEST 模板行（run begin/
# step/assert fail/fixture/hygiene/run end/
# restore failed）齐备。
diagok=1
for s in 'UITEST run begin' 'UITEST step' \
         'UITEST assert fail' 'UITEST fixture create' \
         'UITEST fixture cleanup' 'UITEST hygiene' \
         'UITEST restore failed' 'UITEST run end'; do
  grep -q "$s" "$UITEST" || diagok=0
done
if [ "$diagok" = 1 ]; then
  ok "B25-8 UITEST 打点模板齐全"
else
  bad "B25-8 UITEST 打点缺项"
fi
# B25-9 并发门与检查序：四码在位；受理序在
# run() 函数段内查——前置门（read_only_mode/
# ops_disabled）必须在驱动受理调用（begin，
# 并发门在其内）之前。
runseg=$(awk '/static func run\(/,/static func getResult/' "$UITEST")
rpos=$(echo "$runseg" | grep -n 'read_only_mode' | head -1 | cut -d: -f1)
bpos=$(echo "$runseg" | grep -n 'UITestDriver.shared.begin(' | head -1 | cut -d: -f1)
if echo "$ucode" | grep -q 'device_busy' \
   && echo "$ucode" | grep -q 'driver_busy' \
   && echo "$ucode" | grep -q 'aborted_user_active' \
   && echo "$ucode" | grep -q 'restore_failed' \
   && echo "$runseg" | grep -q 'ops_disabled' \
   && [ -n "$rpos" ] && [ -n "$bpos" ] && [ "$rpos" -lt "$bpos" ]; then
  ok "B25-9 并发门四码 + 前置门先于并发门的检查序"
else
  bad "B25-9 并发门缺码或检查序不对"
fi
# B25-10 名集镜像（方案 §7.3 交叉引用）：B16-3
# 的逐名枚举集与 BPROTO 清单名集差集为空——防
# [16] 与 [25] 两组各说各话（四方口径的仓内半
# 边；中继侧由 B16-15 盯）。
b163names=$(sed -n '/^for t in bridge_status/,/; do/p' "$0" \
  | grep -oE '[a-z_]+' | grep -v '^for$\|^in$\|^do$\|^t$' | sort -u)
protonames2=$(sed -n '/static let toolNames/,/\]/p' "$BPROTO" \
  | grep -o '"[a-z_]*"' | tr -d '"' | sort -u)
if [ "$b163names" = "$protonames2" ]; then
  ok "B25-10 B16-3 枚举名集与协议清单镜像一致"
else
  bad "B25-10 B16-3 枚举与协议清单漂移"
fi

# ── U4a 条目（B25-U4a-1..7，插 B25-10 后）──
# B25-U4a-1 场景目录查表：catalog 定义在位、
# begin() 走 Self.catalog 查表、七景名全注册
# （S1 + U4a 六景），无单景硬编码特判残留。
u4aok=1
for s in 'static let catalog' 'Self.catalog\[scenario\]' \
         'title_capsule_reedit' \
         'title_capsule_reedit_compact' \
         'title_caret_assert' 'title_commit_escape' \
         'done_capsule_cycle' 'slash_menu_flow' \
         'block_type_matrix'; do
  echo "$ucode" | grep -q "$s" || u4aok=0
done
if [ "$u4aok" = 1 ] \
   && ! echo "$ucode" | grep -q 'scenario == "title_capsule_reedit"'; then
  ok "B25-U4a-1 场景目录查表 + 七景全注册（无单景特判）"
else
  bad "B25-U4a-1 场景目录或注册名缺失"
fi
# B25-U4a-2 ctx 跨步存储：store 字段在位且六
# 景有消费点（blockIdByType/expectedCaret 等
# 键经 store 传递，非场景专属 ctx 字段）。
if echo "$ucode" | grep -q 'var store: \[String: Any\]' \
   && echo "$ucode" | grep -q 'store\["blockIdByType"\]' \
   && echo "$ucode" | grep -q 'store\["expectedCaret"\]'; then
  ok "B25-U4a-2 ctx 跨步存储在位且有消费点"
else
  bad "B25-U4a-2 ctx 跨步存储缺失"
fi
# B25-U4a-3 步证据前缀：步记录 Diag 过滤含
# SLASH /SCROLL 两前缀（U4a 新增证据面）。
if echo "$ucode" | grep -q '"SLASH "' \
   && echo "$ucode" | grep -q '"SCROLL "'; then
  ok "B25-U4a-3 步证据前缀含 SLASH/SCROLL"
else
  bad "B25-U4a-3 步证据前缀缺失"
fi
# B25-U4a-4 复原链清三位：restore 内斜杠/链
# 接表单/音乐输入三位置 nil（夹具编辑器限定）。
if echo "$ucode" | grep -q 'ed.slashBlockId = nil' \
   && echo "$ucode" | grep -q 'ed.linkFormBlockId = nil' \
   && echo "$ucode" | grep -q 'ed.focusMusicId = nil'; then
  ok "B25-U4a-4 复原链清斜杠/链接/音乐三位"
else
  bad "B25-U4a-4 复原链三位清理缺失"
fi
# B25-U4a-5 注册面扩展四处：doneCapsule/
# slashPanel 两新面 + scroll 滚动锚 +
# editor.view 的 dockCompact 读数。
if grep -q '"editor.doneCapsule"' "$SRC" \
   && grep -q '"editor.slashPanel"' "$SRC" \
   && grep -q 'UITestScrollAnchor' "$SRC" \
   && grep -q '"dockCompact"' "$SRC" \
   && grep -q '"editor.scroll"' "$SRC"; then
  ok "B25-U4a-5 注册面扩展（完成胶囊/斜杠/滚动锚/坞态读）"
else
  bad "B25-U4a-5 注册面扩展缺处"
fi
# B25-U4a-6 待办勾选具名入口：EditorModel 定
# 义 toggleTodoChecked、勾选钮与驱动同呼此入
# 口（单一来源，防两处内联漂移）。
if grep -q 'func toggleTodoChecked' "$SRC" \
   && grep -q 'editor.toggleTodoChecked(block)' "$SRC" \
   && echo "$ucode" | grep -q 'toggleTodoChecked(todo)'; then
  ok "B25-U4a-6 toggleTodoChecked 具名入口三方同源"
else
  bad "B25-U4a-6 toggleTodoChecked 入口缺失或仍内联"
fi
# B25-U4a-7 EDT-09 现行口径：完成胶囊景断言
# 以键盘通知行（EDIT kb visible=）与三行序为
# 准（fix_donecapsule_retract 后机制），驱动内
# 无 safeArea 派生键盘的旧口径字面。
if echo "$ucode" | grep -q 'EDIT kb visible=1' \
   && echo "$ucode" | grep -q 'EDIT kb visible=0' \
   && echo "$ucode" | grep -q 'triple_ordered' \
   && ! echo "$ucode" | grep -q 'safeAreaInsets'; then
  ok "B25-U4a-7 完成胶囊景以 kb 通知行 + 三行序断言"
else
  bad "B25-U4a-7 完成胶囊断言口径漂移"
fi

# ── E3 条目（转换语义单点化，impl_conversion_e3.md；
# 场景本体 EDT-16/17 归 U4a，本组只锁落码构造）──
# B25-E3-1 转换单点：convertNodeType 定义恰 1、
# clearTypeFields 定义恰 1；调用点全集逐个点名
# 恰 3——① setBlockType（块菜单路径）② applySlash
# 的 convert 闭包（斜杠路径）③ convertSmartPrefix
# （E1 智能前缀路径）。③系 2026-11-27 跨批对账
# 改锚：F-02 智能前缀转换与斜杠同构、正当经同
# 一漏斗（逐点列名与正当性见 impl_editor_loop_
# e1.md F-02 节）；三段各恰 1 + 总数恰 3，防无
# 名第四点混入、亦防任一点名路径脱漏斗。
E3SEG_MENU=$(awk '/func setBlockType/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
E3SEG_SLASH=$(awk '/func applySlash/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
E3SEG_SMART=$(awk '/func convertSmartPrefix/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ "$(grep -c 'func convertNodeType' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func clearTypeFields' "$SRC")" = 1 ] \
  && [ "$(grep -c 'convertNodeType(b' "$SRC")" = 3 ] \
  && [ "$(echo "$E3SEG_MENU" | grep -c 'convertNodeType(b')" = 1 ] \
  && [ "$(echo "$E3SEG_SLASH" | grep -c 'convertNodeType(b')" = 1 ] \
  && [ "$(echo "$E3SEG_SMART" | grep -c 'convertNodeType(b')" = 1 ]; then
  ok "B25-E3-1 转换单点在位（定义 1 + 三路径逐点点名：菜单/斜杠/智能前缀）"
else
  bad "B25-E3-1 转换单点缺失或路径未收敛"
fi
# B25-E3-2 变体保留负查（M-04）：全文件不得再
# 有 calloutType 赋值写点（旧斜杠恒写 note 已删；
# 读取面 calloutVariant 不在此列）。
if [ "$(grep -c '\["calloutType"\] =' "$SRC")" = 0 ]; then
  ok "B25-E3-2 calloutType 零写点（重转变体保留）"
else
  bad "B25-E3-2 calloutType 出现写点（变体可能被抹）"
fi
# B25-E3-3 整表互换（F-04）：互换早路注释锚位
# 于 promoteListItem 调用之前（顺序即语义：先
# 判互换、才升格），且早路内含 start 清除。
swappos=$(grep -n '整表换型（F-04' "$SRC" | head -1 | cut -d: -f1)
prompos=$(grep -n 'promoteListItem(list: list, item: target)' "$SRC" | head -1 | cut -d: -f1)
if [ -n "$swappos" ] && [ -n "$prompos" ] && [ "$swappos" -lt "$prompos" ] \
  && grep -q 'op_convert Item 臂' "$SRC"; then
  ok "B25-E3-3 列表互换整表换型早路在升格之前"
else
  bad "B25-E3-3 整表互换早路缺失或顺序漂移"
fi
# B25-E3-4 start 传递（F-05）：exitListItem 尾
# 表传递恰 2 处、mergeListItemBackward 首项摘
# 除递增恰 3 处；三个 start 助手定义各 1。
if [ "$(grep -c 'setListStart(nl, listStart(of: list)' "$SRC")" = 2 ] \
  && [ "$(grep -c 'shiftListStart(list, by: 1)' "$SRC")" = 3 ] \
  && [ "$(grep -c 'func listStart(of' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func setListStart' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func shiftListStart' "$SRC")" = 1 ]; then
  ok "B25-E3-4 start 传递两处 + 首项递增三处齐全"
else
  bad "B25-E3-4 start 传递/递增计数漂移"
fi
# B25-E3-5 逐行拆项 + 剥前缀 + 尾随空段
# （F-06/M-05/M-03）：行集三助手定义在位、列表
# case 走 listLineRuns、尾随空段助手单点共用
# （ensureTrailingEmptyPara 定义 1 + 调用 3；
# 计数原为 3，callout 扩围微批新增斜杠调用 1
# 后改判为 4，见 fix_callout_trailing_para.md）。
if [ "$(grep -c 'func stripMdLineRuns' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func listLineRuns' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func runsSplitByLine' "$SRC")" = 1 ] \
  && [ "$(grep -c 'let lineRuns = listLineRuns(b)' "$SRC")" = 1 ] \
  && [ "$(grep -c 'ensureTrailingEmptyPara' "$SRC")" = 4 ]; then
  ok "B25-E3-5 逐行拆项/剥前缀/尾随空段构造齐全"
else
  bad "B25-E3-5 F-06/M-05/M-03 构造缺失"
fi
# B25-E3-6 callout 尾随空段（微批
# fix_callout_trailing_para.md，Web op_convert
# 顶层臂 callout 与 todo 同臂）：菜单路径补段
# 条件扩为 todo||callout 恰 1；斜杠 callout
# convert（全文件恰 1）后紧跟顶层守卫补段——
# 守卫与调用在其后 8 行内同在（列表项升格路
# 守卫外不补，Web Item 臂同口径）。
calloutpos=$(grep -n 'convert("callout")' "$SRC" | head -1 | cut -d: -f1)
if [ "$(grep -c 'type == "todo" || type == "callout"' "$SRC")" = 1 ] \
  && [ -n "$calloutpos" ] \
  && sed -n "${calloutpos},$((calloutpos + 8))p" "$SRC" | grep -q 'if parentList == nil' \
  && sed -n "${calloutpos},$((calloutpos + 8))p" "$SRC" | grep -q 'ensureTrailingEmptyPara(after: b)'; then
  ok "B25-E3-6 callout 尾随空段两路径接入（菜单扩条件 + 斜杠顶层守卫）"
else
  bad "B25-E3-6 callout 尾随空段接入缺失"
fi

echo "[26] 标题落点映射（B-4，定案 plan_title_tap_caret.md）"
HDR=$(awk '/^struct EditorHeaderView/,/^    \/\/\/ 背景色底表/' "$SRC")
# T26-1 字段常驻 representable：TitleTextField
# 定义在位（UIViewRepresentable + Coordinator
# 三委托）；CAP 段 SwiftUI 原生 TextField 零残
# 留（T24-1 同口径，此处盯定义侧）。
if has 'struct TitleTextField: UIViewRepresentable' "$TFIELD" \
   && has 'func makeCoordinator' "$TFIELD" \
   && has 'textFieldDidBeginEditing' "$TFIELD" \
   && has 'textFieldDidEndEditing' "$TFIELD"; then
  ok "T26-1 标题字段 representable + Coordinator 委托在位"
else
  bad "T26-1 representable 结构缺失"
fi
# T26-2 焦点单一真相：状态位在 TitleFieldControl
# （@Published focused）；HDR 段 @FocusState 零
# 残留、titleFocused 只剩只读别名定义一处。
if has 'final class TitleFieldControl' "$TFIELD" \
   && has '@Published var focused' "$TFIELD" \
   && ! echo "$HDR" | grep -q '@FocusState private' \
   && echo "$HDR" | grep -q 'private var titleFocused: Bool {'; then
  ok "T26-2 焦点单一真相在 control（别名只读、@FocusState 退场）"
else
  bad "T26-2 焦点真相分裂或旧状态位残留"
fi
# T26-3 入口签名冻结 + 行序：activateTitleFrom-
# Capsule(atX:) 定义在位；入口内 pendingCaret
# 赋值行必须在 focused=true 行之前（先定格后
# 置焦，方案 P5）。
ent=$(awk '/func activateTitleFromCapsule/,/^}/' "$SRC")
ppos=$(echo "$ent" | grep -n 'pendingCaret = ' | head -1 | cut -d: -f1)
fpos=$(echo "$ent" | grep -n 'titleControl.focused = true' | head -1 | cut -d: -f1)
if echo "$HDR" | grep -q 'func activateTitleFromCapsule(' \
   && echo "$ent" | grep -q 'atX: CGFloat?' \
   && [ -n "$ppos" ] && [ -n "$fpos" ] && [ "$ppos" -lt "$fpos" ]; then
  ok "T26-3 落点入口签名冻结 + 记号先于置焦的行序"
else
  bad "T26-3 入口签名漂移或行序反转"
fi
# T26-4 纯函数文件纪律：TitleTapCaret 只 import
# Foundation；两函数签名在位；数值断言主文件在
# 位（tree swiftc 独立编译真跑，见 impl 报告）。
if [ "$(grep -c '^import' "$TCARET")" = 1 ] \
   && has 'import Foundation' "$TCARET" \
   && has 'static func caretScalarIndex(' "$TCARET" \
   && has 'static func utf16Offset(' "$TCARET" \
   && [ -f tests/title_tap_caret_main.swift ]; then
  ok "T26-4 落点纯函数 Foundation-only + 断言主文件在位"
else
  bad "T26-4 纯函数纪律破坏"
fi
# T26-5 落定后只施加：Coordinator 施加点在位
# （didBegin 后一拍 + 回读比对 + 不符记 error
# 行）；updateUIView 编辑期禁反写锚（组字/编
# 辑中不回写 field.text 的守卫行）。
if has 'title caret readback ' "$TFIELD" \
   && has 'mismatch want=' "$TFIELD" \
   && has 'title caret -> ' "$TFIELD" \
   && has 'markedTextRange' "$TFIELD"; then
  ok "T26-5 落点施加 + 回读比对 + 组字守卫在位"
else
  bad "T26-5 落点施加链缺失"
fi
# T26-6 量测同源：titlePrefixWidths 在位且段内
# semibold 量测口径多处同源（capsuleWidth 与本
# 量测同为 14 semibold + kern -0.2，P2 耦合钉
# 子在函数注释）。
if [ "$(echo "$HDR" | grep -c 'weight: .semibold')" -ge 2 ] \
   && echo "$HDR" | grep -q 'func titlePrefixWidths'; then
  ok "T26-6 前缀宽量测与呈现属性同源"
else
  bad "T26-6 量测口径漂移"
fi
# T26-7 驱动可调：胶囊注册动作 tap 指向同一入
# 口（atX 透传），S1 经注册表调入口而非另开路
# 径——CAP 段注册块内 activateTitleFromCapsule
# 调用在位（与 T24-2 的手势调用合计 ≥2 处）。
if [ "$(echo "$CAP" | grep -c 'activateTitleFromCapsule(')" -ge 2 ]; then
  ok "T26-7 胶囊入口双消费者（手势 + 驱动注册）在位"
else
  bad "T26-7 驱动未共用胶囊入口"
fi
# T26-8 字段尺寸契约（0.9.56 竖排渲染异常根
# 治，fix_title_vertical_render.md）：represen-
# table 必须自带 sizeThatFits——宽只认提议
# （proposal.width 在位）、高只认字段自身量
# 测（函数段内 proposal.height 零出现 = 纵向
# 提议不采）。缺此契约时字段按缺省口径成为
# 纵向灵活视图：胶囊 VStack 总高 66 内，竖
# 排灵活行吞掉全部余高、meta 行被顶到胶囊
# 底边（横排单行无第二行可挤、故独竖排异
# 常）。旧 [24]/[26] 条目只锁结构在位（字段
# 常驻/覆盖层/落点算式），锁不住「缺失的方
# 法」这一类缺席缺陷，故本条专锁契约本身。
TFIT=$(awk '/func sizeThatFits/{f=1} f{print} f&&/^    }$/{exit}' "$TFIELD")
if [ -n "$TFIT" ] \
   && echo "$TFIT" | grep -q 'proposal.width' \
   && echo "$TFIT" | grep -q 'sizeThatFits(CGSize(' \
   && ! echo "$TFIT" | grep -q 'proposal.height'; then
  ok "T26-8 字段尺寸契约在位（宽随提议、高为字段自身量测）"
else
  bad "T26-8 representable 尺寸契约缺失（纵向灵活回潮）"
fi
# T26-9 呈现对账锚（占位色）：旧 SwiftUI 字段
# 占位走系统占位色；representable 的 attrib-
# utedPlaceholder 须同色（UIColor.placeholder-
# Text 在位）——初版误填正文主色，空标题时
# 「无标题」呈正文强度（呈现参数漏复刻）。
if has 'UIColor.placeholderText' "$TFIELD" \
   && has 'attributedPlaceholder' "$TFIELD"; then
  ok "T26-9 占位色与旧字段同源（系统占位色）"
else
  bad "T26-9 占位色漏复刻（主色冒充占位色）"
fi

echo "[27] 桥场景库 M3a（方案 plan_bridge_m3.md，定案 impl_bridge_m3a.md）"
# B27-1 文件与构建：场景文件在位且进 build 三
# 名单（每遍名单 + 专属 .o + 链接行）；push_
# small 名单在本机仓外、存在时同查（同 B25-1
# 口径）。
scenpush=1
if [ -f "$PUSHSM" ]; then
  grep -q "MomentBridgeScenarios.swift" "$PUSHSM" || scenpush=0
fi
if [ -f "$BSCEN" ] \
   && [ "$(grep -c 'MomentBridgeScenarios.swift' "$SH")" -ge 19 ] \
   && has 'bridge_scenarios.o' "$SH" \
   && [ "$scenpush" = 1 ]; then
  ok "B27-1 场景文件在位、构建名单/primary 遍/链接行 + 传输名单齐全"
else
  bad "B27-1 场景文件缺失或构建/传输名单不全"
fi
# B27-2 注册表与清单：八景 id 在注册表逐个在
# 位（M3a 四 + M3b 四，M3b 批扩名——计数与注
# 册表条目数一致口径，方案 §7）；场景三件 +
# 量测件在 BPROTO 清单（逐名由 B16-3 守，本条
# 查注册表侧）。snapshot_restore_drill 只注册
# 描述符（快照景已真接线，arm 门由 [67] 组守）。
regok=1
for s in drag_trace_review weather_settings_flow \
         ops_convergence language_roundtrip \
         delete_restore_roundtrip \
         drag_semantic_reorder create_transition \
         snapshot_restore_drill; do
  grep -q "\"$s\"" "$BSCEN" || regok=0
done
if [ "$regok" = 1 ] \
   && [ "$(grep -c 'BridgeScenarioDescriptor(' "$BSCEN")" = 8 ]; then
  ok "B27-2 场景注册表八景齐全（M3a 四 + M3b 四）"
else
  bad "B27-2 场景注册表缺景或条目数漂移"
fi
# B27-3 场景门：分发器声明制验足（注册表解析 +
# 参数面校验 + scope_denied 点名缺层）与场级两
# 段条件（containsHighRisk 才入两段）在位；引
# 擎互斥回 run_conflict。
if has 'BridgeScenarioRegistry' "$BTOOLS" \
   && has 'validateParams' "$BTOOLS" \
   && has 'if let layer = missing.first' "$BTOOLS" \
   && has 'scenarioDesc?.containsHighRisk' "$BTOOLS" \
   && has 'code: "run_conflict"' "$BSCEN"; then
  ok "B27-3 场景声明制门（验足点名 + 参数面 + 场级两段条件 + run_conflict）"
else
  bad "B27-3 场景门机制缺失"
fi
# B27-4 正文红线（本组核心，方案 §5.3）：正文
# 级四件名在 BSCEN 与 BPROTO 的代码行零出现
# （注释提及不算，同 B16-3 口径——评审落地前
# 此断言不得删改，改判须连同桥方案 §12.1 结
# 论一并修订并在落码报告注明）；场景参数声明
# 零 text/blocks/runs 键；证据组装零 notesGet
# 正文回读符号。
scencode=$(grep -v '^[[:space:]]*//' "$BSCEN" "$BPROTO")
redok=1
for t in notes_create editor_insert_block \
         editor_update_block editor_set_block_type; do
  echo "$scencode" | grep -q "\"$t\"" && redok=0
done
if [ "$redok" = 1 ] \
   && ! grep -qE 'key: "(text|blocks|runs)"' "$BSCEN" \
   && ! grep -q 'notesGet' "$BSCEN"; then
  ok "B27-4 正文红线（四件零注册/零引用 + 参数表零正文键 + 证据零正文回读）"
else
  bad "B27-4 正文红线被破（四件混入/参数表含正文键/证据回读正文）"
fi
# B27-5 journal 与卫生：journal 落点/状态枚举
# （含 awaiting_manual_reopen）/7 天过期/单会
# 话景 libraryHash 对账与 hygiene_failed 降格
# 在位。
if has 'bridge-scenarios' "$BSCEN" \
   && has 'runs.json' "$BSCEN" \
   && has 'awaiting_manual_reopen' "$BSCEN" \
   && has '86_400_000' "$BSCEN" \
   && has 'code = "hygiene_failed"' "$BSCEN" \
   && has 'libraryHash()' "$BSCEN"; then
  ok "B27-5 journal 落盘/保留/过期 + 卫生对账降格在位"
else
  bad "B27-5 journal/卫生机制缺失"
fi
# B27-6 快照纪律：场景写步经 BridgeWriteSupport
# 快照入口；BSCEN 内 exportZip( 零出现（同
# B16-12 口径，不污染备份新鲜度）。
if has 'BridgeWriteSupport.shared' "$BSCEN" \
   && has 'ensureSnapshot' "$BSCEN" \
   && ! grep -q 'exportZip(' "$BSCEN"; then
  ok "B27-6 场景快照纪律（写前快照入口 + 零 exportZip）"
else
  bad "B27-6 快照纪律缺失或混入 exportZip"
fi
# B27-7 受限集排除：safeLimitedTools 与场景三
# 名 + 量测名交集为空（安全模式下场景面全拒，
# 方案 §5.4）。
SL27=$(sed -n '/static let safeLimitedTools/,/\]/p' "$BTOOLS")
if ! echo "$SL27" | grep -qE 'scenarios_|metrics_create_settle'; then
  ok "B27-7 安全模式受限集不收场景/量测四件"
else
  bad "B27-7 场景/量测工具混入受限集"
fi
# B27-8 续跑双钩子与打点：启动扫描（协调器
# start 尾 resumePendingRuns via=boot）+ 模式
# 翻转通知（try_normal 内 noteModeFlippedTo
# Normal）在位；SCENARIO 打点模板齐备；共用互
# 斥单锁在驱动核（tryClaimExternalRun）。
if has 'resumePendingRuns(' "$BRIDGE" \
   && has 'via: "boot")' "$BRIDGE" \
   && has 'noteModeFlippedToNormal' "$BOPS" \
   && has 'tryClaimExternalRun' "$UITEST" \
   && has 'SCENARIO run begin' "$BSCEN" \
   && has 'SCENARIO step' "$BSCEN" \
   && has 'SCENARIO suspend' "$BSCEN" \
   && has 'SCENARIO resume' "$BSCEN" \
   && has 'SCENARIO hygiene' "$BSCEN" \
   && has 'SCENARIO run end' "$BSCEN"; then
  ok "B27-8 续跑双钩子（boot/modeflip）+ SCENARIO 打点 + 共用互斥单锁"
else
  bad "B27-8 续跑钩子/打点/互斥缺失"
fi
# B27-9 描述符完整性：每条目含 requiredScopes
# 与 grades 声明（结构扫描：条目构造点逐个含
# 两字段名——注册表 4 条目 + 结构定义/字典面/
# 可用性计算合计 ≥7 处 requiredScopes、grades
# ≥6 处）。
if [ "$(grep -c 'requiredScopes' "$BSCEN")" -ge 7 ] \
   && [ "$(grep -c 'grades' "$BSCEN")" -ge 6 ]; then
  ok "B27-9 描述符完整性（requiredScopes/grades 逐条目声明）"
else
  bad "B27-9 描述符字段声明不全"
fi

echo "[28] 标题横排点按卡死根治（坞态会话锁存 + 翻转面包屑，定案 fix_title_compact_freeze.md）"
HDR=$(awk '/^struct EditorHeaderView/,/^    \/\/\/ 背景色底表/' "$SRC")
CAP=$(awk '/^private func titleCapsule/,/^private var capsuleWidth/' "$SRC")
CW=$(awk '/^private var capsuleWidth/,/^\/\/\/ meta/' "$SRC")
DOCKDEF=$(awk '/private var dockCompact: Bool \{/{f=1} f{print} f&&/^    \}$/{exit}' "$SRC")
# F28-1 锁存单一来源：坞分支 = 会话中读锁存、非
# 会话读实时；分支定义本身不直读 scrollY（实时
# 读数只在 liveDockCompact 一处）；旧活公式（阈
# 值与焦点同行）零残留；锁存载体（Observable-
# Object + @StateObject，本工具链无 @State）位。
if echo "$DOCKDEF" | grep -qF 'titleFocused ? dockSession.latchedCompact : liveDockCompact' \
   && ! echo "$DOCKDEF" | grep -q 'scrollY' \
   && [ "$(echo "$HDR" | grep -cF 'scroll.scrollY > 30 &&')" = 0 ] \
   && echo "$HDR" | grep -qF 'final class DockSession: ObservableObject' \
   && echo "$HDR" | grep -qF '@StateObject private var dockSession'; then
  ok "F28-1 坞分支会话锁存单点派生（旧活公式零残留）"
else
  bad "F28-1 坞分支仍为活公式或锁存缺失"
fi
# F28-2 同步三点在位：onAppear 初值、滚动变化
# （非会话守卫下）、失焦归位——锁存的实时赋值
# 恰三处，会话开始那一刻锁存必等于当刻实时值。
if echo "$HDR" | grep -qF '.onAppear { dockSession.latchedCompact = liveDockCompact }' \
   && echo "$HDR" | grep -qF 'if !titleFocused' \
   && [ "$(echo "$HDR" | grep -cF 'dockSession.latchedCompact = liveDockCompact')" = 3 ]; then
  ok "F28-2 锁存同步三点在位（出现/滚动/失焦）"
else
  bad "F28-2 锁存同步点缺失或多出"
fi
# F28-3 写者封闭：锁存的全部写点恰为同步三处
# （经 dockSession.latchedCompact 之名赋值计
# 数 = 3；类内初值不经此名）；会话期内无其他
# 写者（翻转只许发生在非会话期由此封闭保证）。
if [ "$(echo "$HDR" | grep -cF 'dockSession.latchedCompact =')" = 3 ]; then
  ok "F28-3 锁存写者封闭（同步三点，无会话期写者）"
else
  bad "F28-3 锁存出现未登记写者"
fi
# F28-4 面包屑在位：坞翻转逐次记行（带计数与
# 来源、计数自增恰一处）、标题会话结束记行——
# 下次同类问题仅凭 diag_tail 即可分辨翻转风暴
# 与单点冻住。
if echo "$HDR" | grep -qF 'EDIT dockflip compact=' \
   && [ "$(echo "$HDR" | grep -cF 'dockSession.flipCount += 1')" = 1 ] \
   && echo "$CAP" | grep -qF 'EDIT title session end'; then
  ok "F28-4 坞翻转/会话面包屑在位（计数 + 来源）"
else
  bad "F28-4 面包屑缺失"
fi
# F28-5 竖排路径与宽度口径零改动锚：两分支仍
# 各以 compact true/false 调同一 titleCapsule、
# meta 行仍按 compact 显隐；capsuleWidth 只消费
# 坞分支派生、不直读锁存/实时（宽与形同源）。
if echo "$HDR" | grep -qF 'titleCapsule(compact: true)' \
   && echo "$HDR" | grep -qF 'titleCapsule(compact: false)' \
   && echo "$CAP" | grep -qF 'if !compact {' \
   && ! echo "$CW" | grep -qE 'liveDockCompact|latchedCompact|dockSession'; then
  ok "F28-5 两分支/ meta 显隐/宽度同源零改动"
else
  bad "F28-5 竖排路径或宽度口径被波及"
fi

echo "[29] 编辑页完成胶囊（••• 圆钮键盘态向下延展成竖向胶囊，用户 2026-11-27 规格，定案 impl_editor_done_capsule.md）"
HDR29=$(awk '/^struct EditorHeaderView/,/^    \/\/\/ 背景色底表/' "$SRC")
EXP29=$(awk '/private var doneExpanded/{f=1} f{print} f&&/^}$/{exit}' "$SRC")
FIN29=$(awk '/private func finishEditing/{f=1} f{print} f&&/^}$/{exit}' "$SRC")
GLY29=$(awk '/struct CheckmarkGlyph/{f=1} f{print} f&&/^}$/{exit}' "$SRC")
# F29-1 单容器结构：尾随位只挂 moreCapsule 一处
# （HDR 内出现 2 次 = 调用点 + 定义）、帧宽 46 /
# 高 46↔92 / 顶锚、玻璃半径 pill 在 HDR 内恰 2
# 处（返回钮 + 胶囊容器）——旧 ••• 钮自带玻璃
# 已随容器化删除，第三处即回潮。
if echo "$HDR29" | grep -qF 'private var moreCapsule' \
   && [ "$(echo "$HDR29" | grep -cF 'moreCapsule')" = 2 ] \
   && echo "$HDR29" | grep -qF 'height: expanded ? 92 : 46' \
   && echo "$HDR29" | grep -qF 'alignment: .top' \
   && [ "$(echo "$HDR29" | grep -cF 'glassControl(radius: Radius.pill)')" = 2 ]; then
  ok "F29-1 完成胶囊单容器（宽 46/高 46↔92/顶锚/玻璃单面）"
else
  bad "F29-1 完成胶囊容器结构不符"
fi
# F29-2 触发源 = 键盘通知事实源（0.9.56 真机回
# 归根治，定案 fix_donecapsule_retract.md）：声
# 明恰一处、写点收敛 setKbVisible 一处、通知两
# 名各一处、旧 safeBottom 边沿喂入零残留、展开
# 派生仍以 ui.kbVisible 为首项。旧断言为何没拦
# 住：它只锁接线拓扑（一声明一写一派生），从不
# 问被测量的值语义——旧源 safeAreaInsets.bottom
# 是含设备安全区的量，静息 = 指示条 34 ≠ 0，
# sb > 0 在落下边沿永不回假，拓扑再单源也闩锁。
# 本条改锁「源的种类」：键盘可见性只许平台通知
# 喂入，任何几何量派生回潮即红。
if [ "$(grep -cF '@Published var kbVisible' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'keyboardWillShowNotification' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'keyboardWillHideNotification' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'kbVisible = visible' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'ui.kbVisible = kbVis' "$SRC")" = 0 ] \
   && echo "$EXP29" | grep -qF 'ui.kbVisible'; then
  ok "F29-2 键盘触发事实源（通知单点喂入、旧几何派生零残留）"
else
  bad "F29-2 键盘触发源不符（须通知单点、禁几何派生）"
fi
# F29-3 旧钮零残留：键盘上方工具栏钮与块文本
# 视图键盘附件栏两处旧「完成」连同其构造码全
# 删——四个特征字面在源码内零出现。
if [ "$(grep -cF 'inputAccessoryView' "$SRC")" = 0 ] \
   && [ "$(grep -cF 'ToolbarItemGroup' "$SRC")" = 0 ] \
   && [ "$(grep -cF 'Button("完成")' "$SRC")" = 0 ] \
   && [ "$(grep -cF 'title: "完成"' "$SRC")" = 0 ]; then
  ok "F29-3 旧完成钮零残留（工具栏 + 附件栏）"
else
  bad "F29-3 旧完成钮有残留"
fi
# F29-4 勾形在位：CheckmarkGlyph 为纯 Path 折
# 线（三点 = move + 两段 addLine）、描边圆头在
# 使用点（线宽 2.8），且无 Text 形态的完成字样
# 被渲染（accessibilityLabel 不在此列）。
if echo "$GLY29" | grep -qF 'struct CheckmarkGlyph: Shape' \
   && echo "$GLY29" | grep -qF 'var p = Path()' \
   && [ "$(echo "$GLY29" | grep -cF 'addLine')" = 2 ] \
   && echo "$HDR29" | grep -qF 'lineWidth: 2.8, lineCap: .round' \
   && [ "$(grep -cF 'Text("完成")' "$SRC")" = 0 ]; then
  ok "F29-4 打勾矢量形在位（纯 Path、无文字形）"
else
  bad "F29-4 勾形缺失或混入文字"
fi
# F29-5 抑制矩阵：展开派生六格齐全（菜单/导出/
# 底表/拖拽/卡片菜单/块菜单任一在位即抑制）。
if echo "$EXP29" | grep -qF '!ui.showMenu' \
   && echo "$EXP29" | grep -qF '!ui.showExport' \
   && echo "$EXP29" | grep -qF '!ui.showBgSheet' \
   && echo "$EXP29" | grep -qF 'editor.draggingId == nil' \
   && echo "$EXP29" | grep -qF 'editor.cardMenuBlockId == nil' \
   && echo "$EXP29" | grep -qF 'editor.blockMenuBlockId == nil'; then
  ok "F29-5 展开抑制矩阵六格齐全"
else
  bad "F29-5 抑制格缺失"
fi
# F29-6 动效与行为等价锚：高度动画 0.25 与坞同
# 族、勾淡入延迟 0.1 反序锚在位；Diag 三行中
# done 与 expand/collapse 两行（字面计数 2）；
# 完成动作 = 全文件唯一的 sendAction 辞焦（与
# 旧工具栏钮同路），finishEditing 内不另做提交。
if echo "$HDR29" | grep -qF '.easeInOut(duration: 0.25)' \
   && echo "$HDR29" | grep -qF '.delay(expanded ? 0.1 : 0)' \
   && [ "$(grep -cF 'EDIT donecapsule' "$SRC")" = 2 ] \
   && echo "$FIN29" | grep -qF 'sendAction(' \
   && [ "$(grep -cF '#selector(UIResponder.resignFirstResponder)' "$SRC")" = 1 ] \
   && ! echo "$FIN29" | grep -qF 'commitTitle'; then
  ok "F29-6 动效参数/Diag/辞焦单路在位"
else
  bad "F29-6 动效或完成动作链不符"
fi
# F29-7 事实链可判读 + 喂入生命周期 + 派生全输
# 入基数：kbVisible 翻转 Diag 行恰一处（src=
# notify 带键盘高，桥侧可逐段判读）；通知观察
# token 四点（声明/两注册/ deinit 遍历注销）在
# 位、removeObserver 全文件恰一处（EditorUI
# deinit，防观察泄漏与第二注销点）；doneExpan
# ded 输入基数 = 首项 kbVisible + 六抑制格
# （合取行 5 行：首行并两格；六格字面由 F29-5
# 逐个锁，本条锁基数——增删任一输入即红）。
if [ "$(grep -cF 'EDIT kb visible=' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'kbTokens' "$SRC")" = 4 ] \
   && [ "$(grep -cF 'removeObserver' "$SRC")" = 1 ] \
   && [ "$(echo "$EXP29" | grep -cF '&&')" = 5 ]; then
  ok "F29-7 kb 翻转行/观察注销/派生基数在位"
else
  bad "F29-7 事实链判读面或派生基数不符"
fi

echo "[30] 首页搜索胶囊同源派生 + 内容布局对齐（定案 fix_home_search_layout.md）"
LV=$(awk '/^struct ListView: View \{/,/^struct CompactTitle/' "$SRC")
CAP30=$(awk '/private var searchCapsule/,/private func sublist/' "$SRC")
GH30=$(awk '/private func groupHeader/{f=1} f{print} f&&/^    \}$/{exit}' "$SRC")
# GRIDH30 提取终点改锚（fix_home_grid_land-
# scape）：组头已移出 LazyVGrid、gridCellColumns
# 在首页网格退役，原终点锚失效；改以组内首个
# gridSublist 调用为界（组头块恒在其前）。
GRIDH30=$(awk '/Text\(group\.title\)/,/gridSublist\(group: group, kind: "img"/' "$SRC")
AV30=$(awk '/^struct AvatarView/,/^extension Notification/' "$SRC")
CT30=$(awk '/^struct CompactTitle/,/^struct ChromeView/' "$SRC")
# F30-1 搜索胶囊单一真相 + 字段常驻：展开态由
# @FocusState 派生、旧 searchOpen 标志的代码残
# 留（声明/读写）零——注释中的历史记述不计；
# 字段恒在层级：分支条件不得是焦点本身（同事
# 务置焦 + 条件插入字段，焦点请求因目标缺席被
# 吞、FocusState 回滚、点按净效果为零——
# 0.9.56 真机实报，fix_search_tap_dead 改写本
# 条：原锁的「分支条件即焦点」正是病灶）。锁：
# CAP30 内焦点分支字面零出现、TextField 恰一处。
if echo "$LV" | grep -qF '@FocusState private var searchFocused: Bool' \
   && ! echo "$CAP30" | grep -qF 'if searchFocused {' \
   && [ "$(echo "$CAP30" | grep -cF 'TextField(')" = 1 ] \
   && [ "$(grep -cE 'var searchOpen|nav\.searchOpen' "$SRC")" = 0 ]; then
  ok "F30-1 胶囊焦点单源派生 + 字段常驻（旧标志零残留）"
else
  bad "F30-1 胶囊开合结构漂移（独立标志/焦点分支/字段非常驻）"
fi
# F30-2 辞焦收敛路径齐全：字段焦点绑定 + 回车
# onSubmit 辞焦（src=submit）+ 清除钮辞焦
# （src=clear）+ 离开首页收敛点 resignSearch
# （缺省 src=nav 的无参调用 8：离开首页收敛 4
# ——新建/打开/头像/紧凑标题；列表动作辞焦 4
# ——左滑删除/置顶 + 网格菜单置顶/删除，AUD-
# A-07 批 6 补齐、基数 4→8；定义已带 src 形
# 参、不再以无参字面计数；在席边界 seat 调用
# 由 F30-16 单独锁）。U5 批增补 +5：home.view
# /home.row 注册面同体动作（tapAvatar 1 + 行
# pin/delete 列表网格各 2），与手指路径同一
# resignSearch 本体、非新路径，基数 8→13。
# fix_home_row_registry 改判 13→11：行注册
# 单点化后 pin/delete 只剩 makeRowEntry 一对
# （两形态共用、锚点逐形态副本摘除），U5 增
# 补由 +5 变 +3（tapAvatar 1 + 行动作 2）；
# 辞焦机制与路径全集不变、仅同体声明去重。
if echo "$CAP30" | grep -qF '.focused($searchFocused)' \
   && echo "$CAP30" | grep -qF 'searchCloseSrc = "submit"' \
   && echo "$CAP30" | grep -qF 'searchCloseSrc = "clear"' \
   && [ "$(echo "$LV" | grep -cF 'resignSearch()')" = 11 ]; then
  ok "F30-2 回车/清除/离开首页辞焦路径齐全（来源记账）"
else
  bad "F30-2 辞焦路径缺失"
fi
# F30-3 键盘同源：窄屏 List 与宽屏 ScrollView
# 均交互式滚动收键盘（辞焦即胶囊回缩）；状态
# 迁移 Diag 两行在位（展开一行、回缩带 src）。
if [ "$(echo "$LV" | grep -cF '.scrollDismissesKeyboard(.interactively)')" = 2 ] \
   && echo "$LV" | grep -qF 'APP search capsule open' \
   && echo "$LV" | grep -qF 'APP search capsule close src='; then
  ok "F30-3 滚动收键盘双形态在位 + 迁移打点齐全"
else
  bad "F30-3 滚动收起或打点缺失"
fi
# F30-4 首卡顶距占位账：窄屏占位 132 + 行
# inset 3 = 首卡顶 135 = 头像底 79 + Web 间
# 距 56；网格占位 135（无行 inset、同账）；
# 页眉框 82 不动。
if echo "$LV" | grep -qF '.frame(height: 132)' \
   && echo "$LV" | grep -qF '.frame(height: 135)' \
   && echo "$LV" | grep -qF '.frame(height: 82)'; then
  ok "F30-4 首卡顶距占位账（132/135、页眉 82）"
else
  bad "F30-4 顶占位值漂移"
fi
# F30-5 分组头合成距：bottom 3（与首卡 top 3
# 合成 Web 文字下 6）+ tracking 0.3 + upper-
# case；top 自 AUD-A-08 改判形参化（旧字面
# top: 25 锁作废、沿革 fix_home_header_gap_
# adaptive）：top 恒经 HomeHeaderMath.first-
# GroupTopInset 按紧邻行 bottom 反推（卡邻
# 居态算得 25、原 28/6 账不变），量测面见
# [57] HG57-2（锁量测值不锁本字面）。
if echo "$GH30" | grep -qF 'top: topInset, leading: 20' \
   && echo "$GH30" | grep -qF 'bottom: 3, trailing: 16' \
   && echo "$GH30" | grep -qF '.tracking(0.3)' \
   && echo "$GH30" | grep -qF '.textCase(.uppercase)' \
   && ! echo "$GH30" | grep -qF 'top: 25'; then
  ok "F30-5 分组头合成距（top 动态形参 + bottom 3）+ 字距/大写在位"
else
  bad "F30-5 分组头度量漂移"
fi
# F30-6 网格组头：glass-label 色 + 左距 2 +
# 负底距 −6（与网格 gap 14 合成距首卡 8）。
if echo "$GRIDH30" | grep -qF 'T.glassLabel' \
   && echo "$GRIDH30" | grep -qF '.padding(.leading, 2)' \
   && echo "$GRIDH30" | grep -qF '.padding(.bottom, -6)'; then
  ok "F30-6 网格组头色/左距/负底距在位"
else
  bad "F30-6 网格组头度量漂移"
fi
# F30-7 空状态度量双形态同值：纵距 56、说明
# lineSpacing 7 + maxWidth 280、动作钮横 22
# ——窄屏 emptyRow 与网格 gridEmpty 各一份
# （LV 段内计数各 2，任一形态回退即红）。
if [ "$(echo "$LV" | grep -cF '.padding(.vertical, 56)')" = 2 ] \
   && [ "$(echo "$LV" | grep -cF '.lineSpacing(7)')" = 2 ] \
   && [ "$(echo "$LV" | grep -cF 'maxWidth: 280')" = 2 ] \
   && [ "$(echo "$LV" | grep -cF '.padding(.horizontal, 22)')" = 2 ]; then
  ok "F30-7 空状态度量双形态同值（56/7/280/22）"
else
  bad "F30-7 空状态度量双形态分叉"
fi
# F30-8 标签 chip 体系：强调色令牌逐值在位；
# 行卡 chip 高 18、方卡 chip 高 20/18；三处
# chip 均走 glassLabelAccent。高承载改判
# （DT 韧性补批，impl_dt_home_resilience
# R-1）：Web 的 18/20 是行高本体，定高在
# AX 档纵向裁字——改 minHeight 承载（默认
# 档托底恒 18/20 逐值不变、AX 随字生长），
# 本锚字面随之改 minHeight 形，机制锁转
# DT36-8。
if grep -qF 'dyn(0x005BBB, 0x72B7FF)' "$SRC" \
   && [ "$(echo "$LV" | grep -cF 'T.glassLabelAccent')" = 3 ] \
   && [ "$(echo "$LV" | grep -cF '.frame(minHeight: small ? 18 : 20)')" = 2 ]; then
  ok "F30-8 chip 令牌/三处色/最小高（18·20/18）在位"
else
  bad "F30-8 chip 体系漂移"
fi
# F30-9 材质档：紧凑胶囊 overlay 档、搜索面
# 板 overlay 档（pill）。头像恐龙构图原在本
# 条的字面锁（size−8 底对齐）已改判——用户
# 2026-11-28 参考图定案改比例常数构图，机
# 制锁转 F30-24（数值复算、容差 ±0.02）。
if echo "$CT30" | grep -qF '.overlayCard(radius: Radius.panelS)' \
   && ! echo "$CT30" | grep -qF '.glassCard(radius: 20)' \
   && echo "$CAP30" | grep -qF '.overlayCard(radius: Radius.pill)'; then
  ok "F30-9 紧凑/搜索 overlay 档"
else
  bad "F30-9 材质档漂移"
fi
# F30-24 头像恐龙圆内构图（用户 2026-11-28
# 参考图定案，fix_avatar_dino_position）：
# 构图常数单点在位 + 旧 size−8 字面零残留 +
# 数值复算——描边外接框（viewBox 口径
# x 79…481 / y 59…471）占圆径 D 比例：宽
# 0.698 / 左距 0.191 / 顶距 0.337（各
# ±0.02）、底边越圆底（1.00–1.10，下巴/颈
# 部由圆裁切贴下缘）。圆框本体不在本锁面。
if echo "$AV30" | grep -qF 'DinoView(size: size * Self.dinoCanvasScale)' \
   && ! grep -qF 'DinoView(size: size - 8)' "$SRC" \
   && python3 - "$SRC" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
def const(name):
    m = re.search(name + r': CGFloat = ([0-9.]+)', src)
    return float(m.group(1)) if m else None
cs = const('dinoCanvasScale')
ox = const('dinoOffsetX')
oy = const('dinoOffsetY')
if None in (cs, ox, oy):
    sys.exit(1)
k = cs / 512.0
w = 402 * k
left = ox + 79 * k
top = oy + 59 * k
bottom = top + 412 * k
ok = (abs(w - 0.698) <= 0.02 and abs(left - 0.191) <= 0.02
      and abs(top - 0.337) <= 0.02
      and 1.00 <= bottom <= 1.10)
sys.exit(0 if ok else 1)
PYEOF
then
  ok "F30-24 恐龙圆内构图（宽 .698/左 .191/顶 .337/底越圆裁切，±.02）"
else
  bad "F30-24 恐龙构图常数漂移或旧 size−8 残留"
fi
# F30-10 字段常驻机制（fix_search_tap_dead）：
# 字段宽由焦点派生（收起 0 / 展开 140）而非分
# 支插入；常驻层命中与焦点同源；置焦字面全仓
# 恰一处（具名入口内，见 F30-11）——任何第二
# 处直接置焦都会绕开 tap 打点与常驻前提。
if echo "$CAP30" | grep -qF '.frame(width: searchFocused ? 140 : 0' \
   && echo "$CAP30" | grep -qF '.allowsHitTesting(searchFocused)' \
   && [ "$(grep -cF 'searchFocused = true' "$SRC")" = 1 ]; then
  ok "F30-10 字段常驻（宽派生/命中同源/置焦单点）"
else
  bad "F30-10 字段常驻机制漂移"
fi
# F30-11 点按具名入口：activateSearch 同一函数
# 体内先记 tap 行再置焦（到达与置焦同点，桥侧
# 三段定位：无 tap=命中未达、有 tap 无 open=
# 置焦未立）；触发层 Button 动作即此入口、按
# 压样式在位。
ACT30=$(awk '/private func activateSearch\(\) \{/{f=1} f{print} f&&/^    \}$/{exit}' "$SRC")
if echo "$ACT30" | grep -qF 'APP search capsule tap' \
   && echo "$ACT30" | grep -qF 'searchFocused = true' \
   && echo "$CAP30" | grep -qF 'activateSearch()' \
   && echo "$CAP30" | grep -qF '.buttonStyle(CardPressStyle())'; then
  ok "F30-11 点按具名入口（tap 打点 + 置焦同闭包 + 真 Button 触发层）"
else
  bad "F30-11 点按入口或打点缺失"
fi
# F30-12 字段层级结构锁：TextField 必须位于触
# 发层分支（if !searchFocused）之前的常驻层
# 内——F30-1 的字面锁之外的顺序锁，防字段日
# 后被挪进任一焦点键控分支而常驻前提静默破。
TF30L=$(echo "$CAP30" | grep -nF 'TextField(' | head -1 | cut -d: -f1)
TR30L=$(echo "$CAP30" | grep -nF 'if !searchFocused {' | head -1 | cut -d: -f1)
if [ -n "$TF30L" ] && [ -n "$TR30L" ] && [ "$TF30L" -lt "$TR30L" ]; then
  ok "F30-12 字段居常驻层（触发分支之前）"
else
  bad "F30-12 字段层级漂移（疑落入焦点分支）"
fi
# F30-13 行 insets 单源锁（fix_home_card_
# spacing）：ListView 内每一行必须显式声明
# listRowInsets、零默认依赖——未声明即静默
# 继承系统默认 insets（纵向合计 32），间距
# 账面值与实测分叉（C-A3 分隔行实测合成 72
# vs 账面 40，0.9.56 用户实报）。旧 [30] 断
# 言逐行锁各自的 insets 字面，却从没数过
# 「行数与 insets 声明数是否相等」——漏声明
# 的行在字面锁下不可见。本条以计数相等守单
# 源：行构造（listRowBackground 计数）与
# insets 声明计数恒等且基数 9。
if [ "$(echo "$LV" | grep -cF '.listRowBackground(Color.clear)')" = 9 ] \
   && [ "$(echo "$LV" | grep -cF '.listRowInsets(')" = 9 ]; then
  ok "F30-13 全行显式 insets（行数 = 声明数 = 9，零默认依赖）"
else
  bad "F30-13 存在未声明 insets 的行（默认继承会放大间距）"
fi
# F30-14 合成间距关键值锚：图/文分隔行 = 帧
# 高 6 + 显式零 insets（合成 3+6+3 = 12）。
# 账面沿革：Web 原账 22 = .img-card margin
# 0（:last-child）+ .swipe-wrapper margin 6
# + .gap-16 高 16（base.css:118/191-192/
# 205；再旧锚 40 系误记组间 margin、已于
# fix_home_regressions_0957 改判）；现值 12
# 系用户 2026-11-27 真机观感裁定（fix_
# home_grid_landscape），覆盖 Web parity
# 的 22、分隔行高按新账反推 12−3−3 = 6，
# 不许无声改数。空状态行显式零 insets（纵
# 56 账面值不被默认继承放大）。
SEP30=$(echo "$LV" | awk '/kind: "img"/,/kind: "txt"/')
EMP30=$(awk '/private var emptyRow/,/^struct CompactTitle/' "$SRC")
if echo "$SEP30" | grep -qF '.frame(height: 6)' \
   && echo "$SEP30" | grep -qF '.listRowInsets(EdgeInsets())' \
   && [ "$(echo "$EMP30" | grep -cF '.listRowInsets(EdgeInsets())')" = 1 ]; then
  ok "F30-14 图/文分隔 12 合成锚 + 空行零 insets"
else
  bad "F30-14 分隔行或空行 insets 漂移（合成间距失守）"
fi
# F30-15 网格框序（审计 L-1）：gridHome 段内左
# 右内距 24 必须先于 1240 框（1240 含内距、内
# 容宽 1192、框缘与页眉收轴同轴）；框在内距前
# 即内外反、≥1288 档卡宽与同轴同偏。
GH30=$(awk '/private var gridHome/,/private var gridColumns/' "$SRC")
p30=$(echo "$GH30" | grep -n 'padding(.horizontal, 24)' | head -1 | cut -d: -f1)
f30=$(echo "$GH30" | grep -n 'frame(maxWidth: 1240)' | head -1 | cut -d: -f1)
if [ -n "$p30" ] && [ -n "$f30" ] && [ "$p30" -lt "$f30" ]; then
  ok "F30-15 网格框序内距先于框（1240 含内距）"
else
  bad "F30-15 网格框序反（内距在框外，≥1288 档偏 24/12）"
fi
# F30-16 在席边界辞焦（fix_home_regressions_
# 0957，S1）：「搜索焦点不与编辑器会话共存」
# 的不变量锁在会话边界——EditorSeatRegistry
# 的 seat/unseat 各恰一处发 onSeatChange、
# ListView 在探针接线点登记钩子并以 src=seat
# 走同一 resignSearch 本体。任一环缺失，桥直
# 调 push 的呈现路径即绕开全部手指辞焦点、焦
# 点残存编辑器之下、返回时自弹键盘。
if [ "$(grep -cF 'onSeatChange?(true)' "$TRANS")" = 1 ] \
   && [ "$(grep -cF 'onSeatChange?(false)' "$TRANS")" = 1 ] \
   && grep -qF 'var onSeatChange' "$TRANS" \
   && echo "$LV" | grep -qF 'EditorSeatRegistry.shared.onSeatChange = {' \
   && [ "$(echo "$LV" | grep -cF 'resignSearch(src: "seat")')" = 1 ] \
   && echo "$LV" | grep -qF 'private func resignSearch(src: String = "nav")'; then
  ok "F30-16 在席边界辞焦（钩子单点 + src=seat 同本体）"
else
  bad "F30-16 在席边界辞焦缺失（焦点可残存于编辑器之下）"
fi
# F30-17 距顶量测机制（fix_home_regressions_
# 0957，S2/S3）：旧基线捕获制零残留（基线字段/
# 探针函数/命名坐标空间全删）；新制 = Home-
# ScrollProbe 直读 contentOffset + adjusted-
# ContentInset（KVO 双观察），scrollOffset 写
# 点恰 2（探针接线 + 形态切换归零）；紧凑迁移
# 与探针挂载 Diag 两行在位（真机判读面）。
# 改判注（fix_home_header_vanish）：0.9.58 装
# 机复报头像/胶囊仍偶尔不见——直读无误、病在
# 出口零消毒（首帧/重挂假偏移单帧直达呈现）。
# 本条的量测本体与写点计数不变，出口消毒与
# 边沿 Diag 由 F30-20..23 分锁，「直读即充分」
# 的旧结论作废。
HSP30=$(awk '/^struct HomeScrollProbe/,/^struct ListView/' "$SRC")
if [ "$(grep -cE 'nav\.firstRowMinY|var firstRowMinY' "$SRC")" = 0 ] \
   && [ "$(grep -cF 'probeAction' "$SRC")" = 0 ] \
   && [ "$(grep -cF 'momentList' "$SRC")" = 0 ] \
   && echo "$HSP30" | grep -qF 'adjustedContentInset' \
   && echo "$HSP30" | grep -qF '\.contentOffset' \
   && echo "$HSP30" | grep -qF 'APP home scrollprobe attach' \
   && [ "$(echo "$LV" | grep -cF 'nav.scrollOffset = ')" = 2 ] \
   && echo "$LV" | grep -qF 'APP home compact'; then
  ok "F30-17 距顶直读量测（基线制零残留 + 写点 2 + Diag 两行）"
else
  bad "F30-17 距顶量测机制漂移（基线残留或探针/写点/打点缺失）"
fi
# SH-1 命中集写点全集（P3，定案 fix_search_
# hits_stale.md）：searchHits 赋值只许出自
# search 本体 4 条路径（空查询/lib 未开/成功/
# FFI 失败）与失效刷新 1 处；三同步锁 =
# searchQuery = query 恰 3（非空置 hits 三路）
# + = nil 恰 1（空查询同清）。任何新增写点
# （消费方补刷）或同步缺失即红。
if [ "$(grep -cF 'searchHits = ' "$SRC")" = 5 ] \
   && [ "$(grep -cF 'searchQuery = query' "$SRC")" = 3 ] \
   && [ "$(grep -cF 'searchQuery = nil' "$SRC")" = 1 ]; then
  ok "SH-1 命中集写点全集（search 4 + refresh 1、三同步 3+1）"
else
  bad "SH-1 命中集写点漂移（消费方补刷或三同步缺失）"
fi
# SH-2 失效触发单点：refreshSearchHitsIfStale
# 全仓出现恰 2 行（定义 1 + touchMemos 内调
# 用 1）——触发收进版本漏斗本体，任何第二调
# 用点（reload/persist 收口补刷）即红。
if [ "$(grep -cF 'refreshSearchHitsIfStale()' "$SRC")" = 2 ]; then
  ok "SH-2 失效触发单点（touchMemos 内恰 1 调用）"
else
  bad "SH-2 失效触发点漂移（第二调用点或触发缺失）"
fi
# SH-3 搜索计算单点：computeSearchHits 出现
# 恰 4 行（定义 1 + 调用 3：search /
# bridgeSearchIds / 失效刷新）——匹配逻辑全
# 仓一份，旧桥内嵌复制体回潮即红。
if [ "$(grep -cF 'computeSearchHits(query:' "$SRC")" = 4 ]; then
  ok "SH-3 搜索计算单点（定义 1 + 调用 3）"
else
  bad "SH-3 搜索计算分叉（定义/调用计数漂移）"
fi
# SH-4 刷新守卫三条件：命中集在位、查询串非
# 空、命中集版本与现行 memosVersion 不等——
# 三条同在 refresh 函数体内（取段核），缺一
# 即失效语义破（未搜索误刷/陈旧不刷/塌态）。
RF30=$(awk '/func refreshSearchHitsIfStale\(\)/,/^    }/' "$SRC")
if echo "$RF30" | grep -qF 'searchHits != nil' \
   && echo "$RF30" | grep -qF 'let query = searchQuery, !query.isEmpty' \
   && echo "$RF30" | grep -qF 'searchHitsVersion != memosVersion'; then
  ok "SH-4 刷新守卫三条件在位（hits/query/version）"
else
  bad "SH-4 刷新守卫缺失（失效语义破）"
fi
# F30-18 网格全跨结构锁（fix_home_grid_land-
# scape）：gridCellColumns 是 eager Grid 的
# API、LazyVGrid 静默忽略——首页网格段内该
# 修饰必须零残留（死修饰回潮即红）；组标题
# 必须位于组内 LazyVGrid **之前**（纵排组块
# 结构：标题在网格外、卡片在网格内连续流
# 排），顺序锚 = 标题行 < 网格行 < img 子列
# 调用行。任一回退（标题再入网格/修饰回潮）
# 即真机重现「标题占一列、卡不满 3 列」。
GHX30=$(awk '/private var gridHome/,/private var gridColumns/' "$SRC")
t30=$(echo "$GHX30" | grep -n 'Text(group.title)' | head -1 | cut -d: -f1)
g30=$(echo "$GHX30" | awk -v t="$t30" 'NR > t && /LazyVGrid\(/ { print NR; exit }')
s30=$(echo "$GHX30" | grep -n 'gridSublist(group: group,' | head -1 | cut -d: -f1)
if [ "$(echo "$GHX30" | grep -cF '.gridCellColumns(')" = 0 ] \
   && [ -n "$t30" ] && [ -n "$g30" ] && [ -n "$s30" ] \
   && [ "$t30" -lt "$g30" ] && [ "$g30" -lt "$s30" ]; then
  ok "F30-18 网格全跨结构（标题在网格外 + 死修饰零残留）"
else
  bad "F30-18 网格结构漂移（标题入网格或 gridCellColumns 回潮）"
fi
# F30-19 列数推导逐档锁（fix_home_grid_land-
# scape）：列数与宽屏谓词只许出自 syncHome-
# Size 一处（≥1280 四列、余三列；宽屏 = 宽
# ≥768 或横屏且高 ≤560，与 base.css:371/
# 613 逐项同构）；gridColumns 是列数唯一消
# 费点（count: nav.homeCols 恰 1）、homeCols
# 写点恰 1（syncHomeSize 本体，声明默认值
# 不计）。第二推导点或第二写点即红。
SHS30=$(awk '/private func syncHomeSize/,/^    }/' "$SRC")
if echo "$SHS30" | grep -qF 's.width >= 1280 ? 4 : 3' \
   && echo "$SHS30" | grep -qF 's.width >= 768' \
   && echo "$SHS30" | grep -qF 's.height <= 560' \
   && [ "$(grep -cF 'count: nav.homeCols' "$SRC")" = 1 ] \
   && [ "$(echo "$LV" | grep -cF 'nav.homeCols = ')" = 1 ]; then
  ok "F30-19 列数推导单点（逐档公式 + 写点/消费点各 1）"
else
  bad "F30-19 列数推导分叉（公式漂移或第二写点/消费点）"
fi
# F30-20 紧凑进度纯函数单源（fix_home_header_
# vanish）：compactP 只许经 HomeHeaderMath 纯
# 函数派生（硬不变量：距顶量 ≤0 恒 0、≥30 恒
# 1，逐档期望表在其定义注释）；LV 内旧内联公
# 式零残留、定义恰 1。呈现层私自再算（消费方
# 补丁式派生）即红。
if echo "$LV" | grep -qF 'HomeHeaderMath.compactP(' \
   && [ "$(grep -cF 'static func compactP(forOffset' "$SRC")" = 1 ] \
   && [ "$(echo "$LV" | grep -cF 'min(max(nav.scrollOffset / 30, 0), 1)')" = 0 ]; then
  ok "F30-20 compactP 纯函数单源（内联公式零残留）"
else
  bad "F30-20 compactP 派生分叉（纯函数缺失或内联公式回潮）"
fi
# F30-21 探针出口消毒机制（fix_home_header_
# vanish）：原始读数只许经 ScrollOffsetSani-
# tizer 单点发布——命中门带常量 30、两读确认
# 候选、未落定门（bounds 判定）、毛刺废弃
# Diag 行、feed 调用恰 1（KVO/首读/复读共用
# 同一入口）。消毒被绕（探针内直写 onScroll
# 第二路）或任一环缺失即红。门带沿革：旧值
# 15 ⇔ compactP ≥0.5 关门，AUD-A-04 页眉命
# 中阈值对齐 p<1 后关门点 = 满格点、本带联
# 动改判 30（fix_audit_batch6_home）。
HSPX30=$(awk '/^struct HomeScrollProbe/,/^struct ListView/' "$SRC")
if echo "$HSPX30" | grep -qF 'ScrollOffsetSanitizer' \
   && echo "$HSPX30" | grep -qF 'hitGateBand: CGFloat = 30' \
   && echo "$HSPX30" | grep -qF 'private var candidate' \
   && echo "$HSPX30" | grep -qF 'sv.bounds.width > 0' \
   && echo "$HSPX30" | grep -qF 'APP home scrollprobe spike discarded' \
   && [ "$(echo "$HSPX30" | grep -cF 'sanitizer.feed(')" = 1 ] \
   && [ "$(echo "$HSPX30" | grep -cF 'onScroll?(')" = 1 ]; then
  ok "F30-21 探针出口消毒（带 30/候选/落定门/毛刺行/feed 单点）"
else
  bad "F30-21 出口消毒缺失或被绕（第二发布路）"
fi
# F30-22 静止带边沿 Diag（fix_home_header_
# vanish）：compactP 离/入 0 的边沿行在位
# （带 offset 源值）——15–29 命中带的迁移判读
# 面，缺失则「偶尔不见」再犯时无从分型。
if echo "$LV" | grep -qF 'APP home compactband' \
   && echo "$LV" | grep -qF 'onChange(of: compactP == 0)'; then
  ok "F30-22 静止带边沿 Diag 在位（compactband + offset 源值）"
else
  bad "F30-22 静止带边沿 Diag 缺失（命中带迁移无留痕）"
fi
# F30-23 探针目标选取硬化（fix_home_header_
# vanish）：findScroll 按面积最大选取（承载
# 面恒全屏、嵌套小滚动面不得夺目标），旧先
# 序首胜实现零残留。
if echo "$HSPX30" | grep -qF 'bestArea' \
   && ! echo "$HSPX30" | grep -qF 'if let hit = findScroll(sub)'; then
  ok "F30-23 探针目标面积最大选取（先序首胜零残留）"
else
  bad "F30-23 探针目标选取漂移（先序首胜回潮）"
fi

echo "[31] 圆角令牌单源收口（定案 impl_radius_consolidation.md / plan_dynamic_radius.md）"
# R31-1 令牌完备：新令牌四枚在表；三文件（主/
# 桥设置/救援）内修饰器半径数字字面零残留——
# 任何一处新写 radius: <数字> 即红。
if has 'static let panel: CGFloat = 28' "$SRC" \
   && has 'static let panelHero: CGFloat = 30' "$SRC" \
   && has 'static let panelS: CGFloat = 20' "$SRC" \
   && has 'static let controlS: CGFloat = 14' "$SRC" \
   && ! grep -qE '(glassCard|glassControl|overlayCard|contentCard)\(radius: [0-9]' "$SRC" "$RESCUE" "$BSET"; then
  ok "R31-1 令牌四枚在表 + 三文件修饰器数字半径零残留"
else
  bad "R31-1 令牌缺失或修饰器数字半径回潮"
fi
# R31-2 手搓面对清零：28/30/999/20 的 Rounded-
# Rectangle 字面（含跨行形）全清；背景色底表改
# 走 overlayCard(panel)——SRC 内 panel 档
# overlayCard 恰 3 处（首页吐司/备份吐司/底表）。
if ! grep -qE 'cornerRadius: (28|30|999|20)([^0-9]|$)' "$SRC" \
   && [ "$(grep -cF 'overlayCard(radius: Radius.panel)' "$SRC")" = 3 ]; then
  ok "R31-2 手搓 28 对清零 + 底表走 overlayCard(panel)"
else
  bad "R31-2 手搓圆角字面对回潮或底表未走修饰器"
fi
# R31-3 glassControl 只许令牌：pill 总锚 14
# （收口 12 + 既有 2）、controlS 恰 4（AUD-
# A-06 批 6：图文方卡内联自绘收起钮并入
# squareFoldPill 单点、内联一份消灭，5→4）。
if [ "$(grep -cF 'glassControl(radius: Radius.pill)' "$SRC")" = 14 ] \
   && [ "$(grep -cF 'glassControl(radius: Radius.controlS)' "$SRC")" = 4 ]; then
  ok "R31-3 glassControl 令牌计数锚（pill 14 / controlS 4）"
else
  bad "R31-3 glassControl 令牌计数漂移"
fi
# R31-4 overlayCard 不重述默认值 cardS：
# overlayCard(radius: 22) 三文件零残留。
if ! grep -qF 'overlayCard(radius: 22)' "$SRC" "$RESCUE" "$BSET"; then
  ok "R31-4 overlayCard 默认值重述清零"
else
  bad "R31-4 overlayCard(radius: 22) 回潮"
fi
# R31-5 CornerRect 入参合法集：调用恰 10 处、
# 逐角入参只许 Radius.* / 0 / 条件式（裸数字
# 直入即红，承 [23] 内角规矩）。
if [ "$(grep -c 'CornerRect(' "$SRC")" = 10 ] \
   && ! grep -qE '(tl|tr|bl|br): [0-9]' "$SRC"; then
  ok "R31-5 CornerRect 10 处入参合法集（令牌/0）"
else
  bad "R31-5 CornerRect 计数或入参漂移"
fi
# R31-6 反 SPI 守卫：displayCornerRadius 全源
# 零出现（私有 API 永久排除）；utsname 恒为
# Diag 机型串一处（计数锚，防机型表偷渡）。
if ! grep -q 'displayCornerRadius' ./*.swift \
   && [ "$(grep -c 'utsname()' "$SRC")" = 1 ]; then
  ok "R31-6 反 SPI 守卫 + utsname 单点锚"
else
  bad "R31-6 SPI 偷渡或 utsname 增殖"
fi
# R31-7 容器同心新 API 零引入（引入须显式改
# 本断言 = 显式评审，plan §1.3 裁定）。
if ! grep -q 'ConcentricRectangle' ./*.swift \
   && ! grep -q 'UICornerConfiguration' ./*.swift; then
  ok "R31-7 ConcentricRectangle/UICornerConfiguration 零引入"
else
  bad "R31-7 未经评审引入容器同心新 API"
fi
# R31-8 隐式形状计数锚：Capsule()/Circle()
# 与盘点值 13/8 对账，增减须改锚即须过目。
# 改判（impl_dt_layout_resilience）：错误徽章钮
# 底由 RoundedRectangle(18) 改 Capsule（定尺寸
# 圆改最小尺寸胶囊、随计数文案生长），Capsule
# 12 → 13。
if [ "$(grep -c 'Capsule()' "$SRC")" = 13 ] \
   && [ "$(grep -c 'Circle()' "$SRC")" = 8 ]; then
  ok "R31-8 Capsule 13 / Circle 8 计数锚"
else
  bad "R31-8 隐式形状计数漂移"
fi
# R31-9 微装饰字面集封闭（0.9.52 定案保留）：
# 1.5×2 / 4×1 / 6×5 / 10×3 / 14×1 / 18×0，
# 任一增减即红（防无声增殖）。
# 改判（impl_dt_layout_resilience）：18 的唯一
# 用点（错误徽章钮底 RoundedRectangle）已改
# Capsule 退场，18×1 → 18×0。
if [ "$(grep -cF 'cornerRadius: 1.5' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'cornerRadius: 4)' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'cornerRadius: 6' "$SRC")" = 5 ] \
   && [ "$(grep -cF 'cornerRadius: 10' "$SRC")" = 3 ] \
   && [ "$(grep -cF 'cornerRadius: 14' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'cornerRadius: 18' "$SRC")" = 0 ]; then
  ok "R31-9 微装饰字面集计数锚（1.5/4/6/10/14/18=0）"
else
  bad "R31-9 微装饰字面集漂移"
fi

echo "[32] 编辑器健壮性 E4（定案 impl_editor_robust_e4.md / 审计 F-17/F-18/F-19）"
# E4-1 切后台 flush：App 级 scenePhase 的 .background
# 支内，经在席注册表 saveNow 冲刷 + 打点，且 flush
# 记账行须在哨兵 launchSuspend 之前（序锚：先冲刷
# 后清哨兵，防回收窗口内序反转）。
SEG32=$(awk '/onChange\(of: scenePhase\)/{f=1} f{print} f&&/launchResume/{exit}' "$SRC")
if has 'EDIT flush src=background' "$SRC" \
   && has 'EditorSeatRegistry.shared' "$SRC" \
   && [ "$(printf '%s' "$SEG32" | grep -n 'EDIT flush' | head -1 | cut -d: -f1)" -lt "$(printf '%s' "$SEG32" | grep -n 'launchSuspend' | head -1 | cut -d: -f1)" ]; then
  ok "E4-1 切后台 flush 在位（注册表 saveNow + 打点 + 序在 launchSuspend 前）"
else
  bad "E4-1 切后台 flush 缺失或序反转"
fi
# E4-2 空文档打开守卫 + 空段节点单点：工厂定义恰
# 一处、调用恰三处（打开守卫/原子尾随/删块兜底）。
if has 'EDIT empty doc seeded' "$SRC" \
   && [ "$(grep -c 'static func emptyParagraphNode' "$SRC")" = 1 ] \
   && [ "$(grep -c 'Self.emptyParagraphNode()' "$SRC")" = 3 ]; then
  ok "E4-2 空 doc 打开守卫 + emptyParagraphNode 单点（定义 1 / 调用 3）"
else
  bad "E4-2 空 doc 守卫或空段单点漂移"
fi
# E4-3 未知块降级呈现：开发文案「后续轮支持」全仓
# 零残留 + logOnce 打点键 + 普查 unknown 字段在位。
if ! grep -q '后续轮支持' ./*.swift \
   && has 'EDIT unknown block' "$SRC" \
   && has 'unknown-block:' "$SRC"; then
  ok "E4-3 未知块降级呈现（开发文案零残留 + logOnce 打点）"
else
  bad "E4-3 未知块呈现回潮或打点缺失"
fi
# E4-4 长文档量测普查：init 末普查行 + init 计时
# 基点在位（护栏专项的量测面，删即红）。
if has 'EDIT open census' "$SRC" \
   && has 'let initT0 = CFAbsoluteTimeGetCurrent()' "$SRC" \
   && has 'listItems=' "$SRC"; then
  ok "E4-4 打开普查量测点在位（census + init 计时）"
else
  bad "E4-4 普查量测点缺失"
fi

echo "[33] 媒体增强（Gallery 删/排序 + 视频插入，定案 impl_media_enhance.md / 审计 F-14/F-15）"
GB=$(awk '/^struct GalleryBlockView/,/^struct MusicPillView/' "$SRC")
# M33-1 删项：模型单点 applyGalleryRemove（摘引用
# + 压栈 + 落盘 + Diag）在位，且 gallery 段内角标
# 真接线（xmark 角标点按直调 remove）。
if has 'func applyGalleryRemove' "$SRC" \
   && has 'EDIT gallery remove' "$SRC" \
   && echo "$GB" | grep -q 'xmark.circle.fill' \
   && echo "$GB" | grep -q 'applyGalleryRemove'; then
  ok "M33-1 gallery 删项（模型单点 + 编辑态角标接线）"
else
  bad "M33-1 gallery 删项缺失或角标未接线"
fi
# M33-2 排序：实时换位单点 + drop 委托 + 拖起接线
# 三件齐备（DragPressEngine 不掺瓦级，独立轻量路）。
if has 'func applyGalleryMove' "$SRC" \
   && has 'struct GalleryTileDropDelegate' "$SRC" \
   && has 'galleryDragTileIndex' "$SRC" \
   && echo "$GB" | grep -q 'onDrag'; then
  ok "M33-2 gallery 排序（applyGalleryMove + DropDelegate + onDrag）"
else
  bad "M33-2 gallery 排序链不完整"
fi
# M33-3 卡编辑态行拾起退场：dragAllowed 含卡编辑
# 排除（瓦拖拽与块拾起同触点竞抢的源头收口）。
if has 'editor.cardEditBlockId != block.id' "$SRC"; then
  ok "M33-3 卡编辑态行不拾起（dragAllowed 排除在位）"
else
  bad "M33-3 卡编辑态仍武装拾起（瓦拖拽将与拾起竞抢）"
fi
# M33-4 视频成块：addVideoBlock 定义 1 + 调用 2
# （选片路 onPickVideo / 附件路 movie 分流），且
# 分流判据为 UTType .movie conformance。
if has 'func addVideoBlock' "$SRC" \
   && [ "$(grep -c 'addVideoBlock(fileId:' "$SRC")" = 3 ] \
   && has 'conforms(to: .movie)' "$SRC"; then
  ok "M33-4 视频成块单点（定义 1 / 调用 2 + movie 分流判据）"
else
  bad "M33-4 addVideoBlock 落点漂移（应定义 1 + 调用 2）"
fi
# M33-5 选片器视频支：PhotoPicker 默认关、附件选
# 片路显式开启（allowVideo: true 恰一处）+ movie
# 文件表示读字节在位；余调用点不许误开。
if has 'loadFileRepresentation' "$SRC" \
   && has 'UTType.movie.identifier' "$SRC" \
   && [ "$(grep -c 'allowVideo: true' "$SRC")" = 1 ]; then
  ok "M33-5 选片器视频支（默认关 / 仅附件路开启）"
else
  bad "M33-5 选片器视频支缺失或开启面漂移"
fi

echo "[34] 权限声明 + Live Activity 实况（定案 impl_ios_entitlements_liveops.md / impl_entitlements_b.md）"
LIVEOPS=MomentLiveOps.swift
LIVEATTR=MomentLiveOpsAttributes.swift
LIVEWIDGET=MomentLiveOpsWidget.swift
ENT=Moment.entitlements
WENT=MomentLiveOpsWidget.entitlements
# B34-1 用途声明拉满：主 plist 七键在位（定位沿用
# + 六项惰性就绪），缺串即 API 调用硬崩溃面。
miss=0
for k in NSLocationWhenInUseUsageDescription \
  NSCameraUsageDescription \
  NSPhotoLibraryUsageDescription \
  NSPhotoLibraryAddUsageDescription \
  NSMicrophoneUsageDescription \
  NSFaceIDUsageDescription \
  NSLocalNetworkUsageDescription; do
  has "$k" "$SH" || miss=1
done
if [ "$miss" = 0 ]; then
  ok "B34-1 用途声明七键在位（build-app2.sh plist）"
else
  bad "B34-1 用途声明缺键"
fi
# B34-2 实况 + 后台模式键集：Live Activities 两键、
# UIBackgroundModes 三成员、BGTask 两标识符；同行
# 禁 audio/location（虚假声明红线）。
if has 'NSSupportsLiveActivities' "$SH" \
   && has 'NSSupportsLiveActivitiesFrequentUpdates' "$SH" \
   && has '<string>remote-notification</string><string>processing</string><string>fetch</string>' "$SH" \
   && has 'com.canopies.moment.bg.processing' "$SH" \
   && has 'com.canopies.moment.bg.refresh' "$SH" \
   && ! grep 'UIBackgroundModes' "$SH" | grep -q 'audio\|location'; then
  ok "B34-2 实况/后台模式/BGTask 键集在位且无虚假模式"
else
  bad "B34-2 实况或后台模式键集漂移"
fi
# B34-3 五语 InfoPlist.strings：生成调用恰 5 份、
# 每份含显示名 + 七键（脚本以同一函数生成、键集
# 结构一致，此处锁调用数与函数内键数）。
if [ "$(grep -c '^write_infoplist_strings ' "$SH")" = 5 ] \
   && [ "$(grep -c 'printf ' "$SH")" -ge 8 ]; then
  ok "B34-3 InfoPlist.strings 五份生成（显示名+七键）"
else
  bad "B34-3 InfoPlist.strings 生成面漂移"
fi
# B34-4 entitlements 集 == 矩阵 B 级集：主 App 仅
# aps-environment=development；扩展为空集；禁区项
# （icloud-*/get-task-allow/application-groups）
# 在声明面零出现。
if has '<key>aps-environment</key><string>development</string>' "$ENT" \
   && [ "$(grep -c '<key>' "$ENT")" = 1 ] \
   && [ "$(grep -c '<key>' "$WENT")" = 0 ] \
   && ! grep -qi 'icloud\|get-task-allow\|application-groups' "$ENT" "$WENT" "$SH"; then
  ok "B34-4 entitlements 集与矩阵一致（主=aps / 扩展=空 / 禁区零）"
else
  bad "B34-4 entitlements 集漂移或禁区项混入"
fi
# B34-5 LiveOps 文件与构建接线：封装/属性/扩展三
# 文件在位，属性文件双目标（主 App 遍 + 扩展遍均
# 引用），扩展目标路径字符串在位。改判沿革
# （0.9.61 装机根治）：原预期「扩展产物入
# PlugIns/」已废——用户二分实测证 appex 一经捆
# 绑即整包拒装，交付包不再含 appex（编译保持、
# 入包由 BUNDLE_WIDGET_EXT 门控且现关，见 [52]
# INS52 组）；本条只锁编译接线与目标路径在位，
# 不再锁入包事实。
if [ -f "$LIVEOPS" ] && [ -f "$LIVEATTR" ] \
   && [ -f "$LIVEWIDGET" ] \
   && [ "$(grep -c 'MomentLiveOps.swift' "$SH")" -ge 18 ] \
   && [ "$(grep -c 'MomentLiveOpsAttributes.swift' "$SH")" -ge 20 ] \
   && has 'PlugIns/MomentLiveOpsWidget.appex' "$SH" \
   && has 'com.canopies.moment.liveops' MomentLiveOpsWidget-Info.plist; then
  ok "B34-5 LiveOps 三文件 + 双目标接线 + appex 编译接线（入包门控见 [52]）"
else
  bad "B34-5 LiveOps 接线不完整"
fi
# B34-6 挂点计数（§5.3 表）：start = 桥分发 1 +
# 驱动核 1 + 导出/导入 2；end = 桥 done 1 + 驱动
# finish 2 + 导出/导入 defer 2；update = 步进 1。
if [ "$(grep -c 'MomentLiveOps.shared.start' "$BTOOLS" "$UITEST" "$SRC" | awk -F: '{s+=$2} END {print s}')" = 4 ] \
   && [ "$(grep -c 'MomentLiveOps.shared.end' "$BTOOLS" "$UITEST" "$SRC" | awk -F: '{s+=$2} END {print s}')" = 5 ] \
   && [ "$(grep -c 'MomentLiveOps.shared.update' "$UITEST")" = 1 ] \
   && has 'liveLongOpTools' "$BTOOLS"; then
  ok "B34-6 实况挂点计数与 §5.3 表一致（start 4 / end 5 / update 1）"
else
  bad "B34-6 实况挂点漂移"
fi
# B34-7 Diag 五式齐备（OPS live start/update/end/
# skip/grace）且节流常量 5s 与 staleDate 600 在位。
if has 'OPS live start' "$LIVEOPS" \
   && has 'OPS live update' "$LIVEOPS" \
   && has 'OPS live end' "$LIVEOPS" \
   && has 'OPS live skip' "$LIVEOPS" \
   && has 'OPS live grace' "$LIVEOPS" \
   && has 'addingTimeInterval(600)' "$LIVEOPS"; then
  ok "B34-7 OPS live Diag 五式 + staleDate 口径在位"
else
  bad "B34-7 OPS live Diag 不完整"
fi
# B34-8 BGTask 与通知面：注册点在 App.init、两
# handler 消费点（快照清理 / OPS 拉取）在位、桥
# 设置页通知开关接线。
if has 'MomentLiveOps.registerBackgroundTasks()' "$SRC" \
   && has 'pruneForBackground' "$LIVEOPS" \
   && has 'OpsDirectives.refreshInBackground' "$LIVEOPS" \
   && has 'bridge.notify' "$BSET" \
   && has 'MomentLiveOps.setNotifyEnabled' "$BSET"; then
  ok "B34-8 BGTask 注册/消费 + 通知开关在位"
else
  bad "B34-8 BGTask 或通知面缺失"
fi
# B34-9 语言包新键五份齐备（liveops.* 七键：
# 标题四键 + 实况设计批步名三键；+
# bridge.notify 两键，键数守恒由 [9] 另锁）。
miss=0
for f in ../../web/lang/zh-CN.json ../../web/lang/zh-TW.json \
         ../../web/lang/en-US.json ../../web/lang/ja-JP.json \
         ../../web/lang/ko-KR.json; do
  for k in liveops.bridge_op liveops.export liveops.import \
           liveops.scenario liveops.done liveops.failed \
           liveops.running \
           bridge.notify bridge.notify_note; do
    grep -q "\"$k\"" "$f" || miss=1
  done
done
if [ "$miss" = 0 ]; then
  ok "B34-9 liveops/notify 键五语齐备"
else
  bad "B34-9 语言包新键缺份"
fi

echo "[35] MD 预览缓存失效单点（定案 fix_md_cache_stale.md）"
# MD35-1 失效单点：invalidateMdCache 定义恰一处，
# 且函数体内清树与复位 done 两写齐备（同点作废，
# 不变量：done 为真 ⟹ blocks 是 cacheText 的树）。
SEG35A=$(awk '/func invalidateMdCache/{f=1} f{print} f&&/^    }$/{exit}' "$SRC")
if [ "$(grep -c 'func invalidateMdCache' "$SRC")" = 1 ] \
   && printf '%s' "$SEG35A" | grep -q 'mdCacheBlocks = \[\]' \
   && printf '%s' "$SEG35A" | grep -q 'mdCacheDone = false'; then
  ok "MD35-1 失效单点在位（定义 1 处，体内清树 + 复位 done 同点）"
else
  bad "MD35-1 失效单点缺失或体内两写不齐"
fi
# MD35-2 mdKind 失效路径经单点：段内含单点调用、
# 无散点直清；全文件经 block. 的散点直清/直复位
# 为零（mdBlocks 的回填写 = arr / = true 不在
# 此列——那是与命中口径成对的填充半边）。
SEG35B=$(awk '/func mdKind/{f=1} f{print} f&&/^    }$/{exit}' "$SRC")
if printf '%s' "$SEG35B" | grep -q 'invalidateMdCache()' \
   && ! printf '%s' "$SEG35B" | grep -q 'mdCacheBlocks = \[\]' \
   && [ "$(grep -c '\.mdCacheBlocks = \[\]' "$SRC")" = 0 ] \
   && [ "$(grep -c '\.mdCacheDone = false' "$SRC")" = 0 ]; then
  ok "MD35-2 mdKind 经失效单点（散点直写全仓为零）"
else
  bad "MD35-2 mdKind 未经单点或出现散点直写"
fi
# MD35-3 mdBlocks 命中/回填口径未动：命中仍以
# done 为凭、解析回填仍置 done（不变量消费半边）。
SEG35C=$(awk '/func mdBlocks/{f=1} f{print} f&&/^    }$/{exit}' "$SRC")
if printf '%s' "$SEG35C" | grep -q 'block.mdCacheDone' \
   && printf '%s' "$SEG35C" | grep -q 'block.mdCacheDone = true'; then
  ok "MD35-3 mdBlocks 命中凭 done + 回填置 done 在位"
else
  bad "MD35-3 mdBlocks 命中/回填口径漂移"
fi

echo "[36] 文字大小真跟随防回潮（Dynamic Type 全量实装，impl_dynamic_type_full.md）"
# DT36-1 数字字面字号零回潮：四文件（主 App /
# 救援 / 桥设置 / 标题字段）内 .system(size:<数
# 字 与 UIFont.systemFont(ofSize:<数字 合计恒
# 为白名单 2——MomentApp.capsuleHeight 的行高
# delta 基准字体（未缩放 14 semibold / 10 各
# 一：缩放基准本身不可缩放，否则 delta 恒
# 零）。跨行写法以 tr 合行后计数；新增字面字
# 号须先改走语义样式 / ScaledMetric / dynFont
# 并在此登记白名单理由。
# 改判注（fix_dynamic_type_follow，2026-11-27）：
# 「改走语义样式」一路已被 0.9.58 真机推翻——
# 语义样式面改系统字号纹丝不动；现行口径见
# [46]：SwiftUI 面一律 @ScaledMetric 喂点、
# UIKit 面经 FontFactory + FontHub epoch 重
# 刷。本条只锁数字字面防回潮，机制锁在 [46]。
DT_LIT=$(for f in MomentApp.swift MomentRescue.swift \
    MomentBridgeSettings.swift TitleTextField.swift; do
  tr '\n' ' ' < "$f"
done | grep -oE '\.system\(\s*size:\s*[0-9]|UIFont\.systemFont\(\s*ofSize:\s*[0-9]' \
  | wc -l | tr -d ' ')
if [ "$DT_LIT" = 2 ]; then
  ok "DT36-1 数字字面字号仅余胶囊高基准 2 处"
else
  bad "DT36-1 数字字面字号回潮（现 $DT_LIT 处，白名单 2）"
fi
# ── [36] 续：布局韧性（impl_dt_layout_resilience）──
# DT36-2 字形封顶全集：固定槽内的缩放字形一律封
# 顶至槽宽（min(同源度量, 槽宽)），槽与布局几何
# 不动。位点：min(f20,24)=菜单行/斜杠行图标（槽
# 24）、min(f22,34)=完成胶囊椭圆（槽 46、玻璃裁
# 切）、min(f22,30)=待办勾选（命中槽 44）、
# min(f16,24)=SetRow 图标、min(f17,28)=BackupRow
# 图标、min(f17,24)=双栏行图标、min(f15,28)=天气
# 可见性图标、min(f25,25)=手势图示。计数漂移 =
# 封顶位点增减，须同步报告白名单。
CAP_OK=1
for spec in 'min(f20, 24):2' 'min(f22, 34):1' \
  'min(f22, 30):1' 'min(f16, 24):1' \
  'min(f17, 28):1' 'min(f17, 24):1' \
  'min(f15, 28):1' 'min(f25, 25):1'; do
  tok=${spec%:*}; want=${spec#*:}
  [ "$(grep -cF "$tok" "$SRC")" = "$want" ] \
    || CAP_OK=0
done
if [ "$CAP_OK" = 1 ]; then
  ok "DT36-2 字形封顶全集在位（8 类槽封顶计数守恒）"
else
  bad "DT36-2 字形封顶位点漂移（见 impl_dt_layout_resilience 白名单）"
fi
# DT36-3 文字定高容器零残留：装缩放文字的定高帧
# 已全改最小高/胶囊生长——备份确认双钮（BackupView
# 段 minHeight 44 ×2、全文件 frame(height: 44)
# 零）、诊断日志页（DiagLogPage 段 minHeight 46
# 归零：原导出文字胶囊的生长式 minHeight 随胶囊
# 改图标钮退役——用户 2026-11-28 改判，图标钮定
# 尺寸 46 不装文字、形态由 [59] DL59 锁）、错误
# 徽章钮（minWidth/minHeight 36 胶囊、旧定尺寸零）。
BV36=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
DL36=$(awk '/^struct DiagLogPage/,/^struct ListBlockView/' "$SRC")
EB36=$(awk '/^struct ErrBadgeOverlay/,/^final class DiagLog/' "$SRC")
if [ "$(grep -cF 'frame(height: 44)' "$SRC")" = 0 ] \
   && [ "$(echo "$BV36" | grep -cF 'frame(minHeight: 44)')" = 2 ] \
   && [ "$(echo "$DL36" | grep -cF 'frame(minHeight: 46)')" = 0 ] \
   && [ "$(echo "$DL36" | grep -cF 'frame(height: 46)')" = 0 ] \
   && echo "$EB36" | grep -qF 'minWidth: 36, minHeight: 36' \
   && ! echo "$EB36" | grep -qF 'frame(width: 36, height: 36)'; then
  ok "DT36-3 文字定高容器全改生长式（钮/胶囊/徽章）"
else
  bad "DT36-3 文字定高容器有残留或生长式接线缺失"
fi
# DT36-4 列表标记同源缩放：MD 标记框 markerW =
# scaledBase × 1.125（间距账 J20-12 同步；
# scaledBase = FontFactory 按类别缩放的
# baseSize——fix_dynamic_type_follow 改判：旧
# 锚 baseSize 未含类别缩放、与已缩放的正文
# dynFont 脱档，现 em 账基字与正文同档）、编辑列
# 表标记框/嵌套缩进走 ScaledMetric（markerW /
# indentOrdered 在位、旧定宽 18/20 零残留）。
LB36=$(awk '/^struct ListBlockView/,/^struct SlashCmd/' "$SRC")
if [ "$(grep -cF 'scaledBase * 1.125' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'frame(width: markerW' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'frame(width: 18,' "$SRC")" = 0 ] \
   && [ "$(echo "$LB36" | grep -cF 'frame(width: 20')" = 0 ] \
   && echo "$LB36" | grep -qF 'indentOrdered'; then
  ok "DT36-4 列表标记框与缩进同源缩放（MD + 编辑列表）"
else
  bad "DT36-4 列表标记同源缩放缺失或旧定宽残留"
fi
# DT36-5 导出徽章盒同源缩放：盒随徽章字（caption2
# 同源 f34）缩放、旧定尺寸 34 零残留。
if [ "$(grep -cF 'frame(width: f34, height: f34)' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'frame(width: 34, height: 34)' "$SRC")" = 0 ]; then
  ok "DT36-5 导出徽章盒 f34 同源缩放"
else
  bad "DT36-5 导出徽章盒未同源或旧定尺寸残留"
fi
# DT36-6 面板/底表限高内滚三点：背景底表（实测
# 高回写 bgSheetH 段内 ≥3 处 + 帧高上限 视口
# − 28）、导出面板（exportPanelH 同机制 + 上限
# 视口 − 67）、链接表单（斜杠层 maxH 传入限高）。
HDR36=$(awk '/^struct EditorHeaderView/,/^struct GalleryBlockView/' "$SRC")
if [ "$(echo "$HDR36" | grep -cF 'ui.bgSheetH')" -ge 3 ] \
   && [ "$(grep -cF 'ui.viewH - 28' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'ui.exportPanelH' "$SRC")" -ge 3 ] \
   && [ "$(grep -cF 'ui.viewH - 67' "$SRC")" -ge 2 ] \
   && [ "$(grep -cF 'linkFormPanel(maxH: maxH)' "$SRC")" = 1 ]; then
  ok "DT36-6 限高内滚三点（底表/导出面板/链接表单）"
else
  bad "DT36-6 限高内滚接线缺失（底表/导出/链接表单）"
fi
# DT36-7 固定尺寸文字容器白名单计数锁：以下定尺
# 寸容器经盘点在册（理由见 impl_dt_layout_
# resilience §白名单）——216 菜单面板 ×2（行最小
# 高 + 内滚/自然高）、246 编辑菜单/导出面板 ×3
# （换行 + 内滚）、188 图文行 ×1（设计截断、全
# 文经编辑可达）、366 图库占位瓦 ×2（内容恒小于
# 帧）、救援状态行键列 104 ×1（MomentRescue、键
# 值换行）。计数漂移须先改报告白名单再改此锁。
RS36=MomentRescue.swift
if [ "$(grep -cF 'frame(width: 216' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'frame(width: 246' "$SRC")" = 3 ] \
   && [ "$(grep -cF 'frame(height: 188)' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'frame(height: 366)' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'frame(width: 104' "$RS36")" = 1 ]; then
  ok "DT36-7 固定尺寸文字容器白名单计数守恒（5 类在册）"
else
  bad "DT36-7 白名单计数漂移（先改 impl_dt_layout_resilience 白名单）"
fi
# ── [36] 续二：首页领地韧性补批（impl_dt_home_resilience）──
# DT36-8 标签 chip 定高改最小高（韧性批 §5 登记
# R-1，类 B 手法）：方卡 chip 两体 minHeight
# small ? 18 : 20、行卡 chip minHeight 18，
# 旧定高字面全文件零残留。Web 的 18/20 是行
# 高本体——默认档 minHeight 托底逐值不变，
# AX 档随字生长不被 glassControl 裁字。
if [ "$(grep -cF 'frame(minHeight: small ? 18 : 20)' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'frame(minHeight: 18)' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'frame(height: small ? 18 : 20)' "$SRC")" = 0 ] \
   && [ "$(grep -cF 'frame(height: 18)' "$SRC")" = 0 ]; then
  ok "DT36-8 首页标签 chip 三体最小高生长（18/20 托底）"
else
  bad "DT36-8 chip 最小高缺失或旧定高残留"
fi
# DT36-9 方卡图文区内容驱动下限（登记 R-2）：
# 文区 minHeight 78（默认档内容 ≈76.5 托底
# 恒 78、AX 随字生长、图区让位），旧定高
# 78 零残留；整卡 aspect 与列表交界账
# （22/16）不经此帧。
if [ "$(grep -cF 'frame(minHeight: 78)' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'frame(height: 78)' "$SRC")" = 0 ]; then
  ok "DT36-9 方卡文区 minHeight 78 内容驱动"
else
  bad "DT36-9 方卡文区定高残留或最小高缺失"
fi

echo "[37] 标题提交同步冲刷（会话结束即提交点，定案 fix_title_commit_propagation.md）"
# TC37-1 提交点机制锁：commitTitle 函数体内标题
# 真变更分支只许同步冲刷（saveNow ×1）、不许再
# 走防抖（scheduleSave ×0）——S1 步 3 两遍确定
# 性回读旧标题的根源即提交走了 0.6s 防抖窗。
CT37=$(awk '/^private func commitTitle\(\) \{/,/^}/' "$SRC")
if [ "$(echo "$CT37" | grep -cF 'editor.saveNow()')" = 1 ] \
   && [ "$(echo "$CT37" | grep -cF 'editor.scheduleSave()')" = 0 ]; then
  ok "TC37-1 commitTitle 同步冲刷（saveNow ×1、防抖 ×0）"
else
  bad "TC37-1 commitTitle 提交路径漂移（须 saveNow 同步冲刷）"
fi
# TC37-2 漏斗守恒：commitTitle() 全文件恰 4 处
# （定义 1 + 调用 3：onEndEditing 会话结束 /
# closeEditor 退出 / 驱动 resign 动作）——标题
# 提交不许出现第二漏斗或漏斗外直写。
if [ "$(grep -cF 'commitTitle()' "$SRC")" = 4 ]; then
  ok "TC37-2 commitTitle 单漏斗（定义 1 + 调用 3）"
else
  bad "TC37-2 commitTitle 调用面漂移（期望定义 1 + 调用 3）"
fi
# TC37-3 正文流防抖不动：scheduleSave 函数体内
# 0.6s 防抖在位——本批只改标题提交点，不许以
# 缩短/删除防抖冒充根治（正文键入流口径不变）。
SS37=$(awk '/^    func scheduleSave\(\) \{/,/^    }/' "$SRC")
if [ "$(echo "$SS37" | grep -cF '.now() + 0.6')" = 1 ]; then
  ok "TC37-3 scheduleSave 正文流防抖 0.6s 守恒"
else
  bad "TC37-3 scheduleSave 防抖口径漂移"
fi
# TC37-4 镜像不变量：Library.persist 内存储写
# （upsertMemoJson）恒先于内存镜像更新
# （memos[idx] = it）——桥回读读镜像，镜像只许
# 跟随写成功，不许在消费方或提交方提前刷新。
PS37=$(awk '/^    func persist\(_ item: MemoItem\) \{/,/^    }/' "$SRC")
U37=$(echo "$PS37" | grep -nF 'upsertMemoJson' | head -1 | cut -d: -f1)
M37=$(echo "$PS37" | grep -nF 'memos[idx] = it' | head -1 | cut -d: -f1)
if [ -n "$U37" ] && [ -n "$M37" ] && [ "$U37" -lt "$M37" ]; then
  ok "TC37-4 persist 镜像随写（upsert 先于 memos 更新）"
else
  bad "TC37-4 persist 镜像不变量漂移"
fi

echo "[38] 桥会话实况保活（定案 impl_bridge_live_keepalive.md）"
# B38-1 桥形态在属性同文件内扩：LiveOpKind 有
# bridge 枚举、opDetail 静态短记字段在位（双
# 目标同编同文件、类型全名不变）。
if has 'case bridge = "bridge"' "$LIVEATTR" \
   && has 'var opDetail: String = ""' "$LIVEATTR"; then
  ok "B38-1 桥会话形态（kind=bridge + opDetail 短记）"
else
  bad "B38-1 桥会话属性形态缺失"
fi
# B38-2 复用单栈：Activity.request 只许在封装
# start 一处两式（16.2 content / 16.1 旧式）——
# 桥会话不许另起 request；同步段经 start 的
# kind: .bridge 起。
if [ "$(grep -c 'Activity.request' "$LIVEOPS")" = 2 ] \
   && has 'kind: .bridge' "$LIVEOPS" \
   && has 'func bridgeLiveSync' "$LIVEOPS"; then
  ok "B38-2 桥实况复用 LiveOps 单栈（request 单点）"
else
  bad "B38-2 桥实况另起实况栈或同步段缺失"
fi
# B38-3 起落收敛单点：协调器 syncBridgeLive 恰
# 1 定义、wrapper 同步入口全仓只被它调用 1 处；
# setState 段与回前台观察段各含一次收敛调用。
SEG38A=$(awk '/private func setState/,/^    }/' "$BRIDGE")
SEG38B=$(awk '/willEnterForegroundNotification/,/didBecomeActiveNotification/' "$BRIDGE")
if [ "$(grep -c 'func syncBridgeLive' "$BRIDGE")" = 1 ] \
   && [ "$(grep -c 'MomentLiveOps.shared.bridgeLiveSync' "$BRIDGE")" = 1 ] \
   && [ "$(echo "$SEG38A" | grep -c 'syncBridgeLive()')" = 1 ] \
   && [ "$(echo "$SEG38B" | grep -c 'syncBridgeLive()')" = 1 ]; then
  ok "B38-3 桥实况起落收敛单点（setState + 回前台）"
else
  bad "B38-3 桥实况收敛点漂移"
fi
# B38-4 成对量测面：驻留行（dur/socket/live）
# 起表点 + 桥实况起/止/不可用 Diag 三行在位——
# 无量测不宣称改善的证据面。
if has 'BRIDGE bg return dur=' "$BRIDGE" \
   && has 'backgroundAt = Date()' "$BRIDGE" \
   && has 'BRIDGE live start' "$LIVEOPS" \
   && has 'BRIDGE live end state=' "$LIVEOPS" \
   && has 'BRIDGE live unavailable' "$LIVEOPS"; then
  ok "B38-4 驻留成对量测 + 桥实况起止 Diag 在位"
else
  bad "B38-4 桥实况量测 Diag 缺失"
fi
# B38-5 边界守恒：宽限到期不打桥会话 waiting
# （expireGrace 段含 bridgeLiveId 跳过）；连通
# 路径（connectNow→handleSocketDown 段）零
# bridgeLive 引用——实况起落不改变连通语义。
SEG38C=$(awk '/private func expireGrace/,/^    }/' "$LIVEOPS")
SEG38D=$(awk '/private func connectNow/,/private func handleSocketDown/' "$BRIDGE")
if [ "$(echo "$SEG38C" | grep -c 'bridgeLiveId')" -ge 1 ] \
   && [ "$(echo "$SEG38D" | grep -c 'bridgeLive')" = 0 ]; then
  ok "B38-5 宽限跳过桥会话 + 连通路径零实况依赖"
else
  bad "B38-5 桥实况边界守恒漂移"
fi
# B38-6 呈现与文案：Widget 锁屏面读 opDetail
# （空则不呈现）；会话标题键五语齐备（键数守
# 恒由 [9] 另锁 429）。
miss=0
for f in ../../web/lang/zh-CN.json ../../web/lang/zh-TW.json \
         ../../web/lang/en-US.json ../../web/lang/ja-JP.json \
         ../../web/lang/ko-KR.json; do
  grep -q '"liveops.bridge_session"' "$f" || miss=1
done
if has 'opDetail' "$LIVEWIDGET" && [ "$miss" = 0 ]; then
  ok "B38-6 指纹短记呈现 + 会话标题键五语齐备"
else
  bad "B38-6 桥实况呈现面或语言键缺失"
fi

echo "[39] iPad 大屏贴合新 8 项（定案 impl_ipad_fit8.md）"
# IPAD39-1 底表 600 同口径三点：备份确认底表与
# bgSheet 在主文件各一处 maxWidth 600、WatchdogBar
# 在救援文件一处——三者同为宽屏收窄居中口径，任一
# 漂移即破 iPad 贴合账。
if [ "$(grep -c 'frame(maxWidth: 600)' "$SRC")" = 2 ] \
   && [ "$(grep -c 'frame(maxWidth: 600)' "$RESCUE")" = 1 ]; then
  ok "IPAD39-1 底表 600 同口径（确认底表/bgSheet/WatchdogBar）"
else
  bad "IPAD39-1 底表 600 口径漂移（主文件须 2、救援文件须 1）"
fi
# IPAD39-2 斜杠面板宽公式守恒：内容量测钳
# [220, 360] 且参与 viewW−24 同式（Web render.rs
# 移植式、定义单点）。
if has 'min(360, max(220, maxContent + 12' "$SRC" \
   && [ "$(grep -c 'func slashPanelWidth' "$SRC")" = 1 ]; then
  ok "IPAD39-2 斜杠面板宽钳 [220,360] 公式单点守恒"
else
  bad "IPAD39-2 斜杠面板宽公式漂移或定义多点"
fi
# IPAD39-3 编辑正文 1440 居中守恒：单列与双栏
# flow 两形态各一处 maxWidth 1440（frame 默认横
# 居中），缺一即某种形态在大屏全宽拉伸。
if [ "$(grep -c 'maxWidth: 1440' "$SRC")" = 2 ]; then
  ok "IPAD39-3 编辑正文 maxWidth 1440 双形态在位"
else
  bad "IPAD39-3 编辑正文 1440 上限漂移（须恰 2 处）"
fi
# IPAD39-4 浮层菜单锚块 + 视口钳制：panelLeftX
# 左缘钳制式单点（锚栏左缘、两侧 12）；上下翻转
# 式（越底改上方、顶钳 12）卡菜单/块菜单各一处。
if has 'min(max(x, 12), max(12, viewW - panelW - 12))' "$SRC" \
   && [ "$(grep -c '> geo.size.height - 12' "$SRC")" = 2 ]; then
  ok "IPAD39-4 菜单锚块定位 + 视口钳制/翻转双层守恒"
else
  bad "IPAD39-4 菜单锚定或视口钳制漂移"
fi
# IPAD39-5 DiagLogPage 设计形态：日志卡全宽全高
# 帧（段内 ≥1）+ 页眉 46 命中方成对（段内恰
# 2 = 返回钮 + 导出图标钮，用户 2026-11-28 改
# 判导出由文字胶囊改图标、与返回同形态）——宽
# 屏批刻意排除的全宽形态，不许被收窄居中批误伤。
SEG39=$(awk '/^struct DiagLogPage/,/func exportAll/' "$SRC")
if [ "$(echo "$SEG39" | grep -c 'maxWidth: .infinity, maxHeight: .infinity')" -ge 1 ] \
   && [ "$(echo "$SEG39" | grep -c 'width: 46, height: 46')" = 2 ]; then
  ok "IPAD39-5 DiagLogPage 全宽日志卡 + 页眉 46 钮成对守恒"
else
  bad "IPAD39-5 DiagLogPage 形态漂移（全宽卡或页眉钮）"
fi
# IPAD39-6 备份 toast 全宽条 Web 口径：Web
# .backup-toast 引用恰 2 处（首页撤销条 C-A1 +
# 备份页 toast S4）——同组件两实例、全宽条形态
# 的出处锚，任一改回居中胶囊即丢锚。
if [ "$(grep -c 'Web .backup-toast' "$SRC")" = 2 ]; then
  ok "IPAD39-6 全宽 toast 条 Web 口径双实例守恒"
else
  bad "IPAD39-6 toast 全宽条口径漂移（Web 引用须恰 2）"
fi
# IPAD39-7 系统呈现面：选图走 PHPicker 两个
# representable、文件走 fileImporter、分享走
# UIActivityViewController——iPad 上均为系统居
# 中卡形态，App 侧不自绘弹窗几何（禁区 Photos-
# Picker 由 [2] 另锁）。
if [ "$(grep -c 'PHPickerViewController(configuration' "$SRC")" = 2 ] \
   && [ "$(grep -c 'fileImporter(isPresented' "$SRC")" -ge 2 ] \
   && [ "$(grep -c 'UIActivityViewController(' "$SRC")" -ge 1 ]; then
  ok "IPAD39-7 系统 sheet/PHPicker 呈现面守恒（系统居中卡）"
else
  bad "IPAD39-7 系统呈现面漂移（PHPicker/fileImporter/分享）"
fi
# IPAD39-8 命中尺寸不随屏放大：页眉/页头钮的
# 46×46 命中方全文件恰 8 处——命中贴合手指不
# 贴屏幕，iPad 同值；计数漂移须先改 impl_
# ipad_fit8.md 第 8 项账再改本锁。沿革：原 7
# 处（返回/关闭类），2026-11-28 DiagLogPage
# 导出改图标钮（与返回同形态成对）新增 1 处，
# 账已先行改至 8（fix_diaglog_header_
# spacing.md）。
if [ "$(grep -c 'width: 46, height: 46' "$SRC")" = 8 ]; then
  ok "IPAD39-8 命中 46 方八处守恒（不随屏放大）"
else
  bad "IPAD39-8 命中 46 方计数漂移（须恰 8，先改 fit8 账）"
fi

echo "[40] 备份小批（BK-1 契约拆分 / BK-2 死字段清理 / BK-3 toast 后移，定案 impl_backup_tail.md）"
# BK40-1 成败/计数契约拆分结构锁：ImportOutcome
# 单定义；commitStagedImport 体内 ok:false 记录
# 恰 2（AUD-C-01 lib 守卫 + importBackup 的
# catch；0.9.62 沿革——原「只许 catch 一处」随
# lib==nil 如实失败守卫新增第二记账点）、
# .failure 出口恰 3（writeBlocked + lib 守卫 +
# catch）、.success 出口恰 1；提交点（importOk
# = true）恒先于 reload——计数与重载不许再进
# 成败域（边沿 A/B 根治）。
CSI40=$(awk '/^    func commitStagedImport\(\) -> ImportOutcome \{/,/^    \}$/' "$SRC")
OKT40=$(echo "$CSI40" | grep -nF 'importOk = true' | head -1 | cut -d: -f1)
RLD40=$(echo "$CSI40" | grep -nF 'try reload(lib: lib)' | head -1 | cut -d: -f1)
if [ "$(grep -c 'enum ImportOutcome' "$SRC")" = 1 ] \
   && [ "$(echo "$CSI40" | grep -cF 'recordOp(kind: "import", ok: false')" = 2 ] \
   && [ "$(echo "$CSI40" | grep -cF 'return .failure')" = 3 ] \
   && [ "$(echo "$CSI40" | grep -cF 'return .success(stats: stats)')" = 1 ] \
   && [ "$(echo "$CSI40" | grep -cF 'IMPORT stats unparsed')" = 1 ] \
   && [ -n "$OKT40" ] && [ -n "$RLD40" ] && [ "$OKT40" -lt "$RLD40" ]; then
  ok "BK40-1 ImportOutcome 契约拆分（成败单点、计数/重载出成败域）"
else
  bad "BK40-1 ImportOutcome 契约漂移（成败与计数重新耦合）"
fi
# BK40-2 stageImport 只回校验成败 + stagedStats
# 死字段零残留：stage 体内 validateBackup 在位、
# parseStats 零命中（计数不再作判据）；字段名全
# 文件零命中（BK-2 清理验收，退役即零残留）。
STG40=$(awk '/^    func stageImport\(from picked: URL\) -> Bool \{/,/^    \}$/' "$SRC")
if [ "$(echo "$STG40" | grep -cF 'validateBackup')" = 1 ] \
   && [ "$(echo "$STG40" | grep -cF 'parseStats')" = 0 ] \
   && [ "$(grep -c 'stagedStats' "$SRC")" = 0 ]; then
  ok "BK40-2 stageImport 回 Bool + stagedStats 零残留"
else
  bad "BK40-2 stageImport 契约或 stagedStats 残留漂移"
fi
# BK40-3 导出 toast 锚点后移：BackupView 段内
# ShareSheet 的 onComplete 恰 1 处；status.shared
# 在段内恰 2 处（opMessage 记录口径 + onComplete
# toast），确认底表段内零命中（生成成功不再即时
# 报「文件已分享」，BK-3）。
BV40=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
SHT40=$(awk '/private var backupConfirmSheet/,/^    private func showToast/' "$SRC")
if [ "$(echo "$BV40" | grep -cF 'ShareSheet(url: url, onComplete:')" = 1 ] \
   && [ "$(echo "$BV40" | grep -cF '"status.shared"')" = 2 ] \
   && [ "$(echo "$SHT40" | grep -cF '"status.shared"')" = 0 ]; then
  ok "BK40-3 toast 锚分享完成（onComplete 单点、底表零即时 toast）"
else
  bad "BK40-3 toast 锚点漂移（回生成点或 onComplete 缺失）"
fi
# BK40-4 计数未知成功路 + 重载失败提示接线：
# 确认底表段内 ImportOutcome 分支与无计数成功
# 文案（复用 backup.hist_restored）在位；commit
# 体内重载失败 Diag + notice 键在位。
if [ "$(echo "$SHT40" | grep -cF 'case .success(let stats)')" = 1 ] \
   && [ "$(echo "$SHT40" | grep -cF 'Lang.t("backup.hist_restored")')" = 1 ] \
   && [ "$(echo "$CSI40" | grep -cF 'notice.import_reload_failed')" = 1 ] \
   && [ "$(echo "$CSI40" | grep -cF '导入后重载失败')" = 1 ]; then
  ok "BK40-4 计数未知走无计数成功文案 + 重载失败 Diag/notice 接线"
else
  bad "BK40-4 计数未知分支或重载失败提示缺失"
fi
# BK40-5 lib == nil 如实失败锁（AUD-C-01）：
# stageImport/commitStagedImport 两函数体内
# 可选链（lib?.）零命中 + guard let lib 各
# 恰 1——库未打开时禁假成功（校验假过 / 导
# 入假成功弹 toast），与 exportZip 样板同口径。
if [ "$(echo "$STG40" | grep -c 'lib?\.')" = 0 ] \
   && [ "$(echo "$CSI40" | grep -c 'lib?\.')" = 0 ] \
   && [ "$(echo "$STG40" | grep -cF 'guard let lib else')" = 1 ] \
   && [ "$(echo "$CSI40" | grep -cF 'guard let lib else')" = 1 ]; then
  ok "BK40-5 导入两面 lib 守卫（可选链零命中 + 显式守卫各 1）"
else
  bad "BK40-5 导入 lib 守卫漂移（可选链回潮或守卫缺失）"
fi

echo "[41] 桥呈现三项（定案 fix_bridge_presentation_trio.md；断言名 BRP40 沿设计，组号顺延——[40] 已被备份小批占用）"
# BRP40-1 回执写点单点：revokeOutcome 赋值恒 6
# （disconnectAndRevoke 收口段 4：pending /
# confirmed / unconfirmed ×2；清除点 2：
# beginPairing / finishPairing 置 nil）；吊销
# dataTask 的丢弃式空闭包零残留。
if [ "$(grep -c 'revokeOutcome =' "$BRIDGE")" = 6 ] \
   && [ "$(grep -c '_, _, _ in' "$BRIDGE")" = 0 ]; then
  ok "BRP40-1 吊销回执写点单点（赋值 6）+ 空闭包零残留"
else
  bad "BRP40-1 吊销回执写点漂移或空闭包回潮"
fi
# BRP40-2 Diag 三分行齐（confirmed / unconfirmed
# / skipped）+ 旧行 BRIDGE revoked via=app 在位
# （[16] B16-4 锁不破）。
if has 'BRIDGE revoke relay=confirmed' "$BRIDGE" \
   && has 'BRIDGE revoke relay=unconfirmed' "$BRIDGE" \
   && has 'BRIDGE revoke relay=skipped' "$BRIDGE" \
   && has 'BRIDGE revoked via=app' "$BRIDGE"; then
  ok "BRP40-2 吊销回执 Diag 三分行 + 旧行守恒"
else
  bad "BRP40-2 吊销回执 Diag 分行缺失"
fi
# BRP40-3 空集如实呈现：设置页已配对分支含
# bridge.scopes_none 渲染点；旧三元兜底式
# （空集断言成只读）零残留。
if has 'bridge.scopes_none' "$BSET" \
   && [ "$(grep -cF 'scopes.isEmpty ? Lang.t("bridge.scope_read")' "$BSET")" = 0 ]; then
  ok "BRP40-3 scopes 空集如实呈现 + 旧兜底零残留"
else
  bad "BRP40-3 scopes 空集呈现漂移或旧兜底回潮"
fi
# BRP40-4 规范集与派生单点：scopeUniverse 定义
# 恰 1、ungrantedScopes 派生在位；源头虚构兜底
# ?? ["read"] 全文件零残留（fail-closed 改判）。
if [ "$(grep -c 'static let scopeUniverse' "$BRIDGE")" = 1 ] \
   && has 'var ungrantedScopes' "$BRIDGE" \
   && [ "$(grep -cF '?? ["read"]' "$BRIDGE")" = 0 ]; then
  ok "BRP40-4 scopeUniverse 单点 + 未授派生 + 兜底改判守恒"
else
  bad "BRP40-4 scope 规范集/派生漂移或虚构兜底回潮"
fi
# BRP40-5 reason 留存单点：lastStateReason 赋值
# 恒 1（setState 内；声明行口径不计入本式）。
if [ "$(grep -c 'lastStateReason = ' "$BRIDGE")" = 1 ]; then
  ok "BRP40-5 lastStateReason 留存单点（setState）"
else
  bad "BRP40-5 lastStateReason 写点漂移（须恰 1）"
fi
# BRP40-6 reason 映射四路：network 两 token /
# timeout 两 token / unknown 兜底键 / 仅
# {backoff, connecting} 带因的门，两 token 对
# 与三键须齐在 stateReasonKey 派生处。
if has '"receive_error", "send_error"' "$BRIDGE" \
   && has '"heartbeat_timeout", "probe_timeout"' "$BRIDGE" \
   && has '"bridge.reason_network"' "$BRIDGE" \
   && has '"bridge.reason_timeout"' "$BRIDGE" \
   && has '"bridge.reason_unknown"' "$BRIDGE" \
   && has 'linkState == "backoff"' "$BRIDGE" \
   && has 'linkState == "connecting"' "$BRIDGE"; then
  ok "BRP40-6 reason 映射四路 + 状态门守恒"
else
  bad "BRP40-6 reason 映射漂移（token 对/兜底键/状态门）"
fi
# BRP40-7 五语 8 新键逐包齐 + 五包键数互等
# （绝对总数由 [9] 单点另锁，避免并行批次各写
# 一个数打架；本批对账见 fix_bridge_
# presentation_trio.md 落码节）。
miss=0
for f in ../../web/lang/zh-CN.json ../../web/lang/zh-TW.json \
         ../../web/lang/en-US.json ../../web/lang/ja-JP.json \
         ../../web/lang/ko-KR.json; do
  for k in bridge.revoke_pending bridge.revoke_confirmed \
           bridge.revoke_unconfirmed bridge.scopes_none \
           bridge.scopes_ungranted bridge.reason_network \
           bridge.reason_timeout bridge.reason_unknown; do
    grep -q "\"$k\"" "$f" || miss=1
  done
done
if [ "$miss" = 0 ] && python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
counts = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        counts.append(len(json.load(f)))
sys.exit(0 if len(set(counts)) == 1 else 1)
PYEOF
then
  ok "BRP40-7 五语 8 新键逐包齐 + 五包键数互等"
else
  bad "BRP40-7 桥呈现新键缺失或五包键数不齐"
fi

echo "[42] SVG 解码分流（P2-7 根治，定案 fix_svg_image_page.md）"
# SVG42-1 嗅探汇合点单点：isSvgData 定义在光栅
# 文件恰 1 处；ImageLoader.publish 段内嗅探调
# 用 / 光栅化调用 / 管线汇合调用各恰 1——
# fileId/URL 两路只许经 publish 汇合分流，不
# 许两路各备一份。沿革：原锁 decodeImage( 恒
# 2 行（定义 + 汇合点调用）；审计批 3 解码管
# 线收口后 decodeImage 整体退役、汇合点改
# MediaDecode.image(（全文件恰 1、即 publish
# 内），单汇合点不变量不变、符号随机制迁移。
PUB42=$(awk '/private func publish\(data: Data\?/,/^    }/' "$SRC")
if [ -f "$SVGR" ] \
   && [ "$(grep -c 'func isSvgData' "$SVGR")" = 1 ] \
   && [ "$(echo "$PUB42" | grep -cF 'isSvgData(data)')" = 1 ] \
   && [ "$(echo "$PUB42" | grep -cF 'SvgRasterizer.shared.rasterize')" = 1 ] \
   && [ "$(echo "$PUB42" | grep -cF 'MediaDecode.image(')" = 1 ] \
   && [ "$(grep -cF 'MediaDecode.image(' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'decodeImage(' "$SRC")" = 0 ]; then
  ok "SVG42-1 内容嗅探单汇合点（两路共用 publish 分流）"
else
  bad "SVG42-1 嗅探分流点漂移（须单汇合点、两路共用）"
fi
# SVG42-2 光栅化器沙箱语义锁：SVG-as-image 口
# 径两件——禁脚本（allowsContentJavaScript =
# false）与 baseURL: nil（外部资源无基可解）
# 字面在位，任一漂移即破沙箱等价性。
if has 'allowsContentJavaScript = false' "$SVGR" \
   && has 'baseURL: nil' "$SVGR"; then
  ok "SVG42-2 光栅化沙箱语义（禁脚本 + baseURL nil）"
else
  bad "SVG42-2 光栅化沙箱语义漂移"
fi
# SVG42-3 判图守恒锁：名扩展集仍含 svg（判图
# 对账面 attIsImage 未被分流改动）；入口计数
# 改判（fix_image_tap_regression 沿革）：五入
# 口原直赋 editor.imageTarget 已收口路由单点，
# 计数改锁 editor.presentImagePage 调用恰 5
# （图块/gallery/附件整幅/文件行分发/图文卡图
# 区），防入口分流补丁混入的意图不变。
if has '"bmp", "svg", "avif", "heic", "heif"' "$SRC" \
   && [ "$(grep -c 'editor\.presentImagePage(' "$SRC")" = 5 ]; then
  ok "SVG42-3 判图守恒（扩展集含 svg、路由单点入口调用恰 5）"
else
  bad "SVG42-3 判图口径或图片页入口计数漂移"
fi
# SVG42-4 构建名单锁：MomentSvgRaster.swift 在
# build-app2.sh 内 ≥21 处（20 遍次级输入 + 自
# 身 primary 遍），且 svg_raster.o 进链接行。
if [ "$(grep -c 'MomentSvgRaster.swift' "$SH")" -ge 21 ] \
   && has 'svg_raster.o' "$SH"; then
  ok "SVG42-4 光栅文件在构建名单（多遍 + primary + 链接）"
else
  bad "SVG42-4 光栅文件构建名单缺失"
fi
# SVG42-5 呈现守恒锁：ZoomableImageView fit 基
# 准 min(fitScale, 1)（小图不放大口径）字面未
# 动——本批靠 scale 回填使 image.size = 自然
# 尺寸、呈现公式零改动；缩放上限式与可用区公
# 式已分别由 K22-2 与图片页可用高检查锁定，
# 此处不重复立项（定案 §5 口径）。
if has 'let base = min(fitScale, 1)' "$SRC"; then
  ok "SVG42-5 fit 基准守恒（min(fitScale, 1)，呈现零改动）"
else
  bad "SVG42-5 fit 基准式漂移（呈现口径被动）"
fi

echo "[43] 编辑回路 E1（组字守卫/智能前缀/原子退格/斜杠守卫集/粘贴守卫/标题 Esc，定案 impl_editor_loop_e1.md / 审计 F-01/F-02/F-08/M-01/M-02/m-01）"
# E43-1 组字守卫位置锁（F-01）：didChange 段内
# marked 守卫必须在 runs 写模型之前（守卫在后 =
# 中间态已入模型，等于没守）。
E43SEG_DIDCHANGE=$(awk '/func textViewDidChange/ {f=1} f {print} f && /^        }$/ {exit}' "$SRC")
E43_ORDER=$(echo "$E43SEG_DIDCHANGE" | awk '/guard tv.markedTextRange == nil else \{ return \}/{g=NR} /parent.block.runs/{r=NR} END{print (g>0 && r>0 && g<r) ? 1 : 0}')
if [ "$E43_ORDER" = 1 ]; then
  ok "E43-1 组字守卫在 runs 入模型之前（F-01）"
else
  bad "E43-1 组字守卫缺失或位置漂移"
fi
# E43-2 智能前缀（F-02）：匹配函数定义恰 1、尾
# 扫定义 + 调用点合计恰 11、四类分派齐备。调
# 用点沿革：原六点（didChange/insertLines/
# splitBlock/mergeBlockBackward/mergeListItem-
# Backward 两出口）+ B-05 前向合并四点（merge-
# BlockForward 尾一、mergeListItemForward 三
# 出口，见 [58] FD 组）。
E43SEG_SMART=$(awk '/func applySmartPrefixIfNeeded/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ "$(grep -c 'func smartPrefixMatch' "$SRC")" = 1 ] \
  && [ "$(grep -c 'applySmartPrefixIfNeeded' "$SRC")" = 11 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .divider')" = 1 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .heading')" = 1 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .quote')" = 1 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .todo')" = 1 ]; then
  ok "E43-2 智能前缀匹配 + 尾扫调用点普查（11） + 四类分派（F-02）"
else
  bad "E43-2 智能前缀构造漂移"
fi
# E43-3 原子退格（F-08）：选中态声明恰 1、顶层
# 与列表首项两支各恰 1 处赋值、Diag 行恰 2。
if [ "$(grep -c '@Published var selectedBlockId' "$SRC")" = 1 ] \
  && [ "$(grep -c 'selectedBlockId = prev.id' "$SRC")" = 1 ] \
  && [ "$(grep -c 'selectedBlockId = blocks\[li - 1\].id' "$SRC")" = 1 ] \
  && [ "$(grep -c 'backspace before atomic' "$SRC")" = 2 ]; then
  ok "E43-3 原子前驱退格两支选中态 + Diag（F-08）"
else
  bad "E43-3 原子退格支缺失或漂移"
fi
# E43-4 斜杠守卫集（M-01）：updateSlash 段内
# heading/quote 排除各恰 1。
E43SEG_SLASH=$(awk '/func updateSlash/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ "$(echo "$E43SEG_SLASH" | grep -c 'block.type != "heading"')" = 1 ] \
  && [ "$(echo "$E43SEG_SLASH" | grep -c 'block.type != "quote"')" = 1 ]; then
  ok "E43-4 斜杠守卫集含 heading/quote 排除（M-01）"
else
  bad "E43-4 斜杠守卫集漂移"
fi
# E43-5 粘贴块型守卫（M-02）：handlePaste 段内
# codeBlock 早退恰 1。
E43SEG_PASTE=$(awk '/func handlePaste\(block/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ "$(echo "$E43SEG_PASTE" | grep -c 'if block.type == "codeBlock" { return false }')" = 1 ]; then
  ok "E43-5 粘贴 codeBlock 守卫在位（M-02）"
else
  bad "E43-5 粘贴块型守卫缺失"
fi
# E43-6 标题 Esc 组字守卫（m-01）：TTF 组字态
# 声明 1 + 维护写点 2、handleEscape 标题支检查 1。
E43SEG_ESC=$(awk '/private func handleEscape/ {f=1} f {print} f && /^}$/ {exit}' "$SRC")
if [ "$(grep -c 'var composing = false' "$TFIELD")" = 1 ] \
  && [ "$(grep -c 'control.composing = f.markedTextRange != nil' "$TFIELD")" = 2 ] \
  && [ "$(echo "$E43SEG_ESC" | grep -c 'titleControl.composing')" = 1 ]; then
  ok "E43-6 标题 Esc 组字守卫（m-01）"
else
  bad "E43-6 标题 Esc 组字守卫漂移"
fi

echo "[44] 权限中心（impl_permission_center.md：声明矩阵运行时收口——状态真读/请求正道/本地网络探针/实况深链）"
PERMF=MomentPermissions.swift
# PC44-1 构建接线锁：MomentPermissions.swift 在
# build-app2.sh 内 ≥22 处（21 遍次级输入 + 自身
# primary 遍），permissions.o 两处（primary 输出
# + 链接行）。
if [ "$(grep -c 'MomentPermissions.swift' "$SH")" -ge 22 ] \
   && [ "$(grep -c 'permissions.o' "$SH")" -ge 2 ]; then
  ok "PC44-1 权限文件在构建名单（多遍 + primary + 链接）"
else
  bad "PC44-1 权限文件构建名单缺失"
fi
# PC44-2 状态真读锁：各框架状态读面在新文件内
# 各恰 1（通知走 getNotificationSettings 异步
# 读面；麦克风 recordPermission 新旧两代读面合
# 计 2；EventKit 日历/提醒两实体合计 2）。
if [ "$(grep -c 'getNotificationSettings' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'authorizationStatus(for: .video' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'authorizationStatus(for: .readWrite' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'authorizationStatus(for: .addOnly' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'recordPermission' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'canEvaluatePolicy' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'EKEventStore.authorizationStatus' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'areActivitiesEnabled' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'locManager.authorizationStatus' "$PERMF")" = 1 ]; then
  ok "PC44-2 权限页各项状态真读 API 在位（逐项恰一读面）"
else
  bad "PC44-2 状态真读 API 缺失或重复"
fi
# PC44-3 请求正道锁：请求 API 与权限项一一对
# 应、各恰 1（相册两路 requestAuthorization
# (for:) 合计恰 2；麦克风新旧两代 API 各 1）。
if [ "$(grep -c 'requestWhenInUseAuthorization' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'requestAccess(for: .video' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'PHPhotoLibrary.requestAuthorization' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'requestRecordPermission' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'evaluatePolicy' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'requestFullAccessToEvents' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'requestFullAccessToReminders' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'NWBrowser' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'UNUserNotificationCenter.current()' "$PERMF")" = 2 ]; then
  ok "PC44-3 请求钮与框架请求 API 一一对应（各恰一）"
else
  bad "PC44-3 请求 API 对应关系漂移"
fi
# PC44-4 深链限定锁：openSettingsURLString 全
# App 仅权限文件 1 处（仅实况 (c) 类可用深链；
# 其余项一律页内请求/状态呈现）。
if [ "$(grep -c 'openSettingsURLString' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'openSettingsURLString' "$SRC")" = 0 ] \
   && [ "$(grep -c 'openSettingsURLString' "$LIVEOPS")" = 0 ]; then
  ok "PC44-4 系统设置深链仅限实况一类（全 App 恰一处）"
else
  bad "PC44-4 深链越界（非 (c) 类不得用深链代替请求）"
fi
# PC44-5 Diag 单点锁：请求结果行同式三处（通
# 用收口 / 定位委托回调 / 本地网络探针收口），
# 进页行恰 1；字号无裸字面（DT 口径：fix_
# dynamic_type_follow 改判——原「.system(size:
# 零」以语义样式为跟随通道，该通道已被真机推
# 翻；现全经 @ScaledMetric 喂点：.system(size:
# f 恰 4、数字字面 0，意图不变——无固定字号。
# 计数沿革：原 5 含文字胶囊 f13 一处，该胶囊
# 经 fix_permissions_feedback63 退役改图标标
# 示（字形走 frame 喂点、不经 .system(size:)），
# 故改判 4）。
if [ "$(grep -c 'SET perm request kind=' "$PERMF")" = 3 ] \
   && [ "$(grep -c 'SET permissions enter' "$PERMF")" = 1 ] \
   && [ "$(grep -c '\.system(size: f' "$PERMF")" = 4 ] \
   && [ "$(grep -cE '\.system\(size: [0-9]' "$PERMF")" = 0 ]; then
  ok "PC44-5 权限 Diag 单点（请求结果行 + 进页行）"
else
  bad "PC44-5 权限 Diag 打点漂移"
fi
# PC44-6 设置接线锁：权限子页在 Sub/导航/设置
# 行三处接线齐备（MomentApp 侧；case 字面 2 处
# = Sub.id 映射 + 导航目标分派）。route 赋值
# 基数 1→2（U5 批增补：settings.view 注册面
# openPermissions 同体动作，与设置行同一赋值
# 本体、非新入口）。
if [ "$(grep -c 'case .permissions:' "$SRC")" = 2 ] \
   && [ "$(grep -c 'PermissionsView()' "$SRC")" = 1 ] \
   && [ "$(grep -c 'nav.route = .permissions' "$SRC")" = 2 ]; then
  ok "PC44-6 权限页设置族接线（枚举/导航/入口行）"
else
  bad "PC44-6 权限页接线缺失"
fi
# PC44-7 声明增补锁：日历/提醒四键 + Bonjour
# 服务在 plist 构造段在位；build 内 NSCalen-
# dars/NSReminders 字面各 4 行（plist 2 + 函
# 数 printf 2…函数按 locale 共用、与调用参数无
# 关），_moment._tcp 两处（plist + 探针）。
if [ "$(grep -c 'NSCalendars' "$SH")" = 4 ] \
   && [ "$(grep -c 'NSReminders' "$SH")" = 4 ] \
   && has 'NSBonjourServices' "$SH" \
   && [ "$(grep -c '_moment._tcp' "$SH")" = 1 ] \
   && [ "$(grep -c '_moment._tcp' "$PERMF")" = 1 ] \
   && [ "$(grep -c '\-65570' "$PERMF")" = 1 ]; then
  ok "PC44-7 日历/提醒声明 + Bonjour 服务 + 探针常量在位"
else
  bad "PC44-7 声明增补或探针常量漂移"
fi
# PC44-8 文案键锁：perm.* 48 键五包齐全，且新
# 文件内 Lang.t 引用的每个键五包都在（[9] 的
# 引用键检查只扫 MomentApp.swift，此处补扫新
# 文件；动态拼键 perm.item_/note_/status_ 以
# 前缀全集断言覆盖）。
if python3 - "$LANGDIR" "$PERMF" <<'PYEOF'
import json, re, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
packs = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        packs.append(json.load(f))
perm = [k for k in packs[0] if k.startswith("perm.")]
if len(perm) != 48:
    sys.exit(1)
if any(set(p) != set(packs[0]) for p in packs):
    sys.exit(1)
src = open(sys.argv[2], encoding="utf-8").read()
used = set(re.findall(r'Lang\.t\(\s*"([^"]+)"', src))
sys.exit(0 if all(k in packs[0] for k in used) else 1)
PYEOF
then
  ok "PC44-8 perm.* 48 键五包齐 + 新文件引用键齐全"
else
  bad "PC44-8 perm.* 键缺失或引用键无包"
fi

echo "[45] 深色模式颜色单源（fix_dark_mode_full.md：正文显式前景/令牌归令/裸色字面普查）"
# DM45-1 裸色字面普查（机制锁）：MomentApp 代码行内
# (UIColor|Color)(red: 构造恒 8 行，逐个点名——
# T 工厂 2（memoBg 浅支/rgbOf 的 Color 支 + colorOf）
# 与 T 令牌定义 2（fillHighlightUI/fillAccent18UI）
# 与开屏艺术 4（splashColor 深浅 2 + 开屏底深浅 2）；
# UIColor(red: 恒 3 行（memoBg 浅支 + 两令牌定义）。
# 新增任何裸字面必破计数；改值必破点名子锚。
if [ "$(echo "$CODE" | grep -c 'Color(red:')" = 8 ] \
   && [ "$(echo "$CODE" | grep -c 'UIColor(red:')" = 3 ] \
   && [ "$(echo "$CODE" | grep -c '35.0 / 255')" = 2 ] \
   && [ "$(echo "$CODE" | grep -c '31.0 / 255')" = 2 ]; then
  ok "DM45-1 裸色字面普查 = 白名单 8（工厂 2 / 令牌定义 2 / 开屏艺术 4）"
else
  bad "DM45-1 裸色字面普查漂移（新增字面须先归令或登记白名单）"
fi
# DM45-2 .white 前景归零 + onAccent 归令在位：
# 填充强调面（accent/danger/warning 胶囊）标签色
# 恒走 T.onAccent（MomentApp 5 用点 + Rescue 1 用点）；
# Color.white 全仓只许配对二维码白底板 1 处
# （MomentBridgeSettings，功能要求非装饰）。
# 改判沿革（实况设计批 impl_liveops_design）：
# 扩展目标（MomentLiveOpsWidget）跨进程无 T 令
# 牌，其徽章白字形（着色圆角底上的字形）与二
# 维码白底板同属功能性例外——归零普查排除扩
# 展文件，改为正向锁扩展内恰 1 处（徽章单点），
# 主 App 侧归零口径不变。
if [ "$(grep -h 'foregroundStyle(\.white)' $(ls ./*.swift | grep -v 'MomentLiveOpsWidget.swift') | wc -l | tr -d ' ')" = 0 ] \
   && [ "$(grep -c 'foregroundStyle(\.white)' MomentLiveOpsWidget.swift)" = 1 ] \
   && [ "$(grep -c 'T\.onAccent' "$SRC")" = 5 ] \
   && [ "$(grep -c 'T\.onAccent' "$RESCUE")" = 1 ] \
   && [ "$(grep -c 'Color\.white' "$BSET")" = 1 ]; then
  ok "DM45-2 .white 前景归零（扩展徽章例外 1 处）、onAccent 6 用点、二维码白底板单点"
else
  bad "DM45-2 .white 前景回潮或 onAccent/白底板计数漂移"
fi
# DM45-3 正文显式前景（核心机制）：Marks.attributed
# 与 MdRender.attributed 各带 baseColor 形参（同签
# 名恒 2 处）、普通 run 恒带 .foregroundColor:
# baseColor；BlockTextView.baseColorUI 单点定义且
# reloadContent 把 baseColor 喂进 attributed；
# 表格头把 quoteTextUI 同喂构建器与视图。
if [ "$(grep -c 'baseColor: UIColor = T.textMainUI' "$SRC")" = 2 ] \
   && has '.foregroundColor: baseColor' "$SRC" \
   && has 'static func baseColorUI' "$SRC" \
   && has 'baseColor: baseColor' "$SRC" \
   && has 'baseColor: T.quoteTextUI' "$SRC"; then
  ok "DM45-3 编辑/MD 两构建器显式基准色 + baseColorUI 单点"
else
  bad "DM45-3 正文显式前景机制缺失（深色下正文将恒黑）"
fi
# DM45-4 textColor 死通道退役：reloadContent 不再
# 以 .label 作正文色（该通道不达 attributedText
# 渲染）；textColor 与 typingAttributes 恒由
# baseColor 同喂。
if [ "$(grep -c 'tv\.textColor = \.label' "$SRC")" = 0 ] \
   && has 'tv.textColor = baseColor' "$SRC"; then
  ok "DM45-4 .label 死通道退役、textColor 由 baseColor 同喂"
else
  bad "DM45-4 .label 通道回潮或 textColor 喂点缺失"
fi
# DM45-5 令牌值锁：checkBorder 深值对 Web
# tokens.css:227（#B5B5BB）；新令牌五件定义在位；
# 消费点归令（doneTextUI / linkBlueUI 双用点 /
# termText+termBg 各 2 用点）。
if has 'dyn(0x73737A, 0xB5B5BB)' "$SRC" \
   && has 'static var doneTextUI' "$SRC" \
   && has 'static var codeBgUI' "$SRC" \
   && has 'static var onAccent' "$SRC" \
   && [ "$(grep -c 'T\.termText' "$SRC")" = 2 ] \
   && [ "$(grep -c 'T\.termBg' "$SRC")" = 2 ] \
   && [ "$(grep -c 'value: T.doneTextUI' "$SRC")" = 1 ] \
   && [ "$(echo "$CODE" | grep -c 'T\.linkBlueUI')" = 2 ]; then
  ok "DM45-5 checkBorder 深值归正 + 新令牌定义/消费计数齐"
else
  bad "DM45-5 令牌值或归令消费计数漂移"
fi
# DM45-6 斜杠菜单逐项同面：24 命令恒经 slashRow
# 单点渲染（SlashCmds.all 定义在位、rows 引用在
# 位）；slashRow 段内前景/底恒令牌（accent/
# textMain/textSecondary/fillHover 四锚齐）且无
# 裸 Color( 字面；面板底恒 overlayCard。
SLASHROW=$(awk '/private func slashRow/,/private func linkFormPanel/' "$SRC")
if has 'static let all' "$SRC" \
   && echo "$SLASHROW" | grep -q 'T\.accent' \
   && echo "$SLASHROW" | grep -q 'T\.textMain' \
   && echo "$SLASHROW" | grep -q 'T\.textSecondary' \
   && echo "$SLASHROW" | grep -q 'T\.fillHover' \
   && ! echo "$SLASHROW" | grep -q 'Color(red:' \
   && has '.overlayCard()' "$SRC"; then
  ok "DM45-6 斜杠 24 项单点 slashRow 全令牌 + 面板 overlayCard"
else
  bad "DM45-6 斜杠行令牌锚缺失或裸字面回潮"
fi
# DM45-7 待办勾选令牌双面同源：编辑面与 MD 预览
# 面的未选标记恒同走 T.checkBorder（用点恒 2）。
if [ "$(grep -c 'T\.checkBorder' "$SRC")" = 2 ]; then
  ok "DM45-7 checkBorder 双面同源（编辑 + MD 预览）"
else
  bad "DM45-7 checkBorder 用点漂移"
fi

echo "[46] 文字大小真跟随机制锁（fix_dynamic_type_follow：单源工厂 / 类别 epoch / 语义面收口；[36] 只锁形态、本组锁机制）"
FF46=MomentFontFactory.swift
# DT46-1 字体构造单源：UIFont.systemFont /
# monospacedSystemFont 构造点全集（去注释行）
# = 5——工厂 3（baseFont 双路 + derivedMono）
# + MomentApp 白名单 2（capsuleHeight 未缩放
# 基准，DT36-1 在册：缩放基准本身不可缩放）；
# UIFontMetrics 构造仅工厂 2 处。工厂外新增
# 构造点须先归工厂再改此锁。
SF46=0; UM46=0
for f in *.swift; do
  SF46=$((SF46 + $(grep -v '^[[:space:]]*//' "$f" \
    | grep -c 'UIFont\.systemFont(\|UIFont\.monospacedSystemFont(')))
  UM46=$((UM46 + $(grep -v '^[[:space:]]*//' "$f" \
    | grep -c 'UIFontMetrics(')))
done
SF46F=$(grep -v '^[[:space:]]*//' "$FF46" \
  | grep -c 'UIFont\.systemFont(\|UIFont\.monospacedSystemFont(')
SF46A=$(grep -v '^[[:space:]]*//' "$SRC" \
  | grep -c 'UIFont\.systemFont(\|UIFont\.monospacedSystemFont(')
if [ "$SF46" = 5 ] && [ "$SF46F" = 3 ] \
   && [ "$SF46A" = 2 ] && [ "$UM46" = 2 ]; then
  ok "DT46-1 UIFont 构造单源（全集 5 = 工厂 3 + 白名单 2；UIFontMetrics 仅工厂）"
else
  bad "DT46-1 字体构造点漂移（全集 $SF46 / 工厂 $SF46F / 主 App $SF46A / Metrics $UM46）"
fi
# DT46-2 representable 文本面 adjustsFont 全置
# 真：BlockTextView + MdTextGroupView（主
# App 2）+ TitleTextField（1），逐个点名计数。
if [ "$(grep -c 'adjustsFontForContentSizeCategory = true' "$SRC")" = 2 ] \
   && [ "$(grep -c 'adjustsFontForContentSizeCategory = true' "$TFIELD")" = 1 ]; then
  ok "DT46-2 三个 representable 文本面 adjustsFont 全置真"
else
  bad "DT46-2 adjustsFont 置真点缺失（编辑器/MD/标题字段）"
fi
# DT46-3 类别 epoch 机制在位：FontHub 监听
# didChangeNotification 并递增 epoch；编辑器
# 协调器以 fontEpoch 为失效键、持焦延迟经
# pendingFontRefresh 在失焦时 reloadContent。
if has 'UIContentSizeCategory.didChangeNotification' "$FF46" \
   && has 'epoch += 1' "$FF46" \
   && has 'var fontEpoch = -1' "$SRC" \
   && has 'pendingFontRefresh = true' "$SRC" \
   && has 'parent.reloadContent(tv)' "$SRC" \
   && has 'func reloadContent' "$SRC"; then
  ok "DT46-3 FontHub epoch 发布 + 编辑器 epoch 失效键 + 失焦补刷在位"
else
  bad "DT46-3 类别变更传播机制缺失"
fi
# DT46-4 语义字体零残留：四文件（主 App / 桥
# 设置 / 救援 / 权限）代码行内 .font(.样式 与
# .font(.system(.样式 两式恒 0——语义样式通道
# 已被真机推翻，全量改走 @ScaledMetric 喂点。
SEM46=0
for f in "$SRC" "$BSET" "$RESCUE" "$PERMF"; do
  SEM46=$((SEM46 + $(grep -v '^[[:space:]]*//' "$f" \
    | grep -cE '\.font\([[:space:]]*\.(caption2|caption|footnote|subheadline|callout|body|headline|title3|title2|title|largeTitle)\b|\.font\([[:space:]]*\.system\([[:space:]]*\.(caption2|caption|footnote|subheadline|callout|body|headline|title3|title2|title|largeTitle)\b')))
done
if [ "$SEM46" = 0 ]; then
  ok "DT46-4 四文件语义字体零残留（全走 ScaledMetric 喂点）"
else
  bad "DT46-4 语义字体残留 $SEM46 处（须改走喂点）"
fi
# DT46-5 字形封顶总计数锁（补 DT36-2 分项
# 锁）：min(f<度量>, <槽宽>) 形态全集恒 9，
# 新封顶位点不得静默新增——须先在报告给数
# （哪一档起封顶）并同步 DT36-2 分项。
if [ "$(grep -o 'min(f[0-9]*, [0-9]*)' "$SRC" | wc -l | tr -d ' ')" = 9 ]; then
  ok "DT46-5 字形封顶位点全集 9（与 DT36-2 分项守恒）"
else
  bad "DT46-5 封顶位点总数漂移（现 $(grep -o 'min(f[0-9]*, [0-9]*)' "$SRC" | wc -l | tr -d ' ') 处）"
fi
# DT46-6 SwiftUI 侧重演算触发三点 + 工厂接
# 线：EditorView / EditorHeaderView /
# MdBlockView 各观察 FontHub（类别变更即整树
# 重演算）；build-app2.sh 各遍名单 + primary
# 遍登记工厂文件（原 22 处；E2 撤销体系新增
# undo primary 遍后 23 处；F-09 一期新增
# xsel/xsel_bridge 两 primary 遍后 25 处；状
# 态栏采样批新增 statusbar/statusbar_bridge
# 两 primary 遍后 27 处；图片加载键控批新增
# imageload primary 遍后 28 处；状态栏二轮批
# 新增 statusbar_image/splash_host 两 primary
# 遍后 30 处——均期望合法变更，沿革见
# impl_editor_undo_e2.md /
# impl_cross_block_selection_p1.md /
# fix_statusbar_sampling.md /
# fix_image_card_load.md /
# fix_statusbar_dynamic.md）；状态栏回退批
# 整遍拆除渲染采样器 primary 遍后 29 处
# （fix_statusbar_rollback_all.md 沿革，同口
# 径）；其后快照恢复批增 bridge_restore
# primary 遍至 30；采样去除批整遍拆除采样
# 两文件 primary 遍后 28（remove_statusbar_
# sampling 沿革）；Marks.dynFont 委托工厂
# uiFont。
if [ "$(grep -c '@ObservedObject private var fontHub = FontHub.shared' "$SRC")" = 3 ] \
   && [ "$(grep -c 'MomentFontFactory.swift' build-app2.sh)" = 28 ] \
   && has 'FontFactory.uiFont(' "$SRC"; then
  ok "DT46-6 FontHub 观察三点 + 工厂构建接线 28 + dynFont 委托在位"
else
  bad "DT46-6 观察点/构建接线/dynFont 委托缺失"
fi

echo "[47] 撤销体系机制锁（E2 impl_editor_undo_e2：漏斗单点 / 爆发合并·去重·钳制 / 选区恢复 / 快捷面单轨）"
# E47-1 漏斗单点普查（F-12）：undo()/redo()
# 定义各一（EditorModel 漏斗本体）；入口全集
# 逐点点名——成员调用 .undo()/.redo() 各 3 =
# ••• 菜单行、EditorTextView 三指手势
# （navEditor）、标题字段闭包（editor.）；裸
# 调用 undo() 1 = handleKey 的 Cmd+Z，redo()
# 2 = Cmd+Shift+Z 与 Cmd+Y。任何新入口（第
# 二撤销实现/旁路直调栈）都会打破计数。
if [ "$(grep -c 'func undo()' "$SRC")" = 1 ] \
   && [ "$(grep -c 'func redo()' "$SRC")" = 1 ] \
   && [ "$(grep -o '\.undo()' "$SRC" | wc -l | tr -d ' ')" = 3 ] \
   && [ "$(grep -o '\.redo()' "$SRC" | wc -l | tr -d ' ')" = 3 ] \
   && [ "$(grep -cE '^[[:space:]]+undo\(\)$' "$SRC")" = 1 ] \
   && [ "$(grep -cE '^[[:space:]]+redo\(\)$' "$SRC")" = 2 ]; then
  ok "E47-1 撤销漏斗单点：定义各 1 + 入口全集（成员 3+3 / 裸 1+2）守恒"
else
  bad "E47-1 漏斗入口全集漂移（定义 undo=$(grep -c 'func undo()' "$SRC") redo=$(grep -c 'func redo()' "$SRC") 成员 undo=$(grep -o '\.undo()' "$SRC" | wc -l | tr -d ' ') redo=$(grep -o '\.redo()' "$SRC" | wc -l | tr -d ' ') 裸 undo=$(grep -cE '^[[:space:]]+undo\(\)$' "$SRC") redo=$(grep -cE '^[[:space:]]+redo\(\)$' "$SRC")）"
fi
# E47-2 核心在位 + 旧栈零残留（F-10）：模型
# 只持一台 UndoHistoryCore；旧两裸数组与上
# 限 50 字面清零；合并窗 0.6 与上限 100 常量
# 在核心文件单点声明。
if [ -f "$UNDO" ] \
   && [ "$(grep -c 'UndoHistoryCore<' "$SRC")" = 1 ] \
   && [ "$(grep -c 'private var undoStack' "$SRC")" = 0 ] \
   && [ "$(grep -c 'undoStack.count > 50' "$SRC")" = 0 ] \
   && has 'undoBurstWindow: Double = 0.6' "$UNDO" \
   && has 'undoStackCap = 100' "$UNDO"; then
  ok "E47-2 UndoHistoryCore 单点持有 + 旧栈/上限 50 零残留 + 常量 0.6/100 在位"
else
  bad "E47-2 撤销核心在位/旧栈残留/常量缺失"
fi
# E47-3 核心行为表驱动：MomentUndo.swift 与
# 内嵌断言体一起以宿主 swiftc 编译运行——爆
# 发合并（一段键入一撤回整段）、幻影去重、
# 101 步钳制（栈 100 + 最旧出栈）、选区往
# 返、新编辑清重做尾、结构记录断链、选区替
# 换断链（EDT-14 步 5 复刻），任一不符即红
# （断言体与 impl_editor_undo_e2.md 规则表同
# 源；替换断链口径见 fix_undo_step5_selection
# .md）。
E47D=$(mktemp -d)
cat > "$E47D/main.swift" <<'UNDOEOF'
// E2 撤销核心行为表驱动（verify [47] E47-3）。
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}

// 爆发合并 + 撤销链
var h = UndoHistoryCore<String>()
var r = h.recordOpBoundary(payload: "S0", key: "S0",
                           sel: UndoSel(blockId: "b1",
                                        location: 0,
                                        length: 0))
check(r == .pushed && h.undoDepth == 1, "anchor pushed")
r = h.noteTextWillChange(entry: { ("S0", "S0") },
                         sel: nil, now: 100.0)
check(r == .deduped && h.undoDepth == 1, "burst start dedup")
r = h.noteTextWillChange(entry: { ("S1", "S1") },
                         sel: nil, now: 100.3)
check(r == .withinBurst && h.undoDepth == 1, "burst merge 1")
r = h.noteTextWillChange(entry: { ("S2", "S2") },
                         sel: nil, now: 100.5)
check(r == .withinBurst && h.mergedCount == 2,
      "burst merge 2")
r = h.noteTextWillChange(entry: { ("S3", "S3") },
                         sel: nil, now: 101.2)
check(r == .pushed && h.undoDepth == 2, "burst next step")
var t = h.performUndo(currentPayload: "S4",
                      currentKey: "S4", currentSel: nil)
check(t?.payload == "S3" && h.canRedo, "undo to S3")
t = h.performUndo(currentPayload: "S3",
                  currentKey: "S3", currentSel: nil)
check(t?.payload == "S0", "undo to S0 one-shot")
t = h.performUndo(currentPayload: "S0",
                  currentKey: "S0", currentSel: nil)
check(t == nil, "undo empty nil")

// 去重幻影：两次同态边界记录只入一
var h2 = UndoHistoryCore<String>()
_ = h2.recordOpBoundary(payload: "A", key: "A",
                        sel: nil)
let r2 = h2.recordOpBoundary(payload: "A", key: "A",
                              sel: nil)
check(r2 == .deduped && h2.undoDepth == 1
      && h2.dedupedCount == 1, "phantom dedup")

// 上限钳制：101 个相异返回点 → 栈 100、最旧出栈
var h3 = UndoHistoryCore<String>()
for i in 0...100 {
    _ = h3.recordOpBoundary(payload: "k\(i)",
                            key: "k\(i)", sel: nil)
}
check(h3.undoDepth == 100 && h3.clampedCount == 1,
      "clamp depth")
let top3 = h3.performUndo(currentPayload: "now",
                          currentKey: "now",
                          currentSel: nil)
check(top3?.payload == "k100", "clamp top newest")
var last: UndoEntry<String>?
while let e = h3.performUndo(
    currentPayload: "x",
    currentKey: "x\(h3.undoDepth)",
    currentSel: nil) {
    last = e
}
check(last?.payload == "k1", "clamp oldest evicted k0")

// 选区往返：条目附选区经撤销保全、重做带回
var h4 = UndoHistoryCore<String>()
let sel = UndoSel(blockId: "b1", location: 3,
                  length: 2)
_ = h4.recordOpBoundary(payload: "P0", key: "P0",
                        sel: sel)
let u4 = h4.performUndo(currentPayload: "P1",
                        currentKey: "P1",
                        currentSel: UndoSel(
                            blockId: "b1", location: 5,
                            length: 0))
check(u4?.sel == sel, "undo restores sel")
let r4 = h4.performRedo(currentPayload: "P0",
                        currentKey: "P0",
                        currentSel: u4?.sel)
check(r4?.payload == "P1"
      && r4?.sel?.location == 5, "redo returns sel")

// 新编辑清重做尾
var h5 = UndoHistoryCore<String>()
_ = h5.recordOpBoundary(payload: "A", key: "A",
                        sel: nil)
_ = h5.performUndo(currentPayload: "B",
                   currentKey: "B", currentSel: nil)
check(h5.canRedo, "redo armed")
_ = h5.noteTextWillChange(entry: { ("A", "A") },
                          sel: nil, now: 10.0)
check(!h5.canRedo, "new edit clears redo")

// 断链：结构记录后文本馈入不得命中合并窗
var h6 = UndoHistoryCore<String>()
_ = h6.noteTextWillChange(entry: { ("A", "A") },
                          sel: nil, now: 50.0)
_ = h6.recordOpBoundary(payload: "B", key: "B",
                        sel: nil)
let r6 = h6.noteTextWillChange(entry: { ("C", "C") },
                               sel: nil,
                               now: 50.2)
check(r6 == .pushed && h6.mergedCount == 0,
      "op boundary breaks chain")

// 选区替换断链（EDT-14 步 5 复刻，fix_undo_
// step5_selection.md）：锚→爆发→撤→重做→再
// 撤→续键起链，窗内非空替换恒起新返回点、
// 续键并入替换步、一撤恰回替换前态且条目
// 选区 = 被替换范围（旧行为：替换被爆发链
// 吞并、一撤多退一层、选区落爆发锚点）。
var h7 = UndoHistoryCore<String>()
let selA = UndoSel(blockId: "b", location: 5,
                   length: 0)
let selR = UndoSel(blockId: "b", location: 1,
                   length: 2)
_ = h7.recordOpBoundary(payload: "B", key: "B",
                        sel: selA)
_ = h7.noteTextWillChange(entry: { ("B", "B") },
                          sel: selA, now: 200.0)
_ = h7.noteTextWillChange(entry: { ("Bx", "Bx") },
                          sel: nil, now: 200.2)
var t7 = h7.performUndo(currentPayload: "B1",
                        currentKey: "B1",
                        currentSel: nil)
check(t7?.payload == "B", "h7 undo burst")
t7 = h7.performRedo(currentPayload: "B",
                    currentKey: "B",
                    currentSel: selA)
check(t7?.payload == "B1", "h7 redo burst")
t7 = h7.performUndo(currentPayload: "B1",
                    currentKey: "B1",
                    currentSel: nil)
check(t7?.payload == "B", "h7 undo again")
let rj = h7.noteTextWillChange(
    entry: { ("B", "B") }, sel: selA, now: 201.0)
check(rj == .pushed && !h7.canRedo
      && h7.undoDepth == 1,
      "h7 append restarts chain, clears redo")
let rr = h7.noteTextWillChange(
    entry: { ("B2", "B2") }, sel: selR,
    now: 201.3, breaksBurst: true)
check(rr == .pushed && h7.undoDepth == 2,
      "h7 replace breaks burst in window")
let ra = h7.noteTextWillChange(
    entry: { ("B3", "B3") }, sel: nil, now: 201.5)
check(ra == .withinBurst && h7.undoDepth == 2,
      "h7 next key merges into replace step")
t7 = h7.performUndo(currentPayload: "B3",
                    currentKey: "B3",
                    currentSel: nil)
check(t7?.payload == "B2" && t7?.sel == selR,
      "h7 one undo = pre-replace + replaced sel")

// 对照：零长插入（breaksBurst=false）窗内仍
// 合并，纯插入口径不因替换断链而变。
var h8 = UndoHistoryCore<String>()
_ = h8.noteTextWillChange(entry: { ("B", "B") },
                          sel: selA, now: 300.0)
let r8 = h8.noteTextWillChange(
    entry: { ("B2", "B2") }, sel: nil, now: 300.3)
check(r8 == .withinBurst && h8.undoDepth == 1,
      "h8 plain insert still merges")

if failures == 0 {
    print("UNDO_CORE_PASS")
} else {
    print("UNDO_CORE_FAIL \(failures)")
    exit(1)
}
UNDOEOF
SWIFTC47=""
for c47 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c47" ] && [ -x "$c47" ]; then
    SWIFTC47="$c47"; break
  fi
done
if [ -n "$SWIFTC47" ] \
   && "$SWIFTC47" -O -o "$E47D/undo_test" \
        "$UNDO" "$E47D/main.swift" 2>"$E47D/err.log" \
   && [ "$("$E47D/undo_test" 2>/dev/null)" = "UNDO_CORE_PASS" ]; then
  ok "E47-3 核心行为表驱动全过（合并/去重/钳制/选区往返/断链/替换断链）"
else
  bad "E47-3 核心行为表驱动失败（swiftc=$SWIFTC47，详见编译/运行输出）"
  sed 's/^/    E47-3: /' "$E47D/err.log" | head -5
  "$E47D/undo_test" 2>/dev/null | sed 's/^/    E47-3: /' | head -5
fi
rm -rf "$E47D"
# E47-4 选区恢复接线（F-11）：restoreSelection
# 单点 + 待投递选区长度字段与消费面在位 +
# 文本单元查找（顶层块/列表项）与兜底落点。
if [ "$(grep -c 'func restoreSelection' "$SRC")" = 1 ] \
   && [ "$(grep -c 'var pendingSelectionLength' "$SRC")" = 1 ] \
   && has 'private func textUnit' "$SRC" \
   && has 'private func firstTextUnit' "$SRC" \
   && [ "$(grep -c 'ed.pendingSelectionLength = 0' "$SRC")" = 2 ]; then
  ok "E47-4 选区恢复单点 + 选区长度投递/消费两支 + 单元查找/兜底在位"
else
  bad "E47-4 选区恢复接线缺失"
fi
# E47-5 快捷面单轨接线（F-12）：正文与标题
# 两视图 undoManager 钉 nil 各一；三指手势
# 两枚（左滑撤销/右滑重做）；Cmd+Z 拦截在
# 正文 handleKey 与标题 TitleField 两处；
# 标题回调 onUndoKey 定义与接线在位。
if [ "$(grep -c 'override var undoManager' "$SRC")" = 1 ] \
   && [ "$(grep -c 'override var undoManager' "$TFIELD")" = 1 ] \
   && [ "$(grep -c 'numberOfTouchesRequired = 3' "$SRC")" = 2 ] \
   && has '.keyboardZ' "$SRC" \
   && has '.keyboardZ' "$TFIELD" \
   && has 'var onUndoKey' "$TFIELD" \
   && has 'onUndoKey:' "$SRC"; then
  ok "E47-5 单轨接线：undoManager 钉 nil ×2 + 三指手势 ×2 + Cmd+Z 两面 + 标题回调"
else
  bad "E47-5 快捷面单轨接线缺失"
fi
# E47-6 检查点接线（F-10 馈入面）：feedUndo-
# Checkpoint 定义 1 + 调用 3（代码块换行/
# Shift+Enter 软换行/末尾兜底——普通文本放
# 行点全集）；模型与核心的 noteTextWillChange
# 各一（馈入单点对接）。
if [ "$(grep -c 'feedUndoCheckpoint(' "$SRC")" = 4 ] \
   && [ "$(grep -c 'func noteTextWillChange' "$SRC")" = 1 ] \
   && [ "$(grep -c 'func noteTextWillChange' "$UNDO")" = 1 ]; then
  ok "E47-6 撤销检查点：放行点全集 3 调用 + 馈入单点（模型/核心各一）"
else
  bad "E47-6 检查点接线漂移（feedUndoCheckpoint=$(grep -c 'feedUndoCheckpoint(' "$SRC")）"
fi
# E47-7 Diag 结果量：去重/钳制事件行 + undo/
# redo 行携合并/去重累计计数（两行）。0.9.62
# 沿革（AUD-E-05①）：dedup/clamp 事件行原由
# EditorModel 代记（「EDIT undo dedup skip」/
# 「EDIT undo clamp」两支）已删、收敛为引擎
# 本体 eventSink 自记 + init 单点承接行
# 「EDIT undo core 」恰 1（事件字面在核心侧
# 由 [54] AU54-2/3 锁）；本断言随之改锁承
# 接行 + 累计计数两行。
if [ "$(grep -c 'EDIT undo core ' "$SRC")" = 1 ] \
   && [ "$(grep -c 'merged=\\(history.mergedCount)' "$SRC")" = 2 ]; then
  ok "E47-7 Diag 结果量在位（引擎事件承接行 + undo/redo 累计计数）"
else
  bad "E47-7 Diag 结果量缺失"
fi
# E47-8 构建接线（仿 PC44-1）：MomentUndo.swift
# 在 build-app2.sh 全遍登记（24 处 = 各遍输
# 入 + primary 遍）且 undo.o 恰 2 处（自有
# primary 遍产出 + 主链接行）。F-09 一期新增
# xsel/xsel_bridge 两 primary 遍后登记数 26；
# 状态栏采样批再增 statusbar/statusbar_
# bridge 两 primary 遍后 28；图片加载键控批
# 再增 imageload primary 遍后 29；状态栏二轮
# 批再增 statusbar_image/splash_host 两
# primary 遍后 31——均期望合法变更
# （impl_cross_block_selection_p1.md /
# fix_statusbar_sampling.md /
# fix_image_card_load.md /
# fix_statusbar_dynamic.md 沿革，同 DT46-6
# 口径）；状态栏回退批整遍拆除渲染采样器
# primary 遍后 30（fix_statusbar_rollback_
# all.md 沿革）；其后快照恢复批增 bridge_
# restore primary 遍至 31；采样去除批整遍
# 拆除采样两文件 primary 遍后 29（remove_
# statusbar_sampling 沿革）。
if [ "$(grep -c 'MomentUndo.swift' build-app2.sh)" = 29 ] \
   && [ "$(grep -c 'undo.o' build-app2.sh)" = 2 ]; then
  ok "E47-8 MomentUndo 构建接线 29 + undo.o ×2"
else
  bad "E47-8 构建接线漂移（MomentUndo.swift=$(grep -c 'MomentUndo.swift' build-app2.sh) undo.o=$(grep -c 'undo.o' build-app2.sh)）"
fi
# E47-9 选区替换断链接线（EDT-14 步 5 根治，
# fix_undo_step5_selection.md）：核心 noteText-
# WillChange 携 breaksBurst 形参（注释/声明/
# 合并窗守卫共 3 处），模型馈入面按被替换范
# 围非空传参恰 1——替换恒起新返回点的两端接
# 线在位（行为本体由 E47-3 的 h7/h8 用例锁）。
if [ "$(grep -c 'breaksBurst' "$UNDO")" = 3 ] \
   && [ "$(grep -c 'breaksBurst: range.length > 0' "$SRC")" = 1 ]; then
  ok "E47-9 替换断链接线：核心形参/守卫 + 模型按非空范围传参"
else
  bad "E47-9 替换断链接线漂移（UNDO breaksBurst=$(grep -c 'breaksBurst' "$UNDO") SRC传参=$(grep -c 'breaksBurst: range.length > 0' "$SRC")）"
fi

echo "[48] U4b 撤销回路场景（EDT-14 undo_redo_roundtrip，定案 impl_uitest_u4b.md / 矩阵 EDT-14）"
# U4b-1 场景注册全集：目录含 undo_redo_roundtrip
# 且八景名全在位（S1 + U4a 六景 + 本景），场景
# 本体枚举在位。
u4bok=1
for s in 'undo_redo_roundtrip' 'UITestScenarioUndoRedo' \
         'title_capsule_reedit' 'title_capsule_reedit_compact' \
         'title_caret_assert' 'title_commit_escape' \
         'done_capsule_cycle' 'slash_menu_flow' \
         'block_type_matrix'; do
  echo "$ucode" | grep -q "$s" || u4bok=0
done
if [ "$u4bok" = 1 ]; then
  ok "U4b-1 场景注册全集（八景，undo_redo_roundtrip 在位）"
else
  bad "U4b-1 场景注册缺名"
fi
# U4b-2 被测面接线：场景经漏斗与检查点喂入
# （undo()/redo() 直调漏斗、noteTextWillChange
# 检查点、toggleTodoChecked 压栈源），不另造
# 第二历史。
if echo "$ucode" | grep -q 'ed.undo()' \
   && echo "$ucode" | grep -q 'ed.redo()' \
   && echo "$ucode" | grep -q 'noteTextWillChange(' \
   && echo "$ucode" | grep -q 'toggleTodoChecked(todo)'; then
  ok "U4b-2 场景被测面 = E2 漏斗 + 检查点（无第二历史）"
else
  bad "U4b-2 场景未接漏斗/检查点"
fi
# U4b-3 断言锚：六面判据字面在位（合并计数/
# focus 回读串/去重行/钳制深/余栈步行/单消费
# 计数）。
u4bok=1
for s in 'burst_merged_4' 'focus_restored_sel' \
         'EDIT undo core dedup' 'depth=100' \
         'EDIT undo 余栈' 'single_undo_one_line'; do
  echo "$ucode" | grep -q "$s" || u4bok=0
done
if [ "$u4bok" = 1 ]; then
  ok "U4b-3 六面断言锚在位（合并/选区/幻影/钳制/步行/单消费）"
else
  bad "U4b-3 断言锚缺失"
fi
# U4b-4 矩阵对应：EDT-14 行已回写 undo_redo_
# roundtrip 已覆盖（矩阵维护纪律：场景增删先
# 改矩阵）。
MATRIX=../../../../docs/reports/plan_selftest_coverage.md
if grep 'EDT-14' "$MATRIX" | grep -q 'undo_redo_roundtrip' \
   && grep 'EDT-14' "$MATRIX" | grep -q '已覆盖'; then
  ok "U4b-4 矩阵 EDT-14 行与场景对应（已覆盖回写）"
else
  bad "U4b-4 矩阵 EDT-14 行未回写"
fi

echo "[49] 签名面 AMFI 门（fix_install_signing_0958：0.9.58 起 macho-entitle 嵌坏签名面——LC 页哈希失效 + 签名区溢出 __LINKEDIT——而旧 verify 只回读 slot-5 自写值全程绿灯；本组锁根治三件）"
ENTOOL="$HOME/workspace/ios-tools/macho_entitle.py"
# tree 侧无 workspace 检出：回退部署态工具（同一脚本、
# 组版前已同步新版并对账哈希，见 release_0.9.60）。
[ -f "$ENTOOL" ] || ENTOOL="$HOME/ios-native/bin/macho-entitle"
# SG49-1 工具面：validate 全量校验存在、embed 收尾
# 自调 validate、__LINKEDIT 同步逻辑在位。
if [ -f "$ENTOOL" ] \
   && grep -q "def validate" "$ENTOOL" \
   && grep -q "validate(path, info_path)" "$ENTOOL" \
   && grep -q "find_linkedit" "$ENTOOL" \
   && grep -q "not inside __LINKEDIT" "$ENTOOL"; then
  ok "SG49-1 macho-entitle validate 在位且 embed 自调（AMFI 口径非自读）"
else
  bad "SG49-1 macho-entitle validate/embed 自调缺失"
fi
# SG49-2 构建双门：主程序与 appex 在 entitle 后各有
# 一道显式 validate 硬门（set -e 中断构建）。改判
# 沿革（0.9.61 装机根治）：计数口径不变（脚本内
# 调用点恰两处），但 appex 一道自本版起位于
# BUNDLE_WIDGET_EXT 门控块内、仅开关置 1 时执行
# （交付包不含 appex，见 [52]）；主程序一道恒执行。
nvg=$(grep -c '"$ENTITLE" validate' "$SH")
if [ "$nvg" = 2 ]; then
  ok "SG49-2 build-app2.sh validate 硬门恰两处（主程序恒行 + appex 门控内）"
else
  bad "SG49-2 validate 硬门数 = $nvg（应为 2）"
fi
# SG49-3 appex 版本单源同步：拷入后以主程序
# Info.plist 回写两键的步骤在位（静态 plist 版本
# 冻结脱钩的根治）。改判沿革（0.9.61）：该步骤
# 随 appex 拷入块一并受 BUNDLE_WIDGET_EXT 门控，
# 仅开关置 1 时执行；本条锁步骤在位、口径不变。
if grep -q "appex_plist" "$SH" \
   && grep -q "plistlib" "$SH"; then
  ok "SG49-3 appex 版本同步步骤在位（主程序 Info.plist 单源；随捆绑开关门控）"
else
  bad "SG49-3 appex 版本同步步骤缺失"
fi

echo "[50] 跨块选区一期（F-09 桥接层，定案 plan_cross_block_selection §8.1 / impl_cross_block_selection_p1.md）"
# X50-1 桥接层单点：纯核心符号全集 + 桥接层入
# 口全集 + 模型选区状态恰一处声明（无第二选区
# 模型）。
x50ok=1
for s in 'struct XSel:' 'enum XSelCore' \
         'static func splitRuns' \
         'static func guardSpan' \
         'static func plainResultColumns' \
         'static func k5SegmentColumns' \
         'static func selectedText' \
         'static func ordered'; do
  grep -q -- "$s" "$XSEL" || x50ok=0
done
for s in 'func setXSel' 'func selectAllXSel' \
         'func replaceXSel' 'func replaceRangeUnits' \
         'func collapseXSel' \
         'func noteXSelNativeSelection' \
         'func xselRowCovered'; do
  grep -q -- "$s" "$XSELB" || x50ok=0
done
[ "$(grep -c '@Published var xsel' "$SRC")" = 1 ] \
  || x50ok=0
if [ "$x50ok" = 1 ]; then
  ok "X50-1 桥接层单点（核心 8 符号 + 桥接 7 入口 + xsel 状态恰 1）"
else
  bad "X50-1 桥接层符号/状态漂移"
fi
# X50-2 核心行为表驱动：MomentXSel.swift 与内
# 嵌断言体以宿主 swiftc 编译运行——行内劈分
# （含代理对对齐）/端点排序/源码禁区钳制/选区
# 文本/双路径结果列，任一不符即红（断言体与
# ops.rs 语义同源；沿 E47-3 先例）。
X50D=$(mktemp -d)
cat > "$X50D/main.swift" <<'XSELEOF'
// F-09 一期 XSelCore 行为表驱动（verify [50] X50-2）。
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}

func R(_ t: String, bold: Bool = false) -> [String: Any] {
    var d: [String: Any] = ["text": t]
    if bold { d["bold"] = true }
    return d
}
func texts(_ runs: [[String: Any]]) -> [String] {
    runs.map { $0["text"] as? String ?? "?" }
}

// ── splitRuns ──
var sp = XSelCore.splitRuns([R("hello "), R("world")],
                            atUTF16: 6)
check(texts(sp.head) == ["hello "]
      && texts(sp.tail) == ["world"], "split boundary")
sp = XSelCore.splitRuns([R("hello "), R("world", bold: true)],
                        atUTF16: 8)
check(texts(sp.head) == ["hello ", "wo"]
      && texts(sp.tail) == ["rld"], "split mid-run")
check((sp.tail[0]["bold"] as? Bool) == true,
      "split keeps marks on tail half")
check((sp.head[1]["bold"] as? Bool) == true,
      "split keeps marks on head half")
sp = XSelCore.splitRuns([R("abc")], atUTF16: 0)
check(sp.head.isEmpty && texts(sp.tail) == ["abc"],
      "split at 0")
sp = XSelCore.splitRuns([R("abc")], atUTF16: 3)
check(texts(sp.head) == ["abc"] && sp.tail.isEmpty,
      "split at end")
// 代理对：a(1) 😀(2) b(1)；偏移 2 落在 😀 内部 →
// 进到其后（head 含 😀），与 Web utf16_byte_index
// 的标量对齐口径一致。
sp = XSelCore.splitRuns([R("a😀b")], atUTF16: 2)
check(texts(sp.head) == ["a😀"] && texts(sp.tail) == ["b"],
      "split surrogate snaps forward")
sp = XSelCore.splitRuns([R("a😀b")], atUTF16: 1)
check(texts(sp.head) == ["a"] && texts(sp.tail) == ["😀b"],
      "split before surrogate")

// ── ordered ──
let sel1 = XSel(anchorId: "c", anchorOff: 3,
                focusId: "a", focusOff: 2,
                fromStart: false, toEnd: false)
let ord1 = XSelCore.ordered(sel1, unitIds: ["a", "b", "c"])
check(ord1?.s.id == "a" && ord1?.s.off == 2
      && ord1?.e.id == "c" && ord1?.e.off == 3
      && ord1?.sIdx == 0 && ord1?.eIdx == 2,
      "ordered swaps reversed endpoints")
check(XSelCore.ordered(sel1, unitIds: ["a", "b"]) == nil,
      "ordered missing endpoint nil")
let selSame = XSel(anchorId: "a", anchorOff: 5,
                   focusId: "a", focusOff: 2,
                   fromStart: false, toEnd: false)
let ordSame = XSelCore.ordered(selSame, unitIds: ["a"])
check(ordSame?.s.off == 2 && ordSame?.e.off == 5,
      "ordered same unit by offset")

// ── guardSpan ──
let gu: [XSelUnitInfo] = [
    XSelUnitInfo(id: "p1", isSource: false, utf16Length: 4),
    XSelUnitInfo(id: "code", isSource: true, utf16Length: 9),
    XSelUnitInfo(id: "p2", isSource: false, utf16Length: 6),
]
var g = XSelCore.guardSpan(
    anchor: XSelPos(id: "p1", off: 1),
    focus: XSelPos(id: "p2", off: 3), units: gu)
check(g.id == "p1" && g.off == 4,
      "guardSpan forward clamps to prev tail")
g = XSelCore.guardSpan(
    anchor: XSelPos(id: "p2", off: 1),
    focus: XSelPos(id: "p1", off: 2), units: gu)
check(g.id == "p2" && g.off == 0,
      "guardSpan backward clamps to anchor-side edge")
g = XSelCore.guardSpan(
    anchor: XSelPos(id: "p1", off: 1),
    focus: XSelPos(id: "p1", off: 3), units: gu)
check(g.id == "p1" && g.off == 3,
      "guardSpan same unit untouched")
let gu2: [XSelUnitInfo] = [
    XSelUnitInfo(id: "p1", isSource: false, utf16Length: 4),
    XSelUnitInfo(id: "p2", isSource: false, utf16Length: 6),
]
g = XSelCore.guardSpan(
    anchor: XSelPos(id: "p1", off: 0),
    focus: XSelPos(id: "p2", off: 6), units: gu2)
check(g.id == "p2" && g.off == 6,
      "guardSpan no source passes")

// ── selectedText ──
let tunits: [(id: String, text: String)] = [
    (id: "a", text: "hello"), (id: "b", text: "mid"),
    (id: "c", text: "world!"),
]
let selT = XSel(anchorId: "a", anchorOff: 2,
                focusId: "c", focusOff: 3,
                fromStart: false, toEnd: false)
check(XSelCore.selectedText(selT, units: tunits)
        == "llo\n\nmid\n\nwor", "selectedText slices+joins")
let selT2 = XSel(anchorId: "c", anchorOff: 3,
                 focusId: "a", focusOff: 2,
                 fromStart: false, toEnd: false)
check(XSelCore.selectedText(selT2, units: tunits)
        == "llo\n\nmid\n\nwor", "selectedText reversed same")

// ── plainResultColumns ──
var pr = XSelCore.plainResultColumns(
    head: [R("ab")], tail: [R("yz")], text: "X",
    enter: false)
check(pr.cols.count == 1
      && texts(pr.cols[0]) == ["ab", "X", "yz"]
      && pr.caretCol == 0 && pr.caretOff == 3,
      "plain single line merges tail")
pr = XSelCore.plainResultColumns(
    head: [R("ab")], tail: [R("yz")], text: "X\nY",
    enter: false)
check(pr.cols.count == 2
      && texts(pr.cols[0]) == ["ab", "X"]
      && texts(pr.cols[1]) == ["Y", "yz"]
      && pr.caretCol == 1 && pr.caretOff == 1,
      "plain two lines tail in last col")
pr = XSelCore.plainResultColumns(
    head: [R("ab")], tail: [R("yz")], text: "X\n\nZ",
    enter: false)
check(pr.cols.count == 3 && pr.cols[1].isEmpty
      && texts(pr.cols[2]) == ["Z", "yz"]
      && pr.caretCol == 2 && pr.caretOff == 1,
      "plain empty middle line is empty col")
pr = XSelCore.plainResultColumns(
    head: [R("ab")], tail: [R("yz")], text: "",
    enter: true)
check(pr.cols.count == 2
      && texts(pr.cols[0]) == ["ab"]
      && texts(pr.cols[1]) == ["yz"]
      && pr.caretCol == 1 && pr.caretOff == 0,
      "plain enter head/tail two cols")
pr = XSelCore.plainResultColumns(
    head: [R("ab")], tail: [R("yz")], text: "",
    enter: false)
check(pr.cols.count == 1
      && texts(pr.cols[0]) == ["ab", "yz"]
      && pr.caretOff == 2, "plain delete joins head+tail")

// ── k5SegmentColumns ──
var k5 = XSelCore.k5SegmentColumns(
    head: [R("ab")], tail: [R("yz")], text: "X\nY",
    enter: false)
check(k5.segCols.count == 2
      && texts(k5.segCols[0]) == ["ab", "X"]
      && texts(k5.segCols[1]) == ["Y"]
      && k5.tailCol != nil
      && texts(k5.tailCol!) == ["yz"]
      && !k5.caretInTail && k5.caretCol == 1
      && k5.caretOff == 1,
      "k5 tail stays separate block")
k5 = XSelCore.k5SegmentColumns(
    head: [R("ab")], tail: [], text: "X", enter: false)
check(k5.tailCol == nil && k5.segCols.count == 1
      && k5.caretCol == 0 && k5.caretOff == 3,
      "k5 empty tail no block (select-all delete)")
k5 = XSelCore.k5SegmentColumns(
    head: [R("ab")], tail: [R("yz")], text: "",
    enter: true)
check(k5.segCols.count == 1 && k5.caretInTail
      && k5.tailCol != nil
      && texts(k5.tailCol!) == ["yz"],
      "k5 enter tail carried by end segment")

if failures == 0 {
    print("XSEL_CORE_PASS")
} else {
    print("XSEL_CORE_FAIL \(failures)")
    exit(1)
}
XSELEOF
SWIFTC50=""
for c50 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c50" ] && [ -x "$c50" ]; then
    SWIFTC50="$c50"; break
  fi
done
if [ -n "$SWIFTC50" ] \
   && "$SWIFTC50" -O -o "$X50D/xsel_test" \
        "$XSEL" "$X50D/main.swift" 2>"$X50D/err.log" \
   && [ "$("$X50D/xsel_test" 2>/dev/null)" = "XSEL_CORE_PASS" ]; then
  ok "X50-2 核心行为表驱动全过（劈分/排序/钳制/选区文本/双路径结果列）"
else
  bad "X50-2 核心行为表驱动失败（swiftc=$SWIFTC50，详见编译/运行输出）"
  sed 's/^/    X50-2: /' "$X50D/err.log" | head -5
  "$X50D/xsel_test" 2>/dev/null | sed 's/^/    X50-2: /' | head -5
fi
rm -rf "$X50D"
# X50-3 动作面接线全集：Cmd+A/C/X 与菜单覆写
# （copy/cut/selectAll/canPerformAction 各一）+
# 选区在位分流点 5 处（paste/shouldChange/
# didChangeSelection/handlePaste/菜单判定面）。
if [ "$(grep -c 'selectAllXSel()' "$SRC")" = 3 ] \
   && [ "$(grep -c 'replaceXSel(text:' "$SRC")" = 6 ] \
   && [ "$(grep -c 'override func copy' "$SRC")" = 1 ] \
   && [ "$(grep -c 'override func cut' "$SRC")" = 1 ] \
   && [ "$(grep -c 'override func selectAll' "$SRC")" = 1 ] \
   && [ "$(grep -c 'override func canPerformAction' "$SRC")" = 1 ] \
   && [ "$(grep -c 'ed.xsel != nil' "$SRC")" = 5 ]; then
  ok "X50-3 动作面接线（全选 3 入口/替换 6 调用/菜单覆写 4 件/在位分流 5 点）"
else
  bad "X50-3 动作面接线漂移（selectAll=$(grep -c 'selectAllXSel()' "$SRC") replace=$(grep -c 'replaceXSel(text:' "$SRC") inplace=$(grep -c 'ed.xsel != nil' "$SRC")）"
fi
# X50-4 守卫集：只读禁入两点（全选/替换）+ 组
# 字收拢挂组字判定点 + 失效对账入口 + 陈旧清
# 选 Diag。
if [ "$(grep -c 'library.isReadOnly' "$XSELB")" = 2 ] \
   && [ "$(grep -c 'parent.editor?.collapseXSel()' "$SRC")" = 1 ] \
   && [ "$(grep -c 'collapseXSel()' "$SRC")" = 5 ] \
   && [ "$(grep -c 'ed.noteXSelNativeSelection(' "$SRC")" = 1 ] \
   && [ "$(grep -c 'EDIT xsel stale cleared' "$XSELB")" = 1 ]; then
  ok "X50-4 守卫集（只读 2/组字收拢 1+收拢全集 5/对账入口 1/陈旧清选 1）"
else
  bad "X50-4 守卫集接线漂移"
fi
# X50-5 单步撤销 + op 锚：replaceRangeUnits 内
# pushHistory 恰一（跨块替换 = 单个撤销步）+
# Diag 同 Web 式 + K5 atoms 行 + 列表 start 单
# 点复用（shiftListStart 4 调用点 = 双路径首尾
# 容器各一）。
if [ "$(grep -c 'pushHistory()' "$XSELB")" = 1 ] \
   && [ "$(grep -c 'EDIT replace range' "$XSELB")" = 1 ] \
   && [ "$(grep -c 'atoms kept=' "$XSELB")" = 1 ] \
   && [ "$(grep -c 'shiftListStart(' "$XSELB")" = 4 ]; then
  ok "X50-5 替换单步撤销（pushHistory 恰 1）+ Diag 同式 + start 单点复用 4 点"
else
  bad "X50-5 op 锚漂移（pushHistory=$(grep -c 'pushHistory()' "$XSELB") shift=$(grep -c 'shiftListStart(' "$XSELB")）"
fi
# X50-6 呈现接线：行面覆盖判定挂 BlockRow +
# 高亮令牌单点（T.xselHighlight 定义 + 行面消
# 费）+ 色值与 Web 同。计数沿革：一期 2/2（令
# 牌定义 + 行面消费、dynA 明暗两值）；二期加
# UIColor 变体令牌（段内分段着色：定义 + 属性
# 层消费 + 注记）后为 7/3——期望合法变更（同
# J20-12 先例），分段面明细由 [51] X51-4 分锁。
if [ "$(grep -c 'xselRowCovered(block)' "$SRC")" = 1 ] \
   && [ "$(grep -c 'xselHighlight' "$SRC")" = 7 ] \
   && [ "$(grep -o '0x0069D9' "$SRC" | wc -l | tr -d ' ')" = 3 ]; then
  ok "X50-6 行面高亮接线（覆盖判定 1/令牌定义+消费+注记 7/Web 同值 0x0069D9 ×3）"
else
  bad "X50-6 呈现接线漂移"
fi
# X50-7 构建接线：两新文件在 build-app2.sh 全
# 遍登记（26 处 = 25 遍输入 + primary 遍）且
# xsel.o / xsel_bridge.o 各恰 2 处（自有
# primary 遍产出 + 主链接行）。状态栏采样批
# 新增 statusbar/statusbar_bridge 两 primary
# 遍后登记数各 28；图片加载键控批新增
# imageload primary 遍后各 29；状态栏二轮批
# 新增 statusbar_image/splash_host 两 primary
# 遍后各 31；状态栏回退批整遍拆除渲染采样
# 器 primary 遍后各 30——期望合法变更
# （fix_statusbar_sampling.md /
# fix_image_card_load.md /
# fix_statusbar_dynamic.md /
# fix_statusbar_rollback_all.md 沿革，同
# DT46-6 口径）；其后快照恢复批增 bridge_
# restore primary 遍后各 31；采样去除批整
# 遍拆除采样两文件 primary 遍后各 29
# （remove_statusbar_sampling 沿革）。
if [ "$(grep -c 'MomentXSel.swift' build-app2.sh)" = 29 ] \
   && [ "$(grep -c 'MomentXSelBridge.swift' build-app2.sh)" = 29 ] \
   && [ "$(grep -c 'xsel.o' build-app2.sh)" = 2 ] \
   && [ "$(grep -c 'xsel_bridge.o' build-app2.sh)" = 2 ]; then
  ok "X50-7 构建接线（双文件各 29 + xsel.o/xsel_bridge.o 各 ×2）"
else
  bad "X50-7 构建接线漂移（XSel=$(grep -c 'MomentXSel.swift' build-app2.sh) Bridge=$(grep -c 'MomentXSelBridge.swift' build-app2.sh)）"
fi

echo "[51] 跨块选区二期（F-09 Shift+方向任意端点扩展 + 段内分段着色，定案 plan_cross_block_selection §8.1 二期 / impl_cross_block_selection_p2.md）"
# X51-1 二期符号单点：纯核心决策全集（方向枚
# 举/stepChar/横向接管/纵向决策/分段计算）+
# 桥接层扩展与分段查询两入口。
x51ok=1
for s in 'enum XSelDirection' \
         'static func stepChar' \
         'static func extendHorizontal' \
         'static func verticalFocus' \
         'static func segmentRange'; do
  grep -q -- "$s" "$XSEL" || x51ok=0
done
for s in 'func xselExtend' 'func xselSegment'; do
  grep -q -- "$s" "$XSELB" || x51ok=0
done
if [ "$x51ok" = 1 ]; then
  ok "X51-1 二期符号单点（核心 5 符号 + 桥接 2 入口）"
else
  bad "X51-1 二期符号漂移"
fi
# X51-2 扩展决策表驱动：MomentXSel.swift 与内
# 嵌断言体以宿主 swiftc 编译运行——字符步进
# （代理对/跨界/文档端钳）/横向接管判定/纵向
# 决策全表/分段计算，任一不符即红（断言体与
# editor.js xselExtend/stepChar/paintXsel 语
# 义同源；沿 X50-2 先例）。
X51D=$(mktemp -d)
cat > "$X51D/main.swift" <<'XSELEOF'
// F-09 二期 XSelCore 扩展决策表驱动（verify [51] X51-2）。
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}
func P(_ id: String, _ off: Int) -> XSelPos {
    XSelPos(id: id, off: off)
}

// 单元表：a="ab"(2)、b="😀x"(UTF-16 3)、c=""(0)。
let U: [(id: String, text: String)] = [
    (id: "a", text: "ab"),
    (id: "b", text: "😀x"),
    (id: "c", text: ""),
]

// ── stepChar ──
check(XSelCore.stepChar(units: U, idx: 0, off: 0, dir: 1)
        == P("a", 1), "step bmp forward")
check(XSelCore.stepChar(units: U, idx: 0, off: 2, dir: 1)
        == P("b", 0), "step crosses to next head")
check(XSelCore.stepChar(units: U, idx: 1, off: 0, dir: 1)
        == P("b", 2), "step skips surrogate pair")
check(XSelCore.stepChar(units: U, idx: 1, off: 2, dir: 1)
        == P("b", 3), "step after pair")
check(XSelCore.stepChar(units: U, idx: 1, off: 3, dir: 1)
        == P("c", 0), "step crosses into empty unit")
check(XSelCore.stepChar(units: U, idx: 2, off: 0, dir: 1)
        == P("c", 0), "step clamps at doc end")
check(XSelCore.stepChar(units: U, idx: 2, off: 0, dir: -1)
        == P("b", 3), "step back to prev tail")
check(XSelCore.stepChar(units: U, idx: 1, off: 2, dir: -1)
        == P("b", 0), "step back over pair")
check(XSelCore.stepChar(units: U, idx: 1, off: 3, dir: -1)
        == P("b", 2), "step back bmp")
check(XSelCore.stepChar(units: U, idx: 0, off: 1, dir: -1)
        == P("a", 0), "step back to head")
check(XSelCore.stepChar(units: U, idx: 0, off: 0, dir: -1)
        == P("a", 0), "step clamps at doc start")

// ── extendHorizontal 接管判定 ──
// 入口（原无选区）：跨界才接管、同块放行。
var eh = XSelCore.extendHorizontal(
    anchor: P("a", 2), focus: P("a", 2), hadSel: false,
    dir: 1, units: U)
check(eh != nil && eh!.focus == P("b", 0),
      "extend entry crosses boundary")
eh = XSelCore.extendHorizontal(
    anchor: P("a", 0), focus: P("a", 0), hadSel: false,
    dir: 1, units: U)
check(eh == nil, "extend entry in-block passes")
eh = XSelCore.extendHorizontal(
    anchor: P("b", 0), focus: P("b", 0), hadSel: false,
    dir: -1, units: U)
check(eh != nil && eh!.focus == P("a", 2),
      "extend entry crosses backward")
// 已有选区：同块步进亦接管（焦点逐格走）。
eh = XSelCore.extendHorizontal(
    anchor: P("a", 0), focus: P("a", 1), hadSel: true,
    dir: 1, units: U)
check(eh != nil && eh!.anchor == P("a", 0)
      && eh!.focus == P("a", 2),
      "extend with sel steps in-block")
// 焦点单元不在表中：不接管。
eh = XSelCore.extendHorizontal(
    anchor: P("a", 0), focus: P("zz", 0), hadSel: true,
    dir: 1, units: U)
check(eh == nil, "extend focus gone passes")

// ── verticalFocus 决策表 ──
let F = P("b", 1)
check(XSelCore.verticalFocus(
        hadSel: false, focus: F, onEdge: false,
        sameHit: P("b", 0), crossHit: nil,
        docClamp: nil) == nil,
      "vertical in-block entry passes")
check(XSelCore.verticalFocus(
        hadSel: true, focus: F, onEdge: false,
        sameHit: P("b", 0), crossHit: nil,
        docClamp: nil) == P("b", 0),
      "vertical in-block with sel takes hit")
check(XSelCore.verticalFocus(
        hadSel: true, focus: F, onEdge: false,
        sameHit: nil, crossHit: nil,
        docClamp: nil) == nil,
      "vertical in-block no hit fails")
check(XSelCore.verticalFocus(
        hadSel: false, focus: F, onEdge: true,
        sameHit: nil, crossHit: P("a", 2),
        docClamp: nil) == P("a", 2),
      "vertical edge cross hit entry")
check(XSelCore.verticalFocus(
        hadSel: true, focus: F, onEdge: true,
        sameHit: nil, crossHit: P("c", 0),
        docClamp: nil) == P("c", 0),
      "vertical edge cross hit with sel")
check(XSelCore.verticalFocus(
        hadSel: false, focus: F, onEdge: true,
        sameHit: nil, crossHit: nil,
        docClamp: F) == nil,
      "vertical doc clamp at focus passes entry")
check(XSelCore.verticalFocus(
        hadSel: true, focus: F, onEdge: true,
        sameHit: nil, crossHit: nil,
        docClamp: F) == F,
      "vertical doc clamp at focus with sel")
check(XSelCore.verticalFocus(
        hadSel: false, focus: F, onEdge: true,
        sameHit: nil, crossHit: nil,
        docClamp: P("a", 0)) == P("a", 0),
      "vertical doc clamp moves entry")
check(XSelCore.verticalFocus(
        hadSel: false, focus: F, onEdge: true,
        sameHit: nil, crossHit: nil,
        docClamp: nil) == nil,
      "vertical edge nothing fails")

// ── segmentRange 分段计算 ──
let ids = ["a", "b", "c"]
let lens = [2, 3, 0]
let selAB = XSel(anchorId: "a", anchorOff: 1,
                 focusId: "c", focusOff: 0,
                 fromStart: false, toEnd: false)
var sg = XSelCore.segmentRange(sel: selAB, unitIds: ids,
                               unitLens: lens, idx: 0)
check(sg != nil && sg!.from == 1 && sg!.to == 2,
      "segment start unit tail part")
sg = XSelCore.segmentRange(sel: selAB, unitIds: ids,
                           unitLens: lens, idx: 1)
check(sg != nil && sg!.from == 0 && sg!.to == 3,
      "segment middle unit whole")
sg = XSelCore.segmentRange(sel: selAB, unitIds: ids,
                           unitLens: lens, idx: 2)
check(sg != nil && sg!.from == 0 && sg!.to == 0,
      "segment end unit head part")
let selRev = XSel(anchorId: "c", anchorOff: 0,
                  focusId: "a", focusOff: 1,
                  fromStart: false, toEnd: false)
sg = XSelCore.segmentRange(sel: selRev, unitIds: ids,
                           unitLens: lens, idx: 0)
check(sg != nil && sg!.from == 1 && sg!.to == 2,
      "segment reversed same span")
let selOne = XSel(anchorId: "b", anchorOff: 0,
                  focusId: "b", focusOff: 2,
                  fromStart: false, toEnd: false)
check(XSelCore.segmentRange(sel: selOne, unitIds: ids,
                            unitLens: lens, idx: 0) == nil,
      "segment outside before nil")
sg = XSelCore.segmentRange(sel: selOne, unitIds: ids,
                           unitLens: lens, idx: 1)
check(sg != nil && sg!.from == 0 && sg!.to == 2,
      "segment single unit between ends")
check(XSelCore.segmentRange(sel: selOne, unitIds: ids,
                            unitLens: lens, idx: 2) == nil,
      "segment outside after nil")
let selGone = XSel(anchorId: "zz", anchorOff: 0,
                   focusId: "a", focusOff: 1,
                   fromStart: false, toEnd: false)
check(XSelCore.segmentRange(sel: selGone, unitIds: ids,
                            unitLens: lens, idx: 0) == nil,
      "segment endpoint gone nil")

if failures == 0 {
    print("XSEL_EXT_PASS")
} else {
    print("XSEL_EXT_FAIL \(failures)")
    exit(1)
}
XSELEOF
SWIFTC51=""
for c51 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c51" ] && [ -x "$c51" ]; then
    SWIFTC51="$c51"; break
  fi
done
if [ -n "$SWIFTC51" ] \
   && "$SWIFTC51" -O -o "$X51D/xsel_ext_test" \
        "$XSEL" "$X51D/main.swift" 2>"$X51D/err.log" \
   && [ "$("$X51D/xsel_ext_test" 2>/dev/null)" = "XSEL_EXT_PASS" ]; then
  ok "X51-2 扩展决策表驱动全过（步进/接管/纵向决策/分段）"
else
  bad "X51-2 扩展决策表驱动失败（swiftc=$SWIFTC51，详见编译/运行输出）"
  sed 's/^/    X51-2: /' "$X51D/err.log" | head -5
  "$X51D/xsel_ext_test" 2>/dev/null | sed 's/^/    X51-2: /' | head -5
fi
rm -rf "$X51D"
# X51-3 扩展接线：handleKey 调用点 6（在位支
# 2 + 无选区入口 4）+ 活动端跟踪（定义 + 委托
# 回调调用恰 2）+ 几何量测跨文件共用（line-
# Boxes 去 private、tvForBlock/hitOffset 各一）。
if [ "$(grep -c 'xselExtend(' "$SRC")" = 6 ] \
   && [ "$(grep -c 'noteXSelSelection()' "$SRC")" = 2 ] \
   && [ "$(grep -c 'private func lineBoxes' "$SRC")" = 0 ] \
   && [ "$(grep -c 'func tvForBlock' "$SRC")" = 1 ] \
   && [ "$(grep -c 'func hitOffset' "$SRC")" = 1 ]; then
  ok "X51-3 扩展接线（调用 6/活动端跟踪 2/量测共用 3）"
else
  bad "X51-3 扩展接线漂移（extend=$(grep -c 'xselExtend(' "$SRC") track=$(grep -c 'noteXSelSelection()' "$SRC")）"
fi
# X51-4 分段着色接线：分段查询消费 1（update-
# UIView 收尾）+ 着色刷新（定义 + 调用 + 注记
# 4）+ UIColor 变体令牌 3（定义 + 消费 + 注
# 记）+ 行面收窄为原子行（桥接层严格不等式
# 恰 1）。
if [ "$(grep -c 'xselSegment(forBlockId:' "$SRC")" = 1 ] \
   && [ "$(grep -c 'refreshXSelHighlight' "$SRC")" = 4 ] \
   && [ "$(grep -c 'xselHighlightUI' "$SRC")" = 3 ] \
   && [ "$(grep -c 't > units\[ord.sIdx\].topIndex' "$XSELB")" = 1 ]; then
  ok "X51-4 分段着色接线（查询 1/刷新 4/令牌 3/原子行面 1）"
else
  bad "X51-4 分段着色接线漂移"
fi
# X51-5 扩展 Diag：结果侧打点两行（成立 = 锚/
# 焦终值、步回收拢 = collapsed），与一期
# EDIT xsel 同族口径。
if [ "$(grep -c 'EDIT xsel extend' "$XSELB")" = 2 ]; then
  ok "X51-5 扩展 Diag 两行（终值/collapsed）"
else
  bad "X51-5 扩展 Diag 漂移"
fi

echo "[52] 装机根治：交付包不捆绑 appex（0.9.61，用户二分实测改判真阻因，定案 fix_install_signing_0958.md 附记）"
# INS52-1 捆绑开关在位且为关：BUNDLE_WIDGET_EXT=0
# 赋值恰一处（防第二出处改值漂移），且无置 1 赋值。
if [ "$(grep -c '^BUNDLE_WIDGET_EXT=0' "$SH")" = 1 ] \
   && [ "$(grep -c '^BUNDLE_WIDGET_EXT=1' "$SH")" = 0 ]; then
  ok "INS52-1 捆绑开关在位且为关（BUNDLE_WIDGET_EXT=0 恰一处）"
else
  bad "INS52-1 捆绑开关缺失或未关"
fi
# INS52-2 拷入步骤受开关门控 + 编译保持：门控判定
# 行在位（appex 拷入块以此开启），且 check-macho
# 校验行在门控外保持（appex 照常编译防腐烂）。
if grep -qF 'if [ "$BUNDLE_WIDGET_EXT" = 1 ]; then' "$SH" \
   && has 'check-macho.py' "$SH" \
   && has 'NOT bundled (BUNDLE_WIDGET_EXT=0' "$SH"; then
  ok "INS52-2 appex 拷入门控在位 + 编译/check-macho 保持"
else
  bad "INS52-2 appex 门控或编译保持缺失"
fi
# INS52-3 封包硬断言在位：开关关时 PlugIns 在场即
# 停构建的断言（判定行 + FATAL 行）两件齐备；判定
# 行含方括号、以 grep -F 定串匹配。
if grep -qF 'if [ "$BUNDLE_WIDGET_EXT" != 1 ] && [ -e "$APP/PlugIns" ]; then' "$SH" \
   && has 'FATAL: BUNDLE_WIDGET_EXT off but PlugIns present in app bundle' "$SH"; then
  ok "INS52-3 封包硬断言在位（PlugIns 在场即停构建）"
else
  bad "INS52-3 封包硬断言缺失"
fi

echo "[53] 状态栏系统默认口径（remove_statusbar_sampling：背景色采样整套退役）+ 开屏方向锁（fix_statusbar_dynamic）"
# SB-1 采样家族零残留锁（用户 2026-11-28 裁
# 定：背景色采样都去除——含编辑页、含八色登
# 记）：两采样文件不存在；采样符号集在全部
# .swift 与 build-app2.sh 中零命中——纯核心
# （StatusBarCore / L* 阈值 61.65 / 判定 /
# 渐变带区采样 bandAverageColor）、生效层
# （MomentStatusBar 登记栈 / evaluate）、登
# 记面（registerCurrent / clearCurrent）、
# 送达观察器（StatusBarTraitObserver）、开
# 屏公式色（SplashBandColor）、Diag 的
# STATUSBAR 采样行、承载 override 一并退
# 役；旧代符号（0.1791 / evaluateLightness /
# BandRenderSampler / renderedStyle）延续
# 零残留。去除后口径：全仓无 preferred
# StatusBarStyle override，状态栏明暗由系
# 统按 trait 决定（平台默认）——采样前原生
# 零状态栏代码的基线（diag_statusbar_dark
# 定案）；plist 维持 VC-based=true +
# LightContent 只作开屏首帧（[8] 组锁）。
sb1z=0
for s in 'StatusBarCore' 'MomentStatusBar' \
         'registerCurrent' 'clearCurrent' \
         'prefersLightContent' 'lightnessThreshold' \
         'bandAverageColor' 'SplashBandColor' \
         'StatusBarTraitObserver' 'STATUSBAR bg=' \
         'preferredStatusBarStyle' '61.65' \
         '0.1791' 'evaluateLightness' \
         'BandRenderSampler' 'renderedStyle'; do
  if grep -q -- "$s" ./*.swift 2>/dev/null; then
    sb1z=1
    echo "    SB-1 残留 $s: $(grep -l -- "$s" ./*.swift 2>/dev/null | tr '\n' ' ')"
  fi
done
if [ "$sb1z" = 0 ] \
   && [ ! -f MomentStatusBar.swift ] \
   && [ ! -f MomentStatusBarBridge.swift ] \
   && [ "$(grep -c 'MomentStatusBar' build-app2.sh)" = 0 ] \
   && [ "$(grep -c 'statusbar.o' build-app2.sh)" = 0 ] \
   && [ "$(grep -c 'statusbar_bridge.o' build-app2.sh)" = 0 ]; then
  ok "SB-1 采样家族零残留（两文件不存在 + 符号集全仓零命中 + 构建零登记、字色回平台默认）"
else
  bad "SB-1 采样家族残留（sb1z=$sb1z BuildStatusBar=$(grep -c 'MomentStatusBar' build-app2.sh)）"
fi
# SB-2 开屏承载构建接线（改判）：采样两文件
# 的 primary 遍整遍拆除后全文件遍数各 −2
# ——开屏承载 29 遍 + splash_host.o 恰 2
# （自有 primary 遍 + 主链接行）；两代采样
# 器文件名（渲染/图片）延续零残留。
if [ "$(grep -c 'MomentSplashHost.swift' build-app2.sh)" = 29 ] \
   && [ "$(grep -c 'splash_host.o' build-app2.sh)" = 2 ] \
   && [ "$(grep -c 'MomentStatusBarRender.swift' build-app2.sh)" = 0 ] \
   && [ "$(grep -c 'MomentStatusBarImage.swift' build-app2.sh)" = 0 ] \
   && [ "$(grep -c 'statusbar_render.o' build-app2.sh)" = 0 ] \
   && [ "$(grep -c 'statusbar_image.o' build-app2.sh)" = 0 ]; then
  ok "SB-2 开屏承载构建接线（29 遍 + splash_host.o ×2、两代采样器文件名零残留）"
else
  bad "SB-2 开屏承载构建接线漂移（Splash=$(grep -c 'MomentSplashHost.swift' build-app2.sh)）"
fi
# SB-8 开屏方向锁 + iPad 守卫（用户 2026-11-28
# 裁定，并入本批）：方向收窄单点在开屏承载
# （override 恰 1、全仓仅此文件持有该符号）、
# idiom 闸在位（.phone 才收窄 .portrait）；
# iPad 守卫三件——plist ~ipad 方向数组逐字在
# 位、无全局 UISupportedInterfaceOrientations
# 键被引入（防全应用误锁）、开屏画布 isPad 分
# 支两处特征字面在位（foregroundScale 钳制 +
# logo 纵置 0.35）。采样去除后本条为 [53] 组
# 唯一保留的机制锁（方向锁非采样，remove_
# statusbar_sampling 明确保留）。
if [ "$(grep -c 'override var supportedInterfaceOrientations' "$SPLASH")" = 1 ] \
   && [ "$(grep -l 'supportedInterfaceOrientations' ./*.swift 2>/dev/null)" = "./MomentSplashHost.swift" ] \
   && has 'userInterfaceIdiom == .phone' "$SPLASH" \
   && has '? .portrait' "$SPLASH" \
   && grep -qF 'UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>' build-app2.sh \
   && [ "$(grep -c 'UISupportedInterfaceOrientations</key>' build-app2.sh)" = 0 ] \
   && has 'min(0.72, size.width / 1200)' "$SRC" \
   && has 'isPad ? size.height' "$SRC"; then
  ok "SB-8 开屏方向锁单点（承载 override + idiom 闸）+ iPad 守卫（plist 逐字/无全局键/画布 isPad 分支在位）"
else
  bad "SB-8 开屏方向锁/iPad 守卫漂移（Override=$(grep -c 'override var supportedInterfaceOrientations' "$SPLASH") Holders=$(grep -l 'supportedInterfaceOrientations' ./*.swift 2>/dev/null | tr '\n' ' ')）"
fi

echo "[54] 审计 0.9.62 收尾（批 1+2+7 余项：E-03 原子写 / E-05① 本体打点接线 / E-05③ PdfMaker / A-02 附记 / E-02 配套；定案 fix_audit_0962_b127.md）"
# AU54-1 DiagLog 原子写（AUD-E-03）：write 函
# 数体内 .atomic 恰 1——Diag 落盘改同目录临
# 时文件 + rename 替换，写盘中崩溃旧文件完
# 好（原为全家唯一非原子落盘面）。
DW54=$(awk '/    private func write<T: Encodable>/,/^    \}$/' "$SRC")
if [ "$(echo "$DW54" | grep -c 'options: .atomic')" = 1 ]; then
  ok "AU54-1 DiagLog.write 原子写（.atomic 在位）"
else
  bad "AU54-1 DiagLog.write 原子写漂移（.atomic 缺失）"
fi
# AU54-2 撤销本体打点接线（AUD-E-05①）：
# EditorModel init 注入 eventSink 恰 1 处 +
# Diag 词形「EDIT undo core 」在位；代记收
# 敛——logHistoryFeed 与 clampedBefore 全文
# 件零残留（代记/双记回潮即红）；引擎侧三
# 类事件出口各 2（undo/redo 两栈）。
if [ "$(grep -c 'history.eventSink = {' "$SRC")" = 1 ] \
   && has 'EDIT undo core ' "$SRC" \
   && [ "$(grep -c 'logHistoryFeed' "$SRC")" = 0 ] \
   && [ "$(grep -c 'clampedBefore' "$SRC")" = 0 ] \
   && [ "$(grep -c 'eventSink?("dedup' "$UNDO")" = 2 ] \
   && [ "$(grep -c 'eventSink?("clamp' "$UNDO")" = 2 ] \
   && [ "$(grep -c 'eventSink?("step-empty' "$UNDO")" = 2 ]; then
  ok "AU54-2 eventSink 接线单点 + 代记零残留 + 引擎三类出口各 2"
else
  bad "AU54-2 eventSink 接线/代记残留/引擎出口漂移（sink=$(grep -c 'history.eventSink = {' "$SRC") 代记=$(grep -c 'logHistoryFeed' "$SRC")）"
fi
# AU54-3 撤销引擎事件行为表驱动：MomentUndo
# 与内嵌断言体以宿主 swiftc 编译运行——捕获
# eventSink 断言事件序列：同键连馈出 dedup、
# 101 条馈入出 clamp（逐出 1）、空栈 undo/
# redo 步进各出 step-empty（[47] E47-3 的
# 事件面姊妹断言，锁引擎本体自记）。
E54D=$(mktemp -d)
cat > "$E54D/main.swift" <<'SINKEOF'
// AUD-E-05① 引擎事件序列表驱动（verify [54] AU54-3）。
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}

// 同键连馈 → dedup 事件恰一（第二馈命中）
var events: [String] = []
var h = UndoHistoryCore<String>()
h.eventSink = { events.append($0) }
_ = h.recordOpBoundary(payload: "A", key: "A",
                       sel: nil)
_ = h.recordOpBoundary(payload: "A", key: "A",
                       sel: nil)
check(events.count == 1
      && events[0].hasPrefix("dedup side=undo"),
      "dedup event")

// 101 条相异馈入 → clamp 事件恰一（逐出 1）
events = []
var h2 = UndoHistoryCore<String>()
h2.eventSink = { events.append($0) }
for i in 0...100 {
    _ = h2.recordOpBoundary(payload: "k\(i)",
                            key: "k\(i)", sel: nil)
}
check(events.count == 1
      && events[0].hasPrefix("clamp side=undo n=1"),
      "clamp event")

// 空栈步进 → step-empty 事件（undo/redo 各一）
events = []
var h3 = UndoHistoryCore<String>()
h3.eventSink = { events.append($0) }
_ = h3.performUndo(currentPayload: "x",
                   currentKey: "x", currentSel: nil)
_ = h3.performRedo(currentPayload: "x",
                   currentKey: "x", currentSel: nil)
check(events == ["step-empty side=undo",
                 "step-empty side=redo"],
      "step-empty events")

if failures == 0 {
    print("UNDO_SINK_PASS")
} else {
    print("UNDO_SINK_FAIL \(failures)")
    exit(1)
}
SINKEOF
SWIFTC54=""
for c54 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c54" ] && [ -x "$c54" ]; then
    SWIFTC54="$c54"; break
  fi
done
if [ -n "$SWIFTC54" ] \
   && "$SWIFTC54" -O -o "$E54D/sink_test" \
        "$UNDO" "$E54D/main.swift" 2>"$E54D/err.log" \
   && [ "$("$E54D/sink_test" 2>/dev/null)" = "UNDO_SINK_PASS" ]; then
  ok "AU54-3 引擎事件序列表驱动全过（dedup/clamp/step-empty）"
else
  bad "AU54-3 引擎事件序列表驱动失败（swiftc=$SWIFTC54，详见编译/运行输出）"
fi
# AU54-4 PdfMaker 失败原因行（AUD-E-05③）：
# 两失败路径（导航失败 / createPDF 失败）各
# 一行带原因，全文件各恰 1——上层只报成败、
# 本体记因。
if [ "$(grep -c 'PDF make nav failed' "$SRC")" = 1 ] \
   && [ "$(grep -c 'PDF make create failed' "$SRC")" = 1 ]; then
  ok "AU54-4 PdfMaker 两失败路径带原因 Diag 行（各 1）"
else
  bad "AU54-4 PdfMaker 失败原因行漂移"
fi
# AU54-5 haystack meta.url 滤 data:（AUD-
# A-02 附记）：searchHaystack 体内 url 键同
# 口径守卫在位（与 attrs 两处同形态：非
# data: 才入拼装文本）。
HS54=$(awk '/    static func searchHaystack\(of memo: MemoItem\) -> String \{/,/^    \}$/' "$SRC")
if [ "$(echo "$HS54" | grep -cF 'key == "url"')" = 1 ] \
   && [ "$(echo "$HS54" | grep -cF 's.hasPrefix("data:")')" = 1 ]; then
  ok "AU54-5 haystack meta.url data: 过滤在位"
else
  bad "AU54-5 haystack meta.url 过滤漂移"
fi
# AU54-6 opsValidate 拆集配套（AUD-E-02）：
# 可 guard 集显式声明 + 不可 guard 集以
# subtracting 派生（禁手抄第二份名单）+ 回
# 报含 unguardedSteps 字段且 valid 判据含
# 其为空——点名核心步不再回「合法」。
if has 'static let guardableOpsSteps' "$BOPS" \
   && has 'knownOpsSteps.subtracting(guardableOpsSteps)' "$BOPS" \
   && has '"unguardedSteps": unguardedSteps' "$BOPS" \
   && has '&& unguardedSteps.isEmpty' "$BOPS"; then
  ok "AU54-6 opsValidate 拆集（派生单源 + 回报/判据在位）"
else
  bad "AU54-6 opsValidate 拆集漂移"
fi

echo "[55] 图片加载键控（fix_image_card_load）"
# IMG55-1 键控单点：纯核心三符号在位 + loader
# 已接闸门、旧一次性闩锁（private var started）
# 零残留——闩锁回潮即红（本症根因本体）。
if has 'struct ImageSourceKey' "$IMGCORE" \
   && has 'enum ImageLoadDecision' "$IMGCORE" \
   && has 'struct ImageLoadGate' "$IMGCORE" \
   && [ "$(grep -c 'private var started' "$SRC")" = 0 ] \
   && [ "$(grep -c 'ImageLoadGate' "$SRC")" -ge 1 ]; then
  ok "IMG55-1 键控单点（核心三符号 + loader 接闸门 + started 闩锁零残留）"
else
  bad "IMG55-1 键控单点漂移（核心符号/闸门接线/started 残留）"
fi
# IMG55-2 闸门行为表驱动：MomentImageLoad.swift
# 与内嵌断言体以宿主 swiftc 编译运行——呈键序
# 列（首呈/同键跳过/键变重载/nil↔fid↔url 迁
# 移）+ currentKey 跟踪 + hasSource/diagTag 形
# 态，任一不符即红（沿 SB-2 先例）。
IMG55D=$(mktemp -d)
cat > "$IMG55D/main.swift" <<'IMGEOF'
// 图片加载闸门纯核心表驱动（verify [54] IMG55-2）。
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}

var g = ImageLoadGate()
check(g.offer(fileId: nil, urlString: nil)
        == .start, "first nil start")
check(g.offer(fileId: nil, urlString: nil)
        == .skip, "same nil skip")
check(g.offer(fileId: "att-a", urlString: nil)
        == .reload, "nil to fid reload")
check(g.offer(fileId: "att-a", urlString: nil)
        == .skip, "same fid skip")
check(g.offer(fileId: "att-b", urlString: nil)
        == .reload, "fid swap reload")
check(g.offer(fileId: nil, urlString: nil)
        == .reload, "fid to nil reload")
check(g.offer(fileId: nil,
              urlString: "https://x.test/a.png")
        == .reload, "nil to url reload")
check(g.offer(fileId: nil,
              urlString: "https://x.test/a.png")
        == .skip, "same url skip")
check(g.currentKey == ImageSourceKey(
        fileId: nil,
        urlString: "https://x.test/a.png"),
      "currentKey tracks last")
check(!ImageSourceKey(fileId: nil,
        urlString: nil).hasSource,
      "nosource hasSource false")
check(ImageSourceKey(fileId: "att-a",
        urlString: nil).hasSource,
      "fid hasSource true")
check(ImageSourceKey(fileId: "att-a",
        urlString: nil).diagTag == "fid=att-a",
      "diagTag fid")
check(ImageSourceKey(
        fileId: nil,
        urlString: "https://x.test/a.png")
        .diagTag == "url=x.test",
      "diagTag url host")
check(ImageSourceKey(fileId: nil,
        urlString: nil).diagTag == "none",
      "diagTag none")

if failures == 0 {
    print("IMGLOAD_GATE_PASS")
} else {
    print("IMGLOAD_GATE_FAIL \(failures)")
}
IMGEOF
SWIFTC55=""
for c54 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c54" ] && [ -x "$c54" ]; then
    SWIFTC55="$c54"; break
  fi
done
if [ -n "$SWIFTC55" ] \
   && "$SWIFTC55" -O -o "$IMG55D/img_test" \
        "$IMGCORE" "$IMG55D/main.swift" 2>"$IMG55D/err.log" \
   && [ "$("$IMG55D/img_test" 2>/dev/null)" = "IMGLOAD_GATE_PASS" ]; then
  ok "IMG55-2 闸门行为表驱动全过（呈键序列/键跟踪/标签形态）"
else
  bad "IMG55-2 闸门行为表驱动失败（swiftc=$SWIFTC55，详见编译/运行输出）"
  sed 's/^/    IMG55-2: /' "$IMG55D/err.log" | head -5
  "$IMG55D/img_test" 2>/dev/null | sed 's/^/    IMG55-2: /' | head -5
fi
rm -rf "$IMG55D"
# IMG55-3 变化钩子计数：三块视图（图片/图文/
# 视频）各有 fileId+imageURL 双钩、ItemImageView
# 有 fileId+urlString 双钩——只改闸门不补钩子
# 则重演算无人再呈、照样不刷（诊断 §6.2）。
if [ "$(grep -c 'onChange(of: block.fileId)' "$SRC")" = 3 ] \
   && [ "$(grep -c 'onChange(of: block.imageURL)' "$SRC")" = 3 ] \
   && [ "$(grep -c 'onChange(of: fileId)' "$SRC")" -ge 1 ] \
   && [ "$(grep -c 'onChange(of: urlString)' "$SRC")" -ge 1 ]; then
  ok "IMG55-3 变化钩子（块三视图双钩 3+3、瓦面双钩在位）"
else
  bad "IMG55-3 变化钩子漂移（block.fileId=$(grep -c 'onChange(of: block.fileId)' "$SRC") block.imageURL=$(grep -c 'onChange(of: block.imageURL)' "$SRC")）"
fi
# IMG55-4 gallery 项键：GalleryBlockView 段内
# offset 身份零残留 + tileEntries 在位（定义 +
# ForEach 消费）。
IMG55SEG=$(sed -n '/^struct GalleryBlockView/,/^struct [A-Z]/p' "$SRC")
if [ "$(printf '%s' "$IMG55SEG" | grep -c 'id: \.offset')" = 0 ] \
   && [ "$(printf '%s' "$IMG55SEG" | grep -c 'tileEntries')" -ge 2 ] \
   && has 'GalleryTileEntry' "$SRC"; then
  ok "IMG55-4 gallery 项键（段内 offset 身份 0 + tileEntries 定义/消费在位）"
else
  bad "IMG55-4 gallery 项键漂移（offset 残留或 tileEntries 缺失）"
fi
# IMG55-5 Diag 行：重载起始/成功成对（IMG
# reload + IMG reload ok）、nil 源首行、视频
# 三静默出口 + 无源行（VIDEO prepare 四行）与
# prepare 键控（preparedKey）在位。
if [ "$(grep -c 'IMG reload ' "$SRC")" -ge 2 ] \
   && [ "$(grep -c 'IMG reload ok' "$SRC")" = 1 ] \
   && [ "$(grep -c 'IMG load nosource' "$SRC")" = 1 ] \
   && [ "$(grep -c 'VIDEO prepare ' "$SRC")" -ge 4 ] \
   && [ "$(grep -c 'preparedKey' "$SRC")" -ge 3 ]; then
  ok "IMG55-5 Diag 行（IMG 重载成对/nil 源首行 + VIDEO 出口四行/键控）"
else
  bad "IMG55-5 Diag 行漂移（IMG reload=$(grep -c 'IMG reload ' "$SRC") VIDEO=$(grep -c 'VIDEO prepare ' "$SRC") preparedKey=$(grep -c 'preparedKey' "$SRC")）"
fi
# IMG55-6 场景与矩阵：两景名 + 两场景体 + 媒
# 体夹具接线（mediaFids 多处）在位；覆盖矩阵
# EDT-60/EDT-61 已登记。
if has 'image_block_seated_load' "$UITEST" \
   && has 'gallery_items_follow' "$UITEST" \
   && has 'UITestScenarioImageSeated' "$UITEST" \
   && has 'UITestScenarioGalleryFollow' "$UITEST" \
   && [ "$(grep -c 'mediaFids' "$UITEST")" -ge 3 ] \
   && has 'EDT-60' ../../../../docs/reports/plan_selftest_coverage.md \
   && has 'EDT-61' ../../../../docs/reports/plan_selftest_coverage.md; then
  ok "IMG55-6 场景与矩阵（两景/两体/夹具接线 + EDT-60/61 登记）"
else
  bad "IMG55-6 场景与矩阵漂移（景名/场景体/夹具/矩阵登记任一缺失）"
fi
# IMG55-7 构建名单：新文件与 XSel 同名单全覆
# 盖（计数一致）+ imageload.o 恰 2 处（自有遍
# 产出 + 链接行，仿 SB-5）。
if [ "$(grep -c 'MomentImageLoad.swift' "$SH")" = "$(grep -c 'MomentXSel.swift' "$SH")" ] \
   && [ "$(grep -c 'imageload.o' "$SH")" = 2 ]; then
  ok "IMG55-7 构建名单（ImageLoad 与 XSel 计数一致 + imageload.o ×2）"
else
  bad "IMG55-7 构建名单漂移（ImageLoad=$(grep -c 'MomentImageLoad.swift' "$SH") XSel=$(grep -c 'MomentXSel.swift' "$SH") imageload.o=$(grep -c 'imageload.o' "$SH")）"
fi

echo "[56] 诊断/日志页宽屏收窄（AUD-C-02，用户 2026-11-28 裁定；定案 fix_diag_pages_narrow.md）"
# DG56-1 收窄钳单点：720 字面在主文件恰一处
# 且位于 wideNarrowClamp 定义内；钳调用共 2 =
# 定义行 1 + 设置族内容框本体 1。沿革：C-02
# 落码时视窗页终端卡直调钳（共 3）；同日续批
# （用户实报，fix_diaglog_header_spacing.md）
# 视窗页改经设置框整框接入、间接入钳——计数
# 3→2，钳仍全仓唯一、无第二套收窄逻辑。
DGDEF=$(awk '/func wideNarrowClamp/,/^    }$/' "$SRC")
SCFDEF=$(awk '/func settingsContentFrame/,/^    }$/' "$SRC")
if [ "$(grep -cF '.frame(maxWidth: 720)' "$SRC")" = 1 ] \
   && echo "$DGDEF" | grep -qF '.frame(maxWidth: 720)' \
   && echo "$SCFDEF" | grep -q 'wideNarrowClamp()' \
   && [ "$(grep -c 'wideNarrowClamp()' "$SRC")" = 2 ]; then
  ok "DG56-1 收窄钳单点（720 字面恰一处 + 设置框单点入钳）"
else
  bad "DG56-1 收窄钳单点漂移（720 字面=$(grep -cF '.frame(maxWidth: 720)' "$SRC") 钳调用=$(grep -c 'wideNarrowClamp()' "$SRC")）"
fi
# DG56-2 诊断页经设置族内容框单点接入：Diag-
# View 段内含内容框调用、且原手抄顶距零残留
# （手抄三行已收敛，宽屏与六页同形态、窄屏
# 逐值等价零变化）。顶距改判 126→81 后（用
# 户 2026-11-28 裁定，fix_frame_top_inset_
# 81.md）同锁新值字面零残留，防按新值手抄。
DIAGSEG=$(awk '/^struct DiagView/,/^struct DiagLogPage/' "$SRC")
if echo "$DIAGSEG" | grep -q 'settingsContentFrame()' \
   && [ "$(echo "$DIAGSEG" | grep -c 'padding(.top, 126)')" = 0 ] \
   && [ "$(echo "$DIAGSEG" | grep -c 'padding(.top, 81)')" = 0 ]; then
  ok "DG56-2 诊断页入收敛面（同框调用 + 手抄顶距零残留）"
else
  bad "DG56-2 诊断页收敛缺失（未接入或手抄回潮）"
fi
# DG56-3 日志视窗页终端卡入收敛面（改判）：
# C-02 时为「直调钳 + 自持三值（顶 126/横 20
# 手抄、底 40 + 安全区）」；同日续批（用户实
# 报，fix_diaglog_header_spacing.md）改整框
# 接入：段内含 settingsContentFrame() 调用 +
# 独立安全区底距项，旧合成字面（40 + 安全区
# 一行式）零残留——底距合成值仍为 40 + 安全
# 区（框平 40 + 独立项），窄屏等价守卫成立，
# 防整框顶替时把安全区项一并吞掉。
LOGSEG=$(awk '/^struct DiagLogPage/,/^struct ListBlockView/' "$SRC")
if echo "$LOGSEG" | grep -q 'settingsContentFrame()' \
   && echo "$LOGSEG" | grep -qF '.padding(.bottom, geo.safeAreaInsets.bottom)' \
   && ! echo "$LOGSEG" | grep -q '40 + geo.safeAreaInsets.bottom'; then
  ok "DG56-3 日志视窗页入收敛面（整框接入 + 安全区底距独立在位）"
else
  bad "DG56-3 日志视窗页收敛缺失或底距口径漂移"
fi

echo "[57] 首组头顶距动态适应（AUD-A-08，用户 2026-11-28 裁定；定案 fix_home_header_gap_adaptive.md）"
# HG57-1 动态规则单点：节奏字面只许 Home-
# HeaderMath 持有（groupRhythm 定义恰 1）；
# 规则函数定义恰 1、全文件调用面 3（定义 +
# gap 内调 + 组头调用点）；紧邻派生定义 +
# 调用各 1。
if [ "$(grep -c 'groupRhythm: CGFloat = 28' "$SRC")" = 1 ] \
   && [ "$(grep -c 'static func firstGroupTopInset' "$SRC")" = 1 ] \
   && [ "$(grep -c 'firstGroupTopInset(' "$SRC")" = 3 ] \
   && [ "$(grep -c 'firstGroupAboveBottomInset' "$SRC")" = 2 ]; then
  ok "HG57-1 动态规则单点（节奏/函数/派生计数在位）"
else
  bad "HG57-1 动态规则单点漂移（节奏=$(grep -c 'groupRhythm: CGFloat = 28' "$SRC") 函数面=$(grep -c 'firstGroupTopInset(' "$SRC") 派生=$(grep -c 'firstGroupAboveBottomInset' "$SRC")）"
fi
# HG57-2 两态量测（本组核心，锁量测值不锁
# 文本）：四种紧邻行的 bottom inset 一律从
# 各行定义段提取实测值（新建卡/横幅/notice
# 取 EdgeInsets bottom、占位行零 insets 记
# 0），连同 HomeHeaderMath 源码真身段喂宿
# 主 swiftc 编译实跑——断言四态视觉间隔
# （bottom + 规则反推 top）全 = 基准 28、常
# 态 top = 25（原账零变化）、下限钳不变量
# （b=25→间隔 28、b=40→top 钳 3 且间隔
# 43 ≥ 28）；网格侧同法提取统一 spacing 与
# 组头顶 padding、断言两态间隔同值 22。任
# 一行几何漂移 → 提取值变 → 量测即红。
HH57=$(awk '/^enum HomeHeaderMath \{/{f=1} f{print} f&&/^\}$/{exit}' "$SRC")
NC57=$(awk '/private var newCardRow/,/private func groupHeader/' "$SRC" | grep -oE 'bottom: [0-9]+' | head -1 | grep -oE '[0-9]+')
BN57=$(awk '/private var readonlyBannerRow/,/^    \}$/' "$SRC" | grep -oE 'bottom: [0-9]+' | head -1 | grep -oE '[0-9]+')
NT57=$(awk '/private var noticeRow/,/^    \}$/' "$SRC" | grep -oE 'bottom: [0-9]+' | head -1 | grep -oE '[0-9]+')
SP57=1
echo "$LV" | awk '/private var spacerRow/,/^    \}$/' | grep -qF '.listRowInsets(EdgeInsets())' && SP57=0
GS57=$(awk '/private var gridHome/,/private var gridColumns/' "$SRC" | awk '/VStack\(spacing: [0-9]+\)/ { match($0, /spacing: [0-9]+/); v = substr($0, RSTART + 9, RLENGTH - 9) } /if library\.isReadOnly/ { print v; exit }')
GP57=$(awk '/private var gridHome/,/private var gridColumns/' "$SRC" | grep -oE 'padding\(\.top, [0-9]+\)' | head -1 | grep -oE '[0-9]+')
HG57D=$(mktemp -d)
{ printf 'import Foundation\n'; printf '%s\n' "$HH57"; } > "$HG57D/core.swift"
cat > "$HG57D/main.swift" <<'HGEOF'
// 首组头顶距量测断言体（verify [57] HG57-2）：
// argv = [newCard, banner, notice, spacer,
//         gridSpacing, gridHeadTopPad]，均自源码
// 行定义段提取的实测几何（shell 侧提取）。
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}
let args = CommandLine.arguments
guard args.count == 7,
      let nc = Double(args[1]), let bn = Double(args[2]),
      let nt = Double(args[3]), let sp = Double(args[4]),
      let gs = Double(args[5]), let gp = Double(args[6])
else {
    print("HOME_GAP_FAIL argv")
    exit(1)
}
// 四态视觉间隔全 = 基准节奏 28（动态规则目标）。
for (name, b) in [("newCard", nc), ("banner", bn),
                  ("notice", nt), ("spacer", sp)] {
    check(HomeHeaderMath.firstGroupGap(
            aboveBottomInset: CGFloat(b)) == 28,
          "gap \(name) == 28")
    check(HomeHeaderMath.firstGroupGap(
            aboveBottomInset: CGFloat(b))
          >= HomeHeaderMath.groupRhythm,
          "gap \(name) >= rhythm")
}
// 常态（卡邻居）top = 25：原 28/6 账零变化。
check(HomeHeaderMath.firstGroupTopInset(
        aboveBottomInset: 3) == 25,
      "card neighbor top == 25")
// 下限钳不变量：b 达节奏时 top 钳 3、间隔仍
// = 28；b 超节奏时间隔随 b（> 28、不贴脸）。
check(HomeHeaderMath.firstGroupTopInset(
        aboveBottomInset: 25) == 3,
      "floor at b=25")
check(HomeHeaderMath.firstGroupGap(
        aboveBottomInset: 25) == 28,
      "gap at b=25 == 28")
check(HomeHeaderMath.firstGroupTopInset(
        aboveBottomInset: 40) == 3,
      "floor at b=40")
check(HomeHeaderMath.firstGroupGap(
        aboveBottomInset: 40) == 43,
      "gap at b=40 == 43")
// 网格两态：统一 spacing + 组头顶 padding 构
// 造恒等（横幅只增行不改 spacing）——两态同
// 输入同值 22，与窄屏各形态内节奏自洽。
check(gs + gp == 22, "grid gap == 22")

if failures == 0 {
    print("HOME_GAP_PASS")
} else {
    print("HOME_GAP_FAIL \(failures)")
    exit(1)
}
HGEOF
SWIFTC57=""
for c57 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c57" ] && [ -x "$c57" ]; then
    SWIFTC57="$c57"; break
  fi
done
if [ -n "$SWIFTC57" ] && [ -n "$NC57" ] && [ -n "$BN57" ] \
   && [ -n "$NT57" ] && [ -n "$GS57" ] && [ -n "$GP57" ] \
   && "$SWIFTC57" -O -o "$HG57D/hg_test" \
        "$HG57D/core.swift" "$HG57D/main.swift" 2>"$HG57D/err.log" \
   && [ "$("$HG57D/hg_test" "$NC57" "$BN57" "$NT57" "$SP57" "$GS57" "$GP57" 2>/dev/null)" = "HOME_GAP_PASS" ]; then
  ok "HG57-2 两态量测全过（四态间隔 28 / 常态 top 25 / 钳不变量 / 网格 22）"
else
  bad "HG57-2 两态量测失败（提取 nc=$NC57 bn=$BN57 nt=$NT57 sp=$SP57 gs=$GS57 gp=$GP57，swiftc=$SWIFTC57）"
  sed 's/^/    HG57-2: /' "$HG57D/err.log" | head -5
  "$HG57D/hg_test" "$NC57" "$BN57" "$NT57" "$SP57" "$GS57" "$GP57" 2>/dev/null | sed 's/^/    HG57-2: /' | head -5
fi
rm -rf "$HG57D"
# HG57-3 紧邻派生判定序：newCard 条件与 body
# 字面同源（!loadFailed && !isReadOnly）在
# 派生段内在位；notice 判定先于 banner 判定
# （行序 = body 行序，notice 在横幅之下紧邻
# 组头——序反则只读+notice 并存态误取横幅
# 行、虽同值 6 亦属判定面漂移、锁序防混）。
AB57=$(awk '/private var firstGroupAboveBottomInset/,/^    \}$/' "$SRC")
n57a=$(echo "$AB57" | grep -nF 'notice.isEmpty' | head -1 | cut -d: -f1)
n57b=$(echo "$AB57" | grep -nF 'if library.isReadOnly { return 6 }' | head -1 | cut -d: -f1)
if echo "$AB57" | grep -qF '!library.loadFailed && !library.isReadOnly' \
   && [ -n "$n57a" ] && [ -n "$n57b" ] && [ "$n57a" -lt "$n57b" ]; then
  ok "HG57-3 紧邻派生判定序（newCard 同源 + notice 先于 banner）"
else
  bad "HG57-3 紧邻派生判定序漂移"
fi

echo "[61] 全页面内容框收敛（用户 2026-11-28 裁定：除编辑页/首页外全页对齐设置页口径；定案 fix_page_frame_align_all.md）"
# 沿革：本组原编 [58]（PF58-*），与前向删除
# 批 FD58 同号撞号；组版 0.9.63 定夺 FD 先到
# 留 [58]、本组顺延 [61] 并改断言名 PF61-*，
# 全文引用（定案报告与两批连带改判注）同步。
# PF61-1 内容框单点消费全集：盘点表（fix_
# page_frame_align_all.md §二）应接入页 8 页
# 逐段在位——主文件六页（设置主页/备份/手
# 势/天气/语言/诊断）各段内含 settingsCon-
# tentFrame() 调用；桥设置页、权限页各整文
# 件恰一调用（两文件各只有该页一个整页结
# 构）。任一页脱落，本断言即红。
PFSEG_SET=$(awk '/^struct SettingsView/,/^struct BackupView/' "$SRC")
PFSEG_BAK=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
PFSEG_GES=$(awk '/^struct GesturesView/,/^struct WeatherView/' "$SRC")
PFSEG_WEA=$(awk '/^struct WeatherView/,/^struct LanguageView/' "$SRC")
PFSEG_LAN=$(awk '/^struct LanguageView/,/^struct ImagePageView/' "$SRC")
PFSEG_DIA=$(awk '/^struct DiagView/,/^struct DiagLogPage/' "$SRC")
if echo "$PFSEG_SET" | grep -q 'settingsContentFrame()' \
   && echo "$PFSEG_BAK" | grep -q 'settingsContentFrame()' \
   && echo "$PFSEG_GES" | grep -q 'settingsContentFrame()' \
   && echo "$PFSEG_WEA" | grep -q 'settingsContentFrame()' \
   && echo "$PFSEG_LAN" | grep -q 'settingsContentFrame()' \
   && echo "$PFSEG_DIA" | grep -q 'settingsContentFrame()' \
   && [ "$(grep -c 'settingsContentFrame()' "$BSET")" = 1 ] \
   && [ "$(grep -c 'settingsContentFrame()' "$PERMF")" = 1 ]; then
  ok "PF61-1 内容框消费全集（应接入 8 页逐段在位）"
else
  bad "PF61-1 内容框消费全集缺页或漂移"
fi
# PF61-2 单点唯一 + 标准外字面零新增普查：
# 内容框/收窄钳定义全仓各恰一（无第二单
# 点）；判别字面全仓计数锁现状——顶 126 共
# 1（仅图片页呈现顶让，自持自分叉登记）、
# 顶 81 共 1（单点定义本体）；720 框共 2（主
# 文件钳定义 1 + 救援页 E-2 手抄 1，R19-14
# 登记）；横 20 共 4（主文件：定义 1 + 编
# 辑页豁免面 2；救援页手抄 1）。沿革：日志
# 视窗页原登记自持面（顶 126/横 20 各 1），
# 同日续批（用户实报，fix_diaglog_header_
# spacing.md）整框入单点、自持字面清零——
# 顶 126 由 3→2、横 20 由 5→4，盘点表该页
# 改判「接入面」。同日顶距改判（用户
# 2026-11-28 裁定，fix_frame_top_inset_
# 81.md）：单点定义顶 126→81（上滑 ≈45pt
# 截图位置为标准）——顶 126 由 2→1、顶 81
# 新锁恰 1。新页面手抄间距或新定义
# 出现，计数即变、本断言即红——须先改盘
# 点表再改此数。
if [ "$(grep -h 'func settingsContentFrame' ./*.swift | wc -l)" = 1 ] \
   && [ "$(grep -h 'func wideNarrowClamp' ./*.swift | wc -l)" = 1 ] \
   && [ "$(grep -h 'padding(.top, 126)' ./*.swift | wc -l)" = 1 ] \
   && [ "$(grep -h 'padding(.top, 81)' ./*.swift | wc -l)" = 1 ] \
   && [ "$(grep -hF '.frame(maxWidth: 720)' ./*.swift | wc -l)" = 2 ] \
   && [ "$(grep -h 'padding(.horizontal, 20)' ./*.swift | wc -l)" = 4 ]; then
  ok "PF61-2 单点唯一 + 标准外字面零新增（定义 1/1 · 顶126=1 · 顶81=1 · 720框=2 · 横20=4）"
else
  bad "PF61-2 内容框普查漂移（定义=$(grep -h 'func settingsContentFrame' ./*.swift | wc -l)/$(grep -h 'func wideNarrowClamp' ./*.swift | wc -l) 顶126=$(grep -h 'padding(.top, 126)' ./*.swift | wc -l) 顶81=$(grep -h 'padding(.top, 81)' ./*.swift | wc -l) 720框=$(grep -hF '.frame(maxWidth: 720)' ./*.swift | wc -l) 横20=$(grep -h 'padding(.horizontal, 20)' ./*.swift | wc -l)）"
fi
# PF61-3 豁免/登记面守卫：盘点表非接入面保
# 持其登记形态——首页/编辑页（用户明示豁
# 免）段内零单点调用；图片页顶让 126 在位
# 且零单点调用（contain 可用区公式为既有
# 定案、不被整框顶替）；救援页手抄横 20 +
# 720 框在位且零单点调用（救援隔离：不依
# 赖主应用单点，E-2/R19-14 登记）。
PFSEG_HOME=$(awk '/^struct ListView/,/^struct CompactTitle/' "$SRC")
PFSEG_EDIT=$(awk '/^struct EditorView/,/^struct EditorHeaderView/' "$SRC")
PFSEG_IMG=$(awk '/^struct ImagePageView/,/^struct SplashHostView/' "$SRC")
if [ "$(echo "$PFSEG_HOME" | grep -c 'settingsContentFrame()')" = 0 ] \
   && [ "$(echo "$PFSEG_EDIT" | grep -c 'settingsContentFrame()')" = 0 ] \
   && echo "$PFSEG_IMG" | grep -q 'padding(.top, 126)' \
   && [ "$(echo "$PFSEG_IMG" | grep -c 'settingsContentFrame()')" = 0 ] \
   && [ "$(grep -c 'padding(.horizontal, 20)' "$RESCUE")" = 1 ] \
   && [ "$(grep -cF '.frame(maxWidth: 720)' "$RESCUE")" = 1 ] \
   && [ "$(grep -c 'settingsContentFrame()' "$RESCUE")" = 0 ]; then
  ok "PF61-3 豁免/登记面守卫（首页/编辑页豁免 · 图片页公式面 · 救援手抄隔离）"
else
  bad "PF61-3 豁免/登记面形态漂移"
fi

echo "[58] 前向删除块末合并（AUD-B-05，用户 2026-11-28 裁定；定案 fix_forward_delete_merge.md）"
# FD58-1 定义单点：两合并函数 + 向后最近文本
# 块 + 按键面入口各恰 1。
if [ "$(grep -c 'func mergeBlockForward' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func mergeListItemForward' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func nearestTextBlock(after' "$SRC")" = 1 ] \
  && [ "$(grep -c 'func mergeForwardFromKey' "$SRC")" = 1 ]; then
  ok "FD58-1 前向合并定义四点齐全（顶层/列表项/向后查找/按键入口）"
else
  bad "FD58-1 前向合并定义缺失或重复"
fi
# FD58-2 触发两面：delegate 块末空变更支与
# handleKey 硬件 Delete 支；调用普查（两函数
# 名各 3 = 定义 + delegate + 按键入口）与
# keyboardDeleteForward 普查（恰 2 = XSel 接
# 管支 + 本支）。
if [ "$(grep -c 'mergeBlockForward(' "$SRC")" = 3 ] \
  && [ "$(grep -c 'mergeListItemForward(' "$SRC")" = 3 ] \
  && [ "$(grep -c 'keyboardDeleteForward' "$SRC")" = 2 ]; then
  ok "FD58-2 前向删除触发两面在位（delegate + 硬件按键）"
else
  bad "FD58-2 前向删除触发面漂移"
fi
# FD58-3 撤销单点：两函数段内 pushHistory 普
# 查（顶层 3 = 空支/文本/列表；列表项 5 = 表
# 内/空末项两支/末项两支），每条落变路径恰一
# 检查点 = 单撤销单元（E2 体系）。
FD58SEG_B=$(awk '/func mergeBlockForward/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
FD58SEG_L=$(awk '/func mergeListItemForward/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ "$(echo "$FD58SEG_B" | grep -c 'pushHistory()')" = 3 ] \
  && [ "$(echo "$FD58SEG_L" | grep -c 'pushHistory()')" = 5 ]; then
  ok "FD58-3 前向合并检查点普查（顶层 3 + 列表项 5，单撤销单元）"
else
  bad "FD58-3 前向合并检查点普查漂移"
fi
# FD58-4 原子守卫：两函数各一选中态落点 +
# Diag 同行（原子块永不被键盘删除，F-08 镜像）。
if [ "$(grep -c 'selectedBlockId = next.id' "$SRC")" = 2 ] \
  && [ "$(grep -c 'EDIT merge fwd before atomic' "$SRC")" = 2 ]; then
  ok "FD58-4 前向原子守卫两支（选中保留 + Diag）"
else
  bad "FD58-4 前向原子守卫漂移"
fi
# FD58-5 Diag 谱系：fwd 行恰 7（mergeBlock-
# Forward 六行：空支两行/文本/列表首项/原子/守
# 卫自身，+ 列表项原子行一行）、列表项 fwd 行
# 恰 5（表内两 case/末项两 case/空末项收敛一
# 行）。守卫自身行 2026-11-28 随 [66] 卡片机制
# 统一新增（impl_card_guard_unify），计数 6→7 改判。
if [ "$(grep -c 'EDIT merge fwd' "$SRC")" = 7 ] \
  && [ "$(grep -c 'EDIT merge list-item fwd' "$SRC")" = 5 ]; then
  ok "FD58-5 前向合并 Diag 谱系齐全（顶层 7 + 列表项 5）"
else
  bad "FD58-5 前向合并 Diag 谱系漂移"
fi

echo "[59] 日志视窗页页头图标钮 + 间距同源（用户 2026-11-28 实报；定案 fix_diaglog_header_spacing.md）"
# DL59-1 导出图标钮在位 + 文字胶囊零残留：
# DiagLogPage 段内含统一导出符号 + 无障碍标
# 签（diag.export 键转此一消费）；旧文字胶囊
# 构造（Text 直挂同键 + 生长式 minHeight 46）
# 零残留——防图标改判回潮为文字胶囊。
DL59SEG=$(awk '/^struct DiagLogPage/,/^struct ListBlockView/' "$SRC")
if echo "$DL59SEG" | grep -qF 'Image(systemName: "square.and.arrow.up")' \
   && echo "$DL59SEG" | grep -qF '.accessibilityLabel(Lang.t("diag.export"))' \
   && ! echo "$DL59SEG" | grep -qF 'Text(Lang.t("diag.export"))' \
   && ! echo "$DL59SEG" | grep -qF 'frame(minHeight: 46)'; then
  ok "DL59-1 导出图标钮在位（统一符号 + 无障碍标签，文字胶囊零残留）"
else
  bad "DL59-1 导出钮形态漂移（图标缺失或文字胶囊回潮）"
fi
# DL59-2 黑卡间距同源机制锁：终端卡经设置族
# 内容框单点（settingsContentFrame）接入 +
# 安全区底距独立项在位；手抄间距字面（顶
# 126/81 / 横 20 / 底合成一行式）零残留——
# 顶距来源与设置页同源的源码面锁（量测面见
# 定案报告 §二对照表）。81 为顶距改判新值
# （用户 2026-11-28 裁定，fix_frame_top_
# inset_81.md），同入零残留防按新值手抄。
if echo "$DL59SEG" | grep -q 'settingsContentFrame()' \
   && echo "$DL59SEG" | grep -qF '.padding(.bottom, geo.safeAreaInsets.bottom)' \
   && ! echo "$DL59SEG" | grep -q 'padding(.top, 126)' \
   && ! echo "$DL59SEG" | grep -q 'padding(.top, 81)' \
   && ! echo "$DL59SEG" | grep -q 'padding(.horizontal, 20)' \
   && ! echo "$DL59SEG" | grep -q '40 + geo.safeAreaInsets.bottom'; then
  ok "DL59-2 黑卡间距同源（内容框单点 + 安全区底距，手抄字面零残留）"
else
  bad "DL59-2 黑卡间距同源缺失（单点未接入或手抄回潮）"
fi

echo "[60] 权限页呈现/交互调优（fix_permissions_uiux：图标列/行距/状态色分组/胶囊标示/整行命中/切换过渡——功能与状态口径零改动，PC44 组全数不破；fix_permissions_feedback63 追加：行注请求后才显/未请求文本去除/动作标示统一图标/文案缩短与已声明组归类，PU60-3 改判、PU60-6..8 新增）"
# PU60-1 图标列锁：PermKind.icon 映射在位且
# 13 项符号齐全（段内逐字核对；符号选型口径
# 见 fix_permissions_uiux §二）。
PU60ICON=$(sed -n '/var icon: String/,/^    }/p' "$PERMF")
if [ "$(grep -c 'var icon: String' "$PERMF")" = 1 ] \
   && [ "$(echo "$PU60ICON" | grep -c 'return "')" = 13 ] \
   && echo "$PU60ICON" | grep -qF '"bell.badge"' \
   && echo "$PU60ICON" | grep -qF '"photo.on.rectangle.angled"' \
   && echo "$PU60ICON" | grep -qF '"photo.badge.plus"' \
   && echo "$PU60ICON" | grep -qF '"arrow.triangle.2.circlepath"' \
   && echo "$PU60ICON" | grep -qF '"paperplane"'; then
  ok "PU60-1 权限行图标列（13 项符号映射齐全）"
else
  bad "PU60-1 图标列缺失或符号漂移"
fi
# PU60-2 状态色分组锁：可用态走成功令牌、受
# 阻态（已拒绝/受限制）统一警告色、成功/警告
# 令牌在呈现层各恰一处（statusTint 单点）。
if [ "$(grep -c 'case .granted, .enabled, .available, .lanOK,' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'case .denied, .restricted:' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'return T.success' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'return T.warning' "$PERMF")" = 1 ]; then
  ok "PU60-2 状态色分组（可用=成功/受阻=警告/余次级，单点）"
else
  bad "PU60-2 状态色分组漂移"
fi
# PU60-3 动作标示统一图标化锁（fix_permis-
# sions_feedback63 改判旧胶囊口径）：文字胶囊
# pillLabel 零残留、f13 喂点随胶囊退役删除；
# 标示收口 actionMark 单点（定义 1 + 调用 2：
# 请求 / 去系统设置），字形 PermGuideGlyph
# 全页同一枚（定义 1、实例化仅 actionMark 内
# 1 处），无障碍标签经 accessibilityLabel
# 保留原文语义，玻璃圆形态在位。
if [ "$(grep -c 'pillLabel' "$PERMF")" = 0 ] \
   && [ "$(grep -c 'private var f13' "$PERMF")" = 0 ] \
   && [ "$(grep -c 'func actionMark' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'actionMark(label: Lang.t(' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'struct PermGuideGlyph: Shape' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'PermGuideGlyph()' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'accessibilityLabel(label)' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'glassControl(radius: Radius.pill)' "$PERMF")" = 1 ]; then
  ok "PU60-3 动作标示统一图标（文字胶囊零残留、字形单点一枚）"
else
  bad "PU60-3 动作标示形态漂移（文字胶囊回潮或字形不统一）"
fi
# PU60-4 整行命中锁：行动作收口单点 + 整行钮
# （RowPressStyle radius 0）恰一，胶囊不再自
# 成嵌套钮（Button { 零处）。
if [ "$(grep -c 'func rowAction' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'RowPressStyle(radius: 0)' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'Button(action: act)' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'Button {' "$PERMF")" = 0 ]; then
  ok "PU60-4 整行命中（动作行整行成钮、无嵌套钮）"
else
  bad "PU60-4 整行命中形态漂移"
fi
# PU60-5 行距与过渡锁：长文行距（intro + 行
# 注）两处同式、状态切换 0.15 easeOut 一处、
# 图标字形封顶（min(f16, 24)）一处。
if [ "$(grep -c 'lineSpacing(f12 \* 0.55)' "$PERMF")" = 2 ] \
   && [ "$(grep -c 'easeOut(duration: 0.15)' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'min(f16, 24)' "$PERMF")" = 1 ]; then
  ok "PU60-5 行距/切换过渡/字形封顶在位"
else
  bad "PU60-5 行距或过渡缺失"
fi
# PU60-6 无功能行注显示条件锁（fix_permis-
# sions_feedback63 ①⑥）：noteIsNoFeature 集
# 合恰八项（远程推送经已声明组归类改判移出、
# 注改真实状态说明），showsNote 谓词单点且
# 逐项条件在位（标准面请求后结果集 / 本地网
# 络非未探针 / Face ID 可用），行注渲染经该
# 谓词把关恰一处。
PU60NOTE=$(sed -n '/var noteIsNoFeature: Bool/,/^    }/p' "$PERMF")
if [ "$(grep -c 'var noteIsNoFeature: Bool' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'func showsNote' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'if showsNote(kind, status)' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'return status != .unknown' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'return status == .available' "$PERMF")" = 1 ] \
   && [ "$(grep -c 'case .granted, .denied, .restricted, .writeOnly:' "$PERMF")" = 1 ] \
   && echo "$PU60NOTE" | grep -qF '.calendar' \
   && echo "$PU60NOTE" | grep -qF '.faceID' \
   && echo "$PU60NOTE" | grep -qF '.localNetwork' \
   && echo "$PU60NOTE" | grep -qF '.reminders' \
   && ! echo "$PU60NOTE" | grep -qF '.pushEnv'; then
  ok "PU60-6 无功能行注请求后才显（集合八项 + 谓词逐项条件）"
else
  bad "PU60-6 行注显示条件漂移"
fi
# PU60-7 「未请求」文本去除锁（fix_permis-
# sions_feedback63 ②）：trailing 段内状态词
# 渲染被「未定 + 请求标示在位」门挡恰一处；
# 状态词本体（Lang.t(status.langKey)）仍在
# 段内（余状态照常呈现、状态值不动）。
PU60TRAIL=$(sed -n '/private func trailing/,/^    }/p' "$PERMF")
if echo "$PU60TRAIL" | grep -qF 'if !(status == .notDetermined' \
   && echo "$PU60TRAIL" | grep -qF '&& showsRequest(kind, status)) {' \
   && echo "$PU60TRAIL" | grep -qF 'Text(Lang.t(status.langKey))'; then
  ok "PU60-7 未请求文本去除（与请求标示并置时隐去、余状态不动）"
else
  bad "PU60-7 未请求去除门缺失或状态词本体受损"
fi
# PU60-8 文案缩短/归类改写锁（fix_permis-
# sions_feedback63 ③⑥）：中英四键新文案逐字
# 在位、旧长文特征片段五包零残留、远程推送
# 注五语均已脱离无功能句（归类=声明+账号侧
# 配套）、后台注已脱离声明口径起句。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
packs = {}
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        packs[c] = json.load(f)
new = {
  "zh-CN": {
    "perm.note_notifications": "桥接长操作完成时提醒",
    "perm.note_location": "天气使用：显示所在城市的天气",
    "perm.note_live_activities":
        "桥接长操作与场景运行正在使用",
    "perm.note_background":
        "系统调度中：热修复指令拉取与附件快照清理",
    "perm.note_push_env": "发送需账号配套"},
  "en-US": {
    "perm.note_notifications":
        "Notifies when bridge long operations finish",
    "perm.note_location":
        "In use by Weather: your city's weather",
    "perm.note_live_activities":
        "In use by bridge long operations and scenario runs",
    "perm.note_background":
        "System-scheduled: hot-fix fetch and "
        "attachment snapshot cleanup",
    "perm.note_push_env":
        "Sending requires account-side setup"},
}
for c, kv in new.items():
    for k, v in kv.items():
        if packs[c].get(k) != v:
            sys.exit(1)
old_frag = ["同一授权", "同一授權",
            "same authorization", "同じ許可です",
            "같은 권한입니다", "中开关", "中開關",
            "toggle in Settings", "で切り替えます",
            "에서 전환합니다", "已声明，系统调度",
            "已宣告，系統排程", "Declared and scheduled",
            "宣言済みでシステムがスケジュールします",
            "선언되었고 시스템이 예약합니다"]
for c in codes:
    blob = "\n".join(str(v) for v in packs[c].values())
    if any(fr in blob for fr in old_frag):
        sys.exit(1)
nofeat = {"暂无功能使用", "暫無功能使用",
          "No feature uses it yet",
          "まだ使う機能はありません",
          "아직 사용하는 기능이 없습니다"}
for c in codes:
    if packs[c]["perm.note_push_env"] in nofeat:
        sys.exit(1)
sys.exit(0)
PYEOF
then
  ok "PU60-8 文案缩短 + 已声明组归类措辞（新文案在位、旧长文零残留）"
else
  bad "PU60-8 文案漂移（新文案缺失或旧长文回潮）"
fi

echo "[62] 实况按功能样式设计（impl_liveops_design：kind 图标/色单点 / phase 参与渲染 / 灵动岛成卡治长黑条 / 终态步名）"
# LV62-1 样式单点：LiveOpStyle 恰一处；五 kind
# 图标各恰一（映射本体）；五 kind 主题色以
# kindTint 分支在位。
if [ "$(grep -c 'enum LiveOpStyle' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c 'wrench.and.screwdriver.fill' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c '"checklist"' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c 'square.and.arrow.up.fill' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c 'square.and.arrow.down.fill' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c 'antenna.radiowaves.left.and.right' "$LIVEWIDGET")" = 1 ] \
   && has 'case .bridgeOp: return .indigo' "$LIVEWIDGET" \
   && has 'case .scenario: return .teal' "$LIVEWIDGET" \
   && has 'case .export: return .orange' "$LIVEWIDGET" \
   && has 'case .restore: return .purple' "$LIVEWIDGET" \
   && has 'case .bridge: return .blue' "$LIVEWIDGET"; then
  ok "LV62-1 kind 图标/主题色单点（五 kind 全映射）"
else
  bad "LV62-1 kind 样式单点缺失或映射漂移"
fi
# LV62-2 phase 参与渲染：三阶段覆盖图标各恰
# 一、symbol/tint 双函数以 (kind, phase) 入参
# 在位（终态/等待态覆盖 kind 本体的单点）。
if [ "$(grep -c 'checkmark.circle.fill' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c 'exclamationmark.circle.fill' "$LIVEWIDGET")" = 1 ] \
   && [ "$(grep -c 'pause.circle.fill' "$LIVEWIDGET")" = 1 ] \
   && has 'static func symbol(kind: LiveOpKind,' "$LIVEWIDGET" \
   && has 'static func tint(kind: LiveOpKind,' "$LIVEWIDGET"; then
  ok "LV62-2 phase 渲染分支在位（done/failed/waiting 覆盖）"
else
  bad "LV62-2 phase 渲染分支缺失"
fi
# LV62-3 minimal 态新形态：旧无色圆点零残留；
# minimal 段以 kind/阶段图标呈现；全文件经样
# 式单点取图标共五处（徽章 / 展开 trailing /
# compact 两态 / minimal）。
SEG62=$(awk '/} minimal: {/,/liveOpsKeylineTint/' "$LIVEWIDGET")
if [ "$(grep -c 'Circle()' "$LIVEWIDGET")" = 0 ] \
   && [ "$(grep -c 'Image(systemName: LiveOpStyle.symbol' "$LIVEWIDGET")" = 5 ] \
   && printf '%s' "$SEG62" | grep -q 'Image(systemName: LiveOpStyle.symbol'; then
  ok "LV62-3 minimal 态图标化（无色圆点零残留）"
else
  bad "LV62-3 minimal 态形态漂移"
fi
# LV62-4 终态步名接线：导出/导入 defer 与场
# 景 finish 的 end 步名走 liveops.done/failed
# 本地化键（机器词 export/import/finalCode
# 直传已退役）；桥操作 end 保留工具名作步名
# （B34-6 计数不破，见报告口径）。
if [ "$(grep -c 'liveops.done' "$SRC")" = 2 ] \
   && [ "$(grep -c 'liveops.failed' "$SRC")" = 2 ] \
   && [ "$(grep -c 'liveops.running' "$SRC")" = 2 ] \
   && [ "$(grep -c 'liveops.done' "$UITEST")" = 1 ] \
   && [ "$(grep -c 'liveops.failed' "$UITEST")" = 2 ] \
   && [ "$(grep -c 'step: "export"' "$SRC")" = 0 ] \
   && [ "$(grep -c 'step: "import"' "$SRC")" = 0 ] \
   && [ "$(grep -c 'step: finalCode)' "$UITEST")" = 0 ] \
   && [ "$(grep -c 'step: job.code)' "$UITEST")" = 0 ]; then
  ok "LV62-4 终态步名本地化接线（导出/导入/场景）"
else
  bad "LV62-4 终态步名接线漂移"
fi
# LV62-5 长黑条治法：展开三区在位、徽章锚两
# 处共用（锁屏 + 展开 leading）、背景淡染与
# keyline 着色齐备（keylineTint 为 DynamicIsland
# 自有方法直调——原 View 扩展包法类型不符，
# 0.9.63 组版构建实证后纠正，沿革见
# impl_liveops_design.md 组版附记）。
if [ "$(grep -c 'DynamicIslandExpandedRegion' "$LIVEWIDGET")" = 3 ] \
   && [ "$(grep -c 'LiveOpBadge(' "$LIVEWIDGET")" = 2 ] \
   && has 'activityBackgroundTint' "$LIVEWIDGET" \
   && has 'keylineTint' "$LIVEWIDGET" \
   && has 'struct LiveOpBadge' "$LIVEWIDGET"; then
  ok "LV62-5 灵动岛成卡 + 锁屏卡面着色在位"
else
  bad "LV62-5 展开成卡形态缺失"
fi

echo "[63] 全面审计批 4 编辑器遗留（fix_audit_batch4_editor.md：B-04/SL-16 校验/B-01/F-13/B-06/M-10/M-09/F-16/B-03）"
# EB63-1 URL 抑制逐字移植（B-04/m-03）：up-
# dateSlash 段内含剥前导集 + 大小写不敏感三前
# 缀判；旧口径两判（前字 : 或 / 抑制、所在词
# 词首 hasPrefix）段内零残留。
EB63SEG_US=$(awk '/func updateSlash/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if echo "$EB63SEG_US" | grep -q 'leadChars' \
  && echo "$EB63SEG_US" | grep -q 'tokLow.hasPrefix("http://")' \
  && echo "$EB63SEG_US" | grep -q 'tokLow.hasPrefix("https://")' \
  && echo "$EB63SEG_US" | grep -q 'tokLow.hasPrefix("www.")' \
  && ! echo "$EB63SEG_US" | grep -q 'chars\[ts - 1\] == ":"' \
  && ! echo "$EB63SEG_US" | grep -q 'word.hasPrefix'; then
  ok "EB63-1 斜杠 URL 抑制与 Web 逐字同面（剥前导 + 大小写不敏感）"
else
  bad "EB63-1 URL 抑制判定面漂移"
fi
# EB63-2 链接提交校验面（SL-16）：applyLink
# 段内为解析 + scheme 白名单 + host 非空；旧
# 前缀判段内零残留。
EB63SEG_AL=$(awk '/func applyLink/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if echo "$EB63SEG_AL" | grep -q 'URL(string: trimmed)' \
  && echo "$EB63SEG_AL" | grep -q 'scheme == "http" || scheme == "https"' \
  && ! echo "$EB63SEG_AL" | grep -q 'trimmed.hasPrefix("http://")'; then
  ok "EB63-2 链接校验为解析 + 协议白名单（Web submit_slash_link 同面）"
else
  bad "EB63-2 链接校验面漂移"
fi
# EB63-3 公式块转换保内容（B-01）：mathBlock
# case 段内含空支（旧三行逐字产出）与非空支
# （围栏夹原 runs）；无条件整体替换式赋值消
# 失（段内 b.runs = 赋值恰 2 = 两支各一）。
EB63SEG_MB=$(awk '/case "mathBlock":/ {f=1} f {print} f && /case "callout":/ {exit}' "$SRC")
if echo "$EB63SEG_MB" | grep -q 'if b.text.isEmpty' \
  && echo "$EB63SEG_MB" | grep -qF '["text": "$$\n"]] + b.runs' \
  && echo "$EB63SEG_MB" | grep -qF '"$$\n\n$$"' \
  && [ "$(echo "$EB63SEG_MB" | grep -c 'b.runs = ')" = 2 ]; then
  ok "EB63-3 公式块转换围栏保正文（空支产出与旧逐字同）"
else
  bad "EB63-3 公式块转换保内容形态漂移"
fi
# EB63-4 链接表单延迟剥离（F-13）：applyIn-
# lineSlash 段内 link 记账行号 < 首个 remove-
# RunRange 行号（打开不剥）；快照含 token 长；
# applyLink 段内提交剥除 + 同式换算在位；
# applySlash 段内 link 不落盘门在位。
EB63SEG_AIS=$(awk '/func applyInlineSlash/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
EB63_LN_LINK=$(echo "$EB63SEG_AIS" | grep -n 'if act == "link"' | head -1 | cut -d: -f1)
EB63_LN_RM=$(echo "$EB63SEG_AIS" | grep -n 'removeRunRange' | head -1 | cut -d: -f1)
EB63SEG_AS=$(awk '/func applySlash/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ -n "$EB63_LN_LINK" ] && [ -n "$EB63_LN_RM" ] \
  && [ "$EB63_LN_LINK" -lt "$EB63_LN_RM" ] \
  && echo "$EB63SEG_AIS" | grep -q 'linkTokenLen = slashTokenLen' \
  && echo "$EB63SEG_AL" | grep -q 'removeRunRange(b, start: linkTokenStart' \
  && echo "$EB63SEG_AL" | grep -q 'adjustedSel(linkSelStart,' \
  && echo "$EB63SEG_AS" | grep -q 'if act != "link" { scheduleSave() }' \
  && grep -q 'private var linkTokenLen = 0' "$SRC"; then
  ok "EB63-4 链接打开不剥不压不落盘、提交才剥（取消零丢字）"
else
  bad "EB63-4 链接延迟剥离链漂移"
fi
# EB63-5 sheet 前清斜杠态（B-06/m-05）：三
# sheet 呈现真值各有一枚 onChange 清面板态
# （计数 3）；清法只置 slashBlockId（token
# 文本与 linkForm 会话不动）。
if [ "$(grep -c 'if v { editor.slashBlockId = nil }' "$SRC")" = 3 ] \
  && grep -q '.onChange(of: ui.showPhotoPicker)' "$SRC" \
  && grep -q '.onChange(of: ui.showFilePicker)' "$SRC" \
  && grep -q '.onChange(of: editor.showReplacePicker)' "$SRC"; then
  ok "EB63-5 三 sheet 唤起前清斜杠面板态（幽灵面板根治）"
else
  bad "EB63-5 sheet 前清斜杠态漏斗漂移"
fi
# EB63-6 拾起取消清菜单（M-10）：clearDrag-
# State 单点定义在位（两菜单守卫清）；行侧调
# 用恰 2（onCancel + onDisappear）；commit-
# Drag 段不经此路（原地松手留菜单定案）。
EB63SEG_CD=$(awk '/func commitDrag/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if grep -q 'func clearDragState(for id: String)' "$SRC" \
  && [ "$(grep -c 'editor.clearDragState(for: block.id)' "$SRC")" = 2 ] \
  && ! echo "$EB63SEG_CD" | grep -q 'clearDragState'; then
  ok "EB63-6 拖拽取消/卸载单点复位含拾起菜单（落位路不经）"
else
  bad "EB63-6 拖拽复位单点漂移"
fi
# EB63-7 flow 不钳（M-09）：commitDrag 落点钳
# 制与 dragShift 栏界门同源同式——两段均含
# twoPaneIndependent 条件（flow 下两门皆开）。
EB63SEG_DS=$(awk '/private var dragShift/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if echo "$EB63SEG_CD" | grep -q 'columnsActive, twoPaneIndependent,' \
  && echo "$EB63SEG_DS" | grep -q 'editor.twoPaneIndependent,'; then
  ok "EB63-7 拖拽钳制仅 independent（落点/让位两门同源）"
else
  bad "EB63-7 flow 钳制门漂移"
fi
# EB63-8 拖拽维护 layout 锚（F-16）：commit-
# Drag 段内含重排前分界数快照（normalize-
# Boundary）+ 同数切分重写 + Diag 打点。
if echo "$EB63SEG_CD" | grep -q 'Self.normalizeBoundary(blocks: blocks,' \
  && echo "$EB63SEG_CD" | grep -q '"left": Array(ids\[..<ab\])' \
  && echo "$EB63SEG_CD" | grep -q 'drag anchor maintained'; then
  ok "EB63-8 拖拽重排同数维护 independent 锚名单"
else
  bad "EB63-8 拖拽锚维护漂移"
fi
# EB63-9 面板锚改光标行（B-03）：行锚字段 +
# updateSlash 绑定写入 + 调用方同矩形传参 +
# slashLayer 锚优先（行底 +10）与异块回退门
# （slashAnchorBlockId == blk?.id）全在位。
EB63SEG_SL=$(awk '/private var slashLayer/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if grep -q 'var slashAnchorBlockId: String?' "$SRC" \
  && echo "$EB63SEG_US" | grep -q 'slashAnchorBlockId = block.id' \
  && grep -q 'caretLineTop: caretLineTop,' "$SRC" \
  && echo "$EB63SEG_SL" | grep -q 'editor.slashAnchorBlockId == blk?.id' \
  && echo "$EB63SEG_SL" | grep -q 'editor.slashAnchorBottomY + 10' \
  && echo "$EB63SEG_SL" | grep -q ': top + bh + 10'; then
  ok "EB63-9 斜杠面板纵向锚 = 光标行（缺失/异块回退块底）"
else
  bad "EB63-9 面板光标行锚漂移"
fi

echo "[64] 媒体解码管线收口（审计批 3）"
# MD64-1 管线单点：MediaDecode 本体（解码/共
# 享缓存/帧时长取数）+ ImageIO 缩略图降采样
# 路 + 三字典（GIF/APNG/WebP）取数在位；旧
# decodeImage 零残留（与 SVG42-1 分工：彼锁
# publish 汇合调用面、此锁管线本体）。
if has 'enum MediaDecode' "$SRC" \
   && has 'static func image(for key' "$SRC" \
   && has 'NSCache<NSString, UIImage>' "$SRC" \
   && has 'CGImageSourceCreateThumbnailAtIndex' "$SRC" \
   && has 'kCGImagePropertyAPNGDictionary' "$SRC" \
   && has 'kCGImagePropertyWebPDictionary' "$SRC" \
   && [ "$(grep -cF 'decodeImage(' "$SRC")" = 0 ]; then
  ok "MD64-1 解码管线单点（缓存 + 降采样 + 三字典帧时长、旧路零残留）"
else
  bad "MD64-1 解码管线漂移"
fi
# MD64-2 帧时长裁定表驱动：MomentImageLoad
# .swift 纯核心（MediaFrameTiming）以宿主
# swiftc 编译运行——候选序（GIF 双位/APNG
# 位/WebP 位）+ 零负跳过 + 下限钳 + 缺省回
# 落，任一不符即红（沿 IMG55-2 先例）。
MD64D=$(mktemp -d)
cat > "$MD64D/main.swift" <<'MDEOF'
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if !cond {
        failures += 1
        print("FAIL \(name)")
    }
}

check(MediaFrameTiming.resolve(candidates: [])
        == 0.1, "empty default")
check(MediaFrameTiming.resolve(candidates: [nil, nil])
        == 0.1, "nils default")
check(MediaFrameTiming.resolve(candidates: [0.05])
        == 0.05, "gif unclamped hit")
check(MediaFrameTiming.resolve(candidates: [nil, 0.2])
        == 0.2, "clamped fallback hit")
check(MediaFrameTiming.resolve(candidates: [0, 0.3])
        == 0.3, "zero skipped")
check(MediaFrameTiming.resolve(candidates: [-1, 0.4])
        == 0.4, "negative skipped")
check(MediaFrameTiming.resolve(candidates: [0.001])
        == 0.02, "floor clamp")
check(MediaFrameTiming.resolve(
        candidates: [nil, nil, nil, nil, 0.12, nil])
        == 0.12, "webp position hit")
check(MediaFrameTiming.resolve(
        candidates: [nil, nil, 0.08, nil, nil, nil])
        == 0.08, "apng position hit")
check(MediaDecodePolicy.blockMaxPixel == 2048,
      "block cap value")

if failures == 0 {
    print("MEDIA_TIMING_PASS")
} else {
    print("MEDIA_TIMING_FAIL \(failures)")
}
MDEOF
SWIFTC64=""
for c64 in "$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "/opt/tc/swift-6.4.2-RELEASE-ubuntu22.04/usr/bin/swiftc" \
           "$(command -v swiftc 2>/dev/null)"; do
  if [ -n "$c64" ] && [ -x "$c64" ]; then
    SWIFTC64="$c64"; break
  fi
done
if [ -n "$SWIFTC64" ] \
   && "$SWIFTC64" -O -o "$MD64D/media_test" \
        "$IMGCORE" "$MD64D/main.swift" 2>"$MD64D/err.log" \
   && [ "$("$MD64D/media_test" 2>/dev/null)" = "MEDIA_TIMING_PASS" ]; then
  ok "MD64-2 帧时长裁定表驱动全过（候选序/下限钳/缺省回落）"
else
  bad "MD64-2 帧时长裁定表驱动失败（swiftc=$SWIFTC64，详见编译/运行输出）"
  sed 's/^/    MD64-2: /' "$MD64D/err.log" | head -5
  "$MD64D/media_test" 2>/dev/null | sed 's/^/    MD64-2: /' | head -5
fi
rm -rf "$MD64D"
# MD64-3 块内动图承载（AUD-D-01）：AnimImage-
# View 定义恰 1、五面消费恰 5（ItemImageView
# 瓦/封面共用、图块、MD 图、图文卡两面）；
# 块内媒体面 Image(uiImage: 代码残留恰 1 =
# 头像自定义图（非媒体解码面、不在本批口径）。
if [ "$(grep -c 'struct AnimImageView' "$SRC")" = 1 ] \
   && [ "$(grep -c 'AnimImageView(' "$SRC")" = 5 ] \
   && [ "$(grep -cF 'Image(uiImage:' "$SRC")" = 1 ]; then
  ok "MD64-3 动图承载五面统一（AnimImageView 定义 1 + 消费 5）"
else
  bad "MD64-3 动图承载漂移（AnimImageView=$(grep -c 'AnimImageView(' "$SRC") Image(uiImage:=$(grep -cF 'Image(uiImage:' "$SRC")）"
fi
# MD64-4 降采样接线（AUD-E-04/D-06）：块内四
# 视图的 load 调用全带 blockMaxPixel 桶恰 10
# （Item 3 + 图块 3 + MD 1 + 图文 3）；load
# 双入口默认参数在位（图片页不传 = 全尺寸
# 口径不破）。
if [ "$(grep -c 'maxPixel: MediaDecode.blockMaxPixel' "$SRC")" = 10 ] \
   && [ "$(grep -c 'maxPixel: CGFloat? = nil' "$SRC")" = 2 ]; then
  ok "MD64-4 降采样接线（块内 10 调用点带桶 + 双入口默认 nil）"
else
  bad "MD64-4 降采样接线漂移（带桶=$(grep -c 'maxPixel: MediaDecode.blockMaxPixel' "$SRC") 默认=$(grep -c 'maxPixel: CGFloat? = nil' "$SRC")）"
fi
# MD64-5 视频自然比例 + 失败态（AUD-D-04）：
# holder 比例/失败双状态 + 轨道回填与失败观
# 察两方法 + 失败面符号 + 播放失败行 + 临时
# 名扩展名派生（恒名 .mov 字面零残留）。
if has '@Published var aspect' "$SRC" \
   && has '@Published var failed' "$SRC" \
   && has 'private func resolveAspect' "$SRC" \
   && has 'private func watchItem' "$SRC" \
   && has 'video.badge.exclamationmark' "$SRC" \
   && has 'VIDEO play failed' "$SRC" \
   && has 'preferredFilenameExtension' "$SRC" \
   && [ "$(grep -cF 'video-\(fid).mov' "$SRC")" = 0 ]; then
  ok "MD64-5 视频自然比例 + 失败态 + 临时名派生在位"
else
  bad "MD64-5 视频形态漂移"
fi

# [65] 审计批 6 首页细项（fix_audit_batch6_home）
echo "[65] 审计批 6 首页细项（AUD-A-01/04/05/06/07）"
# HM65-1 封面 URL 白名单单点（AUD-A-01）：cover
# 段内 image/gallery 两支过 safeCoverURL、img-
# TextCard 支无 URL 路（与 Web cover_in_node 同
# 序）。段界：safeCoverURL 定义至 attachment 支。
CV65=$(awk '/static func safeCoverURL/,/case "attachment":/' "$SRC")
ITC65=$(echo "$CV65" | awk '/case "imgTextCard", "imageTextRow":/,/case "gallery":/')
if [ "$(echo "$CV65" | grep -cF 'MemoItem.safeCoverURL(')" = 2 ] \
   && ! echo "$ITC65" | grep -q 'url'; then
  ok "HM65-1 封面白名单单点（image/gallery 过检、图文卡无 URL 路）"
else
  bad "HM65-1 封面 URL 口径漂移（AUD-A-01）"
fi
# HM65-2 页眉命中阈值（AUD-A-04）：< 1 恰两处
# （头像/搜索胶囊）、< 0.5 零处（死区口径回潮
# 即红）；Sanitizer 门带由 F30-21 锚 30。
if [ "$(grep -cF 'allowsHitTesting(compactP < 1)' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'allowsHitTesting(compactP < 0.5)' "$SRC")" = 0 ]; then
  ok "HM65-2 页眉命中阈值 p<1 ×2、死区阈值零回潮"
else
  bad "HM65-2 页眉命中阈值漂移（AUD-A-04）"
fi
# HM65-3 网格组头大写（AUD-A-05）：组头段（至
# LazyVGrid）含 .textCase(.uppercase)。
GH65=$(awk '/Text\(group.title\)/,/LazyVGrid/' "$SRC")
if echo "$GH65" | grep -qF '.textCase(.uppercase)'; then
  ok "HM65-3 网格组头大写呈现 在位"
else
  bad "HM65-3 网格组头缺大写呈现（AUD-A-05）"
fi
# HM65-4 图文方卡药丸单点（AUD-A-06）：段内走
# squareFoldPill、无内联自绘收起钮。段界至
# squareTags。
SI65=$(awk '/private func squareImageCard/,/private func squareTags/' "$SRC")
if echo "$SI65" | grep -qF 'squareFoldPill(expand: expand,' \
   && ! echo "$SI65" | grep -qF 'Button(Lang.t("list.collapse"))'; then
  ok "HM65-4 图文方卡折叠药丸走 squareFoldPill 单点"
else
  bad "HM65-4 图文方卡药丸漂移（AUD-A-06）"
fi
# HM65-5 列表动作辞焦（AUD-A-07）：左滑段与方
# 卡长按菜单段各恰四处 resignSearch()（原动作
# 两处 + U5 home.row 注册面同体动作两处——U 批
# 落码后基数回写，机制不变、计数随同体声明同
# 步；同体动作口径见 F30-2/PC44-6 的 U5 回写）。
# fix_home_row_registry 改判 4→2：注册单点
# 化后行同体动作移出两段、收口 makeRowEntry
# 单点（两形态共用一对），段内只剩原动作两
# 处；四动作辞焦机制不变，行动作辞焦由
# makeRowEntry 承接（F30-2 基数 11 含之）。
SW65=$(awk '/swipeActions\(edge: .trailing/,/private func titleRow/' "$SRC")
CM65=$(awk '/[.]contextMenu [{]/,/private func squareTextCard/' "$SRC")
if [ "$(echo "$SW65" | grep -cF 'resignSearch()')" = 2 ] \
   && [ "$(echo "$CM65" | grep -cF 'resignSearch()')" = 2 ]; then
  ok "HM65-5 左滑/网格菜单四动作辞焦在位"
else
  bad "HM65-5 列表动作辞焦缺失（AUD-A-07）"
fi
# [66] 卡片防误触机制统一收口（impl_card_guard_unify：codeBlock/embedCard 接入 cardMenuTypes + 结构守卫）
echo "[66] 卡片防误触机制统一（impl_card_guard_unify.md：成员集单点 + 合并守卫 + 选中描边同点消费）"
# CG66-1 成员集：cardMenuTypes 恰 11 型且含 codeBlock/embedCard。
CM66=$(awk '/static let cardMenuTypes/,/\]/' "$SRC")
if [ "$(echo "$CM66" | grep -o '"[a-zA-Z-]*"' | sort -u | wc -l | tr -d ' ')" = 11 ] \
   && echo "$CM66" | grep -qF '"codeBlock"' \
   && echo "$CM66" | grep -qF '"embedCard"'; then
  ok "CG66-1 卡片机制成员集 11 型（基线 9 + codeBlock/embedCard）"
else
  bad "CG66-1 成员集漂移（应恰 11 型含 codeBlock/embedCard）"
fi
# CG66-2 非接入型不被误伤：纯文本流五型不在成员集内。
if ! echo "$CM66" | grep -qE '"(paragraph|heading|todo|quote|callout)"'; then
  ok "CG66-2 文本流五型（段落/标题/待办/引用/提示）不在成员集"
else
  bad "CG66-2 文本流块型误入成员集（合并模型被剥夺）"
fi
# CG66-3 editCardTypes 恒 5 型且不含新成员（新成员菜单只出删除）。
EC66=$(awk '/static let editCardTypes/,/\]/' "$SRC")
if [ "$(echo "$EC66" | grep -o '"[a-zA-Z-]*"' | sort -u | wc -l | tr -d ' ')" = 5 ] \
   && ! echo "$EC66" | grep -qE '"(codeBlock|embedCard)"'; then
  ok "CG66-3 editCardTypes 恒 5 型、新成员无编辑项（删除单项菜单）"
else
  bad "CG66-3 editCardTypes 漂移（新成员应只出删除此块）"
fi
# CG66-4 分类单点：isStructuralAtomic 定义式恒为
# !isText || cardMenuTypes 成员判定，全文件 cardMenuTypes.contains 恰两处消费（本谓词 + BlockRow.isCardType）。
if has 'var isStructuralAtomic: Bool' "$SRC" \
   && has '!isText || EditorModel.cardMenuTypes.contains(type)' "$SRC" \
   && [ "$(grep -cF 'cardMenuTypes.contains' "$SRC")" = 2 ]; then
  ok "CG66-4 结构原子分类单点（isStructuralAtomic）+ 成员集恰两处消费"
else
  bad "CG66-4 分类单点漂移（定义式/消费点数不符）"
fi
# CG66-5 退格守卫：mergeBlockBackward 段含自身守卫支 + prev 分类 + 专属 Diag。
MB66=$(awk '/func mergeBlockBackward/,/func mergeBlockForward/' "$SRC")
if echo "$MB66" | grep -qF '} else if b.isStructuralAtomic {' \
   && echo "$MB66" | grep -qF 'prev.isText && !prev.isStructuralAtomic' \
   && echo "$MB66" | grep -qF 'EDIT merge backspace guarded self'; then
  ok "CG66-5 段首退格双向守卫（自身不并出 / 成员前驱落选中支）"
else
  bad "CG66-5 段首退格守卫缺件（mergeBlockBackward）"
fi
# CG66-6 前删守卫：mergeBlockForward 段含自身守卫支 + next 分类 + 专属 Diag。
MF66=$(awk '/func mergeBlockForward/,/func mergeForwardFromKey/' "$SRC")
if echo "$MF66" | grep -qF 'if b.isStructuralAtomic {' \
   && echo "$MF66" | grep -qF 'next.isText && !next.isStructuralAtomic' \
   && echo "$MF66" | grep -qF 'EDIT merge fwd guarded self'; then
  ok "CG66-6 块末前向删除双向守卫（自身不吸收 / 成员后继落选中支）"
else
  bad "CG66-6 前向删除守卫缺件（mergeBlockForward）"
fi
# CG66-7 列表镜像：首项退格两支与末项前删一支同点分类。
LB66=$(awk '/func mergeListItemBackward/,/func mergeListItemForward/' "$SRC")
LF66=$(awk '/func mergeListItemForward/,/func clearDragState/' "$SRC")
if echo "$LB66" | grep -qF '!blocks[li - 1].isStructuralAtomic' \
   && echo "$LB66" | grep -qF 'blocks[li - 1].isStructuralAtomic,' \
   && echo "$LF66" | grep -qF 'next.isText && !next.isStructuralAtomic'; then
  ok "CG66-7 列表项合并镜像三支同点分类（代码块邻接不被项合并溶解）"
else
  bad "CG66-7 列表镜像守卫缺件"
fi
# CG66-8 选中描边：F-08 描边段走 isStructuralAtomic、旧 !block.isText 直判清零于该段。
OL66=$(awk '/原子块选中态描边/,/lineWidth: 2/' "$SRC")
if echo "$OL66" | grep -qF 'block.isStructuralAtomic' \
   && ! echo "$OL66" | grep -qF '!block.isText'; then
  ok "CG66-8 选中描边与守卫同点（代码块被选中同显描边）"
else
  bad "CG66-8 选中描边分类漂移"
fi
echo "[67] 桥场景库 M3b 写景四景（plan_bridge_m3.md §2.2，定案 impl_bridge_m3b_scenarios.md）"
# B67-1 注册与现形：四景步表分发全在位；快照
# 恢复景随工具批真接线——wiringMissing 标记
# 清零、可用性 arm_required 现形 + run 受理
# 武装拒绝两点齐全（wiring 通用机制保留在位
# 供未来未落景使用，本景不再命中）。
if has 'case "delete_restore_roundtrip"' "$BSCEN" \
   && has 'case "drag_semantic_reorder"' "$BSCEN" \
   && has 'case "create_transition"' "$BSCEN" \
   && has 'case "snapshot_restore_drill"' "$BSCEN" \
   && ! has 'wiringMissing: true' "$BSCEN" \
   && has 'return "arm_required"' "$BSCEN" \
   && has 'code: "arm_required"' "$BSCEN"; then
  ok "B67-1 M3b 四景注册（四景分发 + 快照景 arm 武装门现形/拒绝）"
else
  bad "B67-1 M3b 注册形态漂移"
fi
# B67-2 夹具链：建篇同路（create + 登记集）
# 与收尾清理链（softRemove + commitPending
# Deletion + 注销登记 + SCENARIO 打点）在位；
# journal fixture.ids 由 ctx 在 persist 同步。
if has 'UITestFixture.register' "$BSCEN" \
   && has 'SCENARIO fixture create' "$BSCEN" \
   && has 'SCENARIO fixture cleanup' "$BSCEN" \
   && has 'softRemove' "$BSCEN" \
   && has 'commitPendingDeletion' "$BSCEN" \
   && has 'run.fixtureIds = ctx.fixtureIds' "$BSCEN"; then
  ok "B67-2 夹具建篇/登记/收尾清理链 + journal 同步在位"
else
  bad "B67-2 夹具链缺失"
fi
# B67-3 删除恢复景：软删/恢复/永删内部同路 +
# 恢复守卫（最近待删比对）+ includePermanent
# 参数声明在位。
if has 'BridgeWriteTools.softDelete' "$BSCEN" \
   && has 'BridgeWriteTools.restoreDeleted' "$BSCEN" \
   && has 'BridgeWriteTools.deletePermanent' "$BSCEN" \
   && has 'pendingDeletion?.id' "$BSCEN" \
   && has 'key: "includePermanent"' "$BSCEN"; then
  ok "B67-3 删除恢复景（内部同路/恢复守卫/永删段参数）"
else
  bad "B67-3 删除恢复景形态漂移"
fi
# B67-4 重排景：移块内部同路 + 导航通道重开/
# 关闭在位（块序证据走库镜像 id/type 序）。
if has 'BridgeWriteTools.moveBlock' "$BSCEN" \
   && has 'BridgeEditorTools.open' "$BSCEN" \
   && has 'requestClose' "$BSCEN"; then
  ok "B67-4 重排景（移块 + 导航重开腿）"
else
  bad "B67-4 重排景形态漂移"
fi
# B67-5 新建景：settle 解析复用单一解析器 +
# 基线护栏常量 + degraded 结论口径在位。
if has 'BridgeCreateSettleParser.parseLine' "$BSCEN" \
   && has 'settleMsGuard' "$BSCEN" \
   && has '"degraded"' "$BSCEN"; then
  ok "B67-5 新建景（settle 解析/护栏/degraded）"
else
  bad "B67-5 新建景形态漂移"
fi
# B67-6 高危声明：整场两段的景恰两条（删除恢
# 复 + 快照恢复；分发器无参数条件两段，永删
# 段在场内故整景从严，偏差记见落码报告）。
if [ "$(grep -c 'containsHighRisk: true' "$BSCEN")" = 2 ]; then
  ok "B67-6 高危声明恰两景（场级两段从严口径）"
else
  bad "B67-6 高危声明漂移（=$(grep -c 'containsHighRisk: true' "$BSCEN")）"
fi
# B67-7 快照恢复景步表（工具批真接线，定案
# impl_bridge_backup_restore.md）：步表函数在
# 位 + 自取快照走 takeSnapshot 强制新取（非会
# 话复用）+ 恢复走 BridgeBackupTools 内部同
# 路（与工具本体单一实现）+ armRestore 参数
# 声明 + 恢复守卫结论键在位。
if has 'snapshotRestoreDrillSteps' "$BSCEN" \
   && has 'takeSnapshot(' "$BSCEN" \
   && has 'BridgeBackupTools' "$BSCEN" \
   && has 'key: "armRestore"' "$BSCEN" \
   && has '"restoreGuard"' "$BSCEN"; then
  ok "B67-7 快照恢复景步表（自取快照/内部同路恢复/武装参数/守卫）"
else
  bad "B67-7 快照恢复景步表缺失"
fi

echo "[68] 自检覆盖 U2/U3/U5（矩阵 plan_selftest_coverage.md §6.1/§6.2/§6.4，定案 impl_selftest_u2u3u5.md）"
# U68-1 U2 地基：BlockState face 通道五字段 +
# 三处回报点（行槽同值 / image 子视图 −1 /
# gallery 子视图 −1）。
if has 'var faceMinX' "$SRC" \
   && has 'var faceRadius: CGFloat = -2' "$SRC" \
   && has 'block.faceMinX = block.frameMinX' "$SRC" \
   && [ "$(grep -c 'block.faceRadius = -1' "$SRC")" -ge 2 ]; then
  ok "U68-1 face 通道（字段 + 行槽/图/gallery 三回报点）"
else
  bad "U68-1 face 通道缺件"
fi
# U68-2 U2 斜杠 cap 通道：slashPanelMaxH 同点
# 回写 + 注册面两键。
if has 'slashPanelMaxH' "$SRC" \
   && has '"panelH"' "$SRC" \
   && has '"panelMaxH"' "$SRC"; then
  ok "U68-2 slashPanelMaxH 回写 + panelH/panelMaxH 两键"
else
  bad "U68-2 斜杠 cap 通道缺件"
fi
# U68-3 U2 探针六件：ids 齐全 + 落定两读 +
# surface_missing 码 + U1 壳文案清零。
if has '"card_alignment", "lift_gaps",' "$UITEST" \
   && has '"radius_derivation", "home_geometry",' "$UITEST" \
   && has 'code: "surface_missing"' "$UITEST" \
   && has 'enum UITestProbes' "$UITEST" \
   && ! grep -q 'probes are registered in U1' "$UITEST"; then
  ok "U68-3 探针六件落地（UITestProbes + 壳替换）"
else
  bad "U68-3 探针落地不全或 U1 壳残留"
fi
# U68-4 U3 单点化：DragPress 四入口抽取为方
# 法 + 锚点/行面共用接线 + editor.blockRow 面。
if has 'private func dragPickup()' "$SRC" \
   && has 'private func dragMove(_ dy: CGFloat)' "$SRC" \
   && has 'private func dragDrop()' "$SRC" \
   && has 'private func dragCancel()' "$SRC" \
   && has 'id: "editor.blockRow"' "$SRC"; then
  ok "U68-4 拖拽四入口单点化 + 行面接线"
else
  bad "U68-4 拖拽单点化缺件"
fi
# U68-5 U3 场景与证据上限：场景注册 + grades
# recognizer 恒 unknown 字面 + restore 步③ +
# drag_trace 收集单一来源与工具出货四方。
if has 'name: "drag_pickup_statemachine"' "$UITEST" \
   && has 'g["recognizer"] =' "$UITEST" \
   && has '"unknown (by construction)"' "$UITEST" \
   && has '驱动拾起态复位（U3 补实' "$UITEST" \
   && has 'BridgeDragTraceParser.collect' "$BSCEN" \
   && has 'metrics_drag_trace' "$BTOOLS" \
   && has 'metrics_drag_trace' "$RELAY"; then
  ok "U68-5 U3 场景/证据上限/restore③/工具出货"
else
  bad "U68-5 U3 落地缺件"
fi
# U68-6 U5 注册面十件：首页两面 + 设置六面 +
# 桥面 + 图片页面 + RowFrameStore 存储盒。
if has 'id: "home.view"' "$SRC" \
   && has 'id: "home.row"' "$SRC" \
   && has 'final class RowFrameStore' "$SRC" \
   && has 'id: "settings.view"' "$SRC" \
   && has 'id: "settings.diag",' "$SRC" \
   && has 'id: "settings.weather",' "$SRC" \
   && has 'id: "image.view"' "$SRC" \
   && has 'id: "settings.bridge"' "$BSET"; then
  ok "U68-6 U5 注册面（home/settings/bridge/image）"
else
  bad "U68-6 U5 注册面缺件"
fi
# U68-7 U5 场景五件注册 + home_geometry 探针
# 在 ids 内（P4 与 P1–P5 同表）。
if has 'name: "home_search_cycle"' "$UITEST" \
   && has 'name: "home_surface_roundtrip"' "$UITEST" \
   && has 'name: "home_list_actions"' "$UITEST" \
   && has 'name: "image_page_open"' "$UITEST" \
   && has 'name: "settings_surface_roundtrip"' "$UITEST"; then
  ok "U68-7 U5 场景五件注册齐全"
else
  bad "U68-7 U5 场景注册缺件"
fi
# U68-8 行盒高单点口径（fix_drag_pickup_quote_
# face 定案）：BlockState.height 全仓恰两写、
# 同出 BlockRow 行盒 GeometryReader（onAppear
# 的 geo.size.height + onChange 的 h），无
# isText 分流；UITextView 内容高只入 contentH
# 自守卫。旧双喂（文本块以内容高喂 height）
# 令含竖 padding 块型 face 与 row 逐值差
# padding 量（quote 实测 51 vs 31、差 20），
# drag_pickup_statemachine 步 2 两遍实证。景
# 侧 face_equals_row 仍以 block.height 为行
# 盒高对读——口径同源、景不改判。
if [ "$(grep -c 'block.height =' "$SRC")" -eq 2 ] \
   && has 'block.height = geo.size.height' "$SRC" \
   && has 'var contentH: CGFloat = 0' "$SRC" \
   && has 'async { block.contentH = h }' "$SRC" \
   && ! grep -q 'block.height = h }' "$SRC" \
   && has '- block.height) <= 0.5' "$UITEST"; then
  ok "U68-8 height 行盒单点（两写同源/contentH 分流/景对读口径）"
else
  bad "U68-8 height 双喂回潮或行盒单点漂移"
fi

echo "[69] 首页行注册面对账（fix_home_row_registry：注册/注销脱离 List 细胞生命周期、改呈现行集对账单点）"
# HR69-1 注册构造单点：home.row 条目全仓恰
# 一构造点（makeRowEntry）+ 对账存储盒在位；
# 旧锚点制两处行内注册已摘除（计数即证）。
if [ "$(grep -c 'id: "home.row"' "$SRC")" -eq 1 ] \
   && has 'func makeRowEntry(' "$SRC" \
   && has 'final class RowRegistryStore' "$SRC" \
   && has 'func syncRowRegistry()' "$SRC"; then
  ok "HR69-1 行注册构造/对账单点（锚点制摘除）"
else
  bad "HR69-1 行注册单点漂移或锚点制残留"
fi
# HR69-2 对账触发面：在位对账 + 签名变化对
# 账 + 离场全注销三触发齐全。
if has '.onAppear { syncRowRegistry() }' "$SRC" \
   && has '.onChange(of: rowSyncSignature)' "$SRC" \
   && has '.onDisappear { clearRowRegistry() }' "$SRC" \
   && has 'func clearRowRegistry()' "$SRC"; then
  ok "HR69-2 对账三触发（appear/change/disappear）"
else
  bad "HR69-2 对账触发面缺件"
fi
# HR69-3 注销连帧清：unregisterRow 单点内注
# 册摘除与帧清同笔（幽灵行带帧通道关闭）。
if has 'func unregisterRow(_ id: String)' "$SRC" \
   && has 'rowFrameStore.frames.id. = nil' "$SRC"; then
  ok "HR69-3 注销连帧清（unregisterRow 单点）"
else
  bad "HR69-3 注销未连帧清"
fi
# HR69-4 状态现查：条目状态/动作经 liveMemo
# 现查模型（注册时刻快照退役），调用点 ≥4
# （pin/delete/open + 状态四键共用漏斗）。
if has 'func liveMemo(_ id: String)' "$SRC" \
   && [ "$(grep -c 'liveMemo(id)' "$SRC")" -ge 4 ]; then
  ok "HR69-4 行面状态现查（liveMemo 漏斗）"
else
  bad "HR69-4 行面状态仍吃快照"
fi
# HR69-5 折叠派生同源：shownInSublist 定义 1
# + 消费 4（List 子列/网格子列/shownRows 两
# 子列）——渲染与注册的折叠集恒同源。
if has 'func shownInSublist(' "$SRC" \
   && [ "$(grep -c 'shownInSublist(' "$SRC")" -eq 5 ]; then
  ok "HR69-5 折叠派生单点（渲染/注册同源）"
else
  bad "HR69-5 折叠派生分叉"
fi
# HR69-6 景侧两修：home_search_cycle 行断言
# 改等发布 poll；home_surface_roundtrip 首
# 步自密封（closeDest 收导航残留后断言）。
if has '等发布（fix_home_row_' "$UITEST" \
   && has '景自密封（fix_home_row_' "$UITEST"; then
  ok "HR69-6 景侧等发布 + 自密封"
else
  bad "HR69-6 景侧两修缺件"
fi
# HR69-7 @ViewBuilder 归属（0.9.65 组版修复）：
# builder 属性属 sublist（some View 多语句体靠
# 它组 ForEach）——批 5 插入 shownInSublist 时
# 属性留置挂到新函数头上，sublist 丢 builder
# 致 tree 首轮构建 opaque 推断失败（本机文本断
# 言无感、首次编译门抓出）。锁：sublist 签名紧
# 邻上一行 == @ViewBuilder，且 shownInSublist
# 签名上方 3 行内无 @ViewBuilder。
SUBL_LINE=$(grep -n 'private func sublist(' "$SRC" | head -1 | cut -d: -f1)
SHOWN_LINE=$(grep -n 'private func shownInSublist(' "$SRC" | head -1 | cut -d: -f1)
if [ -n "$SUBL_LINE" ] && [ -n "$SHOWN_LINE" ] \
   && [ "$(sed -n "$((SUBL_LINE-1))p" "$SRC" | grep -c '@ViewBuilder')" -eq 1 ] \
   && [ "$(sed -n "$((SHOWN_LINE-3)),$((SHOWN_LINE-1))p" "$SRC" | grep -c '@ViewBuilder')" -eq 0 ]; then
  ok "HR69-7 @ViewBuilder 归属 sublist（纯数据函数不挂）"
else
  bad "HR69-7 @ViewBuilder 归属漂移"
fi

echo "[70] 图片页点按路由与命中形（fix_image_tap_regression：批 3 换承载切断图块点按——AnimImageView 被动承载不提供命中体、图块行级手势无 contentShape 声明命中域，点按恒不达；其余四面或有 contentShape 或有 GeometryReader 满框故独存）"
# TP70-1 路由单点普查：presentImagePage 定义
# 恰 1、全仓调用恰 6（定义 + 图块/gallery 瓦/
# 附件整幅/附件文件行/图文 openImagePage 五入
# 口）、imageTarget 直拼恰 1（单点本体）——任
# 何入口绕单点自拼或单点被摘，本条即红。
if [ "$(grep -c 'func presentImagePage(' "$SRC")" = 1 ] \
   && [ "$(grep -c 'presentImagePage(' "$SRC")" = 6 ] \
   && [ "$(grep -c 'imageTarget = ImageTarget(' "$SRC")" = 1 ]; then
  ok "TP70-1 图片页路由单点（定义 1 + 五入口调用 + 直拼仅单点本体）"
else
  bad "TP70-1 路由单点漂移（def=$(grep -c 'func presentImagePage(' "$SRC") calls=$(grep -c 'presentImagePage(' "$SRC") direct=$(grep -c 'imageTarget = ImageTarget(' "$SRC")）"
fi
# TP70-2 命中形：ImageBlockView 段内 AnimImage-
# View 链 contentShape(Rectangle()) 恰 1（图面
# 命中域声明本体）；承载被动不变量同锁——
# AnimImageView makeUIView 恒 isUserInteraction
# Enabled = false（其被动性正是命中形必须由容
# 器面声明的机制前提，翻转它会改拾起仲裁面）。
TPSEG_IMG=$(sed -n '/^struct ImageBlockView/,/^struct [A-Z]/p' "$SRC")
TPSEG_ANIM=$(sed -n '/^struct AnimImageView/,/^final class/p' "$SRC")
if [ "$(printf '%s' "$TPSEG_IMG" | grep -c 'contentShape(Rectangle())')" = 1 ] \
   && printf '%s' "$TPSEG_ANIM" | grep -q 'isUserInteractionEnabled = false'; then
  ok "TP70-2 图块命中形（contentShape 恰 1 + 承载被动不变量）"
else
  bad "TP70-2 命中形漂移（shape=$(printf '%s' "$TPSEG_IMG" | grep -c 'contentShape(Rectangle())') passive=$(printf '%s' "$TPSEG_ANIM" | grep -c 'isUserInteractionEnabled = false')）"
fi
# TP70-3 不可开集负空间：music/link 卡、MD 图、
# 视频三段内 presentImagePage/imageTarget 恒 0
# （防误开回归锁——2026-11-24 附件误入前科与
# 定案可开范围的负半）。
TPNEG=0
for seg in CardBlockView MdImageView VideoBlockView; do
  TPSEG=$(sed -n "/^struct $seg/,/^struct [A-Z]/p" "$SRC")
  TPNEG=$((TPNEG + $(printf '%s' "$TPSEG" | grep -c 'presentImagePage\|imageTarget')))
done
if [ "$TPNEG" = 0 ]; then
  ok "TP70-3 不可开集无路由（卡/MD 图/视频三段路由符号 0）"
else
  bad "TP70-3 不可开集出现路由（合计 $TPNEG）"
fi
# TP70-4 场景同路：UITest 内直拼 imageTarget
# 恒 0、presentImagePage 调用 ≥2（gallery 腿 +
# cards 景 openLeg）；新景与新夹具在册。
if [ "$(grep -c 'imageTarget = ImageTarget(' "$UITEST")" = 0 ] \
   && [ "$(grep -c 'presentImagePage(' "$UITEST")" -ge 2 ] \
   && has 'name: "image_page_open_cards"' "$UITEST" \
   && has 'case mediaOpen' "$UITEST" \
   && has 'enum UITestScenarioImageCards' "$UITEST"; then
  ok "TP70-4 场景同路（直拼 0 + 单点调用 + cards 景/夹具在册）"
else
  bad "TP70-4 场景同路漂移（direct=$(grep -c 'imageTarget = ImageTarget(' "$UITEST") calls=$(grep -c 'presentImagePage(' "$UITEST")）"
fi
# TP70-5 矩阵登记：IMG-01 行含新景名（入口覆
# 盖表与运行腿口径以矩阵为单一出处）。
if has 'image_page_open_cards' "$MATRIX"; then
  ok "TP70-5 矩阵 IMG-01 已登记 cards 景"
else
  bad "TP70-5 矩阵 IMG-01 未登记 cards 景"
fi

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (incl [65][66][67][68][69][70])"; else echo "FAIL"; exit 1; fi
