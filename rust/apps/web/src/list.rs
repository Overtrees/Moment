//! 列表页：分组/相对时间/标签/封面/行组件。
//! 口径全部对原版源码：preview.js（摘要与标签）、time.js（timeAgo）、
//! memo-list.js（分组与图片判定）、SwipeRow.js / ImageCard.js（行结构）。

use dioxus::prelude::*;
use mynote_core::Memo;

use crate::{diag, icons, i18n};

/// 摘要结果（原版 summarizeMemoDoc 的返回值）。
#[derive(Clone)]
pub(crate) struct Summary {
    pub preview: String,
    pub tags: Vec<String>,
    pub attach_count: usize,
}

fn is_tag_char(c: char) -> bool {
    c.is_alphanumeric() || c == '_' || c == '-' || ('\u{4e00}' <= c && c <= '\u{9fa5}')
}

/// 扫描文本中的 #标签（含 # 前缀），去重保序。
fn scan_tags(text: &str, tags: &mut Vec<String>) {
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '#' {
            let mut j = i + 1;
            while j < chars.len() && is_tag_char(chars[j]) {
                j += 1;
            }
            if j > i + 1 {
                let tag: String = chars[i..j].iter().collect();
                if !tags.contains(&tag) {
                    tags.push(tag);
                }
                i = j;
                continue;
            }
        }
        i += 1;
    }
}

fn strip_tag_tokens(text: &str) -> String {
    let mut out = String::new();
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '#' {
            let mut j = i + 1;
            while j < chars.len() && is_tag_char(chars[j]) {
                j += 1;
            }
            if j > i + 1 {
                i = j;
                continue;
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out.trim().to_string()
}

/// 原版 editor.md.js stripMarkdownForPreview 的逐条移植（替换顺序
/// 与原版严格一致）。旧实现只是近似（只剥少数行首标记），md 源
/// 段落（Callout/代码/列表）会在卡面露出「> [!NOTE]…」「```」原文。
/// 全部替换用手工扫描器实现（scan_replace + 各 try_* 匹配器），
/// 与原版正则逐条等价——不引入 regex 引擎（体积账：+1.4MB wasm，
/// 且其不支持预查，原版个别表达式照样要手写，如 ~x~ 下标）。
fn strip_markdown(text: &str) -> String {
    let s = scan_replace(text, try_footnote_def, |_| String::new());
    let s = scan_replace(&s, try_wiki_pipe, emit_cap);
    let s = scan_replace(&s, try_wiki, emit_cap);
    let s = scan_replace(&s, try_footnote_ref, |_| String::new());
    let s = scan_replace(&s, try_math_block, emit_cap);
    let s = scan_replace(&s, try_sup_paren, emit_cap);
    let s = scan_replace(&s, try_sup, emit_cap);
    let s = scan_replace(&s, try_sub_paren, emit_cap);
    let s = strip_single_tilde_sub(&s);
    let s = scan_replace(&s, try_highlight, emit_cap);
    let s = scan_replace(&s, try_fence, |_| " 代码块 ".to_string());
    let s = scan_replace(&s, try_code_span, emit_cap);
    let s = scan_replace(&s, try_image, emit_cap);
    let s = scan_replace(&s, try_link, emit_cap);
    let s = scan_replace(&s, try_heading, emit_cap);
    let s = scan_replace(&s, try_quote, emit_cap);
    let s = scan_replace(&s, try_bullet, emit_cap);
    let s = scan_replace(&s, try_numbered, emit_cap);
    let s = paired(&s, "**", '*');
    let s = paired(&s, "__", '_');
    let s = paired(&s, "*", '*');
    let s = paired(&s, "_", '_');
    let s = paired(&s, "~~", '~');
    let s = strip_math_inline(&s);
    let s = collapse_newlines(&s);
    let s = collapse_spaces(&s);
    s.trim().to_string()
}

/// 替换文本 = 捕获组内容（原版的 "$1"）。
fn emit_cap(cap: Option<&[char]>) -> String {
    cap.map(|c| c.iter().collect()).unwrap_or_default()
}

/// 左到右扫描替换骨架：try_match 在 char 下标 i 处尝试匹配，成功
/// 返回 (匹配总长, Option<(捕获起, 捕获止)>)（下标均相对 i）；
/// 失败则原样输出当前字符并前进 1。与正则 replace_all 的
/// 最左、非重叠语义一致。
fn scan_replace(
    s: &str,
    try_match: impl Fn(&[char], usize) -> Option<(usize, Option<(usize, usize)>)>,
    emit: impl Fn(Option<&[char]>) -> String,
) -> String {
    let chars: Vec<char> = s.chars().collect();
    let n = chars.len();
    let mut out = String::with_capacity(s.len());
    let mut i = 0usize;
    while i < n {
        match try_match(&chars, i) {
            Some((len, cap)) => {
                let slice = cap.map(|(a, b)| &chars[i + a..i + b]);
                out.push_str(&emit(slice));
                i += len.max(1);
            }
            None => {
                out.push(chars[i]);
                i += 1;
            }
        }
    }
    out
}

/// 从 j 起消费满足 pred 的字符，返回结束下标。
fn eat(chars: &[char], mut j: usize, pred: impl Fn(char) -> bool) -> usize {
    while j < chars.len() && pred(chars[j]) {
        j += 1;
    }
    j
}

/// 判定 chars[i..] 是否以 lit 开头。
fn starts(chars: &[char], i: usize, lit: &str) -> bool {
    lit.chars()
        .enumerate()
        .all(|(k, c)| chars.get(i + k) == Some(&c))
}

/// 脚注定义 ^\[\^[^\]]+\]:.*(?:\n[ \t]+.*)*$（仅行首）：整段删除。
fn try_footnote_def(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if i > 0 && chars[i - 1] != '\n' {
        return None;
    }
    if !starts(chars, i, "[^") {
        return None;
    }
    let j = eat(chars, i + 2, |c| c != ']');
    if j == i + 2 || !starts(chars, j, "]:") {
        return None;
    }
    let mut end = eat(chars, j + 2, |c| c != '\n');
    while end < chars.len()
        && chars[end] == '\n'
        && matches!(chars.get(end + 1), Some(' ' | '\t'))
    {
        let line = eat(chars, end + 1, |c| c == ' ' || c == '\t');
        end = eat(chars, line, |c| c != '\n');
    }
    Some((end - i, None))
}

/// \[\[([^\]|]+)\|([^\]]+)\]\] → $2。
fn try_wiki_pipe(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "[[") {
        return None;
    }
    let g1_end = eat(chars, i + 2, |c| c != ']' && c != '|');
    if g1_end == i + 2 || chars.get(g1_end) != Some(&'|') {
        return None;
    }
    let g2_start = g1_end + 1;
    let g2_end = eat(chars, g2_start, |c| c != ']');
    if g2_end == g2_start || !starts(chars, g2_end, "]]" ) {
        return None;
    }
    Some((g2_end + 2 - i, Some((g2_start - i, g2_end - i))))
}

/// \[\[([^\]]+)\]\] → $1。
fn try_wiki(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "[[") {
        return None;
    }
    let g_end = eat(chars, i + 2, |c| c != ']');
    if g_end == i + 2 || !starts(chars, g_end, "]]") {
        return None;
    }
    Some((g_end + 2 - i, Some((2, g_end - i))))
}

/// \[\^([^\]]+)\] → 删除。
fn try_footnote_ref(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "[^") {
        return None;
    }
    let g_end = eat(chars, i + 2, |c| c != ']');
    if g_end == i + 2 || chars.get(g_end) != Some(&']') {
        return None;
    }
    Some((g_end + 1 - i, None))
}

/// \$\$(.*?)\$\$（惰性）→ $1。
fn try_math_block(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "$$") {
        return None;
    }
    let mut k = i + 2;
    while k + 1 < chars.len() + 1 {
        if starts(chars, k, "$$") {
            return Some((k + 2 - i, Some((2, k - i))));
        }
        k += 1;
        if k >= chars.len() {
            return None;
        }
    }
    None
}

/// \^(([^()\n]+)\)\^ → $1。
fn try_sup_paren(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    paren_form(chars, i, "^(", ")^")
}

/// ~\(([^()\n]+)\)~ → $1。
fn try_sub_paren(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    paren_form(chars, i, "~(", ")~")
}

