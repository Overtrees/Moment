//! Markdown 源段落解析（分类 / 块级解析 / 行内解析）：
//! 与原版 editor.md.js 等价的 marked 子集实现，原住 Web 应用
//! crate 的 blocks.rs，2026-11-26 下沉至 core 供 Web 与原生
//! （FFI）共用同一口径。纯文本处理、无运行时依赖；量测与
//! 缓存由调用方（Web 侧 blocks.rs）包装，本层不直调 diag。
//!
//! 模型口径：代码块/列表/Callout 在文档里都是
//! type=paragraph、children[0].text 存 Markdown 源码，渲染
//! 时经本层分类/解析成预览结构（MdBlock / InlineSeg 树）。

use serde::Serialize;

use crate::mathml::{has_math_syntax, split_math, MathSegment};

/// encodeURIComponent 等价的百分号编码。
pub fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 2);
    for &b in s.as_bytes() {
        let c = b as char;
        if c.is_ascii_alphanumeric() || "-_.!~*'()".contains(c) {
            out.push(c);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

/// Markdown 源段落（原版模型实证，use-slash.js:518-545）：
/// 代码块/列表/Callout 在文档里都是 type=paragraph、children[0].text
/// 存 Markdown 源码，渲染时成 md-preview；点击回源码编辑。
/// 这里是与原版 editor.md.js 等价的分类器（只覆盖块级三类）。
#[derive(Clone, PartialEq)]
pub enum MdKind {
    Code(String),
    /// 含合法 wiki 链接的普通段落（原版 looksLikeMarkdown 含
    /// [[…]] 模式，此类段落进 md 预览、链接成锚点可点）。
    Rich(String),
    Callout {
        style: &'static str,
        title: String,
        body: Vec<String>,
    },
    List {
        ordered: bool,
        items: Vec<String>,
    },
    /// 表格（GFM）：表头 / 对齐（0 左 1 中 2 右）/ 行
    Table {
        head: Vec<String>,
        align: Vec<u8>,
        rows: Vec<Vec<String>>,
    },
    /// 单行 md 标题段（# … ######）
    Heading {
        level: u8,
        text: String,
    },
    /// 引用块：全部行以 > 起（非 Callout），段落已分好
    Quote(Vec<String>),
    /// 分隔线段（--- / *** / ___）
    Divider,
}

fn callout_style_title(raw: &str) -> (&'static str, Option<&'static str>) {
    // editor.md.js CALLOUT_STYLE / CALLOUT_TITLE 逐字移植（标题为
    // 原版硬编码中文，不走语言包——与原版行为一致）。C-21：
    // 未知类型标题回退类型原文（rawType），故标题以 Option
    // 返回——None 时调用方用原文（保留大小写）兜底；此前恒
    // 返回「笔记」，[!FOO] 的标题被吞。
    match raw {
        "note" => ("note", Some("笔记")),
        "info" => ("note", Some("信息")),
        "todo" => ("note", Some("待办")),
        "abstract" => ("note", Some("摘要")),
        "quote" => ("note", Some("引用")),
        "tip" => ("tip", Some("提示")),
        "success" => ("tip", Some("成功")),
        "example" => ("tip", Some("示例")),
        "question" => ("warning", Some("问题")),
        "warning" => ("warning", Some("注意")),
        "important" => ("important", Some("重要")),
        "failure" => ("important", Some("失败")),
        "bug" => ("important", Some("问题")),
        "caution" => ("caution", Some("小心")),
        "danger" => ("caution", Some("危险")),
        _ => ("note", None),
    }
}

/// 表格行拆分：去掉首尾的 | 后按 | 切分；\| 是转义竖线、
/// 不作分隔（marked 口径，预言机实测表头 `a \| b` 为一格），
/// 保留 `\|` 原样留待 parse_inlines 的反斜杠转义解成 '|'。
fn split_table_row(line: &str) -> Vec<String> {
    let t = line.trim();
    let t = t.strip_prefix('|').unwrap_or(t);
    let t = if t.ends_with('|') && !t.ends_with("\\|") {
        &t[..t.len() - 1]
    } else {
        t
    };
    let mut cells = Vec::new();
    let mut cur = String::new();
    let mut it = t.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            cur.push(c);
            if let Some(nc) = it.next() {
                cur.push(nc);
            }
        } else if c == '|' {
            cells.push(std::mem::take(&mut cur));
        } else {
            cur.push(c);
        }
    }
    cells.push(cur);
    cells
}


pub fn md_classify(text: &str) -> Option<MdKind> {
    let trimmed = text.trim_matches('\n');
    if trimmed.is_empty() {
        return None;
    }
    // R3 guard：单行纯 ``` 不转预览（原版失焦 guard 字面
    // 口径；无闭合围栏的孤 ``` 在 parse 侧会成空代码块，
    // 分类层先行挡下，与 C-23 空围栏 guard 同族）。
    if trimmed.trim() == "```" {
        return None;
    }
    let lines: Vec<&str> = trimmed.split('\n').collect();
    // 代码围栏：首行 ``` 或 ~~~ 起；闭合行同字符、长度 ≥ 开围栏，
    // 可缺省（未闭合按 marked 口径取到段尾）。原版分类见 M4。
    if lines.len() >= 2 {
        let f0 = lines[0].trim_start();
        let fc = if f0.starts_with("```") {
            Some('`')
        } else if f0.starts_with("~~~") {
            Some('~')
        } else {
            None
        };
        if let Some(fc) = fc {
            let open_len = f0.chars().take_while(|c| *c == fc).count();
            let mut close_idx: Option<usize> = None;
            for (k, l) in lines.iter().enumerate().skip(1) {
                let t = l.trim();
                if !t.is_empty() && t.len() >= open_len && t.chars().all(|c| c == fc) {
                    close_idx = Some(k);
                    break;
                }
            }
            // C-23 guard：空围栏不转预览（原版失焦 guard：
            // text 剥尽 ``` 后无内容即跳过，如 "```\n```"）。
            if fc == '`' && trimmed.replace("```", "").trim().is_empty() {
                return None;
            }
            let inner = match close_idx {
                Some(k) => lines[1..k].join("\n"),
                None => lines[1..].join("\n"),
            };
            return Some(MdKind::Code(inner));
        }
    }
    // C-23 失焦 guards（原版 md-blocks.js renderSingleParagraph
    // 的 guards 仅失焦路径；Rust 无状态渲染以分类层为等价
    // 单点）：引用正文（剥首行 ^>\s* 后全文）<2 字符不转
    // 预览；> [! 未以 \[!\w+\] 闭合不转预览。此前无等价物，
    // `> a` 这类极短引用失焦即被转成预览块。
    {
        let t = trimmed.trim_start();
        if t.starts_with('>') {
            let after_gt = t[1..].trim_start();
            if after_gt.starts_with("[!") {
                let valid = after_gt[2..]
                    .find(']')
                    .map(|e| {
                        let raw = &after_gt[2..2 + e];
                        !raw.is_empty()
                            && raw
                                .chars()
                                .all(|c| c.is_ascii_alphanumeric() || c == '_')
                    })
                    .unwrap_or(false);
                if !valid {
                    return None;
                }
            } else if after_gt.chars().count() < 2 {
                return None;
            }
        }
    }
    // Callout：首行 > [!TYPE] 可带折叠符 +/- 与自定义标题，
    // 其余行 > 前缀。折叠符不是标题（M5：原版 preprocessCallouts
    // 的正则 \[!(\w+)\]([+-]?)(?:[ \t]+title)? ）。
    if let Some(first) = lines.first() {
        let f = first.trim_start();
        if let Some(rest) = f.strip_prefix("> [!") {
            if let Some(end) = rest.find(']') {
                let raw_orig = &rest[..end];
                let raw = raw_orig.to_lowercase();
                let mut tail = &rest[end + 1..];
                if tail.starts_with('+') || tail.starts_with('-') {
                    tail = &tail[1..];
                }
                // R9：标题口径与 callout_header 单点对齐
                // ——尾巴须以空格/制表符起才作标题，无空
                // 格紧贴（如 > [!NOTE]标题）不算（parse
                // 侧同口径，此前 classify 独自 trim 认
                // 标题，两路呈现分叉）。
                let custom = if tail.starts_with(' ')
                    || tail.starts_with('\t')
                {
                    tail.trim().to_string()
                } else {
                    String::new()
                };
                let (style, default_title) = callout_style_title(&raw);
                // C-21：未知类型标题回退类型原文（保留大小写）
                let title = if !custom.is_empty() {
                    custom
                } else if let Some(dt) = default_title {
                    dt.to_string()
                } else {
                    raw_orig.to_string()
                };
                let body: Vec<String> = lines[1..]
                    .iter()
                    .map(|l| {
                        let t = l.trim_start();
                        t.strip_prefix('>')
                            .map(|r| r.strip_prefix(' ').unwrap_or(r).to_string())
                            .unwrap_or_else(|| l.to_string())
                    })
                    .collect();
                return Some(MdKind::Callout { style, title, body });
            }
        }
    }
    // C-28 缩进代码块：全部非空行 ≥4 缩进（须在 List 分支
    // 之前——"    - x" 此前被 trim 后误判 List，marked 给
    // 代码块）。
    {
        let ne: Vec<&&str> = lines.iter().filter(|l| !l.trim().is_empty()).collect();
        if !ne.is_empty() && ne.iter().all(|l| is_code_indented(l)) {
            let text = lines
                .iter()
                .map(|l| dedent4(l))
                .collect::<Vec<_>>()
                .join("\n")
                .trim_end()
                .to_string();
            return Some(MdKind::Code(text));
        }
    }
    // 列表：全部非空行同为 - 或 N. 前缀
    let non_empty: Vec<&&str> = lines.iter().filter(|l| !l.trim().is_empty()).collect();
    if !non_empty.is_empty() {
        if non_empty.iter().all(|l| l.trim_start().starts_with("- ")) {
            return Some(MdKind::List {
                ordered: false,
                items: non_empty
                    .iter()
                    .map(|l| l.trim_start()[2..].to_string())
                    .collect(),
            });
        }
        let is_num = |l: &str| -> Option<String> {
            let t = l.trim_start();
            let dot = t.find(". ")?;
            if t[..dot].chars().all(|c| c.is_ascii_digit()) && dot > 0 {
                Some(t[dot + 2..].to_string())
            } else {
                None
            }
        };
        if non_empty.iter().all(|l| is_num(l).is_some()) {
            return Some(MdKind::List {
                ordered: true,
                items: non_empty.iter().map(|l| is_num(l).unwrap()).collect(),
            });
        }
    }
    // 分隔线：整段就是 ---（3 个以上）。*** / ___ 独占段在原版
    // 门控 looksLikeMarkdown 下不转换（M8），不归入此类。
    {
        let t = trimmed.trim();
        if t.len() >= 3 && t.chars().all(|c| c == '-') {
            return Some(MdKind::Divider);
        }
    }
    // 单行标题：# ~ ###### + 空格
    if lines.len() == 1 {
        let t = lines[0].trim_start();
        let hashes = t.chars().take_while(|c| *c == '#').count();
        if (1..=6).contains(&hashes) && t[hashes..].starts_with(' ') {
            return Some(MdKind::Heading {
                level: hashes as u8,
                text: t[hashes + 1..].trim().to_string(),
            });
        }
    }
    // 表格：首行含 |、次行是 |---|---| 分隔行。另须全文过
    // looksLikeMarkdown 门控：原版没有表格分组通道，表格段
    // 只经单段落通道转换，门控与其它段相同——单元格无任何
    // 行内 md 信号的纯表格在原版保持源码态（审计 e08 的表格
    // 是靠单元格里的 **粗** 与 `代码` 过门控的）。这是与 M8
    // 同类的反向差：Rust 曾无条件转表格，现收窄对齐原版。
    if lines.len() >= 2 && lines[0].contains('|') && looks_like_markdown(text) {
        let sep = lines[1].trim();
        let cells: Vec<String> = split_table_row(sep);
        let is_sep = !cells.is_empty()
            && cells.iter().all(|c| {
                let c = c.trim();
                !c.is_empty()
                    && c.chars().all(|ch| ch == '-' || ch == ':')
                    && c.contains('-')
            });
        if is_sep {
            let align: Vec<u8> = cells
                .iter()
                .map(|c| {
                    let c = c.trim();
                    if c.starts_with(':') && c.ends_with(':') {
                        1
                    } else if c.ends_with(':') {
                        2
                    } else {
                        0
                    }
                })
                .collect();
            return Some(MdKind::Table {
                head: split_table_row(lines[0])
                    .iter()
                    .map(|c| c.trim().to_string())
                    .collect(),
                align,
                rows: lines[2..]
                    .iter()
                    .filter(|l| !l.trim().is_empty())
                    .map(|l| {
                        split_table_row(l)
                            .iter()
                            .map(|c| c.trim().to_string())
                            .collect()
                    })
                    .collect(),
            });
        }
    }
    // 引用块：全部非空行以 > 起（Callout 已先行处理）
    if !non_empty.is_empty()
        && non_empty.iter().all(|l| l.trim_start().starts_with('>'))
    {
        let mut paras: Vec<String> = Vec::new();
        let mut cur: Vec<String> = Vec::new();
        for l in &lines {
            let t = l.trim_start();
            let body = t
                .strip_prefix('>')
                .map(|r| r.strip_prefix(' ').unwrap_or(r))
                .unwrap_or("");
            if body.trim().is_empty() {
                if !cur.is_empty() {
                    paras.push(cur.join(" "));
                    cur = Vec::new();
                }
            } else {
                cur.push(body.trim().to_string());
            }
        }
        if !cur.is_empty() {
            paras.push(cur.join(" "));
        }
        if !paras.is_empty() {
            return Some(MdKind::Quote(paras));
        }
    }
    // 其余可转换段落（纯行内 md、混合结构、脚注、上下标等）：
    // 原版门控 looksLikeMarkdown 命中即转预览，归 Rich（M1/M3）。
    if looks_like_markdown(text) {
        return Some(MdKind::Rich(text.to_string()));
    }
    None
}

