//! 数学公式管线（Rust 原生自研实现，纯 std、无外部资产与依赖）。
//!
//! # 规格与实现的划分
//!
//! **行为规格（验收标准）对齐原版应用**，从其可观察行为反推：
//! - 哪些输入算公式（门控）：`$$…$$` 任意跨行成对即块级公式；
//!   `$…$` 须同行成对且内容通过内容启发式才算行内公式；
//! - 防误判边界：单个 `$` 不成式、`\$` 转义不成式、内容启发式
//!   （单个字母，或含 `\命令` / 数字 / 运算符 / 希腊字母才算式，
//!   纯字母词如 `$abc$` 不算）、行内式开定界符前一字符为 `$`
//!   时不开式、闭定界符后紧跟 `$` 时不算式；
//! - 切分顺序：代码段（反引号串）先保护、块级 `$$` 先于行内 `$`；
//! - 失败兜底形态：公式整体无法解析（括号不配平、缺参数、环境
//!   不匹配等硬错误）时整式回退为红色原码；未知命令按通行
//!   数学渲染器口径在式内以红色呈现命令名并继续渲染其余部分。
//!
//! **实现为自研设计**：字符级切分器（[`split_math`]）+ TeX 子集
//! 词法器/递归下降解析器 + MathML 发射器。解析树、错误分类、
//! 限值（limits）判定、环境（矩阵/对齐）建模均为本模块自己的
//! 设计，不对应任何既有实现的内部结构。

use std::fmt;

// ================= 门控与防误判 =================

/// 位置 idx 之前紧邻的反斜杠个数为奇数时，该位置被转义。
fn is_escaped_at(chars: &[char], idx: usize) -> bool {
    let mut count = 0usize;
    let mut i = idx;
    while i > 0 && chars[i - 1] == '\\' {
        count += 1;
        i -= 1;
    }
    count % 2 == 1
}

/// 内容启发式：一段 `$…$` 候选内容是否像数学表达式。
///
/// 规格：trim 后非空；单个 ASCII 字母恒真；否则内容须含
/// `\` + 字母（命令）、数字、`^ _ { } = + - * / < >` 之一，
/// 或希腊字母（α-ω / Α-Ω）。
pub fn looks_like_math_expression(expression: &str) -> bool {
    let value = expression.trim();
    if value.is_empty() {
        return false;
    }
    let chars: Vec<char> = value.chars().collect();
    if chars.len() == 1 && chars[0].is_ascii_alphabetic() {
        return true;
    }
    for (i, &c) in chars.iter().enumerate() {
        if c == '\\' && i + 1 < chars.len() && chars[i + 1].is_ascii_alphabetic() {
            return true;
        }
        if c.is_ascii_digit() {
            return true;
        }
        if matches!(c, '=' | '+' | '-' | '*' | '/' | '^' | '_' | '{' | '}' | '<' | '>') {
            return true;
        }
        if ('\u{03b1}'..='\u{03c9}').contains(&c) || ('\u{0391}'..='\u{03a9}').contains(&c) {
            return true;
        }
    }
    false
}

/// 门控：文本是否含数学公式语法（`$$…$$` 成对，或未转义的
/// `$…$` 成对且内容通过启发式）。与段落 Markdown 门控同层使用。
pub fn has_math_syntax(text: &str) -> bool {
    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();
    // 块级：$$ 之后至少隔 1 字符再出现 $$ 即成对。
    let mut i = 0;
    while i + 1 < n {
        if chars[i] == '$' && chars[i + 1] == '$' {
            let mut j = i + 3;
            while j + 1 < n {
                if chars[j] == '$' && chars[j + 1] == '$' {
                    return true;
                }
                j += 1;
            }
            break;
        }
        i += 1;
    }
    // 行内：逐个候选开定界符试配对；配对失败（内容不合启发式）
    // 时整对跳过再继续（与正则全局扫描的 lastIndex 推进一致）。
    let mut i = 0;
    while i < n {
        if chars[i] == '$' && !is_escaped_at(&chars, i) {
            let mut j = i + 1;
            let mut close = None;
            while j < n {
                if chars[j] == '\n' || chars[j] == '\r' {
                    break;
                }
                if chars[j] == '\\' && j + 1 < n {
                    // 转义对整体跳过：\$ 不是闭定界符。
                    j += 2;
                    continue;
                }
                if chars[j] == '$' {
                    close = Some(j);
                    break;
                }
                j += 1;
            }
            match close {
                Some(j) if j > i + 1 => {
                    let content: String = chars[i + 1..j].iter().collect();
                    if looks_like_math_expression(&content) {
                        return true;
                    }
                    i = j + 1;
                    continue;
                }
                _ => {
                    i += 1;
                }
            }
        } else {
            i += 1;
        }
    }
    false
}

// ================= 切分 =================

/// 切分结果段：普通文本或一段公式（tex 为定界符内的源码，
/// display=true 为块级 `$$…$$`）。
#[derive(Clone, Debug, PartialEq)]
pub enum MathSegment {
    Text(String),
    Math { tex: String, display: bool },
}

/// 把段落文本切分为文本段与公式段。
///
/// 规则（规格见模块头）：反引号代码段整体保护（其内 `$` 不
/// 成式）；`\X` 转义对整体作普通文本（`\$` 不开式、`\\` 后
/// 的 `$` 正常开式）；块级 `$$…$$` 优先（内容可跨行、取最近
/// 闭合）；行内 `$…$` 须同行闭合、内容过启发式，且开定界符
/// 的前一字符为 `$` 时不开式、闭定界符后紧跟 `$` 时整对作
/// 普通文本；配对但内容不合启发式时整对作普通文本并跳过。
pub fn split_math(text: &str) -> Vec<MathSegment> {
    let chars: Vec<char> = text.chars().collect();
    let n = chars.len();
    let mut segs: Vec<MathSegment> = Vec::new();
    let mut buf = String::new();
    // 开定界符守卫用：前一源字符是否为「未被公式消费的 $」。
    let mut prev_is_dollar = false;
    let mut flush = |buf: &mut String, segs: &mut Vec<MathSegment>| {
        if !buf.is_empty() {
            segs.push(MathSegment::Text(std::mem::take(buf)));
        }
    };
    let mut i = 0;
    while i < n {
        let c = chars[i];
        // 代码段保护：等长反引号串闭合，整体作普通文本。
        if c == '`' {
            let mut run = 1;
            while i + run < n && chars[i + run] == '`' {
                run += 1;
            }
            let mut j = i + run;
            let mut end = i + run;
            while j < n {
                if chars[j] == '`' {
                    let mut r = 0;
                    while j + r < n && chars[j + r] == '`' {
                        r += 1;
                    }
                    if r == run {
                        end = j + r;
                        break;
                    }
                    j += r;
                } else {
                    j += 1;
                }
            }
            for k in i..end {
                buf.push(chars[k]);
            }
            prev_is_dollar = false;
            i = end;
            continue;
        }
        // 链接目标保护：](…) 内的 $ 不成式（规格：链接目标
        // 在原版管线里先于公式处理被整体保护）。
        if c == ']' && i + 1 < n && chars[i + 1] == '(' {
            let mut j = i;
            while j < n && chars[j] != ')' {
                j += 1;
            }
            let end = if j < n { j + 1 } else { i + 1 };
            for k in i..end {
                buf.push(chars[k]);
            }
            prev_is_dollar = false;
            i = end;
            continue;
        }
        // 转义对整体作普通文本。
        if c == '\\' && i + 1 < n {
            buf.push(c);
            buf.push(chars[i + 1]);
            prev_is_dollar = chars[i + 1] == '$';
            i += 2;
            continue;
        }
        if c == '$' {
            // 块级 $$…$$
            if i + 1 < n && chars[i + 1] == '$' {
                let mut j = i + 2;
                let mut close = None;
                while j + 1 < n {
                    if chars[j] == '\\' && j + 1 < n {
                        // 转义对整体跳过：\$ 不是定界符。
                        j += 2;
                        continue;
                    }
                    if chars[j] == '$' && chars[j + 1] == '$' {
                        close = Some(j);
                        break;
                    }
                    j += 1;
                }
                match close {
                    Some(cl) if cl > i + 2 => {
                        flush(&mut buf, &mut segs);
                        let tex: String = chars[i + 2..cl].iter().collect();
                        segs.push(MathSegment::Math {
                            tex,
                            display: true,
                        });
                        prev_is_dollar = false;
                        i = cl + 2;
                        continue;
                    }
                    _ => {
                        // 无闭合或空内容：$$ 作普通文本。
                        buf.push('$');
                        buf.push('$');
                        prev_is_dollar = true;
                        i += 2;
                        continue;
                    }
                }
            }
            // 行内 $…$：前一字符为 $ 时不开式。
            if prev_is_dollar {
                buf.push('$');
                prev_is_dollar = true;
                i += 1;
                continue;
            }
            let mut j = i + 1;
            let mut close = None;
            while j < n {
                if chars[j] == '\n' || chars[j] == '\r' {
                    break;
                }
                if chars[j] == '\\' && j + 1 < n {
                    // 转义对整体跳过：\$ 不是闭定界符。
                    j += 2;
                    continue;
                }
                if chars[j] == '$' {
                    close = Some(j);
                    break;
                }
                j += 1;
            }
            match close {
                Some(cl) if cl > i + 1 => {
                    let content: String = chars[i + 1..cl].iter().collect();
                    let after_is_dollar = cl + 1 < n && chars[cl + 1] == '$';
                    if !after_is_dollar && looks_like_math_expression(&content) {
                        flush(&mut buf, &mut segs);
                        segs.push(MathSegment::Math {
                            tex: content,
                            display: false,
                        });
                        prev_is_dollar = false;
                    } else {
                        // 整对作普通文本并跳过（规格：闭后跟 $ 或
                        // 内容不合启发式时不成式）。
                        for k in i..=cl {
                            buf.push(chars[k]);
                        }
                        prev_is_dollar = true;
                    }
                    i = cl + 1;
                    continue;
                }
                _ => {
                    buf.push('$');
                    prev_is_dollar = true;
                    i += 1;
                    continue;
                }
            }
        }
        buf.push(c);
        prev_is_dollar = c == '$';
        i += 1;
    }
    flush(&mut buf, &mut segs);
    segs
}

// ================= 错误 =================

/// 渲染硬错误：公式整体无法解析，调用方应整式回退红色原码。
/// 未知命令不在此列（式内红色呈现，见 Node::Unknown）。
#[derive(Clone, Debug, PartialEq)]
pub enum MathError {
    /// 花括号不配平（多余的 } 或 { 未闭合）。
    UnbalancedBrace,
    /// 命令缺少必需参数。
    MissingArgument(&'static str),
    /// 同一底式重复上标或下标（^/^、_/_）。
    DoubleScript,
    /// \left 与 \right 不配对。
    UnmatchedLeftRight,
    /// \left/\right 后的定界符非法。
    BadDelimiter(String),
    /// \begin 与 \end 名称不一致。
    EnvMismatch { begin: String, end: String },
    /// \begin 后缺少 \end。
    MissingEnd(String),
    /// 不支持的环境名。
    UnknownEnv(String),
    /// 嵌套层级过深（防病理输入爆栈）。
    TooDeep,
}

impl fmt::Display for MathError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MathError::UnbalancedBrace => write!(f, "unbalanced braces"),
            MathError::MissingArgument(cmd) => write!(f, "missing argument for \\{cmd}"),
            MathError::DoubleScript => write!(f, "double superscript/subscript"),
            MathError::UnmatchedLeftRight => write!(f, "unmatched \\left/\\right"),
            MathError::BadDelimiter(d) => write!(f, "bad delimiter: {d}"),
            MathError::EnvMismatch { begin, end } => {
                write!(f, "environment mismatch: \\begin{{{begin}}} vs \\end{{{end}}}")
            }
            MathError::MissingEnd(name) => write!(f, "missing \\end{{{name}}}"),
            MathError::UnknownEnv(name) => write!(f, "unknown environment: {name}"),
            MathError::TooDeep => write!(f, "nesting too deep"),
        }
    }
}

impl std::error::Error for MathError {}

// ================= 词法 =================

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    /// 控制词（\frac）或控制符（\, \\ \{ 等，名为单字符）。
    Ctrl(String),
    /// \text 家族：名称 + 花括号内的原始文本（词法期整段捕获，
    /// 因为文本模式不按数学规则分词）。
    CtrlText(String, String),
    LBrace,
    RBrace,
    Sup,
    Sub,
    Amp,
    Char(char),
}

const TEXT_CMDS: &[&str] = &["text", "textbf", "textit", "textrm", "textsf", "texttt", "intertext"];

fn lex(src: &str) -> Vec<Tok> {
    let chars: Vec<char> = src.chars().collect();
    let n = chars.len();
    let mut toks = Vec::new();
    let mut i = 0;
    while i < n {
        let c = chars[i];
        match c {
            ' ' | '\t' | '\n' | '\r' => {
                i += 1;
            }
            '\\' => {
                if i + 1 < n && chars[i + 1].is_ascii_alphabetic() {
                    let mut j = i + 1;
                    while j < n && chars[j].is_ascii_alphabetic() {
                        j += 1;
                    }
                    let name: String = chars[i + 1..j].iter().collect();
                    if TEXT_CMDS.contains(&name.as_str()) {
                        let mut k = j;
                        while k < n && matches!(chars[k], ' ' | '\t' | '\n') {
                            k += 1;
                        }
                        if k < n && chars[k] == '{' {
                            // 平衡捕获原始文本（\{ \} 不计层级）。
                            let mut depth = 0i32;
                            let mut m = k;
                            let mut raw = String::new();
                            while m < n {
                                let ch = chars[m];
                                if ch == '\\' && m + 1 < n {
                                    raw.push(ch);
                                    raw.push(chars[m + 1]);
                                    m += 2;
                                    continue;
                                }
                                if ch == '{' {
                                    depth += 1;
                                    if depth > 1 {
                                        raw.push(ch);
                                    }
                                    m += 1;
                                    continue;
                                }
                                if ch == '}' {
                                    depth -= 1;
                                    if depth == 0 {
                                        m += 1;
                                        break;
                                    }
                                    raw.push(ch);
                                    m += 1;
                                    continue;
                                }
                                raw.push(ch);
                                m += 1;
                            }
                            toks.push(Tok::CtrlText(name, raw));
                            i = m;
                            continue;
                        }
                    }
                    toks.push(Tok::Ctrl(name));
                    i = j;
                } else if i + 1 < n {
                    toks.push(Tok::Ctrl(chars[i + 1].to_string()));
                    i += 2;
                } else {
                    toks.push(Tok::Ctrl("\\".to_string()));
                    i += 1;
                }
            }
            '{' => {
                toks.push(Tok::LBrace);
                i += 1;
            }
            '}' => {
                toks.push(Tok::RBrace);
                i += 1;
            }
            '^' => {
                toks.push(Tok::Sup);
                i += 1;
            }
            '_' => {
                toks.push(Tok::Sub);
                i += 1;
            }
            '&' => {
                toks.push(Tok::Amp);
                i += 1;
            }
            _ => {
                toks.push(Tok::Char(c));
                i += 1;
            }
        }
    }
    toks
}

