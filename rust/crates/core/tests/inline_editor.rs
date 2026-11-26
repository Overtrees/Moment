//! 编辑态全字面互转对验收（斜杠审计 S3）：
//! 字面模型输入往返逐节点恒等；bool 标记输入规范化为字面形
//! 且再写不动点；编辑态 HTML 读→写→读稳定；浏览器风格元素
//! （strong/em/del/mark/a/u/未知标签/实体）折字面正确。

use moment_core::{editor_html_to_inlines, inlines_to_editor_html, Node};

fn text(s: &str, marks: &[&str]) -> Node {
    let mut n = Node {
        text: Some(s.to_string()),
        ..Default::default()
    };
    for m in marks {
        match *m {
            "bold" => n.bold = Some(true),
            "italic" => n.italic = Some(true),
            "underline" => n.underline = Some(true),
            "strikethrough" => n.strikethrough = Some(true),
            "code" => n.code = Some(true),
            other => panic!("unknown mark {other}"),
        }
    }
    n
}

fn plain(s: &str) -> Node {
    text(s, &[])
}

fn link(url: &str, kids: Vec<Node>) -> Node {
    Node {
        node_type: Some("link".into()),
        children: Some(kids),
        url: Some(url.to_string()),
        ..Default::default()
    }
}

/// 字面模型：写→读逐节点恒等。
fn literal_identity(nodes: Vec<Node>) {
    let html = inlines_to_editor_html(&nodes);
    let back = editor_html_to_inlines(&html);
    assert_eq!(back, nodes, "literal identity via html: {html}");
}

/// 任意输入：写→读→写 不动点（第二次的 HTML 与第一次相同）。
fn fixed_point(nodes: Vec<Node>) {
    let html1 = inlines_to_editor_html(&nodes);
    let back = editor_html_to_inlines(&html1);
    let html2 = inlines_to_editor_html(&back);
    assert_eq!(html1, html2, "fixed point: {html1} vs {html2}");
}

/// 编辑态 HTML：读→写→读 恒等（稳定）。
fn html_stable(html: &str) {
    let a = editor_html_to_inlines(html);
    let b = editor_html_to_inlines(&inlines_to_editor_html(&a));
    assert_eq!(a, b, "html stable: {html}");
}

#[test]
fn plain_text_identity() {
    literal_identity(vec![plain("冬日里的实用技巧")]);
}

#[test]
fn literal_markers_stay_literal() {
    // 原版数据形态：格式全是字面标记，编辑态不得把它们变成
    // 元素、也不得切分节点
    let nodes = vec![plain("前**粗**中*斜*与`码`、~~删~~、==亮==尾")];
    let html = inlines_to_editor_html(&nodes);
    assert_eq!(html, "前**粗**中*斜*与`码`、~~删~~、==亮==尾");
    literal_identity(nodes);
}

#[test]
fn highlight_is_not_split_into_mark() {
    // 与渲染对的分工：编辑态 == 保持字面，不写 <mark>
    let html = inlines_to_editor_html(&[plain("==重点==")]);
    assert!(!html.contains("<mark"), "html: {html}");
    assert_eq!(html, "==重点==");
}

#[test]
fn entities_and_angle_brackets_identity() {
    literal_identity(vec![plain("a<b & \"c\" > d、e&f<'g'>")]);
    let html = inlines_to_editor_html(&[plain("a<b")]);
    assert_eq!(html, "a&lt;b");
}

#[test]
fn soft_break_identity() {
    literal_identity(vec![plain("首行\n次行")]);
    assert_eq!(inlines_to_editor_html(&[plain("首行\n次行")]), "首行<br>次行");
    assert_eq!(editor_html_to_inlines("首行<br>次行"), vec![plain("首行\n次行")]);
}

#[test]
fn bool_marks_fold_to_literal() {
    let nodes = vec![
        text("粗", &["bold"]),
        text("斜", &["italic"]),
        text("粗斜", &["bold", "italic"]),
        text("删", &["strikethrough"]),
        text("码", &["code"]),
        plain("普通"),
    ];
    let html = inlines_to_editor_html(&nodes);
    assert_eq!(html, "**粗***斜****粗斜***~~删~~`码`普通");
    // 读回得规范字面形：恰一个纯文本节点
    assert_eq!(
        editor_html_to_inlines(&html),
        vec![plain("**粗***斜****粗斜***~~删~~`码`普通")]
    );
    fixed_point(nodes);
}

#[test]
fn code_with_backtick_upgrades_delimiter() {
    let nodes = vec![text("a`b", &["code"])];
    let html = inlines_to_editor_html(&nodes);
    assert_eq!(html, "``a`b``");
    fixed_point(nodes);
    let nodes2 = vec![text("`x`", &["code"])];
    assert_eq!(inlines_to_editor_html(&nodes2), "`` `x` ``");
    fixed_point(nodes2);
}

#[test]
fn underline_rides_u_element_and_roundtrips() {
    let nodes = vec![plain("前"), text("线", &["underline"]), plain("后")];
    let html = inlines_to_editor_html(&nodes);
    assert_eq!(html, "前<u>线</u>后");
    // 下划线是唯一保持 bool 的标记：读回逐节点恒等
    assert_eq!(editor_html_to_inlines(&html), nodes);
    fixed_point(nodes);
}