/// 原版 looksLikeMarkdown（editor.md.js:330-335）的手写等价：
/// 行首结构模式 + 全文行内模式任一命中即判定为 Markdown。
/// 数学公式门控（hasMathSyntax）由 core::mathml 提供（行为
/// 规格对齐原版：$$ 成对、$ 成对且内容过启发式）。
pub fn looks_like_markdown(text: &str) -> bool {
    let s = text.trim();
    if s.is_empty() {
        return false;
    }
    // 行首模式：(^|\n)#{1,6}\s / [-*+]\s / \d+\.\s / >\s / ---+ 整行
    for line in s.split('\n') {
        let lc: Vec<char> = line.chars().collect();
        let mut h = 0;
        while h < lc.len() && lc[h] == '#' {
            h += 1;
        }
        if (1..=6).contains(&h) && h < lc.len() && lc[h].is_whitespace() {
            return true;
        }
        if lc.len() >= 2 && matches!(lc[0], '-' | '*' | '+') && lc[1].is_whitespace() {
            return true;
        }
        let mut d = 0;
        while d < lc.len() && lc[d].is_ascii_digit() {
            d += 1;
        }
        if d >= 1 && d + 1 < lc.len() && lc[d] == '.' && lc[d + 1].is_whitespace() {
            return true;
        }
        if lc.len() >= 2 && lc[0] == '>' && lc[1].is_whitespace() {
            return true;
        }
        if line.len() >= 3 && line.chars().all(|c| c == '-') {
            return true;
        }
    }
    let chars: Vec<char> = s.chars().collect();
    let n = chars.len();
    // `{1,3}：任一反引号即命中
    if chars.contains(&'`') {
        return true;
    }
    let span = |open: &[char], close: &[char], forbid: &[char]| -> bool {
        scan_span(&chars, 0, open, close, forbid).is_some()
    };
    // \*\*[^*]+\*\* / __[^_]+__ / ~~[^~]+~~ / ==[^=]+==
    if span(&['*', '*'], &['*', '*'], &['*']) {
        return true;
    }
    if span(&['_', '_'], &['_', '_'], &['_']) {
        return true;
    }
    if span(&['~', '~'], &['~', '~'], &['~', '\n']) {
        return true;
    }
    if span(&['=', '='], &['=', '='], &['=', '\n']) {
        return true;
    }
    // \[[^\]]+\]\] 与 \[\^[^\]]+\]
    if span(&['[', '['], &[']', ']'], &[']']) {
        return true;
    }
    if span(&['[', '^'], &[']'], &[']']) {
        return true;
    }
    // \^\([^\n]+\)\^ / ~\([^\n]+\)~
    if span(&['^', '('], &[')', '^'], &['(', ')', '\n']) {
        return true;
    }
    if span(&['~', '('], &[')', '~'], &['(', ')', '\n']) {
        return true;
    }
    // !\[[^\]]*\]\([^)]+\) 与 \[[^\]]+\]\([^)]+\)
    if find_md_link(&chars, true).is_some() || find_md_link(&chars, false).is_some() {
        return true;
    }
    // (^|[^*])\*[^*\n]+\*($|[^*])
    {
        let mut i = 0;
        while i < n {
            if chars[i] == '*' && (i == 0 || chars[i - 1] != '*') {
                let mut j = i + 1;
                while j < n && chars[j] != '*' && chars[j] != '\n' {
                    j += 1;
                }
                if j < n && chars[j] == '*' && j > i + 1 && (j + 1 >= n || chars[j + 1] != '*') {
                    return true;
                }
            }
            i += 1;
        }
    }
    // \^[A-Za-z0-9][A-Za-z0-9,+-]*\^
    {
        let mut i = 0;
        while i + 1 < n {
            if chars[i] == '^' && is_sup_char(chars[i + 1], true) {
                let mut j = i + 1;
                while j < n && is_sup_char(chars[j], false) {
                    j += 1;
                }
                if j < n && chars[j] == '^' && j > i + 1 {
                    return true;
                }
            }
            i += 1;
        }
    }
    // (^|[^~])~[A-Za-z0-9][A-Za-z0-9,+-]*~(?!~)
    {
        let mut i = 0;
        while i + 1 < n {
            if chars[i] == '~'
                && (i == 0 || chars[i - 1] != '~')
                && is_sup_char(chars[i + 1], true)
            {
                let mut j = i + 1;
                while j < n && is_sup_char(chars[j], false) {
                    j += 1;
                }
                if j < n && chars[j] == '~' && j > i + 1 && (j + 1 >= n || chars[j + 1] != '~')
                {
                    return true;
                }
            }
            i += 1;
        }
    }
    // 数学公式门控（hasMathSyntax 等价，core::mathml）。
    has_math_syntax(s)
}

/// 上下标裸形字符集 [A-Za-z0-9,+-]；first=true 时只许字母数字起手。
fn is_sup_char(c: char, first: bool) -> bool {
    if c.is_ascii_alphanumeric() {
        true
    } else {
        !first && matches!(c, ',' | '+' | '-')
    }
}

/// 在 chars[from..] 中找 open…close 跨度：open 后至少一个不含
/// forbid 的字符再接 close。命中返回 (内容, close 之后下标)。
fn scan_span(
    chars: &[char],
    from: usize,
    open: &[char],
    close: &[char],
    forbid: &[char],
) -> Option<(String, usize)> {
    let n = chars.len();
    let mut i = from;
    while i + open.len() <= n {
        if chars[i..i + open.len()] == *open {
            let start = i + open.len();
            let mut j = start;
            loop {
                if j + close.len() <= n && chars[j..j + close.len()] == *close {
                    if j > start {
                        return Some((chars[start..j].iter().collect(), j + close.len()));
                    }
                    break;
                }
                if j >= n || forbid.contains(&chars[j]) {
                    break;
                }
                j += 1;
            }
        }
        i += 1;
    }
    None
}

/// 找 [text](href)（image=true 时找 ![alt](href)）的第一处命中，
/// 返回 (文本字符, href, 结束下标)。
fn find_md_link(chars: &[char], image: bool) -> Option<(Vec<char>, String, usize)> {
    let n = chars.len();
    let mut i = 0;
    while i < n {
        let open = if image {
            if chars[i] == '!' && i + 1 < n && chars[i + 1] == '[' {
                Some(i + 1)
            } else {
                None
            }
        } else if chars[i] == '[' {
            Some(i)
        } else {
            None
        };
        if let Some(o) = open {
            if let Some(res) = parse_md_link_at(chars, o) {
                if image || !res.0.is_empty() {
                    return Some(res);
                }
            }
        }
        i += 1;
    }
    None
}

/// 在 chars[start]=='[' 处解析 [text](href)：text 取首个 ']'，
/// 其后须紧跟 '('，href 取首个 ')'（空格后的 "title" 部分丢弃）。
fn parse_md_link_at(
    chars: &[char],
    start: usize,
) -> Option<(Vec<char>, String, usize)> {
    let n = chars.len();
    let mut close = start + 1;
    while close < n && chars[close] != ']' {
        close += 1;
    }
    if close >= n {
        return None;
    }
    if close + 1 >= n || chars[close + 1] != '(' {
        return None;
    }
    let mut end = close + 2;
    while end < n && chars[end] != ')' {
        end += 1;
    }
    if end >= n {
        return None;
    }
    let raw_href: String = chars[close + 2..end].iter().collect();
    // R5：角括号 href（marked 支持）——<...> 内可含空
    // 格，整体作 href；普通形仍取首个空白前段（余下是
    // title，现口径丢弃）。
    let t = raw_href.trim();
    let href = if let Some(rest) = t.strip_prefix('<') {
        rest.split('>').next().unwrap_or("").to_string()
    } else {
        t.split_whitespace()
            .next()
            .unwrap_or("")
            .to_string()
    };
    if href.is_empty() {
        return None;
    }
    Some((chars[start + 1..close].to_vec(), href, end + 1))
}

/// GFM 裸链接 autolink 扫描（chars[i] 为 ASCII 字母数字）：
/// 命中返回 (显示文本, href, 结束下标)。口径（marked gfm +
/// 双边预言机实测）：
/// - http:// / https:// / ftp://（大小写不敏感）与 www. 开头
///   （www. 的主机段须再含一个 '.'；href 补 http://）；
/// - URL 吞到空白或 '<' 为止，尾部标点（?!.,:*_~'）与不配平
///   的 ')' / ']' 剥除；
/// - 邮箱 local@domain.tld（TLD ≥1 位纯字母；a@b 无点不算，
///   a@b.c 算——预言机实测）→ mailto:；
/// - 起点前一字符为 ASCII 字母数字或 '.'/'/'/'@'/'_' 时不
///   触发（词中/路径中不算新链接起点）；CJK 前字不挡（原版
///   marked 在 CJK 后照样起链接、且把后续 CJK 吞进 URL，
///   本实现吞入规则与之相同，仅 href 不做百分号编码）。
fn scan_autolink(chars: &[char], i: usize) -> Option<(String, String, usize)> {
    let n = chars.len();
    if i > 0 {
        let p = chars[i - 1];
        if p.is_ascii_alphanumeric() || matches!(p, '.' | '/' | '@' | '_') {
            return None;
        }
    }
    let rest: String = chars[i..].iter().collect();
    let lower = rest.to_ascii_lowercase();
    // URL 形
    let (prefix_len, is_www) = if lower.starts_with("https://") {
        (8, false)
    } else if lower.starts_with("http://") {
        (7, false)
    } else if lower.starts_with("ftp://") {
        (6, false)
    } else if lower.starts_with("www.") {
        (4, true)
    } else {
        (0, false)
    };
    if prefix_len > 0 {
        let mut j = i;
        while j < n && !chars[j].is_whitespace() && chars[j] != '<' {
            j += 1;
        }
        let mut end = j;
        // 尾部标点与不配平括号剥除（GFM 口径）
        loop {
            if end <= i + prefix_len {
                break;
            }
            let last = chars[end - 1];
            if matches!(last, '?' | '!' | '.' | ',' | ':' | '*' | '_' | '~' | '\'') {
                end -= 1;
                continue;
            }
            if last == ')' || last == ']' {
                let (open, close) = if last == ')' { ('(', ')') } else { ('[', ']') };
                let opens = chars[i..end].iter().filter(|c| **c == open).count();
                let closes = chars[i..end].iter().filter(|c| **c == close).count();
                if closes > opens {
                    end -= 1;
                    continue;
                }
            }
            break;
        }
        if end <= i + prefix_len {
            return None;
        }
        if is_www {
            // 主机段（首个 '/' 前）除 www. 外须再含一个 '.'
            let host: String = chars[i + 4..end]
                .iter()
                .take_while(|c| **c != '/')
                .collect();
            if !host.contains('.') {
                return None;
            }
        }
        let label: String = chars[i..end].iter().collect();
        let href = if is_www {
            format!("http://{label}")
        } else {
            label.clone()
        };
        return Some((label, href, end));
    }
    // 邮箱形：local@domain.tld
    let mut j = i;
    while j < n
        && (chars[j].is_ascii_alphanumeric() || matches!(chars[j], '.' | '_' | '%' | '+' | '-'))
    {
        j += 1;
    }
    if j == i || j >= n || chars[j] != '@' {
        return None;
    }
    let mut k = j + 1;
    while k < n
        && (chars[k].is_ascii_alphanumeric() || matches!(chars[k], '.' | '-'))
    {
        k += 1;
    }
    let mut end = k;
    while end > j + 1 && matches!(chars[end - 1], '.' | '-') {
        end -= 1;
    }
    let domain: String = chars[j + 1..end].iter().collect();
    let dot = domain.rfind('.')?;
    let tld = &domain[dot + 1..];
    if dot == 0 || tld.is_empty() || !tld.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    let label: String = chars[i..end].iter().collect();
    Some((label.clone(), format!("mailto:{label}"), end))
}

/// scan_span 的锚定版：open 必须恰在 from 处（行内解析用，
/// 避免本处不成跨度时误吞后文的同类跨度）。
fn scan_span_at(
    chars: &[char],
    from: usize,
    open: &[char],
    close: &[char],
    forbid: &[char],
) -> Option<(String, usize)> {
    let n = chars.len();
    if from + open.len() > n || chars[from..from + open.len()] != *open {
        return None;
    }
    let start = from + open.len();
    let mut j = start;
    loop {
        if j + close.len() <= n && chars[j..j + close.len()] == *close {
            if j > start {
                return Some((chars[start..j].iter().collect(), j + close.len()));
            }
            return None;
        }
        if j >= n || forbid.contains(&chars[j]) {
            return None;
        }
        j += 1;
    }
}

// ===== 行内 Markdown 解析（marked 子集 + 此刻扩展语法） =====
//
// 优先级按原版管线：代码段先保护（protectCodeSegments），
// 扩展语法（~~/==/上下标/wiki/脚注）在 marked 之前 stash，
// 其内容不再二次解析；**/__ 粗体、*/_ 斜体、链接文本递归解析。

