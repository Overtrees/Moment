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

echo "---"
if [ $FAIL -eq 0 ]; then
  echo "VERIFY RUSTWEB ALL PASS"
else
  echo "VERIFY RUSTWEB FAILED"
fi
exit $FAIL
