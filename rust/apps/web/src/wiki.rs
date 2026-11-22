//! Wiki 链接与反向链接（原版 editor.js:2-28 目标提取、
//! memo-list.js:291-302 导航解析的等价实现）：纯按标题的文本
//! 链接，文档里永远只存 `[[标题]]` 字面文本，零新增存储字段；
//! 目标解析与反向链接全部运行时现算，无索引、无 id 引用。
//! 扫描全部手写，不引入 regex（与 list.rs 的口径一致）。

use std::collections::HashSet;

use mynote_core::model::{Memo, Node};

use crate::diag;

/// 原版 wikiTitleKey：剥 `#锚点` → trim → 小写。
/// （原版用 toLocaleLowerCase，Rust 用 Unicode 小写近似。）
pub fn wiki_title_key(value: &str) -> String {
    value.split('#').next().unwrap_or("").trim().to_lowercase()
}

/// code 类节点判定（collect 与 editor 指纹走查共用同一口径，
/// 两处跳过的子树集合必须逐字一致，指纹才与源文本同义）。
/// PERF：ASCII 类型走 eq_ignore_ascii_case 免分配（与
/// to_lowercase 对 ASCII 输入结果 identical），非 ASCII 才
/// 回落 Unicode 小写——每节点一次 String 分配在全库走查里
/// 是实测大头（300 篇 × 每篇数十节点 × 每次渲染）。
pub(crate) fn is_code_node_type(t: &str) -> bool {
    if t.is_ascii() {
        ["code", "codeblock", "fencedcode", "inlinecode"]
            .iter()
            .any(|k| t.eq_ignore_ascii_case(k))
    } else {
        matches!(
            t.to_lowercase().as_str(),
            "code" | "codeblock" | "fencedcode" | "inlinecode"
        )
    }
}

/// 原版 collectWikiSource：递归收集 doc 全部 text 叶；类型为
/// code/codeblock/fencedcode/inlinecode 的节点整棵子树跳过。
/// PERF（调优续推）：直接把叶子以 '\n' 拼进单个 String（与先
/// 收集 Vec<String> 再 join("\n") 逐字等价），省去逐叶克隆与
/// join 的二次拷贝——首渲全库扫描时这是每篇的第一笔分配。
fn collect_wiki_source(node: &Node, out: &mut String, first: &mut bool) {
    if let Some(t) = &node.node_type {
        if is_code_node_type(t) {
            return;
        }
    }
    if let Some(text) = &node.text {
        if !*first {
            out.push('\n');
        }
        *first = false;
        out.push_str(text);
    }
    if let Some(children) = &node.children {
        for c in children {
            collect_wiki_source(c, out, first);
        }
    }
}

/// 剥反引号对包裹的内容（原版 /(`+)([\s\S]*?)\1/g → ''）：
/// 一段反引号 run 与其后同形 run 之间的内容整段删除。
/// PERF（调优续推）：字节级单趟——定界符只有 ASCII '`'，字节
/// 出现位置与 char 出现位置一一对应，str::find（memchr 加速）
/// 替代原先 Vec<char> + 朴素滑窗比对；字面段以 seg 切片整段
/// 拷入，不逐字 push。语义与旧 char 版逐项等价（同 run 无闭
/// 合时逐个吐出反引号、以下一位的较短 run 重试），由
/// wiki_tests 的旧实现对照用例钉住。
fn strip_backtick_spans(s: &str) -> String {
    let bytes = s.as_bytes();
    let n = bytes.len();
    let mut out = String::with_capacity(s.len());
    let mut seg = 0usize;
    let mut i = 0usize;
    while i < n {
        if bytes[i] == b'`' {
            let mut run = 1usize;
            while i + run < n && bytes[i + run] == b'`' {
                run += 1;
            }
            if let Some(rel) = s[i + run..].find(&s[i..i + run]) {
                out.push_str(&s[seg..i]);
                i = i + run + rel + run;
                seg = i;
                continue;
            }
        }
        i += 1;
    }
    out.push_str(&s[seg..]);
    out
}