#[derive(Clone, PartialEq, Serialize)]
pub enum InlineSeg {
    Text(String),
    Code(String),
    Strong(Vec<InlineSeg>),
    Em(Vec<InlineSeg>),
    /// 原始 HTML <u> 下划线（C-28）：md 语法无对应定界符，
    /// 仅 HTML 通道产生，子段递归解析（marked 口径）。
    Underline(Vec<InlineSeg>),
    /// ~~删除~~：原版 stash 直出 HTML，内容不解析
    Del(String),
    /// ==高亮==：同上
    Highlight(String),
    Sup(String),
    Sub(String),
    Link {
        href: String,
        children: Vec<InlineSeg>,
    },
    Image {
        src: String,
        alt: String,
    },
    Wiki {
        target: String,
        label: String,
    },
    FootRef {
        id: String,
        ref_id: String,
        number: usize,
    },
    /// 数学公式（$…$ / $$…$$）：预览层经 core::mathml 渲染
    /// MathML；渲染硬错误时回退红色原码（.math-source）。
    Math {
        tex: String,
        display: bool,
    },
    Break,
}

/// 脚注定义（原版 preprocessFootnotes 的逐段等价实现）。
struct FootnoteDef {
    label: String,
    body: String,
    original: String,
    id: String,
    number: usize,
}

/// 行内解析上下文：脚注定义表 + 引用计数（编号按定义顺序，
/// 与原版 order.indexOf 口径一致）。
struct InlineCtx {
    /// 小写 label → 定义下标
    def_map: std::collections::HashMap<String, usize>,
    defs: Vec<FootnoteDef>,
    /// 定义下标 → 已出现的 ref id 列表（文档顺序）
    ref_ids: std::collections::HashMap<usize, Vec<String>>,
    counts: std::collections::HashMap<usize, usize>,
    /// 正在解析链接文本：其内不再触发裸链接 autolink
    /// （marked 不在链接文本内再套链接）。
    in_link: bool,
    /// C-28 引用式链接定义：归一 label（小写、内部空白折叠）
    /// → href，由 parse_md_document 在块解析前装填。
    link_defs: std::collections::HashMap<String, String>,
    /// 本文档已解析的引用式链接数 / 原始 HTML 标签数（Diag）
    ref_links_used: usize,
    html_tags_used: usize,
}

impl InlineCtx {
    fn empty() -> Self {
        InlineCtx {
            def_map: std::collections::HashMap::new(),
            defs: Vec::new(),
            ref_ids: std::collections::HashMap::new(),
            counts: std::collections::HashMap::new(),
            in_link: false,
            link_defs: std::collections::HashMap::new(),
            ref_links_used: 0,
            html_tags_used: 0,
        }
    }
    fn foot_ref(&mut self, label: &str) -> Option<InlineSeg> {
        let idx = *self.def_map.get(&label.to_lowercase())?;
        let def = &self.defs[idx];
        let (id, number) = (def.id.clone(), def.number);
        let c = {
            let e = self.counts.entry(idx).or_insert(0);
            *e += 1;
            *e
        };
        let ref_id = format!("{id}-ref-{c}");
        self.ref_ids.entry(idx).or_default().push(ref_id.clone());
        Some(InlineSeg::FootRef {
            id,
            ref_id,
            number,
        })
    }
}

/// encodeURIComponent 后 %→_、再把 [^A-Za-z0-9_-] 换 _（原版 footnoteId）。
fn footnote_id(label: &str) -> String {
    let enc = url_encode(label.trim());
    let mut out = String::from("fn-");
    for c in enc.chars() {
        if c == '%' {
            out.push('_');
        } else if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    out
}

/// 抽出脚注定义行（含缩进续行），返回 (剩余文本, 定义表)。
/// 定义顺序即编号顺序；重复 label 只取首个（原版口径）。
/// 引用行剥前缀（`> [^1]: x` / `>[^1]: x` → 余下）；
/// 非引用行返回 None。R4：定义抽取的引用变体入口
/// ——原版 preprocess 是全文级，写在引用内的脚注/链
/// 接定义同样生效、脚注区仍归文末。
fn unquote_line(line: &str) -> Option<&str> {
    let t = line.trim_start_matches(' ');
    let r = t.strip_prefix('>')?;
    Some(r.strip_prefix(' ').unwrap_or(r))
}

fn extract_footnotes(text: &str) -> (String, Vec<FootnoteDef>) {
    fn def_line(line: &str) -> Option<(String, String)> {
        let b = line.as_bytes();
        let mut i = 0;
        while i < b.len() && b[i] == b' ' && i < 3 {
            i += 1;
        }
        let rest = &line[i..];
        let rest = rest.strip_prefix("[^")?;
        let close = rest.find("]:")?;
        let label = &rest[..close];
        if label.is_empty() || label.chars().any(|c| c.is_whitespace() || c == ']') {
            return None;
        }
        let body = rest[close + 2..].trim_start_matches([' ', '\t']);
        Some((label.to_string(), body.to_string()))
    }
    fn continuation(line: &str) -> Option<String> {
        if let Some(r) = line.strip_prefix('\t') {
            return Some(r.to_string());
        }
        let spaces = line.chars().take_while(|c| *c == ' ').count();
        if spaces >= 2 {
            return Some(line[spaces..].to_string());
        }
        None
    }
    let lines: Vec<&str> = text.split('\n').collect();
    let mut kept: Vec<&str> = Vec::new();
    let mut defs: Vec<FootnoteDef> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut fence: Option<(char, usize)> = None;
    // R4：引用内围栏状态（与顶层围栏分开跟踪）。
    let mut qfence: Option<(char, usize)> = None;
    let mut i = 0;
    while i < lines.len() {
        // 围栏内的定义形行是代码内容，不抽（原版先
        // stash 围栏同口径；审计 D-R2）。
        if let Some((fc, flen)) = fence {
            kept.push(lines[i]);
            if fence_close(lines[i], fc, flen) {
                fence = None;
            }
            i += 1;
            continue;
        }
        if let Some((fc, flen, _)) = fence_start(lines[i]) {
            fence = Some((fc, flen));
            kept.push(lines[i]);
            i += 1;
            continue;
        }
        // R4：引用变体——剥 > 前缀后命中定义形的同样
        // 抽取（引用内围栏由 qfence 挡：unquote 后命中
        // 围栏起止的行只维护状态不抽）。
        let plain = def_line(lines[i]);
        let in_quote = plain.is_none();
        let hit = match plain {
            Some(h) => Some(h),
            None => {
                let u = unquote_line(lines[i]);
                match u {
                    Some(u) if qfence.is_none()
                        && fence_start(u).is_none() =>
                    {
                        def_line(u)
                    }
                    _ => None,
                }
            }
        };
        if in_quote {
            if let Some(u) = unquote_line(lines[i]) {
                if let Some((fc, flen)) = qfence {
                    if fence_close(u, fc, flen) {
                        qfence = None;
                    }
                } else if let Some((fc, flen, _)) =
                    fence_start(u)
                {
                    qfence = Some((fc, flen));
                }
            }
        }
        if let Some((label, first)) = hit {
            let mut body = vec![first];
            let mut original = vec![lines[i].to_string()];
            let mut j = i + 1;
            while j < lines.len() {
                let c = if in_quote {
                    unquote_line(lines[j])
                        .and_then(continuation)
                } else {
                    continuation(lines[j])
                };
                match c {
                    Some(c) => {
                        body.push(c);
                        original.push(lines[j].to_string());
                        j += 1;
                    }
                    None => break,
                }
            }
            if seen.insert(label.to_lowercase()) {
                let number = defs.len() + 1;
                defs.push(FootnoteDef {
                    id: footnote_id(&label),
                    label,
                    body: body.join("\n").trim().to_string(),
                    original: original.join("\n"),
                    number,
                });
            }
            i = j;
        } else {
            kept.push(lines[i]);
            i += 1;
        }
    }
    (kept.join("\n"), defs)
}

/// 引用 label 归一（marked 口径）：内部空白折叠为单空格、
/// 去首尾空白、转小写。
fn normalize_ref_label(label: &str) -> String {
    label.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}

/// C-28：抽出链接引用定义行 `[label]: href "title"`（marked
/// 词法层吞行、正文不渲染），返回 (剩余文本, 定义表)。href
/// 可用 <> 包裹，其后标题部分丢弃；同 label 只取首个定义。
/// 围栏内的定义形行不抽（与脚注抽取同口径，审计 D-R2）。
fn extract_link_defs(text: &str) -> (String, Vec<(String, String)>) {
    fn def_line(line: &str) -> Option<(String, String)> {
        let bytes = line.as_bytes();
        let mut i = 0;
        while i < bytes.len() && i < 3 && bytes[i] == b' ' {
            i += 1;
        }
        let rest = line[i..].strip_prefix('[')?;
        // 脚注定义已先行抽走，此处防御性排除
        if rest.starts_with('^') {
            return None;
        }
        let close = rest.find("]:")?;
        let label_raw = &rest[..close];
        if label_raw.is_empty() {
            return None;
        }
        let after = rest[close + 2..].trim_start();
        if after.is_empty() {
            return None;
        }
        let href = if let Some(h) = after.strip_prefix('<') {
            let e = h.find('>')?;
            h[..e].to_string()
        } else {
            after.split_whitespace().next()?.to_string()
        };
        if href.is_empty() {
            return None;
        }
        Some((normalize_ref_label(label_raw), href))
    }
    let lines: Vec<&str> = text.split('\n').collect();
    let mut kept: Vec<&str> = Vec::new();
    let mut defs: Vec<(String, String)> = Vec::new();
    let mut fence: Option<(char, usize)> = None;
    let mut qfence: Option<(char, usize)> = None;
    for line in lines {
        if let Some((fc, flen)) = fence {
            kept.push(line);
            if fence_close(line, fc, flen) {
                fence = None;
            }
            continue;
        }
        if let Some((fc, flen, _)) = fence_start(line) {
            fence = Some((fc, flen));
            kept.push(line);
            continue;
        }
        // R4：引用变体同脚注路径（qfence 挡引用内围栏）。
        let hit = match def_line(line) {
            Some(h) => Some(h),
            None => {
                let u = unquote_line(line);
                if let Some(u) = u {
                    if let Some((fc, flen)) = qfence {
                        if fence_close(u, fc, flen) {
                            qfence = None;
                        }
                    } else if let Some((fc, flen, _)) =
                        fence_start(u)
                    {
                        qfence = Some((fc, flen));
                    }
                }
                match u {
                    Some(u) if qfence.is_none()
                        && fence_start(u).is_none() =>
                    {
                        def_line(u)
                    }
                    _ => None,
                }
            }
        };
        match hit {
            Some((label, href)) => {
                if !defs.iter().any(|(l, _)| *l == label) {
                    defs.push((label, href));
                }
            }
            None => kept.push(line),
        }
    }
    (kept.join("\n"), defs)
}

/// C-28 引用式链接/图片解析：chars[start]=='[' 处依次试
/// 全引用 [text][label]、折叠引用 [text][]、快捷引用
/// [label]。命中 ctx.link_defs 才消费；未命中返回 None
/// （调用方按字面处理）。返回 (文本字符, href, 结束下标)。
fn parse_ref_link_at(
    chars: &[char],
    start: usize,
    ctx: &InlineCtx,
) -> Option<(Vec<char>, String, usize)> {
    let n = chars.len();
    if start >= n || chars[start] != '[' {
        return None;
    }
    let mut j = start + 1;
    while j < n && chars[j] != ']' {
        j += 1;
    }
    if j >= n || j == start + 1 {
        return None;
    }
    let text: Vec<char> = chars[start + 1..j].to_vec();
    if j + 1 < n && chars[j + 1] == '[' {
        let mut k = j + 2;
        while k < n && chars[k] != ']' {
            k += 1;
        }
        if k >= n {
            return None;
        }
        let label_raw: String = if k == j + 2 {
            text.iter().collect()
        } else {
            chars[j + 2..k].iter().collect()
        };
        let href = ctx.link_defs.get(&normalize_ref_label(&label_raw))?;
        return Some((text, href.clone(), k + 1));
    }
    // 快捷引用：其后紧跟 ( 时归行内链接形态，不半消费
    if j + 1 < n && chars[j + 1] == '(' {
        return None;
    }
    let label_raw: String = text.iter().collect();
    let href = ctx.link_defs.get(&normalize_ref_label(&label_raw))?;
    Some((text, href.clone(), j + 1))
}

/// 行内解析入口：text 为段落/单元格/列表项的原始行内文本。
fn parse_inlines(text: &str, ctx: &mut InlineCtx) -> Vec<InlineSeg> {
    let chars: Vec<char> = text.chars().collect();
    parse_inline_chars(&chars, ctx)
}

/// 行内解析（带公式切分）：先经 core::split_math 切出公式段
/// （代码段在切分器内整体保护、转义与防误判口径见 core::
/// mathml），文本段再走字符级解析。递归子段（粗斜体/链接
/// 文本）也经此入口，公式在任意嵌套层都能命中。
fn parse_inline_chars(chars: &[char], ctx: &mut InlineCtx) -> Vec<InlineSeg> {
    let text: String = chars.iter().collect();
    let segs = split_math(&text);
    let single_text = segs.len() == 1
        && matches!(&segs[0], MathSegment::Text(t) if t.as_str() == text.as_str());
    if single_text {
        return parse_inline_chars_raw(chars, ctx);
    }
    let mut out: Vec<InlineSeg> = Vec::new();
    for seg in segs {
        match seg {
            MathSegment::Text(t) => {
                let cs: Vec<char> = t.chars().collect();
                out.extend(parse_inline_chars_raw(&cs, ctx));
            }
            MathSegment::Math { tex, display } => {
                out.push(InlineSeg::Math { tex, display });
            }
        }
    }
    out
}

/// C-28 原始 HTML：一个标签的解析结果（属性只保留 href/
/// src/alt 等渲染所需项的原始串，消毒在渲染层过闸）。
struct HtmlTag {
    name: String,
    closing: bool,
    self_closing: bool,
    attrs: Vec<(String, String)>,
    end: usize,
}

fn html_tag_attr<'a>(tag: &'a HtmlTag, name: &str) -> Option<&'a str> {
    tag.attrs
        .iter()
        .find(|(k, _)| k == name)
        .map(|(_, v)| v.as_str())
}

