#!/usr/bin/env bash
# Mynote Rust Web 静态一致性检查（轻量「原版 verify 等价」）：
# 不起浏览器，只核对源码与构建产物的结构性不变量——
#   1) 五个语言包键集完全一致；
#   2) 样式四模块齐全，且 main.rs 的 include_str! 拼接顺序
#      为 tokens → base → editor → panels（顺序即级联顺序，
#      错位会静默改变样式优先级）；
#   3) dist 产物齐全（壳/wasm/胶水/sw/lang/manifest/图标）；
#   4) dist/sw.js 的 VERSION 戳与当前 wasm md5 前 10 位一致
#      （构建脚本按此口径打戳，不一致 = 产物不是同一次构建）；
#   5) 已移除概念残留扫描：五包全部「值」与设置/备份 UI 源码
#      字符串中不得再出现已移除概念的词表（见下方第 5 节
#      RESIDUE 词表）；纯内部注释、Diag 字符串、键名本身不算
#      残留，不在扫描面内。
#   6) 标题面构造门禁：标题源码与标题 CSS 规则禁内距左右
#      分写（对称由 padding-inline 单值构造保证）；旧标题
#      桥符号（titleText/titleLatch/syncTitleLayout）全域
#      零残留。
#   7) i18n 深检：同一键的 {占位符} 集合五包必须齐平
#      （硬门禁——占位符是 tf() 插值面，漏写/多写会让该
#      语言渲染缺量）；键在 src 全域以键界正则零命中 =
#      僵尸键（硬门禁——删键或补引用）；非中文包与
#      zh-CN 同值且含汉字 = 疑似漏译，仅警告（繁简
#      同字/专名同形多为正常，不判失败）。
#   8) dist 体积预算门（批 13 P-D4）：dist 总字节与 wasm
#      字节不得超过预算（见第 8 节常量与依据注释）。
#  12) 页面过渡统一机制静态锁（2026-11-24 顶栏根治）：
#      栈式快照交接已整套退役——styles 不得再有
#      .page-leaving 规则、main.rs 不得再有
#      stack_current_page/render_leaving_page 标识符与
#      page-leaving 渲染串；全部 on_back 必须经
#      Nav::go_back（返回提交点语义），且组件页提交打点
#      （TRANS … -> committed）必须在场。行为侧由
#      probe_page_transitions ⑤⑥⑦ 段守（见 TESTING.md）。
#   9) 串行同帧防回归静态锁：编辑→列表离页舞台
#      .editor-stage.leaving 不得含 position:fixed（须在
#      流内）；main.rs 列表渲染分支必须以
#      editor_slot.is_none() 为门。两条锁 #14 重叠交接
#      不得回归（行为侧由 probe_page_transitions 的防
#      回归判据组（串行同帧语义）守，见 TESTING.md）。
#  10) 备份确认底表进场无位移静态锁：styles/panels.css
#      的 @keyframes sheetIn 规则块内不得出现 transform
#      声明（进场只许 opacity 淡入）；.backup-modal 的
#      animation 声明必须仍指向 sheetIn（防整条动画被
#      误删或换名绕过）。位移动画与底表底部全幅渲染
#      冲突、为确认弹窗底部实心栏的真机定案根因。
#  11) 根色写入收口静态锁（2026-11-24 图片页化后改）：
#      editor.rs 中 apply_root_bg 只准以两处既有先行写入
#      点的形态存在（先行值 = effective_bg 直算、与 App
#      派生同值，以变量落盘），出现次数恰为 2 且形态全
#      合——新增直调点、旧形态直调、注释提及一律判红；
#      src 全域禁已退役符号残留（压暗栈/浮层在场派生输
#      入/LBX 打点已整删，代码与注释均不得复现）。
#
# 【文案规矩（后续批次有据可依）】
# - 任何文案变更必须五个语言包同提交：键齐平只是底线，
#   「值」也要逐包核——某包值里残留旧表述同样算遗漏。
# - 某概念被拍板移除时，除了删 UI 与键，还要把该概念的
#   特征词加进下方第 5 节的 RESIDUE 词表，让门禁长期守住；
#   词表增删只在该节维护，别散落到其他检查里。
# 用法：bash scripts/verify_rustweb.sh [dist 目录]
# 退出码：全部通过 0，任一失败 1。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/rust/apps/web"
DIST="${1:-$WEB/dist}"
FAIL=0
ok()   { echo "✓ $1"; }
bad()  { echo "✗ $1"; FAIL=1; }

