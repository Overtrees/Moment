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
#      editor 模块（editor.rs + editor/ 子模块）中
#      apply_root_bg 只准以两处既有先行写入
#      点的形态存在（先行值 = effective_bg 直算、与 App
#      派生同值，以变量落盘），出现次数恰为 2 且形态全
#      合——新增直调点、旧形态直调、注释提及一律判红；
#      src 全域禁已退役符号残留（压暗栈/浮层在场派生输
#      入/LBX 打点已整删，代码与注释均不得复现）。
#  13) 救援层呈现收敛静态锁（2026-11-24 救援层与现行
#      机制统一）：index.html 外壳救援面板不得再自成
#      一套——(i) 遮罩 #mn-rescue 必须 transparent（与
#      备份确认弹窗同口径、无压暗），退役压暗值与旧
#      玻璃浅值全文件零残留、底表玻璃两值在外壳各只
#      许出现三次（面板卡 + 两条提示条 @supports 复
#      刻各一）；(ii) 面板卡底色必须与确认弹窗底
#      表底色逐值相等——底表 .backup-modal 取
#      var(--glass-overlay-bg)，卡按 tokens.css 该令
#      牌四值级联（基础浅/深实色 + @supports 浅/深
#      玻璃值）同序同值复刻（用户 2026-11-24 改判：
#      取底表同款、不再取页根色），滤镜同口径逐段
#      对齐 --glass-overlay-filter（玻璃段同值、基
#      础/降级段 none，2026-11-25 卡补模糊）；(iii) 进场必
#      须指向 mnRescueIn 且时长 0.25s（底表
#      --motion-sheet 同口径），关键帧块内不得有
#      transform（仅 opacity 淡入）；(v) 两条提示
#      条（SW 更新条/救援条）样式与应用 toast
#      （.backup-toast）逐值对齐（用户 2026-11-24
#      指示）：底色八值全级联（令牌四值 + base.css
#      提实四值）、滤镜/边框/圆角/字色/进场关键帧
#      与 toast 同值，旧条值（0.85/0.88 玻璃、20px
#      圆角、0.28s 旧曲线、旧阴影）零残留；按下态
#      扩锁（2026-11-25）：两条四钮 + 救援面板钮须
#      自带 tap-highlight 透明/圆角/:active（与令牌
#      同值），应用 .undo-toast-btn 同步同口径——
#      外壳不得靠应用全局 * 规则兜底 tap 透明。
#  14) 桥 JS 语法门（批 14 P-D5 合流项）：src/editor/js/
#      editor.js 经 include_str! 装载，Rust 侧只当字符
#      串、语法错 cargo 不拦——以 node --check 为唯一语
#      法门；node 不在 PATH 时打印跳过、不判红（无 node
#      的 CI 环境同口径）。
#  15) SQLite 阶段二静态锁：存储 Worker crate 与 persist
#      门面在位、build.sh 的 MYNOTE_SQLITE 构建段与 sw
#      CORE 注入串在位、消费面调用点不得再直引 idb 存
#      储函数（blob_url 纯函数除外，经 persist 门面）；
#      dist 为 sqlite 构建时另核 Worker 资产齐全且三条
#      资产都在 dist/sw.js 的 CORE 清单内。
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
# 2026-11-24 重定基线：其后功能增长（第五/六轮链尾各批、
# 批 11 性能、封面统一派生、批 12 W-3 天气）使 wasm 达
# 3,589,923 B、dist 5,017,371 B（构建 8a987721e0 实测），
# 增长逐项可归因、非异常膨胀；预算按同口径（实测 +5%）
# 重定。批 12 后续项再增长时按实测续更此注释。
# 2026-11-24 再重定：8a987721e0 之后落地的 B 组余项、
# 去兼容第四/五步（模型单形化 + manifest 类型建模）、
# SW 更新提示、救援层与 panic 取证钩使 wasm 达
# 3,774,658 B、dist 5,241,206 B（与现行生产构建
# 57f59539a3 同尺寸实测），逐项可归因；预算按同口径
# （实测 +5%）续更。
# 2026-11-25 再重定：现行生产 95e831830d（wasm
# 3,868,039 B）之后落地批 14 二轮拆分（editor 模块树
# 拆分、二分实测 3556cfc 构建 wasm 3,905,726 B）与
# Diag 页改版（存储升级：等级维/按天归档/自动删除/
# 视窗页导出 + DiagLogPage 新页）使 wasm 达 3,995,786 B、
# dist 5,466,709 B（本机构建实测），增长逐项可归因；
# 预算按同口径（实测 +5%）续更。
DIST_BUDGET=5740044
WASM_BUDGET=4195575
# 2026-11-25 SQLite 阶段二口径：dist 含 storage-worker
# 资产时（MYNOTE_SQLITE=1 演练构建）另加引擎增量预算——
# spike 实测 Worker wasm（含 SQLite 本体）1,678,202 B、
# 应用 wasm 因 persist 桥增长约 36 KB，增量合计约
# 2.15 MB；增量预算取 2,300,000 B（含 bindgen 胶水与演练
# 台页），默认构建口径不变。阶段三切生产时按当时实测把
# 增量并入主预算重定基线。
SQLITE_DIST_ALLOWANCE=2300000
if [ -d "$DIST" ]; then
  if [ -d "$DIST/storage-worker" ]; then
    DIST_BUDGET=$((DIST_BUDGET + SQLITE_DIST_ALLOWANCE))
  fi
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
#   (i) editor 模块（editor.rs + editor/ 子模块树，批 14
#       二轮拆分后按模块树计、三轮 hooks 子目录以 rglob
#       覆盖）中 apply_root_bg 出现次数
#       恰为 2，且两处均为 crate::apply_root_bg(Some(t))
#       形态——新增
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
for p in sorted((web / "src/editor").rglob("*.rs")):
    editor += p.read_text(encoding="utf-8")