fn is_void_html(name: &str) -> bool {
    matches!(
        name,
        "area" | "base" | "br" | "col" | "embed" | "hr" | "img" | "input" | "link" | "meta"
            | "param" | "source" | "track" | "wbr"
    )
}

/// 连内容一并丢弃的标签（DOMPurify 对 script/style 等的
/// DROP_CONTENT 口径）。svg/math 在 DOMPurify 白名单内，
/// 但段模型无对应结构——丢弃并在提交信息注明此取舍。
fn is_drop_content_html(name: &str) -> bool {
    matches!(
        name,
        "script" | "style" | "title" | "iframe" | "object" | "textarea" | "xmp" | "noscript"
            | "template" | "svg" | "math" | "head" | "noembed" | "noframes" | "frame"
            | "frameset" | "applet"
    )
}

/// 解析 chars[start]=='<' 处的一个标签：属性值可含引号内
/// 的 '>'；形态不合（无标签名、未闭合等）返回 None，调用
/// 方按字面处理。
fn parse_html_tag(chars: &[char], start: usize) -> Option<HtmlTag> {
    let n = chars.len();
    let mut i = start + 1;
    let mut closing = false;
    if i < n && chars[i] == '/' {
        closing = true;
        i += 1;
    }
    if i >= n || !chars[i].is_ascii_alphabetic() {
        return None;
    }
    let name_start = i;
    while i < n && (chars[i].is_ascii_alphanumeric() || chars[i] == '-') {
        i += 1;
    }
    let name: String = chars[name_start..i]
        .iter()
        .collect::<String>()
        .to_lowercase();
    let mut attrs: Vec<(String, String)> = Vec::new();
    loop {
        while i < n && chars[i].is_whitespace() {
            i += 1;
        }
        if i >= n {
            return None;
        }
        if chars[i] == '>' {
            return Some(HtmlTag {
                name,
                closing,
                self_closing: false,
                attrs,
                end: i + 1,
            });
        }
        if chars[i] == '/' {
            if i + 1 < n && chars[i + 1] == '>' {
                return Some(HtmlTag {
                    name,
                    closing,
                    self_closing: true,
                    attrs,
                    end: i + 2,
                });
            }
            return None;
        }
        let a_start = i;
        while i < n
            && !chars[i].is_whitespace()
            && chars[i] != '='
            && chars[i] != '>'
            && chars[i] != '/'
        {
            i += 1;
        }
        if i == a_start {
            return None;
        }
        let a_name: String = chars[a_start..i]
            .iter()
            .collect::<String>()
            .to_lowercase();
        while i < n && chars[i].is_whitespace() {
            i += 1;
        }
        let mut a_val = String::new();
        if i < n && chars[i] == '=' {
            i += 1;
            while i < n && chars[i].is_whitespace() {
                i += 1;
            }
            if i < n && (chars[i] == '"' || chars[i] == '\'') {
                let q = chars[i];
                i += 1;
                let v_start = i;
                while i < n && chars[i] != q {
                    i += 1;
                }
                if i >= n {
                    return None;
                }
                a_val = chars[v_start..i].iter().collect();
                i += 1;
            } else {
                let v_start = i;
                while i < n && !chars[i].is_whitespace() && chars[i] != '>' {
                    i += 1;
                }
                a_val = chars[v_start..i].iter().collect();
            }
        }
        attrs.push((a_name, a_val));
    }
}

/// 同名嵌套计数地找闭合标签：返回 (内容结束下标, 闭合标
/// 签之后下标)；无闭合返回 None（调用方取到输入尾）。
fn scan_html_close(chars: &[char], from: usize, name: &str) -> Option<(usize, usize)> {
    let n = chars.len();
    let mut depth = 1usize;
    let mut j = from;
    while j < n {
        if chars[j] == '<' {
            if let Some(t) = parse_html_tag(chars, j) {
                if t.name == name {
                    if t.closing {
                        depth -= 1;
                        if depth == 0 {
                            return Some((j, t.end));
                        }
                    } else if !t.self_closing && !is_void_html(&t.name) {
                        depth += 1;
                    }
                }
                j = t.end;
                continue;
            }
        }
        j += 1;
    }
    None
}

/// 段列拍平为纯文本（Del/Highlight/Sub/Sup/Code 等 String
/// 载荷段的内层口径，与 marked 渲染后取文本一致）。
fn segs_plain_text(segs: &[InlineSeg]) -> String {
    let mut s = String::new();
    for seg in segs {
        match seg {
            InlineSeg::Text(t) | InlineSeg::Code(t) | InlineSeg::Del(t)
            | InlineSeg::Highlight(t) => s.push_str(t),
            InlineSeg::Strong(c) | InlineSeg::Em(c) | InlineSeg::Underline(c) => {
                s.push_str(&segs_plain_text(c))
            }
            InlineSeg::Link { children, .. } => s.push_str(&segs_plain_text(children)),
            InlineSeg::Sub(t) | InlineSeg::Sup(t) => s.push_str(t),
            InlineSeg::Image { alt, .. } => s.push_str(alt),
            InlineSeg::Math { tex, .. } => s.push_str(tex),
            InlineSeg::Wiki { label, target } => {
                s.push_str(if label.is_empty() { target } else { label })
            }
            InlineSeg::FootRef { .. } | InlineSeg::Break => {}
        }
    }
    s
}

/// C-28：chars[start]=='<' 处的原始 HTML 处理（原版
/// marked + DOMPurify 白名单面的段模型等价）：可映射标签
/// 转结构段，其余白名单标签剥标签留子段，DROP_CONTENT
/// 集连内容丢弃，危险 href/src 在渲染层经 C-30 的
/// safe_http_url / safe_image_url 过闸（此处不裸放行）。
/// 非标签形态返回 None（调用方回落 autolink / 字面）。
fn handle_html_at(
    chars: &[char],
    start: usize,
    ctx: &mut InlineCtx,
) -> Option<(Vec<InlineSeg>, usize)> {
    let n = chars.len();
    // 注释 <!-- … -->：闭合才吞，未闭合按字面
    if chars[start + 1..].starts_with(&['!', '-', '-']) {
        let mut j = start + 4;
        while j + 2 < n {
            if chars[j] == '-' && chars[j + 1] == '-' && chars[j + 2] == '>' {
                ctx.html_tags_used += 1;
                return Some((Vec::new(), j + 3));
            }
            j += 1;
        }
        return None;
    }
    // <!…> / <?…> 声明：跳到 '>'
    if start + 1 < n && (chars[start + 1] == '!' || chars[start + 1] == '?') {
        let mut j = start + 1;
        while j < n && chars[j] != '>' {
            j += 1;
        }
        if j >= n {
            return None;
        }
        ctx.html_tags_used += 1;
        return Some((Vec::new(), j + 1));
    }
    let tag = parse_html_tag(chars, start)?;
    // 游离闭标签直接丢弃（DOMPurify 同口径）
    if tag.closing {
        ctx.html_tags_used += 1;
        return Some((Vec::new(), tag.end));
    }
    ctx.html_tags_used += 1;
    let name = tag.name.as_str();
    if is_void_html(name) {
        return Some((
            match name {
                "br" | "hr" => vec![InlineSeg::Break],
                "img" => vec![InlineSeg::Image {
                    src: html_tag_attr(&tag, "src").unwrap_or("").to_string(),
                    alt: html_tag_attr(&tag, "alt").unwrap_or("").to_string(),
                }],
                _ => Vec::new(),
            },
            tag.end,
        ));
    }
    // 容器内容范围：自闭合为空；无闭合取到输入尾
    let (inner, after): (Vec<char>, usize) = if tag.self_closing {
        (Vec::new(), tag.end)
    } else if let Some((inner_end, close_end)) = scan_html_close(chars, tag.end, name) {
        (chars[tag.end..inner_end].to_vec(), close_end)
    } else {
        (chars[tag.end..].to_vec(), n)
    };
    if is_drop_content_html(name) {
        return Some((Vec::new(), after));
    }
    // code/kbd 内容按原文（不二次解析）
    if name == "code" || name == "kbd" {
        return Some((
            vec![InlineSeg::Code(inner.iter().collect())],
            after,
        ));
    }
    if name == "a" {
        let saved = ctx.in_link;
        ctx.in_link = true;
        let children = parse_inline_chars_raw(&inner, ctx);
        ctx.in_link = saved;
        return Some((
            vec![InlineSeg::Link {
                href: html_tag_attr(&tag, "href").unwrap_or("").to_string(),
                children,
            }],
            after,
        ));
    }
    let children = parse_inline_chars_raw(&inner, ctx);
    let segs = match name {
        "b" | "strong" => vec![InlineSeg::Strong(children)],
        "i" | "em" => vec![InlineSeg::Em(children)],
        "u" | "ins" => vec![InlineSeg::Underline(children)],
        "s" | "del" | "strike" => vec![InlineSeg::Del(segs_plain_text(&children))],
        "mark" => vec![InlineSeg::Highlight(segs_plain_text(&children))],
        "sup" => vec![InlineSeg::Sup(segs_plain_text(&children))],
        "sub" => vec![InlineSeg::Sub(segs_plain_text(&children))],
        // 其余白名单/未知标签：剥标签，子段直接拼入
        _ => children,
    };
    Some((segs, after))
}