/// 删转义写法（原版 /\[\[[^\]\r\n]*\]\]/g → ''）：`\[[...]]`
/// 不计为链接。
/// PERF（调优续推）：同 strip_backtick_spans 的字节级单趟化，
/// 定界符（\、[、]、换行）全为 ASCII，语义与旧 char 版等价。
fn remove_escaped_wiki(s: &str) -> String {
    let bytes = s.as_bytes();
    let n = bytes.len();
    let mut out = String::with_capacity(s.len());
    let mut seg = 0usize;
    let mut i = 0usize;
    while i < n {
        if bytes[i] == b'\\' && i + 2 < n && bytes[i + 1] == b'[' && bytes[i + 2] == b'[' {
            let mut j = i + 3;
            let mut ok = true;
            while j < n {
                if bytes[j] == b']' {
                    if j + 1 < n && bytes[j + 1] == b']' {
                        break;
                    }
                    ok = false;
                    break;
                }
                if bytes[j] == b'\n' || bytes[j] == b'\r' {
                    ok = false;
                    break;
                }
                j += 1;
            }
            if ok && j < n {
                out.push_str(&s[seg..i]);
                i = j + 2;
                seg = i;
                continue;
            }
        }
        i += 1;
    }
    out.push_str(&s[seg..]);
    out
}

/// 源文本 → 目标键集合：两趟剥离 + 目标扫描。
/// PERF（调优续推）：① 两趟剥离只在触发字节存在时才跑——无
/// '`' 时反引号趟恒等、无 "\[[" 时转义趟恒等（删除动作以触
/// 发前缀为必要条件），跳过整趟与其输出分配；检查点与管线
/// 顺序一致（转义趟看的是反引号趟的产物）。② 目标扫描字节
/// 级进行，inner 取 &str 切片（定界符全 ASCII、切点必在字符
/// 边界），不再 collect Vec<char>。语义与旧实现逐项等价，
/// 由 wiki_tests 对照用例钉住。
fn wiki_targets_of_source(joined: &str) -> HashSet<String> {
    if joined.contains('`') {
        let no_code = strip_backtick_spans(joined);
        if no_code.contains("\\[[") {
            let clean = remove_escaped_wiki(&no_code);
            return wiki_targets_of_clean(&clean);
        }
        return wiki_targets_of_clean(&no_code);
    }
    if joined.contains("\\[[") {
        let clean = remove_escaped_wiki(joined);
        return wiki_targets_of_clean(&clean);
    }
    wiki_targets_of_clean(joined)
}