# --- 1) 语言包键集一致 ---
python3 - "$WEB/lang" <<'PYEOF'
import json, sys, pathlib
lang = pathlib.Path(sys.argv[1])
packs = {}
for f in sorted(lang.glob("*.json")):
    packs[f.stem] = set(json.loads(f.read_text(encoding="utf-8")).keys())
names = list(packs)
base = packs[names[0]]
bad = [n for n in names if packs[n] != base]
if bad:
    for n in bad:
        print(f"✗ 语言包 {n} 键集与 {names[0]} 不一致：多 {sorted(packs[n]-base)} 缺 {sorted(base-packs[n])}")
    sys.exit(1)
print(f"✓ 语言包键集一致：{len(names)} 包 × {len(base)} 键")
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 2) 样式四模块齐全 + 拼接顺序 ---
for m in tokens base editor panels; do
  [ -f "$WEB/styles/$m.css" ] || bad "样式模块缺失：styles/$m.css"
done
ORDER="$(grep -o 'include_str!("../styles/[a-z]*\.css")' "$WEB/src/main.rs" \
  | sed 's/.*styles\///; s/\.css.*//' | tr '\n' ' ')"
if [ "$ORDER" = "tokens base editor panels " ]; then
  ok "样式四模块齐全且拼接顺序 tokens→base→editor→panels"
else
  bad "main.rs 样式拼接顺序异常：[$ORDER]"
fi

# --- 3) dist 产物齐全 ---
for f in index.html sw.js manifest.json Mynoteicon.png mynote-web.js; do
  [ -f "$DIST/$f" ] || bad "dist 缺失：$f"
done
ls "$DIST"/*_bg.wasm >/dev/null 2>&1 || bad "dist 缺失：*_bg.wasm"
for l in zh-CN zh-TW en-US ja-JP ko-KR; do
  [ -f "$DIST/lang/$l.json" ] || bad "dist 缺失：lang/$l.json"
done
[ $FAIL -eq 0 ] && ok "dist 产物齐全（壳/wasm/胶水/sw/lang×5/manifest/图标）"

# --- 4) SW 版本戳与 wasm 一致 ---
WASM="$(ls "$DIST"/*_bg.wasm 2>/dev/null | head -1)"
if [ -n "$WASM" ] && [ -f "$DIST/sw.js" ]; then
  MD5="$(md5sum "$WASM" | cut -c1-10)"
  VER="$(grep -o "const VERSION = '[a-f0-9]*'" "$DIST/sw.js" | head -1 | grep -o "[a-f0-9]\{10,\}")"
  if [ "$VER" = "$MD5" ]; then
    ok "sw.js VERSION 与 wasm md5 前 10 位一致（$MD5）"
  else
    bad "sw.js VERSION（$VER）≠ wasm md5 前 10 位（$MD5），产物非同一次构建"
  fi
fi

# --- 5) 已移除概念残留扫描 ---
# 词表维护处：概念被移除时把特征词加进 RESIDUE_WORDS。
# 注意：裸词 "Drive" 不入表——backup.icloud_note 里的
# "iCloud Drive" 是现行有效文案（用户拍板保留的静态说明行），
# 谷歌概念由 谷歌/Google/谷歌云/云端同步/云同步 特征词覆盖。
python3 - "$WEB" <<'PYEOF'
import json, pathlib, re, sys
web = pathlib.Path(sys.argv[1])
RESIDUE_WORDS = ["谷歌", "Google", "谷歌云", "云端同步", "云同步"]
hits = []

# 5a) 五包全部「值」逐包扫（键名不扫：键是内部标识）。
for f in sorted((web / "lang").glob("*.json")):
    pack = json.loads(f.read_text(encoding="utf-8"))
    for k, v in pack.items():
        for w in RESIDUE_WORDS:
            if w in v:
                hits.append(f"lang/{f.name} 键 {k}：值含残留词「{w}」→ {v}")

# 5b) 设置/备份 UI 源码：剥掉注释行与 Diag 行后扫字符串面。
def strip_non_user_lines(text):
    out, in_block = [], False
    for line in text.splitlines():
        s = line.strip()
        if in_block:
            if "*/" in s:
                in_block = False
            continue
        if s.startswith("/*"):
            if "*/" not in s[2:]:
                in_block = True
            continue
        if s.startswith("//"):
            continue
        if "diag::" in line or "diag!" in line:
            continue
        out.append(line)
    return out