fn parse_inline_chars_raw(chars: &[char], ctx: &mut InlineCtx) -> Vec<InlineSeg> {
    let n = chars.len();
    let mut out: Vec<InlineSeg> = Vec::new();
    let mut buf = String::new();
    let flush = |buf: &mut String, out: &mut Vec<InlineSeg>| {
        if !buf.is_empty() {
            out.push(InlineSeg::Text(std::mem::take(buf)));
        }
    };
    let mut i = 0;
    while i < n {
        let c = chars[i];
        // 硬换行：行尾 2+ 空格 + \n（marked 口径）
        if c == ' ' && i + 1 < n && chars[i + 1] == ' ' {
            let mut j = i;
            while j < n && chars[j] == ' ' {
                j += 1;
            }
            if j < n && chars[j] == '\n' {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Break);
                i = j + 1;
                continue;
            }
        }
        // 软换行：原版 marked 以 breaks:true 渲染（markdown-
        // bridge setOptions），段内单个 \n 即 <br>（双边预言机
        // 实测：多行段落/引用懒续行/列表项续行皆然）。
        if c == '\n' {
            flush(&mut buf, &mut out);
            out.push(InlineSeg::Break);
            i += 1;
            continue;
        }
        // 反斜杠转义 ASCII 标点
        if c == '\\' && i + 1 < n && chars[i + 1].is_ascii_punctuation() {
            buf.push(chars[i + 1]);
            i += 2;
            continue;
        }
        // 代码段（等长反引号串闭合）
        if c == '`' {
            let mut run = 1;
            while i + run < n && chars[i + run] == '`' {
                run += 1;
            }
            match find_code_close(chars, i + run, run) {
                Some((content, end)) => {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Code(code_content(&content)));
                    i = end;
                }
                None => {
                    for _ in 0..run {
                        buf.push('`');
                    }
                    i += run;
                }
            }
            continue;
        }
        // 图片 ![alt](src)
        if c == '!' && i + 1 < n && chars[i + 1] == '[' {
            if let Some((alt_chars, href, end)) = parse_md_link_at(chars, i + 1) {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Image {
                    src: href,
                    alt: alt_chars.iter().collect(),
                });
                i = end;
                continue;
            }
            // C-28 引用式图片 ![alt][label]
            if let Some((alt_chars, href, end)) = parse_ref_link_at(chars, i + 1, ctx) {
                flush(&mut buf, &mut out);
                ctx.ref_links_used += 1;
                out.push(InlineSeg::Image {
                    src: href,
                    alt: alt_chars.iter().collect(),
                });
                i = end;
                continue;
            }
        }
        if c == '[' {
            // wiki 链接 [[目标|标签]]
            if i + 1 < n && chars[i + 1] == '[' {
                if let Some((target, label, end)) = parse_wiki_at(chars, i) {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Wiki { target, label });
                    i = end;
                    continue;
                }
            }
            // 脚注引用 [^label]
            if i + 1 < n && chars[i + 1] == '^' {
                let mut j = i + 2;
                while j < n && chars[j] != ']' {
                    j += 1;
                }
                if j < n && j > i + 2 {
                    let label: String = chars[i + 2..j].iter().collect();
                    // R8：label 含空白不算脚注引用（原版
                    // 正则 \[\^([^\]\s]+)\] 口径），保持字
                    // 面；此前 trim 后命中属误报。
                    if !label.chars().any(|c| c.is_whitespace()) {
                        if let Some(seg) = ctx.foot_ref(&label) {
                            flush(&mut buf, &mut out);
                            out.push(seg);
                            i = j + 1;
                            continue;
                        }
                    }
                }
            }
            // 普通链接 [text](href)
            if let Some((text_chars, href, end)) = parse_md_link_at(chars, i) {
                flush(&mut buf, &mut out);
                let saved = ctx.in_link;
                ctx.in_link = true;
                let children = parse_inline_chars(&text_chars, ctx);
                ctx.in_link = saved;
                out.push(InlineSeg::Link { href, children });
                i = end;
                continue;
            }
            // C-28 引用式链接 [text][label] / [text][] / [label]
            if let Some((text_chars, href, end)) = parse_ref_link_at(chars, i, ctx) {
                flush(&mut buf, &mut out);
                ctx.ref_links_used += 1;
                let saved = ctx.in_link;
                ctx.in_link = true;
                let children = parse_inline_chars(&text_chars, ctx);
                ctx.in_link = saved;
                out.push(InlineSeg::Link { href, children });
                i = end;
                continue;
            }
        }
        // 原始 HTML（C-28，先于 autolink）与角标 autolink
        // <https://…>
        if c == '<' {
            if let Some((segs, end)) = handle_html_at(chars, i, ctx) {
                flush(&mut buf, &mut out);
                out.extend(segs);
                i = end;
                continue;
            }
            let mut j = i + 1;
            while j < n && chars[j] != '>' && chars[j] != '\n' {
                j += 1;
            }
            if j < n && chars[j] == '>' {
                let inner: String = chars[i + 1..j].iter().collect();
                if inner.starts_with("http://") || inner.starts_with("https://") {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Link {
                        href: inner.clone(),
                        children: vec![InlineSeg::Text(inner)],
                    });
                    i = j + 1;
                    continue;
                }
            }
        }
        // GFM 裸链接 / 邮箱 autolink（marked gfm 口径，双边
        // 预言机实测：https://…、www.…、me@example.com 成
        // 链接；a@b 不成）。链接文本内不触发（ctx.in_link）。
        if !ctx.in_link && c.is_ascii_alphanumeric() {
            if let Some((label, href, end)) = scan_autolink(chars, i) {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Link {
                    href,
                    children: vec![InlineSeg::Text(label)],
                });
                i = end;
                continue;
            }
        }
        // ~~删除~~（内容不二次解析）
        if c == '~' && i + 1 < n && chars[i + 1] == '~' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['~', '~'], &['~', '~'], &['~', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Del(content));
                i = end;
                continue;
            }
        }
        // ==高亮==（内容不二次解析）
        if c == '=' && i + 1 < n && chars[i + 1] == '=' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['=', '='], &['=', '='], &['=', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Highlight(content));
                i = end;
                continue;
            }
        }
        // ^(上标)^ / ~(下标)~
        if c == '^' && i + 1 < n && chars[i + 1] == '(' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['^', '('], &[')', '^'], &['(', ')', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sup(content));
                i = end;
                continue;
            }
        }
        if c == '~' && i + 1 < n && chars[i + 1] == '(' {
            if let Some((content, end)) =
                scan_span_at(chars, i, &['~', '('], &[')', '~'], &['(', ')', '\n'])
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sub(content));
                i = end;
                continue;
            }
        }
        // ^裸上标^
        if c == '^' && i + 1 < n && is_sup_char(chars[i + 1], true) {
            let mut j = i + 1;
            while j < n && is_sup_char(chars[j], false) {
                j += 1;
            }
            if j < n && chars[j] == '^' && j > i + 1 {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sup(chars[i + 1..j].iter().collect()));
                i = j + 1;
                continue;
            }
        }
        // ~裸下标~（前字符非 ~、闭合 ~ 后非 ~）
        if c == '~'
            && (i == 0 || chars[i - 1] != '~')
            && i + 1 < n
            && is_sup_char(chars[i + 1], true)
        {
            let mut j = i + 1;
            while j < n && is_sup_char(chars[j], false) {
                j += 1;
            }
            if j < n && chars[j] == '~' && j > i + 1 && (j + 1 >= n || chars[j + 1] != '~')
            {
                flush(&mut buf, &mut out);
                out.push(InlineSeg::Sub(chars[i + 1..j].iter().collect()));
                i = j + 1;
                continue;
            }
        }
        // 三连定界 ***x*** / ___x___：原版 marked 渲染为
        // <em><strong>x</strong></em>（双边预言机实测）。
        if (c == '*' || c == '_')
            && i + 3 < n
            && chars[i + 1] == c
            && chars[i + 2] == c
            && !chars[i + 3].is_whitespace()
        {
            let word_inner = c == '_' && i > 0 && chars[i - 1].is_alphanumeric();
            if !word_inner {
                let mut k = i + 3;
                let mut closed = None;
                while k + 2 < n {
                    if chars[k] == c && chars[k + 1] == c && chars[k + 2] == c {
                        if k > i + 3 && !chars[k - 1].is_whitespace() {
                            closed = Some(k);
                        }
                        break;
                    }
                    k += 1;
                }
                if let Some(k) = closed {
                    let inner: Vec<char> = chars[i + 3..k].to_vec();
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Em(vec![InlineSeg::Strong(
                        parse_inline_chars(&inner, ctx),
                    )]));
                    i = k + 3;
                    continue;
                }
            }
        }
        // 粗体 ** / __（__ 不在词内触发；开定界后不得是空白，
        // marked flanking 口径：`** 粗 **` 保持字面）
        if (c == '*' || c == '_')
            && i + 2 < n
            && chars[i + 1] == c
            && !chars[i + 2].is_whitespace()
        {
            let word_inner = c == '_' && i > 0 && chars[i - 1].is_alphanumeric();
            if !word_inner {
                if let Some((inner, end)) = scan_delim(chars, i + 2, c, true) {
                    flush(&mut buf, &mut out);
                    out.push(InlineSeg::Strong(parse_inline_chars(&inner, ctx)));
                    i = end;
                    continue;
                }
            }
        }
        // 斜体 * / _（开定界后不得是空白，同上；当前符若是
        // 双符 run 的起点则不作单符斜体——那是粗体/三连的
        // 领地，粗体因 flanking 失败时原版保持字面，如
        // `** 粗**` 不得退化成斜体吞掉第二个 *）
        if (c == '*' || c == '_')
            && i + 1 < n
            && chars[i + 1] != c
            && !chars[i + 1].is_whitespace()
        {
            let word_inner = c == '_' && i > 0 && chars[i - 1].is_alphanumeric();
            if !word_inner {
                if let Some((inner, end)) = scan_delim(chars, i + 1, c, false) {
                    // _ 斜体闭合后不得紧跟字母数字（词内不触发）
                    let after_ok = c == '*'
                        || end >= n
                        || !chars[end].is_alphanumeric();
                    if after_ok {
                        flush(&mut buf, &mut out);
                        out.push(InlineSeg::Em(parse_inline_chars(&inner, ctx)));
                        i = end;
                        continue;
                    }
                }
            }
        }
        buf.push(c);
        i += 1;
    }
    flush(&mut buf, &mut out);
    out
}

/// 找等长反引号闭合串，返回 (内容字符, 闭合串之后下标)。
fn find_code_close(
    chars: &[char],
    from: usize,
    run: usize,
) -> Option<(Vec<char>, usize)> {
    let n = chars.len();
    let mut j = from;
    while j < n {
        if chars[j] == '`' {
            let mut r = 0;
            while j + r < n && chars[j + r] == '`' {
                r += 1;
            }
            if r == run {
                return Some((chars[from..j].to_vec(), j + r));
            }
            j += r;
        } else {
            j += 1;
        }
    }
    None
}

/// marked 代码段内容规范化：换行变空格；首尾各一个空格且
/// 内容非全空格时各剥一个。
fn code_content(raw: &[char]) -> String {
    let mut s: String = raw
        .iter()
        .map(|c| if *c == '\n' { ' ' } else { *c })
        .collect();
    if s.len() > 1 && s.starts_with(' ') && s.ends_with(' ') && !s.trim().is_empty() {
        s.remove(0);
        s.pop();
    }
    s
}

/// 在 chars[start]=='[' 且 chars[start+1]=='[' 处解析
/// [[目标|标签]]（规则同 parse_wiki 注释），返回
/// (target, label, 结束下标)。
fn parse_wiki_at(chars: &[char], start: usize) -> Option<(String, String, usize)> {
    let n = chars.len();
    let mut j = start + 2;
    let mut close = None;
    while j < n {
        if chars[j] == '\n' || chars[j] == '\r' {
            return None;
        }
        if chars[j] == ']' {
            if j + 1 < n && chars[j + 1] == ']' {
                close = Some(j);
            }
            break;
        }
        j += 1;
    }
    let close = close?;
    let inner: String = chars[start + 2..close].iter().collect();
    let mut parts = inner.splitn(2, '|');
    let target_raw = parts.next().unwrap_or("");
    let label_raw = parts.next();
    if target_raw.is_empty() {
        return None;
    }
    if let Some(l) = label_raw {
        if l.is_empty() {
            return None;
        }
    }
    let target = target_raw.trim().to_string();
    if target.is_empty() {
        return None;
    }
    let label = label_raw
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .unwrap_or(target.clone());
    Some((target, label, close + 2))
}

/// 在 chars[j..]（定界符 run 起点）找一段完整的双字符定界
/// 跨度（**…** / __…__，内容首尾非空白），返回跨度之后下标。
/// 单字符定界扫描遇到双符 run 时用它整段跳过内层粗体。
fn skip_strong_span(chars: &[char], j: usize, delim: char) -> Option<usize> {
    let n = chars.len();
    let mut run = 0;
    while j + run < n && chars[j + run] == delim {
        run += 1;
    }
    if run < 2 {
        return None;
    }
    let start = j + run;
    let mut k = start;
    while k < n {
        if chars[k] == delim {
            let mut r2 = 0;
            while k + r2 < n && chars[k + r2] == delim {
                r2 += 1;
            }
            if r2 >= 2
                && k > start
                && !chars[start].is_whitespace()
                && !chars[k - 1].is_whitespace()
            {
                return Some(k + r2);
            }
            k += r2;
        } else {
            k += 1;
        }
    }
    None
}

/// 找粗/斜体闭合定界：double=true 找双字符定界，否则单字符。
/// 按 marked（CommonMark 定界栈）的近似口径：开定界后首字符
/// 与闭定界前末字符都不得是空白（`** 粗 **`、`* 3 *` 在原版
/// 保持字面）；闭合候选若内容以空白结尾则跳过继续找；同定
/// 界的嵌套开定界（前空白、后非空白）计深度，深度归零处才
/// 是外层闭合（`*a *b* c*`、`**a **b** c**` 的嵌套形）。
/// 单字符扫描遇到双符 run 时，若其构成完整粗体跨度则整段
/// 跳过（`*斜 **粗** 斜*`）。
fn scan_delim(
    chars: &[char],
    from: usize,
    delim: char,
    double: bool,
) -> Option<(Vec<char>, usize)> {
    let n = chars.len();
    let unit = if double { 2 } else { 1 };
    let mut depth = 1usize;
    let mut j = from;
    while j < n {
        if chars[j] != delim {
            j += 1;
            continue;
        }
        let mut run = 0;
        while j + run < n && chars[j + run] == delim {
            run += 1;
        }
        if !double && run >= 2 {
            if let Some(after) = skip_strong_span(chars, j, delim) {
                j = after;
                continue;
            }
        }
        if double && run < 2 {
            j += run;
            continue;
        }
        // 闭合候选：定界前一字符（即内容末字符）非空白
        let can_close = j > from && !chars[j - 1].is_whitespace();
        if can_close {
            if depth == 1 {
                return Some((chars[from..j].to_vec(), j + unit));
            }
            depth -= 1;
            j += run;
            continue;
        }
        // 不能闭合：若是嵌套开定界（前空白、run 后非空白）计深度
        let after = j + run;
        let can_open = after < n
            && !chars[after].is_whitespace()
            && (j == 0 || chars[j - 1].is_whitespace());
        if can_open {
            depth += 1;
        }
        j += run;
    }
    None
}

/// 行内分段渲染：wiki 段经 WikiNav 上报导航，其余按
/// marked 元素形状输出。

// ===== 块级 Markdown 解析（marked 子集） =====
//
// 把一个 md 源段落的全文解析为块序列：混合结构段（标题+正文、
// 正文+列表、setext）按 marked 的块语法逐行切分，不再要求整段
// 同型（M3）。行内文本在切分时即经 parse_inlines 解析为分段。

#[derive(Clone, PartialEq, Serialize)]
pub enum MdBlock {
    Code {
        lang: Option<String>,
        code: String,
    },
    Heading {
        level: u8,
        segs: Vec<InlineSeg>,
    },
    Para {
        segs: Vec<InlineSeg>,
    },
    /// 独占段落的块级公式（$$…$$）：居中成块渲染。
    Math {
        tex: String,
    },
    Quote {
        blocks: Vec<MdBlock>,
    },
    Callout {
        style: &'static str,
        title: String,
        folding: Option<char>,
        blocks: Vec<MdBlock>,
    },
    List {
        ordered: bool,
        start: u64,
        items: Vec<MdItem>,
    },
    Table {
        head: Vec<Vec<InlineSeg>>,
        align: Vec<u8>,
        rows: Vec<Vec<Vec<InlineSeg>>>,
    },
    Divider,
    Footnotes {
        items: Vec<FnItem>,
    },
}

#[derive(Clone, PartialEq, Serialize)]
pub struct MdItem {
    pub checked: Option<bool>,
    pub segs: Vec<InlineSeg>,
    /// 缩进子块（嵌套列表等）：原版 marked 把 `- 父项` 下
    /// 缩进的 `- 子项` 渲染为 li 内的嵌套 ul/ol（预言机实测），
    /// 旧实现把它拍平成同级项。
    pub sub: Vec<MdBlock>,
}

#[derive(Clone, PartialEq, Serialize)]
pub struct FnItem {
    pub id: String,
    pub ref_ids: Vec<String>,
    pub blocks: Vec<MdBlock>,
}

#[derive(Clone, PartialEq)]
enum Marker {
    Bullet(char),
    Ordered(u64, char),
}

fn leading_spaces(line: &str) -> usize {
    line.chars().take_while(|c| *c == ' ').count()
}

/// C-28 缩进代码判定：≥4 空格或行首 tab（marked 按 4 列宽
/// 折算 tab）。
fn is_code_indented(line: &str) -> bool {
    leading_spaces(line) >= 4 || line.starts_with('\t')
}

/// 剥一层代码缩进：4 空格或 1 tab。
fn dedent4(line: &str) -> String {
    if let Some(r) = line.strip_prefix("    ") {
        r.to_string()
    } else if let Some(r) = line.strip_prefix('\t') {
        r.to_string()
    } else {
        line.to_string()
    }
}