/// 在已剥离的文本上扫描 `[[目标]]`（字节级，见上注）。
fn wiki_targets_of_clean(clean: &str) -> HashSet<String> {
    let bytes = clean.as_bytes();
    let n = bytes.len();
    let mut out = HashSet::new();
    let mut i = 0usize;
    while i + 1 < n {
        if bytes[i] == b'[' && bytes[i + 1] == b'[' {
            let mut j = i + 2;
            let mut ok = true;
            while j < n {
                if bytes[j] == b']' {
                    if j + 1 < n && bytes[j + 1] == b']' {
                        break;
                    }
                    ok = false;
                    break;
                }
                if bytes[j] == b'\n' || bytes[j] == b'\r' {
                    ok = false;
                    break;
                }
                j += 1;
            }
            if ok && j < n {
                let inner = &clean[i + 2..j];
                let mut parts = inner.splitn(2, '|');
                let target = parts.next().unwrap_or("");
                let label_ok = match parts.next() {
                    Some(label) => !label.is_empty(),
                    None => true,
                };
                if label_ok && !target.is_empty() {
                    let key = wiki_title_key(target);
                    if !key.is_empty() {
                        out.insert(key);
                    }
                }
                i = j + 2;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// 原版 memoWikiTargets：本篇 doc 里全部 `[[目标]]` 的归一化键
/// 集合。语法 / \[\[([^\]\r\n|]+)(?:\|[^\]\r\n]+)?\]\] /：target
/// 禁 `]`/换行/`|`；带 `|` 时别名段必须非空，否则整体不成立。
pub fn memo_wiki_targets(memo: &Memo) -> HashSet<String> {
    let mut joined = String::new();
    let mut first = true;
    for block in &memo.doc {
        collect_wiki_source(block, &mut joined, &mut first);
    }
    let out = wiki_targets_of_source(&joined);
    // 目标提取留痕（同一备忘同一目标数只记一次，避免渲染反复触发刷屏）
    if !out.is_empty() {
        diag::log_once(
            &format!("wiki-targets:{}:{}", memo.id, out.len()),
            "WIKI",
            &format!("memo {} wiki targets {}", memo.id, out.len()),
        );
    }
    out
}

// 注：原 compute_backlinks（无缓存全量版）已删除——全仓无调用
// 方（编辑器走 editor.rs 的 backlinks_cached 指纹缓存版，语义
// 与 Diag 口径逐字一致），留着只产生 dead_code 警告。

#[cfg(test)]
mod wiki_tests {
    use super::*;

    // ---- 旧实现（Vec<char> 三趟版）原样保留作对照参考 ----
    fn old_find_run(chars: &[char], from: usize, pat: &[char]) -> Option<usize> {
        if pat.is_empty() || chars.len() < pat.len() || from > chars.len() - pat.len() {
            return None;
        }
        (from..=chars.len() - pat.len()).find(|&k| &chars[k..k + pat.len()] == pat)
    }

    fn old_strip_backtick_spans(s: &str) -> String {
        let chars: Vec<char> = s.chars().collect();
        let n = chars.len();
        let mut out = String::with_capacity(s.len());
        let mut i = 0usize;
        while i < n {
            if chars[i] == '`' {
                let mut run = 1usize;
                while i + run < n && chars[i + run] == '`' {
                    run += 1;
                }
                let pat: Vec<char> = chars[i..i + run].to_vec();
                if let Some(close) = old_find_run(&chars, i + run, &pat) {
                    i = close + run;
                    continue;
                }
            }
            out.push(chars[i]);
            i += 1;
        }
        out
    }

    fn old_remove_escaped_wiki(s: &str) -> String {
        let chars: Vec<char> = s.chars().collect();
        let n = chars.len();
        let mut out = String::with_capacity(s.len());
        let mut i = 0usize;
        while i < n {
            if chars[i] == '\\' && i + 2 < n && chars[i + 1] == '[' && chars[i + 2] == '[' {
                let mut j = i + 3;
                let mut ok = true;
                while j < n {
                    if chars[j] == ']' {
                        if j + 1 < n && chars[j + 1] == ']' {
                            break;
                        }
                        ok = false;
                        break;
                    }
                    if chars[j] == '\n' || chars[j] == '\r' {
                        ok = false;
                        break;
                    }
                    j += 1;
                }
                if ok && j < n {
                    i = j + 2;
                    continue;
                }
            }
            out.push(chars[i]);
            i += 1;
        }
        out
    }

    fn old_scan(clean: &str) -> HashSet<String> {
        let chars: Vec<char> = clean.chars().collect();
        let n = chars.len();
        let mut out = HashSet::new();
        let mut i = 0usize;
        while i + 1 < n {
            if chars[i] == '[' && chars[i + 1] == '[' {
                let mut j = i + 2;
                let mut ok = true;
                while j < n {
                    if chars[j] == ']' {
                        if j + 1 < n && chars[j + 1] == ']' {
                            break;
                        }
                        ok = false;
                        break;
                    }
                    if chars[j] == '\n' || chars[j] == '\r' {
                        ok = false;
                        break;
                    }
                    j += 1;
                }
                if ok && j < n {
                    let inner: String = chars[i + 2..j].iter().collect();
                    let mut parts = inner.splitn(2, '|');
                    let target = parts.next().unwrap_or("");
                    let label_ok = match parts.next() {
                        Some(label) => !label.is_empty(),
                        None => true,
                    };
                    if label_ok && !target.is_empty() {
                        let key = wiki_title_key(target);
                        if !key.is_empty() {
                            out.insert(key);
                        }
                    }
                    i = j + 2;
                    continue;
                }
            }
            i += 1;
        }
        out
    }

    fn old_pipeline(text: &str) -> HashSet<String> {
        old_scan(&old_remove_escaped_wiki(&old_strip_backtick_spans(text)))
    }

    const CORPUS: &[&str] = &[
        "",
        "plain text, no links",
        "[[目标]]",
        "前 [[a]] 中 [[b|别名]] 后",
        "[[a|]]",
        "[[|b]]",
        "[[a#锚点]]",
        "[[Ab C]]",
        "`[[x]]`",
        "`code` [[x]]",
        "`unclosed [[x]]",
        "`` `[[x]]` ``",
        "```x``",
        "[`c`[x]]",
        "\\[[x]]",
        "\\[[x]] and [[y]]",
        "\\[[`x`]]",
        "`\\[[x]]`",
        "[[a\nb]]",
        "[[a]b]]",
        "[[abc",
        "[[a]]]]",
        "[[[a]]]",
        "[[目标🎯]]",
        "a `x` b `y` [[t]] `z",
        "``[[x]]``",
        "`a``b` [[x]]",
        "\\[[a]]\\[[b]]",
        "[[a|b|c]]",
        "[[ a ]]",
        "[[#x]]",
        "text [[one]] and `[[two]]` and \\[[three]] and [[four|四]]",
        "[[a]]\n[[b]]",
        "`",
        "``",
        "```",
        "[[a]]`[[b]]`[[c]]",
        "\\[[abc",
        "\\[ [x]]",
        "`a`b`c` [[x]]",
        "第1段 **重点** 这是压测内容 `code0` 公式 $x_0+y^2$ 普通文本继续填充长度 [[链接甲]] 与 \\[[链接乙]]",
    ];

    #[test]
    fn new_pipeline_matches_old_on_corpus() {
        for case in CORPUS {
            assert_eq!(
                old_strip_backtick_spans(case),
                strip_backtick_spans(case),
                "strip differs: {case:?}"
            );
            let stripped = old_strip_backtick_spans(case);
            assert_eq!(
                old_remove_escaped_wiki(&stripped),
                remove_escaped_wiki(&stripped),
                "escape-remove differs: {case:?}"
            );
            assert_eq!(
                old_pipeline(case),
                wiki_targets_of_source(case),
                "targets differ: {case:?}"
            );
        }
    }

    #[test]
    fn memo_targets_skip_code_subtree_and_backtick_spans() {
        // 注：不直调 memo_wiki_targets——它命中目标时经 Diag
        // 落盘，Diag 时钟依赖 js_sys，宿主测试环境不可用；
        // 这里测与其等价的内层组合（collect 拼源 + 管线）。
        let memo: Memo = serde_json::from_str(
            r#"{"id":"t1","title":"T","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z","doc":[
                {"type":"paragraph","id":"b1","children":[{"text":"见 [[目标]] 与 `[[代码内]]`"}]},
                {"type":"code","id":"b2","children":[{"text":"[[代码块]]"}]}
            ]}"#,
        )
        .expect("memo json");
        let mut joined = String::new();
        let mut first = true;
        for block in &memo.doc {
            collect_wiki_source(block, &mut joined, &mut first);
        }
        assert_eq!(joined, "见 [[目标]] 与 `[[代码内]]`");
        let targets = wiki_targets_of_source(&joined);
        assert_eq!(targets, HashSet::from(["目标".to_string()]));
    }

    /// 合成负载计时（只打印不作断言）：300 篇 × 约 2.5K 字、
    /// 每篇带反引号代码段（对齐 big300 压测集形态），对比旧
    /// 三趟与新实现的整库扫描总耗时。
    #[test]
    fn synthetic_scan_timing_print() {
        let mut sources = Vec::new();
        for i in 0..300 {
            let mut s = String::new();
            for p in 0..8 {
                s.push_str(&format!(
                    "第{}段 **重点{}-{}** 这是压测内容 项目 代码 食谱 总结 计划 资料 会议 健身 项目 食谱 笔记 项目 #标签{} [链接](https://example.com/{}) `code{}` 公式 $x_{}+y^2$ 普通文本继续填充长度 ",
                    p, i, p, i, i, i, i
                ));
            }
            if i % 20 == 0 {
                s.push_str("[[某目标]] ");
            }
            sources.push(s);
        }
        let t0 = std::time::Instant::now();
        let mut old_total = 0usize;
        for s in &sources {
            old_total += old_pipeline(s).len();
        }
        let old_ms = t0.elapsed().as_secs_f64() * 1000.0;
        let t1 = std::time::Instant::now();
        let mut new_total = 0usize;
        for s in &sources {
            new_total += wiki_targets_of_source(s).len();
        }
        let new_ms = t1.elapsed().as_secs_f64() * 1000.0;
        assert_eq!(old_total, new_total);
        println!("wiki scan 300 memos: old={old_ms:.1}ms new={new_ms:.1}ms");
    }
}