hits = re.findall(r"apply_root_bg", editor)
calls = re.findall(r"crate::apply_root_bg\(Some\(t\)\)", editor)
if len(hits) == 2 and len(calls) == 2:
    print("✓ 根色收口静态锁 (i)：editor 模块的 apply_root_bg 仅两处既有先行写入点（effective_bg 直算同值落盘）、无其他出现")
else:
    print(f"✗ 根色收口静态锁 (i) 违反：editor 模块中 apply_root_bg 出现 {len(hits)} 次、合法形态 {len(calls)} 次（应各为 2）——editor 侧先行写入只准 effective_bg 直算同值后以变量落盘，新增直调点/旧形态直调/注释提及均须连同根色派生一起评审")
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
#       与 fn go_back 必须在场（提交普查不得静默退化）；
#   (iv) 进/出场动画落点统一（2026-11-24 过渡一致性审
#       计 D-1，diagnose_transition_consistency.md）：
#       五个组件页（设置/备份/图片/诊断/语言）的动画只
#       挂内容层（page-content + page-slide-in/out，
#       PageHead 静止，原版 SettingsView/BackupView 口
#       径）；main.rs 不得再有根层落点形态（根 div 以
#       closing 在 page-slide-out/page-enter 间切换——
#       诊断/语言曾如此、整页连页头滑动，与同级页不一
#       致）。列表根 .page-enter 是另一回事（整页根填
#       充口径，base.css 注释在案），不在本条扫描面。
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

settings = (web / "src/settings.rs").read_text(encoding="utf-8")
n_in = (main + settings).count("page-content page-slide-in")
n_out = (main + settings).count("page-content page-slide-out")
root_form = 'if closing { "page-slide-out" } else { "page-enter" }' in main
if n_in < 5 or n_out < 5 or root_form:
    print(f"✗ 过渡统一静态锁 (iv) 违反：内容层 page-slide-in {n_in} 处 / page-slide-out {n_out} 处（应各 ≥5：设置/备份/图片/诊断/语言），根层落点形态 {'在场' if root_form else '不在场'}——进/出场动画只挂内容层、PageHead 静止（审计 D-1），根层整页滑动不得复活")
    fail = True