/// 围栏起始行（≤3 空格 + 3 个以上 ` 或 ~），返回 (字符, 长度, info)。
fn fence_start(line: &str) -> Option<(char, usize, String)> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let rest = &line[sp..];
    let fc = rest.chars().next()?;
    if fc != '`' && fc != '~' {
        return None;
    }
    let len = rest.chars().take_while(|c| *c == fc).count();
    if len < 3 {
        return None;
    }
    let info = rest[len..].trim().to_string();
    if fc == '`' && info.contains('`') {
        return None;
    }
    Some((fc, len, info))
}

fn fence_close(line: &str, fc: char, open_len: usize) -> bool {
    let sp = leading_spaces(line);
    if sp > 3 {
        return false;
    }
    let rest = line[sp..].trim_end();
    !rest.is_empty() && rest.len() >= open_len && rest.chars().all(|c| c == fc)
}

/// ATX 标题行，返回 (级别, 文本)。闭合 # 序列按 marked 剥除。
fn atx_heading(line: &str) -> Option<(u8, String)> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let rest = &line[sp..];
    let hashes = rest.chars().take_while(|c| *c == '#').count();
    if hashes == 0 || hashes > 6 {
        return None;
    }
    let after = &rest[hashes..];
    if after.is_empty() {
        return Some((hashes as u8, String::new()));
    }
    if !after.starts_with(' ') && !after.starts_with('\t') {
        return None;
    }
    let mut text = after.trim().to_string();
    if text.ends_with('#') {
        let stripped = text.trim_end_matches('#');
        if stripped.len() < text.len()
            && (stripped.is_empty() || stripped.ends_with(' ') || stripped.ends_with('\t'))
        {
            text = stripped.trim().to_string();
        }
    }
    Some((hashes as u8, text))
}

fn setext_level(line: &str) -> Option<u8> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let t = line[sp..].trim();
    if t.is_empty() {
        return None;
    }
    if t.chars().all(|c| c == '=') {
        Some(1)
    } else if t.chars().all(|c| c == '-') {
        Some(2)
    } else {
        None
    }
}

fn is_thematic_break(line: &str) -> bool {
    let sp = leading_spaces(line);
    if sp > 3 {
        return false;
    }
    let rest: String = line[sp..]
        .chars()
        .filter(|c| *c != ' ' && *c != '\t')
        .collect();
    if rest.len() < 3 {
        return false;
    }
    let fc = rest.chars().next().unwrap();
    matches!(fc, '-' | '*' | '_') && rest.chars().all(|c| c == fc)
}

/// 引用行剥前缀（≤3 空格 + > + 可选一空格），非引用行返回 None。
fn quote_strip(line: &str) -> Option<String> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let r = line[sp..].strip_prefix('>')?;
    Some(r.strip_prefix(' ').unwrap_or(r).to_string())
}

/// 列表标记行，返回 (标记, 项文本)。标记后须有空格/制表符。
fn list_marker(line: &str) -> Option<(Marker, String)> {
    let sp = leading_spaces(line);
    if sp > 3 {
        return None;
    }
    let rest = &line[sp..];
    let c0 = rest.chars().next()?;
    if matches!(c0, '-' | '*' | '+') {
        let after = &rest[1..];
        if after.starts_with(' ') || after.starts_with('\t') {
            return Some((Marker::Bullet(c0), after[1..].to_string()));
        }
        return None;
    }
    if c0.is_ascii_digit() {
        let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
        if digits.len() > 9 {
            return None;
        }
        let after_digits = &rest[digits.len()..];
        let delim = after_digits.chars().next()?;
        if delim != '.' && delim != ')' {
            return None;
        }
        let after = &after_digits[1..];
        if after.starts_with(' ') || after.starts_with('\t') {
            let num: u64 = digits.parse().ok()?;
            return Some((Marker::Ordered(num, delim), after[1..].to_string()));
        }
    }
    None
}

/// 该行是否打断段落收集（围栏/引用/标题/分隔线/列表；
/// 有序列表仅 1. 可打断，marked 口径）。
fn interrupts_paragraph(line: &str) -> bool {
    if fence_start(line).is_some()
        || quote_strip(line).is_some()
        || atx_heading(line).is_some()
        || is_thematic_break(line)
    {
        return true;
    }
    match list_marker(line) {
        Some((Marker::Bullet(_), _)) => true,
        Some((Marker::Ordered(num, _), _)) => num == 1,
        None => false,
    }
}

/// 表头行 + 分隔行 → 对齐表（列数须相等，marked 口径）。
fn table_aligns(header: &str, sep: &str) -> Option<Vec<u8>> {
    let head = split_table_row(header);
    let cells = split_table_row(sep);
    if head.is_empty() || head.len() != cells.len() {
        return None;
    }
    let mut aligns = Vec::new();
    for c in &cells {
        let c = c.trim();
        if c.is_empty()
            || !c.chars().all(|ch| ch == '-' || ch == ':')
            || !c.contains('-')
        {
            return None;
        }
        aligns.push(if c.starts_with(':') && c.ends_with(':') {
            1
        } else if c.ends_with(':') {
            2
        } else {
            0
        });
    }
    Some(aligns)
}

/// Callout 首行头解析：[!TYPE] + 可选折叠符 + 可选标题
/// （原版 preprocessCallouts 正则口径；无空格的尾巴不作标题）。
fn callout_header(line: &str) -> Option<(String, String, Option<char>, String)> {
    let rest = line.strip_prefix("[!")?;
    let end = rest.find(']')?;
    let raw_type = &rest[..end];
    if raw_type.is_empty()
        || !raw_type
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return None;
    }
    let mut tail = &rest[end + 1..];
    let mut folding = None;
    if tail.starts_with('+') || tail.starts_with('-') {
        folding = Some(tail.chars().next().unwrap());
        tail = &tail[1..];
    }
    let custom = if tail.is_empty() {
        String::new()
    } else if tail.starts_with(' ') || tail.starts_with('\t') {
        tail.trim().to_string()
    } else {
        String::new()
    };
    // C-21：除小写形外同时返回类型原文，未知类型标题兜底用
    Some((raw_type.to_lowercase(), raw_type.to_string(), folding, custom))
}

fn md_quote_block(inner: Vec<String>, ctx: &mut InlineCtx) -> MdBlock {
    if let Some(first) = inner.first() {
        if let Some((raw, raw_orig, folding, custom)) = callout_header(first) {
            let (style, default_title) = callout_style_title(&raw);
            // C-21：未知类型标题回退类型原文（保留大小写）
            let title = if !custom.is_empty() {
                custom
            } else if let Some(dt) = default_title {
                dt.to_string()
            } else {
                raw_orig
            };
            let body_text = inner[1..].join("\n");
            let blocks = if body_text.trim().is_empty() {
                Vec::new()
            } else {
                let blines: Vec<&str> = body_text.split('\n').collect();
                parse_md_blocks(&blines, ctx)
            };
            return MdBlock::Callout {
                style,
                title,
                folding,
                blocks,
            };
        }
    }
    let text = inner.join("\n");
    let lines: Vec<&str> = text.split('\n').collect();
    MdBlock::Quote {
        blocks: parse_md_blocks(&lines, ctx),
    }
}

/// 任务项拆分：[ ] / [x] / [X] 前缀（后接空格或整项仅此标记）。
fn task_split(text: &str) -> (Option<bool>, String) {
    for (pat, val) in [
        ("[ ] ", false),
        ("[x] ", true),
        ("[X] ", true),
    ] {
        if let Some(rest) = text.strip_prefix(pat) {
            return (Some(val), rest.to_string());
        }
    }
    for (pat, val) in [("[ ]", false), ("[x]", true), ("[X]", true)] {
        if text == pat {
            return (Some(val), String::new());
        }
    }
    (None, text.to_string())
}

fn parse_md_list(
    lines: &[&str],
    start: usize,
    first: &Marker,
    ctx: &mut InlineCtx,
) -> (MdBlock, usize) {
    let ordered = matches!(first, Marker::Ordered(..));
    let start_num = match first {
        Marker::Ordered(num, _) => *num,
        _ => 1,
    };
    let same_kind = |m: &Marker| -> bool {
        match (first, m) {
            (Marker::Bullet(a), Marker::Bullet(b)) => a == b,
            (Marker::Ordered(_, a), Marker::Ordered(_, b)) => a == b,
            _ => false,
        }
    };
    let mut items: Vec<MdItem> = Vec::new();
    let mut i = start;
    while i < lines.len() {
        match list_marker(lines[i]) {
            Some((m, content)) if same_kind(&m) => {
                let mut text = content;
                let mut sub: Vec<MdBlock> = Vec::new();
                let mut j = i + 1;
                while j < lines.len() {
                    let l = lines[j];
                    if l.trim().is_empty() {
                        break;
                    }
                    let indented = l.starts_with("  ") || l.starts_with('\t');
                    if !indented {
                        break;
                    }
                    let stripped = l.trim_start();
                    if list_marker(stripped).is_some() {
                        // 缩进列表行 = 嵌套子列表：连续的缩进
                        // 行整体去缩进后递归解析（marked 口径）。
                        let mut sublines: Vec<&str> = Vec::new();
                        while j < lines.len() {
                            let sl = lines[j];
                            if sl.trim().is_empty()
                                || !(sl.starts_with("  ") || sl.starts_with('\t'))
                            {
                                break;
                            }
                            sublines.push(sl.trim_start());
                            j += 1;
                        }
                        sub.extend(parse_md_blocks(&sublines, ctx));
                    } else {
                        text.push('\n');
                        text.push_str(stripped);
                        j += 1;
                    }
                }
                let (checked, item_text) = task_split(&text);
                items.push(MdItem {
                    checked,
                    segs: parse_inlines(&item_text, ctx),
                    sub,
                });
                i = j;
            }
            _ => break,
        }
    }
    (
        MdBlock::List {
            ordered,
            start: start_num,
            items,
        },
        i,
    )
}

fn parse_md_blocks(lines: &[&str], ctx: &mut InlineCtx) -> Vec<MdBlock> {
    let n = lines.len();
    let mut blocks: Vec<MdBlock> = Vec::new();
    let mut i = 0;
    while i < n {
        let line = lines[i];
        if line.trim().is_empty() {
            i += 1;
            continue;
        }
        // C-28 缩进代码块：≥4 空格（或 1 tab）缩进的连续行
        // （marked 口径：缩进代码不能中断段落，故仅块首判
        // 定；段内缩进行由段落收集作续行）。空行可夹在块
        // 内，尾部空行裁掉；每行剥 4 空格 / 1 tab。
        if is_code_indented(line) {
            let mut code_lines: Vec<String> = Vec::new();
            while i < n {
                let l = lines[i];
                if l.trim().is_empty() {
                    code_lines.push(String::new());
                    i += 1;
                    continue;
                }
                if is_code_indented(l) {
                    code_lines.push(dedent4(l));
                    i += 1;
                    continue;
                }
                break;
            }
            while code_lines.last().is_some_and(|s| s.is_empty()) {
                code_lines.pop();
            }
            if !code_lines.is_empty() {
                blocks.push(MdBlock::Code {
                    lang: None,
                    code: code_lines.join("\n"),
                });
                continue;
            }
        }
        // 围栏代码（闭合可缺省，未闭合取到段尾）
        if let Some((fc, flen, info)) = fence_start(line) {
            let mut j = i + 1;
            let mut code_lines: Vec<&str> = Vec::new();
            while j < n {
                if fence_close(lines[j], fc, flen) {
                    break;
                }
                code_lines.push(lines[j]);
                j += 1;
            }
            let lang = info
                .split_whitespace()
                .next()
                .map(|s| s.to_string())
                .filter(|s| !s.is_empty());
            blocks.push(MdBlock::Code {
                lang,
                code: code_lines.join("\n"),
            });
            i = if j < n { j + 1 } else { j };
            continue;
        }
        // 引用 / Callout（含懒续行）
        if quote_strip(line).is_some() {
            let mut inner: Vec<String> = Vec::new();
            let mut j = i;
            while j < n {
                if let Some(s) = quote_strip(lines[j]) {
                    inner.push(s);
                    j += 1;
                } else if !lines[j].trim().is_empty()
                    && !inner
                        .last()
                        .map(|s| s.trim().is_empty())
                        .unwrap_or(true)
                    && !interrupts_paragraph(lines[j])
                {
                    inner.push(lines[j].to_string());
                    j += 1;
                } else {
                    break;
                }
            }
            blocks.push(md_quote_block(inner, ctx));
            i = j;
            continue;
        }
        // ATX 标题
        if let Some((level, text)) = atx_heading(line) {
            blocks.push(MdBlock::Heading {
                level,
                segs: parse_inlines(&text, ctx),
            });
            i += 1;
            continue;
        }
        // 表格
        if line.contains('|') && i + 1 < n {
            if let Some(align) = table_aligns(line, lines[i + 1]) {
                let head_cells = split_table_row(line);
                let width = head_cells.len();
                let head: Vec<Vec<InlineSeg>> = head_cells
                    .iter()
                    .map(|c| parse_inlines(c.trim(), ctx))
                    .collect();
                let mut rows: Vec<Vec<Vec<InlineSeg>>> = Vec::new();
                let mut j = i + 2;
                while j < n && !lines[j].trim().is_empty() {
                    let mut cells: Vec<Vec<InlineSeg>> = split_table_row(lines[j])
                        .iter()
                        .map(|c| parse_inlines(c.trim(), ctx))
                        .collect();
                    cells.truncate(width);
                    while cells.len() < width {
                        cells.push(Vec::new());
                    }
                    rows.push(cells);
                    j += 1;
                }
                blocks.push(MdBlock::Table { head, align, rows });
                i = j;
                continue;
            }
        }
        // 分隔线
        if is_thematic_break(line) {
            blocks.push(MdBlock::Divider);
            i += 1;
            continue;
        }
        // 列表
        if let Some((marker, _)) = list_marker(line) {
            let (list, j) = parse_md_list(lines, i, &marker, ctx);
            blocks.push(list);
            i = j;
            continue;
        }
        // 段落收集（setext 下划线行在此吸收为标题）
        let mut para_lines: Vec<&str> = vec![line];
        let mut setext: Option<u8> = None;
        let mut j = i + 1;
        while j < n {
            let l = lines[j];
            if l.trim().is_empty() {
                break;
            }
            if let Some(lv) = setext_level(l) {
                setext = Some(lv);
                j += 1;
                break;
            }
            if interrupts_paragraph(l) {
                break;
            }
            if l.contains('|') && j + 1 < n && table_aligns(l, lines[j + 1]).is_some()
            {
                break;
            }
            para_lines.push(l);
            j += 1;
        }
        let text = para_lines.join("\n");
        match setext {
            Some(lv) => blocks.push(MdBlock::Heading {
                level: lv,
                segs: parse_inlines(&text, ctx),
            }),
            None => {
                // 独占段落的块级公式 → Math 块（居中成块）。
                let trimmed = text.trim();
                match split_math(trimmed).as_slice() {
                    [MathSegment::Math { tex, display: true }] => {
                        blocks.push(MdBlock::Math { tex: tex.clone() });
                    }
                    _ => blocks.push(MdBlock::Para {
                        segs: parse_inlines(&text, ctx),
                    }),
                }
            }
        }
        i = j;
    }
    blocks
}

