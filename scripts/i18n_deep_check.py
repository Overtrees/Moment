#!/usr/bin/env python3
# i18n 深检（共源实现）：占位符跨包齐平（硬门禁）/ 僵尸键
# 反向扫描（硬门禁）/ 疑似漏译（仅警告）。
#
# 本文件是这道门禁的唯一实现，两处共读、禁止另抄副本：
#   - scripts/verify_rustweb.sh 第 7 节（Web CI 门禁）；
#   - rust/apps/ios/app/verify_ios.sh [9] 组（原生组版门）。
# bridge.pair_expired 正是从「原生侧无此门」滑过、被 Web
# CI 抓到（2026-11-27），故移植入原生 verify，两边同源。
#
# 用法：python3 scripts/i18n_deep_check.py <WEB 目录> <仓库根>
# 退出码：硬门禁任一失败 1，全过 0（警告不影响退出码）。
#
# 口径（与 verify_rustweb.sh 第 7 节注释同文，改口径先改
# 两处注释再改实现）：
# 7a) 占位符跨包一致：{name} 是 tf() 的插值面，某包漏写
# 或多写会让该语言渲染缺量/多量，同一键的占位符集合
# 五包必须齐平。
# 7b) 僵尸键：键在消费面零命中 = 无代码引用，判失败，
# 删键或补引用。消费面有二、取并集：（i）Web src 全域
# （*.rs）以键界正则（前后非 [A-Za-z0-9_.]——下划线与
# 点同属键内字符，防 list.expand 命中 list.expand_n 一
# 类前缀误报）；（ii）原生 App（rust/apps/ios/app 的
# *.swift）——语言包自原生 i18n I1 起同时供原生消费
# （构建时原样拷入 .app/lang），Swift 侧只认
# Lang.t(/Lang.tf( 调用实参内的纯字符串字面量。
# 动态键口径（2026-11-27 CI 连红根治，旧「实参字面量扫描即完备」已证伪）：
# Swift 侧存在动态引用，字面量扫描误判为僵尸：
#  D1 计算属性/函数返回字面量键、调用方 Lang.t(变量)——
#     bridge.linkStateKey（switch 返回 bridge.state_*）；
#     循环变量取自同域字面量数组（slash.group_*）；
#  D2 Lang.t("前缀" + 变量) 拼接——scopeName 的 "bridge.scope_" + scope，
#     scope 值域来自配对协议（中继 bridge/relay/worker.js 枚举
#     write/ops、默认 read），Swift 内无字面量；
#  D3 键作函数参数传入、函数内 Lang.t(参数)——
#     weatherCard(titleKey:/hintKey:) 的 settings.weather_* 四键。
#  D4 声明体拼接：键属性声明体为 "前缀" + 同文件同值域
#     属性（如 PermKind.titleKey = "perm.item_" + token，
#     token 值域为同文件 token 声明体的字面量全集）——
#     前缀+值恰为包内键才认领（权限中心批形态，2026-11-27
#     移植批补解析；同 D2 后缀法，逐条打 log 供复核）。
#  D5 Lang.t(函数调用(...))：实参为映射函数调用，值域
#     证据取被调用函数的声明体 return 字面量
#     （revokeOutcomeKey 的 bridge.revoke_* 三键）。
#  D6 局部绑定溯源：Lang.t(变量) 的变量由
#     let/if let 绑定自成员访问（reasonKey =
#     bridge.stateReasonKey），值域证据取该成员声明体
#     return 字面量（bridge.reason_* 三键）。
#  D7 数据表 *Key 字段认领：字面量恰为包内键、且作标
#     签以 Key 结尾的实参值出现（SlashCmds 表的
#     titleKey:/subKey:——表存键名、计算属性经 Lang.t
#     解析，与 Web render.rs 存键同构；I4/I5 批形态，
#     2026-11-28 新增）时认领，逐条打 log 供复核。
# 解析规则：声明体 return 字面量 / 同域 for-in 字面量数组 /
# 调用点实参字面量 / 前缀+后缀（后缀取自 Swift + 中继 JS 语料，
# 仅当前缀+后缀恰为包内键时认领）。D2/D4 语料法有误报可能
# （无关字面量恰等于某后缀会掩盖真僵尸），故每条动态认领
# 都逐条打 log 供复核；新增动态形态时须同步扩展本节解析。
# 与键同名的巧合串（如文件名 "export.pdf"）不在 Lang.t 实参
# 内、不算引用。
# 7c) 疑似漏译仅警告：非中文包值与 zh-CN 完全相同且含
# 汉字——繁简同字/专名同形多为正常，只列示不判失败。
# 已逐键定性并登记于 scripts/i18n_7c_exemptions.txt 的
# 同值对只计豁免数、不再列示；未登记者照常列示。登记
# 集与实算集的恒等由 verify_ios.sh [9] 组棘轮断言（本
# 脚本保持警告级、不判失败）。
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

