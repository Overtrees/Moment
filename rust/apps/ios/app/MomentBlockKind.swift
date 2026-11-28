import Foundation

// ── 块型分类表单点（补丁债偿还批二 A-3）────────
// 「原子/已知块型」名单此前三处各写一份字面集且
// 成员互不一致（audit_patch_debt A-3）：文末尾随
// 集（旧 EditorModel.isAtomicType）、MD 预览尾随
// 的后继集（旧 materializeMdTrails 内 atomicNext
// 局部表）、打开普查的已知集（旧 init 内 census
// Known 局部表）——新增块型漏改一处即静默分叉、
// 无断言拦截，其中尾随两集直达落盘文档结构。
// 本表收口为唯一登记处：一型一行、分类维作列，
// 三消费方各取派生子集，不再各写字面名单。
//
// 逐维对账结论（2026-11-28 偿还批二，代码实证）：
// · trailAfterNext 与 Web trail_after（rust/apps
//   /web/src/editor/model.rs 的 matches! 名单）
//   逐字同集——系 Web 口径的忠实移植，其与文末
//   集的出入（无 video、有 embedCard）在 Web 侧
//   同样存在、为两语义刻意不同，非漂移。
// · trailEnd 与 Web TRAIL_END_ATOMIC 有三成员
//   出入（+video +divider −todo）：该出入已经
//   audit_markdown_full.md 登记为已知低危差异
//   （原生插入路径 trailingParagraph 覆盖主要
//   场景、落焦热区兜底），本批只收口不改成员——
//   文末集成员直接决定打开时落盘文档结构，改
//   成员须另行立项裁定，不在偿债批内顺手变更。
// · censusKnown 取全宇宙：普查 unknown 过滤先
//   以 isText/isList 短路、后查本集，故文本/列表
//   型在集内与否对计数恒无影响（旧 11 成员表中
//   的 callout 即此理、属惰性成员）；语义由此
//   字面化为「已知 = 在本表内」，未知型（如他
//   端未来新块型）才计 unknown。
// isText/isList 回答「内容可否打字编辑」、isStru
// cturalAtomic 回答「结构可否合并溶解」，均为
// BlockState 上的独立单点（问题不同），不在本
// 表收口范围。

enum BlockKind {
    struct Row {
        let type: String
        /// 文末尾随物化：打开时末块属此集则补一
        /// 真实空段落（会落盘）。
        let trailEnd: Bool
        /// 预览尾随后继：块级预览段之后紧邻此集
        /// （或列表段/另一预览段/文末）时补尾随
        /// 空段（会落盘）。
        let trailAfterNext: Bool
    }

    static let rows: [Row] = [
        Row(type: "paragraph",     trailEnd: false, trailAfterNext: false),
        Row(type: "heading",       trailEnd: false, trailAfterNext: false),
        Row(type: "todo",          trailEnd: false, trailAfterNext: false),
        Row(type: "quote",         trailEnd: false, trailAfterNext: false),
        Row(type: "callout",       trailEnd: false, trailAfterNext: false),
        Row(type: "codeBlock",     trailEnd: false, trailAfterNext: false),
        Row(type: "bulleted-list", trailEnd: false, trailAfterNext: false),
        Row(type: "numbered-list", trailEnd: false, trailAfterNext: false),
        Row(type: "image",         trailEnd: true,  trailAfterNext: true),
        Row(type: "gallery",       trailEnd: true,  trailAfterNext: true),
        Row(type: "video",         trailEnd: true,  trailAfterNext: false),
        Row(type: "musicCard",     trailEnd: true,  trailAfterNext: true),
        Row(type: "link-card",     trailEnd: true,  trailAfterNext: true),
        Row(type: "attachment",    trailEnd: true,  trailAfterNext: true),
        Row(type: "imgTextCard",   trailEnd: true,  trailAfterNext: true),
        Row(type: "imageTextRow",  trailEnd: true,  trailAfterNext: true),
        Row(type: "divider",       trailEnd: true,  trailAfterNext: true),
        Row(type: "embedCard",     trailEnd: false, trailAfterNext: true),
    ]

    /// 块型宇宙（普查已知集与新块型登记面）。
    static let allTypes: Set<String> = Set(rows.map(\.type))
    /// 文末尾随集（派生，勿另写字面）。
    static let trailEndAtomic: Set<String> =
        Set(rows.filter(\.trailEnd).map(\.type))
    /// 预览尾随后继集（派生，勿另写字面）。
    static let trailAfterAtomic: Set<String> =
        Set(rows.filter(\.trailAfterNext).map(\.type))
    /// 普查已知集 = 全宇宙（对账结论见文件头）。
    static let censusKnown: Set<String> = allTypes

    static func isTrailEndAtomic(_ t: String) -> Bool {
        trailEndAtomic.contains(t)
    }
}