for rel in ["src/settings.rs", "src/backup.rs"]:
    p = web / rel
    if not p.exists():
        continue
    lines = strip_non_user_lines(p.read_text(encoding="utf-8"))
    for i, line in enumerate(lines, 1):
        for w in RESIDUE_WORDS:
            if w in line:
                hits.append(f"{rel}（剥注释后第 {i} 行）：含残留词「{w}」→ {line.strip()[:80]}")

if hits:
    for h in hits:
        print(f"✗ 残留扫描命中：{h}")
    sys.exit(1)
print("✓ 残留扫描：五包值 + 设置/备份源码字符串无已移除概念残留")
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 6) 标题面构造门禁（标题胶囊全面重构后立） ---
# 6a) 标题面禁内距左右分写：标题的左右对称由「padding-
# inline 单值」构造保证，控制器源码（title.rs /
# title_controller.rs）与标题 CSS 规则里不得出现
# padding-left/right 或 paddingLeft/Right 分写。
# 6b) 禁旧标题桥符号残留：titleText / titleLatch /
# syncTitleLayout 是已删除的多写者桥协议，src 全域（剥
# 行注释后）不得再出现——出现即说明旧写者被带回。
python3 - "$WEB" <<'PYEOF'
import pathlib, sys
web = pathlib.Path(sys.argv[1])
hits = []

def code_lines(text):
    # 剥行注释（Rust // 与桥内 JS // 同形；块注释内的历史
    # 提及不算代码残留，与第 5 节口径一致的精神）
    return [l for l in text.splitlines() if not l.strip().startswith("//")]

SPLIT = ["padding-left", "padding-right", "paddingLeft", "paddingRight"]
for rel in ["src/editor/title.rs", "src/editor/title_controller.rs"]:
    p = web / rel
    if not p.exists():
        hits.append(f"{rel} 缺失")
        continue
    for i, line in enumerate(code_lines(p.read_text(encoding="utf-8")), 1):
        for w in SPLIT:
            if w in line:
                hits.append(f"{rel}（剥注释后第 {i} 行）：标题面内距分写「{w}」→ {line.strip()[:80]}")

styles = web / "styles"
for f in sorted(styles.glob("*.css")):
    for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        if "editor-title" in line:
            for w in ["padding-left", "padding-right"]:
                if w in line:
                    hits.append(f"styles/{f.name} 第 {i} 行：标题规则内距分写「{w}」")

BANNED = ["titleText", "titleLatch", "syncTitleLayout"]
for p in sorted((web / "src").rglob("*.rs")):
    rel = p.relative_to(web)
    for i, line in enumerate(code_lines(p.read_text(encoding="utf-8")), 1):
        for w in BANNED:
            if w in line:
                hits.append(f"{rel}（剥注释后第 {i} 行）：旧标题桥符号「{w}」残留 → {line.strip()[:80]}")

if hits:
    for h in hits:
        print(f"✗ 标题门禁命中：{h}")
    sys.exit(1)