/// \text 原始文本的收尾处理：转义标点还原、换行折为空格。
fn clean_text_arg(raw: &str) -> String {
    let mut out = String::new();
    let mut chars = raw.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some(n) if n.is_ascii_punctuation() => out.push(n),
                Some(n) => {
                    out.push('\\');
                    out.push(n);
                }
                None => out.push('\\'),
            }
        } else if c == '\n' || c == '\r' {
            out.push(' ');
        } else {
            out.push(c);
        }
    }
    out
}

// ================= 符号表 =================

fn greek(name: &str) -> Option<char> {
    Some(match name {
        "alpha" => 'α',
        "beta" => 'β',
        "gamma" => 'γ',
        "delta" => 'δ',
        "epsilon" => 'ε',
        "zeta" => 'ζ',
        "eta" => 'η',
        "theta" => 'θ',
        "iota" => 'ι',
        "kappa" => 'κ',
        "lambda" => 'λ',
        "mu" => 'μ',
        "nu" => 'ν',
        "xi" => 'ξ',
        "pi" => 'π',
        "rho" => 'ρ',
        "sigma" => 'σ',
        "tau" => 'τ',
        "upsilon" => 'υ',
        "phi" => 'φ',
        "chi" => 'χ',
        "psi" => 'ψ',
        "omega" => 'ω',
        "varepsilon" => 'ϵ',
        "vartheta" => 'ϑ',
        "varpi" => 'ϖ',
        "varphi" => 'ϕ',
        "varrho" => 'ϱ',
        "varsigma" => 'ς',
        "digamma" => 'ϝ',
        "varkappa" => 'ϰ',
        "Gamma" => 'Γ',
        "Delta" => 'Δ',
        "Theta" => 'Θ',
        "Lambda" => 'Λ',
        "Xi" => 'Ξ',
        "Pi" => 'Π',
        "Sigma" => 'Σ',
        "Upsilon" => 'Υ',
        "Phi" => 'Φ',
        "Psi" => 'Ψ',
        "Omega" => 'Ω',
        _ => return None,
    })
}

/// 符号命令 → (字形, 是否按标识符 mi 呈现)。false 为运算符 mo
/// （关系/二元运算/箭头/定界符，带运算符间距）。
fn symbol(name: &str) -> Option<(&'static str, bool)> {
    Some(match name {
        // 普通符号（mi）
        "infty" => ("∞", true),
        "partial" => ("∂", true),
        "nabla" => ("∇", true),
        "emptyset" => ("∅", true),
        "varnothing" => ("∅", true),
        "forall" => ("∀", true),
        "exists" => ("∃", true),
        "nexists" => ("∄", true),
        "hbar" => ("ℏ", true),
        "ell" => ("ℓ", true),
        "wp" => ("℘", true),
        "Re" => ("ℜ", true),
        "Im" => ("ℑ", true),
        "aleph" => ("ℵ", true),
        "beth" => ("ℶ", true),
        "imath" => ("ı", true),
        "jmath" => ("ȷ", true),
        "prime" => ("′", true),
        "angle" => ("∠", true),
        "measuredangle" => ("∡", true),
        "sphericalangle" => ("∢", true),
        "triangle" => ("△", true),
        "triangledown" => ("▽", true),
        "square" => ("□", true),
        "Box" => ("□", true),
        "Diamond" => ("◇", true),
        "lozenge" => ("◊", true),
        "blacksquare" => ("■", true),
        "blacktriangle" => ("▲", true),
        "blacktriangledown" => ("▼", true),
        "bigstar" => ("★", true),
        "checkmark" => ("✓", true),
        "neg" | "lnot" => ("¬", true),
        "top" => ("⊤", true),
        "bot" => ("⊥", true),
        "ldots" => ("…", true),
        "cdots" => ("⋯", true),
        "dots" => ("…", true),
        "vdots" => ("⋮", true),
        "ddots" => ("⋱", true),
        "surd" => ("√", true),
        "Finv" => ("ⅎ", true),
        "Game" => ("⅁", true),
        // 二元运算（mo）
        "pm" => ("±", false),
        "mp" => ("∓", false),
        "times" => ("×", false),
        "div" => ("÷", false),
        "cdot" => ("⋅", false),
        "ast" => ("∗", false),
        "star" => ("⋆", false),
        "circ" => ("∘", false),
        "bullet" => ("•", false),
        "diamond" => ("⋄", false),
        "oplus" => ("⊕", false),
        "ominus" => ("⊖", false),
        "otimes" => ("⊗", false),
        "odot" => ("⊙", false),
        "oslash" => ("⊘", false),
        "cup" => ("∪", false),
        "cap" => ("∩", false),
        "sqcup" => ("⊔", false),
        "sqcap" => ("⊓", false),
        "setminus" | "smallsetminus" => ("∖", false),
        "wedge" | "land" => ("∧", false),
        "vee" | "lor" => ("∨", false),
        "amalg" => ("⨿", false),
        "wr" => ("≀", false),
        "uplus" => ("⊎", false),
        "dagger" => ("†", false),
        "ddagger" => ("‡", false),
        "ltimes" => ("⋉", false),
        "rtimes" => ("⋊", false),
        "dotplus" => ("∔", false),
        "Cap" => ("⋒", false),
        "Cup" => ("⋓", false),
        "barwedge" => ("⊼", false),
        "veebar" => ("⊻", false),
        "curlywedge" => ("⋏", false),
        "curlyvee" => ("⋎", false),
        "boxplus" => ("⊞", false),
        "boxtimes" => ("⊠", false),
        "boxdot" => ("⊡", false),
        "boxminus" => ("⊟", false),
        // 关系（mo）
        "leq" | "le" => ("≤", false),
        "geq" | "ge" => ("≥", false),
        "neq" | "ne" => ("≠", false),
        "equiv" => ("≡", false),
        "approx" => ("≈", false),
        "cong" => ("≅", false),
        "sim" => ("∼", false),
        "simeq" => ("≃", false),
        "propto" => ("∝", false),
        "ll" => ("≪", false),
        "gg" => ("≫", false),
        "subset" => ("⊂", false),
        "supset" => ("⊃", false),
        "subseteq" => ("⊆", false),
        "supseteq" => ("⊇", false),
        "sqsubseteq" => ("⊑", false),
        "sqsupseteq" => ("⊒", false),
        "in" => ("∈", false),
        "notin" => ("∉", false),
        "ni" | "owns" => ("∋", false),
        "mid" => ("∣", false),
        "nmid" => ("∤", false),
        "parallel" => ("∥", false),
        "perp" => ("⊥", false),
        "bowtie" => ("⋈", false),
        "models" => ("⊨", false),
        "vdash" => ("⊢", false),
        "dashv" => ("⊣", false),
        "Vdash" => ("⊩", false),
        "Vvdash" => ("⊪", false),
        "nvdash" => ("⊬", false),
        "nvDash" => ("⊭", false),
        "nVdash" => ("⊮", false),
        "nVDash" => ("⊯", false),
        "smile" => ("⌣", false),
        "frown" => ("⌢", false),
        "asymp" => ("≍", false),
        "doteq" => ("≐", false),
        "prec" => ("≺", false),
        "succ" => ("≻", false),
        "preceq" => ("⪯", false),
        "succeq" => ("⪰", false),
        "triangleleft" => ("◃", false),
        "triangleright" => ("▹", false),
        "vartriangleleft" => ("⊲", false),
        "vartriangleright" => ("⊳", false),
        "trianglelefteq" => ("⊴", false),
        "trianglerighteq" => ("⊵", false),
        "therefore" => ("∴", false),
        "because" => ("∵", false),
        // 箭头（mo）
        "rightarrow" | "to" => ("→", false),
        "leftarrow" | "gets" => ("←", false),
        "Rightarrow" => ("⇒", false),
        "Leftarrow" => ("⇐", false),
        "leftrightarrow" => ("↔", false),
        "Leftrightarrow" => ("⇔", false),
        "mapsto" => ("↦", false),
        "longmapsto" => ("⟼", false),
        "longrightarrow" => ("⟶", false),
        "longleftarrow" => ("⟵", false),
        "Longrightarrow" => ("⟹", false),
        "Longleftarrow" => ("⟸", false),
        "uparrow" => ("↑", false),
        "downarrow" => ("↓", false),
        "Uparrow" => ("⇑", false),
        "Downarrow" => ("⇓", false),
        "updownarrow" => ("↕", false),
        "Updownarrow" => ("⇕", false),
        "nearrow" => ("↗", false),
        "searrow" => ("↘", false),
        "swarrow" => ("↙", false),
        "nwarrow" => ("↖", false),
        "hookrightarrow" => ("↪", false),
        "hookleftarrow" => ("↩", false),
        "rightharpoonup" => ("⇀", false),
        "rightharpoondown" => ("⇁", false),
        "leftharpoonup" => ("↼", false),
        "leftharpoondown" => ("↽", false),
        "rightleftharpoons" => ("⇌", false),
        "leftrightharpoons" => ("⇋", false),
        "twoheadrightarrow" => ("↠", false),
        "rightarrowtail" => ("↣", false),
        "implies" => ("⇒", false),
        "impliedby" => ("⇐", false),
        "iff" => ("⇔", false),
        "nrightarrow" => ("↛", false),
        "nleftarrow" => ("↚", false),
        "nRightarrow" => ("⇏", false),
        "nLeftarrow" => ("⇍", false),
        "nleftrightarrow" => ("↮", false),
        "nLeftrightarrow" => ("⇎", false),
        // 定界符形符号（mo）
        "langle" => ("⟨", false),
        "rangle" => ("⟩", false),
        "lfloor" => ("⌊", false),
        "rfloor" => ("⌋", false),
        "lceil" => ("⌈", false),
        "rceil" => ("⌉", false),
        "lbrace" => ("{", false),
        "rbrace" => ("}", false),
        "lvert" | "rvert" | "vert" => ("|", false),
        "lVert" | "rVert" | "Vert" => ("‖", false),
        "backslash" => ("∖", false),
        "ulcorner" => ("⌜", false),
        "urcorner" => ("⌝", false),
        "llcorner" => ("⌞", false),
        "lrcorner" => ("⌟", false),
        "diagup" => ("╱", false),
        "diagdown" => ("╲", false),
        _ => return None,
    })
}

/// 大运算符 → (字形, display 时上下标是否默认走限值位)。
fn big_op(name: &str) -> Option<(&'static str, bool)> {
    Some(match name {
        "sum" => ("∑", true),
        "prod" => ("∏", true),
        "coprod" => ("∐", true),
        "bigcup" => ("⋃", true),
        "bigcap" => ("⋂", true),
        "bigvee" => ("⋁", true),
        "bigwedge" => ("⋀", true),
        "bigoplus" => ("⨁", true),
        "bigotimes" => ("⨂", true),
        "bigodot" => ("⨀", true),
        "biguplus" => ("⨄", true),
        "bigsqcup" => ("⨆", true),
        "int" => ("∫", false),
        "iint" => ("∬", false),
        "iiint" => ("∭", false),
        "oint" => ("∮", false),
        "oiint" => ("∯", false),
        "oiiint" => ("∰", false),
        _ => return None,
    })
}

/// 函数名（直立体）→ display 时是否带限值位下标。
fn func_op(name: &str) -> Option<bool> {
    Some(match name {
        "lim" | "liminf" | "limsup" | "max" | "min" | "sup" | "inf" | "det" | "gcd" | "Pr"
        | "projlim" | "injlim" => true,
        "sin" | "cos" | "tan" | "cot" | "sec" | "csc" | "sinh" | "cosh" | "tanh" | "coth"
        | "arcsin" | "arccos" | "arctan" | "arg" | "deg" | "dim" | "exp" | "hom" | "ker"
        | "lg" | "ln" | "log" => false,
        _ => return None,
    })
}

/// 重音命令 → (字形, 是否在下方, 是否重音类)。
fn accent(name: &str) -> Option<(&'static str, bool, bool)> {
    Some(match name {
        "hat" | "widehat" => ("ˆ", false, true),
        "check" => ("ˇ", false, true),
        "tilde" | "widetilde" => ("˜", false, true),
        "acute" => ("´", false, true),
        "grave" => ("`", false, true),
        "dot" => ("˙", false, true),
        "ddot" => ("¨", false, true),
        "bar" => ("¯", false, true),
        "vec" => ("→", false, true),
        "mathring" => ("˚", false, true),
        "breve" => ("˘", false, true),
        "overline" => ("‾", false, false),
        "underline" => ("_", true, false),
        "overrightarrow" => ("→", false, false),
        "overleftarrow" => ("←", false, false),
        "overleftrightarrow" => ("↔", false, false),
        "underrightarrow" => ("→", true, false),
        "underleftarrow" => ("←", true, false),
        "overbrace" => ("⏞", false, false),
        "underbrace" => ("⏟", true, false),
        "overparen" => ("⏜", false, false),
        "underparen" => ("⏝", true, false),
        _ => return None,
    })
}

/// \not 可组合的否定字形（按被否定命令名查）。
fn negated_symbol(name: &str) -> Option<&'static str> {
    Some(match name {
        "in" => "∉",
        "exists" => "∄",
        "mid" => "∤",
        "parallel" => "∦",
        "subset" => "⊄",
        "supset" => "⊅",
        "subseteq" => "⊈",
        "supseteq" => "⊉",
        "vdash" => "⊬",
        "models" => "⊭",
        "Vdash" => "⊮",
        "equiv" => "≢",
        "sim" => "≁",
        "cong" => "≇",
        "approx" => "≉",
        "asymp" => "≭",
        "prec" => "⊀",
        "succ" => "⊁",
        "preceq" => "⪯̸",
        "succeq" => "⪰̸",
        "triangleleft" => "⋪",
        "triangleright" => "⋫",
        "trianglelefteq" => "⋬",
        "trianglerighteq" => "⋭",
        "rightarrow" => "↛",
        "leftarrow" => "↚",
        "Rightarrow" => "⇏",
        "Leftarrow" => "⇍",
        "leftrightarrow" => "↮",
        "Leftrightarrow" => "⇎",
        "leq" | "le" => "≰",
        "geq" | "ge" => "≱",
        "lesssim" => "≴",
        "gtrsim" => "≵",
        _ => return None,
    })
}

/// \mathbb 常用字母的双线体字形（其余字母走 mathvariant）。
fn bb_glyph(c: char) -> Option<char> {
    Some(match c {
        'C' => 'ℂ',
        'H' => 'ℍ',
        'N' => 'ℕ',
        'P' => 'ℙ',
        'Q' => 'ℚ',
        'R' => 'ℝ',
        'Z' => 'ℤ',
        _ => return None,
    })
}

/// \mathcal 常用字母的花体字形（Letterlike 区，其余走 mathvariant）。
fn cal_glyph(c: char) -> Option<char> {
    Some(match c {
        'B' => 'ℬ',
        'E' => 'ℰ',
        'F' => 'ℱ',
        'H' => 'ℋ',
        'I' => 'ℐ',
        'L' => 'ℒ',
        'M' => 'ℳ',
        'R' => 'ℛ',
        'e' => 'ℯ',
        'g' => 'ℊ',
        'o' => 'ℴ',
        _ => return None,
    })
}

