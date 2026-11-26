//! 冷开预热（调优续推排队项）：编辑器冷开的残余耗时几乎
//! 全是渲染 / wiki 提取纯路径的首次执行成本（同路径冷实例
//! 与温实例差数倍，量测见调优续推回报）。列表页空闲期以
//! **合成数据**预跑这些纯函数，把首次执行成本前移到空闲
//! 期：不读真实备忘内容、不写任何 signal/store/存储、不
//! 触发桥的真实文档流程；预热对列表无可感知影响（分阶段
//! 在空闲片执行，每阶段一行 PERF 计时入 Diag）。
//!
//! 触发用 requestIdleCallback（{ timeout } 兜底强制触发；
//! 无此 API 的环境退回一次性延时），分三阶段各自等一个
//! 空闲片：① wiki 提取 + 指纹走查 + 双栏分界 ② md 解析
//! ③ 公式渲染。每片先确认仍在列表页（未打开备忘、未进子
//! 页面），否则中止后续阶段——真实打开已自行付过首次成
//! 本，或用户正忙，不抢占。

use dioxus::prelude::*;

use moment_core::model::Memo;

use crate::{blocks, diag, editor, wiki};

/// 合成备忘语料（预热专用，id/标题均为样本字面量）：块形
/// 覆盖标题/待办/代码子树（collect 跳过）/行内标记与链接
/// 节点/wiki 链接与转义/反引号段/md 源段/图片/画廊/音乐
/// 卡，使提取、指纹、估高走的都是真实分支。
fn synthetic_memos() -> Vec<Memo> {
    let mut out = Vec::new();
    for i in 1..=6 {
        let json = format!(
            r#"{{"id":"warmup-{i}","title":"预热样本 {i}","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z","doc":[
                {{"type":"heading","id":"wb1","attrs":{{"level":2}},"children":[{{"text":"预热样本标题 {i}"}}]}},
                {{"type":"paragraph","id":"wb2","children":[
                    {{"text":"正文 [[链接甲]] 与 `[[代码内]]` 及 \\[[转义]] "}},
                    {{"text":"加粗","bold":true}},
                    {{"text":"斜体","italic":true}},
                    {{"type":"link","attrs":{{"href":"https://example.com"}},"children":[{{"text":"外链"}}]}},
                    {{"text":" 公式 $x^2$ 收尾 [[链接乙|别名]] 与 [[链接丙#锚点]]"}}
                ]}},
                {{"type":"todo","id":"wb3","attrs":{{"checked":true}},"children":[{{"text":"待办事项 [[链接甲]]"}}]}},
                {{"type":"codeBlock","id":"wb4","children":[{{"text":"[[代码块内]] 不计入源文本"}}]}},
                {{"type":"paragraph","id":"wb5","children":[{{"text":"| 列一 | 列二 |\n| --- | --- |\n| **苹果** | 香蕉 |\n\n- 第一项\n- 第二项"}}]}},
                {{"type":"image","id":"wb6","attrs":{{"fileId":"warmup-att"}}}},
                {{"type":"gallery","id":"wb7","attrs":{{"items":[{{"fileId":"warmup-a"}},{{"fileId":"warmup-b"}}]}}}},
                {{"type":"musicCard","id":"wb8","url":"https://example.com/song","meta":{{"title":"样本歌曲"}},"status":"ready"}}
            ]}}"#
        );
        if let Ok(memo) = serde_json::from_str::<Memo>(&json) {
            out.push(memo);
        }
    }
    out
}