print("✓ 标题门禁：标题面无内距分写、旧标题桥符号零残留")
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 7) i18n 深检：占位符一致 / 僵尸键（硬门禁）+ 疑似漏译（警告） ---
# 7a) 占位符跨包一致：{name} 是 tf() 的插值面，某包漏写
# 或多写会让该语言渲染缺量/多量，同一键的占位符集合
# 五包必须齐平。
# 7b) 僵尸键：键在 src 全域（*.rs）以键界正则（前后非
# [A-Za-z0-9_.]——下划线与点同属键内字符，防 list.expand
# 命中 list.expand_n 一类前缀误报）零命中 = 无代码引用，
# 判失败，删键或补引用。动态拼键面已核：src 内无 format!
# 拼键，键均以字面量或字面量变量（settings.font_* 段控、
# callout title_key 等）引用，字面全量扫描即完备。
# 7c) 疑似漏译仅警告：非中文包值与 zh-CN 完全相同且含
# 汉字——繁简同字/专名同形多为正常，只列示不判失败。
python3 - "$WEB" <<'PYEOF'
import json, pathlib, re, sys
web = pathlib.Path(sys.argv[1])
packs = {}
for f in sorted((web / "lang").glob("*.json")):
    packs[f.stem] = json.loads(f.read_text(encoding="utf-8"))
base = packs.get("zh-CN", {})
fail = False

PH = re.compile(r"\{[^{}]*\}")
mismatch = 0
for k in base:
    ref_name, ref_set = None, None
    for name, pack in packs.items():
        if k not in pack:
            continue
        s = tuple(sorted(PH.findall(pack[k])))
        if ref_set is None:
            ref_name, ref_set = name, s
        elif s != ref_set:
            print(f"✗ 占位符不一致：键 {k} 在 {name} 为 {list(s)}，与 {ref_name} 的 {list(ref_set)} 不同")
            mismatch += 1
if mismatch == 0:
    print(f"✓ 占位符跨包一致：{len(base)} 键的 {{占位符}} 集合五包齐平")
else:
    fail = True

corpus = ""
for p in sorted((web / "src").rglob("*.rs")):
    corpus += p.read_text(encoding="utf-8") + "\n"
def referenced(key):
    pat = re.compile(r"(?<![A-Za-z0-9_.])" + re.escape(key) + r"(?![A-Za-z0-9_.])")
    return pat.search(corpus) is not None
zombies = [k for k in base if not referenced(k)]
if zombies:
    for k in zombies:
        print(f"✗ 僵尸键：{k}（src 全域零引用，删键或补引用）")
    fail = True
else:
    print(f"✓ 僵尸键扫描：{len(base)} 键在 src 全域均有引用")

HAN = re.compile(r"[\u4e00-\u9fff]")
for name, pack in packs.items():
    if name == "zh-CN":
        continue
    same = [k for k in base if pack.get(k) == base[k] and HAN.search(base[k] or "")]
    if same:
        shown = ", ".join(same[:6]) + ("…" if len(same) > 6 else "")
        print(f"⚠ 疑似漏译（仅警告）：{name} 与 zh-CN 同值且含汉字 {len(same)} 键：{shown}")

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 8) dist 体积预算门（批 13 P-D4，只落门禁不切构建） ---
# 预算依据：构建 cf1420c69b 实测 dist 总计 4,821,730 B、
# wasm 3,402,741 B，预算取实测 +5% 取整。体积结构性下降的
# 两项已登记待启用（本批不切换）：① build.sh 加 wasm-opt
# -Oz——须链尾全量冒烟背书后另行固化；② 图标出 192/512
# 压缩档（现单文件 Mynoteicon.png 约 1.25MB，占 dist 约
# 26%）。启用任一项后按新实测下调预算并更新此注释。
DIST_BUDGET=5062816
WASM_BUDGET=3572878
if [ -d "$DIST" ]; then
  TOTAL_BYTES="$(find "$DIST" -type f -exec stat -c%s {} + | awk '{s+=$1} END {print s}')"
  WASM_BYTES="$(stat -c%s "$WASM" 2>/dev/null || echo 0)"
  if [ "$TOTAL_BYTES" -le "$DIST_BUDGET" ]; then
    ok "dist 体积 $TOTAL_BYTES B ≤ 预算 $DIST_BUDGET B"
  else
    bad "dist 体积 $TOTAL_BYTES B 超预算 $DIST_BUDGET B（依据见第 8 节注释）"
  fi
  if [ "$WASM_BYTES" -le "$WASM_BUDGET" ]; then
    ok "wasm 体积 $WASM_BYTES B ≤ 预算 $WASM_BUDGET B"
  else
    bad "wasm 体积 $WASM_BYTES B 超预算 $WASM_BUDGET B（依据见第 8 节注释）"
  fi