else:
    print(f"✓ 过渡统一静态锁 (iv)：五页动画落点统一在内容层（slide-in {n_in} / slide-out {n_out}）、无根层落点形态")

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 13) 救援层呈现收敛静态锁（2026-11-24 救援层与现行机制统一） ---
# 救援层在 index.html 外壳内联、与应用解耦（应用死了也
# 要能出面板），故不能引用 tokens.css 令牌——收敛靠同
# 值复刻 + 本节逐值对齐锁守：外壳数值与应用令牌任一侧
# 改动而另一侧没跟，本节判红。守五条不变量：
#   (i) 遮罩 #mn-rescue 的 background 必须 transparent
#       （与 .backup-modal-scrim 同口径、无压暗）；退
#       役值（0.45 压暗、0.92 旧玻璃浅值）全文件零残
#       留；底表玻璃两值（0.84 浅 / 0.94 深）在外壳
#       只许各出现三次（卡 + 两条提示条同款复刻处）；
#   (ii) 面板卡 .mn-rescue-card 六条规则（基础浅/深 +
#       @supports 浅/深 + @supports-not + reduced-
#       transparency，级联序同 tokens.css）的
#       background（仅四条带底色者）必须与确认弹窗底
#       表底色 var(--glass-overlay-bg) 的四值逐值相
#       等；滤镜须与底表同口径逐段对齐
#       --glass-overlay-filter（玻璃段浅/深同值、基
#       础与降级段 none，2026-11-25 用户指示卡补模
#       糊）；底表 background 来源若不再是该变量，
#       本节一并判红须连同评审；
#   (iii) 卡的 animation 必须指向 mnRescueIn 且时长
#       0.25s（--motion-sheet 250ms 同口径）；
#   (iv) @keyframes mnRescueIn 块内不得有 transform
#       ——进场仅 opacity 淡入（与第 10 节 sheetIn 同理）；
#   (v) 两条提示条（#mn-swupd / #mn-rescue-bar）与
#       应用 toast（.backup-toast）逐值对齐：底色八
#       值全级联（tokens 四值 + base.css 提实四值）、
#       滤镜/边框/圆角/字色/钮值/进场（mnSwupdIn 关
#       键帧体与 toastSlideUpBar 同值、时长曲线走
#       --motion-pop/--motion-spring），旧条值零残留；
#       按下态（2026-11-25 扩）：两条四钮自带
#       -webkit-tap-highlight-color: transparent +
#       border-radius 999px（--radius-999 同值）+
#       :active 底（动作钮 --fill-accent-10、关闭钮
#       --fill-hover-strong 同值复刻），救援面板动作
#       钮自带 tap 透明 + :active opacity 0.75，应
#       用 .undo-toast-btn 以 var 形态同步同口径。
python3 - "$WEB" <<'PYEOF'
import pathlib, re, sys
web = pathlib.Path(sys.argv[1])
fail = False

html = (web / "index.html").read_text(encoding="utf-8")
tokens = (web / "styles/tokens.css").read_text(encoding="utf-8")
panels = (web / "styles/panels.css").read_text(encoding="utf-8")