fn paren_form(
    chars: &[char],
    i: usize,
    open: &str,
    close: &str,
) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, open) {
        return None;
    }
    let body_start = i + 2;
    let body_end = eat(chars, body_start, |c| !matches!(c, '(' | ')' | '\n'));
    if body_end == body_start || !starts(chars, body_end, close) {
        return None;
    }
    Some((body_end + 2 - i, Some((2, body_end - i))))
}

/// \^([A-Za-z0-9][A-Za-z0-9,+\-]*)\^ → $1。
fn try_sup(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if chars.get(i) != Some(&'^') {
        return None;
    }
    let first = *chars.get(i + 1)?;
    if !first.is_ascii_alphanumeric() {
        return None;
    }
    let body_end = eat(chars, i + 2, |c| {
        c.is_ascii_alphanumeric() || matches!(c, ',' | '+' | '-')
    });
    if chars.get(body_end) != Some(&'^') {
        return None;
    }
    Some((body_end + 1 - i, Some((1, body_end - i))))
}

/// ==([^=]+)== → $1。
fn try_highlight(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "==") {
        return None;
    }
    let body_end = eat(chars, i + 2, |c| c != '=');
    if body_end == i + 2 || !starts(chars, body_end, "==") {
        return None;
    }
    Some((body_end + 2 - i, Some((2, body_end - i))))
}

/// ```.*?```（惰性）→ 「 代码块 」。
fn try_fence(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "```") {
        return None;
    }
    let mut k = i + 3;
    loop {
        if starts(chars, k, "```") {
            return Some((k + 3 - i, None));
        }
        if k >= chars.len() {
            return None;
        }
        k += 1;
    }
}

/// `([^`]+)` → $1。
fn try_code_span(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if chars.get(i) != Some(&'`') {
        return None;
    }
    let body_end = eat(chars, i + 1, |c| c != '`');
    if body_end == i + 1 || chars.get(body_end) != Some(&'`') {
        return None;
    }
    Some((body_end + 1 - i, Some((1, body_end - i))))
}

/// !\[([^\]]*)\]\(([^\)]+)\) → $1。
fn try_image(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if !starts(chars, i, "![") {
        return None;
    }
    let alt_end = eat(chars, i + 2, |c| c != ']');
    if !starts(chars, alt_end, "](") {
        return None;
    }
    let url_end = eat(chars, alt_end + 2, |c| c != ')');
    if url_end == alt_end + 2 || chars.get(url_end) != Some(&')') {
        return None;
    }
    Some((url_end + 1 - i, Some((2, alt_end - i))))
}

/// \[([^\]]+)\]\(([^\)]+)\) → $1。
fn try_link(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    if chars.get(i) != Some(&'[') {
        return None;
    }
    let text_end = eat(chars, i + 1, |c| c != ']');
    if text_end == i + 1 || !starts(chars, text_end, "](") {
        return None;
    }
    let url_end = eat(chars, text_end + 2, |c| c != ')');
    if url_end == text_end + 2 || chars.get(url_end) != Some(&')') {
        return None;
    }
    Some((url_end + 1 - i, Some((1, text_end - i))))
}

/// 行首锚点：返回 (锚点长度, 正文起始)。锚点本身即原版的 $1
///（起始处为空、行间为那个 \n，替换时原样保留）。
fn line_anchor(chars: &[char], i: usize) -> Option<(usize, usize)> {
    if i == 0 {
        Some((0, 0))
    } else if chars[i] == '\n' {
        Some((1, i + 1))
    } else {
        None
    }
}

/// (^|\n)#{1,6}\s+ → $1。
fn try_heading(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    let (alen, body) = line_anchor(chars, i)?;
    let hashes = eat(chars, body, |c| c == '#') - body;
    if hashes == 0 || hashes > 6 {
        return None;
    }
    let after = eat(chars, body + hashes, |c| c.is_whitespace());
    if after == body + hashes {
        return None;
    }
    Some((after - i, Some((0, alen))))
}

/// (^|\n)>\s? → $1。
fn try_quote(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    let (alen, body) = line_anchor(chars, i)?;
    if chars.get(body) != Some(&'>') {
        return None;
    }
    let mut end = body + 1;
    if chars.get(end).is_some_and(|c| c.is_whitespace()) {
        end += 1;
    }
    Some((end - i, Some((0, alen))))
}

/// (^|\n)[-*+]\s+ → $1。
fn try_bullet(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    let (alen, body) = line_anchor(chars, i)?;
    if !matches!(chars.get(body), Some('-' | '*' | '+')) {
        return None;
    }
    let after = eat(chars, body + 1, |c| c.is_whitespace());
    if after == body + 1 {
        return None;
    }
    Some((after - i, Some((0, alen))))
}

/// (^|\n)\d+\.\s+ → $1。
fn try_numbered(chars: &[char], i: usize) -> Option<(usize, Option<(usize, usize)>)> {
    let (alen, body) = line_anchor(chars, i)?;
    let digits = eat(chars, body, |c| c.is_ascii_digit()) - body;
    if digits == 0 || chars.get(body + digits) != Some(&'.') {
        return None;
    }
    let after = eat(chars, body + digits + 1, |c| c.is_whitespace());
    if after == body + digits + 1 {
        return None;
    }
    Some((after - i, Some((0, alen))))
}

/// 成对定界符替换：delim + (非 excl 字符 ≥1) + delim → 内容。
/// 覆盖 \*\*([^*]+)\*\*、__([^_]+)__、\*([^*]+)\*、_([^_]+)_、
/// ~~([^~]+)~~ 五条原版规则。
fn paired(s: &str, delim: &str, excl: char) -> String {
    let dlen = delim.chars().count();
    scan_replace(
        s,
        move |chars, i| {
            if !starts(chars, i, delim) {
                return None;
            }
            let body_end = eat(chars, i + dlen, |c| c != excl);
            if body_end == i + dlen || !starts(chars, body_end, delim) {
                return None;
            }
            Some((body_end + dlen - i, Some((dlen, body_end - i))))
        },
        emit_cap,
    )
}