fi

# --- 9) 串行同帧防回归静态锁（编辑→列表，审计恢复集 (a) 后立） ---
# 行为侧判据在 probe_page_transitions 的「防回归判据组
# （串行同帧语义）」；本节守两条源码级结构不变量，防
# #14 重叠交接（离页层 fixed + 列表预挂载 + 挂载/翻转
# 解耦——审计定罪的白带唯一结构差异）以改代码的形式
# 回归：
#   (i) .editor-stage.leaving 规则不得含 position:fixed
#       ——离页编辑器必须在流内以当前页身份出场；
#   (ii) main.rs 列表渲染分支必须以 editor_slot.is_none()
#       为门——槽位在场即不挂列表，列表挂载只发生在
#       提交帧与卸载、翻色同帧。
python3 - "$WEB" <<'PYEOF'
import pathlib, re, sys
web = pathlib.Path(sys.argv[1])
fail = False

css = (web / "styles/base.css").read_text(encoding="utf-8")
m = re.search(r"\.editor-stage\.leaving\s*\{([^}]*)\}", css)
if not m:
    print("✗ 防回归静态锁 (i)：styles/base.css 未找到 .editor-stage.leaving 规则，无法确认离页舞台在流内")
    fail = True
elif re.search(r"position\s*:\s*fixed", m.group(1)):
    print("✗ 防回归静态锁 (i) 违反：styles/base.css 的 .editor-stage.leaving 含 position:fixed——离页舞台必须在流内（串行同帧语义不变量），#14 重叠交接的 fixed 离页层不得回归")
    fail = True
else:
    print("✓ 防回归静态锁 (i)：.editor-stage.leaving 无 position:fixed（离页舞台在流内）")

main = (web / "src/main.rs").read_text(encoding="utf-8")
if re.search(r"else if editor_slot\.is_none\(\)", main):
    print("✓ 防回归静态锁 (ii)：main.rs 列表渲染分支以 editor_slot.is_none() 为门")
else:
    print("✗ 防回归静态锁 (ii) 违反：main.rs 列表渲染分支未以 editor_slot.is_none() 为门——槽位口径是串行同帧交换的挂载门，改动须连同 Nav 时序一起评审")
    fail = True

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 10) 备份确认底表进场无位移静态锁（sheetIn 去位移后立） ---
# sheetIn 原 from 带 translateY(20px) 位移：该 transform
# 在进场动画结束后仍持续作用，与底表底部全幅渲染冲突，
# 为确认弹窗底部实心栏的真机定案根因（2026-11-23 去除
# 位移后用户真机确认底部渲染恢复正常）。本节守两条源码
# 级结构不变量，改动须连同底表进场呈现一起评审：
#   (i) @keyframes sheetIn 规则块内不得出现 transform
#       声明——进场只许 opacity 淡入；
#   (ii) .backup-modal 的 animation 声明必须仍指向
#       sheetIn——防整条动画被误删或换名绕过 (i)。
python3 - "$WEB" <<'PYEOF'
import pathlib, re, sys
web = pathlib.Path(sys.argv[1])
fail = False

css = (web / "styles/panels.css").read_text(encoding="utf-8")

m = re.search(r"@keyframes\s+sheetIn\s*\{", css)
if not m:
    print("✗ 底表进场静态锁 (i)：styles/panels.css 未找到 @keyframes sheetIn，无法确认进场无位移")
    fail = True