# 原生引用面：Lang.t(/Lang.tf( 实参内的纯字面量键。
# read_swift_string 消费一个字符串字面量：含插值/转义
# 的不算纯键字面量（返回 None）；插值段按括号配平跳
# 过，内层字符串递归消费，防串内括号污染计数。
def read_swift_string(text, i):
    j = i + 1
    buf = []
    plain = True
    while j < len(text):
        c = text[j]
        if c == "\\":
            plain = False
            if j + 1 < len(text) and text[j + 1] == "(":
                depth = 1
                j += 2
                while j < len(text) and depth > 0:
                    if text[j] == '"':
                        _, j = read_swift_string(text, j)
                        continue
                    if text[j] == "(":
                        depth += 1
                    elif text[j] == ")":
                        depth -= 1
                    j += 1
                continue
            j += 2
            continue
        if c == '"':
            return ("".join(buf) if plain else None), j + 1
        buf.append(c)
        j += 1
    return None, j

def swift_lang_keys(text):
    keys = set()
    for m in re.finditer(r"Lang\.tf?\(", text):
        i = m.end()
        depth = 1
        while i < len(text) and depth > 0:
            c = text[i]
            if c == '"':
                lit, i = read_swift_string(text, i)
                if lit and re.fullmatch(r"[A-Za-z0-9_.]+", lit):
                    keys.add(lit)
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
    return keys

native_keys = set()
ios_app = pathlib.Path(sys.argv[2]) / "rust/apps/ios/app"
swift_sources = []
for p in sorted(ios_app.rglob("*.swift")):
    _t = p.read_text(encoding="utf-8")
    swift_sources.append((p, _t))
    native_keys |= swift_lang_keys(_t)

# --- 动态键值域解析（7b 补丁） ---
# 三类动态引用（字面量扫描不到）的值域证据只认四处：声明体
# return 字面量 / 同域 for-in 字面量数组 / 调用点实参字面量 /
# Swift + 中继 JS 语料内的候选后缀（仅当 前缀+后缀 恰为包内键
# 时认领，逐条打 log 供复核）。
KEY_RE = re.compile(r"[A-Za-z0-9_.]+")

def _paired_body(text, open_idx, open_c, close_c):
    depth = 0
    i = open_idx
    while i < len(text):
        c = text[i]
        if c == '"':
            _, i = read_swift_string(text, i)
            continue
        if c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:i], i + 1
        i += 1
    return text[open_idx + 1:], len(text)

def _all_string_literals(text):
    out = []
    i = 0
    while i < len(text):
        if text[i] == '"':
            lit, i = read_swift_string(text, i)
            if lit is not None:
                out.append(lit)
            continue
        i += 1
    return out

def _split_top_commas(s):
    parts, depth, cur = [], 0, []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            _, ni = read_swift_string(s, i)
            cur.append(s[i:ni]); i = ni; continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    parts.append("".join(cur))
    return parts

