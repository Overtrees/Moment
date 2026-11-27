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
  ok "22 项 checksum 双向一致（改导出面未重生 bindings 会在此红）"
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
# liftScaleFor 双轴公式）：LiftFrame 的 +4 外扩与缩
# 放公式 (dim - 8) 必须同在。
if has 'struct LiftFrame' "$SRC" && has 'padding(-4)' "$SRC" \
   && has '(dim - 8) / dim' "$SRC"; then
  ok "拾起框 + 双轴缩放公式前提组在位"
else
  bad "拾起框/双轴缩放前提缺失（LiftFrame、padding(-4)、(dim - 8) / dim 须同在）"
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
# rescue.check_ops 1 键）= 324。
if python3 - "$LANGDIR" <<'PYEOF'
import json, sys
codes = ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
counts = []
for c in codes:
    with open(f"{sys.argv[1]}/{c}.json",
              encoding="utf-8") as f:
        counts.append(len(json.load(f)))
sys.exit(0 if all(n == 324 for n in counts) else 1)
PYEOF
then
  ok "五语键数 324（307 基线 + 自救批 17）"
else
  bad "五语键数非 324（补键须同步改此期望）"
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
# 组头 40（组头行后一行即 topPad）。
if echo "$SV" | grep -A1 '"settings.data"' | grep -q 'topPad: 40' \
   && echo "$SV" | grep -A1 '"settings.weather"' | grep -q 'topPad: 32' \
   && echo "$SV" | grep -A1 '"settings.about"' | grep -q 'topPad: 40'; then
  ok "S1 组头 topPad 分档 40/32/40"
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
# S4/S5：备份 toast 全宽条（overlayCard 28、旧
# 999 胶囊零残留）、hero radius 30、成功色令牌。
BV=$(awk '/^struct BackupView/,/^struct GesturesView/' "$SRC")
if echo "$BV" | grep -q 'overlayCard(radius: 28)' \
   && ! echo "$BV" | grep -q 'glassCard(radius: 999)' \
   && echo "$BV" | grep -q 'glassCard(radius: 30)'; then
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
# 含 fetch 入口、判定消费 forceSafeMode。
OPSSEG=$(sed -n '/^final class OpsDirectives/,$p' "$OPS")
if has 'https://moment-ops.overtrees.workers.dev/ops.json' "$OPS" \
   && has 'https://overtrees.github.io/moment-ops/ops.json' "$OPS" \
   && echo "$OPSSEG" | grep -q '"disableSteps"' \
   && echo "$OPSSEG" | grep -q '"forceSafeMode"' \
   && echo "$OPSSEG" | grep -q 'func sanitize' \
   && echo "$OPSSEG" | grep -q 'OPS directives fetched src=' \
   && [ "$(grep -c 'OPS skip step=' "$SRC")" -ge 3 ] \
   && echo "$RV" | grep -q 'OpsDirectives.shared.fetch' \
   && has 'OpsDirectives.cached().forceSafeMode' "$SRC"; then
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

echo "[15] 新建过渡第二轮根治（0.9.48，定案 fix_new_note_transition_round2.md）"
# T15-1 归组版本缓存（治 S1 趟基数）：缓存包装 +
# assembleGroups 在位；版本 bump 写点全集计数锁定
# （touchMemos = 定义 1 + 写点 6、touchManifest =
# 定义 1 + 写点 3——漏一处 bump 即归组过期）。
n_tm=$(grep -c 'touchMemos()' "$SRC")
n_tf=$(grep -c 'touchManifest()' "$SRC")
if has 'private func assembleGroups' "$SRC" \
   && has 'groupsCache.key == key' "$SRC" \
   && has 'private(set) var memosVersion' "$SRC" \
   && [ "$n_tm" = 7 ] && [ "$n_tf" = 4 ]; then
  ok "T15-1 归组按版本缓存（bump 写点全集 memos 6 + manifest 3）"
else
  bad "T15-1 归组缓存缺失或 bump 计数漂移（memos=$n_tm 应 7、manifest=$n_tf 应 4）"
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

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAIL"; exit 1; fi