#[test]
fn underline_with_other_marks_folds_inside() {
    let nodes = vec![text("粗线", &["underline", "bold"])];
    let html = inlines_to_editor_html(&nodes);
    assert_eq!(html, "<u>**粗线**</u>");
    assert_eq!(
        editor_html_to_inlines(&html),
        vec![text("**粗线**", &["underline"])]
    );
    fixed_point(nodes);
}

#[test]
fn link_node_folds_to_literal() {
    let nodes = vec![
        plain("看"),
        link("https://example.com/?a=1&b=2", vec![plain("站点")]),
        plain("完"),
    ];
    let html = inlines_to_editor_html(&nodes);
    assert_eq!(html, "看[站点](https://example.com/?a=1&amp;b=2)完");
    assert_eq!(
        editor_html_to_inlines(&html),
        vec![plain("看[站点](https://example.com/?a=1&b=2)完")]
    );
    fixed_point(nodes);
}

#[test]
fn link_children_marks_fold_inside_brackets() {
    let nodes = vec![link("https://x.dev", vec![text("粗链", &["bold"])])];
    assert_eq!(
        inlines_to_editor_html(&nodes),
        "[**粗链**](https://x.dev)"
    );
    fixed_point(nodes);
}

#[test]
fn link_url_with_paren_uses_angle_form() {
    let nodes = vec![link("https://x.dev/a_(b)", vec![plain("链")])];
    // 尖角是字面文本的一部分，写进 HTML 时与其它 < > 一样转义，
    // 显示与回读都还是 (<url>) 字面形
    assert_eq!(
        inlines_to_editor_html(&nodes),
        "[链](&lt;https://x.dev/a_(b)&gt;)"
    );
    fixed_point(nodes);
}

#[test]
fn browser_elements_fold_to_literal() {
    // 浏览器/execCommand 风格 HTML 回收：元素折字面成原版形状
    let nodes = editor_html_to_inlines(
        "<strong>粗</strong>与<em>斜</em>、<del>删</del>、<code>码</code>、<mark class=\"moment-highlight\">亮</mark>",
    );
    assert_eq!(nodes, vec![plain("**粗**与*斜*、~~删~~、`码`、==亮==")]);
}

#[test]
fn browser_link_element_folds_to_literal() {
    let nodes = editor_html_to_inlines("看<a href=\"https://example.com\">站点</a>完");
    assert_eq!(nodes, vec![plain("看[站点](https://example.com)完")]);
}

#[test]
fn browser_u_element_becomes_underline_node() {
    let nodes = editor_html_to_inlines("前<u>线</u>后");
    assert_eq!(
        nodes,
        vec![plain("前"), text("线", &["underline"]), plain("后")]
    );
}

#[test]
fn nested_elements_fold_per_run() {
    // 正常嵌套：内层斜体段 = 粗+斜双标记折 ***，尾字在 b 之外
    let nodes = editor_html_to_inlines("<b>粗<i>斜</i></b>尾");
    assert_eq!(nodes, vec![plain("**粗*****斜***尾")]);
    html_stable("<b>粗<i>斜</i></b>尾");
}

#[test]
fn unknown_tags_strip_and_entities_decode() {
    let nodes = editor_html_to_inlines("<span style=\"x\">净</span>a&lt;b&nbsp;c");
    assert_eq!(nodes, vec![plain("净a<b\u{a0}c")]);
}

#[test]
fn zwsp_placeholders_stripped() {
    let nodes = editor_html_to_inlines("前\u{200b}后<mark>亮\u{200b}</mark>");
    assert_eq!(nodes, vec![plain("前后==亮==")]);
    assert_eq!(
        editor_html_to_inlines("<mark class=\"moment-highlight\">\u{200b}</mark>"),
        vec![plain("")]
    );
}

#[test]
fn empty_inputs() {
    assert_eq!(inlines_to_editor_html(&[]), "");
    assert_eq!(editor_html_to_inlines(""), vec![plain("")]);
    literal_identity(vec![plain("")]);
}

#[test]
fn unclosed_markers_stay_literal() {
    literal_identity(vec![plain("只有**开头和==半截")]);
}

#[test]
fn multi_node_literal_concatenates_to_single() {
    // 多个纯文本节点（旧数据/合并残形）写读后归一为单节点，
    // 与原版 children[0] 形状对齐
    let nodes = vec![plain("甲"), plain("乙")];
    let back = editor_html_to_inlines(&inlines_to_editor_html(&nodes));
    assert_eq!(back, vec![plain("甲乙")]);
    fixed_point(nodes);
}

#[test]
fn html_stability_matrix() {
    for html in [
        "纯文本",
        "<b>粗</b>与<i>斜</i>",
        "<u>线</u>**字面粗**",
        "<a href=\"https://x.dev\">链</a>==亮==",
        "首行<br>次行",
        "<mark>亮</mark><code>码</code>",
        "前<u>**粗线**</u>后",
    ] {
        html_stable(html);
    }
}