else:
    # 花括号配平提取整个关键帧块（from/to 内层各有嵌套）
    depth = 0
    end = None
    for i in range(m.end() - 1, len(css)):
        if css[i] == "{":
            depth += 1
        elif css[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    block = css[m.start():end + 1] if end is not None else ""
    if re.search(r"transform\s*:", block):
        print("✗ 底表进场静态锁 (i) 违反：@keyframes sheetIn 含 transform 声明——进场只许 opacity 淡入；位移动画与底表底部全幅渲染冲突（确认弹窗底部实心栏真机定案根因），不得再给该底表进场加位移/缩放")
        fail = True
    else:
        print("✓ 底表进场静态锁 (i)：@keyframes sheetIn 无 transform（仅 opacity 淡入）")

m2 = re.search(r"\.backup-modal\s*\{([^}]*)\}", css)
anim = re.search(r"animation\s*:\s*([^;]+)", m2.group(1)) if m2 else None
if not m2:
    print("✗ 底表进场静态锁 (ii)：styles/panels.css 未找到 .backup-modal 规则，无法确认进场动画指向")
    fail = True
elif not anim:
    print("✗ 底表进场静态锁 (ii) 违反：.backup-modal 无 animation 声明——进场动画须保留并指向 sheetIn（仅淡入），整条删除须连同底表进场呈现一起评审")
    fail = True
elif not re.search(r"\bsheetIn\b", anim.group(1)):
    print("✗ 底表进场静态锁 (ii) 违反：.backup-modal 的 animation 未指向 sheetIn——换名会绕过 (i) 的位移检查，改名须连同本节一并评审")
    fail = True
else:
    print("✓ 底表进场静态锁 (ii)：.backup-modal 的 animation 仍指向 sheetIn")

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 11) 根色写入收口静态锁（2026-11-24 图片页化后改） ---
# 根色写入只经 main.rs 的唯一写者；editor 侧两处先行写入
# （换色 apply_bg_color、scheme 分支）是既定形态——先行值
# = effective_bg 直算（派生已退化为页面状态纯函数、
# target = base，先行与派生同值），以变量 t 落盘。本节
# 守两条源码级不变量，改动须连同根色派生一起评审：
#   (i) editor.rs 中 apply_root_bg 出现次数恰为 2，且两
#       处均为 crate::apply_root_bg(Some(t)) 形态——新增
#       直调点（自算色值绕开派生同值口径）、旧形态直
#       调、注释顺带提及都会使计数/形态不合而判红；
#   (ii) src 全域零残留锁：压暗栈（DimStack/DimLayer/
#       DimGuard）、浮层在场派生输入（LightboxPresence、
#       derive_root_target）、LBX 打点（log_lbx）与浮层
#       本体（lightbox/Lightbox/LBX/lbx 诸形态）已于图
#       片页化时整删——任何 .rs 文件（含注释）再现任一
#       已退役符号即判红，防死代码以注释/残桩形态回潮。
python3 - "$WEB" <<'PYEOF'
import pathlib, re, sys
web = pathlib.Path(sys.argv[1])
fail = False

editor = (web / "src/editor.rs").read_text(encoding="utf-8")
hits = re.findall(r"apply_root_bg", editor)
calls = re.findall(r"crate::apply_root_bg\(Some\(t\)\)", editor)
if len(hits) == 2 and len(calls) == 2:
    print("✓ 根色收口静态锁 (i)：editor.rs 的 apply_root_bg 仅两处既有先行写入点（effective_bg 直算同值落盘）、无其他出现")
else:
    print(f"✗ 根色收口静态锁 (i) 违反：editor.rs 中 apply_root_bg 出现 {len(hits)} 次、合法形态 {len(calls)} 次（应各为 2）——editor 侧先行写入只准 effective_bg 直算同值后以变量落盘，新增直调点/旧形态直调/注释提及均须连同根色派生一起评审")
    fail = True

RETIRED = re.compile(r"DimStack|DimLayer|DimGuard|LightboxPresence|derive_root_target|log_lbx|[Ll]ightbox|LBX|lbx")
bad = []
for p in sorted((web / "src").rglob("*.rs")):
    if RETIRED.search(p.read_text(encoding="utf-8")):
        bad.append(str(p.relative_to(web / "src")))