/// \mathfrak 常用字母的哥特体字形（其余走 mathvariant）。
fn frak_glyph(c: char) -> Option<char> {
    if c.is_ascii_lowercase() {
        // U+1D51E..U+1D537 与 a..z 连续对应。
        return char::from_u32(0x1D51E + (c as u32 - 'a' as u32));
    }
    Some(match c {
        'C' => 'ℭ',
        'H' => 'ℌ',
        'I' => 'ℑ',
        'R' => 'ℜ',
        'Z' => 'ℨ',
        _ => return None,
    })
}

// ================= 解析树 =================

#[derive(Clone, Debug, PartialEq)]
enum FracStyle {
    Normal,
    Display,
    Text,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Fence {
    None,
    Paren,
    Bracket,
    Brace,
}

/// \big 家族定界符的形态（间距口径）：开 / 合 / 中。
#[derive(Clone, Copy, Debug, PartialEq)]
enum DelimForm {
    Open,
    Close,
    Mid,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum EnvKind {
    Matrix,
    PMatrix,
    BMatrix,
    BraceMatrix,
    VMatrix,
    VVMatrix,
    Cases,
    RCases,
    Aligned,
    Gather,
    Array,
    SmallMatrix,
}

#[derive(Clone, Debug, PartialEq)]
enum Node {
    Row(Vec<Node>),
    Ident(String),
    Num(String),
    Op(String),
    /// CJK 等非 ASCII 字母的连续段（以 mtext 呈现）。
    TextRun(String),
    Sym {
        glyph: String,
        mi: bool,
    },
    Func {
        name: String,
        limits: bool,
    },
    BigOp {
        glyph: String,
        limits: bool,
    },
    Frac {
        num: Box<Node>,
        den: Box<Node>,
        style: FracStyle,
        line: bool,
        fence: Fence,
    },
    Sqrt {
        index: Option<Box<Node>>,
        body: Box<Node>,
    },
    Scripted {
        base: Box<Node>,
        sub: Option<Box<Node>>,
        sup: Option<Box<Node>>,
    },
    /// 限值位脚本（display 大运算符/函数的 munder/mover 形态）。
    Limited {
        base: Box<Node>,
        sub: Option<Box<Node>>,
        sup: Option<Box<Node>>,
    },
    Delimited {
        open: Option<String>,
        body: Box<Node>,
        close: Option<String>,
    },
    Accent {
        glyph: String,
        body: Box<Node>,
        under: bool,
        accent: bool,
    },
    Env {
        kind: EnvKind,
        rows: Vec<Vec<Node>>,
        col_align: String,
        /// 每个行间隙（0 = 首行前，rows.len() = 末行后）的 \hline
        /// 条数（解析时记录语义，发射时物化为 rowlines/空行）。
        hlines: Vec<u8>,
        /// 每个列间隙（0 = 首列前）的竖线条数（array 列规格的 |）。
        vlines: Vec<u8>,
        /// 行间隙的 \\[dim] 额外间距（em），按间隙下标。
        row_extra: Vec<f32>,
    },
    /// \big 家族的定尺寸定界符：level 1..=4 对应
    /// \big / \Big / \bigg / \Bigg（量测口径见发射处），
    /// form 决定开/合/中的间距形态。
    SizedDelim {
        glyph: String,
        level: u8,
        form: DelimForm,
    },
    Styled {
        variant: &'static str,
        body: Box<Node>,
    },
    TextStyled {
        variant: Option<&'static str>,
        text: String,
    },
    Colored {
        color: String,
        body: Box<Node>,
    },
    DisplayStyle {
        display: Option<bool>,
        script_level: Option<u8>,
        body: Box<Node>,
    },
    Space(String),
    Phantom(Box<Node>),
    Enclosed {
        notation: &'static str,
        body: Box<Node>,
    },
    XArrow {
        glyph: String,
        over: Option<Box<Node>>,
        under: Option<Box<Node>>,
    },
    Tag(Box<Node>),
    /// 未知命令：式内红色呈现并继续（规格见模块头）。
    Unknown(String),
    Empty,
    LineBreak,
}

/// \big 家族命令名 → (尺寸档 1..=4, 形态)。无后缀的
/// \big / \Big / \bigg / \Bigg 按开定界符的间距口径（与原版
/// 渲染器的 mopen 口径一致）。
fn delim_size_form(name: &str) -> (u8, DelimForm) {
    let form = if name.ends_with('l') {
        DelimForm::Open
    } else if name.ends_with('r') {
        DelimForm::Close
    } else if name.ends_with('m') {
        DelimForm::Mid
    } else {
        DelimForm::Open
    };
    let level = match name.trim_end_matches(['l', 'r', 'm']) {
        "Bigg" => 4,
        "bigg" => 3,
        "Big" => 2,
        _ => 1,
    };
    (level, form)
}

/// 间隙线数计数表（hlines/vlines）的单点累加，上限 3 条。
fn bump_gap(v: &mut Vec<u8>, gap: usize) {
    if v.len() <= gap {
        v.resize(gap + 1, 0);
    }
    v[gap] = (v[gap] + 1).min(3);
}

// ================= 解析器 =================

const MAX_DEPTH: usize = 64;

struct Parser {
    toks: Vec<Tok>,
    pos: usize,
    depth: usize,
    display: bool,
}

impl Parser {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos)
    }

