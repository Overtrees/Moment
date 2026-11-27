#!/usr/bin/env bash
# 文档门禁（2026-11-27 门禁复刻批立）：docs 面的可机械
# 判定项——做成与 verify_rustweb.sh / verify_ios.sh 同式
# 的静态检查。Web CI 与原生组版流程均可直接跑：
#   bash scripts/verify_docs.sh
# 退出码：硬门禁任一失败 1，全过 0（警告不影响退出码）。
#
# 检查面与定级（逐项盘点 docs 实况后定，理由见
# docs/reports/impl_gate_port_i18n.md 的 docs 门禁节）：
#  D1 MD 链接完整性（硬）：语料内相对链接的目标文件
#     必须存在；带 #锚点的链接，锚点须命中目标 MD 的
#     标题（GitHub slug 口径）。方案示例占位（无 / 且
#     无 . 的裸词、含 … 的省略式）与外部 scheme 不查。
#  D2 反引号引用（硬，僵尸键的文档版）：`裸名.md` 须
#     在全仓文档语料（除 node_modules）有同名文件；
#     以 docs/、scripts/、rust/ 开头的根相对路径（支
#     持 {a,b} 展开）须在仓库根存在。其余相对基准不
#     唯一的历史路径（src/…、apps/… 等原版归档工程
#     口径）不可机械判定，不查、只在报告登记。
#     豁免表逐条点名 + 理由（见下方 EXEMPT）：
#     只收「已验真引用/历史记录」两类，不收真悬空。
#  D3 孤儿报告（警告）：docs/reports 下报告未被语料
#     内任何其他文件按名引用——只列示不判失败（多
#     数为经提交信息/记忆索引的工作报告，非缺陷）。
#  D4 release 一致性（硬）：release_X.Y.Z.md 命名须
#     合 semver 形；现行版本（build-app2.sh 的
#     CFBundleShortVersionString）的 release 报告须
#     存在；不得有高于现行版本的 release 报告。
# 不可机械判定面（如「文档不得逐字引用用户原话」属
# 语义判定）不造假门禁，清单见报告。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PYEOF'
import os, pathlib, re, sys, urllib.parse

ROOT = pathlib.Path(sys.argv[1])
corpus = sorted(ROOT.glob("*.md")) \
    + sorted((ROOT / "docs").rglob("*.md"))
texts = {p: p.read_text(encoding="utf-8") for p in corpus}
fail = False

# 豁免表（逐条点名 + 理由；只收已验真引用与历史
# 记录两类，新增豁免须同步在报告中登记理由）：
EXEMPT_TOKENS = {
    # 连接器文档统一在仓外 custom-connectors 目录
    # （custom.moment-bridge / custom.cloudflare 两
    # 份已验在位），桥报告按约定名引用、CI 检出内
    # 不可达。
    "CONNECTOR.md",
}
EXEMPT_FILE_TOKEN = {
    # 全文存于工作区 .scratch-bounce/ 会话取证文件
    # （已验在位）、未入仓；该报告自述为其落盘摘要。
    ("docs/reports/audit_exit_bounce_progress.md",
     "findings.md"),
    # 审计时点存在（0 字节空 lib 目标），经该审计
    # 定案于 a739862 删除，属删除记录。
    ("docs/reports/audit_slimming.md",
     "rust/apps/web/src/lib.rs"),
    # 审计时点旧名，现行名 docs/moment-visual-language.md
    # （项目改名后更名）。
    ("docs/reports/audit_specs_report.md",
     "docs/mynote-visual-language.md"),
    # 以下五条：该报告即规范文件缺失盘点，所引皆
    # 「不存在」结论本身（报告内已逐条注明）。
    ("docs/reports/audit_specs_report.md", "SKILL.md"),
    ("docs/reports/audit_specs_report.md", "AGENTS.md"),
    ("docs/reports/audit_specs_report.md",
     "CONTRIBUTING.md"),
    ("docs/reports/audit_specs_report.md",
     "docs/SKILL.md"),
    ("docs/reports/audit_specs_report.md",
     "rust/README.md"),
    ("docs/reports/audit_specs_report.md",
     "rust/apps/web/README.md"),
}

def exempt(rel, tok):
    return tok in EXEMPT_TOKENS \
        or (rel, tok) in EXEMPT_FILE_TOKEN

# --- D1) MD 链接完整性（硬） ---
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")

def slugs(text):
    out = set()
    for line in text.splitlines():
        m = re.match(r"^#{1,6}\s+(.*)$", line)
        if not m:
            continue
        h = re.sub(r"[`*_]", "", m.group(1).strip())
        s = re.sub(r"[^\w\- \u4e00-\u9fff]", "", h.lower())
        out.add(s.replace(" ", "-"))
    return out

