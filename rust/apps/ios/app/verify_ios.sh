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
v_sw=$(grep -o 'Text("[0-9][0-9.]*")' "$SRC" | head -1 | sed 's/Text("//; s/")//')
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
if has 'prefix(12)' "$SRC"; then ok "图片页标题 12 字截断在位"; else bad "图片页标题截断缺失（用户定 12 字 + …）"; fi
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
if grep -q "CFBundleIconName" "build-app2.sh" \
   && grep -q "UIColorName" "build-app2.sh" \
   && grep -q "UIStatusBarStyleLightContent" "build-app2.sh" \
   && grep -q "accord" "build-app2.sh"; then
  ok "Info.plist 图标/开屏/状态栏声明在构建脚本内"
else
  bad "构建脚本缺 CFBundleIconName/UIColorName/状态栏/accord 任一项"
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
# = 371。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
counts = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        counts.append(len(json.load(f)))
sys.exit(0 if all(n == 371 for n in counts) else 1)
PYEOF
then
  ok "五语键数 371（370 + 桥会话实况批 1）"
else
  bad "五语键数非 371（补键须同步改此期望）"
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
# 不走填充裁切的 ItemImageView）。
if has 'struct MdImageView' "$SRC" \
   && has 'MdImageView(urlString: src' "$SRC" \
   && has 'scaledToFit()' "$SRC"; then
  ok "J1-6 MD 预览图 MdImageView 在位"
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
# B16-3 工具集边界（M3a 改写）：协议清单 35
# 件逐名在 BPROTO（M2 的 22 + 在席 4 + uitest
# 4 + rescue_arm_safe_mode 1 + M3a 场景 3 +
# 量测 1）；正文级 4 名（待端到端加密专项评
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
         scenarios_get_result metrics_create_settle; do
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
  ok "B16-3 工具清单 35 件齐全、正文级未评审工具零注册"
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
# 为 35 件（连接器 ALLOWED_TOOLS 已由 M3a 批
# 同步，仓外不查）。manifestHash 注记：
# ec9fbc90…（sha256("2025-06-18|" + 35 名排序
# 连接)，运行时两边计算对账）。
protonames=$(sed -n '/static let toolNames/,/\]/p' "$BPROTO" \
  | grep -o '"[a-z_]*"' | tr -d '"' | sort)
relaynames=$(awk '/^const TOOLS = \[/{f=1} f{print} f&&/^\];/{exit}' "$RELAY" \
  | grep -o 'name: "[a-z_]*"' | sed 's/name: "//; s/"$//' | sort)
if [ "$protonames" = "$relaynames" ] \
   && [ "$(echo "$protonames" | wc -l | tr -d ' ')" = 35 ]; then
  ok "B16-15 App/中继工具清单一致（35 件，diff 空）"
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
# B16-QR-1..4 配对二维码（impl_pairing_qr）：载荷
# 只消费 pairingURL() 单一构造点（构造点
# queryItems 恒 pid+fp 两项、设置页引用恰两处
# = 链接钮 + 二维码、构建名单含 bridge_qr.o）；
# 二维码生成文件与构造点函数体内凭据词零出现
# （私钥存取/客户端密钥/会话恢复令牌）；二维码
# 视图恰一处且位于待配对分支内（已配对分支随
# 分支结构零出现）；有效期行与 expiresAtMs 数
# 据源同在待配对分支。
BQR=MomentBridgeQR.swift
PAIRSEG=$(sed -n '/func pairingURL/,/^    }$/p' "$BRIDGE")
PENSEG=$(sed -n '/if let pending = bridge.pendingPairing/,/} else if bridge.isPaired {/p' "$BSET")
if [ -f "$BQR" ] \
   && [ "$(grep -c 'pairingURL()' "$BSET")" = 2 ] \
   && has 'makePairingQRImage(url.absoluteString)' "$BSET" \
   && has 'bridge_qr.o' "$SH" \
   && echo "$PAIRSEG" | grep -q 'URLQueryItem(name: "pid"' \
   && echo "$PAIRSEG" | grep -q 'URLQueryItem(name: "fp"' \
   && [ "$(echo "$PAIRSEG" | grep -c 'URLQueryItem')" = 2 ]; then
  ok "B16-QR-1 二维码载荷单源（pairingURL 恰 pid+fp、设置页引用恰两处、构建名单齐）"
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
# 件内计数 6 = 定义 1 + 五页调用，桥设置文件
# 调用 1；全仓 .padding(.top, 126) 共 4 = 容
# 器定义 1 + Diag 页 2（Diag 不在本批收敛
# 面）+ 图片页 L-4 呈现顶让 1。
if [ "$(grep -c 'func settingsContentFrame' "$SRC")" = 1 ] \
   && [ "$(grep -c 'settingsContentFrame()' "$SRC")" = 6 ] \
   && [ "$(grep -c 'settingsContentFrame()' "$BSET")" = 1 ] \
   && [ "$(grep -c 'padding(.top, 126)' "$SRC")" = 4 ] \
   && [ "$(grep -c 'padding(.top, 126)' "$BSET")" = 0 ]; then
  ok "W18-8 设置六页收敛 SettingsContainer（720 居中单源）"