def _func_spans(text):
    spans = []
    for m in re.finditer(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
        params, after = _paired_body(text, m.end() - 1, "(", ")")
        brace = text.find("{", after)
        if brace < 0:
            continue
        body, end = _paired_body(text, brace, "{", "}")
        spans.append((m.group(1), params, brace, end))
    return spans

def _parse_params(params_text):
    out = []
    for idx, part in enumerate(_split_top_commas(params_text)):
        part = part.strip()
        m = re.match(r"(?:([A-Za-z_][A-Za-z0-9_]*)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:", part)
        if not m:
            out.append((None, None, idx))
            continue
        label = m.group(1)
        if label is None:
            label = m.group(2)
        elif label == "_":
            label = None
        out.append((label, m.group(2), idx))
    return out

def _enclosing_func(text, offset):
    best = None
    for name, params, bstart, bend in _func_spans(text):
        if bstart <= offset < bend:
            if best is None or (bend - bstart) < (best[3] - best[2]):
                best = (name, params, bstart, bend)
    return best

def _declaration_body(name):
    # 计算属性 / 函数声明体；let/var 字面量绑定返回 ("bind", literal)。
    # 含默认值的签名（参数里带 =）会被 "=" 守卫跳过——目标声明均无默认值。
    for path, text in swift_sources:
        for m in re.finditer(r"\b(?:var|let|func)\s+" + re.escape(name) + r"\b", text):
            rest = text[m.end():]
            if rest.lstrip().startswith("="):
                lm = re.match(r"\s*=\s*\"", rest)
                if lm:
                    lit, _ = read_swift_string(rest, lm.end() - 1)
                    return path, ("bind", lit)
                continue
            brace = text.find("{", m.end())
            if brace < 0:
                continue
            between = text[m.end():brace]
            if "=" in between or ";" in between:
                continue
            body, _ = _paired_body(text, brace, "{", "}")
            return path, ("body", body)
    return None, None

def _callsite_literals(fname, label, index):
    lits = []
    for path, text in swift_sources:
        for m in re.finditer(r"(?<![A-Za-z0-9_.])" + re.escape(fname) + r"\s*\(", text):
            before = text[max(0, m.start() - 10):m.start()]
            if re.search(r"\bfunc\s*$", before):
                continue
            args, _ = _paired_body(text, m.end() - 1, "(", ")")
            if label:
                lm = re.search(re.escape(label) + r"\s*:\s*\"", args)
                if lm:
                    lit, _ = read_swift_string(args, lm.end() - 1)
                    if lit:
                        lits.append((lit, path))
            else:
                parts = _split_top_commas(args)
                if index < len(parts):
                    p = parts[index].strip()
                    if p.startswith('"'):
                        lit, _ = read_swift_string(p, 0)
                        if lit:
                            lits.append((lit, path))
    return lits

def _code_string_literals(text):
    # 代码内字符串字面量（跳过 // 与 /* */ 注释内的引号，避免注释
    # 里的巧合词成为后缀证据），返回 (字面量, 行号)。
    out = []
    i, n = 0, len(text)
    line = 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            if j < 0:
                break
            line += text[i:j + 2].count("\n")
            i = j + 2
            continue
        if c == '"':
            lit, ni = read_swift_string(text, i)
            if lit is not None:
                out.append((lit, line))
            line += text[i:ni].count("\n")
            i = ni
            continue
        i += 1
    return out

def _suffix_evidence():
    # 裸词字面量 → (文件, 行号)，先中继 JS（配对协议值域只在后者枚举，
    # 证据优先引协议源）后 Swift。
    ev = {}
    relay_dir = pathlib.Path(sys.argv[2]) / "bridge/relay"
    if relay_dir.is_dir():
        for p in sorted(relay_dir.glob("*.js")):
            t = p.read_text(encoding="utf-8")
            for m in re.finditer(r"""["']([A-Za-z0-9_]+)["']""", t):
                w = m.group(1)
                if w not in ev:
                    ev[w] = (p, t[:m.start()].count("\n") + 1)
    for path, text in swift_sources:
        for w, ln in _code_string_literals(text):
            if re.fullmatch(r"[A-Za-z0-9_]+", w) and w not in ev:
                ev[w] = (path, ln)
    return ev

def _lang_calls(text):
    # 动态实参：("ident", name, offset) / ("concat", prefix, name, offset)。
    # 字面量实参（及三元分支内的字面量）由 swift_lang_keys 已收，此处跳过。
    out = []
    for m in re.finditer(r"Lang\.tf?\(", text):
        arg, _ = _paired_body(text, m.end() - 1, "(", ")")
        s = arg.strip()
        if s.startswith('"'):
            lit, ni = read_swift_string(s, 0)
            rest = s[ni:].strip()
            if lit is not None and rest.startswith("+"):
                rest2 = rest[1:].strip()
                im = re.match(r"([A-Za-z_][A-Za-z0-9_.]*)", rest2)
                if im and rest2[im.end():].strip() == "":
                    out.append(("concat", lit, im.group(1).split(".")[-1], m.start()))
            continue
        im = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_.]*)", s)
        if im:
            out.append(("ident", im.group(1).split(".")[-1], m.start()))
            continue
        # D5：实参整体为一个函数调用（Lang.t(映射函数(...))）
        # ——值域证据取被调用函数的声明体（主循环处理）。
        cm = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", s)
        if cm:
            _, _cend = _paired_body(s, cm.end() - 1, "(", ")")
            if s[_cend:].strip() == "":
                out.append(("call", cm.group(1), m.start()))
    return out

dynamic_keys = set()
dynamic_evidence = []

def _note(key, evidence):
    if key in base and key not in dynamic_keys:
        dynamic_keys.add(key)
        dynamic_evidence.append(f"✓ 动态键：{key} ← {evidence}")

