//! 行内节点 ⇄ 编辑态 HTML：全字面口径（斜杠审计 S3 的 core 互转对）。
//!
//! 行为规格是原版编辑器：模型侧一个文本块的 children 就是
//! `[{text: 整段字面}]`——格式全部以字面标记住在字符串里（斜杠
//! 行内命令的包裹对，src/app/editor/use-slash.js）：
//! 粗 `**…**`、斜 `*…*`、删除线 `~~…~~`、行内代码 `` `…` ``、
//! 高亮 `==…==`、链接 `[文字](url)`；编辑器 HTML 侧
//! renderDocToEditorHTML 对普通块只写转义后的纯文本（esc()），
//! parseEditorDOM 回读 textContent、且只认 children[0]。
//!
//! 现行渲染对（inline_html::inlines_to_html / html_to_inlines）是
//! bool 标记 ⇄ 元素口径，与编辑口径的丢失点：
//! 1. 表示分叉：同一格式按产生路径不同存成 bool 节点或字面
//!    文本；bool 节点存回后原版编辑器只读 children[0].text，
//!    多子节点段落的后段内容与全部标记语义在原版侧不可见，
//!    原版再保存即丢失。
//! 2. 写侧 split_highlight 把字面 == 切成 <mark> 元素——渲染
//!    口径正确，但编辑态里标记应保持字面（见下「与渲染对的
//!    分工」）。
//! 3. 链接节点除 url 外的 extra 字段、文本节点的未知 extra
//!    键在元素口径下无处安放，往返即丢。
//!
//! 本对的规范（编辑口径）：
//! - 写（inlines_to_editor_html）：先把 inlines 折叠成一段字面
//!   文本——bool 标记按上表折成字面包裹对（规范顺序：粗、斜、
//!   删、码；关闭序镜像），链接节点折成 `[文字](url)`（文字内
//!   `\`/`[`/`]` 反斜杠转义、换行折空格，与原版 inline_link
//!   插入口径一致；url 含 `)` 或空白时用 `[文字](<url>)` 尖角
//!   形），高亮本就以字面 == 存在于文本中、原样透传；然后整段
//!   HTML 转义、\n 写成 <br>。
//! - 例外（唯一非字面）：下划线在原版没有字面包裹对（斜杠命令
//!   与 md 预处理均无），故编辑态 HTML 里以下划线段落 `<u>…</u>`
//!   元素承载（其余标记仍折字面住在元素内的文本里），读侧还原
//!   为 underline bool 节点。此不对称是原版规格决定的，往返内
//!   无损。
//! - 读（editor_html_to_inlines）：先经渲染对的解析器归一
//!   （同义标签 strong/em/del、未知标签剥壳、实体解码、<br>→\n、
//!   <mark>→字面 ==、零宽空格剥除、相邻同标记合并），再把元素
//!   标记折回字面，输出原版形状：无下划线时恰一个纯文本节点；
//!   含下划线时下划线段为独立的 underline 节点、其余为字面
//!   文本节点。
//! - 往返性质：字面模型输入 → 写 → 读 **逐节点恒等**；bool
//!   标记输入 → 写 → 读得规范字面形，再写得同一 HTML（不
//!   动点）；编辑态 HTML → 读 → 写 → 读恒等（稳定）。
//!
//! 与渲染对的分工：只读渲染/导出继续用 inlines_to_html（== 切
//! <mark>、标记成元素）；本对只供编辑器填充/回收 contenteditable
//! 时替换调用（接线不在本模块内）。
//!
//! 已知口径差（有意，记录在案）：
//! - 软换行 \n ⇄ <br>：原版 textContent 回读会吞 <br> 的换行，
//!   本对按 Rust 编辑器既有口径保留（与渲染对一致）。
//! - 链接子节点带下划线时折字面会丢下划线（原版链接字面无此
//!   概念）；链接节点的 url 之外 extra、文本节点未知 extra 键
//!   折叠时丢弃——编辑口径的保留字母表就是标记 bool + url。
//! - 字面文本里用户自敲的标记字符不做反斜杠转义（与原版一
//!   致：它们在模型里是字面、在 md 预览里如何解释与原版同）。