else
  bad "W18-8 设置页容器收敛不齐（手抄 padding 回潮或页缺）"
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
if has '(ordered ? 1.4 : 1.2)' "$SRC" \
   && has '* baseSize - markerW' "$SRC"; then
  ok "J20-12 列表文起点 em 公式在位"
else
  bad "J20-12 列表文起点未改"
fi
# J20-13 斜杠面板上翻 maxH 下限 120（审计 L-3，
# 横屏矮高保底）：slashLayer 段下限字面在位、旧
# 48 下限零残留。
SL=$(awk '/private var slashLayer/,/private func slashPanelWidth/' "$SRC")
if echo "$SL" | grep -qF 'max(top - 10 - 12, 120)' \
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
# trim + 空回退「无标题」、Esc 快照源 titleBase
# 两点不移；Enter 收口锚移到字段 Coordinator
# 的 shouldReturn（置 focused=false 辞焦 →
# didEnd 结束支路提交，与旧 onSubmit 等价）。
if echo "$HDR" | grep -q 'trimmed.isEmpty ? "无标题" : trimmed' \
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
# B27-2 注册表与清单：四景 id 在注册表逐个在
# 位；场景三件 + 量测件在 BPROTO 清单（逐名由
# B16-3 守，本条查注册表侧）。
regok=1
for s in drag_trace_review weather_settings_flow \
         ops_convergence language_roundtrip; do
  grep -q "\"$s\"" "$BSCEN" || regok=0
done
if [ "$regok" = 1 ] \
   && [ "$(grep -c 'BridgeScenarioDescriptor(' "$BSCEN")" = 4 ]; then
  ok "B27-2 场景注册表四景齐全（M3a 首批）"
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
GRIDH30=$(awk '/Text\(group\.title\)/,/gridCellColumns/' "$SRC")
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
# （缺省 src=nav 的无参调用 4：新建/打开/头像/
# 紧凑标题；定义已带 src 形参、不再以无参字面
# 计数；在席边界 seat 调用由 F30-16 单独锁）。
if echo "$CAP30" | grep -qF '.focused($searchFocused)' \
   && echo "$CAP30" | grep -qF 'searchCloseSrc = "submit"' \
   && echo "$CAP30" | grep -qF 'searchCloseSrc = "clear"' \
   && [ "$(echo "$LV" | grep -cF 'resignSearch()')" = 4 ]; then
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
# F30-5 分组头合成距：insets 25/3（与卡 inset
# 3 合成 Web 28/6）+ tracking 0.3 + uppercase。
if echo "$GH30" | grep -qF 'top: 25, leading: 20' \
   && echo "$GH30" | grep -qF 'bottom: 3, trailing: 16' \
   && echo "$GH30" | grep -qF '.tracking(0.3)' \
   && echo "$GH30" | grep -qF '.textCase(.uppercase)'; then
  ok "F30-5 分组头合成距 28/6 + 字距/大写在位"
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
# F30-9 材质与回退图：紧凑胶囊 overlay 档、搜
# 索面板 overlay 档（pill）、头像恐龙 size−8
# 底对齐。
if echo "$CT30" | grep -qF '.overlayCard(radius: Radius.panelS)' \
   && ! echo "$CT30" | grep -qF '.glassCard(radius: 20)' \
   && echo "$CAP30" | grep -qF '.overlayCard(radius: Radius.pill)' \
   && echo "$AV30" | grep -qF 'DinoView(size: size - 8)' \
   && echo "$AV30" | grep -qF 'alignment: .bottom'; then
  ok "F30-9 紧凑/搜索 overlay 档 + 恐龙 size−8 底对齐"
