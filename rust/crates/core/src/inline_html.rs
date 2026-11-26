//! 行内节点 ⇄ HTML：DOM 编辑器（contenteditable）与冻结块模型
//! 之间的桥。序列化把标记写成 b/i/u/s/code、链接写成 a；解析
//! 接受浏览器会产生的同义标签（strong/em）与未知标签（剥壳
//! 保字），并解码实体。往返保真是验收线（tests/inline_html.rs）。
//!
//! 高亮口径（与原版一致）：模型文本里以字面 ==重点== 存储；
//! 写 HTML 时切段包 <mark class="moment-highlight">（编辑器与
//! 只读渲染同源，见 split_highlight）；解析时 <mark> 还原为
//! 字面 ==，往返无损。


use crate::model::Node;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct Marks {
    bold: bool,
    italic: bool,
    underline: bool,
    strike: bool,
    code: bool,
}

impl Marks {
    /// 标记落到节点的类型化字段（§2.2）：只在为真时置
    /// Some(true)，与 JSON 形「只在为真时落键」同口径。
    fn apply_to(&self, node: &mut Node) {
        if self.bold {
            node.bold = Some(true);
        }
        if self.italic {
            node.italic = Some(true);
        }
        if self.underline {
            node.underline = Some(true);
        }
        if self.strike {
            node.strikethrough = Some(true);
        }
        if self.code {
            node.code = Some(true);
        }
    }
}

/// 链接 href 协议白名单（C-30，对原版 editor.render.js 的
/// safeHttpUrl + md 管线 DOMPurify 放行面）：只许 http(s)、
/// mailto 与无协议的相对引用；其余带 scheme 的协议
/// （javascript:/data:/vbscript:/file:/tel: 等）一律置空，
/// 防存储型 XSS。判定前先按浏览器 URL 解析口径剥除全部
/// ASCII 空白/控制字符再看 scheme（防 "java\tscript:" 类
/// 混淆）。返回 trim 后的原串或空串（空 = 不得出 href）。
pub fn safe_http_url(value: &str) -> String {
    let url = value.trim();
    if url.is_empty() {
        return String::new();
    }
    let compact: String = url
        .chars()
        .filter(|c| *c > ' ')
        .collect::<String>()
        .to_ascii_lowercase();
    if compact.starts_with("http://")
        || compact.starts_with("https://")
        || compact.starts_with("mailto:")
    {
        return url.to_string();
    }
    // 带 scheme（首个 ':' 早于任何 '/', '?', '#'）→ 拦截；
    // 否则是相对路径/锚点/查询，放行。
    let colon = compact.find(':');
    let sep = compact.find(['/', '?', '#']);
    match (colon, sep) {
        (Some(c), Some(s)) if c > s => url.to_string(),
        (Some(_), None) => String::new(),
        (Some(_), Some(_)) => String::new(),
        (None, _) => url.to_string(),
    }
}

/// 图片 src 白名单（原版 safeImageUrl 逐字口径）：http(s)，
/// 或 data:image/(png|jpeg|gif|webp|bmp|avif);base64,…（类型
/// 与 base64 字符集都核），其余置空。
pub fn safe_image_url(value: &str) -> String {
    let url = value.trim();
    let lower = url.to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        return url.to_string();
    }
    if is_safe_data_image(&lower) {
        return url.to_string();
    }
    String::new()
}

fn is_safe_data_image(lower: &str) -> bool {
    let Some(rest) = lower.strip_prefix("data:image/") else {
        return false;
    };
    let Some((ty, b64)) = rest.split_once(";base64,") else {
        return false;
    };
    if !matches!(ty, "png" | "jpeg" | "gif" | "webp" | "bmp" | "avif") {
        return false;
    }
    !b64.is_empty()
        && b64
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'='))
}

fn marks_of(node: &Node) -> Marks {
    Marks {
        bold: node.bold.unwrap_or(false),
        italic: node.italic.unwrap_or(false),
        underline: node.underline.unwrap_or(false),
        strike: node.strikethrough.unwrap_or(false),
        code: node.code.unwrap_or(false),
    }
}

fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            _ => out.push(c),
        }
    }
    out
}

fn unescape(text: &str) -> String {
    text.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&nbsp;", "\u{a0}")
        .replace("&amp;", "&")
}

