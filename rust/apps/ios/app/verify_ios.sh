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
# 图片页判定前提：小/大图判定用可用高（全屏 − 页头
# 让位 66），与呈现同高（0.9.35 排查修复）。
if has 'geo.size.height - 66' "$SRC"; then
  ok "图片页判定用可用高（全屏 − 66）"
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
# = 360。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
counts = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        counts.append(len(json.load(f)))
sys.exit(0 if all(n == 360 for n in counts) else 1)
PYEOF
then
  ok "五语键数 360（351 + 天气批 11 − 退役 2）"
else
  bad "五语键数非 360（补键须同步改此期望）"
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
# 区 + 三形态 minHeight 占位账（208/192/200）在位。
if ! grep -q 'frame(height: 220)' "$SRC" \
   && has 'minHeight: 220, maxHeight: .infinity' "$SRC" \
   && has 'ui.viewH - 208' "$SRC" \
   && has 'ui.viewH - 192' "$SRC" \
   && has 'ui.viewH - 200' "$SRC" \
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
# B16-3 工具集边界（布防批改写）：协议清单 31
# 件逐名在 BPROTO（M2 的 22 + 在席 4 + uitest
# 4 + rescue_arm_safe_mode 1）；正文级 4 名
# （待端到端加密专项评审，方案 §12.1/附录
# B.3）在桥文件与中继的代码行零注册（注释提
# 及不算，与 [2] 的代码行口径一致）。
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
         uitest_get_result uitest_measure; do
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
  ok "B16-3 工具清单 31 件齐全、正文级未评审工具零注册"
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
# 为 31 件（连接器 ALLOWED_TOOLS 已由布防批
# 同步，仓外不查）。manifestHash 注记：
# a52116c3…（sha256("2025-06-18|" + 31 名排序
# 连接)，运行时两边计算对账）。
protonames=$(sed -n '/static let toolNames/,/\]/p' "$BPROTO" \
  | grep -o '"[a-z_]*"' | tr -d '"' | sort)
relaynames=$(awk '/^const TOOLS = \[/{f=1} f{print} f&&/^\];/{exit}' "$RELAY" \
  | grep -o 'name: "[a-z_]*"' | sed 's/name: "//; s/"$//' | sort)
if [ "$protonames" = "$relaynames" ] \
   && [ "$(echo "$protonames" | wc -l | tr -d ' ')" = 31 ]; then
  ok "B16-15 App/中继工具清单一致（31 件，diff 空）"
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
if has '(ordered ? 1.4 : 1.2)' "$SRC" \
   && has '* baseSize - 18' "$SRC"; then
  ok "J20-12 列表文起点 em 公式在位"
else
  bad "J20-12 列表文起点未改"
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
# （定义 1 + 调用 4：新建/打开/头像/紧凑标题）。
if echo "$CAP30" | grep -qF '.focused($searchFocused)' \
   && echo "$CAP30" | grep -qF 'searchCloseSrc = "submit"' \
   && echo "$CAP30" | grep -qF 'searchCloseSrc = "clear"' \
   && [ "$(echo "$LV" | grep -cF 'resignSearch()')" = 5 ]; then
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
# 行卡 chip 高 18、方卡 chip 高 20/18（frame
# 字面两处）；三处 chip 均走 glassLabelAccent。
if grep -qF 'dyn(0x005BBB, 0x72B7FF)' "$SRC" \
   && [ "$(echo "$LV" | grep -cF 'T.glassLabelAccent')" = 3 ] \
   && [ "$(echo "$LV" | grep -cF '.frame(height: small ? 18 : 20)')" = 2 ]; then
  ok "F30-8 chip 令牌/三处色/高（18·20/18）在位"
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
# 高 34 + 显式零 insets（合成 3+34+3 = 40 =
# Web margin 24 + gap 16）；空状态行显式零
# insets（纵 56 账面值不被默认继承放大）。
SEP30=$(echo "$LV" | awk '/kind: "img"/,/kind: "txt"/')
EMP30=$(awk '/private var emptyRow/,/^struct CompactTitle/' "$SRC")
if echo "$SEP30" | grep -qF '.frame(height: 34)' \
   && echo "$SEP30" | grep -qF '.listRowInsets(EdgeInsets())' \
   && [ "$(echo "$EMP30" | grep -cF '.listRowInsets(EdgeInsets())')" = 1 ]; then
  ok "F30-14 图/文分隔 40 合成锚 + 空行零 insets"
else
  bad "F30-14 分隔行或空行 insets 漂移（合成间距失守）"
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
# 与盘点值 12/8 对账，增减须改锚即须过目。
if [ "$(grep -c 'Capsule()' "$SRC")" = 12 ] \
   && [ "$(grep -c 'Circle()' "$SRC")" = 8 ]; then
  ok "R31-8 Capsule 12 / Circle 8 计数锚"
else
  bad "R31-8 隐式形状计数漂移"
fi
# R31-9 微装饰字面集封闭（0.9.52 定案保留）：
# 1.5×2 / 4×1 / 6×5 / 10×3 / 14×1 / 18×1，
# 任一增减即红（防无声增殖）。
if [ "$(grep -cF 'cornerRadius: 1.5' "$SRC")" = 2 ] \
   && [ "$(grep -cF 'cornerRadius: 4)' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'cornerRadius: 6' "$SRC")" = 5 ] \
   && [ "$(grep -cF 'cornerRadius: 10' "$SRC")" = 3 ] \
   && [ "$(grep -cF 'cornerRadius: 14' "$SRC")" = 1 ] \
   && [ "$(grep -cF 'cornerRadius: 18' "$SRC")" = 1 ]; then
  ok "R31-9 微装饰字面集计数锚（1.5/4/6/10/14/18）"
else
  bad "R31-9 微装饰字面集漂移"
fi

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAIL"; exit 1; fi