else
  bad "F30-9 材质档或恐龙度量漂移"
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
# 高 16 + 显式零 insets（合成 3+16+3 = 22 =
# Web .img-card margin 0（:last-child）+
# .swipe-wrapper margin 6 + .gap-16 高 16，
# base.css:118/191-192/205 逐项核正——旧锚
# 40 把 .list-group 组间 margin 24 误记到子
# 列交界、锁错账面一版，fix_home_regres-
# sions_0957 改判）；空状态行显式零 insets
# （纵 56 账面值不被默认继承放大）。
SEP30=$(echo "$LV" | awk '/kind: "img"/,/kind: "txt"/')
EMP30=$(awk '/private var emptyRow/,/^struct CompactTitle/' "$SRC")
if echo "$SEP30" | grep -qF '.frame(height: 16)' \
   && echo "$SEP30" | grep -qF '.listRowInsets(EdgeInsets())' \
   && [ "$(echo "$EMP30" | grep -cF '.listRowInsets(EdgeInsets())')" = 1 ]; then
  ok "F30-14 图/文分隔 22 合成锚 + 空行零 insets"
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
# （收口 12 + 既有 2）、controlS 恰 5。
if [ "$(grep -cF 'glassControl(radius: Radius.pill)' "$SRC")" = 14 ] \
   && [ "$(grep -cF 'glassControl(radius: Radius.controlS)' "$SRC")" = 5 ]; then
  ok "R31-3 glassControl 令牌计数锚（pill 14 / controlS 5）"
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
# 引用），扩展产物入 PlugIns/。
if [ -f "$LIVEOPS" ] && [ -f "$LIVEATTR" ] \
   && [ -f "$LIVEWIDGET" ] \
   && [ "$(grep -c 'MomentLiveOps.swift' "$SH")" -ge 18 ] \
   && [ "$(grep -c 'MomentLiveOpsAttributes.swift' "$SH")" -ge 20 ] \
   && has 'PlugIns/MomentLiveOpsWidget.appex' "$SH" \
   && has 'com.canopies.moment.liveops' MomentLiveOpsWidget-Info.plist; then
  ok "B34-5 LiveOps 三文件 + 双目标接线 + appex 入包"
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
# B34-9 语言包新键五份齐备（liveops.* 四键 +
# bridge.notify 两键，键数守恒由 [18] 另锁）。
miss=0
for f in ../../web/lang/zh-CN.json ../../web/lang/zh-TW.json \
         ../../web/lang/en-US.json ../../web/lang/ja-JP.json \
         ../../web/lang/ko-KR.json; do
  for k in liveops.bridge_op liveops.export liveops.import \
           liveops.scenario bridge.notify bridge.notify_note; do
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
# 零）、诊断日志页导出胶囊（DiagLogPage 段
# minHeight 46 ×1、同段定高 46 零）、错误徽章钮
# （minWidth/minHeight 36 胶囊、旧定尺寸零）。
BV36=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
DL36=$(awk '/^struct DiagLogPage/,/^struct ListBlockView/' "$SRC")
EB36=$(awk '/^struct ErrBadgeOverlay/,/^final class DiagLog/' "$SRC")
if [ "$(grep -cF 'frame(height: 44)' "$SRC")" = 0 ] \
   && [ "$(echo "$BV36" | grep -cF 'frame(minHeight: 44)')" = 2 ] \
   && [ "$(echo "$DL36" | grep -cF 'frame(minHeight: 46)')" = 1 ] \
   && [ "$(echo "$DL36" | grep -cF 'frame(height: 46)')" = 0 ] \
   && echo "$EB36" | grep -qF 'minWidth: 36, minHeight: 36' \
   && ! echo "$EB36" | grep -qF 'frame(width: 36, height: 36)'; then
  ok "DT36-3 文字定高容器全改生长式（钮/胶囊/徽章）"
else
  bad "DT36-3 文字定高容器有残留或生长式接线缺失"