n_link = n_anchor = 0
bad_link = []
for p, t in texts.items():
    rel = str(p.relative_to(ROOT))
    for m in LINK.finditer(t):
        tgt = m.group(1)
        if tgt.startswith(("http://", "https://", "mailto:",
                           "#", "sandbox://")):
            continue
        if "…" in tgt:
            continue
        raw_path, _, frag = tgt.partition("#")
        path = urllib.parse.unquote(raw_path)
        if not path:
            continue
        # 无路径分隔且无扩展名的裸词 = MD 语法示例占位
        if "/" not in path and "." not in path:
            continue
        n_link += 1
        tp = p.parent / path
        if not tp.exists() and not (ROOT / path).exists():
            bad_link.append(f"{rel} -> {tgt}（目标不存在）")
            continue
        # ../ 形路径须先归一再查语料表，否则锚点检查
        # 会被路径字面不等静默跳过（自检实证）。
        tpn = pathlib.Path(os.path.normpath(str(tp)))
        if frag and tpn.suffix == ".md" and tpn in texts:
            n_anchor += 1
            if urllib.parse.unquote(frag).lower() \
                    not in slugs(texts[tpn]):
                bad_link.append(f"{rel} -> {tgt}（锚点不存在）")
if bad_link:
    for b in bad_link:
        print(f"✗ 文档链接悬空：{b}")
    fail = True
else:
    print(f"✓ 文档链接完整性：{n_link} 条相对链接、"
          f"{n_anchor} 条锚点全部命中")

# --- D2) 反引号引用（硬） ---
TICK = re.compile(r"`([^`\n]+)`")
EXTS = (".md", ".sh", ".py", ".rs", ".swift", ".js",
        ".json", ".yml")
basenames = set()
for p in ROOT.rglob("*.md"):
    if "node_modules" not in p.parts \
            and ".git" not in p.parts:
        basenames.add(p.name)

def expand(tok):
    m = re.search(r"\{([^{}]+)\}", tok)
    if not m:
        return [tok]
    return [tok[:m.start()] + alt + tok[m.end():]
            for alt in m.group(1).split(",")]

n_ref = n_exempt = 0
bad_ref = []
for p, t in texts.items():
    rel = str(p.relative_to(ROOT))
    for m in TICK.finditer(t):
        tok = m.group(1).strip()
        if " " in tok or tok.startswith(("/", "~", "http")):
            continue
        if any(c in tok for c in "*<>|\\") or "://" in tok:
            continue
        if tok.endswith(".md") and "/" not in tok:
            n_ref += 1
            if tok not in basenames:
                if exempt(rel, tok):
                    n_exempt += 1
                else:
                    bad_ref.append(f"{rel} -> {tok}")
        elif tok.startswith(("docs/", "scripts/", "rust/")) \
                and tok.endswith(EXTS):
            for e in expand(tok):
                n_ref += 1
                if not (ROOT / e).exists():
                    if exempt(rel, e):
                        n_exempt += 1
                    else:
                        bad_ref.append(f"{rel} -> {e}")
if bad_ref:
    for b in bad_ref:
        print(f"✗ 文档引用悬空：{b}（文件不存在，改引用或删引用）")
    fail = True
else:
    print(f"✓ 文档引用完整性：{n_ref} 处反引号引用全部命中"
          f"（豁免 {n_exempt} 处，逐条点名见脚本 EXEMPT 表）")

# --- D3) 孤儿报告（警告） ---
orphans = []
for p in sorted((ROOT / "docs" / "reports").glob("*.md")):
    if not any(q != p and p.name in t
               for q, t in texts.items()):
        orphans.append(p.name)
if orphans:
    shown = ", ".join(orphans[:12]) \
        + ("…" if len(orphans) > 12 else "")
    print(f"⚠ 孤儿报告（仅警告）：{len(orphans)} 份未被语料内"
          f"其他文件按名引用：{shown}")
else:
    print("✓ 孤儿报告：docs/reports 全部有入链引用")

# --- D4) release 一致性（硬） ---
build = (ROOT / "rust/apps/ios/app/build-app2.sh") \
    .read_text(encoding="utf-8")
cm = re.search(
    r"CFBundleShortVersionString</key><string>"
    r"(\d+)\.(\d+)\.(\d+)</string>", build)
cur = tuple(int(x) for x in cm.groups()) if cm else None
rel_bad = []
rel_files = sorted((ROOT / "docs" / "reports")
                   .glob("release_*.md"))
seen = set()
for p in rel_files:
    vm = re.fullmatch(
        r"release_(\d+)\.(\d+)\.(\d+)\.md", p.name)
    if not vm:
        rel_bad.append(f"{p.name}（命名不合 release_X.Y.Z.md 形）")
        continue
    v = tuple(int(x) for x in vm.groups())
    seen.add(v)
    if cur and v > cur:
        rel_bad.append(
            f"{p.name}（版本高于现行 "
            f"{'.'.join(map(str, cur))}）")
if cur and cur not in seen:
    rel_bad.append(
        f"release_{'.'.join(map(str, cur))}.md 缺失"
        f"（现行版本无 release 报告）")
if rel_bad:
    for b in rel_bad:
        print(f"✗ release 一致性：{b}")
    fail = True
else:
    print(f"✓ release 一致性：现行 "
          f"{'.'.join(map(str, cur))} 有 release 报告、"
          f"{len(rel_files)} 份命名合规、无未来版本报告")

sys.exit(1 if fail else 0)
PYEOF