    fn next(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.pos).cloned();
        if t.is_some() {
            self.pos += 1;
        }
        t
    }

    fn peek_ctrl(&self, name: &str) -> bool {
        matches!(self.peek(), Some(Tok::Ctrl(n)) if n == name)
    }

    fn peek_char(&self, c: char) -> bool {
        matches!(self.peek(), Some(Tok::Char(x)) if *x == c)
    }

    fn parse_all(&mut self) -> Result<Vec<Node>, MathError> {
        let nodes = self.parse_expr(false, false, false)?;
        if self.pos != self.toks.len() {
            return Err(MathError::UnbalancedBrace);
        }
        Ok(nodes)
    }

    /// 表达式解析。stop_brace/stop_cell/stop_right 控制终止符：
    /// }（组内）、& 与 \\ 与 \end（环境单元格内）、\right。
    fn parse_expr(
        &mut self,
        stop_brace: bool,
        stop_cell: bool,
        stop_right: bool,
    ) -> Result<Vec<Node>, MathError> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            return Err(MathError::TooDeep);
        }
        let result = self.parse_expr_inner(stop_brace, stop_cell, stop_right);
        self.depth -= 1;
        result
    }

    fn parse_expr_inner(
        &mut self,
        stop_brace: bool,
        stop_cell: bool,
        stop_right: bool,
    ) -> Result<Vec<Node>, MathError> {
        let mut nodes: Vec<Node> = Vec::new();
        loop {
            match self.peek().cloned() {
                None => break,
                Some(Tok::RBrace) => {
                    if stop_brace {
                        break;
                    }
                    return Err(MathError::UnbalancedBrace);
                }
                Some(Tok::Amp) if stop_cell => break,
                Some(Tok::Ctrl(ref n))
                    if stop_cell && (n == "\\" || n == "cr" || n == "end" || n == "hline") =>
                {
                    break
                }
                Some(Tok::Ctrl(ref n)) if n == "right" => {
                    if stop_right {
                        break;
                    }
                    return Err(MathError::UnmatchedLeftRight);
                }
                // 中缀 \over 家族：左侧已解析部分作分子。
                Some(Tok::Ctrl(ref n))
                    if matches!(n.as_str(), "over" | "atop" | "choose" | "brace" | "brack") =>
                {
                    let kind = n.clone();
                    self.next();
                    let right = self.parse_expr(stop_brace, stop_cell, stop_right)?;
                    let (line, fence) = match kind.as_str() {
                        "over" => (true, Fence::None),
                        "atop" => (false, Fence::None),
                        "choose" => (false, Fence::Paren),
                        "brace" => (false, Fence::Brace),
                        _ => (false, Fence::Bracket),
                    };
                    return Ok(vec![Node::Frac {
                        num: Box::new(Node::Row(std::mem::take(&mut nodes))),
                        den: Box::new(Node::Row(right)),
                        style: FracStyle::Normal,
                        line,
                        fence,
                    }]);
                }
                // \color{…} 与文体开关：作用域为当前组剩余部分。
                Some(Tok::Ctrl(ref n)) if n == "color" => {
                    self.next();
                    let color = self.parse_raw_group("color")?;
                    let rest = self.parse_expr(stop_brace, stop_cell, stop_right)?;
                    nodes.push(Node::Colored {
                        color,
                        body: Box::new(Node::Row(rest)),
                    });
                    return Ok(nodes);
                }
                Some(Tok::Ctrl(ref n))
                    if matches!(
                        n.as_str(),
                        "displaystyle" | "textstyle" | "scriptstyle" | "scriptscriptstyle"
                    ) =>
                {
                    let (display, level) = match n.as_str() {
                        "displaystyle" => (Some(true), Some(0)),
                        "textstyle" => (Some(false), Some(0)),
                        "scriptstyle" => (Some(false), Some(1)),
                        _ => (Some(false), Some(2)),
                    };
                    self.next();
                    let rest = self.parse_expr(stop_brace, stop_cell, stop_right)?;
                    nodes.push(Node::DisplayStyle {
                        display,
                        script_level: level,
                        body: Box::new(Node::Row(rest)),
                    });
                    return Ok(nodes);
                }
                Some(Tok::Sup) | Some(Tok::Sub) => {
                    // 无底式的脚本挂到空底式上。
                    let n = self.parse_postfix(Node::Empty)?;
                    nodes.push(n);
                }
                Some(_) => {
                    let atom = self.parse_atom()?;
                    let n = self.parse_postfix(atom)?;
                    nodes.push(n);
                }
            }
        }
        Ok(nodes)
    }

    /// 单个参数（组或单个记号）。TeX 数学字段语义：无花括号时
    /// 只取一个记号（\frac12 即 \frac{1}{2}、x^12 即 x^1·2）。
    fn parse_arg(&mut self) -> Result<Node, MathError> {
        match self.peek().cloned() {
            Some(Tok::LBrace) => {
                self.next();
                let inner = self.parse_expr(true, false, false)?;
                match self.next() {
                    Some(Tok::RBrace) => Ok(Node::Row(inner)),
                    _ => Err(MathError::UnbalancedBrace),
                }
            }
            Some(_) => self.parse_atom_single(),
            None => Err(MathError::MissingArgument("expression")),
        }
    }

    /// 原子解析（参数位专用：数字/文本不做连续段合并）。
    fn parse_atom_single(&mut self) -> Result<Node, MathError> {
        match self.peek().cloned() {
            Some(Tok::Char(c)) => {
                self.next();
                Ok(char_node(c, true))
            }
            _ => self.parse_atom(),
        }
    }

    fn parse_atom(&mut self) -> Result<Node, MathError> {
        match self.next() {
            None => Err(MathError::MissingArgument("expression")),
            Some(Tok::LBrace) => {
                let inner = self.parse_expr(true, false, false)?;
                match self.next() {
                    Some(Tok::RBrace) => Ok(Node::Row(inner)),
                    _ => Err(MathError::UnbalancedBrace),
                }
            }
            Some(Tok::Char(c)) => Ok(self.char_run(c)),
            Some(Tok::CtrlText(name, raw)) => Ok(text_styled_node(&name, &raw)),
            Some(Tok::Ctrl(name)) => self.parse_command(&name),
            Some(Tok::Sup) | Some(Tok::Sub) => Err(MathError::MissingArgument("base")),
            Some(Tok::Amp) => Ok(Node::Op("&".to_string())),
            Some(Tok::RBrace) => Err(MathError::UnbalancedBrace),
        }
    }

    /// 普通字符的段合并：数字串成数、非 ASCII 字母串成文本段、
    /// ASCII 字母逐个成标识符（数学惯例：xy 是 x·y 而非一个名）。
    fn char_run(&mut self, first: char) -> Node {
        if first.is_ascii_digit() {
            let mut s = String::new();
            s.push(first);
            loop {
                match self.peek().cloned() {
                    Some(Tok::Char(d)) if d.is_ascii_digit() => {
                        s.push(d);
                        self.next();
                    }
                    Some(Tok::Char('.')) => {
                        // 小数点须后随数字才并入。
                        let save = self.pos;
                        self.next();
                        match self.peek().cloned() {
                            Some(Tok::Char(d)) if d.is_ascii_digit() => {
                                s.push('.');
                                s.push(d);
                                self.next();
                            }
                            _ => {
                                self.pos = save;
                                break;
                            }
                        }
                    }
                    _ => break,
                }
            }
            return Node::Num(s);
        }
        if is_text_char(first) {
            let mut s = String::new();
            s.push(first);
            while let Some(Tok::Char(c)) = self.peek().cloned() {
                if is_text_char(c) {
                    s.push(c);
                    self.next();
                } else {
                    break;
                }
            }
            return Node::TextRun(s);
        }
        char_node(first, false)
    }

    /// 脚本（^/_/撇号）与限值修饰的后缀解析。
    fn parse_postfix(&mut self, base: Node) -> Result<Node, MathError> {
        let mut limits_mode: Option<bool> = None;
        if matches!(base, Node::BigOp { .. } | Node::Func { .. }) {
            if self.peek_ctrl("limits") {
                self.next();
                limits_mode = Some(true);
            } else if self.peek_ctrl("nolimits") || self.peek_ctrl("displaylimits") {
                let display_only = self.peek_ctrl("displaylimits");
                self.next();
                limits_mode = Some(if display_only { self.display } else { false });
            }
        }
        let mut sub: Option<Node> = None;
        let mut sup: Option<Node> = None;
        loop {
            match self.peek().cloned() {
                Some(Tok::Sup) => {
                    if sup.is_some() {
                        return Err(MathError::DoubleScript);
                    }
                    self.next();
                    sup = Some(self.parse_arg()?);
                }
                Some(Tok::Sub) => {
                    if sub.is_some() {
                        return Err(MathError::DoubleScript);
                    }
                    self.next();
                    sub = Some(self.parse_arg()?);
                }
                Some(Tok::Char('\'')) => {
                    let mut count = 0usize;
                    while self.peek_char('\'') {
                        self.next();
                        count += 1;
                    }
                    let primes = Node::Op("′".repeat(count));
                    sup = Some(match sup {
                        None => primes,
                        Some(s) => Node::Row(vec![s, primes]),
                    });
                }
                _ => break,
            }
        }
        if sub.is_none() && sup.is_none() {
            return Ok(base);
        }
        let default_limits = match &base {
            Node::BigOp { limits, .. } => *limits,
            Node::Func { limits, .. } => *limits,
            _ => false,
        };
        let use_limits = limits_mode.unwrap_or(self.display && default_limits)
            && matches!(base, Node::BigOp { .. } | Node::Func { .. });
        if use_limits {
            Ok(Node::Limited {
                base: Box::new(base),
                sub: sub.map(Box::new),
                sup: sup.map(Box::new),
            })
        } else {
            Ok(Node::Scripted {
                base: Box::new(base),
                sub: sub.map(Box::new),
                sup: sup.map(Box::new),
            })
        }
    }

    /// 读取一个花括号原始字符串参数（颜色名、环境名等）。
    fn parse_raw_group(&mut self, cmd: &'static str) -> Result<String, MathError> {
        match self.next() {
            Some(Tok::LBrace) => {}
            _ => return Err(MathError::MissingArgument(cmd)),
        }
        let mut s = String::new();
        loop {
            match self.next() {
                Some(Tok::RBrace) => return Ok(s),
                Some(Tok::Char(c)) => s.push(c),
                Some(Tok::Ctrl(n)) => {
                    s.push('\\');
                    s.push_str(&n);
                }
                Some(_) => {}
                None => return Err(MathError::UnbalancedBrace),
            }
        }
    }

    /// \left / \right 后的定界符。
    fn parse_delimiter(&mut self) -> Result<Option<String>, MathError> {
        match self.next() {
            Some(Tok::Char('.')) => Ok(None),
            Some(Tok::Char(c)) if "()[]|/".contains(c) => Ok(Some(c.to_string())),
            Some(Tok::Ctrl(n)) => {
                let g = match n.as_str() {
                    "{" => Some("{".to_string()),
                    "}" => Some("}".to_string()),
                    "|" => Some("‖".to_string()),
                    "vert" | "lvert" | "rvert" => Some("|".to_string()),
                    "Vert" | "lVert" | "rVert" => Some("‖".to_string()),
                    "backslash" => Some("∖".to_string()),
                    _ => match symbol(&n) {
                        Some((glyph, _)) => Some(glyph.to_string()),
                        None => return Err(MathError::BadDelimiter(n)),
                    },
                };
                Ok(g)
            }
            Some(Tok::LBrace) => Ok(Some("{".to_string())),
            Some(Tok::RBrace) => Ok(Some("}".to_string())),
            _ => Err(MathError::BadDelimiter(String::new())),
        }
    }

    fn parse_command(&mut self, name: &str) -> Result<Node, MathError> {
        // 分式家族
        match name {
            "frac" | "dfrac" | "tfrac" | "cfrac" | "binom" | "dbinom" | "tbinom" => {
                let num = self.parse_arg()?;
                let den = self.parse_arg()?;
                let (style, line, fence) = match name {
                    "dfrac" | "cfrac" => (FracStyle::Display, true, Fence::None),
                    "tfrac" => (FracStyle::Text, true, Fence::None),
                    "binom" => (FracStyle::Normal, false, Fence::Paren),
                    "dbinom" => (FracStyle::Display, false, Fence::Paren),
                    "tbinom" => (FracStyle::Text, false, Fence::Paren),
                    _ => (FracStyle::Normal, true, Fence::None),
                };
                return Ok(Node::Frac {
                    num: Box::new(num),
                    den: Box::new(den),
                    style,
                    line,
                    fence,
                });
            }
            "sqrt" => {
                let index = if self.peek_char('[') {
                    self.next();
                    let inner = self.parse_until_rbracket()?;
                    Some(Box::new(Node::Row(inner)))
                } else {
                    None
                };
                let body = self.parse_arg()?;
                return Ok(Node::Sqrt {
                    index,
                    body: Box::new(body),
                });
            }
            "left" => {
                let open = self.parse_delimiter()?;
                let body = self.parse_expr(false, false, true)?;
                if !self.peek_ctrl("right") {
                    return Err(MathError::UnmatchedLeftRight);
                }
                self.next();
                let close = self.parse_delimiter()?;
                return Ok(Node::Delimited {
                    open,
                    body: Box::new(Node::Row(body)),
                    close,
                });
            }
            "right" => return Err(MathError::UnmatchedLeftRight),
            "begin" => return self.parse_env(),
            "end" => return Err(MathError::MissingEnd(String::new())),
            "overline" | "underline" | "overbrace" | "underbrace" | "widehat" | "widetilde"
            | "overrightarrow" | "overleftarrow" | "overleftrightarrow" | "underrightarrow"
            | "underleftarrow" | "overparen" | "underparen" | "hat" | "check" | "tilde"
            | "acute" | "grave" | "dot" | "ddot" | "bar" | "vec" | "mathring" | "breve" => {
                let (glyph, under, is_accent) = accent(name).unwrap();
                let body = self.parse_arg()?;
                return Ok(Node::Accent {
                    glyph: glyph.to_string(),
                    body: Box::new(body),
                    under,
                    accent: is_accent,
                });
            }
            "overset" | "stackrel" => {
                let over = self.parse_arg()?;
                let base = self.parse_arg()?;
                return Ok(Node::Limited {
                    base: Box::new(base),
                    sub: None,
                    sup: Some(Box::new(over)),
                });
            }
            "underset" => {
                let under = self.parse_arg()?;
                let base = self.parse_arg()?;
                return Ok(Node::Limited {
                    base: Box::new(base),
                    sub: Some(Box::new(under)),
                    sup: None,
                });
            }
            "xrightarrow" | "xleftarrow" => {
                let under = if self.peek_char('[') {
                    self.next();
                    Some(Box::new(Node::Row(self.parse_until_rbracket()?)))
                } else {
                    None
                };
                let over = self.parse_arg()?;
                return Ok(Node::XArrow {
                    glyph: if name == "xrightarrow" { "→" } else { "←" }.to_string(),
                    over: Some(Box::new(over)),
                    under,
                });
            }
            "boxed" => {
                let body = self.parse_arg()?;
                return Ok(Node::Enclosed {
                    notation: "box",
                    body: Box::new(body),
                });
            }
            "cancel" => {
                let body = self.parse_arg()?;
                return Ok(Node::Enclosed {
                    notation: "updiagonalstrike",
                    body: Box::new(body),
                });
            }
            "bcancel" => {
                let body = self.parse_arg()?;
                return Ok(Node::Enclosed {
                    notation: "downdiagonalstrike",
                    body: Box::new(body),
                });
            }
            "xcancel" => {
                let body = self.parse_arg()?;
                return Ok(Node::Enclosed {
                    notation: "crossdiagonalstrike",
                    body: Box::new(body),
                });
            }
            "mathbf" | "mathbfit" | "boldsymbol" | "bm" | "mathit" | "mathrm" | "mathsf"
            | "mathtt" | "mathbb" | "Bbb" | "mathcal" | "mathfrak" | "mathscr" | "mathnormal" => {
                let arg = self.parse_arg()?;
                return Ok(styled_node(name, arg));
            }
            "operatorname" => {
                let star = if self.peek_char('*') {
                    self.next();
                    true
                } else {
                    false
                };
                let text = self.parse_plain_group()?;
                return Ok(Node::Func {
                    name: text,
                    limits: star,
                });
            }
            "text" | "textbf" | "textit" | "textrm" | "textsf" | "texttt" | "intertext" => {
                // 无花括号的退化形态：取一个参数并按纯文本呈现。
                let arg = self.parse_arg()?;
                let text = node_plain_text(&arg);
                return Ok(text_styled_node(name, &text));
            }
            "color" => {
                // 原子位（脚本参数等）的 \color：只作用于下一个原子。
                let color = self.parse_raw_group("color")?;
                let body = self.parse_arg()?;
                return Ok(Node::Colored {
                    color,
                    body: Box::new(body),
                });
            }
            "displaystyle" | "textstyle" | "scriptstyle" | "scriptscriptstyle" => {
                return Ok(Node::Empty);
            }
            "limits" | "nolimits" | "displaylimits" => return Ok(Node::Empty),
            "hline" | "cr" => return Ok(Node::Empty),
            "cline" => {
                let _ = self.parse_raw_group("cline");
                return Ok(Node::Empty);
            }
            "substack" => {
                return self.parse_substack();
            }
            "pmod" => {
                let body = self.parse_arg()?;
                return Ok(Node::Row(vec![
                    Node::Op("(".to_string()),
                    Node::Func {
                        name: "mod".to_string(),
                        limits: false,
                    },
                    Node::Space("0.25em".to_string()),
                    body,
                    Node::Op(")".to_string()),
                ]));
            }
            "bmod" => {
                return Ok(Node::Func {
                    name: "mod".to_string(),
                    limits: false,
                });
            }
            "pod" => {
                let body = self.parse_arg()?;
                return Ok(Node::Row(vec![
                    Node::Op("(".to_string()),
                    body,
                    Node::Op(")".to_string()),
                ]));
            }
            "tag" => {
                let body = self.parse_arg()?;
                return Ok(Node::Tag(Box::new(body)));
            }
            "label" => {
                let _ = self.parse_raw_group("label");
                return Ok(Node::Empty);
            }
            "ref" | "eqref" => {
                let text = self.parse_raw_group("ref")?;
                let text = if name == "eqref" {
                    format!("({text})")
                } else {
                    text
                };
                return Ok(Node::TextRun(text));
            }
            "not" => {
                return self.parse_not();
            }
            "phantom" | "hphantom" | "vphantom" => {
                let body = self.parse_arg()?;
                return Ok(Node::Phantom(Box::new(body)));
            }
            "hspace" | "kern" | "mkern" | "mspace" => {
                let raw = self.parse_raw_group("hspace")?;
                return Ok(Node::Space(dim_to_em(&raw)));
            }
            "bigl" | "bigr" | "Bigl" | "Bigr" | "biggl" | "biggr" | "Biggl" | "Biggr" | "big"
            | "Big" | "bigg" | "Bigg" | "bigm" | "Bigm" | "biggm" | "Biggm" => {
                let (level, form) = delim_size_form(name);
                let d = self.parse_delimiter()?;
                return Ok(Node::SizedDelim {
                    glyph: d.unwrap_or_default(),
                    level,
                    form,
                });
            }
            "over" | "atop" | "choose" | "brace" | "brack" => {
                // 中缀命令出现在参数位（如 \frac 的参数里）时按
                // 表达式层语义不成立，作未知命令呈现。
                return Ok(Node::Unknown(name.to_string()));
            }
            _ => {}
        }
        // 间距控制符与命令
        match name {
            "," => return Ok(Node::Space("0.167em".to_string())),
            ":" => return Ok(Node::Space("0.222em".to_string())),
            ";" => return Ok(Node::Space("0.278em".to_string())),
            " " => return Ok(Node::Space("0.25em".to_string())),
            "!" => return Ok(Node::Space("-0.167em".to_string())),
            "quad" => return Ok(Node::Space("1em".to_string())),
            "qquad" => return Ok(Node::Space("2em".to_string())),
            "\\" => return Ok(Node::LineBreak),
            "{" => return Ok(Node::Op("{".to_string())),
            "}" => return Ok(Node::Op("}".to_string())),
            "|" => return Ok(Node::Op("‖".to_string())),
            "$" => return Ok(Node::Op("$".to_string())),
            "%" => return Ok(Node::Op("%".to_string())),
            "&" => return Ok(Node::Op("&".to_string())),
            "#" => return Ok(Node::Op("#".to_string())),
            "_" => return Ok(Node::Op("_".to_string())),
            _ => {}
        }
        if let Some(g) = greek(name) {
            return Ok(Node::Sym {
                glyph: g.to_string(),
                mi: true,
            });
        }
        if let Some((glyph, limits)) = big_op(name) {
            return Ok(Node::BigOp {
                glyph: glyph.to_string(),
                limits,
            });
        }
        if let Some(limits) = func_op(name) {
            return Ok(Node::Func {
                name: name.to_string(),
                limits,
            });
        }
        if let Some((glyph, mi)) = symbol(name) {
            return Ok(Node::Sym {
                glyph: glyph.to_string(),
                mi,
            });
        }
        Ok(Node::Unknown(name.to_string()))
    }

    /// \not\cmd：优先查否定字形表，否则在原字形后叠加 U+0338。
    fn parse_not(&mut self) -> Result<Node, MathError> {
        match self.peek().cloned() {
            Some(Tok::Ctrl(n)) => {
                if let Some(g) = negated_symbol(&n) {
                    self.next();
                    return Ok(Node::Sym {
                        glyph: g.to_string(),
                        mi: false,
                    });
                }
                if let Some((glyph, mi)) = symbol(&n) {
                    self.next();
                    return Ok(Node::Sym {
                        glyph: format!("{glyph}\u{338}"),
                        mi,
                    });
                }
                if let Some(g) = greek(&n) {
                    self.next();
                    return Ok(Node::Sym {
                        glyph: format!("{g}\u{338}"),
                        mi: true,
                    });
                }
                let atom = self.parse_atom()?;
                Ok(atom)
            }
            Some(Tok::Char('=')) => {
                self.next();
                Ok(Node::Sym {
                    glyph: "≠".to_string(),
                    mi: false,
                })
            }
            _ => {
                let atom = self.parse_atom()?;
                Ok(atom)
            }
        }
    }

    /// 解析到 ] 为止的表达式（\sqrt[…]、\xrightarrow[…] 用）。
    fn parse_until_rbracket(&mut self) -> Result<Vec<Node>, MathError> {
        let mut nodes = Vec::new();
        loop {
            match self.peek().cloned() {
                None => return Err(MathError::MissingArgument("]")),
                Some(Tok::Char(']')) => {
                    self.next();
                    return Ok(nodes);
                }
                Some(Tok::Sup) | Some(Tok::Sub) => {
                    let n = self.parse_postfix(Node::Empty)?;
                    nodes.push(n);
                }
                Some(_) => {
                    let atom = self.parse_atom()?;
                    let n = self.parse_postfix(atom)?;
                    nodes.push(n);
                }
            }
        }
    }

    /// 读取一组纯文本（\operatorname 的参数：字母与符号字形）。
    fn parse_plain_group(&mut self) -> Result<String, MathError> {
        match self.next() {
            Some(Tok::LBrace) => {}
            Some(Tok::Char(c)) => return Ok(c.to_string()),
            Some(Tok::Ctrl(n)) => {
                return Ok(match symbol(&n) {
                    Some((g, _)) => g.to_string(),
                    None => n,
                })
            }
            _ => return Err(MathError::MissingArgument("operatorname")),
        }
        let mut s = String::new();
        loop {
            match self.next() {
                Some(Tok::RBrace) => return Ok(s),
                Some(Tok::Char(c)) => s.push(c),
                Some(Tok::Ctrl(n)) => match symbol(&n) {
                    Some((g, _)) => s.push_str(g),
                    None => {
                        s.push('\\');
                        s.push_str(&n);
                    }
                },
                Some(_) => {}
                None => return Err(MathError::UnbalancedBrace),
            }
        }
    }

    /// \substack{…\\…}：组内以 \\ 分行的单列小矩阵。
    fn parse_substack(&mut self) -> Result<Node, MathError> {
        match self.next() {
            Some(Tok::LBrace) => {}
            _ => return Err(MathError::MissingArgument("substack")),
        }
        let mut rows: Vec<Vec<Node>> = Vec::new();
        loop {
            let cell = self.parse_expr(true, true, false)?;
            rows.push(vec![Node::Row(cell)]);
            match self.next() {
                Some(Tok::Ctrl(n)) if n == "\\" || n == "cr" => continue,
                Some(Tok::RBrace) => break,
                _ => return Err(MathError::UnbalancedBrace),
            }
        }
        Ok(Node::Env {
            kind: EnvKind::Gather,
            rows,
            col_align: "center".to_string(),
            hlines: Vec::new(),
            vlines: Vec::new(),
            row_extra: Vec::new(),
        })
    }

    /// \\[dim] 的原始维度文本：吞掉直到 ']' 的记号并拼回字符串
    /// （维度只是数字+单位，记号级拼写足够；遇不到 ']' 时按已
    /// 吞内容返回，不报错——与旧版忽略该参数的宽容度一致）。
    fn take_dim_raw(&mut self) -> String {
        let mut s = String::new();
        while let Some(t) = self.peek().cloned() {
            match t {
                Tok::Char(']') => {
                    self.next();
                    break;
                }
                Tok::Char(c) => {
                    s.push(c);
                    self.next();
                }
                Tok::Ctrl(n) => {
                    s.push('\\');
                    s.push_str(&n);
                    self.next();
                }
                _ => {
                    self.next();
                }
            }
        }
        s
    }

    /// \begin{…} … \end{…} 环境。
    fn parse_env(&mut self) -> Result<Node, MathError> {
        let name = self.parse_raw_group("begin")?;
        let base = name.trim_end_matches('*');
        let mut vlines: Vec<u8> = Vec::new();
        let (kind, mut col_align) = match base {
            "matrix" => (EnvKind::Matrix, "center".to_string()),
            "pmatrix" => (EnvKind::PMatrix, "center".to_string()),
            "bmatrix" => (EnvKind::BMatrix, "center".to_string()),
            "Bmatrix" => (EnvKind::BraceMatrix, "center".to_string()),
            "vmatrix" => (EnvKind::VMatrix, "center".to_string()),
            "Vmatrix" => (EnvKind::VVMatrix, "center".to_string()),
            "smallmatrix" => (EnvKind::SmallMatrix, "center".to_string()),
            "cases" => (EnvKind::Cases, "left".to_string()),
            "rcases" => (EnvKind::RCases, "left".to_string()),
            "aligned" => (EnvKind::Aligned, String::new()),
            "gather" | "gathered" | "split" => (EnvKind::Gather, "center".to_string()),
            "array" | "subarray" => {
                let spec = self.parse_raw_group("array")?;
                // 列规格逐字扫描：l/c/r 定对齐，| 计入所在列间隙
                // 的竖线数（vlines 下标 = 列间隙，0 为首列前）。
                let mut aligns: Vec<&str> = Vec::new();
                vlines = vec![0];
                for c in spec.chars() {
                    match c {
                        'l' => {
                            aligns.push("left");
                            vlines.push(0);
                        }
                        'c' => {
                            aligns.push("center");
                            vlines.push(0);
                        }
                        'r' => {
                            aligns.push("right");
                            vlines.push(0);
                        }
                        '|' => {
                            let gap = vlines.len().saturating_sub(1);
                            bump_gap(&mut vlines, gap);
                        }
                        _ => {}
                    }
                }
                let aligns = aligns;
                (
                    if base == "subarray" {
                        EnvKind::SmallMatrix
                    } else {
                        EnvKind::Array
                    },
                    if aligns.is_empty() {
                        "center".to_string()
                    } else {
                        aligns.join(" ")
                    },
                )
            }
            "alignedat" => {
                let _ = self.parse_raw_group("alignedat");
                (EnvKind::Aligned, String::new())
            }
            _ => return Err(MathError::UnknownEnv(name.clone())),
        };
        let mut rows: Vec<Vec<Node>> = Vec::new();
        let mut cur_row: Vec<Node> = Vec::new();
        let mut hlines: Vec<u8> = Vec::new();
        let mut row_extra: Vec<f32> = Vec::new();
        let mut ended = false;
        while !ended {
            // 行首的 \hline 计入当前行间隙（下标 = 已完成行数）。
            while self.peek_ctrl("hline") {
                self.next();
                bump_gap(&mut hlines, rows.len());
            }
            let cell = self.parse_expr(false, true, false)?;
            cur_row.push(Node::Row(cell));
            match self.peek().cloned() {
                Some(Tok::Amp) => {
                    self.next();
                }
                Some(Tok::Ctrl(n)) if n == "\\" || n == "cr" => {
                    self.next();
                    // \\[dim]：额外间距计入本行之后的间隙。
                    if self.peek_char('[') {
                        self.next();
                        let raw = self.take_dim_raw();
                        if let Some(em) = dim_em_value(&raw) {
                            let gap = rows.len() + 1;
                            if row_extra.len() <= gap {
                                row_extra.resize(gap + 1, 0.0);
                            }
                            row_extra[gap] += em;
                        }
                    }
                    rows.push(std::mem::take(&mut cur_row));
                }
                Some(Tok::Ctrl(n)) if n == "hline" => {
                    self.next();
                    bump_gap(&mut hlines, rows.len() + 1);
                }
                Some(Tok::Ctrl(n)) if n == "end" => {
                    self.next();
                    let end_name = self.parse_raw_group("end")?;
                    if end_name != name {
                        return Err(MathError::EnvMismatch {
                            begin: name.clone(),
                            end: end_name,
                        });
                    }
                    rows.push(std::mem::take(&mut cur_row));
                    ended = true;
                }
                _ => return Err(MathError::MissingEnd(name.clone())),
            }
        }
        // 尾随 \\ 造成的全空末行丢弃。
        if let Some(last) = rows.last() {
            if rows.len() > 1
                && last.len() == 1
                && matches!(&last[0], Node::Row(v) if v.is_empty())
            {
                rows.pop();
            }
        }
        if kind == EnvKind::Aligned {
            let max_cols = rows.iter().map(|r| r.len()).max().unwrap_or(0);
            let mut parts = Vec::new();
            for i in 0..max_cols {
                parts.push(if i % 2 == 0 { "right" } else { "left" });
            }
            col_align = if parts.is_empty() {
                "center".to_string()
            } else {
                parts.join(" ")
            };
        }
        Ok(Node::Env {
            kind,
            rows,
            col_align,
            hlines,
            vlines,
            row_extra,
        })
    }
}