use serde_json::{json, Map};

use crate::inline_html::html_to_inlines;
use crate::model::Node;

fn mark_of(node: &Node, key: &str) -> bool {
    node.extra.get(key).and_then(|v| v.as_bool()).unwrap_or(false)
}

fn is_underline(node: &Node) -> bool {
    mark_of(node, "underline")
}

/// 标记折字面的规范包裹对（下划线除外，它走 <u> 元素）。
/// 返回 (开, 闭)；顺序 粗→斜→删→码，闭序镜像，相邻拼接
/// （粗+斜即 ***…***）。
fn literal_wraps(node: &Node, text: &str) -> (String, String) {
    let mut open = String::new();
    let mut close = String::new();
    if mark_of(node, "bold") {
        open.push_str("**");
        close.insert_str(0, "**");
    }
    if mark_of(node, "italic") {
        open.push_str("*");
        close.insert_str(0, "*");
    }
    if mark_of(node, "strikethrough") {
        open.push_str("~~");
        close.insert_str(0, "~~");
    }
    if mark_of(node, "code") {
        // 文本含反引号时升级双反引号定界，首尾贴反引号/空格时
        // 内衬一个空格（CommonMark 口径），保证字面可往返辨认。
        if text.contains('`') {
            let pad = text.starts_with(['`', ' ']) || text.ends_with(['`', ' ']);
            if pad {
                open.push_str("`` ");
                close.insert_str(0, " ``");
            } else {
                open.push_str("``");
                close.insert_str(0, "``");
            }
        } else {
            open.push('`');
            close.insert(0, '`');
        }
    }
    (open, close)
}

fn escape_html(text: &str) -> String {
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

/// 链接文字的字面转义（原版 inline_link 口径）：`\`、`[`、`]
/// 反斜杠转义，换行折成空格。
fn escape_link_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '\\' | '[' | ']' => {
                out.push('\\');
                out.push(c);
            }
            '\n' | '\r' => out.push(' '),
            _ => out.push(c),
        }
    }
    out
}

/// 把 inlines 折成一段字面文本（不做 HTML 转义）。`in_link`
/// 为真时文本按链接文字口径转义、下划线无处安放直接并入
/// （已知口径差，见模块头）。
fn fold_literal(nodes: &[Node], in_link: bool) -> String {
    let mut out = String::new();
    for n in nodes {
        fold_node_literal(n, in_link, &mut out);
    }
    out
}

fn fold_node_literal(node: &Node, in_link: bool, out: &mut String) {
    if node.block_type() == Some("link") {
        let url = node.extra.get("url").and_then(|v| v.as_str()).unwrap_or("");
        let inner = fold_literal(node.children.as_deref().unwrap_or(&[]), true);
        out.push('[');
        out.push_str(&inner);
        out.push_str("](");
        if url.contains([')', ' ', '\t', '\n']) {
            out.push('<');
            out.push_str(url);
            out.push('>');
        } else {
            out.push_str(url);
        }
        out.push(')');
        return;
    }
    if let Some(text) = &node.text {
        if text.is_empty() {
            return;
        }
        let body = if in_link {
            escape_link_text(text)
        } else {
            text.clone()
        };
        let (open, close) = literal_wraps(node, &body);
        out.push_str(&open);
        out.push_str(&body);
        out.push_str(&close);
        return;
    }
    if let Some(kids) = &node.children {
        for k in kids {
            fold_node_literal(k, in_link, out);
        }
    }
}

fn any_underline(nodes: &[Node]) -> bool {
    nodes.iter().any(|n| {
        (n.text.is_some() && is_underline(n))
            || n.children.as_deref().is_some_and(any_underline)
    })
}

