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
  ok "21 项 checksum 双向一致（改导出面未重生 bindings 会在此红）"
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
n_sp0=$(echo "$HDR" | grep -c 'Spacer(minLength: 0)')
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
# installer 段内禁止再出现 require(toFail ——该关系
# 使长按等 pan 判失败、拾起永不触发；拾起锁滚动
# isScrollEnabled = false 必须在位。
INST=$(awk '/^struct DragPickupInstaller/,/^struct CardEditSheets/' "$SRC" | grep -v '^[[:space:]]*//')
if echo "$INST" | grep -q "require(toFail"; then
  bad "拖拽仲裁回潮：installer 内出现 require(toFail（拾起永不触发）"
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

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAIL"; exit 1; fi