/// 文档级解析结果：块序列 + C-28 解析面计数（引用式
/// 链接数 / 原始 HTML 标签数，供调用方量测层落 Diag）。
pub struct MdParseOutcome {
    pub blocks: Vec<MdBlock>,
    pub ref_links_used: usize,
    pub html_tags_used: usize,
}

/// 文档级解析：先抽脚注定义，块序列解析后把已引用定义组装为
/// 脚注区（定义顺序）。未引用定义：原版 preprocess 把原文回填
/// 文末后，marked 的词法会把 `[^x]: 单token` 形整行当作链接
/// 定义吞掉（不渲染），正文含空白时才以字面段落出现（双边
/// 预言机实测 U1/U2）——此处按同一口径分流。
pub fn parse_md_document(text: &str) -> Vec<MdBlock> {
    parse_md_document_counted(text).blocks
}

pub fn parse_md_document_counted(text: &str) -> MdParseOutcome {
    let (kept, defs) = extract_footnotes(text);
    // C-28：链接引用定义在脚注定义抽走后抽取（定义行不渲染）
    let (kept, link_defs) = extract_link_defs(&kept);
    let mut ctx = InlineCtx::empty();
    for (idx, d) in defs.iter().enumerate() {
        ctx.def_map.insert(d.label.to_lowercase(), idx);
    }
    ctx.defs = defs;
    for (label, href) in link_defs {
        ctx.link_defs.insert(label, href);
    }
    let lines: Vec<&str> = kept.split('\n').collect();
    let mut blocks = parse_md_blocks(&lines, &mut ctx);
    // C-28 新解析面计数（引用式链接数 / 原始 HTML 标签数）
    // 随结果带出，由调用方取走落 Diag——解析层不直调 diag。
    let ref_links_used = ctx.ref_links_used;
    let html_tags_used = ctx.html_tags_used;
    let mut fn_items: Vec<FnItem> = Vec::new();
    let mut unused: Vec<String> = Vec::new();
    for (idx, def) in ctx.defs.iter().enumerate() {
        match ctx.ref_ids.get(&idx) {
            Some(ref_ids) => {
                let mut ectx = InlineCtx::empty();
                let blines: Vec<&str> = def.body.split('\n').collect();
                let body_blocks = if def.body.trim().is_empty() {
                    Vec::new()
                } else {
                    parse_md_blocks(&blines, &mut ectx)
                };
                fn_items.push(FnItem {
                    id: def.id.clone(),
                    ref_ids: ref_ids.clone(),
                    blocks: body_blocks,
                });
            }
            None => {
                // marked 链接定义吞行口径：不渲染（组件层记 RENDER 日志）
                let first_body = def.body.lines().next().unwrap_or("");
                if first_body.chars().any(|c| c.is_whitespace()) {
                    unused.push(def.original.clone());
                }
            }
        }
    }
    if !fn_items.is_empty() {
        blocks.push(MdBlock::Footnotes { items: fn_items });
    }
    for u in unused {
        blocks.push(MdBlock::Para {
            segs: vec![InlineSeg::Text(u)],
        });
    }
    MdParseOutcome {
        blocks,
        ref_links_used,
        html_tags_used,
    }
}

/// 该 md 源文本渲染成块级预览（.md-preview.block）而非行内
/// 预览：parse 后不止一个块，或唯一的块不是普通段落。与
/// MdPreview 的分支判定同源，供编辑器块流决定尾随空段
/// （原版 ensureTrailingParagraphBlock 只跟块级预览）。
pub fn md_is_block_preview(text: &str) -> bool {
    let blocks = parse_md_document(text);
    !(blocks.len() == 1 && matches!(blocks[0], MdBlock::Para { .. }))
}

#[cfg(test)]
mod md_render_tests {
    use super::*;