def balanced(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return ""

def norm(v):
    return re.sub(r"\s+", "", v).lower()

# 底表侧：.backup-modal 的 background 必须仍取
# var(--glass-overlay-bg)——底色来源变了须连同本节评审。
sm = re.search(r"\.backup-modal\s*\{([^}]*)\}", panels)
if not sm or "background: var(--glass-overlay-bg)" not in sm.group(1):
    print("✗ 救援呈现静态锁：panels.css .backup-modal 的 background 不是 var(--glass-overlay-bg)，底表底色来源已变，须连同本节一并评审")
    fail = True
else:
    print("✓ 救援呈现静态锁：底表 .backup-modal 底色来源为 var(--glass-overlay-bg)")

# 令牌侧：--glass-overlay-bg 在 tokens.css 出现四次，顺
# 序即级联序：基础浅 #ffffff、深 #1c1c1e、@supports
# 浅 rgba(255,255,255,0.84)、深 rgba(28,28,30,0.94)。
toks = [norm(v) for v in re.findall(r"--glass-overlay-bg\s*:\s*(#[0-9a-fA-F]{6}|rgba\([^)]*\))", tokens)]
if len(toks) != 4:
    print(f"✗ 救援呈现静态锁：tokens.css 的 --glass-overlay-bg 出现 {len(toks)} 次（应 4：基础浅/深 + @supports 浅/深），无法对齐")
    fail = True
    toks = None

# (i) 遮罩透明 + 退役值零残留
m = re.search(r"#mn-rescue\s*\{([^}]*)\}", html)
if not m:
    print("✗ 救援呈现静态锁 (i)：index.html 未找到 #mn-rescue 规则")
    fail = True
elif not re.search(r"background\s*:\s*transparent", m.group(1)):
    print("✗ 救援呈现静态锁 (i) 违反：#mn-rescue 遮罩非 transparent——救援面板遮罩与备份确认弹窗同口径（透明、无压暗），压暗呈现不得回归")
    fail = True
else:
    print("✓ 救援呈现静态锁 (i)：#mn-rescue 遮罩 transparent（无压暗）")
# 值检查只读 CSS 本体：注释散文里提及数值不算呈现值。
html_nc = re.sub(r"/\*.*?\*/", "", html, flags=re.S)
RETIRED = ["rgba(0, 0, 0, 0.45)", "rgba(255, 255, 255, 0.92)"]
resid = [v for v in RETIRED if v in html_nc]
if resid:
    print("✗ 救援呈现静态锁 (i) 违反：index.html 残留退役呈现值 " + "、".join(resid) + "（压暗/旧玻璃浅值已收敛退役，零残留）")
    fail = True
else:
    print("✓ 救援呈现静态锁 (i)：退役压暗/旧玻璃浅值零残留")
# 底表玻璃两值原在退役清单（0.94 深值曾是卡旧玻璃值），
# 现为底表/toast 同款值——只许在同款复刻处出现：面板
# 卡 @supports 一处 + 两条提示条 @supports 各一处。
for gv in ["rgba(255, 255, 255, 0.84)", "rgba(28, 28, 30, 0.94)"]:
    n = html_nc.count(gv)
    if n != 3:
        print(f"✗ 救援呈现静态锁 (i) 违反：底表玻璃值 {gv} 在 index.html 出现 {n} 次（应恰 3：卡底色复刻 1 + 两条提示条 @supports 复刻各 1），不得在外壳他处复用")
        fail = True
    else:
        print(f"✓ 救援呈现静态锁 (i)：底表玻璃值 {gv} 仅同款复刻三处（卡 + 两条）")

# (ii)(iii) 面板卡六条规则（基础浅/深 + @supports
# 浅/深 + @supports-not + reduced-transparency，出
# 现序须与 tokens.css 令牌级联序一致）
cards = [mm.group(1) for mm in re.finditer(r"#mn-rescue\s+\.mn-rescue-card\s*\{([^}]*)\}", html)]
if len(cards) != 6:
    print(f"✗ 救援呈现静态锁 (ii)：.mn-rescue-card 规则出现 {len(cards)} 条（应 6：基础浅/深 + @supports 浅/深 + @supports-not + reduced-transparency），无法确认底色/滤镜收敛")
    fail = True
else:
    def bg_of(rule):
        mm = re.search(r"background\s*:\s*(#[0-9a-fA-F]{6}|rgba\([^)]*\))", rule)
        return norm(mm.group(1)) if mm else None
    card_bgs = [b for b in (bg_of(c) for c in cards) if b is not None]
    if toks and card_bgs != toks:
        print(f"✗ 救援呈现静态锁 (ii) 违反：面板卡底色序列 {card_bgs} 与底表 --glass-overlay-bg 级联 {toks} 不逐值相等——面板底色须与确认弹窗底表同款，外壳与令牌任一侧改色须两侧同改")
        fail = True
    else:
        print(f"✓ 救援呈现静态锁 (ii)：面板卡底色与确认弹窗底表 --glass-overlay-bg 逐值相等（{' / '.join(toks or [])}）")
    # 滤镜逐段对齐（2026-11-25 卡补模糊）：六段的
    # backdrop-filter（含 -webkit- 前缀、两形须同值）
    # = [基础浅 none, 基础深 none, 玻璃浅, 玻璃深,
    # @supports-not none, reduced-transparency none]，
    # 玻璃两值取 tokens --glass-overlay-filter 浅/深。
    card_filters = [norm(v) for v in re.findall(r"--glass-overlay-filter\s*:\s*([^;]+);", tokens)]
    if len(card_filters) != 2:
        print(f"✗ 救援呈现静态锁 (ii)：tokens.css 的 --glass-overlay-filter 出现 {len(card_filters)} 次（应 2：浅/深），无法对齐面板卡滤镜")
        fail = True
    else:
        exp_filters = ["none", "none", card_filters[0], card_filters[1], "none", "none"]
        got_filters = [[norm(v) for v in re.findall(r"(?:-webkit-)?backdrop-filter\s*:\s*([^;]+);", c)] for c in cards]
        badf = [i for i, (g, e) in enumerate(zip(got_filters, exp_filters)) if g != [e, e]]
        if badf:
            print(f"✗ 救援呈现静态锁 (ii) 违反：面板卡滤镜段 {badf} 与底表 --glass-overlay-filter 级联 {exp_filters} 不逐段相等——卡须与确认底表同口径带滤镜（玻璃段同值复刻、基础/降级段 none），实测 {got_filters}")
            fail = True
        else:
            print("✓ 救援呈现静态锁 (ii)：面板卡滤镜六段与 --glass-overlay-filter 逐段相等（玻璃浅/深同值、基础/降级 none）")
    anim = re.search(r"animation\s*:\s*([^;]+)", cards[0])
    if not anim or "mnRescueIn" not in anim.group(1) or "0.25s" not in anim.group(1):
        print("✗ 救援呈现静态锁 (iii) 违反：.mn-rescue-card 的 animation 未指向 mnRescueIn 0.25s——进场须与确认底表单一口径（250ms 仅淡入），整条删除/换名/改时长须连同本节一并评审")
        fail = True
    else:
        print("✓ 救援呈现静态锁 (iii)：面板进场指向 mnRescueIn 0.25s")

# (iv) mnRescueIn 关键帧无 transform
mk = re.search(r"@keyframes\s+mnRescueIn\s*\{", html)
if not mk:
    print("✗ 救援呈现静态锁 (iv)：index.html 未找到 @keyframes mnRescueIn")
    fail = True
else:
    block = balanced(html, mk.start())
    if re.search(r"transform\s*:", block):
        print("✗ 救援呈现静态锁 (iv) 违反：@keyframes mnRescueIn 含 transform——进场仅许 opacity 淡入（与 sheetIn 同理），位移不得回归")
        fail = True
    else:
        print("✓ 救援呈现静态锁 (iv)：@keyframes mnRescueIn 无 transform（仅 opacity 淡入）")

# (v) 两条提示条与应用 toast 逐值对齐
base = (web / "styles/base.css").read_text(encoding="utf-8")

# toast 侧锚点：.backup-toast 的规格来源形态——来源变
# 了，提示条的收敛基准须连同本节一并评审。
tm = re.search(r"\.backup-toast\s*\{([^}]*)\}", base)
toast_anchors = ["background: var(--glass-overlay-bg)", "backdrop-filter: var(--glass-overlay-filter)",
                 "border: 0.5px solid var(--glass-overlay-border)", "border-radius: var(--radius-28)",
                 "animation: toastSlideUpBar var(--motion-pop) var(--motion-spring)"]
if not tm or any(a not in tm.group(1) for a in toast_anchors):
    print("✗ 救援呈现静态锁 (v)：base.css .backup-toast 规格来源形态已变（非 --glass-overlay-* + --radius-28 + toastSlideUpBar 令牌口径），提示条收敛基准须连同本节一并评审")
    fail = True
else:
    print("✓ 救援呈现静态锁 (v)：toast .backup-toast 规格来源为令牌口径")

def tok_vals(name, src):
    return [norm(v) for v in re.findall(re.escape(name) + r"\s*:\s*(#[0-9a-fA-F]{6}|rgba\([^)]*\))", src)]

def tok_raw(name, src):
    mm = re.search(re.escape(name) + r"\s*:\s*([^;]+);", src)
    return norm(mm.group(1)) if mm else None

borders = tok_vals("--glass-overlay-border", tokens)   # [浅, 深]
filters = [norm(v) for v in re.findall(r"--glass-overlay-filter\s*:\s*([^;]+);", tokens)]  # [浅, 深]
base_bg = tok_vals("--glass-overlay-bg", base)         # base.css 提实四值 [not浅, not深, rt浅, rt深]
textmains = tok_vals("--text-main", tokens)            # [浅, 深]
radius = tok_raw("--radius-28", tokens)
pop = tok_raw("--motion-pop", tokens)
spring = tok_raw("--motion-spring", tokens)
accent = tok_raw("--color-accent", tokens)
font14 = tok_raw("--font-14", tokens)
spec_ok = bool(toks) and len(borders) == 2 and len(filters) == 2 and len(base_bg) == 4 \
    and len(textmains) == 2 and all([radius, pop, spring, accent, font14])
if not spec_ok:
    print(f"✗ 救援呈现静态锁 (v)：toast 规格令牌抽取不全（border {len(borders)}/2、filter {len(filters)}/2、base 提实 bg {len(base_bg)}/4、text-main {len(textmains)}/2），无法对齐")
    fail = True
else:
    exp_bg = toks + base_bg

    def bg_of2(rule):
        mm = re.search(r"background\s*:\s*(#[0-9a-fA-F]{6}|rgba\([^)]*\))", rule)
        return norm(mm.group(1)) if mm else None

    for sel, btnsel in [("#mn-swupd", "#mn-swupd .mn-swupd-btn"), ("#mn-rescue-bar", "#mn-rescue-bar .mn-rescue-bar-btn")]:
        rules = [mm.group(1) for mm in re.finditer(re.escape(sel) + r"\s*\{([^}]*)\}", html_nc)]
        if len(rules) != 8:
            print(f"✗ 救援呈现静态锁 (v) 违反：{sel} 规则出现 {len(rules)} 条（应 8：基础浅/深 + @supports 浅/深 + @supports-not 浅/深 + reduced-transparency 浅/深），无法确认与 toast 全级联收敛")
            fail = True
            continue
        bgs = [bg_of2(r) for r in rules]
        if bgs != exp_bg:
            print(f"✗ 救援呈现静态锁 (v) 违反：{sel} 底色序列 {bgs} 与 toast 底色全级联 {exp_bg} 不逐值相等——外壳与应用任一侧改色须两侧同改")
            fail = True
        else:
            print(f"✓ 救援呈现静态锁 (v)：{sel} 底色八值与 toast 全级联逐值相等")
        b0, b1 = norm(rules[0]), norm(rules[1])
        want0 = [f"border-radius:{radius}", "padding:14px16px", f"border:0.5pxsolid{borders[0]}",
                 f"backdrop-filter:{filters[0]}", f"color:{textmains[0]}", f"font-size:{font14}",
                 "bottom:calc(env(safe-area-inset-bottom)+16px)"]
        miss = [w for w in want0 if w not in b0]
        anim = re.search(r"animation\s*:\s*([^;]+)", rules[0])
        if not anim or "mnSwupdIn" not in anim.group(1) or pop not in norm(anim.group(1)) or spring not in norm(anim.group(1)):
            miss.append("animation(mnSwupdIn + motion-pop + motion-spring)")
        if "box-shadow" in rules[0]:
            miss.append("box-shadow 应无（toast 无阴影）")
        want1 = [f"border-color:{borders[1]}", f"backdrop-filter:{filters[1]}", f"color:{textmains[1]}"]
        miss += [w for w in want1 if w not in b1]
        for idx in (4, 6):
            if "backdrop-filter:none" not in norm(rules[idx]):
                miss.append(f"第 {idx + 1} 条规则 backdrop-filter 应 none（提实口径）")
        if miss:
            print(f"✗ 救援呈现静态锁 (v) 违反：{sel} 基础/深色规则缺 toast 同值项：" + "、".join(miss))
            fail = True
        else:
            print(f"✓ 救援呈现静态锁 (v)：{sel} 圆角/内距/边框/滤镜/字色/安全区/进场与 toast 同值、无阴影")
        bm = re.search(re.escape(btnsel) + r"\s*\{([^}]*)\}", html_nc)
        bwant = [f"color:{accent}", "font-weight:600", "padding:6px10px", f"font-size:{font14}", "margin:-6px-4px-6px0"]
        if not bm or [w for w in bwant if w not in norm(bm.group(1))]:
            print(f"✗ 救援呈现静态锁 (v) 违反：{btnsel} 未与 toast 动作钮 .undo-toast-btn 同值（色/字重/内距/字号/负边距）")
            fail = True
        else:
            print(f"✓ 救援呈现静态锁 (v)：{btnsel} 与 .undo-toast-btn 同值")

    # (v) 按下态扩锁（2026-11-25 真机报更新条「点击更
    # 新」按下呈方形）：外壳钮必须自带 tap-highlight
    # 透明（不借应用 base.css 全局 * 规则——外壳须在
    # 应用未挂载时也成立）+ 胶囊圆角 + :active 底，
    # 值与令牌同值；应用 .undo-toast-btn 以 var 形态
    # 同步；救援面板动作钮同病同治（tap 透明 +
    # :active 压暗，其圆角 14px 为既有值不另锁）。
    r999 = tok_raw("--radius-999", tokens)
    fa10 = tok_vals("--fill-accent-10", tokens)
    fhs = tok_vals("--fill-hover-strong", tokens)
    if not r999 or len(fa10) != 1 or len(fhs) != 1:
        print(f"✗ 救援呈现静态锁 (v) 违反：按下态令牌抽取不全（radius-999 {r999}、fill-accent-10 {len(fa10)}/1、fill-hover-strong {len(fhs)}/1），无法对齐")
        fail = True
    else:
        def bg_norm(rule):
            mm = re.search(r"background\s*:\s*(#[0-9a-fA-F]{6}|rgba\([^)]*\))", rule)
            return norm(mm.group(1)) if mm else None
        press_fail = []
        for bsel, csel in [("#mn-swupd .mn-swupd-btn", "#mn-swupd .mn-swupd-close"),
                           ("#mn-rescue-bar .mn-rescue-bar-btn", "#mn-rescue-bar .mn-rescue-bar-close")]:
            for s, act_bg in [(bsel, fa10[0]), (csel, fhs[0])]:
                m1 = re.search(re.escape(s) + r"\s*\{([^}]*)\}", html_nc)
                if not m1 or "-webkit-tap-highlight-color:transparent" not in norm(m1.group(1)) or f"border-radius:{r999}" not in norm(m1.group(1)):
                    press_fail.append(f"{s} 缺 tap-highlight 透明或胶囊圆角")
                m2 = re.search(re.escape(s) + r":active\s*\{([^}]*)\}", html_nc)
                if not m2 or bg_norm(m2.group(1)) != act_bg:
                    press_fail.append(f"{s}:active 底非令牌同值（应 {act_bg}）")
        pm = re.search(r"#mn-rescue\s+\.mn-rescue-actions\s+button\s*\{([^}]*)\}", html_nc)
        if not pm or "-webkit-tap-highlight-color:transparent" not in norm(pm.group(1)):
            press_fail.append("救援面板动作钮缺 tap-highlight 透明")
        pa = re.search(r"#mn-rescue\s+\.mn-rescue-actions\s+button:active\s*\{([^}]*)\}", html_nc)
        if not pa or "opacity:0.75" not in norm(pa.group(1)):
            press_fail.append("救援面板动作钮缺 :active opacity 0.75")
        um = re.search(r"\.undo-toast-btn\s*\{([^}]*)\}", base)
        if not um or "border-radius:var(--radius-999)" not in norm(um.group(1)) or "-webkit-tap-highlight-color:transparent" not in norm(um.group(1)):
            press_fail.append("应用 .undo-toast-btn 未同步圆角/tap 透明")
        ua = re.search(r"\.undo-toast-btn:active\s*\{([^}]*)\}", base)
        if not ua or "background:var(--fill-accent-10)" not in norm(ua.group(1)):
            press_fail.append("应用 .undo-toast-btn 缺 :active 底 var(--fill-accent-10)")
        if press_fail:
            print("✗ 救援呈现静态锁 (v) 违反：外壳钮按下态未自带/未同值——" + "、".join(press_fail))
            fail = True
        else:
            print("✓ 救援呈现静态锁 (v)：两条四钮 + 救援面板钮按下态自带（tap 透明/圆角/:active 与令牌同值）、.undo-toast-btn 同步")

    # 进场关键帧体与 toastSlideUpBar 同值（名不同：外
    # 壳 mnSwupdIn 为两条共用、属外壳内部名）。
    def kf(src, name):
        mm = re.search(r"@keyframes\s+" + name + r"\s*\{", src)
        if not mm:
            return None
        blk = balanced(src, mm.start())
        return norm(blk[blk.index("{"):]) if "{" in blk else None

    bar_kf = kf(html_nc, "mnSwupdIn")
    if bar_kf is None or bar_kf != kf(base, "toastSlideUpBar"):
        print("✗ 救援呈现静态锁 (v) 违反：@keyframes mnSwupdIn 帧体与 toast 的 toastSlideUpBar 不逐值相等——进场位移/缩放形态须与 toast 同值")
        fail = True
    else:
        print("✓ 救援呈现静态锁 (v)：mnSwupdIn 关键帧体与 toastSlideUpBar 逐值相等")

    RETIRED_BAR = ["rgba(255, 255, 255, 0.85)", "rgba(28, 28, 30, 0.88)", "blur(20px)", "0.28s",
                   "cubic-bezier(0.22, 0.61, 0.36, 1)", "0 10px 32px rgba(0, 0, 0, 0.18)"]
    resid = [v for v in RETIRED_BAR if v in html_nc]
    if resid:
        print("✗ 救援呈现静态锁 (v) 违反：index.html 残留提示条退役值 " + "、".join(resid) + "（旧玻璃/旧曲线/旧阴影已收敛退役，零残留）")
        fail = True
    else:
        print("✓ 救援呈现静态锁 (v)：提示条退役值零残留")

# (vi) 编辑器手势提示条 .gesture-hint 不得带 box-shadow
# （与 toast 无阴影同口径：半透明模糊晕会在浅色页底上
# 漫成渐变灰带、洗淡条周正文——2026-11-25 真机定案，
# box A/B/C 单变量对照证阴影贡献 100%）。
panels = (web / "styles/panels.css").read_text(encoding="utf-8")
gm = re.search(r"\.gesture-hint\s*\{([^}]*)\}", panels)
if not gm:
    print("✗ 救援呈现静态锁 (vi)：panels.css 未找到 .gesture-hint 规则")
    fail = True
elif "box-shadow" in gm.group(1):
    print("✗ 救援呈现静态锁 (vi) 违反：.gesture-hint 带 box-shadow——提示条阴影晕不得回归（与 toast 无阴影同口径）")
    fail = True
else:
    print("✓ 救援呈现静态锁 (vi)：.gesture-hint 无 box-shadow")

sys.exit(1 if fail else 0)
PYEOF
[ $? -ne 0 ] && FAIL=1

# --- 14) 桥 JS 语法门（批 14 P-D5 合流项） ---
# editor.js 经 include_str! 编译期装载（bridge.rs），
# Rust 侧只当字符串、语法错 cargo 不拦；本节以
# node --check 作唯一语法门。node 不在 PATH 时打印
# 跳过、不判红（无 node 的 CI 环境同口径）。
JS_FILE="$WEB/src/editor/js/editor.js"
if command -v node >/dev/null 2>&1; then
  if node --check "$JS_FILE" 2>/dev/null; then
    ok "桥 JS 语法门：editor.js node --check 通过"
  else
    bad "桥 JS 语法门：editor.js 语法错误（node --check 输出如下）"
    node --check "$JS_FILE" 2>&1 | head -12
  fi
else
  echo "⊘ 桥 JS 语法门跳过（node 不在 PATH）"
fi

# --- 15) SQLite 阶段二静态锁（存储 Worker + persist 门面切换面） ---
# 源级（恒查）：Worker crate 与门面在位、build.sh 的
# MYNOTE_SQLITE 构建段与 sw CORE 注入串在位、消费面调用
# 点不得再直引 idb 存储函数（blob_url 纯函数除外）。
SWK="$ROOT/rust/apps/storage-worker"
for f in "$SWK/Cargo.toml" "$SWK/src/lib.rs" "$SWK/web/worker.js" "$SWK/web/index.html"; do
  [ -f "$f" ] || bad "存储 Worker 缺失：$f"
done
[ -f "$WEB/src/persist.rs" ] || bad "persist 门面缺失：src/persist.rs"
grep -q '^mod persist;' "$WEB/src/main.rs" || bad "main.rs 未声明 mod persist"
grep -q -- '--features sqlite-backend' "$WEB/build.sh" || bad "build.sh 缺 sqlite-backend 构建分支"
grep -q 'storage-worker/pkg/mynote_storage_worker_bg.wasm' "$WEB/build.sh" || bad "build.sh 缺 Worker 资产 sw 注入串"
grep -q 'cmd == "migrate"' "$SWK/src/lib.rs" 2>/dev/null || grep -q '"migrate" =>' "$SWK/src/lib.rs" \
  || bad "存储 Worker 缺 migrate 命令面"
RESIDUE="$(grep -rnE 'idb::(save_memos|load_state|save_all|save_manifest|put_attachment|get_attachment|get_all_attachments)' \
  "$WEB/src" --include='*.rs' | grep -vE '/(idb|persist)\.rs:' || true)"
if [ -z "$RESIDUE" ]; then
  ok "阶段二静态锁：Worker/门面在位，消费面已全经 persist（idb 直引零残留）"
else
  bad "消费面仍直引 idb 存储函数（应经 persist 门面）："
  echo "$RESIDUE" | head -8
fi
# 阶段三呈现统一（2026-11-25）：存储状态呈现走 persist
# 回调推送（500ms 轮询已删）、阻断层底色根色同源 +
# sheetIn 进场（确认底表/救援层单一口径）。
grep -q 'fn notify_state' "$WEB/src/persist.rs" || bad "persist 缺状态 notify 入口（呈现同步应经回调推送）"
grep -q 'persist::set_state_listener' "$WEB/src/main.rs" || bad "main.rs 未注册 persist 状态回调"
if grep -q 'sleep_ms(500)' "$WEB/src/main.rs"; then bad "main.rs 残留 500ms 存储状态轮询（应经 persist 回调推送）"; fi
grep -q '.storage-blocked { .*background: var(--mn-root-bg, var(--primary-bg))' "$WEB/styles/panels.css" \
  || bad ".storage-blocked 底色未走根色同源表达式 var(--mn-root-bg, var(--primary-bg))"
grep -q '.storage-blocked { .*animation: sheetIn var(--motion-sheet) var(--motion-spring) both' "$WEB/styles/panels.css" \
  || bad ".storage-blocked 进场未对齐 sheetIn 单一口径"
# 接管根治（2026-11-25 真机缺陷）：等待重试须重建
# Worker（同实例反复 install 在 WebKit 拿不到已释放句
# 柄）、occupied 行带 install 失败分类打点。
grep -q 'fn reset_bridge' "$WEB/src/persist.rs" || bad "persist 缺 Worker 重建入口（接管重试应重建 Worker）"
grep -q 'install kind=' "$WEB/src/persist.rs" || bad "persist occupied 行缺 install 失败分类打点"
# 池分区指纹锁在下一笔（storage-worker 同批）。
# dist 级（仅 sqlite 构建产物在场时查）：Worker 资产齐全
# 且三条资产都在 dist/sw.js 的 CORE 清单内（同戳换代）。
if [ -d "$DIST/storage-worker" ]; then
  for f in storage-worker/worker.js storage-worker/index.html \
           storage-worker/pkg/mynote_storage_worker.js \
           storage-worker/pkg/mynote_storage_worker_bg.wasm; do
    [ -f "$DIST/$f" ] || bad "sqlite dist 缺失：$f"
  done
  for a in './storage-worker/worker.js' './storage-worker/pkg/mynote_storage_worker.js' './storage-worker/pkg/mynote_storage_worker_bg.wasm'; do
    grep -qF "'$a'," "$DIST/sw.js" || bad "dist/sw.js CORE 未纳入 Worker 资产：$a"
  done
  [ $FAIL -eq 0 ] && ok "阶段二静态锁：sqlite dist Worker 资产齐全且在 sw CORE 内"
else
  echo "⊘ 阶段二 dist 级锁跳过（dist 无 storage-worker，非 sqlite 构建）"
fi

echo "---"
if [ $FAIL -eq 0 ]; then
  echo "VERIFY RUSTWEB ALL PASS"
else
  echo "VERIFY RUSTWEB FAILED"
fi
exit $FAIL