/// 把文本按 ==高亮== 切段：(是否高亮, 片段)。未闭合的 == 不算
/// 高亮、原样保留。编辑器写 HTML 与只读渲染共用这一份切分。
pub fn split_highlight(text: &str) -> Vec<(bool, String)> {
    let mut out = Vec::new();
    let mut rest = text;
    loop {
        if let Some(start) = rest.find("==") {
            if let Some(end) = rest[start + 2..].find("==") {
                if start > 0 {
                    out.push((false, rest[..start].to_string()));
                }
                out.push((true, rest[start + 2..start + 2 + end].to_string()));
                rest = &rest[start + 2 + end + 2..];
                continue;
            }
        }
        if !rest.is_empty() {
            out.push((false, rest.to_string()));
        }
        break;
    }
    out
}

/// 行内节点序列 → HTML（写入 contenteditable 的初始内容）。
pub fn inlines_to_html(nodes: &[Node]) -> String {
    let mut out = String::new();
    for n in nodes {
        write_node(n, &mut out);
    }
    out
}

fn write_node(node: &Node, out: &mut String) {
    if node.block_type() == Some("link") {
        let url = node.url.as_deref().unwrap_or("");
        // C-30：href 过协议白名单，被拦时只出文本不出锚
        // （原版 DOMPurify 剥 href 留文本的等价口径）。
        let safe = safe_http_url(url);
        if !safe.is_empty() {
            out.push_str("<a href=\"");
            out.push_str(&escape(&safe));
            out.push_str("\">");
        }
        if let Some(kids) = &node.children {
            for k in kids {
                write_node(k, out);
            }
        }
        if !safe.is_empty() {
            out.push_str("</a>");
        }
        return;
    }
    if let Some(text) = &node.text {
        let marks = marks_of(node);
        let mut open = String::new();
        let mut close = String::new();
        let mut wrap = |tag: &str, on: bool| {
            if on {
                open.push_str("<");
                open.push_str(tag);
                open.push('>');
                close.insert_str(0, &format!("</{tag}>"));
            }
        };
        wrap("b", marks.bold);
        wrap("i", marks.italic);
        wrap("u", marks.underline);
        wrap("s", marks.strike);
        wrap("code", marks.code);
        for (hi, seg) in split_highlight(text) {
            if hi {
                out.push_str("<mark class=\"moment-highlight\">");
            }
            out.push_str(&open);
            out.push_str(&escape(&seg).replace('\n', "<br>"));
            out.push_str(&close);
            if hi {
                out.push_str("</mark>");
            }
        }
        return;
    }
    if let Some(kids) = &node.children {
        for k in kids {
            write_node(k, out);
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Text(String),
    Open { name: String, href: Option<String> },
    Close { name: String },
    Br,
}

fn tokenize(html: &str) -> Vec<Token> {
    let mut toks = Vec::new();
    let bytes = html.as_bytes();
    let mut i = 0;
    let mut text_start = 0;
    let push_text = |toks: &mut Vec<Token>, s: &str| {
        if !s.is_empty() {
            toks.push(Token::Text(unescape(s)));
        }
    };
    while i < bytes.len() {
        if bytes[i] == b'<' {
            if let Some(end) = html[i..].find('>') {
                let tag = &html[i + 1..i + end];
                push_text(&mut toks, &html[text_start..i]);
                let tag = tag.trim();
                if tag.eq_ignore_ascii_case("br") || tag.eq_ignore_ascii_case("br/") {
                    toks.push(Token::Br);
                } else if let Some(name) = tag.strip_prefix('/') {
                    toks.push(Token::Close {
                        name: name.trim().to_ascii_lowercase(),
                    });
                } else {
                    let name: String = tag
                        .chars()
                        .take_while(|c| c.is_ascii_alphanumeric())
                        .collect::<String>()
                        .to_ascii_lowercase();
                    let href = if name == "a" {
                        extract_href(tag)
                    } else {
                        None
                    };
                    toks.push(Token::Open { name, href });
                }
                i += end + 1;
                text_start = i;
                continue;
            }
        }
        i += 1;
    }
    push_text(&mut toks, &html[text_start..]);
    toks
}

fn extract_href(tag: &str) -> Option<String> {
    let lower = tag.to_ascii_lowercase();
    let pos = lower.find("href")?;
    let rest = &tag[pos + 4..];
    let rest = rest.trim_start();
    let rest = rest.strip_prefix('=')?.trim_start();
    let quote = rest.chars().next()?;
    if quote == '"' || quote == '\'' {
        let end = rest[1..].find(quote)?;
        Some(unescape(&rest[1..1 + end]))
    } else {
        let end = rest
            .find(|c: char| c.is_whitespace())
            .unwrap_or(rest.len());
        Some(unescape(&rest[..end]))
    }
}

struct Parser {
    toks: Vec<Token>,
    pos: usize,
}

impl Parser {
    /// 解析到 `closing` 标签为止（None = 解析到结尾）。
    fn parse_until(&mut self, marks: Marks, closing: Option<&str>) -> Vec<Node> {
        let mut out: Vec<Node> = Vec::new();
        while self.pos < self.toks.len() {
            match self.toks[self.pos].clone() {
                Token::Text(t) => {
                    self.pos += 1;
                    if !t.is_empty() {
                        push_text_node(&mut out, &t, marks);
                    }
                }
                Token::Br => {
                    // 软换行（Shift+Enter）：与原版口径一致地落为
                    // 文本里的 \n，写回 HTML 时再还原成 <br>
                    self.pos += 1;
                    push_text_node(&mut out, "\n", marks);
                }
                Token::Close { name } => {
                    self.pos += 1;
                    if closing == Some(name.as_str()) {
                        return out;
                    }
                    // 不匹配的闭合标签：忽略
                }
                Token::Open { name, href } => {
                    self.pos += 1;
                    match name.as_str() {
                        "b" | "strong" => {
                            let mut m = marks;
                            m.bold = true;
                            let kids = self.parse_until(m, Some(&name));
                            extend_merging(&mut out, kids);
                        }
                        "i" | "em" => {
                            let mut m = marks;
                            m.italic = true;
                            let kids = self.parse_until(m, Some(&name));
                            extend_merging(&mut out, kids);
                        }
                        "u" => {
                            let mut m = marks;
                            m.underline = true;
                            let kids = self.parse_until(m, Some(&name));
                            extend_merging(&mut out, kids);
                        }
                        "s" | "strike" | "del" => {
                            let mut m = marks;
                            m.strike = true;
                            let kids = self.parse_until(m, Some(&name));
                            extend_merging(&mut out, kids);
                        }
                        "code" => {
                            let mut m = marks;
                            m.code = true;
                            let kids = self.parse_until(m, Some(&name));
                            extend_merging(&mut out, kids);
                        }
                        "mark" => {
                            // 高亮元素还原为字面 ==…==（存储口径）
                            let kids = self.parse_until(marks, Some("mark"));
                            extend_merging(&mut out, mark_to_literal(kids));
                        }
                        "a" => {
                            let kids = self.parse_until(marks, Some("a"));
                            out.push(Node {
                                node_type: Some("link".into()),
                                children: Some(kids),
                                url: href,
                                ..Default::default()
                            });
                        }
                        _ => {
                            // 未知标签（span/div/font…）：剥壳保字
                            let kids = self.parse_until(marks, Some(&name));
                            extend_merging(&mut out, kids);
                        }
                    }
                }
            }
        }
        out
    }
}

/// <mark> 内容 → 字面 ==…==：去掉编辑占位用的零宽空格，首个
/// 文本节点加前缀 ==、末个加后缀 ==；无文本则整体消失。
fn mark_to_literal(kids: Vec<Node>) -> Vec<Node> {
    fn strip_zwsp(nodes: &mut [Node]) {
        for n in nodes.iter_mut() {
            if let Some(t) = &mut n.text {
                *t = t.replace('\u{200b}', "");
            }
            if let Some(kids) = &mut n.children {
                strip_zwsp(kids);
            }
        }
    }
    fn first_text(nodes: &mut [Node]) -> Option<&mut Node> {
        for n in nodes.iter_mut() {
            if n.text.is_some() {
                return Some(n);
            }
            if let Some(kids) = &mut n.children {
                if let Some(f) = first_text(kids) {
                    return Some(f);
                }
            }
        }
        None
    }
    fn last_text(nodes: &mut [Node]) -> Option<&mut Node> {
        for n in nodes.iter_mut().rev() {
            if n.text.is_some() {
                return Some(n);
            }
            if let Some(kids) = &mut n.children {
                if let Some(f) = last_text(kids) {
                    return Some(f);
                }
            }
        }
        None
    }
    let mut kids = kids;
    strip_zwsp(&mut kids);
    kids.retain(|n| n.text.as_deref() != Some(""));
    let Some(first) = first_text(&mut kids) else {
        return Vec::new();
    };
    if let Some(t) = &mut first.text {
        t.insert_str(0, "==");
    }
    let last = last_text(&mut kids).expect("first text exists");
    if let Some(t) = &mut last.text {
        t.push_str("==");
    }
    kids
}

/// 拼接子解析结果：边界上相邻的同标记文本节点合并。
fn extend_merging(out: &mut Vec<Node>, kids: Vec<Node>) {
    for kid in kids {
        if kid.is_text() {
            if let Some(last) = out.last_mut() {
                if last.is_text() && marks_of(last) == marks_of(&kid) {
                    if let (Some(a), Some(b)) = (&mut last.text, &kid.text) {
                        a.push_str(b);
                        continue;
                    }
                }
            }
        }
        out.push(kid);
    }
}

fn push_text_node(out: &mut Vec<Node>, text: &str, marks: Marks) {
    // 零宽空格只是编辑器里的光标占位符（mark 占位、实时高亮的
    // 边界锚点），不是内容：解析时统一剥掉。
    let text = &text.replace('\u{200b}', "");
    if text.is_empty() {
        return;
    }
    if let Some(last) = out.last_mut() {
        if last.is_text() && marks_of(last) == marks {
            if let Some(t) = &mut last.text {
                t.push_str(text);
                return;
            }
        }
    }
    let mut node = Node {
        text: Some(text.to_string()),
        ..Default::default()
    };
    marks.apply_to(&mut node);
    out.push(node);
}

/// HTML → 行内节点序列（从 contenteditable 读回时用）。
pub fn html_to_inlines(html: &str) -> Vec<Node> {
    let mut parser = Parser {
        toks: tokenize(html),
        pos: 0,
    };
    let nodes = parser.parse_until(Marks::default(), None);
    if nodes.is_empty() {
        vec![Node {
            text: Some(String::new()),
            ..Default::default()
        }]
    } else {
        nodes
    }
}

#[cfg(test)]
mod tests {
    use super::{safe_http_url, safe_image_url};

    #[test]
    fn http_url_whitelist() {
        assert_eq!(safe_http_url("https://example.com/a?b=c"), "https://example.com/a?b=c");
        assert_eq!(safe_http_url("HTTP://EXAMPLE.COM"), "HTTP://EXAMPLE.COM");
        assert_eq!(safe_http_url("  https://example.com  "), "https://example.com");
        assert_eq!(safe_http_url("mailto:a@b.c"), "mailto:a@b.c");
        assert_eq!(safe_http_url("/docs/page.html"), "/docs/page.html");
        assert_eq!(safe_http_url("#section"), "#section");
        assert_eq!(safe_http_url("foo/bar:baz"), "foo/bar:baz");
        assert_eq!(safe_http_url("//example.com/x"), "//example.com/x");
        assert_eq!(safe_http_url(""), "");
    }

    #[test]
    fn http_url_blocks_dangerous_schemes() {
        assert_eq!(safe_http_url("javascript:alert(1)"), "");
        assert_eq!(safe_http_url("JaVaScRiPt:alert(1)"), "");
        assert_eq!(safe_http_url("java\tscript:alert(1)"), "");
        assert_eq!(safe_http_url("java\nscript:alert(1)"), "");
        assert_eq!(safe_http_url(" javascript:alert(1)"), "");
        assert_eq!(safe_http_url("data:text/html;base64,PHNjcmlwdD4="), "");
        assert_eq!(safe_http_url("vbscript:msgbox(1)"), "");
        assert_eq!(safe_http_url("file:///etc/passwd"), "");
        assert_eq!(safe_http_url("tel:12345"), "");
    }

    #[test]
    fn image_url_whitelist() {
        assert_eq!(safe_image_url("https://example.com/a.png"), "https://example.com/a.png");
        assert_eq!(safe_image_url("data:image/png;base64,iVBORw0KGgo="), "data:image/png;base64,iVBORw0KGgo=");
        assert_eq!(safe_image_url("data:image/jpeg;base64,/9j/4AAQ=="), "data:image/jpeg;base64,/9j/4AAQ==");
        assert_eq!(safe_image_url("DATA:IMAGE/WEBP;BASE64,UklGRg=="), "DATA:IMAGE/WEBP;BASE64,UklGRg==");
        assert_eq!(safe_image_url("data:image/svg+xml;base64,PHN2Zz4="), "");
        assert_eq!(safe_image_url("data:text/html;base64,PHNjcmlwdD4="), "");
        assert_eq!(safe_image_url("javascript:alert(1)"), "");
        assert_eq!(safe_image_url("data:image/png;base64,@@@"), "");
        assert_eq!(safe_image_url("data:image/png;base64,"), "");
        assert_eq!(safe_image_url("blob:https://example.com/uuid"), "");
    }
}