/// 非 ASCII 字母（CJK 等）：在数学模式里按文本呈现。
fn is_text_char(c: char) -> bool {
    !c.is_ascii() && c.is_alphabetic()
}

/// 单个普通字符的节点分类（参数位不合并版共用）。
fn char_node(c: char, single: bool) -> Node {
    match c {
        _ if c.is_ascii_digit() => Node::Num(c.to_string()),
        _ if c.is_ascii_alphabetic() => Node::Ident(c.to_string()),
        _ if is_text_char(c) => Node::TextRun(c.to_string()),
        '~' => Node::Space("0.25em".to_string()),
        '-' => Node::Op("−".to_string()),
        '*' => Node::Op("∗".to_string()),
        '\'' => Node::Op("′".to_string()),
        _ => {
            let _ = single;
            Node::Op(c.to_string())
        }
    }
}

fn text_styled_node(name: &str, raw: &str) -> Node {
    let variant = match name {
        "textbf" => Some("bold"),
        "textit" => Some("italic"),
        "textrm" => Some("normal"),
        "textsf" => Some("sans-serif"),
        "texttt" => Some("monospace"),
        _ => None,
    };
    Node::TextStyled {
        variant,
        text: clean_text_arg(raw),
    }
}

/// 字体命令的节点构造：\mathbb/\mathcal/\mathfrak 对单字母优先
/// 用专用字形，其余走 mathvariant 样式包裹。
fn styled_node(name: &str, arg: Node) -> Node {
    let single_ident = match &arg {
        Node::Ident(s) if s.chars().count() == 1 => s.chars().next(),
        // 花括号参数经 parse_arg 包成 Row：单元素时同样取其标识符。
        Node::Row(v) if v.len() == 1 => match &v[0] {
            Node::Ident(s) if s.chars().count() == 1 => s.chars().next(),
            _ => None,
        },
        _ => None,
    };
    if let Some(c) = single_ident {
        let glyph = match name {
            "mathbb" | "Bbb" => bb_glyph(c),
            "mathcal" => cal_glyph(c),
            "mathfrak" => frak_glyph(c),
            _ => None,
        };
        if let Some(g) = glyph {
            return Node::Sym {
                glyph: g.to_string(),
                mi: true,
            };
        }
    }
    let variant: &'static str = match name {
        "mathbf" => "bold",
        "mathbfit" | "boldsymbol" | "bm" => "bold-italic",
        "mathit" => "italic",
        "mathrm" | "mathnormal" => "normal",
        "mathsf" => "sans-serif",
        "mathtt" => "monospace",
        "mathbb" | "Bbb" => "double-struck",
        "mathcal" | "mathscr" => "script",
        "mathfrak" => "fraktur",
        _ => "normal",
    };
    Node::Styled {
        variant,
        body: Box::new(arg),
    }
}

/// 把参数节点拍平成纯文本（\text 退化形态用）。
fn node_plain_text(node: &Node) -> String {
    match node {
        Node::Row(v) => v.iter().map(node_plain_text).collect(),
        Node::Ident(s) | Node::Num(s) | Node::Op(s) | Node::TextRun(s) => s.clone(),
        Node::Sym { glyph, .. } => glyph.clone(),
        Node::Func { name, .. } => name.clone(),
        _ => String::new(),
    }
}

/// 长度参数 → em 字符串（pt/mu/ex 做近似换算，与 TeX 常用
/// 字号下的比例一致即可，间距类参数不追求绝对精度）。
/// 维度字符串 → em 数值（单位换算与 dim_to_em 同口径）。
/// 数值部分无法解析时返回 None。
fn dim_em_value(raw: &str) -> Option<f32> {
    let raw = raw.trim();
    let num_end = raw
        .find(|c: char| !(c.is_ascii_digit() || c == '.' || c == '-' || c == '+'))
        .unwrap_or(raw.len());
    let (num, unit) = raw.split_at(num_end);
    let v: f32 = num.parse().ok()?;
    let em = match unit.trim() {
        "em" => v,
        "ex" => v * 0.43,
        "pt" => v / 12.0,
        "mu" => v / 18.0,
        "mm" => v * 0.283,
        "cm" => v * 2.83,
        "in" => v * 7.2,
        _ => v,
    };
    Some(em)
}

fn dim_to_em(raw: &str) -> String {
    format!("{:.3}em", dim_em_value(raw).unwrap_or(0.0))
}

// ================= MathML 发射 =================

/// KaTeX 错误红（未知命令式内呈现与整式兜底的共同色值口径）。
pub const MATH_ERROR_COLOR: &str = "#cc0000";

#[derive(Clone, Default)]
struct Ctx {
    variant: Option<&'static str>,
    color: Option<String>,
    /// matrix/array 格内：普通 \frac 的布局盒按原版行距钳制
    /// （见 Node::Frac 发射处注释）。进入格时置位，分数的
    /// 分子/分母子树内清零（只钳格内最外层分数）。
    frac_clamp: bool,
}

fn esc_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            _ => out.push(c),
        }
    }
    out
}