/// $…$ 行内公式：原版带回调（未转义且像公式才剥 $），逐匹配重建。
fn strip_math_inline(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let n = chars.len();
    let mut out = String::with_capacity(s.len());
    let mut i = 0usize;
    while i < n {
        if chars[i] == '$' {
            let body_end = eat(&chars, i + 1, |c| c != '$' && c != '\n');
            if body_end > i + 1 && chars.get(body_end) == Some(&'$') {
                let inner: String = chars[i + 1..body_end].iter().collect();
                let escaped = {
                    let mut count = 0usize;
                    let mut k = i;
                    while k > 0 && chars[k - 1] == '\\' {
                        count += 1;
                        k -= 1;
                    }
                    count % 2 == 1
                };
                if !escaped && looks_like_math(&inner) {
                    out.push_str(&inner);
                } else {
                    out.extend(&chars[i..=body_end]);
                }
                i = body_end + 1;
                continue;
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

/// \n+ → 单个空格。
fn collapse_newlines(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_run = false;
    for c in s.chars() {
        if c == '\n' {
            if !in_run {
                out.push(' ');
                in_run = true;
            }
        } else {
            in_run = false;
            out.push(c);
        }
    }
    out
}

/// \s+ → 单个空格。
fn collapse_spaces(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_run = false;
    for c in s.chars() {
        if c.is_whitespace() {
            if !in_run {
                out.push(' ');
                in_run = true;
            }
        } else {
            in_run = false;
            out.push(c);
        }
    }
    out
}

/// 原版 isEscapedAt：index 前连续反斜杠为奇数个即已转义。
fn is_escaped_at(text: &str, byte_idx: usize) -> bool {
    text[..byte_idx]
        .chars()
        .rev()
        .take_while(|&c| c == '\\')
        .count()
        % 2
        == 1
}

/// 原版 looksLikeMathExpression 的移植。
fn looks_like_math(expr: &str) -> bool {
    let v = expr.trim();
    if v.is_empty() {
        return false;
    }
    let mut chs = v.chars();
    if let (Some(c), None) = (chs.next(), chs.clone().next()) {
        if c.is_ascii_alphabetic() {
            return true;
        }
    }
    let bytes: Vec<char> = v.chars().collect();
    for (i, &c) in bytes.iter().enumerate() {
        if c == '\\' && bytes.get(i + 1).is_some_and(|n| n.is_ascii_alphabetic()) {
            return true;
        }
        if c.is_ascii_digit()
            || matches!(c, '=' | '+' | '-' | '*' | '/' | '^' | '_' | '{' | '}' | '<' | '>')
            || ('\u{03b1}'..='\u{03c9}').contains(&c)
            || ('\u{0391}'..='\u{03a9}').contains(&c)
        {
            return true;
        }
    }
    false
}

/// 原版 /(^|[^~])~([A-Za-z0-9][A-Za-z0-9,+-]*)~(?!~)/ 的手工等价
/// （Rust regex 不支持负向先行断言）：~x~ 下标语法剥除波浪线，
/// 但结尾 ~ 后紧跟另一个 ~ 时不匹配。
fn strip_single_tilde_sub(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let n = chars.len();
    let body_char = |c: char| c.is_ascii_alphanumeric() || matches!(c, ',' | '+' | '-');
    let mut out: Vec<char> = Vec::with_capacity(n);
    let mut pos = 0usize;
    while pos < n {
        let prefix_len = if pos == 0 {
            Some(0)
        } else if chars[pos] != '~' {
            Some(1)
        } else {
            None
        };
        let matched = prefix_len.and_then(|pl| {
            let mut j = pos + pl;
            if j >= n || chars[j] != '~' {
                return None;
            }
            j += 1;
            if j >= n || !chars[j].is_ascii_alphanumeric() {
                return None;
            }
            let start = j;
            while j < n && body_char(chars[j]) {
                j += 1;
            }
            if j >= n || chars[j] != '~' {
                return None;
            }
            if j + 1 < n && chars[j + 1] == '~' {
                return None;
            }
            Some((pl, start, j))
        });
        match matched {
            Some((pl, start, end)) => {
                out.extend_from_slice(&chars[pos..pos + pl]);
                out.extend_from_slice(&chars[start..end]);
                pos = end + 1;
            }
            None => {
                out.push(chars[pos]);
                pos += 1;
            }
        }
    }
    out.into_iter().collect()
}

thread_local! {
    static SUMMARY_CACHE: std::cell::RefCell<std::collections::HashMap<String, Summary>> =
        std::cell::RefCell::new(std::collections::HashMap::new());
}

/// 摘要缓存（与 search_text 同口径的 (id, updatedAt) 键）：strip_markdown
/// 是约 25 趟全文本扫描，列表重渲染时逐行重算纯属浪费；键带当前语言
/// （空摘要回退文案随语言变）与 max_len（图片卡 60 / 文本卡 80）。
pub(crate) fn summarize(memo: &Memo, max_len: usize) -> Summary {
    let key = format!(
        "{}|{}|{}|{}",
        memo.id,
        memo.updated_at.to_millis().unwrap_or(0),
        max_len,
        i18n::current()
    );
    if let Some(hit) = SUMMARY_CACHE.with(|c| c.borrow().get(&key).cloned()) {
        return hit;
    }
    let sum = summarize_uncached(memo, max_len);
    SUMMARY_CACHE.with(|c| {
        let mut map = c.borrow_mut();
        if map.len() > 1024 {
            map.clear();
        }
        map.insert(key, sum.clone());
    });
    sum
}

/// 原版 preview.js summarizeMemoDoc：只看段落块首个子节点的文本。
fn summarize_uncached(memo: &Memo, max_len: usize) -> Summary {
    let mut paras: Vec<String> = Vec::new();
    let mut tags: Vec<String> = Vec::new();
    let mut attach_count = 0usize;
    for node in &memo.doc {
        match node.node_type.as_deref() {
            Some("paragraph") => {
                if let Some(first) = node.children.as_ref().and_then(|c| c.first()) {
                    let text = first.text.clone().unwrap_or_default();
                    let text = text.trim();
                    if !text.is_empty() {
                        scan_tags(text, &mut tags);
                        paras.push(text.to_string());
                    }
                }
            }
            Some("attachment") => attach_count += 1,
            _ => {}
        }
    }
    if paras.is_empty() {
        return Summary {
            preview: i18n::t("list.no_more_text"),
            tags: Vec::new(),
            attach_count,
        };
    }
    let tags: Vec<String> = tags.into_iter().take(3).collect();
    let joined = paras.join(" ");
    let stripped = strip_tag_tokens(&strip_markdown(&joined));
    let cut: String = stripped.chars().take(max_len).collect();
    let preview = if !cut.is_empty() {
        cut
    } else if let Some(first) = tags.first() {
        first.trim_start_matches('#').to_string()
    } else {
        i18n::t("list.no_more_text")
    };
    Summary { preview, tags, attach_count }
}

/// 分组（原版 groupedItems）：置顶组在前，其余按
/// createdAt||updatedAt 的日期标签分桶；组内图片在前。
#[derive(PartialEq)]
pub(crate) struct MemoGroup {
    pub label: String,
    pub images: Vec<Memo>,
    pub texts: Vec<Memo>,
}

/// 原版 hasImageAttachment：含 image/gallery/imgTextCard/
/// imageTextRow 块，或 attachment 块且 image 为真。
/// 2026-11-24 封面统一派生并入：再 ∪ cover_source 命中——增量
/// 仅 attachment 图片文件一类（image 标志为假、但 manifest
/// 类型/扩展名判为图片，即经「添加附件」选入的照片；与编辑
/// 器内 att_file_is_image 图片页扩围同判据），使样式门与封面
/// 派生同源：凡派生得出封面的备忘必为图文卡。
pub(crate) fn has_image(memo: &Memo, manifest_raw: &str) -> bool {
    memo.doc.iter().any(|n| match n.node_type.as_deref() {
        Some("image") | Some("gallery") | Some("imgTextCard") | Some("imageTextRow") => true,
        Some("attachment") => n.image.unwrap_or(false),
        _ => false,
    }) || cover_source(memo, manifest_raw).is_some()
}

/// 天数（days-from-civil，纯算术避免时区库）。
fn day_num(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn local_ymd(ms: i64) -> (i64, i64, i64) {
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_f64(ms as f64));
    (
        d.get_full_year() as i64,
        d.get_month() as i64 + 1,
        d.get_date() as i64,
    )
}

thread_local! {
    static TODAY_CACHE: std::cell::Cell<Option<(i64, i64, i64)>> =
        std::cell::Cell::new(None);
}

/// 今日 (day_num, 年)：按分钟分桶缓存——旧实现每行/每备忘都新建
/// 多个 JS Date 对象重算今日，列表一渲染就是数百次跨界调用；
/// 分桶键取 Date::now() 本身，跨分钟自动失效，标签口径不变。
fn today_info() -> (i64, i64) {
    let bucket = (js_sys::Date::now() / 60_000.0) as i64;
    TODAY_CACHE.with(|c| {
        if let Some((b, day, year)) = c.get() {
            if b == bucket {
                return (day, year);
            }
        }
        let (y, m, d) = local_ymd(js_sys::Date::now() as i64);
        let day = day_num(y, m, d);
        c.set(Some((bucket, day, y)));
        (day, y)
    })
}

fn today_day() -> i64 {
    today_info().0
}

/// 原版 getSectionLabel（日期边界与原版一致）。
fn section_label(ms: i64) -> String {
    let (y, m, dd) = local_ymd(ms);
    // today_info 返回 (day_num, year)：年比较必须取第二分量
    // （W-2：此前误取 day_num，y == ty 永假，同年旧月份全落
    // 「YYYY年」分支、月份粒度丢失；time_ago 取分量本来就对）
    let (_, ty) = today_info();
    let diff = today_day() - day_num(y, m, dd);
    if diff <= 0 {
        i18n::t("group.today")
    } else if diff == 1 {
        i18n::t("group.yesterday")
    } else if diff <= 7 {
        i18n::t("group.week")
    } else if diff <= 30 {
        i18n::t("group.month")
    } else if y == ty {
        i18n::tf("group.month_of_year", &[("m", &m.to_string())])
    } else {
        i18n::tf("group.year", &[("y", &y.to_string())])
    }
}

/// 原版 matchesMemoSearch 的近似：标题 + doc 内文本类字段
/// （text/title/subtitle/source/name/label/alt/description/content
/// 与非 data: 的 url）拼接后子串匹配（小写）。
/// 性能：搜索文本按 (id, updatedAt) 缓存——旧实现每次按键都把
/// 全部备忘的 doc 序列化成 Value 再遍历，300 条备忘实测搜索
/// 600ms；缓存后每键只需在已拼好的小写文本里做子串匹配。
pub(crate) fn matches_search(memo: &Memo, q: &str) -> bool {
    if q.is_empty() {
        return true;
    }
    // 搜索动作留痕（同一查询词只记一次，避免逐键刷屏）
    diag::log_once(&format!("search:{q}"), "APP", &format!("search '{q}'"));
    let q = q.to_lowercase();
    search_text(memo).contains(&q)
}

thread_local! {
    static SEARCH_CACHE: std::cell::RefCell<std::collections::HashMap<String, String>> =
        std::cell::RefCell::new(std::collections::HashMap::new());
}

fn search_text(memo: &Memo) -> String {
    let key = format!(
        "{}|{}|{}",
        memo.id,
        memo.updated_at.to_millis().unwrap_or(0),
        memo.title.as_deref().unwrap_or("")
    );
    if let Some(hit) = SEARCH_CACHE.with(|c| c.borrow().get(&key).cloned()) {
        return hit;
    }
    let mut fields: Vec<String> = vec![memo.title.clone().unwrap_or_default()];
    fn walk_value(v: &serde_json::Value, out: &mut Vec<String>) {
        match v {
            serde_json::Value::String(_) => {}
            serde_json::Value::Array(arr) => arr.iter().for_each(|x| walk_value(x, out)),
            serde_json::Value::Object(map) => {
                for (k, val) in map {
                    let kl = k.to_lowercase();
                    if matches!(
                        kl.as_str(),
                        "id" | "fileid" | "dataurl" | "blob" | "thumb" | "imagedata"
                    ) {
                        continue;
                    }
                    if let serde_json::Value::String(s) = val {
                        if matches!(
                            kl.as_str(),
                            "text" | "title" | "subtitle" | "source" | "name" | "label"
                                | "alt" | "description" | "content"
                        ) || (kl == "url" && !s.to_lowercase().starts_with("data:"))
                        {
                            out.push(s.clone());
                        }
                    } else {
                        walk_value(val, out);
                    }
                }
            }
            _ => {}
        }
    }
    fn walk_node(n: &mynote_core::Node, out: &mut Vec<String>) {
        if let Some(t) = &n.text {
            out.push(t.clone());
        }
        // §2.2 类型化前的 extra 遍历等价面：walk_value 只收
        // 对象内白名单键下的字符串——attrs 里命中的只有
        // text、url（非 data:）与 items 条目的 url；meta 仍
        // 是 Value、整值走 walk_value；其余顶层字段在旧口
        // 径下是裸字符串/标量，walk_value 本就不收。
        if let Some(t) = &n.attrs.text {
            out.push(t.clone());
        }
        if let Some(u) = &n.attrs.url {
            if !u.to_lowercase().starts_with("data:") {
                out.push(u.clone());
            }
        }
        if let Some(items) = &n.attrs.items {
            for it in items {
                if let Some(u) = &it.url {
                    if !u.to_lowercase().starts_with("data:") {
                        out.push(u.clone());
                    }
                }
            }
        }
        if let Some(meta) = &n.meta {
            walk_value(meta, out);
        }
        if let Some(kids) = &n.children {
            for k in kids {
                walk_node(k, out);
            }
        }
    }
    for n in &memo.doc {
        walk_node(n, &mut fields);
    }
    let text = fields.join(" ").to_lowercase();
    SEARCH_CACHE.with(|c| {
        let mut map = c.borrow_mut();
        if map.len() > 512 {
            map.clear();
        }
        map.insert(key, text.clone());
    });
    text
}

pub(crate) fn build_groups(memos: &[&Memo], manifest_raw: &str) -> Vec<MemoGroup> {
    let mut pinned = MemoGroup {
        label: i18n::t("group.pinned"),
        images: Vec::new(),
        texts: Vec::new(),
    };
    let mut groups: Vec<MemoGroup> = Vec::new();
    for m in memos {
        let m = *m;
        let is_img = has_image(m, manifest_raw);
        if m.pinned.unwrap_or(false) {
            if is_img { pinned.images.push(m.clone()) } else { pinned.texts.push(m.clone()) }
            continue;
        }
        let created = m.created_at.to_millis().unwrap_or(0);
        let stamp = if created > 0 { created } else { m.updated_at.to_millis().unwrap_or(0) };
        let label = section_label(stamp);
        // 按标签归并而非连续成组：入参按 updatedAt 排序、标签按
        // createdAt 派生，任一备忘被编辑过，两序分叉即可让同一
        // 标签在序列中复现（如 过去7天…过去30天…过去7天）。连续
        // 成组会产出同标签的两个分组，而列表以标签为键控 key
        // （g-{label}）——兄弟键重复违反 Dioxus 键控 diff 的键
        // 唯一不变量，diff 损坏 mount 表后 panic（invalid key，
        // 2026-11-24 真机定因）。归并后每标签至多一组、键唯一
        // 由构造保证；标签单调时输出与连续成组逐项一致。
        let gi = match groups.iter().position(|g| g.label == label) {
            Some(i) => i,
            None => {
                groups.push(MemoGroup { label, images: Vec::new(), texts: Vec::new() });
                groups.len() - 1
            }
        };
        let g = &mut groups[gi];
        if is_img { g.images.push(m.clone()) } else { g.texts.push(m.clone()) }
    }
    let mut out = Vec::new();
    if !pinned.images.is_empty() || !pinned.texts.is_empty() {
        out.push(pinned);
    }
    out.extend(groups);
    out
}

/// 原版 time.js is24hFormat：Intl formatToParts 无 dayPeriod
/// 即 24 小时制（结果缓存，进程内只探一次）。
pub(crate) fn is_24h() -> bool {
    use std::sync::OnceLock;
    static CACHE: OnceLock<bool> = OnceLock::new();
    *CACHE.get_or_init(|| {
        js_sys::eval("(()=>{try{return !new Intl.DateTimeFormat(undefined,{hour:'numeric'}).formatToParts(new Date(2024,0,1,13)).some(function(p){return p.type==='dayPeriod'})}catch(e){return false}})()")
            .ok()
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
    })
}

/// 原版 time.js timeAgo：今天→（24h 时 HH:MM，时分均补零，
/// time.js:23；否则上午/下午 h:MM）；昨天→昨天；同年 M/D；
/// 否则 Y/M/D。
pub(crate) fn time_ago(ts: &mynote_core::model::Timestamp) -> String {
    let Some(ms) = ts.to_millis() else {
        return i18n::t("list.now");
    };
    if ms <= 0 {
        return i18n::t("list.now");
    }
    let (y, m, d) = local_ymd(ms);
    let diff = today_day() - day_num(y, m, d);
    if diff <= 0 {
        let date = js_sys::Date::new(&wasm_bindgen::JsValue::from_f64(ms as f64));
        let h = date.get_hours();
        let min = date.get_minutes();
        if is_24h() {
            return format!("{h:02}:{min:02}");
        }
        let (ampm, h12) = if h < 12 {
            (i18n::t("time.am"), h % 12)
        } else {
            (i18n::t("time.pm"), h % 12)
        };
        let h12 = if h12 == 0 { 12 } else { h12 };
        format!("{ampm} {h12}:{min:02}")
    } else if diff == 1 {
        i18n::t("group.yesterday")
    } else {
        let (_, ty) = today_info();
        if y == ty {
            format!("{m}/{d}")
        } else {
            format!("{y}/{m}/{d}")
        }
    }
}

/// 封面来源（2026-11-24 用户定案的统一派生，supersede 原版
/// ImageCard「只认第一个 attachment 块」口径——该口径与样式
/// 门 hasImageAttachment 认五种块形分裂，图只存在于 image/
/// gallery/图文卡块中的备忘恒空封面，见 diagnose_list_cover.md）：
/// 封面 = 备忘内**按文档序最靠前的那张自有图**，渲染时按现行
/// doc 动态派生、不落库——删除/新增/换序自动跟随（删首图顺
/// 位次图、拖拽换序跟随新首图）。
/// File = IDB 附件 id（CoverImg 取字节出图）；Url = 已过
/// safe_image_url 的直链（与编辑器内 URL 图同口径、直出 img）。
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum CoverSource {
    File(String),
    Url(String),
}

/// 文档序 = doc 块序深度优先（节点自身先于其 children；双栏
/// layout 下按数据序而非视觉栏序——layout 只是分界点、doc 本
/// 身一份有序表）。逐块候选（命中即停、派生廉价）：
/// - image：fileId（blocks::file_id 双位读）→ File；否则 url
///   过白名单非空 → Url；皆无（空占位块）不算图、继续后找。
/// - gallery：items 序首个可用项（File 恒可用；Url 须过白
///   名单——被拦项在编辑器内亦是空 src，不作封面、看下一项）。
/// - imgTextCard / imageTextRow：fileId → File。
/// - attachment：fileId 且（image 标志为真，或 att_file_is_
///   image_raw 判为图片类文件——manifest 类型优先、文件名扩
///   展名兜底，与编辑器图片页扩围同一判据）→ File。非图附件
///   （PDF 等）跳过、继续后找。
/// 不纳入：musicCard / link-card 的 meta.cover（外部站点封面
/// 图、非备忘自有图，且 has_image 样式门同样不认）；video
/// （非静态图）；MD 段内嵌图（段落按文本卡呈现、样式门不
/// 认，且其图为外链文本的一部分、非块级自有图）。
pub(crate) fn cover_source(memo: &Memo, manifest_raw: &str) -> Option<CoverSource> {
    memo.doc.iter().find_map(|n| cover_in_node(n, manifest_raw))
}

fn cover_in_node(node: &mynote_core::Node, manifest_raw: &str) -> Option<CoverSource> {
    let hit = match node.node_type.as_deref() {
        Some("image") => {
            if let Some(fid) = crate::blocks::file_id(node) {
                Some(CoverSource::File(fid))
            } else {
                node.url
                    .as_deref()
                    .map(mynote_core::safe_image_url)
                    .filter(|s| !s.is_empty())
                    .map(CoverSource::Url)
            }
        }
        Some("gallery") => crate::blocks::gallery_items(node)
            .into_iter()
            .find_map(|item| match item {
                crate::blocks::GalleryItem::File(fid) => Some(CoverSource::File(fid)),
                crate::blocks::GalleryItem::Url(u) => {
                    let s = mynote_core::safe_image_url(&u);
                    if s.is_empty() {
                        None
                    } else {
                        Some(CoverSource::Url(s))
                    }
                }
            }),
        Some("imgTextCard") | Some("imageTextRow") => {
            crate::blocks::file_id(node).map(CoverSource::File)
        }
        Some("attachment") => crate::blocks::file_id(node).and_then(|fid| {
            let is_inline_image = node.image.unwrap_or(false);
            if is_inline_image {
                return Some(CoverSource::File(fid));
            }
            let name = crate::blocks::att_name_in_manifest(manifest_raw, &fid)
                .or_else(|| node.name.clone())
                .unwrap_or_default();
            if crate::blocks::att_file_is_image_raw(manifest_raw, &fid, &name) {
                Some(CoverSource::File(fid))
            } else {
                None
            }
        }),
        _ => None,
    };
    if hit.is_some() {
        return hit;
    }
    node.children
        .as_ref()?
        .iter()
        .find_map(|k| cover_in_node(k, manifest_raw))
}

/// 待删标记（批 12 U3 软删）：备忘 deletedAt 字段 =
/// 删除时刻（毫秒）。标记在 = 处于撤销窗口内：列表分组、
/// 搜索、深链、Wiki 命中与备份导出等一切消费面都排除该
/// 篇；窗口（main.rs UNDO_WINDOW_MS）超时由到期任务真删。
/// 标记随备忘落盘持久化——窗口内杀进程重开，标记仍在、
/// 待删项不丢（启动侧再水化见 main.rs 加载效应）。
pub(crate) fn pending_deleted_at(memo: &Memo) -> Option<i64> {
    memo.deleted_at
}

pub(crate) fn is_pending_deleted(memo: &Memo) -> bool {
    pending_deleted_at(memo).is_some()
}

pub(crate) fn ptr_xy(e: &Event<PointerData>) -> (f64, f64) {
    let p = e.data.client_coordinates();
    (p.x, p.y)
}

/// 原版卡片键盘口径：Enter / Space 为打开键（ImageCard.js /
/// SwipeRow.js 的 onKeyDown 同款判定）。
fn is_open_key(e: &Event<KeyboardData>) -> bool {
    match e.key() {
        Key::Enter => true,
        Key::Character(ref c) => c == " ",
        _ => false,
    }
}

/// manifest 原文 → 某附件登记的 MIME 类型（编辑器入仓三处与
/// 导入路径都把 {name, type} 写进 attachments[id]，与原版
/// files 记录的 stored.type 同位）。
fn manifest_att_type(manifest_raw: &str, fid: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(manifest_raw).ok()?;
    v.get("attachments")?
        .get(fid)?
        .get("type")?
        .as_str()
        .map(|s| s.to_string())
}

/// setTimeout 延时（封面重试节拍用，与原版 300ms 同值）。
async fn sleep_ms(ms: i32) {
    let promise = js_sys::Promise::new(&mut |resolve, _| {
        if let Some(w) = web_sys::window() {
            let _ = w.set_timeout_with_callback_and_timeout_and_arguments_0(&resolve, ms);
        }
    });
    let _ = wasm_bindgen_futures::JsFuture::from(promise).await;
}

/// 封面图（D-21 基线，2026-11-24 随统一派生修订）：候选由
/// cover_source 派生时已定性（块形即图、或附件经 manifest
/// 类型/扩展名判为图片类文件），本组件只负责取图——manifest
/// 登记 type 明确非图片即停（数据冲突时的最后闸门）；字节在
/// 库即出图（与编辑器 BlobMedia 取数对齐：此前 type 未登记
/// 时恒重试至空白，与编辑页同附件可见性分裂）；type 登记为
/// 图时按登记 type 建 Blob（SVG 等格式在 <img> 中拿到正确
/// MIME 才能解码），未登记时无类型建 Blob 靠浏览器嗅探解码
/// （PNG/JPEG/GIF/WebP 均可嗅探）；type 已知为图而字节未到
/// （导入/入仓在途）时按原版 5 次 × 300ms 重试，两侧皆无
/// （附件不存在）即停、渲染空封面占位（.img-cover 无图态）。
#[component]
pub(crate) fn CoverImg(file_id: String, gen: Signal<u32>, manifest: Signal<String>) -> Element {
    let mut url = use_signal(|| Option::<String>::None);
    use_effect(move || {
        let fid = file_id.clone();
        spawn(async move {
            for attempt in 0..5 {
                let raw = manifest.read().clone();
                let ty = manifest_att_type(&raw, &fid);
                let bytes = crate::idb::get_attachment(&fid).await;
                match (ty.as_deref(), bytes) {
                    (Some(t), _) if !t.starts_with("image/") => break,
                    (_, Some(b)) => {
                        let u = match ty.as_deref() {
                            Some(t) => crate::idb::blob_url_typed(&b, t),
                            None => crate::idb::blob_url(&b),
                        };
                        if let Some(u) = u {
                            url.set(Some(u));
                        }
                        break;
                    }
                    (None, None) => break,
                    _ => {
                        if attempt < 4 {
                            sleep_ms(300).await;
                        }
                    }
                }
            }
        });
    });
    let _ = gen.read();
    rsx! {
        if let Some(u) = url.read().as_ref() {
            // draggable=false：封面为真实 IMG 后，鼠标按下拖动会触发
            // 浏览器原生图片拖拽（dragstart+pointercancel）劫持行左滑
            // 手势；禁原生拖拽使指针事件完整归行手势（probe_root_dim ③ 锁）。
            img { class: "img-cover", src: "{u}", alt: "", draggable: "false" }
        } else {
            div { class: "img-cover" }
        }
    }
}

/// 标签 chips（原版 .glass-tag.item-tag：10px/18px 行高，
/// 全部渲染，>2 时多一个 +N，与原版一致）。
#[component]
fn TagList(tags: Vec<String>) -> Element {
    if tags.is_empty() {
        return rsx! {};
    }
    rsx! {
        div { class: "item-tag-list",
            for (i, tag) in tags.iter().enumerate() {
                span {
                    class: "glass-tag item-tag",
                    // W-1：原版每标签带 data-tag-index，宽屏
                    // CSS 据此只露前 2 个（base.css 宽屏块规
                    // 则），其余归 +N；缺此属性隐藏永不命中、
                    // 第 3 个与 +N 重复计数。
                    "data-tag-index": "{i}",
                    key: "{tag}-{i}",
                    style: "font-size:var(--font-10);padding:0 5px;border-radius:var(--radius-999);line-height:18px;white-space:nowrap;",
                    "{tag}"
                }
            }
            if tags.len() > 2 {
                span {
                    class: "glass-tag item-tag item-tag-more",
                    style: "font-size:var(--font-10);padding:0 5px;border-radius:var(--radius-999);line-height:18px;white-space:nowrap;",
                    "+{tags.len() - 2}"
                }
            }
        }
    }
}

/// 一行笔记（原版 SwipeRow / ImageCard 的合一实现）：
/// .swipe-wrapper > .swipe-actions（进度揭示） + .list-item / .img-card。
#[component]
pub(crate) fn MemoRow(
    memo: Memo,
    expand_text: Option<String>,
    on_open: EventHandler<String>,
    on_pin: EventHandler<String>,
    on_delete: EventHandler<String>,
    on_expand: EventHandler<()>,
    gen: Signal<u32>,
    manifest: Signal<String>,
) -> Element {
    let mid = memo.id.to_string();
    let pinned = memo.pinned.unwrap_or(false);
    let manifest_raw = manifest.read().clone();
    let is_image_card = has_image(&memo, &manifest_raw);
    let cover = cover_source(&memo, &manifest_raw);
    let cover_el = match &cover {
        Some(CoverSource::File(fid)) => rsx! {
            CoverImg { file_id: fid.clone(), gen, manifest }
        },
        Some(CoverSource::Url(u)) => rsx! {
            img { class: "img-cover", src: "{u}", alt: "", draggable: "false" }
        },
        None => rsx! {
            div { class: "img-cover" }
        },
    };
    let summary = summarize(&memo, if is_image_card { 60 } else { 80 });
    let ago = time_ago(&memo.updated_at);
    let title_text = memo
        .title
        .clone()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| i18n::t("list.untitled"));

    let mut off = use_signal(|| 0i32);
    let mut drag = use_signal(|| Option::<(f64, f64, i32, bool)>::None);
    let mut moved = use_signal(|| false);
    let offset = *off.read();
    let p = (offset.unsigned_abs() as f64 / 168.0).min(1.0);
    let pin_p = ((p - 0.35) / 0.65).clamp(0.0, 1.0);
    let del_p = (p / 0.55).clamp(0.0, 1.0);
    let dragging = drag.read().is_some();
    let pe = if offset == -168 { "auto" } else { "none" };
    let trans = if dragging {
        "none"
    } else {
        "transform 0.22s cubic-bezier(0.25,0.46,0.45,0.94)"
    };

    rsx! {
        div { class: "swipe-wrapper",
            div { class: "swipe-actions",
                button {
                    class: "swipe-action-btn act-pin",
                    style: "transform:translateX({(1.0 - pin_p) * 60.0}px);opacity:{pin_p};pointer-events:{pe};",
                    onclick: {
                        let mid = mid.clone();
                        move |_| {
                            off.set(0);
                            diag::log("APP", &format!("row pin tap {mid}"));
                            on_pin.call(mid.clone());
                        }
                    },
                    { icons::Icon(icons::IconProps { name: "pin".to_string(), size: 17, stroke_width: "2.2".to_string(), stroke: "var(--color-white)".to_string() }) }
                    span { if pinned { "{i18n::t(\"action.unpin\")}" } else { "{i18n::t(\"action.pin\")}" } }
                }
                button {
                    class: "swipe-action-btn act-del",
                    style: "transform:translateX({(1.0 - del_p) * 30.0}px);opacity:{del_p};pointer-events:{pe};",
                    onclick: {
                        let mid = mid.clone();
                        move |_| {
                            off.set(0);
                            diag::log("APP", &format!("row delete tap {mid}"));
                            on_delete.call(mid.clone());
                        }
                    },
                    { icons::Icon(icons::IconProps { name: "del".to_string(), size: 17, stroke_width: "2.2".to_string(), stroke: "var(--color-white)".to_string() }) }
                    span { "{i18n::t(\"action.delete\")}" }
                }
            }
            if is_image_card {
                div {
                    class: "img-card",
                    // D-21：原版 ImageCard 键盘可达性逐值——
                    // role=group、tabIndex=0、aria-label 硬编码
                    // 中文与原版一致（blocks.rs 既有 aria 先例）。
                    role: "group",
                    tabindex: 0,
                    "aria-label": "{title_text}，图片笔记，按回车或空格打开",
                    style: "transform:translateX({offset}px);transition:{trans};touch-action:pan-y;",
                    onkeydown: {
                        let mid = mid.clone();
                        move |e: Event<KeyboardData>| {
                            if !is_open_key(&e) { return; }
                            e.prevent_default();
                            // 原版 onKeyDown：左滑开启态下无操作，
                            // 未开启才打开（与文本卡的开启态收起
                            // 不同，原版两组件本就如此）。
                            if *off.read() == 0 && !*moved.read() {
                                diag::log("APP", &format!("row open key {mid}"));
                                on_open.call(mid.clone());
                            }
                        }
                    },
                    onpointerdown: move |e: Event<PointerData>| {
                        let (x, y) = ptr_xy(&e);
                        drag.set(Some((x, y, *off.read(), false)));
                    },
                    onpointermove: move |e: Event<PointerData>| {
                        let drag_cur = *drag.read();
                        if let Some((sx, sy, base, engaged)) = drag_cur {
                            let (x, y) = ptr_xy(&e);
                            let dx = x - sx;
                            let dy = y - sy;
                            let mut eng = engaged;
                            if !eng && dy.abs() > dx.abs() + 8.0 {
                                drag.set(None);
                                off.set(0);
                                return;
                            }
                            if !eng && dx.abs() > 5.0 { eng = true; }
                            if eng {
                                if dx.abs() > 8.0 { moved.set(true); }
                                off.set((base + dx as i32).clamp(-168, 0));
                                drag.set(Some((sx, sy, base, true)));
                            }
                        }
                    },
                    onpointerup: move |_| {
                        if drag.read().is_some() {
                            let cur = *off.read();
                            off.set(if cur < -55 { -168 } else { 0 });
                            drag.set(None);
                        }
                    },
                    onpointercancel: move |_| {
                        drag.set(None);
                        off.set(0);
                    },
                    onclick: {
                        let mid = mid.clone();
                        move |_| {
                            // 原版 ImageCard 点按：左滑开启态下无
                            // 操作——不收起、不打开（与上方键盘路
                            // 径同口径；文本卡开启态点按收起是
                            // SwipeRow 的另一口径，不在此列）。
                            // 开启态判定读信号现值不用渲染快照：
                            // 手势尾随的 click 可能赶在手势写信号
                            // 后的重渲染之前派发，快照滞后会误判
                            // 未开启、走下方 moved 吞掉路径而漏记
                            // 本行（原版同理读 gesture ref 现值）。
                            if *off.read() != 0 {
                                diag::log("APP", &format!("row open-state tap noop {mid}"));
                                return;
                            }
                            if *moved.read() { moved.set(false); return; }
                            diag::log("APP", &format!("row open {mid}"));
                            on_open.call(mid.clone());
                        }
                    },
                    {cover_el}
                    div { class: "img-body",
                        div { class: "img-text",
                            div { class: "t", style: "display:flex;align-items:center;gap:6px;width:100%;",
                                span { class: "img-card-title-text", "{title_text}" }
                                TagList { tags: summary.tags.clone() }
                            }
                            div { class: "m", style: "display:flex;align-items:center;gap:6px;",
                                span { "{ago}" }
                                span { class: "glass-label", style: "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;", "· {summary.preview}" }
                                if let Some(et) = expand_text.clone() {
                                    button {
                                        class: "expand-btn",
                                        // D-21：aria-label 与原版同值；
                                        // keydown 阻断冒泡等价于原版
                                        // onKeyDown 的 target===currentTarget
                                        // 守卫（按钮是卡内唯一可聚焦后代，
                                        // 其回车/空格只触发自身 click）。
                                        "aria-label": "{et}",
                                        onkeydown: move |e: Event<KeyboardData>| e.stop_propagation(),
                                        onclick: {
                                            let mid = mid.clone();
                                            move |e| {
                                                e.stop_propagation();
                                                diag::log("APP", &format!("row expand tap {mid}"));
                                                on_expand.call(());
                                            }
                                        },
                                        "{et}"
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                div {
                    class: "list-item",
                    // D-21：原版 SwipeRow 键盘可达性逐值——
                    // role=group、tabIndex=0、aria-label 硬编码
                    // 中文与原版一致。
                    role: "group",
                    tabindex: 0,
                    "aria-label": "{title_text}，按回车或空格打开",
                    style: "transform:translateX({offset}px);transition:{trans};touch-action:pan-y;",
                    onkeydown: {
                        let mid = mid.clone();
                        move |e: Event<KeyboardData>| {
                            if !is_open_key(&e) { return; }
                            e.prevent_default();
                            // 原版 onKeyDown：左滑开启态下先收起，
                            // 否则打开（与 onclick 同路）。
                            if *off.read() != 0 {
                                off.set(0);
                                diag::log("APP", &format!("row close key {mid}"));
                            } else if !*moved.read() {
                                diag::log("APP", &format!("row open key {mid}"));
                                on_open.call(mid.clone());
                            }
                        }
                    },
                    onpointerdown: move |e: Event<PointerData>| {
                        let (x, y) = ptr_xy(&e);
                        drag.set(Some((x, y, *off.read(), false)));
                    },
                    onpointermove: move |e: Event<PointerData>| {
                        let drag_cur = *drag.read();
                        if let Some((sx, sy, base, engaged)) = drag_cur {
                            let (x, y) = ptr_xy(&e);
                            let dx = x - sx;
                            let dy = y - sy;
                            let mut eng = engaged;
                            if !eng && dy.abs() > dx.abs() + 8.0 {
                                drag.set(None);
                                off.set(0);
                                return;
                            }
                            if !eng && dx.abs() > 5.0 { eng = true; }
                            if eng {
                                if dx.abs() > 8.0 { moved.set(true); }
                                off.set((base + dx as i32).clamp(-168, 0));
                                drag.set(Some((sx, sy, base, true)));
                            }
                        }
                    },
                    onpointerup: move |_| {
                        if drag.read().is_some() {
                            let cur = *off.read();
                            off.set(if cur < -55 { -168 } else { 0 });
                            drag.set(None);
                        }
                    },
                    onpointercancel: move |_| {
                        drag.set(None);
                        off.set(0);
                    },
                    onclick: {
                        let mid = mid.clone();
                        move |_| {
                            // 手势尾随 click 必须先于开启态收起
                            // 分支判定：本次手势有过有效位移时，
                            // 这记 click 是拖拽的尾随事件、不是
                            // 点按——桌面鼠标路径没有触摸的 click
                            // 抑制、必然尾随，若先走收起分支，
                            // 左滑刚打开的动作层会被它立即收起
                            // （桌面左滑删除/置顶不可用）；触摸
                            // 路径同口径、行为不变。无位移的普
                            // 通点按仍走下方开启态收起 / 打开备
                            // 忘两分支，语义逐字不变。
                            if *moved.read() { moved.set(false); return; }
                            if *off.read() != 0 { off.set(0); return; }
                            diag::log("APP", &format!("row open {mid}"));
                            on_open.call(mid.clone());
                        }
                    },
                    div { class: "item-left",
                        div { class: "item-title", style: "display:flex;align-items:center;gap:6px;width:100%;",
                            div { class: "item-title-main",
                                if pinned { span { class: "pin-dot" } }
                                span { class: "item-title-text", "{title_text}" }
                            }
                            TagList { tags: summary.tags.clone() }
                        }
                        div { class: "item-meta", style: "display:flex;align-items:center;gap:6px;",
                            span { style: "overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;", "{ago}\u{00a0}\u{00a0}{summary.preview}" }
                            if let Some(et) = expand_text.clone() {
                                button {
                                    class: "expand-btn",
                                    // D-21：同图片卡展开按钮——
                                    // aria-label 与原版同值，keydown
                                    // 阻断冒泡等价于原版目标守卫。
                                    "aria-label": "{et}",
                                    onkeydown: move |e: Event<KeyboardData>| e.stop_propagation(),
                                    onclick: {
                                        let mid = mid.clone();
                                        move |e| {
                                            e.stop_propagation();
                                            diag::log("APP", &format!("row expand tap {mid}"));
                                            on_expand.call(());
                                        }
                                    },
                                    "{et}"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 新建笔记卡（原版列表首行虚拟 SwipeRow：无滑动操作，
/// 标题新建笔记（弱色）、副行「现在  点击记录你的瞬间」）。
#[component]
pub(crate) fn NewCard(
    on_new: EventHandler<()>,
    /// 天气（W-3）：有数据时在 .list-item 末尾追加天气块
    /// （原版 SwipeRow isNewCard 分支同位）；宽屏下 base.css
    /// 的 last-child 规则把它排成方卡底部行。
    weather: Option<crate::weather::WeatherData>,
) -> Element {
    let weather_el = weather.as_ref().map(|w| {
        let city = crate::weather::to_cn(&w.city);
        let city_line = if w.condition.is_empty() {
            city
        } else if city.is_empty() {
            w.condition.clone()
        } else {
            format!("{city} {}", w.condition)
        };
        rsx! {
            div { class: "newcard-weather",
                span { class: "weather-temp", "{w.temp}°" }
                span { class: "weather-city", "{city_line}" }
            }
        }
    });
    rsx! {
        div { class: "swipe-wrapper",
            div {
                class: "list-item",
                // D-21：原版 SwipeRow 新建卡同款键盘可达性——
                // role=group、tabIndex=0、aria-label 硬编码
                // 中文与原版一致。
                role: "group",
                tabindex: 0,
                "aria-label": "新建笔记，按回车或空格打开",
                onkeydown: move |e: Event<KeyboardData>| {
                    if !is_open_key(&e) { return; }
                    e.prevent_default();
                    diag::log("APP", "row new key");
                    on_new.call(());
                },
                onclick: move |_| {
                    diag::log("APP", "row new tap");
                    on_new.call(());
                },
                div { class: "item-left",
                    div { class: "item-title new-card-title", style: "display:flex;align-items:center;gap:6px;width:100%;",
                        div { class: "item-title-main",
                            span { class: "item-title-text", "{i18n::t(\"list.new_note\")}" }
                        }
                    }
                    div { class: "item-meta",
                        span { "{i18n::t(\"list.now\")}\u{00a0}\u{00a0}{i18n::t(\"list.new_note_sub\")}" }
                    }
                }
                {weather_el}
            }
        }
    }
}

/// 三态空状态（批 12 P-U2）：空库 / 搜索零结果 / 加载失败
/// 的统一呈现。原版三态皆近空白（空库仅一行弱文案、搜索
/// 零结果与加载失败完全无呈现），本组件为行为补齐：大图
/// 标（弱化）+ 标题 + 说明 + 单一动作按钮，三态动作分别
/// 为新建备忘 / 清除搜索 / 重新加载。呈现打点在 App 侧
/// （empty state shown: <kind>，种类变化才记）。
#[component]
pub(crate) fn EmptyState(
    icon: String,
    title: String,
    sub: String,
    action_label: String,
    on_action: EventHandler<()>,
) -> Element {
    rsx! {
        div { class: "empty-state",
            div { class: "empty-state-icon", "{icon}" }
            div { class: "empty-state-title", "{title}" }
            div { class: "empty-state-sub", "{sub}" }
            button {
                class: "empty-state-btn",
                onclick: move |_| on_action.call(()),
                "{action_label}"
            }
        }
    }
}

/// 头像内容：Google 头像（localStorage google_avatar）或恐龙线稿玻璃圆。
/// remount_gen = 方案代际：根元素以其为键，翻转时在本组件模板内
/// 重挂（玻璃背板层在新方案下首次合成）。键不能挂在组件调用处
/// ——本框架下组件键变化不重挂子组件根节点（探针实证），必须
/// 落到根元素上（与 SearchCapsule 的元素键同一机制）。
#[component]
pub(crate) fn AvatarContent(size: u32, remount_gen: u32) -> Element {
    let google = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|s| s.get_item("google_avatar").ok().flatten())
        .filter(|s| !s.is_empty());
    rsx! {
        if let Some(src) = google {
            img {
                key: "{remount_gen}",
                src: "{src}",
                alt: "",
                style: "width:{size}px;height:{size}px;border-radius:var(--radius-circle);display:block;object-fit:cover;",
            }
        } else {
            div {
                key: "{remount_gen}",
                style: "width:{size}px;height:{size}px;backdrop-filter:var(--glass-control-filter);-webkit-backdrop-filter:var(--glass-control-filter);border-radius:var(--radius-circle);background:var(--glass-control-bg);border:0.5px solid var(--glass-control-border);display:flex;align-items:flex-end;justify-content:center;overflow:hidden;",
                span { dangerous_inner_html: "{icons::dino_markup(size - 8, 10)}" }
            }
        }
    }
}

#[cfg(test)]
mod cover_tests {
    use super::{cover_source, has_image, CoverSource};

    fn memo(doc: serde_json::Value) -> mynote_core::Memo {
        serde_json::from_value(serde_json::json!({
            "id": "t1", "title": "t", "pinned": false,
            "createdAt": "2026-11-24T00:00:00+08:00",
            "updatedAt": "2026-11-24T00:00:00+08:00",
            "doc": doc,
        }))
        .expect("memo json")
    }

    fn manifest(entries: serde_json::Value) -> String {
        serde_json::json!({ "version": 1, "attachments": entries }).to_string()
    }

    fn file(fid: &str) -> Option<CoverSource> {
        Some(CoverSource::File(fid.to_string()))
    }

    #[test]
    fn image_block_only_is_cover() {
        // 用户复现形：图只在 image 块（attrs 形）
        let m = memo(serde_json::json!([
            { "id": "p", "type": "paragraph", "children": [{ "text": "正文" }] },
            { "id": "i", "type": "image", "attrs": { "fileId": "f-red" } },
        ]));
        assert_eq!(cover_source(&m, ""), file("f-red"));
        // 顶层 fileId 旧形主线不再认（去兼容第四步收紧）：未经
        // 迁移通道归一的顶层形不作封面。
        let m2 = memo(serde_json::json!([
            { "id": "i", "type": "image", "fileId": "f-top" },
        ]));
        assert_eq!(cover_source(&m2, ""), None);
    }

    #[test]
    fn image_block_url_forms() {
        let m = memo(serde_json::json!([
            { "id": "i", "type": "image", "url": "https://example.com/a.png" },
        ]));
        assert_eq!(
            cover_source(&m, ""),
            Some(CoverSource::Url("https://example.com/a.png".to_string()))
        );
        // 被白名单拦的 url 不作封面、继续后找
        let m2 = memo(serde_json::json!([
            { "id": "i", "type": "image", "url": "javascript:alert(1)" },
            { "id": "g", "type": "gallery", "attrs": { "items": [{ "fileId": "f-b" }] } },
        ]));
        assert_eq!(cover_source(&m2, ""), file("f-b"));
    }

    #[test]
    fn gallery_first_item_and_forms() {
        let m = memo(serde_json::json!([
            { "id": "g", "type": "gallery",
              "attrs": { "items": [{ "fileId": "f-b" }, { "fileId": "f-g" }] } },
            { "id": "i", "type": "image", "attrs": { "fileId": "f-y" } },
        ]));
        assert_eq!(cover_source(&m, ""), file("f-b"));
        let m2 = memo(serde_json::json!([
            { "id": "g", "type": "gallery",
              "attrs": { "items": [{ "url": "https://example.com/u.png" }] } },
        ]));
        assert_eq!(
            cover_source(&m2, ""),
            Some(CoverSource::Url("https://example.com/u.png".to_string()))
        );
    }

    #[test]
    fn non_image_attachment_skipped() {
        let man = manifest(serde_json::json!({
            "f-pdf": { "name": "a.pdf", "type": "application/pdf" },
        }));
        let m = memo(serde_json::json!([
            { "id": "a", "type": "attachment", "attrs": { "fileId": "f-pdf" } },
            { "id": "i", "type": "image", "attrs": { "fileId": "f-img" } },
        ]));
        assert_eq!(cover_source(&m, &man), file("f-img"));
        assert!(has_image(&m, &man));
    }

    #[test]
    fn attachment_image_forms() {
        // image:true 内联图
        let m = memo(serde_json::json!([
            { "id": "a", "type": "attachment", "image": true, "attrs": { "fileId": "f-a" } },
        ]));
        assert_eq!(cover_source(&m, ""), file("f-a"));
        // 文件行图片（image 标志缺失、manifest 类型为图）
        let man = manifest(serde_json::json!({
            "f-p": { "name": "photo.png", "type": "image/png" },
            "f-d": { "name": "doc.pdf", "type": "application/pdf" },
        }));
        let m2 = memo(serde_json::json!([
            { "id": "a", "type": "attachment", "attrs": { "fileId": "f-p" } },
        ]));
        assert_eq!(cover_source(&m2, &man), file("f-p"));
        assert!(has_image(&m2, &man));
        // 文件行非图：无封面、非图文卡
        let m3 = memo(serde_json::json!([
            { "id": "a", "type": "attachment", "attrs": { "fileId": "f-d" } },
        ]));
        assert_eq!(cover_source(&m3, &man), None);
        assert!(!has_image(&m3, &man));
        // 类型未登记、靠文件名扩展名兜底（节点 name）
        let m4 = memo(serde_json::json!([
            { "id": "a", "type": "attachment", "name": "shot.jpg",
              "attrs": { "fileId": "f-x" } },
        ]));
        assert_eq!(cover_source(&m4, ""), file("f-x"));
    }

    #[test]
    fn card_blocks_and_externals() {
        let m = memo(serde_json::json!([
            { "id": "c", "type": "imgTextCard", "attrs": { "fileId": "f-c" } },
        ]));
        assert_eq!(cover_source(&m, ""), file("f-c"));
        let m = memo(serde_json::json!([
            { "id": "r", "type": "imageTextRow", "attrs": { "fileId": "f-r" } },
        ]));
        assert_eq!(cover_source(&m, ""), file("f-r"));
        // 外部封面（musicCard / link-card 的 meta.cover）不纳入
        let m = memo(serde_json::json!([
            { "id": "mu", "type": "musicCard", "url": "https://music.example/x",
              "meta": { "title": "歌", "cover": "https://example.com/c.jpg" } },
            { "id": "lk", "type": "link-card", "url": "https://example.com",
              "meta": { "title": "站", "cover": "https://example.com/l.jpg" } },
        ]));
        assert_eq!(cover_source(&m, ""), None);
        assert!(!has_image(&m, ""));
    }

    #[test]
    fn order_shift_and_placeholder() {
        // 删首图后的 doc（派生顺位）与换序后的 doc（跟随新首图）
        let before = memo(serde_json::json!([
            { "id": "i1", "type": "image", "attrs": { "fileId": "f-1" } },
            { "id": "i2", "type": "image", "attrs": { "fileId": "f-2" } },
        ]));
        assert_eq!(cover_source(&before, ""), file("f-1"));
        let after_delete = memo(serde_json::json!([
            { "id": "i2", "type": "image", "attrs": { "fileId": "f-2" } },
        ]));
        assert_eq!(cover_source(&after_delete, ""), file("f-2"));
        let after_swap = memo(serde_json::json!([
            { "id": "i2", "type": "image", "attrs": { "fileId": "f-2" } },
            { "id": "i1", "type": "image", "attrs": { "fileId": "f-1" } },
        ]));
        assert_eq!(cover_source(&after_swap, ""), file("f-2"));
        // 空占位 image 块（无 fid/url）不算图：样式门仍判图文
        // 卡（原版谓词），封面派生为 None（渲染空封面位）
        let ph = memo(serde_json::json!([
            { "id": "i", "type": "image", "attrs": { "fileId": "" } },
        ]));
        assert_eq!(cover_source(&ph, ""), None);
        assert!(has_image(&ph, ""));
        // 纯文本：无封面、非图文卡
        let txt = memo(serde_json::json!([
            { "id": "p", "type": "paragraph", "children": [{ "text": "只有文字" }] },
        ]));
        assert_eq!(cover_source(&txt, ""), None);
        assert!(!has_image(&txt, ""));
    }

    #[test]
    fn nested_children_depth_first() {
        // 容器块 children 内的图按深度优先命中（在后续兄弟块之前）
        let m = memo(serde_json::json!([
            { "id": "w", "type": "callout", "children": [
                { "id": "i", "type": "image", "attrs": { "fileId": "f-in" } },
            ] },
            { "id": "i2", "type": "image", "attrs": { "fileId": "f-out" } },
        ]));
        assert_eq!(cover_source(&m, ""), file("f-in"));
    }
}