def _claim_from_body(body, dpath, via):
    # 声明体值域认领（D1/D5/D6 共用）：(i) 体内纯字面量
    # 恰为包内键（_note 内过滤）；(ii) D4 拼接形态
    # "前缀" + 标识——标识值域取同文件内同名声明的声明
    # 体字面量全集（多声明取并集），前缀+值恰为包内键
    # 才认领（与 D2 后缀法同守卫、逐条打 log）。
    for _lit in _all_string_literals(body):
        if KEY_RE.fullmatch(_lit):
            _note(_lit, f"{via} 声明体字面量（{dpath.name}）")
    for _cm in re.finditer(
            r'"([^"]*)"\s*\+\s*([A-Za-z_][A-Za-z0-9_.]*)', body):
        _prefix = _cm.group(1)
        _ident = _cm.group(2).split(".")[-1]
        for _vpath, _vtext in swift_sources:
            if _vpath != dpath:
                continue
            for _dm in re.finditer(
                    r"\b(?:var|let|func)\s+" + re.escape(_ident) + r"\b",
                    _vtext):
                _brace = _vtext.find("{", _dm.end())
                if _brace < 0:
                    continue
                _between = _vtext[_dm.end():_brace]
                if "=" in _between or ";" in _between:
                    continue
                _vbody, _ = _paired_body(_vtext, _brace, "{", "}")
                for _lit in _all_string_literals(_vbody):
                    _cand = _prefix + _lit
                    if _cand in base:
                        _note(_cand,
                              f"D4 拼接（{via} 声明体）\"{_prefix}\" + "
                              f"{_ident} 值域 \"{_lit}\"（{_vpath.name}）")

_suffixes = _suffix_evidence()
for _path, _text in swift_sources:
    for _call in _lang_calls(_text):
        if _call[0] == "ident":
            _name, _off = _call[1], _call[2]
            _resolved = False
            _enc = _enclosing_func(_text, _off)
            if _enc is not None:
                _fname, _params, _bstart, _bend = _enc
                _fbody = _text[_bstart:_bend]
                for _label, _pname, _idx in _parse_params(_params):
                    if _pname != _name:
                        continue
                    _resolved = True
                    for _lit, _cpath in _callsite_literals(_fname, _label, _idx):
                        if KEY_RE.fullmatch(_lit):
                            _note(_lit, f"D3 {_fname} 参数 {_pname} 调用点实参（{_cpath.name}）")
                for _fm in re.finditer(r"\bfor\s+([^\n]*?)\s+in\s+", _fbody):
                    _vars = re.split(r"[\s,()]+", _fm.group(1))
                    if _name not in _vars:
                        continue
                    _resolved = True
                    _rest = _fbody[_fm.end():].lstrip()
                    if not _rest.startswith("["):
                        continue
                    _lead = len(_fbody[_fm.end():]) - len(_rest)
                    _arr, _ = _paired_body(_fbody, _fm.end() + _lead, "[", "]")
                    for _lit in _all_string_literals(_arr):
                        if KEY_RE.fullmatch(_lit):
                            _note(_lit, f"D1 循环变量 {_name} 同域字面量数组（{_fname}）")
                _bm = re.search(r"\b(?:let|var)\s+" + re.escape(_name) + r"\s*=\s*\"", _fbody)
                if _bm:
                    _resolved = True
                    _lit, _ = read_swift_string(_fbody, _bm.end() - 1)
                    if _lit and KEY_RE.fullmatch(_lit):
                        _note(_lit, f"D1 {_name} 同域绑定字面量（{_fname}）")
            if not _resolved:
                # D6：let/if let 绑定自成员访问（reasonKey =
                # bridge.stateReasonKey）→ 溯源该成员声明体。
                _bm2 = re.search(
                    r"\b(?:if let|let|var)\s+" + re.escape(_name)
                    + r"\s*=\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?"
                    + r"([A-Za-z_][A-Za-z0-9_]*)", _text)
                if _bm2 and _bm2.group(1) != _name:
                    _prop = _bm2.group(1)
                    _ppath, _pval = _declaration_body(_prop)
                    if _pval is not None:
                        _pkind, _pv = _pval
                        if _pkind == "body":
                            _claim_from_body(
                                _pv, _ppath,
                                f"D6 {_name} 绑定自 {_prop}")
                            _resolved = True
                        elif _pv and KEY_RE.fullmatch(_pv):
                            _note(_pv,
                                  f"D6 {_name} 绑定自 {_prop} 字面量"
                                  f"（{_ppath.name}）")
                            _resolved = True
            if not _resolved:
                _dpath, _dval = _declaration_body(_name)
                if _dval is not None:
                    _kind, _v = _dval
                    if _kind == "body":
                        _claim_from_body(_v, _dpath, f"D1 {_name}")
                    elif _v and KEY_RE.fullmatch(_v):
                        _note(_v, f"D1 {_name} 字面量绑定（{_dpath.name}）")
        elif _call[0] == "call":
            # D5：Lang.t(映射函数(...))——值域取被调用
            # 函数的声明体（revokeOutcomeKey 等）。
            _fname = _call[1]
            _dpath, _dval = _declaration_body(_fname)
            if _dval is not None:
                _kind, _v = _dval
                if _kind == "body":
                    _claim_from_body(
                        _v, _dpath, f"D5 {_fname} 调用实参")
                elif _v and KEY_RE.fullmatch(_v):
                    _note(_v, f"D5 {_fname} 调用实参字面量绑定"
                              f"（{_dpath.name}）")
        else:
            _prefix, _name, _off = _call[1], _call[2], _call[3]
            _enc = _enclosing_func(_text, _off)
            if _enc is not None:
                _fname, _params, _bstart, _bend = _enc
                for _label, _pname, _idx in _parse_params(_params):
                    if _pname != _name:
                        continue
                    for _lit, _cpath in _callsite_literals(_fname, _label, _idx):
                        _note(_prefix + _lit, f"D2 \"{_prefix}\" + 调用点实参 \"{_lit}\"（{_cpath.name}）")
            if _prefix.endswith(("_", ".")):
                for _suf, (_spath, _sline) in _suffixes.items():
                    _cand = _prefix + _suf
                    if _cand in base:
                        _note(_cand, f"D2 \"{_prefix}\" + \"{_suf}\"（{_spath.name}:{_sline}）")