fn esc_attr(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
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

/// em 数值 → 属性字符串（最多 3 位小数，去尾零）。
fn em_str(v: f32) -> String {
    let s = format!("{v:.3}");
    let s = s.trim_end_matches('0').trim_end_matches('.');
    format!("{s}em")
}

/// 环境行间隙基础值（em，行内容边到边）：由原版渲染器同夹具
/// 量测的基线行距反推——array/matrix 基线行距 1.8em、含 jot
/// 的 aligned/gather 为 2.25em，减去普通字母行的内容高约
/// 0.43em（内容高随行内容变化，行距本身在原版为固定基线距，
/// 此处以间隙近似，残差见视觉对齐回报）。
fn env_row_gap(kind: &EnvKind) -> f32 {
    match kind {
        EnvKind::Aligned | EnvKind::Gather => 1.82,
        _ => 1.37,
    }
}

/// 环境列间隙基础值（em）：原版量测——matrix/array 列间空隙
/// 1em（间隙两侧各 0.5em）；smallmatrix 列间约 0.39em，按其
/// 本地字号（scriptlevel=1，约 0.71 倍）折合约 0.55em。
fn env_col_gap(kind: &EnvKind) -> f32 {
    match kind {
        EnvKind::SmallMatrix => 0.55,
        _ => 1.0,
    }
}

fn variant_color_attrs(ctx: &Ctx) -> String {
    let mut s = String::new();
    if let Some(v) = ctx.variant {
        s.push_str(&format!(" mathvariant=\"{v}\""));
    }
    if let Some(c) = &ctx.color {
        s.push_str(&format!(" mathcolor=\"{}\"", esc_attr(c)));
    }
    s
}

fn color_attr(ctx: &Ctx) -> String {
    match &ctx.color {
        Some(c) => format!(" mathcolor=\"{}\"", esc_attr(c)),
        None => String::new(),
    }
}

/// 参数位发射：多子节点的行须包 mrow 才能作 mfrac/msub 等的
/// 单个子元素；空参数发空 mrow。
fn emit_arg(node: &Node, ctx: &Ctx, out: &mut String) {
    match node {
        Node::Row(v) if v.len() == 1 => emit(&v[0], ctx, out),
        Node::Row(v) => {
            out.push_str("<mrow>");
            for c in v {
                emit(c, ctx, out);
            }
            out.push_str("</mrow>");
        }
        Node::Empty => out.push_str("<mrow></mrow>"),
        _ => emit(node, ctx, out),
    }
}

/// 样式/颜色包裹的发射：多子节点时用 mrow 分组（属性落在各
/// 叶子记号上，mrow 只负责分组）。
fn emit_wrapped(body: &Node, ctx: &Ctx, out: &mut String) {
    match body {
        Node::Row(v) if v.len() != 1 => {
            out.push_str("<mrow>");
            for c in v {
                emit(c, ctx, out);
            }
            out.push_str("</mrow>");
        }
        Node::Row(v) => {
            if let Some(c) = v.first() {
                emit(c, ctx, out);
            }
        }
        _ => emit(body, ctx, out),
    }
}

fn emit(node: &Node, ctx: &Ctx, out: &mut String) {
    match node {
        Node::Row(v) => {
            for c in v {
                emit(c, ctx, out);
            }
        }
        Node::Ident(s) => {
            out.push_str(&format!("<mi{}>{}</mi>", variant_color_attrs(ctx), esc_text(s)));
        }
        Node::Num(s) => {
            out.push_str(&format!("<mn{}>{}</mn>", variant_color_attrs(ctx), esc_text(s)));
        }
        Node::Op(s) => {
            out.push_str(&format!("<mo{}>{}</mo>", variant_color_attrs(ctx), esc_text(s)));
        }
        Node::TextRun(s) => {
            out.push_str(&format!("<mtext{}>{}</mtext>", color_attr(ctx), esc_text(s)));
        }
        Node::Sym { glyph, mi } => {
            let tag = if *mi { "mi" } else { "mo" };
            out.push_str(&format!(
                "<{tag}{}>{}</{tag}>",
                variant_color_attrs(ctx),
                esc_text(glyph)
            ));
        }
        Node::Func { name, .. } => {
            out.push_str(&format!("<mo{}>{}</mo>", color_attr(ctx), esc_text(name)));
        }
        Node::BigOp { glyph, .. } => {
            out.push_str(&format!(
                "<mo largeop=\"true\"{}>{}</mo>",
                color_attr(ctx),
                esc_text(glyph)
            ));
        }
        Node::SizedDelim { glyph, level, form } => {
            // 原版规格（2026-11-22 同夹具重测，probe_katex_
            // residual/mech5，@16px）：字形墨迹高 19/29/38/48，
            // 布局 strut 总高 1.2/1.8/2.4/3.0em，基线上下分布
            // (0.85,0.35)/(1.15,0.65)/(1.45,0.95)/(1.75,1.25)em
            // ——墨迹≈strut（原版为定界专用字形，轴对称设计）。
            // 此前校准目标 1.55/2.45/3.35/4.25em 系误测：mo 盒
            // 被放大到 24/40/53/68，段总高随之 68 vs 原版 48。
            // 现行两件套：
            // (1) mathsize 按本机字体「墨迹≈盒高×0.96、盒高≈
            //     字号×0.94」反推，使 mo 盒≈原版字形盒
            //     20/36/38/48 量级（实测墨迹 19/29/38/48）；
            // (2) mpadded 按 strut 上下分布钳布局盒——行高只
            //     认 strut、墨迹可溢出，与原版 strut/墨迹分离
            //     的记账一致（段总高实测 68→48 与原版齐平）。
            // 残差（定案）：本机字体的括号墨迹在盒内偏高
            // （上沿占比约 0.77，原版定界字形约 0.58），档位
            // 越大墨迹中心越高于数学轴，属字形设计差异，
            // 不做 voffset 字体相关补偿。
            // \big 家族在 TeX 里是定尺寸、不随邻居内容伸缩，
            // 故 stretchy=false；minsize/maxsize 在 Chromium
            // 对 mo 盒高无效（旧机制），不许回潮。
            let (size, strut_h, strut_d) = match level {
                1 => ("1.3em", "0.85em", "0.35em"),
                2 => ("2em", "1.15em", "0.65em"),
                3 => ("2.65em", "1.45em", "0.95em"),
                _ => ("3.3em", "1.75em", "1.25em"),
            };
            let (form_attr, fence_attr) = match form {
                DelimForm::Open => (" form=\"prefix\"", " fence=\"true\""),
                DelimForm::Close => (" form=\"postfix\"", " fence=\"true\""),
                DelimForm::Mid => (" form=\"infix\"", ""),
            };
            out.push_str(&format!(
                "<mpadded height=\"{strut_h}\" depth=\"{strut_d}\"><mo{fence_attr}{form_attr} stretchy=\"false\" mathsize=\"{size}\"{}>{}</mo></mpadded>",
                variant_color_attrs(ctx),
                esc_text(glyph)
            ));
        }
        Node::Frac {
            num,
            den,
            style,
            line,
            fence,
        } => {
            // 格内钳制（ctx.frac_clamp，matrix/array 格的最外层
            // 普通/文本分数）：原版数组行高是固定基线距（行距
            // 1.205em），其文本分数（墨迹约 18px@16）本就装进
            // 行距；Chromium 的行高是「内容高 + mtd 内衬」，
            // 分数内容 16.19px 再叠内衬后每行多出约 4.2px
            // （2×2 分数阵总高 +8.5）。以 mpadded 把分数布局
            // 盒钳到「行距 − 内衬」= 0.75em，墨迹（16.19px）
            // 溢出量约 2px/侧、仍在内衬区内，与原版 strut/
            // 墨迹分离记账一致。\dfrac（Display）原版会真撑
            // 高行，不钳；分子/分母内的嵌套分数不再钳。
            let clamp = ctx.frac_clamp && *style != FracStyle::Display;
            let child_ctx;
            let ctx = if clamp {
                child_ctx = Ctx { frac_clamp: false, ..ctx.clone() };
                &child_ctx
            } else {
                ctx
            };
            let mut inner = String::new();
            if *fence != Fence::None {
                inner.push_str("<mrow>");
                inner.push_str(match fence {
                    Fence::Paren => "<mo fence=\"true\">(</mo>",
                    Fence::Bracket => "<mo fence=\"true\">[</mo>",
                    Fence::Brace => "<mo fence=\"true\">{</mo>",
                    Fence::None => "",
                });
            }
            if *line {
                // 线宽 0.04em：原版渲染器同夹具量测（frac-line
                // 的 border-bottom-width 内联值）。
                inner.push_str("<mfrac linethickness=\"0.04em\">");
            } else {
                inner.push_str("<mfrac linethickness=\"0\">");
            }
            emit_arg(num, ctx, &mut inner);
            emit_arg(den, ctx, &mut inner);
            inner.push_str("</mfrac>");
            if *fence != Fence::None {
                inner.push_str(match fence {
                    Fence::Paren => "<mo fence=\"true\">)</mo>",
                    Fence::Bracket => "<mo fence=\"true\">]</mo>",
                    Fence::Brace => "<mo fence=\"true\">}</mo>",
                    Fence::None => "",
                });
                inner.push_str("</mrow>");
            }
            let mut body = String::new();
            match style {
                FracStyle::Normal => body.push_str(&inner),
                FracStyle::Display => {
                    body.push_str("<mstyle displaystyle=\"true\" scriptlevel=\"0\">");
                    body.push_str(&inner);
                    body.push_str("</mstyle>");
                }
                FracStyle::Text => {
                    body.push_str("<mstyle displaystyle=\"false\" scriptlevel=\"0\">");
                    body.push_str(&inner);
                    body.push_str("</mstyle>");
                }
            }
            if clamp {
                out.push_str("<mpadded height=\"0.4em\" depth=\"0.35em\">");
                out.push_str(&body);
                out.push_str("</mpadded>");
            } else {
                out.push_str(&body);
            }
        }
        Node::Sqrt { index, body } => match index {
            None => {
                out.push_str("<msqrt>");
                emit_arg(body, ctx, out);
                out.push_str("</msqrt>");
            }
            Some(idx) => {
                out.push_str("<mroot>");
                emit_arg(body, ctx, out);
                emit_arg(idx, ctx, out);
                out.push_str("</mroot>");
            }
        },
        Node::Scripted { base, sub, sup } => {
            let tag = match (sub, sup) {
                (Some(_), Some(_)) => "msubsup",
                (Some(_), None) => "msub",
                (None, Some(_)) => "msup",
                (None, None) => "",
            };
            if tag.is_empty() {
                emit_arg(base, ctx, out);
            } else {
                out.push_str(&format!("<{tag}>"));
                emit_arg(base, ctx, out);
                if let Some(s) = sub {
                    emit_arg(s, ctx, out);
                }
                if let Some(s) = sup {
                    emit_arg(s, ctx, out);
                }
                out.push_str(&format!("</{tag}>"));
            }
        }
        Node::Limited { base, sub, sup } => {
            let tag = match (sub, sup) {
                (Some(_), Some(_)) => "munderover",
                (Some(_), None) => "munder",
                (None, Some(_)) => "mover",
                (None, None) => "",
            };
            if tag.is_empty() {
                emit_arg(base, ctx, out);
            } else {
                out.push_str(&format!("<{tag}>"));
                emit_arg(base, ctx, out);
                if let Some(s) = sub {
                    emit_arg(s, ctx, out);
                }
                if let Some(s) = sup {
                    emit_arg(s, ctx, out);
                }
                out.push_str(&format!("</{tag}>"));
            }
        }
        Node::Delimited { open, body, close } => {
            out.push_str("<mrow>");
            if let Some(o) = open {
                out.push_str(&format!(
                    "<mo fence=\"true\" stretchy=\"true\">{}</mo>",
                    esc_text(o)
                ));
            }
            emit(body, ctx, out);
            if let Some(c) = close {
                out.push_str(&format!(
                    "<mo fence=\"true\" stretchy=\"true\">{}</mo>",
                    esc_text(c)
                ));
            }
            out.push_str("</mrow>");
        }
        Node::Accent {
            glyph,
            body,
            under,
            accent,
        } => {
            let tag = if *under { "munder" } else { "mover" };
            if *accent {
                out.push_str(&format!("<{tag} accent=\"true\">"));
                emit_arg(body, ctx, out);
                out.push_str(&format!(
                    "<mo accent=\"true\"{}>{}</mo>",
                    color_attr(ctx),
                    esc_text(glyph)
                ));
            } else {
                out.push_str(&format!("<{tag}>"));
                emit_arg(body, ctx, out);
                out.push_str(&format!(
                    "<mo stretchy=\"true\"{}>{}</mo>",
                    color_attr(ctx),
                    esc_text(glyph)
                ));
            }
            out.push_str(&format!("</{tag}>"));
        }
        Node::Env {
            kind,
            rows,
            col_align,
            hlines,
            vlines,
            row_extra,
        } => {
            let (open, close) = match kind {
                EnvKind::PMatrix => (Some("("), Some(")")),
                EnvKind::BMatrix => (Some("["), Some("]")),
                EnvKind::BraceMatrix => (Some("{"), Some("}")),
                EnvKind::VMatrix => (Some("|"), Some("|")),
                EnvKind::VVMatrix => (Some("‖"), Some("‖")),
                EnvKind::Cases => (Some("{"), None),
                EnvKind::RCases => (None, Some("}")),
                _ => (None, None),
            };
            let small = *kind == EnvKind::SmallMatrix;
            if small {
                out.push_str("<mstyle displaystyle=\"false\" scriptlevel=\"1\">");
            }
            if open.is_some() || close.is_some() {
                out.push_str("<mrow>");
                if let Some(o) = open {
                    out.push_str(&format!(
                        "<mo fence=\"true\" stretchy=\"true\">{}</mo>",
                        esc_text(o)
                    ));
                }
            }
            let nrows = rows.len();
            let ncols = rows.iter().map(|r| r.len()).max().unwrap_or(0).max(1);
            // ---- 行展开：\hline 物化 ----
            // 间隙 g（0=首行前 … nrows=末行后）线数 c 的物化规则：
            // 内部间隙 c=1 用自然边界的 rowlines；其余情形（边缘
            // 间隙、c>=2）插入空行，靠空行两侧的边界描线，空行
            // 相邻边界的 rowspacing 为 0。\\[dim] 叠加在所在间隙
            // 的基础行距上。
            let base_gap = env_row_gap(kind);
            let hline_at = |g: usize| hlines.get(g).copied().unwrap_or(0).min(3) as usize;
            let extra_at = |g: usize| row_extra.get(g).copied().unwrap_or(0.0);
            // exp_rows: Some(原行下标) / None(物化空行)；row_line /
            // row_gap 为相邻行之间的边界表（长度 = 行数-1）。
            let mut exp_rows: Vec<Option<usize>> = Vec::new();
            let mut row_line: Vec<bool> = Vec::new();
            let mut row_gap: Vec<f32> = Vec::new();
            {
                let mut append_row = |row: Option<usize>, solid: bool, gap: f32| {
                    if !exp_rows.is_empty() {
                        row_line.push(solid);
                        row_gap.push(gap);
                    }
                    exp_rows.push(row);
                };
                for g in 0..=nrows {
                    let c = hline_at(g);
                    let interior = g >= 1 && g < nrows;
                    if c > 0 {
                        let k = if interior { c - 1 } else { c };
                        for j in 0..k {
                            // 内部间隙的首个空行边界保留基础行距
                            // （线画在间隙内，行距不因描线塌缩）。
                            let gap = if interior && j == 0 {
                                base_gap + extra_at(g)
                            } else {
                                0.0
                            };
                            append_row(None, true, gap);
                        }
                        if g < nrows {
                            if interior && c == 1 {
                                append_row(Some(g), true, base_gap + extra_at(g));
                            } else {
                                append_row(Some(g), true, 0.0);
                            }
                        }
                    } else if g < nrows {
                        append_row(Some(g), false, base_gap + extra_at(g));
                    }
                }
            }
            // ---- 列展开：竖线物化（vlines 仅由 array 列规格产生） ----
            // 规则与行同构。array 的边缘内衬：无边缘竖线的一侧用
            // mspace 外衬 0.5em；有边缘竖线时靠竖线内侧的边界
            // 间距 0.5em（原版量测：竖线内侧各有 0.5em 空隙）。
            let vline_at = |g: usize| vlines.get(g).copied().unwrap_or(0).min(3) as usize;
            let cols_built = *kind == EnvKind::Array || (0..=ncols).any(|g| vline_at(g) > 0);
            let mut exp_cols: Vec<Option<usize>> = Vec::new();
            let mut col_line: Vec<bool> = Vec::new();
            let mut col_gap: Vec<f32> = Vec::new();
            let mut pad_left = false;
            let mut pad_right = false;
            if cols_built {
                let base = env_col_gap(kind);
                let mut append_col = |col: Option<usize>, solid: bool, gap: f32| {
                    if !exp_cols.is_empty() {
                        col_line.push(solid);
                        col_gap.push(gap);
                    }
                    exp_cols.push(col);
                };
                for g in 0..=ncols {
                    let c = vline_at(g);
                    let interior = g >= 1 && g < ncols;
                    if c > 0 {
                        let k = if interior { c - 1 } else { c };
                        for j in 0..k {
                            // 右边缘首个空列与末实列之间留内衬；
                            // 内部间隙首个空列边界保留基础列距。
                            let gap = if *kind == EnvKind::Array && g == ncols && j == 0 {
                                0.5
                            } else if interior && j == 0 {
                                base
                            } else {
                                0.0
                            };
                            append_col(None, true, gap);
                        }
                        if g < ncols {
                            if interior && c == 1 {
                                append_col(Some(g), true, base);
                            } else if !interior {
                                // 左边缘空列与首实列之间留内衬。
                                let gap = if *kind == EnvKind::Array { 0.5 } else { 0.0 };
                                append_col(Some(g), true, gap);
                            } else {
                                append_col(Some(g), true, 0.0);
                            }
                        }
                    } else if g < ncols {
                        append_col(Some(g), false, base);
                    }
                }
                if *kind == EnvKind::Array {
                    pad_left = vline_at(0) == 0;
                    pad_right = vline_at(ncols) == 0;
                }
            }
            // ---- mtable 属性 ----
            let aligns: Vec<&str> = col_align.split_whitespace().collect();
            let align_of = |ci: usize| aligns.get(ci).copied().unwrap_or("center");
            let col_align_attr = if cols_built {
                exp_cols
                    .iter()
                    .map(|c| match c {
                        Some(ci) => align_of(*ci),
                        None => "center",
                    })
                    .collect::<Vec<_>>()
                    .join(" ")
            } else {
                col_align.clone()
            };
            let mut attrs = format!(" columnalign=\"{}\"", esc_attr(&col_align_attr));
            // 列距：展开形态用边界表；aligned 对内 0em / 对间 1em
            // （原版量测）；cases 首隙 1em、余 0.5em；其余单值。
            if cols_built {
                let list = col_gap.iter().map(|&v| em_str(v)).collect::<Vec<_>>().join(" ");
                attrs.push_str(&format!(" columnspacing=\"{list}\""));
            } else if ncols >= 2 {
                match kind {
                    EnvKind::Aligned => {
                        let list = (0..ncols - 1)
                            .map(|i| if i % 2 == 0 { "0em" } else { "1em" })
                            .collect::<Vec<_>>()
                            .join(" ");
                        attrs.push_str(&format!(" columnspacing=\"{list}\""));
                    }
                    EnvKind::Cases | EnvKind::RCases => {
                        let list = (0..ncols - 1)
                            .map(|i| if i == 0 { "1em" } else { "0.5em" })
                            .collect::<Vec<_>>()
                            .join(" ");
                        attrs.push_str(&format!(" columnspacing=\"{list}\""));
                    }
                    EnvKind::Gather => {}
                    _ => {
                        attrs.push_str(&format!(
                            " columnspacing=\"{}\"",
                            em_str(env_col_gap(kind))
                        ));
                    }
                }
            }
            // 行距：边界全为基础值且无展开时用单值，否则用边界表。
            if exp_rows.len() == nrows && row_gap.iter().all(|&v| v == base_gap) {
                attrs.push_str(&format!(" rowspacing=\"{}\"", em_str(base_gap)));
            } else {
                let list = row_gap.iter().map(|&v| em_str(v)).collect::<Vec<_>>().join(" ");
                attrs.push_str(&format!(" rowspacing=\"{list}\""));
            }
            if row_line.iter().any(|&b| b) {
                let list = row_line
                    .iter()
                    .map(|&b| if b { "solid" } else { "none" })
                    .collect::<Vec<_>>()
                    .join(" ");
                attrs.push_str(&format!(" rowlines=\"{list}\""));
            }
            if col_line.iter().any(|&b| b) {
                let list = col_line
                    .iter()
                    .map(|&b| if b { "solid" } else { "none" })
                    .collect::<Vec<_>>()
                    .join(" ");
                attrs.push_str(&format!(" columnlines=\"{list}\""));
            }
            if pad_left {
                out.push_str("<mspace width=\"0.5em\"/>");
            }
            // 格内分数钳制只用于固定行距环境（matrix 家族与
            // array）：cases 的行距带 1.2 拉伸、aligned/gather
            // 带 jot，分数行本就与之同量级，不钳（见 Frac 处）。
            let cell_ctx = Ctx {
                frac_clamp: matches!(
                    kind,
                    EnvKind::Matrix
                        | EnvKind::PMatrix
                        | EnvKind::BMatrix
                        | EnvKind::BraceMatrix
                        | EnvKind::VMatrix
                        | EnvKind::VVMatrix
                        | EnvKind::Array
                ),
                ..ctx.clone()
            };
            out.push_str(&format!("<mtable{attrs}>"));
            let exp_ncols = if cols_built { exp_cols.len() } else { ncols };
            for er in &exp_rows {
                out.push_str("<mtr>");
                match er {
                    None => {
                        for _ in 0..exp_ncols {
                            out.push_str("<mtd></mtd>");
                        }
                    }
                    Some(ri) => {
                        let row = &rows[*ri];
                        if cols_built {
                            for ec in &exp_cols {
                                out.push_str("<mtd>");
                                if let Some(ci) = ec {
                                    if let Some(cell) = row.get(*ci) {
                                        emit(cell, &cell_ctx, out);
                                    }
                                }
                                out.push_str("</mtd>");
                            }
                        } else {
                            for cell in row {
                                out.push_str("<mtd>");
                                emit(cell, &cell_ctx, out);
                                out.push_str("</mtd>");
                            }
                        }
                    }
                }
                out.push_str("</mtr>");
            }
            out.push_str("</mtable>");
            if pad_right {
                out.push_str("<mspace width=\"0.5em\"/>");
            }
            if open.is_some() || close.is_some() {
                if let Some(c) = close {
                    out.push_str(&format!(
                        "<mo fence=\"true\" stretchy=\"true\">{}</mo>",
                        esc_text(c)
                    ));
                }
                out.push_str("</mrow>");
            }
            if small {
                out.push_str("</mstyle>");
            }
        }
        Node::Styled { variant, body } => {
            let mut ctx2 = ctx.clone();
            ctx2.variant = Some(variant);
            emit_wrapped(body, &ctx2, out);
        }
        Node::TextStyled { variant, text } => {
            let mut attrs = String::new();
            if let Some(v) = variant {
                attrs.push_str(&format!(" mathvariant=\"{v}\""));
            }
            attrs.push_str(&color_attr(ctx));
            out.push_str(&format!("<mtext{attrs}>{}</mtext>", esc_text(text)));
        }
        Node::Colored { color, body } => {
            let mut ctx2 = ctx.clone();
            ctx2.color = Some(color.clone());
            emit_wrapped(body, &ctx2, out);
        }
        Node::DisplayStyle {
            display,
            script_level,
            body,
        } => {
            let mut attrs = String::new();
            if let Some(d) = display {
                attrs.push_str(&format!(" displaystyle=\"{d}\""));
            }
            if let Some(l) = script_level {
                attrs.push_str(&format!(" scriptlevel=\"{l}\""));
            }
            out.push_str(&format!("<mstyle{attrs}>"));
            emit(body, ctx, out);
            out.push_str("</mstyle>");
        }
        Node::Space(w) => {
            out.push_str(&format!("<mspace width=\"{}\"/>", esc_attr(w)));
        }
        Node::Phantom(body) => {
            out.push_str("<mphantom>");
            emit_arg(body, ctx, out);
            out.push_str("</mphantom>");
        }
        Node::Enclosed { notation, body } => {
            out.push_str(&format!("<menclose notation=\"{notation}\">"));
            emit_arg(body, ctx, out);
            out.push_str("</menclose>");
        }
        Node::XArrow { glyph, over, under } => {
            let base = format!(
                "<mo stretchy=\"true\"{}>{}</mo>",
                color_attr(ctx),
                esc_text(glyph)
            );
            match (under, over) {
                (Some(u), Some(o)) => {
                    out.push_str("<munderover>");
                    out.push_str(&base);
                    emit_arg(u, ctx, out);
                    emit_arg(o, ctx, out);
                    out.push_str("</munderover>");
                }
                (Some(u), None) => {
                    out.push_str("<munder>");
                    out.push_str(&base);
                    emit_arg(u, ctx, out);
                    out.push_str("</munder>");
                }
                (None, Some(o)) => {
                    out.push_str("<mover>");
                    out.push_str(&base);
                    emit_arg(o, ctx, out);
                    out.push_str("</mover>");
                }
                (None, None) => out.push_str(&base),
            }
        }
        Node::Tag(body) => {
            out.push_str("<mspace width=\"1em\"/><mrow><mo>(</mo>");
            emit_arg(body, ctx, out);
            out.push_str("<mo>)</mo></mrow>");
        }
        Node::Unknown(name) => {
            out.push_str(&format!(
                "<mtext mathcolor=\"{MATH_ERROR_COLOR}\">\\{}</mtext>",
                esc_text(name)
            ));
        }
        Node::Empty => {}
        Node::LineBreak => {
            out.push_str("<mspace linebreak=\"newline\"/>");
        }
    }
}

/// 渲染入口：TeX 源码 → MathML 字符串。display=true 时根元素
/// 带 display="block"（块级居中由外层容器样式负责）。
/// 硬错误返回 Err，调用方整式回退红色原码。
pub fn render_mathml(tex: &str, display: bool) -> Result<String, MathError> {
    let toks = lex(tex);
    let mut parser = Parser {
        toks,
        pos: 0,
        depth: 0,
        display,
    };
    let nodes = parser.parse_all()?;
    let mut out = String::from("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"");
    if display {
        out.push_str(" display=\"block\"");
    }
    out.push('>');
    let ctx = Ctx::default();
    for n in &nodes {
        emit(n, &ctx, &mut out);
    }
    out.push_str("</math>");
    Ok(out)
}

// ================= 测试 =================

#[cfg(test)]
mod tests {
    use super::*;

    fn math(tex: &str, display: bool) -> MathSegment {
        MathSegment::Math {
            tex: tex.to_string(),
            display,
        }
    }

    fn text(s: &str) -> MathSegment {
        MathSegment::Text(s.to_string())
    }

    // ---------- 门控与防误判 ----------

    #[test]
    fn gate_single_dollar_no_pair() {
        assert!(!has_math_syntax("售价 $128 元整"));
        assert!(!has_math_syntax("一共 $5"));
        assert!(!has_math_syntax("没有美元符"));
    }

    #[test]
    fn gate_escaped_dollar() {
        assert!(!has_math_syntax("价格 \\$5\\$"));
        assert!(!split_math("标价 \\$x$ 元").iter().any(|s| matches!(s, MathSegment::Math { .. })));
    }

    #[test]
    fn gate_inline_and_display() {
        assert!(has_math_syntax("$E=mc^2$"));
        assert!(has_math_syntax("$x$"));
        assert!(has_math_syntax("$$\n\\int_0^1 f(x)\\,dx\n$$"));
        assert!(has_math_syntax("前文 $$a+b$$ 后文"));
    }

    #[test]
    fn gate_plain_letters_not_math() {
        // 纯字母词（长度 > 1 且无命令/数字/运算符）不算公式。
        assert!(!looks_like_math_expression("abc"));
        assert!(!has_math_syntax("$abc$"));
        assert!(!has_math_syntax("$hello world$"));
    }

    #[test]
    fn gate_expression_heuristic() {
        assert!(looks_like_math_expression("x"));
        assert!(looks_like_math_expression("E=mc^2"));
        assert!(looks_like_math_expression("\\alpha"));
        assert!(looks_like_math_expression("3.14"));
        assert!(looks_like_math_expression("α+β"));
        assert!(looks_like_math_expression("a-b"));
        assert!(!looks_like_math_expression(""));
        assert!(!looks_like_math_expression("  "));
        assert!(!looks_like_math_expression("the"));
    }

    #[test]
    fn gate_code_span_still_counts_for_gate() {
        // 门控工作在原始文本上（与段落 md 门控同层），代码段
        // 里的 $$ 也会让门控命中——渲染层再由切分器保护。
        assert!(has_math_syntax("`$$x$$`"));
    }

    // ---------- 切分 ----------

    #[test]
    fn split_price_with_two_dollars_is_math_by_spec() {
        // 规格口径：$5 和 $10 之间内容含数字 → 判为公式
        // （启发式与原版行为一致的已知口径，非误判豁免范围）。
        let segs = split_math("价格 $5 和 $10 元");
        assert!(segs.contains(&math("5 和 ", false)));
    }

    #[test]
    fn split_price_single_dollar_plain() {
        assert_eq!(split_math("售价 $128 元整"), vec![text("售价 $128 元整")]);
    }

    #[test]
    fn split_plain_letters_plain() {
        assert_eq!(split_math("代号 $abc$ 保密"), vec![text("代号 $abc$ 保密")]);
    }

    #[test]
    fn split_inline() {
        assert_eq!(
            split_math("质能 $E=mc^2$ 方程"),
            vec![text("质能 "), math("E=mc^2", false), text(" 方程")]
        );
    }

    #[test]
    fn split_display_multiline_and_inline_context() {
        let segs = split_math("$$\n\\frac{1}{2}\n$$");
        assert_eq!(segs.len(), 1);
        match &segs[0] {
            MathSegment::Math { tex, display } => {
                assert!(*display);
                assert_eq!(tex.trim(), "\\frac{1}{2}");
            }
            other => panic!("expected display math, got {other:?}"),
        }
        assert_eq!(
            split_math("前 $$x^2$$ 后"),
            vec![text("前 "), math("x^2", true), text(" 后")]
        );
    }

    #[test]
    fn split_code_span_protected() {
        assert_eq!(split_math("代码 `$x$` 示例"), vec![text("代码 `$x$` 示例")]);
        assert_eq!(
            split_math("`$$a$$` 与 $b$"),
            vec![text("`$$a$$` 与 "), math("b", false)]
        );
    }

    #[test]
    fn split_after_dollar_guard() {
        // 闭定界符后紧跟 $ → 整对不成式。
        assert_eq!(split_math("$x$$"), vec![text("$x$$")]);
        // 显示式未闭合 → 全部普通文本。
        assert_eq!(split_math("$$x"), vec![text("$$x")]);
        assert_eq!(split_math("$$$x$"), vec![text("$$$x$")]);
    }

    #[test]
    fn split_link_target_protected() {
        // 链接目标里的 $ 不成式，链接文本里的照常。
        assert_eq!(
            split_math("[说明](https://x.com/$a$b)"),
            vec![text("[说明](https://x.com/$a$b)")]
        );
        let segs = split_math("见 [文档](https://x.com/?p=$5) 与 $x$");
        assert!(segs.contains(&math("x", false)));
    }

    #[test]
    fn split_two_inlines() {
        assert_eq!(
            split_math("$a$ 与 $b$"),
            vec![math("a", false), text(" 与 "), math("b", false)]
        );
    }

    // ---------- 渲染：验收式样 ----------

    #[test]
    fn render_frac() {
        let out = render_mathml("\\frac{a+b}{2}", false).unwrap();
        assert!(out.contains("<mfrac linethickness=\"0.04em\">"), "{out}");
        assert!(out.contains("<mi>a</mi>"));
        assert!(out.contains("<mn>2</mn>"));
    }

    #[test]
    fn render_sqrt_and_root() {
        let out = render_mathml("\\sqrt{\\pi}", false).unwrap();
        assert!(out.contains("<msqrt>"), "{out}");
        assert!(out.contains('π'));
        let out = render_mathml("\\sqrt[3]{x}", false).unwrap();
        assert!(out.contains("<mroot>"), "{out}");
    }

    #[test]
    fn render_scripts() {
        let out = render_mathml("x_1^2", false).unwrap();
        assert!(out.contains("<msubsup>"), "{out}");
        let out = render_mathml("x^2", false).unwrap();
        assert!(out.contains("<msup>"), "{out}");
        let out = render_mathml("x_1", false).unwrap();
        assert!(out.contains("<msub>"), "{out}");
        // 参数单记号语义：x^12 = x^1 · 2
        let out = render_mathml("x^12", false).unwrap();
        assert!(out.contains("<msup><mi>x</mi><mn>1</mn></msup><mn>2</mn>"), "{out}");
        // \frac12 = \frac{1}{2}
        let out = render_mathml("\\frac12", false).unwrap();
        assert!(
            out.contains("<mfrac linethickness=\"0.04em\"><mn>1</mn><mn>2</mn></mfrac>"),
            "{out}"
        );
    }

    #[test]
    fn render_sum_limits_display_vs_inline() {
        let tex = "\\sum_{i=1}^{n} i";
        let out = render_mathml(tex, true).unwrap();
        assert!(out.contains("<munderover>"), "{out}");
        assert!(out.contains("largeop=\"true\""));
        let out = render_mathml(tex, false).unwrap();
        assert!(out.contains("<msubsup>"), "{out}");
        // \limits 强制限值位（行内亦然）；\nolimits 反之。
        let out = render_mathml("\\sum\\limits_{i=1}^{n}", false).unwrap();
        assert!(out.contains("<munderover>"), "{out}");
        let out = render_mathml("\\sum\\nolimits_{i=1}^{n}", true).unwrap();
        assert!(out.contains("<msubsup>"), "{out}");
    }

    #[test]
    fn render_integral_display_block() {
        let out = render_mathml(
            "\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}",
            true,
        )
        .unwrap();
        assert!(out.contains("display=\"block\""), "{out}");
        // 积分按 TeX 惯例走侧脚本而非限值位。
        assert!(out.contains("<msubsup>"), "{out}");
        assert!(out.contains("<msqrt>"), "{out}");
        assert!(out.contains("<mfrac linethickness=\"0.04em\">"), "{out}");
        assert!(out.contains('∞'));
        assert!(out.contains("<mspace width=\"0.167em\"/>"), "{out}");
    }

    #[test]
    fn render_matrix_envs() {
        let out = render_mathml("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", true).unwrap();
        assert!(out.contains("<mtable"), "{out}");
        assert_eq!(out.matches("<mtr>").count(), 2);
        assert_eq!(out.matches("<mtd>").count(), 4);
        assert!(out.contains("<mo fence=\"true\" stretchy=\"true\">(</mo>"), "{out}");
        let out = render_mathml("\\begin{bmatrix} 1 \\\\ 2 \\end{bmatrix}", false).unwrap();
        assert!(out.contains("<mtable"), "{out}");
        // cases：左花括号、两列左对齐。
        let out = render_mathml(
            "\\begin{cases} x & x > 0 \\\\ -x & x < 0 \\end{cases}",
            true,
        )
        .unwrap();
        assert!(out.contains("columnalign=\"left\""), "{out}");
        assert!(out.contains("columnspacing=\"1em\""), "{out}");
        assert!(out.contains("<mo fence=\"true\" stretchy=\"true\">{</mo>"), "{out}");
        // aligned：右/左交替对齐。
        let out = render_mathml("\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}", true)
            .unwrap();
        assert!(out.contains("columnalign=\"right left\""), "{out}");
    }

    #[test]
    fn render_sized_delims() {
        // 原版规格（2026-11-22 重测）：字形墨迹 19/29/38/48px
        // @16、strut 总高 1.2/1.8/2.4/3.0em。发射 = mathsize
        // （校准值 1.3/2/2.65/3.3em）+ mpadded 按 strut 上下
        // 分布钳布局盒；minsize/maxsize 在 Chromium 对 mo 盒
        // 高无效，不许回潮。
        let out = render_mathml("\\big(", false).unwrap();
        assert!(out.contains("mathsize=\"1.3em\""), "{out}");
        assert!(out.contains("<mpadded height=\"0.85em\" depth=\"0.35em\">"), "{out}");
        assert!(out.contains("stretchy=\"false\""), "{out}");
        assert!(!out.contains("minsize"), "{out}");
        assert!(!out.contains("maxsize"), "{out}");
        // 不再塌缩为无尺寸的普通 mo。
        assert!(!out.contains("<mo>(</mo>"), "{out}");
        let out = render_mathml("\\Big[", false).unwrap();
        assert!(out.contains("mathsize=\"2em\""), "{out}");
        assert!(out.contains("<mpadded height=\"1.15em\" depth=\"0.65em\">"), "{out}");
        let out = render_mathml("\\bigg\\{", false).unwrap();
        assert!(out.contains("mathsize=\"2.65em\""), "{out}");
        assert!(out.contains("<mpadded height=\"1.45em\" depth=\"0.95em\">"), "{out}");
        let out = render_mathml("\\Bigg)", false).unwrap();
        assert!(out.contains("mathsize=\"3.3em\""), "{out}");
        assert!(out.contains("<mpadded height=\"1.75em\" depth=\"1.25em\">"), "{out}");
        // 形态：l 开（prefix）、r 合（postfix）、m 中（infix）。
        let out = render_mathml("\\bigl(", false).unwrap();
        assert!(out.contains("form=\"prefix\""), "{out}");
        let out = render_mathml("\\bigr)", false).unwrap();
        assert!(out.contains("form=\"postfix\""), "{out}");
        let out = render_mathml("\\bigm|", false).unwrap();
        assert!(out.contains("form=\"infix\""), "{out}");
    }

    #[test]
    fn frac_clamp_in_matrix_cells() {
        // matrix 格内普通分数：mpadded 钳布局盒（行距记账）。
        let out = render_mathml(
            "\\begin{pmatrix} \\frac{1}{2} & x \\\\ y & \\frac{3}{4} \\end{pmatrix}",
            true,
        )
        .unwrap();
        assert_eq!(out.matches("<mpadded height=\"0.4em\" depth=\"0.35em\">").count(), 2, "{out}");
        // 独立分数不钳。
        let out = render_mathml("\\frac{1}{2}", false).unwrap();
        assert!(!out.contains("mpadded"), "{out}");
        // cases / aligned 不钳（行距模型不同）。
        let out = render_mathml("\\begin{cases} \\frac{1}{2} & x > 0 \\end{cases}", true).unwrap();
        assert!(!out.contains("mpadded"), "{out}");
        let out = render_mathml("\\begin{aligned} a &= \\frac{1}{2} \\end{aligned}", true).unwrap();
        assert!(!out.contains("mpadded"), "{out}");
        // 格内 \dfrac 不钳（原版会真撑高行）。
        let out = render_mathml("\\begin{pmatrix} \\dfrac{1}{2} \\end{pmatrix}", true).unwrap();
        assert!(!out.contains("mpadded"), "{out}");
        // 嵌套分数只钳最外层（分子内的分数不二次钳）。
        let out = render_mathml("\\begin{pmatrix} \\frac{\\frac{1}{2}}{3} \\end{pmatrix}", true)
            .unwrap();
        assert_eq!(out.matches("<mpadded").count(), 1, "{out}");
        // 格内分数嵌在行内表达式里同样钳。
        let out = render_mathml("\\begin{pmatrix} x + \\frac{1}{2} \\end{pmatrix}", true).unwrap();
        assert_eq!(out.matches("<mpadded").count(), 1, "{out}");
    }

    #[test]
    fn render_hline_variants() {
        // 内部单线：rowlines 自然边界，不增加行数。
        let out = render_mathml(
            "\\begin{array}{cc} a & b \\\\ \\hline c & d \\end{array}",
            true,
        )
        .unwrap();
        assert!(out.contains("rowlines=\"solid\""), "{out}");
        assert_eq!(out.matches("<mtr>").count(), 2, "{out}");
        // 顶线：物化一个空行，2 行变 3 行。
        let out = render_mathml(
            "\\begin{array}{cc} \\hline a & b \\\\ c & d \\end{array}",
            true,
        )
        .unwrap();
        assert!(out.contains("rowlines=\"solid none\""), "{out}");
        assert_eq!(out.matches("<mtr>").count(), 3, "{out}");
        // 带框表（顶/中/底线 + 两侧竖线）：展开后 4 行 4 列，
        // rowlines / columnlines 三条边界全 solid，列距呈
        // 内衬-间隙-内衬的 0.5/1/0.5em。
        let out = render_mathml(
            "\\begin{array}{|c|c|} \\hline a & b \\\\ \\hline c & d \\\\ \\hline \\end{array}",
            true,
        )
        .unwrap();
        assert!(out.contains("rowlines=\"solid solid solid\""), "{out}");
        assert!(out.contains("columnlines=\"solid solid solid\""), "{out}");
        assert!(out.contains("columnspacing=\"0.5em 1em 0.5em\""), "{out}");
        assert_eq!(out.matches("<mtr>").count(), 4, "{out}");
        // 内部双线：两条 solid，中间隔一个物化空行。
        let out = render_mathml(
            "\\begin{array}{c} a \\\\ \\hline\\hline b \\end{array}",
            true,
        )
        .unwrap();
        assert!(out.contains("rowlines=\"solid solid\""), "{out}");
        assert_eq!(out.matches("<mtr>").count(), 3, "{out}");
    }

    #[test]
    fn render_array_edge_padding() {
        // 无竖线的 array：两侧 mspace 外衬 0.5em，列距 1em。
        let out = render_mathml("\\begin{array}{cc} a & b \\end{array}", true).unwrap();
        assert_eq!(out.matches("<mspace width=\"0.5em\"/>").count(), 2, "{out}");
        assert!(out.contains("columnspacing=\"1em\""), "{out}");
        // 带边缘竖线时不外衬（内衬进边界列距）。
        let out = render_mathml("\\begin{array}{|c|c|} a & b \\end{array}", true).unwrap();
        assert!(!out.contains("<mspace width=\"0.5em\"/>"), "{out}");
        assert!(out.contains("columnspacing=\"0.5em 1em 0.5em\""), "{out}");
        // 矩阵不带 array 内衬，列距 1em。
        let out = render_mathml("\\begin{pmatrix} a & b \\end{pmatrix}", true).unwrap();
        assert!(!out.contains("<mspace width=\"0.5em\"/>"), "{out}");
        assert!(out.contains("columnspacing=\"1em\""), "{out}");
    }

    #[test]
    fn render_aligned_and_cases_spacing() {
        // aligned 两对：对内 0em、对间 1em；行距 1.82em。
        let out = render_mathml(
            "\\begin{aligned} a &= b & c &= d \\\\ e &= f & g &= h \\end{aligned}",
            true,
        )
        .unwrap();
        assert!(out.contains("columnspacing=\"0em 1em 0em\""), "{out}");
        assert!(out.contains("rowspacing=\"1.82em\""), "{out}");
        // array 基础行距 1.37em。
        let out = render_mathml("\\begin{array}{c} a \\\\ b \\end{array}", true).unwrap();
        assert!(out.contains("rowspacing=\"1.37em\""), "{out}");
    }

    #[test]
    fn render_row_extra_dim() {
        // \\[0.5em]：所在间隙行距 = 1.37 + 0.5 = 1.87em。
        let out = render_mathml(
            "\\begin{array}{c} a \\\\[0.5em] b \\\\ c \\end{array}",
            true,
        )
        .unwrap();
        assert!(out.contains("rowspacing=\"1.87em 1.37em\""), "{out}");
    }

    #[test]
    fn render_greek_and_symbols() {
        let out = render_mathml("\\alpha + \\beta \\leq \\Omega", false).unwrap();
        for g in ['α', 'β', 'Ω'] {
            assert!(out.contains(g), "{out}");
        }
        assert!(out.contains('≤'), "{out}");
    }

    #[test]
    fn render_mixed_chinese_text() {
        let out = render_mathml("\\text{速度} v = \\frac{s}{t}", false).unwrap();
        assert!(out.contains("<mtext>速度</mtext>"), "{out}");
        // 数学模式中的裸 CJK 字符也按文本呈现。
        let out = render_mathml("中文 x^2", false).unwrap();
        assert!(out.contains("<mtext>中文</mtext>"), "{out}");
    }

    #[test]
    fn render_binom_and_delimiters() {
        let out = render_mathml("\\binom{n}{k}", false).unwrap();
        assert!(out.contains("<mfrac linethickness=\"0\">"), "{out}");
        let out = render_mathml("\\left( \\frac{1}{2} \\right)", false).unwrap();
        assert!(out.contains("fence=\"true\""), "{out}");
        assert!(out.contains("<mfrac linethickness=\"0.04em\">"), "{out}");
        let out = render_mathml("\\left\\{ x \\right\\}", false).unwrap();
        assert!(out.contains("<mo fence=\"true\" stretchy=\"true\">{</mo>"), "{out}");
    }

    #[test]
    fn render_functions_and_lim() {
        let out = render_mathml("\\lim_{x \\to 0} f(x)", true).unwrap();
        assert!(out.contains("<munder>"), "{out}");
        assert!(out.contains("<mo>lim</mo>"), "{out}");
        assert!(out.contains('→'), "{out}");
        let out = render_mathml("\\sin x + \\cos y", false).unwrap();
        assert!(out.contains("<mo>sin</mo>"), "{out}");
    }

    #[test]
    fn render_styles_and_color() {
        let out = render_mathml("\\mathbf{v} + \\mathrm{d}x", false).unwrap();
        assert!(out.contains("mathvariant=\"bold\""), "{out}");
        assert!(out.contains("mathvariant=\"normal\""), "{out}");
        let out = render_mathml("\\mathbb{R} \\in \\mathbb{Z}", false).unwrap();
        assert!(out.contains('ℝ'), "{out}");
        assert!(out.contains('ℤ'), "{out}");
        let out = render_mathml("{\\color{red} x} + y", false).unwrap();
        assert!(out.contains("mathcolor=\"red\""), "{out}");
    }

    #[test]
    fn render_accents_and_overset() {
        let out = render_mathml("\\hat{x} + \\vec{v}", false).unwrap();
        assert!(out.contains("<mover accent=\"true\">"), "{out}");
        let out = render_mathml("\\overline{AB}", false).unwrap();
        assert!(out.contains("<mover>"), "{out}");
        let out = render_mathml("\\overset{*}{x}", false).unwrap();
        assert!(out.contains("<mover>"), "{out}");
        let out = render_mathml("f'(x)", false).unwrap();
        assert!(out.contains('′'), "{out}");
    }

    #[test]
    fn render_over_infix_and_not() {
        let out = render_mathml("a \\over b", false).unwrap();
        assert!(out.contains("<mfrac linethickness=\"0.04em\">"), "{out}");
        let out = render_mathml("x \\not\\in A", false).unwrap();
        assert!(out.contains('∉'), "{out}");
        let out = render_mathml("\\boxed{E=mc^2}", false).unwrap();
        assert!(out.contains("<menclose notation=\"box\">"), "{out}");
    }

    // ---------- 容错 ----------

    #[test]
    fn render_unknown_command_soft_red() {
        // 未知命令：式内红色呈现并继续渲染，不整式回退。
        let out = render_mathml("\\unknowncmd{x} + 1", false).unwrap();
        assert!(out.contains(MATH_ERROR_COLOR), "{out}");
        assert!(out.contains("unknowncmd"), "{out}");
        assert!(out.contains("<mi>x</mi>"), "{out}");
    }

    #[test]
    fn render_hard_errors() {
        // 残缺公式（缺参数/不配平/重复脚本/环境问题）→ 硬错误。
        assert_eq!(render_mathml("\\frac{1}", false), Err(MathError::MissingArgument("expression")));
        assert!(render_mathml("{a", false).is_err());
        assert!(render_mathml("a}", false).is_err());
        assert_eq!(render_mathml("x^", false), Err(MathError::MissingArgument("expression")));
        assert_eq!(render_mathml("x^a^b", false), Err(MathError::DoubleScript));
        assert!(matches!(
            render_mathml("\\begin{matrix} a \\end{pmatrix}", false),
            Err(MathError::EnvMismatch { .. })
        ));
        assert!(matches!(
            render_mathml("\\begin{foo} x \\end{foo}", false),
            Err(MathError::UnknownEnv(_))
        ));
        assert!(matches!(
            render_mathml("\\begin{matrix} a", false),
            Err(MathError::MissingEnd(_))
        ));
        assert!(matches!(
            render_mathml("\\left( x", false),
            Err(MathError::UnmatchedLeftRight)
        ));
        // \frac{1}{ 是残缺：第二个参数组未闭合。
        assert!(render_mathml("\\frac{1}{", false).is_err());
    }

    #[test]
    fn render_empty_ok() {
        let out = render_mathml("", false).unwrap();
        assert!(out.starts_with("<math"), "{out}");
        assert!(out.ends_with("</math>"));
    }
}
