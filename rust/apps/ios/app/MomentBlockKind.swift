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

// ── 卡片面型派生（补丁债偿还批二 A-2）─────────
// 音乐/链接卡与附件的「当前呈现哪张面」此前在
// 拾起面整链复制一份判别（旧 musicLiftFace /
// attachmentLiftFace 与呈现分支同判据手写同步，
// audit_patch_debt A-2）：呈现一改、拾起框半径
// 即静默漂移（圆角三处漂移有真机前科）。本派
// 生为唯一判别点：呈现分发（BlockRow）、呈现
// 本体（CardBlockView / AttachmentBlockView）
// 与拾起面半径三方共消费同一 CardFace 值，判
// 别序即呈现有效序（行分发先于卡视图本体）：
//   musicCard+input 胶囊（行分发 MusicPillView）
//   → fileId 文件行 → 音乐 loading 骨架 → 音乐
//   error 卡（须有 URL）→ 有标题内容卡 → 链接
//   无标题 err 卡 → 音乐 URL 胶囊 → 音乐空态
//   胶囊；attachment 独立序：单图面（node.image
//   且恰一文件）→ 空态纯文本（零文件）→ 文件行。
// 收口时坐实的两处旧拾起漂移（呈现为真源、拾
// 起向呈现对齐，呈现行为本身不变）：
// · 音乐尾支（无 fileId/标题/URL、status 非
//   input/loading，含 error 而 URL 为空者）呈
//   现为空态胶囊（pill 面），旧拾起派生却返回
//   0（无面）——拾起框与真面不符。
// · 音乐 input 态与 fileId 并存、及 fileId 卡
//   挂 image 旗的拾起旧序（fileId 先行且套用
//   附件单图判）与呈现有效序不符（input 由行
//   分发先行截走、卡 fileId 恒走文件行面）。
// 本派生只对 musicCard / link-card / attachment
// 三型有定义；其余块型的面由类型令牌直给（拾
// 起面 switch 的类型支），不经此派生。

struct CardFaceInput {
    var type: String
    var status: String
    var url: String
    var title: String
    var hasFileId: Bool
    var nodeImage: Bool
    /// 文件数（AttachmentBlockView.files 同口
    /// 径：items 中带 fileId 者计数、无 items
    /// 时 attrs.fileId 兜底一件）。
    var fileCount: Int
}

enum CardFace: Equatable {
    case inputPill
    case fileRow
    case skeleton
    case errorCard
    case readyCard
    case errCard
    case urlPill
    case emptyPill
    case singleImage
    case plainNote

    /// 拾起框面半径令牌（符号量；与 Radius 的
    /// 数值绑定在 MomentApp 侧的 liftRadius 扩
    /// 展单点，本文件不引 UI 量）。
    enum RadiusToken: Equatable {
        case pill
        case cardL
        case attachmentFile
    }

    var radiusToken: RadiusToken {
        switch self {
        case .inputPill, .urlPill, .emptyPill:
            return .pill
        case .skeleton, .errorCard, .readyCard,
             .errCard, .singleImage:
            return .cardL
        case .fileRow, .plainNote:
            return .attachmentFile
        }
    }

    static func derive(_ i: CardFaceInput) -> CardFace {
        if i.type == "attachment" {
            if i.nodeImage && i.fileCount == 1 {
                return .singleImage
            }
            return i.fileCount == 0 ? .plainNote : .fileRow
        }
        let isMusic = i.type == "musicCard"
        if isMusic && i.status == "input" {
            return .inputPill
        }
        if i.hasFileId { return .fileRow }
        if isMusic && i.status == "loading" {
            return .skeleton
        }
        if isMusic && i.status == "error"
            && !i.url.isEmpty {
            return .errorCard
        }
        if !i.title.isEmpty { return .readyCard }
        if !isMusic { return .errCard }
        if !i.url.isEmpty { return .urlPill }
        return .emptyPill
    }
}