fi
# DT36-4 列表标记同源缩放：MD 标记框 markerW =
# baseSize × 1.125（间距账 J20-12 同步）、编辑列
# 表标记框/嵌套缩进走 ScaledMetric（markerW /
# indentOrdered 在位、旧定宽 18/20 零残留）。
LB36=$(awk '/^struct ListBlockView/,/^struct SlashCmd/' "$SRC")
if [ "$(grep -cF 'baseSize * 1.125' "$SRC")" = 1 ] \
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
# 恒由 [9] 另锁 371）。
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
# 帧（段内 ≥1）+ 页眉返回钮 46 命中方（段内恰
# 1）——宽屏批刻意排除的全宽形态，不许被收窄
# 居中批误伤。
SEG39=$(awk '/^struct DiagLogPage/,/func exportAll/' "$SRC")
if [ "$(echo "$SEG39" | grep -c 'maxWidth: .infinity, maxHeight: .infinity')" -ge 1 ] \
   && [ "$(echo "$SEG39" | grep -c 'width: 46, height: 46')" = 1 ]; then
  ok "IPAD39-5 DiagLogPage 全宽日志卡 + 页眉 46 钮形态守恒"
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
# IPAD39-8 命中尺寸不随屏放大：页眉/页头返回与
# 关闭钮的 46×46 命中方全文件恰 7 处——命中贴
# 合手指不贴屏幕，iPad 同值；计数漂移须先改
# impl_ipad_fit8.md 第 8 项账再改本锁。
if [ "$(grep -c 'width: 46, height: 46' "$SRC")" = 7 ]; then
  ok "IPAD39-8 命中 46 方七处守恒（不随屏放大）"
else
  bad "IPAD39-8 命中 46 方计数漂移（须恰 7，先改 fit8 账）"
fi

# SVG42-1 嗅探汇合点单点：isSvgData 定义在光栅
# 文件恰 1 处；ImageLoader.publish 段内嗅探调
# 用 / 光栅化调用 / decodeImage 调用各恰 1——
# fileId/URL 两路只许经 publish 汇合分流，不
# 许两路各备一份；全文件 decodeImage( 恒 2 行
# （定义 + 汇合点调用），防分流点外直调回潮。
PUB42=$(awk '/private func publish\(data: Data\?/,/^    }/' "$SRC")
if [ -f "$SVGR" ] \
   && [ "$(grep -c 'func isSvgData' "$SVGR")" = 1 ] \
   && [ "$(echo "$PUB42" | grep -cF 'isSvgData(data)')" = 1 ] \
   && [ "$(echo "$PUB42" | grep -cF 'SvgRasterizer.shared.rasterize')" = 1 ] \
   && [ "$(echo "$PUB42" | grep -cF 'decodeImage(data)')" = 1 ] \
   && [ "$(grep -cF 'decodeImage(' "$SRC")" = 2 ]; then
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
# 对账面 attIsImage 未被分流改动）；imageTarget
# 赋值点恒 5（图块/gallery/附件整幅/文件行分
# 发/图文卡图区），防入口分流补丁混入。
if has '"bmp", "svg", "avif", "heic", "heif"' "$SRC" \
   && [ "$(grep -c 'editor\.imageTarget =' "$SRC")" = 5 ]; then
  ok "SVG42-3 判图守恒（扩展集含 svg、imageTarget 赋值恰 5）"
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
# 扫定义 + 六调用点（didChange/insertLines/
# splitBlock/mergeBlockBackward/mergeListItem-
# Backward 两出口）合计恰 7、四类分派齐备。
E43SEG_SMART=$(awk '/func applySmartPrefixIfNeeded/ {f=1} f {print} f && /^    }$/ {exit}' "$SRC")
if [ "$(grep -c 'func smartPrefixMatch' "$SRC")" = 1 ] \
  && [ "$(grep -c 'applySmartPrefixIfNeeded' "$SRC")" = 7 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .divider')" = 1 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .heading')" = 1 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .quote')" = 1 ] \
  && [ "$(echo "$E43SEG_SMART" | grep -c 'case .todo')" = 1 ]; then
  ok "E43-2 智能前缀匹配 + 尾扫六调用点 + 四类分派（F-02）"
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

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAIL"; exit 1; fi