/// 行内节点序列 → 编辑态 HTML（填充 contenteditable 用）。
/// 全字面：折字面后整段转义；仅下划线段以 <u> 元素承载。
pub fn inlines_to_editor_html(nodes: &[Node]) -> String {
    if !any_underline(nodes) {
        return escape_html(&fold_literal(nodes, false)).replace('\n', "<br>");
    }
    let mut out = String::new();
    write_editor_nodes(nodes, &mut out);
    out
}

fn write_editor_nodes(nodes: &[Node], out: &mut String) {
    // 连续的非下划线段先攒成一段字面再转义，下划线文本段单独
    // 成 <u>；链接/容器递归（其内部下划线按已知口径差并入字面）。
    let mut plain: Vec<&Node> = Vec::new();
    let flush = |plain: &mut Vec<&Node>, out: &mut String| {
        if !plain.is_empty() {
            let lit: Vec<Node> = plain.drain(..).cloned().collect();
            out.push_str(&escape_html(&fold_literal(&lit, false)).replace('\n', "<br>"));
        }
    };
    for n in nodes {
        if n.text.is_some() && is_underline(n) {
            flush(&mut plain, out);
            let (open, close) = literal_wraps(n, n.text.as_deref().unwrap_or(""));
            let mut inner = String::new();
            inner.push_str(&open);
            inner.push_str(n.text.as_deref().unwrap_or(""));
            inner.push_str(&close);
            out.push_str("<u>");
            out.push_str(&escape_html(&inner).replace('\n', "<br>"));
            out.push_str("</u>");
        } else if n.text.is_some() || n.block_type() == Some("link") {
            plain.push(n);
        } else if let Some(kids) = &n.children {
            flush(&mut plain, out);
            write_editor_nodes(kids, out);
        }
    }
    flush(&mut plain, out);
}

/// 编辑态 HTML → 行内节点序列（从 contenteditable 回收时用）。
/// 输出原版形状：字面文本节点序列，下划线段为 underline 节点；
/// 全空时恰一个空文本节点（与原版兜底及渲染对口径一致）。
pub fn editor_html_to_inlines(html: &str) -> Vec<Node> {
    let parsed = html_to_inlines(html);
    let mut out: Vec<Node> = Vec::new();
    let mut buf = String::new();
    for n in &parsed {
        fold_parsed(n, &mut out, &mut buf);
    }
    flush_buf(&mut out, &mut buf);
    if out.is_empty() {
        out.push(empty_text());
    }
    out
}

fn empty_text() -> Node {
    Node {
        text: Some(String::new()),
        node_type: None,
        id: None,
        children: None,
        extra: Map::new(),
    }
}

fn text_node(text: String) -> Node {
    Node {
        text: Some(text),
        node_type: None,
        id: None,
        children: None,
        extra: Map::new(),
    }
}

fn flush_buf(out: &mut Vec<Node>, buf: &mut String) {
    if !buf.is_empty() {
        out.push(text_node(std::mem::take(buf)));
    }
}

/// 把解析器归一后的节点折进输出：文本的非下划线标记折字面进
/// buf；下划线文本段自成一个 underline 节点（其余标记折字面
/// 住进它的文本）；链接折字面进 buf；容器递归。
fn fold_parsed(node: &Node, out: &mut Vec<Node>, buf: &mut String) {
    if node.block_type() == Some("link") {
        buf.push_str(&fold_literal(std::slice::from_ref(node), false));
        return;
    }
    if let Some(text) = &node.text {
        if text.is_empty() {
            return;
        }
        let (open, close) = literal_wraps(node, text);
        if is_underline(node) {
            flush_buf(out, buf);
            let mut extra = Map::new();
            extra.insert("underline".into(), json!(true));
            out.push(Node {
                text: Some(format!("{open}{text}{close}")),
                node_type: None,
                id: None,
                children: None,
                extra,
            });
        } else {
            buf.push_str(&open);
            buf.push_str(text);
            buf.push_str(&close);
        }
        return;
    }
    if let Some(kids) = &node.children {
        for k in kids {
            fold_parsed(k, out, buf);
        }
    }
}