    fn seg_dump(segs: &[InlineSeg]) -> String {
        segs.iter()
            .map(|s| match s {
                InlineSeg::Text(t) => format!("T({t:?})"),
                InlineSeg::Code(t) => format!("C({t:?})"),
                InlineSeg::Strong(c) => format!("B[{}]", seg_dump(c)),
                InlineSeg::Em(c) => format!("I[{}]", seg_dump(c)),
                InlineSeg::Underline(c) => format!("U[{}]", seg_dump(c)),
                InlineSeg::Del(t) => format!("D({t:?})"),
                InlineSeg::Highlight(t) => format!("H({t:?})"),
                InlineSeg::Sup(t) => format!("Sup({t:?})"),
                InlineSeg::Sub(t) => format!("Sub({t:?})"),
                InlineSeg::Link { href, children } => {
                    format!("A({href})[{}]", seg_dump(children))
                }
                InlineSeg::Image { src, alt } => format!("Img({src},{alt:?})"),
                InlineSeg::Wiki { target, label } => format!("W({target}|{label})"),
                InlineSeg::FootRef { id, ref_id, number } => {
                    format!("Fn({id},{ref_id},{number})")
                }
                InlineSeg::Math { tex, display } => format!("M({tex},{display})"),
                InlineSeg::Break => "BR".to_string(),
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn block_dump(blocks: &[MdBlock]) -> String {
        blocks
            .iter()
            .map(|b| match b {
                MdBlock::Code { lang, code } => {
                    format!("Code({})[{code:?}]", lang.as_deref().unwrap_or("-"))
                }
                MdBlock::Heading { level, segs } => {
                    format!("H{level}[{}]", seg_dump(segs))
                }
                MdBlock::Para { segs } => format!("P[{}]", seg_dump(segs)),
                MdBlock::Math { tex } => format!("MathBlk({tex})"),
                MdBlock::Quote { blocks } => {
                    format!("Q{{{}}}", block_dump(blocks))
                }
                MdBlock::Callout {
                    style,
                    title,
                    folding,
                    blocks,
                } => format!(
                    "Callout({style},{title:?},{}){{{}}}",
                    folding
                        .map(|c| format!("Some({c})"))
                        .unwrap_or_else(|| "None".into()),
                    block_dump(blocks)
                ),
                MdBlock::List {
                    ordered,
                    start,
                    items,
                } => {
                    let its: Vec<String> = items
                        .iter()
                        .map(|it| {
                            format!(
                                "({})[{}]sub{{{}}}",
                                it.checked
                                    .map(|c| c.to_string())
                                    .unwrap_or_else(|| "-".into()),
                                seg_dump(&it.segs),
                                block_dump(&it.sub)
                            )
                        })
                        .collect();
                    format!(
                        "List({},{})[{}]",
                        if *ordered { "ol" } else { "ul" },
                        start,
                        its.join(" ")
                    )
                }
                MdBlock::Table { head, align, rows } => {
                    let h: Vec<String> = head.iter().map(|c| seg_dump(c)).collect();
                    let r: Vec<String> = rows
                        .iter()
                        .map(|row| {
                            row.iter()
                                .map(|c| seg_dump(c))
                                .collect::<Vec<_>>()
                                .join("/")
                        })
                        .collect();
                    format!("Tbl({align:?})[{}]{{{}}}", h.join("/"), r.join(";"))
                }
                MdBlock::Divider => "HR".to_string(),
                MdBlock::Footnotes { items } => {
                    let its: Vec<String> = items
                        .iter()
                        .map(|it| {
                            format!(
                                "FnItem({},{:?}){{{}}}",
                                it.id,
                                it.ref_ids,
                                block_dump(&it.blocks)
                            )
                        })
                        .collect();
                    format!("Fns[{}]", its.join(" "))
                }
            })
            .collect::<Vec<_>>()
            .join(" | ")
    }

    fn dump(text: &str) -> String {
        block_dump(&parse_md_document(text))
    }

    fn gate(text: &str) -> &'static str {
        match md_classify(text) {
            Some(MdKind::Code(_)) => "Code",
            Some(MdKind::Rich(_)) => "Rich",
            Some(MdKind::Callout { .. }) => "Callout",
            Some(MdKind::List { .. }) => "List",
            Some(MdKind::Table { .. }) => "Table",
            Some(MdKind::Heading { .. }) => "Heading",
            Some(MdKind::Quote(_)) => "Quote",
            Some(MdKind::Divider) => "Divider",
            None => "None",
        }
    }

    #[test]
    fn m1_inline_and_nesting() {
        assert_eq!(
            dump("这是 **粗体** 和 *斜体* 与 ~~删除~~ 和 `代码` 以及 [外链](https://example.com) 混合"),
            "P[T(\"这是 \") B[T(\"粗体\")] T(\" 和 \") I[T(\"斜体\")] T(\" 与 \") D(\"删除\") T(\" 和 \") C(\"代码\") T(\" 以及 \") A(https://example.com)[T(\"外链\")] T(\" 混合\")]"
        );
        // 嵌套强调：原版 em>strong / strong 内 em / 同定界嵌套
        assert_eq!(dump("*斜 **粗** 斜*"), "P[I[T(\"斜 \") B[T(\"粗\")] T(\" 斜\")]]");
        assert_eq!(dump("**粗 *斜* 粗**"), "P[B[T(\"粗 \") I[T(\"斜\")] T(\" 粗\")]]");
        assert_eq!(dump("*a *b* c* 嵌套"), "P[I[T(\"a \") I[T(\"b\")] T(\" c\")] T(\" 嵌套\")]");
        assert_eq!(dump("**a **b** c** 嵌套"), "P[B[T(\"a \") B[T(\"b\")] T(\" c\")] T(\" 嵌套\")]");
        // 三连定界 = em 包 strong（* 与 _ 皆然）
        assert_eq!(dump("***粗斜*** 文字"), "P[I[B[T(\"粗斜\")]] T(\" 文字\")]");
        assert_eq!(
            dump("***粗斜*** 与 ___粗斜___ 尾"),
            "P[I[B[T(\"粗斜\")]] T(\" 与 \") I[B[T(\"粗斜\")]] T(\" 尾\")]"
        );
        // flanking：定界贴空白即字面（乘法星号、** 粗 **）
        assert_eq!(dump("计算 2 * 3 * 4 结果"), "P[T(\"计算 2 * 3 * 4 结果\")]");
        assert_eq!(dump("a ** 粗 ** b"), "P[T(\"a ** 粗 ** b\")]");
        assert_eq!(dump("a *b * c"), "P[T(\"a *b * c\")]");
        assert_eq!(
            dump("** 粗** 与 **粗 ** 混 **粗**"),
            "P[T(\"** 粗** 与 **粗 ** 混 \") B[T(\"粗\")]]"
        );
        assert_eq!(dump("*a * b*"), "P[I[T(\"a * b\")]]");
        // 软换行 = <br>（marked breaks:true）
        assert_eq!(
            dump("第一行 **粗**\n第二行普通"),
            "P[T(\"第一行 \") B[T(\"粗\")] BR T(\"第二行普通\")]"
        );
    }

    #[test]
    fn m1_autolink() {
        assert_eq!(
            dump("看 https://example.com/path?q=1 这个链接 **粗**"),
            "P[T(\"看 \") A(https://example.com/path?q=1)[T(\"https://example.com/path?q=1\")] T(\" 这个链接 \") B[T(\"粗\")]]"
        );
        assert_eq!(
            dump("- 访问 https://example.com 详情"),
            "List(ul,1)[(-)[T(\"访问 \") A(https://example.com)[T(\"https://example.com\")] T(\" 详情\")]sub{}]"
        );
        assert_eq!(
            dump("访问 www.example.com/path 看看 **粗**"),
            "P[T(\"访问 \") A(http://www.example.com/path)[T(\"www.example.com/path\")] T(\" 看看 \") B[T(\"粗\")]]"
        );
        assert_eq!(
            dump("联系 me@example.com 邮箱 **粗**"),
            "P[T(\"联系 \") A(mailto:me@example.com)[T(\"me@example.com\")] T(\" 邮箱 \") B[T(\"粗\")]]"
        );
        assert_eq!(
            dump("(https://example.com/a) 尾 **粗**"),
            "P[T(\"(\") A(https://example.com/a)[T(\"https://example.com/a\")] T(\") 尾 \") B[T(\"粗\")]]"
        );
        // a@b 无点不成邮箱；链接文本内不套 autolink
        assert_eq!(dump("价格 a@b 不是邮箱 **粗**"), "P[T(\"价格 a@b 不是邮箱 \") B[T(\"粗\")]]");
        assert_eq!(
            dump("[https://a.com](https://b.com) 与 **粗**"),
            "P[A(https://b.com)[T(\"https://a.com\")] T(\" 与 \") B[T(\"粗\")]]"
        );
    }

    #[test]
    fn m2_inline_inside_blocks() {
        assert_eq!(
            dump("- 项 **粗** 与 `代码` 与 [链接](https://a.com)"),
            "List(ul,1)[(-)[T(\"项 \") B[T(\"粗\")] T(\" 与 \") C(\"代码\") T(\" 与 \") A(https://a.com)[T(\"链接\")]]sub{}]"
        );
        assert_eq!(
            dump("| 名 | 值 |\n| --- | ---: |\n| **粗** | `码` |"),
            "Tbl([0, 2])[T(\"名\")/T(\"值\")]{B[T(\"粗\")]/C(\"码\")}"
        );
        assert_eq!(
            dump("> [!warning] 注意\n> - 项一\n> - 项二"),
            "Callout(warning,\"注意\",None){List(ul,1)[(-)[T(\"项一\")]sub{} (-)[T(\"项二\")]sub{}]}"
        );
        assert_eq!(
            dump("# 标题 **粗** `码`"),
            "H1[T(\"标题 \") B[T(\"粗\")] T(\" \") C(\"码\")]"
        );
        // 表格转义竖线不成多格
        assert_eq!(
            dump("| a \\| b | c |\n| --- | --- |\n| 1 | 2 |"),
            "Tbl([0, 0])[T(\"a | b\")/T(\"c\")]{T(\"1\")/T(\"2\")}"
        );
    }

    #[test]
    fn m3_mixed_structures() {
        assert_eq!(dump("# 标题行\n后面一行正文"), "H1[T(\"标题行\")] | P[T(\"后面一行正文\")]");
        assert_eq!(
            dump("前一行\n- 列表项\n- 第二项"),
            "P[T(\"前一行\")] | List(ul,1)[(-)[T(\"列表项\")]sub{} (-)[T(\"第二项\")]sub{}]"
        );
        assert_eq!(dump("文字上\n---\n文字下"), "H2[T(\"文字上\")] | P[T(\"文字下\")]");
        assert_eq!(dump("> 引用首行\n懒续行"), "Q{P[T(\"引用首行\") BR T(\"懒续行\")]}");
        assert_eq!(
            dump("> 第一段\n>\n> 第二段"),
            "Q{P[T(\"第一段\")] | P[T(\"第二段\")]}"
        );
        // 表格混排：解析层能切分（门控另测）；后随普通行按
        // marked 口径并入表格行（补空单元格）
        assert_eq!(
            dump("前文说明\n| a | b |\n| - | - |\n| 1 | 2 |\n后文行"),
            "P[T(\"前文说明\")] | Tbl([0, 0])[T(\"a\")/T(\"b\")]{T(\"1\")/T(\"2\");T(\"后文行\")/}"
        );
    }

    #[test]
    fn m4_fences() {
        assert_eq!(dump("```js\nconst a = 1;\n```"), "Code(js)[\"const a = 1;\"]");
        assert_eq!(dump("~~~js\nconst a = 1;\n~~~"), "Code(js)[\"const a = 1;\"]");
        assert_eq!(dump("```\n未闭合代码"), "Code(-)[\"未闭合代码\"]");
        assert_eq!(dump("````\na```b\n````"), "Code(-)[\"a```b\"]");
    }

    #[test]
    fn r3_lone_fence_and_r9_callout_title() {
        // R3：单行纯 ``` 不分类（不转空代码预览）
        assert_eq!(gate("```"), "None");
        assert_eq!(gate("```\n"), "None");
        // R9：无空格紧贴的尾巴不作标题——classify 与
        // parse 同口径（parse 侧 m5 的带空格形对照）。
        match md_classify("> [!note]标题紧贴\n> 正文") {
            Some(MdKind::Callout { title, .. }) => {
                // 默认标题走 callout_style_title（note=笔记）
                assert_eq!(title, "笔记")
            }
            _ => panic!("expected Callout"),
        }
        match md_classify("> [!note] 我的标题\n> 正文") {
            Some(MdKind::Callout { title, .. }) => {
                assert_eq!(title, "我的标题")
            }
            _ => panic!("expected Callout"),
        }
    }

    #[test]
    fn m5_callout_folding() {
        assert_eq!(
            dump("> [!TIP]-\n> 折叠内容"),
            "Callout(tip,\"提示\",Some(-)){P[T(\"折叠内容\")]}"
        );
        assert_eq!(
            dump("> [!TIP]+\n> 展开内容"),
            "Callout(tip,\"提示\",Some(+)){P[T(\"展开内容\")]}"
        );
        assert_eq!(
            dump("> [!note] 我的标题\n> 正文 **粗**"),
            "Callout(note,\"我的标题\",None){P[T(\"正文 \") B[T(\"粗\")]]}"
        );
    }

    #[test]
    fn m6_lists() {
        assert_eq!(
            dump("- [ ] 未完任务\n- [x] 已完任务"),
            "List(ul,1)[(false)[T(\"未完任务\")]sub{} (true)[T(\"已完任务\")]sub{}]"
        );
        assert_eq!(
            dump("2. 第二项\n3. 第三项"),
            "List(ol,2)[(-)[T(\"第二项\")]sub{} (-)[T(\"第三项\")]sub{}]"
        );
        assert_eq!(
            dump("- 无序一\n- 无序二\n\n1. 有序一"),
            "List(ul,1)[(-)[T(\"无序一\")]sub{} (-)[T(\"无序二\")]sub{}] | List(ol,1)[(-)[T(\"有序一\")]sub{}]"
        );
        // 嵌套列表进父项 sub（原版 li 内嵌 ul）
        assert_eq!(
            dump("- 父项\n  - 子项"),
            "List(ul,1)[(-)[T(\"父项\")]sub{List(ul,1)[(-)[T(\"子项\")]sub{}]}]"
        );
        // 项续行 = 项内 <br>
        assert_eq!(
            dump("- 项一\n  续行内容"),
            "List(ul,1)[(-)[T(\"项一\") BR T(\"续行内容\")]sub{}]"
        );
    }

    #[test]
    fn r5_angle_href_and_r8_foot_label_space() {
        // R5：角括号 href 整体作链（内含空格不截断）
        assert_eq!(
            dump("[文档](<https://example.com/a b>)"),
            "P[A(https://example.com/a b)[T(\"文档\")]]"
        );
        // R8：[^ 1] 含空格不命中脚注，保持字面；定义
        // 本身仍被抽取（无引用命中则脚注区不呈现由渲
        // 染层口径决定，此处只断引用侧字面）。
        let d = dump("注[^ 1] 文\n\n[^1]: 出处");
        assert!(
            d.contains("[^ 1]"),
            "R8 字面保持未见于 dump：{d}"
        );
        assert!(!d.contains("Fn("), "R8 不应产生脚注引用：{d}");
    }

    #[test]
    fn r4_defs_inside_quote() {
        // R4：引用内的脚注定义被抽取、引用可命中，
        // 脚注区归文末（与顶层定义同形态）。
        assert_eq!(
            dump("> 引文[^1]\n>\n> [^1]: 出处"),
            "Q{P[T(\"引文\") Fn(fn-1,fn-1-ref-1,1)]} | Fns[FnItem(fn-1,[\"fn-1-ref-1\"]){P[T(\"出处\")]}]"
        );
        // 引用内的链接定义同样生效。
        let d = dump("> 见[文档][d]\n>\n> [d]: https://example.com");
        assert!(
            d.contains("A(https://example.com)"),
            "R4 引用内链接定义未生效：{d}"
        );
    }

    #[test]
    fn m7_footnotes_and_scripts() {
        assert_eq!(
            dump("正文带脚注[^1] 结尾\n\n[^1]: 脚注内容 **粗**"),
            "P[T(\"正文带脚注\") Fn(fn-1,fn-1-ref-1,1) T(\" 结尾\")] | Fns[FnItem(fn-1,[\"fn-1-ref-1\"]){P[T(\"脚注内容 \") B[T(\"粗\")]]}]"
        );
        assert_eq!(
            dump("公式 x^2^ 与水 H~2~O 及 ^(n+1)^ 和 ~(i)~ 形"),
            "P[T(\"公式 x\") Sup(\"2\") T(\" 与水 H\") Sub(\"2\") T(\"O 及 \") Sup(\"n+1\") T(\" 和 \") Sub(\"i\") T(\" 形\")]"
        );
        // 未引用定义：单 token 正文被 marked 链接定义吞行；
        // 含空白正文则字面回填
        assert_eq!(dump("正文无引用\n\n[^9]: 未用定义"), "P[T(\"正文无引用\")]");
        assert_eq!(
            dump("正文无引用\n\n[^9]: 未用 定义 内容"),
            "P[T(\"正文无引用\")] | P[T(\"[^9]: 未用 定义 内容\")]"
        );
    }

    #[test]
    fn m8_and_gate_parity() {
        // *** / ___ 独占段：原版门控不转（解析层虽出 HR）
        assert_eq!(gate("***"), "None");
        assert_eq!(gate("___"), "None");
        // --- 独占段两边都转
        assert_eq!(gate("---"), "Divider");
        // setext === 独占信号：原版门控不转
        assert_eq!(gate("标题文\n==="), "None");
        // 纯表格（单元格无行内信号）：原版门控不转
        assert_eq!(gate("| a | b |\n| - | - |\n| 1 | 2 |"), "None");
        // 单元格带信号的表格（审计 e08 形）两边都转
        assert_eq!(gate("| 列一 | 列二 |\n| --- | --- |\n| **粗** | `代码` |"), "Table");
        // 混排表格（前文无信号）：原版门控不转
        assert_eq!(gate("前文说明\n| a | b |\n| - | - |\n| 1 | 2 |\n后文行"), "None");
        // 硬换行/有序括号形：原版门控不转
        assert_eq!(gate("行一  \n行二"), "None");
        assert_eq!(gate("1) 第一\n2) 第二"), "None");
    }

    #[test]
    fn defs_skip_fences() {
        // D-R2：围栏内的定义形行是代码内容，不抽取。
        assert_eq!(
            dump("```\n[^1]: 不是脚注\n```"),
            "Code(-)[\"[^1]: 不是脚注\"]"
        );
        assert_eq!(
            dump("```\n[ex]: https://example.com\n```\n\n[点此][ex]"),
            "Code(-)[\"[ex]: https://example.com\"] | P[T(\"[点此][ex]\")]"
        );
        // 围栏外的定义照常抽取。
        assert_eq!(
            dump("正文[^1]\n\n[^1]: 真脚注"),
            "P[T(\"正文\") Fn(fn-1,fn-1-ref-1,1)] | Fns[FnItem(fn-1,[\"fn-1-ref-1\"]){P[T(\"真脚注\")]}]"
        );
    }

    #[test]
    fn batch3_parser_additions() {
        // C-28 引用式链接：全引用 / 折叠 / 快捷 / 引用图片；
        // 定义行不渲染；未命中定义保持字面
        assert_eq!(
            dump("[点此][ex]\n\n[ex]: https://example.com"),
            "P[A(https://example.com)[T(\"点此\")]]"
        );
        assert_eq!(
            dump("[Example][]\n\n[example]: https://example.com"),
            "P[A(https://example.com)[T(\"Example\")]]"
        );
        assert_eq!(
            dump("见 [Example] 页\n\n[example]: https://example.com"),
            "P[T(\"见 \") A(https://example.com)[T(\"Example\")] T(\" 页\")]"
        );
        assert_eq!(
            dump("![图][im]\n\n[im]: https://example.com/a.png"),
            "P[Img(https://example.com/a.png,\"图\")]"
        );
        assert_eq!(dump("[无此定义][nope]"), "P[T(\"[无此定义][nope]\")]");
        // C-28 行内原始 HTML：映射 / 剥标签留子段 /
        // DROP_CONTENT 连内容丢弃
        assert_eq!(
            dump("a <b>粗</b> <u>下划</u> <span>x</span> b"),
            "P[T(\"a \") B[T(\"粗\")] T(\" \") U[T(\"下划\")] T(\" \") T(\"x\") T(\" b\")]"
        );
        assert_eq!(
            dump("前 <script>alert(1)</script> 后"),
            "P[T(\"前 \") T(\" 后\")]"
        );
        assert_eq!(
            dump("<a href=\"https://example.com\">链</a>"),
            "P[A(https://example.com)[T(\"链\")]]"
        );
        assert_eq!(
            dump("<del>删</del> <mark>亮</mark>"),
            "P[D(\"删\") T(\" \") H(\"亮\")]"
        );
        // C-28 缩进代码块（解析层 + 分类层）
        assert_eq!(
            dump("    let a = 1;\n    let b = 2;"),
            "Code(-)[\"let a = 1;\\nlet b = 2;\"]"
        );
        assert_eq!(gate("    - 不是列表"), "Code");
        // C-21 未知 Callout 类型：标题回退类型原文；
        // 已知类型 note 仍走标题表（笔记）
        assert_eq!(
            dump("> [!FOO]\n> 正文"),
            "Callout(note,\"FOO\",None){P[T(\"正文\")]}"
        );
        assert_eq!(
            dump("> [!NOTE]\n> 正文"),
            "Callout(note,\"笔记\",None){P[T(\"正文\")]}"
        );
        // C-23 失焦 guards（分类层）：极短引用 / 未闭合
        // Callout / 空围栏均不转预览
        assert_eq!(gate("> a"), "None");
        assert_eq!(gate("> [!NOTE 未闭合"), "None");
        assert_eq!(gate("```\n```"), "None");
        // C-03 标题缺省级 = 2（渲染层经 heading_level 读
        // 取，此处以分类层无关——见探针 DOM 断言）
    }

}
