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

echo "---"
if [ $FAIL -eq 0 ]; then
  echo "VERIFY RUSTWEB ALL PASS"
else
  echo "VERIFY RUSTWEB FAILED"
fi
exit $FAIL