/// md 预热文本组：复合文档（标题/段落全行内构造/嵌套与
/// 任务列表/表格转义竖线/引用/Callout/围栏/脚注/块公式/
/// 分隔线/Setext）+ 各分类单形 + 无标记纯文本（门控否路）。
const MD_TEXTS: &[&str] = &[
    "# 一级标题\n\n正文 **粗体** *斜体* ***粗斜*** ~~删除~~ `代码段` [链接](https://example.com) <https://example.org> 裸链 https://example.net/x 邮箱 a@b.co [[维基页]] 行内公式 $x_i+y^2$ 与脚注[^1]。\n\n## 二级标题\n\n- 第一项\n- 第二项\n  - 嵌套项\n    - 更深一层\n- [ ] 未完成任务\n- [x] 已完成任务\n\n1. 有序一\n2. 有序二\n\n| 列一 | 列二 |\n| --- | --- |\n| **苹果** | a \\| b |\n| 香蕉 | 橙子 |\n\n> 引用一行\n> 引用二行 **粗**\n\n> [!NOTE] 提示标题\n> Callout 内容一行\n\n```rust\nfn main() { println!(\"hi\"); }\n```\n\n$$\n\\frac{a}{b}+\\sqrt{x}\n$$\n\n---\n\nSetext 标题\n===\n\n[^1]: 脚注内容 一行\n[^2]: 未引用定义\n",
    "- 甲\n- 乙\n",
    "| a | b |\n| - | - |\n| 1 | 2 |\n",
    "> 只有引用",
    "```\ncode\n```",
    "普通一段文字，没有任何标记，继续填充一些长度。",
];

/// 公式预热样本（行内/块式/矩阵/求和）：均为合法 TeX，
/// 只走成功渲染路（失败路带 Diag 留痕，不在预热内触发）。
const TEX_SAMPLES: &[(&str, bool)] = &[
    ("x_i+y^2", false),
    ("\\frac{a}{b}+\\sqrt{x}", false),
    ("\\frac{a}{b}+\\sqrt{x}", true),
    ("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", true),
    ("\\sum_{i=1}^{n} i^2", true),
];

fn run_stage(stage: u32) -> usize {
    match stage {
        0 => {
            let memos = synthetic_memos();
            wiki::warm_extract_paths(&memos) + editor::warm_open_pure_paths(&memos)
        }
        1 => blocks::warm_render_paths(MD_TEXTS, &[]),
        _ => blocks::warm_render_paths(&[], TEX_SAMPLES),
    }
}

#[cfg(test)]
mod warmup_tests {
    use super::*;

    /// 合成语料必须能解析且预热管线真有产出（解析失败会让
    /// stage 0 静默空转——本用例钉住语料形状与模型同步）。
    #[test]
    fn synthetic_corpus_parses_and_warms() {
        let memos = synthetic_memos();
        assert_eq!(memos.len(), 6, "synthetic memos failed to parse");
        assert!(wiki::warm_extract_paths(&memos) > 0);
        assert!(editor::warm_open_pure_paths(&memos) > 0);
        assert!(blocks::warm_render_paths(MD_TEXTS, &[]) > 0);
        assert!(blocks::warm_render_paths(&[], TEX_SAMPLES) > 0);
    }
}

/// 等一个空闲片：requestIdleCallback 优先（timeout 到期
/// 强制触发，避免页面持续繁忙时永不预热）；无此 API 时
/// 退回一次性延时。回送一次 'idle' 即止。
const IDLE_JS: &str = "if (typeof window.requestIdleCallback === 'function') {\
    window.requestIdleCallback(() => dioxus.send('idle'), { timeout: 4000 });\
  } else { setTimeout(() => dioxus.send('idle'), 2500); }";

/// App 挂载时注册一次（use_hook 调用）：逐阶段等空闲片，
/// 每片先确认仍在列表页，否则中止并记一行 PERF。
pub fn spawn_idle_warmup(page: Signal<&'static str>, selected: Signal<Option<String>>) {
    spawn(async move {
        for stage in 0..3u32 {
            let mut eval = document::eval(IDLE_JS);
            if eval.recv::<String>().await.is_err() {
                return;
            }
            if !page.peek().is_empty() || selected.peek().is_some() {
                diag::log(
                    "PERF",
                    &format!("warmup aborted at stage {stage} (left list)"),
                );
                return;
            }
            let t0 = js_sys::Date::now();
            let work = run_stage(stage);
            diag::log(
                "PERF",
                &format!(
                    "warmup stage {stage} in {:.1}ms (work {work})",
                    js_sys::Date::now() - t0
                ),
            );
        }
    });
}