if bad:
    print("✗ 根色收口静态锁 (ii) 违反：src 出现已退役符号残留（" + "、".join(bad) + "）——压暗栈/浮层在场派生输入/LBX 打点已整删，不得以代码或注释形态复活")
    fail = True
else:
    print("✓ 根色收口静态锁 (ii)：src 全域无已退役符号残留（压暗栈/浮层在场输入/LBX 打点零残留）")

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 12) 页面过渡统一机制静态锁（2026-11-24 顶栏根治） ---
# 全应用页面过渡只有一套机制（diagnose_settings_topbar
# .md）：前进 go 即刻挂载、返回 go_back 本页本体在流内
# 出场 + 提交点翻转/恢复滚动/打提交普查。旧栈式快照交
# 接（即刻提交 + fixed 离页层重挂快照、滚动不管理）已
# 整套退役，本节守三条源码级不变量：
#   (i) styles 四文件不得再有 .page-leaving 规则块；
#       main.rs 不得再有 stack_current_page /
#       render_leaving_page 标识符与 page-leaving 渲染
#       串（diag.rs CENSUS 的同名计数是恒 0 哨兵，不在
#       本节扫描面内）；
#   (ii) main.rs 的 on_back 调用点必须全部经 go_back
#       （不得有 on_back 直调 go 的即刻提交形态），且
#       go_back 调用点不少于 5（诊断/语言/备份/设置/
#       图片五页返回）；
#   (iii) 组件页提交打点（TRANS {name} -> committed）
#       与 fn go_back 必须在场（提交普查不得静默退化）。
python3 - "$WEB" <<'PYEOF'
import pathlib, re, sys
web = pathlib.Path(sys.argv[1])
fail = False

css_all = ""
for name in ("tokens", "base", "editor", "panels"):
    css_all += (web / "styles" / f"{name}.css").read_text(encoding="utf-8")
main = (web / "src/main.rs").read_text(encoding="utf-8")

bad = []
if re.search(r"\.page-leaving\s*\{", css_all):
    bad.append("styles 出现 .page-leaving 规则块")
for ident in ("stack_current_page", "render_leaving_page", 'class: "page-leaving"'):
    if ident in main:
        bad.append(f"main.rs 出现 {ident}")
if bad:
    print("✗ 过渡统一静态锁 (i) 违反：" + "；".join(bad) + "——栈式快照交接已整套退役，离页层/快照渲染不得以任何形态复活（确诊见 diagnose_settings_topbar.md）")
    fail = True
else:
    print("✓ 过渡统一静态锁 (i)：styles 无 .page-leaving 规则、main.rs 无快照交接标识符与离页层渲染串")

bad_back = re.findall(r"on_back: move \|_\| nav\.go\(", main)
good_back = re.findall(r"on_back: move \|_\| nav\.go_back\(", main)
if bad_back or len(good_back) < 5:
    print(f"✗ 过渡统一静态锁 (ii) 违反：on_back 直调 go {len(bad_back)} 处、经 go_back {len(good_back)} 处（应 0 / ≥5）——全部返回必须走 go_back 的提交点语义，即刻提交的返回是顶栏截断的确诊根因")
    fail = True
else:
    print(f"✓ 过渡统一静态锁 (ii)：全部 on_back 经 go_back（{len(good_back)} 处）、无即刻提交返回")

if "fn go_back" not in main or "TRANS {name} -> committed gen={g}" not in main:
    print("✗ 过渡统一静态锁 (iii) 违反：fn go_back 或组件页 committed 打点缺失——返回提交点与其实测打点不得退化/静默删除")
    fail = True
else:
    print("✓ 过渡统一静态锁 (iii)：go_back 与组件页 committed 提交打点在场")

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

echo "---"
if [ $FAIL -eq 0 ]; then
  echo "VERIFY RUSTWEB ALL PASS"
else
  echo "VERIFY RUSTWEB FAILED"
fi
exit $FAIL