# D7：数据表 *Key 字段认领——字面量恰为包内键、且作标
# 签以 Key 结尾的实参值出现时认领（_note 内过滤非包内
# 键；逐条 log 供复核，与 D2/D4 语料法同守卫）。
for _path, _text in swift_sources:
    for _m in re.finditer(
            r"\b([A-Za-z_][A-Za-z0-9_]*Key)\s*:\s*\"", _text):
        _lit, _ = read_swift_string(_text, _m.end() - 1)
        if _lit:
            _note(_lit, f"D7 {_m.group(1)}: 字段字面量"
                        f"（{_path.name}）")
for _ev in dynamic_evidence:
    print(_ev)

def referenced(key):
    if key in native_keys or key in dynamic_keys:
        return True
    pat = re.compile(r"(?<![A-Za-z0-9_.])" + re.escape(key) + r"(?![A-Za-z0-9_.])")
    return pat.search(corpus) is not None
zombies = [k for k in base if not referenced(k)]
if zombies:
    for k in zombies:
        print(f"✗ 僵尸键：{k}（Web src 与原生 Lang.t/Lang.tf 引用面均零命中，删键或补引用）")
    fail = True
else:
    print(f"✓ 僵尸键扫描：{len(base)} 键在 Web src 或原生引用面均有引用（原生字面引用 {len(native_keys)} 键，动态解析 {len(dynamic_keys)} 键）")

HAN = re.compile(r"[\u4e00-\u9fff]")
_exempt_path = (pathlib.Path(sys.argv[2])
                / "scripts/i18n_7c_exemptions.txt")
_exempt = set()
if _exempt_path.is_file():
    for _line in _exempt_path.read_text(
            encoding="utf-8").splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#"):
            _exempt.add(_line)
for name, pack in packs.items():
    if name == "zh-CN":
        continue
    same = [k for k in base if pack.get(k) == base[k] and HAN.search(base[k] or "")]
    open_same = [k for k in same
                 if f"{name}:{k}" not in _exempt]
    reg_n = len(same) - len(open_same)
    if open_same:
        shown = ", ".join(open_same[:6]) + ("…" if len(open_same) > 6 else "")
        print(f"⚠ 疑似漏译（仅警告）：{name} 与 zh-CN 同值且含汉字未登记 {len(open_same)} 键：{shown}（已登记豁免 {reg_n} 键）")
    elif same:
        print(f"✓ 疑似漏译：{name} 同值含汉字 {len(same)} 键全部已登记豁免（scripts/i18n_7c_exemptions.txt）")

sys.exit(1 if fail else 0)
